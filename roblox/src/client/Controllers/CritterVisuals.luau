--!strict
-- CritterVisuals (Round 5): draws the Heat Critters on the server's invisible "Critter" parts
-- (CritterService). Each wears a pet's art (PetVisuals.model) in warm orange with a soft glow and
-- little steam puffs (it's hot, it wants your ice). Chasing: it bounces quicker and steams harder.
-- Happy (it just grabbed a cube): a little hop. Frozen: an ice block around it that clears up as it
-- thaws. Being shot: the ice creeps up like on a pet. Nothing scary: no teeth, no red eyes.

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Theme = require(ReplicatedStorage.Shared.Theme)
local PetVisuals = require(script.Parent.PetVisuals)
local SettingsController = require(script.Parent.SettingsController)

local CritterVisuals = {}
local C = Config.chasers
type Look = { model: PVInstance, img: ImageLabel?, steam: ParticleEmitter, glow: PointLight, ice: Part, phase: number, at: CFrame }
local looks: { [BasePart]: Look } = {}
local folder: Folder

local function part(size: Vector3, color: Color3): Part
	local p = Instance.new("Part")
	p.Size = size
	p.Color = color
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	p.Parent = folder
	return p
end

local function add(root: Instance)
	if not root:IsA("BasePart") or looks[root] then
		return
	end
	local key = root:GetAttribute("PetKey")
	local model, img = PetVisuals.model(if typeof(key) == "string" then key else C.look.pet, C.size)
	if not model then
		return
	end
	model.Parent = folder
	-- warm it up: a model gets an orange Highlight, a sprite an orange tint
	if img then
		img.ImageColor3 = Theme.round5.critterGlow
	else
		local h = Instance.new("Highlight")
		h.FillColor = Theme.round5.critter
		h.FillTransparency = 0.55
		h.OutlineColor = Theme.round5.critterGlow
		h.OutlineTransparency = 0.2
		h.Parent = model
	end
	local core = part(Vector3.one * 0.2, Theme.round5.critter)
	core.Transparency = 1
	core.Parent = model
	local steam = Instance.new("ParticleEmitter")
	steam.Color = ColorSequence.new(Theme.round5.critterSteam)
	steam.Transparency = NumberSequence.new(0.3, 1)
	steam.Size = NumberSequence.new(0.4, 1.2)
	steam.Lifetime = NumberRange.new(0.6, 1)
	steam.Speed = NumberRange.new(1.5, 3)
	steam.SpreadAngle = Vector2.new(25, 25)
	steam.EmissionDirection = Enum.NormalId.Top
	steam.Rate = 4
	steam.Parent = core
	local glow = Instance.new("PointLight")
	glow.Color = Theme.round5.critterGlow
	glow.Range = 8
	glow.Brightness = 1.2
	glow.Parent = core
	local ice = part(Vector3.one * C.size * 1.25, Theme.ice)
	ice.Material = Enum.Material.Glass
	ice.Transparency = 1
	ice.Name = "CritterIce"
	looks[root] = { model = model, img = img, steam = steam, glow = glow, ice = ice, phase = math.random() * 6, at = root.CFrame }
end

local function remove(root: Instance)
	local l = looks[root :: BasePart]
	if l then
		l.model:Destroy()
		l.ice:Destroy()
		looks[root :: BasePart] = nil
	end
end

local function step(dt: number)
	local t = os.clock()
	local reduced = SettingsController.get("reducedMotion") == true
	local amp = if reduced then 0.35 else 1
	for root, l in looks do
		if not root.Parent then
			remove(root)
			continue
		end
		local state = root:GetAttribute("State")
		local meter = (root:GetAttribute("Meter") or 0) :: number
		local frozen = state == "frozen"
		-- glide after the server's root, bounce while moving (quicker while chasing)
		l.at = l.at:Lerp(root.CFrame, math.min(1, dt * 12))
		local hz = if state == "chase" then 9 elseif state == "happy" then 5 else 4
		local hop = if frozen then 0 else math.abs(math.sin(t * hz + l.phase)) * 0.35 * amp * (1 - meter)
		local base = l.at - Vector3.new(0, C.size / 2, 0) + Vector3.new(0, C.size / 2 + hop, 0)
		l.model:PivotTo(base)
		l.steam.Rate = if frozen then 0 elseif state == "chase" then 14 else 4
		l.glow.Enabled = not frozen
		-- the ice: a block while frozen (it clears as it thaws), creeping up while being shot
		if frozen then
			local untilT = root:GetAttribute("FrozenUntil")
			local left = if typeof(untilT) == "number" then math.max(0, untilT - workspace:GetServerTimeNow()) else 0
			l.ice.Size = Vector3.one * C.size * 1.25
			l.ice.CFrame = CFrame.new(root.Position)
			l.ice.Transparency = 0.3 + 0.4 * (1 - math.min(1, left / 3))
		elseif meter > 0 then
			local h = C.size * 1.1 * meter
			l.ice.Size = Vector3.new(C.size * 1.25, math.max(0.05, h), C.size * 1.25)
			l.ice.CFrame = CFrame.new(root.Position - Vector3.new(0, C.size / 2 - h / 2, 0))
			l.ice.Transparency = 0.5
		else
			l.ice.Transparency = 1
		end
	end
end

function CritterVisuals.Init()
	folder = Instance.new("Folder")
	folder.Name = "CritterVisuals"
	folder.Parent = workspace
end

function CritterVisuals.Start()
	task.spawn(function()
		local f = workspace:WaitForChild("Critters", 30)
		if not f then
			return
		end
		f.ChildAdded:Connect(function(c)
			task.defer(add, c)
		end)
		f.ChildRemoved:Connect(remove)
		for _, c in f:GetChildren() do
			add(c)
		end
	end)
	RunService.RenderStepped:Connect(step)
end

return CritterVisuals
