--!strict
-- FriendService: the friend bonus (Config.friends, 2026-11-09). Each Roblox friend in your server adds
-- perFriend to your coins, up to max friends. Friendships are looked up once per pair when a player
-- joins (IsFriendsWith yields, so each check runs on its own thread) and kept until one of them leaves.
-- PenService applies the bonus; both players hear "friendJoined" when a pair is found.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(script.Parent.Remotes)
local DataService = require(script.Parent.DataService)
local PenService = require(script.Parent.PenService)

local F = Config.friends
local FriendService = {}
local friendsOf: { [Player]: { [number]: boolean } } = {}

function FriendService.count(p: Player): number
	local set = friendsOf[p]
	local n = 0
	if set then
		for _, o in Players:GetPlayers() do
			if o ~= p and set[o.UserId] then
				n += 1
			end
		end
	end
	return math.min(n, F.max)
end

local function refresh(p: Player)
	local n = FriendService.count(p)
	p:SetAttribute("Friends", n)
	PenService.setFriends(p, n)
end

local function link(a: Player, b: Player)
	local sa, sb = friendsOf[a], friendsOf[b]
	if not sa or not sb or sa[b.UserId] then
		return
	end
	sa[b.UserId] = true
	sb[a.UserId] = true
	refresh(a)
	refresh(b)
	Remotes.fire(a, "Notify", "friendJoined", { name = b.DisplayName, bonus = FriendService.count(a) * F.perFriend })
	Remotes.fire(b, "Notify", "friendJoined", { name = a.DisplayName, bonus = FriendService.count(b) * F.perFriend })
end

local function joined(p: Player)
	friendsOf[p] = friendsOf[p] or {}
	for _, o in Players:GetPlayers() do
		if o ~= p and o.UserId > 0 and p.UserId > 0 then
			task.spawn(function()
				local ok, yes = pcall(function()
					return p:IsFriendsWith(o.UserId)
				end)
				if ok and yes and p.Parent and o.Parent then
					link(p, o)
				end
			end)
		end
	end
end

-- tester tool: pretend this many friends are here (Studio has no real friends to test with)
function FriendService.setTest(p: Player, n: number)
	local count = math.clamp(n, 0, F.max)
	p:SetAttribute("Friends", count)
	PenService.setFriends(p, count)
	if count > 0 then
		Remotes.fire(p, "Notify", "friendJoined", { name = "Test friend", bonus = count * F.perFriend })
	end
end

function FriendService.Init() end

function FriendService.Start()
	Players.PlayerAdded:Connect(joined)
	for _, p in Players:GetPlayers() do
		joined(p)
	end
	Players.PlayerRemoving:Connect(function(p)
		friendsOf[p] = nil
		for _, o in Players:GetPlayers() do
			if o ~= p and friendsOf[o] and friendsOf[o][p.UserId] then
				friendsOf[o][p.UserId] = nil
				refresh(o)
			end
		end
	end)
	-- a save that loads after the friend was found still gets the bonus
	DataService.Loaded:Connect(function(p: Player)
		refresh(p)
	end)
end

return FriendService
