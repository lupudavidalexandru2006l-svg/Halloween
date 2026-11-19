--!strict
-- CritterService (Round 5, owner 2026-11-02): Heat Critters on island Config.chasers.fromIsland and on.
-- Hot, cheeky animals that want your ice cube to cool off (never scary: they're after the cube, not
-- you). They wander like pets; when someone on their island carries a cube within aggroRange, the
-- nearest one runs after them (a bit slower than walking). Each critter stays on its own island, so
-- a long trip home is a relay: island 5's critters chase you to island 4's edge, then island 4's take
-- over (owner 2026-11-18: on every island now, faster and more of them the further out: Config.chasers.byIsland;
-- the hub is safe, and so is a kid still in the tutorial). A catch knocks your top cube loose and
-- its pet is dazed (only you can zap it back, like a melt). Shoot them with the ray to freeze them for
-- Config.chasers.frozenBase / the island's heat seconds. Slow Gel slows them too.
-- Each critter is an invisible anchored "Critter" part in workspace.Critters; clients draw it
-- (CritterVisuals) from its attributes: CritterId, Zone, PetKey, State (wander / chase / happy /
-- frozen), Meter, AimedBy, FrozenUntil.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local WorldRules = require(ReplicatedStorage.Shared.WorldRules)
local Remotes = require(script.Parent.Remotes)
local DataService = require(script.Parent.DataService)
local PlayerTracker = require(script.Parent.PlayerTracker)
local CarryService = require(script.Parent.CarryService)
local GearService = require(script.Parent.GearService)
local FreezeService = require(script.Parent.FreezeService)

local CritterService = {}
local C = Config.chasers
type Critter = {
	id: string, zone: number, root: Part, state: string, meter: number, pushedAt: number,
	untilT: number, wanderTo: Vector3?, target: Player?, lungeUntil: number, lungeReady: number,
}

-- this island's critters (Config.chasers.byIsland, owner 2026-11-18): how many, chase speed (studs/s), aggro
local function tuning(zone: number): (number, number, number)
	local t = C.byIsland[zone]
	if not t then
		return C.perIsland, C.chaseSpeed, C.aggroRange
	end
	return t.n, t.speed * Config.player.walkSpeed, t.aggro
end

-- kids still in the tutorial are never chased (they're learning to carry a cube home)
local function learning(p: Player): boolean
	local d = DataService.get(p)
	-- a replay doesn't count (2026-11-19 bug check: replaying the tutorial made you safe from critters until you
	-- finished it again); someone who already finished it once has the last lesson's reward paid
	local paid = d and d.tutorial and d.tutorial.paid
	return d ~= nil and d.tutorial ~= nil and not d.tutorial.done and not (paid and paid.done)
end
local critters: { [string]: Critter } = {}
local forced: { [number]: boolean } = {} -- tester: critters on an island before 3
local folder: Folder
local nextId = 1
local rng = Random.new()

local function setState(c: Critter, s: string)
	if c.state ~= s then
		c.state = s
		c.root:SetAttribute("State", s)
	end
end

local function setMeter(c: Critter, m: number, by: Player?)
	c.meter = m
	local step = Config.aim.step
	local shown = if m <= 0 then 0 else math.max(step, math.floor(m / step) * step)
	if c.root:GetAttribute("Meter") ~= shown then
		c.root:SetAttribute("Meter", shown)
	end
	local id = if by then by.UserId else 0
	if c.root:GetAttribute("AimedBy") ~= id then
		c.root:SetAttribute("AimedBy", id)
	end
end

local function spotIn(zone: number): Vector3?
	local z = Config.zone(zone)
	if not z then
		return nil
	end
	local half = Config.world.tunnel.width / 2 - Config.spawner.wallMargin
	for _ = 1, 20 do
		local at = Vector3.new(-half + rng:NextNumber() * half * 2, 0, z.zMin + 25 + rng:NextNumber() * math.max(1, z.zMax - z.zMin - 35))
		if WorldRules.zoneAt(at) == zone and WorldRules.inTunnel(at, Config.spawner.wallMargin) then
			return at
		end
	end
	return nil
end

local function spawnOne(zone: number): Critter?
	local at = spotIn(zone)
	if not at then
		return nil
	end
	local id = "k" .. nextId
	nextId += 1
	local root = Instance.new("Part")
	root.Name = "Critter"
	root.Size = Vector3.one * C.size
	root.CFrame = CFrame.new(at + Vector3.new(0, C.size / 2, 0))
	root.Anchored = true
	root.CanCollide = false
	root.CanTouch = false
	root.Transparency = 1
	local a = Instance.new("Attachment")
	a.Name = "Aim"
	a.Parent = root
	root:SetAttribute("CritterId", id)
	root:SetAttribute("Zone", zone)
	root:SetAttribute("PetKey", C.look[tostring(zone)] or C.look.pet)
	root:SetAttribute("State", "wander")
	root.Parent = folder
	local c: Critter = { id = id, zone = zone, root = root, state = "wander", meter = 0, pushedAt = 0, untilT = 0, wanderTo = nil, target = nil,
		lungeUntil = 0, lungeReady = 0 }
	critters[id] = c
	return c
end

local function wantsCritters(zone: number): boolean
	local z = Config.zone(zone)
	return (zone >= C.fromIsland and z ~= nil and z.ready) or forced[zone] == true -- Round 4 phase 6: not on "Coming soon" islands
end

-- the nearest player on this critter's island carrying a cube it could take (never in the hub; a Super Freeze
-- cube can't be knocked loose, so its carrier isn't chased, and a Critter Shield is never spent on it)
local function quarry(c: Critter): Player?
	local _, _, aggro = tuning(c.zone)
	local best, bestD = nil, aggro
	for _, p in Players:GetPlayers() do
		local pos = PlayerTracker.position(p)
		if pos and CarryService.knockable(p) and WorldRules.zoneAt(pos) == c.zone and not WorldRules.inHub(pos) and p:GetAttribute("Tagged") ~= true
			and not learning(p) then
			local d = (Vector3.new(pos.X, 0, pos.Z) - Vector3.new(c.root.Position.X, 0, c.root.Position.Z)).Magnitude
			if d < bestD then
				best, bestD = p, d
			end
		end
	end
	return best
end

-- one step toward a point, staying on its own island and inside the walls
local function stepToward(c: Critter, to: Vector3, speed: number, dt: number): boolean
	local from = c.root.Position
	local flat = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
	if flat.Magnitude < 0.05 then
		return false
	end
	local step = math.min(flat.Magnitude, speed * dt)
	local nextPos = from + flat.Unit * step
	if WorldRules.zoneAt(nextPos) ~= c.zone or not WorldRules.inTunnel(nextPos, Config.spawner.wallMargin) then
		return false -- the edge of its island: the relay hands you to the next island's critters
	end
	c.root.CFrame = CFrame.lookAt(nextPos, nextPos + flat.Unit)
	return true
end

local function tick(dt: number)
	local now = os.clock()
	for _, c in critters do
		-- nobody shooting it: the ice melts back
		if c.meter > 0 and c.state ~= "frozen" and now - c.pushedAt > 0.2 then
			setMeter(c, math.max(0, c.meter - Config.aim.thawPerSecond * dt), nil)
		end
		if c.state == "frozen" then
			if now >= c.untilT then
				setMeter(c, 0, nil)
				setState(c, "wander")
			end
			continue
		end
		if c.state == "happy" and now < c.untilT then
			continue -- cooling down on its prize
		end
		local slow = GearService.slowAt(c.root.Position) * (1 - c.meter) -- the ice on it slows it too
		local p = quarry(c)
		local pos = p and PlayerTracker.position(p)
		if p and pos then
			setState(c, "chase")
			local _, speed = tuning(c.zone)
			local gap = (Vector3.new(pos.X, 0, pos.Z) - Vector3.new(c.root.Position.X, 0, c.root.Position.Z)).Magnitude
			-- close up: a lunge (the clients see "Lunge" and stretch it forward)
			if gap <= C.lunge.range and now >= c.lungeReady then
				c.lungeUntil = now + C.lunge.seconds
				c.lungeReady = now + C.lunge.seconds + C.lunge.cooldown
				c.root:SetAttribute("Lunge", workspace:GetServerTimeNow())
			end
			if now < c.lungeUntil then
				speed *= C.lunge.mult
			end
			stepToward(c, pos, speed * slow, dt)
			local d = (Vector3.new(pos.X, 0, pos.Z) - Vector3.new(c.root.Position.X, 0, c.root.Position.Z)).Magnitude
			if d <= C.catchRange then
				-- a Critter Shield (bought, 2026-11-18) takes the catch: the critter still gets its happy cool-down
				local BoostService = require(script.Parent.BoostService) :: any
				if CarryService.knockable(p) and not BoostService.useShield(p) then
					local key = CarryService.knockOff(p, false)
					if key then
						Remotes.fire(p, "Notify", "critterCaught", { key = key })
					end
				end
				setState(c, "happy")
				c.untilT = now + C.afterCatch
			end
			continue
		end
		setState(c, "wander")
		if not c.wanderTo or not stepToward(c, c.wanderTo, C.wanderSpeed * slow, dt) then
			c.wanderTo = if rng:NextNumber() < 0.03 then spotIn(c.zone) else nil
		end
	end
	-- keep each critter island topped up (counted in one pass, not once per island)
	local count: { [number]: number } = {}
	for _, c in critters do
		count[c.zone] = (count[c.zone] or 0) + 1
	end
	for _, z in Config.world.zones do
		if wantsCritters(z.id) then
			if (count[z.id] or 0) < (tuning(z.id)) then
				spawnOne(z.id)
			end
		end
	end
end

-- tester tool: Heat Critters on this island too (islands 3+ aren't built yet); off removes them
function CritterService.force(zone: number, on: boolean)
	forced[zone] = on or nil
	if not on and zone < C.fromIsland then
		for id, c in critters do
			if c.zone == zone then
				c.root:Destroy()
				critters[id] = nil
			end
		end
	end
end

function CritterService.forced(zone: number): boolean
	return forced[zone] == true
end

function CritterService.Init()
	folder = Instance.new("Folder")
	folder.Name = "Critters"
	folder.Parent = workspace
end

function CritterService.Start()
	FreezeService.registerTarget("critter", {
		pos = function(id: string): Vector3?
			local c = critters[id]
			return if c then c.root.Position else nil
		end,
		canAim = function(_player: Player, id: string): boolean
			local c = critters[id]
			return c ~= nil and c.state ~= "frozen"
		end,
		tick = function(player: Player, id: string, dt: number, gun: number)
			local c = critters[id]
			if not c or c.state == "frozen" then
				return
			end
			c.pushedAt = os.clock()
			local d = DataService.get(player)
			-- like the island's pets: the further your Cold Power is above the island's need, the faster
			local seconds = if d and d.tester.instantFreeze then 0 else C.freezeSeconds / Config.freezeSpeed(if d then d.coldPower else 0, c.zone)
			local m = if seconds <= 0 then 1 else math.min(1, c.meter + dt / seconds)
			setMeter(c, m, player)
			if m >= 1 then
				-- frozen solid: hotter islands melt it sooner
				local z = Config.zone(c.zone)
				local heat = if z then math.max(0.1, z.heat) else 1
				local secs = math.clamp(C.frozenBase / heat, C.frozenMin, C.frozenMax)
				setState(c, "frozen")
				c.untilT = os.clock() + secs
				c.root:SetAttribute("FrozenUntil", workspace:GetServerTimeNow() + secs)
				setMeter(c, 1, nil)
				Remotes.fire(player, "Notify", "critterFrozen", { id = id, seconds = secs })
			end
		end,
	})
	task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(0.1)
			local now = os.clock()
			local ok, err = pcall(tick, now - last)
			if not ok then
				warn("[CritterService] tick:", err)
			end
			last = now
		end
	end)
end

return CritterService
