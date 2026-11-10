--!strict
-- TutorialCard: Ranger Bo's speech card, built by TutorialController (no Init/Start of its own).
-- Chunky Pop (UI Rules): a cream panel block with his face in a window, his name on a ribbon in his
-- coat colour, the line typed out letter by letter, the step's goal in small blue, a green Next (only
-- on talk steps, the one thing that pulses) and a quiet grey Skip that asks "Sure?" first.
-- Next: click / tap / Enter / gamepad A. Skip: click / tap / gamepad B. Screen places the card.

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Theme = require(ReplicatedStorage.Shared.Theme)
local Ui = require(script.Parent.Parent.Lib.Ui)
local Screen = require(script.Parent.Screen)
local InputController = require(script.Parent.InputController)
local SettingsController = require(script.Parent.SettingsController)
local TutorialNpc = require(script.Parent.TutorialNpc)

local TutorialCard = {}
local T = Config.tutorial
local TU = Config.ui.tutorial

local root: Frame
local pop: UIScale
local line: TextLabel
local goal: TextLabel
local nextB: Ui.Block
local skipB: Ui.Block
local nextBadge: Frame
local skipBadge: Frame
local pulse: Tween? = nil
local typedAt = 0
local typing = false
local shown = false
local wantShown = false
local held = false -- hidden while a popup is open

local function reduced(): boolean
	return SettingsController.get("reducedMotion") == true
end

-- a small white key badge (like the world prompts' E / X)
local function badge(parent: GuiObject): Frame
	local b = Instance.new("Frame")
	b.Name = "Key"
	b.BackgroundColor3 = Theme.white
	b.AnchorPoint = Vector2.new(1, 0.5)
	b.Position = UDim2.fromScale(0.95, 0.5)
	b.Size = UDim2.fromScale(0.34, 0.62)
	Ui.corner(b, 0.5)
	Ui.stroke(b, Config.ui.cardStroke)
	local t = Ui.inkLabel(b, "", UDim2.fromScale(0.86, 0.8), UDim2.fromScale(0.07, 0.1))
	t.Name = "Text"
	b.Parent = parent
	return b
end

local function setBadge(b: Frame, text: string?)
	b.Visible = text ~= nil
	local t = b:FindFirstChild("Text") :: TextLabel?
	if t and text then
		t.Text = text
	end
end

-- key hints follow the device in use: none on touch
local function refreshKeys()
	local d = InputController.device()
	setBadge(nextBadge, if d == "keyboard" then "Enter" elseif d == "gamepad" then "A" else nil)
	setBadge(skipBadge, if d == "gamepad" then "B" else nil)
	-- the label makes room for the badge when there is one
	local function room(b: Ui.Block, k: Frame)
		b.text.Size = UDim2.fromScale(if k.Visible then 0.56 else 0.9, 0.8)
		b.text.Position = UDim2.fromScale(0.05, 0.1)
	end
	room(nextB, nextBadge)
	room(skipB, skipBadge)
end

-- one text size per role, from the card's height (UI Rules); long lines may shrink a little to fit
local function fitText()
	local h = root.AbsoluteSize.Y
	local function fit(label: TextLabel, share: number)
		local c = label:FindFirstChildOfClass("UITextSizeConstraint")
		if c then
			c.MaxTextSize = math.max(8, math.floor(h * share))
			c.MinTextSize = math.max(6, math.floor(h * share * 0.6))
		end
	end
	fit(line, TU.text)
	fit(goal, TU.goalText)
end

local function sizedLabel(parent: Instance, size: UDim2, pos: UDim2, color: Color3): TextLabel
	local t = Ui.inkLabel(parent, "", size, pos)
	t.TextColor3 = color
	t.TextWrapped = true
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.TextYAlignment = Enum.TextYAlignment.Top
	Instance.new("UITextSizeConstraint").Parent = t
	return t
end

function TutorialCard.build(onNext: () -> (), onSkip: () -> ())
	root = Instance.new("Frame")
	root.Name = "Tutorial"
	root.BackgroundTransparency = 1
	root.Visible = false
	pop = Instance.new("UIScale")
	pop.Name = "Pop"
	pop.Parent = root
	local card = Ui.block(root, "Card", Theme.panel, "", nil, true)
	card.root.Size = UDim2.fromScale(1, 1)
	card.text.Visible = false
	card.face.Activated:Connect(TutorialCard.finishTyping) -- a tap on the card shows the whole line
	-- his face in a window
	local win = Instance.new("Frame")
	win.Name = "Portrait"
	win.BackgroundColor3 = Theme.tutorial.portrait
	win.Position = UDim2.fromScale(0.02, 0.12)
	win.Size = UDim2.fromScale(0.17, 0.76)
	Ui.corner(win)
	Ui.stroke(win, Config.ui.cardStroke)
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1
	aspect.Parent = win
	local vp = Instance.new("ViewportFrame")
	vp.Name = "Face"
	vp.BackgroundTransparency = 1
	vp.Size = UDim2.fromScale(1, 1)
	vp.Ambient = Theme.white
	vp.LightColor = Theme.white
	Ui.corner(vp)
	vp.Parent = win
	win.Parent = card.face
	task.spawn(TutorialNpc.portrait, vp) -- waits for the server's model
	line = sizedLabel(card.face, UDim2.fromScale(0.56, 0.54), UDim2.fromScale(0.21, 0.12), Theme.ink)
	line.Name = "Line"
	goal = sizedLabel(card.face, UDim2.fromScale(0.56, 0.22), UDim2.fromScale(0.21, 0.68), Theme.infoDeep)
	goal.Name = "Goal"
	-- his name on a ribbon over the top edge
	local name = Ui.block(root, "Name", Theme.tutorial.coat, T.name, nil)
	name.root.Position = UDim2.fromScale(0.21, -0.16)
	name.root.Size = UDim2.fromScale(0.24, 0.28)
	nextB = Ui.block(root, "Next", Theme.go, "Next", onNext)
	nextB.root.Position = UDim2.fromScale(0.785, 0.12)
	nextB.root.Size = UDim2.fromScale(0.195, 0.44)
	nextBadge = badge(nextB.face)
	skipB = Ui.block(root, "Skip", Theme.tutorial.skip, "Skip", onSkip)
	skipB.root.Position = UDim2.fromScale(0.81, 0.62)
	skipB.root.Size = UDim2.fromScale(0.145, 0.27)
	skipBadge = badge(skipB.face)
	local ps = Instance.new("UIScale")
	ps.Name = "Pulse"
	ps.Parent = nextB.root
	root:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitText)
	InputController.DeviceChanged:Connect(refreshKeys)
	refreshKeys()
	Screen.register("tutorial", root)
	fitText()
end

local function applyVisible()
	local on = wantShown and not held
	if on == shown then
		return
	end
	shown = on
	if on then
		root.Visible = true
		if reduced() then
			pop.Scale = 1
		else
			pop.Scale = 0.6
			TweenService:Create(pop, TweenInfo.new(T.popSeconds, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		end
	else
		if reduced() then
			root.Visible = false
			return
		end
		local tw = TweenService:Create(pop, TweenInfo.new(T.closeSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0.9 })
		tw.Completed:Connect(function()
			if not shown then
				root.Visible = false
			end
		end)
		tw:Play()
	end
end

function TutorialCard.show()
	wantShown = true
	applyVisible()
end

function TutorialCard.hide()
	wantShown = false
	applyVisible()
	TutorialCard.setNext(false)
end

-- a popup (the Thaw Machine's, a booth) is open: step aside until it closes
function TutorialCard.hold(on: boolean)
	if held ~= on then
		held = on
		applyVisible()
	end
end

function TutorialCard.visible(): boolean
	return shown
end

function TutorialCard.setNext(on: boolean)
	nextB.root.Visible = on
	if pulse then
		pulse:Cancel()
		pulse = nil
	end
	local ps = nextB.root:FindFirstChild("Pulse") :: UIScale
	ps.Scale = 1
	if on and not reduced() then
		-- the one moving thing on the card (Animation Rules: pulse)
		local tw = TweenService:Create(ps, TweenInfo.new(T.pulseSeconds, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Scale = T.pulseScale })
		pulse = tw
		tw:Play()
	end
end

function TutorialCard.nextVisible(): boolean
	return nextB.root.Visible
end

-- a new line, typed out; goalText = the step's goal under it (nil = none); withNext = a talk step
function TutorialCard.say(text: string, goalText: string?, withNext: boolean)
	line.Text = text
	line.MaxVisibleGraphemes = 0
	goal.Text = if goalText then "Goal: " .. goalText else ""
	typedAt = os.clock()
	typing = true
	TutorialCard.setNext(withNext)
	TutorialCard.show()
end

function TutorialCard.finishTyping()
	if typing then
		typing = false
		line.MaxVisibleGraphemes = -1
	end
end

function TutorialCard.typing(): boolean
	return typing
end

-- once a frame: the typewriter
function TutorialCard.update()
	if not typing then
		return
	end
	local n = math.floor((os.clock() - typedAt) * T.typeCps)
	local len = utf8.len(line.Text) or #line.Text
	if n >= len then
		TutorialCard.finishTyping()
	else
		line.MaxVisibleGraphemes = n
	end
end

-- Skip's "Sure?" state
function TutorialCard.confirmSkip(on: boolean)
	skipB.text.Text = if on then T.react.skipConfirm else "Skip"
	skipB.face.BackgroundColor3 = if on then Theme.no else Theme.tutorial.skip
	skipB.root.BackgroundColor3 = Ui.darker(skipB.face.BackgroundColor3)
end

function TutorialCard.skipVisible(on: boolean)
	skipB.root.Visible = on
end

return TutorialCard
