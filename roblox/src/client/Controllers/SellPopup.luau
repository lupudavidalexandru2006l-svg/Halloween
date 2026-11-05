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
		if def then
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
		table.insert(parts, `{p.id}{p.eq}`)
	end
	return table.concat(parts, ",") .. (if lastSale then tostring(lastSale.at) else "")
end

local function label(def: PetDefs.PetDef, pose: string, mut: string?): string
	local ps = Config.poses[pose]
	return def.name .. (if ps and pose ~= "idle" then " " .. ps.label else "") .. (if mut then " " .. mut else "")
end

local function groupRow(h: EquipmentPopup.Helpers, l: GuiObject, n: number, g: Group, o: any)
	local r = h.row(l, n, 0, 5)
	r.Name = "Sell" .. n
	local face: Instance = if h.card then h.card(r) else r
	if o.data.pick == g.id then
		local s = face:FindFirstChildOfClass("UIStroke")
		if not s then
			Ui.stroke(face)
			s = face:FindFirstChildOfClass("UIStroke")
		end
		if s then
			s.Color = Theme.info
			s.Thickness = Config.ui.stroke + 1
		end
	end
	if g.def.icon ~= "" then
		local img = Ui.image(face, g.def.icon, UDim2.fromScale(0.16, 0.9), UDim2.fromScale(0.02, 0.05))
		local a = Instance.new("UIAspectRatioConstraint")
		a.Parent = img
	end
	local name = h.text(face, label(g.def, g.pose, g.mut), 0.2, 0.5, Theme.tiers[g.def.tier])
	if h.sized then
		h.sized(name, "small")
	end
	local count = h.text(face, `x{#g.ids}`, 0.71, 0.12)
	if h.sized then
		h.sized(count, "small")
	end
	local price = h.text(face, Ui.short(g.value), 0.83, 0.16, Theme.coin)
	if h.sized then
		h.sized(price, "small")
	end
	-- the whole row picks this group for the card (click, tap or gamepad A)
	local pick = Instance.new("TextButton")
	pick.Name = "Pick"
	pick.Text = ""
	pick.BackgroundTransparency = 1
	pick.Size = UDim2.fromScale(1, 1)
	pick.ZIndex = 5
	pick.Parent = r
	pick.Activated:Connect(function()
		SoundController.play("click")
		o.data.pick = g.id
		o.data.ask = nil
		h.refresh()
	end)
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
	line(h, l, 1, label(g.def, g.pose, g.mut), Theme.tiers[g.def.tier], "title")
	line(h, l, 2, `{g.def.tier}. You have {#g.ids}` .. (if g.inPan > 0 then ` ({g.inPan} in your pan)` else ""), nil, "small")
	line(h, l, 3, `Sells for {Ui.commas(g.value)} coins each`, nil, "small")
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
	local r = h.row(l, 5, 0.2)
	local one = h.button(r, Theme.coin, `Sell 1  +{Ui.short(g.value)}`, 0.04, 0.44, function()
		sell({ g.ids[1] }) -- Storage ones first
	end)
	one.root.Name = "SellOne"
	o.first = one.face
	if #g.ids >= 2 then
		local extras = table.clone(g.ids)
		table.remove(extras) -- keep one (a pan one if any, since those sort last)
		-- short, so the total still fits on the button ("extras" pushed the price off it); one is kept
		local all = h.button(r, Theme.coin, `Sell {#extras}  +{Ui.short(#extras * g.value)}`, 0.52, 0.44, function()
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
	left.Size = UDim2.fromScale(0.5, 1)
	left.Parent = o.body
	local l = h.list(left, true)
	for n, g in list do
		groupRow(h, l, n, g, o)
	end
	local right = Instance.new("Frame")
	right.Name = "Card"
	right.BackgroundTransparency = 1
	right.Position = UDim2.fromScale(0.53, 0)
	right.Size = UDim2.fromScale(0.47, 1)
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
