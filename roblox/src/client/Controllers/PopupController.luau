--!strict
-- PopupController: owns every popup (Pets, Shop, Index, Settings, welcome back, gift, page done).
-- One at a time, centred a little above the middle; reward popups wait in a queue behind a menu.
-- Buttons only send intent; the server answers and the next "Data" redraws the popup.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Theme = require(ReplicatedStorage.Shared.Theme)
local PetDefs = require(ReplicatedStorage.Shared.PetDefs)
local Ui = require(script.Parent.Parent.Lib.Ui)
local State = require(script.Parent.State)
local Screen = require(script.Parent.Screen)
local InputController = require(script.Parent.InputController)
local SoundController = require(script.Parent.SoundController)
local SettingsController = require(script.Parent.SettingsController)

local PopupController = {}

type Open = { name: string, data: any, frame: Frame, body: Frame, first: GuiObject? }
local current: Open? = nil
local queue: { { name: string, data: any } } = {}
local MENUS = { pets = true, shop = true, index = true, settings = true }
local TITLES: { [string]: string } = {
	pets = "Pets", shop = "Shop", index = "Index", settings = "Settings",
	welcome = "Welcome back!", gift = "Daily gift", pageDone = "Page complete!",
}

local UPGRADE_TEXT: { [string]: (level: number) -> string } = {
	ray = function()
		return `Cubes last {math.round(Config.upgrades.ray.lifeBonus * 100)}% longer`
	end,
	boots = function()
		return `Run {math.round(Config.upgrades.boots.speedBonus * 100)}% faster`
	end,
	backpack = function(level)
		return `Carry {level + 1} cubes`
	end,
	pen = function()
		return `+{Config.upgrades.pen.slotsPerLevel} pen slots`
	end,
}

local function tierColor(tier: string): Color3
	return Theme.tiers[tier] or Theme.ink
end

-- a row of blocks laid out left to right; widths are fractions of the row
-- aspect: inside a scrolling list the height comes from the width (Scale of an auto-sized canvas would loop)
local function row(parent: Instance, order: number, height: number, aspect: number?): Frame
	local f = Instance.new("Frame")
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
	local b = Ui.block(parent, "Button", color, text, function()
		SoundController.play("click")
		onPress()
	end)
	b.root.Position = UDim2.fromScale(x, 0.1)
	b.root.Size = UDim2.fromScale(w, 0.8)
	return b
end

local function text(parent: Instance, s: string, x: number, w: number, color: Color3?): TextLabel
	local t = Ui.label(parent, s, UDim2.fromScale(w, 0.7), UDim2.fromScale(x, 0.15))
	t.TextXAlignment = Enum.TextXAlignment.Left
	if color then
		t.TextColor3 = color
	end
	return t
end

local function list(body: Frame, scroll: boolean): GuiObject
	local holder: GuiObject
	if scroll then
		local sf = Instance.new("ScrollingFrame")
		sf.BackgroundTransparency = 1
		sf.Size = UDim2.fromScale(1, 1)
		sf.CanvasSize = UDim2.fromScale(0, 0)
		sf.AutomaticCanvasSize = Enum.AutomaticSize.Y
		sf.ScrollBarThickness = 8
		sf.ScrollBarImageColor3 = Theme.ink
		holder = sf
	else
		local f = Instance.new("Frame")
		f.BackgroundTransparency = 1
		f.Size = UDim2.fromScale(1, 1)
		holder = f
	end
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0.015, 0)
	layout.Parent = holder
	holder.Parent = body
	return holder
end

-- ---------- contents ----------
local function shop(o: Open, v: State.View)
	local l = list(o.body, false)
	for i, id in Config.upgradeIds do
		local u = Config.upgrades[id]
		local level = v.upgrades[id] or 1
		local r = row(l, i, 0.22)
		text(r, `{u.name}  Lv {level}`, 0.02, 0.34)
		local maxed = level >= u.maxLevel
		text(r, if maxed then "Max level" else UPGRADE_TEXT[id](level), 0.37, 0.33, Theme.ice)
		local cost = Config.upgradeCost(id, level + 1)
		local b = button(r, if maxed then Theme.tiers.Common elseif v.coins >= cost then Theme.coin else Theme.tiers.Common,
			if maxed then "Max" else Ui.short(cost), 0.72, 0.26, function()
				State.send("BuyUpgrade", id)
			end)
		if i == 1 then
			o.first = b.face
		end
	end
end

local function pets(o: Open, v: State.View)
	local pen = 0
	for _, p in v.pets do
		if p.eq then
			pen += 1
		end
	end
	local head = row(o.body, 0, 0.14)
	text(head, `Pen {pen} / {v.slots}   Storage {#v.pets - pen}`, 0.02, 0.6)
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
		text(row(l, 1, 0, 9), "Freeze a pet and carry it to your pen!", 0.02, 0.96)
	end
	for i, p in sorted do
		local def = PetDefs.get(p.key)
		if not def then
			continue
		end
		local r = row(l, i, 0, 9)
		local pose = Config.poses[p.pose]
		local extra = (if pose and p.pose ~= "idle" then " " .. pose.label else "") .. (if p.mut then " " .. p.mut else "")
		text(r, def.name .. extra, 0.02, 0.44, tierColor(def.tier))
		text(r, `{Ui.short(p.income)}/s`, 0.47, 0.2)
		button(r, if p.eq then Theme.go else Theme.info, if p.eq then "In pen" else "Storage", 0.7, 0.28, function()
			State.send("EquipPet", p.id, not p.eq)
		end)
	end
end

local function index(o: Open, v: State.View)
	local l = list(o.body, true)
	for i, page in v.pages do
		local zone = Config.zone(page.zone)
		local head = row(l, i * 10, 0, 10)
		text(head, `{if zone then zone.name else "Zone"}  {page.found} / {page.total}`, 0.02, 0.6)
		text(head, if page.complete then `+{math.round(Config.index.pageBonus * 100)}% coins` else "", 0.64, 0.34, Theme.coin)
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
			local b = Ui.block(grid, def.key, if found then tierColor(def.tier) else Theme.board,
				if found then def.name elseif secret then "Bonus" else "?", nil)
			b.root.LayoutOrder = n
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
		local line = row(l, i, 0.17)
		text(line, r.label, 0.02, 0.6)
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
end

local function message(o: Open, lines: { string }, okText: string, onOk: () -> ())
	local l = list(o.body, false)
	for i, s in lines do
		local r = row(l, i, 0.2)
		local t = text(r, s, 0.02, 0.96)
		t.TextXAlignment = Enum.TextXAlignment.Center
	end
	local r = row(l, #lines + 1, 0.22)
	local b = button(r, Theme.go, okText, 0.3, 0.4, function()
		onOk()
		PopupController.close()
	end)
	o.first = b.face
end

local function fill(o: Open)
	for _, c in o.body:GetChildren() do
		c:Destroy()
	end
	o.first = nil
	local v = State.view
	if o.name == "settings" then
		settings(o)
	elseif o.name == "welcome" then
		local w = o.data
		local hours = math.floor(w.awaySeconds / 3600)
		local best = w.best and PetDefs.get(w.best)
		message(o, {
			`Your pets earned {Ui.commas(w.coins)} coins while you were away`,
			if w.capped then "(up to 8 hours count)" elseif hours > 0 then `You were away {hours} h` else "",
			if best then `Your best catch last time: {best.name}` else "",
		}, "Collect", function()
			State.send("CollectWelcome")
		end)
	elseif o.name == "gift" then
		message(o, { `+{Ui.commas(o.data.coins)} coins`, `Day {o.data.streak} in a row` }, "Yay", function() end)
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
		end
	end
	InputController.select(o.first)
end

function PopupController.isOpen(): boolean
	return current ~= nil
end

function PopupController.refresh()
	local o = current
	if o then
		local scroll = o.body:FindFirstChildWhichIsA("ScrollingFrame", true)
		local at = if scroll then scroll.CanvasPosition else nil
		fill(o)
		local again = o.body:FindFirstChildWhichIsA("ScrollingFrame", true)
		if again and at then
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
	current = nil
	InputController.select(nil)
	State.send("SetMenuOpen", false)
	local nextOne = table.remove(queue, 1)
	if nextOne then
		PopupController.open(nextOne.name, nextOne.data)
	end
end

function PopupController.open(name: string, data: any?)
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
	local panel = Ui.block(frame, "Panel", Theme.panel, "", nil)
	panel.root.Size = UDim2.fromScale(1, 1)
	panel.text.Visible = false
	local title = Ui.label(panel.face, TITLES[name] or "", UDim2.fromScale(0.7, 0.11), UDim2.fromScale(0.15, 0.025))
	title.TextColor3 = Theme.white
	local closeB = Ui.block(panel.face, "Close", Theme.no, "X", PopupController.close)
	closeB.root.AnchorPoint = Vector2.new(1, 0)
	closeB.root.Position = UDim2.fromScale(0.98, 0.02)
	closeB.root.Size = UDim2.fromScale(0.08, 0.12)
	local body = Instance.new("Frame")
	body.Name = "Body"
	body.BackgroundTransparency = 1
	body.Position = UDim2.fromScale(0.04, 0.16)
	body.Size = UDim2.fromScale(0.92, 0.8)
	body.Parent = panel.face
	local o: Open = { name = name, data = data, frame = frame, body = body, first = nil }
	current = o
	State.send("SetMenuOpen", true)
	if name == "shop" then
		State.send("ShopOpened")
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
	State.Changed:Connect(function()
		if current and MENUS[current.name] and current.name ~= "settings" then
			PopupController.refresh()
		end
	end)
	State.Notify:Connect(function(kind: string, data: any)
		if kind == "welcomeBack" then
			PopupController.open("welcome", data)
		elseif kind == "giftClaimed" then
			PopupController.open("gift", data)
		elseif kind == "pageDone" then
			PopupController.open("pageDone", data)
		end
	end)
end

return PopupController
