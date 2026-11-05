--!strict
-- PopupController: owns every popup (Pets, Shop, Index, Settings, welcome back, gift, page done).
-- One at a time, centred a little above the middle; reward popups wait in a queue behind a menu.
-- Buttons only send intent; the server answers and the next "Data" redraws the popup.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
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
local RebirthPopup = require(script.Parent.RebirthPopup)

local PopupController = {}

-- update: set by popups that change their own labels instead of being rebuilt (the Tester panel)
type Open = { name: string, data: any, frame: Frame, body: Frame, first: GuiObject?, update: ((State.View) -> ())?, closed: boolean?, shown: string? }
local current: Open? = nil
local queue: { { name: string, data: any } } = {}
local MENUS = { pets = true, shop = true, index = true, settings = true, tester = true, equipment = true, pan = true, sell = true, rebirth = true }
local TITLES: { [string]: string } = {
	pets = "Pets", shop = "Shop", index = "Index", settings = "Settings", tester = "Tester", equipment = "Equipment",
	pan = "Pan Upgrades", sell = "Sell Booth", rebirth = "Rebirth Booth",
	welcome = "Welcome back!", gift = "Daily gift", pageDone = "Page complete!",
}

-- what a scrolling menu shows; it's only rebuilt when this changes, so a coin tick doesn't throw
-- the list away (and the player's scroll and drag with it) every second (owner QA 2026-10-31).
-- Built field by field: State.Changed hands out a copy whose keys can come in another order, so
-- JSON of the two never matched.
local function shownData(name: string, v: State.View): string?
	local parts: { string } = {}
	if name == "pets" then
		table.insert(parts, tostring(v.slots))
		for _, p in v.pets do
			table.insert(parts, `{p.id},{p.key},{p.pose},{p.mut},{p.eq},{p.income}`)
		end
	elseif name == "index" then
		for _, p in v.pages do
			table.insert(parts, `{p.zone},{p.found},{p.total},{p.complete},{p.secretFound}`)
		end
		local keys: { string } = {}
		for key, on in v.found do
			if on then
				table.insert(keys, key)
			end
		end
		table.sort(keys)
		table.insert(parts, table.concat(keys, ","))
	elseif name == "equipment" then
		return EquipmentPopup.shownKey(v)
	elseif name == "pan" then
		return PanPopup.shownKey(v)
	elseif name == "sell" then
		return SellPopup.shownKey(v)
	elseif name == "rebirth" then
		return RebirthPopup.shownKey(v)
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
	welcome = Theme.coin, gift = Theme.gift, pageDone = Theme.go, tester = Theme.info, equipment = Theme.booths.equipment,
	pan = Theme.booths.pan, sell = Theme.booths.sell, rebirth = Theme.booths.rebirth,
}
local SMALL = { welcome = true, gift = true, pageDone = true } -- short messages get a smaller panel
local HEADER_ICONS: { [string]: string } = {
	pets = Config.ui.tileIcons.pets, shop = Config.ui.tileIcons.shop, index = Config.ui.tileIcons.index,
	settings = Config.ui.tileIcons.settings, welcome = Config.images.icons.coin, gift = Config.images.icons.gift,
}

-- text sizes for the open popup, one per role (Config.ui.popupText x the popup's height)
local px: { [string]: number } = { title = 30, body = 22, small = 16, button = 20 }
local function sized(t: TextLabel, role: string)
	t.TextScaled = false
	t.TextWrapped = true
	t.TextSize = px[role] or px.body
end

-- a row of blocks laid out left to right; widths are fractions of the row
-- aspect: inside a scrolling list the height comes from the width (Scale of an auto-sized canvas would loop)
local function row(parent: Instance, order: number, height: number, aspect: number?): Frame
	local f = Instance.new("Frame")
	f.Name = "Row" .. order -- unique names, so QA tools can click a button by its path
	f.LayoutOrder = order
	f.BackgroundTransparency = 1
	f.Size = UDim2.fromScale(1, if aspect then 1 else height)
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
local function robuxTag(b: Ui.Block)
	local mark = Ui.image(b.face, Config.images.icons.robux, UDim2.fromScale(0.3, 0.62), UDim2.fromScale(0, 0.19))
	mark.ZIndex = 2
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

-- ---------- contents ----------
-- one Robux product as a Chunky Pop block in its kind's colour (Theme.shopCards): the painted icon
-- (stacked 1-3 deep for bigger packs), the name, what it gives, and a green Robux button.
-- featured = the wide banner on top (icon left, words middle, button right); else a tall tile.
local function robuxCard(o: Open, v: State.View, parent: Instance, item: Config.RobuxItem, featured: boolean): Ui.Block
	local owned = item.kind == "pass" and v.doubleCoins == true
	local c = Ui.block(parent, "Robux_" .. item.id, Theme.shopCards[item.kind] or Theme.info, "", nil)
	c.text.Visible = false
	local function box(t: GuiObject, x: number, y: number, w: number, h: number)
		t.Position = UDim2.fromScale(x, y)
		t.Size = UDim2.fromScale(w, h)
	end
	-- the picture: copies of the icon fanned out behind the front one, the group centred on its box
	local icon = Config.images.icons[item.icon] or Config.images.icons.coin
	local stack = item.stack or 1
	local ix, iy, iw, ih = 0.2, 0.05, 0.6, 0.38
	if featured then
		ix, iy, iw, ih = 0.03, 0.1, 0.2, 0.8
	end
	local step = iw * 0.16
	for k = stack, 1, -1 do
		local dx = (k - 1) * step - (stack - 1) * step / 2
		local img = Ui.image(c.face, icon, UDim2.fromScale(iw, ih), UDim2.fromScale(ix + dx, iy - (k - 1) * ih * 0.06))
		img.ZIndex = 1 + stack - k
	end
	local name = Ui.label(c.face, item.name)
	name.Name = "Name"
	sized(name, if featured then "title" else "body")
	local gives = if item.kind == "coins" then `+{Ui.short(Config.robuxCoins(item, v.income))} coins` else item.text
	local what = Ui.label(c.face, gives)
	what.Name = "Gives"
	sized(what, "small")
	local b = button(c.face, if owned then Theme.info else Theme.go, if owned then "Owned" else tostring(item.robux), 0, 1, function()
		if not owned then
			State.send("BuyRobux", item.id)
		end
	end)
	b.root.Name = "Buy"
	if featured then
		for _, t in { name, what } do
			t.TextXAlignment = Enum.TextXAlignment.Left
		end
		box(name, 0.26, 0.14, 0.42, 0.4)
		box(what, 0.26, 0.56, 0.42, 0.3)
		box(b.root, 0.7, 0.2, 0.27, 0.56)
	else
		box(name, 0.04, 0.45, 0.92, 0.16)
		box(what, 0.04, 0.6, 0.92, 0.12)
		box(b.root, 0.08, 0.75, 0.84, 0.19)
	end
	if not owned then
		robuxTag(b)
	end
	if not o.first then
		o.first = b.face
	end
	return c
end

-- the Shop is the Robux shop: the 2x Coins pass as a wide banner on top, the packs as a row of tiles
-- under it. Buttons only ask; the server shows Roblox's own purchase prompt and grants in ProcessReceipt.
local function robuxShop(o: Open, v: State.View, holder: Frame)
	local pass: Config.RobuxItem? = nil
	local packs: { Config.RobuxItem } = {}
	for _, item in Config.monetization.shop do
		if not Config.robuxReady(item) and not RunService:IsStudio() then
			continue -- not made in the Creator Dashboard yet
		end
		if item.kind == "pass" and not pass then
			pass = item
		else
			table.insert(packs, item)
		end
	end
	if not pass and #packs == 0 then
		local t = Ui.inkLabel(holder, "Coming soon", UDim2.fromScale(1, 0.2), UDim2.fromScale(0, 0.4))
		sized(t, "title")
		return
	end
	local top = 0
	if pass then
		local banner = robuxCard(o, v, holder, pass, true)
		banner.root.Size = UDim2.fromScale(1, 0.34)
		top = 0.39
	end
	local tiles = Instance.new("Frame")
	tiles.Name = "Packs"
	tiles.BackgroundTransparency = 1
	tiles.Position = UDim2.fromScale(0, top)
	tiles.Size = UDim2.fromScale(1, 1 - top)
	tiles.Parent = holder
	local gap = 0.025
	local w = math.min(0.3, (1 - gap * (#packs - 1)) / math.max(1, #packs))
	local left = (1 - (w * #packs + gap * (#packs - 1))) / 2
	for i, item in packs do
		local t = robuxCard(o, v, tiles, item, false)
		t.root.Position = UDim2.fromScale(left + (i - 1) * (w + gap), 0)
		t.root.Size = UDim2.fromScale(w, 1)
	end
end

-- the Shop is the Robux shop (owner 2026-11-05: the coin Upgrades list is gone; levels already
-- bought still count, and the pan's Slots stay at the Pan Upgrades stand)
local function shop(o: Open, v: State.View)
	robuxShop(o, v, o.body)
end

local function pets(o: Open, v: State.View)
	local pen = 0
	for _, p in v.pets do
		if p.eq then
			pen += 1
		end
	end
	local head = row(o.body, 0, 0.14)
	text(head, `Pan {pen} / {v.slots}   Storage {#v.pets - pen}`, 0.02, 0.6)
	local best = button(head, Theme.go, "Equip best", 0.66, 0.32, function()
		State.send("EquipBest")
	end)
	o.first = best.face
	local holder = Instance.new("Frame")
	holder.BackgroundTransparency = 1
	holder.Position = UDim2.fromScale(0, 0.16)
	holder.Size = UDim2.fromScale(1, 0.84)
	holder.Parent = o.body
	local l = list(holder, true)
	local sorted = table.clone(v.pets)
	table.sort(sorted, function(a, b)
		if a.eq ~= b.eq then
			return a.eq
		end
		return a.income > b.income
	end)
	if #sorted == 0 then
		text(row(l, 1, 0, 9), "Freeze a pet and carry it to your pan!", 0.02, 0.96)
	end
	for i, p in sorted do
		local def = PetDefs.get(p.key)
		if not def then
			continue
		end
		local r = card(row(l, i, 0, 7.5))
		local pose = Config.poses[p.pose]
		if def.icon ~= "" then
			Ui.image(r, def.icon, UDim2.fromScale(0.11, 0.92), UDim2.fromScale(0.01, 0.04))
		end
		-- the name on top; under it the tier, mutation and pose, each word in its own colour
		-- (tinting the painted sprite made Starry muddy and Golden orange, QA 2026-10-31)
		local name = text(r, def.name, 0.13, 0.4)
		name.Size = UDim2.fromScale(0.4, 0.5)
		name.Position = UDim2.fromScale(0.13, 0.04)
		local function word(s: string, c: Color3): string
			return `<font color="#{c:ToHex()}">{s}</font>`
		end
		local tags = { word(def.tier, Ui.darker(tierColor(def.tier))) }
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
		Ui.image(r, Config.images.icons.coin, UDim2.fromScale(0.07, 0.6), UDim2.fromScale(0.52, 0.2))
		text(r, `{Ui.short(p.income)}/s`, 0.585, 0.13)
		-- a small toggle, not a big green button: the pet is the point of the row
		local tog = button(r, if p.eq then Theme.go else Theme.info, if p.eq then "In pen" else "Stored", 0.78, 0.19, function()
			State.send("EquipPet", p.id, not p.eq)
		end)
		tog.root.Position = UDim2.fromScale(0.78, 0.2)
		tog.root.Size = UDim2.fromScale(0.19, 0.6)
		sized(tog.text, "small")
	end
end

local function index(o: Open, v: State.View)
	local l = list(o.body, true)
	for i, page in v.pages do
		local zone = Config.zone(page.zone)
		local head = row(l, i * 10, 0, 10)
		text(head, `{if zone then zone.name else "Zone"}  {page.found} / {page.total}`, 0.02, 0.6)
		text(head, if page.complete then `+{math.round(Config.index.pageBonus * 100)}% coins` else `Fill it: +{math.round(Config.index.pageBonus * 100)}% coins`, 0.6, 0.38, Ui.darker(Theme.coin), "small").TextXAlignment = Enum.TextXAlignment.Right
		local grid = row(l, i * 10 + 1, 0, 2.6)
		local g = Instance.new("UIGridLayout")
		g.CellSize = UDim2.fromScale(0.23, 0.45)
		g.CellPadding = UDim2.fromScale(0.02, 0.05)
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
			-- the painted pet, or its dark silhouette while it's still missing (the Secret stays a mystery)
			if def.icon ~= "" and (found or not secret) then
				Ui.image(b.face, def.icon, UDim2.fromScale(0.8, 0.66), UDim2.fromScale(0.1, 0.02), not found)
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
end

local function settings(o: Open)
	local l = list(o.body, false)
	local rows = {
		{ key = "music", label = "Music" }, { key = "sound", label = "Sound" },
		{ key = "reducedMotion", label = "Reduced motion" }, { key = "lowGraphics", label = "Low graphics" },
		{ key = "unit", label = "Temperature in F" },
	}
	for i, r in rows do
		local line = card(row(l, i, 0.145))
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
	-- Codes (Round 5): unlocked after catching Config.codes.needPets pets; the server checks the code
	local v = State.view
	local need = Config.codes.needPets
	local caught = if v then v.stats.frozen else 0
	local line = card(row(l, #rows + 1, 0.145))
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

local function tester(o: Open, v: State.View)
	local D = Config.dev
	local l = list(o.body, true)
	local updates: { (State.View) -> () } = {}
	local order = 0
	local function line(): Frame
		order += 1
		return row(l, order, 0, 9)
	end
	local function heading(s: string)
		local t = text(line(), s, 0.02, 0.96, Theme.coin)
		t.TextXAlignment = Enum.TextXAlignment.Left
	end
	local function send(action: string, a: any?, b: any?)
		State.send("Tester", action, a, b)
	end
	local function toggle(r: Frame, label: string, x: number, w: number, get: (State.View) -> boolean, action: string)
		local b = button(r, Theme.no, label, x, w, function()
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

	-- readout
	local readout = text(line(), "", 0.02, 0.96)
	table.insert(updates, function()
		local parts = 0
		for _, d in workspace:GetDescendants() do
			if d:IsA("BasePart") then
				parts += 1
			end
		end
		local r = testerReadout
		readout.Text = `FPS {math.round(fps)}   Parts {Ui.commas(parts)}   Server: {Ui.short(r.coins or 0)} coins, x{r.mult or 1}, rebirths {r.rebirths or 0}`
	end)

	heading("Money multiplier")
	local r = line()
	local multNow = text(r, "", 0.02, 0.2)
	local multBox = numberBox(r, "0.1 - 10000", 0.23, 0.22)
	local setB = button(r, Theme.go, "Set", 0.46, 0.12, function()
		local n = tonumber(multBox.Text)
		if n then
			send("mult", n)
		end
	end)
	o.first = setB.face
	for i, p in D.multPresets do
		button(r, if p == 1 then Theme.no else Theme.info, if p == 1 then "Reset" else `{p}x`, 0.59 + (i - 1) * 0.1, 0.095, function()
			send("mult", p)
		end)
	end
	table.insert(updates, function(view)
		multNow.Text = `Now x{if view.tester then view.tester.mult else 1}`
	end)

	heading("Coins")
	r = line()
	local coinBox = numberBox(r, "Exact amount", 0.02, 0.3)
	button(r, Theme.go, "Set", 0.33, 0.14, function()
		local n = tonumber(coinBox.Text)
		if n then
			send("coinsSet", n)
		end
	end)
	for i, n in D.addCoins do
		local label = if n >= 1e9 then `+{n // 1e9}B` elseif n >= 1e6 then `+{n // 1e6}M` else `+{n // 1e3}K`
		button(r, Theme.coin, label, 0.49 + (i - 1) * 0.17, 0.155, function()
			send("coinsAdd", n)
		end)
	end

	heading("Teleport")
	local targets: { { id: string, label: string } } = testerReadout.targets or {}
	for i = 1, #targets, 4 do
		r = line()
		for j = 0, 3 do
			local t = targets[i + j]
			if t then
				button(r, Theme.info, t.label, 0.02 + j * 0.245, 0.23, function()
					send("teleport", t.id)
				end)
			end
		end
	end

	heading("Unlocks")
	r = line()
	-- every island gate (Round 4 phase 6): all open, the "Coming soon" ones too, or all shut again
	button(r, Theme.go, "Open all gates", 0.02, 0.47, function()
		send("openGates")
	end)
	button(r, Theme.no, "Close all gates", 0.51, 0.47, function()
		send("closeGates")
	end)
	r = line()
	button(r, Theme.go, "Max all upgrades", 0.02, 0.6, function()
		send("upgrade", "all")
	end)
	local rebirthText = text(r, "", 0.66, 0.16)
	button(r, Theme.no, "-", 0.83, 0.07, function()
		send("rebirths", ((State.view and State.view.rebirths) or 0) - 1)
	end)
	button(r, Theme.go, "+", 0.91, 0.07, function()
		send("rebirths", ((State.view and State.view.rebirths) or 0) + 1)
	end)
	table.insert(updates, function(view)
		rebirthText.Text = `Rebirth {view.rebirths}`
	end)
	-- give any gun (Round 4 prompt 1; final QA 2026-11-03: the server action existed but no button sent it)
	r = line()
	local function gunNow(): number
		return math.clamp((game:GetService("Players").LocalPlayer:GetAttribute("GunBest") or 1) :: number, 1, #Config.guns.list)
	end
	local gunText = text(r, "", 0.02, 0.78)
	button(r, Theme.no, "-", 0.83, 0.07, function()
		send("gun", gunNow() - 1)
	end)
	button(r, Theme.go, "+", 0.91, 0.07, function()
		send("gun", gunNow() + 1)
	end)
	table.insert(updates, function()
		gunText.Text = `Gun {gunNow()}: {Config.guns.list[gunNow()].name}`
	end)
	for i = 1, #Config.upgradeIds, 2 do
		r = line()
		for j = 0, 1 do
			local id = Config.upgradeIds[i + j]
			if id then
				local x = 0.02 + j * 0.49
				local lv = text(r, "", x, 0.27)
				button(r, Theme.no, "-", x + 0.28, 0.06, function()
					send("upgrade", id, ((State.view and State.view.upgrades[id]) or 1) - 1)
				end)
				button(r, Theme.go, "+", x + 0.35, 0.06, function()
					send("upgrade", id, ((State.view and State.view.upgrades[id]) or 1) + 1)
				end)
				table.insert(updates, function(view)
					lv.Text = `{Config.upgrades[id].name} {view.upgrades[id] or 1}`
				end)
			end
		end
	end
	-- the pan's Cold Level and Look (Round 4 phase 5); every pan pet into Storage for money tests
	r = line()
	for j, kind in { "cold", "look" } do
		local x = 0.02 + (j - 1) * 0.49
		local lv = text(r, "", x, 0.27)
		local function now(): number
			local pan = State.view and State.view.pan
			return if pan then (pan :: any)[kind] else 1
		end
		button(r, Theme.no, "-", x + 0.28, 0.06, function()
			send("pan", kind, now() - 1)
		end)
		button(r, Theme.go, "+", x + 0.35, 0.06, function()
			send("pan", kind, now() + 1)
		end)
		table.insert(updates, function()
			lv.Text = `{Config.pan.names[kind]} {now()}`
		end)
	end
	r = line()
	button(r, Theme.info, "Pan pets to Storage", 0.02, 0.47, function()
		send("storeAll")
	end)
	button(r, Theme.go, "Equip best", 0.51, 0.47, function()
		State.send("EquipBest")
	end)

	heading("Pets")
	local all: { PetDefs.PetDef } = {}
	for _, z in Config.world.zones do
		for _, def in PetDefs.inZone(z.id) do
			table.insert(all, def)
		end
	end
	local petIdx, mutIdx, tierIdx = 1, 0, #Config.tiers
	local muts: { string } = {}
	for name in Config.mutations do
		table.insert(muts, name)
	end
	r = line()
	local petName = text(r, "", 0.11, 0.38)
	local function showPet()
		local def = all[petIdx]
		petName.Text = if def then `{def.name} ({def.tier})` else "-"
		petName.TextColor3 = if def then tierColor(def.tier) else Theme.white
	end
	button(r, Theme.info, "<", 0.02, 0.08, function()
		petIdx = (petIdx - 2) % #all + 1
		showPet()
	end)
	button(r, Theme.info, ">", 0.5, 0.08, function()
		petIdx = petIdx % #all + 1
		showPet()
	end)
	local mutB: Ui.Block
	mutB = button(r, Theme.info, "No mutation", 0.6, 0.2, function()
		mutIdx = (mutIdx + 1) % (#muts + 1)
		mutB.text.Text = if mutIdx == 0 then "No mutation" else muts[mutIdx]
	end)
	button(r, Theme.go, "Give", 0.82, 0.16, function()
		local def = all[petIdx]
		if def then
			send("givePet", def.key, if mutIdx == 0 then nil else muts[mutIdx])
		end
	end)
	showPet()
	-- the pet above, wild, in any zone (0 = next to me), to test it without waiting for it to spawn
	r = line()
	local zoneIdx = 0
	local zones = Config.world.zones
	local zoneName = text(r, "", 0.11, 0.38)
	local function showZone()
		zoneName.Text = if zoneIdx == 0 then "Next to me" else `{zoneIdx}. {zones[zoneIdx].name}`
	end
	button(r, Theme.info, "<", 0.02, 0.08, function()
		zoneIdx = (zoneIdx - 1) % (#zones + 1)
		showZone()
	end)
	button(r, Theme.info, ">", 0.5, 0.08, function()
		zoneIdx = (zoneIdx + 1) % (#zones + 1)
		showZone()
	end)
	button(r, Theme.go, "Spawn wild", 0.6, 0.38, function()
		local def = all[petIdx]
		if def then
			send("spawnPet", def.key, if zoneIdx == 0 then 0 else zones[zoneIdx].id)
		end
	end)
	showZone()
	r = line()
	local tierB: Ui.Block
	tierB = button(r, tierColor(Config.tiers[tierIdx].name), Config.tiers[tierIdx].name, 0.02, 0.24, function()
		tierIdx = tierIdx % #Config.tiers + 1
		local name = Config.tiers[tierIdx].name
		tierB.text.Text = name
		tierB.face.BackgroundColor3 = tierColor(name)
		tierB.root.BackgroundColor3 = Ui.darker(tierB.face.BackgroundColor3)
	end)
	button(r, Theme.go, "Spawn here", 0.28, 0.24, function()
		send("spawnTier", Config.tiers[tierIdx].name)
	end)
	button(r, Theme.go, "Fill my pan", 0.6, 0.38, function()
		send("fillPan")
	end)

	heading("Speed")
	r = line()
	local walkText = text(r, "", 0.02, 0.2)
	button(r, Theme.no, "Normal", 0.23, 0.14, function()
		send("walk", 0)
	end)
	for i, s in D.walkPresets do
		button(r, Theme.info, tostring(s), 0.39 + (i - 1) * 0.15, 0.13, function()
			send("walk", s)
		end)
	end
	table.insert(updates, function(view)
		local w = if view.tester then view.tester.walk else 0
		walkText.Text = if w > 0 then `Walk {w}` else "Walk normal"
	end)
	r = line()
	toggle(r, "Instant freeze", 0.02, 0.47, function(view)
		return view.tester ~= nil and view.tester.instantFreeze
	end, "instantFreeze")
	toggle(r, "No melt", 0.51, 0.47, function(view)
		return view.tester ~= nil and view.tester.noMelt
	end, "noMelt")

	heading("Events")
	r = line()
	button(r, Theme.info, "Big Chill now", 0.02, 0.31, function()
		send("chill")
	end)
	button(r, Theme.info, "Night / day", 0.35, 0.31, function()
		send("night")
	end)
	r = line()
	button(r, Theme.info, "Away 1 h", 0.02, 0.31, function()
		send("away", 3600)
	end)
	button(r, Theme.info, "Away 8 h", 0.35, 0.31, function()
		send("away", 8 * 3600)
	end)

	heading("Round 5")
	r = line()
	button(r, Theme.info, "Critters here", 0.02, 0.31, function()
		send("critters") -- Heat Critters on the island you stand on (on / off)
	end)
	button(r, Theme.info, "Shield off", 0.35, 0.31, function()
		send("shieldOff") -- ray-tag: drop your new-player shield
	end)
	button(r, Theme.info, "Gel on / off", 0.68, 0.3, function()
		send("gel")
	end)
	r = line()
	button(r, Theme.info, "Caught 25", 0.02, 0.31, function()
		send("caught", Config.codes.needPets) -- unlock Codes
	end)
	button(r, Theme.info, "Thaw level max", 0.35, 0.31, function()
		send("upgrade", "pen", Config.upgrades.pen.maxLevel) -- second Thaw Machine
	end)

	heading("Save")
	r = line()
	local keyText = text(r, "", 0.02, 0.62)
	local armed = false
	local wipeB: Ui.Block
	wipeB = button(r, Theme.no, "Wipe my save", 0.66, 0.32, function()
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
	end)
	table.insert(updates, function()
		keyText.Text = `{testerReadout.saveKey or ""}{if testerReadout.qa then " (QA)" else ""}`
	end)

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
local function reward(o: Open, coins: number, sub: string, okText: string, onOk: () -> ())
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
	local b = button(row(l, 3, 0.34), Theme.go, okText, 0.28, 0.44, function()
		onOk()
		PopupController.close()
	end)
	o.first = b.face
end

-- the builders the Equipment Booth popup borrows (EquipmentPopup)
local helpers: EquipmentPopup.Helpers = {
	list = list, row = row, button = button, text = text, card = card, sized = sized, priceTag = priceTag,
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
		end)
	elseif o.name == "gift" then
		reward(o, o.data.coins, `Day {o.data.streak} in a row`, "Yay", function() end)
	elseif o.name == "pageDone" then
		local zone = Config.zone(o.data.zone)
		message(o, { `{if zone then zone.name else "Zone"} page full!`, `+{math.round(o.data.bonus * 100)}% coins forever` }, "Yay", function() end)
	elseif v then
		if o.name == "shop" then
			shop(o, v)
		elseif o.name == "pets" then
			pets(o, v)
		elseif o.name == "index" then
			index(o, v)
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
		end
	end
	InputController.select(o.first)
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
	InputController.select(nil)
	State.send("SetMenuOpen", false)
	local nextOne = table.remove(queue, 1)
	if nextOne then
		PopupController.open(nextOne.name, nextOne.data)
	end
end

function PopupController.open(name: string, data: any?)
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
	local frame = Screen.popupFrame()
	if SMALL[name] then
		frame.Size = UDim2.fromScale(frame.Size.X.Scale * 0.62, frame.Size.Y.Scale * 0.62)
	end
	local T = Config.ui.popupText
	local ph = frame.AbsoluteSize.Y / (if SMALL[name] then 0.62 else 1) -- text keeps the big panel's sizes
	px = { title = ph * T.title, body = ph * T.body, small = ph * T.small, button = ph * T.button }
	-- the body is a pale tint of the menu's colour and the title sits on a ribbon in the full colour,
	-- so the popup reads as one piece with its tile (a flat cream body looked like another game's UI)
	local menuColor = HEADER[name] or Theme.tiles[name] or Theme.info
	local panel = Ui.block(frame, "Panel", menuColor:Lerp(Theme.white, Config.ui.panelTint), "", nil, true)
	panel.root.Size = UDim2.fromScale(1, 1)
	panel.text.Visible = false
	local hh = Config.ui.headerHeight / (if SMALL[name] then 0.62 else 1)
	local header = Ui.block(panel.face, "Header", menuColor, TITLES[name] or "", nil)
	header.root.Position = UDim2.fromScale(0.02, 0.025)
	header.root.Size = UDim2.fromScale(0.96, hh)
	sized(header.text, "title")
	-- the menu's own icon beside its title, centred together by their visible width
	local iconId = HEADER_ICONS[name]
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
	local body = Instance.new("Frame")
	body.Name = "Body"
	body.BackgroundTransparency = 1
	body.Position = UDim2.fromScale(0.04, 0.05 + hh)
	body.Size = UDim2.fromScale(0.92, 0.92 - hh)
	body.Parent = panel.face
	local o: Open = { name = name, data = data, frame = frame, body = body, first = nil }
	current = o
	Screen.setMenuHidden(Config.ui.hideHudFor[name] == true)
	State.send("SetMenuOpen", true)
	if name == "shop" then
		State.send("ShopOpened")
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
end

function PopupController.Init() end

function PopupController.Start()
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
		fps = fps * 0.95 + (1 / math.max(dt, 1e-3)) * 0.05
	end)
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
		elseif kind == "welcomeBack" then
			PopupController.open("welcome", data)
		elseif kind == "giftClaimed" then
			PopupController.open("gift", data)
		elseif kind == "pageDone" then
			PopupController.open("pageDone", data)
		end
	end)
end

return PopupController

