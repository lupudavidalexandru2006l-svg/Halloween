--!strict
-- FrostBombModel: how a Frost Bomb looks, built from parts. Shared so the bomb on the ground (BombService) and
-- the one in your hand while the bombs are held (RayController, owner 2026-11-23) are the same thing.
-- It matches its painted icon (owner 2026-11-19, icons/gear_frost_bombs.png): a deep-blue glass orb with a
-- swirling glow and ice shards inside, a dark slate band with diamond gems and silver studs round the middle, a
-- snowflake on top. ~22 parts, all anchored, no collisions, all children of the orb (the root, `FrostBomb`).

local FrostBombModel = {}

local function piece(name: string, shape: Enum.PartType, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material, tr: number, parent: Instance?): Part
	local x = Instance.new("Part")
	x.Name = name
	x.Shape = shape
	x.Size = size
	x.CFrame = cf
	x.Color = color
	x.Material = mat
	x.Transparency = tr
	x.Anchored, x.CanCollide, x.CanQuery, x.CanTouch, x.CastShadow = true, false, false, false, false
	x.Parent = parent
	return x
end

-- the orb centred on `c`, `S` studs across; returns the orb with every other part inside it
function FrostBombModel.build(c: CFrame, S: number): Part
	local r = S / 2
	local k = S / 2.2 -- the details were sized for a 2.2-stud bomb
	local Ball, Block, Cyl = Enum.PartType.Ball, Enum.PartType.Block, Enum.PartType.Cylinder
	-- deep blue like the icon (a lighter glass read white on snow in the play test)
	local core = piece("FrostBomb", Ball, Vector3.one * S, c, Color3.fromRGB(40, 110, 235), Enum.Material.Glass, 0.35)
	piece("Glow", Ball, Vector3.one * S * 0.82, c, Color3.fromRGB(15, 75, 210), Enum.Material.Neon, 0.1, core)
	piece("Swirl", Ball, Vector3.new(S * 0.45, S * 0.86, S * 0.86), c * CFrame.Angles(0, 0.6, 0.5), Color3.fromRGB(90, 200, 255), Enum.Material.Neon, 0.5, core)
	for i, v in { Vector3.new(0.45, 0.4, -0.3), Vector3.new(0.3, -0.5, -0.45), Vector3.new(-0.5, 0.15, 0.4) } do
		piece("Shard", Block, Vector3.new(0.12, 0.34, 0.12) * k, c * CFrame.new(v * r) * CFrame.Angles(0.4 * i, i, 0.7), Color3.fromRGB(220, 245, 255), Enum.Material.Neon, 0.1, core)
	end
	-- the band, its 4 gems and 4 studs
	local band = c * CFrame.new(0, -0.06 * k, 0)
	piece("Band", Cyl, Vector3.new(S * 0.2, S * 1.05, S * 1.05), band * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(50, 56, 84), Enum.Material.SmoothPlastic, 0, core)
	local rr = S * 0.525
	for i = 0, 3 do
		local out = band * CFrame.Angles(0, i * math.pi / 2, 0) * CFrame.new(0, 0, -rr)
		piece("GemFrame", Block, Vector3.new(0.52, 0.52, 0.14) * k, out * CFrame.Angles(0, 0, math.pi / 4), Color3.fromRGB(28, 32, 58), Enum.Material.SmoothPlastic, 0, core)
		piece("Gem", Block, Vector3.new(0.32, 0.32, 0.12) * k, out * CFrame.new(0, 0, -0.06 * k) * CFrame.Angles(0, 0, math.pi / 4), Color3.fromRGB(80, 190, 255), Enum.Material.Neon, 0, core)
		local mid = band * CFrame.Angles(0, (i + 0.5) * math.pi / 2, 0) * CFrame.new(0, 0, -rr)
		piece("Stud", Block, Vector3.new(0.26, 0.26, 0.12) * k, mid * CFrame.Angles(0, 0, math.pi / 4), Color3.fromRGB(225, 232, 245), Enum.Material.Metal, 0, core)
	end
	-- the snowflake on top: 3 crossed arms with diamond tips
	local dir = c:VectorToWorldSpace(Vector3.new(-0.45, 0.8, -0.4).Unit)
	local top = CFrame.lookAt(c.Position + dir * (r + 0.02 * k), c.Position + dir * (r + k))
	local white = Color3.fromRGB(235, 250, 255)
	for i = 0, 2 do
		local arm = top * CFrame.Angles(0, 0, i * math.pi / 3)
		-- not Neon: it bloomed into a blob
		piece("Flake", Block, Vector3.new(0.12, 1, 0.05) * k, arm, white, Enum.Material.SmoothPlastic, 0, core)
		for _, e in { 0.5, -0.5 } do
			piece("FlakeTip", Block, Vector3.new(0.2, 0.2, 0.05) * k, arm * CFrame.new(0, e * k, 0) * CFrame.Angles(0, 0, math.pi / 4), white, Enum.Material.SmoothPlastic, 0, core)
		end
	end
	return core
end

return FrostBombModel
