--!strict
-- UpgradeMotion (owner 2026-11-05): the fast pan upgrade, 0.9 s, so buying again feels good.
-- Press: the card's icon tile breathes in (0.92, a small tilt) while the server decides.
-- Impact (the server's answer lands): the tile pops to 1.15 under a white flash that cools into the
-- upgrade's colour, a ring and sparks burst out and the card's outline glows. The popup rebuilds the
-- card with the new level around the same moment, so the flash hides the swap. Then a spring settle,
-- three rising chimes and a gloss sweep. The button works again at 0.45 s; a press before that is
-- kept and sent at that moment. In the world, the pan lights up from the middle and cools, and a new
-- Look's pieces pop off and drop in under the light.
-- Front view (owner 2026-11-07, Config.motion.upgrade.frontView): when the answer lands, Show.panTrip hides
-- the popup and HUD and glides the camera to the front of your pan; the pan's upgrade plays there, the
-- camera glides back, the popup returns and only then does the card pop (its impact waits out the trip).
-- Prototype and timeline: prototype/ice-ray-for-pets/upgrade-demo.html. Numbers: Config.motion.upgrade.
-- Cards are rebuilt whenever a level changes, so the motion is kept per upgrade kind and drawn on
-- whichever card PanPopup has bound for that kind (UpgradeMotion.bind).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Config = require(ReplicatedStorage.Shared.Config)
local Theme = require(ReplicatedStorage.Shared.Theme)
local State = require(script.Parent.State)
local SettingsController = require(script.Parent.SettingsController)
local SoundController = require(script.Parent.SoundController)
local EffectsController = require(script.Parent.EffectsController)
local PanLooks = require(script.Parent.PanLooks)
local Show = require(script.Parent.Show)
local Ui = require(script.Parent.Parent.Lib.Ui)

local UpgradeMotion = {}
local C = Config.motion.upgrade

export type Parts = { card: Frame, tile: GuiObject, chip: GuiObject? }
type Anim = {
	t0: number,
	rm: number,
	from: number, -- the level when pressed
	impact: number?, -- seconds after t0 (scaled time), once the answer has landed
	startTile: number,
	startCard: number,
	buffered: (() -> ())?,
	fired: { [string]: boolean },
	glow: Color3,
	strength: number,
	big: boolean,
	streak: number,
	trip: boolean, -- the front view played: the pan had the hit sound, the card only chimes
}
type Fx = { kind: string, t0: number, life: number, gui: GuiObject, [string]: any }
type PanFx = { t0: number, rm: number, strength: number, glow: Color3, disk: Part, slab: Part, light: PointLight, maxD: number }

local bound: { [string]: Parts } = {}
local anims: { [string]: Anim } = {}
local fxList: { Fx } = {}
local panFx: PanFx? = nil
local lastFlash, lastImpact, streak = -9, -9, 0

local function reduced(): boolean
	return SettingsController.get("reducedMotion") == true
end
local function clamp01(x: number): number
	return math.clamp(x, 0, 1)
end
local function quadOut(t: number): number
	return 1 - (1 - t) * (1 - t)
end
local function quadIn(t: number): number
	return t * t
end
local function quadInOut(t: number): number
	return if t < 0.5 then 2 * t * t else 1 - (-2 * t + 2) ^ 2 / 2
end
local function sineInOut(t: number): number
	return -(math.cos(math.pi * t) - 1) / 2
end
local function backOut(t: number): number
	local c1 = 1.70158
	return 1 + (c1 + 1) * (t - 1) ^ 3 + c1 * (t - 1) ^ 2
end
local function spring(x: number, amp: number): number
	return 1 + amp * math.exp(-C.springK * x) * math.cos(C.springW * math.pi * x)
end

local function glowOf(kind: string, level: number): Color3
	if kind == "look" then
		return PanLooks.style(level).glow
	end
	return Theme.upgradeGlow[kind] or Theme.coin
end

-- one UIScale per thing, named so a rebuilt card gets a fresh one
local function scaleOf(g: Instance): UIScale
	local s = g:FindFirstChild("UpgradeScale")
	if s and s:IsA("UIScale") then
		return s
	end
	local n = Instance.new("UIScale")
	n.Name = "UpgradeScale"
	n.Parent = g
	return n
end

-- the flash and the gloss sweep sit over the card's face
local function overlays(p: Parts): (Frame?, Frame?)
	local face = p.card:FindFirstChild("Face")
	if not face then
		return nil, nil
	end
	local flash = face:FindFirstChild("UpgradeFlash") :: Frame?
	if not flash then
		local f = Instance.new("Frame")
		f.Name = "UpgradeFlash"
		f.BorderSizePixel = 0
		f.BackgroundColor3 = Color3.new(1, 1, 1)
		f.BackgroundTransparency = 1
		f.Size = UDim2.fromScale(1, 1)
		f.ZIndex = 10
		f.Active = false
		Ui.corner(f)
		f.Parent = face
		flash = f
	end
	local gloss = face:FindFirstChild("UpgradeGloss") :: Frame?
	if not gloss then
		local f = Instance.new("Frame")
		f.Name = "UpgradeGloss"
		f.BorderSizePixel = 0
		f.BackgroundColor3 = Color3.new(1, 1, 1)
		f.Size = UDim2.fromScale(1, 1)
		f.ZIndex = 11
		f.Visible = false
		f.Active = false
		Ui.corner(f)
		local g = Instance.new("UIGradient")
		g.Rotation = 20
		g.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.42, 1), NumberSequenceKeypoint.new(0.5, 0.4),
			NumberSequenceKeypoint.new(0.58, 1), NumberSequenceKeypoint.new(1, 1),
		})
		g.Parent = f
		f.Parent = face
		gloss = f
	end
	return flash, gloss
end

-- a layer over the whole popup gui for the ring and the sparks, so a rebuild doesn't cut them off
local function layerFor(g: GuiObject): Frame?
	local gui = g:FindFirstAncestorWhichIsA("ScreenGui")
	if not gui then
		return nil
	end
	local l = gui:FindFirstChild("UpgradeFx") :: Frame?
	if not l then
		local f = Instance.new("Frame")
		f.Name = "UpgradeFx"
		f.BackgroundTransparency = 1
		f.Size = UDim2.fromScale(1, 1)
		f.ZIndex = 50
		f.Active = false
		f.Parent = gui
		l = f
	end
	return l
end

local function centreIn(layer: Frame, g: GuiObject): Vector2
	return g.AbsolutePosition + g.AbsoluteSize / 2 - layer.AbsolutePosition
end

local function addFx(kind: string, gui: GuiObject, life: number, extra: { [string]: any })
	local fx = extra :: Fx
	fx.kind, fx.gui, fx.life, fx.t0 = kind, gui, life, os.clock()
	table.insert(fxList, fx)
end

local function ring(p: Parts, glow: Color3, width: number)
	local layer = layerFor(p.tile)
	if not layer then
		return
	end
	local f = Instance.new("Frame")
	f.Name = "Ring"
	f.BackgroundTransparency = 1
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromOffset(centreIn(layer, p.tile).X, centreIn(layer, p.tile).Y)
	Ui.corner(f, 0.22)
	local s = Instance.new("UIStroke")
	s.Color = glow
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.LineJoinMode = Enum.LineJoinMode.Round
	s.Parent = f
	f.Parent = layer
	addFx("ring", f, C.ring, { size = p.tile.AbsoluteSize.X, stroke = s, width = width })
end

local function sparks(p: Parts, at: GuiObject, glow: Color3, n: number, speed: number)
	local layer = layerFor(at)
	if not layer then
		return
	end
	local c = centreIn(layer, at)
	local cols = { glow, Color3.new(1, 1, 1), Theme.coinFace }
	local rng = Random.new()
	local size = p.tile.AbsoluteSize.X
	for i = 1, (if reduced() then math.ceil(n / 2) else n) do
		local a = rng:NextNumber(0, math.pi * 2)
		local v = rng:NextNumber(220, 540) * speed * size / 90
		local d = rng:NextNumber(8, 16) * size / 90 -- (4-9 read as specks in Studio)
		local f = Instance.new("Frame")
		f.Name = "Spark"
		f.BackgroundColor3 = cols[(i - 1) % 3 + 1]
		f.BorderSizePixel = 0
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Size = UDim2.fromOffset(d, d)
		f.Rotation = 45
		local st = Instance.new("UIStroke")
		st.Color = Theme.ink
		st.Thickness = 1.5
		st.Parent = f
		f.Parent = layer
		addFx("spark", f, rng:NextNumber(0.35, 0.5), { x = c.X, y = c.Y, vx = math.cos(a) * v, vy = math.sin(a) * v - 60, last = os.clock(), spin = rng:NextNumber(-360, 360), stroke = st })
	end
end

-- frost motes pulled into the tile during the build-up
local function motes(p: Parts, glow: Color3)
	if reduced() then
		return
	end
	local layer = layerFor(p.tile)
	if not layer then
		return
	end
	local c = centreIn(layer, p.tile)
	local size = p.tile.AbsoluteSize.X
	local rng = Random.new()
	for _ = 1, C.motes do
		local a, r = rng:NextNumber(0, math.pi * 2), size * rng:NextNumber(0.9, 1.6)
		local d = rng:NextNumber(4, 8) * size / 90
		local f = Instance.new("Frame")
		f.Name = "Mote"
		f.BackgroundColor3 = glow:Lerp(Color3.new(1, 1, 1), 0.5)
		f.BackgroundTransparency = 1
		f.BorderSizePixel = 0
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Size = UDim2.fromOffset(d, d)
		Ui.corner(f, 0.5)
		f.Parent = layer
		addFx("mote", f, C.build - 0.03, { x0 = c.X + math.cos(a) * r, y0 = c.Y + math.sin(a) * r, cx = c.X, cy = c.Y })
	end
end

local function stepFx()
	local now = os.clock()
	local rm = if reduced() then C.reduced.time else 1
	local keep: { Fx } = {}
	for _, fx in fxList do
		local u = (now - fx.t0) / rm / fx.life
		if u >= 1 or not fx.gui.Parent then
			fx.gui:Destroy()
			continue
		end
		table.insert(keep, fx)
		if fx.kind == "mote" then
			local k = quadIn(u)
			fx.gui.Position = UDim2.fromOffset(fx.x0 + (fx.cx - fx.x0) * k, fx.y0 + (fx.cy - fx.y0) * k)
			fx.gui.BackgroundTransparency = 1 - math.min(1, u * 4) * (1 - k * 0.3)
		elseif fx.kind == "spark" then
			local dt = (now - fx.last) / rm
			fx.last = now
			fx.vx *= 0.02 ^ dt
			fx.vy = fx.vy * 0.02 ^ dt + 500 * dt
			fx.x += fx.vx * dt
			fx.y += fx.vy * dt
			fx.gui.Position = UDim2.fromOffset(fx.x, fx.y)
			fx.gui.Rotation = 45 + fx.spin * u
			fx.gui.BackgroundTransparency = quadIn(u)
			fx.stroke.Transparency = quadIn(u)
		elseif fx.kind == "ring" then
			local k = quadOut(u)
			local s = fx.size * (1 + C.ringGrow * k)
			fx.gui.Size = UDim2.fromOffset(s, s)
			fx.stroke.Thickness = (6 - 5 * u) * fx.width
			fx.stroke.Transparency = 1 - 0.8 * (1 - u)
		end
	end
	fxList = keep
end

-- ---------- the pan in the world ----------
local function panEcho(kind: string, data: any, a: Anim)
	local plot = data.plot
	if typeof(plot) ~= "number" or not Config.world.plots[plot] then
		return
	end
	local P = C.pan
	local W = Config.world.pans
	local centre = PanLooks.center(plot)
	local rm = a.rm
	if kind == "look" and typeof(data.level) == "number" then
		local look = data.level :: number
		PanLooks.popOff(plot, P.popOff * rm)
		task.delay(P.popOff * rm, function()
			PanLooks.dropIn(plot, look, P.dropIn * rm)
		end)
	end
	EffectsController.burst(centre + Vector3.new(0, 1, 0), a.glow, if a.big then P.burstBig else P.burst)
	local strength = a.strength * (P.strength[kind] or 1) * (if reduced() then 0.45 else 1)
	if strength <= 0 then
		return
	end
	if panFx then
		panFx.disk:Destroy()
		panFx.slab:Destroy()
	end
	local function part(name: string, shape: Enum.PartType): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Shape = shape
		p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
		p.Material = Enum.Material.Neon
		p.Color = Color3.new(1, 1, 1)
		p.Transparency = 1
		p.Parent = workspace
		return p
	end
	local disk = part("UpgradeDisk", Enum.PartType.Cylinder)
	disk.Size = Vector3.new(0.1, 0.2, 0.2)
	disk.CFrame = CFrame.new(centre + Vector3.new(0, 0.14, 0)) * CFrame.Angles(0, 0, math.pi / 2)
	local slab = part("UpgradeFloor", Enum.PartType.Block)
	slab.Size = Vector3.new(W.width, 0.08, W.length)
	slab.CFrame = CFrame.new(centre + Vector3.new(0, 0.1, 0))
	local light = Instance.new("PointLight")
	light.Range = P.lightRange
	light.Brightness = 0
	light.Color = a.glow
	light.Parent = slab
	panFx = { t0 = os.clock(), rm = rm, strength = strength, glow = a.glow, disk = disk, slab = slab, light = light, maxD = math.min(W.width, W.length) * 1.05 }
end

local function stepPan()
	local f = panFx
	if not f then
		return
	end
	local P = C.pan
	local q = (os.clock() - f.t0) / f.rm
	if q >= P.fadeTo then
		f.disk:Destroy()
		f.slab:Destroy()
		panFx = nil
		return
	end
	local white = Color3.new(1, 1, 1)
	-- a disk of light from the middle (white core cooling to the colour)
	local d = math.max(0.2, f.maxD * quadOut(clamp01(q / P.expand)))
	f.disk.Size = Vector3.new(0.1, d, d)
	local da = if q < P.expand then 1 else 1 - clamp01((q - P.expand) / 0.1)
	f.disk.Transparency = 1 - 0.9 * da * f.strength
	f.disk.Color = white:Lerp(f.glow, clamp01(q / 0.3))
	-- then the whole floor, cooling and fading
	local fa = 0
	if q >= P.fillFrom and q < P.fillFull then
		fa = (q - P.fillFrom) / (P.fillFull - P.fillFrom)
	elseif q >= P.fillFull and q < P.holdTo then
		fa = 1
	elseif q >= P.holdTo then
		fa = 1 - clamp01((q - P.holdTo) / (P.fadeTo - P.holdTo))
	end
	f.slab.Transparency = 1 - 0.85 * fa * f.strength
	f.slab.Color = white:Lerp(f.glow, clamp01((q - 0.15) / 0.3))
	f.light.Brightness = P.light * f.strength * math.max(da * quadOut(clamp01(q / P.expand)), fa)
end

-- ---------- the card ----------
local function impact(kind: string, a: Anim)
	local p = bound[kind]
	if not a.trip then
		SoundController.play("upgrade_hit")
	end
	if p and p.card.Parent then
		ring(p, a.glow, if a.big then 1.4 else 1)
		sparks(p, p.tile, a.glow, if a.big then C.sparksBig else C.sparks, 1)
	end
end

local function apply(kind: string, a: Anim?)
	local p = bound[kind]
	if not p or not p.card.Parent then
		return
	end
	local tileS, cardS = scaleOf(p.tile), scaleOf(p.card)
	local flash, gloss = overlays(p)
	local stroke = p.card:FindFirstChildOfClass("UIStroke")
	if stroke and stroke:GetAttribute("BaseThickness") == nil then
		stroke:SetAttribute("BaseThickness", stroke.Thickness)
	end
	if not a then
		tileS.Scale, cardS.Scale, p.tile.Rotation = 1, 1, 0
		if flash then
			flash.BackgroundTransparency = 1
		end
		if gloss then
			gloss.Visible = false
		end
		if stroke then
			stroke.Color = Theme.ink
			stroke.Thickness = stroke:GetAttribute("BaseThickness") :: number
		end
		if p.chip then
			scaleOf(p.chip).Scale = 1
		end
		return
	end
	local R = reduced()
	local e = (os.clock() - a.t0) / a.rm
	local buildScale = if R then C.reduced.buildScale else C.buildScale
	local popScale = if R then C.reduced.popScale else C.popScale
	local cardPop = if R then C.reduced.cardPop else C.cardPop
	local tilt0 = if R then 0 else C.buildTilt
	local ts, cs, tilt, flashA, flashC, g, sweep, chip = 1, 1, 0, 0, Color3.new(1, 1, 1), 0, -1, 1
	if e < C.build then
		local u = sineInOut(clamp01(e / C.build))
		ts = a.startTile + (buildScale - a.startTile) * u
		cs = a.startCard + (C.cardBuild - a.startCard) * u
		tilt = tilt0 * u
	elseif a.impact == nil or e < a.impact then -- waiting for a slow server: hold the breath
		ts, cs = buildScale, C.cardBuild
		tilt = tilt0 + (if R then 0 else math.sin(e * math.pi * 2 * C.shiverHz) * C.shiverDeg)
	end
	local imp = a.impact
	if imp and e >= imp then
		local q = e - imp
		if q < C.pop then
			local k = backOut(q / C.pop)
			ts = buildScale + (popScale - buildScale) * k
			cs = C.cardBuild + (cardPop - C.cardBuild) * k
			tilt = tilt0 * (1 - quadOut(q / C.pop))
		elseif q < C.pop + C.peakHold then
			ts, cs = popScale, cardPop
		else
			local x = clamp01((q - C.pop - C.peakHold) / C.settle)
			ts, cs = spring(x, popScale - 1), spring(x, cardPop - 1)
		end
		local fa = if R then C.reduced.flashAlpha else C.flashAlpha
		if q < C.flash then
			flashA = fa * a.strength * (1 - q / C.flash) ^ 1.5
			flashC = flashC:Lerp(a.glow, clamp01(q / C.flashCool))
		end
		g = if q < 0.04 then q / 0.04 else 1 - clamp01((q - 0.04) / (C.glow - 0.04))
		if q >= C.shimmerAt and q < C.shimmerAt + C.shimmer then
			sweep = quadInOut((q - C.shimmerAt) / C.shimmer)
		end
		if q < C.chipPop then
			chip = 1 + 0.3 * math.sin(math.pi * q / C.chipPop)
		end
	end
	tileS.Scale, cardS.Scale, p.tile.Rotation = ts, cs, tilt
	if flash then
		flash.BackgroundTransparency = 1 - flashA
		flash.BackgroundColor3 = flashC
	end
	if gloss then
		gloss.Visible = sweep >= 0
		local grad = gloss:FindFirstChildOfClass("UIGradient")
		if grad then
			grad.Offset = Vector2.new(-1 + 2 * math.max(0, sweep), 0)
		end
	end
	if stroke then
		stroke.Color = Theme.ink:Lerp(a.glow, g)
		stroke.Thickness = (stroke:GetAttribute("BaseThickness") :: number) + C.glowStroke * g
	end
	if p.chip then
		scaleOf(p.chip).Scale = chip
	end
end

local function land(kind: string, a: Anim, data: any?)
	if a.impact then
		return
	end
	local now = os.clock()
	local landed = math.max(C.build, (now - a.t0) / a.rm)
	a.trip = C.frontView == true
	-- with the front view the card pops when the popup comes back
	a.impact = if a.trip then landed + C.trip.go + C.trip.watch + C.trip.back else landed
	local level = if data and typeof(data.level) == "number" then data.level else a.from + 1
	a.glow = glowOf(kind, level)
	a.big = level % 5 == 0 or (Config.panMax(kind) == level)
	local since = now - lastFlash
	a.strength = if since < C.flashSkipGap then 0 elseif since < C.flashSoftGap then 0.5 else 1
	if a.strength > 0 then
		lastFlash = now
	end
	streak = if now - lastImpact < C.streakReset then math.min(C.streakMax, streak + 1) else 0
	a.streak, lastImpact = streak, now
end

local function step()
	for kind, a in anims do
		local e = (os.clock() - a.t0) / a.rm
		local fire = function(name: string, at: number, fn: () -> ())
			if not a.fired[name] and e >= at then
				a.fired[name] = true
				fn()
			end
		end
		if not a.impact and e > C.maxWait then -- no answer: let go quietly (the server said why, if anything)
			anims[kind] = nil
			apply(kind, nil)
			continue
		end
		local imp = a.impact
		if imp then
			fire("impact", imp, function()
				impact(kind, a)
			end)
			for i, t in C.chimes do
				fire("chime" .. i, imp + t, function()
					SoundController.play("upgrade_chime", 2 ^ ((a.streak + (i - 1) * 4) / 12))
				end)
			end
			local buffered = a.buffered
			if buffered and e >= imp + C.inputOpen then
				a.buffered = nil
				buffered()
			end
			if anims[kind] == a and e >= imp + C.total then
				anims[kind] = nil
				apply(kind, nil)
				continue
			end
		end
		if anims[kind] == a then
			apply(kind, a)
		end
	end
	stepFx()
	stepPan()
end

-- PanPopup calls this for every card it builds; a running motion carries on on the new card
function UpgradeMotion.bind(kind: string, parts: Parts)
	bound[kind] = parts
	apply(kind, anims[kind])
end

-- the Buy button: starts the build-up and sends now, or keeps the press for when input opens.
-- canAfford: the client's own check, so a press the server will refuse doesn't wind up
function UpgradeMotion.press(kind: string, level: number, canAfford: boolean, send: () -> ())
	local a = anims[kind]
	if a then
		local e = (os.clock() - a.t0) / a.rm
		if not a.impact or e < a.impact + C.inputOpen then
			a.buffered = send
			return
		end
	end
	if not canAfford then
		send() -- the server answers with its "not yet"
		return
	end
	local p = bound[kind]
	local tileNow = if p then scaleOf(p.tile).Scale else 1
	local cardNow = if p then scaleOf(p.card).Scale else 1
	local na: Anim = {
		t0 = os.clock(), rm = if reduced() then C.reduced.time else 1, from = level, impact = nil,
		startTile = tileNow, startCard = cardNow, buffered = nil, fired = {}, glow = glowOf(kind, level + 1),
		strength = 1, big = false, streak = 0, trip = false,
	}
	anims[kind] = na
	SoundController.play("upgrade_charge")
	if p then
		motes(p, na.glow)
	end
	send()
end

function UpgradeMotion.Init() end

function UpgradeMotion.Start()
	RunService.RenderStepped:Connect(step)
	State.Notify:Connect(function(kind: string, data: any)
		if kind ~= "panUpgraded" or not C.fastPan or typeof(data) ~= "table" then
			return
		end
		local k = data.kind
		if typeof(k) ~= "string" then
			return
		end
		local a = anims[k]
		if not a then -- bought some other way (a buffered press already ended, a second device): still answer it
			a = {
				t0 = os.clock() - C.build, rm = if reduced() then C.reduced.time else 1, from = (data.level or 2) - 1, impact = nil,
				startTile = 1, startCard = 1, buffered = nil, fired = {}, glow = glowOf(k, data.level or 1), strength = 1, big = false, streak = 0, trip = false,
			}
			anims[k] = a
		end
		land(k, a, data)
		if a.trip then
			local anim = a
			task.spawn(Show.panTrip, data, a.rm, function()
				SoundController.play("upgrade_hit")
				panEcho(k, data, anim)
			end)
		else
			panEcho(k, data, a)
		end
	end)
end

return UpgradeMotion
