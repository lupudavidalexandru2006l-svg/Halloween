--!strict
-- EquipmentPopup (Round 4 phase 4): the contents of the Equipment Booth popup. PopupController owns
-- the popup itself (opening, the panel, closing) and hands this module its row / list / button
-- builders. Two tabs:
--   Guns: every gun in order (owned, the one you hold, the next to buy, the locked ones) and a card
--         for the picked gun with its 4 stat bars next to your current gun's (Config.guns; the bars
--         are scaled to the 20-island maximum). Buy / Equip only send intent: GunService decides.
--   Gear: Slow Gel to buy (Round 5: it goes on your hotbar), then the coming gear slots, locked, as
--         silhouettes with "Coming soon" (Round 4 prompt 9).
-- Which guns you own and hold comes from the GunBest / GunTier attributes the server sets.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Theme = require(ReplicatedStorage.Shared.Theme)
local Ui = require(script.Parent.Parent.Lib.Ui)
local State = require(script.Parent.State)
local SoundController = require(script.Parent.SoundController)
local SettingsController = require(script.Parent.SettingsController)
local RayController = require(script.Parent.RayController)

local EquipmentPopup = {}
local me = Players.LocalPlayer
local G = Config.guns

-- PopupController's builders (the optional ones only exist in some versions of it)
export type Helpers = {
	list: (Frame, boolean) -> GuiObject,
	row: (Instance, number, number, number?) -> Frame,
	button: (Instance, Color3, string, number, number, () -> ()) -> Ui.Block,
	text: (Instance, string, number, number, Color3?, string?) -> TextLabel,
	refresh: () -> (),
	card: ((Frame) -> Frame)?,
	sized: ((TextLabel, string) -> ())?,
	priceTag: ((Ui.Block) -> ())?,
}

local function attr(name: string, default: number): number
	local v = me:GetAttribute(name)
	return if typeof(v) == "number" then math.floor(v) else default
end

local function best(): number
	return math.clamp(attr("GunBest", 1), 1, #G.list)
end

local function held(): number
	return math.clamp(attr("GunTier", 1), 1, #G.list)
end

-- "owned" / "held" / "next" (buyable now) / "rebirth" (next, but its rebirth isn't reached) / "locked"
local function status(i: number, v: State.View): string
	local b = best()
	if i == held() then
		return "held"
	elseif i <= b then
		return "owned"
	elseif i == b + 1 then
		return if (v.rebirths or 0) >= G.list[i].rebirths then "next" else "rebirth"
	end
	return "locked"
end

-- what a stat reads on the card
function EquipmentPopup.statText(stat: string, g: Config.Gun): string
	if stat == "power" then
		local s = string.format("%.2f", g.power):gsub("0+$", ""):gsub("%.$", "")
		return "x" .. s
	elseif stat == "cold" then
		return `1-{g.cold}`
	end
	return tostring((g :: any)[stat])
end

-- the popup is only rebuilt when this changes (not on every coin tick)
function EquipmentPopup.shownKey(v: State.View): string
	local nextGun = G.list[best() + 1]
	local afford = nextGun ~= nil and v.coins >= nextGun.price
	local gel = me:GetAttribute("GearGel") == true
	return `{best()},{held()},{v.rebirths},{afford},{gel},{v.coins >= Config.gel.price}`
end

local function textRole(h: Helpers, t: TextLabel, role: string)
	if h.sized then
		h.sized(t, role)
	end
end

-- a round swatch in the gun's glow colour with its number (a UI shape, no emoji)
local function swatch(parent: Instance, i: number, x: number, size: number): Frame
	local f = Instance.new("Frame")
	f.Name = "Swatch"
	f.BackgroundColor3 = (Theme.guns[i] or Theme.guns[1]).glow
	f.AnchorPoint = Vector2.new(0, 0.5)
	f.Position = UDim2.fromScale(x, 0.5)
	f.Size = UDim2.fromScale(size, size)
	local a = Instance.new("UIAspectRatioConstraint")
	a.AspectRatio = 1
	a.DominantAxis = Enum.DominantAxis.Height
	a.Parent = f
	Ui.corner(f, 0.5)
	Ui.stroke(f)
	local n = Ui.label(f, tostring(i), UDim2.fromScale(0.8, 0.7), UDim2.fromScale(0.1, 0.15))
	n.Name = "Number"
	f.Parent = parent
	return f
end

local function gunRow(h: Helpers, l: GuiObject, i: number, v: State.View, o: any)
	local g = G.list[i]
	local st = status(i, v)
	local r = h.row(l, i, 0.2, 4.2)
	r.Name = "Gun" .. i
	local face: Instance = if h.card then h.card(r) else r
	if o.data.pick == i then
		-- the picked row's outline turns blue (one outline per block, UI Rules)
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
	swatch(face, i, 0.03, 0.72)
	local name = h.text(face, g.name, 0.24, 0.48, if st == "locked" then Theme.tiers.Common else nil)
	textRole(h, name, "body")
	local tag = if st == "held" then "Holding"
		elseif st == "owned" then "Owned"
		elseif st == "rebirth" or (st == "locked" and g.rebirths > 0) then `Rebirth {g.rebirths}`
		elseif g.price > 0 then Ui.price(g.price)
		else "Free"
	local tagColor = if st == "held" then Theme.go elseif st == "owned" then Theme.info elseif st == "next" then Theme.coin else Theme.tiers.Common
	local t = h.text(face, tag, 0.74, 0.24, tagColor)
	textRole(h, t, "small")
	-- the whole row picks this gun for the card (click, tap or gamepad A)
	local pick = Instance.new("TextButton")
	pick.Name = "Pick"
	pick.Text = ""
	pick.BackgroundTransparency = 1
	pick.Size = UDim2.fromScale(1, 1)
	pick.ZIndex = 5
	pick.Parent = r
	pick.Activated:Connect(function()
		SoundController.play("click")
		o.data.pick = i
		h.refresh()
	end)
end

-- one stat: its name, a bar for the picked gun, a mark where your current gun is, and the number
local function statBar(h: Helpers, l: GuiObject, order: number, stat: string, g: Config.Gun, cur: Config.Gun, color: Color3)
	local r = h.row(l, order, 0.085)
	local label = h.text(r, G.statLabels[stat], 0, 0.26)
	textRole(h, label, "small")
	local track = Instance.new("Frame")
	track.Name = "Track_" .. stat
	track.BackgroundColor3 = Theme.snowFar
	track.Position = UDim2.fromScale(0.27, 0.25)
	track.Size = UDim2.fromScale(0.5, 0.5)
	Ui.corner(track, 0.5)
	Ui.stroke(track)
	track.Parent = r
	local max = G.statMax[stat]
	local share = math.clamp(((g :: any)[stat] :: number) / max, 0, 1)
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BackgroundColor3 = color
	fill.Size = UDim2.fromScale(share, 1)
	Ui.corner(fill, 0.5)
	fill.Parent = track
	local mark = Instance.new("Frame") -- your current gun's value, to compare
	mark.Name = "Current"
	mark.BackgroundColor3 = Theme.ink
	mark.AnchorPoint = Vector2.new(0.5, 0.5)
	mark.Position = UDim2.fromScale(math.clamp(((cur :: any)[stat] :: number) / max, 0, 1), 0.5)
	mark.Size = UDim2.fromScale(0.012, 1.5)
	mark.Parent = track
	local value = h.text(r, EquipmentPopup.statText(stat, g), 0.8, 0.2)
	value.TextXAlignment = Enum.TextXAlignment.Right
	textRole(h, value, "small")
end

-- the picked gun turning slowly in a window (owner 2026-11-05: a 360 preview), the same model the hand
-- holds (RayController.buildGun). The angle comes from the clock, so a refresh of the card doesn't
-- jump it back to the start; the spin stops itself once the window is gone.
local function preview(parent: Instance, i: number): Frame
	local P = G.preview
	local glow = (Theme.guns[i] or Theme.guns[1]).glow
	local box = Instance.new("Frame")
	box.Name = "Preview"
	box.BackgroundColor3 = glow:Lerp(Theme.white, P.tint)
	box.BorderSizePixel = 0
	box.Size = UDim2.fromScale(0.58, 1)
	Ui.corner(box)
	Ui.stroke(box, Config.ui.cardStroke)
	local vp = Instance.new("ViewportFrame")
	vp.Name = "Gun"
	vp.BackgroundTransparency = 1
	vp.Size = UDim2.fromScale(1, 1)
	vp.Ambient = Color3.fromRGB(190, 190, 205)
	vp.LightColor = Theme.white
	vp.LightDirection = Vector3.new(-1, -1.5, -1) -- lit from the top left, like the icons
	vp.Parent = box
	local cam = Instance.new("Camera")
	cam.FieldOfView = P.fov
	cam.Parent = vp
	vp.CurrentCamera = cam
	local m = RayController.buildGun(i)
	-- centre it on the turning axis
	local bb, size = m:GetBoundingBox()
	local rest = m:GetPivot() - bb.Position
	m:PivotTo(rest)
	m.Parent = vp
	local across = math.sqrt(size.X ^ 2 + size.Z ^ 2) / 2 -- widest it gets while turning
	local pitch = math.rad(P.pitch)
	local tall = (size.Y * math.cos(pitch) + across * 2 * math.sin(pitch)) / 2
	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(function()
		if not vp:IsDescendantOf(game) then
			conn:Disconnect()
			return
		end
		local spin = if SettingsController.get("reducedMotion") == true then P.spinSecondsReduced else P.spinSeconds
		m:PivotTo(CFrame.Angles(0, (os.clock() / spin) % 1 * math.pi * 2, 0) * rest)
		local aspect = vp.AbsoluteSize.X / math.max(1, vp.AbsoluteSize.Y)
		local t = math.tan(math.rad(P.fov / 2))
		local dist = math.max(tall / t, across / (aspect * t)) * P.margin + across * 0.5 -- the near end swings toward the camera
		cam.CFrame = CFrame.lookAt(Vector3.new(0, math.sin(pitch), math.cos(pitch)) * dist, Vector3.zero)
	end)
	box.Parent = parent
	return box
end

local function gunCard(h: Helpers, holder: Frame, i: number, v: State.View, o: any)
	local g = G.list[i]
	local cur = G.list[held()]
	local st = status(i, v)
	local l = h.list(holder, false)
	-- the gun turning on the left, its number and name on the right
	local top = h.row(l, 1, 0.42)
	preview(top, i)
	local badge = swatch(top, i, 0.62, 0.3)
	badge.AnchorPoint = Vector2.new(0, 0)
	badge.Position = UDim2.fromScale(0.62, 0.06)
	local name = h.text(top, g.name, 0.62, 0.37)
	name.Size = UDim2.fromScale(0.37, 0.56)
	name.Position = UDim2.fromScale(0.62, 0.4)
	name.TextYAlignment = Enum.TextYAlignment.Top
	textRole(h, name, "body")
	for n, stat in G.stats do
		statBar(h, l, n + 1, stat, g, cur, (Theme.guns[i] or Theme.guns[1]).glow)
	end
	local r = h.row(l, 10, 0.15)
	local label, color = "Locked", Theme.tiers.Common
	if st == "held" then
		label, color = "Holding", Theme.go
	elseif st == "owned" then
		label, color = "Equip", Theme.info
	elseif st == "next" then
		label = if g.price > 0 then Ui.price(g.price) else "Get it"
		color = if v.coins >= g.price then Theme.coin else Theme.tiers.Common
	elseif st == "rebirth" or g.rebirths > 0 then
		label = `Rebirth {g.rebirths}`
	end
	local b = h.button(r, color, label, 0.2, 0.6, function()
		if st == "owned" then
			State.send("EquipGun", i)
		elseif st == "next" then
			State.send("BuyGun", i) -- the server checks the coins, the order and the rebirth
		elseif st ~= "held" then
			State.local_("notYet", { reason = if g.rebirths > (v.rebirths or 0) then `Needs Rebirth {g.rebirths}` else "Buy the one before first" })
		end
	end)
	b.root.Name = "Action"
	if st == "next" and g.price > 0 and h.priceTag then
		h.priceTag(b)
	end
	o.first = b.face
end

-- a gear slot's silhouette, drawn from plain shapes (no picture of the gear yet)
local SHAPES: { [string]: { { number } } } = { -- x, y, w, h (shares of the slot), round
	coat = { { 0.3, 0.2, 0.4, 0.62, 0.15 }, { 0.14, 0.24, 0.2, 0.46, 0.4 }, { 0.66, 0.24, 0.2, 0.46, 0.4 } },
	hat = { { 0.12, 0.56, 0.76, 0.14, 0.5 }, { 0.3, 0.28, 0.4, 0.34, 0.35 } },
	vest = { { 0.26, 0.2, 0.48, 0.62, 0.2 } },
	boots = { { 0.16, 0.26, 0.24, 0.42, 0.25 }, { 0.16, 0.58, 0.34, 0.16, 0.5 }, { 0.54, 0.26, 0.24, 0.42, 0.25 }, { 0.54, 0.58, 0.34, 0.16, 0.5 } },
	suit = { { 0.34, 0.12, 0.32, 0.22, 0.5 }, { 0.28, 0.32, 0.44, 0.38, 0.2 }, { 0.3, 0.66, 0.16, 0.24, 0.3 }, { 0.54, 0.66, 0.16, 0.24, 0.3 } },
}

local function gear(h: Helpers, body: Frame, v: State.View, o: any)
	local l = h.list(body, false)
	-- Slow Gel (Round 5): a card with its picture, what it does, and Buy / Owned
	local owned = me:GetAttribute("GearGel") == true
	local gr = h.row(l, 0, 0.3)
	gr.Name = "SlowGel"
	local face: Instance = if h.card then h.card(gr) else gr
	Ui.image(face, Config.images.icons.motion, UDim2.fromScale(0.2, 0.84), UDim2.fromScale(0.01, 0.08))
	local name = h.text(face, "Slow Gel", 0.2, 0.5)
	textRole(h, name, "body")
	name.Size = UDim2.fromScale(0.5, 0.45)
	name.Position = UDim2.fromScale(0.2, 0.06)
	local what = h.text(face, `Pets and critters x{Config.gel.slow}`, 0.2, 0.5, Theme.infoDeep)
	textRole(h, what, "small")
	what.Size = UDim2.fromScale(0.5, 0.38)
	what.Position = UDim2.fromScale(0.2, 0.52)
	local can = v.coins >= Config.gel.price
	local b = h.button(face, if owned then Theme.go elseif can then Theme.coin else Theme.tiers.Common,
		if owned then "Owned" else Ui.price(Config.gel.price), 0.72, 0.26, function()
			if not owned then
				State.send("BuyGear", "gel") -- the server checks the coins and the booth
			end
		end)
	b.root.Name = "BuyGel"
	if not owned and h.priceTag then
		h.priceTag(b)
	end
	o.first = b.face
	local r = h.row(l, 1, 0.34)
	local n = #Config.gear
	for i, item in Config.gear do
		local slot = Instance.new("Frame")
		slot.Name = "Gear_" .. item.key
		slot.BackgroundColor3 = Theme.snowFar
		slot.AnchorPoint = Vector2.new(0.5, 0.5)
		slot.Position = UDim2.fromScale((i - 0.5) / n, 0.5)
		slot.Size = UDim2.fromScale(0.9 / n, 0.9)
		local a = Instance.new("UIAspectRatioConstraint")
		a.AspectRatio = 1
		a.Parent = slot
		Ui.corner(slot)
		Ui.stroke(slot)
		for _, s in SHAPES[item.shape] or {} do
			local p = Instance.new("Frame")
			p.BackgroundColor3 = Theme.ink
			p.BackgroundTransparency = 0.15
			p.Position = UDim2.fromScale(s[1], s[2])
			p.Size = UDim2.fromScale(s[3], s[4])
			Ui.corner(p, s[5])
			p.Parent = slot
		end
		slot.Parent = r
	end
	local t = h.text(h.row(l, 2, 0.16), "Coming soon", 0.02, 0.96)
	t.TextXAlignment = Enum.TextXAlignment.Center
	textRole(h, t, "title")
end

function EquipmentPopup.fill(o: any, v: State.View, h: Helpers)
	o.data = if typeof(o.data) == "table" then o.data else { tab = "guns" }
	local body: Frame = o.body
	-- the tabs
	local tabs = Instance.new("Frame")
	tabs.Name = "Tabs"
	tabs.BackgroundTransparency = 1
	tabs.Size = UDim2.fromScale(1, 0.12)
	tabs.Parent = body
	for k, tab in { { id = "guns", label = "Guns" }, { id = "gear", label = "Gear" } } do
		local on = o.data.tab == tab.id
		local b = h.button(tabs, if on then Theme.booths.equipment else Theme.tiers.Common, tab.label, (k - 1) * 0.26, 0.24, function()
			o.data.tab = tab.id
			h.refresh()
		end)
		b.root.Name = "Tab_" .. tab.id
	end
	local content = Instance.new("Frame")
	content.Name = "Content"
	content.BackgroundTransparency = 1
	content.Position = UDim2.fromScale(0, 0.14)
	content.Size = UDim2.fromScale(1, 0.86)
	content.Parent = body
	if o.data.tab == "gear" then
		gear(h, content, v, o)
		return
	end
	o.data.pick = o.data.pick or math.min(best() + 1, #G.list)
	local left = Instance.new("Frame")
	left.Name = "Guns"
	left.BackgroundTransparency = 1
	left.Size = UDim2.fromScale(0.5, 1)
	left.Parent = content
	local l = h.list(left, true)
	for i = 1, #G.list do
		gunRow(h, l, i, v, o)
	end
	local right = Instance.new("Frame")
	right.Name = "Card"
	right.BackgroundTransparency = 1
	right.Position = UDim2.fromScale(0.53, 0)
	right.Size = UDim2.fromScale(0.47, 1)
	right.Parent = content
	gunCard(h, right, o.data.pick, v, o)
end

return EquipmentPopup
