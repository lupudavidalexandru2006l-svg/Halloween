--!strict
-- EventService: owns the Big Chill (Game Plan 14). About every 10 minutes, announced 30 s before:
-- snow everywhere, nothing melts for 60 s, and every pet frozen in it is Frosty (x1.5).
-- Clients read the world Attributes ChillUntil / NextChill (server time) and hear Notify chillWarn/Start/End.
-- Also owns the night clock (Config.night): the loop runs from server time; the workspace attribute
-- NightOffset shifts it (tester "Night now"), and Notify nightStart / nightEnd fire as it turns.
-- 2026-11-16 (owner: "an event every 30 mins, the current events are kinda shitty"): the free Big Chill's own
-- 10-minute clock is gone. Server events run on the Unix clock (Config.events, WorldRules.eventAt): every half
-- hour, 15 minutes after each Secret, the next of Big Chill / Lucky Rush / Coin Rush / Golden Rush runs for
-- 5 minutes. EventService.mult(kind) gives the others their multiplier. Notify eventWarn / eventStart / eventEnd,
-- and nightWarn before the islands close for the night (TravelService).

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
local nightChanged = Instance.new("BindableEvent")
EventService.NightChanged = nightChanged.Event -- (night: boolean): WildPetSpawner's Night Reset

local function serverTime(clockAt: number): number
	return workspace:GetServerTimeNow() + (clockAt - os.clock())
end

local function publish()
	workspace:SetAttribute("ChillUntil", if untilAt > 0 then serverTime(untilAt) else 0)
	workspace:SetAttribute("NextChill", if nextAt < math.huge then serverTime(nextAt) else 0)
end

function EventService.isChill(): boolean
	return untilAt > 0 and os.clock() < untilAt
end

-- the server event running now (Config.events), or nil
function EventService.current(): Config.ServerEvent?
	return (WorldRules.eventAt(workspace:GetServerTimeNow()))
end

-- an admin boost (AdminService, owner 2026-11-18 "admin abuse"): workspace attributes Admin_<kind> = its
-- multiplier and AdminUntil_<kind> = the server time it ends. Same in every server (one message sets them all).
function EventService.adminMult(kind: string): number
	local m = workspace:GetAttribute("Admin_" .. kind)
	local untilAt = workspace:GetAttribute("AdminUntil_" .. kind)
	if typeof(m) == "number" and typeof(untilAt) == "number" and workspace:GetServerTimeNow() < untilAt then
		return m
	end
	return 1
end

-- an event's multiplier: "luck" (Rare and up odds), "coins" (pan income), "golden" (Golden chance), "size"
-- (big sizes, admin only); 1 = none. An admin boost multiplies on top of the event.
function EventService.mult(kind: string): number
	local e = EventService.current()
	local E = Config.events
	local admin = EventService.adminMult(kind)
	if not e or e.id ~= kind then
		return admin
	end
	return admin * (if kind == "luck" then E.luckMult elseif kind == "coins" then E.coinMult elseif kind == "golden" then E.goldenMult else 1)
end

function EventService.isNight(): boolean
	return WorldRules.nightCycle(workspace:GetServerTimeNow(), nightOffset).night
end

-- tester button: jump the loop to the start of the night, or back to morning if it's night now
function EventService.toggleNight()
	nightOffset = WorldRules.skipTo(workspace:GetServerTimeNow(), nightOffset, not EventService.isNight())
	workspace:SetAttribute("NightOffset", nightOffset)
end

-- admin: night (true) or morning (false) now, whatever it is
function EventService.setNight(on: boolean)
	if EventService.isNight() ~= on then
		EventService.toggleNight()
	end
end

local function nightTick()
	local night = EventService.isNight()
	if night ~= wasNight then
		wasNight = night
		workspace:SetAttribute("NightReset", night) -- clients poof the pets that leave (PetVisuals)
		nightChanged:Fire(night)
		Remotes.fireAll("Notify", if night then "nightStart" else "nightEnd", {})
	end
end

-- starts one now (the free clock, and the tester button). A Chill already running (a bought one) is
-- never cut short by it.
function EventService.startNow()
	local B = Config.bigChill
	untilAt = math.max(untilAt, os.clock() + B.durationSeconds)
	nextAt = os.clock() + B.everySeconds
	warned = false
	publish()
	Remotes.fireAll("Notify", "chillStart", { seconds = math.round(untilAt - os.clock()) })
end

-- a Big Chill someone bought for the whole server (MonetizationService, Game Design Rules 10: a
-- server-wide event for everyone, with a shout-out). Adds its time to a Chill already running, or starts
-- one. It never moves the free Chill's clock (nextAt), so free players never wait longer because of it.
function EventService.startBought(byName: string)
	local B = Config.bigChill
	local now = os.clock()
	untilAt = math.max(untilAt, now) + B.durationSeconds
	publish()
	Remotes.fireAll("Notify", "chillStart", { seconds = math.round(untilAt - now), by = byName })
end

local lastEvent: string? = nil -- the event id seen on the last tick ("" = none)
local warnedFor = -1 -- the event slot already warned about
local nightWarned = false

local function eventTick()
	local E = Config.events
	local serverNow = workspace:GetServerTimeNow()
	local cur, ends, nextE, nextIn = WorldRules.eventAt(serverNow)
	local id = if cur then cur.id else ""
	local slot = math.floor((serverNow - E.offsetSeconds) / E.everySeconds)
	if nextIn <= E.warnSeconds and warnedFor ~= slot then
		warnedFor = slot
		Remotes.fireAll("Notify", "eventWarn", { id = nextE.id, name = nextE.name, inSeconds = math.max(0, math.round(nextIn)) })
	end
	if id ~= lastEvent then
		local was = lastEvent
		lastEvent = id
		if was == nil then
			-- the server just started: an event already running is joined quietly (no alert, no start burst)
			if cur and cur.id == "chill" then
				untilAt = math.max(untilAt, os.clock() + (ends - serverNow))
				publish()
			end
			return
		end
		if cur then
			if cur.id == "chill" then
				-- the Big Chill itself (snow, nothing melts, Frosty) runs through the old switch
				untilAt = math.max(untilAt, os.clock() + (ends - serverNow))
				publish()
				Remotes.fireAll("Notify", "chillStart", { seconds = math.round(ends - serverNow), quiet = true })
			end
			Remotes.fireAll("Notify", "eventStart", { id = cur.id, name = cur.name, line = cur.line, ends = ends })
		else
			Remotes.fireAll("Notify", "eventEnd", { id = was })
		end
	end
end

local function tick()
	local now = os.clock()
	eventTick()
	-- the islands close at night (TravelService): a warning before it falls
	local nightIn = WorldRules.nightIn(workspace:GetServerTimeNow(), nightOffset)
	if nightIn > 0 and nightIn <= Config.nightClose.warnSeconds then
		if not nightWarned then
			nightWarned = true
			Remotes.fireAll("Notify", "nightWarn", { inSeconds = math.round(nightIn) })
		end
	elseif nightIn > Config.nightClose.warnSeconds then
		nightWarned = false
	end
	if untilAt > 0 and now >= untilAt then
		untilAt = 0
		publish()
		Remotes.fireAll("Notify", "chillEnd", {})
	end
end

function EventService.Init()
	nextAt = math.huge -- no free Big Chill clock any more: Config.events runs it (2026-11-16)
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
