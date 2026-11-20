--!strict
-- ExtrasService (owner 2026-11-19, "bring every score to 10"): the Freeze Streak, the login calendar, weekly
-- quests, milestone chests, ray skins, rebirth titles + VIP tag, achievement badges, chat mute and the per-island
-- analytics. Numbers in Config (raySkins, streak, login, weekly, milestones, rebirthTitles, badges, vip).
-- Server decides everything: the client only asks (remote "Extras": action + one argument), every argument checked.

local Players = game:GetService("Players")
local BadgeService = game:GetService("BadgeService")
local TextChatService = game:GetService("TextChatService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local WorldRules = require(ReplicatedStorage.Shared.WorldRules)
local Remotes = require(script.Parent.Remotes)
local DataService = require(script.Parent.DataService)
local PenService = require(script.Parent.PenService)
local EventService = require(script.Parent.EventService)
local BoostService = require(script.Parent.BoostService)
local AnalyticsSvc = require(script.Parent.AnalyticsSvc)
local PlayerTracker = require(script.Parent.PlayerTracker)
local Hooks = require(script.Parent.Hooks)

type Data = DataService.Data

local ExtrasService = {}

local streak: { [Player]: number } = {}
local muted: { [Player]: { [number]: boolean } } = {}
local zoneSince: { [Player]: { zone: number, at: number } } = {}
local lastSent: { [Player]: string } = {}

-- ---------- helpers ----------
local function weekId(unix: number): string
	return "w" .. math.floor((unix / 86400 + 3) / 7) -- Unix day 0 was a Thursday: +3 makes weeks start on Monday
end
local function weekEnds(unix: number): number
	local w = math.floor((unix / 86400 + 3) / 7)
	return ((w + 1) * 7 - 3) * 86400
end

local function isVip(player: Player): boolean
	return player:GetAttribute("Pass_vip") == true
end

function ExtrasService.ownsSkin(player: Player, d: Data, id: string): boolean
	local s = Config.raySkin(id)
	if not s then
		return false
	end
	if s.unlock == "default" then
		return true
	elseif s.unlock == "rebirth" then
		return d.rebirths >= (s.n or 1)
	elseif s.unlock == "vip" then
		return isVip(player)
	elseif s.unlock == "starter" then
		return d.extra.starter
	end
	return d.extra.skins[id] == true
end

local function ownedCount(player: Player, d: Data): number
	local n = 0
	for _, s in Config.raySkins do
		if s.unlock ~= "default" and ExtrasService.ownsSkin(player, d, s.id) then
			n += 1
		end
	end
	return n
end

-- income minutes, at least floor, at most capShare of the next rebirth's price
local function incomeReward(d: Data, minutes: number, floor: number, capShare: number): number
	local byIncome = PenService.incomePerSecond(d) * 60 * minutes
	local cap = Config.rebirthCost(d.rebirths + 1) * capShare
	return math.max(floor, Config.nice(math.min(byIncome, cap)))
end

local function giveSpeed(x: Data, speed: number, minutes: number)
	local b, now = x.boosts, os.time()
	local mult = 1 + speed
	if now < b.speedUntil and b.speedMult >= mult then
		b.speedUntil += minutes * 60
	else
		b.speedMult, b.speedUntil = mult, now + minutes * 60
	end
end

-- ---------- badges ----------
local function award(player: Player, key: string)
	local d = DataService.get(player)
	local id = Config.badges[key]
	if not d or d.extra.badges[key] or typeof(id) ~= "number" or id == 0 then
		return -- not made yet: given later, once the badge exists (nothing is marked)
	end
	local ok = pcall(function()
		if not BadgeService:UserHasBadgeAsync(player.UserId, id) then
			BadgeService:AwardBadge(player.UserId, id)
		end
	end)
	if ok then
		DataService.mutate(player, function(x)
			x.extra.badges[key] = true
		end)
	end
end

local function checkBadges(player: Player, d: Data)
	local e = d.extra
	local want = {
		first_freeze = d.stats.frozen >= 1,
		first_rebirth = d.rebirths >= 1,
		island_5 = d.reach >= 5,
		island_10 = d.reach >= 10,
		first_secret = (e.ev.secret or 0) >= 1,
		streak_50 = e.streakBest >= 50,
		login_7 = e.login.cycles >= 1,
		first_trade = e.trades >= 1,
		skins_5 = ownedCount(player, d) >= 5,
		weekly_all = e.weekly.champion,
		frozen_legend = (e.ev.legend or 0) >= 1,
	}
	for key, yes in want do
		if yes and not e.badges[key] and (Config.badges :: any)[key] ~= 0 then
			task.spawn(award, player, key)
		end
	end
end

-- ---------- the over-head tag: VIP / rebirth title and the Freeze Streak (everyone sees it) ----------
local function tagOf(player: Player): BillboardGui?
	local head = player.Character and player.Character:FindFirstChild("Head")
	if not head then
		return nil
	end
	local g = head:FindFirstChild("IceTag") :: BillboardGui?
	if g then
		return g
	end
	local b = Instance.new("BillboardGui")
	b.Name = "IceTag"
	b.Size = UDim2.fromOffset(220, 80)
	b.StudsOffset = Vector3.new(0, 3.3, 0)
	b.MaxDistance = 90
	b.LightInfluence = 0
	b.ResetOnSpawn = false
	local function line(name: string, y: number, h: number): TextLabel
		local t = Instance.new("TextLabel")
		t.Name = name
		t.BackgroundTransparency = 1
		t.Size = UDim2.fromScale(1, h)
		t.Position = UDim2.fromScale(0, y)
		t.Font = Enum.Font.FredokaOne
		t.TextScaled = true
		t.TextColor3 = Color3.new(1, 1, 1)
		t.Text = ""
		local s = Instance.new("UIStroke")
		s.Thickness = 2.5
		s.Color = Color3.fromHex("1b1433")
		s.Parent = t
		t.Parent = b
		return t
	end
	line("Title", 0, 0.3)
	line("Streak", 0.32, 0.38)
	line("Friends", 0.72, 0.28)
	b.Parent = head
	return b
end

local function refreshTag(player: Player)
	local d = DataService.get(player)
	local g = d and tagOf(player)
	if not d or not g then
		return
	end
	local title = g:FindFirstChild("Title") :: TextLabel
	local st = g:FindFirstChild("Streak") :: TextLabel
	local rt = Config.rebirthTitle(d.rebirths)
	if isVip(player) then
		title.Text = if rt and d.rebirths >= 2 then `VIP · {rt.name}` else "VIP"
		title.TextColor3 = Color3.fromHex("ffd700")
	elseif rt and d.rebirths >= 2 then
		title.Text = rt.name
		title.TextColor3 = rt.color
	else
		title.Text = ""
	end
	local n = streak[player] or 0
	local tier = Config.streakTier(n)
	if n >= Config.streak.showFrom and tier then
		st.Text = `x{n} STREAK`
		st.TextColor3 = tier.color
	else
		st.Text = ""
	end
	-- the friend boost (Config.friends), so friends playing together see it on each other
	local fr = g:FindFirstChild("Friends") :: TextLabel?
	if fr then
		local f = PenService.friendsOf(d)
		fr.Text = if f > 0 then `+{math.round(f * Config.friends.perFriend * 100)}% FRIEND BOOST` else ""
		fr.TextColor3 = Color3.fromHex("ff9fd6")
	end
end

-- the Freeze Streak x VIP into income, the skin on the player (every client draws the beam from it)
local function applyPlayer(player: Player)
	local d = DataService.get(player)
	if not d then
		return
	end
	local m = (1 + Config.streakBonus(streak[player] or 0)) * (if isVip(player) then 1 + Config.vip.coinBonus else 1)
	PenService.setExtraMult(player, m)
	local skin = d.extra.skin
	if not ExtrasService.ownsSkin(player, d, skin) then
		skin = "default"
	end
	player:SetAttribute("RaySkin", if skin ~= "default" then skin else nil)
	player:SetAttribute("Streak", streak[player] or 0)
	refreshTag(player)
end

-- ---------- weekly quests ----------
local function defOf(id: string): Config.ChallengeDef?
	for _, c in Config.weekly.pool do
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
local function weeklyHave(d: Data, i: number): number
	local c = d.extra.weekly.list[i]
	local def = c and defOf(c.id)
	return if c and def then math.max(0, stat(d, def.stat) - c.from) else 0
end
local function weeklyReward(d: Data): number
	local W = Config.weekly
	return incomeReward(d, W.rewardMinutes, W.floor, W.capShare)
end
-- new week: hand out 3 quests (seeded by week + UserId, so a rejoin gets the same ones)
local function weeklyHandOut(player: Player, x: Data)
	local now = os.time()
	local wk = weekId(now)
	if x.extra.weekly.week == wk and #x.extra.weekly.list > 0 then
		return
	end
	local rng = Random.new(math.floor((now / 86400 + 3) / 7) * 104729 + player.UserId % 1000003)
	local pool = table.clone(Config.weekly.pool)
	local list = {}
	local income = PenService.incomePerSecond(x)
	for i = 1, math.min(Config.weekly.count, #pool) do
		local c = table.remove(pool, rng:NextInteger(1, #pool)) :: Config.ChallengeDef
		local goal = 1
		if c.incomeMinutes then
			goal = math.max(c.floor or 1, Config.nice(income * 60 * c.incomeMinutes[rng:NextInteger(1, #c.incomeMinutes)]))
		elseif c.goals then
			goal = c.goals[rng:NextInteger(1, #c.goals)]
		end
		list[i] = { id = c.id, goal = goal, from = stat(x, c.stat) }
	end
	x.extra.weekly = { week = wk, list = list, claimed = {}, allPaid = false, champion = x.extra.weekly.champion }
end

-- ---------- milestone chests ----------
local function chestState(d: Data): (number?, number) -- next chest index (nil = all opened), progress 0..1
	local i = d.extra.chests + 1
	local m = Config.milestones[i]
	if not m then
		return nil, 1
	end
	local price = Config.rebirthCost(d.rebirths + 1)
	local earned = math.max(0, d.stats.coinsEarned - d.extra.runFrom)
	return i, math.clamp(earned / math.max(1, price * m.at), 0, 1)
end

-- ---------- the client's view ----------
local function view(player: Player, d: Data): { [string]: any }
	local e = d.extra
	local skins = {}
	for _, s in Config.raySkins do
		local prog: number? = nil
		for _, es in Config.eventSkins do
			if es.skin == s.id then
				prog = math.min(es.need, e.ev[es.event] or 0) / es.need
			end
		end
		table.insert(skins, { id = s.id, owned = ExtrasService.ownsSkin(player, d, s.id), progress = prog })
	end
	local weekly = {}
	for i, c in e.weekly.list do
		local def = defOf(c.id)
		table.insert(weekly, { text = if def then def.text else "", goal = c.goal, have = math.min(c.goal, weeklyHave(d, i)),
			done = weeklyHave(d, i) >= c.goal, claimed = e.weekly.claimed[i] == true })
	end
	local ci, cp = chestState(d)
	local today = WorldRules.dayId(os.time())
	local L = Config.login
	local nextDay = (e.login.n % #L.days) + 1
	return {
		streak = streak[player] or 0, streakBest = e.streakBest,
		skin = e.skin, skins = skins,
		login = { n = e.login.n, cycles = e.login.cycles, canClaim = e.login.day ~= today, nextDay = nextDay,
			nextCoins = incomeReward(d, L.days[nextDay].coins or 0, L.floor, L.capShare) },
		weekly = { list = weekly, coins = weeklyReward(d), resetsAt = workspace:GetServerTimeNow() + (weekEnds(os.time()) - os.time()),
			champion = e.weekly.champion },
		chest = { index = ci, progress = cp, name = if ci then Config.milestones[ci].name else nil,
			coins = if ci then Config.nice(Config.rebirthCost(d.rebirths + 1) * Config.milestones[ci].coinShare) else 0 },
		playSeconds = e.playSeconds, starter = e.starter, vip = isVip(player),
		tradeOk = player:GetAttribute("TradeOk") == true,
		muted = (function()
			local out = {}
			for id in muted[player] or {} do
				table.insert(out, id)
			end
			return out
		end)(),
	}
end
PenService.extrasView = view

local function push(player: Player)
	applyPlayer(player)
	PenService.markDirty(player)
end

-- ---------- claims ----------
local function claimLogin(player: Player)
	local d = DataService.get(player)
	local today = WorldRules.dayId(os.time())
	if not d or d.extra.login.day == today then
		return
	end
	local L = Config.login
	local dayN = (d.extra.login.n % #L.days) + 1
	local r = L.days[dayN]
	local coins = if r.coins then incomeReward(d, r.coins, L.floor, L.capShare) else 0
	local skinNew = false
	DataService.mutate(player, function(x)
		x.extra.login.day = today
		x.extra.login.n = dayN
		if dayN == #L.days then
			x.extra.login.cycles += 1
			x.extra.login.n = 0
		end
		if coins > 0 then
			PenService.addCoins(x, coins)
		end
		x.superFreezeCharges = math.min(x.superFreezeCharges + (r.superFreeze or 0), 999)
		if r.speed then
			giveSpeed(x, r.speed, r.minutes or 10)
		end
		if r.skin and not x.extra.skins[r.skin] then
			x.extra.skins[r.skin] = true
			skinNew = true
		end
	end)
	if coins > 0 then
		AnalyticsSvc.coinsIn(player, coins, "login")
	end
	BoostService.refresh(player)
	DataService.saveNow(player) -- the reward and the day stamp in one save
	Remotes.fire(player, "Notify", "loginClaimed", { day = dayN, coins = coins, superFreeze = r.superFreeze, speed = r.speed, skin = if skinNew then r.skin else nil })
	push(player)
end

local function claimWeekly(player: Player, i: any)
	if typeof(i) ~= "number" or i ~= math.floor(i) or i < 1 or i > Config.weekly.count then
		return
	end
	local d = DataService.get(player)
	if not d then
		return
	end
	local w = d.extra.weekly
	local c = w.list[i]
	if not c or w.claimed[i] or w.week ~= weekId(os.time()) then
		return
	end
	if weeklyHave(d, i) < c.goal then
		Remotes.notYet(player, "Not done yet", "daily")
		return
	end
	local coins = weeklyReward(d)
	local W = Config.weekly
	local skinNew, allNow = false, false
	DataService.mutate(player, function(x)
		local xw = x.extra.weekly
		xw.claimed[i] = true
		PenService.addCoins(x, coins)
		x.superFreezeCharges = math.min(x.superFreezeCharges + W.superFreeze, 999)
		local all = true
		for k in xw.list do
			all = all and xw.claimed[k] == true
		end
		if all and not xw.allPaid then
			xw.allPaid = true
			allNow = true
			if not xw.champion then
				xw.champion = true
				x.extra.skins.champion = true
				skinNew = true
			else
				x.superFreezeCharges = math.min(x.superFreezeCharges + W.allBonus, 999)
			end
		end
	end)
	AnalyticsSvc.coinsIn(player, coins, "weekly")
	DataService.saveNow(player)
	Remotes.fire(player, "Notify", "weeklyClaimed", { coins = coins, superFreeze = W.superFreeze, all = allNow, skin = if skinNew then "champion" else nil })
	push(player)
end

local function claimChest(player: Player)
	local d = DataService.get(player)
	if not d then
		return
	end
	local i, p = chestState(d)
	if not i or p < 1 then
		return
	end
	local m = Config.milestones[i]
	local coins = Config.nice(Config.rebirthCost(d.rebirths + 1) * m.coinShare)
	DataService.mutate(player, function(x)
		if x.extra.chests + 1 ~= i then
			return
		end
		x.extra.chests = i
		x.coins = math.min(x.coins + coins, 1e15) -- straight on (not "earned"): a chest never fills the next chest
		x.superFreezeCharges = math.min(x.superFreezeCharges + (m.superFreeze or 0), 999)
		if m.speed then
			giveSpeed(x, m.speed, m.minutes or 10)
		end
	end)
	AnalyticsSvc.coinsIn(player, coins, "chest")
	BoostService.refresh(player)
	DataService.saveNow(player)
	Remotes.fire(player, "Notify", "chestOpened", { index = i, name = m.name, coins = coins, superFreeze = m.superFreeze, speed = m.speed })
	push(player)
end

local function equipSkin(player: Player, id: any)
	local d = DataService.get(player)
	if not d or not Remotes.isId(id, 16) or not Config.raySkin(id) then
		return
	end
	if not ExtrasService.ownsSkin(player, d, id) then
		Remotes.notYet(player, "Not unlocked yet")
		return
	end
	DataService.mutate(player, function(x)
		x.extra.skin = id
	end)
	AnalyticsSvc.event(player, "skin_equip", { skin = id })
	push(player)
end

-- ---------- chat mute (server side, Config.safety) ----------
local function toggleMute(player: Player, userId: any)
	if typeof(userId) ~= "number" or userId ~= math.floor(userId) or userId == player.UserId then
		return
	end
	local list = muted[player] or {}
	muted[player] = list
	if list[userId] then
		list[userId] = nil
	else
		local n = 0
		for _ in list do
			n += 1
		end
		if n >= Config.safety.maxMuted then
			return
		end
		list[userId] = true
	end
	PenService.markDirty(player)
end

local function hookChannel(ch: Instance)
	if not ch:IsA("TextChannel") then
		return
	end
	-- (message, textSource of the RECEIVER): false = this receiver doesn't get it
	ch.ShouldDeliverCallback = function(message: TextChatMessage, target: TextSource): boolean
		local from = message.TextSource
		local receiver = target and Players:GetPlayerByUserId(target.UserId)
		if from and receiver then
			local list = muted[receiver]
			if list and list[from.UserId] then
				return false
			end
		end
		return true
	end
end

-- ---------- hooks ----------
local function onBanked(player: Player, pets: { { key: string, tier: string, rank: number, mut: string? } })
	local d = DataService.get(player)
	if not d then
		return
	end
	local before = streak[player] or 0
	local n = before + #pets
	streak[player] = n
	local ev = EventService.current()
	local skinsNew: { string } = {}
	local legend = false
	DataService.mutate(player, function(x)
		local e = x.extra
		e.streakBest = math.max(e.streakBest, n)
		for _, p in pets do
			for _, es in Config.eventSkins do
				local on = if es.event == "secret" then p.tier == "Secret" else (ev ~= nil and ev.id == es.event)
				if on and (es.rank == nil or p.rank >= es.rank) and (es.mut == nil or p.mut == es.mut) then
					e.ev[es.event] = (e.ev[es.event] or 0) + 1
					if e.ev[es.event] >= es.need and not e.skins[es.skin] then
						e.skins[es.skin] = true
						table.insert(skinsNew, es.skin)
					end
				end
			end
			if p.tier == "Secret" and n >= 100 then
				e.ev.legend = 1 -- the Secret badge (Config.badges.frozen_legend)
				legend = true
			end
		end
	end)
	-- tier marks: a pop for you, a shout for everyone from shoutFrom
	for _, t in Config.streak.tiers do
		if before < t.at and n >= t.at and t.name ~= "" then
			Remotes.fire(player, "Notify", "streakTier", { n = n, name = t.name, bonus = Config.streakBonus(n) })
			if t.at >= Config.streak.shoutFrom then
				Remotes.fireAll("Notify", "adminAbuse", { text = `{player.DisplayName} is on a {t.at} FREEZE STREAK! {t.name}!`, color = "luck", seconds = 5 })
			end
		end
	end
	for _, id in skinsNew do
		Remotes.fire(player, "Notify", "skinUnlocked", { id = id })
	end
	if legend then
		Remotes.fireAll("Notify", "adminAbuse", { text = `{player.DisplayName} became a FROZEN LEGEND!`, color = "luck", seconds = 7 })
	end
	push(player)
	checkBadges(player, d)
end

local function breakStreak(player: Player)
	local n = streak[player] or 0
	if n == 0 then
		return
	end
	streak[player] = 0
	if n >= Config.streak.showFrom then
		Remotes.fire(player, "Notify", "streakLost", { n = n })
	end
	push(player)
end

-- ---------- per-island time (analytics: where players spend time and where they stop) ----------
local function zoneTick(player: Player, final: boolean)
	local s = PlayerTracker.get(player)
	local zone = if s then (s :: any).zone else -1
	local now = os.clock()
	local cur = zoneSince[player]
	if cur and (final or cur.zone ~= zone) then
		if cur.zone >= 1 and now - cur.at >= 5 then
			local d = DataService.get(player)
			AnalyticsSvc.event(player, "island_time", { seconds = math.floor(now - cur.at), zone = tostring(cur.zone),
				left = if final then "left_game" else "moved", stage = AnalyticsSvc.stage(player) })
			local _ = d
		end
		cur = nil
	end
	if not cur and not final then
		zoneSince[player] = { zone = zone, at = now }
	elseif final then
		zoneSince[player] = nil
	end
end

function ExtrasService.Init() end

function ExtrasService.Start()
	Remotes.on("Extras", function(player: Player, action: any, arg: any)
		if action == "login" then
			claimLogin(player)
		elseif action == "weekly" then
			claimWeekly(player, arg)
		elseif action == "chest" then
			claimChest(player)
		elseif action == "skin" then
			equipSkin(player, arg)
		elseif action == "mute" then
			toggleMute(player, arg)
		end
	end)
	Hooks.Banked:Connect(onBanked)
	Hooks.Melted:Connect(breakStreak)
	Hooks.Lost:Connect(breakStreak)
	local function onLoaded(player: Player)
		streak[player] = 0
		DataService.mutate(player, function(x)
			weeklyHandOut(player, x)
		end)
		player.CharacterAdded:Connect(function()
			task.wait(0.5)
			refreshTag(player)
		end)
		player:GetAttributeChangedSignal("Pass_vip"):Connect(function()
			push(player)
		end)
		push(player)
	end
	DataService.Loaded:Connect(onLoaded)
	for _, p in Players:GetPlayers() do
		if DataService.isLoaded(p) then
			task.spawn(onLoaded, p)
		end
	end
	-- a rebirth starts a new chest run (RebirthService resets coins; the run counts coins earned from here)
	local lastRebirths: { [Player]: number } = {}
	DataService.Changed:Connect(function(player: Player)
		local d = DataService.get(player)
		if not d then
			return
		end
		local was = lastRebirths[player]
		lastRebirths[player] = d.rebirths
		if was and d.rebirths > was then
			DataService.mutate(player, function(x)
				x.extra.runFrom = x.stats.coinsEarned
				x.extra.chests = 0
			end)
			task.defer(push, player)
		end
	end)
	Players.PlayerRemoving:Connect(function(p)
		zoneTick(p, true)
		streak[p] = nil
		muted[p] = nil
		lastSent[p] = nil
		lastRebirths[p] = nil
		for _, list in muted do
			list[p.UserId] = nil
		end
	end)
	-- chat mute on every channel, now and later
	task.spawn(function()
		local channels = TextChatService:WaitForChild("TextChannels", 30)
		if channels then
			for _, ch in channels:GetChildren() do
				hookChannel(ch)
			end
			channels.ChildAdded:Connect(hookChannel)
		end
	end)
	-- every second: play time, a new week, chest ready, badges
	local tickN = 0
	while true do
		task.wait(1)
		tickN += 1
		for _, p in Players:GetPlayers() do
			local d = DataService.get(p)
			if not d then
				continue
			end
			DataService.mutateLight(p, function(x)
				x.extra.playSeconds += 1
			end)
			zoneTick(p, false)
			if tickN % 5 == 0 then
				if d.extra.weekly.week ~= weekId(os.time()) then
					DataService.mutate(p, function(x)
						weeklyHandOut(p, x)
					end)
				end
				-- a chest that just became ready, or weekly progress: send a fresh view now and then
				local ci, cp = chestState(d)
				local key = `{ci}:{cp >= 1}:{d.stats.frozen}:{d.stats.banked}:{d.daily.rares}`
				if lastSent[p] ~= key then
					lastSent[p] = key
					PenService.markDirty(p)
				end
				checkBadges(p, d)
				refreshTag(p) -- friends come and go
			end
		end
	end
end

return ExtrasService
