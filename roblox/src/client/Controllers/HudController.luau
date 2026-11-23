--!strict
-- HudController: the HUD's contents: the menu tiles (Pets, Shop, Index, Settings), the coins with
-- +N/s, the island banner (drops in when you walk onto an island) and the banner (Big Chill, others'
-- big wins, "not yet" answers). Screen places all of them. Owner 2026-11-07: the goal bar and the
-- temperature chip are gone; the island banner shows each island's heat as you arrive.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContentProvider = game:GetService("ContentProvider")
local Config = require(ReplicatedStorage.Shared.Config)
local Theme = require(ReplicatedStorage.Shared.Theme)
local PetDefs = require(ReplicatedStorage.Shared.PetDefs)
local WorldRules = require(ReplicatedStorage.Shared.WorldRules)
local Ui = require(script.Parent.Parent.Lib.Ui)
local State = require(script.Parent.State)
local Screen = require(script.Parent.Screen)
local PopupController = require(script.Parent.PopupController)
local SettingsController = require(script.Parent.SettingsController)
local SoundController = require(script.Parent.SoundController)
local EquipmentPopup = require(script.Parent.EquipmentPopup)

local HudController = {}

local coinsRoot: Frame
local coinsText: TextLabel
local coinsRate: TextLabel
local powerRoot: Frame -- Cold Power: its icon and number, under the coins
local powerText: TextLabel
local powerScale: UIScale
local lastPower: number? = nil
local alertsFrame: Frame -- the alert toasts (Config.ui.alerts), placed by Screen under the top buttons
local dailyDot: Frame? = nil -- a round dot on the Daily tile while a finished challenge waits to be claimed

-- ---------- alerts (owner 2026-11-16: "the alerts UI is not really it ... put it under equipment and pan") ----------
-- each alert is a small dark toast: an icon chip in the alert's colour (red no, green go, yellow coins, blue info),
-- short white words. They slide in under the top buttons, stack (newest at the bottom), and fade out. The same
-- words again only restart their timer. pulse = it throbs a few times (a melted cube, a Secret).
type Toast = { root: CanvasGroup, text: string, untilAt: number, scale: UIScale }
local toasts: { Toast } = {}
local toastOrder = 0

local function iconFor(color: Color3): string
	if color == Theme.no then
		return "lock"
	elseif color == Theme.coin then
		return "coin"
	elseif color == Theme.go then
		return "star"
	end
	return "ray"
end

local function reducedMotion(): boolean
	return SettingsController.get("reducedMotion") == true
end

local function dropToast(t: Toast)
	local i = table.find(toasts, t)
	if not i then
		return
	end
	table.remove(toasts, i)
	local A = Config.ui.alerts
	TweenService:Create(t.root, TweenInfo.new(A.outSeconds), { GroupTransparency = 1 }):Play()
	task.delay(A.outSeconds, function()
		t.root:Destroy()
	end)
end

local function makeToast(textValue: string, color: Color3, icon: string): Toast
	local A = Config.ui.alerts
	local stackH = A.stack * A.size[2] + (A.stack - 1) * A.gap
	local g = Instance.new("CanvasGroup")
	g.Name = "Toast"
	g.BackgroundTransparency = 1
	g.Size = UDim2.fromScale(1, A.size[2] / stackH)
	toastOrder += 1
	g.LayoutOrder = toastOrder
	g.GroupTransparency = 1
	-- the pill: navy fading lighter at the top, one ink outline (inset so the group doesn't clip it)
	local back = Instance.new("Frame")
	back.Name = "Back"
	back.AnchorPoint = Vector2.new(0.5, 0.5)
	back.Position = UDim2.fromScale(0.5, 0.5)
	back.Size = UDim2.new(1, -8, 1, -8)
	back.BackgroundColor3 = Theme.alert.back
	back.BorderSizePixel = 0
	Ui.corner(back, 0.5)
	Ui.stroke(back, 3)
	local grad = Instance.new("UIGradient")
	grad.Rotation = 90
	grad.Color = ColorSequence.new(Theme.alert.backTop, Theme.alert.back)
	grad.Parent = back
	back.Parent = g
	-- the coloured chip with the painted icon, at the left end
	local chip = Instance.new("Frame")
	chip.Name = "Chip"
	chip.AnchorPoint = Vector2.new(0, 0.5)
	chip.Position = UDim2.new(0, 3, 0.5, 0)
	chip.Size = UDim2.new(1, -6, 1, -6)
	chip.BackgroundColor3 = color
	chip.BorderSizePixel = 0
	local ca = Instance.new("UIAspectRatioConstraint")
	ca.AspectRatio = 1
	ca.DominantAxis = Enum.DominantAxis.Height
	ca.Parent = chip
	Ui.corner(chip, 0.5)
	Ui.stroke(chip, 2.5)
	chip.Parent = back
	local img = Config.images.icons[icon] or Config.images.icons.ray
	if img then
		Ui.image(chip, img, UDim2.fromScale(0.8, 0.8), UDim2.fromScale(0.1, 0.1))
	end
	-- the words: white with an outline, left of centre after the chip
	local label = Ui.label(back, textValue, UDim2.new(1, 0, 0.62, 0), UDim2.fromScale(0, 0.19))
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.RichText = true
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0.13, 0)
	pad.PaddingRight = UDim.new(0.05, 0)
	pad.Parent = label
	local s = Instance.new("UIScale")
	s.Parent = g
	g.Parent = alertsFrame
	return { root = g, text = textValue, untilAt = 0, scale = s }
end

-- the tutorial is running (QA PT-06, 2026-11-19: three banners stacked under the tutorial bar at step 5)
local function tutorialOn(): boolean
	local tu = State.view and State.view.tutorial
	return tu ~= nil and not tu.done
end

-- waitForHud: a reward toast (daily, weekly, Extras) keeps its time until the player can see it; anything
-- about the clock (night warnings, events) runs out on time instead of showing up late and wrong
function HudController.banner(textValue: string, color: Color3?, seconds: number?, icon: string?, pulse: boolean?, waitForHud: boolean?)
	if not alertsFrame then
		return
	end
	local A = Config.ui.alerts
	local stack = if tutorialOn() then 1 else A.stack -- one banner at a time while the tutorial talks
	local c = color or Theme.info
	local hold = seconds or Config.ui.bannerSeconds
	local still = reducedMotion()
	local t: Toast? = nil
	for _, o in toasts do
		if o.text == textValue then
			t = o -- the same words again: keep the toast, restart its timer, give it a nudge
		end
	end
	if not t then
		while #toasts >= stack do
			dropToast(toasts[1])
		end
		local n = makeToast(textValue, c, icon or iconFor(c))
		table.insert(toasts, n)
		n.scale.Scale = if still then 1 else 0.8
		TweenService:Create(n.root, TweenInfo.new(A.slideSeconds), { GroupTransparency = 0 }):Play()
		t = n
	end
	local toast = t :: Toast
	if not still then
		toast.scale.Scale = math.min(toast.scale.Scale, 0.86)
		TweenService:Create(toast.scale, TweenInfo.new(A.slideSeconds * 1.6, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		if pulse then
			TweenService:Create(toast.scale, TweenInfo.new(0.32, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, 3, true, A.slideSeconds * 1.6), { Scale = 1.07 }):Play()
		end
	end
	local untilAt = os.clock() + hold
	toast.untilAt = untilAt
	-- a reward's clock only runs while the alerts show (QA 2026-11-20: "Day 1: +250" from the Daily popup ran
	-- out unseen behind it); it waits for the menu or show to end, then holds its time
	task.spawn(function()
		local sg = alertsFrame:FindFirstAncestorOfClass("ScreenGui")
		local left = hold
		while left > 0 and toast.untilAt == untilAt do
			local dt = task.wait(0.1)
			local shown = (not sg or sg.Enabled) and alertsFrame.Visible
			if shown or not waitForHud then
				left -= dt
			end
		end
		if toast.untilAt == untilAt then
			dropToast(toast)
		end
	end)
end

-- ---------- the Cold Power gain banner (owner 2026-11-16, from the speed-game reference) ----------
-- a bright cyan-to-mint box at the top with white rays behind it and "+N" with the Cold Power icon. It adds up
-- the gains that come close together and throbs with each one, then goes once you stop training.
local gainRoot: Frame
local gainText: TextLabel
local gainScale: UIScale
local gainSum, gainLast = 0, 0
local gainToken = 0

local function buildGain()
	local root = Instance.new("Frame")
	root.Name = "GainBanner"
	root.BackgroundTransparency = 1
	root.Visible = false
	local rays = Instance.new("ImageLabel")
	rays.Name = "Rays"
	rays.BackgroundTransparency = 1
	rays.Image = Config.images.icons.sunburst or ""
	rays.ImageColor3 = Theme.gainBanner.rays
	rays.ImageTransparency = 0.25
	rays.AnchorPoint = Vector2.new(0.5, 0.5)
	rays.Position = UDim2.fromScale(0.5, 0.5)
	rays.Size = UDim2.fromScale(0.75, 2.6)
	rays.ZIndex = 0
	rays.Parent = root
	local box = Instance.new("Frame")
	box.Name = "Box"
	box.Size = UDim2.fromScale(1, 1)
	box.BackgroundColor3 = Theme.white
	box.BorderSizePixel = 0
	box.ZIndex = 1
	Ui.corner(box)
	Ui.stroke(box, 3)
	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new(Theme.gainBanner.from, Theme.gainBanner.to)
	grad.Parent = box
	box.Parent = root
	local icon = Ui.image(box, Config.images.icons.power, UDim2.fromScale(0.2, 0.92), UDim2.fromScale(0.05, 0.04))
	icon.ZIndex = 2
	gainText = Ui.label(box, "+0", UDim2.fromScale(0.66, 0.8), UDim2.fromScale(0.27, 0.1))
	gainText.ZIndex = 2
	;(gainText:FindFirstChildOfClass("UIStroke") :: UIStroke).Thickness = Config.ui.floatingStroke
	gainScale = Instance.new("UIScale")
	gainScale.Parent = root
	if not reducedMotion() then
		TweenService:Create(rays, TweenInfo.new(8, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1), { Rotation = 360 }):Play()
	end
	gainRoot = root
	Screen.register("gain", root)
end

local function showGain(amount: number)
	local GB = Config.ui.gainBanner
	local now = os.clock()
	if now - gainLast > GB.sumSeconds then
		gainSum = 0
	end
	gainSum += amount
	gainLast = now
	gainText.Text = `+{Config.powerText(gainSum)}`
	gainRoot.Visible = true
	if not reducedMotion() then
		gainScale.Scale = GB.pulse
		TweenService:Create(gainScale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end
	gainToken += 1
	local my = gainToken
	task.delay(GB.sumSeconds + GB.holdSeconds, function()
		if gainToken == my then
			gainRoot.Visible = false
		end
	end)
end

-- ---------- the clocks (owner 2026-11-16: Secret every 30 min, an event every 30 min, the night) ----------
-- three small chips bottom right, like the reference's "in 1m 41s": the event now (or the next one), the next
-- Secret, the next night. From the Unix clock (WorldRules), so they agree with the server without messages.
-- owner 2026-11-17 ("not that much timers"): only the soonest clock shows, with a small "+2" badge; hover
-- the clocks (or tap one on a phone) and all of them show.
type Clock = { root: TextButton, text: TextLabel, chip: Frame, icon: ImageLabel, more: TextLabel }
local clocks: { [string]: Clock } = {}
local CLOCK_ORDER = { "event", "secret", "night" }
local clocksOpenUntil = 0 -- os.clock() until which every clock shows
local soonestClock = "night" -- the one clock shown while they're closed

-- owner 2026-11-17: hover opens and closes at once, no delay
local function applyClocks()
	local open = os.clock() < clocksOpenUntil
	for _, k in CLOCK_ORDER do
		local c = clocks[k]
		c.root.Visible = open or k == soonestClock
		c.more.Visible = not open and k == soonestClock
	end
end

local function clockChip(parent: Frame, order: number, color: Color3, icon: string): Clock
	local C = Config.ui.clocks
	local n = 3
	local totalH = C.size[2] * n + C.gap * (n - 1)
	local f = Instance.new("TextButton")
	f.Name = "Clock"
	f.Text = ""
	f.AutoButtonColor = false
	f.LayoutOrder = order
	f.BackgroundColor3 = Theme.alert.back
	f.BackgroundTransparency = 0.15
	f.BorderSizePixel = 0
	f.Size = UDim2.fromScale(1, C.size[2] / totalH)
	Ui.corner(f, 0.5)
	Ui.stroke(f, 2.5)
	local chip = Instance.new("Frame")
	chip.BackgroundColor3 = color
	chip.BorderSizePixel = 0
	chip.Position = UDim2.new(0, 2, 0, 2)
	chip.Size = UDim2.new(1, -4, 1, -4)
	local a = Instance.new("UIAspectRatioConstraint")
	a.AspectRatio = 1
	a.DominantAxis = Enum.DominantAxis.Height
	a.Parent = chip
	Ui.corner(chip, 0.5)
	chip.Parent = f
	local img = Ui.image(chip, Config.images.icons[icon] or Config.images.icons.star, UDim2.fromScale(0.78, 0.78), UDim2.fromScale(0.11, 0.11))
	local t = Ui.label(f, "", UDim2.new(1, 0, 0.66, 0), UDim2.fromScale(0, 0.17))
	t.TextXAlignment = Enum.TextXAlignment.Right
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0.2, 0)
	pad.PaddingRight = UDim.new(0.07, 0)
	pad.Parent = t
	-- "+2": more clocks are tucked away (only on the one shown while they're closed)
	local more = Instance.new("TextLabel")
	more.Name = "More"
	more.AnchorPoint = Vector2.new(1, 0.5)
	more.Position = UDim2.new(0, -4, 0.5, 0) -- just left of the chip, clear of its icon
	more.Size = UDim2.fromScale(0.5, 0.5)
	more.BackgroundColor3 = Theme.info
	more.TextColor3 = Theme.white
	more.Font = Theme.font
	more.TextScaled = true
	more.ZIndex = 3
	more.Visible = false
	local ma = Instance.new("UIAspectRatioConstraint")
	ma.AspectRatio = 1.4
	ma.DominantAxis = Enum.DominantAxis.Height
	ma.Parent = more
	Ui.corner(more, 0.5)
	Ui.stroke(more, 2)
	more.Parent = f
	local function showAll() -- at once, not on the next tick
		for _, c in clocks do
			c.root.Visible = true
			c.more.Visible = false
		end
	end
	f.MouseEnter:Connect(function()
		clocksOpenUntil = math.huge
		showAll()
	end)
	f.MouseLeave:Connect(function()
		clocksOpenUntil = 0
		-- deferred so moving onto the next clock (its MouseEnter fires right after) doesn't flicker
		task.defer(applyClocks)
	end)
	f.Activated:Connect(function() -- a tap on a phone: open for a few seconds, tap again to close
		if clocksOpenUntil == math.huge then
			return -- a mouse is already hovering them open
		end
		clocksOpenUntil = if os.clock() < clocksOpenUntil then 0 else os.clock() + 5
		if clocksOpenUntil > 0 then
			showAll()
		end
		SoundController.play("click")
	end)
	f.Parent = parent
	return { root = f, text = t, chip = chip, icon = img, more = more }
end

local function buildClocks()
	local C = Config.ui.clocks
	local f = Instance.new("Frame")
	f.Name = "Clocks"
	f.BackgroundTransparency = 1
	local l = Instance.new("UIListLayout")
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.VerticalAlignment = Enum.VerticalAlignment.Bottom
	l.HorizontalAlignment = Enum.HorizontalAlignment.Right
	l.Padding = UDim.new(C.gap / (C.size[2] * 3 + C.gap * 2), 0)
	l.Parent = f
	clocks.event = clockChip(f, 1, Theme.events.chill, "ray")
	clocks.secret = clockChip(f, 2, Theme.events.secret, "trophy")
	clocks.night = clockChip(f, 3, Theme.events.night, "star")
	Screen.register("clocks", f)
end

local function tickClocks()
	local now = workspace:GetServerTimeNow()
	local cur, ends, nextE, nextIn = WorldRules.eventAt(now)
	local ev = clocks.event
	local shown = cur or nextE
	ev.chip.BackgroundColor3 = Theme.events[shown.id] or Theme.info
	ev.icon.Image = Config.images.icons[shown.icon] or Config.images.icons.star
	ev.text.Text = if cur then `{cur.name} {Config.timeText(ends - now)}` else `{nextE.name} in {Config.timeText(nextIn)}`
	local secretIn = WorldRules.secretIn(now)
	local out = ((workspace:GetAttribute("SecretsOut") or 0) :: number) > 0 -- the server's own count
	clocks.secret.text.Text = if out then "SECRET IS OUT!" else `Secret in {Config.timeText(secretIn)}`
	local offset = (workspace:GetAttribute("NightOffset") or 0) :: number
	local nightIn = WorldRules.nightIn(now, offset)
	clocks.night.text.Text = if nightIn <= 0 then "Night!" else `Night in {Config.timeText(nightIn)}`
	-- one clock unless open: always the night (owner 2026-11-18: it was the soonest, so an event or the Secret
	-- took its place; those show only on hover / tap now)
	local soonest = "night"
	soonestClock = soonest
	applyClocks()
	local moreText = `+{#CLOCK_ORDER - 1}`
	if clocks[soonest].more.Text ~= moreText then
		clocks[soonest].more.Text = moreText
	end
end

-- gain text appears beside the coin counter, never on a HUD item. It wears the counter's own look
-- (white-to-gold fill, the firm outline) a size smaller, starts just past the number's visible end
-- (owner 2026-11-05: it sat on the last digit in flat yellow), pops in, then drifts up and fades.
-- power = true: the same pop beside the Cold Power number, fading white to its cyan
-- a small green "+" on a currency's icon that opens the Shop on that tab (owner 2026-11-18, the monetization plan:
-- a way in next to every currency, like the hit games' "+" by the cash counter)
local function plusBadge(root: Frame, x: number, y: number, h: number, tab: string)
	local b = Ui.block(root, "Plus", Theme.go, "+", function()
		SoundController.play("click")
		PopupController.open("shop", { tab = tab })
	end)
	b.root.AnchorPoint = Vector2.new(0.5, 0.5)
	b.root.Position = UDim2.fromScale(x, y)
	b.root.Size = UDim2.fromScale(h, h)
	local a = Instance.new("UIAspectRatioConstraint")
	a.DominantAxis = Enum.DominantAxis.Height
	a.Parent = b.root
	b.root.ZIndex = 4
	Ui.roundBlock(b, 0.5)
end

local function floatGain(amount: number, power: boolean?)
	local G = Config.ui.gain
	local root, number = if power then powerRoot else coinsRoot, if power then powerText else coinsText
	local w = math.max(1, root.AbsoluteSize.X)
	local x = number.Position.X.Scale + number.TextBounds.X / w + G.gap
	local t = Ui.label(root, `+{if power then Config.powerText(amount) else Ui.short(amount)}`, UDim2.fromScale(G.width, if power then G.height * 1.4 else G.height), UDim2.fromScale(x, G.y))
	t.Name = "Gain"
	t.TextXAlignment = Enum.TextXAlignment.Left
	local stroke = t:FindFirstChildOfClass("UIStroke") :: UIStroke
	stroke.Thickness = Config.ui.floatingStroke
	local gold = Instance.new("UIGradient")
	gold.Rotation = 90
	gold.Color = ColorSequence.new(Theme.white, if power then Theme.training.power else Theme.coin)
	gold.Parent = t
	local pop = Instance.new("UIScale")
	pop.Scale = 0.4
	pop.Parent = t
	local still = SettingsController.get("reducedMotion") == true
	TweenService:Create(pop, TweenInfo.new(G.popSeconds, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	local fade = TweenInfo.new(Config.ui.floatSeconds - G.holdSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, G.holdSeconds)
	TweenService:Create(t, fade, { Position = UDim2.fromScale(x, G.y - (if still then 0 else G.rise)), TextTransparency = 1 }):Play()
	TweenService:Create(stroke, fade, { Transparency = 1 }):Play()
	task.delay(Config.ui.floatSeconds, function()
		t:Destroy()
	end)
end

local tilesFrame: Frame
local testerTile: Ui.Block? = nil

-- the "T" tile: only made once the server says this account is a tester
local function ensureTesterTile()
	if testerTile then
		return
	end
	local t = Config.ui.testerTile
	local b = Ui.block(tilesFrame, t.id, Theme.tiers.Common, "T", function() -- quiet grey: a tool for testers, not a game menu
		PopupController.open(t.id)
	end)
	b.root.LayoutOrder = #Config.ui.tiles + 1
	b.text.Size = UDim2.fromScale(0.8, 0.62)
	b.text.Position = UDim2.fromScale(0.1, 0.04)
	local small = Ui.label(b.face, t.label, UDim2.fromScale(0.9, 0.26), UDim2.fromScale(0.05, 0.7))
	small.Name = "Label"
	testerTile = b
	Screen.setTileCount(#Config.ui.tiles + 1)
end

-- the coin counter: the whole number up to 999,999 (owner 2026-11-03), then short with two decimals,
-- 1.50M / 123.45M / 2.07B (owner 2026-11-13: the long whole number got hard to read past a million).
-- Rounds down, so it never shows more than you have.
local function counterText(n: number): string
	n = math.max(0, math.floor(n))
	if n < Config.ui.coinsShortFrom then
		return Ui.commas(n)
	end
	for _, u in Config.coinUnits do
		if n >= u.size then
			return string.format("%.2f", math.floor(n / u.size * 100 + 1e-9) / 100) .. u.suffix
		end
	end
	return Ui.commas(n)
end

-- the +N/s rate sits right of the number, centred on it (the number is centred on the coin now)
local function placeRate()
	local w = math.max(1, coinsRoot.AbsoluteSize.X)
	local x = coinsText.Position.X.Scale + coinsText.TextBounds.X / w + Config.ui.coinsRateGap
	coinsRate.Position = UDim2.fromScale(x, coinsRate.Position.Y.Scale)
end

local function render(v: State.View)
	if v.tester then
		ensureTesterTile()
	end
	coinsText.Text = counterText(v.coins)
	-- the friend bonus rides on the income line (no new HUD item): "+120/s  +20% friends"
	local f = v.friends or 0
	local friendsText = if f > 0
		then `  <font color="#{Theme.tiles.daily:ToHex()}">+{math.round(f * Config.friends.perFriend * 100)}% friends</font>`
		else ""
	-- Coin Rush and other coin events pay more than v.income: show what you really get (QA 2026-11-23 PT-10)
	local ev = (v :: any).coinEvent or 1
	local eventText = if ev > 1 then `  <font color="#{Theme.coin:ToHex()}">x{ev}</font>` else ""
	coinsRate.Text = if v.income > 0 then `+{Ui.short(v.income * ev)}/s{eventText}{friendsText}` else ""
	coinsRate.Visible = v.income > 0
	-- Cold Power: the number, a "+N" beside it and a small bounce when it goes up (not on the first sync)
	local power = v.coldPower or 0
	powerText.Text = Config.powerText(power) -- the total (the % to the next island is under the top buttons)
	if lastPower and power > lastPower then
		floatGain(power - lastPower, true)
		-- (the big "+N" Cold Power box at the top, showGain, is gone: owner 2026-11-18 "remove this thing from the trainer")
		if SettingsController.get("reducedMotion") ~= true then
			local P = Config.ui.powerPop
			powerScale.Scale = P.scale
			TweenService:Create(powerScale, TweenInfo.new(P.seconds, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		end
	end
	lastPower = power
	if dailyDot then
		local ready = false
		for _, c in (if v.daily then v.daily.list else {}) do
			ready = ready or (c.done and not c.claimed)
		end
		dailyDot.Visible = ready
	end
end

-- the island banner (Config.ui.islandBanner, owner's reference clip 2026-11-07): Screen places the
-- slot; only the strip inside it moves. Name row: the island's name in its colour, the thermometer,
-- its feel + degrees in the heat colour. Info row: "Recommended:", the ray icon, the gun that can
-- freeze its pets.
local IB = Config.ui.islandBanner
local islandSlot: Frame
local strip: CanvasGroup
local nameRow: Frame
local infoRow: Frame
local nameText: TextLabel
local feelText: TextLabel
local recLabel: TextLabel
local gunText: TextLabel
local gunBox: Frame -- the recommended gun's own model (owner 2026-11-17: not the generic ray icon); holds Gun1..GunN
local gunShown = 0
local islandToken = 0
local islandShowing = false
local lastZone = -1 -- -1 = not checked yet, 0 = the hub
local lastShown: { [number]: number } = {}
local gatePromptUp = false -- a gate's Open prompt is on screen: the banner steps aside (QA IR-07, it covered it on phones)

local function row(y: number, h: number): Frame
	local f = Instance.new("Frame")
	f.BackgroundTransparency = 1
	f.Size = UDim2.fromScale(1, h)
	f.Position = UDim2.fromScale(0, y)
	local l = Instance.new("UIListLayout")
	l.FillDirection = Enum.FillDirection.Horizontal
	l.HorizontalAlignment = Enum.HorizontalAlignment.Center
	l.VerticalAlignment = Enum.VerticalAlignment.Center
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.Padding = UDim.new(0.01, 0)
	l.Parent = f
	f.Parent = strip
	return f
end

-- a word in a row: as wide as its text, so the row centres what you see (UI Rules: optical centring)
local function rowText(parent: Frame, order: number, color: Color3): TextLabel
	local t = Ui.label(parent, "", UDim2.fromScale(0, 1))
	t.TextScaled = false
	t.AutomaticSize = Enum.AutomaticSize.X
	t.LayoutOrder = order
	t.TextColor3 = color
	local s = t:FindFirstChildOfClass("UIStroke") :: UIStroke
	s.Thickness = IB.textStroke -- no block behind it: the firm outline, like the coin counter
	return t
end

local function rowIcon(parent: Frame, order: number, image: string)
	local i = Instance.new("ImageLabel")
	i.Name = "Icon"
	i.BackgroundTransparency = 1
	i.Image = image
	i.ScaleType = Enum.ScaleType.Fit
	i.Size = UDim2.fromScale(1, IB.iconSize)
	i.LayoutOrder = order
	local a = Instance.new("UIAspectRatioConstraint")
	a.AspectRatio = 1
	a.DominantAxis = Enum.DominantAxis.Height
	a.Parent = i
	i.Parent = parent
end

-- one text size per row, from the row's height (TextScaled made each word a different size)
local function sizeText()
	local nh, ih = nameRow.AbsoluteSize.Y, infoRow.AbsoluteSize.Y
	nameText.TextSize = math.min(100, math.floor(nh * 0.92))
	feelText.TextSize = math.min(100, math.floor(nh * 0.62))
	recLabel.TextSize = math.min(100, math.floor(ih * 0.55)) -- the row is tall for the gun card; the words stay their old size
	gunText.TextSize = recLabel.TextSize
end

local function buildIsland()
	islandSlot = Instance.new("Frame")
	islandSlot.Name = "IslandBanner"
	islandSlot.BackgroundTransparency = 1
	islandSlot.Visible = false
	strip = Instance.new("CanvasGroup") -- fades everything in it together
	strip.Name = "Strip"
	strip.BackgroundTransparency = 1
	strip.Size = UDim2.fromScale(1, 1)
	strip.Parent = islandSlot
	-- the dark see-through strip with soft ends (a gradient on a plain Frame, no tiled image)
	local back = Instance.new("Frame")
	back.Name = "Back"
	back.BorderSizePixel = 0
	back.BackgroundColor3 = Theme.islandStrip
	back.Size = UDim2.fromScale(1, 1)
	local fade = Instance.new("UIGradient")
	local a, e = IB.stripTransparency, IB.stripEnds
	fade.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(e, a),
		NumberSequenceKeypoint.new(1 - e, a), NumberSequenceKeypoint.new(1, 1),
	})
	fade.Parent = back
	back.Parent = strip
	local gap = (1 - IB.nameRow - IB.infoRow) / 3
	nameRow = row(gap, IB.nameRow)
	infoRow = row(gap * 2 + IB.nameRow, IB.infoRow)
	nameText = rowText(nameRow, 1, Theme.white)
	rowIcon(nameRow, 2, Config.images.icons.temp)
	feelText = rowText(nameRow, 3, Theme.white)
	recLabel = rowText(infoRow, 1, Theme.white)
	recLabel.Text = "Recommended:"
	-- the gun itself, no box behind it (owner 2026-11-17: like the icon before, but each island's own gun)
	gunBox = Instance.new("Frame")
	gunBox.Name = "Gun"
	gunBox.BackgroundTransparency = 1
	gunBox.Size = UDim2.fromScale(1, IB.gunCard)
	gunBox.LayoutOrder = 2
	local ga = Instance.new("UIAspectRatioConstraint")
	ga.AspectRatio = IB.gunAspect -- guns are long
	ga.DominantAxis = Enum.DominantAxis.Height
	ga.Parent = gunBox
	gunBox.Parent = infoRow
	-- every gun's window is built now and only switched on when its island shows, and their meshes are
	-- fetched up front: built on show, the gun popped in a moment after the banner (owner 2026-11-17)
	for i in Config.guns.list do
		local vp = EquipmentPopup.gunView(gunBox, i, false, false, nil, true, true)
		vp.Name = `Gun{i}`
		vp.AnchorPoint = Vector2.new(0.5, 0.5)
		vp.Position = UDim2.fromScale(0.5, 0.5)
		vp.Size = UDim2.fromScale(IB.gunZoom, IB.gunZoom) -- see-through edges past the slot: the gun fills it
		vp.Visible = false
	end
	local models = ReplicatedStorage:FindFirstChild("GunModels")
	if models then
		task.spawn(function()
			pcall(function()
				ContentProvider:PreloadAsync({ models })
			end)
		end)
	end
	gunText = rowText(infoRow, 3, Theme.islandValue)
	nameRow:GetPropertyChangedSignal("AbsoluteSize"):Connect(sizeText)
	Screen.register("island", islandSlot)
	sizeText()
end

local function reduced(): boolean
	return SettingsController.get("reducedMotion") == true
end

local function hideIsland(quick: boolean?)
	if not islandShowing then
		return
	end
	islandShowing = false
	islandToken += 1
	local my = islandToken
	local t = IB.outSeconds * (if reduced() then 0.5 else 1) * (if quick then 0.5 else 1)
	local info = TweenInfo.new(t, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	TweenService:Create(strip, info, {
		GroupTransparency = 1,
		Position = UDim2.fromScale(0, if reduced() then 0 else -IB.rise),
	}):Play()
	task.delay(t, function()
		if islandToken == my then
			islandSlot.Visible = false
		end
	end)
end

-- this island's own gun (owner 2026-11-17: each island its specific gun): gun N belongs to island N, as
-- in the pacing ("guns follow their islands", PACING-2026-11-16.md); islands past the last gun get the last
local function gunFor(id: number): number
	return math.clamp(id, 1, #Config.guns.list)
end

local function showIsland(zone: Config.Zone)
	local unit = SettingsController.get("unit")
	local deg = WorldRules.zoneTemperature(zone.id)
	local shown = if unit == "F" then WorldRules.toFahrenheit(deg) else deg
	local band = "hot"
	for _, b in Config.temperature.bands do
		if deg < b.below then
			band = b.name
			break
		end
	end
	nameText.Text = zone.name
	nameText.TextColor3 = Theme.islandTitle[zone.theme] or Theme.white
	feelText.Text = `{zone.feel} {shown}°{unit}`
	feelText.TextColor3 = Theme.temp[band] or Theme.white
	local gi = gunFor(zone.id)
	gunText.Text = Config.guns.list[gi].name
	if gunShown ~= gi then
		local was = gunBox:FindFirstChild(`Gun{gunShown}`) :: GuiObject?
		if was then
			was.Visible = false
		end
		gunShown = gi
		local now = gunBox:FindFirstChild(`Gun{gi}`) :: GuiObject?
		if now then
			now.Visible = true
		end
	end
	sizeText()
	islandToken += 1
	local my = islandToken
	islandShowing = true
	islandSlot.Visible = true
	local still = reduced()
	local inT = IB.inSeconds * (if still then 0.5 else 1)
	if still then
		-- reduced motion: no slide, a soft fade in place
		strip.Position = UDim2.fromScale(0, 0)
		strip.GroupTransparency = 1
		TweenService:Create(strip, TweenInfo.new(inT, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { GroupTransparency = 0 }):Play()
	else
		-- fast in, soft out: drops from above the top edge, overshoots a little and settles (Back Out)
		strip.Position = UDim2.fromScale(0, -IB.drop)
		strip.GroupTransparency = 0
		TweenService:Create(strip, TweenInfo.new(inT, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = UDim2.fromScale(0, 0) }):Play()
	end
	SoundController.play("island")
	task.delay(inT + IB.holdSeconds * (if still then 0.5 else 1), function()
		if islandToken == my then
			hideIsland()
		end
	end)
end

-- walked onto another island? Waits while a popup is open, so the two never meet.
local function watchIsland()
	local c = Players.LocalPlayer.Character
	local root = c and c:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	if PopupController.isOpen() or gatePromptUp then
		hideIsland(true)
		return
	end
	local id = WorldRules.zoneAt(root.Position)
	if id == lastZone then
		return
	end
	lastZone = id
	-- owner 2026-11-21: no island banner (name, degrees, Recommended gun) during the tutorial, it looked weird
	local tu = State.view and (State.view :: any).tutorial
	if tu and not tu.done then
		return
	end
	local zone = if id > 0 then Config.zone(id) else nil
	local reach = if State.view then State.view.reach or 1 else 1
	if not zone or not zone.ready or id > reach then
		return -- the hub, or a closed island the gate guard is about to put you back from
	end
	local now = os.clock()
	if now - (lastShown[id] or -math.huge) < IB.repeatAfter then
		return
	end
	lastShown[id] = now
	showIsland(zone)
end

function HudController.Init() end

function HudController.Start()
	-- owner 2026-11-18 ("maybe there should be some alert that the thaw machine has finished"): when a pet in one of
	-- your Thaw Machines is done, a green banner and a chime, wherever you are. Each pet once a session; several at
	-- once make one banner.
	task.spawn(function()
		local told: { [string]: boolean } = {}
		while true do
			task.wait(0.5)
			local v = State.view
			if v and not (v.tutorial and not v.tutorial.done) then -- QA 2026-11-23 (PT-13): the tutorial claims it for you
				local now = workspace:GetServerTimeNow()
				local fresh: { string } = {}
				for _, p in v.pets do
					if p.thawM and p.thawAt and p.thawAt <= now and not told[p.id] then
						told[p.id] = true
						local def = PetDefs.get(p.key)
						table.insert(fresh, if def then def.name else "pet")
					end
				end
				if #fresh == 1 then
					HudController.banner(`Your {fresh[1]} is thawed! Claim it at your Thaw Machine`, Theme.go, 4, "star", true)
					SoundController.play("unlock")
				elseif #fresh > 1 then
					HudController.banner(`{#fresh} pets are thawed! Claim them at your Thaw Machines`, Theme.go, 4, "star", true)
					SoundController.play("unlock")
				end
			end
		end
	end)
	-- tiles
	local tiles = Instance.new("Frame")
	tiles.Name = "Tiles"
	tiles.BackgroundTransparency = 1 -- Screen places each tile (the Wide one spans the top row)
	tilesFrame = tiles
	for i, t in Config.ui.tiles do
		local b = Ui.block(tiles, t.id, Theme.tiles[t.id] or Theme.info, t.label, function()
			if t.id == "trade" then
				-- the players panel (trade, mute, block); required here so the two controllers don't load each other
				require(script.Parent.ExtrasController).openPlayers()
				return
			end
			PopupController.open(t.id)
		end)
		b.root.LayoutOrder = i
		-- the painted icon on top, the name small underneath (prototype tiles)
		local icon = Config.ui.tileIcons[t.id]
		if icon and t.id == Config.ui.wideTile then
			-- owner 2026-11-15: the Shop takes a whole row on top (two slots): the basket on the left, a big
			-- SHOP on the right, and the basket bobs gently (the one animated tile: the money screen is a focal point)
			b.root.LayoutOrder = 0
			b.root:SetAttribute("Wide", true)
			local img = Ui.image(b.face, icon, UDim2.fromScale(0.44, 1.12), UDim2.fromScale(0.0, -0.1))
			img.ZIndex = 1
			-- smaller than before (owner 2026-11-16: the big SHOP didn't match the other tiles' names)
			local WT = Config.ui.wideTileText
			b.text.Text = t.label -- owner 2026-11-17: "Shop", not "SHOP", like the other tile names
			b.text.Size = UDim2.fromScale(WT[1], WT[2])
			b.text.Position = UDim2.fromScale(WT[3], WT[4])
			b.text.ZIndex = 2
			local ts = b.text:FindFirstChildOfClass("UIStroke") :: UIStroke
			ts.Thickness = Config.ui.floatingStroke
			if SettingsController.get("reducedMotion") ~= true then
				local W = Config.ui.wideTileWiggle
				TweenService:Create(img, TweenInfo.new(W.seconds, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Rotation = W.degrees }):Play()
				img.Rotation = -W.degrees
			end
		elseif icon then
			-- a big centred icon filling the tile, the name sitting on the tile's bottom edge in a bold
			-- outline (simulator-style menu tiles; owner 2026-10-31)
			local img = Ui.image(b.face, icon, UDim2.fromScale(0.92, 0.8), UDim2.fromScale(0.04, 0))
			img.ZIndex = 1
			b.text.Size = UDim2.fromScale(1.12, 0.34)
			b.text.Position = UDim2.fromScale(-0.06, 0.74)
			b.text.ZIndex = 2
			local ts = b.text:FindFirstChildOfClass("UIStroke") :: UIStroke
			ts.Thickness = Config.ui.floatingStroke
		end
		if t.id == "daily" then
			-- "something to claim": a red dot with an ink outline on the tile's top-right corner (a shape, not an emoji)
			local dot = Instance.new("Frame")
			dot.Name = "Ready"
			dot.AnchorPoint = Vector2.new(0.5, 0.5)
			dot.Position = UDim2.fromScale(0.92, 0.08)
			dot.Size = UDim2.fromScale(0.28, 0.28)
			dot.BackgroundColor3 = Theme.no
			dot.ZIndex = 5
			dot.Visible = false
			local a = Instance.new("UIAspectRatioConstraint")
			a.Parent = dot
			Ui.corner(dot, 0.5)
			Ui.stroke(dot)
			dot.Parent = b.root
			dailyDot = dot
		end
	end
	Screen.register("tiles", tiles, #Config.ui.tiles)
	-- coins: the coin image, the number, and +N/s under it
	-- coins: the coin and the number straight on the screen, no box behind them (owner 2026-10-31)
	coinsRoot = Instance.new("Frame")
	coinsRoot.Name = "Coins"
	coinsRoot.BackgroundTransparency = 1
	Ui.image(coinsRoot, Config.images.icons.coin, UDim2.fromScale(0.34, 1), UDim2.fromScale(0, 0))
	-- wider than the frame (it runs on to the right) so a long whole number keeps a big font. Owner
	-- 2026-11-13: centred on the coin and as big as the Cold Power number under it (same size and place)
	-- the number starts at 0.4: the "+" sits on the coin's bottom-right corner, clear of the number (owner
	-- 2026-11-20: first it sat on both, then it floated in a gap between them and looked detached)
	coinsText = Ui.label(coinsRoot, "0", UDim2.fromScale(1.4, 0.84), UDim2.fromScale(0.4, 0.08))
	coinsText.TextXAlignment = Enum.TextXAlignment.Left
	-- wide enough for "+1.2K/s  +30% friends"; a short rate keeps its size (TextScaled caps at the height)
	coinsRate = Ui.label(coinsRoot, "", UDim2.fromScale(1.6, 0.4), UDim2.fromScale(0.6, 0.32))
	coinsRate.TextXAlignment = Enum.TextXAlignment.Left
	coinsRate.RichText = true
	coinsRate.TextColor3 = Theme.go -- income reads as "go/gain" green
	local gold = Instance.new("UIGradient") -- the number fades white to gold, like the coin
	gold.Rotation = 90
	gold.Color = ColorSequence.new(Theme.white, Theme.coin)
	gold.Parent = coinsText
	for _, t in { coinsText, coinsRate } do
		local s = t:FindFirstChildOfClass("UIStroke") :: UIStroke
		s.Thickness = Config.ui.floatingStroke -- nothing behind it now, so a firmer outline reads over snow
	end
	coinsText:GetPropertyChangedSignal("TextBounds"):Connect(placeRate)
	coinsRoot:GetPropertyChangedSignal("AbsoluteSize"):Connect(placeRate)
	Screen.register("coins", coinsRoot)
	plusBadge(coinsRoot, 0.3, 0.8, 0.36, "coins") -- smaller than the icon (owner 2026-11-18: "too big"); on the coin's corner, 2026-11-20
	-- Cold Power under the coins, the same look a size smaller: icon, then the number in white-to-cyan
	powerRoot = Instance.new("Frame")
	powerRoot.Name = "Power"
	powerRoot.BackgroundTransparency = 1
	-- the Cold Power icon and the total in big white-to-cyan (as before), and under the number a slim bar: how far
	-- your Cold Power is toward the next island's need, "62% to Jungle Falls" (owner 2026-11-18)
	Ui.image(powerRoot, Config.images.icons.power, UDim2.fromScale(0.26, 0.96), UDim2.fromScale(0.04, 0.02))
	plusBadge(powerRoot, 0.3, 0.8, 0.36, "power")
	powerText = Ui.label(powerRoot, "0", UDim2.fromScale(1.4, 0.84), UDim2.fromScale(0.4, 0.08))
	powerText.TextXAlignment = Enum.TextXAlignment.Left
	local cyan = Instance.new("UIGradient")
	cyan.Rotation = 90
	cyan.Color = ColorSequence.new(Theme.white, Theme.training.power)
	cyan.Parent = powerText
	local ps = powerText:FindFirstChildOfClass("UIStroke") :: UIStroke
	ps.Thickness = Config.ui.floatingStroke
	-- (the "% to the next island" bar moved under EQUIPMENT and PAN: TopButtons, owner 2026-11-18)
	powerScale = Instance.new("UIScale")
	powerScale.Parent = powerText
	Screen.register("power", powerRoot)
	buildIsland()
	-- alerts: a transparent stack the toasts slide into (Screen places it under the top buttons)
	local af = Instance.new("Frame")
	af.Name = "Alerts"
	af.BackgroundTransparency = 1
	local al = Instance.new("UIListLayout")
	al.SortOrder = Enum.SortOrder.LayoutOrder
	al.HorizontalAlignment = Enum.HorizontalAlignment.Center
	local A = Config.ui.alerts
	al.Padding = UDim.new(A.gap / (A.stack * A.size[2] + (A.stack - 1) * A.gap), 0)
	al.Parent = af
	alertsFrame = af
	Screen.register("banner", af)
	-- QA 2026-11-20: on a PC the toasts sat on top of an open popup's title bar. While a menu is open they
	-- wait out of sight (rewards keep their time, see banner), like on touch screens
	task.spawn(function()
		while true do
			local want = not Screen.popupOpen
			if af.Visible ~= want then
				af.Visible = want
			end
			task.wait(0.1)
		end
	end)
	buildGain()
	buildClocks()
	task.spawn(function()
		while true do
			local ok, err = pcall(tickClocks)
			if not ok then
				warn("[HudController] clocks:", err)
			end
			task.wait(0.5)
		end
	end)

	State.Changed:Connect(render)
	if State.view then
		render(State.view)
	end
	-- server-wide news a new player can't act on yet: held back until the tutorial is done (QA PT-06)
	local worldShout = { secretSpawned = true, bigWin = true, shoutout = true, eventWarn = true, eventStart = true,
		eventEnd = true, chillWarn = true, adminAbuse = true }
	State.Notify:Connect(function(kind: string, data: any)
		if worldShout[kind] and tutorialOn() then
			return
		end
		if kind == "notYet" then
			HudController.banner(tostring(data.reason), Theme.no, Config.ui.notYetSeconds)
		elseif kind == "chillWarn" then
			HudController.banner(`Big Chill in {data.inSeconds} s!`, Theme.info)
		elseif kind == "eventWarn" then
			HudController.banner(`{data.name} in {data.inSeconds}s!`, Theme.events[data.id] or Theme.info, 4, nil, true)
		elseif kind == "eventStart" then
			HudController.banner(`{data.name}! {data.line}`, Theme.events[data.id] or Theme.info, 6, nil, true)
			SoundController.play("unlock")
		elseif kind == "eventEnd" then
			HudController.banner("The event is over. Next one soon!", Theme.info)
		elseif kind == "adminAbuse" and typeof(data) == "table" and typeof(data.text) == "string" then
			-- admin abuse (AdminService, 2026-11-18): a preset line from the server, in the event's colour
			local secs = if typeof(data.seconds) == "number" then math.clamp(data.seconds, 3, 15) else 7
			-- no pulse (owner 2026-11-18: "dont make it pulsate")
			HudController.banner(data.text, Theme.events[data.color] or Theme.events.secret, secs, "star", false)
			SoundController.play("unlock")
		elseif kind == "adminChat" and typeof(data) == "table" and typeof(data.name) == "string" and typeof(data.text) == "string" then
			-- the admin's message as a chat line, like the big pet games: a bold red name with the verified badge,
			-- then the (server-filtered) text. Escaped so the text can't add its own rich-text tags.
			local function esc(s: string): string
				return (s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;"):gsub("'", "&apos;"))
			end
			-- the badge right against the name (owner 2026-11-18: "move the verified thing closer, it's off-centered"):
			-- no space, and drawn in Roblox's own font, which has the badge glyph sitting on the text's middle
			local line = `<font color="#FF3B3B"><b>{esc(data.name)}</b></font><font color="#3B9BFF" face="BuilderSans">\u{E000}</font>: <b>{esc(data.text)}</b>`
			-- on screen too, like Grow a Garden (owner 2026-11-18: "the alert is not it"): no panel, just the line in
			-- big white outlined text near the top, red name and badge, fading out after a while
			local pg = game:GetService("Players").LocalPlayer:FindFirstChildOfClass("PlayerGui")
			if pg then
				local gui = pg:FindFirstChild("AdminLines") :: ScreenGui?
				if not gui then
					local g = Instance.new("ScreenGui")
					g.Name = "AdminLines"
					g.ResetOnSpawn = false
					g.DisplayOrder = 50
					g.IgnoreGuiInset = true
					local holder = Instance.new("Frame")
					holder.Name = "Lines"
					holder.BackgroundTransparency = 1
					holder.AnchorPoint = Vector2.new(0.5, 0)
					holder.Position = UDim2.fromScale(0.5, 0.15)
					holder.Size = UDim2.fromScale(0.8, 0.3)
					local list = Instance.new("UIListLayout")
					list.SortOrder = Enum.SortOrder.LayoutOrder
					list.HorizontalAlignment = Enum.HorizontalAlignment.Center
					list.Padding = UDim.new(0, 4)
					list.Parent = holder
					holder.Parent = g
					g.Parent = pg
					gui = g
				end
				local holder = (gui :: ScreenGui):FindFirstChild("Lines") :: Frame
				local n = 0
				for _, c in holder:GetChildren() do
					if c:IsA("TextLabel") then
						n += 1
					end
				end
				if n >= 3 then -- at most three lines: the oldest goes
					local oldest: TextLabel? = nil
					for _, c in holder:GetChildren() do
						if c:IsA("TextLabel") and (not oldest or c.LayoutOrder < oldest.LayoutOrder) then
							oldest = c
						end
					end
					if oldest then
						oldest:Destroy()
					end
				end
				local cam = workspace.CurrentCamera
				local screenH = if cam then cam.ViewportSize.Y else 720
				local lab = Instance.new("TextLabel")
				lab.Name = "AdminLine"
				lab.LayoutOrder = math.floor(os.clock() * 100)
				lab.BackgroundTransparency = 1
				lab.Size = UDim2.new(1, 0, 0, 0)
				lab.AutomaticSize = Enum.AutomaticSize.Y
				lab.Font = Theme.font
				lab.TextSize = math.clamp(math.floor(screenH * 0.04), 20, 40)
				lab.TextWrapped = true
				lab.RichText = true
				lab.TextColor3 = Color3.new(1, 1, 1)
				lab.Text = `<font color="#FF3B3B">{esc(data.name)}</font><font color="#3B9BFF" face="BuilderSans" weight="bold">\u{E000}</font>: {esc(data.text)}`
				local stroke = Instance.new("UIStroke")
				stroke.Thickness = math.max(2, math.floor(lab.TextSize / 12))
				stroke.Color = Color3.new(0, 0, 0)
				stroke.Parent = lab
				lab.Parent = holder
				SoundController.play("unlock")
				local secs = if typeof(data.seconds) == "number" then math.clamp(data.seconds, 3, 20) else 10
				task.delay(secs, function()
					if lab.Parent then
						local ti = TweenInfo.new(0.6)
						game:GetService("TweenService"):Create(lab, ti, { TextTransparency = 1 }):Play()
						game:GetService("TweenService"):Create(stroke, ti, { Transparency = 1 }):Play()
						task.delay(0.7, function()
							lab:Destroy()
						end)
					end
				end)
			end
			pcall(function()
				local channels = game:GetService("TextChatService"):FindFirstChild("TextChannels")
				local sys = channels and channels:FindFirstChild("RBXSystem")
				if sys and sys:IsA("TextChannel") then
					sys:DisplaySystemMessage(line)
				end
			end)
		elseif kind == "secretSpawned" then
			-- the server-wide alert (owner 2026-11-16): one Secret on the whole map, and where it is
			local where = if typeof(data.islands) == "table" and typeof(data.islands[1]) == "string" then data.islands[1] else "an island"
			-- an island you can't reach yet: don't send a new player off toward it (QA IR-15)
			local reach = if State.view then State.view.reach or 1 else 1
			local far = false
			for _, z in Config.world.zones do
				if z.name == where and z.id > reach then
					far = true
				end
			end
			if far then
				HudController.banner(`A SECRET pet is on {where}! Keep opening islands`, Theme.events.secret, 5, "trophy")
			else
				HudController.banner(`A SECRET pet appeared on {where}!`, Theme.events.secret, 8, "trophy", true)
			end
			SoundController.play("unlock")
		elseif kind == "nightWarn" then
			-- world news waits for the tutorial (UI Rules; QA 2026-11-20 saw it under "Use the Thaw Machine")
			if not tutorialOn() then
				HudController.banner(`Night in {data.inSeconds}s! The islands close`, Theme.events.night, 4, "star")
			end
		elseif kind == "nightHome" then
			local lost = typeof(data) == "table" and typeof(data.lost) == "number" and data.lost > 0
			HudController.banner(if lost then "Night! Your pet got away. Get home before dark" else "Night! Back home until sunrise", Theme.events.night, 4, "star")
		elseif kind == "chillStart" and data.quiet then
			-- the Big Chill as a server event: eventStart already says it
		elseif kind == "chillStart" then
			if typeof(data.by) == "string" then
				HudController.banner(`{data.by} started a Big Chill for everyone!`, Theme.info, data.seconds)
			else
				HudController.banner("Big Chill! Nothing melts", Theme.info, data.seconds)
			end
		elseif kind == "nightStart" then
			-- the Night Reset (Config.night), the closed islands (Config.nightClose) and the night thaw boost
			-- owner 2026-11-20: "stop saying this alert" (the night clock already shows it); no banner
		elseif kind == "nightEnd" then
			local tv = State.view -- QA 2026-11-23 (PT-12): not over the tutorial pill
			if not (tv and tv.tutorial and not tv.tutorial.done) then
				HudController.banner("Good morning! New pets are here", Theme.go)
			end
		elseif kind == "bigWin" then
			-- only other players' big wins (owner 2026-11-13: no alert for your own Epic and up)
			local def = PetDefs.get(data.key)
			if def and data.userId ~= Players.LocalPlayer.UserId then
				HudController.banner(`{data.name} caught a {string.upper(def.tier)} {def.name}!`, Theme.tiers[def.tier])
			end
		elseif kind == "shoutout" then
			-- a Secret was frozen somewhere on the server (the freezer sees their own show instead)
			local def = PetDefs.get(data.key)
			if def and data.userId ~= Players.LocalPlayer.UserId then
				HudController.banner(`{data.name} froze a {string.upper(def.tier)} {def.name}!`, Theme.tierGlow[def.tier] or Theme.coin)
			end
		elseif kind == "banked" then
			-- no banner at all when banking (owner 2026-11-07: no income text; 2026-11-13: no "EPIC! name" alert either)
			-- no green "Put it in your Thaw Machine!" banner: the guide arrow already points there (owner 2026-11-10)
		elseif kind == "zoneUnlocked" then
			local z = Config.zone(if typeof(data.zone) == "number" then data.zone else 2)
			HudController.banner(`{if z then z.name else "The next island"} is open!`, Theme.go)
		elseif kind == "refund" and typeof(data) == "table" and typeof(data.coins) == "number" then
			-- a removed upgrade (the pan's Cold Level 2026-11-10, Speed 2026-11-15): what you spent on it is back
			HudController.banner(`Upgrades changed! +{Ui.commas(data.coins)} coins back`, Theme.coin, Config.ui.bannerSeconds * 2)
		elseif kind == "comingSoon" then
			HudController.banner(`{tostring(data.label)}: coming soon!`, Theme.info)
		elseif kind == "upgraded" then
			local u = Config.upgrades[data.id]
			HudController.banner(`{u and u.name or "Upgrade"} level {data.level}!`, Theme.go)
		elseif kind == "welcomeCollected" or kind == "giftClaimed" then
			floatGain(data.coins)
		elseif kind == "melted" then
			HudController.banner("It melted! Zap it again", Theme.info, 3.5, "ray", true)
		elseif kind == "chargeSaved" then
			HudController.banner("Super Freeze saved for next time", Theme.info)
		elseif kind == "skipKept" then
			HudController.banner("Your pet was already out! Skip saved for next time", Theme.info)
		elseif kind == "skipAllKept" then
			HudController.banner("Your pets were already out! Unfreeze all saved for next time", Theme.info)
		elseif kind == "robuxBought" then
			-- a Robux shop item arrived (saved first, MonetizationService)
			if data.chill then
				-- nothing here: the server-wide "<name> started a Big Chill for everyone!" is the thank-you
			elseif (data.coins or 0) > 0 then
				HudController.banner(`{data.name}! +{Ui.short(data.coins)} coins`, Theme.coin)
				floatGain(data.coins)
			elseif (data.power or 0) > 0 then
				HudController.banner(`{data.name}! +{Config.powerText(data.power)} Cold Power`, Theme.training.power)
			elseif (data.charges or 0) > 0 then
				HudController.banner(`+{data.charges} Super Freezes!`, Theme.go)
			else
				HudController.banner(`{tostring(data.name)} is yours!`, Theme.go)
			end
		-- Round 5
		elseif kind == "codeResult" then
			if data.ok then
				HudController.banner(`{data.text} +{Ui.short(data.coins or 0)}`, Theme.coin)
				floatGain(data.coins or 0)
			else
				HudController.banner(tostring(data.text), Theme.no, Config.ui.notYetSeconds)
			end
		elseif kind == "gearBought" then
			if typeof(data) == "table" and typeof(data.name) == "string" then
				-- an always-on gear's new level (Config.gear, 2026-11-17)
				local lv = if typeof(data.level) == "number" then data.level else 1
				HudController.banner(`{data.name} Lv {lv}! {Config.gearText(data.key, lv)}`, Theme.go)
			else
				HudController.banner("Slow Gel is on your hotbar!", Theme.go)
			end
		-- no banner when a pet goes into or comes out of the Thaw Machine (owner 2026-11-10)
		elseif kind == "critterCaught" then
			HudController.banner("A Heat Critter grabbed your cube! Zap it back", Theme.round5.critter)
		-- PvP (2026-11-19): a hit drops the cube for anyone to grab
		elseif kind == "tagged" then
			HudController.banner(`{data.by} froze you! Grab your pet back!`, Theme.round5.reticlePlayer)
		elseif kind == "tagHit" then
			HudController.banner("Hit! Grab their pet!", Theme.round5.reticlePlayer)
		elseif kind == "bombFrozen" then
			HudController.banner("Frost Bomb! Tap fast to break free!", Theme.round5.reticlePlayer)
		elseif kind == "bombHit" then
			HudController.banner(`Your Frost Bomb froze {data.name}! Grab the pet!`, Theme.go)
		elseif kind == "cubeStolen" then
			HudController.banner(`{data.by} took your pet! Zap them to get it back`, Theme.round5.reticlePlayer)
		elseif kind == "gotBack" then
			HudController.banner("Got it back! Run home!", Theme.go)
		elseif kind == "shieldOff" then
			HudController.banner("Your shield is off: keep your cubes safe!", Theme.round5.shield)
		elseif kind == "friendJoined" then
			HudController.banner(`{data.name} is here! Friends +{math.round((data.bonus or 0) * 100)}% coins`, Theme.tiles.daily)
		elseif kind == "challengeDone" then
			local goal = if typeof(data.goal) == "number" then Ui.short(data.goal) else ""
			local what = string.gsub(tostring(data.text), "{n}", goal)
			HudController.banner(`Challenge done: {what}! Claim it in Daily`, Theme.tiles.daily)
		elseif kind == "challengeClaimed" then
			if data.auto then
				HudController.banner(`Yesterday's challenges paid +{Ui.short(data.coins)}`, Theme.coin)
			end
			floatGain(data.coins)
		end
	end)
	local function isGate(p: ProximityPrompt): boolean
		local spot = p:FindFirstAncestorWhichIsA("BasePart") -- the prompt sits on an Attachment in GatePromptSpotN
		return spot ~= nil and string.sub(spot.Name, 1, 14) == "GatePromptSpot"
	end
	ProximityPromptService.PromptShown:Connect(function(p)
		if isGate(p) then
			gatePromptUp = true
		end
	end)
	ProximityPromptService.PromptHidden:Connect(function(p)
		if isGate(p) then
			gatePromptUp = false
		end
	end)
	task.spawn(function()
		while true do
			watchIsland()
			task.wait(0.25)
		end
	end)
end

return HudController
