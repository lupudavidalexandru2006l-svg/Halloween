--!strict
-- WildPetSpawner: spawn rolls (server only, with soft pity), the action loop that decides poses,
-- wandering, dazed pets after a melt, and each player's own odds for the zone signs.
-- Personal rares (owner 2026-10-30): every player has their own roll stream and pity. A roll that lands
-- Common or Uncommon goes into the shared zone pool; Rare and up spawns a pet only that player sees and
-- can freeze (OwnerUserId on the root). A player's rolls run while the zone they'd see (shared pets plus
-- their own) has room, so one player's odds and pace are the same as playing solo.
-- Each wild pet is an invisible anchored "PetRoot" part with attributes and an Attachment the ray's
-- beam lands on; clients draw the pet model on it (PetVisuals) and play the action as an animation.
-- Round 5: pets are shot, not prompted. FreezeService moves each pet's freeze meter (setMeter); here a
-- pet with some ice on it is scared and runs away from the shooter (Config.aim.fleeSpeed), and once
-- it's stuck (Config.aim.stuckAt) it can't move and its pose is locked in. Slow Gel slows all of it.
-- Mutations (Golden, Starry at night) are rolled here when a pet spawns, so you can see them before you
-- freeze. At night every wild pet sleeps: it stops wandering and freezes in half the hold (Config.night).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local PetDefs = require(ReplicatedStorage.Shared.PetDefs)
local WorldRules = require(ReplicatedStorage.Shared.WorldRules)
local Remotes = require(script.Parent.Remotes)
local DataService = require(script.Parent.DataService)
local WorldService = require(script.Parent.WorldService)
local EventService = require(script.Parent.EventService)
local GearService = require(script.Parent.GearService)

export type WildPet = {
	id: string,
	def: PetDefs.PetDef,
	zone: number,
	root: Part,
	state: "wild" | "dazed",
	loopIdx: number,
	action: string,
	actionEnd: number,
	wanderTo: Vector3?,
	dazedUntil: number,
	pose: string?,
	mut: string?,
	offerFor: Player?,
	dazedOwner: Player?,
	superUsed: boolean,
	offered: boolean, -- the Super Freeze offer was shown on this run already (at most once per run)
	meter: number, -- how frozen it is (0-1), moved by FreezeService
	fleeFrom: Vector3?, -- where the last shot came from (it runs the other way while scared)
	shownMeter: number, -- the meter as last published (in Config.aim.step steps)
	owner: Player?, -- a personal rare: only this player sees it and can freeze it
}

local WildPetSpawner = {}
local pets: { [string]: WildPet } = {}
local pity: { [Player]: { [number]: { [string]: number } } } = {}
local respawnAt: { [Player]: { [number]: number } } = {}
local nextId = 1
local rng = Random.new()
local folder: Folder

local TIER_NAMES = {}
for _, t in Config.tiers do
	table.insert(TIER_NAMES, t.name)
end

local function pityFor(player: Player, zone: number): { [string]: number }
	local byZone = pity[player] or {}
	pity[player] = byZone
	local p = byZone[zone] or {}
	byZone[zone] = p
	return p
end

-- the true odds for this player in this zone, their own pity included (the zone signs that showed
-- them were removed, owner 2026-11-03)
function WildPetSpawner.shownOdds(player: Player, zone: number): { [string]: number }
	local p = pityFor(player, zone)
	local pc = Config.spawner.pity
	local weights: { [string]: number } = {}
	local total = 0
	for _, t in Config.tiers do
		local boost = 1
		if t.rank >= 3 then
			local grace = (100 / t.odds) * pc.graceFactor
			boost = math.min(pc.maxBoost, 1 + math.max(0, (p[t.name] or 0) - grace) * pc.perMiss * (100 / t.odds) / 100)
		end
		weights[t.name] = t.odds * boost
		total += weights[t.name]
	end
	for k, v in weights do
		weights[k] = v / total * 100
	end
	return weights
end

local function pickTier(player: Player, zone: number): string
	local odds = WildPetSpawner.shownOdds(player, zone)
	local r = rng:NextNumber() * 100
	local tier = "Common"
	for _, name in TIER_NAMES do
		if r < odds[name] then
			tier = name
			break
		end
		r -= odds[name]
	end
	return tier
end

-- only a roll that really spawned a pet moves pity
local function commitPity(player: Player, zone: number, tier: string)
	local p = pityFor(player, zone)
	local rolledRank = Config.tier(tier).rank
	for _, t in Config.tiers do
		if t.rank >= 3 then
			p[t.name] = if rolledRank >= t.rank then 0 else (p[t.name] or 0) + 1
		end
	end
end

local function randomSpot(zone: number, near: boolean, rare: boolean): Vector3?
	local z = Config.zone(zone)
	if not z then
		return nil
	end
	local sp = Config.spawner
	local half = Config.world.tunnel.width / 2 - sp.wallMargin
	for _ = 1, 30 do
		local x, zz
		if near then
			local band = sp.near[zone]
			x = -15 + rng:NextNumber() * 30
			zz = band[1] + rng:NextNumber() * (band[2] - band[1])
		else
			-- Rare and up only in the far half, so the pets worth most have the longest run home
			local zMin = if rare then math.max(sp.farZMin[zone], (z.zMin + z.zMax) / 2) else sp.farZMin[zone]
			x = -half + rng:NextNumber() * half * 2
			zz = zMin + rng:NextNumber() * (z.zMax - 10 - zMin)
		end
		local at = Vector3.new(x, 0, zz)
		if WorldRules.zoneAt(at) == zone and WorldRules.inTunnel(at, sp.wallMargin) then
			return at
		end
	end
	return nil
end

local function makeRoot(def: PetDefs.PetDef, pos: Vector3): Part
	local h = PetDefs.sizeHeight[def.size]
	local root = Instance.new("Part")
	root.Name = "PetRoot"
	root.Size = Vector3.new(h, h, h)
	root.CFrame = CFrame.new(pos + Vector3.new(0, h / 2, 0))
	root.Anchored = true
	root.CanCollide = false
	root.CanTouch = false
	root.Transparency = 1
	local a = Instance.new("Attachment") -- the beam lands here, on the pet's middle
	a.Name = "Aim"
	a.Parent = root
	return root
end

-- the server's roll for a new wild pet: rarest first, night-only ones only at night
local function rollMutation(): string?
	local night = EventService.isNight()
	for _, name in Config.mutationRollOrder do
		local m = Config.mutations[name]
		if (night or not m.nightOnly) and rng:NextNumber() < m.chance then
			return name
		end
	end
	return nil
end

local function setAction(pet: WildPet, action: string)
	pet.action = action
	pet.actionEnd = os.clock() + Config.poses[action].seconds
	pet.root:SetAttribute("Action", action)
	pet.root:SetAttribute("ActionStart", workspace:GetServerTimeNow())
end

-- forcedKey: that pet; otherwise a shared Common or Uncommon (60:25, no pity), e.g. the near-band
-- keepers and the pets already there when the server starts. Player rolls call it with a forcedKey.
function WildPetSpawner.spawn(zone: number, at: Vector3?, forcedKey: string?, near: boolean?, owner: Player?): WildPet?
	local def: PetDefs.PetDef?
	if forcedKey then
		def = PetDefs.get(forcedKey)
	else
		local c, u = Config.tier("Common").odds, Config.tier("Uncommon").odds
		local pool = PetDefs.inZone(zone, if rng:NextNumber() < c / (c + u) then "Common" else "Uncommon")
		def = if #pool > 0 then pool[rng:NextInteger(1, #pool)] else nil -- an island that isn't ready has no pets
	end
	if not def then
		return nil
	end
	local pos = at or randomSpot(zone, near == true, Config.tier(def.tier).rank >= 3)
	if not pos then
		return nil
	end
	local id = "p" .. nextId
	nextId += 1
	local root = makeRoot(def, pos)
	root:SetAttribute("PetId", id)
	root:SetAttribute("PetKey", def.key)
	root:SetAttribute("Tier", def.tier)
	root:SetAttribute("Zone", zone)
	root:SetAttribute("State", "wild")
	root:SetAttribute("OwnerUserId", if owner then owner.UserId else 0) -- clients hide others' personal rares
	local mut = rollMutation()
	root:SetAttribute("Mut", mut)
	local pet: WildPet = {
		id = id, def = def, zone = zone, root = root, state = "wild",
		loopIdx = rng:NextInteger(1, #Config.poseLoop), action = "idle", actionEnd = 0,
		wanderTo = nil, dazedUntil = 0, pose = nil, mut = mut, offerFor = nil, dazedOwner = nil, superUsed = false,
		offered = false, meter = 0, fleeFrom = nil, shownMeter = 0, owner = owner,
	}
	setAction(pet, Config.poseLoop[pet.loopIdx])
	pet.actionEnd = os.clock() + rng:NextNumber() * Config.poses[pet.action].seconds
	pets[id] = pet
	root.Parent = folder
	return pet
end

-- a melted cube's pet: dazed for a while, only its carrier can refreeze it, then it's wild again.
-- open (Round 5 ray-tag): a cube knocked out of someone's hands is anyone's to zap, so it isn't personal
function WildPetSpawner.spawnDazed(info: { key: string, zone: number, pose: string, mut: string?, superUsed: boolean, offered: boolean }, pos: Vector3, owner: Player, offer: boolean, open: boolean?): WildPet?
	local def = PetDefs.get(info.key)
	local personal = def ~= nil and Config.tier(def.tier).rank >= 3 and Config.spawner.personalRares and not open
	local pet = WildPetSpawner.spawn(info.zone, pos, info.key, false, if personal then owner else nil)
	if not pet then
		return nil
	end
	pet.state = "dazed"
	pet.dazedUntil = os.clock() + Config.dazedSeconds
	pet.pose = info.pose
	pet.mut = info.mut
	pet.superUsed = info.superUsed
	pet.offered = info.offered or offer
	pet.dazedOwner = if open then nil else owner
	pet.offerFor = if offer then owner else nil
	pet.root:SetAttribute("State", "dazed")
	pet.root:SetAttribute("Pose", info.pose)
	pet.root:SetAttribute("Mut", info.mut)
	pet.root:SetAttribute("OfferUserId", if offer then owner.UserId else 0)
	return pet
end

function WildPetSpawner.get(id: string): WildPet?
	return pets[id]
end

-- every wild pet (FreezeService picks the extra pets a many-beam gun freezes at once)
function WildPetSpawner.all(): { [string]: WildPet }
	return pets
end

function WildPetSpawner.remove(id: string)
	local p = pets[id]
	if p then
		pets[id] = nil
		p.root:Destroy()
	end
end

-- FreezeService moves a pet's freeze meter: published in steps ("Meter"), with the look of the freeze
-- ("FreezeStyle") and who shoots it ("AimedBy", so every client draws that player's beam to it)
function WildPetSpawner.setMeter(pet: WildPet, meter: number, style: string?, from: Vector3?, by: Player?)
	pet.meter = meter
	if from then
		pet.fleeFrom = from
	end
	local step = Config.aim.step
	local shown = if meter <= 0 then 0 else math.max(step, math.floor(meter / step) * step)
	if shown ~= pet.shownMeter then
		pet.shownMeter = shown
		pet.root:SetAttribute("Meter", shown)
	end
	if style and pet.root:GetAttribute("FreezeStyle") ~= style then
		pet.root:SetAttribute("FreezeStyle", style)
	end
	local byId = if by then by.UserId else 0
	if pet.root:GetAttribute("AimedBy") ~= byId then
		pet.root:SetAttribute("AimedBy", byId)
	end
	if meter <= 0 then
		pet.fleeFrom = nil
	end
end

-- one step away from the shooter, turning along the walls when the straight way out is blocked
local function flee(pet: WildPet, dt: number, speed: number)
	local from = pet.root.Position
	local away = Vector3.new(from.X - (pet.fleeFrom :: Vector3).X, 0, from.Z - (pet.fleeFrom :: Vector3).Z)
	if away.Magnitude < 0.01 then
		away = pet.root.CFrame.LookVector * Vector3.new(1, 0, 1)
	end
	away = away.Unit
	local step = speed * dt
	for _, turn in { 0, 0.7, -0.7, 1.4, -1.4, 2.1, -2.1 } do
		local dir = (CFrame.Angles(0, turn, 0) * CFrame.new(away)).Position
		local to = from + dir * step
		if WorldRules.zoneAt(to) == pet.zone and WorldRules.inTunnel(to, Config.spawner.wallMargin) then
			pet.root.CFrame = CFrame.lookAt(to, to + dir)
			return
		end
	end
end

function WildPetSpawner.clearOffer(pet: WildPet)
	pet.offerFor = nil
	pet.root:SetAttribute("OfferUserId", 0)
end

-- "always one within about 3 seconds of walking": wild pets in a zone's near band
local function nearCount(zone: number): number
	local band = Config.spawner.near[zone]
	local n = 0
	for _, p in pets do
		local z = p.root.Position.Z
		if p.zone == zone and p.state == "wild" and z >= band[1] and z <= band[2] then
			n += 1
		end
	end
	return n
end

local function tick(dt: number)
	local now = os.clock()
	local night = EventService.isNight()
	for _, pet in pets do
		-- night: wild pets curl up and sleep (easy to freeze); morning: back to their pose loop
		if pet.state == "wild" and night ~= (pet.action == "sleep") and pet.meter < Config.aim.stuckAt then
			setAction(pet, if night then "sleep" else Config.poseLoop[pet.loopIdx])
			pet.wanderTo = nil
		end
		if pet.state == "wild" and pet.action == "sleep" then
			continue -- asleep: it doesn't run (FreezeService freezes it faster)
		end
		local slow = GearService.slowAt(pet.root.Position)
		-- stuck in the ice: it can't move and its pose is locked in (catch the dance!)
		if pet.meter >= Config.aim.stuckAt then
			pet.actionEnd += dt
			continue
		end
		-- scared: it runs away from the ray, fast, its pose keeps going
		if pet.meter > 0 and pet.fleeFrom and pet.state == "wild" then
			flee(pet, dt, Config.aim.fleeSpeed * slow)
			pet.wanderTo = nil
			continue
		end
		if pet.state == "dazed" then
			if pet.offerFor then
				local hrp = pet.offerFor.Character and pet.offerFor.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
				if not hrp or (hrp.Position - pet.root.Position).Magnitude > Config.monetization.superFreeze.walkAwayStuds then
					WildPetSpawner.clearOffer(pet) -- the button goes away when you walk off
					pet.dazedUntil = math.max(pet.dazedUntil, now)
				end
			end
			-- no hidden timer on a paid offer (Game Plan 15): while it's up, the pet stays dazed
			if not pet.offerFor and now >= pet.dazedUntil then
				pet.state = "wild"
				pet.dazedOwner = nil
				WildPetSpawner.clearOffer(pet)
				pet.root:SetAttribute("State", "wild")
			end
			continue
		end
		if slow < 1 then
			pet.actionEnd += dt * (1 - slow) -- in Slow Gel everything it does is slower
		end
		if now >= pet.actionEnd then
			local nextAction
			if rng:NextNumber() < Config.sneezeChance then
				nextAction = "sneeze"
			else
				pet.loopIdx = pet.loopIdx % #Config.poseLoop + 1
				nextAction = Config.poseLoop[pet.loopIdx]
			end
			setAction(pet, nextAction)
			if nextAction == "idle" and rng:NextNumber() < 0.5 then
				local t = pet.root.Position + Vector3.new((rng:NextNumber() - 0.5) * 10, 0, (rng:NextNumber() - 0.5) * 10)
				if WorldRules.zoneAt(t) == pet.zone and WorldRules.inTunnel(t, Config.spawner.wallMargin) then
					pet.wanderTo = t
				end
			end
		end
		if pet.wanderTo and pet.action == "idle" then
			local from = pet.root.Position
			local to = Vector3.new(pet.wanderTo.X, from.Y, pet.wanderTo.Z)
			local d = (to - from).Magnitude
			local step = Config.spawner.wanderSpeed * dt * slow
			if d < step then
				pet.wanderTo = nil
			else
				pet.root.CFrame = CFrame.lookAt(from + (to - from).Unit * step, to)
			end
		end
	end
	local sp = Config.spawner
	for _, z in Config.world.zones do
		if not z.ready then
			continue -- "Coming soon": no pets until the island's pets are approved (Round 4 phase 6)
		end
		local shared = 0
		local personal: { [Player]: number } = {}
		for _, p in pets do
			if p.zone == z.id then
				if p.owner then
					personal[p.owner] = (personal[p.owner] or 0) + 1
				else
					shared += 1
				end
			end
		end
		-- "always one within about 3 seconds of walking"
		if shared < sp.maxPerZone and nearCount(z.id) < sp.nearCount then
			if WildPetSpawner.spawn(z.id, nil, nil, true) then
				shared += 1
			end
		end
		for _, player in Players:GetPlayers() do
			local data = DataService.get(player)
			if not data or z.id > data.reach then
				continue -- no rolls for a zone you can't reach yet
			end
			local timers = respawnAt[player] or {}
			respawnAt[player] = timers
			local mine = personal[player] or 0
			if now < (timers[z.id] or 0) or shared + mine >= sp.maxPerZone then
				continue
			end
			timers[z.id] = now + sp.respawnSeconds
			local tier = pickTier(player, z.id)
			local rare = Config.tier(tier).rank >= 3
			if rare and sp.personalRares and mine >= sp.personalMaxPerZone then
				continue -- full of your own rares: nothing spawns and pity doesn't move
			end
			local pool = PetDefs.inZone(z.id, tier)
			local def = if #pool > 0 then pool[rng:NextInteger(1, #pool)] else nil
			if def and WildPetSpawner.spawn(z.id, nil, def.key, false, if rare and sp.personalRares then player else nil) then
				commitPity(player, z.id, tier)
				if rare and sp.personalRares then
					personal[player] = mine + 1
				else
					shared += 1
				end
			end
		end
	end
end

-- dev command (Studio only): a personal pet of this tier right next to the player
function WildPetSpawner.devSpawn(player: Player, tier: string): WildPet?
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return nil
	end
	local zone = math.max(1, WorldRules.zoneAt(root.Position))
	local pool = PetDefs.inZone(zone, tier)
	if #pool == 0 then
		return nil
	end
	local at = Vector3.new(root.Position.X + 5, 0, root.Position.Z + 5)
	return WildPetSpawner.spawn(zone, at, pool[rng:NextInteger(1, #pool)].key, false, if Config.tier(tier).rank >= 3 then player else nil)
end

-- Tester: this exact pet, wild, in this zone (any pet in any zone; owner 2026-11-05). zone 0 = right
-- next to you, on the island you stand on. Rare and up is personal, like devSpawn.
function WildPetSpawner.devSpawnPet(player: Player, key: string, zone: number): WildPet?
	local def = PetDefs.get(key)
	if not def then
		return nil
	end
	local owner = if Config.tier(def.tier).rank >= 3 then player else nil
	if zone == 0 then
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root then
			return nil
		end
		local at = Vector3.new(root.Position.X + 5, 0, root.Position.Z + 5)
		return WildPetSpawner.spawn(math.max(1, WorldRules.zoneAt(root.Position)), at, key, false, owner)
	end
	return WildPetSpawner.spawn(zone, nil, key, false, owner)
end

function WildPetSpawner.Init()
	folder = WorldService.petsFolder("WildPets")
end

function WildPetSpawner.Start()
	for _, z in Config.world.zones do
		if not z.ready then
			continue
		end
		for _ = 1, Config.spawner.nearCount do
			WildPetSpawner.spawn(z.id, nil, nil, true)
		end
		for _ = 1, Config.spawner.maxPerZone - 2 - Config.spawner.nearCount do
			WildPetSpawner.spawn(z.id) -- shared Commons and Uncommons; rares come from the players' own rolls
		end
	end
	-- first minute: a fluffy bunny next to the spawn, and a second and third pet right there
	DataService.Loaded:Connect(function(player: Player, data: any)
		if data.stats.frozen == 0 then
			-- the hub is safe (no wild pets), so it waits just inside the tunnel mouth, straight ahead
			local s = Config.world.spawn
			WildPetSpawner.spawn(1, Vector3.new(s.X + 4, 0, Config.world.hubZMax + Config.spawner.firstPetDistance), "snowbun")
		end
		-- the near band is kept topped up for everyone (see nearCount), so nothing more is needed here
	end)
	Players.PlayerRemoving:Connect(function(player)
		pity[player] = nil
		respawnAt[player] = nil
		for id, p in pets do
			if p.owner == player then
				WildPetSpawner.remove(id) -- a personal rare leaves with its player
				continue
			end
			if p.offerFor == player then
				WildPetSpawner.clearOffer(p)
			end
			if p.dazedOwner == player then
				p.dazedOwner = nil
			end
		end
	end)
	task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(0.1)
			local now = os.clock()
			local ok, err = pcall(tick, now - last) -- one bad tick never stops the pets for good
			if not ok then
				warn("[WildPetSpawner] tick:", err)
			end
			last = now
		end
	end)
end

return WildPetSpawner
