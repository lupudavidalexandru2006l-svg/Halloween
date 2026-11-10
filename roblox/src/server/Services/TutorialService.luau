--!strict
-- TutorialService: the one owner of each player's tutorial progress, saved in their data as
-- tutorial = { step, done } (Config.tutorial). The game's services report what a player really did
-- (TutorialService.did, called where the server decides it: FreezeService, CarryService, PenService);
-- this moves the step on and the client plays Ranger Bo (TutorialController). The client only sends
-- intent through the Tutorial remote: "next" on a talk step, "skip", "replay" (Code Rules 6).
-- Each player's progress is their own, so any number of players can be on different steps at once.
-- It also builds Bo's model once (ReplicatedStorage.TutorialGuide); every client clones its own copy.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Theme = require(ReplicatedStorage.Shared.Theme)
local DataService = require(script.Parent.DataService)
local Remotes = require(script.Parent.Remotes)

local TutorialService = {}
local T = Config.tutorial
local lastNext: { [Player]: number } = {}

-- why: "did" (an action), "next", "skip", "replay"
local function setStep(player: Player, step: number, done: boolean, why: string)
	local changed = DataService.mutate(player, function(d)
		d.tutorial.step = math.clamp(step, 1, #T.steps)
		d.tutorial.done = done
	end)
	if not changed then
		return
	end
	Remotes.fire(player, "Notify", "tutorial", { step = math.clamp(step, 1, #T.steps), done = done, why = why })
	if done or why == "replay" then
		task.spawn(DataService.saveNow, player) -- finishing or skipping is remembered at once, not at the next autosave
	end
end

-- a player did something the tutorial teaches. The current step or any later one counts, so a kid who
-- already froze a pet while Bo was still saying hello goes straight on to picking it up.
function TutorialService.did(player: Player, action: string)
	if not T.actions[action] then
		return
	end
	local d = DataService.get(player)
	if not d or d.tutorial.done then
		return
	end
	for i = d.tutorial.step, #T.steps do
		if T.steps[i].on == action then
			local nextStep = i + 1
			setStep(player, nextStep, nextStep > #T.steps, "did")
			return
		end
	end
end

local function onTutorial(player: Player, what: any)
	if typeof(what) ~= "string" then
		return
	end
	local d = DataService.get(player)
	if not d then
		return
	end
	local tu = d.tutorial
	if what == "next" then
		-- only a talk step moves on with Next; an action step needs the action itself
		local step = T.steps[tu.step]
		local now = os.clock()
		if tu.done or not step or step.on ~= "next" or now - (lastNext[player] or -math.huge) < T.nextCooldown then
			return
		end
		lastNext[player] = now
		setStep(player, tu.step + 1, tu.step + 1 > #T.steps, "next")
	elseif what == "skip" then
		if not tu.done then
			setStep(player, tu.step, true, "skip")
		end
	elseif what == "replay" then
		if tu.done then
			setStep(player, 1, false, "replay")
		end
	end
end

-- ---------- Bo's model ----------
local function weld(part: BasePart, to: BasePart, at: CFrame)
	part.CFrame = to.CFrame * at
	part.Anchored = false
	part.CanCollide, part.CanQuery, part.CanTouch, part.CastShadow, part.Massless = false, false, false, true, true
	local w = Instance.new("WeldConstraint")
	w.Part0, w.Part1 = to, part
	w.Parent = part
end

local function piece(model: Model, name: string, shape: Enum.PartType, size: Vector3, color: Color3): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = shape
	p.Size = size
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	p.Parent = model
	return p
end

-- a ranger's hat and a scarf, made of parts (no catalog accessories, so nothing to license or load)
local function dress(model: Model)
	local C = Theme.tutorial
	local head = model:FindFirstChild("Head") :: BasePart?
	local chest = model:FindFirstChild("UpperTorso") :: BasePart?
	if head then
		local w = math.max(head.Size.X, head.Size.Z)
		local up = CFrame.Angles(0, 0, math.pi / 2) -- a cylinder's axis is X: stand it up
		local top = head.Size.Y * 0.42
		weld(piece(model, "HatBrim", Enum.PartType.Cylinder, Vector3.new(0.12, w * 1.85, w * 1.85), C.hat), head, CFrame.new(0, top, 0) * up)
		local crownH = head.Size.Y * 0.5
		weld(piece(model, "HatCrown", Enum.PartType.Cylinder, Vector3.new(crownH, w * 1.02, w * 1.02), C.hat), head, CFrame.new(0, top + crownH / 2, 0) * up)
		weld(piece(model, "HatBand", Enum.PartType.Cylinder, Vector3.new(crownH * 0.3, w * 1.06, w * 1.06), C.hatBand), head, CFrame.new(0, top + crownH * 0.2, 0) * up)
	end
	if chest then
		local s = chest.Size
		weld(piece(model, "Scarf", Enum.PartType.Block, Vector3.new(s.X * 0.8, 0.32, s.Z * 1.2), C.scarf), chest, CFrame.new(0, s.Y / 2 - 0.12, 0))
		weld(piece(model, "ScarfTail", Enum.PartType.Block, Vector3.new(0.38, 0.95, 0.14), C.scarf), chest, CFrame.new(s.X * 0.18, s.Y / 2 - 0.6, -s.Z * 0.62) * CFrame.Angles(0, 0, math.rad(-8)))
	end
end

local function buildGuide()
	if ReplicatedStorage:FindFirstChild(T.modelName) then
		return
	end
	local C = Theme.tutorial
	local ok, result = pcall(function()
		local desc = Instance.new("HumanoidDescription")
		desc.HeadColor, desc.LeftArmColor, desc.RightArmColor = C.skin, C.skin, C.skin
		desc.TorsoColor = C.coat
		desc.LeftLegColor, desc.RightLegColor = C.pants, C.pants
		return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
	end)
	if not ok or typeof(result) ~= "Instance" or not result:IsA("Model") then
		warn(`[TutorialService] couldn't build Ranger Bo: {result}`) -- the tutorial still runs, just without him
		return
	end
	local model = result :: Model
	model.Name = T.modelName
	local hum = model:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None -- his name is our own pill (TutorialNpc)
		hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BaseScript") then
			d:Destroy() -- the default Animate script: the client plays his animations itself
		elseif d:IsA("BasePart") then
			d.CanCollide, d.CanQuery, d.CanTouch = false, false, false -- never blocks you, never takes a ray
		end
	end
	dress(model)
	model.PrimaryPart = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	model.Parent = ReplicatedStorage
end

function TutorialService.Init() end

function TutorialService.Start()
	Remotes.on("Tutorial", onTutorial)
	Players.PlayerRemoving:Connect(function(p)
		lastNext[p] = nil
	end)
	task.spawn(buildGuide) -- CreateHumanoidModelFromDescription waits on Roblox's servers
end

return TutorialService
