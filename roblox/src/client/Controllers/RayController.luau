--!strict
-- RayController: the ice ray (prototype avatar + beam). Every character on this client gets a small
-- ice-ray gun in its right hand (built locally, so it costs the server nothing). While you hold
-- Freeze on a pet or the ice bridge, your arm comes up and a white beam with a cyan glow runs from
-- the gun's tip to the target, with sparkles where it lands. The server still decides the freeze.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Theme = require(ReplicatedStorage.Shared.Theme)

local RayController = {}
local R = Config.ray
local me = Players.LocalPlayer
local guns: { [Model]: Model } = {}
local active: { beams: { Beam }, sparkle: ParticleEmitter?, prompt: ProximityPrompt, shoulder: Motor6D?, c0: CFrame? }? = nil

local function piece(shape: Enum.PartType, size: Vector3, color: Color3, parent: Instance): Part
	local p = Instance.new("Part")
	p.Shape = shape
	p.Size = size
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = false
	p.Parent = parent
	return p
end

local function weld(a: BasePart, b: BasePart, c0: CFrame)
	local w = Instance.new("Weld")
	w.Part0 = a
	w.Part1 = b
	w.C0 = c0
	w.Parent = b
end

-- barrel, glowing tip and a small tank, pointing along the hand's forward direction
local function giveGun(character: Model)
	if guns[character] then
		return
	end
	local hand = character:WaitForChild("RightHand", 5) or character:FindFirstChild("Right Arm")
	if not hand or not hand:IsA("BasePart") then
		return
	end
	local m = Instance.new("Model")
	m.Name = "IceRay"
	local barrel = piece(Enum.PartType.Cylinder, Vector3.new(1.6, 0.74, 0.74), Theme.fx.gunBody, m)
	local base = CFrame.new(0, -hand.Size.Y / 2, -0.5) * CFrame.Angles(0, math.pi / 2, 0) -- cylinder axis X -> forward
	weld(hand, barrel, base)
	local tip = piece(Enum.PartType.Ball, Vector3.one * R.tipSize, Theme.fx.gunTip, m)
	tip.Material = Enum.Material.Neon
	weld(barrel, tip, CFrame.new(0.85, 0, 0)) -- the barrel's +X points forward out of the hand
	local tank = piece(Enum.PartType.Cylinder, Vector3.new(0.7, 0.6, 0.6), Theme.fx.gunTip, m)
	tank.Transparency = 0.15
	weld(barrel, tank, CFrame.new(-0.2, 0.42, 0) * CFrame.Angles(0, 0, math.pi / 2))
	local a = Instance.new("Attachment")
	a.Name = "RayTip"
	a.Parent = tip
	m.Parent = character
	guns[character] = m
	character.Destroying:Once(function()
		guns[character] = nil
	end)
end

local function watchPlayer(p: Player)
	p.CharacterAdded:Connect(giveGun)
	if p.Character then
		task.spawn(giveGun, p.Character)
	end
end

local function stop()
	local a = active
	if not a then
		return
	end
	for _, b in a.beams do
		b:Destroy()
	end
	if a.sparkle then
		a.sparkle:Destroy()
	end
	if a.shoulder and a.c0 then
		a.shoulder.C0 = a.c0
	end
	active = nil
end

local function beam(from: Attachment, to: Attachment, width: number, color: Color3, transparency: number): Beam
	local b = Instance.new("Beam")
	b.Attachment0 = from
	b.Attachment1 = to
	b.Width0, b.Width1 = width, width
	b.Color = ColorSequence.new(color)
	b.Transparency = NumberSequence.new(transparency)
	b.LightEmission = 1
	b.FaceCamera = true
	b.Segments = 1
	b.Parent = from
	return b
end

local function start(prompt: ProximityPrompt)
	stop()
	local target = prompt.Parent
	local gun = me.Character and guns[me.Character]
	local tip = gun and gun:FindFirstChild("RayTip", true)
	if not target or not target:IsA("Attachment") or not tip or not tip:IsA("Attachment") then
		return
	end
	local sparkle = Instance.new("ParticleEmitter")
	sparkle.Color = ColorSequence.new(Theme.fx.frost)
	sparkle.Rate = R.sparkleRate
	sparkle.Speed = NumberRange.new(2, 4)
	sparkle.Lifetime = NumberRange.new(0.3, 0.5)
	sparkle.SpreadAngle = Vector2.new(180, 180)
	sparkle.Size = NumberSequence.new(0.3)
	sparkle.Parent = target
	-- raise the right arm toward the target (the Animator only moves Transform, so C0 stays ours)
	local shoulder = me.Character and me.Character:FindFirstChild("RightShoulder", true)
	local c0: CFrame? = nil
	if shoulder and shoulder:IsA("Motor6D") then
		c0 = shoulder.C0
		shoulder.C0 = shoulder.C0 * CFrame.Angles(math.rad(R.armRaise), 0, 0)
	end
	active = {
		beams = { beam(tip, target, R.beamGlow, Theme.fx.beamGlow, 0.5), beam(tip, target, R.beamCore, Theme.fx.beamCore, 0.05) },
		sparkle = sparkle,
		prompt = prompt,
		shoulder = if shoulder and shoulder:IsA("Motor6D") then shoulder else nil,
		c0 = c0,
	}
end

function RayController.Init() end

function RayController.Start()
	for _, p in Players:GetPlayers() do
		watchPlayer(p)
	end
	Players.PlayerAdded:Connect(watchPlayer)
	ProximityPromptService.PromptButtonHoldBegan:Connect(function(prompt: ProximityPrompt)
		if prompt.ActionText == "Freeze" then
			start(prompt)
		end
	end)
	ProximityPromptService.PromptButtonHoldEnded:Connect(function(prompt: ProximityPrompt)
		if active and active.prompt == prompt then
			stop()
		end
	end)
	ProximityPromptService.PromptHidden:Connect(function(prompt: ProximityPrompt)
		if active and active.prompt == prompt then
			stop()
		end
	end)
end

return RayController
