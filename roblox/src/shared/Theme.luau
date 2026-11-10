--!strict
-- Theme: every colour in the game. No one-off colours anywhere else (UI Rules, World Rules).

local Theme = {
	ink = Color3.fromHex("1b1433"),
	go = Color3.fromHex("3ccf6e"),
	no = Color3.fromHex("ff5a5f"),
	coin = Color3.fromHex("ffc93c"),
	coinFace = Color3.fromHex("ffe38a"), -- the coin counter block (prototype)
	goal = Color3.fromHex("6fd0ff"), -- the goal bar block (prototype)
	info = Color3.fromHex("3aa8ff"),
	infoDeep = Color3.fromHex("2a6fc2"), -- small info text on the cream panel (the light blue washed out)
	panel = Color3.fromHex("fff8ec"),
	slot = Color3.fromHex("d6dcef"), -- an empty Index slot: light, so the missing pet's silhouette shows
	silhouette = Color3.new(0, 0, 0), -- a pet you haven't found yet
	white = Color3.new(1, 1, 1),

	ice = Color3.fromHex("bfe9ff"),
	iceDeep = Color3.fromHex("2f6bff"),
	snow = Color3.fromHex("f4f8ff"),
	snowFar = Color3.fromHex("dfe9f6"),
	grass = Color3.fromHex("7fbf5a"),
	grassFar = Color3.fromHex("a9cf95"),
	forest = Color3.fromHex("4d8a4a"),
	water = Color3.fromHex("4aa3e0"),
	wood = Color3.fromHex("9a6b43"),
	hub = Color3.fromHex("e9f2ff"),
	path = Color3.fromHex("cfdcec"),
	pen = Color3.fromHex("f7e3b0"),
	sunPatch = Color3.fromHex("fff3a0"),
	gift = Color3.fromHex("ff5a8a"),
	-- the Robux shop's cards, one colour per kind: the 2x Coins pass (premium purple), coin packs
	-- (coin gold), Super Freeze packs (ice blue). Buy buttons are always go-green.
	shopCards = {
		pass = Color3.fromHex("aa50e6"),
		coins = Color3.fromHex("ffb020"),
		charges = Color3.fromHex("3aa8ff"),
		chill = Color3.fromHex("2ec4c4"),
	} :: { [string]: Color3 },
	board = Color3.fromHex("2b1f5c"),
	-- the leaderboards: each board's header colour, its plain rows, and the top 3's medal rows
	boards = {
		pets_frozen = Color3.fromHex("3aa8ff"), -- info blue, like the Freeze prompt
		rarest_pet = Color3.fromHex("aa50e6"), -- Epic purple
		coins_week = Color3.fromHex("ffb020"), -- coin gold (the shop's coin cards)
	} :: { [string]: Color3 },
	boardRow = Color3.fromHex("3d3a8f"),
	medals = { Color3.fromHex("ffc93c"), Color3.fromHex("cdd8ec"), Color3.fromHex("e8945a") },
	-- Ranger Bo, the tutorial guide: a park ranger in the game's ice blue, with a red scarf like the snowmen
	tutorial = {
		skin = Color3.fromHex("e8b98f"),
		coat = Color3.fromHex("3aa8ff"),
		pants = Color3.fromHex("2d3561"),
		hat = Color3.fromHex("9a6b43"),
		hatBand = Color3.fromHex("ffc93c"),
		scarf = Color3.fromHex("e8414a"),
		portrait = Color3.fromHex("bfe9ff"), -- behind his face on the card
		focus = Color3.fromHex("3ccf6e"), -- the glow on the thing he's showing (go-green, like the arrow)
		skip = Color3.fromHex("9aa5b1"), -- quiet grey: Skip shouldn't compete with Next
	},

	tiers = {
		Common = Color3.fromHex("9aa5b1"),
		Uncommon = Color3.fromHex("4cc35a"),
		Rare = Color3.fromHex("3c8cf0"),
		Epic = Color3.fromHex("aa50e6"),
		Legendary = Color3.fromHex("fab01e"),
		Mythic = Color3.fromHex("f04678"),
		Secret = Color3.fromHex("2a2a2a"),
	} :: { [string]: Color3 },

	tiles = {
		pets = Color3.fromHex("ff6fa5"),
		shop = Color3.fromHex("ff9f1c"),
		index = Color3.fromHex("3aa8ff"),
		settings = Color3.fromHex("8f7cff"),
		daily = Color3.fromHex("2ec27e"),
	} :: { [string]: Color3 },

	-- the world's look, from prototype scenery.js (MapArt)
	art = {
		snowA = Color3.fromHex("f7fbff"), snowB = Color3.fromHex("cfdff3"), pathSnow = Color3.fromHex("d3e0ef"),
		grassA = Color3.fromHex("86c35c"), forestHill = Color3.fromHex("4d8a4a"), dirt = Color3.fromHex("c7a273"),
		riverBed = Color3.fromHex("7c9fbf"), water = Color3.fromHex("3d9ce0"), stone = Color3.fromHex("9aa9bd"),
		plaza = Color3.fromHex("e3eefb"), straw = Color3.fromHex("f2d17e"),
		trunk = Color3.fromHex("7a5233"), snowCap = Color3.fromHex("f6fbff"),
		snowPine = { Color3.fromHex("2f6b4f"), Color3.fromHex("357a57"), Color3.fromHex("3d8560"), Color3.fromHex("45906a") },
		pine = { Color3.fromHex("2e6a3a"), Color3.fromHex("357a42"), Color3.fromHex("3d8a47"), Color3.fromHex("46964f") },
		plank = Color3.fromHex("b07a4a"), post = Color3.fromHex("8a5a36"), rail = Color3.fromHex("9a6b43"),
		penPost = Color3.fromHex("b77b48"), penRail = Color3.fromHex("c98f58"), benchLeg = Color3.fromHex("5d3b22"),
		sandPost = Color3.fromHex("d9b26a"), sandRail = Color3.fromHex("e8c27a"),
		crystal = Color3.fromHex("bff1ff"), crystalGlow = Color3.fromHex("9fe8ff"), iceBar = Color3.fromHex("9fe3ff"),
		spawnPad = Color3.fromHex("9fdcff"),
		lampPost = Color3.fromHex("3a3f63"), lampGlow = Color3.fromHex("fff1c4"), lanternGlow = Color3.fromHex("ffd47a"),
		mound = Color3.fromHex("f4f9ff"), rock = Color3.fromHex("93a2b8"), bush = Color3.fromHex("3f8c46"),
		stem = Color3.fromHex("fff1dc"), cap = Color3.fromHex("e2453f"),
		snowman = Color3.fromHex("fbfdff"), carrot = Color3.fromHex("ff8a2a"), scarf = Color3.fromHex("e8414a"), hat = Color3.fromHex("2d3561"),
		peakLow = Color3.fromHex("b7c7dc"), peakGreen = Color3.fromHex("6f9a68"), peakSnow = Color3.fromHex("fbfdff"),
		statueBase = Color3.fromHex("dbe8f7"), shade = Color3.fromHex("283c78"), sunGlow = Color3.fromHex("ffec8c"),
	},

	-- the tunnel's sections (Config.world.islands[i].theme): floor, path strip, walls, the wall's
	-- rounded top, lamp light, the island's own colour (gate glow, sign trim, landmark accents) and
	-- the soft tint the camera gets while you're there (MapController)
	islands = {
		meadow = { floor = Color3.fromHex("f7fbff"), path = Color3.fromHex("d3e0ef"), wall = Color3.fromHex("cfdff3"), wallTop = Color3.fromHex("f6fbff"),
			wallBase = Color3.fromHex("9fb4cf"), light = Color3.fromHex("cfeaff"), accent = Color3.fromHex("6fd0ff"), tint = Color3.fromHex("f2f8ff"), haze = Color3.fromHex("bfe9ff") },
		forest = { floor = Color3.fromHex("86c35c"), path = Color3.fromHex("c7a273"), wall = Color3.fromHex("3f7a45"), wallTop = Color3.fromHex("2e6a3a"),
			wallBase = Color3.fromHex("6b4a2e"), light = Color3.fromHex("ffd47a"), accent = Color3.fromHex("3ccf6e"), tint = Color3.fromHex("fffaf0"), haze = Color3.fromHex("d8efc8") },
		grove = { floor = Color3.fromHex("b98ad8"), path = Color3.fromHex("e2c7f2"), wall = Color3.fromHex("7a4fa8"), wallTop = Color3.fromHex("9b6bd0"),
			wallBase = Color3.fromHex("4e3270"), light = Color3.fromHex("f0b8ff"), accent = Color3.fromHex("c070ff"), tint = Color3.fromHex("fbf2ff"), haze = Color3.fromHex("e9d6ff"),
			far = Color3.fromHex("9a72c0"), peak = Color3.fromHex("8a6ab0") },
		-- Round 4 phase 6: islands 4-10 (hotter and hotter, still bright and warm) and the next update's tint.
		-- far = the ground outside the cliffs, peak = the far hills (MapArt's far scenery)
		beach = { floor = Color3.fromHex("f6dfa0"), path = Color3.fromHex("fff1cf"), wall = Color3.fromHex("e9c97a"), wallTop = Color3.fromHex("fff3d6"),
			wallBase = Color3.fromHex("c9a35a"), light = Color3.fromHex("fff2b0"), accent = Color3.fromHex("1fbfe8"), tint = Color3.fromHex("fffaf0"), haze = Color3.fromHex("cfefff"),
			far = Color3.fromHex("45b8e6"), peak = Color3.fromHex("e8c98a") },
		jungle = { floor = Color3.fromHex("4fae4a"), path = Color3.fromHex("b88a55"), wall = Color3.fromHex("2f7a3a"), wallTop = Color3.fromHex("3f9a45"),
			wallBase = Color3.fromHex("5a4028"), light = Color3.fromHex("c8ff9a"), accent = Color3.fromHex("14d38a"), tint = Color3.fromHex("f4fff2"), haze = Color3.fromHex("cdeccf"),
			far = Color3.fromHex("3d9a45"), peak = Color3.fromHex("2f7a3a") },
		desert = { floor = Color3.fromHex("f2c879"), path = Color3.fromHex("e8bd6e"), wall = Color3.fromHex("d9a35a"), wallTop = Color3.fromHex("f0c37a"),
			wallBase = Color3.fromHex("b07a3a"), light = Color3.fromHex("ffe08a"), accent = Color3.fromHex("ff9f1c"), tint = Color3.fromHex("fff6e6"), haze = Color3.fromHex("ffe9c4"),
			far = Color3.fromHex("efc27a"), peak = Color3.fromHex("d9a05a") },
		canyon = { floor = Color3.fromHex("e08f55"), path = Color3.fromHex("f0bd8a"), wall = Color3.fromHex("b5582f"), wallTop = Color3.fromHex("d97a45"),
			wallBase = Color3.fromHex("8a3f22"), light = Color3.fromHex("ffc48a"), accent = Color3.fromHex("ff5a8a"), tint = Color3.fromHex("fff1e6"), haze = Color3.fromHex("ffd9bf"),
			far = Color3.fromHex("d47a45"), peak = Color3.fromHex("b5582f") },
		volcano = { floor = Color3.fromHex("8a6a5e"), path = Color3.fromHex("b09a8e"), wall = Color3.fromHex("5e4a48"), wallTop = Color3.fromHex("7a5f58"),
			wallBase = Color3.fromHex("3e3034"), light = Color3.fromHex("ff9a4a"), accent = Color3.fromHex("ff5a1f"), tint = Color3.fromHex("fff0e8"), haze = Color3.fromHex("ffc9a8"),
			far = Color3.fromHex("6e5652"), peak = Color3.fromHex("5e4a48") },
		lavalake = { floor = Color3.fromHex("7a6280"), path = Color3.fromHex("a896ad"), wall = Color3.fromHex("4e4058"), wallTop = Color3.fromHex("6a5470"),
			wallBase = Color3.fromHex("2f2838"), light = Color3.fromHex("ff7a3a"), accent = Color3.fromHex("ff3d6a"), tint = Color3.fromHex("fff0ea"), haze = Color3.fromHex("ffb898"),
			far = Color3.fromHex("ff6a1f"), peak = Color3.fromHex("4e4058") },
		magma = { floor = Color3.fromHex("8f5446"), path = Color3.fromHex("b8806a"), wall = Color3.fromHex("5a3a38"), wallTop = Color3.fromHex("7a4a40"),
			wallBase = Color3.fromHex("3a2428"), light = Color3.fromHex("ffb03a"), accent = Color3.fromHex("ffcc1f"), tint = Color3.fromHex("fff4e0"), haze = Color3.fromHex("ffc58a"),
			far = Color3.fromHex("ff7a1a"), peak = Color3.fromHex("5a3a38") },
		suntemple = { floor = Color3.fromHex("fff0b8"), path = Color3.fromHex("ffe08a"), wall = Color3.fromHex("f0c860"), wallTop = Color3.fromHex("fff3c4"),
			wallBase = Color3.fromHex("d9a840"), light = Color3.fromHex("fff2a0"), accent = Color3.fromHex("ffd23a"), tint = Color3.fromHex("fffbe8"), haze = Color3.fromHex("fff3c8") },
	} :: { [string]: { [string]: Color3 } },
	-- each island's ground and path material (MapArt / WorldService); missing = grass and dirt
	islandMats = {
		meadow = { floor = Enum.Material.Snow, path = Enum.Material.Snow }, beach = { floor = Enum.Material.Sand, path = Enum.Material.Sand },
		desert = { floor = Enum.Material.Sand, path = Enum.Material.Sand }, canyon = { floor = Enum.Material.Sandstone, path = Enum.Material.Ground },
		volcano = { floor = Enum.Material.Basalt, path = Enum.Material.Slate }, lavalake = { floor = Enum.Material.Basalt, path = Enum.Material.Slate },
		magma = { floor = Enum.Material.Basalt, path = Enum.Material.Slate },
	} :: { [string]: { floor: Enum.Material, path: Enum.Material } },
	-- the islands' props, trees, hazards and landmarks (Round 4 phase 6, MapArt)
	islandArt = {
		toadCaps = { Color3.fromHex("c070ff"), Color3.fromHex("ff6aa8"), Color3.fromHex("5fd0ff") }, toadSpot = Color3.fromHex("fff4ff"), toadStem = Color3.fromHex("f6ead8"),
		palmTrunk = Color3.fromHex("c9925a"), palmLeaf = Color3.fromHex("3fbf4a"), palmLeafDark = Color3.fromHex("2f9a3a"), coconut = Color3.fromHex("7a4a28"),
		umbrella = { Color3.fromHex("ff5a5f"), Color3.fromHex("ffd34a"), Color3.fromHex("3aa8ff") }, umbrellaStripe = Color3.fromHex("fff8ec"),
		shell = Color3.fromHex("ffb0c0"), starfish = Color3.fromHex("ff8a3c"), sea = Color3.fromHex("45b8e6"), foam = Color3.fromHex("ffffff"),
		lighthouseA = Color3.fromHex("ff4a55"), lighthouseB = Color3.fromHex("fff8ec"), lamp = Color3.fromHex("fff2a0"),
		jungleLeaf = { Color3.fromHex("2f9a3a"), Color3.fromHex("3fbf5a"), Color3.fromHex("1f8a4a") }, jungleTrunk = Color3.fromHex("8a6a45"),
		vine = Color3.fromHex("3f9a45"), waterfall = Color3.fromHex("8fe3ff"), pool = Color3.fromHex("3fb8e6"), bigFlower = Color3.fromHex("ff5a8a"),
		cactus = Color3.fromHex("4fae4a"), cactusDark = Color3.fromHex("3a8a3a"), cactusFlower = Color3.fromHex("ff5a8a"), dune = Color3.fromHex("f6d28a"),
		pot = Color3.fromHex("c96a3a"), hoodoo = Color3.fromHex("c9663a"), hoodooBand = Color3.fromHex("f0b07a"), hoodooCap = Color3.fromHex("8a4a2a"),
		charred = Color3.fromHex("4a3a38"), ember = Color3.fromHex("ff7a2a"), ash = Color3.fromHex("d8cdc8"),
		obsidian = Color3.fromHex("3a2f4a"), obsidianGlow = Color3.fromHex("ff6a3a"), crystal = Color3.fromHex("ffcc4a"),
		lava = Color3.fromHex("ff6a1f"), lavaHot = Color3.fromHex("ffb03a"), lavaRim = Color3.fromHex("4a3a3a"), smoke = Color3.fromHex("e8dcd6"),
		core = Color3.fromHex("ffb01f"), coreRing = Color3.fromHex("5a3a38"),
		-- each world's gate towers (MapArt GATE_TOWERS): colours the islands didn't have yet
		minaretTeal = Color3.fromHex("2fc4b8"), forgeIron = Color3.fromHex("4a3c40"), forgeBrass = Color3.fromHex("e0a63a"),
		marble = Color3.fromHex("fff6e0"), sunGold = Color3.fromHex("ffcc2a"), shrineDoor = Color3.fromHex("2f3a2a"),
	},
	hubTint = Color3.fromHex("ffffff"),

	-- the hub: plaza, the pans (soil bed, straw top, fences, door), booths
	hubArt = {
		plaza = Color3.fromHex("e3eefb"), plazaRing = Color3.fromHex("c9dcf2"), wall = Color3.fromHex("dbe7f5"), wallTop = Color3.fromHex("f6fbff"),
		soil = Color3.fromHex("8a5a36"), soilDark = Color3.fromHex("6b4428"), panTop = Color3.fromHex("f2d17e"), panPath = Color3.fromHex("e8c06a"),
		door = Color3.fromHex("9fe3ff"), gaugeTube = Color3.fromHex("f4f8ff"), gaugeFill = Color3.fromHex("6fd0ff"), gaugeFrame = Color3.fromHex("3a3f63"),
		boothWood = Color3.fromHex("b77b48"), boothCounter = Color3.fromHex("fff8ec"), awningStripe = Color3.fromHex("fff8ec"),
		endCap = Color3.fromHex("dff6ff"), endCapGlow = Color3.fromHex("bfe9ff"),
	},
	-- the fast pan upgrade's flash cools into these (a new Look uses its own glow, panLooks)
	upgradeGlow = { slots = Color3.fromHex("ffd45a"), cold = Color3.fromHex("7fdcff") } :: { [string]: Color3 },
	booths = {
		sell = Color3.fromHex("ffc93c"), equipment = Color3.fromHex("3aa8ff"), rebirth = Color3.fromHex("aa50e6"), pan = Color3.fromHex("3ccf6e"),
	} :: { [string]: Color3 },

	-- effects and guides (prototype client.js)
	fx = {
		arrow = Color3.fromHex("3ccf6e"), beacon = Color3.fromHex("7dffb0"),
		beamCore = Color3.new(1, 1, 1), beamGlow = Color3.fromHex("7fe3ff"),
		gunBody = Color3.fromHex("e9f6ff"), gunTip = Color3.fromHex("7fe3ff"),
		star = Color3.fromHex("ffd34a"), shadow = Color3.fromHex("1b1433"), frost = Color3.fromHex("dff6ff"),
		giftBody = Color3.fromHex("ff5a8a"), giftLid = Color3.fromHex("ff7ca3"), giftRibbon = Color3.fromHex("ffd34a"),
		superFrozen = Color3.fromHex("5f8dff"),
		zzz = Color3.fromHex("e6e9ff"),
		sleepLash = Color3.fromHex("2a1e24"), -- the closed-eye curve on a sleeping 3D pet's eyelid
		coinPopTop = Color3.fromHex("d8ff6b"), coinPopBottom = Color3.fromHex("3ccf6e"), -- the "+N" pop: lime fading to go-green
		frostTint = Color3.fromHex("a9dcff"), -- a freezing pet's colour cools to this
		crystal = Color3.fromHex("d9f6ff"), crack = Color3.fromHex("ffffff"), flash = Color3.new(1, 1, 1),
		aurora = { Color3.fromHex("5dffb0"), Color3.fromHex("7fd0ff"), Color3.fromHex("c88bff") },
	},

	-- mutations: a tint over the whole pet + sparkles in this colour (PetVisuals)
	mut = {
		Golden = { tint = Color3.fromHex("ffc21f"), sparkle = Color3.fromHex("fff2a8"), fill = 0.45 },
		Starry = { tint = Color3.fromHex("2b2a8f"), sparkle = Color3.fromHex("fffbe0"), fill = 0.35 },
	} :: { [string]: { tint: Color3, sparkle: Color3, fill: number } },

	-- the freeze shows' light pillars and titles: the tier colour, but one that glows (Secret's dark
	-- grey can't glow, so its light is violet with the dark tier colour as the title outline)
	-- a pan's Look (Round 4 phase 5, Config.pan.looks): fence posts, rails and the floor, each with
	-- its material; glow = the show's build-up glow; crystal / aurora = the extras of the last two
	panLooks = {
		-- Round 5 (owner's picture): white rail fences round a bright striped lawn
		garden = { post = Color3.fromHex("fbfdff"), rail = Color3.fromHex("f4f8ff"), floor = Color3.fromHex("6cc24a"),
			postMat = Enum.Material.SmoothPlastic, railMat = Enum.Material.SmoothPlastic, floorMat = Enum.Material.Grass, glow = Color3.fromHex("b8ff9a"),
			stripe = Color3.fromHex("9ee373") },
		wood = { post = Color3.fromHex("8a5a36"), rail = Color3.fromHex("a8703f"), floor = Color3.fromHex("c08a55"),
			postMat = Enum.Material.Wood, railMat = Enum.Material.Wood, floorMat = Enum.Material.WoodPlanks, glow = Color3.fromHex("ffc27a") },
		stone = { post = Color3.fromHex("8d93a6"), rail = Color3.fromHex("b3b9c9"), floor = Color3.fromHex("c3c8d6"),
			postMat = Enum.Material.Slate, railMat = Enum.Material.Cobblestone, floorMat = Enum.Material.Slate, glow = Color3.fromHex("e6ebff") },
		ice = { post = Color3.fromHex("9fe3ff"), rail = Color3.fromHex("dff6ff"), floor = Color3.fromHex("d8f1ff"),
			postMat = Enum.Material.Glass, railMat = Enum.Material.Ice, floorMat = Enum.Material.Ice, glow = Color3.fromHex("9fe8ff"),
			crystal = Color3.fromHex("bff1ff") },
		aurora = { post = Color3.fromHex("5b4fc4"), rail = Color3.fromHex("5dffb0"), floor = Color3.fromHex("cfe0ff"),
			postMat = Enum.Material.Glass, railMat = Enum.Material.Neon, floorMat = Enum.Material.Ice, glow = Color3.fromHex("c88bff"),
			crystal = Color3.fromHex("d9c8ff"), aurora = { Color3.fromHex("5dffb0"), Color3.fromHex("7fd0ff"), Color3.fromHex("c88bff") } },
	} :: { [string]: { [string]: any } },
	panBounce = Color3.fromHex("ff5a5f"), -- the gauge flashes this when a cube is too hot for the pan
	tierGlow = {
		Common = Color3.fromHex("c9d1da"), Uncommon = Color3.fromHex("7fe38a"), Rare = Color3.fromHex("6fb2ff"),
		Epic = Color3.fromHex("c98bff"), Legendary = Color3.fromHex("ffcc4a"), Mythic = Color3.fromHex("ff6f9a"),
		Secret = Color3.fromHex("b48cff"),
	} :: { [string]: Color3 },

	-- the guns' glow, beam and particle colours by tier (stand-in tiers 1-10 from the Ice Ray level
	-- until phase 4 brings the real guns; each step looks fancier than the last)
	guns = {
		{ core = Color3.fromHex("ffffff"), glow = Color3.fromHex("7fe3ff"), spark = Color3.fromHex("dff6ff") },
		{ core = Color3.fromHex("ffffff"), glow = Color3.fromHex("5fd0ff"), spark = Color3.fromHex("cfefff") },
		{ core = Color3.fromHex("f0fbff"), glow = Color3.fromHex("3fb8ff"), spark = Color3.fromHex("bfe9ff") },
		{ core = Color3.fromHex("e8f4ff"), glow = Color3.fromHex("2f8bff"), spark = Color3.fromHex("9fd6ff") },
		{ core = Color3.fromHex("f2fff8"), glow = Color3.fromHex("33e0c0"), spark = Color3.fromHex("bffff0") },
		{ core = Color3.fromHex("f4fff4"), glow = Color3.fromHex("5dffb0"), spark = Color3.fromHex("c88bff") },
		{ core = Color3.fromHex("f6f0ff"), glow = Color3.fromHex("9b7bff"), spark = Color3.fromHex("dccfff") },
		{ core = Color3.fromHex("fff0fb"), glow = Color3.fromHex("d070ff"), spark = Color3.fromHex("ffd0f6") },
		{ core = Color3.fromHex("ffffff"), glow = Color3.fromHex("6fe8ff"), spark = Color3.fromHex("ffffff") },
		{ core = Color3.fromHex("fffbe8"), glow = Color3.fromHex("ffd34a"), spark = Color3.fromHex("fff3b0") },
	} :: { { core: Color3, glow: Color3, spark: Color3 } },

	-- Round 5 map remake (MapArt v3): the winter village round the hub and the islands' cliffs
	village = {
		houses = { Color3.fromHex("8fd9c4"), Color3.fromHex("ffb79a"), Color3.fromHex("c3a6ff"), Color3.fromHex("9fd0ff"), Color3.fromHex("ffe08a"), Color3.fromHex("ff9fc0") },
		roofs = { Color3.fromHex("d94f5c"), Color3.fromHex("3d6fb6"), Color3.fromHex("6a4fb0"), Color3.fromHex("2f8a6a"), Color3.fromHex("c9663a") },
		trim = Color3.fromHex("fffaf0"), door = Color3.fromHex("8a5a36"), window = Color3.fromHex("ffe7a8"), brick = Color3.fromHex("b5584a"),
		stone = Color3.fromHex("b9c3d4"), stoneDark = Color3.fromHex("8e9ab0"), stoneWarm = Color3.fromHex("d9cbb6"),
		tileA = Color3.fromHex("e6eef9"), tileB = Color3.fromHex("cddcf0"), tileWarm = Color3.fromHex("f1e2c8"),
		lawn = Color3.fromHex("8fd16a"), lawnSnow = Color3.fromHex("eef7ff"), hedge = Color3.fromHex("3f8c46"),
		flowers = { Color3.fromHex("ff5a8a"), Color3.fromHex("ffd34a"), Color3.fromHex("8f7cff"), Color3.fromHex("ff8a3c"), Color3.fromHex("5fd0ff") },
		iron = Color3.fromHex("2d3354"), water = Color3.fromHex("8fe3ff"), flag = Color3.fromHex("ff5a5f"),
		crate = Color3.fromHex("c08a55"), barrel = Color3.fromHex("9a6b43"), gold = Color3.fromHex("ffc93c"),
	},
	cliffs = {
		meadow = { rock = Color3.fromHex("a9bcd6"), rockDark = Color3.fromHex("8597b3"), top = Color3.fromHex("f7fbff"), path = Color3.fromHex("c6d6ea"), edge = Color3.fromHex("93a6c2") },
		forest = { rock = Color3.fromHex("9a7a5a"), rockDark = Color3.fromHex("7a5c40"), top = Color3.fromHex("5aa04f"), path = Color3.fromHex("c7a273"), edge = Color3.fromHex("8d7a66") },
		grove = { rock = Color3.fromHex("8a6ab0"), rockDark = Color3.fromHex("6a4f8e"), top = Color3.fromHex("b98ad8"), path = Color3.fromHex("e2c7f2"), edge = Color3.fromHex("9a7ab8") },
		-- Round 4 phase 6
		beach = { rock = Color3.fromHex("e8cf96"), rockDark = Color3.fromHex("cdb07a"), top = Color3.fromHex("6fcf6a"), path = Color3.fromHex("fff1cf"), edge = Color3.fromHex("d9bf8a") },
		jungle = { rock = Color3.fromHex("7a9a5a"), rockDark = Color3.fromHex("5a7a46"), top = Color3.fromHex("3f9a45"), path = Color3.fromHex("b88a55"), edge = Color3.fromHex("7a6a50") },
		desert = { rock = Color3.fromHex("e0a860"), rockDark = Color3.fromHex("c48a45"), top = Color3.fromHex("f2c879"), path = Color3.fromHex("e8bd6e"), edge = Color3.fromHex("c49a5a") },
		canyon = { rock = Color3.fromHex("c9663a"), rockDark = Color3.fromHex("a84a2a"), top = Color3.fromHex("e8955a"), path = Color3.fromHex("f0bd8a"), edge = Color3.fromHex("b56a45") },
		volcano = { rock = Color3.fromHex("6e5652"), rockDark = Color3.fromHex("54403e"), top = Color3.fromHex("8a6a5e"), path = Color3.fromHex("b09a8e"), edge = Color3.fromHex("7a6660") },
		lavalake = { rock = Color3.fromHex("5e4e68"), rockDark = Color3.fromHex("463a52"), top = Color3.fromHex("7a6280"), path = Color3.fromHex("a896ad"), edge = Color3.fromHex("6a5a72") },
		magma = { rock = Color3.fromHex("6a4240"), rockDark = Color3.fromHex("523232"), top = Color3.fromHex("8f5446"), path = Color3.fromHex("b8806a"), edge = Color3.fromHex("7a5048") },
		suntemple = { rock = Color3.fromHex("f0d48a"), rockDark = Color3.fromHex("d9b660"), top = Color3.fromHex("fff0b8"), path = Color3.fromHex("ffe08a"), edge = Color3.fromHex("e0c070") },
	} :: { [string]: { [string]: Color3 } },

	-- Round 5: the hotbar, Slow Gel, the aim ring, Heat Critters, ray-tag shields, the Thaw Machine
	round5 = {
		hotbar = Color3.fromHex("5b6bd6"), hotbarOn = Color3.fromHex("3ccf6e"), hotbarLocked = Color3.fromHex("9aa5b1"),
		gel = Color3.fromHex("c34dff"), gelLight = Color3.fromHex("e7a8ff"),
		reticle = Color3.fromHex("7fe3ff"), reticleFull = Color3.fromHex("ffffff"), reticlePlayer = Color3.fromHex("ff9f1c"),
		critter = Color3.fromHex("ff7a3c"), critterGlow = Color3.fromHex("ffb35c"), critterSteam = Color3.fromHex("fff1e6"),
		shield = Color3.fromHex("7fd0ff"), tagged = Color3.fromHex("bfe9ff"),
		machine = Color3.fromHex("ff8f5a"), machineTrim = Color3.fromHex("fff8ec"), machineGlow = Color3.fromHex("ffd47a"),
		-- the Thaw Machine's sci-fi parts: navy frame, brushed metal, a see-through core tube, the
		-- holo screen, and the heat it glows with (ice blue idle -> amber -> hot orange as it thaws)
		machineDark = Color3.fromHex("2c3654"), machineMetal = Color3.fromHex("c3cede"), machineGlass = Color3.fromHex("d8f6ff"),
		machineScreen = Color3.fromHex("0f1d36"), machineCold = Color3.fromHex("6fe3ff"), machineWarm = Color3.fromHex("ffc24d"),
		machineHot = Color3.fromHex("ff7a45"), machineReady = Color3.fromHex("5cf29a"),
		codes = Color3.fromHex("3ccf6e"),
	},

	font = Enum.Font.FredokaOne,
	lipDarken = 0.5, -- the lip under every block face is its colour mixed this far toward ink
	temp = { cold = Color3.fromHex("6fd0ff"), cool = Color3.fromHex("5fd6b4"), warm = Color3.fromHex("ffb347"), hot = Color3.fromHex("ff6b5a"), chill = Color3.fromHex("d9f4ff") } :: { [string]: Color3 },
	-- the island banner (Config.ui.islandBanner): each island's name in a bright version of its own
	-- colour (ink outline, readable on the dark strip), the recommended gun in ice cyan
	islandTitle = {
		meadow = Color3.fromHex("bfe9ff"), forest = Color3.fromHex("6ee07a"), grove = Color3.fromHex("d59bff"),
		beach = Color3.fromHex("ffd86b"), jungle = Color3.fromHex("3fe0a8"), desert = Color3.fromHex("ffc46b"),
		canyon = Color3.fromHex("ff9a5c"), volcano = Color3.fromHex("ff7a4a"), lavalake = Color3.fromHex("ffa23a"),
		magma = Color3.fromHex("ff5a6e"),
	} :: { [string]: Color3 },
	islandStrip = Color3.fromHex("1b1433"), -- ink
	islandValue = Color3.fromHex("5ee6ff"),
	shade = Color3.fromRGB(0, 0, 0), -- the dim behind a popup
	shadeTransparency = 0.55,
}

return Theme
