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
	skipAll = Color3.fromHex("aa50e6"), -- the Pets list's Skip all bar: the premium royal purple of the 2x Coins card
	-- the Robux shop's cards, one colour per kind: the 2x Coins pass (premium purple), coin packs
	-- (coin gold), Super Freeze packs (ice blue). Buy buttons are always go-green.
	shopCards = {
		pass = Color3.fromHex("aa50e6"),
		coins = Color3.fromHex("ffb020"),
		charges = Color3.fromHex("3aa8ff"),
		chill = Color3.fromHex("2ec4c4"),
		power = Color3.fromHex("35c8e8"), -- Cold Power packs: frosty cyan
	} :: { [string]: Color3 },
	-- owner 2026-11-13: "different backgrounds for the things you buy": every product its own card colour
	-- (its little world is mixed from it), so two cards side by side never look the same. Green stays
	-- the Buy button's alone. A product missing here falls back to its kind's colour above.
	shopItemCards = {
		doubleCoins = Color3.fromHex("aa50e6"), -- royal purple
		coinsSmall = Color3.fromHex("ff8a2e"), -- warm orange
		coinsMedium = Color3.fromHex("ff5a9e"), -- candy pink
		coinsBig = Color3.fromHex("ffb020"), -- coin gold
		superFreeze3 = Color3.fromHex("3a8cff"), -- ice blue
		bigChill = Color3.fromHex("2ec4c4"), -- teal
		autoTrain = Color3.fromHex("6a5cff"), -- indigo
		doublePower = Color3.fromHex("35c8e8"), -- frosty cyan
		powerSmall = Color3.fromHex("ff6a5a"), -- coral
		powerBig = Color3.fromHex("d14fff"), -- magenta
	} :: { [string]: Color3 },
	-- shop v2 badges: the "+45% MORE" sticker in present pink (a bonus, never red), and the Best Value
	-- ribbon in gold on ink, so the two never read as the same thing
	shopBadge = { more = Color3.fromHex("ff5a8a"), bestBack = Color3.fromHex("1b1433"), bestText = Color3.fromHex("ffd34a"), bonus = Color3.fromHex("2f9e5a") },
	-- the Shop's own frame (owner 2026-11-12: "the colour scheme isn't good"; from the reference shops, one
	-- saturated theme colour round everything): a royal-blue-to-violet frame, a deep indigo well the cards
	-- sit in, an ice-cyan title bar with snow on it, and light text on the well
	shopFrame = {
		top = Color3.fromHex("4c6ef5"), bottom = Color3.fromHex("7048e8"),
		wellTop = Color3.fromHex("2c2f8f"), wellBottom = Color3.fromHex("3a1f80"),
		-- round 3 (2026-11-13): a sunny title bar against the cool frame, like the references' orange bar on
		-- purple; it's the Shop tile's own orange, so the popup matches the button that opened it
		titleTop = Color3.fromHex("ffe14d"), titleBottom = Color3.fromHex("ff9a1f"),
		snow = Color3.fromHex("f4f8ff"), text = Color3.fromHex("bfe9ff"), glow = Color3.fromHex("9fd8ff"),
	},
	board = Color3.fromHex("2b1f5c"),
	-- the leaderboards: each board's header colour, its plain rows, and the top 3's medal rows
	boards = {
		pets_frozen = Color3.fromHex("3aa8ff"), -- info blue, like the Freeze prompt
		rarest_pet = Color3.fromHex("aa50e6"), -- Epic purple
		coins_week = Color3.fromHex("ffb020"), -- coin gold (the shop's coin cards)
	} :: { [string]: Color3 },
	boardRow = Color3.fromHex("3d3a8f"),
	medals = { Color3.fromHex("ffc93c"), Color3.fromHex("cdd8ec"), Color3.fromHex("e8945a") },
	-- Captain Frost, the tutorial guide (owner 2026-11-14: "a guy who would freeze animals"): an ice-blue
	-- parka with white fur trim, a navy cryo suit, a steel cryo tank glowing ice cyan, goggles, a red scarf
	tutorial = {
		skin = Color3.fromHex("e8b98f"),
		coat = Color3.fromHex("2f8cff"), -- parka, and his name pill / ribbon
		fur = Color3.fromHex("f4fbff"), -- fur trim, hat, shoulder pads
		suit = Color3.fromHex("22305e"), -- navy cryo suit: legs, belt, harness, tank frame
		glove = Color3.fromHex("bfe9ff"),
		boot = Color3.fromHex("1a2140"),
		steel = Color3.fromHex("c7d3e0"), -- tank caps, buckle, goggle rims, jet nozzles
		glow = Color3.fromHex("5fe4ff"), -- the cryo glow: tank, lenses, badge, jets
		ice = Color3.fromHex("a8e6ff"), -- the little frozen cube on his belt
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
	upgradeGlow = { slots = Color3.fromHex("ffd45a"), cold = Color3.fromHex("7fdcff"), trainer = Color3.fromHex("5ee6ff") } :: { [string]: Color3 },
	booths = {
		sell = Color3.fromHex("ffc93c"), equipment = Color3.fromHex("3aa8ff"), rebirth = Color3.fromHex("aa50e6"), pan = Color3.fromHex("3ccf6e"),
	} :: { [string]: Color3 },
	-- the top buttons (owner 2026-11-12): Equipment in its booth's blue; Pan is a garden plot, rich soil
	-- with a strip of grass along the top (the reference's "Garden" button)
	topButtons = { equipment = Color3.fromHex("3aa8ff"), soil = Color3.fromHex("8a5232"), grass = Color3.fromHex("6fd04a") },
	-- Cold Power (2026-11-10). power = the Cold Power number and its bars everywhere; heat* = the gun's
	-- heat arc. The Frost Training Yard (2026-11-10, replaces the sky rink): each station's own palette,
	-- warm targets (a snowman, a heat bag, a magma golem, a little sun) that frost over as you shoot them.
	-- title = its floating "x5 Cold Power" sign, in the reference's lime / yellow / purple / orange order.
	training = {
		power = Color3.fromHex("5ee6ff"), frost = Color3.fromHex("bfe9ff"), frostGlow = Color3.fromHex("8ff0ff"),
		heatCool = Color3.fromHex("5ee6ff"), heatWarm = Color3.fromHex("ffb020"), heatHot = Color3.fromHex("ff5a5f"), -- the gun's heat arc
		shatter = Color3.fromHex("ffd34a"), -- the big "+N" when a target freezes solid and shatters
		pad = Color3.fromHex("ece6f7"), padSide = Color3.fromHex("9b92b8"), padEdge = Color3.fromHex("6d6390"),
		-- Trainer looks v2 (owner 2026-11-12: "study the reference better... polished, more in theme"). Every
		-- level is the same kit in its own three colours, like the reference's neon shrine: body / bodyDark (the
		-- blocks), floor / floorInner (the stage), neon (every edge), accent (lanterns, glyphs, small glows),
		-- snow (caps), panel (the doorway behind the target). The rest are the target's and the flankers' own.
		-- snowman = Frost Arch; levels 2-10 are named by their theme (TrainingArt).
		stations = {
			snowman = {
				title = Color3.fromHex("7ee35a"),
				body = Color3.fromHex("2b4a92"), bodyDark = Color3.fromHex("1d336d"), floor = Color3.fromHex("27427f"), floorInner = Color3.fromHex("30508f"),
				neon = Color3.fromHex("63efff"), accent = Color3.fromHex("eafcff"), snow = Color3.fromHex("f4faff"), panel = Color3.fromHex("172a5a"),
				ice = Color3.fromHex("bfe6ff"), iceShade = Color3.fromHex("98d2f7"), pine = Color3.fromHex("2c7f8e"), pineDark = Color3.fromHex("216877"),
				wood = Color3.fromHex("b77b48"), woodDark = Color3.fromHex("8a5530"),
				hat = Color3.fromHex("ff5a5f"), hatBand = Color3.fromHex("ffd34a"), ring = Color3.fromHex("ff5a5f"), ringLight = Color3.fromHex("fff8ec"),
				carrot = Color3.fromHex("ff9a3c"), coal = Color3.fromHex("2b2340"), scarf = Color3.fromHex("3aa8ff"),
			},
			-- v3 (owner 2026-11-12): levels 2-10, themed on the owner's photo. coal / cheek = the targets' faces.
			peppermint = {
				title = Color3.fromHex("ff6fae"),
				body = Color3.fromHex("c7213a"), bodyDark = Color3.fromHex("8e1028"), floor = Color3.fromHex("a8182f"), floorInner = Color3.fromHex("bd2440"),
				neon = Color3.fromHex("ff9ec4"), accent = Color3.fromHex("fff4f7"), snow = Color3.fromHex("fffafa"), panel = Color3.fromHex("6e0c20"),
				stripeA = Color3.fromHex("fff8f4"), stripeB = Color3.fromHex("e8283e"), mint = Color3.fromHex("5fe3b0"), mintDark = Color3.fromHex("2fb58a"),
				stick = Color3.fromHex("fff6ee"), wrap = Color3.fromHex("ffb3d1"), coal = Color3.fromHex("2b2340"), cheek = Color3.fromHex("ff8fb0"),
			},
			gingerbread = {
				title = Color3.fromHex("ffb347"),
				body = Color3.fromHex("a65a28"), bodyDark = Color3.fromHex("6e3a17"), floor = Color3.fromHex("8a4820"), floorInner = Color3.fromHex("9c5426"),
				neon = Color3.fromHex("fff0d8"), accent = Color3.fromHex("ff7ab8"), snow = Color3.fromHex("fffaf2"), panel = Color3.fromHex("4e2610"),
				cookie = Color3.fromHex("c87a3c"), plate = Color3.fromHex("fff8ec"), tree = Color3.fromHex("4fd67a"), treeDark = Color3.fromHex("2fb05a"),
				gumRed = Color3.fromHex("ff4d6d"), gumGreen = Color3.fromHex("4fd67a"), gumYellow = Color3.fromHex("ffd34a"), gumPurple = Color3.fromHex("b46bff"),
				coal = Color3.fromHex("3a1f10"), cheek = Color3.fromHex("ff8fb0"),
			},
			workshop = {
				title = Color3.fromHex("7ee35a"),
				body = Color3.fromHex("1f7a4c"), bodyDark = Color3.fromHex("135536"), floor = Color3.fromHex("186343"), floorInner = Color3.fromHex("1e7550"),
				neon = Color3.fromHex("ffd34a"), accent = Color3.fromHex("ff5a5f"), snow = Color3.fromHex("f4faff"), panel = Color3.fromHex("0e3d27"),
				wood = Color3.fromHex("a8693a"), red = Color3.fromHex("d9323f"), redDark = Color3.fromHex("a3202e"), gold = Color3.fromHex("ffcc33"), goldDark = Color3.fromHex("c9921c"),
				giftA = Color3.fromHex("ff5a8a"), giftB = Color3.fromHex("3aa8ff"), giftC = Color3.fromHex("ffd34a"), giftD = Color3.fromHex("b46bff"),
				white = Color3.fromHex("fff8ec"), black = Color3.fromHex("1d1b2b"), skin = Color3.fromHex("f6c9a0"),
				coal = Color3.fromHex("1d1b2b"), cheek = Color3.fromHex("ff7a8a"),
			},
			ice = {
				title = Color3.fromHex("5ee6ff"),
				body = Color3.fromHex("4fb8f0"), bodyDark = Color3.fromHex("2b86c4"), floor = Color3.fromHex("3a9fdb"), floorInner = Color3.fromHex("48aee6"),
				neon = Color3.fromHex("e8fdff"), accent = Color3.fromHex("ffffff"), snow = Color3.fromHex("ffffff"), panel = Color3.fromHex("1d5f96"),
				ice = Color3.fromHex("bdeeff"), iceDeep = Color3.fromHex("7fd3fa"), crest = Color3.fromHex("8fdcff"), flake = Color3.fromHex("ffffff"),
				coat = Color3.fromHex("24305e"), belly = Color3.fromHex("fff8f0"), beak = Color3.fromHex("ff9a3c"), scarf = Color3.fromHex("ff5a8a"),
				coal = Color3.fromHex("141a33"), cheek = Color3.fromHex("ff9ab8"),
			},
			reindeer = {
				title = Color3.fromHex("ffd23a"),
				body = Color3.fromHex("b8222f"), bodyDark = Color3.fromHex("7e1420"), floor = Color3.fromHex("9a1a27"), floorInner = Color3.fromHex("ad2030"),
				neon = Color3.fromHex("ffd34a"), accent = Color3.fromHex("fff1c9"), snow = Color3.fromHex("f8fbff"), panel = Color3.fromHex("5c0e18"),
				antler = Color3.fromHex("e8b84a"), gold = Color3.fromHex("ffcc33"), wreath = Color3.fromHex("2f9a52"), wreathDark = Color3.fromHex("1f7a3e"), berry = Color3.fromHex("ff3b4e"),
				pine = Color3.fromHex("2c8a56"), pineDark = Color3.fromHex("1f6e44"),
				fur = Color3.fromHex("9a5a32"), furLight = Color3.fromHex("ecd0a8"), hoof = Color3.fromHex("3a2416"), nose = Color3.fromHex("ff2a3a"),
				coal = Color3.fromHex("2b1a10"), cheek = Color3.fromHex("ff9ab0"),
			},
			crystal = {
				title = Color3.fromHex("c77dff"),
				body = Color3.fromHex("5b37c4"), bodyDark = Color3.fromHex("3f2494"), floor = Color3.fromHex("4c2cae"), floorInner = Color3.fromHex("5a36c2"),
				neon = Color3.fromHex("7ff3ff"), accent = Color3.fromHex("ff8af0"), snow = Color3.fromHex("f6f2ff"), panel = Color3.fromHex("26135e"),
				crystal = Color3.fromHex("d5b0ff"), crystalLight = Color3.fromHex("f0e2ff"),
				rock = Color3.fromHex("a996dc"), rockLight = Color3.fromHex("cbbdf2"), core = Color3.fromHex("ff3fd8"), eyes = Color3.fromHex("8ff8ff"),
			},
			aurora = {
				title = Color3.fromHex("5dffc8"),
				body = Color3.fromHex("2b2470"), bodyDark = Color3.fromHex("1a1650"), floor = Color3.fromHex("241d62"), floorInner = Color3.fromHex("2e2678"),
				neon = Color3.fromHex("46f0c8"), accent = Color3.fromHex("c46bff"), snow = Color3.fromHex("f0f2ff"), panel = Color3.fromHex("140f3d"),
				wave1 = Color3.fromHex("46f0c8"), wave2 = Color3.fromHex("3ab0ff"), wave3 = Color3.fromHex("c46bff"), star = Color3.fromHex("ffe36b"),
				trunk = Color3.fromHex("1a1650"), bloom = Color3.fromHex("b8fff0"), bloomTint = Color3.fromHex("d4b8ff"),
				owl = Color3.fromHex("f7f6ff"), owlShade = Color3.fromHex("d6dbf3"), speck = Color3.fromHex("8f97c4"), perch = Color3.fromHex("6e4a2e"),
				beak = Color3.fromHex("ffb020"), eye = Color3.fromHex("ffd84a"), pupil = Color3.fromHex("1a1650"),
			},
			citadel = {
				title = Color3.fromHex("ff8a2a"),
				body = Color3.fromHex("c4234a"), bodyDark = Color3.fromHex("8a1535"), floor = Color3.fromHex("a81c40"), floorInner = Color3.fromHex("bd2550"),
				neon = Color3.fromHex("ffd34a"), accent = Color3.fromHex("ffffff"), snow = Color3.fromHex("fff8fb"), panel = Color3.fromHex("5a0c22"),
				gold = Color3.fromHex("ffcc33"), banner = Color3.fromHex("ffcc33"), roof = Color3.fromHex("6e1030"),
				armor = Color3.fromHex("d3dcec"), armorDark = Color3.fromHex("8d9ab3"), leather = Color3.fromHex("6e4a2e"), blade = Color3.fromHex("eef4ff"),
				plume = Color3.fromHex("ff5a5f"), eye = Color3.fromHex("7ff3ff"),
			},
			northstar = {
				title = Color3.fromHex("ffe36b"),
				body = Color3.fromHex("2348c9"), bodyDark = Color3.fromHex("172f8a"), bodyLight = Color3.fromHex("2f58dc"), floor = Color3.fromHex("1f3fae"), floorInner = Color3.fromHex("2a4cc0"),
				neon = Color3.fromHex("ffd34a"), accent = Color3.fromHex("fff3c4"), snow = Color3.fromHex("f6f8ff"), panel = Color3.fromHex("0f1f5c"),
				gold = Color3.fromHex("ffc933"), goldLight = Color3.fromHex("fff0a0"), tree = Color3.fromHex("1d3a9e"), cloud = Color3.fromHex("ffffff"),
				coal = Color3.fromHex("1b1433"), cheek = Color3.fromHex("ff8fb0"),
			},
		} :: { [string]: { [string]: Color3 } },
	},

	-- effects and guides (prototype client.js)
	fx = {
		arrow = Color3.fromHex("3ccf6e"), beacon = Color3.fromHex("7dffb0"),
		-- the guide chevrons and the arrow over the target (owner 2026-11-16: "you can't really see the arrows,
		-- maybe a darker blue"): one deep blue on every island, so it stands out on snow, grass and sand
		guideArrow = Color3.fromHex("1f4fd8"), guideArrowTop = Color3.fromHex("2c62ff"),
		-- the night walls at the tunnel mouth (Config.nightClose): candy violet, never dark
		nightWall = Color3.fromHex("9b7bff"),
		beamCore = Color3.new(1, 1, 1), beamGlow = Color3.fromHex("7fe3ff"),
		gunBody = Color3.fromHex("e9f6ff"), gunTip = Color3.fromHex("7fe3ff"),
		star = Color3.fromHex("ffd34a"), shadow = Color3.fromHex("1b1433"), frost = Color3.fromHex("dff6ff"),
		giftBody = Color3.fromHex("ff5a8a"), giftLid = Color3.fromHex("ff7ca3"), giftRibbon = Color3.fromHex("ffd34a"),
		-- the Free Gift as a frozen treasure (owner 2026-11-13: "something more relevant to our game"): a
		-- pink chest with gold bands locked in a clear ice cube with frosty white edges, on a snow mound
		giftIce = Color3.fromHex("7fcfff"), giftFrost = Color3.fromHex("f2fbff"), giftShard = Color3.fromHex("7fd0ff"),
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

	-- sizes (Config.sizes): the word's colour on name tags, the Pets list and the reveal card; none is a tier colour
	sizes = {
		Big = Color3.fromHex("1fb5a8"),
		Giant = Color3.fromHex("ff7a1a"),
		Huge = Color3.fromHex("ff3b30"),
	} :: { [string]: Color3 },

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

	-- the world E prompts (owner 2026-11-13: the green pill was "not a good choice"): a deep frosty indigo
	-- pill that reads on snow and grass alike and means no one action colour, a white keycap with the key
	-- in ink, the action in white, what it's on in ice blue, and an ice-cyan sweep while you hold
	prompt = {
		body = Color3.fromHex("2c2f8f"),
		key = Color3.fromHex("ffffff"),
		object = Color3.fromHex("bfe9ff"),
		sweep = Color3.fromHex("7fe3ff"),
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

-- MapSpectacle's giant outside decor (owner 2026-11-13): full candy colours, brighter than the play
-- area's own, so each island's skyline pops
local hex = Color3.fromHex
Theme.spectacle = {
	white = hex("ffffff"), cream = hex("fff0c8"),
	trunk = hex("9a5a2b"), trunkLight = hex("c27c3e"),
	pine = { hex("1fb85a"), hex("2ed46b"), hex("52e57f") },
	leaves = { hex("3bd45a"), hex("7be83a"), hex("1fbf6e") },
	leavesPink = { hex("ff7ac8"), hex("ff4fa8"), hex("ffa3dc") },
	caps = { hex("ff3d7f"), hex("a24bff"), hex("1fc8ff"), hex("ff8a1f") },
	firefly = hex("fff36b"),
	palm = { hex("2edb6a"), hex("18b85a") }, coconut = hex("7a4520"),
	rainbow = { hex("ff3b3b"), hex("ff8a1f"), hex("ffe135"), hex("3bd45a"), hex("2e8bff"), hex("a24bff") },
	templeA = hex("4fc3a1"), templeB = hex("3aa88a"), vine = hex("2fb84a"),
	gold = hex("ffc21a"), emerald = hex("22ff8a"),
	cliff = hex("c98b5a"), grass = hex("49e05a"), water = hex("3fd8ff"),
	sand = hex("f5b942"), sandLight = hex("ffd873"), sunCore = hex("fff27a"), cactus = hex("2fcb5a"),
	crystal = { hex("ff4fd8"), hex("3fe7ff"), hex("b66bff"), hex("7cff6b") },
	cyan = hex("2ef2ff"), nova = hex("ff4fd8"), violet = hex("8a3cff"), pink = hex("ff4fb8"),
	volcano = hex("ff5a2e"), volcanoDark = hex("b8322a"), lava = hex("ff6a00"), lavaHot = hex("ffc21a"),
	smoke = hex("9a8c98"), obsidian = hex("3b2a5a"),
	-- ground detail and the sun patches (owner 2026-11-13)
	shell = hex("ffc2d6"), starfish = hex("ff7a59"), dryBush = hex("c9a35a"), ice = hex("9fe8ff"),
	flowers = { hex("ff4fb8"), hex("ffe135"), hex("ff8a1f"), hex("a24bff"), hex("ffffff") },
	sunRay = hex("ffd21f"), sunRayLight = hex("fff3a0"), sunCoreRing = hex("ff9f1c"),
}

-- each place's own sign and guide colour (owner 2026-11-13: "thematic with the islands, not green"):
-- the gate sign of an open island and the guide arrow on the ground. Green stays only for "READY TO
-- OPEN" (green = go). Forest's own accent is go-green, so its sign and arrow are warm wood instead.
Theme.placeColor = {
	hub = hex("4fc3ff"), meadow = hex("4fc3ff"), forest = hex("e0822b"), grove = hex("b45cff"),
	beach = hex("1fbfe8"), jungle = hex("12c9b4"), desert = hex("ff9f1c"), canyon = hex("ff5a8a"),
	volcano = hex("ff5a1f"), lavalake = hex("ff3d6a"), magma = hex("ffbf1f"), suntemple = hex("ffbf1f"),
}

-- alerts under the top buttons (Config.ui.alerts, owner 2026-11-16): a dark navy toast with a bright edge and an
-- icon chip in the alert's own colour (red = no, green = go, yellow = coins, blue = info)
Theme.alert = { back = hex("20264a"), backTop = hex("323a6e"), text = hex("ffffff") }
-- the server events and the Secret clock (Config.events, Config.secretSpawn): each event's own colour
Theme.events = { chill = hex("5fd0ff"), luck = hex("5dffb0"), coins = hex("ffc93c"), golden = hex("ffb21f"),
	secret = hex("ff4fd8"), night = hex("9b7bff") }
-- the Cold Power gain banner at the top (Config.ui.gainBanner): cyan to mint like the reference's box
Theme.gainBanner = { from = hex("36e0ff"), to = hex("3cf0a0"), rays = hex("ffffff") }

return Theme

