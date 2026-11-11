--!strict
-- TrainingArt: builds a pan's Cold Power trainer (owner 2026-11-10; replaces the sky rink and its door).
-- A raised stage in front of the pan, right of its door, the open side toward the pan, and a warm target
-- on the plaza side that the client frosts over as you shoot it (local +Z, Config.trainerFrame).
--
-- Look v2 (owner 2026-11-12: "study the reference better... polished... more in theme"). The reference is a
-- neon shrine: dark blocks with a neon line on every edge, one accent colour for small glows, perfect mirror
-- symmetry, one big gate as the centrepiece, a matching pair of trees, a lantern avenue and a glowing path
-- leading in. So every level is the same kit in its own three colours (Theme.training.stations):
--   a stepped dark stage with neon edges, a runway with snowflake glyphs to a ring under the target, two
--   pairs of lanterns, a doorway panel behind the target, snow caps on top surfaces, a pair of flankers
--   behind the gate's shoulders, and the gate itself, which is the level's identity (round -> pointy):
--   1 Frost Arch (snowman): ice-block arch on two pillars, snowflake keystone, snowy pines
--   2 Frost Torii (heat bag): the bag hangs from the torii's lower beam, frost-blossom trees
--   3 Crystal Citadel (golem): crystal-tipped obelisks, a snowy pediment, a pale ice doorway, crystal clusters
--   4 Aurora Wolf Gate (sun): a neon wolf head on the lintel, aurora trees, floating crystals
-- Same stage, stand spot and target spot on every level, so the lock and the bolts never change.
-- TrainingService builds each pan's trainer at its owner's level and rebuilds it on an upgrade.
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

-- the kit's fixed layout (studs, local to the stage's middle on the ground; +Z toward the plaza)
local LINE = 0.14 -- neon edge thickness
local GX, GZ = 4.3, 5.9 -- the gate's pillars: their middles at x = +-GX, z = GZ (1.2 square)
local PANEL_Z = 6.6 -- the doorway panel behind the target (clear of the sun's gyro rings)
local LANTERNS = { { 4.6, -4.7 }, { 4.6, -1.4 } } -- each mirrored to -x
local FLANK = { x = 5.5, z = 6.6 } -- the flankers behind the gate's shoulders, mirrored

type Palette = { [string]: Color3 }

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
local function wedge(size: Vector3, cf: CFrame, color: Color3, parent: Instance, collide: boolean?): BasePart
	local p = Instance.new("WedgePart")
	p.Size = size
	p.CFrame = cf
	p.Material = Enum.Material.SmoothPlastic
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

-- a cylinder lying along cf's X axis (a disc facing X)
local function rod(length: number, radius: number, cf: CFrame, color: Color3, parent: Instance): BasePart
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Cylinder
	p.Size = Vector3.new(length, radius * 2, radius * 2)
	p.CFrame = cf
	p.Material = Enum.Material.SmoothPlastic
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

-- glints drifting out of an invisible box (heat off a target)
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

-- a gentle snowfall over the whole trainer
local function snowfall(parent: Instance, at: CFrame)
	local p = quiet(block(Vector3.new(W + 2, 0.4, D + 2), at * CFrame.new(0, H + 14, 0), Theme.white, parent))
	p.Name = "Snowfall"
	p.Transparency = 1
	p.CanQuery = false
	local e = Instance.new("ParticleEmitter")
	e.Shape = Enum.ParticleEmitterShape.Box
	e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	e.Color = ColorSequence.new(Theme.white)
	e.LightEmission = 0.3
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.1, 0.22), NumberSequenceKeypoint.new(0.9, 0.22), NumberSequenceKeypoint.new(1, 0) })
	e.Speed = NumberRange.new(1.8, 2.4)
	e.Lifetime = NumberRange.new(6, 7.5)
	e.Rate = 4
	e.SpreadAngle = Vector2.new(15, 15)
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

-- ---------- the kit ----------
-- a neon line from a to b (world points; never straight up: use edgeFrame for upright edges)
local function line(f: Instance, a: Vector3, b: Vector3, color: Color3)
	quiet(glow(block(Vector3.new((b - a).Magnitude + LINE, LINE, LINE), CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, math.pi / 2, 0), color, f)))
end

-- neon on the four edges of a block's front face (local -Z), and its back face too when `back`
local function edgeFrame(f: Instance, cf: CFrame, size: Vector3, color: Color3, back: boolean?)
	for _, side in (if back then { -1, 1 } else { -1 }) do
		local z = side * size.Z / 2
		for _, s in { -1, 1 } do
			quiet(glow(block(Vector3.new(LINE, size.Y + LINE, LINE), cf * CFrame.new(s * size.X / 2, 0, z), color, f)))
			quiet(glow(block(Vector3.new(size.X + LINE, LINE, LINE), cf * CFrame.new(0, s * size.Y / 2, z), color, f)))
		end
	end
end

-- a neon half circle of radius r in cf's XY plane, its ends on cf's X axis
local function arcLine(f: Instance, cf: CFrame, r: number, n: number, color: Color3)
	local chord = 2 * r * math.sin(math.pi / (2 * n)) + LINE
	for k = 0, n - 1 do
		local a = (k + 0.5) * math.pi / n
		quiet(glow(block(Vector3.new(chord, LINE, LINE), cf * CFrame.new(r * math.cos(a), r * math.sin(a), 0) * CFrame.Angles(0, 0, a + math.pi / 2), color, f)))
	end
end

-- a flat slab of snow on a top surface (cf = the surface's middle)
local function snowCap(f: Instance, cf: CFrame, sx: number, sz: number, color: Color3)
	quiet(block(Vector3.new(sx + 0.2, 0.3, sz + 0.2), cf * CFrame.new(0, 0.15, 0), color, f))
end

-- a six-armed snowflake facing cf's -Z, `size` studs across, every arm tipped with a V
local function flake(f: Instance, cf: CFrame, size: number, color: Color3)
	local bar = math.max(0.1, size * 0.08)
	for k = 0, 2 do
		quiet(glow(block(Vector3.new(bar, size, 0.06), cf * CFrame.Angles(0, 0, k * math.pi / 3), color, f)))
	end
	for k = 0, 5 do
		local tip = cf * CFrame.Angles(0, 0, k * math.pi / 3) * CFrame.new(0, size * 0.3, 0)
		for _, s in { -1, 1 } do
			quiet(glow(block(Vector3.new(bar * 0.8, size * 0.2, 0.06), tip * CFrame.Angles(0, 0, s * 0.8) * CFrame.new(0, size * 0.08, 0), color, f)))
		end
	end
end

-- a three-bar snowflake lying on the floor (cf on the floor)
local function floorFlake(f: Instance, cf: CFrame, size: number, color: Color3)
	for k = 0, 2 do
		quiet(glow(block(Vector3.new(0.14, 0.04, size), cf * CFrame.Angles(0, k * math.pi / 3, 0), color, f)))
	end
end

-- a round badge facing cf's -Z: a dark disc, a neon rim, a snowflake
local function medallion(f: Instance, cf: CFrame, r: number, P: Palette)
	rod(0.24, r, cf * CFrame.Angles(0, math.pi / 2, 0), P.bodyDark, f)
	quiet(glow(rod(0.2, r + 0.12, cf * CFrame.new(0, 0, 0.04) * CFrame.Angles(0, math.pi / 2, 0), P.neon, f)))
	flake(f, cf * CFrame.new(0, 0, -0.14), r * 1.35, P.accent)
end

-- the stage: a dark lower step, the pad (you walk on it) with neon round its top edge, an inset floor
local function stage(f: Instance, at: CFrame, P: Palette)
	named(block(Vector3.new(W, H, D), at * CFrame.new(0, H / 2, 0), P.floor, f, true), "Pad")
	block(Vector3.new(W + 1, 0.4, D + 0.8), at * CFrame.new(0, 0.2, 0), P.bodyDark, f, true)
	quiet(block(Vector3.new(W - 1, 0.04, D - 1), at * CFrame.new(0, H + 0.02, 0), P.floorInner, f))
	for _, s in { -1, 1 } do
		quiet(glow(block(Vector3.new(LINE, LINE, D + LINE), at * CFrame.new(s * W / 2, H, 0), P.neon, f)))
		quiet(glow(block(Vector3.new(W + LINE, LINE, LINE), at * CFrame.new(0, H, s * D / 2), P.neon, f)))
	end
	quiet(glow(block(Vector3.new(W + 1 + LINE, LINE, LINE), at * CFrame.new(0, 0.4, -(D + 0.8) / 2), P.accent, f)))
end

-- the runway from the open side to z1, neon down both edges, snowflakes along it
local function runway(f: Instance, at: CFrame, P: Palette, z1: number)
	local z0 = -D / 2
	local len = z1 - z0
	quiet(block(Vector3.new(3, 0.06, len), at * CFrame.new(0, H + 0.05, z0 + len / 2), P.bodyDark, f))
	for _, s in { -1, 1 } do
		quiet(glow(block(Vector3.new(LINE, 0.08, len), at * CFrame.new(s * 1.5, H + 0.06, z0 + len / 2), P.neon, f)))
	end
	for _, z in { -4.7, -2.6, -0.5 } do
		if z < z1 - 0.8 then
			floorFlake(f, at * CFrame.new(0, H + 0.1, z), 1.5, P.accent)
		end
	end
end

-- a neon ring on the floor round the target's foot
local function targetRing(f: Instance, at: CFrame, P: Palette, r: number)
	quiet(glow(cyl(r + LINE, 0.04, at * CFrame.new(0, H + 0.06, T.targetZ), P.neon, f)))
	quiet(cyl(r, 0.05, at * CFrame.new(0, H + 0.075, T.targetZ), P.bodyDark, f))
end

-- a lantern on a post: a glowing cube in a dark frame, a snowy roof, a neon finial
local function lantern(f: Instance, base: CFrame, P: Palette)
	block(Vector3.new(0.9, 0.3, 0.9), base * CFrame.new(0, 0.15, 0), P.bodyDark, f, true)
	block(Vector3.new(0.3, 1.5, 0.3), base * CFrame.new(0, 1.05, 0), P.body, f, true)
	local box = base * CFrame.new(0, 2.2, 0)
	quiet(glow(block(Vector3.new(0.52, 0.62, 0.52), box, P.accent, f)))
	for _, cx in { -1, 1 } do
		for _, cz in { -1, 1 } do
			quiet(block(Vector3.new(0.12, 0.72, 0.12), box * CFrame.new(cx * 0.3, 0, cz * 0.3), P.body, f))
		end
	end
	quiet(block(Vector3.new(0.8, 0.12, 0.8), box * CFrame.new(0, -0.38, 0), P.bodyDark, f))
	quiet(block(Vector3.new(0.95, 0.18, 0.95), box * CFrame.new(0, 0.45, 0), P.bodyDark, f))
	snowCap(f, box * CFrame.new(0, 0.54, 0), 0.75, 0.75, P.snow)
	quiet(glow(block(Vector3.new(0.22, 0.22, 0.22), box * CFrame.new(0, 1.0, 0) * CFrame.Angles(0, math.pi / 4, math.pi / 4), P.neon, f)))
end

local function lanterns(f: Instance, at: CFrame, P: Palette)
	for _, s in { -1, 1 } do
		for _, l in LANTERNS do
			lantern(f, at * CFrame.new(s * l[1], H, l[2]), P)
		end
	end
end

-- one of the gate's pillars, from the ground to `top`: neon edges front and back, a lit slot, a dark foot,
-- and (when capped) a dark cap with snow
local function pillar(f: Instance, at: CFrame, x: number, top: number, P: Palette, capped: boolean, snowy: boolean?)
	local size = Vector3.new(1.2, top, 1.2)
	local cf = at * CFrame.new(x, top / 2, GZ)
	block(size, cf, P.body, f, true)
	edgeFrame(f, cf, size, P.neon, true)
	for _, side in { -1, 1 } do
		quiet(glow(block(Vector3.new(0.34, top * 0.4, 0.06), at * CFrame.new(x, top * 0.55, GZ + side * 0.61), P.accent, f), 0.1))
	end
	block(Vector3.new(1.6, 1.1, 1.6), at * CFrame.new(x, 0.55, GZ), P.bodyDark, f, true)
	if capped then
		block(Vector3.new(1.6, 0.4, 1.6), at * CFrame.new(x, top + 0.2, GZ), P.bodyDark, f)
		if snowy then
			snowCap(f, at * CFrame.new(x, top + 0.4, GZ), 1.6, 1.6, P.snow)
		end
	end
end

-- the dark doorway behind the target, from the ground to `top`, between the pillars
local function doorway(f: Instance, at: CFrame, top: number, color: Color3, transparency: number?): BasePart
	local p = quiet(block(Vector3.new(2 * (GX - 0.6) + 0.1, top, 0.12), at * CFrame.new(0, top / 2, PANEL_Z), color, f))
	p.Transparency = transparency or 0
	return p
end

-- a snowy pine: a trunk and three cone tiers, each with a snow cap
local function pine(f: Instance, base: CFrame, h: number, P: Palette)
	cyl(0.25 * h / 7, h * 0.24, base * CFrame.new(0, h * 0.12, 0), P.bodyDark, f, true)
	for k = 0, 2 do
		local w = h * (0.44 - k * 0.1)
		local ch = h * (0.4 - k * 0.06)
		local y = h * (0.18 + k * 0.22) + ch / 2
		shape("Cone", Vector3.new(w, ch, w), base * CFrame.new(0, y, 0), if k % 2 == 0 then P.pine else P.pineDark, f)
		quiet(shape("Cone", Vector3.new(w * 0.5 + 0.12, ch * 0.5 + 0.06, w * 0.5 + 0.12), base * CFrame.new(0, y + ch / 4 + 0.03, 0), P.snow, f))
	end
end

-- a tidy blossom tree: a straight trunk forking in two, a symmetric crown of puffs (some glowing when neon)
local PUFFS = { { 0, 0, 0, 1.3 }, { 1.15, -0.3, 0, 0.95 }, { -1.15, -0.3, 0, 0.95 }, { 0, 0.95, 0, 0.95 },
	{ 0.6, 0.25, -0.9, 0.85 }, { -0.6, 0.25, -0.9, 0.85 }, { 0, 0.15, 0.9, 0.9 } }
local function blossom(f: Instance, base: CFrame, h: number, trunk: Color3, a: Color3, b: Color3, neon: boolean)
	local k = h / 7
	cyl(0.26 * k, h * 0.6, base * CFrame.new(0, h * 0.3, 0), trunk, f, true)
	local crown = base * CFrame.new(0, h * 0.72, 0)
	for n, o in PUFFS do
		local p = quiet(ball(o[4] * k, (crown * CFrame.new(o[1] * k, o[2] * k, o[3] * k)).Position, if n == 1 or n == 4 then a else b, f))
		if neon and (n == 2 or n == 3 or n == 4) then
			glow(p, 0.3)
		end
	end
end

-- a crystal cluster: a tall clear crystal round a glowing core, two smaller ones leaning out, a dark foot
local function crystals(f: Instance, base: CFrame, h: number, s: number, P: Palette)
	cyl(1.1, 0.5, base * CFrame.new(0, 0.25, 0), P.bodyDark, f, true)
	local main = base * CFrame.new(0, h * 0.45, 0)
	local outer = shape("Octa", Vector3.new(1.3, h, 1.3), main, P.crystal, f)
	outer.Transparency = 0.35
	quiet(glow(shape("Octa", Vector3.new(0.5, h * 0.72, 0.5), main, P.accent, f), 0.1))
	shape("Octa", Vector3.new(0.9, h * 0.55, 0.9), base * CFrame.new(s * 0.8, h * 0.25, 0) * CFrame.Angles(0, 0, -s * 0.35), P.crystal, f)
	shape("Octa", Vector3.new(0.8, h * 0.45, 0.8), base * CFrame.new(-s * 0.3, h * 0.2, -0.75) * CFrame.Angles(-0.3, 0, 0), P.crystal, f)
end

-- two crystals floating over the flankers, bobbing out of step
local function floaters(f: Instance, at: CFrame, y: number, color: Color3)
	for k, s in { -1, 1 } do
		local cf = at * CFrame.new(s * FLANK.x, y, FLANK.z)
		quiet(glow(shape("Octa", Vector3.new(0.7, 1.4, 0.7), cf, color, bobber(f, cf, 0.35, 0.35, k / 2)), 0.1))
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

-- ---------- 1. Frost Arch: an ice-block arch on two pillars, a snowflake keystone, snowy pines ----------
local function frostArch(f: Instance, at: CFrame, i: number)
	local P = TT.stations.snowman
	local tz = T.targetZ
	stage(f, at, P)
	runway(f, at, P, tz - 2.4)
	targetRing(f, at, P, 2.4)
	lanterns(f, at, P)
	snowfall(f, at)
	local top = 6.6
	local spring = top + 0.4 -- where the arch springs from the pillar caps
	for _, s in { -1, 1 } do
		pillar(f, at, s * GX, top, P, true)
	end
	-- the doorway: a rectangle and a half disc under the arch
	doorway(f, at, spring, P.panel)
	rod(0.12, GX - 0.6, at * CFrame.new(0, spring, PANEL_Z + 0.03) * CFrame.Angles(0, math.pi / 2, 0), P.panel, f)
	-- the arch: seven ice blocks, two shades in turn, neon on its inner and outer curves, front and back
	local c = at * CFrame.new(0, spring, GZ)
	local n = 7
	local chord = 2 * (GX + 0.6) * math.sin(math.pi / (2 * n)) + 0.05
	for k = 0, n - 1 do
		local a = (k + 0.5) * math.pi / n
		local depth = if k % 2 == 0 then 1.3 else 1.16
		block(Vector3.new(chord, 1.2, depth), c * CFrame.new(GX * math.cos(a), GX * math.sin(a), 0) * CFrame.Angles(0, 0, a + math.pi / 2),
			if k % 2 == 0 then P.ice else P.iceShade, f, true)
	end
	for _, side in { -1, 1 } do
		arcLine(f, c * CFrame.new(0, 0, side * 0.66), GX + 0.62, 12, P.neon)
		arcLine(f, c * CFrame.new(0, 0, side * 0.66), GX - 0.62, 10, P.neon)
	end
	-- the keystone: a snowflake badge front and back, snow on top
	medallion(f, c * CFrame.new(0, GX, -0.72), 0.9, P)
	medallion(f, c * CFrame.new(0, GX, 0.72) * CFrame.Angles(0, math.pi, 0), 0.9, P)
	snowCap(f, c * CFrame.new(0, GX + 0.6, 0), 1.8, 1.3, P.snow)
	-- snowy pines behind the gate's shoulders
	for _, s in { -1, 1 } do
		pine(f, at * CFrame.new(s * FLANK.x, 0, FLANK.z + 0.3), 8.5, P)
	end

	-- the Snowman Dummy: a wooden stand, three snowballs, a bullseye on its chest, X eyes, a carrot,
	-- a red bucket hat with a gold band, a blue scarf and stick arms
	local foot = at * CFrame.new(0, H, tz)
	local m = target(f, i)
	cyl(1.7, 0.35, foot * CFrame.new(0, 0.175, 0), P.woodDark, m, false, Enum.Material.WoodPlanks)
	local by, my, hy = 2.15, 5.05, 7.15
	named(ball(2, (foot * CFrame.new(0, by, 0)).Position, P.snow, m), "Heat")
	named(ball(1.5, (foot * CFrame.new(0, my, 0)).Position, P.snow, m), "Heat")
	named(ball(1.05, (foot * CFrame.new(0, hy, 0)).Position, P.snow, m), "Heat")
	local face = CFrame.Angles(0, math.pi / 2, 0)
	for k, r in { 0.95, 0.66, 0.36 } do
		quiet(rod(0.08, r, foot * CFrame.new(0, my + 0.05, -1.28 - k * 0.05) * face, if k % 2 == 1 then P.ring else P.ringLight, m))
	end
	for _, s in { -1, 1 } do
		for _, a in { -0.78, 0.78 } do
			quiet(block(Vector3.new(0.13, 0.5, 0.13), foot * CFrame.new(s * 0.38, hy + 0.22, -0.92) * CFrame.Angles(0, 0, a), P.coal, m))
		end
	end
	for k = -2, 2 do
		quiet(ball(0.08, (foot * CFrame.new(k * 0.17, hy - 0.42 + math.abs(k) * 0.06, -0.93)).Position, P.coal, m))
	end
	quiet(shape("Cone", Vector3.new(0.34, 1, 0.34), foot * CFrame.new(0, hy - 0.05, -1.2) * CFrame.Angles(-math.pi / 2, 0, 0), P.carrot, m))
	local hat = foot * CFrame.new(0.1, hy + 0.85, 0) * CFrame.Angles(0, 0, -0.12)
	cyl(1.3, 0.14, hat, P.hat, m)
	cyl(0.86, 1, hat * CFrame.new(0, 0.55, 0), P.hat, m)
	quiet(cyl(0.88, 0.22, hat * CFrame.new(0, 0.25, 0), P.hatBand, m))
	cyl(1.12, 0.42, foot * CFrame.new(0, 6.35, 0) * CFrame.Angles(0.06, 0, 0), P.scarf, m)
	quiet(block(Vector3.new(0.5, 1.5, 0.16), foot * CFrame.new(0.65, 5.6, -1.2) * CFrame.Angles(0.2, 0, 0.12), P.scarf, m))
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

-- ---------- 2. Frost Torii: the heat bag hangs from the torii's lower beam, frost-blossom trees ----------
local function frostTorii(f: Instance, at: CFrame, i: number)
	local P = TT.stations.heatbag
	local tz = T.targetZ
	stage(f, at, P)
	runway(f, at, P, tz - 2.6)
	targetRing(f, at, P, 2.6)
	lanterns(f, at, P)
	snowfall(f, at)
	local nukiY = H + 8.2 -- the lower beam's middle: the bag hangs from its underside
	local top = H + 9.6 -- the pillars' top, under the top beam
	for _, s in { -1, 1 } do
		pillar(f, at, s * GX, top, P, false)
	end
	doorway(f, at, nukiY - 0.3, P.panel)
	-- the lower beam, neon edged
	local nuki = at * CFrame.new(0, nukiY, GZ)
	local nukiSize = Vector3.new(2 * GX + 2, 0.6, 0.8)
	block(nukiSize, nuki, P.body, f)
	edgeFrame(f, nuki, nukiSize, P.accent, true)
	-- the plaque between the beams, a snowflake on each face
	local plaque = at * CFrame.new(0, (nukiY + 0.3 + top) / 2, GZ)
	local plaqueSize = Vector3.new(1.3, top - nukiY - 0.3, 0.5)
	block(plaqueSize, plaque, P.bodyDark, f)
	edgeFrame(f, plaque, plaqueSize, P.neon, true)
	flake(f, plaque * CFrame.new(0, 0, -0.29), 0.8, P.accent)
	flake(f, plaque * CFrame.new(0, 0, 0.29) * CFrame.Angles(0, math.pi, 0), 0.8, P.accent)
	-- the top beam: a neon-edged beam, a wider dark cap with upswept ends, snow along it
	local kas = at * CFrame.new(0, top + 0.35, GZ)
	local kasSize = Vector3.new(2 * GX + 2.4, 0.7, 1.1)
	block(kasSize, kas, P.body, f)
	edgeFrame(f, kas, kasSize, P.neon, true)
	local capY = top + 0.85
	local capW = 2 * GX + 2.4
	block(Vector3.new(capW, 0.3, 1.4), at * CFrame.new(0, capY, GZ), P.bodyDark, f)
	for _, s in { -1, 1 } do
		local tilt = 0.3
		local x = s * (capW / 2 + 0.6 * math.cos(tilt))
		block(Vector3.new(1.2, 0.3, 1.4), at * CFrame.new(x, capY + 0.6 * math.sin(tilt), GZ) * CFrame.Angles(0, 0, s * tilt), P.bodyDark, f)
	end
	snowCap(f, at * CFrame.new(0, capY + 0.15, GZ), capW - 0.4, 1.2, P.snow)
	-- frost-blossom trees behind the gate's shoulders
	for _, s in { -1, 1 } do
		blossom(f, at * CFrame.new(s * FLANK.x, 0, FLANK.z + 0.3), 9.2, P.trunk, P.bloom, P.bloomTint, false)
	end

	-- the chain, link by link, from the lower beam to the bag's top
	local bagY, bagH = 4.6, 4.6
	local hangY = nukiY - 0.3 - H
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

-- ---------- 3. Crystal Citadel: crystal-tipped obelisks, a snowy pediment, a pale ice doorway ----------
local function crystalCitadel(f: Instance, at: CFrame, i: number)
	local P = TT.stations.golem
	local tz = T.targetZ
	stage(f, at, P)
	runway(f, at, P, tz - 2.4)
	targetRing(f, at, P, 2.4)
	lanterns(f, at, P)
	snowfall(f, at)
	local top = H + 9.4
	for _, s in { -1, 1 } do
		pillar(f, at, s * GX, top, P, true)
		-- a glowing crystal on each obelisk
		quiet(glow(shape("Octa", Vector3.new(1.1, 2.6, 1.1), at * CFrame.new(s * GX, top + 0.4 + 1.1, GZ), P.neon, f), 0.05))
	end
	-- the lintel between the obelisks, and the pediment on it
	local lintelY = top - 0.5
	local lintel = at * CFrame.new(0, lintelY, GZ)
	local lintelSize = Vector3.new(2 * (GX - 0.6), 1, 1.2)
	block(lintelSize, lintel, P.body, f)
	edgeFrame(f, lintel, lintelSize, P.neon, true)
	doorway(f, at, lintelY - 0.5, P.panel, 0.15)
	local half, rise = GX - 0.6, 2.6
	local baseY = lintelY + 0.5
	for _, s in { -1, 1 } do
		-- each half of the triangle is a ramp rising toward the middle
		wedge(Vector3.new(1.2, rise, half), at * CFrame.new(s * half / 2, baseY + rise / 2, GZ) * CFrame.Angles(0, -s * math.pi / 2, 0), P.body, f)
		local slope = math.atan2(rise, half)
		for _, side in { -1, 1 } do
			line(f, (at * CFrame.new(s * half, baseY, GZ + side * 0.62)).Position, (at * CFrame.new(0, baseY + rise, GZ + side * 0.62)).Position, P.neon)
		end
		-- snow along the slope
		local midCf = at * CFrame.new(s * half / 2, baseY + rise / 2, GZ) * CFrame.Angles(0, 0, -s * slope)
		quiet(block(Vector3.new(math.sqrt(half * half + rise * rise) + 0.2, 0.28, 1.4), midCf * CFrame.new(0, 0.16, 0), P.snow, f))
	end
	quiet(glow(shape("Octa", Vector3.new(1.0, 2.2, 1.0), at * CFrame.new(0, baseY + rise + 1.0, GZ), P.accent, f), 0.05))
	medallion(f, at * CFrame.new(0, baseY + 1.0, GZ - 0.72), 0.75, P)
	medallion(f, at * CFrame.new(0, baseY + 1.0, GZ + 0.72) * CFrame.Angles(0, math.pi, 0), 0.75, P)
	-- crystal clusters behind the gate's shoulders, and crystals floating over them
	for _, s in { -1, 1 } do
		crystals(f, at * CFrame.new(s * FLANK.x, 0, FLANK.z), 6, s, P)
	end
	floaters(f, at, H + 8.6, P.accent)

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

-- ---------- 4. Aurora Wolf Gate: a neon wolf head on the lintel, aurora trees, floating crystals ----------
local function auroraWolf(f: Instance, at: CFrame, i: number)
	local P = TT.stations.sun
	local tz = T.targetZ
	stage(f, at, P)
	runway(f, at, P, tz - 3.2)
	lanterns(f, at, P)
	snowfall(f, at)
	local top = H + 8.6
	for _, s in { -1, 1 } do
		pillar(f, at, s * GX, top, P, true)
	end
	-- the lintel on the pillar caps, and the violet veil under it
	local lintel = at * CFrame.new(0, top + 0.9, GZ)
	local lintelSize = Vector3.new(2 * GX + 2, 1, 1.5)
	block(lintelSize, lintel, P.body, f)
	edgeFrame(f, lintel, lintelSize, P.neon, true)
	doorway(f, at, top + 0.4, P.panel, 0.2)
	-- the wolf's head: a neon-edged head, a brow, triangle ears with glowing insides, fur ruffs, a snout,
	-- glowing ice eyes and a snowflake on the forehead (and a big one on the back, for the plaza)
	local hy = top + 1.4 -- the head's bottom
	local headSize = Vector3.new(7.2, 3.4, 2.2)
	local head = at * CFrame.new(0, hy + headSize.Y / 2, GZ)
	block(headSize, head, P.body, f)
	edgeFrame(f, head, headSize, P.neon, true)
	local browY = hy + headSize.Y + 0.4
	local brow = at * CFrame.new(0, browY, GZ)
	local browSize = Vector3.new(5.4, 0.8, 2.0)
	block(browSize, brow, P.wolfLight, f)
	edgeFrame(f, brow, browSize, P.neon)
	snowCap(f, at * CFrame.new(0, browY + 0.4, GZ), 5.4, 2.0, P.snow)
	local front = GZ - headSize.Z / 2
	local earBase, earH, earW = hy + headSize.Y, 3.4, 2.3
	for _, s in { -1, 1 } do
		-- the ear: a right triangle, its upright edge toward the middle
		local inner = s * 1.3
		wedge(Vector3.new(1.4, earH, earW), at * CFrame.new(inner + s * earW / 2, earBase + earH / 2, GZ) * CFrame.Angles(0, -s * math.pi / 2, 0), P.body, f)
		line(f, (at * CFrame.new(inner + s * earW, earBase, front + 0.25)).Position, (at * CFrame.new(inner, earBase + earH, front + 0.25)).Position, P.neon)
		quiet(glow(wedge(Vector3.new(0.12, 1.9, 1.3), at * CFrame.new(inner + s * (0.2 + 0.65), earBase + 0.8 + 0.95, front + 0.28) * CFrame.Angles(0, -s * math.pi / 2, 0), P.accent, f)))
		-- the fur ruff at the head's lower corner
		wedge(Vector3.new(1.4, 2.0, 1.3), at * CFrame.new(s * (headSize.X / 2 + 0.65), hy + 1.0, GZ) * CFrame.Angles(0, -s * math.pi / 2, 0), P.wolfLight, f)
		line(f, (at * CFrame.new(s * headSize.X / 2, hy + 2.0, front + 0.3)).Position, (at * CFrame.new(s * (headSize.X / 2 + 1.3), hy, front + 0.3)).Position, P.neon)
		-- the eye, slanted up toward the outside
		quiet(glow(block(Vector3.new(1.3, 0.45, 0.15), at * CFrame.new(s * 1.8, hy + 2.1, front - 0.05) * CFrame.Angles(0, 0, s * 0.2), P.eye, f)))
	end
	-- the snout, the bridge up to the brow, the nose
	local snout = at * CFrame.new(0, hy + 0.85, front - 0.75)
	local snoutSize = Vector3.new(2.4, 1.4, 1.5)
	block(snoutSize, snout, P.wolfLight, f)
	edgeFrame(f, snout, snoutSize, P.neon)
	wedge(Vector3.new(2.4, 1.0, 1.5), at * CFrame.new(0, hy + 2.05, front - 0.75), P.body, f)
	quiet(block(Vector3.new(0.9, 0.5, 0.35), at * CFrame.new(0, hy + 1.35, front - 1.55), P.bodyDark, f))
	medallion(f, at * CFrame.new(0, browY, GZ - 1.1), 0.5, P)
	flake(f, at * CFrame.new(0, hy + headSize.Y / 2, GZ + headSize.Z / 2 + 0.05) * CFrame.Angles(0, math.pi, 0), 2.4, P.accent)
	local eyeLight = quiet(block(Vector3.new(0.2, 0.2, 0.2), at * CFrame.new(0, hy + 2.1, front - 0.6), P.eye, f))
	eyeLight.Transparency = 1
	light(eyeLight, P.eye, 14, 0.9)
	-- aurora trees behind the gate's shoulders, crystals floating over them
	for _, s in { -1, 1 } do
		blossom(f, at * CFrame.new(s * FLANK.x, 0, FLANK.z + 0.3), 9.2, P.trunk, P.bloom, P.bloomTint, true)
	end
	floaters(f, at, H + 9, P.accent)
	-- the emitter the sun floats over
	local base = at * CFrame.new(0, H, tz)
	cyl(2.6, 0.7, base * CFrame.new(0, 0.35, 0), P.bodyDark, f, true)
	quiet(cyl(1.9, 0.22, base * CFrame.new(0, 0.8, 0), P.body, f))
	quiet(glow(cyl(2.75, 0.1, base * CFrame.new(0, 0.66, 0), P.neon, f)))
	for k = 0, 2 do
		local a = k * math.pi * 2 / 3
		local arm = base * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, 2.2)
		block(Vector3.new(0.45, 2.6, 0.45), arm * CFrame.new(0, 1.9, 0) * CFrame.Angles(-0.35, 0, 0), P.body, f)
		quiet(glow(block(Vector3.new(0.5, 0.5, 0.5), arm * CFrame.new(0, 3.2, -0.45), P.accent, f)))
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
	snowman = frostArch,
	heatbag = frostTorii,
	golem = crystalCitadel,
	sun = auroraWolf,
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
