--!strict
-- TradeService (owner 2026-11-19 "we'll add trading"; Game Design Rules 6: a confirm screen). Config.trade.
-- ask -> the other player says yes -> both put in up to maxPets pets -> both Ready -> a confirmSeconds wait in
-- which ANY change un-readies both -> both Accept -> the server checks everything again and swaps both sides in one
-- go, then saves both. The client only asks; every pet id is checked against the asker's own save.
-- Nobody can trade where PolicyService says paid-item trading isn't allowed (attribute TradeOk), and new
-- accounts wait minPlayMinutes of play. Pets thawing in a Thaw Machine can't go in.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Config = require(ReplicatedStorage.Shared.Config)
local PetDefs = require(ReplicatedStorage.Shared.PetDefs)
local Remotes = require(script.Parent.Remotes)
local DataService = require(script.Parent.DataService)
local AnalyticsSvc = require(script.Parent.AnalyticsSvc)
local IndexService = require(script.Parent.IndexService)

local T = Config.trade
local TradeService = {}

type Trade = {
	a: Player, b: Player,
	offer: { [Player]: { string } }, -- pet ids
	ready: { [Player]: boolean }, accepted: { [Player]: boolean },
	confirmAt: number?, -- os.clock(): Accept opens at this time (both ready)
	done: boolean,
}

local asks: { [Player]: { from: Player, at: number } } = {} -- the last ask each player got
local tradeOf: { [Player]: Trade } = {}
local lastAsk: { [Player]: number } = {}
local askTimes: { [Player]: { number } } = {}

local function canTrade(p: Player): (boolean, string?)
	local d = DataService.get(p)
	if not d then
		return false, "Still loading"
	end
	if p:GetAttribute("TradeOk") ~= true and not RunService:IsStudio() then
		return false, "Trading isn't available here"
	end
	if d.extra.playSeconds < T.minPlayMinutes * 60 and not RunService:IsStudio() then
		return false, `Trading opens after {T.minPlayMinutes} min of play`
	end
	return true, nil
end

local function petOf(d: any, id: string): any?
	for _, p in d.pets do
		if p.id == id then
			return p
		end
	end
	return nil
end

local function petView(p: any): { [string]: any }
	local def = PetDefs.get(p.key)
	return { id = p.id, key = p.key, pose = p.pose, mut = p.mut, sz = p.sz, frozen = p.frozen == true,
		income = if def then PetDefs.income(def, p.pose, p.mut, p.sz) else 0 }
end

local function sideValue(d: any, ids: { string }): number
	local sum = 0
	for _, id in ids do
		local p = petOf(d, id)
		local def = p and PetDefs.get(p.key)
		if p and def then
			sum += PetDefs.income(def, p.pose, p.mut, p.sz)
		end
	end
	return sum
end

local function other(t: Trade, p: Player): Player
	return if t.a == p then t.b else t.a
end

-- what each side's client shows
local function send(t: Trade)
	local now = os.clock()
	for _, me in { t.a, t.b } do
		local them = other(t, me)
		local dm, dt = DataService.get(me), DataService.get(them)
		if not dm or not dt then
			continue
		end
		local mine, theirs = {}, {}
		for _, id in t.offer[me] do
			local p = petOf(dm, id)
			if p then
				table.insert(mine, petView(p))
			end
		end
		for _, id in t.offer[them] do
			local p = petOf(dt, id)
			if p then
				table.insert(theirs, petView(p))
			end
		end
		local vm, vt = sideValue(dm, t.offer[me]), sideValue(dt, t.offer[them])
		local hi, lo = math.max(vm, vt), math.min(vm, vt)
		Remotes.fire(me, "Notify", "tradeState", {
			themName = them.DisplayName, themId = them.UserId,
			mine = mine, theirs = theirs, mineValue = vm, theirsValue = vt,
			unfair = hi > 0 and (lo == 0 or hi / lo >= T.unfairRatio), youGiveMore = vm > vt,
			ready = t.ready[me] == true, themReady = t.ready[them] == true,
			accepted = t.accepted[me] == true, themAccepted = t.accepted[them] == true,
			confirmIn = if t.confirmAt then math.max(0, t.confirmAt - now) else nil,
		})
	end
end

local function close(t: Trade, why: string?)
	if tradeOf[t.a] == t then
		tradeOf[t.a] = nil
	end
	if tradeOf[t.b] == t then
		tradeOf[t.b] = nil
	end
	for _, p in { t.a, t.b } do
		if p.Parent then
			Remotes.fire(p, "Notify", "tradeClosed", { why = why or "Trade cancelled" })
		end
	end
end

local function unready(t: Trade)
	t.ready = {}
	t.accepted = {}
	t.confirmAt = nil
end

local function ask(player: Player, userId: any)
	if typeof(userId) ~= "number" then
		return
	end
	local target = Players:GetPlayerByUserId(userId)
	if not target or target == player or tradeOf[player] then
		return
	end
	local now = os.clock()
	if now - (lastAsk[player] or -math.huge) < T.cooldown then
		Remotes.notYet(player, "Wait a moment")
		return
	end
	local times = askTimes[player] or {}
	local kept = {}
	for _, t0 in times do
		if now - t0 < 3600 then
			table.insert(kept, t0)
		end
	end
	if #kept >= T.maxPerHour then
		Remotes.notYet(player, "Too many trade asks. Try later")
		return
	end
	local ok, why = canTrade(player)
	if not ok then
		Remotes.notYet(player, why or "Can't trade")
		return
	end
	local ok2 = canTrade(target)
	if not ok2 or tradeOf[target] then
		Remotes.notYet(player, "They can't trade right now")
		return
	end
	lastAsk[player] = now
	table.insert(kept, now)
	askTimes[player] = kept
	asks[target] = { from = player, at = now }
	Remotes.fire(target, "Notify", "tradeAsk", { fromId = player.UserId, name = player.DisplayName, seconds = T.requestSeconds })
	Remotes.fire(player, "Notify", "tradeAsked", { name = target.DisplayName })
end

local function answer(player: Player, yes: any)
	local a = asks[player]
	asks[player] = nil
	if not a or typeof(yes) ~= "boolean" or os.clock() - a.at > T.requestSeconds then
		return
	end
	local from = a.from
	if not yes then
		if from.Parent then
			Remotes.fire(from, "Notify", "tradeClosed", { why = `{player.DisplayName} said no thanks` })
		end
		return
	end
	if not from.Parent or tradeOf[from] or tradeOf[player] or not canTrade(from) or not canTrade(player) then
		return
	end
	local t: Trade = { a = from, b = player, offer = { [from] = {}, [player] = {} }, ready = {}, accepted = {}, confirmAt = nil, done = false }
	tradeOf[from] = t
	tradeOf[player] = t
	AnalyticsSvc.event(from, "trade_open", { role = "asker" })
	AnalyticsSvc.event(player, "trade_open", { role = "answerer" })
	send(t)
end

local function setPet(player: Player, id: any, add: boolean)
	local t = tradeOf[player]
	local d = DataService.get(player)
	if not t or not d or not Remotes.isId(id, 12) then
		return
	end
	local list = t.offer[player]
	local at = table.find(list, id)
	if add then
		local p = petOf(d, id)
		if at or not p or #list >= T.maxPets then
			return
		end
		if p.thawM then
			Remotes.notYet(player, "Take it out of the Thaw Machine first")
			return
		end
		table.insert(list, id)
	else
		if not at then
			return
		end
		table.remove(list, at)
	end
	unready(t) -- any change: both have to look again
	send(t)
end

-- both sides' pets still there, still free, and room on each side
local function valid(t: Trade): boolean
	local da, db = DataService.get(t.a), DataService.get(t.b)
	if not da or not db then
		return false
	end
	for _, side in { { t.a, da }, { t.b, db } } do
		for _, id in t.offer[side[1]] do
			local p = petOf(side[2], id)
			if not p or p.thawM then
				return false
			end
		end
	end
	if #da.pets - #t.offer[t.a] + #t.offer[t.b] > Config.pen.storageMax then
		return false
	end
	if #db.pets - #t.offer[t.b] + #t.offer[t.a] > Config.pen.storageMax then
		return false
	end
	return #t.offer[t.a] + #t.offer[t.b] > 0
end

local function execute(t: Trade)
	if t.done or not valid(t) then
		close(t, "Trade didn't go through. Nothing changed")
		return
	end
	t.done = true
	local da, db = DataService.get(t.a) :: any, DataService.get(t.b) :: any
	-- take both sides out first, then hand them over: one pass, nothing runs in between (no yields)
	local function take(d: any, ids: { string }): { any }
		local out = {}
		for _, id in ids do
			for i, p in d.pets do
				if p.id == id then
					table.insert(out, table.remove(d.pets, i))
					break
				end
			end
		end
		return out
	end
	local fromA, fromB = {}, {}
	DataService.mutate(t.a, function(x)
		fromA = take(x, t.offer[t.a])
	end)
	DataService.mutate(t.b, function(x)
		fromB = take(x, t.offer[t.b])
	end)
	local function give(player: Player, pets: { any })
		local newKeys = {}
		DataService.mutate(player, function(x)
			for _, p in pets do
				local entry = { id = "q" .. x.nextPetId, key = p.key, pose = p.pose, mut = p.mut, sz = p.sz, at = os.time(), eq = false,
					frozen = if p.frozen then true else nil }
				x.nextPetId += 1
				table.insert(x.pets, entry)
				if not x.found[p.key] then
					x.found[p.key] = true
					table.insert(newKeys, p.key)
				end
			end
			x.extra.trades += 1
		end)
		local d = DataService.get(player)
		if d then
			for _, key in newKeys do
				IndexService.onFound(player, key, d.found, d.indexClaimed)
			end
		end
	end
	give(t.a, fromB)
	give(t.b, fromA)
	DataService.saveNow(t.a)
	DataService.saveNow(t.b)
	for _, p in { t.a, t.b } do
		AnalyticsSvc.event(p, "trade_done", { pets = #fromA + #fromB })
	end
	if tradeOf[t.a] == t then
		tradeOf[t.a] = nil
	end
	if tradeOf[t.b] == t then
		tradeOf[t.b] = nil
	end
	Remotes.fire(t.a, "Notify", "tradeDone", { got = #fromB, gave = #fromA, name = t.b.DisplayName })
	Remotes.fire(t.b, "Notify", "tradeDone", { got = #fromA, gave = #fromB, name = t.a.DisplayName })
	local _ = da
	local _ = db
end

local function setReady(player: Player, on: any)
	local t = tradeOf[player]
	if not t or typeof(on) ~= "boolean" then
		return
	end
	if on and not valid(t) then
		Remotes.notYet(player, "Put a pet in first")
		return
	end
	t.ready[player] = on or nil
	t.accepted = {}
	if t.ready[t.a] and t.ready[t.b] then
		t.confirmAt = os.clock() + T.confirmSeconds
		local at = t.confirmAt
		task.delay(T.confirmSeconds + 0.05, function()
			if tradeOf[t.a] == t and t.confirmAt == at then
				send(t) -- Accept opens
			end
		end)
	else
		t.confirmAt = nil
	end
	send(t)
end

local function accept(player: Player)
	local t = tradeOf[player]
	if not t or not t.confirmAt or os.clock() < t.confirmAt or not (t.ready[t.a] and t.ready[t.b]) then
		return
	end
	t.accepted[player] = true
	if t.accepted[t.a] and t.accepted[t.b] then
		execute(t)
	else
		send(t)
	end
end

function TradeService.Init() end

function TradeService.Start()
	Remotes.on("Trade", function(player: Player, action: any, arg: any)
		if action == "ask" then
			ask(player, arg)
		elseif action == "answer" then
			answer(player, arg)
		elseif action == "add" then
			setPet(player, arg, true)
		elseif action == "remove" then
			setPet(player, arg, false)
		elseif action == "ready" then
			setReady(player, arg)
		elseif action == "accept" then
			accept(player)
		elseif action == "cancel" then
			local t = tradeOf[player]
			if t then
				close(t, `{player.DisplayName} cancelled the trade`)
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(p)
		local t = tradeOf[p]
		if t then
			close(t, "They left the game")
		end
		asks[p] = nil
		lastAsk[p] = nil
		askTimes[p] = nil
		for target, a in asks do
			if a.from == p then
				asks[target] = nil
			end
		end
	end)
end

-- other services: is this player in a trade? (selling or thawing a pet in the trade breaks it)
function TradeService.inTrade(player: Player): boolean
	return tradeOf[player] ~= nil
end

return TradeService
