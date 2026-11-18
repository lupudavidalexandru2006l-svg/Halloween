--!strict
-- WorldRules: rules both sides agree on (zones along the tunnel, heat, shade/sun, pans, gates, calendar).
-- Shade and sun areas come from parts tagged "ShadeZone" / "SunZone" (cylinders), so the map
-- can be edited in Studio without touching code. Call WorldRules.refreshAreas() after the map loads.

local CollectionService = game:GetService("CollectionService")
local Config = require(script.Parent.Config)

type Area = { x: number, z: number, r2: number }

local WorldRules = {}
local shade: { Area } = {}
local sun: { Area } = {}
local lava: { Area } = {} -- lava pools (hot islands, Round 4 phase 6): parts tagged "LavaZone"

local function collect(tag: string): { Area }
	local out: { Area } = {}
	for _, inst in CollectionService:GetTagged(tag) do
		if inst:IsA("BasePart") then
			local r = math.max(inst.Size.X, inst.Size.Z) / 2
			table.insert(out, { x = inst.Position.X, z = inst.Position.Z, r2 = r * r })
		end
	end
	return out
end

local watching = false
function WorldRules.refreshAreas()
	shade = collect("ShadeZone")
	sun = collect("SunZone")
	lava = collect("LavaZone")
	-- Round 4 phase 6: on a client, map parts stream in as you walk, so areas that arrive later are added
	-- then (the map never changes while playing; one streamed out again stays known)
	if not watching then
		watching = true
		for tag, list in { ShadeZone = shade, SunZone = sun, LavaZone = lava } do
			CollectionService:GetInstanceAddedSignal(tag):Connect(function(inst)
				if not inst:IsA("BasePart") then
					return
				end
				local r = math.max(inst.Size.X, inst.Size.Z) / 2
				local x, z = inst.Position.X, inst.Position.Z
				local into = if tag == "ShadeZone" then shade elseif tag == "SunZone" then sun else lava
				for _, a in into do
					if a.x == x and a.z == z then
						return
					end
				end
				table.insert(into, { x = x, z = z, r2 = r * r })
			end)
		end
	end
end

function WorldRules.inHub(pos: Vector3): boolean
	return pos.Z < Config.world.hubZMax
end

-- 0 = hub, otherwise the zone id (the tunnel's section you're in)
function WorldRules.zoneAt(pos: Vector3): number
	if WorldRules.inHub(pos) then
		return 0
	end
	local zones = Config.world.zones
	for _, zone in zones do
		if pos.Z >= zone.zMin and pos.Z < zone.zMax then
			return zone.id
		end
	end
	return zones[#zones].id -- past the end cap (can't happen on foot)
end

-- inside the tunnel's walls, at least `margin` studs from them (wild pets spawn and wander here)
function WorldRules.inTunnel(pos: Vector3, margin: number?): boolean
	local half = Config.world.tunnel.width / 2 - (margin or 0)
	return math.abs(pos.X) <= half and pos.Z >= Config.world.hubZMax and pos.Z <= Config.world.tunnelEnd
end

function WorldRules.heatAt(pos: Vector3): number
	local id = WorldRules.zoneAt(pos)
	if id == 0 then
		return Config.melt.hubHeat
	end
	local zone = Config.zone(id)
	return if zone then zone.heat else 1
end

function WorldRules.lightAt(pos: Vector3): "shade" | "sun" | "lava" | "open"
	for _, a in lava do
		if (pos.X - a.x) ^ 2 + (pos.Z - a.z) ^ 2 < a.r2 then
			return "lava"
		end
	end
	for _, a in shade do
		if (pos.X - a.x) ^ 2 + (pos.Z - a.z) ^ 2 < a.r2 then
			return "shade"
		end
	end
	for _, a in sun do
		if (pos.X - a.x) ^ 2 + (pos.Z - a.z) ^ 2 < a.r2 then
			return "sun"
		end
	end
	return "open"
end

function WorldRules.meltRate(pos: Vector3): number
	local light = WorldRules.lightAt(pos)
	local f = if light == "shade" then Config.melt.shade elseif light == "sun" then Config.melt.sun elseif light == "lava" then Config.melt.lava else 1
	return WorldRules.heatAt(pos) * f
end

-- Temperature from the same numbers that drive melting, so it can never disagree with the cube.
function WorldRules.temperatureAt(pos: Vector3, night: boolean, chill: boolean): (number, string)
	local T = Config.temperature
	local melt = if chill then 0 else WorldRules.meltRate(pos) * (if night then Config.melt.night else 1)
	local c = math.round(T.atZeroMelt + T.perMelt * melt)
	local band = "hot"
	for _, b in T.bands do
		if c < b.below then
			band = b.name
			break
		end
	end
	return c, band
end

function WorldRules.zoneTemperature(zoneId: number): number
	local heat = if zoneId == 0 then Config.melt.hubHeat else ((Config.zone(zoneId) :: any).heat :: number)
	return math.round(Config.temperature.atZeroMelt + Config.temperature.perMelt * heat)
end

function WorldRules.toFahrenheit(c: number): number
	return math.round(c * 9 / 5 + 32)
end

-- the pan's middle; it moves back as the pan grows with its Slots (Config.plotZ)
function WorldRules.plotCenter(index: number): Vector3
	local p = Config.world.plots[index]
	return Vector3.new(p.x, 0, Config.plotZ(index))
end

function WorldRules.inPlot(index: number, pos: Vector3): boolean
	local c = WorldRules.plotCenter(index)
	local s = Config.world.penSize
	return math.abs(pos.X - c.X) <= s.X / 2 and math.abs(pos.Z - c.Z) <= Config.plotLength(index) / 2
end

-- how far this player may go: islands 1..reach are open to them (Round 4 phase 6; the save's reach)
function WorldRules.canEnter(zoneId: number, reach: number?): boolean
	return zoneId <= math.max(1, reach or 1)
end

-- the z of the gate in front of a zone (zone 1 starts at the tunnel mouth, which has no gate)
function WorldRules.gateZ(zoneId: number): number?
	local z = Config.zone(zoneId)
	return if z and zoneId > 1 then z.zMin else nil
end

-- the day/night loop from server time (+ the offset the server publishes as workspace NightOffset, moved
-- by the tester "Night now" button). blend: 0 = full day, 1 = full night; clock = Lighting.ClockTime.
function WorldRules.nightCycle(serverNow: number, offset: number): { blend: number, night: boolean, clock: number }
	local N = Config.night
	local cycle = N.daySeconds + N.fadeSeconds * 2 + N.nightSeconds
	local t = (serverNow + offset) % cycle
	local blend, clock
	if t < N.daySeconds then
		blend, clock = 0, N.day.clock
	elseif t < N.daySeconds + N.fadeSeconds then -- sunset: the sun goes down in the west
		blend = (t - N.daySeconds) / N.fadeSeconds
		clock = N.day.clock + (N.night.clock - N.day.clock) * blend
	elseif t < N.daySeconds + N.fadeSeconds + N.nightSeconds then
		blend, clock = 1, 0
	else -- sunrise: from midnight up to the day's clock
		local u = (t - N.daySeconds - N.fadeSeconds - N.nightSeconds) / N.fadeSeconds
		blend, clock = 1 - u, N.day.clock * u
	end
	return { blend = blend, night = blend >= N.nightAt, clock = clock % 24 }
end

-- seconds to add to the offset so the loop is at the start of the night (or the start of the day)
function WorldRules.skipTo(serverNow: number, offset: number, toNight: boolean): number
	local N = Config.night
	local cycle = N.daySeconds + N.fadeSeconds * 2 + N.nightSeconds
	local t = (serverNow + offset) % cycle
	local target = if toNight then N.daySeconds + N.fadeSeconds else 0
	return offset + (target - t) % cycle
end

-- seconds until the next night falls (the moment nightCycle turns `night`), 0 while it's night
function WorldRules.nightIn(serverNow: number, offset: number): number
	local N = Config.night
	local cycle = N.daySeconds + N.fadeSeconds * 2 + N.nightSeconds
	if WorldRules.nightCycle(serverNow, offset).night then
		return 0
	end
	local t = (serverNow + offset) % cycle
	local falls = N.daySeconds + N.fadeSeconds * N.nightAt
	return (falls - t) % cycle
end

-- when the Secret of half hour `boundary` (Unix :00 / :30) comes: the nightfall nearest it (owner 2026-11-18:
-- "the secret should spawn in a night reset, don't change the times, only the second it happens should be the
-- same"), so it lands the same second as the Night Reset, 16 s before the half hour with the default loop
local function secretAt(boundary: number, offset: number): number
	local N = Config.night
	local cycle = N.daySeconds + N.fadeSeconds * 2 + N.nightSeconds
	local falls = N.daySeconds + N.fadeSeconds * N.nightAt -- the moment nightCycle turns `night`
	local d = (falls - (boundary + offset)) % cycle
	if d > cycle / 2 then
		d -= cycle
	end
	return boundary + d
end

-- the Secret clock (Config.secretSpawn): seconds to the next one, and the slot number of the last one
-- (the workspace attribute NightOffset moves it with the night loop)
function WorldRules.secretIn(serverNow: number): (number, number)
	local every = Config.secretSpawn.everySeconds
	local off = workspace:GetAttribute("NightOffset")
	local offset = if typeof(off) == "number" then off else 0
	local k = math.floor(serverNow / every) + 1
	while secretAt(k * every, offset) > serverNow do
		k -= 1
	end
	return secretAt((k + 1) * every, offset) - serverNow, k
end

-- the server event clock (Config.events): the event running now (nil = none), when it ends, the next one and
-- the seconds to it. Unix time, so every server and every client agree without messages.
-- (the workspace attribute EventOffset shifts it: the Studio tester's "next event" jump)
function WorldRules.eventAt(serverNow: number): (Config.ServerEvent?, number, Config.ServerEvent, number)
	local E = Config.events
	local off = workspace:GetAttribute("EventOffset")
	local shift = if typeof(off) == "number" then off else 0
	local t = serverNow + shift
	local slot = math.floor((t - E.offsetSeconds) / E.everySeconds)
	local start = slot * E.everySeconds + E.offsetSeconds
	local function at(n: number): Config.ServerEvent
		return E.list[n % #E.list + 1]
	end
	local now: Config.ServerEvent? = if t < start + E.durationSeconds then at(slot) else nil
	return now, start + E.durationSeconds - shift, at(slot + 1), start + E.everySeconds - t
end

-- calendar (UTC): the daily gift day and the weekly leaderboard week (fixed reset day)
function WorldRules.dayId(unix: number): string
	return os.date("!%Y-%m-%d", unix) :: string
end

function WorldRules.weekId(unix: number): string
	local wday = tonumber(os.date("!%w", unix)) :: number -- 0 = Sunday
	local back = (wday - Config.leaderboards.weeklyResetDay) % 7
	return os.date("!%Y-%m-%d", unix - back * 86400) :: string
end

return WorldRules
