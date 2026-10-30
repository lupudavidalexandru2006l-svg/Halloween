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
end

function CameraController.Start()
	apply()
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(apply)
end

return CameraController
