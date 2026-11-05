--!strict
-- TesterService: the Tester panel's server side (Round 4 phase 1). Only Config.isTester accounts
-- (the place owner, n2012haidu, and Player1 in a Studio Start Server test) are answered; anyone
-- else gets no panel and no response. Every action is checked here, on the server.
-- One remote, "Tester", carries (action, a, b). The old "/dev" chat commands run the same actions.

local Players = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")
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

-- the pan's Cold Level or Look (Round 4 phase 5; Slots is the "pen" upgrade above)
ACTIONS.pan = function(player, kind, level)
	if (kind == "cold" or kind == "look") and finite(level) then
		change(player, function(d)
			if kind == "cold" then
				d.pan.cold = math.clamp(math.floor(level), Config.pan.cold.start, Config.pan.cold.max)
			else
				d.pan.look = math.clamp(math.floor(level), 1, #Config.pan.looks)
			end
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

ACTIONS.givePet = function(player, key, mut)
	if typeof(key) ~= "string" or not PetDefs.get(key) then
		return
	end
	local m = if typeof(mut) == "string" and Config.mutations[mut] then mut else nil
	change(player, function(d)
		if not PenService.addPet(d, key, "idle", m) then
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
		coins = math.floor(d.coins), mult = d.tester.mult, rebirths = d.rebirths,
		income = PenService.incomePerSecond(d), saveKey = key, qa = qa, targets = targets,
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
end

return TesterService
