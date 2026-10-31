--!strict
-- WorldService: owns the map's game objects (plots, river, bridges, gate, signs, boards, gift box,
-- shade/sun areas, lighting). If Workspace.Map is missing it builds a blockout from Config so the
-- game runs in an empty place; the real art replaces the blockout parts later (same names and tags).

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Theme = require(ReplicatedStorage.Shared.Theme)
local WorldRules = require(ReplicatedStorage.Shared.WorldRules)
local Scenery = require(ReplicatedStorage.Shared.Scenery)
local MapArt = require(script.Parent.MapArt)

local WorldService = {}

local map: Folder
local plotOwner: { [number]: Player } = {}
local playerPlot: { [Player]: number } = {}
local iceBridge: BasePart
local forestOpen: { [Player]: boolean } = {}
WorldService.zoneSigns = {} :: { [number]: BasePart }
WorldService.boards = {} :: { BasePart }
WorldService.giftPrompt = nil :: ProximityPrompt?
WorldService.bridgePrompts = {} :: { ProximityPrompt } -- one on each bank
WorldService.gateSign = nil :: BasePart?
WorldService.gatePrompt = nil :: ProximityPrompt? -- hold to pay the gate's coins (PenService)

local GATE_GROUP, OPEN_GROUP = "ForestGate", "ForestOpen"

local function part(name: string, size: Vector3, cf: CFrame, color: Color3, parent: Instance, props: { [string]: any }?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	if props then
		for k, v in props do
			(p :: any)[k] = v
		end
	end
	p.Parent = parent
	return p
end

local function prompt(parent: Instance, action: string, object: string, hold: number): ProximityPrompt
	local a = Instance.new("Attachment")
	a.Position = Vector3.new(0, 3, 0)
	a.Parent = parent
	local pp = Instance.new("ProximityPrompt")
	pp.ActionText = action
	pp.ObjectText = object
	pp.HoldDuration = hold
	pp.MaxActivationDistance = Config.player.freezeRange
	pp.RequiresLineOfSight = false
	pp.Style = Enum.ProximityPromptStyle.Custom -- styled by the client Prompts controller
	pp.Parent = a
	return pp
end

local function surfaceText(p: BasePart, face: Enum.NormalId, text: string, bg: Color3)
	local sg = Instance.new("SurfaceGui")
	sg.Face = face
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 40
	sg.Parent = p
	local t = Instance.new("TextLabel")
	t.Name = "Text"
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundColor3 = bg
	t.TextColor3 = Theme.white
	t.TextScaled = true
	t.Font = Theme.font
	t.Text = text
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = Theme.ink
	stroke.Parent = t
	t.Parent = sg
end

local function buildBlockout()
	map = Instance.new("Folder")
	map.Name = "Map"
	local W = Config.world
	local b = W.bounds
	local width = b.xMax - b.xMin + 40
	-- ground: hub plaza, snowy meadow, grassy forest (the river is a gap between them)
	local A, ART = Theme.art, Config.art
	part("HubGround", Vector3.new(width, 2, 70), CFrame.new(0, -1, -35), A.plaza, map, { Material = Enum.Material.CeramicTiles })
	local meadowLen = W.river.zMin - (-2)
	part("MeadowGround", Vector3.new(width, 2, meadowLen), CFrame.new(0, -1, -2 + meadowLen / 2), A.snowA, map, { Material = Enum.Material.Snow })
	local forestLen = b.zMax - W.river.zMax + 10
	part("ForestGround", Vector3.new(width, 2, forestLen), CFrame.new(0, -1, W.river.zMax + forestLen / 2), A.grassA, map, { Material = Enum.Material.Grass })
	part("Path", Vector3.new(18, 0.2, meadowLen), CFrame.new(0, 0.05, -2 + meadowLen / 2), A.pathSnow, map, { Material = Enum.Material.Snow })
	part("ForestPath", Vector3.new(17, 0.2, forestLen - 10), CFrame.new(0, 0.05, W.river.zMax + 1 + (forestLen - 10) / 2), A.dirt, map, { Material = Enum.Material.Ground })
	-- river: a water surface just below the banks; step in and you sink onto the catcher, which puts
	-- you gently back on the near bank (prototype: the river isn't walkable)
	local rz = (W.river.zMin + W.river.zMax) / 2
	local rLen = W.river.zMax - W.river.zMin
	part("RiverBed", Vector3.new(width, 1, rLen), CFrame.new(0, ART.bedY - 0.5, rz), A.riverBed, map, { Material = Enum.Material.Pebble })
	part("RiverWater", Vector3.new(width, 0.2, rLen), CFrame.new(0, ART.waterY, rz), A.water, map,
		{ Material = Enum.Material.Glass, Transparency = 0.25, Reflectance = 0.1, CanCollide = false, CanQuery = false, CastShadow = false })
	local catcher = part("RiverCatcher", Vector3.new(width, 1, rLen + 2), CFrame.new(0, ART.catcherY, rz), A.water, map, { Transparency = 1, CanCollide = false })
	catcher.Touched:Connect(function(hit)
		local character = hit.Parent
		local hrp = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if hrp and Players:GetPlayerFromCharacter(character) then
			local back = if hrp.Position.Z > rz then W.river.zMax + 4 else W.river.zMin - 4
			hrp.CFrame = CFrame.new(hrp.Position.X, 4, back) -- falling is gentle: back on solid ground, nothing lost
		end
	end)
	-- main bridge (always there) and the ice bridge (frozen by players)
	local mb = W.mainBridge
	part("MainBridge", Vector3.new(mb.xMax - mb.xMin, 1, W.river.zMax - W.river.zMin + 6), CFrame.new((mb.xMin + mb.xMax) / 2, -0.3, rz), A.plank, map, { Material = Enum.Material.WoodPlanks })
	local ib = W.iceBridgeSpot
	iceBridge = part("IceBridge", Vector3.new(ib.xMax - ib.xMin, 1, W.river.zMax - W.river.zMin + 6), CFrame.new((ib.xMin + ib.xMax) / 2, -0.5, rz), Theme.ice, map,
		{ Material = Enum.Material.Ice, Transparency = 1, CanCollide = false })
	-- a glowing freeze spot on each bank; both prompts make the same bridge
	WorldService.bridgePrompts = {}
	for i, spotPos in WorldRules.iceBridgeSpots() do
		local spot = part("IceBridgeSpot" .. i, Vector3.new(0.3, 6, 6), CFrame.new(spotPos.X, 0.15, spotPos.Z) * CFrame.Angles(0, 0, math.rad(90)), Theme.ice, map, { Material = Enum.Material.Neon, Transparency = 0.55, Shape = Enum.PartType.Cylinder, CanCollide = false }) -- see-through Neon: solid Neon blooms into a white blob
		table.insert(WorldService.bridgePrompts, prompt(spot, "Freeze", "Ice bridge", Config.player.freezeHold))
	end
	-- the Forest gate: a fence line; the opening is collidable only for players who haven't unlocked it
	local g = W.gate
	-- the wall that blocks the opening is invisible: MapArt's ice bars show it (hidden on clients that opened it)
	local gate = part("ForestGate", Vector3.new(g.xMax - g.xMin, 10, 1.5), CFrame.new((g.xMin + g.xMax) / 2, 5, g.z), Theme.ice, map, { Transparency = 1 })
	gate.CollisionGroup = GATE_GROUP
	local gz = (Config.zone(2) :: Config.Zone).gateCoins
	local post = part("GatePromptSpot", Vector3.new(1, 1, 1), CFrame.new((g.xMin + g.xMax) / 2, 0.5, g.z - Config.gatePromptOffset), Theme.ice, map, { Transparency = 1, CanCollide = false, CanQuery = false })
	WorldService.gatePrompt = prompt(post, "Open", `Pine Forest: {gz} coins`, Config.player.interactHold)
	-- the fence's collision (MapArt draws the posts and rails)
	part("FenceL", Vector3.new(g.xMin - b.xMin, 4, 1), CFrame.new((b.xMin + g.xMin) / 2, 2, g.z), Theme.wood, map, { Transparency = 1 })
	part("FenceR", Vector3.new(b.xMax - g.xMax, 4, 1), CFrame.new((g.xMax + b.xMax) / 2, 2, g.z), Theme.wood, map, { Transparency = 1 })
	local sign = part("GateSign", Vector3.new(16, 3.4, 0.5), CFrame.new(0, 12, g.z - 1), Theme.go, map) -- text toward the meadow
	surfaceText(sign, Enum.NormalId.Front, "PINE FOREST", Theme.go)
	WorldService.gateSign = sign
	-- invisible walls at the map edge (edges look natural in the real art: hedges, cliffs)
	for _, x in { b.xMin - 2, b.xMax + 2 } do
		part("EdgeWall", Vector3.new(2, 40, b.zMax - b.zMin + 40), CFrame.new(x, 20, (b.zMin + b.zMax) / 2), Theme.snow, map, { Transparency = 1 })
	end
	part("EdgeWallN", Vector3.new(width, 40, 2), CFrame.new(0, 20, b.zMin - 2), Theme.snow, map, { Transparency = 1 })
	part("EdgeWallS", Vector3.new(width, 40, 2), CFrame.new(0, 20, b.zMax + 2), Theme.snow, map, { Transparency = 1 })
	-- pen plots
	for i, pl in W.plots do
		local pen = part("Plot" .. i, W.penSize, CFrame.new(pl.x, 0.15, pl.z), A.straw, map, { Size = Vector3.new(W.penSize.X, 0.3, W.penSize.Z), Material = Enum.Material.Grass })
		pen:SetAttribute("PlotIndex", i)
		CollectionService:AddTag(pen, "Plot")
		-- on the back edge, facing the path: at the front it stood between the camera and the spawn
		local signPart = part("PlotSign", Vector3.new(10, 2.4, 0.4), CFrame.new(pl.x, 4.5, pl.z - W.penSize.Z / 2) * CFrame.Angles(0, math.pi, 0), Theme.tiles.shop, pen)
		surfaceText(signPart, Enum.NormalId.Front, "Free pen", Theme.tiles.shop)
	end
	local spawnLoc = Instance.new("SpawnLocation")
	spawnLoc.Size = Vector3.new(8, 1, 8)
	spawnLoc.CFrame = CFrame.new(W.spawn.X, 0.5, W.spawn.Z) * CFrame.Angles(0, math.pi, 0) -- you start facing the meadow, the pens behind you (prototype camera)
	spawnLoc.Anchored = true
	spawnLoc.Color = Theme.ice
	spawnLoc.Transparency = 1 -- MapArt draws the round spawn pad
	spawnLoc.Neutral = true
	spawnLoc.Parent = map
	-- gift box
	-- invisible: MapArt draws the ribboned box, the client bobs it and shows its label
	local gift = part("GiftBox", Vector3.new(3, 3, 3), CFrame.new(W.giftBox.X, 1.5, W.giftBox.Z), Theme.gift, map, { Transparency = 1 })
	WorldService.giftPrompt = prompt(gift, "Open", "Daily gift", Config.player.interactHold)
	-- leaderboard boards, turned to face the spawn
	for i, pos in W.boards do
		local look = CFrame.lookAt(Vector3.new(pos.X, 10, pos.Z), Vector3.new(W.spawn.X, 10, W.spawn.Z))
		local board = part("Leaderboard" .. i, Vector3.new(14, 18, 1), look, Theme.board, map)
		WorldService.boards[i] = board
	end
	-- zone signs (odds drawn by WildPetSpawner)
	for _, z in W.zones do
		-- its Front (the text) faces the hub, where players come from
		local s = part("ZoneSign" .. z.id, Vector3.new(11, 9, 0.5), CFrame.new(z.signPos.X, 6, z.signPos.Z), Theme.art.rail, map, { Material = Enum.Material.Wood })
		WorldService.zoneSigns[z.id] = s
	end
	-- shade (under each tree) and sun patches: the prototype's exact list (Shared/Scenery), so the
	-- spots that melt slower or faster are where the artifact has them; MapArt draws the trees
	local list = Scenery.get()
	for _, t in list.trees do
		local shade = part("Shade", Vector3.new(0.2, t.r * 2, t.r * 2), CFrame.new(t.x, 0.08, t.z) * CFrame.Angles(0, 0, math.rad(90)), A.shade, map,
			{ Shape = Enum.PartType.Cylinder, Transparency = 0.82, CanCollide = false, CanQuery = false, CastShadow = false })
		CollectionService:AddTag(shade, "ShadeZone")
	end
	for _, s in list.sun do
		local patch = part("SunPatch", Vector3.new(0.2, s.r * 2, s.r * 2), CFrame.new(s.x, 0.07, s.z) * CFrame.Angles(0, 0, math.rad(90)), A.sunGlow, map,
			{ Shape = Enum.PartType.Cylinder, Transparency = 0.45, CanCollide = false, CanQuery = false, CastShadow = false })
		CollectionService:AddTag(patch, "SunZone")
	end
	MapArt.build(map)
	map.Parent = workspace
end

local function findExisting(): boolean
	local existing = workspace:FindFirstChild("Map")
	if not existing then
		return false
	end
	map = existing :: Folder
	iceBridge = map:FindFirstChild("IceBridge", true) :: BasePart
	WorldService.bridgePrompts = {}
	for i = 1, 2 do
		local spot = map:FindFirstChild("IceBridgeSpot" .. i, true)
		local pp = spot and spot:FindFirstChildWhichIsA("ProximityPrompt", true)
		if pp then
			table.insert(WorldService.bridgePrompts, pp)
		end
	end
	local gift = map:FindFirstChild("GiftBox", true)
	WorldService.giftPrompt = gift and gift:FindFirstChildWhichIsA("ProximityPrompt", true)
	WorldService.gateSign = map:FindFirstChild("GateSign", true) :: BasePart?
	local gp = map:FindFirstChild("GatePromptSpot", true)
	WorldService.gatePrompt = gp and gp:FindFirstChildWhichIsA("ProximityPrompt", true)
	for i = 1, #Config.world.boards do
		WorldService.boards[i] = map:FindFirstChild("Leaderboard" .. i, true) :: BasePart
	end
	for _, z in Config.world.zones do
		WorldService.zoneSigns[z.id] = map:FindFirstChild("ZoneSign" .. z.id, true) :: BasePart
	end
	return true
end

local function applyLighting()
	local L = Config.lighting
	Lighting.ClockTime = L.clockTime
	Lighting.Brightness = L.brightness
	local atmo = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere")
	atmo.Density = L.atmosphereDensity
	atmo.Glare = 0
	atmo.Color = Theme.ice
	atmo.Parent = Lighting
	local cc = Lighting:FindFirstChildOfClass("ColorCorrectionEffect") or Instance.new("ColorCorrectionEffect")
	cc.Saturation = L.saturation
	cc.Parent = Lighting
end

local function setCharacterGroup(player: Player)
	local character = player.Character
	if not character then
		return
	end
	local group = if forestOpen[player] then OPEN_GROUP else "Default"
	for _, d in character:GetDescendants() do
		if d:IsA("BasePart") then
			d.CollisionGroup = group
		end
	end
end

function WorldService.Init()
	PhysicsService:RegisterCollisionGroup(GATE_GROUP)
	PhysicsService:RegisterCollisionGroup(OPEN_GROUP)
	PhysicsService:CollisionGroupSetCollidable(GATE_GROUP, OPEN_GROUP, false)
	if not findExisting() then
		buildBlockout()
	end
	WorldRules.refreshAreas()
	applyLighting()
end

function WorldService.Start()
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function()
			task.defer(setCharacterGroup, player)
		end)
	end)
	Players.PlayerRemoving:Connect(function(player)
		local i = playerPlot[player]
		if i then
			plotOwner[i] = nil
			local plot = map:FindFirstChild("Plot" .. i)
			local sign = plot and plot:FindFirstChild("PlotSign")
			local label = sign and sign:FindFirstChild("Text", true) :: TextLabel?
			if label then
				label.Text = "Free pen"
			end
		end
		playerPlot[player] = nil
		forestOpen[player] = nil
	end)
end

-- one pen per player; nil when the server's pens are all taken (MaxPlayers should match #plots)
function WorldService.assignPlot(player: Player): number?
	if playerPlot[player] then
		return playerPlot[player]
	end
	for i = 1, #Config.world.plots do
		if not plotOwner[i] then
			plotOwner[i] = player
			playerPlot[player] = i
			local plot = map:FindFirstChild("Plot" .. i)
			local sign = plot and plot:FindFirstChild("PlotSign")
			local label = sign and sign:FindFirstChild("Text", true) :: TextLabel?
			if label then
				label.Text = player.DisplayName .. "'s pen" -- Roblox display names only
			end
			return i
		end
	end
	return nil
end

function WorldService.plotOf(player: Player): number?
	return playerPlot[player]
end

function WorldService.setForestOpen(player: Player, open: boolean)
	forestOpen[player] = open
	setCharacterGroup(player)
end

function WorldService.setIceBridge(active: boolean)
	iceBridge.Transparency = if active then 0.25 else 1
	iceBridge.CanCollide = active
end

function WorldService.petsFolder(name: string): Folder
	local f = workspace:FindFirstChild(name)
	if not f then
		f = Instance.new("Folder")
		f.Name = name
		f.Parent = workspace
	end
	return f :: Folder
end

return WorldService
