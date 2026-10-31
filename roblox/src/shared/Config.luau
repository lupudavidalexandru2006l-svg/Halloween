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
	gateCoins: number, -- coins to open it (owner 2026-10-30: zones open with coins; the pen no longer counts)
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
} :: { [string]: { label: string, bonus: number, seconds: number } }
Config.poseLoop = { "idle", "yawn", "idle", "jump", "idle", "dance" }
Config.sneezeChance = 0.08
Config.zapSlowdown = 0.5 -- a pet being held with Freeze acts at half speed, so a pose can be caught on purpose

Config.mutations = {
	Frosty = { bonus = 1.5 },
} :: { [string]: { bonus: number } }

Config.upgrades = { -- baseCost = the price of level 2; each step costs x1.5 the last (Game Plan 11)
	-- cube size: +12% a level for the first 4 levels (you can see it), then +2%
	ray = { name = "Ice Ray", baseCost = 40, costGrowth = 1.5, maxLevel = 20, lifeBonus = 0.02, bridgeBonus = 4, -- +2% cube life a level (owner 2026-10-30)
		cubeSize = { early = 0.12, earlyLevels = 4, late = 0.02 } },
	boots = { name = "Boots", baseCost = 64, costGrowth = 1.5, maxLevel = 15, speedBonus = 0.08 },
	backpack = { name = "Backpack", baseCost = 750, costGrowth = 1.5, maxLevel = 5, slowPerExtraCube = 0.08 },
	pen = { name = "Pen", baseCost = 150, costGrowth = 1.5, maxLevel = 19, slotsPerLevel = 5 }, -- Game Plan 11: +5 earning slots
} :: { [string]: { [string]: any } }
Config.upgradeIds = { "ray", "boots", "backpack", "pen" }
-- Pen and Storage (owner 2026-10-30): the pen's pets earn; every other banked pet waits in Storage
-- (kept forever, in the Index, earns nothing). Players equip by hand or press Equip best.
Config.pen = { baseSlots = 10, storageMax = 500,
	displayMax = 30, displayMargin = 2.5 } -- up to 30 of the pen's pets stand in it (prototype; Storage isn't shown in the world)
Config.carryHomeMinStuds = 4 -- funnel step 4 counts a cube carried at least this far out of the hub and back
Config.beachGateCoins = 500
Config.notYetCooldown = 2 -- seconds between two of the same "not yet" message
Config.bigWinRank = 5 -- banking Legendary or better sends a server-wide banner and a light pillar over your pen (Game Plan 14)
Config.index = { pageBonus = 0.1 } -- each full zone page (its 7 regular pets; the Secret is a bonus slot) = +10% coins forever
Config.income = { tickSeconds = 1 }
Config.sync = { seconds = 0.5 } -- the client's copy of its data is sent at most this often
Config.gatePromptOffset = 2.5 -- the gate prompt stands this far on the hub side of the gate
Config.oddsPushSeconds = 5 -- each player's own odds go to their zone signs this often (personal rares, own pity)
Config.shopOpenedCooldown = 2
Config.settingsDefault = { music = true, sound = true, reducedMotion = false, lowGraphics = false, unit = "C" }
-- Studio-only test switches (Port Plan 6, 6c): chat "/dev coins 5000", "/dev epic", "/dev chill", "/dev heat 2", "/dev ray 10", "/dev away 3600", "/dev wipe"
Config.dev = { maxCoins = 1e9, heatMax = 5, awayMax = 24 * 3600 }

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
	bands = { { below = 0, name = "cold" }, { below = 15, name = "cool" }, { below = 35, name = "warm" }, { below = 999, name = "hot" } },
}
Config.dazedSeconds = 8

Config.server = { maxPlayers = 6 }

Config.spawner = {
	-- owner 2026-10-30: Common and Uncommon pets are shared by everyone on the server; Rare and up
	-- spawn just for one player (only they see and can freeze it), each with their own pity
	personalRares = true,
	personalMaxPerZone = 3,
	maxPerZone = 9,
	respawnSeconds = 1.5,
	firstPetDistance = 12,
	-- "always one within about 3 seconds of walking": each zone keeps 2 Commons or Uncommons in its
	-- near band; other Commons spawn from farZMin; Rare and up only in the far half of the zone
	near = { [1] = { 8, 34 }, [2] = { 204, 236 } } :: { [number]: { number } },
	nearCount = 2,
	farZMin = { [1] = 60, [2] = 204 } :: { [number]: number },
	wanderSpeed = 2,
	pity = { graceFactor = 1.0, perMiss = 0.0015, maxBoost = 3 },
}

Config.bridge = { baseSeconds = 20 }
Config.bigChill = { everySeconds = 600, warnSeconds = 30, durationSeconds = 60 }

Config.away = { minSeconds = 60, capSeconds = 8 * 3600, rate = 0.25 } -- owner 2026-10-30: 25%, so a night away never skips a zone
Config.dailyGift = { baseCoins = 50, incomeMinutes = 10, streakBonus = 0.1, streakMax = 7, afterFirstBank = true } -- the gift box opens after your first bank

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
	-- scores come from the server's own counters and are clamped before writing (OrderedDataStore needs an integer under 2^63)
	limits = { frozen = 10000000, weekCoins = 1e13, freezesPerSecond = 1 },
	storePrefix = "LB_v1_",
	boards = {
		{ id = "pets_frozen", title = "Most pets frozen", kind = "alltime" },
		{ id = "rarest_pet", title = "Rarest pet found", kind = "alltime" },
		{ id = "coins_week", title = "Coins earned this week", kind = "weekly" },
	},
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
	tiles = { { id = "pets", label = "Pets" }, { id = "shop", label = "Shop" }, { id = "index", label = "Index" }, { id = "settings", label = "Settings" } },
	scale = { phone = 1, tablet = 1.2, pc = 1.35 },
	-- sizes are fractions of the screen's short side (Scale only, UI Rules); the Screen module places them
	tileSize = 0.13, tileGap = 0.02, coinsSize = { 0.3, 0.1 }, goalSize = { 0.42, 0.075 }, tempSize = { 0.21, 0.09 },
	topInset = 0.02, sideInset = 0.03, touchLift = 0.28, -- the coins sit above the thumbstick on touch screens
	popupSize = { 0.92, 0.78 }, popupLift = 0.04, promptSize = { 0.36, 0.115 }, -- world prompts keep this screen size at any distance
	bannerSeconds = 3, floatSeconds = 1.2, notYetSeconds = 1.6,
	pressDepth = 0.06, pressSeconds = 0.08, stroke = 3, corner = 0.18,
	gamepadKeys = { close = Enum.KeyCode.ButtonB, superFreeze = Enum.KeyCode.ButtonY, menu = Enum.KeyCode.ButtonSelect },
	keys = { pets = Enum.KeyCode.P, shop = Enum.KeyCode.B, index = Enum.KeyCode.I, close = Enum.KeyCode.Backspace, superFreeze = Enum.KeyCode.F }, -- Escape belongs to Roblox's own menu,
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
	-- one pen per player, up to 6 per server (owner 2026-10-30): two rows of three around the hub.
	-- Owner item: set the place's Server Size to 6 in Game Settings > Places.
	plots = {
		{ x = -52, z = -20 },
		{ x = 0, z = -20 },
		{ x = 52, z = -20 },
		{ x = -52, z = -44 },
		{ x = 0, z = -44 },
		{ x = 52, z = -44 },
	},
	penSize = Vector3.new(26, 1, 18),
	giftBox = Vector3.new(-26, 0, -8), -- between the front pens, by the path out
	boards = { Vector3.new(-52, 0, -60), Vector3.new(0, 0, -60), Vector3.new(52, 0, -60) }, -- the back of the hub, behind the back row of pens (six pens leave no room at the front), turned to face the spawn
	zones = {
		{ id = 1, key = "meadow", name = "Snowy Meadow", heat = 0.5, zMin = -2, zMax = 166, gateCoins = 0, signPos = Vector3.new(-16, 0, 4) },
		{ id = 2, key = "forest", name = "Pine Forest", heat = 0.8, zMin = 194, zMax = 372, gateCoins = 1000, signPos = Vector3.new(-16, 0, 202) }, -- starts at the gate
	} :: { Zone },
	river = { zMin = 168, zMax = 182, depth = 30 },
	mainBridge = { xMin = -74, xMax = -62 }, -- the free bridge is the long way round
	iceBridgeSpot = { xMin = -6, xMax = 6 }, -- the ice bridge sits on the straight line from the gate to the pens (frozen from either bank)
	gate = { z = 194, xMin = -10, xMax = 10 },
	beachGate = { z = 368 }, -- Sunny Beach (zone 3) starts here
}

-- Uploaded images (the prototype's painted icons and pet sprites, roblox/assets/images)
Config.images = {
	icons = {
		coin = "rbxassetid://114690725766316", bag = "rbxassetid://76257814527627", book = "rbxassetid://103706811541834",
		gear = "rbxassetid://84856334538368", gift = "rbxassetid://86444394737076", trophy = "rbxassetid://96802650316741",
	} :: { [string]: string },
	-- pets with no 3D model yet are drawn as these painted sprites, facing the camera (prototype)
	pets = {
		snowbun = "rbxassetid://92428027252754", waddles = "rbxassetid://85819786009594", mittenkit = "rbxassetid://80224010045349",
		pupcicle = "rbxassetid://99464046375243", frostfox = "rbxassetid://75892873565699", blizzard_yeti = "rbxassetid://93201949480148",
		aurora_owl = "rbxassetid://82434091513318", snowglobe_drake = "rbxassetid://118494815244289", conehog = "rbxassetid://73502496724119",
		hopsprout = "rbxassetid://95878437320181", capmouse = "rbxassetid://107833749569236", mossfawn = "rbxassetid://117305047075010",
		lanternbug = "rbxassetid://74192529771490", mapleguard_bear = "rbxassetid://75624001245030", bloomhorn_stag = "rbxassetid://81929702575504",
		glowshroom_mammoth = "rbxassetid://88722165161459",
	} :: { [string]: string },
}

Config.ui.tileIcons = { pets = Config.images.pets.snowbun, shop = Config.images.icons.bag, index = Config.images.icons.book, settings = Config.images.icons.gear }
Config.ui.silhouetteTransparency = 0.25
Config.ui.petSpriteScale = 1.25 -- a pet sprite is this many times the pet's height wide

-- The world teaches (prototype client.js): a green arrow to a pet in your first minutes and home while
-- you carry, a diamond over the nearest pet you can't reach yet, a light pillar over your pen
Config.guide = {
	earlyPets = 3, -- the arrow points to pets until you own this many
	arrowDistance = 6.5, arrowHideNear = 8, arrowY = 0.5, arrowBob = 0.35, arrowBobSpeed = 4,
	markerRange = 45, markerY = 1, markerBob = 0.3, markerSpin = 1.5,
	beaconRadius = 3.2, beaconHeight = 70, beaconTransparency = 0.78, beaconPulse = 0.06,
}
-- the ice ray: a small gun in every player's right hand, a beam while you hold Freeze
Config.ray = { beamCore = 0.28, beamGlow = 0.84, armRaise = 90, tipSize = 0.76, sparkleRate = 20 }
-- extra pet looks (prototype syncWild / makeCube)
Config.petFx = {
	ringScale = 1.8, ringSpin = 0.5, shadowScale = 1.0, starCount = 3, starRadius = 0.9, starHeight = 1.45, starSpin = 3,
	rareSparkleRate = 2, frostySparkleRate = 6, crackBelow = 0.35, crackLines = 9, edgeTransparency = 0.45,
	popSeconds = 0.25,
}
Config.mapFx = { gateBarsDrop = 9, gateBarsSeconds = 1.2, giftBob = 0.6, giftSway = 0.15, bridgeFlashSeconds = 4 }

-- Trees (shade) and sun patches: prototype config.js buildScenery(), same seed and ranges, so the
-- shade and sun spots are exactly where the artifact has them (Shared/Scenery makes the list)
Config.scenery = {
	seed = 1234,
	pathHalfWidth = 9, -- the main path stays open
	riverClear = { 160, 200 }, -- and both river banks
	bands = {
		{ kind = "snowpine", trees = 26, x = { -72, 72 }, z = { 14, 160 }, r = { 4, 6.5 },
			sun = 7, sunX = { -60, 60 }, sunZ = { 30, 150 }, sunR = { 7, 12 } },
		{ kind = "pine", trees = 70, x = { -74, 74 }, z = { 204, 368 }, r = { 4.5, 7.5 },
			sun = 4, sunX = { -55, 55 }, sunZ = { 215, 355 }, sunR = { 6, 10 } },
	},
}

-- The look of the world (MapArt, ported from prototype scenery.js). Shapes come from
-- ReplicatedStorage.SceneryMeshes (roblox/tools/make_scenery_meshes.ps1); plain parts stand in if missing.
Config.art = {
	seed = 77, -- props (mounds, rocks, mushrooms...) are placed with the prototype's generator too
	treeUnitRadius = 2.4, -- a tree of shade radius r is drawn at scale r / 2.4 (prototype)
	hillTrees = 160, -- decorative trees on the hills outside the play area
	hills = { cell = 8, reach = 96, maxHeight = 34, falloff = 14, power = 1.6, scale = 6, base = -12 },
	waterY = -0.8, -- the river surface; you fall through it onto the catcher and land back on the bank
	catcherY = -3,
	bedY = -4,
	bankStones = 90,
	props = { mounds = 40, rocks = 22, crystals = 14, mushrooms = 40, bushes = 50, logs = 10 },
	lanternEvery = 18,
	penFenceGap = 10, -- the open side of each pen faces the path
	penPostEvery = 3.2,
	gatePostEvery = 4,
	beachPostEvery = 3.5,
	statue = Vector3.new(-26, 0, -56),
	snowman = Vector3.new(46, 0, 112),
	giantMushroom = Vector3.new(-44, 0, 296),
	lamps = { Vector3.new(-12, 0, -3), Vector3.new(12, 0, -3), Vector3.new(-26, 0, -32), Vector3.new(26, 0, -32) },
	benches = { { pos = Vector3.new(-12, 0, -58), ry = 0 }, { pos = Vector3.new(12, 0, -58), ry = 0 } },
	clouds = { cover = 0.55, density = 0.6 },
}

Config.camera = { fov = 70, minZoom = 10, maxZoom = 40, carryFov = 74, fovSeconds = 0.4,
	-- the prototype's framing at spawn: high and behind, looking ahead, so carried cubes never hide you
	startHeight = 15, startBack = 21, startLookAhead = 10, frameSettleSeconds = 0.25 }
Config.effects = { pillarSeconds = 8, pillarHeight = 60, burstParts = 12, beamSeconds = 0.15, snowRate = 60, showRank = 4 } -- showRank: Epic and up get a pillar in your pen

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

function Config.cubeSizeFactor(rayLevel: number): number
	local c = Config.upgrades.ray.cubeSize
	local n = rayLevel - 1
	return 1 + c.early * math.min(n, c.earlyLevels) + c.late * math.max(0, n - c.earlyLevels)
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
