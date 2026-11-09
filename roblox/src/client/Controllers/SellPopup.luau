--!strict
-- SellPopup (Round 4 phase 5): the contents of the Sell Booth popup. Left: your pets, identical ones
-- (same pet, pose and mutation) grouped into one row with how many you have and what one sells for.
-- Right: the picked group, what you get before you sell (Config.sellValue of the pet's own income),
-- "Sell 1" (Storage first, so your pan keeps earning) and "Sell extras" (all but one, in one go).
-- Epic and up ask "Sure?" first. Buttons send the pets' ids; SellService decides and pays.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Theme = require(ReplicatedStorage.Shared.Theme)
local PetDefs = require(ReplicatedStorage.Shared.PetDefs)
local Ui = require(script.Parent.Parent.Lib.Ui)
local State = require(script.Parent.State)
local EquipmentPopup = require(script.Parent.EquipmentPopup)
local SoundController = require(script.Parent.SoundController)

local SellPopup = {}
local S = Config.sell
local lastSale: { coins: number, count: number, at: number }? = nil

type Group = { id: string, def: PetDefs.PetDef, pose: string, mut: string?, ids: { string }, inPan: number, value: number, rank: number }

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
			local gid = `{p.key}|{p.pose}|{p.mut or ""}`
			local g = byId[gid]
			if not g then
				g = { id = gid, def = def, pose = p.pose, mut = p.mut, ids = {}, inPan = 0, value = Config.sellValue(p.income, mult), rank = Config.tier(def.tier).rank }
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

local function label(def: PetDefs.PetDef, pose: string, mut: string?): string
	local ps = Config.poses[pose]
	return def.name .. (if ps and pose ~= "idle" then " " .. ps.label else "") .. (if mut then " " .. mut else "")
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
	local w = (1 - S.tileGap * (S.columns - 1)) / S.columns
	tile.root.Position = UDim2.fromScale((k - 1) * (w + S.tileGap), 0.04)
	tile.root.Size = UDim2.fromScale(w, 0.92)
	if o.data.pick == g.id then
		local s = tile.root:FindFirstChildOfClass("UIStroke")
		if s then
			s.Color = Theme.white
			s.Thickness = Config.ui.stroke + 2
		end
	end
	if g.def.icon ~= "" then
		Ui.image(tile.face, g.def.icon, UDim2.fromScale(0.8, 0.5), UDim2.fromScale(0.1, 0.06))
	end
	local name = Ui.label(tile.face, label(g.def, g.pose, g.mut), UDim2.fromScale(0.92, 0.18), UDim2.fromScale(0.04, 0.56))
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

local function card(h: EquipmentPopup.Helpers, holder: Frame, g: Group, o: any)
	local l = h.list(holder, false)
	-- the pet big in a window glowing in its tier colour, its tier on a chip, then its name
	local top = h.row(l, 0, S.windowHeight)
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
	if g.def.icon ~= "" then
		Ui.image(win, g.def.icon, UDim2.fromScale(0.8, 0.86), UDim2.fromScale(0.1, 0.07))
	end
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
	local nm = Ui.label(h.row(l, 2, 0.1), label(g.def, g.pose, g.mut), UDim2.fromScale(1, 0.9), UDim2.fromScale(0, 0.05))
	role(h, nm, "title")
	line(h, l, 3, `You have {#g.ids}` .. (if g.inPan > 0 then `  ({g.inPan} in your pan)` else ""), nil, "small")
	local ask = o.data.ask
	if ask then
		-- Epic and up: say yes first, seeing exactly what you get
		line(h, l, 4, `Sell {ask.n} for {Ui.commas(ask.n * g.value)} coins?`, Theme.no, "body")
		local r = h.row(l, 5, 0.2)
		local yes = h.button(r, Theme.go, "Yes, sell", 0.04, 0.44, function()
			State.send("SellPets", ask.ids, true)
			o.data.ask = nil
			h.refresh()
		end)
		yes.root.Name = "Yes"
		local keep = h.button(r, Theme.no, "Keep", 0.52, 0.44, function()
			o.data.ask = nil
			h.refresh()
		end)
		keep.root.Name = "Keep"
		o.first = keep.face -- the safe answer is selected first on a gamepad
		return
	end
	local function sell(ids: { string })
		if g.rank >= S.confirmFromRank then
			o.data.ask = { ids = ids, n = #ids }
			h.refresh()
		else
			State.send("SellPets", ids)
		end
	end
	local r = h.row(l, 5, 0.16)
	-- "Sell all but one" only when it sells more than one: with 2 pets it was the same as "Sell 1", so the
	-- card showed two "Sell 1" buttons (owner 2026-11-09)
	local extras = table.clone(g.ids)
	table.remove(extras) -- keep one (a pan one if any, since those sort last)
	local two = #extras >= 2
	local one = h.button(r, Theme.coin, `Sell 1  +{Ui.short(g.value)}`, 0, if two then 0.48 else 1, function()
		sell({ g.ids[1] }) -- Storage ones first
	end)
	one.root.Name = "SellOne"
	o.first = one.face
	if two then
		local all = h.button(r, Theme.coin, `Sell {#extras}  +{Ui.short(#extras * g.value)}`, 0.52, 0.48, function()
			sell(extras)
		end)
		all.root.Name = "SellExtras"
	end
	local sale = lastSale
	if sale and os.clock() - sale.at < 4 then
		line(h, l, 6, `Sold {sale.count}: +{Ui.commas(sale.coins)} coins`, Theme.go, "body")
	end
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
		picked = list[1]
		o.data.pick = list[1].id
		o.data.ask = nil
	end
	local left = Instance.new("Frame")
	left.Name = "Pets"
	left.BackgroundTransparency = 1
	left.Size = UDim2.fromScale(0.56, 1)
	left.Parent = o.body
	local l = h.list(left, true)
	-- tiles, S.columns to a row (each row sized from its width, so the scrolling list measures it)
	local r: Frame? = nil
	for n, g in list do
		local k = (n - 1) % S.columns + 1
		if k == 1 then
			r = h.row(l, n, 0, S.rowAspect)
		end
		groupTile(h, r :: Frame, k, g, o)
	end
	local right = Instance.new("Frame")
	right.Name = "Card"
	right.BackgroundTransparency = 1
	right.Position = UDim2.fromScale(0.59, 0)
	right.Size = UDim2.fromScale(0.41, 1)
	right.Parent = o.body
	card(h, right, picked :: Group, o)
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
