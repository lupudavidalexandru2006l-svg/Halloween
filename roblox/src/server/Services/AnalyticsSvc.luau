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

-- "when, where and why players leave" (owner 2026-11-17 night): one session_end per visit, with how long they
-- played (value), the island they were on (0 = hub), what they were doing and how far they'd got ("R2 I5" =
-- 2 rebirths, 5 islands open). Read it in the Creator Dashboard > Analytics > Custom events, split by a field.
local joinedAt: { [Player]: number } = {}

function AnalyticsSvc.stage(player: Player): string
	local d = DataService.get(player)
	return if d then `R{d.rebirths} I{d.reach}` else "?"
end

local function doing(player: Player, zone: number): string
	local ok, CarryService = pcall(require, script.Parent.CarryService) -- required late: CarryService requires this module
	if (player:GetAttribute("TrainStation") or 0) ~= 0 or player:GetAttribute("TrainLocked") == true then
		return "training"
	elseif ok and CarryService.count(player) > 0 then
		return "carrying"
	elseif player:GetAttribute("Aiming") then
		return "zapping"
	elseif zone > 0 then
		return "on_island"
	end
	return "in_hub"
end

function AnalyticsSvc.Start()
	local Players = game:GetService("Players")
	local WorldRules = require(ReplicatedStorage.Shared.WorldRules)
	Players.PlayerAdded:Connect(function(p)
		joinedAt[p] = os.clock()
	end)
	for _, p in Players:GetPlayers() do
		joinedAt[p] = joinedAt[p] or os.clock()
	end
	Players.PlayerRemoving:Connect(function(p)
		local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
		local zone = if root and root:IsA("BasePart") then WorldRules.zoneAt(root.Position) else 0
		local ok, what = pcall(doing, p, zone)
		AnalyticsSvc.event(p, "session_end", {
			sessionSeconds = os.clock() - (joinedAt[p] or os.clock()),
			zone = zone, doing = if ok then what else "?", stage = AnalyticsSvc.stage(p),
		})
		joinedAt[p] = nil
	end)
end

return AnalyticsSvc
