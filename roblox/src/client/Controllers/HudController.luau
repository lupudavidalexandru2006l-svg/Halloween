--!strict
-- HudController: the HUD's contents: the menu tiles (Pets, Shop, Index, Settings), the coins with
-- +N/s, the goal bar (one named goal, have / need, never empty), the temperature chip and the banner
-- (Big Chill, others' big wins, "not yet" answers). Screen places all of them.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
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

local coinsRoot: Frame
local coinsText: TextLabel
local coinsRate: TextLabel
local goal: Ui.Block
local goalFill: Frame
local temp: Ui.Block
local tempWhy: TextLabel
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

-- gain text appears beside the coin counter, never on a HUD item. It wears the counter's own look
-- (white-to-gold fill, the firm outline) a size smaller, starts just past the number's visible end
-- (owner 2026-11-05: it sat on the last digit in flat yellow), pops in, then drifts up and fades.
local function floatGain(amount: number)
	local G = Config.ui.gain
	local w = math.max(1, coinsRoot.AbsoluteSize.X)
	local x = coinsText.Position.X.Scale + coinsText.TextBounds.X / w + G.gap
	local t = Ui.label(coinsRoot, `+{Ui.short(amount)}`, UDim2.fromScale(G.width, G.height), UDim2.fromScale(x, G.y))
	t.Name = "Gain"
	t.TextXAlignment = Enum.TextXAlignment.Left
	local stroke = t:FindFirstChildOfClass("UIStroke") :: UIStroke
	stroke.Thickness = Config.ui.floatingStroke
	local gold = Instance.new("UIGradient")
	gold.Rotation = 90
	gold.Color = ColorSequence.new(Theme.white, Theme.coin)
	gold.Parent = t
	local pop = Instance.new("UIScale")
	pop.Scale = 0.4
	pop.Parent = t
	local still = SettingsController.get("reducedMotion") == true
	TweenService:Create(pop, TweenInfo.new(G.popSeconds, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	local fade = TweenInfo.new(Config.ui.floatSeconds - G.holdSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, G.holdSeconds)
	TweenService:Create(t, fade, { Position = UDim2.fromScale(x, G.y - (if still then 0 else G.rise)), TextTransparency = 1 }):Play()
	TweenService:Create(stroke, fade, { Transparency = 1 }):Play()
	task.delay(Config.ui.floatSeconds, function()
		t:Destroy()
	end)
end

local function goalFor(v: State.View): (string, number)
	-- Round 4 phase 6: the next gate along the tunnel (coins, and on odd islands a rebirth)
	local nz = Config.zone((v.reach or 1) + 1)
	if nz and nz.ready then
		if v.rebirths < nz.gateRebirth then
			return `{nz.name}: Rebirth {nz.gateRebirth}`, v.rebirths / nz.gateRebirth
		end
		if v.coins >= nz.gateCoins then
			return `{nz.name}: go open the gate!`, 1
		end
		return `Unlock {nz.name}: {Ui.short(v.coins)} / {Ui.short(nz.gateCoins)}`, v.coins / math.max(1, nz.gateCoins)
	end
	local soon = if nz then nz.name elseif Config.world.nextIsland then Config.world.nextIsland.name else "the next island"
	if v.coins < Config.beachGateCoins and not beachSeen then
		return `Save for {soon}: {Ui.short(v.coins)} / {Ui.short(Config.beachGateCoins)}`, v.coins / Config.beachGateCoins
	end
	beachSeen = true
	for _, page in v.pages do
		if not page.complete then
			local z = Config.zone(page.zone)
			return `Fill the {if z then z.name else "zone"} page: {page.found} / {page.total}`, page.found / math.max(1, page.total)
		end
	end
	-- the next island isn't open yet (its pets are coming), so the next real goal is a rebirth
	-- (final QA 2026-11-03: the bar said "Every page full! Mushroom Grove is next" for the rest of the game)
	local n = (v.rebirths or 0) + 1
	local cost = Config.rebirthCost(n)
	if v.coins >= cost then
		return `Rebirth {n}: go to the Rebirth Booth!`, 1
	end
	return `Rebirth {n}: {Ui.short(v.coins)} / {Ui.short(cost)}`, v.coins / math.max(1, cost)
end

local tilesFrame: Frame
local testerTile: Ui.Block? = nil

-- the "T" tile: only made once the server says this account is a tester
local function ensureTesterTile()
	if testerTile then
		return
	end
	local t = Config.ui.testerTile
	local b = Ui.block(tilesFrame, t.id, Theme.tiers.Common, "T", function() -- quiet grey: a tool for testers, not a game menu
		PopupController.open(t.id)
	end)
	b.root.LayoutOrder = #Config.ui.tiles + 1
	b.text.Size = UDim2.fromScale(0.8, 0.62)
	b.text.Position = UDim2.fromScale(0.1, 0.04)
	local small = Ui.label(b.face, t.label, UDim2.fromScale(0.9, 0.26), UDim2.fromScale(0.05, 0.7))
	small.Name = "Label"
	testerTile = b
	Screen.setTileCount(#Config.ui.tiles + 1)
end

local function render(v: State.View)
	if v.tester then
		ensureTesterTile()
	end
	coinsText.Text = Ui.commas(v.coins) -- the whole number, 1,508,273 not 1.5M (owner 2026-11-03)
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
	local offset = workspace:GetAttribute("NightOffset")
	local night = WorldRules.nightCycle(workspace:GetServerTimeNow(), if typeof(offset) == "number" then offset else 0).night
	local deg, band = WorldRules.temperatureAt(root.Position, night, chill)
	local unit = SettingsController.get("unit")
	local shown = if unit == "F" then WorldRules.toFahrenheit(deg) else deg
	local light = WorldRules.lightAt(root.Position)
	temp.text.Text = `{shown}°{unit}`
	local zone = Config.zone(WorldRules.zoneAt(root.Position))
	tempWhy.Text = if chill then "Big Chill" elseif light == "lava" then "Lava pool" elseif night then "Night" elseif light == "shade" then "Shade" elseif light == "sun" then "Sunny spot"
		elseif zone then zone.name else "Hub"
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
	tilesFrame = tiles
	for i, t in Config.ui.tiles do
		local b = Ui.block(tiles, t.id, Theme.tiles[t.id] or Theme.info, t.label, function()
			PopupController.open(t.id)
		end)
		b.root.LayoutOrder = i
		-- the painted icon on top, the name small underneath (prototype tiles)
		local icon = Config.ui.tileIcons[t.id]
		if icon then
			-- a big centred icon filling the tile, the name sitting on the tile's bottom edge in a bold
			-- outline (simulator-style menu tiles; owner 2026-10-31)
			local img = Ui.image(b.face, icon, UDim2.fromScale(0.92, 0.8), UDim2.fromScale(0.04, 0))
			img.ZIndex = 1
			b.text.Size = UDim2.fromScale(1.12, 0.34)
			b.text.Position = UDim2.fromScale(-0.06, 0.74)
			b.text.ZIndex = 2
			local ts = b.text:FindFirstChildOfClass("UIStroke") :: UIStroke
			ts.Thickness = Config.ui.floatingStroke
		end
	end
	Screen.register("tiles", tiles, #Config.ui.tiles)
	-- coins: the coin image, the number, and +N/s under it
	-- coins: the coin and the number straight on the screen, no box behind them (owner 2026-10-31)
	coinsRoot = Instance.new("Frame")
	coinsRoot.Name = "Coins"
	coinsRoot.BackgroundTransparency = 1
	Ui.image(coinsRoot, Config.images.icons.coin, UDim2.fromScale(0.34, 1), UDim2.fromScale(0, 0))
	-- wider than the frame (it runs on to the right) so a long whole number keeps a big font
	coinsText = Ui.label(coinsRoot, "0", UDim2.fromScale(1.4, 0.62), UDim2.fromScale(0.34, 0))
	coinsText.TextXAlignment = Enum.TextXAlignment.Left
	coinsRate = Ui.label(coinsRoot, "", UDim2.fromScale(0.64, 0.34), UDim2.fromScale(0.35, 0.62))
	coinsRate.TextXAlignment = Enum.TextXAlignment.Left
	coinsRate.TextColor3 = Theme.go -- income reads as "go/gain" green
	local gold = Instance.new("UIGradient") -- the number fades white to gold, like the coin
	gold.Rotation = 90
	gold.Color = ColorSequence.new(Theme.white, Theme.coin)
	gold.Parent = coinsText
	for _, t in { coinsText, coinsRate } do
		local s = t:FindFirstChildOfClass("UIStroke") :: UIStroke
		s.Thickness = Config.ui.floatingStroke -- nothing behind it now, so a firmer outline reads over snow
	end
	Screen.register("coins", coinsRoot)
	-- goal bar
	goal = Ui.block(Screen.hud :: ScreenGui, "Goal", Theme.goal, "", nil)
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
	-- temperature chip: a thermometer (built from shapes, no emoji), the degrees, and why (zone, shade, sun)
	-- the painted thermometer (the one built from UI shapes looked cheap), the degrees and why, centred
	-- in the space beside it
	temp = Ui.block(Screen.hud :: ScreenGui, "Temp", Theme.temp.cool, "", nil)
	Ui.image(temp.face, Config.images.icons.temp, UDim2.fromScale(0.24, 0.9), UDim2.fromScale(0.02, 0.05))
	temp.text.Size = UDim2.fromScale(0.7, 0.54)
	temp.text.Position = UDim2.fromScale(0.27, 0.06)
	tempWhy = Ui.label(temp.face, "", UDim2.fromScale(0.7, 0.32), UDim2.fromScale(0.27, 0.6))
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
		elseif kind == "nightStart" then
			HudController.banner("Night time! Pets are sleeping", Theme.info)
		elseif kind == "nightEnd" then
			HudController.banner("Good morning!", Theme.info)
		elseif kind == "bigWin" then
			local def = PetDefs.get(data.key)
			if def then
				HudController.banner(`{data.name} caught a {string.upper(def.tier)} {def.name}!`, Theme.tiers[def.tier])
			end
		elseif kind == "shoutout" then
			-- a Secret was frozen somewhere on the server (the freezer sees their own show instead)
			local def = PetDefs.get(data.key)
			if def and data.userId ~= Players.LocalPlayer.UserId then
				HudController.banner(`{data.name} froze a {string.upper(def.tier)} {def.name}!`, Theme.tierGlow[def.tier] or Theme.coin)
			end
		elseif kind == "banked" then
			local total, best = 0, nil :: PetDefs.PetDef?
			for _, b in data.banked do
				total += b.income
				local def = PetDefs.get(b.key)
				if def and (not best or Config.tier(def.tier).rank > Config.tier(best.tier).rank) then
					best = def
				end
			end
			if best and Config.tier(best.tier).rank >= Config.effects.showRank then
				HudController.banner(`{string.upper(best.tier)}! {best.name}`, Theme.tiers[best.tier]) -- prototype: Epic and up get the show
			else
				HudController.banner(`+{Ui.short(total)}/s in your pan`, Theme.go)
			end
		elseif kind == "zoneUnlocked" then
			local z = Config.zone(if typeof(data.zone) == "number" then data.zone else 2)
			HudController.banner(`{if z then z.name else "The next island"} is open!`, Theme.go)
		elseif kind == "comingSoon" then
			HudController.banner(`{tostring(data.label)}: coming soon!`, Theme.info)
		elseif kind == "upgraded" then
			local u = Config.upgrades[data.id]
			HudController.banner(`{u and u.name or "Upgrade"} level {data.level}!`, Theme.go)
		elseif kind == "welcomeCollected" or kind == "giftClaimed" then
			floatGain(data.coins)
		elseif kind == "melted" then
			HudController.banner("It melted! Zap it again", Theme.info)
		elseif kind == "chargeSaved" then
			HudController.banner("Super Freeze saved for next time", Theme.info)
		elseif kind == "robuxBought" then
			-- a Robux shop item arrived (saved first, MonetizationService)
			if (data.coins or 0) > 0 then
				HudController.banner(`{data.name}! +{Ui.short(data.coins)} coins`, Theme.coin)
				floatGain(data.coins)
			elseif (data.charges or 0) > 0 then
				HudController.banner(`+{data.charges} Super Freezes!`, Theme.go)
			else
				HudController.banner(`{tostring(data.name)} is yours!`, Theme.go)
			end
		-- Round 5
		elseif kind == "codeResult" then
			if data.ok then
				HudController.banner(`{data.text} +{Ui.short(data.coins or 0)}`, Theme.coin)
				floatGain(data.coins or 0)
			else
				HudController.banner(tostring(data.text), Theme.no, Config.ui.notYetSeconds)
			end
		elseif kind == "gearBought" then
			HudController.banner("Slow Gel is on your hotbar!", Theme.go)
		elseif kind == "thawed" then
			local def = PetDefs.get(data.key)
			HudController.banner(`{if def then def.name else "Your pet"} is out! +{Ui.short(data.income or 0)}/s`, Theme.go)
		elseif kind == "critterCaught" then
			HudController.banner("A Heat Critter grabbed your cube! Zap it back", Theme.round5.critter)
		elseif kind == "tagged" then
			HudController.banner(`{data.by} knocked your cube loose!`, Theme.round5.reticlePlayer)
		elseif kind == "tagHit" then
			HudController.banner("Cube knocked loose! Zap it", Theme.round5.reticlePlayer)
		elseif kind == "shieldOff" then
			HudController.banner("Your shield is off: keep your cubes safe!", Theme.round5.shield)
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
