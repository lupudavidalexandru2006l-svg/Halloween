--!strict
-- EggController: the limited Robux egg on the client (LimitedEgg, owner 2026-11-22).
--   * the Shop's featured banner (through ClientHooks.shopTop): the egg, its 6 pets with odds (soft pity
--     included) and the income each would hatch with for you right now, and the 1 / 3 / 10 buttons
--   * the Index's Limited page (ClientHooks.indexExtra): no Claim, no +10%
--   * the hatch show (Animation Rules 3) for Notify "eggHatch": the server has already rolled and saved;
--     the show only plays it. Beats: title card, pocket stage in the sky, the egg arrives inside turning
--     gold rings, honest build-up (one crack per rarity step, never more than the pet earns), star flare
--     in the tier's colour, burst, the pet rises turning, its name slams in letter by letter, OK.
--     3 / 10 eggs: the eggs crack one by one in a row (a tally), then the best pet gets the full reveal.
--     SKIP from the second viewing on (Settings "skip shows" skips from the start); Reduced motion halves
--     every beat and drops the shake, kick and flash; finish() always runs and is safe twice.
-- Buttons only ask ("Egg" remote); Roblox's own prompt shows and the server grants in ProcessReceipt.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Theme = require(ReplicatedStorage.Shared.Theme)
local PetDefs = require(ReplicatedStorage.Shared.PetDefs)
local LimitedEgg = require(ReplicatedStorage.Shared.LimitedEgg)
local Ui = require(script.Parent.Parent.Lib.Ui)
local ClientHooks = require(script.Parent.Parent.Lib.ClientHooks)
local State = require(script.Parent.State)
local Screen = require(script.Parent.Screen)
local CameraController = require(script.Parent.CameraController)
local SettingsController = require(script.Parent.SettingsController)
local SoundController = require(script.Parent.SoundController)
local PetRig = require(script.Parent.Parent.Lib.PetRig)
local PetClips = require(ReplicatedStorage.Shared.PetClips)

local EggController = {}
local me = Players.LocalPlayer

-- the show's numbers (one table, Animation Rules 3: "each beat has a duration in Config")
local SHOW = {
	title = 0.9, arrival = 1.3, crack = 0.55, flare = 0.7, burst = 0.35, rise = 1.4, name = 1.1, hold = 0.6,
	tallyEach = 0.32, -- 3 / 10 eggs: each small egg pops this long after the last
	stageHeight = 1400, -- the pocket stage floats this high above you
	ringSpin = { 0.35, -0.5, 0.7 }, -- turns a second, per gold ring
	kick = 0.35, -- camera kick on a crack (studs), none with reduced motion
	eggHeight = 9,
	petHeightMul = 2.2, -- the revealed pet stands this many times its normal height
}
-- the tier's colour for the flare / rays / words. Rare blue, Epic purple, Legendary gold, Mythic aurora pink
local FLARE: { [string]: Color3 } = {
	Rare = Color3.fromRGB(80, 170, 255), Epic = Color3.fromRGB(170, 90, 255),
	Legendary = Color3.fromRGB(255, 200, 60), Mythic = Color3.fromRGB(255, 110, 200),
}
local AURORA = { Color3.fromRGB(60, 230, 200), Color3.fromRGB(150, 110, 255), Color3.fromRGB(255, 120, 210) }
-- cracks before the burst: one per step above Rare. The build-up never promises more than you got.
local CRACKS: { [string]: number } = { Rare = 1, Epic = 2, Legendary = 3, Mythic = 4 }

local view: { odds: { number }, incomes: { number }, opened: number }? = nil
local running: any = nil

local function reduced(): boolean
	return SettingsController.get("reducedMotion") == true
end

local function eggModel(): Model?
	local f = ReplicatedStorage:FindFirstChild("EggModels")
	local m = f and f:FindFirstChild("FrostlightEgg")
	return if m and m:IsA("Model") then m else nil
end

local function pct(p: number): string
	if p >= 10 then
		return string.format("%d%%", math.floor(p + 0.5))
	elseif p >= 1 then
		return string.format("%.1f%%", p)
	end
	return string.format("%.2f%%", p)
end

local function oneIn(p: number): string
	return "1 in " .. Ui.commas(math.max(1, math.floor(100 / math.max(p, 0.0001) + 0.5)))
end

-- ---------------------------------------------------------------- the egg as a little 3D picture
local function eggPicture(parent: Instance, size: UDim2, pos: UDim2): GuiObject
	local src = eggModel()
	if not src then
		local f = Instance.new("Frame")
		f.BackgroundColor3 = Color3.fromRGB(140, 210, 255)
		f.Size = size
		f.Position = pos
		Ui.corner(f, 0.5)
		f.Parent = parent
		return f
	end
	local vf = Instance.new("ViewportFrame")
	vf.Name = "Egg"
	vf.BackgroundTransparency = 1
	vf.Size = size
	vf.Position = pos
	vf.Ambient = Color3.fromRGB(170, 180, 210)
	vf.LightColor = Theme.white
	vf.LightDirection = Vector3.new(-1, -1, -1)
	local a = Instance.new("UIAspectRatioConstraint")
	a.Parent = vf
	local m = src:Clone()
	m:PivotTo(CFrame.new())
	local cf, ext = m:GetBoundingBox()
	local cam = Instance.new("Camera")
	cam.FieldOfView = 30
	local r = math.max(ext.X, ext.Y, ext.Z)
	cam.CFrame = CFrame.lookAt(cf.Position + Vector3.new(0, r * 0.15, -r * 2.2), cf.Position)
	cam.Parent = vf
	vf.CurrentCamera = cam
	m.Parent = vf
	vf.Parent = parent
	if not reduced() then
		-- a slow turn, so the crystal catches the light
		local t0 = os.clock()
		local conn: RBXScriptConnection
		conn = RunService.RenderStepped:Connect(function()
			if not vf.Parent then
				conn:Disconnect()
				return
			end
			m:PivotTo(CFrame.Angles(0, (os.clock() - t0) * 0.6, 0))
		end)
	end
	return vf
end

-- ---------------------------------------------------------------- Shop banner
-- v2 (owner 2026-11-22 "doesn't look very nice"): a featured-egg card in the pet-sim style, kept Chunky Pop.
-- Left: the egg big on a frosty pedestal, a slow sunburst and glow behind it, snow drifting, a LIMITED
-- sticker. Right: the title, one plain hint line, six tier-coloured pet cards (odds pill on top, the pet,
-- its name, a white chip with its boost: the biggest number is what you get), then three green Robux
-- buttons where the egg count is the biggest word and honest tags say the extra per Robux.
local function frame(parent: Instance, name: string, size: UDim2, pos: UDim2, color: Color3?, alpha: number?): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.Size = size
	f.Position = pos
	f.BackgroundColor3 = color or Theme.white
	f.BackgroundTransparency = alpha or 0
	f.BorderSizePixel = 0
	f.Parent = parent
	return f
end

local function forever(inst: Instance, info: TweenInfo, goal: { [string]: any })
	if not reduced() then
		TweenService:Create(inst, info, goal):Play()
	end
end

-- a soft white glint that sweeps across a face now and then (Legendary / Mythic cards, the sticker)
local function shine(face: GuiObject, every: number)
	if reduced() then
		return
	end
	local s = frame(face, "Shine", UDim2.fromScale(1, 1), UDim2.new(), Theme.white, 0)
	s.ZIndex = 0
	Ui.corner(s)
	local g = Instance.new("UIGradient")
	g.Rotation = 25
	g.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.4, 1), NumberSequenceKeypoint.new(0.5, 0.6),
		NumberSequenceKeypoint.new(0.6, 1), NumberSequenceKeypoint.new(1, 1),
	})
	g.Offset = Vector2.new(-1, 0)
	g.Parent = s
	task.spawn(function()
		task.wait(math.random() * every)
		while s.Parent do
			g.Offset = Vector2.new(-1, 0)
			TweenService:Create(g, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), { Offset = Vector2.new(1, 0) }):Play()
			task.wait(every)
		end
	end)
end

-- a slow sunburst: thin bars through one middle, each fading out toward its ends
local function sunburst(parent: Instance, centre: UDim2, size: number, color: Color3, n: number): Frame
	local box = frame(parent, "Rays", UDim2.fromScale(size, size), centre, nil, 1)
	box.AnchorPoint = Vector2.new(0.5, 0.5)
	box.SizeConstraint = Enum.SizeConstraint.RelativeYY
	for k = 0, n - 1 do
		local r = frame(box, "Ray", UDim2.fromScale(if k % 2 == 0 then 0.1 else 0.06, 1), UDim2.fromScale(0.5, 0.5), color, 0)
		r.AnchorPoint = Vector2.new(0.5, 0.5)
		r.Rotation = k * 180 / n
		local g = Instance.new("UIGradient")
		g.Rotation = 90
		g.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.8), NumberSequenceKeypoint.new(0.5, 0.45),
			NumberSequenceKeypoint.new(0.7, 0.8), NumberSequenceKeypoint.new(1, 1),
		})
		g.Parent = r
	end
	forever(box, TweenInfo.new(40, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1), { Rotation = 360 })
	return box
end

local function robuxButton(parent: Instance, p: any, tag: string?, best: boolean): Ui.Block
	local b = Ui.block(parent, "Buy_" .. p.id, Theme.go, "", function()
		SoundController.play("click")
		State.send("Egg", { op = "buy", pack = p.id })
	end)
	b.text.Visible = false
	Ui.label(b.face, if p.eggs == 1 then "1 EGG" else `{p.eggs} EGGS`, UDim2.fromScale(0.86, 0.42), UDim2.fromScale(0.07, 0.11))
	-- the price: Robux mark + number, centred together by their real width
	local row = frame(b.face, "Price", UDim2.fromScale(0.9, 0.36), UDim2.fromScale(0.05, 0.55), nil, 1)
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.Padding = UDim.new(0.02, 0)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = row
	local icon = Instance.new("ImageLabel")
	icon.BackgroundTransparency = 1
	icon.Image = Config.images.icons.robux
	icon.SizeConstraint = Enum.SizeConstraint.RelativeYY
	icon.Size = UDim2.fromScale(0.95, 0.95)
	icon.ScaleType = Enum.ScaleType.Fit
	icon.LayoutOrder = 1
	icon.Parent = row
	-- owner 2026-11-22 "make the robux look like the other robux": the Shop's mark (PopupController robuxMark),
	-- a white mark in a thick ink contour. The slot stays empty; eight ink copies nudged round the white one draw it.
	icon.ImageTransparency = 1
	local o = Config.ui.shop.robuxOutline
	for k = 0, 8 do
		local a = k * math.pi / 4
		local copy = Instance.new("ImageLabel")
		copy.Name = if k == 8 then "Mark" else "Contour"
		copy.BackgroundTransparency = 1
		copy.Image = icon.Image
		copy.ScaleType = Enum.ScaleType.Fit
		copy.ImageColor3 = if k == 8 then Theme.white else Theme.ink
		copy.AnchorPoint = Vector2.new(0.5, 0.5)
		copy.Position = if k == 8 then UDim2.fromScale(0.5, 0.5) else UDim2.fromScale(0.5 + math.cos(a) * o, 0.5 + math.sin(a) * o)
		copy.Size = UDim2.fromScale(1, 1)
		copy.ZIndex = if k == 8 then 4 else 3
		copy.Parent = icon
	end
	local price = Ui.label(row, tostring(p.robux), UDim2.fromScale(0, 1), UDim2.new())
	local priceStroke = price:FindFirstChildOfClass("UIStroke")
	if priceStroke then
		priceStroke.Thickness = Config.ui.floatingStroke -- the same firm outline as the Shop's prices
	end
	price.TextScaled = false
	price.AutomaticSize = Enum.AutomaticSize.X
	price.LayoutOrder = 2
	local function fit()
		price.TextSize = math.max(8, math.floor(row.AbsoluteSize.Y * 0.95))
	end
	row:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	fit()
	if tag then
		-- a yellow sticker straddling the top-right corner
		local t = Ui.block(b.root, "Tag", Theme.coin, "", nil, true)
		t.root.AnchorPoint = Vector2.new(1, 0.8)
		t.root.Position = UDim2.fromScale(1.03, 0)
		t.root.Size = UDim2.fromScale(0.62, 0.36)
		t.root.Rotation = 4
		t.root.ZIndex = 3
		t.text.Text = tag
		t.text.Size = UDim2.fromScale(0.9, 0.78)
		t.text.Position = UDim2.fromScale(0.05, 0.1)
		Ui.roundBlock(t, 0.5)
	end
	if best then
		-- the one pulse in the shop: the true best value
		local sc = Instance.new("UIScale")
		sc.Parent = b.root
		forever(sc, TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Scale = 1.04 })
	end
	return b
end

local function petCard(grid: Instance, i: number, e: any): (TextLabel, TextLabel)
	local def = PetDefs.get(e.key)
	local tc = Theme.tiers[e.tier] or Theme.info
	local slot = Ui.block(grid, e.key, tc, "", nil)
	slot.root.LayoutOrder = i
	slot.text.Visible = false
	if e.tier == "Mythic" then
		-- the Mythic card shimmers through the aurora colours
		slot.face.BackgroundColor3 = Theme.white
		slot.root.BackgroundColor3 = Ui.darker(AURORA[2])
		local g = Instance.new("UIGradient")
		g.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, AURORA[1]:Lerp(Theme.ink, 0.15)),
			ColorSequenceKeypoint.new(0.5, AURORA[2]:Lerp(Theme.ink, 0.15)),
			ColorSequenceKeypoint.new(1, AURORA[3]:Lerp(Theme.ink, 0.15)),
		})
		g.Rotation = 45
		g.Parent = slot.face
		forever(g, TweenInfo.new(6, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1), { Rotation = 405 })
	end
	if e.tier == "Mythic" or e.tier == "Legendary" then
		shine(slot.face, if e.tier == "Mythic" then 2.2 else 3.4)
	end
	-- odds on a dark pill at the top
	local op = frame(slot.face, "Odds", UDim2.fromScale(0.7, 0.13), UDim2.fromScale(0.15, 0.05), Theme.ink, 0.45)
	Ui.corner(op, 0.5)
	local o = Ui.label(op, pct(e.weight), UDim2.fromScale(0.84, 0.86), UDim2.fromScale(0.08, 0.07))
	if def then
		Ui.petPicture(slot.face, def, UDim2.fromScale(1.1, 0.56), UDim2.fromScale(-0.05, 0.15))
	end
	Ui.label(slot.face, e.name, UDim2.fromScale(0.92, 0.1), UDim2.fromScale(0.04, 0.69))
	-- the boost: a white chip, the biggest number on the card
	local chip = frame(slot.face, "Boost", UDim2.fromScale(0.84, 0.16), UDim2.fromScale(0.08, 0.81), Theme.white, 0)
	Ui.corner(chip, 0.5)
	Ui.stroke(chip, 2)
	local inc = Ui.inkLabel(chip, `{math.floor(e.pct * 100)}%`, UDim2.fromScale(0.8, 0.82), UDim2.fromScale(0.1, 0.09))
	return o, inc
end

local function banner(sf: Instance, order: number): number
	if Players.LocalPlayer:GetAttribute("RandomItemsOk") ~= true and not RunService:IsStudio() then
		return order -- paid random items not allowed here: no egg banner (the server checks too)
	end
	if not LimitedEgg.onSale(workspace:GetServerTimeNow()) then
		return order
	end
	State.send("Egg", { op = "view" })
	order += 1
	local row = Instance.new("Frame")
	row.Name = "LimitedEgg"
	row.LayoutOrder = order
	row.BackgroundTransparency = 1
	row.Size = UDim2.fromScale(1, 1)
	local ar = Instance.new("UIAspectRatioConstraint")
	ar.AspectRatio = if Screen.deviceClass() == "phone" then 1.75 else 2.2
	ar.DominantAxis = Enum.DominantAxis.Width
	ar.Parent = row
	row.Parent = sf
	local card = Ui.block(row, "Card", Color3.fromRGB(40, 36, 120), "", nil, true)
	card.root.Size = UDim2.fromScale(1, 1)
	card.text.Visible = false
	local face = card.face
	face.ClipsDescendants = true
	-- the night sky: deep blue into violet, an aurora band across the top
	local sky = frame(face, "Sky", UDim2.fromScale(1, 1), UDim2.new(), Theme.white, 0)
	sky.ZIndex = 0
	Ui.corner(sky)
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(30, 60, 150)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(70, 40, 150)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(40, 24, 100)),
	})
	g.Rotation = 90
	g.Parent = sky
	local band = frame(face, "Aurora", UDim2.fromScale(1.2, 0.35), UDim2.fromScale(-0.1, -0.05), Theme.white, 0)
	band.ZIndex = 0
	local bg = Instance.new("UIGradient")
	bg.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, AURORA[1]), ColorSequenceKeypoint.new(0.5, AURORA[2]), ColorSequenceKeypoint.new(1, AURORA[3]),
	})
	bg.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.45, 0.72), NumberSequenceKeypoint.new(1, 1),
	})
	bg.Rotation = 80
	bg.Parent = band
	forever(bg, TweenInfo.new(5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Rotation = 100 })
	-- snow drifting down (still dots with reduced motion)
	local rng = Random.new(7)
	for k = 1, 18 do
		local s = frame(face, "Snow", UDim2.fromScale(0.006, 0.006), UDim2.fromScale(rng:NextNumber(), rng:NextNumber()), Theme.white, rng:NextNumber(0.25, 0.6))
		s.SizeConstraint = Enum.SizeConstraint.RelativeXX
		s.ZIndex = 0
		Ui.corner(s, 1)
		if not reduced() then
			local x = s.Position.X.Scale
			task.delay(rng:NextNumber(0, 6), function()
				if s.Parent then
					s.Position = UDim2.fromScale(x, -0.05)
					TweenService:Create(s, TweenInfo.new(rng:NextNumber(6, 10), Enum.EasingStyle.Linear, Enum.EasingDirection.In, -1), { Position = UDim2.fromScale(x + 0.03, 1.05) }):Play()
				end
			end)
		end
	end
	-- the egg: glow, sunburst, pedestal, the egg bobbing and turning
	local EGG_X, EGG_Y = 0.16, 0.5
	for k, sz in { 0.9, 0.66, 0.44 } do
		local c = frame(face, "Glow", UDim2.fromScale(sz, sz), UDim2.fromScale(EGG_X, EGG_Y), Color3.fromRGB(150, 225, 255), 0.88 - k * 0.04)
		c.AnchorPoint = Vector2.new(0.5, 0.5)
		c.SizeConstraint = Enum.SizeConstraint.RelativeYY
		Ui.corner(c, 1)
	end
	sunburst(face, UDim2.fromScale(EGG_X, EGG_Y), 1.25, Color3.fromRGB(200, 240, 255), 12)
	-- QA 2026-11-23 (DR-08): wider, flatter and up under the egg's foot, so it reads as a stand, not an empty pill
	local ped = frame(face, "Pedestal", UDim2.fromScale(0.21, 0.05), UDim2.fromScale(EGG_X, 0.745), Color3.fromRGB(190, 235, 255), 0)
	ped.AnchorPoint = Vector2.new(0.5, 0.5)
	Ui.corner(ped, 0.5)
	Ui.stroke(ped, 2)
	local pg = Instance.new("UIGradient")
	pg.Color = ColorSequence.new(Theme.white, Color3.fromRGB(120, 180, 240))
	pg.Rotation = 90
	pg.Parent = ped
	local eggPos = UDim2.fromScale(0.02, 0.12)
	local egg = eggPicture(face, UDim2.fromScale(0.28, 0.74), eggPos)
	forever(egg, TweenInfo.new(1.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Position = UDim2.fromScale(0.02, 0.09) })
	-- the LIMITED sticker, tilted on the corner
	local tag = Ui.block(face, "Limited", Theme.no, "LIMITED", nil)
	tag.root.Position = UDim2.fromScale(0.02, 0.05)
	tag.root.Size = UDim2.fromScale(0.15, 0.11)
	tag.root.Rotation = -7
	tag.root.ZIndex = 3
	shine(tag.face, 2.8)
	-- title + one hint line + the leave date (a plain date, never a ticking countdown)
	local title = Ui.label(face, string.upper(LimitedEgg.name), UDim2.fromScale(0.5, 0.13), UDim2.fromScale(0.32, 0.03))
	title.TextXAlignment = Enum.TextXAlignment.Left
	local tg = Instance.new("UIGradient")
	tg.Color = ColorSequence.new(Theme.white, Color3.fromRGB(150, 225, 255))
	tg.Rotation = 90
	tg.Parent = title
	local hint = Ui.label(face, "Each pet earns this % of your best pet's coins  ·  odds include your luck", UDim2.fromScale(0.66, 0.05), UDim2.fromScale(0.32, 0.16))
	hint.TextXAlignment = Enum.TextXAlignment.Left
	hint.TextColor3 = Color3.fromRGB(205, 225, 255)
	local leaves = LimitedEgg.leavesText()
	if leaves then
		local l = Ui.label(face, leaves, UDim2.fromScale(0.16, 0.07), UDim2.fromScale(0.82, 0.05))
		l.TextXAlignment = Enum.TextXAlignment.Right
		l.TextColor3 = Color3.fromRGB(205, 225, 255)
	end
	-- the six pets
	local grid = frame(face, "Pets", UDim2.fromScale(0.66, 0.5), UDim2.fromScale(0.32, 0.23), nil, 1)
	local gl = Instance.new("UIGridLayout")
	gl.CellSize = UDim2.fromScale(0.155, 1)
	gl.CellPadding = UDim2.fromScale(0.014, 0)
	gl.SortOrder = Enum.SortOrder.LayoutOrder
	gl.Parent = grid
	local oddsLabels, incLabels = {}, {}
	for i, e in LimitedEgg.pets do
		oddsLabels[i], incLabels[i] = petCard(grid, i, e)
	end
	-- the buttons: honest tags only (extra eggs per Robux against one egg, rounded down; BEST VALUE on the true best)
	local one = LimitedEgg.packs[1].robux / LimitedEgg.packs[1].eggs
	local bestI, bestEach = 1, math.huge
	for i, p in LimitedEgg.packs do
		if p.robux / p.eggs < bestEach then
			bestI, bestEach = i, p.robux / p.eggs
		end
	end
	for i, p in LimitedEgg.packs do
		local more = math.floor((one * p.eggs / p.robux - 1) * 100)
		local tagText = if i == bestI and i > 1 then "BEST VALUE" elseif more > 0 then `+{more}% MORE` else nil
		local b = robuxButton(face, p, tagText, i == bestI and i > 1)
		b.root.Position = UDim2.fromScale(0.32 + (i - 1) * 0.225, 0.79)
		b.root.Size = UDim2.fromScale(0.205, 0.17)
	end
	-- live numbers once the server answers (pity odds)
	local function fill()
		local v = view
		if not v then
			return
		end
		for i, l in oddsLabels do
			l.Text = pct(v.odds[i] or LimitedEgg.pets[i].weight)
		end
		for i, l in incLabels do
			l.Text = `{math.floor(LimitedEgg.pets[i].pct * 100)}%`
		end
	end
	fill()
	local conn: RBXScriptConnection
	conn = State.Notify:Connect(function(kind: string)
		if not row.Parent then
			conn:Disconnect()
			return
		end
		if kind == "eggView" then
			fill()
		end
	end)
	return order
end

-- ---------------------------------------------------------------- Index: the Limited page
local function limitedPage(l: Instance, order: number, v: any, helpers: any)
	local X = Config.ui.index
	local c = helpers.card(helpers.row(l, order, 0, X.pageAspect))
	c.Name = "PageLimited"
	c.ClipsDescendants = true
	local head = Instance.new("Frame")
	head.Name = "Head"
	head.BackgroundColor3 = Color3.fromRGB(60, 40, 140)
	head.BorderSizePixel = 0
	head.Size = UDim2.fromScale(1, X.headHeight)
	Ui.corner(head)
	head.Parent = c
	local found, total = 0, #PetDefs.limited
	for _, def in PetDefs.limited do
		if v.found[def.key] then
			found += 1
		end
	end
	local name = Ui.label(head, LimitedEgg.indexTitle, UDim2.fromScale(0.25, 0.7), UDim2.fromScale(0.018, 0.15))
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextColor3 = Theme.coin
	helpers.sized(name, "body")
	helpers.bar(head, 0.28, 0.2, 0.44, 0.6, found / math.max(1, total), `{found} / {total}`, Theme.go)
	local what = Ui.label(head, LimitedEgg.name, UDim2.fromScale(0.25, 0.6), UDim2.fromScale(0.74, 0.2))
	what.TextXAlignment = Enum.TextXAlignment.Left
	helpers.sized(what, "small")
	local grid = Instance.new("Frame")
	grid.Name = "Pets"
	grid.BackgroundTransparency = 1
	grid.Position = UDim2.fromScale(X.slotInset, X.headHeight + X.slotTop)
	grid.Size = UDim2.fromScale(1 - X.slotInset * 2, 1 - X.headHeight - X.slotTop * 2)
	grid.Parent = c
	local g = Instance.new("UIGridLayout")
	local n = math.max(1, total)
	g.CellSize = UDim2.fromScale((1 - X.slotGap * (n - 1)) / n, 1)
	g.CellPadding = UDim2.fromScale(X.slotGap, 0)
	g.SortOrder = Enum.SortOrder.LayoutOrder
	g.Parent = grid
	for i, def in PetDefs.limited do
		local got = v.found[def.key] == true
		local b = Ui.block(grid, def.key, if got then Theme.tiers[def.tier] or Theme.info else Theme.slot, if got then def.name else "", nil)
		b.root.LayoutOrder = i
		helpers.sized(b.text, "button")
		if Ui.petPicture(b.face, def, UDim2.fromScale(0.8, 0.66), UDim2.fromScale(0.1, 0.02), not got) then
			b.text.Size = UDim2.fromScale(0.9, 0.28)
			b.text.Position = UDim2.fromScale(0.05, 0.68)
		end
	end
end

-- ---------------------------------------------------------------- the hatch show
type Ctx = {
	results: { any }, reduced: boolean, skipped: boolean, finished: boolean,
	folder: Folder, gui: ScreenGui, cam: Camera?, conns: { RBXScriptConnection }, center: Vector3,
	kickUntil: number, orbit: number, orbitR: number, orbitH: number, look: Vector3,
	controls: { hum: Humanoid, walk: number, jump: number, jumpH: number }?,
	stage: any, -- the sanctum's pieces (rune parts, chains, pillar tops, ribbons)
}

local function hold(ctx: Ctx, seconds: number, keep: boolean?)
	local t0 = os.clock()
	local s = seconds * (if ctx.reduced then 0.5 else 1)
	while os.clock() - t0 < s and not ctx.finished do
		if ctx.skipped and not keep then
			return
		end
		RunService.RenderStepped:Wait()
	end
end

local function part(ctx: Ctx, size: Vector3, color: Color3, alpha: number, neon: boolean?): Part
	local p = Instance.new("Part")
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	p.Material = if neon then Enum.Material.Neon else Enum.Material.SmoothPlastic
	p.Color = color
	p.Size = size
	p.Transparency = alpha
	p.Parent = ctx.folder
	return p
end

local function sparkles(at: BasePart, color: Color3, rate: number, speed: number?): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	e.Color = ColorSequence.new(color)
	e.LightEmission = 1
	e.Rate = rate
	e.Lifetime = NumberRange.new(0.8, 1.6)
	e.Speed = NumberRange.new(speed or 4, (speed or 4) * 2)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0) })
	e.Transparency = NumberSequence.new(0.1, 1)
	e.Parent = at
	return e
end

-- a flat ring of thin glowing blocks on the floor (a rune circle), or standing up (a gyroscope ring)
local function ring(ctx: Ctx, radius: number, color: Color3, n: number, thick: number, alpha: number): Model
	local m = Instance.new("Model")
	m.Name = "Ring"
	for i = 1, n do
		local a = (i - 1) / n * math.pi * 2
		local len = 2 * math.pi * radius / n * 0.82
		local p = part(ctx, Vector3.new(len, thick, thick), color, alpha, true)
		p.CFrame = CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -radius)
		p.Parent = m
	end
	m.Parent = ctx.folder
	return m
end

-- the Frost Sanctum (owner 2026-11-22: "Boo Town's was better, inspire from it and make a better one"):
-- a bright violet arena in the sky, not a dark room. Ice pillars with glowing crystal tops hold frost chains
-- that carry the egg; a big rune circle on the floor waits dim until the egg lands on it; aurora ribbons
-- (soft textured beams, not neon bars) wave across a starry violet sky with a big moon; snow falls.
local VIOLET, VIOLET_DEEP = Color3.fromRGB(96, 52, 190), Color3.fromRGB(46, 22, 110)
local ICE = Color3.fromRGB(95, 150, 225) -- a deeper ice: the paler one blew out to white under the lights
local PILLARS = 6 -- around the back and sides (none on the camera's side)
local PILLAR_R, PILLAR_H = 19, 16
local HANG_Y = 10 -- the egg's middle while it hangs
local CHAINS = 4

local function stage(ctx: Ctx)
	local c = ctx.center
	local st: any = { runeParts = {}, chains = {}, crystals = {} }
	ctx.stage = st
	-- the floor: a violet disc with a glowing edge
	local floor = part(ctx, Vector3.new(0.6, 52, 52), VIOLET_DEEP, 0)
	floor.Shape = Enum.PartType.Cylinder
	floor.CFrame = CFrame.new(c) * CFrame.Angles(0, 0, math.rad(90))
	local edge = ring(ctx, 25.4, AURORA[2], 72, 0.45, 0.1)
	edge:PivotTo(CFrame.new(c + Vector3.new(0, 0.32, 0)))
	-- the rune circle: two rings, tick marks and an eight-point star, dim until the drop lights it
	local rune = Instance.new("Model")
	rune.Name = "Rune"
	rune.Parent = ctx.folder
	local function runePart(size: Vector3, cf: CFrame)
		local p = part(ctx, size, AURORA[1], 0.78, true)
		p.CFrame = CFrame.new(c + Vector3.new(0, 0.33, 0)) * cf
		p.Parent = rune
		table.insert(st.runeParts, p)
	end
	for _, rr in { { 11, 48, 0.4 }, { 8.4, 40, 0.25 } } do
		for i = 1, rr[2] do
			local a = (i - 1) / rr[2] * math.pi * 2
			runePart(Vector3.new(2 * math.pi * rr[1] / rr[2] * 0.85, 0.12, rr[3]), CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -rr[1]))
		end
	end
	for i = 0, 23 do
		local a = i / 24 * math.pi * 2
		local L = if i % 6 == 0 then 2 else 1
		runePart(Vector3.new(0.22, 0.12, L), CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -(10.6 - L / 2)))
	end
	for i = 0, 7 do -- two squares of glowing lines = an eight-point star
		local off = if i >= 4 then 0.5 else 0
		local a1, a2 = (i % 4 + off) / 4 * math.pi * 2, (i % 4 + 1 + off) / 4 * math.pi * 2
		local p1 = Vector3.new(math.sin(a1) * 8, 0, math.cos(a1) * 8)
		local p2 = Vector3.new(math.sin(a2) * 8, 0, math.cos(a2) * 8)
		runePart(Vector3.new(0.25, 0.12, (p2 - p1).Magnitude), CFrame.lookAt((p1 + p2) / 2, p2))
	end
	rune.WorldPivot = CFrame.new(c + Vector3.new(0, 0.33, 0))
	-- ice pillars with glowing crystal tops (back half and sides only)
	st.tops = {}
	for i = 1, PILLARS do
		local a = math.pi * (0.1 + 0.8 * (i - 1) / (PILLARS - 1)) -- 18 to 162 degrees: the far side
		local pos = c + Vector3.new(math.cos(a) * PILLAR_R, 0, math.sin(a) * PILLAR_R)
		local base = part(ctx, Vector3.new(3.2, 1, 3.2), VIOLET_DEEP:Lerp(Theme.white, 0.15), 0)
		base.CFrame = CFrame.new(pos + Vector3.new(0, 0.5, 0)) * CFrame.Angles(0, a, 0)
		local col = part(ctx, Vector3.new(2, PILLAR_H, 2), ICE, 0.1)
		col.Material = Enum.Material.Ice
		col.CFrame = CFrame.new(pos + Vector3.new(0, PILLAR_H / 2, 0)) * CFrame.Angles(0, a, 0)
		local band = part(ctx, Vector3.new(2.15, PILLAR_H * 0.7, 0.2), AURORA[(i % 3) + 1], 0.65, true)
		band.CFrame = col.CFrame * CFrame.new(0, -PILLAR_H * 0.05, -1.02)
		local cap = part(ctx, Vector3.new(2.6, 0.5, 2.6), Theme.coin, 0)
		cap.CFrame = CFrame.new(pos + Vector3.new(0, PILLAR_H + 0.25, 0)) * CFrame.Angles(0, a, 0)
		local gem = part(ctx, Vector3.new(1.4, 2.4, 1.4), AURORA[(i % 3) + 1], 0.05, true)
		gem.CFrame = CFrame.new(pos + Vector3.new(0, PILLAR_H + 1.9, 0)) * CFrame.Angles(0, a + math.pi / 4, math.rad(45))
		local l = Instance.new("PointLight")
		l.Range, l.Brightness, l.Color = 14, 1.6, AURORA[(i % 3) + 1]
		l.Parent = gem
		st.tops[i] = pos + Vector3.new(0, PILLAR_H, 0)
	end
	-- the sky: a violet box (top lighter), a big pale moon, aurora ribbons, twinkling stars
	local R = 120
	for _, w in {
		{ Vector3.new(R * 2, 2, R * 2), Vector3.new(0, 95, 0), Color3.fromRGB(70, 40, 150) },
		{ Vector3.new(R * 2, 2, R * 2), Vector3.new(0, -8, 0), VIOLET_DEEP },
		{ Vector3.new(R * 2, 105, 2), Vector3.new(0, 43, R), Color3.fromRGB(60, 34, 140) },
		{ Vector3.new(R * 2, 105, 2), Vector3.new(0, 43, -R), Color3.fromRGB(60, 34, 140) },
		{ Vector3.new(2, 105, R * 2), Vector3.new(R, 43, 0), Color3.fromRGB(60, 34, 140) },
		{ Vector3.new(2, 105, R * 2), Vector3.new(-R, 43, 0), Color3.fromRGB(60, 34, 140) },
	} do
		local p = part(ctx, w[1], w[3], 0)
		p.Position = c + w[2]
	end
	-- a soft moon high on the back wall (smaller and not neon: the bright one was a white blob in the video)
	local moon = part(ctx, Vector3.new(1, 22, 22), Color3.fromRGB(190, 200, 245), 0.25)
	moon.Shape = Enum.PartType.Cylinder
	moon.CFrame = CFrame.new(c + Vector3.new(-45, 68, R - 3)) * CFrame.Angles(0, math.rad(90), 0)
	-- aurora ribbons: soft smoke-textured beams that slowly wave
	st.ribbons = {}
	for i = 1, 3 do
		local a0 = part(ctx, Vector3.one * 0.2, Theme.white, 1)
		local a1 = part(ctx, Vector3.one * 0.2, Theme.white, 1)
		a0.Position = c + Vector3.new(-90, 40 + i * 9, 70 + i * 8)
		a1.Position = c + Vector3.new(90, 46 + i * 7, 60 + i * 10)
		local at0, at1 = Instance.new("Attachment"), Instance.new("Attachment")
		at0.Parent, at1.Parent = a0, a1
		local b = Instance.new("Beam")
		b.Attachment0, b.Attachment1 = at0, at1
		b.Texture = "rbxasset://textures/particles/smoke_main.dds"
		b.TextureMode = Enum.TextureMode.Wrap
		b.TextureLength = 30
		b.TextureSpeed = 0.15
		b.LightEmission = 1
		b.Width0, b.Width1 = 16 + i * 3, 12 + i * 2
		b.CurveSize0, b.CurveSize1 = 30, -24
		b.FaceCamera = true
		b.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, AURORA[1]), ColorSequenceKeypoint.new(0.5, AURORA[2]), ColorSequenceKeypoint.new(1, AURORA[3]) })
		b.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.45), NumberSequenceKeypoint.new(0.7, 0.45), NumberSequenceKeypoint.new(1, 1) })
		b.Parent = a0
		st.ribbons[i] = b
	end
	local stars = part(ctx, Vector3.new(R * 1.8, 1, R * 1.8), Theme.white, 1)
	stars.Position = c + Vector3.new(0, 80, 0)
	local twinkle = sparkles(stars, Color3.fromRGB(235, 240, 255), if ctx.reduced then 6 else 22, 0.3)
	twinkle.Lifetime = NumberRange.new(3, 5)
	-- snow, and a light over the middle
	local air = part(ctx, Vector3.new(50, 1, 50), Theme.white, 1)
	air.CFrame = CFrame.new(c + Vector3.new(0, 30, 0))
	local snow = Instance.new("ParticleEmitter")
	snow.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	snow.Rate = if ctx.reduced then 8 else 30
	snow.Lifetime = NumberRange.new(6, 8)
	snow.Speed = NumberRange.new(3, 5)
	snow.EmissionDirection = Enum.NormalId.Bottom
	snow.Size = NumberSequence.new(0.35)
	snow.LightEmission = 0.6
	snow.Parent = air
	local light = Instance.new("PointLight")
	light.Range, light.Brightness, light.Color = 45, 2.2, Color3.fromRGB(200, 190, 255)
	light.Parent = air
	-- motion: only the ribbons wave (turning the ~220 rune and edge parts every frame cost too much: the
	-- Studio captures timed out mid-show, and phones would feel it)
	local _ = rune
	local t0 = os.clock()
	table.insert(ctx.conns, RunService.RenderStepped:Connect(function()
		local t = os.clock() - t0
		local slow = if ctx.reduced then 0.3 else 1
		for i, b in st.ribbons do
			b.CurveSize0 = 30 + math.sin(t * 0.4 * slow + i) * 10
			b.CurveSize1 = -24 + math.cos(t * 0.33 * slow + i * 2) * 10
		end
	end))
end

-- frost chains from the pillar tops to the egg: links of ice, each chain kept so it can snap
local function chains(ctx: Ctx, eggTop: Vector3)
	local st = ctx.stage
	local pick = { 1, 3, 4, 6 } -- four of the pillars, spread out
	for k = 1, CHAINS do
		local from = st.tops[pick[k]] + Vector3.new(0, 0.6, 0)
		local to = eggTop
		local m = Instance.new("Model")
		m.Name = "Chain"
		local d = to - from
		local n = math.max(6, math.floor(d.Magnitude / 1.3))
		for j = 0, n - 1 do
			local p = from + d * ((j + 0.5) / n)
			local link = part(ctx, Vector3.new(0.28, 0.9, 1.4), ICE, 0.05)
			link.Material = Enum.Material.Glass
			link.CFrame = CFrame.lookAt(p, to) * CFrame.Angles(0, 0, if j % 2 == 0 then 0 else math.rad(90))
			link.Parent = m
		end
		local glowLine = part(ctx, Vector3.new(0.12, 0.12, d.Magnitude), AURORA[1], 0.35, true)
		glowLine.CFrame = CFrame.lookAt(from + d / 2, to)
		glowLine.Parent = m
		m.Parent = ctx.folder
		st.chains[k] = { model = m, from = from }
	end
end

-- one chain snaps: a spark burst where it breaks, a standing ring of light round the egg, a kick; the chain
-- drops away and fades
local function snap(ctx: Ctx, k: number, eggMid: Vector3)
	local c = ctx.stage.chains[k]
	if not c then
		return
	end
	SoundController.play("crack")
	SoundController.play("tink")
	ctx.kickUntil = os.clock() + 0.15
	local spark = part(ctx, Vector3.one * 0.3, Theme.white, 1)
	spark.Position = eggMid + (c.from - eggMid).Unit * 4
	sparkles(spark, AURORA[1], 0, 14):Emit(if ctx.reduced then 10 else 30)
	local wave = ring(ctx, 3, Theme.white, 28, 0.25, 0.2)
	local t0 = os.clock()
	task.spawn(function()
		while wave.Parent and not ctx.finished do
			local u = math.min(1, (os.clock() - t0) / 0.5)
			local r = 3 + 6 * (1 - (1 - u) ^ 3)
			for i, p in wave:GetChildren() do
				local a = (i - 1) / 28 * math.pi * 2
				local bp = p :: BasePart
				bp.Size = Vector3.new(2 * math.pi * r / 28 * 0.8, 0.25, 0.25)
				bp.CFrame = CFrame.new(eggMid) * CFrame.Angles(0, ctx.orbit, 0) * CFrame.Angles(math.rad(90), 0, 0) * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -r)
				bp.Transparency = 0.2 + 0.8 * u
			end
			if u >= 1 then
				break
			end
			RunService.RenderStepped:Wait()
		end
		wave:Destroy()
	end)
	for _, p in c.model:GetChildren() do
		local bp = p :: BasePart
		TweenService:Create(bp, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			CFrame = bp.CFrame - Vector3.new(0, 10, 0) * (0.5 + math.random()), Transparency = 1,
		}):Play()
	end
	task.delay(0.8, function()
		c.model:Destroy()
	end)
	ctx.stage.chains[k] = nil
end

-- the rune circle lights up (the drop)
local function lightRune(ctx: Ctx)
	for _, p in ctx.stage.runeParts do
		p.Transparency = 0
		p.Color = Theme.white
		TweenService:Create(p, TweenInfo.new(0.6), { Color = AURORA[1], Transparency = 0.12 }):Play()
	end
end

-- the camera drifts on a slow arc in front of the egg and kicks on a crack
local function camera(ctx: Ctx)
	local cam = CameraController.borrow()
	if not cam then
		return
	end
	ctx.cam = cam
	ctx.orbit, ctx.orbitR, ctx.orbitH = math.rad(-25), 34, 7
	ctx.look = ctx.center + Vector3.new(0, 5, 0)
	local t0 = os.clock()
	table.insert(ctx.conns, RunService.RenderStepped:Connect(function(dt)
		local t = os.clock() - t0
		local swing = if ctx.reduced then 0.1 else 0.35
		local a = ctx.orbit + math.sin(t * 0.35) * swing
		local pos = ctx.center + Vector3.new(math.sin(a) * ctx.orbitR, ctx.orbitH, -math.cos(a) * ctx.orbitR)
		local cf = CFrame.lookAt(pos, ctx.look)
		if os.clock() < ctx.kickUntil and not ctx.reduced then
			cf *= CFrame.new((math.random() - 0.5) * SHOW.kick, (math.random() - 0.5) * SHOW.kick, 0)
		end
		cam.CFrame = cam.CFrame:Lerp(cf, math.min(1, dt * 6))
	end))
end

local function tweenCam(ctx: Ctx, radius: number, height: number, lookY: number, seconds: number)
	-- eased glide of the orbit numbers
	local r0, h0, l0 = ctx.orbitR, ctx.orbitH, ctx.look.Y - ctx.center.Y
	local s = seconds * (if ctx.reduced then 0.5 else 1)
	task.spawn(function()
		local t0 = os.clock()
		while not ctx.finished do
			local u = math.min(1, (os.clock() - t0) / math.max(0.05, s))
			local e = 1 - (1 - u) ^ 3
			ctx.orbitR = r0 + (radius - r0) * e
			ctx.orbitH = h0 + (height - h0) * e
			ctx.look = ctx.center + Vector3.new(0, l0 + (lookY - l0) * e, 0)
			if u >= 1 then
				break
			end
			RunService.RenderStepped:Wait()
		end
	end)
end

local function flash(ctx: Ctx, color: Color3, seconds: number)
	local f = Instance.new("Frame")
	f.Name = "Flash"
	f.BackgroundColor3 = color
	f.BorderSizePixel = 0
	f.Position = UDim2.fromScale(-0.1, -0.2)
	f.Size = UDim2.fromScale(1.2, 1.4)
	f.BackgroundTransparency = if ctx.reduced then 0.6 else 0
	f.ZIndex = 50
	f.Parent = ctx.gui
	TweenService:Create(f, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 1 }):Play()
	task.delay(seconds + 0.1, function()
		f:Destroy()
	end)
end

local function spaced(s: string): string
	return (s:gsub("(.)", "%1 "):sub(1, -2))
end

local function titleCard(ctx: Ctx)
	local card = Instance.new("Frame")
	card.Name = "TitleCard"
	card.BackgroundColor3 = Color3.fromRGB(8, 10, 24)
	card.BorderSizePixel = 0
	card.Position = UDim2.fromScale(-0.1, -0.2)
	card.Size = UDim2.fromScale(1.2, 1.4)
	card.ZIndex = 40
	card.Parent = ctx.gui
	local word = Ui.label(card, spaced(string.upper(LimitedEgg.name)), UDim2.fromScale(0.6, 0.08), UDim2.fromScale(0.3, 0.38))
	word.TextColor3 = Theme.coin
	word.TextTransparency = 1
	word.ZIndex = 41
	local line = Instance.new("Frame")
	line.AnchorPoint = Vector2.new(0.5, 0.5)
	line.Position = UDim2.fromScale(0.5, 0.48)
	line.Size = UDim2.fromScale(0, 0.004)
	line.BackgroundColor3 = Theme.white
	line.BorderSizePixel = 0
	line.ZIndex = 41
	local lg = Instance.new("UIGradient")
	lg.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(1, 1) })
	lg.Color = ColorSequence.new(AURORA[1], AURORA[3])
	lg.Parent = line
	line.Parent = card
	local cap = Ui.label(card, "Something inside is waking up...", UDim2.fromScale(0.4, 0.04), UDim2.fromScale(0.4, 0.52))
	cap.TextTransparency = 1
	cap.ZIndex = 41
	SoundController.play("chill")
	local s = SHOW.title * (if ctx.reduced then 0.5 else 1)
	TweenService:Create(line, TweenInfo.new(s * 0.7, Enum.EasingStyle.Quad), { Size = UDim2.fromScale(0.5, 0.004) }):Play()
	TweenService:Create(word, TweenInfo.new(s * 0.6), { TextTransparency = 0 }):Play()
	TweenService:Create(cap, TweenInfo.new(s * 0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, s * 0.25), { TextTransparency = 0 }):Play()
	hold(ctx, SHOW.title)
	-- the card fades away and shows the stage
	for _, d in card:GetDescendants() do
		if d:IsA("TextLabel") then
			TweenService:Create(d, TweenInfo.new(0.35), { TextTransparency = 1 }):Play()
		elseif d:IsA("UIStroke") then
			TweenService:Create(d, TweenInfo.new(0.35), { Transparency = 1 }):Play()
		end
	end
	TweenService:Create(card, TweenInfo.new(0.45), { BackgroundTransparency = 1 }):Play()
	task.delay(0.5, function()
		card:Destroy()
	end)
end

-- the egg drops in inside three turning gold rings
local function arrive(ctx: Ctx, at: Vector3, scale: number): (Model?, { Model })
	local src = eggModel()
	local egg: Model? = nil
	if src then
		egg = src:Clone()
		local e = egg :: Model
		local _, ext = e:GetBoundingBox()
		e:ScaleTo(e:GetScale() * (SHOW.eggHeight * scale) / math.max(0.1, ext.Y))
		for _, d in e:GetDescendants() do
			if d:IsA("BasePart") then
				d.Anchored, d.CanCollide, d.CanQuery = true, false, false
			end
		end
		e.Parent = ctx.folder
	end
	-- it hangs in the frost chains over the rune circle, swaying a little and turning slowly; st.eggY is
	-- its height over the floor (the drop eases it down), st.shake how hard it trembles (the build-up)
	local st = ctx.stage
	local h = SHOW.eggHeight * scale
	st.eggY, st.shake = HANG_Y, 0
	chains(ctx, at + Vector3.new(0, HANG_Y + h * 0.45, 0))
	local conn = RunService.RenderStepped:Connect(function()
		local t = os.clock()
		local calm = if ctx.reduced then 0 else 1
		local sway = Vector3.new(math.sin(t * 1.1) * 0.35, 0, math.cos(t * 0.9) * 0.25) * calm * (if st.eggY > h then 1 else 0)
		local tremble = CFrame.Angles(0, 0, math.rad((math.random() - 0.5) * 6 * st.shake * calm))
		if egg then
			egg:PivotTo(CFrame.new(at + Vector3.new(0, st.eggY, 0) + sway) * CFrame.Angles(0, t * 0.4, 0) * tremble)
		end
	end)
	table.insert(ctx.conns, conn)
	return egg, {}
end

-- the drop: the last chain gone, the egg falls onto the rune circle, which lights up; a ring of light runs
-- out across the floor, the camera shakes once
local function drop(ctx: Ctx, at: Vector3, scale: number)
	local st = ctx.stage
	local h = SHOW.eggHeight * scale
	local y0, y1 = st.eggY, h / 2 + 0.35
	local t0 = os.clock()
	local s = 0.32 * (if ctx.reduced then 0.5 else 1)
	while not ctx.finished do
		local u = math.min(1, (os.clock() - t0) / s)
		st.eggY = y0 + (y1 - y0) * u * u
		if u >= 1 then
			break
		end
		RunService.RenderStepped:Wait()
	end
	SoundController.play("slam")
	SoundController.play("rebirth_hit")
	ctx.kickUntil = os.clock() + 0.35
	lightRune(ctx)
	local floorWave = part(ctx, Vector3.new(0.2, 2, 2), Theme.white, 0.3, true)
	floorWave.Shape = Enum.PartType.Cylinder
	local w0 = os.clock()
	task.spawn(function()
		while floorWave.Parent and not ctx.finished do
			local u = math.min(1, (os.clock() - w0) / 0.7)
			local r = 2 + 24 * (1 - (1 - u) ^ 3)
			floorWave.Size = Vector3.new(0.2, r * 2, r * 2)
			floorWave.CFrame = CFrame.new(at + Vector3.new(0, 0.45, 0)) * CFrame.Angles(0, 0, math.rad(90))
			floorWave.Transparency = 0.3 + 0.7 * u
			if u >= 1 then
				break
			end
			RunService.RenderStepped:Wait()
		end
		floorWave:Destroy()
	end)
	local dust = part(ctx, Vector3.one * 0.3, Theme.white, 1)
	dust.Position = at + Vector3.new(0, 0.6, 0)
	local d = sparkles(dust, Color3.fromRGB(220, 230, 255), 0, 16)
	d.SpreadAngle = Vector2.new(10, 180)
	d.EmissionDirection = Enum.NormalId.Top
	d:Emit(if ctx.reduced then 15 else 45)
end

-- one honest crack: shake, a light crack line, a spark burst, a shockwave on the floor, a small kick
local function crack(ctx: Ctx, egg: Model?, at: Vector3, color: Color3, n: number, scale: number)
	SoundController.play("crack")
	SoundController.play("ice_tap")
	ctx.kickUntil = os.clock() + 0.18
	local h = SHOW.eggHeight * scale
	-- a glowing crack: a thin bright bar on the egg's surface, at a new angle each time
	local a = n * 2.1
	local bar = part(ctx, Vector3.new(0.18 * scale, h * (0.3 + n * 0.08), 0.18 * scale), color, 0.05, true)
	bar.CFrame = CFrame.new(at + Vector3.new(math.cos(a) * h * 0.36, h / 2 + 0.6 + (n % 2 - 0.5) * h * 0.2, math.sin(a) * h * 0.36)) * CFrame.Angles(0, -a, math.rad(25 - n * 15))
	local pop = part(ctx, Vector3.one * 0.3, color, 1)
	pop.Position = bar.Position
	local e = sparkles(pop, color, 0, 12)
	e:Emit(if ctx.reduced then 8 else 26)
	-- shockwave
	local wave = part(ctx, Vector3.new(0.2, 2, 2), color, 0.65, true) -- light, so stacked waves don't paint the floor
	wave.Shape = Enum.PartType.Cylinder
	local t0 = os.clock()
	task.spawn(function()
		while wave.Parent and not ctx.finished do
			local u = math.min(1, (os.clock() - t0) / 0.55)
			local r = 2 + 22 * (1 - (1 - u) ^ 3)
			wave.Size = Vector3.new(0.2, r * 2, r * 2)
			wave.CFrame = CFrame.new(at + Vector3.new(0, 0.5, 0)) * CFrame.Angles(0, 0, math.rad(90))
			wave.Transparency = 0.65 + 0.35 * u
			if u >= 1 then
				break
			end
			RunService.RenderStepped:Wait()
		end
		wave:Destroy()
	end)
	-- hit-stop shiver on the egg (Animation Rules 8), none with reduced motion
	if egg and not ctx.reduced then
		local base = egg:GetPivot()
		task.spawn(function()
			for _ = 1, 6 do
				if not egg.Parent then
					break
				end
				egg:PivotTo(base * CFrame.Angles(0, 0, math.rad((math.random() - 0.5) * 10)))
				task.wait(0.03)
			end
		end)
	end
end

-- the star flare: a long bright cross that grows from a point, in the tier's colour (the reference rolls)
local function starFlare(ctx: Ctx, at: Vector3, color: Color3, size: number): BillboardGui
	local holder = part(ctx, Vector3.one * 0.2, color, 1)
	holder.Position = at
	local g = Instance.new("BillboardGui")
	g.Size = UDim2.fromScale(0.5, 0.5)
	g.LightInfluence = 0
	g.AlwaysOnTop = true
	g.Adornee = holder
	g.Parent = holder
	local fade = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(1, 1) })
	for _, spec in { { 1, 0.06, 0 }, { 0.06, 1, 0 }, { 0.5, 0.035, 45 }, { 0.5, 0.035, -45 } } do
		local bar = Instance.new("Frame")
		bar.AnchorPoint = Vector2.new(0.5, 0.5)
		bar.Position = UDim2.fromScale(0.5, 0.5)
		bar.Size = UDim2.fromScale(spec[1], spec[2])
		bar.Rotation = spec[3]
		bar.BackgroundColor3 = Theme.white
		bar.BorderSizePixel = 0
		local grad = Instance.new("UIGradient")
		grad.Transparency = fade
		grad.Color = ColorSequence.new(color, Theme.white)
		grad.Rotation = if spec[2] > spec[1] then 90 else 0
		grad.Parent = bar
		bar.Parent = g
	end
	local core = Instance.new("ImageLabel")
	core.BackgroundTransparency = 1
	core.Image = Config.images.icons.sunburst
	core.ImageColor3 = color
	core.AnchorPoint = Vector2.new(0.5, 0.5)
	core.Position = UDim2.fromScale(0.5, 0.5)
	core.Size = UDim2.fromScale(0.6, 0.6)
	core.Parent = g
	local s = SHOW.flare * (if ctx.reduced then 0.5 else 1)
	TweenService:Create(g, TweenInfo.new(s, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = UDim2.fromScale(size, size) }):Play()
	if not ctx.reduced then
		task.spawn(function()
			local t0 = os.clock()
			while g.Parent and not ctx.finished do
				core.Rotation = (os.clock() - t0) * 60
				RunService.RenderStepped:Wait()
			end
		end)
	end
	return g
end

-- burst: flash, spinning rays, a thin light pillar (Legendary+), shell pieces flying, confetti
local function burst(ctx: Ctx, egg: Model?, rings: { Model }, at: Vector3, color: Color3, tier: string, scale: number)
	SoundController.play(if tier == "Mythic" or tier == "Legendary" then "reveal_secret" else "reveal_rare")
	SoundController.play("slam")
	flash(ctx, Theme.white, if ctx.reduced then 0.25 else 0.45)
	ctx.kickUntil = os.clock() + 0.3
	local h = SHOW.eggHeight * scale
	local mid = at + Vector3.new(0, h / 2 + 0.6, 0)
	-- shell shards fly out
	if egg then
		for _, d in egg:GetDescendants() do
			if d:IsA("BasePart") then
				d.Transparency = 1
			end
		end
	end
	for i = 1, (if ctx.reduced then 6 else 14) do
		local sh = part(ctx, Vector3.new(1.2, 1.6, 0.4) * scale, Color3.fromRGB(170, 220, 255), 0.15, true)
		sh.Material = Enum.Material.Glass
		sh.CFrame = CFrame.new(mid)
		local dir = Vector3.new(math.random() - 0.5, math.random() * 0.8 + 0.2, math.random() - 0.5).Unit
		TweenService:Create(sh, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			CFrame = CFrame.new(mid + dir * (14 + math.random() * 8)) * CFrame.Angles(math.random() * 6, math.random() * 6, 0),
			Transparency = 1,
		}):Play()
	end
	for _, r in rings do
		r:Destroy()
	end
	table.clear(rings)
	-- the sunburst: big see-through blades in a wall behind the egg, facing the camera, filling the screen and
	-- turning slowly (Boo Town's best moment, in the tier's colour; Mythic in the three aurora colours).
	-- They stay up behind the reveal and fade slowly.
	local camDir = Vector3.new(math.sin(ctx.orbit), 0, -math.cos(ctx.orbit))
	local wallAt = mid - camDir * 10
	local base = CFrame.lookAt(wallAt, wallAt + camDir)
	local nRays = if tier == "Mythic" then 18 elseif tier == "Legendary" then 16 else 12
	local blades: { BasePart } = {}
	for i = 1, nRays do
		-- the tier colour, two shades (a whitened blade swallowed the white Frost Lynx in the video)
		local col = if tier == "Mythic" then AURORA[(i % 3) + 1] elseif i % 2 == 0 then color else color:Lerp(Color3.new(0, 0, 0), 0.25)
		local blade = part(ctx, Vector3.new(if i % 2 == 0 then 5 else 2.5, 90, 0.2), col, 0.5, true)
		blades[i] = blade
	end
	local r0 = os.clock()
	table.insert(ctx.conns, RunService.RenderStepped:Connect(function()
		local t = os.clock() - r0
		local grow = math.min(1, t / 0.3)
		local spin = t * (if ctx.reduced then 0.05 else 0.25)
		for i, b in blades do
			local a = (i - 1) / nRays * math.pi * 2 + spin
			-- they start 7 studs out: a clear dark disc right behind the pet keeps it readable
			b.Size = Vector3.new(b.Size.X, 90 * grow, 0.2)
			b.CFrame = base * CFrame.Angles(0, 0, a) * CFrame.new(0, 7 + 45 * grow, 0)
			b.Transparency = math.min(0.85, 0.45 + t * 0.06)
		end
	end))
	-- a thin see-through light pillar for the rare ones (never fat: never hide the reward)
	if tier == "Legendary" or tier == "Mythic" then
		local pil = part(ctx, Vector3.new(400, 3, 3), color, 0.45, true)
		pil.Shape = Enum.PartType.Cylinder
		pil.CFrame = CFrame.new(at + Vector3.new(0, 200, 0)) * CFrame.Angles(0, 0, math.rad(90))
		TweenService:Create(pil, TweenInfo.new(2.5), { Transparency = 1, Size = Vector3.new(400, 0.6, 0.6) }):Play()
	end
	-- confetti
	local c = part(ctx, Vector3.one * 0.3, color, 1)
	c.Position = mid
	local conf = Instance.new("ParticleEmitter")
	conf.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	conf.Color = if tier == "Mythic" then ColorSequence.new(AURORA[1], AURORA[3]) else ColorSequence.new(color, Theme.white)
	conf.LightEmission = 1
	conf.Lifetime = NumberRange.new(1.2, 2.2)
	conf.Speed = NumberRange.new(16, 30)
	conf.SpreadAngle = Vector2.new(180, 180)
	conf.Acceleration = Vector3.new(0, -18, 0)
	conf.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(1, 0) })
	conf.Rate = 0
	conf.Parent = c
	conf:Emit(if ctx.reduced then 30 else 90)
end

-- the pet rises turning out of the light, then lands and stands animated (idle) facing the camera
local function rise(ctx: Ctx, key: string, at: Vector3): Model?
	local def = PetDefs.get(key)
	if not def then
		return nil
	end
	local size = PetDefs.height(def, nil) * SHOW.petHeightMul
	-- the pet's own skinned model, posed here with PetRig and its idle clip. (PetVisuals.driver follows a
	-- server root's replayed path and put the mesh ~43 studs under the stage in the first play test.)
	local models = ReplicatedStorage:FindFirstChild("PetModels")
	local src = models and models:FindFirstChild(def.model or key)
	if not (src and src:IsA("Model")) then
		return nil
	end
	local model = src:Clone()
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored, d.CanCollide, d.CanQuery, d.CanTouch = true, false, false, false
			if size >= Config.petShadowMaxHeight then
				d.CastShadow = false -- a big pet's own shadow turns it dark (PetVisuals)
			end
		end
	end
	local rh = model:GetAttribute("RigHeight")
	local h0 = if typeof(rh) == "number" and rh > 0 then rh else model:GetExtentsSize().Y
	model:ScaleTo(model:GetScale() * size / math.max(0.01, h0))
	local camDir = Vector3.new(math.sin(ctx.orbit), 0, -math.cos(ctx.orbit))
	local mid = at + Vector3.new(0, size / 2, 0)
	-- pets face -Z, and lookAt points -Z at the target: the camera's side
	local facing = CFrame.lookAt(mid, mid + camDir)
	model:PivotTo(facing)
	model.Parent = ctx.folder
	local rig = if model:GetAttribute("Skinned") then PetRig.new(model) else nil
	local idle = if rig then PetClips.get(rig.plan, "idle") else nil
	local parts, cfs = {}, {}
	local t0 = os.clock()
	local s = SHOW.rise * (if ctx.reduced then 0.5 else 1)
	table.insert(ctx.conns, RunService.RenderStepped:Connect(function()
		if not model.Parent then
			return
		end
		local now = os.clock() - t0
		local u = math.min(1, now / s)
		local e = 1 - (1 - u) ^ 3
		local lift = (1 - e) * 6
		local turn = (1 - e) * math.pi * 2 * (if ctx.reduced then 0 else 1)
		local base = facing * CFrame.Angles(0, turn, 0) + Vector3.new(0, lift, 0)
		if rig and idle then
			table.clear(parts)
			table.clear(cfs)
			local vals = PetRig.sample(rig, { { clip = idle, t = (now % idle.s) / idle.s, w = 1, name = "idle" } })
			local cf = PetRig.apply(rig, vals, base, parts, cfs)
			workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
			model.WorldPivot = cf
		else
			model:PivotTo(base)
		end
	end))
	-- a glow on the pet itself while it rises
	local hl = Instance.new("Highlight")
	hl.FillColor = Theme.white
	hl.FillTransparency = 0.2
	hl.OutlineTransparency = 1
	hl.Adornee = model
	hl.Parent = ctx.folder
	TweenService:Create(hl, TweenInfo.new(s), { FillTransparency = 1 }):Play()
	return model
end

-- the words: rarity above, the name slamming in letter by letter over a sunburst, the income line
local function nameCard(ctx: Ctx, r: any)
	local e = LimitedEgg.pet(r.key)
	local def = PetDefs.get(r.key)
	if not e or not def then
		return
	end
	local color = FLARE[e.tier] or Theme.coin
	local holder = Instance.new("Frame")
	holder.Name = "Words"
	holder.BackgroundTransparency = 1
	holder.Position = UDim2.fromScale(0, 0.03) -- the name at the top, the pet in the middle, OK at the bottom
	holder.Size = UDim2.fromScale(1, 0.3)
	holder.ZIndex = 20
	holder.Parent = ctx.gui
	local sun = Instance.new("ImageLabel")
	sun.BackgroundTransparency = 1
	sun.Image = Config.images.icons.sunburst
	sun.ImageColor3 = color
	sun.ImageTransparency = 0.35
	sun.AnchorPoint = Vector2.new(0.5, 0.5)
	sun.Position = UDim2.fromScale(0.5, 0.42)
	sun.Size = UDim2.fromScale(0.5, 1.4)
	sun.ZIndex = 20
	local sa = Instance.new("UIAspectRatioConstraint")
	sa.Parent = sun
	sun.Parent = holder
	if not ctx.reduced then
		task.spawn(function()
			while sun.Parent and not ctx.finished do
				sun.Rotation += 0.6
				RunService.RenderStepped:Wait()
			end
		end)
	end
	local tierWord = Ui.label(holder, spaced(string.upper(e.tier)), UDim2.fromScale(0.4, 0.16), UDim2.fromScale(0.3, 0.0))
	-- white letters tinted by a light gradient, on a thick ink outline: the tier colour alone was lost on violet
	tierWord.TextColor3 = Theme.white
	tierWord.ZIndex = 22
	local tws = tierWord:FindFirstChildOfClass("UIStroke")
	if tws then
		tws.Thickness = 3
	end
	if e.tier ~= "Mythic" then
		local tg = Instance.new("UIGradient")
		tg.Color = ColorSequence.new(color:Lerp(Theme.white, 0.45), color:Lerp(Theme.white, 0.1))
		tg.Rotation = 90
		tg.Parent = tierWord
	end
	if e.tier == "Mythic" then
		local g = Instance.new("UIGradient")
		g.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, AURORA[1]), ColorSequenceKeypoint.new(0.5, AURORA[2]), ColorSequenceKeypoint.new(1, AURORA[3]) })
		g.Parent = tierWord
	end
	-- the name, letter by letter
	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.Position = UDim2.fromScale(0.1, 0.17)
	row.Size = UDim2.fromScale(0.8, 0.42)
	row.ZIndex = 22
	row.Parent = holder
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Parent = row
	local name = string.upper(def.name)
	local per = math.min(0.07, 0.8 / math.max(1, #name))
	local step = (SHOW.name * 0.6 * (if ctx.reduced then 0.5 else 1)) / math.max(1, #name)
	for i = 1, #name do
		local ch = name:sub(i, i)
		local l = Ui.label(row, ch, UDim2.fromScale(per / 0.8 * (if ch == " " then 0.5 else 1), 1), UDim2.fromScale(0, 0))
		l.LayoutOrder = i
		l.ZIndex = 23
		l.TextColor3 = Theme.white
		local s = l:FindFirstChildOfClass("UIStroke")
		if s then
			s.Thickness = 3
		end
		if not ctx.reduced then
			local sc = Instance.new("UIScale")
			sc.Scale = 2.4
			sc.Parent = l
			l.TextTransparency = 1
			task.delay(i * step, function()
				l.TextTransparency = 0
				TweenService:Create(sc, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
				if i % 2 == 1 then
					SoundController.play("tink")
				end
			end)
		end
	end
	local line = `{math.floor(e.pct * 100)}% of your best pet  ·  +{Ui.short(r.inc)}/s`
	if r.odds < 100 then -- the hub stand's straight buy has no odds to show
		line ..= `  ·  {oneIn(r.odds)}`
	end
	if r.new then
		line = "NEW!  " .. line
	end
	local sub = Ui.label(holder, line, UDim2.fromScale(0.7, 0.14), UDim2.fromScale(0.15, 0.62))
	sub.TextColor3 = Theme.coin
	sub.ZIndex = 22
	hold(ctx, SHOW.name, true)
	if e.tier == "Mythic" or e.tier == "Legendary" then
		SoundController.play("rebirth_fanfare")
	end
end

-- 3 / 10 eggs: a row of small cards fills in one by one (Animation Rules 8: tally), each in its tier colour
local function tally(ctx: Ctx)
	local holder = Instance.new("Frame")
	holder.Name = "Tally"
	holder.BackgroundTransparency = 1
	holder.AnchorPoint = Vector2.new(0.5, 0)
	holder.Position = UDim2.fromScale(0.5, 0.835) -- low, under the pet's feet: the name card takes the top later
	holder.Size = UDim2.fromScale(0.9, 0.075)
	holder.ZIndex = 30
	holder.Parent = ctx.gui
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0.006, 0)
	layout.Parent = holder
	local n = #ctx.results
	for i, r in ctx.results do
		local def = PetDefs.get(r.key)
		local tc = Theme.tiers[r.tier] or Theme.info
		local b = Ui.block(holder, "R" .. i, tc, "", nil)
		b.root.Size = UDim2.fromScale(math.min(0.095, 0.95 / n), 1)
		b.root.LayoutOrder = i
		b.text.Visible = false
		local a = Instance.new("UIAspectRatioConstraint")
		a.AspectRatio = 0.85
		a.Parent = b.root
		if def then
			Ui.petPicture(b.face, def, UDim2.fromScale(0.9, 0.9), UDim2.fromScale(0.05, 0.02))
		end
		local sc = Instance.new("UIScale")
		sc.Scale = if ctx.reduced then 1 else 0
		sc.Parent = b.root
		if not ctx.reduced then
			TweenService:Create(sc, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		end
		SoundController.play(if Config.tier(r.tier).rank >= 5 then "unlock" else "tink")
		hold(ctx, SHOW.tallyEach)
	end
end

local function finish(ctx: Ctx)
	if ctx.finished then
		return
	end
	ctx.finished = true
	if running == ctx then
		running = nil
	end
	for _, c in ctx.conns do
		c:Disconnect()
	end
	table.clear(ctx.conns)
	ctx.folder:Destroy()
	ctx.gui:Destroy()
	if ctx.cam then
		ctx.cam = nil
		CameraController.giveBack()
	end
	local c = ctx.controls
	if c and c.hum.Parent then
		c.hum.WalkSpeed, c.hum.JumpPower, c.hum.JumpHeight = c.walk, c.jump, c.jumpH
	end
	if not running then
		Screen.setHidden(false)
	end
	State.send("Egg", { op = "seen" }) -- SKIP shows from the next egg on (seenShows.egg)
end

local function okButton(ctx: Ctx)
	local done = false
	local b = Ui.block(ctx.gui, "OK", Theme.go, "OK", function()
		SoundController.play("click")
		done = true
	end)
	b.root.AnchorPoint = Vector2.new(0.5, 0.5)
	b.root.Position = UDim2.fromScale(0.5, 0.95)
	b.root.Size = UDim2.fromScale(0.16, 0.08)
	b.root.ZIndex = 30
	local a = Instance.new("UIAspectRatioConstraint")
	a.AspectRatio = 2.6
	a.Parent = b.root
	while not done and not ctx.finished do
		RunService.RenderStepped:Wait()
	end
end

local function skipButton(ctx: Ctx)
	if SettingsController.get("skipShows") == true then
		ctx.skipped = true
		return
	end
	local seen = State.view and State.view.seenShows
	if not (seen and seen.egg) then
		return -- the first egg always plays in full
	end
	local b = Ui.block(ctx.gui, "Skip", Theme.info, "SKIP", function()
		ctx.skipped = true
		local s = ctx.gui:FindFirstChild("Skip")
		if s then
			s:Destroy()
		end
	end)
	b.root.AnchorPoint = Vector2.new(1, 0)
	b.root.Position = UDim2.fromScale(0.97, 0.04)
	b.root.Size = UDim2.fromScale(0.1, 0.06)
	b.root.ZIndex = 45
end

function EggController.play(data: any)
	if running or typeof(data) ~= "table" or typeof(data.results) ~= "table" or #data.results == 0 then
		return
	end
	local char = me.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then
		return
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "EggShow"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 60
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = me:WaitForChild("PlayerGui")
	local folder = Instance.new("Folder")
	folder.Name = "EggStage"
	folder.Parent = workspace
	local ctx: Ctx = {
		results = data.results, reduced = reduced(), skipped = false, finished = false, folder = folder, gui = gui,
		cam = nil, conns = {}, center = hrp.Position + Vector3.new(0, SHOW.stageHeight, 0), kickUntil = 0,
		orbit = 0, orbitR = 34, orbitH = 7, look = hrp.Position, controls = nil,
	}
	running = ctx
	Screen.setHidden(true)
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum then
		ctx.controls = { hum = hum, walk = hum.WalkSpeed, jump = hum.JumpPower, jumpH = hum.JumpHeight }
		hum.WalkSpeed, hum.JumpPower, hum.JumpHeight = 0, 0, 0
	end
	local ok, err = pcall(function()
		-- the stage and camera are ready under the title card, so it fades straight onto the arena
		-- (built after it, one frame of the daytime sky showed through)
		stage(ctx)
		camera(ctx)
		ctx.orbitR, ctx.orbitH, ctx.look = 26, 3, ctx.center + Vector3.new(0, HANG_Y + 1, 0)
		titleCard(ctx)
		skipButton(ctx)
		local best = ctx.results[#ctx.results] -- the server sends best last
		local tier = best.tier
		local color = FLARE[tier] or Theme.coin
		if #ctx.results > 1 then
			tally(ctx)
		end
		-- arrival: the egg hangs in its frost chains; the camera starts low and wide, looking up at it
		local egg, rings = arrive(ctx, ctx.center, 1)
		tweenCam(ctx, 21, 4, HANG_Y, SHOW.arrival)
		hold(ctx, SHOW.arrival)
		-- heartbeat: the chains snap one at a time (every egg: this part never hints at the rarity)
		local eggMid = ctx.center + Vector3.new(0, HANG_Y, 0)
		for k = 1, CHAINS do
			snap(ctx, k, eggMid)
			tweenCam(ctx, 21 - k * 1, 4, HANG_Y - k * 0.6, 0.35)
			hold(ctx, if k == CHAINS then 0.25 else 0.42)
		end
		-- the drop onto the rune circle
		drop(ctx, ctx.center, 1)
		tweenCam(ctx, 25, 6, 5, 0.5)
		hold(ctx, 0.45)
		-- honest build-up: one crack per step above Rare, the egg trembling harder each time
		for n = 1, CRACKS[tier] or 1 do
			ctx.stage.shake = n / 4
			crack(ctx, egg, ctx.center, color, n, 1)
			tweenCam(ctx, 25 - n * 2, 6, 5, SHOW.crack)
			hold(ctx, SHOW.crack)
		end
		-- a breath in: it goes still for a moment, then...
		ctx.stage.shake = 0
		hold(ctx, 0.18)
		local flare = starFlare(ctx, ctx.center + Vector3.new(0, SHOW.eggHeight / 2 + 0.6, 0), color, if tier == "Mythic" then 3.2 elseif tier == "Legendary" then 2.4 else 1.6)
		hold(ctx, SHOW.flare)
		burst(ctx, egg, rings, ctx.center, color, tier, 1)
		flare:Destroy()
		hold(ctx, SHOW.burst, true)
		local model = rise(ctx, best.key, ctx.center + Vector3.new(0, 0.3, 0))
		local _ = model
		-- the pet in the middle of the shot, a little low: its name sits at the top, OK at the bottom
		-- framed by the pet's size, so a small Rare fills the shot as well as the big dragon
		local def = PetDefs.get(best.key)
		local ph = (if def then PetDefs.height(def, nil) else 4) * SHOW.petHeightMul
		tweenCam(ctx, ph * 2.3, ph * 0.45, ph * 0.72, SHOW.rise)
		hold(ctx, SHOW.rise, true)
		nameCard(ctx, best)
		hold(ctx, SHOW.hold, true)
		okButton(ctx)
	end)
	finish(ctx)
	if not ok then
		warn("[EggController] show failed:", err)
	end
end

function EggController.Init()
	ClientHooks.shopTop = banner
	ClientHooks.indexExtra = limitedPage
end

function EggController.Start()
	State.Notify:Connect(function(kind: string, data: any)
		if kind == "eggView" and typeof(data) == "table" then
			view = data
		elseif kind == "eggHatch" then
			task.spawn(EggController.play, data)
		end
	end)
end

return EggController
