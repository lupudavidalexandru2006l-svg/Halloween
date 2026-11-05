--!strict
-- WorldService: owns the map's game objects (Round 4 phase 2): the hub (spawn plaza, the row of
-- pans with their doors, signs, temperature gauges and Pan Upgrades stands, the booths, gift box,
-- leaderboards), the tunnel (one section per open island in Config.world.islands: floor, walls,
-- zone sign, the gate in front of it) and its "New island coming soon" end cap, the shade/sun areas,
-- the fall catcher and the lighting. Walls are invisible colliders; MapArt draws the look.
-- A Workspace.Map saved in the place is used as it is (so it shows in Edit mode); one saved by an
-- older build (MapVersion attribute) is thrown away and rebuilt.

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Theme = require(ReplicatedStorage.Shared.Theme)
local WorldRules = require(ReplicatedStorage.Shared.WorldRules)
local Scenery = require(ReplicatedStorage.Shared.Scenery)
local WorldText = require(ReplicatedStorage.Shared.WorldText)
local MapArt = require(script.Parent.MapArt)

local WorldService = {}

local map: Folder
local plotOwner: { [number]: Player } = {}
local playerPlot: { [Player]: number } = {}
WorldService.gateSigns = {} :: { [number]: BasePart }
WorldService.gatePrompts = {} :: { [number]: ProximityPrompt } -- hold to pay a gate's coins (PenService); zone id -> prompt
WorldService.boards = {} :: { BasePart }
WorldService.giftPrompt = nil :: ProximityPrompt?

-- Round 4 phase 6: the gates are plain solid walls. Each client turns off the ones it has opened (and
-- any gate it stands beyond, so nobody is ever shut in); PlayerTracker puts anyone found past a gate
-- they haven't opened back in front of it. A player's reach (islands 1..reach open) is the Reach attribute.

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

-- an invisible wall (MapArt draws what you see)
local function collider(name: string, size: Vector3, cf: CFrame, parent: Instance): Part
	return part(name, size, cf, Theme.snow, parent, { Transparency = 1, CastShadow = false })
end

local function prompt(parent: Instance, action: string, object: string, hold: number, at: Vector3?): ProximityPrompt
	local a = Instance.new("Attachment")
	a.Position = at or Vector3.new(0, 3, 0)
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

local function surfaceText(p: BasePart, face: Enum.NormalId, text: string, bg: Color3, maxStuds: number?)
	local sg = WorldText.surface(p, "SurfaceGui", face)
	sg.Parent = p
	local t = Instance.new("TextLabel")
	t.Name = "Text"
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundColor3 = bg
	t.TextColor3 = Theme.white
	t.Text = text
	t.Parent = sg
	WorldText.fitSign(sg, t, WorldText.px(maxStuds or Config.worldText.gate)) -- big signs (booths, gates) use the gate size
end

-- a saved map keeps the signs it was built with: bring their text up to the current WorldText look
local function restyleSign(p: Instance?, maxStuds: number)
	local sg = p and p:FindFirstChildOfClass("SurfaceGui")
	local t = sg and sg:FindFirstChild("Text")
	if sg and t and t:IsA("TextLabel") then
		WorldText.fitSign(sg, t, WorldText.px(maxStuds))
	end
end

-- a sign whose Front face (its text) looks toward `toward`, where players come from
local function signFacing(name: string, size: Vector3, at: Vector3, toward: Vector3, color: Color3, parent: Instance): Part
	local look = Vector3.new(toward.X, at.Y, toward.Z)
	return part(name, size, CFrame.lookAt(at, look), color, parent)
end

-- falling is gentle: anyone who drops below the map lands back on the path nearby, nothing lost
local function hookCatcher(catcher: BasePart)
	catcher.Touched:Connect(function(hit)
		local character = hit.Parent
		local hrp = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if hrp and Players:GetPlayerFromCharacter(character) then
			local p = hrp.Position
			if p.Z < Config.world.hubZMax then
				hrp.CFrame = CFrame.new(Config.world.spawn + Vector3.new(0, 2, 0)) * CFrame.Angles(0, math.pi, 0)
			else
				local z = math.clamp(p.Z, Config.world.hubZMax + 4, Config.world.tunnelEnd - 8)
				hrp.CFrame = CFrame.new(0, 5, z) * CFrame.Angles(0, math.pi, 0)
			end
		end
	end)
end

-- ---------- the hub ----------
local function buildHub()
	local W = Config.world
	local H, P, T = W.hub, W.pans, W.tunnel
	local HA = Theme.hubArt
	local width, depth = H.xMax - H.xMin, W.hubZMax - H.zMin
	local cx, cz = (H.xMin + H.xMax) / 2, (H.zMin + W.hubZMax) / 2
	part("HubGround", Vector3.new(width + 8, 2, depth + 8), CFrame.new(cx, -1, cz - 2), HA.plaza, map, { Material = Enum.Material.CeramicTiles })
	-- the hub's walls; the south wall leaves the tunnel mouth open
	local hc, half = H.colliderHeight, T.width / 2
	collider("HubWallW", Vector3.new(2, hc, depth + 4), CFrame.new(H.xMin - 1, hc / 2, cz), map)
	collider("HubWallE", Vector3.new(2, hc, depth + 4), CFrame.new(H.xMax + 1, hc / 2, cz), map)
	collider("HubWallN", Vector3.new(width + 4, hc, 2), CFrame.new(cx, hc / 2, H.zMin - 1), map)
	local sw = -half - H.xMin
	collider("HubWallSW", Vector3.new(sw, hc, 2), CFrame.new(H.xMin + sw / 2, hc / 2, W.hubZMax + 1), map)
	collider("HubWallSE", Vector3.new(sw, hc, 2), CFrame.new(H.xMax - sw / 2, hc / 2, W.hubZMax + 1), map)
	-- the pans: a thick soil bed per lane, walls on every side, a door at the front only its owner
	-- can walk through (the owner's client turns it off for itself; PlayerTracker puts anyone else back)
	local back = H.zMin
	for i, pl in W.plots do
		local x0, x1 = pl.x - P.width / 2, pl.x + P.width / 2
		local pan = part("Plot" .. i, Vector3.new(P.width, P.soilHeight, P.length), CFrame.new(pl.x, P.soilHeight / 2, pl.z), HA.soil, map, { Material = Enum.Material.Ground })
		pan:SetAttribute("PlotIndex", i)
		CollectionService:AddTag(pan, "Plot")
		local ph = P.wallHeight
		collider("PanWallL", Vector3.new(1, ph, P.length), CFrame.new(x0 - 0.5, ph / 2, pl.z), pan)
		collider("PanWallR", Vector3.new(1, ph, P.length), CFrame.new(x1 + 0.5, ph / 2, pl.z), pan)
		collider("PanWallB", Vector3.new(P.width + 2, ph, 1), CFrame.new(pl.x, ph / 2, pl.z - P.length / 2 - 0.5), pan)
		local side = (P.width - P.doorWidth) / 2
		collider("PanWallFL", Vector3.new(side, ph, 1), CFrame.new(x0 + side / 2, ph / 2, P.frontZ + 0.5), pan)
		collider("PanWallFR", Vector3.new(side, ph, 1), CFrame.new(x1 - side / 2, ph / 2, P.frontZ + 0.5), pan)
		local door = collider("PanDoor", Vector3.new(P.doorWidth, ph, 1), CFrame.new(pl.x, ph / 2, P.frontZ + 0.5), pan)
		door:SetAttribute("PlotIndex", i)
		-- the temperature gauge right of the door, facing the plaza (the name sign over the door was
		-- removed, owner 2026-11-03)
		local front = Vector3.new(pl.x, 0, P.frontZ + 40)
		local gauge = signFacing("PanGauge", Vector3.new(2.4, 3.2, 0.4), Vector3.new(pl.x + P.gaugeOffset, 4.2, P.frontZ + 1.2), front + Vector3.new(P.gaugeOffset, 4.2, 0), HA.gaugeFrame, pan)
		gauge:SetAttribute("PlotIndex", i)
		-- Pan Upgrades: a small stand left of the door (its feature comes in phase 5; the Shop for now)
		local stand = collider("PanUpgrade", Vector3.new(3, 3, 2), CFrame.new(pl.x + P.boothOffset, 1.5, P.frontZ + 2.5), pan)
		stand.CanCollide = true
		local pp = prompt(stand, "Upgrade", "Pan Upgrades", Config.player.openHold, Vector3.new(0, 2, 1))
		pp:SetAttribute("Booth", "pan")
		pp:SetAttribute("Action", W.panUpgradeAction)
		pp:SetAttribute("PlotIndex", i)
		-- fill the gaps between lanes (and at both ends of the row) so nobody walks into a dead end
		if i < #W.plots then
			local gx0, gx1 = x1 + 1, W.plots[i + 1].x - P.width / 2 - 1
			if gx1 > gx0 then
				collider("PanGap", Vector3.new(gx1 - gx0, ph, P.frontZ - back + 1), CFrame.new((gx0 + gx1) / 2, ph / 2, (back + P.frontZ + 1) / 2), map)
			end
		end
	end
	local first, last = W.plots[1], W.plots[#W.plots]
	for _, ends in { { H.xMin, first.x - P.width / 2 - 1 }, { last.x + P.width / 2 + 1, H.xMax } } do
		if ends[2] > ends[1] then
			collider("PanEnd", Vector3.new(ends[2] - ends[1], P.wallHeight, P.frontZ - back + 1), CFrame.new((ends[1] + ends[2]) / 2, P.wallHeight / 2, (back + P.frontZ + 1) / 2), map)
		end
	end
	-- the spawn: you start facing down the tunnel, the pans behind you
	local spawnLoc = Instance.new("SpawnLocation")
	spawnLoc.Size = Vector3.new(W.spawnPadRadius * 2, 1, W.spawnPadRadius * 2)
	spawnLoc.CFrame = CFrame.new(W.spawn.X, 0.5, W.spawn.Z) * CFrame.Angles(0, math.pi, 0)
	spawnLoc.Anchored = true
	spawnLoc.Color = Theme.ice
	spawnLoc.Transparency = 1 -- MapArt draws the round spawn pad
	spawnLoc.Neutral = true
	spawnLoc.Duration = 0
	spawnLoc.Parent = map
	-- the booths by the tunnel mouth (features come later; MapArt draws the stall, awning and sign)
	for _, b in W.booths do
		local counter = collider("Booth_" .. b.id, Vector3.new(10, 4, 5), CFrame.new(b.pos.X, 2, b.pos.Z), map)
		local pp = prompt(counter, "Open", b.label, Config.player.openHold, Vector3.new(0, 1, -3))
		pp:SetAttribute("Booth", b.id)
		pp:SetAttribute("Action", b.action)
		local BS = W.boothSign
		local sign = signFacing("BoothSign", Vector3.new(BS.w, BS.h, 0.4), Vector3.new(b.pos.X, BS.y, b.pos.Z + BS.z), Vector3.new(b.pos.X, BS.y, b.pos.Z - 40), Theme.booths[b.id] or Theme.info, counter)
		surfaceText(sign, Enum.NormalId.Front, string.upper(b.label), Theme.booths[b.id] or Theme.info, BS.text)
	end
	-- gift box (invisible: MapArt draws the ribboned box, the client bobs it and shows its label)
	local gift = part("GiftBox", Vector3.new(3, 3, 3), CFrame.new(W.giftBox.X, 1.5, W.giftBox.Z), Theme.gift, map, { Transparency = 1 })
	WorldService.giftPrompt = prompt(gift, "Open", "Daily gift", Config.player.openHold)
	-- leaderboards on the side walls, facing into the plaza
	for i, pos in W.boards do
		local at = Vector3.new(pos.X, 10, pos.Z)
		WorldService.boards[i] = part("Leaderboard" .. i, Vector3.new(14, 18, 1), CFrame.lookAt(at, Vector3.new(0, 10, pos.Z)), Theme.board, map)
	end
end

-- ---------- the tunnel: one section per open island, a gate in front of each after the first ----------
local function buildTunnel()
	local W = Config.world
	local T, G = W.tunnel, W.gate
	local half, hc = T.width / 2, T.colliderHeight
	local open = 0
	for _, isl in W.islands do
		if not isl.open then
			continue
		end
		open += 1
		local zone = W.zones[open]
		local look = Theme.islands[isl.theme] or Theme.islands.meadow
		local len, mid = zone.zMax - zone.zMin, (zone.zMin + zone.zMax) / 2
		local mats = Theme.islandMats[isl.theme]
		local floorMat = if mats then mats.floor else Enum.Material.Grass
		local sec = Instance.new("Folder")
		sec.Name = "Section" .. zone.id
		sec:SetAttribute("Zone", zone.id)
		sec.Parent = map
		part("Floor", Vector3.new(T.width + T.wallThick * 2, 2, len), CFrame.new(0, -1, mid), look.floor, sec, { Material = floorMat })
		part("Path", Vector3.new(T.pathWidth, 0.2, len), CFrame.new(0, 0.05, mid), look.path, sec,
			{ Material = if mats then mats.path else Enum.Material.Ground, CanCollide = false })
		local wx = half + T.wallThick / 2
		collider("WallL", Vector3.new(T.wallThick, hc, len), CFrame.new(-wx, hc / 2, mid), sec)
		collider("WallR", Vector3.new(T.wallThick, hc, len), CFrame.new(wx, hc / 2, mid), sec)
		local gz = WorldRules.gateZ(zone.id)
		if gz then
			-- the gate: invisible wall to wall, solid only for players who haven't opened it (MapArt
			-- draws the glowing arch and ice bars; each client hides the bars once it's open)
			local gate = collider("Gate" .. zone.id, Vector3.new(T.width, G.height, G.depth), CFrame.new(0, G.height / 2, gz), sec)
			gate:SetAttribute("GateZone", zone.id)
			local spot = part("GatePromptSpot" .. zone.id, Vector3.new(1, 1, 1), CFrame.new(0, 0.5, gz - Config.gatePromptOffset), Theme.ice, sec, { Transparency = 1, CanCollide = false, CanQuery = false })
			local cost = if zone.gateRebirth > 0 then `Rebirth {zone.gateRebirth} + {zone.gateCoins} coins` else `{zone.gateCoins} coins`
			WorldService.gatePrompts[zone.id] = prompt(spot, "Open", if zone.ready then `{zone.name}: {cost}` else `{zone.name}: coming soon`, Config.player.interactHold)
			local sign = part("GateSign" .. zone.id, Vector3.new(22, 4.4, 0.5), CFrame.new(0, G.height + 3.4, gz - G.depth / 2 - 0.4), look.accent, sec) -- text toward the section before
			surfaceText(sign, Enum.NormalId.Front, if zone.ready then string.upper(zone.name) else "COMING SOON", look.accent)
			WorldService.gateSigns[zone.id] = sign
		end
	end
	-- the end cap after the last open island: a frosted gate you can't pass (yet)
	local E = W.endCap
	local cap = Instance.new("Folder")
	cap.Name = "EndCap"
	cap.Parent = map
	collider("EndCapWall", Vector3.new(T.width + T.wallThick * 2, hc, E.depth), CFrame.new(0, hc / 2, W.tunnelEnd + E.depth / 2), cap)
	local nextName = if W.nextIsland then W.nextIsland.name else "A new island"
	local sign = part("EndCapSign", Vector3.new(40, 5, 0.5), CFrame.new(0, E.height + 4.4, W.tunnelEnd - 0.6), Theme.info, cap)
	surfaceText(sign, Enum.NormalId.Front, "NEW ISLAND COMING SOON", Theme.info)
	local sub = part("EndCapName", Vector3.new(20, 2.6, 0.5), CFrame.new(0, E.height + 0.6, W.tunnelEnd - 0.6), Theme.board, cap)
	surfaceText(sub, Enum.NormalId.Front, nextName, Theme.board)
end

local function buildMap()
	map = Instance.new("Folder")
	map.Name = "Map"
	map:SetAttribute("MapVersion", Config.world.mapVersion)
	map:SetAttribute("TunnelEnd", Config.world.tunnelEnd) -- Round 4 phase 6: a new island in Config rebuilds a saved map
	workspace.Terrain:Clear() -- the old map's hills; the tunnel has walls instead
	buildHub()
	buildTunnel()
	local W = Config.world
	local catcher = part("FallCatcher", Vector3.new(W.hub.xMax - W.hub.xMin + 200, 2, W.tunnelEnd - W.hub.zMin + 200), CFrame.new(0, -40, (W.hub.zMin + W.tunnelEnd) / 2), Theme.snow, map,
		{ Transparency = 1, CanCollide = false, CanQuery = false })
	hookCatcher(catcher)
	-- shade (under each tree) and sun patches: Shared/Scenery's list, so the spots that melt slower or
	-- faster are exactly where MapArt draws the trees and glowing patches
	local A = Theme.art
	local list = Scenery.get()
	local areas = Instance.new("Folder")
	areas.Name = "Areas"
	areas.Parent = map
	for _, t in list.trees do
		local shade = part("Shade", Vector3.new(0.2, t.r * 2, t.r * 2), CFrame.new(t.x, 0.08, t.z) * CFrame.Angles(0, 0, math.rad(90)), A.shade, areas,
			{ Shape = Enum.PartType.Cylinder, Transparency = 0.82, CanCollide = false, CanQuery = false, CastShadow = false })
		CollectionService:AddTag(shade, "ShadeZone")
	end
	for _, s in list.sun do
		local patch = part("SunPatch", Vector3.new(0.2, s.r * 2, s.r * 2), CFrame.new(s.x, 0.07, s.z) * CFrame.Angles(0, 0, math.rad(90)), A.sunGlow, areas,
			{ Shape = Enum.PartType.Cylinder, Transparency = 0.45, CanCollide = false, CanQuery = false, CastShadow = false })
		CollectionService:AddTag(patch, "SunZone")
	end
	-- lava pools on the hot islands: cubes melt fastest here (Config.melt.lava); MapArt draws the glow
	for _, l in list.lava do
		local pool = part("LavaPool", Vector3.new(0.2, l.r * 2, l.r * 2), CFrame.new(l.x, 0.09, l.z) * CFrame.Angles(0, 0, math.rad(90)), Theme.islandArt.lava, areas,
			{ Shape = Enum.PartType.Cylinder, Transparency = 1, CanCollide = false, CanQuery = false, CastShadow = false })
		CollectionService:AddTag(pool, "LavaZone")
	end
	MapArt.build(map)
	map.Parent = workspace
end

local function findExisting(): boolean
	local existing = workspace:FindFirstChild("Map")
	if not existing then
		return false
	end
	if existing:GetAttribute("MapVersion") ~= Config.world.mapVersion or existing:GetAttribute("TunnelEnd") ~= Config.world.tunnelEnd then
		existing:Destroy() -- saved by an older build, or the islands changed in Config: rebuild it from Config
		return false
	end
	map = existing :: Folder
	-- a saved map skips buildMap, so hook its live parts here too
	local catcher = map:FindFirstChild("FallCatcher") :: BasePart?
	if catcher then
		hookCatcher(catcher)
	end
	local gift = map:FindFirstChild("GiftBox", true)
	WorldService.giftPrompt = gift and gift:FindFirstChildWhichIsA("ProximityPrompt", true)
	-- a saved map keeps the hold it was built with: menus and the gift open on a tap
	for _, d in map:GetDescendants() do
		if d:IsA("ProximityPrompt") and (d:GetAttribute("Booth") ~= nil or d == WorldService.giftPrompt) then
			d.HoldDuration = Config.player.openHold
		end
	end
	for i = 1, #Config.world.boards do
		WorldService.boards[i] = map:FindFirstChild("Leaderboard" .. i, true) :: BasePart
	end
	for _, z in Config.world.zones do
		local gs = map:FindFirstChild("GateSign" .. z.id, true)
		if gs then
			WorldService.gateSigns[z.id] = gs :: BasePart
		end
		local spot = map:FindFirstChild("GatePromptSpot" .. z.id, true)
		local pp = spot and spot:FindFirstChildWhichIsA("ProximityPrompt", true)
		if pp then
			WorldService.gatePrompts[z.id] = pp
		end
	end
	return true
end

-- Studio / tools: build the map into Workspace.Map now (used to save it into the place in Edit mode)
function WorldService.rebuild()
	local old = workspace:FindFirstChild("Map")
	if old then
		old:Destroy()
	end
	buildMap()
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

-- day <-> night: the loop's blend fades the sky, ambient light, haze and the map's lamps (Config.night)
local lamps: { [Light]: number } = {}
local shownBlend = -1
local function applyNight(blend: number, clock: number)
	Lighting.ClockTime = clock
	if math.abs(blend - shownBlend) < 0.005 then
		return
	end
	shownBlend = blend
	local D, N = Config.night.day, Config.night.night
	Lighting.Brightness = D.brightness + (N.brightness - D.brightness) * blend
	Lighting.Ambient = D.ambient:Lerp(N.ambient, blend)
	Lighting.OutdoorAmbient = D.outdoor:Lerp(N.outdoor, blend)
	local atmo = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmo then
		atmo.Color = Theme.ice:Lerp(N.atmo, blend) -- the day haze is the ice blue applyLighting sets
		atmo.Haze = D.haze + (N.haze - D.haze) * blend
	end
	local cc = Lighting:FindFirstChildOfClass("ColorCorrectionEffect")
	if cc then
		cc.TintColor = D.tint:Lerp(N.tint, blend)
		cc.Brightness = D.ccBrightness + (N.ccBrightness - D.ccBrightness) * blend
	end
	local sky = Lighting:FindFirstChildOfClass("Sky")
	if sky then
		sky.StarCount = math.round(D.stars + (N.stars - D.stars) * blend)
	end
	for light, base in lamps do
		light.Brightness = base * (1 + (Config.night.lampBoost - 1) * blend)
	end
end

function WorldService.Init()
	if not findExisting() then
		buildMap()
	end
	WorldRules.refreshAreas()
	applyLighting()
	for _, d in map:GetDescendants() do
		if d:IsA("Light") then
			lamps[d] = d.Brightness
		end
	end
end

function WorldService.Start()
	Players.PlayerRemoving:Connect(function(player)
		local i = playerPlot[player]
		if i then
			plotOwner[i] = nil
			map:SetAttribute("PlotOwner" .. i, nil)
		end
		playerPlot[player] = nil
	end)
	-- EventService owns the clock (NightOffset); the lighting just follows it
	task.spawn(function()
		while true do
			local offset = workspace:GetAttribute("NightOffset")
			local c = WorldRules.nightCycle(workspace:GetServerTimeNow(), if typeof(offset) == "number" then offset else 0)
			applyNight(c.blend, c.clock)
			task.wait(0.2)
		end
	end)
end

-- one pan per player; nil when the server's pans are all taken (Server Size should match maxPlayers)
function WorldService.assignPlot(player: Player): number?
	if playerPlot[player] then
		return playerPlot[player]
	end
	for i = 1, #Config.world.plots do
		if not plotOwner[i] then
			plotOwner[i] = player
			playerPlot[player] = i
			map:SetAttribute("PlotOwner" .. i, player.UserId) -- each client opens its own pan's door
			return i
		end
	end
	return nil
end

function WorldService.plotOf(player: Player): number?
	return playerPlot[player]
end

function WorldService.plotOwner(index: number): Player?
	return plotOwner[index]
end

-- islands 1..reach are open to this player (their client opens those gates on its own screen)
function WorldService.setReach(player: Player, reach: number)
	player:SetAttribute("Reach", reach)
end

export type TeleportTarget = { id: string, label: string, cf: CFrame }

-- every place a tester can jump to (also when it's locked): the hub, your pan, each booth, the start
-- of each island, and the end cap
function WorldService.teleportTargets(player: Player): { TeleportTarget }
	local W = Config.world
	local up = Vector3.new(0, 4, 0)
	local south = CFrame.Angles(0, math.pi, 0) -- facing down the tunnel
	local list: { TeleportTarget } = {
		{ id = "hub", label = "Hub", cf = CFrame.new(W.spawn + up) * south },
	}
	local plot = playerPlot[player]
	if plot then
		local pl = W.plots[plot]
		table.insert(list, { id = "pan", label = "My Pan", cf = CFrame.new(pl.x, 4, pl.z) * south })
	end
	for _, b in W.booths do
		-- in front of the booth, facing it
		table.insert(list, { id = "booth_" .. b.id, label = b.label, cf = CFrame.lookAt(b.pos + Vector3.new(0, 4, -7), b.pos + Vector3.new(0, 4, 0)) })
	end
	for _, z in W.zones do
		local start = z.zMin + (if z.id > 1 then W.gate.depth + 6 else 6)
		table.insert(list, { id = "zone" .. z.id, label = z.name, cf = CFrame.new(0, 4, start) * south })
	end
	table.insert(list, { id = "endcap", label = "Tunnel end", cf = CFrame.new(0, 4, W.tunnelEnd - 10) * south })
	return list
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
