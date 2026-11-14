--!strict
-- TutorialController: plays the tutorial the server tracks (TutorialService decides when a step is
-- done; this only shows it). Captain Frost (TutorialNpc) drops in from the sky, and for each step flies
-- to where it happens (the green arrow's target, GuideController), points at it and makes it glow, and
-- says one short line on his card (TutorialCard). Then he reacts to what the player really does:
--   - a finished step: its own cheer (or a quick "Nice!"), then the next line
--   - stuck on a step: after a while he says how, for the device in hand (mouse, touch, controller)
--   - something goes wrong: a cube melts, a pet is too hot, you carry it away from home
-- A talk line moves on by itself after a while, so nobody waits on a button they didn't see.
-- The last steps: Claim your first pet, then a first Pan Upgrade (Speed) with his coins, then he jets off.
-- Skip (asks "Sure?" first) ends it for good; Settings > Tutorial > Replay starts it again.

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
local TutorialNpc = require(script.Parent.TutorialNpc)
local TutorialCard = require(script.Parent.TutorialCard)

local TutorialController = {}
local T = Config.tutorial
local N = T.npc
local me = Players.LocalPlayer

type Step = { id: string, on: string, say: string, focus: string?, goal: string?, hints: { [string]: string }?, cheer: string?,
	gift: string?, giftSay: string?, maxedSay: string?, maxedGoal: string? }

local active = false -- a tutorial is running
local leaving = false -- the last line is up and the Captain is about to go
local step = 0 -- the step on screen
local stepAt = 0
local spokeAt = 0
local hints = 0
local reactAt = -math.huge
local closestHome = math.huge
local skipAskedAt = -math.huge
local skipped = false -- the server said this end was a Skip
local token = 0 -- a newer line cancels older delayed ones
local glow: Highlight
local keysBound = false
local autoSent = false -- this talk step already moved itself on
local gift = 0 -- coins he just handed over with this step (the server's Notify), said in its line

local function flat(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

local function myPos(): Vector3?
	local r = TutorialNpc.myRoot()
	return r and r.Position
end

local function current(): Step?
	return T.steps[step]
end

-- one line on the card; the Captain turns to you and makes the gesture
local function say(text: string, goalText: string?, withNext: boolean, gesture: string?)
	TutorialCard.say(text, goalText, withNext)
	spokeAt = os.clock()
	SoundController.play(T.sounds.line, 1.25)
	if gesture then
		TutorialNpc.gesture(gesture)
	end
end

local function hintFor(s: Step): string?
	local h = s.hints
	if not h then
		return nil
	end
	return h[InputController.device()] or h.all
end

-- something went wrong: the Captain says so, at most once per cooldown
local function react(kind: string)
	local text = (T.react :: any)[kind]
	if not active or not text or os.clock() - reactAt < T.reactCooldown then
		return
	end
	reactAt = os.clock()
	local s = current()
	say(text, s and s.goal, false, "point")
end

local function gestureFor(s: Step): string?
	if s.id == "hello" then
		return "wave"
	elseif s.id == "done" then
		return "cheer"
	end
	return if s.focus then "point" else nil
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
	local level = if kind == "speed" then v.upgrades.boots elseif kind == "slots" then v.upgrades.pen
		elseif kind == "thaw" then (v.pan and (v.pan :: any).thaw) else 1
	return Config.panPrice(kind, level or 1, v.rebirths) == nil
end

-- `done` = the step the player just finished (its cheer), nil = no praise
local function showStep(i: number, done: Step?)
	token += 1
	local my = token
	step, stepAt, hints, closestHome, autoSent = i, os.clock(), 0, math.huge, false
	local s = current()
	if not s then
		return
	end
	GuideController.pointPets = s.focus == "pet"
	local given = gift
	gift = 0
	local function line()
		if token == my and active then
			local text, goalText = s.say, s.goal
			if given > 0 and s.giftSay then
				text = s.giftSay:gsub("{coins}", Config.coinText(given))
				SoundController.play(T.sounds.gift)
			elseif s.gift and s.maxedSay and isMaxed(s.gift) then
				text, goalText = s.maxedSay, s.maxedGoal or goalText
			end
			say(text, goalText, s.on == "next", gestureFor(s))
		end
	end
	if done then
		say(done.cheer or T.praise[math.random(#T.praise)], nil, false, "cheer")
		SoundController.play(T.sounds.praise)
		task.delay(T.praiseHold + (if done.cheer then 0.6 else 0), line) -- a longer cheer stays a bit longer
	else
		line()
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

-- beside you where the camera sees him: to the right and a little beyond you (nearer the horizon, so
-- the card over the hotbar doesn't hide him)
local function besideYou(p: Vector3): Vector3
	local cam = workspace.CurrentCamera
	local right = if cam then cam.CFrame.RightVector else Vector3.xAxis
	local fwd = if cam then cam.CFrame.LookVector else -Vector3.zAxis
	right = Vector3.new(right.X, 0, right.Z)
	fwd = Vector3.new(fwd.X, 0, fwd.Z)
	right = if right.Magnitude > 0.1 then right.Unit else Vector3.xAxis
	fwd = if fwd.Magnitude > 0.1 then fwd.Unit else -Vector3.zAxis
	return p + right * N.followSide + fwd * 3
end

local function begin(i: number)
	active, leaving, skipped = true, false, false
	-- a new player meets him by the spawn; a replay (or a rejoin mid-tutorial) far from there gets him at your side
	local p = myPos()
	local hello = Config.world.spawn + N.helloOffset
	local at = if p and flat(p, hello) > N.followGap * 2 then besideYou(p) else hello
	TutorialNpc.despawn()
	TutorialCard.confirmSkip(false)
	TutorialCard.skipVisible(true)
	showStep(i, nil) -- the card first: it never waits on his model
	local my = token
	if TutorialNpc.spawn(at, p) then -- false = no model from the server: the card still teaches
		SoundController.play(T.sounds.arrive)
		task.delay(0.8, function()
			local c = current()
			if token == my and c then
				TutorialNpc.gesture(gestureFor(c) or "wave") -- landed: hello!
			end
		end)
	end
end

local function finish()
	if not active then
		return
	end
	active, leaving = false, true
	token += 1
	local my = token
	GuideController.pointPets = false
	GuideController.extra = nil
	setGlow(nil)
	TutorialCard.skipVisible(false)
	if skipped then
		say(T.react.skipped, nil, false, "wave")
	else
		say(T.react.finished, nil, false, "wave")
		SoundController.play(T.sounds.finish)
	end
	-- a wave, then he jets up into the sky and is gone
	task.delay(T.leaveSeconds * 0.45, function()
		if token == my and TutorialNpc.alive() then
			TutorialNpc.leave()
			SoundController.play(T.sounds.leave)
		end
	end)
	task.delay(T.leaveSeconds, function()
		if token == my then
			leaving = false
			TutorialCard.hide()
			TutorialNpc.despawn()
		end
	end)
end

-- the server's answer: from the view (on join) or a Notify (at once)
local function apply(i: number, done: boolean)
	if done then
		finish()
		return
	end
	if not active then
		begin(i)
	elseif i ~= step then
		local was = current()
		-- praise only a step the player did (not one they just read)
		showStep(i, if i > step and was ~= nil and was.on ~= "next" then was else nil)
	end
end

-- ---------- buttons and keys ----------
local function onNext()
	local s = current()
	if not active or not s then
		return
	end
	if TutorialCard.typing() then
		TutorialCard.finishTyping() -- first press shows the whole line
		return
	end
	if s.on == "next" then
		SoundController.play("click")
		State.send("Tutorial", "next")
	end
end

local function onSkip()
	if not active then
		return
	end
	SoundController.play("click")
	if os.clock() - skipAskedAt <= T.skipConfirmSeconds then
		skipAskedAt = -math.huge
		skipped = true
		State.send("Tutorial", "skip")
		return
	end
	skipAskedAt = os.clock()
	TutorialCard.confirmSkip(true)
	task.delay(T.skipConfirmSeconds, function()
		if os.clock() - skipAskedAt >= T.skipConfirmSeconds then
			TutorialCard.confirmSkip(false)
		end
	end)
end

-- Enter / gamepad A = Next (only while Next shows, so A still jumps the rest of the time);
-- gamepad B = Skip (only while no popup is open, so B still closes popups)
local function bindKeys(on: boolean)
	if on == keysBound then
		return
	end
	keysBound = on
	if not on then
		ContextActionService:UnbindAction("IceRay_TutorialNext")
		ContextActionService:UnbindAction("IceRay_TutorialSkip")
		return
	end
	local K, G = Config.ui.keys, Config.ui.gamepadKeys
	ContextActionService:BindActionAtPriority("IceRay_TutorialNext", function(_, state: Enum.UserInputState)
		if state == Enum.UserInputState.Begin and TutorialCard.nextVisible() then
			onNext()
			return Enum.ContextActionResult.Sink
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.ContextActionPriority.High.Value + 5, K.skip, G.skip)
	ContextActionService:BindActionAtPriority("IceRay_TutorialSkip", function(_, state: Enum.UserInputState)
		if state == Enum.UserInputState.Begin then
			onSkip()
			return Enum.ContextActionResult.Sink
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.ContextActionPriority.High.Value + 5, G.close)
end

-- ---------- each frame ----------
-- where the step happens: the arrow's target when it's the right kind, else the step's own place
local function focusOf(s: Step, v: State.View): (Vector3?, Instance?)
	local t = GuideController.target
	if t and t.kind == s.focus then
		return t.pos, t.inst
	end
	local plot = v.plot
	if s.focus == "pan" and plot then
		return WorldRules.plotCenter(plot), nil
	elseif s.focus == "stand" and plot then
		return standOf(plot), nil
	elseif s.focus == "machine" and plot then
		for _, p in v.pets do
			local m = p.thawM
			if m then
				return GuideController.machineAt(plot, m), nil -- the machine your pet is thawing in
			end
		end
		return GuideController.machineAt(plot, 1), nil
	end
	return nil, nil
end

local function frame(dt: number)
	if not active and not leaving then
		bindKeys(false)
		return
	end
	TutorialNpc.step(dt)
	TutorialCard.update()
	local popup = PopupController.isOpen()
	TutorialCard.hold(popup)
	bindKeys(TutorialCard.visible() and not popup)
	local p = myPos()
	local v = State.view
	local s = current()
	if not p or not v or not s then
		return
	end
	-- the arrow doesn't know the Pan Upgrades stand: point it there while that's the step
	GuideController.extra = if active and s.focus == "stand" and v.plot then { kind = "stand", pos = standOf(v.plot) } else nil
	-- the Captain: by the thing to do next (on your side of it), or at your side
	local npc = TutorialNpc.position()
	local focus: Vector3?, inst: Instance? = nil, nil
	if active then
		focus, inst = focusOf(s, v)
	end
	if focus and flat(p, focus) < N.focusRange then
		local away = Vector3.new(p.X - focus.X, 0, p.Z - focus.Z)
		local dir = if away.Magnitude > 0.1 then away.Unit else Vector3.xAxis
		TutorialNpc.walkTo(focus + dir * N.focusStand)
		TutorialNpc.look(if TutorialCard.typing() then p else focus)
	elseif focus then
		-- still far off: he leads the way, a few steps ahead of you toward it
		local ahead = Vector3.new(focus.X - p.X, 0, focus.Z - p.Z).Unit
		local lead = p + ahead * N.leadAhead
		if not npc or flat(npc, lead) > N.followGap / 2 then
			TutorialNpc.walkTo(lead)
		end
		TutorialNpc.look(focus)
	else
		if npc and flat(npc, p) > N.followGap then
			TutorialNpc.walkTo(besideYou(p))
		end
		TutorialNpc.look(p)
	end
	if not active then
		return
	end
	-- a talk line moves on by itself once it's had time to be read (the card is up, no popup over it)
	if s.on == "next" and not autoSent and not popup and not TutorialCard.typing() and os.clock() - spokeAt > T.autoNext then
		autoSent = true
		State.send("Tutorial", "next")
	end
	setGlow(if s.focus == "pet" or s.focus == "cube" then inst else nil)
	-- stuck: say how, then again now and then
	local hint = hintFor(s)
	if hint and not TutorialCard.typing() then
		local waitFor = if hints == 0 then T.hintAfter else T.hintEvery
		if os.clock() - math.max(stepAt, spokeAt) > waitFor then
			hints += 1
			say(hint, s.goal, false, "point")
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
	TutorialCard.build(onNext, onSkip)
	State.Changed:Connect(function(v: State.View)
		local t = v.tutorial
		if t and (t.done == active or (active and t.step ~= step)) then
			apply(t.step, t.done)
		end
	end)
	State.Notify:Connect(function(kind: string, data: any)
		if kind == "tutorial" and typeof(data) == "table" then
			skipped = data.why == "skip"
			gift = if typeof(data.gift) == "number" then data.gift else 0
			apply(data.step, data.done == true)
			gift = 0 -- only the line of the step it came with says it
		elseif kind == "melted" then
			react("melted")
		elseif kind == "tooWarm" then
			react("tooWarm")
		end
	end)
	me.CharacterAdded:Connect(function(c: Model)
		-- respawned: he comes to you (a frost poof over if you're far)
		local r = c:WaitForChild("HumanoidRootPart", 10)
		if active and r and r:IsA("BasePart") then
			TutorialNpc.walkTo(besideYou(r.Position))
		end
	end)
	RunService.RenderStepped:Connect(frame)
end

return TutorialController
