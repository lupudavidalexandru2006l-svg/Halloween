--!strict
-- TrainingController (owner 2026-11-10; replaces the rink's client): Cold Power training on this client.
-- Every pan has its own trainer in front of it (TrainingService builds it at its owner's level). The
-- server decides every shot and its Cold Power; this only draws, and sends intent ("Train" "shot" on a
-- click / tap / R2 / E while you stand on your own trainer). Stations below = pans' trainers.
--   Signs:  each trainer's "x5 Cold Power" title floats over it in its level's colour (the reference's
--           "X3 Strength" signs), so you see how far everyone has upgraded.
--   Bolts:  a frost bolt flies from a player's gun tip to the target on each of their shots: my clicks at
--           once, my gun's own shots when the server says (Notify "train"), everyone else's from their
--           TrainShots counter. The gun flashes, the target wobbles and puffs frost where it's hit.
--   Frost:  on the target I'm training on, frost climbs up it and its warm parts (named Heat) cool toward
--           ice as my meter fills; at a shatter it bursts, flashes and the frost falls away.
--   Hint:   "CLICK!" / "TAP!" / "R2!" pulses over my target with the shatter meter under it (the one next action).
--   Pops:   "+N" shoots off the target to one side on each of my shots (CoinPops' motion); a shatter's
--           bonus is a big gold one.
--   Facing: standing still on a station turns you to face its target.
--   Lock:   while the server holds you at your trainer ("TrainLocked", owner 2026-11-11), you always face
--           the target, can't jump, the camera swings round behind you once, and a red STOP button
--           takes the hotbar's place (click / tap, Space, or gamepad B). STOP tells the server to let you go.
-- One HUD piece, the STOP button; the Cold Power counter (HudController) already bounces as it climbs.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local TextService = game:GetService("TextService")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Theme = require(ReplicatedStorage.Shared.Theme)
local Ui = require(script.Parent.Parent.Lib.Ui)
local State = require(script.Parent.State)
local InputController = require(script.Parent.InputController)
local SettingsController = require(script.Parent.SettingsController)
local SoundController = require(script.Parent.SoundController)
local EffectsController = require(script.Parent.EffectsController)
local CameraController = require(script.Parent.CameraController)
local RayController = require(script.Parent.RayController)
local Screen = require(script.Parent.Screen)

local TrainingController = {}
local T = Config.training
local U = Config.ui.training
local J = Config.juice -- hit flash, shiver, hit-stop (Animation Rules 8)
local TT = Theme.training
local me = Players.LocalPlayer
local folder: Folder

local function reduced(): boolean
	return SettingsController.get("reducedMotion") == true
end

local function lowGfx(): boolean
	return SettingsController.get("lowGraphics") == true
end

local function anchorPart(name: string, pos: Vector3): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	p.Transparency = 1
	p.Size = Vector3.one * 0.2
	p.CFrame = CFrame.new(pos)
	p.Parent = folder
	return p
end

-- pan i's trainer level (PanService puts it on the map; a free pan shows level 1)
local function tierAt(i: number): number
	local map = workspace:FindFirstChild("Map")
	local t = map and map:GetAttribute("PanTrainer" .. i)
	return if typeof(t) == "number" and T.stations[t] then t else 1
end

local function stationOf(i: number): Config.TrainStation
	return T.stations[tierAt(i)]
end

local function aimAt(i: number): Vector3
	return Config.trainerTarget(i) + Vector3.new(0, T.padHeight + stationOf(i).aimY, 0)
end

-- the pan whose trainer I stand on (only ever my own; 0 = none)
local function myStation(): number
	local i = me:GetAttribute("TrainStation")
	return if typeof(i) == "number" and Config.world.plots[i] then i else 0
end

-- the server holds me at my trainer until I press STOP
local function locked(): boolean
	return me:GetAttribute("TrainLocked") == true
end

-- ---------- the targets (TrainingArt's models, streamed in) ----------
type HeatPart = { part: BasePart, color: Color3 }
type Look = {
	model: Model, base: CFrame, hang: Vector3?, heat: { HeatPart },
	wobbleAt: number, wobbleAmp: number, wobbleSeconds: number, moved: boolean,
	holdUntil: number, shake: number, -- a shatter's hit-stop: held still, shaking, until holdUntil
}
local looks: { [number]: Look } = {}

local function addTarget(m: Instance)
	if not m:IsA("Model") then
		return
	end
	local i = m:GetAttribute("Station")
	if typeof(i) ~= "number" then
		return
	end
	-- its built pivot lives in an attribute (World Rules: never a weak table keyed by the part)
	local base = m:GetAttribute("BasePivot")
	if typeof(base) ~= "CFrame" then
		base = m:GetPivot()
		m:SetAttribute("BasePivot", base)
	end
	local heat: { HeatPart } = {}
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") and d.Name == "Heat" then
			local c = d:GetAttribute("BaseColor")
			if typeof(c) ~= "Color3" then
				c = d.Color
				d:SetAttribute("BaseColor", c)
			end
			table.insert(heat, { part = d, color = c :: Color3 })
		end
	end
	local hang = m:GetAttribute("HangAt")
	looks[i] = { model = m, base = base :: CFrame, hang = if typeof(hang) == "Vector3" then hang else nil, heat = heat,
		wobbleAt = -math.huge, wobbleAmp = 0, wobbleSeconds = 1, moved = false, holdUntil = 0, shake = 0 }
end

local function removeTarget(m: Instance)
	for i, l in looks do
		if l.model == m then
			looks[i] = nil
		end
	end
end

local function wobble(i: number, big: boolean)
	local l = looks[i]
	if not l then
		return
	end
	local W = U.wobble
	l.wobbleAt = os.clock()
	l.wobbleSeconds = (if big then W.shatterSeconds else W.seconds) * (if reduced() then 0.5 else 1)
	l.wobbleAmp = W.squash * (if big then 2.2 else 1) * (if l.hang then 2.5 else 1) * (if reduced() then 0.35 else 1)
end

-- the hit's lean back (or the bag's swing), a damped spring (Animation Rules 4: overshoot once, rest),
-- plus `shiver` (a small side rock when the next shots may shatter it) and a shatter's hit-stop shake
local function stepWobble(l: Look, now: number, shiver: number)
	if now < l.holdUntil then
		local s = l.shake
		l.model:PivotTo(l.base + Vector3.new(math.sin(now * 97) * s, 0, math.cos(now * 83) * s))
		l.moved = true
		return
	end
	local x = (now - l.wobbleAt) / l.wobbleSeconds
	local a = if x >= 0 and x < 1 then l.wobbleAmp * math.exp(-4 * x) * math.sin(math.pi * 2.5 * x) else 0
	if a == 0 and shiver == 0 then
		if l.moved then
			l.model:PivotTo(l.base)
			l.moved = false
		end
		return
	end
	local cf
	if l.hang then
		local pivot = CFrame.new(l.hang)
		cf = pivot * CFrame.Angles(a, 0, shiver) * pivot:Inverse() * l.base
	else
		cf = l.base * CFrame.Angles(a, 0, shiver) -- top leans away from the shooter (+Z)
	end
	l.model:PivotTo(cf)
	l.moved = true
end

-- ---------- my frost on my target ----------
local frost = { station = 0, shown = 0, goal = 0, shell = nil :: Part? }

-- the hit flash on my target: `peak` white, held for `hold` seconds, then gone over J.hitFlash
local flashFx = { at = -math.huge, hold = 0, peak = 0 }
local function hitFlash(peak: number, hold: number)
	flashFx.at, flashFx.hold, flashFx.peak = os.clock(), hold, peak
end

local function flashAmount(now: number): number
	local t = now - flashFx.at - flashFx.hold
	if t < 0 then
		return flashFx.peak
	end
	local fade = J.hitFlash * (if reduced() then 0.5 else 1)
	return if t < fade then flashFx.peak * (1 - t / fade) else 0
end

local function paintFrost(i: number, m: number)
	local l = looks[i]
	if l then
		local fl = flashAmount(os.clock())
		for _, h in l.heat do
			if h.part.Parent then
				h.part.Color = h.color:Lerp(TT.frost, math.clamp(m, 0, 1) * 0.85):Lerp(Theme.white, fl)
			end
		end
	end
	local shell = frost.shell
	if not shell then
		return
	end
	if m <= 0.01 then
		shell.Transparency = 1
		return
	end
	local st = stationOf(i)
	local h = math.max(0.1, st.shell.height * m)
	local foot = Config.trainerTarget(i) + Vector3.new(0, T.padHeight + st.shell.bottom, 0)
	shell.Size = Vector3.new(h, st.shell.width, st.shell.width) -- an upright cylinder: its axis is X
	shell.CFrame = CFrame.new(foot + Vector3.new(0, h / 2, 0)) * CFrame.Angles(0, 0, math.pi / 2)
	shell.Transparency = 0.55
end

local function setFrostStation(i: number)
	if frost.station == i then
		return
	end
	if frost.station ~= 0 then
		paintFrost(frost.station, 0) -- the old target warms back up
	end
	frost.station = i
	local m = me:GetAttribute("TrainMeter")
	frost.goal = if typeof(m) == "number" then m else 0
	frost.shown = 0
end

-- ---------- bolts ----------
type Bolt = { part: BasePart, from: Vector3, to: Vector3, t0: number, seconds: number, land: () -> () }
local bolts: { Bolt } = {}

local function gunTipPos(c: Model): Vector3?
	local tip = RayController.tipOf(c)
	if tip then
		return tip.WorldPosition
	end
	local root = c:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position + root.CFrame.LookVector * 1.5 + Vector3.new(0, 0.6, 0)
	end
	return nil
end

local function launch(from: Vector3, to: Vector3, big: boolean, land: () -> ())
	local B = U.bolt
	local s = if big then B.clickSize else B.size
	local p = Instance.new("Part")
	p.Name = "FrostBolt"
	p.Shape = Enum.PartType.Ball
	p.Size = Vector3.one * s
	p.Color = TT.frostGlow
	p.Material = Enum.Material.Neon
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	p.CFrame = CFrame.new(from)
	if not lowGfx() then
		local a0, a1 = Instance.new("Attachment"), Instance.new("Attachment")
		a0.Position, a1.Position = Vector3.new(0, s * 0.45, 0), Vector3.new(0, -s * 0.45, 0)
		a0.Parent, a1.Parent = p, p
		local tr = Instance.new("Trail")
		tr.Attachment0, tr.Attachment1 = a0, a1
		tr.Lifetime = B.trail
		tr.LightEmission = 1
		tr.Color = ColorSequence.new(Theme.white, TT.frostGlow)
		tr.Transparency = NumberSequence.new(0.1, 1)
		tr.Parent = p
	end
	p.Parent = folder
	table.insert(bolts, { part = p, from = from, to = to, t0 = os.clock(), seconds = B.seconds, land = land })
end

local function stepBolts(now: number)
	for k = #bolts, 1, -1 do
		local b = bolts[k]
		local f = (now - b.t0) / b.seconds
		if f >= 1 then
			table.remove(bolts, k)
			b.part.Transparency = 1 -- its trail fades out behind it, then it goes
			task.delay(U.bolt.trail, function()
				b.part:Destroy()
			end)
			local ok, err = pcall(b.land)
			if not ok then
				warn("[TrainingController] bolt:", err)
			end
		else
			local pos = b.from:Lerp(b.to, f) + Vector3.new(0, math.sin(f * math.pi) * 0.6, 0) -- a small arc
			b.part.CFrame = CFrame.new(pos)
		end
	end
end

-- one shot from a player's gun at station i; land runs when the bolt arrives
local function drawShot(p: Player, i: number, mine: boolean, big: boolean, land: (() -> ())?)
	local c = p.Character
	local from = c and gunTipPos(c)
	if not c or not from then
		return
	end
	local cam = workspace.CurrentCamera
	if not mine and cam and (cam.CFrame.Position - from).Magnitude > U.pop.maxDistance * 1.5 then
		return -- far off: phones don't draw it
	end
	RayController.muzzle(c, "flash")
	if mine and big then
		RayController.muzzle(c, "mist")
	end
	local to = aimAt(i)
	launch(from, to, big, function()
		wobble(i, false)
		if mine then
			hitFlash(J.flashPeak, 0)
		end
		EffectsController.burst(to - Vector3.new(0, 2, 0), TT.frost, if mine then 5 else 2) -- burst() lifts by 2
		if mine then
			SoundController.play("tink", 0.9 + 0.6 * frost.goal) -- the pitch climbs with the frost (Game Design 8)
		end
		if land then
			land()
		end
	end)
end

-- ---------- "+N" pops (CoinPops' motion) ----------
type Pop = { gui: BillboardGui, group: Frame, scale: UIScale, text: TextLabel, stroke: UIStroke, grad: UIGradient,
	born: number, side: number, dx: number, dy: number, still: boolean }
local live: { Pop } = {}
local spare: { Pop } = {}
local aims: { [number]: Part } = {}
local popSide = 1

local function backOut(x: number): number
	return 1 + 2.70158 * (x - 1) ^ 3 + 1.70158 * (x - 1) ^ 2
end

local function buildPop(): Pop
	local P = U.pop
	local g = Instance.new("BillboardGui")
	g.Name = "TrainPop"
	g.Size = UDim2.fromOffset(P.boxPx[1], P.boxPx[2])
	g.LightInfluence = 0
	g.AlwaysOnTop = true
	g.MaxDistance = P.maxDistance
	g.ResetOnSpawn = false
	g.Enabled = false
	local group = Instance.new("Frame")
	group.Name = "Pop"
	group.BackgroundTransparency = 1
	group.AnchorPoint = Vector2.new(0.5, 0.5)
	group.Parent = g
	local scale = Instance.new("UIScale")
	scale.Parent = group
	local text = Ui.label(group, "")
	text.Name = "Amount"
	text.TextScaled = false
	local grad = Instance.new("UIGradient")
	grad.Rotation = 90
	grad.Parent = text
	local stroke = text:FindFirstChildOfClass("UIStroke") :: UIStroke
	g.Parent = me:WaitForChild("PlayerGui")
	return { gui = g, group = group, scale = scale, text = text, stroke = stroke, grad = grad, born = 0, side = 1, dx = 0, dy = 0, still = false }
end

local function placePop(p: Pop, age: number): boolean
	local P = U.pop
	local k = if p.still then 0.5 else 1
	local out, hold, exit = P.out * k, P.hold * k, P.exit * k
	local x, y, s, a
	if p.still then
		x, y, s = p.dx, p.dy, 1
		a = if age < out then 1 - age / out else math.clamp((age - out - hold) / exit, 0, 1)
	elseif age < out then
		local f = backOut(age / out)
		x, y = p.dx * f, p.dy * f
		s = P.startScale + (1 - P.startScale) * f
		a = 0
	elseif age < out + hold then
		local f = (age - out) / hold
		x, y, s, a = p.dx, p.dy - P.drift * (1 - (1 - f) * (1 - f)), 1, 0
	else
		local f = math.clamp((age - out - hold) / exit, 0, 1)
		f *= f
		x, y = p.dx, p.dy - P.drift * (1 + 0.6 * f)
		s, a = 1 + (P.exitScale - 1) * f, f
	end
	p.group.Position = UDim2.new(0.5, x, 0.5, y)
	p.group.Rotation = P.tilt * p.side
	p.scale.Scale = s
	p.text.TextTransparency = a
	p.stroke.Transparency = a
	return age >= out + hold + exit
end

local function pop(i: number, amount: number, big: boolean)
	local P = U.pop
	local anchor = aims[i]
	if not anchor or amount <= 0 or #live >= P.maxActive then
		return
	end
	local p = table.remove(spare) or buildPop()
	local label = "+" .. Config.powerText(amount)
	local px = if big then P.bigPx else P.px
	p.text.Text = label
	p.text.TextSize = px
	p.stroke.Thickness = math.max(2, px * 0.1)
	p.grad.Color = ColorSequence.new(Theme.white, if big then TT.shatter else TT.power)
	local w = TextService:GetTextSize(label, px, Theme.font, Vector2.new(2000, 400)).X
	p.group.Size = UDim2.fromOffset(w + 8, px * 1.3)
	p.text.Size = UDim2.fromScale(1, 1)
	p.gui.Adornee = anchor
	popSide = -popSide
	p.side = popSide
	local lo, hi = P.outX[1], P.outX[2]
	p.dx = (lo + math.random() * (hi - lo)) * p.side * (if big then 0.4 else 1)
	p.dy = -(P.outY[1] + math.random() * (P.outY[2] - P.outY[1])) * (if big then 1.3 else 1)
	p.still = reduced()
	p.born = os.clock()
	placePop(p, 0)
	p.gui.Enabled = true
	table.insert(live, p)
end

local function stepPops(now: number)
	for k = #live, 1, -1 do
		local p = live[k]
		if placePop(p, now - p.born) then
			p.gui.Enabled = false
			table.remove(live, k)
			table.insert(spare, p)
		end
	end
end

-- ---------- the trainer signs ----------
-- "x5 Cold Power" over each owned pan's trainer, in its level's colour, lighter at the top (the
-- reference's chunky titles); retitled when its owner upgrades it
type Sign = { gui: BillboardGui, title: TextLabel, grad: UIGradient, anchor: Part, tier: number }
local signs: { [number]: Sign } = {}

local function buildSign(i: number)
	local anchor = anchorPart("TrainSign" .. i, Config.trainerTarget(i)) -- placed by refreshSigns
	local g = Instance.new("BillboardGui")
	g.Name = "TrainSign"
	g.LightInfluence = 0
	g.MaxDistance = U.signMaxDistance
	g.ResetOnSpawn = false
	g.Adornee = anchor
	local title = Ui.label(g, "", UDim2.fromScale(1, 1), UDim2.fromScale(0, 0))
	title.Name = "Title"
	title.TextScaled = false
	title.TextSize = U.signPx
	title.TextColor3 = Theme.white
	local stroke = title:FindFirstChildOfClass("UIStroke") :: UIStroke
	stroke.Thickness = math.max(3, U.signPx * 0.1)
	local grad = Instance.new("UIGradient")
	grad.Rotation = 90
	grad.Parent = title
	g.Parent = me:WaitForChild("PlayerGui")
	signs[i] = { gui = g, title = title, grad = grad, anchor = anchor, tier = 0 }
end

-- each frame: a sign shows only over a pan someone owns, with its trainer's current level
local function refreshSigns()
	local map = workspace:FindFirstChild("Map")
	for i, s in signs do
		local owned = map ~= nil and typeof(map:GetAttribute("PlotOwner" .. i)) == "number"
		s.gui.Enabled = owned
		local tier = tierAt(i)
		if tier ~= s.tier then
			local upgraded = s.tier ~= 0 and tier > s.tier
			s.tier = tier
			local st = T.stations[tier]
			local col = TT.stations[st.kind] and TT.stations[st.kind].title or TT.power
			local text = `x{st.mult} Cold Power`
			s.title.Text = text
			s.grad.Color = ColorSequence.new(col:Lerp(Theme.white, 0.35), col)
			local w = TextService:GetTextSize(text, U.signPx, Theme.font, Vector2.new(2000, 400)).X
			s.gui.Size = UDim2.fromOffset(w + 24, U.signPx * 1.3)
			local a = aims[i]
			if a then
				a.CFrame = CFrame.new(aimAt(i)) -- the bolts aim at the new target's middle
			end
			-- the title floats signGap studs over this level's target (clear of the CLICK! hint)
			s.anchor.CFrame = CFrame.new(Config.trainerTarget(i) + Vector3.new(0, T.padHeight + st.shell.bottom + st.shell.height + U.signGap, 0))
			if upgraded then -- the new trainer arrives with a burst in its colour
				EffectsController.burst(aimAt(i) - Vector3.new(0, 2, 0), col, 30)
				EffectsController.burst(aimAt(i) - Vector3.new(0, 2, 0), Theme.white, 12)
			end
		end
	end
end

-- ---------- "CLICK!" and the shatter meter over my target ----------
local hint: { gui: BillboardGui, text: TextLabel, fill: Frame, scale: UIScale }? = nil
local hintTween: Tween? = nil

local function buildHint()
	local g = Instance.new("BillboardGui")
	g.Name = "TrainHint"
	g.LightInfluence = 0
	g.AlwaysOnTop = true
	g.ResetOnSpawn = false
	g.Enabled = false
	g.Size = UDim2.fromOffset(U.hintPx * 5, U.hintPx * 2.1)
	local box = Instance.new("Frame")
	box.BackgroundTransparency = 1
	box.Size = UDim2.fromScale(1, 1)
	box.Parent = g
	local scale = Instance.new("UIScale")
	scale.Parent = box
	local text = Ui.label(box, "CLICK!", UDim2.new(1, 0, 0, U.hintPx * 1.25), UDim2.fromScale(0, 0))
	text.TextScaled = false
	text.TextSize = U.hintPx
	text.TextColor3 = TT.power
	local track = Instance.new("Frame")
	track.Name = "Meter"
	track.AnchorPoint = Vector2.new(0.5, 0)
	track.Position = UDim2.new(0.5, 0, 0, U.hintPx * 1.35)
	track.Size = UDim2.new(0.62, 0, 0, U.hintPx * 0.42)
	track.BackgroundColor3 = Theme.ink:Lerp(Theme.white, Config.ui.barTrackAlpha)
	track.BorderSizePixel = 0
	Ui.corner(track, 1)
	Ui.stroke(track)
	track.Parent = box
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BackgroundColor3 = TT.power
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(0, 1)
	Ui.corner(fill, 1)
	fill.Parent = track
	g.Parent = me:WaitForChild("PlayerGui")
	hint = { gui = g, text = text, fill = fill, scale = scale }
end

local function showHint(i: number)
	local h = hint
	if not h then
		return
	end
	local on = i ~= 0 and me:GetAttribute("TrainReady") == true
	if on then
		local d = InputController.device()
		h.text.Text = if d == "touch" then "TAP!" elseif d == "gamepad" then "R2!" else "CLICK!"
		local anchor = aims[i]
		h.gui.Adornee = anchor
		local st = stationOf(i)
		h.gui.StudsOffset = Vector3.new(0, st.shell.bottom + st.shell.height - st.aimY + U.hintY, 0) -- just over the target's top
	end
	if on ~= h.gui.Enabled then
		h.gui.Enabled = on
		if hintTween then
			hintTween:Cancel()
			hintTween = nil
		end
		h.scale.Scale = 1
		if on and not reduced() then
			hintTween = TweenService:Create(h.scale, TweenInfo.new(U.hintPulse.seconds, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Scale = U.hintPulse.scale })
			hintTween:Play()
		end
	end
end

-- ---------- shots I hear about ----------
-- the shatter: a hit-stop first (the target holds white and shakes, Sakurai's hit stop), then
-- everything lands at once: burst, rays, kick, the freeze crunch with a crystal tink an octave up
local function shatter(i: number, bonus: number)
	local to = aimAt(i)
	local hold = J.hitStop.shatter * (if reduced() then 0.5 else 1)
	local l = looks[i]
	if l then
		l.holdUntil = os.clock() + hold
		l.shake = if reduced() then 0 else J.hitShake
	end
	hitFlash(1, hold)
	task.delay(hold, function()
		wobble(i, true)
		EffectsController.burst(to - Vector3.new(0, 2, 0), TT.frost, 26)
		EffectsController.burst(to - Vector3.new(0, 2, 0), Theme.white, 10)
		if not lowGfx() then
			EffectsController.rays(to, TT.frostGlow, 8, 0.45)
		end
		CameraController.kick("lock", 0.6)
		SoundController.play("freeze")
		SoundController.play("tink", 2)
		task.delay(0.12, function()
			pop(i, bonus, true)
		end)
		frost.shown, frost.goal = 0, 0 -- the frost falls away with the burst
	end)
end

local function onTrain(data: any)
	if typeof(data) ~= "table" or typeof(data.station) ~= "number" or not Config.world.plots[data.station] then
		return
	end
	local i = data.station :: number
	local gain = if typeof(data.gain) == "number" then data.gain else 0
	local bonus = if typeof(data.bonus) == "number" then data.bonus else 0
	local meter = if typeof(data.meter) == "number" then data.meter else 0
	local function landed()
		if frost.station == i then
			frost.goal = if bonus > 0 then 1 else meter -- a shatter shows the full crust first
		end
		pop(i, gain, false)
		if bonus > 0 then
			shatter(i, bonus)
		end
	end
	if data.click == true then
		landed() -- my click's bolt was drawn when I clicked
	else
		drawShot(me, i, true, false, landed) -- my gun's own shot
	end
end

-- a click / tap / R2 / E on a station I can use: the bolt flies at once, the server counts it
local clicks: { number } = {}
local function tryShot(): boolean
	local i = myStation()
	if i == 0 or me:GetAttribute("TrainReady") ~= true then
		return false
	end
	local now = os.clock()
	local kept: { number } = {}
	for _, t in clicks do
		if now - t < 1 then
			table.insert(kept, t)
		end
	end
	clicks = kept
	if #kept >= T.clickMax then
		return true -- the same cap as the server: a faster click draws nothing it won't count
	end
	table.insert(kept, now)
	State.send("Train", "shot")
	drawShot(me, i, true, true, nil)
	CameraController.kick("fire", 0.5)
	SoundController.play("ray_clack", 1.05 + 0.15 * math.random())
	return true
end

-- ---------- lock mode: the STOP button ----------
local stopButton: Frame? = nil
local jumpOff = false -- I switched jumping off for the lock

local function pressStop()
	if not locked() then
		return
	end
	SoundController.play("click")
	State.send("Train", "stop")
end

local function buildStop()
	local holder = Instance.new("Frame")
	holder.Name = "TrainStop"
	holder.BackgroundTransparency = 1
	holder.Visible = false
	local b = Ui.block(holder, "Stop", Theme.no, "STOP", pressStop) -- red = stop / no (UI Rules)
	b.root.Size = UDim2.fromScale(1, 1)
	stopButton = holder
	Screen.register("trainStop", holder)
end

local function applyLock()
	local on = locked()
	if stopButton then
		stopButton.Visible = on
	end
	local c = me.Character
	local hum = c and c:FindFirstChildOfClass("Humanoid")
	if hum then
		if on then
			hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
			jumpOff = true
		elseif jumpOff then
			hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
			jumpOff = false
		end
	end
	if on then
		-- Space (jumping is off while locked) and gamepad B press STOP; B leaves an open popup to close it
		ContextActionService:BindActionAtPriority("IceRay_TrainStop", function(_, st: Enum.UserInputState, input: InputObject)
			if UserInputService:GetFocusedTextBox() or (Screen.popupOpen and input.KeyCode == Enum.KeyCode.ButtonB) then
				return Enum.ContextActionResult.Pass
			end
			if st == Enum.UserInputState.Begin then
				pressStop()
			end
			return Enum.ContextActionResult.Sink
		end, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.Space, Enum.KeyCode.ButtonB)
		-- once the server's snap has landed, the camera swings round behind me toward the target
		task.delay(0.2, function()
			local i = myStation()
			local root = me.Character and me.Character:FindFirstChild("HumanoidRootPart")
			if locked() and i ~= 0 and root and root:IsA("BasePart") then
				CameraController.lookPast(root, aimAt(i))
			end
		end)
	else
		ContextActionService:UnbindAction("IceRay_TrainStop")
	end
end

-- ---------- every frame ----------
local turned = false -- I switched AutoRotate off to face my target
local function faceTarget(i: number, dt: number)
	local c = me.Character
	local hum = c and c:FindFirstChildOfClass("Humanoid")
	local root = c and c:FindFirstChild("HumanoidRootPart")
	if not hum or not root or not root:IsA("BasePart") then
		return
	end
	local still = hum.MoveDirection.Magnitude < 0.1 and hum.FloorMaterial ~= Enum.Material.Air
	if i ~= 0 and (locked() or me:GetAttribute("TrainReady") == true and still) then
		local goal = Config.trainerTarget(i)
		local flat = Vector3.new(goal.X, root.Position.Y, goal.Z)
		if (flat - root.Position).Magnitude > 1 then
			hum.AutoRotate = false
			turned = true
			local want = CFrame.lookAt(root.Position, flat)
			root.CFrame = root.CFrame:Lerp(want, math.min(1, dt * U.turnSpeed))
		end
	elseif turned then
		hum.AutoRotate = true
		turned = false
	end
end

local function step(dt: number)
	local now = os.clock()
	refreshSigns()
	stepBolts(now)
	stepPops(now)
	local i = myStation()
	setFrostStation(i)
	if frost.station ~= 0 then
		local goal = frost.goal
		frost.shown += (goal - frost.shown) * math.min(1, dt * 10)
		paintFrost(frost.station, frost.shown)
	end
	-- almost there: my target shivers once the frost is past tremble.from, more as it nears a shatter
	local TR = J.tremble
	local shiver = 0
	if frost.station ~= 0 and frost.shown > TR.from and not reduced() then
		local k = math.clamp((frost.shown - TR.from) / (1 - TR.from), 0, 1)
		shiver = TR.amp * k * math.sin(now * TR.hz * 2 * math.pi)
	end
	for si, l in looks do
		stepWobble(l, now, if si == frost.station then shiver else 0)
	end
	local h = hint
	if h and h.gui.Enabled then
		h.fill.Size = UDim2.fromScale(math.clamp(frost.shown, 0, 1), 1)
	end
	faceTarget(i, dt)
end

local function watchOther(p: Player)
	if p == me then
		return
	end
	p:GetAttributeChangedSignal("TrainShots"):Connect(function()
		local i = p:GetAttribute("TrainStation")
		if typeof(i) == "number" and Config.world.plots[i] then
			drawShot(p, i, false, false, nil)
		end
	end)
end

function TrainingController.Init()
	folder = Instance.new("Folder")
	folder.Name = "TrainingVisuals"
	folder.Parent = workspace
end

function TrainingController.Start()
	local shell = Instance.new("Part")
	shell.Name = "FrostShell"
	shell.Shape = Enum.PartType.Cylinder
	shell.Material = Enum.Material.SmoothPlastic -- see-through panels are never Glass (World Rules 6)
	shell.Color = TT.frost
	shell.Transparency = 1
	shell.Anchored, shell.CanCollide, shell.CanQuery, shell.CanTouch, shell.CastShadow = true, false, false, false, false
	shell.Parent = folder
	frost.shell = shell
	for i in Config.world.plots do
		aims[i] = anchorPart("TrainAim" .. i, aimAt(i))
		buildSign(i)
	end
	buildHint()
	buildStop()
	me:GetAttributeChangedSignal("TrainLocked"):Connect(applyLock)
	applyLock()
	refreshSigns()
	for _, m in CollectionService:GetTagged(T.targetTag) do
		addTarget(m)
	end
	CollectionService:GetInstanceAddedSignal(T.targetTag):Connect(function(m)
		task.defer(addTarget, m) -- its children arrive with it; one beat later to be safe
	end)
	CollectionService:GetInstanceRemovedSignal(T.targetTag):Connect(removeTarget)
	local function refreshMine()
		local i = myStation()
		local m = me:GetAttribute("TrainMeter")
		if i ~= 0 and frost.station == i and typeof(m) == "number" and m > frost.goal then
			frost.goal = m -- coming back to a target you'd half-frosted
		end
		showHint(i)
	end
	for _, name in { "TrainStation", "TrainReady", "TrainMeter" } do
		me:GetAttributeChangedSignal(name):Connect(refreshMine)
	end
	refreshMine()
	for _, p in Players:GetPlayers() do
		watchOther(p)
	end
	Players.PlayerAdded:Connect(watchOther)
	State.Notify:Connect(function(kind: string, data: any)
		if kind == "train" then
			onTrain(data)
		end
	end)
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed or UserInputService:GetFocusedTextBox() then
			return
		end
		local t = input.UserInputType
		if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch
			or input.KeyCode == Enum.KeyCode.ButtonR2 or input.KeyCode == Enum.KeyCode.E then
			tryShot()
		end
	end)
	RunService.RenderStepped:Connect(step)
end

return TrainingController
