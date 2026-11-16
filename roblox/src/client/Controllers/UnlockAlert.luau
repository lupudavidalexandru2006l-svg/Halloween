--!strict
-- UnlockAlert (owner 2026-11-12, from a reference): the first time this session you have the coins for
-- your next gun, a card slides in at the top right: "NEW EQUIPMENT!", the gun turning in a window, its
-- name, price and Cold Power, and a green Buy button that takes you to the Equipment Booth with that gun
-- picked. It waits while a cube is in your hands, a popup is open or a show plays, and goes away by itself
-- (Config.ui.unlockAlert). Only shows what's true; GunService still checks every buy.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Theme = require(ReplicatedStorage.Shared.Theme)
local Ui = require(script.Parent.Parent.Lib.Ui)
local State = require(script.Parent.State)
local Screen = require(script.Parent.Screen)
local SoundController = require(script.Parent.SoundController)
local SettingsController = require(script.Parent.SettingsController)
local PopupController = require(script.Parent.PopupController)
local EquipmentPopup = require(script.Parent.EquipmentPopup)

local UnlockAlert = {}
local A = Config.ui.unlockAlert
local G = Config.guns
local me = Players.LocalPlayer
local holder: Frame
local card: Frame? = nil
local shownFor: { [number]: boolean } = {} -- each gun alerts once per session
local showId = 0

local function reduced(): boolean
	return SettingsController.get("reducedMotion") == true
end

local function boothPos(): Vector3?
	for _, b in Config.world.booths do
		if b.action == "equipment" then
			return b.pos
		end
	end
	return nil
end

local function hide()
	local c = card
	card = nil
	showId += 1
	if c then
		local t = TweenService:Create(c, TweenInfo.new(A.slide * (if reduced() then 0.5 else 1), Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = UDim2.fromScale(1.3, 0) })
		t.Completed:Connect(function()
			c:Destroy()
		end)
		t:Play()
	end
end

-- Buy: off to the Equipment Booth (the same trip as the top Equipment button), and once you're there its
-- popup opens on this gun. It closes again if you walk away, like a booth opened with E.
local function goBuy(i: number)
	hide()
	SoundController.play("click")
	State.send("Teleport", "equipment")
	local at = boothPos()
	if not at then
		return
	end
	local center = at :: Vector3
	local function away(): number?
		local root = me.Character and me.Character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			return Vector2.new(root.Position.X - center.X, root.Position.Z - center.Z).Magnitude
		end
		return nil
	end
	local limit = G.boothRange - Config.boothLeaveMargin
	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < 3 do
			local d = away()
			if d and d <= limit then
				if not PopupController.isOpen() then
					PopupController.open("equipment", { tab = "guns", pick = i })
				end
				while PopupController.openName() == "equipment" do
					local now = away()
					if now and now > limit then
						PopupController.close()
						break
					end
					task.wait(0.25)
				end
				return
			end
			task.wait(0.1)
		end
	end)
end

local function show(i: number)
	hide()
	showId += 1
	local id = showId
	local g = G.list[i]
	local glow = (Theme.guns[i] or Theme.guns[1]).glow
	local c = Instance.new("Frame")
	c.Name = "Card"
	c.BackgroundTransparency = 1
	c.Size = UDim2.fromScale(1, 1)
	c.Position = UDim2.fromScale(1.3, 0)
	c.Parent = holder
	card = c
	-- the body: a deep navy block (like the boards), the header strip across its top in info blue
	local body = Ui.block(c, "Body", Theme.board, "", nil, true)
	body.root.Size = UDim2.fromScale(1, 1)
	body.text.Visible = false
	local head = Ui.block(body.face, "Header", Theme.info, "NEW EQUIPMENT!", nil)
	head.root.Size = UDim2.fromScale(1, 0.3)
	head.text.TextXAlignment = Enum.TextXAlignment.Left
	head.text.Position = UDim2.fromScale(0.04, 0.12)
	head.text.Size = UDim2.fromScale(0.74, 0.72)
	local close = Ui.block(head.face, "Close", Theme.no, "X", hide)
	close.root.AnchorPoint = Vector2.new(1, 0.5)
	close.root.Position = UDim2.fromScale(0.97, 0.5)
	close.root.Size = UDim2.fromScale(0.9, 0.84)
	local ca = Instance.new("UIAspectRatioConstraint")
	ca.DominantAxis = Enum.DominantAxis.Height
	ca.Parent = close.root
	-- the gun turning in a window in its glow colour
	local window = Instance.new("Frame")
	window.Name = "Window"
	window.BackgroundColor3 = glow:Lerp(Theme.white, 0.45)
	window.BorderSizePixel = 0
	window.Position = UDim2.fromScale(0.03, 0.36)
	window.Size = UDim2.fromScale(0.3, 0.58)
	Ui.corner(window)
	Ui.stroke(window, Config.ui.cardStroke)
	window.Parent = body.face
	EquipmentPopup.gunView(window, i, false, true)
	-- the Cold Power it trains, as a white pill on the window's corner: the power icon and "x2"
	local pill = Instance.new("Frame")
	pill.Name = "Power"
	pill.BackgroundColor3 = Theme.white
	pill.BorderSizePixel = 0
	pill.AnchorPoint = Vector2.new(1, 1)
	pill.Position = UDim2.fromScale(1.06, 1.08)
	pill.Size = UDim2.fromScale(0.62, 0.3)
	pill.ZIndex = 3
	Ui.corner(pill, 0.5)
	Ui.stroke(pill, Config.ui.cardStroke)
	pill.Parent = window
	local pi = Ui.image(pill, Config.images.icons.power, UDim2.fromScale(0.36, 0.9), UDim2.fromScale(0.03, 0.05))
	pi.ZIndex = 4
	local pt = Ui.inkLabel(pill, `x{g.training}`, UDim2.fromScale(0.56, 0.78), UDim2.fromScale(0.4, 0.11))
	pt.ZIndex = 4
	-- what it is: "You can now buy", the name, and the price with its coin
	local small = Ui.label(body.face, "YOU CAN NOW BUY", UDim2.fromScale(0.6, 0.12), UDim2.fromScale(0.37, 0.34))
	small.TextXAlignment = Enum.TextXAlignment.Left
	small.TextColor3 = Theme.ice
	local name = Ui.label(body.face, string.upper(g.name), UDim2.fromScale(0.6, 0.19), UDim2.fromScale(0.37, 0.47))
	name.TextXAlignment = Enum.TextXAlignment.Left
	Ui.image(body.face, Config.images.icons.coin, UDim2.fromScale(0.08, 0.22), UDim2.fromScale(0.365, 0.71))
	local price = Ui.label(body.face, Ui.price(g.price), UDim2.fromScale(0.2, 0.17), UDim2.fromScale(0.45, 0.735))
	price.TextXAlignment = Enum.TextXAlignment.Left
	price.TextColor3 = Theme.coin
	-- the one focal point: green Buy, breathing gently
	local buy = Ui.block(body.face, "Buy", Theme.go, "BUY", function()
		goBuy(i)
	end)
	buy.root.AnchorPoint = Vector2.new(1, 1)
	buy.root.Position = UDim2.fromScale(0.97, 0.95)
	buy.root.Size = UDim2.fromScale(0.27, 0.26) -- under the name, never over it
	if not reduced() then
		local s = Instance.new("UIScale")
		s.Parent = buy.root
		TweenService:Create(s, TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Scale = 1.06 }):Play()
	end
	SoundController.play("unlock")
	TweenService:Create(c, TweenInfo.new(A.slide * (if reduced() then 0.5 else 1), Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = UDim2.fromScale(0, 0) }):Play()
	task.delay(A.seconds, function()
		if showId == id then
			hide()
		end
	end)
end

local function check()
	local v = State.view
	-- not during the tutorial either (QA 2026-11-16: the card covered the first steps' goal)
	if not v or card or Screen.popupOpen or Screen.showHidden or Screen.menusLocked or me:GetAttribute("GunLocked") == true
		or (v.tutorial and not v.tutorial.done) then
		return
	end
	local best = me:GetAttribute("GunBest")
	local i = (if typeof(best) == "number" then math.floor(best) else 1) + 1
	local g = G.list[i]
	if g and not shownFor[i] and g.price > 0 and (v.rebirths or 0) >= g.rebirths and v.coins >= g.price then
		shownFor[i] = true
		show(i)
	end
end

function UnlockAlert.Init() end

function UnlockAlert.Start()
	holder = Instance.new("Frame")
	holder.Name = "UnlockAlert"
	holder.BackgroundTransparency = 1
	Screen.register("alert", holder)
	State.Changed:Connect(check)
	me:GetAttributeChangedSignal("GunBest"):Connect(function()
		if card then
			hide() -- bought it: the card has done its job
		end
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			check() -- a popup or a show just ended, or the cube left your hands
			if card and (Screen.popupOpen or Screen.showHidden) then
				hide()
			end
		end
	end)
end

return UnlockAlert
