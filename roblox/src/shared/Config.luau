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
	walkSpeed = 16,
	respawnSeconds = 1, -- Game Design Rules 7: failure is gentle, quick respawn (Roblox's default is 5)
	freezeRange = 10,
	refreezeHold = 0.35, -- zapping a melted pet back (a first freeze takes Config.show.freeze seconds)
	interactHold = 0.4, -- hold to pay at a gate (spends coins: no accidental taps)
	openHold = 0, -- booths, the Pan Upgrades stand and the gift open on a tap (owner 2026-11-02: "E to open doesn't work" = a tap did nothing)
	freezeCooldown = 0.3,
	rateLimitPerSecond = 12,
	-- remotes with their own budget, so a burst of one (aiming while you drag, or calls bunched up by a lag
	-- spike on a phone) can't crowd out the rest (mobile QA 2026-11-10)
	rateLimits = { Aim = 20 } :: { [string]: number },
	maxSpeedTolerance = 1.6, -- server flags positions that move faster than this x walk speed
}

Config.tiers = {
	{ name = "Common", odds = 59.995, cubeLife = 90, income = 1, rank = 1 },
	{ name = "Uncommon", odds = 25, cubeLife = 70, income = 3, rank = 2 },
	{ name = "Rare", odds = 10, cubeLife = 30, income = 10, rank = 3 }, -- owner 2026-10-30: steep: Commons easy, Secrets hard
	{ name = "Epic", odds = 4, cubeLife = 22, income = 30, rank = 4 },
	{ name = "Legendary", odds = 0.9, cubeLife = 16, income = 100, rank = 5 },
	{ name = "Mythic", odds = 0.1, cubeLife = 12, income = 400, rank = 6 },
	{ name = "Secret", odds = 0.005, cubeLife = 8, income = 1500, rank = 7 }, -- 1 in 20,000, every zone
} :: { Tier }
Config.incomeZoneMultiplier = 4

Config.poses = {
	idle = { label = "Normal", bonus = 1.0, seconds = 2.4 },
	yawn = { label = "Yawn", bonus = 1.2, seconds = 1.3 },
	jump = { label = "Jump", bonus = 1.2, seconds = 0.9 },
	dance = { label = "Dance", bonus = 1.5, seconds = 1.6 },
	sneeze = { label = "Mid-Sneeze", bonus = 2.0, seconds = 0.7 },
	sleep = { label = "Sleeping", bonus = 1.5, seconds = 3 }, -- night only: every wild pet sleeps
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
	boots = { name = "Boots", baseCost = 64, costGrowth = 1.5, maxLevel = 15, speedBonus = 0.08 },
	backpack = { name = "Backpack", baseCost = 750, costGrowth = 1.5, maxLevel = 5, slowPerExtraCube = 0.08 },
	-- owner 2026-11-05: 100 slots was "insane"; the pan tops out at 16 (10 to start, +1 a level, 7 levels).
	-- One slot is a bigger share now, so each level costs x2.5 the last, rounded (100, 250, 600, 1.5K, 4K, 10K)
	pen = { name = "Pan", baseCost = 100, costGrowth = 2.5, maxLevel = 7, slotsPerLevel = 1, rebirthGrowth = 5 },
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
Config.gateCooldown = 0.4 -- seconds between two tries at the same player's gate (Round 4 phase 6)
Config.gateGuardStuds = 3 -- PlayerTracker puts anyone this far past a gate they haven't opened back in front of it
Config.shopOpenedCooldown = 2
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
	maxCoins = 1e15, heatMax = 5, awayMax = 24 * 3600,
	multMin = 0.1, multMax = 10000,
	walkMin = 16, walkMax = 100,
	addCoins = { 1e3, 1e6, 1e9 },
	multPresets = { 1, 10, 100, 1000 },
	walkPresets = { 16, 32, 60, 100 },
	maxRebirths = 50,
	readoutSeconds = 1,
	powerPresets = { 0, 1e3, 1e6, 1e9, 1e12 }, -- the Tester panel's Cold Power buttons
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
}

Config.bigChill = { everySeconds = 600, warnSeconds = 30, durationSeconds = 60 }

-- Night (owner 2026-10-31): one 15-minute loop for the whole server, worked out from server time so
-- every client agrees without messages. day -> sunset -> night -> sunrise. At night pets sleep (freeze
-- in half the time, Sleeping pose), cubes melt slower (Config.melt.night) and Starry pets can spawn.
-- Candy night, never scary: deep blue-purple, bright enough to play.
Config.night = {
	daySeconds = 600, fadeSeconds = 60, nightSeconds = 180, -- cycle = day + fade + night + fade
	sleepFreezeFactor = 0.5, -- a sleeping pet's Freeze hold is this much of the normal hold
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
Config.dailyGift = { baseCoins = 50, incomeMinutes = 10, streakBonus = 0.1, streakMax = 7, afterFirstBank = true } -- the gift box opens after your first bank

export type RobuxItem = {
	id: string, kind: string, name: string, text: string, icon: string, robux: number,
	productId: number?, passId: number?, -- a developer product, or a game pass (kind "pass")
	mult: number?, minutes: number?, floor: number?, stack: number?, charges: number?,
	share: number?, -- a Cold Power pack: this share of your next island's need (Config.powerPack)
}
Config.monetization = {
	-- Owner items: create the developer product in the Creator Dashboard and paste its id here.
	superFreeze = { productId = 0, robux = 15, minTier = "Rare", walkAwayStuds = 18 },
	-- the Robux tab of the Shop, top to bottom (owner 2026-11-05). An id of 0 = not made yet: hidden in
	-- live servers, given free in Studio so it can be tested. Coin packs are minutes of your own income
	-- (never under floor), so a pack is worth the same at every stage. Bought coins skip the weekly board.
	-- Robux prices (owner 2026-11-07) sit on the price points players know from hit games (49 / 99 / 199;
	-- Steal a Brainrot's 2x Money is 299), and a bigger pack is better value: 1 hour, 3 hours, 8 hours of
	-- income. The real price is set on the product in the Creator Dashboard: keep both the same.
	shop = {
		{ id = "doubleCoins", kind = "pass", passId = 0, robux = 199, mult = 2, name = "2x Coins", text = "Your pan earns double, forever", icon = "coin", stack = 2 },
		{ id = "coinsSmall", kind = "coins", productId = 0, robux = 49, minutes = 60, floor = 2500, name = "Coin Bag", text = "", icon = "coin", stack = 1 },
		{ id = "coinsMedium", kind = "coins", productId = 0, robux = 99, minutes = 180, floor = 10e3, name = "Coin Chest", text = "", icon = "coin", stack = 2 },
		{ id = "coinsBig", kind = "coins", productId = 0, robux = 199, minutes = 480, floor = 25e3, name = "Coin Vault", text = "", icon = "coin", stack = 3 },
		{ id = "superFreeze3", kind = "charges", productId = 0, robux = 39, charges = 3, name = "Super Freeze", text = "3 for rare pets", icon = "ray", stack = 1 },
		-- a Big Chill for the whole server, with "<name> started a Big Chill for everyone!" (2026-11-10,
		-- Game Design Rules 10: server-wide events). Everyone gets it; it never moves the free Chill's clock.
		{ id = "bigChill", kind = "chill", productId = 0, robux = 49, name = "Big Chill", text = "60 s for everyone", icon = "temp", stack = 1 },
		-- Cold Power (2026-11-10; starting prices, the owner sets the real ones). Never needed to progress:
		-- free Auto-Train runs at Config.rink.autoFree, and playing by hand is always the best rate.
		-- A pack is a share of your next island's need (Config.powerPack), so it's worth the same at every stage.
		{ id = "autoTrain", kind = "pass", passId = 0, robux = 149, name = "Full-Speed Auto-Train", text = "Auto trains at full speed", icon = "power", stack = 1 },
		{ id = "doublePower", kind = "pass", passId = 0, robux = 199, mult = 2, name = "2x Cold Power", text = "Double Cold Power, forever", icon = "power", stack = 2 },
		{ id = "powerSmall", kind = "power", productId = 0, robux = 49, share = 0.25, name = "Cold Power Pack", text = "", icon = "power", stack = 1 },
		{ id = "powerBig", kind = "power", productId = 0, robux = 149, share = 1, name = "Big Cold Power Pack", text = "", icon = "power", stack = 3 },
	} :: { RobuxItem },
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
		{ id = "rarest_pet", title = "RAREST PET", subtitle = "Best pet ever found", icon = "trophy", kind = "alltime" },
		{ id = "coins_week", title = "TOP COINS", subtitle = "Coins earned this week", icon = "coin", kind = "weekly" },
	},
	updatesLabel = "Updates every minute",
	cosmeticReward = "Top 3 each week get a glowing name",
	weeklyTopReward = 3, -- how many places get the name-plate glow; never coins or pets
	weeklyBadgeId = 0, -- optional owner item: a badge for weekly top 3 (0 = off)
	hiddenName = "A player", -- shown when a display name can't be fetched
}

Config.analytics = {
	-- one list for the whole game; AnalyticsSvc refuses anything not in it
	funnel = {
		{ step = 1, name = "joined" },
		{ step = 2, name = "first_zap" },
		{ step = 3, name = "first_freeze" },
		{ step = 4, name = "first_carry_home" },
		{ step = 5, name = "first_bank" },
		{ step = 6, name = "first_coins_spent" },
		{ step = 7, name = "first_rare_pet" },
		{ step = 8, name = "first_new_zone" },
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
		rink_wave = { value = "gain", fields = { "level" } }, -- a Training Rink wave finished
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
	streakReset = 1.5,
}

Config.ui = {
	tiles = { { id = "pets", label = "Pets" }, { id = "shop", label = "Shop" }, { id = "index", label = "Index" }, { id = "daily", label = "Daily" }, { id = "settings", label = "Settings" } },
	-- touch screens (mobile QA 2026-11-10): no tap target under this many pixels (Apple asks 44). Tiles,
	-- world prompts and the popup X use it; the hotbar slot has its own floor so its name stays readable
	minTouchPx = 46, hotbarMinPx = 52,
	-- phones: popups take the whole height under the top bar (at 70% the text came out 8.8 px), short
	-- reward popups keep this share instead of 0.62 (at 0.8 a 338 px tall phone still had 9 px text),
	-- and the banner is at least this share of the width
	phoneSmallPopup = 1, bannerPhoneWidth = 0.62,
	touchTextFloor = { title = 18, body = 14, button = 14, small = 12, tiny = 11 } :: { [string]: number }, -- popup text caps never go under these on touch screens (px)
	touchRowAspect = 0.8, -- phones and tablets: long list rows (Pets, Thaw, Tester) are this much less wide-for-their-height
	-- sizes are fractions of the screen's short side (Scale only, UI Rules); the Screen module places them
	-- owner 2026-10-31: smaller side tiles (still over 10% of the short side for small fingers);
	-- owner 2026-11-07: the goal bar and temperature chip are gone; the island banner (below) took their place
	tileSize = 0.105, tileGap = 0.016, coinsSize = { 0.3, 0.1 }, bannerSize = { 0.5, 0.088 },
	-- Cold Power (2026-11-10): its counter sits under the coins, bottom left (the two lift together over
	-- the thumbstick). popScale / popSeconds: the number's small bounce when it goes up.
	powerSize = { 0.3, 0.07 }, powerPop = { scale = 1.18, seconds = 0.22 },
	-- the Training Rink's HUD (Figma file "Chunky Pop Icons", page "Training Rink HUD"): the sprites-left
	-- bar top centre with the combo beside it, Auto and Exit on the right edge, the result card in the
	-- middle. While you're in the rink the menu tiles step aside (5 pieces: coins, Cold Power, hotbar,
	-- bar, buttons). Sizes: shares of the screen's short side; gain* = the "+120" over a frozen sprite.
	rink = { barSize = { 0.62, 0.052 }, barTop = 0.025, comboWidth = 0.2, buttonSize = 0.12, buttonGap = 0.02,
		gainPx = 30, gainRise = 3, gainSeconds = 0.9, againPulse = { scale = 1.06, seconds = 0.6 },
		resultShare = 0.74 }, -- the result card: this share of a normal popup
	topInset = 0.02, sideInset = 0.03, touchLift = 0.28, -- the coins sit above the thumbstick on touch screens
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
	hideHudFor = { shop = true, equipment = true, index = true, sell = true, rebirth = true } :: { [string]: boolean },
	-- the big popups (Equipment, Index, Sell, Rebirth: owner 2026-11-09 "make it bigger"), share of the screen and aspect
	bigPopups = { equipment = true, index = true, sell = true, rebirth = true } :: { [string]: boolean },
	popupSizeBig = { 0.9, 0.86 }, popupAspectBig = 1.68,
	barTrackAlpha = 0.2, -- progress bars: the light track behind the fill
	-- the Index (2026-11-09): pageAspect = a page card's width / height; shares of the card below
	index = { pageAspect = 4, headHeight = 0.3, slotTop = 0.05, slotInset = 0.012, slotGap = 0.012,
		totalHeight = 0.13, totalGap = 0.02, badgeFaint = 0.6 },
	popupSize = { 0.8, 0.7 }, popupLift = 0.04, promptSize = { 0.27, 0.095 }, -- world prompts keep this screen size at any distance (owner: smaller)
	bannerSeconds = 3, floatSeconds = 1.2, notYetSeconds = 1.6,
	-- the "+17.5K" beside the coin counter: shares of the coins block; a size under the number (0.62 tall)
	gain = { height = 0.46, width = 1.2, y = 0.08, gap = 0.04, rise = 0.55, popSeconds = 0.25, holdSeconds = 0.45 },
	pressDepth = 0.06, pressSeconds = 0.08, stroke = 3, corner = 0.18,
	radius = 0.018, -- THE corner radius for every block, as a share of the screen's short side
	textStroke = 1.5, -- white text's outline (2 plus the block outline read heavy)
	floatingStroke = 2.5, -- text with no block behind it (the coin counter) needs a firmer outline
	cardStroke = 2, -- the thin outline round a list card
	panelTint = 0.86, -- a popup body is its menu colour this far toward white, so body and ribbon match
	promptHoldFill = 0.55, -- the white sweep that fills a world prompt while you hold (transparency)
	promptFade = 0.45, -- a world prompt's pill is this see-through so the pet under it shows (its words stay solid)
	promptLift = -0.6, -- studs from the prompt's attachment (1 stud over the pet's head) down onto the pet
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
	-- the tutorial card (Ranger Bo's lines): bottom centre, just above the hotbar. Shares of the screen's
	-- short side: phone is wider (fewer pixels), PC and tablet use `wide`. text = the line's size, a share of the card's height
	tutorial = { phone = { 1.08, 0.27 }, wide = { 0.82, 0.2 }, text = 0.17, goalText = 0.13 },
	settingsRow = 0.128, -- a Settings row's height (share of the list): 7 rows and their gaps fit
	gamepadKeys = { close = Enum.KeyCode.ButtonB, superFreeze = Enum.KeyCode.ButtonY, menu = Enum.KeyCode.ButtonSelect, skip = Enum.KeyCode.ButtonA },
	keys = { pets = Enum.KeyCode.P, shop = Enum.KeyCode.B, index = Enum.KeyCode.I, close = Enum.KeyCode.Backspace, superFreeze = Enum.KeyCode.F, tester = Enum.KeyCode.T, skip = Enum.KeyCode.Return }, -- Escape belongs to Roblox's own menu,
	testerTile = { id = "tester", label = "Tester" }, -- only testers see it
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
	atmosphereDensity = 0.22,
	atmosphereOffset = 0.1,
	atmosphereDecay = Color3.fromHex("8fd8ff"), -- far haze fades to sky cyan, not grey
	saturation = 0.2,
	contrast = 0.05,
	sky = {
		bk = "rbxassetid://6295671271", dn = "rbxassetid://6295671382", ft = "rbxassetid://6295671136",
		lf = "rbxassetid://6295670996", rt = "rbxassetid://6295671509", up = "rbxassetid://6295671667",
		sunSize = 12,
	},
	clouds = { cover = 0.5, density = 0.55, color = Color3.fromRGB(255, 255, 255) },
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
	trees: { kind: string, count: number, r: { number } }?, sun: { count: number, r: { number } }?,
	near: { number }?, farFrom: number?, -- spawn bands, measured from the section's start
	feel: string?, -- the island banner's heat word (Round 4 Prompt 6: "cold", "mild", "lava"...)
}
export type Booth = { id: string, label: string, action: string, pos: Vector3, sign: { y: number, z: number }? }
-- one cue in a shot clip (Config.ray.anim): at a share of the clip, a sound, an effect and/or a camera kick
export type RayCue = { at: number, sound: string?, fx: string?, kick: string? }

Config.world = {
	maxPlayers = 6, -- one pan per server slot. Owner item: Server Size 6 in Game Settings > Places
	mapVersion = 16, -- 16 = the Training Rink's door. Workspace.Map carries this; an older saved map is rebuilt (3 = Round 5 map remake, 4 = 10 islands, 5 = clear centre / rich edges, 6 = bigger square pans, 7 = pans measured against the real avatar, 8 = open gaps, open ground behind, level pans, 9 = no flush overlapping surfaces, 10 = booth details: sign bulbs, log ends, scalloped awnings, chalk coin, 11 = wide tunnel and big entrance for big pets, a clean road, 12 = booths shaped like what they do: treasure chest, gear workshop, ring portal, 13 = the detailed sci-fi Thaw Machine, 14 = each world's own gate towers, 15 = never-visible buried parts left out (PERF-AUDIT-2026-11-09))
	hubZMax = 0, -- the tunnel mouth: the hub is z < 0 (no wild pets, no heat)
	-- wide enough for the row of six pans plus 10 studs at each end; zMin is worked out below (behind the pans' backSpace)
	hub = { xMin = -150, xMax = 150, zMin = 0, wallHeight = 16, colliderHeight = 60 },
	spawn = Vector3.new(0, 3, -34),
	spawnPadRadius = 6,
	-- the pans: fenced gardens a little deeper than wide, level with the ground round them, doors facing
	-- the plaza, open walkable ground between them and backSpace of open ground behind them.
	-- Sizes follow the owner's reference shots (2026-11-05), measured against the real avatar (5.8 studs
	-- tall, 3.3 across the arms) and the reference's 4-stud floor tiles: width about 7 avatar heights,
	-- depth 1.1 x width, door 0.4 x width, gap 0.2 x width, about one width of open ground behind,
	-- fence about shoulder high (0.8 avatar heights)
	pans = { width = 40, length = 44, gap = 8, frontZ = -62, soilHeight = 0.2, backSpace = 40, doorWidth = 16, fenceHeight = 4.5,
		signY = 6.5, gaugeOffset = 10.5, boothOffset = -11 }, -- gauge right of the door, Pan Upgrades stand left of it (x from the lane's middle)
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
	islands = {
		{ key = "meadow", name = "Snowy Meadow", feel = "Cold", open = true, ready = true, theme = "meadow", length = 168, heat = 0.5, iceLife = 1, need = 0,
			landmark = "snowman", landmarkAt = { x = 66, z = 112 }, -- landmarks stand in the cliffs, tall enough to show over them (World Rules 9)
			trees = { kind = "snowpine", count = 14, r = { 4, 6.5 } }, sun = { count = 5, r = { 7, 11 } },
			near = { 8, 34 }, farFrom = 60 },
		{ key = "forest", name = "Pine Forest", feel = "Cold", open = true, ready = true, theme = "forest", length = 176, heat = 0.8, iceLife = 1, need = 1e3,
			landmark = "mushroom", landmarkAt = { x = -66, z = 104 },
			trees = { kind = "pine", count = 34, r = { 4.5, 7.5 } }, sun = { count = 3, r = { 6, 10 } },
			near = { 10, 42 }, farFrom = 10 },
		{ key = "grove", name = "Mushroom Grove", feel = "Mild", open = true, ready = true, theme = "grove", length = 172, heat = 1.0, iceLife = 1.6, need = 25e3,
			landmark = "toadstoolTower", landmarkAt = { x = 66, z = 100 },
			trees = { kind = "toadstool", count = 22, r = { 4, 7 } }, sun = { count = 3, r = { 6, 9 } },
			near = { 10, 40 }, farFrom = 12 },
		{ key = "beach", name = "Sunny Beach", feel = "Warm", open = true, ready = true, theme = "beach", length = 172, heat = 1.3, iceLife = 2.4, need = 500e3,
			landmark = "lighthouse", landmarkAt = { x = -66, z = 104 },
			trees = { kind = "palm", count = 14, r = { 4, 6 } }, sun = { count = 7, r = { 7, 11 } },
			near = { 10, 40 }, farFrom = 12 },
		{ key = "jungle", name = "Jungle Falls", feel = "Hot and humid", open = true, ready = true, theme = "jungle", length = 176, heat = 1.6, iceLife = 3.3, need = 10e6,
			landmark = "waterfall", landmarkAt = { x = 56, z = 108 }, -- pours from the cliff face
			trees = { kind = "jungle", count = 28, r = { 4.5, 7.5 } }, sun = { count = 4, r = { 6, 9 } },
			near = { 10, 42 }, farFrom = 12 },
		{ key = "desert", name = "Desert Dunes", feel = "Hot", open = true, ready = true, theme = "desert", length = 176, heat = 2.0, iceLife = 4.4, need = 150e6,
			landmark = "cactus", landmarkAt = { x = -66, z = 104 },
			trees = { kind = "cactus", count = 9, r = { 3.5, 5 } }, sun = { count = 9, r = { 8, 12 } },
			near = { 10, 42 }, farFrom = 12 },
		{ key = "canyon", name = "Canyon Mesa", feel = "Very hot", open = true, ready = true, theme = "canyon", length = 180, heat = 2.4, iceLife = 5.7, need = 4e9,
			landmark = "arch", landmarkAt = { x = 0, z = 112 },
			trees = { kind = "hoodoo", count = 10, r = { 4, 6 } }, sun = { count = 8, r = { 8, 12 } },
			near = { 10, 42 }, farFrom = 12 },
		{ key = "volcano", name = "Volcano Slopes", feel = "Lava", open = true, ready = true, theme = "volcano", length = 180, heat = 2.9, iceLife = 7.2, need = 75e9,
			landmark = "volcano", landmarkAt = { x = 70, z = 108 }, -- beside the tunnel, rising over the cliffs
			trees = { kind = "charred", count = 8, r = { 4, 6 } }, sun = { count = 3, r = { 6, 9 } }, lava = { count = 5, r = { 5, 8 } },
			near = { 10, 42 }, farFrom = 12 },
		{ key = "lavalake", name = "Lava Lake", feel = "Lava", open = true, ready = true, theme = "lavalake", length = 184, heat = 3.4, iceLife = 9, need = 1.2e12,
			landmark = "spire", landmarkAt = { x = -66, z = 112 },
			trees = { kind = "obsidian", count = 8, r = { 4, 6 } }, lava = { count = 8, r = { 6, 10 } },
			near = { 10, 42 }, farFrom = 12 },
		{ key = "magma", name = "Magma Core", feel = "Extreme", open = true, ready = true, theme = "magma", length = 184, heat = 4.0, iceLife = 11, need = 20e12,
			landmark = "core", landmarkAt = { x = 0, z = 116 },
			trees = { kind = "obsidian", count = 7, r = { 4, 6 } }, lava = { count = 10, r = { 5, 9 } },
			near = { 10, 42 }, farFrom = 12 },
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
		{ id = "equipment", label = "Equipment", action = "equipment", pos = Vector3.new(80, 0, -8), sign = { y = 9, z = -3.3 } },
		{ id = "rebirth", label = "Rebirth", action = "rebirth", pos = Vector3.new(-103, 0, -8), sign = { y = 14.6, z = 3.9 } },
		-- the Training Rink's door (Cold Power, 2026-11-10): a frosty dome; its prompt takes you to your own rink in the sky
		{ id = "rink", label = "Training Rink", action = "rink", pos = Vector3.new(126, 0, -8), sign = { y = 10.4, z = -3.6 } },
	} :: { Booth },
	boothSign = { y = 8.8, w = 9, h = 2.2, z = -3.2, text = 1.5 }, -- a booth sign's size (text = letter height in studs); y / z are the spot for a booth without its own `sign`
	panUpgradeAction = "pan", -- the Pan Upgrades popup (Round 4 phase 5)
	giftBox = Vector3.new(106, 0, -10),
	-- leaderboards on the hub's side walls, turned to face the plaza
	boards = { Vector3.new(-146, 0, -46), Vector3.new(-146, 0, -24), Vector3.new(146, 0, -46) },
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
		gear = "rbxassetid://84856334538368", gift = "rbxassetid://86444394737076", trophy = "rbxassetid://96802650316741",
		-- 2026-10-31 batch (prototype/ice-ray-for-pets/icons, cleaned with tools/icon_cleanup.ps1)
		ray = "rbxassetid://139931668460856", boots = "rbxassetid://82792097425872", pen = "rbxassetid://92747015965127",
		music = "rbxassetid://110832713318779", sound = "rbxassetid://117928774777865", motion = "rbxassetid://87612144122340",
		graphics = "rbxassetid://136668522918870", temp = "rbxassetid://72963487370215",
		paint = "rbxassetid://133624884100688", -- 2026-11-03: the Pan Upgrades Look card (icons/paint.png)
		-- Cold Power. STAND-IN: the thermometer, until the painted snowflake crystal is made (owner's OK on Figma credits first)
		power = "rbxassetid://72963487370215",
		robux = "rbxasset://textures/ui/common/robux.png", -- Roblox's own Robux mark, on every Robux price
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

Config.ui.tileIcons = { pets = Config.images.pets.snowbun, shop = Config.images.icons.bag, index = Config.images.icons.book, settings = Config.images.icons.gear,
	daily = Config.images.icons.trophy }
-- painted icons on the Shop and Settings rows
local I = Config.images.icons
Config.ui.upgradeIcons = { ray = I.ray, boots = I.boots, backpack = I.bag, pen = I.pen } :: { [string]: string }
Config.ui.settingIcons = { music = I.music, sound = I.sound, reducedMotion = I.motion, lowGraphics = I.graphics, unit = I.temp } :: { [string]: string }
Config.ui.silhouetteTransparency = 0
Config.ui.shopPerRow = 5 -- the Robux shop's product tiles to a row
Config.ui.petSpriteScale = 1.25 -- a pet sprite is this many times the pet's height wide

-- The world teaches (prototype client.js): a green arrow to a pet in your first minutes and home while
-- you carry, a diamond over the nearest pet you can't reach yet, a light pillar over your pen
Config.guide = {
	earlyPets = 3, -- the arrow points to pets until you own this many
	arrowDistance = 6.5, arrowHideNear = 8, arrowY = 0.5, arrowBob = 0.35, arrowBobSpeed = 4,
	markerRange = 45, markerY = 1, markerBob = 0.3, markerSpin = 1.5,
	beaconRadius = 3.2, beaconHeight = 70, beaconTransparency = 0.78, beaconPulse = 0.06,
}
-- The tutorial (owner 2026-11-10): Ranger Bo, a guide only you can see, walks a new player through one
-- full catch. The world still teaches (the green arrow, the glow on the next thing); Bo says one short
-- line per step and reacts to what you do (Game Design Rules 2: goal shown, not told).
-- on = what finishes a step: an action the server saw (TutorialService.did) or "next" (the Next
-- button). A later step's action counts too, so a player who runs ahead is never held back.
-- focus = what Bo walks to, points at and makes glow (GuideController's arrow target).
-- hints = said again if the step takes a while, worded for the player's device (or "all").
-- Saved per player (DataService tutorial = { step, done }); saves from before it existed count as done
-- (Lessons: new-player things are for new players only). Replay is in Settings.
Config.tutorial = {
	name = "Ranger Bo",
	modelName = "TutorialGuide", -- the server builds the guide here in ReplicatedStorage; each client clones it
	steps = {
		{ id = "hello", on = "next", say = "Hi, I'm Bo! The pets out here run too hot. Let's cool one down!" },
		{ id = "zap", on = "zap", focus = "pet", say = "See that pet? Point your ice ray at it.", goal = "Aim at a pet",
			hints = { keyboard = "Hold click on the pet!", touch = "Hold your finger on the pet!", gamepad = "Aim at it and hold R2!" } },
		{ id = "freeze", on = "freeze", focus = "pet", say = "Keep the ray on it until it freezes!", goal = "Freeze the pet",
			hints = { keyboard = "Don't let go yet!", touch = "Keep holding!", gamepad = "Keep holding R2!" } },
		{ id = "pickup", on = "pickup", focus = "cube", say = "Brrr! Now grab the ice cube.", goal = "Pick up the cube",
			hints = { keyboard = "Walk to the cube and press E!", touch = "Walk to the cube and tap Pick up!", gamepad = "Walk to the cube and press X!" } },
		{ id = "carry", on = "bank", focus = "pan", say = "Run it home to your pan. Follow the arrow!", goal = "Bring it to your pan",
			hints = { all = "Walk into your pan with the cube on your back!" } },
		{ id = "thaw", on = "thawStart", focus = "machine", say = "Pop it in your Thaw Machine!", goal = "Use the Thaw Machine",
			hints = { keyboard = "Stand by the machine and press E!", touch = "Stand by the machine and tap its button!", gamepad = "Stand by the machine and press X!" } },
		{ id = "wait", on = "thawed", focus = "machine", say = "It's thawing! It hops out in a few seconds.", goal = "Wait for your pet" },
		{ id = "done", on = "next", say = "Your pet makes coins for you now. Go catch them all!" },
	} :: { { id: string, on: string, say: string, focus: string?, goal: string?, hints: { [string]: string }? } },
	actions = { zap = true, freeze = true, pickup = true, bank = true, thawStart = true, thawed = true } :: { [string]: boolean },
	praise = { "Nice!", "Great job!", "You got it!", "Perfect!" },
	react = {
		melted = "Oh no, it thawed out! Zap it again.",
		tooWarm = "Too hot for your ray! Try a pet near the start.",
		wrongWay = "Your pan is the other way! Follow the arrow.",
		skipped = "No problem! Have fun out there.",
		finished = "See you around!",
		skipConfirm = "Sure?",
	},
	-- timings (seconds) and distances (studs)
	typeCps = 45, -- typewriter letters per second
	praiseHold = 1.3, -- "Nice!" stays this long before the next step's line
	hintAfter = 14, hintEvery = 20, -- a stuck player hears the step's hint after this, then again every hintEvery
	reactCooldown = 8, -- at most one reaction line this often
	wrongWayStuds = 18, -- carrying home: this much farther from the pan than your closest = wrong way
	skipConfirmSeconds = 3, -- Skip asks "Sure?"; a second press within this skips
	nextCooldown = 0.5, -- the server ignores a second "next" sooner than this
	leaveSeconds = 2.5, -- after the last line Bo waves, then goes
	popSeconds = 0.25, closeSeconds = 0.15, -- the card pops in and closes (Animation Rules: pop, close)
	pulseSeconds = 0.6, pulseScale = 1.06, -- Next breathes (Animation Rules: pulse, 1.2 s a loop)
	npc = {
		walkSpeed = 14, runSpeed = 24, runFrom = 14, -- runs to catch up when this far from where he wants to be
		arrive = 1.5, teleport = 90, -- snaps to you if left this far behind (a gate, a respawn)
		followGap = 9, followSide = 5, -- walks at your side; only moves when you get this far away
		focusRange = 45, focusStand = 6, -- stands this far from the thing he's showing, on your side
		leadAhead = 9, -- farther than focusRange: he walks this far ahead of you toward it, leading the way
		turnRate = 10, groundRay = 80, stepUp = 6, -- the ground ray starts this far over his feet
		helloOffset = Vector3.new(4, 0, 9), -- from the spawn, toward the tunnel and the pets
		pillY = 1.8, -- name pill height over his head
		-- Roblox's own R15 animations: owned by Roblox, so they play in any game (Animation Rules 4)
		anims = { idle = 507766388, walk = 507777826, run = 507767714, wave = 507770239, point = 507770453, cheer = 507770677 } :: { [string]: number },
		portraitFov = 26, portraitDistance = 3.4,
	},
	sounds = { line = "click", praise = "coin", finish = "unlock" },
}
-- the ice ray: a small gun in every player's right hand, a beam while you hold Freeze
Config.ray = { beamCore = 0.28, beamGlow = 0.84, armRaise = 90, tipSize = 0.76, sparkleRate = 20,
	-- each gun tier: a wider beam, more sparkles along it and at the pet, a curl from tier 5 (beam colours: Theme.guns)
	beamPerGun = 0.04, sparklePerGun = 4, sparkleSize = 0.3, sparkleSizePerGun = 0.03, curlFromGun = 5, curlAmount = 0.6,
	tipLightRange = 5, tipLightBrightness = 2, -- a real gun model: a small light in its glow colour at each barrel tip
	putAwayAfterFreeze = true, -- a freeze puts the ray away; it comes back when you carry nothing (owner 2026-11-05)
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
	pickUpRange = 10, groundSeconds = 60,
	-- QA 2026-11-08 (Studio-side work): the cube flies into your hands by itself this many seconds after
	-- the snap, no E. Restored 2026-11-09 after a sync overwrote Studio's Config: the delay is a guess
	autoPickUp = true, autoPickUpDelay = 0.6 }

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
}

-- The look of the world (MapArt). Shapes come from ReplicatedStorage.SceneryMeshes
-- (roblox/tools/make_scenery_meshes.ps1); plain parts stand in if missing.
Config.art = {
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
	statue = Vector3.new(0, 0, -50),
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
	touchSeconds = 0.8, spikeCount = 6, spikeHeight = 1.6, starCount = 7, auroraBands = 3,
	-- which tiers get a show instead of the plain snap (smaller for Legendary and Mythic)
	shows = { Legendary = "legendaryFreeze", Mythic = "mythicFreeze", Secret = "secretFreeze" } :: { [string]: string },
	graceExtra = 1.5, -- the shown cube doesn't melt while its show runs (plus this much)
}
-- Secret pets: the full in-world show (Animation Rules 3). The server has already put the pet in
-- your hands; the show only plays it. SKIP shows after your first viewing and jumps to the reveal.
Config.show.secretFreeze = {
	beats = {
		{ name = "pillar", time = 1.1 }, -- a light pillar in the tier colour
		{ name = "push", time = 0.9 }, -- the camera pushes in from the far side
		{ name = "slam", time = 0.35, keepOnSkip = true }, -- the ice slams shut
		{ name = "burst", time = 0.55 }, -- a burst (one flash at most)
		{ name = "name", time = 2.2, keepOnSkip = true }, -- the name slams in
		{ name = "fly", time = 0.6, keepOnSkip = true }, -- the cube flies into your hands, camera back
	} :: { Beat },
	pillar = true, camera = true, flash = true, shout = true, burstParts = 46, rays = 8, title = "SECRET!",
	pushDistance = 11, pushHeight = 3.5, kick = 0.25, slamDrop = 7,
}
Config.show.mythicFreeze = {
	beats = {
		{ name = "pillar", time = 0.7 },
		{ name = "push", time = 0.7 },
		{ name = "slam", time = 0.3, keepOnSkip = true },
		{ name = "burst", time = 0.4 },
		{ name = "name", time = 1.6, keepOnSkip = true },
		{ name = "fly", time = 0.5, keepOnSkip = true },
	} :: { Beat },
	pillar = true, camera = true, flash = true, shout = false, burstParts = 30, rays = 6, title = "MYTHIC!",
	pushDistance = 10, pushHeight = 3, kick = 0.2, slamDrop = 5,
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
-- Cold Power remake (2026-11-10): training = Cold Power per frozen fire sprite in the Training Rink (a
-- multiplier), heat = the hottest island the gun works on (the old cold values). power and cold go in the cleanup.
export type Gun = { key: string, name: string, training: number, range: number, heat: number, beams: number, price: number, rebirths: number }
Config.guns = {
	list = {
		{ key = "frost_popper", name = "Frost Popper", training = 1, range = 10, heat = 2, beams = 1, price = 0, rebirths = 0 },
		{ key = "snowball_blaster", name = "Snowball Blaster", training = 2, range = 11, heat = 2, beams = 1, price = 25e3, rebirths = 0 },
		{ key = "icicle_repeater", name = "Icicle Repeater", training = 3, range = 12, heat = 4, beams = 1, price = 150e3, rebirths = 0 },
		{ key = "glacier_cannon", name = "Glacier Cannon", training = 5, range = 13, heat = 4, beams = 2, price = 300e3, rebirths = 0 },
		{ key = "blizzard_beam", name = "Blizzard Beam", training = 8, range = 14, heat = 6, beams = 2, price = 3e6, rebirths = 0 },
		{ key = "aurora_ray", name = "Aurora Ray", training = 12, range = 15, heat = 6, beams = 2, price = 10e6, rebirths = 0 },
		{ key = "cryo_lance", name = "Cryo Lance", training = 20, range = 16, heat = 8, beams = 3, price = 30e6, rebirths = 0 },
		{ key = "polar_vortex", name = "Polar Vortex", training = 30, range = 17, heat = 8, beams = 3, price = 75e6, rebirths = 0 },
		{ key = "absolute_zero", name = "Absolute Zero", training = 50, range = 18, heat = 10, beams = 3, price = 600e6, rebirths = 0 },
		{ key = "starfrost_nova", name = "Starfrost Nova", training = 100, range = 19, heat = 10, beams = 4, price = 3e9, rebirths = 0 },
		-- owner 2026-11-09: every gun shows a coin price (the free rebirth guns read "Rebirth 2" on only some
		-- rows and looked odd), so all guns are bought with coins in order; rebirth gates islands, not guns
	} :: { Gun },
	-- the card's bars are scaled to the game's 20-island maximum, not to gun 10, so later guns fill them further
	-- Cold Power remake (2026-11-10): Training = Cold Power per frozen sprite in the rink (x1 to x100, so
	-- its bar is drawn on a log scale: Config.gunStatShare), Heat = the hottest island the gun works on
	stats = { "training", "heat", "range", "beams" },
	statLabels = { training = "Training", heat = "Heat", range = "Range", beams = "Beams" } :: { [string]: string },
	statMax = { training = 100, heat = 20, range = 30, beams = 6 } :: { [string]: number },
	boothRange = 30, -- studs: guns are bought standing at the Equipment Booth
	gridColumns = 2, gridGap = 0.03, -- the Equipment popup's gun tiles (owner 2026-11-09: bigger, themed, every price shown)
	lockedGrey = 0.55, -- a gun you can't buy yet: its colour mixed this far toward grey
	buyCooldown = 0.4, -- seconds between two buys (spam is dropped; a double charge can't happen anyway)
	-- the gun's heat bar (0-1), kept on the server (GunService). Firing at a pet from an island one past the
	-- gun's heat fills it in overSeconds (under a Mythic's 4.5 s floor, so a gun one step short can't finish
	-- a Mythic or Secret); on islands it's made for, in okSeconds (it barely moves); in the Training Rink,
	-- in rinkSeconds of nonstop firing. Full = it steams for steamSeconds and can't fire. Not firing, it
	-- cools in coolSeconds. step = how finely clients hear about it (the arc round the aim ring).
	-- coolAfter = it starts cooling this long after the last shot.
	heatBar = { overSeconds = 4, okSeconds = 60, coolSeconds = 3, coolAfter = 0.3, steamSeconds = 2, rinkSeconds = 12, step = 0.05 },
	maxRange = 0, -- the longest range of any gun (filled in below): the pet prompts' own reach on the server
	-- a pet too warm for your gun gives a small side shake (Animation Rules 2: shake), never a freeze
	tooWarmShake = { seconds = 0.3, amp = 0.22, speed = 40 },
	-- the part-built stand-in gun (until the image-to-3D guns arrive): longer and fancier each tier,
	-- one barrel tip per beam; fins from gun 3, a glowing ring from gun 5, a crystal from gun 9
	standIn = { barrel = 1.4, barrelPerGun = 0.07, tipRing = 0.24, finsFrom = 3, ringFrom = 5, gemFrom = 9 },
	-- the picked gun turning on the Equipment card (owner 2026-11-05: a 360 preview). Seconds per full
	-- turn (slower with Reduced motion), camera pitch (degrees, looking down), field of view, fit margin
	preview = { spinSeconds = 6, spinSecondsReduced = 14, pitch = 14, fov = 30, margin = 1.0, tint = 0.72 },
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
	costs = { 75e3, 1e6, 7.5e6, 20e6, 100e6, 200e6, 750e6 }, -- Rebirth 1, 2, 3 ...
	costGrowth = 3,
	fullAt = 7,
	boothRange = 30, -- studs from the Rebirth Booth (the server's position)
	cooldown = 1, -- seconds between two tries
	typicalFactor = 1.5, -- a typical free player takes the playtest bot's time x this (Round 4 prompt 7)
	maxWait = 600, -- seconds of typical play: never longer than this without something to buy (Round 4 prompt 7)
	-- the popup (2026-11-09): shares of its body; barSteps = how often the coin bar redraws
	ui = { heroHeight = 0.2, colsTop = 0.25, colsHeight = 0.45, colWidth = 0.32, colGap = 0.02, colHead = 0.2,
		footTop = 0.73, barSteps = 20, itemHeight = 0.18 },
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

-- Gear (planned for after this round, Round 4 prompt 9): the Equipment Booth's Gear tab shows these
-- slots locked, as silhouettes with "Coming soon". shape = the silhouette drawn from UI shapes.
Config.gear = {
	{ key = "wool_coat", shape = "coat" }, { key = "sun_hat", shape = "hat" }, { key = "cooling_vest", shape = "vest" },
	{ key = "lava_boots", shape = "boots" }, { key = "heat_suit", shape = "suit" },
}

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
	order = { "slots", "look" },
	coldStart = 2,
	coldRefund = { [3] = 7500, [4] = 2e6, [5] = 6e6, [6] = 30e6, [7] = 100e6, [8] = 250e6, [9] = 750e6, [10] = 3e9 } :: { [number]: number },
	names = { slots = "Slots", look = "Look" } :: { [string]: string },
	standRange = 16, -- studs from your own Pan Upgrades stand (the server's position)
	buyCooldown = 0.4,
	looks = {
		{ key = "garden", name = "Garden", price = 0 }, -- Round 5: white fences on a striped lawn (was straw)
		{ key = "wood", name = "Wood", price = 40e3 },
		{ key = "stone", name = "Stone", price = 1.2e6 },
		{ key = "ice", name = "Crystal Ice", price = 20e6 },
		{ key = "aurora", name = "Aurora", price = 1e9 },
	} :: { { key: string, name: string, price: number } },
	crystalEvery = 2, -- crystal ice: a crystal on every 2nd fence post
	auroraSpeed = 0.2, -- aurora: the rails' colours drift this many cycles a second
	drawDistance = 160, -- studs: pans farther than this keep their look but stop animating
}

-- what the next level of a pan upgrade costs (nil = at the top)
function Config.panMax(kind: string): number
	if kind == "slots" then
		return Config.upgrades.pen.maxLevel
	end
	return #Config.pan.looks
end


function Config.panPrice(kind: string, level: number, rebirths: number?): number?
	if level >= Config.panMax(kind) then
		return nil
	elseif kind == "slots" then
		return Config.slotsCost(level + 1, rebirths or 0)
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
	columns = 4, tileGap = 0.03, rowAspect = 3.1, windowHeight = 0.38,
}

function Config.sellValue(income: number, mult: number?): number
	return math.max(1, math.floor(income * 60 * Config.sell.incomeMinutes * (mult or 1)))
end

-- the fast pan upgrade (owner 2026-11-05: a reference clip, then prototype/ice-ray-for-pets/upgrade-demo.html).
-- 0.9 s in the popup, which stays open: a build-up on the press (it also hides the server's answer
-- time), the impact when the answer lands, a spring settle and a shimmer. Buying again works from
-- 0.45 s. The pan answers in the world with a floor flash. Times in seconds from the impact unless
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
		frontView = true,
		trip = { go = 0.45, watch = 0.9, back = 0.4, -- glide there, watch the pan, glide home
			camBack = 24, camUp = 13, lookUp = 1, lookIn = 0.42 }, -- studs in front of the pan's front edge, height; looks this far into the pan
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

-- a rebirth (Round 4 phase 7, Animation Rules 3): the camera pushes in to face you at the booth, an ice
-- burst with one flash, then REBIRTH n! and the new coin multiplier slam in. The server has already
-- rebirthed and saved; the show only plays it. SKIP from the second rebirth; reduced motion halves it.
Config.show.rebirth = {
	beats = {
		{ name = "push", time = 0.9 },
		{ name = "burst", time = 0.5 },
		{ name = "slam", time = 1.9, keepOnSkip = true }, -- SKIP still shows what you got
		{ name = "back", time = 0.5, keepOnSkip = true },
	} :: { Beat },
	pushDistance = 9, pushHeight = 2.5, angle = 40, burstParts = 44, rays = 8, flash = true, -- angle: degrees round from "straight away from the booth"
}

-- ---------- Round 5 (owner 2026-11-02, prototype/ice-ray-for-pets/ROUND5-PROMPT.md) ----------
-- Shooting the ray: hold the mouse / your finger on a target (E or gamepad R2 aims at the nearest one
-- in front of you). Every target has a freeze meter on the server: it rises while someone aims at it
-- (1 / the freeze's seconds, Config.show.freeze, x timeScale) and melts back when nobody does. Up to
-- stuckAt a pet is scared and runs away; from stuckAt on it is stuck in the ice; at 1 the cube shuts.
Config.aim = {
	tickSeconds = 0.1,
	timeScale = 2.2, -- a shot freeze takes this much longer than the old prompt hold (time to see it run)
	thawPerSecond = 0.3, -- meter lost each second nobody aims at it
	stuckAt = 0.5,
	fleeSpeed = 4.5, -- studs a second while scared (wandering is Config.spawner.wanderSpeed; you walk 16)
	rangeGrace = 2, -- studs past the gun's range the server still accepts (lag)
	pickRadius = 0.12, -- a click / touch picks the nearest target this close on screen (share of the short side)
	autoAimDot = 0.3, -- E / R2: only targets in front of the camera (dot product) within range
	closerHintRange = 30, -- studs: a shot that reaches nothing says "Get closer!" if a pet is this near (QA 2026-11-08; value restored 2026-11-09, a guess)
	keys = { Enum.KeyCode.E, Enum.KeyCode.ButtonR2 },
	sendEvery = 0.1, -- the client sends a changed aim at most this often
	step = 0.02, -- the meter reaches clients in steps of this size
	refreezeSeconds = 0.6, -- zapping a dazed pet back
	reticle = 0.16, -- the aim ring on the nearest target, a share of the screen's short side
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
Config.gel = { price = 50e3, slow = 0.6, radius = 7, seconds = 6, cooldown = 10, throwRange = 45, flySeconds = 0.45 }

-- the Thaw Machine in every pan (owner 2026-11-09): a cube you bring home goes into your Pets as a
-- frozen pet. You walk to your Thaw Machine and put one in; when its time is up the pet hops out,
-- wanders your pan and starts earning. The time is saved (os.time), so it keeps thawing while you're away.
-- time = seconds[tier] x sizeFactor[size] x mutFactor[mutation] x islandGrowth^(island - 1), then / the
-- pan's thaw speed (each Slots level x perLevel faster). A Secret from island 1 takes 30 min (M size, no
-- mutation, Slots level 1); each island further out takes x islandGrowth longer. A second machine comes
-- with Slots level secondAt.
Config.thaw = {
	seconds = { Common = 15, Uncommon = 30, Rare = 60, Epic = 180, Legendary = 360, Mythic = 720, Secret = 1800 } :: { [string]: number },
	sizeFactor = { S = 0.85, M = 1, L = 1.2 } :: { [string]: number },
	mutFactor = { Frosty = 1.2, Golden = 1.5, Starry = 2 } :: { [string]: number },
	islandGrowth = 1.3, -- island 2 x1.3, island 3 x1.69, island 8 x6.3
	swapWeakest = true, -- pan full: a thawed pet that earns more takes the weakest pan pet's place (that one goes to Storage)
	useRange = 14, -- studs from the machine's pad the server accepts "put this pet in"
	perLevel = 1.33, -- 7 Slots levels: about x5.5 at the top, as fast as the old 19 levels at x1.1
	secondAt = Config.upgrades.pen.maxLevel - 1,
	tickSeconds = 0.25,
	-- machine 1 from the middle of the pan's back fence (x across, z toward the door); machine 2 is gap
	-- further right. padTop: the cube sits on the raised heat pad this high. haloY / haloRadius: the
	-- floating ring over the pad (MapArt builds it, ThawMachines spins it)
	machine = { x = -6.25, z = 5.5, gap = 8.5, padTop = 0.75, haloY = 6.5, haloRadius = 2.55 },
	queueGap = 3.4, queueX = 2.4, queueFrom = 5.5, -- waiting cubes line up along the left fence (queueX in from it), from the machine toward the door
	queueShown = 8, -- at most this many waiting cubes are drawn
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

-- how long a pet takes in the Thaw Machine (seconds); panLevel = the pan's Slots level (upgrades.pen)
function Config.thawSeconds(tier: string, size: string, zone: number, mut: string?, panLevel: number): number
	local T = Config.thaw
	local base = (T.seconds[tier] or 15) * (T.sizeFactor[size] or 1) * (if mut then T.mutFactor[mut] or 1 else 1)
	local far = T.islandGrowth ^ math.max(0, zone - 1)
	return math.max(1, math.round(base * far / (T.perLevel ^ math.max(0, panLevel - 1))))
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
-- One endless stat, never spent, trained in the Training Rink. It opens islands (each island's `need`),
-- and the further it is above an island's need the faster that island's pets freeze, up to maxSpeed:
-- speed = sqrt(power / need), so 4x the need is 2x faster and 25x the need hits the cap. Island 1 has
-- no need, so its speed is measured against speedFloor. minSeconds = the freeze time no amount of
-- power can skip, per rarity (real seconds with the ray on the pet). Past the last island the next
-- "need" (rink levels, pack sizes) keeps growing x needGrowth, so the rink never runs out.
Config.coldPower = {
	max = 1e30,
	maxSpeed = 5,
	speedFloor = 50,
	needGrowth = 20,
	minSeconds = { Common = 0.5, Uncommon = 1, Rare = 1.5, Epic = 2.5, Legendary = 3.5, Mythic = 4.5, Secret = 6 } :: { [string]: number },
}

-- The Training Rink: a private ice arena in the sky, one per pan slot. A wave of waveSize fire sprites
-- hops in from the edge toward the ice sculpture in the middle; hold the ray on one to freeze it for
-- Cold Power. No clock: the wave ends when every sprite is frozen or has reached the sculpture.
--   kinds: hold = seconds of ray to freeze it, value = its Cold Power before multipliers, size in studs,
--          weight = how often it's picked, fromLevel = the rink level it first shows up at
--   level  = Config.rinkLevel(your Cold Power): each level makes sprites worth x levelValue and a bit faster
--   combo  = sprites frozen in a row: +perHit each, up to x max; one reaching the sculpture resets it
--   auto   = the rink fires for you at autoFree of the hold speed (autoPass with the game pass), never a combo
export type SpriteKind = { hold: number, value: number, size: number, weight: number, fromLevel: number }
Config.rink = {
	origin = Vector3.new(0, 600, -400), spacing = 160, -- rink i stands at origin + ((i - 3.5) * spacing, 0, 0)
	radius = 30, wallHeight = 14, sculptureRadius = 4,
	-- sprites come in over an arc (degrees) in front of the sculpture; you start playerAt studs in front
	-- of it, facing them, so a gun's Range decides how early you can reach one. leaveAt = this far past
	-- the rim and you've left the rink. firstSpawn = seconds before a wave's first sprite.
	arc = 120, playerAt = 9, leaveAt = 20, firstSpawn = 0.6,
	waveSize = 30, spawnEvery = 0.9, maxAlive = 8,
	speed = 5, speedPerLevel = 0.4, speedMax = 9, -- studs a second toward the sculpture
	kinds = {
		small = { hold = 0.35, value = 1, size = 2.2, weight = 60, fromLevel = 0 },
		medium = { hold = 0.9, value = 3, size = 3.2, weight = 28, fromLevel = 0 },
		big = { hold = 1.8, value = 7, size = 4.4, weight = 12, fromLevel = 1 },
	} :: { [string]: SpriteKind },
	kindOrder = { "small", "medium", "big" },
	goldenChance = 0.05, goldenValue = 10, -- a golden sprite is a small one worth x10
	levelValue = 10,
	combo = { perHit = 0.1, max = 3 },
	thawPerSecond = 0.5, thawAfter = 0.3, -- a sprite's ice melts back this fast, this long after the ray leaves it
	autoFree = 0.25, autoPass = 1, autoRestart = 2, -- autoRestart: seconds before Auto starts the next wave
	boothRange = 30, cooldown = 1, tickSeconds = 0.1,
	arrowSeconds = 6, -- after "Need more Cold Power" the guide arrow points at the rink's door this long
}

-- where rink number `index` (a pan slot) floats
function Config.rinkCentre(index: number): Vector3
	local R = Config.rink
	return R.origin + Vector3.new((index - (Config.world.maxPlayers + 1) / 2) * R.spacing, 0, 0)
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
	local g = Config.coldPower.needGrowth
	local n = math.max(1, last) * g
	while n <= power do
		n *= g
	end
	return n
end

-- how many of those thresholds this Cold Power has passed (0 until island 2's need)
function Config.rinkLevel(power: number): number
	power = cleanPower(power)
	local level, last = 0, 0
	for _, z in Config.world.zones do
		if z.need > 0 and z.need <= power then
			level += 1
		end
		last = math.max(last, z.need)
	end
	local g = Config.coldPower.needGrowth
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
function Config.freezeSeconds(tier: string, size: string, power: number, zoneId: number, asleep: boolean?): number
	local F = Config.show.freeze
	local raw = (F.tierSeconds[tier] or 1) * (F.sizeFactor[size] or 1) * Config.aim.timeScale / Config.freezeSpeed(power, zoneId)
	if asleep then
		raw *= Config.night.sleepFreezeFactor
	end
	return math.max(Config.coldPower.minSeconds[tier] or 0, raw)
end

-- the Cold Power one frozen fire sprite gives: its value x golden x the rink level x the gun's Training
-- x the rebirth multiplier x the combo x the 2x Cold Power pass
function Config.rinkGain(kind: string, golden: boolean, level: number, gun: number, rebirths: number, combo: number, doubled: boolean): number
	local R = Config.rink
	local k = R.kinds[kind]
	if not k then
		return 0
	end
	local gain = k.value * (if golden then R.goldenValue else 1) * R.levelValue ^ math.max(0, level)
		* Config.gun(gun).training * Config.rebirthIncome(rebirths) * math.clamp(combo, 1, R.combo.max) * (if doubled then 2 else 1)
	-- to the nearest whole number, never 0 (rounding up made a small sprite at x1.1 worth 2)
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

return Config
