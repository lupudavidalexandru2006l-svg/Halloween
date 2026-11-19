--!strict
-- BoostService (owner 2026-11-18: "the monetizations are good, you can add them"; vault Games/Ice Ray for Pets/
-- Monetization Plan 2026-11-18): runs the boosts players buy (MonetizationService grants them into d.boosts):
--  - Speed Potion: PlayerTracker.updateSpeed multiplies walk speed while it lasts; this re-runs it when one starts
--    or ends.
--  - Lucky Ray: while it lasts, a bonus Rare-or-better pet of your own (only you see it) appears near you every
--    Config.monetization.luckEvery seconds, on an island whose pets you can freeze, while your hands are free.
--  - Server Luck: workspace "BoughtLuckUntil" (server time); EventService.mult("luck") reads it.
--  - Critter Shield: CritterService asks BoostService.useShield when a critter reaches you.
-- Every player gets attributes for the HUD's boost timers: BoostSpeedUntil / BoostLuckUntil (server clock), and
-- BoostShields. Times are saved as os.time() ends, so a rejoin keeps what's left.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local PetDefs = require(ReplicatedStorage.Shared.PetDefs)
local WorldRules = require(ReplicatedStorage.Shared.WorldRules)
local Remotes = require(script.Parent.Remotes)
local DataService = require(script.Parent.DataService)
local PlayerTracker = require(script.Parent.PlayerTracker)

local BoostService = {}
local M = Config.monetization
local rng = Random.new()
local speedOn: { [Player]: boolean } = {}
local nextLucky: { [Player]: number } = {}
local lucky: { [Player]: { string } } = {} -- the bonus pets still out (at most 3)

local function serverTime(untilOs: number): number
	return workspace:GetServerTimeNow() + (untilOs - os.time())
end

local function setAttr(p: Player, name: string, v: any)
	if p:GetAttribute(name) ~= v then
		p:SetAttribute(name, v)
	end
end

-- a Rare-or-better rarity, by the normal odds among those tiers
local function rollRare(): string
	local total = 0
	for _, t in Config.tiers do
		if t.rank >= 3 then
			total += t.odds
		end
	end
	local r = rng:NextNumber() * total
	for _, t in Config.tiers do
		if t.rank >= 3 then
			r -= t.odds
			if r < 0 then
				return t.name
			end
		end
	end
	return "Rare"
end

local function luckyPet(player: Player, d: any)
	local pos = PlayerTracker.position(player)
	if not pos then
		return
	end
	local zone = WorldRules.zoneAt(pos)
	if zone < 1 or zone > d.reach or d.coldPower < Config.need(zone) or WorldRules.inHub(pos) then
		return -- only where you can freeze what appears
	end
	-- and only where your gun works: one island past its Heat it overheats, two past it fizzles (FreezeService)
	local GunService = require(script.Parent.GunService) :: any
	if zone > Config.gun(GunService.equipped(player)).heat then
		return
	end
	local CarryService = require(script.Parent.CarryService) :: any
	if CarryService.count(player) > 0 or CarryService.groundCount(player) > 0 then
		return
	end
	local WildPetSpawner = require(script.Parent.WildPetSpawner) :: any
	local alive: { string } = {}
	for _, id in lucky[player] or {} do
		if WildPetSpawner.get(id) then
			table.insert(alive, id)
		end
	end
	lucky[player] = alive
	if #alive >= 3 then
		return
	end
	local tier = rollRare()
	local pool = PetDefs.inZone(zone, tier)
	if #pool == 0 then
		pool = PetDefs.inZone(zone, "Rare")
	end
	if #pool == 0 then
		return
	end
	-- 14-24 studs from you, inside the island's walls
	local at: Vector3? = nil
	for _ = 1, 12 do
		local a = rng:NextNumber() * math.pi * 2
		local r = 14 + rng:NextNumber() * 10
		local p = Vector3.new(pos.X + math.cos(a) * r, 0, pos.Z + math.sin(a) * r)
		if WorldRules.zoneAt(p) == zone and WorldRules.inTunnel(p, Config.spawner.wallMargin) then
			at = p
			break
		end
	end
	if not at then
		return
	end
	local def = pool[rng:NextInteger(1, #pool)]
	local pet = WildPetSpawner.spawn(zone, at, def.key, false, player)
	if pet then
		table.insert(alive, pet.id)
		Remotes.fire(player, "Notify", "adminAbuse", { text = `Lucky Ray! A {string.upper(def.tier)} {def.name} appeared near you!`, color = "luck", seconds = 4 })
	end
end

local function tickPlayer(player: Player, now: number)
	local d = DataService.get(player)
	if not d then
		return
	end
	local b = d.boosts
	local t = os.time()
	local speed = t < b.speedUntil
	setAttr(player, "BoostSpeedUntil", if speed then serverTime(b.speedUntil) else nil)
	setAttr(player, "BoostSpeedMult", if speed then b.speedMult else nil)
	if speed ~= (speedOn[player] == true) then
		speedOn[player] = speed
		PlayerTracker.updateSpeed(player)
		if not speed then
			Remotes.fire(player, "Notify", "adminAbuse", { text = "Your Speed Potion wore off", color = "night", seconds = 3 })
		end
	end
	local luck = t < b.luckUntil
	setAttr(player, "BoostLuckUntil", if luck then serverTime(b.luckUntil) else nil)
	setAttr(player, "BoostShields", if b.shields > 0 then b.shields else nil)
	if luck and now >= (nextLucky[player] or 0) then
		nextLucky[player] = now + M.luckEvery
		luckyPet(player, d)
	elseif not luck then
		nextLucky[player] = now + 5 -- the first bonus pet comes soon after you buy
	end
end

-- right after a grant: the speed and the timers change now, not on the next tick
function BoostService.refresh(player: Player)
	pcall(tickPlayer, player, os.clock())
end

-- a Critter caught you: a Critter Shield takes it (true = blocked)
function BoostService.useShield(player: Player): boolean
	local d = DataService.get(player)
	if not d or d.boosts.shields <= 0 then
		return false
	end
	local left = 0
	DataService.mutate(player, function(x)
		x.boosts.shields = math.max(0, x.boosts.shields - 1)
		left = x.boosts.shields
	end)
	setAttr(player, "BoostShields", if left > 0 then left else nil)
	Remotes.fire(player, "Notify", "adminAbuse", { text = `Critter Shield! Your pet is safe ({left} left)`, color = "chill", seconds = 3 })
	return true
end

function BoostService.Init() end

function BoostService.Start()
	Players.PlayerRemoving:Connect(function(p)
		speedOn[p] = nil
		nextLucky[p] = nil
		lucky[p] = nil
	end)
	while true do
		task.wait(1)
		local now = os.clock()
		for _, p in Players:GetPlayers() do
			if DataService.isLoaded(p) then
				local ok, err = pcall(tickPlayer, p, now)
				if not ok then
					warn("[BoostService]", err)
				end
			end
		end
	end
end

return BoostService
