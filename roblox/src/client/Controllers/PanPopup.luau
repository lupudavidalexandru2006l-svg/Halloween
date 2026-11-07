--!strict
-- PanPopup (Round 4 phase 5): the contents of the Pan Upgrades popup (your own pan's stand). One card
-- per upgrade in Config.pan.order: Slots, Cold Level, Look. Redesign 2026-11-03 (owner approved the
-- Figma mock, file "Ice Ray for Pets UI"): a Chunky Pop card on a lip, a painted icon on a coloured
-- tile, the name with a level badge, one big "now > next" line, and the full price. The button you
-- can afford is the focal point (it pulses); short of coins it's grey with a bar of how close you are;
-- Soon / Max is a flat box, not a button. Buy only sends intent; PanService decides, and the upgrade
-- show (Show.panUpgrade) plays the result. PopupController owns the popup and lends its builders.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Config = require(ReplicatedStorage.Shared.Config)
local Theme = require(ReplicatedStorage.Shared.Theme)
local Ui = require(script.Parent.Parent.Lib.Ui)
local State = require(script.Parent.State)
local EquipmentPopup = require(script.Parent.EquipmentPopup)
local SettingsController = require(script.Parent.SettingsController)
local UpgradeMotion = require(script.Parent.UpgradeMotion)

local PanPopup = {}
local P = Config.pan
local I = Config.images.icons
local ICONS: { [string]: string } = { slots = I.pen, cold = I.temp, look = I.paint }
local TILES: { [string]: Color3 } = { slots = Theme.pen, cold = Theme.ice, look = Theme.grassFar }
local NAMES: { [string]: string } = { slots = "Slots", cold = "Cold", look = "Look" }
local PROGRESS_STEPS = 20 -- the "how close" bar redraws in 5% steps (the popup only rebuilds on a key change)

function PanPopup.level(v: State.View, kind: string): number
	if kind == "slots" then
		return v.upgrades.pen or 1
	elseif kind == "cold" then
		return if v.pan then v.pan.cold else P.cold.start
	end
	return if v.pan then v.pan.look else 1
end

-- the popup is only rebuilt when this changes (not on every coin tick)
function PanPopup.shownKey(v: State.View): string
	local parts: { string } = {}
	for _, kind in P.order do
		local level = PanPopup.level(v, kind)
		local price = Config.panPrice(kind, level, v.rebirths)
		local near = if price then math.floor(math.min(1, v.coins / math.max(1, price)) * PROGRESS_STEPS) else 0
		table.insert(parts, `{kind}{level}{price ~= nil and v.coins >= price}{near}`)
	end
	return table.concat(parts, ",")
end

local function slotsAt(level: number, rebirths: number): number
	return Config.panSlots(level, rebirths)
end

-- what a card shows: the value now, the value after buying (nil when there's no next level), a unit
local function values(kind: string, level: number, rebirths: number, canBuy: boolean): (string, string?, string?)
	if kind == "slots" then
		return tostring(slotsAt(level, rebirths)), if canBuy then tostring(slotsAt(level + 1, rebirths)) else nil, "pets"
	elseif kind == "cold" then
		return `Islands 1-{level}`, if canBuy then `1-{level + 1}` else nil, nil
	end
	local cur, nxt = P.looks[level], P.looks[level + 1]
	return if cur then cur.name else "", if canBuy and nxt then nxt.name else nil, nil
end

-- a label that is exactly as wide as its words, for the left-to-right rows of the card
local function word(parent: Instance, s: string, color: Color3, role: string, h: EquipmentPopup.Helpers, order: number): TextLabel
	local t = Ui.inkLabel(parent, s, UDim2.fromScale(0, 1), UDim2.fromScale(0, 0))
	t.TextColor3 = color
	if h.sized then
		h.sized(t, role)
	end
	t.TextWrapped = false
	t.AutomaticSize = Enum.AutomaticSize.X
	t.LayoutOrder = order
	return t
end

local function line(parent: Instance, name: string, y: number, height: number): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundTransparency = 1
	f.Position = UDim2.fromScale(0.17, y)
	f.Size = UDim2.fromScale(0.52, height)
	local l = Instance.new("UIListLayout")
	l.FillDirection = Enum.FillDirection.Horizontal
	l.VerticalAlignment = Enum.VerticalAlignment.Center
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.Padding = UDim.new(0.02, 0)
	l.Parent = f
	f.Parent = parent
	return f
end

-- a small block with a word on it, as tall as its row (the level badge, the "next" arrow)
local function chip(parent: Instance, s: string, color: Color3, role: string, h: EquipmentPopup.Helpers, order: number, height: number): Frame
	local f = Instance.new("Frame")
	f.BackgroundColor3 = color
	f.Size = UDim2.fromScale(0, height)
	f.AutomaticSize = Enum.AutomaticSize.X
	f.LayoutOrder = order
	Ui.corner(f, 0.5)
	Ui.stroke(f, Config.ui.cardStroke)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 8)
	pad.Parent = f
	local t = Ui.label(f, s, UDim2.fromScale(0, 1), UDim2.fromScale(0, 0))
	if h.sized then
		h.sized(t, role)
	end
	t.TextWrapped = false
	t.AutomaticSize = Enum.AutomaticSize.X
	f.Parent = parent
	return f
end

-- the painted icon on a tile in the upgrade's own colour
local function icon(parent: Instance, kind: string)
	local tile = Instance.new("Frame")
	tile.Name = "Icon"
	tile.BackgroundColor3 = TILES[kind] or Theme.snowFar
	tile.AnchorPoint = Vector2.new(0, 0.5)
	tile.Position = UDim2.fromScale(0.015, 0.5)
	tile.Size = UDim2.fromScale(0.82, 0.82)
	local a = Instance.new("UIAspectRatioConstraint")
	a.AspectRatio = 1
	a.DominantAxis = Enum.DominantAxis.Height
	a.Parent = tile
	Ui.corner(tile)
	Ui.stroke(tile)
	tile.Parent = parent
	Ui.image(tile, ICONS[kind] or I.coin, UDim2.fromScale(0.84, 0.84), UDim2.fromScale(0.08, 0.08))
end

-- the focal point: a slow pulse on the button you can afford (none with reduced motion)
local function pulse(b: Ui.Block)
	if SettingsController.get("reducedMotion") == true then
		return
	end
	local s = Instance.new("UIScale")
	s.Parent = b.root
	local tw = TweenService:Create(s, TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Scale = 1.06 })
	tw:Play()
	b.root.Destroying:Once(function()
		tw:Cancel()
	end)
end

-- under the price on a grey button: how close your coins are to it
local function progress(b: Ui.Block, share: number)
	b.text.Size = UDim2.fromScale(0.62, 0.52)
	b.text.Position = UDim2.fromScale(0.34, 0.08)
	local bar = Instance.new("Frame")
	bar.Name = "Progress"
	bar.BackgroundColor3 = Theme.white
	bar.Position = UDim2.fromScale(0.36, 0.64)
	bar.Size = UDim2.fromScale(0.56, 0.2)
	Ui.corner(bar, 0.5)
	Ui.stroke(bar, Config.ui.cardStroke)
	local fill = Instance.new("Frame")
	fill.BackgroundColor3 = Theme.coin
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(math.clamp(share, 0.04, 1), 1)
	Ui.corner(fill, 0.5)
	fill.Parent = bar
	bar.Parent = b.face
end

-- Soon / Max: a flat box in the right-hand spot, clearly not something to press
local function flatBox(parent: Instance, s: string, h: EquipmentPopup.Helpers)
	local f = Instance.new("Frame")
	f.Name = "State"
	f.BackgroundColor3 = Theme.snowFar
	f.Position = UDim2.fromScale(0.7, 0.14)
	f.Size = UDim2.fromScale(0.28, 0.72)
	Ui.corner(f)
	local st = Instance.new("UIStroke")
	st.Color = Theme.tiers.Common
	st.Thickness = Config.ui.cardStroke
	st.Parent = f
	local t = Ui.inkLabel(f, s, UDim2.fromScale(0.9, 0.6), UDim2.fromScale(0.05, 0.2))
	t.TextColor3 = Theme.tiers.Common
	if h.sized then
		h.sized(t, "button")
	end
	f.Parent = parent
end

function PanPopup.fill(o: any, v: State.View, h: EquipmentPopup.Helpers)
	local l = h.list(o.body, false)
	local pulsing = false
	for i, kind in P.order do
		local level = PanPopup.level(v, kind)
		local r = h.row(l, i, 0.3)
		r.Name = "Pan_" .. kind
		-- the card: white on a lip, a little inset so the lip and outline aren't clipped
		local card = Ui.block(r, "Card", Theme.white, "", nil, true)
		card.root.Position = UDim2.fromScale(0.005, 0.04)
		card.root.Size = UDim2.fromScale(0.99, 0.92)
		card.text.Visible = false
		local face = card.face
		icon(face, kind)
		local price = Config.panPrice(kind, level, v.rebirths)
		local now, nxt, unit = values(kind, level, v.rebirths or 0, price ~= nil)
		-- the name and its level badge
		local top = line(face, "Title", 0.1, 0.38)
		word(top, NAMES[kind] or kind, Theme.ink, "title", h, 1)
		local lv = chip(top, `LV {level}`, Theme.info, "small", h, 2, 0.72)
		-- the fast upgrade motion follows this card (and the next one, after the rebuild)
		local tile = face:FindFirstChild("Icon") :: GuiObject?
		if tile then
			UpgradeMotion.bind(kind, { card = card.root, tile = tile, chip = lv })
		end
		-- now > next, the next value in green
		local stat = line(face, "Stat", 0.52, 0.36)
		word(stat, now, if nxt then Theme.tiers.Common:Lerp(Theme.ink, 0.35) else Theme.ink, "body", h, 1)
		if nxt then
			chip(stat, ">", Theme.go, "small", h, 2, 0.8)
			word(stat, nxt, Ui.darker(Theme.go), "body", h, 3)
		end
		if unit then
			word(stat, unit, Theme.tiers.Common:Lerp(Theme.ink, 0.35), "small", h, 4)
		end
		if not price then
			flatBox(face, if kind == "cold" and level < P.cold.max then "Soon" else "Max", h)
			continue
		end
		local afford = v.coins >= price
		local b = h.button(face, if afford then Theme.coin else Theme.tiers.Common, Ui.price(price), 0.7, 0.28, function()
			local send = function()
				State.send("BuyPanUpgrade", kind) -- the server checks the stand, the price and the level
			end
			if Config.motion.upgrade.fastPan then
				UpgradeMotion.press(kind, level, afford, send) -- the build-up starts now; a press mid-motion waits its turn
			else
				send()
			end
		end)
		b.root.Name = "Buy_" .. kind
		if h.priceTag then
			h.priceTag(b)
		end
		if afford and not pulsing then
			pulsing = true
			pulse(b)
		elseif not afford then
			progress(b, v.coins / price)
		end
		if not o.first then
			o.first = b.face
		end
	end
end

return PanPopup

