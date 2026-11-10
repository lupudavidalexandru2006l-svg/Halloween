--!strict
-- HudController: the HUD's contents: the menu tiles (Pets, Shop, Index, Settings), the coins with
-- +N/s, the island banner (drops in when you walk onto an island) and the banner (Big Chill, others'
-- big wins, "not yet" answers). Screen places all of them. Owner 2026-11-07: the goal bar and the
-- temperature chip are gone; the island banner shows each island's heat as you arrive.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
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

local HudController = {}

local coinsRoot: Frame
local coinsText: TextLabel
local coinsRate: TextLabel
local powerRoot: Frame -- Cold Power: its icon and number, under the coins
local powerText: TextLabel
local powerScale: UIScale
local lastPower: number? = nil
local banner: Ui.Block
local dailyDot: Frame? = nil -- a round dot on the Daily tile while a finished challenge waits to be claimed

local bannerUntil = 0

function HudController.banner(textValue: string, color: Color3?, seconds: number?)
	banner.text.Text = textValue
	banner.face.BackgroundColor3 = color or Theme.info
	banner.root.BackgroundColor3 = Ui.darker(color or Theme.info)
	banner.root.Visible = true
	local untilAt = os.clock() + (seconds or Config.ui.bannerSeconds)
	bannerUntil = untilAt
	task.delay(seconds or Config.ui.bannerSeconds, function()
		if bannerUntil == untilAt then
			banner.root.Visible = false
		end
	end)
end

-- gain text appears beside the coin counter, never on a HUD item. It wears the counter's own look
-- (white-to-gold fill, the firm outline) a size smaller, starts just past the number's visible end
-- (owner 2026-11-05: it sat on the last digit in flat yellow), pops in, then drifts up and fades.
-- power = true: the same pop beside the Cold Power number, fading white to its cyan
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
	gold.Color = ColorSequence.new(Theme.white, if power then Theme.rink.power else Theme.coin)
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

local function render(v: State.View)
	if v.tester then
		ensureTesterTile()
	end
	coinsText.Text = Ui.commas(v.coins) -- the whole number, 1,508,273 not 1.5M (owner 2026-11-03)
	-- the friend bonus rides on the income line (no new HUD item): "+120/s  +20% friends"
	local f = v.friends or 0
	local friendsText = if f > 0
		then `  <font color="#{Theme.tiles.daily:ToHex()}">+{math.round(f * Config.friends.perFriend * 100)}% friends</font>`
		else ""
	coinsRate.Text = if v.income > 0 then `+{Ui.short(v.income)}/s{friendsText}` else ""
	coinsRate.Visible = v.income > 0
	-- Cold Power: the number, a "+N" beside it and a small bounce when it goes up (not on the first sync)
	local power = v.coldPower or 0
	powerText.Text = Config.powerText(power)
	if lastPower and power > lastPower then
		floatGain(power - lastPower, true)
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
local islandToken = 0
local islandShowing = false
local lastZone = -1 -- -1 = not checked yet, 0 = the hub
local lastShown: { [number]: number } = {}

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
	recLabel.TextSize = math.min(100, math.floor(ih * 0.9))
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
	rowIcon(infoRow, 2, Config.images.icons.ray)
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

-- the gun that can freeze this island's pets: the first one whose Cold reaches it
local function gunFor(id: number): string
	for _, g in Config.guns.list do
		if g.heat >= id then
			return g.name
		end
	end
	return Config.guns.list[#Config.guns.list].name
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
	gunText.Text = gunFor(zone.id)
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
	if PopupController.isOpen() then
		hideIsland(true)
		return
	end
	local id = WorldRules.zoneAt(root.Position)
	if id == lastZone then
		return
	end
	lastZone = id
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
	-- tiles
	local tiles = Instance.new("Frame")
	tiles.Name = "Tiles"
	tiles.BackgroundTransparency = 1
	local grid = Instance.new("UIGridLayout")
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = tiles
	tilesFrame = tiles
	for i, t in Config.ui.tiles do
		local b = Ui.block(tiles, t.id, Theme.tiles[t.id] or Theme.info, t.label, function()
			PopupController.open(t.id)
		end)
		b.root.LayoutOrder = i
		-- the painted icon on top, the name small underneath (prototype tiles)
		local icon = Config.ui.tileIcons[t.id]
		if icon then
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
	-- wider than the frame (it runs on to the right) so a long whole number keeps a big font
	coinsText = Ui.label(coinsRoot, "0", UDim2.fromScale(1.4, 0.62), UDim2.fromScale(0.34, 0))
	coinsText.TextXAlignment = Enum.TextXAlignment.Left
	-- wide enough for "+1.2K/s  +30% friends"; a short rate keeps its size (TextScaled caps at the height)
	coinsRate = Ui.label(coinsRoot, "", UDim2.fromScale(1.6, 0.34), UDim2.fromScale(0.35, 0.62))
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
	Screen.register("coins", coinsRoot)
	-- Cold Power under the coins, the same look a size smaller: icon, then the number in white-to-cyan
	powerRoot = Instance.new("Frame")
	powerRoot.Name = "Power"
	powerRoot.BackgroundTransparency = 1
	Ui.image(powerRoot, Config.images.icons.power, UDim2.fromScale(0.26, 0.96), UDim2.fromScale(0.04, 0.02))
	powerText = Ui.label(powerRoot, "0", UDim2.fromScale(1.4, 0.84), UDim2.fromScale(0.34, 0.08))
	powerText.TextXAlignment = Enum.TextXAlignment.Left
	local cyan = Instance.new("UIGradient")
	cyan.Rotation = 90
	cyan.Color = ColorSequence.new(Theme.white, Theme.rink.power)
	cyan.Parent = powerText
	local ps = powerText:FindFirstChildOfClass("UIStroke") :: UIStroke
	ps.Thickness = Config.ui.floatingStroke
	powerScale = Instance.new("UIScale")
	powerScale.Parent = powerText
	Screen.register("power", powerRoot)
	buildIsland()
	-- banner
	banner = Ui.block(Screen.hud :: ScreenGui, "Banner", Theme.info, "", nil)
	banner.root.Visible = false
	Screen.register("banner", banner.root)

	State.Changed:Connect(render)
	if State.view then
		render(State.view)
	end
	State.Notify:Connect(function(kind: string, data: any)
		if kind == "notYet" then
			HudController.banner(tostring(data.reason), Theme.no, Config.ui.notYetSeconds)
		elseif kind == "chillWarn" then
			HudController.banner(`Big Chill in {data.inSeconds} s!`, Theme.info)
		elseif kind == "chillStart" then
			if typeof(data.by) == "string" then
				HudController.banner(`{data.by} started a Big Chill for everyone!`, Theme.info, data.seconds)
			else
				HudController.banner("Big Chill! Nothing melts", Theme.info, data.seconds)
			end
		elseif kind == "nightStart" then
			HudController.banner("Night time! Pets are sleeping", Theme.info)
		elseif kind == "nightEnd" then
			HudController.banner("Good morning!", Theme.info)
		elseif kind == "bigWin" then
			local def = PetDefs.get(data.key)
			if def then
				HudController.banner(`{data.name} caught a {string.upper(def.tier)} {def.name}!`, Theme.tiers[def.tier])
			end
		elseif kind == "shoutout" then
			-- a Secret was frozen somewhere on the server (the freezer sees their own show instead)
			local def = PetDefs.get(data.key)
			if def and data.userId ~= Players.LocalPlayer.UserId then
				HudController.banner(`{data.name} froze a {string.upper(def.tier)} {def.name}!`, Theme.tierGlow[def.tier] or Theme.coin)
			end
		elseif kind == "banked" then
			-- no "+N/s in your pan" banner (owner 2026-11-07: take the income text off); Epic and up still get named
			local best = nil :: PetDefs.PetDef?
			for _, b in data.banked do
				local def = PetDefs.get(b.key)
				if def and (not best or Config.tier(def.tier).rank > Config.tier(best.tier).rank) then
					best = def
				end
			end
			if best and Config.tier(best.tier).rank >= Config.effects.showRank then
				HudController.banner(`{string.upper(best.tier)}! {best.name}`, Theme.tiers[best.tier]) -- prototype: Epic and up get the show
			else
				-- it's in your Pets, still frozen: the guide arrow points at your Thaw Machine (owner 2026-11-09)
				HudController.banner("Put it in your Thaw Machine!", Theme.go)
			end
		elseif kind == "zoneUnlocked" then
			local z = Config.zone(if typeof(data.zone) == "number" then data.zone else 2)
			HudController.banner(`{if z then z.name else "The next island"} is open!`, Theme.go)
		elseif kind == "refund" and typeof(data) == "table" and typeof(data.coins) == "number" then
			-- the pan's Cold Level was removed (Cold Power, 2026-11-10): what you spent on it is back
			HudController.banner(`Cold Level is gone. +{Ui.commas(data.coins)} coins back`, Theme.coin, Config.ui.bannerSeconds * 2)
		elseif kind == "comingSoon" then
			HudController.banner(`{tostring(data.label)}: coming soon!`, Theme.info)
		elseif kind == "upgraded" then
			local u = Config.upgrades[data.id]
			HudController.banner(`{u and u.name or "Upgrade"} level {data.level}!`, Theme.go)
		elseif kind == "welcomeCollected" or kind == "giftClaimed" then
			floatGain(data.coins)
		elseif kind == "melted" then
			HudController.banner("It melted! Zap it again", Theme.info)
		elseif kind == "chargeSaved" then
			HudController.banner("Super Freeze saved for next time", Theme.info)
		elseif kind == "robuxBought" then
			-- a Robux shop item arrived (saved first, MonetizationService)
			if data.chill then
				-- nothing here: the server-wide "<name> started a Big Chill for everyone!" is the thank-you
			elseif (data.coins or 0) > 0 then
				HudController.banner(`{data.name}! +{Ui.short(data.coins)} coins`, Theme.coin)
				floatGain(data.coins)
			elseif (data.power or 0) > 0 then
				HudController.banner(`{data.name}! +{Config.powerText(data.power)} Cold Power`, Theme.rink.power)
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
			HudController.banner("Slow Gel is on your hotbar!", Theme.go)
		elseif kind == "thawStarted" then
			local def = PetDefs.get(data.key)
			HudController.banner(`{if def then def.name else "Your pet"} is thawing: {Config.timeText(data.seconds or 0)}`, Theme.info)
		elseif kind == "thawed" then
			local def = PetDefs.get(data.key)
			local gone = if typeof(data.replaced) == "string" then PetDefs.get(data.replaced) else nil
			if gone then
				HudController.banner(`{if def then def.name else "Your pet"} is out! It took {gone.name}'s spot`, Theme.go)
			elseif data.stored then
				HudController.banner(`{if def then def.name else "Your pet"} is out! Pan full: it's in Storage`, Theme.info)
			else
				HudController.banner(`{if def then def.name else "Your pet"} is out!`, Theme.go) -- no income text (owner 2026-11-07)
			end
		elseif kind == "critterCaught" then
			HudController.banner("A Heat Critter grabbed your cube! Zap it back", Theme.round5.critter)
		elseif kind == "tagged" then
			HudController.banner(`{data.by} knocked your cube loose!`, Theme.round5.reticlePlayer)
		elseif kind == "tagHit" then
			HudController.banner("Cube knocked loose! Zap it", Theme.round5.reticlePlayer)
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
	task.spawn(function()
		while true do
			watchIsland()
			task.wait(0.25)
		end
	end)
end

return HudController
