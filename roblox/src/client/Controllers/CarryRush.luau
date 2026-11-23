--!strict
-- CarryRush: the run home with a frozen pet in your hands (owner 2026-11-22: "when picking up an animal all the
-- UI disappears ... red effects, outlines etc for players to feel the dopamine and challenge"). Numbers in
-- Config.carry.rush, colours in Theme.fx.rush. Only the look: the server's carry, melt and chasers are unchanged.
-- PetVisuals tells it every frame how many cubes you hold, the least ice left and the drawn ice parts.
-- Grab (a cube lands in your hands): you flash white then red, red glitter and a breath of red vapour burst round
--   you, the camera punches in, and the red screen edge slams on and settles.
-- While you carry: the HUD steps aside (Screen.setCarryHidden), a red edge round the screen beats like a heart and
--   beats faster as the ice melts, and you and your cubes wear a red outline. Chasers after you get one too
--   (CritterVisuals asks CarryRush.active()). The carry's sounds are unchanged (SoundController).
-- Reduced motion: no punch, no flash, slower glitter, the edge glows steady. Low graphics: half the glitter.
-- Safe hub (owner 2026-11-22: "cancel the red animation after entering the safe zone"): the ice doesn't melt there,
--   so the rush stops: the edge fades out, the outlines go and the HUD comes back. Back out on an island it fades
--   in again (no new grab: that's only for a cube landing in your hands).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Theme = require(ReplicatedStorage.Shared.Theme)
local WorldRules = require(ReplicatedStorage.Shared.WorldRules)
local SettingsController = require(script.Parent.SettingsController)
local CameraController = require(script.Parent.CameraController)
local Screen = require(script.Parent.Screen)

local CarryRush = {}
local R = Config.carry.rush
local G = R.grab
local E = R.edge
local player = Players.LocalPlayer

local count = 0 -- cubes in your hands
local safe = false -- you're in the safe hub (no melting, so no rush)
local life = 1 -- the least ice left on them (0-1)
local grabAt = -math.huge
local grabSize = 1
local beat = 0 -- heartbeat phase, in beats
local shown = 0 -- 0-1: the red edge fading in and out
local gui: ScreenGui? = nil
local edges: { [string]: Frame } = {}
local border: UIStroke? = nil
local folder: Folder? = nil
local body: Highlight? = nil
local cubeLights: { [Instance]: Highlight } = {}
local seen: { [Instance]: boolean } = {}
local hidPlayerList = false

local function reduced(): boolean
	return SettingsController.get("reducedMotion") == true
end

local function time(seconds: number): number
	return seconds * (if reduced() then 0.5 else 1)
end

function CarryRush.active(): boolean
	return count > 0 and not safe
end

-- a red outline in the rush style; fill = how see-through the red tint over it is (1 = outline only)
function CarryRush.outline(adornee: Instance, fill: number, parent: Instance?): Highlight
	local h = Instance.new("Highlight")
	h.Name = "RushOutline"
	h.Adornee = adornee
	h.OutlineColor = Theme.fx.rush
	h.OutlineTransparency = 0
	h.FillColor = Theme.fx.rush
	h.FillTransparency = fill
	-- never through walls (owner 2026-11-17: outlines that showed through the cliffs from miles away)
	h.DepthMode = Enum.HighlightDepthMode.Occluded
	h.Parent = parent or folder
	return h
end

local function myRoot(): BasePart?
	local c = player.Character
	local r = c and c:FindFirstChild("HumanoidRootPart")
	return if r and r:IsA("BasePart") then r else nil
end

local function inHub(): boolean
	local r = myRoot()
	return r ~= nil and WorldRules.inHub(r.Position)
end

-- red glitter and a breath of red vapour round you as the cube lands (textured, not neon shapes: Animation Rules)
local function burst(root: BasePart, size: number)
	local k = (if SettingsController.get("lowGraphics") then 0.5 else 1) * (if reduced() then 0.5 else 1) * size
	local slow = if reduced() then 0.35 else 1
	local p = Instance.new("Part")
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch = true, false, false, false
	p.Transparency = 1
	p.Size = Vector3.one
	p.Position = root.Position
	p.Parent = folder
	local glitter = Instance.new("ParticleEmitter")
	glitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	glitter.Color = ColorSequence.new(Theme.fx.rushGlint, Theme.fx.rush)
	glitter.LightEmission = 1
	glitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.1), NumberSequenceKeypoint.new(1, 0) })
	glitter.Transparency = NumberSequence.new(0, 0.4)
	glitter.Speed = NumberRange.new(10 * slow, 20 * slow)
	glitter.Drag = 4
	glitter.Lifetime = NumberRange.new(0.35, 0.75)
	glitter.SpreadAngle = Vector2.new(180, 180)
	glitter.Rotation = NumberRange.new(0, 360)
	glitter.Rate = 0
	glitter.Parent = p
	glitter:Emit(math.max(1, math.floor(G.sparks * k)))
	local vapour = Instance.new("ParticleEmitter")
	vapour.Texture = "rbxasset://textures/particles/smoke_main.dds"
	vapour.Color = ColorSequence.new(Theme.fx.rush)
	vapour.LightEmission = 0.6
	vapour.Size = NumberSequence.new(1.5, 4.5)
	vapour.Transparency = NumberSequence.new(0.55, 1)
	vapour.Speed = NumberRange.new(4 * slow, 8 * slow)
	vapour.Drag = 5
	vapour.Lifetime = NumberRange.new(0.4, 0.7)
	vapour.SpreadAngle = Vector2.new(180, 180)
	vapour.Rotation = NumberRange.new(0, 360)
	vapour.Rate = 0
	vapour.Parent = p
	vapour:Emit(math.max(1, math.floor(G.vapour * k)))
	task.delay(1.2, function()
		p:Destroy()
	end)
end

-- the red outline on you; follows respawns
local function ensureBody(): Highlight?
	local c = player.Character
	if not c then
		return nil
	end
	if body and body.Adornee ~= c then
		body:Destroy()
		body = nil
	end
	if not body then
		body = CarryRush.outline(c, R.outline.youFill)
	end
	return body
end

-- a cube landed in your hands: hit flash on you, glitter, punch, edge slam
local function grab(size: number)
	grabAt = os.clock()
	grabSize = size
	beat = 0
	local root = myRoot()
	if root then
		burst(root, size)
	end
	CameraController.kick("grab", size)
	local h = ensureBody()
	if h then
		-- white for a blink, then the red tint (a soft fade with reduced motion: Animation Rules 1)
		h.FillColor = Theme.fx.flash
		h.FillTransparency = if reduced() then 0.6 else 0
		task.delay(time(G.bodyFlash), function()
			if body == h and h.Parent then
				h.FillColor = Theme.fx.rush
				h.FillTransparency = 0.3
				TweenService:Create(h, TweenInfo.new(time(G.bodyFade), Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
					{ FillTransparency = R.outline.youFill }):Play()
			end
		end)
	end
end

-- PetVisuals, every frame: cubes in your hands, the least ice left, and the frozen pet drawn in each (outlined red:
-- a Highlight skips see-through parts, so the ice itself can't carry one)
function CarryRush.set(n: number, lowest: number, ices: { Instance })
	safe = inHub()
	if n > count and not safe then
		grab(if count == 0 then 1 else G.again)
	end
	count, life = n, math.clamp(lowest, 0, 1)
	table.clear(seen)
	for _, ice in (if safe then {} else ices) do
		seen[ice] = true
		if not cubeLights[ice] then
			cubeLights[ice] = CarryRush.outline(ice, R.outline.cubeFill)
		end
	end
	for ice, h in cubeLights do
		if not seen[ice] or not ice.Parent then
			h:Destroy()
			cubeLights[ice] = nil
		end
	end
end

local function setPlayerList(hide: boolean)
	if hide and not hidPlayerList then
		local ok, on = pcall(StarterGui.GetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.PlayerList)
		if ok and on then
			hidPlayerList = pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.PlayerList, false)
		end
	elseif not hide and hidPlayerList then
		hidPlayerList = false
		pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.PlayerList, true)
	end
end

local function step(dt: number)
	local on = CarryRush.active()
	Screen.setCarryHidden(on and R.hideHud)
	setPlayerList(on and R.hidePlayerList)
	if on then
		ensureBody()
	elseif body then
		body:Destroy()
		body = nil
	end
	-- the red edge: fades in and out, slams on at a grab, beats like a heart (faster as the ice melts)
	shown = math.clamp(shown + (if on then 1 else -1) * dt / math.max(0.01, time(E.fade)), 0, 1)
	local g = gui
	if not g then
		return
	end
	g.Enabled = shown > 0
	if shown <= 0 then
		return
	end
	local slam = math.max(0, 1 - (os.clock() - grabAt) / math.max(0.01, time(G.flashSeconds))) * grabSize
	local pulse = 0
	if not reduced() then
		local bpm = R.bpm[1] + (R.bpm[2] - R.bpm[1]) * (1 - life)
		beat += dt * bpm / 60
		pulse = math.exp(-(beat % 1) * 6) -- a quick swell on the beat, easing off until the next
	else
		slam = 0
	end
	local alpha = E.base - E.beat * pulse
	alpha += (E.slam - alpha) * math.min(1, slam)
	alpha = 1 - (1 - alpha) * shown
	-- the edge's depth: a share of the short side, as Scale of each axis
	local size = g.AbsoluteSize
	local short = math.max(1, math.min(size.X, size.Y))
	local dx, dy = E.size * short / math.max(1, size.X), E.size * short / math.max(1, size.Y)
	edges.left.Size = UDim2.fromScale(dx, 1)
	edges.right.Size = UDim2.fromScale(dx, 1)
	edges.top.Size = UDim2.fromScale(1, dy)
	edges.bottom.Size = UDim2.fromScale(1, dy)
	for _, f in edges do
		f.BackgroundTransparency = alpha
	end
	local b = border
	if b then
		local thick = E.stroke + E.strokeSlam * math.min(1, slam) + (if reduced() then 0 else 2 * pulse)
		b.Thickness = thick
		-- a border stroke draws outside its frame: the frame shrinks by it, so the stroke sits on the screen's edge
		local holder = b.Parent :: Frame
		holder.Size = UDim2.new(1, -2 * thick, 1, -2 * thick)
		b.Transparency = 1 - (1 - math.min(0.35, alpha)) * shown
	end
end

function CarryRush.Init()
	local f = Instance.new("Folder")
	f.Name = "CarryRush"
	f.Parent = workspace
	folder = f
	-- the red edge: four gradient strips (red at the screen's edge, clear inward) and a hard red outline round it
	local g = Instance.new("ScreenGui")
	g.Name = "CarryRush"
	g.IgnoreGuiInset = true
	g.ResetOnSpawn = false
	g.DisplayOrder = 15 -- over the HUD layers, under the show flash (20)
	g.Enabled = false
	local function strip(name: string, anchor: Vector2, pos: UDim2, rotation: number)
		local s = Instance.new("Frame")
		s.Name = name
		s.AnchorPoint = anchor
		s.Position = pos
		s.BackgroundColor3 = Theme.fx.rush
		s.BackgroundTransparency = 1
		s.BorderSizePixel = 0
		s.Active = false
		local grad = Instance.new("UIGradient")
		grad.Rotation = rotation
		grad.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.45, 0.6), NumberSequenceKeypoint.new(1, 1) })
		grad.Parent = s
		s.Parent = g
		edges[name] = s
	end
	strip("left", Vector2.new(0, 0), UDim2.fromScale(0, 0), 0)
	strip("right", Vector2.new(1, 0), UDim2.fromScale(1, 0), 180)
	strip("top", Vector2.new(0, 0), UDim2.fromScale(0, 0), 90)
	strip("bottom", Vector2.new(0, 1), UDim2.fromScale(0, 1), 270)
	local frame = Instance.new("Frame")
	frame.Name = "Border"
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundTransparency = 1
	frame.Active = false
	local s = Instance.new("UIStroke")
	s.Color = Theme.fx.rush
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Thickness = E.stroke
	s.Transparency = 1
	s.Parent = frame
	frame.Parent = g
	border = s
	g.Parent = player:WaitForChild("PlayerGui")
	gui = g
end

function CarryRush.Start()
	RunService.RenderStepped:Connect(step)
end

return CarryRush
