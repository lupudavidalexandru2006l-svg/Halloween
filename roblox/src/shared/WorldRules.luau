--!strict
-- WorldRules: rules both sides agree on (zones, heat, shade/sun, pens, calendar).
-- Shade and sun areas come from parts tagged "ShadeZone" / "SunZone" (cylinders), so the map
-- can be edited in Studio without touching code. Call WorldRules.refreshAreas() after the map loads.

local CollectionService = game:GetService("CollectionService")
local Config = require(script.Parent.Config)

type Area = { x: number, z: number, r2: number }

local WorldRules = {}
local shade: { Area } = {}
local sun: { Area } = {}

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

function WorldRules.refreshAreas()
	shade = collect("ShadeZone")
	sun = collect("SunZone")
end

function WorldRules.inHub(pos: Vector3): boolean
	return pos.Z < Config.world.hubZMax
end

-- 0 = hub, otherwise the zone id
function WorldRules.zoneAt(pos: Vector3): number
	if WorldRules.inHub(pos) then
		return 0
	end
	for _, zone in Config.world.zones do
		if pos.Z >= zone.zMin and pos.Z <= zone.zMax then
			return zone.id
		end
	end
	return if pos.Z < Config.world.zones[2].zMin then 1 else 2
end

function WorldRules.heatAt(pos: Vector3): number
	local id = WorldRules.zoneAt(pos)
	if id == 0 then
		return Config.melt.hubHeat
	end
	local zone = Config.zone(id)
	return if zone then zone.heat else 1
end

function WorldRules.lightAt(pos: Vector3): "shade" | "sun" | "open"
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
	local f = if light == "shade" then Config.melt.shade elseif light == "sun" then Config.melt.sun else 1
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

function WorldRules.plotCenter(index: number): Vector3
	local p = Config.world.plots[index]
	return Vector3.new(p.x, 0, p.z)
end

function WorldRules.inPlot(index: number, pos: Vector3): boolean
	local c = WorldRules.plotCenter(index)
	local s = Config.world.penSize
	return math.abs(pos.X - c.X) <= s.X / 2 and math.abs(pos.Z - c.Z) <= s.Z / 2
end

function WorldRules.iceBridgeCenter(): Vector3
	local i = Config.world.iceBridgeSpot
	return Vector3.new((i.xMin + i.xMax) / 2, 0, Config.world.river.zMin - 2)
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
