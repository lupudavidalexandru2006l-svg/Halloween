--!strict
-- ShopService: owns upgrade prices and buying (Ray, Boots, Backpack, Pen). Prices come from
-- Config.upgradeCost: level 2 costs baseCost and each step costs x1.5 the last. Coins are looked up
-- on the server; the client only says which upgrade it wants.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(script.Parent.Remotes)
local DataService = require(script.Parent.DataService)
local AnalyticsSvc = require(script.Parent.AnalyticsSvc)
local PlayerTracker = require(script.Parent.PlayerTracker)
local PenService = require(script.Parent.PenService)

local ShopService = {}
local lastOpened: { [Player]: number } = {}

-- nil when already at the top level
function ShopService.nextCost(id: string, level: number): number?
	local u = Config.upgrades[id]
	if not u or level >= u.maxLevel then
		return nil
	end
	return Config.upgradeCost(id, level + 1)
end

local function buy(player: Player, id: any)
	local d = DataService.get(player)
	if not d or typeof(id) ~= "string" or not table.find(Config.upgradeIds, id) then
		return
	end
	local level = d.upgrades[id]
	local cost = ShopService.nextCost(id, level)
	if not cost then
		Remotes.notYet(player, "Max level", id)
		return
	end
	if d.coins < cost then
		-- a button press is always answered
		Remotes.notYet(player, `Need {math.ceil(cost - d.coins)} more`, id)
		return
	end
	DataService.mutate(player, function(x)
		x.coins -= cost
		x.upgrades[id] = level + 1
		if id == "pen" then
			PenService.fillEmptySlots(x)
		end
	end)
	if id == "boots" or id == "backpack" then
		PlayerTracker.updateSpeed(player)
	end
	AnalyticsSvc.funnel(player, "first_coins_spent")
	DataService.saveNow(player)
	Remotes.fire(player, "Notify", "upgraded", { id = id, level = level + 1, cost = cost })
end

function ShopService.Init() end

function ShopService.Start()
	Remotes.on("BuyUpgrade", buy)
	Remotes.on("ShopOpened", function(player)
		local now = os.clock()
		if now - (lastOpened[player] or -math.huge) < Config.shopOpenedCooldown then
			return
		end
		lastOpened[player] = now
		AnalyticsSvc.event(player, "shop_opened", {})
	end)
	game:GetService("Players").PlayerRemoving:Connect(function(player)
		lastOpened[player] = nil
	end)
end

return ShopService
