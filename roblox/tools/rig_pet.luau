-- rig_pet.luau: turn an imported split pet (split_pet.py -> Studio Import 3D, model named <key> in Workspace)
-- into a PetModels entry PetVisuals can animate. Run with execute_luau (Edit) after setting KEY / HANG / GLOW:
--   local KEY, HANG, GLOW = "dunehorn_ram", true, nil   -- prepended by the caller
-- Parts come named Body, Head, EarL/EarR, FrillL/FrillR (+ FrillGlowL/R), Tail, LegFL/FR/BL/BR (L = the pet's
-- left = Roblox -X). Sets: 1 stud tall, pivot at the box centre, anchored, DoubleSided, and the rig attributes
-- (Role, Hip/Swing/Front/Side for legs, Pivot for head/ears/tail). GLOW = { color, light = Color3 } makes every
-- *Glow* part an untextured Neon piece (it really glows) with sparkles, plus a warm light at the head.
local KEY: string, HANG: boolean, GLOW: any = ...

local src = workspace:FindFirstChild(KEY)
assert(src and src:IsA("Model"), "no imported model " .. KEY .. " in Workspace")
local pets = game:GetService("ReplicatedStorage"):FindFirstChild("PetModels")
assert(pets, "no PetModels")

-- flatten: the importer nests each mesh in "<Name>_Node" models
local model = Instance.new("Model")
model.Name = KEY
local parts: { [string]: MeshPart } = {}
for _, d in src:GetDescendants() do
	if d:IsA("MeshPart") then
		local n = d.Name:gsub("_Node$", ""):gsub("_mesh$", "")
		if n == "" or n == "MeshPart" or n:find("^Mesh") then
			n = (d.Parent :: Instance).Name:gsub("_Node$", "")
		end
		d.Name = n
		d.Parent = model
		parts[n] = d
	end
end
assert(parts.Body and parts.Head, "missing Body/Head")
model.Parent = workspace
src:Destroy()

-- 1 stud tall, pivot at the box centre
local cf, size = model:GetBoundingBox()
model.WorldPivot = CFrame.new(cf.Position)
model:ScaleTo(model:GetScale() / size.Y)
local pivot = model:GetPivot()

for _, p in model:GetChildren() do
	if p:IsA("MeshPart") then
		p.Anchored = true
		p.CanCollide = false
		p.DoubleSided = true
	end
end

local function box(p: BasePart): (Vector3, Vector3) -- centre and size in model space (parts aren't rotated)
	return pivot:PointToObjectSpace(p.Position), p.Size
end
local headC = box(parts.Head)

for n, p in parts do
	local c, s = box(p)
	if n:match("^Leg") then
		local front = n:sub(4, 4) == "F"
		local left = n:sub(5, 5) == "L"
		p:SetAttribute("Role", "leg")
		p:SetAttribute("Front", front)
		p:SetAttribute("Side", if left then -1 else 1)
		-- diagonal pairs swing together (FL with BR)
		p:SetAttribute("Swing", if front == left then 1 else -1)
		p:SetAttribute("Hip", Vector3.new(c.X, c.Y + s.Y * 0.3, c.Z))
	elseif n == "Head" then
		p:SetAttribute("Role", "head")
		p:SetAttribute("Pivot", Vector3.new(0, c.Y - s.Y * 0.3, c.Z + s.Z * 0.2)) -- the neck: low and toward the back
	elseif n:match("^Ear") or n:match("^Frill") then
		-- ears and frill halves twitch outward round the edge nearest the head
		local side = if n:sub(-1) == "L" then -1 else 1
		p:SetAttribute("Role", "ear")
		p:SetAttribute("Side", side)
		p:SetAttribute("Hang", HANG and n:match("^Ear") ~= nil)
		local inner = c.X - side * s.X * 0.42
		p:SetAttribute("Pivot", Vector3.new(inner, if n:match("^Frill") then headC.Y else c.Y - s.Y * 0.25, c.Z))
	elseif n:match("^Wing") then
		-- wings flap up and out together round the edge nearest the body, and don't turn with the head
		local side = if n:sub(-1) == "L" then -1 else 1
		p:SetAttribute("Role", "wing")
		p:SetAttribute("Side", side)
		p:SetAttribute("Pivot", Vector3.new(c.X - side * s.X * 0.45, c.Y, c.Z))
	elseif n:match("^Gem") then
		-- a small piece on the head (Solaris Sphinx's sun gem): rides on the head, no twitch of its own
		p:SetAttribute("Role", "ear")
		p:SetAttribute("Side", 0)
		p:SetAttribute("Pivot", c)
	elseif n:match("^Tail") then
		p:SetAttribute("Role", "tail")
		p:SetAttribute("Pivot", Vector3.new(c.X, c.Y + s.Y * 0.2, c.Z - s.Z * 0.45)) -- the root, at the body
	end
end

if GLOW then
	for n, p in parts do
		if n:find("Glow") then
			p.TextureID = ""
			p.Material = Enum.Material.Neon
			p.Color = GLOW.color
			local e = Instance.new("ParticleEmitter")
			e.Name = "Sparkles"
			e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
			e.Color = ColorSequence.new(GLOW.color)
			e.LightEmission = 1
			e.Rate = 3
			e.Lifetime = NumberRange.new(0.6, 1.1)
			e.Speed = NumberRange.new(0.2, 0.5)
			e.SpreadAngle = Vector2.new(180, 180)
			e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.3, 0.18), NumberSequenceKeypoint.new(1, 0) })
			e.Parent = p
		end
	end
	local at = Instance.new("Attachment")
	at.Name = "LightAt"
	at.Parent = parts.Head
	local l = Instance.new("PointLight")
	l.Color = GLOW.light
	l.Range = 6
	l.Brightness = 1.3
	l.Parent = at
end

-- next to the other pets in PetModels (they stand in a row 3 studs apart at y 300)
local old = pets:FindFirstChild(KEY)
if old then
	old:Destroy()
end
local x = 0
for _, m in pets:GetChildren() do
	if m:IsA("Model") then
		x = math.max(x, m:GetPivot().X)
	end
end
model:PivotTo(CFrame.new(x + 3, 300, 0))
model.Parent = pets
game:GetService("ChangeHistoryService"):SetWaypoint("Rig pet " .. KEY)

local out = { KEY .. " size " .. tostring(model:GetExtentsSize()) }
for n, p in parts do
	local s = n
	for k, v in p:GetAttributes() do
		s ..= " " .. k .. "=" .. (typeof(v) == "Vector3" and string.format("(%.3f,%.3f,%.3f)", v.X, v.Y, v.Z) or tostring(v))
	end
	table.insert(out, s)
end
return table.concat(out, "\n")
