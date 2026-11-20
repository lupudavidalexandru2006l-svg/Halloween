--!strict
-- EffectsController: bursts (freeze, bank), the light pillar over a pen when someone banks a
-- Legendary or better, and Big Chill snow. Low graphics halves the particles; reduced motion keeps
-- bursts small and the pillar still.
-- Round 4 phase 3: the moment a cube shuts. At 100% the cube snaps shut at the pet's spot (a puff of
-- frost; a flash-freeze adds a quick glow and a light "tink"), the gun's finishing touch plays
-- (spikes, an aurora shimmer or a star sparkle) and the cube flies into your hands. Legendary and up
-- get a show instead (Show module), built from the pieces here (pillar, burst, rays, flash).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Theme = require(ReplicatedStorage.Shared.Theme)
local WorldRules = require(ReplicatedStorage.Shared.WorldRules)
local PetDefs = require(ReplicatedStorage.Shared.PetDefs)
local State = require(script.Parent.State)
local SettingsController = require(script.Parent.SettingsController)
local SoundController = require(script.Parent.SoundController)
local PetVisuals = require(script.Parent.PetVisuals)

local EffectsController = {}
local E = Config.effects
local F = Config.show.freeze
local J = Config.juice -- hit-stop and the bank tally (Animation Rules 8, Sound Rules 11)
local snow: Part? = nil
local flashFrame: Frame? = nil
local meshes: Instance? = nil

local function reduced(): boolean
	return SettingsController.get("reducedMotion") == true
end

-- reduced motion halves every look timing (Animation Rules 1)
function EffectsController.time(seconds: number): number
	return seconds * (if reduced() then 0.5 else 1)
end

local function anchor(pos: Vector3): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Transparency = 1
	p.Size = Vector3.new(1, 1, 1)
	p.Position = pos
	p.Parent = workspace
	return p
end

-- a glowing shape for an effect (a scenery mesh when it's there, else a plain part)
local function glow(size: Vector3, color: Color3, mesh: string?): BasePart
	local template = mesh and meshes and meshes:FindFirstChild(mesh)
	local p: BasePart = if template and template:IsA("MeshPart") then template:Clone() else Instance.new("Part")
	p.Size = size
	p.Color = color
	p.Material = Enum.Material.Neon
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Parent = workspace
	return p
end

local function amount(n: number): number
	local f = if SettingsController.get("lowGraphics") then 0.5 else 1
	f *= if reduced() then 0.5 else 1
	return math.max(1, math.floor(n * f))
end

function EffectsController.burst(pos: Vector3, color: Color3, count: number?)
	local p = anchor(pos + Vector3.new(0, 2, 0))
	local e = Instance.new("ParticleEmitter")
	e.Color = ColorSequence.new(color)
	e.Speed = NumberRange.new(6, 12)
	e.Lifetime = NumberRange.new(0.4, 0.8)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Rate = 0
	e.Parent = p
	e:Emit(amount(count or E.burstParts))
	task.delay(1.5, function()
		p:Destroy()
	end)
end

-- a soft cloud of frost where the cube shut
local function puff(pos: Vector3, count: number)
	local p = anchor(pos)
	local e = Instance.new("ParticleEmitter")
	e.Color = ColorSequence.new(Theme.fx.frost)
	e.LightEmission = 0.4
	e.Transparency = NumberSequence.new(0.2, 1)
	e.Size = NumberSequence.new(0.6, 1.6)
	e.Speed = NumberRange.new(2, 5)
	e.Drag = 4
	e.Lifetime = NumberRange.new(0.5, 0.9)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Rate = 0
	e.Parent = p
	e:Emit(amount(count))
	task.delay(1.2, function()
		p:Destroy()
	end)
end

-- a light pillar in the tier's colour; rise > 0 grows it up from the ground first
function EffectsController.pillar(pos: Vector3, color: Color3, seconds: number?, rise: number?)
	local life = seconds or E.pillarSeconds
	local p = anchor(pos)
	p.Shape = Enum.PartType.Cylinder
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Transparency = 0.4
	local function place(h: number)
		p.Size = Vector3.new(math.max(0.1, h), 6, 6)
		p.CFrame = CFrame.new(pos + Vector3.new(0, h / 2, 0)) * CFrame.Angles(0, 0, math.rad(90))
	end
	if rise and rise > 0 then
		place(0.1)
		local t0 = os.clock()
		local conn: RBXScriptConnection
		conn = RunService.RenderStepped:Connect(function()
			local u = math.min(1, (os.clock() - t0) / rise)
			place(E.pillarHeight * (1 - (1 - u) ^ 2))
			if u >= 1 or not p.Parent then
				conn:Disconnect()
			end
		end)
	else
		place(E.pillarHeight)
	end
	if not reduced() then
		TweenService:Create(p, TweenInfo.new(life, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Transparency = 1 }):Play()
	end
	task.delay(life, function()
		p:Destroy()
	end)
end

-- light rays turning slowly round a point, fading out (Rare-and-up shows)
function EffectsController.rays(pos: Vector3, color: Color3, count: number, seconds: number)
	local parts: { BasePart } = {}
	for i = 1, count do
		local r = glow(Vector3.new(0.35, 0.35, 9), color, nil)
		r.Transparency = 0.35
		table.insert(parts, r)
	end
	local t0 = os.clock()
	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(function()
		local u = (os.clock() - t0) / seconds
		if u >= 1 then
			conn:Disconnect()
			for _, r in parts do
				r:Destroy()
			end
			return
		end
		local spin = if reduced() then 0 else u * 0.8
		for i, r in parts do
			local a = i * (2 * math.pi / count) + spin
			r.CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, a) * CFrame.new(0, 5, 0) * CFrame.Angles(math.pi / 2, 0, 0)
			r.Transparency = 0.35 + 0.65 * u
		end
	end)
end

-- one full-screen flash (a soft fade with reduced motion). Shows use one flash each, far under the
-- 3-per-second limit (Animation Rules 1).
function EffectsController.flash()
	local f = flashFrame
	if not f then
		return
	end
	local U = Config.show.ui
	f.BackgroundTransparency = if reduced() then U.softFlashAlpha else U.flashAlpha
	f.Visible = true
	local tw = TweenService:Create(f, TweenInfo.new(EffectsController.time(U.flashSeconds) * (if reduced() then 2 else 1)), { BackgroundTransparency = 1 })
	tw.Completed:Once(function()
		f.Visible = false
	end)
	tw:Play()
end

-- the gun's finishing touch round a cube that just shut (higher gun tiers)
function EffectsController.touch(kind: string, at: CFrame, size: number)
	local time = EffectsController.time(F.touchSeconds)
	local parts: { { part: BasePart, from: CFrame, to: CFrame, size: Vector3 } } = {}
	if kind == "spikes" then
		for i = 1, F.spikeCount do
			local a = i * (2 * math.pi / F.spikeCount)
			local base = at * CFrame.Angles(0, a, 0) * CFrame.new(0, size * 0.35, -size * 0.45) * CFrame.Angles(-0.6, 0, 0)
			local s = glow(Vector3.new(0.4, F.spikeHeight, 0.4), Theme.fx.crystal, "Cone")
			s.Material = Enum.Material.Glass
			s.Transparency = 0.1
			table.insert(parts, { part = s, from = base, to = base * CFrame.new(0, F.spikeHeight * 0.5, 0), size = s.Size })
		end
	elseif kind == "aurora" then
		for i = 1, F.auroraBands do
			local ring = glow(Vector3.new(size * 1.6, 0.12, size * 1.6), Theme.fx.aurora[(i - 1) % #Theme.fx.aurora + 1], "Ring")
			ring.Transparency = 0.3
			local from = at * CFrame.new(0, -size * 0.4 + i * 0.25, 0)
			table.insert(parts, { part = ring, from = from, to = from * CFrame.new(0, size * 0.9, 0) * CFrame.Angles(0, 2, 0), size = ring.Size })
		end
	elseif kind == "stars" then
		for i = 1, F.starCount do
			local a = i * (2 * math.pi / F.starCount)
			local s = glow(Vector3.new(0.35, 0.5, 0.35), Theme.fx.star, "Octa")
			table.insert(parts, { part = s, from = at, to = at * CFrame.Angles(0, a, 0) * CFrame.new(0, size * 0.4, -size * 1.1), size = s.Size })
		end
	end
	for _, p in parts do
		p.part.CFrame = p.from
		TweenService:Create(p.part, TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = p.to, Transparency = 1 }):Play()
		task.delay(time, function()
			p.part:Destroy()
		end)
	end
end

-- the real cube for this freeze: waiting on the ground (right after the freeze) or in my hands (after E).
-- It replicates with the notice; wait a moment if needed.
function EffectsController.realCube(uid: any): BasePart?
	if typeof(uid) ~= "string" then
		return nil
	end
	local t0 = os.clock()
	while os.clock() - t0 < 1 do
		for _, name in { "Cubes", "GroundCubes" } do
			local folder = workspace:FindFirstChild(name)
			for _, c in (if folder then folder:GetChildren() else {}) do
				if c:GetAttribute("CubeUid") == uid and c:IsA("BasePart") then
					return c
				end
			end
		end
		task.wait()
	end
	return nil
end

-- E on my cube on the ground: it flies from there into my hands (the same fly as a freeze used to end with)
local function pickUp(data: any)
	local def = PetDefs.get(data.key)
	if not def then
		return
	end
	local real = EffectsController.realCube(data.uid)
	local size = if real then real.Size.X else PetDefs.cube(def, data.sz, true) * Config.carry.scale
	local model = PetVisuals.frozenCube(data.key, size)
	if not model then
		return
	end
	if real then
		real:SetAttribute("ShowHidden", true)
	end
	model:PivotTo(data.from)
	EffectsController.flyHome(model, real, EffectsController.time(F.flySeconds))
end

-- move the shown cube into your hands, then show the real one again
function EffectsController.flyHome(model: Model, real: BasePart?, seconds: number)
	local start = model:GetPivot()
	local t0 = os.clock()
	while true do
		local u = math.min(1, (os.clock() - t0) / math.max(0.01, seconds))
		local target = if real and real.Parent then real.CFrame else start
		model:PivotTo(start:Lerp(target, u * u))
		if u >= 1 then
			break
		end
		RunService.RenderStepped:Wait()
	end
	if real then
		real:SetAttribute("ShowHidden", nil)
	end
	model:Destroy()
end

-- where a cube that shut at a pet's spot sits (its bottom on the pet's ground)
function EffectsController.cubeAt(data: any, size: number): CFrame
	local def = PetDefs.get(data.key)
	local h = if def then PetDefs.height(def, data.sz) else 3
	local at: Vector3 = data.at
	return CFrame.new(at - Vector3.new(0, h / 2, 0) + Vector3.new(0, size / 2, 0))
end

-- ---------- the snap in detail (2026-11-17 realism pass, Config.show.freeze) ----------
-- ice shards burst off the new cube, spin, fall and bounce on the ground, then fade
function EffectsController.shards(center: Vector3, size: number, groundY: number, count: number?)
	local S = F.shards
	local n = amount(count or S.count)
	local r = Random.new()
	local list: { { part: BasePart, vel: Vector3, spin: Vector3 } } = {}
	for i = 1, n do
		local w = Instance.new("WedgePart")
		local s = r:NextNumber(S.size[1], S.size[2])
		w.Size = Vector3.new(s * 0.5, s, s * 1.4)
		w.Color = if i % 3 == 0 then Theme.white else Theme.ice
		w.Material = Enum.Material.SmoothPlastic
		w.Transparency = 0.2
		w.Anchored = true
		w.CanCollide = false
		w.CanQuery = false
		w.CanTouch = false
		w.CastShadow = false
		local a = (i + r:NextNumber(-0.3, 0.3)) * (2 * math.pi / n)
		local out = Vector3.new(math.cos(a), 0, math.sin(a))
		w.CFrame = CFrame.new(center + out * size * 0.45 + Vector3.new(0, r:NextNumber(-0.2, 0.4) * size, 0))
			* CFrame.Angles(r:NextNumber(0, 6), r:NextNumber(0, 6), 0)
		w.Parent = workspace
		local speed = r:NextNumber(S.speed[1], S.speed[2])
		table.insert(list, { part = w, vel = out * speed + Vector3.new(0, r:NextNumber(S.up[1], S.up[2]), 0),
			spin = Vector3.new(r:NextNumber(-14, 14), r:NextNumber(-14, 14), r:NextNumber(-14, 14)) })
	end
	local life = EffectsController.time(S.seconds)
	local t0 = os.clock()
	local last = t0
	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(function()
		local now = os.clock()
		local dt = math.min(0.05, now - last)
		last = now
		local u = (now - t0) / life
		for _, s in list do
			s.vel -= Vector3.new(0, S.gravity * dt, 0)
			local cf = s.part.CFrame + s.vel * dt
			local low = groundY + s.part.Size.Y * 0.3
			if cf.Position.Y < low then -- bounce on the ground, losing most of the speed
				cf = cf + Vector3.new(0, low - cf.Position.Y, 0)
				s.vel = Vector3.new(s.vel.X * 0.6, math.abs(s.vel.Y) * S.bounce, s.vel.Z * 0.6)
				s.spin *= 0.5
			end
			s.part.CFrame = cf * CFrame.Angles(s.spin.X * dt, s.spin.Y * dt, s.spin.Z * dt)
			s.part.Transparency = 0.2 + 0.8 * math.clamp((u - 0.55) / 0.45, 0, 1)
		end
		if u >= 1 then
			conn:Disconnect()
			for _, s in list do
				s.part:Destroy()
			end
		end
	end)
end

-- a snowy frost patch spreads where the cube shut and cold vapour rolls out low over the ground
function EffectsController.frostRing(groundAt: Vector3, size: number)
	local R = F.frostRing
	local patch = glow(Vector3.new(0.05, size, size), Theme.fx.frost, nil)
	patch.Shape = Enum.PartType.Cylinder
	patch.Material = Enum.Material.Snow
	patch.Transparency = 0.25
	patch.CFrame = CFrame.new(groundAt + Vector3.new(0, 0.04, 0)) * CFrame.Angles(0, 0, math.pi / 2)
	local reach = size * R.reach
	local linger = EffectsController.time(R.linger)
	TweenService:Create(patch, TweenInfo.new(EffectsController.time(R.seconds), Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
		{ Size = Vector3.new(0.05, reach * 0.8, reach * 0.8) }):Play()
	TweenService:Create(patch, TweenInfo.new(linger, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Transparency = 1 }):Play()
	-- a cloud of cold vapour rolls out low over the ground (a neon shock ring was tried first, 2026-11-17: seen
	-- edge-on it drew a hard line across the ground)
	local fog = anchor(groundAt + Vector3.new(0, 0.3, 0))
	local e = Instance.new("ParticleEmitter")
	e.Texture = Config.ray.beam.tex.smoke
	e.Color = ColorSequence.new(Theme.fx.frost, Theme.white)
	e.LightEmission = 0.2
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.15, 0.45), NumberSequenceKeypoint.new(1, 1) })
	e.Size = NumberSequence.new(size * 0.35, size * 0.9)
	e.EmissionDirection = Enum.NormalId.Top
	e.SpreadAngle = Vector2.new(88, 88) -- out sideways, hugging the ground
	e.Speed = NumberRange.new(size * 1.6, size * 2.6)
	e.Drag = 5
	e.Acceleration = Vector3.new(0, -2, 0)
	e.Lifetime = NumberRange.new(0.7, 1.1)
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-30, 30)
	e.Rate = 0
	e.Parent = fog
	e:Emit(amount(R.fog))
	task.delay(math.max(linger, 1.2), function()
		patch:Destroy()
		fog:Destroy()
	end)
end

-- a freshly shut cube is frosted white and clears from the bottom up; star glints wink on its corners.
-- Everything rides on the cube's model, so it moves with it if it flies home early.
local function frostOver(model: Model, cube: BasePart, size: number)
	local coat = Instance.new("Part")
	coat.Anchored = true
	coat.CanCollide = false
	coat.CanQuery = false
	coat.CanTouch = false
	coat.CastShadow = false
	coat.Material = Enum.Material.Snow
	coat.Color = Theme.fx.frost
	coat.Transparency = 0.05
	coat.Parent = model
	local glints: { { parts: { BasePart }, corner: Vector3, at: number } } = {}
	local r = Random.new()
	for i = 1, F.glints do
		local parts = {}
		for k = 1, 2 do -- a four-point star: two thin bars crossed
			local bar = glow(Vector3.new(0.06, 0.06, 0.06), Theme.white, nil)
			bar.Parent = model
			bar.Transparency = 1
			parts[k] = bar
		end
		local corner = Vector3.new(if r:NextNumber() < 0.5 then -1 else 1, 1, if r:NextNumber() < 0.5 then -1 else 1) * size * 0.5
		table.insert(glints, { parts = parts, corner = corner, at = (i - 1) / math.max(1, F.glints) * 0.6 })
	end
	local coatTime = EffectsController.time(F.coatSeconds)
	local glintTime = EffectsController.time(F.glintSeconds)
	local total = math.max(coatTime, coatTime * 0.6 + glintTime)
	local t0 = os.clock()
	local crackled = false
	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(function()
		if not model.Parent or not cube.Parent then
			conn:Disconnect()
			return
		end
		local e = os.clock() - t0
		-- the coat's bottom edge rises: frosty white above it, clear ice below
		local u = math.clamp(e / coatTime, 0, 1)
		local lo = -size / 2 + size * u
		local hgt = math.max(0.02, size / 2 - lo)
		coat.Size = Vector3.new(size * 1.03, hgt * 1.0 + 0.02, size * 1.03)
		coat.CFrame = cube.CFrame * CFrame.new(0, (lo + size / 2) / 2, 0)
		coat.Transparency = if u >= 1 then 1 else 0.05 + 0.4 * u
		if not crackled and u > 0.1 then
			crackled = true
			SoundController.play("ray_crackle", 1.1) -- the ice settling
		end
		-- glints: each star pops up and shrinks away on its corner, one after another
		for _, g in glints do
			local v = (e - coatTime * g.at) / glintTime
			local s = if v > 0 and v < 1 then math.sin(v * math.pi) * F.glintSize else 0
			local at = cube.CFrame * CFrame.new(g.corner) * CFrame.Angles(0, 0, if reduced() then 0 else v * 1.2)
			g.parts[1].Size = Vector3.new(0.07, math.max(0.05, s), 0.07)
			g.parts[2].Size = Vector3.new(math.max(0.05, s), 0.07, 0.07)
			for _, bar in g.parts do
				bar.CFrame = at
				bar.Transparency = if s > 0.06 then 0.05 else 1
			end
		end
		if e >= total then
			conn:Disconnect()
			coat:Destroy()
			for _, g in glints do
				for _, bar in g.parts do
					bar:Destroy()
				end
			end
		end
	end)
end

-- the plain snap at 100% (every freeze without a show)
local function snap(data: any)
	local real = EffectsController.realCube(data.uid)
	local def = PetDefs.get(data.key)
	if not def then
		return
	end
	local size = if real then real.Size.X else PetDefs.cube(def, data.sz, true) * Config.carry.scale
	if real then
		real:SetAttribute("ShowHidden", true)
	end
	local model, cube = PetVisuals.frozenCube(data.key, size)
	if not model or not cube then
		if real then
			real:SetAttribute("ShowHidden", nil)
		end
		return
	end
	local at = EffectsController.cubeAt(data, size)
	model:PivotTo(at)
	local flash = data.style == "flash"
	-- the hit-stop (Animation Rules 8): the cube appears big and white and shakes for a beat (longer for
	-- rarer pets), then snaps to size with the puff and the tink
	local rank = Config.tier(def.tier).rank
	local f = math.clamp((rank - 1) / math.max(1, Config.camera.lockKickFullRank - 1), 0, 1)
	local hold = EffectsController.time(J.hitStop.lock[1] + (J.hitStop.lock[2] - J.hitStop.lock[1]) * f)
	if data.first then
		hold *= F.firstHoldScale -- your very first freeze: a longer hit-stop (Tizzy: the first time is a wow)
	end
	cube.Size = Vector3.one * size * F.snapScale
	cube.Color = Theme.white
	cube.Transparency = 0.15
	local shake = if reduced() then 0 else J.hitShake
	local t0 = os.clock()
	while os.clock() - t0 < hold and model.Parent do
		local now = os.clock()
		model:PivotTo(at + Vector3.new(math.sin(now * 97) * shake, 0, math.cos(now * 83) * shake))
		RunService.RenderStepped:Wait()
	end
	model:PivotTo(at)
	cube.Color = Theme.ice
	cube.Transparency = 0.9
	SoundController.play("freeze") -- the crunch lands on the release, not the hit (Sound Rules 11)
	local snapTime = EffectsController.time(F.snapSeconds)
	TweenService:Create(cube, TweenInfo.new(snapTime, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = Vector3.one * size, Transparency = 0.45 }):Play()
	puff(at.Position, if flash then F.flashPuffParts else F.puffParts)
	-- the realism pass: shards burst off and bounce, frost races over the ground, the cube clears bottom-up
	local groundAt = at.Position - Vector3.new(0, size / 2, 0)
	EffectsController.shards(at.Position, size, groundAt.Y)
	EffectsController.frostRing(groundAt, size)
	frostOver(model, cube, size)
	-- the lock: one quick white glow as the ice shuts (owner 2026-11-05); a flash-freeze's is brighter
	-- and adds a light "tink"
	local g = glow(Vector3.one * size * 1.3, Theme.fx.flash, nil)
	g.Shape = Enum.PartType.Ball
	g.Transparency = if flash then (if reduced() then 0.75 else 0.35) else (if reduced() then 0.85 else 0.65)
	g.CFrame = at
	TweenService:Create(g, TweenInfo.new(snapTime * 1.5), { Transparency = 1, Size = Vector3.one * size * 1.8 }):Play()
	task.delay(snapTime * 1.5, function()
		g:Destroy()
	end)
	if flash then
		SoundController.play("tink")
	end
	if data.first then
		-- the first freeze ever: one flash, light rays and a big frosty burst round the new cube
		EffectsController.flash()
		EffectsController.rays(at.Position, Theme.ice, F.firstRays, EffectsController.time(F.firstRaySeconds))
		EffectsController.burst(at.Position, Theme.ice, F.firstBurst)
		EffectsController.burst(at.Position, Theme.white, math.floor(F.firstBurst / 2))
		SoundController.play("tink")
	end
	if typeof(data.touch) == "string" then
		EffectsController.touch(data.touch, at, size)
	end
	task.wait(snapTime + EffectsController.time(0.12 + F.settleSeconds)) -- it sits a beat so the clearing ice reads
	EffectsController.flyHome(model, real, EffectsController.time(F.flySeconds))
end

-- banking (Animation Rules 8 follow-through): each cube hops from your hands into your pen, one by
-- one, each landing a coin ding a step higher up a major scale; then the finale (bank chime, bursts,
-- the Epic-and-up pillar). The server has already banked them; this only plays it.
local function hop(model: Model, from: Vector3, to: Vector3, seconds: number, note: number)
	local T = J.tally
	local t0 = os.clock()
	while model.Parent do
		local u = math.min(1, (os.clock() - t0) / math.max(0.01, seconds))
		local pos = from:Lerp(to, u) + Vector3.new(0, math.sin(u * math.pi) * T.arc, 0)
		model:PivotTo(CFrame.new(pos) * CFrame.Angles(0, u * math.pi, 0))
		if u >= 1 then
			break
		end
		RunService.RenderStepped:Wait()
	end
	model:Destroy()
	EffectsController.burst(to - Vector3.new(0, 2, 0), Theme.ice, T.landParts)
	SoundController.play("coin", 2 ^ (note / 12))
end

local function tally(data: any)
	local v = State.view
	if not v or not v.plot or typeof(data) ~= "table" or typeof(data.banked) ~= "table" then
		return
	end
	local T = J.tally
	local at = WorldRules.plotCenter(v.plot)
	local c = Players.LocalPlayer.Character
	local root = c and c:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		local n = math.min(#data.banked, T.maxCubes)
		for k = 1, n do
			local def = PetDefs.get(data.banked[k].key)
			if def then
				local size = PetDefs.cube(def, data.banked[k].sz, true) * Config.carry.scale
				local model = PetVisuals.frozenCube(def.key, size)
				if model then
					local from = (root.CFrame * CFrame.new(0, T.startUp, -T.startFront)).Position
					model:PivotTo(CFrame.new(from))
					local note = T.notes[math.min(k, #T.notes)]
					task.spawn(hop, model, from, at + Vector3.new(0, size / 2, 0), EffectsController.time(T.fly), note)
				end
			end
			if k < n then
				task.wait(EffectsController.time(T.stagger))
			end
		end
		task.wait(EffectsController.time(T.fly + T.finale))
	end
	SoundController.play("made_it_home") -- ElevenLabs fanfare (2026-11-18), was the "bank" chime
	EffectsController.burst(at, Theme.ice)
	EffectsController.burst(at, Theme.coin)
	-- Epic and up get an extra burst in the tier's colour (owner 2026-11-13: no light pillar any more)
	for _, b in data.banked do
		local def = PetDefs.get(b.key)
		if def and Config.tier(def.tier).rank >= E.showRank then
			EffectsController.burst(at, Theme.tiers[def.tier] or Theme.coin)
		end
	end
end

local function setSnow(on: boolean)
	if on and not snow then
		local p = anchor(Vector3.zero)
		p.Size = Vector3.new(80, 1, 80)
		local e = Instance.new("ParticleEmitter")
		e.Color = ColorSequence.new(Theme.snow)
		e.Rate = amount(E.snowRate)
		e.Speed = NumberRange.new(4, 8)
		e.Lifetime = NumberRange.new(4, 6)
		e.EmissionDirection = Enum.NormalId.Bottom
		e.Parent = p
		snow = p
	elseif not on and snow then
		snow:Destroy()
		snow = nil
	end
end

function EffectsController.Init()
	local g = Instance.new("ScreenGui")
	g.Name = "Flash"
	g.IgnoreGuiInset = true
	g.ResetOnSpawn = false
	g.DisplayOrder = 20
	local f = Instance.new("Frame")
	f.Size = UDim2.fromScale(1, 1)
	f.BackgroundColor3 = Theme.fx.flash
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	f.Visible = false
	f.Parent = g
	g.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	flashFrame = f
end

function EffectsController.Start()
	meshes = ReplicatedStorage:FindFirstChild("SceneryMeshes")
	State.Notify:Connect(function(kind: string, data: any)
		if kind == "frozen" and typeof(data) == "table" and typeof(data.at) == "Vector3" then
			if not data.show then -- Legendary and up: the Show module plays it
				task.spawn(snap, data)
			end
		elseif kind == "pickedUp" and typeof(data) == "table" and typeof(data.from) == "CFrame" then
			task.spawn(pickUp, data)
		elseif kind == "banked" then
			task.spawn(tally, data)
		elseif kind == "melted" then
			local c = Players.LocalPlayer.Character
			local root = c and c:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root then
				EffectsController.burst(root.Position, Theme.ice)
			end
		elseif kind == "cubeGone" and typeof(data) == "table" and typeof(data.at) == "Vector3" then
			EffectsController.burst(data.at, Theme.ice) -- a frozen pet left on the ground for 60 s poofs away
		elseif kind == "zoneUnlocked" then
			EffectsController.burst(Vector3.new(0, 6, WorldRules.gateZ(if typeof(data.zone) == "number" then data.zone else 2) or 0), Theme.go)
		elseif kind == "giftClaimed" then
			EffectsController.burst(Config.world.giftBox, Theme.coin)
		elseif kind == "chillStart" then
			setSnow(true)
		elseif kind == "chillEnd" then
			setSnow(false)
		end
	end)
	-- snow follows the camera; it also starts for a player who joins mid-Chill
	RunService.RenderStepped:Connect(function()
		local untilAt = workspace:GetAttribute("ChillUntil")
		local chill = typeof(untilAt) == "number" and untilAt > workspace:GetServerTimeNow()
		if chill ~= (snow ~= nil) then
			setSnow(chill)
		end
		local cam = workspace.CurrentCamera
		if snow and cam then
			snow.Position = cam.CFrame.Position + Vector3.new(0, 25, 0)
		end
	end)
end

return EffectsController
