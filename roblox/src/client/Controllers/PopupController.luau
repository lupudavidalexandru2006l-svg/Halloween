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

-- update: set by popups that change their own labels instead of being rebuilt (the Tester panel)
type Open = { name: string, data: any, frame: Frame, body: Frame, first: GuiObject?, update: ((State.View) -> ())?, closed: boolean? }
local current: Open? = nil
local queue: { { name: string, data: any } } = {}
local MENUS = { pets = true, shop = true, index = true, settings = true, tester = true }
local TITLES: { [string]: string } = {
	pets = "Pets", shop = "Shop", index = "Index", settings = "Settings", tester = "Tester",
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
		sf.Name = "List"
		sf.BackgroundTransparency = 1
		sf.Size = UDim2.fromScale(1, 1)
		sf.CanvasSize = UDim2.fromScale(0, 0)
		sf.AutomaticCanvasSize = Enum.AutomaticSize.Y
		sf.ScrollBarThickness = 8
		sf.ScrollBarImageColor3 = Theme.ink
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
	layout.Parent = holder
	if holder:IsA("ScrollingFrame") then
		-- AutomaticCanvasSize under-counts rows sized by an aspect ratio (the last rows of a long list
		-- could never be reached), so the canvas follows the measured content height instead
		local sf = holder
		sf.AutomaticCanvasSize = Enum.AutomaticSize.None
		local function fit()
			sf.CanvasSize = UDim2.fromOffset(0, layout.AbsoluteContentSize.Y)
		end
		layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(fit)
		fit()
	end
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
		if def.icon ~= "" then
			Ui.image(r, def.icon, UDim2.fromScale(0.1, 1), UDim2.fromScale(0.01, 0))
		end
		text(r, def.name .. extra, 0.12, 0.34, tierColor(def.tier))
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
			-- the painted pet, or its dark silhouette while it's still missing (the Secret stays a mystery)
			if def.icon ~= "" and (found or not secret) then
				Ui.image(b.face, def.icon, UDim2.fromScale(0.8, 0.66), UDim2.fromScale(0.1, 0.02), not found)
				b.text.Size = UDim2.fromScale(0.9, 0.28)
				b.text.Position = UDim2.fromScale(0.05, 0.68)
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
	button(r, Theme.go, "Open all gates", 0.02, 0.3, function()
		send("openGates")
	end)
	button(r, Theme.go, "Max all upgrades", 0.34, 0.3, function()
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
	button(r, Theme.info, "Away 1 h", 0.35, 0.31, function()
		send("away", 3600)
	end)
	button(r, Theme.info, "Away 8 h", 0.68, 0.3, function()
		send("away", 8 * 3600)
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
		elseif o.name == "tester" then
			tester(o, v)
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
	o.closed = true
	current = nil
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
			PopupController.refresh()
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
