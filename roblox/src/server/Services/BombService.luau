--!strict
-- BombService (owner 2026-11-19, vault Games/Ice Ray for Pets/PvP Plan): Frost Bombs. Bought once at the Equipment
-- Booth (Config.gear frost_bombs), held from hotbar slot 2 (GearService "bomb"); a click or tap places one at your
-- feet (PlaceBomb). At most Config.bombs.max out (one more replaces your oldest), each lasts `life` seconds.
-- A player CARRYING a cube (TagService.taggable: not shielded, not in the hub, not on the first tutorial lesson)
-- who comes near someone else's bomb is frozen for freezeMax s (tapping breaks out down to freezeMin, TagService)
-- and drops the cube for anyone to grab (CarryService.dropOpen). Empty-handed players walk over them safely.
-- Shooting a bomb with the ray pops it (a FreezeService target, kind "bomb"). Islands only.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local WorldRules = require(ReplicatedStorage.Shared.WorldRules)
local Remotes = require(script.Parent.Remotes)
local DataService = require(script.Parent.DataService)
local PlayerTracker = require(script.Parent.PlayerTracker)
local CarryService = require(script.Parent.CarryService)
local FreezeService = require(script.Parent.FreezeService)
local GearService = require(script.Parent.GearService)
local TagService = require(script.Parent.TagService)
local TutorialService = require(script.Parent.TutorialService)

local BombService = {}
local B = Config.bombs
type Bomb = { id: string, owner: Player, pos: Vector3, untilT: number, part: BasePart, hitsOwner: boolean? }
local bombs: { [string]: Bomb } = {}
local lastPlace: { [Player]: number } = {}
local nextId = 1
local folder: Folder

local function owns(p: Player): boolean
	local d = DataService.get(p)
	local lv = d and d.gear.frost_bombs
	return typeof(lv) == "number" and lv > 0
end

local function pop(b: Bomb, loud: boolean)
	if bombs[b.id] ~= b then
		return
	end
	bombs[b.id] = nil
	b.part:Destroy()
	if loud then
		Remotes.fireAll("Notify", "bombPop", { at = b.pos }) -- every client: a puff of snow there (and its sound)
	end
end

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

-- the model matches its painted icon (owner 2026-11-19, icons/gear_frost_bombs.png): a deep-blue glass orb with a
-- swirling glow and ice shards inside, a dark slate band with diamond gems and silver studs round the middle, a
-- snowflake on top. ~22 parts, all anchored, no collisions. The ring on the ground shows the trigger radius
-- (World Rules: hazards you can see). The orb (root) is the ray's target, so it stays a BasePart.
local function build(id: string, at: Vector3, owner: Player): BasePart
	local S, r = B.size, B.size / 2
	local c = CFrame.new(at + Vector3.new(0, r + 0.1, 0))
	local Ball, Block, Cyl = Enum.PartType.Ball, Enum.PartType.Block, Enum.PartType.Cylinder
	-- deep blue like the icon (a lighter glass read white on snow in the play test)
	local core = piece("FrostBomb", Ball, Vector3.one * S, c, Color3.fromRGB(40, 110, 235), Enum.Material.Glass, 0.35)
	piece("Glow", Ball, Vector3.one * S * 0.82, c, Color3.fromRGB(15, 75, 210), Enum.Material.Neon, 0.1, core)
	piece("Swirl", Ball, Vector3.new(S * 0.45, S * 0.86, S * 0.86), c * CFrame.Angles(0, 0.6, 0.5), Color3.fromRGB(90, 200, 255), Enum.Material.Neon, 0.5, core)
	for k, v in { Vector3.new(0.45, 0.4, -0.3), Vector3.new(0.3, -0.5, -0.45), Vector3.new(-0.5, 0.15, 0.4) } do
		piece("Shard", Block, Vector3.new(0.12, 0.34, 0.12), c * CFrame.new(v * r) * CFrame.Angles(0.4 * k, k, 0.7), Color3.fromRGB(220, 245, 255), Enum.Material.Neon, 0.1, core)
	end
	-- the band, its 4 gems and 4 studs
	local band = c * CFrame.new(0, -0.06, 0)
	piece("Band", Cyl, Vector3.new(S * 0.2, S * 1.05, S * 1.05), band * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(50, 56, 84), Enum.Material.SmoothPlastic, 0, core)
	local rr = S * 0.525
	for i = 0, 3 do
		local out = band * CFrame.Angles(0, i * math.pi / 2, 0) * CFrame.new(0, 0, -rr)
		piece("GemFrame", Block, Vector3.new(0.52, 0.52, 0.14), out * CFrame.Angles(0, 0, math.pi / 4), Color3.fromRGB(28, 32, 58), Enum.Material.SmoothPlastic, 0, core)
		piece("Gem", Block, Vector3.new(0.32, 0.32, 0.12), out * CFrame.new(0, 0, -0.06) * CFrame.Angles(0, 0, math.pi / 4), Color3.fromRGB(80, 190, 255), Enum.Material.Neon, 0, core)
		local mid = band * CFrame.Angles(0, (i + 0.5) * math.pi / 2, 0) * CFrame.new(0, 0, -rr)
		piece("Stud", Block, Vector3.new(0.26, 0.26, 0.12), mid * CFrame.Angles(0, 0, math.pi / 4), Color3.fromRGB(225, 232, 245), Enum.Material.Metal, 0, core)
	end
	-- the snowflake on top: 3 crossed arms with diamond tips
	local dir = Vector3.new(-0.45, 0.8, -0.4).Unit
	local top = CFrame.lookAt(c.Position + dir * (r + 0.02), c.Position + dir * (r + 1))
	local white = Color3.fromRGB(235, 250, 255)
	for k = 0, 2 do
		local arm = top * CFrame.Angles(0, 0, k * math.pi / 3)
		piece("Flake", Block, Vector3.new(0.12, 1, 0.05), arm, white, Enum.Material.SmoothPlastic, 0, core) -- not Neon: it bloomed into a blob
		for _, e in { 0.5, -0.5 } do
			piece("FlakeTip", Block, Vector3.new(0.2, 0.2, 0.05), arm * CFrame.new(0, e, 0) * CFrame.Angles(0, 0, math.pi / 4), white, Enum.Material.SmoothPlastic, 0, core)
		end
	end
	core:SetAttribute("BombId", id)
	core:SetAttribute("OwnerUserId", owner.UserId)
	local ring = Instance.new("Part")
	ring.Name = "Ring"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.15, B.radius * 2, B.radius * 2)
	ring.CFrame = CFrame.new(at + Vector3.new(0, 0.12, 0)) * CFrame.Angles(0, 0, math.pi / 2)
	ring.Material = Enum.Material.SmoothPlastic
	ring.Color = B.ringColor
	ring.Transparency = 0.15
	ring.Anchored, ring.CanCollide, ring.CanQuery, ring.CanTouch, ring.CastShadow = true, false, false, false, false
	ring.Parent = core
	local light = Instance.new("PointLight")
	light.Color = B.color
	light.Range = 10
	light.Brightness = 1.5
	light.Parent = core
	return core
end

local function onPlace(player: Player)
	local pos = PlayerTracker.position(player)
	if not pos or GearService.held(player) ~= "bomb" or not owns(player) then
		return
	end
	if WorldRules.inHub(pos) or WorldRules.zoneAt(pos) < 1 or TutorialService.learning(player) then
		Remotes.notYet(player, "Frost Bombs work out on the islands", "hotbar")
		return
	end
	local now = os.clock()
	if now - (lastPlace[player] or -math.huge) < B.cooldown then
		return
	end
	-- one more than the max: your oldest goes
	local mine: { Bomb } = {}
	for _, b in bombs do
		if b.owner == player then
			table.insert(mine, b)
		end
	end
	if #mine >= B.max then
		table.sort(mine, function(a, b)
			return a.untilT < b.untilT
		end)
		for i = 1, #mine - B.max + 1 do
			pop(mine[i], true)
		end
	end
	lastPlace[player] = now
	-- on the ground under you
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local skip: { Instance } = { folder }
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(skip, p.Character)
		end
	end
	params.FilterDescendantsInstances = skip
	local hit = workspace:Raycast(pos + Vector3.new(0, 2, 0), Vector3.new(0, -30, 0), params)
	local at = if hit then hit.Position else pos - Vector3.new(0, 3, 0)
	local id = "b" .. nextId
	nextId += 1
	local part = build(id, at, player)
	part.Parent = folder
	bombs[id] = { id = id, owner = player, pos = at, untilT = now + B.life, part = part }
	Remotes.fire(player, "Notify", "bombPlaced", { cooldown = B.cooldown, left = B.max - math.min(#mine + 1, B.max) })
end

local function trigger(b: Bomb, victim: Player)
	local key = CarryService.dropOpen(victim)
	TagService.freeze(victim, B.freezeMax, B.freezeMin)
	pop(b, true)
	Remotes.fire(victim, "Notify", "bombFrozen", { seconds = B.freezeMax, by = b.owner.DisplayName, key = key })
	if b.owner.Parent then
		Remotes.fire(b.owner, "Notify", "bombHit", { name = victim.DisplayName, key = key })
	end
end

-- Studio play tests only (TesterService's TesterHook): a bomb 8 studs ahead of you that also hits you
function BombService.testBomb(player: Player): string?
	local root = PlayerTracker.rootPart(player)
	if not root or not game:GetService("RunService"):IsStudio() then
		return nil
	end
	local at = root.Position + root.CFrame.LookVector * 8 - Vector3.new(0, 3, 0)
	local id = "b" .. nextId
	nextId += 1
	local part = build(id, at, player)
	part.Parent = folder
	bombs[id] = { id = id, owner = player, pos = at, untilT = os.clock() + B.life, part = part, hitsOwner = true }
	return id
end

function BombService.Init()
	folder = Instance.new("Folder")
	folder.Name = "FrostBombs"
	folder.Parent = workspace
end

function BombService.Start()
	Remotes.on("PlaceBomb", onPlace)
	FreezeService.registerTarget("bomb", {
		pos = function(id: string): Vector3?
			local b = bombs[id]
			return if b then b.pos else nil
		end,
		canAim = function(shooter: Player, id: string): boolean
			local from = PlayerTracker.position(shooter)
			return bombs[id] ~= nil and from ~= nil and shooter:GetAttribute("Tagged") ~= true
		end,
		tick = function(_shooter: Player, id: string, _dt: number, _gun: number)
			local b = bombs[id]
			if b then
				pop(b, true) -- one zap and it bursts into harmless snow
			end
		end,
	})
	Players.PlayerRemoving:Connect(function(p)
		lastPlace[p] = nil
		for _, b in bombs do
			if b.owner == p then
				pop(b, false)
			end
		end
	end)
	task.spawn(function()
		while true do
			task.wait(0.1)
			local now = os.clock()
			for _, b in bombs do
				if now >= b.untilT then
					pop(b, false)
					continue
				end
				for _, p in Players:GetPlayers() do
					if p == b.owner and not b.hitsOwner then
						continue
					end
					local pos = PlayerTracker.position(p)
					if pos and math.abs(pos.Y - b.pos.Y) < 6
						and Vector3.new(pos.X - b.pos.X, 0, pos.Z - b.pos.Z).Magnitude <= B.radius and TagService.taggable(p) then
						trigger(b, p)
						break
					end
				end
			end
		end
	end)
end

return BombService
