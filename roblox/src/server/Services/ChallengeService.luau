--!strict
-- ChallengeService: owns the daily challenges (Config.challenges, 2026-11-09). Each UTC day a player
-- gets perDay goals picked from the pool (seeded by the day and their UserId, so a rejoin gets the same
-- ones). Progress = a stat now minus its value when the goal was handed out, so nothing done earlier
-- counts. Claiming pays a few minutes of the player's own income. A finished goal left unclaimed when
-- the day turns is paid automatically: missing the claim never loses it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local WorldRules = require(ReplicatedStorage.Shared.WorldRules)
local Remotes = require(script.Parent.Remotes)
local DataService = require(script.Parent.DataService)

type Data = DataService.Data
local C = Config.challenges

local ChallengeService = {}
local told: { [Player]: { [string]: boolean } } = {} -- "day#i" already announced as finished

-- PenService requires this module for its view, so it is fetched on first use (no require loop)
local penService: any = nil
local function pen(): any
	if not penService then
		penService = require(script.Parent.PenService) :: any
	end
	return penService
end

local function defOf(id: string): Config.ChallengeDef?
	for _, c in C.pool do
		if c.id == id then
			return c
		end
	end
	return nil
end

local function stat(d: Data, name: string): number
	if name == "rares" then
		return d.daily.rares
	end
	return (d.stats :: any)[name] or 0
end

local function have(d: Data, i: number): number
	local c = d.daily.list[i]
	local def = c and defOf(c.id)
	return if c and def then math.max(0, stat(d, def.stat) - c.from) else 0
end

local function isDone(d: Data, i: number): boolean
	local c = d.daily.list[i]
	return c ~= nil and have(d, i) >= c.goal
end

function ChallengeService.reward(d: Data): number
	return math.max(C.rewardFloor, Config.nice(pen().incomePerSecond(d) * 60 * C.rewardMinutes))
end

-- hands out today's goals if the day has turned (call inside DataService.mutate); returns coins auto-paid
local function handOut(player: Player, d: Data): number
	local today = WorldRules.dayId(os.time())
	if d.daily.day == today and #d.daily.list > 0 then
		return 0
	end
	local paid = 0
	for i in d.daily.list do
		if not d.daily.claimed[i] and isDone(d, i) then
			paid += ChallengeService.reward(d)
		end
	end
	if paid > 0 then
		pen().addCoins(d, paid)
	end
	local rng = Random.new(math.floor(os.time() / 86400) * 7919 + player.UserId % 1000003)
	local pool = table.clone(C.pool)
	local list = {}
	local income = pen().incomePerSecond(d)
	for i = 1, math.min(C.perDay, #pool) do
		local c = table.remove(pool, rng:NextInteger(1, #pool)) :: Config.ChallengeDef
		local goal = 1
		if c.incomeMinutes then
			local minutes = c.incomeMinutes[rng:NextInteger(1, #c.incomeMinutes)]
			goal = math.max(c.floor or 1, Config.nice(income * 60 * minutes))
		elseif c.goals then
			goal = c.goals[rng:NextInteger(1, #c.goals)]
		end
		list[i] = { id = c.id, goal = goal, from = stat(d, c.stat) }
	end
	d.daily = { day = today, list = list, claimed = {}, rares = d.daily.rares }
	return paid
end

-- what the client shows (PenService puts it in the player's view)
export type ChallengeView = { text: string, goal: number, have: number, done: boolean, claimed: boolean }
function ChallengeService.view(d: Data): { list: { ChallengeView }, coins: number, resetsAt: number }
	local list = {}
	for i, c in d.daily.list do
		local def = defOf(c.id)
		table.insert(list, {
			text = if def then def.text else "",
			goal = c.goal,
			have = math.min(c.goal, have(d, i)),
			done = isDone(d, i),
			claimed = d.daily.claimed[i] == true,
		})
	end
	local now = os.time()
	return { list = list, coins = ChallengeService.reward(d), resetsAt = workspace:GetServerTimeNow() + (86400 - now % 86400) }
end

local function check(player: Player)
	local d = DataService.get(player)
	if not d then
		return
	end
	local paid = 0
	if d.daily.day ~= WorldRules.dayId(os.time()) or #d.daily.list == 0 then
		DataService.mutate(player, function(x)
			paid = handOut(player, x)
		end)
		if paid > 0 then
			DataService.saveNow(player)
			Remotes.fire(player, "Notify", "challengeClaimed", { coins = paid, auto = true })
		end
	end
	local seen = told[player] or {}
	told[player] = seen
	for i, c in d.daily.list do
		local key = `{d.daily.day}#{i}`
		if not seen[key] and not d.daily.claimed[i] and isDone(d, i) then
			seen[key] = true
			local def = defOf(c.id)
			Remotes.fire(player, "Notify", "challengeDone", { index = i, text = if def then def.text else "", goal = c.goal })
		end
	end
end

local function claim(player: Player, i: any)
	if typeof(i) ~= "number" or i ~= math.floor(i) or i < 1 or i > C.perDay then
		return
	end
	local d = DataService.get(player)
	if not d or not d.daily.list[i] or d.daily.claimed[i] or d.daily.day ~= WorldRules.dayId(os.time()) then
		return
	end
	if not isDone(d, i) then
		Remotes.notYet(player, "Not done yet", "daily")
		return
	end
	local coins = ChallengeService.reward(d)
	DataService.mutate(player, function(x)
		x.daily.claimed[i] = true
		pen().addCoins(x, coins)
	end)
	DataService.saveNow(player) -- the coins and the claim stamp in the same save
	Remotes.fire(player, "Notify", "challengeClaimed", { coins = coins, index = i })
end

function ChallengeService.Init() end

function ChallengeService.Start()
	Remotes.on("ClaimChallenge", claim)
	Players.PlayerRemoving:Connect(function(p)
		told[p] = nil
	end)
	-- on join: today's goals at once (a finished, unclaimed one is announced again as a reminder)
	DataService.Loaded:Connect(function(player: Player)
		check(player)
	end)
	while true do
		task.wait(C.checkSeconds)
		for _, p in Players:GetPlayers() do
			task.spawn(check, p)
		end
	end
end

return ChallengeService
