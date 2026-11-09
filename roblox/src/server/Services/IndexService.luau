--!strict
-- IndexService: owns the Index pages. One page per zone: all its pets, the Secret included (owner
-- 2026-11-09: "include the secrets"). A full page shows a pulsing Claim button; claiming it gives
-- +10% coins forever (Config.index.pageBonus) and the page's badge (Config.index.badges). PenService
-- asks for the multiplier, which counts claimed pages only. Old saves had full pages counted without
-- the Secret: DataService marks those claimed on load, so nobody loses a bonus they had.

local BadgeService = game:GetService("BadgeService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local PetDefs = require(ReplicatedStorage.Shared.PetDefs)
local Remotes = require(script.Parent.Remotes)
local DataService = require(script.Parent.DataService)

export type Page = { zone: number, found: number, total: number, complete: boolean, secretFound: boolean, claimed: boolean }

local IndexService = {}
local claimAt: { [Player]: number } = {}

-- only zones that are in the world count (an island behind a "Coming soon" gate has no page yet)
function IndexService.pages(found: { [string]: boolean }, claimed: { [string]: boolean }?): { Page }
	local out: { Page } = {}
	for _, z in Config.world.zones do
		if not z.ready then
			continue
		end
		local page: Page = { zone = z.id, found = 0, total = 0, complete = false, secretFound = false,
			claimed = claimed ~= nil and claimed[tostring(z.id)] == true }
		for _, def in PetDefs.inZone(z.id) do
			page.total += 1
			if found[def.key] then
				page.found += 1
				if def.tier == "Secret" then
					page.secretFound = true
				end
			end
		end
		page.complete = page.total > 0 and page.found == page.total
		table.insert(out, page)
	end
	return out
end

-- +10% for every page claimed
function IndexService.multiplier(claimed: { [string]: boolean }): number
	local n = 0
	for _, z in Config.world.zones do
		if claimed[tostring(z.id)] then
			n += 1
		end
	end
	return 1 + Config.index.pageBonus * n
end

-- PenService calls this after a new pet is marked found; tells the player when it filled a page
function IndexService.onFound(player: Player, key: string, found: { [string]: boolean }, claimed: { [string]: boolean })
	local def = PetDefs.get(key)
	if not def then
		return
	end
	for _, p in IndexService.pages(found, claimed) do
		if p.zone == def.zone and p.complete and not p.claimed then
			Remotes.fire(player, "Notify", "pageDone", { zone = p.zone, bonus = Config.index.pageBonus })
		end
	end
end

-- the client asks to claim a full page: checked here (a real, full, unclaimed page), saved, then the badge
local function claim(player: Player, zone: any)
	if typeof(zone) ~= "number" or zone ~= zone or zone % 1 ~= 0 then
		return
	end
	local now = os.clock()
	if now - (claimAt[player] or -math.huge) < Config.index.claimCooldown then
		return
	end
	claimAt[player] = now
	local ok = false
	DataService.mutate(player, function(d)
		for _, p in IndexService.pages(d.found, d.indexClaimed) do
			if p.zone == zone and p.complete and not p.claimed then
				d.indexClaimed[tostring(zone)] = true
				ok = true
			end
		end
	end)
	if not ok then
		return
	end
	DataService.saveNow(player)
	Remotes.fire(player, "Notify", "pageClaimed", { zone = zone, bonus = Config.index.pageBonus })
	local badge = Config.index.badges[zone]
	if badge and badge > 0 then
		task.spawn(function()
			local okB, err = pcall(function()
				if not BadgeService:UserHasBadgeAsync(player.UserId, badge) then
					BadgeService:AwardBadge(player.UserId, badge)
				end
			end)
			if not okB then
				warn(`[IndexService] badge {badge} for {player.UserId}: {err}`)
			end
		end)
	end
end

function IndexService.Init() end
function IndexService.Start()
	Remotes.on("ClaimPage", claim)
	game:GetService("Players").PlayerRemoving:Connect(function(p)
		claimAt[p] = nil
	end)
end

return IndexService
