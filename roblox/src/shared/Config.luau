--!strict
-- Config: every number, price, odd, timing, id and name lives here (Code Rules 4).
-- Mirrors prototype/ice-ray-for-pets/src/config.js; change both together.

export type Tier = {
	name: string,
	odds: number, -- percent
	cubeLife: number, -- seconds before heat
	income: number, -- coins per second in zone 1
	rank: number,
}

export type Zone = {
	id: number,
	key: string,
	name: string,
	heat: number,
	zMin: number,
	zMax: number,
	need: number, -- Cold Power to open it (Cold Power remake, 2026-11-10)
	-- Round 4 phase 6
	theme: string,
	ready: boolean, -- its pets are approved and finished; false = a glowing "Coming soon" gate, no pets
	gateRebirth: number, -- rebirths needed to open its gate (Config.world.rebirthGates), 0 = none
	iceLife: number, -- its pets' cubes last this many times longer (a colder gun froze them)
	feel: string, -- how hot it feels, the vault's word for it (Round 4 Prompt 6), on the island banner
}

local Config = {}

Config.version = 1

Config.data = {
	storeName = "IceRayPlayerData_v1",
	qaStoreSuffix = "_QA", -- Studio and test servers never touch the live store (QA Rules 8)
	retries = 5,
	retryBase = 0.5, -- seconds, doubles each retry
	-- the autosave refreshes the session lock, so it must come well before the lock counts as stale (it was 90 = 90,
	-- so a slow autosave could let another server take a live save: QA 2026-11-05, CA-03)
	autosaveSeconds = 60,
	lockStaleSeconds = 90,
	bindToCloseSeconds = 25,
	receiptsKept = 50,
}

Config.player = {
	-- owner 2026-11-10: 16 (Roblox's default) made the walk out "slow and boring". The pans' doors are 85-145
	-- studs from the first meadow pets, so 32 gets you there in 3-5 s, and every later island in half the time.
	-- Nothing sells speed (owner 2026-11-15: speed comes from Gear only, Ice Skates), so this is everyone's base speed.
	walkSpeed = 32,
	respawnSeconds = 1, -- Game Design Rules 7: failure is gentle, quick respawn (Roblox's default is 5)
	freezeRange = 10,
	refreezeHold = 0.35, -- zapping a melted pet back (a first freeze takes Config.show.freeze seconds)
	interactHold = 0.4, -- hold to pay at a gate (spends coins: no accidental taps)
	openHold = 0, -- booths, the Pan Upgrades stand and the gift open on a tap (owner 2026-11-02: "E to open doesn't work" = a tap did nothing)
	freezeCooldown = 0.3,
	rateLimitPerSecond = 12,
	-- remotes with their own budget, so a burst of one (aiming while you drag, or calls bunched up by a lag
	-- spike on a phone) can't crowd out the rest (mobile QA 2026-11-10)
	rateLimits = { Aim = 20, Train = 14, GetBoard = 2 } :: { [string]: number }, -- Train: click shots (TrainingService counts at most clickMax a second)
	maxSpeedTolerance = 1.6, -- server flags positions that move faster than this x walk speed
}

Config.tiers = {
	-- income (rarity pass 2026-11-17, owner: "apply Steal an Egg's rarities"): Steal an Egg's x4-x5 a rarity, tamed
	-- (no x10 at Legendary; Secret x10 Mythic as the jackpot) so luck never decides the game. Was 1/3/10/30/100/400/1500.
	-- Each island's 8 pets cover the 7 tiers (two Commons). PACING-2026-11-16.md section 6.
	{ name = "Common", odds = 59.995, cubeLife = 90, income = 1, rank = 1 },
	{ name = "Uncommon", odds = 25, cubeLife = 70, income = 4, rank = 2 },
	{ name = "Rare", odds = 10, cubeLife = 30, income = 20, rank = 3 }, -- owner 2026-10-30: steep: Commons easy, Secrets hard
	{ name = "Epic", odds = 4, cubeLife = 22, income = 100, rank = 4 },
	{ name = "Legendary", odds = 0.9, cubeLife = 16, income = 500, rank = 5 },
	{ name = "Mythic", odds = 0.1, cubeLife = 12, income = 2500, rank = 6 },
	{ name = "Secret", odds = 0.005, cubeLife = 8, income = 25000, rank = 7 }, -- 1 in 20,000, every zone
} :: { Tier }
Config.incomeZoneMultiplier = 4

Config.poses = {
	idle = { label = "Normal", bonus = 1.0, seconds = 2.4 },
	yawn = { label = "Yawn", bonus = 1.2, seconds = 1.3 },
	jump = { label = "Jump", bonus = 1.2, seconds = 0.9 },
	dance = { label = "Dance", bonus = 1.5, seconds = 1.6 },
	sneeze = { label = "Mid-Sneeze", bonus = 2.0, seconds = 0.7 },
	sleep = { label = "Sleeping", bonus = 0.8, seconds = 3 }, -- night only: every wild pet sleeps. 0.8 (owner 2026-11-12): a sleeping pet freezes in half the time, so it pays less
} :: { [string]: { label: string, bonus: number, seconds: number } }
Config.poseLoop = { "idle", "yawn", "idle", "jump", "idle", "dance" }
Config.sneezeChance = 0.08
Config.zapSlowdown = 0.5 -- a pet being held with Freeze acts at half speed, so a pose can be caught on purpose

-- chance = per wild spawn, rolled on the server; nightOnly = only while it's night (owner 2026-10-31:
-- Golden x2, Starry x5 and rarer). Frosty comes from freezing during the Big Chill instead.
-- One mutation per pet: if two apply, the bigger bonus wins.
Config.mutations = {
	Frosty = { bonus = 1.5, chance = 0 },
	Golden = { bonus = 2, chance = 1 / 40 },
	Starry = { bonus = 5, chance = 1 / 150, nightOnly = true },
} :: { [string]: { bonus: number, chance: number, nightOnly: boolean? } }
Config.mutationRollOrder = { "Starry", "Golden" } -- rarest first

Config.upgrades = { -- baseCost = the price of level 2; each step costs x1.5 the last (Game Plan 11)
	-- cube size: +12% a level for the first 4 levels (you can see it), then +2%
	ray = { name = "Ice Ray", baseCost = 40, costGrowth = 1.5, maxLevel = 20, lifeBonus = 0.02, -- +2% cube life a level (owner 2026-10-30)
		cubeSize = { early = 0.12, earlyLevels = 4, late = 0.02 } },
	-- boots: the old walk Speed upgrade. owner 2026-11-15: "we shouldn't be able to buy speed from the pan
	-- upgrades, gear was the idea behind speed". No longer sold or applied; DataService refunds old levels
	-- (Config.pan.speedRefund) and keeps the saved level at 1. Kept here only because saves carry it.
	boots = { name = "Speed", baseCost = 64, costGrowth = 1.5, maxLevel = 10, speedBonus = 0.1 },
	backpack = { name = "Backpack", baseCost = 750, costGrowth = 1.5, maxLevel = 5, slowPerExtraCube = 0.08 },
	-- owner 2026-11-05: 100 slots was "insane"; the pan tops out at 16 (10 to start, +1 a level, 7 levels).
	-- One slot is a bigger share now, so each level costs x2.5 the last, rounded (100, 250, 600, 1.5K, 4K, 10K)
	-- balance pass 2026-11-12: baseCost 100 -> 50 (first upgrade at ~90 s), rebirthGrowth 5 -> 15 (the
	-- rebuild after a late rebirth took 1-2 minutes)
	pen = { name = "Pan", baseCost = 50, costGrowth = 2.5, maxLevel = 7, slotsPerLevel = 1, rebirthGrowth = 15 },
} :: { [string]: { [string]: any } }
Config.upgradeIds = { "ray", "boots", "backpack", "pen" } -- every saved upgrade level
-- what the coin Shop sells: nothing since the owner removed its Upgrades list (2026-11-05); levels already
-- bought still count. ShopService only sells what's here, so a faked BuyUpgrade can't buy them (QA 2026-11-05, CA-01).
-- The pan's Slots ("pen") sell at the Pan Upgrades stand.
Config.shopUpgradeIds = {} :: { string }
-- Pen and Storage (owner 2026-10-30): the pen's pets earn; every other banked pet waits in Storage
-- (kept forever, in the Index, earns nothing). Players equip by hand or press Equip best.
Config.pen = { baseSlots = 10, maxSlots = 16, storageMax = 500, -- maxSlots: the pan never holds more, whatever adds slots
	displayMax = 32 } -- up to 32 of the pan's pets sit in it, frozen in a grid (Config.panCubes; Storage isn't shown in the world)
Config.carryHomeMinStuds = 4 -- funnel step 4 counts a cube carried at least this far out of the hub and back
Config.notYetCooldown = 2 -- seconds between two of the same "not yet" message
-- every pet's size multiplier (PetDefs.sizeHeight). QA 2026-11-08 (Studio-side work); restored 2026-11-09
-- after a sync overwrote Studio's Config. The value there was lost: 1 = the sizes the repo always had
Config.petScale = 1
-- a booth's popup closes this many studs before the server's own range ends: its buttons only work at
-- the booth, so walking away with it open left buttons that did nothing (final QA 2026-11-03)
Config.boothLeaveMargin = 4
Config.bigWinRank = 5 -- banking Legendary or better sends a server-wide banner and a light pillar over your pen (Game Plan 14)
-- each full zone page (all its pets, the Secret too) has a Claim button: +10% coins forever and the
-- page's Roblox badge. badges[zone] = the badge id from the Creator Dashboard (0 = not made yet, skipped).
-- pulse = the Claim button's bounce (scale, seconds a beat).
Config.index = {
	pageBonus = 0.1,
	claimCooldown = 0.5,
	badges = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 } :: { number },
	pulse = { scale = 1.08, seconds = 0.55 },
}
Config.income = { tickSeconds = 1 }
Config.sync = { seconds = 0.5 } -- the client's copy of its data is sent at most this often
Config.gatePromptOffset = 4 -- the gate prompt stands this far on the hub side of the gate
-- the gate's hold-to-open (owner 2026-11-12: "you literally cannot see it"): reach in studs (the gate is
-- wall to wall, so it shows anywhere along it, not only on the path) and the hold, long enough to see
-- the fill sweep across the pill
Config.gatePrompt = { range = 22, hold = 0.6 }
Config.gateCooldown = 0.4 -- seconds between two tries at the same player's gate (Round 4 phase 6)
Config.gateGuardStuds = 3 -- PlayerTracker puts anyone this far past a gate they haven't opened back in front of it
Config.shopOpenedCooldown = 2
-- owner 2026-11-15: phones (PerformanceController). A touch device under autoLowFps on average over
-- windowSeconds (after settleSeconds of loading) switches Low graphics on by itself, once per session.
Config.performance = { autoLowFps = 40, windowSeconds = 6, settleSeconds = 12 }

Config.settingsDefault = { music = true, sound = true, reducedMotion = false, lowGraphics = false, unit = "C" }
-- Tester tools (Round 4 phase 1): only these accounts get the Tester panel ("T" tile / T key) and the
-- "/dev" chat commands; every tester remote checks the caller's UserId on the server.
-- 1929450116 = the place owner (LupusorCoiotul, game.CreatorId), 520039727 = n2012haidu.
-- In Studio's local Start Server test, Player1 (UserId -1) is a tester and Player2 (-2) is not.
Config.testers = {
	userIds = { 1929450116, 520039727 },
	studioUserIds = { -1 },
}
Config.dev = {
	-- "Play as a new player" (design review 2026-11-15): in Studio only (the QA store), a non-empty name gives
	-- every save its own key u_<id>_<name>, so a play test starts from a brand-new save and nobody's own save
	-- is touched. Change the name for another fresh start. Leave it "" normally. A live server ignores it.
	freshSave = "",
	maxCoins = 1e15, heatMax = 5, awayMax = 24 * 3600,
	multMin = 0.1, multMax = 10000,
	walkMin = 16, walkMax = 100,
	addCoins = { 1e3, 1e6, 1e9 },
	multPresets = { 1, 10, 100, 1000 },
	walkPresets = { 16, 32, 60, 100 },
	maxRebirths = 50,
	readoutSeconds = 1,
	powerPresets = { 0, 1e3, 1e6, 1e9, 1e12 }, -- the Tester panel's Cold Power buttons
	awayHours = { 1, 8, 24 },
	friendPresets = { 0, 1, 3 },
	-- the panel (remade 2026-11-12): a big popup, the readout and tabs on top (topHeight, share of the
	-- body), then a grid of small buttons: perRow slots a row, gap between them (share of the width),
	-- rowAspect / headAspect = a button row's / a heading's width over height
	panel = {
		tabs = { { id = "player", label = "Player" }, { id = "world", label = "World" }, { id = "pets", label = "Pets" },
			{ id = "events", label = "Events" }, { id = "save", label = "Save" } },
		topHeight = 0.16, perRow = 6, gap = 0.01, rowAspect = 20, headAspect = 30,
	},
}

function Config.isTester(userId: number): boolean
	if table.find(Config.testers.userIds, userId) then
		return true
	end
	return game:GetService("RunService"):IsStudio() and table.find(Config.testers.studioUserIds, userId) ~= nil
end

Config.melt = {
	shade = 0.5,
	sun = 1.5,
	night = 0.6, -- Game Plan 12
	lava = 2.5, -- standing in a lava pool (hot islands, Round 4 phase 6)
	hubHeat = 0, -- the hub is a safe zone: nothing melts there (Round 4 phase 2)
	tickSeconds = 0.1, -- server melt tick
	-- How long a carried cube lasts (owner 2026-11-12: "it's very hard to unfreeze, it's too ez"; the old
	-- fixed lives gave an island-1 Common 3 minutes for a 4 second walk, and a Magma Core Secret too little
	-- for a straight walk home). Now worked out from the trip home (Config.cubeLife): the melt a straight
	-- walk home costs from homeFrom of the way into the pet's island, plus slackSeconds of extra walking on
	-- its island, is homeShare[tier] of the cube. So a straight run home always makes it; a detour, sun
	-- patches or lava can melt it, more easily the rarer the pet. A melt is gentle: the pet drops dazed
	-- next to you and only you can zap it back.
	homeShare = { Common = 0.3, Uncommon = 0.4, Rare = 0.5, Epic = 0.58, Legendary = 0.65, Mythic = 0.72, Secret = 0.8 } :: { [string]: number },
	homeFrom = 0.75, -- Rare and up spawn in an island's far half
	slackSeconds = 8,
}

-- Temperature: a readable version of the melt speed (owner request 2026-10-30). Worked out from the
-- melt numbers, never the other way round: degrees C = atZeroMelt + perMelt x melt speed.
-- Zone, shade, sun, night and the Big Chill all move it. Shown on the HUD chip and the zone signs.
Config.temperature = {
	unit = "C", -- players can switch to F in Settings
	atZeroMelt = -20,
	perMelt = 30,
	bands = { { below = 0, name = "cold" }, { below = 15, name = "cool" }, { below = 35, name = "warm" }, { below = 999, name = "hot" } },
}
Config.dazedSeconds = 8

Config.spawner = {
	-- owner 2026-10-30: Common and Uncommon pets are shared by everyone on the server; Rare and up
	-- spawn just for one player (only they see and can freeze it), each with their own pity
	personalRares = true,
	personalMaxPerZone = 3,
	maxPerZone = 9,
	respawnSeconds = 1.5,
	firstPetDistance = 10, -- studs past the tunnel mouth (about 3 s from the spawn)
	-- "always one within about 3 seconds of walking": each zone keeps 2 Commons or Uncommons in its
	-- near band; other Commons spawn from farZMin; Rare and up only in the far half of the zone.
	-- Both come from each island's near / farFrom in Config.world (filled in there).
	near = {} :: { [number]: { number } },
	nearCount = 2,
	farZMin = {} :: { [number]: number },
	wallMargin = 6, -- pets spawn and wander at least this far from the tunnel walls
	wanderSpeed = 2,
	pity = { graceFactor = 1.0, perMiss = 0.0015, maxBoost = 3 },
	-- owner 2026-11-12: "players leave because they can't find an Epic". On the first islands the rarer
	-- tiers roll more often (x the tier's odds, then all tiers rescaled to 100%): Epic ~4% -> ~7.3%.
	-- Secret stays the long chase.
	earlyIslands = { upTo = 4, mult = { Rare = 1.5, Epic = 2, Legendary = 2, Mythic = 1.5 } :: { [string]: number } },
	-- Wild pets nobody is after wander off after lifeSeconds, so a zone never clogs with uncaught Commons
	-- (rolls only happen while it has room). Only when no player is within despawnClearStuds, so a pet
	-- never vanishes in front of you; never while it has ice on it. Tiers not listed stay until caught.
	-- owner 2026-11-15 (Night Reset): Commons, Uncommons and Rares nobody is freezing go after a minute.
	-- "Interacting" = ice on it; the stand-off guard is only right next to you now (it was 30 studs).
	lifeSeconds = { Common = 60, Uncommon = 60, Rare = 60 } :: { [string]: number },
	despawnClearStuds = 12,
	-- the rarest pets are restless (owner 2026-11-12: "secrets should be harder to ice ray, they should move
	-- quicker and more random"). Per tier: speed = x wanderSpeed, always on the move whatever their pose;
	-- dart = seconds before they pick a new random spot (min, max) within dartRadius studs; flee = x
	-- Config.aim.fleeSpeed while scared; zigzag = the most they swerve (radians) each swerveEvery seconds
	-- while running from the ray; sleeps = false: too excited to nap at night
	motion = {
		-- flee raised 2026-11-13 (owner: "the minigame is too easy"); the base fleeSpeed went 4.5 -> 6 too
		Mythic = { speed = 1.6, dart = { 1.2, 2.4 }, dartRadius = 12, flee = 2.1, zigzag = 0.7, swerveEvery = 0.45, sleeps = true },
		Secret = { speed = 2.6, dart = { 0.5, 1.2 }, dartRadius = 16, flee = 2.6, zigzag = 1.1, swerveEvery = 0.3, sleeps = false },
	} :: { [string]: { speed: number, dart: { number }, dartRadius: number, flee: number, zigzag: number, swerveEvery: number, sleeps: boolean } },
}

Config.bigChill = { everySeconds = 600, warnSeconds = 30, durationSeconds = 60 }

-- Secret spawns (owner 2026-11-16: "a secret every 30 minutes"). On the clock, not from server start: every
-- server agrees, a player who joins late isn't behind, and the HUD can say "Secret in 12:30" anywhere. At each
-- half hour (Unix time, so :00 and :30) ONE Secret appears on the whole map, on a ready island picked at random
-- (owner 2026-11-16: "only 1 in the whole map"), shared: anyone whose Cold Power and gun can freeze that
-- island's pets may catch it. It stays lifeSeconds (or until frozen), visible
-- from every island (PetVisuals), and the whole server gets an alert. Ice on it keeps it from leaving.
Config.secretSpawn = { everySeconds = 1800, lifeSeconds = 300, warnSeconds = 60 }

-- Server events (owner 2026-11-16: "an event every 30 mins, the current events are kinda shitty"): replaces the
-- Big Chill's own 10-minute clock. Every everySeconds (Unix time, offsetSeconds after each half hour, so they
-- never land on a Secret) one event runs for durationSeconds, the next in the list each time. Everyone gets the
-- alert warnSeconds before. A bought Big Chill still works any time (EventService.startBought).
--   chill  = the Big Chill: nothing melts, and every pet frozen in it is Frosty
--   luck   = Lucky Rush: Rare and up roll luckMult x as often (the odds a player sees include it)
--   coins  = Coin Rush: every pan earns coinMult x
--   golden = Golden Rush: Golden pets spawn goldenMult x as often
export type ServerEvent = { id: string, name: string, line: string, icon: string }
Config.events = {
	everySeconds = 1800, offsetSeconds = 900, durationSeconds = 300, warnSeconds = 30,
	luckMult = 2, coinMult = 2, goldenMult = 5,
	list = {
		{ id = "chill", name = "BIG CHILL", line = "Nothing melts! Pets freeze Frosty", icon = "ray" },
		{ id = "luck", name = "LUCKY RUSH", line = "Rare pets x2 more often!", icon = "gift" },
		{ id = "coins", name = "COIN RUSH", line = "Your pets make x2 coins!", icon = "coin" },
		{ id = "golden", name = "GOLDEN RUSH", line = "Golden pets x5 more often!", icon = "coin" },
	} :: { ServerEvent },
}

-- the islands close at night (owner 2026-11-16, "just like in steal an egg"): as the Night Reset falls, glowing
-- walls rise at the tunnel mouth and anyone out on the islands is brought home to their pan (cubes in hand come
-- too, nothing is lost). They open again at sunrise. warnSeconds: "Night soon! Head home" this long before.
Config.nightClose = { warnSeconds = 15, wallHeight = 40, wallZ = 1, homeDelay = 0.6 }

-- Night (owner 2026-10-31): one 15-minute loop for the whole server, worked out from server time so
-- every client agrees without messages. day -> sunset -> night -> sunrise. At night pets sleep (freeze
-- in half the time, Sleeping pose), cubes melt slower (Config.melt.night) and Starry pets can spawn.
-- Candy night, never scary: deep blue-purple, bright enough to play.
-- Night Reset (owner 2026-11-15: "night is too easy, sleeping pets are free catches; make night a reset"):
-- every 5 minutes a 10-second night falls. Its first moment clears the islands' Commons, Uncommons and
-- Rares (resetTiers) with a snowy poof, unless someone has ice on them; nothing new spawns while it's dark;
-- at sunrise a fresh wave pops in at once, and that wave can roll Starry. Epic and up stay through it.
-- Pets no longer sleep at night (petsSleep), so the night is never a free catch.
Config.night = {
	daySeconds = 282, fadeSeconds = 4, nightSeconds = 10, -- cycle = day + fade + night + fade = 300 s
	petsSleep = false,
	resetTiers = { Common = true, Uncommon = true, Rare = true } :: { [string]: boolean }, -- never a personal pet (your own Rare, the tutorial pet)
	-- Starry night (design review 2026-11-15: the night was 14 s with nothing to do): as night falls, each player
	-- may get one personal Starry pet near them, on the island they stand on (from the hub: island 1). Rolled with
	-- the island's normal odds and their pity, so it's a nice surprise, not a free Rare. Numbers: an owner call.
	starry = { chance = 0.5, minStuds = 14, maxStuds = 26 },
	sleepFreezeFactor = 0.5, -- a sleeping pet's Freeze hold is this much of the normal hold (only if petsSleep)
	nightAt = 0.5, -- the blend (0 day, 1 night) at which the rules switch to night
	day = { clock = 14, brightness = 2.2, ambient = Color3.fromRGB(95, 90, 85), outdoor = Color3.fromRGB(115, 115, 128), -- warm, bright day (2026-11-09)
		tint = Color3.new(1, 1, 1), ccBrightness = 0, stars = 0, haze = 0 },
	night = { clock = 24, brightness = 1.6, ambient = Color3.fromRGB(95, 85, 160), outdoor = Color3.fromRGB(130, 120, 200),
		tint = Color3.fromRGB(215, 220, 255), ccBrightness = 0.06, atmo = Color3.fromHex("6a5cc4"), stars = 3000,
		haze = 2.2 }, -- haze paints the night sky blue-purple instead of black
	lampBoost = 2.5, -- the map's lamps and lanterns shine this much brighter at night
	zzzEvery = 1.2, -- a little Z rises over a sleeping pet this often
}

Config.away = { minSeconds = 60, capSeconds = 8 * 3600, rate = 0.25 } -- owner 2026-10-30: 25%, so a night away never skips a zone

-- Friend bonus (2026-11-09, Game Design Rules 1 "the friend twist": playing with friends is better,
-- nobody loses anything): every Roblox friend in your server adds perFriend to your coins, up to max
-- friends. Shown beside your +N/s; a banner when a friend arrives. Nothing is taken from anyone.
Config.friends = { perFriend = 0.1, max = 3 }

-- Daily challenges (2026-11-09): three small goals a day, picked per player from the pool by the UTC
-- day. Progress counts from the moment they're handed out. Each pays rewardMinutes of your own income
-- (never under rewardFloor), rounded like every price. A finished one you forgot to claim is paid
-- automatically when the day turns, so missing the claim never loses it (Game Design Rules 9).
-- goal: a fixed count picked from `goals`, or for coins, `incomeMinutes` of your income (never under floor).
export type ChallengeDef = { id: string, text: string, stat: string, goals: { number }?, incomeMinutes: { number }?, floor: number? }
Config.challenges = {
	perDay = 3,
	rewardMinutes = 6,
	rewardFloor = 150,
	pool = {
		{ id = "freeze", text = "Freeze {n} pets", stat = "frozen", goals = { 8, 12, 16 } },
		{ id = "bank", text = "Bring {n} pets home", stat = "banked", goals = { 5, 8, 10 } },
		{ id = "rare", text = "Catch {n} Rare or better", stat = "rares", goals = { 1, 2 } },
		{ id = "coins", text = "Earn {n} coins", stat = "coinsEarned", incomeMinutes = { 10, 15, 20 }, floor = 500 },
	} :: { ChallengeDef },
	rareRank = 3, -- "Rare or better" = this tier rank and up
	checkSeconds = 1, -- how often the server looks for a newly finished challenge (to tell the player)
}
-- The Free Gift (owner 2026-11-12, replaces the daily gift): a one-time early boost at the gift box.
-- Three steps like hit games' "free reward" boards: Like the game, Favorite it, join the community.
-- Only the community join can be checked (Player:IsInGroupAsync), so only it is required on the server;
-- Like has no API, and Favorite opens Roblox's own prompt. groupId = 0: no community made yet (the step
-- shows "Soon" and isn't checked). coins + power: a head start, power = half of Pine Forest's need.
Config.freeGift = { coins = 2500, power = 75, -- power: half of Pine Forest's need (150 since 2026-11-16)
	 groupId = 552866458, claimRange = 30 } -- groupId: WolfDev (owner 2026-11-12)

export type RobuxItem = {
	id: string, kind: string, name: string, text: string, icon: string, robux: number,
	productId: number?, passId: number?, -- a developer product, or a game pass (kind "pass")
	mult: number?, minutes: number?, floor: number?, stack: number?, charges: number?,
	share: number?, -- a Cold Power pack: this share of your next island's need (Config.powerPack)
	big: string?, chip: string?, -- the shop card's big number and its white chip, when the game can't work them out
}
Config.monetization = {
	-- Owner items: create the developer product in the Creator Dashboard and paste its id here.
	superFreeze = { productId = 3732434839, robux = 15, minTier = "Rare", walkAwayStuds = 18 },
	passCheck = { tries = 5, seconds = 4 }, -- after a pass purchase: ask Roblox this many times, this far apart, before giving up
	-- the Robux tab of the Shop, top to bottom (owner 2026-11-05). An id of 0 = not made yet: hidden in
	-- live servers, given free in Studio so it can be tested. Coin packs are minutes of your own income
	-- (never under floor), so a pack is worth the same at every stage. Bought coins skip the weekly board.
	-- Robux prices (owner 2026-11-07) sit on the price points players know from hit games (49 / 99 / 199;
	-- Steal a Brainrot's 2x Money is 299), and a bigger pack is better value: 1 hour, 3 hours, 8 hours of
	-- income. The real price is set on the product in the Creator Dashboard: keep both the same.
	shop = {
		{ id = "doubleCoins", kind = "pass", passId = 2088197425, robux = 199, mult = 2, name = "2x Coins", text = "Your pan earns double, forever", icon = "coin", stack = 2 },
		{ id = "coinsSmall", kind = "coins", productId = 3732434676, robux = 49, minutes = 60, floor = 2500, name = "Coin Bag", text = "", icon = "coin", stack = 1 },
		{ id = "coinsMedium", kind = "coins", productId = 3732434699, robux = 99, minutes = 180, floor = 10e3, name = "Coin Chest", text = "", icon = "coin", stack = 2 },
		{ id = "coinsBig", kind = "coins", productId = 3732434725, robux = 199, minutes = 480, floor = 25e3, name = "Coin Vault", text = "", icon = "coin", stack = 3 },
		{ id = "superFreeze3", kind = "charges", productId = 3732434800, robux = 39, charges = 3, name = "Super Freeze", text = "3 for rare pets", icon = "ray", stack = 1, chip = "Rare+ pets, instantly" },
		-- a Big Chill for the whole server, with "<name> started a Big Chill for everyone!" (2026-11-10,
		-- Game Design Rules 10: server-wide events). Everyone gets it; it never moves the free Chill's clock.
		{ id = "bigChill", kind = "chill", productId = 3732434823, robux = 49, name = "Big Chill", text = "60 s for everyone", icon = "temp", stack = 1, big = "60s", chip = "For everyone" },
		-- Cold Power (2026-11-10; starting prices, the owner sets the real ones). Never needed to progress:
		-- standing on a training station shoots by itself for free (Config.training.autoEvery), the pass
		-- only makes those shots faster, and clicking on top is always the best rate.
		-- A pack is a share of your next island's need (Config.powerPack), so it's worth the same at every stage.
		{ id = "autoTrain", kind = "pass", passId = 2089625470, robux = 149, name = "Full-Speed Auto-Train", text = "Your gun trains 4x faster on its own", icon = "power", stack = 1 },
		{ id = "doublePower", kind = "pass", passId = 2088923504, robux = 199, mult = 2, name = "2x Cold Power", text = "Double Cold Power, forever", icon = "power", stack = 2 },
		{ id = "powerSmall", kind = "power", productId = 3732434754, robux = 49, share = 0.25, name = "Cold Power Pack", text = "", icon = "power", stack = 1 },
		{ id = "powerBig", kind = "power", productId = 3732434775, robux = 149, share = 1, name = "Big Cold Power Pack", text = "", icon = "power", stack = 3 },
	} :: { RobuxItem },
	-- the Shop's tabs (shop v2, 2026-11-10: mobile-store layout), top to bottom on the left rail.
	-- kinds = the items each tab shows; colour = Theme.shopCards[colour]. The shop opens on Forever
	-- while a pass is still unowned, else on Coins.
	shopTabs = {
		{ id = "forever", label = "Forever", icon = "star", colour = "pass", kinds = { pass = true }, title = "Forever passes", sub = "Buy once, keep it for good" },
		{ id = "coins", label = "Coins", icon = "coin", colour = "coins", kinds = { coins = true }, title = "Coins", sub = "Bigger packs give more coins for each Robux" },
		{ id = "power", label = "Power", icon = "power", colour = "power", kinds = { power = true }, title = "Cold Power", sub = "" },
		{ id = "boosts", label = "Boosts", icon = "ray", colour = "charges", kinds = { charges = true, chill = true }, title = "Boosts", sub = "Use them when you need them" },
	} :: { { id: string, label: string, icon: string, colour: string, kinds: { [string]: boolean }, title: string, sub: string } },
}

function Config.robuxItem(id: string): RobuxItem?
	for _, item in Config.monetization.shop do
		if item.id == id then
			return item
		end
	end
	return nil
end

-- a coin pack's coins at this income (coins per second), rounded to a round number like every price
function Config.robuxCoins(item: RobuxItem, income: number): number
	-- rounded up, never down: a paid pack never gives less than its minutes of income
	local raw = income * 60 * (item.minutes or 0)
	local coins = Config.nice(raw)
	if coins < raw then
		local p = 10 ^ math.floor(math.log10(raw))
		for _, s in Config.niceSteps do
			if s * p >= raw then
				coins = math.round(s * p)
				break
			end
		end
	end
	return math.max(item.floor or 0, coins)
end

-- made in the Creator Dashboard yet? (0 = not yet)
function Config.robuxReady(item: RobuxItem): boolean
	return (if item.kind == "pass" then item.passId else item.productId) ~= 0
end

Config.leaderboards = {
	size = 10,
	refreshSeconds = 60, -- read + redraw boards (cached on the server)
	writeSeconds = 120, -- each player's scores are written at most this often (DataStore limits)
	rankScanSize = 100, -- "your rank" looks this far down the board; past it shows "100+"
	weeklyResetDay = 1, -- 1 = Monday, UTC calendar day (not a countdown)
	weeklyResetLabel = "Resets every Monday",
	-- scores come from the server's own counters and are clamped before writing (OrderedDataStore needs an integer under 2^63)
	limits = { frozen = 10000000, weekCoins = 1e13, freezesPerSecond = 1 },
	storePrefix = "LB_v1_",
	-- icon = a Config.images.icons name on the header; the header's colour is Theme.boards[id]
	boards = {
		{ id = "pets_frozen", title = "MOST FROZEN", subtitle = "Pets frozen, all time", icon = "ray", kind = "alltime" },
		{ id = "coins_week", title = "TOP COINS", subtitle = "Coins earned this week", icon = "coin", kind = "weekly" },
	},
	updatesLabel = "Updates every minute",
	cosmeticReward = "Top 3 each week get a glowing name",
	weeklyTopReward = 3, -- how many places get the name-plate glow; never coins or pets
	weeklyBadgeId = 0, -- optional owner item: a badge for weekly top 3 (0 = off)
	hiddenName = "A player", -- shown when a display name can't be fetched
	-- owner 2026-11-12: press E at a board to scroll its top 100, with your own place under the list.
	-- prompt = where the E prompt floats (studs from the board's middle; -Z is its front) and its reach;
	-- rowAspect = a row's width / height in the popup
	-- 8 studs out (was 2.5): close to the board the pill cut into it and your character hid it (owner 2026-11-12)
	prompt = { offset = Vector3.new(0, -6, -8), range = 16 },
	popup = { rowAspect = 9.5, footHeight = 0.13 },
	nameBatch = 50, -- display names are asked of Roblox this many at a time
	loadRange = 20, -- owner 2026-11-16 (performance): a board only draws while you stand this many studs from it
}

Config.analytics = {
	-- one list for the whole game; AnalyticsSvc refuses anything not in it
	funnel = {
		{ step = 1, name = "joined" },
		{ step = 2, name = "first_zap" },
		{ step = 3, name = "first_freeze" },
		{ step = 4, name = "first_carry_home" },
		{ step = 5, name = "first_bank" },
		{ step = 6, name = "first_thaw" }, -- Lesson 1's every step (2026-11-15, Tizzy: funnel each tutorial step)
		{ step = 7, name = "first_pet_out" },
		{ step = 8, name = "first_coins_spent" },
		{ step = 9, name = "tutorial_done" },
		{ step = 10, name = "first_rare_pet" },
		{ step = 11, name = "lesson2_start" }, -- Tutorial Lesson 2, Cold Power (2026-11-15)
		{ step = 12, name = "first_train" },
		{ step = 13, name = "first_power_ready" },
		{ step = 14, name = "first_new_zone" },
	},
	-- AnalyticsService:LogCustomEvent takes one number (value) and up to 3 string custom fields
	events = {
		cube_melted = { value = "studsFromHome", fields = { "pet", "tier", "zone" } },
		pet_banked = { value = "carrySeconds", fields = { "pet", "tier", "pose" } },
		zone_entered = { value = nil, fields = { "zone" } },
		shop_opened = { value = nil, fields = {} },
		offer_shown = { value = nil, fields = { "offer", "pet", "tier" } },
		offer_bought = { value = "robux", fields = { "offer" } },
		session_end = { value = "sessionSeconds", fields = { "zone", "lastAction", "carryingCube" } },
		train_session = { value = "gain", fields = { "station", "level" } }, -- someone stepped off a training station
		rebirth = { value = "rebirths", fields = {} }, -- RebirthService (QA IR-13: it was dropped, not on this list)
	} :: { [string]: { value: string?, fields: { string } } },
	lastActions = { "zapping", "carrying", "in_pen", "in_menu", "exploring" },
}

Config.sounds = {
	-- Picked 2026-11-09 from Roblox-licensed audio only (Sound Rules 8): "Roblox" = Roblox's own UI and
	-- Pinball packs, PSE = Pro Sound Effects (91xxxxxxxx), APM = APM Music (APMOfficial). Each id was
	-- checked with ContentProvider:PreloadAsync (Success) in this place. 0 = silent stand-in.
	-- The owner should listen once and swap any that don't fit.
	music = 0.45,
	sfx = 0.8,
	ids = {
		click = 15675059323, -- Roblox_UI_Bright_Click (Roblox)
		zap = 9120985853, -- Zaps Sharp Attack 1 (PSE)
		freeze = 9125611312, -- Ice Freeze Large Piece Crackles (PSE)
		coin = 9126073001, -- Synth Sparkle Tone High Pitch Bell Tone Ding (PSE)
		bank = 9116395089, -- Magic Glows Soft Clusters Of Chiming Hits 4 (PSE)
		reveal_rare = 9119447936, -- Sparkle Bell Tree Wind Chimes 1 (PSE)
		no = 15675075163, -- Roblox_UI_Delete (Roblox): a soft falling "not yet"
		buy = 17208380755, -- Roblox GUI - Purchase (Roblox)
		melt = 9114869369, -- Ice Slush Scraping Up Melted Remnants 2 (PSE)
		chill = 9116431854, -- Magic Wind Airy Whooshy Wind 1 (PSE)
		gift = 9126076030, -- Synth Sparkle Tone High Pitch Tone Burst (PSE)
		unlock = 15675043410, -- Roblox_UI_Tonal_Stinger (Roblox)
		bridge = 9120733055, -- Whoosh Rising Swish Airy 1 (PSE)
		music_meadow = 1839620758, -- Charming View Ukulele (APM), the owner's pick
		music_forest = 1838880621, -- Forest Walk (APM)
		island = 15674975792, -- the island banner dropping in: Roblox_UI_Whoosh_03 (Roblox)
		tink = 9114618736, -- freeze snap: Glass Tinks 1 (PSE)
		crack = 9125611419, -- layered crack: Ice Freeze Large Piece Crackles (PSE)
		slam = 9113225986, -- show slam: Axe Impact Giant Thuddy Hits On Wood Floor 5 (PSE)
		reveal_secret = 9125641284, -- Magic Synth Stinger Glassine Multi Tone Burst (PSE)
		pan_up = 9126072453, -- a pan upgrade's burst: Synth Sparkle Tone Bell Tone Burst (PSE)
		sell = 9113728042, -- Cash Register 1 (PSE)
		bounce = 12222124, -- a cube too hot for your pan: Short spring sound (Roblox)
		thaw_done = 15675055424, -- your Thaw Machine lets a pet out: Roblox_UI_Cute_Pop (Roblox)
		upgrade_charge = 9125805094, -- Rising Synth Tone Ascending In Pitch (PSE)
		upgrade_hit = 16480574637, -- Roblox_Pinball_Bumper_Full_01 (Roblox)
		upgrade_chime = 9126073318, -- Synth Sparkle Tone Bell Tone Ding (PSE), pitched up per streak
		-- the shot (Config.ray.anim): charge whoosh, mechanical clack, fire, the hold's hum (looped), the
		-- airy tail after a lock, a fizz when you let go early, and soft crackles as ice flecks form
		ray_charge = 9125626779, -- Light Cone Suck Synth And Reverse Cymbal Build (PSE)
		ray_clack = 16480551554, -- Roblox_Pinball_Small_Metal_Click_01 (Roblox)
		ray_fire = 9120985853, -- Zaps Sharp Attack 1 (PSE)
		ray_hum = 9116386800, -- Magic Force Field Constant 1 (PSE), looped
		ray_tail = 9116418035, -- Magic Tone Falling Shimmer Flanged 3 (PSE)
		ray_fizz = 9119165650, -- Sizzle Short And Explosive Sear 4 (PSE)
		ray_crackle = 9125611291, -- Ice Freeze Large Piece Crackles (PSE)
		friend = 17208361335, -- a friend joins your server: Roblox GUI - Notification High (Roblox)
		challenge = 15675043410, -- a daily challenge done: Roblox_UI_Tonal_Stinger (Roblox)
		-- the rebirth show (2026-11-12): bright orchestral stings (APM "Magical Meetup", Spot On / Happy Place)
		rebirth_fanfare = 9048764286, -- Magical Meetup - Tag2 (APM), the reveal
		rebirth_hit = 9048764753, -- Magical Meetup - Hit4 (APM), the burst
	} :: { [string]: number },
	-- long library sounds are cut to fit the moment (seconds, with a short fade). Sound Rules 8: trimmed.
	trim = {
		freeze = 1.6, crack = 1.0, tink = 0.8, ray_charge = 0.6, ray_fire = 0.7, zap = 0.7, ray_crackle = 0.5,
		ray_tail = 1.2, chill = 3, reveal_rare = 2.5, reveal_secret = 3, upgrade_charge = 1.2, melt = 1.2,
		thaw_done = 1.2, bank = 1.6, sell = 1.2, coin = 0.8,
	} :: { [string]: number },
	-- per-sound loudness on top of sfx, so they feel about equally loud (Sound Rules 8: leveled)
	volume = { ray_hum = 0.35, ray_crackle = 0.5, chill = 0.6, melt = 0.7, crack = 0.7, freeze = 0.8, slam = 0.8 } :: { [string]: number },
	-- these climb a semitone each time they play again within streakReset seconds (Sound Rules 3)
	streak = { coin = true, bank = true, tink = true, sell = true } :: { [string]: boolean },
	streakMax = 7,
	pitchJitter = 0.05, -- every other one-shot plays at 1 +/- this, so the 500th doesn't grate
	fadeSeconds = 0.15,
	maxSame = 3,
	maxSameFor = { coin = 8 } :: { [string]: number }, -- the bank tally plays a quick run of coin dings (Config.juice.tally)
	streakReset = 1.5,
}

Config.ui = {
	tiles = { { id = "pets", label = "Pets" }, { id = "shop", label = "Shop" }, { id = "index", label = "Index" }, { id = "daily", label = "Daily" }, { id = "settings", label = "Settings" } },
	-- owner 2026-11-15: this tile spans the whole top row of the tile grid (Screen.layout); its icon rocks gently
	wideTile = "shop",
	tileMinFit = 0.075,
	phoneShortPx = 600, -- a touch screen whose short side is under this many px is a phone (InputController) -- a tile never shrinks below this share of the short side to fit above the coins
	wideTileWiggle = { degrees = 6, seconds = 1.1 },
	wideTileText = { 0.48, 0.42, 0.47, 0.29 }, -- SHOP on the wide tile: width, height, x, y (smaller, owner 2026-11-16: it didn't match the others)
	-- touch screens (mobile QA 2026-11-10): no tap target under this many pixels (Apple asks 44). Tiles,
	-- world prompts and the popup X use it; the hotbar slot has its own floor so its name stays readable
	minTouchPx = 46, hotbarMinPx = 52,
	-- phones: popups take the whole height under the top bar (at 70% the text came out 8.8 px), short
	-- reward popups keep this share instead of 0.62 (at 0.8 a 338 px tall phone still had 9 px text),
	-- and the banner is at least this share of the width
	phoneSmallPopup = 1, bannerPhoneWidth = 0.62,
	touchTextFloor = { title = 18, body = 14, button = 14, small = 12, tiny = 11 } :: { [string]: number }, -- popup text caps never go under these on touch screens (px)
	touchRowAspect = 0.8, -- phones and tablets: long list rows (Pets, Thaw, Tester) are this much less wide-for-their-height
	-- the purple Robux bars (owner 2026-11-16: the Thaw Machine's Skip, Pets' Unfreeze all): the row's
	-- width-for-height, and the gaps (share of the bar) between the words and the Robux mark, and the mark and the price
	skipAll = { aspect = 6.2, wordGap = 0.04, markGap = 0.012 },
	-- sizes are fractions of the screen's short side (Scale only, UI Rules); the Screen module places them
	-- owner 2026-10-31: smaller side tiles (still over 10% of the short side for small fingers);
	-- owner 2026-11-07: the goal bar and temperature chip are gone; the island banner (below) took their place
	tileSize = 0.105, tileGap = 0.016, coinsSize = { 0.3, 0.1 }, bannerSize = { 0.5, 0.088 },
	-- Cold Power (2026-11-10): its counter sits under the coins, bottom left (the two lift together over
	-- the thumbstick). popScale / popSeconds: the number's small bounce when it goes up.
	gearCardAspect = 6, -- a card's width / height in the scrolling Gear and Pan Upgrades lists (2026-11-13)
	coinsShortFrom = 1e6, coinsRateGap = 0.06, -- owner 2026-11-13: from 1M the counter reads 1.50M; the +N/s sits this far right of the number
	powerSize = { 0.3, 0.1 }, powerPop = { scale = 1.18, seconds = 0.22 }, -- powerSize (owner 2026-11-12): as big as the coins (was 0.07 tall)
	-- Cold Power trainers (2026-11-10): no HUD pieces, everything floats in the world (pixel-sized
	-- BillboardGuis, the same size at any distance, like the coin pops).
	--   sign*  = "+N/shot" over your own trainer (owner 2026-11-11), signGap studs over its target. It shows
	--            only while your character is within signShowStuds of the target (flat distance)
	--   pop    = the "+N" that shoots off the target on every shot (CoinPops' motion), big* on a shatter
	--   bolt   = the frost bolt from the gun's tip to the target (seconds in flight, size in studs)
	--   wobble = the target's squash when a bolt lands; turnSpeed = how fast you turn to face it
	training = {
		signPx = 32, signGap = 3.5, signShowStuds = 25, -- signGap clears the heat bag frame's top beam
		pop = { px = 34, bigPx = 56, iconPx = 36, outX = { 40, 95 }, outY = { 36, 78 }, out = 0.22, hold = 0.5, exit = 0.18,
			drift = 12, tilt = 10, startScale = 0.45, exitScale = 0.8, maxActive = 18, maxDistance = 90, boxPx = { 420, 260 },
			front = 3.5 }, -- studs toward the camera, in front of the target (the pops aren't AlwaysOnTop)
		bolt = { seconds = 0.13, size = 0.55, clickSize = 0.9, trail = 0.14 },
		wobble = { squash = 0.12, seconds = 0.28, shatterSeconds = 0.5 },
		turnSpeed = 10,
	},
	-- touchLift: how far the coins sit above the bottom on touch screens. Owner 2026-11-15: "put the coins under the
	-- joystick": 0, they stay in the bottom-left corner under the thumbstick (they're text only, touches pass through)
	topInset = 0.02, sideInset = 0.03, touchLift = 0,
	stickClear = 0.36, -- touch: the menu tiles stay this far (share of the short side) above the bottom, clear of the thumbstick
	-- the island banner (owner 2026-11-07, from a reference clip): walking onto an island drops a strip
	-- in from above the top edge, top centre: the island's name in its colour, the thermometer and its
	-- feel + degrees, then "Recommended: <gun>". It holds, then fades up and out. A dark see-through
	-- strip with soft ends, no box. Sizes: shares of the screen's short side; times in seconds
	-- (reduced motion halves them and drops the slide). nameRow / infoRow: shares of the strip's height.
	islandBanner = {
		width = 1.25, height = 0.15, nameRow = 0.56, infoRow = 0.36, iconSize = 0.9,
		stripTransparency = 0.45, stripEnds = 0.22, -- the strip fades to clear over this share at each end
		drop = 1.25, inSeconds = 0.34, holdSeconds = 2.8, outSeconds = 0.24, rise = 0.25, -- drop/rise: strip heights
		textStroke = 2.5, repeatAfter = 6, -- the same island again within this many seconds doesn't re-show
	},
	-- these menus hide the HUD (tiles, coins, island banner, hotbar) and the world prompts while open,
	-- so the shop is the only thing on screen (owner 2026-11-05); the banner still shows answers
	hideHudFor = { shop = true, equipment = true, index = true, sell = true, rebirth = true, tester = true } :: { [string]: boolean },
	-- the big popups (Equipment, Index, Sell, Rebirth: owner 2026-11-09 "make it bigger"), share of the screen and aspect
	bigPopups = { equipment = true, index = true, sell = true, rebirth = true, shop = true, tester = true } :: { [string]: boolean }, -- shop v2: its cards were 85 px wide in a phone-sized window (2026-11-11); it hides the HUD, so the wide panel is safe
	popupSizeBig = { 0.9, 0.86 }, popupAspectBig = 1.68,
	barTrackAlpha = 0.2, -- progress bars: the light track behind the fill
	-- the Index (2026-11-09): pageAspect = a page card's width / height; shares of the card below
	index = { pageAspect = 4, headHeight = 0.3, slotTop = 0.05, slotInset = 0.012, slotGap = 0.012,
		totalHeight = 0.13, totalGap = 0.02, badgeFaint = 0.6 },
	popupSize = { 0.8, 0.7 }, popupLift = 0.04, promptSize = { 0.27, 0.095 }, -- world prompts keep this screen size at any distance (owner: smaller)
	bannerSeconds = 3, floatSeconds = 1.2, notYetSeconds = 1.6,
	-- alerts (owner 2026-11-16: "I don't like the alerts UI ... put it under Equipment and Pan"): small toasts that
	-- slide down under the top buttons, an icon chip on the left, at most `stack` at once (the oldest goes first).
	-- size = a toast's width and height (shares of the screen's short side); gap between toasts
	-- phoneWidth: a share of the screen's width (between the tiles and the clocks); phoneScale: every height x this
	alerts = { stack = 3, size = { 0.62, 0.075 }, phoneWidth = 0.6, phoneScale = 1.45, gap = 0.012, slideSeconds = 0.22, outSeconds = 0.18 },
	-- the gain banner at the top (owner 2026-11-16, from the speed-game reference): "+N" Cold Power in a bright
	-- box with rays behind it, pulsing while you keep training; sums gains for sumSeconds
	gainBanner = { size = { 0.36, 0.085 }, y = 0.012, sumSeconds = 1.6, holdSeconds = 1.2, pulse = 1.08 },
	-- the clocks bottom right (night, Secret, event): "in 1m 41s" chips, like the reference
	clocks = { size = { 0.3, 0.06 }, gap = 0.01, phoneScale = 1.4 },
	-- the "+17.5K" beside the coin counter: shares of the coins block; a size under the number (0.62 tall)
	gain = { height = 0.46, width = 1.2, y = 0.08, gap = 0.04, rise = 0.55, popSeconds = 0.25, holdSeconds = 0.45 },
	pressDepth = 0.06, pressSeconds = 0.08, stroke = 3, corner = 0.18,
	radius = 0.018, -- THE corner radius for every block, as a share of the screen's short side
	textStroke = 1.5, -- white text's outline (2 plus the block outline read heavy)
	floatingStroke = 2.5, -- text with no block behind it (the coin counter) needs a firmer outline
	cardStroke = 2, -- the thin outline round a list card
	panelTint = 0.86, -- a popup body is its menu colour this far toward white, so body and ribbon match
	promptHoldFill = 0.25, -- the ice sweep that fills a world prompt while you hold (transparency; 0.55 inside the faded pill was invisible, owner 2026-11-12)
	promptFade = 0.2, -- a world prompt's dark pill is this see-through so the pet under it shows (its words and key stay solid)
	-- the prompt's keycap: as tall as the prompt, it sits over the pill's left end and taps itself down every
	-- keyTap seconds (a "press me" hint; none with reduced motion)
	promptKey = { tapEvery = 1.6, down = 0.07, up = 0.14 },
	-- studs from the prompt's attachment (3 over the ground at booths, gates, the Thaw Machine) up to over
	-- your head: prompts are depth-tested now (PromptController), so at chest height your own body covered
	-- them (2026-11-12). Was -0.6, from when pets had prompts
	promptLift = 2.6,
	-- a "Compact" prompt (the Pick up on a frozen pet's small cube): this much smaller, and resting on
	-- top of its object instead of over it, so the pet inside stays in view (owner 2026-11-07). Nothing
	-- is under it, so it's solid (not promptFade), and its outlines shrink with it (UI Rules: after
	-- scaling, recheck outline weight)
	promptCompact = 0.7,
	lipDepth = 0.012, -- every block's lip is this share of the screen's short side, so a big panel gets the same thin lip as a tile
	-- popup text sizes as shares of the popup's height: one size per role, so rows never jump in size
	popupText = { title = 0.075, body = 0.052, small = 0.04, button = 0.05 },
	headerHeight = 0.13, -- the coloured title ribbon at the top of a popup
	listInset = 0.015, -- scrolling lists keep this gap on every side so outlines and lips aren't clipped
	-- a block face's dressing (Ui.block): white wash at the top, a shade toward the lip, a bevel line (transparencies)
	face = { topLight = 0.75, bottomShade = 0.82, rimInset = 0.035, rimThickness = 2, rimTop = 0.35 },
	-- the tutorial's goal pill, top centre (shares of the short side): icon tile, goal words, a count bar on
	-- counted steps, step dots under it, Skip at the right end
	tutorialGoal = { wide = { 0.8, 0.12 }, phone = { 1.2, 0.16 }, dots = 0.022 },
	settingsRow = 0.128, -- a Settings row's height (share of the list): 7 rows and their gaps fit
	gamepadKeys = { close = Enum.KeyCode.ButtonB, superFreeze = Enum.KeyCode.ButtonY, menu = Enum.KeyCode.ButtonSelect, skip = Enum.KeyCode.ButtonA },
	keys = { pets = Enum.KeyCode.P, shop = Enum.KeyCode.B, index = Enum.KeyCode.I, close = Enum.KeyCode.Backspace, superFreeze = Enum.KeyCode.F, tester = Enum.KeyCode.T, skip = Enum.KeyCode.Return }, -- Escape belongs to Roblox's own menu,
	testerTile = { id = "tester", label = "Tester" }, -- only testers see it
	-- the top buttons (owner 2026-11-12, from a reference: chunky labelled blocks across the top centre).
	-- Each takes you somewhere in the hub (TravelService). They go away while a cube is in your hands and
	-- come back once you've reached your pan with empty hands, and step aside while a popup is open.
	-- size = one button (shares of the screen's short side; never under minTouchPx tall on touch), gap
	-- between them; at = where you land (Vector3 in the world, or "pan" = in front of your own pan's door,
	-- panFront studs out onto the plaza); face = where you look on arrival; cooldown = seconds (server)
	-- "you can now buy" alerts (owner 2026-11-12, from a reference): a card slides in at the top right the
	-- first time this session you have the coins for your next gun. size = shares of the short side;
	-- seconds = how long it stays; slide = its slide-in time
	unlockAlert = { size = { 0.66, 0.26 }, phoneScale = 1.3, seconds = 10, slide = 0.35 },
	topButtons = {
		list = {
			{ id = "equipment", label = "EQUIPMENT", icon = "ray" },
			{ id = "pan", label = "PAN", icon = "pen" },
		},
		-- owner 2026-11-13 "make them bigger": 1.3x (was size { 0.34, 0.1 } and 76% of the top bar's height).
		-- barFill = their height as a share of Roblox's top bar (over 1 = they hang below it); barTop = their
		-- top edge down the bar (share of its height), level with Roblox's own buttons
		-- barShort = the most they take of the screen's short side (laptops: 1.3x the bar was too big on a
		-- ~650 px tall window); barMin = never smaller than this share of the bar (the old size)
		size = { 0.44, 0.13 }, gap = 0.03, iconSize = 0.86, barFill = 1.3, barTop = 0.12, barShort = 0.085, barMin = 0.76,
		equipment = { at = Vector3.new(80, 3, -19), face = Vector3.new(80, 3, -8) },
		panFront = 7,
		cooldown = 2,
	},
}

-- Text out in the world (Shared/WorldText). Sizes in studs on signs; pet tags and the gift label are
-- pixel-sized pills (the same size on screen at any distance) that only show up close.
Config.worldText = {
	pixelsPerStud = 100, -- 40 rendered soft and blurry up close
	lightInfluence = 0, -- signs stay bright at night and in shade
	outlineRatio = 0.08, -- outline thickness = text size x this
	signPadding = 0.06,
	-- leaderboards (14 x 18 studs). Text sizes in studs; pixelsPerStud is lower than signs' 100 so the
	-- 1.3-stud title stays under Roblox's 100 px text cap. Layout = shares of the board: pad (sides /
	-- top), header height, the "updates" line under it, row height and gap; lip = share of a block's height,
	-- strokePx / rimPx in pixels. The bottom stays clear: the flower bed in front covers it.
	board = {
		pixelsPerStud = 70,
		text = { title = 1.3, subtitle = 0.55, row = 0.6, rank = 0.58, note = 0.42 },
		padX = 0.035, padY = 0.022, header = 0.15, note = 0.045, row = 0.064, rowGap = 0.0085,
		lip = 0.1, strokePx = 4, rimPx = 8, iconScale = 1.18, emptyFade = 0.6,
	},
	gate = 1.9, -- the gate signs (biggest size; long names shrink to fit)
	tag = { textPx = 19, heightPx = 32, padPx = 22, maxDistance = 45, offset = 0.9 }, -- pet name pills (45: the camera sits ~30 studs back)
	gift = { textPx = 24, heightPx = 44, padPx = 30, maxDistance = 80 },
}

-- owner 2026-11-09: "brighter colours" and a real sky (World Rules > Sky). The skybox is a painted
-- cartoon sky (six images from Creator Store asset 118356786274870 by nov4_gg2010; its scripts were thrown
-- away, only the image ids are used). Clouds are Roblox's own, white and soft.
Config.lighting = {
	clockTime = 14,
	brightness = 2.2,
	atmosphereDensity = 0.14, -- owner 2026-11-13 "brighter, more striking": less haze (was 0.22), so the far decor reads crisp
	atmosphereOffset = 0.1,
	atmosphereDecay = Color3.fromHex("8fd8ff"), -- far haze fades to sky cyan, not grey
	saturation = 0.35, -- was 0.2 (owner 2026-11-13: candy-bright like the big simulator games)
	contrast = 0.1, -- was 0.05
	sky = {
		bk = "rbxassetid://6295671271", dn = "rbxassetid://6295671382", ft = "rbxassetid://6295671136",
		lf = "rbxassetid://6295670996", rt = "rbxassetid://6295671509", up = "rbxassetid://6295671667",
		sunSize = 12,
	},
	clouds = { cover = 0.5, density = 0.55, color = Color3.fromRGB(255, 255, 255) },
	-- owner 2026-11-13: the last islands leave the blue day behind for a starry space sky.
	-- MapController swaps the skybox on your own screen when you walk into an island listed in
	-- zoneSky (by theme), behind a quick white flash (flashUp / flashDown seconds, flash = extra
	-- ColorCorrection brightness; no flash with reduced motion), and swaps back when you leave.
	-- The space images come from Creator Store asset 138820118883293 ("Purple Space Sky"); only
	-- the image ids are used, the model itself was thrown away (it carried a hidden script).
	zoneSky = { lavalake = "space", magma = "space" },
	skies = {
		space = {
			bk = "rbxassetid://14543264135", dn = "rbxassetid://14543358958", ft = "rbxassetid://14543257810",
			lf = "rbxassetid://14543275895", rt = "rbxassetid://14543280890", up = "rbxassetid://14543371676",
			sun = false, cloudCover = 0, decay = Color3.fromHex("6a3cff"),
		},
	},
	skyFlash = { flash = 0.35, flashUp = 0.2, flashDown = 0.45 },
}

-- World layout in studs (Round 4 phase 2: a row of pans and the tunnel). The hub is north (-Z): a
-- safe spawn plaza with one fenced pan per server slot side by side in one row. One straight walled
-- tunnel leaves the hub's mouth (z = 0) and runs south (+Z) through every open island in order, one
-- section per entry in `islands`, then ends in a "New island coming soon" cap. A new island is one
-- new entry (plus its art and pets); room is left for 20 sections (about 3,400 studs of tunnel).
export type Island = {
	key: string, name: string, open: boolean, theme: string,
	length: number?, heat: number?, need: number?,
	ready: boolean?, iceLife: number?, lava: { count: number, r: { number } }?, -- Round 4 phase 6
	landmark: string?, landmarkAt: { x: number, z: number }?, -- z is measured from the section's start
	landmarkScale: number?, -- this island's landmark size, if not Config.art.landmarkScale (map pass 2026-11-10)
	trees: { kind: string, count: number, r: { number } }?, sun: { count: number, r: { number } }?,
	near: { number }?, farFrom: number?, -- spawn bands, measured from the section's start
	feel: string?, -- the island banner's heat word (Round 4 Prompt 6: "cold", "mild", "lava"...)
}
export type Booth = { id: string, label: string, action: string, pos: Vector3, sign: { y: number, z: number }? }
-- one cue in a shot clip (Config.ray.anim): at a share of the clip, a sound, an effect and/or a camera kick
export type RayCue = { at: number, sound: string?, fx: string?, kick: string? }

Config.world = {
	maxPlayers = 6, -- one pan per server slot. Owner item: Server Size 6 in Game Settings > Places
	mapVersion = 27, -- 27 = the fall catcher in tiles, so the hub and the end of Magma Core are covered too (QA IR-05), 26 = at most 3 lava pools per island, each in its own stretch (owner 2026-11-13), 25 = vivid colours and the giant outside decor per island (MapSpectacle, owner 2026-11-13), 24 = solid scenery (MapArt.solidify: everything you can see blocks you), 23 = smaller outside (MapArt farScenery: ground and peaks only as big as the camera needs), 22 = pan fence walls only fence-high, so you can jump them, 21 = solid pan fences (invisible PanFence walls; the gate is the only way in), 20 = Cold Power trainers in every pan (TrainingService builds them; the rink door, its beacon and the right flower box are gone, Equipment back by the tunnel mouth), 19 = open plaza: no fountain, no paved boulevard, no spawn pad, 18 = the Sell and Equipment booths no longer run into the village wall, 17 = map pass 2026-11-10 (rink door in front, its beacon, bigger snowman and waterfall), 16 = the Training Rink's door. Workspace.Map carries this; an older saved map is rebuilt (3 = Round 5 map remake, 4 = 10 islands, 5 = clear centre / rich edges, 6 = bigger square pans, 7 = pans measured against the real avatar, 8 = open gaps, open ground behind, level pans, 9 = no flush overlapping surfaces, 10 = booth details: sign bulbs, log ends, scalloped awnings, chalk coin, 11 = wide tunnel and big entrance for big pets, a clean road, 12 = booths shaped like what they do: treasure chest, gear workshop, ring portal, 13 = the detailed sci-fi Thaw Machine, 14 = each world's own gate towers, 15 = never-visible buried parts left out (PERF-AUDIT-2026-11-09))
	hubZMax = 0, -- the tunnel mouth: the hub is z < 0 (no wild pets, no heat)
	-- wide enough for the row of six pans plus 10 studs at each end; zMin is worked out below (behind the pans' backSpace)
	hub = { xMin = -150, xMax = 150, zMin = 0, wallHeight = 16, colliderHeight = 60 },
	spawn = Vector3.new(0, 3, -34),
	spawnPadRadius = 6,
	-- owner 2026-11-15: "spawn you in front of your pan": studs out from the pan's hub-side edge, facing it
	panSpawnFront = 6,
	-- the pans: fenced gardens a little deeper than wide, level with the ground round them, doors facing
	-- the plaza, open walkable ground between them and backSpace of open ground behind them.
	-- Sizes follow the owner's reference shots (2026-11-05), measured against the real avatar (5.8 studs
	-- tall, 3.3 across the arms) and the reference's 4-stud floor tiles: width about 7 avatar heights,
	-- depth 1.1 x width, door 0.4 x width, gap 0.2 x width, about one width of open ground behind,
	-- fence about shoulder high (0.8 avatar heights)
	pans = { width = 40, length = 44, gap = 8, frontZ = -62, soilHeight = 0.2, backSpace = 40, doorWidth = 16, fenceHeight = 4.5, wallHeight = 5.2, -- wallHeight: the fences' invisible walls, as tall as the fence (top 4.7 + caps): you can't walk through, but a jump clears it
		signY = 6.5, gaugeOffset = -16.5, boothOffset = -11 }, -- the gauge and the Pan Upgrades stand left of the door (x from the lane's middle); right of it stands the Cold Power trainer (Config.training.spot)
	-- owner 2026-11-07: bigger pets are coming, so the tunnel is wide (about 34 avatar widths, was 22)
	-- and the entrance and the island gates are scaled up with it (archScale: their towers, roofs and
	-- lintels). The road is one plain strip: no lamps or stones on it; the lanterns stand at the foot of
	-- the cliffs, one every lampEvery studs
	tunnel = { width = 112, wallHeight = 24, wallThick = 4, colliderHeight = 60, pathWidth = 24, lampEvery = 56, archScale = 1.5 },
	gate = { depth = 3, barGap = 4, height = 20 },
	endCap = { depth = 4, height = 24, glowDepth = 30 },
	-- Round 4 phase 6: 10 islands at launch, room for 20. You freeze pets in hotter and hotter places.
	-- open  = built into the tunnel (a section, gate, sign and tester teleport). An entry with open = false
	--         isn't built: the first one only tints the end cap ("New island coming soon").
	-- ready = its pets are approved and finished. An island that isn't ready stays behind a glowing
	--         "Coming soon" gate and has no wild pets (never placeholder pets). Owner 2026-11-10: every
	--         island ready for now, its unfinished pets shown as stand-ins ("implement every pet in the game").
	-- heat  = how fast a carried cube melts while you're on this island (x shade / sun / lava, Config.melt).
	-- iceLife = its pets' cubes last this many times longer, so the trip home still works from far out.
	-- gateCoins + rebirthGates (below) = what opening its gate costs. Prices tuned in phase 7 with the playtest bot (ServerStorage.GrindBot): even islands to the time table, odd islands 3x the gate before.
	-- Retuned 2026-11-05 for the 16-slot pan and no coin Shop upgrades: gates from island 4, coin guns 4+, pan Looks
	-- and Cold Level (it follows the gates) x0.2; Rebirth 1 520K -> 150K; island 2 2,500 -> 5,000. GrindBot: everything in ~6.9 h typical.
	-- Repriced 2026-11-07 (owner: round prices, a long smooth game): every gate a round number (Config.nice),
	-- island 10 3B (was a 13x jump over island 9, now 4x). GrindBot: everything in ~7.2 h typical, see Config.rebirth.
	-- Hazards: sun patches (sun) and lava pools (lava) melt cubes faster and glow so you see them from far.
	-- Owner 2026-11-13: sun patches only on the two sunny islands (Sunny Beach, Desert Dunes), drawn in
	-- more detail there (MapArt hazards); every other island lost its `sun` entry.
	-- Owner 2026-11-13: "make later islands longer". From Jungle Falls on each island is longer than the
	-- one before (176 -> 210 ... 320 studs; about 30 s more walking to the end), with its trees, sun
	-- patches, lava and landmark spot scaled to match. Cube life follows on its own (Config.cubeLife
	-- measures the real walk home).
	islands = {
		{ key = "meadow", name = "Snowy Meadow", feel = "Cold", open = true, ready = true, theme = "meadow", length = 168, heat = 0.5, iceLife = 1, need = 0,
			landmark = "snowman", landmarkAt = { x = 66, z = 112 }, landmarkScale = 2.6, -- map pass 2026-11-10: the first landmark a new player sees, now well over the cliffs -- landmarks stand in the cliffs, tall enough to show over them (World Rules 9)
			trees = { kind = "snowpine", count = 14, r = { 4, 6.5 } },
			near = { 8, 34 }, farFrom = 60 },
		{ key = "forest", name = "Pine Forest", feel = "Cold", open = true, ready = true, theme = "forest", length = 176, heat = 0.8, iceLife = 1, need = 150, -- 150 (owner 2026-11-16: the tutorial's 500 took too long)
			landmark = "mushroom", landmarkAt = { x = -66, z = 104 },
			trees = { kind = "pine", count = 34, r = { 4.5, 7.5 } },
			near = { 10, 42 }, farFrom = 10 },
		{ key = "grove", name = "Mushroom Grove", feel = "Mild", open = true, ready = true, theme = "grove", length = 172, heat = 1.0, iceLife = 1.6, need = 1e3,
			landmark = "toadstoolTower", landmarkAt = { x = 66, z = 100 },
			trees = { kind = "toadstool", count = 22, r = { 4, 7 } },
			near = { 10, 40 }, farFrom = 12 },
		{ key = "beach", name = "Sunny Beach", feel = "Warm", open = true, ready = true, theme = "beach", length = 172, heat = 1.3, iceLife = 2.4, need = 300e3,
			landmark = "lighthouse", landmarkAt = { x = -66, z = 104 },
			trees = { kind = "palm", count = 14, r = { 4, 6 } }, sun = { count = 7, r = { 7, 11 } },
			near = { 10, 40 }, farFrom = 12 },
		{ key = "jungle", name = "Jungle Falls", feel = "Hot and humid", open = true, ready = true, theme = "jungle", length = 210, heat = 1.6, iceLife = 3.3, need = 4e6,
			landmark = "waterfall", landmarkAt = { x = 56, z = 130 }, landmarkScale = 2.3, -- map pass 2026-11-10: it hid behind the jungle trees -- pours from the cliff face
			trees = { kind = "jungle", count = 33, r = { 4.5, 7.5 } },
			near = { 10, 42 }, farFrom = 12 },
		{ key = "desert", name = "Desert Dunes", feel = "Hot", open = true, ready = true, theme = "desert", length = 230, heat = 2.0, iceLife = 4.4, need = 75e6,
			landmark = "cactus", landmarkAt = { x = -66, z = 136 },
			trees = { kind = "cactus", count = 12, r = { 3.5, 5 } }, sun = { count = 12, r = { 8, 12 } },
			near = { 10, 42 }, farFrom = 12 },
		{ key = "canyon", name = "Canyon Mesa", feel = "Very hot", open = true, ready = true, theme = "canyon", length = 250, heat = 2.4, iceLife = 5.7, need = 250e6,
			landmark = "arch", landmarkAt = { x = 0, z = 155 },
			trees = { kind = "hoodoo", count = 14, r = { 4, 6 } },
			near = { 10, 42 }, farFrom = 12 },
		{ key = "volcano", name = "Volcano Slopes", feel = "Lava", open = true, ready = true, theme = "volcano", length = 270, heat = 2.9, iceLife = 7.2, need = 15e9,
			landmark = "volcano", landmarkAt = { x = 70, z = 160 }, -- beside the tunnel, rising over the cliffs
			trees = { kind = "charred", count = 12, r = { 4, 6 } }, lava = { count = 3, r = { 5, 8 } },
			near = { 10, 42 }, farFrom = 12 },
		{ key = "lavalake", name = "Lava Lake", feel = "Lava", open = true, ready = true, theme = "lavalake", length = 290, heat = 3.4, iceLife = 9, need = 150e9,
			landmark = "spire", landmarkAt = { x = -66, z = 176 },
			trees = { kind = "obsidian", count = 13, r = { 4, 6 } }, lava = { count = 3, r = { 6, 10 } },
			near = { 10, 42 }, farFrom = 12 },
		{ key = "magma", name = "Magma Core", feel = "Extreme", open = true, ready = true, theme = "magma", length = 320, heat = 4.0, iceLife = 11, need = 4e12,
			landmark = "core", landmarkAt = { x = 0, z = 200 },
			trees = { kind = "obsidian", count = 12, r = { 4, 6 } }, lava = { count = 3, r = { 5, 9 } },
			near = { 10, 42 }, farFrom = 12 },
		-- Balance pass 2026-11-12 (prototype/ice-ray-for-pets/BALANCE-2026-11-12.md, balance_sim.py): needs
		-- 500 / 20K / 300K / 600K / 40M / 150M / 7.5B / 15B / 2T with training.levelValue 4.
		-- Pacing pass 2026-11-16 (PACING-2026-11-16.md): 150 / 5K / 300K / 4M / 75M / 150M / 15B / 200B / 4T;
		-- rarity pass 2026-11-17: 150 / 1K / 300K / 4M / 75M / 250M / 15B / 150B / 4T. The islands behind
		-- a rebirth gate (3, 5, 7, 9) need about 2x the island before, so they open soon after their rebirth;
		-- 4, 6, 8 and 10 are the real Cold Power goals. Typical kid: island 2 at 4.7 min, island 10 at 6.4 h.
		-- the next update (not built): its colour glows behind the end cap. Later updates add islands 11-20
		-- past extreme heat into the sky and space (Sun Temple, Solar Flare Fields, Starfall Sky, Comet
		-- Drift, Moon Base, Nebula Reef): one entry each, plus its Theme look and pets.
		{ key = "suntemple", name = "Sun Temple", open = false, theme = "suntemple" },
	} :: { Island },
	-- rebirths needed to open an island's gate (island number -> rebirths). A rebirth gate on every odd
	-- island from 3, the gaps widening; updates add 11 = 9, 13 = 12, 15 = 15, 17 = 18, 19 = 21.
	rebirthGates = { [3] = 1, [5] = 2, [7] = 4, [9] = 6 } :: { [number]: number },
	-- booths by the tunnel mouth, in front of the hub's south wall, facing the plaza. Their features
	-- come in phases (Equipment phase 4, Sell + Pan Upgrades phase 5, Rebirth phase 7); action = what the
	-- prompt does ("equipment" opens the Equipment Booth, "shop" the Shop, "soon" says it's coming).
	-- The client reads the action from here, so a saved map's prompts follow a change.
	booths = {
		-- Booth v4 (owner 2026-11-07): each booth is a giant version of what it does (MapArt), about 17 wide,
		-- clear of the tunnel towers. label = the action only, no "Booth" (the sign and the prompt show it).
		-- sign = where its sign stands (y up, z toward the plaza, from pos): over the chest's window, over
		-- the workshop's opening, on the portal's keystone
		{ id = "sell", label = "Sell", action = "sell", pos = Vector3.new(-80, 0, -8), sign = { y = 8.6, z = -3.55 } },
		-- 2026-11-10: the Training Rink door is gone (Cold Power is trained in the Frost Training Yard,
		-- Config.training), so Equipment is back in the front-row spot by the tunnel mouth
		{ id = "equipment", label = "Equipment", action = "equipment", pos = Vector3.new(80, 0, -8), sign = { y = 9, z = -3.3 } },
		{ id = "rebirth", label = "Rebirth", action = "rebirth", pos = Vector3.new(-103, 0, -8), sign = { y = 14.6, z = 3.9 } },
	} :: { Booth },
	boothSign = { y = 8.8, w = 9, h = 2.2, z = -3.2, text = 1.5 }, -- a booth sign's size (text = letter height in studs); y / z are the spot for a booth without its own `sign`
	panUpgradeAction = "pan", -- the Pan Upgrades popup (Round 4 phase 5)
	giftBox = Vector3.new(106, 0, -10), -- the outer slot, past Equipment
	-- leaderboards on the hub's side walls, turned to face the plaza
	-- owner 2026-11-15: "move the leaderboards here": side by side on the back wall, between the Rebirth
	-- portal and the west wall, facing the pans (boardFacing)
	boards = { Vector3.new(-139.6, 0, -2), Vector3.new(-120.4, 0, -2) },
	boardFacing = Vector3.new(0, 0, -1),
	-- filled in below from the lists above
	zones = {} :: { Zone },
	plots = {} :: { { x: number, z: number } },
	penSize = Vector3.zero,
	bounds = { xMin = 0, xMax = 0, zMin = 0, zMax = 0 },
	tunnelEnd = 0,
	nextIsland = nil :: Island?,
	readyCount = 0, -- islands 1..readyCount have their pets (filled in below)
}

do
	local W = Config.world
	-- the pans, side by side in one row, centred on the hub
	local P = W.pans
	local row = W.maxPlayers * P.width + (W.maxPlayers - 1) * P.gap
	for i = 1, W.maxPlayers do
		table.insert(W.plots, { x = -row / 2 + P.width / 2 + (i - 1) * (P.width + P.gap), z = P.frontZ - P.length / 2 })
	end
	W.penSize = Vector3.new(P.width, 1, P.length)
	W.hub.zMin = P.frontZ - P.length - P.backSpace
	-- the tunnel's sections: one per open island, end to end from the mouth
	local z = W.hubZMax
	for _, isl in W.islands do
		if not isl.open then
			W.nextIsland = W.nextIsland or isl
			continue
		end
		local id = #W.zones + 1
		local len = isl.length :: number
		table.insert(W.zones, {
			id = id, key = isl.key, name = isl.name, heat = isl.heat :: number, zMin = z, zMax = z + len,
			need = isl.need or 0,
			theme = isl.theme, ready = isl.ready == true, gateRebirth = W.rebirthGates[id] or 0, iceLife = isl.iceLife or 1,
			feel = isl.feel or "",
		})
		if isl.ready == true and W.readyCount == id - 1 then
			W.readyCount = id
		end
		local near = isl.near or { 8, 34 }
		Config.spawner.near[id] = { z + near[1], z + near[2] }
		Config.spawner.farZMin[id] = z + (isl.farFrom or 10)
		z += len
	end
	W.tunnelEnd = z
	local half = W.tunnel.width / 2
	W.bounds = { xMin = -half, xMax = half, zMin = W.hub.zMin, zMax = z }
end

-- Uploaded images (the prototype's painted icons and pet sprites, roblox/assets/images)
Config.images = {
	icons = {
		coin = "rbxassetid://114690725766316", bag = "rbxassetid://76257814527627", book = "rbxassetid://103706811541834",
		gear = "rbxassetid://84856334538368", gift = "rbxassetid://86444394737076", trophy = "rbxassetid://99838454157287",
		-- 2026-10-31 batch (prototype/ice-ray-for-pets/icons, cleaned with tools/icon_cleanup.ps1)
		ray = "rbxassetid://139931668460856", boots = "rbxassetid://82792097425872", pen = "rbxassetid://92747015965127",
		music = "rbxassetid://110832713318779", sound = "rbxassetid://117928774777865", motion = "rbxassetid://87612144122340",
		graphics = "rbxassetid://136668522918870", temp = "rbxassetid://72963487370215",
		paint = "rbxassetid://133624884100688", -- 2026-11-03: the Pan Upgrades Look card (icons/paint.png)
		star = "rbxassetid://124754707375216", -- 2026-11-10: the Shop's Forever tab (starter-kit/icons/ai/star.png)
		-- 2026-11-12 (icons/gate.png, icons/lock.png): the Rebirth popup's gates, and the lock on a gun you don't own
		gate = "rbxassetid://125059317907976", lock = "rbxassetid://80262628352180", -- lock re-cut 2026-11-12: the shackle's hole was painted solid grey (owner: "a grey thing behind it")
		-- Cold Power. STAND-IN: the thermometer, until the painted snowflake crystal is made (owner's OK on Figma credits first)
		power = "rbxassetid://72963487370215",
		robux = "rbxasset://textures/ui/common/robux.png", -- Roblox's own Robux mark, on every Robux price
		-- 2026-11-12, drawn (icons/arrow.png, icons/sunburst.png): the chunky go-green arrow (Rebirth banner and show)
		-- and a soft white sunburst, tinted with ImageColor3 behind reveals
		arrow = "rbxassetid://110202146195386", sunburst = "rbxassetid://78560668257766",
		-- owner 2026-11-15: a painted Chunky Pop thumbs-up for the Free Gift's "Like" step (was Roblox's flat one)
		like = "rbxassetid://119807405342526",
		-- owner 2026-11-15: the Shop tile is a red basket full of goodies (their reference picture)
		basket = "rbxassetid://104654565423481",
		-- owner 2026-11-15: the Thaw Speed card shows the Thaw Machine, not a thermometer (icons/thaw.png)
		thaw = "rbxassetid://73836085521963",
	} :: { [string]: string },
	-- pets with no 3D model yet are drawn as these painted sprites, facing the camera (prototype)
	pets = {
		snowbun = "rbxassetid://92428027252754", waddles = "rbxassetid://85819786009594", mittenkit = "rbxassetid://80224010045349",
		pupcicle = "rbxassetid://99464046375243", frostfox = "rbxassetid://75892873565699", blizzard_yeti = "rbxassetid://93201949480148",
		aurora_owl = "rbxassetid://82434091513318", snowglobe_drake = "rbxassetid://118494815244289", conehog = "rbxassetid://73502496724119",
		hopsprout = "rbxassetid://95878437320181", capmouse = "rbxassetid://107833749569236", mossfawn = "rbxassetid://117305047075010",
		lanternbug = "rbxassetid://74192529771490", mapleguard_bear = "rbxassetid://75624001245030", bloomhorn_stag = "rbxassetid://81929702575504",
		glowshroom_mammoth = "rbxassetid://88722165161459",
		-- Mushroom Grove (island 3)
		toddle = "rbxassetid://117747190893131", puffball = "rbxassetid://134110767591106", trufflet = "rbxassetid://123445413435843",
		glimmermoth = "rbxassetid://82844804865391", shimmerfrog = "rbxassetid://81305476693408", capcrown_badger = "rbxassetid://108878977839888",
		sporewing_drake = "rbxassetid://90224936160282", myco_golem = "rbxassetid://119241536493295",
	} :: { [string]: string },
}

Config.ui.tileIcons = { pets = Config.images.pets.snowbun, shop = Config.images.icons.basket, index = Config.images.icons.book, settings = Config.images.icons.gear,
	daily = Config.images.icons.trophy }
-- painted icons on the Shop and Settings rows
local I = Config.images.icons
Config.ui.upgradeIcons = { ray = I.ray, boots = I.boots, backpack = I.bag, pen = I.pen } :: { [string]: string }
Config.ui.settingIcons = { music = I.music, sound = I.sound, reducedMotion = I.motion, lowGraphics = I.graphics, unit = I.temp } :: { [string]: string }
Config.ui.silhouetteTransparency = 0
Config.ui.shopPerRow = 5 -- the Robux shop's product tiles to a row
-- shop v2 (2026-11-10): the tab rail's width (share of the body), the card row's top, a card's widest share,
-- how much bigger the Best Value card is, and the bonus sticker's step (a "+47%" shows as "+45%": never more than true)
-- 2026-11-12: one scrolling page. A row's height comes from its width: headAspect = a section title,
-- bannerAspect = a Forever pass, cardsAspect = a row of pack cards. jumpSeconds = a tab's scroll to its
-- section; markLine = how far down the view a title must come for its tab to light (share of the view)
Config.ui.shop = { rail = 0.19, gap = 0.035, cardMax = 0.3, bestGrow = 1.07, bonusStep = 0.05, bigText = 1.5,
	-- round 2: full width without the rail, so rows got wider shapes (banners 4.6 -> 6.2, card rows 1.9 -> 2.4, titles 7 -> 9)
	bannerAspect = 6.2, cardsAspect = 2.4, jumpSeconds = 0.25, markLine = 0.35,
	-- the frame (2026-11-12): snowflakes drifting in the well (fewer on Low graphics, none with Reduced
	-- motion), snow caps along the title bar, a sunburst behind every product picture
	-- snowCaps: where the drifts sit along the title bar (shares of its width), clear of the title and the X
	flakes = 16, flakeSeconds = { 7, 12 }, snowCaps = {} :: { number }, sunAlpha = 0.45, -- snowCaps: none since round 2 (they read as white blobs over the title icon)
	-- round 2 (owner 2026-11-12: "improve the shop, look at the references"): no tab rail (one full-width page),
	-- faint diagonal stripes on the frame and title bar, the title left with its icon big and tilted over the
	-- corner, a coin pill on the right of the title bar, section titles as plain words with an icon each side,
	-- and island pets peeking over the bottom corners. Sizes are shares of the panel / title bar height.
	showRail = false, stripes = "rbxassetid://74630162488270", stripePx = 64, stripeAlpha = 0.9, titleStripeAlpha = 0.86,
	titleIcon = 1.75, titleIconTilt = -12, coinPill = { x = 0.6, w = 0.25, h = 0.62 },
	-- mascots sit mostly outside the frame's bottom corners, so they never cover a Buy button
	mascots = {} :: { { pet: string, x: number, y: number, size: number, tilt: number } }, -- owner 2026-11-12: penguin and bunny removed
	-- round 3 (owner 2026-11-13: "the shop still needs improvements", the reference clips): slim section
	-- titles (headAspect) with their line in a thin row of its own (subAspect); everything but coin packs
	-- as landscape tiles two a row (tileRowAspect = the row's width / height, tileGap between them,
	-- tileTop = room above for the stickers); an odd product out leads as a full-width banner.
	headIcon = 0.9, headAspect = 16, subAspect = 34, tileRowAspect = 4.4, tileGap = 0.025, tileTop = 0.1, stickerRoom = 0.16,
	tileRowAspectTouch = 3.3, cardsAspectTouch = 1.85, -- taller on phones (thumb-sized Buy buttons)
	-- where things sit on a tile, { x, y, w, h } shares of it: title across the top, picture bottom-left,
	-- chip (or bar) and the buy button bottom-right
	tile = { title = { 0.04, 0.06, 0.92, 0.25 }, icon = { 0.03, 0.33, 0.31, 0.62 }, chip = { 0.37, 0.35, 0.59, 0.17 }, buy = { 0.37, 0.56, 0.59, 0.37 } },
	wideTile = { title = { 0.2, 0.1, 0.52, 0.42 }, icon = { 0.03, 0.08, 0.14, 0.84 }, chip = { 0.25, 0.56, 0.42, 0.32 }, buy = { 0.745, 0.2, 0.235, 0.6 } },
	-- each card's little world: a pale moon (x, y, size as a share of the card's short side), dark hills far
	-- off and snowy ground in front, both mixed from the card's colour (toward ink or white by `amount`;
	-- dark-on-dark hills vanished into the card's own bottom shade); at = { x, width, height }
	cardStripeAlpha = 0.9,
	-- owner 2026-11-13 ("make some animations", the reference clip): each product's rays turn slowly
	-- (sunSpin = seconds a turn), its picture rocks gently (iconTilt degrees, iconSeconds a swing), and a
	-- light sweeps over each Buy button (shineSeconds, then a rest of shineEvery; staggered card to card).
	-- None of it with Reduced motion. robuxOutline = the Robux mark's dark contour, a share of its size.
	motion = { sunSpin = 16, iconTilt = 6, iconSeconds = 1.4, shineSeconds = 0.7, shineEvery = 2.8, shineStagger = 0.45, shineAlpha = 0.35 },
	-- the opening (owner 2026-11-16, the vault's shop clips): the colour wash, the panel pop, the title bar drop, then
	-- the rows one by one (rowGap apart, a rising tink on the first `tinks`), and the corner pets last. Seconds.
	opening = { washSeconds = 0.25, washAlpha = 0.45, panelFrom = 0.55, panelSeconds = 0.32, headerDrop = 0.12, headerSeconds = 0.3,
		rowSeconds = 0.28, rowGap = 0.06, tinks = 6, mascotSeconds = 0.35 },
	robuxOutline = 0.075,
	scene = { moonAlpha = 0.72, moon = { x = 0.84, y = 0.16, size = 0.5 },
		hills = {
			{ to = "ink", amount = 0.3, at = { { 0.12, 0.42, 0.3 }, { 0.5, 0.5, 0.36 }, { 0.9, 0.44, 0.28 } } },
			{ to = "white", amount = 0.6, at = { { -0.02, 0.4, 0.14 }, { 0.32, 0.46, 0.17 }, { 0.7, 0.42, 0.13 }, { 1.04, 0.4, 0.16 } } },
		} },
}
-- the Daily Challenges popup (2026-11-12): row heights (shares of the body), where a card's words and bar
-- sit, and its right-hand side (the coin tag, Claim, Done)
Config.ui.daily = { timerHeight = 0.09, rowHeight = 0.2, inviteHeight = 0.17, textX = 0.145, textW = 0.52, sideX = 0.69, sideW = 0.29 }
Config.ui.petSpriteScale = 1.25 -- a pet sprite is this many times the pet's height wide

-- The world teaches (prototype client.js): a green arrow to a pet in your first minutes and home while
-- you carry, a diamond over the nearest pet you can't reach yet, a light pillar over your pen
Config.guide = {
	earlyPets = 3, -- the arrow points to pets until you own this many
	arrowDistance = 6.5, arrowHideNear = 8, arrowY = 0.5, arrowBob = 0.35, arrowBobSpeed = 4,
	markerRange = 45, markerY = 1, markerBob = 0.3, markerSpin = 1.5,
	beaconRadius = 3.2, beaconHeight = 70, beaconTransparency = 0.78, beaconPulse = 0.06,
	-- tutorial references 2026-11-15 (vault Research › Tutorial References): every top game draws a trail of
	-- chevrons on the ground all the way to the target and a big bouncing arrow over the target itself.
	-- trail: up to trailCount small chevrons every trailGap studs after the lead arrow, flowing forward at
	-- trailFlow studs a second (still with reduced motion), each trailScale of the lead arrow
	trailCount = 8, trailGap = 4, trailScale = 0.7, trailFlow = 3,
	-- target arrow: a big chevron pointing down over the target, targetY studs over its top, bobbing
	-- targetBob studs at targetBobSpeed; hidden when you're closer than targetHideNear (you're there)
	targetScale = 1.6, targetY = 3, targetBob = 0.8, targetBobSpeed = 4, targetHideNear = 5,
	-- how high the target's top is, by kind (pets and cubes use their own size)
	targetTop = { pan = 9, machine = 7, stand = 6, train = 5, gate = 12 } :: { [string]: number },
}
-- The tutorial (owner 2026-11-10; no guide character since 2026-11-15, owner: "get rid of captain frost").
-- The world teaches: the goal pill at the top centre (TutorialGoal), the chevron trail and the arrow over
-- the target (GuideController), the glow on the pet or cube, a dimmed popup with an arrow at the button.
-- on = what finishes a step: an action the server saw (TutorialService.did) or "next" (by itself after
-- autoNext seconds). A later step's action counts too, so a player who runs ahead is never held back,
-- except an `only` step, which counts only while it's the current one (an upgrade bought before the catch
-- must not skip the catch).
-- focus = the arrow's target kind (and the glow); goal = the pill's words; icon = its painted icon.
-- hints = shown in the pill if the step takes a while, worded for the player's device (or "all").
-- cheer = shown in the pill when that step is done (else a random praise).
-- gift = coins topped up to the price of this Pan Upgrade's next level when the step starts, once per save.
-- Saved per player (DataService tutorial = { step, done, gift, paid }); saves from before it existed count
-- as done (Lessons: new-player things are for new players only). Replay is in Settings.
Config.tutorial = {
	-- 2026-11-15 (owner: "get rid of captain frost", and Cold Power training belongs in the tutorial): one run,
	-- no guide character and no talk steps. The goal pill says each goal; cheers, hints and reactions show in
	-- it for a moment. The whole loop: catch -> home -> thaw -> upgrade -> train -> open the next island.
	steps = {
		-- 2026-11-16 (owner: "you need to hold it"): the ray only fires while you hold, so the goal says hold
		-- goals = the goal worded for a device (touch, gamepad), else `goal` (QA IR-09: "Click" on a phone)
		{ id = "zap", on = "zap", focus = "pet", icon = "pet", goal = "Hold the ray on a pet", say = "",
			goals = { touch = "Hold your finger on a pet", gamepad = "Aim at a pet and hold R2" },
			hints = { keyboard = "Hold click on the pet!", touch = "Hold your finger on the pet!", gamepad = "Aim at it and hold R2!" } },
		{ id = "freeze", on = "freeze", focus = "pet", icon = "ray", goal = "Keep holding to freeze it", say = "",
			cheer = "BRRR! Frozen solid!",
			hints = { keyboard = "Keep holding click!", touch = "Keep holding!", gamepad = "Keep holding R2!" } },
		{ id = "pickup", on = "pickup", focus = "cube", icon = "pet", goal = "Pick up your frozen pet", say = "",
			hints = { keyboard = "Walk to the cube and press E!", touch = "Walk to the cube and tap Pick up!", gamepad = "Walk to the cube and press X!" } },
		{ id = "carry", on = "bank", focus = "pan", icon = "pen", goal = "Run it home to your pan!", say = "",
			hints = { all = "Follow the arrows to your pan!" } },
		{ id = "thaw", on = "thawStart", focus = "machine", icon = "thaw", goal = "Use the Thaw Machine", say = "",
			hints = { keyboard = "Stand by the machine and press E!", touch = "Stand by the machine and tap its button!", gamepad = "Stand by the machine and press X!" } },
		-- the very first pet pops out by itself with a little reveal (Config.thaw.firstPops)
		{ id = "wait", on = "thawed", focus = "machine", icon = "thaw", goal = "Wait for your pet", say = "",
			cheer = "Your first pet! It makes coins!" },
		-- gift = coins topped up to the price of this Pan Upgrade's next level, once per save (giftSay is the
		-- goal while they're new; {coins} = how many)
		{ id = "upgrade", on = "upgrade", only = true, focus = "stand", icon = "pen", gift = "slots", say = "",
			goal = "Buy Slots at your pan", giftSay = "+{coins} coins! Buy Slots at your pan",
			-- a replay with Slots already at the top: any Pan Upgrade counts (TutorialService takes any kind)
			maxedSay = "Buy any upgrade", maxedGoal = "Buy any upgrade at your pan",
			cheer = "More room for pets!",
			hints = { keyboard = "Press E at the stand, then Buy!", touch = "Tap the stand, then tap Buy!", gamepad = "Press X at the stand, then Buy!" } },
		-- peek (reworked 2026-11-16, owner: "it's weird how it goes to that pet"): the camera looks at the next
		-- island's gate and the bigger pets waiting behind it, while the pill says what opens it: Cold Power.
		-- So the next step (train) has a reason (Config.tutorial.tease)
		{ id = "peek", on = "next", tease = true, icon = "gate", say = "Island 2 opens at {need} Cold Power!" },
		{ id = "train", on = "trainStart", only = true, focus = "train", icon = "power", goal = "Train on your Snowman", say = "",
			hints = { keyboard = "Stand on the pad and press E!", touch = "Stand on the pad and tap Train!", gamepad = "Stand on the pad and press X!" } },
		{ id = "power", on = "powerReady", only = true, focus = "train", icon = "power", count = "power", goal = "Click fast to fill your Cold Power", say = "",
			goals = { touch = "Tap fast to fill your Cold Power", gamepad = "Press R2 fast to fill your Cold Power" },
			cheer = "Full power!", hintOnce = true,
			hints = { keyboard = "Click fast to zap faster!", touch = "Tap fast to zap faster!", gamepad = "Press R2 fast to zap faster!" } },
		{ id = "gate", on = "gateOpen", only = true, focus = "gate", icon = "gate", goal = "Hop off and open the gate", say = "",
			cheer = "A new island!",
			hints = { keyboard = "Walk up to the gate and press E!", touch = "Walk up to the gate and tap its button!", gamepad = "Walk up to the gate and press X!" } },
		-- reward = coins paid once per save as the tutorial ends, shown on the TUTORIAL COMPLETE card
		{ id = "done", on = "next", icon = "trophy", say = "Tutorial complete!", reward = 900, rewardTitle = "TUTORIAL COMPLETE!" },
	} :: { { id: string, on: string, say: string, focus: string?, goal: string?, goals: { [string]: string }?, hints: { [string]: string }?, cheer: string?, only: boolean?, gift: string?, giftSay: string?, maxedSay: string?, maxedGoal: string?, quiet: boolean?, hintOnce: boolean?, tease: boolean?, icon: string?, count: string?, reward: number?, rewardTitle: string? } },
	-- the goal pill (references: one short goal at the top centre, always on, with step dots; nothing to
	-- dismiss). icon = Config.images.icons key, or "pet" = the first island's Common sprite. A cheer, hint or
	-- reaction replaces the goal for messageSeconds, then the goal comes back. Skip lives on the pill.
	messageSeconds = 3.5,
	petIcon = "snowbun",
	-- the menus (the tiles and the top buttons) stay hidden up to and including this step, then pop in
	-- (references: the HUD starts nearly empty and unlocks as it's taught)
	lockMenus = true, lockUntil = "upgrade",
	-- the TUTORIAL COMPLETE card: a trophy pops over a turning sunburst, the coins count up, confetti, a green OK
	complete = { pop = 0.35, countSeconds = 0.9, confetti = 40, confettiReduced = 12, fall = { 1.4, 2.4 }, sunSpin = 20 },
	actions = { zap = true, freeze = true, pickup = true, bank = true, thawStart = true, thawed = true, upgrade = true,
		trainStart = true, powerReady = true, gateOpen = true } :: { [string]: boolean },
	-- the peek (step "peek"): the camera flies to look over the next island's gate at one of its Rares, glowing
	-- (a real pet of that island, shown as a picture of what lives there), holds, then flies back
	-- high over the gate (the sign and the bars hide a low shot), the pet on the island's path (checked in Studio)
	-- 2026-11-16: framed from the hub side, low and to one side, so the gate (with its Cold Power sign) is in
	-- front and the pets stand just behind its bars; several pets, not one, so it reads "a new island"
	tease = { fly = 0.9, hold = 2.6, back = 0.6, camBack = 40, camUp = 17, camSide = 12, lookUp = 9, petIn = 14, petSize = 4.5, pets = 3, petGap = 9, glow = true }, -- further back so the gate's sign fits (QA 2026-11-16)
	praise = { "Nice!", "Great job!", "Ice cold!", "Perfect!", "Chill moves!" },
	react = {
		melted = "It melted! Zap it again!",
		tooWarm = "Too hot! Try a closer pet.",
		wrongWay = "Home is the other way!",
		skipConfirm = "Sure?",
	},
	-- timings (seconds) and distances (studs)
	praiseHold = 1.6, -- a cheer stays this long before the next goal
	autoNext = 4, -- a talk step (the peek, the end) moves on by itself after this
	hintAfter = 9, hintEvery = 14, -- a stuck player sees the step's hint after this, then again every hintEvery
	reactCooldown = 8, -- at most one reaction this often
	wrongWayStuds = 18, -- carrying home: this much farther from the pan than your closest = wrong way
	skipConfirmSeconds = 3, -- Skip asks "Sure?"; a second press within this skips
	nextCooldown = 0.5, -- the server ignores a second "next" sooner than this
	popSeconds = 0.25, -- the pill pops in (Animation Rules: pop)
	sounds = { praise = "coin", finish = "unlock", gift = "gift", hint = "click" },
}
-- the ice ray: a small gun in every player's right hand, a beam while you hold Freeze
Config.ray = { beamCore = 0.28, beamGlow = 0.84, armRaise = 90, tipSize = 0.76, sparkleRate = 20,
	-- each gun tier: a wider beam, more sparkles along it and at the pet, a curl from tier 5 (beam colours: Theme.guns)
	beamPerGun = 0.04, sparklePerGun = 4, sparkleSize = 0.3, sparkleSizePerGun = 0.03, curlFromGun = 5, curlAmount = 0.6,
	tipLightRange = 5, tipLightBrightness = 2, -- a real gun model: a small light in its glow colour at each barrel tip
	-- owner 2026-11-16: "you can freeze more": the ray stays out after a freeze, so you can freeze one pet after
	-- another; they wait on the ground (Config.carry) while your hands still hold only what they can
	putAwayAfterFreeze = false,
-- the shot's body motion (owner 2026-11-05, from a freeze reference clip): a quick start (hips lead, the
-- torso coils back, then everything snaps forward and the beam lands), a hold that leans in harder as the
-- meter climbs, and a lock (the cube shut) or a cancel (let go early). Seconds; angles in degrees;
-- dips in studs. Every character on every client. Reduced motion halves the times and stops the strain.
anim = {
	start = { seconds = 0.27, weightEnd = 0.05, coilFrom = 0.033, coilEnd = 0.083, fireAt = 0.10, kickEnd = 0.133,
		snapSeconds = 0.033, snapStagger = 0.008 }, -- each joint unwinds in 2 frames, half a frame after the one below
	dip = 0.12, hipTurn = 5, coilTwist = 8, coilBack = 4, cockDip = 3, kickUp = 5, -- the start
	braceLean = 3, holdLean = 7, holdDip = 0.2, -- the hold: leans in harder as the meter climbs
	strain = { amount = 0.6, hz = 5, from = 0.6 }, -- a slow wobble on the gun near the end (not with reduced motion)
	lock = { seconds = 0.45, kickEnd = 0.05, kickUp = 7 }, -- the cube shut: the gun rocks up as the tension lets go
	cancel = { seconds = 0.25 }, -- let go early: a soft return, no kick
	lockFromMeter = 0.8, -- someone else's beam that stops this far up (or on a vanished target) counts as a lock
	blendSeconds = 0.08, -- each change of phase crossfades from the pose it was in
	-- cues as shares of the clip (0-1); sounds are Config.sounds names, effects are in RayController
	startCues = { { at = 0.12, sound = "ray_charge", fx = "mist" }, { at = 0.31, sound = "ray_clack" },
		{ at = 0.37, sound = "ray_fire", fx = "flash", kick = "fire" }, { at = 0.42, fx = "eject" } } :: { RayCue },
	lockCues = { { at = 0, kick = "lock" }, { at = 0.07, sound = "ray_tail" }, { at = 0.15, fx = "vent" } } :: { RayCue },
	cancelCues = { { at = 0, sound = "ray_fizz" } } :: { RayCue },
	humPitch = { 1.0, 1.2 }, -- the hold's hum rises with the meter
	fx = { mist = 8, eject = 5, vent = 10, flashSize = 0.9, flashSeconds = 0.07, flashGap = 0.34, -- flashGap: at most 3 flashes a second
		beamOut = 0.06, beamIn = 0.1 }, -- the beam pulls back: the muzzle end first, then the target end
} }
-- extra pet looks (prototype syncWild / makeCube)
Config.petFx = {
	ringScale = 1.8, ringSpin = 0.5, shadowScale = 1.0, starCount = 3, starRadius = 0.9, starHeight = 1.45, starSpin = 3,
	rareSparkleRate = 2, frostySparkleRate = 6, crackBelow = 0.35, crackLines = 9, edgeTransparency = 0.45,
	popSeconds = 0.25,
	mutSparkleRate = 5, mutOutline = 0.35, -- Golden / Starry pets (colours in Theme.mut)
	mutSparkleSize = { Golden = 0.3, Starry = 0.6 } :: { [string]: number }, -- Starry's twinkles are big enough to read on a phone
	sleepTilt = 0.4, -- radians a sleeping pet leans over onto its side
	-- a cube's ice melts away from the top down as its life runs out (owner 2026-11-17: "slowly unfreeze it
	-- like from up to bottom"): the ice block's height = its life left, sitting on the cube's bottom, so the
	-- pet comes free head first. follow: how fast the drawn height catches up with the server's LifeFrac (per
	-- second; it arrives in 1% steps). floor: the ice never draws lower than this share of the cube.
	-- fade: extra see-through as it melts. line: the wet, bright water line on the ice's top (studs thick,
	-- share wider than the cube). drips: water drops off the melt line while it is melting (stops when it
	-- isn't: hub, Big Chill), rate a second, half with reduced motion.
	melt = {
		-- refreeze: how fast the ice grows back to full once you're in the safe hub (per second, ~1 s)
		follow = 6, refreeze = 2.5, floor = 0.06, fade = 0.15,
		line = { thick = 0.05, grow = 0.04, transparency = 0.6 }, -- 0.3 white read as a snow lid in play (2026-11-17)
		drips = { rate = 12, size = 0.14, speed = { 0.4, 1.2 }, life = { 0.45, 0.75 }, fall = 28, meltingFor = 3 },
	},
}
-- pet motion (PetVisuals): no rigs yet, so each action is squash, stretch, lean, hop and turn on the whole
-- pet around its feet. Heights, steps and sways are fractions of the pet's height (PetDefs.sizeHeight);
-- beat times are fractions of the action's Config.poses seconds; angles in radians (pitch > 0 = nose up).
Config.petAnim = {
	farDistance = 110, -- studs: farther away or off-screen a pet just stands (cheap on phones)
	reducedAmp = 0.35, -- reduced motion: every hop, lean and squash this much smaller, no twirls
	blendSeconds = 0.15, -- quick crossfade between actions, so nothing pops
	sleepBlendSeconds = 0.9, -- lying down at night and getting up are slow
	follow = 12, turn = 7, -- how fast the drawn pet glides after and turns to its server root (10 Hz steps)
	snapDistance = 8, -- farther than this from its root it jumps there instead of gliding
	walkAt = 0.5, -- full walk cycle from this fraction of Config.spawner.wanderSpeed
	walkFade = 6, -- how fast the walk fades in and out as it starts and stops
	-- pets split into a body and legs (a Model with Leg parts that carry Hip / Swing / Front attributes,
	-- owner 2026-11-03: "move its limbs"): radians each leg swings round its hip. Diagonal pairs swing
	-- together while walking; front legs reach forward and back legs kick back in the air (jump)
	limbs = { walk = 0.42, dance = 0.3, tuck = 0.45, tuckHeight = 0.25 }, -- owner 2026-11-04: "tweak it a bit" (was 0.6 / 0.4 / 0.55)
	-- the other split parts (Role head / ear / tail, each turning round its Pivot; ears ride on the head):
	-- the head looks around and nods with the steps, ears twitch now and then and flop as it moves,
	-- the tail wags (faster in a dance). Radians, periods in seconds
	-- a hat (Role "hat", e.g. Toddle's toadstool cap) rides on the head; on a jump it pops off at take-off,
	-- floats hatLift pet heights over the head, lands just after the pet (hatOff / hatOn: fractions of the
	-- jump), does a tiny re-hop (hatHop heights, hatHopSeconds) and wobbles hatTilt radians, settling on a
	-- damped spring over hatSettle seconds
	parts = { headLook = 0.22, headLookPeriod = 3.7, headNod = 0.1, earTwitch = 0.5, earTwitchEvery = 2.6,
		earTwitchSeconds = 0.22, earFlop = 0.3, tailWag = 0.3, tailHz = 1.4, tailDanceWag = 0.55, tailDanceHz = 3.2,
		hatLift = 0.25, hatOff = 0.24, hatOn = 0.8, hatHop = 0.05, hatHopSeconds = 0.14, hatTilt = 0.22, hatSettle = 0.7,
		hatShowAt = 0.16 }, -- a LiftedOnly hat part (the cap's underside) shows once the hat is this far off the head
	-- some idles become a scratch (owner 2026-11-04: "scratching or smth"): a back leg (or an arm) comes up
	-- and rubs behind the ear on one side while the head tilts into it. Looks only: picked from the pet's
	-- id and its ActionStart, so every player sees the same scratch and the pose (and income) don't change
	scratch = { chance = 0.45, start = 0.3, seconds = 1.6, ramp = 0.22, leg = 1.2, arm = 2.5, out = 0.35, rub = 0.22,
		rubHz = 7, headRoll = 0.32, headPitch = 0.15, earFlap = 0.45, lean = 0.1 },
	idle = { breathe = 0.035, breathePeriod = 1.8, lookYaw = 0.25, lookPeriod = 6 },
	yawn = { rise = 0.3, settle = 0.72, stretch = 0.26, lean = 0.45, roll = 0.12, sag = 0.08 },
	jump = { crouch = 0.2, land = 0.7, height = 0.9, squash = 0.25, tuck = 0.3 },
	dance = { beats = 4, hop = 0.2, twirlHop = 1.5, roll = 0.3, sway = 0.4, step = 0.12, squash = 0.12 },
	sneeze = { build = 0.55, snap = 0.64, stretch = 0.15, lean = 0.32, snapLean = 0.5, squash = 0.24, recoil = 0.18,
		puff = 10, puffSize = 0.18, puffSpeed = 6, puffLife = 0.5 },
	-- asleep (owner 2026-11-09: "make the pets not move and close their eyes while sleeping"): it only
	-- breathes, slowly. No walking, strolling, head looks, ear twitches, tail wags or scratches.
	sleep = { flatten = 0.12, breathe = 0.05, breathePeriod = 4, sink = 0.06 },
	-- closed eyelids on 3D pets (spots in Shared.PetEyes): a soft lid in the fur colour over each painted
	-- eye with a dark U-shaped curve on it. Sizes are fractions of the eye's radius: width / height of the
	-- lid, depth (how far it bulges), sink (pushed into the face), lash (the curve's thickness).
	-- faceBlend: how much the lid turns toward the pet's front (the measured face direction is rough).
	-- shutAt: the eyes close this far into lying down (0-1 of sleepBlendSeconds)
	lids = { width = 1.3, height = 1.2, depth = 0.8, sink = 0.2, lash = 0.17, lashSegments = 5, lashWidth = 0.78,
		lashDip = 0.32, faceBlend = 1, shutAt = 0.5 },
	dazed = { tilt = 0.25, wobble = 3, spin = 1.6, sway = 0.06 },
	-- walk cycle per rig family (PetDefs.rig, or gaitFor): stride = pet heights per step; bob/bobHz = idle hover
	gait = {
		Quadruped = { stride = 0.35, hop = 0.08, pitch = 0.1, roll = 0.04, yaw = 0.04, squash = 0.08, lean = 0.1, bob = 0, bobHz = 0 },
		Hopper = { stride = 0.6, hop = 0.24, pitch = 0.15, roll = 0, yaw = 0, squash = 0.2, lean = 0.12, bob = 0, bobHz = 0 },
		Biped = { stride = 0.28, hop = 0.05, pitch = 0.03, roll = 0.18, yaw = 0.12, squash = 0.05, lean = 0.04, bob = 0, bobHz = 0 },
		Bird = { stride = 0.5, hop = 0.18, pitch = 0.08, roll = 0.03, yaw = 0.03, squash = 0.14, lean = 0.12, bob = 0.06, bobHz = 1.4 },
		Blob = { stride = 0.55, hop = 0.2, pitch = 0.02, roll = 0.03, yaw = 0, squash = 0.24, lean = 0.05, bob = 0, bobHz = 0 },
		Swimmer = { stride = 0.4, hop = 0.05, pitch = 0.05, roll = 0.08, yaw = 0.25, squash = 0.12, lean = 0.03, bob = 0, bobHz = 0 },
		Custom = { stride = 0.4, hop = 0.09, pitch = 0.08, roll = 0.06, yaw = 0.05, squash = 0.08, lean = 0.08, bob = 0, bobHz = 0 },
	},
	gaitFor = { snowbun = "Hopper", hopsprout = "Hopper", shimmerfrog = "Hopper" } :: { [string]: string }, -- bunnies and frogs hop
}
Config.mapFx = { gateBarsDrop = 19.3, gateBarsSeconds = 1.2, giftBob = 0.6, giftSway = 0.15,
	motionTag = "MapMotion", -- MapArt's moving parts (booth gears, portal swirl, floating crystals); MapController moves them
	gateGlowPulse = 1.6, -- seconds per breath of a gate's glowing arch (the next goal glows)
	lightTweenSeconds = 1.5, -- each island's own tint fades in as you walk into it
	panDoorSeconds = 0.5,
	-- studs: moving parts and breathing gate glows farther than this from the camera hold still (too far
	-- to see the motion; PERF-AUDIT-2026-11-09)
	motionDistance = 450 }
-- banked pets stay frozen: ice cubes in a neat grid on the pan, the pet inside wiggles a little,
-- frost shimmers on the ice and a coin rises from each cube now and then
Config.panCubes = { cols = 7, gap = 5, frontMargin = 7, backMargin = 3, maxSize = 4.2, wiggle = 0.06, wiggleSpeed = 2.2,
	shimmerSpeed = 1.3, shimmerAmount = 0.12, coinEvery = 3.2, coinRise = 2.6, coinSize = 1.1, drawDistance = 120 }
-- Coin pops (owner's reference clip 2026-11-07): every `every` seconds each thawed pet in your pan
-- shoots a "+N" (the coin and what it earned in that time) out of the spot over its head, to one side
-- and up, tilted that way; it hangs there drifting up a little, then shrinks and fades. Sides alternate
-- per pet. Pixels are on screen (a BillboardGui), so pops stay the same size at any distance.
Config.coinPop = {
	every = 2, -- seconds between one pet's pops; the number is its real income for that time
	firstDelay = 1.2, -- the longest wait for a pet's first pop (each pet starts at a random point in this)
	maxDistance = 45, -- like name tags: only close up (the camera sits ~30 studs back)
	maxActive = 24, -- phones: never more pops on screen than this
	lift = 0.5, -- studs above the pet's head where a pop starts
	boxPx = { 340, 200 }, -- the billboard's size; the pop moves inside it
	textPx = 36, coinPx = 40, gapPx = 3, strokeRatio = 0.1, -- outline = text size x this
	out = 0.24, -- the shoot out (Back Out, a small overshoot)
	outX = { 50, 85 }, outY = { 38, 62 }, -- how far it shoots, px (random in each range)
	startScale = 0.45, tilt = 11, -- degrees, leaning toward its side
	hold = 0.9, drift = 10, -- hangs, rising this many px
	exit = 0.16, exitScale = 0.8, -- shrinks and fades (Quad In)
	reducedFade = 0.12, -- reduced motion: it fades in and out where it lands, no flight
}

-- carried cubes are held in front of you, in your hands (both arms come up while you carry)
Config.carry = { scale = 0.62, handY = 0.4, front = 0.9, stackGap = 0.15, armRaise = 80,
	-- a freeze leaves the cube on the ground where the pet stood; E picks it up (owner 2026-11-07).
	-- Only the player who froze it can. Left alone this long, it thaws back into a dazed pet that
	-- only you can zap, so a forgotten cube never blocks your hands.
	-- groundSeconds = 0 (owner 2026-11-10): it never wakes up; the frozen pet stays down until you pick it up.
	-- owner 2026-11-13: a frozen pet nobody picks up is gone after 60 s (groundVanish: it poofs, no dazed pet);
	-- the ice clears as the time runs out, so you can see it going
	-- owner 2026-11-16: "you can freeze more and they will unfreeze after a time": a frozen pet you leave on the
	-- ground thaws back out after groundSeconds (dazed for a moment, only you can zap it again), it never poofs
	pickUpRange = 10, groundSeconds = 45, groundVanish = false,
	groundMax = 12, -- at most this many of your frozen pets wait on the ground at once (phones)
	-- QA 2026-11-08 (Studio-side work): the cube flies into your hands by itself this many seconds after
	-- the snap, no E. Restored 2026-11-09 after a sync overwrote Studio's Config: the delay is a guess.
	-- Off again (owner 2026-11-10): the frozen pet stays on the ground until you pick it up with E
	autoPickUp = false, autoPickUpDelay = 0.6 }

-- Trees (shade) and sun patches, placed with the prototype's generator (mulberry32) so the same seed
-- always gives the same map. Each island's own list (Config.world.islands) says how many and how big;
-- Shared/Scenery spreads them across that section of the tunnel.
Config.scenery = {
	seed = 1234,
	pathHalfWidth = 13, -- the main path stays open
	wallMargin = 5, -- trees keep this far from the tunnel walls
	treeBand = 32, -- shade trees stand between this |x| and the walls, so the middle of each island stays open (World Rules 9)
	gateClear = 20, -- and this far from a gate or the end cap (they stay in view)
	startClear = 12, -- the first studs of a section stay open (its sign and the near pets)
	maxLava = 3, -- owner 2026-11-13: "fewer, never beside each other, max 3 per island"; each pool gets its own stretch of the island
}

-- The look of the world (MapArt). Shapes come from ReplicatedStorage.SceneryMeshes
-- (roblox/tools/make_scenery_meshes.ps1); plain parts stand in if missing.
Config.art = {
	-- the Free Gift's frozen treasure (MapArt.giftCorner): the ice cube's size, how see-through it is,
	-- its frosty edges' thickness (a share of a 4-stud cube), the pedestal's height, and how far over the
	-- gift box its "Free gift!" label floats (MapController)
	gift = { cube = 4, ice = 0.74, frost = 0.32, pedestal = 0.7, labelLift = 6.6 },
	seed = 77, -- props (mounds, rocks, mushrooms...) are placed with the prototype's generator too
	treeUnitRadius = 2.4, -- a tree of shade radius r is drawn at scale r / 2.4 (prototype)
	props = { meadow = { mounds = 10, rocks = 8, crystals = 6 }, forest = { mushrooms = 14, bushes = 14, logs = 4 } },
	wallTreesEvery = 14, -- a row of trees behind each tunnel wall, so the corridor reads as a valley
	wallBumpEvery = 16, -- the wall's rounded top (snow drifts, hedges)
	landmarkScale = 1.8, -- landmarks are big enough to see from the section before
	-- World Rules 9 (clear centre, rich edges): the islands' props sit only in this band of |x| at the foot
	-- of the cliffs, between the pets' wander limit (spawner.wallMargin) and the wall; a strip of earth
	-- (the floor darkened toward the cliff rock by stripDarken) blends the floor into the cliffs there
	edge = { from = 51, to = 55.5, stripFrom = 52, stripHeight = 0.2, stripDarken = 0.4 }, -- tunnel half-width 56, pets wander to 50
	canopyClear = 6.5, -- a shade pine's lowest branches start this high, above an avatar's head, so pets under it stay in view
	penPostEvery = 3.2,
	lamps = { Vector3.new(-20, 0, -4), Vector3.new(20, 0, -4), Vector3.new(-30, 0, -40), Vector3.new(30, 0, -40) },
	benches = { { pos = Vector3.new(76, 0, -24), ry = math.pi / 2 }, { pos = Vector3.new(76, 0, -32), ry = math.pi / 2 } },
	farPeaks = 14,
	clouds = { cover = 0.55, density = 0.6 },
}

Config.camera = { fov = 70, minZoom = 10, maxZoom = 40, carryFov = 74, fovSeconds = 0.4,
	-- the prototype's framing at spawn: high and behind, looking ahead, so carried cubes never hide you
	startHeight = 15, startBack = 21, startLookAhead = 10, frameSettleSeconds = 0.25,
	-- short camera kicks: A * e^(-t/decay) * cos(2*pi*hz*t), cut off at `seconds` (Animation Rules 6: 0.3 s or less);
	-- none with reduced motion. The lock kick grows with the pet's tier (Common x0.6 up to Epic x1)
	kicks = {
		fire = { pitch = 0.35, roll = 0, back = 0.04, hz = 16, decay = 0.05, seconds = 0.15 },
		lock = { pitch = 0.8, roll = 0.3, back = 0.1, hz = 12, decay = 0.08, seconds = 0.3 },
	} :: { [string]: { pitch: number, roll: number, back: number, hz: number, decay: number, seconds: number } },
	lockKickScale = { 0.6, 1 }, lockKickFullRank = 4,
	pushFov = -3 } -- while you hold the ray on a target the view tightens this much, with the meter
Config.effects = { pillarSeconds = 8, pillarHeight = 60, burstParts = 12, beamSeconds = 0.15, snowRate = 60, showRank = 4 } -- showRank: Epic and up get a pillar in your pen

-- Nintendo-style juice on the three most common actions (To Do job 2, 2026-11-11; Animation Rules 8,
-- Sound Rules 11): a training shot, a cube shutting, banking. Reduced motion halves every time here and
-- drops the shakes and the shiver.
--   hitStop  = seconds the hit thing holds still (and shakes) before the burst, so a big hit reads
--              (Sakurai's hit stop): a training shatter, and a cube shutting (Common .. Epic; Legendary
--              and up have their own show)
--   hitShake = how far (studs) the held thing shakes during the hit-stop
--   hitFlash = a training target flashes white this long when a bolt lands (a bolt = flashPeak, a
--              shatter = full white through its hit-stop)
--   tremble  = past `from` of the shatter meter, your training target shivers (radians, cycles per second):
--              the next shots may break it
--   tally    = banking: the cubes hop from your hands into the pen one by one, each a note higher up a
--              major scale (`notes`, semitones), then the bank chime and bursts land (the finale)
Config.juice = {
	hitStop = { shatter = 0.09, lock = { 0.04, 0.09 } },
	hitShake = 0.12,
	hitFlash = 0.08, flashPeak = 0.55,
	tremble = { from = 0.7, amp = 0.035, hz = 22 },
	tally = { stagger = 0.12, fly = 0.3, arc = 2.5, maxCubes = 8, finale = 0.08, startUp = 1.2, startFront = 1.6,
		notes = { 0, 2, 4, 5, 7, 9, 11, 12 }, landParts = 6 },
}

-- Freezing that looks great (Round 4 phase 3). Every freeze timing and every show beat lives here
-- (Animation Rules 1). Reduced motion halves the client's look timings and every show beat.
export type Beat = { name: string, time: number, keepOnSkip: boolean? }
Config.show = {}
Config.show.freeze = {
	-- how long a freeze takes (FreezeService times it on the server): tierSeconds x sizeFactor / the gun's power (Config.guns)
	tierSeconds = { Common = 0.9, Uncommon = 1.0, Rare = 1.3, Epic = 1.6, Legendary = 2.1, Mythic = 2.7, Secret = 3.4 } :: { [string]: number },
	sizeFactor = { S = 1, M = 1.12, L = 1.3 } :: { [string]: number },
	minSeconds = 0.2,
	flashBelow = 0.45, -- this quick or quicker: a flash-freeze (a snap, a puff of frost, a light "tink")
	layeredFrom = 1.9, -- this slow or slower: layers, cracks, falling ice, and a bar that fights back a little
	fightBack = { amount = 0.12, pushes = 3 }, -- the bar slips back this much, this many times (always ends at 100%)
	holdSeconds = 600, -- the prompt's own hold never finishes by itself: FreezeService decides when the cube shuts
	-- higher gun tiers add their own finishing touch when the cube shuts (the highest one that applies)
	touches = { { fromGun = 3, touch = "spikes" }, { fromGun = 6, touch = "aurora" }, { fromGun = 9, touch = "stars" } },
	-- the look while you hold (PetVisuals)
	slowdown = 0.85, -- the pet's moves slow to 15% as the ice climbs
	struggle = { amp = 0.14, speed = 13 }, -- a cute wiggle (radians, per second), biggest half-way up
	crystals = 8, crystalSize = 0.55, -- crystals grow along the outline as the ice rises
	shellPad = 1.12, -- the creeping ice is this much wider than the pet
	cracksFrom = 0.3, cracks = 6, -- layered freezes crack from 30% up
	chipEvery = 0.4, chipFall = 2.2, chipSeconds = 0.55, chipSize = 0.32, -- bits of ice falling off a layered freeze
	frostFill = 0.55, -- the frost overlay at 100% (Highlight fill, 0 = none)
	-- the ice front (owner 2026-11-05, from a freeze reference clip): mist rolls in first, the ice climbs fast
	-- then slows near the top (height = 1 - (1 - meter)^2), a bright frost rim leads it, and loose crystal
	-- flecks flicker just above the rim. The frost colour follows the meter, so it trails the front.
	mist = { rate = 14, untilMeter = 0.5 }, -- per second at the feet, fading out by this meter
	rim = { thick = 0.1, transparency = 0.2 }, -- a thin bright line round the top edge of the ice
	flecks = { count = 5, size = 0.22, seconds = 0.3, band = { 0.1, 0.25 } }, -- band: heights above the rim, shares of the pet's height
	-- the snap at 100% (EffectsController)
	snapSeconds = 0.16, snapScale = 1.22, puffParts = 14, flashPuffParts = 22, flySeconds = 0.3,
	-- a save's very first freeze (2026-11-15): longer hit-stop, a flash, rays and a big burst
	firstHoldScale = 2.5, firstRays = 10, firstRaySeconds = 1.2, firstBurst = 60,
	touchSeconds = 0.8, spikeCount = 6, spikeHeight = 1.6, starCount = 7, auroraBands = 3,
	-- which tiers get a show instead of the plain snap (smaller for Legendary and Mythic)
	shows = { Legendary = "legendaryFreeze", Mythic = "mythicFreeze", Secret = "secretFreeze" } :: { [string]: string },
	graceExtra = 1.5, -- the shown cube doesn't melt while its show runs (plus this much)
}
-- Secret pets: the full in-world show (Animation Rules 3). The server has already put the pet in
-- your hands; the show only plays it. SKIP shows after your first viewing and jumps to the reveal.
-- Remade 2026-11-13 (owner: "the animations when catching a secret/mythic are very shit"): the luck roll
-- (LuckReveal, Config.show.reveal) replaces the fat light pillar and the plain name. odds = "1 in N" climbs
-- to the real odds while the name freezes in; title = rarity, name, sunburst, confetti, Continue.
-- v3 (owner 2026-11-16: "improve the secret catching animation by miles", from the owner's reference clips):
-- the neon stage, glowing pet outlines flicking past while the odds climb and landing on yours, a ring and a
-- slash of light in the dark, a white-out, then the slam, rainbow ribbons, the reveal with a stat card
Config.show.secretFreeze = {
	beats = {
		{ name = "push", time = 0.8 }, -- the camera pushes in from the far side
		{ name = "blackout", time = 0.5 }, -- the neon night stage fades in over the world
		{ name = "silhouettes", time = 4.2 }, -- "1 in N" climbs, outlines flick past and land on yours, the name fills in
		{ name = "ring", time = 1.2 }, -- dark, a white ring pulses twice, a slash of light
		{ name = "whiteout", time = 0.6, keepOnSkip = true }, -- white-out; the stage goes, the world is back
		{ name = "slam", time = 0.35, keepOnSkip = true }, -- the ice slams shut
		{ name = "ribbons", time = 0.05, keepOnSkip = true }, -- rainbow ribbons start swirling round it
		{ name = "burst", time = 0.55 }, -- a burst and rays (no second flash: the white-out was it)
		{ name = "title", time = 1.0, keepOnSkip = true }, -- the reveal and the stat card, then Continue
		{ name = "fly", time = 0.6, keepOnSkip = true }, -- the cube flies home, camera back
	} :: { Beat },
	pillar = false, camera = true, flash = false, shout = true, burstParts = 46, rays = 12, title = "SECRET!", stats = true,
	-- pushSide: degrees round to one side of the pet (you never block it); lookDrop: studs under the pet the camera
	-- looks at, so the pet sits above the reveal's words
	pushDistance = 9, pushHeight = 2.5, pushSide = 35, lookDrop = 2.4, kick = 0.25, slamDrop = 7,
}
-- the Secret show's stage and effects (Show: blackout, silhouettes, ring, whiteout, ribbons, statsCard)
Config.show.secretCinema = {
	skyTop = Color3.fromHex("3a1a8a"), skyBottom = Color3.fromHex("140c3c"), dark = Color3.fromHex("0c0820"),
	orbs = 10, orbSize = { 0.05, 0.13 }, orbColors = { Color3.fromHex("ff4fd8"), Color3.fromHex("5fd0ff"), Color3.fromHex("9b7bff"), Color3.fromHex("5dffb0") },
	flakes = 28, flakeMint = Color3.fromHex("7dffb0"),
	-- the outlines: middle of the screen, a share of its height; outline = how far each glow copy is nudged
	silY = 0.43, silSize = 0.42, outline = 0.022, silhouette = Color3.fromHex("0c0820"),
	outlineColors = { Color3.fromHex("5fd0ff"), Color3.fromHex("ff4fd8"), Color3.fromHex("7dffb0"), Color3.fromHex("ffd34a") },
	swapFrom = 0.08, swapTo = 0.5, landAt = 0.88, holdFinal = 0.45,
	ringFrom = 0.03, ringTo = 0.1, softPeak = 0.55,
	ribbons = 4, ribbonRadius = 3.5, ribbonArc = 200, ribbonRise = 1.1, ribbonWidth = 1.1, ribbonSpin = 1.8,
	statsY = 0.045, statsSize = { 0.7, 0.115 },
}
Config.show.mythicFreeze = {
	beats = {
		{ name = "push", time = 0.7 },
		{ name = "odds", time = 2.4 },
		{ name = "slam", time = 0.3, keepOnSkip = true },
		{ name = "burst", time = 0.4 },
		{ name = "title", time = 0.8, keepOnSkip = true },
		{ name = "fly", time = 0.5, keepOnSkip = true },
	} :: { Beat },
	pillar = false, camera = true, flash = true, shout = false, burstParts = 30, rays = 8, title = "MYTHIC!",
	pushDistance = 10, pushHeight = 3, kick = 0.2, slamDrop = 5,
}
-- a Secret coming out of your Thaw Machine after you press Claim (owner 2026-11-13): the camera looks at
-- the machine, it charges up, the same luck roll, a burst, the reveal and Continue
Config.show.thawReveal = {
	beats = {
		{ name = "aim", time = 0.8 },
		{ name = "charge", time = 1.2 },
		{ name = "blackout", time = 0.4 }, -- the same neon stage and outlines as the Secret catch (2026-11-16)
		{ name = "silhouettes", time = 3.4 },
		{ name = "whiteout", time = 0.5, keepOnSkip = true },
		{ name = "ribbons", time = 0.05, keepOnSkip = true },
		{ name = "burst", time = 0.5, keepOnSkip = true },
		{ name = "title", time = 1.0, keepOnSkip = true },
		{ name = "fly", time = 0.7, keepOnSkip = true },
	} :: { Beat },
	tiers = { Secret = true } :: { [string]: boolean },
	camera = true, flash = false, burstParts = 50, rays = 10, chargePulses = 3, stats = true,
	camBack = 15, camUp = 6, lookUp = 2,
}
-- your very first pet coming out (Config.thaw.firstPops; Tizzy: the first time is a wow): the thaw reveal,
-- shorter, for any tier
Config.show.firstReveal = {
	beats = {
		{ name = "aim", time = 0.6 },
		{ name = "charge", time = 0.8 },
		{ name = "odds", time = 1.6 },
		{ name = "burst", time = 0.5, keepOnSkip = true },
		{ name = "title", time = 0.8, keepOnSkip = true },
		{ name = "fly", time = 0.6, keepOnSkip = true },
	} :: { Beat },
	tiers = {} :: { [string]: boolean },
	camera = true, flash = true, burstParts = 40, rays = 8, chargePulses = 2,
	camBack = 15, camUp = 6, lookUp = 2,
}
-- the luck roll's numbers (LuckReveal). words: shown once "1 in N" passes `from` (ice-themed, our own);
-- tier = which tier colour the word wears. rollEase: how hard the count slows near the real odds.
Config.show.reveal = {
	words = {
		{ from = 10, text = "COOL!", tier = "Uncommon" },
		{ from = 100, text = "FROSTY LUCK!", tier = "Rare" },
		{ from = 1000, text = "ICE COLD LUCK!", tier = "Epic" },
		{ from = 10000, text = "BLIZZARD LUCK!!", tier = "Legendary" },
	},
	rollEase = 2.2, tickEvery = 0.07, tickSound = "upgrade_chime", tickFrom = 0.8, tickTo = 1.8,
	letterPop = 0.2, shiver = { deg = 3, hz = 26 }, cubeShiver = 0.12, vignette = 0.35,
	confetti = 48, confettiReduced = 14, confettiFall = { 1.8, 3.0 },
	sunRays = 12, sunSpin = 0.06, sunSize = 0.62,
	maxHold = 12, -- seconds the reveal waits for Continue before going on by itself
	-- shares of the screen: luck word and counter at the top, rarity / name / odds / Continue low
	ui = { wordY = 0.06, wordH = 0.065, oddsY = 0.13, oddsH = 0.1, rarityY = 0.6, rarityH = 0.05, nameY = 0.66, nameH = 0.11,
		nameMaxW = 0.9, letterAspect = 0.72, spaceShare = 0.45, lineY = 0.78, lineH = 0.045, continueY = 0.895, continueSize = { 0.3, 0.115 } }, -- Continue: 0.085 tall was 27 px on a phone
}
Config.show.legendaryFreeze = {
	beats = {
		{ name = "slam", time = 0.3, keepOnSkip = true },
		{ name = "burst", time = 0.35 },
		{ name = "name", time = 1.3, keepOnSkip = true },
		{ name = "fly", time = 0.45, keepOnSkip = true },
	} :: { Beat },
	pillar = false, camera = false, flash = true, shout = false, burstParts = 20, rays = 0, title = "LEGENDARY!",
	pushDistance = 0, pushHeight = 0, kick = 0.15, slamDrop = 4,
}
Config.show.ui = { titleSize = { 0.7, 0.16 }, nameSize = { 0.6, 0.1 }, titleY = 0.3, skipSize = { 0.22, 0.09 }, skipY = 0.86,
	slamFrom = 2.2, flashAlpha = 0.55, softFlashAlpha = 0.85, flashSeconds = 0.25 }

-- buying a gun at the Equipment Booth (Round 4 phase 4, Animation Rules 3): the new gun spins in,
-- its stat bars fill from your old gun's values, and the old gun drops into your locker. The server
-- has already charged and given the gun; the show only plays it. SKIP from the second viewing.
Config.show.gunBuy = {
	beats = {
		{ name = "spinIn", time = 0.7, keepOnSkip = true }, -- the gun flies in, turning (SKIP keeps the gun and its bars)
		{ name = "bars", time = 1.1, keepOnSkip = true }, -- the 4 stat bars fill from the old gun's values
		{ name = "locker", time = 0.7 }, -- the old gun shrinks into the locker
		{ name = "rest", time = 0.6 }, -- a moment to look before it goes
	} :: { Beat },
	turns = 1.5, -- the gun turns this many times while it flies in
	slowSpin = 0.6, -- turns a second afterwards
	viewSize = 0.34, -- the gun's window, a share of the screen's height (square)
	barWidth = 0.4, barHeight = 0.045, barGap = 0.012,
	title = "NEW GUN!",
}

-- Guns (Round 4 phase 4): 10 at launch and about one more with each island an update adds, up to 20.
-- A list that grows without code changes; each gun is clearly better than the one before it.
-- At most 4 stats (bars on the gun card):
--   power = how fast it freezes (a freeze takes Config.show.freeze seconds / power; gun 1 = 1)
--   range = studs from you to the pet
--   cold  = the hottest island whose pets it can freeze (its place in Config.world.islands)
--   beams = how many pets one hold freezes at once
-- Bought in order at the Equipment Booth. rebirths = the Rebirth needed; price = coins. The rebirth
-- guns (3, 5, 7, 9) come free with their rebirth ("rebirth gives the next gun tier", Round 4 prompt 7);
-- gun 10 needs Rebirth 7 and coins. Coin prices (GrindBot, repriced 2026-11-07): round numbers placed where a
-- player would otherwise wait with nothing to buy; gun 2 (25K) fills the save between island 2 and Rebirth 1. Looks: Theme.guns[i]. A real model goes in ReplicatedStorage.GunModels.<key>
-- once the painted line-up is approved and turned into 3D (Pet Rules 5); until then each gun is the
-- part-built stand-in from RayController.
-- Cold Power remake (2026-11-10): training = the Cold Power multiplier of every shot at a training station
-- (Config.trainGain), heat = the hottest island the gun works on (the old cold values). power and cold go in the cleanup.
export type Gun = { key: string, name: string, training: number, range: number, heat: number, beams: number, price: number, rebirths: number }
Config.guns = {
	list = {
		{ key = "frost_popper", name = "Frost Popper", training = 1, range = 10, heat = 2, beams = 1, price = 0, rebirths = 0 },
		-- balance pass 2026-11-12: each Heat gun lands just before the island that needs it, the rest fill saves
		-- pacing pass 2026-11-16 (PACING-2026-11-16.md): guns 2-10 repriced (rarity pass 2026-11-17 too);
		-- each gun lands within about 25 min of its island (gun 8 25B -> 7.5B, gun 10 1.5T -> 200B)
		-- 2026-11-13: 20K -> 7.5K, the first gun lands ~8 min in (guns now also freeze faster: Config.gunFreeze)
		{ key = "snowball_blaster", name = "Snowball Blaster", training = 2, range = 11, heat = 2, beams = 1, price = 40e3, rebirths = 0 },
		{ key = "icicle_repeater", name = "Icicle Repeater", training = 3, range = 12, heat = 4, beams = 1, price = 2.5e6, rebirths = 0 },
		{ key = "glacier_cannon", name = "Glacier Cannon", training = 5, range = 13, heat = 4, beams = 2, price = 15e6, rebirths = 0 },
		{ key = "blizzard_beam", name = "Blizzard Beam", training = 8, range = 14, heat = 6, beams = 2, price = 100e6, rebirths = 0 },
		{ key = "aurora_ray", name = "Aurora Ray", training = 12, range = 15, heat = 6, beams = 2, price = 400e6, rebirths = 0 },
		{ key = "cryo_lance", name = "Cryo Lance", training = 20, range = 16, heat = 8, beams = 3, price = 15e9, rebirths = 0 },
		{ key = "polar_vortex", name = "Polar Vortex", training = 30, range = 17, heat = 8, beams = 3, price = 40e9, rebirths = 0 },
		{ key = "absolute_zero", name = "Absolute Zero", training = 50, range = 18, heat = 10, beams = 3, price = 1.5e12, rebirths = 0 },
		{ key = "starfrost_nova", name = "Starfrost Nova", training = 100, range = 19, heat = 10, beams = 4, price = 3e12, rebirths = 0 },
		-- owner 2026-11-09: every gun shows a coin price (the free rebirth guns read "Rebirth 2" on only some
		-- rows and looked odd), so all guns are bought with coins in order; rebirth gates islands, not guns
	} :: { Gun },
	-- the card's bars are scaled to the game's 20-island maximum, not to gun 10, so later guns fill them further
	-- Cold Power remake (2026-11-10): Training = the Cold Power multiplier of each training shot (x1 to x100, so
	-- its bar is drawn on a log scale: Config.gunStatShare), Heat = the hottest island the gun works on
	stats = { "training", "heat", "range" }, -- owner 2026-11-12: Beams is no longer shown (guns still have their beams)
	statLabels = { training = "Training", heat = "Heat", range = "Range", beams = "Beams" } :: { [string]: string },
	statMax = { training = 100, heat = 20, range = 30, beams = 6 } :: { [string]: number },
	boothRange = 30, -- studs: guns are bought standing at the Equipment Booth
	freezePerGun = 0.12, -- each gun after the first freezes 12% faster (Config.gunFreeze)
	gridColumns = 2, gridGap = 0.03, phoneTileAspect = 2.3, -- phones: the gun grid scrolls, tiles this wide for their height
	 -- the Equipment popup's gun tiles (owner 2026-11-09: bigger, themed, every price shown)
	lockedGrey = 0.18, -- a gun you can't buy yet: its colour mixed this far toward grey (0.55 looked dull, owner 2026-11-16)
	buyCooldown = 0.4, -- seconds between two buys (spam is dropped; a double charge can't happen anyway)
	-- the gun's heat bar (0-1), kept on the server (GunService). Firing at a pet from an island one past the
	-- gun's heat fills it in overSeconds (under a Mythic's 4.5 s floor, so a gun one step short can't finish
	-- a Mythic or Secret); on islands it's made for, in okSeconds (it barely moves). Full = it steams for steamSeconds and can't fire. Not firing, it
	-- cools in coolSeconds. step = how finely clients hear about it (the arc round the aim ring).
	-- coolAfter = it starts cooling this long after the last shot.
	heatBar = { overSeconds = 4, okSeconds = 60, coolSeconds = 3, coolAfter = 0.3, steamSeconds = 2, step = 0.05 },
	maxRange = 0, -- the longest range of any gun (filled in below): the pet prompts' own reach on the server
	-- a pet too warm for your gun gives a small side shake (Animation Rules 2: shake), never a freeze
	tooWarmShake = { seconds = 0.3, amp = 0.22, speed = 40 },
	-- the part-built stand-in gun (until the image-to-3D guns arrive): longer and fancier each tier,
	-- one barrel tip per beam; fins from gun 3, a glowing ring from gun 5, a crystal from gun 9
	standIn = { barrel = 1.4, barrelPerGun = 0.07, tipRing = 0.24, finsFrom = 3, ringFrom = 5, gemFrom = 9 },
	-- the picked gun turning on the Equipment card (owner 2026-11-05: a 360 preview). Seconds per full
	-- turn (slower with Reduced motion), camera pitch (degrees, looking down), field of view, fit margin
	-- lockedFade = how see-through the black figurine of a gun you don't own is (owner 2026-11-12)
	preview = { spinSeconds = 6, spinSecondsReduced = 14, pitch = 14, fov = 30, margin = 1.0, tint = 0.72, lockedFade = 0.3 },
	-- a gun tile's picture: the gun itself, turned tileYaw degrees so it shows some depth; its window's
	-- left edge and width (shares of the tile) and the lock's size on it (share of the window)
	tileYaw = -28, tile = { viewX = 0.12, viewW = 0.24, lock = 0.42 },
	-- the card's stat panel: its height (share of the card), padding, and each row's label, bar and number
	-- pill; minFill keeps a tiny bar a pill, topLight / shine are the bar's gloss
	statCard = { height = 0.3, pad = 0.09, labelW = 0.25, trackX = 0.27, trackW = 0.5, trackH = 0.56, valueX = 0.81,
		minFill = 0.09, topLight = 0.45, shine = 0.62 },
}
for _, g in Config.guns.list do
	Config.guns.maxRange = math.max(Config.guns.maxRange, g.range)
end

-- Rebirth (Round 4 phase 7): part of the journey, not an ending. The first comes after island 2 and
-- every odd island after that has a rebirth gate (Config.world.rebirthGates). No cap: updates add gates.
--   resets: coins and the pan's Slots upgrade (upgrades.pen)
--   keeps:  pets, the index, guns, opened gates (reach), Look (and gear later)
--   also resets Cold Power (Cold Power remake, 2026-11-10); the +50% counts for coins and for training
--   gives:  +50% coin income per rebirth (no pan slot since 2026-11-05: the pan caps at 16), and its gun tier (the free
--           rebirth guns in Config.guns.list; the next island pair comes from the rebirth gates)
-- Cost (owner 2026-11-07, priced like hit games' rebirths: a real goal each time): each rebirth costs
-- about 5 minutes of the income you have when you reach it, so it's its own short save and the pairs
-- (3 + 4, 5 + 6) no longer come back to back. Rebirths past the list cost x costGrowth the one before.
-- Bought at the Rebirth Booth, decided on the server inside one data change. fullAt = the rebirth the
-- 4-8 hour "full game" ends on.
Config.rebirth = {
	incomePer = 0.5,
	slotsPer = 0, -- pan slots a rebirth adds (0 = none: the 16-slot pan comes from the Slots upgrade only)
	-- Retuned 2026-11-10 for Cold Power (gates cost no coins now, and training takes part of the time):
	-- GrindBot, typical player: island 2 in 11 min, Rebirth 1 in 35 min, everything in about 4.4 h
	-- balance pass 2026-11-12 (BALANCE-2026-11-12.md): Rebirth 1 at ~36 min, Rebirth 2 at ~67 min, then about one an hour
	-- pacing pass 2026-11-16 (PACING-2026-11-16.md): Rebirth 1 at ~34 min, Rebirth 2 at ~69 min, then one every
	-- 1-1.5 h; island 10 at ~8 h and the last buy at ~10 h (rarity pass 2026-11-17) for a typical kid (was everything in ~4.5 h)
	costs = { 5e6, 200e6, 1.5e9, 25e9, 400e9, 750e9, 15e12 }, -- Rebirth 1, 2, 3 ...
	costGrowth = 3,
	fullAt = 7,
	boothRange = 30, -- studs from the Rebirth Booth (the server's position)
	cooldown = 1, -- seconds between two tries
	typicalFactor = 1.5, -- a typical free player takes the playtest bot's time x this (Round 4 prompt 7)
	maxWait = 600, -- seconds of typical play: never longer than this without something to buy (Round 4 prompt 7)
	-- the popup (2026-11-09): shares of its body; barSteps = how often the coin bar redraws
	-- 2026-11-12 (owner: column words bigger): taller columns, a slimmer header strip, rows filling the column
	-- device QA 2026-11-13: the Rebirth button was 21 px tall on a phone; the foot grew (0.76 -> 0.68) and the
	-- columns gave up the room (0.5 -> 0.42)
	ui = { heroHeight = 0.2, colsTop = 0.24, colsHeight = 0.42, colWidth = 0.32, colGap = 0.02, colHead = 0.16,
		phone = { footTop = 0.6, colsHeight = 0.34 }, -- phones: a taller foot, so the Rebirth button is a thumb's size
		footTop = 0.68, barSteps = 20, itemHeight = 0.19,
		-- the banner (owner 2026-11-12: "make the writing bigger, change the arrow"): its words at the big role
		-- (x Config.ui.shop.bigText of a title), the painted arrow nudging right every arrowNudge seconds
		heroText = 0.82, arrowWidth = 0.11, arrowNudge = 1.1, arrowNudgeBy = 0.012 },
}

function Config.rebirthIncome(rebirths: number): number
	return 1 + Config.rebirth.incomePer * rebirths
end

-- the coins rebirth number n costs (n = 1 for the first)
function Config.rebirthCost(n: number): number
	local list = Config.rebirth.costs
	local i = math.clamp(math.floor(n), 1, #list)
	return Config.nice(list[i] * Config.rebirth.costGrowth ^ math.max(0, n - #list))
end

-- Gear (owner 2026-11-13, replaces the five "Coming soon" slots): bought once with coins at the Equipment
-- Booth's Gear tab, always on, kept through rebirth (saved in d.gear[key]; the server sets the player
-- attribute Gear_<key>, which the services read). One clear job each, cheapest first; prices fill the
-- saves between the big buys (BALANCE-2026-11-12 risk 4). shape = the silhouette on its card until the
-- painted icons exist.
--   Magnet Gloves: pick up your frozen pets from rangeMult x further
--   Ice Skates:    carrying pets home, x carrySpeed and no slowdown from a full load
--   Frost Boots:   pets you shoot run away at x fleeMult
--   Cooling Vest:  your gun heats up at x heatMult
--   Cozy Hat:      your pan's coins x coinMult
export type GearItem = { key: string, name: string, shape: string, price: number, text: string, [string]: any }
Config.gear = {
	{ key = "magnet_gloves", name = "Magnet Gloves", shape = "gloves", price = 250e3, text = "Grab frozen pets from far away", rangeMult = 2.5 },
	{ key = "ice_skates", name = "Ice Skates", shape = "skates", price = 1.5e6, text = "Faster when carrying pets home", carrySpeed = 1.2 },
	{ key = "frost_boots", name = "Frost Boots", shape = "boots", price = 25e6, text = "Pets run slower from you", fleeMult = 0.75 },
	{ key = "cooling_vest", name = "Cooling Vest", shape = "vest", price = 400e6, text = "Your gun heats up slower", heatMult = 0.6 },
	{ key = "cozy_hat", name = "Cozy Hat", shape = "hat", price = 1e12, text = "+10% coins from your pets", coinMult = 1.1 },
} :: { GearItem }

function Config.gearItem(key: string): GearItem?
	for _, g in Config.gear do
		if g.key == key then
			return g
		end
	end
	return nil
end

-- this gear's number for a player (from the Gear_<key> attribute the server sets), or `off` without it
-- owner 2026-11-15: Thaw Machines stand centred in the pan's back row: one in the middle, two side by side
-- round the middle. count = the plot's "Machines" attribute (PenService); returns the X offset from the plot centre.
-- owner 2026-11-15: "make insane models for the gear": painted Chunky Pop art per gear (prototype/
-- ice-ray-for-pets/icons/gear_<shape>.png), shown on the Equipment > Gear cards and the hotbar
Config.gearIcons = {
	magnet_gloves = "rbxassetid://125482225182830", ice_skates = "rbxassetid://74729644563221",
	frost_boots = "rbxassetid://137780570610075", cooling_vest = "rbxassetid://78634527461413",
	cozy_hat = "rbxassetid://132801452561040", gel = "rbxassetid://92227942664230",
} :: { [string]: string }

-- owner 2026-11-15: "did you make actual models for the gear so you can see it on your character":
-- GearWear (server) welds a chunky model of each owned gear onto the avatar, seen by everyone.
-- Colours match the painted gear art. sparkle = particles per second on each piece (kept low for phones).
Config.gearWear = {
	sparkle = 3,
	steel = Color3.fromRGB(205, 214, 228), steelDark = Color3.fromRGB(96, 104, 122), ice = Color3.fromRGB(110, 230, 255),
	gold = Color3.fromRGB(255, 196, 46), fur = Color3.fromRGB(250, 248, 240),
	gloves = { main = Color3.fromRGB(226, 38, 48), dark = Color3.fromRGB(150, 20, 34) },
	skates = { main = Color3.fromRGB(34, 196, 214) },
	boots = { main = Color3.fromRGB(92, 52, 170), fur = Color3.fromRGB(205, 210, 255) },
	vest = { main = Color3.fromRGB(40, 132, 235), dark = Color3.fromRGB(24, 60, 140) },
	hat = { main = Color3.fromRGB(255, 186, 30), cuff = Color3.fromRGB(232, 150, 20) },
}

-- owner 2026-11-15: each Index page shows a picture of its island behind the pets (Studio captures,
-- prototype/ice-ray-for-pets/index-zones/zone<id>.jpg); shade = a navy veil so the slots stay the loudest thing
Config.zoneArt = {
	images = {
		[1] = "rbxassetid://128742404878593", [2] = "rbxassetid://102683207719472", [3] = "rbxassetid://135606247453303",
		[4] = "rbxassetid://134067032992963", [5] = "rbxassetid://114874239519537", [6] = "rbxassetid://135940420082087",
		[7] = "rbxassetid://117806398354676", [8] = "rbxassetid://137792578962326", [9] = "rbxassetid://118928538142029",
		[10] = "rbxassetid://127890747322861",
	},
	shadeTop = 0.75, -- veil transparency at the top of the picture (1 = no veil)
	shadeBottom = 0.35,
	slotSeeThrough = 0.45,
	headSeeThrough = 0.3, -- the page's coloured name strip lets the island show through too -- the pet slots on a page are this see-through, so the island shows between and behind them
}

function Config.thawMachineOffset(m: number, count: number?): number
	return if (count or 1) >= 2 then (m - 1.5) * Config.thaw.machine.gap else 0
end

-- the "Machines" attribute of plot i (1 when the map or the attribute isn't there yet)
function Config.machineCount(plot: number): number
	local map = workspace:FindFirstChild("Map")
	local p = map and map:FindFirstChild("Plot" .. plot)
	local v = p and p:GetAttribute("Machines")
	return if typeof(v) == "number" then v else 1
end

function Config.gearValue(player: Player, key: string, field: string, off: number): number
	local g = Config.gearItem(key)
	return if g and player:GetAttribute("Gear_" .. key) == true then g[field] or off else off
end

-- Pan upgrades (Round 4 phase 5): three upgrades at your own pan's Pan Upgrades stand.
--   slots = how many pets your pan holds: the old "pen" upgrade (Config.upgrades.pen, saved in
--           upgrades.pen). Rebirth (phase 7) resets it.
--   cold  = Cold Level: the hottest island whose pets your pan keeps frozen, as that island's place
--           in Config.world.islands (saved in pan.cold; the same scale as a gun's Cold stat). A pet
--           from a hotter island can't go in: its cube bounces back and the gauge flashes the level
--           it needs. It only goes as far as the open islands. Rebirth keeps it.
--   look  = straw -> wood -> stone -> crystal ice -> aurora (saved in pan.look; colours Theme.panLooks).
--           Rebirth keeps it.
-- Bought like guns: decided on the server at the stand, checked again inside the one data change that
-- charges, plus a cooldown. Prices (GrindBot, repriced 2026-11-07): Cold Level n = island n's gate, Slots x6 a
-- rebirth (all through Config.nice); each Look sits in a stretch that had nothing to buy (Wood 40K before Rebirth 1).
Config.pan = {
	-- Cold Power remake (2026-11-10): the Cold Level upgrade is gone (the pan keeps every pet frozen).
	-- coldRefund = what each level cost (island n's old gate coins); DataService pays it back on load,
	-- once, for levels above coldStart.
	-- trainer: your pan's Cold Power trainer (Config.training.stations). owner 2026-11-13: + Thaw (the Thaw
	-- Machine's wait -10% a level); rebirth keeps it. Speed was sold here too until 2026-11-15 (now Gear only).
	order = { "slots", "thaw", "trainer", "look" },
	-- the price of level 2, 3 ... 10 (cheap at first: a buy every minute or two in the first half hour)
	thawPrices = { 250, 1e3, 4e3, 200e3, 1e6, 5e6, 200e6, 2.5e9, 75e9 }, -- pacing + rarity pass 2026-11-16/17
	-- what Speed level 2, 3 ... 10 cost while it was sold: DataService pays these back once and resets the level
	speedRefund = { 120, 500, 2e3, 7.5e3, 30e3, 200e3, 2e6, 20e6, 250e6 },
	coldStart = 2,
	coldRefund = { [3] = 7500, [4] = 2e6, [5] = 6e6, [6] = 30e6, [7] = 100e6, [8] = 250e6, [9] = 750e6, [10] = 3e9 } :: { [number]: number },
	names = { slots = "Slots", look = "Look", trainer = "Trainer", thaw = "Thaw Speed" } :: { [string]: string },
	standRange = 16, -- studs from your own Pan Upgrades stand (the server's position)
	buyCooldown = 0.4,
	looks = {
		{ key = "garden", name = "Garden", price = 0 }, -- Round 5: white fences on a striped lawn (was straw)
		{ key = "wood", name = "Wood", price = 500e3 }, -- each fills a save (pacing pass 2026-11-16)
		{ key = "stone", name = "Stone", price = 30e6 },
		{ key = "ice", name = "Crystal Ice", price = 7.5e9 },
		{ key = "aurora", name = "Aurora", price = 6e12 },
	} :: { { key: string, name: string, price: number } },
	crystalEvery = 2, -- crystal ice: a crystal on every 2nd fence post
	auroraSpeed = 0.2, -- aurora: the rails' colours drift this many cycles a second
	drawDistance = 160, -- studs: pans farther than this keep their look but stop animating
	-- owner 2026-11-13: the new Look showed for a split second before its animation. From the Look card's
	-- Buy press your pan keeps its old Look until the pieces pop off; if no upgrade comes within this
	-- many seconds (refused, lost), it lets go and shows whatever the server says.
	holdLook = 5,
}

-- what the next level of a pan upgrade costs (nil = at the top)
function Config.panMax(kind: string): number
	if kind == "slots" then
		return Config.upgrades.pen.maxLevel
	end
	if kind == "trainer" then
		return #Config.training.stations
	end
	if kind == "thaw" then
		return #Config.pan.thawPrices + 1
	end
	return #Config.pan.looks
end


function Config.panPrice(kind: string, level: number, rebirths: number?): number?
	if level >= Config.panMax(kind) then
		return nil
	elseif kind == "slots" then
		return Config.slotsCost(level + 1, rebirths or 0)
	end
	if kind == "trainer" then
		local st = Config.training.stations[level + 1]
		return if st then st.price else nil
	end
	if kind == "thaw" then
		return Config.pan.thawPrices[level]
	end
	local look = Config.pan.looks[level + 1]
	return if look then look.price else nil
end

-- the Sell Booth (Round 4 phase 5): sell pets from your pan or Storage for coins. A pet sells for this
-- many minutes of its own income (its pose and mutation count, and a tester's money multiplier; the Index bonus doesn't).
-- Epic and up ask first; identical pets (same pet, pose and mutation) can be sold in one go.
Config.sell = {
	incomeMinutes = 5,
	confirmFromRank = 4, -- Epic
	boothRange = 30, -- studs from the Sell Booth (the server's position)
	cooldown = 0.35, -- seconds between two sales (spam can't sell a pet twice anyway: it's gone)
	maxPerSale = 500,
	-- the popup (2026-11-09): pet tiles, columns to a row; rowAspect = a row's width / height; the card's
	-- pet window is this share of the card's height
	columns = 4, phoneColumns = 3, tileGap = 0.03, rowAspect = 3.1, windowHeight = 0.38,
}

function Config.sellValue(income: number, mult: number?): number
	return math.max(1, math.floor(income * 60 * Config.sell.incomeMinutes * (mult or 1)))
end

-- the fast pan upgrade (owner 2026-11-05: a reference clip, then prototype/ice-ray-for-pets/upgrade-demo.html).
-- 0.9 s in the popup, which stays open: a build-up on the press (it also hides the server's answer
-- time), the impact when the answer lands, a spring settle and a shimmer. Buying again works from
-- 0.45 s. A new Look answers at the pan, a new Trainer at the trainer (below). Times in seconds from the impact unless
-- said; reduced motion halves them. fastPan = false brings back the long camera show below.
Config.motion = {
	-- a compact world prompt (Pick up on a frozen pet) pops up off the cube (Animation Rules: pop, Back Out)
	promptPop = 0.25,
	upgrade = {
		fastPan = true,
		build = 0.18, buildScale = 0.92, buildTilt = -2, cardBuild = 0.97, -- from the press
		shiverDeg = 1.2, shiverHz = 26, maxWait = 1.5, -- a slow server: hold with a tiny shiver; no answer by maxWait = let go
		pop = 0.08, popScale = 1.15, cardPop = 1.05, peakHold = 0.055,
		settle = 0.4, springK = 4, springW = 1.5, -- 1 + a * e^(-k x) * cos(w pi x) (Animation Rules 4)
		flash = 0.3, flashCool = 0.15, flashAlpha = 0.9, -- white cooling into the upgrade's colour
		glow = 0.52, glowStroke = 4, -- the card's outline glows in that colour
		ring = 0.25, ringGrow = 0.7, sparks = 16, sparksBig = 28, motes = 10, chipPop = 0.2,
		inputOpen = 0.27, shimmerAt = 0.42, shimmer = 0.25, total = 0.72,
		chimes = { 0.14, 0.22, 0.3 }, streakReset = 1.5, streakMax = 7, -- each buy within streakReset plays a semitone higher
		flashSoftGap = 0.5, flashSkipGap = 0.34, -- kid-safe: never more than 3 flashes a second
		reduced = { time = 0.5, popScale = 1.05, buildScale = 0.97, cardPop = 1.02, flashAlpha = 0.35 },
		pan = { expand = 0.25, fillFrom = 0.2, fillFull = 0.3, holdTo = 0.45, fadeTo = 0.8, light = 6, lightRange = 40,
			popOff = 0.12, dropIn = 0.4, burst = 22, burstBig = 36,
			strength = { slots = 0.75, cold = 0.85, look = 1 } :: { [string]: number } },
		-- the front view (owner 2026-11-07, the reference clip): when the answer lands the popup and HUD
		-- hide, the camera glides to the front of your pan, the pan upgrades there, the camera glides
		-- back and the popup returns, where the card then pops. Seconds; reduced motion halves them.
		-- frontView = false keeps the camera on you and the popup open (the 0.9 s version).
		-- owner 2026-11-13: the front view and the pan's floor flash are the Look upgrade's only; Slots,
		-- Thaw Speed and Speed just pop their card, and the Trainer has its own view (trainerTrip).
		frontView = true,
		trip = { go = 0.45, watch = 0.9, back = 0.4, -- glide there, watch the pan, glide home
			camBack = 24, camUp = 13, lookUp = 1, lookIn = 0.42 }, -- studs in front of the pan's front edge, height; looks this far into the pan
		-- the Trainer's transformation (owner 2026-11-13: "for the trainers make separate animation, the camera
		-- should show their transformation with a clean transition", Show.trainerTrip): the popup and HUD hide,
		-- the camera glides to where you stand at your trainer (go), the old trainer glows white and shivers
		-- (charge), shrinks into a flash and a burst (swap), the new one grows in with a spring as the glow
		-- leaves it and its name pops up (grow), you look at it (watch), the camera glides home (back).
		-- Seconds; reduced motion halves them and drops the shiver. trainerView = false: the card pop only.
		trainerView = true,
		trainerTrip = { go = 0.5, charge = 0.7, swap = 0.16, grow = 0.5, watch = 1.1, back = 0.45,
			-- studs from the trainer's middle, on the side you stand. Up high over the pan's fence: at 6.5 high its
			-- posts filled the bottom of the shot; at 10 back the name covered the trainer's top. arc = how far
			-- the glides there and back rise in the middle, so they pass over the fence instead of through it.
			camBack = 15, camUp = 11, camSide = -2, lookUp = 5, arc = 6,
			glow = 0.85, shiverDeg = 2.5, shiverHz = 18, shrinkTo = 0.3, growFrom = 0.3, burst = 36,
			waitNew = 1.5 }, -- longest wait for the server's new trainer after the swap
	},
}

-- a pan upgrade's show (Animation Rules 3): a glow builds up on the pan, the old pieces pop off, new
-- ones drop in with a squash, a burst and a sound, coins fly from your counter into the pan. The server
-- has already charged and upgraded; the show only plays it. Bigger upgrades get longer shows.
Config.show.panUpgrade = {
	beats = {
		{ name = "glow", time = 0.6 },
		{ name = "popOff", time = 0.45 },
		{ name = "dropIn", time = 0.75, keepOnSkip = true }, -- SKIP keeps the new pieces landing
		{ name = "burst", time = 0.35, keepOnSkip = true },
		{ name = "coins", time = 0.6 },
		{ name = "rest", time = 0.35 },
	} :: { Beat },
	kindScale = { slots = 0.6, cold = 0.85, look = 1.25 } :: { [string]: number }, -- a new look is the biggest
	perLevel = 0.05, maxScale = 1.9, -- and each level a little longer than the last
	camBack = 30, camUp = 17, camLookUp = 1, -- the camera looks at your pan from the plaza
	dropHeight = 7, squash = 0.4, popSpeed = 16, popUp = 10, popSpin = 7,
	glowTransparency = 0.35, burstParts = 26, coins = 8, coinSize = 0.07,
	title = { slots = "MORE SLOTS!", cold = "COLDER PAN!", look = "NEW LOOK!" } :: { [string]: string },
}

-- a rebirth, remade 2026-11-12 (owner: "it needs to be very good, sfx vfx all the things"; references in
-- the vault: Research/Reference Clips 2026-11-12). A short film in beats (CLAUDE.md opening animations):
-- title card, a rune stage under you, your coins flying in, three charge pulses, one burst, the reveal
-- (REBIRTH n letter by letter over a sunburst, then coin x1 -> x1.5), and back. The server has already
-- rebirthed and saved; the show only plays it. SKIP from the second rebirth jumps to the reveal;
-- reduced motion halves every beat, slows the camera and drops the kick and the flash.
Config.show.rebirth = {
	beats = {
		{ name = "title", time = 0.9 },
		{ name = "gather", time = 1.3 },
		{ name = "drain", time = 1.2 },
		{ name = "charge", time = 2.1 },
		{ name = "burst", time = 0.5 },
		{ name = "reveal", time = 3.0, keepOnSkip = true }, -- SKIP still shows what you got
		{ name = "back", time = 0.6, keepOnSkip = true },
	} :: { Beat },
	angle = 40, -- the camera starts this many degrees round from "straight away from the booth"
	-- the camera swings gently on the open side of the booth (never round behind it, where walls are):
	-- start far and low, creep in each pulse, end close. swing = degrees each side, swingSeconds = one sway
	-- revealLook: during the reveal the camera looks this far below your middle, so you sit in the top half
	-- of the screen above the words
	orbit = { startRadius = 18, startHeight = 2.5, endRadius = 12, endHeight = 5.5, lookHeight = 2, revealLook = -3.2, swing = 28, swingSeconds = 9, reducedSwing = 8, follow = 3 },
	pillar = { width = 2.6, alpha = 0.55, height = 70, rise = 0.25, seconds = 2.2 }, -- thin and see-through, so you stay visible
	-- the rune stage: a glowing disc and three rings (radius, width, segments, turns a second, dashed)
	discRadius = 12.5, discAlpha = 0.72,
	rings = {
		{ radius = 5.5, width = 0.55, segments = 30, spin = 0.12, dashed = false, colour = "rebirth" },
		{ radius = 8, width = 0.4, segments = 36, spin = -0.08, dashed = true, colour = "gold" },
		{ radius = 10.6, width = 0.28, segments = 44, spin = 0.05, dashed = false, colour = "ice" },
	},
	motes = 22, -- rising sparks a second (halved on Low graphics)
	coins = 12, coinRadius = 11, coinFly = 0.75, coinSize = 1.2, -- your coins fly in over the drain beat (coinSize: studs across)
	pulses = 3, pulseRadius = 15, pulseSpin = 1.1, kick = 0.22, -- each pulse speeds the rings up by pulseSpin
	star = { from = 2.5, to = 9, height = 6.5 }, -- the star flare over your head (studs)
	hum = { from = 0.7, to = 1.6 }, -- the charge hum's pitch
	burstParts = 60, confetti = 90, rays = 12,
	-- the reveal: text low on the screen so you stay in view (shares of the screen height)
	reveal = { y = 0.68, small = 0.045, big = 0.12, line = 0.07, letterGap = 0.12, spaceWidth = 0.35, sunburst = 0.95, sunSpin = 0.04 },
	titleCard = { word = "REBIRTH", line = 0.42, caption = "Everything gets stronger" },
}

-- ---------- Round 5 (owner 2026-11-02, prototype/ice-ray-for-pets/ROUND5-PROMPT.md) ----------
-- Shooting the ray: hold the mouse / your finger on a target (E or gamepad R2 aims at the nearest one
-- in front of you). Every target has a freeze meter on the server: it rises while someone aims at it
-- (1 / the freeze's seconds, Config.show.freeze, x timeScale) and melts back when nobody does. Up to
-- stuckAt a pet is scared and runs away; from stuckAt on it is stuck in the ice; at 1 the cube shuts.
Config.aim = {
	tickSeconds = 0.1,
	timeScale = 2.2, -- a shot freeze takes this much longer than the old prompt hold (time to see it run)
	-- harder chase (owner 2026-11-13: "the minigame is too easy", after a reference clip where the pet runs
	-- round while you hold the ray on it): pets run longer (stuckAt 0.5 -> 0.7), faster, rarer ones faster
	-- still (fleeTier, x fleeSpeed; Mythic and Secret use Config.spawner.motion), they dodge (zig-zag) while
	-- they run, and the ice melts back quicker when you lose them (0.3 -> 0.4)
	thawPerSecond = 0.4, -- meter lost each second nobody aims at it
	stuckAt = 0.7,
	fleeSpeed = 6, -- studs a second while scared (wandering is Config.spawner.wanderSpeed; you walk Config.player.walkSpeed)
	fleeTier = { Common = 1, Uncommon = 1.15, Rare = 1.35, Epic = 1.6, Legendary = 1.9 } :: { [string]: number },
	dodge = { zigzag = 0.55, swerveEvery = 0.6 }, -- every scared pet below Mythic swerves this much (radians)
	rangeGrace = 2, -- studs past the gun's range the server still accepts (lag)
	pickRadius = 0.12, -- a click / touch picks the nearest target this close on screen (share of the short side)
	autoAimDot = 0.3, -- E / R2: only targets in front of the camera (dot product) within range
	closerHintRange = 30, -- studs: a shot that reaches nothing says "Get closer!" if a pet is this near (QA 2026-11-08; value restored 2026-11-09, a guess)
	keys = { Enum.KeyCode.E, Enum.KeyCode.ButtonR2 },
	sendEvery = 0.1, -- the client sends a changed aim at most this often
	step = 0.02, -- the meter reaches clients in steps of this size
	refreezeSeconds = 0.6, -- zapping a dazed pet back
	reticle = 0.16, -- the aim ring on the nearest target, a share of the screen's short side
	-- the ring sits reticleFront x the target's width toward the camera (+0.6 studs), so its body doesn't
	-- cover it, and reticleLift studs up, so the ground doesn't cut its "CLICK" hint
	reticleFront = 0.9, reticleLift = 0.9,
}

-- the hotbar (bottom middle): tap a slot to hold that thing, tap it again to put it away
Config.hotbar = {
	slots = {
		{ id = "ray", label = "Ice Ray", key = Enum.KeyCode.One },
		{ id = "gel", label = "Slow Gel", key = Enum.KeyCode.Two },
	},
	gamepadPrev = Enum.KeyCode.ButtonL1, gamepadNext = Enum.KeyCode.ButtonR1,
	size = 0.12, gap = 0.018, bottomInset = 0.025, -- shares of the screen's short side
}

-- Slow Gel (Gear tab of the Equipment Booth): equipped, click / tap throws a puddle; pets and Heat
-- Critters in it move at x slow. A cooldown, no ammo.
-- price: a goal on the way to Rebirth 1, just before island 3 brings the Heat Critters it slows (was 3,000)
Config.gel = { price = 1e6, -- 1M (rarity pass 2026-11-17): fills the Rebirth 1 save
	 slow = 0.6, radius = 7, seconds = 6, cooldown = 10, throwRange = 45, flySeconds = 0.45 }

-- the Thaw Machine in every pan (owner 2026-11-09): a cube you bring home goes into your Pets as a
-- frozen pet. You walk to your Thaw Machine and put one in; when its time is up the pet hops out,
-- wanders your pan and starts earning. The time is saved (os.time), so it keeps thawing while you're away.
-- time = seconds[tier] x sizeFactor[size] x mutFactor[mutation] x islandGrowth^(island - 1), then / the
-- pan's thaw speed (each Slots level x perLevel faster). A Secret from island 1 takes 30 min (M size, no
-- mutation, Slots level 1); each island further out takes x islandGrowth longer. A second machine comes
-- with Slots level secondAt.
Config.thaw = {
	-- juicy first half hour (owner 2026-11-13, "like Throw Food for Pets"): the low tiers thaw fast
	-- (was 15 / 30 / 60 / 180 / 360) so the catch -> thaw -> earn loop turns over every minute or so;
	-- Mythic and Secret stay the long waits
	-- owner 2026-11-16 ("the pets unfreeze very hard"): about a third shorter again
	seconds = { Common = 4, Uncommon = 8, Rare = 20, Epic = 60, Legendary = 150, Mythic = 480, Secret = 1200 } :: { [string]: number },
	sizeFactor = { S = 0.85, M = 1, L = 1.2 } :: { [string]: number },
	mutFactor = { Frosty = 1.2, Golden = 1.5, Starry = 2 } :: { [string]: number },
	islandGrowth = 1.3, -- island 2 x1.3, island 3 x1.69, island 8 x6.3
	upgradeFactor = 0.9, -- the Thaw Speed upgrade: each level makes every thaw 10% shorter (x0.39 at level 10)
	swapWeakest = true, -- pan full: a thawed pet that earns more takes the weakest pan pet's place (that one goes to Storage)
	useRange = 14, -- studs from the machine's pad the server accepts "put this pet in"
	perLevel = 1.33, -- 7 Slots levels: about x5.5 at the top, as fast as the old 19 levels at x1.1
	secondAt = 3, -- the second machine comes with Slots level 3 (~3 min in; was level 6), two thaws at once early (2026-11-13)
	tickSeconds = 0.25,
	-- machine 1 from the middle of the pan's back fence (x across, z toward the door); machine 2 is gap
	-- further right. padTop: the cube sits on the raised heat pad this high. haloY / haloRadius: the
	-- floating ring over the pad (MapArt builds it, ThawMachines spins it)
	machine = { x = -6.25, z = 5.5, gap = 8.5, padTop = 0.75, haloY = 6.5, haloRadius = 2.55 },
	queueGap = 3.4, queueX = 2.4, queueFrom = 5.5, -- waiting cubes line up along the left fence (queueX in from it), from the machine toward the door
	queueShown = 8, -- at most this many waiting cubes are drawn
	-- owner 2026-11-13: a pet whose time is up waits in its machine until you press Claim there (a READY!
	-- sign over the machine); a Secret gets the luck reveal (Config.show.reveal)
	firstPops = true, -- a player's very first pet comes out by itself, with Show.thawReveal (Config.show.firstReveal); Claim from the 2nd on
	-- owner 2026-11-16 ("it doesn't really unfreeze ... not having to press E"): a pet whose time is up pops out by
	-- itself again; a timer over each busy machine shows the time left (ThawMachines). true = the old Claim button
	claimByHand = false, claimCooldown = 0.5,
	timerSign = { lift = 5, size = { 5.2, 2 }, drawDistance = 90 }, -- lift: studs over the machine's top readySign = { y = 9.5, size = { 6, 2.2 }, bob = 0.35, bobSpeed = 2.4 },
	-- Skip with Robux (owner 2026-11-12, at the machine only, never in the Shop): a big purple Skip bar under
	-- the pet in a busy machine's popup. Waiting is always free. One price (owner 2026-11-16: "make the skip
	-- in the thaw for like 99"; it was 5/15/29/49 stepped by the time left): the first tier whose upTo covers
	-- the time left. productId 0 = not made yet (free in Studio, "Not available yet" live). A skip bought just
	-- as the pet came out by itself is kept as a free skip (thawSkips), so Robux is never lost. minLeft: no
	-- bar under this. retired: the old stepped products, still granted if a purchase of one arrives late.
	skip = {
		tiers = {
			{ upTo = math.huge, robux = 99, productId = 0 },
		} :: { { upTo: number, robux: number, productId: number } },
		retired = { [3732434857] = 5, [3732434877] = 15, [3732434893] = 29, [3732434908] = 49 } :: { [number]: number },
		minLeft = 10,
		cooldown = 1,
		-- Unfreeze all (owner 2026-11-16, like the reference's SKIP ALL bar; in Pets only): one product thaws
		-- every pet still in its cube at once, in a machine or waiting in your Pets. The bar sits under those
		-- pets once minPets are frozen. Bought with nothing left frozen = kept for later (thawSkipAlls).
		all = { robux = 199, productId = 0, minPets = 1 },
	},
	wander = { speed = 2.4, pause = { 1.5, 4.5 }, margin = 2.5 }, -- thawed pets stroll around the pan (drawn on each client)
	-- the machine coming to life on each client (ThawMachines): idle it breathes in ice blue; thawing,
	-- the heat climbs from ice blue through amber to hot orange as the time runs out, every light,
	-- beam and gauge following it; the pet's release is one burst. Kid-safe: smooth pulses, no strobes.
	fx = {
		drawDistance = 120, -- nothing moves beyond this (phones)
		scanEvery = 0.25, -- how often each machine looks for the cube it's thawing
		heatFollow = 5, -- how fast the shown heat catches up with the real progress (per second)
		chase = { idle = 2.5, from = 6, to = 22, tail = 3 }, -- the rim lights' running light: steps a second idle, active from -> to as it heats; lit tail length
		halo = { idleSpin = 0.35, spinFrom = 1.2, spinTo = 4.2, bob = 0.12, bobSpeed = 1.1, innerSpin = -1.6 }, -- radians a second; the inner ring turns the other way
		gauge = { idleLevel = 0.06, breathe = 0.03 }, -- the core tube's fill while idle (share of its height)
		pulse = { speed = 2.2, beam = 0.25, strip = 0.35 }, -- the beams' and pylon strips' soft pulse (Hz, depth)
		beam = { from = 0.16, to = 0.34, transparency = 0.25 }, -- widths at the emitter and at the cube
		beacon = { idle = 0.5, active = 1.2 }, -- the antenna light's slow pulse (Hz), never a strobe
		light = { range = 12, idle = 0.35, from = 0.9, to = 2.4 },
		steam = { idle = 1.2, from = 3, to = 12 }, -- puffs a second from the two stacks
		mist = { from = 5, to = 16 }, -- melt vapour off the cube while it thaws
		burst = { sparks = 26, mist = 18, ring = 0.55, ringFrom = 3, ringTo = 10, flash = 0.6, outFor = 2.2 },
		scanline = 2.6, -- seconds for the screen's scan line to sweep down
	},
}

-- Heat Critters (island 3 and on): hot, cheeky animals that want your ice cube to cool off. They chase
-- whoever carries a cube on their own island (each stays inside its island, so a long trip home is a
-- relay), knock the top cube loose if they reach you (its pet is dazed: only you can zap it back), and
-- can be frozen with the ray for frozenBase / the island's heat seconds.
Config.chasers = {
	fromIsland = 3,
	perIsland = 3,
	wanderSpeed = 3,
	chaseSpeed = 13, -- a bit slower than walking (16), so you can always get away
	aggroRange = 45,
	catchRange = 3.5,
	afterCatch = 4, -- seconds a critter sits happily cooling down after a catch
	freezeSeconds = 1.6, -- with gun 1 (the gun's power speeds it up, like pets)
	frozenBase = 10, -- seconds frozen = frozenBase / island heat (hotter = shorter)
	frozenMin = 3, frozenMax = 20,
	size = 3.2,
	look = { pet = "conehog" } :: { [string]: string }, -- which pet's art a critter wears until its own art exists
}

-- Ray-tag (owner 2026-11-02, overrides the old "no theft" rule): shoot a player who carries a cube and
-- their meter fills; at 1 they tumble over and their top cube pops out as a dazed pet anyone can zap.
-- Never in the hub, never your banked pets; a shield for a new player's first minutes of play (two-way: you
-- can't tag anyone while you have it) and a short one after you've been tagged.
Config.tag = {
	freezeSeconds = 1.4, -- with gun 1
	thawPerSecond = 0.5,
	ragdollSeconds = 2.2,
	shieldMinutes = 15, -- of play time, once per player (saved), not per server
	afterTagShield = 10, -- seconds
}

-- Codes (Settings): unlocked after catching needPets pets. The codes themselves live on the server only
-- (ServerStorage.Codes), so nobody can read them from the client.
Config.codes = { needPets = 25, maxLength = 20, cooldown = 1.5 }

-- how full a gun card's bar is for this stat (0-1). Training runs x1 to x100, so it's on a log scale:
-- on a straight bar the early guns would all look empty.
function Config.gunStatShare(stat: string, value: number): number
	local max = Config.guns.statMax[stat] or 1
	if stat == "training" then
		return math.clamp(math.log(value + 1) / math.log(max + 1), 0, 1)
	end
	return math.clamp(value / max, 0, 1)
end

-- the gun a player holds (1 when the number is missing or out of range)
function Config.gun(index: number?): Gun
	local list = Config.guns.list
	return list[math.clamp(math.floor(tonumber(index) or 1), 1, #list)]
end

function Config.tier(name: string): Tier
	for _, t in Config.tiers do
		if t.name == name then
			return t
		end
	end
	error("unknown tier " .. name)
end

-- Round prices (owner 2026-11-07: "make the prices eye appealing"). Every price a player pays lands on
-- a round number, the way hit games price things (Grow a Garden seeds 400 / 2,500 / 50K / 1M, Steal a
-- Brainrot rebirths 1M / 5B): 1, 1.2, 1.5, 2, 2.5, 3, 4, 5, 6 or 7.5 times a power of ten. Prices worked
-- out from a formula go through Config.nice; prices typed in here are picked from the same steps.
Config.niceSteps = { 1, 1.2, 1.5, 2, 2.5, 3, 4, 5, 6, 7.5, 10 }
function Config.nice(n: number): number
	if n < 1 then
		return 0
	end
	local p = 10 ^ math.floor(math.log10(n))
	local m, best = n / p, 1
	for _, s in Config.niceSteps do
		if math.abs(math.log(m / s)) < math.abs(math.log(m / best)) then
			best = s
		end
	end
	return math.round(best * p)
end

-- a coin amount for prices and "need more": 750 / 2.5K / 40K / 1.2M / 7.5B. Never shows less than the
-- real amount (rounds up), so "Need 1.3M more" is always enough.
Config.coinUnits = { { size = 1e27, suffix = "Oc" }, { size = 1e24, suffix = "Sp" }, { size = 1e21, suffix = "Sx" }, { size = 1e18, suffix = "Qi" }, -- Cold Power is endless
	{ size = 1e15, suffix = "Qa" }, { size = 1e12, suffix = "T" }, { size = 1e9, suffix = "B" },
	{ size = 1e6, suffix = "M" }, { size = 1e3, suffix = "K" } }
function Config.coinText(n: number): string
	n = math.max(0, math.ceil(n))
	local units = Config.coinUnits
	for i, u in units do
		if n >= u.size then
			local v = n / u.size
			if math.ceil(v) >= 1000 and i > 1 then -- 999,999 reads 1M, not 1000K
				return "1" .. units[i - 1].suffix
			end
			local text = if v >= 100 then tostring(math.ceil(v)) else string.format("%.1f", math.ceil(v * 10 - 1e-9) / 10)
			return (text:gsub("%.0$", "")) .. u.suffix
		end
	end
	return tostring(n)
end

-- a Cold Power amount you HAVE or GAIN: the whole number up to 99,999, then short (45.2M). It never
-- shows more than the real amount (rounds down), where coinText (prices, "need more") rounds up.
function Config.powerText(n: number): string
	n = math.max(0, math.floor(n))
	if n < 1e5 then
		local s = tostring(n):reverse():gsub("(%d%d%d)", "%1,"):reverse()
		return (s:gsub("^,", ""))
	end
	for _, u in Config.coinUnits do
		if n >= u.size then
			local v = n / u.size
			local text = if v >= 100 then tostring(math.floor(v)) else string.format("%.1f", math.floor(v * 10 + 1e-9) / 10)
			return (text:gsub("%.0$", "")) .. u.suffix
		end
	end
	return tostring(n)
end

function Config.upgradeCost(id: string, level: number): number
	local u = Config.upgrades[id]
	return Config.nice(u.baseCost * u.costGrowth ^ (level - 2)) -- level 2 costs baseCost
end

-- the pan's Slots upgrade (upgrades.pen) after some rebirths: rebirth resets Slots, and each rebirth
-- makes the rebuild cost x rebirthGrowth more (still x costGrowth a level), so it fills the wait after a rebirth
function Config.slotsCost(level: number, rebirths: number): number
	local u = Config.upgrades.pen
	return Config.nice(u.baseCost * u.costGrowth ^ (level - 2) * u.rebirthGrowth ^ rebirths)
end

-- how many pets the pan holds at a Slots level (+ Config.rebirth.slotsPer a rebirth), never over maxSlots
function Config.panSlots(level: number, rebirths: number): number
	local n = Config.pen.baseSlots + Config.upgrades.pen.slotsPerLevel * (level - 1) + Config.rebirth.slotsPer * rebirths
	return math.min(n, Config.pen.maxSlots)
end

function Config.cubeSizeFactor(rayLevel: number): number
	local c = Config.upgrades.ray.cubeSize
	local n = rayLevel - 1
	return 1 + c.early * math.min(n, c.earlyLevels) + c.late * math.max(0, n - c.earlyLevels)
end

-- how long a pet takes in the Thaw Machine (seconds); panLevel = the pan's Slots level (upgrades.pen),
-- thawLevel = the Thaw Speed upgrade (pan.thaw): each level x upgradeFactor (-10%)
function Config.thawSeconds(tier: string, size: string, zone: number, mut: string?, panLevel: number, thawLevel: number?): number
	local T = Config.thaw
	local base = (T.seconds[tier] or 15) * (T.sizeFactor[size] or 1) * (if mut then T.mutFactor[mut] or 1 else 1)
	local far = T.islandGrowth ^ math.max(0, zone - 1)
	local upgrade = T.upgradeFactor ^ math.max(0, (thawLevel or 1) - 1)
	return math.max(1, math.round(base * far * upgrade / (T.perLevel ^ math.max(0, panLevel - 1))))
end

-- the Robux price step for skipping a thaw with this many seconds left
function Config.thawSkipTier(secondsLeft: number): { upTo: number, robux: number, productId: number }
	local tiers = Config.thaw.skip.tiers
	for _, t in tiers do
		if secondsLeft <= t.upTo then
			return t
		end
	end
	return tiers[#tiers]
end

-- "45s", "12m", "1h 5m": a thaw time, short enough for a button
function Config.timeText(seconds: number): string
	local s = math.max(0, math.ceil(seconds))
	if s < 60 then
		return `{s}s`
	elseif s < 3600 then
		local m, r = s // 60, s % 60
		return if m < 10 and r > 0 then `{m}m {r}s` else `{m}m`
	end
	local h, m = s // 3600, (s % 3600) // 60
	return if m > 0 then `{h}h {m}m` else `{h}h`
end

function Config.zone(id: number): Zone?
	for _, z in Config.world.zones do
		if z.id == id then
			return z
		end
	end
	return nil
end

-- ---------- Cold Power (core loop remake, owner 2026-11-09; prototype/ice-ray-for-pets/COLD-POWER-DESIGN.md) ----------
-- One endless stat, never spent, trained in the Frost Training Yard (Config.training). It opens islands (each island's `need`),
-- and the further it is above an island's need the faster that island's pets freeze, up to maxSpeed:
-- speed = sqrt(power / need), so 4x the need is 2x faster and 25x the need hits the cap. Island 1 has
-- no need, so its speed is measured against speedFloor. minSeconds = the freeze time no amount of
-- power can skip, per rarity (real seconds with the ray on the pet). Past the last island the next
-- "need" (power levels, pack sizes) keeps growing x needGrowth, so training never runs out.
Config.coldPower = {
	max = 1e30,
	maxSpeed = 5,
	speedFloor = 50,
	needGrowth = 20,
	minSeconds = { Common = 0.5, Uncommon = 1, Rare = 1.5, Epic = 2.5, Legendary = 3.5, Mythic = 4.5, Secret = 6 } :: { [string]: number },
}

-- Cold Power training (owner 2026-11-10, replaces the sky rink; from the owner's references: hit
-- simulators' training dummies with a big "xN" over them, and a piece of training gear in every base).
-- Every pan has its own trainer, in front of it right of its door, and only its owner trains there. Stand
-- on it and your gun shoots the target by itself, one frost bolt every autoEvery seconds (autoPass with
-- the Full-Speed Auto-Train pass). Every click / tap / R2 / E fires one more (at most clickMax a second
-- count), so clicking is always the best rate. Each bolt is Cold Power (Config.trainGain); every
-- shatterHits bolts the target frosts over completely and shatters for shatterBonus bolts more.
-- Nothing to lose and no clock.
-- The trainer is a pan upgrade (Config.pan.order "trainer", saved in pan.trainer, rebirth keeps it):
--   stations = its levels: kind = its look (TrainingArt, Theme.training.stations[kind]), mult = its xN,
--              price = coins at your Pan Upgrades stand. Each one hotter and grander, like the islands.
--   aimY / shell: where the bolts land (studs over the pad) and the frost crust that climbs the target
--              as you shoot it (bottom over the pad, full height, width)
--   levelValue: every island need you've passed makes each bolt worth x levelValue (Config.powerLevel)
--   spot     = the pad's middle from the pan's door (x along the front, z out toward the plaza). padSize =
--              (x, z) studs, a few studs clear of the fence. It faces away from the pan (owner 2026-11-10):
--              the open side toward the pan, the target targetZ studs out toward the plaza, and you stand
--              round standZ facing it, your back to your pets.
export type TrainStation = { id: string, name: string, kind: string, mult: number, price: number, aimY: number,
	shell: { bottom: number, height: number, width: number } }
Config.training = {
	stations = {
		{ id = "snowman", name = "Snowman Dummy", kind = "snowman", mult = 1, price = 0, aimY = 4.4, shell = { bottom = 0.9, height = 8.4, width = 4.6 } },
		-- v3 (owner 2026-11-12): nine themed levels after the snowman, each its own gate and target (TrainingArt)
		-- prices: pacing pass 2026-11-16 (spread through the saves, PACING-2026-11-16.md)
		{ id = "peppermint", name = "Peppermint Pal", kind = "peppermint", mult = 2, price = 15e3, aimY = 4.9, shell = { bottom = 0.3, height = 7.8, width = 5.4 } },
		{ id = "gingerbread", name = "Gingerbread Man", kind = "gingerbread", mult = 3, price = 1.2e6, aimY = 4.4, shell = { bottom = 0.3, height = 7.8, width = 4.6 } },
		{ id = "workshop", name = "Nutcracker", kind = "workshop", mult = 5, price = 200e6, aimY = 4.8, shell = { bottom = 0.5, height = 8.6, width = 4.4 } },
		{ id = "ice", name = "Penguin", kind = "ice", mult = 8, price = 2.5e9, aimY = 4.2, shell = { bottom = 0.4, height = 7.8, width = 4.6 } },
		{ id = "reindeer", name = "Reindeer", kind = "reindeer", mult = 12, price = 20e9, aimY = 4.6, shell = { bottom = 0.3, height = 8.4, width = 4.4 } },
		{ id = "crystal", name = "Amethyst Golem", kind = "crystal", mult = 20, price = 300e9, aimY = 5, shell = { bottom = 0.8, height = 8.6, width = 6.2 } },
		{ id = "aurora", name = "Snow Owl", kind = "aurora", mult = 30, price = 2e12, aimY = 4.6, shell = { bottom = 1.2, height = 7.4, width = 4.6 } },
		{ id = "citadel", name = "Knight", kind = "citadel", mult = 50, price = 4e12, aimY = 4.6, shell = { bottom = 0.3, height = 8.4, width = 5.0 } },
		{ id = "northstar", name = "Star Spirit", kind = "northstar", mult = 100, price = 40e12, aimY = 4.9, shell = { bottom = 0.4, height = 7.6, width = 5.6 } },
	} :: { TrainStation },
	targetTag = "TrainTarget", -- each trainer's target Model (TrainingArt); the client frosts and wobbles it
	spot = { x = 14, z = 12 }, padSize = { 11, 12 }, padHeight = 0.8,
	targetZ = 3.3, standZ = -2.6,
	baseValue = 1, levelValue = 4, -- 4 (balance pass 2026-11-12): at 10 the late islands' needs trained in seconds
	autoEvery = 1.2, autoPass = 0.3,
	clickMax = 5,
	shatterHits = 12, shatterBonus = 5,
	tickSeconds = 0.1,
	arrowSeconds = 45, -- after "Need more Cold Power" the guide arrow points at your trainer this long, or until you step on it (was 6: gone before a kid got there, review 2026-11-15)
	-- lock mode (owner 2026-11-11, from reference clips): E at your trainer (prompt, below) snaps you to the stand
	-- spot (standZ) facing the target and holds you there, training, until you jump (Space, the touch jump
	-- button, gamepad A or B; no STOP button, owner 2026-11-11). Then you hop off the pad the way you're
	-- pushing (any direction, owner 2026-11-11), or to your right if you aren't: hop.clear studs past the
	-- pad's edge (hop.step further, up to hop.tries times, while the spot is taken), in an arc hop.height
	-- studs high lasting hop.seconds + hop.perStud per stud. It passes over the trainer's low walls but
	-- never through a solid wall (pan fences).
	-- breakStuds: pulled further than this from the stand spot (a tester teleport, a fling) = the lock
	-- lets go.
	lock = { breakStuds = 8, hop = { clear = 2.5, step = 1.5, tries = 4, height = 4.5, seconds = 0.3, perStud = 0.02 } },
	-- the "Train" E prompt (owner 2026-11-13: you press E to step in; walking over the pad does nothing):
	-- it floats lift studs over the stand spot and answers within range studs
	prompt = { range = 10, lift = 3 },
}

-- pan `plot`'s trainer: its middle on the ground; its local +Z (the target side) faces the plaza
function Config.trainerFrame(plot: number): CFrame
	return CFrame.new(Config.trainerCentre(plot))
end

-- the middle of pan `plot`'s trainer pad, on the ground
function Config.trainerCentre(plot: number): Vector3
	local pl = Config.world.plots[plot]
	local T = Config.training
	if not pl then
		return Vector3.zero
	end
	return Vector3.new(pl.x + T.spot.x, 0, Config.world.pans.frontZ + T.spot.z)
end

-- the foot of pan `plot`'s trainer target
function Config.trainerTarget(plot: number): Vector3
	return (Config.trainerFrame(plot) * CFrame.new(0, 0, Config.training.targetZ)).Position
end

-- the pan whose trainer pad this point stands on (nil = none). The server checks it with its own position.
function Config.trainerAt(pos: Vector3): number?
	local T = Config.training
	local hx, hz = T.padSize[1] / 2, T.padSize[2] / 2
	for i in Config.world.plots do
		local c = Config.trainerCentre(i)
		if math.abs(pos.X - c.X) <= hx and math.abs(pos.Z - c.Z) <= hz and pos.Y < c.Y + 12 then
			return i
		end
	end
	return nil
end

-- the Cold Power an island's gate needs (0 = none: island 1, or an island that doesn't exist)
function Config.need(zoneId: number): number
	local z = Config.zone(zoneId)
	return if z then z.need else 0
end

local function cleanPower(power: number): number
	if typeof(power) ~= "number" or power ~= power then
		return 0
	end
	return math.clamp(power, 0, Config.coldPower.max)
end

-- the next threshold above this Cold Power: the island needs in order, then x needGrowth for ever
function Config.nextNeed(power: number): number
	power = cleanPower(power)
	local last = 0
	for _, z in Config.world.zones do
		if z.need > power then
			return z.need
		end
		last = math.max(last, z.need)
	end
	local g = math.max(1.5, Config.coldPower.needGrowth) -- never 1 or less: the loop below would not end
	local n = math.max(1, last) * g
	while n <= power do
		n *= g
	end
	return n
end

-- how many of those thresholds this Cold Power has passed (0 until island 2's need)
function Config.powerLevel(power: number): number
	power = cleanPower(power)
	local level, last = 0, 0
	for _, z in Config.world.zones do
		if z.need > 0 and z.need <= power then
			level += 1
		end
		last = math.max(last, z.need)
	end
	local g = math.max(1.5, Config.coldPower.needGrowth)
	local n = math.max(1, last) * g
	while n <= power do
		level += 1
		n *= g
	end
	return level
end

-- how many times faster an island's pets freeze at this Cold Power (1 to maxSpeed)
function Config.freezeSpeed(power: number, zoneId: number): number
	local CP = Config.coldPower
	return math.clamp(math.sqrt(cleanPower(power) / math.max(Config.need(zoneId), CP.speedFloor)), 1, CP.maxSpeed)
end

-- real seconds of ray to freeze a pet (FreezeService times it on the server). The rarity's minimum
-- comes last, so nothing skips it (not power, not a sleeping pet).
-- how much faster this gun freezes than the first one (owner 2026-11-13: guns must be worth buying for the
-- chase, not only for training): +perGun a gun, so gun 10 freezes about twice as fast
function Config.gunFreeze(gun: number?): number
	return 1 + Config.guns.freezePerGun * (math.clamp(math.floor(tonumber(gun) or 1), 1, #Config.guns.list) - 1)
end

function Config.freezeSeconds(tier: string, size: string, power: number, zoneId: number, asleep: boolean?, gun: number?): number
	local F = Config.show.freeze
	local raw = (F.tierSeconds[tier] or 1) * (F.sizeFactor[size] or 1) * Config.aim.timeScale / Config.freezeSpeed(power, zoneId)
		/ Config.gunFreeze(gun)
	if asleep then
		raw *= Config.night.sleepFreezeFactor
	end
	return math.max(Config.coldPower.minSeconds[tier] or 0, raw)
end

-- a fresh cube's life (melt units: one second on open ground where heat = 1) for a pet of this tier
-- from this island; see Config.melt.homeShare. Before the Ice Ray upgrade's lifeBonus.
function Config.cubeLife(tier: string, zoneId: number): number
	local M = Config.melt
	local speed = Config.player.walkSpeed
	local home = 0
	local own = 1
	for _, z in Config.world.zones do
		if z.id < zoneId then
			home += (z.zMax - z.zMin) * z.heat / speed -- every island crossed on the way home
		elseif z.id == zoneId then
			own = z.heat
			home += (z.zMax - z.zMin) * M.homeFrom * z.heat / speed
		end
	end
	return (home + M.slackSeconds * own) / (M.homeShare[tier] or 0.5)
end

-- the Cold Power one training bolt gives: the base value x the power level x the trainer's xN x the
-- gun's Training x the rebirth multiplier x the 2x Cold Power pass (a shatter is shatterBonus of these)
function Config.trainGain(tier: number, level: number, gun: number, rebirths: number, doubled: boolean): number
	local T = Config.training
	local s = T.stations[tier] -- the trainer's level (pan.trainer)
	if not s then
		return 0
	end
	local gain = T.baseValue * T.levelValue ^ math.max(0, level) * s.mult
		* Config.gun(gun).training * Config.rebirthIncome(rebirths) * (if doubled then 2 else 1)
	-- to the nearest whole number, never 0
	return math.min(Config.coldPower.max, math.max(1, math.round(gain)))
end

-- the smallest round number (Config.niceSteps) that is at least n
function Config.niceUp(n: number): number
	if n < 1 then
		return 0
	end
	local p = 10 ^ math.floor(math.log10(n))
	for _, s in Config.niceSteps do
		if s * p >= n * (1 - 1e-9) then
			return math.round(s * p)
		end
	end
	return math.round(10 * p)
end

-- a Cold Power pack's size: a share of your next island's need, rounded up, so a pack is worth the
-- same at every stage
function Config.powerPack(item: RobuxItem, power: number): number
	return Config.niceUp((item.share or 0) * Config.nextNeed(power))
end

-- MapSpectacle (owner 2026-11-13): the giant decor outside the tunnel, one set per island, louder the
-- further in (a few pines first, a supernova last), and the vivid pass over the whole map's colours.
-- side = how far out from the tunnel's middle the big pieces stand (the cliffs end near 85); arches
-- span the road at archRadius with their feet at archFeet; spin speeds in rad/s, bob in Hz; the
-- supernova hangs novaPast studs beyond the last island, novaHeight up. vivid: saturation x this
-- (and value x vividValue) for every map colour with more than vividMinSat saturation.
Config.art.spectacle = {
	seed = 20261113,
	sideMin = 95, sideMax = 150,
	archSegments = 28, archRadius = 105, archFeet = -6, archDepth = 5,
	bobHz = 0.12, spinSlow = 0.08, spinFast = 0.25,
	novaHeight = 185, novaPast = 90, novaRadius = 58,
	vividSaturation = 1.45, vividValue = 1.03, vividMinSat = 0.06,
	-- "make it more" (owner 2026-11-13): pieces per island = the recipe x (island length / baseLength) x
	-- (1 + densityPerIsland per island after the first); from island backFrom a second, further layer
	-- (backMin..backMax out, backDensity as many) fills the skyline behind
	baseLength = 176, densityPerIsland = 0.08,
	backFrom = 2, backMin = 175, backMax = 240, backDensity = 0.8,
	-- ground detail inside the tunnel (owner 2026-11-13 "make the map more detailed"): small themed
	-- clusters (tufts, flowers, shells, crystals, glowing cracks) perStud of island length, from inner
	-- studs off the road's middle to the cliffs' foot (edgeMargin), more of them toward the edges, kept
	-- clear studs away from trees, sun patches and lava pools. Walk-through, never in the way.
	detail = { perStud = 0.3, inner = 16, edgeMargin = 4, clear = 2, scale = 1.8 }, -- scale: each piece grown round its foot
	-- the detailed sun patch: rays round the rim (rayCount, rayLength x radius), turning rayTurn rad/s
	sun = { rayCount = 14, rayLength = 0.45, rayTurn = 0.15 },
}

return Config
