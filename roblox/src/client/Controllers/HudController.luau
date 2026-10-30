--!strict
-- HudController: the HUD's contents: the menu tiles (Pets, Shop, Index, Settings), the coins with
-- +N/s, the goal bar (one named goal, have / need, never empty), the temperature chip and the banner
-- (Big Chill, others' big wins, "not yet" answers). Screen places all of them.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Theme = require(ReplicatedStorage.Shared.Theme)
local PetDefs = require(ReplicatedStorage.Shared.PetDefs)
local WorldRules = require(ReplicatedStorage.Shared.WorldRules)
local Ui = require(script.Parent.Parent.Lib.Ui)
local State = require(script.Parent.State)
local Screen = require(script.Parent.Screen)
local PopupController = require(script.Parent.PopupController)
local SettingsController = require(script.Parent.SettingsController)

local HudController = {}

local coins: Ui.Block
local coinsRate: TextLabel
local goal: Ui.Block
local goalFill: Frame
local temp: Ui.Block
local banner: Ui.Block
local bannerUntil = 0
local beachSeen = false

function HudController.banner(textValue: string, color: Color3?, seconds: number?)
	banner.text.Text = textValue
	banner.face.BackgroundColor3 = color or Theme.info
	banner.root.BackgroundColor3 = Ui.darker(color or Theme.info)
	banner.root.Visible = true
	local untilAt = os.clock() + (seconds or Config.ui.bannerSeconds)
	bannerUntil = untilAt
	task.delay(seconds or Config.ui.bannerSeconds, function()
		if bannerUntil == untilAt then
			banner.root.Visible = false
		end
	end)
end

-- gain text appears beside the coin counter, never on a HUD item
local function floatGain(amount: number)
	local t = Ui.label(coins.root, `+{Ui.short(amount)}`, UDim2.fromScale(0.6, 0.8), UDim2.fromScale(1.05, 0.1))
	t.TextColor3 = Theme.coin
	t.TextXAlignment = Enum.TextXAlignment.Left
	task.delay(Config.ui.floatSeconds, function()
		t:Destroy()
	end)
end

local function goalFor(v: State.View): (string, number)
	local forest = Config.zone(2) :: Config.Zone
	if not v.forestUnlocked then
		if v.coins >= forest.gateCoins then
			return "Pine Forest: go open the gate!", 1
		end
		return `Unlock Pine Forest: {Ui.short(v.coins)} / {Ui.short(forest.gateCoins)}`, v.coins / forest.gateCoins
	end
	if v.coins < Config.beachGateCoins and not beachSeen then
		return `Save for Sunny Beach: {Ui.short(v.coins)} / {Ui.short(Config.beachGateCoins)}`, v.coins / Config.beachGateCoins
	end
	beachSeen = true
	for _, page in v.pages do
		if not page.complete then
			local z = Config.zone(page.zone)
			return `Fill the {if z then z.name else "zone"} page: {page.found} / {page.total}`, page.found / math.max(1, page.total)
		end
	end
	return "Every page full! Sunny Beach is next", 1
end

local function render(v: State.View)
	coins.text.Text = Ui.short(v.coins)
	coinsRate.Text = if v.income > 0 then `+{Ui.short(v.income)}/s` else ""
	coinsRate.Visible = v.income > 0
	local textValue, frac = goalFor(v)
	goal.text.Text = textValue
	goalFill.Size = UDim2.fromScale(math.clamp(frac, 0, 1), 1)
	goal.root.Visible = #v.pets > 0 -- shows with the first pet, so it starts at a real 1 / 8
end

local function updateTemp()
	local c = Players.LocalPlayer.Character
	local root = c and c:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	local chillUntil = workspace:GetAttribute("ChillUntil")
	local chill = typeof(chillUntil) == "number" and chillUntil > workspace:GetServerTimeNow()
	local deg, band = WorldRules.temperatureAt(root.Position, false, chill)
	local unit = SettingsController.get("unit")
	local shown = if unit == "F" then WorldRules.toFahrenheit(deg) else deg
	local light = WorldRules.lightAt(root.Position)
	temp.text.Text = `{shown}°{unit}` .. (if chill then " Big Chill" elseif light ~= "open" then " " .. light else "")
	local color = if chill then Theme.temp.chill else Theme.temp[band]
	temp.face.BackgroundColor3 = color
	temp.root.BackgroundColor3 = Ui.darker(color)
end

function HudController.Init() end

function HudController.Start()
	-- tiles
	local tiles = Instance.new("Frame")
	tiles.Name = "Tiles"
	tiles.BackgroundTransparency = 1
	local grid = Instance.new("UIGridLayout")
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = tiles
	for i, t in Config.ui.tiles do
		local b = Ui.block(tiles, t.id, Theme.tiles[t.id] or Theme.info, t.label, function()
			PopupController.open(t.id)
		end)
		b.root.LayoutOrder = i
	end
	Screen.register("tiles", tiles, #Config.ui.tiles)
	-- coins
	coins = Ui.block(Screen.hud :: ScreenGui, "Coins", Theme.coin, "0", nil)
	coins.text.Size = UDim2.fromScale(0.9, 0.55)
	coinsRate = Ui.label(coins.face, "", UDim2.fromScale(0.9, 0.3), UDim2.fromScale(0.05, 0.65))
	Screen.register("coins", coins.root)
	-- goal bar
	goal = Ui.block(Screen.hud :: ScreenGui, "Goal", Theme.board, "", nil)
	goalFill = Instance.new("Frame")
	goalFill.Name = "Fill"
	goalFill.BackgroundColor3 = Theme.go
	goalFill.BorderSizePixel = 0
	goalFill.Size = UDim2.fromScale(0, 1)
	goalFill.ZIndex = 0
	Ui.corner(goalFill)
	goalFill.Parent = goal.face
	goal.text.ZIndex = 2
	goal.root.Visible = false
	Screen.register("goal", goal.root)
	-- temperature chip
	temp = Ui.block(Screen.hud :: ScreenGui, "Temp", Theme.temp.cool, "", nil)
	Screen.register("temp", temp.root)
	-- banner
	banner = Ui.block(Screen.hud :: ScreenGui, "Banner", Theme.info, "", nil)
	banner.root.Visible = false
	Screen.register("banner", banner.root)

	State.Changed:Connect(render)
	if State.view then
		render(State.view)
	end
	State.Notify:Connect(function(kind: string, data: any)
		if kind == "notYet" then
			HudController.banner(tostring(data.reason), Theme.no, Config.ui.notYetSeconds)
		elseif kind == "chillWarn" then
			HudController.banner(`Big Chill in {data.inSeconds} s!`, Theme.info)
		elseif kind == "chillStart" then
			HudController.banner("Big Chill! Nothing melts", Theme.info, data.seconds)
		elseif kind == "bigWin" then
			local def = PetDefs.get(data.key)
			if def then
				HudController.banner(`{data.name} caught a {string.upper(def.tier)} {def.name}!`, Theme.tiers[def.tier])
			end
		elseif kind == "banked" then
			local total = 0
			for _, b in data.banked do
				total += b.income
			end
			HudController.banner(`+{Ui.short(total)}/s in your pen`, Theme.go)
		elseif kind == "zoneUnlocked" then
			HudController.banner("Pine Forest is open!", Theme.go)
		elseif kind == "upgraded" then
			local u = Config.upgrades[data.id]
			HudController.banner(`{u and u.name or "Upgrade"} level {data.level}!`, Theme.go)
		elseif kind == "welcomeCollected" or kind == "giftClaimed" then
			floatGain(data.coins)
		elseif kind == "melted" then
			HudController.banner("It melted! Zap it again", Theme.info)
		elseif kind == "chargeSaved" then
			HudController.banner("Super Freeze saved for next time", Theme.info)
		elseif kind == "splash" then
			HudController.banner("Splash! Back on the bank", Theme.info)
		end
	end)
	task.spawn(function()
		WorldRules.refreshAreas() -- shade and sun parts are tagged in the map
		while true do
			updateTemp()
			task.wait(0.25)
		end
	end)
end

return HudController
