--!strict
-- Remotes: the owner of every RemoteEvent (created in Init). Every client call goes through
-- Remotes.on, which rate-limits per player and swallows errors quietly (Code Rules 6).
-- Clients send intent only; outcomes are decided by the services.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)

local Remotes = {}

local NAMES = {
	-- client -> server (intent)
	"BuyUpgrade", "CollectWelcome", "RequestSuperFreeze", "SetMenuOpen", "ShopOpened",
	"EquipPet", "EquipBest", "SetSetting",
	-- server -> client (what happened)
	"Data", "Notify", "BoardRank",
}
local events: { [string]: RemoteEvent } = {}
local calls: { [Player]: { number } } = {}
local notYetAt: { [Player]: { [string]: number } } = {}

function Remotes.Init()
	local folder = Instance.new("Folder")
	folder.Name = "Remotes"
	for _, name in NAMES do
		local e = Instance.new("RemoteEvent")
		e.Name = name
		e.Parent = folder
		events[name] = e
	end
	folder.Parent = ReplicatedStorage
end

function Remotes.Start()
	Players.PlayerRemoving:Connect(function(p)
		calls[p] = nil
		notYetAt[p] = nil
	end)
end

local function allowed(player: Player): boolean
	local now = os.clock()
	local list: { number } = calls[player] or {}
	local kept: { number } = {}
	for _, t in list do
		if now - t < 1 then
			table.insert(kept, t)
		end
	end
	if #kept >= Config.player.rateLimitPerSecond then
		calls[player] = kept
		return false -- dropped quietly
	end
	table.insert(kept, now)
	calls[player] = kept
	return true
end

-- handler gets (player, ...) exactly as sent; it must type-check every argument itself
function Remotes.on(name: string, handler: (Player, ...any) -> ...any)
	local e = events[name]
	assert(e, "unknown remote " .. name)
	e.OnServerEvent:Connect(function(player: Player, ...)
		if not allowed(player) then
			return
		end
		local ok, err = pcall(handler, player, ...)
		if not ok then
			warn(`[Remotes] {name} from {player.UserId}: {err}`)
		end
	end)
end

function Remotes.fire(player: Player, name: string, ...: any)
	events[name]:FireClient(player, ...)
end

function Remotes.fireAll(name: string, ...: any)
	events[name]:FireAllClients(...)
end

-- "not yet" answers ("Need 120 more", "Pen full"): the same message at most once per cooldown,
-- so standing in a full pen or mashing a button never spams (prototype QA)
function Remotes.notYet(player: Player, reason: string, at: string?)
	local list = notYetAt[player] or {}
	notYetAt[player] = list
	local now = os.clock()
	if now - (list[reason] or -math.huge) < Config.notYetCooldown then
		return
	end
	list[reason] = now
	events.Notify:FireClient(player, "notYet", { reason = reason, at = at })
end

-- small shared validators
function Remotes.isId(v: any, maxLen: number?): boolean
	return typeof(v) == "string" and #v > 0 and #v <= (maxLen or 32)
end

return Remotes
