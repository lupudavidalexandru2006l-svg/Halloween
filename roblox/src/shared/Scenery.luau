--!strict
-- Scenery: the trees (shade) and sun patches, made with the prototype's own random generator
-- (mulberry32, seed in Config.scenery), per island section of the tunnel; the trees keep to the side
-- bands so the middle stays open (World Rules 9). WorldService turns them into
-- shade/sun areas; MapArt draws the trees on the same spots.

local Config = require(script.Parent.Config)

export type Tree = { x: number, z: number, r: number, kind: string }
export type Sun = { x: number, z: number, r: number }
export type List = { trees: { Tree }, sun: { Sun }, lava: { Sun } } -- lava pools (hot islands, Round 4 phase 6)

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

-- each open island's trees and sun patches, spread over its own section of the tunnel. The order of
-- the random calls is fixed (island by island, trees then sun), so the map is the same every time,
-- and adding an island at the end never moves the ones before it.
function Scenery.get(): List
	if cached then
		return cached
	end
	local S, W = Config.scenery, Config.world
	local r = Scenery.rng(S.seed)
	local trees: { Tree } = {}
	local sun: { Sun } = {}
	local lava: { Sun } = {}
	local half = W.tunnel.width / 2 - S.wallMargin
	local open = 0
	for _, isl in W.islands do
		if not isl.open then
			continue
		end
		open += 1
		local zone = W.zones[open]
		local z0, z1 = zone.zMin + S.startClear, zone.zMax - S.gateClear
		local s = isl.sun
		if s then
			for _ = 1, s.count do
				local x = -half + 4 + r() * (half * 2 - 8)
				local z = z0 + 10 + r() * (z1 - z0 - 10)
				table.insert(sun, { x = x, z = z, r = s.r[1] + r() * (s.r[2] - s.r[1]) })
			end
		end
		-- lava pools beside the path (never on it: the path stays a safe way through), clear of each other
		local first = #lava + 1
		local l = isl.lava
		if l then
			for _ = 1, l.count do
				local rad = l.r[1] + r() * (l.r[2] - l.r[1])
				for _ = 1, 8 do
					local side = if r() < 0.5 then -1 else 1
					local x = side * (S.pathHalfWidth + 2 + rad + r() * math.max(0, half - S.pathHalfWidth - 4 - rad * 2))
					local z = z0 + 10 + r() * (z1 - z0 - 10)
					local ok = true
					for _, p in lava do
						if (p.x - x) ^ 2 + (p.z - z) ^ 2 < (p.r + rad + 3) ^ 2 then
							ok = false
						end
					end
					if ok then
						table.insert(lava, { x = x, z = z, r = rad })
						break
					end
				end
			end
		end
		-- shade trees in the side bands only (S.treeBand to the walls): the middle, where pets are easiest to
		-- spot, stays open (World Rules 9). A few tries each for a spot whose shade stays off this island's lava.
		local t = isl.trees
		if t then
			for _ = 1, t.count do
				local rad = t.r[1] + r() * (t.r[2] - t.r[1])
				for _ = 1, 6 do
					local side = if r() < 0.5 then -1 else 1
					local outer = math.max(S.treeBand, half - rad * 0.5)
					local x = side * (S.treeBand + r() * (outer - S.treeBand))
					local z = z0 + r() * (z1 - z0)
					local ok = true
					for i = first, #lava do
						local p = lava[i]
						if (p.x - x) ^ 2 + (p.z - z) ^ 2 < (p.r + rad) ^ 2 then
							ok = false
						end
					end
					if ok then
						table.insert(trees, { x = x, z = z, r = rad, kind = t.kind })
						break
					end
				end
			end
		end
	end
	cached = { trees = trees, sun = sun, lava = lava }
	return cached :: List
end

return Scenery
