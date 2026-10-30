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
		icon = "",
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
	-- Sunny Beach (zone 3): concepts made (4 full size, 4 previews)
	pet("puffsy", "Puffsy", 3, "Common", "Swimmer", "S", "f07a1e"),
	pet("starbit", "Starbit", 3, "Common", "Blob", "S", "e0157a"),
	pet("flopseal", "Flopseal", 3, "Uncommon", "Swimmer", "M", "1f3fd6"),
	pet("pearlsnail", "Pearlsnail", 3, "Rare", "Blob", "S", "f3cf1c"),
	pet("glowfin", "Glowfin", 3, "Epic", "Swimmer", "M", "1d7a63", { "Pearl" }),
	pet("reefback_turtle", "Reefback Turtle", 3, "Legendary", "Swimmer", "L", "e8413a"),
	pet("prismapus", "Prismapus", 3, "Mythic", "Custom", "M", "7a2fb0", { "TentacleTips", "Gem" }),
	pet("beacon_orca", "Beacon Orca", 3, "Secret", "Swimmer", "M", "1a1a1a", { "Lamp" }),
	-- Desert Dunes (zone 4): roster designed, no art yet
	pet("catcus", "Catcus", 4, "Common", "Quadruped", "S", "3f9a3a"),
	pet("fenny", "Fenny", 4, "Common", "Quadruped", "S", "f0742a"),
	pet("lumpkin", "Lumpkin", 4, "Uncommon", "Quadruped", "M", "6a3f22"),
	pet("scarabit", "Scarabit", 4, "Rare", "Custom", "S", "5a2a9a"),
	pet("sunfrill", "Sunfrill", 4, "Epic", "Quadruped", "M", "c41f2a", { "Frill" }),
	pet("dunehorn_ram", "Dunehorn Ram", 4, "Legendary", "Quadruped", "L", "d64f86"),
	pet("solaris_sphinx", "Solaris Sphinx", 4, "Mythic", "Custom", "M", "e3a81c", { "Wings", "SunGem", "TailTip" }),
	pet("mirage_manta", "Mirage Manta", 4, "Secret", "Swimmer", "M", "14837f", { "WingDots" }),
	-- Volcano (zone 5): roster designed, no art yet
	pet("emberpup", "Emberpup", 5, "Common", "Quadruped", "S", "f37a1b"),
	pet("magmallow", "Magmallow", 5, "Common", "Blob", "S", "c4204f"),
	pet("obby", "Obby", 5, "Uncommon", "Quadruped", "M", "26232e"),
	pet("sizzlemander", "Sizzlemander", 5, "Rare", "Quadruped", "S", "8ccf2a"),
	pet("flarechick", "Flarechick", 5, "Epic", "Bird", "S", "e0207e", { "Crest" }),
	pet("geodillo", "Geodillo", 5, "Legendary", "Quadruped", "L", "5b2aa6", { "Geodes", "Crown" }),
	pet("pyrokoi", "Pyrokoi", 5, "Mythic", "Swimmer", "M", "e8a21c", { "Fins", "Tail" }),
	pet("lavalamp_jelly", "Lavalamp Jelly", 5, "Secret", "Blob", "M", "2a2f8f", { "Blobs" }),
}

local byKey: { [string]: PetDef } = {}
for _, p in PetDefs do
	byKey[p.key] = p
end

local M = {
	list = PetDefs,
	byKey = byKey,
	sizeHeight = { S = 2.2, M = 3, L = 4 } :: { [string]: number },
	cubeSize = { S = 3.0, M = 3.8, L = 4.8 } :: { [string]: number },
}

function M.get(key: string): PetDef?
	return byKey[key]
end

function M.inZone(zone: number, tier: string?): { PetDef }
	local out = {}
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
