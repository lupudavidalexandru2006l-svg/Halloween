--!strict
-- WildPetSpawner: spawn rolls (server only, with soft pity), the action loop that decides poses,
-- wandering, dazed pets after a melt, and each player's own odds for the zone signs.
-- Personal rares (owner 2026-10-30): every player has their own roll stream and pity. A roll that lands
-- Common or Uncommon goes into the shared zone pool; Rare and up spawns a pet only that player sees and
-- can freeze (OwnerUserId on the root). A player's rolls run while the zone they'd see (shared pets plus
-- their own) has room, so one player's odds and pace are the same as playing solo.
-- Each wild pet is an invisible anchored "PetRoot" part with attributes and a ProximityPrompt;
-- clients draw the pet model on it (PetVisuals) and play the action as an animation.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local PetDefs = require(ReplicatedStorage.Shared.PetDefs)
local WorldRules = require(ReplicatedStorage.Shared.WorldRules)
local Remotes = require(script.Parent.Remotes)
local DataService = require(script.Parent.DataService)
local WorldService = require(script.Parent.WorldService)

export type WildPet = {
	id: string,
	def: PetDefs.PetDef,
	zone: number,
	root: Part,
	prompt: ProximityPrompt,
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
	held: number, -- players holding Freeze on it right now (it acts at half speed)
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

-- the true odds for this player in this zone, their own pity included (shown on the zone signs)
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
	local b = Config.world.bounds
	local sp = Config.spawner
	for _ = 1, 30 do
		local x, zz
		if near then
			local band = sp.near[zone]
			x = -15 + rng:NextNumber() * 30
			zz = band[1] + rng:NextNumber() * (band[2] - band[1])
		else
			-- Rare and up only in the far half, so the pets worth most have the longest run home
			local zMin = if rare then math.max(sp.farZMin[zone], (z.zMin + z.zMax) / 2) else sp.farZMin[zone]
			x = b.xMin + 6 + rng:NextNumber() * (b.xMax - b.xMin - 12)
			zz = zMin + rng:NextNumber() * (z.zMax - 10 - zMin)
		end
		if zz < Config.world.river.zMin - 2 or zz > Config.world.gate.z + 3 then
			return Vector3.new(x, 0, zz)
		end
	end
	return nil
end

local function makeRoot(def: PetDefs.PetDef, pos: Vector3): (Part, ProximityPrompt)
	local h = PetDefs.sizeHeight[def.size]
	local root = Instance.new("Part")
	root.Name = "PetRoot"
	root.Size = Vector3.new(h, h, h)
	root.CFrame = CFrame.new(pos + Vector3.new(0, h / 2, 0))
	root.Anchored = true
	root.CanCollide = false
	root.CanTouch = false
	root.Transparency = 1
	local a = Instance.new("Attachment")
	a.Position = Vector3.new(0, h / 2 + 1, 0)
	a.Parent = root
	local pp = Instance.new("ProximityPrompt")
	pp.ActionText = "Freeze"
	pp.ObjectText = def.name
	pp.HoldDuration = Config.player.freezeHold
	pp.MaxActivationDistance = Config.player.freezeRange
	pp.RequiresLineOfSight = false
	pp.Style = Enum.ProximityPromptStyle.Custom
	pp.Parent = a
	return root, pp
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
		def = pool[rng:NextInteger(1, #pool)]
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
	local root, pp = makeRoot(def, pos)
	root:SetAttribute("PetId", id)
	root:SetAttribute("PetKey", def.key)
	root:SetAttribute("Tier", def.tier)
	root:SetAttribute("Zone", zone)
	root:SetAttribute("State", "wild")
	root:SetAttribute("OwnerUserId", if owner then owner.UserId else 0) -- clients hide others' personal rares
	local pet: WildPet = {
		id = id, def = def, zone = zone, root = root, prompt = pp, state = "wild",
		loopIdx = rng:NextInteger(1, #Config.poseLoop), action = "idle", actionEnd = 0,
		wanderTo = nil, dazedUntil = 0, pose = nil, mut = nil, offerFor = nil, dazedOwner = nil, superUsed = false,
		offered = false, held = 0, owner = owner,
	}
	setAction(pet, Config.poseLoop[pet.loopIdx])
	pet.actionEnd = os.clock() + rng:NextNumber() * Config.poses[pet.action].seconds
	pets[id] = pet
	root.Parent = folder
	return pet
end

-- a melted cube's pet: dazed for a while, only its carrier can refreeze it, then it's wild again
function WildPetSpawner.spawnDazed(info: { key: string, zone: number, pose: string, mut: string?, superUsed: boolean, offered: boolean }, pos: Vector3, owner: Player, offer: boolean): WildPet?
	local def = PetDefs.get(info.key)
	local personal = def ~= nil and Config.tier(def.tier).rank >= 3 and Config.spawner.personalRares
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
	pet.dazedOwner = owner
	pet.offerFor = if offer then owner else nil
	pet.prompt.HoldDuration = Config.player.refreezeHold
	pet.prompt.ActionText = "Zap"
	pet.root:SetAttribute("State", "dazed")
	pet.root:SetAttribute("Pose", info.pose)
	pet.root:SetAttribute("Mut", info.mut)
	pet.root:SetAttribute("OfferUserId", if offer then owner.UserId else 0)
	return pet
end

-- FreezeService listens to ProximityPromptService and asks which pet a prompt belongs to
-- (the spawner owns pets and never calls FreezeService, so there is no require cycle)
function WildPetSpawner.idFromPrompt(prompt: ProximityPrompt): string?
	local root = prompt.Parent
	if not root or root.Parent ~= folder then
		return nil
	end
	local id = root:GetAttribute("PetId")
	if typeof(id) == "string" and pets[id] then
		return id
	end
	return nil
end

function WildPetSpawner.get(id: string): WildPet?
	return pets[id]
end

function WildPetSpawner.remove(id: string)
	local p = pets[id]
	if p then
		pets[id] = nil
		p.root:Destroy()
	end
end

-- FreezeService says when a player starts and stops holding Freeze on a pet
function WildPetSpawner.setHeld(id: string, on: boolean)
	local p = pets[id]
	if p then
		p.held = math.max(0, p.held + (if on then 1 else -1))
		p.root:SetAttribute("Held", p.held > 0) -- clients play its animation at half speed too
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
	for _, pet in pets do
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
				pet.prompt.HoldDuration = Config.player.freezeHold
				pet.prompt.ActionText = "Freeze"
				pet.root:SetAttribute("State", "wild")
			end
			continue
		end
		if pet.held > 0 then
			pet.actionEnd += dt * (1 - Config.zapSlowdown) -- half speed while someone holds Freeze on it
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
				if WorldRules.zoneAt(t) == pet.zone then
					pet.wanderTo = t
				end
			end
		end
		if pet.wanderTo and pet.action == "idle" then
			local from = pet.root.Position
			local to = Vector3.new(pet.wanderTo.X, from.Y, pet.wanderTo.Z)
			local d = (to - from).Magnitude
			local step = Config.spawner.wanderSpeed * dt
			if d < step then
				pet.wanderTo = nil
			else
				pet.root.CFrame = CFrame.lookAt(from + (to - from).Unit * step, to)
			end
		end
	end
	local sp = Config.spawner
	for _, z in Config.world.zones do
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
			if not data or (z.id == 2 and not data.forestUnlocked) then
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
			local def = pool[rng:NextInteger(1, #pool)]
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

-- the zone signs show your own odds (personal rares, own pity): each client draws them on the sign
local function pushOdds()
	for _, player in Players:GetPlayers() do
		if DataService.isLoaded(player) then
			local byZone = {}
			for _, z in Config.world.zones do
				byZone[tostring(z.id)] = WildPetSpawner.shownOdds(player, z.id)
			end
			Remotes.fire(player, "Notify", "odds", byZone)
		end
	end
end

function WildPetSpawner.Init()
	folder = WorldService.petsFolder("WildPets")
end

function WildPetSpawner.Start()
	for _, z in Config.world.zones do
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
			local s = Config.world.spawn
			WildPetSpawner.spawn(1, Vector3.new(s.X + 4, 0, s.Z + Config.spawner.firstPetDistance), "snowbun")
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
			tick(now - last)
			last = now
		end
	end)
	task.spawn(function()
		while true do
			pushOdds()
			task.wait(Config.oddsPushSeconds)
		end
	end)
end

return WildPetSpawner
