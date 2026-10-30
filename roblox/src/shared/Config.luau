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
	gatePets: number,
	signPos: Vector3,
}

local Config = {}

Config.version = 1

Config.data = {
	storeName = "IceRayPlayerData_v1",
	qaStoreSuffix = "_QA", -- Studio and test servers never touch the live store (QA Rules 8)
	retries = 5,
	retryBase = 0.5, -- seconds, doubles each retry
	autosaveSeconds = 90,
	bindToCloseSeconds = 25,
	receiptsKept = 50,
}

Config.player = {
	walkSpeed = 16,
	freezeRange = 10,
	freezeHold = 1.0,
	refreezeHold = 0.35,
	interactHold = 0.4,
	freezeCooldown = 0.3,
	rateLimitPerSecond = 12,
	maxSpeedTolerance = 1.6, -- server flags positions that move faster than this x walk speed
}

Config.tiers = {
	{ name = "Common", odds = 59.995, cubeLife = 90, income = 1, rank = 1 },
	{ name = "Uncommon", odds = 25, cubeLife = 70, income = 3, rank = 2 },
	{ name = "Rare", odds = 10, cubeLife = 50, income = 10, rank = 3 },
	{ name = "Epic", odds = 4, cubeLife = 40, income = 30, rank = 4 },
	{ name = "Legendary", odds = 0.9, cubeLife = 30, income = 100, rank = 5 },
	{ name = "Mythic", odds = 0.1, cubeLife = 25, income = 400, rank = 6 },
	{ name = "Secret", odds = 0.005, cubeLife = 20, income = 1500, rank = 7 }, -- 1 in 20,000, every zone
} :: { Tier }
Config.incomeZoneMultiplier = 4

Config.poses = {
	idle = { label = "Idle", bonus = 1.0, seconds = 2.4 },
	yawn = { label = "Yawn", bonus = 1.2, seconds = 1.3 },
	jump = { label = "Jump", bonus = 1.2, seconds = 0.9 },
	dance = { label = "Dance", bonus = 1.5, seconds = 1.6 },
	sneeze = { label = "Mid-Sneeze", bonus = 2.0, seconds = 0.7 },
} :: { [string]: { label: string, bonus: number, seconds: number } }
Config.poseLoop = { "idle", "yawn", "idle", "jump", "idle", "dance" }
Config.sneezeChance = 0.08

Config.mutations = {
	Frosty = { bonus = 1.5 },
} :: { [string]: { bonus: number } }

Config.upgrades = { -- baseCost = the price of level 2
	ray = { name = "Ice Ray", baseCost = 40, costGrowth = 1.6, maxLevel = 20, lifeBonus = 0.20, bridgeBonus = 4, cubeSizeBonus = 0.04 },
	boots = { name = "Boots", baseCost = 64, costGrowth = 1.6, maxLevel = 15, speedBonus = 0.08 },
	backpack = { name = "Backpack", baseCost = 750, costGrowth = 3.0, maxLevel = 5, slowPerExtraCube = 0.08 },
} :: { [string]: { [string]: any } }
Config.upgradeIds = { "ray", "boots", "backpack" }
Config.penSlots = 40

Config.melt = {
	shade = 0.5,
	sun = 1.5,
	night = 0.6, -- Game Plan 12
	hubHeat = 0.3,
	tickSeconds = 0.1, -- server melt tick
}

-- Temperature: a readable version of the melt speed (owner request 2026-10-30). Worked out from the
-- melt numbers, never the other way round: degrees C = atZeroMelt + perMelt x melt speed.
-- Zone, shade, sun, night and the Big Chill all move it. Shown on the HUD chip and the zone signs.
Config.temperature = {
	unit = "C", -- players can switch to F in Settings
	atZeroMelt = -20,
	perMelt = 30,
	bands = { { 0, "cold" }, { 15, "cool" }, { 35, "warm" }, { 999, "hot" } },
}
Config.dazedSeconds = 8

Config.spawner = {
	maxPerZone = 9,
	respawnSeconds = 1.5,
	firstPetDistance = 12,
	nearUntilPets = 3,
	nearZ = { 8, 34 },
	farZMin = 60,
	wanderSpeed = 2,
	pity = { graceFactor = 1.0, perMiss = 0.0015, maxBoost = 3 },
}

Config.bridge = { baseSeconds = 20 }
Config.bigChill = { everySeconds = 600, warnSeconds = 30, durationSeconds = 60 }

Config.away = { minSeconds = 60, capSeconds = 8 * 3600, rate = 1.0 }
Config.dailyGift = { baseCoins = 50, incomeMinutes = 10, streakBonus = 0.1, streakMax = 7 }

Config.monetization = {
	-- Owner items: create the developer product in the Creator Dashboard and paste its id here.
	superFreeze = { productId = 0, robux = 15, minTier = "Rare", walkAwayStuds = 18 },
}

Config.leaderboards = {
	size = 10,
	refreshSeconds = 60, -- read + redraw boards (cached on the server)
	writeSeconds = 120, -- each player's scores are written at most this often (DataStore limits)
	rankScanSize = 100, -- "your rank" looks this far down the board; past it shows "100+"
	weeklyResetDay = 1, -- 1 = Monday, UTC calendar day (not a countdown)
	weeklyResetLabel = "Resets every Monday",
	storePrefix = "LB_v1_",
	boards = {
		{ id = "pets_frozen", title = "Most pets frozen", kind = "alltime" },
		{ id = "rarest_pet", title = "Rarest pet found", kind = "alltime" },
		{ id = "coins_week", title = "Coins earned this week", kind = "weekly" },
	},
	cosmeticReward = "Top 3 each week get a glowing name plate (cosmetic only)",
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
	} :: { [string]: { value: string?, fields: { string } } },
	lastActions = { "zapping", "carrying", "in_pen", "in_menu", "exploring" },
}

Config.sounds = {
	-- owner items: Roblox-licensed or our own uploads; 0 = silent stand-in
	music = 0.45,
	sfx = 0.8,
	ids = {
		click = 0, zap = 0, freeze = 0, coin = 0, bank = 0, reveal_rare = 0, no = 0, buy = 0,
		melt = 0, chill = 0, gift = 0, unlock = 0, bridge = 0, music_meadow = 0, music_forest = 0,
	} :: { [string]: number },
	maxSame = 3,
	streakReset = 1.5,
}

Config.ui = {
	tiles = { { id = "shop", label = "Shop" }, { id = "index", label = "Index" }, { id = "settings", label = "Settings" } },
	scale = { phone = 1, tablet = 1.2, pc = 1.35 },
}

Config.lighting = {
	clockTime = 14,
	brightness = 2.5,
	atmosphereDensity = 0.3,
	saturation = 0.1,
}

-- World layout in studs. North (hub) is -Z, zones run south (+Z).
Config.world = {
	bounds = { xMin = -78, xMax = 78, zMin = -62, zMax = 372 },
	spawn = Vector3.new(0, 3, -6),
	hubZMax = -2,
	plots = { -- one pen per player (up to 4 per server); walk in to bank
		{ x = -51, z = -24 },
		{ x = -17, z = -24 },
		{ x = 17, z = -24 },
		{ x = 51, z = -24 },
	},
	penSize = Vector3.new(26, 1, 18),
	giftBox = Vector3.new(0, 0, -30),
	boards = { Vector3.new(-40, 0, -4), Vector3.new(-24, 0, -1), Vector3.new(24, 0, -1) }, -- hub edge, turned to face the spawn
	zones = {
		{ id = 1, key = "meadow", name = "Snowy Meadow", heat = 0.5, zMin = -2, zMax = 166, gatePets = 0, signPos = Vector3.new(-16, 0, 4) },
		{ id = 2, key = "forest", name = "Pine Forest", heat = 0.8, zMin = 186, zMax = 372, gatePets = 8, signPos = Vector3.new(-16, 0, 202) },
	} :: { Zone },
	river = { zMin = 168, zMax = 182, depth = 30 },
	mainBridge = { xMin = -54, xMax = -42 },
	iceBridgeSpot = { xMin = 18, xMax = 30 },
	gate = { z = 194, xMin = -10, xMax = 10 },
}

Config.camera = { fov = 70 }

function Config.tier(name: string): Tier
	for _, t in Config.tiers do
		if t.name == name then
			return t
		end
	end
	error("unknown tier " .. name)
end

function Config.upgradeCost(id: string, level: number): number
	local u = Config.upgrades[id]
	return math.round(u.baseCost * u.costGrowth ^ (level - 2)) -- level 2 costs baseCost
end

function Config.zone(id: number): Zone?
	for _, z in Config.world.zones do
		if z.id == id then
			return z
		end
	end
	return nil
end

return Config
