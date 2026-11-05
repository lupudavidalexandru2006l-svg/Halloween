--!strict
-- RebirthService (Round 4 phase 7): owns rebirths. Bought at the Rebirth Booth (the server's own
-- position) for Config.rebirthCost coins. In one data change, checked again inside it so spam or a
-- second call can't rebirth twice:
--   resets: coins and the pan's Slots upgrade (the best pets stay in the pan, the rest go to Storage)
--   keeps:  pets, the index, guns, opened gates, Cold Level, Look; carried cubes aren't in the save
--           at all, so a rebirth while carrying (or during a show) loses nothing
--   gives:  +50% income and +1 pan slot (PenService reads d.rebirths), and the free rebirth gun when
--           it's the next gun in line (Config.guns.list)
-- Saved at once, so a quick rejoin can't roll it back or apply it twice. The client plays the show.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(script.Parent.Remotes)
local DataService = require(script.Parent.DataService)
local AnalyticsSvc = require(script.Parent.AnalyticsSvc)
local PlayerTracker = require(script.Parent.PlayerTracker)
local PenService = require(script.Parent.PenService)

local RebirthService = {}
local R = Config.rebirth
local lastTry: { [Player]: number } = {}

local function boothPos(): Vector3?
	for _, b in Config.world.booths do
		if b.id == "rebirth" then
			return b.pos
		end
	end
	return nil
end

local function atBooth(player: Player): boolean
	local p, b = PlayerTracker.position(player), boothPos()
	return p ~= nil and b ~= nil and (Vector3.new(p.X, 0, p.Z) - Vector3.new(b.X, 0, b.Z)).Magnitude <= R.boothRange
end

-- the free gun this rebirth hands over (nil = none: not next in line, or a coin gun)
function RebirthService.giftGun(d: any, rebirths: number): number?
	local index = d.guns.best + 1
	local g = Config.guns.list[index]
	if g and g.price == 0 and g.rebirths > 0 and g.rebirths <= rebirths then
		return index
	end
	return nil
end

-- what stops this player rebirthing right now (nil = they can)
function RebirthService.blocker(d: any): string?
	local cost = Config.rebirthCost(d.rebirths + 1)
	if d.coins < cost then
		return `Need {math.ceil(cost - d.coins)} more`
	end
	return nil
end

-- yes = the player said yes on the popup's "Sure?" (without it, it only answers what's missing)
local function rebirth(player: Player, yes: any)
	local d = DataService.get(player)
	if not d or not atBooth(player) then
		return
	end
	local now = os.clock()
	if now - (lastTry[player] or -math.huge) < R.cooldown then
		return -- spam: dropped quietly
	end
	lastTry[player] = now
	local why = RebirthService.blocker(d)
	if why then
		Remotes.notYet(player, why, "rebirth") -- a button press is always answered
		return
	end
	if yes ~= true then
		return
	end
	local old = d.rebirths
	local done, gun = false, nil :: number?
	DataService.mutate(player, function(x)
		-- checked again inside the change itself: nothing runs between this check and the reset
		if x.rebirths ~= old or RebirthService.blocker(x) then
			return
		end
		x.rebirths = old + 1
		x.coins = 0
		x.upgrades.pen = 1
		PenService.fitSlots(x)
		PenService.fillEmptySlots(x) -- the new rebirth slot takes the best pet from Storage
		gun = RebirthService.giftGun(x, x.rebirths)
		if gun then
			x.guns.best = gun
			x.guns.equipped = gun -- straight into your hand, like a bought gun
		end
		done = true
	end)
	if not done then
		return
	end
	if gun then
		player:SetAttribute("GunBest", gun)
	end
	DataService.saveNow(player) -- written at once: a rejoin can't roll it back or give it twice
	AnalyticsSvc.event(player, "rebirth", { rebirths = old + 1 })
	Remotes.fire(player, "Notify", "rebirthed", {
		rebirths = old + 1, mult = Config.rebirthIncome(old + 1), slots = PenService.slots(d), gun = gun,
	})
	DataService.mutate(player, function(x)
		x.seenShows.rebirth = true -- SKIP from the second rebirth on
	end)
end

function RebirthService.Init() end

function RebirthService.Start()
	Remotes.on("Rebirth", rebirth)
	Players.PlayerRemoving:Connect(function(p)
		lastTry[p] = nil
	end)
end

return RebirthService
