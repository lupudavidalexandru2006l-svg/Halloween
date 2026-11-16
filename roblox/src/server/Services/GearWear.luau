--!strict
-- GearWear (owner 2026-11-15: "actual models for the gear so you can see it on your character"): every
-- gear you own (the player's Gear_<key> attributes, GearService) is worn on your avatar, seen by everyone.
--  Magnet Gloves: red armoured gauntlets, a horseshoe magnet with a crackling ice bolt on each hand.
--  Ice Skates: turquoise skates with fur cuffs, gold laces, steel blades and a heel booster puffing mist.
--  Frost Boots: purple armoured boots, ice crystal spikes at toe and heel, fur cuffs. With skates too,
--  the boots get the skates' blades and boosters.
--  Cooling Vest: blue padded vest, glowing coolant tubes, two fans, a tank on the back, misty vents.
--  Cozy Hat: a gold knitted beanie, a big pompom, a coin emblem and gold stars.
-- Built from parts sized off each limb (any avatar scale), welded, massless, no collisions or shadows.
-- Looks only: what the gear does stays in GearService and Config.gearValue.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)

local GearWear = {}
local GW = Config.gearWear
local KEYS = { "magnet_gloves", "ice_skates", "frost_boots", "cooling_vest", "cozy_hat" }
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

local function gloves(m: Model, c: Model)
	local C = GW.gloves
	for _, side in { -1, 1 } do
		local hand = c:FindFirstChild(if side > 0 then "RightHand" else "LeftHand") :: BasePart?
		if not hand then
			continue
		end
		local H = hand.Size
		local w = math.max(H.X, H.Z)
		block(m, hand, Vector3.new(H.X * 1.15, H.Y * 0.78, H.Z * 1.15), CFrame.new(0, -H.Y * 0.06, 0), C.main)
		ring(m, hand, H.Y * 0.42, w * 1.18, CFrame.new(0, H.Y * 0.4, 0), C.main)
		glow(ring(m, hand, H.Y * 0.08, w * 1.22, CFrame.new(0, H.Y * 0.3, 0), GW.ice), GW.ice)
		ring(m, hand, H.Y * 0.07, w * 1.24, CFrame.new(0, H.Y * 0.6, 0), GW.steel, Enum.Material.Metal)
		-- silver knuckle plates along the bottom
		for k = 1, 4 do
			block(m, hand, Vector3.new(H.X * 0.3, H.Y * 0.2, H.Z * 0.22), CFrame.new(side * H.X * 0.45, -H.Y * 0.36, (k - 2.5) * H.Z * 0.27), GW.steel, Enum.Material.Metal)
		end
		-- the horseshoe magnet on the back of the hand, an ice bolt between its tips
		local x = side * H.X * 0.66
		for _, z in { -1, 1 } do
			block(m, hand, Vector3.new(H.X * 0.16, H.Y * 0.36, H.Z * 0.16), CFrame.new(x, H.Y * 0.04, z * H.Z * 0.22), C.main)
			block(m, hand, Vector3.new(H.X * 0.17, H.Y * 0.12, H.Z * 0.17), CFrame.new(x, H.Y * 0.26, z * H.Z * 0.22), GW.steel, Enum.Material.Metal)
		end
		block(m, hand, Vector3.new(H.X * 0.16, H.Y * 0.14, H.Z * 0.6), CFrame.new(x, -H.Y * 0.18, 0), C.dark)
		local bolt = glow(block(m, hand, Vector3.new(H.X * 0.06, H.Y * 0.06, H.Z * 0.3), CFrame.new(x, H.Y * 0.26, 0), GW.ice), GW.ice)
		sparkle(bolt, GW.ice)
	end
end

local function feet(m: Model, c: Model, skates: boolean, boots: boolean)
	for _, side in { -1, 1 } do
		local foot = c:FindFirstChild(if side > 0 then "RightFoot" else "LeftFoot") :: BasePart?
		if not foot then
			continue
		end
		local F = foot.Size
		local main = if boots then GW.boots.main else GW.skates.main
		local fur = if boots then GW.boots.fur else GW.fur
		-- the shell, a rounded toe, the ankle and the fur cuff
		block(m, foot, Vector3.new(F.X * 1.15, F.Y * 1.25, F.Z * 0.9), CFrame.new(0, F.Y * 0.1, F.Z * 0.08), main)
		piece(m, foot, Enum.PartType.Cylinder, Vector3.new(F.X * 1.15, F.Y * 1.25, F.Y * 1.25), CFrame.new(0, F.Y * 0.1, -F.Z * 0.38), main)
		ring(m, foot, F.Y * 1.6, F.X * 1.1, CFrame.new(0, F.Y * 1.2, F.Z * 0.14), main)
		local cuff = ring(m, foot, F.Y * 0.42, F.X * 1.26, CFrame.new(0, F.Y * 2.0, F.Z * 0.14), fur, Enum.Material.Fabric)
		if boots then
			-- a steel strap with a buckle, ice crystal spikes at the toe and the heel
			ring(m, foot, F.Y * 0.22, F.X * 1.2, CFrame.new(0, F.Y * 1.0, F.Z * 0.14), GW.steelDark, Enum.Material.Metal)
			block(m, foot, Vector3.new(F.X * 0.4, F.Y * 0.36, F.Z * 0.08), CFrame.new(0, F.Y * 1.0, -F.Z * 0.24), GW.steel, Enum.Material.Metal)
			for k, spike in { { 0, -0.62, -0.5 }, { -0.3, -0.55, -0.3 }, { 0.3, -0.55, -0.3 }, { -0.25, 0.55, 0.45 }, { 0.25, 0.55, 0.45 } } do
				local tilt = CFrame.Angles(spike[3], 0, spike[1] * 0.8)
				local s = block(m, foot, Vector3.new(F.X * 0.2, F.Y * (if k == 1 then 0.9 else 0.7), F.X * 0.2), CFrame.new(spike[1] * F.X, F.Y * 0.35, spike[2] * F.Z) * tilt, GW.ice, Enum.Material.Neon)
				s.Transparency = 0.1
			end
			sparkle(cuff, GW.ice)
		end
		if skates then
			if not boots then
				-- gold laces up the front
				for k = 0, 2 do
					block(m, foot, Vector3.new(F.X * 0.85, F.Y * 0.09, F.Z * 0.06), CFrame.new(0, F.Y * (0.7 + k * 0.4), -F.Z * 0.18) * CFrame.Angles(0, 0, (k % 2 - 0.5) * 0.4), GW.gold)
				end
			end
			-- the blade on two struts, its ice edge, and the booster on the heel
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

local function vest(m: Model, c: Model)
	local torso = c:FindFirstChild("UpperTorso") :: BasePart?
	if not torso then
		return
	end
	local T, C = torso.Size, GW.vest
	block(m, torso, Vector3.new(T.X * 1.08, T.Y * 0.86, T.Z * 1.22), CFrame.new(0, -T.Y * 0.06, 0), C.main, Enum.Material.Fabric)
	for _, s in { -1, 1 } do
		block(m, torso, Vector3.new(T.X * 0.3, T.Y * 0.12, T.Z * 1.26), CFrame.new(s * T.X * 0.34, T.Y * 0.4, 0), C.dark)
		-- a glowing coolant tube down each side of the front, a fan above it
		glow(ring(m, torso, T.Y * 0.72, T.Z * 0.13, CFrame.new(s * T.X * 0.34, -T.Y * 0.06, -T.Z * 0.62), GW.ice), GW.ice)
		disc(m, torso, T.Z * 0.06, T.X * 0.27, CFrame.new(s * T.X * 0.17, T.Y * 0.17, -T.Z * 0.63), GW.steel, Enum.Material.Metal)
		glow(disc(m, torso, T.Z * 0.07, T.X * 0.17, CFrame.new(s * T.X * 0.17, T.Y * 0.17, -T.Z * 0.64), GW.ice), GW.ice)
		disc(m, torso, T.Z * 0.08, T.X * 0.06, CFrame.new(s * T.X * 0.17, T.Y * 0.17, -T.Z * 0.66), GW.steelDark, Enum.Material.Metal)
		-- misty side vents
		local v = block(m, torso, Vector3.new(T.X * 0.05, T.Y * 0.22, T.Z * 0.5), CFrame.new(s * T.X * 0.55, -T.Y * 0.12, 0), GW.steelDark, Enum.Material.Metal)
		sparkle(v, GW.fur, true)
	end
	block(m, torso, Vector3.new(T.X * 0.04, T.Y * 0.78, T.Z * 0.04), CFrame.new(0, -T.Y * 0.06, -T.Z * 0.62), GW.steel, Enum.Material.Metal)
	block(m, torso, Vector3.new(T.X * 0.5, T.Y * 0.1, T.Z * 1.28), CFrame.new(0, T.Y * 0.42, 0), C.dark)
	block(m, torso, Vector3.new(T.X * 1.12, T.Y * 0.1, T.Z * 1.28), CFrame.new(0, -T.Y * 0.44, 0), C.dark)
	-- the coolant tank on the back
	ring(m, torso, T.Y * 0.62, T.Z * 0.55, CFrame.new(0, 0, T.Z * 0.78), GW.steel, Enum.Material.Metal)
	glow(ring(m, torso, T.Y * 0.4, T.Z * 0.57, CFrame.new(0, 0, T.Z * 0.78), GW.ice), GW.ice).Transparency = 0.25
end

local function hat(m: Model, c: Model)
	local head = c:FindFirstChild("Head") :: BasePart?
	if not head then
		return
	end
	local D, C = head.Size, GW.hat
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
		if owns(player, "magnet_gloves") then
			gloves(m, c)
		end
		local skates, boots = owns(player, "ice_skates"), owns(player, "frost_boots")
		if skates or boots then
			feet(m, c, skates, boots)
		end
		if owns(player, "cooling_vest") then
			vest(m, c)
		end
		if owns(player, "cozy_hat") then
			hat(m, c)
		end
	end)
	if not ok then
		warn("[GearWear]", err)
	end
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
