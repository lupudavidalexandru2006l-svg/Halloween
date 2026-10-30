--!strict
-- IndexService: owns the Index pages. One page per zone: its 7 regular pets (Common to Mythic).
-- The Secret is a bonus slot: it shows on the page but a page is complete without it.
-- Each complete page = +10% coins forever (Config.index.pageBonus); PenService asks for the multiplier.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local PetDefs = require(ReplicatedStorage.Shared.PetDefs)
local Remotes = require(script.Parent.Remotes)

export type Page = { zone: number, found: number, total: number, complete: boolean, secretFound: boolean }

local IndexService = {}

local function isRegular(def: PetDefs.PetDef): boolean
	return def.tier ~= "Secret"
end

-- only zones that are in the world count (zones 3-5 have pets designed but no map yet)
function IndexService.pages(found: { [string]: boolean }): { Page }
	local out: { Page } = {}
	for _, z in Config.world.zones do
		local page: Page = { zone = z.id, found = 0, total = 0, complete = false, secretFound = false }
		for _, def in PetDefs.inZone(z.id) do
			if isRegular(def) then
				page.total += 1
				if found[def.key] then
					page.found += 1
				end
			elseif found[def.key] then
				page.secretFound = true
			end
		end
		page.complete = page.total > 0 and page.found == page.total
		table.insert(out, page)
	end
	return out
end

function IndexService.completedPages(found: { [string]: boolean }): number
	local n = 0
	for _, p in IndexService.pages(found) do
		if p.complete then
			n += 1
		end
	end
	return n
end

function IndexService.multiplier(found: { [string]: boolean }): number
	return 1 + Config.index.pageBonus * IndexService.completedPages(found)
end

-- PenService calls this after a new pet is marked found; tells the player when it finished a page
function IndexService.onFound(player: Player, key: string, found: { [string]: boolean })
	local def = PetDefs.get(key)
	if not def then
		return
	end
	for _, p in IndexService.pages(found) do
		if p.zone == def.zone and p.complete and isRegular(def) then
			Remotes.fire(player, "Notify", "pageDone", { zone = p.zone, bonus = Config.index.pageBonus })
		end
	end
end

function IndexService.Init() end
function IndexService.Start() end

return IndexService
