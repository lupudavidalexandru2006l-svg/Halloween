--!strict
-- AnalyticsSvc: the one wrapper around Roblox AnalyticsService (server only, no personal data,
-- nothing off-platform). Every funnel step and event name comes from Config.analytics; anything
-- else is refused. There is no RemoteEvent for analytics, so a client can't send fake events.

local AnalyticsService = game:GetService("AnalyticsService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local DataService = require(script.Parent.DataService)

local AnalyticsSvc = {}

local FIELD_KEYS = {
	Enum.AnalyticsCustomFieldKeys.CustomField01.Name,
	Enum.AnalyticsCustomFieldKeys.CustomField02.Name,
	Enum.AnalyticsCustomFieldKeys.CustomField03.Name,
}
local stepByName: { [string]: number } = {}
for _, s in Config.analytics.funnel do
	stepByName[s.name] = s.step
end
local verbose = RunService:IsStudio()

-- onboarding funnel: each step logged once per player, ever (stamped in their save)
function AnalyticsSvc.funnel(player: Player, name: string)
	local step = stepByName[name]
	if not step then
		return
	end
	local data = DataService.get(player)
	if not data or data.funnel[name] then
		return
	end
	DataService.mutate(player, function(d)
		d.funnel[name] = true
	end)
	if verbose then
		print(`[analytics] funnel step {step} {name} ({player.UserId})`)
	end
	pcall(function()
		AnalyticsService:LogOnboardingFunnelStepEvent(player, step, name)
	end)
end

-- custom events: one number + up to 3 short string fields, as Config.analytics.events says
function AnalyticsSvc.event(player: Player, name: string, values: { [string]: any }?)
	local def = Config.analytics.events[name]
	if not def then
		return
	end
	local v = values or {}
	local number: number? = nil
	if def.value then
		local raw = v[def.value]
		number = if typeof(raw) == "number" then math.round(raw) else nil
	end
	local fields: { [string]: string } = {}
	for i, f in def.fields do
		if i > 3 then
			break
		end
		local raw = v[f]
		if raw ~= nil then
			fields[FIELD_KEYS[i]] = string.sub(tostring(raw), 1, 32)
		end
	end
	if verbose then
		print(`[analytics] event {name}`, number, fields)
	end
	pcall(function()
		AnalyticsService:LogCustomEvent(player, name, number, fields)
	end)
end

return AnalyticsSvc
