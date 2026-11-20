--!strict
-- PopupController: owns every popup (Pets, Shop, Index, Settings, welcome back, gift, page done).
-- One at a time, centred a little above the middle; reward popups wait in a queue behind a menu.
-- Buttons only send intent; the server answers and the next "Data" redraws the popup.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SocialService = game:GetService("SocialService")
local GroupService = game:GetService("GroupService")
local TweenService = game:GetService("TweenService")
local Config = require(ReplicatedStorage.Shared.Config)
local Theme = require(ReplicatedStorage.Shared.Theme)
local PetDefs = require(ReplicatedStorage.Shared.PetDefs)
local Ui = require(script.Parent.Parent.Lib.Ui)
local State = require(script.Parent.State)
local Screen = require(script.Parent.Screen)
local InputController = require(script.Parent.InputController)
local SoundController = require(script.Parent.SoundController)
local SettingsController = require(script.Parent.SettingsController)
local EquipmentPopup = require(script.Parent.EquipmentPopup)
local PanPopup = require(script.Parent.PanPopup)
local SellPopup = require(script.Parent.SellPopup)
local MailPopup = require(script.Parent.MailPopup)
local RebirthPopup = require(script.Parent.RebirthPopup)

local PopupController = {}

-- update: set by popups that change their own labels instead of being rebuilt (the Tester panel)
type Open = { name: string, data: any, frame: Frame, body: Frame, first: GuiObject?, update: ((State.View) -> ())?, closed: boolean?, shown: string? }
local current: Open? = nil
local queue: { { name: string, data: any } } = {}
local shopKey: ((State.View) -> string)? = nil -- the Shop's "what it shows" key (set with the Shop below)
local boardStamp = 0 -- goes up each time a leaderboard's rows arrive, so its open popup is drawn again
local MENUS = { board = true, pets = true, shop = true, index = true, settings = true, tester = true, equipment = true, pan = true, sell = true, rebirth = true, thaw = true, daily = true, freeGift = true, mail = true }
local giftJoined: boolean? = nil -- this session's answer to "in the group?" for the Free Gift board (nil = not asked yet)
local TITLES: { [string]: string } = {
	pets = "Pets", shop = "Shop", index = "Index", settings = "Settings", tester = "Tester", equipment = "Equipment", daily = "Daily",
	pan = "Pan Upgrades", sell = "Sell Booth", rebirth = "Rebirth Booth", thaw = "Thaw Machine",
	welcome = "Welcome back!", gift = "Free gift!", freeGift = "Free gift!", pageDone = "Page complete!",
	mail = "Mailbox", mailThanks = "Mailbox",
}

-- what a scrolling menu shows; it's only rebuilt when this changes, so a coin tick doesn't throw
-- the list away (and the player's scroll and drag with it) every second (owner QA 2026-10-31).
-- Built field by field: State.Changed hands out a copy whose keys can come in another order, so
-- JSON of the two never matched.
local function shownData(name: string, v: State.View): string?
	local parts: { string } = {}
	if name == "pets" then
		table.insert(parts, tostring(v.slots))
		table.insert(parts, tostring(v.thawSkipAlls or 0)) -- the Unfreeze all bar turns free / paid
		for _, p in v.pets do
			table.insert(parts, `{p.id},{p.key},{p.pose},{p.mut},{p.sz},{p.eq},{p.income},{p.frozen},{p.thawM}`)
		end
	elseif name == "thaw" then
		table.insert(parts, tostring(v.machines))
		table.insert(parts, tostring(v.thawSkips or 0))
		table.insert(parts, tostring(v.thawSkipAlls or 0))
		for _, p in v.pets do
			if p.frozen then
				table.insert(parts, `{p.id},{p.thawM}`)
			end
		end
	elseif name == "index" then
		for _, p in v.pages do
			table.insert(parts, `{p.zone},{p.found},{p.total},{p.complete},{p.secretFound},{p.claimed}`)
		end
		local keys: { string } = {}
		for key, on in v.found do
			if on then
				table.insert(keys, key)
			end
		end
		table.sort(keys)
		table.insert(parts, table.concat(keys, ","))
	elseif name == "daily" then
		for _, c in (if v.daily then v.daily.list else {}) do
			table.insert(parts, `{c.text},{c.goal},{c.have},{c.claimed}`)
		end
		table.insert(parts, tostring(if v.daily then v.daily.coins else 0))
		local ex = (v :: any).extras
		if ex then
			table.insert(parts, `L{ex.login.n},{ex.login.canClaim},{ex.login.nextCoins}`)
			for _, c in ex.weekly.list do
				table.insert(parts, `W{c.goal},{c.have},{c.claimed}`)
			end
			table.insert(parts, tostring(ex.weekly.coins))
		end
	elseif name == "equipment" then
		return EquipmentPopup.shownKey(v)
	elseif name == "pan" then
		return PanPopup.shownKey(v)
	elseif name == "sell" then
		return SellPopup.shownKey(v)
	elseif name == "rebirth" then
		return RebirthPopup.shownKey(v)
	elseif name == "shop" then
		return if shopKey then shopKey(v) else nil
	elseif name == "board" then
		return tostring(boardStamp)
	elseif name == "freeGift" then
		return `{v.gift.ready},{giftJoined}`
	elseif name == "mail" then
		-- nothing in the mailbox depends on your data. Before 2026-11-18 this was nil, so every coin tick redrew
		-- the popup and destroyed the message box mid-typing (owner: "writing in the feedback is very buggy")
		return "mail"
	else
		return nil
	end
	return table.concat(parts, ";")
end

local function tierColor(tier: string): Color3
	return Theme.tiers[tier] or Theme.ink
end

-- the title ribbon's colour: a menu wears its tile's colour, rewards wear the reward colours
local HEADER: { [string]: Color3 } = {
	welcome = Theme.coin, gift = Theme.gift, freeGift = Theme.gift, pageDone = Theme.go, tester = Theme.info, equipment = Theme.booths.equipment,
	pan = Theme.booths.pan, sell = Theme.booths.sell, rebirth = Theme.booths.rebirth, thaw = Theme.info,
	mail = Theme.info, mailThanks = Theme.go,
}
local SMALL = { welcome = true, gift = true, pageDone = true, mailThanks = true } -- short messages get a smaller panel
local FIT = { thaw = true } -- list popups that shrink to their rows (QA 2026-11-20, PT-04)
local HEADER_ICONS: { [string]: string } = {
	pets = Config.ui.tileIcons.pets, shop = Config.ui.tileIcons.shop, index = Config.ui.tileIcons.index,
	settings = Config.ui.tileIcons.settings, welcome = Config.images.icons.coin, gift = Config.images.icons.gift, freeGift = Config.images.icons.gift,
	daily = Config.ui.tileIcons.daily,
}

-- text sizes for the open popup, one per role (Config.ui.popupText x the popup's height)
local px: { [string]: number } = { title = 30, body = 22, small = 16, button = 20 }
-- each role's size is a cap: text that fits shows at exactly that size (so rows never jump), and only a
-- word too long for its box ("Glowshroom Mammoth", the X, Pan Upgrades titles) shrinks to fit instead of
-- being cut off (QA 2026-11-05, PT-04)
local function sized(t: TextLabel, role: string)
	local size = px[role] or px.body
	t.TextWrapped = true
	t.TextSize = size
	t.TextScaled = true
	local c = t:FindFirstChildOfClass("UITextSizeConstraint") or Instance.new("UITextSizeConstraint")
	c.MaxTextSize = math.max(1, math.floor(size))
	c.MinTextSize = math.max(1, math.floor(size * 0.5))
	c.Parent = t
end

-- a row of blocks laid out left to right; widths are fractions of the row
-- aspect: inside a scrolling list the height comes from the width (Scale of an auto-sized canvas would loop)
local function row(parent: Instance, order: number, height: number, aspect: number?): Frame
	local f = Instance.new("Frame")
	f.Name = "Row" .. order -- unique names, so QA tools can click a button by its path
	f.LayoutOrder = order
	f.BackgroundTransparency = 1
	f.Size = UDim2.fromScale(1, if aspect then 1 else height)
	if aspect and aspect >= 6 and Screen.deviceClass() ~= "pc" then
		-- touch screens: fewer, taller list rows (UI Rules), so a row's button is thumb-sized (mobile QA 2026-11-10:
		-- "In pen" was 29 px tall). Only long thin list rows; the Index pages and Sell grid keep their shape.
		aspect *= Config.ui.touchRowAspect
	end
	if aspect then
		local a = Instance.new("UIAspectRatioConstraint")
		a.AspectRatio = aspect
		a.DominantAxis = Enum.DominantAxis.Width
		a.Parent = f
	end
	f.Parent = parent
	return f
end

local function button(parent: Instance, color: Color3, text: string, x: number, w: number, onPress: () -> ()): Ui.Block
	local b = Ui.block(parent, text, color, text, function()
		SoundController.play("click")
		onPress()
	end)
	b.root.Position = UDim2.fromScale(x, 0.1)
	b.root.Size = UDim2.fromScale(w, 0.8)
	sized(b.text, "button")
	return b
end

-- dark text on the cream panel (white on cream washed out); role picks the shared size
local function text(parent: Instance, s: string, x: number, w: number, color: Color3?, role: string?): TextLabel
	local t = Ui.inkLabel(parent, s, UDim2.fromScale(w, 0.7), UDim2.fromScale(x, 0.15))
	t.TextXAlignment = Enum.TextXAlignment.Left
	if color then
		t.TextColor3 = color
	end
	sized(t, role or "body")
	return t
end

-- a flat white card behind one row of a list, a thin outline and no lip: calm, so the pet or the
-- price is the loudest thing in the row (owner 2026-10-31)
local function card(r: Frame): Frame
	local c = Instance.new("Frame")
	c.Name = "Card"
	c.BackgroundColor3 = Theme.white
	c.BorderSizePixel = 0
	c.Size = UDim2.fromScale(1, 1)
	Ui.corner(c)
	Ui.stroke(c, Config.ui.cardStroke)
	c.Parent = r
	return c
end

-- the coin image in front of a price (one coin image everywhere, UI Rules)
local function priceTag(b: Ui.Block)
	Ui.image(b.face, Config.images.icons.coin, UDim2.fromScale(0.3, 0.8), UDim2.fromScale(0.06, 0.1))
	b.text.Size = UDim2.fromScale(0.62, 0.8)
	b.text.Position = UDim2.fromScale(0.34, 0.1)
end

-- a rounded progress bar: a light track with an ink outline, a fill in `color` and the count centred
-- on top (owner 2026-11-09: a completion bar on every Index page, and one for all pets)
local function bar(parent: Instance, x: number, y: number, w: number, h: number, share: number, label: string, color: Color3): Frame
	local track = Instance.new("Frame")
	track.Name = "Bar"
	track.BackgroundColor3 = Theme.white
	track.BackgroundTransparency = Config.ui.barTrackAlpha
	track.BorderSizePixel = 0
	track.Position = UDim2.fromScale(x, y)
	track.Size = UDim2.fromScale(w, h)
	Ui.corner(track, 0.5)
	Ui.stroke(track)
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BackgroundColor3 = color
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(math.clamp(share, 0, 1), 1)
	fill.Visible = share > 0
	Ui.corner(fill, 0.5)
	local shine = Instance.new("UIGradient") -- a lighter top, like the blocks
	shine.Rotation = 90
	shine.Color = ColorSequence.new(color:Lerp(Theme.white, 0.45), color)
	shine.Parent = fill
	fill.Parent = track
	local t = Ui.inkLabel(track, label, UDim2.fromScale(0.96, 0.8), UDim2.fromScale(0.02, 0.1))
	t.Name = "Count"
	t.ZIndex = 2
	track.Parent = parent
	return track
end

-- the one focal point of a screen breathes gently (UI Rules: animate only what matters); still with Reduced motion
local function pulse(gui: GuiObject)
	if SettingsController.get("reducedMotion") == true then
		return
	end
	local s = Instance.new("UIScale")
	s.Parent = gui
	local P = Config.index.pulse
	TweenService:Create(s, TweenInfo.new(P.seconds, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Scale = P.scale }):Play()
end

-- the Starter Pack's card (owner 2026-11-19: "pulsating lowk"): a soft breathe and a warm glow ring that fades in
-- and out. Reduced motion: the ring stays lit, nothing moves.
local function starterGlow(root: GuiObject)
	local ring = Instance.new("UIStroke")
	ring.Name = "StarterGlow"
	ring.Color = Color3.fromHex("ffe066")
	ring.Thickness = 5
	ring.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	ring.LineJoinMode = Enum.LineJoinMode.Round
	ring.Parent = root
	if SettingsController.get("reducedMotion") == true then
		return
	end
	local s = Instance.new("UIScale")
	s.Parent = root
	local info = TweenInfo.new(1.1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
	TweenService:Create(s, info, { Scale = 1.025 }):Play()
	ring.Transparency = 0.7
	TweenService:Create(ring, info, { Transparency = 0 }):Play()
end

-- inside the first Config.starterPack.featureMinutes of play: the Shop opens on the Limited offers and the Starter
-- Pack pulses (it stays buyable after, just quieter)
local function starterFeatured(): boolean
	local ex = State.view and (State.view :: any).extras
	return ex ~= nil and ex.starter ~= true and (ex.playSeconds or 0) < Config.starterPack.featureMinutes * 60
end

local function list(body: Frame, scroll: boolean): GuiObject
	local holder: GuiObject
	if scroll then
		local sf = Instance.new("ScrollingFrame")
		sf.Name = "List"
		sf.BackgroundTransparency = 1
		sf.Size = UDim2.fromScale(1, 1)
		sf.CanvasSize = UDim2.fromScale(0, 0)
		sf.AutomaticCanvasSize = Enum.AutomaticSize.Y
		sf.ScrollBarThickness = 8
		sf.ScrollBarImageColor3 = Theme.ink
		-- the bar gets its own strip, and the content an inset, so the edge cards' outlines and lips
		-- aren't cut off at the sides or hidden under the bar (owner QA 2026-10-31)
		sf.VerticalScrollBarInset = Enum.ScrollBarInset.Always
		local pad = Instance.new("UIPadding")
		local P = Config.ui.listInset
		pad.PaddingLeft = UDim.new(P, 0)
		pad.PaddingRight = UDim.new(P, 0)
		pad.PaddingTop = UDim.new(P, 0)
		pad.PaddingBottom = UDim.new(P, 0)
		pad.Parent = sf
		holder = sf
	else
		local f = Instance.new("Frame")
		f.Name = "List"
		f.BackgroundTransparency = 1
		f.Size = UDim2.fromScale(1, 1)
		holder = f
	end
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0.015, 0)
	-- a short list sits in the middle of its space, not stuck to the top (owner: centre it)
	layout.VerticalAlignment = if scroll then Enum.VerticalAlignment.Top else Enum.VerticalAlignment.Center
	layout.Parent = holder
	if holder:IsA("ScrollingFrame") then
		-- AutomaticCanvasSize under-counts rows sized by an aspect ratio (the last rows of a long list
		-- could never be reached), so the canvas follows the measured content height instead
		local sf = holder
		sf.AutomaticCanvasSize = Enum.AutomaticSize.None
		local function fit()
			-- room for the top and bottom inset too, so the last row's lip isn't cut
			sf.CanvasSize = UDim2.fromOffset(0, layout.AbsoluteContentSize.Y + sf.AbsoluteSize.Y * Config.ui.listInset * 2)
		end
		-- inside a ScrollingFrame a Scale gap is a share of the canvas, and the canvas is set from the
		-- content, gaps included: with ~70+ rows it ran away to millions of pixels and the Pets, Sell and
		-- Tester lists showed empty (final QA 2026-11-03). Gaps here are pixels from the visible height.
		local function spacing()
			local h = sf.AbsoluteSize.Y
			layout.Padding = UDim.new(0, h * 0.015)
			local pad = sf:FindFirstChildOfClass("UIPadding")
			if pad then
				pad.PaddingTop = UDim.new(0, h * Config.ui.listInset)
				pad.PaddingBottom = UDim.new(0, h * Config.ui.listInset)
			end
			fit()
		end
		layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(fit)
		sf:GetPropertyChangedSignal("AbsoluteSize"):Connect(spacing)
		spacing()
	end
	holder.Parent = body
	return holder
end

-- the Robux mark and the price on a Robux button (Child Safety: every purchase shows the Robux icon),
-- centred together by their visible width (UI Rules: centre the visible shape)
local function robuxMark(face: GuiObject): ImageLabel
	local mark = Ui.image(face, Config.images.icons.robux, UDim2.fromScale(0.3, 0.62), UDim2.fromScale(0, 0.19))
	mark.ZIndex = 2
	-- owner 2026-11-13 "make the robux more contoured": a thick ink contour round a white mark, like the
	-- price's own outlined numbers. The slot stays empty; eight ink copies nudged round the white one draw it.
	mark.ImageTransparency = 1
	local o = Config.ui.shop.robuxOutline
	for k = 0, 8 do
		local a = k * math.pi / 4
		local copy = Instance.new("ImageLabel")
		copy.Name = if k == 8 then "Mark" else "Contour"
		copy.BackgroundTransparency = 1
		copy.Image = mark.Image
		copy.ScaleType = Enum.ScaleType.Fit
		copy.ImageColor3 = if k == 8 then Theme.white else Theme.ink
		copy.AnchorPoint = Vector2.new(0.5, 0.5)
		copy.Position = if k == 8 then UDim2.fromScale(0.5, 0.5) else UDim2.fromScale(0.5 + math.cos(a) * o, 0.5 + math.sin(a) * o)
		copy.Size = UDim2.fromScale(1, 1)
		copy.ZIndex = if k == 8 then 4 else 3
		copy.Parent = mark
	end
	return mark
end

local function robuxTag(b: Ui.Block)
	local mark = robuxMark(b.face)
	local stroke = b.text:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Thickness = Config.ui.floatingStroke -- the price wears the same firm outline
	end
	b.text.TextXAlignment = Enum.TextXAlignment.Left
	local function place()
		local w = math.max(1, b.face.AbsoluteSize.X)
		local markW, gap = mark.AbsoluteSize.X / w, 0.04
		local textW = math.min(b.text.TextBounds.X / w, 0.7)
		local x = 0.5 - (markW + gap + textW) / 2
		mark.Position = UDim2.fromScale(x + markW / 2, 0.5)
		b.text.Position = UDim2.fromScale(x + markW + gap, b.text.Position.Y.Scale)
		b.text.Size = UDim2.fromScale(textW + 0.05, b.text.Size.Y.Scale)
	end
	task.defer(place)
	b.face:GetPropertyChangedSignal("AbsoluteSize"):Connect(place)
end

-- the Shop's motion (owner 2026-11-13: "make some animations"): the rays behind a product turn, its
-- picture rocks, and a light sweeps over its Buy button now and then. Looping tweens on the card's own
-- instances, so they stop when the popup is rebuilt or closed. None with Reduced motion.
local function shopMotion(order: number, sun: ImageLabel?, front: ImageLabel?, buy: Ui.Block?)
	if SettingsController.get("reducedMotion") == true then
		return
	end
	local M = Config.ui.shop.motion
	if sun then
		sun.Rotation = (order * 37) % 360
		TweenService:Create(sun, TweenInfo.new(M.sunSpin, Enum.EasingStyle.Linear, Enum.EasingDirection.In, -1), { Rotation = sun.Rotation + 360 }):Play()
	end
	if front then
		front.Rotation = -M.iconTilt
		TweenService:Create(front, TweenInfo.new(M.iconSeconds, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true, (order % 3) * 0.2), { Rotation = M.iconTilt }):Play()
	end
	if buy then
		local shine = Instance.new("Frame")
		shine.Name = "Shine"
		shine.BackgroundColor3 = Theme.white
		shine.BorderSizePixel = 0
		shine.Size = UDim2.fromScale(1, 1)
		shine.ZIndex = 3
		Ui.corner(shine)
		local g = Instance.new("UIGradient")
		g.Rotation = 25
		g.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.42, 1), NumberSequenceKeypoint.new(0.5, M.shineAlpha),
			NumberSequenceKeypoint.new(0.58, 1), NumberSequenceKeypoint.new(1, 1),
		})
		g.Offset = Vector2.new(-1, 0)
		g.Parent = shine
		shine.Parent = buy.face
		TweenService:Create(g, TweenInfo.new(M.shineSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut, -1, false, M.shineEvery + order * M.shineStagger % M.shineEvery), { Offset = Vector2.new(1, 0) }):Play()
	end
end

-- a product's own card colour (Theme.shopItemCards), its kind's colour if it has none
local function productColour(item: Config.RobuxItem): Color3
	return Theme.shopItemCards[item.id] or Theme.shopCards[if item.kind == "pass" and item.icon == "power" then "power" else item.kind] or Theme.info
end

-- ---------- contents ----------
-- ---------- the Shop (v2, 2026-11-10): laid out like a hit mobile store, so every product's value reads
-- at a glance. Tabs on the left rail (Forever / Coins / Power / Boosts), 2-3 big cards per tab, small to big
-- left to right. Each card's biggest text is what you GET (+3.5M, 2x, x3), a white chip says it in plain
-- words ("= 8 hours of coins", "120/s -> 240/s") or a bar shows how far it takes you to the next island.
-- A pink "+45% MORE" sticker = true extra per Robux against the smallest pack in the tab (rounded down);
-- "BEST VALUE" only on the pack with the most per Robux. No timers, no fake scarcity (CLAUDE.md).
-- Buttons only ask; the server shows Roblox's own purchase prompt and grants in ProcessReceipt.

type ShopTab = { id: string, label: string, icon: string, colour: string, kinds: { [string]: boolean }, title: string, sub: string }
type CardInfo = { big: string, name: string, chip: string?, bar: number?, barText: string?, amount: number? }

local function ownsPass(v: State.View, item: Config.RobuxItem): boolean
	return item.kind == "pass"
		and (Players.LocalPlayer:GetAttribute("Pass_" .. item.id) == true or (item.id == "doubleCoins" and v.doubleCoins == true))
end

-- the items a tab sells (an id of 0 = not made yet: hidden in live servers, shown in Studio for testing)
local function shopItems(tab: ShopTab): { Config.RobuxItem }
	local out: { Config.RobuxItem } = {}
	for _, item in Config.monetization.shop do
		local gone = item.kind == "deal" and State.view ~= nil and State.view.dealBought == true -- one time only
		-- the Starter Pack (2026-11-19): one time only; hidden after Config.starterPack.hideAfterMinutes when that is set
		if item.kind == "starter" and State.view then
			local ex = (State.view :: any).extras
			local hide = Config.starterPack.hideAfterMinutes
			if ex and (ex.starter == true or (hide and (ex.playSeconds or 0) > hide * 60)) then
				gone = true
			end
		end
		-- paid random items only where the policy allows them (the server checks too; QA CA-01)
		if Config.oddsKind[item.kind] and Players.LocalPlayer:GetAttribute("RandomItemsOk") ~= true then
			gone = true
		end
		if tab.kinds[item.kind] and not gone and (Config.robuxReady(item) or RunService:IsStudio()) then
			table.insert(out, item)
		end
	end
	return out
end

local function shopTabs(): { ShopTab }
	local out: { ShopTab } = {}
	for _, t in Config.monetization.shopTabs do
		if #shopItems(t) > 0 then
			table.insert(out, t)
		end
	end
	return out
end

local ARROW = " → "
local function hours(minutes: number): string
	if minutes >= 60 then
		local h = math.floor(minutes / 60)
		return `{h} hour{if h == 1 then "" else "s"}`
	end
	return `{minutes} min`
end

-- what one card shows: the big number, its name, and a white chip (or a bar) saying the value in plain words
local function cardInfo(v: State.View, item: Config.RobuxItem): CardInfo
	local name = string.gsub(item.name, "^%d+x ", "") -- "2x Coins" under a big "2x" says "Coins"
	local good = `<font color="#{Theme.shopBadge.bonus:ToHex()}">%s</font>`
	if item.kind == "coins" then
		local n = Config.robuxCoins(item, v.income)
		return { big = Ui.short(n), name = name, chip = string.format(good, hours(item.minutes or 0)) .. " of coins", amount = n } -- no "= ": it drew as a small square
	elseif item.kind == "power" then
		local n = Config.powerPack(item, v.coldPower or 0)
		local share = item.share or 0
		-- islands 3/5/7/9 also need rebirths: only promise the island when Cold Power is all it's missing
		local need = Config.nextNeed(v.coldPower or 0)
		local opens = false -- past the last island the goals go on, but no island opens
		for _, z in Config.world.zones do
			if z.need == need then
				opens = (v.rebirths or 0) >= (z.gateRebirth or 0)
			end
		end
		return { big = "+" .. Config.powerText(n), name = name, bar = math.min(share, 1), amount = n,
			barText = if share < 1 then `{math.round(share * 100)}% of the way`
				elseif opens then "Opens the next island!" else "Fills your Cold Power goal!" }
	elseif item.kind == "pass" then
		if item.id == "doubleCoins" then
			local base = if ownsPass(v, item) then v.income / (item.mult or 2) else v.income
			return { big = `{item.mult or 2}x`, name = name,
				chip = `{Ui.short(base)}/s{ARROW}` .. string.format(good, `{Ui.short(base * (item.mult or 2))}/s`) }
		elseif item.id == "autoTrain" then
			-- the gun's own training shots a second, free -> with the pass (Config.training)
			local TR = Config.training
			local function rate(seconds: number): string
				return (string.format("%.1f", 1 / seconds):gsub("%.0$", ""))
			end
			return { big = `{math.round(TR.autoEvery / TR.autoPass)}x`, name = "Auto-Train speed",
				chip = `{rate(TR.autoEvery)}/s{ARROW}` .. string.format(good, `{rate(TR.autoPass)}/s`) }
		elseif item.id == "vip" then
			return { big = "VIP", name = "Pass", chip = string.format(good, `+{math.round(Config.vip.coinBonus * 100)}% coins`) .. ", gold tag, Royal Frost ray" }
		end
		return { big = `{item.mult or 2}x`, name = name, chip = `x1{ARROW}` .. string.format(good, `x{item.mult or 2}`) }
	elseif item.kind == "charges" then
		return { big = `x{item.charges or 1}`, name = name, chip = item.chip or item.text }
	-- the 2026-11-18 boosts
	elseif item.kind == "speed" then
		return { big = `+{math.round((item.speed or 0) * 100)}%`, name = name, chip = string.format(good, hours(item.minutes or 0)) .. " of speed" }
	elseif item.kind == "luck" then
		return { big = hours(item.minutes or 0), name = "Lucky Ray", chip = "Bonus rare pets near you" }
	elseif item.kind == "serverLuck" then
		return { big = `{Config.monetization.serverLuckMult}x`, name = "Server Luck", chip = string.format(good, "Everyone") .. ` for {hours(item.minutes or 0)}` }
	elseif item.kind == "shield" then
		return { big = `x{item.charges or 1}`, name = name, chip = "Critters can't take your pet" }
	elseif item.kind == "deal" then
		return { big = "DEAL", name = name, chip = string.format(good, "One time") .. ": 3 Super Freeze + Luck + Coins" }
	elseif item.kind == "starter" then
		-- honest value: what the same things cost one by one in this shop (Coin Chest + Super Freeze x3 + Mega Speed)
		local worth = 0
		for _, id in { "coinsMedium", "superFreeze3", "speedBig" } do
			local it = Config.robuxItem(id)
			worth += if it then it.robux else 0
		end
		local SP = Config.starterPack
		local coins = Config.robuxCoins({ minutes = SP.coinMinutes, floor = SP.coinFloor } :: any, v.income)
		local x = math.floor(worth / math.max(1, item.robux))
		return { big = "STARTER", name = "Pack",
			-- QA 2026-11-20 (CA-01): the long list shrank to ~10 px in its chip; the short line fits one size up
			chip = string.format(good, `{x}x value!`) .. ` Coins, {SP.superFreeze} Freeze, Speed, Skin` }
	end
	return { big = item.big or "", name = name, chip = item.chip or item.text }
end

-- each card's true extra per Robux against the first (smallest) pack of the tab, rounded DOWN to a step,
-- and which one is the best value (only when there's a real difference)
local function shopBonuses(items: { Config.RobuxItem }, infos: { CardInfo }): ({ number }, number?)
	local bonus: { number } = {}
	local base = if infos[1] and infos[1].amount then infos[1].amount / math.max(1, items[1].robux) else nil
	local best, bestRatio = nil, base or 0
	local step = Config.ui.shop.bonusStep
	for k, info in infos do
		bonus[k] = 0
		if base and base > 0 and info.amount and items[k].kind == items[1].kind then
			local ratio = info.amount / math.max(1, items[k].robux)
			bonus[k] = math.floor((ratio / base - 1) / step + 1e-9) * step
			if ratio > bestRatio * 1.0001 then
				best, bestRatio = k, ratio
			end
		end
	end
	return bonus, best
end

-- the open tab: reset each time the Shop opens (it starts on Forever while a pass is unowned)
local shopTab: string? = nil
local shopHoldUntil = 0 -- os.clock(): until then each Shop build scrolls to shopTab (QA PT-04)
local shopWant: string? = nil -- the tab a "+" button asked for (owner 2026-11-18: "+" next to coins and Cold Power)
local function defaultTab(v: State.View, tabs: { ShopTab }): string
	if starterFeatured() then
		for _, t in tabs do
			if t.kinds.starter then
				return t.id
			end
		end
	end
	for _, t in tabs do
		if t.kinds.pass then
			for _, item in shopItems(t) do
				if not ownsPass(v, item) then
					return t.id
				end
			end
		end
	end
	for _, t in tabs do
		if not t.kinds.pass then
			return t.id
		end
	end
	return tabs[1].id
end

-- the Shop redraws only when something it shows changes (it was redrawn on every coin tick before)
shopKey = function(v: State.View): string
	local parts: { string } = {}
	for _, item in Config.monetization.shop do
		local info = cardInfo(v, item)
		table.insert(parts, `{item.id},{info.big},{info.chip or ""},{ownsPass(v, item)}`)
	end
	table.insert(parts, Config.powerText(Config.nextNeed(v.coldPower or 0)))
	local ex = (v :: any).extras
	table.insert(parts, `starter={ex and ex.starter}:{starterFeatured()}:{v.dealBought}`)
	return table.concat(parts, ";")
end

local function box(t: GuiObject, x: number, y: number, w: number, h: number)
	t.Position = UDim2.fromScale(x, y)
	t.Size = UDim2.fromScale(w, h)
end

-- a soft white sunburst behind a product's picture (the reference shops' rays), under everything else
local function shopSun(parent: Instance, x: number, y: number, size: number): ImageLabel
	local s = Instance.new("ImageLabel")
	s.Name = "Sun"
	s.BackgroundTransparency = 1
	s.Image = Config.images.icons.sunburst
	s.ImageColor3 = Theme.white
	s.ImageTransparency = Config.ui.shop.sunAlpha
	s.AnchorPoint = Vector2.new(0.5, 0.5)
	s.Position = UDim2.fromScale(x, y)
	s.Size = UDim2.fromScale(size, size)
	s.SizeConstraint = Enum.SizeConstraint.RelativeYY
	s.ZIndex = 0
	s.Parent = parent
	return s
end

-- the Shop's own frame (owner 2026-11-12: "the colour scheme isn't good", from the reference shop clips):
-- the panel turns a saturated royal-blue-to-violet, the title bar an ice-cyan gradient with snow caps on
-- it, and the content sits in a deep indigo well with a soft sunburst and snowflakes drifting down.
-- Only colours and dressing change; the layout (rail + scrolling sections) stays.
-- faint diagonal stripes over a block's face, under everything on it (the reference shops' texture)
local function stripes(g: GuiObject, alpha: number)
	if g:FindFirstChild("Stripes") then
		return
	end
	local S = Config.ui.shop
	local s = Instance.new("ImageLabel")
	s.Name = "Stripes"
	s.BackgroundTransparency = 1
	s.Image = S.stripes
	s.ImageTransparency = alpha
	s.ScaleType = Enum.ScaleType.Tile
	s.TileSize = UDim2.fromOffset(S.stripePx, S.stripePx)
	s.Size = UDim2.fromScale(1, 1)
	s.ZIndex = 0
	Ui.corner(s)
	s.Parent = g
end

local function shopFrame(o: Open, v: State.View)
	local F = Theme.shopFrame
	local S = Config.ui.shop
	local face = o.body.Parent :: GuiObject
	local root = face.Parent :: GuiObject
	stripes(face, S.stripeAlpha)
	local function gradient(g: GuiObject, top: Color3, bottom: Color3)
		g.BackgroundColor3 = Theme.white
		local old = g:FindFirstChildOfClass("UIGradient")
		if old then
			old:Destroy()
		end
		local gr = Instance.new("UIGradient")
		gr.Rotation = 90
		gr.Color = ColorSequence.new(top, bottom)
		gr.Parent = g
	end
	gradient(face, F.top, F.bottom)
	root.BackgroundColor3 = Ui.darker(F.bottom)
	local header = face:FindFirstChild("Header") :: Frame?
	local hface = header and header:FindFirstChild("Face") :: GuiObject?
	if header and hface and not hface:FindFirstChild("CoinPill") then -- a redraw keeps the frame it has
		gradient(hface, F.titleTop, F.titleBottom)
		header.BackgroundColor3 = Ui.darker(F.titleBottom)
		stripes(hface, S.titleStripeAlpha)
		-- the title on the left, its icon big and tilted over the panel's corner (after open() centred them)
		local title = hface:FindFirstChildOfClass("TextLabel")
		local icon = hface:FindFirstChild("Icon") :: ImageLabel?
		task.defer(function()
			if icon then
				icon.Size = UDim2.fromScale(0.2, S.titleIcon)
				icon.Position = UDim2.fromScale(0.035, 0.42)
				icon.Rotation = S.titleIconTilt
				icon.ZIndex = 4
			end
			if title then
				title.TextXAlignment = Enum.TextXAlignment.Left
				title.Position = UDim2.fromScale(0.105, title.Position.Y.Scale)
				title.Size = UDim2.fromScale(0.45, title.Size.Y.Scale)
			end
		end)
		-- your coins in a dark pill on the right of the title bar (kept current while the Shop is open)
		local P = S.coinPill
		local pill = Instance.new("Frame")
		pill.Name = "CoinPill"
		pill.BackgroundColor3 = Theme.ink
		pill.BackgroundTransparency = 0.45
		pill.BorderSizePixel = 0
		pill.AnchorPoint = Vector2.new(0, 0.5)
		pill.Position = UDim2.fromScale(P.x, 0.5)
		pill.Size = UDim2.fromScale(P.w, P.h)
		pill.ZIndex = 2
		Ui.corner(pill, 0.5)
		pill.Parent = hface
		local coin = Ui.image(pill, Config.images.icons.coin, UDim2.fromScale(0.3, 1.2), UDim2.fromScale(-0.04, -0.1))
		coin.ZIndex = 3
		local amount = Ui.label(pill, Ui.short(v.coins), UDim2.fromScale(0.66, 0.8), UDim2.fromScale(0.27, 0.1))
		amount.Name = "Coins"
		amount.ZIndex = 3
		amount.TextColor3 = Theme.coin
		sized(amount, "body")
		local conn: RBXScriptConnection
		conn = State.Changed:Connect(function(nv: State.View)
			if not amount.Parent or o.closed then
				conn:Disconnect()
				return
			end
			amount.Text = Ui.short(nv.coins)
		end)
		-- island pets peeking over the bottom corners (the reference shops' pumpkins and ghosts)
		for _, m in S.mascots do
			local img = Config.images.pets[m.pet]
			if img then
				local pic = Instance.new("ImageLabel")
				pic.Name = "Mascot_" .. m.pet
				pic.BackgroundTransparency = 1
				pic.Image = img
				pic.ScaleType = Enum.ScaleType.Fit
				pic.AnchorPoint = Vector2.new(0.5, 0.5)
				pic.Position = UDim2.fromScale(m.x, m.y)
				pic.Size = UDim2.fromScale(m.size, m.size)
				pic.SizeConstraint = Enum.SizeConstraint.RelativeYY
				pic.Rotation = m.tilt
				pic.ZIndex = 6
				pic.Parent = root
			end
		end
		-- snow resting on the title bar: soft white lumps along its top edge
		local rng = Random.new(7) -- the same lumps every time the Shop opens
		for k, at in S.snowCaps do
			local cap = Instance.new("Frame")
			cap.Name = "Snow" .. k
			cap.BackgroundColor3 = F.snow
			cap.BorderSizePixel = 0
			cap.AnchorPoint = Vector2.new(0.5, 0.5)
			-- a drift: a wide soft lump with a smaller one on top, hugging the bar's top edge
			local w = 0.09 + rng:NextNumber() * 0.08
			local x = at + (rng:NextNumber() - 0.5) * 0.02
			cap.Position = UDim2.fromScale(x, 0.1)
			cap.Size = UDim2.fromScale(w, 0.3)
			cap.ZIndex = 3
			Ui.corner(cap, 0.5)
			cap.Parent = header
			local bump = Instance.new("Frame")
			bump.Name = "Bump"
			bump.BackgroundColor3 = F.snow
			bump.BorderSizePixel = 0
			bump.AnchorPoint = Vector2.new(0.5, 1)
			bump.Position = UDim2.fromScale(0.35 + rng:NextNumber() * 0.3, 0.55)
			bump.Size = UDim2.fromScale(0.5, 1)
			bump.ZIndex = 3
			Ui.corner(bump, 0.5)
			bump.Parent = cap
		end
	end
	-- the well behind the rail and the sections
	local well = Instance.new("Frame")
	well.Name = "Well"
	well.BackgroundColor3 = Theme.white
	well.BorderSizePixel = 0
	well.Position = UDim2.fromScale(-0.015, -0.02)
	well.Size = UDim2.fromScale(1.03, 1.04)
	well.ZIndex = 0
	well.ClipsDescendants = true
	Ui.corner(well)
	Ui.stroke(well, Config.ui.cardStroke)
	gradient(well, F.wellTop, F.wellBottom)
	well.Parent = o.body
	local sun = shopSun(well, 0.6, 0.0, 1.6)
	sun.ImageColor3 = F.glow
	sun.ImageTransparency = 0.72
	-- snowflakes drifting down (none with Reduced motion: the well stays still)
	if SettingsController.get("reducedMotion") ~= true then
		local n = if SettingsController.get("lowGraphics") == true then math.floor(S.flakes / 2) else S.flakes
		local rng = Random.new()
		for k = 1, n do
			local f = Instance.new("Frame")
			f.Name = "Flake"
			f.BackgroundColor3 = Theme.white
			f.BackgroundTransparency = 0.25 + rng:NextNumber() * 0.45
			f.BorderSizePixel = 0
			f.SizeConstraint = Enum.SizeConstraint.RelativeYY
			local size = 0.008 + rng:NextNumber() * 0.012
			f.Size = UDim2.fromScale(size, size)
			f.ZIndex = 0
			Ui.corner(f, 1)
			f.Parent = well
			local x = rng:NextNumber()
			local secs = rng:NextNumber(S.flakeSeconds[1], S.flakeSeconds[2])
			f.Position = UDim2.fromScale(x, rng:NextNumber()) -- spread over the well at the start
			task.spawn(function()
				local first = true
				while f.Parent and not o.closed do
					local fromY = if first then f.Position.Y.Scale else -0.03
					first = false
					f.Position = UDim2.fromScale(x, fromY)
					local t = secs * (1.03 - fromY)
					local tw = TweenService:Create(f, TweenInfo.new(t, Enum.EasingStyle.Linear), { Position = UDim2.fromScale(x + (rng:NextNumber() - 0.5) * 0.08, 1.03) })
					tw:Play()
					tw.Completed:Wait()
				end
			end)
		end
	end
end

-- round 3 (owner 2026-11-13: "the shop still needs improvements", the 2026-11-12 reference clips): every
-- product sits in its own little world, like the reference cards. A pale moon up in the sky, two rows of
-- hills along the bottom (dark ones far off, snowy ground in front) and the frame's stripes.
-- Hills are opaque (see-through ones showed dark seams where they overlap); the CanvasGroup with the
-- shared corner clips them to the card's rounded shape.
local function scene(face: GuiObject, colour: Color3)
	local S = Config.ui.shop.scene
	local g = Instance.new("CanvasGroup")
	g.Name = "Scene"
	g.BackgroundTransparency = 1
	g.Size = UDim2.fromScale(1, 1)
	g.ZIndex = 0
	Ui.corner(g)
	g.Parent = face
	local moon = Instance.new("Frame")
	moon.Name = "Moon"
	moon.BackgroundColor3 = Theme.white
	moon.BackgroundTransparency = S.moonAlpha
	moon.BorderSizePixel = 0
	moon.AnchorPoint = Vector2.new(0.5, 0.5)
	moon.Position = UDim2.fromScale(S.moon.x, S.moon.y)
	moon.Size = UDim2.fromScale(S.moon.size, S.moon.size)
	local a = Instance.new("UIAspectRatioConstraint")
	a.AspectRatio = 1
	a.Parent = moon
	Ui.corner(moon, 1)
	moon.Parent = g
	for layer, hills in S.hills do
		for _, h in hills.at do -- { centre x, width, height } as shares of the card
			local hill = Instance.new("Frame")
			hill.Name = "Hill" .. layer
			hill.BackgroundColor3 = colour:Lerp(if hills.to == "white" then Theme.white else Theme.ink, hills.amount)
			hill.BorderSizePixel = 0
			hill.AnchorPoint = Vector2.new(0.5, 0)
			hill.Position = UDim2.fromScale(h[1], 1 - h[3])
			hill.Size = UDim2.fromScale(h[2], h[3] * 2)
			Ui.corner(hill, 0.5)
			hill.Parent = g
		end
	end
	stripes(g, Config.ui.shop.cardStripeAlpha)
end

-- a card's title says what you get, the gain first in coin gold: "2x Coins", "+3.5M Coins", "x3 Super Freeze"
local function cardTitle(item: Config.RobuxItem, info: CardInfo): string
	local word = if item.kind == "coins" then "Coins" elseif item.kind == "power" then "Cold Power" else info.name
	return `<font color="#{Theme.coin:ToHex()}">{info.big}</font> {word}`
end

-- the "+45% MORE" sticker on the top-right corner and the BEST VALUE ribbon over the top edge.
-- wide = a landscape tile: its sizes are shares of a short card, so they are set from its height.
local function stickers(c: Ui.Block, bonus: number, best: boolean, wide: boolean)
	if bonus > 0 then
		local s = Instance.new("Frame")
		s.Name = "More"
		s.BackgroundColor3 = Theme.shopBadge.more
		s.BorderSizePixel = 0
		s.AnchorPoint = Vector2.new(0.5, 0.5)
		-- inside the card's right edge, so the list's scroll bar strip never cuts it (round 3)
		s.Position = UDim2.fromScale(if wide then 0.93 else 0.84, if wide then 0.08 else 0.05)
		s.Size = UDim2.fromScale(if wide then 0.42 else 0.36, if wide then 0.42 else 0.36)
		s.SizeConstraint = if wide then Enum.SizeConstraint.RelativeYY else Enum.SizeConstraint.RelativeXY
		s.Rotation = 12
		s.ZIndex = 5
		local a = Instance.new("UIAspectRatioConstraint")
		a.AspectRatio = 1
		a.Parent = s
		Ui.corner(s, 1)
		Ui.stroke(s)
		local t = Ui.label(s, `+{math.round(bonus * 100)}%\nMORE`, UDim2.fromScale(0.8, 0.6), UDim2.fromScale(0.1, 0.2))
		t.ZIndex = 6
		sized(t, "small")
		s.Parent = c.root
	end
	if best then
		local r = Instance.new("Frame")
		r.Name = "BestValue"
		r.BackgroundColor3 = Theme.shopBadge.bestBack
		r.BorderSizePixel = 0
		if wide then
			r.Position = UDim2.fromScale(0.04, -0.13) -- clear of the title under it
			r.Size = UDim2.fromScale(0.34, 0.15)
		else
			r.Position = UDim2.fromScale(0.06, -0.045)
			r.Size = UDim2.fromScale(0.56, 0.085) -- ends before the "+% MORE" sticker
		end
		r.ZIndex = 5
		Ui.corner(r)
		local st = Instance.new("UIStroke")
		st.Color = Theme.shopBadge.bestText
		st.Thickness = Config.ui.cardStroke
		st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		st.Parent = r
		local t = Ui.inkLabel(r, "BEST VALUE", UDim2.fromScale(0.9, 0.76), UDim2.fromScale(0.05, 0.12))
		t.TextColor3 = Theme.shopBadge.bestText
		t.ZIndex = 6
		sized(t, "small")
		r.Parent = c.root
	end
end

-- one product card: a Chunky Pop block in its kind's colour, the painted icon (stacked 1-3 deep for bigger
-- packs), the big number, the name, the chip or bar, and a green Robux button. The whole card buys
-- (mobile QA 2026-11-10); Roblox's own prompt still confirms, so a stray tap costs nothing.
local function shopCard(o: Open, v: State.View, parent: Instance, item: Config.RobuxItem, info: CardInfo, bonus: number, best: boolean): (Ui.Block, Ui.Block)
	local owned = ownsPass(v, item)
	local colour = productColour(item)
	if owned then
		colour = colour:Lerp(Theme.slot, 0.6)
	end
	local c = Ui.block(parent, "Robux_" .. item.id, colour, "", if owned then nil else function()
		SoundController.play("click")
		State.send("BuyRobux", item.id)
	end)
	c.text.Visible = false
	scene(c.face, colour)
	-- the picture: copies of the icon fanned out behind the front one, the group centred on its box
	local icon = Config.images.icons[item.icon] or Config.images.icons.coin
	local stack = item.stack or 1
	local ix, iy, iw, ih = 0.15, 0.05, 0.7, 0.34
	local step = iw * 0.16
	local sun = shopSun(c.face, 0.5, iy + ih / 2, ih * 1.5)
	local front: ImageLabel? = nil
	for k = stack, 1, -1 do
		local dx = (k - 1) * step - (stack - 1) * step / 2
		local img = Ui.image(c.face, icon, UDim2.fromScale(iw, ih), UDim2.fromScale(ix + dx, iy - (k - 1) * ih * 0.06))
		img.ZIndex = 1 + stack - k
		front = img
	end
	local big = Ui.label(c.face, info.big)
	big.Name = "Big"
	sized(big, "big")
	box(big, 0.04, 0.4, 0.92, 0.15)
	local name = Ui.label(c.face, info.name)
	name.Name = "Name"
	sized(name, "small")
	box(name, 0.04, 0.555, 0.92, 0.08)
	if info.bar then
		local b = bar(c.face, 0.08, 0.655, 0.84, 0.085, info.bar, info.barText or "", Theme.training.power)
		local t = b:FindFirstChild("Count") :: TextLabel
		sized(t, "small")
	elseif info.chip and info.chip ~= "" then
		local chip = Instance.new("Frame")
		chip.Name = "Chip"
		chip.BackgroundColor3 = Theme.white
		chip.BorderSizePixel = 0
		box(chip, 0.06, 0.65, 0.88, 0.095)
		Ui.corner(chip, 0.5)
		Ui.stroke(chip, Config.ui.cardStroke)
		local t = Ui.inkLabel(chip, info.chip, UDim2.fromScale(0.9, 0.8), UDim2.fromScale(0.05, 0.1))
		t.RichText = true
		sized(t, "small") -- shrinks to fit a long chip; "tiny" was hard to read on PC (QA 2026-11-11)
		chip.Parent = c.face
	end
	local b = button(c.face, if owned then Theme.info else Theme.go, if owned then "Owned" else tostring(item.robux), 0, 1, function()
		if not owned then
			State.send("BuyRobux", item.id)
		end
	end)
	b.root.Name = "Buy"
	box(b.root, 0.07, 0.785, 0.86, 0.17)
	if not owned then
		robuxTag(b)
	end
	shopMotion(table.find(Config.monetization.shop, item) or 1, sun, front, if owned then nil else b)
	stickers(c, bonus, best, false)
	return c, b
end

-- The odds behind a paid random item (QA CA-01/02, owner 2026-11-19: "add odds into the shop, a button on the
-- bottom of the luck"): a panel over the Shop with each rarity's chance, from Config.oddsRows (the same numbers
-- the server rolls with). Server Luck shows now -> with it. Tap anywhere or Close to go back.
local function pctText(p: number): string
	if p >= 10 then
		return string.format("%.0f%%", p)
	elseif p >= 1 then
		return string.format("%.1f%%", p)
	elseif p >= 0.1 then
		return string.format("%.2f%%", p)
	end
	return string.format("%.3f%%", p)
end

local function oddsPanel(o: Open, item: Config.RobuxItem)
	local kind = Config.oddsKind[item.kind]
	if not kind then
		return
	end
	local old = o.body:FindFirstChild("Odds")
	if old then
		old:Destroy()
	end
	local shade = Instance.new("TextButton") -- tap outside the card to close
	shade.Name = "Odds"
	shade.Text = ""
	shade.AutoButtonColor = false
	shade.BackgroundColor3 = Theme.ink
	shade.BackgroundTransparency = 0.35
	shade.BorderSizePixel = 0
	shade.Size = UDim2.fromScale(1, 1)
	shade.ZIndex = 20
	shade.Parent = o.body
	shade.Activated:Connect(function()
		shade:Destroy()
	end)
	local c = Instance.new("Frame")
	c.Name = "Card"
	c.BackgroundColor3 = Theme.white
	c.BorderSizePixel = 0
	c.AnchorPoint = Vector2.new(0.5, 0.5)
	c.Position = UDim2.fromScale(0.5, 0.5)
	c.Size = UDim2.fromScale(0.7, 0.92)
	Ui.corner(c)
	Ui.stroke(c, Config.ui.cardStroke)
	c.Parent = shade
	local rows = Config.oddsRows(kind)
	local head = if kind == "serverLuck"
		then `Server Luck: wild pet chances for everyone ({Config.monetization.serverLuckMult}x Rare and up)`
		elseif item.kind == "deal" then "Welcome Deal: the Lucky Ray pet's chances"
		else `Lucky Ray: a bonus pet every {Config.monetization.luckEvery} s. Its chances:`
	local h = Ui.inkLabel(c, head, UDim2.fromScale(0.92, 0.14), UDim2.fromScale(0.04, 0.03))
	sized(h, "body")
	local n = #rows + (if kind == "serverLuck" then 1 else 0)
	local top, bottom = 0.19, 0.8
	local rh = (bottom - top) / n
	local y = top
	if kind == "serverLuck" then
		local a = Ui.inkLabel(c, "Now", UDim2.fromScale(0.25, rh), UDim2.fromScale(0.42, y))
		sized(a, "small")
		local b = Ui.inkLabel(c, "With Server Luck", UDim2.fromScale(0.3, rh), UDim2.fromScale(0.66, y))
		sized(b, "small")
		y += rh
	end
	for _, r in rows do
		local name = Ui.inkLabel(c, r.name, UDim2.fromScale(0.36, rh), UDim2.fromScale(0.06, y))
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.TextColor3 = tierColor(r.name)
		sized(name, "body")
		local p = Ui.inkLabel(c, pctText(r.pct), UDim2.fromScale(0.25, rh), UDim2.fromScale(0.42, y))
		sized(p, "body")
		if r.boosted then
			local q = Ui.inkLabel(c, pctText(r.boosted), UDim2.fromScale(0.3, rh), UDim2.fromScale(0.66, y))
			q.TextColor3 = if r.boosted > r.pct then Theme.shopBadge.bonus else Theme.ink
			sized(q, "body")
		end
		y += rh
	end
	local close = button(c, Theme.info, "Close", 0.3, 0.4, function()
		shade:Destroy()
	end)
	close.root.Name = "Close"
	close.root.Position = UDim2.fromScale(0.3, 0.82)
	close.root.Size = UDim2.fromScale(0.4, 0.15)
	for _, d in shade:GetDescendants() do
		if d:IsA("GuiObject") then
			d.ZIndex += 20
		end
	end
end

-- the small "Odds" button on a paid random item's tile, in its top-left corner (owner 2026-11-19)
local function oddsButton(o: Open, face: GuiObject, item: Config.RobuxItem, at: { number })
	if not Config.oddsKind[item.kind] then
		return
	end
	local b = Ui.block(face, "OddsButton", Theme.white, "Odds", function()
		SoundController.play("click")
		oddsPanel(o, item)
	end)
	b.root.Name = "OddsButton"
	b.root.ZIndex = 3
	b.text.TextColor3 = Theme.ink
	-- ink text with an ink outline read as a black blob, "Odds" unreadable (owner 2026-11-20)
	local oddsStroke = b.text:FindFirstChildOfClass("UIStroke")
	if oddsStroke then
		oddsStroke.Enabled = false
	end
	box(b.root, at[1], at[2], at[3], at[4])
	sized(b.text, "small")
	-- a bigger invisible hit area: the chip is only ~38x24 px on a phone, under the thumb minimum
	-- (phone check 2026-11-19); this one is ~50x48 px there
	local hit = Instance.new("TextButton")
	hit.Name = "OddsHit"
	hit.Text = ""
	hit.BackgroundTransparency = 1
	hit.AnchorPoint = Vector2.new(0.5, 0.5)
	hit.Position = UDim2.fromScale(0.5, 0.5)
	hit.Size = UDim2.fromScale(1.35, 2)
	hit.ZIndex = 10
	hit.Selectable = false
	hit.Parent = b.root
	hit.Activated:Connect(function()
		SoundController.play("click")
		oddsPanel(o, item)
	end)
end

-- a landscape product tile (round 3, the reference cards): the title across the top ("2x Coins", the gain
-- in gold), the picture bottom-left on rays, the value chip (or a Cold Power bar) and a fat green Robux
-- button bottom-right. wide = a full-width banner (an odd product out at the top of its section): the
-- picture on the left, title and chip in the middle, the button on the right. The whole tile buys.
-- Boxes are { x, y, w, h } shares of the tile (Config.ui.shop.tile / .wideTile).
local function shopTile(o: Open, v: State.View, parent: Instance, item: Config.RobuxItem, info: CardInfo, bonus: number, best: boolean, wide: boolean): (Ui.Block, Ui.Block)
	local owned = ownsPass(v, item)
	local colour = productColour(item)
	if owned then
		colour = colour:Lerp(Theme.slot, 0.6)
	end
	local c = Ui.block(parent, "Robux_" .. item.id, colour, "", if owned then nil else function()
		SoundController.play("click")
		State.send("BuyRobux", item.id)
	end)
	c.text.Visible = false
	scene(c.face, colour)
	local L = if wide then Config.ui.shop.wideTile else Config.ui.shop.tile
	local function place(g: GuiObject, at: { number })
		box(g, at[1], at[2], at[3], at[4])
	end
	-- the picture: copies of the icon fanned out behind the front one, on soft rays
	local ix, iy, iw, ih = L.icon[1], L.icon[2], L.icon[3], L.icon[4]
	local sun = shopSun(c.face, ix + iw / 2, iy + ih / 2, ih * 1.6)
	local icon = Config.images.icons[item.icon] or Config.images.icons.coin
	local stack = item.stack or 1
	local step = iw * 0.2
	local front: ImageLabel? = nil
	for k = stack, 1, -1 do
		local dx = (k - 1) * step - (stack - 1) * step / 2
		local img = Ui.image(c.face, icon, UDim2.fromScale(iw, ih), UDim2.fromScale(ix + dx, iy - (k - 1) * ih * 0.06))
		img.ZIndex = 1 + stack - k
		front = img
	end
	local title = Ui.label(c.face, cardTitle(item, info))
	title.Name = "Title"
	title.RichText = true
	title.ZIndex = 2
	sized(title, "title")
	place(title, L.title)
	if Config.oddsKind[item.kind] and not wide then -- leave the top-left corner to the Odds button
		box(title, 0.23, L.title[2], 0.74, L.title[4])
	end
	if bonus > 0 then -- leave the top-right corner to the "+% MORE" sticker
		title.Size = UDim2.fromScale(L.title[3] - Config.ui.shop.stickerRoom, L.title[4])
	end
	if info.bar then
		local b = bar(c.face, L.chip[1], L.chip[2], L.chip[3], L.chip[4], info.bar, info.barText or "", Theme.training.power)
		b.ZIndex = 2
		sized(b:FindFirstChild("Count") :: TextLabel, "small")
	elseif info.chip and info.chip ~= "" then
		local chip = Instance.new("Frame")
		chip.Name = "Chip"
		chip.BackgroundColor3 = Theme.white
		chip.BorderSizePixel = 0
		chip.ZIndex = 2
		place(chip, L.chip)
		Ui.corner(chip, 0.5)
		Ui.stroke(chip, Config.ui.cardStroke)
		local t = Ui.inkLabel(chip, info.chip, UDim2.fromScale(0.9, 0.8), UDim2.fromScale(0.05, 0.1))
		t.RichText = true
		t.ZIndex = 2
		sized(t, "small")
		chip.Parent = c.face
	end
	local b = button(c.face, if owned then Theme.info else Theme.go, if owned then "Owned" else tostring(item.robux), 0, 1, function()
		if not owned then
			State.send("BuyRobux", item.id)
		end
	end)
	b.root.Name = "Buy"
	b.root.ZIndex = 2
	place(b.root, L.buy)
	if not owned then
		robuxTag(b)
	end
	shopMotion(table.find(Config.monetization.shop, item) or 1, sun, front, if owned then nil else b)
	stickers(c, bonus, best, true)
	oddsButton(o, c.face, item, if wide then { 0.015, 0.06, 0.12, 0.3 } else { 0.025, 0.05, 0.19, 0.22 })
	return c, b
end

-- owner 2026-11-12: the Shop is one page you scroll from Forever down to Boosts (the reference's layout:
-- a titled section per kind, wide banners for the permanent passes, cards for the packs). The left rail
-- stays as shortcuts: a tab scrolls to its section, and the section in view is the lit tab.
local function shop(o: Open, v: State.View)
	local S = Config.ui.shop
	local tabs = shopTabs()
	shopFrame(o, v)
	if #tabs == 0 then
		local t = Ui.inkLabel(o.body, "Coming soon", UDim2.fromScale(1, 0.2), UDim2.fromScale(0, 0.4))
		sized(t, "title")
		return
	end
	local fresh = shopTab == nil -- a new visit starts at its default section; a redraw keeps the scroll
	shopTab = shopTab or shopWant or defaultTab(v, tabs)
	shopWant = nil
	local rail = Instance.new("Frame")
	rail.Name = "Tabs"
	rail.BackgroundTransparency = 1
	rail.Size = UDim2.fromScale(S.rail, 1)
	rail.Visible = S.showRail -- round 2: one full-width page like the references (the rail's code stays for a quick way back)
	rail.Parent = o.body
	local railW = if S.showRail then S.rail + 0.03 else 0
	local content = Instance.new("Frame")
	content.Name = "Content"
	content.BackgroundTransparency = 1
	content.Position = UDim2.fromScale(railW, 0)
	content.Size = UDim2.fromScale(1 - railW, 1)
	content.Parent = o.body
	local sf = list(content, true) :: ScrollingFrame
	sf.ScrollBarImageColor3 = Theme.white -- the ink bar vanished on the dark well
	local heads: { [string]: Frame } = {}
	local tabBlocks: { [string]: { block: Ui.Block, ring: UIStroke, colour: Color3, y: number } } = {}
	local pinned: string? = nil -- a pressed tab keeps its light until the player scrolls by hand
	local function styleTabs()
		for id, t in tabBlocks do
			local on = id == shopTab
			local colour = if on then t.colour else t.colour:Lerp(Theme.white, 0.4)
			t.block.face.BackgroundColor3 = colour
			t.block.root.BackgroundColor3 = Ui.darker(colour)
			t.block.root.Position = UDim2.fromScale(if on then 0.08 else 0, t.y)
			t.ring.Enabled = on
		end
	end
	local function jump(id: string, instant: boolean)
		local h = heads[id]
		if not h then
			return
		end
		local y = h.AbsolutePosition.Y - sf.AbsolutePosition.Y + sf.CanvasPosition.Y - sf.AbsoluteSize.Y * Config.ui.listInset
		local target = Vector2.new(0, math.clamp(y, 0, math.max(0, sf.AbsoluteCanvasSize.Y - sf.AbsoluteSize.Y)))
		if instant or SettingsController.get("reducedMotion") == true then
			sf.CanvasPosition = target
		else
			TweenService:Create(sf, TweenInfo.new(S.jumpSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CanvasPosition = target }):Play()
		end
	end
	-- the lit tab follows the scroll: the last section whose title has come into the top part of the view
	local function mark()
		if pinned then
			return
		end
		local line = sf.AbsolutePosition.Y + sf.AbsoluteSize.Y * S.markLine
		local cur = tabs[1].id
		for _, t in tabs do
			local h = heads[t.id]
			if h and h.AbsolutePosition.Y <= line then
				cur = t.id
			end
		end
		local room = sf.AbsoluteCanvasSize.Y - sf.AbsoluteSize.Y
		if room > 4 and sf.CanvasPosition.Y >= room - 2 then
			cur = tabs[#tabs].id -- at the very bottom: the last section, even if its title can't reach the top
		end
		if cur ~= shopTab then
			shopTab = cur
			styleTabs()
		end
	end
	local n = #tabs
	local tabH = math.min(0.22, (1 - S.gap * (n - 1)) / n)
	local top = (1 - (tabH * n + S.gap * (n - 1))) / 2
	for i, t in tabs do
		local colour = Theme.shopCards[t.colour] or Theme.info
		local b = Ui.block(rail, "Tab_" .. t.id, colour, t.label, function()
			SoundController.play("click")
			pinned = t.id
			shopTab = t.id
			styleTabs()
			jump(t.id, false)
		end)
		local y = top + (i - 1) * (tabH + S.gap)
		box(b.root, 0, y, 0.92, tabH)
		Ui.image(b.face, Config.images.icons[t.icon] or Config.images.icons.coin, UDim2.fromScale(0.6, 0.6), UDim2.fromScale(0.2, 0.03))
		box(b.text, 0.05, 0.62, 0.9, 0.34)
		sized(b.text, "small")
		local ring = Instance.new("UIStroke") -- the lit tab: a white ring inside its outline
		ring.Color = Theme.white
		ring.Thickness = Config.ui.cardStroke * 1.5
		ring.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		ring.LineJoinMode = Enum.LineJoinMode.Round
		ring.Parent = b.face
		tabBlocks[t.id] = { block = b, ring = ring, colour = colour, y = y }
	end
	-- the sections, top to bottom. Phones get taller tiles and cards, so a Buy button is thumb-sized
	-- (preview 2026-11-13: 32 px tall on a 338 px phone at the PC shape; a tablet's are 70+ px without it)
	local touch = Screen.deviceClass() == "phone"
	local order = 0
	local passBuy: Ui.Block? = nil
	local starterBuy: Ui.Block? = nil
	local bestBuy: Ui.Block? = nil
	local firstBuy: Ui.Block? = nil
	for _, tab in tabs do
		local colour = Theme.shopCards[tab.colour] or Theme.info
		order += 1
		local hr = row(sf, order, 1, S.headAspect)
		hr.Name = "Head_" .. tab.id
		heads[tab.id] = hr
		-- the section's title as plain white words with its icon each side, straight on the well (round 2,
		-- like the references: a coloured pill per section read as a button), and one short line under it
		-- round 3: one slim line like the references' "Boost Upgrades", so more products fit on screen;
		-- the short line under it gets its own thin row
		local _ = colour
		local title = Ui.label(hr, tab.title, UDim2.fromScale(0.7, 0.84), UDim2.fromScale(0.15, 0.08))
		title.Name = "Title"
		sized(title, "body") -- quieter than the product titles under it
		local tabIcon = Config.images.icons[tab.icon] or Config.images.icons.coin
		local left = Ui.image(hr, tabIcon, UDim2.fromScale(0.1, S.headIcon), UDim2.fromScale(0, 0.03))
		local right = Ui.image(hr, tabIcon, UDim2.fromScale(0.1, S.headIcon), UDim2.fromScale(0, 0.03))
		task.defer(function()
			local w = math.max(1, hr.AbsoluteSize.X)
			local half = title.TextBounds.X / w / 2
			local iw = left.AbsoluteSize.X / w
			left.Position = UDim2.fromScale(0.5 - half - 0.015 - iw / 2, 0.5)
			right.Position = UDim2.fromScale(0.5 + half + 0.015 + iw / 2, 0.5)
		end)
		local sub = tab.sub
		if tab.kinds.power then
			local need = Config.nextNeed(v.coldPower or 0)
			local isle = nil
			for _, z in Config.world.zones do
				if z.need == need then
					isle = z.name
				end
			end
			sub = `{isle or "Your next island"} needs {Config.powerText(need)} Cold Power`
		end
		if sub ~= "" then
			order += 1
			local sr = row(sf, order, 1, S.subAspect)
			sr.Name = "Sub_" .. tab.id
			local line = Ui.inkLabel(sr, sub, UDim2.fromScale(1, 0.9), UDim2.fromScale(0, 0.05))
			line.TextColor3 = Theme.shopFrame.text -- light words on the dark well
			sized(line, "small")
		end
		-- its products: owned passes go last
		local items = shopItems(tab)
		table.sort(items, function(a, b)
			local oa, ob = ownsPass(v, a), ownsPass(v, b)
			if oa ~= ob then
				return ob
			end
			return false
		end)
		local infos: { CardInfo } = {}
		for k, item in items do
			infos[k] = cardInfo(v, item)
		end
		if not tab.kinds.coins then
			-- round 3: two landscape tiles a row, like the references; an odd one out leads as a full-width
			-- banner (with owned passes sorted last, that's the first pass you don't have yet)
			local bonus, best = shopBonuses(items, infos)
			local function note(k: number, buy: Ui.Block, card: Ui.Block?)
				local item = items[k]
				if item.kind == "starter" and card then
					starterGlow(card.root)
					if starterFeatured() then
						starterBuy = buy
					end
				end
				firstBuy = firstBuy or buy
				if item.kind == "pass" and not passBuy and not ownsPass(v, item) then
					passBuy = buy
				end
				if k == best then
					bestBuy = bestBuy or buy
				end
			end
			local k = 1
			if #items % 2 == 1 then
				order += 1
				local r = row(sf, order, 1, S.bannerAspect)
				r.Name = "Banner_" .. items[1].id
				local c, buy = shopTile(o, v, r, items[1], infos[1], bonus[1], best == 1, true)
				c.root.Size = UDim2.fromScale(1, 1)
				note(1, buy, c)
				k = 2
			end
			while k <= #items do
				order += 1
				local r = row(sf, order, 1, if touch then S.tileRowAspectTouch else S.tileRowAspect)
				r.Name = `Tiles_{tab.id}_{k}`
				for j = 0, 1 do
					local i = k + j
					if items[i] then
						local c, buy = shopTile(o, v, r, items[i], infos[i], bonus[i], best == i, false)
						box(c.root, j * (0.5 + S.tileGap / 2), S.tileTop, 0.5 - S.tileGap / 2, 1 - S.tileTop)
						note(i, buy, c)
					end
				end
				k += 2
			end
		else
			-- packs as cards, small to big, left to right
			local bonus, best = shopBonuses(items, infos)
			order += 1
			local r = row(sf, order, 1, if touch then S.cardsAspectTouch else S.cardsAspect)
			r.Name = "Cards_" .. tab.id
			local count = #items
			local gap = 0.04
			local w = math.min(S.cardMax, (1 - gap * (count - 1)) / (count + (if best then S.bestGrow - 1 else 0)))
			local total = w * count + gap * (count - 1) + (if best then w * (S.bestGrow - 1) else 0)
			local x = (1 - total) / 2
			for k, item in items do
				local isBest = k == best
				local cw = if isBest then w * S.bestGrow else w
				local c, buy = shopCard(o, v, r, item, infos[k], bonus[k], isBest)
				box(c.root, x, if isBest then 0.06 else 0.1, cw, if isBest then 0.94 else 0.86) -- room above for the stickers
				x += cw + gap
				firstBuy = firstBuy or buy
				if isBest then
					bestBuy = bestBuy or buy
				end
			end
		end
	end
	-- one focal point: the first pass you don't own, else the best-value pack
	local focal = starterBuy or passBuy or bestBuy or firstBuy
	if focal then
		pulse(focal.root)
		-- not the gamepad's first pick (QA 2026-11-17): opening the Shop on a console put A on a Robux Buy, so
		-- one press opened a purchase. Like the Thaw Machine's Skip, A never starts a purchase: it lands on the X
		-- and the stick moves to the cards.
	end
	styleTabs()
	sf:GetPropertyChangedSignal("CanvasPosition"):Connect(mark)
	sf.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			pinned = nil
		end
	end)
	sf.InputChanged:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseWheel then
			pinned = nil
		end
	end)
	-- QA PT-04 (2026-11-19): "+" opened the Shop at the top. The jump ran once, 0.05 s in, while the opening
	-- show was still growing the panel, and the redraw right after opening (ShopOpened) built a fresh list at
	-- the top. Now the asked-for section is held for the first second: every build in it jumps there again.
	if fresh then
		shopHoldUntil = os.clock() + 2
	end
	if shopTab ~= tabs[1].id and os.clock() < shopHoldUntil then
		pinned = shopTab
		-- once the list has been measured, and again after the opening show (panel pop 0.32 s, rows sliding in ~0.9 s)
		for _, wait in { 0.05, 0.4, 1.0, 1.4 } do
			task.delay(wait, function()
				if sf.Parent and shopTab and pinned == shopTab then
					jump(shopTab, true)
				end
			end)
		end
	end
end

-- a pet's picture, name and its tier / mutation / pose line, on the left of a list card
local function petInfo(r: Frame, p: State.PetView, def: PetDefs.PetDef)
	local pose = Config.poses[p.pose]
	Ui.petPicture(r, def, UDim2.fromScale(0.11, 0.92), UDim2.fromScale(0.01, 0.04)) -- the painting, or its 3D model
	-- the name on top; under it the tier, mutation and pose, each word in its own colour
	-- (tinting the painted sprite made Starry muddy and Golden orange, QA 2026-10-31)
	local name = text(r, def.name, 0.13, 0.4)
	name.Size = UDim2.fromScale(0.4, 0.5)
	name.Position = UDim2.fromScale(0.13, 0.04)
	local function word(s: string, c: Color3): string
		return `<font color="#{c:ToHex()}">{s}</font>`
	end
	local tags = { word(def.tier, Ui.darker(tierColor(def.tier))) }
	if p.sz and Theme.sizes[p.sz] then -- Big ... Cosmic (Config.sizes)
		table.insert(tags, word(p.sz, Ui.darker(Theme.sizes[p.sz])))
	end
	local look = if p.mut then Theme.mut[p.mut] else nil
	if p.mut then
		table.insert(tags, word(p.mut, if look then Ui.darker(look.tint) else Theme.infoDeep))
	end
	if pose and p.pose ~= "idle" then
		table.insert(tags, word(pose.label, Theme.infoDeep))
	end
	local tagLine = text(r, table.concat(tags, "  "), 0.13, 0.4, nil, "small")
	tagLine.RichText = true
	tagLine.Size = UDim2.fromScale(0.4, 0.4)
	tagLine.Position = UDim2.fromScale(0.13, 0.54)
end

-- labels that count down to a pet's thaw (server clock) while their popup is open
type Countdown = { label: TextLabel, at: number }
local function countdowns(o: Open, items: { Countdown })
	if #items == 0 then
		return
	end
	task.spawn(function()
		while not o.closed and items[1].label.Parent do
			local now = workspace:GetServerTimeNow()
			for _, it in items do
				it.label.Text = Config.timeText(it.at - now)
			end
			task.wait(0.5)
		end
	end)
end

-- Daily challenges (ChallengeService): one card per goal: what to do, a bar with the count, and on the
-- right what it pays (a coin tag), a pulsing Claim button once it's done, or "Done" once claimed.
-- may this player send game invites? Asked of Roblox once at Start (it yields); until it answers, or
-- where Roblox says no, the Daily popup has no Invite row
local canInvite = false

-- the Daily popup's last row (2026-11-10): the friend bonus (Config.friends) and an Invite button that
-- opens Roblox's own friend picker. Roblox doesn't show invite prompts in Studio play tests.
-- which painted icon a challenge wears (found by its text in Config.challenges.pool)
local CHALLENGE_ICONS: { [string]: string } = {
	frozen = Config.images.icons.ray, banked = Config.ui.tileIcons.pets, rares = Config.images.icons.star, coinsEarned = Config.images.icons.coin,
}
local function challengeIcon(c: State.Challenge): string
	for _, def in Config.challenges.pool do
		if def.text == c.text then
			return CHALLENGE_ICONS[def.stat] or Config.images.icons.trophy
		end
	end
	return Config.images.icons.trophy
end

local function inviteRow(l: GuiObject, order: number)
	local r = card(row(l, order, 1, 7))
	r.Name = "Invite"
	r.BackgroundColor3 = Theme.info:Lerp(Theme.white, 0.82) -- info blue: a tip, not one of today's goals
	local F = Config.friends
	Ui.image(r, Config.images.icons.gift, UDim2.fromScale(0.1, 0.8), UDim2.fromScale(0.02, 0.1))
	local D = Config.ui.daily
	local t = text(r, "Play with friends", D.textX, D.textW)
	t.Size = UDim2.fromScale(D.textW, 0.46)
	t.Position = UDim2.fromScale(D.textX, 0.07)
	local s = text(r, `+{math.round(F.perFriend * 100)}% coins for each friend (up to {F.max})`, D.textX, D.textW, Theme.infoDeep, "small")
	s.Size = UDim2.fromScale(D.textW, 0.36)
	s.Position = UDim2.fromScale(D.textX, 0.55)
	local b = button(r, Theme.go, "Invite", D.sideX, D.sideW, function()
		pcall(function()
			SocialService:PromptGameInvite(Players.LocalPlayer)
		end)
	end)
	b.root.Name = "InviteButton"
end

-- owner 2026-11-12 ("looks very strange"): the reward was a big yellow block that read as a button, the
-- little bar hid under the words, and the timer floated between the cards. Now: the timer is a blue pill
-- on top; each goal is a card with its painted icon, the goal, a wide bar, and on the right a quiet coin
-- tag (what it pays), a pulsing green Claim once it's done (the card turns pale green), or "Done".
-- a section heading inside the Daily popup (2026-11-19): bold words on the cream, left aligned
local function sectionHead(l: GuiObject, order: number, s: string, sub: string?)
	local r = row(l, order, 1, 18)
	r.Name = "Head" .. order
	local t = text(r, s, 0.01, if sub then 0.5 else 0.98, Theme.ink, "title")
	t.Size = UDim2.fromScale(if sub then 0.5 else 0.98, 0.9)
	t.Position = UDim2.fromScale(0.01, 0.05)
	if sub then
		local st = text(r, sub, 0.5, 0.49, Theme.infoDeep, "small")
		st.TextXAlignment = Enum.TextXAlignment.Right
		st.Size = UDim2.fromScale(0.49, 0.8)
		st.Position = UDim2.fromScale(0.5, 0.1)
		return st
	end
	return nil
end

-- the login calendar (2026-11-19, Config.login): 7 day tiles, the days you've had ticked, today's glowing with a
-- Claim button under it. Missing a day never resets it: you just carry on.
local LOGIN_ICON = { coins = "coin", superFreeze = "ray", speed = "boots", skin = "star" }
local function loginRows(o: Open, l: GuiObject, ex: any)
	local L = Config.login
	sectionHead(l, -30, "Login calendar", "Come back each day. Missing a day never resets it")
	local r = row(l, -29, 1, 5.6)
	r.Name = "LoginDays"
	local n = #L.days
	local gap = 0.012
	local w = (1 - gap * (n - 1)) / n
	for i, day in L.days do
		local had = i <= ex.login.n
		local today = ex.login.canClaim and i == ex.login.nextDay
		local tile = Instance.new("Frame")
		tile.Name = "Day" .. i
		tile.BorderSizePixel = 0
		tile.Position = UDim2.fromScale((i - 1) * (w + gap), 0.04)
		tile.Size = UDim2.fromScale(w, 0.92)
		tile.BackgroundColor3 = if had then Theme.go:Lerp(Theme.white, 0.75) elseif today then Theme.coin:Lerp(Theme.white, 0.35)
			elseif i == n then Theme.gift:Lerp(Theme.white, 0.7) else Theme.white
		Ui.corner(tile)
		Ui.stroke(tile, if today then Config.ui.cardStroke * 2 else Config.ui.cardStroke)
		tile.Parent = r
		local head = Ui.inkLabel(tile, `Day {i}`, UDim2.fromScale(0.9, 0.22), UDim2.fromScale(0.05, 0.03))
		sized(head, "small")
		local key = if day.skin then "skin" elseif day.speed then "speed" elseif day.superFreeze and not day.coins then "superFreeze" else "coins"
		Ui.image(tile, Config.images.icons[LOGIN_ICON[key]] or Config.images.icons.coin, UDim2.fromScale(0.6, 0.42), UDim2.fromScale(0.2, 0.25))
		local what = if day.skin then "Skin!" elseif day.speed then "Speed"
			elseif day.superFreeze and not day.coins then `x{day.superFreeze}` elseif today then `+{Ui.short(ex.login.nextCoins)}` else "Coins"
		local wl = Ui.inkLabel(tile, if had then "Got it" else what, UDim2.fromScale(0.94, 0.26), UDim2.fromScale(0.03, 0.7))
		wl.TextColor3 = if had then Theme.go else Theme.ink
		sized(wl, "small")
		if today then
			pulse(tile)
		end
	end
	if ex.login.canClaim then
		local cr = row(l, -28, 1, 10)
		cr.Name = "LoginClaim"
		local claim = button(cr, Theme.go, `Claim day {ex.login.nextDay}`, 0.3, 0.4, function()
			State.send("Extras", "login")
		end)
		pulse(claim.root)
		o.first = o.first or claim.face
	end
end

-- weekly quests (2026-11-19, Config.weekly): like the daily cards, bigger goals, a weekly timer
local function weeklyRows(o: Open, l: GuiObject, ex: any)
	local D = Config.ui.daily
	local W = Config.weekly
	local sub = sectionHead(l, 30, "Weekly quests", "")
	if sub then
		local function show()
			sub.Text = `New quests in {Config.timeText(ex.weekly.resetsAt - workspace:GetServerTimeNow())}` ..
				(if ex.weekly.champion then "" else "  ·  all 3 = Champion ray")
		end
		show()
		task.spawn(function()
			while not o.closed and sub.Parent do
				task.wait(1)
				show()
			end
		end)
	end
	for i, c in ex.weekly.list do
		local line = card(row(l, 30 + i, 1, 6.5))
		line.Name = "Weekly" .. i
		local ready = c.done and not c.claimed
		if c.claimed then
			line.BackgroundColor3 = Theme.slot:Lerp(Theme.white, 0.5)
		elseif ready then
			line.BackgroundColor3 = Theme.go:Lerp(Theme.white, 0.8)
		else
			line.BackgroundColor3 = Theme.info:Lerp(Theme.white, 0.9)
		end
		local def = nil
		for _, p in W.pool do
			if p.text == c.text then
				def = p
			end
		end
		local badge = Instance.new("Frame")
		badge.Name = "Badge"
		badge.BackgroundColor3 = Theme.info:Lerp(Theme.white, 0.6)
		badge.BorderSizePixel = 0
		badge.AnchorPoint = Vector2.new(0, 0.5)
		badge.Position = UDim2.fromScale(0.015, 0.5)
		badge.Size = UDim2.fromScale(0.2, 0.8)
		local ba = Instance.new("UIAspectRatioConstraint")
		ba.DominantAxis = Enum.DominantAxis.Height
		ba.Parent = badge
		Ui.corner(badge)
		Ui.stroke(badge, Config.ui.cardStroke)
		badge.Parent = line
		Ui.image(badge, if def then CHALLENGE_ICONS[def.stat] or Config.images.icons.trophy else Config.images.icons.trophy,
			UDim2.fromScale(0.84, 0.84), UDim2.fromScale(0.08, 0.08))
		local t = text(line, (string.gsub(c.text, "{n}", Ui.short(c.goal))), D.textX, D.textW)
		t.Size = UDim2.fromScale(D.textW, 0.42)
		t.Position = UDim2.fromScale(D.textX, 0.08)
		local b = bar(line, D.textX, 0.56, D.textW, 0.32, c.have / math.max(1, c.goal),
			`{Ui.short(math.min(c.have, c.goal))} / {Ui.short(c.goal)}`, if c.done then Theme.go else Theme.info)
		sized(b:FindFirstChild("Count") :: TextLabel, "small")
		if c.claimed then
			local done = text(line, "Done", D.sideX, D.sideW, Theme.go, "button")
			done.TextXAlignment = Enum.TextXAlignment.Center
		elseif ready then
			local claim = button(line, Theme.go, "Claim", D.sideX, D.sideW, function()
				State.send("Extras", "weekly", i)
			end)
			pulse(claim.root)
			o.first = o.first or claim.face
		else
			local tag = Instance.new("Frame")
			tag.Name = "Reward"
			tag.BackgroundColor3 = Theme.coin:Lerp(Theme.white, 0.78)
			tag.BorderSizePixel = 0
			tag.Position = UDim2.fromScale(D.sideX + 0.01, 0.12)
			tag.Size = UDim2.fromScale(D.sideW - 0.02, 0.4)
			Ui.corner(tag, 0.5)
			Ui.stroke(tag, Config.ui.cardStroke)
			tag.Parent = line
			Ui.image(tag, Config.images.icons.coin, UDim2.fromScale(0.3, 0.84), UDim2.fromScale(0.05, 0.08))
			local amount = Ui.inkLabel(tag, `+{Ui.short(ex.weekly.coins)}`, UDim2.fromScale(0.56, 0.7), UDim2.fromScale(0.37, 0.15))
			sized(amount, "button")
			local sf = Ui.inkLabel(line, `+{W.superFreeze} Super Freeze`, UDim2.fromScale(D.sideW, 0.3), UDim2.fromScale(D.sideX, 0.58))
			sf.TextColor3 = Theme.infoDeep
			sized(sf, "small")
		end
	end
end

local function daily(o: Open, v: State.View)
	local D = Config.ui.daily
	local l = list(o.body, true) -- scrolls since 2026-11-19 (login calendar + weekly quests joined it)
	local d = v.daily
	local items = if d then d.list else {}
	local ex = (v :: any).extras
	if ex then
		loginRows(o, l, ex)
		sectionHead(l, -1, "Daily challenges", nil)
		weeklyRows(o, l, ex)
	end
	if d then
		local pill = Instance.new("Frame")
		pill.Name = "Timer"
		pill.BackgroundColor3 = Theme.info:Lerp(Theme.white, 0.8)
		pill.BorderSizePixel = 0
		pill.AnchorPoint = Vector2.new(0.5, 0.5)
		pill.Position = UDim2.fromScale(0.5, 0.5)
		pill.Size = UDim2.fromScale(0.56, 0.9)
		Ui.corner(pill, 0.5) -- (unchanged)
		Ui.stroke(pill, Config.ui.cardStroke)
		pill.Parent = row(l, 0, 1, 16)
		local foot = Ui.inkLabel(pill, "", UDim2.fromScale(0.92, 0.7), UDim2.fromScale(0.04, 0.15))
		foot.TextColor3 = Theme.infoDeep
		sized(foot, "small")
		local function show()
			foot.Text = `New challenges in {Config.timeText(d.resetsAt - workspace:GetServerTimeNow())}`
		end
		show()
		task.spawn(function()
			while not o.closed and foot.Parent do
				task.wait(1)
				show()
			end
		end)
	end
	for i, c in items do
		local line = card(row(l, i, 1, 6.5))
		line.Name = "Challenge" .. i
		local ready = c.done and not c.claimed
		if c.claimed then
			line.BackgroundColor3 = Theme.slot:Lerp(Theme.white, 0.5)
		elseif ready then
			line.BackgroundColor3 = Theme.go:Lerp(Theme.white, 0.8)
		end
		local badge = Instance.new("Frame")
		badge.Name = "Badge"
		badge.BackgroundColor3 = Theme.tiles.daily:Lerp(Theme.white, 0.7)
		badge.BorderSizePixel = 0
		badge.AnchorPoint = Vector2.new(0, 0.5)
		badge.Position = UDim2.fromScale(0.015, 0.5)
		badge.Size = UDim2.fromScale(0.2, 0.8)
		local ba = Instance.new("UIAspectRatioConstraint")
		ba.DominantAxis = Enum.DominantAxis.Height
		ba.Parent = badge
		Ui.corner(badge)
		Ui.stroke(badge, Config.ui.cardStroke)
		badge.Parent = line
		Ui.image(badge, challengeIcon(c), UDim2.fromScale(0.84, 0.84), UDim2.fromScale(0.08, 0.08))
		local what = string.gsub(c.text, "{n}", Ui.short(c.goal))
		local t = text(line, what, D.textX, D.textW)
		t.Size = UDim2.fromScale(D.textW, 0.42)
		t.Position = UDim2.fromScale(D.textX, 0.08)
		local b = bar(line, D.textX, 0.56, D.textW, 0.32, c.have / math.max(1, c.goal),
			`{Ui.short(math.min(c.have, c.goal))} / {Ui.short(c.goal)}`, if c.done then Theme.go else Theme.tiles.daily)
		sized(b:FindFirstChild("Count") :: TextLabel, "small")
		if c.claimed then
			local done = text(line, "Done", D.sideX, D.sideW, Theme.go, "button")
			done.TextXAlignment = Enum.TextXAlignment.Center
		elseif ready then
			local claim = button(line, Theme.go, "Claim", D.sideX, D.sideW, function()
				State.send("ClaimChallenge", i)
			end)
			pulse(claim.root)
			o.first = o.first or claim.face
		else
			local tag = Instance.new("Frame")
			tag.Name = "Reward"
			tag.BackgroundColor3 = Theme.coin:Lerp(Theme.white, 0.78)
			tag.BorderSizePixel = 0
			tag.Position = UDim2.fromScale(D.sideX + 0.01, 0.24)
			tag.Size = UDim2.fromScale(D.sideW - 0.02, 0.52)
			Ui.corner(tag, 0.5)
			Ui.stroke(tag, Config.ui.cardStroke)
			tag.Parent = line
			Ui.image(tag, Config.images.icons.coin, UDim2.fromScale(0.3, 0.84), UDim2.fromScale(0.05, 0.08))
			local amount = Ui.inkLabel(tag, `+{Ui.short(d and d.coins or 0)}`, UDim2.fromScale(0.56, 0.7), UDim2.fromScale(0.37, 0.15))
			sized(amount, "button")
		end
	end
	if canInvite then
		inviteRow(l, 50)
	end
end

local function thawTime(v: State.View, p: State.PetView, def: PetDefs.PetDef): number
	return Config.thawSeconds(def.tier, def.size, def.zone, p.mut, v.upgrades.pen or 1, if v.pan then (v.pan :: any).thaw else 1, p.sz)
end

-- an ice-blue tag on the right of a pet card for a frozen pet: its thaw time, or the live time left in
-- a machine. Not a button: thawing happens at the machine, so it's a flat pale chip with the thaw icon
-- (like a challenge's reward chip), never a raised block that looks tappable (QA IR-08)
local function iceTag(r: Frame, s: string): TextLabel
	local tag = Instance.new("Frame")
	tag.Name = "Ice"
	tag.BackgroundColor3 = Theme.ice:Lerp(Theme.white, 0.6)
	tag.BorderSizePixel = 0
	tag.Position = UDim2.fromScale(0.78, 0.24)
	tag.Size = UDim2.fromScale(0.19, 0.52)
	Ui.corner(tag, 0.5)
	Ui.stroke(tag, Config.ui.cardStroke)
	tag.Parent = r
	Ui.image(tag, Config.images.icons.thaw, UDim2.fromScale(0.26, 0.84), UDim2.fromScale(0.04, 0.08))
	local label = Ui.inkLabel(tag, s, UDim2.fromScale(0.64, 0.7), UDim2.fromScale(0.31, 0.15))
	sized(label, "button")
	return label
end

-- a wide royal-purple Robux bar (owner 2026-11-16, from a reference's SKIP ALL bar): the words, the Robux
-- mark and the price centred together. The Thaw Machine's "Skip" 99 and Pets' "Unfreeze all" 199. Roblox's
-- own prompt confirms. It never pulses: waiting is always free. One kept from before shows as a free one.
local function robuxBar(l: GuiObject, order: number, name: string, words: string, robux: number, free: boolean, onPress: () -> ())
	local S = Config.ui.skipAll
	local r = row(l, order, 0, S.aspect)
	r.Name = name
	local b = button(r, Theme.skipAll, if free then words .. " free" else words, 0.01, 0.98, onPress)
	b.root.Name = name .. "Button"
	sized(b.text, "title")
	if free then
		return
	end
	local stroke = b.text:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Thickness = Config.ui.floatingStroke -- the firm outline of every Robux price
	end
	b.text.TextXAlignment = Enum.TextXAlignment.Left
	local price = b.text:Clone()
	price.Name = "Price"
	price.Text = tostring(robux)
	price.Parent = b.face
	local mark = robuxMark(b.face)
	local function place()
		local w = math.max(1, b.face.AbsoluteSize.X)
		local wordsW = math.min(b.text.TextBounds.X / w, 0.5)
		local markW = mark.AbsoluteSize.X / w
		local priceW = math.min(price.TextBounds.X / w, 0.3)
		local x = 0.5 - (wordsW + S.wordGap + markW + S.markGap + priceW) / 2
		b.text.Position = UDim2.fromScale(x, b.text.Position.Y.Scale)
		b.text.Size = UDim2.fromScale(wordsW + 0.05, b.text.Size.Y.Scale)
		x += wordsW + S.wordGap
		mark.Position = UDim2.fromScale(x + markW / 2, 0.5)
		x += markW + S.markGap
		price.Position = UDim2.fromScale(x, price.Position.Y.Scale)
		price.Size = UDim2.fromScale(priceW + 0.05, price.Size.Y.Scale)
	end
	task.defer(place)
	b.face:GetPropertyChangedSignal("AbsoluteSize"):Connect(place)
end

-- does Pets' Unfreeze all bar show (a pet still in its cube: thawing or waiting), and is it a free one?
local function skipAllState(v: State.View): (boolean, boolean)
	local now = workspace:GetServerTimeNow()
	local cubes = 0
	for _, p in v.pets do
		if p.frozen and (not p.thawM or (p.thawAt or 0) > now) then
			cubes += 1
		end
	end
	local free = (v.thawSkipAlls or 0) > 0
	return cubes >= (if free then 1 else Config.thaw.skip.all.minPets), free
end

-- the Thaw Machine (owner 2026-11-09): pick a frozen pet from your Pets to put in this machine. A busy
-- machine shows its pet and the time left. The server checks you stand at your own machine.
local function thaw(o: Open, v: State.View)
	local m = if typeof(o.data) == "table" and typeof(o.data.machine) == "number" then o.data.machine else 1
	local busy: State.PetView? = nil
	local frozen: { State.PetView } = {}
	for _, p in v.pets do
		if p.thawM == m then
			busy = p
		elseif p.frozen and not p.thawM then
			table.insert(frozen, p)
		end
	end
	local inside = busy
	-- its time is up: it waits for Claim (owner 2026-11-13), the one big green focal point
	local readyNow = inside ~= nil and Config.thaw.claimByHand and (inside.thawAt or 0) <= workspace:GetServerTimeNow()
	if inside and readyNow then
		local l = list(o.body, false)
		local def = PetDefs.get(inside.key)
		if def then
			local r = card(row(l, 1, 0, 7.5))
			petInfo(r, inside, def)
			local tag = iceTag(r, "Ready!")
			tag.Parent.BackgroundColor3 = Theme.go
		end
		local r2 = row(l, 2, 0.2)
		local claim = button(r2, Theme.go, "Claim", 0.25, 0.5, function()
			State.send("ClaimThaw", m)
			PopupController.close()
		end)
		pulse(claim.root)
		o.first = claim.face
		return
	end
	if inside or #frozen == 0 then
		local l = list(o.body, false)
		local def = if inside then PetDefs.get(inside.key) else nil
		if inside and def then
			local r = card(row(l, 1, 0, 7.5))
			petInfo(r, inside, def)
			countdowns(o, { { label = iceTag(r, ""), at = inside.thawAt or 0 } })
			-- when the time runs out with the popup open, draw it again with the Claim button
			local wait = (inside.thawAt or 0) - workspace:GetServerTimeNow()
			if Config.thaw.claimByHand and wait > 0 then
				task.delay(wait + 0.1, function()
					if not o.closed then
						PopupController.refresh()
					end
				end)
			end
		else
			text(row(l, 1, 0.2), "No frozen pets. Freeze one and bring it home!", 0.02, 0.96).TextXAlignment = Enum.TextXAlignment.Center
		end
		local left = if inside and inside.thawAt then inside.thawAt - workspace:GetServerTimeNow() else 0
		-- no OK button (owner 2026-11-16: "we dont need that OK"); the X closes it. The paid Skip is the
		-- purple bar under the pet (never a pop-up, waiting is always free), and it isn't the gamepad's
		-- first pick, so A never opens a purchase. A skip kept from before shows as a free one.
		if left > Config.thaw.skip.minLeft then
			robuxBar(l, 2, "Skip", "Skip", Config.thawSkipTier(left).robux, (v.thawSkips or 0) > 0, function()
				State.send("SkipThaw", m)
			end)
		end
		return
	end
	table.sort(frozen, function(a, b)
		local da, db = PetDefs.get(a.key), PetDefs.get(b.key)
		local ra = if da then Config.tier(da.tier).rank else 0
		local rb = if db then Config.tier(db.tier).rank else 0
		if ra ~= rb then
			return ra > rb -- the best first
		end
		return a.income > b.income
	end)
	local l = list(o.body, true)
	for i, p in frozen do
		local def = PetDefs.get(p.key)
		if not def then
			continue
		end
		local r = card(row(l, i, 0, 7.5))
		petInfo(r, p, def)
		-- how long it takes (the server works it out the same way when it goes in)
		local secs = text(r, Config.timeText(thawTime(v, p, def)), 0.55, 0.21, Ui.darker(Theme.info))
		secs.TextXAlignment = Enum.TextXAlignment.Right
		local b = button(r, Theme.go, "Thaw", 0.78, 0.19, function()
			State.send("ThawPet", p.id, m)
			PopupController.close()
		end)
		b.root.Position = UDim2.fromScale(0.78, 0.2)
		b.root.Size = UDim2.fromScale(0.19, 0.6)
		sized(b.text, "small")
		if not o.first then
			o.first = b.face
			pulse(b.root) -- the best pet's Thaw is the one focal point (tutorial references: show the button to press)
		end
	end
end

local function pets(o: Open, v: State.View)
	local pen, ice = 0, 0
	for _, p in v.pets do
		if p.eq then
			pen += 1
		elseif p.frozen then
			ice += 1
		end
	end
	-- touch screens: a taller head row so "Equip best" is thumb-sized (mobile QA 2026-11-10: 22 px tall)
	local headH = if Screen.deviceClass() ~= "pc" then 0.2 else 0.14
	local head = row(o.body, 0, headH)
	text(head, `Pan {pen} / {v.slots}   Storage {#v.pets - pen - ice}` .. (if ice > 0 then `   Frozen {ice}` else ""), 0.02, 0.6)
	local best = button(head, Theme.go, "Equip best", 0.66, 0.32, function()
		State.send("EquipBest")
	end)
	o.first = best.face
	local holder = Instance.new("Frame")
	holder.BackgroundTransparency = 1
	holder.Position = UDim2.fromScale(0, headH + 0.02)
	holder.Size = UDim2.fromScale(1, 1 - headH - 0.02)
	holder.Parent = o.body
	local l = list(holder, true)
	-- thawing first, then frozen (they need you), then the pan, then Storage
	local function group(p: State.PetView): number
		return if p.thawM then 0 elseif p.frozen then 1 elseif p.eq then 2 else 3
	end
	local sorted = table.clone(v.pets)
	table.sort(sorted, function(a, b)
		if group(a) ~= group(b) then
			return group(a) < group(b)
		end
		return a.income > b.income
	end)
	local timers: { Countdown } = {}
	if #sorted == 0 then
		text(row(l, 1, 0, 9), "Freeze a pet and carry it to your pan!", 0.02, 0.96)
	end
	-- the pets still in their cubes come first (thawing, then frozen); the Unfreeze all bar goes right under
	-- them, so every row after it moves down one
	local lastCube = 0
	for i, p in sorted do
		if group(p) <= 1 then
			lastCube = i
		end
	end
	local showAll, freeAll = skipAllState(v)
	local barAt = if showAll then lastCube + 1 else nil
	if barAt then
		robuxBar(l, barAt, "UnfreezeAll", "Unfreeze all", Config.thaw.skip.all.robux, freeAll, function()
			State.send("SkipThawAll")
		end)
	end
	for i, p in sorted do
		local def = PetDefs.get(p.key)
		if not def then
			continue
		end
		local r = card(row(l, if barAt and i >= barAt then i + 1 else i, 0, 7.5))
		petInfo(r, p, def)
		Ui.image(r, Config.images.icons.coin, UDim2.fromScale(0.07, 0.6), UDim2.fromScale(0.52, 0.2))
		-- owner 2026-11-18: a pet still in its cube keeps its income a surprise until it thaws
		text(r, if p.frozen or p.thawM then "???/s" else `{Ui.short(p.income)}/s`, 0.585, 0.13)
		if p.thawM then
			table.insert(timers, { label = iceTag(r, ""), at = p.thawAt or 0 }) -- in a Thaw Machine: the time left
		elseif p.frozen then
			iceTag(r, Config.timeText(thawTime(v, p, def))) -- still frozen: put it in your Thaw Machine
		else
			-- a small toggle, not a big green button: the pet is the point of the row
			local tog = button(r, if p.eq then Theme.go else Theme.info, if p.eq then "In pen" else "Stored", 0.78, 0.19, function()
				State.send("EquipPet", p.id, not p.eq)
			end)
			tog.root.Position = UDim2.fromScale(0.78, 0.2)
			tog.root.Size = UDim2.fromScale(0.19, 0.6)
			sized(tog.text, "small")
		end
	end
	countdowns(o, timers)
end

-- the Index (owner 2026-11-09: "ugly"): one white card per island with a header strip in the island's
-- colour (its name, a completion bar, and a pulsing Claim when it's full, or the trophy once claimed),
-- its pets in one row (the Secret counts too), and a bar for all pets at the bottom
local function index(o: Open, v: State.View)
	local X = Config.ui.index
	local holder = Instance.new("Frame")
	holder.Name = "Pages"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromScale(1, 1 - X.totalHeight - X.totalGap)
	holder.Parent = o.body
	local l = list(holder, true)
	local allFound, allTotal, claimedN = 0, 0, 0
	local bonus = math.round(Config.index.pageBonus * 100)
	for i, page in v.pages do
		allFound += page.found
		allTotal += page.total
		if page.claimed then
			claimedN += 1
		end
		local zone = Config.zone(page.zone)
		local look = zone and Theme.islands[zone.theme]
		local accent = if look then look.accent else Theme.info
		local c = card(row(l, i, 0, X.pageAspect))
		c.Name = "Page" .. page.zone
		c.ClipsDescendants = true
		local head = Instance.new("Frame")
		head.Name = "Head"
		head.BackgroundColor3 = accent
		head.BorderSizePixel = 0
		head.Size = UDim2.fromScale(1, X.headHeight)
		Ui.corner(head)
		local square = Instance.new("Frame") -- rounded top corners (the card's), square bottom ones
		square.BackgroundColor3 = accent
		square.BorderSizePixel = 0
		square.Position = UDim2.fromScale(0, 0.5)
		square.Size = UDim2.fromScale(1, 0.5)
		square.ZIndex = 0
		square.Parent = head
		head.Parent = c
		local name = Ui.label(head, if zone then zone.name else "Zone", UDim2.fromScale(0.25, 0.7), UDim2.fromScale(0.018, 0.15))
		name.TextXAlignment = Enum.TextXAlignment.Left
		sized(name, "body")
		bar(head, 0.28, 0.2, 0.44, 0.6, page.found / math.max(1, page.total), `{page.found} / {page.total}`, Theme.go)
		if page.complete and not page.claimed then
			local b = button(head, Theme.go, `CLAIM +{bonus}%`, 0.745, 0.24, function()
				State.send("ClaimPage", page.zone)
			end)
			b.root.Name = "Claim"
			b.root.Position = UDim2.fromScale(0.745, 0.12)
			b.root.Size = UDim2.fromScale(0.24, 0.76)
			pulse(b.root)
			if not o.first then
				o.first = b.face
			end
		else
			-- the page's badge: the coin (owner 2026-11-17: the bonus is coins), bright once claimed, faint until then
			local tr = Ui.image(head, Config.images.icons.coin, UDim2.fromScale(0.07, 0.9), UDim2.fromScale(0.75, 0.05))
			tr.Name = "Badge"
			if not page.claimed then
				tr.ImageTransparency = X.badgeFaint
			end
			local what = Ui.label(head, if page.claimed then `+{bonus}% coins` else `Fill: +{bonus}%`, UDim2.fromScale(0.17, 0.6), UDim2.fromScale(0.82, 0.2))
			what.TextXAlignment = Enum.TextXAlignment.Left
			what.TextColor3 = if page.claimed then Theme.coin else Theme.white
			sized(what, "small")
		end
		-- owner 2026-11-15: the island's own picture behind its pets, under a navy veil (Config.zoneArt)
		local art = Config.zoneArt.images[page.zone]
		if art then
			local pic = Instance.new("ImageLabel")
			pic.Name = "ZoneArt"
			pic.BackgroundTransparency = 1
			pic.Image = art
			pic.ScaleType = Enum.ScaleType.Crop
			pic.Position = UDim2.fromScale(0, 0)
			pic.Size = UDim2.fromScale(1, 1) -- the whole card: under the slots the picture hardly showed (QA 2026-11-15)
			head.BackgroundTransparency = Config.zoneArt.headSeeThrough
			square.BackgroundTransparency = Config.zoneArt.headSeeThrough
			pic.ZIndex = 0
			Ui.corner(pic)
			local veil = Instance.new("Frame")
			veil.Name = "Veil"
			veil.BackgroundColor3 = Theme.ink
			veil.BorderSizePixel = 0
			veil.Size = UDim2.fromScale(1, 1)
			veil.ZIndex = 0
			Ui.corner(veil)
			local vg = Instance.new("UIGradient")
			vg.Rotation = 90
			vg.Transparency = NumberSequence.new(Config.zoneArt.shadeTop, Config.zoneArt.shadeBottom)
			vg.Parent = veil
			veil.Parent = pic
			pic.Parent = c
		end
		local grid = Instance.new("Frame")
		grid.Name = "Pets"
		grid.BackgroundTransparency = 1
		grid.Position = UDim2.fromScale(X.slotInset, X.headHeight + X.slotTop)
		grid.Size = UDim2.fromScale(1 - X.slotInset * 2, 1 - X.headHeight - X.slotTop * 2)
		grid.Parent = c
		local g = Instance.new("UIGridLayout")
		local n = math.max(1, #PetDefs.inZone(page.zone))
		local gap = X.slotGap
		g.CellSize = UDim2.fromScale((1 - gap * (n - 1)) / n, 1)
		g.CellPadding = UDim2.fromScale(gap, 0)
		g.SortOrder = Enum.SortOrder.LayoutOrder
		g.Parent = grid
		for n, def in PetDefs.inZone(page.zone) do
			local found = v.found[def.key] == true
			local secret = def.tier == "Secret"
			-- silhouettes show what's missing; the Secret is a bonus slot
			-- missing pets sit on a light slot so their dark silhouette shows (on the navy board it vanished)
			local b = Ui.block(grid, def.key, if found then tierColor(def.tier) elseif secret then Theme.board else Theme.slot,
				if found then def.name elseif secret then "?" else "", nil)
			b.root.LayoutOrder = n
			sized(b.text, "button")
			if art then
				-- QA 2026-11-15: solid slots hid the island picture; they let it show through a little
				b.root.BackgroundTransparency = Config.zoneArt.slotSeeThrough
				b.face.BackgroundTransparency = Config.zoneArt.slotSeeThrough
			end
			-- the painted pet, or its dark silhouette while it's still missing (the Secret stays a mystery)
			if (found or not secret) and Ui.petPicture(b.face, def, UDim2.fromScale(0.8, 0.66), UDim2.fromScale(0.1, 0.02), not found) then
				b.text.Size = UDim2.fromScale(0.9, 0.28)
				b.text.Position = UDim2.fromScale(0.05, 0.68)
			end
			if secret and not found then
				local tag = Ui.label(b.face, "Secret", UDim2.fromScale(0.9, 0.28), UDim2.fromScale(0.05, 0.68))
				sized(tag, "small")
				b.text.Size = UDim2.fromScale(0.9, 0.6)
				b.text.Position = UDim2.fromScale(0.05, 0.06)
				sized(b.text, "title")
			end
		end
	end
	-- every pet in the game, the Secrets too, as one bar; the trophies you've claimed on the right
	local total = Ui.block(o.body, "Total", Theme.info, "", nil)
	total.root.Position = UDim2.fromScale(0, 1 - X.totalHeight)
	total.root.Size = UDim2.fromScale(1, X.totalHeight)
	total.text.Visible = false
	Ui.image(total.face, Config.images.icons.book, UDim2.fromScale(0.07, 0.9), UDim2.fromScale(0.01, 0.05))
	local all = Ui.label(total.face, "All pets", UDim2.fromScale(0.15, 0.6), UDim2.fromScale(0.085, 0.2))
	all.TextXAlignment = Enum.TextXAlignment.Left
	sized(all, "body")
	local pct = if allTotal > 0 then math.floor(allFound / allTotal * 100) else 0
	bar(total.face, 0.24, 0.22, 0.6, 0.56, allFound / math.max(1, allTotal), `{allFound} / {allTotal}   {pct}%`, Theme.go)
	Ui.image(total.face, Config.images.icons.trophy, UDim2.fromScale(0.07, 0.9), UDim2.fromScale(0.86, 0.05))
	local tn = Ui.label(total.face, tostring(claimedN), UDim2.fromScale(0.06, 0.6), UDim2.fromScale(0.93, 0.2))
	tn.TextXAlignment = Enum.TextXAlignment.Left
	sized(tn, "body")
end

local function settings(o: Open)
	-- touch screens (phones and tablets): the 7 rows scroll, each tall enough for a thumb (mobile QA
	-- 2026-11-10: On / Off were 20 px tall on a phone when all 7 shared the panel)
	local touch = Screen.deviceClass() ~= "pc"
	local l = list(o.body, touch)
	local function settingRow(order: number, height: number): Frame
		return card(row(l, order, if touch then 0 else height, if touch then 9 else nil))
	end
	local rows = {
		{ key = "music", label = "Music" }, { key = "sound", label = "Sound" },
		{ key = "reducedMotion", label = "Reduced motion" }, { key = "lowGraphics", label = "Low graphics" },
		{ key = "unit", label = "Temperature in F" }, { key = "skipShows", label = "Auto-skip cutscenes" },
	}
	-- the rows share the panel: 5 settings, the tutorial and codes (0.128 x 7 plus the gaps fits in 1)
	local rowH = Config.ui.settingsRow
	for i, r in rows do
		local line = settingRow(i, rowH)
		local icon = Config.ui.settingIcons[r.key]
		if icon then
			Ui.image(line, icon, UDim2.fromScale(0.1, 0.84), UDim2.fromScale(0.015, 0.08))
		end
		text(line, r.label, 0.13, 0.55)
		local on = if r.key == "unit" then SettingsController.get("unit") == "F" else SettingsController.get(r.key) == true
		local b = button(line, if on then Theme.go else Theme.no, if on then "On" else "Off", 0.72, 0.26, function()
			if r.key == "unit" then
				SettingsController.set("unit", if SettingsController.get("unit") == "F" then "C" else "F")
			else
				SettingsController.set(r.key, not SettingsController.get(r.key))
			end
			PopupController.refresh()
		end)
		if i == 1 then
			o.first = b.face
		end
	end
	local v = State.view
	-- the tutorial (2026-11-10): Ranger Bo walks you through a catch again. While it runs, the button rests.
	local tut = settingRow(#rows + 1, rowH)
	tut.Name = "Tutorial"
	-- no guide character since 2026-11-15 (Config.tutorial.name is gone): the old "Tutorial with <name>" threw
	-- here and the Tutorial and Codes rows never appeared (QA 2026-11-16)
	text(tut, "Tutorial", 0.03, 0.66)
	local running = v ~= nil and v.tutorial ~= nil and not v.tutorial.done
	button(tut, if running then Theme.tutorial.skip else Theme.info, if running then "On now" else "Replay", 0.72, 0.26, function()
		if not running then
			State.send("Tutorial", "replay")
			PopupController.close()
		end
	end)
	-- Codes (Round 5): unlocked after catching Config.codes.needPets pets; the server checks the code
	local need = Config.codes.needPets
	local caught = if v then v.stats.frozen else 0
	local line = settingRow(#rows + 2, rowH)
	line.Name = "Codes"
	local title = text(line, "Codes", 0.03, 0.2)
	title.Size = UDim2.fromScale(0.2, 0.7)
	if caught < need then
		-- locked: how many pets to go, as a bar that's never empty-looking
		local track = Instance.new("Frame")
		track.Name = "Progress"
		track.BackgroundColor3 = Theme.snowFar
		track.Position = UDim2.fromScale(0.24, 0.3)
		track.Size = UDim2.fromScale(0.44, 0.4)
		Ui.corner(track, 0.5)
		Ui.stroke(track)
		local fill = Instance.new("Frame")
		fill.BackgroundColor3 = Theme.round5.codes
		fill.Size = UDim2.fromScale(math.max(0.06, caught / need), 1)
		Ui.corner(fill, 0.5)
		fill.Parent = track
		track.Parent = line
		local left = text(line, `Catch {need} pets  {math.floor(caught)}/{need}`, 0.7, 0.28, Theme.infoDeep, "small")
		left.TextXAlignment = Enum.TextXAlignment.Right
		return
	end
	local holder = Ui.block(line, "CodeBox", Theme.white, "", nil, true)
	holder.root.Position = UDim2.fromScale(0.24, 0.12)
	holder.root.Size = UDim2.fromScale(0.46, 0.76)
	holder.text.Visible = false
	local box = Instance.new("TextBox")
	box.Name = "Code"
	box.BackgroundTransparency = 1
	box.Size = UDim2.fromScale(0.9, 0.7)
	box.Position = UDim2.fromScale(0.05, 0.15)
	box.Font = Theme.font
	box.TextScaled = true
	box.TextColor3 = Theme.ink
	box.PlaceholderText = "Type a code"
	box.PlaceholderColor3 = Theme.tiers.Common
	box.Text = ""
	box.ClearTextOnFocus = false
	box.Parent = holder.face
	local function redeem()
		local code = box.Text:gsub("%s", ""):sub(1, Config.codes.maxLength)
		if #code > 0 then
			State.send("RedeemCode", code)
		end
	end
	box.FocusLost:Connect(function(enter: boolean)
		if enter then
			redeem()
		end
	end)
	button(line, Theme.go, "Redeem", 0.72, 0.26, redeem)
end

-- ---------- Tester panel (testers only; the server checks every button again) ----------
local testerReadout: { [string]: any } = {}
local fps = 60

local function numberBox(parent: Instance, placeholder: string, x: number, w: number): TextBox
	local holder = Ui.block(parent, "Box", Theme.white, "", nil)
	holder.root.Position = UDim2.fromScale(x, 0.1)
	holder.root.Size = UDim2.fromScale(w, 0.8)
	holder.text.Visible = false
	local box = Instance.new("TextBox")
	box.BackgroundTransparency = 1
	box.Size = UDim2.fromScale(0.9, 0.8)
	box.Position = UDim2.fromScale(0.05, 0.1)
	box.Font = Theme.font
	box.TextScaled = true
	box.TextColor3 = Theme.ink
	box.PlaceholderText = placeholder
	box.PlaceholderColor3 = Theme.board
	box.Text = ""
	box.ClearTextOnFocus = false
	box.Parent = holder.face
	return box
end

-- The Tester panel, remade (owner 2026-11-12: "actual good UI, smaller buttons but a bigger panel on
-- the screen, a button for each thing I need"). A big popup with a live readout on top, five tabs, and
-- each tab a compact grid of small buttons (Config.dev.panel: slots to a row, the row's shape). Kinds of
-- item: a button (one slot), a stepper (a value with - and +, two slots), a number box with Set (two
-- slots), an On / Off toggle (one slot). Dev tools stay quiet: grey tabs, colour only on actions.
local testerTab = "player"
local testerMail: { { t: number, k: string, m: string, s: string } } = {} -- the Mail tab's rows (TesterService "mail")
-- the panel's picks, kept across tabs and redraws (2026-11-18): the pet, its mutation and size (0 = none), the
-- spawn zone, the ADMIN tab's rain rarity / count, boost kind / x / minutes, and where admin things happen
local pick = { pet = 1, mut = 0, size = 0, zone = 0, rainTier = 0, rainCount = 1, boost = 1, bMult = 1, bMin = 1, tMult = 2, tMin = 1, here = false }
local giftArmed = false
local adminDraft = "" -- the ADMIN tab's message, kept while the panel redraws

local function tester(o: Open, v: State.View)
	local D = Config.dev
	local P = D.panel
	local updates: { (State.View) -> () } = {}
	local function send(action: string, a: any?, b: any?, c: any?)
		State.send("Tester", action, a, b, c)
	end
	local function readNum(key: string, default: number): number
		local n = testerReadout[key]
		return if typeof(n) == "number" then n else default
	end

	-- top: the readout and the tab row
	local top = Instance.new("Frame")
	top.Name = "TesterTop"
	top.BackgroundTransparency = 1
	top.Size = UDim2.fromScale(1, P.topHeight)
	top.Parent = o.body
	local readout = Ui.inkLabel(top, "", UDim2.fromScale(1, 0.42), UDim2.fromScale(0, 0))
	readout.Name = "Readout"
	readout.TextXAlignment = Enum.TextXAlignment.Left
	readout.RichText = true
	sized(readout, "small")
	table.insert(updates, function()
		local parts = 0
		for _, d in workspace:GetDescendants() do
			if d:IsA("BasePart") then
				parts += 1
			end
		end
		local r = testerReadout
		local function b(s: string): string
			return `<b>{s}</b>`
		end
		readout.Text = `FPS {b(tostring(math.round(fps)))}   Parts {b(Ui.commas(parts))}   Coins {b(Ui.short(r.coins or 0))} (x{r.mult or 1})   Power {b(Config.powerText(r.power or 0))}   `
			.. `Rebirth {b(tostring(r.rebirths or 0))}   Islands {b(`{r.reach or 1}/{#Config.world.zones}`)}   Gun {b(tostring(r.gun or 1))}   `
			.. `Trainer {b(tostring(r.trainer or 1))}   Slots {b(tostring(r.slots or 1))}   Pets {b(tostring(r.pets or 0))}`
	end)
	local tabRow = Instance.new("Frame")
	tabRow.Name = "Tabs"
	tabRow.BackgroundTransparency = 1
	tabRow.Position = UDim2.fromScale(0, 0.48)
	tabRow.Size = UDim2.fromScale(1, 0.52)
	tabRow.Parent = top
	for i, t in P.tabs do
		local on = t.id == testerTab
		local tb = button(tabRow, if on then Theme.info else Theme.tutorial.skip, t.label, (i - 1) / #P.tabs + 0.004, 1 / #P.tabs - 0.008, function()
			if testerTab ~= t.id then
				testerTab = t.id
				PopupController.refresh()
			end
		end)
		tb.root.Name = "Tab_" .. t.id
		if on then
			o.first = tb.face
		end
	end
	local page = Instance.new("Frame")
	page.Name = "Page"
	page.BackgroundTransparency = 1
	page.Position = UDim2.fromScale(0, P.topHeight + 0.02)
	page.Size = UDim2.fromScale(1, 1 - P.topHeight - 0.02)
	page.Parent = o.body
	local l = list(page, true)

	-- the grid: items fill rows of P.perRow slots
	local GAP = P.gap
	local slotW = (1 - GAP * (P.perRow + 1)) / P.perRow
	local order, used = 0, P.perRow
	local cur: Frame = Instance.new("Frame")
	local function take(n: number): (Frame, number, number)
		if used + n > P.perRow then
			order += 1
			cur = row(l, order, 0, P.rowAspect)
			used = 0
		end
		local x = GAP + used * (slotW + GAP)
		used += n
		return cur, x, n * slotW + (n - 1) * GAP
	end
	local function heading(s: string)
		order += 1
		local r = row(l, order, 0, P.headAspect)
		used = P.perRow
		local t = text(r, s, GAP, 1 - 2 * GAP, Theme.infoDeep, "small")
		t.Size = UDim2.fromScale(1 - 2 * GAP, 0.9)
		t.Position = UDim2.fromScale(GAP, 0.05)
	end
	local function btn(label: string, colour: Color3, fn: () -> (), n: number?): Ui.Block
		local r, x, w = take(n or 1)
		local b = button(r, colour, label, x, w, fn)
		sized(b.text, "small")
		return b
	end
	local function stepper(get: (State.View) -> string, minus: () -> (), plus: () -> ())
		local r, x, w = take(2)
		local lab = text(r, "", x, w * 0.56, nil, "small")
		lab.TextXAlignment = Enum.TextXAlignment.Center
		sized(button(r, Theme.no, "-", x + w * 0.58, w * 0.2, minus).text, "small")
		sized(button(r, Theme.go, "+", x + w * 0.8, w * 0.2, plus).text, "small")
		table.insert(updates, function(view)
			lab.Text = get(view)
		end)
	end
	local function input(placeholder: string, onSet: (number) -> ())
		local r, x, w = take(2)
		local box = numberBox(r, placeholder, x, w * 0.66)
		sized(button(r, Theme.go, "Set", x + w * 0.69, w * 0.31, function()
			local n = tonumber(box.Text)
			if n then
				onSet(n)
			end
		end).text, "small")
	end
	local function toggle(label: string, get: (State.View) -> boolean, action: string)
		local b = btn(label, Theme.no, function()
			local view = State.view
			if view and view.tester then
				send(action, not get(view))
			end
		end)
		table.insert(updates, function(view)
			local on = get(view)
			b.face.BackgroundColor3 = if on then Theme.go else Theme.no
			b.root.BackgroundColor3 = Ui.darker(b.face.BackgroundColor3)
			b.text.Text = `{label}: {if on then "On" else "Off"}`
		end)
	end
	local function short(n: number): string
		return Config.coinText(n)
	end
	local function redrawLabels()
		if State.view then
			o.update(State.view :: State.View)
		end
	end
	-- the pet picker (Pets and ADMIN tabs): < > walk the pets (<< >> jump ten), then the mutation and size buttons cycle
	local allPets: { PetDefs.PetDef } = {}
	for _, z in Config.world.zones do
		for _, def in PetDefs.inZone(z.id) do
			table.insert(allPets, def)
		end
	end
	local muts: { string } = {}
	for name in Config.mutations do
		table.insert(muts, name)
	end
	table.sort(muts)
	local sizes: { string } = {}
	for i = #Config.sizeRollOrder, 1, -1 do -- Big first, Cosmic last
		table.insert(sizes, Config.sizeRollOrder[i])
	end
	local function pickedPet(): PetDefs.PetDef?
		return allPets[math.clamp(pick.pet, 1, math.max(1, #allPets))]
	end
	local function pickedMut(): string
		return if pick.mut == 0 then "" else muts[pick.mut] or ""
	end
	local function pickedSize(): string
		return if pick.size == 0 then "" else sizes[pick.size] or ""
	end
	local function petPicker()
		local n = math.max(1, #allPets)
		btn("<<", Theme.info, function()
			pick.pet = (pick.pet - 11) % n + 1
			redrawLabels()
		end)
		btn("<", Theme.info, function()
			pick.pet = (pick.pet - 2) % n + 1
			redrawLabels()
		end)
		local r, x, w = take(2)
		local petName = text(r, "", x, w, nil, "small")
		petName.TextXAlignment = Enum.TextXAlignment.Center
		btn(">", Theme.info, function()
			pick.pet = pick.pet % n + 1
			redrawLabels()
		end)
		btn(">>", Theme.info, function()
			pick.pet = (pick.pet + 9) % n + 1
			redrawLabels()
		end)
		local mutB = btn("", Theme.events.golden or Theme.coin, function()
			pick.mut = (pick.mut + 1) % (#muts + 1)
			redrawLabels()
		end, 2)
		local sizeB = btn("", Theme.events.secret or Theme.info, function()
			pick.size = (pick.size + 1) % (#sizes + 1)
			redrawLabels()
		end, 2)
		local sizeBack = btn("Size back", Theme.tutorial.skip, function()
			pick.size = (pick.size - 1) % (#sizes + 1)
			redrawLabels()
		end, 2)
		sizeBack.root.Name = "SizeBack"
		table.insert(updates, function()
			local def = pickedPet()
			petName.Text = if def then `{pick.pet}. {def.name} ({def.tier})` else "-"
			petName.TextColor3 = if def then Ui.darker(tierColor(def.tier)) else Theme.ink
			mutB.text.Text = if pickedMut() == "" then "Mutation: none" else `Mutation: {pickedMut()}`
			sizeB.text.Text = if pickedSize() == "" then "Size: normal" else `Size: {pickedSize()}`
		end)
	end

	if testerTab == "player" then
		heading("Coins")
		input("Exact coins", function(n)
			send("coinsSet", n)
		end)
		for _, n in D.addCoins do
			btn("+" .. short(n), Theme.coin, function()
				send("coinsAdd", n)
			end)
		end
		btn("Zero", Theme.no, function()
			send("coinsSet", 0)
		end)
		heading("Money multiplier (all coin income)")
		for _, p in D.multPresets do
			btn(if p == 1 then "x1 (reset)" else `x{p}`, if p == 1 then Theme.no else Theme.info, function()
				send("mult", p)
			end)
		end
		input("0.1 - 10000", function(n)
			send("mult", n)
		end)
		heading("Cold Power")
		for _, n in D.powerPresets do
			btn(if n == 0 then "0" else Config.powerText(n), Theme.training.power, function()
				send("power", n)
			end)
		end
		btn("Next island", Theme.go, function()
			send("powerNext")
		end)
		input("Exact Cold Power", function(n)
			send("power", n)
		end)
		heading("Progress")
		stepper(function(view)
			return `Rebirth {view.rebirths}`
		end, function()
			send("rebirths", ((State.view and State.view.rebirths) or 0) - 1)
		end, function()
			send("rebirths", ((State.view and State.view.rebirths) or 0) + 1)
		end)
		stepper(function()
			local g = math.clamp(readNum("gun", 1), 1, #Config.guns.list)
			return `Gun {g}: {Config.guns.list[g].name}`
		end, function()
			send("gun", readNum("gun", 1) - 1)
		end, function()
			send("gun", readNum("gun", 1) + 1)
		end)
		stepper(function(view)
			return `Islands open {view.reach or 1}`
		end, function()
			send("reach", ((State.view and State.view.reach) or 1) - 1)
		end, function()
			send("reach", ((State.view and State.view.reach) or 1) + 1)
		end)
		local function panLevel(kind: string): number
			local pan = State.view and State.view.pan
			return if pan and typeof((pan :: any)[kind]) == "number" then (pan :: any)[kind] else 1
		end
		stepper(function()
			local t = math.clamp(panLevel("trainer"), 1, #Config.training.stations)
			return `Trainer {t}: x{Config.training.stations[t].mult}`
		end, function()
			send("pan", "trainer", panLevel("trainer") - 1)
		end, function()
			send("pan", "trainer", panLevel("trainer") + 1)
		end)
		stepper(function(view)
			return `Slots level {view.upgrades.pen or 1}`
		end, function()
			send("upgrade", "pen", ((State.view and State.view.upgrades.pen) or 1) - 1)
		end, function()
			send("upgrade", "pen", ((State.view and State.view.upgrades.pen) or 1) + 1)
		end)
		stepper(function()
			local lk = math.clamp(panLevel("look"), 1, #Config.pan.looks)
			return `Look: {Config.pan.looks[lk].name}`
		end, function()
			send("pan", "look", panLevel("look") - 1)
		end, function()
			send("pan", "look", panLevel("look") + 1)
		end)
		heading("Movement and switches")
		btn("Walk normal", Theme.no, function()
			send("walk", 0)
		end)
		for _, s in D.walkPresets do
			btn(`Walk {s}`, Theme.info, function()
				send("walk", s)
			end)
		end
		toggle("Instant freeze", function(view)
			return view.tester ~= nil and view.tester.instantFreeze
		end, "instantFreeze")
		toggle("No melt", function(view)
			return view.tester ~= nil and view.tester.noMelt
		end, "noMelt")
		btn("Shield off", Theme.info, function()
			send("shieldOff")
		end)
		btn("Respawn me", Theme.info, function()
			send("respawn")
		end)
		heading("Shortcuts")
		btn("MAX EVERYTHING", Theme.go, function()
			send("maxAll")
		end, 2)
		btn("Max all upgrades", Theme.info, function()
			send("upgrade", "all")
		end, 2)
		btn("Caught 0", Theme.no, function()
			send("caught", 0)
		end)
		heading("Gear levels")
		local function gearLv(key: string): number
			local g = testerReadout.gear
			local lv = if typeof(g) == "table" then g[key] else nil
			return if typeof(lv) == "number" then lv else 0
		end
		for _, g in Config.gear do
			stepper(function()
				return `{g.name} {gearLv(g.key)}/{Config.gearMax}`
			end, function()
				send("gearLevel", g.key, gearLv(g.key) - 1)
			end, function()
				send("gearLevel", g.key, gearLv(g.key) + 1)
			end)
		end
	elseif testerTab == "world" then
		heading("Teleport")
		local targets: { { id: string, label: string } } = testerReadout.targets or {}
		for _, t in targets do
			btn(t.label, Theme.info, function()
				send("teleport", t.id)
			end)
		end
		heading("Gates")
		btn("Open all gates", Theme.go, function()
			send("openGates")
		end, 2)
		btn("Close all gates", Theme.no, function()
			send("closeGates")
		end, 2)
		heading("Hazards")
		btn("Critters here on / off", Theme.info, function()
			send("critters")
		end, 2)
		heading("Wild pets (this server)")
		btn("To the Secret", Theme.events.secret or Theme.info, function()
			send("toSecret")
		end, 2)
		btn("New wave now", Theme.go, function()
			send("newWave")
		end, 2)
		btn("Clear wild pets", Theme.no, function()
			send("clearWild")
		end, 2)
	elseif testerTab == "pets" then
		heading("Pick a pet, a mutation and a size")
		petPicker()
		local zones = Config.world.zones
		btn("Give", Theme.go, function()
			local def = pickedPet()
			if def then
				send("givePet", def.key, if pickedMut() == "" then nil else pickedMut(), if pickedSize() == "" then nil else pickedSize())
			end
		end)
		btn("Give frozen", Theme.go, function()
			local def = pickedPet()
			if def then
				send("giveFrozen", def.key)
			end
		end)
		btn("<", Theme.info, function()
			pick.zone = (pick.zone - 1) % (#zones + 1)
			redrawLabels()
		end)
		local r2, x2, w2 = take(2)
		local zoneName = text(r2, "", x2, w2, nil, "small")
		zoneName.TextXAlignment = Enum.TextXAlignment.Center
		btn(">", Theme.info, function()
			pick.zone = (pick.zone + 1) % (#zones + 1)
			redrawLabels()
		end)
		btn("Spawn wild", Theme.go, function()
			local def = pickedPet()
			if def then
				send("spawnPetX", def.key, { zone = if pick.zone == 0 then 0 else zones[pick.zone].id, mut = pickedMut(), sz = pickedSize() })
			end
		end, 2)
		btn("+10 random pets", Theme.info, function()
			send("giveMany", 10)
		end, 2)
		btn("+50 random pets", Theme.info, function()
			send("giveMany", 50)
		end, 2)
		table.insert(updates, function()
			zoneName.Text = if pick.zone == 0 then "Next to me" else `{pick.zone}. {zones[pick.zone].name}`
		end)
		heading("Any pet of a rarity, next to you")
		for _, t in Config.tiers do
			btn(t.name, tierColor(t.name), function()
				send("spawnTier", t.name)
			end)
		end
		heading("Your pan")
		btn("Fill my pan", Theme.go, function()
			send("fillPan")
		end)
		btn("Pan pets to Storage", Theme.info, function()
			send("storeAll")
		end)
		btn("Equip best", Theme.go, function()
			State.send("EquipBest")
		end)
		btn(`Caught {Config.codes.needPets} (codes)`, Theme.info, function()
			send("caught", Config.codes.needPets)
		end)
		heading("Thaw and carry")
		btn("Finish all thaws", Theme.go, function()
			send("thawNow")
		end)
		btn("Melt my cube", Theme.no, function()
			send("meltNow")
		end)
		stepper(function()
			return `Free skips {readNum("skips", 0)}`
		end, function()
			send("thawSkips", readNum("skips", 0) - 1)
		end, function()
			send("thawSkips", readNum("skips", 0) + 1)
		end)
		btn("2nd Thaw Machine", Theme.info, function()
			send("upgrade", "pen", Config.thaw.machinesAt[2])
		end)
		btn("3rd Thaw Machine", Theme.info, function()
			send("upgrade", "pen", Config.thaw.machinesAt[3])
		end)
	elseif testerTab == "events" then
		heading("Server events (this server only; ADMIN tab = every server)")
		for _, e in Config.events.list do
			btn(e.name, Theme.events[e.id] or Theme.info, function()
				send("admin", { op = "event", a = e.id, here = true })
			end)
		end
		btn("End event", Theme.no, function()
			send("admin", { op = "endEvent", here = true })
		end)
		btn("Secret now", Theme.events.secret or Theme.info, function()
			send("admin", { op = "secret", here = true })
		end)
		btn("Big Chill now", Theme.info, function()
			send("chill")
		end)
		btn("Night / morning", Theme.info, function() -- the night that refreshes the islands (Config.night)
			send("night")
		end)
		heading("Time away (welcome back)")
		for _, h in D.awayHours do
			btn(`Away {h} h`, Theme.info, function()
				send("away", h * 3600)
			end)
		end
		heading("Friends in the server (friend bonus)")
		for _, n in D.friendPresets do
			btn(`{n} friends`, Theme.info, function()
				send("friends", n)
			end)
		end
	elseif testerTab == "admin" then
		-- ADMIN ABUSE (owner 2026-11-18): AdminService runs each of these in every server of the game (or only this
		-- one while "This server" is picked). The server takes only the presets from Config.admin.
		local AD = Config.admin
		local function admin(op: string, a: any?, b: any?, c: any?, d: any?)
			send("admin", { op = op, a = a, b = b, c = c, d = d, here = pick.here })
		end
		heading("Where it happens")
		local whereB = btn("", Theme.no, function()
			pick.here = not pick.here
			redrawLabels()
		end, 2)
		local rb, xb, wb = take(4)
		local boostsNow = text(rb, "", xb, wb, Theme.infoDeep, "small")
		table.insert(updates, function()
			whereB.text.Text = if pick.here then "THIS server only" else "ALL SERVERS"
			whereB.face.BackgroundColor3 = if pick.here then Theme.info else Theme.no
			whereB.root.BackgroundColor3 = Ui.darker(whereB.face.BackgroundColor3)
			local on: { string } = {}
			local now = workspace:GetServerTimeNow()
			for _, b in AD.boosts do
				local m = workspace:GetAttribute("Admin_" .. b.id)
				local u = workspace:GetAttribute("AdminUntil_" .. b.id)
				if typeof(m) == "number" and typeof(u) == "number" and u > now then
					local left = math.floor(u - now)
					table.insert(on, `{b.label} x{m} ({left // 60}:{string.format("%02d", left % 60)})`)
				end
			end
			local tm = workspace:GetAttribute("Admin_trainer")
			local tu = workspace:GetAttribute("AdminUntil_trainer")
			if typeof(tm) == "number" and typeof(tu) == "number" and tu > now then
				local left = math.floor(tu - now)
				table.insert(on, `TRAINER x{tm} ({left // 60}:{string.format("%02d", left % 60)})`)
			end
			boostsNow.Text = if #on > 0 then "Boosts: " .. table.concat(on, "  ") else "No boosts running"
		end)
		heading("Start an event now")
		for _, e in Config.events.list do
			btn(e.name, Theme.events[e.id] or Theme.info, function()
				admin("event", e.id)
			end)
		end
		btn("End event", Theme.no, function()
			admin("endEvent")
		end, 2)
		heading("Boost (press to change, then START)")
		local kindB = btn("", Theme.info, function()
			pick.boost = pick.boost % #AD.boosts + 1
			redrawLabels()
		end)
		local multB = btn("", Theme.info, function()
			pick.bMult = pick.bMult % #AD.boostMults + 1
			redrawLabels()
		end)
		local minB = btn("", Theme.info, function()
			pick.bMin = pick.bMin % #AD.boostMinutes + 1
			redrawLabels()
		end)
		btn("START BOOST", Theme.go, function()
			admin("boost", AD.boosts[pick.boost].id, AD.boostMults[pick.bMult], AD.boostMinutes[pick.bMin])
		end, 2)
		btn("Stop boosts", Theme.no, function()
			admin("clearBoosts")
		end)
		table.insert(updates, function()
			kindB.text.Text = AD.boosts[pick.boost].label
			multB.text.Text = `x{AD.boostMults[pick.bMult]}`
			minB.text.Text = `{AD.boostMinutes[pick.bMin]} min`
		end)
		-- ADMIN TRAINER (owner 2026-11-18): every pan's trainer turns gold and gives xN of its own power
		heading("ADMIN TRAINER (every pan's trainer gives xN)")
		local tMultB = btn("", Theme.coin, function()
			pick.tMult = pick.tMult % #AD.trainer.mults + 1
			redrawLabels()
		end)
		local tMinB = btn("", Theme.info, function()
			pick.tMin = pick.tMin % #AD.trainer.minutes + 1
			redrawLabels()
		end)
		btn("SPAWN ADMIN TRAINER", Theme.go, function()
			admin("trainer", AD.trainer.mults[pick.tMult], AD.trainer.minutes[pick.tMin])
		end, 2)
		btn("Remove trainer", Theme.no, function()
			admin("endTrainer")
		end)
		table.insert(updates, function()
			tMultB.text.Text = `Trainer x{AD.trainer.mults[pick.tMult]}`
			tMinB.text.Text = `{AD.trainer.minutes[pick.tMin]} min`
		end)
		heading("Pets for everyone (pick a pet, mutation and size)")
		petPicker()
		btn("Next to everyone", Theme.go, function()
			local def = pickedPet()
			if def then
				admin("petAll", def.key, pickedMut(), pickedSize())
			end
		end, 2)
		local giftB: Ui.Block
		giftB = btn("Gift to everyone", Theme.gift, function()
			local def = pickedPet()
			if not def then
				return
			end
			if giftArmed then
				giftArmed = false
				giftB.text.Text = "Gift to everyone"
				admin("giveAll", def.key, pickedMut(), pickedSize())
			else
				-- it goes into every player's save: press twice
				giftArmed = true
				giftB.text.Text = "Sure? Press again"
				task.delay(4, function()
					giftArmed = false
					if giftB.text.Parent then
						giftB.text.Text = "Gift to everyone"
					end
				end)
			end
		end, 2)
		local tierB = btn("", Theme.info, function()
			pick.rainTier = (pick.rainTier + 1) % (#Config.tiers + 1)
			redrawLabels()
		end)
		local countB = btn("", Theme.info, function()
			pick.rainCount = pick.rainCount % #AD.rainCounts + 1
			redrawLabels()
		end)
		btn("PET RAIN", Theme.go, function()
			local t = if pick.rainTier == 0 then "" else Config.tiers[pick.rainTier].name
			admin("rain", t, AD.rainCounts[pick.rainCount], pickedMut(), pickedSize())
		end, 2)
		table.insert(updates, function()
			tierB.text.Text = if pick.rainTier == 0 then "Any rarity" else Config.tiers[pick.rainTier].name
			countB.text.Text = `{AD.rainCounts[pick.rainCount]} / island`
		end)
		heading("World")
		btn("Night", Theme.events.night or Theme.info, function()
			admin("night", true)
		end)
		btn("Morning", Theme.coin, function()
			admin("night", false)
		end)
		btn("Secret now", Theme.events.secret or Theme.info, function()
			admin("secret")
		end)
		btn("New wave", Theme.go, function()
			admin("wave")
		end)
		heading(`Your message on everyone's screen (Roblox filters it, max {AD.messageMax})`)
		local rm, xm, wm = take(6)
		local holder = Ui.block(rm, "MessageBox", Theme.white, "", nil)
		holder.root.Position = UDim2.fromScale(xm, 0.1)
		holder.root.Size = UDim2.fromScale(wm * 0.78, 0.8)
		holder.text.Visible = false
		local msgBox = Instance.new("TextBox")
		msgBox.Name = "AdminMessage"
		msgBox.BackgroundTransparency = 1
		msgBox.Size = UDim2.fromScale(0.96, 0.8)
		msgBox.Position = UDim2.fromScale(0.02, 0.1)
		msgBox.Font = Theme.font
		msgBox.TextScaled = false -- UI Rules: a box people type into keeps one text size
		msgBox.TextSize = 18
		msgBox.TextColor3 = Theme.ink
		msgBox.TextXAlignment = Enum.TextXAlignment.Left
		msgBox.ClipsDescendants = true
		msgBox.PlaceholderText = "Type a message for every server"
		msgBox.PlaceholderColor3 = Theme.board
		msgBox.ClearTextOnFocus = false
		msgBox.Text = adminDraft
		msgBox.Parent = holder.face
		local function fitMsg()
			local h = msgBox.AbsoluteSize.Y
			if h > 0 then
				msgBox.TextSize = math.clamp(math.floor(h * 0.7), 12, 28)
			end
		end
		msgBox:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitMsg)
		task.defer(fitMsg)
		msgBox:GetPropertyChangedSignal("Text"):Connect(function()
			local n = utf8.len(msgBox.Text)
			if n and n > AD.messageMax then
				msgBox.Text = string.sub(msgBox.Text, 1, (utf8.offset(msgBox.Text, AD.messageMax + 1) :: number) - 1)
				return
			end
			adminDraft = msgBox.Text
		end)
		local function sendMessage()
			local s = string.match(adminDraft, "^%s*(.-)%s*$") or ""
			if s ~= "" then
				admin("message", s)
				adminDraft = ""
				msgBox.Text = ""
			end
		end
		msgBox.FocusLost:Connect(function(enter: boolean)
			if enter then
				sendMessage()
			end
		end)
		sized(button(rm, Theme.go, "SEND", xm + wm * 0.8, wm * 0.2, sendMessage).text, "small")
		heading("Shout (a fixed line on everyone's screen)")
		for i, s in AD.shouts do
			btn(s, Theme.info, function()
				admin("shout", i)
			end, 3)
		end
	elseif testerTab == "mail" then
		-- the Feedback mailbox's messages, newest first (FeedbackService; Studio needs API access to DataStores)
		heading("Feedback mail from players (newest first)")
		btn("Load mail", Theme.info, function()
			send("mail")
		end, 2)
		if #testerMail == 0 then
			heading("Nothing loaded yet")
		end
		for _, m in testerMail do
			local msg = if m.m ~= "" then m.m else "(no message)"
			heading(`{os.date("!%d %b %H:%M", m.t)}  {string.upper(m.k)}  {m.s}:  {msg}`)
		end
	else -- save
		heading("Save")
		local r, x, w = take(3)
		local keyText = text(r, "", x, w, nil, "small")
		table.insert(updates, function()
			keyText.Text = `{testerReadout.saveKey or ""}{if testerReadout.qa then " (QA store)" else " (LIVE store)"}`
		end)
		local armed = false
		local wipeB: Ui.Block
		wipeB = btn("Wipe my save", Theme.no, function()
			if not testerReadout.qa then
				wipeB.text.Text = "Live save: no"
				return
			end
			if armed then
				send("wipe", "confirm")
			else
				armed = true
				wipeB.text.Text = "Sure? Press again"
				task.delay(4, function()
					armed = false
					wipeB.text.Text = "Wipe my save"
				end)
			end
		end, 2)
		heading("Reset things to test them again")
		btn("Free Gift again", Theme.gift, function()
			send("giftReset")
		end)
		btn("Dailies done", Theme.tiles.daily, function()
			send("dailyDone")
		end)
		btn("Replay tutorial", Theme.info, function()
			State.send("Tutorial", "replay")
		end)
		btn("Skip tutorial", Theme.tutorial.skip, function()
			State.send("Tutorial", "skip")
		end)
	end

	o.update = function(view)
		for _, fn in updates do
			fn(view)
		end
	end
	o.update(v)
end

local function message(o: Open, lines: { string }, okText: string, onOk: () -> ())
	local l = list(o.body, false)
	local n = 0
	for _, s in lines do
		if s ~= "" then -- no blank rows: a short message stays short
			n += 1
			local t = text(row(l, n, 0.2), s, 0.02, 0.96, nil, if n == 1 then "body" else "small")
			t.TextXAlignment = Enum.TextXAlignment.Center
		end
	end
	local r = row(l, n + 1, 0.34) -- tall enough to stay a thumb-sized button on a phone
	local b = button(r, Theme.go, okText, 0.28, 0.44, function()
		onOk()
		PopupController.close()
	end)
	o.first = b.face
end

-- a coin reward: the coin and "+2,487" big, one short line under it, then the button
local function reward(o: Open, coins: number, sub: string, okText: string, onOk: () -> (), double: Config.RobuxItem?)
	local l = list(o.body, false)
	local top = row(l, 1, 0.38)
	local coin = Ui.image(top, Config.images.icons.coin, UDim2.fromScale(0.2, 0.9), UDim2.fromScale(0.24, 0.05))
	local amount = Ui.label(top, `+{Ui.commas(coins)}`, UDim2.fromScale(0.5, 0.9), UDim2.fromScale(0.4, 0.05))
	amount.TextColor3 = Theme.coin
	amount.TextXAlignment = Enum.TextXAlignment.Left
	sized(amount, "title")
	-- centre the coin and the number together by their visible width, not the boxes (UI Rules)
	task.defer(function()
		local w = math.max(1, top.AbsoluteSize.X)
		local coinW, gap, textW = coin.AbsoluteSize.X / w, 0.02, amount.TextBounds.X / w
		local x = 0.5 - (coinW + gap + textW) / 2
		coin.Position = UDim2.fromScale(x + coinW / 2, 0.5) -- the coin is centre-anchored (Ui.image)
		amount.Position = UDim2.fromScale(x + coinW + gap, 0.05)
	end)
	local t = text(row(l, 2, 0.2), sub, 0.02, 0.96, nil, "small")
	t.TextXAlignment = Enum.TextXAlignment.Center
	local r3 = row(l, 3, 0.34)
	local b = button(r3, Theme.go, okText, if double then 0.04 else 0.28, if double then 0.44 else 0.44, function()
		onOk()
		PopupController.close()
	end)
	o.first = b.face
	if double then
		-- 2x Welcome Back (owner 2026-11-18, the monetization plan): beside Collect, never instead of it. Closing
		-- Roblox's prompt without buying still collects the normal amount (MonetizationService)
		local x2 = button(r3, Theme.skipAll, "Collect x2", 0.52, 0.44, function()
			State.send("BuyRobux", double.id)
			PopupController.close()
		end)
		x2.text.Size = UDim2.fromScale(0.62, x2.text.Size.Y.Scale)
		x2.text.Position = UDim2.fromScale(0.04, x2.text.Position.Y.Scale)
		local mark = robuxMark(x2.face)
		mark.Position = UDim2.fromScale(0.72, 0.5)
		local price = x2.text:Clone()
		price.Name = "Price"
		price.Text = tostring(double.robux)
		price.TextXAlignment = Enum.TextXAlignment.Left
		price.Size = UDim2.fromScale(0.22, x2.text.Size.Y.Scale)
		price.Position = UDim2.fromScale(0.78, x2.text.Position.Y.Scale)
		price.Parent = x2.face
	end
end

-- The one-time Free Gift board (owner 2026-11-12, from hit games' "free reward" boards): what you get, big,
-- at the top; one numbered step card in the middle (join the group, checked on the server); one green Claim,
-- the only thing that pulses. Join opens Roblox's own group prompt. QA DR-01 (owner 2026-11-19): Like and
-- Favorite stay as optional "Enjoying it?" cards either side, with no number: Roblox doesn't allow rewarding
-- them, so they ask but aren't a step to the reward. Favorite opens Roblox's own favourite prompt.
local function giftStep(parent: Instance, n: number, x: number, w: number, title: string, picture: string, action: (Frame) -> ())
	local c = Instance.new("Frame")
	c.Name = "Step" .. n
	c.BackgroundColor3 = Theme.white
	c.BorderSizePixel = 0
	c.Position = UDim2.fromScale(x, 0)
	c.Size = UDim2.fromScale(w, 1)
	Ui.corner(c)
	Ui.stroke(c, Config.ui.cardStroke)
	c.Parent = parent
	local badge = Instance.new("Frame")
	badge.Name = "Number"
	badge.BackgroundColor3 = Theme.gift
	badge.BorderSizePixel = 0
	badge.Position = UDim2.fromScale(0.05, 0.04)
	badge.Size = UDim2.fromScale(0.2, 0.2)
	local ba = Instance.new("UIAspectRatioConstraint")
	ba.Parent = badge
	Ui.corner(badge, 1)
	Ui.stroke(badge, Config.ui.cardStroke)
	badge.Parent = c
	badge.Visible = n > 0 -- 0: an optional card, not a step to the reward
	local num = Ui.label(badge, tostring(n), UDim2.fromScale(0.8, 0.8), UDim2.fromScale(0.1, 0.1))
	sized(num, "body")
	local t = text(c, title, 0.04, 0.92, nil, "small")
	t.TextXAlignment = Enum.TextXAlignment.Center
	t.Position = UDim2.fromScale(0.04, 0.25)
	t.Size = UDim2.fromScale(0.92, 0.15)
	local pic = Ui.image(c, picture, UDim2.fromScale(0.5, 0.3), UDim2.fromScale(0.5, 0.57))
	pic.Name = "Picture"
	local pa = Instance.new("UIAspectRatioConstraint")
	pa.Parent = pic
	pic.AnchorPoint = Vector2.new(0.5, 0.5)
	pic.Position = UDim2.fromScale(0.5, 0.56)
	local a = Instance.new("Frame")
	a.Name = "Action"
	a.BackgroundTransparency = 1
	a.Position = UDim2.fromScale(0, 0.73)
	a.Size = UDim2.fromScale(1, 0.25)
	a.Parent = c
	action(a)
end

-- a quiet word where a step has no button ("Joined", "Soon", where to tap Like)
local function giftTag(a: Frame, s: string, color: Color3)
	local t = text(a, s, 0.06, 0.88, color, "small")
	t.TextXAlignment = Enum.TextXAlignment.Center
end

local giftAsking = false
local function freeGift(o: Open, v: State.View)
	local G = v.gift
	local me = Players.LocalPlayer
	-- Claim is green only once it can work (QA IR-11): ask once whether they're in the group already
	if G.groupId ~= 0 and giftJoined == nil and not giftAsking then
		giftAsking = true
		task.spawn(function()
			local ok, yes = pcall(function()
				return (me :: any):IsInGroupAsync(G.groupId)
			end)
			giftJoined = ok and yes == true
			giftAsking = false
			PopupController.refresh()
		end)
	end
	local ready = G.groupId == 0 or giftJoined == true
	local joinButton: Ui.Block? = nil
	-- what you get: the coin and the Cold Power with their amounts, centred together
	local head = text(o.body, "One-time free reward", 0, 1, Theme.gift, "small")
	head.TextXAlignment = Enum.TextXAlignment.Center
	head.Position = UDim2.fromScale(0, 0)
	head.Size = UDim2.fromScale(1, 0.08)
	local top = Instance.new("Frame")
	top.Name = "Reward"
	top.BackgroundTransparency = 1
	top.Position = UDim2.fromScale(0, 0.08)
	top.Size = UDim2.fromScale(1, 0.2)
	top.Parent = o.body
	local parts: { { icon: ImageLabel, label: TextLabel } } = {}
	for _, r in { { Config.images.icons.coin, G.coins, Theme.coin }, { Config.images.icons.power, G.power, Theme.info } } do
		local icon = Ui.image(top, r[1] :: string, UDim2.fromScale(0.12, 0.95), UDim2.fromScale(0, 0.025))
		local ia = Instance.new("UIAspectRatioConstraint")
		ia.Parent = icon
		local amount = Ui.label(top, `+{Ui.commas(r[2] :: number)}`, UDim2.fromScale(0.3, 0.95), UDim2.fromScale(0, 0.025))
		amount.TextColor3 = r[3] :: Color3
		amount.TextXAlignment = Enum.TextXAlignment.Left
		sized(amount, "big")
		table.insert(parts, { icon = icon, label = amount })
	end
	task.defer(function()
		local w = math.max(1, top.AbsoluteSize.X)
		local gap, between = 0.012, 0.06
		local total = -between
		for _, p in parts do
			total += p.icon.AbsoluteSize.X / w + gap + p.label.TextBounds.X / w + between
		end
		local x = 0.5 - total / 2
		for _, p in parts do
			local iw = p.icon.AbsoluteSize.X / w
			p.icon.Position = UDim2.fromScale(x + iw / 2, 0.5)
			p.label.Position = UDim2.fromScale(x + iw + gap, 0.025)
			x += iw + gap + p.label.TextBounds.X / w + between
		end
	end)
	-- the one step in the middle, the optional asks either side (QA DR-01)
	local steps = Instance.new("Frame")
	steps.Name = "Steps"
	steps.BackgroundTransparency = 1
	steps.Position = UDim2.fromScale(0, 0.31)
	steps.Size = UDim2.fromScale(1, 0.45)
	steps.Parent = o.body
	local w, gap = 0.31, 0.035
	giftStep(steps, 0, 0, w, "Enjoying it? Like the game", Config.images.icons.like, function(a)
		giftTag(a, "On the game page", Theme.infoDeep)
	end)
	giftStep(steps, 0, (w + gap) * 2, w, "Favorite to find us fast", Config.images.icons.star, function(a)
		local b = button(a, Theme.info, "Favorite", 0.1, 0.8, function()
			pcall(function()
				game:GetService("AvatarEditorService"):PromptSetFavorite(game.PlaceId, Enum.AvatarItemType.Asset, true)
			end)
		end)
		b.root.Name = "FavoriteButton"
	end)
	giftStep(steps, 1, w + gap, w, "Join the community", Config.ui.tileIcons.pets, function(a)
		if G.groupId == 0 then
			giftTag(a, "Soon", Theme.tiers.Common)
		elseif giftJoined then
			giftTag(a, "Joined!", Theme.shopBadge.bonus)
		else
			local b = button(a, Theme.info, "Join", 0.1, 0.8, function()
				task.spawn(function()
					pcall(function()
						GroupService:PromptJoinAsync(G.groupId)
					end)
					local ok, yes = pcall(function()
						return (me :: any):IsInGroupAsync(G.groupId)
					end)
					giftJoined = ok and yes == true
					PopupController.refresh()
				end)
			end)
			b.root.Name = "JoinButton"
			joinButton = b
		end
	end)
	-- the one focal point
	local foot = Instance.new("Frame")
	foot.Name = "Foot"
	foot.BackgroundTransparency = 1
	foot.Position = UDim2.fromScale(0, 0.79)
	foot.Size = UDim2.fromScale(1, 0.21)
	foot.Parent = o.body
	local claim = button(foot, if ready then Theme.go else Theme.tiers.Common, "Claim!", 0.28, 0.44, function()
		State.send("ClaimGift") -- not ready: the server answers "Join the group first"
	end)
	claim.root.Name = "ClaimButton"
	claim.root.Position = UDim2.fromScale(0.28, 0.05)
	claim.root.Size = UDim2.fromScale(0.44, 0.9)
	local focus = if ready or not joinButton then claim else joinButton :: Ui.Block
	pulse(focus.root)
	o.first = focus.face
end

-- A leaderboard's top 100 (owner 2026-11-12: press E at a board): a scrolling list of rank, face, name
-- and score, the top 3 in their medal colours and your own row in green; under the list, your place.
-- The rows are the server's (State.boards, asked for when the popup opens).
local function boardDef(data: any): any
	local id = if typeof(data) == "table" then data.id else nil
	for _, b in Config.leaderboards.boards do
		if b.id == id then
			return b
		end
	end
	return Config.leaderboards.boards[1]
end

local function board(o: Open)
	local LB = Config.leaderboards
	local P = LB.popup
	local def = boardDef(o.data)
	local got = State.boards[def.id]
	local accent = Theme.boards[def.id] or Theme.info
	local myId = Players.LocalPlayer.UserId
	local top = Instance.new("Frame")
	top.Name = "Rows"
	top.BackgroundTransparency = 1
	top.Size = UDim2.fromScale(1, 1 - P.footHeight - 0.02)
	top.Parent = o.body
	if not got or #got.rows == 0 then
		local t = Ui.inkLabel(top, if got then "Be the first!" else "Loading...", UDim2.fromScale(1, 0.2), UDim2.fromScale(0, 0.4))
		sized(t, "title")
	else
		local l = list(top, true)
		local function circle(parent: Instance, name: string, x: number, color: Color3): Frame
			local c = Instance.new("Frame")
			c.Name = name
			c.BackgroundColor3 = color
			c.BorderSizePixel = 0
			c.AnchorPoint = Vector2.new(0, 0.5)
			c.Position = UDim2.fromScale(x, 0.5)
			c.Size = UDim2.fromScale(0.2, 0.8)
			local a = Instance.new("UIAspectRatioConstraint")
			a.DominantAxis = Enum.DominantAxis.Height
			a.Parent = c
			Ui.corner(c, 0.5)
			Ui.stroke(c, Config.ui.cardStroke)
			c.Parent = parent
			return c
		end
		for i, r in got.rows do
			local line = card(row(l, i, 1, P.rowAspect))
			local medal = Theme.medals[i]
			if r.u == myId then
				line.BackgroundColor3 = Theme.go:Lerp(Theme.white, 0.7)
			elseif medal then
				line.BackgroundColor3 = medal:Lerp(Theme.white, 0.6)
			end
			local rank = circle(line, "Rank", 0.012, medal or Theme.snowFar)
			Ui.inkLabel(rank, tostring(i), UDim2.fromScale(0.84, 0.66), UDim2.fromScale(0.08, 0.17))
			local head = circle(line, "Avatar", 0.105, Theme.ice)
			local img = Instance.new("ImageLabel")
			img.BackgroundTransparency = 1
			img.Size = UDim2.fromScale(1, 1)
			img.Image = `rbxthumb://type=AvatarHeadShot&id={r.u}&w=150&h=150` -- Roblox draws it, no web call
			Ui.corner(img, 0.5)
			img.Parent = head
			-- owner 2026-11-20: a Visit button on every other player's row opens their pan, read-only (ExtrasController draws
			-- it when the server's "panVisit" comes back); the name and score move left to make room
			local canVisit = r.u ~= myId
			local name = text(line, r.n, 0.205, if canVisit then 0.3 else 0.44)
			-- the circles are as wide as the row is tall, so on a phone's taller rows they ran into each other
			-- and into the name ("1(" and "Aplayer", QA 2026-11-17): place them from the row's real size (on PC
			-- this lands where the fixed 0.105 / 0.205 did)
			local function fit()
				local w, h = line.AbsoluteSize.X, line.AbsoluteSize.Y
				if w <= 0 or h <= 0 then
					return
				end
				local d, gap = 0.8 * h, 0.012 * w
				head.Position = UDim2.new(0, gap * 2 + d, 0.5, 0)
				name.Position = UDim2.new(0, gap * 3 + d * 2, name.Position.Y.Scale, 0)
			end
			line:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
			task.defer(fit)
			local coins = def.id == "coins_week"
			local shift = if canVisit then 0.18 else 0
			local score = text(line, r.s, 0.65 - shift, if coins then 0.26 else 0.33)
			score.TextXAlignment = Enum.TextXAlignment.Right
			if coins then
				Ui.image(line, Config.images.icons.coin, UDim2.fromScale(0.06, 0.7), UDim2.fromScale(0.925 - shift, 0.15))
			end
			if canVisit then
				local userId = r.u
				local vb = button(line, Theme.go, "Visit", 0.825, 0.165, function()
					State.send("VisitPan", userId)
				end)
				vb.root.Name = "Visit"
				if not o.first then
					o.first = vb.face -- a controller starts on the first Visit (your own row has none: QA 2026-11-20, you at #1 sent it to the X)
				end
			end
		end
	end
	-- your own place, always in view under the list
	local foot = Ui.block(o.body, "YourPlace", accent, "", nil)
	foot.root.Position = UDim2.fromScale(0, 1 - P.footHeight)
	foot.root.Size = UDim2.fromScale(1, P.footHeight)
	foot.text.Text = if not got then "" elseif got.place then `Your place: #{got.place}` else `Your place: not in the top {LB.rankScanSize} yet`
	sized(foot.text, "body")
end

-- the builders the Equipment Booth popup borrows (EquipmentPopup)
local helpers: EquipmentPopup.Helpers = {
	list = list, row = row, button = button, text = text, card = card, sized = sized, priceTag = priceTag, bar = bar, pulse = pulse,
	refresh = function()
		PopupController.refresh()
	end,
}

local function fill(o: Open)
	for _, c in o.body:GetChildren() do
		c:Destroy()
	end
	o.first = nil
	local v = State.view
	o.shown = if v then shownData(o.name, v) else nil
	if o.name == "settings" then
		settings(o)
	elseif o.name == "welcome" then
		local w = o.data
		local hours = math.floor(w.awaySeconds / 3600)
		reward(o, w.coins, if w.capped then "Your pets earned this while you were away (8 h max)"
			elseif hours > 0 then `Your pets earned this in {hours} h away` else "Your pets earned this while you were away", "Collect", function()
			State.send("CollectWelcome")
		end, if w.coins >= Config.monetization.welcomeDoubleMin then Config.robuxItem("welcomeDouble") else nil)
	elseif o.name == "mailThanks" then
		message(o, { "Thank you!", "We read every message." }, "OK", function() end)
	elseif o.name == "gift" then
		reward(o, o.data.coins, `and +{Ui.commas(o.data.power or 0)} Cold Power. Thank you!`, "Yay", function() end)
	elseif o.name == "pageDone" then
		local zone = Config.zone(o.data.zone)
		-- a full page: claim its +10% right here (or later in the Index)
		message(o, { `{if zone then zone.name else "Zone"} page full!`, `Claim +{math.round(o.data.bonus * 100)}% coins forever` }, "Claim", function()
			State.send("ClaimPage", o.data.zone)
		end)
	elseif v then
		if o.name == "shop" then
			shop(o, v)
		elseif o.name == "pets" then
			pets(o, v)
		elseif o.name == "thaw" then
			thaw(o, v)
		elseif o.name == "index" then
			index(o, v)
		elseif o.name == "daily" then
			daily(o, v)
		elseif o.name == "freeGift" then
			freeGift(o, v)
		elseif o.name == "board" then
			board(o)
		elseif o.name == "tester" then
			tester(o, v)
		elseif o.name == "equipment" then
			EquipmentPopup.fill(o, v, helpers)
		elseif o.name == "pan" then
			PanPopup.fill(o, v, helpers)
		elseif o.name == "sell" then
			SellPopup.fill(o, v, helpers)
		elseif o.name == "rebirth" then
			RebirthPopup.fill(o, v, helpers)
		elseif o.name == "mail" then
			MailPopup.fill(o, v, helpers)
		end
	end
	-- nothing to press yet (Index, Daily with nothing to claim): a controller still lands on the X
	-- (device QA 2026-11-13, console)
	InputController.select(o.first or (o :: any).closeFace)
end

function PopupController.isOpen(): boolean
	return current ~= nil
end

-- which popup is open ("equipment", "sell" ...), nil when none
function PopupController.openName(): string?
	return if current then current.name else nil
end

function PopupController.refresh()
	local o = current
	if o then
		local scroll = o.body:FindFirstChildWhichIsA("ScrollingFrame", true)
		local at = if scroll then scroll.CanvasPosition else nil
		local canvas = if scroll then scroll.CanvasSize else nil
		fill(o)
		local again = o.body:FindFirstChildWhichIsA("ScrollingFrame", true)
		if again and at and canvas then
			-- the new list hasn't been measured yet (its canvas is 0 tall), so the old position would be
			-- clamped to the top: borrow the old canvas until the layout measures the new one
			again.CanvasSize = canvas
			again.CanvasPosition = at
		end
	end
end

function PopupController.close()
	local o = current
	if not o then
		return
	end
	o.frame:Destroy()
	o.closed = true
	current = nil
	Screen.setMenuHidden(false)
	Screen.setPopupOpen(false)
	InputController.select(nil)
	State.send("SetMenuOpen", false)
	local nextOne = table.remove(queue, 1)
	if nextOne then
		PopupController.open(nextOne.name, nextOne.data)
	end
end

-- rebuilt = the same popup drawn again for a new screen size (no "ShopOpened" twice)
-- the Shop's opening (owner 2026-11-16: "add opening animations to the shop just like in the reference", the
-- 2026-11-12 Halloween and Autumn shop clips in the vault): the screen washes over in the Shop's colour, the panel
-- pops up from small, the title bar drops in, then each section title and card pops in one after another (a soft
-- rising tink each), and last the island pets hop onto the corners. Numbers in Config.ui.shop.opening. Reduced
-- motion: only the colour wash and a quick fade. Everything it adds goes with the popup.
local function shopOpening(o: Open, panel: Ui.Block, header: Ui.Block)
	local OP = Config.ui.shop.opening
	local still = SettingsController.get("reducedMotion") == true
	local frame = o.frame
	-- the wash: a big soft sheet behind the panel in the Shop's colours (under the panel, over the world)
	local wash = Instance.new("Frame")
	wash.Name = "OpeningWash"
	wash.AnchorPoint = Vector2.new(0.5, 0.5)
	wash.Position = UDim2.fromScale(0.5, 0.5)
	wash.Size = UDim2.fromScale(12, 12)
	wash.BackgroundColor3 = Theme.white
	wash.BackgroundTransparency = 1
	wash.BorderSizePixel = 0
	wash.ZIndex = 0
	local wg = Instance.new("UIGradient")
	wg.Rotation = 90
	wg.Color = ColorSequence.new(Theme.shopFrame.top, Theme.shopFrame.bottom)
	wg.Parent = wash
	wash.Parent = frame
	TweenService:Create(wash, TweenInfo.new(OP.washSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = OP.washAlpha }):Play()
	if still then
		return
	end
	-- the panel pops up from small
	local ps = Instance.new("UIScale")
	ps.Scale = OP.panelFrom
	ps.Parent = panel.root
	TweenService:Create(ps, TweenInfo.new(OP.panelSeconds, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	-- the title bar drops in from above
	local hp = header.root.Position
	header.root.Position = UDim2.new(hp.X.Scale, hp.X.Offset, hp.Y.Scale - OP.headerDrop, hp.Y.Offset)
	TweenService:Create(header.root, TweenInfo.new(OP.headerSeconds, Enum.EasingStyle.Back, Enum.EasingDirection.Out, 0, false, OP.panelSeconds * 0.5), { Position = hp }):Play()
	-- the island pets on the corners start hidden and hop on at the end
	local mascots: { GuiObject } = {}
	for _, c in panel.root:GetChildren() do
		if c:IsA("GuiObject") and string.sub(c.Name, 1, 7) == "Mascot_" then
			local ms = Instance.new("UIScale")
			ms.Scale = 0
			ms.Parent = c
			table.insert(mascots, c)
		end
	end
	-- each row of the page (section titles, banners, card rows): hidden, then popped in one after another
	task.defer(function()
		local sf = o.body:FindFirstChildWhichIsA("ScrollingFrame", true)
		local rows: { GuiObject } = {}
		if sf then
			for _, c in sf:GetChildren() do
				if c:IsA("GuiObject") and c.Visible then
					table.insert(rows, c)
				end
			end
			table.sort(rows, function(a, b)
				return a.LayoutOrder < b.LayoutOrder
			end)
		end
		local scales: { UIScale } = {}
		for _, r in rows do
			local s = r:FindFirstChild("OpeningPop") :: UIScale? or Instance.new("UIScale")
			s.Name = "OpeningPop"
			s.Scale = 0.01
			s.Parent = r
			table.insert(scales, s)
		end
		task.wait(OP.panelSeconds * 0.6)
		for i, s in scales do
			if o.closed then
				break
			end
			TweenService:Create(s, TweenInfo.new(OP.rowSeconds, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
			if i <= OP.tinks then
				SoundController.play("tink", 1 + i * 0.08)
			end
			task.wait(OP.rowGap)
		end
		for _, s in scales do
			s.Scale = 1 -- a row that was closed mid-way, or rows past the stagger, all end full size
		end
		for k, m in mascots do
			local ms = m:FindFirstChildOfClass("UIScale")
			if ms and not o.closed then
				TweenService:Create(ms, TweenInfo.new(OP.mascotSeconds, Enum.EasingStyle.Back, Enum.EasingDirection.Out, 0, false, (k - 1) * 0.08), { Scale = 1 }):Play()
			end
		end
	end)
end

function PopupController.open(name: string, data: any?, rebuilt: boolean?)
	if name == "tester" and not (State.view and State.view.tester) then
		return -- not a tester: the panel doesn't exist
	end
	if current then
		if current.name == name and MENUS[name] then
			PopupController.close() -- pressing the same tile again closes it
			return
		end
		if not MENUS[name] then
			table.insert(queue, { name = name, data = data }) -- rewards wait their turn
			return
		end
		PopupController.close()
	end
	-- on a touch screen (phone or tablet) every full menu hides the HUD (device QA 2026-11-13: squeezed
	-- between the tiles and the coin number, Pets / Daily / Settings / Pan / Thaw came out half the screen
	-- wide on a phone and a third of it on a tablet, with 8 px text)
	local hideHud = Config.ui.hideHudFor[name] == true or (Screen.deviceClass() ~= "pc" and not SMALL[name])
	local frame = Screen.popupFrame(Config.ui.bigPopups[name] == true, not hideHud)
	-- short messages get a smaller panel; on a phone only a little smaller, or their text came out 8.8 px
	local smallK = if Screen.deviceClass() == "phone" then Config.ui.phoneSmallPopup else 0.62
	if SMALL[name] then
		frame.Size = UDim2.fromScale(frame.Size.X.Scale * smallK, frame.Size.Y.Scale * smallK)
	end
	local T = Config.ui.popupText
	local ph = frame.AbsoluteSize.Y / (if SMALL[name] then smallK else 1) -- text keeps the big panel's sizes
	px = { title = ph * T.title, body = ph * T.body, small = ph * T.small, button = ph * T.button, tiny = ph * T.small * 0.72,
		big = ph * T.title * Config.ui.shop.bigText }
	if Screen.deviceClass() ~= "pc" then
		-- touch screens: no role's cap under a readable size (a 338 px tall phone capped small text at 10 px).
		-- Only the cap rises: text whose box is too small still shrinks to fit (sized)
		local F = Config.ui.touchTextFloor
		for role, size in px do
			px[role] = math.max(size, F[role] or F.small)
		end
	end
	-- the body is a pale tint of the menu's colour and the title sits on a ribbon in the full colour,
	-- so the popup reads as one piece with its tile (a flat cream body looked like another game's UI)
	local menuColor = HEADER[name] or Theme.tiles[name] or Theme.info
	local titleText, iconId = TITLES[name] or "", HEADER_ICONS[name]
	if name == "board" then
		-- a leaderboard's popup wears its board's colour, title and icon
		local def = boardDef(data)
		menuColor = Theme.boards[def.id] or Theme.info
		titleText, iconId = def.title, Config.images.icons[def.icon]
	end
	local panel = Ui.block(frame, "Panel", menuColor:Lerp(Theme.white, Config.ui.panelTint), "", nil, true)
	panel.root.Size = UDim2.fromScale(1, 1)
	panel.text.Visible = false
	local hh = Config.ui.headerHeight / (if SMALL[name] then smallK else 1)
	local header = Ui.block(panel.face, "Header", menuColor, titleText, nil)
	header.root.Position = UDim2.fromScale(0.02, 0.025)
	header.root.Size = UDim2.fromScale(0.96, hh)
	sized(header.text, "title")
	-- the menu's own icon beside its title, centred together by their visible width
	if iconId then
		local icon = Ui.image(header.face, iconId, UDim2.fromScale(0.2, 1.1), UDim2.fromScale(0, -0.05))
		icon.ZIndex = 2
		task.defer(function()
			local w = math.max(1, header.face.AbsoluteSize.X)
			local iconW, gap, textW = icon.AbsoluteSize.X / w, 0.012, header.text.TextBounds.X / w
			local x = 0.5 - (iconW + gap + textW) / 2
			icon.Position = UDim2.fromScale(x + iconW / 2, 0.5)
			header.text.Position = UDim2.fromScale(x + iconW + gap - (header.text.Size.X.Scale - textW) / 2, header.text.Position.Y.Scale)
		end)
	end
	local closeB = Ui.block(panel.face, "Close", Theme.no, "X", PopupController.close)
	closeB.root.AnchorPoint = Vector2.new(1, 0)
	closeB.root.Position = UDim2.fromScale(0.975, 0.035)
	closeB.root.Size = UDim2.fromScale(0.2, hh * 0.8)
	local ca = Instance.new("UIAspectRatioConstraint")
	ca.AspectRatio = 1.15
	ca.Parent = closeB.root
	sized(closeB.text, "title")
	-- an invisible tap area round the X, never under a thumb's size (mobile QA 2026-11-10: the X was 27x20 px on a phone)
	local hit = Instance.new("TextButton")
	hit.Name = "CloseHit"
	hit.Text = ""
	hit.BackgroundTransparency = 1
	hit.Selectable = false
	hit.AnchorPoint = Vector2.new(0.5, 0.5)
	hit.Position = UDim2.fromScale(0.5, 0.5)
	hit.ZIndex = 0 -- under the X's face (a tap on the X itself still plays its press), over the ribbon beside it
	hit.Parent = closeB.root
	closeB.root.ZIndex = 2
	local function fitHit()
		local s = closeB.root.AbsoluteSize
		local m = Config.ui.minTouchPx
		hit.Size = UDim2.fromScale(math.max(1, m / math.max(1, s.X)), math.max(1, m / math.max(1, s.Y)))
	end
	closeB.root:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitHit)
	fitHit()
	hit.Activated:Connect(function()
		SoundController.play("click")
		PopupController.close()
	end)
	local body = Instance.new("Frame")
	body.Name = "Body"
	body.BackgroundTransparency = 1
	body.Position = UDim2.fromScale(0.04, 0.05 + hh)
	body.Size = UDim2.fromScale(0.92, 0.92 - hh)
	body.Parent = panel.face
	local o: Open = { name = name, data = data, frame = frame, body = body, first = nil }
	;(o :: any).closeFace = closeB.face
	current = o
	Screen.setMenuHidden(hideHud)
	Screen.setPopupOpen(true)
	State.send("SetMenuOpen", true)
	if name == "shop" and not rebuilt then
		shopTab = nil -- each visit starts on its default tab
		shopWant = if typeof(data) == "table" and typeof(data.tab) == "string" then data.tab else nil
		State.send("ShopOpened")
	end
	if name == "board" and not rebuilt then
		State.send("GetBoard", boardDef(data).id) -- the answer ("boardRows") draws the list
	end
	if name == "tester" then
		-- the server's readout while the panel is open (it also brings the teleport list)
		task.spawn(function()
			while not o.closed do
				State.send("Tester", "readout")
				task.wait(Config.dev.readoutSeconds)
			end
		end)
	end
	fill(o)
	-- QA 2026-11-20 (PT-04): the Thaw Machine with one pet filled ~15% of a full-height panel. A list popup
	-- shrinks to its rows (UI Rules: popups fit their content); header, X and body go to pixels first so
	-- they keep their size, and the text keeps the big panel's sizes. Rows are measured from their shape
	-- (width / aspect), not their AbsoluteSize, because the open animation starts them scaled down.
	if FIT[name] then
		local H = frame.AbsoluteSize.Y
		local lst = body:FindFirstChild("List") :: GuiObject?
		local layout = lst and lst:FindFirstChildOfClass("UIListLayout")
		if lst and layout and H > 0 then
			local pad = lst:FindFirstChildOfClass("UIPadding")
			local padT = if pad then pad.PaddingTop.Scale * lst.AbsoluteSize.Y + pad.PaddingTop.Offset else 0
			local padB = if pad then pad.PaddingBottom.Scale * lst.AbsoluteSize.Y + pad.PaddingBottom.Offset else 0
			local padX = if pad then (pad.PaddingLeft.Scale + pad.PaddingRight.Scale) * lst.AbsoluteSize.X else 0
			local w = lst.AbsoluteSize.X - padX - (if lst:IsA("ScrollingFrame") then lst.ScrollBarThickness else 0)
			local gap = layout.Padding.Scale * lst.AbsoluteSize.Y + layout.Padding.Offset
			local contentH, n = padT + padB, 0
			for _, r in lst:GetChildren() do
				if r:IsA("GuiObject") and r.Visible then
					local a = r:FindFirstChildOfClass("UIAspectRatioConstraint")
					contentH += if a then w / a.AspectRatio else r.Size.Y.Scale * lst.AbsoluteSize.Y + r.Size.Y.Offset
					n += 1
				end
			end
			contentH += math.max(0, n - 1) * gap
			local top = (0.05 + hh) * H
			local newH = math.clamp(top + contentH + 0.04 * H, H * 0.42, H)
			if newH < H - 4 then
				header.root.Position = UDim2.new(0.02, 0, 0, 0.025 * H)
				header.root.Size = UDim2.new(0.96, 0, 0, hh * H)
				closeB.root.Position = UDim2.new(0.975, 0, 0, 0.035 * H)
				closeB.root.Size = UDim2.new(0.2, 0, 0, hh * 0.8 * H)
				body.Position = UDim2.new(0.04, 0, 0, top)
				body.Size = UDim2.new(0.92, 0, 0, newH - top - 0.02 * H)
				-- a shape lock on the frame would narrow it too: give it the new, wider shape
				local lock = frame:FindFirstChildOfClass("UIAspectRatioConstraint")
				if lock then
					lock.AspectRatio = frame.AbsoluteSize.X / newH
				end
				frame.Size = UDim2.new(frame.Size.X.Scale, frame.Size.X.Offset, frame.Size.Y.Scale * newH / H, frame.Size.Y.Offset * newH / H)
			end
		end
	end
	if name == "shop" and not rebuilt then
		shopOpening(o, panel, header)
	end
end

function PopupController.Init() end

function PopupController.Start()
	-- Studio-only test hook (device QA 2026-11-13): touch taps can't be sent from a test script, so setting
	-- the player attribute DevOpen = "name" or "name:tab" opens that popup ("close" closes it). Off in live servers.
	if game:GetService("RunService"):IsStudio() then
		local lp = game:GetService("Players").LocalPlayer
		lp:GetAttributeChangedSignal("DevOpen"):Connect(function()
			local v = lp:GetAttribute("DevOpen")
			if typeof(v) ~= "string" or v == "" then
				return
			end
			local name, tab = string.match(v, "^([^:]+):?(.*)$")
			if name == "close" then
				PopupController.close()
			elseif name then
				PopupController.close()
				PopupController.open(name, if tab ~= "" then { tab = tab } else nil)
			end
		end)
	end
	task.spawn(function()
		local ok, yes = pcall(function()
			return SocialService:CanSendGameInviteAsync(Players.LocalPlayer)
		end)
		-- shown in Studio too, so its layout can be checked (the prompt itself only opens in the real game)
		canInvite = (ok and yes == true) or RunService:IsStudio()
	end)
	InputController.Action:Connect(function(a: string)
		if a == "close" then
			PopupController.close()
		elseif MENUS[a] then
			PopupController.open(a)
		end
	end)
	State.Changed:Connect(function(v: State.View)
		local o = current
		if o and o.update then
			o.update(v)
		elseif o and MENUS[o.name] and o.name ~= "settings" then
			local key = shownData(o.name, v)
			if key == nil or key ~= o.shown then
				PopupController.refresh()
			end
		end
	end)
	game:GetService("RunService").RenderStepped:Connect(function(dt: number)
		if current and current.name == "tester" then -- only the Tester readout shows it
			fps = fps * 0.95 + (1 / math.max(dt, 1e-3)) * 0.05
		end
	end)
	-- the screen changed size (iPad split view, a resized window, the top bar): text sizes and corners are
	-- worked out when a popup opens, so the open one is drawn again for the new size (mobile QA 2026-11-10)
	local resizeToken = 0
	local function redraw()
		resizeToken += 1
		local my = resizeToken
		task.delay(0.15, function()
			local o = current
			if my ~= resizeToken or not o or o.closed then
				return
			end
			-- typing: a phone's keyboard sliding up resizes the screen; don't rebuild the box under the finger
			local typing = game:GetService("UserInputService"):GetFocusedTextBox()
			if typing and typing:IsDescendantOf(o.frame) then
				return
			end
			o.closed = true
			o.frame:Destroy()
			current = nil
			PopupController.open(o.name, o.data, true)
		end)
	end
	local popups = Screen.popups
	if popups then
		popups:GetPropertyChangedSignal("AbsoluteSize"):Connect(redraw)
	end
	InputController.DeviceChanged:Connect(redraw) -- touch vs mouse picks the phone layout
	State.Notify:Connect(function(kind: string, data: any)
		if kind == "testerReadout" then
			local hadTargets = testerReadout.targets ~= nil
			testerReadout = data
			local o = current
			if o and o.name == "tester" then
				if not hadTargets then
					PopupController.refresh() -- the teleport buttons arrive with the first readout
				elseif o.update and State.view then
					o.update(State.view)
				end
			end
		elseif kind == "boardRows" then
			boardStamp += 1
			local o = current
			if o and o.name == "board" and boardDef(o.data).id == data then
				PopupController.refresh()
			end
		elseif kind == "welcomeBack" then
			PopupController.open("welcome", data)
		elseif kind == "freeGift" then
			PopupController.open("freeGift", data)
		elseif kind == "feedbackSent" then
			MailPopup.sent()
			if current and current.name == "mail" then
				PopupController.close()
			end
			PopupController.open("mailThanks", data)
		elseif kind == "feedbackRows" then
			testerMail = if typeof(data) == "table" and typeof(data.rows) == "table" then data.rows else {}
			if current and current.name == "tester" then
				PopupController.refresh()
			end
		elseif kind == "giftClaimed" then
			if current and current.name == "freeGift" then
				PopupController.close()
			end
			PopupController.open("gift", data)
		elseif kind == "pageDone" then
			PopupController.open("pageDone", data)
		elseif kind == "pageClaimed" then
			SoundController.play("coin")
		end
	end)
end

return PopupController
