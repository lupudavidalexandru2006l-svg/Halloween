--!strict
-- MapArt v3 (Round 5 map remake, owner 2026-11-02: "develop the map ... everything, booths,
-- leaderboards, islands"). The look of the world, built once by WorldService.buildMap; every gameplay
-- part, name and tag still comes from WorldService.
-- The hub is a winter village: a low stone wall with lanterns, candy-coloured cottages and big pines
-- outside it, a frozen three-tier fountain, tiled paths, lawns with flower beds, benches and lamps.
-- The pans are striped lawns with white rail fences (the owner's picture), a white gate arch, flower
-- boxes and the Thaw Machine(s) at the back (PanLooks restyles fences per Look, shows machine 2).
-- Booths are little cottages with a roof, awning and one big object on top (coin / ice ray / crystal).
-- Leaderboards stand in a wooden frame between stone pillars with glowing crystal caps.
-- The islands have natural rock cliffs instead of flat walls (snowy or mossy, two rows, trees on top),
-- stone-edged paths, lanterns, themed props, a big landmark and a castle gatehouse in front of each.
-- World Rules 9 (clear centre, rich edges): the middle where pets walk stays calm (shade trees in the
-- side bands, pines' branches above head height), the props sit on an earth strip at the cliffs' foot,
-- and the landmarks stand in the cliffs, rising over them.
-- Contracts other scripts rely on: Art.Hub.Pan<i> holds FencePost / PostCap / FenceRail / PanFloor /
-- LawnStripe / DoorGlow / ThawMachine1-2 (PanLooks, MapController); GateBars<id> and GateGlow parts
-- (MapController); GiftArt (MapController bobs it); Lights anywhere in the map (WorldService, night).
-- Shapes Roblox has no primitive for (cone, crystal, rock, dome, ring, arch) are MeshParts in
-- ReplicatedStorage.SceneryMeshes; plain parts stand in when they're missing.

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

local function bench(parent: Instance, cf: CFrame)
	block(Vector3.new(4.4, 0.35, 1.3), cf * CFrame.new(0, 1, 0), A.penRail, parent, true, Enum.Material.WoodPlanks)
	block(Vector3.new(4.4, 1.1, 0.3), cf * CFrame.new(0, 1.7, 0.6), A.penRail, parent, true, Enum.Material.WoodPlanks)
	for _, x in { -1.8, 1.8 } do
		block(Vector3.new(0.35, 1, 1.2), cf * CFrame.new(x, 0.5, 0), V.iron, parent, true)
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

local function thawMachine(parent: Instance, name: string, at: Vector3)
	local R5 = Theme.round5
	local m = Instance.new("Model")
	m.Name = name
	local base = CFrame.new(at.X, at.Y - 0.2, at.Z) -- faces the door (+Z)
	cyl(2.5, 0.35, base * CFrame.new(0, 0.18, 0), R5.machineTrim, m)
	quiet(glow(cyl(2.7, 0.15, base * CFrame.new(0, 0.1, 0), R5.machineGlow, m), 0.2))
	for _, x in { -2.7, 2.7 } do
		block(Vector3.new(1, 5.6, 1.2), base * CFrame.new(x, 2.8, -0.3), R5.machine, m, true)
		block(Vector3.new(1.3, 0.35, 1.5), base * CFrame.new(x, 5.75, -0.3), R5.machineTrim, m)
	end
	block(Vector3.new(6.6, 1, 1.6), base * CFrame.new(0, 6.3, -0.3), R5.machine, m)
	block(Vector3.new(6.4, 4.8, 0.4), base * CFrame.new(0, 3, -1.7), R5.machineTrim, m)
	-- the warm-up gauge on the back panel and three heat lamps glowing down onto the pad
	quiet(glow(block(Vector3.new(0.5, 3.6, 0.1), base * CFrame.new(-2, 3, -1.45), R5.machineGlow, m), 0.1))
	for k = -1, 1 do
		local lamp = quiet(glow(block(Vector3.new(1, 0.5, 1), base * CFrame.new(k * 2, 5.6, -0.3), R5.machineGlow, m), 0.05))
		if k == 0 then
			light(lamp, R5.machineGlow, 10, 1.2)
		end
	end
	-- a little chimney puffing steam
	cyl(0.45, 1.6, base * CFrame.new(2, 7.4, -0.9), R5.machine, m)
	local puff = Instance.new("ParticleEmitter")
	puff.Color = ColorSequence.new(Theme.white)
	puff.Transparency = NumberSequence.new(0.3, 1)
	puff.Size = NumberSequence.new(0.5, 1.4)
	puff.Lifetime = NumberRange.new(1, 1.6)
	puff.Speed = NumberRange.new(1.5, 2.5)
	puff.Rate = 3
	puff.EmissionDirection = Enum.NormalId.Top
	local spot = block(Vector3.one * 0.3, base * CFrame.new(2, 8.3, -0.9), R5.machine, m)
	spot.Transparency = 1
	puff.Parent = spot
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
		thawMachine(f, "ThawMachine" .. m, Vector3.new(pl.x + T.machine.x + (m - 1) * T.machine.gap, y + 0.2, zb + T.machine.z))
	end
end

-- ---------- the hub ----------
local function fountain(parent: Instance, at: Vector3)
	local f = folder("Fountain", parent)
	local cf = CFrame.new(at.X, 0, at.Z)
	-- the plaza round it: a stone ring with a tiled band
	quiet(cyl(13, 0.1, cf * CFrame.new(0, 0.05, 0), V.stone, f, false, Enum.Material.Slate))
	quiet(cyl(11.6, 0.16, cf * CFrame.new(0, 0.08, 0), V.tileWarm, f, false, Enum.Material.Slate)) -- clearly above the ring (0.02 flickered)
	-- the pool: a rim you can't walk through, frozen water inside
	cyl(7, 1.4, cf * CFrame.new(0, 0.7, 0), V.stone, f, true, Enum.Material.Cobblestone)
	cyl(7.3, 0.4, cf * CFrame.new(0, 1.5, 0), V.trim, f, true)
	local water = cyl(6.2, 0.2, cf * CFrame.new(0, 1.42, 0), V.water, f, false, Enum.Material.Ice)
	water.Transparency = 0.15
	-- the middle column and two basins, each with frozen spill arcs
	cyl(1.3, 6, cf * CFrame.new(0, 4, 0), V.stone, f, true, Enum.Material.Cobblestone)
	cyl(3.8, 0.7, cf * CFrame.new(0, 4.4, 0), V.trim, f)
	cyl(3.4, 0.3, cf * CFrame.new(0, 4.8, 0), V.water, f, false, Enum.Material.Ice)
	cyl(0.9, 3, cf * CFrame.new(0, 6.5, 0), V.stone, f)
	cyl(2.3, 0.55, cf * CFrame.new(0, 7.9, 0), V.trim, f)
	cyl(2, 0.25, cf * CFrame.new(0, 8.2, 0), V.water, f, false, Enum.Material.Ice)
	for k = 0, 7 do
		local a = k * math.pi / 4
		local icicle = shape("Cone", Vector3.new(0.6, 2.4, 0.6), cf * CFrame.new(math.cos(a) * 3.5, 3.2, math.sin(a) * 3.5) * CFrame.Angles(math.pi, 0, 0), A.crystal, f)
		icicle.Material = Enum.Material.Ice
		icicle.Transparency = 0.2
		local arc = cyl(0.25, 2.6, cf * CFrame.new(math.cos(a) * 5.2, 3, math.sin(a) * 5.2) * CFrame.Angles(math.sin(a) * 0.5, 0, -math.cos(a) * 0.5), V.water, f, false, Enum.Material.Glass)
		arc.Transparency = 0.25
	end
	-- the crystal on top: the hub's landmark, glowing softly
	local top = shape("Octa", Vector3.new(2.6, 5, 2.6), cf * CFrame.new(0, 10.9, 0), A.crystalGlow, f)
	glow(top, 0.15)
	light(top, A.crystalGlow, 18, 1.4)
	for k = 0, 3 do
		local a = k * math.pi / 2 + 0.4
		glow(shape("Octa", Vector3.new(1.1, 2.4, 1.1), cf * CFrame.new(math.cos(a) * 1.4, 9.6, math.sin(a) * 1.4) * CFrame.Angles(math.cos(a) * 0.4, 0, math.sin(a) * 0.4), A.crystal, f), 0.25)
	end
	-- benches round it, looking at it
	for k = 0, 3 do
		local a = k * math.pi / 2 + math.pi / 4
		local p = Vector3.new(at.X + math.cos(a) * 10, 0, at.Z + math.sin(a) * 10)
		bench(f, CFrame.lookAt(p, Vector3.new(at.X, 0, at.Z)) * CFrame.Angles(0, math.pi, 0))
	end
end

-- a horizontal log: a cylinder along the X axis of cf
local function log(len: number, r: number, cf: CFrame, color: Color3, parent: Instance): BasePart
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Cylinder
	p.Size = Vector3.new(len, r * 2, r * 2)
	p.CFrame = cf
	p.Material = Enum.Material.Wood
	return finish(p, color, parent)
end

-- light cut faces on a log's ends (end grain), so stacked logs read as cut timber.
-- which = -1 or 1 for one end only (along the log's X axis), nil for both
local function logEnds(lg: BasePart, color: Color3, parent: Instance, which: number?)
	local half, r = lg.Size.X / 2, lg.Size.Y / 2
	for _, e in { -1, 1 } do
		if not which or which == e then
			-- the disc sinks 0.01 into the log and stands 0.05 out: no flush faces
			quiet(log(0.06, r * 0.82, lg.CFrame * CFrame.new(e * (half + 0.02), 0, 0), color, parent))
		end
	end
end

-- a display ice ray of gun `tier`, like the stand-in in your hand (RayController) but bigger:
-- body, glowing tip, tank, grip, and fins / ring / gem on the higher tiers. Barrel along +X of cf.
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

local function jar(parent: Instance, at: Vector3, color: Color3)
	local glass = cyl(0.3, 0.62, CFrame.new(at + Vector3.new(0, 0.31, 0)), color, parent, false, Enum.Material.Glass)
	glass.Transparency = 0.2
	cyl(0.33, 0.14, CFrame.new(at + Vector3.new(0, 0.68, 0)), A.post, parent, false, Enum.Material.Wood)
end

local function booth(parent: Instance, b: Config.Booth, rng: () -> number)
	-- Booth v3 (owner 2026-11-02: v2 was "boxy and flat, wrong style"; picked "cozy wooden chalet").
	-- A log cabin with crossed log ends, a steep front gable with a deep snowy roof that overhangs a
	-- porch on log posts, the sign standing on the porch beam, a lean-to with firewood on the outer
	-- side, an outside stone chimney, warm windows and snow drifts. Natural wood, stone and snow; the
	-- shop's colour only on the awning, the sign, the roof trim and the rug. Front = -Z (the plaza).
	local f = folder("Booth_" .. b.id, parent)
	local at = CFrame.new(b.pos.X, 0, b.pos.Z)
	local color = Theme.booths[b.id] or Theme.info
	local logA, logB = HA.boothWood, HA.boothWood:Lerp(Theme.ink, 0.15)
	local grain = HA.boothWood:Lerp(Theme.white, 0.4) -- the cut ends of the logs
	local dark = A.post
	local Wd, y0, H = 14, 0.6, 7.4 -- width, floor height, wall height
	local fz, bz = 1, 11 -- the cabin's front and back walls
	local eaveY = y0 + H
	local outer = if b.pos.X < 0 then -1 else 1 -- the side away from the tunnel mouth
	-- the stone base under the cabin and the porch, steps down to the plaza, a rug in the shop's colour
	block(Vector3.new(Wd + 2, y0, bz + 4.8), at * CFrame.new(0, y0 / 2, (bz - 3.8) / 2), V.stoneWarm:Lerp(V.stone, 0.5), f, false, Enum.Material.Cobblestone)
	quiet(block(Vector3.new(Wd - 1, y0 + 0.02, bz + 3.6), at * CFrame.new(0, y0 / 2 + 0.02, (bz - 3.4) / 2), A.plank, f, false, Enum.Material.WoodPlanks))
	-- two log steps up to the porch (the stone base's front is at z = -4.3, its top at y0)
	logEnds(log(8, 0.2, at * CFrame.new(0, 0.2, -5.02), logB, f), grain, f)
	logEnds(log(8, 0.26, at * CFrame.new(0, 0.34, -4.56), logA, f), grain, f)
	quiet(block(Vector3.new(8.4, 0.06, 3), at * CFrame.new(0, 0.03, -6.6), color, f, false, Enum.Material.Fabric))
	-- a fringe of tassels on the rug's two short ends (just past its edge: no overlapping tops)
	for _, sgn in { -1, 1 } do
		for k = 0, 9 do
			quiet(block(Vector3.new(0.4, 0.06, 0.09), at * CFrame.new(sgn * 4.42, 0.04, -7.95 + k * 0.3), Theme.panel, f, false, Enum.Material.Fabric))
		end
	end
	quiet(block(Vector3.new(7, 0.1, 1.9), at * CFrame.new(0, 0.05, -6.6), Theme.panel, f, false, Enum.Material.Fabric)) -- clearly above the rug (0.015 flickered)
	-- log walls: the sides and back are stacked logs whose ends cross at the corners
	local step = 0.84
	local rows = math.floor(H / step)
	for i = 0, rows - 1 do
		local y = y0 + 0.42 + i * step
		local c = if i % 2 == 0 then logA else logB
		for _, side in { -1, 1 } do
			logEnds(log(bz - fz + 1.6, 0.44, at * CFrame.new(side * (Wd / 2 - 0.42), y, (fz + bz) / 2) * CFrame.Angles(0, math.pi / 2, 0), c, f), grain, f)
		end
		logEnds(log(Wd + 1.6, 0.44, at * CFrame.new(0, y + 0.42, bz - 0.42), c, f), grain, f)
		-- the front: logs either side of the shop window, and over it
		local winTop = y0 + 4.6
		if y < winTop then
			for _, side in { -1, 1 } do
				-- only the end at the window shows (the outer end meets the side wall)
				logEnds(log(2.6, 0.44, at * CFrame.new(side * (Wd / 2 - 1.3), y + 0.42, fz + 0.42), c, f), grain, f, -side)
			end
		else
			logEnds(log(Wd + 1.6, 0.44, at * CFrame.new(0, y + 0.42, fz + 0.42), c, f), grain, f)
		end
	end
	-- warm windows on the sides, with plank shutters and a snowy sill
	for _, side in { -1, 1 } do
		local wcf = at * CFrame.new(side * (Wd / 2 + 0.05), y0 + 4, (fz + bz) / 2) * CFrame.Angles(0, side * math.pi / 2, 0)
		-- frame, glass and bars each stand clearly proud of the one behind (0.01 apart they flickered)
		block(Vector3.new(3, 2.8, 0.3), wcf, dark, f)
		quiet(glow(block(Vector3.new(2.4, 2.2, 0.4), wcf, V.window, f), 0.1))
		block(Vector3.new(0.18, 2.1, 0.5), wcf, dark, f)
		block(Vector3.new(2.3, 0.18, 0.5), wcf, dark, f)
		for _, sx in { -1.9, 1.9 } do
			block(Vector3.new(0.8, 2.6, 0.2), wcf * CFrame.new(sx, 0, -0.1), logB, f, false, Enum.Material.WoodPlanks)
		end
		quiet(block(Vector3.new(3.3, 0.35, 0.7), wcf * CFrame.new(0, -1.55, -0.2), A.snowCap, f, false, Enum.Material.Snow))
	end
	-- inside: plank shelves with the shop's goods and a warm hanging lamp
	for _, y in { 2.6, 4.6 } do
		local shelf = block(Vector3.new(Wd - 3, 0.25, 1.2), at * CFrame.new(0, y, bz - 1.4), dark, f, false, Enum.Material.Wood)
		if y > 3 then
			light(shelf, A.lanternGlow, 9, 0.8) -- a soft warm light on the back shelves, so the goods show from outside
		end
	end
	cyl(0.07, 1.4, at * CFrame.new(0, eaveY - 0.8, (fz + bz) / 2), V.iron, f)
	local bulb = quiet(glow(ball(0.5, (at * CFrame.new(0, eaveY - 1.7, (fz + bz) / 2)).Position, A.lanternGlow, f), 0.05))
	light(bulb, A.lanternGlow, 18, 1.2)
	-- the counter in the shop window: thick natural wood with a thin stripe in the shop's colour
	block(Vector3.new(Wd - 4.8, 3, 1), at * CFrame.new(0, y0 + 1.5, fz - 0.2), logA, f, false, Enum.Material.WoodPlanks)
	block(Vector3.new(Wd - 4.2, 0.4, 1.8), at * CFrame.new(0, y0 + 3.2, fz - 0.3), dark, f, false, Enum.Material.Wood)
	quiet(block(Vector3.new(Wd - 4.8, 0.35, 0.1), at * CFrame.new(0, y0 + 2.4, fz - 0.75), color, f))
	-- the counter's carved trim: dark corner posts, a baseboard and two diamonds in the shop's colour.
	-- The counter's front face is at fz - 0.7; every piece stands clearly in front of it.
	for _, sgn in { -1, 1 } do
		block(Vector3.new(0.5, 3.1, 1.3), at * CFrame.new(sgn * ((Wd - 4.8) / 2 + 0.1), y0 + 1.55, fz - 0.2), dark, f, false, Enum.Material.Wood)
		local d = at * CFrame.new(sgn * 2.3, y0 + 1.25, fz - 0.76) * CFrame.Angles(0, 0, math.pi / 4)
		quiet(block(Vector3.new(0.75, 0.75, 0.1), d, dark, f, false, Enum.Material.Wood))
		quiet(block(Vector3.new(0.5, 0.5, 0.1), d * CFrame.new(0, 0, -0.05), color, f))
	end
	block(Vector3.new(Wd - 4.6, 0.45, 1.15), at * CFrame.new(0, y0 + 0.22, fz - 0.2), dark, f, false, Enum.Material.Wood)
	-- a short striped awning over the shop window, under the porch roof
	local n = 6
	for k = 0, n - 1 do
		local x = -(Wd - 4.4) / 2 + (k + 0.5) * (Wd - 4.4) / n
		local c = if k % 2 == 0 then color else HA.awningStripe
		local w = (Wd - 4.4) / n
		local board = at * CFrame.new(x, y0 + 4.9, fz - 0.9) * CFrame.Angles(math.rad(-22), 0, 0)
		block(Vector3.new(w, 0.2, 2), board, c, f, false, Enum.Material.Fabric)
		-- a scalloped edge: two round flaps per stripe hanging under the front edge (set just behind
		-- the board's front face, so no faces are flush)
		for _, dx in { -w / 4, w / 4 } do
			local flap = quiet(log(0.1, w / 4 - 0.02, board * CFrame.new(dx, -0.32, -0.92) * CFrame.Angles(0, math.pi / 2, 0), c, f))
			flap.Material = Enum.Material.Fabric
		end
	end
	-- the roof: a steep gable facing the plaza, thick dark-wood slabs under a deep layer of snow,
	-- overhanging the porch at the front and the walls at the sides
	local side, rise = 1.4, 7.2
	local eaveX = Wd / 2 + side
	local run = eaveX
	local theta = math.atan2(rise, run)
	local slopeLen = math.sqrt(run * run + rise * rise)
	local zFront, zBack = -3.8, bz + 1
	local roofLen, roofZ = zBack - zFront, (zFront + zBack) / 2
	local eaveEdgeY = eaveY - side * rise / run
	for _, sgn in { -1, 1 } do
		local mid = at * CFrame.new(sgn * eaveX / 2, eaveEdgeY + rise / 2, roofZ) * CFrame.Angles(0, 0, -sgn * theta)
		block(Vector3.new(slopeLen + 0.4, 0.6, roofLen), mid, dark, f, false, Enum.Material.WoodPlanks)
		quiet(block(Vector3.new(slopeLen - 0.2, 0.7, roofLen - 0.4), mid * CFrame.new(0, 0.62, 0), A.snowA, f, false, Enum.Material.Snow))
		-- a soft rounded snow lip along the eave, icicles under it
		quiet(cyl(0.55, roofLen - 0.4, at * CFrame.new(sgn * (eaveX - 0.2), eaveEdgeY + 0.55, roofZ) * CFrame.Angles(math.pi / 2, 0, 0), A.snowA, f, false, Enum.Material.Snow))
		for k = 0, 6 do
			local len = 0.5 + ((k + (sgn + 1)) % 3) * 0.35
			local ice = shape("Cone", Vector3.new(0.32, len, 0.32), at * CFrame.new(sgn * (eaveX - 0.1), eaveEdgeY - 0.2 - len / 2, zFront + 1 + k * (roofLen - 2) / 6) * CFrame.Angles(math.pi, 0, 0), A.crystal, f)
			ice.Material = Enum.Material.Ice
			quiet(ice)
		end
		-- the barge boards along the front gable, in the shop's colour
		local edge = at * CFrame.new(sgn * eaveX / 2, eaveEdgeY + rise / 2, zFront - 0.15) * CFrame.Angles(0, 0, -sgn * theta)
		block(Vector3.new(slopeLen + 0.6, 0.55, 0.45), edge * CFrame.new(0, 0.1, 0), color, f)
		-- a soft snow lip along the front edge too, sitting on the barge board like the side lips
		local lip = quiet(log(slopeLen - 0.8, 0.32, edge * CFrame.new(-sgn * 0.2, 0.75, 0.1), A.snowA, f))
		lip.Material = Enum.Material.Snow
	end
	quiet(cyl(0.75, roofLen + 0.4, at * CFrame.new(0, eaveEdgeY + rise + 0.75, roofZ) * CFrame.Angles(math.pi / 2, 0, 0), A.snowA, f, false, Enum.Material.Snow))
	-- the gable ends: vertical planks with a round lit window at the front
	for _, z in { fz + 0.2, bz - 0.2 } do
		for _, sgn in { -1, 1 } do
			wedge(Vector3.new(0.4, rise - 0.3, Wd / 2), at * CFrame.new(sgn * Wd / 4, eaveY + (rise - 0.3) / 2, z) * CFrame.Angles(0, -sgn * math.pi / 2, 0), A.plank, f, Enum.Material.WoodPlanks)
		end
	end
	local rw = at * CFrame.new(0, eaveY + 2.4, fz - 0.05)
	cyl(1.15, 0.3, rw * CFrame.Angles(math.pi / 2, 0, 0), dark, f)
	-- half-see-through glow over the dark frame: a warm lit window, not a white blob (at 0.1 it washed out)
	quiet(glow(cyl(0.9, 0.4, rw * CFrame.Angles(math.pi / 2, 0, 0), V.window, f), 0.45))
	-- a cross of window bars in front of the glass (the glass's front face is at 0.2 in front of rw)
	for _, rz in { 0, math.pi / 2 } do
		quiet(block(Vector3.new(0.16, 1.85, 0.08), rw * CFrame.new(0, 0, -0.27) * CFrame.Angles(0, 0, rz), dark, f))
	end
	-- the porch: two log posts holding the overhang, a beam across, the sign standing on it
	local BS = Config.world.boothSign
	local postZ = -2.9
	for _, sgn in { -1, 1 } do
		local h = eaveEdgeY + (eaveX - 6.4) * rise / run - y0 - 0.2
		cyl(0.42, h, at * CFrame.new(sgn * 6.4, y0 + h / 2, postZ), logA, f, true, Enum.Material.Wood)
		block(Vector3.new(1.1, 0.5, 1.1), at * CFrame.new(sgn * 6.4, y0 + 0.25, postZ), V.stone, f, false, Enum.Material.Cobblestone)
		-- a lantern hanging from each post (one light, both glow)
		local lc = at * CFrame.new(sgn * 6.4, y0 + 4.6, postZ - 0.9)
		block(Vector3.new(0.22, 0.22, 1), lc * CFrame.new(0, 0.9, 0.45), V.iron, f)
		local box = quiet(block(Vector3.new(0.85, 1.05, 0.85), lc, A.lanternGlow, f))
		box.Material = Enum.Material.Glass
		shape("Cone", Vector3.new(1.2, 0.6, 1.2), lc * CFrame.new(0, 0.82, 0), V.iron, f)
		if sgn == outer then
			light(box, A.lanternGlow, 14, 0.9)
		end
	end
	log(13.6, 0.4, at * CFrame.new(0, BS.y - BS.h / 2 - 0.4, postZ), logB, f)
	block(Vector3.new(BS.w + 1.4, BS.h + 0.6, 0.4), at * CFrame.new(0, BS.y, postZ + 0.35), dark, f, false, Enum.Material.Wood)
	-- marquee bulbs round the sign (UI Rules: "a framed, bulb-lit sign"), on the frame's border just
	-- clear of the sign board. The top row stops where the roof comes down over the frame's corners.
	local bz0 = postZ + 0.35 - 0.2 - 0.12 -- in front of the frame's face, behind the sign's front
	local function bulb(x: number, y: number, z: number?)
		quiet(glow(ball(0.14, (at * CFrame.new(x, BS.y + y, z or bz0)).Position, A.lanternGlow, f), 0.05))
	end
	for k = -6, 6 do
		bulb(k * 0.66, BS.h / 2 + 0.15)
	end
	-- the bottom row sits on the front of the porch beam the sign stands on
	for k = -7, 7 do
		bulb(k * 0.66, -BS.h / 2 - 0.15, postZ - 0.4)
	end
	for _, sgn in { -1, 1 } do
		for _, y in { -0.55, 0, 0.5 } do
			bulb(sgn * (BS.w / 2 + 0.35), y)
		end
	end
	-- an outside stone chimney on the back corner, puffing smoke
	local chim = at * CFrame.new(outer * (Wd / 2 + 0.9), 0, bz - 2.4)
	for k = 0, 9 do
		local w = if k < 4 then 2.4 else 1.8
		block(Vector3.new(w, 1.6, w), chim * CFrame.new(0, 0.8 + k * 1.6, 0) * CFrame.Angles(0, (k % 2) * 0.08, 0), if k % 2 == 0 then V.stone else V.stoneDark, f, false, Enum.Material.Cobblestone)
	end
	quiet(block(Vector3.new(2.2, 0.4, 2.2), chim * CFrame.new(0, 16.2, 0), A.snowA, f, false, Enum.Material.Snow))
	local smokeAt = block(Vector3.one * 0.3, chim * CFrame.new(0, 16.8, 0), V.stone, f)
	smokeAt.Transparency = 1
	local smoke = Instance.new("ParticleEmitter")
	smoke.Color = ColorSequence.new(Theme.white)
	smoke.Transparency = NumberSequence.new(0.35, 1)
	smoke.Size = NumberSequence.new(0.7, 2)
	smoke.Lifetime = NumberRange.new(1.6, 2.4)
	smoke.Speed = NumberRange.new(1.5, 2.5)
	smoke.Rate = 2.5
	smoke.EmissionDirection = Enum.NormalId.Top
	smoke.Parent = smokeAt
	-- a lean-to on the outer side, front part: a sloping plank roof over a stack of firewood
	local lean = at * CFrame.new(outer * (Wd / 2 + 2.2), 0, fz + 2.6)
	for k = 0, 2 do
		for j = 0, 3 - k do
			local lg = log(3.2, 0.32, lean * CFrame.new(-outer * 0.2 + (j - (3 - k) / 2) * 0.68 * outer, y0 + 0.32 + k * 0.58, 0) * CFrame.Angles(0, math.pi / 2, 0), if (j + k) % 2 == 0 then logA else logB, f)
			lg.Material = Enum.Material.Wood
			logEnds(lg, grain, f)
		end
	end
	for _, dz in { -1.8, 1.8 } do
		cyl(0.2, 3.4, lean * CFrame.new(outer * 1.4, y0 + 1.7, dz), dark, f)
	end
	block(Vector3.new(3.6, 0.3, 4.6), lean * CFrame.new(outer * 0.2, y0 + 3.5, 0) * CFrame.Angles(0, 0, outer * 0.3), dark, f, false, Enum.Material.WoodPlanks)
	quiet(block(Vector3.new(3.4, 0.35, 4.4), lean * CFrame.new(outer * 0.15, y0 + 3.85, 0) * CFrame.Angles(0, 0, outer * 0.3), A.snowA, f, false, Enum.Material.Snow))
	-- snow drifts against the walls, and potted pines either side of the steps
	for _, p in { { -Wd / 2 - 0.6, bz + 0.2 }, { Wd / 2 + 0.6, bz + 0.2 }, { -outer * (Wd / 2 + 0.6), fz + 3 } } do
		quiet(ellipsoid(Vector3.new(2.6, 1.3, 3.2), at * CFrame.new(p[1], 0.4, p[2]), A.snowA, f))
	end
	for _, sgn in { -1, 1 } do
		local p = at * CFrame.new(sgn * 5.6, 0, -4.9)
		cyl(0.75, 1.1, p * CFrame.new(0, 0.55, 0), logB, f, true, Enum.Material.WoodPlanks)
		quiet(cyl(0.8, 0.18, p * CFrame.new(0, 1.1, 0), A.snowA, f))
		-- a small potted pine straight on the soil, no trunk lift: it stays under the sign
		-- (a full tree() lifts its branches above head height and covered the sign's corners)
		local s, ry = 0.55, rng() * 6
		for _, c in SNOW_PINE do
			shape("Cone", Vector3.new(c.r * 2 * s, c.h * s, c.r * 2 * s), p * CFrame.new(0, 1.2 + (c.y - 1.3) * s, 0) * CFrame.Angles(0, ry, 0), c.color, f)
		end
	end
	-- what the shop does: goods on the shelves and counter (owner 2026-11-03: no big object over the
	-- ridge any more; the roof coin, crystal and ice ray were removed)
	if b.id == "sell" then
		for k = 0, 3 do
			for h = 0, k % 3 do
				cyl(0.42, 0.17, at * CFrame.new(-3.6 + k * 1.2, y0 + 3.5 + h * 0.19, fz - 0.4), V.gold, f)
			end
		end
		for _, y in { 2.95, 4.95 } do
			for k = 0, 5 do
				block(Vector3.new(1, 0.42, 0.55), at * CFrame.new(-4.2 + k * 1.7, y, bz - 1.4), V.gold, f)
			end
		end
		for _, x in { -4.6 } do
			ellipsoid(Vector3.new(1.8, 2.2, 1.8), at * CFrame.new(x, y0 + 1.1, fz - 1.9), V.crate, f, Enum.Material.Fabric)
			ellipsoid(Vector3.new(1.2, 0.45, 1.2), at * CFrame.new(x, y0 + 2.2, fz - 1.9), V.gold, f)
		end
	elseif b.id == "equipment" then
		for _, y in { 3.1, 5.1 } do
			for k = 0, 3 do
				local g = at * CFrame.new(-3.9 + k * 2.6, y, bz - 1.4)
				block(Vector3.new(1.5, 0.55, 0.55), g, Theme.fx.gunBody, f)
				quiet(glow(ball(0.26, (g * CFrame.new(0.9, 0, 0)).Position, (Theme.guns[k * 2 + 1] or Theme.guns[1]).glow, f), 0.05))
			end
		end
		for k = 0, 2 do
			glow(shape("Octa", Vector3.new(0.6, 1.3, 0.6), at * CFrame.new(2.6 + k * 0.8, y0 + 4.1, fz - 0.4) * CFrame.Angles(0, 0, (k - 1) * 0.3), A.crystalGlow, f), 0.2)
		end
	elseif b.id == "rebirth" then
		cyl(0.45, 0.45, at * CFrame.new(0, y0 + 3.62, fz - 0.4), V.gold, f)
		local orb = ball(0.8, (at * CFrame.new(0, y0 + 4.6, fz - 0.4)).Position, A.crystalGlow, f)
		orb.Material = Enum.Material.Glass
		orb.Transparency = 0.25
		light(orb, color, 10, 0.9)
		for _, y in { 3.15, 5.15 } do
			for k = 0, 6 do
				local pot = cyl(0.28, 0.75, at * CFrame.new(-4.5 + k * 1.5, y, bz - 1.4), V.flowers[k % #V.flowers + 1], f)
				pot.Material = Enum.Material.Glass
				pot.Transparency = 0.15
			end
		end
		quiet(glow(shape("Ring", Vector3.new(4.4, 0.12, 4.4), at * CFrame.new(0, 0.1, -6.6), color, f), 0.2))
		for k = 0, 2 do
			glow(shape("Octa", Vector3.new(0.9, 2.1, 0.9), at * CFrame.new(4.8 - k * 0.7, y0 + 1, fz - 2 + k * 0.5) * CFrame.Angles(0, 0, (k - 1) * 0.3), A.crystalGlow, f), 0.2)
		end
	end
	-- every chalet: a wreath round the gable window, coloured string lights along the front roof edge
	local wreathAt = at * CFrame.new(0, eaveY + 2.4, fz - 0.35)
	shape("Ring", Vector3.new(3.1, 0.55, 3.1), wreathAt * CFrame.Angles(math.pi / 2, 0, 0), V.hedge, f)
	for k = 0, 5 do
		local ang = k / 6 * math.pi * 2 + 0.3
		ball(0.16, (wreathAt * CFrame.new(math.cos(ang) * 1.3, math.sin(ang) * 1.3, -0.25)).Position, V.flag, f)
	end
	for _, sx in { -0.35, 0.35 } do
		block(Vector3.new(0.6, 0.45, 0.2), wreathAt * CFrame.new(sx, -1.45, -0.3) * CFrame.Angles(0, 0, sx * 1.4), V.flag, f)
	end
	for _, sgn in { -1, 1 } do
		for k = 0, 10 do
			local t = k / 10
			local p = at * CFrame.new(sgn * eaveX * (1 - t) * 0.97, eaveEdgeY + rise * t - 0.45, zFront - 0.5)
			quiet(glow(ball(0.17, p.Position, V.flowers[(k + (if sgn > 0 then 2 else 0)) % #V.flowers + 1], f), 0.05))
		end
	end
	if b.id == "equipment" then
		-- (owner 2026-11-03: the ice ray rack on the back wall and the glass gun case were removed)
		-- gear: a mannequin in the warm coat, beanie and fur boots, and a sun hat on a peg
		mannequin(f, at * CFrame.new(5, y0, -1.5) * CFrame.Angles(0, -0.35, 0))
		local hat = at * CFrame.new(-outer * (Wd / 2 - 1), y0 + 5.6, (fz + bz) / 2 + 2)
		cyl(0.1, 0.5, hat * CFrame.new(outer * 0.3, 0, 0) * CFrame.Angles(0, 0, math.pi / 2), dark, f)
		cyl(1, 0.12, hat * CFrame.Angles(0, 0, outer * 1.2), V.flowers[2], f, false, Enum.Material.Fabric)
		shape("Dome", Vector3.new(1.1, 0.6, 1.1), hat * CFrame.Angles(0, 0, outer * 1.2) * CFrame.new(0, 0.3, 0), V.flowers[2], f)
		-- jars of Slow Gel on the counter, a crate of parts by the lean-to
		for k = 0, 2 do
			jar(f, (at * CFrame.new(-3.6 + k * 0.85, y0 + 3.4, fz - 0.3)).Position, Theme.round5.gel)
		end
		crate(f, at * CFrame.new(outer * (Wd / 2 + 1.6), 0.6, fz - 1.4) * CFrame.Angles(0, 0.3, 0), 1.6)
		-- a banded barrel on the porch by the counter (the other booths have their sack and crystals there)
		local bar = at * CFrame.new(-4.8, y0 + 0.65, -0.9)
		cyl(0.55, 1.3, bar, V.barrel, f, false, Enum.Material.WoodPlanks)
		for _, dy in { -0.35, 0.35 } do
			cyl(0.58, 0.1, bar * CFrame.new(0, dy, 0), V.iron, f)
		end
	elseif b.id == "sell" then
		-- an open treasure chest full of coins on the porch
		local chest = at * CFrame.new(5, y0, -1.5) * CFrame.Angles(0, -0.3, 0)
		block(Vector3.new(2.2, 1.2, 1.4), chest * CFrame.new(0, 0.6, 0), V.barrel, f, true, Enum.Material.WoodPlanks)
		for _, x in { -0.75, 0.75 } do
			block(Vector3.new(0.18, 1.28, 1.48), chest * CFrame.new(x, 0.6, 0), V.gold, f) -- bands stand clear of the wood (0.02 flickered)
		end
		quiet(glow(ellipsoid(Vector3.new(1.9, 0.7, 1.1), chest * CFrame.new(0, 1.25, 0), V.gold, f), 0.1))
		block(Vector3.new(2.2, 0.35, 1.4), chest * CFrame.new(0, 1.55, 0.95) * CFrame.Angles(math.rad(-70), 0, 0), V.barrel, f, false, Enum.Material.WoodPlanks)
		for k = 0, 4 do
			cyl(0.3, 0.1, chest * CFrame.new(-1.2 + k * 0.6, 0.05, -1 - (k % 2) * 0.4), V.gold, f)
		end
		-- a balance scale on the counter, coins on one pan
		local sc = at * CFrame.new(3.2, y0 + 3.4, fz - 0.3)
		cyl(0.3, 0.15, sc * CFrame.new(0, 0.08, 0), V.gold, f)
		cyl(0.08, 1.4, sc * CFrame.new(0, 0.85, 0), V.gold, f)
		block(Vector3.new(1.8, 0.1, 0.1), sc * CFrame.new(0, 1.55, 0) * CFrame.Angles(0, 0, 0.12), V.gold, f)
		for _, x in { -0.85, 0.85 } do
			local py = 0.9 - x * 0.12
			block(Vector3.new(0.04, 0.6, 0.04), sc * CFrame.new(x, py + 0.35, 0), V.iron, f)
			cyl(0.35, 0.06, sc * CFrame.new(x, py, 0), V.gold, f)
		end
		cyl(0.22, 0.2, sc * CFrame.new(-0.85, 1.12, 0), V.gold, f)
		-- a chalkboard sign by the steps with a coin drawn on it in chalk, and real coins at its foot
		-- (World Rules: the painted UI icons never go on world objects)
		local board = at * CFrame.new(outer * 7.8, 0, -5.6) * CFrame.Angles(0, outer * -0.4, 0) -- clear of the potted pine
		for _, tilt in { 0.18, -0.18 } do
			local leaf = block(Vector3.new(1.8, 2.4, 0.12), board * CFrame.new(0, 1.2, tilt * 2) * CFrame.Angles(-tilt, 0, 0), V.iron, f, false, Enum.Material.Slate)
			leaf.Name = "Chalkboard"
		end
		-- the chalk sits 0.06 in front of the front leaf's face, along its tilt
		local front = board * CFrame.new(0, 1.3, -0.48) * CFrame.Angles(0.18, 0, 0)
		local chalk = Theme.white
		quiet(shape("Ring", Vector3.new(1.1, 0.05, 1.1), front * CFrame.Angles(math.pi / 2, 0, 0), chalk, f))
		quiet(shape("Ring", Vector3.new(0.7, 0.05, 0.7), front * CFrame.Angles(math.pi / 2, 0, 0), chalk, f))
		quiet(block(Vector3.new(0.08, 0.36, 0.04), front, chalk, f)) -- the coin's mark
		quiet(block(Vector3.new(1.3, 0.05, 0.04), front * CFrame.new(0, -0.82, 0), chalk, f)) -- a chalk line under it
		for k = 0, 2 do
			cyl(0.26, 0.09, board * CFrame.new(-0.3 + k * 0.08, 0.05 + k * 0.09, -0.9), V.gold, f)
		end
		cyl(0.26, 0.09, board * CFrame.new(0.45, 0.05, -0.75), V.gold, f)
	elseif b.id == "rebirth" then
		-- a lectern with an open spell book on the porch, a little glow floating over it
		local lec = at * CFrame.new(-5, y0, -1.5) * CFrame.Angles(0, 0.3, 0)
		cyl(0.6, 0.2, lec * CFrame.new(0, 0.1, 0), dark, f)
		cyl(0.18, 2.6, lec * CFrame.new(0, 1.4, 0), logA, f, false, Enum.Material.Wood)
		block(Vector3.new(1.8, 0.2, 1.3), lec * CFrame.new(0, 2.8, 0) * CFrame.Angles(math.rad(25), 0, 0), logB, f, false, Enum.Material.Wood)
		block(Vector3.new(1.7, 0.08, 1.2), lec * CFrame.new(0, 2.95, 0) * CFrame.Angles(math.rad(25), 0, 0), color, f)
		for _, x in { -0.42, 0.42 } do
			block(Vector3.new(0.8, 0.1, 1.05), lec * CFrame.new(x, 3.03, 0) * CFrame.Angles(math.rad(25), 0, x * 0.25), Theme.panel, f)
		end
		local spark = quiet(glow(shape("Octa", Vector3.new(0.5, 0.8, 0.5), lec * CFrame.new(0, 3.9, 0), A.crystalGlow, f), 0.1))
		light(spark, color, 8, 0.7)
		-- candles on the counter
		for k = 0, 2 do
			local c = at * CFrame.new(-3.8 + k * 0.7, y0 + 3.4, fz - 0.3)
			local h = 0.5 + (k % 2) * 0.35
			cyl(0.16, h, c * CFrame.new(0, h / 2, 0), Theme.panel, f)
			quiet(glow(shape("Octa", Vector3.new(0.18, 0.32, 0.18), c * CFrame.new(0, h + 0.18, 0), A.lanternGlow, f), 0.05))
		end
		-- a star mobile hanging inside
		local mob = at * CFrame.new(-3, eaveY - 1, (fz + bz) / 2 - 1)
		cyl(0.03, 0.8, mob * CFrame.new(0, 0.4, 0), V.iron, f)
		shape("Ring", Vector3.new(2, 0.12, 2), mob, V.gold, f)
		for k = 0, 4 do
			local ang = k / 5 * math.pi * 2
			local drop = 0.6 + (k % 3) * 0.35
			local p = mob * CFrame.new(math.cos(ang) * 0.9, 0, math.sin(ang) * 0.9)
			quiet(block(Vector3.new(0.03, drop, 0.03), p * CFrame.new(0, -drop / 2, 0), V.iron, f))
			quiet(glow(shape("Octa", Vector3.new(0.35, 0.5, 0.35), p * CFrame.new(0, -drop - 0.25, 0), if k % 2 == 0 then V.gold else A.crystalGlow, f), 0.05))
		end
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

local function hubGround(parent: Instance, rng: () -> number)
	local f = folder("Ground", parent)
	-- (no paved strip along the pans' gates: the plaza ground runs right up to the fences, as in the
	-- owner's reference)
	-- the boulevard from the spawn to the tunnel mouth: a checkerboard of light tiles with a stone edge
	for row = 0, 7 do
		for col = 0, 3 do
			quiet(block(Vector3.new(4, 0.1, 4), CFrame.new(-6 + col * 4, 0.06, -30 + row * 4), if (row + col) % 2 == 0 then V.tileA else V.tileB, f, false, Enum.Material.Slate))
		end
	end
	for _, sx in { -8.4, 8.4 } do
		quiet(block(Vector3.new(0.8, 0.25, 32), CFrame.new(sx, 0.12, -16), V.stone, f, false, Enum.Material.Cobblestone))
	end
	-- lawns either side of the plaza: snowy grass, a little white fence, flower beds, trees, a bench
	for _, side in { -1, 1 } do
		local cx, cz = side * 33, -40
		quiet(block(Vector3.new(24, 0.2, 20), CFrame.new(cx, 0.1, cz), V.lawn, f, false, Enum.Material.Grass))
		-- its stone edge tops out below the grass (flush tops flickered)
		quiet(block(Vector3.new(24.6, 0.3, 20.6), CFrame.new(cx, 0, cz), V.stone, f, false, Enum.Material.Cobblestone))
		for _, sp in { { -7, -5 }, { 6, 4 }, { -2, 6 } } do
			snowyBush(f, Vector3.new(cx + sp[1], 0.2, cz + sp[2]), 0.8 + rng() * 0.4, true)
		end
		tree(cx + side * 7, 0.2, cz - 5, 0.95, rng() * 6, "snowpine", f)
		tree(cx - side * 8, 0.2, cz + 6, 0.8, rng() * 6, "snowpine", f)
		for b = 0, 3 do
			flowers(f, Vector3.new(cx - 8 + b * 5, 0.2, cz + side * 0 - 8.5), 5, rng)
		end
		bench(f, CFrame.lookAt(Vector3.new(cx - side * 9.5, 0.2, cz), Vector3.new(0, 0.2, cz)) * CFrame.Angles(0, math.pi, 0))
		smallSnowman(f, Vector3.new(cx + side * 2, 0.2, cz - 2), 0.9, side * 0.6 + math.pi)
	end
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
	hubGround(parent, rng)
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
	-- the spawn pad: a ring of light on the plaza
	local sp = W.spawn
	cyl(W.spawnPadRadius - 0.25, 0.35, CFrame.new(sp.X, 0.18, sp.Z), A.spawnPad, parent, true)
	glow(cyl(W.spawnPadRadius, 0.2, CFrame.new(sp.X, 0.12, sp.Z), Theme.white, parent), 0.1)
	fountain(parent, C.statue)
	-- lanterns along the boulevard
	for _, z in { -24, -12 } do
		for _, x in { -10, 10 } do
			lantern(parent, Vector3.new(x, 0, z), A.lanternGlow, 5.4, 16, z == -12)
		end
	end
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
	local first_look = Theme.islands[W.islands[1].theme] or Theme.islands.meadow
	for _, x in { -half - 4.5, half + 4.5 } do
		cyl(4.2, T.wallHeight + 8, CFrame.new(x, (T.wallHeight + 8) / 2, W.hubZMax + 1.5), V.stone, parent, true, Enum.Material.Cobblestone)
		cyl(4.7, 1.2, CFrame.new(x, T.wallHeight + 8.6, W.hubZMax + 1.5), V.trim, parent)
		for c = 0, 7 do
			local a = c * math.pi / 4
			block(Vector3.new(1.4, 1.6, 1.4), CFrame.new(x + math.cos(a) * 4.1, T.wallHeight + 10, W.hubZMax + 1.5 + math.sin(a) * 4.1), V.stone, parent, false, Enum.Material.Cobblestone)
		end
		shape("Cone", Vector3.new(10, 9, 10), CFrame.new(x, T.wallHeight + 15.5, W.hubZMax + 1.5), first_look.accent, parent)
		quiet(shape("Cone", Vector3.new(4.4, 3.4, 4.4), CFrame.new(x, T.wallHeight + 18.6, W.hubZMax + 1.5), A.snowCap, parent))
		cyl(0.15, 4, CFrame.new(x, T.wallHeight + 21.5, W.hubZMax + 1.5), V.iron, parent)
		block(Vector3.new(0.15, 1.4, 2.4), CFrame.new(x, T.wallHeight + 22.6, W.hubZMax + 2.7), V.flag, parent)
	end
	block(Vector3.new(T.width + 4, 2.6, 3), CFrame.new(0, T.wallHeight + 6.8, W.hubZMax + 1.5), V.stone, parent, false, Enum.Material.Cobblestone)
	quiet(ellipsoid(Vector3.new(T.width + 6, 1.4, 3.6), CFrame.new(0, T.wallHeight + 8.3, W.hubZMax + 1.5), A.snowCap, parent))
	glow(block(Vector3.new(T.width + 2, 1.2, 1.2), CFrame.new(0, T.wallHeight + 5, W.hubZMax), first_look.accent, parent), 0.2)
	for k = 0, 6 do
		glow(shape("Octa", Vector3.new(1.6, 3, 1.6), CFrame.new(-half + 4 + k * (T.width - 8) / 6, T.wallHeight + 9.6, W.hubZMax + 1.5), A.crystalGlow, parent), 0.15)
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

-- the path: rounded stones along both edges, and lanterns at its sides in the island's own light
local function pathDetail(parent: Instance, zone: Config.Zone, cl: { [string]: Color3 }, look: { [string]: Color3 }, rng: () -> number)
	local T = W.tunnel
	local f = folder("Path", parent)
	local edge = T.pathWidth / 2 + 0.5
	local z = zone.zMin + 1.5
	while z < zone.zMax - 1 do
		for _, side in { -1, 1 } do
			quiet(ellipsoid(Vector3.new(1.3 + rng() * 0.5, 0.45, 1.7 + rng() * 0.5), CFrame.new(side * edge, 0.12, z + (rng() - 0.5) * 0.5), cl.edge, f, Enum.Material.Slate))
		end
		z += 2.6
	end
	local side, lz = -1, zone.zMin + T.lampEvery / 2
	local n = 0
	while lz < zone.zMax - 4 do
		n += 1
		lantern(f, Vector3.new(side * (edge + 1.6), 0, lz), look.light, 6, 22, true)
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
	local sheet = block(Vector3.new(0.6, 22, 6) * s, CFrame.new(back - side * 4.4 * s, 11.4 * s, z), IA.waterfall, parent)
	sheet.Transparency = 0.2
	sheet.Material = Enum.Material.Glass
	quiet(sheet)
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

-- a castle gatehouse in front of a section: two round towers with pointed roofs in the island's
-- colour and flags, a stone lintel with crystals, the glowing beam (GateGlow) and the ice bars
local function gatehouse(parent: Instance, gz: number, look: { [string]: Color3 }, id: number, withBars: boolean, soon: boolean?)
	local T, G = W.tunnel, W.gate
	local half = T.width / 2
	local gf = folder("Gate" .. id, parent)
	for _, x in { -half - 2, half + 2 } do
		cyl(4, G.height + 9, CFrame.new(x, (G.height + 9) / 2, gz), V.stone, gf, true, Enum.Material.Cobblestone)
		cyl(4.5, 1.1, CFrame.new(x, G.height + 9.4, gz), V.trim, gf)
		for c = 0, 7 do
			local a = c * math.pi / 4
			block(Vector3.new(1.3, 1.5, 1.3), CFrame.new(x + math.cos(a) * 3.9, G.height + 10.7, gz + math.sin(a) * 3.9), V.stone, gf, false, Enum.Material.Cobblestone)
		end
		shape("Cone", Vector3.new(9.6, 9, 9.6), CFrame.new(x, G.height + 16, gz), look.accent, gf)
		cyl(0.15, 4, CFrame.new(x, G.height + 22, gz), V.iron, gf)
		block(Vector3.new(0.15, 1.4, 2.4), CFrame.new(x, G.height + 23.1, gz + 1.2), look.accent, gf)
		-- a lit arrow slit
		glow(block(Vector3.new(0.6, 2.2, 0.3), CFrame.new(x - math.sign(x) * 3.9, G.height + 3, gz - 0.6) * CFrame.Angles(0, -math.sign(x) * 0.9, 0), A.lanternGlow, gf), 0.1)
	end
	block(Vector3.new(T.width + 2, 2.2, 2.6), CFrame.new(0, G.height + 2.6, gz + 0.4), V.stone, gf, false, Enum.Material.Cobblestone)
	quiet(ellipsoid(Vector3.new(T.width + 4, 1.2, 3.2), CFrame.new(0, G.height + 3.8, gz + 0.4), A.snowCap, gf))
	local beam = glow(block(Vector3.new(T.width - 2, 1.6, 1.6), CFrame.new(0, G.height + 0.6, gz), look.accent, gf), 0.15)
	beam.Name = "GateGlow"
	for k = 0, 6 do
		local cx = -half + 6 + k * (T.width - 12) / 6
		glow(shape("Octa", Vector3.new(1.4, 2.6, 1.4), CFrame.new(cx, G.height + 5, gz + 0.4), A.crystalGlow, gf), 0.15)
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
	pathDetail(f, zone, cl, look, rng)
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
		LANDMARKS[isl.landmark](f, isl.landmarkAt.x, zone.zMin + isl.landmarkAt.z, C.landmarkScale)
	end
	local gz = WorldRules.gateZ(zone.id)
	if gz then
		gatehouse(f, gz, look, zone.id, true, not zone.ready)
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
	gatehouse(f, z + 0.6, look, 99, false)
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
	local terrain = workspace.Terrain
	if not terrain:FindFirstChildOfClass("Clouds") then
		local clouds = Instance.new("Clouds")
		clouds.Cover = C.clouds.cover
		clouds.Density = C.clouds.density
		clouds.Parent = terrain
	end
end

return MapArt
