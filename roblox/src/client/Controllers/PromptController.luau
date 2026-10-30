--!strict
-- PromptController: draws every world prompt (they use ProximityPromptStyle.Custom) as a Chunky Pop
-- block floating on its object: what it is, what it does, the key (E / X / Hold) and a hold bar.
-- On touch the block itself is the hold button. The server still decides what a prompt does.
-- Also hides prompts that can't do anything for you right now (open gate, gift before the first bank).

local ProximityPromptService = game:GetService("ProximityPromptService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Theme = require(ReplicatedStorage.Shared.Theme)
local Ui = require(script.Parent.Parent.Lib.Ui)
local State = require(script.Parent.State)
local InputController = require(script.Parent.InputController)

local PromptController = {}
local playerGui: Instance
local shown: { [ProximityPrompt]: { gui: BillboardGui, bar: Frame, conns: { RBXScriptConnection } } } = {}

local function color(prompt: ProximityPrompt): Color3
	local a = prompt.ActionText
	return if a == "Freeze" or a == "Zap" then Theme.ice elseif a == "Open" then Theme.go else Theme.info
end

local function show(prompt: ProximityPrompt)
	if shown[prompt] then
		return
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "Prompt"
	gui.AlwaysOnTop = true
	gui.Size = UDim2.fromScale(5, 1.6)
	gui.StudsOffset = Vector3.new(0, 1, 0)
	gui.Adornee = prompt.Parent :: any
	gui.Active = true
	local b = Ui.block(gui, "Block", color(prompt), "", nil)
	b.root.Size = UDim2.fromScale(1, 1)
	b.text.TextColor3 = Theme.white
	b.text.Size = UDim2.fromScale(0.62, 0.8)
	b.text.Position = UDim2.fromScale(0.34, 0.1)
	b.text.Text = if prompt.ObjectText ~= "" then `{prompt.ActionText} {prompt.ObjectText}` else prompt.ActionText
	local key = Ui.label(b.face, InputController.keyHint(prompt), UDim2.fromScale(0.28, 0.8), UDim2.fromScale(0.03, 0.1))
	key.TextColor3 = Theme.ink
	local bar = Instance.new("Frame")
	bar.Name = "Hold"
	bar.BackgroundColor3 = Theme.white
	bar.BackgroundTransparency = 0.3
	bar.BorderSizePixel = 0
	bar.Size = UDim2.fromScale(0, 0.12)
	bar.Position = UDim2.fromScale(0, 0.88)
	bar.Parent = b.face
	gui.Parent = playerGui
	local conns: { RBXScriptConnection } = {}
	-- touch and mouse: the block is the hold button
	table.insert(conns, b.face.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			prompt:InputHoldBegin()
		end
	end))
	table.insert(conns, b.face.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			prompt:InputHoldEnd()
		end
	end))
	table.insert(conns, InputController.DeviceChanged:Connect(function()
		key.Text = InputController.keyHint(prompt)
	end))
	shown[prompt] = { gui = gui, bar = bar, conns = conns }
end

local function hide(prompt: ProximityPrompt)
	local s = shown[prompt]
	if s then
		for _, c in s.conns do
			c:Disconnect()
		end
		s.gui:Destroy()
		shown[prompt] = nil
	end
end

-- prompts that only make sense in some states (set locally; the server checks again anyway)
local function refreshWorldPrompts(v: State.View)
	local map = workspace:FindFirstChild("Map")
	if not map then
		return
	end
	local gate = map:FindFirstChild("GatePromptSpot", true)
	local gp = gate and gate:FindFirstChildWhichIsA("ProximityPrompt", true)
	if gp then
		gp.Enabled = not v.forestUnlocked
	end
	local gift = map:FindFirstChild("GiftBox", true)
	local gift_p = gift and gift:FindFirstChildWhichIsA("ProximityPrompt", true)
	if gift_p then
		gift_p.Enabled = v.gift.ready
	end
end

function PromptController.Init()
	playerGui = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
end

function PromptController.Start()
	ProximityPromptService.PromptShown:Connect(function(prompt: ProximityPrompt)
		if prompt.Style == Enum.ProximityPromptStyle.Custom then
			show(prompt)
		end
	end)
	ProximityPromptService.PromptHidden:Connect(hide)
	ProximityPromptService.PromptButtonHoldBegan:Connect(function(prompt: ProximityPrompt)
		local s = shown[prompt]
		if s then
			s.bar.Size = UDim2.fromScale(0, 0.12)
			TweenService:Create(s.bar, TweenInfo.new(prompt.HoldDuration, Enum.EasingStyle.Linear), { Size = UDim2.fromScale(1, 0.12) }):Play()
		end
	end)
	ProximityPromptService.PromptButtonHoldEnded:Connect(function(prompt: ProximityPrompt)
		local s = shown[prompt]
		if s then
			TweenService:Create(s.bar, TweenInfo.new(0.1), { Size = UDim2.fromScale(0, 0.12) }):Play()
		end
	end)
	State.Changed:Connect(refreshWorldPrompts)
end

return PromptController
