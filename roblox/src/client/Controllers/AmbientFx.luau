--!strict
-- AmbientFx (owner 2026-11-20: "add small things that improve the scores ... UI or decor or art"; QA 2026-11-20
-- counted 0 / 2 / 9 effects on islands 1 / 2 / 4, the plainest). Gentle toon weather over each island's
-- floor, client-only, from Roblox's own particle textures (no uploads), no lights (World Rules: lights are
-- rationed). An island's effect only runs while the camera is on it or next to it; Low graphics turns them
-- all off and Reduced motion slows them. Numbers in Config.ambientFx.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local WorldRules = require(ReplicatedStorage.Shared.WorldRules)
local SettingsController = require(script.Parent.SettingsController)

local AmbientFx = {}

type Fx = { zone: number, part: Part, emitter: ParticleEmitter, rate: number, speed: NumberRange }
local list: { Fx } = {}

local function build(zone: number, spec: any): Fx?
	local section = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("Section" .. zone)
	local floor = section and section:FindFirstChild("Floor") :: BasePart?
	if not floor then
		return nil
	end
	local p = Instance.new("Part")
	p.Name = "AmbientFx" .. zone
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	p.Transparency = 1
	p.Size = Vector3.new(floor.Size.X * 0.9, 1, floor.Size.Z * 0.95)
	p.CFrame = CFrame.new(floor.Position.X, floor.Position.Y + spec.height, floor.Position.Z)
	local e = Instance.new("ParticleEmitter")
	e.Texture = spec.texture
	e.Shape = Enum.ParticleEmitterShape.Box
	e.ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward
	e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	e.EmissionDirection = spec.direction
	e.Color = ColorSequence.new(spec.color[1], spec.color[2])
	e.LightEmission = spec.light
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, spec.size[1]), NumberSequenceKeypoint.new(0.5, spec.size[2]), NumberSequenceKeypoint.new(1, spec.size[1] * 0.6) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.15, spec.alpha), NumberSequenceKeypoint.new(0.8, spec.alpha), NumberSequenceKeypoint.new(1, 1) })
	e.Lifetime = NumberRange.new(spec.life[1], spec.life[2])
	e.Speed = NumberRange.new(spec.speed[1], spec.speed[2])
	e.SpreadAngle = Vector2.new(spec.spread, spec.spread)
	e.Acceleration = spec.drift
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-spec.spin, spec.spin)
	e.Rate = 0
	e.Parent = p
	p.Parent = workspace
	return { zone = zone, part = p, emitter = e, rate = spec.rate, speed = e.Speed }
end

local function sync()
	local cam = workspace.CurrentCamera
	local here = if cam then WorldRules.zoneAt(cam.CFrame.Position) else -1
	local low = SettingsController.get("lowGraphics") == true
	local calm = SettingsController.get("reducedMotion") == true
	for _, fx in list do
		local near = here >= 1 and math.abs(fx.zone - here) <= 1
		local rate = if near and not low then fx.rate else 0
		if fx.emitter.Rate ~= rate then
			fx.emitter.Rate = rate
		end
		local k = if calm then 0.5 else 1
		fx.emitter.TimeScale = k
	end
end

function AmbientFx.Init() end

function AmbientFx.Start()
	local A = (Config :: any).ambientFx
	if not A then
		return
	end
	-- the map streams in (StreamingEnabled), so an island's floor may not be here yet: keep trying until it is
	local built: { [string]: boolean } = {}
	while true do
		for zone, spec in A.islands do
			if not built[zone] then
				local ok, fx = pcall(build, tonumber(zone) :: number, spec)
				if ok and fx then
					built[zone] = true
					table.insert(list, fx)
				end
			end
		end
		pcall(sync)
		task.wait(A.checkEvery)
	end
end

return AmbientFx
