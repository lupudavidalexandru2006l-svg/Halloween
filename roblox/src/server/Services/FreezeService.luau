--!strict
-- FreezeService: decides every freeze. Round 5 (owner 2026-11-02): the ray is SHOT, not a prompt hold.
-- A client says what it aims at (remote "Aim": a pet, a Heat Critter or a player, or "none"); this
-- service keeps one freeze meter per target on the server and, every Config.aim.tickSeconds, raises
-- the meter of each target someone aims at (1 / the freeze's seconds: the pet's tier and size against
-- the gun's power, Config.show.freeze x Config.aim.timeScale) and lets every other meter melt back.
-- Checked each tick on the server: the ray is in your hands (GearService), the target is in your gun's
-- range from the server's own character position, you can freeze it (gun's Cold, backpack space).
-- A pet's meter is published on its root ("Meter", "AimedBy", "FreezeStyle") so every client draws the
-- ice creeping up and the beam; WildPetSpawner makes it run away while scared and stop once stuck.
-- At 1 the cube shuts: decided and stored first, then the client plays the snap or the show
-- (Legendary, Mythic, Secret; leaving mid-show puts the pet in your pan; a Secret shouts server-wide).
-- Heat Critters (CritterService) and players (TagService) register their own meters with
-- FreezeService.registerTarget; this service only checks the aim and the range for them.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local PetDefs = require(ReplicatedStorage.Shared.PetDefs)
local Remotes = require(script.Parent.Remotes)
local DataService = require(script.Parent.DataService)
local AnalyticsSvc = require(script.Parent.AnalyticsSvc)
local PlayerTracker = require(script.Parent.PlayerTracker)
local WildPetSpawner = require(script.Parent.WildPetSpawner)
local CarryService = require(script.Parent.CarryService)
local EventService = require(script.Parent.EventService)
local PenService = require(script.Parent.PenService)
local GunService = require(script.Parent.GunService)
local GearService = require(script.Parent.GearService)

local FreezeService = {}
local F = Config.show.freeze
local A = Config.aim
-- froze = this shot has shut at least one cube; the ray goes away once every beam of it is done
type Aim = { kind: string, id: string, extras: { string }, froze: boolean? }
local aims: { [Player]: Aim } = {} -- what each player shoots at right now
type Shown = { show: string, key: string, pose: string, mut: string? }
local shows: { [Player]: { [string]: Shown } } = {} -- cube uid -> the show still playing for it

-- other kinds of target (Heat Critters, players): where it is, can this player freeze it, and one tick of aiming
export type Target = {
	pos: (id: string) -> Vector3?,
	canAim: (player: Player, id: string) -> boolean,
	tick: (player: Player, id: string, dt: number, gun: number) -> (),
}
local targets: { [string]: Target } = {}

function FreezeService.registerTarget(kind: string, t: Target)
	targets[kind] = t
end

-- the gun a player freezes with: the one they hold (GunService, Round 4 phase 4); everything else
-- reads the tier from here (it also becomes the GunTier attribute every client draws the gun from)
function FreezeService.gunTier(player: Player): number
	return GunService.equipped(player)
end

-- within the gun's range of the server's own character position (never the client's)
local function inRange(player: Player, pos: Vector3, extra: number): boolean
	local p = PlayerTracker.position(player)
	local range = Config.gun(FreezeService.gunTier(player)).range
	return p ~= nil and (Vector3.new(p.X, 0, p.Z) - Vector3.new(pos.X, 0, pos.Z)).Magnitude <= range + extra
end
FreezeService.inRange = inRange

local function touchFor(gun: number): string?
	local best: string? = nil
	for _, t in F.touches do
		if gun >= t.fromGun then
			best = t.touch
		end
	end
	return best
end

-- how long this freeze takes with the ray on it the whole time, and how it looks: flash (quick snap),
-- normal, or layered (slow, cracks). A dazed pet zaps back quickly; a sleeping one freezes faster.
function FreezeService.plan(def: PetDefs.PetDef, gun: number, dazed: boolean, asleep: boolean?): (number, string)
	if dazed then
		return A.refreezeSeconds, "flash"
	end
	local base = math.max(F.minSeconds, (F.tierSeconds[def.tier] or 1) * (F.sizeFactor[def.size] or 1) / Config.gun(gun).power)
	local look = FreezeService.styleFor(base)
	local seconds = base * A.timeScale * (if asleep then Config.night.sleepFreezeFactor else 1)
	return seconds, look
end

function FreezeService.styleFor(seconds: number): string
	return if seconds <= F.flashBelow then "flash" elseif seconds >= F.layeredFrom then "layered" else "normal"
end

local function showSeconds(show: string): number
	local total = F.graceExtra
	for _, b in (Config.show :: any)[show].beats do
		total += b.time
	end
	return total
end

-- everything that must be true to freeze this pet now; says "Backpack full", or gives a pet too warm
-- for your gun a gentle shake, when that's the reason (loud = only when the aim starts, never every tick)
local function canFreeze(player: Player, pet: any, data: any, loud: boolean?): boolean
	if pet.owner and pet.owner ~= player then
		return false -- someone else's personal rare (their client draws it, yours doesn't)
	end
	if pet.state == "dazed" and pet.dazedOwner and pet.dazedOwner ~= player then
		return false -- only the player who carried it can zap a dazed pet back (nobody takes it from them)
	end
	if pet.zone > Config.gun(FreezeService.gunTier(player)).cold then
		if loud then -- a little shake at the pet and two words, no freeze
			Remotes.fire(player, "Notify", "tooWarm", { id = pet.id })
			Remotes.notYet(player, "Needs a colder gun", "pet")
		end
		return false
	end
	if CarryService.load(player) >= CarryService.capacity(player) then
		if loud then
			Remotes.notYet(player, "Backpack full", "pet")
		end
		return false
	end
	if pet.zone > data.reach then
		return false -- can't happen through the gate, but never trust a position
	end
	return true
end

-- the extra pets a many-beam gun freezes at the same time: the nearest ones in reach that this gun
-- can freeze, while the backpack has room. A pet with a show (Legendary and up) is only ever the one
-- you aim at, so two shows never start at once.
local function pickExtras(player: Player, main: any, data: any, gun: number): { string }
	local extras: { string } = {}
	local want = math.min(Config.gun(gun).beams - 1, CarryService.capacity(player) - CarryService.load(player) - 1)
	local p = PlayerTracker.position(player)
	if want <= 0 or not p then
		return extras
	end
	local found: { { id: string, d: number } } = {}
	for id, pet in WildPetSpawner.all() do
		if pet ~= main and pet.state == "wild" and not F.shows[pet.def.tier] and inRange(player, pet.root.Position, 0) and canFreeze(player, pet, data) then
			table.insert(found, { id = id, d = (pet.root.Position - p).Magnitude })
		end
	end
	table.sort(found, function(a, b)
		return a.d < b.d
	end)
	for i = 1, math.min(want, #found) do
		table.insert(extras, found[i].id)
	end
	return extras
end

-- one pet's cube shuts: decided and stored here first, then this player's client plays it
local function freezeOne(player: Player, pet: any)
	local id = pet.id
	local dazed = pet.state == "dazed"
	local pose = if dazed then pet.pose or "idle" else pet.action -- the pose it was stuck in
	-- the mutation it spawned with (or kept while dazed); freezing in the Big Chill makes it Frosty unless it already has a bigger one
	local mut = pet.mut
	if not dazed and EventService.isChill() and (not mut or Config.mutations[mut].bonus < Config.mutations.Frosty.bonus) then
		mut = "Frosty"
	end
	local info = { key = pet.def.key, zone = pet.zone, pose = pose, mut = mut, superFrozen = false, superUsed = pet.superUsed, offered = pet.offered }
	local at = pet.root.Position
	local gun = FreezeService.gunTier(player)
	local _, style = FreezeService.plan(pet.def, gun, dazed)
	-- a show only for a first freeze (zapping a melted pet back is quick and plain)
	local show = if dazed then nil else F.shows[pet.def.tier]
	WildPetSpawner.remove(id)
	-- the result is decided and stored before any show plays (Animation Rules 3)
	local uid = CarryService.dropCube(player, info, at, if show then showSeconds(show) else 0) -- on the ground until it's picked up
	DataService.mutate(player, function(d)
		d.stats.frozen += 1
		if not dazed and Config.tier(pet.def.tier).rank >= Config.challenges.rareRank then
			d.daily.rares += 1 -- the "Catch a Rare" daily challenge (a melted pet zapped back doesn't count twice)
		end
	end)
	AnalyticsSvc.funnel(player, "first_freeze")
	if show and uid then
		local list = shows[player] or {}
		shows[player] = list
		list[uid] = { show = show, key = info.key, pose = pose, mut = mut }
		task.delay(showSeconds(show), function()
			if shows[player] then
				shows[player][uid] = nil
			end
		end)
	end
	Remotes.fire(player, "Notify", "frozen", {
		key = info.key, pose = pose, mut = mut, at = at, uid = uid, style = style, gun = gun, touch = touchFor(gun), show = show,
	})
	if show and (Config.show :: any)[show].shout then
		Remotes.fireAll("Notify", "shoutout", { name = player.DisplayName, userId = player.UserId, key = info.key, tier = pet.def.tier })
	end
	-- no E between the freeze and the reward (QA 2026-11-08): the cube flies into your hands by itself once
	-- the snap (or the Legendary+ show) has played. A player who left, or a cube already gone, is a no-op.
	if uid and Config.carry.autoPickUp then
		task.delay(if show then showSeconds(show) else Config.carry.autoPickUpDelay, function()
			if player.Parent then
				CarryService.pickUp(player, uid, true)
			end
		end)
	end
	-- the ray goes away once the whole shot is done (tick / clearAim), not here: a many-beam gun's
	-- first cube to shut used to put it away and thaw the pet you were aiming at (QA 2026-11-05, PT-01)
end

-- one tick of the ray on a pet (the main one or an extra beam's): "frozen" when its cube shut this
-- tick, "pushed" when the ice rose, nil when it can't be frozen (or another beam already pushed it)
local function pushPet(player: Player, pet: any, data: any, gun: number, dt: number, pushed: { [any]: boolean }): string?
	if pushed[pet] or not canFreeze(player, pet, data) then
		return nil
	end
	local asleep = pet.state == "wild" and pet.action == "sleep"
	local seconds, style = FreezeService.plan(pet.def, gun, pet.state == "dazed", asleep)
	if data.tester.instantFreeze then -- tester switch: freezes on the first touch of the ray
		seconds = 0
	end
	pushed[pet] = true
	local meter = if seconds <= 0 then 1 else pet.meter + dt / seconds
	WildPetSpawner.setMeter(pet, math.min(meter, 1), style, PlayerTracker.position(player), player)
	if meter >= 1 then
		freezeOne(player, pet) -- the pet leaves the world here, so it can only shut once
		return "frozen"
	end
	return "pushed"
end

local function setAiming(player: Player, on: boolean)
	PlayerTracker.setZapping(player, on)
	player:SetAttribute("Aiming", on) -- every client raises this player's gun arm
end

-- you froze something: the ray goes away by itself until you've carried everything home (owner 2026-11-05)
local function stowAfterShot(player: Player)
	if Config.ray.putAwayAfterFreeze then
		GearService.stowRay(player)
	end
end

local function clearAim(player: Player)
	local aim = aims[player]
	if aim then
		aims[player] = nil
		setAiming(player, false)
		if aim.froze then
			stowAfterShot(player) -- let go after a freeze: the shot is over
		end
	end
end

local function tick(dt: number)
	local pushed: { [any]: boolean } = {}
	for player, aim in aims do
		local data = DataService.get(player)
		if not data or GearService.held(player) ~= "ray" or player:GetAttribute("Tagged") then
			continue -- the ray is put away, or you're tumbling over
		end
		local gun = FreezeService.gunTier(player)
		if aim.kind == "pet" then
			-- the main pet and every extra beam's pet rise together; each cube shuts on its own, and the
			-- ray goes away only once nothing of this shot is still freezing
			local busy = false
			local pet = WildPetSpawner.get(aim.id)
			if pet and inRange(player, pet.root.Position, A.rangeGrace) then
				local r = pushPet(player, pet, data, gun, dt, pushed)
				aim.froze = aim.froze or r == "frozen"
				busy = r == "pushed"
			end
			local left: { string } = {}
			for _, x in aim.extras do
				local e = WildPetSpawner.get(x)
				if e and e.state == "wild" and inRange(player, e.root.Position, A.rangeGrace) then
					local r = pushPet(player, e, data, gun, dt, pushed)
					aim.froze = aim.froze or r == "frozen"
					if r == "pushed" then
						busy = true
						table.insert(left, x)
					end
				end
			end
			aim.extras = left
			if aim.froze and not busy and aims[player] == aim then
				clearAim(player) -- the shot is done: the ray goes away (stowAfterShot)
			end
		else
			local t = targets[aim.kind]
			local pos = t and t.pos(aim.id)
			if t and pos and inRange(player, pos, A.rangeGrace) and t.canAim(player, aim.id) then
				t.tick(player, aim.id, dt, gun)
			end
		end
	end
	-- nobody aims at it: the ice melts back
	for _, pet in WildPetSpawner.all() do
		if pet.meter > 0 and not pushed[pet] then
			WildPetSpawner.setMeter(pet, math.max(0, pet.meter - A.thawPerSecond * dt), nil, nil, nil)
		end
	end
end

-- the client's aim: kind "pet" | "critter" | "player" | "none" and the target's id
local function onAim(player: Player, kind: any, id: any)
	if kind == "none" then
		clearAim(player)
		return
	end
	if typeof(kind) ~= "string" or not Remotes.isId(id, 24) then
		return
	end
	local data = DataService.get(player)
	if not data or GearService.held(player) ~= "ray" then
		return
	end
	local cur = aims[player]
	if cur and cur.kind == kind and cur.id == id then
		return
	end
	if kind == "pet" then
		local pet = WildPetSpawner.get(id)
		if not pet or not canFreeze(player, pet, data, true) then
			clearAim(player)
			return
		end
		-- a new pick while a shot that already froze something runs on carries that on (the ray still goes away after)
		aims[player] = { kind = kind, id = id, extras = pickExtras(player, pet, data, FreezeService.gunTier(player)), froze = cur and cur.froze }
		AnalyticsSvc.funnel(player, "first_zap")
	elseif targets[kind] and targets[kind].canAim(player, id) then
		aims[player] = { kind = kind, id = id, extras = {}, froze = cur and cur.froze }
	else
		clearAim(player)
		return
	end
	setAiming(player, true)
end

-- the client says a show ended (or was skipped): its cube melts normally again, and SKIP shows next time
local function onShowDone(player: Player, uid: any)
	if typeof(uid) ~= "string" or #uid > 16 then
		return
	end
	local list = shows[player]
	local s = list and list[uid]
	if not s then
		return
	end
	list[uid] = nil
	CarryService.endGrace(player, uid)
	DataService.mutate(player, function(d)
		d.seenShows[s.show] = true
	end)
end

local function setGunAttribute(player: Player)
	player:SetAttribute("GunTier", FreezeService.gunTier(player)) -- every client draws each player's gun and beam from it
end

function FreezeService.Init() end

function FreezeService.Start()
	Remotes.on("Aim", onAim)
	Remotes.on("ShowDone", onShowDone)
	GearService.Changed:Connect(function(player: Player)
		if GearService.held(player) ~= "ray" then
			clearAim(player) -- putting the ray away stops the beam
		end
	end)
	-- a ray the game put away comes back out once you carry nothing and nothing waits on the ground (banked, melted, knocked loose)
	task.spawn(function()
		while true do
			task.wait(0.25)
			for _, p in Players:GetPlayers() do
				if GearService.isStowed(p) and CarryService.load(p) == 0 then
					GearService.unstowRay(p)
				end
			end
		end
	end)
	-- leaving mid-show keeps the pet: it goes into your Pets, frozen for the Thaw Machine, saved on the way out
	CarryService.setLeaveHandler(function(player: Player, c)
		local list = shows[player]
		if not list or not list[c.uid] then
			return
		end
		list[c.uid] = nil
		DataService.mutate(player, function(d)
			PenService.addPet(d, c.key, c.pose, c.mut, true)
			d.stats.banked += 1
		end)
	end)
	DataService.Loaded:Connect(setGunAttribute)
	DataService.Changed:Connect(setGunAttribute)
	for _, p in Players:GetPlayers() do
		if DataService.isLoaded(p) then
			setGunAttribute(p)
		end
	end
	Players.PlayerRemoving:Connect(function(p)
		aims[p] = nil
		task.defer(function() -- after CarryService has handed over any mid-show cube
			shows[p] = nil
		end)
	end)
	task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(A.tickSeconds)
			local now = os.clock()
			local ok, err = pcall(tick, now - last)
			if not ok then
				warn("[FreezeService] tick:", err)
			end
			last = now
		end
	end)
end

return FreezeService
