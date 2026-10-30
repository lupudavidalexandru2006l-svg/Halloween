--!strict
-- Theme: every colour in the game. No one-off colours anywhere else (UI Rules, World Rules).

local Theme = {
	ink = Color3.fromHex("1b1433"),
	go = Color3.fromHex("3ccf6e"),
	no = Color3.fromHex("ff5a5f"),
	coin = Color3.fromHex("ffc93c"),
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

	font = Enum.Font.FredokaOne,
	lipDarken = 0.35, -- the lip under every block face is its colour this much darker
	temp = { cold = Color3.fromHex("3aa8ff"), cool = Color3.fromHex("2fc6b5"), warm = Color3.fromHex("ff9f1c"), hot = Color3.fromHex("ff5a5f"), chill = Color3.fromHex("bfe9ff") } :: { [string]: Color3 },
	shade = Color3.fromRGB(0, 0, 0), -- the dim behind a popup
	shadeTransparency = 0.55,
}

return Theme
