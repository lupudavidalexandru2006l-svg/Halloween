--!strict
-- PetVisuals: draws the pets on the server's invisible PetRoot parts, inside carried cubes and inside
-- the ice cubes banked on the pans (with a tiny wiggle, frost shimmer and rising coins).
-- A model from ReplicatedStorage.PetModels when it's uploaded, else a stand-in in the pet's colour
-- with its name. The action (yawn, jump, dance, sneeze, sleep) plays from the root's Action attribute as
-- a short procedural animation, at half speed while held; pets walk while they wander; dazed pets wobble. Other players' personal rares are hidden: no model and the
-- prompt turned off on this client (the server refuses them anyway). Also draws the Super Freeze
-- button next to your own melted Rare+ pet: small, in the world, no countdown.
-- Mutations (Golden, Starry) tint the whole pet and add sparkles; sleeping pets (night, or frozen
-- asleep in a pen) lie down, breathe slowly and float little z's.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Theme = require(ReplicatedStorage.Shared.Theme)
local PetDefs = require(ReplicatedStorage.Shared.PetDefs)
local PetEyes = require(ReplicatedStorage.Shared.PetEyes)
local Ui = require(script.Parent.Parent.Lib.Ui)
local State = require(script.Parent.State)
local InputController = require(script.Parent.InputController)
local SettingsController = require(script.Parent.SettingsController)
local CameraController = require(script.Parent.CameraController)
local RayController = require(script.Parent.RayController)
local SoundController = require(script.Parent.SoundController)
local CoinPops = require(script.Parent.CoinPops)
local WorldRules = require(ReplicatedStorage.Shared.WorldRules)
local TweenService = game:GetService("TweenService")

local PetVisuals = {}
local me = Players.LocalPlayer
type Fx = { core: Part, ring: BasePart?, shadow: BasePart, stars: { BasePart } }
type Pose = { x: number, y: number, z: number, pitch: number, yaw: number, roll: number, sx: number, sy: number }
type Gait = { stride: number, hop: number, pitch: number, roll: number, yaw: number, squash: number, lean: number, bob: number, bobHz: number }
type Anim = { key: string, start: any, t: number, clock: number, from: Pose?, blend: number, blendLen: number, last: Pose, base: CFrame,
	walk: number, phase: number, gait: Gait, parts: { { part: BasePart, size: Vector3, rel: CFrame, hip: Vector3?, swing: number, front: boolean,
	role: string, pivot: Vector3?, side: number, hang: boolean, liftedOnly: boolean } }, sneezed: boolean, culled: boolean,
	seed: number, scratchy: boolean, hasArms: boolean, headPivot: Vector3?, -- seed: from the pet's id (the scratch pick); scratchy: it has back legs or arms
	lids: { BasePart }, shut: boolean, awake: number } -- lids: closed eyelids (shown while shut); awake: 1 awake, 0 asleep (head, ears and tail fade still)
type Banked = { edges: SelectionBox, coin: BillboardGui, coinImg: ImageLabel, phase: number, ready: BillboardGui? } -- ready: the READY! sign over a finished thaw
type Fleck = { part: BasePart, round: number, angle: number, y: number, reach: number }
type FreezeLook = { bands: { { part: BasePart, jitter: number, turn: number } }, highlight: Highlight?, crystals: { BasePart }, cracks: { { part: BasePart, face: number, u: number, v: number, turn: number } }, nextChip: number, style: string, cracked: number,
	rim: { BasePart }, flecks: { Fleck }, mist: BasePart?, mistFx: ParticleEmitter?, -- the ice front (owner 2026-11-05)
	-- realism pass (2026-11-17): frost on the ground (patch + fingers), frost feathers on the faces, glints
	patch: BasePart?, fingers: { { part: BasePart, angle: number, len: number } },
	ferns: { { parts: { BasePart }, face: number, u: number, v: number, tilt: number } }, glintBox: BasePart?, glintFx: ParticleEmitter? }
type Drawn = { model: PVInstance, height: number, offer: BillboardGui?, img: ImageLabel?, born: number, fx: Fx, banked: Banked?,
	clock: number, freeze: FreezeLook?, zzz: BillboardGui, anim: Anim, box: Folder?, shown: boolean? } -- box: a wild pet's own folder (hidden off your island) -- clock: the pet's own animation time (it slows while held and freezing)
-- onGround: frozen, waiting for E. ice / line / drips: the drawn ice that melts from the top down
-- (Config.petFx.melt); shown = its drawn height share; lastFrac / meltAt: when LifeFrac last went down
type CubeLook = { model: PVInstance, edges: SelectionBox, cracks: { { part: BasePart, offset: CFrame } }, onGround: boolean,
	ice: BasePart, line: BasePart, drips: ParticleEmitter, shown: number, lastFrac: number, meltAt: number,
	bubbles: { { part: BasePart, offset: CFrame } }, -- frozen air bubbles near the walls (they go as the ice melts past them)
	detail: { { part: BasePart, offset: CFrame, top: boolean, alpha: number } } } -- cubeDetail: base, corners, fractures, streaks, rime
local drawn: { [BasePart]: Drawn } = {}
local cubes: { [BasePart]: CubeLook } = {}
local folder: Folder
local P = Config.petFx
local A = Config.petAnim
local puffPart: BasePart? = nil
local PC = Config.panCubes
local meshes: Instance? = nil
local FZ = Config.show.freeze
local clearFreeze: (d: Drawn) -> ()
-- Round 5: a thawed pan pet strolls round its pan, drawn on this client only (its root stays put on the server)
local strolls: { [BasePart]: { pos: Vector3, to: Vector3?, pauseUntil: number } } = setmetatable({}, { __mode = "k" }) :: any

local function fxPart(size: Vector3, color: Color3, parent: Instance, mesh: string?): BasePart
	local template = mesh and meshes and meshes:FindFirstChild(mesh)
	local p: BasePart = if template and template:IsA("MeshPart") then template:Clone() else Instance.new("Part")
	p.Size = size
	p.Color = color
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Parent = parent
	return p
end

local function sparkles(parent: Instance, color: Color3, rate: number): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Color = ColorSequence.new(color)
	e.LightEmission = 0.8
	e.Rate = rate
	e.Speed = NumberRange.new(0.5, 1.5)
	e.Lifetime = NumberRange.new(0.5, 0.9)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Size = NumberSequence.new(0.25, 0)
	e.Parent = parent
	return e
end

local function lidPart(parent: Instance, size: Vector3, cf: CFrame, color: Color3, role: any, shut: boolean)
	local p = Instance.new("Part")
	p.Name = "Lid"
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.LocalTransparencyModifier = if shut then 0 else 1
	local mesh = Instance.new("SpecialMesh") -- an ellipsoid that follows the part's size (it squashes with the pet)
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	p:SetAttribute("Lid", true)
	if typeof(role) == "string" then
		p:SetAttribute("Role", role) -- on the head: the lids turn with it
	end
	p.Parent = parent
end

-- closed eyelids for a 3D pet (spots in Shared.PetEyes): a soft lid in the fur colour over each painted
-- eye, with a dark U-shaped curve across it. Hidden unless shut (the pet is asleep).
local function addLids(def: PetDefs.PetDef, model: Model, size: number, shut: boolean)
	local spec = PetEyes[def.model]
	local anchor = spec and model:FindFirstChild(spec.part, true)
	if not spec or not anchor then
		return
	end
	local L = A.lids
	local role = anchor:GetAttribute("Role")
	local piv = model:GetPivot()
	for _, e in spec.eyes do
		local r = e.r * size
		local n = piv:VectorToWorldSpace((e.normal + Vector3.new(0, 0, -L.faceBlend)).Unit)
		local at = piv:PointToWorldSpace(e.at * size) - n * (L.sink * r)
		local frame = CFrame.lookAt(at, at + n) -- looks out of the face: the lid's front is its -Z side
		local a, b, c = L.width * r, L.height * r, L.depth * r -- half sizes
		lidPart(model, Vector3.new(2 * a, 2 * b, 2 * c), frame, spec.lid, role, shut)
		-- the curve: points across the lid's front, low in the middle, joined by overlapping little ellipsoids
		local pts = {}
		for i = 0, L.lashSegments do
			local t = i / L.lashSegments * 2 - 1
			local x = t * a * L.lashWidth
			local y = b * L.lashDip * (t * t - 0.6)
			local z = c * math.sqrt(math.max(0, 1 - (x / a) ^ 2 - (y / b) ^ 2))
			table.insert(pts, frame:PointToWorldSpace(Vector3.new(x, y, -z)))
		end
		local thick = L.lash * r
		for i = 1, #pts - 1 do
			local p0, p1 = pts[i], pts[i + 1]
			local mid = (p0 + p1) / 2 + n * thick * 0.15
			lidPart(model, Vector3.new(thick, thick * 0.6, (p1 - p0).Magnitude + thick), CFrame.lookAt(mid, p1, n),
				Theme.fx.sleepLash, role, shut)
		end
	end
end

-- shut: draw it with its eyes closed from the start (a pet frozen asleep in a carried cube)
local function standIn(def: PetDefs.PetDef, size: number, shut: boolean?): (PVInstance, ImageLabel?)
	local models = ReplicatedStorage:FindFirstChild("PetModels")
	local m = models and models:FindFirstChild(def.model)
	if m and m:IsA("Model") then
		local clone = m:Clone()
		clone:ScaleTo(size / math.max(0.1, clone:GetExtentsSize().Y))
		for _, d in clone:GetDescendants() do
			if d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide = false
				d.CanQuery = false
				if table.find(def.glowParts, d.Name) then
					d.Material = Enum.Material.Neon
				end
			end
		end
		addLids(def, clone, size, shut == true)
		return clone
	end
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	if def.icon ~= "" then
		-- the painted sprite, always facing the camera (prototype): an invisible anchor carries it
		p.Size = Vector3.one * size
		p.Transparency = 1
		local g = Instance.new("BillboardGui")
		g.Name = "Sprite"
		g.Size = UDim2.fromScale(size * Config.ui.petSpriteScale, size * Config.ui.petSpriteScale)
		g.LightInfluence = 0
		g.Adornee = p
		g.Parent = p
		local img = Instance.new("ImageLabel")
		img.BackgroundTransparency = 1
		img.AnchorPoint = Vector2.new(0.5, 1) -- squash and stretch from the feet (prototype poses)
		img.Position = UDim2.fromScale(0.5, 1)
		img.Size = UDim2.fromScale(1, 1)
		img.Image = def.icon
		img.Parent = g
		return p, img
	end
	p.Shape = Enum.PartType.Ball
	p.Size = Vector3.new(size, size, size)
	p.Color = def.color
	p.Material = Enum.Material.SmoothPlastic
	return p, nil
end

-- Golden / Starry: sprites are tinted, 3D models get a coloured Highlight; both sparkle
local function mutationLook(model: PVInstance, img: ImageLabel?, sparkleAt: Instance, mut: any)
	local look = if typeof(mut) == "string" then Theme.mut[mut] else nil
	if not look then
		return
	end
	if img then
		img.ImageColor3 = Theme.white:Lerp(look.tint, 1 - look.fill)
	else
		local h = Instance.new("Highlight")
		h.FillColor = look.tint
		h.FillTransparency = look.fill
		h.OutlineColor = look.sparkle
		h.OutlineTransparency = P.mutOutline
		h.DepthMode = Enum.HighlightDepthMode.Occluded
		h.Parent = model
	end
	local e = sparkles(sparkleAt, look.sparkle, P.mutSparkleRate)
	e.Size = NumberSequence.new(P.mutSparkleSize[mut] or 0.25, 0)
end

-- three little z's that drift up over a sleeping pet (letters, not an emoji)
local function zzzGui(parent: BasePart, height: number): BillboardGui
	local g = Instance.new("BillboardGui")
	g.Name = "Zzz"
	g.Size = UDim2.fromScale(3, 3)
	-- above and right of the name pill, so the z's never write over the name
	g.StudsOffset = Vector3.new(height * 0.5 + 0.6, height / 2 + Config.worldText.tag.offset + 1.6, 0)
	g.MaxDistance = 60
	g.Enabled = false
	for i = 1, 3 do
		local t = Ui.label(g, if i == 3 then "Z" else "z")
		t.Name = "Z" .. i
		t.Size = UDim2.fromScale(0.45, 0.45)
		t.AnchorPoint = Vector2.new(0.5, 0.5)
		t.TextColor3 = Theme.fx.zzz
	end
	g.Parent = parent
	return g
end

-- the name as a pill in the tier's colour (a Golden or Starry pet wears its mutation colour and name),
-- only up close so a crowd of pets doesn't stack labels on top of each other
-- "Huge Golden Snowbun": the size word, the mutation, the name; the pill takes the mutation's tint, else the
-- size's colour (Theme.sizes), else the tier's
local function nameTag(parent: Instance, def: PetDefs.PetDef, height: number, mut: any, sz: any)
	local look = if typeof(mut) == "string" then Theme.mut[mut] else nil
	local big = if Config.size(sz) then sz :: string else nil
	local T = Config.worldText.tag
	local text = (if big then big .. " " else "") .. (if look then `{mut} ` else "") .. def.name
	local color = if look then look.tint elseif big then Theme.sizes[big] else (Theme.tiers[def.tier] or Theme.info)
	local g = Ui.pill(text, color, T)
	g.Name = "NameTag"
	g.StudsOffset = Vector3.new(0, height / 2 + T.offset, 0)
	g.Parent = parent
end

local function offerButton(root: BasePart): BillboardGui
	local g = Instance.new("BillboardGui")
	g.Name = "SuperFreeze"
	g.Size = UDim2.fromScale(5, 1.4)
	-- beside the dazed pet and pulled toward the camera (Z), not AlwaysOnTop: in this place an AlwaysOnTop
	-- BillboardGui never draws (Lessons 2026-11-12). Sibling so the block's face dressing sits on its face
	g.StudsOffset = Vector3.new(3.5, 1, 2)
	g.AlwaysOnTop = false
	g.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	g.Active = true
	g.Adornee = root
	local charges = if State.view then State.view.superFreezeCharges else 0
	local label = if charges > 0 then `Super Freeze ({charges} left)` else "Super Freeze"
	local b = Ui.block(g, "Button", Theme.iceDeep, label, function()
		State.send("RequestSuperFreeze", root:GetAttribute("PetId"))
	end)
	b.root.Size = UDim2.fromScale(1, 1)
	if charges == 0 then
		-- the price wears Roblox's own Robux mark (Child Safety: every purchase shows it), not "R$" text
		b.text.Size = UDim2.fromScale(0.6, 0.8)
		b.text.Position = UDim2.fromScale(0.04, 0.1)
		local mark = Ui.image(b.face, Config.images.icons.robux, UDim2.fromScale(0.14, 0.62), UDim2.fromScale(0.65, 0.19))
		mark.ZIndex = 2
		local price = Ui.label(b.face, tostring(Config.monetization.superFreeze.robux), UDim2.fromScale(0.18, 0.8), UDim2.fromScale(0.79, 0.1))
		price.TextXAlignment = Enum.TextXAlignment.Left
		price.ZIndex = 2
	end
	g.Parent = me:WaitForChild("PlayerGui")
	return g
end

local function hiddenFromMe(root: BasePart): boolean
	local owner = root:GetAttribute("OwnerUserId")
	return typeof(owner) == "number" and owner ~= 0 and owner ~= me.UserId
end

-- Pet motion (no rigs yet): every action is squash, stretch, lean, hop and turn on the whole pet,
-- around its feet, sized by its height. Each action is a short film in beats from its start (ActionStart),
-- so a crouch comes before a jump and a sneeze builds up before the CHOO. Walking keys off how far the
-- drawn pet really moved, not the action. Numbers in Config.petAnim.
local REST: Pose = { x = 0, y = 0, z = 0, pitch = 0, yaw = 0, roll = 0, sx = 1, sy = 1 }

local function seg(u: number, a: number, b: number): number
	return math.clamp((u - a) / (b - a), 0, 1)
end

local function easeOut(x: number): number
	return 1 - (1 - x) * (1 - x)
end

local function smooth(x: number): number
	return x * x * (3 - 2 * x)
end

local function backOut(x: number): number
	return 1 + 2.70158 * (x - 1) ^ 3 + 1.70158 * (x - 1) ^ 2
end

-- 1 at the start, swings past 0 once, then rests: the soft settle after a landing or a sneeze
local function settle(x: number): number
	return math.exp(-4 * x) * math.cos(math.pi * 1.5 * x)
end

local function wrap(a: number): number
	return (a + math.pi) % (2 * math.pi) - math.pi
end

local function mix(a: Pose, b: Pose, f: number): Pose
	local function m(x: number, y: number): number
		return x + (y - x) * f
	end
	return { x = m(a.x, b.x), y = m(a.y, b.y), z = m(a.z, b.z), pitch = m(a.pitch, b.pitch), yaw = m(a.yaw, b.yaw),
		roll = m(a.roll, b.roll), sx = m(a.sx, b.sx), sy = m(a.sy, b.sy) }
end

-- the action's pose t seconds in (clock = the pet's own ever-running time for loops);
-- k = 1, or Config.petAnim.reducedAmp with reduced motion. Pitch > 0 = nose up.
local function actionPose(key: string, t: number, clock: number, h: number, g: Gait, k: number): Pose
	local p = table.clone(REST)
	if key == "dazed" then -- dizzy after a melt: wobbles round in a circle and slowly turns
		local D = A.dazed
		local a = clock * D.wobble
		p.pitch, p.roll = D.tilt * k * math.sin(a), D.tilt * k * math.cos(a)
		p.x, p.z = D.sway * h * k * math.cos(a), D.sway * h * k * math.sin(a)
		p.yaw = wrap(clock * D.spin * k)
	elseif key == "sleep" then -- lying on its side, slow deep breaths
		local S = A.sleep
		local b = math.sin(clock * 2 * math.pi / S.breathePeriod) * k
		p.roll = P.sleepTilt
		p.y = -S.sink * h
		p.sy = 1 - S.flatten + S.breathe * b
		p.sx = 1 + S.flatten * 0.5 - S.breathe * 0.4 * b
	elseif key == "yawn" then -- a big slow stretch up and back, hold it, then sag and settle
		local Y = A.yawn
		local u = t / Config.poses.yawn.seconds
		local open = easeOut(seg(u, 0, Y.rise)) * (1 - smooth(seg(u, Y.settle, 1)))
		local sag = math.sin(math.pi * seg(u, Y.settle, 1))
		p.sy = 1 + (Y.stretch * open - Y.sag * sag) * k
		p.sx = 1 + (Y.sag * 0.6 * sag - Y.stretch * 0.45 * open) * k
		p.pitch = Y.lean * open * k
		p.roll = Y.roll * open * k
	elseif key == "jump" then -- crouch, spring up stretched, tip over the top, land in a squash and wobble back
		local J = A.jump
		local u = t / Config.poses.jump.seconds
		if u < J.crouch then
			local c = easeOut(u / J.crouch)
			p.sy, p.sx = 1 - J.squash * c * k, 1 + J.squash * 0.6 * c * k
		elseif u < J.land then
			local air = seg(u, J.crouch, J.land)
			local stretch = J.squash * math.max(0, 1 - 2 * air)
			p.y = J.height * h * 4 * air * (1 - air) * k
			p.sy, p.sx = 1 + stretch * k, 1 - stretch * 0.5 * k
			p.pitch = J.tuck * math.sin(2 * math.pi * air) * k
		else
			local s = settle(seg(u, J.land, 1))
			p.sy, p.sx = 1 - J.squash * s * k, 1 + J.squash * 0.6 * s * k
		end
	elseif key == "dance" then -- side-to-side hops on the beat, and a twirl on the last one
		local D = A.dance
		local u = math.min(t / Config.poses.dance.seconds, 0.9999)
		local beat = math.floor(u * D.beats)
		local b = u * D.beats - beat
		local arc = math.sin(math.pi * b)
		local side = if beat % 2 == 0 then 1 else -1
		local twirl = beat == D.beats - 1 and k >= 1
		p.y = D.hop * h * arc * k * (if twirl then D.twirlHop else 1)
		p.sy = 1 + D.squash * (arc - 0.6) * k
		p.sx = 1 - D.squash * 0.5 * (arc - 0.6) * k
		if twirl then
			p.yaw = 2 * math.pi * smooth(b)
		else
			p.roll = D.roll * side * arc * k
			p.yaw = D.sway * side * arc * k
			p.x = D.step * h * side * arc * k
		end
	elseif key == "sneeze" then -- "ah... ah..." leaning back in two breaths, then CHOO: snaps forward, jolts back
		local S = A.sneeze
		local u = t / Config.poses.sneeze.seconds
		if u < S.build then
			local v = u / S.build
			local inhale = 0.6 * smooth(seg(v, 0, 0.45)) + 0.4 * smooth(seg(v, 0.55, 1))
			p.sy, p.sx = 1 + S.stretch * inhale * k, 1 - S.stretch * 0.4 * inhale * k
			p.pitch = S.lean * inhale * k
		else
			local choo = if u < S.snap then easeOut(seg(u, S.build, S.snap)) else 1
			local rest = if u < S.snap then 1 else settle(seg(u, S.snap, 1))
			local stretch = S.stretch * (1 - choo) - S.squash * choo
			p.pitch = (S.lean * (1 - choo) - S.snapLean * choo) * rest * k
			p.sy, p.sx = 1 + stretch * rest * k, 1 - stretch * 0.5 * rest * k
			p.z = S.recoil * h * choo * rest * k
		end
	else -- idle: slow breathing, a look round now and then, and the rig's own bob (flyers hover)
		local I = A.idle
		local b = math.sin(clock * 2 * math.pi / I.breathePeriod)
		p.sy = 1 + I.breathe * b * k
		p.sx = 1 - I.breathe * 0.5 * b * k
		p.yaw = I.lookYaw * math.clamp(1.6 * math.sin(clock * 2 * math.pi / I.lookPeriod), -1, 1) * k
		p.y = g.bob * h * (0.5 + 0.5 * math.sin(clock * 2 * math.pi * g.bobHz)) * k
	end
	return p
end

-- the walk on top, w = how much it's walking (0-1): a bounce per step, rocking, waddling and leaning in
local function addWalk(p: Pose, w: number, phase: number, h: number, g: Gait, k: number)
	local s = phase % 1
	local arc = math.sin(math.pi * s)
	local side = math.sin(math.pi * phase) -- swaps sides every step
	local wk = w * k
	p.y += g.hop * h * arc * wk
	p.sy += g.squash * (arc - 0.5) * wk
	p.sx -= g.squash * 0.5 * (arc - 0.5) * wk
	p.pitch += (g.pitch * math.sin(2 * math.pi * s) - g.lean) * wk
	p.roll += g.roll * side * wk
	p.yaw += g.yaw * side * wk
end

-- a little snowy puff out of the nose on the CHOO
local function puffAt(at: CFrame, h: number, k: number)
	local e = puffPart and puffPart:FindFirstChildOfClass("ParticleEmitter")
	if puffPart and e then
		puffPart.CFrame = at
		e.Size = NumberSequence.new(h * A.sneeze.puffSize, 0)
		e:Emit(math.max(1, math.round(A.sneeze.puff * k)))
	end
end

local function newAnim(def: PetDefs.PetDef, model: PVInstance, img: ImageLabel?, root: BasePart): Anim
	local parts = {}
	local lids: { BasePart } = {}
	local headPivot: Vector3? = nil
	local scratchy, hasArms = false, false
	-- the same number on every client for this pet (its scratches line up for everyone)
	local id = root:GetAttribute("PetId")
	local seed = 0
	if typeof(id) == "string" then
		for i = 1, #id do
			seed = (seed * 31 + string.byte(id, i)) % 1000003
		end
	end
	if model:IsA("Model") then
		local pivot = model:GetPivot()
		local scale = (model :: Model):GetScale() -- Hip / Pivot attributes are in the unscaled model's space
		for _, p in model:GetDescendants() do
			if p:IsA("BasePart") then
				-- rigged pets: a leg or arm swings round its Hip; a head, ear or tail turns round its Pivot
				local hip = p:GetAttribute("Hip")
				local swing = p:GetAttribute("Swing")
				local at = p:GetAttribute("Pivot")
				local side = p:GetAttribute("Side")
				local role = p:GetAttribute("Role")
				table.insert(parts, { part = p, size = p.Size, rel = pivot:ToObjectSpace(p.CFrame),
					hip = if typeof(hip) == "Vector3" then hip * scale else nil, swing = if typeof(swing) == "number" then swing else 0,
					front = p:GetAttribute("Front") == true, role = if typeof(role) == "string" then role else "",
					pivot = if typeof(at) == "Vector3" then at * scale else nil, side = if typeof(side) == "number" then side else 0,
					hang = p:GetAttribute("Hang") == true, liftedOnly = p:GetAttribute("LiftedOnly") == true })
				if role == "head" and typeof(at) == "Vector3" then
					headPivot = at * scale
				end
				if role == "arm" or (role == "leg" and p:GetAttribute("Front") ~= true) then
					scratchy = true
				end
				hasArms = hasArms or role == "arm"
				if p:GetAttribute("Lid") == true then
					table.insert(lids, p)
				end
			end
		end
	elseif not img and model:IsA("BasePart") then -- the coloured ball stand-in
		table.insert(parts, { part = model, size = model.Size, rel = CFrame.identity, hip = nil, swing = 0, front = false,
			role = "", pivot = nil, side = 0, hang = false, liftedOnly = false })
	end
	local gaits: { [string]: Gait } = A.gait :: any
	return { key = "", start = nil, t = 0, clock = math.random() * 10, from = nil, blend = 0, blendLen = 0, last = REST,
		base = root.CFrame, walk = 0, phase = 0, gait = gaits[A.gaitFor[def.key] or def.rig] or gaits.Custom, parts = parts,
		sneezed = false, culled = false, seed = seed, scratchy = scratchy, hasArms = hasArms, headPivot = headPivot,
		lids = lids, shut = false, awake = 1 }
end

-- closes or opens a 3D pet's eyes (its lids show only while shut)
local function shutEyes(a: Anim, shut: boolean)
	if a.shut ~= shut then
		a.shut = shut
		for _, p in a.lids do
			p.LocalTransparencyModifier = if shut then 0 else 1
		end
	end
end

-- moves one pet for this frame; returns how high it is off the ground (0-1 of its height) for the shadow.
-- speed: the pet's clock rate (slower while held and while freezing); wiggle: the freeze struggle roll
-- Every drawn pet part is moved in one BulkMoveTo per frame instead of one CFrame write per part
-- (PERF-AUDIT-2026-11-09: ~1,000 parts a frame). Same CFrames, same frame.
local moveParts: { BasePart } = {}
local moveCFs: { CFrame } = {}
local function flushMoves()
	if #moveParts > 0 then
		workspace:BulkMoveTo(moveParts, moveCFs, Enum.BulkMoveMode.FireCFrameChanged)
	end
	table.clear(moveParts)
	table.clear(moveCFs)
end

local function animate(root: BasePart, d: Drawn, dt: number, now: number, cam: Camera, speed: number, wiggle: number): number
	local a = d.anim
	local h = d.height
	local feet = -h / 2
	-- the drawn pet glides after the server's root (it moves in 10 Hz steps) and turns smoothly
	local prev = a.base.Position
	local target = root.CFrame
	if (target.Position - prev).Magnitude > A.snapDistance then
		a.base = target
	else
		a.base = a.base.Rotation:Lerp(target.Rotation, 1 - math.exp(-A.turn * dt)) + prev:Lerp(target.Position, 1 - math.exp(-A.follow * dt))
	end
	local stepped = ((a.base.Position - prev) * Vector3.new(1, 0, 1)).Magnitude
	local walking = math.clamp(stepped / math.max(dt, 1e-3) / (Config.spawner.wanderSpeed * A.walkAt), 0, 1)
	a.walk += (walking - a.walk) * (1 - math.exp(-A.walkFade * dt))
	a.phase += stepped / (a.gait.stride * h)

	local action = root:GetAttribute("Action")
	local start = root:GetAttribute("ActionStart")
	local key = if root:GetAttribute("State") == "dazed" then "dazed"
		elseif typeof(action) == "string" and Config.poses[action] then action
		else "idle"
	if key ~= a.key or start ~= a.start then
		a.from, a.blend = a.last, 0
		a.blendLen = if key == "sleep" or a.key == "sleep" then A.sleepBlendSeconds else A.blendSeconds
		a.t = if typeof(start) == "number" and key ~= "dazed" then math.max(0, workspace:GetServerTimeNow() - start) else 0
		a.key, a.start, a.sneezed = key, start, false
	end
	a.t += dt * speed
	a.clock += dt * speed
	a.blend += dt
	-- asleep it holds still (only slow breathing) and its eyes close partway through lying down
	local asleep = key == "sleep"
	if asleep then
		a.walk = 0
	end
	a.awake += ((if asleep then 0 else 1) - a.awake) * (1 - math.exp(-4 * dt))
	shutEyes(a, asleep and a.blend >= a.blendLen * A.lids.shutAt)

	-- far away or off-screen it just stands (no pose maths), so a phone only animates what you see
	local _, onScreen = cam:WorldToViewportPoint(a.base.Position)
	local near = onScreen and (cam.CFrame.Position - a.base.Position).Magnitude < A.farDistance
	local pose = REST
	local legSwing, legTuck = 0, 0 -- rigged legs: the diagonal swing, and the reach / kick in the air
	local scratch, scratchSide, rub = 0, 1, 0 -- the scratch: how far in (0-1), which side, the rubbing wave
	local headRot, earTwitch, earWhich, earFlop, tailYaw = CFrame.identity, 0, 0, 0, 0
	if near then
		local k = if SettingsController.get("reducedMotion") == true then A.reducedAmp else 1
		pose = actionPose(key, a.t, a.clock, h, a.gait, k)
		if a.walk > 0.01 then
			addWalk(pose, a.walk, a.phase, h, a.gait, k)
		end
		-- the legs step with the walk cycle (one step per phase unit, like addWalk's side swap), tap
		-- along to the dance's beats, and tuck in while the pet is off the ground. cos, not sin: the feet
		-- are furthest apart as a foot lands (the low point of each step) and pass under the body at its
		-- high point, while the body leans onto the leg that's on the ground (owner 2026-11-04: with sin
		-- the penguin's legs moved reversed)
		local L = A.limbs
		legSwing = L.walk * a.walk * math.cos(math.pi * a.phase) * k
		if key == "dance" then
			legSwing += L.dance * math.sin(math.pi * A.dance.beats * a.t / Config.poses.dance.seconds) * k
		end
		legTuck = L.tuck * math.clamp(pose.y / (h * L.tuckHeight), 0, 1)
		-- a scratch: some idles, standing still, picked from the pet's id and this idle's start
		local S = A.scratch
		if key == "idle" and a.scratchy and a.walk < 0.2 and typeof(a.start) == "number" then
			local r = Random.new(a.seed + math.floor(a.start * 10))
			if r:NextNumber() < S.chance then
				scratchSide = if r:NextNumber() < 0.5 then -1 else 1
				local u = a.t - S.start
				scratch = math.clamp(math.min(u, S.seconds - u) / S.ramp, 0, 1) * k
				rub = math.sin(a.clock * 2 * math.pi * S.rubHz)
			end
		end
		if scratch > 0 then
			pose = table.clone(pose)
			pose.roll -= S.lean * scratch * scratchSide -- leans into the scratch
		end
		-- head, ears and tail
		local PA = A.parts
		local still = (1 - 0.6 * a.walk) * a.awake -- asleep: the head stops looking round
		local hYaw = PA.headLook * math.sin(a.clock * 2 * math.pi / PA.headLookPeriod) * still * k
		local hPitch = PA.headNod * a.walk * math.sin(2 * math.pi * a.phase) * k - S.headPitch * scratch
		local hRoll = -scratchSide * S.headRoll * scratch + 0.04 * scratch * rub
		headRot = CFrame.Angles(hPitch, hYaw, hRoll)
		-- one ear at a time flicks now and then (each pet on its own beat)
		local every = PA.earTwitchEvery
		local tt = a.clock + (a.seed % 97) / 97 * every
		local cyc = tt % every
		earTwitch = if cyc < PA.earTwitchSeconds then math.sin(math.pi * cyc / PA.earTwitchSeconds) * k * a.awake else 0
		earWhich = if math.floor(tt / every) % 2 == 0 then -1 else 1
		earFlop = PA.earFlop * (a.walk * math.sin(2 * math.pi * a.phase) + math.clamp(pose.y / h, 0, 1)) * k
		local dancing = key == "dance"
		tailYaw = (if dancing then PA.tailDanceWag else PA.tailWag)
			* math.sin(a.clock * 2 * math.pi * (if dancing then PA.tailDanceHz else PA.tailHz)) * k * a.awake
		if a.culled then
			a.from, a.blend, a.blendLen = REST, 0, A.blendSeconds
		end
		if a.from and a.blend < a.blendLen then
			pose = mix(a.from, pose, smooth(a.blend / a.blendLen))
		end
		pose.yaw = wrap(pose.yaw)
		if key == "sneeze" and not a.sneezed and a.t >= A.sneeze.build * Config.poses.sneeze.seconds then
			a.sneezed = true
			puffAt(a.base * CFrame.new(0, h * 0.15, -h * 0.55), h, k)
		end
	end
	if wiggle ~= 0 then
		pose = table.clone(pose)
		pose.roll += wiggle
	end
	a.culled = not near
	a.last = pose

	-- a hat pops off on a jump (Toddle's signature: the cap bounces off and back on), timed from the jump's
	-- start like every other beat: off at take-off, over the head, back on just after the landing, a tiny
	-- re-hop, then a wobble that settles on a damped spring
	local PA = A.parts
	local hatLift, hatRoll = 0, 0
	if near and key == "jump" then
		local len = Config.poses.jump.seconds
		local u = a.t / len
		local side = if a.seed % 2 == 0 then 1 else -1
		local reduce = if SettingsController.get("reducedMotion") == true then A.reducedAmp else 1
		if u > PA.hatOff and u < PA.hatOn then
			local s = (u - PA.hatOff) / (PA.hatOn - PA.hatOff)
			local arc = math.sin(math.pi * s ^ 0.8) -- peaks a little after the middle, like it's still rising
			hatLift = PA.hatLift * h * arc
			hatRoll = PA.hatTilt * arc * side
		elseif u >= PA.hatOn then
			local x = (u - PA.hatOn) * len -- seconds since it landed
			if x < PA.hatHopSeconds then
				hatLift = PA.hatHop * h * math.sin(math.pi * x / PA.hatHopSeconds)
			end
			local w = x / PA.hatSettle
			if w < 1 then
				hatRoll = -PA.hatTilt * math.exp(-4 * w) * math.cos(1.5 * math.pi * w) * side
			end
		end
		hatLift *= reduce
		hatRoll *= reduce
	end

	local pop = math.max(0.05, backOut(math.min(1, (now - d.born) / P.popSeconds)))
	local sx, sy = pose.sx * pop, pose.sy * pop
	if d.img then
		-- a sprite always faces the camera: it moves, squashes and tilts; a turn shows as a paper flip
		d.model:PivotTo(CFrame.new((a.base * CFrame.new(pose.x, pose.y, pose.z)).Position))
		d.img.Size = UDim2.fromScale(sx * math.max(0.2, math.abs(math.cos(pose.yaw))), sy)
		d.img.Rotation = math.deg(pose.roll + pose.pitch * 0.5)
	else
		-- lean and turn round the feet, then squash each part about the feet too
		local cf = a.base * CFrame.new(pose.x, feet + pose.y, pose.z) * CFrame.Angles(0, pose.yaw, 0)
			* CFrame.Angles(pose.pitch, 0, pose.roll) * CFrame.new(0, -feet, 0)
		-- the head turns round its neck (squashed with the rest); ears ride on it
		local headTurn = CFrame.identity
		if a.headPivot then
			local np = a.headPivot
			local neck = CFrame.new(np.X * sx, feet + (np.Y - feet) * sy, np.Z * sx)
			headTurn = neck * headRot * neck:Inverse()
		end
		for _, part in a.parts do
			local rp = part.rel.Position
			local place = CFrame.new(rp.X * sx, feet + (rp.Y - feet) * sy, rp.Z * sx) * part.rel.Rotation
			local hp = part.hip
			local role = part.role
			if hp then
				-- turning round X moves the foot forward (-Z) for a positive angle
				local hipAt = CFrame.new(hp.X * sx, feet + (hp.Y - feet) * sy, hp.Z * sx)
				local angle = part.swing * legSwing + (if part.front then legTuck else -legTuck)
				local out = 0
				if scratch > 0 and part.side == scratchSide then
					local S = A.scratch
					if role == "arm" then
						angle += scratch * (S.arm + S.rub * rub) -- the hand comes up to the head
					elseif role == "leg" and not part.front and not a.hasArms then -- a pet with arms scratches with a hand
						angle += scratch * (S.leg + S.rub * rub) -- the back foot comes forward and up
						out = part.side * S.out * scratch -- and out to the side, toward the ear
					end
				end
				place = hipAt * CFrame.Angles(angle, 0, out) * hipAt:Inverse() * place
			elseif role == "head" then
				place = headTurn * place
			elseif role == "hat" then
				-- rides on the head, lifted by the hat's own bounce and tipped a little round its rim
				local pv = part.pivot or rp
				local base = CFrame.new(pv.X * sx, feet + (pv.Y - feet) * sy, pv.Z * sx)
				place = CFrame.new(0, hatLift, 0) * headTurn * base * CFrame.Angles(hatLift / h * 0.12, 0, hatRoll)
					* base:Inverse() * place
				if part.liftedOnly then
					-- e.g. the cap's underside: inside the head at rest, only shown while the hat is off
					part.part.LocalTransparencyModifier = if hatLift > A.parts.hatShowAt * h then 0 else 1
				end
			elseif (role == "ear" or role == "wing") and part.pivot then
				-- twitch outward (an upright ear tips out with -side, a hanging one with +side), flop with the steps,
				-- and flap on the side being scratched; ears ride on the head. Wings flap the same way, both at
				-- once, and stay on the body when the head turns.
				local pv = part.pivot
				local base = CFrame.new(pv.X * sx, feet + (pv.Y - feet) * sy, pv.Z * sx)
				local outward = if part.hang then part.side else -part.side
				local twitch = if part.side == 0 or part.side == earWhich or role == "wing" then earTwitch else 0
				local flap = if part.side == scratchSide then A.scratch.earFlap * scratch * (0.5 + 0.5 * rub) else 0
				local roll = outward * (A.parts.earTwitch * twitch + flap)
				local pitch = if part.hang then earFlop else earFlop * 0.3
				place = (if role == "wing" then CFrame.identity else headTurn) * base * CFrame.Angles(pitch, 0, roll)
					* base:Inverse() * place
			elseif role == "tail" and part.pivot then
				local pv = part.pivot
				local base = CFrame.new(pv.X * sx, feet + (pv.Y - feet) * sy, pv.Z * sx)
				place = base * CFrame.Angles(0, tailYaw, 0) * base:Inverse() * place
			end
			table.insert(moveParts, part.part) -- moved together at the end of the frame (flushMoves)
			table.insert(moveCFs, cf * place)
			local s = part.rel:VectorToObjectSpace(Vector3.new(sx, sy, sx))
			local size = part.size * Vector3.new(math.abs(s.X), math.abs(s.Y), math.abs(s.Z))
			if size ~= part.part.Size then
				part.part.Size = size
			end
		end
		local m = d.model
		if m:IsA("Model") then
			m.WorldPivot = cf -- the name tag follows the pet
		end
	end
	return math.clamp(pose.y / h, 0, 1)
end

local function addPet(root: Instance)
	if not root:IsA("BasePart") or drawn[root] then
		return
	end
	local def = PetDefs.get(root:GetAttribute("PetKey") :: string)
	if not def then
		return
	end
	if hiddenFromMe(root) then
		local prompt = root:FindFirstChildWhichIsA("ProximityPrompt", true)
		if prompt then
			prompt.Enabled = false -- someone else's personal rare: not here for you
		end
		return
	end
	-- a banked pet waits frozen in its ice cube (in the Thaw Machine's line or inside it): drawn inside
	-- it, a bit smaller. Thawed ("out"), it's a normal pet strolling round the pan (Round 5).
	local penPet = root:GetAttribute("Banked") == true
	local banked = penPet and root:GetAttribute("Thaw") ~= "out"
	local h = if banked then (root :: BasePart).Size.Y * 0.62 else PetDefs.height(def, root:GetAttribute("Size") :: string?) -- Big ... Cosmic stand taller
	local wild = root:GetAttribute("PenOwner") == nil
	-- a wild pet's parts all live in its own box, so step() can hide it while you're on another island
	-- (owner 2026-11-13: no glowing pets seen through the gates and walls)
	local box: Folder? = nil
	local home: Instance = folder
	if wild then
		box = Instance.new("Folder")
		;(box :: Folder).Name = "WildPet"
		;(box :: Folder).Parent = folder
		home = box :: Folder
	end
	local model, img = standIn(def, h)
	model.Parent = home
	if not banked and not penPet then
		nameTag(model, def, h, root:GetAttribute("Mut"), root:GetAttribute("Size"))
	end
	-- prototype syncWild: a soft shadow, a glowing ring in the tier's colour (wild pets only),
	-- dazed stars, sparkles round Rare and up, snowflakes round Frosty pets
	local color = Theme.tiers[def.tier] or Theme.white
	local core = fxPart(Vector3.one * 0.2, color, home) :: Part
	core.Transparency = 1
	local shadow = fxPart(Vector3.new(0.1, h * P.shadowScale, h * P.shadowScale), Theme.fx.shadow, home)
	shadow.Shape = Enum.PartType.Cylinder
	shadow.Transparency = 0.7
	local ring = if wild then fxPart(Vector3.new(h * P.ringScale, 0.15, h * P.ringScale), color, home, "Ring") else nil
	if ring then
		ring.Material = Enum.Material.Neon
		ring.Transparency = 0.25
		if Config.tier(def.tier).rank >= 3 then
			sparkles(ring, color, P.rareSparkleRate)
		end
	end
	local stars: { BasePart } = {}
	for _ = 1, P.starCount do
		local s = fxPart(Vector3.new(0.35, 0.5, 0.35), Theme.fx.star, home, "Octa")
		s.Material = Enum.Material.Neon
		s.Transparency = 1
		table.insert(stars, s)
	end
	if root:GetAttribute("Mut") == "Frosty" then
		sparkles(core, Theme.fx.frost, P.frostySparkleRate)
	end
	local b: Banked? = nil
	if banked then
		shadow.Transparency = 1
		-- white ice edges like a carried cube, and a coin that rises from it now and then
		local edges = Instance.new("SelectionBox")
		edges.Adornee = root :: BasePart
		edges.Color3 = Theme.white
		edges.LineThickness = 0.04
		edges.Transparency = P.edgeTransparency
		edges.SurfaceTransparency = 1
		edges.Parent = folder
		local coin = Instance.new("BillboardGui")
		coin.Name = "PanCoin"
		coin.Size = UDim2.fromScale(PC.coinSize, PC.coinSize)
		coin.Adornee = root :: BasePart
		coin.MaxDistance = PC.drawDistance * 0.5
		coin.LightInfluence = 0
		local ci = Instance.new("ImageLabel")
		ci.BackgroundTransparency = 1
		ci.Size = UDim2.fromScale(1, 1)
		ci.Image = Config.images.icons.coin
		ci.Parent = coin
		coin.Parent = folder
		b = { edges = edges, coin = coin, coinImg = ci, phase = math.random() * PC.coinEvery }
	end
	mutationLook(model, img, core, root:GetAttribute("Mut"))
	drawn[root] = { model = model, height = h, offer = nil, img = img, born = os.clock(), fx = { core = core, ring = ring, shadow = shadow, stars = stars }, banked = b,
		clock = math.random() * 10, freeze = nil, zzz = zzzGui(core, h), anim = newAnim(def, model, img, root), box = box, shown = true }
end

local function removePet(root: Instance)
	local d = drawn[root :: BasePart]
	if d then
		clearFreeze(d)
		-- the Night Reset takes the wild pets away: a snowy poof where each one stood, not a blink
		if workspace:GetAttribute("NightReset") == true and d.model.Parent and d.model:IsA("PVInstance") then
			puffAt((d.model :: PVInstance):GetPivot(), d.height, 4)
		end
		d.model:Destroy()
		if d.offer then
			d.offer:Destroy()
		end
		d.fx.core:Destroy()
		d.fx.shadow:Destroy()
		if d.fx.ring then
			d.fx.ring:Destroy()
		end
		for _, s in d.fx.stars do
			s:Destroy()
		end
		if d.banked then
			d.banked.edges:Destroy()
			d.banked.coin:Destroy()
			if d.banked.ready then
				d.banked.ready:Destroy()
			end
		end
		if d.box then
			d.box:Destroy()
		end
		drawn[root :: BasePart] = nil
	end
end

-- frozen air bubbles (2026-11-17 realism pass): a few small pale balls just inside the cube's walls, where
-- the pet in the middle doesn't hide them. Offsets from the cube's middle.
local function bubbleSpots(size: number): { CFrame }
	local r = Random.new()
	local out = {}
	for i = 1, FZ.bubbles do
		local v = { r:NextNumber(-0.4, 0.4), r:NextNumber(-0.4, 0.4), r:NextNumber(-0.4, 0.4) }
		local axis = (i - 1) % 3 + 1
		v[axis] = (if r:NextNumber() < 0.5 then -1 else 1) * r:NextNumber(0.33, 0.44) -- pushed out to a wall
		table.insert(out, CFrame.new(v[1] * size, v[2] * size, v[3] * size))
	end
	return out
end

local function bubble(size: number, parent: Instance): BasePart
	local b = fxPart(Vector3.one * size * (0.03 + 0.03 * math.random()), Theme.white, parent)
	b.Shape = Enum.PartType.Ball
	b.Material = Enum.Material.SmoothPlastic
	b.Transparency = 0.5
	return b
end

-- the cube's detail (owner 2026-11-17: "make the cube even more detailed"; Config.show.freeze.cubeDetail). Real ice
-- blocks: cloudy at the bottom where air got trapped, frosted at the corners, faint fracture planes inside catching
-- the light, glossy reflection streaks on the faces, and a few rime crystals on the top. Offsets from the cube's
-- middle; top = rides down on the ice's top as a carried cube melts. Low graphics: base and streaks only.
type Detail = { part: BasePart, offset: CFrame, top: boolean, alpha: number }
local function cubeDetail(size: number, parent: Instance): { Detail }
	local D = FZ.cubeDetail
	local r = Random.new()
	local low = SettingsController.get("lowGraphics") == true
	local out: { Detail } = {}
	local function add(p: BasePart, offset: CFrame, top: boolean)
		p.CFrame = offset
		table.insert(out, { part = p, offset = offset, top = top, alpha = p.Transparency })
	end
	-- the cloudy base: milky ice in the bottom share, a touch inside the walls
	local base = fxPart(Vector3.new(size * 0.97, size * D.base, size * 0.97), Theme.white, parent)
	base.Material = Enum.Material.Snow
	base.Transparency = D.baseTransparency
	add(base, CFrame.new(0, -size / 2 + size * D.base / 2 + 0.01, 0), false)
	-- glossy streaks: two long thin highlights running diagonally across two side faces, a short one beside each
	for k = 0, 1 do
		local face = CFrame.Angles(0, k * math.pi / 2, 0) * CFrame.new(0, 0, -size / 2 - 0.015)
		for j, len in { D.streak, D.streak * 0.45 } do
			local s = fxPart(Vector3.new(size * len, size * (if j == 1 then 0.045 else 0.03), 0.02), Theme.white, parent)
			s.Material = Enum.Material.SmoothPlastic
			s.Transparency = D.streakTransparency + (j - 1) * 0.1
			add(s, face * CFrame.new(size * (0.08 - 0.12 * (j - 1)), size * (0.12 + 0.13 * (j - 1)), 0) * CFrame.Angles(0, 0, D.streakAngle), false)
		end
	end
	if low then
		return out
	end
	-- frosted corners: small snowy caps sitting into each corner
	for _, x in { -1, 1 } do
		for _, y in { -1, 1 } do
			for _, z in { -1, 1 } do
				local c = fxPart(Vector3.one * size * D.corner * r:NextNumber(0.75, 1.15), Theme.fx.frost, parent)
				c.Material = Enum.Material.Snow
				c.Transparency = D.cornerTransparency
				add(c, CFrame.new(Vector3.new(x, y, z) * size * (0.5 - D.corner * 0.35)) * CFrame.Angles(r:NextNumber(-0.3, 0.3), r:NextNumber(0, 1.5), r:NextNumber(-0.3, 0.3)), y > 0)
			end
		end
	end
	-- fracture planes: thin, faint sheets inside at odd angles
	for _ = 1, D.fractures do
		local f = fxPart(Vector3.new(size * r:NextNumber(0.35, 0.55), size * r:NextNumber(0.3, 0.5), 0.02), Theme.white, parent)
		f.Material = Enum.Material.Neon
		f.Transparency = D.fractureTransparency
		local at = Vector3.new(r:NextNumber(-0.25, 0.25), r:NextNumber(-0.2, 0.2), r:NextNumber(-0.25, 0.25)) * size
		add(f, CFrame.new(at) * CFrame.Angles(r:NextNumber(-1, 1), r:NextNumber(0, 3), r:NextNumber(-1, 1)), false)
	end
	-- rime crystals standing on the top face
	for _ = 1, D.rime do
		local c = fxPart(Vector3.one * 0.05, Theme.fx.crystal, parent, "Octa")
		local s = size * r:NextNumber(0.05, 0.09)
		c.Size = Vector3.new(s * 0.6, s * 1.4, s * 0.6)
		c.Material = Enum.Material.Glass
		c.Transparency = 0.2
		local at = Vector3.new(r:NextNumber(-0.38, 0.38) * size, size / 2 + s * 0.45, r:NextNumber(-0.38, 0.38) * size)
		add(c, CFrame.new(at) * CFrame.Angles(r:NextNumber(-0.5, 0.5), r:NextNumber(0, 3), r:NextNumber(-0.5, 0.5)), true)
	end
	return out
end

-- prototype crackGeo: a few zig-zag cracks on three faces, shown when the cube is nearly gone
local function makeCracks(part: BasePart): { { part: BasePart, offset: CFrame } }
	local out = {}
	local s = part.Size.X
	local r = Random.new()
	for i = 1, P.crackLines do
		local face = i % 3
		local a, b = (r:NextNumber() - 0.5) * 0.6, (r:NextNumber() - 0.5) * 0.6
		for _ = 1, 3 do
			local na, nb = a + (r:NextNumber() - 0.5) * 0.35, b + (r:NextNumber() - 0.5) * 0.35
			local function onFace(u: number, v: number): Vector3
				return (if face == 0 then Vector3.new(u, v, 0.51) elseif face == 1 then Vector3.new(0.51, u, v) else Vector3.new(u, 0.51, v)) * s
			end
			local p0, p1 = onFace(a, b), onFace(na, nb)
			local seg = fxPart(Vector3.new(0.05, 0.05, math.max(0.05, (p1 - p0).Magnitude)), Theme.white, folder)
			seg.Material = Enum.Material.Neon
			seg.Transparency = 1
			table.insert(out, { part = seg, offset = CFrame.lookAt((p0 + p1) / 2, p1) })
			a, b = na, nb
		end
	end
	return out
end

local function addCube(part: Instance)
	if not part:IsA("BasePart") or cubes[part] then
		return
	end
	local def = PetDefs.get(part:GetAttribute("PetKey") :: string)
	if not def then
		return
	end
	local onGround = part.Parent ~= nil and part.Parent.Name == "GroundCubes"
	if onGround and part:GetAttribute("OwnerUserId") ~= me.UserId then
		local prompt = part:FindFirstChildWhichIsA("ProximityPrompt", true)
		if prompt then
			-- someone else's frozen pet: only they can pick it up, until the server opens it to all
			-- (Config.carry.openAfter, owner 2026-11-17)
			local function sync()
				prompt.Enabled = part:GetAttribute("OpenToAll") == true
			end
			sync()
			part:GetAttributeChangedSignal("OpenToAll"):Connect(sync) -- goes with the part
		end
	end
	local model, img = standIn(def, part.Size.Y * 0.6, part:GetAttribute("Pose") == "sleep") -- frozen asleep: eyes shut
	model.Parent = folder
	mutationLook(model, img, part, part:GetAttribute("Mut"))
	-- the ice we draw (the server's cube is hidden on this screen): it melts from the top down
	local M = P.melt
	local ice = fxPart(part.Size, Theme.ice, folder)
	ice.Name = "MeltIce"
	ice.Material = Enum.Material.SmoothPlastic -- not Glass: the pet inside would vanish (World Rules)
	ice.Transparency = 0.45
	local line = fxPart(Vector3.new(part.Size.X * (1 + M.line.grow), M.line.thick, part.Size.Z * (1 + M.line.grow)), Theme.ice, folder)
	line.Name = "MeltLine"
	line.Material = Enum.Material.Neon
	line.Transparency = 1
	local drips = Instance.new("ParticleEmitter")
	drips.Color = ColorSequence.new(Theme.ice)
	drips.LightEmission = 0.4
	drips.Rate = 0
	drips.EmissionDirection = Enum.NormalId.Top
	drips.Speed = NumberRange.new(M.drips.speed[1], M.drips.speed[2])
	drips.SpreadAngle = Vector2.new(70, 70)
	drips.Acceleration = Vector3.new(0, -M.drips.fall, 0)
	drips.Lifetime = NumberRange.new(M.drips.life[1], M.drips.life[2])
	drips.Size = NumberSequence.new(M.drips.size, M.drips.size * 0.6)
	drips.Transparency = NumberSequence.new(0.1, 0.6)
	drips.Parent = line
	-- white ice edges (prototype frame lines), round the ice that's left
	local edges = Instance.new("SelectionBox")
	edges.Adornee = ice
	edges.Color3 = Theme.white
	edges.LineThickness = 0.04
	edges.Transparency = P.edgeTransparency
	edges.SurfaceTransparency = 1
	edges.Parent = folder
	local frac = part:GetAttribute("LifeFrac")
	local start = if typeof(frac) == "number" then frac else 1
	local bubbles = {}
	for _, off in bubbleSpots(part.Size.X) do
		table.insert(bubbles, { part = bubble(part.Size.X, folder), offset = off })
	end
	cubes[part] = { model = model, edges = edges, cracks = makeCracks(part), onGround = onGround,
		ice = ice, line = line, drips = drips, shown = start, lastFrac = start, meltAt = -math.huge, bubbles = bubbles,
		detail = cubeDetail(part.Size.X, folder) }
end

local function removeCube(part: Instance)
	local c = cubes[part :: BasePart]
	if c then
		c.model:Destroy()
		c.edges:Destroy()
		c.ice:Destroy()
		c.line:Destroy() -- its drips go with it
		for _, k in c.cracks do
			k.part:Destroy()
		end
		for _, b in c.bubbles do
			b.part:Destroy()
		end
		for _, x in c.detail do
			x.part:Destroy()
		end
		cubes[part :: BasePart] = nil
	end
end

-- ---------- the pet I'm freezing (Round 4 phase 3) ----------
-- Ice creeps up from the feet as a glassy shell, frost spreads over the pet and its colour cools,
-- crystals grow along the outline. A layered freeze (big or rare pet, weak gun) also cracks and drops
-- bits of ice. How far it has got comes from RayController (the server's plan for this hold).
-- The front (owner 2026-11-05, from a freeze reference clip): mist at the feet first, then the ice climbs
-- fast and slows near the top, with a bright rim on it and crystal flecks flickering just above.
local function newFreeze(root: BasePart, d: Drawn, style: string): FreezeLook
	local h = d.height
	-- the ice grows in layers (Config.show.freeze.bands): each band a little crooked and a little wider or narrower
	local B = FZ.bands
	local rb = Random.new()
	local bands = {}
	for _ = 1, (if style == "flash" then 1 else B.count) do
		local band = fxPart(Vector3.new(h, 0.05, h), Theme.ice, folder)
		band.Material = Enum.Material.SmoothPlastic -- not Glass: it would hide a sprite pet inside (World Rules)
		band.Transparency = 1
		table.insert(bands, { part = band, jitter = rb:NextNumber(-B.jitter, B.jitter), turn = rb:NextNumber(-B.turn, B.turn) })
	end
	local hl: Highlight? = nil
	if not d.img then -- a 3D model gets a frost overlay; a sprite's colour is tinted instead
		local x = Instance.new("Highlight")
		x.Adornee = d.model
		x.FillColor = Theme.fx.frostTint
		x.OutlineColor = Theme.white
		x.FillTransparency = 1
		x.OutlineTransparency = 1
		x.DepthMode = Enum.HighlightDepthMode.Occluded
		x.Parent = folder
		hl = x
	end
	local crystals: { BasePart } = {}
	local cracks: { { part: BasePart, face: number, u: number, v: number, turn: number } } = {}
	if style ~= "flash" then -- a flash-freeze is over too fast for crystals
		for _ = 1, FZ.crystals do
			local c = fxPart(Vector3.one * 0.05, Theme.fx.crystal, folder, "Octa")
			c.Material = Enum.Material.Neon
			c.Transparency = 0.15
			table.insert(crystals, c)
		end
	end
	if style == "layered" then
		local r = Random.new()
		for _ = 1, FZ.cracks do
			local k = fxPart(Vector3.new(0.06, 0.06, h * 0.35), Theme.fx.crack, folder)
			k.Material = Enum.Material.Neon
			k.Transparency = 1
			table.insert(cracks, { part = k, face = r:NextInteger(0, 3), u = r:NextNumber(-0.35, 0.35), v = r:NextNumber(0.15, 0.85), turn = r:NextNumber(-0.9, 0.9) })
		end
	end
	-- the front: a bright rim on the ice, flecks flickering just above it, mist rolling in at the feet
	-- (a flash-freeze is over too fast for any of it)
	local rim: { BasePart } = {}
	local flecks: { Fleck } = {}
	local mist: BasePart? = nil
	local mistFx: ParticleEmitter? = nil
	if style ~= "flash" then
		for _ = 1, 4 do -- a thin bright line round the top edge of the ice (four bars, not a lid)
			local bar = fxPart(Vector3.new(h, FZ.rim.thick, FZ.rim.thick), Theme.fx.frost, folder)
			bar.Material = Enum.Material.Neon
			bar.Transparency = 1
			table.insert(rim, bar)
		end
		for _ = 1, FZ.flecks.count do
			local c = fxPart(Vector3.one * 0.05, Theme.fx.crystal, folder, "Octa")
			c.Material = Enum.Material.Neon
			c.Transparency = 1
			table.insert(flecks, { part = c, round = -1, angle = 0, y = 0, reach = 1 })
		end
		local m = fxPart(Vector3.new(h, 0.1, h), Theme.fx.frost, folder)
		m.Transparency = 1
		local e = Instance.new("ParticleEmitter")
		e.Color = ColorSequence.new(Theme.fx.frost)
		e.LightEmission = 0.2
		e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.55), NumberSequenceKeypoint.new(1, 1) })
		e.Size = NumberSequence.new(0.6, 1.8)
		e.Speed = NumberRange.new(0.8, 1.8)
		e.Drag = 2
		e.Acceleration = Vector3.new(0, -0.5, 0)
		e.Lifetime = NumberRange.new(0.8, 1.2)
		e.EmissionDirection = Enum.NormalId.Top
		e.SpreadAngle = Vector2.new(80, 80)
		e.Rate = 0
		e.Parent = m
		mist, mistFx = m, e
	end
	-- frost spreading over the ground from the feet (a snowy patch with fingers reaching out of it), frost
	-- feathers growing on the ice faces and glints twinkling on the ice (not on a flash-freeze: too quick)
	local patch: BasePart? = nil
	local fingers = {}
	local ferns = {}
	local glintBox: BasePart? = nil
	local glintFx: ParticleEmitter? = nil
	if style ~= "flash" then
		local low = SettingsController.get("lowGraphics") == true
		local G = FZ.groundFrost
		local pt = fxPart(Vector3.new(0.05, h, h), Theme.fx.frost, folder)
		pt.Shape = Enum.PartType.Cylinder
		pt.Material = Enum.Material.Snow
		pt.Transparency = 1
		patch = pt
		local nf = if low then math.ceil(G.fingers / 2) else G.fingers
		for i = 1, nf do
			local f = fxPart(Vector3.new(0.08, 0.04, 0.1), Theme.fx.frost, folder)
			f.Material = Enum.Material.Neon
			f.Transparency = 1
			table.insert(fingers, { part = f, angle = (i + rb:NextNumber(-0.35, 0.35)) * (2 * math.pi / nf), len = rb:NextNumber(0.6, 1) })
		end
		local FN = FZ.ferns
		local nn = if low then math.ceil(FN.count / 2) else FN.count
		for i = 1, nn do
			local parts = {}
			for _ = 1, 3 do -- a stem and a pair of side branches
				local s = fxPart(Vector3.new(0.05, 0.1, 0.05), Theme.fx.crack, folder)
				s.Material = Enum.Material.Neon
				s.Transparency = 1
				table.insert(parts, s)
			end
			table.insert(ferns, { parts = parts, face = (i - 1) % 4, u = rb:NextNumber(-0.3, 0.3), v = rb:NextNumber(FN.from, 0.7), tilt = rb:NextNumber(-0.5, 0.5) })
		end
		local gb = fxPart(Vector3.one, Theme.ice, folder)
		gb.Transparency = 1
		local ge = Instance.new("ParticleEmitter")
		ge.Color = ColorSequence.new(Theme.white)
		ge.LightEmission = 1
		ge.Shape = Enum.ParticleEmitterShape.Box
		ge.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
		ge.Speed = NumberRange.new(0)
		ge.Lifetime = NumberRange.new(0.15, 0.3)
		ge.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.4, 0.22), NumberSequenceKeypoint.new(1, 0) })
		ge.Rotation = NumberRange.new(0, 90)
		ge.Rate = 0
		ge.Parent = gb
		glintBox, glintFx = gb, ge
	end
	return { bands = bands, highlight = hl, crystals = crystals, cracks = cracks, nextChip = os.clock() + FZ.chipEvery, style = style, cracked = 0,
		rim = rim, flecks = flecks, mist = mist, mistFx = mistFx, patch = patch, fingers = fingers, ferns = ferns, glintBox = glintBox, glintFx = glintFx }
end

clearFreeze = function(d: Drawn)
	local f = d.freeze
	if not f then
		return
	end
	for _, b in f.bands do
		b.part:Destroy()
	end
	for _, x in f.fingers do
		x.part:Destroy()
	end
	for _, fern in f.ferns do
		for _, s in fern.parts do
			s:Destroy()
		end
	end
	if f.patch then
		f.patch:Destroy()
	end
	if f.glintBox then
		f.glintBox:Destroy()
	end
	if f.highlight then
		f.highlight:Destroy()
	end
	for _, c in f.crystals do
		c:Destroy()
	end
	for _, k in f.cracks do
		k.part:Destroy()
	end
	for _, x in f.flecks do
		x.part:Destroy()
	end
	for _, bar in f.rim do
		bar:Destroy()
	end
	if f.mist then
		f.mist:Destroy()
	end
	if d.img then
		d.img.ImageColor3 = Theme.white
	end
	d.freeze = nil
end

-- a bit of ice falls off the shell's top edge and fades
local function chip(at: Vector3)
	local c = fxPart(Vector3.one * FZ.chipSize, Theme.ice, folder)
	c.Material = Enum.Material.Glass
	c.Transparency = 0.25
	c.CFrame = CFrame.new(at) * CFrame.Angles(math.random() * 3, math.random() * 3, 0)
	local time = FZ.chipSeconds * (if SettingsController.get("reducedMotion") == true then 0.5 else 1)
	TweenService:Create(c, TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		CFrame = c.CFrame - Vector3.new(0, FZ.chipFall, 0), Transparency = 1,
	}):Play()
	task.delay(time, function()
		c:Destroy()
	end)
end

local function drawFreeze(root: BasePart, d: Drawn, fz: RayController.Freeze, t: number)
	if d.freeze and d.freeze.style ~= fz.style then
		clearFreeze(d) -- the server's plan arrived with another style
	end
	if not d.freeze then
		d.freeze = newFreeze(root, d, fz.style)
	end
	local f = d.freeze :: FreezeLook
	local p = fz.p
	local h = d.height
	local w = h * FZ.shellPad
	local ground = root.Position - Vector3.new(0, root.Size.Y / 2, 0)
	-- the front climbs fast, then slows near the top; the frost colour (from p) trails behind it
	local front = easeOut(math.clamp(p, 0, 1))
	local iceH = math.max(0.05, front * h * 1.05)
	-- the ice in layers: each band fills as the front climbs through it, pops out a touch as it forms, sits a
	-- little crooked; the lower bands are thicker and older ice turns cloudier (still glassy enough to see the pet)
	local B = FZ.bands
	local nb = #f.bands
	local full = h * 1.05
	local outer = w * (1 + B.jitter + B.baseThick) -- the widest the ice gets (feathers and cracks sit on it)
	for i, b in f.bands do
		local lo, hi = (i - 1) / nb * full, i / nb * full
		local filled = math.clamp(iceH - lo, 0, hi - lo)
		if filled <= 0.01 then
			b.part.Transparency = 1
			continue
		end
		local k = filled / (hi - lo)
		local pop = 0.86 + 0.14 * backOut(math.min(1, k / B.pop))
		local bw = w * (1 + b.jitter + B.baseThick * (1 - (i - 1) / math.max(1, nb - 1))) * pop
		b.part.Size = Vector3.new(bw, filled, bw)
		b.part.CFrame = CFrame.new(ground + Vector3.new(0, lo + filled / 2, 0)) * root.CFrame.Rotation * CFrame.Angles(0, b.turn, 0)
		local age = seg(front, i / nb, i / nb + 0.35)
		b.part.Transparency = B.clear[1] + (B.clear[2] - B.clear[1]) * age
		b.part.Color = Theme.ice:Lerp(Theme.white, B.cloud * age)
	end
	-- frost on the ground first: a snowy patch spreads from the feet, fingers of frost reach out of it
	local G = FZ.groundFrost
	local spread = easeOut(seg(p, 0, 0.6))
	if f.patch then
		local dia = outer * (0.6 + (G.reach - 0.6) * spread)
		f.patch.Size = Vector3.new(0.05, dia, dia)
		f.patch.CFrame = CFrame.new(ground + Vector3.new(0, 0.03, 0)) * CFrame.Angles(0, 0, math.pi / 2)
		f.patch.Transparency = if p > 0.01 then G.transparency + (1 - G.transparency) * (1 - spread) * 0.6 else 1
		for _, x in f.fingers do
			local len = G.fingerLength * h * x.len * easeOut(seg(p, 0.08, 0.75))
			local r0 = dia / 2 * 0.85
			x.part.Size = Vector3.new(0.08, 0.04, math.max(0.05, len))
			x.part.CFrame = CFrame.new(ground + Vector3.new(0, 0.05, 0)) * CFrame.Angles(0, x.angle, 0) * CFrame.new(0, 0, -(r0 + len / 2))
			x.part.Transparency = if len > 0.06 then 0.35 else 1
		end
	end
	-- frost feathers grow on the ice faces once the front passes them: a stem and two side branches
	for _, fern in f.ferns do
		local g = math.clamp((front - fern.v) * 4, 0, 1)
		local stem = FZ.ferns.size * h * g
		local face = CFrame.new(ground) * root.CFrame.Rotation * CFrame.Angles(0, fern.face * math.pi / 2, 0)
			* CFrame.new(fern.u * outer, fern.v * h, -outer / 2 - 0.03) * CFrame.Angles(0, 0, fern.tilt)
		local function place(part: BasePart, x0: number, y0: number, x1: number, y1: number)
			local dx, dy = x1 - x0, y1 - y0
			local len = math.sqrt(dx * dx + dy * dy)
			part.Transparency = if len > 0.04 then FZ.ferns.transparency else 1
			part.Size = Vector3.new(FZ.ferns.thick, math.max(0.05, len), FZ.ferns.thick)
			part.CFrame = face * CFrame.new((x0 + x1) / 2, (y0 + y1) / 2, 0) * CFrame.Angles(0, 0, math.atan2(-dx, dy))
		end
		place(fern.parts[1], 0, 0, 0, stem)
		local b = stem * 0.45
		place(fern.parts[2], 0, stem * 0.45, -b * 0.7, stem * 0.45 + b * 0.7)
		place(fern.parts[3], 0, stem * 0.65, b * 0.6, stem * 0.65 + b * 0.6)
	end
	-- glints twinkle on the ice's surface
	if f.glintBox and f.glintFx then
		f.glintBox.Size = Vector3.new(outer, iceH, outer)
		f.glintBox.CFrame = CFrame.new(ground + Vector3.new(0, iceH / 2, 0)) * root.CFrame.Rotation
		f.glintFx.Rate = FZ.iceGlints.rate * p * (if SettingsController.get("lowGraphics") == true then 0.5 else 1)
	end
	if f.highlight then
		f.highlight.FillTransparency = 1 - FZ.frostFill * p
		f.highlight.OutlineTransparency = 1 - 0.8 * p
	end
	-- crystals along the outline, from the feet up: each one grows once the ice reaches it
	local n = #f.crystals
	for i, c in f.crystals do
		local from = (i - 1) / n
		local grow = math.clamp((front - from) * n, 0, 1)
		local a = i * 2.4 + 0.3
		local s = FZ.crystalSize * grow * (0.7 + 0.3 * math.sin(i * 1.7))
		c.Size = Vector3.new(s * 0.6, math.max(0.05, s * 1.3), s * 0.6)
		c.Transparency = if grow <= 0 then 1 else 0.15
		local y = math.min(from, 0.9) * h + 0.2
		c.CFrame = CFrame.new(ground + Vector3.new(math.cos(a) * w * 0.5, y, math.sin(a) * w * 0.5)) * CFrame.Angles(math.sin(a) * 0.5, 0, -math.cos(a) * 0.5)
	end
	-- layered: cracks show on the ice as it passes them; bits of ice fall off now and then
	-- the rim rides the top of the ice and fades as it reaches the top
	local open = front > 0.02 and front < 0.97
	local rimClear = if open then FZ.rim.transparency + (1 - FZ.rim.transparency) * seg(front, 0.8, 0.97) else 1
	local top = CFrame.new(ground + Vector3.new(0, iceH, 0)) * root.CFrame.Rotation
	for i, bar in f.rim do
		bar.Transparency = rimClear
		bar.Size = Vector3.new(w + FZ.rim.thick, FZ.rim.thick, FZ.rim.thick)
		bar.CFrame = top * CFrame.Angles(0, (i - 1) * math.pi / 2, 0) * CFrame.new(0, 0, w / 2)
	end
	-- flecks flicker in a band just above the rim, each at a new spot every round
	local FL = FZ.flecks
	local mine = RayController.current()
	local myTarget = mine ~= nil and mine.root == root
	for i, x in f.flecks do
		local u = t / FL.seconds + i / #f.flecks
		local round = math.floor(u)
		if round ~= x.round then
			x.round = round
			x.angle = math.random() * math.pi * 2
			x.y = FL.band[1] + math.random() * (FL.band[2] - FL.band[1])
			x.reach = 0.7 + math.random() * 0.35
			if open and myTarget and i == 1 then
				SoundController.play("ray_crackle", 0.95 + 0.1 * math.random())
			end
		end
		local life = 1 - math.abs(2 * (u - round) - 1) -- 0 -> 1 -> 0 over the round
		local y = math.min(iceH + x.y * h, h * 1.05)
		local s = FL.size * life
		x.part.Transparency = if open and life > 0.05 then 1 - 0.8 * life else 1
		x.part.Size = Vector3.new(s * 0.6, math.max(0.05, s * 1.3), s * 0.6)
		x.part.CFrame = CFrame.new(ground + Vector3.new(math.cos(x.angle) * w * 0.5 * x.reach, y, math.sin(x.angle) * w * 0.5 * x.reach))
			* CFrame.Angles(0, x.angle, 0.4)
	end
	-- mist rolls in at the feet first and thins out as the ice takes over
	if f.mist and f.mistFx then
		f.mist.Size = Vector3.new(w, 0.1, w)
		f.mist.CFrame = CFrame.new(ground + Vector3.new(0, 0.1, 0))
		local low = if SettingsController.get("lowGraphics") == true then 0.5 else 1
		f.mistFx.Rate = FZ.mist.rate * low * (1 - seg(p, FZ.mist.untilMeter * 0.5, FZ.mist.untilMeter))
	end
	for i, k in f.cracks do
		local show = p >= FZ.cracksFrom and k.v <= front
		k.part.Transparency = if show then 0.1 else 1
		if show then
			local side = CFrame.Angles(0, k.face * math.pi / 2, 0)
			k.part.CFrame = CFrame.new(ground) * root.CFrame.Rotation * side * CFrame.new(k.u * w, k.v * h, -outer / 2 - 0.02) * CFrame.Angles(0, 0, k.turn) * CFrame.Angles(math.pi / 2, 0, 0)
			if i > f.cracked then
				f.cracked = i
				SoundController.play("crack")
			end
		end
	end
	if f.style == "layered" and t >= f.nextChip and p > 0.1 then
		f.nextChip = t + FZ.chipEvery
		local a = math.random() * math.pi * 2
		chip(ground + Vector3.new(math.cos(a) * w * 0.5, iceH, math.sin(a) * w * 0.5))
	end
end

-- a pet frozen in its cube, drawn for an effect or a show (the cube shuts at the pet's spot, then
-- flies into your hands). The caller moves it with PivotTo and destroys it.
function PetVisuals.frozenCube(key: string, size: number): (Model?, Part?)
	local def = PetDefs.get(key)
	if not def then
		return nil, nil
	end
	local m = Instance.new("Model")
	m.Name = "FrozenCube"
	local cube = fxPart(Vector3.one * size, Theme.ice, m) :: Part
	cube.Name = "Cube"
	cube.Material = Enum.Material.SmoothPlastic -- not Glass: it would hide a sprite pet inside (World Rules)
	cube.Transparency = 0.45
	local pet = standIn(def, size * 0.6)
	cube.CFrame = CFrame.new()
	pet:PivotTo(CFrame.new()) -- the pet sits in the middle of its cube; the caller moves both with PivotTo
	pet.Parent = m
	local edges = Instance.new("SelectionBox")
	edges.Adornee = cube
	edges.Color3 = Theme.white
	edges.LineThickness = 0.04
	edges.Transparency = P.edgeTransparency
	edges.SurfaceTransparency = 1
	edges.Parent = cube
	for _, off in bubbleSpots(size) do -- frozen air bubbles near the walls
		local b = bubble(size, m)
		b.CFrame = off
	end
	cubeDetail(size, m) -- cloudy base, frosted corners, fractures, streaks, rime (placed round the origin)
	m.PrimaryPart = cube
	m.Parent = folder
	return m, cube
end

-- a pet's model (or painted sprite) on its own, for other controllers (Heat Critters wear a pet's art)
-- the model drawn for a wild or pen pet's root (the root itself is an invisible part): the tutorial
-- makes the pet the tutorial is showing glow
function PetVisuals.drawnModel(root: Instance): PVInstance?
	local d = if root:IsA("BasePart") then drawn[root] else nil
	return if d then d.model else nil
end

function PetVisuals.model(key: string, size: number): (PVInstance?, ImageLabel?)
	local def = PetDefs.get(key)
	if not def then
		return nil, nil
	end
	return standIn(def, size)
end

-- a thawed pan pet's stroll: a slow walk to a random spot in its pan, a little pause, again. Only this
-- client moves the root (the server's copy stays on its grid spot), and the ice cube is hidden here.
local function stroll(root: BasePart, d: Drawn, dt: number, t: number)
	local plot = root:GetAttribute("Plot")
	local spot = typeof(plot) == "number" and Config.world.plots[plot]
	if not spot then
		return
	end
	root.LocalTransparencyModifier = 1
	local W, P = Config.thaw.wander, Config.world.pans
	local s = strolls[root]
	if not s then
		local y = root.Position.Y - root.Size.Y / 2 + d.height / 2
		s = { pos = Vector3.new(root.Position.X, y, root.Position.Z), to = nil, pauseUntil = t + math.random() * W.pause[2] }
		strolls[root] = s
	end
	local st = s :: { pos: Vector3, to: Vector3?, pauseUntil: number }
	if root:GetAttribute("Action") == "sleep" then
		root.CFrame = CFrame.new(st.pos) * root.CFrame.Rotation -- asleep: it stays where it lay down
		return
	end
	if not st.to and t >= st.pauseUntil then
		local halfW = P.width / 2 - W.margin
		local plotN = root:GetAttribute("Plot")
		local len = if typeof(plotN) == "number" then Config.plotLength(plotN) else P.length -- the pan grows with its Slots
		local back, front = P.frontZ - len + Config.thaw.machine.z + 4, P.frontZ - W.margin
		st.to = Vector3.new(spot.x + (math.random() * 2 - 1) * halfW, st.pos.Y, back + math.random() * (front - back))
	end
	local to = st.to
	if to then
		local flat = to - st.pos
		local step = W.speed * dt
		if flat.Magnitude <= step then
			st.pos = to
			st.to = nil
			st.pauseUntil = t + W.pause[1] + math.random() * (W.pause[2] - W.pause[1])
		else
			st.pos += flat.Unit * step
			root.CFrame = CFrame.lookAt(st.pos, st.pos + flat.Unit)
			return
		end
	end
	root.CFrame = CFrame.new(st.pos) * root.CFrame.Rotation
end

local function nearestOffer(): BasePart?
	for root, d in drawn do
		if d.offer then
			return root
		end
	end
	return nil
end

local function step(dt: number)
	local t = os.clock()
	local mine = 0
	local cam = workspace.CurrentCamera
	local reduced = SettingsController.get("reducedMotion") == true
	-- the island I'm on: wild pets show only there (from the hub, island 1 shows too: it's open to it)
	local char = me.Character
	local myRoot = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local myZone = if myRoot then WorldRules.zoneAt(myRoot.Position) else -1
	for root, d in drawn do
		if not root.Parent then
			removePet(root)
			continue
		end
		if d.box then
			local z = root:GetAttribute("Zone")
			-- owner 2026-11-16 ("the pets disappear after not being in the zone, so you cannot see if a secret spawned"):
			-- your island and the ones either side of it show, and a Secret shows from anywhere
			local show = z == myZone or (myZone == 0 and z == 1)
				or (typeof(z) == "number" and myZone > 0 and math.abs(z - myZone) <= 1)
				or root:GetAttribute("Tier") == "Secret"
			if show ~= d.shown then
				d.shown = show
				d.box.Parent = if show then folder else nil
				root:SetAttribute("OffIsland", not show) -- this client only: RayController won't aim at it
				if not show then
					clearFreeze(d)
				end
			end
			if not show then
				continue
			end
		end
		if d.banked then
			-- frozen on the pan: a tiny wiggle inside the ice, frost shimmer, a coin rising now and then
			local b = d.banked
			d.fx.core.Position = root.Position -- Frosty snowflakes stay with the cube
			shutEyes(d.anim, root:GetAttribute("Action") == "sleep") -- frozen asleep: it naps with its eyes shut
			if cam and (cam.CFrame.Position - root.Position).Magnitude > PC.drawDistance then
				continue -- nothing moves far away
			end
			local amp = if reduced then 0.3 else 1
			-- in the Thaw Machine: it shakes more and the ice clears as the time runs out
			local thawLeft = 1
			local ends, total = root:GetAttribute("ThawEnd"), root:GetAttribute("ThawTotal")
			if root:GetAttribute("Thaw") == "machine" and typeof(ends) == "number" and typeof(total) == "number" and total > 0 then
				thawLeft = math.clamp((ends - workspace:GetServerTimeNow()) / total, 0, 1)
				amp *= 1 + 3 * (1 - thawLeft)
			end
			-- done and waiting for Claim (Config.thaw.claimByHand): a green READY! sign bobs over it
			local isReady = Config.thaw.claimByHand and root:GetAttribute("Thaw") == "machine" and thawLeft <= 0
			if isReady then
				amp = if reduced then 0.3 else 1 -- it waits calmly in its ice, no more shaking
			end
			if isReady and not b.ready then
				local RS = Config.thaw.readySign
				local g = Instance.new("BillboardGui")
				g.Name = "ThawReady"
				g.Adornee = root
				g.Size = UDim2.fromScale(RS.size[1], RS.size[2])
				g.LightInfluence = 0
				g.MaxDistance = PC.drawDistance
				local sign = Ui.block(g, "Sign", Theme.go, "READY!", nil)
				sign.root.Size = UDim2.fromScale(1, 1)
				g.Parent = folder
				b.ready = g
			elseif not isReady and b.ready then
				b.ready:Destroy()
				b.ready = nil
			end
			if b.ready then
				local RS = Config.thaw.readySign
				b.ready.StudsOffset = Vector3.new(0, RS.y - root.Size.Y / 2 + math.sin(t * RS.bobSpeed) * RS.bob * (if reduced then 0 else 1), 0)
			end
			local w = math.sin(t * PC.wiggleSpeed + b.phase) * PC.wiggle * amp
			local at = root.CFrame * CFrame.new(0, -root.Size.Y / 2 + d.height / 2 + 0.15, 0) * CFrame.Angles(0, 0, w)
			if d.img then
				d.model:PivotTo(CFrame.new(at.Position))
				d.img.Rotation = math.deg(w)
			else
				d.model:PivotTo(at)
			end
			local shimmer = math.sin(t * PC.shimmerSpeed * math.pi * 2 + b.phase * 2)
			-- in the machine the ice clears away round the pet as its time runs out (owner 2026-11-16: "you should see
			-- how your pet unfreezes"): the block fades toward glass and its edges soften. Owner 2026-11-18: at the
			-- end the cube vanished and the pet looked out but stuck in the machine, so it stays a clear ice cube
			-- (never past PC.thawMeltMax), and once it's ready it's a full cube again until you Claim it
			local melted = if isReady then 0 else math.min(1 - thawLeft, PC.thawMeltMax)
			local iceLeft = if isReady then 1 else thawLeft
			root.Transparency = math.min(0.97, 0.5 + shimmer * PC.shimmerAmount * amp * iceLeft + 0.47 * melted)
			b.edges.Transparency = math.min(1, P.edgeTransparency - shimmer * 0.2 * amp + (1 - P.edgeTransparency) * melted)
			local u = ((t + b.phase) % PC.coinEvery) / PC.coinEvery
			b.coin.StudsOffset = Vector3.new(0, root.Size.Y / 2 + math.min(1, u * 2) * PC.coinRise, 0)
			b.coinImg.ImageTransparency = if u < 0.5 then u * 2 else 1
			continue
		end
		if root:GetAttribute("Thaw") == "out" then
			stroll(root, d, dt, t)
			CoinPops.tick(root, d.height, t) -- my pan's pets pop "+N" as they earn
		end
		local dazed = root:GetAttribute("State") == "dazed"
		-- the pet I'm freezing: it slows down as the ice climbs and struggles a little (cute, never scary)
		local fz = RayController.freezeOf(root) -- anyone's ray on it (Round 5: every player sees every freeze)
		local p = if fz then fz.p else 0
		-- scared (some ice, not stuck yet): it scurries; stuck: it slows to a stop as the ice climbs
		local meter = (root:GetAttribute("Meter") or 0) :: number
		local scared = meter > 0 and meter < Config.aim.stuckAt and not dazed and root:GetAttribute("Action") ~= "sleep"
		local speed = if scared then 1.7 else (1 - FZ.slowdown * p)
		d.clock += dt * speed
		local wiggle = if fz then math.sin(t * FZ.struggle.speed) * FZ.struggle.amp * 4 * p * (1 - p) * (if reduced then 0.3 else 1) else 0
		wiggle += RayController.shakeOf(root, reduced) -- too warm for my gun: a little side shake
		local lift = animate(root, d, dt, t, cam, speed, wiggle)
		if d.img then
			d.img.ImageColor3 = Theme.white:Lerp(Theme.fx.frostTint, p) -- the colour cools and fades
		end
		if fz then
			drawFreeze(root, d, fz, t)
		elseif d.freeze then
			clearFreeze(d)
		end
		local ground = root.Position - Vector3.new(0, root.Size.Y / 2, 0)
		d.fx.core.Position = root.Position
		-- the shadow stays under the drawn pet and shrinks while it's up in the air
		local shadowSize = d.height * P.shadowScale * (1 - 0.4 * lift)
		d.fx.shadow.Size = Vector3.new(0.1, shadowSize, shadowSize)
		d.fx.shadow.CFrame = CFrame.new(d.anim.base.Position - Vector3.new(0, d.height / 2 - 0.1, 0)) * CFrame.Angles(0, 0, math.pi / 2)
		if d.fx.ring then
			d.fx.ring.CFrame = CFrame.new(ground + Vector3.new(0, 0.14, 0)) * CFrame.Angles(0, t * P.ringSpin, 0)
			d.fx.ring.Transparency = 0.3 + math.sin(t * 4) * 0.12
		end
		for i, s in d.fx.stars do
			local a = t * P.starSpin + i * (math.pi * 2 / #d.fx.stars)
			s.Transparency = if dazed then 0 else 1
			s.CFrame = CFrame.new(root.Position + Vector3.new(math.cos(a) * P.starRadius, d.height * (P.starHeight - 0.5), math.sin(a) * P.starRadius)) * CFrame.Angles(0, a, 0)
		end
		local asleep = root:GetAttribute("Action") == "sleep" and not dazed
		d.zzz.Enabled = asleep
		if asleep then
			for i = 1, 3 do
				local z = d.zzz:FindFirstChild("Z" .. i) :: TextLabel
				local u = (t / (Config.night.zzzEvery * 3) + (i - 1) / 3) % 1
				z.Position = UDim2.fromScale(0.3 + u * 0.4, 0.9 - u * 0.8)
				z.TextTransparency = u
				local stroke = z:FindFirstChildOfClass("UIStroke") :: UIStroke
				stroke.Transparency = u
				z.Size = UDim2.fromScale(0.3 + u * 0.3, 0.3 + u * 0.3)
			end
		end
		local offerFor = root:GetAttribute("OfferUserId")
		local wantOffer = offerFor == me.UserId and root:GetAttribute("State") == "dazed"
		if wantOffer and not d.offer then
			d.offer = offerButton(root)
		elseif not wantOffer and d.offer then
			d.offer:Destroy()
			d.offer = nil
		end
	end
	for part, c in cubes do
		if not part.Parent then
			removeCube(part)
			continue
		end
		if part:GetAttribute("OwnerUserId") == me.UserId and not c.onGround then
			mine += 1
		end
		-- hidden on this screen while its snap or show plays at the pet's spot (a local attribute)
		local hidden = part:GetAttribute("ShowHidden") == true
		part.LocalTransparencyModifier = 1 -- its ice is drawn here (c.ice), melting from the top down
		c.edges.Visible = not hidden
		if hidden then
			c.model:PivotTo(part.CFrame * CFrame.new(0, -500, 0))
			c.ice.Transparency = 1
			c.line.Transparency = 1
			c.drips.Rate = 0
			for _, k in c.cracks do
				k.part.Transparency = 1
			end
			for _, b in c.bubbles do
				b.part.Transparency = 1
			end
			for _, x in c.detail do
				x.part.Transparency = 1
			end
			continue
		end
		c.model:PivotTo(part.CFrame)
		-- the cube shows time left (no timer): the ice melts away from the top down, so the pet comes free
		-- head first, with a wet water line and drips at the melt edge; it cracks low down, then flashes
		local M = P.melt
		local frac = part:GetAttribute("LifeFrac")
		local superFrozen = part:GetAttribute("SuperFrozen") == true
		-- back in the safe hub it freezes solid again (owner 2026-11-17: "so it looks right on the thaw
		-- machine"). Only the look: the server's life is unchanged, so out on an island again it shows
		-- the real ice left
		local safe = WorldRules.inHub(part.Position)
		local life = if typeof(frac) == "number" and not superFrozen and not safe then math.clamp(frac, 0, 1) else 1
		if life < c.lastFrac - 1e-4 then
			c.meltAt = t -- it's melting right now (in the hub or a Big Chill it stops)
		end
		c.lastFrac = life
		-- LifeFrac comes in 1% steps: glide between them; refreezing in the hub is a slower, visible grow
		c.shown += (life - c.shown) * math.min(1, dt * (if life > c.shown then M.refreeze else M.follow))
		local share = math.max(M.floor, c.shown)
		local size = part.Size
		local h = size.Y * share
		local bottom = part.CFrame * CFrame.new(0, -size.Y / 2, 0)
		c.ice.Size = Vector3.new(size.X, h, size.Z)
		c.ice.CFrame = bottom * CFrame.new(0, h / 2, 0)
		if superFrozen then
			c.ice.Color = Theme.fx.superFrozen
			c.ice.Transparency = 0.45
		else
			local flash = life < 0.25 and math.sin(t * 12) > 0
			c.ice.Transparency = 0.45 + (1 - life) * M.fade
			c.ice.Color = if flash then Theme.no else Theme.ice
		end
		for _, b in c.bubbles do -- bubbles stay only in the ice that's left
			local inIce = b.offset.Position.Y < h - size.Y / 2 - 0.05
			b.part.Transparency = if inIce then 0.5 else 1
			b.part.CFrame = part.CFrame * b.offset
		end
		-- the detail: top pieces (rime, upper corners) ride down on the ice's top; the rest show only in the ice left
		for _, x in c.detail do
			if x.top then
				x.part.Transparency = x.alpha
				x.part.CFrame = part.CFrame * CFrame.new(0, h - size.Y, 0) * x.offset
			else
				local inIce = x.offset.Position.Y < h - size.Y / 2 - 0.02
				x.part.Transparency = if inIce then x.alpha else 1
				x.part.CFrame = part.CFrame * x.offset
			end
		end
		c.line.CFrame = bottom * CFrame.new(0, h, 0)
		c.line.Transparency = if share < 0.995 then M.line.transparency else 1
		local melting = share < 0.995 and t - c.meltAt < M.drips.meltingFor
		c.drips.Rate = if melting then M.drips.rate * (if reduced then 0.5 else 1) else 0
		-- cracks: the top face's ride down on the ice's top, the sides' show only below the melt line
		local cracked = life < P.crackBelow and not superFrozen
		for _, k in c.cracks do
			local y = k.offset.Position.Y
			local onTop = y > size.Y * 0.45
			local show = cracked and (onTop or y < h - size.Y / 2)
			k.part.Transparency = if show then 0.1 else 1
			if show then
				k.part.CFrame = part.CFrame * (if onTop then CFrame.new(0, h - size.Y, 0) * k.offset else k.offset)
			end
		end
	end
	CameraController.setCarrying(mine > 0)
end

local function watch(name: string, add: (Instance) -> (), remove: (Instance) -> ())
	task.spawn(function()
		local f = workspace:WaitForChild(name, 30)
		if not f then
			return
		end
		f.ChildAdded:Connect(function(c)
			task.defer(add, c) -- attributes arrive with the part
		end)
		f.ChildRemoved:Connect(remove)
		for _, c in f:GetChildren() do
			add(c)
		end
	end)
end

function PetVisuals.Init()
	folder = Instance.new("Folder")
	folder.Name = "PetVisuals"
	folder.Parent = workspace
end

function PetVisuals.Start()
	meshes = ReplicatedStorage:FindFirstChild("SceneryMeshes")
	-- one shared emitter for every sneeze puff (moved to the sneezing nose, then Emit)
	local pp = fxPart(Vector3.one * 0.2, Theme.white, folder)
	pp.Name = "SneezePuff"
	pp.Transparency = 1
	local e = Instance.new("ParticleEmitter")
	e.Rate = 0
	e.Color = ColorSequence.new(Theme.white)
	e.LightEmission = 0.3
	e.EmissionDirection = Enum.NormalId.Front
	e.SpreadAngle = Vector2.new(25, 25)
	e.Speed = NumberRange.new(A.sneeze.puffSpeed * 0.6, A.sneeze.puffSpeed)
	e.Drag = 5
	e.Lifetime = NumberRange.new(A.sneeze.puffLife * 0.6, A.sneeze.puffLife)
	e.Transparency = NumberSequence.new(0.1, 1)
	e.Parent = pp
	puffPart = pp
	watch("WildPets", addPet, removePet)
	-- everyone's banked pets: frozen cubes waiting for the Thaw Machine, then pets strolling round the pan.
	-- When a pet thaws it's drawn again as a walking pet.
	watch("PenPets", function(root: Instance)
		if root:IsA("BasePart") and not root:GetAttribute("ThawWatched") then
			root:SetAttribute("ThawWatched", true) -- a local mark: connect once
			root:GetAttributeChangedSignal("Thaw"):Connect(function()
				local d = drawn[root]
				local isCube = d ~= nil and d.banked ~= nil
				if d and isCube == (root:GetAttribute("Thaw") == "out") then
					removePet(root)
					strolls[root] = nil
					root.LocalTransparencyModifier = 0
					addPet(root)
				end
			end)
		end
		addPet(root)
	end, removePet)
	watch("Cubes", addCube, removeCube)
	watch("GroundCubes", addCube, removeCube)
	RunService.RenderStepped:Connect(function(dt: number)
		table.clear(moveParts) -- a frame that errored part-way leaves nothing stale behind
		table.clear(moveCFs)
		step(dt)
		flushMoves()
	end)
	InputController.Action:Connect(function(a: string)
		if a == "superFreeze" then
			local root = nearestOffer()
			if root then
				State.send("RequestSuperFreeze", root:GetAttribute("PetId"))
			end
		end
	end)
end

return PetVisuals
