--!strict
-- SellService (Round 4 phase 5): owns selling pets at the Sell Booth. The client names the pets (their
-- ids) and whether the player said yes to the "Sure?" step; everything else is decided here: standing
-- at the booth (the server's own position), each pet's value (Config.sellValue of its own income), the
-- Epic-and-up confirm, and the payment. The pets leave the pan / Storage and the coins arrive in the
-- same DataService.mutate (PenService.removePets), so a pet can't be sold twice: a second press finds
-- it gone. The change is written at once, and leaving mid-sale keeps whichever side the save landed on:
-- the pets, or their coins, never neither.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local PetDefs = require(ReplicatedStorage.Shared.PetDefs)
local Remotes = require(script.Parent.Remotes)
local DataService = require(script.Parent.DataService)
local PlayerTracker = require(script.Parent.PlayerTracker)
local PenService = require(script.Parent.PenService)

local SellService = {}
local S = Config.sell
local lastSale: { [Player]: number } = {}

local function boothPos(): Vector3?
	for _, b in Config.world.booths do
		if b.id == "sell" then
			return b.pos
		end
	end
	return nil
end

local function atBooth(player: Player): boolean
	local p, b = PlayerTracker.position(player), boothPos()
	return p ~= nil and b ~= nil and (Vector3.new(p.X, 0, p.Z) - Vector3.new(b.X, 0, b.Z)).Magnitude <= S.boothRange
end

-- what one pet sells for (nil for a pet that no longer exists in PetDefs). A tester's money multiplier
-- counts on sales too (Round 4 prompt 1); SellPopup works it out the same way, per pet.
function SellService.value(p: DataService.PetEntry, mult: number): number?
	local def = PetDefs.get(p.key)
	return if def then Config.sellValue(PetDefs.income(def, p.pose, p.mut), mult) else nil
end

local function sell(player: Player, ids: any, confirmed: any)
	if typeof(ids) ~= "table" or #ids < 1 or #ids > S.maxPerSale or (confirmed ~= nil and typeof(confirmed) ~= "boolean") then
		return
	end
	local want: { [string]: boolean } = {}
	for _, id in ids do
		if not Remotes.isId(id, 12) then
			return
		end
		want[id] = true
	end
	local d = DataService.get(player)
	if not d or not atBooth(player) then
		return
	end
	local now = os.clock()
	if now - (lastSale[player] or -math.huge) < S.cooldown then
		return -- spam: dropped quietly (and the pets would be gone anyway)
	end
	lastSale[player] = now
	local coins, sold, needsYes = 0, {}, false
	DataService.mutate(player, function(x)
		-- decided inside the change: only pets still here count, and Epic+ needs the player's yes
		local here: { [string]: boolean } = {}
		local total = 0
		for _, p in x.pets do
			if want[p.id] and not p.thawM then -- a pet in a Thaw Machine can't be sold until it's out
				local def = PetDefs.get(p.key)
				local v = SellService.value(p, x.tester.mult)
				if def and v then
					if Config.tier(def.tier).rank >= S.confirmFromRank and confirmed ~= true then
						needsYes = true
						return
					end
					here[p.id] = true
					total += v
				end
			end
		end
		if next(here) == nil then
			return
		end
		for _, p in PenService.removePets(x, here) do
			table.insert(sold, p.key)
		end
		coins = total
		PenService.addCoins(x, total)
	end)
	if needsYes then
		Remotes.notYet(player, "Say yes first", "sell")
		return
	end
	if #sold == 0 then
		return
	end
	DataService.saveNow(player) -- the pets out and the coins in, written together
	Remotes.fire(player, "Notify", "sold", { coins = coins, count = #sold, key = sold[1] })
end

function SellService.Init() end

function SellService.Start()
	Remotes.on("SellPets", sell)
	Players.PlayerRemoving:Connect(function(p)
		lastSale[p] = nil
	end)
end

return SellService
