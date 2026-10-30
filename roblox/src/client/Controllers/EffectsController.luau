--!strict
-- EffectsController: bursts (freeze, bank), the light pillar over a pen when someone banks a
-- Legendary or better, and Big Chill snow. Low graphics halves the particles; reduced motion keeps
-- bursts small and the pillar still.

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Theme = require(ReplicatedStorage.Shared.Theme)
local WorldRules = require(ReplicatedStorage.Shared.WorldRules)
local State = require(script.Parent.State)
local SettingsController = require(script.Parent.SettingsController)

local EffectsController = {}
local E = Config.effects
local snow: Part? = nil

local function anchor(pos: Vector3): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Transparency = 1
	p.Size = Vector3.new(1, 1, 1)
	p.Position = pos
	p.Parent = workspace
	return p
end

local function amount(n: number): number
	local f = if SettingsController.get("lowGraphics") then 0.5 else 1
	f *= if SettingsController.get("reducedMotion") then 0.5 else 1
	return math.max(1, math.floor(n * f))
end

function EffectsController.burst(pos: Vector3, color: Color3)
	local p = anchor(pos + Vector3.new(0, 2, 0))
	local e = Instance.new("ParticleEmitter")
	e.Color = ColorSequence.new(color)
	e.Speed = NumberRange.new(6, 12)
	e.Lifetime = NumberRange.new(0.4, 0.8)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Rate = 0
	e.Parent = p
	e:Emit(amount(E.burstParts))
	task.delay(1.5, function()
		p:Destroy()
	end)
end

local function pillar(pos: Vector3, color: Color3)
	local p = anchor(pos + Vector3.new(0, E.pillarHeight / 2, 0))
	p.Shape = Enum.PartType.Cylinder
	p.Size = Vector3.new(E.pillarHeight, 6, 6)
	p.CFrame = CFrame.new(p.Position) * CFrame.Angles(0, 0, math.rad(90))
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Transparency = 0.4
	if not SettingsController.get("reducedMotion") then
		TweenService:Create(p, TweenInfo.new(E.pillarSeconds), { Transparency = 1 }):Play()
	end
	task.delay(E.pillarSeconds, function()
		p:Destroy()
	end)
end

local function setSnow(on: boolean)
	if on and not snow then
		local p = anchor(Vector3.zero)
		p.Size = Vector3.new(80, 1, 80)
		local e = Instance.new("ParticleEmitter")
		e.Color = ColorSequence.new(Theme.snow)
		e.Rate = amount(E.snowRate)
		e.Speed = NumberRange.new(4, 8)
		e.Lifetime = NumberRange.new(4, 6)
		e.EmissionDirection = Enum.NormalId.Bottom
		e.Parent = p
		snow = p
	elseif not on and snow then
		snow:Destroy()
		snow = nil
	end
end

function EffectsController.Init() end

function EffectsController.Start()
	State.Notify:Connect(function(kind: string, data: any)
		if kind == "frozen" and typeof(data.at) == "Vector3" then
			EffectsController.burst(data.at, Theme.ice)
		elseif kind == "banked" then
			local v = State.view
			if v and v.plot then
				EffectsController.burst(WorldRules.plotCenter(v.plot), Theme.coin)
			end
		elseif kind == "bigWin" and typeof(data.plot) == "number" then
			pillar(WorldRules.plotCenter(data.plot), Theme.tiers[data.tier] or Theme.coin)
		elseif kind == "chillStart" then
			setSnow(true)
		elseif kind == "chillEnd" then
			setSnow(false)
		end
	end)
	-- snow follows the camera; it also starts for a player who joins mid-Chill
	RunService.RenderStepped:Connect(function()
		local untilAt = workspace:GetAttribute("ChillUntil")
		local chill = typeof(untilAt) == "number" and untilAt > workspace:GetServerTimeNow()
		if chill ~= (snow ~= nil) then
			setSnow(chill)
		end
		local cam = workspace.CurrentCamera
		if snow and cam then
			snow.Position = cam.CFrame.Position + Vector3.new(0, 25, 0)
		end
	end)
end

return EffectsController
