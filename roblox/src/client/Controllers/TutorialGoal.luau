--!strict
-- TutorialGoal (2026-11-15, from the tutorial references in the vault: Research > Tutorial References):
-- the tutorial's one goal, in a pill at the top centre, always on while a step is running. A painted
-- icon on a tile, the goal in a few big words, a count bar on counted steps ("Cold Power 120 / 500"),
-- a row of dots under it for how far through the lesson you are, and a quiet Skip at its right end.
-- It pops in on each new goal and flashes green when one is done. Since Captain Frost left (2026-11-15)
-- it also carries the short messages: a cheer, a hint or a reaction replaces the goal for a moment.
-- Built and driven by TutorialController (no Init/Start of its own); Screen places it.

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Theme = require(ReplicatedStorage.Shared.Theme)
local Ui = require(script.Parent.Parent.Lib.Ui)
local Screen = require(script.Parent.Screen)
local InputController = require(script.Parent.InputController)
local SettingsController = require(script.Parent.SettingsController)

local TutorialGoal = {}
local T = Config.tutorial

local root: Frame
local pill: Ui.Block
local pop: UIScale
local icon: ImageLabel
local words: TextLabel
local bar: Frame
local fill: Frame
local countText: TextLabel
local dots: Frame
local skipB: Ui.Block
local skipBadge: TextLabel
local wiggle: Tween? = nil
local goalWords = "" -- the goal, put back after a message
local messageToken = 0

local function reduced(): boolean
	return SettingsController.get("reducedMotion") == true
end

-- "pet" = the first island's Common, as its painted sprite; anything else = a painted icon
local function imageFor(key: string?): string
	if key == "pet" then
		return Config.images.pets[T.petIcon] or Config.images.icons.coin
	end
	return (key and Config.images.icons[key]) or Config.images.icons.star
end

-- one text size per role, from the pill's height (UI Rules: no TextScaled per label)
local function fitText()
	local h = pill.root.AbsoluteSize.Y
	local function fit(l: TextLabel, share: number)
		local c = l:FindFirstChildOfClass("UITextSizeConstraint")
		if c then
			c.MaxTextSize = math.max(8, math.floor(h * share))
			c.MinTextSize = math.max(6, math.floor(h * share * 0.6))
		end
	end
	fit(words, if bar.Visible then 0.34 else 0.42)
	fit(countText, 0.24)
	fit(skipB.text, 0.26)
end

local function sized(l: TextLabel)
	l.TextScaled = true
	Instance.new("UITextSizeConstraint").Parent = l
end

local function refreshKeys()
	skipBadge.Visible = InputController.device() == "gamepad"
end

function TutorialGoal.build(onSkip: () -> ())
	root = Instance.new("Frame")
	root.Name = "TutorialGoal"
	root.BackgroundTransparency = 1
	root.Visible = false
	pop = Instance.new("UIScale")
	pop.Name = "Pop"
	pop.Parent = root
	pill = Ui.block(root, "Pill", Theme.panel, "", nil, true)
	pill.root.Size = UDim2.fromScale(1, 0.78)
	pill.text.Visible = false
	Ui.roundBlock(pill, 0.5)
	-- the icon on a round tile in info blue, standing a little out of the pill's left end
	local tile = Instance.new("Frame")
	tile.Name = "IconTile"
	tile.BackgroundColor3 = Theme.info
	tile.AnchorPoint = Vector2.new(0, 0.5)
	tile.Position = UDim2.fromScale(-0.01, 0.5)
	tile.Size = UDim2.fromScale(1.15, 1.15)
	local ta = Instance.new("UIAspectRatioConstraint")
	ta.AspectRatio = 1
	ta.DominantAxis = Enum.DominantAxis.Height
	ta.Parent = tile
	Ui.corner(tile, 0.5)
	Ui.stroke(tile)
	tile.Parent = pill.face
	icon = Ui.image(tile, imageFor(nil), UDim2.fromScale(0.8, 0.8), UDim2.fromScale(0.1, 0.1))
	-- the goal words
	words = Ui.inkLabel(pill.face, "", UDim2.fromScale(0.62, 0.8), UDim2.fromScale(0.15, 0.1))
	words.Name = "Goal"
	words.TextXAlignment = Enum.TextXAlignment.Left
	sized(words)
	-- the count: a bar and "120 / 500" under the words on a counted step
	bar = Instance.new("Frame")
	bar.Name = "Count"
	bar.BackgroundColor3 = Theme.white
	bar.Position = UDim2.fromScale(0.15, 0.58)
	bar.Size = UDim2.fromScale(0.4, 0.24)
	bar.Visible = false
	Ui.corner(bar, 0.5)
	Ui.stroke(bar, Config.ui.cardStroke)
	fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BackgroundColor3 = Theme.info
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(0, 1)
	Ui.corner(fill, 0.5)
	fill.Parent = bar
	bar.Parent = pill.face
	countText = Ui.inkLabel(pill.face, "", UDim2.fromScale(0.2, 0.3), UDim2.fromScale(0.57, 0.55))
	countText.Name = "CountText"
	countText.TextXAlignment = Enum.TextXAlignment.Left
	countText.Visible = false
	sized(countText)
	-- Skip: small and grey at the right end (it asks "Sure?" first)
	skipB = Ui.block(pill.face, "Skip", Theme.tutorial.skip, "Skip", onSkip)
	skipB.root.AnchorPoint = Vector2.new(1, 0.5)
	skipB.root.Position = UDim2.fromScale(0.97, 0.5)
	skipB.root.Size = UDim2.fromScale(0.15, 0.62)
	sized(skipB.text)
	skipB.text.TextScaled = true
	skipBadge = Ui.inkLabel(skipB.root, "B", UDim2.fromScale(0.3, 0.6), UDim2.fromScale(0.82, -0.3))
	skipBadge.BackgroundTransparency = 0
	skipBadge.BackgroundColor3 = Theme.white
	Ui.corner(skipBadge, 0.5)
	Ui.stroke(skipBadge, Config.ui.cardStroke)
	-- the step dots, under the pill
	dots = Instance.new("Frame")
	dots.Name = "Dots"
	dots.BackgroundTransparency = 1
	dots.AnchorPoint = Vector2.new(0.5, 0)
	dots.Position = UDim2.fromScale(0.5, 0.84)
	dots.Size = UDim2.fromScale(0.5, 0.16)
	local l = Instance.new("UIListLayout")
	l.FillDirection = Enum.FillDirection.Horizontal
	l.HorizontalAlignment = Enum.HorizontalAlignment.Center
	l.VerticalAlignment = Enum.VerticalAlignment.Center
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.Padding = UDim.new(0.02, 0)
	l.Parent = dots
	dots.Parent = root
	pill.root:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitText)
	InputController.DeviceChanged:Connect(refreshKeys)
	refreshKeys()
	Screen.register("goal", root)
	fitText()
end

local function setDots(at: number, count: number)
	for _, c in dots:GetChildren() do
		if c:IsA("Frame") then
			c:Destroy()
		end
	end
	for i = 1, count do
		local d = Instance.new("Frame")
		d.Name = "Dot" .. i
		d.LayoutOrder = i
		d.BackgroundColor3 = if i < at then Theme.go elseif i == at then Theme.white else Theme.tiers.Common
		d.Size = UDim2.fromScale(if i == at then 0.07 else 0.05, if i == at then 0.95 else 0.7)
		local a = Instance.new("UIAspectRatioConstraint")
		a.AspectRatio = 1
		a.DominantAxis = Enum.DominantAxis.Height
		a.Parent = d
		Ui.corner(d, 0.5)
		Ui.stroke(d, Config.ui.cardStroke)
		d.Parent = dots
	end
end

-- a new goal: words, icon key, which dot of how many; counted = show the count bar
function TutorialGoal.set(goalText: string, iconKey: string?, at: number, count: number, counted: boolean)
	messageToken += 1 -- a new goal ends any message
	goalWords = goalText
	words.Text = goalText
	words.TextColor3 = Theme.ink
	icon.Image = imageFor(iconKey)
	bar.Visible, countText.Visible = counted, counted
	words.Size = UDim2.fromScale(0.62, if counted then 0.46 else 0.8)
	words.Position = UDim2.fromScale(0.15, if counted then 0.08 else 0.1)
	setDots(at, count)
	fitText()
	local was = root:GetAttribute("Want") == true
	root:SetAttribute("Want", true) -- Screen shows it (and hides it while a popup is open)
	if reduced() then
		pop.Scale = 1
	else
		pop.Scale = if was then 0.85 else 0.5
		TweenService:Create(pop, TweenInfo.new(T.popSeconds * 1.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		-- the icon gives a little wiggle: the one moving thing on the pill
		if wiggle then
			wiggle:Cancel()
		end
		icon.Rotation = -12
		local w = TweenService:Create(icon, TweenInfo.new(0.5, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out), { Rotation = 0 })
		wiggle = w
		w:Play()
	end
end

-- the count on a counted step (have / need), every frame while it shows
function TutorialGoal.count(have: number, need: number)
	local share = math.clamp(have / math.max(1, need), 0, 1)
	fill.Size = UDim2.fromScale(math.max(share, 0.04), 1)
	fill.BackgroundColor3 = if share >= 1 then Theme.go else Theme.info
	countText.Text = `{Config.powerText(math.floor(have))} / {Config.powerText(need)}`
end

-- a short message in the pill for `seconds` (a cheer in green words, a hint or a reaction in blue), then
-- the goal comes back
function TutorialGoal.message(text: string, cheer: boolean, seconds: number)
	if root:GetAttribute("Want") ~= true then
		return
	end
	messageToken += 1
	local my = messageToken
	words.Text = text
	words.TextColor3 = if cheer then Ui.darker(Theme.go) else Theme.infoDeep
	if not reduced() then
		pop.Scale = 0.9
		TweenService:Create(pop, TweenInfo.new(T.popSeconds, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end
	task.delay(seconds, function()
		if messageToken == my then
			words.Text = goalWords
			words.TextColor3 = Theme.ink
		end
	end)
end

-- a goal was done: the pill flashes go-green for a moment
function TutorialGoal.flash()
	if root:GetAttribute("Want") ~= true then
		return
	end
	pill.face.BackgroundColor3 = Theme.go
	TweenService:Create(pill.face, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundColor3 = Theme.panel }):Play()
end

function TutorialGoal.hide()
	root:SetAttribute("Want", false)
end

function TutorialGoal.visible(): boolean
	return root.Visible
end

-- Skip's "Sure?" state
function TutorialGoal.confirmSkip(on: boolean)
	skipB.text.Text = if on then T.react.skipConfirm else "Skip"
	skipB.face.BackgroundColor3 = if on then Theme.no else Theme.tutorial.skip
	skipB.root.BackgroundColor3 = Ui.darker(skipB.face.BackgroundColor3)
end

function TutorialGoal.skipVisible(on: boolean)
	skipB.root.Visible = on
end

return TutorialGoal
