--!strict
-- PetVisuals: draws the pets on the server's invisible PetRoot parts and inside carried cubes.
-- A model from ReplicatedStorage.PetModels when it's uploaded, else a stand-in in the pet's colour
-- with its name. The action (yawn, jump, dance, sneeze) plays from the root's Action attribute, at
-- half speed while held; dazed pets spin. Other players' personal rares are hidden: no model and the
-- prompt turned off on this client (the server refuses them anyway). Also draws the Super Freeze
-- button next to your own melted Rare+ pet: small, in the world, no countdown.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Theme = require(ReplicatedStorage.Shared.Theme)
local PetDefs = require(ReplicatedStorage.Shared.PetDefs)
local Ui = require(script.Parent.Parent.Lib.Ui)
local State = require(script.Parent.State)
local InputController = require(script.Parent.InputController)
local SettingsController = require(script.Parent.SettingsController)
local CameraController = require(script.Parent.CameraController)

local PetVisuals = {}
local me = Players.LocalPlayer
local drawn: { [BasePart]: { model: PVInstance, height: number, offer: BillboardGui? } } = {}
local cubes: { [BasePart]: PVInstance } = {}
local folder: Folder

local function standIn(def: PetDefs.PetDef, size: number): PVInstance
	local models = ReplicatedStorage:FindFirstChild("PetModels")
	local m = models and models:FindFirstChild(def.model)
	if m and m:IsA("Model") then
		local clone = m:Clone()
		clone:ScaleTo(size / math.max(0.1, clone:GetExtentsSize().Y))
		for _, d in clone:GetDescendants() do
			if d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide = false
				d.CanQuery = false
				if table.find(def.glowParts, d.Name) then
					d.Material = Enum.Material.Neon
				end
			end
		end
		return clone
	end
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	if def.icon ~= "" then
		-- the painted sprite, always facing the camera (prototype): an invisible anchor carries it
		p.Size = Vector3.one * size
		p.Transparency = 1
		local g = Instance.new("BillboardGui")
		g.Name = "Sprite"
		g.Size = UDim2.fromScale(size * Config.ui.petSpriteScale, size * Config.ui.petSpriteScale)
		g.LightInfluence = 0
		g.Adornee = p
		g.Parent = p
		local img = Instance.new("ImageLabel")
		img.BackgroundTransparency = 1
		img.Size = UDim2.fromScale(1, 1)
		img.Image = def.icon
		img.Parent = g
		return p
	end
	p.Shape = Enum.PartType.Ball
	p.Size = Vector3.new(size, size, size)
	p.Color = def.color
	p.Material = Enum.Material.SmoothPlastic
	return p
end

local function nameTag(parent: Instance, def: PetDefs.PetDef, height: number)
	local g = Instance.new("BillboardGui")
	g.Size = UDim2.fromScale(4, 1)
	g.StudsOffset = Vector3.new(0, height / 2 + 0.8, 0)
	g.MaxDistance = 60
	local t = Ui.label(g, def.name)
	t.TextColor3 = Theme.tiers[def.tier] or Theme.white
	g.Parent = parent
end

local function offerButton(root: BasePart): BillboardGui
	local g = Instance.new("BillboardGui")
	g.Name = "SuperFreeze"
	g.Size = UDim2.fromScale(5, 1.4)
	g.StudsOffset = Vector3.new(3.5, 1, 0)
	g.AlwaysOnTop = true
	g.Active = true
	g.Adornee = root
	local charges = if State.view then State.view.superFreezeCharges else 0
	local label = if charges > 0 then `Super Freeze ({charges} left)` else `Super Freeze {Config.monetization.superFreeze.robux} R$`
	Ui.block(g, "Button", Theme.iceDeep, label, function()
		State.send("RequestSuperFreeze", root:GetAttribute("PetId"))
	end).root.Size = UDim2.fromScale(1, 1)
	g.Parent = me:WaitForChild("PlayerGui")
	return g
end

local function hiddenFromMe(root: BasePart): boolean
	local owner = root:GetAttribute("OwnerUserId")
	return typeof(owner) == "number" and owner ~= 0 and owner ~= me.UserId
end

local function addPet(root: Instance)
	if not root:IsA("BasePart") or drawn[root] then
		return
	end
	local def = PetDefs.get(root:GetAttribute("PetKey") :: string)
	if not def then
		return
	end
	if hiddenFromMe(root) then
		local prompt = root:FindFirstChildWhichIsA("ProximityPrompt", true)
		if prompt then
			prompt.Enabled = false -- someone else's personal rare: not here for you
		end
		return
	end
	local h = PetDefs.sizeHeight[def.size]
	local model = standIn(def, h)
	model.Parent = folder
	nameTag(model, def, h)
	drawn[root] = { model = model, height = h, offer = nil }
end

local function removePet(root: Instance)
	local d = drawn[root :: BasePart]
	if d then
		d.model:Destroy()
		if d.offer then
			d.offer:Destroy()
		end
		drawn[root :: BasePart] = nil
	end
end

local function addCube(part: Instance)
	if not part:IsA("BasePart") or cubes[part] then
		return
	end
	local def = PetDefs.get(part:GetAttribute("PetKey") :: string)
	if not def then
		return
	end
	local model = standIn(def, part.Size.Y * 0.6)
	model.Parent = folder
	cubes[part] = model
end

local function removeCube(part: Instance)
	local m = cubes[part :: BasePart]
	if m then
		m:Destroy()
		cubes[part :: BasePart] = nil
	end
end

-- the pose as motion: a hop, a wiggle, a stretch or a shake (smaller with reduced motion)
local function poseOffset(root: BasePart, t: number): CFrame
	local action = root:GetAttribute("Action")
	local reduced = SettingsController.get("reducedMotion") == true
	local amp = if reduced then 0.3 else 1
	local speed = if root:GetAttribute("Held") then 1 - Config.zapSlowdown else 1
	local x = t * speed
	if root:GetAttribute("State") == "dazed" then
		return CFrame.Angles(0, x * 4 * amp, 0)
	elseif action == "jump" then
		return CFrame.new(0, math.abs(math.sin(x * 6)) * 1.2 * amp, 0)
	elseif action == "dance" then
		return CFrame.Angles(0, 0, math.sin(x * 8) * 0.35 * amp)
	elseif action == "yawn" then
		return CFrame.Angles(-0.25 * amp, 0, 0)
	elseif action == "sneeze" then
		return CFrame.new(math.sin(x * 40) * 0.15 * amp, 0, 0)
	end
	return CFrame.new(0, math.sin(x * 2) * 0.08 * amp, 0)
end

local function nearestOffer(): BasePart?
	for root, d in drawn do
		if d.offer then
			return root
		end
	end
	return nil
end

local function step()
	local t = os.clock()
	local mine = 0
	for root, d in drawn do
		if not root.Parent then
			removePet(root)
			continue
		end
		d.model:PivotTo(root.CFrame * poseOffset(root, t))
		local offerFor = root:GetAttribute("OfferUserId")
		local wantOffer = offerFor == me.UserId and root:GetAttribute("State") == "dazed"
		if wantOffer and not d.offer then
			d.offer = offerButton(root)
		elseif not wantOffer and d.offer then
			d.offer:Destroy()
			d.offer = nil
		end
	end
	for part, m in cubes do
		if not part.Parent then
			removeCube(part)
			continue
		end
		m:PivotTo(part.CFrame)
		if part:GetAttribute("OwnerUserId") == me.UserId then
			mine += 1
		end
		-- the cube shows time left: it clears up as it melts and flashes near the end (no timer)
		local frac = part:GetAttribute("LifeFrac")
		if typeof(frac) == "number" and not part:GetAttribute("SuperFrozen") then
			local flash = frac < 0.25 and math.sin(t * 12) > 0
			part.Transparency = 0.45 + (1 - frac) * 0.35
			part.Color = if flash then Theme.no else Theme.ice
		end
	end
	CameraController.setCarrying(mine > 0)
end

local function watch(name: string, add: (Instance) -> (), remove: (Instance) -> ())
	task.spawn(function()
		local f = workspace:WaitForChild(name, 30)
		if not f then
			return
		end
		f.ChildAdded:Connect(function(c)
			task.defer(add, c) -- attributes arrive with the part
		end)
		f.ChildRemoved:Connect(remove)
		for _, c in f:GetChildren() do
			add(c)
		end
	end)
end

function PetVisuals.Init()
	folder = Instance.new("Folder")
	folder.Name = "PetVisuals"
	folder.Parent = workspace
end

function PetVisuals.Start()
	watch("WildPets", addPet, removePet)
	watch("PenPets", addPet, removePet) -- everyone's pen pets (no prompt; they just idle in the pen)
	watch("Cubes", addCube, removeCube)
	RunService.RenderStepped:Connect(step)
	InputController.Action:Connect(function(a: string)
		if a == "superFreeze" then
			local root = nearestOffer()
			if root then
				State.send("RequestSuperFreeze", root:GetAttribute("PetId"))
			end
		end
	end)
end

return PetVisuals
