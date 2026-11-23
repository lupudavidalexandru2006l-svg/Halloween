--!strict
-- TutorialController: plays the tutorial the server tracks (TutorialService decides when a step is
-- done; this only shows it). No guide character since 2026-11-15 (owner: "get rid of captain frost"):
-- the world teaches, the way the top games do (vault Research > Tutorial References):
--   - the goal pill at the top centre (TutorialGoal): icon, a few words, a count on the Cold Power step,
--     step dots and Skip (asks "Sure?" first)
--   - the chevron trail and the bouncing arrow over the target (GuideController), a glow on the pet or cube
--   - a finished step: its cheer (or a quick praise) in the pill, then the next goal
--   - stuck on a step: after a while its hint shows in the pill, for the device in hand
--   - something goes wrong (a cube melts, a pet is too hot, you carry it away from home): a short line
--   - the menus stay hidden until the upgrade step is done (Screen.lockMenus, Config.tutorial.lockUntil)
--   - it ends on the TUTORIAL COMPLETE card with its coin reward (TutorialComplete)
-- One run from the first catch to the next island: catch, home, thaw, upgrade, train, open the gate.
-- Skip ends it for good; Settings > Tutorial > Replay starts it again. "{need}" = the next island's need.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Theme = require(ReplicatedStorage.Shared.Theme)
local WorldRules = require(ReplicatedStorage.Shared.WorldRules)
local State = require(script.Parent.State)
local InputController = require(script.Parent.InputController)
local SoundController = require(script.Parent.SoundController)
local GuideController = require(script.Parent.GuideController)
local PopupController = require(script.Parent.PopupController)
local PetVisuals = require(script.Parent.PetVisuals)
local TutorialGoal = require(script.Parent.TutorialGoal)
local TutorialComplete = require(script.Parent.TutorialComplete)
local Screen = require(script.Parent.Screen)
local CameraController = require(script.Parent.CameraController)
local SettingsController = require(script.Parent.SettingsController)
local TweenService = game:GetService("TweenService")
local PetDefs = require(ReplicatedStorage.Shared.PetDefs)
local Spotlight = require(script.Parent.Parent.Lib.Spotlight)

local TutorialController = {}
local T = Config.tutorial
local me = Players.LocalPlayer

type Step = { id: string, on: string, say: string, focus: string?, goal: string?, goals: { [string]: string }?, hints: { [string]: string }?, cheer: string?,
	gift: string?, giftSay: string?, maxedSay: string?, maxedGoal: string?, quiet: boolean?, hintOnce: boolean?, tease: boolean?,
	icon: string?, count: string?, reward: number?, rewardTitle: string? }

local active = false -- a tutorial is running
local step = 0 -- the step on screen
local stepAt = 0 -- when it started (or when its goal showed, after a cheer)
local hints = 0
local reactAt = -math.huge
local closestHome = math.huge
local skipAskedAt = -math.huge
local token = 0 -- a newer step cancels older delayed ones
local glow: Highlight
local keysBound = false
local autoSent = false -- this talk step already moved itself on
local gift = 0 -- coins the server just handed over with this step (its Notify)

local function flat(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

local function myPos(): Vector3?
	local c = me.Character
	local r = c and c:FindFirstChild("HumanoidRootPart") :: BasePart?
	return r and r.Position
end

local function current(): Step?
	return T.steps[step]
end

local function reduced(): boolean
	return SettingsController.get("reducedMotion") == true
end

-- "{need}" = the Cold Power the next island asks for
local function fill(text: string?): string?
	if not text then
		return nil
	end
	local v = State.view
	local need = Config.need(((v and v.reach) or 1) + 1)
	return (string.gsub(text, "{need}", Config.powerText(need)))
end

-- where you stand on your own pan's trainer (the same spot as GuideController's)
local function trainSpotOf(plot: number): Vector3
	return (Config.trainerFrame(plot) * CFrame.new(0, 0, Config.training.standZ)).Position
end

-- the next island's gate, at the start of that island
local function gateSpot(v: State.View): Vector3?
	local z = Config.zone(((v.reach or 1) :: number) + 1)
	return if z then Vector3.new(0, 0, z.zMin - 4) else nil
end

local function hintFor(s: Step): string?
	local h = s.hints
	if not h then
		return nil
	end
	return h[InputController.device()] or h.all
end

-- something went wrong: a short line in the pill, at most once per cooldown
local function react(kind: string)
	local text = (T.react :: any)[kind]
	if not active or not text or os.clock() - reactAt < T.reactCooldown then
		return
	end
	reactAt = os.clock()
	TutorialGoal.message(text, false, T.messageSeconds)
end

-- the Pan Upgrades stand of your pan (the same spot as PanService's atStand)
local function standOf(plot: number): Vector3
	local W = Config.world.pans
	return Vector3.new(Config.world.plots[plot].x + W.boothOffset, 0, W.frontZ + 2.5)
end

-- this Pan Upgrade is already at the top for you (a replay): nothing left to buy there
local function isMaxed(kind: string): boolean
	local v = State.view
	if not v then
		return false
	end
	local level = if kind == "slots" then v.upgrades.pen
		elseif kind == "thaw" then (v.pan and (v.pan :: any).thaw) else 1
	return Config.panPrice(kind, level or 1, v.rebirths) == nil
end

-- the peek (a "tease" step, Config.tutorial.tease): the camera flies to the hub side of the next island's
-- gate, low and to one side, so the gate and its Cold Power sign fill the front and a few of that island's
-- pets (glowing) stand just behind the bars; the pill says what opens it. Then it flies back. Only on this
-- screen; the camera always comes back, even if something fails (reworked 2026-11-16)
local teasing = false
local function tease()
	local cfg = T.tease
	local v = State.view
	local z = Config.zone(((v and v.reach) or 1) + 1)
	if teasing or not z then
		return
	end
	local pool = PetDefs.inZone(z.id, "Rare")
	if #pool == 0 then
		pool = PetDefs.inZone(z.id, "Uncommon")
	end
	local cam = CameraController.borrow()
	if not cam then
		return
	end
	teasing = true
	local home = cam.CFrame
	local models: { PVInstance } = {}
	local reduced = SettingsController.get("reducedMotion") == true
	local ok, err = pcall(function()
		-- a short row of that island's pets just past the gate, facing you (its Rares and Uncommons)
		local more = PetDefs.inZone(z.id, "Uncommon")
		for n = 1, cfg.pets do
			local list = if n == 2 and #pool > 0 then pool elseif #more > 0 then more else pool
			local def = if #list > 0 then list[math.random(#list)] else nil
			local x = (n - (cfg.pets + 1) / 2) * cfg.petGap
			local petAt = Vector3.new(x, 0, z.zMin + cfg.petIn + (if n == 2 then 4 else 0))
			local size = cfg.petSize * (if n == 2 then 1.3 else 1)
			local model = if def then PetVisuals.model(def.key, size) else nil
			if def and model then
				model:PivotTo(CFrame.lookAt(petAt + Vector3.new(0, size / 2, 0), petAt + Vector3.new(0, size / 2, -10)))
				if cfg.glow then
					local h = Instance.new("Highlight")
					h.FillColor = Theme.tiers[def.tier] or Theme.white
					h.FillTransparency = 0.65
					h.OutlineColor = Theme.white
					h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
					h.Parent = model
				end
				model.Parent = workspace
				table.insert(models, model)
			end
		end
		local look = Vector3.new(0, cfg.lookUp, z.zMin + cfg.petIn * 0.4)
		local to = CFrame.lookAt(Vector3.new(cfg.camSide, cfg.camUp, z.zMin - cfg.camBack), look)
		if reduced then
			cam.CFrame = to
		else
			local tw = TweenService:Create(cam, TweenInfo.new(cfg.fly, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), { CFrame = to })
			tw:Play()
			tw.Completed:Wait()
		end
		task.wait(if reduced then cfg.hold * 0.5 else cfg.hold)
		if not reduced then
			local back = TweenService:Create(cam, TweenInfo.new(cfg.back, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), { CFrame = home })
			back:Play()
			back.Completed:Wait()
		end
	end)
	for _, m in models do
		m:Destroy()
	end
	CameraController.giveBack()
	teasing = false
	if not ok then
		warn("[TutorialController] peek:", err)
	end
end

local function indexOf(id: string): number
	for i, s in T.steps do
		if s.id == id then
			return i
		end
	end
	return #T.steps
end

-- the pill for step i: its goal (a talk step shows its line); one dot per goal, the ones before it done
local function showGoal(i: number, text: string)
	local s = T.steps[i]
	local before, count, at = 0, 0, 0
	for j, o in T.steps do
		if o.goal then
			count += 1
			if j < i then
				before += 1
			elseif j == i then
				at = count
			end
		end
	end
	TutorialGoal.set(fill(text) :: string, s.icon, if at > 0 then at else before + 1, count, s.count ~= nil)
end

-- `done` = the step the player just finished (its cheer), nil = none
local function showStep(i: number, done: Step?)
	token += 1
	local my = token
	step, stepAt, hints, closestHome, autoSent = i, os.clock(), 0, math.huge, false
	local s = current()
	if not s then
		return
	end
	TutorialGoal.skipVisible(s.id ~= "done") -- QA PT-08: nothing left to skip on "Tutorial complete!"
	GuideController.pointPets = s.focus == "pet"
	GuideController.tutorial = true
	GuideController.focus = s.focus -- nil on a talk step: no arrow while the peek or the end plays
	Screen.lockMenus(T.lockMenus and i <= indexOf(T.lockUntil), reduced())
	local given = gift
	gift = 0
	local text = (s.goals and s.goals[InputController.device()]) or s.goal or s.say -- worded for the device in hand (QA IR-09)
	if given > 0 and s.giftSay then
		text = (s.giftSay:gsub("{coins}", Config.coinText(given)))
	elseif s.gift and s.maxedGoal and isMaxed(s.gift) then
		text = s.maxedGoal
	end
	local function show()
		if token ~= my or not active then
			return
		end
		stepAt = os.clock()
		showGoal(i, text)
		if given > 0 then
			SoundController.play(T.sounds.gift)
		end
		if s.tease then
			-- the camera swoop waits for the popup and the upgrade show to be gone
			task.spawn(function()
				local waited = 0
				while (PopupController.isOpen() or Screen.showHidden) and waited < 15 do
					waited += task.wait(0.2)
				end
				if token == my and active then
					stepAt = os.clock() -- the step moves on autoNext seconds after the swoop starts
					tease()
				end
			end)
		end
	end
	if done and done.focus == "stand" then
		-- the upgrade is bought: the Pan Upgrades popup closes once its upgrade show is over, so the next
		-- step (the peek, then training) isn't waiting behind it
		task.spawn(function()
			local waited = 0
			repeat
				waited += task.wait(0.2)
			until not Screen.showHidden or waited > 10
			task.wait(0.6)
			if token == my and PopupController.openName() == "pan" then
				PopupController.close()
			end
		end)
	end
	if done then
		-- the cheer first, in green, then the next goal
		TutorialGoal.flash()
		TutorialGoal.message(done.cheer or T.praise[math.random(#T.praise)], true, T.praiseHold + 1)
		SoundController.play(T.sounds.praise)
		task.delay(T.praiseHold, show)
	else
		show()
	end
end

local function setGlow(inst: Instance?)
	local target: Instance? = inst
	if inst then
		target = PetVisuals.drawnModel(inst) or inst -- a pet's root is invisible: glow its drawn model
	end
	if glow.Adornee ~= target then
		glow.Adornee = target
		glow.Enabled = target ~= nil
	end
end

local function begin(i: number)
	active = true
	TutorialGoal.confirmSkip(false)
	TutorialGoal.skipVisible(true)
	showStep(i, nil)
end

local function finish()
	if not active then
		return
	end
	active = false
	token += 1
	GuideController.pointPets = false
	GuideController.tutorial = false
	GuideController.focus = nil
	GuideController.extra = nil
	setGlow(nil)
	TutorialGoal.hide()
	Screen.lockMenus(false, reduced())
end

-- the server's answer: from the view (on join) or a Notify (at once)
local function apply(i: number, done: boolean)
	local s = T.steps[i]
	if done or (s and s.quiet) then
		finish()
		step = i
		return
	end
	if not active then
		begin(i)
	elseif i ~= step then
		local was = current()
		-- cheer only a step the player did (not a talk step)
		showStep(i, if i > step and was ~= nil and was.on ~= "next" then was else nil)
	end
end

-- ---------- Skip ----------
local function onSkip()
	if not active then
		return
	end
	SoundController.play("click")
	if os.clock() - skipAskedAt <= T.skipConfirmSeconds then
		skipAskedAt = -math.huge
		State.send("Tutorial", "skip")
		return
	end
	skipAskedAt = os.clock()
	TutorialGoal.confirmSkip(true)
	task.delay(T.skipConfirmSeconds, function()
		if os.clock() - skipAskedAt >= T.skipConfirmSeconds then
			TutorialGoal.confirmSkip(false)
		end
	end)
end

-- gamepad B = Skip (only while no popup is open, so B still closes popups)
local function bindKeys(on: boolean)
	if on == keysBound then
		return
	end
	keysBound = on
	if not on then
		ContextActionService:UnbindAction("IceRay_TutorialSkip")
		return
	end
	ContextActionService:BindActionAtPriority("IceRay_TutorialSkip", function(_, state: Enum.UserInputState)
		if state == Enum.UserInputState.Begin then
			onSkip()
			return Enum.ContextActionResult.Sink
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.ContextActionPriority.High.Value + 5, Config.ui.gamepadKeys.close)
end

-- ---------- each frame ----------
local function frame()
	local popup = PopupController.isOpen()
	bindKeys(active and TutorialGoal.visible() and not popup and not TutorialComplete.isOpen())
	if not active then
		Spotlight.show(nil)
		return
	end
	local p = myPos()
	local v = State.view
	local s = current()
	if not p or not v or not s then
		Spotlight.show(nil)
		return
	end
	-- the gear step (owner 2026-11-21): no walk to the booth. The screen dims round the EQUIPMENT top button,
	-- then, with the booth open, round Frost Boots' Buy button
	local spot: GuiObject? = nil
	local boothOpen = PopupController.openName() == "equipment"
	if s.focus == "booth" and not TutorialComplete.isOpen() then
		local pg = me:FindFirstChildOfClass("PlayerGui")
		if pg then
			local name = if PopupController.openName() == "equipment" then "Buy_frost_boots"
				elseif not popup then "Top_equipment" else nil
			local f = if name then pg:FindFirstChild(name, true) else nil
			spot = if f and f:IsA("GuiObject") then f else nil
		end
	end
	-- the booth open: the game shows again, only the ring on Buy (owner 2026-11-22)
	Spotlight.show(spot, boothOpen)
	-- the arrow doesn't know the Pan Upgrades stand, your trainer while you're off it, or the next gate
	local extra: GuideController.Target? = nil
	if v.plot then
		if s.focus == "stand" then
			extra = { kind = "stand", pos = standOf(v.plot) }
		elseif s.focus == "train" and (me:GetAttribute("TrainStation") or 0) == 0 then
			extra = { kind = "train", pos = trainSpotOf(v.plot) }
		elseif s.focus == "gate" then
			local g = gateSpot(v)
			extra = if g then { kind = "gate", pos = g } else nil
		end
	end
	GuideController.extra = extra
	-- the glow on the pet or the cube the arrow points at
	local t = GuideController.target
	setGlow(if t and t.kind == s.focus and (s.focus == "pet" or s.focus == "cube") then t.inst else nil)
	-- a talk step moves on by itself (no popup over it, the TUTORIAL COMPLETE card closed)
	if s.on == "next" and not autoSent and not popup and not TutorialComplete.isOpen() and os.clock() - stepAt > T.autoNext then
		autoSent = true
		State.send("Tutorial", "next")
	end
	if s.count == "power" then
		TutorialGoal.count((v.coldPower or 0) :: number, Config.need(((v.reach or 1) :: number) + 1))
	end
	-- stuck: the hint in the pill, then again now and then
	local hint = hintFor(s)
	if hint and not (s.hintOnce and hints >= 1) then
		local waitFor = if hints == 0 then T.hintAfter else T.hintEvery
		if os.clock() - stepAt > waitFor then
			hints += 1
			stepAt = os.clock()
			TutorialGoal.message(hint, false, T.messageSeconds)
			SoundController.play(T.sounds.hint, 1.25)
		end
	end
	-- carrying the cube the wrong way
	local plot = v.plot
	if s.id == "carry" and plot then
		local d = flat(p, WorldRules.plotCenter(plot))
		closestHome = math.min(closestHome, d)
		if d > closestHome + T.wrongWayStuds then
			react("wrongWay")
			closestHome = d
		end
	end
end

function TutorialController.Init()
	glow = Instance.new("Highlight")
	glow.Name = "TutorialGlow"
	glow.FillColor = Theme.tutorial.focus
	glow.FillTransparency = 0.8
	glow.OutlineColor = Theme.tutorial.focus
	glow.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	glow.Enabled = false
	glow.Parent = workspace
end

function TutorialController.Start()
	TutorialGoal.build(onSkip)
	State.Changed:Connect(function(v: State.View)
		local t = v.tutorial
		if t and (t.done == active or (active and t.step ~= step)) then
			apply(t.step, t.done)
		end
	end)
	State.Notify:Connect(function(kind: string, data: any)
		if kind == "tutorial" and typeof(data) == "table" then
			gift = if typeof(data.gift) == "number" then data.gift else 0
			apply(data.step, data.done == true)
			gift = 0 -- only the step it came with shows it
			local s = T.steps[data.step]
			if typeof(data.reward) == "number" and data.reward > 0 and s then
				task.spawn(TutorialComplete.show, s.rewardTitle or "TUTORIAL COMPLETE!", data.reward)
			end
		elseif kind == "melted" then
			react("melted")
		elseif kind == "tooWarm" then
			react("tooWarm")
		end
	end)
	RunService.RenderStepped:Connect(frame)
end

return TutorialController
