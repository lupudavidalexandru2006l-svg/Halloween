--!strict
-- TrainingArt: builds a pan's Cold Power trainer (owner 2026-11-10; replaces the sky rink and its door).
-- From the owner's references (hit simulators' training dummies, and training gear in every base): a
-- raised pad with a visible side and its own floor in front of the pan, right of its door, walls on
-- three sides, the open side toward the pan, and a warm target on the plaza side that the client
-- frosts over as you shoot it (local +Z, Config.trainerFrame, faces the plaza). Its four levels get hotter and grander like the islands: a snowman in a rustic yard, a
-- heat bag in a boxing ring, a magma golem in a stone keep, a little sun in a sci-fi lab. TrainingService
-- builds each pan's trainer at its owner's level and rebuilds it on an upgrade. Sizes and places:
-- Config.training; colours: Theme.training.
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

-- parts the client turns (MapController): Kind "spin" round the Pivot's local Axis at Speed rad/s
local function spinner(parent: Instance, pivot: CFrame, axis: Vector3, speed: number): Folder
	local f = folder("Motion", parent)
	f:SetAttribute("Kind", "spin")
	f:SetAttribute("Pivot", pivot)
	f:SetAttribute("Axis", axis)
	f:SetAttribute("Speed", speed)
	CollectionService:AddTag(f, Config.mapFx.motionTag)
	return f
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

-- ---------- 1. the snowman yard: snowy checker floor, a plank path, a log fence with snow caps ----------
local function snowmanYard(f: Instance, at: CFrame, i: number)
	local P = TT.stations.snowman
	pad(f, at, P.floor, P.tile, TT.padEdge, Enum.Material.SmoothPlastic, "checker")
	-- the plank path from the open side to the dummy
	for k = 0, 2 do
		quiet(block(Vector3.new(2.6, 0.14, 1.6), at * CFrame.new(if k % 2 == 0 then -0.3 else 0.3, H + 0.08, -D / 2 + 1.2 + k * 2.2) * CFrame.Angles(0, (k % 2 - 0.5) * 0.12, 0), P.wood, f, false, Enum.Material.WoodPlanks))
	end
	-- the fence: posts with snow caps and two rails, on the left, right and back
	local function fenceLine(a: Vector3, b: Vector3)
		local len = (b - a).Magnitude
		local n = math.max(1, math.floor(len / 2.9))
		for k = 0, n do
			local p = a:Lerp(b, k / n)
			block(Vector3.new(0.55, 2.7, 0.55), at * CFrame.new(p.X, H + 1.35, p.Z), P.wood, f, true, Enum.Material.WoodPlanks)
			quiet(ellipsoid(Vector3.new(0.85, 0.45, 0.85), at * CFrame.new(p.X, H + 2.75, p.Z), P.snow, f))
		end
		local mid = (a + b) / 2
		local look = CFrame.lookAt(Vector3.new(mid.X, 0, mid.Z), Vector3.new(b.X, 0, b.Z))
		for _, y in { 1, 2 } do
			block(Vector3.new(0.22, 0.32, len), at * look * CFrame.new(0, H + y, 0), P.woodDark, f, true, Enum.Material.WoodPlanks)
		end
	end
	local x, z = W / 2 - 0.45, D / 2 - 0.45
	fenceLine(Vector3.new(-x, 0, -z), Vector3.new(-x, 0, z))
	fenceLine(Vector3.new(x, 0, -z), Vector3.new(x, 0, z))
	fenceLine(Vector3.new(-x, 0, z), Vector3.new(x, 0, z))
	-- a barrel and a pile of snowballs in the back corners
	local bx, bz = -W / 2 + 1.4, D / 2 - 1.4
	cyl(0.95, 1.9, at * CFrame.new(bx, H + 0.95, bz), P.wood, f, true, Enum.Material.WoodPlanks)
	for _, y in { 0.45, 1.45 } do
		quiet(cyl(0.99, 0.16, at * CFrame.new(bx, H + y, bz), P.woodDark, f))
	end
	quiet(cyl(0.8, 0.08, at * CFrame.new(bx, H + 1.93, bz), P.woodDark:Lerp(Theme.white, 0.2), f))
	local sx, sz = W / 2 - 1.6, D / 2 - 1.4
	for k, s in { { 0, 0.3 }, { 0.8, 0.1 }, { 0.35, -0.6 } } do
		ball(0.55, (at * CFrame.new(sx + s[1], H + 0.5, sz + s[2])).Position, P.snow, f)
		if k == 1 then
			ball(0.5, (at * CFrame.new(sx + 0.35, H + 1.25, sz - 0.1)).Position, P.snow, f)
		end
	end
	-- the Snowman Dummy: a wooden stand, three snowballs, a bullseye on its chest, X eyes, a carrot,
	-- a red bucket hat with a gold band, a blue scarf and stick arms
	local tz = T.targetZ
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

-- ---------- 2. the heat bag ring: a boxing ring with ropes and a red heat bag on a navy frame ----------
local function heatBagRing(f: Instance, at: CFrame, i: number)
	local P = TT.stations.heatbag
	pad(f, at, P.floor, P.tile, P.post, Enum.Material.SmoothPlastic, "grid")
	local tz = T.targetZ
	-- the round mat under the bag: red, cream, red (each a little higher)
	for k, r in { 3, 2.4, 1.8 } do
		quiet(cyl(r, 0.05, at * CFrame.new(0, H + 0.03 + k * 0.03, tz - 0.4), if k == 2 then P.matRing else P.mat, f))
	end
	-- corner posts with red caps, ropes on three sides (the open side faces the pans)
	local px, pz = W / 2 - 0.6, D / 2 - 0.6
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			cyl(0.45, 4.4, at * CFrame.new(sx * px, H + 2.2, sz * pz), P.post, f, true)
			cyl(0.62, 0.7, at * CFrame.new(sx * px, H + 4.6, sz * pz), P.cap, f)
			quiet(cyl(0.5, 0.3, at * CFrame.new(sx * px, H + 0.5, sz * pz), P.rope, f))
		end
	end
	for _, y in { 1.5, 2.5, 3.5 } do
		for _, sx in { -1, 1 } do
			quiet(rod(D - 1.2, 0.12, at * CFrame.new(sx * px, H + y, 0) * CFrame.Angles(0, math.pi / 2, 0), P.rope, f))
		end
		quiet(rod(W - 1.2, 0.12, at * CFrame.new(0, H + y, pz), P.rope, f))
	end
	-- the corner stool, and a towel over the ropes
	local st = at * CFrame.new(-px + 1.2, H, -pz + 1.2)
	cyl(0.75, 0.25, st * CFrame.new(0, 1.3, 0), P.cap, f, true)
	for _, a in { 0, 2.1, 4.2 } do
		quiet(block(Vector3.new(0.18, 1.25, 0.18), st * CFrame.Angles(0, a, 0) * CFrame.new(0.45, 0.62, 0), P.post, f))
	end
	quiet(block(Vector3.new(0.12, 1.4, 1.6), at * CFrame.new(px + 0.05, H + 2.9, 2), P.band, f))
	-- the frame: two posts and a beam, gold bolts, braces in the corners
	local fz = tz + 0.2
	local top = 9.4
	for _, s in { -1, 1 } do
		block(Vector3.new(0.9, top, 0.9), at * CFrame.new(s * 3.4, H + top / 2, fz), P.post, f, true)
		quiet(block(Vector3.new(0.4, 2.2, 0.5), at * CFrame.new(s * 2.55, H + top - 0.95, fz) * CFrame.Angles(0, 0, s * 0.78), P.post, f))
		cyl(0.55, 0.4, at * CFrame.new(s * 3.4, H + 0.2, fz), P.cap, f)
	end
	block(Vector3.new(8, 0.9, 1.1), at * CFrame.new(0, H + top, fz), P.post, f)
	for _, x in { -2.2, 2.2 } do
		quiet(rod(0.12, 0.22, at * CFrame.new(x, H + top, fz - 0.58) * CFrame.Angles(0, math.pi / 2, 0), Theme.coin, f))
	end
	-- the chain, link by link, from the beam to the bag's top
	local bagY, bagH = 4.6, 4.6
	local hang = at * CFrame.new(0, H + top - 0.45, tz)
	local links = 4
	local drop = (top - 0.45) - (bagY + bagH / 2)
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

-- ---------- 3. the magma golem keep: stone walls with battlements, a red carpet, cold-flame braziers ----------
local function golemKeep(f: Instance, at: CFrame, i: number)
	local P = TT.stations.golem
	pad(f, at, P.floor, P.tile, P.wallDark, Enum.Material.Slate, "grid")
	local tz = T.targetZ
	-- the red carpet with gold edges, from the open side to the golem
	local cz0, cz1 = -D / 2 + 0.3, tz - 1.6
	local cl = cz1 - cz0
	quiet(block(Vector3.new(3.4, 0.08, cl), at * CFrame.new(0, H + 0.05, (cz0 + cz1) / 2), P.carpet, f, false, Enum.Material.Fabric))
	for _, s in { -1, 1 } do
		quiet(block(Vector3.new(0.22, 0.1, cl), at * CFrame.new(s * 1.8, H + 0.06, (cz0 + cz1) / 2), P.gold, f))
	end
	-- the walls on three sides, battlements on top
	local wx, wz = W / 2 - 0.5, D / 2 - 0.5
	local function wall(cf: CFrame, len: number)
		block(Vector3.new(1, 2.2, len), cf * CFrame.new(0, H + 1.1, 0), P.wall, f, true, Enum.Material.Cobblestone)
		quiet(block(Vector3.new(1.15, 0.3, len), cf * CFrame.new(0, H + 0.15, 0), P.wallDark, f))
		local n = math.floor(len / 2)
		for k = 0, n - 1 do
			block(Vector3.new(1.05, 0.85, 1), cf * CFrame.new(0, H + 2.62, -len / 2 + (k + 0.5) * len / n), P.wall, f, false, Enum.Material.Cobblestone)
		end
	end
	wall(at * CFrame.new(-wx, 0, 0), D)
	wall(at * CFrame.new(wx, 0, 0), D)
	wall(at * CFrame.new(0, 0, wz) * CFrame.Angles(0, math.pi / 2, 0), W - 2)
	-- towers in the back corners with gold crowns
	for _, s in { -1, 1 } do
		local tw = at * CFrame.new(s * (W / 2 - 0.9), 0, D / 2 - 0.9)
		block(Vector3.new(1.8, 5.4, 1.8), tw * CFrame.new(0, H + 2.7, 0), P.wallDark, f, true, Enum.Material.Cobblestone)
		block(Vector3.new(2.3, 0.4, 2.3), tw * CFrame.new(0, H + 5.6, 0), P.gold, f)
		shape("Octa", Vector3.new(1.2, 1.8, 1.2), tw * CFrame.new(0, H + 6.7, 0), P.gold, f)
	end
	-- braziers at the open side's corners: stone pillars, gold bowls, cold blue flames
	for _, s in { -1, 1 } do
		local b = at * CFrame.new(s * (W / 2 - 0.9), 0, -D / 2 + 0.9)
		block(Vector3.new(1.7, 3, 1.7), b * CFrame.new(0, H + 1.5, 0), P.wall, f, true, Enum.Material.Cobblestone)
		cyl(1.05, 0.6, b * CFrame.new(0, H + 3.3, 0), P.gold, f)
		local flame = glow(shape("Octa", Vector3.new(0.95, 1.9, 0.95), b * CFrame.new(0, H + 4.35, 0), P.flame, f), 0.05)
		light(flame, P.flame, 12, 0.9)
		sparkles(f, Vector3.new(1, 0.4, 1), b * CFrame.new(0, H + 3.9, 0), P.flame, 6, 2.4, 0.3)
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

-- ---------- 4. the little sun lab: a navy deck with neon edges, pylons, glass rails, a sun in rings ----------
local function sunLab(f: Instance, at: CFrame, i: number)
	local P = TT.stations.sun
	pad(f, at, P.floor, P.tile, P.pylon, Enum.Material.SmoothPlastic, "checker")
	local tz = T.targetZ
	-- neon strips round the deck's edge
	for _, s in { -1, 1 } do
		quiet(glow(block(Vector3.new(0.25, 0.06, D - 0.6), at * CFrame.new(s * (W / 2 - 0.3), H + 0.03, 0), P.neon, f)))
		quiet(glow(block(Vector3.new(W - 0.6, 0.06, 0.25), at * CFrame.new(0, H + 0.03, s * (D / 2 - 0.3)), P.neon, f)))
	end
	-- pylons at the corners: navy towers, white caps, a pink neon stripe facing in, a light on top
	local px, pz = W / 2 - 0.75, D / 2 - 0.75
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			local p = at * CFrame.new(sx * px, 0, sz * pz)
			local h = if sz > 0 then 7 else 4.5 -- the back pair taller, so the deck reads as a stage
			block(Vector3.new(1.5, h, 1.5), p * CFrame.new(0, H + h / 2, 0), P.pylon, f, true)
			block(Vector3.new(1.8, 0.35, 1.8), p * CFrame.new(0, H + h + 0.17, 0), P.trim, f)
			quiet(glow(block(Vector3.new(0.25, h - 1.2, 0.25), p * CFrame.new(-sx * 0.76, H + h / 2, -sz * 0.4), P.neonAlt, f)))
			quiet(glow(block(Vector3.new(0.6, 0.6, 0.6), p * CFrame.new(0, H + h + 0.65, 0), P.neon, f)))
		end
	end
	-- glass rails between the pylons on three sides (see-through panels are SmoothPlastic, World Rules 6)
	local function rail(cf: CFrame, len: number)
		local glass = quiet(block(Vector3.new(0.25, 1.5, len), cf * CFrame.new(0, H + 0.85, 0), P.neon, f, true))
		glass.Transparency = 0.7
		block(Vector3.new(0.4, 0.22, len), cf * CFrame.new(0, H + 1.7, 0), P.trim, f)
	end
	rail(at * CFrame.new(-px, 0, 0), D - 3)
	rail(at * CFrame.new(px, 0, 0), D - 3)
	rail(at * CFrame.new(0, 0, pz) * CFrame.Angles(0, math.pi / 2, 0), W - 3)
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
	snowman = snowmanYard,
	heatbag = heatBagRing,
	golem = golemKeep,
	sun = sunLab,
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
