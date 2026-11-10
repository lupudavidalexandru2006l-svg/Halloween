--!strict
-- TrainingController (Cold Power remake, 2026-11-10): the Training Rink on this client. The server
-- (TrainingService) decides everything; this only draws and sends intent.
--   Fire sprites: a candy-orange flame with a face on each of MY sprite roots in workspace.RinkSprites
--     (other players' rinks are far away and not drawn). It hops toward the sculpture, ice creeps up it
--     with its Meter, and it ends in a puff: frozen (+N floats up) or run off. Part-built stand-ins
--     until a painted sprite is turned into 3D (like the stand-in guns). Cute, never scary: big eyes,
--     pink cheeks, no teeth.
--   HUD (Figma "Chunky Pop Icons" > Training Rink HUD; Screen places it): the sprites-left bar with the
--     combo, Auto and Exit on the right edge, and the result card ("+45K Cold Power!", AGAIN, EXIT).
--     Read from the player's InRink / RinkLeft / RinkCombo / RinkAuto / RinkState attributes.
-- Shooting is RayController's job: sprites are one more kind of target for the ray.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Theme = require(ReplicatedStorage.Shared.Theme)
local Ui = require(script.Parent.Parent.Lib.Ui)
local State = require(script.Parent.State)
local Screen = require(script.Parent.Screen)
local InputController = require(script.Parent.InputController)
local SettingsController = require(script.Parent.SettingsController)
local SoundController = require(script.Parent.SoundController)
local EffectsController = require(script.Parent.EffectsController)

local TrainingController = {}
local R = Config.rink
local RK = Config.ui.rink
local T = Theme.rink
local me = Players.LocalPlayer

type Look = { model: Model, ice: Part, shadow: Part, size: number, phase: number, at: CFrame, centre: Vector3 }
local looks: { [BasePart]: Look } = {}
local folder: Folder

local function reduced(): boolean
	return SettingsController.get("reducedMotion") == true
end

-- ---------- fire sprites ----------
local function piece(shape: Enum.PartType, size: Vector3, color: Color3, parent: Instance, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Shape = shape
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- a flame built from three stacked balls, a lighter belly, and a face on its front (-Z): big ink
-- eyes with a white glint, pink cheeks, a small round mouth
local function buildSprite(s: number, golden: boolean): Model
	local m = Instance.new("Model")
	m.Name = "FireSprite"
	local main, belly = if golden then T.golden else T.flame, if golden then T.goldenCore else T.flameCore
	local function ball(d: number, at: Vector3, color: Color3, material: Enum.Material?): Part
		local p = piece(Enum.PartType.Ball, Vector3.one * d * s, color, m, material)
		p.CFrame = CFrame.new(at * s)
		return p
	end
	local body = ball(1, Vector3.zero, main)
	body.Name = "Body"
	ball(0.66, Vector3.new(0.03, 0.38, 0), main)
	ball(0.36, Vector3.new(0.08, 0.72, 0), belly, Enum.Material.Neon)
	ball(0.64, Vector3.new(0, -0.1, -0.22), belly)
	for _, x in { -1, 1 } do
		ball(0.15, Vector3.new(x * 0.17, 0.1, -0.44), T.face)
		ball(0.055, Vector3.new(x * 0.15, 0.14, -0.5), Theme.white)
		ball(0.13, Vector3.new(x * 0.3, -0.06, -0.41), T.cheek)
	end
	ball(0.07, Vector3.new(0, -0.05, -0.5), T.face)
	local light = Instance.new("PointLight")
	light.Color = main
	light.Range = s * 3.5
	light.Brightness = 0.9
	light.Shadows = false
	light.Parent = body
	if golden then -- a golden sprite twinkles, so it reads as "worth more" from across the rink
		local e = Instance.new("ParticleEmitter")
		e.Color = ColorSequence.new(Theme.white, T.golden)
		e.LightEmission = 1
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.4, 0.35), NumberSequenceKeypoint.new(1, 0) })
		e.Lifetime = NumberRange.new(0.5, 0.9)
		e.Rate = 10
		e.Speed = NumberRange.new(1, 2.5)
		e.SpreadAngle = Vector2.new(180, 180)
		e.Parent = body
	end
	m.PrimaryPart = body
	m.Parent = folder
	return m
end

local function add(root: Instance)
	if not root:IsA("BasePart") or looks[root] or root:GetAttribute("OwnerUserId") ~= me.UserId then
		return
	end
	local kind = root:GetAttribute("Kind")
	local k = R.kinds[if typeof(kind) == "string" then kind else "small"] or R.kinds.small
	local s = k.size
	local index = me:GetAttribute("RinkIndex")
	local centre = Config.rinkCentre(if typeof(index) == "number" then index else 1)
	local ice = piece(Enum.PartType.Block, Vector3.one, Theme.ice, folder)
	ice.Name = "SpriteIce"
	ice.Transparency = 1
	local shadow = piece(Enum.PartType.Cylinder, Vector3.new(0.08, s, s), Theme.ink, folder)
	shadow.Name = "SpriteShadow"
	shadow.Transparency = 0.72
	looks[root] = { model = buildSprite(s, root:GetAttribute("Golden") == true), ice = ice, shadow = shadow, size = s, phase = math.random() * 6, at = root.CFrame, centre = centre }
end

local function remove(root: Instance)
	local l = looks[root :: BasePart]
	if l then
		l.model:Destroy()
		l.ice:Destroy()
		l.shadow:Destroy()
		looks[root :: BasePart] = nil
	end
end

local function step(dt: number)
	local t = os.clock()
	local still = reduced()
	for root, l in looks do
		if not root.Parent then
			remove(root)
			continue
		end
		local meter = (root:GetAttribute("Meter") or 0) :: number
		local s = l.size
		-- glide after the server's root; hop along (smaller as the ice climbs; none with reduced motion)
		l.at = l.at:Lerp(root.CFrame, math.min(1, dt * 12))
		local pos = l.at.Position
		local ground = pos.Y - s / 2
		local hop = if still then 0 else math.abs(math.sin(t * 7 + l.phase)) * 0.42 * s * (1 - meter)
		local at = Vector3.new(pos.X, pos.Y + hop, pos.Z)
		local toward = Vector3.new(l.centre.X, at.Y, l.centre.Z)
		l.model:PivotTo(if (toward - at).Magnitude > 0.05 then CFrame.lookAt(at, toward) else CFrame.new(at))
		-- a soft shadow on the ice, smaller while it's in the air
		local sh = s * (0.95 - 0.35 * hop / math.max(0.01, 0.42 * s))
		l.shadow.Size = Vector3.new(0.08, sh, sh)
		l.shadow.CFrame = CFrame.new(pos.X, ground + 0.3, pos.Z) * CFrame.Angles(0, 0, math.pi / 2)
		if meter > 0 then
			local h = s * 1.5 * meter
			l.ice.Size = Vector3.new(s * 1.2, math.max(0.05, h), s * 1.2)
			l.ice.CFrame = CFrame.new(pos.X, ground + h / 2 + hop, pos.Z)
			l.ice.Transparency = 0.45
		else
			l.ice.Transparency = 1
		end
	end
end

-- "+120" floating up from a frozen sprite, in the Cold Power colour (gold for a golden one)
local function floatGain(at: Vector3, amount: number, golden: boolean)
	local holder = Instance.new("Part")
	holder.Anchored, holder.CanCollide, holder.CanQuery, holder.CanTouch = true, false, false, false
	holder.Transparency = 1
	holder.Size = Vector3.one * 0.2
	holder.CFrame = CFrame.new(at)
	holder.Parent = folder
	local g = Instance.new("BillboardGui")
	g.AlwaysOnTop = true
	g.LightInfluence = 0
	g.Size = UDim2.fromOffset(RK.gainPx * 6, RK.gainPx * 1.4)
	g.StudsOffset = Vector3.new(0, 1.5, 0)
	g.Adornee = holder
	local text = Ui.label(g, `+{Config.coinText(amount)}`, UDim2.fromScale(1, 1), UDim2.fromScale(0, 0))
	text.TextColor3 = if golden then Theme.coin else T.power
	local stroke = text:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Thickness = Config.ui.floatingStroke
	end
	g.Parent = holder
	local seconds = EffectsController.time(RK.gainSeconds)
	local info = TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	if not reduced() then
		TweenService:Create(g, info, { StudsOffset = Vector3.new(0, 1.5 + RK.gainRise, 0) }):Play()
	end
	local fade = TweenInfo.new(seconds * 0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, seconds * 0.6)
	TweenService:Create(text, fade, { TextTransparency = 1 }):Play()
	if stroke then
		TweenService:Create(stroke, fade, { Transparency = 1 }):Play()
	end
	task.delay(seconds + 0.05, function()
		holder:Destroy()
	end)
end

-- ---------- the rink HUD ----------
local bar: Frame
local barFill: Frame
local barText: TextLabel
local comboText: TextLabel
local buttons: Frame
local autoBlock: Ui.Block
local autoSub: TextLabel
local boostBlock: Ui.Block -- the Full-Speed Auto-Train pass (Robux), only while you don't own it
local exitBlock: Ui.Block
local result: Frame? = nil
local inRink = false

local function recolor(b: Ui.Block, color: Color3)
	b.face.BackgroundColor3 = color
	b.root.BackgroundColor3 = Ui.darker(color)
end

local function hideResult()
	if result then
		result:Destroy()
		result = nil
	end
end

-- the result card: what the wave gave, a big green AGAIN (the one focal point), a smaller EXIT
local function showResult(data: any)
	hideResult()
	local frame = Screen.popupFrame(false)
	frame.Name = "RinkResult"
	-- smaller than a menu popup: a short reward card that stays clear of the hotbar and the bar
	frame.Size = UDim2.fromScale(frame.Size.X.Scale * RK.resultShare, frame.Size.Y.Scale * RK.resultShare)
	result = frame
	local tint = Theme.booths.rink:Lerp(Theme.white, Config.ui.panelTint)
	local panel = Ui.block(frame, "Panel", tint, "", nil, true)
	panel.root.Size = UDim2.fromScale(1, 1)
	panel.text.Visible = false
	local ribbon = Instance.new("Frame")
	ribbon.Name = "Ribbon"
	ribbon.BackgroundColor3 = Theme.booths.rink
	ribbon.BorderSizePixel = 0
	ribbon.Size = UDim2.fromScale(1, 0.2)
	Ui.corner(ribbon)
	ribbon.Parent = panel.face
	Ui.label(ribbon, "WAVE DONE", UDim2.fromScale(0.9, 0.62), UDim2.fromScale(0.05, 0.19))
	local gained = if typeof(data.gained) == "number" then data.gained else 0
	local gain = Ui.inkLabel(panel.face, `+{Config.coinText(gained)} Cold Power!`, UDim2.fromScale(0.9, 0.2), UDim2.fromScale(0.05, 0.25))
	gain.Name = "Gain"
	local detail = Ui.inkLabel(panel.face, `{tostring(data.frozen)} of {tostring(data.total)} frozen`, UDim2.fromScale(0.9, 0.09), UDim2.fromScale(0.05, 0.47))
	detail.Name = "Detail"
	detail.TextColor3 = Theme.ink:Lerp(Theme.white, 0.35)
	local again = Ui.block(panel.face, "Again", Theme.go, "AGAIN", function()
		SoundController.play("click")
		State.send("Rink", "again")
		hideResult()
	end)
	again.root.Position = UDim2.fromScale(0.18, 0.6)
	again.root.Size = UDim2.fromScale(0.44, 0.3)
	local exit = Ui.block(panel.face, "Exit", Theme.no, "EXIT", function()
		SoundController.play("click")
		State.send("Rink", "leave")
	end)
	exit.root.Position = UDim2.fromScale(0.67, 0.66)
	exit.root.Size = UDim2.fromScale(0.2, 0.2)
	if not reduced() then -- the next action pulses gently
		local sc = Instance.new("UIScale")
		sc.Parent = again.root
		TweenService:Create(sc, TweenInfo.new(RK.againPulse.seconds, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Scale = RK.againPulse.scale }):Play()
	end
	InputController.select(again.face) -- gamepad: A plays again (B leaves, below)
	SoundController.play("challenge")
end

-- the side column: Auto, the pass button while you don't own it, Exit (Screen sizes the column from "Slots")
local function placeButtons()
	local item = Config.robuxItem("autoTrain")
	local canBuy = item ~= nil and me:GetAttribute("Pass_autoTrain") ~= true and (Config.robuxReady(item) or RunService:IsStudio())
	local n = if canBuy then 3 else 2
	local total = RK.buttonSize * n + RK.buttonGap * (n - 1)
	local share, stepY = RK.buttonSize / total, (RK.buttonSize + RK.buttonGap) / total
	boostBlock.root.Visible = canBuy
	for i, b in { autoBlock, boostBlock, exitBlock } do
		b.root.Size = UDim2.fromScale(1, share)
		b.root.Position = UDim2.fromScale(0, stepY * (if i == 3 then n - 1 else i - 1))
	end
	if buttons:GetAttribute("Slots") ~= n then
		buttons:SetAttribute("Slots", n)
	end
end

local function refresh()
	placeButtons()
	local now = me:GetAttribute("InRink") == true
	if now ~= inRink then
		inRink = now
		Screen.setRinkMode(now)
		if not now then
			hideResult()
		end
	end
	if not now then
		return
	end
	local left = me:GetAttribute("RinkLeft")
	local n = if typeof(left) == "number" then left else 0
	barText.Text = tostring(n)
	barFill.Size = UDim2.fromScale(math.clamp(n / R.waveSize, 0, 1), 1)
	barFill.Visible = n > 0
	local combo = me:GetAttribute("RinkCombo")
	local c = if typeof(combo) == "number" then combo else 1
	comboText.Visible = c > 1
	comboText.Text = `x{string.format("%.1f", c)}`
	local on = me:GetAttribute("RinkAuto") == true
	recolor(autoBlock, if on then Theme.go else Theme.info)
	local rate = if me:GetAttribute("Pass_autoTrain") == true then R.autoPass else R.autoFree
	autoSub.Text = `{math.round(rate * 100)}%`
end

local function buildHud()
	bar = Instance.new("Frame")
	bar.Name = "RinkBar"
	bar.BackgroundTransparency = 1
	bar.Visible = false
	local track = Instance.new("Frame")
	track.Name = "Track"
	track.BackgroundColor3 = Theme.ink:Lerp(Theme.white, Config.ui.barTrackAlpha)
	track.BorderSizePixel = 0
	track.Size = UDim2.fromScale(1, 1)
	Ui.corner(track, 1)
	Ui.stroke(track)
	track.Parent = bar
	barFill = Instance.new("Frame")
	barFill.Name = "Fill"
	barFill.BackgroundColor3 = T.flame
	barFill.BorderSizePixel = 0
	barFill.Size = UDim2.fromScale(1, 1)
	Ui.corner(barFill, 1)
	barFill.Parent = track
	barText = Ui.label(bar, "", UDim2.fromScale(1, 0.82), UDim2.fromScale(0, 0.09))
	barText.Name = "Left"
	barText.ZIndex = 2
	-- the combo sits just past the bar's right end, in reward yellow, only while it's above x1
	comboText = Ui.label(bar, "", UDim2.fromScale(RK.comboWidth / RK.barSize[1], 1.5), UDim2.fromScale(1.03, -0.25))
	comboText.Name = "Combo"
	comboText.TextXAlignment = Enum.TextXAlignment.Left
	comboText.TextColor3 = Theme.coin
	comboText.Visible = false
	local cs = comboText:FindFirstChildOfClass("UIStroke")
	if cs then
		cs.Thickness = Config.ui.floatingStroke
	end
	Screen.register("rinkBar", bar)

	buttons = Instance.new("Frame")
	buttons.Name = "RinkButtons"
	buttons.BackgroundTransparency = 1
	buttons.Visible = false
	autoBlock = Ui.block(buttons, "Auto", Theme.info, "AUTO", function()
		SoundController.play("click")
		State.send("Rink", "auto", me:GetAttribute("RinkAuto") ~= true)
	end)
	autoBlock.text.Size = UDim2.fromScale(0.9, 0.36)
	autoBlock.text.Position = UDim2.fromScale(0.05, 0.14)
	autoSub = Ui.label(autoBlock.face, "", UDim2.fromScale(0.9, 0.3), UDim2.fromScale(0.05, 0.54))
	autoSub.Name = "Speed"
	-- the pass: a small side button with Roblox's Robux mark (Child Safety: never a pop-up, never a
	-- countdown; free Auto keeps working). The server shows Roblox's own purchase prompt.
	boostBlock = Ui.block(buttons, "Boost", Theme.shopCards.pass, "100%", function()
		SoundController.play("click")
		State.send("BuyRobux", "autoTrain")
	end)
	boostBlock.text.Size = UDim2.fromScale(0.9, 0.32)
	boostBlock.text.Position = UDim2.fromScale(0.05, 0.56)
	Ui.image(boostBlock.face, Config.images.icons.robux, UDim2.fromScale(0.5, 0.42), UDim2.fromScale(0.25, 0.1))
	exitBlock = Ui.block(buttons, "Exit", Theme.no, "EXIT", function()
		SoundController.play("click")
		State.send("Rink", "leave")
	end)
	exitBlock.text.Size = UDim2.fromScale(0.9, 0.4)
	exitBlock.text.Position = UDim2.fromScale(0.05, 0.3)
	placeButtons()
	Screen.register("rinkButtons", buttons)
end

local function onRink(data: any)
	if typeof(data) ~= "table" then
		return
	end
	local what = data.what
	if what == "gain" and typeof(data.at) == "Vector3" and typeof(data.gain) == "number" then
		EffectsController.burst(data.at, if data.golden == true then T.golden else Theme.ice, 8)
		floatGain(data.at, data.gain, data.golden == true)
		SoundController.play("tink")
	elseif what == "escaped" then
		local index = me:GetAttribute("RinkIndex")
		local centre = Config.rinkCentre(if typeof(index) == "number" then index else 1)
		EffectsController.burst(centre + Vector3.new(0, 3, R.sculptureRadius), T.flame, 6) -- a puff where it ran off
		SoundController.play("bounce")
	elseif what == "done" then
		if data.auto ~= true then
			showResult(data)
		end
	elseif what == "wave" or what == "leave" then
		hideResult()
	end
end

function TrainingController.Init()
	folder = Instance.new("Folder")
	folder.Name = "RinkVisuals"
	folder.Parent = workspace
end

function TrainingController.Start()
	buildHud()
	for _, name in { "InRink", "RinkLeft", "RinkCombo", "RinkAuto", "RinkState", "Pass_autoTrain" } do
		me:GetAttributeChangedSignal(name):Connect(refresh)
	end
	refresh()
	State.Notify:Connect(function(kind: string, data: any)
		if kind == "rink" then
			onRink(data)
		end
	end)
	UserInputService.InputBegan:Connect(function(input: InputObject)
		if result and input.KeyCode == Config.ui.gamepadKeys.close then
			State.send("Rink", "leave") -- gamepad B on the result card
		end
	end)
	task.spawn(function()
		local f = workspace:WaitForChild("RinkSprites", 30)
		if not f then
			return
		end
		f.ChildAdded:Connect(function(c)
			task.defer(add, c) -- its attributes arrive with it; one beat later to be safe
		end)
		f.ChildRemoved:Connect(remove)
		for _, c in f:GetChildren() do
			add(c)
		end
	end)
	RunService.RenderStepped:Connect(step)
end

return TrainingController
