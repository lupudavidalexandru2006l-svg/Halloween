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

export type PetEntry = { id: string, key: string, pose: string, mut: string?, at: number, eq: boolean } -- eq = in the pen (earning); else in Storage
export type Settings = { music: boolean, sound: boolean, reducedMotion: boolean, lowGraphics: boolean, unit: string }
export type Data = {
	version: number,
	coins: number,
	pets: { PetEntry },
	nextPetId: number,
	upgrades: { [string]: number },
	found: { [string]: boolean },
	stats: { frozen: number, banked: number, melts: number, coinsEarned: number },
	rarest: { rank: number, key: string?, at: number },
	week: { id: string, coins: number },
	lastSeen: number,
	welcome: { coins: number, awaySeconds: number, capped: boolean, best: string? }?,
	gift: { lastDay: string, streak: number },
	funnel: { [string]: boolean },
	forestUnlocked: boolean,
	superFreezeCharges: number,
	superCubes: { { key: string, pose: string, mut: string? } }, -- bought Super Freeze cubes not yet banked (back on your back after a rejoin)
	lastBest: string?, -- best pet banked last session, shown in the welcome back (end on a high, on the return)
	receipts: { string },
	settings: Settings,
	createdAt: number,
	lock: { job: string, t: number }?,
}

local Remotes = require(script.Parent.Remotes)

local DataService = {}

local store: DataStore
local sessions: { [Player]: { data: Data, saving: boolean, wiping: boolean } } = {}
local loadedEvent = Instance.new("BindableEvent")
local changedEvent = Instance.new("BindableEvent")
DataService.Loaded = loadedEvent.Event -- (player, data)
DataService.Changed = changedEvent.Event -- (player)

local function defaults(): Data
	return {
		version = Config.version,
		coins = 0,
		pets = {},
		nextPetId = 1,
		upgrades = { ray = 1, boots = 1, backpack = 1, pen = 1 },
		found = {},
		stats = { frozen = 0, banked = 0, melts = 0, coinsEarned = 0 },
		rarest = { rank = 0, key = nil, at = 0 },
		week = { id = "", coins = 0 },
		lastSeen = 0,
		welcome = nil,
		gift = { lastDay = "", streak = 0 },
		funnel = {},
		forestUnlocked = false,
		superFreezeCharges = 0,
		superCubes = {},
		lastBest = nil,
		receipts = {},
		settings = table.clone(Config.settingsDefault) :: any,
		createdAt = os.time(),
		lock = nil,
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
	local slots = Config.pen.baseSlots + Config.upgrades.pen.slotsPerLevel * (d.upgrades.pen - 1)
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
			local eq = p.eq == true and inPen < slots
			if eq then
				inPen += 1
			end
			table.insert(d.pets, { id = id :: string, key = p.key, pose = knownPose(p.pose), mut = knownMut(p.mut), at = num(p.at, 0, 1e12), eq = eq })
		end
	end
	if inPen == 0 and #d.pets > 0 then -- an older save without flags: the best pets go in the pen
		local sorted = table.clone(d.pets)
		table.sort(sorted, function(a, b)
			local da, db = PetDefs.get(a.key), PetDefs.get(b.key)
			return PetDefs.income(da :: any, a.pose, a.mut) > PetDefs.income(db :: any, b.pose, b.mut)
		end)
		for i, p in sorted do
			p.eq = i <= slots
		end
	end
	for k, v in tbl(old.found) do
		if typeof(k) == "string" and v == true and PetDefs.get(k) then
			d.found[k] = true
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
	d.gift = { lastDay = str(g.lastDay, 10), streak = int(g.streak, 0, Config.dailyGift.streakMax) }
	for _, step in Config.analytics.funnel do
		if tbl(old.funnel)[step.name] == true then
			d.funnel[step.name] = true
		end
	end
	d.forestUnlocked = old.forestUnlocked == true
	d.superFreezeCharges = int(old.superFreezeCharges, 0, 999)
	for _, c in tbl(old.superCubes) do
		if #d.superCubes < 5 and typeof(c) == "table" and typeof(c.key) == "string" and PetDefs.get(c.key) then
			table.insert(d.superCubes, { key = c.key, pose = knownPose(c.pose), mut = knownMut(c.mut) })
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
	d.createdAt = num(old.createdAt, 0, 1e12, os.time())
	d.lastBest = if typeof(old.lastBest) == "string" and PetDefs.get(old.lastBest) then old.lastBest else nil
	if typeof(old.lock) == "table" and typeof(old.lock.job) == "string" then
		d.lock = { job = old.lock.job, t = num(old.lock.t, 0, 1e12) }
	end
	d.version = Config.version
	return d
end

local function keyFor(player: Player): string
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
				if lock and lock.job ~= game.JobId and os.time() - lock.t < 90 then
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
		return
	end
	if not loaded then
		-- never play on defaults: a child's progress is never overwritten
		player:Kick("We couldn't load your pets right now. Please rejoin in a minute - nothing is lost!")
		return
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
		return false
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
	local name = Config.data.storeName .. (if RunService:IsStudio() then Config.data.qaStoreSuffix else "")
	store = DataStoreService:GetDataStore(name)
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
		local t0 = os.clock()
		while pending > 0 and os.clock() - t0 < Config.data.bindToCloseSeconds do
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

-- write now (claims, purchases): the grant and its stamp land in the same save
function DataService.saveNow(player: Player): boolean
	return save(player, false)
end

-- dev command: really wipe (saving is blocked first, so the old save can't come back)
function DataService.wipe(player: Player)
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
