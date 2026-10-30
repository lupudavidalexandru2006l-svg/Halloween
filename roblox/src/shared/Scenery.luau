--!strict
-- Scenery: the trees (shade) and sun patches, made with the prototype's own random generator
-- (mulberry32, seed in Config.scenery) so they land exactly where they are in the artifact.
-- WorldService turns them into shade/sun areas; MapArt draws the trees on the same spots.

local Config = require(script.Parent.Config)

export type Tree = { x: number, z: number, r: number, kind: string }
export type Sun = { x: number, z: number, r: number }
export type List = { trees: { Tree }, sun: { Sun } }

local Scenery = {}

local TWO32 = 4294967296

-- 32-bit multiply (Math.imul): split into 16-bit halves so no precision is lost
local function imul(a: number, b: number): number
	local ah, al = bit32.rshift(a, 16), bit32.band(a, 0xffff)
	local bh, bl = bit32.rshift(b, 16), bit32.band(b, 0xffff)
	local mid = bit32.band(ah * bl + al * bh, 0xffff)
	return (al * bl + mid * 65536) % TWO32
end

-- the same numbers as the prototype's mulberry32(seed)
function Scenery.rng(seed: number): () -> number
	local a = seed % TWO32
	return function(): number
		a = (a + 0x6d2b79f5) % TWO32
		local t = imul(bit32.bxor(a, bit32.rshift(a, 15)), bit32.bor(1, a))
		t = bit32.bxor((t + imul(bit32.bxor(t, bit32.rshift(t, 7)), bit32.bor(61, t))) % TWO32, t)
		return bit32.bxor(t, bit32.rshift(t, 14)) / TWO32
	end
end

local cached: List? = nil

-- prototype config.js buildScenery(), step for step (the order of the random calls matters)
function Scenery.get(): List
	if cached then
		return cached
	end
	local S = Config.scenery
	local r = Scenery.rng(S.seed)
	local trees: { Tree } = {}
	local sun: { Sun } = {}
	local function clear(x: number, z: number): boolean
		return math.abs(x) < S.pathHalfWidth or (z > S.riverClear[1] and z < S.riverClear[2])
	end
	for _, band in S.bands do
		for _ = 1, band.trees do
			local x = band.x[1] + r() * (band.x[2] - band.x[1])
			local z = band.z[1] + r() * (band.z[2] - band.z[1])
			if not clear(x, z) then
				table.insert(trees, { x = x, z = z, r = band.r[1] + r() * (band.r[2] - band.r[1]), kind = band.kind })
			end
		end
		for _ = 1, band.sun do
			local x = band.sunX[1] + r() * (band.sunX[2] - band.sunX[1])
			local z = band.sunZ[1] + r() * (band.sunZ[2] - band.sunZ[1])
			table.insert(sun, { x = x, z = z, r = band.sunR[1] + r() * (band.sunR[2] - band.sunR[1]) })
		end
	end
	cached = { trees = trees, sun = sun }
	return cached :: List
end

return Scenery
