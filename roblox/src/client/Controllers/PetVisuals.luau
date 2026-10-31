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
type Fx = { core: Part, ring: BasePart?, shadow: BasePart, stars: { BasePart } }
type Drawn = { model: PVInstance, height: number, offer: BillboardGui?, img: ImageLabel?, born: number, fx: Fx }
type CubeLook = { model: PVInstance, edges: SelectionBox, cracks: { { part: BasePart, offset: CFrame } } }
local drawn: { [BasePart]: Drawn } = {}
local cubes: { [BasePart]: CubeLook } = {}
local folder: Folder
local P = Config.petFx
local meshes: Instance? = nil

local function fxPart(size: Vector3, color: Color3, parent: Instance, mesh: string?): BasePart
	local template = mesh and meshes and meshes:FindFirstChild(mesh)
	local p: BasePart = if template and template:IsA("MeshPart") then template:Clone() else Instance.new("Part")
	p.Size = size
	p.Color = color
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Parent = parent
	return p
end

local function sparkles(parent: Instance, color: Color3, rate: number): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Color = ColorSequence.new(color)
	e.LightEmission = 0.8
	e.Rate = rate
	e.Speed = NumberRange.new(0.5, 1.5)
	e.Lifetime = NumberRange.new(0.5, 0.9)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Size = NumberSequence.new(0.25, 0)
	e.Parent = parent
	return e
end

local function standIn(def: PetDefs.PetDef, size: number): (PVInstance, ImageLabel?)
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
		img.AnchorPoint = Vector2.new(0.5, 1) -- squash and stretch from the feet (prototype poses)
		img.Position = UDim2.fromScale(0.5, 1)
		img.Size = UDim2.fromScale(1, 1)
		img.Image = def.icon
		img.Parent = g
		return p, img
	end
	p.Shape = Enum.PartType.Ball
	p.Size = Vector3.new(size, size, size)
	p.Color = def.color
	p.Material = Enum.Material.SmoothPlastic
	return p, nil
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
	local model, img = standIn(def, h)
	model.Parent = folder
	nameTag(model, def, h)
	-- prototype syncWild: a soft shadow, a glowing ring in the tier's colour (wild pets only),
	-- dazed stars, sparkles round Rare and up, snowflakes round Frosty pets
	local wild = root:GetAttribute("PenOwner") == nil
	local color = Theme.tiers[def.tier] or Theme.white
	local core = fxPart(Vector3.one * 0.2, color, folder) :: Part
	core.Transparency = 1
	local shadow = fxPart(Vector3.new(0.1, h * P.shadowScale, h * P.shadowScale), Theme.fx.shadow, folder)
	shadow.Shape = Enum.PartType.Cylinder
	shadow.Transparency = 0.7
	local ring = if wild then fxPart(Vector3.new(h * P.ringScale, 0.15, h * P.ringScale), color, folder, "Ring") else nil
	if ring then
		ring.Material = Enum.Material.Neon
		ring.Transparency = 0.25
		if Config.tier(def.tier).rank >= 3 then
			sparkles(ring, color, P.rareSparkleRate)
		end
	end
	local stars: { BasePart } = {}
	for _ = 1, P.starCount do
		local s = fxPart(Vector3.new(0.35, 0.5, 0.35), Theme.fx.star, folder, "Octa")
		s.Material = Enum.Material.Neon
		s.Transparency = 1
		table.insert(stars, s)
	end
	if root:GetAttribute("Mut") == "Frosty" then
		sparkles(core, Theme.fx.frost, P.frostySparkleRate)
	end
	drawn[root] = { model = model, height = h, offer = nil, img = img, born = os.clock(), fx = { core = core, ring = ring, shadow = shadow, stars = stars } }
end

local function removePet(root: Instance)
	local d = drawn[root :: BasePart]
	if d then
		d.model:Destroy()
		if d.offer then
			d.offer:Destroy()
		end
		d.fx.core:Destroy()
		d.fx.shadow:Destroy()
		if d.fx.ring then
			d.fx.ring:Destroy()
		end
		for _, s in d.fx.stars do
			s:Destroy()
		end
		drawn[root :: BasePart] = nil
	end
end

-- prototype crackGeo: a few zig-zag cracks on three faces, shown when the cube is nearly gone
local function makeCracks(part: BasePart): { { part: BasePart, offset: CFrame } }
	local out = {}
	local s = part.Size.X
	local r = Random.new()
	for i = 1, P.crackLines do
		local face = i % 3
		local a, b = (r:NextNumber() - 0.5) * 0.6, (r:NextNumber() - 0.5) * 0.6
		for _ = 1, 3 do
			local na, nb = a + (r:NextNumber() - 0.5) * 0.35, b + (r:NextNumber() - 0.5) * 0.35
			local function onFace(u: number, v: number): Vector3
				return (if face == 0 then Vector3.new(u, v, 0.51) elseif face == 1 then Vector3.new(0.51, u, v) else Vector3.new(u, 0.51, v)) * s
			end
			local p0, p1 = onFace(a, b), onFace(na, nb)
			local seg = fxPart(Vector3.new(0.05, 0.05, math.max(0.05, (p1 - p0).Magnitude)), Theme.white, folder)
			seg.Material = Enum.Material.Neon
			seg.Transparency = 1
			table.insert(out, { part = seg, offset = CFrame.lookAt((p0 + p1) / 2, p1) })
			a, b = na, nb
		end
	end
	return out
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
	-- white ice edges (prototype frame lines)
	local edges = Instance.new("SelectionBox")
	edges.Adornee = part
	edges.Color3 = Theme.white
	edges.LineThickness = 0.04
	edges.Transparency = P.edgeTransparency
	edges.SurfaceTransparency = 1
	edges.Parent = folder
	cubes[part] = { model = model, edges = edges, cracks = makeCracks(part) }
end

local function removeCube(part: Instance)
	local c = cubes[part :: BasePart]
	if c then
		c.model:Destroy()
		c.edges:Destroy()
		for _, k in c.cracks do
			k.part:Destroy()
		end
		cubes[part :: BasePart] = nil
	end
end

-- prototype applyPose for a sprite: squash, stretch and tilt (rotation in degrees)
local function spritePose(root: BasePart, t: number): (number, number, number)
	local action = root:GetAttribute("Action")
	local amp = if SettingsController.get("reducedMotion") == true then 0.3 else 1
	if root:GetAttribute("State") == "dazed" then
		return 1, 1, math.deg(math.sin(t * 3) * 0.15) * amp
	elseif action == "yawn" then
		return 0.94, 1.16, -5 * amp
	elseif action == "jump" then
		local u = (t % 0.9) / 0.9
		return if u < 0.15 then 1.12 else 0.94, if u < 0.15 then 0.85 else 1.1, 0
	elseif action == "dance" then
		return 1, 1, math.deg(math.sin(t * 10) * 0.28) * amp
	elseif action == "sneeze" then
		return 1.16, 0.82, 8 * amp
	end
	return 1, 1 + math.sin(t * 6) * 0.02 * amp, 0
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
		local dazed = root:GetAttribute("State") == "dazed"
		if d.img then
			-- a sprite always faces the camera: only the hop/shake moves it, the pose squashes it
			d.model:PivotTo(CFrame.new((root.CFrame * poseOffset(root, t)).Position))
			local sx, sy, rot = spritePose(root, t)
			local pop = math.min(1, (t - d.born) / P.popSeconds)
			local grow = if pop < 1 then pop * 1.08 else 1
			d.img.Size = UDim2.fromScale(sx * grow, sy * grow)
			d.img.Rotation = rot
		else
			d.model:PivotTo(root.CFrame * poseOffset(root, t))
		end
		local ground = root.Position - Vector3.new(0, root.Size.Y / 2, 0)
		d.fx.core.Position = root.Position
		d.fx.shadow.CFrame = CFrame.new(ground + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.pi / 2)
		if d.fx.ring then
			d.fx.ring.CFrame = CFrame.new(ground + Vector3.new(0, 0.14, 0)) * CFrame.Angles(0, t * P.ringSpin, 0)
			d.fx.ring.Transparency = 0.3 + math.sin(t * 4) * 0.12
		end
		for i, s in d.fx.stars do
			local a = t * P.starSpin + i * (math.pi * 2 / #d.fx.stars)
			s.Transparency = if dazed then 0 else 1
			s.CFrame = CFrame.new(root.Position + Vector3.new(math.cos(a) * P.starRadius, d.height * (P.starHeight - 0.5), math.sin(a) * P.starRadius)) * CFrame.Angles(0, a, 0)
		end
		local offerFor = root:GetAttribute("OfferUserId")
		local wantOffer = offerFor == me.UserId and root:GetAttribute("State") == "dazed"
		if wantOffer and not d.offer then
			d.offer = offerButton(root)
		elseif not wantOffer and d.offer then
			d.offer:Destroy()
			d.offer = nil
		end
	end
	for part, c in cubes do
		if not part.Parent then
			removeCube(part)
			continue
		end
		c.model:PivotTo(part.CFrame)
		if part:GetAttribute("OwnerUserId") == me.UserId then
			mine += 1
		end
		-- the cube shows time left: it clears up as it melts, cracks, then flashes near the end (no timer)
		local frac = part:GetAttribute("LifeFrac")
		local superFrozen = part:GetAttribute("SuperFrozen") == true
		local cracked = typeof(frac) == "number" and frac < P.crackBelow and not superFrozen
		if superFrozen then
			part.Color = Theme.fx.superFrozen
		elseif typeof(frac) == "number" then
			local flash = frac < 0.25 and math.sin(t * 12) > 0
			part.Transparency = 0.45 + (1 - frac) * 0.35
			part.Color = if flash then Theme.no else Theme.ice
		end
		for _, k in c.cracks do
			k.part.Transparency = if cracked then 0.1 else 1
			if cracked then
				k.part.CFrame = part.CFrame * k.offset
			end
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
	meshes = ReplicatedStorage:FindFirstChild("SceneryMeshes")
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
