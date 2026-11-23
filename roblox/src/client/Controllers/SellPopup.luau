--!strict
-- SellPopup (Round 4 phase 5): the contents of the Sell Booth popup. Left: your pets, identical ones
-- (same pet, pose and mutation) grouped into one row with how many you have and what one sells for.
-- Right: the picked group, what you get before you sell (Config.sellValue of the pet's own income),
-- "Sell 1" (Storage first, so your pan keeps earning) with "Sell all" (every copy of it) stacked under it.
-- Under the tiles, "Sell all Storage" sells every Storage pet. Epic and up, and Sell all Storage, ask "Sure?" first. Buttons send the pets' ids; SellService decides and pays.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Theme = require(ReplicatedStorage.Shared.Theme)
local PetDefs = require(ReplicatedStorage.Shared.PetDefs)
local Ui = require(script.Parent.Parent.Lib.Ui)
local State = require(script.Parent.State)
local EquipmentPopup = require(script.Parent.EquipmentPopup)
local SoundController = require(script.Parent.SoundController)
local Screen = require(script.Parent.Screen)

-- tiles to a row: fewer on a phone (device QA 2026-11-13: 4 made 7 px pet names); the row keeps each
-- tile's shape, so its width / height shrinks with the count
local function columns(): number
	return if Screen.deviceClass() == "phone" then Config.sell.phoneColumns else Config.sell.columns
end

local SellPopup = {}
local S = Config.sell
local lastSale: { coins: number, count: number, at: number }? = nil

type Group = { id: string, def: PetDefs.PetDef, pose: string, mut: string?, sz: string?, ids: { string }, inPan: number, value: number, rank: number }

-- identical pets in one group; within a group the Storage ones come first (sold first)
local function groups(v: State.View): { Group }
	local byId: { [string]: Group } = {}
	local out: { Group } = {}
	local mult = if v.tester then v.tester.mult else 1 -- a tester's money multiplier, as SellService pays it
	local sorted = table.clone(v.pets)
	table.sort(sorted, function(a, b)
		return (if a.eq then 1 else 0) < (if b.eq then 1 else 0)
	end)
	for _, p in sorted do
		local def = PetDefs.get(p.key)
		if def and not p.thawM then -- a pet in a Thaw Machine can't be sold until it's out
			local gid = `{p.key}|{p.pose}|{p.mut or ""}|{p.sz or ""}`
			local g = byId[gid]
			if not g then
				g = { id = gid, def = def, pose = p.pose, mut = p.mut, sz = p.sz, ids = {}, inPan = 0, value = Config.sellValue(p.income, mult), rank = Config.tier(def.tier).rank }
				byId[gid] = g
				table.insert(out, g)
			end
			table.insert(g.ids, p.id)
			if p.eq then
				g.inPan += 1
			end
		end
	end
	table.sort(out, function(a, b)
		if a.rank ~= b.rank then
			return a.rank > b.rank
		end
		return a.value > b.value
	end)
	return out
end

function SellPopup.shownKey(v: State.View): string
	local parts: { string } = {}
	for _, p in v.pets do
		table.insert(parts, `{p.id}{p.eq}{p.thawM or ""}`)
	end
	return table.concat(parts, ",") .. (if lastSale then tostring(lastSale.at) else "")
end

local function label(def: PetDefs.PetDef, pose: string, mut: string?, sz: string?): string
	local ps = Config.poses[pose]
	return (if sz then sz .. " " else "") .. def.name .. (if ps and pose ~= "idle" then " " .. ps.label else "") .. (if mut then " " .. mut else "")
end

local function role(h: EquipmentPopup.Helpers, t: TextLabel, r: string)
	if h.sized then
		h.sized(t, r)
	end
end

-- a white pill (count or price) on a tile; coin = the coin image in front of the words
local function pill(h: EquipmentPopup.Helpers, parent: Instance, s: string, coin: boolean, x: number, y: number, w: number, hgt: number): Frame
	local p = Instance.new("Frame")
	p.Name = if coin then "Price" else "Count"
	p.BackgroundColor3 = Theme.white
	p.BorderSizePixel = 0
	p.Position = UDim2.fromScale(x, y)
	p.Size = UDim2.fromScale(w, hgt)
	p.ZIndex = 3
	Ui.corner(p, 0.5)
	Ui.stroke(p)
	if coin then
		local c = Ui.image(p, Config.images.icons.coin, UDim2.fromScale(0.28, 0.86), UDim2.fromScale(0.03, 0.07))
		c.ZIndex = 4
	end
	local t = Ui.inkLabel(p, s, UDim2.fromScale(if coin then 0.64 else 0.86, 0.78), UDim2.fromScale(if coin then 0.32 else 0.07, 0.11))
	t.ZIndex = 4
	role(h, t, "small")
	p.Parent = parent
	return p
end

-- one group of identical pets as a tile in its tier colour (owner 2026-11-09: the list looked plain):
-- the pet, its name, how many you have and what one sells for. The tile picks the group for the card.
local function groupTile(h: EquipmentPopup.Helpers, parent: Instance, k: number, g: Group, o: any)
	local tile = Ui.block(parent, "Sell_" .. g.id:gsub("|", "_"), Theme.tiers[g.def.tier] or Theme.info, "", function()
		SoundController.play("click")
		o.data.pick = g.id
		o.data.ask = nil
		h.refresh()
	end)
	tile.text.Visible = false
	local w = (1 - S.tileGap * (columns() - 1)) / columns()
	tile.root.Position = UDim2.fromScale((k - 1) * (w + S.tileGap), 0.04)
	tile.root.Size = UDim2.fromScale(w, 0.92)
	if o.data.pick == g.id then
		local s = tile.root:FindFirstChildOfClass("UIStroke")
		if s then
			s.Color = Theme.white
			s.Thickness = Config.ui.stroke + 2
		end
	end
	Ui.petPicture(tile.face, g.def, UDim2.fromScale(0.8, 0.5), UDim2.fromScale(0.1, 0.06)) -- the painting, or its 3D model
	local name = Ui.label(tile.face, label(g.def, g.pose, g.mut, g.sz), UDim2.fromScale(0.92, 0.18), UDim2.fromScale(0.04, 0.56))
	role(h, name, "tiny") -- one size for every tile's name (short names grew huge on "small")
	pill(h, tile.face, `x{#g.ids}`, false, 0.62, 0.03, 0.34, 0.15)
	pill(h, tile.face, Ui.short(g.value), true, 0.1, 0.78, 0.8, 0.18)
end

local function line(h: EquipmentPopup.Helpers, l: GuiObject, order: number, s: string, color: Color3?, role: string?): TextLabel
	local t = h.text(h.row(l, order, 0.12), s, 0, 1, color)
	t.TextXAlignment = Enum.TextXAlignment.Center
	if h.sized then
		h.sized(t, role or "body")
	end
	return t
end

-- QA DR-01: would this sale leave no pets at all? (SellService asks for a yes then too)
local function lastPets(v: State.View, ids: { string }): boolean
	local selling: { [string]: boolean } = {}
	for _, id in ids do
		selling[id] = true
	end
	for _, p in v.pets do
		if not selling[p.id] and not p.thawM then
			return false
		end
	end
	return true
end

local function card(h: EquipmentPopup.Helpers, holder: Frame, g: Group, o: any, v: State.View)
	local l = h.list(holder, false)
	-- lined up with the left side (owner 2026-11-18: "make sure the buttons are positioned good"): the rows sit
	-- at the bottom so the last button is level with the Sell all Storage bar, and the window grows to fill the
	-- rest, so its top meets the tiles' top whatever the buttons below it
	local layout = l:FindFirstChildOfClass("UIListLayout")
	if layout then
		layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	end
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(S.cardTopPad, 0)
	pad.Parent = l
	-- the pet big in a window glowing in its tier colour, its tier on a chip, then its name
	local top = h.row(l, 0, S.windowHeight)
	local grow = Instance.new("UIFlexItem")
	grow.FlexMode = Enum.UIFlexMode.Fill
	grow.Parent = top
	local glow = Theme.tierGlow[g.def.tier] or Theme.ice
	local win = Instance.new("Frame")
	win.Name = "Window"
	win.BackgroundColor3 = Theme.white
	win.BorderSizePixel = 0
	win.Size = UDim2.fromScale(1, 1)
	Ui.corner(win)
	Ui.stroke(win, Config.ui.cardStroke)
	local grad = Instance.new("UIGradient")
	grad.Rotation = 90
	grad.Color = ColorSequence.new(Theme.white, glow)
	grad.Parent = win
	win.Parent = top
	Ui.petPicture(win, g.def, UDim2.fromScale(0.8, 0.86), UDim2.fromScale(0.1, 0.07))
	local tierRow = h.row(l, 1, 0.07)
	local tierChip = Instance.new("Frame")
	tierChip.Name = "Tier"
	tierChip.BackgroundColor3 = Theme.tiers[g.def.tier] or Theme.info
	tierChip.AnchorPoint = Vector2.new(0.5, 0)
	tierChip.Position = UDim2.fromScale(0.5, 0)
	tierChip.Size = UDim2.fromScale(0.36, 1)
	Ui.corner(tierChip, 0.5)
	Ui.stroke(tierChip)
	local tt = Ui.label(tierChip, string.upper(g.def.tier), UDim2.fromScale(0.9, 0.8), UDim2.fromScale(0.05, 0.1))
	role(h, tt, "small")
	tierChip.Parent = tierRow
	local nm = Ui.label(h.row(l, 2, 0.1), label(g.def, g.pose, g.mut, g.sz), UDim2.fromScale(1, 0.9), UDim2.fromScale(0, 0.05))
	role(h, nm, "title")
	-- a sale just now shows here for a moment, in place of the count (an extra row pushed the buttons off the card)
	local sale = lastSale
	if sale and os.clock() - sale.at < S.soldSeconds then
		line(h, l, 3, `Sold {sale.count}: +{Ui.commas(sale.coins)} coins`, Theme.go, "small")
	else
		line(h, l, 3, `You have {#g.ids}` .. (if g.inPan > 0 then `  ({g.inPan} in your pan)` else ""), nil, "small")
	end
	local ask = o.data.ask
	if ask then
		-- Epic and up: say yes first, seeing exactly what you get
		line(h, l, 4, if ask.last then (if ask.n > 1 then `Your last pets! Sell all {ask.n} for {Ui.commas(ask.n * g.value)} coins?` else `Your last pet! Sell it for {Ui.commas(g.value)} coins?`) elseif ask.all then `Sell all {ask.n} for {Ui.commas(ask.total)} coins?` else `Sell {ask.n} for {Ui.commas(ask.n * g.value)} coins?`, Theme.no, "body")
		-- the same height as the sell buttons, edge to edge like them, the last one level with the Storage bar
		local r = h.row(l, 5, S.buttonHeight)
		-- Keep is the green one: the safe answer (QA 2026-11-23 DR-07)
		local yes = h.button(r, Theme.coin, "Yes, sell", 0, 0.48, function()
			State.send("SellPets", ask.ids, true)
			o.data.ask = nil
			h.refresh()
		end)
		yes.root.Name = "Yes"
		local keep = h.button(r, Theme.go, "Keep", 0.52, 0.48, function()
			o.data.ask = nil
			h.refresh()
		end)
		keep.root.Name = "Keep"
		o.first = keep.face -- the safe answer is selected first on a gamepad
		return
	end
	local function sell(ids: { string })
		local last = lastPets(v, ids)
		if g.rank >= S.confirmFromRank or last then
			o.data.ask = { ids = ids, n = #ids, last = last }
			h.refresh()
		else
			State.send("SellPets", ids)
		end
	end
	-- owner 2026-11-18: the buttons stack, "Sell all" under "Sell 1" (not beside it), each the card's full width.
	-- "Sell all" (owner 2026-11-17) = every copy of this pet; only when there's more than one, or it's "Sell 1" again.
	local one = h.button(h.row(l, 4, S.buttonHeight), Theme.coin, `Sell 1  +{Ui.short(g.value)}`, 0, 1, function()
		sell({ g.ids[1] }) -- Storage ones first
	end)
	one.root.Name = "SellOne"
	o.first = one.face
	if #g.ids >= 2 then
		local ids = table.clone(g.ids)
		local all = h.button(h.row(l, 5, S.buttonHeight), Theme.coin, `Sell all {#ids}  +{Ui.short(#ids * g.value)}`, 0, 1, function()
			sell(ids)
		end)
		all.root.Name = "SellExtras"
	end
end

-- the bar under the pet tiles: Sell all Storage = every pet in Storage in one go (owner 2026-11-17, confirmed
-- 2026-11-18: the pan's pets keep earning, so they stay). It always asks "Sure?" with the total first, since it
-- can't be undone. With Storage empty it stays, greyed out, so the player knows it's there.
local function storageBar(h: EquipmentPopup.Helpers, holder: Frame, list: { Group }, o: any)
	local ids: { string } = {}
	local total = 0
	for _, g in list do
		for n = 1, math.min(#g.ids - g.inPan, S.maxPerSale - #ids) do -- Storage ones come first in each group
			table.insert(ids, g.ids[n])
			total += g.value
		end
	end
	local empty = #ids == 0
	local b = h.button(holder, if empty then Theme.tutorial.skip else Theme.go, if empty then "Sell all Storage  (Storage is empty)" else `Sell all Storage ({#ids})  +{Ui.short(total)}`, 0, 1, function()
		if empty then
			return
		end
		o.data.ask = { ids = ids, n = #ids, total = total, all = true }
		h.refresh()
	end)
	b.root.Name = "SellAll" -- h.button's own spot in the row: the same height as the card's buttons
end

function SellPopup.fill(o: any, v: State.View, h: EquipmentPopup.Helpers)
	o.data = if typeof(o.data) == "table" then o.data else {}
	local list = groups(v)
	if #list == 0 then
		line(h, h.list(o.body, false), 1, "No pets to sell yet. Freeze some and bring them to your pan!")
		return
	end
	local picked: Group? = nil
	for _, g in list do
		if g.id == o.data.pick then
			picked = g
		end
	end
	if not picked then
		-- the safe first pick (QA IR-12): the least valuable pets, ones in Storage before ones in the pan
		-- (the list is rarest first, so walk it from the end)
		local first = list[#list]
		for n = #list, 1, -1 do
			if #list[n].ids > list[n].inPan then
				first = list[n]
				break
			end
		end
		picked = first
		o.data.pick = first.id
		o.data.ask = nil
	end
	local left = Instance.new("Frame")
	left.Name = "Pets"
	left.BackgroundTransparency = 1
	left.Size = UDim2.fromScale(0.56, 1 - S.storageBarHeight - S.storageBarGap)
	left.Parent = o.body
	local l = h.list(left, true)
	-- the bar spans exactly the tile grid: the list's inset on each side, less its scroll bar's strip on the right
	local inset = 0.56 * Config.ui.listInset
	local strip = if l:IsA("ScrollingFrame") then l.ScrollBarThickness else 0
	local bar = Instance.new("Frame")
	bar.Name = "StorageBar"
	bar.BackgroundTransparency = 1
	bar.Position = UDim2.new(inset, 0, 1 - S.storageBarHeight, 0)
	bar.Size = UDim2.new(0.56 - 2 * inset, -strip, S.storageBarHeight, 0)
	bar.Parent = o.body
	storageBar(h, bar, list, o)
	-- tiles, S.columns to a row (each row sized from its width, so the scrolling list measures it)
	local r: Frame? = nil
	for n, g in list do
		local k = (n - 1) % columns() + 1
		if k == 1 then
			r = h.row(l, n, 0, S.rowAspect * columns() / S.columns)
		end
		groupTile(h, r :: Frame, k, g, o)
	end
	local right = Instance.new("Frame")
	right.Name = "Card"
	right.BackgroundTransparency = 1
	right.Position = UDim2.fromScale(0.59, 0)
	right.Size = UDim2.fromScale(0.41, 1)
	right.Parent = o.body
	card(h, right, picked :: Group, o, v)
end

function SellPopup.Init() end

function SellPopup.Start()
	State.Notify:Connect(function(kind: string, data: any)
		if kind == "sold" and typeof(data) == "table" then
			lastSale = { coins = tonumber(data.coins) or 0, count = tonumber(data.count) or 0, at = os.clock() }
			SoundController.play("sell")
			SoundController.play("coin")
		end
	end)
end

return SellPopup
