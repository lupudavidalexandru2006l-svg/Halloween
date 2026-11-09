--!strict
-- CarryService: owns the cubes each player carries. Melt ticks on the SERVER (heat x shade/sun,
-- nothing melts during the Big Chill or in a Super Freeze cube). A melted cube becomes a dazed pet
-- (only you can zap it back, free, always) and, for Rare and up, a Super Freeze offer at most once per run.
-- The cube Part is welded to the character so everyone sees it; clients draw the pet inside and the melt.
-- A fresh freeze first waits on the ground where the pet stood (owner 2026-11-07): only the player who
-- froze it picks it up, with E, and then it's carried like any other cube. Ground cubes don't melt;
-- one left alone for Config.carry.groundSeconds thaws back into a dazed pet. With Config.carry.autoPickUp
-- (QA 2026-11-08) FreezeService picks it up for you a moment after the snap, so there's no E.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Theme = require(ReplicatedStorage.Shared.Theme)
local PetDefs = require(ReplicatedStorage.Shared.PetDefs)
local WorldRules = require(ReplicatedStorage.Shared.WorldRules)
local Remotes = require(script.Parent.Remotes)
local DataService = require(script.Parent.DataService)
local AnalyticsSvc = require(script.Parent.AnalyticsSvc)
local PlayerTracker = require(script.Parent.PlayerTracker)
local WorldService = require(script.Parent.WorldService)
local WildPetSpawner = require(script.Parent.WildPetSpawner)
local EventService = require(script.Parent.EventService)

export type CubeInfo = { key: string, zone: number, pose: string, mut: string?, superFrozen: boolean, superUsed: boolean, offered: boolean }
export type Cube = CubeInfo & { uid: string, life: number, lifeMax: number, since: number, part: Part? , shownFrac: number,
	graceUntil: number } -- no melting before this (os.clock): the freeze show for this cube is still playing

local CarryService = {}
local carrying: { [Player]: { Cube } } = {}
local ground: { [Player]: { Cube } } = {} -- frozen, waiting where the pet stood for its owner's E
local nextUid = 1
local folder: Folder
local groundFolder: Folder
local leaveHandler: ((Player, Cube) -> ())? = nil -- FreezeService: keeps a pet whose show was still playing

function CarryService.count(player: Player): number
	local list = carrying[player]
	return if list then #list else 0
end

-- carried plus waiting on the ground: what counts against your hands' room
function CarryService.load(player: Player): number
	local list = ground[player]
	return CarryService.count(player) + (if list then #list else 0)
end

-- how many cubes fit in your hands: the old Backpack upgrade, or your gun's beams if that's more (the
-- Backpack can't be bought since 2026-11-05, so a many-beam gun's extra beams had no room and its Beams
-- stat did nothing: QA 2026-11-05, PT-02)
function CarryService.capacity(player: Player): number
	local data = DataService.get(player)
	if not data then
		return 1
	end
	return math.max(data.upgrades.backpack, Config.gun(data.guns.equipped).beams)
end

local function cubeSize(player: Player, def: PetDefs.PetDef): number
	local data = DataService.get(player)
	local ray = if data then data.upgrades.ray else 1
	return PetDefs.cubeSize[def.size] * Config.cubeSizeFactor(ray) * Config.carry.scale -- carried cubes are smaller, so the stack never hides you
end

-- where a body joint holds its second part on its first, standing still: a Motor6D (classic rigs) or an
-- AnimationConstraint (newer avatars, joined by two attachments)
local function restOf(joint: Instance?): CFrame?
	if joint and joint:IsA("Motor6D") then
		return joint.C0 * joint.C1:Inverse()
	elseif joint and joint:IsA("AnimationConstraint") and joint.Attachment0 and joint.Attachment1 then
		return joint.Attachment0.CFrame * joint.Attachment1.CFrame:Inverse()
	end
	return nil
end

-- weld the stack in front of the character, the first cube in its hands and the rest on top
-- (re-run after respawn or any change; clients raise both arms while you carry: RayController)
local function layout(player: Player)
	local list = carrying[player]
	local hrp = PlayerTracker.rootPart(player)
	if not list or not hrp then
		return
	end
	-- the stack rides on the upper torso, so it bobs and leans with the body as you walk (owner
	-- 2026-11-03: welded to the root it slid along while the body moved, which looked strange). It's
	-- placed from the torso's standing pose on the root, so it sits where it always did.
	local holder: BasePart, rest = hrp, CFrame.identity
	local character = player.Character
	local torso = character and character:FindFirstChild("UpperTorso")
	local lower = character and character:FindFirstChild("LowerTorso")
	local root = restOf(lower and lower:FindFirstChild("Root"))
	local waist = restOf(torso and torso:FindFirstChild("Waist"))
	if torso and torso:IsA("BasePart") and root and waist then
		holder = torso
		rest = root * waist
	end
	local K = Config.carry
	local y = K.handY
	for _, c in list do
		local part = c.part
		if part then
			local s = part.Size.Y
			for _, w in part:GetChildren() do
				if w:IsA("Weld") then
					w:Destroy()
				end
			end
			local at = CFrame.new(0, y + s / 2, -(K.front + s / 2)) -- the character looks down -Z
			part.CFrame = hrp.CFrame * at
			local weld = Instance.new("Weld")
			weld.Part0 = holder
			weld.Part1 = part
			weld.C0 = rest:Inverse() * at
			weld.Parent = part
			part.Parent = folder
			y += s + K.stackGap
		end
	end
end

local function makePart(player: Player, c: Cube): Part
	local def = PetDefs.get(c.key) :: PetDefs.PetDef
	local s = cubeSize(player, def)
	local p = Instance.new("Part")
	p.Name = "Cube"
	p.Size = Vector3.new(s, s, s)
	p.Material = Enum.Material.SmoothPlastic -- not Glass: it would hide a sprite pet inside (World Rules)
	p.Color = if c.superFrozen then Theme.iceDeep else Theme.ice
	p.Transparency = if c.superFrozen then 0.35 else 0.45
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.Massless = true
	p.Anchored = false
	p:SetAttribute("CubeUid", c.uid)
	p:SetAttribute("PetKey", c.key)
	p:SetAttribute("Pose", c.pose)
	p:SetAttribute("Mut", c.mut)
	p:SetAttribute("SuperFrozen", c.superFrozen)
	p:SetAttribute("LifeFrac", 1)
	p:SetAttribute("OwnerUserId", player.UserId)
	return p
end

local function newCube(def: PetDefs.PetDef, data: any, info: CubeInfo, graceSeconds: number?): Cube
	local home = Config.zone(def.zone)
	local lifeMax = Config.tier(def.tier).cubeLife * (1 + Config.upgrades.ray.lifeBonus * (data.upgrades.ray - 1))
		* (if home then home.iceLife else 1) -- a hotter island's pets were frozen by a colder gun: their ice lasts longer (Round 4 phase 6)
	local c: Cube = {
		key = info.key, zone = info.zone, pose = info.pose, mut = info.mut, superFrozen = info.superFrozen, superUsed = info.superUsed, offered = info.offered,
		uid = "c" .. nextUid, life = lifeMax, lifeMax = lifeMax, since = os.clock(), part = nil, shownFrac = 1,
		graceUntil = os.clock() + (graceSeconds or 0),
	}
	nextUid += 1
	return c
end

local function changed(player: Player)
	PlayerTracker.setCarrying(player, CarryService.count(player))
	layout(player)
end

-- restoring = a saved Super Freeze cube coming back after a rejoin (it's already in the save)
function CarryService.addCube(player: Player, info: CubeInfo, restoring: boolean?, graceSeconds: number?): string?
	local def = PetDefs.get(info.key)
	local data = DataService.get(player)
	if not def or not data then
		return nil
	end
	if info.superFrozen and not restoring then
		-- a paid cube lives in the save until it's banked, so leaving or a crash never loses it (CA-03).
		-- MonetizationService saves right after this, before returning PurchaseGranted.
		DataService.mutate(player, function(d)
			table.insert(d.superCubes, { key = info.key, pose = info.pose, mut = info.mut })
		end)
	end
	local c = newCube(def, data, info, graceSeconds)
	c.part = makePart(player, c)
	local list = carrying[player] or {}
	table.insert(list, c)
	carrying[player] = list
	changed(player)
	return c.uid
end

-- a fresh freeze: the cube stays on the ground where the pet stood, bottom on the pet's ground, until
-- its owner picks it up with E (pickUp). Returns its uid (it keeps it in your hands, for the show's grace).
function CarryService.dropCube(player: Player, info: CubeInfo, petAt: Vector3, graceSeconds: number?): string?
	local def = PetDefs.get(info.key)
	local data = DataService.get(player)
	if not def or not data then
		return nil
	end
	local c = newCube(def, data, info, graceSeconds)
	local p = makePart(player, c)
	local s = p.Size.Y
	-- the same spot the client's snap draws it at (EffectsController.cubeAt)
	p.CFrame = CFrame.new(petAt - Vector3.new(0, PetDefs.sizeHeight[def.size] / 2, 0) + Vector3.new(0, s / 2, 0))
	p.Anchored = true
	local a = Instance.new("Attachment")
	a.Position = Vector3.new(0, s / 2 + 0.15, 0) -- the top of the cube: the compact pill rests here, the pet stays in view
	a.Parent = p
	local pp = Instance.new("ProximityPrompt")
	pp:SetAttribute("Compact", true) -- PromptController draws it small, above the cube
	pp.ActionText = "Pick up"
	pp.ObjectText = def.name
	pp.HoldDuration = 0
	pp.KeyboardKeyCode = Enum.KeyCode.E
	pp.MaxActivationDistance = Config.carry.pickUpRange
	pp.RequiresLineOfSight = false
	pp.Style = Enum.ProximityPromptStyle.Custom -- drawn by PromptController; other players' clients hide it (PetVisuals)
	pp.Parent = a
	pp.Triggered:Connect(function(who: Player)
		if who == player then
			CarryService.pickUp(player, c.uid)
		end
	end)
	c.part = p
	p.Parent = groundFolder
	local list = ground[player] or {}
	table.insert(list, c)
	ground[player] = list
	return c.uid
end

-- E on your own cube on the ground: it goes into your hands (the client flies it there), and only
-- starts melting from now. auto = the server's own pick-up right after a freeze (Config.carry.autoPickUp):
-- the pet may have been frozen from the gun's full range, past the E prompt's reach
function CarryService.pickUp(player: Player, uid: string, auto: boolean?)
	local list = ground[player]
	local p = PlayerTracker.position(player)
	local c: Cube? = nil
	for i, g in list or {} do
		local at = g.part and g.part.Position
		local near = auto == true or (p ~= nil and at ~= nil and (Vector3.new(p.X, 0, p.Z) - Vector3.new(at.X, 0, at.Z)).Magnitude <= Config.carry.pickUpRange + 2)
		if g.uid == uid and near then
			c = table.remove(list :: { Cube }, i)
			break
		end
	end
	if not c then
		return
	end
	local cube = c :: Cube
	local from = if cube.part then cube.part.CFrame else CFrame.new()
	if cube.part then
		cube.part:Destroy()
	end
	cube.part = makePart(player, cube)
	cube.since = os.clock()
	local hands = carrying[player] or {}
	table.insert(hands, cube)
	carrying[player] = hands
	changed(player)
	Remotes.fire(player, "Notify", "pickedUp", { uid = cube.uid, key = cube.key, from = from })
end

-- left on the ground too long: the pet wakes up dazed where it stood (only you can zap it back)
local function thawOnGround(player: Player, c: Cube)
	local list = ground[player]
	local i = list and table.find(list, c)
	if i then
		table.remove(list :: { Cube }, i)
	end
	local at = if c.part then c.part.Position else PlayerTracker.position(player) or Vector3.zero
	if c.part then
		c.part:Destroy()
	end
	WildPetSpawner.spawnDazed({ key = c.key, zone = c.zone, pose = c.pose, mut = c.mut, superUsed = c.superUsed, offered = c.offered },
		Vector3.new(at.X, 0, at.Z), player, false)
	Remotes.fire(player, "Notify", "melted", { key = c.key, offer = false })
end

-- the show for this cube finished (or was skipped): it melts normally from now on
function CarryService.endGrace(player: Player, uid: string)
	for _, list in { carrying[player] or {}, ground[player] or {} } do
		for _, c in list do
			if c.uid == uid then
				c.graceUntil = math.min(c.graceUntil, os.clock())
			end
		end
	end
end

-- FreezeService hears about cubes that leave with a player while their show still plays
function CarryService.setLeaveHandler(fn: (Player, Cube) -> ())
	leaveHandler = fn
end

-- banking takes every cube (PenService decides what happens to them)
function CarryService.takeAll(player: Player): { Cube }
	local list: { Cube } = carrying[player] or {}
	carrying[player] = {}
	DataService.mutate(player, function(d)
		for _, c in list do
			if c.superFrozen then -- leaves the save as it leaves your back; PenService hands back any it can't bank with addCube
				for i, r in d.superCubes do
					if r.key == c.key and r.pose == c.pose and r.mut == c.mut then
						table.remove(d.superCubes, i)
						break
					end
				end
			end
		end
	end)
	for _, c in list do
		if c.part then
			c.part:Destroy()
		end
	end
	changed(player)
	return list
end

local function melt(player: Player, c: Cube)
	local list = carrying[player]
	if not list then
		return
	end
	local i = table.find(list, c)
	if i then
		table.remove(list, i)
	end
	if c.part then
		c.part:Destroy()
	end
	changed(player)
	local def = PetDefs.get(c.key) :: PetDefs.PetDef
	local pos = PlayerTracker.position(player) or Vector3.zero
	local angle = math.random() * math.pi * 2
	local half = Config.world.tunnel.width / 2 - Config.spawner.wallMargin
	local at = Vector3.new(math.clamp(pos.X + math.cos(angle) * 3, -half, half), 0, pos.Z + math.sin(angle) * 3)
	-- Rare and up, never after a Super Freeze, and at most once per run (the flag rides along through a free re-freeze)
	local offer = Config.tier(def.tier).rank >= Config.tier(Config.monetization.superFreeze.minTier).rank and not c.superUsed and not c.offered
	WildPetSpawner.spawnDazed({ key = c.key, zone = c.zone, pose = c.pose, mut = c.mut, superUsed = c.superUsed, offered = c.offered }, at, player, offer)
	DataService.mutate(player, function(d)
		d.stats.melts += 1
	end)
	local plot = WorldService.plotOf(player)
	local home = if plot then WorldRules.plotCenter(plot) else Config.world.spawn
	AnalyticsSvc.event(player, "cube_melted", {
		pet = c.key, tier = def.tier, zone = c.zone,
		studsFromHome = (Vector3.new(pos.X, 0, pos.Z) - Vector3.new(home.X, 0, home.Z)).Magnitude,
	})
	if offer then
		AnalyticsSvc.event(player, "offer_shown", { offer = "super_freeze", pet = c.key, tier = def.tier })
	end
	Remotes.fire(player, "Notify", "melted", { key = c.key, offer = offer })
end

-- Round 5: the top cube is knocked out of your hands (a Heat Critter caught you, or another player's
-- ray tagged you). Its pet lands dazed next to you, like a melt: open = anyone can zap it (ray-tag),
-- otherwise only you can (critters). A bought Super Freeze cube is never knocked loose. Returns the
-- pet's key, or nil when there was nothing to knock off.
function CarryService.knockOff(player: Player, open: boolean): string?
	local list = carrying[player]
	if not list then
		return nil
	end
	local c: Cube? = nil
	for i = #list, 1, -1 do
		if not list[i].superFrozen and os.clock() >= list[i].graceUntil then
			c = table.remove(list, i)
			break
		end
	end
	if not c then
		return nil
	end
	local cube = c :: Cube
	if cube.part then
		cube.part:Destroy()
	end
	changed(player)
	local pos = PlayerTracker.position(player) or Vector3.zero
	local angle = math.random() * math.pi * 2
	local half = Config.world.tunnel.width / 2 - Config.spawner.wallMargin
	local z = math.clamp(pos.Z + math.sin(angle) * 4, Config.world.hubZMax + 2, Config.world.tunnelEnd - 2) -- never in the safe hub
	local at = Vector3.new(math.clamp(pos.X + math.cos(angle) * 4, -half, half), 0, z)
	WildPetSpawner.spawnDazed({ key = cube.key, zone = cube.zone, pose = cube.pose, mut = cube.mut, superUsed = cube.superUsed, offered = true }, at, player, false, open)
	return cube.key
end

-- called from ProcessReceipt: turn this player's dazed offer pet into a never-melting cube
function CarryService.superFreezeOffer(player: Player): boolean
	local WildPets = workspace:FindFirstChild("WildPets")
	if not WildPets then
		return false
	end
	for _, root in WildPets:GetChildren() do
		if root:GetAttribute("OfferUserId") == player.UserId then
			local pet = WildPetSpawner.get(root:GetAttribute("PetId") :: string)
			if pet and CarryService.load(player) < CarryService.capacity(player) then
				local info = { key = pet.def.key, zone = pet.zone, pose = pet.pose or "idle", mut = pet.mut, superFrozen = true, superUsed = true, offered = true }
				WildPetSpawner.remove(pet.id)
				CarryService.addCube(player, info)
				return true
			end
		end
	end
	return false
end

local function tick(dt: number)
	-- cubes waiting on the ground: the ice clears up as their time runs out (same look as a melt), then the pet wakes up
	local now = os.clock()
	for player, list in ground do
		for _, c in table.clone(list) do
			local left = Config.carry.groundSeconds - (now - math.max(c.since, c.graceUntil))
			if left <= 0 then
				thawOnGround(player, c)
				continue
			end
			local frac = math.clamp(left / Config.carry.groundSeconds, 0, 1)
			if c.part and math.abs(frac - c.shownFrac) > 0.01 then
				c.shownFrac = frac
				c.part:SetAttribute("LifeFrac", frac)
			end
		end
	end
	local chill = EventService.isChill()
	local nightFactor = if EventService.isNight() then Config.melt.night else 1 -- cubes melt slower at night
	for player, list in carrying do
		if #list == 0 then
			continue
		end
		local pos = PlayerTracker.position(player)
		if not pos then
			continue
		end
		local rate = WorldRules.meltRate(pos) * nightFactor
		local data = DataService.get(player)
		local noMelt = data ~= nil and data.tester.noMelt -- tester switch (off for everyone else)
		for _, c in table.clone(list) do
			if not c.superFrozen and not chill and not noMelt and os.clock() >= c.graceUntil then
				c.life -= rate * dt
				if c.life <= 0 then
					melt(player, c)
					continue
				end
			end
			local frac = math.clamp(c.life / c.lifeMax, 0, 1)
			if c.part and math.abs(frac - c.shownFrac) > 0.01 then
				c.shownFrac = frac
				c.part:SetAttribute("LifeFrac", frac) -- clients shrink, crack and flash the cube from this
			end
		end
	end
end

function CarryService.Init()
	folder = WorldService.petsFolder("Cubes")
	groundFolder = WorldService.petsFolder("GroundCubes")
end

function CarryService.Start()
	-- bought Super Freeze cubes that weren't banked yet come back onto your back
	DataService.Loaded:Connect(function(player: Player, data: any)
		for _, r in data.superCubes do
			local def = PetDefs.get(r.key)
			if def then
				CarryService.addCube(player, { key = r.key, zone = def.zone, pose = r.pose, mut = r.mut, superFrozen = true, superUsed = true, offered = true }, true)
			end
		end
	end)
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function()
			task.defer(layout, player)
		end)
	end)
	for _, player in Players:GetPlayers() do
		player.CharacterAdded:Connect(function()
			task.defer(layout, player)
		end)
	end
	Players.PlayerRemoving:Connect(function(player)
		-- free cubes aren't owned pets yet (nothing owned is lost); paid ones are already in the save
		-- except a cube whose freeze show was still playing: leaving mid-show keeps that pet (FreezeService)
		local list: { Cube } = table.clone(carrying[player] or {})
		for _, c in ground[player] or {} do
			table.insert(list, c) -- one still on the ground goes the same way (it isn't yours until you bank it)
		end
		ground[player] = nil
		for _, c in list do
			if leaveHandler and os.clock() < c.graceUntil and not c.superFrozen then
				local ok, err = pcall(leaveHandler, player, c)
				if not ok then
					warn("[CarryService] keeping a mid-show pet failed:", err)
				end
			end
			if c.part then
				c.part:Destroy()
			end
		end
		carrying[player] = nil
	end)
	task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(Config.melt.tickSeconds)
			local now = os.clock()
			tick(now - last)
			last = now
		end
	end)
end

return CarryService
