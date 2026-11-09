--!strict
-- ThawMachines (owner 2026-11-07: the Thaw Machine "looks so boring ... make it more techy and
-- futuristic, much more detailed"): brings every pan's Thaw Machine (MapArt.thawMachine) to life on
-- this client. Nothing here changes the game; the server still decides when a pet is out.
--  - Idle: it breathes in ice blue. A slow running light round the rim, the halo turning gently, the
--    core tube a little lit, the beacon pulsing green, the screen saying READY.
--  - Thawing (a PenPets cube with Thaw = "machine" and Machine = its number): the heat climbs from ice
--    blue through amber to hot orange as the time runs out. The core tube fills, beams reach into the
--    cube from the six halo nodes, the two pylons and the overhead emitter, melt vapour rises off the
--    cube, the halo tilts and speeds up, the rim light races, the stacks puff harder and the screen
--    counts the % and the seconds left.
--  - Release: one burst (sparks, a vapour puff, a shock ring along the deck, the halo flashing white
--    once) and OUT! on the screen, then it cools back to blue.
-- Numbers in Config.thaw.fx, colours in Theme.round5. Kid-safe: smooth pulses, one flash per release.
-- Reduced motion: slower turns, no bob or tilt, the shock ring fades without growing.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Theme = require(ReplicatedStorage.Shared.Theme)
local PetDefs = require(ReplicatedStorage.Shared.PetDefs)
local WorldText = require(ReplicatedStorage.Shared.WorldText)
local SettingsController = require(script.Parent.SettingsController)
local SoundController = require(script.Parent.SoundController)

local ThawMachines = {}
local me = Players.LocalPlayer
local FX = Config.thaw.fx
local R5 = Theme.round5
local TAU = math.pi * 2

type Spin = { part: BasePart, off: CFrame }
type Screen = { gui: SurfaceGui, status: TextLabel, sub: TextLabel, queue: TextLabel, fill: Frame, scan: Frame }
type Machine = {
	model: Model,
	plot: number,
	m: number,
	chase: { BasePart },
	coils: { BasePart },
	glows: { BasePart }, -- nozzle, pylon emitters, halo nodes, halo edge, inner ring: they all glow the heat colour
	strips: { BasePart },
	leds: { [number]: BasePart },
	core: BasePart,
	light: PointLight?,
	fill: BasePart?,
	fillCF: CFrame,
	fillSize: Vector3,
	beacon: BasePart?,
	halo: { Spin },
	haloCF: CFrame,
	inner: BasePart?,
	innerCF: CFrame,
	stacks: { ParticleEmitter },
	-- made on this client
	target: Part,
	mid: Attachment,
	top: Attachment,
	mist: ParticleEmitter,
	sparks: ParticleEmitter,
	beams: { Beam },
	screen: Screen?,
	-- state
	phase: number,
	chaseAt: number,
	angle: number,
	innerAngle: number,
	heat: number,
	flash: number,
	outUntil: number,
	outName: string,
	cube: BasePart?,
	queue: number,
	culled: boolean,
}

local machines: { [Model]: Machine } = {}
local fxFolder: Folder? = nil
local meshes: Instance? = nil

-- ice blue -> amber -> hot orange as the heat goes 0 -> 1
local function heatColor(h: number): Color3
	if h < 0.5 then
		return R5.machineCold:Lerp(R5.machineWarm, h * 2)
	end
	return R5.machineWarm:Lerp(R5.machineHot, (h - 0.5) * 2)
end

local function wave(t: number, hz: number, phase: number?): number -- 0..1, smooth
	return 0.5 + 0.5 * math.sin(t * hz * TAU + (phase or 0))
end

local function plain(p: BasePart)
	p.Anchored = true
	p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = false, false, false, false
end

local function attach(part: BasePart, name: string, offset: Vector3?): Attachment
	local a = Instance.new("Attachment")
	a.Name = name
	a.Position = offset or Vector3.zero
	a.Parent = part
	return a
end

local function beam(from: Attachment, to: Attachment, parent: Instance): Beam
	local b = Instance.new("Beam")
	b.Attachment0 = from
	b.Attachment1 = to
	b.Width0 = FX.beam.from
	b.Width1 = FX.beam.to
	b.FaceCamera = true
	b.LightEmission = 1
	b.LightInfluence = 0
	b.Segments = 1
	b.Enabled = false
	b.Parent = parent
	return b
end

-- the holo screen: a title, the queue, a big status, a progress bar, the pet's name and time left,
-- and a scan line sweeping down (WorldText: crisp, one fixed size per role, ink outlines)
local function makeScreen(part: BasePart, m: number): Screen
	local sg, px = WorldText.surface(part, "ThawScreen", Enum.NormalId.Back) -- the machine faces +Z
	sg.MaxDistance = FX.drawDistance * 0.6
	local w, h = px.X, px.Y
	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = R5.machineScreen
	bg.BorderSizePixel = 0
	bg.ClipsDescendants = true
	bg.Parent = sg
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, math.floor(h * 0.08))
	corner.Parent = bg
	local edge = Instance.new("UIStroke")
	edge.Color = R5.machineCold
	edge.Thickness = 2
	edge.Transparency = 0.35
	edge.Parent = bg
	local grad = Instance.new("UIGradient")
	grad.Rotation = 90
	grad.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(150, 160, 190))
	grad.Parent = bg
	-- faint grid lines: the "holo" look
	for k = 1, 4 do
		local line = Instance.new("Frame")
		line.Size = UDim2.new(1, 0, 0, 1)
		line.Position = UDim2.fromScale(0, k / 5)
		line.BackgroundColor3 = R5.machineCold
		line.BackgroundTransparency = 0.88
		line.BorderSizePixel = 0
		line.Parent = bg
	end
	local scan = Instance.new("Frame")
	scan.Size = UDim2.new(1, 0, 0, 3)
	scan.BackgroundColor3 = R5.machineCold
	scan.BackgroundTransparency = 0.7
	scan.BorderSizePixel = 0
	scan.Parent = bg
	local pad = math.floor(w * 0.05)
	local title = WorldText.label(bg, `THAW POD {m}`, math.floor(h * 0.13), R5.machineCold, true, UDim2.new(0.6, -pad, 0, math.floor(h * 0.18)), UDim2.fromOffset(pad, math.floor(h * 0.04)))
	title.TextXAlignment = Enum.TextXAlignment.Left
	local queue = WorldText.label(bg, "", math.floor(h * 0.12), R5.machineWarm, true, UDim2.new(0.4, -pad, 0, math.floor(h * 0.18)), UDim2.new(0.6, 0, 0, math.floor(h * 0.04)))
	queue.TextXAlignment = Enum.TextXAlignment.Right
	local status = WorldText.label(bg, "READY", math.floor(h * 0.36), R5.machineReady, true, UDim2.new(1, 0, 0, math.floor(h * 0.4)), UDim2.fromOffset(0, math.floor(h * 0.2)))
	local track = Instance.new("Frame")
	track.Size = UDim2.new(1, -pad * 2, 0, math.floor(h * 0.1))
	track.Position = UDim2.new(0, pad, 0, math.floor(h * 0.63))
	track.BackgroundColor3 = R5.machineDark
	track.BorderSizePixel = 0
	track.Parent = bg
	local tc = Instance.new("UICorner")
	tc.CornerRadius = UDim.new(1, 0)
	tc.Parent = track
	local ts = Instance.new("UIStroke")
	ts.Color = R5.machineCold
	ts.Thickness = 1.5
	ts.Transparency = 0.4
	ts.Parent = track
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = R5.machineCold
	fill.BorderSizePixel = 0
	fill.Parent = track
	local fc = Instance.new("UICorner")
	fc.CornerRadius = UDim.new(1, 0)
	fc.Parent = fill
	local sub = WorldText.label(bg, "", math.floor(h * 0.13), Theme.white, true, UDim2.new(1, -pad * 2, 0, math.floor(h * 0.2)), UDim2.new(0, pad, 0, math.floor(h * 0.76)))
	sg.Adornee = part
	sg.Parent = part
	return { gui = sg, status = status, sub = sub, queue = queue, fill = fill, scan = scan }
end

local function setup(model: Model, plot: number, m: number): Machine?
	local halo = model:FindFirstChild("Halo")
	local centre = halo and halo:FindFirstChild("HaloCenter")
	local core = model:FindFirstChild("CoilCore")
	if not (centre and centre:IsA("BasePart") and core and core:IsA("BasePart")) then
		return nil -- an older map, or not streamed in yet
	end
	local folder = fxFolder :: Folder
	local target = Instance.new("Part")
	target.Name = "ThawTarget"
	target.Size = Vector3.one * 3
	target.Transparency = 1
	plain(target)
	target.CFrame = core.CFrame + Vector3.new(0, 1.5, 0)
	target.Parent = folder
	local mc: Machine = {
		model = model, plot = plot, m = m,
		chase = {}, coils = {}, glows = {}, strips = {}, leds = {},
		core = core, light = core:FindFirstChildOfClass("PointLight"),
		fill = nil, fillCF = CFrame.identity, fillSize = Vector3.one,
		beacon = nil, halo = {}, haloCF = centre.CFrame, inner = nil, innerCF = CFrame.identity,
		stacks = {},
		target = target, mid = attach(target, "Mid"), top = attach(target, "Top", Vector3.new(0, 1.5, 0)),
		mist = Instance.new("ParticleEmitter"), sparks = Instance.new("ParticleEmitter"),
		beams = {}, screen = nil,
		phase = math.random() * TAU, chaseAt = 0, angle = 0, innerAngle = 0, heat = 0, flash = 0,
		outUntil = 0, outName = "", cube = nil, queue = 0, culled = true,
	}
	for _, d in model:GetDescendants() do
		if not d:IsA("BasePart") then
			continue
		end
		local n = d.Name
		if n == "Chase" then
			mc.chase[(d:GetAttribute("I") :: number?) or (#mc.chase + 1)] = d
		elseif n == "Coil" then
			table.insert(mc.coils, d)
		elseif n == "Strip" then
			table.insert(mc.strips, d)
		elseif n == "Led" then
			mc.leds[(d:GetAttribute("I") :: number?) or 1] = d
		elseif n == "GaugeFill" then
			mc.fill, mc.fillCF, mc.fillSize = d, d.CFrame, d.Size
		elseif n == "Beacon" then
			mc.beacon = d
		elseif n == "HaloInner" then
			mc.inner, mc.innerCF = d, d.CFrame
			table.insert(mc.glows, d)
		elseif n == "Screen" then
			mc.screen = makeScreen(d, m)
		elseif n == "Stack" then
			local e = Instance.new("ParticleEmitter")
			e.Color = ColorSequence.new(Theme.white)
			e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 1) })
			e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 1.6) })
			e.Lifetime = NumberRange.new(1.2, 1.8)
			e.Speed = NumberRange.new(2, 3)
			e.SpreadAngle = Vector2.new(10, 10)
			e.Rotation = NumberRange.new(0, 360)
			e.RotSpeed = NumberRange.new(-30, 30)
			e.EmissionDirection = Enum.NormalId.Top
			e.Rate = 0
			e.Parent = d
			table.insert(mc.stacks, e)
		elseif n == "Nozzle" then
			table.insert(mc.glows, d)
			table.insert(mc.beams, beam(attach(d, "Out"), mc.top, target))
		elseif n == "Emitter" then
			table.insert(mc.glows, d)
			table.insert(mc.beams, beam(attach(d, "Out"), mc.mid, target))
		elseif n == "HaloNode" then
			table.insert(mc.glows, d)
			table.insert(mc.beams, beam(attach(d, "Out"), mc.mid, target))
		elseif n == "HaloGlow" then
			table.insert(mc.glows, d)
		end
	end
	-- the halo's parts turn together round its centre
	for _, d in (halo :: Instance):GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(mc.halo, { part = d, off = centre.CFrame:ToObjectSpace(d.CFrame) })
		end
	end
	-- melt vapour off the cube's sides while it thaws
	local mist = mc.mist
	mist.Shape = Enum.ParticleEmitterShape.Box
	mist.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
	mist.Color = ColorSequence.new(Theme.white, R5.machineGlass)
	mist.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.2, 0.45), NumberSequenceKeypoint.new(1, 1) })
	mist.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1.3) })
	mist.Lifetime = NumberRange.new(1, 1.6)
	mist.Speed = NumberRange.new(0.4, 1)
	mist.Acceleration = Vector3.new(0, 1.8, 0)
	mist.Drag = 1
	mist.Rotation = NumberRange.new(0, 360)
	mist.RotSpeed = NumberRange.new(-40, 40)
	mist.LightEmission = 0.2
	mist.Rate = 0
	mist.Parent = target
	-- the release sparks
	local sparks = mc.sparks
	sparks.Shape = Enum.ParticleEmitterShape.Sphere
	sparks.Color = ColorSequence.new(R5.machineWarm, R5.machineHot)
	sparks.LightEmission = 1
	sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) })
	sparks.Lifetime = NumberRange.new(0.45, 0.85)
	sparks.Speed = NumberRange.new(9, 15)
	sparks.Drag = 4
	sparks.Acceleration = Vector3.new(0, -10, 0)
	sparks.Rate = 0
	sparks.Parent = target
	return mc
end

local function drop(mc: Machine)
	mc.target:Destroy()
	if mc.screen then
		mc.screen.gui:Destroy()
	end
	for _, e in mc.stacks do
		e:Destroy()
	end
	machines[mc.model] = nil
end

-- a ring of light running out along the deck when a pet is let out
local function shockRing(mc: Machine, reduced: boolean)
	local B = FX.burst
	local template = meshes and meshes:FindFirstChild("Ring")
	local ring: BasePart
	if template and template:IsA("MeshPart") then
		ring = template:Clone()
	else
		local p = Instance.new("Part")
		p.Shape = Enum.PartType.Cylinder
		ring = p
	end
	plain(ring)
	ring.Material = Enum.Material.Neon
	ring.Color = R5.machineWarm
	ring.Transparency = 0.15
	local flat = ring:IsA("MeshPart")
	local function size(d: number): Vector3
		return if flat then Vector3.new(d, 0.12, d) else Vector3.new(0.05, d, d)
	end
	local from = if reduced then B.ringTo * 0.6 else B.ringFrom
	ring.Size = size(from)
	local cf = CFrame.new(mc.core.Position + Vector3.new(0, 0.08, 0))
	ring.CFrame = if flat then cf else cf * CFrame.Angles(0, 0, math.pi / 2)
	ring.Parent = fxFolder
	local seconds = B.ring * (if reduced then 0.5 else 1)
	local goal: { [string]: any } = { Transparency = 1 }
	if not reduced then
		goal.Size = size(B.ringTo)
	end
	TweenService:Create(ring, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goal):Play()
	task.delay(seconds + 0.05, function()
		ring:Destroy()
	end)
end

local function release(mc: Machine, cube: BasePart)
	local B = FX.burst
	local reduced = SettingsController.get("reducedMotion") == true
	local def = PetDefs.get(cube:GetAttribute("PetKey") :: string)
	mc.outName = if def then def.name else "Your pet"
	mc.outUntil = os.clock() + B.outFor
	mc.flash = 1
	mc.heat = math.max(mc.heat, 1)
	if mc.culled then
		return
	end
	mc.target.CFrame = cube.CFrame
	mc.sparks:Emit(if reduced then math.ceil(B.sparks / 2) else B.sparks)
	mc.mist:Emit(B.mist)
	shockRing(mc, reduced)
	if cube:GetAttribute("PenOwner") == me.UserId then
		SoundController.play("thaw_done")
	end
end

-- which cube each machine is thawing, and how long each pan's line is
local function scanCubes()
	local active: { [string]: BasePart } = {}
	local queued: { [number]: number } = {}
	local folder = workspace:FindFirstChild("PenPets")
	if folder then
		for _, c in folder:GetChildren() do
			local plot = c:GetAttribute("Plot")
			if c:IsA("BasePart") and typeof(plot) == "number" then
				local th = c:GetAttribute("Thaw")
				if th == "machine" then
					local k = c:GetAttribute("Machine")
					active[`{plot}:{if typeof(k) == "number" then k else 1}`] = c
				elseif th == "queue" then
					queued[plot] = (queued[plot] or 0) + 1
				end
			end
		end
	end
	for _, mc in machines do
		local c = active[`{mc.plot}:{mc.m}`]
		local old = mc.cube
		if old and c ~= old and old.Parent and old:GetAttribute("Thaw") == "out" then
			release(mc, old) -- its pet just came out
		end
		mc.cube = c
		mc.queue = queued[mc.plot] or 0
	end
end

-- find each pan's machines (the hub streams in; maps get rebuilt)
local panFolders: { [number]: Instance } = {}
local function scanModels()
	for model, mc in machines do
		if not model.Parent then
			drop(mc)
		end
	end
	local map = workspace:FindFirstChild("Map")
	if not map then
		return
	end
	for i in Config.world.plots do
		local f = panFolders[i]
		if not f or not f:IsDescendantOf(map) then
			f = map:FindFirstChild("Pan" .. i, true)
			if f then
				panFolders[i] = f
			end
		end
		if f then
			for m = 1, 2 do
				local model = f:FindFirstChild("ThawMachine" .. m)
				if model and model:IsA("Model") and not machines[model] then
					local mc = setup(model, i, m)
					if mc then
						machines[model] = mc
					end
				end
			end
		end
	end
end

local function hidden(mc: Machine): boolean
	if mc.m == 1 then
		return false
	end
	local map = workspace:FindFirstChild("Map")
	local plot = map and map:FindFirstChild("Plot" .. mc.plot)
	return not plot or plot:GetAttribute("Machines") ~= 2
end

local function sleep(mc: Machine)
	mc.culled = true
	mc.mist.Rate = 0
	for _, e in mc.stacks do
		e.Rate = 0
	end
	for _, b in mc.beams do
		b.Enabled = false
	end
end

local function updateScreen(mc: Machine, active: boolean, p: number, left: number, lit: Color3, t: number)
	local s = mc.screen
	if not s then
		return
	end
	local status, sub, color, bar, barColor
	if os.clock() < mc.outUntil then
		status, color, bar, barColor = "OUT!", R5.machineReady, 1, R5.machineReady
		sub = `{mc.outName} is out!`
	elseif active then
		status, color, bar, barColor = `{math.floor(p * 100)}%`, lit, p, lit
		local cube = mc.cube :: BasePart
		local def = PetDefs.get(cube:GetAttribute("PetKey") :: string)
		sub = `{if def then def.name else "Thawing"}  {Config.timeText(left)}`
	else
		status, color, bar, barColor = "READY", R5.machineReady, 0, R5.machineCold
		sub = "Put a pet in!" -- you put frozen pets in yourself (owner 2026-11-09)
	end
	if s.status.Text ~= status then
		s.status.Text = status
	end
	s.status.TextColor3 = color
	if s.sub.Text ~= sub then
		s.sub.Text = sub
	end
	local q = if mc.queue >= Config.thaw.queueShown then `{mc.queue}+ IN LINE` elseif mc.queue > 0 then `{mc.queue} IN LINE` else ""
	if s.queue.Text ~= q then
		s.queue.Text = q
	end
	s.fill.Size = UDim2.fromScale(math.clamp(bar, 0, 1), 1)
	s.fill.BackgroundColor3 = barColor
	s.scan.Position = UDim2.fromScale(0, (t / FX.scanline) % 1)
end

local function update(mc: Machine, t: number, dt: number, reduced: boolean)
	-- progress from the server's clock
	local cube = mc.cube
	local active = cube ~= nil and cube.Parent ~= nil
	local p, left = 0, 0
	if active then
		local c = cube :: BasePart
		local ends, total = c:GetAttribute("ThawEnd"), c:GetAttribute("ThawTotal")
		if typeof(ends) == "number" and typeof(total) == "number" and total > 0 then
			left = math.max(0, ends - workspace:GetServerTimeNow())
			p = math.clamp(1 - left / total, 0, 1)
		end
	end
	mc.heat += ((if active then p else 0) - mc.heat) * math.min(1, dt * FX.heatFollow)
	local h = mc.heat
	mc.flash = math.max(0, mc.flash - dt / FX.burst.flash)
	local lit = heatColor(h):Lerp(Theme.white, mc.flash)
	local motion = if reduced then 0.35 else 1
	local pulse = wave(t, FX.pulse.speed, mc.phase)

	-- the rim lights: a running light with a fading tail, faster as it heats
	local C = FX.chase
	local n = math.max(1, #mc.chase)
	mc.chaseAt = (mc.chaseAt + dt * (if active then C.from + (C.to - C.from) * h else C.idle) * motion) % n
	for i, c in mc.chase do
		local behind = (mc.chaseAt - (i - 1)) % n
		local on = if behind < C.tail then 1 - behind / C.tail else 0
		c.Color = lit
		c.Transparency = 0.78 - 0.78 * on
	end
	-- the pad's coils and core: a soft ripple outward
	for k, c in mc.coils do
		c.Color = lit
		c.Transparency = if active then 0.25 * wave(t, 1.6 + 2 * h, -k) else 0.3 + 0.25 * wave(t, 0.5, -k)
	end
	mc.core.Color = lit
	mc.core.Transparency = if active then 0 else 0.2 * wave(t, 0.5)
	local L = FX.light
	if mc.light then
		mc.light.Color = lit
		mc.light.Brightness = (if active then L.from + (L.to - L.from) * h else L.idle) + mc.flash * 2
	end
	-- the core tube fills with the heat (drains back after a release)
	local fill = mc.fill
	if fill then
		local G = FX.gauge
		local full = mc.fillSize.X -- an upright cylinder's length is its X size
		local len = math.max(0.05, full * math.max(G.idleLevel + G.breathe * math.sin(t * 1.4), h))
		fill.Size = Vector3.new(len, mc.fillSize.Y, mc.fillSize.Z)
		fill.CFrame = mc.fillCF - Vector3.yAxis * ((full - len) / 2)
		fill.Color = lit
	end
	-- emitters, nodes, the halo's edge and the inner ring
	for _, g in mc.glows do
		g.Color = lit
		g.Transparency = if active or mc.flash > 0 then 0 else 0.35
	end
	for _, s in mc.strips do
		s.Color = lit
		s.Transparency = if active then 0.05 + FX.pulse.strip * pulse else 0.45
	end
	-- status lights: power (steady), working (pulses while thawing), ready (breathes while idle)
	local power, busy, ready = mc.leds[1], mc.leds[2], mc.leds[3]
	if power then
		power.Color = R5.machineCold
		power.Transparency = 0.05
	end
	if busy then
		busy.Color = R5.machineWarm
		busy.Transparency = if active then 0.6 * wave(t, 1) else 0.85
	end
	if ready then
		ready.Color = R5.machineReady
		ready.Transparency = if active then 0.85 else 0.35 * wave(t, 0.5)
	end
	if mc.beacon then
		local B = FX.beacon
		mc.beacon.Color = if active then R5.machineWarm else R5.machineReady
		mc.beacon.Transparency = 0.6 * wave(t, if active then B.active else B.idle)
	end
	-- the halo turns (and wobbles a little while thawing); the inner ring turns the other way
	local H = FX.halo
	mc.angle += dt * (if active then H.spinFrom + (H.spinTo - H.spinFrom) * h else H.idleSpin) * motion
	mc.innerAngle += dt * H.innerSpin * (if active then 1 + 2 * h else 0.5) * motion
	local bob = if reduced then 0 else math.sin(t * H.bobSpeed * TAU + mc.phase) * H.bob
	local tilt = if reduced then 0 else 0.06 * h
	local base = mc.haloCF * CFrame.new(0, bob, 0) * CFrame.Angles(math.sin(t * 2) * tilt, 0, math.cos(t * 2) * tilt) * CFrame.Angles(0, mc.angle, 0)
	for _, s in mc.halo do
		s.part.CFrame = base * s.off
	end
	if mc.inner then
		mc.inner.CFrame = mc.innerCF * CFrame.new(0, bob, 0) * CFrame.Angles(0, mc.innerAngle, 0)
	end
	-- beams into the cube, vapour off it, steam out of the stacks
	if active then
		local c = cube :: BasePart
		mc.target.CFrame = c.CFrame
		mc.target.Size = c.Size
		mc.top.Position = Vector3.new(0, c.Size.Y / 2, 0)
	end
	local beamOn = (active and h > 0.02) or mc.flash > 0
	local seq = ColorSequence.new(lit)
	local tr = NumberSequence.new(FX.beam.transparency + FX.pulse.beam * pulse, math.min(1, 0.55 + FX.pulse.beam * pulse))
	local width = 0.8 + 0.4 * h
	for _, b in mc.beams do
		b.Enabled = beamOn
		if beamOn then
			b.Color = seq
			b.Transparency = tr
			b.Width0 = FX.beam.from * width
			b.Width1 = FX.beam.to * width
		end
	end
	local M, S = FX.mist, FX.steam
	mc.mist.Rate = if active then M.from + (M.to - M.from) * h else 0
	for _, e in mc.stacks do
		e.Rate = if active then S.from + (S.to - S.from) * h else S.idle
	end
	updateScreen(mc, active, p, left, lit, t)
end

function ThawMachines.Init()
	local f = Instance.new("Folder")
	f.Name = "ThawMachineFx"
	f.Parent = workspace
	fxFolder = f
	meshes = ReplicatedStorage:FindFirstChild("SceneryMeshes")
end

function ThawMachines.Start()
	task.spawn(function()
		while true do
			scanModels()
			task.wait(2)
		end
	end)
	task.spawn(function()
		while true do
			scanCubes()
			task.wait(FX.scanEvery)
		end
	end)
	RunService.RenderStepped:Connect(function(dt: number)
		local cam = workspace.CurrentCamera
		local t = os.clock()
		local reduced = SettingsController.get("reducedMotion") == true
		for _, mc in machines do
			local far = not cam or (cam.CFrame.Position - mc.core.Position).Magnitude > FX.drawDistance
			if far or hidden(mc) then
				if not mc.culled then
					sleep(mc)
				end
				if mc.screen then
					mc.screen.gui.Enabled = false
				end
				continue
			end
			mc.culled = false
			if mc.screen then
				mc.screen.gui.Enabled = true
			end
			update(mc, t, dt, reduced)
		end
	end)
end

return ThawMachines
