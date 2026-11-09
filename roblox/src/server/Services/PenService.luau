--!strict
-- PenService: owns coins, income, banking, the pen and Storage, equip / Equip best, the coin gates,
-- the welcome back (25% while away, capped at 8 h, shows lastBest) and the daily gift (opens after
-- the first bank). It also sends each client its own copy of its data ("Data", throttled).
-- Every grant and its claim stamp are written in the same UpdateAsync (DataService.saveNow).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Theme = require(ReplicatedStorage.Shared.Theme)
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
local bouncedAt: { [Player]: number } = {} -- when a too-hot cube last bounced off this player's pan
local penShown: { [Player]: { key: string, parts: { [string]: Part } } } = {}
-- The Thaw Machine (owner 2026-11-09): banked pets go into your Pets still frozen (PetEntry.frozen, not
-- earning). You put one in a machine at your pan (remote "ThawPet"); its time (Config.thawSeconds) is
-- saved as os.time, so it keeps thawing while you're away, then it wanders the pan.
-- the save's data table -> owns the 2x Coins game pass. Not saved: Roblox owns the pass, and
-- MonetizationService asks it on every join (and after a purchase)
local doubled: { [any]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local DOUBLE = Config.robuxItem("doubleCoins")

-- the pan's pets sit frozen in ice cubes, in a neat grid from the door to the back, seen by everyone.
-- Each cube is a see-through ice Part with PetKey; clients draw the pet inside it with a little wiggle,
-- the frost shimmer and the rising coins (PetVisuals). Rebuilt only when the set of pets changes; a pet
-- keeps its grid spot (the order of the pan's list).
local function gridSpot(plot: number, n: number): Vector3
	local G, P = Config.panCubes, Config.world.pans
	local spot = Config.world.plots[plot]
	local col, row = (n - 1) % G.cols, (n - 1) // G.cols
	local x = spot.x + (col - (G.cols - 1) / 2) * G.gap
	local z = P.frontZ - G.frontMargin - row * G.gap
	return Vector3.new(x, P.soilHeight + 0.2, z)
end

-- where Thaw Machine m stands in a pan (also used by MapArt to build it)
function PenService.machineSpot(plot: number, m: number): Vector3
	local T, P = Config.thaw, Config.world.pans
	local spot = Config.world.plots[plot]
	return Vector3.new(spot.x + T.machine.x + (m - 1) * T.machine.gap, P.soilHeight + T.machine.padTop, P.frontZ - P.length + T.machine.z) -- on its heat pad
end

local function machines(d: Data): number
	return if d.upgrades.pen >= Config.thaw.secondAt then 2 else 1
end
PenService.machines = machines

-- the pet thawing in machine m, if any
local function inMachine(d: Data, m: number): PetEntry?
	for _, p in d.pets do
		if p.thawM == m then
			return p
		end
	end
	return nil
end

local function drawPen(player: Player, d: Data)
	local plot = WorldService.plotOf(player)
	if not plot then
		return
	end
	-- the pets thawing in a machine, then the pan's pets (frozen ones in your Pets aren't in the world)
	local show: { PetEntry } = {}
	for _, p in d.pets do
		if p.thawM then
			table.insert(show, p)
		end
	end
	for _, p in d.pets do
		if p.eq and not p.frozen and #show < Config.pen.displayMax then
			table.insert(show, p)
		end
	end
	local ids = {}
	for _, p in show do
		table.insert(ids, p.id .. (if p.thawM then `m{p.thawM}@{p.thawEnd}` else ""))
	end
	local key = table.concat(ids, ",") .. "|" .. machines(d)
	local map = workspace:FindFirstChild("Map")
	local plotPart = map and map:FindFirstChild("Plot" .. plot)
	if plotPart then
		plotPart:SetAttribute("Machines", machines(d)) -- clients show the second machine from this
	end
	local state = penShown[player] or { key = "", parts = {} }
	penShown[player] = state
	if state.key == key then
		return
	end
	state.key = key
	local keep: { [string]: boolean } = {}
	local folder = WorldService.petsFolder("PenPets")
	local outN = 0
	for _, p in show do
		local st: string?, k = if p.thawM then "machine" else nil, p.thawM or 0
		keep[p.id] = true
		local def = PetDefs.get(p.key)
		local s = if def then math.min(PetDefs.cubeSize[def.size], Config.panCubes.maxSize) else 0
		local at
		if st == "machine" then
			at = PenService.machineSpot(plot, k)
		else
			outN += 1
			at = gridSpot(plot, outN) -- its home spot; each client walks it round the pan
		end
		local cube = state.parts[p.id]
		if def and not cube then
			cube = Instance.new("Part")
			cube.Name = "PenPet"
			cube.Size = Vector3.one * s
			cube.Anchored = true
			cube.CanCollide = false
			cube.CanQuery = false
			cube.CanTouch = false
			-- not Glass: Roblox draws nothing see-through behind Glass, so a sprite pet in its cube (or
			-- strolling inside the hidden one once thawed) vanished (World Rules)
			cube.Material = Enum.Material.SmoothPlastic
			cube.Color = Theme.ice
			cube.Transparency = 0.5
			cube.CastShadow = false
			cube:SetAttribute("PetKey", p.key)
			cube:SetAttribute("PetId", p.id) -- the owner's client finds this pet's income for its coin pops
			cube:SetAttribute("PenOwner", player.UserId)
			cube:SetAttribute("Mut", p.mut)
			cube:SetAttribute("Action", if p.pose == "sleep" then "sleep" else nil) -- frozen asleep, it naps in your pen
			cube:SetAttribute("Banked", true)
			cube.Parent = folder
			state.parts[p.id] = cube
		end
		if cube then
			cube.CFrame = CFrame.new(at + Vector3.new(0, s / 2, 0)) * CFrame.Angles(0, math.pi, 0) -- facing the door (+Z): the pet inside shows its face, not its back
			cube:SetAttribute("Plot", plot)
			cube:SetAttribute("Thaw", st or "out")
			cube:SetAttribute("Machine", if st == "machine" then k else nil) -- which Thaw Machine it sits in (ThawMachines lights that one up)
			local ends = if st == "machine" then p.thawEnd else nil
			cube:SetAttribute("ThawEnd", if ends then workspace:GetServerTimeNow() + (ends - os.time()) else nil)
			cube:SetAttribute("ThawTotal", if ends then p.thawTotal else nil)
		end
	end
	for id, part in state.parts do
		if not keep[id] then
			part:Destroy()
			state.parts[id] = nil
		end
	end
end

local function clearPen(player: Player)
	local state = penShown[player]
	if state then
		for _, part in state.parts do
			part:Destroy()
		end
		penShown[player] = nil
	end
end

local function earn(p: PetEntry): number
	local def = PetDefs.get(p.key)
	return if def then PetDefs.income(def, p.pose, p.mut) else 0
end

function PenService.slots(d: Data): number
	return Config.panSlots(d.upgrades.pen, d.rebirths)
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

-- only the pen's pets earn; each full Index page adds 10%, each rebirth 50%; a tester's money multiplier on top
-- (DataService resets it to 1 for everyone who isn't a tester)
function PenService.incomePerSecond(d: Data): number
	local sum = 0
	for _, p in d.pets do
		if p.eq and not p.frozen then -- a pet still in its cube earns nothing until the Thaw Machine lets it out
			sum += earn(p)
		end
	end
	return sum * PenService.incomeMult(d)
end

-- what every pet's own income is multiplied by: Index pages, rebirths (+50% each, Round 4 phase 7),
-- a tester's money multiplier and the 2x Coins game pass
function PenService.incomeMult(d: Data): number
	local pass = if doubled[d] and DOUBLE then DOUBLE.mult or 2 else 1
	return IndexService.multiplier(d.indexClaimed) * Config.rebirthIncome(d.rebirths) * d.tester.mult * pass
end

-- MonetizationService: this player owns the 2x Coins pass
function PenService.setDoubleCoins(player: Player, on: boolean)
	local d = DataService.get(player)
	if d then
		doubled[d] = if on then true else nil
		dirty[player] = true
	end
end

function PenService.hasDoubleCoins(player: Player): boolean
	local d = DataService.get(player)
	return d ~= nil and doubled[d] == true
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
	local out = {}
	for _, p in d.pets do
		if not p.frozen then -- a frozen pet can't go in the pen until it's thawed
			table.insert(out, p)
		end
	end
	for i, p in byEarnings(out) do
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
		if not p.eq and not p.frozen then
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

-- fewer slots than pets in the pan (a rebirth resets Slots): the best earners stay, the rest go to
-- Storage (kept forever, nothing lost)
function PenService.fitSlots(d: Data)
	local slots = PenService.slots(d)
	if PenService.equippedCount(d) <= slots then
		return
	end
	local inPan = {}
	for _, p in d.pets do
		if p.eq then
			table.insert(inPan, p)
		end
	end
	for i, p in byEarnings(inPan) do
		p.eq = i <= slots
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

-- tester tool: a pet straight into the pen (or Storage when the pen is full); false when Storage is full.
-- frozen = into your Pets still in its cube, for the Thaw Machine (a pet kept when leaving mid-show)
function PenService.addPet(d: Data, key: string, pose: string, mut: string?, frozen: boolean?): boolean
	if not PetDefs.get(key) or #d.pets >= Config.pen.storageMax then
		return false
	end
	local eq = not frozen and PenService.equippedCount(d) < PenService.slots(d)
	table.insert(d.pets, { id = "q" .. d.nextPetId, key = key, pose = pose, mut = mut, at = os.time(), eq = eq, frozen = if frozen then true else nil })
	d.nextPetId += 1
	d.found[key] = true
	return true
end

-- the Sell Booth (SellService): take these pets out of the pan / Storage and give back what was taken.
-- Runs inside the caller's DataService.mutate, so the removal and the payment land together; an id
-- that's already gone (a second press, spam) is simply not there any more.
function PenService.removePets(d: Data, ids: { [string]: boolean }): { PetEntry }
	local kept, taken = {}, {}
	for _, p in d.pets do
		if ids[p.id] then
			table.insert(taken, p)
		else
			table.insert(kept, p)
		end
	end
	if #taken > 0 then
		d.pets = kept
		PenService.fillEmptySlots(d) -- a sold pan pet's slot takes the best one from Storage
	end
	return taken
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
	if os.clock() - (bouncedAt[player] or -math.huge) < Config.pan.bounce.again then
		return -- it just bounced: one bounce, not one every tick while you stand in the pan
	end
	if #d.pets >= Config.pen.storageMax then
		Remotes.notYet(player, "Storage full", "pets") -- the cubes stay on your back
		return
	end
	bankingNow[player] = true
	local cubes = CarryService.takeAll(player)
	local banked = {}
	local handBack = {}
	local need = 0 -- the Cold Level a too-hot cube needs (Round 4 phase 5)
	for _, c in cubes do
		local def = PetDefs.get(c.key)
		if not def then
			continue
		end
		if def.zone > d.pan.cold then
			-- from an island hotter than this pan's Cold Level: it can't stay frozen here, it bounces back
			table.insert(handBack, c)
			need = math.max(need, def.zone)
			continue
		end
		if #d.pets >= Config.pen.storageMax then
			table.insert(handBack, c)
			continue
		end
		local rank = Config.tier(def.tier).rank
		local firstTime = not d.found[c.key]
		DataService.mutate(player, function(x)
			local id = "q" .. x.nextPetId
			-- into your Pets, still frozen: you put it in a Thaw Machine yourself (owner 2026-11-09)
			table.insert(x.pets, { id = id, key = c.key, pose = c.pose, mut = c.mut, at = os.time(), eq = false, frozen = true })
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
			IndexService.onFound(player, c.key, d.found, d.indexClaimed)
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
		table.insert(banked, { key = c.key, pose = c.pose, mut = c.mut, income = PetDefs.income(def, c.pose, c.mut), firstTime = firstTime, frozen = true,
			thawSeconds = Config.thawSeconds(def.tier, def.size, def.zone, c.mut, d.upgrades.pen) })
	end
	for _, c in handBack do
		-- nothing is lost: cubes that don't fit go back on your back (paid ones back into the save)
		CarryService.addCube(player, { key = c.key, zone = c.zone, pose = c.pose, mut = c.mut, superFrozen = c.superFrozen, superUsed = c.superUsed, offered = c.offered })
	end
	if need > 0 then
		bouncedAt[player] = os.clock()
		Remotes.notYet(player, `Your pan needs Cold Level {need}`, "pan")
		Remotes.fire(player, "Notify", "panBounce", { need = need, cold = d.pan.cold, plot = WorldService.plotOf(player) })
	elseif #handBack > 0 then
		Remotes.notYet(player, "Storage full", "pets")
	end
	if #banked > 0 then
		-- the feedback first: the save can take seconds on a slow DataStore, and the pets are already
		-- in the data (a leave saves them too), so the player shouldn't wait for it (QA 2026-11-05, CA-04)
		Remotes.fire(player, "Notify", "banked", { banked = banked, income = PenService.incomePerSecond(d) })
		DataService.saveNow(player)
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
	if on and entry.frozen then
		Remotes.notYet(player, "Thaw it in your Thaw Machine first", "pets")
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

-- ---------- the Thaw Machine (owner 2026-11-09) ----------
-- "put this frozen pet in machine m": your own pan, standing at that machine, the machine free
local function thawPet(player: Player, id: any, m: any)
	local d = DataService.get(player)
	if not d or not Remotes.isId(id, 12) or typeof(m) ~= "number" or m ~= math.floor(m) or m < 1 or m > machines(d) then
		return
	end
	local plot = WorldService.plotOf(player)
	local pos = PlayerTracker.position(player)
	if not plot or not pos then
		return
	end
	local at = PenService.machineSpot(plot, m)
	if (Vector3.new(pos.X, 0, pos.Z) - Vector3.new(at.X, 0, at.Z)).Magnitude > Config.thaw.useRange then
		Remotes.notYet(player, "Walk to your Thaw Machine", "pets")
		return
	end
	if inMachine(d, m) then
		Remotes.notYet(player, "This machine is busy", "pets")
		return
	end
	local started: PetEntry? = nil
	DataService.mutate(player, function(x)
		if inMachine(x, m) then
			return
		end
		for _, p in x.pets do
			if p.id == id and p.frozen and not p.thawM then
				local def = PetDefs.get(p.key)
				if def then
					local secs = Config.thawSeconds(def.tier, def.size, def.zone, p.mut, x.upgrades.pen)
					p.thawM, p.thawEnd, p.thawTotal = m, os.time() + secs, secs
					started = p
				end
				break
			end
		end
	end)
	local p = started
	if not p then
		return
	end
	DataService.saveNow(player) -- the timer is saved, so leaving never loses it
	Remotes.fire(player, "Notify", "thawStarted", { key = p.key, seconds = p.thawTotal, machine = m })
end

-- a pet whose time is up hops out: into the pen when there's a free slot, else Storage
local function releaseThawed(player: Player, d: Data)
	local now = os.time()
	local out: { { p: PetEntry, m: number } } = {}
	for _, p in d.pets do
		if p.thawM and (p.thawEnd or 0) <= now then
			table.insert(out, { p = p, m = p.thawM :: number })
		end
	end
	if #out == 0 then
		return
	end
	DataService.mutate(player, function(x)
		for _, o in out do
			local p = o.p
			p.frozen, p.thawM, p.thawEnd, p.thawTotal = nil, nil, nil, nil
			p.eq = PenService.equippedCount(x) < PenService.slots(x)
		end
	end)
	for _, o in out do
		Remotes.fire(player, "Notify", "thawed", { key = o.p.key, income = earn(o.p), plot = WorldService.plotOf(player), machine = o.m, stored = not o.p.eq })
	end
end

-- each pan's Thaw Machine gets an E prompt (made here, so the saved map never needs a rebuild);
-- the client opens the "Put a pet in" popup from it (PromptController) and shows it only at your own pan
local function machinePrompts()
	local map = workspace:FindFirstChild("Map")
	if not map then
		return
	end
	for i in Config.world.plots do
		local pan = map:FindFirstChild("Pan" .. i, true)
		for m = 1, 2 do
			local model = pan and pan:FindFirstChild("ThawMachine" .. m)
			if not model or model:FindFirstChild("ThawPrompt", true) then
				continue
			end
			local core = model:FindFirstChild("CoilCore", true) or model:FindFirstChildWhichIsA("BasePart", true)
			if not core or not core:IsA("BasePart") then
				continue
			end
			local a = Instance.new("Attachment")
			a.Name = "ThawPromptSpot"
			a.Parent = core
			-- in world space at the machine's middle: the coil is a cylinder turned on its side, so a local
			-- "up" offset put the prompt 3 studs to the left of the machine (owner 2026-11-09)
			a.WorldPosition = model:GetBoundingBox().Position
			local pp = Instance.new("ProximityPrompt")
			pp.Name = "ThawPrompt"
			pp.ActionText = "Thaw a pet"
			pp.ObjectText = "Thaw Machine"
			pp.HoldDuration = 0
			pp.KeyboardKeyCode = Enum.KeyCode.E
			pp.MaxActivationDistance = Config.thaw.useRange - 2
			pp.RequiresLineOfSight = false
			pp.Style = Enum.ProximityPromptStyle.Custom -- drawn by PromptController
			pp:SetAttribute("Booth", "thaw")
			pp:SetAttribute("Plot", i)
			pp:SetAttribute("Machine", m)
			pp.Parent = a
		end
	end
end

-- ---------- zone gates (owner 2026-10-30: pay coins at the gate) ----------
-- Round 4 phase 6: every island after the first has a gate, opened in order (reach = the last one open).
-- A gate costs its coins and, on the odd islands from 3, a number of rebirths (Config.world.rebirthGates).
-- An island whose pets aren't ready stays shut ("coming soon"). Checked again inside the one data change.
local gateCooldown: { [Player]: number } = {}
local function openGate(player: Player, id: number)
	local d = DataService.get(player)
	local zone = Config.zone(id)
	if not d or not zone or id ~= d.reach + 1 or not nearPart(player, WorldService.gatePrompts[id], 4) then
		return
	end
	local now = os.clock()
	if now < (gateCooldown[player] or 0) then
		return
	end
	gateCooldown[player] = now + Config.gateCooldown
	if not zone.ready then
		Remotes.fire(player, "Notify", "comingSoon", { label = zone.name })
		return
	end
	if d.rebirths < zone.gateRebirth then
		Remotes.notYet(player, `Needs Rebirth {zone.gateRebirth}`, "gate")
		return
	end
	local price = zone.gateCoins
	if d.coins < price then
		Remotes.notYet(player, `Need {Config.coinText(price - d.coins)} more coins`, "gate")
		return
	end
	local opened = false
	DataService.mutate(player, function(x)
		if x.reach + 1 == id and x.coins >= price and x.rebirths >= zone.gateRebirth then
			x.coins -= price
			x.reach = id
			x.forestUnlocked = x.reach >= 2
			opened = true
		end
	end)
	if not opened then
		return
	end
	DataService.saveNow(player) -- paid and opened in the same save
	WorldService.setReach(player, id)
	AnalyticsSvc.funnel(player, "first_coins_spent")
	Remotes.fire(player, "Notify", "zoneUnlocked", { zone = zone.id, price = price })
end

-- ---------- the client's copy of its data ----------
local function view(player: Player, d: Data): { [string]: any }
	local pets = {}
	local now, serverNow = os.time(), workspace:GetServerTimeNow()
	for _, p in d.pets do
		table.insert(pets, { id = p.id, key = p.key, pose = p.pose, mut = p.mut, eq = p.eq, income = earn(p),
			frozen = p.frozen == true, thawM = p.thawM, -- thawAt: when it comes out, on the clients' server clock
			thawAt = if p.thawEnd then serverNow + (p.thawEnd - now) else nil })
	end
	return {
		coins = math.floor(d.coins),
		income = PenService.incomePerSecond(d),
		incomeMult = PenService.incomeMult(d), -- each pet's coin pop shows its own income times this
		upgrades = d.upgrades,
		pets = pets,
		slots = PenService.slots(d),
		machines = machines(d), -- Thaw Machines in the pan (1, or 2 from Slots level Config.thaw.secondAt)
		found = d.found,
		pages = IndexService.pages(d.found, d.indexClaimed),
		gift = PenService.giftState(d),
		forestUnlocked = d.forestUnlocked,
		reach = d.reach,
		welcome = d.welcome,
		settings = d.settings,
		superFreezeCharges = d.superFreezeCharges,
		doubleCoins = doubled[d] == true,
		stats = d.stats,
		plot = WorldService.plotOf(player),
		rebirths = d.rebirths,
		seenShows = d.seenShows,
		pan = d.pan, -- Cold Level and Look (Slots = slots / upgrades.pen)
		tester = if Config.isTester(player.UserId) then d.tester else nil, -- only testers learn the panel exists
	}
end

-- tester tool: send the client its data on the next sync
function PenService.markDirty(player: Player)
	dirty[player] = true
end

function PenService.Init() end

function PenService.Start()
	WorldService.petsFolder("PenPets") -- made now so clients find it even before anyone banks
	DataService.Loaded:Connect(function(player: Player, d: any)
		local data = d :: Data
		incomeCarry[player] = 0
		if not WorldService.assignPlot(player) then
			warn(`[PenService] no free pen for {player.UserId}: set the place's Server Size to {#Config.world.plots}`)
		end
		WorldService.setReach(player, data.reach)
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
		incomeCarry[player] = nil -- a pet in a Thaw Machine keeps its saved time (thawEnd) and comes out on a later join
		sessionBest[player] = nil
		dirty[player] = nil
		bankingNow[player] = nil
		bouncedAt[player] = nil
		gateCooldown[player] = nil
		clearPen(player)
	end)
	PlayerTracker.EnteredPen:Connect(bank)
	Remotes.on("CollectWelcome", collectWelcome)
	Remotes.on("EquipPet", equipPet)
	Remotes.on("EquipBest", equipBest)
	Remotes.on("ThawPet", thawPet)
	local gift = WorldService.giftPrompt
	if gift then
		gift.Triggered:Connect(claimGift)
	end
	for id, gate in WorldService.gatePrompts do
		gate.Triggered:Connect(function(player: Player)
			openGate(player, id)
		end)
	end
	-- the Thaw Machines: a pet whose saved time is up hops out (also the ones that finished while you were away)
	task.spawn(function()
		while true do
			task.wait(Config.thaw.tickSeconds)
			for _, player in Players:GetPlayers() do
				local d = DataService.get(player)
				if d then
					local ok, err = pcall(releaseThawed, player, d)
					if not ok then
						warn("[PenService] thaw release:", err)
					end
				end
			end
		end
	end)
	task.spawn(function()
		while true do
			pcall(machinePrompts) -- the map can be rebuilt or stream in late
			task.wait(5)
		end
	end)
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
					drawPen(player, d)
				end
			end
		end
	end)
end

return PenService
