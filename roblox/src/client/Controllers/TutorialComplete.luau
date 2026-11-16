--!strict
-- TutorialComplete (2026-11-15, from the tutorial references: a lesson ends on a real moment, not a
-- line). A card in the popup layer: a trophy pops in over a turning sunburst, the lesson's title, the
-- coin reward counting up (the server already paid it, TutorialService), confetti, and a green OK (the
-- one focal point, gently pulsing). Waits for a show to finish first (the pan upgrade's trip). Enter /
-- gamepad A / a tap on OK closes it. Reduced motion: no spin, fewer confetti, no pulse.

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Theme = require(ReplicatedStorage.Shared.Theme)
local Ui = require(script.Parent.Parent.Lib.Ui)
local Screen = require(script.Parent.Screen)
local SoundController = require(script.Parent.SoundController)
local SettingsController = require(script.Parent.SettingsController)
local PopupController = require(script.Parent.PopupController)

local TutorialComplete = {}
local C = Config.tutorial.complete
local open: Frame? = nil

function TutorialComplete.isOpen(): boolean
	return open ~= nil
end

local function confetti(layer: Frame, reduced: boolean)
	local colors = { Theme.coin, Theme.go, Theme.info, Theme.tutorial.glow, Theme.white, Theme.tutorial.scarf }
	for i = 1, if reduced then C.confettiReduced else C.confetti do
		local p = Instance.new("Frame")
		p.Name = "Confetti"
		p.BorderSizePixel = 0
		p.BackgroundColor3 = colors[(i % #colors) + 1]
		p.AnchorPoint = Vector2.new(0.5, 0.5)
		p.Size = UDim2.fromScale(0.012 + math.random() * 0.01, 0.02 + math.random() * 0.016)
		p.Position = UDim2.fromScale(math.random(), -0.05 - math.random() * 0.2)
		p.Rotation = math.random(0, 360)
		p.ZIndex = 20
		p.Parent = layer
		local fall = C.fall[1] + math.random() * (C.fall[2] - C.fall[1])
		local tw = TweenService:Create(p, TweenInfo.new(fall, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Position = UDim2.fromScale(p.Position.X.Scale + (math.random() - 0.5) * 0.2, 1.1),
			Rotation = p.Rotation + math.random(-360, 360),
		})
		tw.Completed:Once(function()
			p:Destroy()
		end)
		tw:Play()
	end
end

-- title: the lesson's ("TUTORIAL COMPLETE!"); coins: what the server paid
function TutorialComplete.show(title: string, coins: number)
	if open then
		return
	end
	-- the pan upgrade's trip hides the popup layer: wait for it (never forever)
	local waited = 0
	while Screen.showHidden and waited < 20 do
		waited += task.wait(0.1)
	end
	local reduced = SettingsController.get("reducedMotion") == true
	-- one popup at a time (UI Rules): the Pan Upgrades popup it was earned in closes first
	if PopupController.isOpen() then
		PopupController.close()
	end
	local frame = Screen.popupFrame(false)
	frame.Name = "TutorialComplete"
	open = frame
	local layer = frame.Parent :: Instance
	-- a soft ink wash behind it, so the card is the only thing to look at
	local wash = Instance.new("Frame")
	wash.Name = "Wash"
	wash.BackgroundColor3 = Theme.ink
	wash.BackgroundTransparency = 0.55
	wash.AnchorPoint = Vector2.new(0.5, 0.5)
	wash.Position = UDim2.fromScale(0.5, 0.5)
	wash.Size = UDim2.fromScale(5, 5)
	wash.ZIndex = 0
	wash.Parent = frame
	local pop = Instance.new("UIScale")
	pop.Scale = if reduced then 1 else 0.4
	pop.Parent = frame
	-- the card: a cream panel in the middle of the popup space
	local card = Ui.block(frame, "Card", Theme.panel, "", nil, true)
	card.text.Visible = false
	card.root.AnchorPoint = Vector2.new(0.5, 0.5)
	card.root.Position = UDim2.fromScale(0.5, 0.56)
	card.root.Size = UDim2.fromScale(0.62, 0.62)
	-- the sunburst and the trophy over the card's top edge
	local sun = Ui.image(frame, Config.images.icons.sunburst, UDim2.fromScale(0.5, 0.62), UDim2.fromScale(0.25, -0.06))
	sun.ImageColor3 = Theme.coin
	sun.ImageTransparency = 0.25
	local trophy = Ui.image(frame, Config.images.icons.trophy, UDim2.fromScale(0.3, 0.38), UDim2.fromScale(0.35, 0.06))
	trophy.ZIndex = 3
	local tScale = Instance.new("UIScale")
	tScale.Scale = if reduced then 1 else 0.2
	tScale.Parent = trophy
	-- the title, then the coins
	local head = Ui.label(card.face, title, UDim2.fromScale(0.9, 0.24), UDim2.fromScale(0.05, 0.3))
	head.Name = "Title"
	local row = Instance.new("Frame")
	row.Name = "Coins"
	row.BackgroundTransparency = 1
	row.Position = UDim2.fromScale(0.25, 0.54)
	row.Size = UDim2.fromScale(0.5, 0.18)
	row.Parent = card.face
	Ui.image(row, Config.images.icons.coin, UDim2.fromScale(0.3, 1), UDim2.fromScale(0, 0))
	local amount = Ui.label(row, "+0", UDim2.fromScale(0.68, 1), UDim2.fromScale(0.3, 0))
	amount.Name = "Amount"
	amount.TextColor3 = Theme.coin
	amount.TextXAlignment = Enum.TextXAlignment.Left
	-- OK: the one focal point
	local closing = false
	local function close()
		if closing then
			return
		end
		closing = true
		ContextActionService:UnbindAction("IceRay_TutorialCompleteOk")
		if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(frame) then
			GuiService.SelectedObject = nil
		end
		SoundController.play("click")
		local function gone()
			frame:Destroy()
			if open == frame then
				open = nil
			end
		end
		if reduced then
			gone()
		else
			local tw = TweenService:Create(pop, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0.85 })
			tw.Completed:Once(gone)
			tw:Play()
		end
	end
	local ok = Ui.block(card.face, "Ok", Theme.go, "OK", close)
	ok.root.AnchorPoint = Vector2.new(0.5, 0)
	ok.root.Position = UDim2.fromScale(0.5, 0.76)
	ok.root.Size = UDim2.fromScale(0.36, 0.2)
	ContextActionService:BindActionAtPriority("IceRay_TutorialCompleteOk", function(_, state: Enum.UserInputState)
		if state == Enum.UserInputState.Begin then
			close()
			return Enum.ContextActionResult.Sink
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.ContextActionPriority.High.Value + 10, Enum.KeyCode.Return, Enum.KeyCode.ButtonA)
	-- in: pop, trophy, confetti, coins counting up
	SoundController.play(Config.tutorial.sounds.finish)
	if not reduced then
		TweenService:Create(pop, TweenInfo.new(C.pop, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		task.delay(C.pop * 0.6, function()
			TweenService:Create(tScale, TweenInfo.new(C.pop * 1.4, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		end)
		local ps = Instance.new("UIScale")
		ps.Parent = ok.root
		TweenService:Create(ps, TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Scale = 1.07 }):Play()
	end
	if layer:IsA("GuiBase2d") then
		local full = Instance.new("Frame")
		full.Name = "ConfettiLayer"
		full.BackgroundTransparency = 1
		full.Size = UDim2.fromScale(1, 1)
		full.Parent = frame
		confetti(full, reduced)
	end
	task.spawn(function()
		local t0 = os.clock()
		local last = -1
		while open == frame do
			local k = math.clamp((os.clock() - t0) / C.countSeconds, 0, 1)
			local n = math.floor(coins * (1 - (1 - k) ^ 3))
			if n ~= last then
				last = n
				amount.Text = "+" .. Ui.commas(n)
			end
			if k >= 1 then
				break
			end
			RunService.RenderStepped:Wait()
		end
		SoundController.play("coin")
	end)
	if not reduced then
		task.spawn(function()
			while open == frame and sun.Parent do
				sun.Rotation = (sun.Rotation + RunService.RenderStepped:Wait() * C.sunSpin) % 360
			end
		end)
	end
	-- gamepad: OK is selected, so A works through the normal selection too
	ok.face.Selectable = true
	if GuiService:IsTenFootInterface() then
		GuiService.SelectedObject = ok.face
	end
end

return TutorialComplete
