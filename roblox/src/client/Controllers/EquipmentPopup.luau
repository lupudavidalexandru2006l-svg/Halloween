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
local Screen = require(script.Parent.Screen)

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
	bar: ((Instance, number, number, number, number, number, string, Color3) -> Frame)?, -- x, y, w, h, share, label, colour
	pulse: ((GuiObject) -> ())?, -- the screen's one focal point breathes gently
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
	if stat == "training" then
		return `x{g.training}` -- the Cold Power multiplier of every training shot
	elseif stat == "heat" then
		return `1-{g.heat}` -- the islands it works on
	end
	return tostring((g :: any)[stat])
end

-- the popup is only rebuilt when this changes (not on every coin tick)
function EquipmentPopup.shownKey(v: State.View): string
	local nextGun = G.list[best() + 1]
	local afford = nextGun ~= nil and v.coins >= nextGun.price
	local gear = ""
	for _, g in Config.gear do -- each gear card: its level, and whether the next one is affordable
		local lv = me:GetAttribute("GearLv_" .. g.key)
		lv = if typeof(lv) == "number" then lv else 0
		local p = Config.gearPrice(g.key, lv)
		gear ..= `{lv}{p ~= nil and v.coins >= p}`
	end
	return `{best()},{held()},{v.rebirths},{afford},{gear}`
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

-- a white pill with the coin and a price (or "Free"), on a tile (every gun shows its price, owner 2026-11-09)
local function pricePill(h: Helpers, parent: Instance, price: number, x: number, y: number, w: number, hgt: number): Frame
	local p = Instance.new("Frame")
	p.Name = "Price"
	p.BackgroundColor3 = Theme.white
	p.BorderSizePixel = 0
	p.Position = UDim2.fromScale(x, y)
	p.Size = UDim2.fromScale(w, hgt)
	Ui.corner(p, 0.5)
	Ui.stroke(p)
	Ui.image(p, Config.images.icons.coin, UDim2.fromScale(0.3, 0.86), UDim2.fromScale(0.02, 0.07))
	local t = Ui.inkLabel(p, if price > 0 then Ui.price(price) else "Free", UDim2.fromScale(0.64, 0.8), UDim2.fromScale(0.32, 0.1))
	textRole(h, t, "small")
	p.Parent = parent
	return p
end

-- a small coloured chip ("Owned", "Holding") with white outlined words
local function chip(h: Helpers, parent: Instance, s: string, color: Color3, x: number, y: number, w: number, hgt: number)
	local c = Instance.new("Frame")
	c.Name = "Chip"
	c.BackgroundColor3 = color
	c.BorderSizePixel = 0
	c.Position = UDim2.fromScale(x, y)
	c.Size = UDim2.fromScale(w, hgt)
	Ui.corner(c, 0.5)
	Ui.stroke(c)
	local t = Ui.label(c, s, UDim2.fromScale(0.9, 0.8), UDim2.fromScale(0.05, 0.1))
	textRole(h, t, "small")
	c.Parent = parent
end

local gunView: (Instance, number, boolean, boolean, number?) -> ViewportFrame -- the gun in a window (below)

-- one gun as a Chunky Pop tile in its own glow colour: number, picture, name, Owned / Holding, price.
-- Guns you can't buy yet are greyed. The whole tile picks the gun for the card on the right.
local function gunTile(h: Helpers, parent: Instance, i: number, v: State.View, o: any)
	local g = G.list[i]
	local st = status(i, v)
	local color = (Theme.guns[i] or Theme.guns[1]).glow
	if st == "locked" then
		color = color:Lerp(Theme.tiers.Common, G.lockedGrey)
	end
	color = color:Lerp(Theme.ink, G.tileShade) -- deeper tiles so the white names stand out
	local b = Ui.block(parent, "Gun" .. i, color, "", function()
		SoundController.play("click")
		o.data.pick = i
		h.refresh()
	end)
	b.root.LayoutOrder = i
	b.text.Visible = false
	if o.data.pick == i then
		-- the picked tile gets a white outline (still one outline per block)
		local s = b.root:FindFirstChildOfClass("UIStroke")
		if s then
			s.Color = Theme.white
			s.Thickness = Config.ui.stroke + 2
		end
	end
	local num = swatch(b.face, i, 0.025, 0.42)
	num.BackgroundColor3 = Theme.white
	local numText = num:FindFirstChild("Number") :: TextLabel?
	if numText then
		numText.TextColor3 = Theme.ink
		local s = numText:FindFirstChildOfClass("UIStroke")
		if s then
			s.Enabled = false
		end
	end
	-- the gun itself (owner 2026-11-12: not one picture for all ten); plain black with a lock until it's yours
	local T = G.tile
	local window = Instance.new("Frame")
	window.Name = "Picture"
	window.BackgroundTransparency = 1
	window.Position = UDim2.fromScale(T.viewX, 0.03)
	window.Size = UDim2.fromScale(T.viewW, 0.94)
	window.Parent = b.face
	local unowned = i > best()
	gunView(window, i, unowned, false)
	if unowned then
		local lock = Ui.image(window, Config.images.icons.lock, UDim2.fromScale(T.lock, T.lock), UDim2.fromScale(1 - T.lock, 1 - T.lock))
		lock.Name = "Lock"
		lock.ZIndex = 3
	end
	local name = Ui.label(b.face, g.name, UDim2.fromScale(0.6, 0.46), UDim2.fromScale(0.36, 0.06))
	name.TextXAlignment = Enum.TextXAlignment.Left
	textRole(h, name, "body")
	-- a gun you have shows Owned / Holding in the price's place: its price beside it read as "pay again"
	-- (QA 2026-11-17), and the wider chip keeps its word readable on a phone (it was 8 px)
	if st == "held" then
		chip(h, b.face, "Holding", Theme.coin, 0.36, 0.56, 0.6, 0.32)
	elseif st == "owned" then
		chip(h, b.face, "Owned", Theme.go, 0.36, 0.56, 0.6, 0.32)
	else
		pricePill(h, b.face, g.price, 0.65, 0.56, 0.32, 0.32)
	end
end

-- one stat on the card's white panel (owner 2026-11-12: "the stat bars look too simple"): its name, a
-- chunky bar and the number on a pill. The bar compares the picked gun with the one you hold: blue is
-- what both have, green is what you'd gain, pale red what you'd lose (colour meanings, UI Rules).
local function statBar(h: Helpers, parent: Instance, n: number, count: number, stat: string, g: Config.Gun, cur: Config.Gun)
	local S = G.statCard
	local rh = (1 - S.pad * 2) / count
	local r = Instance.new("Frame")
	r.Name = "Stat_" .. stat
	r.BackgroundTransparency = 1
	r.Position = UDim2.fromScale(0.04, S.pad + (n - 1) * rh)
	r.Size = UDim2.fromScale(0.92, rh)
	r.Parent = parent
	-- a phone has no room for the bar (QA 2026-11-17: its numbers came out 6 px): the name and the number only,
	-- each twice as wide, still green / red for gain / loss
	local phone = Screen.deviceClass() == "phone"
	local label = h.text(r, G.statLabels[stat], 0, if phone then 0.5 else S.labelW)
	textRole(h, label, "small")
	local track = Instance.new("Frame")
	track.Name = "Track_" .. stat
	track.BackgroundColor3 = Theme.slot
	track.BorderSizePixel = 0
	track.AnchorPoint = Vector2.new(0, 0.5)
	track.Position = UDim2.fromScale(S.trackX, 0.5)
	track.Size = UDim2.fromScale(S.trackW, S.trackH)
	Ui.corner(track, 0.5)
	Ui.stroke(track)
	track.Parent = r
	track.Visible = not phone
	local value, held_ = (g :: any)[stat] :: number, (cur :: any)[stat] :: number
	local share, heldShare = Config.gunStatShare(stat, value), Config.gunStatShare(stat, held_)
	-- every piece is a pill that starts at the left edge, so each keeps its round end
	local function piece(name: string, s: number, color: Color3, z: number)
		local f = Instance.new("Frame")
		f.Name = name
		f.BackgroundColor3 = Theme.white
		f.BorderSizePixel = 0
		f.Size = UDim2.fromScale(math.clamp(s, S.minFill, 1), 1)
		f.ZIndex = z
		Ui.corner(f, 0.5)
		local shade = Instance.new("UIGradient") -- a lighter top, like the blocks
		shade.Rotation = 90
		shade.Color = ColorSequence.new(color:Lerp(Theme.white, S.topLight), color)
		shade.Parent = f
		f.Parent = track
	end
	if share > heldShare then
		piece("Gain", share, Theme.go, 1)
	elseif share < heldShare then
		piece("Loss", heldShare, Theme.no:Lerp(Theme.white, 0.5), 1)
	end
	piece("Fill", math.min(share, heldShare), Theme.info, 2)
	local shine = Instance.new("Frame") -- a thin gloss line along the top of the bar
	shine.Name = "Shine"
	shine.BackgroundColor3 = Theme.white
	shine.BackgroundTransparency = S.shine
	shine.BorderSizePixel = 0
	shine.Position = UDim2.fromScale(0.03, 0.14)
	shine.Size = UDim2.fromScale(0.94, 0.2)
	shine.ZIndex = 3
	Ui.corner(shine, 0.5)
	shine.Parent = track
	local pill = Instance.new("Frame")
	pill.Name = "Value"
	pill.BackgroundColor3 = Theme.white
	pill.BorderSizePixel = 0
	pill.AnchorPoint = Vector2.new(0, 0.5)
	local vx = if phone then 0.52 else S.valueX
	pill.Position = UDim2.fromScale(vx, 0.5)
	pill.Size = UDim2.fromScale(1 - vx, if phone then 0.86 else S.trackH * 1.15)
	Ui.corner(pill, 0.5)
	Ui.stroke(pill, Config.ui.cardStroke)
	pill.Parent = r
	local t = Ui.inkLabel(pill, EquipmentPopup.statText(stat, g), UDim2.fromScale(0.86, 0.8), UDim2.fromScale(0.07, 0.1))
	if value > held_ then
		t.TextColor3 = Theme.shopBadge.bonus
	elseif value < held_ then
		t.TextColor3 = Theme.no
	end
	textRole(h, t, "small")
end

-- a gun in a window: the same model the hand holds (RayController.buildGun), still (a tile) or turning
-- (the card). dark = a gun you don't own yet: only its shape in solid black (the window's ImageColor3
-- multiplies every colour to black), `fade` see-through on the card (owner 2026-11-12).
-- A turning gun's angle comes from the clock, so a refresh of the card doesn't jump it back to the
-- start; the spin stops itself once the window is gone.
-- even = every gun at one scale: framed as if it were the biggest gun's box, so a small chunky gun isn't
-- blown up past a long thin one (the island banner, owner 2026-11-17: "make sure their sizes match")
local sharedBox: Vector3? = nil
local function biggestGunBox(fallback: Vector3): Vector3
	if not sharedBox then
		local box = Vector3.zero
		local models = ReplicatedStorage:FindFirstChild("GunModels")
		for _, m in (if models then models:GetChildren() else {}) do
			if m:IsA("Model") then
				local _, s = m:GetBoundingBox()
				box = box:Max(s)
			end
		end
		sharedBox = if box.Magnitude > 0 then box else nil
	end
	return sharedBox or fallback
end

-- faceRight: the muzzle points right (the island banner's "Recommended" gun, owner 2026-11-18)
function gunView(parent: Instance, i: number, dark: boolean, spin: boolean, fade: number?, even: boolean?, faceRight: boolean?): ViewportFrame
	local P = G.preview
	local vp = Instance.new("ViewportFrame")
	vp.Name = "Gun"
	vp.BackgroundTransparency = 1
	vp.Size = UDim2.fromScale(1, 1)
	vp.Ambient = Color3.fromRGB(190, 190, 205)
	vp.LightColor = Theme.white
	vp.LightDirection = Vector3.new(-1, -1.5, -1) -- lit from the top left, like the icons
	if dark then
		vp.ImageColor3 = Theme.silhouette
		vp.ImageTransparency = fade or 0
	end
	vp.Parent = parent
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
	size = if even then biggestGunBox(size) else size -- the box the camera fits
	local pitch = math.rad(P.pitch)
	local t = math.tan(math.rad(P.fov / 2))
	-- across = half its width as the camera sees it, depth = how far its near end comes toward the camera
	local function frame(yaw: number, across: number, depth: number)
		m:PivotTo(CFrame.Angles(0, yaw, 0) * rest)
		local tall = (size.Y * math.cos(pitch) + across * 2 * math.sin(pitch)) / 2
		local aspect = vp.AbsoluteSize.X / math.max(1, vp.AbsoluteSize.Y)
		local dist = math.max(tall / t, across / (aspect * t)) * P.margin + depth
		cam.CFrame = CFrame.lookAt(Vector3.new(0, math.sin(pitch), math.cos(pitch)) * dist, Vector3.zero)
	end
	if spin then
		local across = math.sqrt(size.X ^ 2 + size.Z ^ 2) / 2 -- widest it gets while turning
		local conn: RBXScriptConnection
		conn = RunService.RenderStepped:Connect(function()
			if not vp:IsDescendantOf(game) then
				conn:Disconnect()
				return
			end
			local seconds = if SettingsController.get("reducedMotion") == true then P.spinSecondsReduced else P.spinSeconds
			frame((os.clock() / seconds) % 1 * math.pi * 2, across, across * 0.5)
		end)
	else
		local yaw = math.rad(G.tileYaw) + (if faceRight then math.pi else 0)
		local c, s = math.abs(math.cos(yaw)), math.abs(math.sin(yaw))
		local function still()
			frame(yaw, (size.X * c + size.Z * s) / 2, (size.X * s + size.Z * c) / 2)
		end
		vp:GetPropertyChangedSignal("AbsoluteSize"):Connect(still)
		still()
	end
	return vp
end

-- the picked gun turning slowly in a big window in its glow colour (owner 2026-11-05: a 360 preview).
-- A gun you don't own turns as a see-through black figurine with a lock in the corner.
local function preview(parent: Instance, i: number, dark: boolean): Frame
	local P = G.preview
	local glow = (Theme.guns[i] or Theme.guns[1]).glow
	local box = Instance.new("Frame")
	box.Name = "Preview"
	box.BackgroundColor3 = glow:Lerp(Theme.white, P.tint)
	box.BorderSizePixel = 0
	box.Size = UDim2.fromScale(0.58, 1)
	Ui.corner(box)
	Ui.stroke(box, Config.ui.cardStroke)
	gunView(box, i, dark, true, P.lockedFade)
	if dark then
		local lock = Ui.image(box, Config.images.icons.lock, UDim2.fromScale(0.2, 0.3), UDim2.fromScale(0.79, 0.03))
		lock.Name = "Lock"
	end
	box.Parent = parent
	return box
end

local function gunCard(h: Helpers, holder: Frame, i: number, v: State.View, o: any)
	local g = G.list[i]
	local cur = G.list[held()]
	local st = status(i, v)
	local l = h.list(holder, false)
	-- the gun turning in a big window in its glow colour, its number in the corner, the name under it
	local phone = Screen.deviceClass() == "phone"
	local top = h.row(l, 1, if phone then 0.24 else 0.33) -- a phone gives the stats more of the card
	local box = preview(top, i, i > best())
	box.Size = UDim2.fromScale(1, 1)
	local badge = swatch(box, i, 0.02, 0.24)
	badge.AnchorPoint = Vector2.new(0, 0)
	badge.Position = UDim2.fromScale(0.02, 0.04)
	badge.BackgroundColor3 = Theme.white
	local bn = badge:FindFirstChild("Number") :: TextLabel?
	if bn then
		bn.TextColor3 = Theme.ink
		local s = bn:FindFirstChildOfClass("UIStroke")
		if s then
			s.Enabled = false
		end
	end
	local name = Ui.label(h.row(l, 2, 0.09), g.name, UDim2.fromScale(1, 0.9), UDim2.fromScale(0, 0.05))
	textRole(h, name, "title")
	-- on the pale panel: dark ink letters, not white ones (owner 2026-11-17: "more contrast")
	name.TextColor3 = Theme.ink
	local ns = name:FindFirstChildOfClass("UIStroke")
	if ns then
		ns.Enabled = false
	end
	local sr = h.row(l, 3, if phone then G.statCard.height + 0.09 else G.statCard.height)
	sr.Name = "Stats"
	local panel: Instance = if h.card then h.card(sr) else sr
	for n, stat in G.stats do
		statBar(h, panel, n, #G.stats, stat, g, cur)
	end
	local r = h.row(l, 10, 0.16)
	local label, color = Ui.price(g.price), Theme.tiers.Common
	if st == "held" then
		label, color = "Holding", Theme.go
	elseif st == "owned" then
		label, color = "Equip", Theme.info
	elseif st == "next" then
		label = if g.price > 0 then Ui.price(g.price) else "Get it"
		color = if v.coins >= g.price then Theme.coin else Theme.tiers.Common
	end
	local b = h.button(r, color, label, 0, 1, function()
		if st == "owned" then
			State.send("EquipGun", i)
		elseif st == "next" then
			State.send("BuyGun", i) -- the server checks the coins, the order and the rebirth
		elseif st ~= "held" then
			State.local_("notYet", { reason = if g.rebirths > (v.rebirths or 0) then `Needs Rebirth {g.rebirths}` else "Buy the one before first" })
		end
	end)
	b.root.Name = "Action"
	if (st == "next" or st == "locked") and g.price > 0 and h.priceTag then
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
	gloves = { { 0.14, 0.3, 0.3, 0.44, 0.4 }, { 0.08, 0.42, 0.1, 0.18, 0.5 }, { 0.56, 0.3, 0.3, 0.44, 0.4 }, { 0.82, 0.42, 0.1, 0.18, 0.5 } },
	skates = { { 0.14, 0.2, 0.26, 0.4, 0.25 }, { 0.14, 0.56, 0.32, 0.12, 0.5 }, { 0.1, 0.74, 0.38, 0.05, 0.5 }, { 0.56, 0.2, 0.26, 0.4, 0.25 }, { 0.56, 0.56, 0.32, 0.12, 0.5 }, { 0.52, 0.74, 0.38, 0.05, 0.5 } },
	pack = { { 0.22, 0.24, 0.56, 0.6, 0.2 }, { 0.32, 0.14, 0.36, 0.14, 0.5 }, { 0.34, 0.4, 0.32, 0.28, 0.15 } }, -- Frost Pack until its painted icon exists
	suit = { { 0.34, 0.12, 0.32, 0.22, 0.5 }, { 0.28, 0.32, 0.44, 0.38, 0.2 }, { 0.3, 0.66, 0.16, 0.24, 0.3 }, { 0.54, 0.66, 0.16, 0.24, 0.3 } },
}

local function gear(h: Helpers, body: Frame, v: State.View, o: any)
	-- a scrolling list sizes rows by shape (width / height), never a share of its own height. Slow Gel's card
	-- is gone (owner 2026-11-17).
	local l = h.list(body, true)
	-- the always-on gear (Config.gear, levels since 2026-11-17): one card each, the cheapest level you can
	-- afford is the focal point (it gets the selection)
	local focus = true
	local cheapest: string? = nil
	local cheapestPrice = math.huge
	for _, item in Config.gear do
		local lv = me:GetAttribute("GearLv_" .. item.key)
		local p = Config.gearPrice(item.key, if typeof(lv) == "number" then lv else 0)
		if p and p <= v.coins and p < cheapestPrice then
			cheapest, cheapestPrice = item.key, p
		end
	end
	for i, item in Config.gear do
		local lvAttr = me:GetAttribute("GearLv_" .. item.key)
		local lv: number = if typeof(lvAttr) == "number" then lvAttr else 0
		local mine = lv > 0
		local price = Config.gearPrice(item.key, lv)
		local row = h.row(l, i, 0, Config.ui.gearCardAspect)
		row.Name = "Gear_" .. item.key
		local f: Instance = if h.card then h.card(row) else row
		-- its silhouette (UI shapes) until the painted icons exist
		local slot = Instance.new("Frame")
		slot.Name = "Picture"
		slot.BackgroundColor3 = if mine then Theme.go else Theme.snowFar
		slot.Position = UDim2.fromScale(0.03, 0.1)
		slot.Size = UDim2.fromScale(0.16, 0.8)
		local a = Instance.new("UIAspectRatioConstraint")
		a.AspectRatio = 1
		a.Parent = slot
		Ui.corner(slot)
		Ui.stroke(slot)
		local art = Config.gearIcons[item.key]
		if art then
			-- the painted gear (owner 2026-11-15), a little bigger than its slot so it pops out of it
			local img = Ui.image(slot, art, UDim2.fromScale(1.2, 1.2), UDim2.fromScale(-0.1, -0.12))
			img.ZIndex = 2
		end
		for _, s in if art then {} else SHAPES[item.shape] or {} do
			local p = Instance.new("Frame")
			p.BackgroundColor3 = if mine then Theme.white else Theme.ink
			p.BackgroundTransparency = 0.15
			p.Position = UDim2.fromScale(s[1], s[2])
			p.Size = UDim2.fromScale(s[3], s[4])
			Ui.corner(p, s[5])
			p.Parent = slot
		end
		slot.Parent = f
		local nm = h.text(f, `{item.name}  Lv {lv}`, 0.2, 0.5)
		textRole(h, nm, "body")
		nm.Size = UDim2.fromScale(0.5, 0.45)
		nm.Position = UDim2.fromScale(0.2, 0.06)
		-- what it does now, and what the next level brings
		local now = if mine then Config.gearText(item.key, lv) else "Not owned yet"
		local wt = h.text(f, if price then `{now}  >  {Config.gearText(item.key, lv + 1)}` else `{now}  (max)`, 0.2, 0.5, Theme.infoDeep)
		textRole(h, wt, "small")
		wt.Size = UDim2.fromScale(0.5, 0.38)
		wt.Position = UDim2.fromScale(0.2, 0.52)
		local afford = price ~= nil and v.coins >= price
		local gb = h.button(f, if not price then Theme.go elseif afford then Theme.coin else Theme.tiers.Common,
			if price then Ui.price(price) else "Max", 0.72, 0.26, function()
				if price then
					State.send("BuyGear", item.key) -- the server checks the level, the coins and the booth
				end
			end)
		gb.root.Name = "Buy_" .. item.key
		if i == 1 then
			o.first = gb.face -- nothing affordable: the first card has the selection
		end
		if price and h.priceTag then
			h.priceTag(gb)
		end
		if cheapest == item.key and focus then
			focus = false
			o.first = gb.face
		end
	end
end

function EquipmentPopup.fill(o: any, v: State.View, h: Helpers)
	o.data = if typeof(o.data) == "table" then o.data else { tab = "guns" }
	local body: Frame = o.body
	-- the tabs
	local tabs = Instance.new("Frame")
	tabs.Name = "Tabs"
	tabs.BackgroundTransparency = 1
	-- device QA 2026-11-13: 0.12 made 20 px tall tabs on a phone; a phone gets 0.2
	local tabsH = if Screen.deviceClass() == "phone" then 0.2 else 0.15
	tabs.Size = UDim2.fromScale(1, tabsH)
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
	content.Position = UDim2.fromScale(0, tabsH + 0.02)
	content.Size = UDim2.fromScale(1, 0.98 - tabsH)
	content.Parent = body
	if o.data.tab == "gear" then
		gear(h, content, v, o)
		return
	end
	o.data.pick = o.data.pick or math.min(best() + 1, #G.list)
	-- every gun at once as tiles, two to a row (no scrolling to find the next one). On a phone that made
	-- 32 px tiles with 8 px words (device QA 2026-11-13): there the grid scrolls and each tile keeps a
	-- readable shape (G.phoneTileAspect, width / height)
	local phone = Screen.deviceClass() == "phone"
	local left: GuiObject
	if phone then
		local sf = Instance.new("ScrollingFrame")
		sf.BackgroundTransparency = 1
		sf.BorderSizePixel = 0
		sf.ScrollBarThickness = 6
		sf.ScrollBarImageColor3 = Theme.ink
		sf.CanvasSize = UDim2.fromScale(0, 0)
		sf.AutomaticCanvasSize = Enum.AutomaticSize.Y
		sf.ScrollingDirection = Enum.ScrollingDirection.Y
		left = sf
	else
		left = Instance.new("Frame")
		left.BackgroundTransparency = 1
	end
	left.Name = "Guns"
	left.Size = UDim2.fromScale(0.56, 1)
	left.Parent = content
	local cols = G.gridColumns
	local rows = math.ceil(#G.list / cols)
	local grid = Instance.new("UIGridLayout")
	local gap = G.gridGap
	if phone then
		-- pixel cells from the window's width (a scrolling canvas can't size cells by its own height)
		local function fit()
			local w = left.AbsoluteSize.X - 10
			local gpx = math.floor(w * gap)
			local cw = math.floor((w - gpx * (cols - 1)) / cols)
			grid.CellSize = UDim2.fromOffset(cw, math.floor(cw / G.phoneTileAspect))
			grid.CellPadding = UDim2.fromOffset(gpx, gpx)
		end
		left:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
		fit()
	else
		grid.CellSize = UDim2.fromScale((1 - gap * (cols - 1)) / cols, (1 - gap * (rows - 1)) / rows)
		grid.CellPadding = UDim2.fromScale(gap, gap)
	end
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = left
	for i = 1, #G.list do
		gunTile(h, left, i, v, o)
	end
	local right = Instance.new("Frame")
	right.Name = "Card"
	right.BackgroundTransparency = 1
	right.Position = UDim2.fromScale(0.59, 0)
	right.Size = UDim2.fromScale(0.41, 1)
	right.Parent = content
	gunCard(h, right, o.data.pick, v, o)
end

-- the gun in a window, for the "you can now buy" card (UnlockAlert)
EquipmentPopup.gunView = gunView

return EquipmentPopup
