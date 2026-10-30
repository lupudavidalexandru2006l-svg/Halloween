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
	local boots = 1 + Config.upgrades.boots.speedBonus * (data.upgrades.boots - 1)
	local extra = math.max(0, s.carrying - 1)
	local slow = math.max(0.5, 1 - Config.upgrades.backpack.slowPerExtraCube * extra)
	hum.WalkSpeed = Config.player.walkSpeed * boots * slow
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
		s.inPen = plot ~= nil and WorldRules.inPlot(plot, pos)
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
			end
		end
		s.lastPos = pos
		s.lastPosAt = now
	end
end

function PlayerTracker.Init() end

function PlayerTracker.Start()
	DataService.Loaded:Connect(function(player: Player)
		states[player] = {
			zone = -1, lastAction = "exploring", menuOpen = false, zapping = false, joinedAt = os.clock(),
			carrying = 0, inPen = false, lastPos = nil, lastPosAt = os.clock(), speedFlags = 0, carriedOut = false,
		}
		AnalyticsSvc.funnel(player, "joined")
		player.CharacterAdded:Connect(function()
			task.defer(PlayerTracker.updateSpeed, player)
		end)
		PlayerTracker.updateSpeed(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		local s = states[player]
		if s then
			AnalyticsSvc.event(player, "session_end", {
				sessionSeconds = os.clock() - s.joinedAt,
				zone = zoneKey(math.max(0, s.zone)),
				lastAction = s.lastAction,
				carryingCube = tostring(s.carrying > 0),
			})
		end
		states[player] = nil
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
