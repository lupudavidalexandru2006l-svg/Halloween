--!strict
-- TutorialNpc: Captain Frost in the world, driven by TutorialController (no Init/Start of its own).
-- Each player gets a local copy of the model the server built (ReplicatedStorage.TutorialGuide), so a
-- full server never has six guides crowding the plaza and each one only follows its own player.
-- He glides on the frost jets under his cryo tank (owner 2026-11-14: he used to slide through fences
-- and pop up onto their tops): an anchored root moved by hand, standing on the ground while still,
-- hovering a little while he moves and rising smoothly over anything in his way. His height always
-- eases toward where it should be, so nothing ever pops. He drops in from the sky, poofs over to you
-- when left far behind, and jets off at the end. Roblox's own R15 animations (idle, wave, point, cheer).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Theme = require(ReplicatedStorage.Shared.Theme)
local Ui = require(script.Parent.Parent.Lib.Ui)
local SettingsController = require(script.Parent.SettingsController)

local TutorialNpc = {}
local T = Config.tutorial
local N = T.npc
local me = Players.LocalPlayer

local model: Model? = nil
local root: BasePart? = nil
local hip = 3
local tracks: { [string]: AnimationTrack } = {}
local jets: { ParticleEmitter } = {}
local poof: ParticleEmitter? = nil
local pos = Vector3.zero -- where he is over the ground (Y = the ground under him)
local feetY = 0 -- where his feet are drawn (eases toward the ground plus his hover)
local yaw = 0
local lean = 0
local speed = 0 -- studs a second right now (eases toward what he wants)
local goal: Vector3? = nil
local lookAt: Vector3? = nil
local leaving = false
local gestureTrack: AnimationTrack? = nil
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.RespectCanCollide = true

local function template(): Model?
	local t = ReplicatedStorage:WaitForChild(T.modelName, 15)
	return if t and t:IsA("Model") then t else nil
end

local function flat(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

-- the top of whatever's under (x, z), looking down from fromY; nil = nothing there. Players, pets,
-- cubes and the guides never count: only the world he can stand on.
local function surface(at: Vector3, fromY: number, depth: number): number?
	local exclude: { Instance } = {}
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(exclude, p.Character)
		end
	end
	for _, name in { "WildPets", "PenPets", "Cubes", "GroundCubes", "Guides" } do
		local f = workspace:FindFirstChild(name)
		if f then
			table.insert(exclude, f)
		end
	end
	if model then
		table.insert(exclude, model)
	end
	rayParams.FilterDescendantsInstances = exclude
	local hit = workspace:Raycast(Vector3.new(at.X, fromY, at.Z), Vector3.new(0, -depth, 0), rayParams)
	return if hit then hit.Position.Y else nil
end

-- the ground under `at`: from a little over his feet, so a fence, a post or an awning over him is
-- never mistaken for the ground (he flies over those, see step)
local function groundY(at: Vector3): number
	return surface(at, at.Y + N.stepUp, N.groundRay) or at.Y
end

local function yawTo(dir: Vector3): number
	return math.atan2(-dir.X, -dir.Z) -- CFrame.Angles(0, yaw, 0) looks down -Z
end

local function turnToward(want: number, rate: number)
	yaw += math.atan2(math.sin(want - yaw), math.cos(want - yaw)) * math.min(1, rate)
end

local function load(name: string, looped: boolean, priority: Enum.AnimationPriority): AnimationTrack?
	local id = N.anims[name]
	local hum = model and model:FindFirstChildOfClass("Humanoid")
	if not id or not hum then
		return nil
	end
	local animator = hum:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = hum
	end
	assert(animator)
	local a = Instance.new("Animation")
	a.AnimationId = "rbxassetid://" .. id
	local ok, track = pcall(function()
		return animator:LoadAnimation(a)
	end)
	if not ok or not track then
		return nil
	end
	track.Looped = looped
	track.Priority = priority
	return track
end

local function place()
	if root then
		root.CFrame = CFrame.new(pos.X, feetY + hip, pos.Z) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(-math.rad(lean), 0, 0)
	end
end

local function setJets(on: boolean)
	for _, e in jets do
		if e.Enabled ~= on then
			e.Enabled = on
		end
	end
end

local function burst()
	if poof and SettingsController.get("reducedMotion") ~= true then
		poof:Emit(28)
	end
end

-- he drops in from the sky at `at`, facing `face` (the player); false if the server couldn't build him
function TutorialNpc.spawn(at: Vector3, face: Vector3?): boolean
	if model then
		return true
	end
	local t = template()
	if not t or model then -- a second spawn while this one waited for the template: keep the first
		return model ~= nil
	end
	local m = t:Clone()
	local r = m.PrimaryPart or m:FindFirstChild("HumanoidRootPart") :: BasePart?
	local hum = m:FindFirstChildOfClass("Humanoid")
	if not r or not hum then
		m:Destroy()
		return false
	end
	r.Anchored = true
	hum.EvaluateStateMachine = false -- he's moved by hand: no falling, no climbing, no physics fights
	hip = hum.HipHeight + r.Size.Y / 2
	model, root = m, r
	pos = Vector3.new(at.X, groundY(at), at.Z)
	feetY = pos.Y + N.dropFrom
	yaw = if face then yawTo(Vector3.new(face.X - at.X, 0, face.Z - at.Z)) else 0
	goal, lookAt, leaving, speed, lean = nil, nil, false, 0, 0
	jets, poof = {}, nil
	-- the whole model to its first spot before it goes live (moving only the root left welded pieces behind)
	m:PivotTo(CFrame.new(pos.X, feetY + hip, pos.Z) * CFrame.Angles(0, yaw, 0))
	for _, d in m:GetDescendants() do
		if d:IsA("ParticleEmitter") then
			if d.Name == "Jet" then
				table.insert(jets, d)
			elseif d.Name == "Poof" then
				poof = d
			end
		end
	end
	place()
	-- his name over his head: the same Chunky Pop pill as the pets' names
	local head = m:FindFirstChild("Head") :: BasePart?
	if head then
		local pill = Ui.pill(T.name, Theme.tutorial.coat, Config.worldText.tag)
		pill.Name = "NamePill"
		pill.Adornee = head
		pill.StudsOffsetWorldSpace = Vector3.new(0, N.pillY, 0)
		pill.Parent = m
	end
	m.Parent = workspace
	tracks = {}
	for name, spec in { idle = { true, Enum.AnimationPriority.Idle }, wave = { false, Enum.AnimationPriority.Action },
		point = { false, Enum.AnimationPriority.Action }, cheer = { false, Enum.AnimationPriority.Action } } :: { [string]: { any } } do
		local tr = load(name, spec[1], spec[2])
		if tr then
			tracks[name] = tr
		end
	end
	if tracks.idle then
		tracks.idle:Play()
	end
	return true
end

function TutorialNpc.despawn()
	for _, tr in tracks do
		tr:Stop(0)
		tr:Destroy()
	end
	tracks = {}
	gestureTrack = nil
	jets, poof = {}, nil
	if model then
		model:Destroy()
	end
	model, root = nil, nil
	leaving = false
end

-- the end: he jets straight up into the sky (TutorialController despawns him a moment later)
function TutorialNpc.leave()
	if model then
		leaving = true
		goal = nil
	end
end

function TutorialNpc.alive(): boolean
	return model ~= nil
end

function TutorialNpc.position(): Vector3?
	return if model then pos else nil
end

-- where he flies to (nil = stay put). A spot close to where he's already going is ignored, so a
-- wandering pet or a player shuffling about doesn't make him twitch.
function TutorialNpc.walkTo(at: Vector3?)
	if at and goal and flat(at, goal) < N.retarget then
		return
	end
	goal = at
end

-- what he turns to once he's standing still
function TutorialNpc.look(at: Vector3?)
	lookAt = at
end

-- a one-shot gesture: "wave" | "point" | "cheer"
function TutorialNpc.gesture(name: string)
	local tr = tracks[name]
	if not tr then
		return
	end
	if gestureTrack and gestureTrack ~= tr then
		gestureTrack:Stop(0.15)
	end
	gestureTrack = tr
	tr:Play(0.15)
end

-- one frame: fly toward the goal (fast to catch up, a poof over if far behind), stand on the ground
-- or hover over what's in the way, lean into the flight, turn toward where he's going or what he's
-- looking at
function TutorialNpc.step(dt: number)
	if not model or not root then
		return
	end
	dt = math.min(dt, 0.1) -- a hitch never flings him
	local want = 0
	local dir: Vector3? = nil
	local dist = 0
	if goal and not leaving then
		local to = Vector3.new(goal.X - pos.X, 0, goal.Z - pos.Z)
		dist = to.Magnitude
		if dist > N.teleport then
			burst() -- a poof where he was...
			pos = Vector3.new(goal.X, groundY(goal), goal.Z)
			feetY, speed = pos.Y, 0
			place()
			burst() -- ...and one where he lands
		elseif dist > N.arrive then
			want = if dist > N.runFrom then N.runSpeed else N.walkSpeed
			dir = to.Unit
		end
	end
	speed += (want - speed) * math.min(1, N.accel * dt)
	if dir then
		-- a little start-up speed, so he never creeps for the first frames
		local nextPos = pos + dir * math.min(math.max(speed, N.walkSpeed * 0.3) * dt, dist)
		pos = Vector3.new(nextPos.X, groundY(nextPos), nextPos.Z)
		turnToward(yawTo(dir), N.turnRate * dt)
	else
		pos = Vector3.new(pos.X, groundY(pos), pos.Z)
		if lookAt then
			local d = Vector3.new(lookAt.X - pos.X, 0, lookAt.Z - pos.Z)
			if d.Magnitude > 0.5 then
				turnToward(yawTo(d), N.turnRate * 0.6 * dt)
			end
		end
	end
	-- how high: on the ground standing still; hovering while moving, over anything up to clearMax
	-- tall under him or just ahead (fences, posts, rocks); jetting off at the end
	local moving = want > 0
	local target = pos.Y
	if leaving then
		target = pos.Y + N.leaveRise
	else
		local over = surface(pos, pos.Y + N.clearMax, N.clearMax + 1)
		if moving and dir then
			local ahead = surface(pos + dir * N.lookAhead, pos.Y + N.clearMax, N.clearMax + 1)
			over = math.max(over or pos.Y, ahead or pos.Y)
			target = math.max(pos.Y, over :: number) + (if want >= N.runSpeed then N.hoverRun else N.hoverWalk)
		elseif over and over > pos.Y + 0.5 then
			target = over + N.hoverWalk -- stopped over a fence or a prop: he hovers over it, never sinks into it
		end
	end
	-- coming down from high up (his drop from the sky, off a tall prop) is slower: a landing, not a fall
	local rate = if leaving then N.leaveRate elseif feetY - target > 2 then N.dropRate else N.heightRate
	feetY += (target - feetY) * math.min(1, rate * dt)
	local airborne = leaving or moving or target > pos.Y + 0.1 or feetY - target > 0.3
	setJets(airborne)
	-- lean into a fast flight, stand up straight when he stops
	local wantLean = if moving then N.lean * math.clamp(speed / N.runSpeed, 0, 1) else 0
	lean += (wantLean - lean) * math.min(1, 6 * dt)
	place()
end

-- his face on the tutorial card: a still copy in a ViewportFrame, framed on his head
function TutorialNpc.portrait(vp: ViewportFrame): boolean
	local t = template()
	if not t then
		return false
	end
	local m = t:Clone()
	local head = m:FindFirstChild("Head") :: BasePart?
	local r = m.PrimaryPart
	if not head or not r then
		m:Destroy()
		return false
	end
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
		end
	end
	m.Parent = vp
	local cam = Instance.new("Camera")
	cam.FieldOfView = N.portraitFov
	local target = head.Position + Vector3.new(0, head.Size.Y * 0.3, 0) -- a little up: the hat is half his look
	cam.CFrame = CFrame.lookAt(target + r.CFrame.LookVector * N.portraitDistance + r.CFrame.RightVector * 0.6 + Vector3.new(0, 0.2, 0), target)
	cam.Parent = vp
	vp.CurrentCamera = cam
	return true
end

-- the player's own spot, for him to stand beside
function TutorialNpc.myRoot(): BasePart?
	local c = me.Character
	return c and c:FindFirstChild("HumanoidRootPart") :: BasePart?
end

return TutorialNpc
