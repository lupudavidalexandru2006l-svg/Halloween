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
	panel = Color3.fromHex("fff8ec"),
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
	board = Color3.fromHex("2b1f5c"),

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

	-- effects and guides (prototype client.js)
	fx = {
		arrow = Color3.fromHex("3ccf6e"), beacon = Color3.fromHex("7dffb0"),
		beamCore = Color3.new(1, 1, 1), beamGlow = Color3.fromHex("7fe3ff"),
		gunBody = Color3.fromHex("e9f6ff"), gunTip = Color3.fromHex("7fe3ff"),
		star = Color3.fromHex("ffd34a"), shadow = Color3.fromHex("1b1433"), frost = Color3.fromHex("dff6ff"),
		giftBody = Color3.fromHex("ff5a8a"), giftLid = Color3.fromHex("ff7ca3"), giftRibbon = Color3.fromHex("ffd34a"),
		superFrozen = Color3.fromHex("5f8dff"),
	},

	font = Enum.Font.FredokaOne,
	lipDarken = 0.35, -- the lip under every block face is its colour this much darker
	temp = { cold = Color3.fromHex("6fd0ff"), cool = Color3.fromHex("5fd6b4"), warm = Color3.fromHex("ffb347"), hot = Color3.fromHex("ff6b5a"), chill = Color3.fromHex("d9f4ff") } :: { [string]: Color3 },
	shade = Color3.fromRGB(0, 0, 0), -- the dim behind a popup
	shadeTransparency = 0.55,
}

return Theme
