--!strict
-- LuckReveal: the 2D half of the big "you got something" moments (owner 2026-11-13: the Secret / Mythic
-- catch shows were weak; inspired by a reference clip's luck roll, not copied). Used by Show for the
-- Mythic and Secret freeze shows and the Secret thaw. Numbers in Config.show.reveal.
--   roll:     "1 in N" climbs from 1 to the pet's REAL odds (it never passes them: no fake near-miss),
--             ice-themed luck words step up as it passes 10 / 100 / 1,000 / 10,000, and the pet's name
--             freezes in letter by letter under it (blanks first). Ticks climb in pitch.
--   finale:   the rarity word, the whole name slamming in over a turning sunburst, "1 in N", ice confetti.
--   continue: one big green Continue button (the focal point); auto-continues after maxHold.
-- Reduced motion: no shiver, no sunburst spin, fewer confetti, quicker pops.

local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Theme = require(ReplicatedStorage.Shared.Theme)
local PetDefs = require(ReplicatedStorage.Shared.PetDefs)
local Ui = require(script.Parent.Parent.Lib.Ui)
local SoundController = require(script.Parent.SoundController)
local InputController = require(script.Parent.InputController)

local LuckReveal = {}
LuckReveal.__index = LuckReveal

export type Reveal = typeof(setmetatable({} :: {
	gui: ScreenGui, root: Frame, def: PetDefs.PetDef, reduced: boolean, odds: number, color: Color3,
	word: TextLabel, count: TextLabel, letters: { TextLabel }, order: { number }, shown: number, nameRow: Frame,
	done: boolean,
}, LuckReveal))

local function R()
	return Config.show.reveal
end

-- 1 in N for this pet's rarity (the real odds of its tier)
function LuckReveal.oddsOf(def: PetDefs.PetDef): number
	local pct = Config.tier(def.tier).odds
	return math.max(1, math.round(100 / math.max(pct, 1e-6)))
end

local function wordFor(n: number): (string, Color3)
	local text, color = "", Theme.white
	for _, w in R().words do
		if n >= w.from then
			text, color = w.text, Theme.tiers[w.tier] or Theme.white
		end
	end
	return text, color
end

local function band(parent: Instance, y: number, h: number, flip: boolean)
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	f.BackgroundColor3 = Theme.ink
	-- past the safe-area edges (notches, the top bar), so it never reads as a grey box on a phone
	f.Size = UDim2.new(1, 600, h, if flip then 300 else 300)
	f.Position = UDim2.new(0, -300, y, if flip then 0 else -300)
	f.ZIndex = 1
	local g = Instance.new("UIGradient")
	g.Rotation = if flip then 270 else 90
	g.Transparency = NumberSequence.new(R().vignette, 1)
	g.Parent = f
	f.Parent = parent
end

local function stroke(t: TextLabel, color: Color3, thick: number)
	local s = t:FindFirstChildOfClass("UIStroke")
	if s then
		s.Color = color
		s.Thickness = thick
	end
end

function LuckReveal.new(gui: ScreenGui, def: PetDefs.PetDef, reduced: boolean): Reveal
	local U = R().ui
	local root = Instance.new("Frame")
	root.Name = "LuckReveal"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromScale(1, 1)
	root.ZIndex = 2
	root.Parent = gui
	-- soft dark bands top and bottom so the words read over any scene (no full-screen black)
	band(root, 0, 0.3, false)
	band(root, 0.6, 0.4, true)
	local word = Ui.label(root, "", UDim2.fromScale(0.8, U.wordH), UDim2.fromScale(0.1, U.wordY))
	word.ZIndex = 3
	stroke(word, Theme.ink, 3)
	local count = Ui.label(root, "1 in 1", UDim2.fromScale(0.7, U.oddsH), UDim2.fromScale(0.15, U.oddsY))
	count.ZIndex = 3
	stroke(count, Theme.ink, 4)
	local grad = Instance.new("UIGradient")
	grad.Rotation = 90
	grad.Color = ColorSequence.new(Theme.white, Theme.ice)
	grad.Parent = count
	-- the name as blanks, one cell per letter
	local nameRow = Instance.new("Frame")
	nameRow.Name = "Name"
	nameRow.BackgroundTransparency = 1
	nameRow.AnchorPoint = Vector2.new(0.5, 0)
	nameRow.Position = UDim2.fromScale(0.5, U.nameY)
	nameRow.Size = UDim2.fromScale(U.nameMaxW, U.nameH)
	nameRow.ZIndex = 3
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0.004, 0)
	layout.Parent = nameRow
	nameRow.Parent = root
	local name = string.upper(def.name)
	local letters: { TextLabel } = {}
	local order: { number } = {}
	local cells = math.max(1, #name)
	-- each cell is a letter's shape (letterAspect x the row's height), shrinking only when a long name
	-- wouldn't fit the row (a phone)
	for i = 1, #name do
		local ch = string.sub(name, i, i)
		local space = ch == " "
		local t = Ui.label(nameRow, if space then "" else "_", UDim2.fromScale(1 / cells, 1))
		local ar = Instance.new("UIAspectRatioConstraint")
		ar.AspectRatio = U.letterAspect * (if space then U.spaceShare else 1)
		ar.AspectType = Enum.AspectType.FitWithinMaxSize
		ar.Parent = t
		t.LayoutOrder = i
		t.ZIndex = 4
		t.TextTransparency = 0.25
		t:SetAttribute("Letter", ch)
		stroke(t, Theme.ink, 3)
		local s = Instance.new("UIScale")
		s.Parent = t
		table.insert(letters, t)
		if not space then
			table.insert(order, i)
		end
	end
	-- the letters freeze in in a shuffled order (seeded by the name, so it's the same each time)
	local rng = Random.new(#name * 7919 + string.byte(name, 1))
	for i = #order, 2, -1 do
		local j = rng:NextInteger(1, i)
		order[i], order[j] = order[j], order[i]
	end
	local self = setmetatable({
		gui = gui, root = root, def = def, reduced = reduced, odds = LuckReveal.oddsOf(def),
		color = Theme.tierGlow[def.tier] or Theme.tiers[def.tier] or Theme.coin,
		word = word, count = count, letters = letters, order = order, shown = 0, nameRow = nameRow, done = false,
	}, LuckReveal)
	return self
end

function LuckReveal.showLetter(self: Reveal, i: number, quiet: boolean?)
	local t = self.letters[i]
	if not t or t.Text == t:GetAttribute("Letter") then
		return
	end
	t.Text = t:GetAttribute("Letter") :: string
	t.TextTransparency = 0
	t.TextColor3 = Theme.white
	local g = Instance.new("UIGradient")
	g.Rotation = 90
	g.Color = ColorSequence.new(Theme.white, self.color)
	g.Parent = t
	local s = t:FindFirstChildOfClass("UIScale") :: UIScale
	s.Scale = if self.reduced then 1.1 else 1.6
	TweenService:Create(s, TweenInfo.new(R().letterPop, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	if not quiet then
		SoundController.play("tink")
	end
end

local function setCount(self: Reveal, n: number)
	self.count.Text = `1 in {Ui.commas(n)}`
	local text, color = wordFor(n)
	if self.word.Text ~= text then
		self.word.Text = text
		self.word.TextColor3 = color
		if text ~= "" then
			local s = self.word:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
			s.Parent = self.word
			s.Scale = if self.reduced then 1.05 else 1.45
			TweenService:Create(s, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
			SoundController.play("upgrade_hit")
		end
	end
end

-- the roll: seconds long, or cut short by skipped(); onStep(u) lets the show shiver the cube
function LuckReveal.roll(self: Reveal, seconds: number, skipped: () -> boolean, onStep: ((number) -> ())?)
	local C = R()
	local t0 = os.clock()
	local lastTick = 0
	local logN = math.log(self.odds)
	while not self.done do
		local u = if skipped() then 1 else math.min(1, (os.clock() - t0) / math.max(0.05, seconds))
		-- climbs on a log scale, fast then slowing as it nears the real number (and stops on it)
		local e = 1 - (1 - u) ^ C.rollEase
		local n = if u >= 1 then self.odds else math.max(1, math.floor(math.exp(logN * e)))
		setCount(self, n)
		local want = math.floor(u * #self.order + 1e-9)
		while self.shown < want do
			self.shown += 1
			LuckReveal.showLetter(self, self.order[self.shown], self.shown % 2 == 0)
		end
		if os.clock() - lastTick >= C.tickEvery and u < 1 then
			lastTick = os.clock()
			SoundController.play(C.tickSound, C.tickFrom + (C.tickTo - C.tickFrom) * u)
		end
		-- the counter shivers harder near the end (never with reduced motion)
		if not self.reduced then
			self.count.Rotation = math.sin(os.clock() * C.shiver.hz) * C.shiver.deg * u * u
		end
		if onStep then
			onStep(u)
		end
		if u >= 1 then
			break
		end
		RunService.RenderStepped:Wait()
	end
	self.count.Rotation = 0
	for _, i in self.order do
		LuckReveal.showLetter(self, i, true)
	end
end

local function sunburst(self: Reveal)
	local C = R()
	local U = C.ui
	local sun = Instance.new("Frame")
	sun.Name = "Sunburst"
	sun.BackgroundTransparency = 1
	sun.AnchorPoint = Vector2.new(0.5, 0.5)
	sun.Position = UDim2.fromScale(0.5, U.nameY + U.nameH / 2)
	sun.Size = UDim2.fromScale(C.sunSize, C.sunSize)
	sun.SizeConstraint = Enum.SizeConstraint.RelativeYY
	sun.ZIndex = 2
	for i = 1, C.sunRays do
		local ray = Instance.new("Frame")
		ray.BorderSizePixel = 0
		ray.BackgroundColor3 = if i % 2 == 0 then self.color else Theme.white
		ray.AnchorPoint = Vector2.new(0.5, 0.5)
		ray.Position = UDim2.fromScale(0.5, 0.5)
		ray.Size = UDim2.fromScale(0.07, 1)
		ray.Rotation = (i - 1) * 180 / C.sunRays
		ray.ZIndex = 2
		local g = Instance.new("UIGradient")
		g.Rotation = 90
		g.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0.35), NumberSequenceKeypoint.new(1, 1),
		})
		g.Parent = ray
		ray.Parent = sun
	end
	local s = Instance.new("UIScale")
	s.Scale = 0.2
	s.Parent = sun
	sun.Parent = self.root
	TweenService:Create(s, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	if not self.reduced then
		TweenService:Create(sun, TweenInfo.new(1 / C.sunSpin, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1), { Rotation = 360 }):Play()
	end
end

-- ice confetti: little diamonds in the pet's colour, white and ice blue, drifting down the screen
local function confetti(self: Reveal)
	local C = R()
	local colors = { self.color, Theme.white, Theme.ice }
	local n = if self.reduced then C.confettiReduced else C.confetti
	for i = 1, n do
		local p = Instance.new("Frame")
		p.BorderSizePixel = 0
		p.BackgroundColor3 = colors[(i % #colors) + 1]
		p.AnchorPoint = Vector2.new(0.5, 0.5)
		local sz = 0.012 + math.random() * 0.014
		p.Size = UDim2.fromScale(sz, sz)
		p.SizeConstraint = Enum.SizeConstraint.RelativeYY
		local x = math.random()
		p.Position = UDim2.fromScale(x, -0.05 - math.random() * 0.3)
		p.Rotation = 45
		p.ZIndex = 5
		Ui.stroke(p, 1.5)
		p.Parent = self.root
		local fall = C.confettiFall[1] + math.random() * (C.confettiFall[2] - C.confettiFall[1])
		TweenService:Create(p, TweenInfo.new(fall, Enum.EasingStyle.Sine, Enum.EasingDirection.In), {
			Position = UDim2.fromScale(x + (math.random() - 0.5) * 0.2, 1.08),
			Rotation = if self.reduced then 45 else 45 + (math.random() - 0.5) * 720,
		}):Play()
		task.delay(fall, function()
			p:Destroy()
		end)
	end
end

-- the reveal: the rarity word, the name slams, "1 in N" under it, sunburst and confetti
function LuckReveal.finale(self: Reveal)
	local U = R().ui
	for _, i in self.order do
		LuckReveal.showLetter(self, i, true)
	end
	self.word.Text = ""
	self.count.Visible = false
	sunburst(self)
	confetti(self)
	local rarity = Ui.label(self.root, string.gsub(string.upper(self.def.tier), "(.)", "%1 "), UDim2.fromScale(0.6, U.rarityH), UDim2.fromScale(0.2, U.rarityY))
	rarity.ZIndex = 4
	rarity.TextColor3 = self.color
	stroke(rarity, Theme.ink, 3)
	local line = Ui.label(self.root, `1 in {Ui.commas(self.odds)}`, UDim2.fromScale(0.5, U.lineH), UDim2.fromScale(0.25, U.lineY))
	line.ZIndex = 4
	stroke(line, Theme.ink, 3)
	local s = self.nameRow:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
	s.Parent = self.nameRow
	s.Scale = if self.reduced then 1.1 else 1.8
	TweenService:Create(s, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

-- one green Continue button; returns when it's pressed, the show ends, or after maxHold
function LuckReveal.waitContinue(self: Reveal, alive: () -> boolean)
	local C = R()
	local U = C.ui
	local pressed = false
	local b = Ui.block(self.root, "Continue", Theme.go, "Continue", function()
		pressed = true
	end)
	b.root.AnchorPoint = Vector2.new(0.5, 0.5)
	b.root.Position = UDim2.fromScale(0.5, U.continueY)
	b.root.Size = UDim2.fromScale(U.continueSize[1], U.continueSize[2])
	-- the show's ScreenGui orders by ZIndex across the whole screen, so every part of the button goes on top
	b.root.ZIndex = 6
	for _, d in b.root:GetDescendants() do
		if d:IsA("GuiObject") then
			d.ZIndex = if d == b.text then 8 else 7
		end
	end
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = U.continueSize[1] / U.continueSize[2] * 16 / 9
	aspect.Parent = b.root
	if not self.reduced then
		local ps = Instance.new("UIScale")
		ps.Parent = b.root
		TweenService:Create(ps, TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Scale = 1.06 }):Play()
	end
	InputController.select(b.face)
	ContextActionService:BindActionAtPriority("IceRay_RevealContinue", function(_, state: Enum.UserInputState)
		if state == Enum.UserInputState.Begin then
			pressed = true
			return Enum.ContextActionResult.Sink
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.ContextActionPriority.High.Value + 11, Enum.KeyCode.Return, Enum.KeyCode.Space, Enum.KeyCode.ButtonA)
	local t0 = os.clock()
	while not pressed and alive() and os.clock() - t0 < C.maxHold do
		RunService.RenderStepped:Wait()
	end
	ContextActionService:UnbindAction("IceRay_RevealContinue")
	if pressed then
		SoundController.play("click")
	end
end

function LuckReveal.destroy(self: Reveal)
	if self.done then
		return
	end
	self.done = true
	ContextActionService:UnbindAction("IceRay_RevealContinue")
	self.root:Destroy()
end

return LuckReveal
