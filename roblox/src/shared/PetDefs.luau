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
	-- desert 4 -> 6, volcano 5 -> 8). They are designs waiting for the owner's line-up approval: until
	-- their island is ready (Config.world.islands ready = true) inZone gives nothing, so they never spawn.
	-- Islands 3, 5, 7, 9 and 10 have roster cards only (vault: Games/Ice Ray for Pets/Pet Roster).
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
	-- Desert Dunes (zone 6): roster designed, no art yet
	pet("catcus", "Catcus", 6, "Common", "Quadruped", "S", "3f9a3a"),
	pet("fenny", "Fenny", 6, "Common", "Quadruped", "S", "f0742a"),
	pet("lumpkin", "Lumpkin", 6, "Uncommon", "Quadruped", "M", "6a3f22"),
	pet("scarabit", "Scarabit", 6, "Rare", "Custom", "S", "5a2a9a"),
	pet("sunfrill", "Sunfrill", 6, "Epic", "Quadruped", "M", "c41f2a", { "Frill" }),
	pet("dunehorn_ram", "Dunehorn Ram", 6, "Legendary", "Quadruped", "L", "d64f86"),
	pet("solaris_sphinx", "Solaris Sphinx", 6, "Mythic", "Custom", "M", "e3a81c", { "Wings", "SunGem", "TailTip" }),
	pet("mirage_manta", "Mirage Manta", 6, "Secret", "Swimmer", "M", "14837f", { "WingDots" }),
	-- Volcano Slopes (zone 8): roster designed, no art yet
	pet("emberpup", "Emberpup", 8, "Common", "Quadruped", "S", "f37a1b"),
	pet("magmallow", "Magmallow", 8, "Common", "Blob", "S", "c4204f"),
	pet("obby", "Obby", 8, "Uncommon", "Quadruped", "M", "26232e"),
	pet("sizzlemander", "Sizzlemander", 8, "Rare", "Quadruped", "S", "8ccf2a"),
	pet("flarechick", "Flarechick", 8, "Epic", "Bird", "S", "e0207e", { "Crest" }),
	pet("geodillo", "Geodillo", 8, "Legendary", "Quadruped", "L", "5b2aa6", { "Geodes", "Crown" }),
	pet("pyrokoi", "Pyrokoi", 8, "Mythic", "Swimmer", "M", "e8a21c", { "Fins", "Tail" }),
	pet("lavalamp_jelly", "Lavalamp Jelly", 8, "Secret", "Blob", "M", "2a2f8f", { "Blobs" }),
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
