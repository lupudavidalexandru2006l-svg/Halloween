--!strict
-- MapArt v3 (Round 5 map remake, owner 2026-11-02: "develop the map ... everything, booths,
-- leaderboards, islands"). The look of the world, built once by WorldService.buildMap; every gameplay
-- part, name and tag still comes from WorldService.
-- The hub is a winter village: a low stone wall with lanterns, candy-coloured cottages and big pines
-- outside it, and open snowy ground inside it.
-- The pans are striped lawns with white rail fences (the owner's picture), a white gate arch, flower
-- boxes and the Thaw Machine(s) at the back (PanLooks restyles fences per Look, shows machine 2).
-- Booths are giant versions of what they do: a treasure chest (Sell), a workshop with turning gears
-- (Equipment), a ring portal (Rebirth); the client turns and bobs their Motion folders.
-- Leaderboards stand in a wooden frame between stone pillars with glowing crystal caps.
-- The islands have natural rock cliffs instead of flat walls (snowy or mossy, two rows, trees on top),
-- stone-edged paths, lanterns, themed props, a big landmark and a castle gatehouse in front of each.
-- World Rules 9 (clear centre, rich edges): the middle where pets walk stays calm (shade trees in the
-- side bands, pines' branches above head height), the props sit on an earth strip at the cliffs' foot,
-- and the landmarks stand in the cliffs, rising over them.
-- Contracts other scripts rely on: Art.Hub.Pan<i> holds FencePost / PostCap / FenceRail / PanFloor /
-- LawnStripe / DoorGlow / ThawMachine1-2 (PanLooks, MapController, ThawMachines); GateBars<id> and GateGlow parts
-- (MapController); GiftArt (MapController bobs it); Lights anywhere in the map (WorldService, night).
-- Shapes Roblox has no primitive for (cone, crystal, rock, dome, ring, arch) are MeshParts in
-- ReplicatedStorage.SceneryMeshes; plain parts stand in when they're missing.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Theme = require(ReplicatedStorage.Shared.Theme)
local Scenery = require(ReplicatedStorage.Shared.Scenery)
local WorldRules = require(ReplicatedStorage.Shared.WorldRules)

local MapArt = {}
local A = Theme.art
local HA = Theme.hubArt
local V = Theme.village
local C = Config.art
local W = Config.world

-- tree recipes from the prototype: { radius, height, centre y, colour } per cone, in tree units
type ConeSpec = { r: number, h: number, y: number, color: Color3 }
local function cones(list: { { any } }): { ConeSpec }
	local out: { ConeSpec } = {}
	for _, c in list do
		table.insert(out, { r = c[1], h = c[2], y = c[3], color = c[4] })
	end
	return out
end
local SNOW_PINE = cones({
	{ 2.1, 2.6, 2.6, A.snowPine[1] }, { 1.75, 2.3, 3.9, A.snowPine[2] }, { 1.35, 2.0, 5.1, A.snowPine[3] }, { 0.9, 1.8, 6.2, A.snowPine[4] },
	{ 1.3, 0.9, 3.2, A.snowCap }, { 1.0, 0.8, 4.4, A.snowCap }, { 0.7, 0.7, 5.5, A.snowCap }, { 0.45, 0.8, 6.8, A.snowCap },
})
local PINE = cones({ { 2.2, 2.7, 2.6, A.pine[1] }, { 1.8, 2.4, 3.9, A.pine[2] }, { 1.4, 2.1, 5.1, A.pine[3] }, { 0.95, 1.9, 6.2, A.pine[4] } })

local meshes: Instance? = nil

local function finish(p: BasePart, color: Color3, parent: Instance, collide: boolean?): BasePart
	p.Anchored = true
	p.CanCollide = collide == true
	p.CanQuery = true -- the camera's Invisicam needs to see it to fade it when it hides the player
	p.CanTouch = false
	p.Color = color
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function block(size: Vector3, cf: CFrame, color: Color3, parent: Instance, collide: boolean?, material: Enum.Material?): BasePart
	local p = Instance.new("Part")
	p.Size = size
	p.CFrame = cf
	p.Material = material or Enum.Material.SmoothPlastic
	return finish(p, color, parent, collide)
end

local function named(p: BasePart, name: string): BasePart
	p.Name = name
	return p
end

-- a wedge whose slope rises toward +Z (its tall back face at +Z)
local function wedge(size: Vector3, cf: CFrame, color: Color3, parent: Instance, material: Enum.Material?): BasePart
	local p = Instance.new("WedgePart")
	p.Size = size
	p.CFrame = cf
	p.Material = material or Enum.Material.SmoothPlastic
	return finish(p, color, parent)
end

-- an upright cylinder centred at cf
local function cyl(radius: number, height: number, cf: CFrame, color: Color3, parent: Instance, collide: boolean?, material: Enum.Material?): BasePart
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Cylinder
	p.Size = Vector3.new(height, radius * 2, radius * 2)
	p.CFrame = cf * CFrame.Angles(0, 0, math.pi / 2)
	p.Material = material or Enum.Material.SmoothPlastic
	return finish(p, color, parent, collide)
end

-- a (possibly squashed) sphere filling size
local function ellipsoid(size: Vector3, cf: CFrame, color: Color3, parent: Instance, material: Enum.Material?): BasePart
	local p = Instance.new("Part")
	p.Size = size
	p.CFrame = cf
	p.Material = material or Enum.Material.SmoothPlastic
	local m = Instance.new("SpecialMesh")
	m.MeshType = Enum.MeshType.Sphere
	m.Parent = p
	return finish(p, color, parent)
end

local function ball(r: number, at: Vector3, color: Color3, parent: Instance): BasePart
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Ball
	p.Size = Vector3.one * r * 2
	p.CFrame = CFrame.new(at)
	p.Material = Enum.Material.SmoothPlastic
	return finish(p, color, parent)
end

-- one of the imported shapes, stretched to size (a sphere stands in if the mesh isn't there)
local function shape(name: string, size: Vector3, cf: CFrame, color: Color3, parent: Instance): BasePart
	local template = meshes and meshes:FindFirstChild(name)
	if template and template:IsA("MeshPart") then
		local p = template:Clone()
		p.Size = size
		p.CFrame = cf
		p.CastShadow = true
		return finish(p, color, parent)
	end
	return ellipsoid(size, cf, color, parent)
end

local function glow(p: BasePart, transparency: number?): BasePart
	p.Material = Enum.Material.Neon
	p.Transparency = transparency or 0
	p.CastShadow = false
	return p
end

local function far(p: BasePart): BasePart
	p.CastShadow = false
	p.CanQuery = false -- far away: never between the camera and you
	return p
end

local function quiet(p: BasePart): BasePart
	p.CastShadow = false
	return p
end

local function light(parent: Instance, color: Color3, range: number, brightness: number?)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness or 0.9
	l.Shadows = false
	l.Parent = parent
end

local function folder(name: string, parent: Instance): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

-- ---------- small pieces used everywhere ----------
-- a lantern on a post: iron base and pole, a warm glass box with a little roof, and its light
local function lantern(parent: Instance, at: Vector3, color: Color3, height: number, range: number, withLight: boolean?)
	cyl(0.55, 0.5, CFrame.new(at + Vector3.new(0, 0.25, 0)), V.iron, parent, true)
	cyl(0.17, height, CFrame.new(at + Vector3.new(0, height / 2, 0)), V.iron, parent, true)
	block(Vector3.new(1.3, 0.2, 1.3), CFrame.new(at + Vector3.new(0, height + 0.1, 0)), V.iron, parent)
	local box = block(Vector3.new(1, 1.25, 1), CFrame.new(at + Vector3.new(0, height + 0.85, 0)), color, parent)
	box.Material = Enum.Material.Glass
	box.Transparency = 0.05
	quiet(box)
	shape("Cone", Vector3.new(1.6, 0.9, 1.6), CFrame.new(at + Vector3.new(0, height + 1.9, 0)), V.iron, parent)
	if withLight ~= false then
		light(box, color, range)
	end
end

-- Round 4 phase 6: each new island's own "tree" (what gives shade there), and its cheap far version
local ISLAND_TREES: { [string]: (CFrame, number, Instance) -> () } = {}
local FAR_TREES: { [string]: (Vector3, number, Instance) -> () } = {}

local function tree(x: number, y: number, z: number, s: number, ry: number, kind: string, parent: Instance)
	local m = Instance.new("Model")
	m.Name = "Tree"
	local at = CFrame.new(x, y, z) * CFrame.Angles(0, ry, 0)
	local custom = ISLAND_TREES[kind]
	if custom then
		custom(at, s, m)
	else
		-- a taller trunk lifts the branches above head height, so pets under the pine stay in view (World Rules 9)
		local recipe = if kind == "snowpine" then SNOW_PINE else PINE
		local low = math.huge
		for _, c in recipe do
			low = math.min(low, c.y - c.h / 2)
		end
		local lift = math.max(0, C.canopyClear - low * s)
		local trunk = 2.4 * s + lift
		cyl(0.43 * s, trunk, at * CFrame.new(0, trunk / 2, 0), A.trunk, m, true)
		for _, c in recipe do
			shape("Cone", Vector3.new(c.r * 2 * s, c.h * s, c.r * 2 * s), at * CFrame.new(0, c.y * s + lift, 0), c.color, m)
		end
	end
	m.Parent = parent
end

-- a cheap tree for far away: one cone (and a snow cap on snowy ground)
local function farTree(x: number, y: number, z: number, s: number, kind: string, parent: Instance)
	if FAR_TREES[kind] then
		FAR_TREES[kind](Vector3.new(x, y, z), s, parent)
		return
	end
	local col = if kind == "snowpine" then A.snowPine[2] else A.pine[2]
	far(shape("Cone", Vector3.new(4.4 * s, 7 * s, 4.4 * s), CFrame.new(x, y + 3.5 * s, z), col, parent))
	if kind == "snowpine" then
		far(shape("Cone", Vector3.new(2.2 * s, 2.6 * s, 2.2 * s), CFrame.new(x, y + 6 * s, z), A.snowCap, parent))
	end
end

-- a little bunch of flowers: green stems and round heads in candy colours
local function flowers(parent: Instance, at: Vector3, n: number, rng: () -> number)
	for k = 1, n do
		local a, r = rng() * math.pi * 2, rng() * 0.9
		local p = at + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
		local h = 0.5 + rng() * 0.4
		quiet(block(Vector3.new(0.12, h, 0.12), CFrame.new(p + Vector3.new(0, h / 2, 0)), A.bush, parent))
		quiet(ball(0.22, p + Vector3.new(0, h + 0.1, 0), V.flowers[(k + math.floor(rng() * 5)) % #V.flowers + 1], parent))
	end
end

local function planter(parent: Instance, cf: CFrame, len: number, rng: () -> number)
	block(Vector3.new(len, 0.9, 1.3), cf * CFrame.new(0, 0.45, 0), V.crate, parent, false, Enum.Material.WoodPlanks)
	block(Vector3.new(len - 0.3, 0.12, 1), cf * CFrame.new(0, 0.92, 0), A.trunk, parent, false, Enum.Material.Ground)
	local n = math.max(1, math.floor(len / 1.2))
	for k = 1, n do
		flowers(parent, (cf * CFrame.new(-len / 2 + (k - 0.5) * len / n, 0.95, 0)).Position, 2, rng)
	end
end

local function snowyBush(parent: Instance, at: Vector3, s: number, snow: boolean)
	ellipsoid(Vector3.new(2.4 * s, 1.8 * s, 2.4 * s), CFrame.new(at + Vector3.new(0, 0.7 * s, 0)), A.bush, parent, Enum.Material.LeafyGrass)
	ellipsoid(Vector3.new(1.6 * s, 1.4 * s, 1.6 * s), CFrame.new(at + Vector3.new(0.7 * s, 0.9 * s, 0.3 * s)), A.bush, parent, Enum.Material.LeafyGrass)
	if snow then
		quiet(ellipsoid(Vector3.new(2 * s, 0.6 * s, 2 * s), CFrame.new(at + Vector3.new(0, 1.5 * s, 0)), A.snowCap, parent))
	end
end

local function crate(parent: Instance, cf: CFrame, s: number)
	block(Vector3.one * s, cf * CFrame.new(0, s / 2, 0), V.crate, parent, true, Enum.Material.WoodPlanks)
	for _, y in { 0.15, 0.85 } do
		block(Vector3.new(s + 0.08, 0.15 * s, s + 0.08), cf * CFrame.new(0, y * s, 0), A.post, parent)
	end
end

local function barrel(parent: Instance, at: Vector3, s: number)
	cyl(0.75 * s, 1.8 * s, CFrame.new(at + Vector3.new(0, 0.9 * s, 0)), V.barrel, parent, true, Enum.Material.WoodPlanks)
	for _, y in { 0.35, 1.45 } do
		cyl(0.79 * s, 0.14 * s, CFrame.new(at + Vector3.new(0, y * s, 0)), V.iron, parent)
	end
end

local function present(parent: Instance, at: Vector3, s: number, color: Color3, ry: number)
	local cf = CFrame.new(at) * CFrame.Angles(0, ry, 0)
	block(Vector3.one * s, cf * CFrame.new(0, s / 2, 0), color, parent)
	block(Vector3.new(s * 0.22, s + 0.08, s + 0.08), cf * CFrame.new(0, s / 2, 0), V.gold, parent) -- ribbons stand clear of the box (0.02 flickered)
	block(Vector3.new(s + 0.08, s + 0.08, s * 0.22), cf * CFrame.new(0, s / 2, 0), V.gold, parent)
end

local function smallSnowman(parent: Instance, at: Vector3, s: number, ry: number)
	local cf = CFrame.new(at) * CFrame.Angles(0, ry, 0)
	ball(1.1 * s, (cf * CFrame.new(0, 1 * s, 0)).Position, A.snowman, parent)
	ball(0.8 * s, (cf * CFrame.new(0, 2.6 * s, 0)).Position, A.snowman, parent)
	ball(0.55 * s, (cf * CFrame.new(0, 3.7 * s, 0)).Position, A.snowman, parent)
	shape("Cone", Vector3.new(0.25, 0.7, 0.25) * s, cf * CFrame.new(0, 3.7 * s, -0.75 * s) * CFrame.Angles(-math.pi / 2, 0, 0), A.carrot, parent)
	for _, ex in { -0.2, 0.2 } do
		ball(0.08 * s, (cf * CFrame.new(ex * s, 3.9 * s, -0.48 * s)).Position, Theme.ink, parent)
	end
	cyl(0.45 * s, 0.6 * s, cf * CFrame.new(0, 4.35 * s, 0), A.hat, parent)
	cyl(0.65 * s, 0.1 * s, cf * CFrame.new(0, 4.08 * s, 0), A.hat, parent)
	shape("Ring", Vector3.new(1.25, 0.35, 1.25) * s, cf * CFrame.new(0, 3.2 * s, 0), A.scarf, parent)
end

-- a cottage facing -Z of cf: walls, corner trim, a gable roof with snow on the ridge, a door, lit
-- windows with shutters, and a chimney
local function house(parent: Instance, cf: CFrame, w: number, d: number, h: number, wall: Color3, roof: Color3, shutter: Color3, rng: () -> number)
	local m = Instance.new("Model")
	m.Name = "Cottage"
	block(Vector3.new(w + 0.6, 1, d + 0.6), cf * CFrame.new(0, 0.5, 0), V.stone, m, false, Enum.Material.Cobblestone)
	block(Vector3.new(w, h, d), cf * CFrame.new(0, 1 + h / 2, 0), wall, m, false, Enum.Material.SmoothPlastic)
	for _, x in { -w / 2, w / 2 } do
		for _, z in { -d / 2, d / 2 } do
			block(Vector3.new(0.45, h, 0.45), cf * CFrame.new(x, 1 + h / 2, z), V.trim, m)
		end
	end
	block(Vector3.new(w + 0.3, 0.4, d + 0.3), cf * CFrame.new(0, 1 + h, 0), V.trim, m)
	local rh = 0.55 * d
	local top = 1 + h + 0.2
	-- the gable roof: two wedges meeting at the ridge (along x), with overhang
	wedge(Vector3.new(w + 1.4, rh, d / 2 + 0.8), cf * CFrame.new(0, top + rh / 2, -(d / 2 + 0.8) / 2), roof, m)
	wedge(Vector3.new(w + 1.4, rh, d / 2 + 0.8), cf * CFrame.new(0, top + rh / 2, (d / 2 + 0.8) / 2) * CFrame.Angles(0, math.pi, 0), roof, m)
	-- the triangle under the roof at each end, in the wall colour
	for _, x in { -w / 2, w / 2 } do
		wedge(Vector3.new(0.3, rh - 0.2, d / 2), cf * CFrame.new(x, top + (rh - 0.2) / 2, -d / 4), wall, m)
		wedge(Vector3.new(0.3, rh - 0.2, d / 2), cf * CFrame.new(x, top + (rh - 0.2) / 2, d / 4) * CFrame.Angles(0, math.pi, 0), wall, m)
	end
	quiet(cyl(0.7, w + 1.6, cf * CFrame.new(0, top + rh, 0) * CFrame.Angles(0, 0, math.pi / 2), A.snowCap, m))
	-- chimney
	local cx = (rng() - 0.5) * w * 0.5
	block(Vector3.new(1.2, rh + 1.2, 1.2), cf * CFrame.new(cx, top + rh * 0.6 + 0.4, d * 0.18), V.brick, m, false, Enum.Material.Brick)
	quiet(block(Vector3.new(1.45, 0.35, 1.45), cf * CFrame.new(cx, top + rh * 1.1 + 1, d * 0.18), A.snowCap, m))
	-- the front: door with a frame and step, two lit windows with shutters
	local front = -d / 2 - 0.05
	block(Vector3.new(2.4, 3.6, 0.2), cf * CFrame.new(0, 2.8, front), V.trim, m)
	block(Vector3.new(1.8, 3.2, 0.25), cf * CFrame.new(0, 2.6, front - 0.05), V.door, m, false, Enum.Material.WoodPlanks)
	ball(0.13, (cf * CFrame.new(0.6, 2.5, front - 0.2)).Position, V.gold, m)
	block(Vector3.new(3, 0.4, 1.2), cf * CFrame.new(0, 1.2, front - 0.6), V.stoneWarm, m)
	for _, x in { -w / 4 - 0.4, w / 4 + 0.4 } do
		if math.abs(x) + 1.2 < w / 2 then
			block(Vector3.new(2, 2, 0.2), cf * CFrame.new(x, 1 + h * 0.6, front), V.trim, m)
			quiet(glow(block(Vector3.new(1.6, 1.6, 0.22), cf * CFrame.new(x, 1 + h * 0.6, front - 0.03), V.window, m), 0.1))
			-- the cross bars stop short of the glass's edges and stand clearly in front of it (flush, they flickered)
			block(Vector3.new(0.12, 1.5, 0.3), cf * CFrame.new(x, 1 + h * 0.6, front - 0.1), V.trim, m)
			block(Vector3.new(1.5, 0.12, 0.3), cf * CFrame.new(x, 1 + h * 0.6, front - 0.1), V.trim, m)
			for _, sx in { -1.25, 1.25 } do
				block(Vector3.new(0.5, 1.9, 0.15), cf * CFrame.new(x + sx, 1 + h * 0.6, front - 0.02), shutter, m)
			end
		end
	end
	for _, d0 in m:GetDescendants() do
		if d0:IsA("BasePart") then
			d0.CanQuery = false -- outside the walls: never between the camera and you
		end
	end
	m.Parent = parent
end

-- ---------- the pans ----------
local function fence(parent: Instance, x1: number, z1: number, x2: number, z2: number, y: number, every: number, post: Color3, rail: Color3, height: number)
	local len = math.sqrt((x2 - x1) ^ 2 + (z2 - z1) ^ 2)
	local n = math.max(1, math.round(len / every))
	for i = 0, n do
		local x, z = x1 + (x2 - x1) * i / n, z1 + (z2 - z1) * i / n
		named(block(Vector3.new(0.6, height, 0.6), CFrame.new(x, y + height / 2, z), post, parent), "FencePost")
		named(shape("Octa", Vector3.new(0.75, 0.7, 0.75), CFrame.new(x, y + height + 0.2, z), post, parent), "PostCap")
	end
	local mid = CFrame.lookAt(Vector3.new((x1 + x2) / 2, 0, (z1 + z2) / 2), Vector3.new(x2, 0, z2))
	for _, h in { height * 0.38, height * 0.75 } do
		named(block(Vector3.new(0.25, 0.3, len), mid + Vector3.new(0, y + h, 0), rail, parent), "FenceRail")
	end
end

-- the Thaw Machine (owner 2026-11-07: "much more detailed ... techy and futuristic"): a sci-fi thaw pod
-- facing the door. A round two-step deck with 12 running rim lights; a raised diamond-plate heat pad
-- with two glowing coils and a core disc (the cube sits on it); a reactor tower behind it with a
-- see-through core tube that fills as the pet thaws, a holo screen, status lights, orange vent fins,
-- two steam stacks and an antenna beacon; an overhead arm with an emitter pointing down; two pylons
-- with light strips and emitter heads aimed at the cube; and a floating halo ring with six emitter
-- nodes and a thin inner ring. Only the shapes are built here: ThawMachines (client) animates the
-- named parts (Chase with I = 1..12, Coil, CoilCore, GaugeFill, Strip, Led with I = 1..3, Beacon,
-- Nozzle, Emitter, HaloNode, the Halo model round HaloCenter, HaloInner, Screen, Stack).
local function thawMachine(parent: Instance, name: string, ground: Vector3)
	local R5 = Theme.round5
	local M = Config.thaw.machine
	local m = Instance.new("Model")
	m.Name = name
	m.ModelStreamingMode = Enum.ModelStreamingMode.Atomic -- it streams in whole (the client animates its parts)
	local cf = CFrame.new(ground) -- faces the door (+Z)
	local function at(x: number, y: number, z: number): CFrame
		return cf * CFrame.new(x, y, z)
	end
	local dark, metal, body, accent, cold = R5.machineDark, R5.machineMetal, R5.machineTrim, R5.machine, R5.machineCold
	local pad = M.padTop
	local up = CFrame.Angles(math.pi / 2, 0, 0) -- turns an upright cylinder to lie along z

	-- the deck: a navy base, a cream step with four bolts, 12 rim lights on the ledge between them
	cyl(3.7, 0.3, at(0, 0.15, 0), dark, m, false, Enum.Material.Metal)
	cyl(3.45, 0.22, at(0, 0.41, 0), body, m)
	for k = 0, 11 do
		local c = named(quiet(glow(block(Vector3.new(0.62, 0.1, 0.2), cf * CFrame.Angles(0, k * math.pi / 6, 0) * CFrame.new(0, 0.35, 3.575), cold, m), 0.6)), "Chase")
		c:SetAttribute("I", k + 1)
	end
	for k = 0, 3 do
		quiet(cyl(0.13, 0.08, cf * CFrame.Angles(0, k * math.pi / 2 + math.pi / 4, 0) * CFrame.new(0, 0.54, 3.08), metal, m, false, Enum.Material.Metal))
	end

	-- the heat pad: diamond plate on an orange band, two glowing coils and a core disc under the cube
	cyl(2.8, 0.14, at(0, pad - 0.1, 0), accent, m)
	cyl(2.65, 0.25, at(0, pad - 0.125, 0), metal, m, false, Enum.Material.DiamondPlate)
	for _, d in { 4.4, 2.2 } do
		named(quiet(glow(shape("Ring", Vector3.new(d, 0.08, d), at(0, pad + 0.02, 0), cold, m), 0.2)), "Coil")
	end
	local core = named(quiet(glow(cyl(0.45, 0.06, at(0, pad + 0.01, 0), cold, m), 0.1)), "CoilCore")
	light(core, cold, Config.thaw.fx.light.range, Config.thaw.fx.light.idle)

	-- the reactor tower behind the pad: a navy plinth, a cream body, orange fins with vent slats
	local tz = -3.6
	local fz = tz + 0.75 -- its front face
	block(Vector3.new(3.1, 0.6, 2), at(0, 0.6, tz), dark, m, true, Enum.Material.Metal)
	block(Vector3.new(2.6, 8, 1.5), at(0, 4.9, tz), body, m, true)
	for _, sx in { -1, 1 } do
		block(Vector3.new(0.5, 7, 1.9), at(sx * 1.55, 4.4, tz - 0.05), accent, m, true)
		wedge(Vector3.new(0.5, 1, 1.9), at(sx * 1.55, 8.4, tz - 0.05) * CFrame.Angles(0, math.pi, 0), accent, m)
		for j = 0, 3 do
			quiet(block(Vector3.new(0.08, 0.16, 1.3), at(sx * 1.83, 2.2 + j * 0.5, tz - 0.05), dark, m))
		end
	end
	-- the front: a navy panel, the core tube (glass, a glowing fill, metal caps, orange clamps) with a
	-- scale either side, the holo screen in a cream bezel, status lights down the left fin, grille right
	quiet(block(Vector3.new(2.2, 6.9, 0.1), at(0, 4.9, fz + 0.04), dark, m))
	local tubeZ = fz + 0.05
	local glass = quiet(cyl(0.42, 4.3, at(0, 3.55, tubeZ), R5.machineGlass, m))
	glass.Transparency = 0.6
	named(quiet(glow(cyl(0.3, 4.1, at(0, 3.55, tubeZ), cold, m))), "GaugeFill")
	for _, y in { 1.25, 5.85 } do
		cyl(0.52, 0.4, at(0, y, tubeZ), metal, m, false, Enum.Material.Metal)
	end
	for _, y in { 2.6, 4.5 } do
		quiet(cyl(0.46, 0.1, at(0, y, tubeZ), accent, m))
	end
	for _, sx in { -1, 1 } do
		for j = 0, 4 do
			local long = j % 2 == 0
			quiet(block(Vector3.new(if long then 0.32 else 0.18, 0.06, 0.05), at(sx * (if long then 0.78 else 0.71), 1.6 + j * 0.95, fz + 0.1), body, m))
		end
	end
	quiet(block(Vector3.new(2.15, 1.45, 0.08), at(0, 7.55, fz + 0.1), body, m))
	named(quiet(block(Vector3.new(1.95, 1.25, 0.06), at(0, 7.55, fz + 0.15), R5.machineScreen, m)), "Screen")
	for j = 1, 3 do
		local led = named(quiet(glow(ball(0.14, at(-1.55, 6.2 + j * 0.55, tz + 0.95).Position, cold, m), 0.1)), "Led")
		led:SetAttribute("I", j)
		quiet(block(Vector3.new(0.3, 0.3, 0.05), at(1.55, 6.2 + j * 0.55, tz + 0.88), dark, m))
	end
	-- the top: a navy cap, a cream dome, two steam stacks and an antenna with its beacon
	block(Vector3.new(3, 0.35, 2.1), at(0, 9.07, tz), dark, m, false, Enum.Material.Metal)
	shape("Dome", Vector3.new(2.2, 1, 1.6), at(0, 9.75, tz), body, m)
	for _, sx in { -1, 1 } do
		cyl(0.28, 1.1, at(sx * 1.05, 9.8, tz - 0.55), metal, m, false, Enum.Material.Metal)
		quiet(cyl(0.34, 0.16, at(sx * 1.05, 10.38, tz - 0.55), accent, m))
		local vent = named(quiet(block(Vector3.one * 0.3, at(sx * 1.05, 10.5, tz - 0.55), dark, m)), "Stack")
		vent.Transparency = 1
		vent.CanQuery = false
	end
	cyl(0.07, 1.5, at(0.55, 10.6, tz - 0.2), metal, m, false, Enum.Material.Metal)
	named(quiet(glow(ball(0.22, at(0.55, 11.45, tz - 0.2).Position, R5.machineReady, m))), "Beacon")
	-- power: two conduits from the tower's back into sockets in the ground
	for _, sx in { -0.7, 0.7 } do
		cyl(0.22, 0.45, at(sx, 0.5, tz - 0.95) * up, dark, m, false, Enum.Material.Metal)
		quiet(cyl(0.27, 0.12, at(sx, 0.5, tz - 0.95) * up, accent, m))
		block(Vector3.new(0.6, 0.7, 0.45), at(sx, 0.35, tz - 1.35), dark, m, false, Enum.Material.Metal) -- clear of the back fence posts
	end

	-- the overhead arm: out of the tower over the pad, a navy head and an emitter pointing down
	block(Vector3.new(0.8, 0.55, 3.2), at(0, 8.5, -1.35), body, m)
	quiet(block(Vector3.new(0.5, 0.08, 3), at(0, 8.2, -1.3), accent, m))
	cyl(0.75, 0.6, at(0, 8.45, 0), dark, m, false, Enum.Material.Metal)
	quiet(cyl(0.82, 0.14, at(0, 8.45, 0), accent, m))
	shape("Cone", Vector3.new(1, 0.8, 1), at(0, 7.8, 0) * CFrame.Angles(math.pi, 0, 0), metal, m)
	named(quiet(glow(ball(0.2, at(0, 7.35, 0).Position, cold, m))), "Nozzle")

	-- two pylons beside the pad, each with a light strip facing it and an emitter head aimed at the cube
	local aim = at(0, pad + 2, 0).Position
	for _, side in { -1, 1 } do
		local p = cf * CFrame.Angles(0, side * math.rad(125), 0) * CFrame.new(0, 0, 3.25) -- its -Z faces the pad
		cyl(0.55, 0.4, p * CFrame.new(0, 0.7, 0), dark, m, true, Enum.Material.Metal)
		cyl(0.42, 4.6, p * CFrame.new(0, 2.95, 0), body, m, true)
		for _, y in { 2, 4 } do
			quiet(cyl(0.47, 0.18, p * CFrame.new(0, y, 0), accent, m))
		end
		cyl(0.5, 0.3, p * CFrame.new(0, 5.4, 0), dark, m, false, Enum.Material.Metal)
		quiet(block(Vector3.new(0.26, 3.4, 0.1), p * CFrame.new(0, 3, -0.4), dark, m))
		named(quiet(glow(block(Vector3.new(0.14, 3.2, 0.08), p * CFrame.new(0, 3, -0.45), cold, m), 0.2)), "Strip")
		local head = CFrame.lookAt((p * CFrame.new(0, 5.9, 0)).Position, aim)
		block(Vector3.new(0.7, 0.6, 0.9), head, dark, m, false, Enum.Material.Metal)
		quiet(block(Vector3.new(0.78, 0.12, 0.95), head * CFrame.new(0, 0.3, 0), accent, m))
		named(quiet(glow(cyl(0.22, 0.12, head * CFrame.new(0, 0, -0.48) * up, cold, m))), "Emitter")
	end

	-- the floating halo: a cream ring with a glowing edge and six emitter nodes under it (they turn
	-- together round HaloCenter), and a thin inner ring just below that turns the other way
	local hc = at(0, M.haloY, 0)
	local R = M.haloRadius
	local halo = Instance.new("Model")
	halo.Name = "Halo"
	halo.Parent = m
	local centre = named(quiet(block(Vector3.one * 0.2, hc, dark, halo)), "HaloCenter")
	centre.Transparency = 1
	centre.CanQuery = false
	shape("Ring", Vector3.new(R * 2 - 0.2, 0.4, R * 2 - 0.2), hc, body, halo)
	named(quiet(glow(shape("Ring", Vector3.new(R * 2, 0.14, R * 2), hc, cold, halo), 0.1)), "HaloGlow")
	for k = 0, 5 do
		local ncf = hc * CFrame.Angles(0, k * math.pi / 3 + math.pi / 6, 0) * CFrame.new(0, -0.3, R * 0.78)
		block(Vector3.new(0.5, 0.3, 0.5), ncf, dark, halo, false, Enum.Material.Metal)
		named(quiet(glow(ball(0.15, (ncf * CFrame.new(0, -0.2, 0)).Position, cold, halo))), "HaloNode")
	end
	named(quiet(glow(shape("Ring", Vector3.new(2.6, 0.1, 2.6), hc * CFrame.new(0, -0.55, 0), cold, m), 0.3)), "HaloInner")
	m.Parent = parent
end

local function panArt(parent: Instance, i: number, pl: { x: number, z: number }, rng: () -> number)
	local P = W.pans
	local look = Theme.panLooks.garden
	local f = folder("Pan" .. i, parent)
	local y = P.soilHeight
	local x0, x1 = pl.x - P.width / 2, pl.x + P.width / 2
	local zb, zf = P.frontZ - P.length, P.frontZ
	-- a flush stone edge round the bed (the pan sits level with the ground), then the lawn with mowed stripes
	local kerb = y + 0.1
	block(Vector3.new(P.width + 0.9, kerb, P.length + 0.9), CFrame.new(pl.x, kerb / 2, pl.z), V.stone, f, false, Enum.Material.Cobblestone)
	named(block(Vector3.new(P.width - 0.2, 0.2, P.length - 0.2), CFrame.new(pl.x, y + 0.1, pl.z), look.floor, f, false, Enum.Material.Grass), "PanFloor")
	local band = 4
	local n = math.floor((P.length - 0.4) / band)
	for k = 0, n - 1, 2 do
		quiet(named(block(Vector3.new(P.width - 0.4, 0.05, band), CFrame.new(pl.x, y + 0.225, zb + 0.2 + (k + 0.5) * band), look.stripe, f, false, Enum.Material.Grass), "LawnStripe"))
	end
	-- stepping stones in from the gate
	for k = 0, 2 do
		quiet(block(Vector3.new(2.6, 0.12, 1.8), CFrame.new(pl.x + (if k % 2 == 0 then -0.5 else 0.5), y + 0.27, zf - 1.8 - k * 2.6), V.stoneWarm, f, false, Enum.Material.Slate))
	end
	-- white rail fences (the owner's picture); PanLooks repaints them for the other Looks
	local h = P.fenceHeight
	fence(f, x0, zb, x1, zb, y, C.penPostEvery, look.post, look.rail, h)
	fence(f, x0, zb, x0, zf, y, C.penPostEvery, look.post, look.rail, h)
	fence(f, x1, zb, x1, zf, y, C.penPostEvery, look.post, look.rail, h)
	fence(f, x0, zf, pl.x - P.doorWidth / 2, zf, y, C.penPostEvery, look.post, look.rail, h)
	fence(f, pl.x + P.doorWidth / 2, zf, x1, zf, y, C.penPostEvery, look.post, look.rail, h)
	-- the gate arch: two tall posts, a top beam (the name sign hangs on it) and round finials
	local gh = P.signY + 1.6
	for _, dx in { -P.doorWidth / 2, P.doorWidth / 2 } do
		named(block(Vector3.new(0.9, gh, 0.9), CFrame.new(pl.x + dx, gh / 2, zf + 0.5), look.post, f), "FencePost")
		named(ball(0.6, Vector3.new(pl.x + dx, gh + 0.5, zf + 0.5), look.post, f), "PostCap")
	end
	named(block(Vector3.new(P.doorWidth + 1.6, 0.6, 0.7), CFrame.new(pl.x, gh - 0.4, zf + 0.5), look.rail, f), "FenceRail")
	local curtain = block(Vector3.new(P.doorWidth - 1, 4.6, 0.3), CFrame.new(pl.x, y + 2.3, zf + 0.5), HA.door, f, false, Enum.Material.ForceField)
	curtain.Name = "DoorGlow"
	curtain.CastShadow = false
	-- flower boxes inside the front corners
	planter(f, CFrame.new(x0 + 2.4, y, zf - 1.3), 3.2, rng)
	planter(f, CFrame.new(x1 - 2.4, y, zf - 1.3), 3.2, rng)
	-- the gauge's post
	cyl(0.25, 2.6, CFrame.new(pl.x + P.gaugeOffset, 1.3, zf + 1.4), V.iron, f)
	-- the Pan Upgrades stand: a green counter with white trim and a big gold up arrow
	local sx, sz = pl.x + P.boothOffset, zf + 2.5
	block(Vector3.new(3, 2.6, 2), CFrame.new(sx, 1.3, sz), Theme.booths.pan, f, false, Enum.Material.WoodPlanks)
	block(Vector3.new(3.4, 0.35, 2.4), CFrame.new(sx, 2.75, sz), V.trim, f)
	local arrow = CFrame.new(sx, 4.6, sz)
	block(Vector3.new(0.8, 1.6, 0.8), arrow * CFrame.new(0, -0.6, 0), Theme.coin, f)
	shape("Cone", Vector3.new(2, 1.5, 2), arrow * CFrame.new(0, 0.85, 0), Theme.coin, f)
	-- the Thaw Machines at the back (the second one shows once the pan has it: PanLooks)
	local T = Config.thaw
	for m = 1, 2 do
		thawMachine(f, "ThawMachine" .. m, Vector3.new(pl.x + T.machine.x + (m - 1) * T.machine.gap, y, zb + T.machine.z)) -- on the ground; the pad lifts the cube to padTop
	end
end

-- ---------- the hub ----------
-- a horizontal log: a cylinder along the X axis of cf
local function log(len: number, r: number, cf: CFrame, color: Color3, parent: Instance): BasePart
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Cylinder
	p.Size = Vector3.new(len, r * 2, r * 2)
	p.CFrame = cf
	p.Material = Enum.Material.Wood
	return finish(p, color, parent)
end

-- a gear mannequin facing -Z of cf: fur boots, trousers, a warm red coat with a zip and buttons,
-- a scarf, and a knitted beanie with a pompom
local function mannequin(parent: Instance, cf: CFrame)
	cyl(0.65, 0.2, cf * CFrame.new(0, 0.1, 0), V.iron, parent)
	for _, x in { -0.3, 0.3 } do
		block(Vector3.new(0.45, 0.6, 0.75), cf * CFrame.new(x, 0.5, -0.1), A.trunk, parent)
		block(Vector3.new(0.56, 0.22, 0.62), cf * CFrame.new(x, 0.86, 0), Theme.white, parent, false, Enum.Material.Fabric)
	end
	block(Vector3.new(0.9, 1, 0.5), cf * CFrame.new(0, 1.45, 0), V.iron, parent, false, Enum.Material.Fabric)
	local red = V.roofs[1]
	block(Vector3.new(1.5, 1.6, 0.85), cf * CFrame.new(0, 2.65, 0), red, parent, false, Enum.Material.Fabric)
	block(Vector3.new(1.56, 0.22, 0.9), cf * CFrame.new(0, 1.9, 0), Theme.white, parent, false, Enum.Material.Fabric)
	quiet(block(Vector3.new(0.1, 1.45, 0.05), cf * CFrame.new(0, 2.65, -0.45), Theme.white, parent))
	for i = 0, 2 do
		ball(0.08, (cf * CFrame.new(0.3, 3.1 - i * 0.4, -0.45)).Position, V.gold, parent)
	end
	for _, x in { -1, 1 } do
		block(Vector3.new(0.45, 1.4, 0.5), cf * CFrame.new(x * 0.95, 2.55, 0) * CFrame.Angles(0, 0, x * 0.15), red, parent, false, Enum.Material.Fabric)
		block(Vector3.new(0.5, 0.25, 0.55), cf * CFrame.new(x * 1.03, 1.85, 0) * CFrame.Angles(0, 0, x * 0.15), Theme.white, parent, false, Enum.Material.Fabric)
	end
	shape("Ring", Vector3.new(1.05, 0.38, 1.05), cf * CFrame.new(0, 3.5, 0), V.flowers[2], parent)
	block(Vector3.new(0.3, 0.9, 0.08), cf * CFrame.new(0.3, 3.05, -0.5) * CFrame.Angles(0.1, 0, 0.1), V.flowers[2], parent, false, Enum.Material.Fabric)
	ball(0.42, (cf * CFrame.new(0, 3.98, 0)).Position, Theme.panel, parent)
	cyl(0.44, 0.3, cf * CFrame.new(0, 4.22, 0), V.flowers[5], parent, false, Enum.Material.Fabric)
	shape("Dome", Vector3.new(0.88, 0.45, 0.88), cf * CFrame.new(0, 4.48, 0), V.flowers[5], parent)
	ball(0.17, (cf * CFrame.new(0, 4.78, 0)).Position, Theme.white, parent)
end

-- ---------- booths ----------
-- Booth v4 (owner 2026-11-07: "make the booths look like the thing they are doing", like the best
-- money-making Roblox games). Each booth is a giant version of what it does, the way hit simulators
-- build their shops (Pet Simulator's machines, Bee Swarm's shop huts): Sell = an open treasure chest
-- overflowing with coins, Equipment = a frosty workshop with turning gears, Rebirth = a stone ring
-- portal with a swirling vortex. Something on each moves or sparkles, so it reads as "use me" from
-- across the plaza (World Rules 6). The sign shows only the action, on a board ringed with bulbs.
-- Front = -Z (the plaza). WorldService's invisible counter (10 x 4 x 5 at the booth's pos) sits
-- inside each design, and its sign stands at the booth's `sign` (Config.world.booths).

-- parts the client moves (MapController): a folder tagged Config.mapFx.motionTag. "spin" turns its
-- parts round the Pivot's local Axis at Speed rad/s; "bob" lifts them Amp studs, Hz times a second.
local function motion(parent: Instance, kind: string, pivot: CFrame, attrs: { [string]: any }): Folder
	local f = folder("Motion", parent)
	f:SetAttribute("Kind", kind)
	f:SetAttribute("Pivot", pivot)
	for k, v in attrs do
		f:SetAttribute(k, v)
	end
	CollectionService:AddTag(f, Config.mapFx.motionTag)
	return f
end

-- little glints rising out of a box (coins, a portal's mouth, bubbles in a tank)
local function sparkles(parent: Instance, size: Vector3, cf: CFrame, color: Color3, rate: number, speed: number, dir: Enum.NormalId, big: number?)
	local p = quiet(block(size, cf, color, parent))
	p.Transparency = 1
	p.CanQuery = false
	local e = Instance.new("ParticleEmitter")
	e.Shape = Enum.ParticleEmitterShape.Box
	e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	e.Color = ColorSequence.new(Theme.white, color)
	e.LightEmission = 1
	local s = big or 0.45
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.4, s), NumberSequenceKeypoint.new(1, 0) })
	e.Lifetime = NumberRange.new(0.7, 1.3)
	e.Rate = rate
	e.Speed = NumberRange.new(speed * 0.5, speed)
	e.EmissionDirection = dir
	e.Parent = p
end

-- the board behind a booth's sign, with a trim round its edge and marquee bulbs between the two
-- (UI Rules: a framed, bulb-lit sign). sy / sz = the sign's middle; the board reaches `depth` back
local function signBoard(f: Instance, at: CFrame, sy: number, sz: number, board: Color3, trim: Color3, depth: number, mat: Enum.Material?)
	local BS = W.boothSign
	local w, h = BS.w + 1.6, BS.h + 1.2
	local front = sz + 0.2 - 0.02 -- 0.02 into the sign's back: no flush faces
	block(Vector3.new(w, h, depth), at * CFrame.new(0, sy, front + depth / 2), board, f, false, mat or Enum.Material.Wood)
	for _, s in { -1, 1 } do
		quiet(block(Vector3.new(w + 0.2, 0.22, 0.2), at * CFrame.new(0, sy + s * (h / 2 - 0.05), front - 0.04), trim, f))
		quiet(block(Vector3.new(0.22, h, 0.2), at * CFrame.new(s * (w / 2 - 0.05), sy, front - 0.04), trim, f))
	end
	local function bulb(x: number, y: number)
		quiet(glow(ball(0.13, (at * CFrame.new(x, sy + y, front - 0.1)).Position, A.lanternGlow, f), 0.05))
	end
	for k = -7, 7 do
		bulb(k * 0.66, BS.h / 2 + 0.28)
		bulb(k * 0.66, -BS.h / 2 - 0.28)
	end
	for _, s in { -1, 1 } do
		for _, y in { -0.6, 0, 0.6 } do
			bulb(s * (BS.w / 2 + 0.38), y)
		end
	end
end

-- a cog wheel facing -Z, centred at cf: a rim, square teeth, six spokes and a hub with a bolt
local function cog(parent: Instance, cf: CFrame, r: number, teeth: number, color: Color3, hub: Color3)
	local th = 0.7
	local face = cf * CFrame.Angles(math.pi / 2, 0, 0)
	shape("Ring", Vector3.new(r * 2, th, r * 2), face, color, parent)
	for k = 0, teeth - 1 do
		local a = k / teeth * math.pi * 2
		block(Vector3.new(math.pi * r / teeth, 0.65, th - 0.05), cf * CFrame.Angles(0, 0, a) * CFrame.new(0, r + 0.2, 0), color, parent, false, Enum.Material.Metal)
	end
	for k = 0, 2 do
		block(Vector3.new(r * 0.32, r * 1.5, th - 0.15), cf * CFrame.Angles(0, 0, k * math.pi / 3), color, parent, false, Enum.Material.Metal)
	end
	cyl(r * 0.3, th + 0.25, face, hub, parent)
	cyl(r * 0.12, th + 0.45, face, V.iron, parent)
end

-- a mound of coins: a lumpy gold heap (a few smaller mounds on a big one, so it doesn't read as a
-- smooth dome) covered in loose coins lying tilted, some on their edge
local function coinHeap(f: Instance, cf: CFrame, size: Vector3, n: number, rng: () -> number)
	local gold, goldHi, goldLo = V.gold, V.gold:Lerp(Theme.white, 0.3), V.gold:Lerp(V.barrel, 0.3)
	local heap = ellipsoid(size, cf, goldLo, f) -- a deeper gold under the coins, so they stand out
	local rx, ry, rz = size.X / 2, size.Y / 2, size.Z / 2
	local function surface(s: number): number
		return ry * math.sqrt(1 - s)
	end
	for _ = 1, math.max(2, math.floor(n / 20)) do
		local u, v = rng() * 0.9 - 0.45, rng() * 0.9 - 0.45 -- inside the heap's outline
		local w = 0.25 + rng() * 0.15
		ellipsoid(Vector3.new(size.X * w, size.Y * 0.45, size.Z * w), cf * CFrame.new(u * rx, surface(u * u + v * v) - size.Y * 0.08, v * rz), if rng() < 0.5 then gold else goldLo, f)
	end
	local r = math.clamp(math.min(rx, rz) * 0.1, 0.35, 0.6)
	for _ = 1, n do
		local u, v = rng() * 2 - 1, rng() * 2 - 1
		local s = u * u + v * v
		if s < 0.92 then
			local edge = rng() < 0.12 -- a few stand on their edge
			local tilt = if edge then CFrame.Angles(math.pi / 2, rng() * 6.3, 0) else CFrame.Angles((rng() - 0.5) * 1.1, rng() * 6.3, (rng() - 0.5) * 1.1)
			quiet(cyl(r, 0.16, cf * CFrame.new(u * rx, surface(s) + (if edge then r * 0.6 else 0.06), v * rz) * tilt, if rng() < 0.5 then goldHi else gold, f))
		end
	end
	return heap
end

-- Sell: a giant open treasure chest. Plank walls on gold straps and corner brackets, the shop window
-- cut into its front with the counter, a heap of coins with gems and a crown over the rim, the lid
-- standing open behind it with a tufted red velvet lining, coin piles out front, coin sacks at the side
local function sellBooth(f: Instance, at: CFrame, color: Color3, outer: number, sign: { y: number, z: number }, rng: () -> number)
	local wood, woodB, dark = HA.boothWood, HA.boothWood:Lerp(Theme.ink, 0.18), A.post
	local gold, goldHi, goldLo = V.gold, V.gold:Lerp(Theme.white, 0.3), V.gold:Lerp(Theme.ink, 0.22)
	local velvet = V.flag:Lerp(Theme.ink, 0.3)
	local Wd, y0, top = 16, 0.6, 10 -- the chest's width, floor and rim
	-- its front and back faces. The back stays clear of the village wall (front face at hub z = 0, the
	-- booth stands at z = -8): at 9 the wall's pillar and rails ran through the shop inside
	local fz, bz = -2.6, 6.6
	local mz, D, H = (fz + bz) / 2, bz - fz, top - y0
	local winX, winLo, winHi = 4.6, 3.6, 7.2 -- the shop window in its front
	-- a stone plinth, wide enough for the coin piles out front
	block(Vector3.new(Wd + 3, y0, D + 4.4), at * CFrame.new(0, y0 / 2, mz - 1), V.stoneWarm:Lerp(V.stone, 0.5), f, true, Enum.Material.Cobblestone)
	-- the walls: dark slabs (hollow inside, open at the window) under the plank boards
	local slabs: { { Vector3 } } = {
		{ Vector3.new(Wd, H, 0.6), Vector3.new(0, y0 + H / 2, bz - 0.3) },
		{ Vector3.new(0.6, H, D), Vector3.new(-Wd / 2 + 0.3, y0 + H / 2, mz) },
		{ Vector3.new(0.6, H, D), Vector3.new(Wd / 2 - 0.3, y0 + H / 2, mz) },
		{ Vector3.new(Wd, winLo - y0, 0.6), Vector3.new(0, (y0 + winLo) / 2, fz + 0.3) },
		{ Vector3.new(Wd, top - winHi, 0.6), Vector3.new(0, (winHi + top) / 2, fz + 0.3) },
	}
	for _, s in { -1, 1 } do
		table.insert(slabs, { Vector3.new(Wd / 2 - winX, winHi - winLo, 0.6), Vector3.new(s * (Wd / 2 + winX) / 2, (winLo + winHi) / 2, fz + 0.3) })
	end
	for _, s in slabs do
		block(s[1], at * CFrame.new(s[2]), dark, f, true, Enum.Material.Wood)
	end
	block(Vector3.new(Wd - 1.2, 0.4, D - 1.2), at * CFrame.new(0, winHi + 0.2, mz), dark, f, false, Enum.Material.Wood) -- the ceiling under the coins
	quiet(block(Vector3.new(Wd - 1.2, 0.1, D - 1.2), at * CFrame.new(0, y0 + 0.75, mz), A.plank, f, false, Enum.Material.WoodPlanks)) -- the floor, above the foot band
	-- plank boards in rows, dark seams between them; the front ones stop at the window
	local pitch = H / 10
	for i = 0, 9 do
		local y = y0 + (i + 0.5) * pitch
		local c = (if i % 2 == 0 then wood else woodB):Lerp(Theme.ink, rng() * 0.06)
		local bh = pitch - 0.08
		block(Vector3.new(Wd + 0.3, bh, 0.3), at * CFrame.new(0, y, bz + 0.12), c, f, false, Enum.Material.WoodPlanks)
		for _, s in { -1, 1 } do
			block(Vector3.new(0.3, bh, D + 0.3), at * CFrame.new(s * (Wd / 2 + 0.12), y, mz), c, f, false, Enum.Material.WoodPlanks)
		end
		if y > winLo and y < winHi then
			for _, s in { -1, 1 } do
				block(Vector3.new(Wd / 2 - winX + 0.15, bh, 0.3), at * CFrame.new(s * (Wd / 2 + winX + 0.15) / 2, y, fz - 0.12), c, f, false, Enum.Material.WoodPlanks)
			end
		else
			block(Vector3.new(Wd + 0.3, bh, 0.3), at * CFrame.new(0, y, fz - 0.12), c, f, false, Enum.Material.WoodPlanks)
		end
	end
	-- gold: a band round the foot and the rim, straps beside the window, brackets round the corners,
	-- all studded with rivets (every gold face stands 0.15 clear of the next: no flicker)
	for _, y in { y0 + 0.35, top - 0.35 } do
		block(Vector3.new(Wd + 0.9, 0.7, D + 0.9), at * CFrame.new(0, y, mz), gold, f, true)
	end
	for _, s in { -1, 1 } do
		block(Vector3.new(0.9, H, 0.3), at * CFrame.new(s * (winX + 0.55), y0 + H / 2, fz - 0.45), gold, f)
		for _, z in { fz, bz } do
			local zs = if z == fz then -1 else 1
			block(Vector3.new(1.8, H + 0.2, 0.3), at * CFrame.new(s * (Wd / 2 - 0.3), y0 + H / 2, z + zs * 0.45), gold, f)
			block(Vector3.new(0.3, H + 0.2, 1.5), at * CFrame.new(s * (Wd / 2 + 0.45), y0 + H / 2, z - zs * 0.45), gold, f)
		end
		for k = 0, 7 do
			local y = y0 + 1 + k * 1.1
			quiet(ball(0.14, (at * CFrame.new(s * (winX + 0.55), y, fz - 0.62)).Position, goldLo, f))
			quiet(ball(0.14, (at * CFrame.new(s * (Wd / 2 - 0.3), y, fz - 0.62)).Position, goldLo, f))
		end
	end
	-- the sign on a dark board with a gold trim, over the window
	signBoard(f, at, sign.y, sign.z, dark, gold, (fz - 0.25) - (sign.z + 0.18))
	-- the counter in the window: coin stacks, a service bell and a balance scale with coins on one pan
	local ct = winLo + 0.35
	block(Vector3.new(winX * 2, 0.35, 1.9), at * CFrame.new(0, winLo + 0.17, fz - 0.25), dark, f, false, Enum.Material.Wood)
	for k = 0, 3 do
		for h = 0, k % 3 + 1 do
			cyl(0.42, 0.17, at * CFrame.new(-3.6 + k * 0.75, ct + 0.09 + h * 0.19, fz - 0.6), if h % 2 == 0 then gold else goldHi, f)
		end
	end
	local bell = at * CFrame.new(-0.4, ct, fz - 0.8)
	cyl(0.42, 0.12, bell * CFrame.new(0, 0.06, 0), V.iron, f)
	shape("Dome", Vector3.new(0.75, 0.45, 0.75), bell * CFrame.new(0, 0.34, 0), gold, f)
	ball(0.09, (bell * CFrame.new(0, 0.62, 0)).Position, goldLo, f)
	local sc = at * CFrame.new(2.9, ct, fz - 0.5)
	cyl(0.3, 0.15, sc * CFrame.new(0, 0.08, 0), gold, f)
	cyl(0.08, 1.4, sc * CFrame.new(0, 0.85, 0), gold, f)
	block(Vector3.new(1.8, 0.1, 0.1), sc * CFrame.new(0, 1.55, 0) * CFrame.Angles(0, 0, 0.12), gold, f)
	for _, x in { -0.85, 0.85 } do
		local py = 0.9 - x * 0.12
		block(Vector3.new(0.04, 0.6, 0.04), sc * CFrame.new(x, py + 0.35, 0), V.iron, f)
		cyl(0.35, 0.06, sc * CFrame.new(x, py, 0), gold, f)
	end
	cyl(0.22, 0.2, sc * CFrame.new(-0.85, 1.12, 0), goldHi, f)
	-- inside: a velvet drape on the back wall, shelves of gold bars and coin stacks, a warm lamp
	quiet(block(Vector3.new(Wd - 2, winHi - winLo, 0.1), at * CFrame.new(0, (winLo + winHi) / 2, bz - 0.68), velvet, f, false, Enum.Material.Fabric))
	for i, y in { 4.4, 6.0 } do
		block(Vector3.new(Wd - 2.4, 0.25, 1.2), at * CFrame.new(0, y, bz - 1.3), dark, f, false, Enum.Material.Wood)
		if i == 1 then
			for _, x0 in { -3.6, 3.6 } do
				for row = 0, 2 do
					for k = 0, 2 - row do
						block(Vector3.new(1, 0.42, 0.55), at * CFrame.new(x0 + (k - (2 - row) / 2) * 1.05, y + 0.34 + row * 0.42, bz - 1.3), if row % 2 == 0 then gold else goldHi, f)
					end
				end
			end
		else
			for k = 0, 5 do
				for h = 0, (k * 7) % 3 + 1 do
					cyl(0.38, 0.17, at * CFrame.new(-4.5 + k * 1.8, y + 0.22 + h * 0.19, bz - 1.3), if h % 2 == 0 then gold else goldHi, f)
				end
			end
		end
	end
	cyl(0.06, 0.6, at * CFrame.new(0, winHi - 0.3, mz + 1), V.iron, f)
	local lamp = quiet(glow(ball(0.45, (at * CFrame.new(0, winHi - 0.8, mz + 1)).Position, A.lanternGlow, f), 0.05))
	light(lamp, A.lanternGlow, 12, 1.1)
	-- the treasure over the rim: a coin heap with gems, a crown on top, glints rising off it
	local cy = top + 0.1
	local heap = coinHeap(f, at * CFrame.new(0, cy, mz), Vector3.new(Wd - 0.4, 5.6, D - 0.6), 160, rng)
	light(heap, goldHi, 18, 0.9)
	local gems = { A.crystalGlow, V.flowers[1], V.flowers[3], Theme.booths.rebirth, Theme.booths.equipment }
	for k, c in gems do
		local a = k / #gems * math.pi * 2 + 0.5
		local x, z = math.cos(a) * 4.2, math.sin(a) * 2.6
		local s = (x / (Wd / 2 - 0.2)) ^ 2 + (z / (D / 2 - 0.3)) ^ 2
		shape("Octa", Vector3.new(0.8, 1.4, 0.8), at * CFrame.new(x, cy + 2.8 * math.sqrt(1 - s) + 0.3, mz + z) * CFrame.Angles(0.3, a, 0.4), c, f)
	end
	local crown = at * CFrame.new(-1.4, cy + 2.6, mz + 0.4) * CFrame.Angles(0.12, 0.5, -0.1)
	shape("Ring", Vector3.new(2, 0.8, 2), crown * CFrame.new(0, 0.4, 0), gold, f)
	for k = 0, 4 do
		local a = k / 5 * math.pi * 2
		shape("Cone", Vector3.new(0.45, 0.85, 0.45), crown * CFrame.new(math.cos(a) * 0.8, 1.15, math.sin(a) * 0.8), gold, f)
		ball(0.13, (crown * CFrame.new(math.cos(a) * 0.8, 1.62, math.sin(a) * 0.8)).Position, V.flag, f)
		ball(0.12, (crown * CFrame.new(math.cos(a + 0.6) * 0.98, 0.4, math.sin(a + 0.6) * 0.98)).Position, if k % 2 == 0 then V.flag else A.crystalGlow, f)
	end
	sparkles(f, Vector3.new(Wd - 3, 2.4, D - 3), at * CFrame.new(0, cy + 2.4, mz), goldHi, 8, 0.8, Enum.NormalId.Top)
	-- the lid, standing open behind: planks with gold edge bands, a red velvet lining tufted with gold
	-- buttons inside a gold frame, a hasp on its top edge and snow on top
	local hinge = at * CFrame.new(0, top + 0.1, bz + 0.25) * CFrame.Angles(math.rad(10), 0, 0)
	local LW, LH, LT = Wd + 0.6, 12, 1.4
	block(Vector3.new(LW, LH, LT), hinge * CFrame.new(0, LH / 2, LT / 2), wood, f, true, Enum.Material.WoodPlanks)
	local lin = hinge * CFrame.new(0, LH / 2 + 0.1, 0)
	quiet(block(Vector3.new(LW - 2.6, LH - 2.4, 0.2), lin * CFrame.new(0, 0, -0.05), velvet, f, false, Enum.Material.Fabric))
	for _, s in { -1, 1 } do
		block(Vector3.new(0.7, LH - 1.7, 0.26), lin * CFrame.new(s * (LW / 2 - 1.3), 0, -0.12), gold, f)
		block(Vector3.new(LW - 1.9, 0.7, 0.26), lin * CFrame.new(0, s * (LH / 2 - 1.2), -0.12), gold, f)
		block(Vector3.new(0.9, LH + 0.1, LT + 0.3), hinge * CFrame.new(s * (LW / 2 - 0.3), LH / 2, LT / 2), gold, f)
		block(Vector3.new(0.9, LH, 0.2), hinge * CFrame.new(s * (winX + 0.55), LH / 2, LT + 0.12), gold, f) -- straps on its back
	end
	for i = -3, 3 do
		for j = -2, 2 do
			if (i + j) % 2 == 0 then
				quiet(ball(0.13, (lin * CFrame.new(i * 1.75, j * 1.8, -0.18)).Position, goldHi, f))
			end
		end
	end
	block(Vector3.new(LW + 0.3, 0.9, LT + 0.3), hinge * CFrame.new(0, LH - 0.3, LT / 2), gold, f)
	block(Vector3.new(2.4, 2.2, 0.4), hinge * CFrame.new(0, LH + 0.6, 0.35), gold, f)
	quiet(cyl(0.28, 0.1, hinge * CFrame.new(0, LH + 0.95, 0.12) * CFrame.Angles(math.pi / 2, 0, 0), Theme.ink, f))
	quiet(block(Vector3.new(0.16, 0.45, 0.1), hinge * CFrame.new(0, LH + 0.6, 0.12), Theme.ink, f))
	quiet(block(Vector3.new(LW + 0.1, 0.35, LT + 0.2), hinge * CFrame.new(0, LH + 0.3, LT / 2), A.snowA, f, false, Enum.Material.Snow))
	-- coin piles on the plinth's front corners, each with a tall stack
	for _, s in { -1, 1 } do
		local p = at * CFrame.new(s * 7.3, y0, -4.4)
		coinHeap(f, p * CFrame.new(0, 0.1, 0), Vector3.new(2.6, 1.2, 1.9), 18, rng)
		for h = 0, 4 + (if s > 0 then 2 else 0) do
			cyl(0.45, 0.17, p * CFrame.new(-s * 1.7, 0.09 + h * 0.18, 0.3), if h % 2 == 0 then gold else goldHi, f)
		end
	end
	-- coin sacks by the outer wall, a gold coin pressed on each, coins at their feet
	for k, z in { 0.4, 2.6, 4.8 } do
		local sk = at * CFrame.new(outer * (Wd / 2 + 1.9), 0, z) * CFrame.Angles(0, outer * 0.5 + (rng() - 0.5) * 0.4, 0)
		local s = if k == 2 then 1.15 else 0.95
		ellipsoid(Vector3.new(1.9, 2.2, 1.9) * s, sk * CFrame.new(0, 1.05 * s, 0), V.crate, f, Enum.Material.Fabric)
		cyl(0.45 * s, 0.3, sk * CFrame.new(0, 2.15 * s, 0), goldLo, f)
		ellipsoid(Vector3.new(1.1, 0.7, 1.1) * s, sk * CFrame.new(0, 2.45 * s, 0), V.crate, f, Enum.Material.Fabric)
		cyl(0.42 * s, 0.1, sk * CFrame.new(0, 1.1 * s, -0.93 * s) * CFrame.Angles(math.pi / 2, 0, 0), gold, f)
		quiet(cyl(0.35, 0.12, sk * CFrame.new(0.6, 0.06, -1.2), goldHi, f))
	end
	-- snow drifted against the back corners
	for _, x in { -Wd / 2 - 0.4, Wd / 2 + 0.4 } do
		quiet(ellipsoid(Vector3.new(2.6, 1.2, 3), at * CFrame.new(x, 0.4, bz + 0.4), A.snowA, f))
	end
end

-- Equipment: a frosty workshop. Stone pillars and a stone foot under pale-blue painted boards, a
-- snowy roof, two big gears turning on the front gable, an open front with a roll-up shutter over a
-- workbench (vise with an ice ingot, a toolbox, Slow Gel jars), a pegboard of tools and ice rays,
-- a cryo tank bubbling at the side, a steam pipe puffing, an anvil and the gear mannequin out front
local function equipmentBooth(f: Instance, at: CFrame, color: Color3, outer: number, sign: { y: number, z: number }, rng: () -> number)
	local dark, steel = A.post, V.stone:Lerp(Theme.white, 0.15)
	local brass = V.gold:Lerp(V.barrel, 0.25)
	local paint = color:Lerp(Theme.white, 0.62)
	local Wd, y0, H = 16, 0.6, 9.4
	local fz, bz = -2.6, 6.6 -- clear of the village wall, as the Sell chest (at 9.4 the roof and back sat in it)
	local eave = y0 + H
	local mz, D = (fz + bz) / 2, bz - fz
	local opX, opHi = 5.4, 7 -- the open front
	local stoneTop = y0 + 2.4
	block(Vector3.new(Wd + 3, y0, D + 4.4), at * CFrame.new(0, y0 / 2, mz - 1), V.stone:Lerp(V.stoneWarm, 0.3), f, true, Enum.Material.Slate)
	-- the walls: dark slabs under the cladding, open at the front
	local slabs: { { Vector3 } } = {
		{ Vector3.new(Wd, H, 0.6), Vector3.new(0, y0 + H / 2, bz - 0.3) },
		{ Vector3.new(0.6, H, D), Vector3.new(-Wd / 2 + 0.3, y0 + H / 2, mz) },
		{ Vector3.new(0.6, H, D), Vector3.new(Wd / 2 - 0.3, y0 + H / 2, mz) },
		{ Vector3.new(Wd, eave - opHi, 0.6), Vector3.new(0, (opHi + eave) / 2, fz + 0.3) },
	}
	for _, s in { -1, 1 } do
		table.insert(slabs, { Vector3.new(Wd / 2 - opX, opHi - y0, 0.6), Vector3.new(s * (Wd / 2 + opX) / 2, (y0 + opHi) / 2, fz + 0.3) })
	end
	for _, s in slabs do
		block(s[1], at * CFrame.new(s[2]), dark, f, true, Enum.Material.Wood)
	end
	quiet(block(Vector3.new(Wd - 1.2, 0.1, D - 1.2), at * CFrame.new(0, y0 + 0.05, mz), A.plank, f, false, Enum.Material.WoodPlanks))
	-- a stone course round the foot, painted vertical boards above it, dark corner posts
	block(Vector3.new(Wd + 0.5, stoneTop - y0, 0.5), at * CFrame.new(0, (y0 + stoneTop) / 2, bz + 0.1), V.stoneDark, f, false, Enum.Material.Cobblestone)
	for _, s in { -1, 1 } do
		block(Vector3.new(0.5, stoneTop - y0, D + 0.5), at * CFrame.new(s * (Wd / 2 + 0.1), (y0 + stoneTop) / 2, mz), V.stoneDark, f, false, Enum.Material.Cobblestone)
	end
	local function boards(len: number, cf: CFrame, lo: number)
		local n = math.floor(len)
		for k = 0, n - 1 do
			local c = paint:Lerp(Theme.white, if k % 2 == 0 then 0 else 0.3)
			block(Vector3.new(len / n - 0.1, eave - lo, 0.25), cf * CFrame.new(-len / 2 + (k + 0.5) * len / n, (lo + eave) / 2, 0), c, f, false, Enum.Material.WoodPlanks)
		end
	end
	boards(Wd, at * CFrame.new(0, 0, bz + 0.1), stoneTop)
	for _, s in { -1, 1 } do
		boards(D, at * CFrame.new(s * (Wd / 2 + 0.1), 0, mz) * CFrame.Angles(0, math.pi / 2, 0), stoneTop)
		block(Vector3.new(0.7, H, 0.7), at * CFrame.new(s * (Wd / 2 + 0.15), y0 + H / 2, bz + 0.15), dark, f, false, Enum.Material.Wood)
		-- the stone pillars either side of the open front
		block(Vector3.new(Wd / 2 - opX + 0.35, H, 0.5), at * CFrame.new(s * (opX + Wd / 2 + 0.35) / 2, y0 + H / 2, fz - 0.15), V.stone, f, true, Enum.Material.Cobblestone)
	end
	-- the front over the opening: a dark lintel, painted boards, the sign on a dark board
	block(Vector3.new(opX * 2 + 0.6, 0.6, 0.5), at * CFrame.new(0, opHi + 0.3, fz - 0.1), dark, f, false, Enum.Material.Wood)
	boards(opX * 2, at * CFrame.new(0, 0, fz - 0.05), opHi + 0.6)
	signBoard(f, at, sign.y, sign.z, dark, color, (fz - 0.1) - (sign.z + 0.18))
	-- the roll-up shutter: the rolled drum and its last slat, striped, with a handle
	log(opX * 2 + 0.2, 0.45, at * CFrame.new(0, opHi - 0.45, fz - 0.7), steel, f)
	for _, s in { -1, 1 } do
		block(Vector3.new(0.3, 0.9, 0.9), at * CFrame.new(s * (opX + 0.05), opHi - 0.45, fz - 0.6), V.iron, f)
	end
	for k = 0, 9 do
		local w = (opX * 2 - 0.4) / 10
		block(Vector3.new(w, 0.42, 0.12), at * CFrame.new(-opX + 0.2 + (k + 0.5) * w, opHi - 1.1, fz - 0.7), if k % 2 == 0 then color else Theme.white, f, false, Enum.Material.Metal)
	end
	block(Vector3.new(1.2, 0.12, 0.2), at * CFrame.new(0, opHi - 1.38, fz - 0.78), V.iron, f)
	-- the workbench across the opening: drawers in front, a vise holding a glowing ice ingot, a
	-- toolbox and jars of Slow Gel on top
	local bt = y0 + 3.2 -- the bench top
	block(Vector3.new(opX * 2 - 0.2, 0.4, 1.9), at * CFrame.new(0, bt + 0.2, fz - 0.15), dark, f, false, Enum.Material.Wood)
	block(Vector3.new(opX * 2 - 0.6, bt - y0, 0.3), at * CFrame.new(0, (y0 + bt) / 2, fz - 0.1), paint:Lerp(color, 0.35), f, false, Enum.Material.WoodPlanks)
	for _, y in { y0 + 0.9, y0 + 2.2 } do
		for _, x in { -3.2, 0, 3.2 } do
			quiet(block(Vector3.new(2.7, 1, 0.1), at * CFrame.new(x, y, fz - 0.3), paint, f, false, Enum.Material.WoodPlanks))
			quiet(block(Vector3.new(0.7, 0.14, 0.12), at * CFrame.new(x, y + 0.15, fz - 0.4), V.iron, f))
		end
	end
	local top = bt + 0.4
	local vise = at * CFrame.new(-4.1, top, fz - 0.3)
	block(Vector3.new(1.2, 0.35, 0.9), vise * CFrame.new(0, 0.17, 0), V.iron, f)
	for _, x in { -0.42, 0.42 } do
		block(Vector3.new(0.3, 0.7, 0.8), vise * CFrame.new(x, 0.7, 0), steel, f, false, Enum.Material.Metal)
	end
	log(1.8, 0.08, vise * CFrame.new(0.5, 0.6, 0), V.iron, f)
	local ingot = quiet(glow(block(Vector3.new(0.5, 0.4, 0.7), vise * CFrame.new(0, 0.75, 0), A.crystalGlow, f), 0.05))
	light(ingot, A.crystalGlow, 8, 0.7)
	local tb = at * CFrame.new(3.6, top, fz - 0.4) * CFrame.Angles(0, -0.15, 0)
	block(Vector3.new(1.7, 0.8, 0.85), tb * CFrame.new(0, 0.4, 0), V.flag, f)
	block(Vector3.new(1.8, 0.15, 0.9), tb * CFrame.new(0, 0.86, 0), V.flag:Lerp(Theme.ink, 0.2), f)
	block(Vector3.new(0.9, 0.12, 0.12), tb * CFrame.new(0, 1.25, 0), V.iron, f)
	for _, x in { -0.4, 0.4 } do
		block(Vector3.new(0.1, 0.35, 0.1), tb * CFrame.new(x, 1.08, 0), V.iron, f)
	end
	for k = 0, 2 do
		local j = at * CFrame.new(0.9 + k * 0.75, top, fz - 0.35)
		local glass = cyl(0.28, 0.62, j * CFrame.new(0, 0.31, 0), Theme.round5.gel, f)
		glass.Transparency = 0.25
		cyl(0.31, 0.14, j * CFrame.new(0, 0.68, 0), A.post, f, false, Enum.Material.Wood)
	end
	-- the back wall: a pegboard with a wrench, a hammer and a screwdriver, three ice rays on pegs
	local pz = bz - 0.75
	block(Vector3.new(Wd - 2.4, 4.6, 0.2), at * CFrame.new(0, y0 + 4.3, pz), A.plank:Lerp(Theme.white, 0.35), f, false, Enum.Material.WoodPlanks)
	for i = 0, 11 do
		for j = 0, 3 do
			quiet(block(Vector3.new(0.12, 0.12, 0.06), at * CFrame.new(-6 + i * 1.09, y0 + 2.6 + j * 1.15, pz - 0.12), dark, f))
		end
	end
	local tz = pz - 0.2
	local wr = at * CFrame.new(-5, y0 + 4.7, tz) * CFrame.Angles(0, 0, 0.25)
	block(Vector3.new(0.32, 2, 0.14), wr, steel, f, false, Enum.Material.Metal)
	shape("Ring", Vector3.new(0.95, 0.18, 0.95), wr * CFrame.new(0, 1.2, 0) * CFrame.Angles(math.pi / 2, 0, 0), steel, f)
	local hm = at * CFrame.new(-3.4, y0 + 4.6, tz) * CFrame.Angles(0, 0, -0.15)
	block(Vector3.new(0.26, 1.9, 0.14), hm, A.plank, f, false, Enum.Material.Wood)
	block(Vector3.new(1.1, 0.42, 0.3), hm * CFrame.new(0, 0.95, 0), V.iron, f)
	local sd = at * CFrame.new(-2, y0 + 4.6, tz)
	cyl(0.18, 0.8, sd * CFrame.new(0, 0.4, 0), V.flag, f)
	cyl(0.06, 0.9, sd * CFrame.new(0, -0.45, 0), steel, f)
	for k = 0, 2 do
		local g = at * CFrame.new(0.8 + k * 1.9, y0 + 4.6, tz)
		block(Vector3.new(1.5, 0.55, 0.55), g, Theme.fx.gunBody, f)
		cyl(0.2, 0.5, g * CFrame.new(-0.3, 0.45, 0), (Theme.guns[k * 2 + 1] or Theme.guns[1]).glow, f)
		quiet(glow(ball(0.26, (g * CFrame.new(0.9, 0, 0)).Position, (Theme.guns[k * 2 + 1] or Theme.guns[1]).glow, f), 0.05))
	end
	-- an iron lamp with a shade hanging over the bench
	cyl(0.06, 2.2, at * CFrame.new(0, eave - 1.1, mz - 1), V.iron, f)
	shape("Dome", Vector3.new(1.6, 0.9, 1.6), at * CFrame.new(0, eave - 2.4, mz - 1), V.iron, f)
	local bulb = quiet(glow(ball(0.35, (at * CFrame.new(0, eave - 2.65, mz - 1)).Position, A.lanternGlow, f), 0.05))
	light(bulb, A.lanternGlow, 14, 1.1)
	-- the roof: dark slabs under deep snow, icicles, barge boards in the booth's colour, plank gables
	local side, rise = 0.6, 6
	local eaveX = Wd / 2 + side
	local theta = math.atan2(rise, eaveX)
	local slopeLen = math.sqrt(eaveX * eaveX + rise * rise)
	local zFront, zBack = fz - 1.6, bz + 1
	local roofLen, roofZ = zBack - zFront, (zFront + zBack) / 2
	local eaveEdgeY = eave - side * rise / eaveX
	for _, sgn in { -1, 1 } do
		local mid = at * CFrame.new(sgn * eaveX / 2, eaveEdgeY + rise / 2, roofZ) * CFrame.Angles(0, 0, -sgn * theta)
		block(Vector3.new(slopeLen + 0.4, 0.6, roofLen), mid, color:Lerp(Theme.ink, 0.45), f, false, Enum.Material.Metal)
		quiet(block(Vector3.new(slopeLen - 0.2, 0.7, roofLen - 0.4), mid * CFrame.new(0, 0.62, 0), A.snowA, f, false, Enum.Material.Snow))
		quiet(cyl(0.55, roofLen - 0.4, at * CFrame.new(sgn * (eaveX - 0.2), eaveEdgeY + 0.55, roofZ) * CFrame.Angles(math.pi / 2, 0, 0), A.snowA, f, false, Enum.Material.Snow))
		for k = 0, 6 do
			local len = 0.5 + ((k + (sgn + 1)) % 3) * 0.35
			local ice = quiet(shape("Cone", Vector3.new(0.32, len, 0.32), at * CFrame.new(sgn * (eaveX - 0.1), eaveEdgeY - 0.2 - len / 2, zFront + 1 + k * (roofLen - 2) / 6) * CFrame.Angles(math.pi, 0, 0), A.crystal, f))
			ice.Material = Enum.Material.Ice
		end
		local edge = at * CFrame.new(sgn * eaveX / 2, eaveEdgeY + rise / 2, zFront - 0.15) * CFrame.Angles(0, 0, -sgn * theta)
		block(Vector3.new(slopeLen + 0.6, 0.55, 0.45), edge * CFrame.new(0, 0.1, 0), color, f)
		for _, z in { fz + 0.2, bz - 0.2 } do
			wedge(Vector3.new(0.4, rise - 0.3, Wd / 2), at * CFrame.new(sgn * Wd / 4, eave + (rise - 0.3) / 2, z) * CFrame.Angles(0, -sgn * math.pi / 2, 0), paint, f, Enum.Material.WoodPlanks)
		end
	end
	quiet(cyl(0.75, roofLen + 0.4, at * CFrame.new(0, eaveEdgeY + rise + 0.75, roofZ) * CFrame.Angles(math.pi / 2, 0, 0), A.snowA, f, false, Enum.Material.Snow))
	-- two meshed gears on the front gable, out in front of the roof's edge, each on an iron axle back
	-- into the gable; the client turns them (the small one the other way, faster). The small one sits
	-- low beside the big one, inside the gable's outline, its teeth clear of the sign's bulbs.
	local gz = zFront - 0.9
	local big, small = 3, 1.8
	local bigAt = at * CFrame.new(-outer * 1.2, sign.y + 3.05 + big, gz)
	local a = if outer > 0 then math.rad(-25) else math.rad(205)
	local dist = big + small + 0.15
	local smallAt = bigAt * CFrame.new(math.cos(a) * dist, math.sin(a) * dist, -0.3)
	cog(motion(f, "spin", bigAt, { Axis = Vector3.new(0, 0, 1), Speed = 0.5 }), bigAt, big, 14, V.iron:Lerp(Theme.white, 0.45), color)
	cog(motion(f, "spin", smallAt, { Axis = Vector3.new(0, 0, 1), Speed = -0.5 * 14 / 8 }), smallAt, small, 8, brass, brass:Lerp(Theme.ink, 0.2))
	for _, g in { bigAt, smallAt } do
		local len = fz - g.Position.Z + at.Position.Z
		cyl(0.35, len, g * CFrame.new(0, 0, len / 2) * CFrame.Angles(math.pi / 2, 0, 0), V.iron, f)
	end
	-- a cryo tank bubbling at the outer side, piped into the wall
	local tk = at * CFrame.new(outer * (Wd / 2 + 2), 0, 1.2)
	cyl(1.6, 0.8, tk * CFrame.new(0, 0.4, 0), V.iron, f, true) -- taller than the plinth (flush tops flicker)
	local tank = cyl(1.25, 4.4, tk * CFrame.new(0, 0.8 + 2.2, 0), A.crystal, f, true)
	tank.Transparency = 0.5
	local liquid = quiet(glow(cyl(1.05, 3.4, tk * CFrame.new(0, 0.8 + 2, 0), A.crystalGlow, f), 0.25))
	light(liquid, A.crystalGlow, 12, 0.9)
	for _, y in { 2.4, 3.9 } do
		quiet(cyl(1.32, 0.18, tk * CFrame.new(0, y, 0), steel, f))
	end
	cyl(1.4, 0.5, tk * CFrame.new(0, 5.45, 0), V.iron, f)
	shape("Dome", Vector3.new(2.6, 0.9, 2.6), tk * CFrame.new(0, 6.1, 0), steel, f)
	log(2.3, 0.28, tk * CFrame.new(-outer * 1.4, 5.3, 0), steel, f)
	ball(0.4, (tk * CFrame.new(-outer * 0.3, 5.3, 0)).Position, steel, f)
	cyl(0.45, 0.12, tk * CFrame.new(0, 3.1, -1.3) * CFrame.Angles(math.pi / 2, 0, 0), Theme.white, f) -- a gauge
	quiet(block(Vector3.new(0.06, 0.35, 0.05), tk * CFrame.new(0.08, 3.18, -1.4) * CFrame.Angles(0, 0, -0.6), Theme.ink, f))
	sparkles(f, Vector3.new(1.4, 0.4, 1.4), tk * CFrame.new(0, 1.2, 0), Theme.white, 5, 2, Enum.NormalId.Top, 0.25)
	-- a steam pipe at the back corner, puffing
	local pipe = at * CFrame.new(outer * (Wd / 2 + 0.9), 0, bz - 1.5)
	cyl(0.55, 15, pipe * CFrame.new(0, 7.5, 0), V.iron, f, true)
	for k = 1, 4 do
		quiet(cyl(0.62, 0.25, pipe * CFrame.new(0, k * 3.2, 0), brass, f))
	end
	cyl(0.8, 0.5, pipe * CFrame.new(0, 15.2, 0), V.iron, f)
	local steamAt = quiet(block(Vector3.one * 0.3, pipe * CFrame.new(0, 15.8, 0), V.stone, f))
	steamAt.Transparency = 1
	local steam = Instance.new("ParticleEmitter")
	steam.Color = ColorSequence.new(Theme.white)
	steam.Transparency = NumberSequence.new(0.3, 1)
	steam.Size = NumberSequence.new(0.8, 2.4)
	steam.Lifetime = NumberRange.new(1.4, 2.2)
	steam.Speed = NumberRange.new(2, 3.5)
	steam.Rate = 4
	steam.EmissionDirection = Enum.NormalId.Top
	steam.Parent = steamAt
	-- an anvil out front with an ice ingot cooling on it and a hammer, the gear mannequin opposite
	local av = at * CFrame.new(-outer * 6.3, y0, -4.4) * CFrame.Angles(0, -outer * 0.3, 0)
	local anvil = V.iron:Lerp(Theme.white, 0.15)
	block(Vector3.new(1.6, 0.5, 1.1), av * CFrame.new(0, 0.25, 0), V.iron, f, true)
	block(Vector3.new(0.8, 0.9, 0.7), av * CFrame.new(0, 0.95, 0), V.iron, f)
	block(Vector3.new(2, 0.55, 0.95), av * CFrame.new(0.15, 1.65, 0), anvil, f, true, Enum.Material.Metal)
	shape("Cone", Vector3.new(0.75, 1.1, 0.6), av * CFrame.new(-1.4, 1.7, 0) * CFrame.Angles(0, 0, math.pi / 2), anvil, f)
	local cool = quiet(glow(block(Vector3.new(0.9, 0.3, 0.45), av * CFrame.new(0.3, 2.07, -0.1) * CFrame.Angles(0, 0.3, 0), A.crystalGlow, f), 0.05))
	light(cool, A.crystalGlow, 8, 0.7)
	local hcf = av * CFrame.new(0.4, 2.05, 0.3) * CFrame.Angles(0, -0.5, 0)
	block(Vector3.new(1.6, 0.2, 0.2), hcf, A.plank, f, false, Enum.Material.Wood)
	block(Vector3.new(0.4, 0.4, 0.85), hcf * CFrame.new(0.85, 0.05, 0), V.iron, f)
	mannequin(f, at * CFrame.new(outer * 6.2, y0, -4.2) * CFrame.Angles(0, outer * 0.35, 0))
	crate(f, at * CFrame.new(outer * (Wd / 2 + 1.9), 0.6, 4.8) * CFrame.Angles(0, 0.3, 0), 1.4)
	for _, x in { -Wd / 2 - 0.4, Wd / 2 + 0.4 } do
		quiet(ellipsoid(Vector3.new(2.6, 1.2, 3), at * CFrame.new(x, 0.4, bz + 0.6), A.snowA, f))
	end
	local _ = rng
end

-- Rebirth: a stone ring portal on a round dais. The ring is cut stones with glowing runes and snow
-- on top, the sign on a stone tablet over its keystone; inside it a dark vortex with two layers of
-- spiral arms turning opposite ways and a bright heart, sparkles drifting out. In front an altar with
-- a draped cloth, an open spell book, a floating spark and candles; purple fire in two braziers;
-- crystals floating either side of the ring; a ring of rune tiles in the floor
local function rebirthBooth(f: Instance, at: CFrame, color: Color3, outer: number, sign: { y: number, z: number }, rng: () -> number)
	local pale, deep = color:Lerp(Theme.white, 0.5), color:Lerp(Theme.ink, 0.5)
	local y1, dz = 1, 2.4 -- the dais top and centre
	cyl(8.6, 0.5, at * CFrame.new(0, 0.25, dz), V.stoneDark, f, true, Enum.Material.Slate)
	cyl(7.3, 0.5, at * CFrame.new(0, 0.75, dz), V.stone, f, true, Enum.Material.Slate)
	for k = 0, 23 do
		local a = k / 24 * math.pi * 2
		local big = k % 3 == 0
		quiet(glow(block(Vector3.new(if big then 0.7 else 1.3, 0.06, if big then 0.7 else 0.28), at * CFrame.new(0, y1 + 0.03, dz) * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, 6.5) * CFrame.Angles(0, if big then math.pi / 4 else 0, 0), pale, f), 0.3))
	end
	-- the ring of stones round the opening, every other one carved with a glowing rune
	local R = 5.4
	local pc = at * CFrame.new(0, y1 + R + 0.8, 5.4)
	local N = 20
	for k = 0, N - 1 do
		local a = k / N * math.pi * 2
		local seg = pc * CFrame.Angles(0, 0, a) * CFrame.new(0, R + 0.8, 0)
		block(Vector3.new(2 * math.pi * (R + 0.8) / N + 0.05, 1.6, 2), seg, if k % 2 == 0 then V.stone else V.stoneDark, f, true, Enum.Material.Slate)
		if k % 2 == 0 then
			quiet(glow(block(Vector3.new(0.5, 0.7, 0.12), seg * CFrame.new(0, 0, -1.02) * CFrame.Angles(0, 0, if k % 4 == 0 then math.pi / 4 else 0), pale, f), 0.1))
		end
		if math.cos(a) > 0.75 then
			quiet(ellipsoid(Vector3.new(2.2, 0.5, 2.1), seg * CFrame.new(0, 0.85, 0), A.snowA, f))
		end
	end
	for _, s in { -1, 1 } do
		block(Vector3.new(2.2, 2.2, 2.6), at * CFrame.new(s * 4.6, y1 + 1.1, 5.4), V.stoneDark, f, true, Enum.Material.Slate) -- the ring's feet
	end
	signBoard(f, at, sign.y, sign.z, V.stoneDark, color, 0.9, Enum.Material.Slate)
	-- the vortex: a dark disc, two layers of spiral arms turning opposite ways, a bright heart
	local face = pc * CFrame.Angles(math.pi / 2, 0, 0)
	glow(cyl(R + 0.1, 0.3, face, deep, f), 0.05)
	local function arms(n: number, r0: number, r1: number, z: number, twist: number, speed: number, colors: { Color3 })
		local m = motion(f, "spin", pc, { Axis = Vector3.new(0, 0, 1), Speed = speed })
		for arm = 0, n - 1 do
			for j = 0, 9 do
				local t = j / 9
				local seg = pc * CFrame.Angles(0, 0, arm * math.pi * 2 / n + t * twist) * CFrame.new(0, r0 + t * (r1 - r0), z)
				quiet(glow(ellipsoid(Vector3.new(1.3 - t * 0.5, 0.5 - t * 0.15, 0.1), seg, colors[j % #colors + 1], m), 0.1 + t * 0.35))
			end
		end
	end
	arms(4, 0.8, R - 0.4, -0.25, 2.6, 1.1, { pale, color })
	arms(3, 0.5, 2.8, -0.35, -2, -1.8, { Theme.white, pale })
	local heart = quiet(glow(ball(0.9, (pc * CFrame.new(0, 0, -0.3)).Position, Theme.white, f), 0.05))
	light(heart, color, 16, 1) -- brighter washed the dais out
	sparkles(f, Vector3.new(R * 1.6, R * 1.6, 0.2), pc * CFrame.new(0, 0, -0.5), pale, 10, 2, Enum.NormalId.Front)
	-- crystals floating either side of the ring
	for k, p in { Vector2.new(-7.4, 9.6), Vector2.new(7.4, 9.6), Vector2.new(-7.9, 4.8), Vector2.new(7.9, 4.8) } do
		local cf = at * CFrame.new(p.X, y1 + p.Y, 5.4)
		local m = motion(f, "bob", cf, { Amp = 0.5, Hz = 0.35, Phase = k * 0.27 })
		local c = glow(shape("Octa", Vector3.new(1.1, 2.4, 1.1), cf * CFrame.Angles(0, k, (if p.X < 0 then 1 else -1) * 0.15), if k <= 2 then color else pale, m), 0.15)
		glow(shape("Octa", Vector3.new(0.45, 0.9, 0.45), cf * CFrame.new(if p.X < 0 then -0.9 else 0.9, -0.9, 0), pale, m), 0.15)
		if k <= 2 then
			light(c, color, 10, 0.8)
		end
	end
	-- the altar: stone with a cloth runner, rune circles on its front, an open spell book, candles
	local al = at * CFrame.new(0, y1, -0.4)
	block(Vector3.new(5.2, 2.4, 2.2), al * CFrame.new(0, 1.2, 0), V.stone, f, true, Enum.Material.Slate)
	block(Vector3.new(5.8, 0.4, 2.7), al * CFrame.new(0, 2.6, 0), V.stoneWarm, f, true, Enum.Material.Slate)
	block(Vector3.new(5.8, 0.4, 2.7), al * CFrame.new(0, 0.2, 0), V.stoneDark, f, true, Enum.Material.Slate)
	quiet(block(Vector3.new(1.9, 0.06, 2.9), al * CFrame.new(0, 2.83, 0), color, f, false, Enum.Material.Fabric))
	quiet(block(Vector3.new(1.9, 1.6, 0.06), al * CFrame.new(0, 2.05, -1.42), color, f, false, Enum.Material.Fabric))
	quiet(block(Vector3.new(1.9, 0.14, 0.1), al * CFrame.new(0, 1.25, -1.44), V.gold, f))
	for _, s in { -1, 1 } do
		quiet(glow(shape("Ring", Vector3.new(1.2, 0.1, 1.2), al * CFrame.new(s * 1.75, 1.3, -1.13) * CFrame.Angles(math.pi / 2, 0, 0), pale, f), 0.1))
	end
	local book = al * CFrame.new(0, 2.92, 0.1) * CFrame.Angles(math.rad(-12), 0, 0)
	block(Vector3.new(1.8, 0.1, 1.3), book, deep, f)
	for _, x in { -0.43, 0.43 } do
		block(Vector3.new(0.82, 0.12, 1.15), book * CFrame.new(x, 0.09, 0) * CFrame.Angles(0, 0, x * 0.28), Theme.panel, f)
	end
	local sparkAt = book * CFrame.new(0, 1.1, 0)
	local spark = quiet(glow(shape("Octa", Vector3.new(0.5, 0.8, 0.5), sparkAt, A.crystalGlow, motion(f, "bob", sparkAt, { Amp = 0.25, Hz = 0.6, Phase = 0 })), 0.1))
	light(spark, color, 8, 0.7)
	for _, x in { -2.5, -1.95, 1.95, 2.5 } do
		local h = if math.abs(x) > 2.2 then 0.5 else 0.85
		local c = al * CFrame.new(x, 2.8, 0.3)
		cyl(0.15, h, c * CFrame.new(0, h / 2, 0), Theme.panel, f)
		quiet(glow(shape("Octa", Vector3.new(0.18, 0.32, 0.18), c * CFrame.new(0, h + 0.18, 0), A.lanternGlow, f), 0.05))
	end
	-- braziers of purple fire either side of the altar, on the lower step
	for _, s in { -1, 1 } do
		local bp = at * CFrame.new(s * 5.4, 0.5, -2.6)
		cyl(0.75, 0.4, bp * CFrame.new(0, 0.2, 0), V.stoneDark, f, true, Enum.Material.Slate)
		cyl(0.42, 2.4, bp * CFrame.new(0, 1.4, 0), V.stone, f, true, Enum.Material.Slate)
		local bowl = cyl(1, 0.6, bp * CFrame.new(0, 2.9, 0), V.iron, f, true)
		shape("Ring", Vector3.new(2.3, 0.3, 2.3), bp * CFrame.new(0, 3.2, 0), V.gold, f)
		quiet(glow(ellipsoid(Vector3.new(1.5, 0.4, 1.5), bp * CFrame.new(0, 3.2, 0), pale, f), 0.1))
		local fire = Instance.new("Fire")
		fire.Color = color
		fire.SecondaryColor = pale
		fire.Size = 3
		fire.Heat = 7
		fire.Parent = bowl
		light(bowl, color, 10, 0.8)
	end
	for _, p in { { -6.6, 7.2 }, { 6.6, 7.2 } } do
		quiet(ellipsoid(Vector3.new(2.6, 1, 2.6), at * CFrame.new(p[1], 0.6, p[2]), A.snowA, f))
	end
	local _, _ = outer, rng
end

-- the Training Rink's door (Cold Power, 2026-11-10): an igloo of stacked ice rings under a snow cap,
-- an ice porch with a dark doorway rimmed in glowing runes, a big snowflake turning over it and
-- crystals either side. Its prompt takes you up to your own rink in the sky (TrainingService).
local function rinkBooth(f: Instance, at: CFrame, color: Color3, outer: number, sign: { y: number, z: number }, rng: () -> number)
	local T = Theme.rink
	local ice, deep = T.floor, T.floorSide
	local y0 = 0.6
	block(Vector3.new(18, y0, 14), at * CFrame.new(0, y0 / 2, 3), V.stone:Lerp(Theme.white, 0.3), f, true, Enum.Material.Slate)
	-- the igloo: three rings, each smaller, and a cap of snow
	cyl(8, 3.2, at * CFrame.new(0, y0 + 1.6, 3.4), ice, f, true, Enum.Material.Ice)
	cyl(7.1, 2.6, at * CFrame.new(0, y0 + 4.5, 3.4), ice:Lerp(deep, 0.25), f, true, Enum.Material.Ice)
	cyl(5.6, 2, at * CFrame.new(0, y0 + 6.8, 3.4), ice, f, false, Enum.Material.Ice)
	ellipsoid(Vector3.new(8.6, 3.6, 8.6), at * CFrame.new(0, y0 + 8.1, 3.4), Theme.snow, f)
	-- the porch and its doorway, facing the plaza
	local pw, ph, pz = 7.6, 7.2, -2.6
	block(Vector3.new(pw, ph, 4.4), at * CFrame.new(0, y0 + ph / 2, pz), ice:Lerp(deep, 0.12), f, true, Enum.Material.Ice)
	block(Vector3.new(pw + 0.8, 0.7, 5), at * CFrame.new(0, y0 + ph + 0.35, pz), Theme.snow, f)
	local front = pz - 2.2
	quiet(block(Vector3.new(5.4, 6, 0.2), at * CFrame.new(0, y0 + 3, front - 0.05), deep:Lerp(Theme.ink, 0.6), f))
	for _, s in { -1, 1 } do
		quiet(glow(block(Vector3.new(0.35, 6.2, 0.3), at * CFrame.new(s * 2.9, y0 + 3.1, front - 0.12), T.rune, f), 0.1))
		-- crystals either side of the door
		local c = quiet(glow(shape("Octa", Vector3.new(2, 4.6, 2), at * CFrame.new(s * 6.2, y0 + 2.5, front + 0.6), T.crystal, f), 0.15))
		light(c, T.rune, 10, 0.7)
		quiet(glow(shape("Octa", Vector3.new(1.2, 2.6, 1.2), at * CFrame.new(s * 7.6, y0 + 1.5, front - 0.6), T.crystal, f), 0.2))
		-- the posts that carry the sign
		block(Vector3.new(0.5, sign.y - (y0 + ph) - 0.4, 0.5), at * CFrame.new(s * 3.4, (sign.y + y0 + ph + 0.3) / 2, sign.z + 0.7), deep:Lerp(Theme.ink, 0.4), f)
	end
	quiet(glow(block(Vector3.new(6.15, 0.35, 0.3), at * CFrame.new(0, y0 + 6.2, front - 0.12), T.rune, f), 0.1))
	sparkles(f, Vector3.new(4.6, 0.4, 0.8), at * CFrame.new(0, y0 + 0.6, front - 0.8), T.rune, 6, 1.2, Enum.NormalId.Top, 0.3)
	signBoard(f, at, sign.y, sign.z, deep:Lerp(Theme.ink, 0.5), color, 0.6)
	-- the big snowflake over the igloo, turning slowly (MapController moves it)
	local pivot = at * CFrame.new(0, y0 + 13.4, 3.4)
	local m = motion(f, "spin", pivot, { Axis = Vector3.new(0, 0, 1), Speed = 0.4 })
	for k = 0, 2 do
		local arm = pivot * CFrame.Angles(0, 0, k * math.pi / 3)
		quiet(glow(block(Vector3.new(6.4, 0.55, 0.45), arm, T.rune, m), 0.1))
		for _, e in { -1, 1 } do -- the little barbs near each tip
			quiet(glow(block(Vector3.new(0.4, 1.7, 0.4), arm * CFrame.new(e * 2.3, 0, 0), T.rune, m), 0.1))
		end
	end
	light(quiet(glow(ball(0.7, pivot.Position, Theme.white, m), 0.05)), T.rune, 16, 1)
	-- the sky beacon (map pass 2026-11-10): a column of frost light from the snowflake up toward the rinks
	-- in the sky, crowned by a big turning snowflake. The hub's one tall weenie: it says where Cold Power
	-- comes from, and from the first islands it marks the hub
	local B = C.rinkBeacon
	if B then
		local bm = folder("RinkBeacon", f)
		local base = pivot.Position.Y + 2
		local mid = CFrame.new(pivot.Position.X, base + B.height / 2, pivot.Position.Z)
		far(glow(cyl(B.radius, B.height, mid, Theme.white, bm), B.clear))
		far(glow(cyl(B.radius * 1.9, B.height, mid, T.rune, bm), 0.82))
		local top = CFrame.new(pivot.Position.X, base + B.height, pivot.Position.Z)
		far(glow(shape("Ring", Vector3.new(B.haloRadius * 2, 1.2, B.haloRadius * 2), top * CFrame.new(0, -B.height * 0.35, 0), T.rune, bm), 0.2))
		-- upright and facing along the tunnel, so it reads from the plaza and from the islands alike
		local crown = motion(bm, "spin", top, { Axis = Vector3.new(0, 0, 1), Speed = B.crownSpin })
		local arm = B.crownSize / 2
		for k = 0, 2 do
			local a = top * CFrame.Angles(0, 0, k * math.pi / 3)
			far(glow(block(Vector3.new(B.crownSize, 1.6, 1.6), a, T.rune, crown), 0.05))
			for _, e in { -1, 1 } do -- the barbs near each tip
				far(glow(block(Vector3.new(1.2, arm * 0.55, 1.2), a * CFrame.new(e * arm * 0.68, 0, 0), T.rune, crown), 0.05))
			end
		end
		local core = far(glow(ball(2.2, top.Position, Theme.white, crown), 0))
		light(core, T.rune, 40, 2)
		sparkles(bm, Vector3.new(B.radius * 2, 2, B.radius * 2), CFrame.new(pivot.Position.X, base + 2, pivot.Position.Z), T.rune, 10, 18, Enum.NormalId.Top, 1.2)
	end
	local _, _ = outer, rng
end

local function booth(parent: Instance, b: Config.Booth, rng: () -> number)
	local f = folder("Booth_" .. b.id, parent)
	local at = CFrame.new(b.pos.X, 0, b.pos.Z)
	local color = Theme.booths[b.id] or Theme.info
	local outer = if b.pos.X < 0 then -1 else 1 -- the side away from the tunnel mouth
	local sign = b.sign or { y = W.boothSign.y, z = W.boothSign.z }
	if b.id == "sell" then
		sellBooth(f, at, color, outer, sign, rng)
	elseif b.id == "equipment" then
		equipmentBooth(f, at, color, outer, sign, rng)
	elseif b.id == "rebirth" then
		rebirthBooth(f, at, color, outer, sign, rng)
	elseif b.id == "rink" then
		rinkBooth(f, at, color, outer, sign, rng)
	else
		signBoard(f, at, sign.y, sign.z, A.post, color, 0.5)
	end
end

-- a leaderboard's frame: stone pillars with glowing crystal caps, a wooden border, a crown on top
local function boardFrame(parent: Instance, pos: Vector3, i: number)
	local f = folder("BoardFrame" .. i, parent)
	local cf = CFrame.lookAt(Vector3.new(pos.X, 10, pos.Z), Vector3.new(0, 10, pos.Z)) -- the board's own frame (front = -Z)
	for _, x in { -8.4, 8.4 } do
		block(Vector3.new(2.4, 21, 2.4), cf * CFrame.new(x, 0.5, 0.6), V.stone, f, true, Enum.Material.Cobblestone)
		block(Vector3.new(3, 0.8, 3), cf * CFrame.new(x, 11.2, 0.6), V.trim, f)
		block(Vector3.new(3, 1.2, 3), cf * CFrame.new(x, -9.4, 0.6), V.stoneDark, f, false, Enum.Material.Slate) -- taller than the border (flush tops flickered)
		local cap = glow(shape("Octa", Vector3.new(1.6, 3, 1.6), cf * CFrame.new(x, 13.1, 0.6), A.crystalGlow, f), 0.15)
		light(cap, A.crystalGlow, 12, 0.8)
	end
	-- the border round the board (the board is 14 x 18)
	block(Vector3.new(15.6, 1, 1.4), cf * CFrame.new(0, 9.5, 0.3), HA.boothWood, f, false, Enum.Material.WoodPlanks)
	block(Vector3.new(15.6, 1, 1.4), cf * CFrame.new(0, -9.5, 0.3), HA.boothWood, f, false, Enum.Material.WoodPlanks)
	for _, x in { -7.4, 7.4 } do
		block(Vector3.new(0.9, 19, 1.4), cf * CFrame.new(x, 0, 0.3), HA.boothWood, f, false, Enum.Material.WoodPlanks)
	end
	-- a gold crown over the middle
	local crown = cf * CFrame.new(0, 11, 0.3)
	block(Vector3.new(3.6, 1, 1), crown, V.gold, f)
	for k = -1, 1 do
		glow(shape("Octa", Vector3.new(0.8, 1.4, 0.8), crown * CFrame.new(k * 1.3, 1, 0), V.gold, f), 0.1)
	end
	-- a flower bed at its foot
	planter(f, cf * CFrame.new(0, -10, -1.2), 12, Scenery.rng(i * 7))
end

-- the low village wall round the hub (the real walls are WorldService's invisible colliders), with
-- stone pillars and lanterns, and the village outside it: cottages and big pines
local function villageWall(parent: Instance, from: Vector3, to: Vector3)
	local len = (to - from).Magnitude
	local mid = CFrame.lookAt((from + to) / 2, to)
	block(Vector3.new(2.2, 4, len), mid + Vector3.new(0, 2, 0), V.stone, parent, false, Enum.Material.Cobblestone)
	quiet(block(Vector3.new(2.6, 0.5, len), mid + Vector3.new(0, 4.25, 0), V.trim, parent))
	local n = math.max(1, math.floor(len / 8))
	for i = 0, n - 1 do
		quiet(ellipsoid(Vector3.new(3, 1.4, len / n * 1.1), mid * CFrame.new(0, 4.6, -len / 2 + (i + 0.5) * len / n), A.snowCap, parent))
	end
	local pillars = math.max(1, math.floor(len / 18))
	for i = 0, pillars do
		local p = mid * CFrame.new(0, 0, -len / 2 + i * len / pillars)
		block(Vector3.new(3, 6, 3), p * CFrame.new(0, 3, 0), V.stoneDark, parent, false, Enum.Material.Cobblestone)
		quiet(block(Vector3.new(3.4, 0.5, 3.4), p * CFrame.new(0, 6.25, 0), V.trim, parent))
		local lampBox = quiet(glow(block(Vector3.new(1, 1.2, 1), p * CFrame.new(0, 7.1, 0), A.lanternGlow, parent), 0.1))
		shape("Cone", Vector3.new(1.6, 1, 1.6), p * CFrame.new(0, 8.2, 0), V.iron, parent)
		if i % 2 == 0 then
			light(lampBox, A.lanternGlow, 14, 0.8)
		end
	end
end

local function village(parent: Instance, rng: () -> number)
	local H = W.hub
	local f = folder("Village", parent)
	local wf = folder("VillageWall", parent)
	local half = W.tunnel.width / 2
	villageWall(wf, Vector3.new(H.xMin - 1.5, 0, H.zMin - 1.5), Vector3.new(H.xMax + 1.5, 0, H.zMin - 1.5))
	villageWall(wf, Vector3.new(H.xMin - 1.5, 0, H.zMin - 1.5), Vector3.new(H.xMin - 1.5, 0, W.hubZMax + 1.5))
	villageWall(wf, Vector3.new(H.xMax + 1.5, 0, H.zMin - 1.5), Vector3.new(H.xMax + 1.5, 0, W.hubZMax + 1.5))
	villageWall(wf, Vector3.new(H.xMin - 1.5, 0, W.hubZMax + 1.5), Vector3.new(-half - 6, 0, W.hubZMax + 1.5))
	villageWall(wf, Vector3.new(half + 6, 0, W.hubZMax + 1.5), Vector3.new(H.xMax + 1.5, 0, W.hubZMax + 1.5))
	local k = 0
	local function cottage(at: Vector3, face: Vector3)
		k += 1
		local w, d, h = 9 + rng() * 4, 7 + rng() * 2, 5 + rng() * 3
		local cf = CFrame.lookAt(at, Vector3.new(face.X, at.Y, face.Z))
		house(f, cf, w, d, h, V.houses[k % #V.houses + 1], V.roofs[(k * 3) % #V.roofs + 1], V.roofs[(k * 2 + 1) % #V.roofs + 1], rng)
	end
	-- north, behind the pans
	local x = H.xMin + 4
	while x < H.xMax - 4 do
		cottage(Vector3.new(x + 6, 0, H.zMin - 16 - rng() * 4), Vector3.new(x + 6, 0, 0))
		x += 18 + rng() * 4
	end
	-- west and east
	for _, side in { -1, 1 } do
		local z = H.zMin + 6
		while z < W.hubZMax - 6 do
			cottage(Vector3.new(side * (H.xMax + 16 + rng() * 4), 0, z + 5), Vector3.new(0, 0, z + 5))
			z += 17 + rng() * 4
		end
	end
	-- big pines behind and between the cottages
	for i = 0, 40 do
		local a = i / 40
		local px, pz
		if i % 3 == 0 then
			px, pz = H.xMin - 8 + a * (H.xMax - H.xMin + 16), H.zMin - 30 - rng() * 14
		elseif i % 3 == 1 then
			px, pz = -(H.xMax + 30 + rng() * 14), H.zMin + a * (W.hubZMax - H.zMin)
		else
			px, pz = H.xMax + 30 + rng() * 14, H.zMin + a * (W.hubZMax - H.zMin)
		end
		farTree(px, -0.5, pz, 1.5 + rng() * 1.2, "snowpine", f)
	end
end

local function hub(parent: Instance, rng: () -> number)
	local P, T = W.pans, W.tunnel
	local half = T.width / 2
	-- (owner 2026-11-10: no fountain, no paved boulevard and no lawns on the plaza; the hub ground
	-- stays open space)
	village(parent, rng)
	-- the pans, with open walkable ground between them (as in the owner's reference) and a lantern at
	-- the front of each gap
	for i, pl in W.plots do
		panArt(parent, i, pl, rng)
		if i < #W.plots then
			local gx0, gx1 = pl.x + P.width / 2 + 1, W.plots[i + 1].x - P.width / 2 - 1
			if gx1 > gx0 then
				lantern(parent, Vector3.new((gx0 + gx1) / 2, 0, P.frontZ + 1.2), A.lanternGlow, 5, 14, i % 2 == 1)
			end
		end
	end
	-- (owner 2026-11-10: no spawn pad drawn; you spawn on the open plaza)
	for _, b in W.booths do
		booth(parent, b, rng)
	end
	for i, pos in W.boards do
		boardFrame(parent, pos, i)
	end
	-- presents round the gift box, barrels and sleds round the plaza
	local gb = W.giftBox
	for k = 0, 3 do
		present(parent, Vector3.new(gb.X - 3.5 + (k % 2) * 7, 0, gb.Z + 3 - math.floor(k / 2) * 6), 1.2 + (k % 3) * 0.3, V.flowers[k + 1], k * 0.7)
	end
	-- the tunnel mouth: two stone towers with pointed roofs, a lintel with crystals, a welcome glow
	-- (everything but the span scaled by archScale, so the entrance stays in proportion to the tunnel)
	local first_look = Theme.islands[W.islands[1].theme] or Theme.islands.meadow
	local s, mz, wh = T.archScale, W.hubZMax + 1.5, T.wallHeight
	for _, x in { -half - 4.5 * s, half + 4.5 * s } do
		cyl(4.2 * s, wh + 8 * s, CFrame.new(x, (wh + 8 * s) / 2, mz), V.stone, parent, true, Enum.Material.Cobblestone)
		cyl(4.7 * s, 1.2 * s, CFrame.new(x, wh + 8.6 * s, mz), V.trim, parent)
		for c = 0, 7 do
			local a = c * math.pi / 4
			block(Vector3.new(1.4, 1.6, 1.4) * s, CFrame.new(x + math.cos(a) * 4.1 * s, wh + 10 * s, mz + math.sin(a) * 4.1 * s), V.stone, parent, false, Enum.Material.Cobblestone)
		end
		shape("Cone", Vector3.new(10, 9, 10) * s, CFrame.new(x, wh + 15.5 * s, mz), first_look.accent, parent)
		quiet(shape("Cone", Vector3.new(4.4, 3.4, 4.4) * s, CFrame.new(x, wh + 18.6 * s, mz), A.snowCap, parent))
		cyl(0.15 * s, 4 * s, CFrame.new(x, wh + 21.5 * s, mz), V.iron, parent)
		block(Vector3.new(0.15, 1.4, 2.4) * s, CFrame.new(x, wh + 22.6 * s, mz + 1.2 * s), V.flag, parent)
	end
	block(Vector3.new(T.width + 4, 2.6 * s, 3 * s), CFrame.new(0, wh + 6.8 * s, mz), V.stone, parent, false, Enum.Material.Cobblestone)
	quiet(ellipsoid(Vector3.new(T.width + 6, 1.4 * s, 3.6 * s), CFrame.new(0, wh + 8.3 * s, mz), A.snowCap, parent))
	glow(block(Vector3.new(T.width + 2, 1.2 * s, 1.2 * s), CFrame.new(0, wh + 5 * s, W.hubZMax), first_look.accent, parent), 0.2)
	for k = 0, 8 do
		glow(shape("Octa", Vector3.new(1.6, 3, 1.6) * s, CFrame.new(-half + 4 + k * (T.width - 8) / 8, wh + 9.6 * s, mz), A.crystalGlow, parent), 0.15)
	end
end

-- ---------- the islands ----------
-- natural edges instead of flat walls: two rows of rocks with snow (or grass) on top, trees on the
-- higher row, small boulders at the foot. All looks: the walls are WorldService's invisible colliders.
local function cliffs(parent: Instance, zone: Config.Zone, cl: { [string]: Color3 }, kind: string, rng: () -> number)
	local half = W.tunnel.width / 2
	local f = folder("Cliffs", parent)
	for _, side in { -1, 1 } do
		local z = zone.zMin + (if zone.id == 1 then 2 else -2) -- the first island's rocks stay out of the hub
		while z < zone.zMax do
			local w, h, d = 9 + rng() * 5, 13 + rng() * 9, 8 + rng() * 5
			local x = side * (half + 0.4 + w / 2)
			local at = CFrame.new(x, h / 2 - 2, z + d / 2) * CFrame.Angles(0, (rng() - 0.5) * 0.5, 0)
			shape("Rock", Vector3.new(w, h, d), at, if rng() < 0.5 then cl.rock else cl.rockDark, f)
			quiet(shape("Dome", Vector3.new(w * 0.62, 2, d * 0.62), CFrame.new(x, h - 2.9, z + d / 2), cl.top, f))
			-- the higher row behind, with a tree now and then
			local w2, h2, d2 = 12 + rng() * 6, 22 + rng() * 10, 10 + rng() * 6
			local x2 = side * (half + 7 + w2 / 2 + rng() * 3)
			far(shape("Rock", Vector3.new(w2, h2, d2), CFrame.new(x2, h2 / 2 - 2, z + d / 2 + 2) * CFrame.Angles(0, rng() * 3, 0), if rng() < 0.5 then cl.rockDark else cl.rock, f))
			far(shape("Dome", Vector3.new(w2 * 0.6, 2.4, d2 * 0.6), CFrame.new(x2, h2 - 3.1, z + d / 2 + 2), cl.top, f))
			if rng() < 0.7 then
				farTree(x2 + (rng() - 0.5) * 4, h2 - 2.8, z + d / 2 + 2, 1.3 + rng() * 0.8, kind, f)
			end
			-- a boulder at the foot now and then
			if rng() < 0.45 then
				local s = 1.6 + rng() * 1.6
				shape("Rock", Vector3.new(s * 1.6, s, s * 1.4), CFrame.new(side * (half - 0.6), s * 0.35, z + rng() * d) * CFrame.Angles(0, rng() * 6, 0), cl.rockDark, f)
			end
			z += d * 0.72
		end
	end
end

-- the road stays a plain strip (owner 2026-11-07: no lamps or stones on it). Its lanterns, in the
-- island's own light, stand on the earth at the foot of the cliffs, out of the pets' way
local function pathDetail(parent: Instance, zone: Config.Zone, look: { [string]: Color3 })
	local T = W.tunnel
	local f = folder("Path", parent)
	local x = C.edge.to - 1.5
	local side, lz = -1, zone.zMin + T.lampEvery / 2
	while lz < zone.zMax - 4 do
		lantern(f, Vector3.new(side * x, 0, lz), look.light, 7, 28, true)
		side = -side
		lz += T.lampEvery
	end
end

-- spots for an island's props: only in the band at the foot of the cliffs, outside where pets walk
-- (World Rules 9: clean centre, detail rising toward the edge). A bigger prop (room) sits further out,
-- backing into the rocks.
local function pick(zone: Config.Zone, trees: { Scenery.Tree }, rng: () -> number, n: number, room: number, taken: { Vector3 }): { Vector3 }
	local E = C.edge
	local lo = math.min(E.from + room * 0.5, E.to)
	local out: { Vector3 } = {}
	for _ = 1, n * 6 do
		if #out >= n then
			break
		end
		local side = if rng() < 0.5 then -1 else 1
		local x, z = side * (lo + rng() * (E.to - lo)), zone.zMin + 12 + rng() * (zone.zMax - zone.zMin - 24)
		local ok = true
		for _, t in trees do
			if ok and (t.x - x) ^ 2 + (t.z - z) ^ 2 < (3 + room) ^ 2 then
				ok = false
			end
		end
		for _, p in taken do
			if ok and (p.X - x) ^ 2 + (p.Z - z) ^ 2 < (4 + room) ^ 2 then
				ok = false
			end
		end
		if ok then
			local p = Vector3.new(x, 0, z)
			table.insert(out, p)
			table.insert(taken, p)
		end
	end
	return out
end

local function mushroom(parent: Instance, at: Vector3, s: number, ry: number, cap: Color3)
	local cf = CFrame.new(at) * CFrame.Angles(0, ry, 0)
	cyl(0.4 * s, 1.2 * s, cf * CFrame.new(0, 0.6 * s, 0), A.stem, parent)
	shape("Dome", Vector3.new(2 * s, 0.75 * s, 2 * s), cf * CFrame.new(0, 1.475 * s, 0), cap, parent)
	for k = 0, 2 do
		ellipsoid(Vector3.one * 0.32 * s, cf * CFrame.new(math.cos(k * 2.1) * 0.6 * s, 1.75 * s, math.sin(k * 2.1) * 0.6 * s), A.snowman, parent)
	end
end

local function meadowProps(parent: Instance, zone: Config.Zone, trees: { Scenery.Tree }, rng: () -> number)
	local f = folder("Props", parent)
	local taken: { Vector3 } = {}
	-- frozen ponds with a snowy rim
	for _, p in pick(zone, trees, rng, 2, 6, taken) do
		local r = 5 + rng() * 2
		local ice = cyl(r, 0.15, CFrame.new(p + Vector3.new(0, 0.115, 0)), V.water, f, false, Enum.Material.Ice) -- top 0.19 (floor layers: WorldService)
		ice.Transparency = 0.1
		for k = 0, 9 do
			local a = k / 10 * math.pi * 2
			quiet(ellipsoid(Vector3.new(2.6, 0.9, 2.2), CFrame.new(p + Vector3.new(math.cos(a) * r, 0.2, math.sin(a) * r)), A.mound, f))
		end
	end
	-- an igloo
	for _, p in pick(zone, trees, rng, 1, 5, taken) do
		shape("Dome", Vector3.new(9, 4.6, 9), CFrame.new(p + Vector3.new(0, 2.3, 0)), A.snowman, f)
		local door = CFrame.lookAt(p, Vector3.new(0, 0, p.Z)) * CFrame.new(0, 1.2, -4.2)
		block(Vector3.new(2.6, 2.4, 2.4), door, A.snowman, f)
		block(Vector3.new(1.8, 1.9, 0.3), door * CFrame.new(0, -0.1, -1.1), Theme.ink, f).Transparency = 0.2
		for ring = 1, 2 do
			quiet(cyl(4.5 - ring * 0.9, 0.12, CFrame.new(p + Vector3.new(0, 1.2 + ring * 1.1, 0)), A.snowB, f))
		end
	end
	-- sleds
	for _, p in pick(zone, trees, rng, 2, 2, taken) do
		local cf = CFrame.new(p) * CFrame.Angles(0, rng() * 6, 0)
		block(Vector3.new(1.6, 0.25, 3.4), cf * CFrame.new(0, 0.7, 0), V.flag, f, false, Enum.Material.WoodPlanks)
		for _, x in { -0.7, 0.7 } do
			block(Vector3.new(0.15, 0.15, 3.8), cf * CFrame.new(x, 0.15, 0), V.iron, f)
			block(Vector3.new(0.15, 0.5, 0.15), cf * CFrame.new(x, 0.4, 1.2), V.iron, f)
			block(Vector3.new(0.15, 0.5, 0.15), cf * CFrame.new(x, 0.4, -1.2), V.iron, f)
		end
	end
	for _, p in pick(zone, trees, rng, 4, 1.5, taken) do
		smallSnowman(f, p, 0.9 + rng() * 0.4, math.pi + (rng() - 0.5))
	end
	for _, p in pick(zone, trees, rng, 10, 1.5, taken) do
		local s = 1.4 + rng() * 2
		quiet(ellipsoid(Vector3.new(s * 2, (0.5 + rng() * 0.3) * 2, s * 2), CFrame.new(p.X, -0.3, p.Z), A.mound, f))
	end
	for _, p in pick(zone, trees, rng, 7, 1, taken) do
		local s = 0.8 + rng() * 0.6
		local cf = CFrame.new(p) * CFrame.Angles(0, rng() * 6, 0)
		for k = 0, 2 do
			glow(shape("Octa", Vector3.new(s, (2.2 + k * 0.4) * s, s), cf * CFrame.new(math.cos(k * 2.1) * 0.5 * s, 0.8 * s, math.sin(k * 2.1) * 0.5 * s), A.crystalGlow, f), 0.2)
		end
	end
	for _, p in pick(zone, trees, rng, 8, 1, taken) do
		snowyBush(f, p, 0.9 + rng() * 0.6, true)
	end
	for _, p in pick(zone, trees, rng, 2, 2, taken) do
		for k = 0, 2 do
			present(f, p + Vector3.new((k - 1) * 1.6, 0, (k % 2) * 1.2), 1 + rng() * 0.5, V.flowers[k + 1], rng() * 6)
		end
	end
end

local function forestProps(parent: Instance, zone: Config.Zone, trees: { Scenery.Tree }, rng: () -> number)
	local f = folder("Props", parent)
	local taken: { Vector3 } = {}
	for _, p in pick(zone, trees, rng, 16, 1, taken) do
		mushroom(f, p, 0.8 + rng() * 1.1, rng() * 6, if rng() < 0.7 then A.cap else V.flowers[3])
	end
	for _, p in pick(zone, trees, rng, 22, 0.5, taken) do
		flowers(f, p, 5 + math.floor(rng() * 4), rng)
	end
	for _, p in pick(zone, trees, rng, 12, 1, taken) do
		snowyBush(f, p, 0.9 + rng() * 0.6, false)
	end
	for _, p in pick(zone, trees, rng, 4, 2, taken) do
		local cf = CFrame.new(p + Vector3.new(0, 0.65, 0)) * CFrame.Angles(0, rng() * 6, 0)
		local log = block(Vector3.new(4.5, 1.3, 1.3), cf, A.post, f, false, Enum.Material.Wood)
		log.Shape = Enum.PartType.Cylinder
		for _, x in { -2.26, 2.26 } do
			quiet(cyl(0.55, 0.05, cf * CFrame.new(x, 0, 0) * CFrame.Angles(0, 0, math.pi / 2), V.crate, f))
		end
	end
	for _, p in pick(zone, trees, rng, 5, 1, taken) do
		cyl(0.9, 1, CFrame.new(p + Vector3.new(0, 0.5, 0)), A.post, f, false, Enum.Material.Wood)
		quiet(cyl(0.75, 0.06, CFrame.new(p + Vector3.new(0, 1.02, 0)), V.crate, f))
	end
	-- fireflies: warm little sparks drifting over the grass
	for _, p in pick(zone, trees, rng, 6, 1, taken) do
		local spot = block(Vector3.new(6, 1, 6), CFrame.new(p + Vector3.new(0, 1.5, 0)), A.lanternGlow, f)
		spot.Transparency = 1
		spot.CanQuery = false
		local e = Instance.new("ParticleEmitter")
		e.Color = ColorSequence.new(A.lanternGlow)
		e.LightEmission = 1
		e.Size = NumberSequence.new(0.18)
		e.Lifetime = NumberRange.new(2, 3)
		e.Speed = NumberRange.new(0.3, 0.8)
		e.SpreadAngle = Vector2.new(180, 180)
		e.Rate = 3
		e.Parent = spot
	end
end

-- ---------- landmarks (big enough to see from the section before) ----------
local function snowman(parent: Instance, x: number, z: number, s: number)
	local at = CFrame.new(x, 0, z) * CFrame.Angles(0, math.pi + 0.3, 0) -- looking back toward the hub
	cyl(4 * s, 1, at * CFrame.new(0, 0.5, 0), A.snowman, parent, true)
	for _, b in { { 4, 4 }, { 10, 3 }, { 14.6, 2.2 } } do
		ellipsoid(Vector3.one * b[2] * 2 * s, at * CFrame.new(0, b[1] * s, 0), A.snowman, parent)
	end
	shape("Cone", Vector3.new(0.9, 2.2, 0.9) * s, at * CFrame.new(0, 14.6 * s, -2.9 * s) * CFrame.Angles(-math.pi / 2, 0, 0), A.carrot, parent)
	for _, ex in { -0.8, 0.8 } do
		ellipsoid(Vector3.one * 0.6 * s, at * CFrame.new(ex * s, 15.3 * s, -2 * s), Theme.ink, parent)
	end
	for k = 0, 2 do
		ellipsoid(Vector3.one * 0.55 * s, at * CFrame.new(0, (8.8 + k * 1.3) * s, -2.9 * s), Theme.ink, parent)
	end
	-- stick arms waving
	for _, side in { -1, 1 } do
		local arm = cyl(0.22 * s, 5 * s, at * CFrame.new(side * 4.6 * s, 11.4 * s, 0) * CFrame.Angles(0, 0, side * 1.0), A.trunk, parent)
		arm.Material = Enum.Material.Wood
	end
	shape("Ring", Vector3.new(5.9, 1.1, 5.9) * s, at * CFrame.new(0, 12.6 * s, 0), A.scarf, parent)
	block(Vector3.new(1.2, 3.4, 0.4) * s, at * CFrame.new(1.4 * s, 11 * s, -2.7 * s) * CFrame.Angles(0.2, 0, 0.15), A.scarf, parent)
	cyl(1.6 * s, 2.4 * s, at * CFrame.new(0, 17.6 * s, 0), A.hat, parent)
	cyl(2.4 * s, 0.3 * s, at * CFrame.new(0, 16.5 * s, 0), A.hat, parent)
	cyl(1.65 * s, 0.4 * s, at * CFrame.new(0, 16.9 * s, 0), A.scarf, parent)
end

local function giantMushroom(parent: Instance, x: number, z: number, s: number)
	cyl(2.6 * s, 14 * s, CFrame.new(x, 7 * s, z), A.stem, parent, true)
	shape("Dome", Vector3.new(18, 5.4, 18) * s, CFrame.new(x, 16.2 * s, z), A.cap, parent)
	for k = 0, 8 do
		local a, rr = k * 0.7, 4 + (k % 3) * 1.5
		ellipsoid(Vector3.one * 2.2 * s, CFrame.new(x + math.cos(a) * rr * s, (13.5 + math.sqrt(math.max(0, 81 - rr * rr)) * 0.6 - 0.3) * s, z + math.sin(a) * rr * s), A.snowman, parent)
	end
	-- a little door and round lit windows: someone lives in it
	local front = CFrame.lookAt(Vector3.new(x, 0, z), Vector3.new(0, 0, z - 30)) * CFrame.new(0, 0, -2.55 * s)
	block(Vector3.new(1.8, 3.2, 0.3) * s, front * CFrame.new(0, 1.6 * s, 0), V.door, parent, false, Enum.Material.WoodPlanks)
	ball(0.12 * s, (front * CFrame.new(0.5 * s, 1.6 * s, -0.25 * s)).Position, V.gold, parent)
	for _, y in { 6, 10 } do
		local win = cyl(0.7 * s, 0.25, front * CFrame.new(0, y * s, 0) * CFrame.Angles(math.pi / 2, 0, 0), V.window, parent)
		glow(win, 0.1)
	end
	lantern(parent, (front * CFrame.new(2.4 * s, 0, -0.8 * s)).Position, A.lanternGlow, 4, 14)
end

-- ---------- Round 4 phase 6: islands 3-10 ----------
local IA = Theme.islandArt

-- trees (s = shade radius / 2.4, like the pines)
ISLAND_TREES.toadstool = function(at: CFrame, s: number, m: Instance)
	local cap = IA.toadCaps[math.floor((at.Position.X * 7 + at.Position.Z) % #IA.toadCaps) + 1]
	cyl(0.55 * s, 4.6 * s, at * CFrame.new(0, 2.3 * s, 0), IA.toadStem, m, true)
	shape("Dome", Vector3.new(5.4 * s, 2 * s, 5.4 * s), at * CFrame.new(0, 5.4 * s, 0), cap, m)
	for k = 0, 2 do
		quiet(ellipsoid(Vector3.new(0.9, 0.4, 0.9) * s, at * CFrame.new(math.cos(k * 2.1) * 1.4 * s, 6.1 * s, math.sin(k * 2.1) * 1.4 * s), IA.toadSpot, m))
	end
end
ISLAND_TREES.palm = function(at: CFrame, s: number, m: Instance)
	local cf = at
	for k = 1, 4 do -- a gently bending trunk
		cyl(0.32 * s, 1.9 * s, cf * CFrame.new(0, 0.95 * s, 0), IA.palmTrunk, m, k == 1)
		cf = cf * CFrame.new(0, 1.8 * s, 0) * CFrame.Angles(0, 0, 0.09)
	end
	for k = 0, 5 do
		local leaf = cf * CFrame.Angles(0, k * math.pi / 3, 0) * CFrame.Angles(-0.45, 0, 0) * CFrame.new(0, 0, -1.9 * s)
		block(Vector3.new(1.1 * s, 0.15 * s, 4 * s), leaf, if k % 2 == 0 then IA.palmLeaf else IA.palmLeafDark, m)
	end
	for k = 0, 1 do
		ball(0.32 * s, (cf * CFrame.new((k - 0.5) * 0.6 * s, -0.4 * s, 0.3 * s)).Position, IA.coconut, m)
	end
end
ISLAND_TREES.jungle = function(at: CFrame, s: number, m: Instance)
	cyl(0.55 * s, 6 * s, at * CFrame.new(0, 3 * s, 0), IA.jungleTrunk, m, true)
	ellipsoid(Vector3.new(2.2, 1, 2.2) * s, at * CFrame.new(0, 0.3 * s, 0), IA.jungleTrunk, m, Enum.Material.Wood)
	for k = 0, 2 do
		local a = k * 2.1
		ellipsoid(Vector3.new(3.8, 2.6, 3.8) * s, at * CFrame.new(math.cos(a) * 1.3 * s, (6.2 + k * 0.5) * s, math.sin(a) * 1.3 * s), IA.jungleLeaf[k + 1], m, Enum.Material.LeafyGrass)
	end
end
ISLAND_TREES.cactus = function(at: CFrame, s: number, m: Instance)
	cyl(0.6 * s, 4.6 * s, at * CFrame.new(0, 2.3 * s, 0), IA.cactus, m, true)
	ball(0.6 * s, (at * CFrame.new(0, 4.6 * s, 0)).Position, IA.cactus, m)
	for _, side in { -1, 1 } do
		local y = (if side < 0 then 2.2 else 2.9) * s
		cyl(0.36 * s, 1.4 * s, at * CFrame.new(side * 1.1 * s, y, 0) * CFrame.Angles(0, 0, math.pi / 2), IA.cactusDark, m)
		cyl(0.36 * s, 1.6 * s, at * CFrame.new(side * 1.7 * s, y + 0.8 * s, 0), IA.cactusDark, m)
		ball(0.36 * s, (at * CFrame.new(side * 1.7 * s, y + 1.6 * s, 0)).Position, IA.cactusDark, m)
	end
	ball(0.32 * s, (at * CFrame.new(0, 5.25 * s, 0)).Position, IA.cactusFlower, m)
end
ISLAND_TREES.hoodoo = function(at: CFrame, s: number, m: Instance)
	cyl(1.1 * s, 2.4 * s, at * CFrame.new(0, 1.2 * s, 0), IA.hoodoo, m, true, Enum.Material.Sandstone)
	cyl(0.8 * s, 2 * s, at * CFrame.new(0, 3.4 * s, 0), IA.hoodooBand, m, true, Enum.Material.Sandstone)
	cyl(0.65 * s, 1.6 * s, at * CFrame.new(0, 5.2 * s, 0), IA.hoodoo, m, true, Enum.Material.Sandstone)
	ellipsoid(Vector3.new(3.6, 1.1, 3.6) * s, at * CFrame.new(0, 6.3 * s, 0), IA.hoodooCap, m, Enum.Material.Sandstone)
end
ISLAND_TREES.charred = function(at: CFrame, s: number, m: Instance)
	cyl(0.45 * s, 4.4 * s, at * CFrame.new(0, 2.2 * s, 0), IA.charred, m, true, Enum.Material.Basalt)
	for k = 0, 2 do
		local a = k * 2.1
		cyl(0.2 * s, 2 * s, at * CFrame.new(math.cos(a) * 0.6 * s, (3 + k * 0.5) * s, math.sin(a) * 0.6 * s) * CFrame.Angles(math.sin(a) * 0.8, 0, -math.cos(a) * 0.8), IA.charred, m, false, Enum.Material.Basalt)
	end
	-- a soft glow in the bark, so it reads as warm, not gloomy
	glow(block(Vector3.new(0.2, 1.6, 0.12) * s, at * CFrame.new(0, 1.5 * s, -0.42 * s), IA.ember, m), 0.15)
end
ISLAND_TREES.obsidian = function(at: CFrame, s: number, m: Instance)
	for k = 0, 2 do
		local a = k * 2.1
		local p = shape("Octa", Vector3.new(1.4, 4.5 + k, 1.4) * s, at * CFrame.new(math.cos(a) * 0.9 * s, (2.2 + k * 0.5) * s, math.sin(a) * 0.9 * s) * CFrame.Angles(math.sin(a) * 0.25, 0, math.cos(a) * 0.25), IA.obsidian, m)
		p.Material = Enum.Material.Glass
		p.CanCollide = true
	end
	glow(shape("Octa", Vector3.new(0.9, 3, 0.9) * s, at * CFrame.new(0, 1.8 * s, 0), IA.obsidianGlow, m), 0.1)
end
FAR_TREES.toadstool = function(p: Vector3, s: number, parent: Instance)
	far(cyl(0.5 * s, 4 * s, CFrame.new(p + Vector3.new(0, 2 * s, 0)), IA.toadStem, parent))
	far(shape("Dome", Vector3.new(4.6, 1.8, 4.6) * s, CFrame.new(p + Vector3.new(0, 4.6 * s, 0)), IA.toadCaps[1], parent))
end
FAR_TREES.palm = function(p: Vector3, s: number, parent: Instance)
	far(cyl(0.3 * s, 6 * s, CFrame.new(p + Vector3.new(0, 3 * s, 0)), IA.palmTrunk, parent))
	far(ellipsoid(Vector3.new(4.4, 1.2, 4.4) * s, CFrame.new(p + Vector3.new(0, 6.2 * s, 0)), IA.palmLeaf, parent))
end
FAR_TREES.jungle = function(p: Vector3, s: number, parent: Instance)
	far(ellipsoid(Vector3.new(4.4, 4, 4.4) * s, CFrame.new(p + Vector3.new(0, 2.2 * s, 0)), IA.jungleLeaf[2], parent))
end
FAR_TREES.cactus = function(p: Vector3, s: number, parent: Instance)
	far(cyl(0.5 * s, 4.4 * s, CFrame.new(p + Vector3.new(0, 2.2 * s, 0)), IA.cactus, parent))
	far(ball(0.5 * s, p + Vector3.new(0, 4.4 * s, 0), IA.cactus, parent))
end
for _, k in { "hoodoo", "charred", "obsidian" } do
	FAR_TREES[k] = function(p: Vector3, s: number, parent: Instance)
		far(shape("Octa", Vector3.new(1.6, 5, 1.6) * s, CFrame.new(p + Vector3.new(0, 2.5 * s, 0)), if k == "hoodoo" then IA.hoodoo else IA.obsidian, parent))
	end
end

-- pick spots for props, never inside a lava pool
local function pickDry(zone: Config.Zone, trees: { Scenery.Tree }, rng: () -> number, n: number, room: number, taken: { Vector3 }): { Vector3 }
	local out: { Vector3 } = {}
	for _, p in pick(zone, trees, rng, n, room, taken) do
		local wet = false
		for _, l in Scenery.get().lava do
			if (l.x - p.X) ^ 2 + (l.z - p.Z) ^ 2 < (l.r + room + 2) ^ 2 then
				wet = true
			end
		end
		if not wet then
			table.insert(out, p)
		end
	end
	return out
end

-- drifting sparks or spores over a spot (cheap: one invisible part, one emitter)
local function sparks(parent: Instance, at: Vector3, color: Color3, size: number, rate: number, up: number?)
	local spot = block(Vector3.new(6, 1, 6), CFrame.new(at + Vector3.new(0, 1.5, 0)), color, parent)
	spot.Transparency = 1
	spot.CanQuery = false
	local e = Instance.new("ParticleEmitter")
	e.Color = ColorSequence.new(color)
	e.LightEmission = 1
	e.Size = NumberSequence.new(size)
	e.Lifetime = NumberRange.new(2, 3)
	e.Speed = NumberRange.new(0.3, 0.8 + (up or 0))
	e.SpreadAngle = Vector2.new(if up then 25 else 180, if up then 25 else 180)
	e.EmissionDirection = Enum.NormalId.Top
	e.Rate = rate
	e.Parent = spot
end

local function smallRocks(f: Instance, zone: Config.Zone, trees: { Scenery.Tree }, rng: () -> number, n: number, taken: { Vector3 }, a: Color3, b: Color3, mat: Enum.Material?)
	for _, p in pickDry(zone, trees, rng, n, 1, taken) do
		local s = 1 + rng() * 1.8
		local r = shape("Rock", Vector3.new(s * 1.6, s, s * 1.3), CFrame.new(p + Vector3.new(0, s * 0.3, 0)) * CFrame.Angles(0, rng() * 6, 0), if rng() < 0.5 then a else b, f)
		if mat then
			r.Material = mat
		end
	end
end

local PROPS: { [string]: (Instance, Config.Zone, { Scenery.Tree }, () -> number) -> () } = {}
PROPS.grove = function(parent, zone, trees, rng)
	local f = folder("Props", parent)
	local taken: { Vector3 } = {}
	for _, p in pickDry(zone, trees, rng, 16, 1, taken) do
		mushroom(f, p, 0.8 + rng() * 1.2, rng() * 6, IA.toadCaps[math.floor(rng() * #IA.toadCaps) + 1])
	end
	-- glowing puffballs: the grove's soft lights
	for _, p in pickDry(zone, trees, rng, 9, 1, taken) do
		local r = 0.6 + rng() * 0.5
		glow(ball(r, p + Vector3.new(0, r, 0), IA.toadCaps[math.floor(rng() * #IA.toadCaps) + 1], f), 0.25)
	end
	-- a fairy ring of little mushrooms
	for _, p in pickDry(zone, trees, rng, 2, 4, taken) do
		for k = 0, 7 do
			local a = k / 8 * math.pi * 2
			mushroom(f, p + Vector3.new(math.cos(a) * 3.2, 0, math.sin(a) * 3.2), 0.5, a, IA.toadCaps[k % #IA.toadCaps + 1])
		end
	end
	for _, p in pickDry(zone, trees, rng, 16, 0.5, taken) do
		flowers(f, p, 4 + math.floor(rng() * 3), rng)
	end
	for _, p in pickDry(zone, trees, rng, 5, 1, taken) do
		sparks(f, p, IA.toadSpot, 0.16, 3)
	end
end
PROPS.beach = function(parent, zone, trees, rng)
	local f = folder("Props", parent)
	local taken: { Vector3 } = {}
	for i, p in pickDry(zone, trees, rng, 4, 3, taken) do
		local col = IA.umbrella[(i - 1) % #IA.umbrella + 1]
		cyl(0.12, 4.4, CFrame.new(p + Vector3.new(0, 2.2, 0)), V.trim, f)
		shape("Cone", Vector3.new(6, 1.6, 6), CFrame.new(p + Vector3.new(0, 4.6, 0)), col, f)
		quiet(shape("Cone", Vector3.new(3, 0.85, 3), CFrame.new(p + Vector3.new(0, 5.03, 0)), IA.umbrellaStripe, f))
		block(Vector3.new(2, 0.1, 4), CFrame.new(p + Vector3.new(1.6, 0.06, 0.6)) * CFrame.Angles(0, rng(), 0), col, f)
	end
	-- sandcastles
	for _, p in pickDry(zone, trees, rng, 3, 2, taken) do
		block(Vector3.new(3, 1.4, 3), CFrame.new(p + Vector3.new(0, 0.7, 0)), IA.dune, f, false, Enum.Material.Sand)
		for _, d in { Vector3.new(-1.5, 0, -1.5), Vector3.new(1.5, 0, -1.5), Vector3.new(-1.5, 0, 1.5), Vector3.new(1.5, 0, 1.5) } do
			cyl(0.6, 2.4, CFrame.new(p + d + Vector3.new(0, 1.2, 0)), IA.dune, f, false, Enum.Material.Sand)
			shape("Cone", Vector3.new(1.4, 1, 1.4), CFrame.new(p + d + Vector3.new(0, 2.9, 0)), IA.dune, f)
		end
		block(Vector3.new(0.1, 0.6, 0.9), CFrame.new(p + Vector3.new(1.5, 3.7, -1.5)), V.flag, f)
	end
	-- shells and starfish
	for _, p in pickDry(zone, trees, rng, 14, 0.5, taken) do
		if rng() < 0.5 then
			quiet(ellipsoid(Vector3.new(0.8, 0.35, 0.7), CFrame.new(p + Vector3.new(0, 0.15, 0)) * CFrame.Angles(0, rng() * 6, 0), IA.shell, f))
		else
			for k = 0, 4 do
				quiet(block(Vector3.new(0.25, 0.2, 0.8), CFrame.new(p + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, k * math.pi * 2 / 5, 0) * CFrame.new(0, 0, -0.35), IA.starfish, f))
			end
		end
	end
	-- beach balls
	for _, p in pickDry(zone, trees, rng, 3, 1, taken) do
		ball(0.8, p + Vector3.new(0, 0.8, 0), IA.umbrella[math.floor(rng() * #IA.umbrella) + 1], f)
	end
	-- tide pools with a shine
	for _, p in pickDry(zone, trees, rng, 2, 4, taken) do
		local w = cyl(3 + rng(), 0.15, CFrame.new(p + Vector3.new(0, 0.115, 0)), IA.sea, f, false, Enum.Material.Glass) -- top 0.19 (floor layers: WorldService)
		w.Transparency = 0.15
		for k = 0, 5 do
			local a = k / 6 * math.pi * 2
			quiet(shape("Rock", Vector3.new(1.4, 0.8, 1.2), CFrame.new(p + Vector3.new(math.cos(a) * 3.6, 0.3, math.sin(a) * 3.6)), V.stone, f))
		end
	end
end
PROPS.jungle = function(parent, zone, trees, rng)
	local f = folder("Props", parent)
	local taken: { Vector3 } = {}
	for _, p in pickDry(zone, trees, rng, 14, 1, taken) do
		local s = 1 + rng() * 0.8
		ellipsoid(Vector3.new(3.2, 2, 3.2) * s, CFrame.new(p + Vector3.new(0, 0.8 * s, 0)), IA.jungleLeaf[math.floor(rng() * 3) + 1], f, Enum.Material.LeafyGrass)
	end
	-- giant flowers
	for _, p in pickDry(zone, trees, rng, 6, 1.5, taken) do
		local h = 2.4 + rng() * 1.2
		cyl(0.18, h, CFrame.new(p + Vector3.new(0, h / 2, 0)), IA.vine, f)
		ball(0.5, p + Vector3.new(0, h + 0.1, 0), V.gold, f)
		for k = 0, 4 do
			local a = k / 5 * math.pi * 2
			ellipsoid(Vector3.new(1.3, 0.3, 0.8), CFrame.new(p + Vector3.new(math.cos(a) * 0.8, h, math.sin(a) * 0.8)) * CFrame.Angles(0, -a, 0.3), IA.bigFlower, f)
		end
	end
	for _, p in pickDry(zone, trees, rng, 4, 2, taken) do
		local cf = CFrame.new(p + Vector3.new(0, 0.7, 0)) * CFrame.Angles(0, rng() * 6, 0)
		local log = block(Vector3.new(5, 1.4, 1.4), cf, IA.jungleTrunk, f, false, Enum.Material.Wood)
		log.Shape = Enum.PartType.Cylinder
		quiet(ellipsoid(Vector3.new(2.6, 0.5, 1.6), cf * CFrame.new(0.6, 0.7, 0), IA.vine, f, Enum.Material.LeafyGrass))
	end
	for _, p in pickDry(zone, trees, rng, 16, 0.5, taken) do
		flowers(f, p, 4, rng)
	end
	for _, p in pickDry(zone, trees, rng, 5, 1, taken) do
		sparks(f, p, A.lanternGlow, 0.18, 3)
	end
end
PROPS.desert = function(parent, zone, trees, rng)
	local f = folder("Props", parent)
	local taken: { Vector3 } = {}
	for _, p in pickDry(zone, trees, rng, 10, 2, taken) do
		local s = 2 + rng() * 2.5
		quiet(ellipsoid(Vector3.new(s * 2.6, s * 0.7, s * 1.8), CFrame.new(p.X, -0.2, p.Z) * CFrame.Angles(0, rng() * 3, 0), IA.dune, f, Enum.Material.Sand))
	end
	for _, p in pickDry(zone, trees, rng, 7, 1, taken) do
		local h = 1.4 + rng() * 1.2
		cyl(0.35, h, CFrame.new(p + Vector3.new(0, h / 2, 0)), IA.cactus, f)
		ball(0.35, p + Vector3.new(0, h, 0), IA.cactus, f)
		if rng() < 0.5 then
			ball(0.2, p + Vector3.new(0, h + 0.35, 0), IA.cactusFlower, f)
		end
	end
	-- clay pots
	for _, p in pickDry(zone, trees, rng, 4, 1.5, taken) do
		for k = 0, 2 do
			local d = Vector3.new((k - 1) * 1.3, 0, (k % 2) * 1)
			ellipsoid(Vector3.new(1.3, 1.5, 1.3), CFrame.new(p + d + Vector3.new(0, 0.7, 0)), IA.pot, f)
			quiet(cyl(0.4, 0.3, CFrame.new(p + d + Vector3.new(0, 1.5, 0)), IA.pot, f))
		end
	end
	smallRocks(f, zone, trees, rng, 8, taken, IA.hoodoo, IA.hoodooBand, Enum.Material.Sandstone)
	-- an oasis: a little pool with two palms (shade!)
	for _, p in pickDry(zone, trees, rng, 1, 6, taken) do
		local w = cyl(4.5, 0.2, CFrame.new(p + Vector3.new(0, 0.09, 0)), IA.pool, f, false, Enum.Material.Glass) -- top 0.19 (floor layers: WorldService)
		w.Transparency = 0.1
		for _, dx in { -5.5, 5.5 } do
			local m = Instance.new("Model")
			m.Name = "Palm"
			ISLAND_TREES.palm(CFrame.new(p + Vector3.new(dx, 0, 1)) * CFrame.Angles(0, dx, 0), 1.5, m)
			m.Parent = f
		end
	end
end
PROPS.canyon = function(parent, zone, trees, rng)
	local f = folder("Props", parent)
	local taken: { Vector3 } = {}
	-- little mesas: layered rock steps
	for _, p in pickDry(zone, trees, rng, 4, 4, taken) do
		local w = 6 + rng() * 3
		for k = 0, 2 do
			block(Vector3.new(w - k * 1.8, 1.6, w * 0.8 - k * 1.4), CFrame.new(p + Vector3.new(0, 0.8 + k * 1.6, 0)) * CFrame.Angles(0, 0.3, 0), if k % 2 == 0 then IA.hoodoo else IA.hoodooBand, f, k == 0, Enum.Material.Sandstone)
		end
	end
	for _, p in pickDry(zone, trees, rng, 5, 1.5, taken) do
		local m = Instance.new("Model")
		m.Name = "Hoodoo"
		ISLAND_TREES.hoodoo(CFrame.new(p), 0.7 + rng() * 0.3, m)
		m.Parent = f
	end
	for _, p in pickDry(zone, trees, rng, 4, 1, taken) do
		cyl(0.35, 1.8, CFrame.new(p + Vector3.new(0, 0.9, 0)), IA.cactus, f)
		ball(0.35, p + Vector3.new(0, 1.8, 0), IA.cactus, f)
	end
	smallRocks(f, zone, trees, rng, 10, taken, IA.hoodoo, IA.hoodooCap, Enum.Material.Sandstone)
end
local function hotProps(parent: Instance, zone: Config.Zone, trees: { Scenery.Tree }, rng: () -> number, crystal: Color3)
	local f = folder("Props", parent)
	local taken: { Vector3 } = {}
	local cl = Theme.cliffs[zone.theme] or Theme.cliffs.meadow
	smallRocks(f, zone, trees, rng, 12, taken, cl.rock, cl.rockDark, Enum.Material.Basalt)
	-- steam vents: a dark ring puffing soft white steam
	for _, p in pickDry(zone, trees, rng, 4, 1.5, taken) do
		quiet(shape("Ring", Vector3.new(2.4, 0.5, 2.4), CFrame.new(p + Vector3.new(0, 0.15, 0)), cl.rockDark, f))
		local spot = block(Vector3.new(1.4, 0.2, 1.4), CFrame.new(p + Vector3.new(0, 0.2, 0)), IA.smoke, f)
		spot.Transparency = 1
		spot.CanQuery = false
		local e = Instance.new("ParticleEmitter")
		e.Color = ColorSequence.new(IA.smoke)
		e.Transparency = NumberSequence.new(0.5, 1)
		e.Size = NumberSequence.new(0.8, 2.6)
		e.Lifetime = NumberRange.new(1.6, 2.4)
		e.Speed = NumberRange.new(3, 4.5)
		e.SpreadAngle = Vector2.new(10, 10)
		e.EmissionDirection = Enum.NormalId.Top
		e.Rate = 4
		e.Parent = spot
	end
	-- glowing crystals (the warm light of the hot islands)
	for _, p in pickDry(zone, trees, rng, 6, 1, taken) do
		local s = 0.8 + rng() * 0.6
		local cf = CFrame.new(p) * CFrame.Angles(0, rng() * 6, 0)
		for k = 0, 2 do
			glow(shape("Octa", Vector3.new(s, (2 + k * 0.5) * s, s), cf * CFrame.new(math.cos(k * 2.1) * 0.5 * s, 0.9 * s, math.sin(k * 2.1) * 0.5 * s), crystal, f), 0.2)
		end
	end
	for _, p in pickDry(zone, trees, rng, 4, 1, taken) do
		sparks(f, p, IA.ember, 0.14, 3, 2)
	end
end
PROPS.volcano = function(parent, zone, trees, rng)
	hotProps(parent, zone, trees, rng, IA.ember)
end
PROPS.lavalake = function(parent, zone, trees, rng)
	hotProps(parent, zone, trees, rng, IA.obsidianGlow)
end
PROPS.magma = function(parent, zone, trees, rng)
	hotProps(parent, zone, trees, rng, IA.crystal)
end

-- hazards that read from far away: lava pools glow and spark; on the warm islands every sun patch gets
-- a glowing rim and a heat shimmer (the patches themselves are WorldService's SunPatch parts)
local function hazards(parent: Instance, zone: Config.Zone)
	local f = folder("Hazards", parent)
	local list = Scenery.get()
	local cl = Theme.cliffs[zone.theme] or Theme.cliffs.meadow
	for _, l in list.lava do
		if l.z >= zone.zMin and l.z < zone.zMax then
			local at = Vector3.new(l.x, 0, l.z)
			local pool = glow(cyl(l.r, 0.3, CFrame.new(at + Vector3.new(0, 0.12, 0)), IA.lava, f), 0)
			pool.Name = "LavaGlow"
			glow(ellipsoid(Vector3.new(l.r * 1.1, 0.4, l.r * 0.9), CFrame.new(at + Vector3.new(l.r * 0.15, 0.25, 0)), IA.lavaHot, f), 0.1)
			local n = math.max(8, math.floor(l.r * 1.6))
			for k = 0, n - 1 do
				local a = k / n * math.pi * 2
				quiet(shape("Rock", Vector3.new(2.2, 0.9, 1.6), CFrame.new(at + Vector3.new(math.cos(a) * (l.r + 0.4), 0.3, math.sin(a) * (l.r + 0.4))) * CFrame.Angles(0, -a, 0), if k % 2 == 0 then IA.lavaRim else cl.rockDark, f))
			end
			light(pool, IA.lava, l.r * 2.4, 1.4)
			local e = Instance.new("ParticleEmitter")
			e.Color = ColorSequence.new(IA.lavaHot)
			e.LightEmission = 1
			e.Size = NumberSequence.new(0.25, 0)
			e.Lifetime = NumberRange.new(1.2, 2)
			e.Speed = NumberRange.new(2, 4)
			e.SpreadAngle = Vector2.new(20, 20)
			e.EmissionDirection = Enum.NormalId.Right -- the cylinder's axis points up
			e.Rate = 2 + l.r * 0.4
			e.Parent = pool
		end
	end
	if zone.id >= 3 then
		for _, s in list.sun do
			if s.z >= zone.zMin and s.z < zone.zMax then
				local rim = glow(shape("Ring", Vector3.new(s.r * 2 + 0.6, 0.3, s.r * 2 + 0.6), CFrame.new(s.x, 0.12, s.z), A.sunGlow, f), 0.15)
				rim.Name = "SunRim"
				local e = Instance.new("ParticleEmitter")
				e.Color = ColorSequence.new(A.sunGlow)
				e.LightEmission = 0.6
				e.Transparency = NumberSequence.new(0.4, 1)
				e.Size = NumberSequence.new(0.5, 1.2)
				e.Lifetime = NumberRange.new(1, 1.6)
				e.Speed = NumberRange.new(1.5, 2.5)
				e.SpreadAngle = Vector2.new(15, 15)
				e.EmissionDirection = Enum.NormalId.Top
				e.Rate = 1 + s.r * 0.3
				e.Parent = rim
			end
		end
	end
end

-- landmarks of islands 3-10 (each one big shape in the island's colour, seen from the island before)
local function toadstoolTower(parent: Instance, x: number, z: number, s: number)
	local caps = IA.toadCaps
	local tiers = { { r = 2, h = 10, cap = 16, capH = 5 }, { r = 1.4, h = 7, cap = 11, capH = 4 }, { r = 0.9, h = 5, cap = 7, capH = 3 } }
	local y, dx = 0, 0
	local base: BasePart? = nil
	for i, t in tiers do
		local at = Vector3.new(x + dx * s, 0, z)
		local stem = cyl(t.r * s, t.h * s, CFrame.new(at + Vector3.new(0, (y + t.h / 2) * s, 0)), IA.toadStem, parent, i == 1)
		base = base or stem
		y += t.h
		shape("Dome", Vector3.new(t.cap, t.capH, t.cap) * s, CFrame.new(at + Vector3.new(0, (y + t.capH / 2 - 0.5) * s, 0)), caps[i], parent)
		glow(shape("Ring", Vector3.new(t.cap * 0.9, 0.4, t.cap * 0.9) * s, CFrame.new(at + Vector3.new(0, (y - 0.4) * s, 0)), caps[(i % #caps) + 1], parent), 0.2)
		for k = 0, 4 do
			local a, rr = k * 1.26 + i, t.cap * 0.3
			quiet(ellipsoid(Vector3.new(1.4, 0.6, 1.4) * s * (t.cap / 16 + 0.4), CFrame.new(at + Vector3.new(math.cos(a) * rr * s, (y + t.capH * 0.55) * s, math.sin(a) * rr * s)), IA.toadSpot, parent))
		end
		y += t.capH * 0.5
		dx = if i == 1 then 1.2 else -0.6
	end
	-- a door and round lit windows in the bottom stem
	local front = CFrame.lookAt(Vector3.new(x, 0, z), Vector3.new(0, 0, z - 30)) * CFrame.new(0, 0, -2 * s)
	block(Vector3.new(1.6, 3, 0.3) * s, front * CFrame.new(0, 1.5 * s, 0), V.door, parent, false, Enum.Material.WoodPlanks)
	for _, yy in { 5.5, 8 } do
		glow(cyl(0.6 * s, 0.25, front * CFrame.new(0, yy * s, 0) * CFrame.Angles(math.pi / 2, 0, 0), V.window, parent), 0.1)
	end
	if base then
		light(base, caps[1], 30, 1)
	end
end

local function lighthouse(parent: Instance, x: number, z: number, s: number)
	for k = 0, 2 do
		shape("Rock", Vector3.new(9, 4, 8) * s, CFrame.new(x + (k - 1) * 4 * s, 1.2 * s, z + (k % 2) * 3 * s) * CFrame.Angles(0, k, 0), V.stone, parent)
	end
	local y = 3
	for k = 0, 4 do
		local r = (3.1 - k * 0.22) * s
		cyl(r, 4 * s, CFrame.new(x, (y + 2) * s, z), if k % 2 == 0 then IA.lighthouseA else IA.lighthouseB, parent, k == 0)
		y += 4
	end
	cyl(2.9 * s, 0.6 * s, CFrame.new(x, (y + 0.3) * s, z), V.iron, parent)
	quiet(shape("Ring", Vector3.new(5.6, 1, 5.6) * s, CFrame.new(x, (y + 1.1) * s, z), V.iron, parent))
	local lampRoom = cyl(1.7 * s, 2.6 * s, CFrame.new(x, (y + 1.9) * s, z), IA.lamp, parent, false, Enum.Material.Glass)
	lampRoom.Transparency = 0.25
	local lamp = glow(ball(1 * s, Vector3.new(x, (y + 1.9) * s, z), IA.lamp, parent), 0)
	light(lamp, IA.lamp, 40, 2)
	shape("Cone", Vector3.new(4.2, 2.8, 4.2) * s, CFrame.new(x, (y + 4.6) * s, z), IA.lighthouseA, parent)
	ball(0.4 * s, Vector3.new(x, (y + 6.2) * s, z), V.gold, parent)
end

local function waterfall(parent: Instance, x: number, z: number, s: number)
	local side = if x >= 0 then 1 else -1
	local back = x + side * 4 * s
	for k = -1, 1 do
		shape("Rock", Vector3.new(9, 24 + math.abs(k) * -4, 8) * s, CFrame.new(back + side * math.abs(k) * 1.5 * s, (12 - math.abs(k) * 2) * s, z + k * 6 * s), if k == 0 then Theme.cliffs.jungle.rock else Theme.cliffs.jungle.rockDark, parent)
	end
	-- map pass 2026-11-10: wider and nearly solid, SmoothPlastic not Glass (World Rules 6), with a bright foam
	-- lip at the top, so the falls read from the road instead of vanishing behind the jungle trees
	local sheet = block(Vector3.new(0.8, 22, 9) * s, CFrame.new(back - side * 4.4 * s, 11.4 * s, z), IA.waterfall, parent)
	sheet.Transparency = 0.08
	quiet(sheet)
	quiet(ellipsoid(Vector3.new(2.2, 1.6, 10) * s, CFrame.new(back - side * 4.6 * s, 22.4 * s, z), IA.foam, parent))
	local pool = cyl(5.5 * s, 0.3, CFrame.new(x - side * 2 * s, 0.15, z), IA.pool, parent, false, Enum.Material.Glass)
	pool.Transparency = 0.1
	for k = 0, 4 do
		quiet(ellipsoid(Vector3.new(2.4, 1.2, 2.4) * s, CFrame.new(back - side * (4.6 + (k % 2)) * s, 0.4 * s, z + (k - 2) * 1.3 * s), IA.foam, parent))
	end
	local mist = Instance.new("ParticleEmitter")
	mist.Color = ColorSequence.new(IA.foam)
	mist.Transparency = NumberSequence.new(0.5, 1)
	mist.Size = NumberSequence.new(1.5, 4)
	mist.Lifetime = NumberRange.new(1.5, 2.5)
	mist.Speed = NumberRange.new(1, 2)
	mist.SpreadAngle = Vector2.new(60, 60)
	mist.EmissionDirection = Enum.NormalId.Top
	mist.Rate = 6
	mist.Parent = pool
	-- big leaves round the top and the pool
	for k = 0, 5 do
		local a = k / 6 * math.pi * 2
		ellipsoid(Vector3.new(5, 1.6, 3) * s, CFrame.new(back + math.cos(a) * 3 * s, (23 + math.sin(k) * 1.5) * s, z + math.sin(a) * 5 * s) * CFrame.Angles(0, a, 0.3), IA.jungleLeaf[k % 3 + 1], parent, Enum.Material.LeafyGrass)
	end
	for k = 0, 3 do
		ellipsoid(Vector3.new(3.6, 2, 3.6) * s, CFrame.new(x - side * 2 * s + math.cos(k * 1.6) * 6 * s, 0.6 * s, z + math.sin(k * 1.6) * 6 * s), IA.jungleLeaf[k % 3 + 1], parent, Enum.Material.LeafyGrass)
	end
end

local function giantCactus(parent: Instance, x: number, z: number, s: number)
	local at = CFrame.new(x, 0, z) * CFrame.Angles(0, 0.4, 0)
	quiet(ellipsoid(Vector3.new(12, 2.4, 10) * s, at * CFrame.new(0, -0.3 * s, 0), IA.dune, parent, Enum.Material.Sand))
	cyl(2 * s, 22 * s, at * CFrame.new(0, 11 * s, 0), IA.cactus, parent, true)
	ball(2 * s, (at * CFrame.new(0, 22 * s, 0)).Position, IA.cactus, parent)
	for _, arm in { { side = -1, y = 9, len = 7 }, { side = 1, y = 13, len = 6 } } do
		cyl(1.2 * s, 3.6 * s, at * CFrame.new(arm.side * 3 * s, arm.y * s, 0) * CFrame.Angles(0, 0, math.pi / 2), IA.cactusDark, parent)
		cyl(1.2 * s, arm.len * s, at * CFrame.new(arm.side * 4.8 * s, (arm.y + arm.len / 2) * s, 0), IA.cactusDark, parent)
		ball(1.2 * s, (at * CFrame.new(arm.side * 4.8 * s, (arm.y + arm.len) * s, 0)).Position, IA.cactusDark, parent)
	end
	-- ribs (darker stripes) and a big flower on top
	for k = 0, 3 do
		quiet(block(Vector3.new(0.4, 20, 0.4) * s, at * CFrame.new(math.cos(k * 1.57) * 1.95 * s, 11 * s, math.sin(k * 1.57) * 1.95 * s), IA.cactusDark, parent))
	end
	for k = 0, 4 do
		local a = k / 5 * math.pi * 2
		ellipsoid(Vector3.new(2.2, 0.6, 1.3) * s, at * CFrame.new(math.cos(a) * 1.2 * s, 24 * s, math.sin(a) * 1.2 * s) * CFrame.Angles(0, -a, 0.35), IA.cactusFlower, parent)
	end
	glow(ball(0.8 * s, (at * CFrame.new(0, 24.2 * s, 0)).Position, V.gold, parent), 0.1)
end

local function stoneArch(parent: Instance, x: number, z: number, s: number)
	local half = W.tunnel.width / 2
	for _, side in { -1, 1 } do
		local lx = x + side * (half - 6)
		shape("Rock", Vector3.new(12, 30, 10) * (s * 0.6), CFrame.new(lx, 9 * s, z) * CFrame.Angles(0, side, 0), IA.hoodoo, parent)
		for k = 0, 2 do
			quiet(block(Vector3.new(7.6, 1.2, 6.4) * (s * 0.6), CFrame.new(lx, (3 + k * 5) * s, z) * CFrame.Angles(0, side * 0.3, 0), IA.hoodooBand, parent))
		end
	end
	shape("Arch", Vector3.new(half * 2 + 6, (half + 3), 9), CFrame.new(x, (half + 3) / 2 + 9 * s * 0.75, z), IA.hoodoo, parent)
	quiet(shape("Arch", Vector3.new(half * 2 + 7, (half + 3) * 0.55, 9.6), CFrame.new(x, (half + 3) / 2 + 9 * s * 0.75 + (half + 3) * 0.24, z), IA.hoodooBand, parent))
end

local function volcanoCone(parent: Instance, x: number, z: number, s: number)
	local cl = Theme.cliffs.volcano
	-- a cone 36 wide and 34 tall (x s) beside the tunnel, standing 2 studs into the ground; slope atan(34 / 18)
	shape("Cone", Vector3.new(36, 34, 36) * s, CFrame.new(x, 17 * s - 2, z), cl.rock, parent)
	local top = glow(shape("Cone", Vector3.new(7, 6, 7) * s, CFrame.new(x, 31 * s - 2, z), IA.lava, parent), 0)
	light(top, IA.lava, 60, 2)
	-- three lava streams down the side facing the path (half way up the slope, tilted with it)
	for k = -1, 1 do
		local a = (if x > 0 then math.pi / 2 else -math.pi / 2) + k * 0.45
		local cf = CFrame.new(x, 0, z) * CFrame.Angles(0, a, 0) * CFrame.new(0, 15 * s - 2, -10.2 * s) * CFrame.Angles(-1.084, 0, 0)
		glow(block(Vector3.new(1.6 * s, 0.5, 20 * s), cf, IA.lava, parent), 0.05)
	end
	local smoke = Instance.new("ParticleEmitter")
	smoke.Color = ColorSequence.new(IA.smoke)
	smoke.Transparency = NumberSequence.new(0.3, 1)
	smoke.Size = NumberSequence.new(4, 12)
	smoke.Lifetime = NumberRange.new(4, 6)
	smoke.Speed = NumberRange.new(3, 5)
	smoke.SpreadAngle = Vector2.new(15, 15)
	smoke.EmissionDirection = Enum.NormalId.Top
	smoke.Rate = 2
	smoke.Parent = top
end

local function obsidianSpire(parent: Instance, x: number, z: number, s: number)
	local pool = glow(cyl(5 * s, 0.3, CFrame.new(x, 0.12, z), IA.lava, parent), 0)
	light(pool, IA.lava, 40, 1.6)
	for k = 0, 11 do
		local a = k / 12 * math.pi * 2
		shape("Rock", Vector3.new(3, 1.6, 2.4) * s, CFrame.new(x + math.cos(a) * 5.3 * s, 0.5 * s, z + math.sin(a) * 5.3 * s) * CFrame.Angles(0, -a, 0), Theme.cliffs.lavalake.rockDark, parent).CanCollide = true
	end
	local y = 0
	for k = 0, 3 do
		local h, w = (11 - k * 2) * s, (6.4 - k * 1.2) * s
		local p = shape("Octa", Vector3.new(w, h, w), CFrame.new(x, (y + h / s / 2) * s, z) * CFrame.Angles(0, k * 0.7, 0), IA.obsidian, parent)
		p.Material = Enum.Material.Glass
		y += h / s * 0.8
		glow(shape("Octa", Vector3.new(w * 0.35, h * 0.5, w * 0.35), CFrame.new(x + w * 0.45, (y - h / s * 0.3) * s, z), IA.obsidianGlow, parent), 0.1)
	end
	glow(ball(1.2 * s, Vector3.new(x, (y + 1.6) * s, z), Theme.islands.lavalake.accent, parent), 0)
end

local function magmaCore(parent: Instance, x: number, z: number, s: number)
	local cy = 24 * s
	local orb = glow(ball(6 * s, Vector3.new(x, cy, z), IA.core, parent), 0)
	light(orb, IA.core, 60, 2.5)
	glow(ball(7.2 * s, Vector3.new(x, cy, z), IA.lavaHot, parent), 0.75)
	-- thin orbit rings at three tilts (thick ones turned it into an eye)
	for k = 0, 2 do
		shape("Ring", Vector3.new(17, 0.9, 17) * s, CFrame.new(x, cy, z) * CFrame.Angles(0.35 + k * 0.5, k * 2.1, 0), IA.lavaHot, parent)
	end
	-- floating rocks round it, and two rock pillars that seem to hold it up
	for k = 0, 5 do
		local a = k / 6 * math.pi * 2
		shape("Rock", Vector3.new(3, 2.4, 2.6) * s, CFrame.new(x + math.cos(a) * 12 * s, cy + math.sin(k * 1.7) * 4 * s, z + math.sin(a) * 9 * s) * CFrame.Angles(k, k * 2, 0), Theme.cliffs.magma.rock, parent)
	end
	local half = W.tunnel.width / 2
	for _, side in { -1, 1 } do
		shape("Rock", Vector3.new(10, cy * 1.1, 9), CFrame.new(side * (half - 4), cy * 0.5, z) * CFrame.Angles(0, side, 0), Theme.cliffs.magma.rockDark, parent)
		glow(block(Vector3.new(0.5, cy * 0.8, 0.5), CFrame.new(side * (half - 8.6), cy * 0.45, z - 2), IA.lava, parent), 0.1)
	end
end

local LANDMARKS: { [string]: (Instance, number, number, number) -> () } = { snowman = snowman, mushroom = giantMushroom,
	-- Round 4 phase 6
	toadstoolTower = toadstoolTower, lighthouse = lighthouse, waterfall = waterfall, cactus = giantCactus, arch = stoneArch,
	volcano = volcanoCone, spire = obsidianSpire, core = magmaCore }

-- ---------- gate towers: one style per world (skill designing-map-appeal, World Rules 12) ----------
-- Owner 2026-11-09: "each world's towers should look different". Every gate keeps the same job and
-- footprint (a tower either side of the tunnel, the lintel, the GateGlow beam, the ice bars, the crystal
-- row); each world's towers take their shape, skyline top, material and one modifier from its identity
-- card, so a tower moved to another world would look wrong there (the skill's swap test).
--   castle    round cobblestone keep, crenels, pointed roof in the island colour, pennant (the default)
--   forest    timber watchtower: square log frame, lookout deck, gable roof, pennant
--   grove     toadstool: fat cream stem, giant cap with glowing spots, little mushrooms at its foot
--   beach     sandcastle: three stacked buckets with crenels and shells, a beach umbrella on top
--   jungle    stepped temple: four mossy tiers, a stairway, vines, a shrine with a glowing gem
--   desert    minaret: square sandstone base, slim round shaft, balcony, teal onion dome, lit window
--   canyon    hoodoo: banded rocks stacked with a lean, a wide balanced cap stone, a hanging lantern
--   volcano   basalt cluster: hexagonal columns of different heights, glowing cracks, smoke
--   lavalake  obsidian shards: tilted dark crystals with glowing pink veins
--   magma     forge: riveted iron drum, glowing furnace door, a cone hood and a chimney on fire
--   suntemple sun pillar: fluted marble column, gold capital, a sun disc with rays
-- x = the tower's centre (its sign is the outward side), gz = the gate line, s = archScale, h = gate height
type TowerFn = (gf: Instance, x: number, gz: number, s: number, look: { [string]: Color3 }, h: number) -> ()

local function smokeFrom(p: BasePart, size: number)
	local e = Instance.new("ParticleEmitter")
	e.Color = ColorSequence.new(IA.smoke)
	e.Transparency = NumberSequence.new(0.35, 1)
	e.Size = NumberSequence.new(size, size * 3)
	e.Lifetime = NumberRange.new(3, 4.5)
	e.Speed = NumberRange.new(3, 5)
	e.SpreadAngle = Vector2.new(12, 12)
	e.Rate = 3
	e.Parent = p
end

-- a hexagonal column: three blocks turned 60 degrees apart (flat-to-flat width w)
local function hexColumn(gf: Instance, at: Vector3, w: number, height: number, color: Color3, mat: Enum.Material, collide: boolean?)
	for k = 0, 2 do
		block(Vector3.new(w / math.sqrt(3), height, w), CFrame.new(at + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, k * math.pi / 3, 0), color, gf, collide and k == 0, mat)
	end
end

local GATE_TOWERS: { [string]: TowerFn } = {}

GATE_TOWERS.castle = function(gf, x, gz, s, look, h)
	cyl(4 * s, h + 9 * s, CFrame.new(x, (h + 9 * s) / 2, gz), V.stone, gf, true, Enum.Material.Cobblestone)
	cyl(4.5 * s, 1.1 * s, CFrame.new(x, h + 9.4 * s, gz), V.trim, gf)
	for c = 0, 7 do
		local a = c * math.pi / 4
		block(Vector3.new(1.3, 1.5, 1.3) * s, CFrame.new(x + math.cos(a) * 3.9 * s, h + 10.7 * s, gz + math.sin(a) * 3.9 * s), V.stone, gf, false, Enum.Material.Cobblestone)
	end
	shape("Cone", Vector3.new(9.6, 9, 9.6) * s, CFrame.new(x, h + 16 * s, gz), look.accent, gf)
	cyl(0.15 * s, 4 * s, CFrame.new(x, h + 22 * s, gz), V.iron, gf)
	block(Vector3.new(0.15, 1.4, 2.4) * s, CFrame.new(x, h + 23.1 * s, gz + 1.2 * s), look.accent, gf)
	-- a lit arrow slit
	glow(block(Vector3.new(0.6, 2.2, 0.3) * s, CFrame.new(x - math.sign(x) * 3.9 * s, h + 3 * s, gz - 0.6 * s) * CFrame.Angles(0, -math.sign(x) * 0.9, 0), A.lanternGlow, gf), 0.1)
end

GATE_TOWERS.forest = function(gf, x, gz, s, look, h)
	local log, plank, wood = V.door, HA.boothWood, Enum.Material.Wood
	block(Vector3.new(10, 3, 10) * s, CFrame.new(x, 1.5 * s, gz), Theme.cliffs.forest.rock, gf, true, Enum.Material.Cobblestone)
	local deck = h + 6 * s
	-- the planked core and four log legs round it
	block(Vector3.new(6 * s, deck - 3 * s, 6 * s), CFrame.new(x, 3 * s + (deck - 3 * s) / 2, gz), plank, gf, true, Enum.Material.WoodPlanks)
	for _, cx in { -3.6, 3.6 } do
		for _, cz in { -3.6, 3.6 } do
			cyl(0.8 * s, deck, CFrame.new(x + cx * s, deck / 2, gz + cz * s), log, gf, false, wood)
		end
	end
	-- log bands and an X brace on the side you walk toward
	for _, y in { deck * 0.4, deck * 0.75, deck - 0.4 * s } do
		for _, c in { -3.6, 3.6 } do
			block(Vector3.new(8 * s, 0.7 * s, 0.7 * s), CFrame.new(x, y, gz + c * s), log, gf, false, wood)
			block(Vector3.new(0.7 * s, 0.7 * s, 8 * s), CFrame.new(x + c * s, y, gz), log, gf, false, wood)
		end
	end
	local dy, dx = deck * 0.75 - deck * 0.4, 7.2 * s
	for _, sgn in { -1, 1 } do
		block(Vector3.new(math.sqrt(dx * dx + dy * dy), 0.5 * s, 0.5 * s), CFrame.new(x, deck * 0.575, gz - 3.9 * s) * CFrame.Angles(0, 0, sgn * math.atan2(dy, dx)), log, gf, false, wood)
	end
	-- the lookout deck with its rail, a warm lamp inside and the roof posts
	block(Vector3.new(10.5, 0.8, 10.5) * s, CFrame.new(x, deck + 0.4 * s, gz), plank, gf, false, Enum.Material.WoodPlanks)
	for _, c in { -5, 5 } do
		block(Vector3.new(10.5 * s, 0.4 * s, 0.4 * s), CFrame.new(x, deck + 2 * s, gz + c * s), log, gf, false, wood)
		block(Vector3.new(0.4 * s, 0.4 * s, 10.5 * s), CFrame.new(x + c * s, deck + 2 * s, gz), log, gf, false, wood)
	end
	for _, cx in { -4.6, 4.6 } do
		for _, cz in { -4.6, 4.6 } do
			cyl(0.4 * s, 4.4 * s, CFrame.new(x + cx * s, deck + 3 * s, gz + cz * s), log, gf, false, wood)
		end
	end
	local lamp = glow(ball(0.8 * s, Vector3.new(x, deck + 2.2 * s, gz), A.lanternGlow, gf), 0.1)
	light(lamp, A.lanternGlow, 18, 0.8)
	-- the gable roof (ridge along x) with filled ends, and a pennant on the ridge
	local eave, rh, w, d = deck + 5.2 * s, 4.5 * s, 12 * s, 12 * s
	wedge(Vector3.new(w, rh, d / 2), CFrame.new(x, eave + rh / 2, gz - d / 4), look.wall, gf, Enum.Material.WoodPlanks)
	wedge(Vector3.new(w, rh, d / 2), CFrame.new(x, eave + rh / 2, gz + d / 4) * CFrame.Angles(0, math.pi, 0), look.wall, gf, Enum.Material.WoodPlanks)
	for _, ex in { -w / 2 + 1.2 * s, w / 2 - 1.2 * s } do
		wedge(Vector3.new(0.3 * s, rh - 0.3 * s, d / 2 - 1.2 * s), CFrame.new(x + ex, eave + (rh - 0.3 * s) / 2, gz - (d / 2 - 1.2 * s) / 2), plank, gf, Enum.Material.WoodPlanks)
		wedge(Vector3.new(0.3 * s, rh - 0.3 * s, d / 2 - 1.2 * s), CFrame.new(x + ex, eave + (rh - 0.3 * s) / 2, gz + (d / 2 - 1.2 * s) / 2) * CFrame.Angles(0, math.pi, 0), plank, gf, Enum.Material.WoodPlanks)
	end
	cyl(0.15 * s, 5 * s, CFrame.new(x, eave + rh + 2.2 * s, gz), V.iron, gf)
	block(Vector3.new(0.15, 1.4, 2.6) * s, CFrame.new(x, eave + rh + 4 * s, gz + 1.3 * s), look.accent, gf)
end

GATE_TOWERS.grove = function(gf, x, gz, s, look, h)
	local sx = math.sign(x)
	local stemH = h + 8 * s
	quiet(ellipsoid(Vector3.new(10, 4, 10) * s, CFrame.new(x, 1 * s, gz), IA.toadStem, gf))
	cyl(3 * s, stemH, CFrame.new(x, stemH / 2, gz), IA.toadStem, gf, true)
	quiet(ellipsoid(Vector3.new(7.4, 9, 7.4) * s, CFrame.new(x, stemH * 0.42, gz), IA.toadStem, gf)) -- the stem's belly
	-- the gills under the cap, then the cap itself
	cyl(6.6 * s, 0.6 * s, CFrame.new(x, stemH + 0.3 * s, gz), look.light, gf)
	local capY = stemH + 0.4 * s
	shape("Dome", Vector3.new(15, 7, 15) * s, CFrame.new(x, capY + 3.5 * s, gz), look.accent, gf)
	-- spots that glow softly (the modifier): a ring on the slope and one on top
	for k = 0, 5 do
		local a = k * math.pi / 3 + 0.3
		glow(ball(1 * s, Vector3.new(x + math.cos(a) * 4.6 * s, capY + 5.2 * s, gz + math.sin(a) * 4.6 * s), IA.toadSpot, gf), 0.05)
	end
	glow(ball(1.2 * s, Vector3.new(x, capY + 6.8 * s, gz), IA.toadSpot, gf), 0.05)
	-- little mushrooms at its foot, on the outside
	mushroom(gf, Vector3.new(x + sx * 6.5 * s, 0, gz - 2 * s), 2.2 * s, 0.4, IA.toadCaps[2])
	mushroom(gf, Vector3.new(x + sx * 4.5 * s, 0, gz - 6 * s), 1.5 * s, 1.1, IA.toadCaps[3])
end

GATE_TOWERS.beach = function(gf, x, gz, s, look, h)
	-- three stacked sand buckets, each with a darker rim and crenels
	local tiers = { { r = 4.6, h = 10 }, { r = 3.7, h = 9 }, { r = 2.8, h = 8 } }
	local y = 0
	for i, t in tiers do
		cyl(t.r * s, t.h * s, CFrame.new(x, y + t.h * s / 2, gz), if i % 2 == 1 then look.wall else look.floor, gf, i == 1, Enum.Material.Sand)
		y += t.h * s
		cyl((t.r + 0.3) * s, 0.7 * s, CFrame.new(x, y - 0.35 * s, gz), look.wallBase, gf, false, Enum.Material.Sand)
		local n = 10 - i * 2
		for c = 0, n - 1 do
			local a = c * 2 * math.pi / n
			block(Vector3.new(1.2, 1.3, 1.2) * s, CFrame.new(x + math.cos(a) * (t.r - 0.5) * s, y + 0.65 * s, gz + math.sin(a) * (t.r - 0.5) * s) * CFrame.Angles(0, -a, 0), look.wall, gf, false, Enum.Material.Sand)
		end
	end
	-- shells and starfish pressed into the sand on the side you walk toward
	for k = 0, 4 do
		local a = -math.pi / 2 + (k - 2) * 0.45
		local r = tiers[k % 2 + 1].r
		local at = Vector3.new(x + math.cos(a) * r * s, 3 * s + (k % 2) * 10 * s, gz + math.sin(a) * r * s)
		quiet(ellipsoid(Vector3.new(1.4, 1.2, 0.6) * s, CFrame.lookAt(at, at + Vector3.new(math.cos(a), 0, math.sin(a))), if k % 2 == 0 then IA.shell else IA.starfish, gf))
	end
	-- the beach umbrella on top: pole, red canopy, white trim and a white knob
	cyl(0.25 * s, 6 * s, CFrame.new(x, y + 3 * s, gz), IA.umbrellaStripe, gf)
	shape("Cone", Vector3.new(11, 3, 11) * s, CFrame.new(x, y + 6.8 * s, gz), IA.umbrella[1], gf)
	cyl(5.6 * s, 0.35 * s, CFrame.new(x, y + 5.4 * s, gz), IA.umbrellaStripe, gf)
	ball(0.6 * s, Vector3.new(x, y + 8.5 * s, gz), IA.umbrellaStripe, gf)
end

GATE_TOWERS.jungle = function(gf, x, gz, s, look, h)
	local cl = Theme.cliffs.jungle
	local tiers = { { w = 10, h = 7 }, { w = 8.4, h = 7 }, { w = 6.8, h = 6 }, { w = 5.2, h = 5 } }
	local y = 0
	for i, t in tiers do
		block(Vector3.new(t.w, t.h, t.w) * s, CFrame.new(x, y + t.h * s / 2, gz), if i % 2 == 1 then cl.rock else cl.rockDark, gf, i == 1, Enum.Material.Slate)
		y += t.h * s
		-- a mossy lip on each step
		quiet(block(Vector3.new(t.w + 0.4, 0.5, t.w + 0.4) * s, CFrame.new(x, y + 0.1 * s, gz), cl.top, gf, false, Enum.Material.Grass))
		-- vines hanging over the front edge
		for v = -1, 1, 2 do
			local len = (2.5 + (i % 2) * 1.5) * s
			quiet(block(Vector3.new(0.3, 0, 0.3) * s + Vector3.new(0, len, 0), CFrame.new(x + v * t.w * 0.28 * s, y - len / 2, gz - t.w / 2 * s - 0.2 * s), IA.vine, gf))
		end
	end
	-- the stairway up the front, as one ramp
	local stairH = (7 + 7 + 6) * s
	wedge(Vector3.new(3 * s, stairH, 6 * s), CFrame.new(x, stairH / 2, gz - 5 * s - 3 * s), cl.rockDark, gf, Enum.Material.Slate)
	-- the shrine on top, its dark doorway and the glowing gem (the modifier)
	block(Vector3.new(4, 3.5, 4) * s, CFrame.new(x, y + 1.75 * s, gz), cl.rock, gf, false, Enum.Material.Slate)
	block(Vector3.new(1.6, 2.4, 0.2) * s, CFrame.new(x, y + 1.2 * s, gz - 2 * s), IA.shrineDoor, gf)
	block(Vector3.new(5.4, 0.8, 5.4) * s, CFrame.new(x, y + 3.9 * s, gz), cl.rockDark, gf, false, Enum.Material.Slate)
	local gem = glow(shape("Octa", Vector3.new(2.2, 4, 2.2) * s, CFrame.new(x, y + 6.4 * s, gz), look.accent, gf), 0.05)
	light(gem, look.accent, 24, 1.2)
end

GATE_TOWERS.desert = function(gf, x, gz, s, look, h)
	-- the square base with a pointed niche facing you
	block(Vector3.new(9, 10, 9) * s, CFrame.new(x, 5 * s, gz), look.wall, gf, true, Enum.Material.Sandstone)
	block(Vector3.new(9.6, 0.8, 9.6) * s, CFrame.new(x, 10.2 * s, gz), look.wallBase, gf, false, Enum.Material.Sandstone)
	block(Vector3.new(2.4, 4, 0.3) * s, CFrame.new(x, 4 * s, gz - 4.5 * s), look.wallBase, gf)
	ellipsoid(Vector3.new(2.4, 2.6, 0.3) * s, CFrame.new(x, 6 * s, gz - 4.5 * s), look.wallBase, gf)
	-- the slim shaft with painted bands
	local shaftH = h + 2 * s
	cyl(2.6 * s, shaftH, CFrame.new(x, 10.6 * s + shaftH / 2, gz), look.floor, gf, false, Enum.Material.Sandstone)
	for _, f in { 0.35, 0.7 } do
		cyl(2.75 * s, 0.8 * s, CFrame.new(x, 10.6 * s + shaftH * f, gz), IA.minaretTeal, gf)
	end
	-- the balcony: a disc and an eight-sided rail
	local by = 10.6 * s + shaftH
	cyl(3.8 * s, 0.8 * s, CFrame.new(x, by, gz), look.wallBase, gf, false, Enum.Material.Sandstone)
	for c = 0, 7 do
		local a = c * math.pi / 4 + math.pi / 8
		block(Vector3.new(2.9, 1.2, 0.3) * s, CFrame.new(x + math.cos(a) * 3.5 * s, by + 1 * s, gz + math.sin(a) * 3.5 * s) * CFrame.Angles(0, -a + math.pi / 2, 0), look.wall, gf, false, Enum.Material.Sandstone)
	end
	-- the upper drum with a lit window (the modifier), the onion dome and its spike
	cyl(2 * s, 4 * s, CFrame.new(x, by + 2.4 * s, gz), look.floor, gf, false, Enum.Material.Sandstone)
	local win = glow(block(Vector3.new(1, 1.8, 0.3) * s, CFrame.new(x, by + 2.4 * s, gz - 2 * s), look.light, gf), 0.05)
	light(win, look.light, 16, 0.8)
	ellipsoid(Vector3.new(5.6, 6, 5.6) * s, CFrame.new(x, by + 6.6 * s, gz), IA.minaretTeal, gf)
	shape("Cone", Vector3.new(2.8, 3.4, 2.8) * s, CFrame.new(x, by + 10.2 * s, gz), IA.minaretTeal, gf)
	cyl(0.15 * s, 3 * s, CFrame.new(x, by + 12.8 * s, gz), IA.forgeBrass, gf)
	ball(0.5 * s, Vector3.new(x, by + 14.4 * s, gz), IA.forgeBrass, gf)
end

GATE_TOWERS.canyon = function(gf, x, gz, s, look, h)
	local sx = math.sign(x)
	-- banded rocks stacked with a slight outward lean, pinched at the neck
	local stack = { { 10, 9, 10 }, { 7.4, 8, 7.4 }, { 8.4, 7, 8 }, { 6, 6, 6 } }
	local y = 0
	for i, d in stack do
		local hh = d[2] * s
		shape("Rock", Vector3.new(d[1], d[2], d[3]) * s, CFrame.new(x + sx * (i - 1) * 0.5 * s, y + hh / 2, gz) * CFrame.Angles(0, i * 1.3, 0), if i % 2 == 1 then IA.hoodoo else IA.hoodooBand, gf)
		y += hh - 0.8 * s
	end
	-- the collider for the stack (rock meshes are looks only)
	local core = block(Vector3.new(6, y / s, 6) * s, CFrame.new(x, y / 2, gz), IA.hoodoo, gf, true)
	core.Transparency = 1
	-- the wide cap stone balanced on top
	shape("Rock", Vector3.new(13, 3.6, 11) * s, CFrame.new(x + sx * 2 * s, y + 1.4 * s, gz) * CFrame.Angles(0.06, 0.5, -sx * 0.08), IA.hoodooCap, gf)
	-- a wooden arm with a hanging lantern (the modifier)
	local ay = y * 0.55
	block(Vector3.new(0.7, 0.7, 7) * s, CFrame.new(x, ay, gz - 5.5 * s), V.door, gf, false, Enum.Material.Wood)
	cyl(0.08 * s, 1.6 * s, CFrame.new(x, ay - 1.1 * s, gz - 8.5 * s), V.iron, gf)
	local lamp = glow(block(Vector3.new(1, 1.4, 1) * s, CFrame.new(x, ay - 2.4 * s, gz - 8.5 * s), A.lanternGlow, gf), 0.1)
	light(lamp, A.lanternGlow, 16, 0.8)
end

GATE_TOWERS.volcano = function(gf, x, gz, s, look, h)
	local cl = Theme.cliffs.volcano
	-- a cluster of hexagonal basalt columns: the tallest in the middle
	local cols = { { 0, 0, h + 14 * s }, { 3, 0, h + 6 * s }, { -1.5, 2.6, h + 9 * s }, { -1.5, -2.6, h + 2 * s }, { 1.5, -2.6, h + 10 * s }, { 1.5, 2.6, h + 4 * s }, { -3, 0, h + 7 * s } }
	for i, c in cols do
		local at = Vector3.new(x + c[1] * s, 0, gz + c[2] * s)
		hexColumn(gf, at, 3.2 * s, c[3], if i % 2 == 0 then cl.rock else cl.rockDark, Enum.Material.Basalt, i == 1)
		quiet(block(Vector3.new(3.2 / math.sqrt(3), 0.4, 3.2) * s, CFrame.new(at + Vector3.new(0, c[3] + 0.2 * s, 0)), cl.top, gf, false, Enum.Material.Basalt))
	end
	local core = block(Vector3.new(8.5, 1, 8.5) * s + Vector3.new(0, h, 0), CFrame.new(x, h / 2, gz), cl.rock, gf, true)
	core.Transparency = 1
	-- glowing cracks running up the columns you walk toward
	for _, c in { cols[4], cols[5], cols[1] } do
		glow(block(Vector3.new(0.35 * s, c[3] * 0.55, 0.35 * s), CFrame.new(x + c[1] * s, c[3] * 0.35, gz + c[2] * s - 1.65 * s), IA.lava, gf), 0)
	end
	-- the tallest column smokes (the modifier), an ember at its top
	local ember = glow(ball(1 * s, Vector3.new(x, cols[1][3] + 0.6 * s, gz), IA.ember, gf), 0)
	light(ember, IA.lava, 20, 1.2)
	smokeFrom(ember, 2.5 * s)
end

GATE_TOWERS.lavalake = function(gf, x, gz, s, look, h)
	local sx = math.sign(x)
	shape("Rock", Vector3.new(11, 4, 10) * s, CFrame.new(x, 1.2 * s, gz), IA.obsidian, gf)
	local core = block(Vector3.new(6, 1, 6) * s + Vector3.new(0, h + 8 * s, 0), CFrame.new(x, (h + 8 * s) / 2, gz), IA.obsidian, gf, true)
	core.Transparency = 1
	-- tilted shards: { offset x, offset z, width, height, lean out, lean forward }
	-- (wide and matte: thin or shiny shards read as pale slivers against the sky)
	local shards = { { 0, 0, 10, 36, 0.1, 0 }, { 2.6, -2.2, 7, 22, 0.4, -0.25 }, { -2.4, 1.8, 6, 19, -0.3, 0.2 }, { 1.8, 2.6, 5, 14, 0.25, 0.35 } }
	for i, d in shards do
		local cf = CFrame.new(x + sx * d[1] * s, d[4] * s * 0.38, gz + d[2] * s) * CFrame.Angles(d[6], 0, -sx * d[5])
		shape("Octa", Vector3.new(d[3], d[4], d[3]) * s, cf, IA.obsidian, gf)
		-- a glowing vein down its face (the modifier)
		if i <= 3 then
			glow(shape("Octa", Vector3.new(d[3] * 0.18, d[4] * 0.8, d[3] * 0.18) * s, cf * CFrame.new(0, 0, -d[3] * s * 0.36), look.accent, gf), 0.05)
		end
	end
	local base = glow(shape("Octa", Vector3.new(2, 5, 2) * s, CFrame.new(x - sx * 3.5 * s, 2 * s, gz - 3.5 * s) * CFrame.Angles(0.3, 0, sx * 0.4), IA.obsidianGlow, gf), 0)
	light(base, look.accent, 20, 1.2)
end

GATE_TOWERS.magma = function(gf, x, gz, s, look, h)
	local sx = math.sign(x)
	local drumH = h + 4 * s
	cyl(4.4 * s, drumH, CFrame.new(x, drumH / 2, gz), IA.forgeIron, gf, true, Enum.Material.Metal)
	-- brass bands with rivets
	for _, f in { 0.12, 0.55, 0.96 } do
		local by = drumH * f
		cyl(4.6 * s, 0.9 * s, CFrame.new(x, by, gz), IA.forgeBrass, gf, false, Enum.Material.Metal)
		if f < 0.9 then
			for c = 0, 9 do
				local a = c * math.pi / 5
				ball(0.3 * s, Vector3.new(x + math.cos(a) * 4.65 * s, by, gz + math.sin(a) * 4.65 * s), IA.forgeIron, gf)
			end
		end
	end
	-- the furnace door, glowing hot (the modifier's first half)
	block(Vector3.new(4, 5, 0.6) * s, CFrame.new(x, 5.5 * s, gz - 4.2 * s), IA.coreRing, gf, false, Enum.Material.Metal)
	local door = glow(block(Vector3.new(3, 4, 0.4) * s, CFrame.new(x, 5.5 * s, gz - 4.5 * s), IA.lavaHot, gf), 0)
	light(door, IA.lava, 22, 1.4)
	-- the cone hood, the chimney and its fire
	shape("Cone", Vector3.new(10, 4.5, 10) * s, CFrame.new(x, drumH + 2.2 * s, gz), IA.forgeIron, gf)
	local cx = x + sx * 1.6 * s
	cyl(1.2 * s, 10 * s, CFrame.new(cx, drumH + 5 * s, gz), IA.forgeIron, gf, false, Enum.Material.Metal)
	cyl(1.45 * s, 0.8 * s, CFrame.new(cx, drumH + 9.8 * s, gz), IA.forgeBrass, gf, false, Enum.Material.Metal)
	local mouth = glow(cyl(1 * s, 0.3 * s, CFrame.new(cx, drumH + 10.2 * s, gz), IA.lavaHot, gf), 0)
	local fire = Instance.new("Fire")
	fire.Color = IA.lava
	fire.SecondaryColor = look.accent
	fire.Size = 4 * s
	fire.Heat = 9
	fire.Parent = mouth
end

GATE_TOWERS.suntemple = function(gf, x, gz, s, look, h)
	block(Vector3.new(9, 2, 9) * s, CFrame.new(x, 1 * s, gz), look.wallTop, gf, true, Enum.Material.Marble)
	local colH = h + 6 * s
	cyl(3 * s, colH, CFrame.new(x, 2 * s + colH / 2, gz), IA.marble, gf, true, Enum.Material.Marble)
	-- flutes: darker strips round the column
	for c = 0, 7 do
		local a = c * math.pi / 4
		block(Vector3.new(0.45 * s, colH - 1.5 * s, 0.45 * s), CFrame.new(x + math.cos(a) * 2.95 * s, 2 * s + colH / 2, gz + math.sin(a) * 2.95 * s), look.wall, gf)
	end
	-- the gold capital
	local top = 2 * s + colH
	cyl(3.6 * s, 1.2 * s, CFrame.new(x, top + 0.6 * s, gz), IA.sunGold, gf, false, Enum.Material.Metal)
	block(Vector3.new(8, 1.4, 8) * s, CFrame.new(x, top + 1.9 * s, gz), IA.sunGold, gf, false, Enum.Material.Metal)
	-- the sun disc facing you, a glowing core (the modifier) and twelve rays
	local cy = top + 8 * s
	local disc = CFrame.new(x, cy, gz) * CFrame.Angles(math.pi / 2, 0, 0)
	cyl(4 * s, 0.8 * s, disc, IA.sunGold, gf, false, Enum.Material.Metal)
	local coreDisc = glow(cyl(2.4 * s, 0.4 * s, disc * CFrame.new(0, -0.5 * s, 0), look.light, gf), 0)
	light(coreDisc, look.accent, 26, 1.2)
	for k = 0, 11 do
		local a = k * math.pi / 6
		block(Vector3.new(0.8, 2.6, 0.6) * s, CFrame.new(x + math.cos(a) * 5.4 * s, cy + math.sin(a) * 5.4 * s, gz) * CFrame.Angles(0, 0, a - math.pi / 2), IA.sunGold, gf, false, Enum.Material.Metal)
	end
	block(Vector3.new(1.2, 3.4, 1.2) * s, CFrame.new(x, top + 3.6 * s, gz), IA.sunGold, gf, false, Enum.Material.Metal) -- the disc's stem
end

-- the lintel across the tunnel: each world's own material (only the castle keeps the snow on it)
local GATE_LINTELS: { [string]: { color: Color3, mat: Enum.Material } } = {
	castle = { color = V.stone, mat = Enum.Material.Cobblestone },
	forest = { color = V.door, mat = Enum.Material.Wood },
	grove = { color = IA.toadStem, mat = Enum.Material.SmoothPlastic },
	beach = { color = Theme.islands.beach.wall, mat = Enum.Material.Sand },
	jungle = { color = Theme.cliffs.jungle.rock, mat = Enum.Material.Slate },
	desert = { color = Theme.islands.desert.wall, mat = Enum.Material.Sandstone },
	canyon = { color = V.door, mat = Enum.Material.Wood },
	volcano = { color = Theme.cliffs.volcano.rockDark, mat = Enum.Material.Basalt },
	lavalake = { color = IA.obsidian, mat = Enum.Material.SmoothPlastic },
	magma = { color = IA.forgeIron, mat = Enum.Material.Metal },
	suntemple = { color = IA.marble, mat = Enum.Material.Marble },
}

-- a gatehouse in front of a section: the island's own towers (GATE_TOWERS), its lintel with the
-- crystal row, the glowing beam (GateGlow) and the ice bars
local function gatehouse(parent: Instance, gz: number, theme: string, id: number, withBars: boolean, soon: boolean?)
	local T, G = W.tunnel, W.gate
	local half = T.width / 2
	local look = Theme.islands[theme] or Theme.islands.meadow
	local gf = folder("Gate" .. id, parent)
	local s = T.archScale -- the towers, roofs and lintel grow with the tunnel (the span is the tunnel's own width)
	local style = if GATE_TOWERS[theme] then theme else "castle"
	for _, x in { -half - 2 * s, half + 2 * s } do
		GATE_TOWERS[style](gf, x, gz, s, look, G.height)
	end
	local lin = GATE_LINTELS[style]
	block(Vector3.new(T.width + 2, 2.2 * s, 2.6 * s), CFrame.new(0, G.height + 2.6 * s, gz + 0.4), lin.color, gf, false, lin.mat)
	if style == "castle" then
		quiet(ellipsoid(Vector3.new(T.width + 4, 1.2 * s, 3.2 * s), CFrame.new(0, G.height + 3.8 * s, gz + 0.4), A.snowCap, gf))
	end
	local beam = glow(block(Vector3.new(T.width - 2, 1.6 * s, 1.6 * s), CFrame.new(0, G.height + 0.6 * s, gz), look.accent, gf), 0.15)
	beam.Name = "GateGlow"
	for k = 0, 8 do
		local cx = -half + 6 + k * (T.width - 12) / 8
		glow(shape("Octa", Vector3.new(1.4, 2.6, 1.4) * s, CFrame.new(cx, G.height + 5 * s, gz + 0.4), A.crystalGlow, gf), 0.15)
	end
	if soon then
		-- Round 4 phase 6: frosted glass you can see the island through, glowing round its edges
		-- (MapController clears it on a tester's screen once the gate is open)
		local panel = block(Vector3.new(T.width - 2, G.height - 0.5, 0.6), CFrame.new(0, G.height / 2, gz - 1.4), HA.endCap, gf, false, Enum.Material.SmoothPlastic) -- not Glass: Roblox hides signs and glows behind glass
		panel.Name = "SoonPanel" .. id
		panel.Transparency = 0.35
		panel.CastShadow = false
		for _, x in { -half + 1.2, half - 1.2 } do
			local edge = glow(block(Vector3.new(0.9, G.height, 0.9), CFrame.new(x, G.height / 2, gz - 1.4), HA.endCapGlow, gf), 0.1)
			edge.Name = "GateGlow"
		end
	end
	if withBars then
		local bars = folder("GateBars" .. id, gf)
		local x = -half + G.barGap
		while x < half - 1 do
			local bar = block(Vector3.new(0.8, G.height - 1, 0.8), CFrame.new(x, (G.height - 1) / 2, gz), A.iceBar, bars, false, Enum.Material.Ice)
			bar.Transparency = 0.2
			x += G.barGap
		end
	end
	return gf
end

local function section(parent: Instance, zone: Config.Zone, isl: Config.Island, trees: { Scenery.Tree }, rng: () -> number)
	local look = Theme.islands[isl.theme] or Theme.islands.meadow
	local cl = Theme.cliffs[isl.theme] or Theme.cliffs.meadow
	local f = folder("Section" .. zone.id, parent)
	local kind = if isl.trees then isl.trees.kind else "pine"
	cliffs(f, zone, cl, kind, rng)
	-- the floor blends into the cliffs: a darker strip of earth (snow, sand...) at their foot (World Rules 9)
	local E, half = C.edge, W.tunnel.width / 2
	local mats = Theme.islandMats[isl.theme]
	local sw, len = half - E.stripFrom, zone.zMax - zone.zMin
	for _, side in { -1, 1 } do
		quiet(block(Vector3.new(sw, E.stripHeight, len), CFrame.new(side * (E.stripFrom + sw / 2), E.stripHeight / 4, (zone.zMin + zone.zMax) / 2),
			look.floor:Lerp(cl.rockDark, E.stripDarken), f, false, if mats then mats.floor else Enum.Material.Ground))
	end
	pathDetail(f, zone, look)
	-- the trees that give shade (Shared/Scenery's spots)
	local tf = folder("Trees", f)
	for _, t in trees do
		if t.z >= zone.zMin and t.z < zone.zMax then
			tree(t.x, 0, t.z, t.r / C.treeUnitRadius, rng() * 6, t.kind, tf)
		end
	end
	if PROPS[isl.theme] then
		PROPS[isl.theme](f, zone, trees, rng)
	elseif isl.theme == "meadow" then
		meadowProps(f, zone, trees, rng)
	else
		forestProps(f, zone, trees, rng)
	end
	hazards(f, zone)
	if isl.landmark and isl.landmarkAt and LANDMARKS[isl.landmark] then
		LANDMARKS[isl.landmark](f, isl.landmarkAt.x, zone.zMin + isl.landmarkAt.z, isl.landmarkScale or C.landmarkScale)
	end
	local gz = WorldRules.gateZ(zone.id)
	if gz then
		gatehouse(f, gz, isl.theme, zone.id, true, not zone.ready)
	end
end

-- after the last open island: a frosted gate, glowing, with the next island's colour behind it
local function endCap(parent: Instance)
	local T, E = W.tunnel, W.endCap
	local f = folder("EndCapArt", parent)
	local half, z = T.width / 2, W.tunnelEnd
	local nxt = W.nextIsland
	local look = Theme.islands[if nxt then nxt.theme else "grove"] or Theme.islands.grove
	local cl = Theme.cliffs[if nxt then nxt.theme else "grove"] or Theme.cliffs.grove
	local panel = block(Vector3.new(T.width, E.height, 1), CFrame.new(0, E.height / 2, z + 0.6), HA.endCap, f, false, Enum.Material.Glass)
	panel.Transparency = 0.35
	panel.CastShadow = false
	local top = glow(block(Vector3.new(T.width, 1.4, 1.4), CFrame.new(0, E.height + 1.6, z + 0.6), HA.endCapGlow, f), 0.1)
	top.Name = "GateGlow"
	gatehouse(f, z + 0.6, if nxt then nxt.theme else "grove", 99, false)
	-- the hint behind it: the next island's ground, cliffs, a few of its shapes and its glow
	local d = E.glowDepth
	block(Vector3.new(T.width + T.wallThick * 2 + 40, 2, d + 20), CFrame.new(0, -1, z + E.depth + d / 2 + 10), look.floor, f)
	for _, side in { -1, 1 } do
		for k = 0, 3 do
			shape("Rock", Vector3.new(12, 20 + k * 3, 10), CFrame.new(side * (half + 6), 8, z + 8 + k * 9), cl.rock, f)
		end
	end
	for k = 0, 5 do
		local s = 1.6 + (k % 2) * 0.8
		local at = Vector3.new(-25 + k * 10, 0, z + 14 + (k % 2) * 8)
		if not nxt or nxt.theme == "grove" then
			mushroom(f, at, s * 1.4, k, look.accent)
		else -- Round 4 phase 6: tall pillars in the next island's colour, lit at the top
			cyl(1.3 * s, 9 * s, CFrame.new(at + Vector3.new(0, 4.5 * s, 0)), look.accent, f)
			glow(ball(1 * s, at + Vector3.new(0, 9.6 * s, 0), look.light, f), 0.1)
		end
	end
	local back = block(Vector3.new(T.width + T.wallThick * 2 + 40, T.wallHeight + 14, 1), CFrame.new(0, (T.wallHeight + 14) / 2, z + E.depth + d + 20), look.accent, f)
	back.CastShadow = false
	glow(block(Vector3.new(T.width, 1.2, 1.2), CFrame.new(0, 0.6, z + E.depth + d - 1), look.light, f), 0.1)
end

-- ---------- far scenery: snowy peaks, rolling hills and ground all round ----------
local function peak(parent: Instance, x: number, z: number, r: number, h: number, snowLine: number, low: Color3)
	local cy = h / 2 - 4
	far(shape("Cone", Vector3.new(r * 2, h, r * 2), CFrame.new(x, cy, z), low, parent))
	if snowLine < 1 then
		local top = 1 - snowLine
		far(shape("Cone", Vector3.new(r * 2 * top + 0.5, h * top + 0.2, r * 2 * top + 0.5), CFrame.new(x, cy + h / 2 - h * top / 2 + 0.1, z), A.peakSnow, parent))
	end
end

local function farScenery(parent: Instance, rng: () -> number)
	local H = W.hub
	-- the ground everywhere outside: snow round the hub and the meadow, grass from the forest on
	local forestZ = if W.zones[2] then W.zones[2].zMin else W.tunnelEnd
	far(block(Vector3.new(1400, 1, forestZ + 700), CFrame.new(0, -0.65, (forestZ - 700) / 2), A.snowA, parent, false, Enum.Material.Snow))
	-- Round 4 phase 6: from the forest on, each island's own ground (sea by the beach, lava past the lake)
	for _, zone in W.zones do
		if zone.id >= 2 then
			local look = Theme.islands[zone.theme]
			local z1 = if zone.id == #W.zones then zone.zMax + 900 else zone.zMax
			local mats = Theme.islandMats[zone.theme]
			far(block(Vector3.new(1400, 1, z1 - zone.zMin), CFrame.new(0, -0.65, (zone.zMin + z1) / 2), (look and look.far) or A.grassA, parent, false,
				if mats and zone.theme ~= "lavalake" and zone.theme ~= "magma" and zone.theme ~= "beach" then mats.floor else Enum.Material.Grass))
		end
	end
	for i = 0, 8 do
		peak(parent, -240 + i * 60, H.zMin - 140 - (i % 3) * 40, 46 + (i % 4) * 10, 90 + (i % 5) * 22, 0.5, A.peakLow)
	end
	local len = W.tunnelEnd - H.zMin
	for i = 0, C.farPeaks - 1 do
		local z = H.zMin + (i + 0.5) * len / C.farPeaks
		local zid = WorldRules.zoneAt(Vector3.new(0, 0, z))
		local snowy = zid <= 1
		local zlook = if zid > 0 then Theme.islands[(Config.zone(zid) :: Config.Zone).theme] else nil
		local hill = if snowy then A.snowB elseif zlook and zlook.peak then zlook.peak else A.forestHill
		local isl = W.islands[zid]
		local farKind = if snowy then "snowpine" elseif isl and isl.trees then isl.trees.kind else "pine"
		for _, side in { -1, 1 } do
			peak(parent, side * (200 + (i % 3) * 30), z, 60, 70 + ((i + (side + 1) / 2) % 3) * 20, if snowy then 0.55 else 1.1, if snowy then A.peakLow elseif zlook and zlook.peak then zlook.peak else A.peakGreen)
			-- rolling hills between the cliffs and the peaks (along the islands only: round the hub the village is there)
			local hz = z + (rng() - 0.5) * 30
			if hz < W.hubZMax + 30 then
				continue
			end
			far(ellipsoid(Vector3.new(70, 18 + rng() * 10, 60), CFrame.new(side * (110 + rng() * 30), 0, hz), hill, parent))
			if not snowy or rng() < 0.6 then
				for t = 0, 2 do
					farTree(side * (95 + rng() * 50), 2, hz + (t - 1) * 14, 2 + rng(), farKind, parent)
				end
			end
		end
	end
end

-- Parts no camera can ever see: every corner inside a bigger, solid, still block (coins packed inside
-- the Sell chest, booth backs inside the hub wall, props sunk in island ground). PERF-AUDIT-2026-11-09.
-- Runs after the whole map is built, so the random layout of everything else is unchanged. Only the
-- booths and tunnel props are checked; a block can hide them only if nothing ever moves, restyles or
-- fades it (no pans, gate bars, motion folders, see-through or neon blocks).
local function stillBlock(p: Instance): boolean
	if p.ClassName ~= "Part" or (p :: Part).Shape ~= Enum.PartType.Block then
		return false
	end
	local b = p :: Part
	if b.Transparency ~= 0 or b.Material == Enum.Material.Neon then
		return false
	end
	if b:FindFirstChildWhichIsA("DataModelMesh") then
		return false -- drawn as another shape (ellipsoid() is a Block with a sphere mesh): its box hides nothing
	end
	local x: Instance? = b.Parent
	while x and x.Name ~= "Art" do
		if CollectionService:HasTag(x, Config.mapFx.motionTag) or string.match(x.Name, "^Pan%d") or string.match(x.Name, "^GateBars") then
			return false
		end
		x = x.Parent
	end
	return true
end

local function pruneBuried(art: Instance): number
	local CELL = 8
	local grid: { [number]: { BasePart } } = {}
	local function cellKey(cx: number, cy: number, cz: number): number
		return ((cx + 500) * 1000 + (cy + 500)) * 1000 + (cz + 500)
	end
	for _, d in art:GetDescendants() do
		if stillBlock(d) then
			local b = d :: BasePart
			-- the rotated block's world-aligned box: each axis gets |rotation| x half size
			local h, cf = b.Size / 2, b.CFrame
			local rx, ry, rz = cf.RightVector, cf.UpVector, -cf.LookVector
			local ext = Vector3.new(
				math.abs(rx.X) * h.X + math.abs(ry.X) * h.Y + math.abs(rz.X) * h.Z,
				math.abs(rx.Y) * h.X + math.abs(ry.Y) * h.Y + math.abs(rz.Y) * h.Z,
				math.abs(rx.Z) * h.X + math.abs(ry.Z) * h.Y + math.abs(rz.Z) * h.Z
			)
			local lo, hi = (b.Position - ext) / CELL, (b.Position + ext) / CELL
			for cx = math.floor(lo.X), math.floor(hi.X) do
				for cy = math.floor(lo.Y), math.floor(hi.Y) do
					for cz = math.floor(lo.Z), math.floor(hi.Z) do
						local key = cellKey(cx, cy, cz)
						local cell = grid[key]
						if not cell then
							cell = {}
							grid[key] = cell
						end
						table.insert(cell, b)
					end
				end
			end
		end
	end
	local candidates: { Instance } = {}
	local hub = art:FindFirstChild("Hub")
	for _, name in { "Booth_sell", "Booth_equipment" } do
		local f = hub and hub:FindFirstChild(name)
		if f then
			table.insert(candidates, f)
		end
	end
	local tunnel = art:FindFirstChild("Tunnel")
	if tunnel then
		for _, sec in tunnel:GetChildren() do
			local props = sec:FindFirstChild("Props")
			if props then
				table.insert(candidates, props)
			end
		end
	end
	local removed = 0
	for _, root in candidates do
		for _, d in root:GetDescendants() do
			if not d:IsA("BasePart") or #d:GetChildren() > 0 then
				continue -- a part with children (a prompt, light, sparkles) stays
			end
			local p = d :: BasePart
			local moving = false
			local x: Instance? = p.Parent
			while x and x ~= root do
				if CollectionService:HasTag(x, Config.mapFx.motionTag) then
					moving = true
					break
				end
				x = x.Parent
			end
			if moving then
				continue
			end
			local h = p.Size / 2
			local cell = grid[cellKey(math.floor(p.Position.X / CELL), math.floor(p.Position.Y / CELL), math.floor(p.Position.Z / CELL))]
			for _, box in cell or {} do
				if box ~= p and box.Size.Magnitude > p.Size.Magnitude then
					local half = box.Size / 2 + Vector3.new(0.01, 0.01, 0.01)
					local all = true
					for _, c in { Vector3.new(1, 1, 1), Vector3.new(1, 1, -1), Vector3.new(1, -1, 1), Vector3.new(1, -1, -1),
						Vector3.new(-1, 1, 1), Vector3.new(-1, 1, -1), Vector3.new(-1, -1, 1), Vector3.new(-1, -1, -1) } do
						local l = box.CFrame:PointToObjectSpace(p.CFrame:PointToWorldSpace(h * c))
						if math.abs(l.X) > half.X or math.abs(l.Y) > half.Y or math.abs(l.Z) > half.Z then
							all = false
							break
						end
					end
					if all then
						p:Destroy()
						removed += 1
						break
					end
				end
			end
		end
	end
	return removed
end

function MapArt.build(map: Instance)
	meshes = ReplicatedStorage:FindFirstChild("SceneryMeshes")
	if not meshes then
		warn("[MapArt] ReplicatedStorage.SceneryMeshes is missing: trees and crystals use plain stand-ins")
	end
	local art = folder("Art", map)
	local list = Scenery.get()
	local rng = Scenery.rng(C.seed)
	hub(folder("Hub", art), rng)
	local tunnel = folder("Tunnel", art)
	local open = 0
	for _, isl in W.islands do
		if isl.open then
			open += 1
			section(tunnel, W.zones[open], isl, list.trees, rng)
		end
	end
	endCap(tunnel)
	farScenery(folder("Far", art), rng)
	-- the gift box (prototype): body, lid, gold ribbons and a bow; the client bobs it while a gift waits
	local giftArt = folder("GiftArt", art)
	local gb = W.giftBox
	local at = CFrame.new(gb.X, 0, gb.Z)
	local F = Theme.fx
	block(Vector3.new(3, 2.4, 3), at * CFrame.new(0, 1.2, 0), F.giftBody, giftArt)
	block(Vector3.new(3.4, 0.8, 3.4), at * CFrame.new(0, 2.7, 0), F.giftLid, giftArt)
	block(Vector3.new(0.6, 3.25, 3.5), at * CFrame.new(0, 1.6, 0), F.giftRibbon, giftArt)
	block(Vector3.new(3.5, 3.25, 0.6), at * CFrame.new(0, 1.6, 0), F.giftRibbon, giftArt)
	for _, x in { -0.55, 0.55 } do
		shape("Ring", Vector3.new(1.6, 0.4, 1.6), at * CFrame.new(x, 3.4, 0) * CFrame.Angles(0, 0, math.pi / 2), F.giftRibbon, giftArt)
	end
	local pruned = pruneBuried(art)
	art:SetAttribute("PrunedHidden", pruned) -- how many never-visible parts were left out (QA reads it)
	local terrain = workspace.Terrain
	if not terrain:FindFirstChildOfClass("Clouds") then
		local clouds = Instance.new("Clouds")
		clouds.Cover = C.clouds.cover
		clouds.Density = C.clouds.density
		clouds.Parent = terrain
	end
end

return MapArt
