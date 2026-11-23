--!strict
-- Screen: the only module that places HUD pieces (UI Rules, Code Rules 1). Others build contents and
-- register them here. Sizes are fractions of the screen's short side, turned into Scale (no Offset)
-- each time the screen size, the device or a piece changes. The ScreenGuis use the core-UI safe
-- insets, so nothing sits under Roblox's top bar; on touch the coins sit above the thumbstick.
-- HUD (5 at most): tile grid (left, centred), coins and Cold Power (bottom left, one block), the island
-- banner (top centre, only while it shows), the hotbar (bottom centre, Round 5) and the banner (only
-- while it shows).
-- The tutorial's goal pill sits top centre, for new players only, until the tutorial ends.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local InputController = require(script.Parent.InputController)

local Screen = {}
local U = Config.ui
local items: { [string]: GuiObject } = {}
local tileCount = 0

Screen.hud = nil :: ScreenGui?
Screen.popups = nil :: ScreenGui?
-- the alert toasts get their own layer just above the popups: in the HUD they were drawn under an open
-- popup, so on a phone a "not yet" answer ("Join the group first") was never seen (2-player phone test 2026-11-16)
Screen.alerts = nil :: ScreenGui?
-- the free strip of Roblox's top bar (between its own buttons): the top buttons live here
Screen.topbar = nil :: ScreenGui?
-- every HUD piece but the banner sits in this full-screen frame, so a shop can hide them together
-- (Config.ui.hideHudFor) while the banner still answers "Need 120 more"
local main: Frame? = nil
local menuHiddenEvent = Instance.new("BindableEvent")
Screen.menuHidden = false
Screen.MenuHiddenChanged = menuHiddenEvent.Event -- (hidden)
-- a show is playing (setHidden): the world prompts step aside too (PromptController)
local showHiddenEvent = Instance.new("BindableEvent")
Screen.showHidden = false
Screen.ShowHiddenChanged = showHiddenEvent.Event -- (hidden)

local function gui(name: string, order: number): ScreenGui
	local g = Instance.new("ScreenGui")
	g.Name = name
	g.ResetOnSpawn = false
	g.IgnoreGuiInset = false
	g.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	g.DisplayOrder = order
	g.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	g.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	return g
end

-- "phone" | "tablet" | "pc": popups and prompts use a UI scale per device class
function Screen.deviceClass(): string
	local cam = workspace.CurrentCamera
	local short = if cam then math.min(cam.ViewportSize.X, cam.ViewportSize.Y) else 720
	if InputController.device() == "touch" then
		return if short < 600 then "phone" else "tablet"
	end
	return "pc"
end

function Screen.layout()
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	-- sizes are shares of the SCREEN's short side; Scale is a share of the HUD layer, which is the
	-- screen minus Roblox's top bar (final QA 2026-11-03: on a phone the tiles came out 8.9%, not 10.5%)
	local short = math.min(cam.ViewportSize.X, cam.ViewportSize.Y)
	local layer = Screen.hud and Screen.hud.AbsoluteSize or cam.ViewportSize
	local w, h = math.max(1, layer.X), math.max(1, layer.Y)
	short = math.max(1, short)
	local function sx(f: number): number
		return f * short / w
	end
	local function sy(f: number): number
		return f * short / h
	end
	local touch = InputController.device() == "touch"
	local lift = if touch then U.touchLift else 0
	-- touch screens: tiles and hotbar slots never shrink under a thumb's size (mobile QA 2026-11-10: 40 px tiles on a phone)
	local tileSize = if touch then math.max(U.tileSize, U.minTouchPx / short) else U.tileSize
	local slotSize = if touch then math.max(Config.hotbar.size, U.hotbarMinPx / short) else Config.hotbar.size
	local coins = items.coins
	local coinsTop = 1
	-- Cold Power sits in the corner, the coins straight above it (both lifted over the thumbstick on touch)
	local power = items.power
	local powerH = if power then U.powerSize[2] else 0
	if power then
		power.AnchorPoint = Vector2.new(0, 1)
		power.Size = UDim2.fromScale(sx(U.powerSize[1]), sy(U.powerSize[2]))
		power.Position = UDim2.fromScale(sx(U.sideInset), 1 - sy(U.sideInset + lift))
	end
	if coins then
		coins.AnchorPoint = Vector2.new(0, 1)
		coins.Size = UDim2.fromScale(sx(U.coinsSize[1]), sy(U.coinsSize[2]))
		coins.Position = UDim2.fromScale(sx(U.sideInset), 1 - sy(U.sideInset + lift + powerH))
		coinsTop = 1 - sy(U.sideInset + lift + powerH + U.coinsSize[2])
	end
	-- the top buttons (TopButtons): at the very top, inside Roblox's top bar between its own buttons
	-- (owner 2026-11-13: "put this UI at the very top for every platform"). Where there is no top bar
	-- (consoles, or the top bar switched off) they fall back to the top centre of the HUD layer, with the
	-- island banner and the message banner under them. Gone while a popup or a shop is open, or while
	-- they don't want to show.
	local top = items.top
	local topH = 0
	if top then
		local TB = U.topButtons
		local ib = top:FindFirstChild("IslandBar") :: GuiObject?
		local under = if ib and ib.Visible then TB.under else 0 -- the bar shows only while training
		-- only the travel buttons make the row (owner 2026-11-18: "center them, they're off by much": the Cold Power
		-- quick-buy hangs under the row, it isn't a slot in it)
		local n = 0
		for _, b in TB.list do
			if not (b :: any).product then
				n += 1
			end
		end
		local want = top:GetAttribute("Want") == true and not Screen.popupOpen
		local bar = Screen.topbar
		local barSize = if bar then bar.AbsoluteSize else Vector2.zero
		if bar and GuiService.TopbarInset.Height > 0 and barSize.X > 0 and barSize.Y > 0 then
			-- in pixels first (the bar is a strip of the screen), then Scale of the bar
			local barW, barH = barSize.X, barSize.Y
			-- owner 2026-11-13: "make the equipment and pan buttons bigger": taller than the bar (TB.barFill), hanging
			-- from its top a little way down over the view (they were 76% of it, 44 px of 58)
			-- owner 2026-11-13: "on my friend's laptop it's too big": the bar is the same 58 px on every screen,
			-- so the height is also capped at a share of the screen's short side (TB.barShort), never under the
			-- old size (TB.barMin of the bar) or a thumb on touch
			local bh = math.min(barH * TB.barFill, short * TB.barShort)
			bh = math.max(bh, barH * TB.barMin, if touch then U.minTouchPx else 0)
			local bw = TB.size[1] * bh / TB.size[2]
			local gap = TB.gap * bh / TB.size[2]
			local rowW = bw * n + gap * (n - 1)
			if rowW > barW then
				bh *= barW / rowW
				rowW = barW
			end
			-- centred on the screen, slid sideways only if it would run into Roblox's own buttons
			local half = rowW / 2 / barW
			local cx = math.clamp((cam.ViewportSize.X / 2 - bar.AbsolutePosition.X) / barW, half, 1 - half)
			if top.Parent ~= bar then
				top.Parent = bar
			end
			top.Visible = want and not Screen.menuHidden and not Screen.menusLocked
			top.AnchorPoint = Vector2.new(0.5, 0)
			top.Size = UDim2.fromScale(rowW / barW, bh / barH)
			top.Position = UDim2.fromScale(cx, TB.barTop)
			-- the part hanging below the bar pushes the island banner and the message banner down with it
			-- (+ the next-island bar under the buttons, TB.under of their height)
			local overhang = barH * TB.barTop + bh - barH + bh * under
			if top.Visible and overhang > 0 then
				topH = overhang / short
			end
		else
			if top.Parent ~= main then
				top.Parent = main
			end
			local bh = if touch then math.max(TB.size[2], U.minTouchPx / short) else TB.size[2]
			local bw = TB.size[1] * bh / TB.size[2]
			top.Visible = want and not Screen.menusLocked
			top.AnchorPoint = Vector2.new(0.5, 0)
			top.Size = UDim2.fromScale(math.min(0.96, sx(bw * n + TB.gap * (n - 1) * bh / TB.size[2])), sy(bh))
			top.Position = UDim2.fromScale(0.5, sy(U.topInset))
			if top.Visible then
				topH = bh * (1 + under) + U.tileGap
			end
		end
	end
	-- the tutorial's goal pill (TutorialGoal): top centre under the top buttons, for new players only;
	-- everything below it at the top moves down by its height. Steps aside while a popup is open.
	local goal = items.goal
	if goal then
		local GU = U.tutorialGoal
		local size = if Screen.deviceClass() == "phone" then GU.phone else GU.wide
		goal.Visible = goal:GetAttribute("Want") == true and not Screen.popupOpen
		goal.AnchorPoint = Vector2.new(0.5, 0)
		goal.Size = UDim2.fromScale(math.min(0.92, sx(size[1])), sy(size[2]))
		goal.Position = UDim2.fromScale(0.5, sy(U.topInset + topH))
		if goal.Visible then
			topH += size[2] + U.tileGap
		end
	end
	-- the Cold Power gain banner (HudController, Config.ui.gainBanner): top centre under the top buttons while you gain
	local gain = items.gain
	if gain then
		local GB = U.gainBanner
		gain.AnchorPoint = Vector2.new(0.5, 0)
		gain.Size = UDim2.fromScale(math.min(0.8, sx(GB.size[1])), sy(GB.size[2]))
		gain.Position = UDim2.fromScale(0.5, sy(U.topInset + topH + GB.y))
		if gain.Visible then
			topH += GB.size[2] + GB.y + U.tileGap
		end
	end
	local IB = U.islandBanner
	local island = items.island
	if island then
		-- a fixed slot at the top centre; the strip inside it slides (HudController animates the inside only)
		island.AnchorPoint = Vector2.new(0.5, 0)
		island.Size = UDim2.fromScale(math.min(1, sx(IB.width)), sy(IB.height))
		island.Position = UDim2.fromScale(0.5, sy(U.topInset + topH))
	end
	local banner = items.banner
	if banner then
		-- the alerts (owner 2026-11-16: "put it under equipment and pan"): a stack of toasts right under the top
		-- buttons (and under the island banner while that shows, so they never overlap)
		local A = U.alerts
		banner.AnchorPoint = Vector2.new(0.5, 0)
		-- phones (2-player phone test 2026-11-16): taller toasts (28 px was too small to read) and narrower, so
		-- they sit between the menu tiles on the left and the clocks on the right instead of under the tiles
		local phone = Screen.deviceClass() == "phone"
		local k = if phone then A.phoneScale else 1
		local bw = if phone then A.phoneWidth else sx(A.size[1])
		local stackH = (A.stack * A.size[2] + (A.stack - 1) * A.gap) * k
		banner.Size = UDim2.fromScale(math.min(0.96, bw), sy(stackH))
		-- on a phone there's no room to stack them under the island banner (they ran down onto the coins and the
		-- hotbar): they stay under the top buttons and draw over the island banner instead
		local below = if island and island.Visible and not phone then IB.height + U.topInset else 0
		banner.Position = UDim2.fromScale(0.5, sy(U.topInset + topH + below))
		banner.ZIndex = 5
	end
	-- the clocks (night, Secret, event): bottom right, over the jump button on touch screens
	local clocks = items.clocks
	if clocks then
		local C = U.clocks
		local n = 3
		local ck = if Screen.deviceClass() == "phone" then C.phoneScale else 1 -- bigger on phones (24 px chips were too small)
		clocks.Visible = not Screen.menusLocked
		clocks.AnchorPoint = Vector2.new(1, 1)
		clocks.Size = UDim2.fromScale(sx(C.size[1] * ck), sy((C.size[2] * n + C.gap * (n - 1)) * ck))
		clocks.Position = UDim2.fromScale(1 - sx(U.sideInset), 1 - sy(U.sideInset + (if touch then U.stickClear else 0)))
	end
	-- the "you can now buy" card (UnlockAlert): top right, under the top buttons' row; bigger on a phone
	-- so its words stay readable
	local alert = items.alert
	if alert then
		local A = U.unlockAlert
		local k = if Screen.deviceClass() == "phone" then A.phoneScale else 1
		alert.AnchorPoint = Vector2.new(1, 0)
		alert.Size = UDim2.fromScale(math.min(0.6, sx(A.size[1] * k)), sy(A.size[2] * k))
		alert.Position = UDim2.fromScale(1 - sx(U.sideInset), sy(U.topInset + topH))
	end
	-- the hotbar: bottom centre, between the thumbstick and the jump button on touch screens
	local hotbar = items.hotbar
	if hotbar then
		-- a phone popup takes the whole height, so the hotbar would peek out from under it: it steps aside
		-- Locked: a cube is in your hands, so there's nothing to hold (GearController)
		hotbar.Visible = hotbar:GetAttribute("Locked") ~= true and not (Screen.popupOpen and Screen.deviceClass() == "phone")
		local H = Config.hotbar
		local n = math.max(1, (hotbar:GetAttribute("Slots") or 1) :: number)
		local k = slotSize / H.size -- the gap grows with the slot, so GearController's proportions still hold
		hotbar.AnchorPoint = Vector2.new(0.5, 1)
		hotbar.Size = UDim2.fromScale(sx((H.size * n + H.gap * (n - 1)) * k), sy(slotSize * 1.45))
		hotbar.Position = UDim2.fromScale(0.5, 1 - sy(H.bottomInset))
	end
	local tiles = items.tiles
	if tiles then
		tiles.Visible = not Screen.menusLocked
		-- owner 2026-11-15: a "Wide" tile (Shop) takes a whole row of two on top, the rest pair up under it
		local list: { GuiObject } = {}
		for _, c in tiles:GetChildren() do
			if c:IsA("GuiObject") then
				table.insert(list, c)
			end
		end
		table.sort(list, function(a, b)
			return a.LayoutOrder < b.LayoutOrder
		end)
		local slots: { { obj: GuiObject, row: number, col: number, span: number } } = {}
		local row, col = 0, 0
		for _, c in list do
			if c:GetAttribute("Wide") == true then
				if col > 0 then
					row, col = row + 1, 0
				end
				table.insert(slots, { obj = c, row = row, col = 0, span = 2 })
				row += 1
			else
				table.insert(slots, { obj = c, row = row, col = col, span = 1 })
				col += 1
				if col == 2 then
					row, col = row + 1, 0
				end
			end
		end
		local rows = row + (if col > 0 then 1 else 0)
		if #list == 0 then
			rows = math.ceil(tileCount / 2)
		end
		-- touch screens: the tiles stay above the thumbstick's corner (U.stickClear), since a tile under a thumb
		-- would take the touch meant for the stick (the coins can sit under it: they're text, owner 2026-11-15)
		local tilesFloor = if touch then math.min(coinsTop, 1 - sy(U.stickClear)) else coinsTop
		if rows > 0 then
			-- the touch floor only grows a tile as far as the room above the coins allows (a 338 px tall
			-- phone had 46 px tiles running into the coin counter). An extra row (the Tester tile under the
			-- wide Shop row) shrinks the tiles to fit too, never below U.tileMinFit
			local room = (tilesFloor - sy(U.topInset) - sy(U.tileGap)) * h / short -- in short-side units
			local fit = (room - U.tileGap * (rows - 1)) / rows
			tileSize = math.max(math.min(U.tileSize, U.tileMinFit), math.min(tileSize, fit))
		end
		local tw, th = sx(tileSize * 2 + U.tileGap), sy(tileSize * rows + U.tileGap * math.max(0, rows - 1))
		-- centred on the screen's middle; pushed up only if it would touch the coins
		local top = 0.5 - th / 2
		local gap = sy(U.tileGap)
		if top + th > tilesFloor - gap then
			top = math.max(sy(U.topInset), tilesFloor - gap - th)
		end
		tiles.AnchorPoint = Vector2.new(0, 0)
		tiles.Size = UDim2.fromScale(tw, th)
		tiles.Position = UDim2.fromScale(sx(U.sideInset), top)
		-- placed by hand (a UIGridLayout can't span two columns): Scale of the tiles frame
		local totalW = tileSize * 2 + U.tileGap
		local totalH = math.max(1e-6, tileSize * rows + U.tileGap * math.max(0, rows - 1))
		for _, s in slots do
			local w = if s.span == 2 then totalW else tileSize
			s.obj.AnchorPoint = Vector2.zero
			s.obj.Size = UDim2.fromScale(w / totalW, tileSize / totalH)
			s.obj.Position = UDim2.fromScale(s.col * (tileSize + U.tileGap) / totalW, s.row * (tileSize + U.tileGap) / totalH)
		end
	end
end

-- name: "tiles" | "coins" | "power" | "island" | "banner" | "hotbar" | "goal" | "top" | "alert" | "gain" | "clocks"; count = number of tiles for "tiles"
-- (the hotbar's slot count is its "Slots" attribute)
function Screen.register(name: string, obj: GuiObject, count: number?)
	items[name] = obj
	if name == "tiles" then
		tileCount = count or 0
	end
	obj.Parent = if name == "banner" then Screen.alerts elseif name == "gain" then Screen.hud else main
	obj:GetPropertyChangedSignal("Visible"):Connect(Screen.layout) -- a piece appearing re-runs the layout
	obj:GetAttributeChangedSignal("Slots"):Connect(Screen.layout)
	obj:GetAttributeChangedSignal("Locked"):Connect(Screen.layout)
	obj:GetAttributeChangedSignal("Want"):Connect(Screen.layout)
	Screen.layout()
end

-- the tile grid grew or shrank (the Tester tile appears only for testers)
function Screen.setTileCount(count: number)
	tileCount = count
	Screen.layout()
end

-- the popup layer: centred in the band under the top of the screen (the island banner waits while a
-- popup is open, so the two never meet; QA 2026-10-31: a panel over top-HUD text looked broken). Sizes are Scale with a fixed
-- aspect, so a popup is the same share of the screen everywhere.
-- big = the booth and Index popups (owner 2026-11-09: "make it bigger"): Config.ui.popupSizeBig, and
-- they hide the HUD while open (Config.ui.hideHudFor) so the wider panel never sits on the tiles
-- keepsHud = the popup leaves the tiles on screen: it is kept narrow enough to clear them (mobile QA
-- 2026-11-10: on a 4:3 tablet the Pets popup covered the second tile column by 46 px).
-- Phones (mobile QA 2026-11-10): the popup takes the whole height under the top bar. At 70% of a 330 px
-- layer the text came out 8.8 px and buttons 17-22 px tall; the island banner never shows with a popup open.
function Screen.popupFrame(big: boolean?, keepsHud: boolean?): Frame
	local cam = workspace.CurrentCamera
	local short = if cam then math.min(cam.ViewportSize.X, cam.ViewportSize.Y) else 720
	local layer = if Screen.popups and Screen.popups.AbsoluteSize.Y > 0 then Screen.popups.AbsoluteSize elseif cam then cam.ViewportSize else Vector2.new(1280, 720)
	local w, h = math.max(1, layer.X), math.max(1, layer.Y)
	local phone = Screen.deviceClass() == "phone"
	local top = if phone then U.sideInset * short / h else (U.topInset + U.islandBanner.height * U.islandBanner.nameRow + U.tileGap) * short / h
	local bottom = 1 - U.sideInset * short / h
	local f = Instance.new("Frame")
	f.Name = "Popup"
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromScale(0.5, (top + bottom) / 2)
	local size = if big then U.popupSizeBig else U.popupSize
	local width = size[1]
	if keepsHud and Screen.popups and not Screen.menuHidden then
		-- the right edge of the tiles and of the coin number (its text runs past its frame), plus a gap,
		-- mirrored on the right: the popup stays between them (on a tablet it cut "242,518" to "242,3")
		local function rightOf(g: GuiObject?): number
			if not g or not g.Visible then
				return 0
			end
			local r = g.AbsolutePosition.X + g.AbsoluteSize.X
			for _, d in g:GetChildren() do
				if d:IsA("TextLabel") and d.Visible then
					r = math.max(r, d.AbsolutePosition.X + d.TextBounds.X)
				end
			end
			return r
		end
		-- the coins only reach the popup's height on touch screens (lifted over the thumbstick); on PC they
		-- sit in the corner under it
		local coinsRight = if InputController.device() == "touch" then rightOf(items.coins) else 0
		local right = math.max(rightOf(items.tiles), coinsRight) - Screen.popups.AbsolutePosition.X + U.tileGap * short
		width = math.min(width, math.max(0.3, (w - 2 * right) / w))
	end
	f.Size = UDim2.fromScale(width, if phone then bottom - top else math.min(size[2], bottom - top))
	f.BackgroundTransparency = 1
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = if big then U.popupAspectBig else 1.6
	aspect.Parent = f
	f.Parent = Screen.popups
	return f
end

-- Lesson 1 of the tutorial is running (TutorialController, Config.tutorial.lockMenus): the menu tiles and
-- the top buttons wait, so a new player sees only the goal; when it ends they pop in
Screen.menusLocked = false
function Screen.lockMenus(on: boolean, reduced: boolean?)
	if Screen.menusLocked == on then
		return
	end
	Screen.menusLocked = on
	Screen.layout()
	if on then
		return
	end
	for _, name in { "tiles", "top" } do
		local g = items[name]
		if g and not reduced then
			local s = (g:FindFirstChild("UnlockPop") :: UIScale?) or Instance.new("UIScale")
			s.Name = "UnlockPop"
			s.Scale = 0.3
			s.Parent = g
			game:GetService("TweenService"):Create(s, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		end
	end
end

-- any popup is open (PopupController): on a phone the hotbar steps aside (see layout)
Screen.popupOpen = false
function Screen.setPopupOpen(open: boolean)
	if Screen.popupOpen ~= open then
		Screen.popupOpen = open
		Screen.layout()
	end
end

-- a shop is open: the HUD pieces and the world prompts step aside (the banner stays)
function Screen.setMenuHidden(hidden: boolean)
	if Screen.menuHidden == hidden then
		return
	end
	Screen.menuHidden = hidden
	if main then
		main.Visible = not hidden
	end
	Screen.layout() -- the top buttons sit in the top bar, outside main
	menuHiddenEvent:Fire(hidden)
end

-- shows hide the HUD and any popup while they play (Animation Rules 3) and show them again in their cleanup.
-- Carrying a cube hides them too (CarryRush, setCarryHidden). Both ask here, so a show that ends mid-carry
-- doesn't bring the HUD back, and the end of a carry doesn't bring it back mid-show.
local carryHidden = false
local function applyHidden()
	local hide = Screen.showHidden or carryHidden
	for _, g in { Screen.hud, Screen.popups, Screen.topbar, Screen.alerts } do
		if g then
			g.Enabled = not hide
		end
	end
end

-- CarryRush, every frame: a cube is in your hands. Not while the tutorial's goal pill shows (a new player needs
-- it to find the way home). The world prompts stay (they only step aside for shows).
function Screen.setCarryHidden(hidden: boolean)
	local goal = items.goal
	local want = hidden and not (goal ~= nil and goal.Visible)
	if want ~= carryHidden then
		carryHidden = want
		applyHidden()
	end
end

function Screen.setHidden(hidden: boolean)
	local changed = Screen.showHidden ~= hidden
	Screen.showHidden = hidden
	applyHidden()
	if changed then
		showHiddenEvent:Fire(hidden)
	end
end

function Screen.Init()
	Screen.hud = gui("Hud", 1)
	Screen.popups = gui("Popups", 5)
	Screen.alerts = gui("Alerts", 6) -- same insets as the Hud, so the layout's Scale numbers are unchanged
	local bar = gui("TopBar", 2)
	bar.ScreenInsets = Enum.ScreenInsets.TopbarSafeInsets
	Screen.topbar = bar
	local f = Instance.new("Frame")
	f.Name = "Main"
	f.BackgroundTransparency = 1
	f.Size = UDim2.fromScale(1, 1)
	f.Parent = Screen.hud
	main = f
end

function Screen.Start()
	local function watch()
		local cam = workspace.CurrentCamera
		if cam then
			cam:GetPropertyChangedSignal("ViewportSize"):Connect(Screen.layout)
		end
		Screen.layout()
	end
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watch)
	if Screen.hud then
		Screen.hud:GetPropertyChangedSignal("AbsoluteSize"):Connect(Screen.layout) -- the top bar's size can change after the viewport
	end
	if Screen.topbar then
		Screen.topbar:GetPropertyChangedSignal("AbsoluteSize"):Connect(Screen.layout)
		Screen.topbar:GetPropertyChangedSignal("AbsolutePosition"):Connect(Screen.layout)
	end
	GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(Screen.layout)
	watch()
	InputController.DeviceChanged:Connect(Screen.layout)
end

return Screen
