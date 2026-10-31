--!strict
-- GuideController: the world teaches (prototype client.js). The only owner of three local guides:
--  - a green chevron on the ground, 6.5 studs out: to the nearest pet while you own fewer than 3,
--    home to your pen while you carry a cube (hidden once you're close)
--  - a small diamond over the nearest pet you can't reach yet (hands free, arrow hidden)
--  - a soft green light pillar over your pen while you carry
-- Everything is local; nothing here changes the game.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Theme = require(ReplicatedStorage.Shared.Theme)
local WorldRules = require(ReplicatedStorage.Shared.WorldRules)
local State = require(script.Parent.State)
local SettingsController = require(script.Parent.SettingsController)

local GuideController = {}
local G = Config.guide
local me = Players.LocalPlayer
local folder: Folder
local arrow: Model
local marker: BasePart
local beacon: BasePart

local function part(size: Vector3, color: Color3, parent: Instance, class: string?): BasePart
	local p = Instance.new((class or "Part") :: any) :: BasePart
	p.Size = size
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Parent = parent
	return p
end

-- a flat chevron: a triangle tip (two wedges) on a short shaft, ink outline from a Highlight
local function buildArrow(): Model
	local m = Instance.new("Model")
	m.Name = "GuideArrow"
	local shaft = part(Vector3.new(1.1, 0.35, 1.2), Theme.fx.arrow, m)
	shaft.CFrame = CFrame.new(0, 0, 0.6)
	for _, side in { -1, 1 } do
		-- each wedge, laid on its side, is one half of the flat triangle; the tip points -Z
		local w = part(Vector3.new(0.35, 1.4, 1.8), Theme.fx.arrow, m, "WedgePart")
		w.CFrame = CFrame.new(side * 0.7, 0, -0.9) * CFrame.Angles(0, 0, if side > 0 then -math.pi / 2 else math.pi / 2)
	end
	m.PrimaryPart = shaft
	local h = Instance.new("Highlight")
	h.FillTransparency = 1
	h.OutlineColor = Theme.ink
	h.DepthMode = Enum.HighlightDepthMode.Occluded
	h.Parent = m
	m.Parent = folder
	return m
end

local function myRoot(): BasePart?
	local c = me.Character
	return c and c:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function carrying(): boolean
	local cubes = workspace:FindFirstChild("Cubes")
	if cubes then
		for _, c in cubes:GetChildren() do
			if c:GetAttribute("OwnerUserId") == me.UserId then
				return true
			end
		end
	end
	return false
end

-- pets this player can freeze: shared ones and their own rares, Forest only once it's open
local function freezable(r: Instance, v: State.View?): boolean
	if not r:IsA("BasePart") then
		return false
	end
	local owner = r:GetAttribute("OwnerUserId")
	if typeof(owner) == "number" and owner ~= 0 and owner ~= me.UserId then
		return false
	end
	if r:GetAttribute("Zone") == 2 and not (v and v.forestUnlocked) then
		return false
	end
	return r:GetAttribute("State") ~= "dazed" or r:GetAttribute("OfferUserId") == me.UserId
end

local function nearestPet(from: Vector3, minDist: number, maxDist: number, zone: number?): BasePart?
	local wild = workspace:FindFirstChild("WildPets")
	local best, bestD = nil, maxDist
	for _, r in (if wild then wild:GetChildren() else {}) do
		if freezable(r, State.view) and (zone == nil or r:GetAttribute("Zone") == zone) then
			local p = (r :: BasePart).Position
			local d = (Vector3.new(p.X, 0, p.Z) - Vector3.new(from.X, 0, from.Z)).Magnitude
			if d < bestD and d > minDist then
				best, bestD = r :: BasePart, d
			end
		end
	end
	return best
end

local function step()
	local root = myRoot()
	local v = State.view
	local t = os.clock()
	local still = SettingsController.get("reducedMotion") == true
	local holding = carrying()
	if not root or not v then
		arrow.Parent, marker.Parent, beacon.Parent = nil, nil, nil
		return
	end
	local pos = root.Position
	-- arrow
	local goal: Vector3? = nil
	if holding and v.plot then
		goal = WorldRules.plotCenter(v.plot)
	elseif #v.pets < G.earlyPets then
		local p = nearestPet(pos, 0, math.huge, 1)
		goal = if p then p.Position else nil
	end
	local flat = if goal then Vector3.new(goal.X - pos.X, 0, goal.Z - pos.Z) else Vector3.zero
	local showArrow = goal ~= nil and flat.Magnitude > G.arrowHideNear
	if showArrow then
		local dir = flat.Unit
		local bob = if still then 0.15 else math.abs(math.sin(t * G.arrowBobSpeed)) * G.arrowBob
		local at = Vector3.new(pos.X, 0, pos.Z) + dir * G.arrowDistance + Vector3.new(0, G.arrowY + bob, 0)
		arrow:PivotTo(CFrame.lookAt(at, at + dir))
		arrow.Parent = folder
	else
		arrow.Parent = nil
	end
	-- marker: the nearest pet just out of reach, while your hands are free
	local mk = if not holding and not showArrow then nearestPet(pos, Config.player.freezeRange, G.markerRange, nil) else nil
	if mk then
		local tier = mk:GetAttribute("Tier")
		marker.Color = if typeof(tier) == "string" then Theme.tiers[tier] or Theme.white else Theme.white
		local bob = if still then 0 else math.sin(t * 3) * G.markerBob
		marker.CFrame = CFrame.new(mk.Position + Vector3.new(0, mk.Size.Y * 0.9 + G.markerY + bob, 0)) * CFrame.Angles(0, if still then 0 else t * G.markerSpin, 0)
		marker.Parent = folder
	else
		marker.Parent = nil
	end
	-- beacon over your pen while you carry
	if holding and v.plot then
		local c = WorldRules.plotCenter(v.plot)
		beacon.CFrame = CFrame.new(c.X, G.beaconHeight / 2, c.Z) * CFrame.Angles(0, 0, math.pi / 2)
		beacon.Transparency = G.beaconTransparency + (if still then 0 else math.sin(t * 3) * G.beaconPulse)
		beacon.Parent = folder
	else
		beacon.Parent = nil
	end
end

function GuideController.Init()
	folder = Instance.new("Folder")
	folder.Name = "Guides"
	folder.Parent = workspace
end

function GuideController.Start()
	arrow = buildArrow()
	local meshes = ReplicatedStorage:FindFirstChild("SceneryMeshes")
	local octa = meshes and meshes:FindFirstChild("Octa")
	marker = if octa and octa:IsA("MeshPart") then octa:Clone() else Instance.new("Part")
	marker.Name = "NearestPetMarker"
	marker.Size = Vector3.new(1.1, 1.65, 1.1)
	marker.Material = Enum.Material.Neon
	marker.Anchored, marker.CanCollide, marker.CanQuery, marker.CanTouch, marker.CastShadow = true, false, false, false, false
	beacon = part(Vector3.new(G.beaconHeight, G.beaconRadius * 2, G.beaconRadius * 2), Theme.fx.beacon, folder)
	beacon.Name = "PenBeacon"
	beacon.Shape = Enum.PartType.Cylinder
	beacon.Material = Enum.Material.Neon
	RunService.RenderStepped:Connect(step)
end

return GuideController
