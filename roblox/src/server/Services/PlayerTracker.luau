--!strict
-- PlayerTracker: owns each player's runtime state that isn't saved: zone, last action, menu open,
-- session start, and the Humanoid's WalkSpeed (one owner). Logs zone_entered, first_new_zone,
-- first_carry_home and session_end. The server uses the character's real position, never a claimed one.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local WorldRules = require(ReplicatedStorage.Shared.WorldRules)
local Remotes = require(script.Parent.Remotes)
local DataService = require(script.Parent.DataService)
local AnalyticsSvc = require(script.Parent.AnalyticsSvc)

type State = {
	zone: number,
	lastAction: string,
	menuOpen: boolean,
	zapping: boolean,
	joinedAt: number,
	carrying: number, -- set by CarryService
	inPen: boolean,
	lastPos: Vector3?,
	lastPosAt: number,
	speedFlags: number,
	carriedOut: boolean, -- a carried cube has been a real distance out of the hub
}

local PlayerTracker = {}
local states: { [Player]: State } = {}
local flagTimes: { [Player]: { number } } = {} -- os.clock() of each speed flag (Config.antiCheat)
local enteredPenEvent = Instance.new("BindableEvent")
PlayerTracker.EnteredPen = enteredPenEvent.Event -- (player) fired while a carrying player stands in their own pen

local WorldService -- required lazily (avoids a require cycle)

function PlayerTracker.rootPart(player: Player): BasePart?
	local c = player.Character
	return if c then c:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
end

function PlayerTracker.position(player: Player): Vector3?
	local r = PlayerTracker.rootPart(player)
	return if r then r.Position else nil
end

function PlayerTracker.get(player: Player): State?
	return states[player]
end

function PlayerTracker.setCarrying(player: Player, n: number)
	local s = states[player]
	if s then
		s.carrying = n
		PlayerTracker.updateSpeed(player)
	end
end

function PlayerTracker.setZapping(player: Player, on: boolean)
	local s = states[player]
	if s then
		s.zapping = on
	end
end

-- the only place WalkSpeed is set
function PlayerTracker.updateSpeed(player: Player)
	local data = DataService.get(player)
	local c = player.Character
	local hum = c and c:FindFirstChildOfClass("Humanoid")
	local s = states[player]
	if not data or not hum or not s then
		return
	end
	if player:GetAttribute("TrainLocked") == true then
		hum.WalkSpeed = 0 -- locked in at their trainer until they jump off (TrainingService)
		return
	end
	if data.tester.walk > 0 then
		hum.WalkSpeed = data.tester.walk -- tester walk speed slider (DataService keeps it 0 for everyone else)
		return
	end
	local extra = math.max(0, s.carrying - 1)
	local slow = math.max(0.5, 1 - Config.upgrades.backpack.slowPerExtraCube * extra)
	-- Frost Boots (Config.gear, 2026-11-17): faster all the time, +5% a level
	local boots = Config.gearValue(player, "frost_boots", "speedMult", 1)
	-- a Speed Potion (2026-11-18, owner: "the monetizations are good, add them"): x its mult until it ends
	local b = data.boosts
	local potion = if b and os.time() < b.speedUntil then b.speedMult else 1
	hum.WalkSpeed = Config.player.walkSpeed * slow * boots * potion
end

-- moves a player's character (tester teleports); the speed check starts fresh from there
function PlayerTracker.teleport(player: Player, cf: CFrame): boolean
	local root = PlayerTracker.rootPart(player)
	if not root then
		return false
	end
	root.AssemblyLinearVelocity = Vector3.zero
	root.CFrame = cf
	local s = states[player]
	if s then
		s.lastPos = cf.Position
		s.lastPosAt = os.clock()
	end
	return true
end

-- a long jump (Night home, tester teleports): ask Roblox to stream the far side in first, then move. Without it
-- the player lands where nothing is loaded and, with StreamingIntegrityMode PauseOutsideLoadedArea, the game
-- stops until it arrives: QA PT-05 (2026-11-19), "0 FPS on first arrival at Jungle Falls". Yields up to
-- Config.streamAhead.wait seconds, so callers run it in their own thread.
function PlayerTracker.teleportFar(player: Player, cf: CFrame): boolean
	local root = PlayerTracker.rootPart(player)
	if root and (root.Position - cf.Position).Magnitude > Config.streamAhead.minStuds then
		pcall(function()
			player:RequestStreamAroundAsync(cf.Position, Config.streamAhead.wait)
		end)
	end
	if not player.Parent then
		return false
	end
	return PlayerTracker.teleport(player, cf)
end

local function zoneKey(id: number): string
	if id == 0 then
		return "hub"
	end
	local z = Config.zone(id)
	return if z then z.key else tostring(id)
end

local function tick()
	local now = os.clock()
	for player, s in states do
		local pos = PlayerTracker.position(player)
		if not pos then
			continue
		end
		-- zone tracking
		local zone = WorldRules.zoneAt(pos)
		if zone ~= s.zone then
			s.zone = zone
			AnalyticsSvc.event(player, "zone_entered", { zone = zoneKey(zone) })
			if zone == 2 then
				AnalyticsSvc.funnel(player, "first_new_zone")
			end
		end
		-- funnel step 4: a cube that went a real distance out of the hub and came back (CarryService
		-- also logs it just before the first bank, so the funnel stays in order)
		if s.carrying > 0 then
			if pos.Z > Config.world.hubZMax + Config.carryHomeMinStuds then
				s.carriedOut = true
			elseif s.carriedOut and WorldRules.inHub(pos) then
				AnalyticsSvc.funnel(player, "first_carry_home")
			end
		else
			s.carriedOut = false
		end
		if not WorldService then
			WorldService = require(script.Parent.WorldService) :: any
		end
		local plot = WorldService.plotOf(player)
		s.inPen = plot ~= nil and WorldRules.inPlot(plot, pos) -- anyone may walk into any pan (owner 2026-11-07)
		-- Round 4 phase 6: past a gate you haven't opened (a glitch, a hacked client) = put back in front of
		-- it. Each client opens its own gates; testers may stand anywhere (their teleports reach locked islands).
		local data = DataService.get(player)
		if data and zone > data.reach and not Config.isTester(player.UserId) then
			local gz = WorldRules.gateZ(data.reach + 1)
			if gz and pos.Z > gz + Config.gateGuardStuds then
				PlayerTracker.teleport(player, CFrame.new(0, 4, gz - Config.gatePromptOffset - 2) * CFrame.Angles(0, math.pi, 0))
				continue
			end
		end
		if s.inPen and s.carrying > 0 then
			enteredPenEvent:Fire(player)
		end
		s.lastAction = if s.zapping then "zapping" elseif s.menuOpen then "in_menu" elseif s.carrying > 0 then "carrying" elseif s.inPen then "in_pen" else "exploring"
		-- speed sanity check (flag only; kids lag, so nobody is punished automatically)
		if s.lastPos then
			local dt = now - s.lastPosAt
			local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
			local max = (if hum then hum.WalkSpeed else Config.player.walkSpeed) * Config.player.maxSpeedTolerance * dt + 4
			local flat = Vector3.new(pos.X - s.lastPos.X, 0, pos.Z - s.lastPos.Z).Magnitude
			if flat > max then
				s.speedFlags += 1
				if RunService:IsStudio() then
					warn(`[PlayerTracker] {player.UserId} moved {math.floor(flat)} studs in {string.format("%.2f", dt)}s`)
				end
				-- QA security (2026-11-19): one flag is lag; many in a short time is a speed or teleport hack. A soft kick
				-- (the save is kept, nothing is taken), never for testers or in Studio (Config.antiCheat)
				local AC = Config.antiCheat
				local times = flagTimes[player] or {}
				flagTimes[player] = times
				table.insert(times, now)
				while times[1] and now - times[1] > AC.windowSeconds do
					table.remove(times, 1)
				end
				if #times > AC.kickFlags and not Config.isTester(player.UserId) and not RunService:IsStudio() then
					warn(`[PlayerTracker] soft kick {player.UserId}: {#times} speed flags in {AC.windowSeconds}s`)
					player:Kick(AC.kickText)
					continue
				end
			end
		end
		s.lastPos = pos
		s.lastPosAt = now
	end
end

function PlayerTracker.Init() end

function PlayerTracker.Start()
	Players.RespawnTime = Config.player.respawnSeconds -- a reset or a fall puts you back fast (Roblox's default is 5 s)
	DataService.Loaded:Connect(function(player: Player)
		states[player] = {
			zone = -1, lastAction = "exploring", menuOpen = false, zapping = false, joinedAt = os.clock(),
			carrying = 0, inPen = false, lastPos = nil, lastPosAt = os.clock(), speedFlags = 0, carriedOut = false,
		}
		AnalyticsSvc.funnel(player, "joined")
		player.CharacterAdded:Connect(function()
			local s = states[player]
			if s then
				s.lastPos = nil -- a new body (respawn, then the walk-free hop to your pan) isn't a fast move
			end
			task.defer(PlayerTracker.updateSpeed, player)
		end)
		PlayerTracker.updateSpeed(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		-- session_end is AnalyticsSvc's (one per visit; this second copy, with fields it doesn't take, was dropped 2026-11-18)
		states[player] = nil
		flagTimes[player] = nil
	end)
	Remotes.on("SetMenuOpen", function(player, open)
		local s = states[player]
		if s and typeof(open) == "boolean" then
			s.menuOpen = open
		end
	end)
	task.spawn(function()
		while true do
			task.wait(0.2)
			tick()
		end
	end)
end

return PlayerTracker
