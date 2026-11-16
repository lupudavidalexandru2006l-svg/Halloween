--!strict
-- MapSpectacle (owner 2026-11-13: "brighter and more striking colours, like the big simulator games;
-- the decor gets better island by island: a few trees at the start, a whole supernova at the end; focus
-- on the decor OUTSIDE the map"). Builds the giant scenery past the tunnel's cliffs, one set per island,
-- each louder than the one before (tier = island number), and the vivid pass that lifts the whole map's
-- colours. MapArt.build calls both.
-- Everything goes in Art.Far.Spectacle: walk-through and ignored by the camera (MapArt's Far rules).
-- What turns or floats sits straight inside a MapMotion folder, which MapController moves on each screen.
-- Arches cross high over the tunnel; their feet land outside the cliffs, never on the road.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Theme = require(ReplicatedStorage.Shared.Theme)
local Scenery = require(ReplicatedStorage.Shared.Scenery)

local Spectacle = {}
local P = Theme.spectacle
local S = Config.art.spectacle
local W = Config.world

local meshes: Instance? = nil
local rng: () -> number = math.random
-- owner 2026-11-13 "make it more": each set is built twice, the front layer (everything) and, from
-- island S.backFrom on, a back layer further out (only the repeatable pieces: no arches, no one-off
-- volcanoes, planets or suns). dens scales how many pieces spots() hands out.
local front = true
local dens = 1

-- ---------- pieces ----------
local function finish(p: BasePart, color: Color3, parent: Instance): BasePart
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Color = color
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function block(size: Vector3, cf: CFrame, color: Color3, parent: Instance, mat: Enum.Material?): BasePart
	local p = Instance.new("Part")
	p.Size = size
	p.CFrame = cf
	p.Material = mat or Enum.Material.SmoothPlastic
	return finish(p, color, parent)
end

local function neon(p: BasePart, transparency: number?): BasePart
	p.Material = Enum.Material.Neon
	p.Transparency = transparency or 0
	return p
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
	local p = block(size, cf, color, parent)
	local m = Instance.new("SpecialMesh")
	m.MeshType = Enum.MeshType.Sphere
	m.Parent = p
	return p
end

-- an upright cylinder centred at cf
local function cyl(r: number, h: number, cf: CFrame, color: Color3, parent: Instance): BasePart
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Cylinder
	p.Size = Vector3.new(h, r * 2, r * 2)
	p.CFrame = cf * CFrame.Angles(0, 0, math.pi / 2)
	p.Material = Enum.Material.SmoothPlastic
	return finish(p, color, parent)
end

-- one of SceneryMeshes' shapes (Cone, Rock, Ring, Octa, Dome), a squashed sphere if it's missing
local function mesh(name: string, size: Vector3, cf: CFrame, color: Color3, parent: Instance): BasePart
	local template = meshes and meshes:FindFirstChild(name)
	if template and template:IsA("MeshPart") then
		local p = template:Clone()
		p.Size = size
		p.CFrame = cf
		return finish(p, color, parent)
	end
	return ellipsoid(size, cf, color, parent)
end

local function folder(name: string, parent: Instance): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

-- MapController: "spin" turns the parts round the Pivot's local Axis at Speed rad/s; "bob" lifts them
-- Amp studs, Hz times a second
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

local function bobber(parent: Instance, at: Vector3, amp: number): Folder
	return motion(parent, "bob", CFrame.new(at), { Amp = amp, Hz = S.bobHz * (0.8 + rng() * 0.4), Phase = rng() })
end

local function particles(parent: Instance, at: Vector3, box: Vector3, color: Color3, size: number, rate: number, speed: number, life: number, spread: number?)
	local anchor = block(box, CFrame.new(at), color, parent)
	anchor.Transparency = 1
	local e = Instance.new("ParticleEmitter")
	e.Shape = Enum.ParticleEmitterShape.Box
	e.Color = ColorSequence.new(P.white, color)
	e.LightEmission = 1
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.3, size), NumberSequenceKeypoint.new(1, 0) })
	e.Lifetime = NumberRange.new(life * 0.7, life)
	e.Rate = rate
	e.Speed = NumberRange.new(speed * 0.5, speed)
	e.SpreadAngle = Vector2.new(spread or 180, spread or 180)
	e.Parent = anchor
end

local function lamp(p: BasePart, color: Color3, range: number, brightness: number)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Shadows = false
	l.Parent = p
end

-- a half circle across the tunnel (in the XY plane at z), radius r to the band's middle, feet at cy
local function arch(parent: Instance, z: number, r: number, band: number, depth: number, color: Color3, glowing: boolean, cy: number?)
	if not front then
		return -- one arch per spot, built with the front layer
	end
	local n = S.archSegments
	local seg = 2 * r * math.sin(math.pi / (2 * n)) + band * 0.35 -- a little overlap so no gaps show
	for i = 0, n - 1 do
		local mid = math.pi * (i + 0.5) / n
		local p = block(Vector3.new(seg, band, depth), CFrame.new(math.cos(mid) * r, (cy or S.archFeet) + math.sin(mid) * r, z) * CFrame.Angles(0, 0, mid + math.pi / 2), color, parent)
		if glowing then
			neon(p)
		end
	end
end

local function rainbow(parent: Instance, z: number, r0: number, band: number, glowing: boolean)
	for k, c in P.rainbow do
		arch(parent, z + (k % 2) * 0.2, r0 + (k - 1) * band, band + 0.1, S.archDepth, c, glowing)
	end
end

-- spots outside the cliffs: n per side, spread along the zone, the two sides offset half a step
local function spots(zone: Config.Zone, n: number, xMin: number?, xMax: number?): { Vector3 }
	local out: { Vector3 } = {}
	local len = zone.zMax - zone.zMin
	local a, b = xMin or S.sideMin, xMax or S.sideMax
	if not front then
		a, b = S.backMin, S.backMax
	end
	n = math.max(1, math.round(n * dens))
	for _, side in { -1, 1 } do
		for i = 1, n do
			local z = zone.zMin + (i - 0.5 + (side + 1) * 0.25) * len / (n + 0.5) + (rng() - 0.5) * 10
			table.insert(out, Vector3.new(side * (a + rng() * (b - a)), 0, z))
		end
	end
	return out
end

-- ---------- the big things ----------
local function pine(f: Instance, at: Vector3, h: number, snow: boolean)
	cyl(h * 0.05, h * 0.3, CFrame.new(at + Vector3.new(0, h * 0.15, 0)), P.trunk, f)
	for k = 0, 2 do
		local w, ch = h * (0.62 - k * 0.15), h * 0.42
		local y = h * (0.38 + k * 0.2)
		mesh("Cone", Vector3.new(w, ch, w), CFrame.new(at + Vector3.new(0, y, 0)), P.pine[k + 1], f)
		if snow then
			mesh("Cone", Vector3.new(w * 0.45, ch * 0.32, w * 0.45), CFrame.new(at + Vector3.new(0, y + ch * 0.36, 0)), P.white, f)
		end
	end
end

local function roundTree(f: Instance, at: Vector3, h: number, leaves: { Color3 })
	cyl(h * 0.07, h * 0.65, CFrame.new(at + Vector3.new(0, h * 0.32, 0)), P.trunk, f)
	local top = at + Vector3.new(0, h * 0.72, 0)
	ball(h * 0.26, top, leaves[1], f)
	for k = 0, 3 do
		local a = k * math.pi / 2 + rng()
		ball(h * 0.18, top + Vector3.new(math.cos(a) * h * 0.22, -h * 0.04 + (k % 2) * h * 0.08, math.sin(a) * h * 0.22), leaves[(k % #leaves) + 1], f)
	end
end

local function mushroom(f: Instance, at: Vector3, h: number, cap: Color3)
	cyl(h * 0.1, h, CFrame.new(at + Vector3.new(0, h / 2, 0)), P.cream, f)
	local top = at + Vector3.new(0, h, 0)
	ellipsoid(Vector3.new(h * 0.95, h * 0.45, h * 0.95), CFrame.new(top), cap, f)
	neon(cyl(h * 0.4, h * 0.03, CFrame.new(top - Vector3.new(0, h * 0.04, 0)), P.white, f), 0.2)
	for k = 0, 5 do
		local a = k * math.pi / 3 + 0.4
		ball(h * 0.06, top + Vector3.new(math.cos(a) * h * 0.28, h * 0.14, math.sin(a) * h * 0.28), P.white, f)
	end
	ball(h * 0.08, top + Vector3.new(0, h * 0.22, 0), P.white, f)
end

local function palm(f: Instance, at: Vector3, h: number, lean: number)
	local pos = at
	for k = 0, 5 do
		local seg = h / 6
		local nxt = pos + Vector3.new(lean * seg * 0.12 * (k + 1) * 0.4, seg, 0)
		local mid = (pos + nxt) / 2
		local p = cyl(h * (0.045 - k * 0.003), seg * 1.08, CFrame.new(mid), if k % 2 == 0 then P.trunk else P.trunkLight, f)
		p.CFrame = CFrame.lookAt(mid, nxt) * CFrame.Angles(0, math.pi / 2, 0) -- the cylinder's axis along the trunk
		pos = nxt
	end
	for k = 0, 7 do
		local a = k * math.pi / 4
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		local len = h * 0.42
		block(Vector3.new(len * 0.28, h * 0.02, len), CFrame.lookAt(pos + dir * len * 0.45 + Vector3.new(0, -len * 0.12, 0), pos + dir * len - Vector3.new(0, len * 0.35, 0)), P.palm[(k % #P.palm) + 1], f)
	end
	for k = 0, 2 do
		ball(h * 0.035, pos + Vector3.new(math.cos(k * 2.1) * 1.5, -1.5, math.sin(k * 2.1) * 1.5), P.coconut, f)
	end
end

local function beachBall(f: Instance, at: Vector3, r: number)
	local m = bobber(f, at, 3)
	ball(r, at, P.white, m)
	for k, c in { P.rainbow[1], P.rainbow[3], P.rainbow[5] } do
		local band = cyl(r * 1.005, r * 0.5, CFrame.new(at) * CFrame.Angles(0, k * math.pi / 3, math.pi / 2), c, m)
		band.Size = Vector3.new(r * 0.45, r * 2.01, r * 2.01)
	end
end

local function temple(f: Instance, at: Vector3, w: number, tiers: number)
	local y, step = 0, w * 0.13
	for k = 0, tiers - 1 do
		local tw = w * (1 - k * 0.17)
		block(Vector3.new(tw, step, tw), CFrame.new(at + Vector3.new(0, y + step / 2, 0)), if k % 2 == 0 then P.templeA else P.templeB, f)
		neon(block(Vector3.new(tw + 0.4, step * 0.12, tw + 0.4), CFrame.new(at + Vector3.new(0, y + step * 0.92, 0)), P.gold, f))
		y += step
	end
	-- a stair up the front (toward the tunnel)
	local face = if at.X > 0 then -1 else 1
	block(Vector3.new(w * 0.5, y * 1.12, w * 0.2), CFrame.new(at + Vector3.new(face * w * 0.42, y * 0.45, 0)) * CFrame.Angles(0, 0, face * -0.75), P.templeB, f)
	local gemAt = at + Vector3.new(0, y + w * 0.16, 0)
	local m = motion(f, "spin", CFrame.new(gemAt), { Axis = Vector3.new(0, 1, 0), Speed = S.spinSlow * 3 })
	local gem = neon(mesh("Octa", Vector3.new(w * 0.14, w * 0.24, w * 0.14), CFrame.new(gemAt), P.emerald, m))
	lamp(gem, P.emerald, 40, 2)
	particles(f, gemAt, Vector3.new(4, 4, 4), P.emerald, 1.4, 6, 3, 2.5)
end

local function waterfall(f: Instance, at: Vector3, h: number)
	mesh("Rock", Vector3.new(h * 0.45, h, h * 0.4), CFrame.new(at + Vector3.new(0, h * 0.45, 0)) * CFrame.Angles(0, rng() * 6, 0), P.cliff, f)
	ellipsoid(Vector3.new(h * 0.3, h * 0.06, h * 0.3), CFrame.new(at + Vector3.new(0, h * 0.94, 0)), P.grass, f)
	local face = if at.X > 0 then -1 else 1
	local fallX = at.X + face * h * 0.23
	neon(block(Vector3.new(1.2, h * 0.92, h * 0.16), CFrame.new(fallX, h * 0.46, at.Z), P.water, f), 0.15)
	neon(block(Vector3.new(0.6, h * 0.92, h * 0.08), CFrame.new(fallX + face * 0.8, h * 0.46, at.Z), P.white, f), 0.35)
	ellipsoid(Vector3.new(h * 0.35, 3, h * 0.35), CFrame.new(fallX + face * h * 0.1, 0.5, at.Z), P.water, f)
	particles(f, Vector3.new(fallX + face * 2, 3, at.Z), Vector3.new(h * 0.15, 2, h * 0.15), P.white, 6, 8, 5, 1.5, 60)
end

local function pyramid(f: Instance, at: Vector3, w: number, steps: number)
	local step = w * 0.08
	for k = 0, steps - 1 do
		local tw = w * (1 - k / steps)
		block(Vector3.new(tw, step, tw), CFrame.new(at + Vector3.new(0, step * (k + 0.5), 0)), if k % 2 == 0 then P.sand else P.sandLight, f)
	end
	local capAt = at + Vector3.new(0, step * steps + w * 0.08, 0)
	local cap = neon(mesh("Octa", Vector3.new(w * 0.16, w * 0.18, w * 0.16), CFrame.new(capAt), P.gold, f))
	lamp(cap, P.gold, 50, 2)
	particles(f, capAt, Vector3.new(3, 3, 3), P.gold, 2, 5, 4, 3)
end

local function goldRing(f: Instance, at: Vector3, d: number)
	local m = motion(f, "spin", CFrame.new(at), { Axis = Vector3.new(0, 1, 0), Speed = S.spinFast })
	neon(mesh("Ring", Vector3.new(d, d * 0.08, d), CFrame.new(at) * CFrame.Angles(math.pi / 2, 0, 0), P.gold, m))
	neon(mesh("Octa", Vector3.new(d * 0.2, d * 0.32, d * 0.2), CFrame.new(at), P.sunCore, m))
end

local function sunDisc(f: Instance, at: Vector3, r: number)
	local core = neon(ball(r, at, P.sunCore, f))
	lamp(core, P.sunCore, 60, 3)
	neon(ball(r * 1.25, at, P.gold, f), 0.6)
	local m = motion(f, "spin", CFrame.new(at), { Axis = Vector3.new(0, 0, 1), Speed = S.spinSlow })
	for k = 0, 7 do
		local a = k * math.pi / 4
		neon(block(Vector3.new(r * 0.9, r * 0.22, r * 0.22), CFrame.new(at) * CFrame.Angles(0, 0, a) * CFrame.new(r * 1.7, 0, 0), P.gold, m), 0.1)
	end
end

local function cactus(f: Instance, at: Vector3, h: number)
	cyl(h * 0.09, h, CFrame.new(at + Vector3.new(0, h / 2, 0)), P.cactus, f)
	ball(h * 0.09, at + Vector3.new(0, h, 0), P.cactus, f)
	for _, side in { -1, 1 } do
		local y = h * (0.45 + (side + 1) * 0.08)
		block(Vector3.new(h * 0.25, h * 0.12, h * 0.12), CFrame.new(at + Vector3.new(side * h * 0.15, y, 0)), P.cactus, f)
		cyl(h * 0.06, h * 0.3, CFrame.new(at + Vector3.new(side * h * 0.27, y + h * 0.13, 0)), P.cactus, f)
	end
	ball(h * 0.05, at + Vector3.new(0, h * 1.08, 0), P.rainbow[1], f)
end

local function floatingIsland(f: Instance, at: Vector3, s: number)
	local m = bobber(f, at, 4)
	mesh("Cone", Vector3.new(s * 1.6, s * 1.4, s * 1.6), CFrame.new(at - Vector3.new(0, s * 0.7, 0)) * CFrame.Angles(math.pi, 0, 0), P.cliff, m)
	cyl(s * 0.82, s * 0.18, CFrame.new(at), P.grass, m)
	roundTree(m, at + Vector3.new(s * 0.25, s * 0.09, 0), s * 0.9, P.leaves)
	local gem = neon(mesh("Octa", Vector3.new(s * 0.18, s * 0.4, s * 0.18), CFrame.new(at + Vector3.new(-s * 0.35, s * 0.3, s * 0.1)), P.crystal[1 + math.floor(rng() * #P.crystal)], m))
	lamp(gem, gem.Color, 25, 1.5)
	neon(block(Vector3.new(s * 0.12, s * 1.6, 0.6), CFrame.new(at + Vector3.new(0, -s * 0.85, s * 0.7)), P.water, m), 0.2)
end

local function crystalCluster(f: Instance, at: Vector3, h: number, color: Color3)
	for k = 0, 4 do
		local a = k * 1.3
		local kh = h * (if k == 0 then 1 else 0.45 + rng() * 0.3)
		local off = if k == 0 then Vector3.zero else Vector3.new(math.cos(a) * h * 0.18, 0, math.sin(a) * h * 0.18)
		local tilt = if k == 0 then CFrame.identity else CFrame.Angles(math.sin(a) * 0.35, 0, math.cos(a) * 0.35)
		neon(mesh("Octa", Vector3.new(kh * 0.24, kh, kh * 0.24), CFrame.new(at + off + Vector3.new(0, kh * 0.4, 0)) * tilt, color, f), 0.05)
	end
end

local function volcano(f: Instance, at: Vector3, r: number, h: number)
	mesh("Cone", Vector3.new(r * 2, h, r * 2), CFrame.new(at + Vector3.new(0, h / 2 - 2, 0)), P.volcano, f)
	mesh("Cone", Vector3.new(r * 0.9, h * 0.45, r * 0.9), CFrame.new(at + Vector3.new(0, h * 0.78 - 2, 0)), P.volcanoDark, f)
	local top = at + Vector3.new(0, h - 4, 0)
	local crater = neon(ellipsoid(Vector3.new(r * 0.32, 4, r * 0.32), CFrame.new(top + Vector3.new(0, 1.5, 0)), P.lava, f))
	lamp(crater, P.lava, 60, 3)
	for k = 0, 5 do
		local a = k * math.pi / 3 + rng() * 0.5
		local p1 = top + Vector3.new(math.cos(a) * r * 0.1, 0, math.sin(a) * r * 0.1)
		local p2 = at + Vector3.new(math.cos(a) * r * 0.92, 1, math.sin(a) * r * 0.92)
		local mid = (p1 + p2) / 2 + Vector3.new(math.cos(a) * 1.5, 1.5, math.sin(a) * 1.5) -- just proud of the slope
		neon(block(Vector3.new(r * 0.07, 1, (p2 - p1).Magnitude), CFrame.lookAt(mid, p2), if k % 2 == 0 then P.lava else P.lavaHot, f))
	end
	particles(f, top + Vector3.new(0, 4, 0), Vector3.new(r * 0.2, 2, r * 0.2), P.lavaHot, 4, 22, 25, 3, 35)
	local smoke = block(Vector3.new(r * 0.2, 2, r * 0.2), CFrame.new(top + Vector3.new(0, 8, 0)), P.smoke, f)
	smoke.Transparency = 1
	local e = Instance.new("ParticleEmitter")
	e.Color = ColorSequence.new(P.smoke)
	e.Transparency = NumberSequence.new(0.3, 1)
	e.Size = NumberSequence.new(10, 30)
	e.Lifetime = NumberRange.new(5, 8)
	e.Speed = NumberRange.new(6, 10)
	e.SpreadAngle = Vector2.new(15, 15)
	e.Rate = 4
	e.Parent = smoke
end

local function magmaRock(f: Instance, at: Vector3, s: number)
	local m = bobber(f, at, 3)
	mesh("Rock", Vector3.new(s, s * 0.8, s * 0.9), CFrame.new(at) * CFrame.Angles(rng() * 3, rng() * 3, 0), P.volcanoDark, m)
	neon(ball(s * 0.32, at, P.lava, m))
	for k = 0, 2 do
		neon(block(Vector3.new(s * 1.02, s * 0.06, s * 0.08), CFrame.new(at) * CFrame.Angles(k, k * 2, k * 0.7), P.lavaHot, m))
	end
end

local function planet(f: Instance, at: Vector3, r: number, body: Color3, ring: Color3)
	ball(r, at, body, f)
	neon(ball(r * 0.35, at + Vector3.new(r * 0.5, r * 0.55, -r * 0.55), P.white, f), 0.6)
	local tilt = CFrame.new(at) * CFrame.Angles(0.45, 0, 0.3)
	local m = motion(f, "spin", tilt, { Axis = Vector3.new(0, 1, 0), Speed = S.spinFast })
	neon(mesh("Ring", Vector3.new(r * 3.4, r * 0.1, r * 3.4), tilt, ring, m), 0.1)
	neon(mesh("Ring", Vector3.new(r * 2.7, r * 0.08, r * 2.7), tilt, P.white, m), 0.3)
	-- a little moon
	local mm = motion(f, "spin", CFrame.new(at), { Axis = Vector3.new(0.2, 1, 0).Unit, Speed = S.spinFast * 0.8 })
	ball(r * 0.18, at + Vector3.new(r * 2.1, 0, 0), P.cream, mm)
end

local function spire(f: Instance, at: Vector3, h: number, color: Color3)
	mesh("Rock", Vector3.new(h * 0.3, h * 0.2, h * 0.3), CFrame.new(at + Vector3.new(0, h * 0.06, 0)), P.obsidian, f)
	local tip = neon(mesh("Octa", Vector3.new(h * 0.16, h, h * 0.16), CFrame.new(at + Vector3.new(0, h * 0.55, 0)) * CFrame.Angles(0, rng() * 3, (rng() - 0.5) * 0.15), color, f), 0.05)
	lamp(tip, color, 45, 2)
	for k = 0, 2 do
		local a = k * 2.1 + rng()
		neon(mesh("Octa", Vector3.new(h * 0.07, h * 0.4, h * 0.07), CFrame.new(at + Vector3.new(math.cos(a) * h * 0.12, h * 0.2, math.sin(a) * h * 0.12)) * CFrame.Angles(math.sin(a) * 0.4, 0, math.cos(a) * 0.4), color, f), 0.1)
	end
end

local function comet(f: Instance, at: Vector3, s: number, color: Color3)
	local m = bobber(f, at, 6)
	neon(ball(s, at, P.white, m))
	neon(ball(s * 1.5, at, color, m), 0.5)
	local dir = Vector3.new(if at.X > 0 then 1 else -1, 0.5, 0.4).Unit
	for k = 1, 4 do
		neon(ball(s * (1.2 - k * 0.22), at + dir * s * k * 1.6, color, m), 0.2 + k * 0.17)
	end
end

local function supernova(f: Instance, at: Vector3, r: number)
	local core = neon(ball(r * 0.5, at, P.white, f))
	lamp(core, P.sunCore, 60, 4)
	neon(ball(r * 0.68, at, P.sunCore, f), 0.3)
	neon(ball(r * 0.88, at, P.lavaHot, f), 0.55)
	neon(ball(r * 1.12, at, P.nova, f), 0.75)
	neon(ball(r * 1.45, at, P.violet, f), 0.88)
	-- the burst: long rays turning slowly, facing the tunnel (-Z)
	local rays = motion(f, "spin", CFrame.new(at), { Axis = Vector3.new(0, 0, 1), Speed = S.spinSlow })
	for k = 0, 11 do
		local long = if k % 2 == 0 then 3.4 else 2.3
		neon(block(Vector3.new(r * long, r * 0.07, r * 0.07), CFrame.new(at) * CFrame.Angles(0, 0, k * math.pi / 12), if k % 3 == 0 then P.white elseif k % 3 == 1 then P.sunCore else P.nova, rays), 0.05)
	end
	-- three tilted rings, each turning its own way
	for k, c in { P.cyan, P.nova, P.gold } do
		local tilt = CFrame.new(at) * CFrame.Angles(0.5 + k * 0.6, k * 1.1, 0.2 * k)
		local m = motion(f, "spin", tilt, { Axis = Vector3.new(0, 1, 0), Speed = S.spinFast * (if k % 2 == 0 then -1 else 1) })
		neon(mesh("Ring", Vector3.new(r * (2.4 + k * 0.45), r * 0.06, r * (2.4 + k * 0.45)), tilt, c, m), 0.05)
		neon(ball(r * 0.09, (tilt * CFrame.new(r * (1.2 + k * 0.22), 0, 0)).Position, P.white, m))
	end
	particles(f, at, Vector3.new(r, r, r), P.sunCore, r * 0.12, 30, r * 0.6, 3)
	particles(f, at, Vector3.new(r * 2.5, r * 2.5, r * 2.5), P.nova, r * 0.06, 25, 2, 4)
end

-- ---------- one set per island: tier = how far in it is ----------
type Builder = (Instance, Config.Zone) -> ()
local SETS: { Builder } = {
	-- 1: a few snowy pines past the cliffs, nothing more
	function(f, zone)
		for _, at in spots(zone, 3, S.sideMin, S.sideMin + 30) do
			pine(f, at, 30 + rng() * 10, true)
		end
	end,
	-- 2: giant round trees and tall pines
	function(f, zone)
		for i, at in spots(zone, 5) do
			if i % 2 == 0 then
				pine(f, at, 44 + rng() * 12, false)
			else
				roundTree(f, at, 50 + rng() * 15, P.leaves)
			end
		end
	end,
	-- 3: giant candy mushrooms with fireflies
	function(f, zone)
		for i, at in spots(zone, 5) do
			mushroom(f, at, 36 + rng() * 22, P.caps[(i % #P.caps) + 1])
			if i % 2 == 0 then
				particles(f, at + Vector3.new(0, 20, 0), Vector3.new(30, 20, 30), P.firefly, 0.9, 6, 1, 4)
			end
		end
		for _, at in spots(zone, 2, S.sideMax, S.sideMax + 20) do
			roundTree(f, at, 60, P.leavesPink)
		end
	end,
	-- 4: palms, floating beach balls and a rainbow over the road
	function(f, zone)
		for i, at in spots(zone, 5) do
			palm(f, at, 42 + rng() * 18, if at.X > 0 then -1 else 1)
			if i % 3 == 0 then
				beachBall(f, at + Vector3.new(0, 55 + rng() * 15, 0), 8)
			end
		end
		rainbow(f, (zone.zMin + zone.zMax) / 2, S.archRadius, 5, false)
	end,
	-- 5: jungle temples with spinning gems, giant waterfalls, a vine arch
	function(f, zone)
		for i, at in spots(zone, 3) do
			if i % 3 == 1 then
				temple(f, at + Vector3.new(if at.X > 0 then 25 else -25, 0, 0), 60, 5)
			elseif i % 3 == 2 then
				waterfall(f, at, 85 + rng() * 15)
			else
				roundTree(f, at, 70, P.leaves)
			end
		end
		local z = zone.zMin + (zone.zMax - zone.zMin) * 0.3
		arch(f, z, S.archRadius, 6, 6, P.vine, false)
		for k = 1, 9 do
			local a = k * math.pi / 10
			ball(5 + rng() * 3, Vector3.new(math.cos(a) * (S.archRadius + 2), S.archFeet + math.sin(a) * (S.archRadius + 2), z), P.leaves[(k % #P.leaves) + 1], f)
			neon(ball(1.6, Vector3.new(math.cos(a) * S.archRadius, S.archFeet + math.sin(a) * S.archRadius - 4, z), P.caps[(k % #P.caps) + 1], f))
		end
	end,
	-- 6: golden pyramids, spinning gold rings, a big sun, cacti
	function(f, zone)
		for _, at in spots(zone, 2, S.sideMin + 30, S.sideMax) do
			pyramid(f, at + Vector3.new(if at.X > 0 then 20 else -20, 0, 0), 90 + rng() * 20, 9)
		end
		for _, at in spots(zone, 3, S.sideMin, S.sideMin + 15) do
			if rng() < 0.5 then
				goldRing(f, at + Vector3.new(0, 50 + rng() * 20, 0), 26)
			else
				cactus(f, at, 34 + rng() * 10)
			end
		end
		if front then
			sunDisc(f, Vector3.new(-S.sideMax, 120, (zone.zMin + zone.zMax) / 2), 16)
		end
		arch(f, zone.zMax - 30, S.archRadius, 4, 4, P.gold, true)
	end,
	-- 7: floating islands with waterfalls, crystal clusters, two glowing ring gates
	function(f, zone)
		for _, at in spots(zone, 3, S.sideMin, S.sideMax) do
			floatingIsland(f, at + Vector3.new(0, 48 + rng() * 30, 0), 22 + rng() * 8)
		end
		for i, at in spots(zone, 3, S.sideMin, S.sideMin + 20) do
			crystalCluster(f, at, 40 + rng() * 20, P.crystal[(i % #P.crystal) + 1])
		end
		arch(f, zone.zMin + 50, S.archRadius, 4, 4, P.cyan, true)
		arch(f, zone.zMax - 50, S.archRadius + 6, 4, 4, P.nova, true)
	end,
	-- 8: erupting volcanoes, floating magma rocks, a fire arch
	function(f, zone)
		local zm = (zone.zMin + zone.zMax) / 2
		if front then
			volcano(f, Vector3.new(-170, 0, zm - 50), 70, 130)
			volcano(f, Vector3.new(175, 0, zm + 60), 62, 115)
		else
			volcano(f, Vector3.new(230, 0, zone.zMin + 40), 50, 95)
			volcano(f, Vector3.new(-235, 0, zone.zMax - 40), 55, 105)
		end
		for _, at in spots(zone, 4, S.sideMin, S.sideMin + 30) do
			magmaRock(f, at + Vector3.new(0, 45 + rng() * 35, 0), 10 + rng() * 6)
		end
		arch(f, zone.zMin + 40, S.archRadius, 5, 5, P.lava, true)
		arch(f, zone.zMin + 40.4, S.archRadius + 5, 2.5, 5, P.lavaHot, true)
	end,
	-- 9: giant glowing crystal spires, ringed planets, neon gates
	function(f, zone)
		for i, at in spots(zone, 4, S.sideMin, S.sideMax) do
			spire(f, at, 80 + rng() * 50, P.crystal[(i % #P.crystal) + 1])
		end
		local zm = (zone.zMin + zone.zMax) / 2
		if front then
			planet(f, Vector3.new(-140, 115, zm + 20), 22, P.violet, P.pink)
			planet(f, Vector3.new(150, 95, zm - 60), 14, P.cyan, P.gold)
		end
		for _, at in spots(zone, 2, S.sideMin, S.sideMin + 20) do
			local m = bobber(f, at + Vector3.new(0, 60, 0), 5)
			neon(mesh("Octa", Vector3.new(6, 14, 6), CFrame.new(at + Vector3.new(0, 60, 0)), P.pink, m))
		end
		arch(f, zone.zMin + 45, S.archRadius, 4, 4, P.pink, true)
		arch(f, zone.zMax - 45, S.archRadius, 4, 4, P.violet, true)
	end,
	-- 10: the supernova over the end of the road, planets, comets and a glowing rainbow
	function(f, zone)
		if front then
			supernova(f, Vector3.new(0, S.novaHeight, zone.zMax + S.novaPast), S.novaRadius)
			planet(f, Vector3.new(-150, 110, zone.zMin + 50), 24, P.pink, P.cyan)
			planet(f, Vector3.new(160, 130, zone.zMin + 160), 18, P.emerald, P.nova)
			planet(f, Vector3.new(-120, 150, zone.zMax - 60), 14, P.gold, P.violet)
			particles(f, Vector3.new(0, 90, (zone.zMin + zone.zMax) / 2), Vector3.new(260, 60, zone.zMax - zone.zMin), P.white, 1.2, 40, 1, 4)
		end
		for i, at in spots(zone, 3, S.sideMin, S.sideMax) do
			if i % 2 == 0 then
				comet(f, at + Vector3.new(0, 70 + rng() * 40, 0), 4, P.crystal[(i % #P.crystal) + 1])
			else
				spire(f, at, 70 + rng() * 40, P.crystal[(i % #P.crystal) + 1])
			end
		end
		rainbow(f, zone.zMin + 60, S.archRadius, 4, true)
		rainbow(f, zone.zMax - 70, S.archRadius + 8, 4, true)
	end,
}

-- ---------- ground detail inside the tunnel (owner 2026-11-13: "make the map more detailed") ----------
-- small themed things in clusters on the open ground beside the road: never on the road's middle, never
-- on a tree's, sun patch's or lava pool's spot, walk-through (MapArt treats GroundDetail like Far)
type Bit = (Instance, Vector3) -> ()

local function tuft(color: Color3): Bit
	return function(f, at)
		local h = 0.9 + rng() * 0.6
		for k = 0, 2 do
			local a = k * 2.1 + rng()
			block(Vector3.new(0.18, h * (0.7 + rng() * 0.5), 0.45), CFrame.new(at + Vector3.new(math.cos(a) * 0.25, h * 0.35, math.sin(a) * 0.25)) * CFrame.Angles(0, a, (rng() - 0.5) * 0.7), color, f)
		end
	end
end

local function flower(f: Instance, at: Vector3)
	block(Vector3.new(0.12, 0.8, 0.12), CFrame.new(at + Vector3.new(0, 0.4, 0)), P.leaves[1], f)
	ball(0.3, at + Vector3.new(0, 0.85, 0), P.flowers[1 + math.floor(rng() * #P.flowers)], f)
	ball(0.12, at + Vector3.new(0, 0.9, -0.22), P.sunCore, f)
end

local function pebble(color: Color3): Bit
	return function(f, at)
		local s = 0.7 + rng() * 1.1
		mesh("Rock", Vector3.new(s, s * 0.6, s * 0.8), CFrame.new(at + Vector3.new(0, s * 0.18, 0)) * CFrame.Angles(0, rng() * 6, 0), color, f)
	end
end

local function miniShroom(glowing: boolean): Bit
	return function(f, at)
		local h = 0.6 + rng() * 0.5
		cyl(0.14, h, CFrame.new(at + Vector3.new(0, h / 2, 0)), P.cream, f)
		local cap = ellipsoid(Vector3.new(h * 1.3, h * 0.6, h * 1.3), CFrame.new(at + Vector3.new(0, h, 0)), P.caps[1 + math.floor(rng() * #P.caps)], f)
		if glowing then
			neon(cap, 0.1)
		end
	end
end

local function starfish(f: Instance, at: Vector3)
	for k = 0, 4 do
		local a = k * math.pi * 2 / 5 + rng()
		block(Vector3.new(0.8, 0.14, 0.26), CFrame.new(at + Vector3.new(math.cos(a) * 0.38, 0.2, math.sin(a) * 0.38)) * CFrame.Angles(0, -a, 0), P.starfish, f)
	end
end

local function shell(f: Instance, at: Vector3)
	ellipsoid(Vector3.new(0.75, 0.35, 0.6), CFrame.new(at + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, rng() * 6, 0), P.shell, f)
end

local function crystal(colors: { Color3 }): Bit
	return function(f, at)
		local h = 0.9 + rng() * 0.9
		neon(mesh("Octa", Vector3.new(h * 0.32, h, h * 0.32), CFrame.new(at + Vector3.new(0, h * 0.4, 0)) * CFrame.Angles((rng() - 0.5) * 0.6, rng() * 3, (rng() - 0.5) * 0.6), colors[1 + math.floor(rng() * #colors)], f), 0.05)
	end
end

local function crack(color: Color3): Bit
	return function(f, at)
		local pos, a = at, rng() * 6
		for _ = 1, 3 do
			local len = 1.2 + rng() * 1.2
			local dir = Vector3.new(math.cos(a), 0, math.sin(a))
			neon(block(Vector3.new(len, 0.06, 0.2), CFrame.new(pos + dir * len / 2 + Vector3.new(0, 0.19, 0)) * CFrame.Angles(0, -a, 0), color, f), 0.05)
			pos += dir * len
			a += (rng() - 0.5) * 1.6
		end
	end
end

local function snowLump(f: Instance, at: Vector3)
	ellipsoid(Vector3.new(1.4 + rng(), 0.55, 1.1 + rng() * 0.6), CFrame.new(at + Vector3.new(0, 0.18, 0)) * CFrame.Angles(0, rng() * 6, 0), P.white, f)
end

local function fern(f: Instance, at: Vector3)
	for k = 0, 4 do
		local a = k * math.pi * 2 / 5 + rng()
		block(Vector3.new(0.4, 0.08, 1.4), CFrame.new(at + Vector3.new(math.cos(a) * 0.55, 0.4, math.sin(a) * 0.55)) * CFrame.Angles(0, -a + math.pi / 2, 0) * CFrame.Angles(0.5, 0, 0), P.palm[1 + k % #P.palm], f)
	end
end

local function dryBush(f: Instance, at: Vector3)
	for k = 0, 3 do
		local a = k * 1.6 + rng()
		block(Vector3.new(0.1, 0.9, 0.1), CFrame.new(at + Vector3.new(math.cos(a) * 0.2, 0.4, math.sin(a) * 0.2)) * CFrame.Angles(math.sin(a) * 0.5, 0, math.cos(a) * 0.5), P.dryBush, f)
	end
	ball(0.35, at + Vector3.new(0, 0.3, 0), P.dryBush, f)
end

-- what grows on each island's ground (a bit is picked at random per item, so repeats are common)
local GROUND: { [string]: { Bit } } = {
	meadow = { snowLump, snowLump, crystal({ P.ice }), pebble(P.white) },
	forest = { tuft(P.leaves[2]), flower, fern, pebble(P.cliff), miniShroom(false) },
	grove = { miniShroom(true), miniShroom(true), tuft(P.leavesPink[1]), flower },
	beach = { shell, starfish, tuft(P.palm[1]), pebble(P.sandLight) },
	jungle = { fern, fern, flower, tuft(P.leaves[1]), miniShroom(false) },
	desert = { pebble(P.sand), dryBush, tuft(P.dryBush), pebble(P.cliff) },
	canyon = { pebble(P.cliff), dryBush, crystal({ P.pink, P.nova }) },
	volcano = { crack(P.lava), crack(P.lavaHot), pebble(P.volcanoDark), crystal({ P.lava }) },
	lavalake = { crystal(P.crystal), crack(P.pink), pebble(P.obsidian) },
	magma = { crack(P.lava), crack(P.lavaHot), crystal({ P.gold, P.lavaHot }), pebble(P.volcanoDark) },
}

function Spectacle.ground(tunnel: Instance)
	meshes = ReplicatedStorage:FindFirstChild("SceneryMeshes")
	rng = Scenery.rng(S.seed + 1)
	front, dens = true, 1
	local D = S.detail
	local list = Scenery.get()
	local half = W.tunnel.width / 2
	local root = folder("GroundDetail", tunnel)
	local function clearOf(x: number, z: number): boolean
		for _, group in { list.trees, list.sun, list.lava } do
			for _, s in group :: { any } do
				if (s.x - x) ^ 2 + (s.z - z) ^ 2 < (s.r + D.clear) ^ 2 then
					return false
				end
			end
		end
		return true
	end
	for _, zone in W.zones do
		local bits = GROUND[zone.theme]
		if not bits then
			continue
		end
		local f = folder("Island" .. zone.id, root)
		local n = math.round((zone.zMax - zone.zMin) * D.perStud)
		for _ = 1, n do
			local side = if rng() < 0.5 then -1 else 1
			-- sqrt pushes more of them toward the cliffs (World Rules 9: calm middle, richer edges)
			local x = side * (D.inner + math.sqrt(rng()) * (half - D.edgeMargin - D.inner))
			local z = zone.zMin + 6 + rng() * (zone.zMax - zone.zMin - 12)
			if clearOf(x, z) then
				for _ = 1, 2 + math.floor(rng() * 2) do
					local at = Vector3.new(x + (rng() - 0.5) * 4, 0, z + (rng() - 0.5) * 4)
					-- built at toy size, then grown round its foot by D.scale so it reads from the camera
					local tmp = Instance.new("Folder")
					bits[1 + math.floor(rng() * #bits)](tmp, at)
					for _, p in tmp:GetChildren() do
						if p:IsA("BasePart") then
							local cf = p.CFrame
							p.Size *= D.scale
							p.CFrame = cf.Rotation + (at + (cf.Position - at) * D.scale)
							p.Parent = f
						end
					end
					tmp:Destroy()
				end
			end
		end
	end
end

function Spectacle.build(far: Instance)
	meshes = ReplicatedStorage:FindFirstChild("SceneryMeshes")
	rng = Scenery.rng(S.seed)
	local root = folder("Spectacle", far)
	for _, zone in W.zones do
		local set = SETS[zone.id]
		if set then
			local f = folder("Island" .. zone.id, root)
			local stretch = (zone.zMax - zone.zMin) / S.baseLength
			front, dens = true, stretch * (1 + (zone.id - 1) * S.densityPerIsland)
			set(f, zone)
			if zone.id >= S.backFrom then
				front, dens = false, stretch * S.backDensity
				set(folder("Back", f), zone)
			end
		end
	end
	front, dens = true, 1
end

-- the whole map's colours, more saturated (owner 2026-11-13: "brighter and more striking"). White and
-- grey stay as they are (no hue to push); the Spectacle's and GroundDetail's own colours are already
-- full (pushed again, the desert's tan bushes turned lime).
function Spectacle.vivid(map: Instance)
	for _, d in map:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 1 and not d:FindFirstAncestor("Spectacle") and not d:FindFirstAncestor("GroundDetail") then
			local h, s, v = d.Color:ToHSV()
			if s > S.vividMinSat then
				d.Color = Color3.fromHSV(h, math.min(1, s * S.vividSaturation), math.min(1, v * S.vividValue))
			end
		end
	end
end

return Spectacle
