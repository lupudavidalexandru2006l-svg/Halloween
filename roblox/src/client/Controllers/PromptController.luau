--!strict
-- PromptController: draws every world prompt (they use ProximityPromptStyle.Custom) as a Chunky Pop
-- pill floating on its object: a keycap (E / X / Tap / Hold), what it does, what it's on and a hold sweep.
-- On touch the block itself is the hold button. The server still decides what a prompt does.
-- Also hides prompts that can't do anything for you right now (open gate, gift before the first bank,
-- another player's Pan Upgrades), and runs the booth prompts (Round 4 phase 2: each booth opens what
-- it can so far; its own feature comes in a later phase).


local ProximityPromptService = game:GetService("ProximityPromptService")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Theme = require(ReplicatedStorage.Shared.Theme)
local Ui = require(script.Parent.Parent.Lib.Ui)
local State = require(script.Parent.State)
local InputController = require(script.Parent.InputController)
local PopupController = require(script.Parent.PopupController)
local Screen = require(script.Parent.Screen)
local SettingsController = require(script.Parent.SettingsController)

local PromptController = {}
local playerGui: Instance
-- key = the keycap's face; held = the key is down for a hold; lift = studs over its attachment
local shown: { [ProximityPrompt]: { gui: Frame, bar: Frame, key: GuiObject, held: boolean, lift: number, conns: { RBXScriptConnection } } } = {}
local layer: ScreenGui -- every world prompt, under the HUD (Hud = 1) and popups

local P = Theme.prompt
local K = Config.ui.promptKey

-- the keycap's face drops onto its lip (a press); unless it's held down, it springs back up
local function keyDown(face: GuiObject, hold: boolean)
	local down = TweenService:Create(face, TweenInfo.new(K.down), { Position = UDim2.fromScale(0, 1 - face.Size.Y.Scale) })
	down:Play()
	if not hold then
		down.Completed:Once(function()
			TweenService:Create(face, TweenInfo.new(K.up, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = UDim2.fromScale(0, 0) }):Play()
		end)
	end
end

local function keyUp(face: GuiObject)
	TweenService:Create(face, TweenInfo.new(K.up, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = UDim2.fromScale(0, 0) }):Play()
end

-- v3 (owner 2026-11-13: "green is not a good choice, improve the E UI"): a chunky white keycap with the
-- key on it, standing over the left end of a deep indigo pill; the action big in white, what it's on
-- small in ice blue under it. The key taps itself down now and then ("press me"), goes down for real
-- when you press or hold, and the pill fills with an ice sweep while you hold. Pops in when it appears.
local function show(prompt: ProximityPrompt)
	if shown[prompt] then
		return
	end
	-- a screen frame pinned to its object every frame (stepPrompts), not a BillboardGui: in this place an
	-- AlwaysOnTop billboard never draws at all (2026-11-12, checked again 2026-11-13 with every post
	-- effect off), and a depth-tested one hid behind fences, awnings and your own body, where it also
	-- couldn't be tapped (owner 2026-11-13: "you cannot see it in some places")
	local gui = Instance.new("Frame")
	gui.Name = "Prompt"
	gui.BackgroundTransparency = 1
	gui.AnchorPoint = Vector2.new(0.5, 0.5)
	gui.Visible = false -- until stepPrompts has put it on its object
	-- a fixed screen size (a share of the short side), so it never fills the screen up close
	local cam = workspace.CurrentCamera
	local short = if cam then math.min(cam.ViewportSize.X, cam.ViewportSize.Y) else 720
	local ps = Config.ui.promptSize
	local compact = prompt:GetAttribute("Compact") == true
	local k = if compact then Config.ui.promptCompact else 1
	if InputController.device() == "touch" then
		-- a thumb has to hit it (mobile QA 2026-11-10: the compact Pick up was 26 px tall on a phone); the
		-- width grows with it, so the pill keeps its shape
		local floor = Config.ui.minTouchPx * (if compact then 0.87 else 1)
		k = math.max(k, floor / (ps[2] * short))
	end
	gui.Size = UDim2.fromOffset(ps[1] * short * k, ps[2] * short * k)
	local lift = Config.ui.promptLift -- studs over its attachment: over your head, not at chest height
	if compact then
		lift = 0
		gui.AnchorPoint = Vector2.new(0.5, 1.1) -- its bottom edge rests on the attachment (the top of a frozen pet's cube)
	end
	local reduced = SettingsController.get("reducedMotion") == true
	-- everything in one holder, so the prompt pops in as one piece
	local holder = Instance.new("Frame")
	holder.Name = "Holder"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromScale(1, 1)
	holder.Parent = gui
	local pop = Instance.new("UIScale")
	pop.Parent = holder
	local baseW, baseH = gui.Size.X.Offset, gui.Size.Y.Offset
	local bodyY, bodyH = 0.1, 0.8 -- the pill is a little shorter than the key, so the key stands proud of it
	-- the pill: see-through so a pet under it stays in view (owner 2026-10-31). A CanvasGroup fades it as
	-- one layer (fading face and lip apart went dark where they overlap); the key and words sit above it
	-- and stay solid. The margin keeps the outline from being clipped.
	local m = Config.ui.stroke + 1
	local fade = Instance.new("CanvasGroup")
	fade.Name = "Fade"
	fade.BackgroundTransparency = 1
	fade.ZIndex = 1
	-- solid where nothing under it needs to show: a hold prompt (a gate) and a compact one (on a cube)
	fade.GroupTransparency = if compact or prompt.HoldDuration > 0 then 0 else Config.ui.promptFade
	fade.Parent = holder
	local b = Ui.block(fade, "Block", P.body, "", nil)
	b.root.Position = UDim2.fromOffset(m, m)
	b.root.Size = UDim2.new(1, -2 * m, 1, -2 * m)
	b.text.Visible = false
	Ui.roundBlock(b, 0.5)
	-- the hold sweep: over the pill (inside the faded pill it was too faint to see: owner 2026-11-12),
	-- under the key and the words; it fills its track left to right
	local track = Instance.new("Frame")
	track.Name = "Track"
	track.BackgroundTransparency = 1
	track.ZIndex = 2
	track.Parent = holder
	local bar = Instance.new("Frame")
	bar.Name = "Hold"
	bar.BackgroundColor3 = P.sweep
	bar.BackgroundTransparency = Config.ui.promptHoldFill
	bar.BorderSizePixel = 0
	bar.Size = UDim2.fromScale(0, 1)
	Ui.corner(bar, 0.5)
	bar.Parent = track
	-- the keycap: a white Chunky Pop block (its lip is the key's side), the key in ink
	local key = Ui.block(holder, "Key", P.key, InputController.keyHint(prompt), nil)
	key.root.ZIndex = 3
	Ui.roundBlock(key, 0.28)
	local keyText = key.text
	keyText.TextColor3 = Theme.ink
	local ks = keyText:FindFirstChildOfClass("UIStroke")
	if ks then
		ks.Enabled = false
	end
	keyText.Size = UDim2.fromScale(0.76, 0.6)
	keyText.Position = UDim2.fromScale(0.12, 0.16)
	-- the words
	local hasObject = prompt.ObjectText ~= ""
	local action = Ui.label(holder, prompt.ActionText, UDim2.fromScale(0.6, if hasObject then 0.4 else 0.5), UDim2.fromScale(0.35, if hasObject then 0.15 else 0.22))
	action.Name = "Action"
	action.ZIndex = 4
	action.TextXAlignment = Enum.TextXAlignment.Left
	local what: TextLabel? = nil
	if hasObject then
		local w = Ui.label(holder, prompt.ObjectText, UDim2.fromScale(0.6, 0.24), UDim2.fromScale(0.35, 0.54))
		w.Name = "What"
		w.ZIndex = 4
		w.TextXAlignment = Enum.TextXAlignment.Left
		w.TextColor3 = P.object
		what = w
	end
	-- "Tap" / "Hold" on touch gets a wider key, and the prompt grows by the extra width so the words keep
	-- their room (QA 2026-11-13: squeezed to a sliver on a phone). The pill starts under the key's middle
	-- and the words right after the key, so a wide key never covers them (final QA 2026-11-03)
	local function fitKey()
		local keyPx = baseH * (if #keyText.Text > 1 then 1.55 else 1)
		local w = baseW + keyPx - baseH
		gui.Size = UDim2.fromOffset(w, baseH)
		local kw = keyPx / w
		key.root.Size = UDim2.fromScale(kw, 1)
		local bodyX = kw * 0.5
		fade.Position = UDim2.new(bodyX, -m, bodyY, -m)
		fade.Size = UDim2.new(1 - bodyX, 2 * m, bodyH, 2 * m)
		track.Position = UDim2.fromScale(bodyX, bodyY)
		track.Size = UDim2.fromScale(1 - bodyX, bodyH * 0.86) -- the pill's face, above its lip
		local x = kw + 0.035
		for _, t in { action, what } do
			if t then
				t.Position = UDim2.fromScale(x, t.Position.Y.Scale)
				t.Size = UDim2.fromScale(0.95 - x, t.Size.Y.Scale)
			end
		end
	end
	fitKey()
	if compact then
		-- outlines shrink with the pill (UI Rules: after scaling, recheck outline weight), never under 1.5 px
		for _, s in { b.root:FindFirstChildOfClass("UIStroke"), key.root:FindFirstChildOfClass("UIStroke") } do
			if s then
				s.Thickness = math.max(1.5, s.Thickness * k)
			end
		end
	end
	-- touch and mouse: the whole prompt is the hold button
	local top = Instance.new("TextButton")
	top.Name = "Top"
	top.Text = ""
	top.AutoButtonColor = false
	top.BackgroundTransparency = 1
	top.Size = UDim2.fromScale(1, 1)
	top.ZIndex = 5
	top.Parent = holder
	gui.Parent = layer
	if not reduced then
		-- pops up (Animation Rules: pop, Back Out)
		pop.Scale = 0.4
		TweenService:Create(pop, TweenInfo.new(Config.motion.promptPop, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end
	local entry = { gui = gui, bar = bar, key = key.face, held = false, lift = lift, conns = {} :: { RBXScriptConnection } }
	if not reduced then
		task.spawn(function()
			while gui.Parent do
				task.wait(K.tapEvery)
				if gui.Parent and gui.Visible and layer.Enabled and not entry.held then
					keyDown(key.face, false)
				end
			end
		end)
	end
	local conns = entry.conns
	-- the hold ends when that finger (or the mouse button) lifts anywhere: a finger that slid off the
	-- pill kept the hold going (mobile QA 2026-11-10)
	local holding: InputObject? = nil
	local function release(input: InputObject)
		local h = holding
		if h and (input == h or (input.UserInputType == Enum.UserInputType.MouseButton1 and h.UserInputType == Enum.UserInputType.MouseButton1)) then
			holding = nil
			prompt:InputHoldEnd()
		end
	end
	table.insert(conns, top.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			holding = input
			prompt:InputHoldBegin()
		end
	end))
	table.insert(conns, top.InputEnded:Connect(release))
	table.insert(conns, UserInputService.InputEnded:Connect(release))
	table.insert(conns, InputController.DeviceChanged:Connect(function()
		keyText.Text = InputController.keyHint(prompt)
		fitKey()
	end))
	shown[prompt] = entry
end

local function hide(prompt: ProximityPrompt)
	local s = shown[prompt]
	if s then
		for _, c in s.conns do
			c:Disconnect()
		end
		s.gui:Destroy()
		shown[prompt] = nil
	end
end

-- prompts that only make sense in some states (set locally; the server checks again anyway)
local function refreshWorldPrompts(v: State.View)
	local map = workspace:FindFirstChild("Map")
	if not map then
		return
	end
	-- every island's gate (Round 4 phase 6): only the next one you can open asks you to pay
	local reach = v.reach or 1
	for _, z in Config.world.zones do
		local gate = if z.id > 1 then map:FindFirstChild("GatePromptSpot" .. z.id, true) else nil
		local gp = gate and gate:FindFirstChildWhichIsA("ProximityPrompt", true)
		if gp then
			gp.Enabled = z.ready and z.id == reach + 1
		end
	end
	local gift = map:FindFirstChild("GiftBox", true)
	local gift_p = gift and gift:FindFirstChildWhichIsA("ProximityPrompt", true)
	if gift_p then
		gift_p.Enabled = v.gift.ready
		gift_p.ObjectText = "Free gift" -- a saved map keeps the old "Daily gift" text (one-time gift since 2026-11-12)
	end
	-- Pan Upgrades: only at your own pan
	for i in Config.world.plots do
		local plot = map:FindFirstChild("Plot" .. i)
		local stand = plot and plot:FindFirstChild("PanUpgrade")
		local pp = stand and stand:FindFirstChildWhichIsA("ProximityPrompt", true)
		if pp then
			pp.Enabled = v.plot == i
		end
		-- the Thaw Machine's "Thaw a pet": only at your own pan, and machines 2-3 once you have them
		local pan = map:FindFirstChild("Pan" .. i, true)
		for m = 1, #Config.thaw.machinesAt do
			local machine = pan and pan:FindFirstChild("ThawMachine" .. m)
			local tp = machine and machine:FindFirstChild("ThawPrompt", true)
			if tp and tp:IsA("ProximityPrompt") then
				tp.Enabled = v.plot == i and m <= (v.machines or 1)
			end
		end
	end
	-- the Cold Power trainer's "Train" (TrainingService): only at your own pan, and not while you're in
	local training = Players.LocalPlayer:GetAttribute("TrainLocked") == true
	for _, a in workspace.Terrain:GetChildren() do
		if a.Name == "TrainPromptSpot" then
			local tp = a:FindFirstChildWhichIsA("ProximityPrompt")
			if tp and Config.isRobuxStation(tp:GetAttribute("Station") or 0) then
				-- the hub's Magma Trainer (Config.training.robux) is the shop window: "Unlock" sells the pass; once owned
				-- it has no prompt, you train at your own pan (owner 2026-11-23: "thats just for show")
				tp.Enabled = not training and Players.LocalPlayer:GetAttribute("Pass_" .. Config.training.robux.item) ~= true
				tp.ActionText = "Unlock"
			elseif tp then
				tp.Enabled = v.plot ~= nil and v.plot == tp:GetAttribute("Trainer") and not training
			end
		end
	end
end

function PromptController.Init()
	playerGui = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
	layer = Instance.new("ScreenGui")
	layer.Name = "Prompts"
	layer.ResetOnSpawn = false
	layer.IgnoreGuiInset = true -- so a WorldToViewportPoint position lands where the object is drawn
	layer.DisplayOrder = 0
	layer.ZIndexBehavior = Enum.ZIndexBehavior.Sibling -- children draw over their parent (Global hid the key's "E" under its badge)
	layer.Parent = playerGui
end

-- every frame: each prompt sits on its object's spot on screen; behind the camera = not drawn
local function stepPrompts()
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	for prompt, s in shown do
		local parent = prompt.Parent
		local at = if parent and parent:IsA("Attachment") then parent.WorldPosition elseif parent and parent:IsA("BasePart") then parent.Position else nil
		if at then
			local v = cam:WorldToViewportPoint(at + Vector3.new(0, s.lift, 0))
			s.gui.Visible = v.Z > 0
			s.gui.Position = UDim2.fromOffset(math.round(v.X), math.round(v.Y))
		else
			s.gui.Visible = false
		end
	end
end

function PromptController.Start()
	ProximityPromptService.PromptShown:Connect(function(prompt: ProximityPrompt)
		if prompt.Style == Enum.ProximityPromptStyle.Custom then
			show(prompt)
		end
	end)
	ProximityPromptService.PromptHidden:Connect(hide)
	game:GetService("RunService").RenderStepped:Connect(stepPrompts)
	-- a shop is open or a show plays: the prompts stay out of the way
	local function stepAside()
		local hidden = Screen.menuHidden or Screen.showHidden
		layer.Enabled = not hidden
		-- the ProximityPrompt itself still listens for its key: a press with the shop open would reopen it
		ProximityPromptService.Enabled = not hidden
	end
	Screen.MenuHiddenChanged:Connect(stepAside)
	Screen.ShowHiddenChanged:Connect(stepAside)
	ProximityPromptService.PromptButtonHoldBegan:Connect(function(prompt: ProximityPrompt)
		local s = shown[prompt]
		if s then
			s.held = true
			keyDown(s.key, true)
			s.bar.Size = UDim2.fromScale(0, 1)
			if prompt.ActionText ~= "Freeze" and prompt.ActionText ~= "Zap" then -- a freeze's bar follows the freeze (below)
				TweenService:Create(s.bar, TweenInfo.new(prompt.HoldDuration, Enum.EasingStyle.Linear), { Size = UDim2.fromScale(1, 1) }):Play()
			end
		end
	end)
	-- (Round 5: pets are shot, not prompted; RayController's aim ring shows how frozen a target is)
	ProximityPromptService.PromptButtonHoldEnded:Connect(function(prompt: ProximityPrompt)
		local s = shown[prompt]
		if s then
			s.held = false
			keyUp(s.key)
			TweenService:Create(s.bar, TweenInfo.new(0.1), { Size = UDim2.fromScale(0, 1) }):Play()
		end
	end)
	State.Changed:Connect(refreshWorldPrompts)
	-- a trainer's prompt is new when its trainer is rebuilt (an upgrade), and hides while you train
	local function refreshNow()
		local v = State.view
		if v then
			refreshWorldPrompts(v)
		end
	end
	Players.LocalPlayer:GetAttributeChangedSignal("TrainLocked"):Connect(refreshNow)
	Players.LocalPlayer:GetAttributeChangedSignal("Pass_" .. Config.training.robux.item):Connect(refreshNow) -- Unlock -> Train
	workspace.Terrain.ChildAdded:Connect(function(c)
		if c.Name == "TrainPromptSpot" then
			task.defer(refreshNow) -- its prompt arrives with it; one beat later to be safe
		end
	end)
	refreshNow()
	-- booths: the prompt card is the way in (no HUD button)
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt)
		local s = shown[prompt]
		if s and prompt.HoldDuration <= 0 then
			keyDown(s.key, false) -- the key clicks down under your press
		end
		-- a leaderboard: its top 100 (owner 2026-11-12)
		local boardId = prompt:GetAttribute("Leaderboard")
		if typeof(boardId) == "string" then
			if PopupController.openName() ~= "board" then
				PopupController.open("board", { id = boardId })
			end
			return
		end
		local booth = prompt:GetAttribute("Booth")
		if typeof(booth) ~= "string" then
			return
		end
		-- what it does comes from Config (a prompt in the saved map keeps the attribute it was built with)
		local action = prompt:GetAttribute("Action")
		for _, b in Config.world.booths do
			if b.id == booth then
				action = b.action
			end
		end
		if booth == "pan" then
			action = Config.world.panUpgradeAction -- your pan's stand (Round 4 phase 5: the Pan Upgrades popup)
		elseif booth == "thaw" then
			action = "thaw" -- your Thaw Machine: pick a frozen pet to put in (owner 2026-11-09)
		elseif booth == "mail" then
			action = "mail" -- the Feedback mailbox (owner 2026-11-17 night)
		end
		if action == "shop" or action == "equipment" or action == "pan" or action == "sell" or action == "rebirth" or action == "thaw" or action == "mail" then
			PromptController.openBooth(booth, action, prompt)
		else
			State.local_("comingSoon", { label = prompt.ObjectText })
		end
	end)
end

-- opens a booth's popup; it closes again when you walk away from the booth (final QA 2026-11-03: a booth's
-- buttons only work at the booth, Buy far away did nothing). Also used by the EQUIPMENT top button
-- (owner 2026-11-22: after its teleport the booth opens by itself, no E press needed)
function PromptController.openBooth(booth: string, action: string, prompt: ProximityPrompt?)
	do
		do
			PopupController.open(action, if action == "thaw" and prompt then { machine = prompt:GetAttribute("Machine") or 1 } else nil)
			local range = ({ equipment = Config.guns.boothRange, sell = Config.sell.boothRange, rebirth = Config.rebirth.boothRange, pan = Config.pan.standRange, thaw = Config.thaw.useRange, mail = Config.feedback.range } :: { [string]: number })[action]
			local at: Vector3? = nil
			for _, b in Config.world.booths do
				if b.id == booth then
					at = b.pos
				end
			end
			local parent = prompt and prompt.Parent
			if not at and parent then
				at = if parent:IsA("Attachment") then parent.WorldPosition elseif parent:IsA("BasePart") then parent.Position else nil
			end
			if range and at then
				local center, limit = at :: Vector3, range - Config.boothLeaveMargin
				task.spawn(function()
					local me = game:GetService("Players").LocalPlayer
					while PopupController.openName() == action do
						local root = me.Character and me.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
						if root and Vector2.new(root.Position.X - center.X, root.Position.Z - center.Z).Magnitude > limit then
							PopupController.close()
							break
						end
						task.wait(0.25)
					end
				end)
			end
		end
	end
end

return PromptController
