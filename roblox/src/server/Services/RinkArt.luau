--!strict
-- RinkArt: builds one Training Rink (Cold Power, 2026-11-10): a round ice floor floating in the sky
-- with a visible side face and a rocky underside (depth: thickness, not a flat disc), glowing rune
-- rings and tick marks on the floor, a snowflake under the ice sculpture in the middle, crystal
-- shards round the rim, and an invisible wall so nobody walks off. Sizes come from Config.rink,
-- colours from Theme.rink. Front = +Z: the fire sprites come in over that side (two glowing gate
-- posts mark the ends of their arc). TrainingService places one per pan slot and owns what happens on it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Theme = require(ReplicatedStorage.Shared.Theme)

local RinkArt = {}
local R = Config.rink
local T = Theme.rink

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

local function glow(p: BasePart, transparency: number?): BasePart
	p.Material = Enum.Material.Neon
	p.Transparency = transparency or 0
	p.CastShadow = false
	return p
end

-- a flat ring on the floor: a glowing disc with a floor-coloured disc on top of it, a little higher,
-- so only the rim shows (never flush: overlapping tops flicker)
local function ring(parent: Instance, centre: Vector3, radius: number, width: number, lift: number)
	glow(cyl(radius, 0.06, CFrame.new(centre + Vector3.new(0, lift, 0)), T.rune, parent), 0.1)
	cyl(radius - width, 0.06, CFrame.new(centre + Vector3.new(0, lift + 0.04, 0)), T.floor, parent, false, Enum.Material.Ice).CastShadow = false
end

-- centre = the middle of the floor's top face (players stand at centre.Y)
function RinkArt.build(parent: Instance, centre: Vector3, index: number): Model
	local m = Instance.new("Model")
	m.Name = "Rink" .. index
	local rad = R.radius
	local at = CFrame.new(centre)
	-- the floor: thick ice with a darker side band and a rocky underside tapering down
	local floor = cyl(rad, 3, at * CFrame.new(0, -1.5, 0), T.floor, m, true, Enum.Material.Ice)
	floor.Name = "Floor"
	cyl(rad + 0.6, 1.6, at * CFrame.new(0, -2.2, 0), T.floorSide, m, false, Enum.Material.Glacier)
	cyl(rad * 0.82, 4, at * CFrame.new(0, -5, 0), T.floorSide:Lerp(Theme.ink, 0.25), m, false, Enum.Material.Slate)
	cyl(rad * 0.5, 5, at * CFrame.new(0, -9.4, 0), T.floorSide:Lerp(Theme.ink, 0.4), m, false, Enum.Material.Slate)
	-- the rune circle: two rings, tick marks between them, a six-armed snowflake in the middle
	ring(m, centre, rad - 3, 0.5, 0.03)
	ring(m, centre, rad * 0.55, 0.4, 0.12)
	for i = 0, 23 do
		local a = i / 24 * math.pi * 2
		local long = i % 2 == 0
		local r = rad - 5.2
		glow(block(Vector3.new(0.3, 0.06, if long then 2.4 else 1.2), at * CFrame.Angles(0, a, 0) * CFrame.new(0, 0.23, r), T.rune, m), 0.15)
	end
	for i = 0, 2 do
		local arm = glow(block(Vector3.new(0.5, 0.06, rad * 0.9), at * CFrame.Angles(0, i * math.pi / 3, 0) * CFrame.new(0, 0.25, 0), T.rune, m), 0.25)
		arm.Name = "Snowflake"
	end
	-- the ice sculpture the sprites want to reach: a pedestal and a cluster of tilted crystals
	local sr = R.sculptureRadius
	cyl(sr, 1.2, at * CFrame.new(0, 0.6, 0), T.floorSide, m, true, Enum.Material.Glacier).Name = "Pedestal"
	cyl(sr * 0.8, 0.5, at * CFrame.new(0, 1.45, 0), T.sculpture, m, true, Enum.Material.Ice)
	local tilts = { { 0, 0, 0, 9, 2.6 }, { 0.5, 0.35, 1.2, 6.5, 2 }, { 2.6, -0.4, -1.1, 5.5, 1.8 }, { 4.4, 0.3, 0.9, 4.6, 1.6 } }
	for _, t in tilts do
		local yaw, lean, off, h, w = t[1], t[2], t[3], t[4], t[5]
		local c = block(Vector3.new(w, h, w), at * CFrame.new(off, 1.6 + h / 2 - 0.3, off * 0.6) * CFrame.Angles(0, yaw, lean) * CFrame.Angles(0, math.pi / 4, 0), T.sculpture, m, false, Enum.Material.Glass)
		c.Transparency = 0.25
		c.Reflectance = 0.15
		c.Name = "Sculpture"
	end
	local core = glow(block(Vector3.new(1.2, 5, 1.2), at * CFrame.new(0, 4.4, 0) * CFrame.Angles(0, math.pi / 4, 0), T.rune, m), 0.35)
	core.Name = "SculptureCore"
	local l = Instance.new("PointLight")
	l.Color = T.rune
	l.Range = 26
	l.Brightness = 1.2
	l.Shadows = false
	l.Parent = core
	-- crystal shards round the rim (not across the front arc's middle, so nothing hides a sprite coming in)
	for i = 0, 15 do
		local a = (i + 0.5) / 16 * math.pi * 2
		local h = 4 + (i * 7 % 5) * 1.3
		local c = block(Vector3.new(1.6, h, 1.6), at * CFrame.Angles(0, a, 0) * CFrame.new(0, h / 2 - 0.4, rad + 0.4) * CFrame.Angles(0.25, math.pi / 4, 0), T.crystal, m, false, Enum.Material.Glass)
		c.Transparency = 0.2
		c.CastShadow = false
		c.Name = "Shard"
	end
	-- the two gate posts at the ends of the sprites' arc
	for _, s in { -1, 1 } do
		local a = s * math.rad(R.arc / 2 + 6)
		local post = glow(block(Vector3.new(1, 9, 1), at * CFrame.Angles(0, a, 0) * CFrame.new(0, 4.5, rad - 1.2), Theme.rink.flameCore, m), 0.2)
		post.Name = "ArcPost"
	end
	-- the invisible wall
	local n = 24
	local seg = 2 * math.pi * (rad + 1) / n + 0.6
	for i = 0, n - 1 do
		local wall = block(Vector3.new(seg, R.wallHeight, 1), at * CFrame.Angles(0, i / n * math.pi * 2, 0) * CFrame.new(0, R.wallHeight / 2, rad + 1), T.floor, m, true)
		wall.Transparency = 1
		wall.CastShadow = false
		wall.CanQuery = false
		wall.Name = "Wall"
	end
	m.Parent = parent
	return m
end

return RinkArt
