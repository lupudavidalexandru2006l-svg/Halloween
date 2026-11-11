--!strict
-- PromptController: draws every world prompt (they use ProximityPromptStyle.Custom) as a Chunky Pop
-- block floating on its object: what it is, what it does, the key (E / X / Hold) and a hold bar.
-- On touch the block itself is the hold button. The server still decides what a prompt does.
-- Also hides prompts that can't do anything for you right now (open gate, gift before the first bank,
-- another player's Pan Upgrades), and runs the booth prompts (Round 4 phase 2: each booth opens what
-- it can so far; its own feature comes in a later phase).


local ProximityPromptService = game:GetService("ProximityPromptService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Theme = require(ReplicatedStorage.Shared.Theme)
local Ui = require(script.Parent.Parent.Lib.Ui)
local State = require(script.Parent.State)
local InputController = require(script.Parent.InputController)
local PopupController = require(script.Parent.PopupController)
local Screen = require(script.Parent.Screen)
local SettingsController = require(script.Parent.SettingsController)

local PromptController = {}
local playerGui: Instance
local shown: { [ProximityPrompt]: { gui: BillboardGui, bar: Frame, conns: { RBXScriptConnection } } } = {}

local function color(prompt: ProximityPrompt): Color3
	local a = prompt.ActionText
	return if a == "Freeze" or a == "Zap" then Theme.info elseif a == "Open" or a == "Pick up" then Theme.go else Theme.info
end

local function show(prompt: ProximityPrompt)
	if shown[prompt] then
		return
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "Prompt"
	gui.AlwaysOnTop = true
	-- a fixed screen size (a share of the short side), so it never fills the screen up close
	local cam = workspace.CurrentCamera
	local short = if cam then math.min(cam.ViewportSize.X, cam.ViewportSize.Y) else 720
	local ps = Config.ui.promptSize
	local compact = prompt:GetAttribute("Compact") == true
	local k = if compact then Config.ui.promptCompact else 1
	if InputController.device() == "touch" then
		-- a thumb has to hit it (mobile QA 2026-11-10: the compact Pick up was 26 px tall on a phone); the
		-- width grows with it, so the pill keeps its shape
		local floor = Config.ui.minTouchPx * (if compact then 0.87 else 1)
		k = math.max(k, floor / (ps[2] * short))
	end
	gui.Size = UDim2.fromOffset(ps[1] * short * k, ps[2] * short * k)
	gui.StudsOffset = Vector3.new(0, Config.ui.promptLift, 0) -- on the pet, just over its head (it floated well above before)
	if compact then
		gui.StudsOffset = Vector3.zero
		gui.SizeOffset = Vector2.new(0, 0.6) -- its bottom edge rests on the attachment (the top of a frozen pet's cube)
	end
	gui.Adornee = prompt.Parent :: any
	gui.Active = true
	-- a pill in the action's colour (owner 2026-10-31: the white card was "buns"): a white key badge,
	-- the action big in white, what it's on small under it, and the hold filling the pill left to right
	-- see-through, so the pet under it stays in view (owner 2026-10-31). A CanvasGroup fades the pill
	-- as one layer (fading face and lip apart went dark where they overlap); the words and key sit on
	-- an overlay outside it and stay solid. The margin keeps the outline from being clipped.
	local m = Config.ui.stroke + 1
	local fade = Instance.new("CanvasGroup")
	fade.Name = "Fade"
	fade.BackgroundTransparency = 1
	fade.Position = UDim2.fromOffset(-m, -m)
	fade.Size = UDim2.new(1, 2 * m, 1, 2 * m)
	fade.GroupTransparency = Config.ui.promptFade
	fade.Parent = gui
	local b = Ui.block(fade, "Block", color(prompt), "", nil)
	b.root.Position = UDim2.fromOffset(m, m)
	b.root.Size = UDim2.new(1, -2 * m, 1, -2 * m)
	local top = Instance.new("TextButton") -- the face's twin above the fade: the words, the key, the touch target
	top.Name = "Top"
	top.Text = ""
	top.AutoButtonColor = false
	top.BackgroundTransparency = 1
	top.Size = b.face.Size
	top.Parent = gui
	b.face:GetPropertyChangedSignal("Size"):Connect(function()
		top.Size = b.face.Size
	end)
	b.text.Parent = top
	for _, part in { b.root, b.face } do
		local c = part:FindFirstChildOfClass("UICorner") :: UICorner
		c.CornerRadius = UDim.new(0.5, 0)
	end
	local bar = Instance.new("Frame") -- under the text, over the face's colour
	bar.Name = "Hold"
	bar.BackgroundColor3 = Theme.white
	bar.BackgroundTransparency = Config.ui.promptHoldFill
	bar.BorderSizePixel = 0
	bar.Size = UDim2.fromScale(0, 1)
	bar.ZIndex = 0
	Ui.corner(bar, 0.5)
	bar.Parent = b.face
	local keyBox = Instance.new("Frame")
	keyBox.Name = "Key"
	keyBox.BackgroundColor3 = Theme.white
	keyBox.AnchorPoint = Vector2.new(0, 0.5)
	keyBox.Position = UDim2.fromScale(0.04, 0.5)
	keyBox.Size = UDim2.fromScale(0.5, 0.74)
	local ka = Instance.new("UIAspectRatioConstraint")
	ka.Parent = keyBox
	Ui.corner(keyBox, 0.5)
	Ui.stroke(keyBox, 2)
	keyBox.Parent = top
	local key = Ui.inkLabel(keyBox, InputController.keyHint(prompt), UDim2.fromScale(0.8, 0.7), UDim2.fromScale(0.1, 0.15))
	local function fitKey()
		ka.AspectRatio = if #key.Text > 1 then 1.5 else 1 -- "Tap" / "Hold" on touch gets a wider badge
		-- the words start right after the badge, so a wide badge never covers them (final QA 2026-11-03:
		-- on a phone "Tap" hid the "Up" of "Upgrade" and the "Op" of "Open")
		local x = 0.04 + 0.74 * ka.AspectRatio * ps[2] / ps[1] + 0.03
		for _, t in { b.text, top:FindFirstChild("What") } do
			if t and t:IsA("GuiObject") then
				t.Position = UDim2.fromScale(x, t.Position.Y.Scale)
				t.Size = UDim2.fromScale(0.97 - x, t.Size.Y.Scale)
			end
		end
	end
	b.text.Text = prompt.ActionText
	b.text.TextXAlignment = Enum.TextXAlignment.Left
	local hasObject = prompt.ObjectText ~= ""
	b.text.Size = UDim2.fromScale(0.62, if hasObject then 0.5 else 0.7)
	b.text.Position = UDim2.fromScale(0.33, if hasObject then 0.08 else 0.15)
	if hasObject then
		local what = Ui.label(top, prompt.ObjectText, UDim2.fromScale(0.62, 0.32), UDim2.fromScale(0.33, 0.57))
		what.Name = "What"
		what.TextXAlignment = Enum.TextXAlignment.Left
		what.TextTransparency = 0.1
	end
	fitKey()
	if compact then
		-- it rests above the cube, so nothing under it needs to show through: a solid pill reads crisper
		fade.GroupTransparency = 0
		-- outlines shrink with the pill (UI Rules: after scaling, recheck outline weight), never under 1.5 px
		for _, s in { b.root:FindFirstChildOfClass("UIStroke"), keyBox:FindFirstChildOfClass("UIStroke") } do
			if s then
				s.Thickness = math.max(1.5, s.Thickness * k)
			end
		end
	end
	gui.Enabled = not (Screen.menuHidden or Screen.showHidden) -- a shop is open or a show plays: the pill stays out of the way
	gui.Parent = playerGui
	if compact then
		-- pops up off the cube (Animation Rules: pop, Back Out); the bottom stays on the cube as it grows
		local full = gui.Size
		local reduced = SettingsController.get("reducedMotion") == true
		gui.Size = UDim2.fromOffset(full.X.Offset * 0.3, full.Y.Offset * 0.3)
		TweenService:Create(gui, TweenInfo.new(Config.motion.promptPop * (if reduced then 0.5 else 1), Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = full }):Play()
	end
	local conns: { RBXScriptConnection } = {}
	-- touch and mouse: the block is the hold button. The hold ends when that finger (or the mouse button)
	-- lifts anywhere: a finger that slid off the pill kept the hold going (mobile QA 2026-11-10)
	local holding: InputObject? = nil
	local function release(input: InputObject)
		local h = holding
		if h and (input == h or (input.UserInputType == Enum.UserInputType.MouseButton1 and h.UserInputType == Enum.UserInputType.MouseButton1)) then
			holding = nil
			prompt:InputHoldEnd()
		end
	end
	table.insert(conns, top.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			holding = input
			prompt:InputHoldBegin()
		end
	end))
	table.insert(conns, top.InputEnded:Connect(release))
	table.insert(conns, UserInputService.InputEnded:Connect(release))
	table.insert(conns, InputController.DeviceChanged:Connect(function()
		key.Text = InputController.keyHint(prompt)
		fitKey()
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
	-- every island's gate (Round 4 phase 6): only the next one you can open asks you to pay
	local reach = v.reach or 1
	for _, z in Config.world.zones do
		local gate = if z.id > 1 then map:FindFirstChild("GatePromptSpot" .. z.id, true) else nil
		local gp = gate and gate:FindFirstChildWhichIsA("ProximityPrompt", true)
		if gp then
			gp.Enabled = z.ready and z.id == reach + 1
		end
	end
	local gift = map:FindFirstChild("GiftBox", true)
	local gift_p = gift and gift:FindFirstChildWhichIsA("ProximityPrompt", true)
	if gift_p then
		gift_p.Enabled = v.gift.ready
	end
	-- Pan Upgrades: only at your own pan
	for i in Config.world.plots do
		local plot = map:FindFirstChild("Plot" .. i)
		local stand = plot and plot:FindFirstChild("PanUpgrade")
		local pp = stand and stand:FindFirstChildWhichIsA("ProximityPrompt", true)
		if pp then
			pp.Enabled = v.plot == i
		end
		-- the Thaw Machine's "Thaw a pet": only at your own pan, and machine 2 once you have it
		local pan = map:FindFirstChild("Pan" .. i, true)
		for m = 1, 2 do
			local machine = pan and pan:FindFirstChild("ThawMachine" .. m)
			local tp = machine and machine:FindFirstChild("ThawPrompt", true)
			if tp and tp:IsA("ProximityPrompt") then
				tp.Enabled = v.plot == i and m <= (v.machines or 1)
			end
		end
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
	local function stepAside()
		local hidden = Screen.menuHidden or Screen.showHidden
		for _, s in shown do
			s.gui.Enabled = not hidden
		end
		-- the ProximityPrompt itself still listens for its key: a press with the shop open would reopen it
		ProximityPromptService.Enabled = not hidden
	end
	Screen.MenuHiddenChanged:Connect(stepAside)
	Screen.ShowHiddenChanged:Connect(stepAside)
	ProximityPromptService.PromptButtonHoldBegan:Connect(function(prompt: ProximityPrompt)
		local s = shown[prompt]
		if s then
			s.bar.Size = UDim2.fromScale(0, 1)
			if prompt.ActionText ~= "Freeze" and prompt.ActionText ~= "Zap" then -- a freeze's bar follows the freeze (below)
				TweenService:Create(s.bar, TweenInfo.new(prompt.HoldDuration, Enum.EasingStyle.Linear), { Size = UDim2.fromScale(1, 1) }):Play()
			end
		end
	end)
	-- (Round 5: pets are shot, not prompted; RayController's aim ring shows how frozen a target is)
	ProximityPromptService.PromptButtonHoldEnded:Connect(function(prompt: ProximityPrompt)
		local s = shown[prompt]
		if s then
			TweenService:Create(s.bar, TweenInfo.new(0.1), { Size = UDim2.fromScale(0, 1) }):Play()
		end
	end)
	State.Changed:Connect(refreshWorldPrompts)
	-- booths: the prompt card is the way in (no HUD button)
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt)
		local booth = prompt:GetAttribute("Booth")
		if typeof(booth) ~= "string" then
			return
		end
		-- what it does comes from Config (a prompt in the saved map keeps the attribute it was built with)
		local action = prompt:GetAttribute("Action")
		for _, b in Config.world.booths do
			if b.id == booth then
				action = b.action
			end
		end
		if booth == "pan" then
			action = Config.world.panUpgradeAction -- your pan's stand (Round 4 phase 5: the Pan Upgrades popup)
		elseif booth == "thaw" then
			action = "thaw" -- your Thaw Machine: pick a frozen pet to put in (owner 2026-11-09)
		end
		if action == "shop" or action == "equipment" or action == "pan" or action == "sell" or action == "rebirth" or action == "thaw" then
			PopupController.open(action, if action == "thaw" then { machine = prompt:GetAttribute("Machine") or 1 } else nil)
			-- a booth's buttons only work at the booth (the server checks its own range), so its popup
			-- closes when you walk away (final QA 2026-11-03: Buy far away did nothing, with no answer)
			local range = ({ equipment = Config.guns.boothRange, sell = Config.sell.boothRange, rebirth = Config.rebirth.boothRange, pan = Config.pan.standRange, thaw = Config.thaw.useRange } :: { [string]: number })[action]
			local at: Vector3? = nil
			for _, b in Config.world.booths do
				if b.id == booth then
					at = b.pos
				end
			end
			local parent = prompt.Parent
			if not at and parent then
				at = if parent:IsA("Attachment") then parent.WorldPosition elseif parent:IsA("BasePart") then parent.Position else nil
			end
			if range and at then
				local center, limit = at :: Vector3, range - Config.boothLeaveMargin
				task.spawn(function()
					local me = game:GetService("Players").LocalPlayer
					while PopupController.openName() == action do
						local root = me.Character and me.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
						if root and Vector2.new(root.Position.X - center.X, root.Position.Z - center.Z).Magnitude > limit then
							PopupController.close()
							break
						end
						task.wait(0.25)
					end
				end)
			end
		else
			State.local_("comingSoon", { label = prompt.ObjectText })
		end
	end)
end

return PromptController
