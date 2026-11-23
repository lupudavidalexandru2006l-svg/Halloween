--!strict
-- OfferController (owner 2026-11-18: "the monetizations are good, you can add them"; vault Games/Ice Ray for Pets/
-- Monetization Plan 2026-11-18). The in-the-moment offers and the boost timers, all small and on the side, never a
-- full-screen pop-up, never a countdown on an offer, and the free way always still works:
--  - Keep It Frozen: while the cube in your hands has less than Config.monetization.keepFrozenBelow of its ice, a
--    pulsing ice-blue button over the hotbar. Gone once it's safe, banked or melted.
--  - Boost timers: small pills bottom right for a running Speed Potion, Lucky Ray, Server Luck, Critter Shields.
--  - Short on coins: after the needOffer.after-th "Need X more" of a session, a small Coin Bag card for a few
--    seconds (at most needOffer.max a session), with an X.
-- Every button only asks: the server shows Roblox's own purchase prompt and grants in ProcessReceipt.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Theme = require(ReplicatedStorage.Shared.Theme)
local WorldRules = require(ReplicatedStorage.Shared.WorldRules)
local Ui = require(script.Parent.Parent.Lib.Ui)
local State = require(script.Parent.State)
local SoundController = require(script.Parent.SoundController)

local OfferController = {}
local M = Config.monetization
local me = Players.LocalPlayer
local gui: ScreenGui

-- a Robux button: an icon, the words, and a dark price chip on the right with Roblox's mark and the price side by
-- side. Owner 2026-11-21: the mark used to sit on top of the number ("the robux coin was overlapping"), so the
-- mark and the number now each get their own half of the chip.
local function robuxButton(parent: Instance, name: string, color: Color3, words: string, item: Config.RobuxItem?, icon: string?): Ui.Block
	local b = Ui.block(parent, name, color, words, function()
		SoundController.play("click")
		if item then
			State.send("BuyRobux", item.id)
		end
	end)
	local left = 0.05
	if icon and Config.images.icons[icon] then
		local ic = Ui.image(b.face, Config.images.icons[icon], UDim2.fromScale(0.13, 0.86), UDim2.fromScale(0.02, 0.07))
		ic.ZIndex = 2
		left = 0.15
	end
	b.text.Size = UDim2.fromScale(0.68 - left, 0.56)
	b.text.Position = UDim2.fromScale(left, 0.2)
	b.text.TextXAlignment = Enum.TextXAlignment.Left
	local chip = Instance.new("Frame")
	chip.Name = "Price"
	chip.BackgroundColor3 = Theme.ink
	chip.BackgroundTransparency = 0.35
	chip.BorderSizePixel = 0
	chip.AnchorPoint = Vector2.new(1, 0.5)
	chip.Position = UDim2.fromScale(0.96, 0.5)
	chip.Size = UDim2.fromScale(0.27, 0.72)
	chip.ZIndex = 2
	Ui.corner(chip, 0.5)
	chip.Parent = b.face
	local mark = Ui.image(chip, Config.images.icons.robux, UDim2.fromScale(0.34, 0.7), UDim2.fromScale(0.07, 0.15))
	mark.ZIndex = 3
	local price = Ui.label(chip, if item then tostring(item.robux) else "", UDim2.fromScale(0.5, 0.72), UDim2.fromScale(0.43, 0.14))
	price.TextXAlignment = Enum.TextXAlignment.Left
	price.ZIndex = 3
	return b
end

local function aspect(obj: GuiObject, ratio: number)
	local a = Instance.new("UIAspectRatioConstraint")
	a.AspectRatio = ratio
	a.Parent = obj
end

-- ---------- Keep It Frozen ----------
local keepB: Ui.Block
local keepTween: Tween? = nil

local function myLowCube(): boolean
	local f = workspace:FindFirstChild("Cubes", true)
	if not f then
		return false
	end
	-- owner 2026-11-22: not in the safe hub, where the ice doesn't melt (nothing to keep frozen)
	local char = me.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root and WorldRules.inHub(root.Position) then
		return false
	end
	for _, c in f:GetChildren() do
		if c:GetAttribute("OwnerUserId") == me.UserId and c:GetAttribute("SuperFrozen") ~= true then
			local frac = c:GetAttribute("LifeFrac")
			if typeof(frac) == "number" and frac < M.keepFrozenBelow then
				return true
			end
		end
	end
	return false
end

local function syncKeep()
	local show = myLowCube()
	if keepB.root.Visible == show then
		return
	end
	keepB.root.Visible = show
	local sc = keepB.root:FindFirstChildOfClass("UIScale") :: UIScale
	if show then
		sc.Scale = 1
		keepTween = TweenService:Create(sc, TweenInfo.new(0.45, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Scale = 1.1 })
		;(keepTween :: Tween):Play()
	elseif keepTween then
		keepTween:Cancel()
		keepTween = nil
	end
end

-- ---------- boost timers ----------
local pills: Frame
local pillLabels: { [string]: TextLabel } = {}

local function clock(secs: number): string
	secs = math.max(0, math.floor(secs))
	return `{secs // 60}:{string.format("%02d", secs % 60)}`
end

-- owner 2026-11-20: the old wide green pill looked bad and sat on the clocks. Each boost is now a chip in the
-- clocks' own look (navy pill, round icon chip in the boost's colour, white words), stacked just above the
-- clocks and the same size, following them as they open on hover (placePills, every frame).
local PILL_GAP = 4
local function pill(id: string, order: number, color: Color3, icon: string, text: string?)
	local l = pillLabels[id]
	if not text then
		if l then
			(l.Parent :: Instance):Destroy()
			pillLabels[id] = nil
		end
		return
	end
	if not l then
		local f = Instance.new("Frame")
		f.Name = id
		f.LayoutOrder = order
		f.BackgroundColor3 = Theme.alert.back
		f.BackgroundTransparency = 0.15
		f.BorderSizePixel = 0
		f.Size = UDim2.fromScale(1, 0.3)
		Ui.corner(f, 0.5)
		Ui.stroke(f, 2.5)
		local chip = Instance.new("Frame")
		chip.BackgroundColor3 = color
		chip.BorderSizePixel = 0
		chip.Position = UDim2.new(0, 2, 0, 2)
		chip.Size = UDim2.new(1, -4, 1, -4)
		local a = Instance.new("UIAspectRatioConstraint")
		a.AspectRatio = 1
		a.DominantAxis = Enum.DominantAxis.Height
		a.Parent = chip
		Ui.corner(chip, 0.5)
		chip.Parent = f
		Ui.image(chip, Config.images.icons[icon] or Config.images.icons.star, UDim2.fromScale(0.78, 0.78), UDim2.fromScale(0.11, 0.11))
		f.Parent = pills
		l = Ui.label(f, "", UDim2.new(1, 0, 0.66, 0), UDim2.fromScale(0, 0.17))
		l.TextXAlignment = Enum.TextXAlignment.Right
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0.2, 0)
		pad.PaddingRight = UDim.new(0.07, 0)
		pad.Parent = l
		pillLabels[id] = l
	end
	(l :: TextLabel).Text = text
end

-- sit the boost chips right above the top visible clock, at the clocks' size
local function placePills()
	local hud = me.PlayerGui:FindFirstChild("Clocks", true) :: GuiObject?
	if not hud or not hud:IsA("GuiObject") or not hud.Visible then
		pills.Visible = false
		return
	end
	local top, w, h, right = math.huge, 0, 0, 0
	for _, c in hud:GetChildren() do
		if c:IsA("GuiObject") and c.Visible then
			top = math.min(top, c.AbsolutePosition.Y)
			w, h = c.AbsoluteSize.X, c.AbsoluteSize.Y
			right = c.AbsolutePosition.X + c.AbsoluteSize.X
		end
	end
	if top == math.huge or h <= 0 then
		pills.Visible = false
		return
	end
	pills.Visible = true
	local n = 0
	for _, c in pills:GetChildren() do
		if c:IsA("Frame") then
			n += 1
			c.Size = UDim2.new(1, 0, 0, h)
		end
	end
	local off = gui.AbsolutePosition
	pills.Size = UDim2.fromOffset(w, math.max(0, n * (h + PILL_GAP)))
	pills.Position = UDim2.fromOffset(right - off.X, top - PILL_GAP - off.Y)
end

local function syncPills()
	local now = workspace:GetServerTimeNow()
	local su = me:GetAttribute("BoostSpeedUntil")
	local sm = me:GetAttribute("BoostSpeedMult")
	pill("speed", 1, Theme.go, "boots", if typeof(su) == "number" and su > now and typeof(sm) == "number"
		then `Speed +{math.round((sm - 1) * 100)}%  {clock(su - now)}` else nil)
	local lu = me:GetAttribute("BoostLuckUntil")
	pill("luck", 2, Theme.events.luck or Theme.go, "star", if typeof(lu) == "number" and lu > now then `Lucky Ray  {clock(lu - now)}` else nil)
	local sl = workspace:GetAttribute("BoughtLuckUntil")
	pill("server", 3, Theme.skipAll, "sunburst", if typeof(sl) == "number" and sl > now then `Server Luck x{M.serverLuckMult}  {clock(sl - now)}` else nil)
	local sh = me:GetAttribute("BoostShields")
	pill("shield", 4, Theme.info, "lock", if typeof(sh) == "number" and sh > 0 then `Critter Shield x{sh}` else nil)
end

-- ---------- short on coins ----------
local needCount, needShown = 0, 0
local card: Frame

local function showNeedCard()
	card.Visible = true
	local shownAt = os.clock()
	card:SetAttribute("ShownAt", shownAt)
	task.delay(M.needOffer.seconds, function()
		if card:GetAttribute("ShownAt") == shownAt then
			card.Visible = false
		end
	end)
end

function OfferController.Init() end

function OfferController.Start()
	gui = Instance.new("ScreenGui")
	gui.Name = "Offers"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 4
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.Parent = me:WaitForChild("PlayerGui")
	-- Keep It Frozen, over the hotbar
	keepB = robuxButton(gui, "KeepFrozen", Theme.iceDeep, "Keep it frozen!", Config.robuxItem("keepFrozen"), "ray")
	keepB.root.AnchorPoint = Vector2.new(0.5, 1)
	keepB.root.Position = UDim2.fromScale(0.5, 0.82)
	keepB.root.Size = UDim2.fromScale(0.36, 0.09)
	aspect(keepB.root, 5.6) -- wide enough for "Keep it frozen!" on one line
	Ui.roundBlock(keepB, 0.5)
	-- what it does, small, over the button: the ice stops melting
	local keepSub = Ui.label(keepB.root, "Your cube is melting!", UDim2.fromScale(0.8, 0.4), UDim2.fromScale(0.1, -0.46))
	keepSub.TextColor3 = Theme.coin
	Instance.new("UIScale").Parent = keepB.root
	keepB.root.Visible = false
	-- the boost timers, bottom right over the clock
	pills = Instance.new("Frame")
	pills.Name = "BoostPills"
	pills.BackgroundTransparency = 1
	pills.AnchorPoint = Vector2.new(1, 1)
	pills.Position = UDim2.fromScale(0.985, 0.86)
	pills.Size = UDim2.fromScale(0.2, 0.2)
	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.VerticalAlignment = Enum.VerticalAlignment.Bottom
	list.Padding = UDim.new(0, PILL_GAP)
	game:GetService("RunService").RenderStepped:Connect(function()
		pcall(placePills)
	end)
	list.Parent = pills
	pills.Parent = gui
	-- the short-on-coins card, right side
	card = Instance.new("Frame")
	card.Name = "ShortOnCoins"
	card.BackgroundColor3 = Theme.panel
	card.BorderSizePixel = 0
	card.AnchorPoint = Vector2.new(1, 0.5)
	card.Position = UDim2.fromScale(0.925, 0.5) -- left of the Skins / Players column (2026-11-19)
	card.Size = UDim2.fromScale(0.24, 0.2)
	aspect(card, 2.2)
	Ui.corner(card, 0.18)
	Ui.stroke(card, 3)
	card.Visible = false
	card.Parent = gui
	-- owner 2026-11-21 ("make it better"): a coin pile, the title, and the X as a small round badge on the corner
	local pile = Ui.image(card, Config.images.icons.coin, UDim2.fromScale(0.16, 0.36), UDim2.fromScale(0.04, 0.06))
	pile.ZIndex = 2
	local title = Ui.inkLabel(card, "Short on coins?", UDim2.fromScale(0.72, 0.3), UDim2.fromScale(0.21, 0.09))
	title.TextXAlignment = Enum.TextXAlignment.Left
	local x = Ui.block(card, "Close", Theme.no, "X", function()
		card.Visible = false
	end)
	x.root.AnchorPoint = Vector2.new(0.5, 0.5)
	x.root.Position = UDim2.fromScale(0.97, 0.06)
	x.root.Size = UDim2.fromScale(0.15, 0.34)
	aspect(x.root, 1)
	Ui.roundBlock(x, 0.5)
	local bag = Config.robuxItem("coinsSmall")
	local buy = robuxButton(card, "CoinBag", Theme.coin, "Coin Bag", bag, "bag")
	buy.root.Position = UDim2.fromScale(0.05, 0.46)
	buy.root.Size = UDim2.fromScale(0.9, 0.44)
	State.Notify:Connect(function(kind: string, data: any)
		if kind == "notYet" and typeof(data) == "table" and typeof(data.reason) == "string"
			and string.find(data.reason, "^Need .+ more") and not string.find(data.reason, "Cold Power") then
			needCount += 1
			-- QA first 10 minutes (2026-11-19): never during the tutorial or a new player's first 2 minutes
			local v = State.view :: any
			local fresh = v == nil or (v.tutorial and not v.tutorial.done) or (v.extras and (v.extras.playSeconds or 0) < 120)
			if not fresh and needCount % M.needOffer.after == 0 and needShown < M.needOffer.max then
				needShown += 1
				showNeedCard()
			end
		elseif kind == "robuxBought" then
			card.Visible = false
		end
	end)
	task.spawn(function()
		while true do
			pcall(syncKeep)
			pcall(syncPills)
			task.wait(0.25)
		end
	end)
end

return OfferController
