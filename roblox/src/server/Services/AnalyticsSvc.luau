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

-- ---------- coin economy (owner 2026-11-18: "all the money I've made is from daily gifts" + "add funnels so we
-- have more data than just the analytics") ----------
-- Every coin in and out, by where it came from: Creator Dashboard > Analytics > Economy shows sources and sinks
-- side by side (pets' income vs daily vs gifts vs Robux packs; guns vs gear vs pan vs rebirth). Added up per
-- player and kind and sent once a minute (and when they leave), so the busy income tick stays inside Roblox's limits.
local TX: { [string]: string } = {
	income = "Gameplay", sell = "Gameplay", away = "TimedReward", daily = "TimedReward", code = "TimedReward",
	free_gift = "Onboarding", tutorial = "Onboarding", robux_pack = "IAP",
	gun = "Shop", gear = "Shop", pan = "Shop", shop = "Shop", rebirth = "Shop",
}
local pending: { [Player]: { [string]: { flow: string, n: number } } } = {}

local function addFlow(player: Player, flow: string, amount: number, kind: string)
	if typeof(amount) ~= "number" or amount ~= amount or amount <= 0 or not TX[kind] then
		return
	end
	local p = pending[player] or {}
	pending[player] = p
	local key = flow .. ":" .. kind
	local b = p[key] or { flow = flow, n = 0 }
	b.n += amount
	p[key] = b
end

function AnalyticsSvc.coinsIn(player: Player, amount: number, kind: string)
	addFlow(player, "Source", amount, kind)
end

function AnalyticsSvc.coinsOut(player: Player, amount: number, kind: string)
	addFlow(player, "Sink", amount, kind)
end

local function flush(player: Player)
	local p = pending[player]
	pending[player] = nil
	local d = DataService.get(player)
	if not p or not d then
		return
	end
	for key, b in p do
		local kind = string.match(key, ":(.+)$") or "?"
		local amount = math.min(math.floor(b.n), 2 ^ 52)
		if amount > 0 then
			if verbose then
				print(`[analytics] economy {b.flow} {kind} {amount}`)
			end
			pcall(function()
				AnalyticsService:LogEconomyEvent(player, (Enum.AnalyticsEconomyFlowType :: any)[b.flow], "Coins", amount,
					math.min(math.floor(d.coins), 2 ^ 52), TX[kind], kind)
			end)
		end
	end
end

-- the tutorial as a step funnel (Creator Dashboard > Analytics > Funnels): which step new players stop on
function AnalyticsSvc.tutorialStep(player: Player, step: number, id: string)
	if verbose then
		print(`[analytics] tutorial step {step} {id}`)
	end
	pcall(function()
		AnalyticsService:LogFunnelStepEvent(player, "Tutorial", tostring(player.UserId), step, id)
	end)
end

-- "when, where and why players leave" (owner 2026-11-17 night): one session_end per visit, with how long they
-- played (value), the island they were on (0 = hub), what they were doing and how far they'd got ("R2 I5" =
-- 2 rebirths, 5 islands open). Read it in the Creator Dashboard > Analytics > Custom events, split by a field.
local joinedAt: { [Player]: number } = {}

-- "R2 I5", and "T7" on the end while the tutorial is still running (the step they're on)
function AnalyticsSvc.stage(player: Player): string
	local d = DataService.get(player)
	if not d then
		return "?"
	end
	local tut = if d.tutorial and not d.tutorial.done then ` T{d.tutorial.step}` else ""
	return `R{d.rebirths} I{d.reach}{tut}`
end

-- a cube melted in their hands a moment ago (CarryService): a leave right after one reads "left_after_melt"
local meltAt: { [Player]: number } = {}
function AnalyticsSvc.melted(player: Player)
	meltAt[player] = os.clock()
end

local function doing(player: Player, zone: number): string
	local ok, CarryService = pcall(require, script.Parent.CarryService) -- required late: CarryService requires this module
	if os.clock() - (meltAt[player] or -math.huge) < 30 then
		return "left_after_melt"
	elseif (player:GetAttribute("TrainStation") or 0) ~= 0 or player:GetAttribute("TrainLocked") == true then
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
	task.spawn(function()
		while true do
			task.wait(60)
			for p in pending do
				pcall(flush, p)
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(p)
		pcall(flush, p)
		meltAt[p] = nil
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
