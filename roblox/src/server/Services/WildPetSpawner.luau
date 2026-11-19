--!strict
-- WildPetSpawner: the wild pets (server only): the nightly wave, the action loop that decides poses,
-- wandering, and dazed pets after a melt.
-- Each wild pet is an invisible anchored "PetRoot" part with attributes and an Attachment the ray's
-- beam lands on; clients draw the pet model on it (PetVisuals) and play the action as an animation.
-- Round 5: pets are shot, not prompted. FreezeService moves each pet's freeze meter (setMeter); here a
-- pet with some ice on it is scared and runs away from the shooter (Config.aim.fleeSpeed), and once
-- it's stuck (Config.aim.stuckAt) it can't move and its pose is locked in. Slow Gel slows all of it.
-- Mutations (Golden, Starry at night) are rolled here when a pet spawns, so you can see them before you
-- freeze. At night every wild pet sleeps: it stops wandering and freezes in half the hold (Config.night).
-- One wave a day, pure luck (owner 2026-11-17: "after freezing something another animal shouldn't spawn,
-- that's why we have the night"; "every night resets every island and every player sees the same animals.
-- They do not decide what spawns, it's just luck"). Nothing spawns during the day, so a frozen pet leaves a
-- gap. The Night Reset clears every island, and sunrise rolls each island's new pets from that island's
-- rarity odds, each with its own size and mutation. Every player sees the same pets: no player rolls, no
-- pity, no personal pets in the wave. Config.night.wave holds the numbers.

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
	sz: string?, -- Big ... Cosmic (Config.sizes), nil = normal
	offerFor: Player?,
	dazedOwner: Player?,
	superUsed: boolean,
	offered: boolean, -- the Super Freeze offer was shown on this run already (at most once per run)
	meter: number, -- how frozen it is (0-1), moved by FreezeService
	fleeFrom: Vector3?, -- where the last shot came from (it runs the other way while scared)
	shownMeter: number, -- the meter as last published (in Config.aim.step steps)
	owner: Player?, -- only this player sees it and can freeze it (the tutorial pet, a melted cube's Rare)
	-- restless tiers (Config.spawner.motion): when it next darts somewhere new, and its swerve while fleeing
	dartAt: number,
	swerve: number,
	swerveAt: number,
	bornAt: number, -- os.clock() at spawn
	knocked: boolean?, -- knocked out of its carrier's hands: theirs (any tier)
	tutorial: boolean?, -- a new player's first pet: the Night Reset leaves it alone
}

local WildPetSpawner = {}
local pets: { [string]: WildPet } = {}
local nextId = 1
local rng = Random.new()
local folder: Folder
local dawnWave = false -- the sunrise wave after a Night Reset: it may roll night-only mutations (Starry)

-- a wave pet's rarity: the rarities as they are (Config.tiers odds), the same for every island and player.
-- Only Lucky Rush (Config.events) tips it while it runs: Rare and up x its luck.
local function pickTier(): string
	local total = 0
	for _, t in Config.tiers do
		total += t.odds * (if t.rank >= 3 then EventService.mult("luck") else 1)
	end
	local r = rng:NextNumber() * total
	for _, t in Config.tiers do
		r -= t.odds * (if t.rank >= 3 then EventService.mult("luck") else 1)
		if r < 0 then
			return t.name
		end
	end
	return "Common"
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

local function makeRoot(def: PetDefs.PetDef, pos: Vector3, sz: string?): Part
	local h = PetDefs.height(def, sz)
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
	local night = EventService.isNight() or dawnWave
	for _, name in Config.mutationRollOrder do
		local m = Config.mutations[name]
		local chance = m.chance * (if name == "Golden" then EventService.mult("golden") else 1) -- Golden Rush
		if (night or not m.nightOnly) and rng:NextNumber() < chance then
			return name
		end
	end
	return nil
end

-- the server's size roll for a new wild pet (Config.sizes): rarest first, nil = a normal pet
local function rollSize(): string?
	local boost = EventService.mult("size") -- an admin size boost (AdminService); 1 normally
	for _, name in Config.sizeRollOrder do
		if rng:NextNumber() < Config.sizes[name].chance * boost then
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

-- one wild pet of this kind (its size and mutation are rolled here); owner = only that player sees it.
-- forced (Tester / admin, 2026-11-18): this size and mutation instead of the rolls ("" or nil in it = normal)
export type Forced = { mut: string?, sz: string? }
function WildPetSpawner.spawn(zone: number, at: Vector3?, key: string, near: boolean?, owner: Player?, forced: Forced?): WildPet?
	local def = PetDefs.get(key)
	if not def then
		return nil
	end
	local pos = at or randomSpot(zone, near == true, Config.tier(def.tier).rank >= 3)
	if not pos then
		return nil
	end
	local id = "p" .. nextId
	nextId += 1
	local sz = if forced then forced.sz else rollSize()
	local root = makeRoot(def, pos, sz)
	root:SetAttribute("PetId", id)
	root:SetAttribute("PetKey", def.key)
	root:SetAttribute("Tier", def.tier)
	root:SetAttribute("Zone", zone)
	root:SetAttribute("State", "wild")
	root:SetAttribute("OwnerUserId", if owner then owner.UserId else 0) -- clients hide others' personal rares
	local mut = if forced then forced.mut else rollMutation()
	root:SetAttribute("Mut", mut)
	root:SetAttribute("Size", sz)
	local pet: WildPet = {
		id = id, def = def, zone = zone, root = root, state = "wild",
		loopIdx = rng:NextInteger(1, #Config.poseLoop), action = "idle", actionEnd = 0,
		wanderTo = nil, dazedUntil = 0, pose = nil, mut = mut, sz = sz, offerFor = nil, dazedOwner = nil, superUsed = false,
		offered = false, meter = 0, fleeFrom = nil, shownMeter = 0, owner = owner,
		dartAt = 0, swerve = 0, swerveAt = 0, bornAt = os.clock(),
	}
	setAction(pet, Config.poseLoop[pet.loopIdx])
	pet.actionEnd = os.clock() + rng:NextNumber() * Config.poses[pet.action].seconds
	pets[id] = pet
	root.Parent = folder
	return pet
end

-- a melted cube's pet: dazed for a while, only its carrier can refreeze it, then it's wild again.
-- open (Round 5 ray-tag): a cube knocked out of someone's hands is anyone's to zap, so it isn't personal.
-- knocked (tag or critter, not open): personal to the carrier at any tier, so a tagger can't take it
-- once the daze ends (QA IR-20)
function WildPetSpawner.spawnDazed(info: { key: string, zone: number, pose: string, mut: string?, sz: string?, superUsed: boolean, offered: boolean }, pos: Vector3, owner: Player, offer: boolean, open: boolean?, knocked: boolean?): WildPet?
	local def = PetDefs.get(info.key)
	local personal = def ~= nil and Config.spawner.personalRares and not open
		and (Config.tier(def.tier).rank >= 3 or knocked == true)
	local pet = WildPetSpawner.spawn(info.zone, pos, info.key, false, if personal then owner else nil)
	if not pet then
		return nil
	end
	pet.state = "dazed"
	pet.knocked = knocked
	pet.dazedUntil = os.clock() + Config.dazedSeconds
	pet.pose = info.pose
	pet.mut = info.mut
	if pet.sz ~= info.sz and pet.def then
		-- it keeps the size it was frozen with: redo the fresh roll's root, bottom on the same ground
		pet.sz = info.sz
		local h = PetDefs.height(pet.def, info.sz)
		local r = pet.root
		local bottom = r.Position.Y - r.Size.Y / 2
		r.Size = Vector3.new(h, h, h)
		r.CFrame = CFrame.new(r.Position.X, bottom + h / 2, r.Position.Z)
	end
	pet.root:SetAttribute("Size", info.sz)
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
		pet.fleeBy = by -- Frost Boots: the shooter's gear slows its run
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

-- a restless tier's motion (Config.spawner.motion), nil for everyone else
local function motionOf(pet: WildPet)
	return Config.spawner.motion[pet.def.tier]
end

-- one step away from the shooter, turning along the walls when the straight way out is blocked.
-- A restless pet zig-zags: it swerves a random amount every few tenths of a second
local function flee(pet: WildPet, dt: number, speed: number)
	local from = pet.root.Position
	local here = WorldRules.zoneAt(from) -- the island it stands on (a melted pet can land on one nearer home)
	local away = Vector3.new(from.X - (pet.fleeFrom :: Vector3).X, 0, from.Z - (pet.fleeFrom :: Vector3).Z)
	if away.Magnitude < 0.01 then
		away = pet.root.CFrame.LookVector * Vector3.new(1, 0, 1)
	end
	away = away.Unit
	-- every scared pet dodges (Config.aim.dodge; Mythic and Secret wilder, Config.spawner.motion)
	local m = motionOf(pet)
	local zig = if m then m.zigzag else Config.aim.dodge.zigzag
	local every = if m then m.swerveEvery else Config.aim.dodge.swerveEvery
	local now = os.clock()
	if now >= (pet.swerveAt or 0) then
		pet.swerveAt = now + every
		pet.swerve = (rng:NextNumber() * 2 - 1) * zig
	end
	away = (CFrame.Angles(0, pet.swerve or 0, 0) * CFrame.new(away)).Position
	local step = speed * dt
	for _, turn in { 0, 0.7, -0.7, 1.4, -1.4, 2.1, -2.1 } do
		local dir = (CFrame.Angles(0, turn, 0) * CFrame.new(away)).Position
		local to = from + dir * step
		if WorldRules.zoneAt(to) == here and WorldRules.inTunnel(to, Config.spawner.wallMargin) then
			pet.root.CFrame = CFrame.lookAt(to, to + dir)
			return
		end
	end
end

function WildPetSpawner.clearOffer(pet: WildPet)
	pet.offerFor = nil
	pet.root:SetAttribute("OfferUserId", 0)
end

local function tick(dt: number)
	local now = os.clock()
	local night = EventService.isNight()
	for _, pet in pets do
		-- night: wild pets curl up and sleep (easy to freeze); morning: back to their pose loop
		local m = motionOf(pet)
		local sleeps = Config.night.petsSleep and (m == nil or m.sleeps)
		if pet.state == "wild" and (night and sleeps) ~= (pet.action == "sleep") and pet.meter < Config.aim.stuckAt then
			setAction(pet, if night and sleeps then "sleep" else Config.poseLoop[pet.loopIdx])
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
			-- (the old Frost Boots slowed this; since the 2026-11-17 gear rework the boots make you faster instead)
			flee(pet, dt, Config.aim.fleeSpeed * slow * (if m then m.flee else Config.aim.fleeTier[pet.def.tier] or 1))
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
				if WorldRules.zoneAt(t) == WorldRules.zoneAt(pet.root.Position) and WorldRules.inTunnel(t, Config.spawner.wallMargin) then
					pet.wanderTo = t
				end
			end
		end
		-- restless: darts to a new random spot every so often, whatever its pose
		if m and now >= pet.dartAt then
			pet.dartAt = now + m.dart[1] + rng:NextNumber() * (m.dart[2] - m.dart[1])
			local a = rng:NextNumber() * math.pi * 2
			local r = m.dartRadius * (0.4 + 0.6 * rng:NextNumber())
			local t = pet.root.Position + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
			if WorldRules.zoneAt(t) == WorldRules.zoneAt(pet.root.Position) and WorldRules.inTunnel(t, Config.spawner.wallMargin) then
				pet.wanderTo = t
			end
		end
		if pet.wanderTo and (pet.action == "idle" or m ~= nil) then
			local from = pet.root.Position
			local to = Vector3.new(pet.wanderTo.X, from.Y, pet.wanderTo.Z)
			local d = (to - from).Magnitude
			local step = Config.spawner.wanderSpeed * dt * slow * (if m then m.speed else 1)
			if d < step then
				pet.wanderTo = nil
			else
				pet.root.CFrame = CFrame.lookAt(from + (to - from).Unit * step, to)
			end
		end
	end
end

-- the Secret clock (Config.secretSpawn, owner 2026-11-16): at each half hour ONE shared Secret appears on the whole
-- map (owner: "only 1 in the whole map, not 1 per island"), on a ready island picked at random; anyone whose Cold
-- Power and gun can freeze that island's pets may catch it, and the whole server hears where it is.
-- It leaves after lifeSeconds unless someone has ice on it. lastSecretSlot = the half hour already done.
local lastSecretSlot: number? = nil
local secretBorn: { [string]: number } = {} -- pet id -> os.clock() it appeared

function WildPetSpawner.spawnSecrets(): { string }
	local names: { string } = {}
	local choices: { Config.Zone } = {}
	for _, z in Config.world.zones do
		if z.ready and #PetDefs.inZone(z.id, "Secret") > 0 then
			table.insert(choices, z)
		end
	end
	if #choices == 0 then
		return names
	end
	local z = choices[rng:NextInteger(1, #choices)]
	local pool = PetDefs.inZone(z.id, "Secret")
	local pet = WildPetSpawner.spawn(z.id, nil, pool[rng:NextInteger(1, #pool)].key, false, nil)
	if pet then
		secretBorn[pet.id] = os.clock()
		pet.root:SetAttribute("ClockSecret", true)
		table.insert(names, z.name)
	end
	return names
end

local function secretTick()
	local S = Config.secretSpawn
	local _, slot = WorldRules.secretIn(workspace:GetServerTimeNow())
	if lastSecretSlot == nil then
		lastSecretSlot = slot -- a server that starts mid-way waits for the next half hour
	elseif slot ~= lastSecretSlot then
		lastSecretSlot = slot
		local names = WildPetSpawner.spawnSecrets()
		if #names > 0 then
			Remotes.fireAll("Notify", "secretSpawned", { islands = names, count = #names })
		end
	end
	local out = 0
	for id, born in secretBorn do
		local pet = pets[id]
		if not pet then
			secretBorn[id] = nil
		elseif os.clock() - born > S.lifeSeconds and pet.meter <= 0 then
			secretBorn[id] = nil
			WildPetSpawner.remove(id)
		else
			out += 1
		end
	end
	if workspace:GetAttribute("SecretsOut") ~= out then
		workspace:SetAttribute("SecretsOut", out) -- the HUD's Secret clock says "SECRET IS OUT!" while one is
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
function WildPetSpawner.devSpawnPet(player: Player, key: string, zone: number, forced: Forced?, personal: boolean?): WildPet?
	local def = PetDefs.get(key)
	if not def then
		return nil
	end
	local owner = if personal or Config.tier(def.tier).rank >= 3 then player else nil
	if zone == 0 then
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root then
			return nil
		end
		local spread = rng:NextNumber() * math.pi * 2 -- a few at once don't stack in one spot
		local at = Vector3.new(root.Position.X + math.cos(spread) * 7, 0, root.Position.Z + math.sin(spread) * 7)
		return WildPetSpawner.spawn(math.max(1, WorldRules.zoneAt(root.Position)), at, key, false, owner, forced)
	end
	return WildPetSpawner.spawn(zone, nil, key, false, owner, forced)
end

-- admin rain (2026-11-18): count shared pets on every ready island, rarity tier ("" = rolled), forced size / mutation
function WildPetSpawner.rain(tier: string, count: number, forced: Forced?): number
	local made = 0
	for _, z in Config.world.zones do
		if not z.ready then
			continue
		end
		for _ = 1, count do
			local t = if tier ~= "" then tier else pickTier()
			local pool = PetDefs.inZone(z.id, t)
			if #pool > 0 and WildPetSpawner.spawn(z.id, nil, pool[rng:NextInteger(1, #pool)].key, false, nil, forced) then
				made += 1
			end
		end
	end
	return made
end

-- admin: a fresh wave now (the islands' shared wild pets go and new ones roll, like a sunrise)
function WildPetSpawner.newWave()
	WildPetSpawner.nightReset(true)
	WildPetSpawner.nightReset(false)
end

-- tester: every wild pet nobody is busy with goes (a clean island to test on)
function WildPetSpawner.clearWild(): number
	local n = 0
	for id, pet in pets do
		if pet.state == "wild" and pet.meter <= 0 and not pet.tutorial then
			WildPetSpawner.remove(id)
			n += 1
		end
	end
	return n
end

function WildPetSpawner.Init()
	folder = WorldService.petsFolder("WildPets")
end

-- the day's wave: every ready island gets Config.night.wave.perIsland pets, each one's rarity rolled from the
-- rarities as they are (pickTier), then a pet of that rarity from the island, its size and its mutation.
-- Shared: every player sees the same pets. The first nearCount (below Rare) go in the near band, so there's
-- one a few steps in; Rare and up go in the far half. Server start and every sunrise.
local function rollWave()
	for _, z in Config.world.zones do
		if not z.ready then
			continue
		end
		for i = 1, Config.night.wave.perIsland do
			local tier = pickTier()
			local pool = PetDefs.inZone(z.id, tier)
			if #pool > 0 then
				local near = i <= Config.spawner.nearCount and Config.tier(tier).rank < 3
				WildPetSpawner.spawn(z.id, nil, pool[rng:NextInteger(1, #pool)].key, near)
			end
		end
	end
end

-- Commons don't hang about (owner 2026-11-17 night: "rare pets don't spawn that often, commons despawn too
-- slowly"): a wild Common nobody has ice on wanders off after Config.night.wave.commonLeave seconds, and a fresh
-- pet takes its place on the same island, its rarity rolled like the wave's. Never at night (the islands are
-- shut), never a pet that's someone's (tutorial, a melted cube's), being chased, dazed or on offer.
local function replaceStaleCommons()
	local after = Config.night.wave.commonLeave
	if not after or after <= 0 or EventService.isNight() then
		return
	end
	local now = os.clock()
	local gone: { number } = {}
	for id, pet in pets do
		if pet.state == "wild" and pet.def.tier == "Common" and pet.meter <= 0 and not pet.knocked and not pet.tutorial
			and not pet.owner and not pet.offerFor and not pet.fleeFrom and now - (pet.bornAt or now) >= after then
			table.insert(gone, pet.zone)
			WildPetSpawner.remove(id)
		end
	end
	for _, zone in gone do
		local pool = PetDefs.inZone(zone, pickTier())
		if #pool > 0 then
			WildPetSpawner.spawn(zone, nil, pool[rng:NextInteger(1, #pool)].key, false)
		end
	end
end

-- Night Reset (Config.night): night falls = every wild pet on every island goes (never one with ice on it, a
-- melted or knocked cube's pet, the tutorial pet, or the Secret on its clock). Sunrise = the new wave at once.
function WildPetSpawner.nightReset(night: boolean)
	if night then
		for id, pet in pets do
			if pet.state == "wild" and pet.meter <= 0 and not pet.knocked and not pet.tutorial
				and not pet.root:GetAttribute("ClockSecret") then
				WildPetSpawner.remove(id)
			end
		end
	else
		dawnWave = true -- the sunrise wave may roll night-only mutations (Starry)
		local ok, err = pcall(rollWave)
		dawnWave = false
		if not ok then
			warn("[WildPetSpawner] sunrise wave:", err)
		end
	end
end

function WildPetSpawner.Start()
	if not EventService.isNight() then
		rollWave() -- a server that starts in the night waits for sunrise's wave, like every other server
	end
	EventService.NightChanged:Connect(WildPetSpawner.nightReset)
	task.spawn(function()
		while true do
			task.wait(5)
			local ok, err = pcall(replaceStaleCommons)
			if not ok then
				warn("[WildPetSpawner] common refresh:", err)
			end
		end
	end)
	-- first minute: a fluffy bunny next to the spawn, and a second and third pet right there
	DataService.Loaded:Connect(function(player: Player, data: any)
		if data.stats.frozen == 0 then
			-- the hub is safe (no wild pets), so it waits just inside the tunnel mouth, straight ahead. It's
			-- theirs (2026-11-15): nobody else takes it, and the Night Reset leaves it alone
			local s = Config.world.spawn
			local first = WildPetSpawner.spawn(1, Vector3.new(s.X + 4, 0, Config.world.hubZMax + Config.spawner.firstPetDistance), "snowbun", false, player)
			if first then
				first.tutorial = true
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		for id, p in pets do
			if p.owner == player then
				WildPetSpawner.remove(id) -- their own pet (tutorial pet, a melted cube's Rare) leaves with them
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
			local ok2, err2 = pcall(secretTick)
			if not ok2 then
				warn("[WildPetSpawner] secret clock:", err2)
			end
			last = now
		end
	end)
end

return WildPetSpawner
