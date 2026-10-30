--!strict
-- CameraController: the only script that touches the camera. Roblox's own follow camera does the
-- moving (players expect it on every device); this owns the field of view and zoom limits, and widens
-- the view a little while you carry cubes so the run home feels fast (prototype: the camera rises).

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)

local CameraController = {}
local player = Players.LocalPlayer
local carrying = false

local function apply()
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	local fov = if carrying then Config.camera.carryFov else Config.camera.fov
	TweenService:Create(cam, TweenInfo.new(Config.camera.fovSeconds), { FieldOfView = fov }):Play()
end

-- EffectsController says when cubes appear on or leave the player's back
function CameraController.setCarrying(on: boolean)
	if on ~= carrying then
		carrying = on
		apply()
	end
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

function CameraController.Start()
	apply()
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(apply)
	player.CharacterAdded:Connect(frame)
	if player.Character then
		task.spawn(frame, player.Character)
	end
end

return CameraController
