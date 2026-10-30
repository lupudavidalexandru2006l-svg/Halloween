--!strict
-- WildPetSpawner: spawn rolls (server only, with soft pity), the action loop that decides poses,
-- wandering, dazed pets after a melt, and the live odds on every zone sign.
-- Each wild pet is an invisible anchored "PetRoot" part with attributes and a ProximityPrompt;
-- clients draw the pet model on it (PetVisuals) and play the action as an animation.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Theme = require(ReplicatedStorage.Shared.Theme)
local PetDefs = require(ReplicatedStorage.Shared.PetDefs)
local WorldRules = require(ReplicatedStorage.Shared.WorldRules)
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
}

local WildPetSpawner = {}
local pets: { [string]: WildPet } = {}
local pity: { [number]: { [string]: number } } = {}
local respawnAt: { [number]: number } = {}
local nextId = 1
local rng = Random.new()
local folder: Folder

local TIER_NAMES = {}
for _, t in Config.tiers do
	table.insert(TIER_NAMES, t.name)
end

function WildPetSpawner.shownOdds(zone: number): { [string]: number }
	local p = pity[zone] or {}
	pity[zone] = p
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

local function rollTier(zone: number): string
	local odds = WildPetSpawner.shownOdds(zone)
	local r = rng:NextNumber() * 100
	local tier = "Common"
	for _, name in TIER_NAMES do
		if r < odds[name] then
			tier = name
			break
		end
		r -= odds[name]
	end
	local p = pity[zone]
	local rolledRank = Config.tier(tier).rank
	for _, t in Config.tiers do
		if t.rank >= 3 then
			p[t.name] = if rolledRank >= t.rank then 0 else (p[t.name] or 0) + 1
		end
	end
	return tier
end

local function randomSpot(zone: number, near: boolean): Vector3?
	local z = Config.zone(zone)
	if not z then
		return nil
	end
	local b = Config.world.bounds
	local sp = Config.spawner
	for _ = 1, 30 do
		local x, zz
		if near then
			x = -15 + rng:NextNumber() * 30
			zz = sp.nearZ[1] + rng:NextNumber() * (sp.nearZ[2] - sp.nearZ[1])
		else
			local zMin = if zone == 1 then sp.farZMin else z.zMin + 10
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

function WildPetSpawner.spawn(zone: number, at: Vector3?, forcedKey: string?, near: boolean?): WildPet?
	local def: PetDefs.PetDef?
	if forcedKey then
		def = PetDefs.get(forcedKey)
	else
		local pool = PetDefs.inZone(zone, rollTier(zone))
		def = pool[rng:NextInteger(1, #pool)]
	end
	local pos = at or randomSpot(zone, near == true)
	if not def or not pos then
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
	local pet: WildPet = {
		id = id, def = def, zone = zone, root = root, prompt = pp, state = "wild",
		loopIdx = rng:NextInteger(1, #Config.poseLoop), action = "idle", actionEnd = 0,
		wanderTo = nil, dazedUntil = 0, pose = nil, mut = nil, offerFor = nil, dazedOwner = nil, superUsed = false,
	}
	setAction(pet, Config.poseLoop[pet.loopIdx])
	pet.actionEnd = os.clock() + rng:NextNumber() * Config.poses[pet.action].seconds
	pets[id] = pet
	root.Parent = folder
	return pet
end

-- a melted cube's pet: dazed for a while, only its carrier can refreeze it, then it's wild again
function WildPetSpawner.spawnDazed(info: { key: string, zone: number, pose: string, mut: string?, superUsed: boolean }, pos: Vector3, owner: Player, offer: boolean): WildPet?
	local pet = WildPetSpawner.spawn(info.zone, pos, info.key)
	if not pet then
		return nil
	end
	pet.state = "dazed"
	pet.dazedUntil = os.clock() + Config.dazedSeconds
	pet.pose = info.pose
	pet.mut = info.mut
	pet.superUsed = info.superUsed
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

function WildPetSpawner.clearOffer(pet: WildPet)
	pet.offerFor = nil
	pet.root:SetAttribute("OfferUserId", 0)
end

local function tick(dt: number)
	local now = os.clock()
	for _, pet in pets do
		if pet.state == "dazed" then
			if pet.offerFor then
				local hrp = pet.offerFor.Character and pet.offerFor.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
				if not hrp or (hrp.Position - pet.root.Position).Magnitude > Config.monetization.superFreeze.walkAwayStuds then
					WildPetSpawner.clearOffer(pet) -- the button goes away when you walk off
				end
			end
			if now >= pet.dazedUntil then
				pet.state = "wild"
				pet.dazedOwner = nil
				WildPetSpawner.clearOffer(pet)
				pet.prompt.HoldDuration = Config.player.freezeHold
				pet.prompt.ActionText = "Freeze"
				pet.root:SetAttribute("State", "wild")
			end
			continue
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
	for _, z in Config.world.zones do
		local count = 0
		for _, p in pets do
			if p.zone == z.id then
				count += 1
			end
		end
		if count < Config.spawner.maxPerZone and now >= (respawnAt[z.id] or 0) then
			WildPetSpawner.spawn(z.id)
			respawnAt[z.id] = now + Config.spawner.respawnSeconds
		end
	end
end

local function drawSign(zone: Config.Zone)
	local part = WorldService.zoneSigns[zone.id]
	if not part then
		return
	end
	local sg = part:FindFirstChild("Odds") :: SurfaceGui?
	if not sg then
		local g = Instance.new("SurfaceGui")
		g.Name = "Odds"
		g.Face = Enum.NormalId.Front
		g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		g.PixelsPerStud = 40
		local frame = Instance.new("Frame")
		frame.Size = UDim2.fromScale(1, 1)
		frame.BackgroundColor3 = Theme.panel
		frame.Parent = g
		local list = Instance.new("UIListLayout")
		list.Padding = UDim.new(0.01, 0)
		list.Parent = frame
		local function row(name: string, text: string, h: number, color: Color3?)
			local t = Instance.new("TextLabel")
			t.Name = name
			t.Size = UDim2.fromScale(1, h)
			t.BackgroundTransparency = 1
			t.TextScaled = true
			t.Font = Theme.font
			t.TextColor3 = color or Theme.ink
			t.Text = text
			t.Parent = frame
		end
		row("Title", zone.name, 0.14)
		row("Heat", `Melt speed x{zone.heat} - shade melts slower`, 0.07)
		for _, t in Config.tiers do
			row(t.name, t.name, 0.1, Theme.tiers[t.name])
		end
		g.Parent = part
		sg = g
	end
	local odds = WildPetSpawner.shownOdds(zone.id)
	local frame = (sg :: SurfaceGui):FindFirstChildOfClass("Frame") :: Frame
	for _, t in Config.tiers do
		local label = frame:FindFirstChild(t.name) :: TextLabel?
		if label then
			local o = odds[t.name]
			local shown = if o >= 1 then string.format("%.1f%%", o) elseif o >= 0.01 then string.format("%.2f%%", o) else `1 in {math.round(100 / o)}`
			label.Text = `{t.name}   {shown}` -- the true odds, pity included
		end
	end
end

function WildPetSpawner.Init()
	folder = WorldService.petsFolder("WildPets")
end

function WildPetSpawner.Start()
	for _, z in Config.world.zones do
		for _ = 1, Config.spawner.maxPerZone - 2 do
			WildPetSpawner.spawn(z.id)
		end
	end
	-- first minute: a fluffy bunny next to the spawn, and a second and third pet right there
	DataService.Loaded:Connect(function(player: Player, data: any)
		if data.stats.frozen == 0 then
			local s = Config.world.spawn
			WildPetSpawner.spawn(1, Vector3.new(s.X + 4, 0, s.Z + Config.spawner.firstPetDistance), "snowbun")
		end
		for _ = #data.pets + 2, Config.spawner.nearUntilPets do
			WildPetSpawner.spawn(1, nil, nil, true)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		for _, p in pets do
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
			for _, z in Config.world.zones do
				drawSign(z)
			end
			task.wait(5)
		end
	end)
end

return WildPetSpawner
