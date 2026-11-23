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
-- Trainers v3 (owner 2026-11-12: "I like the first one most... make 9 more in exactly this style"): levels 2-10
-- are themed Peppermint, Gingerbread, Workshop, Ice, Reindeer, Crystal, Aurora, Citadel and North Star, each
-- with its own gate top and a target the snowman's size (the list is above the level-2 builder below).
-- Same stage, stand spot and target spot on every level, so the lock and the bolts never change.
-- TrainingService builds each pan's trainer at its owner's level and rebuilds it on an upgrade.
-- Contract (TrainingController): each target is a Model named Target, tagged Config.training.targetTag,
-- with the attributes Station (its pan) and Tier (its level) and its WorldPivot at the target's foot. Parts the client cools
-- toward frost are named Heat. A hanging target's model would also have HangAt (the chain's top: it swings from there).

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Theme = require(ReplicatedStorage.Shared.Theme)
local MapArt = require(script.Parent.MapArt)

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

	-- the Snowman Dummy: a wooden stand, three snowballs, a bullseye on its chest, round coal eyes (QA DR-02: X eyes read as knocked out), a carrot,
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
		quiet(ball(0.16, (foot * CFrame.new(s * 0.38, hy + 0.22, -0.93)).Position, P.coal, m))
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

-- ========== Trainers v3 (owner 2026-11-12): nine more levels on the Frost Arch's kit ==========
-- Same stage, runway, ring, lanterns and snowfall; a gate on the same two pillar spots; a matching pair of
-- flankers; a target the snowman's size. Each gate's skyline top is its own (World Rules 12, the Swap Test):
--   2 Peppermint   candy-cane arch, a wrapped peppermint keystone     lollipops        Peppermint Pal
--   3 Gingerbread  stepped icing roof, a gumdrop on top               gumdrop trees    Gingerbread Man
--   4 Workshop     timber gate, three turning gears                   present stacks   Nutcracker
--   5 Ice          ice spires, a pointed snowflake crest              ice obelisks     Penguin
--   6 Reindeer     snowy red beam, golden antlers, a wreath           decorated trees  Reindeer
--   7 Crystal      chamfered gate, a crystal crown                    crystal clusters Amethyst Golem
--   8 Aurora       aurora ribbons, a turning sparkle, a curtain       aurora trees     Snow Owl
--   9 Citadel      castle towers and crenels, a shield crest          turrets          Knight
--  10 North Star   starry arch, a turning compass star                garland trees    Star Spirit

local tz = T.targetZ -- every target stands here (local +Z from the stage's middle)
local FACE = CFrame.Angles(0, math.pi / 2, 0) -- turns rod() to face along Z (a disc you see from the front)
local TRI_POS = CFrame.fromMatrix(Vector3.zero, Vector3.new(0, 0, 1), Vector3.new(0, 1, 0))
local TRI_NEG = CFrame.fromMatrix(Vector3.zero, Vector3.new(0, 0, -1), Vector3.new(0, 1, 0))

local function pt(cf: CFrame, x: number, y: number, z: number): Vector3
	return (cf * CFrame.new(x, y, z)).Position
end

local function heat(parts: { BasePart }): { BasePart }
	for _, p in parts do
		p.Name = "Heat"
	end
	return parts
end

-- a right triangle in cf's XY plane, t thick: the right angle at cf, one leg a studs along s * X, one b up Y
local function tri(f: Instance, cf: CFrame, s: number, a: number, b: number, t: number, color: Color3): BasePart
	local p = Instance.new("WedgePart")
	p.Size = Vector3.new(t, b, a)
	p.CFrame = cf * CFrame.new(s * a / 2, b / 2, 0) * (if s > 0 then TRI_POS else TRI_NEG)
	p.Material = Enum.Material.SmoothPlastic
	return finish(p, color, f)
end

-- an upright isosceles triangle: base 2 * halfW wide on cf, apex h up
local function isoTri(f: Instance, cf: CFrame, halfW: number, h: number, t: number, color: Color3): { BasePart }
	return { tri(f, cf, 1, halfW, h, t, color), tri(f, cf, -1, halfW, h, t, color) }
end

-- an n-pointed star facing Z: a disc in the middle, a triangle per point
local function star(f: Instance, cf: CFrame, rOut: number, rIn: number, t: number, color: Color3, n: number): { BasePart }
	local parts = { rod(t, rIn, cf * FACE, color, f) }
	local half = math.pi / n
	for k = 0, n - 1 do
		local base = cf * CFrame.Angles(0, 0, k * 2 * half) * CFrame.new(0, rIn * math.cos(half), 0)
		for _, p in isoTri(f, base, rIn * math.sin(half) + 0.02, rOut - rIn * math.cos(half), t, color) do
			table.insert(parts, p)
		end
	end
	return parts
end

local function glowAll(parts: { BasePart }, transparency: number?): { BasePart }
	for _, p in parts do
		quiet(glow(p, transparency))
	end
	return parts
end

-- a beam between two points in a plane facing Z: w across, depth along Z
local function bar(f: Instance, a: Vector3, b: Vector3, w: number, depth: number, color: Color3): BasePart
	return block(Vector3.new(w, depth, (b - a).Magnitude + w * 0.5), CFrame.lookAt((a + b) / 2, b, Vector3.zAxis), color, f)
end

-- an upright candy-cane cylinder: a base colour with tilted stripes wound round it
local function candy(f: Instance, cf: CFrame, r: number, h: number, a: Color3, b: Color3, collide: boolean?): { BasePart }
	local parts = { cyl(r, h, cf, a, f, collide) }
	local tilt = 0.38
	local R = (r + 0.03) / math.cos(tilt)
	local margin = R * math.sin(tilt) + 0.12
	local y = -h / 2 + margin
	while y <= h / 2 - margin do
		table.insert(parts, quiet(cyl(R, 0.3, cf * CFrame.new(0, y, 0) * CFrame.Angles(0, 0, tilt), b, f)))
		y += 0.75
	end
	return parts
end

-- a peppermint swirl facing -Z (and +Z when `back`): a disc, six twisted stripes, a plain middle
local function swirl(f: Instance, cf: CFrame, r: number, thick: number, base: Color3, stripe: Color3, back: boolean, capR: number?): { BasePart }
	local parts = { rod(thick, r, cf * FACE, base, f) }
	for _, side in (if back then { -1, 1 } else { -1 }) do
		for k = 0, 5 do
			table.insert(parts, quiet(block(Vector3.new(r * 0.4, r * 0.84, 0.06),
				cf * CFrame.Angles(0, 0, k * math.pi / 3) * CFrame.new(0, r * 0.5, side * (thick / 2 + 0.03)) * CFrame.Angles(0, 0, 0.3), stripe, f)))
		end
		table.insert(parts, quiet(rod(0.08, capR or r * 0.26, cf * CFrame.new(0, 0, side * (thick / 2 + 0.05)) * FACE, base, f)))
	end
	return parts
end

-- a gear facing Z: a rim with teeth, a dark ring crossed by spokes, a hub
local function gear(f: Instance, cf: CFrame, r: number, teeth: number, color: Color3, dark: Color3, hub: Color3)
	rod(0.5, r, cf * FACE, color, f)
	quiet(rod(0.58, r * 0.62, cf * FACE, dark, f))
	for k = 0, 2 do
		quiet(block(Vector3.new(r * 0.16, r * 1.3, 0.64), cf * CFrame.Angles(0, 0, k * math.pi / 3), color, f))
	end
	rod(0.72, r * 0.3, cf * FACE, hub, f)
	for k = 0, teeth - 1 do
		block(Vector3.new(r * 0.34, r * 0.3, 0.5), cf * CFrame.Angles(0, 0, k * 2 * math.pi / teeth) * CFrame.new(0, r * 1.1, 0), color, f)
	end
end

-- a wrapped present from its bottom middle: a box, a lid, a ribbon cross and a bow; returns its top
local function gift(f: Instance, cf: CFrame, size: Vector3, box: Color3, ribbon: Color3, bow: boolean): CFrame
	block(size, cf * CFrame.new(0, size.Y / 2, 0), box, f, true)
	block(Vector3.new(size.X + 0.2, 0.35, size.Z + 0.2), cf * CFrame.new(0, size.Y - 0.1, 0), box, f)
	quiet(block(Vector3.new(size.X + 0.24, size.Y + 0.1, 0.32), cf * CFrame.new(0, size.Y / 2 + 0.03, 0), ribbon, f))
	quiet(block(Vector3.new(0.32, size.Y + 0.1, size.Z + 0.24), cf * CFrame.new(0, size.Y / 2 + 0.03, 0), ribbon, f))
	local top = cf * CFrame.new(0, size.Y + 0.08, 0)
	if bow then
		for _, s in { -1, 1 } do
			quiet(ellipsoid(Vector3.new(0.8, 0.5, 0.35), top * CFrame.new(s * 0.36, 0.2, 0) * CFrame.Angles(0, 0, -s * 0.5), ribbon, f))
		end
		quiet(ball(0.16, pt(top, 0, 0.12, 0), ribbon, f))
	end
	return top
end

-- the arch of the Frost Arch's shape: n blocks round a half circle on the pillars, two colours in turn,
-- neon on both curves front and back
local function archOf(f: Instance, c: CFrame, n: number, a: Color3, b: Color3, neon: Color3)
	local chord = 2 * (GX + 0.6) * math.sin(math.pi / (2 * n)) + 0.05
	for k = 0, n - 1 do
		local ang = (k + 0.5) * math.pi / n
		block(Vector3.new(chord, 1.2, if k % 2 == 0 then 1.3 else 1.18), c * CFrame.new(GX * math.cos(ang), GX * math.sin(ang), 0) * CFrame.Angles(0, 0, ang + math.pi / 2),
			if k % 2 == 0 then a else b, f, true)
	end
	for _, side in { -1, 1 } do
		arcLine(f, c * CFrame.new(0, 0, side * 0.66), GX + 0.62, 12, neon)
		arcLine(f, c * CFrame.new(0, 0, side * 0.66), GX - 0.62, 10, neon)
	end
end

-- the shared stage, runway, ring, lanterns and snowfall
local function kit(f: Instance, at: CFrame, P: Palette, ringR: number)
	stage(f, at, P)
	runway(f, at, P, T.targetZ - ringR)
	targetRing(f, at, P, ringR)
	lanterns(f, at, P)
	snowfall(f, at)
end

-- a cartoon face on a surface facing -Z at cf: two eyes with glints, a smile, rosy cheeks
local function face(m: Instance, cf: CFrame, eyeGap: number, eyeR: number, P: Palette)
	for _, s in { -1, 1 } do
		ball(eyeR, pt(cf, s * eyeGap, 0.15, 0), P.coal, m)
		quiet(ball(eyeR * 0.35, pt(cf, s * eyeGap - eyeR * 0.3, 0.15 + eyeR * 0.35, -eyeR * 0.8), Theme.white, m))
		quiet(ellipsoid(Vector3.new(eyeR * 2, eyeR * 1.3, 0.1), cf * CFrame.new(s * (eyeGap + eyeR * 1.6), -eyeR * 1.6, 0.02), P.cheek, m))
	end
	for k = -2, 2 do
		quiet(ball(eyeR * 0.32, pt(cf, k * eyeR * 0.7, -eyeR * 2.1 + math.abs(k) * eyeR * 0.25, 0), P.coal, m))
	end
end

-- ---------- 2. Peppermint: a candy-cane arch, a wrapped peppermint keystone, giant lollipops ----------
local function peppermint(f: Instance, at: CFrame, i: number)
	local P = TT.stations.peppermint
	kit(f, at, P, 2.6)
	local spring = 6.8
	for _, s in { -1, 1 } do
		block(Vector3.new(1.7, 1.1, 1.7), at * CFrame.new(s * GX, 0.55, GZ), P.bodyDark, f, true)
		edgeFrame(f, at * CFrame.new(s * GX, 0.55, GZ), Vector3.new(1.7, 1.1, 1.7), P.neon, true)
		candy(f, at * CFrame.new(s * GX, 1.1 + (spring - 1.1) / 2, GZ), 0.62, spring - 1.1, P.stripeA, P.stripeB, true)
		quiet(glow(cyl(0.7, 0.14, at * CFrame.new(s * GX, spring - 0.3, GZ), P.neon, f)))
	end
	doorway(f, at, spring, P.panel)
	rod(0.12, GX - 0.6, at * CFrame.new(0, spring, PANEL_Z + 0.03) * FACE, P.panel, f)
	local c = at * CFrame.new(0, spring, GZ)
	archOf(f, c, 9, P.stripeA, P.stripeB, P.neon)
	-- the keystone: a big wrapped peppermint through the arch, a glowing rim, twisted wrapper ends
	local key = c * CFrame.new(0, GX + 0.3, 0)
	quiet(glow(rod(1.3, 1.68, key * FACE, P.neon, f)))
	swirl(f, key, 1.55, 1.6, P.stripeA, P.stripeB, true)
	for _, s in { -1, 1 } do
		local w = quiet(shape("Cone", Vector3.new(1.2, 1.3, 1.2), key * CFrame.new(s * 2.15, 0, 0) * CFrame.Angles(0, 0, s * math.pi / 2), P.wrap, f))
		w.Transparency = 0.2
		quiet(ball(0.3, pt(key, s * 1.55, 0, 0), P.wrap, f))
	end
	-- giant lollipops behind the gate's shoulders
	for _, s in { -1, 1 } do
		local b = at * CFrame.new(s * FLANK.x, 0, FLANK.z + 0.3)
		cyl(0.75, 0.4, b * CFrame.new(0, 0.2, 0), P.mintDark, f, true)
		cyl(0.17, 6.4, b * CFrame.new(0, 3.4, 0), P.stick, f, true)
		local pop = b * CFrame.new(0, 7.5, 0)
		quiet(glow(rod(0.36, 1.78, pop * FACE, P.stripeB, f), 0.1))
		swirl(f, pop, 1.65, 0.5, P.stripeA, P.mint, true)
		for _, t in { -1, 1 } do
			quiet(ellipsoid(Vector3.new(0.9, 0.5, 0.3), b * CFrame.new(t * 0.4, 5.6, 0) * CFrame.Angles(0, 0, -t * 0.5), P.stripeB, f))
		end
		quiet(ball(0.18, pt(b, 0, 5.55, 0), P.stripeB, f))
	end

	-- Peppermint Pal: a wrapped peppermint on candy-cane legs, a face in its middle, mint leaves on top
	local foot = at * CFrame.new(0, H, tz)
	local m = target(f, i)
	cyl(1.7, 0.35, foot * CFrame.new(0, 0.175, 0), P.mintDark, m)
	quiet(glow(cyl(1.78, 0.08, foot * CFrame.new(0, 0.3, 0), P.neon, m)))
	for _, s in { -1, 1 } do
		heat(candy(m, foot * CFrame.new(s * 0.85, 1.4, 0), 0.32, 2.1, P.stripeA, P.stripeB))
		ellipsoid(Vector3.new(0.95, 0.6, 1.35), foot * CFrame.new(s * 0.85, 0.62, -0.18), P.mint, m)
	end
	local body = foot * CFrame.new(0, 4.9, 0)
	heat(swirl(m, body, 2.5, 1.8, P.stripeA, P.stripeB, true, 1.15))
	for _, s in { -1, 1 } do
		local w = shape("Cone", Vector3.new(1.4, 1.5, 1.4), body * CFrame.new(s * 3.15, 0, 0) * CFrame.Angles(0, 0, s * math.pi / 2), P.wrap, m)
		w.Transparency = 0.2
		ball(0.34, pt(body, s * 2.5, 0, 0), P.wrap, m)
		quiet(ellipsoid(Vector3.new(1.1, 0.35, 0.6), body * CFrame.new(s * 0.45, 2.62, 0) * CFrame.Angles(0, 0, -s * 0.5), P.mint, m))
	end
	quiet(ball(0.3, pt(body, 0, 2.6, 0), P.stripeB, m))
	face(m, body * CFrame.new(0, 0.05, -1.0), 0.45, 0.2, P)
	sealTarget(m, foot)
	targetBlock(f, foot * CFrame.new(0, 4, 0), Vector3.new(4.4, 8, 3))
end

-- ---------- 3. Gingerbread: cookie pillars, a stepped roof dripping icing, a gumdrop on top ----------
local GUMS = { "gumRed", "gumGreen", "gumYellow", "gumPurple" }
local function gumdrop(f: Instance, cf: CFrame, r: number, color: Color3)
	cyl(r, r * 0.6, cf * CFrame.new(0, r * 0.3, 0), color, f)
	ellipsoid(Vector3.new(r * 2, r * 1.8, r * 2), cf * CFrame.new(0, r * 0.6, 0), color, f)
end

local function gingerbread(f: Instance, at: CFrame, i: number)
	local P = TT.stations.gingerbread
	kit(f, at, P, 2.4)
	local top = 7.0
	for _, s in { -1, 1 } do
		pillar(f, at, s * GX, top, P, true, true)
		gumdrop(f, at * CFrame.new(s * GX, top + 0.7, GZ), 0.45, P[GUMS[if s < 0 then 1 else 2]])
	end
	doorway(f, at, top, P.panel)
	local ly = top + 1.2
	local lintel = at * CFrame.new(0, ly, GZ)
	block(Vector3.new(2 * GX + 2.2, 1.2, 1.5), lintel, P.body, f)
	edgeFrame(f, lintel, Vector3.new(2 * GX + 2.2, 1.2, 1.5), P.neon, true)
	-- the stepped roof: four cookie slabs, icing on each step and a row of drips under it, gumdrops on the ends
	local y = ly + 0.6
	for k, w in { 9.8, 7.6, 5.4, 3.2 } do
		block(Vector3.new(w, 0.7, 1.3), at * CFrame.new(0, y + 0.35, GZ), if k % 2 == 1 then P.cookie else P.body, f)
		snowCap(f, at * CFrame.new(0, y + 0.7, GZ), w, 1.3, P.snow)
		local n = math.floor(w / 0.8)
		for d = 0, n - 1 do
			local x = -w / 2 + 0.4 + d * (w - 0.8) / math.max(1, n - 1)
			for _, side in { -1, 1 } do
				quiet(ball(if d % 2 == 0 then 0.17 else 0.12, pt(at, x, y + 0.66, GZ + side * 0.76), P.snow, f))
			end
		end
		for _, s in { -1, 1 } do
			gumdrop(f, at * CFrame.new(s * (w / 2 - 0.35), y + 1.0, GZ), 0.26, P[GUMS[(k + (if s < 0 then 0 else 2)) % 4 + 1]])
		end
		y += 0.7
	end
	gumdrop(f, at * CFrame.new(0, y + 0.3, GZ), 0.75, P.gumRed)
	quiet(glow(ball(0.2, pt(at, -0.3, y + 1.55, GZ - 0.4), P.accent, f), 0.2))
	-- a cookie badge on the lintel, front and back: icing dots round a snowflake
	for _, side in { -1, 1 } do
		local badge = at * CFrame.new(0, ly + 1.15, GZ + side * 0.8) * (if side > 0 then CFrame.Angles(0, math.pi, 0) else CFrame.identity)
		rod(0.3, 1.05, badge * FACE, P.cookie, f)
		for k = 0, 11 do
			local a = k * math.pi / 6
			quiet(ball(0.08, pt(badge, 0.85 * math.cos(a), 0.85 * math.sin(a), -0.16), P.snow, f))
		end
		flake(f, badge * CFrame.new(0, 0, -0.18), 1.1, P.snow)
	end
	-- gumdrop trees behind the gate's shoulders
	for _, s in { -1, 1 } do
		local b = at * CFrame.new(s * FLANK.x, 0, FLANK.z + 0.3)
		cyl(0.28, 1.8, b * CFrame.new(0, 0.9, 0), P.bodyDark, f, true)
		for k = 0, 3 do
			local w = 3.4 - k * 0.75
			local ty = 1.9 + k * 1.3
			ellipsoid(Vector3.new(w, 1.5, w), b * CFrame.new(0, ty, 0), if k % 2 == 0 then P.tree else P.treeDark, f)
			quiet(cyl(w / 2 - 0.05, 0.16, b * CFrame.new(0, ty - 0.25, 0), P.snow, f))
			for d = 0, 4 do
				local a = d * math.pi * 2 / 5 + k
				quiet(ball(0.16, pt(b, (w / 2 - 0.1) * math.cos(a), ty + 0.1, (w / 2 - 0.1) * math.sin(a)), P[GUMS[(d + k) % 4 + 1]], f))
			end
		end
		gumdrop(f, b * CFrame.new(0, 6.6, 0), 0.5, P.gumYellow)
	end

	-- the Gingerbread Man: a thick cookie with icing trim, gumdrop buttons, a candy bow tie
	local foot = at * CFrame.new(0, H, tz)
	local m = target(f, i)
	quiet(cyl(1.9, 0.18, foot * CFrame.new(0, 0.09, 0), P.gumRed, m))
	cyl(1.8, 0.3, foot * CFrame.new(0, 0.2, 0), P.plate, m)
	local cookie = P.cookie
	for _, s in { -1, 1 } do
		local leg = foot * CFrame.new(s * 0.8, 1.65, 0) * CFrame.Angles(0, 0, s * 0.18)
		named(block(Vector3.new(1.15, 2.4, 1.2), leg, cookie, m), "Heat")
		named(rod(1.2, 0.6, leg * CFrame.new(0, -1.1, 0) * FACE, cookie, m), "Heat")
		for _, dy in { -0.6, -0.85 } do
			quiet(block(Vector3.new(1.0, 0.1, 0.06), leg * CFrame.new(0, dy, -0.63), P.snow, m))
		end
		local arm = foot * CFrame.new(s * 1.9, 4.9, 0) * CFrame.Angles(0, 0, -s * 1.0)
		named(block(Vector3.new(1.05, 2.3, 1.2), arm, cookie, m), "Heat")
		named(rod(1.2, 0.55, arm * CFrame.new(0, 1.1, 0) * FACE, cookie, m), "Heat")
		for _, dy in { 0.55, 0.8 } do
			quiet(block(Vector3.new(0.9, 0.1, 0.06), arm * CFrame.new(0, dy, -0.63), P.snow, m))
		end
	end
	named(block(Vector3.new(2.7, 3.0, 1.2), foot * CFrame.new(0, 4.1, 0), cookie, m), "Heat")
	local headAt = foot * CFrame.new(0, 6.55, 0)
	named(rod(1.2, 1.35, headAt * FACE, cookie, m), "Heat")
	for k = 0, 17 do
		local a = k * math.pi / 9
		quiet(ball(0.07, pt(headAt, 1.17 * math.cos(a), 1.17 * math.sin(a), -0.62), P.snow, m))
	end
	face(m, headAt * CFrame.new(0, 0.1, -0.68), 0.45, 0.18, P)
	for k, gy in { 4.9, 4.1, 3.3 } do
		gumdrop(m, foot * CFrame.new(0, gy - 0.25, -0.62) * CFrame.Angles(-math.pi / 2, 0, 0), 0.24, P[GUMS[k]])
	end
	for _, s in { -1, 1 } do
		quiet(ellipsoid(Vector3.new(0.6, 0.45, 0.2), foot * CFrame.new(s * 0.32, 5.45, -0.66) * CFrame.Angles(0, 0, s * 0.3), P.gumRed, m))
	end
	quiet(ball(0.14, pt(foot, 0, 5.45, -0.72), P.gumRed, m))
	sealTarget(m, foot)
	targetBlock(f, foot * CFrame.new(0, 4, 0), Vector3.new(3.6, 8, 2.4))
end

-- ---------- 4. Workshop: a timber gate with knee braces, three turning gears, stacks of presents ----------
local function workshop(f: Instance, at: CFrame, i: number)
	local P = TT.stations.workshop
	kit(f, at, P, 2.4)
	local top = 7.4
	for _, s in { -1, 1 } do
		pillar(f, at, s * GX, top, P, true, true)
		block(Vector3.new(0.45, 2.3, 0.5), at * CFrame.new(s * (GX - 1.25), top - 0.55, GZ) * CFrame.Angles(0, 0, s * 0.785), P.wood, f)
	end
	doorway(f, at, top + 0.4, P.panel)
	local ly = top + 1.1
	local lintel = at * CFrame.new(0, ly, GZ)
	local lintelSize = Vector3.new(2 * GX + 2.6, 1.4, 1.6)
	block(lintelSize, lintel, P.red, f)
	edgeFrame(f, lintel, lintelSize, P.neon, true)
	for _, s in { -1, 1 } do
		snowCap(f, at * CFrame.new(s * (GX + 0.2), ly + 0.7, GZ), 2.6, 1.6, P.snow)
		for _, side in { -1, 1 } do
			for _, dx in { -0.9, 0.9 } do
				quiet(ball(0.12, pt(lintel, s * (GX - 1.6) + dx, 0, side * 0.82), P.gold, f))
			end
		end
	end
	-- the big gear on top with a snowflake hub, a small gear meshing on each side (MapController turns them)
	local gAt = at * CFrame.new(0, ly + 0.7 + 1.85, GZ)
	local big = spinner(f, gAt, Vector3.new(0, 0, 1), 0.45)
	gear(big, gAt, 1.8, 12, P.gold, P.goldDark, P.red)
	flake(big, gAt * CFrame.new(0, 0, -0.38), 1.0, P.snow)
	flake(big, gAt * CFrame.new(0, 0, 0.38) * CFrame.Angles(0, math.pi, 0), 1.0, P.snow)
	for _, s in { -1, 1 } do
		local sAt = at * CFrame.new(s * 3.05, ly + 0.7 + 1.15, GZ - 0.05)
		gear(spinner(f, sAt, Vector3.new(0, 0, 1), -0.45 * 1.8 / 0.95), sAt, 0.95, 8, P.red, P.redDark, P.gold)
	end
	-- presents piled behind the gate's shoulders
	for k, s in { -1, 1 } do
		local b = at * CFrame.new(s * FLANK.x, 0, FLANK.z + 0.2)
		local t1 = gift(f, b, Vector3.new(2.6, 2.0, 2.6), P[if k == 1 then "giftA" else "giftB"], P.gold, false)
		local t2 = gift(f, t1 * CFrame.Angles(0, s * 0.35, 0), Vector3.new(2.0, 1.7, 2.0), P[if k == 1 then "giftC" else "giftD"], P.snow, false)
		gift(f, t2 * CFrame.Angles(0, -s * 0.5, 0), Vector3.new(1.4, 1.3, 1.4), P[if k == 1 then "giftB" else "giftA"], P.gold, true)
	end

	-- the Nutcracker: a red coat with gold buttons and epaulettes, white trousers, black boots, a tall hat
	local foot = at * CFrame.new(0, H, tz)
	local m = target(f, i)
	cyl(1.6, 0.5, foot * CFrame.new(0, 0.25, 0), P.red, m)
	quiet(cyl(1.68, 0.14, foot * CFrame.new(0, 0.45, 0), P.gold, m))
	for _, s in { -1, 1 } do
		block(Vector3.new(0.85, 1.0, 1.25), foot * CFrame.new(s * 0.55, 1.0, -0.1), P.black, m)
		named(cyl(0.42, 1.6, foot * CFrame.new(s * 0.55, 2.3, 0), P.white, m), "Heat")
		named(block(Vector3.new(0.7, 2.2, 0.8), foot * CFrame.new(s * 1.62, 4.55, 0), P.red, m), "Heat")
		quiet(block(Vector3.new(0.8, 0.3, 0.9), foot * CFrame.new(s * 1.62, 3.55, 0), P.white, m))
		ball(0.4, pt(foot, s * 1.62, 3.15, 0), P.white, m)
		cyl(0.55, 0.25, foot * CFrame.new(s * 1.35, 5.8, 0), P.gold, m)
		for k = -1, 1 do
			quiet(block(Vector3.new(0.1, 0.4, 0.1), foot * CFrame.new(s * 1.35 + k * 0.3, 5.5, -0.5), P.gold, m))
		end
		for _, y in { 4.35, 4.9, 5.45 } do
			quiet(ball(0.12, pt(foot, s * 0.45, y, -0.92), P.gold, m))
		end
	end
	named(block(Vector3.new(2.5, 2.7, 1.8), foot * CFrame.new(0, 4.45, 0), P.red, m), "Heat")
	named(block(Vector3.new(2.8, 0.6, 2.0), foot * CFrame.new(0, 3.25, 0), P.redDark, m), "Heat")
	block(Vector3.new(2.6, 0.4, 1.9), foot * CFrame.new(0, 3.75, 0), P.white, m)
	quiet(block(Vector3.new(0.5, 0.36, 0.1), foot * CFrame.new(0, 3.75, -0.97), P.gold, m))
	quiet(block(Vector3.new(0.22, 2.0, 0.06), foot * CFrame.new(0, 4.85, -0.92), P.gold, m))
	local head = foot * CFrame.new(0, 6.75, 0)
	block(Vector3.new(1.8, 1.9, 1.6), head, P.skin, m)
	block(Vector3.new(2.0, 1.5, 0.6), head * CFrame.new(0, 0.05, 0.6), P.white, m)
	quiet(block(Vector3.new(1.2, 0.34, 0.1), head * CFrame.new(0, -0.55, -0.82), P.white, m))
	quiet(block(Vector3.new(1.3, 0.12, 0.1), head * CFrame.new(0, -0.35, -0.83), P.black, m))
	block(Vector3.new(0.32, 0.45, 0.3), head * CFrame.new(0, 0.0, -0.92), P.skin, m)
	face(m, head * CFrame.new(0, 0.15, -0.82), 0.42, 0.15, P)
	named(cyl(0.95, 1.4, foot * CFrame.new(0, 8.4, 0), P.black, m), "Heat")
	quiet(cyl(0.98, 0.3, foot * CFrame.new(0, 7.95, 0), P.gold, m))
	star(m, foot * CFrame.new(0, 8.55, -0.98), 0.38, 0.16, 0.08, P.gold, 5)
	sealTarget(m, foot)
	targetBlock(f, foot * CFrame.new(0, 4.5, 0), Vector3.new(3.8, 9, 2.6))
end

-- ---------- 5. Ice: ice spires on the pillars, a pointed crest with a big snowflake, ice obelisks ----------
local function iceGate(f: Instance, at: CFrame, i: number)
	local P = TT.stations.ice
	kit(f, at, P, 2.4)
	local top = 7.6
	for _, s in { -1, 1 } do
		pillar(f, at, s * GX, top, P, true, true)
		local spire = shape("Octa", Vector3.new(1.3, 3.6, 1.3), at * CFrame.new(s * GX, top + 0.4 + 1.65, GZ), P.ice, f)
		spire.Transparency = 0.15
		quiet(glow(shape("Octa", Vector3.new(0.5, 2.4, 0.5), at * CFrame.new(s * GX, top + 0.4 + 1.65, GZ), P.neon, f), 0.2))
		for _, side in { -1, 1 } do
			shape("Octa", Vector3.new(0.75, 2.0, 0.75), at * CFrame.new(s * GX + side * 0.62, top + 0.4 + 0.75, GZ) * CFrame.Angles(0, 0, -side * 0.42), P.iceDeep, f)
		end
	end
	local ly = top - 0.3
	local lintel = at * CFrame.new(0, ly, GZ)
	local lintelSize = Vector3.new(2 * (GX - 0.6), 1.0, 1.1)
	block(lintelSize, lintel, P.body, f)
	edgeFrame(f, lintel, lintelSize, P.neon, true)
	doorway(f, at, ly - 0.5, P.panel, 0.15)
	-- the crest: a panel with a pointed top, a big glowing snowflake front and back, a crystal on the point
	local cy = ly + 0.5 + 1.3
	local crest = at * CFrame.new(0, cy, GZ)
	local crestSize = Vector3.new(5.4, 2.6, 0.8)
	block(crestSize, crest, P.crest, f)
	edgeFrame(f, crest, crestSize, P.neon, true)
	isoTri(f, crest * CFrame.new(0, 1.3, 0), 2.7, 1.6, 0.8, P.crest)
	for _, side in { -1, 1 } do
		for _, s in { -1, 1 } do
			line(f, pt(crest, s * 2.7, 1.3, side * 0.42), pt(crest, 0, 2.9, side * 0.42), P.neon)
		end
		flake(f, crest * CFrame.new(0, 0.35, side * 0.44) * (if side > 0 then CFrame.Angles(0, math.pi, 0) else CFrame.identity), 2.3, P.flake)
	end
	quiet(glow(shape("Octa", Vector3.new(0.9, 1.8, 0.9), crest * CFrame.new(0, 3.5, 0), P.neon, f), 0.05))
	for _, s in { -1, 1 } do
		shape("Octa", Vector3.new(0.6, 1.3, 0.6), crest * CFrame.new(s * 2.7, 1.8, 0), P.ice, f)
	end
	-- ice obelisks with a glowing snowflake bobbing over each
	for k, s in { -1, 1 } do
		local b = at * CFrame.new(s * FLANK.x, 0, FLANK.z + 0.2)
		cyl(1.0, 0.5, b * CFrame.new(0, 0.25, 0), P.bodyDark, f, true)
		local ob = b * CFrame.new(0, 0.5 + 2.6, 0)
		local o = block(Vector3.new(1.1, 5.2, 1.1), ob, P.ice, f, true)
		o.Transparency = 0.15
		edgeFrame(f, ob, Vector3.new(1.1, 5.2, 1.1), P.neon, true)
		shape("Octa", Vector3.new(1.15, 1.8, 1.15), b * CFrame.new(0, 6.0, 0), P.iceDeep, f)
		local fl = b * CFrame.new(0, 7.9, 0)
		local bob = bobber(f, fl, 0.35, 0.35, k / 2)
		flake(bob, fl, 1.6, P.flake)
		flake(bob, fl * CFrame.Angles(0, math.pi / 2, 0), 1.6, P.flake)
	end

	-- the Penguin: a round navy body and white belly, flippers, an orange beak and feet, a pink scarf and beanie
	local foot = at * CFrame.new(0, H, tz)
	local m = target(f, i)
	quiet(cyl(2.0, 0.15, foot * CFrame.new(0, 0.08, 0), P.iceDeep, m))
	cyl(1.9, 0.4, foot * CFrame.new(0, 0.25, 0), P.snow, m)
	for _, s in { -1, 1 } do
		ellipsoid(Vector3.new(1.0, 0.4, 1.5), foot * CFrame.new(s * 0.7, 0.6, -0.55), P.beak, m)
		named(ellipsoid(Vector3.new(0.6, 2.6, 1.3), foot * CFrame.new(s * 1.85, 3.3, 0) * CFrame.Angles(0, 0, s * 0.35), P.coat, m), "Heat")
	end
	named(ellipsoid(Vector3.new(3.6, 5.0, 3.2), foot * CFrame.new(0, 3.0, 0), P.coat, m), "Heat")
	named(ellipsoid(Vector3.new(2.7, 3.9, 1.4), foot * CFrame.new(0, 2.8, -1.0), P.belly, m), "Heat")
	named(ball(1.45, pt(foot, 0, 6.1, 0), P.coat, m), "Heat")
	named(ellipsoid(Vector3.new(2.2, 1.8, 0.8), foot * CFrame.new(0, 5.95, -1.1), P.belly, m), "Heat")
	face(m, foot * CFrame.new(0, 6.0, -1.5), 0.45, 0.19, P)
	shape("Cone", Vector3.new(0.5, 0.8, 0.42), foot * CFrame.new(0, 5.82, -1.85) * CFrame.Angles(-math.pi / 2, 0, 0), P.beak, m)
	cyl(1.35, 0.45, foot * CFrame.new(0, 4.85, 0), P.scarf, m)
	quiet(block(Vector3.new(0.45, 1.3, 0.15), foot * CFrame.new(0.55, 4.25, -1.3) * CFrame.Angles(0.15, 0, 0.15), P.scarf, m))
	ellipsoid(Vector3.new(2.5, 1.5, 2.5), foot * CFrame.new(0, 7.15, 0), P.scarf, m)
	cyl(1.34, 0.32, foot * CFrame.new(0, 6.78, 0), P.snow, m)
	ball(0.4, pt(foot, 0, 7.95, 0), P.snow, m)
	sealTarget(m, foot)
	targetBlock(f, foot * CFrame.new(0, 4, 0), Vector3.new(3.8, 8, 3.4))
end

-- ---------- 6. Reindeer: a snowy red beam, golden antlers, a wreath, decorated trees ----------
-- an antler in the plane facing Z at base: a main beam out and up, three tines (s = which side)
local ANTLER = { { 0, 0, 0.8, 1.5 }, { 0.8, 1.5, 1.7, 2.5 }, { 1.7, 2.5, 2.1, 3.6 }, { 0.8, 1.5, 0.3, 2.6 }, { 1.7, 2.5, 1.4, 3.5 }, { 1.7, 2.5, 2.8, 2.8 } }
local function antler(f: Instance, base: CFrame, s: number, k: number, w: number, color: Color3)
	for _, seg in ANTLER do
		local a, b = pt(base, s * seg[1] * k, seg[2] * k, 0), pt(base, s * seg[3] * k, seg[4] * k, 0)
		bar(f, a, b, w, w, color)
		ball(w * 0.55, b, color, f)
	end
end

local function reindeer(f: Instance, at: CFrame, i: number)
	local P = TT.stations.reindeer
	kit(f, at, P, 2.4)
	local top = 7.4
	for _, s in { -1, 1 } do
		pillar(f, at, s * GX, top, P, false)
		ball(0.36, pt(at, s * GX, top - 0.7, GZ - 0.86), P.gold, f)
		quiet(ellipsoid(Vector3.new(0.7, 0.4, 0.2), at * CFrame.new(s * GX, top - 0.15, GZ - 0.86), P.berry, f))
	end
	doorway(f, at, top, P.panel)
	local ly = top + 0.7
	local beam = at * CFrame.new(0, ly, GZ)
	local beamSize = Vector3.new(2 * GX + 2.4, 1.4, 1.6)
	block(beamSize, beam, P.body, f)
	edgeFrame(f, beam, beamSize, P.neon, true)
	for _, s in { -1, 1 } do
		rod(1.6, 0.7, beam * CFrame.new(s * beamSize.X / 2, 0, 0) * FACE, P.body, f)
		quiet(glow(rod(1.4, 0.78, beam * CFrame.new(s * beamSize.X / 2, 0, 0) * FACE, P.neon, f)))
	end
	-- fluffy snow along the beam
	block(Vector3.new(beamSize.X + 0.4, 0.4, 1.8), beam * CFrame.new(0, 0.9, 0), P.snow, f)
	local x = -beamSize.X / 2 - 0.2
	while x <= beamSize.X / 2 + 0.2 do
		quiet(ball(0.45, pt(beam, x, 1.12, 0), P.snow, f))
		x += 1.2
	end
	-- the golden antlers
	for _, s in { -1, 1 } do
		antler(f, beam * CFrame.new(s * 0.9, 1.0, 0), s, 1.05, 0.5, P.antler)
	end
	-- a wreath with berries and a bow, front and back
	for _, side in { -1, 1 } do
		local w = beam * CFrame.new(0, -0.2, side * 0.95)
		shape("Ring", Vector3.new(2.3, 0.45, 2.3), w * CFrame.Angles(math.pi / 2, 0, 0), P.wreath, f)
		for k = 0, 13 do
			local a = k * math.pi / 7
			quiet(ball(0.3, pt(w, 1.0 * math.cos(a), 1.0 * math.sin(a), side * 0.05), if k % 2 == 0 then P.wreath else P.wreathDark, f))
			if k % 3 == 0 then
				quiet(ball(0.13, pt(w, 1.0 * math.cos(a + 0.2), 1.0 * math.sin(a + 0.2), side * 0.3), P.berry, f))
			end
		end
		for _, s in { -1, 1 } do
			quiet(ellipsoid(Vector3.new(0.8, 0.5, 0.25), w * CFrame.new(s * 0.38, -1.0, side * 0.3) * CFrame.Angles(0, 0, -s * 0.45), P.berry, f))
			quiet(block(Vector3.new(0.22, 0.75, 0.08), w * CFrame.new(s * 0.22, -1.45, side * 0.3) * CFrame.Angles(0, 0, s * 0.3), P.berry, f))
		end
		quiet(ball(0.18, pt(w, 0, -1.0, side * 0.35), P.gold, f))
	end
	-- decorated trees behind the gate's shoulders: baubles on every tier, a star on top
	for _, s in { -1, 1 } do
		local b = at * CFrame.new(s * FLANK.x, 0, FLANK.z + 0.3)
		local h = 8.4
		pine(f, b, h, P)
		for k = 0, 2 do
			local w = h * (0.44 - k * 0.1)
			local y = h * (0.18 + k * 0.22) + 0.35
			for d = 0, 4 do
				local a = d * math.pi * 2 / 5 + k * 0.6
				quiet(ball(0.2, pt(b, (w / 2 - 0.25) * math.cos(a), y, (w / 2 - 0.25) * math.sin(a)), if (d + k) % 2 == 0 then P.berry else P.gold, f))
			end
		end
		glowAll(star(f, b * CFrame.new(0, h * 0.9 + 0.45, 0), 0.7, 0.3, 0.25, P.neon, 5))
	end

	-- the Reindeer: brown and cream, a red collar with a bell, a glowing red nose, little gold antlers
	local foot = at * CFrame.new(0, H, tz)
	local m = target(f, i)
	quiet(cyl(1.78, 0.15, foot * CFrame.new(0, 0.08, 0), P.body, m))
	cyl(1.7, 0.35, foot * CFrame.new(0, 0.2, 0), P.snow, m)
	for _, s in { -1, 1 } do
		cyl(0.5, 0.45, foot * CFrame.new(s * 0.65, 0.6, 0), P.hoof, m)
		named(cyl(0.45, 1.8, foot * CFrame.new(s * 0.65, 1.7, 0), P.fur, m), "Heat")
		local arm = foot * CFrame.new(s * 1.6, 3.9, 0) * CFrame.Angles(0, 0, s * 0.3)
		named(ellipsoid(Vector3.new(0.8, 2.2, 0.9), arm, P.fur, m), "Heat")
		ball(0.38, (arm * CFrame.new(0, -1.1, 0)).Position, P.hoof, m)
		local ear = foot * CFrame.new(s * 1.25, 6.9, 0) * CFrame.Angles(0, 0, -s * 1.0)
		ellipsoid(Vector3.new(0.5, 1.1, 0.3), ear, P.fur, m)
		quiet(ellipsoid(Vector3.new(0.3, 0.7, 0.1), ear * CFrame.new(0, 0, -0.14), P.cheek, m))
		antler(m, foot * CFrame.new(s * 0.55, 7.15, 0.1), s, 0.45, 0.24, P.antler)
	end
	named(ellipsoid(Vector3.new(3.0, 3.4, 2.6), foot * CFrame.new(0, 3.7, 0), P.fur, m), "Heat")
	named(ellipsoid(Vector3.new(2.0, 2.4, 0.8), foot * CFrame.new(0, 3.5, -1.0), P.furLight, m), "Heat")
	cyl(1.05, 0.35, foot * CFrame.new(0, 5.2, 0), P.body, m)
	ball(0.32, pt(foot, 0, 4.92, -1.05), P.gold, m)
	named(ellipsoid(Vector3.new(2.3, 2.1, 2.2), foot * CFrame.new(0, 6.3, 0), P.fur, m), "Heat")
	named(ellipsoid(Vector3.new(1.4, 0.95, 1.0), foot * CFrame.new(0, 5.85, -0.95), P.furLight, m), "Heat")
	local nose = quiet(glow(ball(0.33, pt(foot, 0, 6.08, -1.45), P.nose, m)))
	light(nose, P.nose, 8, 0.8)
	for _, s in { -1, 1 } do
		ball(0.17, pt(foot, s * 0.48, 6.62, -0.98), P.coal, m)
		quiet(ball(0.06, pt(foot, s * 0.43, 6.7, -1.13), Theme.white, m))
		quiet(ellipsoid(Vector3.new(0.4, 0.28, 0.1), foot * CFrame.new(s * 0.85, 6.2, -0.92), P.cheek, m))
	end
	sealTarget(m, foot)
	targetBlock(f, foot * CFrame.new(0, 4, 0), Vector3.new(3.6, 8, 3))
end

-- ---------- 7. Crystal: a chamfered gate, a crystal crown, crystal clusters, an Amethyst Golem ----------
local function crystalGate(f: Instance, at: CFrame, i: number)
	local P = TT.stations.crystal
	kit(f, at, P, 2.6)
	local top = 6.8
	local c = 1.6 -- the chamfer
	for _, s in { -1, 1 } do
		pillar(f, at, s * GX, top, P, false)
		local a, b = pt(at, s * GX, top, GZ), pt(at, s * (GX - c), top + c, GZ)
		bar(f, a, b, 1.2, 1.2, P.body)
		local dir = (b - a).Unit
		local n = Vector3.new(s * dir.Y, -s * dir.X, 0)
		for _, side in { -1, 1 } do
			local z = Vector3.new(0, 0, side * 0.62)
			line(f, a + n * 0.6 + z, b + n * 0.6 + z, P.neon)
			line(f, a - n * 0.6 + z, b - n * 0.6 + z, P.neon)
		end
		quiet(glow(shape("Octa", Vector3.new(0.7, 1.3, 0.7), CFrame.new((a + b) / 2 + n * 0.95) * CFrame.Angles(0, 0, -s * 0.785), P.accent, f), 0.05))
		-- small crystals at the pillar's foot
		shape("Octa", Vector3.new(0.7, 1.7, 0.7), at * CFrame.new(s * (GX + 0.95), 0.7, GZ - 0.5) * CFrame.Angles(0.2, 0, -s * 0.4), P.crystal, f)
		shape("Octa", Vector3.new(0.5, 1.1, 0.5), at * CFrame.new(s * (GX + 0.9), 0.5, GZ + 0.4) * CFrame.Angles(-0.3, 0, -s * 0.6), P.crystalLight, f)
	end
	local lintel = at * CFrame.new(0, top + c, GZ)
	local lintelSize = Vector3.new(2 * (GX - c) + 1.2, 1.2, 1.2)
	block(lintelSize, lintel, P.body, f)
	edgeFrame(f, lintel, lintelSize, P.neon, true)
	doorway(f, at, top + 1.0, P.panel, 0.1)
	quiet(glow(shape("Octa", Vector3.new(0.9, 0.9, 0.4), lintel * CFrame.new(0, 0, -0.62), P.accent, f), 0.05))
	-- the crown: a fan of crystals round a glowing core
	local crownY = top + c + 0.6
	local main = shape("Octa", Vector3.new(1.5, 4.0, 1.5), at * CFrame.new(0, crownY + 1.8, GZ), P.crystal, f)
	main.Transparency = 0.3
	quiet(glow(shape("Octa", Vector3.new(0.6, 2.8, 0.6), at * CFrame.new(0, crownY + 1.8, GZ), P.accent, f), 0.1))
	for _, s in { -1, 1 } do
		shape("Octa", Vector3.new(1.0, 2.8, 1.0), at * CFrame.new(s * 0.95, crownY + 1.1, GZ) * CFrame.Angles(0, 0, -s * 0.42), P.crystal, f)
		shape("Octa", Vector3.new(0.8, 1.9, 0.8), at * CFrame.new(s * 1.75, crownY + 0.6, GZ) * CFrame.Angles(0, 0, -s * 0.85), P.crystalLight, f)
	end
	for _, s in { -1, 1 } do
		crystals(f, at * CFrame.new(s * FLANK.x, 0, FLANK.z), 6, s, P)
	end
	floaters(f, at, H + 8.6, P.accent)

	-- the Amethyst Golem: purple rock, glowing violet cracks and heart, crystals growing from its shoulders
	local foot = at * CFrame.new(0, H, tz)
	local m = target(f, i)
	for _, s in { -1, 1 } do
		block(Vector3.new(1.5, 2.4, 1.7), foot * CFrame.new(s * 1, 1.2, 0), P.rock, m, false, Enum.Material.Slate)
		named(quiet(glow(block(Vector3.new(0.16, 1.1, 0.1), foot * CFrame.new(s * 1.1, 1.3, -0.86) * CFrame.Angles(0, 0, s * 0.35), P.core, m))), "Heat")
	end
	block(Vector3.new(3.6, 1.2, 2.2), foot * CFrame.new(0, 2.95, 0), P.rock, m, false, Enum.Material.Slate)
	local torso = foot * CFrame.new(0, 5.05, 0) * CFrame.Angles(0.06, 0, 0)
	block(Vector3.new(4.4, 3.2, 2.8), torso, P.rockLight, m, false, Enum.Material.Slate)
	local heart = named(glow(shape("Octa", Vector3.new(1.2, 1.6, 1.2), torso * CFrame.new(0, 0.1, -1.38), P.core, m)), "Heat")
	light(heart, P.core, 12, 1.1)
	for _, cr in { { -1.3, 0.7, 0.5 }, { -1.1, -0.6, -0.4 }, { 1.2, 0.6, -0.55 }, { 1.4, -0.7, 0.35 } } do
		named(quiet(glow(block(Vector3.new(0.16, 1.2, 0.1), torso * CFrame.new(cr[1], cr[2], -1.42) * CFrame.Angles(0, 0, cr[3]), P.core, m))), "Heat")
	end
	for _, s in { -1, 1 } do
		shape("Rock", Vector3.new(2.3, 2, 2.3), foot * CFrame.new(s * 2.9, 6.3, 0), P.rock, m)
		block(Vector3.new(1.3, 2.4, 1.4), foot * CFrame.new(s * 3.1, 4.6, 0), P.rock, m, false, Enum.Material.Slate)
		shape("Rock", Vector3.new(1.9, 1.7, 1.9), foot * CFrame.new(s * 3.2, 3.05, -0.2), P.rockLight, m)
		named(quiet(glow(shape("Octa", Vector3.new(0.85, 2.3, 0.85), foot * CFrame.new(s * 2.9, 7.7, 0.2) * CFrame.Angles(0, 0, -s * 0.4), P.crystal, m), 0.15)), "Heat")
		named(shape("Octa", Vector3.new(0.65, 1.6, 0.65), foot * CFrame.new(s * 2.3, 7.35, 0.6) * CFrame.Angles(0.3, 0, -s * 0.15), P.crystalLight, m), "Heat")
	end
	local head = foot * CFrame.new(0, 7.55, -0.15)
	block(Vector3.new(2.2, 1.8, 2), head, P.rock, m, false, Enum.Material.Slate)
	block(Vector3.new(2.5, 0.4, 0.5), head * CFrame.new(0, 0.55, -0.9), P.rockLight, m, false, Enum.Material.Slate)
	for _, s in { -1, 1 } do
		named(quiet(glow(block(Vector3.new(0.5, 0.32, 0.1), head * CFrame.new(s * 0.48, 0.05, -1.02), P.eyes, m))), "Eye")
	end
	sparkles(m, Vector3.new(4.4, 0.4, 2.4), foot * CFrame.new(0, 7.2, 0), P.core, 6, 1.8, 0.3)
	sealTarget(m, foot)
	targetBlock(f, foot * CFrame.new(0, 4, 0), Vector3.new(5, 8, 3))
end

-- ---------- 8. Aurora: aurora ribbons over the lintel, a turning sparkle, an aurora curtain in the door ----------
local function aurora(f: Instance, at: CFrame, i: number)
	local P = TT.stations.aurora
	kit(f, at, P, 2.4)
	local top = 7.6
	for _, s in { -1, 1 } do
		pillar(f, at, s * GX, top, P, true, true)
	end
	doorway(f, at, top, P.panel)
	-- the curtain: glowing strips of aurora hanging in the doorway
	local waves = { P.wave1, P.wave2, P.wave3 }
	for k = 0, 9 do
		local x = -3.15 + k * 0.7
		local h = 3.2 + 1.4 * math.sin(k * 0.9)
		quiet(glow(block(Vector3.new(0.5, h, 0.06), at * CFrame.new(x, top - 0.3 - h / 2, PANEL_Z - 0.1), waves[k % 3 + 1], f), 0.45))
	end
	local ly = top + 0.9
	local lintel = at * CFrame.new(0, ly, GZ)
	local lintelSize = Vector3.new(2 * GX + 2, 1.0, 1.4)
	block(lintelSize, lintel, P.body, f)
	edgeFrame(f, lintel, lintelSize, P.neon, true)
	snowCap(f, lintel * CFrame.new(0, 0.5, 0), lintelSize.X, lintelSize.Z, P.snow)
	-- three ribbons waving over it
	for j = 0, 2 do
		local prev: Vector3? = nil
		for k = 0, 16 do
			local x = -5.6 + k * 0.7
			local p = pt(at, x, ly + 1.55 + j * 0.6 + 0.65 * math.sin(x * 0.8 + j * 0.7), GZ + (j - 1) * 0.25)
			if prev then
				quiet(glow(bar(f, prev, p, 0.34, 0.45, waves[j + 1]), 0.12))
			end
			prev = p
		end
	end
	-- a four-pointed sparkle turning over it all
	local sAt = at * CFrame.new(0, ly + 4.6, GZ)
	local spin = spinner(f, sAt, Vector3.new(0, 1, 0), 0.8)
	local sp = glowAll(star(spin, sAt, 1.4, 0.35, 0.35, P.star, 4))
	light(sp[1], P.star, 12, 0.8)
	glowAll(star(spin, sAt * CFrame.Angles(0, 0, math.pi / 4), 0.8, 0.25, 0.3, P.accent, 4))
	-- aurora trees behind the gate's shoulders, crystals floating over them
	for _, s in { -1, 1 } do
		blossom(f, at * CFrame.new(s * FLANK.x, 0, FLANK.z + 0.3), 9.2, P.trunk, P.bloom, P.bloomTint, true)
	end
	floaters(f, at, H + 9.2, P.accent)

	-- the Snow Owl: a fluffy white body with speckles, big golden eyes, aurora-tipped wings, ear tufts
	local foot = at * CFrame.new(0, H, tz)
	local m = target(f, i)
	cyl(1.7, 0.35, foot * CFrame.new(0, 0.175, 0), P.bodyDark, m)
	quiet(glow(cyl(1.78, 0.08, foot * CFrame.new(0, 0.3, 0), P.neon, m)))
	cyl(0.9, 1.0, foot * CFrame.new(0, 0.85, 0), P.perch, m)
	for _, s in { -1, 1 } do
		for k = -1, 1 do
			quiet(block(Vector3.new(0.16, 0.2, 0.55), foot * CFrame.new(s * 0.6 + k * 0.2, 1.42, -0.75), P.beak, m))
		end
	end
	named(ellipsoid(Vector3.new(3.6, 4.4, 3.2), foot * CFrame.new(0, 3.5, 0), P.owl, m), "Heat")
	for _, sp in { { -0.6, 3.0 }, { 0, 3.3 }, { 0.6, 3.0 }, { -0.35, 2.3 }, { 0.35, 2.3 }, { -0.7, 3.9 }, { 0, 4.2 }, { 0.7, 3.9 } } do
		local dx, dy = sp[1] / 1.8, (sp[2] - 3.5) / 2.2
		local z = -1.6 * math.sqrt(math.max(0, 1 - dx * dx - dy * dy)) - 0.02
		for _, t in { -1, 1 } do
			quiet(block(Vector3.new(0.28, 0.08, 0.05), foot * CFrame.new(sp[1] + t * 0.11, sp[2], z) * CFrame.Angles(0, 0, -t * 0.5), P.speck, m))
		end
	end
	for _, s in { -1, 1 } do
		local wing = foot * CFrame.new(s * 1.75, 3.6, 0.2) * CFrame.Angles(0, 0, s * 0.18)
		named(ellipsoid(Vector3.new(0.9, 3.4, 2.4), wing, P.owlShade, m), "Heat")
		for k = 0, 2 do
			quiet(glow(ellipsoid(Vector3.new(0.5, 1.0, 0.7), wing * CFrame.new(s * 0.1, -1.5, -0.6 + k * 0.6), waves[k + 1], m), 0.2))
		end
		shape("Cone", Vector3.new(0.6, 1.2, 0.5), foot * CFrame.new(s * 1.1, 8.0, -0.2) * CFrame.Angles(0, 0, -s * 0.35), P.owlShade, m)
		local eye = foot * CFrame.new(s * 0.65, 6.65, 0)
		local zf = -1.5 * math.sqrt(1 - (0.65 / 1.7) ^ 2)
		quiet(rod(0.2, 0.75, eye * CFrame.new(0, 0, zf + 0.05) * FACE, P.owlShade, m))
		quiet(rod(0.12, 0.5, eye * CFrame.new(0, 0, zf - 0.08) * FACE, P.eye, m))
		quiet(rod(0.1, 0.26, eye * CFrame.new(0, 0, zf - 0.15) * FACE, P.pupil, m))
		quiet(ball(0.08, pt(eye, -0.1, 0.12, zf - 0.22), Theme.white, m))
	end
	named(ellipsoid(Vector3.new(3.4, 2.6, 3.0), foot * CFrame.new(0, 6.6, 0), P.owl, m), "Heat")
	shape("Cone", Vector3.new(0.45, 0.75, 0.4), foot * CFrame.new(0, 6.1, -1.55) * CFrame.Angles(-2.1, 0, 0), P.beak, m)
	sealTarget(m, foot)
	targetBlock(f, foot * CFrame.new(0, 4.2, 0), Vector3.new(3.8, 8.4, 3.2))
end

-- ---------- 9. Citadel: two castle towers, crenels over the gate, a shield crest, turrets ----------
local function citadel(f: Instance, at: CFrame, i: number)
	local P = TT.stations.citadel
	kit(f, at, P, 2.4)
	local tw = 1.8
	for _, s in { -1, 1 } do
		local tower = at * CFrame.new(s * GX, 4.3, GZ)
		block(Vector3.new(tw, 8.6, tw), tower, P.body, f, true)
		edgeFrame(f, tower, Vector3.new(tw, 8.6, tw), P.neon, true)
		block(Vector3.new(2.2, 1.0, 2.2), at * CFrame.new(s * GX, 0.5, GZ), P.bodyDark, f, true)
		block(Vector3.new(2.3, 0.4, 2.3), at * CFrame.new(s * GX, 8.8, GZ), P.bodyDark, f)
		for _, cx in { -1, 1 } do
			for _, cz in { -1, 1 } do
				block(Vector3.new(0.6, 0.8, 0.6), at * CFrame.new(s * GX + cx * 0.85, 9.4, GZ + cz * 0.85), P.body, f)
				snowCap(f, at * CFrame.new(s * GX + cx * 0.85, 9.8, GZ + cz * 0.85), 0.6, 0.6, P.snow)
			end
		end
		for _, side in { -1, 1 } do
			quiet(glow(block(Vector3.new(0.26, 1.1, 0.06), at * CFrame.new(s * GX, 6.6, GZ + side * (tw / 2 + 0.02)), P.accent, f), 0.1))
		end
	end
	doorway(f, at, 6.9, P.panel)
	local wall = at * CFrame.new(0, 8.0, GZ)
	local wallSize = Vector3.new(2 * (GX - tw / 2), 2.2, 1.4)
	block(wallSize, wall, P.body, f)
	edgeFrame(f, wall, wallSize, P.neon, true)
	for _, x in { -2.8, -1.4, 1.4, 2.8 } do
		block(Vector3.new(0.8, 0.8, 1.4), wall * CFrame.new(x, 1.5, 0), P.body, f)
		snowCap(f, wall * CFrame.new(x, 1.9, 0), 0.8, 1.4, P.snow)
	end
	-- the portcullis's teeth under the wall
	for k = 0, 7 do
		local x = -2.8 + k * 0.8
		quiet(block(Vector3.new(0.14, 1.0, 0.14), at * CFrame.new(x, 6.4, GZ + 0.3), P.gold, f))
		quiet(shape("Cone", Vector3.new(0.24, 0.35, 0.24), at * CFrame.new(x, 5.75, GZ + 0.3) * CFrame.Angles(math.pi, 0, 0), P.gold, f))
	end
	-- banners on the wall, front and back
	for _, side in { -1, 1 } do
		for _, s in { -1, 1 } do
			local bn = at * CFrame.new(s * 2.1, 8.0, GZ + side * 0.74)
			quiet(block(Vector3.new(0.9, 1.6, 0.06), bn, P.banner, f))
			quiet(tri(f, bn * CFrame.new(0, -0.8, 0) * CFrame.Angles(0, 0, math.pi), 1, 0.45, 0.5, 0.06, P.banner))
			quiet(tri(f, bn * CFrame.new(0, -0.8, 0) * CFrame.Angles(0, 0, math.pi), -1, 0.45, 0.5, 0.06, P.banner))
			quiet(glow(block(Vector3.new(0.3, 0.3, 0.08), bn * CFrame.new(0, 0.2, 0) * CFrame.Angles(0, 0, math.pi / 4), P.body, f)))
		end
	end
	-- the shield crest with a crown on top
	local sh = at * CFrame.new(0, 10.5, GZ)
	block(Vector3.new(2.2, 1.8, 0.5), sh, P.gold, f)
	isoTri(f, sh * CFrame.new(0, -0.9, 0) * CFrame.Angles(0, 0, math.pi), 1.1, 1.3, 0.5, P.gold)
	block(Vector3.new(1.8, 1.5, 0.56), sh * CFrame.new(0, 0.05, 0), P.body, f)
	isoTri(f, sh * CFrame.new(0, -0.7, 0) * CFrame.Angles(0, 0, math.pi), 0.9, 1.05, 0.56, P.body)
	for _, side in { -1, 1 } do
		flake(f, sh * CFrame.new(0, -0.15, side * 0.31) * (if side > 0 then CFrame.Angles(0, math.pi, 0) else CFrame.identity), 1.3, P.accent)
	end
	block(Vector3.new(1.6, 0.35, 0.5), sh * CFrame.new(0, 1.05, 0), P.gold, f)
	for _, x in { -0.6, 0, 0.6 } do
		isoTri(f, sh * CFrame.new(x, 1.2, 0), 0.22, if x == 0 then 0.7 else 0.5, 0.4, P.gold)
	end
	quiet(glow(ball(0.12, pt(sh, 0, 1.95, 0), P.accent, f)))
	-- turrets with cone roofs and gold pennants behind the gate's shoulders
	for _, s in { -1, 1 } do
		local b = at * CFrame.new(s * 5.6, 0, 7.6)
		cyl(0.85, 6.0, b * CFrame.new(0, 3.0, 0), P.body, f, true)
		quiet(glow(cyl(0.9, 0.12, b * CFrame.new(0, 5.9, 0), P.neon, f)))
		cyl(1.05, 0.3, b * CFrame.new(0, 6.1, 0), P.bodyDark, f)
		shape("Cone", Vector3.new(2.3, 2.4, 2.3), b * CFrame.new(0, 7.45, 0), P.roof, f)
		quiet(shape("Cone", Vector3.new(1.2, 1.25, 1.2), b * CFrame.new(0, 8.05, 0), P.snow, f))
		cyl(0.07, 1.4, b * CFrame.new(0, 9.2, 0), P.gold, f)
		tri(f, b * CFrame.new(0, 9.35, 0), s, 1.2, 0.6, 0.06, P.banner)
		quiet(glow(block(Vector3.new(0.22, 0.9, 0.06), b * CFrame.new(0, 4.0, -0.86), P.accent, f), 0.1))
	end

	-- the Knight: polished armour, a crimson tabard with a snowflake, a shield and a sword, a plumed helm
	local foot = at * CFrame.new(0, H, tz)
	local m = target(f, i)
	cyl(1.7, 0.35, foot * CFrame.new(0, 0.175, 0), P.bodyDark, m)
	quiet(glow(cyl(1.78, 0.08, foot * CFrame.new(0, 0.3, 0), P.neon, m)))
	for _, s in { -1, 1 } do
		named(block(Vector3.new(0.8, 2.3, 0.9), foot * CFrame.new(s * 0.55, 1.6, 0), P.armor, m), "Heat")
		block(Vector3.new(0.9, 0.45, 1.3), foot * CFrame.new(s * 0.55, 0.58, -0.15), P.armorDark, m)
		ball(0.32, pt(foot, s * 0.55, 1.9, -0.45), P.armorDark, m)
		named(ellipsoid(Vector3.new(1.3, 0.9, 1.6), foot * CFrame.new(s * 1.45, 5.45, 0), P.armor, m), "Heat")
		named(block(Vector3.new(0.7, 2.2, 0.8), foot * CFrame.new(s * 1.55, 4.2, 0), P.armorDark, m), "Heat")
		ball(0.42, pt(foot, s * 1.55, 3.0, 0), P.armorDark, m)
	end
	named(block(Vector3.new(2.6, 2.8, 1.7), foot * CFrame.new(0, 4.1, 0), P.armor, m), "Heat")
	named(block(Vector3.new(1.9, 3.2, 0.12), foot * CFrame.new(0, 3.65, -0.9), P.body, m), "Heat")
	for _, s in { -1, 1 } do
		quiet(block(Vector3.new(0.12, 3.2, 0.14), foot * CFrame.new(s * 0.95, 3.65, -0.9), P.gold, m))
	end
	quiet(block(Vector3.new(1.9, 0.12, 0.14), foot * CFrame.new(0, 2.05, -0.9), P.gold, m))
	flake(m, foot * CFrame.new(0, 4.25, -0.98), 1.0, P.neon)
	block(Vector3.new(2.7, 0.35, 1.8), foot * CFrame.new(0, 2.95, 0), P.leather, m)
	-- the shield on the left arm
	local shield = foot * CFrame.new(-2.05, 4.2, -0.55) * CFrame.Angles(0, 0.3, 0)
	block(Vector3.new(1.6, 1.4, 0.25), shield, P.gold, m)
	isoTri(m, shield * CFrame.new(0, -0.7, 0) * CFrame.Angles(0, 0, math.pi), 0.8, 1.0, 0.25, P.gold)
	heat({ block(Vector3.new(1.3, 1.15, 0.3), shield * CFrame.new(0, 0.05, 0), P.body, m) })
	heat(isoTri(m, shield * CFrame.new(0, -0.55, 0) * CFrame.Angles(0, 0, math.pi), 0.65, 0.8, 0.3, P.body))
	flake(m, shield * CFrame.new(0, -0.1, -0.17), 0.8, P.neon)
	-- the sword in the right hand
	local sword = foot * CFrame.new(1.55, 0, -0.7)
	block(Vector3.new(0.28, 2.8, 0.1), sword * CFrame.new(0, 4.95, 0), P.blade, m)
	block(Vector3.new(0.95, 0.2, 0.22), sword * CFrame.new(0, 3.5, 0), P.gold, m)
	block(Vector3.new(0.2, 0.6, 0.2), sword * CFrame.new(0, 3.1, 0), P.leather, m)
	ball(0.16, pt(sword, 0, 2.75, 0), P.gold, m)
	-- the helm: a great helm with a glowing visor slit, a gold band, a red plume
	named(cyl(0.95, 1.7, foot * CFrame.new(0, 6.5, 0), P.armor, m), "Heat")
	ellipsoid(Vector3.new(1.9, 1.0, 1.9), foot * CFrame.new(0, 7.35, 0), P.armor, m)
	quiet(cyl(0.98, 0.18, foot * CFrame.new(0, 7.1, 0), P.gold, m))
	quiet(glow(block(Vector3.new(1.2, 0.18, 0.1), foot * CFrame.new(0, 6.65, -0.94), P.eye, m)))
	quiet(block(Vector3.new(0.18, 0.9, 0.1), foot * CFrame.new(0, 6.3, -0.96), P.armorDark, m))
	ellipsoid(Vector3.new(0.5, 1.2, 1.6), foot * CFrame.new(0, 8.05, 0.3) * CFrame.Angles(0.35, 0, 0), P.plume, m)
	sealTarget(m, foot)
	targetBlock(f, foot * CFrame.new(0, 4.3, 0), Vector3.new(4.6, 8.6, 3))
end

-- ---------- 10. North Star: a starry arch, a turning compass star, garland trees, the Star Spirit ----------
local NIGHT = { { -2.6, 2.2 }, { -1.4, 4.6 }, { -3.0, 5.6 }, { 1.2, 1.6 }, { 2.7, 3.4 }, { 0.3, 6.4 }, { -0.6, 3.0 }, { 2.0, 5.9 }, { -2.0, 7.4 }, { 1.6, 7.6 }, { 3.1, 1.2 }, { -3.2, 1.1 } }
local function northStar(f: Instance, at: CFrame, i: number)
	local P = TT.stations.northstar
	kit(f, at, P, 2.6)
	local top = 6.6
	local spring = top + 0.4
	for _, s in { -1, 1 } do
		pillar(f, at, s * GX, top, P, true)
		glowAll(star(f, at * CFrame.new(s * GX, top + 1.2, GZ), 0.6, 0.18, 0.2, P.neon, 4))
	end
	doorway(f, at, spring, P.panel)
	rod(0.12, GX - 0.6, at * CFrame.new(0, spring, PANEL_Z + 0.03) * FACE, P.panel, f)
	for _, n in NIGHT do
		quiet(glow(block(Vector3.new(0.16, 0.16, 0.05), at * CFrame.new(n[1], n[2], PANEL_Z - 0.08) * CFrame.Angles(0, 0, math.pi / 4), P.accent, f)))
	end
	local c = at * CFrame.new(0, spring, GZ)
	archOf(f, c, 7, P.body, P.bodyLight, P.neon)
	for _, a in { 0.4, 0.85, math.pi - 0.85, math.pi - 0.4 } do
		for _, side in { -1, 1 } do
			glowAll(star(f, c * CFrame.new(GX * math.cos(a), GX * math.sin(a), side * 0.68), 0.36, 0.14, 0.08, P.neon, 5))
		end
	end
	-- the compass star: a gold ring, a navy disc, a turning eight-pointed star (MapController turns it)
	local cAt = c * CFrame.new(0, GX + 0.45, 0)
	shape("Ring", Vector3.new(3.4, 0.35, 3.4), cAt * CFrame.Angles(math.pi / 2, 0, 0), P.gold, f)
	rod(0.3, 1.55, cAt * FACE, P.bodyDark, f)
	local spin = spinner(f, cAt, Vector3.new(0, 0, 1), 0.35)
	star(spin, cAt, 2.1, 0.42, 0.5, P.gold, 4)
	star(spin, cAt * CFrame.Angles(0, 0, math.pi / 4), 1.35, 0.32, 0.56, P.goldLight, 4)
	local core = quiet(glow(ball(0.32, cAt.Position, P.accent, spin)))
	light(core, P.gold, 14, 0.9)
	-- garland trees behind the gate's shoulders: a gold garland wound round, a star on top
	for _, s in { -1, 1 } do
		local b = at * CFrame.new(s * FLANK.x, 0, FLANK.z + 0.3)
		cyl(0.3, 1.3, b * CFrame.new(0, 0.65, 0), P.bodyDark, f, true)
		shape("Cone", Vector3.new(3.4, 6.4, 3.4), b * CFrame.new(0, 1.2 + 3.2, 0), P.tree, f)
		quiet(shape("Cone", Vector3.new(1.4, 2.4, 1.4), b * CFrame.new(0, 6.4, 0), P.snow, f))
		for k = 0, 26 do
			local t = k / 26
			local y = 1.5 + t * 5.2
			local r = 1.7 * (1 - (y - 1.2) / 6.4) + 0.1
			local a = t * math.pi * 6 + (if s > 0 then 0 else math.pi)
			quiet(glow(ball(0.13, pt(b, r * math.cos(a), y, r * math.sin(a)), P.neon, f)))
		end
		glowAll(star(f, b * CFrame.new(0, 8.0, 0), 0.75, 0.3, 0.25, P.neon, 5))
	end

	-- the Star Spirit: a big golden star with a happy face, a glowing halo, standing on a cloud
	local foot = at * CFrame.new(0, H, tz)
	local m = target(f, i)
	cyl(1.7, 0.35, foot * CFrame.new(0, 0.175, 0), P.bodyDark, m)
	for _, p in { { -0.9, 1.0, 0, 0.85 }, { 0.9, 1.0, 0, 0.85 }, { 0, 1.25, 0.3, 0.95 }, { 0, 0.95, -0.6, 0.75 }, { -0.6, 0.8, 0.7, 0.7 }, { 0.6, 0.8, 0.7, 0.7 } } do
		ball(p[4], pt(foot, p[1], p[2], p[3]), P.cloud, m)
	end
	local sc = foot * CFrame.new(0, 4.9, 0)
	heat(glowAll(star(m, sc * CFrame.new(0, 0, 0.2), 3.3, 1.5, 0.9, P.neon, 5), 0.45))
	local body = heat(star(m, sc, 3.0, 1.35, 1.1, P.gold, 5))
	light(body[1], P.gold, 14, 1)
	face(m, sc * CFrame.new(0, 0.1, -0.6), 0.55, 0.26, P)
	sparkles(m, Vector3.new(4.5, 4.5, 1), sc, P.neon, 6, 1.2, 0.3)
	sealTarget(m, foot)
	targetBlock(f, foot * CFrame.new(0, 3.9, 0), Vector3.new(4.4, 7.8, 2.2))
end

local BUILDERS: { [string]: (Instance, CFrame, number) -> () } = {
	snowman = frostArch,
	peppermint = peppermint,
	gingerbread = gingerbread,
	workshop = workshop,
	ice = iceGate,
	reindeer = reindeer,
	crystal = crystalGate,
	aurora = aurora,
	citadel = citadel,
	northstar = northStar,
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
	MapArt.solidify(f) -- solid like the rest of the map (owner 2026-11-12)
	f.Parent = parent
	return f
end

-- ADMIN TRAINER dress (owner 2026-11-18, Config.admin.trainer): while an admin trainer runs, every pan's trainer
-- gets a gold neon frame round its pad, a gold beam into the sky (seen from far away, like the speed sims'
-- admin treadmills), gold sparkles and a big "ADMIN TRAINER xN" sign. Added to the trainer's folder `f`.
function TrainingArt.adminDress(f: Folder, plot: number, mult: number)
	local d = folder("AdminDress", f)
	local gold = Color3.fromRGB(255, 205, 40)
	local at = Config.trainerFrame(plot)
	local y = H + 0.12
	for _, e in { { 0, D / 2, W + 0.6, 0.5 }, { 0, -D / 2, W + 0.6, 0.5 }, { W / 2, 0, 0.5, D + 0.6 }, { -W / 2, 0, 0.5, D + 0.6 } } do
		glow(quiet(block(Vector3.new(e[3], 0.3, e[4]), at * CFrame.new(e[1], y, e[2]), gold, d)))
	end
	local beam = glow(quiet(cyl(2.2, 140, at * CFrame.new(0, 70, T.targetZ), gold, d)), 0.65)
	beam.CanQuery = false
	light(beam, gold, 22, 2)
	sparkles(d, Vector3.new(W, 1, D), at * CFrame.new(0, H + 0.5, 0), gold, 18, 4, 0.5)
	local anchor = quiet(block(Vector3.one * 0.2, at * CFrame.new(0, H + 13, T.targetZ), gold, d))
	anchor.Transparency = 1
	anchor.CanQuery = false
	local bb = Instance.new("BillboardGui")
	bb.Name = "AdminSign"
	bb.Size = UDim2.fromScale(14, 5)
	bb.MaxDistance = 220
	bb.LightInfluence = 0
	bb.AlwaysOnTop = false
	bb.Parent = anchor
	local function label(text: string, y0: number, h: number, color: Color3)
		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1
		t.Size = UDim2.fromScale(1, h)
		t.Position = UDim2.fromScale(0, y0)
		t.Font = Theme.font
		t.TextScaled = true
		t.Text = text
		t.TextColor3 = color
		local s = Instance.new("UIStroke")
		s.Thickness = 3
		s.Color = Color3.fromRGB(90, 40, 0)
		s.Parent = t
		t.Parent = bb
	end
	label("ADMIN TRAINER", 0, 0.42, gold)
	label(`x{mult} POWER!`, 0.42, 0.58, Color3.fromRGB(255, 255, 255))
end

-- ---------- the Magma Trainer (owner 2026-11-22, Config.training.robux) ----------
-- From the owner's reference clip: a lava forge on a black stone stage. Oxblood voxel blocks with molten
-- cracks, a yellow-white energy column out of the forge, fire in two lava basins and on the chimneys, embers
-- over the pad and violet-white spark bursts at the forge's shoulders, under a big sign with the Robux price.
-- One shared trainer in the hub, right of the leaderboards. Same pad size and target spot as every trainer, so
-- the lock, the frost shell and the bolts work unchanged. One PointLight, a handful of emitters (phones).
local MR = T.robux

-- ---------- the Magma Trainer, Omega look (owner 2026-11-23: "omega style ... much more cooler looking ... add some vfx") ----------
-- One shared trainer in the hub, right of the leaderboards (Config.training.robux). Same pad, stand slots and
-- target spot as every trainer, so the lock, the frost shell and the bolts work unchanged. On top:
--   the Omega gate: a giant obsidian Ω ring behind the golem (molten inner edge, gold outer edge), a lava and
--     violet portal inside it with a swirling vortex, two rings of gold runes and violet crystals spinning round
--     it (MapController's motion folders), a gold crown with a floating crystal and a beam into the sky
--   the Omega Titan: an obsidian golem in gold armour (pauldrons with spikes, gauntlets, crown helm, horns),
--     violet eyes and a molten core
--   four obelisks with floating crystals whose lightning (Beams named Zap, crackled by TrainingController)
--     arcs into the ring; fire in the basins; gold shockwaves from the golem's feet; a spinning rune circle on
--     the floor; rising embers
-- Particles use Roblox's own textures (no uploads). Two PointLights; one shared trainer, so it stays light.
-- Tech look (owner 2026-11-23, a reference clip): dark navy plates, red glow strips, fins, floor tiles, red stars and
-- black-red tendrils; it replaced the stone "realism" pass. Turned 45 degrees to face the plaza (robux.yaw).

-- Roblox's built-in particle textures
local TEX = {
	fire = "rbxasset://textures/particles/fire_main.dds",
	sparks = "rbxasset://textures/particles/fire_sparks_main.dds",
	glint = "rbxasset://textures/particles/sparkles_main.dds",
	shock = "rbxasset://textures/particles/explosion01_shockwave_main.dds",
	vortex = "rbxasset://textures/particles/forcefield_vortex_main.dds",
	smoke = "rbxasset://textures/particles/smoke_main.dds",
}

type Fx = {
	tex: string?, c0: Color3, c1: Color3, size: { number }, rate: number, life: { number }, speed: { number },
	spread: number?, accel: Vector3?, rot: number?, flat: boolean?, dir: Enum.NormalId?, alpha: number?,
}

-- an invisible box that emits particles
local function fxBox(f: Instance, size: Vector3, cf: CFrame): BasePart
	local p = quiet(block(size, cf, Theme.white, f))
	p.Name = "Fx"
	p.Transparency = 1
	p.CanQuery = false
	return p
end

-- flat = lying flat to its direction (a shockwave on the floor); size = { start, end }
local function emit(p: BasePart, o: Fx): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	if o.tex then
		e.Texture = o.tex
	end
	e.Shape = Enum.ParticleEmitterShape.Box
	e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	e.EmissionDirection = o.dir or Enum.NormalId.Top
	e.Color = ColorSequence.new(o.c0, o.c1)
	e.LightEmission = 1
	e.LightInfluence = 0
	e.Size = NumberSequence.new(o.size[1], o.size[2] or o.size[1] * 0.2)
	local a = o.alpha or 0.1
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, a), NumberSequenceKeypoint.new(0.7, math.min(1, a + 0.3)), NumberSequenceKeypoint.new(1, 1) })
	e.Lifetime = NumberRange.new(o.life[1], o.life[2])
	e.Rate = o.rate
	e.Speed = NumberRange.new(o.speed[1], o.speed[2])
	e.SpreadAngle = Vector2.new(o.spread or 0, o.spread or 0)
	e.Acceleration = o.accel or Vector3.zero
	local r = o.rot or 0
	e.RotSpeed = NumberRange.new(-r, r)
	e.Rotation = NumberRange.new(0, 360)
	if o.flat then
		e.Orientation = Enum.ParticleOrientation.VelocityPerpendicular
	end
	e.Parent = p
	return e
end

-- real fire with sparks falling out of it (basins)
local function flames(f: Instance, cf: CFrame, w: number, P: Palette, rate: number)
	local p = fxBox(f, Vector3.new(w, 0.2, w), cf)
	emit(p, { tex = TEX.fire, c0 = P.lavaHot, c1 = P.crimson, size = { w * 1.4, w * 0.3 }, rate = rate, life = { 0.5, 0.9 },
		speed = { 2.5, 4.5 }, spread = 10, accel = Vector3.new(0, 4, 0), rot = 60, alpha = 0.15 })
	emit(p, { tex = TEX.sparks, c0 = P.goldHi, c1 = P.lava, size = { 0.5, 0.1 }, rate = rate * 0.6, life = { 0.6, 1.2 },
		speed = { 4, 7 }, spread = 25, accel = Vector3.new(0, -6, 0) })
	-- dark smoke curling up out of it (realism pass)
	local sm = emit(p, { tex = TEX.smoke, c0 = P.smoke, c1 = P.basalt, size = { w * 1.2, w * 4 }, rate = rate * 0.2, life = { 3, 4.5 },
		speed = { 1.5, 2.5 }, spread = 12, accel = Vector3.new(0.4, 0.6, 0), rot = 25, alpha = 0.55 })
	sm.LightEmission = 0
	sm.LightInfluence = 1
end

-- one block of the golem that frosts over as you shoot (the client cools parts named Heat)
local function heatBlock(m: Instance, size: Vector3, cf: CFrame, color: Color3): BasePart
	return named(block(size, cf, color, m), "Heat")
end

-- a thin molten crack on a face (cf = its middle, already turned)
local function crack(m: Instance, len: number, cf: CFrame, color: Color3)
	quiet(glow(block(Vector3.new(0.14, len, 0.06), cf, color, m)))
end

-- a pointed ridge, `h` tall on cf (two wedges back to back across cf's Z)
local function spike(f: Instance, cf: CFrame, w: number, h: number, d: number, color: Color3)
	wedge(Vector3.new(w, h, d / 2), cf * CFrame.new(0, h / 2, d / 4) * CFrame.Angles(0, math.pi, 0), color, f)
	wedge(Vector3.new(w, h, d / 2), cf * CFrame.new(0, h / 2, -d / 4), color, f)
end

-- a violet crystal floating and bobbing at cf; returns the crystal (lightning leaves from it)
local function crystal(f: Instance, cf: CFrame, size: Vector3, P: Palette, phase: number): BasePart
	local c = quiet(glow(shape("Octa", size, cf, P.violetHi, bobber(f, cf, 0.3, 0.45, phase)), 0.05))
	c.Name = "Crystal"
	return c
end

-- lightning from a to b: off until TrainingController crackles it (new bend each flicker)
local function zap(from: Attachment, to: Attachment, P: Palette)
	local bm = Instance.new("Beam")
	bm.Name = "Zap"
	bm.Attachment0, bm.Attachment1 = from, to
	bm.Color = ColorSequence.new(P.violetHi, P.violet) -- white-to-violet vanished against the daytime sky
	bm.LightEmission = 1
	bm.LightInfluence = 0
	bm.Width0, bm.Width1 = 0.5, 0.25
	bm.Segments = 14
	bm.FaceCamera = true
	bm.Enabled = false
	bm.Parent = from.Parent
end

local function attach(p: BasePart, at: Vector3?): Attachment
	local a = Instance.new("Attachment")
	if at then
		a.WorldPosition = at
	end
	a.Parent = p
	if at then
		a.WorldPosition = at
	end
	return a
end

-- the Omega Titan, sharp (owner 2026-11-23: "make the guy in the middle more sharp, not a squared character"):
-- built from triangles and blades, not boxes. A V torso to a narrow waist, an inverted-triangle chest plate with a
-- molten diamond core, blade legs to pointed feet with knee spikes, angled shoulder blades with spikes, blade arms,
-- a diamond helm with a crest, swept horns and slanted eye slits. Faces the stand spot (local -Z), foot at `foot`.
-- Everything solid is named Heat so it frosts over as you shoot (TrainingController). Its outline (shoulders,
-- horns, crest) is dark so it stands out against the red portal behind it; red only inside and on the edges.
local function omegaTitan(f: Instance, station: number, foot: CFrame, P: Palette)
	local m = target(f, station)
	local function at(x: number, y: number, z: number): CFrame
		return foot * CFrame.new(x, y, z)
	end
	local DOWN = CFrame.Angles(0, 0, math.pi) -- an isoTri pointing down
	local FLAT = CFrame.Angles(-math.pi / 2, 0, 0) -- a triangle lying on the floor, its apex forward
	local function hot(parts: { BasePart }): { BasePart }
		return heat(parts)
	end
	-- the V torso, the waist and the chest plate
	hot(isoTri(m, at(0, 6.5, 0) * DOWN, 2.1, 3.1, 2.0, P.obsidian))
	hot(isoTri(m, at(0, 3.7, 0) * DOWN, 1.3, 1.0, 1.7, P.obsidianHi))
	hot(isoTri(m, at(0, 6.3, -1.08) * DOWN, 1.55, 2.3, 0.3, P.crimson))
	heatBlock(m, Vector3.new(3.6, 0.35, 2.05), at(0, 6.35, 0), P.obsidianHi) -- the collar
	local core = quiet(glow(block(Vector3.new(0.9, 0.9, 0.22), at(0, 5.3, -1.3) * CFrame.Angles(0, 0, math.pi / 4), P.core, m)))
	quiet(glow(block(Vector3.new(1.35, 1.35, 0.1), at(0, 5.3, -1.24) * CFrame.Angles(0, 0, math.pi / 4), P.lavaHot, m), 0.35))
	light(core, P.lava, 11, 1.6)
	for _, s in { -1, 1 } do
		-- molten lines down the V
		crack(m, 2.2, at(s * 0.95, 5.0, -1.1) * CFrame.Angles(0, 0, s * 0.62), P.lava)
		-- legs: a thigh, a blade shin pointing down, a knee spike forward, a pointed foot
		heatBlock(m, Vector3.new(1.0, 1.5, 1.3), at(s * 1.0, 3.0, 0) * CFrame.Angles(0, 0, s * 0.12), P.obsidianHi)
		hot(isoTri(m, at(s * 1.1, 2.45, 0) * DOWN, 0.75, 1.95, 1.3, P.obsidian))
		local knee = at(s * 1.1, 2.3, -0.62) * CFrame.Angles(-math.pi / 2, 0, 0)
		spike(m, knee, 0.45, 0.9, 0.5, P.crimson)
		hot(isoTri(m, at(s * 1.1, 0.42, 0.5) * FLAT, 0.75, 1.9, 0.45, P.obsidianHi))
		crack(m, 1.4, at(s * 1.1, 1.6, -0.68), P.lava)
		-- shoulders: an angled blade with a spike sweeping up and out
		hot({ tri(m, at(s * 1.5, 5.75, 0), s, 1.9, 1.5, 2.1, P.obsidianHi) })
		crack(m, 2.2, at(s * 2.45, 6.5, -1.08) * CFrame.Angles(0, 0, s * 0.9), P.lava) -- the blade's molten edge
		spike(m, at(s * 2.7, 6.3, 0) * CFrame.Angles(0, 0, -s * 0.75), 0.4, 1.7, 0.9, P.obsidianHi)
		-- arms: a short upper arm, a blade forearm pointing down, a molten edge
		heatBlock(m, Vector3.new(0.85, 1.3, 1.0), at(s * 2.75, 5.1, 0) * CFrame.Angles(0, 0, s * 0.15), P.obsidian)
		hot(isoTri(m, at(s * 2.9, 4.45, 0) * DOWN, 0.6, 2.7, 0.9, P.obsidianHi))
		crack(m, 2.0, at(s * 2.9 + s * 0.28, 3.4, -0.47) * CFrame.Angles(0, 0, -s * 0.2), P.lava)
		-- horns sweeping back and out, red-tipped; slanted eye slits
		local horn = at(s * 0.55, 8.1, 0.1) * CFrame.Angles(0, 0, -s * 0.85)
		spike(m, horn, 0.35, 1.6, 0.5, P.obsidianHi)
		quiet(glow(block(Vector3.new(0.14, 0.5, 0.2), horn * CFrame.new(0, 1.25, 0), P.lava, m))) -- red tip
		quiet(glow(block(Vector3.new(0.6, 0.12, 0.1), at(s * 0.36, 7.5, -0.78) * CFrame.Angles(0, 0, s * 0.38), P.eye, m)))
	end
	-- the helm: a diamond (a point up, a point down), a crest on top
	hot(isoTri(m, at(0, 7.3, 0) * DOWN, 0.85, 0.85, 1.5, P.obsidian))
	hot(isoTri(m, at(0, 7.3, 0), 0.85, 1.45, 1.5, P.obsidian))
	hot(isoTri(m, at(0, 7.45, -0.76), 0.55, 0.9, 0.08, P.crimson)) -- a face plate
	spike(m, at(0, 8.5, 0), 0.3, 1.0, 1.2, P.obsidianHi)
	quiet(glow(block(Vector3.new(0.12, 0.6, 1.25), at(0, 8.8, 0), P.lava, m))) -- the crest's red blade
	sealTarget(m, foot)
	targetBlock(f, foot * CFrame.new(0, 4.6, 0), Vector3.new(4.2, 8.4, 2.6))
end

-- the Omega gate behind the golem; returns the lightning's landing points on the ring
local function omegaGate(f: Instance, at: CFrame, P: Palette): { [string]: Attachment }
	local z, cy, R = 7.0, 12, 8 -- R 8 (was 6.8): a landmark beside the 24-stud boards
	local C = at * CFrame.new(0, cy, z) -- the ring's middle (local X right, Y up)
	local a0, a1, n = math.rad(-50), math.rad(230), 20
	local step = (a1 - a0) / n
	local chord = 2 * R * math.sin(step / 2)
	for k = 0, n - 1 do
		local cf = C * CFrame.Angles(0, 0, a0 + (k + 0.5) * step) * CFrame.new(R, 0, 0) -- X out from the middle
		block(Vector3.new(1.5, chord + 0.25, 1.6), cf, if k % 2 == 0 then P.obsidian else P.obsidianHi, f, true)
		quiet(glow(block(Vector3.new(0.18, chord + 0.05, 1.7), cf * CFrame.new(-0.8, 0, 0), P.lava, f))) -- molten inner edge
		quiet(glow(block(Vector3.new(0.22, chord + 0.05, 1.7), cf * CFrame.new(0.8, 0, 0), P.gold, f))) -- gold outer edge
		-- angular fins breaking out of the ring's rim, longer toward the top, each with a red blade core (tech look)
		if k % 2 == 1 then
			local up = math.max(0, math.sin(a0 + (k + 0.5) * step))
			local len = 1.4 + up * 1.8
			local fin = cf * CFrame.new(0.85, 0, 0) * CFrame.Angles(0, 0, -math.pi / 2) -- its Y points out of the ring
			spike(f, fin, 0.5, len, 1.3, P.obsidianHi)
			quiet(glow(block(Vector3.new(0.12, len * 0.6, 1.35), fin * CFrame.new(0, len * 0.3, 0), P.lava, f)))
		end
	end
	-- the Ω's legs down to the ground and its feet stepping out
	local ex, ey = R * math.cos(a0), R * math.sin(a0)
	local legH = cy + ey
	for _, s in { -1, 1 } do
		local x = s * ex
		block(Vector3.new(1.5, legH, 1.6), at * CFrame.new(x, legH / 2, z), P.obsidian, f, true)
		quiet(glow(block(Vector3.new(0.18, legH, 1.7), at * CFrame.new(x - s * 0.8, legH / 2, z), P.lava, f)))
		quiet(glow(block(Vector3.new(0.22, legH, 1.7), at * CFrame.new(x + s * 0.8, legH / 2, z), P.gold, f)))
		block(Vector3.new(3.4, 1.1, 2.2), at * CFrame.new(x + s * 1.2, 0.55, z), P.brass, f, true)
		quiet(block(Vector3.new(3.6, 0.3, 2.4), at * CFrame.new(x + s * 1.2, 1.25, z), P.obsidianHi, f))
	end
	-- the portal: crimson at its edge to a white-hot core (one fire, no pink: violet over orange read as pink), a
	-- swirling vortex, the main light
	local disc = quiet(glow(rod(0.2, R - 0.75, C * CFrame.Angles(0, math.pi / 2, 0), P.crimson, f), 0.3))
	disc.CanQuery = false
	light(disc, P.lavaHot, 24, 2.2)
	-- tech look: red and near-black rings like a reactor (one flat red disc didn't match the reference's dark-with-red)
	for k, d in { { R - 2.4, P.panel, 0.1 }, { R - 3.2, P.lava, 0.3 }, { R - 4.6, P.panel, 0.1 }, { 1.4, P.core, 0.2 } } do
		local p = quiet(glow(rod(0.12, d[1], C * CFrame.new(0, 0, -0.18 * k) * CFrame.Angles(0, math.pi / 2, 0), d[2], f), d[3]))
		p.CanQuery = false
	end
	local vb = fxBox(f, Vector3.new(1, 1, 0.2), C * CFrame.new(0, 0, -0.5))
	emit(vb, { tex = TEX.vortex, c0 = P.goldHi, c1 = P.lava, size = { 9, 12 }, rate = 2.5, life = { 2, 2.6 }, speed = { 0, 0 }, rot = 90, alpha = 0.3 })
	-- two rings spinning round it: gold runes one way, violet crystals the other
	local ring1 = spinner(f, C, Vector3.new(0, 0, 1), 0.45)
	for k = 0, 15 do
		quiet(glow(block(Vector3.new(1.1, 0.4, 0.4), C * CFrame.Angles(0, 0, k * math.pi / 8) * CFrame.new(R + 1.9, 0, 0),
			if k % 4 == 0 then P.violetHi else P.gold, ring1)))
	end
	local ring2 = spinner(f, C, Vector3.new(0, 0, 1), -0.25)
	for k = 0, 7 do
		quiet(glow(shape("Octa", Vector3.new(0.9, 1.8, 0.9), C * CFrame.Angles(0, 0, k * math.pi / 4 + 0.2) * CFrame.new(R + 3.2, 0, 0), P.violet, ring2), 0.05))
	end
	-- the crown: three gold spikes, a floating crystal, the beam into the sky
	local top = C * CFrame.new(0, R + 0.7, 0)
	for _, x in { -1.1, 0, 1.1 } do
		spike(f, top * CFrame.new(x, 0, 0), 0.5, if x == 0 then 2.4 else 1.5, 1.2, P.gold)
	end
	local crys = top * CFrame.new(0, 4.2, 0)
	crystal(f, crys, Vector3.new(1.6, 3, 1.6), P, 0)
	-- the beam into the sky (owner 2026-11-23: "make this light beam go up to the sky, it looks cheap like this"):
	-- Beams instead of a 40-stud cylinder that stopped in mid-air, so it reaches robux.skyBeam.height and fades out.
	-- A wide red glow round a white-hot core; sparks race up it.
	local baseY = (crys.Position - at.Position).Y + 1.8
	local root = quiet(block(Vector3.one * 0.2, at * CFrame.new(0, baseY, z), P.lava, f))
	root.Name = "SkyBeamRoot"
	root.Transparency = 1
	root.CanQuery = false
	local b0, b1 = Instance.new("Attachment"), Instance.new("Attachment")
	b1.Position = Vector3.new(0, MR.skyBeam.height, 0)
	b0.Parent, b1.Parent = root, root
	-- { width, colour, transparency at the bottom, light emission }: the glow is barely additive so it stays red
	-- against the bright daytime sky (fully additive it washed out to white-lavender in the play test)
	for _, l in { { MR.skyBeam.halo, P.lava, 0.2, 0.15 }, { MR.skyBeam.core, P.core, 0, 1 } } do
		local bm = Instance.new("Beam")
		bm.Name = "SkyBeam"
		bm.Attachment0, bm.Attachment1 = b0, b1
		bm.Width0, bm.Width1 = l[1], l[1] * 1.6
		bm.Color = ColorSequence.new(l[2])
		bm.LightEmission = l[4]
		bm.LightInfluence = 0
		bm.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, l[3]), NumberSequenceKeypoint.new(0.55, math.min(1, l[3] + 0.3)),
			NumberSequenceKeypoint.new(1, 1) })
		bm.FaceCamera = true
		bm.Segments = 1
		bm.Parent = root
	end
	local cs = fxBox(f, Vector3.new(1, 2, 1), at * CFrame.new(0, baseY + 1, z))
	emit(cs, { tex = TEX.glint, c0 = P.goldHi, c1 = P.violetHi, size = { 0.9, 0.2 }, rate = 18, life = { 3, 5 }, speed = { 30, 45 }, spread = 3 })
	-- where the lightning lands: four points on the ring
	local anchor = quiet(block(Vector3.one * 0.2, C, P.gold, f))
	anchor.Name = "ZapAnchor"
	anchor.Transparency = 1
	anchor.CanQuery = false
	local pts = {}
	for key, deg in { lowL = 205, lowR = -25, highL = 155, highR = 25 } do
		local a = math.rad(deg)
		pts[key] = attach(anchor, (C * CFrame.new(R * math.cos(a), R * math.sin(a), -0.9)).Position)
	end
	return pts
end

-- an obelisk on the plinth: obsidian, gold bands, a gold point, a crystal floating over it
local function obelisk(f: Instance, base: CFrame, P: Palette, phase: number): BasePart
	block(Vector3.new(1.8, 0.8, 1.8), base * CFrame.new(0, 0.4, 0), P.obsidianHi, f, true)
	block(Vector3.new(1.2, 4.2, 1.2), base * CFrame.new(0, 2.9, 0), P.obsidian, f, true)
	for _, y in { 1.6, 4.2 } do
		quiet(glow(block(Vector3.new(1.32, 0.24, 1.32), base * CFrame.new(0, y, 0), P.gold, f)))
	end
	for _, s in { -1, 1 } do
		quiet(glow(block(Vector3.new(0.14, 2.2, 0.14), base * CFrame.new(s * 0.6, 2.9, -0.6), P.lava, f)))
	end
	spike(f, base * CFrame.new(0, 5.0, 0), 1.2, 1.4, 1.2, P.brass)
	return crystal(f, base * CFrame.new(0, 7.4, 0), Vector3.new(0.9, 1.7, 0.9), P, phase)
end

-- the price sign over the gate (Child Safety: every Robux price shows Roblox's Robux mark, world offers too)
local function magmaSign(f: Instance, at: CFrame, P: Palette)
	local anchor = quiet(block(Vector3.one * 0.2, at * CFrame.new(0, H + MR.signLift, T.targetZ), P.lava, f))
	anchor.Name = "MagmaSignAnchor"
	anchor.Transparency = 1
	anchor.CanQuery = false
	local bb = Instance.new("BillboardGui")
	bb.Name = "MagmaSign"
	bb.Size = UDim2.fromScale(15, 6.4)
	bb.MaxDistance = MR.signMaxDistance
	bb.LightInfluence = 0
	bb.AlwaysOnTop = false
	bb.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	bb.Parent = anchor
	-- a dark plate with a gold rim behind the words (Chunky Pop: chunky outline, rounded)
	local plate = Instance.new("Frame")
	plate.Name = "Plate"
	plate.Size = UDim2.fromScale(1, 1)
	plate.BackgroundColor3 = P.obsidian
	plate.BackgroundTransparency = 0.15
	plate.Parent = bb
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.22, 0)
	corner.Parent = plate
	local rim = Instance.new("UIStroke")
	rim.Thickness = 4
	rim.Color = P.gold
	rim.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	rim.Parent = plate
	local pg = Instance.new("UIGradient")
	pg.Color = ColorSequence.new(P.obsidianHi, P.obsidian)
	pg.Rotation = 90
	pg.Parent = plate
	local function text(parent: Instance, s: string, size: UDim2, pos: UDim2, color: Color3, stroke: number, grad: Color3?): TextLabel
		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1
		t.Size = size
		t.Position = pos
		t.Font = Theme.font
		t.TextScaled = true
		t.Text = s
		t.TextColor3 = color
		t.ZIndex = 2
		local st = Instance.new("UIStroke")
		st.Thickness = stroke
		st.Color = P.signInk
		st.LineJoinMode = Enum.LineJoinMode.Round
		st.Parent = t
		if grad then
			local g = Instance.new("UIGradient")
			g.Color = ColorSequence.new(color, grad)
			g.Rotation = 90
			g.Parent = t
			t.TextColor3 = Theme.white
		end
		t.Parent = parent
		return t
	end
	text(plate, "MAGMA TRAINER", UDim2.fromScale(0.86, 0.2), UDim2.fromScale(0.07, 0.07), P.violetHi, 3, P.violet)
	text(plate, `x{MR.mult} COLD POWER`, UDim2.fromScale(0.9, 0.38), UDim2.fromScale(0.05, 0.27), P.goldHi, 4, P.lava)
	local row = Instance.new("Frame")
	row.Name = "Price"
	row.BackgroundTransparency = 1
	row.Size = UDim2.fromScale(1, 0.28)
	row.Position = UDim2.fromScale(0, 0.66)
	row.Parent = plate
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.Padding = UDim.new(0.02, 0)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = row
	-- Roblox's Robux mark, white with an ink contour (eight ink copies round a white one, as on the Shop's buttons)
	local mark = Instance.new("Frame")
	mark.Name = "RobuxMark"
	mark.BackgroundTransparency = 1
	-- a square by the sign's own shape (15 x 6.4 studs, the row 28% of it): no aspect constraint (play test
	-- 2026-11-23: inside the plate it collapsed to zero width and the price showed without its mark)
	mark.Size = UDim2.fromScale(0.9 * 0.28 * 6.4 / 15, 0.9)
	mark.LayoutOrder = 1
	for k = 0, 8 do
		local ang = k * math.pi / 4
		local img = Instance.new("ImageLabel")
		img.BackgroundTransparency = 1
		img.Image = Config.images.icons.robux
		img.ScaleType = Enum.ScaleType.Fit
		img.ImageColor3 = if k == 8 then Theme.white else P.signInk
		img.AnchorPoint = Vector2.new(0.5, 0.5)
		img.Position = if k == 8 then UDim2.fromScale(0.5, 0.5) else UDim2.fromScale(0.5 + math.cos(ang) * 0.06, 0.5 + math.sin(ang) * 0.06)
		img.Size = UDim2.fromScale(1, 1)
		img.ZIndex = if k == 8 then 3 else 2
		img.Parent = mark
	end
	mark.Parent = row
	local item = Config.robuxItem(MR.item)
	local price = text(row, tostring(item and item.robux or 0), UDim2.fromScale(0.3, 1), UDim2.fromScale(0, 0), Theme.white, 4)
	price.TextXAlignment = Enum.TextXAlignment.Left
	price.LayoutOrder = 2
end

-- ---------- tech look (owner 2026-11-23, reference: "try matching this style") ----------
-- A dark navy machine with thick glowing red panel strips, red star sparkles and black-red thorny energy. The
-- palette does most of it (Theme.training.stations.magma); these add the reference's details.

-- groove lines across the stage floor, so it reads as heavy tiles
local function floorTiles(f: Instance, at: CFrame, P: Palette)
	local y = H + 0.05
	for k = -3, 3 do
		quiet(block(Vector3.new(0.08, 0.02, D - 1.2), at * CFrame.new(k * 1.45, y, 0), P.panel, f))
	end
	for k = -3, 4 do
		quiet(block(Vector3.new(W - 1.2, 0.02, 0.08), at * CFrame.new(0, y, k * 1.45 - 0.7), P.panel, f))
	end
end

-- black-red thorny energy crawling out from the golem's feet: Beams named Zap, so TrainingController crackles them
-- with the lightning (a new bend every flicker). Returns how many.
local function tendrils(f: Instance, foot: CFrame, P: Palette): number
	local hub = quiet(block(Vector3.one * 0.2, foot * CFrame.new(0, 0.3, 0), P.lava, f))
	hub.Name = "TendrilHub"
	hub.Transparency = 1
	hub.CanQuery = false
	local from = attach(hub)
	local n = 6
	for k = 0, n - 1 do
		local tip = attach(hub, (foot * CFrame.Angles(0, k * math.pi * 2 / n + 0.3, 0) * CFrame.new(0, 0.15, 4.2)).Position)
		local bm = Instance.new("Beam")
		bm.Name = "Zap"
		bm.Attachment0, bm.Attachment1 = from, tip
		bm.Color = ColorSequence.new(P.violet, P.panel) -- deep red into black
		bm.LightEmission = 0.4
		bm.LightInfluence = 0
		bm.Width0, bm.Width1 = 0.6, 0.05
		bm.Segments = 16
		bm.FaceCamera = true
		bm.Enabled = false
		bm.Parent = hub
	end
	return n
end

-- the hub's Magma Trainer (Omega look) as one folder in `parent`. With `plot`: the same trainer standing in pan
-- `plot`'s trainer spot instead (its owner bought the pass, Config.panMagmaMult), named like a pan's trainer and
-- tagged with that pan's level `tier` (Show.trainerTrip puts back the folder whose Tier the map says), no price sign
function TrainingArt.magma(parent: Instance, plot: number?, tier: number?): Folder
	meshes = ReplicatedStorage:FindFirstChild("SceneryMeshes")
	local P = TT.stations.magma
	local station = plot or MR.id
	local at = Config.trainerFrame(station)
	local f = Instance.new("Folder")
	if plot then
		f.Name = "Trainer" .. plot
		f:SetAttribute("Plot", plot)
		f:SetAttribute("Magma", true)
		f:SetAttribute("Tier", tier or 1)
	else
		f.Name = "MagmaTrainer"
		f:SetAttribute("Tier", 0)
	end
	-- a wide obsidian plinth with a gold edge, then the stage in obsidian with molten edges
	local PW, PD, PZ = W + 4, D + 3, 0.5
	block(Vector3.new(PW, 0.5, PD), at * CFrame.new(0, 0.25, PZ), P.obsidian, f, true)
	for _, s in { -1, 1 } do
		quiet(glow(block(Vector3.new(0.2, 0.2, PD), at * CFrame.new(s * PW / 2, 0.5, PZ), P.gold, f)))
		quiet(glow(block(Vector3.new(PW, 0.2, 0.2), at * CFrame.new(0, 0.5, PZ + s * PD / 2), P.gold, f)))
	end
	local SP = table.clone(P)
	SP.floor, SP.bodyDark, SP.neon, SP.accent = P.obsidianHi, P.obsidian, P.lava, P.gold
	stage(f, at, SP)
	-- a low obsidian rim down both long sides, gold caps on the tall blocks
	for _, s in { -1, 1 } do
		for k = 0, 9 do
			local zz = -D / 2 + 0.6 + k * 1.2
			local tall = if k % 2 == 0 then 1.0 else 0.65
			block(Vector3.new(0.9, tall, 1.2), at * CFrame.new(s * (W / 2 - 0.45), H + tall / 2, zz), if k % 2 == 0 then P.obsidian else P.obsidianHi, f, true)
			if k % 2 == 0 then
				quiet(block(Vector3.new(0.95, 0.12, 1.25), at * CFrame.new(s * (W / 2 - 0.45), H + tall, zz), P.brass, f))
			end
		end
		-- a lava basin each side of the way in, on fire (clear of the side stand slots, robux.slots)
		local bx, bz = s * 4.0, -5.0
		cyl(1.05, 0.7, at * CFrame.new(bx, H + 0.35, bz), P.obsidianHi, f, true)
		quiet(glow(cyl(1.12, 0.12, at * CFrame.new(bx, H + 0.7, bz), P.gold, f)))
		quiet(glow(cyl(0.8, 0.06, at * CFrame.new(bx, H + 0.74, bz), P.lava, f)))
		flames(f, at * CFrame.new(bx, H + 0.9, bz), 1.2, P, 16)
		-- molten cracks across the floor
		local y = H + 0.06
		line(f, (at * CFrame.new(s * 1.9, y, -1.6)).Position, (at * CFrame.new(s * 3.0, y, -0.4)).Position, P.lava)
		line(f, (at * CFrame.new(s * 3.0, y, -0.4)).Position, (at * CFrame.new(s * 2.4, y, 1.2)).Position, P.lava)
		line(f, (at * CFrame.new(s * 2.4, y, 1.2)).Position, (at * CFrame.new(s * 4.0, y, 2.6)).Position, P.lavaHot)
	end
	-- the way in: dark obsidian with molten edges up to the ring
	local z0, z1 = -D / 2, T.targetZ - 2.6
	quiet(block(Vector3.new(3, 0.06, z1 - z0), at * CFrame.new(0, H + 0.05, (z0 + z1) / 2), P.obsidian, f))
	for _, s in { -1, 1 } do
		quiet(glow(block(Vector3.new(LINE, 0.08, z1 - z0), at * CFrame.new(s * 1.5, H + 0.06, (z0 + z1) / 2), P.lava, f)))
	end
	-- the ring under the golem and a rune circle spinning round it
	local foot = at * CFrame.new(0, H, T.targetZ)
	targetRing(f, at, SP, 2.8)
	local runes = spinner(f, foot, Vector3.new(0, 1, 0), 0.35)
	for k = 0, 11 do
		quiet(glow(block(Vector3.new(0.9, 0.06, 0.18), foot * CFrame.Angles(0, k * math.pi / 6, 0) * CFrame.new(0, 0.12, 3.4),
			if k % 3 == 0 then P.violetHi else P.gold, runes)))
	end
	local pts = omegaGate(f, at, P)
	omegaTitan(f, station, foot, P)
	-- the four obelisks, their crystals arcing lightning into the ring
	local ox = PW / 2 - 1.2
	for _, o in { { -1, -PD / 2 + PZ + 1.3, "lowL" }, { 1, -PD / 2 + PZ + 1.3, "lowR" }, { -1, 4.0, "highL" }, { 1, 4.0, "highR" } } do
		local cr = obelisk(f, at * CFrame.new(o[1] * ox, 0.5, o[2]), P, (o[1] + 1) * 0.25 + (if o[2] > 0 then 0.5 else 0))
		zap(attach(cr), pts[o[3]], P)
	end
	-- vfx: gold shockwaves out of the golem's feet, fire round them, embers over the whole pad
	local sw = fxBox(f, Vector3.new(0.2, 0.2, 0.2), foot * CFrame.new(0, 0.15, 0))
	emit(sw, { tex = TEX.shock, c0 = P.goldHi, c1 = P.lava, size = { 1, 13 }, rate = 0.7, life = { 1.3, 1.3 }, speed = { 0.01, 0.01 }, flat = true, alpha = 0.2 })
	local aura = fxBox(f, Vector3.new(4.5, 0.3, 3), foot * CFrame.new(0, 0.3, 0))
	emit(aura, { tex = TEX.fire, c0 = P.lava, c1 = P.crimson, size = { 1.6, 0.3 }, rate = 10, life = { 0.5, 0.8 }, speed = { 1.5, 3 },
		spread = 15, accel = Vector3.new(0, 3, 0), rot = 40, alpha = 0.35 })
	local em = fxBox(f, Vector3.new(PW - 1, 0.4, PD - 1), at * CFrame.new(0, H + 0.4, PZ))
	emit(em, { tex = TEX.glint, c0 = P.goldHi, c1 = P.lava, size = { 0.35, 0.05 }, rate = 14, life = { 2, 3.2 }, speed = { 1.2, 3 },
		spread = 25, accel = Vector3.new(0, 0.8, 0), rot = 120 })
	-- smoke off the crown, drifting (realism pass)
	local crownSmoke = fxBox(f, Vector3.new(2, 0.4, 1.2), at * CFrame.new(0, 21.5, 7))
	local cs = emit(crownSmoke, { tex = TEX.smoke, c0 = P.smoke, c1 = P.basalt, size = { 2.5, 7 }, rate = 1.5, life = { 4, 6 },
		speed = { 1.5, 2.5 }, spread = 15, accel = Vector3.new(0.5, 0.4, 0), rot = 20, alpha = 0.6 })
	cs.LightEmission = 0
	cs.LightInfluence = 1
	floorTiles(f, at, P)
	-- red strips along the plinth's sides (the reference's glowing panel insets)
	for _, s in { -1, 1 } do
		quiet(glow(block(Vector3.new(0.1, 0.14, PD - 2), at * CFrame.new(s * (PW / 2 + 0.03), 0.25, PZ), P.lava, f)))
		quiet(glow(block(Vector3.new(PW - 2, 0.14, 0.1), at * CFrame.new(0, 0.25, PZ + s * (PD / 2 + 0.03)), P.lava, f)))
	end
	local zaps = 4 + tendrils(f, foot, P) -- the obelisks' lightning + the thorny energy
	f:SetAttribute("ZapCount", zaps) -- TrainingController looks for its beams until it has them all
	-- red star sparkles round the golem
	local stars = fxBox(f, Vector3.new(6, 6, 4), foot * CFrame.new(0, 4.5, 0))
	emit(stars, { tex = TEX.glint, c0 = P.goldHi, c1 = P.lava, size = { 0.6, 0.1 }, rate = 14, life = { 0.6, 1.1 }, speed = { 1, 3 }, spread = 180, rot = 180 })
	if not plot then
		magmaSign(f, at, P) -- the price sign is the hub's (at a pan it's already owned)
	end
	MapArt.solidify(f) -- solid like the rest of the map ...
	for _, d in f:GetDescendants() do
		if d:IsA("BasePart") and d.Parent and d.Parent.Name == "Motion" then
			d.CanCollide = false -- ... except what spins and floats (the client moves it)
			d.CanQuery = false
		end
	end
	f.Parent = parent
	return f
end

return TrainingArt
