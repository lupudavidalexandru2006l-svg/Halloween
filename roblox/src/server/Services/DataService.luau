--!strict
-- DataService: the only owner of saved player data (Code Rules 7).
-- pcall + retries with backoff, a session lock so a quick rejoin can't load a stale save,
-- load gate (no play on defaults), save on leave + BindToClose + autosave, block saving while wiping,
-- versioned data merged into a defaults template. Studio uses a separate QA store.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local PetDefs = require(ReplicatedStorage.Shared.PetDefs)

-- eq = in the pen (earning); else in Storage. frozen = still in its ice cube (owner 2026-11-09): it
-- waits in your Pets until you put it in a Thaw Machine; thawM / thawEnd (os.time) / thawTotal = the
-- machine it's in and when it comes out. A frozen pet is never eq and earns nothing.
export type PetEntry = { id: string, key: string, pose: string, mut: string?, sz: string?, at: number, eq: boolean,
	frozen: boolean?, thawM: number?, thawEnd: number?, thawTotal: number?,
	inc: number? } -- inc: a limited egg pet's own income, fixed when it hatched (EggService, 2026-11-22)
export type Settings = { music: boolean, sound: boolean, reducedMotion: boolean, lowGraphics: boolean, unit: string, skipShows: boolean? }
-- tester switches, saved per tester; reset to these defaults on load for everyone else
export type TesterSettings = { mult: number, walk: number, instantFreeze: boolean, noMelt: boolean }
-- today's challenges (ChallengeService): which ones, each one's goal and the stat's value when handed out
export type DailyState = { day: string, list: { { id: string, goal: number, from: number } }, claimed: { boolean }, rares: number }
export type Data = {
	version: number,
	coins: number,
	pets: { PetEntry },
	nextPetId: number,
	upgrades: { [string]: number },
	found: { [string]: boolean },
	indexClaimed: { [string]: boolean }, -- Index pages claimed (zone id as a string): +10% coins each (IndexService)
	stats: { frozen: number, banked: number, melts: number, coinsEarned: number },
	rarest: { rank: number, key: string?, at: number },
	week: { id: string, coins: number },
	lastSeen: number,
	welcome: { coins: number, awaySeconds: number, capped: boolean, best: string? }?,
	gift: { claimed: boolean }, -- the one-time Free Gift (2026-11-12, was a daily gift)
	funnel: { [string]: boolean },
	forestUnlocked: boolean, -- kept in step with reach (reach >= 2) for older code
	reach: number, -- Round 4 phase 6: islands 1..reach have their gates open (rebirth keeps it)
	coldPower: number, -- the endless stat trained in the Frost Training Yard (never spent; rebirth resets it)
	coldRefund: number, -- coins paid back for the removed pan Cold Level, not yet shown to the player (PenService tells them once)
	superFreezeCharges: number,
	thawSkips: number, -- paid Thaw Machine skips not used yet (a skip bought just as the pet came out is kept for later)
	thawSkipAlls: number, -- paid Skip alls not used yet (bought just as every pet came out: kept for later)
	-- bought boosts (2026-11-18, MonetizationService): Speed Potion (mult, ends at os.time), Lucky Ray (ends), Critter
	-- Shield charges, the one-time Welcome Deal, and the last Welcome back coins (for 2x Welcome Back after collecting)
	boosts: { speedMult: number, speedUntil: number, luckUntil: number, shields: number, deal: boolean, lastWelcome: number },
	superCubes: { { key: string, pose: string, mut: string?, sz: string? } }, -- bought Super Freeze cubes not yet banked (back on your back after a rejoin)
	lastBest: string?, -- best pet banked last session, shown in the welcome back (end on a high, on the return)
	receipts: { string },
	settings: Settings,
	rebirths: number,
	seenShows: { [string]: boolean }, -- shows watched once (their SKIP button shows after that)
	guns: { best: number, equipped: number }, -- guns are bought in order, so the best one says which you own (Round 4 phase 4)
	pan: { look: number, trainer: number, thaw: number }, -- thaw: the Thaw Speed upgrade (2026-11-13) -- the pan's Look (Round 4 phase 5; Slots is upgrades.pen; Cold Level was removed 2026-11-10) and its Cold Power trainer (2026-11-10, Config.training.stations). Rebirth keeps both
	tester: TesterSettings,
	gear: { [string]: any }, -- gel (boolean) + every Config.gear key as a level 0-10 (2026-11-17 rework) -- bought at the Equipment Booth's Gear tab
	codes: { [string]: boolean }, -- codes already redeemed (Round 5)
	shieldLeft: number, -- seconds of the new-player tag shield still to use (counts down only while playing)
	daily: DailyState,
	tutorial: { step: number, done: boolean, gift: boolean?, paid: { [string]: boolean }? }, -- the tutorial (TutorialService): the step you're on, or done; gift = his coins for the first upgrade were given; paid = the lesson rewards already given (by step id)
	createdAt: number,
	lock: { job: string, t: number }?,
	extra: Extra, -- the 2026-11-19 "every score to 10" pass (ExtrasService)
	-- the limited Robux eggs (EggService, 2026-11-22): dry = eggs opened since the last Legendary or better (soft
	-- pity), opened = all eggs opened, got = how many of each limited pet you ever hatched
	egg: { dry: number, opened: number, got: { [string]: number } },
}
-- starter: Starter Pack bought; playSeconds: total play time; login: the calendar (day claimed last, days done this
-- cycle, cycles done); weekly: this week's quests; runFrom: stats.coinsEarned at the last rebirth; chests: milestone
-- chests opened this run; ev: event-skin progress; skins: earned skins (rebirth / VIP / starter ones are worked out,
-- not stored); skin: the equipped one; streakBest; trades: trades done; badges: achievement badges already given
export type Extra = {
	starter: boolean, playSeconds: number,
	login: { day: string, n: number, cycles: number },
	weekly: { week: string, list: { { id: string, goal: number, from: number } }, claimed: { boolean }, allPaid: boolean, champion: boolean },
	runFrom: number, chests: number,
	ev: { [string]: number }, skins: { [string]: boolean }, skin: string,
	streakBest: number, trades: number, badges: { [string]: boolean },
}
local function extraDefaults(): Extra
	return {
		starter = false, playSeconds = 0,
		login = { day = "", n = 0, cycles = 0 },
		weekly = { week = "", list = {}, claimed = {}, allPaid = false, champion = false },
		runFrom = 0, chests = 0,
		ev = {}, skins = {}, skin = "default",
		streakBest = 0, trades = 0, badges = {},
	}
end

local function testerDefaults(): TesterSettings
	return { mult = 1, walk = 0, instantFreeze = false, noMelt = false } -- walk 0 = normal speed
end

local Remotes = require(script.Parent.Remotes)

local DataService = {}

local store: DataStore
local storeName = ""
local isQaStore = false
local sessions: { [Player]: { data: Data, saving: boolean, wiping: boolean } } = {}
local loadedEvent = Instance.new("BindableEvent")
local changedEvent = Instance.new("BindableEvent")
DataService.Loaded = loadedEvent.Event -- (player, data)
DataService.Changed = changedEvent.Event -- (player)
-- (player): only coins, Cold Power or stats moved (the pan's income every second, a training shot). Listeners
-- that only show those numbers hear this too; the client then gets just those numbers, not the whole save
local lightChangedEvent = Instance.new("BindableEvent")
DataService.LightChanged = lightChangedEvent.Event

local function defaults(): Data
	return {
		version = Config.version,
		coins = 0,
		pets = {},
		nextPetId = 1,
		upgrades = { ray = 1, boots = 1, backpack = 1, pen = 1 },
		found = {},
		indexClaimed = {},
		stats = { frozen = 0, banked = 0, melts = 0, coinsEarned = 0 },
		rarest = { rank = 0, key = nil, at = 0 },
		week = { id = "", coins = 0 },
		lastSeen = 0,
		welcome = nil,
		gift = { claimed = false },
		funnel = {},
		forestUnlocked = false,
		reach = 1,
		coldPower = 0,
		coldRefund = 0,
		superFreezeCharges = 0,
		thawSkips = 0,
		thawSkipAlls = 0,
		boosts = { speedMult = 1, speedUntil = 0, luckUntil = 0, shields = 0, deal = false, lastWelcome = 0 },
		superCubes = {},
		lastBest = nil,
		receipts = {},
		settings = table.clone(Config.settingsDefault) :: any,
		rebirths = 0,
		seenShows = {},
		guns = { best = 1, equipped = 1 },
		pan = { look = 1, trainer = 1, thaw = 1 },
		tester = testerDefaults(),
		gear = { gel = false },
		codes = {},
		shieldLeft = Config.tag.shieldMinutes * 60,
		daily = { day = "", list = {}, claimed = {}, rares = 0 },
		tutorial = { step = 1, done = false },
		createdAt = os.time(),
		lock = nil,
		extra = extraDefaults(),
		egg = { dry = 0, opened = 0, got = {} },
	}
end

-- Every field is type- and range-checked on load, so a damaged or old save can't break the join or
-- carry impossible values (prototype QA, CA-11). Old saves get new fields from the defaults.
local function num(v: any, lo: number, hi: number, default: number?): number
	if typeof(v) == "number" and v == v and v > -math.huge and v < math.huge then
		return math.clamp(v, lo, hi)
	end
	return default or lo
end
local function int(v: any, lo: number, hi: number, default: number?): number
	return math.floor(num(v, lo, hi, default))
end
local function str(v: any, maxLen: number): string
	return if typeof(v) == "string" and #v <= maxLen then v else ""
end
local function tbl(v: any): { [any]: any }
	return if typeof(v) == "table" then v else {}
end
local function knownPose(v: any): string
	return if typeof(v) == "string" and Config.poses[v] then v else "idle"
end
local function knownMut(v: any): string?
	return if typeof(v) == "string" and Config.mutations[v] then v else nil
end
-- Big ... Cosmic (Config.sizes; an old name goes through Config.sizeRenamed); anything else (and every pet
-- saved before sizes) is a normal pet
local function knownSize(v: any): string?
	local n = if typeof(v) == "string" then Config.sizeRenamed[v] or v else v
	return if Config.size(n) then n else nil
end

local function migrate(old: any): Data
	local d = defaults()
	if typeof(old) ~= "table" then
		return d
	end
	d.coins = num(old.coins, 0, 1e15)
	for _, id in Config.upgradeIds do
		d.upgrades[id] = int(tbl(old.upgrades)[id], 1, Config.upgrades[id].maxLevel, 1)
	end
	-- pets: each has an id and an "in the pen" flag; never more in the pen than it has slots
	d.nextPetId = int(old.nextPetId, 1, 1e9, 1)
	local seen: { [string]: boolean } = {}
	local slots = Config.panSlots(d.upgrades.pen, int(old.rebirths, 0, 1e6)) -- rebirth slots count too (Round 4 phase 7)
	local inPen = 0
	for _, p in tbl(old.pets) do
		if #d.pets >= Config.pen.storageMax then
			break
		end
		if typeof(p) == "table" and typeof(p.key) == "string" and PetDefs.get(p.key) then
			local id = if typeof(p.id) == "string" and #p.id <= 12 and not seen[p.id] then p.id else nil
			if not id then
				id = "q" .. d.nextPetId
				d.nextPetId += 1
			end
			seen[id :: string] = true
			local frozen = p.frozen == true
			local eq = p.eq == true and inPen < slots and not frozen
			if eq then
				inPen += 1
			end
			local entry: PetEntry = { id = id :: string, key = p.key, pose = knownPose(p.pose), mut = knownMut(p.mut), sz = knownSize(p.sz), at = num(p.at, 0, 1e12), eq = eq }
			if PetDefs.isLimited(p.key) then
				entry.inc = num(p.inc, 0, 1e15, 0) -- a limited pet keeps the income it hatched with
			end
			if frozen then
				entry.frozen = true
				-- every machine a pan can have (was 2: a pet in Thaw Machine 3 moved into machine 2 on every rejoin)
				local m = int(p.thawM, 0, #Config.thaw.machinesAt, 0)
				if m >= 1 and typeof(p.thawEnd) == "number" then -- in a Thaw Machine: keeps its time (PenService checks the machine is still free)
					entry.thawM = m
					entry.thawEnd = num(p.thawEnd, 0, 1e12)
					entry.thawTotal = num(p.thawTotal, 1, 1e8, 1)
				end
			end
			table.insert(d.pets, entry)
		end
	end
	if inPen == 0 and #d.pets > 0 then -- an older save without flags: the best pets go in the pen
		local sorted = {}
		for _, p in d.pets do
			if not p.frozen then
				table.insert(sorted, p)
			end
		end
		table.sort(sorted, function(a, b)
			local da, db = PetDefs.get(a.key), PetDefs.get(b.key)
			return PetDefs.income(da :: any, a.pose, a.mut, a.sz, a.inc) > PetDefs.income(db :: any, b.pose, b.mut, b.sz, b.inc)
		end)
		for i, p in sorted do
			p.eq = i <= slots
		end
	end
	do -- the limited eggs (2026-11-22)
		local e = tbl(old.egg)
		d.egg.dry = int(e.dry, 0, 1e6, 0)
		d.egg.opened = int(e.opened, 0, 1e7, 0)
		for k, n in tbl(e.got) do
			if typeof(k) == "string" and PetDefs.isLimited(k) then
				d.egg.got[k] = int(n, 0, 1e7, 0)
			end
		end
	end
	for k, v in tbl(old.found) do
		if typeof(k) == "string" and v == true and PetDefs.get(k) then
			d.found[k] = true
		end
	end
	if typeof(old.indexClaimed) == "table" then
		for _, z in Config.world.zones do
			if old.indexClaimed[tostring(z.id)] == true then
				d.indexClaimed[tostring(z.id)] = true
			end
		end
	else
		-- a save from before Claim (2026-11-09): a page that was full by the old rule (every pet but the
		-- Secret) already paid its +10%, so it counts as claimed and nobody loses a bonus they had
		for _, z in Config.world.zones do
			local full, any = true, false
			for _, def in PetDefs.inZone(z.id) do
				if def.tier ~= "Secret" then
					any = true
					full = full and d.found[def.key] == true
				end
			end
			if z.ready and any and full then
				d.indexClaimed[tostring(z.id)] = true
			end
		end
	end
	local st = tbl(old.stats)
	d.stats = { frozen = num(st.frozen, 0, 1e15), banked = num(st.banked, 0, 1e15), melts = num(st.melts, 0, 1e15), coinsEarned = num(st.coinsEarned, 0, 1e15) }
	local ra = tbl(old.rarest)
	d.rarest = { rank = int(ra.rank, 0, 7), key = if typeof(ra.key) == "string" and PetDefs.get(ra.key) then ra.key else nil, at = num(ra.at, 0, 1e12) }
	local wk = tbl(old.week)
	d.week = { id = str(wk.id, 10), coins = num(wk.coins, 0, Config.leaderboards.limits.weekCoins) }
	d.lastSeen = num(old.lastSeen, 0, 1e12)
	if typeof(old.welcome) == "table" then
		local best = old.welcome.best
		d.welcome = { coins = math.floor(num(old.welcome.coins, 0, 1e15)), awaySeconds = num(old.welcome.awaySeconds, 0, 1e9), capped = old.welcome.capped == true, best = if typeof(best) == "string" and PetDefs.get(best) then best else nil }
	end
	local g = tbl(old.gift)
	d.gift = { claimed = g.claimed == true } -- old daily-gift saves (lastDay/streak) start unclaimed: everyone gets the one-time gift once
	for _, step in Config.analytics.funnel do
		if tbl(old.funnel)[step.name] == true then
			d.funnel[step.name] = true
		end
	end
	d.forestUnlocked = old.forestUnlocked == true
	d.reach = math.max(int(old.reach, 1, math.max(1, #Config.world.zones), 1), if d.forestUnlocked then 2 else 1) -- old saves: the Forest flag
	d.forestUnlocked = d.reach >= 2
	-- a save from before Cold Power starts at the need of its highest open island, so nobody is locked out
	d.coldPower = if typeof(old.coldPower) == "number" then num(old.coldPower, 0, Config.coldPower.max) else Config.need(d.reach)
	d.superFreezeCharges = int(old.superFreezeCharges, 0, 999)
	d.thawSkips = int(old.thawSkips, 0, 999)
	d.thawSkipAlls = int(old.thawSkipAlls, 0, 99)
	local bo = tbl(old.boosts)
	d.boosts = {
		speedMult = num(bo.speedMult, 1, 2, 1), speedUntil = num(bo.speedUntil, 0, 4e9, 0), luckUntil = num(bo.luckUntil, 0, 4e9, 0),
		shields = int(bo.shields, 0, 999, 0), deal = bo.deal == true, lastWelcome = num(bo.lastWelcome, 0, 1e15, 0),
	}
	for _, c in tbl(old.superCubes) do
		if #d.superCubes < 5 and typeof(c) == "table" and typeof(c.key) == "string" and PetDefs.get(c.key) then
			table.insert(d.superCubes, { key = c.key, pose = knownPose(c.pose), mut = knownMut(c.mut), sz = knownSize(c.sz) })
		end
	end
	for _, r in tbl(old.receipts) do
		if typeof(r) == "string" and #r <= 64 and #d.receipts < Config.data.receiptsKept then
			table.insert(d.receipts, r)
		end
	end
	local se = tbl(old.settings)
	for k, v in Config.settingsDefault :: { [string]: any } do
		if typeof(se[k]) == typeof(v) and (k ~= "unit" or se[k] == "C" or se[k] == "F") then
			(d.settings :: any)[k] = se[k]
		end
	end
	d.rebirths = int(old.rebirths, 0, 1e6)
	for k, v in tbl(old.seenShows) do
		if typeof(k) == "string" and v == true and (Config.show :: any)[k] then
			d.seenShows[k] = true
		end
	end
	local gu = tbl(old.guns)
	d.guns.best = int(gu.best, 1, #Config.guns.list, 1)
	d.guns.equipped = int(gu.equipped, 1, d.guns.best, d.guns.best)
	local pa = tbl(old.pan)
	-- the pan's Cold Level is gone (Cold Power remake, 2026-11-10): the coins spent on it come back.
	-- The level itself isn't copied, so a save written from now on has nothing left to refund.
	local refund = 0
	for n = Config.pan.coldStart + 1, int(pa.cold, Config.pan.coldStart, 20, Config.pan.coldStart) do
		refund += Config.pan.coldRefund[n] or 0
	end
	-- the Speed pan upgrade is gone too (owner 2026-11-15: speed comes from Gear): its coins come back
	-- and the level goes back to 1, so this pays out once
	for n = 1, d.upgrades.boots - 1 do
		refund += Config.pan.speedRefund[n] or 0
	end
	d.upgrades.boots = 1
	d.coins = math.min(d.coins + refund, 1e15)
	d.coldRefund = math.min(num(old.coldRefund, 0, 1e15) + refund, 1e15)
	d.pan.look = int(pa.look, 1, #Config.pan.looks, 1)
	d.pan.trainer = int(pa.trainer, 1, #Config.training.stations, 1)
	d.pan.thaw = int(pa.thaw, 1, Config.panMax("thaw"), 1)
	local te = tbl(old.tester)
	d.tester = {
		mult = num(te.mult, Config.dev.multMin, Config.dev.multMax, 1),
		walk = if te.walk == 0 then 0 else num(te.walk, Config.dev.walkMin, Config.dev.walkMax, 0),
		instantFreeze = te.instantFreeze == true,
		noMelt = te.noMelt == true,
	}
	local og = tbl(old.gear)
	-- removed gear (owner 2026-11-17): Slow Gel, Magnet Gloves, Cooling Vest. What they cost comes back once;
	-- the save keeps none of them, so a save written from now on has nothing left to pay back
	local gearBack = if og.gel == true then Config.gel.price else 0
	for key, r in Config.gearRefund do
		local v = og[key]
		if v == true then
			gearBack += r.old
		elseif typeof(v) == "number" then
			for n = 0, int(v, 0, Config.gearMax, 0) - 1 do
				gearBack += r.start * Config.gearGrowth ^ n
			end
		end
	end
	d.gear.gel = false
	for _, g in Config.gear do
		d.gear[g.key] = if typeof(og[g.key]) == "number" then int(og[g.key], 0, Config.gearMaxOf(g.key), 0) else 0
	end
	-- gear bought once before the 2026-11-17 rework (true): at least as strong as it was, never weaker.
	-- Ice Skates (x1.2 when carrying) and the old Frost Boots (pets flee slower) both become Frost Boots levels.
	local function atLeast(key: string, level: number)
		d.gear[key] = math.max(d.gear[key], level)
	end
	if og.cozy_hat == true then atLeast("cozy_hat", 4) end -- was +10% coins
	atLeast("frost_boots", (if og.ice_skates == true then 4 else 0) + (if og.frost_boots == true then 2 else 0))
	if gearBack > 0 then
		d.coins = math.min(d.coins + gearBack, 1e15)
		d.coldRefund = math.min(d.coldRefund + gearBack, 1e15) -- PenService says "coins back" once
	end
	for k, v in tbl(old.codes) do
		if typeof(k) == "string" and #k <= Config.codes.maxLength and v == true then
			d.codes[k] = true
		end
	end
	d.shieldLeft = num(old.shieldLeft, 0, Config.tag.shieldMinutes * 60, 0) -- saves from before the shield was saved aren't new players
	local da = tbl(old.daily)
	local oldList = tbl(da.list)
	d.daily.day = str(da.day, 16)
	d.daily.rares = int(da.rares, 0, 1e9, 0)
	for i = 1, math.min(#oldList, Config.challenges.perDay) do
		local c = oldList[i]
		if typeof(c) == "table" and typeof(c.id) == "string" and #c.id <= 16 then
			d.daily.list[i] = { id = c.id, goal = num(c.goal, 1, 1e15, 1), from = num(c.from, 0, 1e15, 0) }
			d.daily.claimed[i] = tbl(da.claimed)[i] == true
		end
	end
	if #d.daily.list ~= math.min(#oldList, Config.challenges.perDay) then
		d.daily = { day = "", list = {}, claimed = {}, rares = d.daily.rares } -- damaged: handed out fresh
	end
	-- a save from before the tutorial existed is a player who already knows the game (Lessons:
	-- new-player things are for new players only); they can still replay it from Settings
	local tu = old.tutorial
	if typeof(tu) == "table" then
		local paid: { [string]: boolean } = {}
		for _, s in Config.tutorial.steps do
			if s.reward and typeof(tu.paid) == "table" and tu.paid[s.id] == true then
				paid[s.id] = true
			end
		end
		-- the gear step's coin top-up (TutorialService) is once per save too: it was dropped here, so replaying the
		-- tutorial after a rejoin topped your coins up to your next gear level's price again and again
		if typeof(tu.paid) == "table" and tu.paid.gearGift == true then
			paid.gearGift = true
		end
		d.tutorial = { step = int(tu.step, 1, #Config.tutorial.steps, 1), done = tu.done == true, gift = tu.gift == true, paid = paid }
	else
		-- nothing to earn on a replay: every lesson reward counts as given
		local paid: { [string]: boolean } = {}
		for _, s in Config.tutorial.steps do
			if s.reward then
				paid[s.id] = true
			end
		end
		paid.gearGift = true
		d.tutorial = { step = #Config.tutorial.steps, done = true, gift = true, paid = paid }
	end
	d.createdAt = num(old.createdAt, 0, 1e12, os.time())
	d.lastBest = if typeof(old.lastBest) == "string" and PetDefs.get(old.lastBest) then old.lastBest else nil
	if typeof(old.lock) == "table" and typeof(old.lock.job) == "string" then
		d.lock = { job = old.lock.job, t = num(old.lock.t, 0, 1e12) }
	end
	-- the 2026-11-19 extras: every field checked, unknown keys dropped
	local ex = tbl(old.extra)
	local e = d.extra
	e.starter = ex.starter == true
	e.playSeconds = num(ex.playSeconds, 0, 1e10, 0)
	local lo = tbl(ex.login)
	e.login = { day = str(lo.day, 16), n = int(lo.n, 0, #Config.login.days, 0), cycles = int(lo.cycles, 0, 1e6, 0) }
	local we = tbl(ex.weekly)
	e.weekly = { week = str(we.week, 16), list = {}, claimed = {}, allPaid = we.allPaid == true, champion = we.champion == true }
	for i = 1, math.min(#tbl(we.list), Config.weekly.count) do
		local c = tbl(we.list)[i]
		if typeof(c) == "table" and typeof(c.id) == "string" and #c.id <= 16 then
			e.weekly.list[i] = { id = c.id, goal = num(c.goal, 1, 1e15, 1), from = num(c.from, 0, 1e15, 0) }
			e.weekly.claimed[i] = tbl(we.claimed)[i] == true
		else
			e.weekly = { week = "", list = {}, claimed = {}, allPaid = false, champion = e.weekly.champion } -- damaged: handed out fresh
			break
		end
	end
	e.runFrom = num(ex.runFrom, 0, 1e15, d.stats.coinsEarned)
	e.chests = int(ex.chests, 0, #Config.milestones, 0)
	if tbl(ex.ev).legend == 1 then
		e.ev.legend = 1 -- the Secret badge was earned
	end
	for _, es in Config.eventSkins do
		local v = tbl(ex.ev)[es.event]
		if typeof(v) == "number" then
			e.ev[es.event] = int(v, 0, 1e6, 0)
		end
	end
	for _, s in Config.raySkins do
		if tbl(ex.skins)[s.id] == true then
			e.skins[s.id] = true
		end
	end
	e.skin = if Config.raySkin(ex.skin) then ex.skin else "default"
	e.streakBest = int(ex.streakBest, 0, 1e9, 0)
	e.trades = int(ex.trades, 0, 1e9, 0)
	for k in Config.badges do
		if tbl(ex.badges)[k] == true then
			e.badges[k] = true
		end
	end
	d.version = Config.version
	return d
end

local function keyFor(player: Player): string
	local fresh = Config.dev.freshSave
	if isQaStore and typeof(fresh) == "string" and fresh ~= "" then
		return `u_{player.UserId}_{fresh}` -- Studio "play as a new player" (Config.dev.freshSave)
	end
	return "u_" .. player.UserId
end

local function withRetries<T>(fn: () -> T): (boolean, T | string)
	local wait = Config.data.retryBase
	local lastErr: any = nil
	for _ = 1, Config.data.retries do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		lastErr = result
		task.wait(wait)
		wait *= 2
	end
	return false, tostring(lastErr)
end

local function load(player: Player)
	local key = keyFor(player)
	local loaded: Data? = nil
	for _ = 1, Config.data.retries do
		local lockedByOther = false
		local ok, err = withRetries(function()
			return store:UpdateAsync(key, function(old: any)
				local d = migrate(old)
				local lock = d.lock
				if lock and lock.job ~= game.JobId and os.time() - lock.t < Config.data.lockStaleSeconds then
					lockedByOther = true
					return nil -- another server still owns this save: try again shortly
				end
				d.lock = { job = game.JobId, t = os.time() }
				loaded = d
				return d
			end)
		end)
		if not ok then
			warn(`[DataService] load failed for {player.UserId}: {err}`)
			break
		end
		if loaded or not lockedByOther then
			break
		end
		task.wait(3)
	end
	if not player.Parent then
		-- they left while the save was loading: free the lock this load just wrote, or a rejoin on another
		-- server within the stale time waits and is kicked with "couldn't load" (QA 2026-11-05, CA-02)
		if loaded then
			withRetries(function()
				return store:UpdateAsync(key, function(old: any)
					if typeof(old) == "table" and typeof(old.lock) == "table" and old.lock.job == game.JobId then
						old.lock = nil
						return old
					end
					return nil
				end)
			end)
		end
		return
	end
	if not loaded then
		-- never play on defaults: a child's progress is never overwritten
		player:Kick("We couldn't load your pets right now. Please rejoin in a minute - nothing is lost!")
		return
	end
	if not Config.isTester(player.UserId) then
		(loaded :: Data).tester = testerDefaults() -- tester switches never apply to anyone else
	end
	-- the tutorial carries on where a player left it (owner 2026-11-16: "still show the tutorial for people who
	-- left mid tutorial"); only Skip or finishing ends it. Its last step is the "Tutorial complete!" line (the
	-- reward is already paid there): a save left on it counts as finished, so it doesn't show again on a rejoin.
	local tu = (loaded :: Data).tutorial
	if not tu.done and tu.step >= #Config.tutorial.steps then
		tu.done = true
	end
	sessions[player] = { data = loaded :: Data, saving = false, wiping = false }
	loadedEvent:Fire(player, loaded)
end

local function save(player: Player, releaseLock: boolean): boolean
	local s = sessions[player]
	if not s or s.wiping then
		return false
	end
	if s.saving then
		if not releaseLock then
			return false -- an autosave or purchase save is already writing this data
		end
		-- leaving while another save runs (a purchase, then quitting at once): wait for it, then write
		-- again so the last changes land and the session lock is freed (final QA 2026-11-03: the lock
		-- stayed, so a rejoin on another server waited 90 s and was kicked)
		local t0 = os.clock()
		while s.saving and os.clock() - t0 < Config.data.bindToCloseSeconds do
			task.wait(0.1)
		end
		if s.saving or s.wiping then
			return false
		end
	end
	s.saving = true
	s.data.lastSeen = os.time()
	s.data.lock = if releaseLock then nil else { job = game.JobId, t = os.time() }
	local snapshot = s.data
	local ok, err = withRetries(function()
		return store:UpdateAsync(keyFor(player), function(old: any)
			if typeof(old) == "table" and old.lock and old.lock.job ~= game.JobId then
				return nil -- someone else owns it now; don't overwrite
			end
			return snapshot
		end)
	end)
	s.saving = false
	if not ok then
		warn(`[DataService] save failed for {player.UserId}: {err}`)
	end
	return ok
end

function DataService.Init()
	isQaStore = RunService:IsStudio()
	storeName = Config.data.storeName .. (if isQaStore then Config.data.qaStoreSuffix else "")
	store = DataStoreService:GetDataStore(storeName)
end

function DataService.Start()
	-- Settings are saved on the server (music, sound, reduced motion, low graphics, C or F)
	Remotes.on("SetSetting", function(player, key, value)
		local s = sessions[player]
		local default = (Config.settingsDefault :: any)[key]
		if not s or typeof(key) ~= "string" or default == nil or typeof(value) ~= typeof(default) then
			return
		end
		if key == "unit" and value ~= "C" and value ~= "F" then
			return
		end
		DataService.mutate(player, function(d)
			(d.settings :: any)[key] = value
		end)
	end)
	Players.PlayerAdded:Connect(load)
	for _, p in Players:GetPlayers() do
		task.spawn(load, p)
	end
	Players.PlayerRemoving:Connect(function(p)
		-- other services hear PlayerRemoving first (they connect in Start too), then this saves
		task.defer(function()
			save(p, true)
			sessions[p] = nil
		end)
	end)
	game:BindToClose(function()
		local pending = 0
		for p in sessions do
			pending += 1
			task.spawn(function()
				save(p, true)
				pending -= 1
			end)
		end
		-- also wait for saves already running (a PlayerRemoving save makes ours return at once; without
		-- this the server closed mid-save and the last player's progress was lost, QA 2026-10-31)
		local function saving(): boolean
			for _, s in sessions do
				if s.saving then
					return true
				end
			end
			return false
		end
		local t0 = os.clock()
		while (pending > 0 or saving()) and os.clock() - t0 < Config.data.bindToCloseSeconds do
			task.wait(0.2)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(Config.data.autosaveSeconds)
			for p in sessions do
				task.spawn(save, p, false)
			end
		end
	end)
end

function DataService.get(player: Player): Data?
	local s = sessions[player]
	return if s then s.data else nil
end

function DataService.isLoaded(player: Player): boolean
	return sessions[player] ~= nil
end

-- every change goes through here so listeners (HUD sync, leaderstats) hear about it
function DataService.mutate(player: Player, fn: (Data) -> ()): boolean
	local s = sessions[player]
	if not s or s.wiping then
		return false
	end
	fn(s.data)
	changedEvent:Fire(player)
	return true
end

-- a change that only touches coins, coldPower or stats (anything else must go through mutate): fires LightChanged
function DataService.mutateLight(player: Player, fn: (Data) -> ()): boolean
	local s = sessions[player]
	if not s or s.wiping then
		return false
	end
	fn(s.data)
	lightChangedEvent:Fire(player)
	return true
end

-- write now (claims, purchases): the grant and its stamp land in the same save
function DataService.saveNow(player: Player): boolean
	return save(player, false)
end

-- read-only look at any player's data (the leaderboard's Visit, owner 2026-11-20): the live copy when they're on
-- this server, else their save via GetAsync. Never writes, never takes the session lock, so it can't touch their
-- progress. nil when there's no save or the read failed after retries.
function DataService.peek(userId: number): any?
	for p, s in sessions do
		if p.UserId == userId then
			return s.data
		end
	end
	local ok, value = withRetries(function()
		return store:GetAsync("u_" .. userId)
	end)
	if ok and typeof(value) == "table" then
		return migrate(table.clone(value)) -- old saves get today's fields (a copy: nothing is written back)
	end
	return nil
end

-- "IceRayPlayerData_v1_QA / u_123": shown on the Tester panel
function DataService.saveKey(player: Player): (string, boolean)
	return `{storeName} / {keyFor(player)}`, isQaStore
end

-- tester tool: really wipe (saving is blocked first, so the old save can't come back).
-- Only ever on the QA store: a live server never wipes a real save.
function DataService.wipe(player: Player)
	if not isQaStore then
		return
	end
	local s = sessions[player]
	if s then
		s.wiping = true
	end
	withRetries(function()
		store:RemoveAsync(keyFor(player))
		return true
	end)
	player:Kick("Save wiped for testing. Rejoin to start fresh.")
end

return DataService
