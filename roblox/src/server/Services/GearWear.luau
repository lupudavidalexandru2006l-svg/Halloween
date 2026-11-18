--!strict
-- GearWear (owner 2026-11-15: "actual models for the gear so you can see it on your character"): every
-- gear you own (the player's Gear_<key> attributes, GearService) is worn on your avatar, seen by everyone.
--  Frost Boots (2026-11-17 rework): purple boots with fur cuffs that grow a new look every
--  Config.gearBootsTierEvery levels: frost puffs, then sparkles and a glowing sole, then a glow ribbon
--  trail and ice spikes, then crystal blades, then an aurora trail and little gold wings (level 10).
--  Frost Pack: a chunky turquoise backpack with straps over the shoulders and an ice block on top, misty.
--  Cozy Hat: a gold knitted beanie, a big pompom, a coin emblem and gold stars.
-- Meshes live in ServerStorage.GearMeshes (2026-11-18): boots, cap and pack are Blender-built Models (one MeshPart per colour, coloured from
-- Config.gearWear.meshLook) scaled to the head / torso, their pivot = the Blender origin (head or torso
-- centre), facing -Z. The boot level extras are parts on top. All welded, massless, no collisions or
-- shadows. If a mesh is missing the old part-built shape is used.
-- Worn gear replaces what it covers (owner 2026-11-18): the Cozy Cap hides hair and hat accessories, the
-- Frost Boots hide the feet, lower legs and shoe accessories; taking the gear off shows them again.
-- Looks only: what the gear does stays in GearService and Config.gearValue.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Config = require(ReplicatedStorage.Shared.Config)

local GearWear = {}
local GW = Config.gearWear
local KEYS = { "frost_boots", "frost_pack", "cozy_hat" } -- gloves and vest removed (owner 2026-11-17)
local UPRIGHT = CFrame.Angles(0, 0, math.pi / 2) -- a cylinder's length runs along X: stand it up
local FACING = CFrame.Angles(0, math.pi / 2, 0) -- or point it forward / back (Z)

local function piece(model: Model, limb: BasePart, shape: Enum.PartType, size: Vector3, at: CFrame, color: Color3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Shape = shape
	p.Size = size
	p.CFrame = limb.CFrame * at
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	p.Anchored = false
	p.Massless = true
	p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = false, false, false, false
	if p.Material == Enum.Material.Metal then
		p.Reflectance = 0.15
	end
	local w = Instance.new("WeldConstraint")
	w.Part0 = limb
	w.Part1 = p
	w.Parent = p
	p.Parent = model
	return p
end

-- a clone of a GearMeshes Model, scaled, placed by its pivot and welded to the limb; each part coloured
-- from Config.gearWear.meshLook[name][part]
local function meshModel(model: Model, limb: BasePart, name: string, scale: number, at: CFrame): Model?
	local folder = ServerStorage:FindFirstChild("GearMeshes")
	local src = folder and folder:FindFirstChild(name)
	if not (src and src:IsA("Model")) then
		return nil
	end
	local g = src:Clone()
	g:ScaleTo(scale)
	g:PivotTo(limb.CFrame * at)
	local looks = GW.meshLook[name] or {}
	for _, p in g:GetChildren() do
		if p:IsA("BasePart") then
			local look = looks[p.Name]
			if look then
				p.Color = look.color
				p.Material = look.material
				p.Transparency = look.transparency or 0
				p.Reflectance = look.reflectance or 0
			end
			p.Anchored = false
			p.Massless = true
			p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = false, false, false, false
			local w = Instance.new("WeldConstraint")
			w.Part0 = limb
			w.Part1 = p
			w.Parent = p
		end
	end
	g.Parent = model
	return g
end

-- hide a body part or accessory handle under worn gear, remembering how see-through it was
local function hide(part: BasePart, hidden: boolean)
	local was = part:GetAttribute("GearWearShown")
	if hidden then
		if was == nil then
			part:SetAttribute("GearWearShown", part.Transparency)
		end
		part.Transparency = 1
	elseif typeof(was) == "number" then
		part.Transparency = was
		part:SetAttribute("GearWearShown", nil)
	end
end

local HAIR_TYPES = { [Enum.AccessoryType.Hair] = true, [Enum.AccessoryType.Hat] = true }
local SHOE_TYPES = { [Enum.AccessoryType.LeftShoe] = true, [Enum.AccessoryType.RightShoe] = true }

-- cap on: hair and hats hidden; boots on: feet, lower legs and shoes hidden
local function cover(c: Model, cap: boolean, boots: boolean)
	for _, a in c:GetChildren() do
		if a:IsA("Accessory") then
			local handle = a:FindFirstChild("Handle")
			if handle and handle:IsA("BasePart") then
				if HAIR_TYPES[a.AccessoryType] then
					hide(handle, cap)
				elseif SHOE_TYPES[a.AccessoryType] then
					hide(handle, boots)
				end
			end
		end
	end
	for _, name in { "LeftFoot", "RightFoot", "LeftLowerLeg", "RightLowerLeg" } do
		local limb = c:FindFirstChild(name)
		if limb and limb:IsA("BasePart") then
			hide(limb, boots)
		end
	end
end

local function block(m: Model, limb: BasePart, size: Vector3, at: CFrame, color: Color3, material: Enum.Material?): Part
	return piece(m, limb, Enum.PartType.Block, size, at, color, material)
end

-- an upright cylinder (length along Y)
local function ring(m: Model, limb: BasePart, length: number, dia: number, at: CFrame, color: Color3, material: Enum.Material?): Part
	return piece(m, limb, Enum.PartType.Cylinder, Vector3.new(length, dia, dia), at * UPRIGHT, color, material)
end

-- a disc or tube pointing along Z
local function disc(m: Model, limb: BasePart, length: number, dia: number, at: CFrame, color: Color3, material: Enum.Material?): Part
	return piece(m, limb, Enum.PartType.Cylinder, Vector3.new(length, dia, dia), at * FACING, color, material)
end

local function ball(m: Model, limb: BasePart, dia: number, at: CFrame, color: Color3, material: Enum.Material?): Part
	return piece(m, limb, Enum.PartType.Ball, Vector3.one * dia, at, color, material)
end

local function glow(p: Part, color: Color3): Part
	p.Material = Enum.Material.Neon
	p.Color = color
	return p
end

-- a few slow sparkles (or puffs) on a piece; rate 0 on the server's own setting is never used
local function sparkle(p: Part, color: Color3, mist: boolean?)
	local e = Instance.new("ParticleEmitter")
	e.Color = ColorSequence.new(color)
	e.LightEmission = if mist then 0.2 else 1
	e.Size = if mist then NumberSequence.new(0.15, 0.5) else NumberSequence.new(0.12, 0)
	e.Transparency = NumberSequence.new(if mist then 0.4 else 0, 1)
	e.Lifetime = NumberRange.new(0.5, 0.9)
	e.Speed = NumberRange.new(if mist then 0.6 else 0.4, if mist then 1.2 else 1.2)
	e.SpreadAngle = Vector2.new(40, 40)
	e.Rate = GW.sparkle
	e.Parent = p
end

-- a ribbon behind a boot (Trail between two attachments on its sole)
local function ribbon(p: Part, colors: ColorSequence, life: number)
	local a0, a1 = Instance.new("Attachment"), Instance.new("Attachment")
	a0.Position = Vector3.new(0, p.Size.Y * 0.5, 0)
	a1.Position = Vector3.new(0, -p.Size.Y * 0.5, 0)
	a0.Parent, a1.Parent = p, p
	local t = Instance.new("Trail")
	t.Attachment0, t.Attachment1 = a0, a1
	t.Color = colors
	t.LightEmission = 1
	t.Transparency = NumberSequence.new(0.15, 1)
	t.Lifetime = life
	t.FaceCamera = true
	t.Parent = p
end

-- the Frost Boots at a level: tier = level // gearBootsTierEvery (0 at level 1, 5 at level 10)
local function feet(m: Model, c: Model, level: number)
	local tier = level // Config.gearBootsTierEvery
	for _, side in { -1, 1 } do
		local foot = c:FindFirstChild(if side > 0 then "RightFoot" else "LeftFoot") :: BasePart?
		if not foot then
			continue
		end
		local F = foot.Size
		local main, fur = GW.boots.main, GW.boots.fur
		-- the boot (Blender-built Model, made round a reference lower leg), welded to the lower leg and scaled
		-- so its sole sits on the foot's bottom and its fur cuff at the knee
		local B = GW.bootMesh
		local leg = c:FindFirstChild(if side > 0 then "RightLowerLeg" else "LeftLowerLeg") :: BasePart?
		local boot: Model? = nil
		if leg then
			local sole = leg.CFrame:PointToObjectSpace((foot.CFrame * CFrame.new(0, -F.Y / 2, 0)).Position)
			local s = (leg.Size.Y / 2 - sole.Y) / B.soleToKnee
			boot = meshModel(m, leg, "frost_boot", s, CFrame.new(0, sole.Y + B.soleBelow * s, 0))
		end
		local shell = boot
		local cuff: BasePart
		if boot then
			cuff = (boot:FindFirstChild("fur") or boot:FindFirstChildWhichIsA("BasePart")) :: BasePart
		else
			block(m, foot, Vector3.new(F.X * 1.15, F.Y * 1.25, F.Z * 0.9), CFrame.new(0, F.Y * 0.1, F.Z * 0.08), main)
			piece(m, foot, Enum.PartType.Cylinder, Vector3.new(F.X * 1.15, F.Y * 1.25, F.Y * 1.25), CFrame.new(0, F.Y * 0.1, -F.Z * 0.38), main)
			ring(m, foot, F.Y * 1.6, F.X * 1.1, CFrame.new(0, F.Y * 1.2, F.Z * 0.14), main)
			cuff = ring(m, foot, F.Y * 0.42, F.X * 1.26, CFrame.new(0, F.Y * 2.0, F.Z * 0.14), fur, Enum.Material.Fabric)
		end
		if tier >= 1 then
			sparkle(cuff, GW.fur, true) -- frost puffs
		end
		if tier >= 2 then
			local sole = glow(block(m, foot, Vector3.new(F.X * 1.18, F.Y * 0.14, F.Z * 0.95), CFrame.new(0, -F.Y * 0.5, F.Z * 0.04), GW.ice), GW.ice)
			sparkle(sole, GW.ice)
			if tier >= 3 then
				ribbon(sole, if tier >= 5 then GW.aurora else ColorSequence.new(GW.ice, GW.fur), if tier >= 5 then 0.6 else 0.35)
			end
		end
		if tier >= 5 then
			-- level 10: little gold wings at the heel
			for _, up in { 0.55, 1.0 } do
				block(m, foot, Vector3.new(F.X * 0.08, F.Y * 0.32, F.Z * 0.75 * up), CFrame.new(side * F.X * 0.66, F.Y * (0.9 + up * 0.5), F.Z * 0.3) * CFrame.Angles(-0.5, 0, side * 0.35), GW.gold, Enum.Material.Metal)
			end
		end
		if tier >= 3 then
			-- ice crystal spikes at the toe and the heel (the part-built boot also gets the mesh's strap and buckle)
			if not shell then
				ring(m, foot, F.Y * 0.22, F.X * 1.2, CFrame.new(0, F.Y * 1.0, F.Z * 0.14), GW.steelDark, Enum.Material.Metal)
				block(m, foot, Vector3.new(F.X * 0.4, F.Y * 0.36, F.Z * 0.08), CFrame.new(0, F.Y * 1.0, -F.Z * 0.24), GW.steel, Enum.Material.Metal)
			end
			for k, spike in { { 0, -0.62, -0.5 }, { -0.3, -0.55, -0.3 }, { 0.3, -0.55, -0.3 }, { -0.25, 0.55, 0.45 }, { 0.25, 0.55, 0.45 } } do
				local tilt = CFrame.Angles(spike[3], 0, spike[1] * 0.8)
				local s = block(m, foot, Vector3.new(F.X * 0.2, F.Y * (if k == 1 then 0.9 else 0.7), F.X * 0.2), CFrame.new(spike[1] * F.X, F.Y * 0.35, spike[2] * F.Z) * tilt, GW.ice, Enum.Material.Neon)
				s.Transparency = 0.1
			end
			sparkle(cuff, GW.ice)
		end
		if tier >= 4 then
			-- crystal blades on two struts, an ice edge, and a booster on the heel
			block(m, foot, Vector3.new(F.X * 0.14, F.Y * 0.16, F.Z * 1.35), CFrame.new(0, -F.Y * 0.72, -F.Z * 0.04), GW.steel, Enum.Material.Metal)
			for _, z in { -0.36, 0.34 } do
				block(m, foot, Vector3.new(F.X * 0.14, F.Y * 0.4, F.Z * 0.14), CFrame.new(0, -F.Y * 0.48, z * F.Z), GW.steelDark, Enum.Material.Metal)
			end
			local edge = glow(block(m, foot, Vector3.new(F.X * 0.16, F.Y * 0.05, F.Z * 1.3), CFrame.new(0, -F.Y * 0.81, -F.Z * 0.04), GW.ice), GW.ice)
			edge.Transparency = 0.2
			disc(m, foot, F.Z * 0.25, F.Y * 0.62, CFrame.new(0, F.Y * 0.35, F.Z * 0.56), GW.steel, Enum.Material.Metal)
			local nozzle = glow(disc(m, foot, F.Z * 0.05, F.Y * 0.42, CFrame.new(0, F.Y * 0.35, F.Z * 0.69), GW.ice), GW.ice)
			sparkle(nozzle, GW.fur, true)
		end
	end
end

-- the Frost Pack: a backpack with an ice block in it
local function pack(m: Model, c: Model)
	local torso = c:FindFirstChild("UpperTorso") :: BasePart?
	if not torso then
		return
	end
	local T = torso.Size
	local P = GW.packMesh
	-- built for a 2x2x1 torso; scaled so it is as wide and as deep as this one (straps on the chest)
	local s = math.max(T.X / 2, T.Z) * P.scale
	local bag = meshModel(m, torso, "frost_pack", s, CFrame.new(0, T.Y * P.lift, T.Z / 2 - s / 2))
	if bag then
		local ice = bag:FindFirstChild("ice")
		if ice then
			sparkle(ice :: Part, GW.fur, true)
		end
		return
	end
	local z = T.Z * 0.85
	block(m, torso, Vector3.new(T.X * 0.78, T.Y * 0.82, T.Z * 0.62), CFrame.new(0, -T.Y * 0.04, z), GW.pack.main, Enum.Material.Fabric)
	block(m, torso, Vector3.new(T.X * 0.82, T.Y * 0.16, T.Z * 0.66), CFrame.new(0, T.Y * 0.36, z), GW.pack.dark, Enum.Material.Fabric)
	for _, s in { -1, 1 } do -- straps
		block(m, torso, Vector3.new(T.X * 0.12, T.Y * 0.9, T.Z * 0.1), CFrame.new(s * T.X * 0.28, 0, -T.Z * 0.55), GW.pack.dark, Enum.Material.Fabric)
	end
	local ice = block(m, torso, Vector3.new(T.X * 0.5, T.X * 0.5, T.Z * 0.2), CFrame.new(0, -T.Y * 0.06, z + T.Z * 0.32), GW.ice, Enum.Material.Glass)
	ice.Transparency = 0.25
	sparkle(ice, GW.fur, true)
end

local function hat(m: Model, c: Model)
	local head = c:FindFirstChild("Head") :: BasePart?
	if not head then
		return
	end
	local D, C = head.Size, GW.hat
	local H = GW.hatMesh
	-- built for a 1x1x1 head
	local cap = meshModel(m, head, "hat", D.X * H.scale, CFrame.new(0, D.Y * H.lift, 0))
	if cap then
		local pom = cap:FindFirstChild("pom")
		if pom then
			sparkle(pom :: Part, GW.gold)
		end
		return
	end
	ring(m, head, D.Y * 0.28, D.X * 1.22, CFrame.new(0, D.Y * 0.32, 0), C.cuff, Enum.Material.Fabric)
	ring(m, head, D.Y * 0.3, D.X * 1.15, CFrame.new(0, D.Y * 0.55, 0), C.main, Enum.Material.Fabric)
	ball(m, head, D.X * 1.15, CFrame.new(0, D.Y * 0.62, 0), C.main, Enum.Material.Fabric)
	local pom = ball(m, head, D.X * 0.6, CFrame.new(0, D.Y * 1.28, 0), GW.fur, Enum.Material.Fabric)
	sparkle(pom, GW.gold)
	-- the coin emblem on the front of the cuff, gold stars round it
	disc(m, head, D.Z * 0.08, D.X * 0.4, CFrame.new(0, D.Y * 0.32, -D.Z * 0.62), GW.gold, Enum.Material.Metal)
	glow(disc(m, head, D.Z * 0.09, D.X * 0.18, CFrame.new(0, D.Y * 0.32, -D.Z * 0.63), GW.gold), GW.gold)
	for _, a in { -1.1, -0.55, 0.55, 1.1, math.pi } do
		local r = D.X * 0.62
		block(m, head, Vector3.new(D.X * 0.12, D.X * 0.12, D.X * 0.03), CFrame.Angles(0, a, 0) * CFrame.new(0, D.Y * 0.62, -r) * CFrame.Angles(0, 0, math.pi / 4), GW.gold, Enum.Material.Metal)
	end
end

local function owns(player: Player, key: string): boolean
	return player:GetAttribute("Gear_" .. key) == true
end

local function levelOf(player: Player, key: string): number
	local v = player:GetAttribute("GearLv_" .. key)
	return if typeof(v) == "number" then v else 0
end

function GearWear.refresh(player: Player)
	local c = player.Character
	if not c or not c:FindFirstChild("UpperTorso") then
		return -- R15 only (the place's avatars are R15)
	end
	local old = c:FindFirstChild("GearWear")
	if old then
		old:Destroy()
	end
	local m = Instance.new("Model")
	m.Name = "GearWear"
	local ok, err = pcall(function()
		local boots = levelOf(player, "frost_boots")
		if boots > 0 then
			feet(m, c, boots)
		end
		if owns(player, "frost_pack") then
			pack(m, c)
		end
		if owns(player, "cozy_hat") then
			hat(m, c)
		end
	end)
	if not ok then
		warn("[GearWear]", err)
	end
	-- only hide what a mesh really covers (the part-built fallbacks don't)
	cover(c, m:FindFirstChild("hat") ~= nil, m:FindFirstChild("frost_boot") ~= nil)
	m.Parent = c
end

function GearWear.Init() end

function GearWear.Start()
	local function watch(player: Player)
		player.CharacterAppearanceLoaded:Connect(function()
			GearWear.refresh(player)
		end)
		for _, key in KEYS do
			player:GetAttributeChangedSignal("Gear_" .. key):Connect(function()
				GearWear.refresh(player)
			end)
		end
		-- a new boots level can bring a new look (every Config.gearBootsTierEvery levels)
		player:GetAttributeChangedSignal("GearLv_frost_boots"):Connect(function()
			GearWear.refresh(player)
		end)
		if player.Character and player:HasAppearanceLoaded() then
			GearWear.refresh(player)
		end
	end
	Players.PlayerAdded:Connect(watch)
	for _, p in Players:GetPlayers() do
		task.spawn(watch, p)
	end
end

return GearWear
