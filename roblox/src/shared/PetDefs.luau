--!strict
-- PetDefs: one entry per pet (Pet Rules 11). Nothing about a pet is hard-coded anywhere else.
-- model = name of the Model in ReplicatedStorage/PetModels (uploaded mesh, rigged by family).
-- Until a model exists the game shows a stand-in in the pet's colour with its real name and size.
-- icon / anims / sounds are owner items (uploads); empty strings mean "not uploaded yet".

local Config = require(script.Parent.Config)

export type PetDef = {
	key: string,
	name: string,
	zone: number,
	tier: "Common" | "Uncommon" | "Rare" | "Epic" | "Legendary" | "Mythic" | "Secret",
	rig: "Quadruped" | "Biped" | "Bird" | "Blob" | "Swimmer" | "Custom",
	size: "S" | "M" | "L",
	model: string,
	icon: string,
	color: Color3,
	anims: { [string]: string },
	sounds: { happy: string, signature: string },
	income: number,
	glowParts: { string }, -- parts made Neon after upload (crystals, gems, lanterns)
}

local function pet(key: string, name: string, zone: number, tier: any, rig: any, size: any, hex: string, glow: { string }?): PetDef
	local t = Config.tier(tier)
	return {
		key = key,
		name = name,
		zone = zone,
		tier = tier,
		rig = rig,
		size = size,
		model = key,
		icon = Config.images.pets[key] or "",
		color = Color3.fromHex(hex),
		anims = { idle = "", move = "", happy = "", signature = "", yawn = "", jump = "", dance = "", sneeze = "", asleep = "", dazed = "" },
		sounds = { happy = "", signature = "" },
		income = t.income * Config.incomeZoneMultiplier ^ (zone - 1),
		glowParts = glow or {},
	}
end

local PetDefs: { PetDef } = {
	-- Snowy Meadow (zone 1): approved concepts; 3D: Frostfox, Snowbun done (Rodin V2, trimmed under 8,000 triangles)
	pet("snowbun", "Snowbun", 1, "Common", "Quadruped", "S", "e9507f"),
	pet("waddles", "Waddles", 1, "Common", "Biped", "S", "1d2756"),
	pet("mittenkit", "Mittenkit", 1, "Uncommon", "Quadruped", "S", "f08a22"),
	pet("pupcicle", "Pupcicle", 1, "Rare", "Quadruped", "M", "f2d81c"),
	pet("frostfox", "Frostfox", 1, "Epic", "Quadruped", "M", "1f7f95", { "TailCrystal", "ForeheadGem" }),
	pet("blizzard_yeti", "Blizzard Yeti", 1, "Legendary", "Biped", "L", "8d6ad6", { "ShoulderPlates", "IceCrown" }),
	pet("aurora_owl", "Aurora Owl", 1, "Mythic", "Bird", "M", "178a63", { "WingL", "WingR", "ChestEmblem" }),
	pet("snowglobe_drake", "Snowglobe Drake", 1, "Secret", "Custom", "M", "c8202f", { "SnowGlobe" }),
	-- Pine Forest (zone 2): concepts made, waiting for the owner's line-up review
	pet("conehog", "Conehog", 2, "Common", "Quadruped", "S", "8a4b2a"),
	pet("hopsprout", "Hopsprout", 2, "Common", "Quadruped", "S", "e7b528"),
	pet("capmouse", "Capmouse", 2, "Uncommon", "Quadruped", "S", "6b2f8f"),
	pet("mossfawn", "Mossfawn", 2, "Rare", "Quadruped", "M", "2f6a30"),
	pet("lanternbug", "Lanternbug", 2, "Epic", "Bird", "S", "36318c", { "Lantern" }),
	pet("mapleguard_bear", "Mapleguard Bear", 2, "Legendary", "Quadruped", "L", "b51f2c"),
	pet("bloomhorn_stag", "Bloomhorn Stag", 2, "Mythic", "Custom", "M", "d6286f", { "Antlers", "Hooves", "LeafEmblem" }),
	pet("glowshroom_mammoth", "Glowshroom Mammoth", 2, "Secret", "Custom", "M", "1f5a6a", { "Mushrooms" }),
	-- Mushroom Grove (zone 3): roster and concepts approved (2026-11-05); 3D + rig done for Toddle,
	-- Puffball, Trufflet (2026-11-06), Glimmermoth, Shimmerfrog, Capcrown Badger, Sporewing Drake (2026-11-09),
	-- Myco Golem (2026-11-10): all 8 grove pets are 3D
	pet("toddle", "Toddle", 3, "Common", "Quadruped", "S", "e8641c"),
	pet("puffball", "Puffball", 3, "Common", "Blob", "S", "c2185b"),
	pet("trufflet", "Trufflet", 3, "Uncommon", "Quadruped", "S", "5c3a26"),
	pet("glimmermoth", "Glimmermoth", 3, "Rare", "Bird", "S", "33307a"),
	pet("shimmerfrog", "Shimmerfrog", 3, "Epic", "Quadruped", "M", "117a76", { "Gem" }),
	pet("capcrown_badger", "Capcrown Badger", 3, "Legendary", "Quadruped", "L", "6b2763", { "Crown" }),
	pet("sporewing_drake", "Sporewing Drake", 3, "Mythic", "Custom", "M", "b3152f", { "WingGills" }),
	pet("myco_golem", "Myco Golem", 3, "Secret", "Custom", "M", "0f8fa3", { "Mushrooms" }),
	-- Round 4 phase 6 moved the next three rosters to their places on the 10-island ladder (beach 3 -> 4,
	-- desert 4 -> 6, volcano 5 -> 8). Owner 2026-11-10: "implement every pet in the game" for now, so every
	-- island is ready and all 80 pets spawn. A pet with no model shows its painting, or with no painting a
	-- ball in its colour with its name. Islands 5, 7, 9 and 10 come from the roster cards (vault Pet Roster).
	-- Sunny Beach (zone 4): line-up approved 2026-11-10; 3D + rig done for Puffsy, Starbit, Flopseal (island still
	-- closed: Pearlsnail's 3D and full concepts for the other four come first)
	pet("puffsy", "Puffsy", 4, "Common", "Swimmer", "S", "f07a1e"),
	pet("starbit", "Starbit", 4, "Common", "Blob", "S", "e0157a"),
	pet("flopseal", "Flopseal", 4, "Uncommon", "Swimmer", "M", "1f3fd6"),
	pet("pearlsnail", "Pearlsnail", 4, "Rare", "Blob", "S", "f3cf1c"),
	pet("glowfin", "Glowfin", 4, "Epic", "Swimmer", "M", "1d7a63", { "Pearl" }),
	pet("reefback_turtle", "Reefback Turtle", 4, "Legendary", "Swimmer", "L", "e8413a"),
	pet("prismapus", "Prismapus", 4, "Mythic", "Custom", "M", "7a2fb0", { "TentacleTips", "Gem" }),
	pet("beacon_orca", "Beacon Orca", 4, "Secret", "Swimmer", "M", "1a1a1a", { "Lamp" }),
	-- Jungle Falls (zone 5): roster card only (vault Pet Roster), in the game as stand-ins (owner 2026-11-10)
	pet("bananabo", "Bananabo", 5, "Common", "Biped", "S", "e0a810"),
	pet("splashfrog", "Splashfrog", 5, "Common", "Quadruped", "S", "1f4fe0"),
	pet("tucanny", "Tucanny", 5, "Uncommon", "Bird", "S", "1c1c22"),
	pet("chamelo", "Chamelo", 5, "Rare", "Quadruped", "S", "c2187a"),
	pet("glowpanther", "Glowpanther", 5, "Epic", "Quadruped", "M", "5b21a8", { "Spots" }),
	pet("fallcrown_gorilla", "Fallcrown Gorilla", 5, "Legendary", "Biped", "L", "137a7a", { "Crown" }),
	pet("rainbow_quetzal", "Rainbow Quetzal", 5, "Mythic", "Bird", "M", "0f8a4a", { "TailTips" }),
	pet("vinewyrm", "Vinewyrm", 5, "Secret", "Custom", "M", "c21d4a", { "FlowerCrown" }),
	-- Desert Dunes (zone 6): roster designed, no art yet
	pet("catcus", "Catcus", 6, "Common", "Quadruped", "S", "3f9a3a"),
	pet("fenny", "Fenny", 6, "Common", "Quadruped", "S", "f0742a"),
	pet("lumpkin", "Lumpkin", 6, "Uncommon", "Quadruped", "M", "6a3f22"),
	pet("scarabit", "Scarabit", 6, "Rare", "Custom", "S", "5a2a9a"),
	pet("sunfrill", "Sunfrill", 6, "Epic", "Quadruped", "M", "c41f2a", { "Frill" }),
	pet("dunehorn_ram", "Dunehorn Ram", 6, "Legendary", "Quadruped", "L", "d64f86"),
	pet("solaris_sphinx", "Solaris Sphinx", 6, "Mythic", "Custom", "M", "e3a81c", { "Wings", "SunGem", "TailTip" }),
	pet("mirage_manta", "Mirage Manta", 6, "Secret", "Swimmer", "M", "14837f", { "WingDots" }),
	-- Canyon Mesa (zone 7): roster card only, in the game as stand-ins (owner 2026-11-10)
	pet("yipyap", "Yipyap", 7, "Common", "Quadruped", "S", "b8481a"),
	pet("hopalope", "Hopalope", 7, "Common", "Quadruped", "S", "2a8fd6"),
	pet("gilly", "Gilly", 7, "Uncommon", "Quadruped", "S", "d63f86"),
	pet("burrowl", "Burrowl", 7, "Rare", "Bird", "S", "c99a12"),
	pet("sparkhorn_goat", "Sparkhorn Goat", 7, "Epic", "Quadruped", "M", "6a2fb0", { "Horns" }),
	pet("mesa_tortoise", "Mesa Tortoise", 7, "Legendary", "Quadruped", "L", "b5412a", { "Crown" }),
	pet("sandstorm_lynx", "Sandstorm Lynx", 7, "Mythic", "Custom", "M", "139a8f", { "DustTail" }),
	pet("echo_whale", "Echo Whale", 7, "Secret", "Swimmer", "M", "1b2a6b", { "Stripes" }),
	-- Volcano Slopes (zone 8): roster designed, no art yet
	pet("emberpup", "Emberpup", 8, "Common", "Quadruped", "S", "f37a1b"),
	pet("magmallow", "Magmallow", 8, "Common", "Blob", "S", "c4204f"),
	pet("obby", "Obby", 8, "Uncommon", "Quadruped", "M", "26232e"),
	pet("sizzlemander", "Sizzlemander", 8, "Rare", "Quadruped", "S", "8ccf2a"),
	pet("flarechick", "Flarechick", 8, "Epic", "Bird", "S", "e0207e", { "Crest" }),
	pet("geodillo", "Geodillo", 8, "Legendary", "Quadruped", "L", "5b2aa6", { "Geodes", "Crown" }),
	pet("pyrokoi", "Pyrokoi", 8, "Mythic", "Swimmer", "M", "e8a21c", { "Fins", "Tail" }),
	pet("lavalamp_jelly", "Lavalamp Jelly", 8, "Secret", "Blob", "M", "2a2f8f", { "Blobs" }),
	-- Lava Lake (zone 9): roster card only, in the game as stand-ins (owner 2026-11-10)
	pet("bubblava", "Bubblava", 9, "Common", "Blob", "S", "f06a12"),
	pet("crustacrab", "Crustacrab", 9, "Common", "Custom", "S", "5a2a9a"),
	pet("paddleduck", "Paddleduck", 9, "Uncommon", "Bird", "S", "f2c41a"),
	pet("basalt_beaver", "Basalt Beaver", 9, "Rare", "Quadruped", "M", "6b3e1f"),
	pet("ember_eel", "Ember Eel", 9, "Epic", "Swimmer", "M", "c41a7a", { "Stripe" }),
	pet("caldera_hippo", "Caldera Hippo", 9, "Legendary", "Quadruped", "L", "167a7a", { "Crown" }),
	pet("obsidian_swan", "Obsidian Swan", 9, "Mythic", "Bird", "M", "5a1fa0", { "FlameTrail" }),
	pet("lakeheart_serpent", "Lakeheart Serpent", 9, "Secret", "Custom", "M", "b0132a", { "Core" }),
	-- Magma Core (zone 10): roster card only, in the game as stand-ins (owner 2026-11-10)
	pet("coreling", "Coreling", 10, "Common", "Blob", "S", "e8661a", { "Core" }),
	pet("sparkmole", "Sparkmole", 10, "Common", "Quadruped", "S", "1d2a6b"),
	pet("ironhorn_beetle", "Ironhorn Beetle", 10, "Uncommon", "Custom", "S", "1f7a3a"),
	pet("pyrolamb", "Pyrolamb", 10, "Rare", "Quadruped", "M", "e0508f"),
	pet("thermowl", "Thermowl", 10, "Epic", "Bird", "M", "1f4fd0", { "ChestGem" }),
	pet("forge_bear", "Forge Bear", 10, "Legendary", "Quadruped", "L", "b81f24", { "Plates" }),
	pet("coreflare_drake", "Coreflare Drake", 10, "Mythic", "Custom", "M", "d9a316", { "Wings" }),
	pet("planetcore_turtle", "Planetcore Turtle", 10, "Secret", "Custom", "M", "1f3fb0", { "Planet" }),
}

local byKey: { [string]: PetDef } = {}
for _, p in PetDefs do
	byKey[p.key] = p
end

local M = {
	list = PetDefs,
	byKey = byKey,
	sizeHeight = { S = 2.2 * Config.petScale, M = 3 * Config.petScale, L = 4 * Config.petScale } :: { [string]: number },
	cubeSize = { S = 3.0, M = 3.8, L = 4.8 } :: { [string]: number },
}

function M.get(key: string): PetDef?
	return byKey[key]
end

-- the pets of a zone that can be met in the game: nothing for an island whose pets aren't approved
-- and finished yet (it waits behind a "Coming soon" gate, never with placeholder pets)
function M.inZone(zone: number, tier: string?): { PetDef }
	local out = {}
	local z = Config.zone(zone)
	if not z or not z.ready then
		return out
	end
	for _, p in PetDefs do
		if p.zone == zone and (tier == nil or p.tier == tier) then
			table.insert(out, p)
		end
	end
	return out
end

function M.income(def: PetDef, pose: string, mutation: string?): number
	local p = Config.poses[pose]
	local m = if mutation then Config.mutations[mutation] else nil
	return def.income * (if p then p.bonus else 1) * (if m then m.bonus else 1)
end

return M
