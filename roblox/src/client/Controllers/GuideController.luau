--!strict
-- GuideController: the world teaches (prototype client.js). The only owner of three local guides:
--  - a chevron on the ground in the island's own colour (Theme.placeColor, owner 2026-11-13), 6.5 studs out: to the nearest pet while you own fewer than 3,
--    home to your pen while you carry a cube (hidden once you're close)
--  - a small diamond over the nearest pet you can't reach yet (hands free, arrow hidden)
--  - (the green light pillar over your pen while you carry was removed, owner 2026-11-17)
--  - (2026-11-15, tutorial references) a trail of smaller chevrons flowing from the lead one to the
--    target, and a big white chevron bobbing over the target itself, pointing down
-- Everything is local; nothing here changes the game.
-- 2026-11-16 (owner: "after you finish the tutorial the arrows still remain", "while training the arrows keep
-- aiming at the pets", "after you put the pet in the thaw machine the arrows guide you to another pet"): the
-- chevrons and the target arrow show only while the tutorial runs, and only toward the current step's own
-- target (GuideController.focus).
-- 2026-11-18 (owner: "stop showing the arrows to the base if we're not in a tutorial, for example when I do not
-- have enough power"): the "go train" pointer after "Need more Cold Power" is gone. Outside the tutorial only the
-- "NEW ISLAND!" gate pointer is left.
-- One deep blue everywhere (Theme.fx.guideArrow), not the island colours, which washed out on snow.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Theme = require(ReplicatedStorage.Shared.Theme)
local WorldRules = require(ReplicatedStorage.Shared.WorldRules)
local State = require(script.Parent.State)
local SettingsController = require(script.Parent.SettingsController)
local Screen = require(script.Parent.Screen)

local GuideController = {}
-- what the arrow points at this frame (TutorialController makes it glow):
-- kind = "pet" | "cube" | "machine" | "pan" | "train" | "stand" | "gate"; inst = the pet or cube part when there is one
export type Target = { kind: string, pos: Vector3, inst: Instance? }
GuideController.target = nil :: Target?
-- the tutorial is teaching the catch: point at pets even if you own plenty (a replay) and before a
-- frozen pet waiting for the Thaw Machine
GuideController.pointPets = false
-- the tutorial is running (TutorialController): the arrows show only then; focus = the step's target kind
-- ("pet" | "cube" | "pan" | "machine" | "stand" | "train" | "gate"), nil on a talk step = no arrow
GuideController.tutorial = false
GuideController.focus = nil :: string?
-- the tutorial is showing something the arrow doesn't know (the Pan Upgrades stand): point there instead
GuideController.extra = nil :: Target?
local G = Config.guide
local me = Players.LocalPlayer
-- "NEW ISLAND!" (UnlockAlert's GO): the arrow points at that island's gate until it's open or the time is up
local gateZone, gateUntil = 0, 0
function GuideController.pointGate(zoneId: number, seconds: number)
	gateZone, gateUntil = zoneId, os.clock() + seconds
end
local function gateSpot(v: State.View): Vector3?
	local z = Config.zone(gateZone)
	if not z or (v.reach or 1) >= gateZone then
		return nil
	end
	return Vector3.new(0, 0, z.zMin - Config.gatePromptOffset)
end
local folder: Folder
local arrow: Model
local trail: { Model } = {}
local targetArrow: Model
local arrowZone = -1 -- the zone whose colour the arrow wears now
local marker: BasePart

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
local function buildArrow(color: Color3?): Model
	local m = Instance.new("Model")
	m.Name = "GuideArrow"
	local shaft = part(Vector3.new(1.1, 0.35, 1.2), color or Theme.fx.guideArrow, m)
	shaft.CFrame = CFrame.new(0, 0, 0.6)
	for _, side in { -1, 1 } do
		-- each wedge, laid on its side, is one half of the flat triangle; the tip points -Z
		local w = part(Vector3.new(0.35, 1.4, 1.8), color or Theme.fx.guideArrow, m, "WedgePart")
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
	local zone = r:GetAttribute("Zone")
	if typeof(zone) == "number" and zone > ((v and v.reach) or 1) then
		return false -- behind a gate you haven't opened yet
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

-- a frozen pet waiting in your Pets and a free Thaw Machine: the arrow points at that machine
-- (owner 2026-11-09: you put each pet in yourself). Same spot as PenService.machineSpot.
local function freeMachine(v: State.View): Vector3?
	if not v.plot then
		return nil
	end
	local frozen, busy = false, {} :: { [number]: boolean }
	for _, p in v.pets do
		if p.thawM then
			busy[p.thawM] = true
		elseif p.frozen then
			frozen = true
		end
	end
	if not frozen then
		return nil
	end
	for m = 1, v.machines or 1 do
		if not busy[m] then
			return GuideController.machineAt(v.plot :: number, m)
		end
	end
	return nil
end

-- the machine my pet is thawing in right now (the tutorial's "wait for your pet": the arrow stays on it)
local function busyMachine(v: State.View): Vector3?
	if not v.plot then
		return nil
	end
	for _, p in v.pets do
		if p.thawM then
			return GuideController.machineAt(v.plot :: number, p.thawM)
		end
	end
	return nil
end

-- a pet done thawing and waiting for Claim: the arrow points at its machine (the READY sign says the
-- rest; the first pet pops out by itself, so this is how Claim is taught, 2026-11-15)
local function readyMachine(v: State.View): number?
	if not Config.thaw.claimByHand then
		return nil
	end
	local now = workspace:GetServerTimeNow()
	for _, p in v.pets do
		local at = (p :: any).thawAt
		if p.thawM and typeof(at) == "number" and at <= now then
			return p.thawM
		end
	end
	return nil
end

-- where Thaw Machine m of a pan stands (same spot as PenService.machineSpot)
function GuideController.machineAt(plot: number, m: number): Vector3
	local T, P = Config.thaw, Config.world.pans
	local spot = Config.world.plots[plot]
	return Vector3.new(spot.x + Config.thawMachineOffset(m, Config.machineCount(plot)), 0, P.frontZ - Config.plotLength(plot) + T.machine.z)
end

local function step()
	local root = myRoot()
	local v = State.view
	local t = os.clock()
	local still = SettingsController.get("reducedMotion") == true
	local holding = carrying()
	-- my frozen pet still waiting on the ground for E (CarryService.dropCube)
	local waiting: Vector3? = nil
	local waitingPart: BasePart? = nil
	local gf = workspace:FindFirstChild("GroundCubes")
	for _, g in (if gf then gf:GetChildren() else {}) do
		if g:IsA("BasePart") and g:GetAttribute("OwnerUserId") == me.UserId then
			waiting, waitingPart = g.Position, g
			break
		end
	end
	if not root or not v then
		arrow.Parent, marker.Parent, targetArrow.Parent = nil, nil, nil
		for _, c in trail do
			c.Parent = nil
		end
		GuideController.target = nil
		return
	end
	local pos = root.Position
	-- arrow
	local goal: Vector3? = nil
	local kind: string? = nil
	local inst: Instance? = nil
	local ready = if v.plot then readyMachine(v) else nil
	local machine = if ready and v.plot then GuideController.machineAt(v.plot, ready) else freeMachine(v)
	local focus = GuideController.focus
	if GuideController.tutorial then
		-- only the current step's own target (nothing on a talk step, nothing while you train on the pad)
		if (focus == "pan" or focus == "cube") and holding and v.plot then
			goal, kind = WorldRules.plotCenter(v.plot), "pan"
		elseif (focus == "pan" or focus == "cube") and waiting then
			goal, kind, inst = waiting, "cube", waitingPart -- go back and pick it up
		elseif focus == "pet" then
			local p = nearestPet(pos, 0, math.huge, 1)
			if p then
				goal, kind, inst = p.Position, "pet", p
			end
		elseif focus == "machine" then
			local at = machine or busyMachine(v)
			if at then
				goal, kind = at, "machine" -- put it in, then wait by it
			end
		elseif GuideController.extra and GuideController.extra.kind == focus then
			goal, kind = GuideController.extra.pos, GuideController.extra.kind
		end
	elseif t < gateUntil and not holding and gateSpot(v) then
		goal, kind = gateSpot(v), "gate" -- "NEW ISLAND!": walk to its gate and open it
	end
	GuideController.target = if goal and kind then { kind = kind, pos = goal, inst = inst } else nil
	local flat = if goal then Vector3.new(goal.X - pos.X, 0, goal.Z - pos.Z) else Vector3.zero
	-- a show is playing (Screen.showHidden): the arrow steps out of the shot (2026-11-12, it sat in the rebirth reveal)
	local showArrow = goal ~= nil and flat.Magnitude > G.arrowHideNear and not Screen.showHidden
	local shownTrail = 0
	if showArrow then
		local dir = flat.Unit
		local bob = if still then 0.15 else math.abs(math.sin(t * G.arrowBobSpeed)) * G.arrowBob
		local base = Vector3.new(pos.X, 0, pos.Z)
		local at = base + dir * G.arrowDistance + Vector3.new(0, G.arrowY + bob, 0)
		arrow:PivotTo(CFrame.lookAt(at, at + dir))
		arrow.Parent = folder
		-- the trail: smaller chevrons flowing on from the lead one, stopping short of the target
		local flow = if still then 0 else (t * G.trailFlow) % G.trailGap
		local stopAt = flat.Magnitude - G.arrowHideNear * 0.5
		for i, c in trail do
			local d = G.arrowDistance + G.trailGap * i - G.trailGap + flow + G.trailGap * 0.5
			if d < stopAt then
				local p = base + dir * d + Vector3.new(0, G.arrowY * 0.6, 0)
				c:PivotTo(CFrame.lookAt(p, p + dir))
				c.Parent = folder
				shownTrail = i
			else
				break
			end
		end
	else
		arrow.Parent = nil
	end
	for i = shownTrail + 1, #trail do
		trail[i].Parent = nil
	end
	-- the target arrow: a big white chevron over the target, pointing down at it, facing the camera
	local near = if goal then flat.Magnitude < G.targetHideNear else true
	if goal and kind and not near and not Screen.showHidden then
		local top = goal.Y + (G.targetTop[kind] or 4)
		if inst and inst:IsA("BasePart") then
			top = inst.Position.Y + inst.Size.Y / 2
		end
		local bob = if still then 0 else math.abs(math.sin(t * G.targetBobSpeed)) * G.targetBob
		local at = Vector3.new(goal.X, top + G.targetY + bob, goal.Z)
		local cam = workspace.CurrentCamera
		local toCam = if cam then cam.CFrame.Position - at else Vector3.zAxis
		-- QA PT-07 (2026-11-19): a target just under the camera (the Thaw Machine behind you) drew the chevron huge
		-- at the bottom of the screen, over the hotbar. Too close to the camera = not drawn; the trail still leads
		local tooClose = toCam.Magnitude < (G.targetHideCam or 14)
		toCam = Vector3.new(toCam.X, 0, toCam.Z)
		toCam = if toCam.Magnitude > 0.1 then toCam.Unit else Vector3.zAxis
		-- lookAt makes -Z face the camera; tipping it -90 degrees round X points the tip (-Z) down
		targetArrow:PivotTo(CFrame.lookAt(at, at + toCam) * CFrame.Angles(-math.pi / 2, 0, 0))
		targetArrow.Parent = if tooClose then nil else folder
	else
		targetArrow.Parent = nil
	end
	-- marker: the nearest pet just out of reach, while your hands are free
	local mk = if not holding and not waiting and not showArrow then nearestPet(pos, Config.gun(me:GetAttribute("GunTier") :: number?).range, G.markerRange, nil) else nil -- just out of your gun's reach
	if mk then
		local tier = mk:GetAttribute("Tier")
		marker.Color = if typeof(tier) == "string" then Theme.tiers[tier] or Theme.white else Theme.white
		local bob = if still then 0 else math.sin(t * 3) * G.markerBob
		marker.CFrame = CFrame.new(mk.Position + Vector3.new(0, mk.Size.Y * 0.9 + G.markerY + bob, 0)) * CFrame.Angles(0, if still then 0 else t * G.markerSpin, 0)
		marker.Parent = folder
	else
		marker.Parent = nil
	end
end

function GuideController.Init()
	folder = Instance.new("Folder")
	folder.Name = "Guides"
	folder.Parent = workspace
end

function GuideController.Start()
	arrow = buildArrow()
	for i = 1, G.trailCount do
		local c = buildArrow()
		c.Name = "GuideTrail" .. i
		c:ScaleTo(G.trailScale)
		local h = c:FindFirstChildOfClass("Highlight")
		if h then
			h:Destroy() -- Roblox draws at most 31 Highlights at once: the small trail goes without an outline
		end
		c.Parent = nil
		trail[i] = c
	end
	targetArrow = buildArrow(Theme.fx.guideArrowTop)
	targetArrow.Name = "TargetArrow"
	targetArrow:ScaleTo(G.targetScale)
	local th = targetArrow:FindFirstChildOfClass("Highlight")
	if th then
		th.OutlineColor = Theme.white -- a white rim round the deep blue reads over grass, snow and sky
		th.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	end
	targetArrow.Parent = nil
	local meshes = ReplicatedStorage:FindFirstChild("SceneryMeshes")
	local octa = meshes and meshes:FindFirstChild("Octa")
	marker = if octa and octa:IsA("MeshPart") then octa:Clone() else Instance.new("Part")
	marker.Name = "NearestPetMarker"
	marker.Size = Vector3.new(1.1, 1.65, 1.1)
	marker.Material = Enum.Material.Neon
	marker.Anchored, marker.CanCollide, marker.CanQuery, marker.CanTouch, marker.CastShadow = true, false, false, false, false
	RunService.RenderStepped:Connect(step)
end

return GuideController
