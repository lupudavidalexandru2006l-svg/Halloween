--!strict
-- CameraController: the only script that touches the camera. Roblox's own follow camera does the
-- moving (players expect it on every device); this owns the field of view and zoom limits, and widens
-- the view a little while you carry cubes so the run home feels fast (prototype: the camera rises).
-- It also plays the ray's short camera kicks (fire, lock) and tightens the view while you hold the ray
-- on a target (RayController asks; Config.camera.kicks / pushFov). Kicks are undone before Roblox's
-- camera updates each frame, so they never add up into where the camera looks.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local SettingsController = require(script.Parent.SettingsController)

local CameraController = {}
local player = Players.LocalPlayer
local carrying = false
local push = 0 -- 0-1: how far the view is tightened for the ray's hold
local fovNow: number? = nil
type Kick = { name: string, t0: number, scale: number }
local kicks: { Kick } = {}
local applied: CFrame? = nil -- the kick offset put on the camera this frame (taken off before the next update)

local function reduced(): boolean
	return SettingsController.get("reducedMotion") == true
end

local function targetFov(): number
	local C = Config.camera
	return (if carrying then C.carryFov else C.fov) + C.pushFov * push
end

-- EffectsController says when cubes appear on or leave the player's back
function CameraController.setCarrying(on: boolean)
	carrying = on
end

-- RayController: how hard you're pushing the ray into a target (0 = not shooting)
function CameraController.setPush(amount: number)
	push = if reduced() then 0 else math.clamp(amount, 0, 1)
end

-- a short kick ("fire", "lock"); scale grows it with the pet's tier
function CameraController.kick(name: string, scale: number?)
	if reduced() or not Config.camera.kicks[name] then
		return
	end
	table.insert(kicks, { name = name, t0 = os.clock(), scale = scale or 1 })
end

-- shows borrow the camera and hand it back (Animation Rules 6); only one borrower at a time
local borrowed: { cframe: CFrame }? = nil
function CameraController.borrow(): Camera?
	local cam = workspace.CurrentCamera
	if not cam or borrowed then
		return nil
	end
	if applied then -- hand it over clean
		cam.CFrame *= (applied :: CFrame):Inverse()
		applied = nil
	end
	table.clear(kicks)
	borrowed = { cframe = cam.CFrame }
	cam.CameraType = Enum.CameraType.Scriptable
	return cam
end

function CameraController.giveBack()
	local cam = workspace.CurrentCamera
	if not borrowed then
		return
	end
	if cam then
		cam.CameraType = Enum.CameraType.Custom
	end
	borrowed = nil
	fovNow = nil -- glide back from whatever the show left
end

-- where the camera was when the show borrowed it (the show flies back there before handing it over)
function CameraController.homeCFrame(): CFrame?
	return if borrowed then borrowed.cframe else nil
end

function CameraController.Init()
	player.CameraMinZoomDistance = Config.camera.minZoom
	player.CameraMaxZoomDistance = Config.camera.maxZoom
	-- trees between the camera and you fade to see-through: StarterPlayer.DevCameraOcclusionMode is
	-- Invisicam, set in default.project.json (scripts may not set it)
end

-- on spawn: the prototype's framing (high and behind, looking ahead); Roblox's follow camera keeps
-- that angle and distance until the player turns or zooms it
local function frame(character: Model)
	local root = character:WaitForChild("HumanoidRootPart", 5) :: BasePart?
	local cam = workspace.CurrentCamera
	if not root or not cam then
		return
	end
	-- Roblox's camera keeps its own zoom, so push the distance out with the minimum zoom for a moment
	local C = Config.camera
	local distance = math.sqrt(C.startHeight ^ 2 + C.startBack ^ 2)
	player.CameraMinZoomDistance = math.min(distance, C.maxZoom)
	task.wait(C.frameSettleSeconds)
	local look = (root.CFrame.LookVector * Vector3.new(1, 0, 1)).Unit
	cam.CFrame = CFrame.lookAt(root.Position - look * C.startBack + Vector3.new(0, C.startHeight, 0), root.Position + look * C.startLookAhead)
	task.wait(C.frameSettleSeconds)
	player.CameraMinZoomDistance = C.minZoom
end

-- the kicks still running this frame, added up: A * e^(-t/decay) * cos(2*pi*hz*t)
local function kickOffset(now: number): CFrame?
	if #kicks == 0 then
		return nil
	end
	local pitch, roll, back = 0, 0, 0
	for i = #kicks, 1, -1 do
		local k = kicks[i]
		local K = Config.camera.kicks[k.name]
		local t = now - k.t0
		if t >= K.seconds then
			table.remove(kicks, i)
			continue
		end
		local wave = math.exp(-t / K.decay) * math.cos(2 * math.pi * K.hz * t) * k.scale
		pitch += K.pitch * wave
		roll += K.roll * wave
		back += K.back * wave
	end
	return CFrame.new(0, 0, back) * CFrame.Angles(math.rad(pitch), 0, math.rad(roll))
end

function CameraController.Start()
	player.CharacterAdded:Connect(frame)
	if player.Character then
		task.spawn(frame, player.Character)
	end
	-- before Roblox's camera: take last frame's kick off, so the camera reads its own direction
	RunService:BindToRenderStep("RayKickUndo", Enum.RenderPriority.Camera.Value - 1, function()
		local cam = workspace.CurrentCamera
		if applied and cam and not borrowed then
			cam.CFrame *= (applied :: CFrame):Inverse()
		end
		applied = nil
	end)
	-- after it: the field of view glides to its target, then this frame's kick goes on
	RunService:BindToRenderStep("RayKickApply", Enum.RenderPriority.Camera.Value + 1, function(dt: number)
		local cam = workspace.CurrentCamera
		if not cam or borrowed then
			return
		end
		local want = targetFov()
		local f = fovNow or cam.FieldOfView
		f += (want - f) * math.min(1, dt * 3 / Config.camera.fovSeconds)
		fovNow = f
		cam.FieldOfView = f
		local off = kickOffset(os.clock())
		if off then
			cam.CFrame *= off
			applied = off
		end
	end)
end

return CameraController
