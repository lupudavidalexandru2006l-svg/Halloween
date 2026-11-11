--!strict
-- TrainingArt: builds a pan's Cold Power trainer (owner 2026-11-10; replaces the sky rink and its door).
-- From the owner's references (hit simulators' training dummies, training gear in every base, and on
-- 2026-11-11 a neon shrine clip: "different designs, all WINTER, COLD, at this level"): a raised pad in
-- front of the pan, right of its door, the open side toward the pan, and a warm target on the plaza side
-- that the client frosts over as you shoot it (local +Z, Config.trainerFrame, faces the plaza).
-- Each level is its own winter place, round and cosy first, pointy and grand last (designing-map-appeal):
--   1 Igloo Camp: a snowman inside a snow-brick wall, an igloo with a lit door, snowy pines, fairy lights
--   2 Frost Dojo: a heat bag hanging from an ice torii, paper screens, stone lanterns, frost-blossom trees
--   3 Glacier Fortress: a magma golem before a frozen waterfall, ice walls with spikes, crystal spires
--   4 Aurora Wolf Shrine: a little sun inside a neon wolf-head gate, pagodas, aurora trees and ribbons
-- The targets are the warm things you freeze; everything round them is snow and ice. Same footprint and
-- target spot on every level, so the lock and the bolts never change. TrainingService builds each pan's
-- trainer at its owner's level and rebuilds it on an upgrade. Sizes and places: Config.training;
-- colours: Theme.training.
-- Contract (TrainingController): each target is a Model named Target, tagged Config.training.targetTag,
-- with the attributes Station (its pan) and Tier (its level) and its WorldPivot at the target's foot. Parts the client cools
-- toward frost are named Heat. A heat bag's model also has HangAt (the chain's top: it swings from there).

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Theme = require(ReplicatedStorage.Shared.Theme)

local TrainingArt = {}
local T = Config.training
local TT = Theme.training
local W, D, H = T.padSize[1], T.padSize[2], T.padHeight
local meshes: Instance? = nil

-- ---------- pieces ----------
local function finish(p: BasePart, color: Color3, parent: Instance, collide: boolean?): BasePart
	p.Anchored = true
	p.CanCollide = collide == true
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

-- a ramp: full height at its local +Z end, down to nothing at -Z
local function wedge(size: Vector3, cf: CFrame, color: Color3, parent: Instance, collide: boolean?, material: Enum.Material?): BasePart
	local p = Instance.new("WedgePart")
	p.Size = size
	p.CFrame = cf
	p.Material = material or Enum.Material.SmoothPlastic
	return finish(p, color, parent, collide)
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

-- a cylinder lying along cf's X axis (a rope, a log, a disc facing X)
local function rod(length: number, radius: number, cf: CFrame, color: Color3, parent: Instance, material: Enum.Material?): BasePart
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Cylinder
	p.Size = Vector3.new(length, radius * 2, radius * 2)
	p.CFrame = cf
	p.Material = material or Enum.Material.SmoothPlastic
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

-- one of the imported shapes (ReplicatedStorage.SceneryMeshes), stretched to size; a sphere stands in
local function shape(name: string, size: Vector3, cf: CFrame, color: Color3, parent: Instance): BasePart
	local template = meshes and meshes:FindFirstChild(name)
	if template and template:IsA("MeshPart") then
		local p = template:Clone()
		p.Size = size
		p.CFrame = cf
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

local function quiet(p: BasePart): BasePart
	p.CastShadow = false
	return p
end

local function named(p: BasePart, name: string): BasePart
	p.Name = name
	return p
end

-- a thin straight piece from a to b (a wire, a branch)
local function segment(a: Vector3, b: Vector3, r: number, color: Color3, parent: Instance, material: Enum.Material?): BasePart
	return quiet(rod((b - a).Magnitude, r, CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, math.pi / 2, 0), color, parent, material))
end

local function light(parent: Instance, color: Color3, range: number, brightness: number)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Shadows = false
	l.Parent = parent
end

local function folder(name: string, parent: Instance): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

-- glints drifting out of an invisible box (heat off a target, cold off a brazier)
local function sparkles(parent: Instance, size: Vector3, cf: CFrame, color: Color3, rate: number, speed: number, big: number)
	local p = quiet(block(size, cf, color, parent))
	p.Name = "Sparkles"
	p.Transparency = 1
	p.CanQuery = false
	local e = Instance.new("ParticleEmitter")
	e.Shape = Enum.ParticleEmitterShape.Box
	e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	e.Color = ColorSequence.new(Theme.white, color)
	e.LightEmission = 1
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.4, big), NumberSequenceKeypoint.new(1, 0) })
	e.Lifetime = NumberRange.new(0.8, 1.4)
	e.Rate = rate
	e.Speed = NumberRange.new(speed * 0.5, speed)
	e.EmissionDirection = Enum.NormalId.Top
	e.Parent = p
end

-- flakes (snow, petals) falling slowly out of an invisible box, about `fall` studs before they fade
local function flakes(parent: Instance, size: Vector3, cf: CFrame, a: Color3, b: Color3, rate: number, big: number, fall: number)
	local p = quiet(block(size, cf, a, parent))
	p.Name = "Flakes"
	p.Transparency = 1
	p.CanQuery = false
	local e = Instance.new("ParticleEmitter")
	e.Shape = Enum.ParticleEmitterShape.Box
	e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	e.Color = ColorSequence.new(a, b)
	e.LightEmission = 0.4
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.15, big), NumberSequenceKeypoint.new(0.85, big), NumberSequenceKeypoint.new(1, 0) })
	e.Speed = NumberRange.new(1.6, 2.4)
	e.Lifetime = NumberRange.new(fall / 2.4, fall / 1.6)
	e.Rate = rate
	e.SpreadAngle = Vector2.new(20, 20)
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-90, 90)
	e.EmissionDirection = Enum.NormalId.Bottom
	e.Parent = p
end

-- parts the client moves (MapController). Kind "spin": round the Pivot's local Axis at Speed rad/s
local function spinner(parent: Instance, pivot: CFrame, axis: Vector3, speed: number): Folder
	local f = folder("Motion", parent)
	f:SetAttribute("Kind", "spin")
	f:SetAttribute("Pivot", pivot)
	f:SetAttribute("Axis", axis)
	f:SetAttribute("Speed", speed)
	CollectionService:AddTag(f, Config.mapFx.motionTag)
	return f
end

-- ... or up and down by Amp studs, Hz times a second (Phase 0-1 staggers neighbours)
local function bobber(parent: Instance, pivot: CFrame, amp: number, hz: number, phase: number): Folder
	local f = folder("Motion", parent)
	f:SetAttribute("Kind", "bob")
	f:SetAttribute("Pivot", pivot)
	f:SetAttribute("Amp", amp)
	f:SetAttribute("Hz", hz)
	f:SetAttribute("Phase", phase)
	CollectionService:AddTag(f, Config.mapFx.motionTag)
	return f
end

-- a snowy pine h studs tall standing at base: a trunk and three cone tiers, each with a snow cap
local function pine(f: Instance, base: CFrame, h: number, green: Color3, dark: Color3, snow: Color3, trunk: Color3)
	cyl(0.3 * h / 6, h * 0.24, base * CFrame.new(0, h * 0.12, 0), trunk, f, true, Enum.Material.WoodPlanks)
	for k = 0, 2 do
		local w = h * (0.62 - k * 0.15)
		local ch = h * (0.4 - k * 0.06)
		local y = h * (0.18 + k * 0.22) + ch / 2
		local turn = CFrame.Angles(0, k * 0.5, 0)
		shape("Cone", Vector3.new(w, ch, w), base * CFrame.new(0, y, 0) * turn, if k % 2 == 0 then green else dark, f)
		quiet(shape("Cone", Vector3.new(w * 0.5 + 0.12, ch * 0.5 + 0.06, w * 0.5 + 0.12), base * CFrame.new(0, y + ch / 4 + 0.03, 0) * turn, snow, f))
	end
end

-- a blossom tree h studs tall leaning toward local X `out` (1 or -1): a bent trunk, a side branch and a
-- crown of puffs (every other one glowing when neon)
local BLOOM = { -- each puff: offset from the crown and radius, for a tree 7 studs tall
	{ 0, 0.5, 0, 1.5 }, { 1.5, 0, 0.3, 1.2 }, { -1.4, 0.1, -0.2, 1.25 }, { 0.6, 1.3, -0.5, 1.05 }, { -0.6, 1.1, 0.6, 1.05 },
	{ 0.3, -0.6, 1.0, 1.0 }, { -0.2, -0.5, -1.0, 1.0 }, { 1.9, -0.7, -0.3, 0.8 }, { -1.8, -0.6, 0.4, 0.8 },
}
local function blossomTree(f: Instance, base: CFrame, h: number, out: number, trunk: Color3, blooms: { Color3 }, neon: boolean)
	local k = h / 7
	local root = base.Position
	local bend = root + base:VectorToWorldSpace(Vector3.new(out * 0.35 * k, h * 0.38, 0))
	local crown = root + base:VectorToWorldSpace(Vector3.new(out * 0.9 * k, h * 0.62, 0))
	segment(root, bend, 0.36 * k, trunk, f, Enum.Material.Wood)
	segment(bend, crown, 0.28 * k, trunk, f, Enum.Material.Wood)
	quiet(ball(0.3 * k, bend, trunk, f))
	segment(bend, bend + base:VectorToWorldSpace(Vector3.new(-out * 1.2 * k, 1.3 * k, 0.5 * k)), 0.18 * k, trunk, f, Enum.Material.Wood)
	for n, o in BLOOM do
		local p = quiet(ball(o[4] * k, crown + base:VectorToWorldSpace(Vector3.new(o[1] * k, (o[2] + 0.6) * k, o[3] * k)), blooms[(n - 1) % #blooms + 1], f))
		if neon and n % 2 == 1 then
			glow(p, 0.2)
		end
	end
end

-- fairy lights on a sagging wire from a to b
local function stringLights(f: Instance, a: Vector3, b: Vector3, sag: number, n: number, colors: { Color3 }, wire: Color3)
	local prev = a
	for k = 1, n do
		local t = k / (n + 1)
		local p = a:Lerp(b, t) - Vector3.new(0, sag * 4 * t * (1 - t), 0)
		segment(prev, p, 0.04, wire, f)
		quiet(glow(ball(0.2, p - Vector3.new(0, 0.22, 0), colors[(k - 1) % #colors + 1], f)))
		prev = p
	end
	segment(prev, b, 0.04, wire, f)
end

-- the raised pad every station stands on: the floor (you walk on it), a darker plinth that shows as
-- a lip all round, and a pattern of tiles a hair above the floor (never flush: flush tops flicker)
local function pad(f: Instance, at: CFrame, floor: Color3, tile: Color3, edge: Color3, material: Enum.Material?, tiles: string)
	named(block(Vector3.new(W, H, D), at * CFrame.new(0, H / 2, 0), floor, f, true, material), "Pad")
	quiet(block(Vector3.new(W + 0.8, H * 0.6, D + 0.8), at * CFrame.new(0, H * 0.3, 0), edge, f, true, Enum.Material.Slate))
	if tiles == "checker" then
		local cols, rows = 4, 4
		local tw, td = W / cols, D / rows
		for cx = 0, cols - 1 do
			for cz = 0, rows - 1 do
				if (cx + cz) % 2 == 0 then
					quiet(block(Vector3.new(tw - 0.2, 0.04, td - 0.2), at * CFrame.new(-W / 2 + (cx + 0.5) * tw, H + 0.02, -D / 2 + (cz + 0.5) * td), tile, f, false, material))
				end
			end
		end
	elseif tiles == "grid" then
		for x = -W / 2 + 2, W / 2 - 2, 2 do
			quiet(block(Vector3.new(0.12, 0.03, D - 0.4), at * CFrame.new(x, H + 0.015, 0), tile, f))
		end
		for z = -D / 2 + 2, D / 2 - 2, 2 do
			quiet(block(Vector3.new(W - 0.4, 0.03, 0.12), at * CFrame.new(0, H + 0.015, z), tile, f))
		end
	end
end

-- a target model: tagged for the client, pivot at its foot
local function target(f: Instance, i: number): Model
	local m = Instance.new("Model")
	m.Name = "Target"
	m:SetAttribute("Tier", f:GetAttribute("Tier"))
	m.ModelStreamingMode = Enum.ModelStreamingMode.Atomic -- it streams in whole, so the client can move it as one
	m:SetAttribute("Station", i)
	m.Parent = f
	return m
end

local function sealTarget(m: Model, foot: CFrame)
	m.WorldPivot = foot
	CollectionService:AddTag(m, T.targetTag)
end

-- an invisible post where the target stands, so nobody walks through it (the drawn target never collides:
-- the client moves it)
local function targetBlock(f: Instance, cf: CFrame, size: Vector3)
	local p = block(size, cf, TT.pad, f, true)
	p.Name = "TargetBlock"
	p.Transparency = 1
	p.CastShadow = false
	p.CanQuery = false
end

-- ---------- 1. Igloo Camp: a snow-brick wall round the dummy, an igloo, snowy pines, fairy lights ----------
local function iglooCamp(f: Instance, at: CFrame, i: number)
	local P = TT.stations.snowman
	pad(f, at, P.floor, P.tile, TT.padEdge, Enum.Material.SmoothPlastic, "checker")
	local tz = T.targetZ
	-- the snow-brick wall: an oval of ice bricks round the back of the dummy, three rows at the back,
	-- two at the sides, bricks staggered row by row, snow on top
	local rx, rz, span = W / 2 - 0.6, 2.75, math.rad(100)
	local function onWall(a: number): Vector3
		return Vector3.new(rx * math.sin(a), 0, tz + rz * math.cos(a))
	end
	local n = 10
	local step = span * 2 / n
	for row = 0, 2 do
		local off = (row % 2) * 0.5
		for k = 0, n - 1 - (row % 2) do
			local a = -span + (k + 0.5 + off) * step
			local side = math.abs(a) > math.rad(62)
			if row == 2 and side then
				continue
			end
			local p0, p1 = onWall(a - step / 2), onWall(a + step / 2)
			local len = (p1 - p0).Magnitude + 0.06
			local y0 = if row == 0 then 0 else H + 1.1 * row
			local y1 = H + 1.1 * (row + 1)
			local mid, y = onWall(a), (y0 + y1) / 2
			local cf = at * CFrame.lookAt(Vector3.new(mid.X, y, mid.Z), Vector3.new(p1.X, y, p1.Z))
			block(Vector3.new(0.9, y1 - y0, len), cf, if (k + row) % 2 == 0 then P.brick else P.brickShade, f, true)
			if (row == 2 or row == 1 and side) and k % 2 == 0 then
				quiet(ellipsoid(Vector3.new(1.1, 0.45, len * 0.9), cf * CFrame.new(0, (y1 - y0) / 2, 0), P.snow, f))
			end
		end
	end
	-- two snowy pines behind the wall's back corners, fairy lights strung between them
	local lx, lz, rxp, rzp = -W / 2 + 0.9, D / 2 - 0.3, W / 2 - 0.7, D / 2 - 0.5
	pine(f, at * CFrame.new(lx, H, lz), 8, P.pine, P.pineDark, P.snow, P.woodDark)
	pine(f, at * CFrame.new(rxp, H, rzp), 6.6, P.pine, P.pineDark, P.snow, P.woodDark)
	local star = quiet(glow(shape("Octa", Vector3.new(0.9, 1.3, 0.5), at * CFrame.new(lx, H + 7.6, lz), P.star, f)))
	light(star, P.star, 10, 0.7)
	stringLights(f, (at * CFrame.new(lx, H + 6.4, lz)).Position, (at * CFrame.new(rxp, H + 5.6, rzp)).Position, 1.2, 11,
		{ P.bulbRed, P.bulbGold, P.bulbIce, P.bulbLime }, P.iron)
	-- the igloo in the front right corner: block seams, a tunnel and a warm lit doorway toward the stand spot
	local ig = at * CFrame.new(W / 2 - 1.75, H, -D / 2 + 2.1)
	local ir, ih = 1.85, 2.9
	named(shape("Dome", Vector3.new(ir * 2, ih, ir * 2), ig * CFrame.new(0, ih / 2, 0), P.igloo, f), "Igloo").CanCollide = true
	for _, t in { 0.3, 0.58, 0.82 } do
		local rr = ir * math.sqrt(1 - t * t)
		quiet(shape("Ring", Vector3.new(rr * 2 + 0.12, 0.14, rr * 2 + 0.12), ig * CFrame.new(0, ih * t, 0), P.iglooSeam, f))
	end
	local mouth = ig * CFrame.new(-ir - 0.2, 0, 0)
	rod(1.6, 1.0, mouth * CFrame.new(0.5, 0, 0), P.igloo, f) -- its lower half sits inside the pad
	quiet(rod(0.1, 1.04, mouth * CFrame.new(-0.3, 0, 0), P.iglooSeam, f))
	local door = quiet(glow(rod(0.06, 0.72, mouth * CFrame.new(-0.38, 0, 0), P.lamp, f)))
	light(door, P.lamp, 9, 0.9)
	-- a pile of snowballs beside it
	local sx, sz = W / 2 - 1.1, -1.0
	for _, s in { { 0, 0.3 }, { 0.6, -0.4 }, { -0.5, -0.3 } } do
		ball(0.5, (at * CFrame.new(sx + s[1], H + 0.45, sz + s[2])).Position, P.snow, f)
	end
	ball(0.45, (at * CFrame.new(sx, H + 1.2, sz - 0.1)).Position, P.snow, f)
	-- a lantern post in the front left corner
	local lp = at * CFrame.new(-W / 2 + 0.7, H, -D / 2 + 0.7)
	block(Vector3.new(0.35, 3.8, 0.35), lp * CFrame.new(0, 1.9, 0), P.iron, f, true)
	block(Vector3.new(1.3, 0.2, 0.2), lp * CFrame.new(0.55, 3.7, 0), P.iron, f)
	quiet(ellipsoid(Vector3.new(0.6, 0.22, 0.6), lp * CFrame.new(0, 3.85, 0), P.snow, f))
	local lan = lp * CFrame.new(1.05, 2.7, 0)
	quiet(block(Vector3.new(0.7, 0.12, 0.7), lan * CFrame.new(0, -0.44, 0), P.iron, f))
	local bulb = quiet(glow(block(Vector3.new(0.55, 0.75, 0.55), lan, P.lamp, f), 0.05))
	for _, cx in { -1, 1 } do
		for _, cz in { -1, 1 } do
			quiet(block(Vector3.new(0.1, 0.8, 0.1), lan * CFrame.new(cx * 0.3, 0, cz * 0.3), P.iron, f))
		end
	end
	quiet(shape("Cone", Vector3.new(0.95, 0.5, 0.95), lan * CFrame.new(0, 0.62, 0), P.iron, f))
	quiet(ellipsoid(Vector3.new(0.8, 0.25, 0.8), lan * CFrame.new(0, 0.8, 0), P.snow, f))
	quiet(rod(0.12, 0.06, lan * CFrame.new(0, 0.95, 0) * CFrame.Angles(0, 0, math.pi / 2), P.iron, f))
	light(bulb, P.lamp, 12, 0.8)
	-- snow drifts along the sides
	for _, d in { { -W / 2 + 0.7, -2.2, 1.7, 1.2, 3.4 }, { -W / 2 + 0.6, 0.8, 1.4, 0.9, 2.4 }, { W / 2 - 0.6, 1.6, 1.4, 1.0, 2.4 } } do
		quiet(ellipsoid(Vector3.new(d[3], d[4], d[5]), at * CFrame.new(d[1], H, d[2]), P.snow, f))
	end
	-- the camp's own snowfall
	flakes(f, Vector3.new(W + 2, 0.4, D + 2), at * CFrame.new(0, H + 13, 0), P.flake, Theme.white, 7, 0.28, 13)

	-- the Snowman Dummy: a wooden stand, three snowballs, a bullseye on its chest, X eyes, a carrot,
	-- a red bucket hat with a gold band, a blue scarf and stick arms
	local foot = at * CFrame.new(0, H, tz)
	local m = target(f, i)
	cyl(1.7, 0.35, foot * CFrame.new(0, 0.175, 0), P.woodDark, m, false, Enum.Material.WoodPlanks)
	local by, my, hy = 2.15, 5.05, 7.15
	named(ball(2, (foot * CFrame.new(0, by, 0)).Position, P.snow, m), "Heat")
	named(ball(1.5, (foot * CFrame.new(0, my, 0)).Position, P.snow, m), "Heat")
	named(ball(1.05, (foot * CFrame.new(0, hy, 0)).Position, P.snow, m), "Heat")
	-- the bullseye, as discs facing the shooter (-Z)
	local face = CFrame.Angles(0, math.pi / 2, 0)
	for k, r in { 0.95, 0.66, 0.36 } do
		quiet(rod(0.08, r, foot * CFrame.new(0, my + 0.05, -1.28 - k * 0.05) * face, if k % 2 == 1 then P.ring else P.ringLight, m))
	end
	-- X eyes and a little smile
	for _, s in { -1, 1 } do
		for _, a in { -0.78, 0.78 } do
			quiet(block(Vector3.new(0.13, 0.5, 0.13), foot * CFrame.new(s * 0.38, hy + 0.22, -0.92) * CFrame.Angles(0, 0, a), P.coal, m))
		end
	end
	for k = -2, 2 do
		quiet(ball(0.08, (foot * CFrame.new(k * 0.17, hy - 0.42 + math.abs(k) * 0.06, -0.93)).Position, P.coal, m))
	end
	quiet(shape("Cone", Vector3.new(0.34, 1, 0.34), foot * CFrame.new(0, hy - 0.05, -1.2) * CFrame.Angles(-math.pi / 2, 0, 0), P.carrot, m))
	-- the bucket hat, tipped a little
	local hat = foot * CFrame.new(0.1, hy + 0.85, 0) * CFrame.Angles(0, 0, -0.12)
	cyl(1.3, 0.14, hat, P.hat, m)
	cyl(0.86, 1, hat * CFrame.new(0, 0.55, 0), P.hat, m)
	quiet(cyl(0.88, 0.22, hat * CFrame.new(0, 0.25, 0), P.hatBand, m))
	-- the scarf and its loose end
	cyl(1.12, 0.42, foot * CFrame.new(0, 6.35, 0) * CFrame.Angles(0.06, 0, 0), P.scarf, m)
	quiet(block(Vector3.new(0.5, 1.5, 0.16), foot * CFrame.new(0.65, 5.6, -1.2) * CFrame.Angles(0.2, 0, 0.12), P.scarf, m))
	-- stick arms, raised like it's ready
	for _, s in { -1, 1 } do
		local arm = foot * CFrame.new(s * 2.35, my + 0.75, 0) * CFrame.Angles(0, 0, s * -0.95)
		block(Vector3.new(0.2, 2.6, 0.2), arm, P.woodDark, m, false, Enum.Material.WoodPlanks)
		for _, a in { -0.5, 0.5 } do
			quiet(block(Vector3.new(0.14, 0.7, 0.14), arm * CFrame.new(0, 1.35, 0) * CFrame.Angles(0, 0, a), P.woodDark, m))
		end
	end
	sealTarget(m, foot)
	targetBlock(f, foot * CFrame.new(0, 4, 0), Vector3.new(3.6, 8, 3.6))
end

-- ---------- 2. Frost Dojo: an ice torii the heat bag hangs from, paper screens, stone lanterns, frost blossoms ----------
local function frostDojo(f: Instance, at: CFrame, i: number)
	local P = TT.stations.heatbag
	pad(f, at, P.floor, P.tile, P.toriiDark, Enum.Material.SmoothPlastic, "grid")
	local tz = T.targetZ
	-- the round mat under the bag (blue, white, blue) with a snowflake on it
	for k, r in { 3, 2.4, 1.8 } do
		quiet(cyl(r, 0.05, at * CFrame.new(0, H + 0.03 + k * 0.03, tz - 0.4), if k == 2 then P.matRing else P.mat, f))
	end
	for k = 0, 2 do
		quiet(block(Vector3.new(0.22, 0.03, 3.1), at * CFrame.new(0, H + 0.14, tz - 0.4) * CFrame.Angles(0, k * math.pi / 3, 0), P.matRing, f))
	end
	-- the torii: two indigo pillars with a neon line up their fronts, the lower beam (the bag hangs from
	-- it), a plaque with a snowflake, and the snowy top beam with upswept ends
	local fz = tz + 0.2
	local px = 3.6
	local nukiY = 8.2
	for _, s in { -1, 1 } do
		local base = at * CFrame.new(s * px, H, fz)
		cyl(0.5, 8.6, base * CFrame.new(0, 4.3, 0), P.torii, f, true)
		cyl(0.7, 0.7, base * CFrame.new(0, 0.35, 0), P.toriiDark, f, true)
		quiet(glow(cyl(0.56, 0.16, base * CFrame.new(0, 0.8, 0), P.neon, f)))
		quiet(glow(block(Vector3.new(0.16, 7, 0.1), base * CFrame.new(0, 4.4, -0.49), P.neon, f)))
	end
	block(Vector3.new(8.8, 0.55, 0.55), at * CFrame.new(0, H + nukiY, fz), P.torii, f)
	quiet(glow(block(Vector3.new(8.4, 0.08, 0.08), at * CFrame.new(0, H + nukiY - 0.3, fz - 0.3), P.neon, f)))
	local plaque = at * CFrame.new(0, H + 8.95, fz)
	block(Vector3.new(1.45, 1.3, 0.25), plaque * CFrame.new(0, 0, 0.04), P.toriiDark, f)
	block(Vector3.new(1.15, 1.0, 0.25), plaque, P.plaque, f)
	for k = 0, 2 do
		quiet(glow(block(Vector3.new(0.09, 0.8, 0.05), plaque * CFrame.new(0, 0, -0.14) * CFrame.Angles(0, 0, k * math.pi / 3), P.neon, f)))
	end
	block(Vector3.new(9.4, 0.4, 0.7), at * CFrame.new(0, H + 9.75, fz), P.torii, f)
	block(Vector3.new(9.6, 0.6, 0.9), at * CFrame.new(0, H + 10.25, fz), P.toriiDark, f)
	quiet(glow(block(Vector3.new(9.0, 0.1, 0.1), at * CFrame.new(0, H + 9.93, fz - 0.46), P.neon, f)))
	for _, s in { -1, 1 } do
		wedge(Vector3.new(0.9, 0.9, 1.6), at * CFrame.new(s * 4.8, H + 10.65, fz) * CFrame.Angles(0, s * math.pi / 2, 0), P.toriiDark, f)
	end
	quiet(block(Vector3.new(8, 0.22, 0.95), at * CFrame.new(0, H + 10.65, fz), P.snow, f))
	for _, x in { -2.6, 0.4, 2.9 } do
		quiet(ellipsoid(Vector3.new(1.6, 0.4, 0.9), at * CFrame.new(x, H + 10.78, fz), P.snow, f))
	end
	-- paper screens down both sides: navy frames, see-through paper, a neon line under the top rail
	local function shoji(cf: CFrame, len: number)
		local h = 2.6
		block(Vector3.new(0.3, 0.25, len), cf * CFrame.new(0, H + 0.125, 0), P.frame, f, true)
		block(Vector3.new(0.3, 0.25, len + 0.3), cf * CFrame.new(0, H + h, 0), P.frame, f, true)
		local paper = quiet(block(Vector3.new(0.08, h - 0.3, len), cf * CFrame.new(0, H + h / 2 + 0.06, 0), P.paper, f, true))
		paper.Transparency = 0.25
		local cells = math.max(2, math.floor(len / 1.4))
		for k = 0, cells do
			block(Vector3.new(0.22, h, 0.22), cf * CFrame.new(0, H + h / 2, -len / 2 + k * len / cells), P.frame, f)
		end
		quiet(block(Vector3.new(0.14, 0.08, len), cf * CFrame.new(0, H + h * 0.55, 0), P.frame, f))
		quiet(glow(block(Vector3.new(0.34, 0.07, len + 0.3), cf * CFrame.new(0, H + h - 0.16, 0), P.neon, f)))
		quiet(ellipsoid(Vector3.new(0.6, 0.3, len + 0.4), cf * CFrame.new(0, H + h + 0.15, 0), P.snow, f))
	end
	shoji(at * CFrame.new(-W / 2 + 0.35, 0, -0.6), 6.2)
	shoji(at * CFrame.new(W / 2 - 0.35, 0, -0.6), 6.2)
	-- stone lanterns in the front corners, a cold flame in each
	for _, s in { -1, 1 } do
		local b = at * CFrame.new(s * (W / 2 - 0.85), H, -D / 2 + 0.85)
		block(Vector3.new(1.3, 0.4, 1.3), b * CFrame.new(0, 0.2, 0), P.stoneDark, f, true)
		cyl(0.28, 1.6, b * CFrame.new(0, 1.2, 0), P.stone, f, true)
		block(Vector3.new(1.1, 0.3, 1.1), b * CFrame.new(0, 2.1, 0), P.stoneDark, f)
		local box = b * CFrame.new(0, 2.65, 0)
		local fire = quiet(glow(block(Vector3.new(0.62, 0.62, 0.62), box, P.flame, f), 0.05))
		for _, cx in { -1, 1 } do
			for _, cz in { -1, 1 } do
				quiet(block(Vector3.new(0.18, 0.8, 0.18), box * CFrame.new(cx * 0.38, 0, cz * 0.38), P.stone, f))
			end
		end
		shape("Cone", Vector3.new(1.9, 0.8, 1.9), box * CFrame.new(0, 0.8, 0), P.stoneDark, f)
		quiet(ellipsoid(Vector3.new(1.5, 0.35, 1.5), box * CFrame.new(0, 1.05, 0), P.snow, f))
		quiet(ball(0.18, (box * CFrame.new(0, 1.35, 0)).Position, P.stone, f))
		light(fire, P.flame, 10, 0.8)
	end
	-- frost-blossom trees in the back corners, petals drifting off them
	for _, s in { -1, 1 } do
		local t = at * CFrame.new(s * (W / 2 - 0.8), H, D / 2 - 0.6)
		blossomTree(f, t, 7.2, s, P.trunk, { P.bloom, P.bloomIce, P.bloomPink, P.bloom }, false)
		flakes(f, Vector3.new(3, 0.3, 3), t * CFrame.new(s * 0.6, 6.4, 0), P.bloomPink, P.bloom, 3, 0.22, 6)
	end

	-- the chain, link by link, from the lower beam to the bag's top
	local bagY, bagH = 4.6, 4.6
	local hangY = nukiY - 0.28
	local hang = at * CFrame.new(0, H + hangY, tz)
	local links = 3
	local drop = hangY - (bagY + bagH / 2)
	for k = 0, links - 1 do
		quiet(shape("Ring", Vector3.new(0.55, 0.14, 0.75), hang * CFrame.new(0, -(k + 0.5) * drop / links, 0) * CFrame.Angles(0, k * math.pi / 2, math.pi / 2), P.chain, f))
	end
	-- the Heat Bag: a warm red bag with cream bands, a navy top and bottom, a cream X, heat rising off it
	local foot = at * CFrame.new(0, H, tz)
	local m = target(f, i)
	local mid = foot * CFrame.new(0, bagY, 0)
	named(cyl(1.55, bagH, mid, P.bag, m), "Heat")
	cyl(1.35, 0.35, mid * CFrame.new(0, bagH / 2 + 0.15, 0), P.post, m)
	cyl(1.35, 0.35, mid * CFrame.new(0, -bagH / 2 - 0.15, 0), P.post, m)
	for _, y in { -1.4, 1.4 } do
		quiet(cyl(1.6, 0.38, mid * CFrame.new(0, y, 0), P.band, m))
	end
	for _, a in { -0.62, 0.62 } do
		quiet(block(Vector3.new(0.38, 2.2, 0.12), mid * CFrame.new(0, 0, -1.5) * CFrame.Angles(0, 0, a), P.band, m))
	end
	local warm = quiet(glow(block(Vector3.new(0.2, 0.2, 0.2), mid, P.heat, m), 1))
	warm.Name = "Warmth"
	light(warm, P.heat, 10, 0.8)
	sparkles(m, Vector3.new(2.6, 0.4, 2.6), mid * CFrame.new(0, bagH / 2, 0), P.heat, 5, 1.6, 0.35)
	m:SetAttribute("HangAt", hang.Position)
	sealTarget(m, foot)
	targetBlock(f, foot * CFrame.new(0, 2, 0), Vector3.new(3, 4, 3))
end

-- ---------- 3. Glacier Fortress: a frozen waterfall behind the golem, spiked ice walls, crystal spires ----------
local function glacierFortress(f: Instance, at: CFrame, i: number)
	local P = TT.stations.golem
	pad(f, at, P.floor, P.tile, P.wallDark, Enum.Material.SmoothPlastic, "grid")
	local tz = T.targetZ
	-- the frost carpet with silver edges, from the open side to the golem
	local cz0, cz1 = -D / 2 + 0.3, tz - 1.6
	local cl = cz1 - cz0
	quiet(block(Vector3.new(3.4, 0.08, cl), at * CFrame.new(0, H + 0.05, (cz0 + cz1) / 2), P.carpet, f, false, Enum.Material.Fabric))
	for _, s in { -1, 1 } do
		quiet(block(Vector3.new(0.22, 0.1, cl), at * CFrame.new(s * 1.8, H + 0.06, (cz0 + cz1) / 2), P.silver, f))
	end
	-- ice walls down both sides, a silver rim and a row of ice spikes on top
	for _, s in { -1, 1 } do
		local len = 8.1
		local cf = at * CFrame.new(s * (W / 2 - 0.5), 0, -0.15)
		block(Vector3.new(1, 2.2, len), cf * CFrame.new(0, H + 1.1, 0), P.wall, f, true, Enum.Material.Ice)
		quiet(block(Vector3.new(1.15, 0.35, len), cf * CFrame.new(0, H + 0.17, 0), P.wallDark, f))
		quiet(block(Vector3.new(1.12, 0.18, len), cf * CFrame.new(0, H + 2.2, 0), P.silver, f))
		local spikes = 6
		for k = 0, spikes - 1 do
			local h = if k % 2 == 0 then 1.7 else 1.1
			shape("Cone", Vector3.new(0.85, h, 0.85), cf * CFrame.new(0, H + 2.25 + h / 2, -len / 2 + (k + 0.5) * len / spikes), P.crystal, f)
		end
	end
	-- crystal spires in the back corners: a glowing core in a clear crystal, two smaller ones, a rock foot
	for _, s in { -1, 1 } do
		local c = at * CFrame.new(s * (W / 2 - 1.0), H, D / 2 - 1.0)
		shape("Rock", Vector3.new(2.6, 1.3, 2.4), c * CFrame.new(0, 0.4, 0), P.cliff, f).CanCollide = true
		local main = c * CFrame.new(0, 4.3, 0) * CFrame.Angles(0, 0, -s * 0.1)
		local outer = shape("Octa", Vector3.new(1.7, 8, 1.7), main, P.crystal, f)
		outer.Transparency = 0.45
		quiet(glow(shape("Octa", Vector3.new(0.7, 6, 0.7), main, P.crystalCore, f), 0.1))
		shape("Octa", Vector3.new(1.1, 4.6, 1.1), c * CFrame.new(-s * 0.9, 2.4, -0.4) * CFrame.Angles(0.15, 0, s * 0.2), P.crystal, f)
		shape("Octa", Vector3.new(0.9, 3.2, 0.9), c * CFrame.new(s * 0.5, 1.7, -1.0) * CFrame.Angles(-0.35, 0, -s * 0.2), P.wall, f)
	end
	-- the frozen waterfall behind the golem: ice columns from a snowy cliff lip, frozen ripples,
	-- icicles, shimmering light running in it, and a frozen pool at its foot
	local wf = at * CFrame.new(0, H, D / 2 - 0.35)
	local top = 10
	for k = -2, 2 do
		block(Vector3.new(1.3, top, 0.6 + (k % 2) * 0.15), wf * CFrame.new(k * 1.22, top / 2, 0), if k % 2 == 0 then P.fall else P.fallLight, f, true, Enum.Material.Ice)
	end
	for _, b in { { -2.3, 2.2 }, { -1.1, 5.6 }, { 0.1, 3.4 }, { 1.3, 7.1 }, { 2.4, 4.4 }, { -0.5, 8.2 }, { 0.9, 1.4 }, { -1.9, 6.9 }, { 2.1, 8.6 } } do
		quiet(ellipsoid(Vector3.new(1.1, 1.8, 0.5), wf * CFrame.new(b[1], b[2], -0.4), P.fallLight, f))
	end
	for k, x in { -2.4, -1.2, 0.1, 1.3, 2.4 } do
		local cf = wf * CFrame.new(x, 4 + (k % 3) * 1.6, -0.44)
		quiet(glow(block(Vector3.new(0.22, 3.2, 0.08), cf, P.crystalCore, bobber(f, cf, 1.4, 0.18, k / 5)), 0.1))
	end
	-- the cliff behind it, so the plaza side reads as rock and ice too
	for k, c in { { -2.2, 2.2, 3.2 }, { 1.9, 3.0, 3.6 }, { -1.4, 6.3, 3.0 }, { 1.6, 7.2, 2.8 }, { 0, 4.6, 3.4 } } do
		shape("Rock", Vector3.new(c[3], c[3] * 1.1, 1.6), wf * CFrame.new(c[1], c[2], 0.75) * CFrame.Angles(0, k * 0.7, 0), P.cliff, f)
	end
	quiet(ellipsoid(Vector3.new(7, 0.8, 1.6), wf * CFrame.new(0, 0.05, -0.6), P.fallLight, f))
	for k, x in { -2.6, 0, 2.6 } do
		local lift = (k % 2) * 0.3
		shape("Rock", Vector3.new(3.2, 2.2, 2.4), wf * CFrame.new(x, top + 0.6 + lift, 0.2) * CFrame.Angles(0, k, 0), P.cliff, f)
		quiet(ellipsoid(Vector3.new(3, 0.7, 2.2), wf * CFrame.new(x, top + 1.65 + lift, 0.2), P.cliffSnow, f))
	end
	for k = 0, 8 do
		local h = 0.9 + ((k * 7) % 5) * 0.25
		quiet(shape("Cone", Vector3.new(0.38, h, 0.38), wf * CFrame.new(-3.2 + k * 0.8, top - 0.45 - h / 2, -0.75) * CFrame.Angles(math.pi, 0, 0), P.icicle, f))
	end
	-- braziers at the open side's corners: ice pillars, silver bowls, cold blue flames
	for _, s in { -1, 1 } do
		local b = at * CFrame.new(s * (W / 2 - 0.9), 0, -D / 2 + 0.9)
		block(Vector3.new(1.6, 3, 1.6), b * CFrame.new(0, H + 1.5, 0), P.wall, f, true, Enum.Material.Ice)
		quiet(block(Vector3.new(1.8, 0.3, 1.8), b * CFrame.new(0, H + 0.15, 0), P.wallDark, f))
		cyl(1.05, 0.6, b * CFrame.new(0, H + 3.3, 0), P.silver, f)
		local flame = glow(shape("Octa", Vector3.new(0.95, 1.9, 0.95), b * CFrame.new(0, H + 4.35, 0), P.flame, f), 0.05)
		light(flame, P.flame, 12, 0.9)
		sparkles(f, Vector3.new(1, 0.4, 1), b * CFrame.new(0, H + 3.9, 0), P.flame, 6, 2.4, 0.3)
	end
	-- crystals floating over the spires and the cliff
	for k, c in { { -(W / 2 - 1), 9.8, D / 2 - 1 }, { W / 2 - 1, 10.4, D / 2 - 1 }, { 0, top + 3.2, D / 2 - 0.2 } } do
		local cf = at * CFrame.new(c[1], H + c[2], c[3])
		quiet(glow(shape("Octa", Vector3.new(0.7, 1.4, 0.7), cf, P.crystal, bobber(f, cf, 0.35, 0.35, k / 3)), 0.15))
	end

	-- the Magma Golem: chunky rock with glowing magma cracks, a magma heart and bright eyes
	local foot = at * CFrame.new(0, H, tz)
	local m = target(f, i)
	for _, s in { -1, 1 } do
		block(Vector3.new(1.5, 2.4, 1.7), foot * CFrame.new(s * 1, 1.2, 0), P.rock, m, false, Enum.Material.Slate)
		named(quiet(glow(block(Vector3.new(0.16, 1.1, 0.1), foot * CFrame.new(s * 1.1, 1.3, -0.86) * CFrame.Angles(0, 0, s * 0.35), P.magma, m))), "Heat")
	end
	block(Vector3.new(3.6, 1.2, 2.2), foot * CFrame.new(0, 2.95, 0), P.rock, m, false, Enum.Material.Slate)
	local torso = foot * CFrame.new(0, 5.05, 0) * CFrame.Angles(0.06, 0, 0)
	block(Vector3.new(4.4, 3.2, 2.8), torso, P.rockLight, m, false, Enum.Material.Slate)
	local heart = named(glow(shape("Octa", Vector3.new(1.2, 1.6, 1.2), torso * CFrame.new(0, 0.1, -1.38), P.magma, m)), "Heat")
	light(heart, P.magma, 12, 1.1)
	for _, c in { { -1.3, 0.7, 0.5 }, { -1.1, -0.6, -0.4 }, { 1.2, 0.6, -0.55 }, { 1.4, -0.7, 0.35 } } do
		named(quiet(glow(block(Vector3.new(0.16, 1.2, 0.1), torso * CFrame.new(c[1], c[2], -1.42) * CFrame.Angles(0, 0, c[3]), P.magma, m))), "Heat")
	end
	for _, s in { -1, 1 } do
		shape("Rock", Vector3.new(2.3, 2, 2.3), foot * CFrame.new(s * 2.9, 6.3, 0), P.rock, m)
		block(Vector3.new(1.3, 2.4, 1.4), foot * CFrame.new(s * 3.1, 4.6, 0), P.rock, m, false, Enum.Material.Slate)
		shape("Rock", Vector3.new(1.9, 1.7, 1.9), foot * CFrame.new(s * 3.2, 3.05, -0.2), P.rockLight, m)
	end
	local head = foot * CFrame.new(0, 7.55, -0.15)
	block(Vector3.new(2.2, 1.8, 2), head, P.rock, m, false, Enum.Material.Slate)
	block(Vector3.new(2.5, 0.4, 0.5), head * CFrame.new(0, 0.55, -0.9), P.rockLight, m, false, Enum.Material.Slate)
	for _, s in { -1, 1 } do
		named(quiet(glow(block(Vector3.new(0.5, 0.32, 0.1), head * CFrame.new(s * 0.48, 0.05, -1.02), P.eyes, m))), "Eye")
	end
	sparkles(m, Vector3.new(4.4, 0.4, 2.4), foot * CFrame.new(0, 7.2, 0), P.magma, 6, 1.8, 0.3)
	sealTarget(m, foot)
	targetBlock(f, foot * CFrame.new(0, 4, 0), Vector3.new(5, 8, 3))
end

-- ---------- 4. Aurora Wolf Shrine: a neon wolf-head gate round the sun, pagodas, aurora trees and ribbons ----------
local function auroraShrine(f: Instance, at: CFrame, i: number)
	local P = TT.stations.sun
	pad(f, at, P.floor, P.tile, P.pylon, Enum.Material.SmoothPlastic, "checker")
	local tz = T.targetZ
	-- neon strips round the deck's edge
	for _, s in { -1, 1 } do
		quiet(glow(block(Vector3.new(0.25, 0.06, D - 0.6), at * CFrame.new(s * (W / 2 - 0.3), H + 0.03, 0), P.neon, f)))
		quiet(glow(block(Vector3.new(W - 0.6, 0.06, 0.25), at * CFrame.new(0, H + 0.03, s * (D / 2 - 0.3)), P.neon, f)))
	end
	-- a glowing path of diamonds from the open side to the emitter, violet and ice in turn
	for k = 0, 4 do
		local z = -D / 2 + 0.9 + k * 1.25
		quiet(glow(block(Vector3.new(0.7, 0.04, 0.7), at * CFrame.new(0, H + 0.05, z) * CFrame.Angles(0, math.pi / 4, 0), if k % 2 == 0 then P.neonAlt else P.neon, f), 0.1))
		for _, s in { -1, 1 } do
			quiet(glow(block(Vector3.new(0.35, 0.04, 0.35), at * CFrame.new(s * 1.1, H + 0.05, z) * CFrame.Angles(0, math.pi / 4, 0), P.neon, f), 0.3))
		end
	end
	-- the gate behind the sun: two pillars with neon edges and lit windows, a neon double arch round the
	-- opening, a violet veil in it (the sun pops against it), and the lintel
	local gz = D / 2 + 0.1
	local g = at * CFrame.new(0, 0, gz) -- on the ground: the pillars stand past the pad's back edge
	local gx = 4.45
	for _, s in { -1, 1 } do
		local p = g * CFrame.new(s * gx, 0, 0)
		block(Vector3.new(1.7, H + 0.6, 1.7), p * CFrame.new(0, (H + 0.6) / 2, 0), P.trim, f, true)
		block(Vector3.new(1.3, H + 9.2, 1.3), p * CFrame.new(0, (H + 9.2) / 2, 0), P.wolf, f, true)
		block(Vector3.new(1.6, 0.4, 1.6), p * CFrame.new(0, H + 9.0, 0), P.trim, f)
		quiet(glow(block(Vector3.new(0.14, 8.4, 0.14), p * CFrame.new(-s * 0.62, H + 4.6, -0.62), P.neon, f)))
		quiet(glow(block(Vector3.new(0.14, 8.4, 0.14), p * CFrame.new(s * 0.62, H + 4.6, -0.62), P.neonAlt, f)))
		-- the plaza sees the back: neon on its back edges too
		quiet(glow(block(Vector3.new(0.14, 8.4, 0.14), p * CFrame.new(-s * 0.62, H + 4.6, 0.62), P.neonAlt, f)))
		quiet(glow(block(Vector3.new(0.14, 8.4, 0.14), p * CFrame.new(s * 0.62, H + 4.6, 0.62), P.neon, f)))
		for k = 0, 2 do
			quiet(glow(block(Vector3.new(0.5, 0.7, 0.08), p * CFrame.new(0, H + 2.2 + k * 2.2, -0.66), P.pink, f), 0.15))
		end
	end
	local opening = 2 * (gx - 0.65)
	quiet(glow(shape("Arch", Vector3.new(opening, 4, 0.3), g * CFrame.new(0, H + 7.2, -0.7), P.neon, f)))
	quiet(glow(shape("Arch", Vector3.new(opening - 0.9, 3.5, 0.25), g * CFrame.new(0, H + 6.95, -0.66), P.neonAlt, f)))
	for _, s in { -1, 1 } do
		quiet(glow(block(Vector3.new(0.2, 5.2, 0.2), g * CFrame.new(s * (opening / 2 - 0.1), H + 2.6, -0.7), P.neon, f)))
	end
	local veil = quiet(block(Vector3.new(opening, 9.2, 0.1), g * CFrame.new(0, H + 4.6, 0.5), P.veil, f))
	veil.Transparency = 0.25
	block(Vector3.new(10.8, 1, 1.7), g * CFrame.new(0, H + 9.7, 0), P.wolfLight, f)
	quiet(glow(block(Vector3.new(10.4, 0.12, 0.12), g * CFrame.new(0, H + 9.22, -0.86), P.neonAlt, f)))
	quiet(block(Vector3.new(11, 0.3, 1.9), g * CFrame.new(0, H + 10.25, 0), P.trim, f))
	-- the wolf's head on the lintel: ears with glowing insides and frosted tips, fur ruffs, a snout, a
	-- forehead gem and glowing ice eyes, neon along its jaw and crown
	local head = g * CFrame.new(0, H + 12.2, 0)
	block(Vector3.new(7.4, 3.6, 2.4), head, P.wolf, f)
	block(Vector3.new(5.6, 1.1, 2.2), head * CFrame.new(0, 2.3, 0.1), P.wolf, f)
	quiet(ellipsoid(Vector3.new(5, 0.5, 2), head * CFrame.new(0, 2.95, 0.1), P.wolfSnow, f))
	for _, s in { -1, 1 } do
		local ear = head * CFrame.new(s * 2.5, 3.9, 0) * CFrame.Angles(0, 0, -s * 0.22)
		shape("Cone", Vector3.new(2.6, 3.8, 1.5), ear, P.wolf, f)
		quiet(glow(shape("Cone", Vector3.new(1.3, 2.3, 0.3), ear * CFrame.new(0, -0.35, -0.55) * CFrame.Angles(0.22, 0, 0), P.neonAlt, f), 0.05))
		quiet(shape("Cone", Vector3.new(0.9, 1.1, 1.55), ear * CFrame.new(0, 1.4, 0), P.wolfSnow, f))
		for k, c in { { 4.1, -0.6, 2.2 }, { 3.9, -1.7, 1.6 } } do
			shape("Cone", Vector3.new(1.3, c[3], 1.2), head * CFrame.new(s * c[1], c[2], 0) * CFrame.Angles(0, 0, -s * (math.pi / 2 + 0.35)), if k == 1 then P.wolfLight else P.wolf, f)
		end
		quiet(block(Vector3.new(1.5, 0.3, 0.4), head * CFrame.new(s * 2.0, 1.25, -1.3) * CFrame.Angles(0, 0, s * 0.3), P.wolfLight, f))
	end
	local snout = head * CFrame.new(0, -0.6, -1.9)
	block(Vector3.new(2.6, 1.6, 1.6), snout, P.wolfLight, f)
	wedge(Vector3.new(2.6, 1.1, 1.8), head * CFrame.new(0, 0.75, -2.0), P.wolf, f)
	block(Vector3.new(1.0, 0.6, 0.5), snout * CFrame.new(0, 0.55, -0.85), P.roof, f)
	quiet(block(Vector3.new(2.2, 0.35, 1.2), snout * CFrame.new(0, -0.95, 0.1), P.wolfSnow, f))
	local eyes: BasePart? = nil
	for _, s in { -1, 1 } do
		eyes = named(quiet(glow(block(Vector3.new(1.2, 0.55, 0.12), head * CFrame.new(s * 2.0, 0.7, -1.24) * CFrame.Angles(0, 0, s * 0.22), P.eye, f))), "WolfEye")
	end
	if eyes then
		light(eyes, P.eye, 14, 1)
	end
	quiet(glow(shape("Octa", Vector3.new(0.7, 1.1, 0.4), head * CFrame.new(0, 2.2, -1.2), P.neon, f)))
	quiet(glow(block(Vector3.new(7.2, 0.12, 0.12), head * CFrame.new(0, -1.8, -1.22), P.neonAlt, f)))
	quiet(glow(block(Vector3.new(5.4, 0.12, 0.12), head * CFrame.new(0, 2.85, -1.02), P.neon, f)))
	-- the back of the head (the plaza's side): neon jaw and crown lines, a big snowflake, the lintel's edge
	quiet(glow(block(Vector3.new(7.2, 0.12, 0.12), head * CFrame.new(0, -1.8, 1.22), P.neonAlt, f)))
	quiet(glow(block(Vector3.new(5.4, 0.12, 0.12), head * CFrame.new(0, 2.85, 1.22), P.neon, f)))
	quiet(glow(block(Vector3.new(10.4, 0.12, 0.12), g * CFrame.new(0, H + 9.22, 0.86), P.neonAlt, f)))
	for k = 0, 2 do
		quiet(glow(block(Vector3.new(0.22, 2.6, 0.1), head * CFrame.new(0, 0.2, 1.24) * CFrame.Angles(0, 0, k * math.pi / 3), P.neon, f)))
	end
	-- ice crystals circling the head, and three aurora ribbons waving over it
	local orbit = spinner(f, head, Vector3.new(0, 1, 0), 0.5)
	for k = 0, 3 do
		quiet(glow(shape("Octa", Vector3.new(0.6, 1.2, 0.6), head * CFrame.Angles(0, k * math.pi / 2, 0) * CFrame.new(0, 1.5 + (k % 2) * 0.8, 5), P.neon, orbit), 0.2))
	end
	for k, c in { { P.aurora, 19.2 }, { P.neon, 20.2 }, { P.neonAlt, 21.2 } } do
		local band = g * CFrame.new(0, H + c[2], 0.6)
		local mo = bobber(f, band, 0.45, 0.22, k / 3)
		local prev: Vector3? = nil
		for j = 0, 7 do
			local pt = Vector3.new(-5.6 + j * 1.6, math.sin(j * 0.9 + k * 1.3) * 0.6, 0)
			if prev then
				local a, b = band * prev, band * pt
				quiet(glow(block(Vector3.new((b - a).Magnitude + 0.1, 0.9, 0.08), CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, math.pi / 2, 0), c[1], mo), 0.45))
			end
			prev = pt
		end
	end
	-- pagodas in the front corners: three stacked rooms with lit windows, snowy roofs with neon eaves,
	-- a spire with a glowing crystal
	for _, s in { -1, 1 } do
		local b = at * CFrame.new(s * (W / 2 - 0.95), H, -D / 2 + 0.95)
		local y = 0
		for k = 0, 2 do
			local w = 1.5 - k * 0.3
			local bh = 1.4 - k * 0.2
			local lit = if k % 2 == 0 then P.pink else P.neon
			block(Vector3.new(w, bh, w), b * CFrame.new(0, y + bh / 2, 0), P.wolf, f, k == 0)
			quiet(glow(block(Vector3.new(w * 0.45, bh * 0.5, 0.06), b * CFrame.new(0, y + bh / 2, -w / 2 - 0.02), lit, f), 0.1))
			quiet(glow(block(Vector3.new(0.06, bh * 0.5, w * 0.45), b * CFrame.new(-s * (w / 2 + 0.02), y + bh / 2, 0), lit, f), 0.1))
			y += bh
			local rw = w + 1.3
			shape("Cone", Vector3.new(rw, 0.75, rw), b * CFrame.new(0, y + 0.3, 0), P.roof, f)
			quiet(glow(shape("Ring", Vector3.new(rw - 0.1, 0.12, rw - 0.1), b * CFrame.new(0, y, 0), if k % 2 == 0 then P.neon else P.neonAlt, f)))
			quiet(shape("Cone", Vector3.new(rw * 0.55, 0.4, rw * 0.55), b * CFrame.new(0, y + 0.5, 0), P.wolfSnow, f))
			y += 0.55
		end
		cyl(0.1, 1.4, b * CFrame.new(0, y + 0.7, 0), P.trim, f)
		quiet(glow(shape("Octa", Vector3.new(0.5, 0.9, 0.5), b * CFrame.new(0, y + 1.6, 0), P.neon, f)))
	end
	-- aurora trees halfway down the sides, glowing petals drifting off them, and low neon-topped rails
	for _, s in { -1, 1 } do
		local t = at * CFrame.new(s * (W / 2 - 0.65), H, 0.9)
		blossomTree(f, t, 6.4, s, P.trunk, { P.neonAlt, P.pink, P.bloomBlue, P.neonAlt }, true)
		flakes(f, Vector3.new(3, 0.3, 3), t * CFrame.new(s * 0.6, 6, 0), P.pink, P.neonAlt, 3, 0.2, 6)
		local r = at * CFrame.new(s * (W / 2 - 0.2), H, 0.4)
		block(Vector3.new(0.3, 0.9, 8.4), r * CFrame.new(0, 0.45, 0), P.wolf, f, true)
		quiet(glow(block(Vector3.new(0.34, 0.1, 8.4), r * CFrame.new(0, 0.95, 0), P.neon, f)))
	end
	-- the emitter the sun floats over
	local base = at * CFrame.new(0, H, tz)
	cyl(2.6, 0.7, base * CFrame.new(0, 0.35, 0), P.trim, f, true)
	quiet(cyl(1.9, 0.22, base * CFrame.new(0, 0.8, 0), P.pylon, f))
	quiet(glow(shape("Ring", Vector3.new(6.2, 0.22, 6.2), base * CFrame.new(0, 0.74, 0), P.neon, f), 0.05))
	for k = 0, 2 do
		local a = k * math.pi * 2 / 3
		local arm = base * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, 2.2)
		block(Vector3.new(0.45, 2.6, 0.45), arm * CFrame.new(0, 1.9, 0) * CFrame.Angles(-0.35, 0, 0), P.pylon, f)
		quiet(glow(block(Vector3.new(0.5, 0.5, 0.5), arm * CFrame.new(0, 3.2, -0.45), P.neon, f)))
	end
	-- two gyro rings turning round the sun (MapController spins them)
	local sunAt = base * CFrame.new(0, 5.6, 0)
	local gyro = spinner(f, sunAt, Vector3.new(0, 1, 0), 0.7)
	quiet(glow(shape("Ring", Vector3.new(6.4, 0.3, 6.4), sunAt * CFrame.Angles(math.pi / 2, 0, 0), P.ring, gyro), 0.1))
	quiet(glow(shape("Ring", Vector3.new(5.6, 0.26, 5.6), sunAt * CFrame.Angles(math.pi / 2, math.pi / 2, 0.5), P.neon, gyro), 0.1))
	-- the Little Sun: a glowing core in a soft corona, with rays round it (it cools to ice as you shoot it)
	local foot = base
	local m = target(f, i)
	local core = named(glow(ball(1.8, sunAt.Position, P.core, m)), "Heat")
	named(glow(ball(2.35, sunAt.Position, P.corona, m), 0.7), "Heat")
	for k = 0, 7 do
		local a = k * math.pi / 4
		named(quiet(glow(shape("Octa", Vector3.new(0.5, 1.1, 0.5), sunAt * CFrame.Angles(0, 0, a) * CFrame.new(0, 2.75, 0), P.ring, m))), "Heat")
	end
	light(core, P.core, 18, 1.4)
	sparkles(m, Vector3.new(3, 3, 3), sunAt, P.ring, 8, 1.4, 0.35)
	sealTarget(m, foot)
	targetBlock(f, foot * CFrame.new(0, 2.5, 0), Vector3.new(4.6, 5, 4.6))
end

local BUILDERS: { [string]: (Instance, CFrame, number) -> () } = {
	snowman = iglooCamp,
	heatbag = frostDojo,
	golem = glacierFortress,
	sun = auroraShrine,
}

-- pan `plot`'s trainer at level `tier` (Config.training.stations), as one folder in `parent`
function TrainingArt.build(parent: Instance, plot: number, tier: number): Folder
	meshes = ReplicatedStorage:FindFirstChild("SceneryMeshes")
	local f = Instance.new("Folder")
	f.Name = "Trainer" .. plot
	f:SetAttribute("Plot", plot)
	f:SetAttribute("Tier", tier)
	local s = T.stations[tier] or T.stations[1]
	local build = BUILDERS[s.kind]
	if build then
		build(f, Config.trainerFrame(plot), plot)
	end
	f.Parent = parent
	return f
end

return TrainingArt
