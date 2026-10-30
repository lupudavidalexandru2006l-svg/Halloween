--!strict
-- Screen: the only module that places HUD pieces (UI Rules, Code Rules 1). Others build contents and
-- register them here. Sizes are fractions of the screen's short side, turned into Scale (no Offset)
-- each time the screen size, the device or a piece changes. The ScreenGuis use the core-UI safe
-- insets, so nothing sits under Roblox's top bar; on touch the coins sit above the thumbstick.
-- HUD (5 at most): tile grid (left, centred), coins (bottom left), goal bar (top centre),
-- temperature chip (beside the goal bar), and the banner (only while it shows).

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
	local w, h = math.max(1, cam.ViewportSize.X), math.max(1, cam.ViewportSize.Y)
	local short = math.min(w, h)
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
	local goal = items.goal
	if goal then
		goal.AnchorPoint = Vector2.new(0.5, 0)
		goal.Size = UDim2.fromScale(sx(U.goalSize[1]), sy(U.goalSize[2]))
		goal.Position = UDim2.fromScale(0.5, sy(U.topInset))
	end
	local temp = items.temp
	if temp then
		temp.AnchorPoint = Vector2.new(0, 0)
		temp.Size = UDim2.fromScale(sx(U.tempSize[1]), sy(U.tempSize[2]))
		temp.Position = UDim2.fromScale(0.5 + sx(U.goalSize[1] / 2 + U.tileGap), sy(U.topInset))
	end
	local banner = items.banner
	if banner then
		banner.AnchorPoint = Vector2.new(0.5, 0)
		banner.Size = UDim2.fromScale(sx(U.goalSize[1] * 1.2), sy(U.goalSize[2] * 1.1))
		banner.Position = UDim2.fromScale(0.5, sy(U.topInset * 2 + U.goalSize[2]))
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

-- name: "tiles" | "coins" | "goal" | "temp" | "banner"; count = number of tiles for "tiles"
function Screen.register(name: string, obj: GuiObject, count: number?)
	items[name] = obj
	if name == "tiles" then
		tileCount = count or 0
	end
	obj.Parent = Screen.hud
	obj:GetPropertyChangedSignal("Visible"):Connect(Screen.layout) -- a piece appearing re-runs the layout
	Screen.layout()
end

-- the popup layer's centre (a little above the middle). Sizes are Scale with a fixed aspect, so a
-- popup is the same share of the screen everywhere; that replaces the offset-era UIScale per device.
function Screen.popupFrame(): Frame
	local f = Instance.new("Frame")
	f.Name = "Popup"
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromScale(0.5, 0.5 - U.popupLift)
	f.Size = UDim2.fromScale(U.popupSize[1], U.popupSize[2])
	f.BackgroundTransparency = 1
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1.6
	aspect.Parent = f
	f.Parent = Screen.popups
	return f
end

function Screen.Init()
	Screen.hud = gui("Hud", 1)
	Screen.popups = gui("Popups", 5)
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
	watch()
	InputController.DeviceChanged:Connect(Screen.layout)
end

return Screen
