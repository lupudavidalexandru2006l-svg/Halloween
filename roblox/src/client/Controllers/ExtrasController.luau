--!nonstrict
-- ExtrasController (owner 2026-11-19, "bring every score to 10"): the client side of ExtrasService and TradeService.
--   left column: Chest (milestone chest, fills as you earn), Skins (ray skins), Players (trade / mute / block)
--   the Freeze Streak chip and its tier pops, reward toasts, "Almost there!" nudges, the trade window.
-- Buttons only ask the server (remotes "Extras" / "Trade"); what shows comes from the server's view (v.extras).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local StarterGui = game:GetService("StarterGui")
local Config = require(ReplicatedStorage.Shared.Config)
local Theme = require(ReplicatedStorage.Shared.Theme)
local PetDefs = require(ReplicatedStorage.Shared.PetDefs)
local Ui = require(script.Parent.Parent.Lib.Ui)
local State = require(script.Parent.State)
local SoundController = require(script.Parent.SoundController)
local SettingsController = require(script.Parent.SettingsController)
local Screen = require(script.Parent.Screen)

local ExtrasController = {}
local me = Players.LocalPlayer

local gui: ScreenGui
local column: Frame
local chestBtn
local chestBar: Frame
local chestLabel: TextLabel
local streakChip: Frame
local streakText: TextLabel
local toastHolder: Frame
local openPanel: Frame? = nil
local openName: string? = nil
local trade: any = nil -- the last tradeState
local tradeFrame: Frame? = nil

local function reduced(): boolean
	return SettingsController.get("reducedMotion") == true
end

local function ex(): any
	return State.view and (State.view :: any).extras
end

-- ---------- small builders ----------
local function square(parent: Instance, name: string, sizeY: number): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundTransparency = 1
	f.SizeConstraint = Enum.SizeConstraint.RelativeYY
	f.Size = UDim2.fromScale(sizeY, sizeY)
	f.Parent = parent
	return f
end

local function textSize(t: TextLabel, maxPx: number)
	t.TextScaled = true
	local c = Instance.new("UITextSizeConstraint")
	c.MaxTextSize = maxPx
	c.MinTextSize = 8
	c.Parent = t
end

-- a round Chunky Pop button with a painted icon and a short word under it
local function roundButton(name: string, color: Color3, icon: string, word: string, onPress: () -> ())
	local holder = square(column, name, 1)
	holder.Size = UDim2.fromScale(1, 1)
	holder.SizeConstraint = Enum.SizeConstraint.RelativeXX
	local b = Ui.block(holder, "Button", color, "", function()
		SoundController.play("click")
		onPress()
	end)
	b.root.Size = UDim2.fromScale(1, 1)
	Ui.roundBlock(b, 0.5)
	Ui.image(b.face, icon, UDim2.fromScale(0.66, 0.66), UDim2.fromScale(0.17, 0.08))
	local w = Ui.label(b.face, word, UDim2.fromScale(1.3, 0.34), UDim2.fromScale(-0.15, 0.7))
	textSize(w, 18)
	w.ZIndex = 3
	return { holder = holder, block = b, word = w }
end

-- owner 2026-11-20: the wide green bar mid-screen ("Day 2: +1 Super Freeze") looked bad. Every toast now goes
-- through the HUD's own small alert toasts under the top buttons (UI Rules: alerts are small toasts).
-- HudController is required lazily: it requires this module back.
local function toast(s: string, color: Color3?, seconds: number?)
	local ok = pcall(function()
		require(script.Parent.HudController).banner(s, color, seconds, nil, nil, true) -- rewards wait to be seen
	end)
	if ok then
		return
	end
	local f = Instance.new("Frame")
	f.Name = "Toast"
	f.BackgroundColor3 = color or Theme.info
	f.Size = UDim2.fromScale(1, 0.18)
	f.BorderSizePixel = 0
	Ui.corner(f, 0.5)
	Ui.stroke(f)
	local t = Ui.label(f, s, UDim2.fromScale(0.94, 0.76), UDim2.fromScale(0.03, 0.12))
	textSize(t, 24)
	t.RichText = true
	local sc = Instance.new("UIScale")
	sc.Scale = if reduced() then 1 else 0.6
	sc.Parent = f
	f.Parent = toastHolder
	if not reduced() then
		TweenService:Create(sc, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end
	task.delay(seconds or 3, function()
		if f.Parent then
			TweenService:Create(sc, TweenInfo.new(0.2), { Scale = 0.01 }):Play()
			task.wait(0.22)
			f:Destroy()
		end
	end)
end
ExtrasController.toast = toast

-- a big word in the middle of the screen (streak tiers, a new skin)
local function bigPop(s: string, color: Color3, sub: string?)
	local f = Instance.new("Frame")
	f.Name = "BigPop"
	f.BackgroundTransparency = 1
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromScale(0.5, 0.36)
	f.Size = UDim2.fromScale(0.7, 0.2)
	f.Parent = gui
	local t = Ui.label(f, s, UDim2.fromScale(1, 0.62), UDim2.fromScale(0, 0))
	t.TextColor3 = color
	textSize(t, 72)
	if sub then
		local st = Ui.label(f, sub, UDim2.fromScale(1, 0.32), UDim2.fromScale(0, 0.64))
		textSize(st, 30)
	end
	local sc = Instance.new("UIScale")
	sc.Parent = f
	if not reduced() then
		sc.Scale = 0.2
		TweenService:Create(sc, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		local r = Instance.new("UIGradient")
		r.Color = ColorSequence.new(Color3.new(1, 1, 1), color)
		r.Rotation = 90
		r.Parent = t
	end
	task.delay(1.8, function()
		TweenService:Create(sc, TweenInfo.new(0.25), { Scale = 0.01 }):Play()
		task.wait(0.3)
		f:Destroy()
	end)
end

-- ---------- panels (my own menus: Skins, Players, Trade) ----------
local function closePanel()
	if openPanel then
		openPanel:Destroy()
	end
	local wasVisit = openName == "visit"
	openPanel, openName = nil, nil
	if not wasVisit then -- a visit opens over the leaderboard popup, which is still open underneath
		State.send("SetMenuOpen", false)
		Screen.setPopupOpen(false) -- the top buttons and goal pill come back
	end
end

local function panel(name: string, title: string, color: Color3): Frame
	closePanel()
	local shade = Instance.new("TextButton")
	shade.Name = "Shade_" .. name
	shade.Text = ""
	shade.AutoButtonColor = false
	shade.BackgroundColor3 = Color3.new(0, 0, 0)
	shade.BackgroundTransparency = 0.45
	-- this gui keeps the top-bar inset, so the shade reaches up over it too (QA 2026-11-23 PT-05b)
	local inset = game:GetService("GuiService"):GetGuiInset().Y
	shade.Position = UDim2.fromOffset(0, -inset)
	shade.Size = UDim2.new(1, 0, 1, inset)
	shade.ZIndex = 20
	shade.Parent = gui
	shade.Activated:Connect(closePanel)
	local p = Instance.new("Frame")
	p.Name = "Panel"
	p.AnchorPoint = Vector2.new(0.5, 0.5)
	p.Position = UDim2.fromScale(0.5, 0.53)
	p.Size = UDim2.fromScale(0.92, 0.82)
	-- QA PT-05: the same frame as every other popup: a pale tint of the menu colour, the title on a
	-- full-width ribbon inside the top, the X on the ribbon's right
	p.BackgroundColor3 = color:Lerp(Theme.white, Config.ui.panelTint)
	p.ZIndex = 21
	Ui.corner(p)
	Ui.stroke(p)
	local ar = Instance.new("UIAspectRatioConstraint")
	ar.AspectRatio = 1.45
	ar.Parent = p
	p.Parent = shade
	local sink = Instance.new("TextButton") -- clicks on the panel don't reach the shade
	sink.Text = ""
	sink.BackgroundTransparency = 1
	sink.Size = UDim2.fromScale(1, 1)
	sink.ZIndex = 21
	sink.Parent = p
	local head = Ui.block(p, "Header", color, title)
	local hh = Config.ui.headerHeight
	head.root.Position = UDim2.fromScale(0.02, 0.025)
	head.root.Size = UDim2.fromScale(0.96, hh)
	textSize(head.text, 34)
	local x = Ui.block(p, "Close", Theme.no, "X", function()
		SoundController.play("click")
		closePanel()
	end)
	x.root.AnchorPoint = Vector2.new(1, 0)
	x.root.Position = UDim2.fromScale(0.975, 0.035)
	x.root.Size = UDim2.fromScale(0.2, hh * 0.8)
	local xa = Instance.new("UIAspectRatioConstraint")
	xa.AspectRatio = 1.15
	xa.Parent = x.root
	textSize(x.text, 30)
	-- phone: the X face is ~30 px at 844x390, so an invisible tap area keeps it at minTouchPx (like PopupController's X; QA 2026-11-20)
	local hit = Instance.new("TextButton")
	hit.Name = "Hit"
	hit.Text = ""
	hit.BackgroundTransparency = 1
	hit.Selectable = false
	hit.AnchorPoint = Vector2.new(0.5, 0.5)
	hit.Position = UDim2.fromScale(0.5, 0.5)
	hit.Parent = x.root
	local function fitHit()
		local s = x.root.AbsoluteSize
		local m = Config.ui.minTouchPx
		hit.Size = UDim2.fromScale(math.max(1, m / math.max(1, s.X)), math.max(1, m / math.max(1, s.Y)))
	end
	x.root:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitHit)
	fitHit()
	hit.Activated:Connect(function()
		SoundController.play("click")
		closePanel()
	end)
	local body = Instance.new("Frame")
	body.Name = "Body"
	body.BackgroundTransparency = 1
	body.Position = UDim2.fromScale(0.03, 0.05 + hh)
	body.Size = UDim2.fromScale(0.94, 0.93 - hh)
	body.ZIndex = 22
	body.Parent = p
	for _, d in p:GetDescendants() do
		if d:IsA("GuiObject") and d.ZIndex < 22 then
			d.ZIndex = 22
		end
	end
	local sc = Instance.new("UIScale")
	sc.Parent = p
	if not reduced() then
		sc.Scale = 0.7
		TweenService:Create(sc, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end
	openPanel = shade :: any
	openName = name
	State.send("SetMenuOpen", true)
	Screen.setPopupOpen(true) -- QA PT-05: the top buttons hide like they do for every other popup
	return body
end

-- everything made inside a panel's body draws above it
local function lift(root: Instance)
	for _, d in root:GetDescendants() do
		if d:IsA("GuiObject") then
			d.ZIndex = math.max(d.ZIndex, 23)
		end
	end
end

local function scroller(parent: Instance, cols: number, cellAspect: number): ScrollingFrame
	local sf = Instance.new("ScrollingFrame")
	sf.BackgroundTransparency = 1
	sf.Size = UDim2.fromScale(1, 1)
	sf.CanvasSize = UDim2.new()
	sf.AutomaticCanvasSize = Enum.AutomaticSize.Y
	sf.ScrollBarThickness = 8
	sf.ScrollBarImageColor3 = Theme.ink
	sf.BorderSizePixel = 0
	sf.Parent = parent
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 6)
	pad.PaddingLeft = UDim.new(0, 6)
	pad.PaddingRight = UDim.new(0, 14)
	pad.PaddingBottom = UDim.new(0, 6)
	pad.Parent = sf
	local grid = Instance.new("UIGridLayout")
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.CellPadding = UDim2.fromScale(0.02, 0)
	local function fit()
		local w = sf.AbsoluteSize.X - 20
		local cw = (w - w * 0.02 * (cols - 1)) / cols
		grid.CellSize = UDim2.fromOffset(cw, cw / cellAspect)
		grid.CellPadding = UDim2.fromOffset(w * 0.02, w * 0.02)
	end
	sf:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	grid.Parent = sf
	task.defer(fit)
	return sf
end

local function card(parent: Instance, order: number, color: Color3?): Frame
	local c = Instance.new("Frame")
	c.Name = "Card" .. order
	c.LayoutOrder = order
	c.BackgroundColor3 = color or Theme.white
	c.BorderSizePixel = 0
	Ui.corner(c)
	Ui.stroke(c, Config.ui.cardStroke)
	c.Parent = parent
	return c
end

local function ink(parent: Instance, s: string, x: number, y: number, w: number, h: number, maxPx: number, color: Color3?): TextLabel
	local t = Ui.inkLabel(parent, s, UDim2.fromScale(w, h), UDim2.fromScale(x, y))
	if color then
		t.TextColor3 = color
	end
	textSize(t, maxPx)
	return t
end

local function smallButton(parent: Instance, color: Color3, s: string, x: number, y: number, w: number, h: number, onPress: () -> ()): any
	local b = Ui.block(parent, s, color, s, function()
		SoundController.play("click")
		onPress()
	end)
	b.root.Position = UDim2.fromScale(x, y)
	b.root.Size = UDim2.fromScale(w, h)
	textSize(b.text, 22)
	return b
end

-- a beam swatch: the skin's core -> glow -> spark as a glowing bar
local function swatch(parent: Instance, s: Config.RaySkin, x: number, y: number, w: number, h: number)
	local f = Instance.new("Frame")
	f.Name = "Swatch"
	f.Position = UDim2.fromScale(x, y)
	f.Size = UDim2.fromScale(w, h)
	f.BackgroundColor3 = Color3.new(1, 1, 1)
	f.BorderSizePixel = 0
	Ui.corner(f, 0.5)
	Ui.stroke(f, Config.ui.cardStroke)
	local g = Instance.new("UIGradient")
	if s.rainbow then
		g.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromHex("ff5f7a")), ColorSequenceKeypoint.new(0.25, Color3.fromHex("ffd34a")),
			ColorSequenceKeypoint.new(0.5, Color3.fromHex("5dffb0")), ColorSequenceKeypoint.new(0.75, Color3.fromHex("4fb8ff")),
			ColorSequenceKeypoint.new(1, Color3.fromHex("c88bff")),
		})
	else
		g.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, s.glow), ColorSequenceKeypoint.new(0.5, s.core), ColorSequenceKeypoint.new(1, s.spark:Lerp(s.glow, 0.4)) })
	end
	g.Parent = f
	if not reduced() then
		TweenService:Create(g, TweenInfo.new(1.6, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1, true), { Offset = Vector2.new(0.25, 0) }):Play()
	end
	f.Parent = parent
	return f
end

-- ---------- Skins ----------
local function openSkins()
	local e = ex()
	if not e then
		return
	end
	local body = panel("skins", "Ray Skins", Color3.fromHex("6a5cff"))
	local top = ink(body, "Your beam's colour, for everyone to see. Looks only: every skin freezes the same.", 0, 0, 1, 0.08, 20, Theme.infoDeep)
	top.TextXAlignment = Enum.TextXAlignment.Center
	local holder = Instance.new("Frame")
	holder.BackgroundTransparency = 1
	holder.Position = UDim2.fromScale(0, 0.1)
	holder.Size = UDim2.fromScale(1, 0.9)
	holder.Parent = body
	local sf = scroller(holder, 3, 1.25)
	local byId = {}
	for _, s in e.skins do
		byId[s.id] = s
	end
	for i, s in Config.raySkins do
		local st = byId[s.id] or { owned = false }
		local on = e.skin == s.id
		local c = card(sf, i, if on then Theme.go:Lerp(Theme.white, 0.75) elseif st.owned then Theme.white else Theme.slot:Lerp(Theme.white, 0.4))
		swatch(c, s, 0.08, 0.1, 0.84, 0.2)
		ink(c, s.name, 0.04, 0.34, 0.92, 0.2, 26)
		if on then
			ink(c, "Equipped", 0.04, 0.6, 0.92, 0.26, 22, Theme.go)
		elseif st.owned then
			smallButton(c, Theme.go, "Equip", 0.2, 0.58, 0.6, 0.32, function()
				State.send("Extras", "skin", s.id)
			end)
		else
			local how = ink(c, s.how, 0.04, 0.55, 0.92, if st.progress then 0.22 else 0.38, 16, Theme.infoDeep)
			how.TextWrapped = true
			if st.progress then
				local track = Instance.new("Frame")
				track.BackgroundColor3 = Theme.white
				track.Position = UDim2.fromScale(0.1, 0.8)
				track.Size = UDim2.fromScale(0.8, 0.12)
				Ui.corner(track, 0.5)
				Ui.stroke(track, Config.ui.cardStroke)
				track.Parent = c
				local fill = Instance.new("Frame")
				fill.BackgroundColor3 = s.glow
				fill.Size = UDim2.fromScale(math.clamp(st.progress, 0, 1), 1)
				fill.Visible = st.progress > 0
				Ui.corner(fill, 0.5)
				fill.Parent = track
			end
			local lock = Ui.image(c, Config.images.icons.lock, UDim2.fromScale(0.16, 0.2), UDim2.fromScale(0.8, 0.02))
			lock.ZIndex = 24
		end
	end
	lift(body)
end

-- ---------- Players: trade, mute, block ----------
local function openPlayers()
	local e = ex()
	local body = panel("players", "Trade", Theme.info)
	local note = ink(body, "Trade pets, or mute / block someone. To report: Roblox menu (top left) > Report.", 0, 0, 1, 0.08, 20, Theme.infoDeep)
	note.TextXAlignment = Enum.TextXAlignment.Center
	local holder = Instance.new("Frame")
	holder.BackgroundTransparency = 1
	holder.Position = UDim2.fromScale(0, 0.1)
	holder.Size = UDim2.fromScale(1, 0.9)
	holder.Parent = body
	local sf = scroller(holder, 1, 7.5)
	local mutedSet = {}
	for _, id in (if e then e.muted else {}) do
		mutedSet[id] = true
	end
	local n = 0
	for _, p in Players:GetPlayers() do
		if p == me then
			continue
		end
		n += 1
		local c = card(sf, n)
		local pic = Instance.new("ImageLabel")
		pic.BackgroundColor3 = Theme.info:Lerp(Theme.white, 0.7)
		pic.Position = UDim2.fromScale(0.01, 0.1)
		pic.Size = UDim2.fromScale(0.1, 0.8)
		local pa = Instance.new("UIAspectRatioConstraint")
		pa.Parent = pic
		Ui.corner(pic, 0.5)
		pic.Parent = c
		task.spawn(function()
			local ok, img = pcall(function()
				return Players:GetUserThumbnailAsync(p.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
			end)
			if ok and pic.Parent then
				pic.Image = img
			end
		end)
		local nm = ink(c, p.DisplayName, 0.12, 0.15, 0.36, 0.7, 26)
		nm.TextXAlignment = Enum.TextXAlignment.Left
		smallButton(c, Theme.go, "Trade", 0.5, 0.12, 0.16, 0.76, function()
			if e and e.tradeOk == false and not game:GetService("RunService"):IsStudio() then
				toast("Trading isn't available for your account here", Theme.no)
				return
			end
			State.send("Trade", "ask", p.UserId)
			closePanel()
		end)
		smallButton(c, if mutedSet[p.UserId] then Theme.coin else Theme.info, if mutedSet[p.UserId] then "Unmute" else "Mute", 0.67, 0.12, 0.16, 0.76, function()
			State.send("Extras", "mute", p.UserId)
			toast(if mutedSet[p.UserId] then `{p.DisplayName}'s chat is back` else `You won't see {p.DisplayName}'s chat`, Theme.info)
			closePanel()
		end)
		smallButton(c, Theme.no, "Block", 0.84, 0.12, 0.15, 0.76, function()
			pcall(function()
				StarterGui:SetCore("PromptBlockPlayer", p)
			end)
		end)
	end
	if n == 0 then
		local c = card(sf, 1)
		ink(c, "Nobody else is here yet. Invite a friend from the Daily menu!", 0.03, 0.15, 0.94, 0.7, 24)
	end
	lift(body)
end

ExtrasController.openPlayers = openPlayers -- the Trade tile (HudController)

-- ---------- Trade window ----------
local function petCell(parent: Instance, order: number, p: any, onPress: (() -> ())?, tint: Color3?)
	local c = card(parent, order, tint)
	local def = PetDefs.get(p.key)
	if def then
		Ui.petPicture(c, def, UDim2.fromScale(0.8, 0.56), UDim2.fromScale(0.1, 0.04))
	end
	local tierC = def and Theme.tiers[def.tier] or Theme.ink
	local nm = ink(c, if def then def.name else p.key, 0.03, 0.6, 0.94, 0.18, 16, tierC)
	nm.TextWrapped = true
	ink(c, `+{Ui.short(p.income)}/s` .. (if p.mut then ` {p.mut}` else ""), 0.03, 0.79, 0.94, 0.17, 14, Theme.infoDeep)
	if onPress then
		local hit = Instance.new("TextButton")
		hit.Text = ""
		hit.BackgroundTransparency = 1
		hit.Size = UDim2.fromScale(1, 1)
		hit.ZIndex = 30
		hit.Parent = c
		hit.Activated:Connect(function()
			SoundController.play("click")
			onPress()
		end)
	end
	return c
end

-- ---------- Visit a top-100 pan (owner 2026-11-20; opened from a leaderboard row's Visit) ----------
-- Read-only: who they are, their rebirths, pets frozen, best tier and ray skin, then the pets in their pan, best first.
local function openVisit(v: any)
	local body = panel("visit", `{v.name}'s Pan`, Theme.go)
	if v.failed then
		local c = ink(body, "Couldn't open this pan right now. Try again in a moment!", 0.05, 0.4, 0.9, 0.14, 28)
		c.TextWrapped = true
		lift(body)
		return
	end
	local top = Instance.new("Frame")
	top.Name = "Top"
	top.BackgroundColor3 = Theme.white
	top.Size = UDim2.fromScale(1, 0.2)
	Ui.corner(top)
	Ui.stroke(top, Config.ui.cardStroke)
	top.Parent = body
	local pic = Instance.new("ImageLabel")
	pic.Name = "Avatar"
	pic.BackgroundColor3 = Theme.ice
	pic.Position = UDim2.fromScale(0.012, 0.1)
	pic.Size = UDim2.fromScale(0.2, 0.8)
	pic.Image = `rbxthumb://type=AvatarHeadShot&id={v.userId}&w=150&h=150` -- Roblox draws it, no web call
	local pa = Instance.new("UIAspectRatioConstraint")
	pa.Parent = pic
	Ui.corner(pic, 0.5)
	Ui.stroke(pic, Config.ui.cardStroke)
	pic.Parent = top
	local facts = { `Rebirth {v.rebirths}`, `{Ui.commas(v.frozen)} pets frozen` }
	if v.best then
		table.insert(facts, `Best: {v.best}`)
	end
	local line1 = ink(top, table.concat(facts, "  ·  "), 0.12, 0.08, 0.86, 0.42, 26)
	line1.TextXAlignment = Enum.TextXAlignment.Left
	local skin = if v.skin then Config.raySkin(v.skin) else nil
	local line2 = ink(top, `{v.inPen} pets in the pan` .. (if skin then `  ·  Ray: {skin.name}` else ""), 0.12, 0.52, 0.6, 0.38, 22, Theme.infoDeep)
	line2.TextXAlignment = Enum.TextXAlignment.Left
	if skin then
		swatch(top, skin, 0.74, 0.58, 0.23, 0.26)
	end
	local holder = Instance.new("Frame")
	holder.Name = "Pets"
	holder.BackgroundTransparency = 1
	holder.Position = UDim2.fromScale(0, 0.23)
	holder.Size = UDim2.fromScale(1, 0.77)
	holder.Parent = body
	if #v.pets == 0 then
		ink(holder, "No pets in this pan right now.", 0.05, 0.35, 0.9, 0.16, 28)
	else
		local sf = scroller(holder, 5, 0.8)
		for i, p in v.pets do
			petCell(sf, i, p)
		end
	end
	lift(body)
end
ExtrasController.openVisit = openVisit

local function drawTrade()
	local t = trade
	if not t then
		return
	end
	local body = panel("trade", `Trade with {t.themName}`, Theme.go)
	tradeFrame = body
	local function side(x: number, title: string, list: { any }, value: number, mine: boolean, ready: boolean)
		local box = Instance.new("Frame")
		box.BackgroundColor3 = if ready then Theme.go:Lerp(Theme.white, 0.7) else Theme.white:Lerp(Theme.panel, 0.4)
		box.Position = UDim2.fromScale(x, 0)
		box.Size = UDim2.fromScale(0.485, 0.47)
		Ui.corner(box)
		Ui.stroke(box, Config.ui.cardStroke)
		box.Parent = body
		ink(box, title .. (if ready then "  ✓ Ready" else ""), 0.03, 0.02, 0.94, 0.14, 24, if ready then Theme.go else Theme.ink)
		ink(box, `{Ui.short(value)} coins/s`, 0.03, 0.85, 0.94, 0.13, 20, Theme.infoDeep)
		local grid = Instance.new("Frame")
		grid.BackgroundTransparency = 1
		grid.Position = UDim2.fromScale(0.03, 0.17)
		grid.Size = UDim2.fromScale(0.94, 0.66)
		grid.Parent = box
		local gl = Instance.new("UIGridLayout")
		gl.CellSize = UDim2.fromScale(0.235, 0.95)
		gl.CellPadding = UDim2.fromScale(0.018, 0)
		gl.SortOrder = Enum.SortOrder.LayoutOrder
		gl.Parent = grid
		for i = 1, Config.trade.maxPets do
			local p = list[i]
			if p then
				petCell(grid, i, p, if mine then function()
					State.send("Trade", "remove", p.id)
				end else nil)
			else
				local empty = card(grid, i, Theme.slot:Lerp(Theme.white, 0.6))
				ink(empty, "empty", 0.05, 0.4, 0.9, 0.2, 14, Theme.infoDeep)
			end
		end
	end
	side(0, "You give", t.mine, t.mineValue, true, t.ready)
	side(0.515, "You get", t.theirs, t.theirsValue, false, t.themReady)
	-- the warning: a big gap in value
	if t.unfair then
		local w = ink(body, if t.youGiveMore then "Careful: you give a lot more than you get!" else "Unfair for them: they give a lot more",
			0, 0.48, 1, 0.06, 22, Theme.no)
		w.TextXAlignment = Enum.TextXAlignment.Center
	end
	-- your pets to pick from (tap to put in)
	local pick = Instance.new("Frame")
	pick.BackgroundTransparency = 1
	pick.Position = UDim2.fromScale(0, 0.55)
	pick.Size = UDim2.fromScale(0.7, 0.45)
	pick.Parent = body
	ink(pick, "Tap your pets to put them in", 0, 0, 1, 0.12, 18, Theme.infoDeep)
	local ph = Instance.new("Frame")
	ph.BackgroundTransparency = 1
	ph.Position = UDim2.fromScale(0, 0.13)
	ph.Size = UDim2.fromScale(1, 0.87)
	ph.Parent = pick
	local sf = scroller(ph, 6, 0.8)
	local inTrade = {}
	for _, p in t.mine do
		inTrade[p.id] = true
	end
	local pets = if State.view then table.clone(State.view.pets) else {}
	table.sort(pets, function(a, b)
		return (a.income or 0) > (b.income or 0)
	end)
	local n = 0
	for _, p in pets do
		if not inTrade[p.id] and not p.thawM and n < 120 then
			n += 1
			petCell(sf, n, p, function()
				State.send("Trade", "add", p.id)
			end)
		end
	end
	-- the buttons
	local right = Instance.new("Frame")
	right.BackgroundTransparency = 1
	right.Position = UDim2.fromScale(0.72, 0.56)
	right.Size = UDim2.fromScale(0.28, 0.44)
	right.Parent = body
	local status = ink(right, "", 0, 0, 1, 0.24, 20)
	status.TextWrapped = true
	if t.confirmIn and t.confirmIn > 0 then
		status.Text = "Check both sides!"
		local left = t.confirmIn
		task.spawn(function()
			while left > 0 and status.Parent do
				status.Text = `Check both sides! {math.ceil(left)}`
				task.wait(0.2)
				left -= 0.2
			end
		end)
		smallButton(right, Theme.slot, "Wait...", 0.05, 0.28, 0.9, 0.3, function() end)
	elseif t.ready and t.themReady then
		status.Text = if t.accepted then `Waiting for {t.themName}...` else "Both ready. Accept?"
		if not t.accepted then
			local acc = smallButton(right, Theme.go, "Accept", 0.05, 0.28, 0.9, 0.3, function()
				State.send("Trade", "accept")
			end)
			local _ = acc
		end
	else
		status.Text = if t.ready then `Waiting for {t.themName}...` else "Put pets in, then Ready"
		smallButton(right, if t.ready then Theme.coin else Theme.go, if t.ready then "Not ready" else "Ready", 0.05, 0.28, 0.9, 0.3, function()
			State.send("Trade", "ready", not t.ready)
		end)
	end
	smallButton(right, Theme.no, "Cancel", 0.05, 0.66, 0.9, 0.28, function()
		State.send("Trade", "cancel")
	end)
	lift(body)
end

-- someone asks: a small card with Yes / No (never a full-screen pop-up)
local function askCard(data: any)
	local f = Instance.new("Frame")
	f.Name = "TradeAsk"
	f.AnchorPoint = Vector2.new(0.5, 0)
	f.Position = UDim2.fromScale(0.5, 0.2)
	f.Size = UDim2.fromScale(0.42, 0.13)
	f.BackgroundColor3 = Theme.panel
	Ui.corner(f)
	Ui.stroke(f)
	f.ZIndex = 15
	f.Parent = gui
	local ar = Instance.new("UIAspectRatioConstraint")
	ar.AspectRatio = 4.2
	ar.Parent = f
	ink(f, `{data.name} wants to trade!`, 0.04, 0.06, 0.92, 0.4, 26)
	local done = false
	local function answer(yes: boolean)
		if done then
			return
		end
		done = true
		State.send("Trade", "answer", yes)
		f:Destroy()
	end
	smallButton(f, Theme.go, "Trade", 0.12, 0.5, 0.34, 0.42, function()
		answer(true)
	end)
	smallButton(f, Theme.no, "No thanks", 0.54, 0.5, 0.34, 0.42, function()
		answer(false)
	end)
	SoundController.play("friend")
	task.delay(data.seconds or 20, function()
		if not done and f.Parent then
			done = true
			f:Destroy()
		end
	end)
end

-- ---------- HUD: chest, streak ----------
local shownStreak = 0
local function refreshHud()
	local e = ex()
	if not e then
		return
	end
	-- the chest
	-- owner 2026-11-21: "remove the ice chest": the milestone chest is off (button and nudges)
	local c = if Config.milestoneChestOn then e.chest else nil
	if c and c.index then
		-- the chest waits until the tutorial is over (the first minutes stay calm)
		chestBtn.holder.Visible = not ((State.view :: any).tutorial and not (State.view :: any).tutorial.done)
		chestBar.Size = UDim2.fromScale(math.clamp(c.progress, 0, 1), 1)
		local ready = c.progress >= 1
		chestLabel.Text = if ready then "OPEN!" else `{math.floor(c.progress * 100)}%`
		chestBtn.block.face.BackgroundColor3 = if ready then Theme.go else Theme.gift
		local sc = chestBtn.holder:FindFirstChild("Bounce") :: UIScale?
		if ready and not sc and not reduced() then
			local s = Instance.new("UIScale")
			s.Name = "Bounce"
			s.Parent = chestBtn.holder
			TweenService:Create(s, TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Scale = 1.12 }):Play()
		elseif not ready and sc then
			sc:Destroy()
		end
	else
		chestBtn.holder.Visible = false
	end
	-- the streak chip
	local n = e.streak or 0
	if n >= Config.streak.showFrom then
		streakChip.Visible = true
		local tier = Config.streakTier(n)
		streakChip.BackgroundColor3 = if tier then tier.color else Theme.info
		streakText.Text = `x{n} STREAK  <font color="#fff3a0">+{math.round(Config.streakBonus(n) * 100)}% coins</font>`
		if n > shownStreak and not reduced() then
			local s = streakChip:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
			s.Parent = streakChip
			s.Scale = 1.25
			TweenService:Create(s, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		end
	else
		streakChip.Visible = false
	end
	shownStreak = n
end

-- ---------- Almost there! ----------
local nudged: { [string]: boolean } = {}
local lastNudge = 0
local function nudge(key: string, s: string)
	if nudged[key] or os.clock() - lastNudge < Config.nudge.cooldown then
		return
	end
	nudged[key] = true
	lastNudge = os.clock()
	toast(`<b>Almost there!</b> {s}`, Theme.coin, Config.nudge.seconds)
	SoundController.play("tink")
end
local function checkNudges(v: any)
	-- first-time players: nothing extra on screen in their first minutes or during the tutorial (QA first 10 min)
	local e0 = v.extras
	if not e0 or (e0.playSeconds or 0) < Config.nudge.quietSeconds or (v.tutorial and not v.tutorial.done) then
		return
	end
	local at = Config.nudge.at
	for i, c in (if v.daily then v.daily.list else {}) do
		if not c.done and c.goal > 0 and c.have / c.goal >= at then
			nudge(`d{i}{c.text}{c.goal}`, `{Ui.price(c.goal - c.have)} more for your daily: ` .. (string.gsub(c.text, "{n}", Ui.short(c.goal))))
		end
	end
	local e = v.extras
	if e then
		for i, c in e.weekly.list do
			if not c.done and c.goal > 0 and c.have / c.goal >= at then
				nudge(`w{i}{c.text}{c.goal}`, `{Ui.price(c.goal - c.have)} more for a weekly quest`)
			end
		end
		if Config.milestoneChestOn and e.chest and e.chest.index and e.chest.progress >= at and e.chest.progress < 1 then
			nudge(`c{e.chest.index}{v.rebirths}`, `Your {e.chest.name} is {math.floor(e.chest.progress * 100)}% full`)
		end
	end
	local cost = Config.rebirthCost((v.rebirths or 0) + 1)
	if (v.rebirths or 0) < Config.rebirth.max and cost > 0 and v.coins / cost >= at and v.coins < cost then
		nudge(`r{v.rebirths}`, "You can almost Rebirth!")
	end
end

-- ---------- notices from the server ----------
local function money(n: number?): string
	return if n and n > 0 then `+{Ui.short(n)} coins` else ""
end
local function onNotify(kind: string, data: any)
	if kind == "streakTier" then
		local tier = Config.streakTier(data.n)
		bigPop(data.name, if tier then tier.color else Theme.info, `x{data.n} streak: +{math.round(data.bonus * 100)}% coins`)
		SoundController.play("reveal_rare")
	elseif kind == "streakLost" then
		local lead = if data.why == "melt" or data.why == nil then "Your cube melted" else "You lost your pet"
		toast(`{lead}: x{data.n} streak lost!`, Theme.no, 3)
	elseif kind == "skinUnlocked" then
		local s = Config.raySkin(data.id)
		if s then
			bigPop("NEW RAY SKIN!", s.glow, `{s.name}: equip it in Equipment > Skins`)
			SoundController.play("unlock")
		end
	elseif kind == "loginClaimed" then
		local parts = {}
		if data.coins and data.coins > 0 then table.insert(parts, money(data.coins)) end
		if data.superFreeze then table.insert(parts, `+{data.superFreeze} Super Freeze`) end
		if data.speed then table.insert(parts, `+{math.round(data.speed * 100)}% speed for 10 min`) end
		toast(`Day {data.day}: {table.concat(parts, ", ")}`, Theme.go, 3.5)
		SoundController.play("gift")
		if data.skin then
			onNotify("skinUnlocked", { id = data.skin })
		end
	elseif kind == "weeklyClaimed" then
		toast(`Weekly quest: {money(data.coins)}, +{data.superFreeze} Super Freeze` .. (if data.all then ". ALL DONE!" else ""), Theme.go, 3.5)
		SoundController.play("challenge")
		if data.skin then
			onNotify("skinUnlocked", { id = data.skin })
		end
	elseif kind == "chestOpened" then
		bigPop(string.upper(data.name) .. "!", Theme.coin, money(data.coins) .. (if data.superFreeze then `, +{data.superFreeze} Super Freeze` else "")
			.. (if data.speed then ", speed boost" else ""))
		SoundController.play("gift")
	elseif kind == "panVisit" then
		openVisit(data)
	elseif kind == "tradeAsk" then
		askCard(data)
	elseif kind == "tradeAsked" then
		toast(`Asked {data.name} to trade...`, Theme.info, 2.5)
	elseif kind == "tradeState" then
		trade = data
		drawTrade()
	elseif kind == "tradeClosed" then
		trade = nil
		if openName == "trade" then
			closePanel()
		end
		toast(data.why or "Trade closed", Theme.info, 3)
	elseif kind == "tradeDone" then
		trade = nil
		if openName == "trade" then
			closePanel()
		end
		bigPop("TRADE DONE!", Theme.go, `You got {data.got} pet{if data.got == 1 then "" else "s"} from {data.name}. They're in your Pets`)
		SoundController.play("unlock")
	end
end

function ExtrasController.Init() end

function ExtrasController.Start()
	gui = Instance.new("ScreenGui")
	gui.Name = "Extras"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets -- phones: clear of the notch and Roblox's top bar
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Global
	gui.DisplayOrder = 8
	gui.Parent = me:WaitForChild("PlayerGui")
	local X = Config.ui.extras
	column = Instance.new("Frame")
	column.Name = "Column"
	column.BackgroundTransparency = 1
	column.AnchorPoint = Vector2.new(1, 0.5)
	column.Position = UDim2.fromScale(X.columnX, X.columnY)
	column.SizeConstraint = Enum.SizeConstraint.RelativeYY
	column.Size = UDim2.fromScale(X.buttonSize, X.buttonSize * 3 + X.gap * 2)
	column.Parent = gui
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(X.gap / (X.buttonSize * 3 + X.gap * 2), 0)
	layout.Parent = column
	chestBtn = roundButton("Chest", Theme.gift, Config.images.icons.gift, "Chest", function()
		local e = ex()
		if e and e.chest and e.chest.index then
			if e.chest.progress >= 1 then
				State.send("Extras", "chest")
			else
				toast(`{e.chest.name}: {math.floor(e.chest.progress * 100)}% full. Earn coins to fill it!`, Theme.gift, 3)
			end
		end
	end)
	chestBtn.holder.LayoutOrder = 1
	local track = Instance.new("Frame")
	track.Name = "Track"
	track.BackgroundColor3 = Theme.white
	track.AnchorPoint = Vector2.new(1, 0.5) -- left of the button (the column hugs the right edge)
	track.Position = UDim2.fromScale(-0.08, 0.5)
	track.Size = UDim2.fromScale(0.9, 0.28)
	Ui.corner(track, 0.5)
	Ui.stroke(track)
	track.Parent = chestBtn.holder
	chestBar = Instance.new("Frame")
	chestBar.BackgroundColor3 = Theme.coin
	chestBar.Size = UDim2.fromScale(0, 1)
	Ui.corner(chestBar, 0.5)
	chestBar.Parent = track
	chestLabel = Ui.label(track, "", UDim2.fromScale(0.96, 0.9), UDim2.fromScale(0.02, 0.05))
	chestLabel.ZIndex = 3
	textSize(chestLabel, 18)
	-- owner 2026-11-19: Skins and Players buttons removed (skins moved to Equipment > Skins; the players panel opens
	-- from the Trade tile next to Shop, HudController). openSkins stays for a possible return.
	local _ = openSkins
	-- the streak chip
	streakChip = Instance.new("Frame")
	streakChip.Name = "Streak"
	streakChip.AnchorPoint = Vector2.new(1, 0)
	streakChip.Position = UDim2.fromScale(X.streakX, X.streakY)
	streakChip.SizeConstraint = Enum.SizeConstraint.RelativeYY
	streakChip.Size = UDim2.fromScale(X.streakW, X.streakH)
	streakChip.BackgroundColor3 = Theme.info
	streakChip.Visible = false
	Ui.corner(streakChip, 0.5)
	Ui.stroke(streakChip)
	streakChip.Parent = gui
	Ui.image(streakChip, Config.images.icons.ray, UDim2.fromScale(0.16, 0.9), UDim2.fromScale(0.02, 0.05))
	streakText = Ui.label(streakChip, "", UDim2.fromScale(0.8, 0.78), UDim2.fromScale(0.18, 0.11))
	streakText.RichText = true
	textSize(streakText, 26)
	-- toasts
	toastHolder = Instance.new("Frame")
	toastHolder.Name = "Toasts"
	toastHolder.BackgroundTransparency = 1
	toastHolder.AnchorPoint = Vector2.new(0.5, 0)
	toastHolder.Position = UDim2.fromScale(0.5, X.toastY)
	toastHolder.SizeConstraint = Enum.SizeConstraint.RelativeYY
	toastHolder.Size = UDim2.fromScale(0.8, 0.4)
	toastHolder.Parent = gui
	local tl = Instance.new("UIListLayout")
	tl.SortOrder = Enum.SortOrder.LayoutOrder
	tl.Padding = UDim.new(0.02, 0)
	tl.HorizontalAlignment = Enum.HorizontalAlignment.Center
	tl.Parent = toastHolder
	-- sizes in pixels from the screen's short side, never under the touch minimum (UI Rules: 44+ px on phones)
	local function fit()
		local cam = workspace.CurrentCamera
		if not cam then
			return
		end
		local short = math.min(cam.ViewportSize.X, cam.ViewportSize.Y)
		local b = math.max(short * X.buttonSize, Config.ui.minTouchPx + 4)
		local g = short * X.gap
		column.SizeConstraint = Enum.SizeConstraint.RelativeXY
		column.Size = UDim2.fromOffset(b, b * 3 + g * 2)
		layout.Padding = UDim.new(0, g)
		local h = math.max(short * X.streakH, 30)
		streakChip.SizeConstraint = Enum.SizeConstraint.RelativeXY
		streakChip.Size = UDim2.fromOffset(h * X.streakW / X.streakH, h)
		toastHolder.SizeConstraint = Enum.SizeConstraint.RelativeXY
		toastHolder.Size = UDim2.fromOffset(math.min(cam.ViewportSize.X * 0.9, short * 0.9), math.max(short * 0.4, 160))
	end
	fit()
	if workspace.CurrentCamera then
		workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
	end
	State.Notify:Connect(onNotify)
	State.Changed:Connect(function(v)
		refreshHud()
		checkNudges(v)
		-- an open Skins / Players panel redraws with fresh data
		if openName == "skins" then
			local key = `{ex().skin}`
			if ExtrasController._skinKey ~= key then
				ExtrasController._skinKey = key
				openSkins()
			end
		end
	end)
	if State.view then
		refreshHud()
	end
end

return ExtrasController
