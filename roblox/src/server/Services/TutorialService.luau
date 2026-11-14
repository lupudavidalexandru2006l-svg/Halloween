--!strict
-- TutorialService: the one owner of each player's tutorial progress, saved in their data as
-- tutorial = { step, done, gift } (Config.tutorial). The game's services report what a player really did
-- (TutorialService.did, called where the server decides it: FreezeService, CarryService, PenService,
-- PanService); this moves the step on and the client plays Captain Frost (TutorialController). The client
-- only sends intent through the Tutorial remote: "next" on a talk step, "skip", "replay" (Code Rules 6).
-- Each player's progress is their own, so any number of players can be on different steps at once.
-- It also builds Captain Frost's model once (ReplicatedStorage.TutorialGuide); every client clones its own copy.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Theme = require(ReplicatedStorage.Shared.Theme)
local DataService = require(script.Parent.DataService)
local Remotes = require(script.Parent.Remotes)

local TutorialService = {}
local T = Config.tutorial
local N = T.npc
local lastNext: { [Player]: number } = {}

-- a Pan Upgrade's level in a save (the same places PanService keeps them)
local function panLevel(d: any, kind: string): number
	if kind == "speed" then
		return d.upgrades.boots or 1
	elseif kind == "slots" then
		return d.upgrades.pen or 1
	elseif kind == "thaw" then
		return d.pan.thaw or 1
	end
	return 1
end

-- why: "did" (an action), "next", "skip", "replay"
local function setStep(player: Player, step: number, done: boolean, why: string)
	step = math.clamp(step, 1, #T.steps)
	local gift = 0
	local changed = DataService.mutate(player, function(d)
		d.tutorial.step = step
		d.tutorial.done = done
		-- the upgrade step: coins topped up to the price of that upgrade's next level, once per save (a
		-- replay can't farm it), so the first upgrade is bought right away (Game Psychology: endowed progress)
		local s = T.steps[step]
		if not done and s.gift and not d.tutorial.gift then
			local price = Config.panPrice(s.gift, panLevel(d, s.gift), d.rebirths)
			d.tutorial.gift = true
			if price and d.coins < price then
				gift = price - math.floor(d.coins)
				d.coins += gift
			end
		end
	end)
	if not changed then
		return
	end
	Remotes.fire(player, "Notify", "tutorial", { step = step, done = done, why = why, gift = if gift > 0 then gift else nil })
	if done or why == "replay" or gift > 0 then
		task.spawn(DataService.saveNow, player) -- finishing, skipping or a gift is remembered at once, not at the next autosave
	end
end

-- a player did something the tutorial teaches. The current step or any later one counts, so a kid who
-- already froze a pet while the Captain was still saying hello goes straight on to picking it up. An
-- `only` step counts only while it's the current one (a Pan Upgrade bought mid-catch skips nothing).
function TutorialService.did(player: Player, action: string)
	if not T.actions[action] then
		return
	end
	local d = DataService.get(player)
	if not d or d.tutorial.done then
		return
	end
	for i = d.tutorial.step, #T.steps do
		local s = T.steps[i]
		if s.on == action and (i == d.tutorial.step or not s.only) then
			local nextStep = i + 1
			setStep(player, nextStep, nextStep > #T.steps, "did")
			return
		end
	end
end

local function onTutorial(player: Player, what: any)
	if typeof(what) ~= "string" then
		return
	end
	local d = DataService.get(player)
	if not d then
		return
	end
	local tu = d.tutorial
	if what == "next" then
		-- only a talk step moves on with Next; an action step needs the action itself
		local step = T.steps[tu.step]
		local now = os.clock()
		if tu.done or not step or step.on ~= "next" or now - (lastNext[player] or -math.huge) < T.nextCooldown then
			return
		end
		lastNext[player] = now
		setStep(player, tu.step + 1, tu.step + 1 > #T.steps, "next")
	elseif what == "skip" then
		if not tu.done then
			setStep(player, tu.step, true, "skip")
		end
	elseif what == "replay" then
		if tu.done then
			setStep(player, 1, false, "replay")
		end
	end
end

-- ---------- Captain Frost's model ----------
-- Made of parts on a Roblox R15 body (no catalog accessories, so nothing to license or load). He faces
-- -Z, so his back is +Z. Every piece is welded, massless and never collides or takes a ray.
-- a Weld with its offset written down (C0), not a WeldConstraint: a WeldConstraint takes whatever offset
-- the parts have when a client's copy goes live, and the root is moved before that, so pieces were left
-- floating far from his body (owner 2026-11-14: "the tutorial NPC is glitching")
local function weld(part: BasePart, to: BasePart, at: CFrame)
	part.CFrame = to.CFrame * at
	part.Anchored = false
	part.CanCollide, part.CanQuery, part.CanTouch, part.CastShadow, part.Massless = false, false, false, true, true
	local w = Instance.new("Weld")
	w.Part0, w.Part1, w.C0 = to, part, at
	w.Parent = part
end

local function piece(model: Model, name: string, shape: Enum.PartType, size: Vector3, color: Color3, neon: boolean?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = shape
	p.Size = size
	p.Color = color
	p.Material = if neon then Enum.Material.Neon else Enum.Material.SmoothPlastic
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	p.Parent = model
	return p
end

local UP = CFrame.Angles(0, 0, math.pi / 2) -- a cylinder's axis is X: stand it up
local FORWARD = CFrame.Angles(0, math.pi / 2, 0) -- a cylinder's axis along Z: a lens facing out

-- a jet under the cryo tank: frost mist blowing down while he flies (TutorialNpc switches it on)
local function jet(model: Model, tank: BasePart, name: string)
	local C = Theme.tutorial
	local a = Instance.new("Attachment")
	a.Name = name
	a.Position = Vector3.new(0, -0.2, 0)
	a.Parent = tank
	local e = Instance.new("ParticleEmitter")
	e.Name = "Jet"
	e.Enabled = false
	e.Color = ColorSequence.new(Theme.white, C.glow)
	e.LightEmission = 0.8
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	e.Lifetime = NumberRange.new(0.25, 0.45)
	e.Speed = NumberRange.new(7, 11)
	e.SpreadAngle = Vector2.new(10, 10)
	e.EmissionDirection = Enum.NormalId.Bottom
	e.Rate = 45
	e.Parent = a
end

local function dress(model: Model)
	local C = Theme.tutorial
	local function part(name: string): BasePart?
		return model:FindFirstChild(name) :: BasePart?
	end
	-- gloves and boots: the body's own hands and feet, recoloured
	for _, n in { "LeftHand", "RightHand" } do
		local p = part(n)
		if p then
			p.Color = C.glove
		end
	end
	for _, n in { "LeftFoot", "RightFoot" } do
		local p = part(n)
		if p then
			p.Color = C.boot
		end
	end
	local head = part("Head")
	if head then
		local h = head.Size
		local w = math.max(h.X, h.Z)
		local top = h.Y * 0.36
		-- a big fluffy trapper hat: a short parka-blue crown in a fat white fur roll, long fur ear flaps,
		-- a glowing ice-crystal badge and three ice shards sticking up from the crown like a crest
		local crownH = h.Y * 0.3
		weld(piece(model, "HatCrown", Enum.PartType.Cylinder, Vector3.new(crownH, w * 1.02, w * 1.02), C.coat), head, CFrame.new(0, top + 0.12 + crownH / 2, 0.04) * UP)
		local fur = piece(model, "HatFur", Enum.PartType.Cylinder, Vector3.new(h.Y * 0.36, w * 1.34, w * 1.34), C.fur)
		weld(fur, head, CFrame.new(0, top + 0.06, 0) * UP)
		for _, side in { -1, 1 } do
			weld(piece(model, "EarFlap", Enum.PartType.Block, Vector3.new(0.28, h.Y * 0.62, w * 0.56), C.fur), head, CFrame.new(side * (h.X / 2 + 0.14), top - h.Y * 0.3, 0.08) * CFrame.Angles(0, 0, side * math.rad(-6)))
		end
		local badge = piece(model, "HatBadge", Enum.PartType.Block, Vector3.new(0.34, 0.34, 0.1), C.glow, true)
		weld(badge, head, CFrame.new(0, top + 0.08, -w * 0.67) * CFrame.Angles(0, 0, math.rad(45)))
		for i, x in { -0.22, 0, 0.22 } do
			local tall = if i == 2 then 0.75 else 0.5
			local shard = piece(model, "HatShard", Enum.PartType.Block, Vector3.new(0.16, tall, 0.16), C.glow, true)
			shard.Transparency = 0.15
			weld(shard, head, CFrame.new(x, top + 0.12 + crownH + tall / 2 - 0.08, 0.05) * CFrame.Angles(0, math.rad(45), x * -1.2))
		end
		-- cryo goggles pushed up on the forehead, just under the fur
		local gy = top - h.Y * 0.1
		weld(piece(model, "GoggleStrap", Enum.PartType.Cylinder, Vector3.new(0.16, w * 1.08, w * 1.08), C.suit), head, CFrame.new(0, gy, 0) * UP)
		for _, side in { -1, 1 } do
			local x = side * h.X * 0.22
			weld(piece(model, "GoggleRim", Enum.PartType.Cylinder, Vector3.new(0.14, 0.5, 0.5), C.steel), head, CFrame.new(x, gy, -h.Z / 2 - 0.02) * FORWARD)
			local lens = piece(model, "GoggleLens", Enum.PartType.Cylinder, Vector3.new(0.08, 0.38, 0.38), C.glow, true)
			weld(lens, head, CFrame.new(x, gy, -h.Z / 2 - 0.08) * FORWARD)
		end
	end
	local chest = part("UpperTorso")
	if chest then
		local s = chest.Size
		-- red scarf (like the snowmen) with a tail over the shoulder
		weld(piece(model, "Scarf", Enum.PartType.Block, Vector3.new(s.X * 0.8, 0.34, s.Z * 1.22), C.scarf), chest, CFrame.new(0, s.Y / 2 - 0.12, 0))
		weld(piece(model, "ScarfTail", Enum.PartType.Block, Vector3.new(0.38, 0.95, 0.14), C.scarf), chest, CFrame.new(s.X * 0.18, s.Y / 2 - 0.6, -s.Z * 0.62) * CFrame.Angles(0, 0, math.rad(-8)))
		-- a navy harness strap across the chest with a glowing cryo core on it
		weld(piece(model, "Harness", Enum.PartType.Block, Vector3.new(0.32, s.Y * 1.3, 0.1), C.suit), chest, CFrame.new(0, -0.05, -s.Z / 2 - 0.04) * CFrame.Angles(0, 0, math.rad(38)))
		weld(piece(model, "CoreRim", Enum.PartType.Cylinder, Vector3.new(0.1, 0.56, 0.56), C.steel), chest, CFrame.new(-s.X * 0.17, s.Y * 0.08, -s.Z / 2 - 0.1) * FORWARD)
		weld(piece(model, "Core", Enum.PartType.Cylinder, Vector3.new(0.1, 0.4, 0.4), C.glow, true), chest, CFrame.new(-s.X * 0.17, s.Y * 0.08, -s.Z / 2 - 0.14) * FORWARD)
		-- the cryo tank on his back: a navy frame, two glowing tanks with steel caps, a jet under each
		weld(piece(model, "TankFrame", Enum.PartType.Block, Vector3.new(s.X * 0.82, s.Y * 0.9, 0.28), C.suit), chest, CFrame.new(0, 0, s.Z / 2 + 0.14))
		local tankH = s.Y * 1.05
		for i, side in { -1, 1 } do
			local x, z = side * s.X * 0.2, s.Z / 2 + 0.5
			local tank = piece(model, "Tank", Enum.PartType.Cylinder, Vector3.new(tankH, 0.58, 0.58), C.glow, true)
			tank.Transparency = 0.25
			weld(tank, chest, CFrame.new(x, 0.05, z) * UP)
			-- steel bands round the middle, so the two tanks read as tanks, not one glowing slab
			for _, y in { -tankH * 0.18, tankH * 0.18 } do
				weld(piece(model, "TankBand", Enum.PartType.Cylinder, Vector3.new(0.1, 0.64, 0.64), C.steel), chest, CFrame.new(x, 0.05 + y, z) * UP)
			end
			for _, y in { tankH / 2 + 0.05, -tankH / 2 - 0.0 } do
				weld(piece(model, "TankCap", Enum.PartType.Cylinder, Vector3.new(0.2, 0.66, 0.66), C.steel), chest, CFrame.new(x, 0.05 + y, z) * UP)
			end
			local nozzle = piece(model, "JetNozzle", Enum.PartType.Cylinder, Vector3.new(0.32, 0.42, 0.42), C.steel)
			weld(nozzle, chest, CFrame.new(x, 0.05 - tankH / 2 - 0.3, z) * UP)
			jet(model, nozzle, "Jet" .. i)
		end
		local light = Instance.new("PointLight")
		light.Name = "CryoLight"
		light.Color = C.glow
		light.Range = 7
		light.Brightness = 1.2
		light.Parent = chest
	end
	-- chunky fur shoulder pads, fur cuffs on the sleeves and boots
	for _, n in { "LeftUpperArm", "RightUpperArm" } do
		local a = part(n)
		if a then
			weld(piece(model, "ShoulderPad", Enum.PartType.Block, Vector3.new(a.Size.X * 1.35, 0.4, a.Size.Z * 1.35), C.fur), a, CFrame.new(0, a.Size.Y / 2 - 0.05, 0))
			-- ice shards growing out of the pads, pointing up and out
			local out = if n == "LeftUpperArm" then -1 else 1
			for i, z in { -0.22, 0.2 } do
				local tall = if i == 1 then 0.6 else 0.45
				local shard = piece(model, "PadShard", Enum.PartType.Block, Vector3.new(0.17, tall, 0.17), C.glow, true)
				shard.Transparency = 0.15
				weld(shard, a, CFrame.new(out * 0.18, a.Size.Y / 2 + 0.1 + tall / 2, z) * CFrame.Angles(0, math.rad(45), 0) * CFrame.Angles(0, 0, out * math.rad(-25)))
			end
		end
	end
	for _, n in { "LeftLowerArm", "RightLowerArm" } do
		local a = part(n)
		if a then
			weld(piece(model, "Cuff", Enum.PartType.Block, Vector3.new(a.Size.X * 1.2, 0.26, a.Size.Z * 1.2), C.fur), a, CFrame.new(0, -a.Size.Y / 2 + 0.12, 0))
		end
	end
	for _, n in { "LeftLowerLeg", "RightLowerLeg" } do
		local l = part(n)
		if l then
			weld(piece(model, "BootCuff", Enum.PartType.Block, Vector3.new(l.Size.X * 1.25, 0.3, l.Size.Z * 1.25), C.fur), l, CFrame.new(0, -l.Size.Y / 2 + 0.2, 0))
		end
	end
	local hips = part("LowerTorso")
	if hips then
		local l = hips.Size
		-- belt with a steel buckle, a white fur parka hem, and a tiny frozen cube clipped to his hip
		weld(piece(model, "Belt", Enum.PartType.Block, Vector3.new(l.X * 1.06, 0.3, l.Z * 1.1), C.suit), hips, CFrame.new(0, 0.05, 0))
		weld(piece(model, "Buckle", Enum.PartType.Block, Vector3.new(0.45, 0.32, 0.08), C.steel), hips, CFrame.new(0, 0.05, -l.Z * 0.56))
		weld(piece(model, "Hem", Enum.PartType.Block, Vector3.new(l.X * 1.1, 0.22, l.Z * 1.16), C.fur), hips, CFrame.new(0, -l.Y / 2 - 0.02, 0))
		local cube = piece(model, "IceCube", Enum.PartType.Block, Vector3.new(0.46, 0.46, 0.46), C.ice)
		cube.Material = Enum.Material.Glass
		cube.Transparency = 0.3
		weld(cube, hips, CFrame.new(-l.X / 2 - 0.2, -0.35, -0.1) * CFrame.Angles(math.rad(12), math.rad(20), math.rad(8)))
	end
	-- the best ice ray in the game in his right hand, held like a player's (RayController.giveGun)
	local hand = part("RightHand")
	local models = ReplicatedStorage:FindFirstChild("GunModels")
	local real = models and models:FindFirstChild(N.gun)
	if hand and real and real:IsA("Model") and real.PrimaryPart then
		local g = real:Clone()
		g.Name = "IceRay"
		g:ScaleTo(N.gunScale)
		local body = g.PrimaryPart :: BasePart
		for _, d in g:GetDescendants() do
			if d:IsA("BasePart") then
				d.Anchored = false
				d.CanCollide, d.CanQuery, d.CanTouch, d.Massless = false, false, false, true
			end
		end
		local base = CFrame.new(0, -hand.Size.Y / 2, 0) * CFrame.fromMatrix(Vector3.zero, -Vector3.yAxis, -Vector3.zAxis, Vector3.xAxis)
		local grip = body:FindFirstChild("Grip")
		local c1 = if grip and grip:IsA("Attachment") then grip.CFrame else CFrame.new()
		g:PivotTo(hand.CFrame * base * c1:Inverse() * body.PivotOffset)
		local w = Instance.new("Weld")
		w.Part0, w.Part1, w.C0, w.C1 = hand, body, base, c1
		w.Parent = body
		g.Parent = model
	end
	-- a frost poof for arriving and catching up (TutorialNpc emits it)
	local root = part("HumanoidRootPart")
	if root then
		local a = Instance.new("Attachment")
		a.Name = "PoofAt"
		a.Parent = root
		local e = Instance.new("ParticleEmitter")
		e.Name = "Poof"
		e.Enabled = false
		e.Color = ColorSequence.new(Theme.white, C.glow)
		e.LightEmission = 0.5
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.4), NumberSequenceKeypoint.new(1, 0) })
		e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
		e.Lifetime = NumberRange.new(0.4, 0.7)
		e.Speed = NumberRange.new(6, 12)
		e.SpreadAngle = Vector2.new(180, 180)
		e.Drag = 4
		e.Parent = a
	end
end

local function buildGuide()
	if ReplicatedStorage:FindFirstChild(T.modelName) then
		return
	end
	local C = Theme.tutorial
	local ok, result = pcall(function()
		local desc = Instance.new("HumanoidDescription")
		desc.HeadColor = C.skin
		desc.LeftArmColor, desc.RightArmColor = C.coat, C.coat
		desc.TorsoColor = C.coat
		desc.LeftLegColor, desc.RightLegColor = C.suit, C.suit
		desc.HeightScale, desc.WidthScale, desc.DepthScale = 1.05, 1.08, 1.05 -- a bit bigger than you: the pro
		return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
	end)
	if not ok or typeof(result) ~= "Instance" or not result:IsA("Model") then
		warn(`[TutorialService] couldn't build Captain Frost: {result}`) -- the tutorial still runs, just without him
		return
	end
	local model = result :: Model
	model.Name = T.modelName
	local hum = model:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None -- his name is our own pill (TutorialNpc)
		hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BaseScript") then
			d:Destroy() -- the default Animate script: the client plays his animations itself
		elseif d:IsA("BasePart") then
			d.CanCollide, d.CanQuery, d.CanTouch = false, false, false -- never blocks you, never takes a ray
		end
	end
	model.PrimaryPart = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	dress(model)
	model.Parent = ReplicatedStorage
end

function TutorialService.Init() end

function TutorialService.Start()
	Remotes.on("Tutorial", onTutorial)
	Players.PlayerRemoving:Connect(function(p)
		lastNext[p] = nil
	end)
	task.spawn(buildGuide) -- CreateHumanoidModelFromDescription waits on Roblox's servers
end

return TutorialService
