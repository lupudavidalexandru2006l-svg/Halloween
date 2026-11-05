--!strict
-- EffectsController: bursts (freeze, bank), the light pillar over a pen when someone banks a
-- Legendary or better, and Big Chill snow. Low graphics halves the particles; reduced motion keeps
-- bursts small and the pillar still.
-- Round 4 phase 3: the moment a cube shuts. At 100% the cube snaps shut at the pet's spot (a puff of
-- frost; a flash-freeze adds a quick glow and a light "tink"), the gun's finishing touch plays
-- (spikes, an aurora shimmer or a star sparkle) and the cube flies into your hands. Legendary and up
-- get a show instead (Show module), built from the pieces here (pillar, burst, rays, flash).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Theme = require(ReplicatedStorage.Shared.Theme)
local WorldRules = require(ReplicatedStorage.Shared.WorldRules)
local PetDefs = require(ReplicatedStorage.Shared.PetDefs)
local State = require(script.Parent.State)
local SettingsController = require(script.Parent.SettingsController)
local SoundController = require(script.Parent.SoundController)
local PetVisuals = require(script.Parent.PetVisuals)

local EffectsController = {}
local E = Config.effects
local F = Config.show.freeze
local snow: Part? = nil
local flashFrame: Frame? = nil
local meshes: Instance? = nil

local function reduced(): boolean
	return SettingsController.get("reducedMotion") == true
end

-- reduced motion halves every look timing (Animation Rules 1)
function EffectsController.time(seconds: number): number
	return seconds * (if reduced() then 0.5 else 1)
end

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

-- a glowing shape for an effect (a scenery mesh when it's there, else a plain part)
local function glow(size: Vector3, color: Color3, mesh: string?): BasePart
	local template = mesh and meshes and meshes:FindFirstChild(mesh)
	local p: BasePart = if template and template:IsA("MeshPart") then template:Clone() else Instance.new("Part")
	p.Size = size
	p.Color = color
	p.Material = Enum.Material.Neon
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Parent = workspace
	return p
end

local function amount(n: number): number
	local f = if SettingsController.get("lowGraphics") then 0.5 else 1
	f *= if reduced() then 0.5 else 1
	return math.max(1, math.floor(n * f))
end

function EffectsController.burst(pos: Vector3, color: Color3, count: number?)
	local p = anchor(pos + Vector3.new(0, 2, 0))
	local e = Instance.new("ParticleEmitter")
	e.Color = ColorSequence.new(color)
	e.Speed = NumberRange.new(6, 12)
	e.Lifetime = NumberRange.new(0.4, 0.8)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Rate = 0
	e.Parent = p
	e:Emit(amount(count or E.burstParts))
	task.delay(1.5, function()
		p:Destroy()
	end)
end

-- a soft cloud of frost where the cube shut
local function puff(pos: Vector3, count: number)
	local p = anchor(pos)
	local e = Instance.new("ParticleEmitter")
	e.Color = ColorSequence.new(Theme.fx.frost)
	e.LightEmission = 0.4
	e.Transparency = NumberSequence.new(0.2, 1)
	e.Size = NumberSequence.new(0.6, 1.6)
	e.Speed = NumberRange.new(2, 5)
	e.Drag = 4
	e.Lifetime = NumberRange.new(0.5, 0.9)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Rate = 0
	e.Parent = p
	e:Emit(amount(count))
	task.delay(1.2, function()
		p:Destroy()
	end)
end

-- a light pillar in the tier's colour; rise > 0 grows it up from the ground first
function EffectsController.pillar(pos: Vector3, color: Color3, seconds: number?, rise: number?)
	local life = seconds or E.pillarSeconds
	local p = anchor(pos)
	p.Shape = Enum.PartType.Cylinder
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Transparency = 0.4
	local function place(h: number)
		p.Size = Vector3.new(math.max(0.1, h), 6, 6)
		p.CFrame = CFrame.new(pos + Vector3.new(0, h / 2, 0)) * CFrame.Angles(0, 0, math.rad(90))
	end
	if rise and rise > 0 then
		place(0.1)
		local t0 = os.clock()
		local conn: RBXScriptConnection
		conn = RunService.RenderStepped:Connect(function()
			local u = math.min(1, (os.clock() - t0) / rise)
			place(E.pillarHeight * (1 - (1 - u) ^ 2))
			if u >= 1 or not p.Parent then
				conn:Disconnect()
			end
		end)
	else
		place(E.pillarHeight)
	end
	if not reduced() then
		TweenService:Create(p, TweenInfo.new(life, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Transparency = 1 }):Play()
	end
	task.delay(life, function()
		p:Destroy()
	end)
end

-- light rays turning slowly round a point, fading out (Rare-and-up shows)
function EffectsController.rays(pos: Vector3, color: Color3, count: number, seconds: number)
	local parts: { BasePart } = {}
	for i = 1, count do
		local r = glow(Vector3.new(0.35, 0.35, 9), color, nil)
		r.Transparency = 0.35
		table.insert(parts, r)
	end
	local t0 = os.clock()
	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(function()
		local u = (os.clock() - t0) / seconds
		if u >= 1 then
			conn:Disconnect()
			for _, r in parts do
				r:Destroy()
			end
			return
		end
		local spin = if reduced() then 0 else u * 0.8
		for i, r in parts do
			local a = i * (2 * math.pi / count) + spin
			r.CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, a) * CFrame.new(0, 5, 0) * CFrame.Angles(math.pi / 2, 0, 0)
			r.Transparency = 0.35 + 0.65 * u
		end
	end)
end

-- one full-screen flash (a soft fade with reduced motion). Shows use one flash each, far under the
-- 3-per-second limit (Animation Rules 1).
function EffectsController.flash()
	local f = flashFrame
	if not f then
		return
	end
	local U = Config.show.ui
	f.BackgroundTransparency = if reduced() then U.softFlashAlpha else U.flashAlpha
	f.Visible = true
	local tw = TweenService:Create(f, TweenInfo.new(EffectsController.time(U.flashSeconds) * (if reduced() then 2 else 1)), { BackgroundTransparency = 1 })
	tw.Completed:Once(function()
		f.Visible = false
	end)
	tw:Play()
end

-- the gun's finishing touch round a cube that just shut (higher gun tiers)
function EffectsController.touch(kind: string, at: CFrame, size: number)
	local time = EffectsController.time(F.touchSeconds)
	local parts: { { part: BasePart, from: CFrame, to: CFrame, size: Vector3 } } = {}
	if kind == "spikes" then
		for i = 1, F.spikeCount do
			local a = i * (2 * math.pi / F.spikeCount)
			local base = at * CFrame.Angles(0, a, 0) * CFrame.new(0, size * 0.35, -size * 0.45) * CFrame.Angles(-0.6, 0, 0)
			local s = glow(Vector3.new(0.4, F.spikeHeight, 0.4), Theme.fx.crystal, "Cone")
			s.Material = Enum.Material.Glass
			s.Transparency = 0.1
			table.insert(parts, { part = s, from = base, to = base * CFrame.new(0, F.spikeHeight * 0.5, 0), size = s.Size })
		end
	elseif kind == "aurora" then
		for i = 1, F.auroraBands do
			local ring = glow(Vector3.new(size * 1.6, 0.12, size * 1.6), Theme.fx.aurora[(i - 1) % #Theme.fx.aurora + 1], "Ring")
			ring.Transparency = 0.3
			local from = at * CFrame.new(0, -size * 0.4 + i * 0.25, 0)
			table.insert(parts, { part = ring, from = from, to = from * CFrame.new(0, size * 0.9, 0) * CFrame.Angles(0, 2, 0), size = ring.Size })
		end
	elseif kind == "stars" then
		for i = 1, F.starCount do
			local a = i * (2 * math.pi / F.starCount)
			local s = glow(Vector3.new(0.35, 0.5, 0.35), Theme.fx.star, "Octa")
			table.insert(parts, { part = s, from = at, to = at * CFrame.Angles(0, a, 0) * CFrame.new(0, size * 0.4, -size * 1.1), size = s.Size })
		end
	end
	for _, p in parts do
		p.part.CFrame = p.from
		TweenService:Create(p.part, TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = p.to, Transparency = 1 }):Play()
		task.delay(time, function()
			p.part:Destroy()
		end)
	end
end

-- the cube I'm carrying for this freeze (it replicates with the freeze; wait a moment if needed)
function EffectsController.realCube(uid: any): BasePart?
	if typeof(uid) ~= "string" then
		return nil
	end
	local folder = workspace:FindFirstChild("Cubes")
	local t0 = os.clock()
	while os.clock() - t0 < 1 do
		if folder then
			for _, c in folder:GetChildren() do
				if c:GetAttribute("CubeUid") == uid and c:IsA("BasePart") then
					return c
				end
			end
		end
		task.wait()
		folder = folder or workspace:FindFirstChild("Cubes")
	end
	return nil
end

-- move the shown cube into your hands, then show the real one again
function EffectsController.flyHome(model: Model, real: BasePart?, seconds: number)
	local start = model:GetPivot()
	local t0 = os.clock()
	while true do
		local u = math.min(1, (os.clock() - t0) / math.max(0.01, seconds))
		local target = if real and real.Parent then real.CFrame else start
		model:PivotTo(start:Lerp(target, u * u))
		if u >= 1 then
			break
		end
		RunService.RenderStepped:Wait()
	end
	if real then
		real:SetAttribute("ShowHidden", nil)
	end
	model:Destroy()
end

-- where a cube that shut at a pet's spot sits (its bottom on the pet's ground)
function EffectsController.cubeAt(data: any, size: number): CFrame
	local def = PetDefs.get(data.key)
	local h = if def then PetDefs.sizeHeight[def.size] else 3
	local at: Vector3 = data.at
	return CFrame.new(at - Vector3.new(0, h / 2, 0) + Vector3.new(0, size / 2, 0))
end

-- the plain snap at 100% (every freeze without a show)
local function snap(data: any)
	local real = EffectsController.realCube(data.uid)
	local def = PetDefs.get(data.key)
	if not def then
		return
	end
	local size = if real then real.Size.X else PetDefs.cubeSize[def.size] * Config.carry.scale
	if real then
		real:SetAttribute("ShowHidden", true)
	end
	local model, cube = PetVisuals.frozenCube(data.key, size)
	if not model or not cube then
		if real then
			real:SetAttribute("ShowHidden", nil)
		end
		return
	end
	local at = EffectsController.cubeAt(data, size)
	model:PivotTo(at)
	local flash = data.style == "flash"
	cube.Size = Vector3.one * size * F.snapScale
	cube.Transparency = 0.9
	local snapTime = EffectsController.time(F.snapSeconds)
	TweenService:Create(cube, TweenInfo.new(snapTime, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = Vector3.one * size, Transparency = 0.45 }):Play()
	puff(at.Position, if flash then F.flashPuffParts else F.puffParts)
	-- the lock: one quick white glow as the ice shuts (owner 2026-11-05); a flash-freeze's is brighter
	-- and adds a light "tink"
	local g = glow(Vector3.one * size * 1.3, Theme.fx.flash, nil)
	g.Shape = Enum.PartType.Ball
	g.Transparency = if flash then (if reduced() then 0.75 else 0.35) else (if reduced() then 0.85 else 0.65)
	g.CFrame = at
	TweenService:Create(g, TweenInfo.new(snapTime * 1.5), { Transparency = 1, Size = Vector3.one * size * 1.8 }):Play()
	task.delay(snapTime * 1.5, function()
		g:Destroy()
	end)
	if flash then
		SoundController.play("tink")
	end
	if typeof(data.touch) == "string" then
		EffectsController.touch(data.touch, at, size)
	end
	task.wait(snapTime + EffectsController.time(0.12))
	EffectsController.flyHome(model, real, EffectsController.time(F.flySeconds))
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

function EffectsController.Init()
	local g = Instance.new("ScreenGui")
	g.Name = "Flash"
	g.IgnoreGuiInset = true
	g.ResetOnSpawn = false
	g.DisplayOrder = 20
	local f = Instance.new("Frame")
	f.Size = UDim2.fromScale(1, 1)
	f.BackgroundColor3 = Theme.fx.flash
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	f.Visible = false
	f.Parent = g
	g.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	flashFrame = f
end

function EffectsController.Start()
	meshes = ReplicatedStorage:FindFirstChild("SceneryMeshes")
	State.Notify:Connect(function(kind: string, data: any)
		if kind == "frozen" and typeof(data) == "table" and typeof(data.at) == "Vector3" then
			if not data.show then -- Legendary and up: the Show module plays it
				task.spawn(snap, data)
			end
		elseif kind == "banked" then
			local v = State.view
			if v and v.plot then
				local at = WorldRules.plotCenter(v.plot)
				EffectsController.burst(at, Theme.ice)
				EffectsController.burst(at, Theme.coin)
				-- Epic and up get the show in your own pen (prototype): a pillar in the tier's colour
				for _, b in data.banked do
					local def = PetDefs.get(b.key)
					if def and Config.tier(def.tier).rank >= E.showRank then
						EffectsController.pillar(at, Theme.tiers[def.tier] or Theme.coin)
						EffectsController.burst(at, Theme.tiers[def.tier] or Theme.coin)
					end
				end
			end
		elseif kind == "melted" then
			local c = Players.LocalPlayer.Character
			local root = c and c:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root then
				EffectsController.burst(root.Position, Theme.ice)
			end
		elseif kind == "zoneUnlocked" then
			EffectsController.burst(Vector3.new(0, 6, WorldRules.gateZ(if typeof(data.zone) == "number" then data.zone else 2) or 0), Theme.go)
		elseif kind == "giftClaimed" then
			EffectsController.burst(Config.world.giftBox, Theme.coin)
		elseif kind == "bigWin" and typeof(data.plot) == "number" then
			EffectsController.pillar(WorldRules.plotCenter(data.plot), Theme.tiers[data.tier] or Theme.coin)
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
