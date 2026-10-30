--!strict
-- CarryService: owns the cubes each player carries. Melt ticks on the SERVER (heat x shade/sun,
-- nothing melts during the Big Chill or in a Super Freeze cube). A melted cube becomes a dazed pet
-- (only you can zap it back, free, always) and, for Rare and up, a Super Freeze offer at most once per run.
-- The cube Part is welded to the character so everyone sees it; clients draw the pet inside and the melt.

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

export type CubeInfo = { key: string, zone: number, pose: string, mut: string?, superFrozen: boolean, superUsed: boolean }
export type Cube = CubeInfo & { uid: string, life: number, lifeMax: number, since: number, part: Part? , shownFrac: number }

local CarryService = {}
local carrying: { [Player]: { Cube } } = {}
local nextUid = 1
local folder: Folder

local BACK_SCALE = 0.62 -- carried cubes are smaller so they never hide the player's head

function CarryService.count(player: Player): number
	local list = carrying[player]
	return if list then #list else 0
end

function CarryService.capacity(player: Player): number
	local data = DataService.get(player)
	return if data then data.upgrades.backpack else 1
end

local function cubeSize(player: Player, def: PetDefs.PetDef): number
	local data = DataService.get(player)
	local ray = if data then data.upgrades.ray else 1
	return PetDefs.cubeSize[def.size] * (1 + Config.upgrades.ray.cubeSizeBonus * (ray - 1)) * BACK_SCALE
end

-- weld the stack behind the character (re-run after respawn or any change)
local function layout(player: Player)
	local list = carrying[player]
	local hrp = PlayerTracker.rootPart(player)
	if not list or not hrp then
		return
	end
	local y = -0.6
	for _, c in list do
		local part = c.part
		if part then
			local s = part.Size.Y
			for _, w in part:GetChildren() do
				if w:IsA("Weld") then
					w:Destroy()
				end
			end
			part.CFrame = hrp.CFrame * CFrame.new(0, y + s / 2, 1.2 + s / 2)
			local weld = Instance.new("Weld")
			weld.Part0 = hrp
			weld.Part1 = part
			weld.C0 = CFrame.new(0, y + s / 2, 1.2 + s / 2)
			weld.Parent = part
			part.Parent = folder
			y += s + 0.15
		end
	end
end

local function makePart(player: Player, c: Cube): Part
	local def = PetDefs.get(c.key) :: PetDefs.PetDef
	local s = cubeSize(player, def)
	local p = Instance.new("Part")
	p.Name = "Cube"
	p.Size = Vector3.new(s, s, s)
	p.Material = Enum.Material.Glass
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

local function changed(player: Player)
	PlayerTracker.setCarrying(player, CarryService.count(player))
	layout(player)
end

function CarryService.addCube(player: Player, info: CubeInfo)
	local def = PetDefs.get(info.key)
	local data = DataService.get(player)
	if not def or not data then
		return
	end
	local lifeMax = Config.tier(def.tier).cubeLife * (1 + Config.upgrades.ray.lifeBonus * (data.upgrades.ray - 1))
	local c: Cube = {
		key = info.key, zone = info.zone, pose = info.pose, mut = info.mut, superFrozen = info.superFrozen, superUsed = info.superUsed,
		uid = "c" .. nextUid, life = lifeMax, lifeMax = lifeMax, since = os.clock(), part = nil, shownFrac = 1,
	}
	nextUid += 1
	c.part = makePart(player, c)
	local list = carrying[player] or {}
	table.insert(list, c)
	carrying[player] = list
	changed(player)
end

-- banking takes every cube (PenService decides what happens to them)
function CarryService.takeAll(player: Player): { Cube }
	local list: { Cube } = carrying[player] or {}
	carrying[player] = {}
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
	local at = Vector3.new(pos.X + math.cos(angle) * 3, 0, pos.Z + math.sin(angle) * 3)
	local offer = Config.tier(def.tier).rank >= Config.tier(Config.monetization.superFreeze.minTier).rank and not c.superUsed
	WildPetSpawner.spawnDazed({ key = c.key, zone = c.zone, pose = c.pose, mut = c.mut, superUsed = c.superUsed }, at, player, offer)
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

-- called from ProcessReceipt: turn this player's dazed offer pet into a never-melting cube
function CarryService.superFreezeOffer(player: Player): boolean
	local WildPets = workspace:FindFirstChild("WildPets")
	if not WildPets then
		return false
	end
	for _, root in WildPets:GetChildren() do
		if root:GetAttribute("OfferUserId") == player.UserId then
			local pet = WildPetSpawner.get(root:GetAttribute("PetId") :: string)
			if pet and CarryService.count(player) < CarryService.capacity(player) then
				local info = { key = pet.def.key, zone = pet.zone, pose = pet.pose or "idle", mut = pet.mut, superFrozen = true, superUsed = true }
				WildPetSpawner.remove(pet.id)
				CarryService.addCube(player, info)
				return true
			end
		end
	end
	return false
end

local function tick(dt: number)
	local chill = EventService.isChill()
	for player, list in carrying do
		if #list == 0 then
			continue
		end
		local pos = PlayerTracker.position(player)
		if not pos then
			continue
		end
		local rate = WorldRules.meltRate(pos)
		for _, c in table.clone(list) do
			if not c.superFrozen and not chill then
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
end

function CarryService.Start()
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
		-- cubes aren't owned pets yet (nothing owned is lost); just clean up
		local list: { Cube } = carrying[player] or {}
		for _, c in list do
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
