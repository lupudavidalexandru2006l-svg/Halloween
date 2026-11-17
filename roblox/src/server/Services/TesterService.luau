--!strict
-- TesterService: the Tester panel's server side (Round 4 phase 1). Only Config.isTester accounts
-- (the place owner, n2012haidu, and Player1 in a Studio Start Server test) are answered; anyone
-- else gets no panel and no response. Every action is checked here, on the server.
-- One remote, "Tester", carries (action, a, b). The old "/dev" chat commands run the same actions.

local Players = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local PetDefs = require(ReplicatedStorage.Shared.PetDefs)
local Remotes = require(script.Parent.Remotes)
local DataService = require(script.Parent.DataService)
local PenService = require(script.Parent.PenService)
local EventService = require(script.Parent.EventService)
local WildPetSpawner = require(script.Parent.WildPetSpawner)
local WorldService = require(script.Parent.WorldService)
local PlayerTracker = require(script.Parent.PlayerTracker)
local CritterService = require(script.Parent.CritterService)
local FriendService = require(script.Parent.FriendService)
local CarryService = require(script.Parent.CarryService)
local WorldRules = require(ReplicatedStorage.Shared.WorldRules)

local TesterService = {}
local D = Config.dev

local function finite(v: any): boolean
	return typeof(v) == "number" and v == v and v > -math.huge and v < math.huge
end

local function tierName(v: any): string?
	if typeof(v) ~= "string" then
		return nil
	end
	for _, t in Config.tiers do
		if string.lower(t.name) == string.lower(v) then
			return t.name
		end
	end
	return nil
end

local function change(player: Player, fn: (DataService.Data) -> ())
	if DataService.mutate(player, fn) then
		PenService.markDirty(player)
	end
end

local ACTIONS: { [string]: (Player, any, any) -> () } = {}

-- money multiplier: 0.1 to 10,000x on all coin income, saved with the tester's data
ACTIONS.mult = function(player, n)
	if finite(n) then
		change(player, function(d)
			d.tester.mult = math.clamp(n, D.multMin, D.multMax)
		end)
	end
end

ACTIONS.coinsSet = function(player, n)
	if finite(n) then
		change(player, function(d)
			d.coins = math.clamp(math.floor(n), 0, D.maxCoins)
		end)
	end
end

ACTIONS.coinsAdd = function(player, n)
	if finite(n) and table.find(D.addCoins, n) then
		change(player, function(d)
			PenService.addCoins(d, n)
		end)
	end
end

ACTIONS.teleport = function(player, id)
	if not Remotes.isId(id) then
		return
	end
	for _, t in WorldService.teleportTargets(player) do
		if t.id == id then
			PlayerTracker.teleport(player, t.cf)
			return
		end
	end
end

-- every gate open (the "Coming soon" ones too, so a tester can walk the whole tunnel), or all shut again
ACTIONS.openGates = function(player)
	local n = #Config.world.zones
	change(player, function(d)
		d.reach = n
		d.forestUnlocked = true
	end)
	WorldService.setReach(player, n)
end

ACTIONS.closeGates = function(player)
	change(player, function(d)
		d.reach = 1
		d.forestUnlocked = false
	end)
	WorldService.setReach(player, 1)
end

-- open islands 1..n exactly (the panel's - / + on "Islands open", 2026-11-12)
ACTIONS.reach = function(player, n)
	if not finite(n) then
		return
	end
	local r = math.clamp(math.floor(n), 1, #Config.world.zones)
	change(player, function(d)
		d.reach = r
		d.forestUnlocked = r >= 2
	end)
	WorldService.setReach(player, r)
end

-- Cold Power straight to the next island's need (the next gate opens with it)
ACTIONS.powerNext = function(player)
	change(player, function(d)
		d.coldPower = math.min(Config.coldPower.max, Config.nextNeed(d.coldPower))
	end)
end

-- every pet in a Thaw Machine comes out now (PenService lets them out on its next tick)
ACTIONS.thawNow = function(player)
	change(player, function(d)
		for _, p in d.pets do
			if p.thawM then
				p.thawEnd = os.time()
			end
		end
	end)
end

-- the cubes in your hands melt now (test melting and zapping a pet back)
ACTIONS.meltNow = function(player)
	CarryService.devMeltAll(player)
end

-- the one-time Free Gift can be claimed again
ACTIONS.giftReset = function(player)
	change(player, function(d)
		d.gift.claimed = false
	end)
end

-- today's daily challenges all done (ready to claim)
ACTIONS.dailyDone = function(player)
	change(player, function(d)
		for _, c in d.daily.list do
			for _, def in Config.challenges.pool do
				if def.id == c.id then
					local now = if def.stat == "rares" then d.daily.rares else ((d.stats :: any)[def.stat] or 0)
					c.from = now - c.goal
				end
			end
		end
	end)
end

-- free Thaw Machine skips to test "Skip free" (paid skips are free in Studio until the products exist)
ACTIONS.thawSkips = function(player, n)
	if finite(n) then
		change(player, function(d)
			d.thawSkips = math.clamp(math.floor(n), 0, 999)
		end)
	end
end

-- Cold Power (2026-11-10): set it to any amount, to test gates, freeze speed and the training stations
ACTIONS.power = function(player, n)
	if finite(n) then
		change(player, function(d)
			d.coldPower = math.clamp(n, 0, Config.coldPower.max)
		end)
	end
end

ACTIONS.rebirths = function(player, n)
	if finite(n) then
		change(player, function(d)
			d.rebirths = math.clamp(math.floor(n), 0, D.maxRebirths)
		end)
	end
end

-- own guns 1..n and hold gun n (Round 4 phase 4: re-test buying from any gun)
ACTIONS.gun = function(player, n)
	if finite(n) then
		change(player, function(d)
			d.guns.best = math.clamp(math.floor(n), 1, #Config.guns.list)
			d.guns.equipped = d.guns.best
		end)
	end
end

-- set one upgrade to a level ("all" + "max" maxes every upgrade)
ACTIONS.upgrade = function(player, id, level)
	if id == "all" then
		change(player, function(d)
			for _, uid in Config.upgradeIds do
				d.upgrades[uid] = Config.upgrades[uid].maxLevel
			end
			PenService.fillEmptySlots(d)
		end)
	elseif typeof(id) == "string" and table.find(Config.upgradeIds, id) and finite(level) then
		change(player, function(d)
			d.upgrades[id] = math.clamp(math.floor(level), 1, Config.upgrades[id].maxLevel)
			PenService.fillEmptySlots(d)
		end)
	else
		return
	end
	PlayerTracker.updateSpeed(player)
end

-- the pan's Look and its trainer (Round 4 phase 5; Slots is the "pen" upgrade above; Cold Level is gone)
ACTIONS.pan = function(player, kind, level)
	if kind == "look" and finite(level) then
		change(player, function(d)
			d.pan.look = math.clamp(math.floor(level), 1, #Config.pan.looks)
		end)
	elseif kind == "trainer" and finite(level) then
		change(player, function(d)
			d.pan.trainer = math.clamp(math.floor(level), 1, #Config.training.stations)
		end)
	end
end

-- every pan pet into Storage (income 0, so money tests can see an exact charge); Equip best undoes it
ACTIONS.storeAll = function(player)
	change(player, function(d)
		for _, p in d.pets do
			p.eq = false
		end
	end)
end

ACTIONS.givePet = function(player, key, mut, sz)
	if typeof(key) ~= "string" or not PetDefs.get(key) then
		return
	end
	local m = if typeof(mut) == "string" and Config.mutations[mut] then mut else nil
	local size = if Config.size(sz) then sz else nil -- Big ... Cosmic (Config.sizes)
	change(player, function(d)
		if not PenService.addPet(d, key, "idle", m, nil, size) then
			Remotes.notYet(player, "Storage full", "pets")
		end
	end)
end

-- a pet into your Pets still in its ice cube, ready for the Thaw Machine (QA of thawing, 2026-11-10)
ACTIONS.giveFrozen = function(player, key)
	if typeof(key) ~= "string" or not PetDefs.get(key) then
		return
	end
	change(player, function(d)
		if not PenService.addPet(d, key, "idle", nil, true) then
			Remotes.notYet(player, "Storage full", "pets")
		end
	end)
end

-- fill every free pen slot with pets from the zones
ACTIONS.fillPan = function(player)
	local pool: { PetDefs.PetDef } = {}
	for _, z in Config.world.zones do
		for _, def in PetDefs.inZone(z.id) do
			table.insert(pool, def)
		end
	end
	if #pool == 0 then
		return
	end
	local rng = Random.new()
	change(player, function(d)
		local room = PenService.slots(d) - PenService.equippedCount(d)
		for _ = 1, room do
			if not PenService.addPet(d, pool[rng:NextInteger(1, #pool)].key, "idle", nil) then
				break
			end
		end
	end)
end

-- a wild pet of this tier right next to you, on the island you stand on (Secret included)
ACTIONS.spawnTier = function(player, tier)
	local t = tierName(tier)
	if t then
		WildPetSpawner.devSpawn(player, t)
	end
end

-- one chosen pet, wild, in a chosen zone (0 = right next to you): test any pet in any zone
ACTIONS.spawnPet = function(player, key, zone)
	if typeof(key) ~= "string" or not PetDefs.get(key) then
		return
	end
	if not (finite(zone) and zone == math.floor(zone) and (zone == 0 or Config.zone(zone))) then
		return
	end
	if not WildPetSpawner.devSpawnPet(player, key, zone) then
		Remotes.notYet(player, "No spot for a pet there")
	end
end

ACTIONS.walk = function(player, n)
	if finite(n) then
		change(player, function(d)
			d.tester.walk = if n <= 0 then 0 else math.clamp(n, D.walkMin, D.walkMax)
		end)
		PlayerTracker.updateSpeed(player)
	end
end

ACTIONS.instantFreeze = function(player, on)
	if typeof(on) == "boolean" then
		change(player, function(d)
			d.tester.instantFreeze = on
		end)
	end
end

ACTIONS.noMelt = function(player, on)
	if typeof(on) == "boolean" then
		change(player, function(d)
			d.tester.noMelt = on
		end)
	end
end

ACTIONS.chill = function()
	EventService.startNow()
end

-- jump the whole server to nightfall, or to morning if it's night
ACTIONS.night = function()
	EventService.toggleNight()
end

-- Round 5: Heat Critters on the island you stand on (islands 3+ aren't built yet); press again for off
ACTIONS.critters = function(player)
	local pos = PlayerTracker.position(player)
	local zone = if pos then WorldRules.zoneAt(pos) else 0
	if zone > 0 then
		CritterService.force(zone, not CritterService.forced(zone))
	end
end

-- Round 5: drop the new-player shield now (to test ray-tag)
ACTIONS.shieldOff = function(player)
	player:SetAttribute("ShieldUntil", 0)
end

-- Round 5: own Slow Gel or not
ACTIONS.gel = function(player)
	change(player, function(d)
		d.gear.gel = not d.gear.gel
	end)
end

-- pretend this many Roblox friends are in the server (the friend bonus; Studio has no real friends)
ACTIONS.friends = function(player, n)
	if finite(n) then
		FriendService.setTest(player, math.floor(n))
	end
end

-- Round 5: set how many pets you've caught (Codes unlock at Config.codes.needPets)
ACTIONS.caught = function(player, n)
	if finite(n) then
		change(player, function(d)
			d.stats.frozen = math.clamp(math.floor(n), 0, 1e9)
		end)
	end
end

ACTIONS.heat = function(_player, n)
	local forest = Config.zone(2)
	if forest and finite(n) then
		forest.heat = math.clamp(n, 0, D.heatMax)
	end
end

ACTIONS.away = function(player, n)
	if finite(n) then
		PenService.devAway(player, math.clamp(n, 0, D.awayMax))
	end
end

-- wipe my save: the panel asks first and sends "confirm"; DataService refuses outside the QA store
ACTIONS.wipe = function(player, confirm)
	if confirm == "confirm" then
		DataService.wipe(player)
	end
end

-- the server's view of you, for the panel's readout
ACTIONS.readout = function(player)
	local d = DataService.get(player)
	if not d then
		return
	end
	local key, qa = DataService.saveKey(player)
	local targets = {}
	for _, t in WorldService.teleportTargets(player) do
		table.insert(targets, { id = t.id, label = t.label })
	end
	Remotes.fire(player, "Notify", "testerReadout", {
		coins = math.floor(d.coins), mult = d.tester.mult, rebirths = d.rebirths, power = d.coldPower,
		income = PenService.incomePerSecond(d), saveKey = key, qa = qa, targets = targets,
		reach = d.reach, gun = d.guns.best, trainer = d.pan.trainer, slots = d.upgrades.pen, look = d.pan.look,
		pets = #d.pets, frozen = d.stats.frozen, skips = d.thawSkips,
	})
end

function TesterService.run(player: Player, action: any, a: any, b: any)
	if not Config.isTester(player.UserId) or not DataService.isLoaded(player) then
		return -- not a tester: no answer at all
	end
	local fn = if typeof(action) == "string" then ACTIONS[action] else nil
	if fn then
		fn(player, a, b)
	end
end

-- the old chat commands, same checks: "/dev coins 5000", "/dev epic", "/dev chill", "/dev heat 2",
-- "/dev ray 10", "/dev away 3600", "/dev wipe"
local function chat(player: Player, text: string)
	local words = string.split(string.lower(text), " ")
	local cmd, n = words[2], tonumber(words[3])
	if cmd == "coins" then
		TesterService.run(player, "coinsSet", n, nil)
	elseif cmd and tierName(cmd) then
		TesterService.run(player, "spawnTier", cmd, nil)
	elseif cmd == "ray" then
		TesterService.run(player, "upgrade", "ray", n)
	elseif cmd == "wipe" then
		TesterService.run(player, "wipe", "confirm", nil)
	elseif cmd then
		TesterService.run(player, cmd, n, nil)
	end
end

function TesterService.Init() end

function TesterService.Start()
	Remotes.on("Tester", TesterService.run)
	local command = Instance.new("TextChatCommand")
	command.Name = "DevCommand"
	command.PrimaryAlias = "/dev"
	command.Triggered:Connect(function(source: TextSource, text: string)
		local player = Players:GetPlayerByUserId(source.UserId)
		if player then
			chat(player, text)
		end
	end)
	command.Parent = TextChatService
	-- Studio only: automated play-tests run outside this server's module cache, so they can't call the
	-- services. This hook runs the same tester actions for a player and gives a short look at their save.
	if RunService:IsStudio() then
		local hook = Instance.new("BindableFunction")
		hook.Name = "TesterHook"
		hook.OnInvoke = function(userId: any, action: any, a: any, b: any): any
			local player = if typeof(userId) == "number" then Players:GetPlayerByUserId(userId) else nil
			local d = player and DataService.get(player)
			if not player or not d then
				return nil
			end
			if action == "data" then
				return {
					coins = d.coins, coldPower = d.coldPower, reach = d.reach, rebirths = d.rebirths,
					gunBest = d.guns.best, gunEquipped = d.guns.equipped, panLook = d.pan.look, slots = d.upgrades.pen,
					pets = #d.pets, frozen = d.stats.frozen, banked = d.stats.banked,
					tutorialStep = d.tutorial.step, tutorialDone = d.tutorial.done, noMelt = d.tester.noMelt,
				}
			elseif action == "carry" and typeof(a) == "string" then
				-- a fresh cube of this pet straight into your hands, as if just picked up (melt tests, 2026-11-17)
				local def = PetDefs.get(a)
				return def and CarryService.addCube(player, { key = a, zone = def.zone, pose = "idle" })
			elseif action == "tutorialDid" and typeof(a) == "string" then
				require(script.Parent.TutorialService).did(player, a) -- drive a tutorial step from a play test
				return true
			elseif action == "secretNow" then
				-- the half-hour Secret wave, now (2026-11-16 QA)
				local names = require(script.Parent.WildPetSpawner).spawnSecrets()
				Remotes.fireAll("Notify", "secretSpawned", { islands = names, count = #names })
				return names
			elseif action == "eventNext" then
				-- jump the event clock to the start of the next server event (2026-11-16 QA)
				local off = (workspace:GetAttribute("EventOffset") or 0) :: number
				local _, _, nextE, nextIn = require(game.ReplicatedStorage.Shared.WorldRules).eventAt(workspace:GetServerTimeNow())
				workspace:SetAttribute("EventOffset", off + nextIn + 0.5)
				return nextE.id
			end
			TesterService.run(player, action, a, b)
			return true
		end
		hook.Parent = ServerStorage
	end
end

return TesterService
