--!strict
-- MapArt: the look of the world, ported from prototype scenery.js (hills, layered snowy pines, river
-- stones, bridge rails, the Forest gate with its arch, fences, hub lamps and benches, props, landmarks,
-- far peaks, clouds). It only decorates: every gameplay part, name and tag still comes from
-- WorldService, which calls MapArt.build once while it builds the map. Nothing here collides except
-- tree trunks and pen fences. Shapes Roblox has no primitive for (cone, crystal, rock, dome, ring,
-- arch) are MeshParts in ReplicatedStorage.SceneryMeshes; plain parts stand in when they're missing.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Config = require(ReplicatedStorage.Shared.Config)
local Theme = require(ReplicatedStorage.Shared.Theme)
local Scenery = require(ReplicatedStorage.Shared.Scenery)

local MapArt = {}
local A = Theme.art
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

local function block(size: Vector3, cf: CFrame, color: Color3, parent: Instance, collide: boolean?): BasePart
	local p = Instance.new("Part")
	p.Size = size
	p.CFrame = cf
	p.Material = Enum.Material.SmoothPlastic
	return finish(p, color, parent, collide)
end

-- an upright cylinder centred at cf
local function cyl(radius: number, height: number, cf: CFrame, color: Color3, parent: Instance, collide: boolean?): BasePart
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Cylinder
	p.Size = Vector3.new(height, radius * 2, radius * 2)
	p.CFrame = cf * CFrame.Angles(0, 0, math.pi / 2)
	p.Material = Enum.Material.SmoothPlastic
	return finish(p, color, parent, collide)
end

-- a (possibly squashed) sphere filling size
local function ellipsoid(size: Vector3, cf: CFrame, color: Color3, parent: Instance): BasePart
	local p = Instance.new("Part")
	p.Size = size
	p.CFrame = cf
	p.Material = Enum.Material.SmoothPlastic
	local m = Instance.new("SpecialMesh")
	m.MeshType = Enum.MeshType.Sphere
	m.Parent = p
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

local function folder(name: string, parent: Instance): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

-- ---------- trees ----------
local function tree(x: number, y: number, z: number, s: number, ry: number, kind: string, parent: Instance)
	local m = Instance.new("Model")
	m.Name = "Tree"
	local at = CFrame.new(x, y, z) * CFrame.Angles(0, ry, 0)
	cyl(0.43 * s, 2.4 * s, at * CFrame.new(0, 1.2 * s, 0), A.trunk, m, true)
	for _, c in (if kind == "snowpine" then SNOW_PINE else PINE) do
		shape("Cone", Vector3.new(c.r * 2 * s, c.h * s, c.r * 2 * s), at * CFrame.new(0, c.y * s, 0), c.color, m)
	end
	m.Parent = parent
end

-- ---------- hills: terrain rising past the map edge (snow north of the river, grass south) ----------
local function hillHeight(x: number, z: number): number
	local H, b = C.hills, W.bounds
	local edge = math.max(math.abs(x) - (b.xMax + 4), b.zMin + 4 - z, z - (b.zMax - 4), 0)
	if edge <= 0 then
		return 0
	end
	local n = math.noise(x * 0.05, z * 0.05) * 0.5 + 0.5
	return math.min(H.maxHeight, (edge / H.falloff) ^ H.power * H.scale) + n * edge * 0.25
end

local function hills(terrain: Terrain)
	local H, b, R = C.hills, W.bounds, W.river
	terrain:SetMaterialColor(Enum.Material.Snow, A.snowA)
	terrain:SetMaterialColor(Enum.Material.Grass, A.forestHill)
	for x = b.xMin - H.reach, b.xMax + H.reach, H.cell do
		for z = b.zMin - H.reach, b.zMax + H.reach, H.cell do
			local h = hillHeight(x, z)
			if h > 0 then
				local mat = if z > R.zMax and h < H.maxHeight * 0.8 then Enum.Material.Grass else Enum.Material.Snow
				-- a column up to just under the top, then a ball, so the hills are round, not terraced
				local top = h - H.cell * 0.5
				if top > H.base then
					terrain:FillBlock(CFrame.new(x, (H.base + top) / 2, z), Vector3.new(H.cell, top - H.base, H.cell), mat)
				end
				terrain:FillBall(Vector3.new(x, top, z), H.cell * 0.8, mat)
			end
		end
	end
end

local function groundY(x: number, z: number, terrain: Terrain): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { terrain }
	local hit = Workspace:Raycast(Vector3.new(x, 120, z), Vector3.new(0, -260, 0), params)
	return if hit then hit.Position.Y else 0
end

-- ---------- the river: stones on both banks ----------
local function river(parent: Instance, rng: () -> number)
	local R, b = W.river, W.bounds
	for i = 1, C.bankStones do
		local side = if i % 2 == 1 then R.zMin - 0.5 else R.zMax + 0.5
		local s = 0.6 + rng() * 0.9
		local x, z = b.xMin + rng() * (b.xMax - b.xMin), side + (rng() - 0.5) * 1.5
		shape("Rock", Vector3.new(s * 2, s, s * 2), CFrame.new(x, -0.1, z) * CFrame.Angles(0, rng() * 6, 0), A.stone, parent)
	end
	-- main bridge: posts and two rails (the walkway itself is WorldService's MainBridge)
	local mb = W.mainBridge
	local len, z0 = R.zMax - R.zMin + 6, R.zMin - 3
	for i = 0, 4 do
		for _, x in { mb.xMin, mb.xMax } do
			cyl(0.38, 3, CFrame.new(x, 1.5, z0 + i * len / 4), A.post, parent)
		end
	end
	for _, x in { mb.xMin, mb.xMax } do
		block(Vector3.new(0.4, 0.4, len), CFrame.new(x, 2.4, z0 + len / 2), A.rail, parent)
	end
	-- five crystals round each ice bridge spot
	local ib = W.iceBridgeSpot
	local cx = (ib.xMin + ib.xMax) / 2
	for _, sz in { R.zMin - 2, R.zMax + 2 } do
		for k = 0, 4 do
			local a = k / 5 * math.pi * 2
			glow(shape("Octa", Vector3.new(1.2, 2.6, 1.2), CFrame.new(cx + math.cos(a) * 3.6, 0.9, sz + math.sin(a) * 3.6), A.crystalGlow, parent), 0.15)
		end
	end
end

-- a fence line of posts with two rails (rails skip the given gap)
local function fence(parent: Instance, x1: number, z1: number, x2: number, z2: number, every: number, postColor: Color3, railColor: Color3, height: number, collide: boolean)
	local len = math.sqrt((x2 - x1) ^ 2 + (z2 - z1) ^ 2)
	local n = math.max(1, math.round(len / every))
	for i = 0, n do
		local x, z = x1 + (x2 - x1) * i / n, z1 + (z2 - z1) * i / n
		block(Vector3.new(0.6, height, 0.6), CFrame.new(x, height / 2, z), postColor, parent, collide)
	end
	local mid = CFrame.lookAt(Vector3.new((x1 + x2) / 2, 0, (z1 + z2) / 2), Vector3.new(x2, 0, z2))
	for _, y in { height * 0.38, height * 0.75 } do
		block(Vector3.new(0.25, 0.3, len), mid + Vector3.new(0, y, 0), railColor, parent, collide)
	end
end

-- ---------- the Forest gate: fence, two big posts, a wooden arch with ice crystals, ice bars ----------
local function gate(parent: Instance)
	local g, b = W.gate, W.bounds
	fence(parent, b.xMin, g.z, g.xMin - 1, g.z, C.gatePostEvery, A.post, A.rail, 3.2, false)
	fence(parent, g.xMax + 1, g.z, b.xMax, g.z, C.gatePostEvery, A.post, A.rail, 3.2, false)
	for _, x in { g.xMin, g.xMax } do
		cyl(1.08, 10, CFrame.new(x, 5, g.z), A.post, parent)
	end
	local radius = (g.xMax - g.xMin) / 2
	local cx = (g.xMin + g.xMax) / 2
	-- the Arch mesh is a half ring of radius 1 with a 0.09 tube: its box is 2.18 x 1.09 x 0.18
	shape("Arch", Vector3.new(2.18, 1.09, 0.18) * radius, CFrame.new(cx, 10 + 0.545 * radius, g.z), A.rail, parent)
	for k = 0, 6 do
		local a = math.pi * k / 6
		local cf = CFrame.new(cx + math.cos(a) * (radius + 0.5), 10 + math.sin(a) * (radius + 0.5), g.z) * CFrame.Angles(0, 0, a - math.pi / 2)
		glow(shape("Octa", Vector3.new(1.8, 3.2, 1.8), cf, A.crystalGlow, parent), 0.1)
	end
	-- the bars show the gate is shut; each client hides them once its player has opened the Forest
	local bars = folder("GateBars", parent)
	local x = g.xMin + 2
	while x < g.xMax do
		local bar = block(Vector3.new(0.8, 8, 0.8), CFrame.new(x, 4, g.z), A.iceBar, bars)
		bar.Material = Enum.Material.Ice
		bar.Transparency = 0.12
		x += 2.5
	end
	-- Sunny Beach (closed): a sandy fence
	local bz = W.beachGate.z + 1
	fence(parent, b.xMin, bz, b.xMax, bz, C.beachPostEvery, A.sandPost, A.sandRail, 3.2, false)
end

-- ---------- props: mounds, rocks, crystals (meadow); mushrooms, bushes, logs, lanterns (forest) ----------
local function mushroom(parent: Instance, x: number, z: number, s: number, ry: number)
	local at = CFrame.new(x, 0, z) * CFrame.Angles(0, ry, 0)
	cyl(0.4 * s, 1.2 * s, at * CFrame.new(0, 0.6 * s, 0), A.stem, parent)
	shape("Dome", Vector3.new(2 * s, 0.75 * s, 2 * s), at * CFrame.new(0, 1.475 * s, 0), A.cap, parent)
	for k = 0, 3 do
		ellipsoid(Vector3.one * 0.32 * s, at * CFrame.new(math.cos(k * 1.6) * 0.6 * s, 1.75 * s, math.sin(k * 1.6) * 0.6 * s), A.snowman, parent)
	end
end

local function props(parent: Instance, trees: { Scenery.Tree }, rng: () -> number)
	local R, P = W.river, C.props
	local function clear(x: number, z: number): boolean
		if math.abs(x) < 11 or (z > R.zMin - 5 and z < W.gate.z + 4) or z < 0 then
			return true
		end
		for _, t in trees do
			if (t.x - x) ^ 2 + (t.z - z) ^ 2 < 16 then
				return true
			end
		end
		return false
	end
	local function pick(n: number, zMin: number, zMax: number): { Vector2 }
		local out: { Vector2 } = {}
		for _ = 1, n * 3 do
			if #out >= n then
				break
			end
			local x, z = -74 + rng() * 148, zMin + rng() * (zMax - zMin)
			if not clear(x, z) then
				table.insert(out, Vector2.new(x, z))
			end
		end
		return out
	end
	for _, p in pick(P.mounds, 10, 160) do
		local s, sy = 1.4 + rng() * 2, 0.5 + rng() * 0.3
		ellipsoid(Vector3.new(s * 2, sy * 2, s * 2), CFrame.new(p.X, -0.3, p.Y), A.mound, parent).CastShadow = false
	end
	for _, p in pick(P.rocks, 10, 160) do
		local s = 0.8 + rng() * 1.2
		local at = CFrame.new(p.X, 0, p.Y) * CFrame.Angles(0, rng() * 6, 0)
		shape("Rock", Vector3.new(s * 2, 1.4 * s, s * 2), at * CFrame.new(0, 0.5 * s, 0), A.rock, parent)
		shape("Dome", Vector3.new(s * 1.5, 0.45 * s, s * 1.5), at * CFrame.new(0, 1.05 * s, 0), A.snowCap, parent)
	end
	for _, p in pick(P.crystals, 15, 155) do
		local s = 0.8 + rng() * 0.6
		local at = CFrame.new(p.X, 0, p.Y) * CFrame.Angles(0, rng() * 6, 0)
		for k = 0, 2 do
			glow(shape("Octa", Vector3.new(s, (2.2 + k * 0.4) * s, s), at * CFrame.new(math.cos(k * 2.1) * 0.5 * s, 0.8 * s, math.sin(k * 2.1) * 0.5 * s), A.crystalGlow, parent), 0.2)
		end
	end
	for _, p in pick(P.mushrooms, 200, 365) do
		mushroom(parent, p.X, p.Y, 0.8 + rng() * 1.1, rng() * 6)
	end
	for _, p in pick(P.bushes, 200, 365) do
		local s = 1 + rng() * 1.3
		ellipsoid(Vector3.new(s * 2, 1.5 * s, s * 2), CFrame.new(p.X, 0.4, p.Y), A.bush, parent)
	end
	for _, p in pick(P.logs, 205, 360) do
		local log = cyl(0.6, 4, CFrame.new(p.X, 0.6, p.Y), A.post, parent)
		log.CFrame = CFrame.new(p.X, 0.6, p.Y) * CFrame.Angles(0, rng() * 6, 0) -- lying down: a cylinder's own axis is X
	end
	-- lanterns along the forest path
	local z = R.zMax + 22
	while z < W.bounds.zMax - 6 do
		for _, x in { -10.5, 10.5 } do
			cyl(0.18, 3.2, CFrame.new(x, 1.6, z), A.benchLeg, parent)
			local l = glow(ellipsoid(Vector3.one * 0.9, CFrame.new(x, 3.2, z), A.lanternGlow, parent))
			local light = Instance.new("PointLight")
			light.Color = A.lanternGlow
			light.Range = 10
			light.Brightness = 0.8
			light.Parent = l
		end
		z += C.lanternEvery
	end
end

-- ---------- landmarks: ice-crystal statue (hub), giant snowman (meadow), giant mushroom (forest) ----------
local function landmarks(parent: Instance)
	local st = C.statue
	cyl(4.75, 1.6, CFrame.new(st.X, 0.8, st.Z), A.statueBase, parent, true)
	for _, c in { { 0, 9, 0, 2.2 }, { 2, 6, 1, 1.5 }, { -2, 6.5, -0.5, 1.6 }, { 0.8, 5, -2, 1.2 }, { -1.2, 4.6, 2, 1.1 } } do
		local p = shape("Octa", Vector3.new(c[4] * 2, c[2] * 1.25, c[4] * 2), CFrame.new(st.X + c[1], 1.6 + c[2] / 2, st.Z + c[3]), A.crystal, parent)
		p.Material = Enum.Material.Ice
		p.Transparency = 0.08
	end
	local sm = C.snowman
	local at = CFrame.new(sm.X, 0, sm.Z) * CFrame.Angles(0, 0.3, 0)
	for _, b in { { 4, 4 }, { 10, 3 }, { 14.6, 2.2 } } do
		ellipsoid(Vector3.one * b[2] * 2, at * CFrame.new(0, b[1], 0), A.snowman, parent)
	end
	shape("Cone", Vector3.new(0.9, 2.2, 0.9), at * CFrame.new(0, 14.6, -2.9) * CFrame.Angles(-math.pi / 2, 0, 0), A.carrot, parent)
	for _, x in { -0.8, 0.8 } do
		ellipsoid(Vector3.one * 0.6, at * CFrame.new(x, 15.3, -2), Theme.ink, parent)
	end
	shape("Ring", Vector3.new(5.9, 1.1, 5.9), at * CFrame.new(0, 12.6, 0), A.scarf, parent)
	cyl(1.6, 2.4, at * CFrame.new(0, 17.6, 0), A.hat, parent)
	local gm = C.giantMushroom
	cyl(2.6, 14, CFrame.new(gm.X, 7, gm.Z), A.stem, parent, true)
	shape("Dome", Vector3.new(18, 5.4, 18), CFrame.new(gm.X, 16.2, gm.Z), A.cap, parent)
	for k = 0, 8 do
		local a, rr = k * 0.7, 4 + (k % 3) * 1.5
		ellipsoid(Vector3.one * 2.2, CFrame.new(gm.X + math.cos(a) * rr, 13.5 + math.sqrt(math.max(0, 81 - rr * rr)) * 0.6 - 0.3, gm.Z + math.sin(a) * rr), A.snowman, parent)
	end
end

-- ---------- far scenery: snowy peaks north, green hills on the sides ----------
local function peak(parent: Instance, x: number, z: number, r: number, h: number, snowLine: number, low: Color3)
	local cy = h / 2 - 4
	local p = shape("Cone", Vector3.new(r * 2, h, r * 2), CFrame.new(x, cy, z), low, parent)
	p.CastShadow = false
	if snowLine < 1 then
		local top = 1 - snowLine
		local s = shape("Cone", Vector3.new(r * 2 * top + 0.5, h * top + 0.2, r * 2 * top + 0.5), CFrame.new(x, cy + h / 2 - h * top / 2 + 0.1, z), A.peakSnow, parent)
		s.CastShadow = false
	end
end

local function farScenery(parent: Instance)
	for i = 0, 12 do
		peak(parent, -300 + i * 50, -200 - (i % 3) * 40, 46 + (i % 4) * 10, 90 + (i % 5) * 22, 0.5, A.peakLow)
	end
	for i = 0, 7 do
		local snowy = i < 4
		peak(parent, if i % 2 == 1 then 230 else -230, 40 + i * 50, 60, 60 + (i % 3) * 20, if snowy then 0.55 else 1.1, if snowy then A.peakLow else A.peakGreen)
	end
end

-- ---------- hub: pen fences, spawn pad, lamps, benches ----------
local function hub(parent: Instance)
	local half = W.penSize / 2
	for _, pl in W.plots do
		local x0, x1, z0, z1 = pl.x - half.X, pl.x + half.X, pl.z - half.Z, pl.z + half.Z
		local gap = C.penFenceGap / 2
		fence(parent, x0, z0, x1, z0, C.penPostEvery, A.penPost, A.penRail, 2.4, true)
		fence(parent, x0, z0, x0, z1, C.penPostEvery, A.penPost, A.penRail, 2.4, true)
		fence(parent, x1, z0, x1, z1, C.penPostEvery, A.penPost, A.penRail, 2.4, true)
		fence(parent, x0, z1, pl.x - gap, z1, C.penPostEvery, A.penPost, A.penRail, 2.4, true) -- the open side faces the path
		fence(parent, pl.x + gap, z1, x1, z1, C.penPostEvery, A.penPost, A.penRail, 2.4, true)
	end
	local sp = W.spawn
	cyl(3.75, 0.35, CFrame.new(sp.X, 0.18, sp.Z), A.spawnPad, parent, true)
	glow(cyl(3.95, 0.2, CFrame.new(sp.X, 0.12, sp.Z), Theme.white, parent), 0.1)
	for _, l in C.lamps do
		cyl(0.26, 6.2, CFrame.new(l.X, 3.1, l.Z), A.lampPost, parent, true)
		local ball = ellipsoid(Vector3.one * 1.1, CFrame.new(l.X, 6.4, l.Z), A.lampGlow, parent) -- warm, not Neon: Neon blooms into a big blob up close
		local light = Instance.new("PointLight")
		light.Color = A.lanternGlow
		light.Range = 16
		light.Brightness = 0.8
		light.Parent = ball
	end
	for _, bspec in C.benches do
		local at = CFrame.new(bspec.pos) * CFrame.Angles(0, bspec.ry, 0)
		block(Vector3.new(4, 0.35, 1.2), at * CFrame.new(0, 1, 0), A.penRail, parent, true)
		block(Vector3.new(4, 1, 0.3), at * CFrame.new(0, 1.6, 0.55), A.penRail, parent, true)
		for _, x in { -1.6, 1.6 } do
			block(Vector3.new(0.3, 1, 1), at * CFrame.new(x, 0.5, 0), A.benchLeg, parent, true)
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
	local terrain = Workspace.Terrain
	hills(terrain)
	local trees = folder("Trees", art)
	for _, t in list.trees do
		tree(t.x, 0, t.z, t.r / C.treeUnitRadius, rng() * 6, t.kind, trees)
	end
	local b, R = W.bounds, W.river
	for i = 1, C.hillTrees do
		local side = if i % 2 == 1 then 1 else -1
		local x, z = side * (b.xMax + 10 + rng() * 60), -60 + rng() * 440
		local s, ry = 1.2 + rng() * 1.2, rng() * 6
		if not (z > R.zMin - 4 and z < R.zMax + 4) then
			tree(x, groundY(x, z, terrain), z, s, ry, if z < R.zMin then "snowpine" else "pine", trees)
		end
	end
	river(folder("River", art), rng)
	gate(folder("Gate", art))
	props(folder("Props", art), list.trees, rng)
	landmarks(folder("Landmarks", art))
	farScenery(folder("Far", art))
	hub(folder("Hub", art))
	-- two wooden legs under each zone sign (the board itself is WorldService's ZoneSign)
	local legs = folder("SignLegs", art)
	for _, z in W.zones do
		for _, dx in { -4.2, 4.2 } do
			cyl(0.3, 2.2, CFrame.new(z.signPos.X + dx, 1.1, z.signPos.Z), A.post, legs)
		end
	end
	if not terrain:FindFirstChildOfClass("Clouds") then
		local clouds = Instance.new("Clouds")
		clouds.Cover = C.clouds.cover
		clouds.Density = C.clouds.density
		clouds.Parent = terrain
	end
end

return MapArt
