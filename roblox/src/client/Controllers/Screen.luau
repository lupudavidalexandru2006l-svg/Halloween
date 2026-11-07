--!strict
-- Screen: the only module that places HUD pieces (UI Rules, Code Rules 1). Others build contents and
-- register them here. Sizes are fractions of the screen's short side, turned into Scale (no Offset)
-- each time the screen size, the device or a piece changes. The ScreenGuis use the core-UI safe
-- insets, so nothing sits under Roblox's top bar; on touch the coins sit above the thumbstick.
-- HUD (5 at most): tile grid (left, centred), coins (bottom left), the island banner (top centre,
-- only while it shows), the hotbar (bottom centre, Round 5) and the banner (only while it shows).

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
	local lift = if InputController.device() == "touch" then U.touchLift else 0
	local coins = items.coins
	local coinsTop = 1
	if coins then
		coins.AnchorPoint = Vector2.new(0, 1)
		coins.Size = UDim2.fromScale(sx(U.coinsSize[1]), sy(U.coinsSize[2]))
		coins.Position = UDim2.fromScale(sx(U.sideInset), 1 - sy(U.sideInset + lift))
		coinsTop = 1 - sy(U.sideInset + lift + U.coinsSize[2])
	end
	local IB = U.islandBanner
	local island = items.island
	if island then
		-- a fixed slot at the top centre; the strip inside it slides (HudController animates the inside only)
		island.AnchorPoint = Vector2.new(0.5, 0)
		island.Size = UDim2.fromScale(math.min(1, sx(IB.width)), sy(IB.height))
		island.Position = UDim2.fromScale(0.5, sy(U.topInset))
	end
	local banner = items.banner
	if banner then
		-- under the island banner, so the two never overlap
		banner.AnchorPoint = Vector2.new(0.5, 0)
		banner.Size = UDim2.fromScale(sx(U.bannerSize[1]), sy(U.bannerSize[2]))
		banner.Position = UDim2.fromScale(0.5, sy(U.topInset * 2 + IB.height))
	end
	-- the hotbar: bottom centre, between the thumbstick and the jump button on touch screens
	local hotbar = items.hotbar
	if hotbar then
		local H = Config.hotbar
		local n = math.max(1, (hotbar:GetAttribute("Slots") or 1) :: number)
		hotbar.AnchorPoint = Vector2.new(0.5, 1)
		hotbar.Size = UDim2.fromScale(sx(H.size * n + H.gap * (n - 1)), sy(H.size * 1.45))
		hotbar.Position = UDim2.fromScale(0.5, 1 - sy(H.bottomInset))
	end
	local tiles = items.tiles
	if tiles then
		local rows = math.ceil(tileCount / 2)
		local tw, th = sx(U.tileSize * 2 + U.tileGap), sy(U.tileSize * rows + U.tileGap * math.max(0, rows - 1))
		-- centred on the screen's middle; pushed up only if it would touch the coins
		local top = 0.5 - th / 2
		local gap = sy(U.tileGap)
		if top + th > coinsTop - gap then
			top = math.max(sy(U.topInset), coinsTop - gap - th)
		end
		tiles.AnchorPoint = Vector2.new(0, 0)
		tiles.Size = UDim2.fromScale(tw, th)
		tiles.Position = UDim2.fromScale(sx(U.sideInset), top)
		local grid = tiles:FindFirstChildOfClass("UIGridLayout")
		if grid then
			local cell = U.tileSize / (U.tileSize * 2 + U.tileGap)
			grid.CellSize = UDim2.fromScale(cell, U.tileSize / (U.tileSize * rows + U.tileGap * math.max(0, rows - 1)))
			grid.CellPadding = UDim2.fromScale(1 - cell * 2, if rows > 1 then U.tileGap / (U.tileSize * rows + U.tileGap * (rows - 1)) else 0)
		end
	end
end

-- name: "tiles" | "coins" | "island" | "banner" | "hotbar"; count = number of tiles for "tiles"
-- (the hotbar's slot count is its "Slots" attribute)
function Screen.register(name: string, obj: GuiObject, count: number?)
	items[name] = obj
	if name == "tiles" then
		tileCount = count or 0
	end
	obj.Parent = if name == "banner" then Screen.hud else main
	obj:GetPropertyChangedSignal("Visible"):Connect(Screen.layout) -- a piece appearing re-runs the layout
	obj:GetAttributeChangedSignal("Slots"):Connect(Screen.layout)
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
function Screen.popupFrame(): Frame
	local cam = workspace.CurrentCamera
	local short = if cam then math.min(cam.ViewportSize.X, cam.ViewportSize.Y) else 720
	local h = if Screen.popups and Screen.popups.AbsoluteSize.Y > 0 then Screen.popups.AbsoluteSize.Y elseif cam then math.max(1, cam.ViewportSize.Y) else 720
	local top = (U.topInset + U.islandBanner.height * U.islandBanner.nameRow + U.tileGap) * short / h
	local bottom = 1 - U.sideInset * short / h
	local f = Instance.new("Frame")
	f.Name = "Popup"
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromScale(0.5, (top + bottom) / 2)
	f.Size = UDim2.fromScale(U.popupSize[1], math.min(U.popupSize[2], bottom - top))
	f.BackgroundTransparency = 1
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1.6
	aspect.Parent = f
	f.Parent = Screen.popups
	return f
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
	menuHiddenEvent:Fire(hidden)
end

-- shows hide the HUD and any popup while they play (Animation Rules 3) and show them again in their cleanup
function Screen.setHidden(hidden: boolean)
	for _, g in { Screen.hud, Screen.popups } do
		if g then
			g.Enabled = not hidden
		end
	end
	if Screen.showHidden ~= hidden then
		Screen.showHidden = hidden
		showHiddenEvent:Fire(hidden)
	end
end

function Screen.Init()
	Screen.hud = gui("Hud", 1)
	Screen.popups = gui("Popups", 5)
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
	watch()
	InputController.DeviceChanged:Connect(Screen.layout)
end

return Screen
