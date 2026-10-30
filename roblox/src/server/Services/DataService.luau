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

export type PetEntry = { key: string, pose: string, mut: string?, at: number }
export type Data = {
	version: number,
	coins: number,
	pets: { PetEntry },
	upgrades: { [string]: number },
	found: { [string]: boolean },
	stats: { frozen: number, banked: number, melts: number, coinsEarned: number },
	rarest: { rank: number, key: string?, at: number },
	week: { id: string, coins: number },
	lastSeen: number,
	welcome: { coins: number, awaySeconds: number, capped: boolean }?,
	gift: { lastDay: string, streak: number },
	funnel: { [string]: boolean },
	forestUnlocked: boolean,
	superFreezeCharges: number,
	receipts: { string },
	createdAt: number,
	lock: { job: string, t: number }?,
}

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
		upgrades = { ray = 1, boots = 1, backpack = 1 },
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
		receipts = {},
		createdAt = os.time(),
		lock = nil,
	}
end

-- old saves get new fields; future versions migrate here
local function migrate(old: any): Data
	local d = defaults()
	if typeof(old) ~= "table" then
		return d
	end
	for k, v in old do
		if typeof(v) == "table" and typeof((d :: any)[k]) == "table" and k ~= "pets" and k ~= "receipts" then
			for k2, v2 in v do
				(d :: any)[k][k2] = v2
			end
		else
			(d :: any)[k] = v
		end
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
