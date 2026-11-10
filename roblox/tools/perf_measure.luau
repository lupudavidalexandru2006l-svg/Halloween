-- Performance snapshot for Ice Ray for Pets (PERF-AUDIT-2026-11-09.md). Run in a playtest on the
-- CLIENT datamodel (Studio MCP execute_luau, datamodel_type "Client"). It parks the camera at fixed
-- spots for a moment, averages the engine's render counters over 60 frames at each, then hands the
-- camera back. It changes nothing else.
local Stats = game:GetService("Stats")
local RunService = game:GetService("RunService")

local SPOTS = {
	{ "hub", Vector3.new(0, 40, -10), Vector3.new(0, 3, -80) },
	{ "pans", Vector3.new(-48, 30, -40), Vector3.new(-48, 3, -90) },
	{ "tunnel", Vector3.new(0, 14, 330), Vector3.new(0, 6, 380) },
}
local FRAMES = 60

local out = {}
local function frames(n: number)
	for _ = 1, n do
		RunService.RenderStepped:Wait()
	end
end
local function read()
	local a = { sd = 0, st = 0, hd = 0, ht = 0, cpu = 0, ft = 0 }
	for _ = 1, FRAMES do
		frames(1)
		a.sd += Stats.SceneDrawcallCount
		a.st += Stats.SceneTriangleCount
		a.hd += Stats.ShadowsDrawcallCount
		a.ht += Stats.ShadowsTriangleCount
		a.cpu += Stats.RenderCPUFrameTime
		a.ft += Stats.FrameTime
	end
	for k, v in a do
		a[k] = v / FRAMES
	end
	return a
end

local cam = workspace.CurrentCamera
local oldType = cam.CameraType
local ok, err = pcall(function()
	for _, s in SPOTS do
		local cf = CFrame.lookAt(s[2], s[3])
		cam.CameraType = Enum.CameraType.Scriptable
		local conn = RunService.RenderStepped:Connect(function()
			cam.CFrame = cf
		end)
		frames(45)
		local a = read()
		conn:Disconnect()
		table.insert(out, string.format("%-7s scene dc %4.0f tris %7.0f | shadow dc %4.0f tris %7.0f | renderCPU %5.2f ms | frame %5.1f ms",
			s[1], a.sd, a.st, a.hd, a.ht, a.cpu * 1000, a.ft * 1000))
	end
end)
cam.CameraType = oldType
if not ok then
	table.insert(out, "ERROR " .. tostring(err))
end

local map = workspace:FindFirstChild("Map")
table.insert(out, string.format("instances: workspace %d | Map %d | client total %d | primitives %d | moving %d",
	#workspace:GetDescendants(), map and #map:GetDescendants() or 0, Stats.InstanceCount, Stats.PrimitivesCount, Stats.MovingPrimitivesCount))
return table.concat(out, "\n")
