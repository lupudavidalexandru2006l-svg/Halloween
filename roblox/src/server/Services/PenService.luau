--!strict
-- PenService: owns coins, income, banking, the pen and Storage, equip / Equip best, the coin gates,
-- the welcome back (25% while away, capped at 8 h, shows lastBest) and the daily gift (opens after
-- the first bank). It also sends each client its own copy of its data ("Data", throttled).
-- Every grant and its claim stamp are written in the same UpdateAsync (DataService.saveNow).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local PetDefs = require(ReplicatedStorage.Shared.PetDefs)
local WorldRules = require(ReplicatedStorage.Shared.WorldRules)
local Remotes = require(script.Parent.Remotes)
local DataService = require(script.Parent.DataService)
local AnalyticsSvc = require(script.Parent.AnalyticsSvc)
local PlayerTracker = require(script.Parent.PlayerTracker)
local WorldService = require(script.Parent.WorldService)
local CarryService = require(script.Parent.CarryService)
local IndexService = require(script.Parent.IndexService)

type Data = DataService.Data
type PetEntry = DataService.PetEntry

local PenService = {}

local incomeCarry: { [Player]: number } = {}
local sessionBest: { [Player]: number } = {}
local dirty: { [Player]: boolean } = {}
local bankingNow: { [Player]: boolean } = {}

local function earn(p: PetEntry): number
	local def = PetDefs.get(p.key)
	return if def then PetDefs.income(def, p.pose, p.mut) else 0
end

function PenService.slots(d: Data): number
	return Config.pen.baseSlots + Config.upgrades.pen.slotsPerLevel * (d.upgrades.pen - 1)
end

function PenService.equippedCount(d: Data): number
	local n = 0
	for _, p in d.pets do
		if p.eq then
			n += 1
		end
	end
	return n
end

-- only the pen's pets earn; each full Index page adds 10%
function PenService.incomePerSecond(d: Data): number
	local sum = 0
	for _, p in d.pets do
		if p.eq then
			sum += earn(p)
		end
	end
	return sum * IndexService.multiplier(d.found)
end

local function byEarnings(list: { PetEntry }): { PetEntry }
	local sorted = table.clone(list)
	table.sort(sorted, function(a, b)
		return earn(a) > earn(b)
	end)
	return sorted
end

local function equipBestIn(d: Data)
	local slots = PenService.slots(d)
	for i, p in byEarnings(d.pets) do
		p.eq = i <= slots
	end
end

-- new slots (Pen upgrade) take the best pets from Storage; the player's own picks stay
function PenService.fillEmptySlots(d: Data)
	local room = PenService.slots(d) - PenService.equippedCount(d)
	if room <= 0 then
		return
	end
	local stored = {}
	for _, p in d.pets do
		if not p.eq then
			table.insert(stored, p)
		end
	end
	for _, p in byEarnings(stored) do
		if room <= 0 then
			break
		end
		p.eq = true
		room -= 1
	end
end

-- every coin the game pays goes through here (weekly board counter included)
function PenService.addCoins(d: Data, n: number)
	if n <= 0 then
		return
	end
	d.coins += n
	d.stats.coinsEarned += n
	local w = WorldRules.weekId(os.time())
	if d.week.id ~= w then
		d.week = { id = w, coins = 0 } -- calendar reset (Monday UTC), nothing else is lost
	end
	d.week.coins = math.min(d.week.coins + n, Config.leaderboards.limits.weekCoins)
end

-- ---------- daily gift ----------
export type GiftState = { ready: boolean, locked: boolean, streak: number, nextStreak: number, coins: number }

function PenService.giftState(d: Data): GiftState
	local G = Config.dailyGift
	local today = WorldRules.dayId(os.time())
	local locked = G.afterFirstBank and d.stats.banked == 0
	local nextStreak = math.min(G.streakMax, d.gift.streak + 1)
	local base = math.max(G.baseCoins, PenService.incomePerSecond(d) * 60 * G.incomeMinutes)
	return {
		ready = not locked and d.gift.lastDay < today,
		locked = locked,
		streak = d.gift.streak,
		nextStreak = nextStreak,
		coins = math.round(base * (1 + G.streakBonus * (nextStreak - 1))),
	}
end

local function nearPart(player: Player, prompt: ProximityPrompt?, extra: number): boolean
	local pos = PlayerTracker.position(player)
	local parent = prompt and prompt.Parent
	local at: Vector3? = if parent and parent:IsA("Attachment") then parent.WorldPosition elseif parent and parent:IsA("BasePart") then parent.Position else nil
	return pos ~= nil and at ~= nil and (pos - at).Magnitude <= Config.player.freezeRange + extra
end

local function claimGift(player: Player)
	local d = DataService.get(player)
	if not d or not nearPart(player, WorldService.giftPrompt, 4) then
		return
	end
	local g = PenService.giftState(d)
	if not g.ready then
		Remotes.notYet(player, if g.locked then "Bank a pet first" else "Next gift tomorrow", "gift")
		return
	end
	DataService.mutate(player, function(x)
		x.gift = { lastDay = WorldRules.dayId(os.time()), streak = g.nextStreak }
		PenService.addCoins(x, g.coins)
	end)
	DataService.saveNow(player) -- grant and claim stamp in the same save
	Remotes.fire(player, "Notify", "giftClaimed", { coins = g.coins, streak = g.nextStreak })
end

-- ---------- welcome back ----------
local function checkWelcome(player: Player, d: Data)
	local now = os.time()
	if not d.welcome and d.lastSeen > 0 then
		local away = now - d.lastSeen
		local inc = PenService.incomePerSecond(d)
		if away >= Config.away.minSeconds and inc > 0 then
			local counted = math.min(away, Config.away.capSeconds)
			DataService.mutate(player, function(x)
				x.welcome = { coins = math.floor(inc * counted * Config.away.rate), awaySeconds = away, capped = away > Config.away.capSeconds, best = x.lastBest }
			end)
		end
	end
	DataService.saveNow(player) -- stamps lastSeen with the welcome, so a quick rejoin can't pay it twice
	if d.welcome then
		Remotes.fire(player, "Notify", "welcomeBack", d.welcome)
	end
end

local function collectWelcome(player: Player)
	local d = DataService.get(player)
	if not d or not d.welcome then
		return
	end
	local coins = d.welcome.coins
	DataService.mutate(player, function(x)
		PenService.addCoins(x, coins)
		x.welcome = nil
	end)
	DataService.saveNow(player) -- grant and clear in the same save
	Remotes.fire(player, "Notify", "welcomeCollected", { coins = coins })
end

-- dev command: pretend the player was away this long
function PenService.devAway(player: Player, seconds: number)
	local d = DataService.get(player)
	if d then
		d.welcome = nil
		d.lastSeen = os.time() - seconds
		checkWelcome(player, d)
	end
end

-- ---------- banking ----------
local function bank(player: Player)
	local d = DataService.get(player)
	if not d or bankingNow[player] or CarryService.count(player) == 0 then
		return
	end
	bankingNow[player] = true
	local cubes = CarryService.takeAll(player)
	local banked = {}
	local handBack = {}
	for _, c in cubes do
		local def = PetDefs.get(c.key)
		if not def then
			continue
		end
		if #d.pets >= Config.pen.storageMax then
			table.insert(handBack, c)
			continue
		end
		local rank = Config.tier(def.tier).rank
		local firstTime = not d.found[c.key]
		local eq = PenService.equippedCount(d) < PenService.slots(d) -- a free pen slot: it starts earning; else Storage
		DataService.mutate(player, function(x)
			table.insert(x.pets, { id = "q" .. x.nextPetId, key = c.key, pose = c.pose, mut = c.mut, at = os.time(), eq = eq })
			x.nextPetId += 1
			x.found[c.key] = true
			x.stats.banked += 1
			if rank > x.rarest.rank then
				x.rarest = { rank = rank, key = c.key, at = os.time() }
			end
			if rank >= (sessionBest[player] or 0) then
				sessionBest[player] = rank
				x.lastBest = c.key -- this session's best so far (shown in the next welcome back)
			end
		end)
		if firstTime then
			IndexService.onFound(player, c.key, d.found)
		end
		AnalyticsSvc.event(player, "pet_banked", { pet = c.key, tier = def.tier, pose = c.pose, carrySeconds = os.clock() - c.since })
		AnalyticsSvc.funnel(player, "first_carry_home") -- a cube frozen right by the hub still counts, before the bank
		AnalyticsSvc.funnel(player, "first_bank")
		if rank >= 3 then
			AnalyticsSvc.funnel(player, "first_rare_pet")
		end
		if rank >= Config.bigWinRank then
			-- others' wins, seen by everyone: a banner and a light pillar over this player's pen
			Remotes.fireAll("Notify", "bigWin", { name = player.DisplayName, key = c.key, tier = def.tier, plot = WorldService.plotOf(player) })
		end
		table.insert(banked, { key = c.key, pose = c.pose, mut = c.mut, income = PetDefs.income(def, c.pose, c.mut), firstTime = firstTime, stored = not eq })
	end
	for _, c in handBack do
		-- nothing is lost: cubes that don't fit go back on your back (paid ones back into the save)
		CarryService.addCube(player, { key = c.key, zone = c.zone, pose = c.pose, mut = c.mut, superFrozen = c.superFrozen, superUsed = c.superUsed, offered = c.offered })
	end
	if #handBack > 0 then
		Remotes.notYet(player, "Storage full", "pets")
	end
	if #banked > 0 then
		DataService.saveNow(player)
		Remotes.fire(player, "Notify", "banked", { banked = banked, income = PenService.incomePerSecond(d) })
	end
	bankingNow[player] = nil
end

-- ---------- equip ----------
local function equipPet(player: Player, id: any, on: any)
	local d = DataService.get(player)
	if not d or not Remotes.isId(id, 12) or typeof(on) ~= "boolean" then
		return
	end
	local entry: PetEntry? = nil
	for _, p in d.pets do
		if p.id == id then
			entry = p
			break
		end
	end
	if not entry or entry.eq == on then
		return
	end
	if on and PenService.equippedCount(d) >= PenService.slots(d) then
		Remotes.notYet(player, "Pen full: put one in Storage first", "pets")
		return
	end
	local e = entry :: PetEntry
	DataService.mutate(player, function()
		e.eq = on
	end)
end

local function equipBest(player: Player)
	if DataService.get(player) then
		DataService.mutate(player, equipBestIn)
	end
end

-- ---------- zone gates (owner 2026-10-30: pay coins at the gate) ----------
local function openGate(player: Player)
	local d = DataService.get(player)
	local zone = Config.zone(2)
	if not d or not zone or d.forestUnlocked or not nearPart(player, WorldService.gatePrompt, 4) then
		return
	end
	local price = zone.gateCoins
	if d.coins < price then
		Remotes.notYet(player, `Need {math.ceil(price - d.coins)} more coins`, "gate")
		return
	end
	DataService.mutate(player, function(x)
		x.coins -= price
		x.forestUnlocked = true
	end)
	DataService.saveNow(player) -- paid and opened in the same save
	WorldService.setForestOpen(player, true)
	AnalyticsSvc.funnel(player, "first_coins_spent")
	Remotes.fire(player, "Notify", "zoneUnlocked", { zone = zone.id, price = price })
end

-- ---------- the client's copy of its data ----------
local function view(player: Player, d: Data): { [string]: any }
	local pets = {}
	for _, p in d.pets do
		table.insert(pets, { id = p.id, key = p.key, pose = p.pose, mut = p.mut, eq = p.eq, income = earn(p) })
	end
	return {
		coins = math.floor(d.coins),
		income = PenService.incomePerSecond(d),
		upgrades = d.upgrades,
		pets = pets,
		slots = PenService.slots(d),
		found = d.found,
		pages = IndexService.pages(d.found),
		gift = PenService.giftState(d),
		forestUnlocked = d.forestUnlocked,
		welcome = d.welcome,
		settings = d.settings,
		superFreezeCharges = d.superFreezeCharges,
		stats = d.stats,
		plot = WorldService.plotOf(player),
	}
end

function PenService.Init() end

function PenService.Start()
	DataService.Loaded:Connect(function(player: Player, d: any)
		local data = d :: Data
		incomeCarry[player] = 0
		if not WorldService.assignPlot(player) then
			warn(`[PenService] no free pen for {player.UserId}: set the place's Server Size to {#Config.world.plots}`)
		end
		if data.forestUnlocked then
			WorldService.setForestOpen(player, true)
		end
		local w = WorldRules.weekId(os.time())
		if data.week.id ~= w then
			data.week = { id = w, coins = 0 }
		end
		checkWelcome(player, data)
		dirty[player] = true
	end)
	DataService.Changed:Connect(function(player: Player)
		dirty[player] = true
	end)
	Players.PlayerRemoving:Connect(function(player)
		incomeCarry[player] = nil
		sessionBest[player] = nil
		dirty[player] = nil
		bankingNow[player] = nil
	end)
	PlayerTracker.EnteredPen:Connect(bank)
	Remotes.on("CollectWelcome", collectWelcome)
	Remotes.on("EquipPet", equipPet)
	Remotes.on("EquipBest", equipBest)
	local gift = WorldService.giftPrompt
	if gift then
		gift.Triggered:Connect(claimGift)
	end
	local gate = WorldService.gatePrompt
	if gate then
		gate.Triggered:Connect(openGate)
	end
	-- income: the pen's pets earn every second (whole coins; the rest carries over)
	task.spawn(function()
		while true do
			task.wait(Config.income.tickSeconds)
			for player, carry in incomeCarry do
				local d = DataService.get(player)
				if d then
					local total = carry + PenService.incomePerSecond(d) * Config.income.tickSeconds
					local whole = math.floor(total)
					incomeCarry[player] = total - whole
					if whole > 0 then
						DataService.mutate(player, function(x)
							PenService.addCoins(x, whole)
						end)
					end
				end
			end
		end
	end)
	task.spawn(function()
		while true do
			task.wait(Config.sync.seconds)
			for player in dirty do
				dirty[player] = nil
				local d = DataService.get(player)
				if d and player.Parent then
					Remotes.fire(player, "Data", view(player, d))
				end
			end
		end
	end)
end

return PenService
