--!strict
-- RebirthPopup (Round 4 phase 7): the contents of the Rebirth Booth popup. Three columns of icons with
-- a word or two each, not paragraphs: what you KEEP, what RESETS, what you GET (income, a pan slot,
-- the free gun when it's next in line, the islands it opens). Then the price and one Rebirth button
-- that asks "Sure?" first (it resets your coins). Buttons send intent only; RebirthService decides.
-- PopupController owns the popup and lends its builders; the show plays from Show.rebirth.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Theme = require(ReplicatedStorage.Shared.Theme)
local Ui = require(script.Parent.Parent.Lib.Ui)
local State = require(script.Parent.State)
local EquipmentPopup = require(script.Parent.EquipmentPopup)

local RebirthPopup = {}
local me = Players.LocalPlayer
local I = Config.images.icons

function RebirthPopup.shownKey(v: State.View): string
	local cost = Config.rebirthCost(v.rebirths + 1)
	return `{v.rebirths},{v.coins >= cost},{me:GetAttribute("GunBest")}`
end

-- the free gun this rebirth hands over, if it's next in line (as RebirthService works it out)
local function giftGun(rebirths: number): Config.Gun?
	local best = me:GetAttribute("GunBest")
	local index = (if typeof(best) == "number" then best else 1) + 1
	local g = Config.guns.list[index]
	if g and g.price == 0 and g.rebirths > 0 and g.rebirths <= rebirths then
		return g
	end
	return nil
end

-- the islands whose rebirth gate this rebirth meets
local function opens(rebirths: number): string?
	for id, need in Config.world.rebirthGates do
		if need == rebirths then
			local isl = Config.world.islands[id]
			-- a "Coming soon" island isn't promised (final QA 2026-11-03: Rebirth 1 offered Mushroom Grove,
			-- whose gate still says Coming soon)
			return if isl and isl.ready then isl.name else nil
		end
	end
	return nil
end

-- a little castle gate from UI shapes (there is no painted gate icon; no emojis in UI)
local function gateShape(parent: Instance, color: Color3)
	local box = Instance.new("Frame")
	box.Name = "GateIcon"
	box.BackgroundTransparency = 1
	box.Size = UDim2.fromScale(0.22, 0.9)
	box.Position = UDim2.fromScale(0.03, 0.05)
	box.Parent = parent
	local a = Instance.new("UIAspectRatioConstraint")
	a.Parent = box
	local function part(x: number, y: number, w: number, h: number): Frame
		local f = Instance.new("Frame")
		f.BackgroundColor3 = color
		f.BorderSizePixel = 0
		f.Position = UDim2.fromScale(x, y)
		f.Size = UDim2.fromScale(w, h)
		f.Parent = box
		Ui.corner(f, 0.2)
		return f
	end
	part(0.08, 0.2, 0.22, 0.75) -- left tower
	part(0.7, 0.2, 0.22, 0.75) -- right tower
	part(0.08, 0.12, 0.84, 0.2) -- the arch
	for i = 0, 2 do
		local bar = part(0.36 + i * 0.1, 0.32, 0.06, 0.6) -- bars, lighter so the gate reads as a gate
		bar.BackgroundColor3 = Theme.info
	end
end

-- one icon row: a painted icon (or the gate shape) and a short word
local function item(h: EquipmentPopup.Helpers, l: GuiObject, order: number, icon: string?, word: string, color: Color3?)
	local r = h.row(l, order, 0.15)
	r.Name = "Item" .. order
	if icon then
		local img = Ui.image(r, icon, UDim2.fromScale(0.22, 0.9), UDim2.fromScale(0.03, 0.05))
		local a = Instance.new("UIAspectRatioConstraint")
		a.Parent = img
	else
		gateShape(r, color or Theme.ink)
	end
	local t = h.text(r, word, 0.3, 0.68, color)
	if h.sized then
		h.sized(t, "small")
	end
end

local function column(h: EquipmentPopup.Helpers, body: Frame, x: number, title: string, color: Color3): GuiObject
	local holder = Instance.new("Frame")
	holder.Name = title
	holder.BackgroundTransparency = 1
	holder.Position = UDim2.fromScale(x, 0)
	holder.Size = UDim2.fromScale(0.32, 0.7)
	holder.Parent = body
	local l = h.list(holder, false)
	local lay = l:FindFirstChildOfClass("UIListLayout")
	if lay then
		lay.VerticalAlignment = Enum.VerticalAlignment.Top -- the three headings line up
	end
	local head = h.text(h.row(l, 0, 0.14), title, 0, 1, color)
	head.TextXAlignment = Enum.TextXAlignment.Center
	if h.sized then
		h.sized(head, "body")
	end
	return l
end

function RebirthPopup.fill(o: any, v: State.View, h: EquipmentPopup.Helpers)
	o.data = if typeof(o.data) == "table" then o.data else {}
	local n = v.rebirths + 1
	local cost = Config.rebirthCost(n)
	local keep = column(h, o.body, 0, "KEEP", Theme.go)
	item(h, keep, 1, Config.ui.tileIcons.pets, "Pets")
	item(h, keep, 2, I.book, "Index")
	item(h, keep, 3, I.ray, "Guns")
	item(h, keep, 4, nil, "Gates", Theme.ink)
	item(h, keep, 5, I.pen, "Cold + Look")
	local resets = column(h, o.body, 0.34, "RESETS", Theme.no)
	item(h, resets, 1, I.coin, "Coins")
	item(h, resets, 2, I.pen, "Slots")
	local get = column(h, o.body, 0.68, "YOU GET", Theme.booths.rebirth)
	item(h, get, 1, I.coin, `x{Config.rebirthIncome(n)} coins`)
	local order = 2
	if Config.rebirth.slotsPer > 0 then
		item(h, get, order, I.pen, `+{Config.rebirth.slotsPer} slot`)
		order += 1
	end
	local gun = giftGun(n)
	if gun then
		item(h, get, order, I.ray, gun.name)
		order += 1
	end
	local island = opens(n)
	if island then
		item(h, get, order, nil, island, Theme.booths.rebirth)
	end
	-- the price and the button along the bottom
	local foot = Instance.new("Frame")
	foot.Name = "Foot"
	foot.BackgroundTransparency = 1
	foot.Position = UDim2.fromScale(0, 0.72)
	foot.Size = UDim2.fromScale(1, 0.28)
	foot.Parent = o.body
	local fl = h.list(foot, false)
	if o.data.ask then
		local q = h.text(h.row(fl, 1, 0.4), `Rebirth {n}? Your coins and Slots reset.`, 0, 1, Theme.no)
		q.TextXAlignment = Enum.TextXAlignment.Center
		if h.sized then
			h.sized(q, "body")
		end
		local r = h.row(fl, 2, 0.5)
		local yes = h.button(r, Theme.go, "Yes, rebirth", 0.04, 0.44, function()
			o.data.ask = nil
			State.send("Rebirth", true)
			h.refresh()
		end)
		yes.root.Name = "Yes"
		local no = h.button(r, Theme.no, "Not yet", 0.52, 0.44, function()
			o.data.ask = nil
			h.refresh()
		end)
		no.root.Name = "No"
		o.first = no.face -- the safe answer is selected first on a gamepad
		return
	end
	local have = v.coins >= cost
	local price = h.text(h.row(fl, 1, 0.4), if have then `Rebirth {n}: {Ui.price(cost)} coins`
		else `Rebirth {n}: {Ui.price(cost)} coins (need {Ui.price(cost - v.coins)} more)`, 0, 1)
	price.TextXAlignment = Enum.TextXAlignment.Center
	if h.sized then
		h.sized(price, "body")
	end
	local r = h.row(fl, 2, 0.5)
	local go = h.button(r, if have then Theme.booths.rebirth else Theme.no, "Rebirth", 0.28, 0.44, function()
		if have then
			o.data.ask = true
			h.refresh()
		else
			State.send("Rebirth", false) -- not enough: the server answers "Need N more"
		end
	end)
	go.root.Name = "RebirthButton"
	o.first = go.face
end

function RebirthPopup.Init() end
function RebirthPopup.Start() end

return RebirthPopup
