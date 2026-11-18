--!strict
-- RebirthPopup (Round 4 phase 7): the contents of the Rebirth Booth popup. Three columns of icons with
-- a word or two each, not paragraphs: what you KEEP, what RESETS, what you GET (income, a pan slot,
-- the free gun when it's next in line, the islands it opens). Then the price and one Rebirth button
-- that asks "Sure?" first (it resets your coins). Buttons send intent only; RebirthService decides.
-- PopupController owns the popup and lends its builders; the show plays from Show.rebirth.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Theme = require(ReplicatedStorage.Shared.Theme)
local Ui = require(script.Parent.Parent.Lib.Ui)
local State = require(script.Parent.State)
local SettingsController = require(script.Parent.SettingsController)
local EquipmentPopup = require(script.Parent.EquipmentPopup)
local Screen = require(script.Parent.Screen)

-- the layout shares; on a phone the foot (coin bar + Rebirth button) is taller (device QA 2026-11-13:
-- the button was 28 px) and the columns give up the room
local function ui(): any
	local base = Config.rebirth.ui
	if Screen.deviceClass() ~= "phone" then
		return base
	end
	return setmetatable({ footTop = base.phone.footTop, colsHeight = base.phone.colsHeight }, { __index = base })
end

local RebirthPopup = {}
local me = Players.LocalPlayer
local I = Config.images.icons

function RebirthPopup.shownKey(v: State.View): string
	local cost = Config.rebirthCost(v.rebirths + 1)
	-- the coin bar moves in steps, so the popup isn't rebuilt on every coin tick
	local step = math.floor(math.clamp(v.coins / math.max(1, cost), 0, 1) * Config.rebirth.ui.barSteps)
	return `{v.rebirths},{v.coins >= cost},{me:GetAttribute("GunBest")},{step}`
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

-- one icon row: a painted icon and a short word (gates wear the painted gate, owner 2026-11-12)
local function item(h: EquipmentPopup.Helpers, l: GuiObject, order: number, icon: string, word: string, color: Color3?)
	local r = h.row(l, order, Config.rebirth.ui.itemHeight)
	r.Name = "Item" .. order
	local img = Ui.image(r, icon, UDim2.fromScale(0.22, 1), UDim2.fromScale(0.02, 0))
	local a = Instance.new("UIAspectRatioConstraint")
	a.Parent = img
	local t = h.text(r, word, 0.27, 0.71, color)
	-- owner 2026-11-12: "make this text bigger": the title role, in a box as tall as the row
	t.Position = UDim2.fromScale(0.27, 0.02)
	t.Size = UDim2.fromScale(0.71, 0.96)
	if h.sized then
		h.sized(t, "title")
	end
end

-- one white card with a header strip in its colour (KEEP green, RESETS red, YOU GET gold), owner
-- 2026-11-09: "improve the rebirth UI"
local function column(h: EquipmentPopup.Helpers, body: Frame, x: number, title: string, color: Color3): GuiObject
	local R = ui()
	local c = Instance.new("Frame")
	c.Name = title
	c.BackgroundColor3 = Theme.white
	c.BorderSizePixel = 0
	c.ClipsDescendants = true
	c.Position = UDim2.fromScale(x, R.colsTop)
	c.Size = UDim2.fromScale(R.colWidth, R.colsHeight)
	Ui.corner(c)
	Ui.stroke(c, Config.ui.cardStroke)
	c.Parent = body
	local head = Instance.new("Frame")
	head.Name = "Head"
	head.BackgroundColor3 = color
	head.BorderSizePixel = 0
	head.Size = UDim2.fromScale(1, R.colHead)
	Ui.corner(head)
	local square = Instance.new("Frame") -- square bottom corners, rounded top ones (the card's own corners)
	square.BackgroundColor3 = color
	square.BorderSizePixel = 0
	square.Position = UDim2.fromScale(0, 0.5)
	square.Size = UDim2.fromScale(1, 0.5)
	square.ZIndex = 0
	square.Parent = head
	head.Parent = c
	local t = Ui.label(head, title, UDim2.fromScale(0.9, 0.84), UDim2.fromScale(0.05, 0.08))
	if h.sized then
		h.sized(t, "title")
	end
	local holder = Instance.new("Frame")
	holder.Name = "Items"
	holder.BackgroundTransparency = 1
	holder.Position = UDim2.fromScale(0.04, R.colHead + 0.03)
	holder.Size = UDim2.fromScale(0.92, 1 - R.colHead - 0.06)
	holder.Parent = c
	local l = h.list(holder, false)
	local lay = l:FindFirstChildOfClass("UIListLayout")
	if lay then
		lay.VerticalAlignment = Enum.VerticalAlignment.Top
	end
	return l
end

-- the top banner: "Rebirth N" and what your coins become, x1 -> x1.5 (the reason to do it, biggest).
-- Owner 2026-11-12: bigger words and a better arrow. The words use the popup's big role; the arrow is the
-- drawn chunky go-green one (icons/arrow.png) and nudges right now and then (still with Reduced motion).
local function hero(h: EquipmentPopup.Helpers, body: Frame, n: number)
	local R = ui()
	local b = Ui.block(body, "Hero", Theme.booths.rebirth, "", nil)
	b.root.Size = UDim2.fromScale(1, R.heroHeight)
	b.text.Visible = false
	local ty = (1 - R.heroText) / 2
	local title = Ui.label(b.face, `Rebirth {n}`, UDim2.fromScale(0.34, R.heroText), UDim2.fromScale(0.025, ty))
	title.Name = "Title"
	if h.sized then
		h.sized(title, "big")
	end
	local parts: { GuiObject } = {}
	local function mult(value: number, gold: boolean)
		local icon = Ui.image(b.face, I.coin, UDim2.fromScale(0.1, R.heroText), UDim2.fromScale(0, ty))
		local t = Ui.label(b.face, `x{value}`, UDim2.fromScale(0.16, R.heroText), UDim2.fromScale(0, ty))
		t.Name = if gold then "New" else "Now"
		t.TextXAlignment = Enum.TextXAlignment.Left
		if gold then
			t.TextColor3 = Theme.coin -- what you'll have shines gold
		end
		if h.sized then
			h.sized(t, "big")
		end
		table.insert(parts, icon)
		table.insert(parts, t)
	end
	mult(Config.rebirthIncome(n - 1), false)
	local arrow = Ui.image(b.face, I.arrow, UDim2.fromScale(R.arrowWidth, R.heroText * 0.8), UDim2.fromScale(0, 0))
	arrow.Name = "Arrow"
	local aa = arrow:FindFirstChildOfClass("UIAspectRatioConstraint")
	if aa then
		aa.AspectRatio = 512 / 384 -- the drawing's shape (Ui.image keeps pictures square)
	end
	table.insert(parts, arrow)
	mult(Config.rebirthIncome(n), true)
	-- lay the right-hand group out by its visible widths: coin x1 [arrow] coin x1.5, centred in the space
	-- right of the title
	task.defer(function()
		local w = math.max(1, b.face.AbsoluteSize.X)
		local gap = 0.012
		local widths: { number } = {}
		local total = 0
		for _, p in parts do
			local pw = if p:IsA("TextLabel") then p.TextBounds.X / w else p.AbsoluteSize.X / w
			table.insert(widths, pw)
			total += pw
		end
		total += gap * (#parts - 1) + gap * 2 -- a wider gap either side of the arrow
		local x = 0.38 + (0.6 - total) / 2
		for i, p in parts do
			if p == arrow then
				x += gap
			end
			p.AnchorPoint = Vector2.new(0, 0.5)
			p.Position = UDim2.fromScale(x, 0.5)
			x += widths[i] + gap
			if p == arrow then
				x += gap
			end
		end
		-- a little nudge to the right now and then: "this becomes that"
		if SettingsController.get("reducedMotion") ~= true and arrow.Parent then
			local from = arrow.Position
			local to = from + UDim2.fromScale(R.arrowNudgeBy, 0)
			TweenService:Create(arrow, TweenInfo.new(R.arrowNudge / 2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Position = to }):Play()
		end
	end)
end

function RebirthPopup.fill(o: any, v: State.View, h: EquipmentPopup.Helpers)
	o.data = if typeof(o.data) == "table" then o.data else {}
	local n = v.rebirths + 1
	local cost = Config.rebirthCost(n)
	local R = ui()
	hero(h, o.body, n)
	local keep = column(h, o.body, 0, "KEEP", Theme.go)
	item(h, keep, 1, Config.ui.tileIcons.pets, "Pets")
	item(h, keep, 2, I.book, "Index")
	item(h, keep, 3, I.ray, "Guns")
	item(h, keep, 4, I.gate, "Gates")
	item(h, keep, 5, I.pen, "Look")
	local resets = column(h, o.body, R.colWidth + R.colGap, "RESETS", Theme.no)
	item(h, resets, 1, I.coin, "Coins")
	item(h, resets, 2, I.power, "Cold Power") -- Slots are kept since the balance pass 2026-11-17
	local get = column(h, o.body, (R.colWidth + R.colGap) * 2, "YOU GET", Theme.coin)
	item(h, get, 1, I.coin, `x{Config.rebirthIncome(n)} coins`)
	item(h, get, 2, I.power, `x{Config.rebirthIncome(n)} training`)
	local order = 3
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
		item(h, get, order, I.gate, island, Theme.booths.rebirth)
	end
	-- the price and the button along the bottom
	local foot = Instance.new("Frame")
	foot.Name = "Foot"
	foot.BackgroundTransparency = 1
	foot.Position = UDim2.fromScale(0, R.footTop)
	foot.Size = UDim2.fromScale(1, 1 - R.footTop)
	foot.Parent = o.body
	local fl = h.list(foot, false)
	if o.data.ask then
		local q = h.text(h.row(fl, 1, 0.4), `Rebirth {n}? Your coins and Cold Power reset.`, 0, 1, Theme.no)
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
	-- your coins toward the price, as a gold bar with the coin in front
	local pr = h.row(fl, 1, 0.36)
	Ui.image(pr, I.coin, UDim2.fromScale(0.07, 1), UDim2.fromScale(0, 0))
	local label = `{Ui.price(math.min(v.coins, cost))} / {Ui.price(cost)}`
	if h.bar then
		h.bar(pr, 0.08, 0.1, 0.92, 0.8, v.coins / math.max(1, cost), label, Theme.coin)
	else
		h.text(pr, label, 0.08, 0.92)
	end
	local r = h.row(fl, 2, 0.5)
	local go = h.button(r, if have then Theme.booths.rebirth else Theme.tiers.Common, if have then "REBIRTH" else `Need {Ui.price(cost - v.coins)} more`, 0.2, 0.6, function()
		if have then
			o.data.ask = true
			h.refresh()
		else
			State.send("Rebirth", false) -- not enough: the server answers "Need N more"
		end
	end)
	go.root.Name = "RebirthButton"
	if have and h.pulse then
		h.pulse(go.root)
	end
	o.first = go.face
end

function RebirthPopup.Init() end
function RebirthPopup.Start() end

return RebirthPopup
