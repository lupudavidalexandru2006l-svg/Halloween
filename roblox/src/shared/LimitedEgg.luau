--!strict
-- LimitedEgg: the Frostlight Egg, the first limited Robux egg (owner 2026-11-22). Everything about it lives
-- here; EggService (server) rolls and grants, EggController (client) sells it and plays the hatch show.
-- Owner's calls: Robux only (vault Game Design Rules > Money, owner exception 2026-11-22), 6 pets, each pet
-- earns a share of your best pet's income (fixed when it hatches), its own "Limited" Index page that gives
-- no +10% bonus, a real "Leaves <date>" line (never a ticking countdown), the best pet also sold straight
-- at a hub stand. Pets you hatched stay forever, after the egg leaves too.

export type EggPet = { key: string, name: string, tier: string, pct: number, weight: number, hex: string, rig: string, size: string, glow: { string } }

local LimitedEgg = {
	id = "frostlight",
	name = "Frostlight Egg",
	short = "Frostlight",
	tagline = "Limited holiday egg",
	-- the egg leaves on this date (os.time, UTC). nil = no date yet: the egg is on sale and no date shows.
	-- Owner 2026-11-22: "do not add december 7, I'll tell you what date": leave nil until the owner gives one.
	endsAt = nil :: number?,
	-- the pets, worst to best. pct = income as a share of your best (non-limited) pet when it hatches.
	-- weight = odds in percent (they add up to 100).
	pets = {
		{ key = "frost_lynx", name = "Frost Lynx", tier = "Rare", pct = 0.8, weight = 45, hex = "dfe9f5", rig = "Quadruped", size = "M", glow = { "Crystal" } },
		{ key = "evergreen_stag", name = "Evergreen Stag", tier = "Rare", pct = 1.0, weight = 28, hex = "8a4b2a", rig = "Quadruped", size = "M", glow = { "Ornaments" } },
		{ key = "nutcracker_bear", name = "Nutcracker Bear", tier = "Epic", pct = 1.25, weight = 15, hex = "c8202f", rig = "Quadruped", size = "L", glow = {} },
		{ key = "aurora_wolf", name = "Aurora Wolf", tier = "Epic", pct = 1.5, weight = 8.5, hex = "3a4fb8", rig = "Quadruped", size = "M", glow = { "Mane", "Tail" } },
		{ key = "glacier_gryphon", name = "Glacier Gryphon", tier = "Legendary", pct = 2.0, weight = 3, hex = "8fd0ff", rig = "Quadruped", size = "L", glow = { "Wings", "Ruby" } },
		{ key = "starlight_dragon", name = "Starlight Dragon", tier = "Mythic", pct = 2.5, weight = 0.5, hex = "2b2f8f", rig = "Quadruped", size = "L", glow = { "Star", "Wings" } },
	} :: { EggPet },
	-- soft pity (Game Design Rules 4): every egg with no Legendary or better adds this many percent to the
	-- Legendary and Mythic odds (taken from the commonest pet), up to the caps; a Legendary+ resets it.
	-- The odds shown at the egg always include it.
	pity = { legendaryStep = 0.12, mythicStep = 0.02, legendaryCap = 9, mythicCap = 2.5 },
	-- Robux products: how many eggs, the price, and the developer product id (0 = not made yet; Studio
	-- then grants it for free so it can be tested). The bigger packs are a little cheaper per egg.
	-- Made 2026-11-22 with tools/rbx_create_egg_products.py, painted icons in icons/products/limited.
	packs = {
		{ id = "egg1", eggs = 1, robux = 59, productId = 3734729876 },
		{ id = "egg3", eggs = 3, robux = 159, productId = 3734729723 },
		{ id = "egg10", eggs = 10, robux = 499, productId = 3734729745 },
	},
	-- the hub stand: the best pet sold straight, no roll (owner screenshot 2026-11-22: "250% Of Best Pet! Only 499")
	direct = { key = "starlight_dragon", robux = 499, productId = 3734729769 },
	-- the Limited page in the Index: its own page, no Claim button, no +10%
	indexTitle = "Limited",
	-- a pet's income can never be less than this (a brand-new player with no pets yet)
	minIncome = 5,
}

function LimitedEgg.pet(key: string): EggPet?
	for _, p in LimitedEgg.pets do
		if p.key == key then
			return p
		end
	end
	return nil
end

function LimitedEgg.pack(id: string): any?
	for _, p in LimitedEgg.packs do
		if p.id == id then
			return p
		end
	end
	return nil
end

-- the egg is still on sale at time `now` (os.time / server time)
function LimitedEgg.onSale(now: number): boolean
	return LimitedEgg.endsAt == nil or now < (LimitedEgg.endsAt :: number)
end

-- "Leaves Dec 9" (UTC date), or nil while no date is set
function LimitedEgg.leavesText(): string?
	local t = LimitedEgg.endsAt
	if not t then
		return nil
	end
	local d = os.date("!*t", t)
	local months = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" }
	return `Leaves {months[d.month]} {d.day}`
end

-- the odds in percent for every pet with `dry` eggs opened since the last Legendary or better
function LimitedEgg.odds(dry: number): { number }
	local P = LimitedEgg.pity
	local addL = math.min(P.legendaryCap, dry * P.legendaryStep)
	local addM = math.min(P.mythicCap, dry * P.mythicStep)
	local out = {}
	for i, p in LimitedEgg.pets do
		local w = p.weight
		if p.tier == "Legendary" then
			w += addL
		elseif p.tier == "Mythic" then
			w += addM
		end
		out[i] = w
	end
	out[1] -= addL + addM -- taken from the commonest pet, so they still add up to 100
	return out
end

-- one roll: r in [0, 100). Returns the pet's index.
function LimitedEgg.pick(dry: number, r: number): number
	local odds = LimitedEgg.odds(dry)
	local acc = 0
	for i, w in odds do
		acc += w
		if r < acc then
			return i
		end
	end
	return #odds
end

return LimitedEgg
