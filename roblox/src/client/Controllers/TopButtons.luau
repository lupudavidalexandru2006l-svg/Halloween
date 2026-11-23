--!strict
-- TopButtons (owner 2026-11-12, from a reference): chunky labelled blocks at the very top, inside Roblox's
-- top bar (owner 2026-11-13; Screen falls back to the top centre where there is no top bar), that
-- take you somewhere in the hub (Config.ui.topButtons; TravelService decides). Equipment wears its
-- booth's blue; Pan is plain soil brown (owner 2026-11-12: no green strip on top, green means "go"). They go away while a cube
-- is in your hands ("GunLocked") and come back as soon as your hands are empty again: banked, melted or
-- grabbed by a Heat Critter (owner 2026-11-18: they waited until you walked into your pan, so after a critter
-- took your cube Pan and Equipment seemed broken). Screen places them (and hides them while a popup is open).

local Players = game:GetService("Players")
local TextService = game:GetService("TextService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Theme = require(ReplicatedStorage.Shared.Theme)
local Ui = require(script.Parent.Parent.Lib.Ui)
local State = require(script.Parent.State)
local Screen = require(script.Parent.Screen)
local SoundController = require(script.Parent.SoundController)
local PromptController = require(script.Parent.PromptController)
local TutorialGoal = require(script.Parent.TutorialGoal)

local TopButtons = {}
local TB = Config.ui.topButtons
local me = Players.LocalPlayer
local frame: Frame
local away = false -- a cube is in your hands: hidden until they're empty
local labels: { TextLabel } = {}
local widthPer100: { [TextLabel]: number } = {} -- each word's width at text size 100
local travel: { GuiObject } = {} -- the buttons that take you somewhere (they step aside while you carry)
local powerBtn: any = nil -- the Cold Power quick-buy (owner 2026-11-18): { root, amount, scale }
local powerUntil = 0 -- it shows only until this (os.clock) after a cube melted in your hands
local islandFill: Frame -- the "% to the next island" bar under the buttons (owner 2026-11-18)
local islandText: TextLabel
local powerTween: Tween? = nil

-- owner 2026-11-13: "PAN is bigger than EQUIPMENT". TextScaled grew the short word; now every label
-- uses the one size the longest word still fits at.
local function syncTextSize()
	local size = math.huge
	-- the menus' pop-in (Screen.lockMenus' UnlockPop UIScale) shrinks every AbsoluteSize while it plays: undo it,
	-- or the words were measured at 30% and stayed tiny (QA 2026-11-16, after the tutorial unlocked the menus)
	local pop = frame and frame:FindFirstChild("UnlockPop") :: UIScale?
	local k = if pop and pop.Scale > 0.05 then pop.Scale else 1
	for _, l in labels do
		local box = l.AbsoluteSize / k
		local w = widthPer100[l]
		if box.X <= 0 or not w then
			return
		end
		size = math.min(size, box.Y, box.X / w * 100)
	end
	-- owner 2026-11-22: "the equipment button says only EQUIPM". A fixed TextSize measured a beat too big
	-- wrapped the one long word mid-word and cut its end off. Now the shared size is only a ceiling: never
	-- wrapped, and TextScaled shrinks a word that still wouldn't fit
	for _, l in labels do
		l.TextWrapped = false
		l.TextScaled = true
		local c = l:FindFirstChild("SharedSize") :: UITextSizeConstraint?
		if not c then
			c = Instance.new("UITextSizeConstraint")
			;(c :: UITextSizeConstraint).Name = "SharedSize"
			;(c :: UITextSizeConstraint).Parent = l
		end
		;(c :: UITextSizeConstraint).MaxTextSize = math.max(1, math.floor(size))
	end
end

local function measure(l: TextLabel)
	local p = Instance.new("GetTextBoundsParams")
	p.Text = l.Text
	p.Font = l.FontFace
	p.Size = 100
	p.Width = 1e5
	local ok, bounds = pcall(TextService.GetTextBoundsAsync, TextService, p)
	widthPer100[l] = if ok then bounds.X * 1.06 else #l.Text * 62 -- a little room for the outline
end

local lockedAt = 0
local function update()
	-- hidden only once the cube has flown into your hands (owner 2026-11-16: it vanished before the cube arrived)
	local carrying = me:GetAttribute("GunLocked") == true and os.clock() - lockedAt >= Config.show.freeze.flySeconds
	if carrying then
		away = true
	elseif away and me:GetAttribute("GunLocked") ~= true then
		away = false
	end
	-- carrying: the travel buttons step aside; the Cold Power quick-buy shows only after a melt (owner 2026-11-18)
	for _, g in travel do
		g.Visible = not away
	end
	local showPower = powerBtn ~= nil and os.clock() < powerUntil
	if powerBtn and powerBtn.root.Visible ~= showPower then
		powerBtn.root.Visible = showPower
		if not showPower and powerTween then
			powerTween:Cancel()
			powerTween = nil
			powerBtn.scale.Scale = 1
		end
	end
	-- the island bar only while you train (owner 2026-11-18: "this should only appear when you are in the trainer")
	if islandFill then
		local training = me:GetAttribute("TrainLocked") == true or (me:GetAttribute("TrainStation") or 0) ~= 0
		-- QA 2026-11-22: the bar sat on the tutorial pill's words ("Click fast to fill..."); the pill has its own
		-- power bar, so the island bar waits while the tutorial pill shows
		local okPill, pillUp = pcall(TutorialGoal.visible)
		if okPill and pillUp then
			training = false
		end
		local bar = islandFill.Parent :: Frame
		if bar.Visible ~= training then
			bar.Visible = training
		end
		if powerBtn then -- the quick-buy sits right under the buttons when the bar is away
			local y = 1 + TB.power.gap + (if training then TB.bar.gap + TB.bar.height else 0)
			if powerBtn.root.Position.Y.Scale ~= y then
				powerBtn.root.Position = UDim2.fromScale(0.5, y)
			end
		end
	end
	local want = true -- the frame stays (bar, quick-buy); only the travel buttons step aside while you carry
	if frame:GetAttribute("Want") ~= want then
		frame:SetAttribute("Want", want)
	end
end

-- how much Cold Power the pack gives you right now (a share of your next island's need), and the island bar
local function refreshPower()
	local item = Config.robuxItem("powerSmall")
	local v = State.view
	if powerBtn and item and v then
		powerBtn.amount.Text = `+{Config.powerText(Config.powerPack(item, v.coldPower or 0))}`
	end
	if v and islandFill then
		local power = v.coldPower or 0
		local nextZone = Config.zone((v.reach or 1) + 1)
		local need = if nextZone and nextZone.need > 0 then nextZone.need else Config.nextNeed(power)
		local frac = math.clamp(power / math.max(1, need), 0, 1)
		islandFill.Size = UDim2.fromScale(math.max(frac, 0.04), 1)
		islandFill.BackgroundColor3 = if nextZone and frac >= 1 then Theme.go else Theme.training.power
		islandText.Text = if nextZone and frac >= 1 then `{nextZone.name}: READY!`
			elseif nextZone then `{math.floor(frac * 100)}% to {nextZone.name}`
			else `{math.floor(frac * 100)}% to Power Lv {Config.powerLevel(power) + 1}`
	end
end

-- the "% to the next island" bar, centred under EQUIPMENT and PAN (owner 2026-11-18)
local function makeIslandBar()
	local B = TB.bar
	local track = Instance.new("Frame")
	track.Name = "IslandBar"
	track.BackgroundColor3 = Theme.ink
	track.BackgroundTransparency = 0.2
	track.BorderSizePixel = 0
	track.AnchorPoint = Vector2.new(0.5, 0)
	track.Position = UDim2.fromScale(0.5, 1 + B.gap)
	track.Size = UDim2.fromScale(B.width, B.height)
	track.ClipsDescendants = true
	Ui.corner(track, 0.5)
	local ts = Instance.new("UIStroke")
	ts.Thickness = 2
	ts.Color = Theme.white
	ts.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	ts.Parent = track
	track.Parent = frame
	islandFill = Instance.new("Frame")
	islandFill.Name = "Fill"
	islandFill.BackgroundColor3 = Theme.training.power
	islandFill.BorderSizePixel = 0
	islandFill.Size = UDim2.fromScale(0.04, 1)
	Ui.corner(islandFill, 0.5)
	local shine = Instance.new("UIGradient")
	shine.Rotation = 90
	shine.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(190, 190, 190))
	shine.Parent = islandFill
	islandFill.Parent = track
	islandText = Ui.label(track, "", UDim2.fromScale(0.92, 0.84), UDim2.fromScale(0.04, 0.08))
	islandText.TextXAlignment = Enum.TextXAlignment.Center
	islandText.ZIndex = 2
end

-- your cube melted on the way home: the quick-buy pops up and pulses for powerShowSeconds (owner 2026-11-18)
local function pulsePower()
	if not powerBtn then
		return
	end
	powerUntil = os.clock() + TB.powerShowSeconds
	if not powerTween then
		local P = TB.powerPulse
		powerBtn.scale.Scale = 1
		powerTween = game:GetService("TweenService"):Create(powerBtn.scale,
			TweenInfo.new(P.seconds, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Scale = P.scale })
		;(powerTween :: Tween):Play()
	end
	update()
end

local function makeButton(i: number, b: { id: string, label: string, icon: string })
	-- the row is only the travel buttons (the quick-buy hangs under it), so they're centred
	local n = 0
	for _, x in TB.list do
		if not (x :: any).product then
			n += 1
		end
	end
	local product = (b :: any).product :: string?
	local colour = if b.id == "pan" then Theme.topButtons.soil
		elseif product then Theme.training.power else Theme.topButtons.equipment
	local block = Ui.block(frame, "Top_" .. b.id, colour, b.label, function()
		SoundController.play("click")
		if product then
			State.send("BuyRobux", product) -- Roblox's own prompt; the server checks and grants
		else
			State.send("Teleport", b.id)
			-- owner 2026-11-22: EQUIPMENT opens the booth by itself once you land there (no E press, and the
			-- tutorial's dark screen moves straight on to the Buy button)
			if b.id == "equipment" then
				task.spawn(function()
					local at = TB.equipment.at
					local t0 = os.clock()
					while os.clock() - t0 < 2 do
						task.wait(0.1)
						local root = me.Character and me.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
						if root and Vector2.new(root.Position.X - at.X, root.Position.Z - at.Z).Magnitude < 8 then
							PromptController.openBooth("equipment", "equipment")
							return
						end
					end
				end)
			end
		end
	end)
	-- each button's share of the row, the gap between them a share of the same short-side units
	local unit = 1 / (n * TB.size[1] + (n - 1) * TB.gap)
	block.root.Size = UDim2.fromScale(TB.size[1] * unit, 1)
	block.root.Position = UDim2.fromScale((i - 1) * (TB.size[1] + TB.gap) * unit, 0)
	local icon = Config.images.icons[b.icon]
	if icon then
		local img = Ui.image(block.face, icon, UDim2.fromScale(0.3, TB.iconSize), UDim2.fromScale(0.02, (1 - TB.iconSize) / 2))
		img.ZIndex = 2
	end
	local s = block.text:FindFirstChildOfClass("UIStroke") :: UIStroke
	s.Thickness = Config.ui.floatingStroke -- big words over a busy face read with a firmer outline
	if product then
		-- the amount on top (sized on its own), Roblox's Robux mark and the price under it
		local item = Config.robuxItem(product)
		block.text.Size = UDim2.fromScale(0.68, 0.52)
		block.text.Position = UDim2.fromScale(0.28, 0.04)
		block.text.ZIndex = 2
		block.text.TextScaled = true
		local mark = Ui.image(block.face, Config.images.icons.robux, UDim2.fromScale(0.14, 0.36), UDim2.fromScale(0.34, 0.58))
		mark.ZIndex = 2
		local price = Ui.label(block.face, if item then tostring(item.robux) else "", UDim2.fromScale(0.46, 0.38), UDim2.fromScale(0.5, 0.57))
		price.TextXAlignment = Enum.TextXAlignment.Left
		price.ZIndex = 2
		local sc = Instance.new("UIScale")
		sc.Parent = block.root
		-- under the island bar, centred (owner 2026-11-18)
		block.root.AnchorPoint = Vector2.new(0.5, 0)
		block.root.Position = UDim2.fromScale(0.5, 1 + TB.bar.gap + TB.bar.height + TB.power.gap)
		block.root.Size = UDim2.fromScale(TB.power.width, 1)
		powerBtn = { root = block.root, amount = block.text, scale = sc }
		block.root.Visible = false -- hidden until a cube melts (pulsePower)
		return
	end
	table.insert(travel, block.root)
	block.text.Size = UDim2.fromScale(0.68, 0.78)
	block.text.Position = UDim2.fromScale(0.28, 0.11)
	block.text.ZIndex = 2
	table.insert(labels, block.text)
	block.text:GetPropertyChangedSignal("AbsoluteSize"):Connect(syncTextSize)
end

function TopButtons.Init() end

function TopButtons.Start()
	frame = Instance.new("Frame")
	frame.Name = "TopButtons"
	frame.BackgroundTransparency = 1
	frame:SetAttribute("Want", true)
	local slot = 0
	for _, b in TB.list do
		if not (b :: any).product then
			slot += 1
		end
		makeButton(if (b :: any).product then 1 else slot, b)
	end
	makeIslandBar()
	Screen.register("top", frame)
	State.Changed:Connect(refreshPower)
	refreshPower()
	State.Notify:Connect(function(kind: string)
		if kind == "melted" then
			pulsePower()
		end
	end)
	task.spawn(function()
		for _, l in labels do
			measure(l)
		end
		syncTextSize()
	end)
	me:GetAttributeChangedSignal("GunLocked"):Connect(function()
		if me:GetAttribute("GunLocked") == true then
			lockedAt = os.clock()
			task.delay(Config.show.freeze.flySeconds + 0.02, update)
		end
		update()
	end)
	task.spawn(function()
		while true do
			update()
			task.wait(0.25)
		end
	end)
end

return TopButtons
