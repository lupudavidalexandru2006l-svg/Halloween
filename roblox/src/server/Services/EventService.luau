--!strict
-- EventService: owns the Big Chill (Game Plan 14). About every 10 minutes, announced 30 s before:
-- snow everywhere, nothing melts for 60 s, and every pet frozen in it is Frosty (x1.5).
-- Clients read the world Attributes ChillUntil / NextChill (server time) and hear Notify chillWarn/Start/End.
-- Also owns the night clock (Config.night): the loop runs from server time; the workspace attribute
-- NightOffset shifts it (tester "Night now"), and Notify nightStart / nightEnd fire as it turns.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local WorldRules = require(ReplicatedStorage.Shared.WorldRules)
local Remotes = require(script.Parent.Remotes)

local EventService = {}

local nextAt = 0 -- os.clock() of the next Big Chill
local untilAt = 0 -- os.clock() when the current one ends (0 = none)
local warned = false
local nightOffset = 0
local wasNight = false

local function serverTime(clockAt: number): number
	return workspace:GetServerTimeNow() + (clockAt - os.clock())
end

local function publish()
	workspace:SetAttribute("ChillUntil", if untilAt > 0 then serverTime(untilAt) else 0)
	workspace:SetAttribute("NextChill", serverTime(nextAt))
end

function EventService.isChill(): boolean
	return untilAt > 0 and os.clock() < untilAt
end

function EventService.isNight(): boolean
	return WorldRules.nightCycle(workspace:GetServerTimeNow(), nightOffset).night
end

-- tester button: jump the loop to the start of the night, or back to morning if it's night now
function EventService.toggleNight()
	nightOffset = WorldRules.skipTo(workspace:GetServerTimeNow(), nightOffset, not EventService.isNight())
	workspace:SetAttribute("NightOffset", nightOffset)
end

local function nightTick()
	local night = EventService.isNight()
	if night ~= wasNight then
		wasNight = night
		Remotes.fireAll("Notify", if night then "nightStart" else "nightEnd", {})
	end
end

-- starts one now (dev command; later the paid server-wide Big Chill, Game Plan 15)
function EventService.startNow()
	local B = Config.bigChill
	untilAt = os.clock() + B.durationSeconds
	nextAt = os.clock() + B.everySeconds
	warned = false
	publish()
	Remotes.fireAll("Notify", "chillStart", { seconds = B.durationSeconds })
end

local function tick()
	local B = Config.bigChill
	local now = os.clock()
	if not warned and now >= nextAt - B.warnSeconds then
		warned = true
		Remotes.fireAll("Notify", "chillWarn", { inSeconds = math.max(0, math.round(nextAt - now)) })
	end
	if now >= nextAt then
		EventService.startNow()
	end
	if untilAt > 0 and now >= untilAt then
		untilAt = 0
		publish()
		Remotes.fireAll("Notify", "chillEnd", {})
	end
end

function EventService.Init()
	nextAt = os.clock() + Config.bigChill.everySeconds
end

function EventService.Start()
	publish()
	workspace:SetAttribute("NightOffset", nightOffset)
	wasNight = EventService.isNight()
	task.spawn(function()
		while true do
			task.wait(0.5)
			tick()
			nightTick()
		end
	end)
end

return EventService
