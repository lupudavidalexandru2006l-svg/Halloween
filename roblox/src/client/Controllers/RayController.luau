--!strict
-- RayController: the ice ray. Every character on this client gets its gun in its right hand while the
-- ray is in their hands (the "Held" attribute, GearService; built locally, so it costs the server
-- nothing): the one that player holds (the GunTier attribute). A gun's model comes from
-- ReplicatedStorage.GunModels.<key> once the image-to-3D guns exist; until then a part-built STAND-IN
-- (buildGun) in the gun's colours, one barrel tip per beam.
-- Round 5 (owner 2026-11-02): the ray is SHOT. Hold the mouse or a finger on a pet, a Heat Critter or a
-- player who carries a cube (a forgiving pick: the nearest target near your finger; once locked, it
-- stays locked while you hold and it's in range). E / gamepad R2 aim at the nearest target in front.
-- This client tells the server what it aims at ("Aim"); the server moves each target's freeze meter
-- and publishes it ("Meter", "FreezeStyle", "AimedBy"), so every client draws every player's beams and
-- the ice creeping up (PetVisuals reads freezeOf). An aim ring sits on the target you'd hit.
-- It also owns the arm poses: the gun arm is held out in front while the gun is in the hand, and anyone carrying cubes holds
-- both arms out in front (the cubes sit in their hands, CarryService), on every client for every character.
-- Each shot plays as three clips (Config.ray.anim, owner 2026-11-05): a quick start (hips lead, the torso
-- coils back, everything snaps forward and the beam lands at 0.10 s), a hold that leans in harder as the
-- meter climbs, and a lock when the cube shuts (or a soft cancel if you let go early). The clips also fire
-- the shot's sounds, muzzle effects and camera kicks (your own shots only for sounds and kicks).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Theme = require(ReplicatedStorage.Shared.Theme)
local PetDefs = require(ReplicatedStorage.Shared.PetDefs)
local State = require(script.Parent.State)
local InputController = require(script.Parent.InputController)
local CameraController = require(script.Parent.CameraController)
local SoundController = require(script.Parent.SoundController)
local SettingsController = require(script.Parent.SettingsController)

local RayController = {}
local R = Config.ray
local A = Config.aim
local me = Players.LocalPlayer
local guns: { [Model]: { model: Model, tier: number } } = {}
export type Freeze = {
	root: BasePart, style: string, gun: number,
	u: number, -- the server's meter (0-1)
	p: number, -- how frozen it looks (0-1, eased toward the meter)
}
type Target = { kind: string, id: string, part: BasePart }
local shakes: { [BasePart]: number } = setmetatable({}, { __mode = "k" }) :: any -- pet root -> when its "too warm" shake ends
local baseC0: { [Instance]: CFrame } = setmetatable({}, { __mode = "k" }) :: any -- each shoulder's rest pose
local looks: { [BasePart]: Freeze } = setmetatable({}, { __mode = "k" }) :: any -- each target's eased freeze look
local skip: { [BasePart]: number } = setmetatable({}, { __mode = "k" }) :: any -- targets the server said no to, until then
-- input: the pointer (mouse / one finger) held on the screen, or the auto-aim key held
local pointer: { pos: Vector2, touch: InputObject? }? = nil
local autoAim = false
local locked: Target? = nil
local sentKey = "none"
local lastSent = 0
type BeamSet = { beams: { Beam }, sparkles: { ParticleEmitter } }
local beamSets: { [string]: BeamSet } = {}
local reticle: { gui: BillboardGui, ring: Frame, fill: Frame, hint: TextLabel }? = nil

local function holdsRay(p: Player?): boolean
	local h = p and p:GetAttribute("Held")
	return h == nil or h == "ray"
end

-- the gun is in the hand while the ray or the Slow Gel is held: the gel is shot out of the gun
-- (owner 2026-11-03); only putting everything away ("none") empties the hand
local function showsGun(p: Player?): boolean
	return (p and p:GetAttribute("Held")) ~= "none"
end

local function piece(shape: Enum.PartType, size: Vector3, color: Color3, parent: Instance): Part
	local p = Instance.new("Part")
	p.Shape = shape
	p.Size = size
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = false
	p.Parent = parent
	return p
end

local function weld(a: BasePart, b: BasePart, c0: CFrame): Weld
	local w = Instance.new("Weld")
	w.Part0 = a
	w.Part1 = b
	w.C0 = c0
	w.Parent = b
	return w
end

local function gunTierOf(p: Player?): number
	local t = p and p:GetAttribute("GunTier")
	return if typeof(t) == "number" then math.clamp(math.floor(t), 1, math.min(#Theme.guns, #Config.guns.list)) else 1
end

-- one part of the stand-in gun, placed relative to its body (the body sits at the origin)
local function place(body: BasePart, p: BasePart, at: CFrame)
	p.CFrame = body.CFrame * at
	local w = Instance.new("WeldConstraint")
	w.Part0 = body
	w.Part1 = p
	w.Parent = p
end

-- gun `tier`, pointing along the body's +X (the barrel axis). The real model when
-- ReplicatedStorage.GunModels.<key> exists (a PrimaryPart called Body and RayTip attachments);
-- until then the STAND-IN: a barrel that grows each tier, one glowing tip per beam, a tank in the
-- gun's glow, fins (3+), a glowing ring (5+) and a crystal (9+). Also used by the buy show.
function RayController.buildGun(tier: number): Model
	local g = Config.gun(tier)
	local models = ReplicatedStorage:FindFirstChild("GunModels")
	local real = models and models:FindFirstChild(g.key)
	if real and real:IsA("Model") and real.PrimaryPart then
		local m = real:Clone()
		m.Name = "IceRay"
		-- painted glow comes out flat in 3D, so each barrel tip gets a small light in the gun's glow (Pet Rules 5)
		local look = Theme.guns[tier] or Theme.guns[1]
		for _, a in m:GetDescendants() do
			if a:IsA("Attachment") and a.Name:sub(1, 6) == "RayTip" then
				local l = Instance.new("PointLight")
				l.Color = look.glow
				l.Range = R.tipLightRange
				l.Brightness = R.tipLightBrightness
				l.Parent = a
			end
		end
		return m
	end
	local S = Config.guns.standIn
	local look = Theme.guns[tier] or Theme.guns[1]
	local m = Instance.new("Model")
	m.Name = "IceRay"
	local len = S.barrel + S.barrelPerGun * (tier - 1)
	local body = piece(Enum.PartType.Cylinder, Vector3.new(len, 0.74, 0.74), Theme.fx.gunBody, m)
	body.Name = "Body"
	body.CFrame = CFrame.new()
	m.PrimaryPart = body
	-- one tip per beam: one in the middle, or a ring of them round the muzzle
	for i = 1, g.beams do
		local tip = piece(Enum.PartType.Ball, Vector3.one * R.tipSize * (if g.beams > 1 then 0.7 else 1), look.glow, m)
		tip.Material = Enum.Material.Neon
		local a = if g.beams > 1 then (i - 1) / g.beams * math.pi * 2 else 0
		local r = if g.beams > 1 then S.tipRing else 0
		place(body, tip, CFrame.new(len / 2 + 0.05, math.cos(a) * r, math.sin(a) * r))
		local at = Instance.new("Attachment")
		at.Name = if i == 1 then "RayTip" else "RayTip" .. i
		at.Parent = tip
	end
	local tank = piece(Enum.PartType.Cylinder, Vector3.new(0.7, 0.6, 0.6), look.glow, m)
	tank.Transparency = 0.15
	place(body, tank, CFrame.new(-len * 0.12, 0.42, 0) * CFrame.Angles(0, 0, math.pi / 2))
	if tier >= S.finsFrom then
		for _, side in { -1, 1 } do
			local fin = piece(Enum.PartType.Block, Vector3.new(0.5, 0.08, 0.36), look.glow, m)
			place(body, fin, CFrame.new(-len * 0.25, 0, side * 0.42) * CFrame.Angles(0, 0, side * 0.3))
		end
	end
	if tier >= S.ringFrom then
		local ring = piece(Enum.PartType.Cylinder, Vector3.new(0.16, 0.9, 0.9), look.spark, m)
		ring.Material = Enum.Material.Neon
		place(body, ring, CFrame.new(len * 0.28, 0, 0))
	end
	if tier >= S.gemFrom then
		local gem = piece(Enum.PartType.Ball, Vector3.new(0.34, 0.5, 0.34), look.spark, m)
		gem.Material = Enum.Material.Neon
		place(body, gem, tank.CFrame * CFrame.new(0.42, 0, 0)) -- the body sits at the origin while it's built
	end
	return m
end

-- the held gun, pointing along the hand's forward direction
local function giveGun(character: Model)
	local p = Players:GetPlayerFromCharacter(character)
	local tier = gunTierOf(p)
	local had = guns[character]
	if not showsGun(p) then -- everything is put away (hotbar): no gun in the hand
		if had then
			had.model:Destroy()
			guns[character] = nil
		end
		return
	end
	if had and had.tier == tier then
		return
	end
	local hand = character:WaitForChild("RightHand", 5) or character:FindFirstChild("Right Arm")
	if not hand or not hand:IsA("BasePart") or not character.Parent then
		return
	end
	had = guns[character]
	if had then
		if had.tier == tier then
			return
		end
		had.model:Destroy()
		guns[character] = nil
	end
	local m = RayController.buildGun(tier)
	local body = m.PrimaryPart :: BasePart
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = false
			d.CanCollide, d.CanQuery, d.CanTouch, d.Massless = false, false, false, true
		end
	end
	-- the arm is held out in front while the gun is in it (poseArms), so the hand's -Y points forward and
	-- its -Z points up: the barrel (+X of the stand-in, and of a real model's Grip, which is turned to
	-- face its barrel) goes along -Y and the gun's top along -Z, so it points straight ahead
	-- (owner 2026-11-03: it hung down at the hip)
	local base = CFrame.new(0, -hand.Size.Y / 2, 0) * CFrame.fromMatrix(Vector3.zero, -Vector3.yAxis, -Vector3.zAxis, Vector3.xAxis)
	-- a real model is held by its Grip attachment (set at import), centred in the hand
	local grip = body:FindFirstChild("Grip")
	local c1 = CFrame.new()
	if grip and grip:IsA("Attachment") then
		c1 = grip.CFrame
	end
	m:PivotTo(hand.CFrame * base * c1:Inverse() * body.PivotOffset) -- the weld holds it there from now on
	weld(hand, body, base).C1 = c1
	m.Parent = character
	guns[character] = { model = m, tier = tier }
	character.Destroying:Once(function()
		guns[character] = nil
	end)
end

local function watchPlayer(p: Player)
	p.CharacterAdded:Connect(giveGun)
	if p.Character then
		task.spawn(giveGun, p.Character)
	end
	for _, attr in { "GunTier", "Held" } do
		p:GetAttributeChangedSignal(attr):Connect(function()
			if p.Character then
				task.spawn(giveGun, p.Character) -- a better gun, or the ray put away / taken out
			end
		end)
	end
end

-- ---------- targets ----------
local function myRoot(): BasePart?
	local c = me.Character
	return if c then c:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
end

-- everything the ray could hit right now: wild pets I can see, Heat Critters, players who can be tagged
local function candidates(): { Target }
	local out: { Target } = {}
	local wild = workspace:FindFirstChild("WildPets")
	if wild then
		for _, r in wild:GetChildren() do
			local owner = r:GetAttribute("OwnerUserId")
			if r:IsA("BasePart") and (owner == 0 or owner == me.UserId) then
				table.insert(out, { kind = "pet", id = r:GetAttribute("PetId") :: string, part = r })
			end
		end
	end
	local critters = workspace:FindFirstChild("Critters")
	if critters then
		for _, r in critters:GetChildren() do
			if r:IsA("BasePart") and r:GetAttribute("State") ~= "frozen" then
				table.insert(out, { kind = "critter", id = r:GetAttribute("CritterId") :: string, part = r })
			end
		end
	end
	for _, p in Players:GetPlayers() do
		local hrp = p ~= me and p.Character and p.Character:FindFirstChild("HumanoidRootPart")
		if hrp and hrp:IsA("BasePart") and p:GetAttribute("Taggable") == true and me:GetAttribute("Shielded") ~= true then
			table.insert(out, { kind = "player", id = tostring(p.UserId), part = hrp })
		end
	end
	return out
end

local function inReach(t: Target, from: Vector3): boolean
	local range = Config.gun(gunTierOf(me)).range
	local d = Vector3.new(t.part.Position.X - from.X, 0, t.part.Position.Z - from.Z).Magnitude
	return d <= range and (skip[t.part] or 0) < os.clock() and typeof(t.id) == "string"
end

-- the target nearest a spot on the screen (a forgiving pick for small fingers)
local function pickAt(screen: Vector2): Target?
	local cam = workspace.CurrentCamera
	local root = myRoot()
	if not cam or not root then
		return nil
	end
	local short = math.min(cam.ViewportSize.X, cam.ViewportSize.Y)
	local best, bestD = nil, A.pickRadius * short
	for _, t in candidates() do
		if inReach(t, root.Position) then
			local v, onScreen = cam:WorldToViewportPoint(t.part.Position)
			local d = (Vector2.new(v.X, v.Y) - screen).Magnitude
			if onScreen and d < bestD then
				best, bestD = t, d
			end
		end
	end
	return best
end

-- E / R2: the nearest target in front of the camera, in reach
local function pickAuto(): Target?
	local cam = workspace.CurrentCamera
	local root = myRoot()
	if not cam or not root then
		return nil
	end
	local look = cam.CFrame.LookVector * Vector3.new(1, 0, 1)
	look = if look.Magnitude > 0 then look.Unit else Vector3.zAxis
	local best, bestD = nil, math.huge
	for _, t in candidates() do
		local to = (t.part.Position - root.Position) * Vector3.new(1, 0, 1)
		if inReach(t, root.Position) and (to.Magnitude < 3 or to.Unit:Dot(look) >= A.autoAimDot) and to.Magnitude < bestD then
			best, bestD = t, to.Magnitude
		end
	end
	return best
end

local function stillValid(t: Target): boolean
	local root = myRoot()
	return t.part.Parent ~= nil and root ~= nil and inReach(t, root.Position)
		and not (t.kind == "critter" and t.part:GetAttribute("State") == "frozen")
		and not (t.kind == "player" and t.part.Parent and Players:GetPlayerFromCharacter(t.part.Parent :: Model) and (Players:GetPlayerFromCharacter(t.part.Parent :: Model) :: Player):GetAttribute("Taggable") ~= true)
end

local function send(force: boolean?)
	local key = if locked then locked.kind .. ":" .. locked.id else "none"
	if key == sentKey then
		return
	end
	if not force and os.clock() - lastSent < A.sendEvery then
		return -- sent on a later frame
	end
	sentKey, lastSent = key, os.clock()
	if locked then
		State.send("Aim", locked.kind, locked.id)
	else
		State.send("Aim", "none")
	end
end

local function aiming(): boolean
	return (pointer ~= nil or autoAim) and holdsRay(me)
end

local function updateAim()
	if not aiming() then
		locked = nil
	elseif locked and not stillValid(locked) then
		locked = nil
	end
	if aiming() and not locked then
		locked = if pointer then pickAt(pointer.pos) else pickAuto()
	end
	send(locked == nil)
end

-- ---------- beams ----------
local function beam(from: Attachment, to: Attachment, width: number, color: Color3, transparency: number): Beam
	local b = Instance.new("Beam")
	b.Attachment0 = from
	b.Attachment1 = to
	b.Width0, b.Width1 = width, width
	b.Color = ColorSequence.new(color)
	b.Transparency = NumberSequence.new(transparency)
	b.LightEmission = 1
	b.FaceCamera = true
	b.Segments = 12
	b.Parent = from
	return b
end

local function sparkle(parent: Instance, color: Color3, gun: number, speed: number): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Color = ColorSequence.new(color)
	e.LightEmission = 0.6
	e.Rate = R.sparkleRate + R.sparklePerGun * (gun - 1)
	e.Speed = NumberRange.new(speed * 0.5, speed)
	e.Lifetime = NumberRange.new(0.3, 0.5)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Size = NumberSequence.new(R.sparkleSize + R.sparkleSizePerGun * (gun - 1), 0)
	e.Parent = parent
	return e
end

local function aimAttachment(part: BasePart): Attachment
	local a = part:FindFirstChild("Aim") or part:FindFirstChild("AimLocal")
	if a and a:IsA("Attachment") then
		return a
	end
	local n = Instance.new("Attachment")
	n.Name = "AimLocal"
	n.Parent = part
	return n
end

local function makeBeams(tip: Attachment, part: BasePart, tier: number): BeamSet
	local look = Theme.guns[tier] or Theme.guns[1]
	local w = R.beamPerGun * (tier - 1)
	local target = aimAttachment(part)
	return {
		beams = { beam(tip, target, R.beamGlow + w * 2, look.glow, 0.5), beam(tip, target, R.beamCore + w, look.core, 0.05) },
		sparkles = { sparkle(target, look.spark, tier, 4), sparkle(tip, look.glow, tier, 2) },
	}
end

-- the beam pulls back rather than vanishing: the muzzle end thins first, then the target end
local function dropBeams(set: BeamSet)
	local F = R.anim.fx
	local k = if SettingsController.get("reducedMotion") == true then 0.5 else 1
	for _, b in set.beams do
		TweenService:Create(b, TweenInfo.new(F.beamOut * k, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Width0 = 0 }):Play()
		TweenService:Create(b, TweenInfo.new(F.beamIn * k, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Width1 = 0 }):Play()
		task.delay(F.beamIn * k, function()
			b:Destroy()
		end)
	end
	for _, s in set.sparkles do
		s:Destroy()
	end
end

-- ---------- the shot's clips (Config.ray.anim) ----------
local AN = R.anim
type BodyPose = { dip: number, hipYaw: number, twist: number, lean: number, arm: number }
local ZERO: BodyPose = { dip = 0, hipYaw = 0, twist = 0, lean = 0, arm = 0 }
type Shot = {
	phase: string, -- "start" | "hold" | "lock" | "cancel"
	t0: number, part: BasePart?, meter: number, side: number, -- side: +1 the target is to the right, -1 left
	from: BodyPose, fromT: number, -- the pose this phase crossfades from
	cue: number, fired: boolean, mine: boolean, hum: Sound?, kicked: boolean,
}
local shots: { [Model]: Shot } = {}
local bodyPose: { [Model]: BodyPose } = setmetatable({}, { __mode = "k" }) :: any -- this frame's pose, read by poseArms
local lastFlash = 0
local pendingLock: { scale: number, show: boolean, at: number }? = nil -- my cube shut ("frozen")

local function reduced(): boolean
	return SettingsController.get("reducedMotion") == true
end

local function timeScale(): number
	return if reduced() then 0.5 else 1
end

local function seg(x: number, a: number, b: number): number
	return if b <= a then (if x >= b then 1 else 0) else math.clamp((x - a) / (b - a), 0, 1)
end
local function quadOut(x: number): number
	return 1 - (1 - x) ^ 2
end
local function cubicOut(x: number): number
	return 1 - (1 - x) ^ 3
end
local function expoOut(x: number): number
	return if x >= 1 then 1 else 1 - 2 ^ (-10 * x)
end
local function smooth(x: number): number
	return x * x * (3 - 2 * x)
end
-- 1 at the start, swings past 0 once, then rests (Animation Rules 4: the settle)
local function settle(x: number): number
	return math.exp(-4 * x) * math.cos(math.pi * 1.5 * x)
end

local function mixPose(a: BodyPose, b: BodyPose, f: number): BodyPose
	return {
		dip = a.dip + (b.dip - a.dip) * f, hipYaw = a.hipYaw + (b.hipYaw - a.hipYaw) * f,
		twist = a.twist + (b.twist - a.twist) * f, lean = a.lean + (b.lean - a.lean) * f, arm = a.arm + (b.arm - a.arm) * f,
	}
end

local function scalePose(p: BodyPose, f: number): BodyPose
	return { dip = p.dip * f, hipYaw = p.hipYaw * f, twist = p.twist * f, lean = p.lean * f, arm = p.arm * f }
end

-- the start, t in clip seconds: hips lead, the torso coils back and the gun cocks, then the torso and
-- the arm snap forward in turn, the beam lands and the gun kicks up and settles into the brace
local function startPose(t: number, side: number): BodyPose
	local S = AN.start
	local w = quadOut(seg(t, 0, S.weightEnd))
	local c = quadOut(seg(t, S.coilFrom, S.coilEnd))
	local torso = cubicOut(seg(t, S.coilEnd + S.snapStagger, S.coilEnd + S.snapStagger + S.snapSeconds))
	local arm = cubicOut(seg(t, S.coilEnd + 2 * S.snapStagger, S.coilEnd + 2 * S.snapStagger + S.snapSeconds))
	local kick = if t < S.fireAt then 0 elseif t < S.kickEnd then expoOut(seg(t, S.fireAt, S.kickEnd)) else settle(seg(t, S.kickEnd, S.seconds))
	return {
		dip = AN.dip * w,
		hipYaw = AN.hipTurn * side * w,
		twist = -AN.coilTwist * side * c * (1 - torso),
		lean = -AN.coilBack * c * (1 - torso) + AN.braceLean * torso,
		arm = -AN.cockDip * c * (1 - arm) + AN.kickUp * kick,
	}
end

-- the hold: leans in harder as the meter climbs; near the end the gun strains a little
local function holdPose(m: number, side: number, clock: number): BodyPose
	local s = smooth(math.clamp(m, 0, 1))
	local strain = if reduced() then 0 else AN.strain.amount * smooth(seg(m, AN.strain.from, 1)) * math.sin(clock * AN.strain.hz * 2 * math.pi)
	return {
		dip = AN.dip + (AN.holdDip - AN.dip) * s,
		hipYaw = AN.hipTurn * side,
		twist = 0,
		lean = AN.braceLean + (AN.holdLean - AN.braceLean) * s,
		arm = strain,
	}
end

-- the lock: the body lets go with a soft settle while the gun rocks up and settles
local function lockPose(t: number, from: BodyPose): BodyPose
	local L = AN.lock
	local body = settle(seg(t, 0, L.seconds))
	local kick = if t < L.kickEnd then quadOut(seg(t, 0, L.kickEnd)) else settle(seg(t, L.kickEnd, L.seconds))
	local p = scalePose(from, body)
	p.arm += L.kickUp * kick
	return p
end

local function frostEmitter(tip: Attachment): ParticleEmitter
	local e = tip:FindFirstChild("ShotFrost")
	if e and e:IsA("ParticleEmitter") then
		return e
	end
	local n = Instance.new("ParticleEmitter")
	n.Name = "ShotFrost"
	n.Color = ColorSequence.new(Theme.fx.frost)
	n.LightEmission = 0.3
	n.Transparency = NumberSequence.new(0.3, 1)
	n.Size = NumberSequence.new(0.25, 0.7)
	n.Speed = NumberRange.new(1, 3)
	n.Drag = 3
	n.Acceleration = Vector3.new(0, -1.5, 0) -- cold vapour sinks
	n.Lifetime = NumberRange.new(0.35, 0.6)
	n.EmissionDirection = Enum.NormalId.Right -- the barrel points along the tip's +X
	n.SpreadAngle = Vector2.new(40, 40)
	n.Rate = 0
	n.Parent = tip
	return n
end

local function gunTip(c: Model): (Attachment?, number)
	local g = guns[c]
	local tip = g and g.model:FindFirstChild("RayTip", true)
	return if tip and tip:IsA("Attachment") then tip else nil, if g then g.tier else 1
end

-- a muzzle effect: frost wisps (mist / eject / vent) or the one quick flash when the beam lands
local function muzzle(c: Model, kind: string)
	local tip, tier = gunTip(c)
	if not tip then
		return
	end
	local F = AN.fx
	if kind == "flash" then
		local now = os.clock()
		if now - lastFlash < F.flashGap then
			return -- never more than 3 flashes a second (Animation Rules 1)
		end
		lastFlash = now
		local look = Theme.guns[tier] or Theme.guns[1]
		local b = piece(Enum.PartType.Ball, Vector3.one * F.flashSize, look.core, workspace)
		b.Anchored = true
		b.Material = Enum.Material.Neon
		b.Transparency = if reduced() then 0.6 else 0.2
		b.Position = tip.WorldPosition
		local time = F.flashSeconds * timeScale()
		TweenService:Create(b, TweenInfo.new(time), { Transparency = 1, Size = Vector3.one * F.flashSize * 1.4 }):Play()
		task.delay(time, function()
			b:Destroy()
		end)
		return
	end
	local count = (F :: any)[kind]
	if typeof(count) == "number" then
		local f = if SettingsController.get("lowGraphics") == true then 0.5 else 1
		frostEmitter(tip):Emit(math.max(1, math.floor(count * f)))
	end
end

local function playCue(c: Model, s: Shot, cue: Config.RayCue)
	if cue.sound and s.mine then
		SoundController.play(cue.sound, 0.95 + 0.1 * math.random()) -- a little variety (Sound Rules 3)
	end
	if cue.fx then
		muzzle(c, cue.fx)
	end
	if cue.kick == "fire" and s.mine then
		CameraController.kick("fire")
	end
end

-- my cube shut ("frozen", which can arrive just before or just after my beam stops): one lock kick,
-- sized by the pet's tier. Legendary and up skip it, because their show owns the camera.
local function lockKick(s: Shot)
	local lock = pendingLock
	if not lock or s.kicked then
		return
	end
	s.kicked = true
	pendingLock = nil
	if not lock.show then
		CameraController.kick("lock", lock.scale)
	end
end

local function setPhase(c: Model, s: Shot, phase: string, now: number)
	s.from = bodyPose[c] or ZERO
	s.fromT = now
	s.phase = phase
	s.t0 = now
	s.cue = 1
	s.kicked = false
	if s.hum then
		s.hum:Destroy()
		s.hum = nil
	end
end

local function sideOf(c: Model, part: BasePart): number
	local hrp = c:FindFirstChild("HumanoidRootPart")
	if not hrp or not hrp:IsA("BasePart") then
		return 1
	end
	return if (part.Position - hrp.Position):Dot(hrp.CFrame.RightVector) >= 0 then 1 else -1
end

-- who shoots this frame (character -> its first target) moves each shot through its clips
local function updateShots(shooting: { [Model]: BasePart }, now: number)
	local k = timeScale()
	local mine = me.Character
	for c, part in shooting do
		local s = shots[c]
		-- a new shot; after a lock the next one waits for the gun's kick, after a cancel it starts at once
		if not s or s.phase == "cancel" or (s.phase == "lock" and now - s.t0 >= AN.lock.kickEnd * k) then
			if not s then
				s = { phase = "start", t0 = now, part = part, meter = 0, side = 1, from = ZERO, fromT = now, cue = 1, fired = false, mine = c == mine, kicked = false }
				shots[c] = s
			end
			local sh = s :: Shot
			setPhase(c, sh, "start", now)
			sh.side = sideOf(c, part)
			sh.fired = false
		end
		local sh = s :: Shot
		sh.part = part
		local m = part:GetAttribute("Meter")
		sh.meter = if typeof(m) == "number" then m else 0
		if sh.phase == "start" and now - sh.t0 >= AN.start.seconds * k then
			sh.phase = "hold" -- the start ends on the brace pose, so no crossfade is needed
			sh.from, sh.fromT = bodyPose[c] or ZERO, now
			if sh.mine then
				sh.hum = SoundController.loop("ray_hum")
			end
		end
	end
	local lock = pendingLock
	if lock and now - lock.at > 0.5 then
		pendingLock = nil -- nothing of mine was shooting when it arrived
		lock = nil
	end
	for c, s in shots do
		local live = s.phase == "start" or s.phase == "hold"
		-- my cube shut: only a shot that began before it shut can be the one that froze it
		local myLock = s.mine and lock ~= nil and (s.phase == "lock" or s.t0 <= (lock :: any).at)
		if live and (myLock or not shooting[c]) then
			local p = s.part
			local locked = myLock or s.meter >= AN.lockFromMeter or not (p and p.Parent)
			setPhase(c, s, if locked then "lock" else "cancel", now)
		end
		if myLock and s.phase == "lock" then
			lockKick(s)
		end
		if s.phase == "lock" and now - s.t0 >= AN.lock.seconds * k and not shooting[c] then
			shots[c] = nil
		elseif s.phase == "cancel" and now - s.t0 >= AN.cancel.seconds * k and not shooting[c] then
			shots[c] = nil
		end
		if c.Parent == nil then
			if s.hum then
				s.hum:Destroy()
			end
			shots[c] = nil
		end
	end
	-- cues and poses
	local myPush = 0
	for c, s in shots do
		local t = (now - s.t0) / k -- clip seconds
		local cues: { Config.RayCue }? = nil
		local length = 1
		local pose: BodyPose
		if s.phase == "start" then
			cues, length = AN.startCues, AN.start.seconds
			s.fired = t >= AN.start.fireAt
			pose = startPose(t, s.side)
		elseif s.phase == "hold" then
			s.fired = true
			pose = holdPose(s.meter, s.side, now)
			if s.hum then
				s.hum.PlaybackSpeed = AN.humPitch[1] + (AN.humPitch[2] - AN.humPitch[1]) * s.meter
			end
		elseif s.phase == "lock" then
			cues, length = AN.lockCues, AN.lock.seconds
			pose = lockPose(t, s.from)
		else
			cues, length = AN.cancelCues, AN.cancel.seconds
			pose = scalePose(s.from, settle(seg(t, 0, AN.cancel.seconds)))
		end
		if cues then
			local n = t / length
			while cues[s.cue] and cues[s.cue].at <= n do
				playCue(c, s, cues[s.cue])
				s.cue += 1
			end
		end
		-- each change of phase crossfades from the pose it was in
		local f = smooth(seg(now - s.fromT, 0, AN.blendSeconds * k))
		bodyPose[c] = if f < 1 then mixPose(s.from, pose, f) else pose
		if s.mine and (s.phase == "start" or s.phase == "hold") then
			myPush = smooth(math.clamp(s.meter, 0, 1))
		end
	end
	for c in bodyPose do
		if not shots[c] then
			bodyPose[c] = nil
		end
	end
	CameraController.setPush(myPush)
end

-- has this character's shot reached the frame the beam lands?
local function hasFired(c: Model?): boolean
	local s = c and shots[c]
	return s ~= nil and (s.phase == "hold" or (s.phase == "start" and s.fired))
end

-- who shoots what this frame: my own lock (drawn at once) plus every target the server says a player aims at
-- every target part gets its own number for the beam keys: wild pet roots all share one name, so a key
-- built from the name let one pet's beam overwrite another's
local partIds: { [BasePart]: number } = setmetatable({}, { __mode = "k" }) :: any
local nextPartId = 0
local function partKey(part: BasePart): number
	local id = partIds[part]
	if not id then
		nextPartId += 1
		id = nextPartId
		partIds[part] = id
	end
	return id
end

local function drawBeams()
	local want: { [string]: { player: Player, part: BasePart, n: number } } = {}
	local count: { [Player]: number } = {}
	local function add(p: Player, part: BasePart)
		local key = p.UserId .. ">" .. partKey(part)
		if want[key] then
			return
		end
		local n = (count[p] or 0) + 1
		count[p] = n
		want[key] = { player = p, part = part, n = n }
	end
	if locked and aiming() then
		add(me, locked.part)
	end
	local byId: { [number]: Player } = {}
	for _, p in Players:GetPlayers() do
		byId[p.UserId] = p
	end
	local function scan(folder: Instance?)
		if not folder then
			return
		end
		for _, r in folder:GetChildren() do
			local by = r:GetAttribute("AimedBy")
			local p = typeof(by) == "number" and by ~= 0 and byId[by]
			if p and r:IsA("BasePart") and (p ~= me or not locked or locked.part ~= r) and ((r:GetAttribute("Meter") or 0) :: number) > 0 then
				add(p, r)
			end
		end
	end
	scan(workspace:FindFirstChild("WildPets"))
	scan(workspace:FindFirstChild("Critters"))
	for _, p in Players:GetPlayers() do
		local hrp = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
		local by = hrp and hrp:GetAttribute("AimedBy")
		local shooter = typeof(by) == "number" and by ~= 0 and byId[by]
		if shooter and hrp:IsA("BasePart") and (shooter ~= me or not locked or locked.part ~= hrp) then
			add(shooter, hrp)
		end
	end
	-- each shooter's shot moves through its clips (start, hold, lock / cancel)
	local shooting: { [Model]: BasePart } = {}
	for _, w in want do
		local c = w.player.Character
		if c and w.n == 1 and guns[c] then
			shooting[c] = w.part
		end
	end
	updateShots(shooting, os.clock())
	for key, set in beamSets do
		local w = want[key]
		if not w or not hasFired(w.player.Character) then
			dropBeams(set)
			beamSets[key] = nil
		end
	end
	for key, w in want do
		if beamSets[key] or not hasFired(w.player.Character) then
			continue -- the beam lands on the start's fire frame
		end
		local gun = w.player.Character and guns[w.player.Character]
		if gun then
			local tip = gun.model:FindFirstChild("RayTip" .. w.n, true) or gun.model:FindFirstChild("RayTip", true)
			if tip and tip:IsA("Attachment") then
				beamSets[key] = makeBeams(tip, w.part, gun.tier)
			end
		end
	end
	-- higher guns: the beam curls a little as it pushes the cold in
	local c = math.sin(os.clock() * 9) * R.curlAmount
	for key, set in beamSets do
		local w = want[key]
		if w and gunTierOf(w.player) >= R.curlFromGun then
			for _, b in set.beams do
				b.CurveSize0, b.CurveSize1 = c, -c
			end
		end
	end
end

-- ---------- the aim ring ----------
local function hintText(): string
	local d = InputController.device()
	return if d == "touch" then "HOLD" elseif d == "gamepad" then "HOLD R2" else "HOLD CLICK"
end

local function makeReticle(): { gui: BillboardGui, ring: Frame, fill: Frame, hint: TextLabel }
	local gui = Instance.new("BillboardGui")
	gui.Name = "AimRing"
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.ResetOnSpawn = false
	local ring = Instance.new("Frame")
	ring.Name = "Ring"
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromScale(0.5, 0.42)
	ring.Size = UDim2.fromScale(0.62, 0.62)
	ring.BackgroundTransparency = 1
	local rc = Instance.new("UICorner")
	rc.CornerRadius = UDim.new(0.5, 0)
	rc.Parent = ring
	local st = Instance.new("UIStroke")
	st.Thickness = 4
	st.Color = Theme.round5.reticle
	st.Parent = ring
	ring.Parent = gui
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.AnchorPoint = Vector2.new(0.5, 0.5)
	fill.Position = UDim2.fromScale(0.5, 0.5)
	fill.Size = UDim2.fromScale(0, 0)
	fill.BackgroundColor3 = Theme.round5.reticleFull
	fill.BackgroundTransparency = 0.45
	local fc = Instance.new("UICorner")
	fc.CornerRadius = UDim.new(0.5, 0)
	fc.Parent = fill
	fill.Parent = ring
	local hint = Instance.new("TextLabel")
	hint.Name = "Hint"
	hint.BackgroundTransparency = 1
	hint.AnchorPoint = Vector2.new(0.5, 0)
	hint.Position = UDim2.fromScale(0.5, 0.76)
	hint.Size = UDim2.fromScale(1.6, 0.24)
	hint.Font = Theme.font
	hint.TextScaled = true
	hint.TextColor3 = Theme.white
	local hs = Instance.new("UIStroke")
	hs.Thickness = 2
	hs.Color = Theme.ink
	hs.Parent = hint
	hint.Parent = gui
	gui.Parent = me:WaitForChild("PlayerGui")
	return { gui = gui, ring = ring, fill = fill, hint = hint }
end

local function drawReticle()
	local cam = workspace.CurrentCamera
	local t = if aiming() then locked else nil
	if not t and holdsRay(me) and not aiming() then
		t = pickAuto() -- the target you'd hit: the ring shows it before you shoot
	end
	if not reticle then
		reticle = makeReticle()
	end
	local r = reticle :: { gui: BillboardGui, ring: Frame, fill: Frame, hint: TextLabel }
	if not t or not cam then
		r.gui.Enabled = false
		r.gui.Adornee = nil
		return
	end
	local short = math.min(cam.ViewportSize.X, cam.ViewportSize.Y)
	local px = A.reticle * short
	r.gui.Size = UDim2.fromOffset(px, px * 1.35)
	r.gui.Adornee = t.part
	r.gui.Enabled = true
	local meter = (t.part:GetAttribute("Meter") or 0) :: number
	local pulse = if aiming() then 1 else 1 + 0.08 * math.sin(os.clock() * 5)
	r.ring.Size = UDim2.fromScale(0.62 * pulse, 0.62 * pulse * (1 / 1.35))
	r.fill.Size = UDim2.fromScale(meter, meter)
	local stroke = r.ring:FindFirstChildOfClass("UIStroke") :: UIStroke
	stroke.Color = if t.kind == "player" then Theme.round5.reticlePlayer elseif t.kind == "critter" then Theme.round5.critter else Theme.round5.reticle
	-- teach by showing: a two-word hint until you've frozen a few pets
	local v = State.view
	r.hint.Visible = not aiming() and v ~= nil and v.stats.frozen < 5
	r.hint.Text = hintText()
end

-- ---------- what other controllers read ----------
-- how frozen this target looks (nil when it has no ice): every player's freeze, from the server's meter
function RayController.freezeOf(root: BasePart): Freeze?
	local m = root:GetAttribute("Meter")
	local f = looks[root]
	if typeof(m) ~= "number" or m <= 0 then
		if f and f.p > 0.01 then
			f.u = 0
			return f -- eases back down
		end
		looks[root] = nil
		return nil
	end
	if not f then
		f = { root = root, style = "normal", gun = 1, u = 0, p = 0 }
		looks[root] = f
	end
	local ff = f :: Freeze
	ff.u = m
	local style = root:GetAttribute("FreezeStyle")
	ff.style = if typeof(style) == "string" then style else "normal"
	return ff
end

-- the target I'm shooting right now (nil when none)
function RayController.current(): Freeze?
	return if locked and aiming() then RayController.freezeOf(locked.part) else nil
end

-- the "too warm for your gun" shake: a small side wiggle (radians) while it lasts, 0 otherwise
function RayController.shakeOf(root: BasePart, reduced: boolean): number
	local untilT = shakes[root]
	local left = if untilT then untilT - os.clock() else 0
	if left <= 0 then
		return 0
	end
	local S = Config.guns.tooWarmShake
	return math.sin(os.clock() * S.speed) * S.amp * (left / S.seconds) * (if reduced then 0.5 else 1)
end

local function petRoot(id: any): BasePart?
	local wild = workspace:FindFirstChild("WildPets")
	if typeof(id) ~= "string" or not wild then
		return nil
	end
	for _, r in wild:GetChildren() do
		if r:IsA("BasePart") and r:GetAttribute("PetId") == id then
			return r
		end
	end
	return nil
end

local function update(dt: number)
	updateAim()
	drawBeams()
	drawReticle()
	-- every look eases toward its meter (the server sends it in steps)
	for root, f in looks do
		f.p += (f.u - f.p) * math.min(1, dt * 10)
	end
end

-- arm poses, every physics step: the right arm points the gun forward while the gun is in the hand,
-- and both arms hold the cubes out in front while someone carries. Classic rigs use a Motor6D (we turn
-- its C0; the Animator only moves Transform). Newer avatars use an AnimationConstraint, which only
-- follows its Transform, so we overwrite that after the Animator (only while posing). Both turn round
-- the torso's own side axis, so the arm swings forward whatever angle the joint is set at.
-- A posed arm is held still (owner 2026-11-03: walking with a cube looked strange): the walk
-- animation's swing is cleared from its shoulder, elbow and wrist, so the hands stay on the cube and
-- the gun stays level; the cubes are welded to the torso, so they bob and lean with the body.
-- the shot's hips and torso: an offset put on top of whatever the Animator set this step. A joint the
-- Animator didn't touch still holds last step's offset, so it's taken off first (never adds up).
-- Both joint kinds (Code Rules: Motor6D and AnimationConstraint); offsets are in the upper part's
-- parent space (y up, -z forward), turned into the joint's own frame.
local jointBase: { [Instance]: { base: CFrame, wrote: CFrame } } = setmetatable({}, { __mode = "k" }) :: any
local posedBody: { [Model]: boolean } = setmetatable({}, { __mode = "k" }) :: any

local function offsetJoint(j: Instance?, off: CFrame)
	if not j or not (j:IsA("Motor6D") or j:IsA("AnimationConstraint")) then
		return
	end
	local rot = CFrame.identity
	if j:IsA("Motor6D") then
		rot = j.C0.Rotation
	elseif j:IsA("AnimationConstraint") and j.Attachment0 then
		rot = j.Attachment0.CFrame.Rotation
	end
	local cur: CFrame = (j :: any).Transform
	local rec = jointBase[j]
	local base = if rec and cur == rec.wrote then rec.base else cur
	local out = (rot:Inverse() * off * rot) * base
	;(j :: any).Transform = out
	jointBase[j] = { base = base, wrote = out }
end

-- the hips turn the whole body (feet stay planted, they only turn); the dip sinks the upper body at the
-- waist, so the feet never sink into the ground
local function poseBody(character: Model, pose: BodyPose?)
	if not pose and not posedBody[character] then
		return
	end
	local p = pose or ZERO
	local waist = character:FindFirstChild("Waist", true)
	local root = character:FindFirstChild("Root", true) or character:FindFirstChild("RootJoint", true)
	local hips = CFrame.Angles(0, -math.rad(p.hipYaw), 0)
	local torso = CFrame.Angles(0, -math.rad(p.twist), 0) * CFrame.Angles(-math.rad(p.lean), 0, 0)
	if waist then
		offsetJoint(root, hips)
		offsetJoint(waist, CFrame.new(0, -p.dip, 0) * torso)
	else
		offsetJoint(root, hips * torso) -- classic R6: one joint for the whole body, so no dip
	end
	if not pose then -- back at rest: forget the offsets
		posedBody[character] = nil
		for _, j in { root, waist } do
			if j then
				jointBase[j] = nil
			end
		end
	else
		posedBody[character] = true
	end
end

local function poseArms()
	local carriers: { [number]: boolean } = {}
	local cubes = workspace:FindFirstChild("Cubes")
	if cubes then
		for _, c in cubes:GetChildren() do
			local owner = c:GetAttribute("OwnerUserId")
			if typeof(owner) == "number" then
				carriers[owner] = true
			end
		end
	end
	for _, p in Players:GetPlayers() do
		local character = p.Character
		if not character then
			continue
		end
		local carrying = carriers[p.UserId] == true
		local holding = guns[character] ~= nil -- the gun arm stays up while the gun is in the hand, not only while shooting
		-- the shot's body motion plays on while you carry (the cube lands in your hands as the lock starts);
		-- only the gun arm's part of it gives way to the carry pose
		local pose = bodyPose[character]
		poseBody(character, pose)
		for _, side in { "Right", "Left" } do
			local joint = character:FindFirstChild(side .. "Shoulder", true)
			local shot = if pose then pose.arm else 0
			local angle = if carrying then Config.carry.armRaise elseif side == "Right" and holding then R.armRaise + shot else 0
			local turn = CFrame.Angles(math.rad(angle), 0, 0)
			if joint and joint:IsA("Motor6D") then
				local base = baseC0[joint]
				if not base then
					base = joint.C0
					baseC0[joint] = base
				end
				local b = base :: CFrame
				joint.C0 = CFrame.new(b.Position) * turn * b.Rotation
			elseif joint and joint:IsA("AnimationConstraint") and angle ~= 0 and joint.Attachment0 then
				local r = joint.Attachment0.CFrame.Rotation
				joint.Transform = r:Inverse() * turn * r
			end
			if angle ~= 0 then
				if joint and joint:IsA("Motor6D") then
					joint.Transform = CFrame.identity
				end
				for _, part in { "Elbow", "Wrist" } do
					local j = character:FindFirstChild(side .. part, true)
					if j and (j:IsA("Motor6D") or j:IsA("AnimationConstraint")) then
						j.Transform = CFrame.identity
					end
				end
			end
		end
	end
end

local function isAimKey(k: Enum.KeyCode): boolean
	return table.find(A.keys, k) ~= nil
end

function RayController.Init() end

function RayController.Start()
	for _, p in Players:GetPlayers() do
		watchPlayer(p)
	end
	Players.PlayerAdded:Connect(watchPlayer)
	RunService.Stepped:Connect(poseArms) -- after the Animator, before physics
	RunService.RenderStepped:Connect(update)
	-- shooting: hold the mouse or a finger on a target; E / R2 aim at the nearest one in front
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed or UserInputService:GetFocusedTextBox() then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			pointer = { pos = Vector2.new(input.Position.X, input.Position.Y), touch = nil }
		elseif input.UserInputType == Enum.UserInputType.Touch and not pointer then
			pointer = { pos = Vector2.new(input.Position.X, input.Position.Y), touch = input }
		elseif isAimKey(input.KeyCode) then
			autoAim = true
		end
	end)
	UserInputService.InputChanged:Connect(function(input: InputObject)
		local pt = pointer
		if not pt then
			return
		end
		if (input.UserInputType == Enum.UserInputType.MouseMovement and not pt.touch) or input == pt.touch then
			pt.pos = Vector2.new(input.Position.X, input.Position.Y)
		end
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		local pt = pointer
		if pt and ((input.UserInputType == Enum.UserInputType.MouseButton1 and not pt.touch) or input == pt.touch) then
			pointer = nil
		elseif isAimKey(input.KeyCode) then
			autoAim = false
		end
	end)
	State.Notify:Connect(function(kind: string, data: any)
		if kind == "frozen" then
			locked = nil -- the cube shut: hold on to pick the next one
			-- my shot plays its lock; the camera kick grows with the pet's tier (Common x0.6 up to Epic x1)
			local C = Config.camera
			local def = if typeof(data) == "table" and typeof(data.key) == "string" then PetDefs.get(data.key) else nil
			local rank = if def then Config.tier(def.tier).rank else 1
			local f = math.clamp((rank - 1) / math.max(1, C.lockKickFullRank - 1), 0, 1)
			pendingLock = {
				scale = C.lockKickScale[1] + (C.lockKickScale[2] - C.lockKickScale[1]) * f,
				show = typeof(data) == "table" and data.show ~= nil,
				at = os.clock(),
			}
		elseif kind == "tagged" and typeof(data) == "table" then
			-- ray-tag: this client owns its character's physics, so it lies the Humanoid down (the server
			-- loosened the joints) and gets up again when the tumble ends
			locked = nil
			local c = me.Character
			local hum = c and c:FindFirstChildOfClass("Humanoid")
			local hrp = c and c:FindFirstChild("HumanoidRootPart")
			if hum and hrp and hrp:IsA("BasePart") then
				hum:ChangeState(Enum.HumanoidStateType.Physics)
				hrp:ApplyImpulse((hrp.CFrame.LookVector * -6 + Vector3.new(0, 10, 0)) * hrp.AssemblyMass)
				task.delay(if typeof(data.seconds) == "number" then data.seconds else Config.tag.ragdollSeconds, function()
					if hum.Parent then
						hum:ChangeState(Enum.HumanoidStateType.GettingUp)
					end
				end)
			end
		elseif kind == "tooWarm" and typeof(data) == "table" then
			-- this gun can't freeze that island's pets: no beam, the pet shakes a little
			local root = petRoot(data.id)
			if root then
				shakes[root] = os.clock() + Config.guns.tooWarmShake.seconds
				skip[root] = os.clock() + 1.5
				if locked and locked.part == root then
					locked = nil
				end
			end
		end
	end)
end

return RayController
