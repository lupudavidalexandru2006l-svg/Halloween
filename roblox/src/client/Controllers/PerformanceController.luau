--!strict
-- PerformanceController (owner 2026-11-15: "optimize for phone players, it has to work on a crappy phone").
-- Low graphics (the Settings switch) now also turns off, on this screen only: the post effects (bloom,
-- depth of field, sun rays), the map's decorative lights and its decorative particles. Shadows stay with
-- SettingsController. Things the game needs (the ray, the shows, the HUD) are never touched.
-- Auto: on a touch device that can't hold Config.performance.autoLowFps for a few seconds, low graphics
-- switches itself on once per session, with a banner. If the player turns it off again, that stays.

local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Theme = require(ReplicatedStorage.Shared.Theme)
local SettingsController = require(script.Parent.SettingsController)
local InputController = require(script.Parent.InputController)

local PerformanceController = {}
local PF = Config.performance
local low = false
-- what we switched off, so switching back restores exactly the map's own values
local turnedOff: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: any

local function decorative(d: Instance): boolean
	return (d:IsA("Light") or d:IsA("ParticleEmitter")) and d:IsDescendantOf(workspace.Map)
end

local function dim(d: Instance)
	if low and decorative(d) and (d :: any).Enabled then
		(d :: any).Enabled = false
		turnedOff[d] = true
	end
end

local function apply(on: boolean)
	if on == low then
		return
	end
	low = on
	for _, e in Lighting:GetChildren() do
		if e:IsA("BloomEffect") or e:IsA("DepthOfFieldEffect") or e:IsA("SunRaysEffect") then
			if on and e.Enabled then
				e.Enabled = false
				turnedOff[e] = true
			elseif not on and turnedOff[e] then
				e.Enabled = true
				turnedOff[e] = nil
			end
		end
	end
	local map = workspace:FindFirstChild("Map")
	if not map then
		return
	end
	if on then
		for i, d in map:GetDescendants() do
			dim(d)
			if i % 4000 == 0 then
				task.wait() -- spread over frames on a slow phone
			end
		end
	else
		for d in turnedOff do
			if d:IsA("Light") or d:IsA("ParticleEmitter") then
				(d :: any).Enabled = true
				turnedOff[d] = nil
			end
		end
	end
end

-- touch only: average frame rate over a window; too slow = low graphics on, once per session
local function watchFps()
	local autoDone = false
	local frames, since = 0, os.clock()
	local startAt = os.clock() + PF.settleSeconds -- loading hitches don't count
	RunService.Heartbeat:Connect(function()
		if autoDone then
			return
		end
		local now = os.clock()
		if now < startAt then
			frames, since = 0, now
			return
		end
		frames += 1
		if now - since >= PF.windowSeconds then
			local fps = frames / (now - since)
			frames, since = 0, now
			if InputController.device() == "touch" and fps < PF.autoLowFps and SettingsController.get("lowGraphics") ~= true then
				autoDone = true
				SettingsController.set("lowGraphics", true)
				local ok, Hud = pcall(require, script.Parent.HudController)
				if ok then
					(Hud :: any).banner("Low graphics on for a smoother game", Theme.info)
				end
			end
		end
	end)
end

-- the leaderboards (owner 2026-11-16: "the leaderboard can load only if you are close to it, like 20 studs"):
-- each board's SurfaceGui (tag LeaderboardGui) is drawn only while your character is within
-- Config.leaderboards.loadRange studs of the board; far off it costs nothing to draw
local function watchBoards()
	local CollectionService = game:GetService("CollectionService")
	local me = game:GetService("Players").LocalPlayer
	task.spawn(function()
		while true do
			local c = me.Character
			local hrp = c and c:FindFirstChild("HumanoidRootPart") :: BasePart?
			for _, g in CollectionService:GetTagged("LeaderboardGui") do
				local sg = g :: SurfaceGui
				local board = sg.Parent
				local near = false
				if hrp and board and board:IsA("BasePart") then
					local off = board.CFrame:PointToObjectSpace(hrp.Position)
					-- distance to the board's face (its size counts, so the edge of a wide board is near too)
					local h = board.Size / 2
					local d = Vector3.new(math.max(0, math.abs(off.X) - h.X), math.max(0, math.abs(off.Y) - h.Y), math.max(0, math.abs(off.Z) - h.Z))
					near = d.Magnitude <= Config.leaderboards.loadRange
				end
				if sg.Enabled ~= near then
					sg.Enabled = near
				end
			end
			task.wait(0.4)
		end
	end)
end

function PerformanceController.Init() end

function PerformanceController.Start()
	SettingsController.Changed:Connect(function()
		task.spawn(apply, SettingsController.get("lowGraphics") == true)
	end)
	task.spawn(apply, SettingsController.get("lowGraphics") == true)
	-- streamed-in parts of the map arrive later: dim their lights and particles too
	local map = workspace:WaitForChild("Map", 30)
	if map then
		map.DescendantAdded:Connect(function(d)
			if low and (d:IsA("Light") or d:IsA("ParticleEmitter")) then
				task.defer(dim, d)
			end
		end)
	end
	watchFps()
	watchBoards()
end

return PerformanceController
