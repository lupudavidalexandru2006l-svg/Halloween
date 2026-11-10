--!strict
-- TutorialNpc: Ranger Bo in the world, driven by TutorialController (no Init/Start of its own).
-- Each player gets a local copy of the model the server built (ReplicatedStorage.TutorialGuide), so a
-- full server never has six guides crowding the plaza and each one only follows its own player.
-- Bo glides over the ground like the pets do (an anchored root, a ground ray each frame), plays
-- Roblox's own R15 animations (idle, walk, run, wave, point, cheer) and turns to what he's looking at.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Theme = require(ReplicatedStorage.Shared.Theme)
local Ui = require(script.Parent.Parent.Lib.Ui)

local TutorialNpc = {}
local T = Config.tutorial
local N = T.npc
local me = Players.LocalPlayer

local model: Model? = nil
local root: BasePart? = nil
local hip = 3
local tracks: { [string]: AnimationTrack } = {}
local pos = Vector3.zero -- where he stands (ground level)
local yaw = 0
local goal: Vector3? = nil
local lookAt: Vector3? = nil
local moving: string? = nil -- "walk" | "run" | nil
local gestureTrack: AnimationTrack? = nil
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.RespectCanCollide = true

local function template(): Model?
	local t = ReplicatedStorage:WaitForChild(T.modelName, 15)
	return if t and t:IsA("Model") then t else nil
end

local function groundY(at: Vector3): number
	local exclude: { Instance } = {}
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(exclude, p.Character)
		end
	end
	if model then
		table.insert(exclude, model)
	end
	rayParams.FilterDescendantsInstances = exclude
	-- from a little above his feet, so a booth roof or an awning over him is never mistaken for the ground
	local hit = workspace:Raycast(Vector3.new(at.X, at.Y + N.stepUp, at.Z), Vector3.new(0, -N.groundRay, 0), rayParams)
	return if hit then hit.Position.Y else at.Y
end

local function yawTo(dir: Vector3): number
	return math.atan2(-dir.X, -dir.Z) -- CFrame.Angles(0, yaw, 0) looks down -Z
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
		root.CFrame = CFrame.new(pos.X, pos.Y + hip, pos.Z) * CFrame.Angles(0, yaw, 0)
	end
end

-- Bo appears at `at`, facing `face` (the player); false if the server couldn't build him
function TutorialNpc.spawn(at: Vector3, face: Vector3?): boolean
	if model then
		return true
	end
	local t = template()
	if not t then
		return false
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
	yaw = if face then yawTo(Vector3.new(face.X - at.X, 0, face.Z - at.Z)) else 0
	goal, lookAt, moving = nil, nil, nil
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
	for name, spec in { idle = { true, Enum.AnimationPriority.Idle }, walk = { true, Enum.AnimationPriority.Movement },
		run = { true, Enum.AnimationPriority.Movement }, wave = { false, Enum.AnimationPriority.Action },
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
	if model then
		model:Destroy()
	end
	model, root = nil, nil
end

function TutorialNpc.alive(): boolean
	return model ~= nil
end

function TutorialNpc.position(): Vector3?
	return if model then pos else nil
end

-- where he walks to (nil = stay put)
function TutorialNpc.walkTo(at: Vector3?)
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

local function setMoving(kind: string?, speed: number)
	if kind ~= moving then
		for _, k in { "walk", "run" } do
			local tr = tracks[k]
			if tr then
				if k == kind then
					tr:Play(0.2)
				else
					tr:Stop(0.2)
				end
			end
		end
		moving = kind
	end
	local tr = kind and tracks[kind]
	if tr then
		tr:AdjustSpeed(speed / (if kind == "run" then N.runSpeed else N.walkSpeed))
	end
end

-- one frame: walk toward the goal (running to catch up, snapping over if far behind), stand on the
-- ground, and turn smoothly toward where he's going or what he's looking at
function TutorialNpc.step(dt: number)
	if not model or not root then
		return
	end
	local speed = 0
	if goal then
		local to = Vector3.new(goal.X - pos.X, 0, goal.Z - pos.Z)
		local dist = to.Magnitude
		if dist > N.teleport then
			pos = Vector3.new(goal.X, groundY(goal), goal.Z)
		elseif dist > N.arrive then
			speed = if dist > N.runFrom then N.runSpeed else N.walkSpeed
			local stepLen = math.min(dist, speed * dt)
			local nextPos = pos + to.Unit * stepLen
			pos = Vector3.new(nextPos.X, groundY(nextPos), nextPos.Z)
			yaw = yaw + math.atan2(math.sin(yawTo(to) - yaw), math.cos(yawTo(to) - yaw)) * math.min(1, N.turnRate * dt)
		end
	end
	if speed == 0 and lookAt then
		local dir = Vector3.new(lookAt.X - pos.X, 0, lookAt.Z - pos.Z)
		if dir.Magnitude > 0.5 then
			local want = yawTo(dir)
			yaw = yaw + math.atan2(math.sin(want - yaw), math.cos(want - yaw)) * math.min(1, N.turnRate * 0.6 * dt)
		end
	end
	setMoving(if speed == 0 then nil elseif speed >= N.runSpeed then "run" else "walk", speed)
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
	local target = head.Position + Vector3.new(0, head.Size.Y * 0.15, 0)
	cam.CFrame = CFrame.lookAt(target + r.CFrame.LookVector * N.portraitDistance + Vector3.new(0, 0.3, 0), target)
	cam.Parent = vp
	vp.CurrentCamera = cam
	return true
end

-- the player's own spot, for Bo to walk beside
function TutorialNpc.myRoot(): BasePart?
	local c = me.Character
	return c and c:FindFirstChild("HumanoidRootPart") :: BasePart?
end

return TutorialNpc
