--!strict
-- TrainingController (owner 2026-11-10; replaces the rink's client): Cold Power training on this client.
-- Every pan has its own trainer in front of it (TrainingService builds it at its owner's level). The
-- server decides every shot and its Cold Power; this only draws, and sends intent ("Train" "shot" on a
-- click / tap / R2 / E while you stand on your own trainer). Stations below = pans' trainers.
--   Label:  "+N/shot" over my own trainer (the Cold Power one shot gives me now), only while I'm within
--           signShowStuds of it (owner 2026-11-11, from the reference's "+30/step").
--   Bolts:  a frost bolt flies from a player's gun tip to the target on each of their shots: my clicks at
--           once, my gun's own shots when the server says (Notify "train"), everyone else's from their
--           TrainShots counter. The gun flashes, the target wobbles and puffs frost where it's hit.
--   Frost:  on the target I'm training on, frost climbs up it and its warm parts (named Heat) cool toward
--           ice as my meter fills; at a shatter it bursts, flashes and the frost falls away.
--   Pops:   "+N" shoots off the target to one side on each of my shots (CoinPops' motion); a shatter's
--           bonus is a big gold one.
--   Facing: standing still on a station turns you to face its target.
--   Lock:   while the server holds you at your trainer ("TrainLocked", owner 2026-11-11), you always face
--           the target and the camera swings round behind you once. Any jump (Space, the touch jump
--           button, gamepad A) or gamepad B tells the server to let you go and hops you off the pad the
--           way you're pushing, or to your right if you aren't (the owner's reference clip, 2026-11-11;
--           Config.training.lock.hop). The hop is a drawn arc, so it clears the trainer's low walls, but
--           never a solid wall like a pan fence. No STOP button (owner 2026-11-11: like the reference).
-- No HUD pieces; the Cold Power counter (HudController) already bounces as it climbs.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Theme = require(ReplicatedStorage.Shared.Theme)
local Ui = require(script.Parent.Parent.Lib.Ui)
local State = require(script.Parent.State)
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

-- the server holds me at my trainer until I jump off
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

-- ---------- the trainers' levels, and my "+N/shot" label ----------
-- Every pan: when its trainer's level changes, the bolts aim at the new target's middle and the new
-- trainer arrives with a burst in its colour.
-- Over MY trainer only (owner 2026-11-11, from the reference's "+30/step"): "+N/shot", the Cold Power one
-- shot gives me right now (the server's own Config.trainGain), in my trainer level's colour. It shows only
-- while my character stands within signShowStuds of the trainer.
local tiers: { [number]: number } = {}
type Sign = { gui: BillboardGui, title: TextLabel, grad: UIGradient, anchor: Part, plot: number, tier: number, text: string }
local sign: Sign? = nil

local function buildSign()
	local anchor = anchorPart("TrainSign", Vector3.zero) -- placed by refreshTrainers
	local g = Instance.new("BillboardGui")
	g.Name = "TrainSign"
	g.LightInfluence = 0
	g.ResetOnSpawn = false
	g.Enabled = false
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
	sign = { gui = g, title = title, grad = grad, anchor = anchor, plot = 0, tier = 0, text = "" }
end

-- the Cold Power one of my shots gives on a trainer of this level (what TrainingService pays)
local function myGain(tier: number): number
	local v = State.view
	if not v then
		return 0
	end
	local gun = me:GetAttribute("GunTier")
	return Config.trainGain(tier, Config.powerLevel(v.coldPower or 0), if typeof(gun) == "number" then gun else 1,
		v.rebirths or 0, me:GetAttribute("Pass_doublePower") == true)
end

local function refreshTrainers()
	for i in Config.world.plots do
		local tier = tierAt(i)
		local was = tiers[i]
		if tier ~= was then
			tiers[i] = tier
			local a = aims[i]
			if a then
				a.CFrame = CFrame.new(aimAt(i))
			end
			if was and tier > was then
				local st = T.stations[tier]
				local col = TT.stations[st.kind] and TT.stations[st.kind].title or TT.power
				EffectsController.burst(aimAt(i) - Vector3.new(0, 2, 0), col, 30)
				EffectsController.burst(aimAt(i) - Vector3.new(0, 2, 0), Theme.white, 12)
			end
		end
	end
	local s = sign
	if not s then
		return
	end
	local v = State.view
	local i = if v and v.plot and Config.world.plots[v.plot] then v.plot else 0
	local root = me.Character and me.Character:FindFirstChild("HumanoidRootPart")
	local near = false
	if i ~= 0 and root and root:IsA("BasePart") then
		local t = Config.trainerTarget(i)
		near = Vector3.new(root.Position.X - t.X, 0, root.Position.Z - t.Z).Magnitude <= U.signShowStuds
	end
	s.gui.Enabled = near
	if not near then
		return
	end
	local tier = tiers[i] or 1
	if i ~= s.plot or tier ~= s.tier then
		s.plot, s.tier = i, tier
		local st = T.stations[tier]
		local col = TT.stations[st.kind] and TT.stations[st.kind].title or TT.power
		s.grad.Color = ColorSequence.new(col:Lerp(Theme.white, 0.35), col)
		-- signGap studs over this level's target
		s.anchor.CFrame = CFrame.new(Config.trainerTarget(i) + Vector3.new(0, T.padHeight + st.shell.bottom + st.shell.height + U.signGap, 0))
	end
	local text = `+{Config.powerText(myGain(tier))}/shot`
	if text ~= s.text then
		s.text = text
		s.title.Text = text
		local w = TextService:GetTextSize(text, U.signPx, Theme.font, Vector2.new(2000, 400)).X
		s.gui.Size = UDim2.fromOffset(w + 24, U.signPx * 1.3)
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

-- ---------- lock mode: hopping off (any jump, gamepad B) ----------
-- The hop goes the way I'm pushing (keys / thumbstick), or to my right if I'm not (the reference clip),
-- just far enough to clear the pad. It never crosses a solid wall (the pan fences, booths) and never
-- lands inside something; if that way has no clear landing it tries my right, else I'm just let go.
local hopped = false -- I've asked to leave this lock (cleared when the next one starts)
type Hop = { t0: number, seconds: number, from: Vector3, to: Vector3, yaw0: number, yaw1: number }
local hop: Hop? = nil

-- locked in and not already leaving
local function holding(): boolean
	return locked() and not hopped
end

local function solidParams(ignore: { Instance }): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	params.RespectCanCollide = true
	return params
end

-- the solid ground's height under a point (my character ignored)
local function groundY(from: Vector3, ignore: Instance): number?
	local hit = workspace:Raycast(from, Vector3.new(0, -40, 0), solidParams({ ignore }))
	return if hit then hit.Position.Y else nil
end

-- the facing angle of a flat direction (CFrame.Angles(0, yaw, 0) looks along it)
local function yawOf(v: Vector3): number
	return math.atan2(-v.X, -v.Z)
end

-- where a hop from p (standing standH over the pad's top padTop) the way dir lands, or nil if that
-- way is blocked: past the pad's edge by hop.clear, pushed further out while the spot is taken
local function landingFor(i: number, p: Vector3, dir: Vector3, standH: number, padTop: number, c: Instance): Vector3?
	local H = T.lock.hop
	local centre = Config.trainerCentre(i)
	local hx, hz = T.padSize[1] / 2 + 0.4, T.padSize[2] / 2 + 0.4 -- the pad and its rim
	local exit = math.huge
	if math.abs(dir.X) > 1e-3 then
		exit = math.min(exit, ((centre.X + math.sign(dir.X) * hx) - p.X) / dir.X)
	end
	if math.abs(dir.Z) > 1e-3 then
		exit = math.min(exit, ((centre.Z + math.sign(dir.Z) * hz) - p.Z) / dir.Z)
	end
	if exit == math.huge then
		return nil
	end
	local trainers = workspace:FindFirstChild("Trainers")
	local pathIgnore: { Instance } = if trainers then { c, trainers } else { c } -- the arc clears the trainer
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	overlap.FilterDescendantsInstances = { c }
	overlap.RespectCanCollide = true
	for k = 0, H.tries - 1 do
		local d = math.max(0, exit) + H.clear + k * H.step
		local land = p + dir * d
		-- a solid wall on the way (fences, booths) = this way is closed
		local from = p + Vector3.new(0, 1.5, 0)
		if workspace:Raycast(from, dir * d, solidParams(pathIgnore)) then
			return nil
		end
		local gy = groundY(Vector3.new(land.X, p.Y + 6, land.Z), c)
		if gy and gy <= padTop + 0.3 and gy >= padTop - 4 then
			local body = CFrame.new(land.X, gy + 0.3 + standH, land.Z)
			if #workspace:GetPartBoundsInBox(body, Vector3.new(2.4, standH * 2 - 0.6, 2.4), overlap) == 0 then
				return Vector3.new(land.X, gy + standH, land.Z)
			end
		end
	end
	return nil
end

local function hopOff()
	if not holding() then
		return
	end
	hopped = true
	State.send("Train", "stop")
	local i = myStation()
	local c = me.Character
	local hum = c and c:FindFirstChildOfClass("Humanoid")
	local root = c and c:FindFirstChild("HumanoidRootPart")
	if i == 0 or not c or not hum or not root or not root:IsA("BasePart") or hum.Health <= 0 then
		return
	end
	local p = root.Position
	local at = Config.trainerTarget(i)
	local flat = Vector3.new(at.X - p.X, 0, at.Z - p.Z)
	local look = if flat.Magnitude > 0.1 then flat.Unit else Vector3.zAxis
	local right = look:Cross(Vector3.yAxis) -- my right as I face the target
	local move = Vector3.new(hum.MoveDirection.X, 0, hum.MoveDirection.Z)
	local dir = if move.Magnitude > 0.1 then move.Unit else right
	local floor = groundY(p, c)
	local standH = if floor then p.Y - floor else hum.HipHeight + root.Size.Y / 2
	local padTop = p.Y - standH
	local to = landingFor(i, p, dir, standH, padTop, c)
	if not to and dir ~= right then
		dir = right
		to = landingFor(i, p, dir, standH, padTop, c)
	end
	if not to then
		return -- nowhere clear to land: just let go here
	end
	local H = T.lock.hop
	local dist = Vector3.new(to.X - p.X, 0, to.Z - p.Z).Magnitude
	hum:ChangeState(Enum.HumanoidStateType.Jumping) -- the jump animation and sound
	hum.AutoRotate = false
	hop = { t0 = os.clock(), seconds = H.seconds + H.perStud * dist, from = p, to = to, yaw0 = yawOf(root.CFrame.LookVector), yaw1 = yawOf(dir) }
end

-- each frame of the hop: up and over to the landing spot, turning toward where I'm going
local function stepHop(now: number)
	local h = hop
	if not h then
		return
	end
	local c = me.Character
	local hum = c and c:FindFirstChildOfClass("Humanoid")
	local root = c and c:FindFirstChild("HumanoidRootPart")
	if not hum or not root or not root:IsA("BasePart") or hum.Health <= 0 then
		hop = nil
		return
	end
	local H = T.lock.hop
	local u = math.min(1, (now - h.t0) / h.seconds)
	local base = h.from:Lerp(h.to, u)
	local pos = base + Vector3.new(0, 4 * H.height * u * (1 - u), 0)
	local turn = (h.yaw1 - h.yaw0 + math.pi) % (2 * math.pi) - math.pi -- the short way round
	root.CFrame = CFrame.new(pos) * CFrame.Angles(0, h.yaw0 + turn * math.min(1, u * 1.5), 0)
	if u < 1 then
		-- moving along the arc, so physics carries on the same way between frames
		local d = (h.to - h.from) / h.seconds
		root.AssemblyLinearVelocity = Vector3.new(d.X, d.Y + 4 * H.height * (1 - 2 * u) / h.seconds, d.Z)
	else
		root.AssemblyLinearVelocity = Vector3.new(0, -10, 0)
		hum.AutoRotate = true
		hop = nil
	end
end

local function applyLock()
	local on = locked()
	if on then
		hopped = false
		-- gamepad B hops off too (jumps come through JumpRequest); B leaves an open popup to close it
		ContextActionService:BindActionAtPriority("IceRay_TrainStop", function(_, st: Enum.UserInputState, input: InputObject)
			if UserInputService:GetFocusedTextBox() or Screen.popupOpen then
				return Enum.ContextActionResult.Pass
			end
			if st == Enum.UserInputState.Begin then
				hopOff()
			end
			return Enum.ContextActionResult.Sink
		end, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.ButtonB)
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
	if not hum or not root or not root:IsA("BasePart") or hop then
		return -- the hop steers me itself
	end
	local still = hum.MoveDirection.Magnitude < 0.1 and hum.FloorMaterial ~= Enum.Material.Air
	if i ~= 0 and not hopped and (locked() or me:GetAttribute("TrainReady") == true and still) then
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
	refreshTrainers()
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
	stepHop(now)
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
	end
	buildSign()
	me:GetAttributeChangedSignal("TrainLocked"):Connect(applyLock)
	applyLock()
	refreshTrainers()
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
	-- any jump while locked in (Space, the touch jump button, gamepad A) hops me off
	UserInputService.JumpRequest:Connect(hopOff)
	RunService.RenderStepped:Connect(step)
end

return TrainingController
