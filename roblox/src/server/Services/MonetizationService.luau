--!strict
-- MonetizationService: the one ProcessReceipt in the game, plus the PolicyService check.
-- Super Freeze (15 R$, Rare and up, at most once per run, no timer, Game Plan 15): the cube is
-- written into the save (superCubes) and saved BEFORE PurchaseGranted. If the pet is gone by the
-- time the receipt arrives, the player gets a Super Freeze charge instead, so Robux is never lost.
-- The Shop's Robux tab (owner 2026-11-05, Config.monetization.shop): coin packs and Super Freeze packs
-- are developer products granted here the same way (saved before PurchaseGranted, receipt ids stop a
-- double grant); 2x Coins is a game pass, checked with Roblox on join and after buying (PenService).
-- Cold Power (2026-11-10): two more passes (Full-Speed Auto-Train, 2x Cold Power) and the Cold Power
-- packs (kind "power": a share of your next island's need, granted like coin packs). Every pass a
-- player owns is kept here (MonetizationService.owns) and marked on the player as a `Pass_<id>`
-- attribute, which other services and the client read.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local PolicyService = game:GetService("PolicyService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(script.Parent.Remotes)
local DataService = require(script.Parent.DataService)
local AnalyticsSvc = require(script.Parent.AnalyticsSvc)
local PlayerTracker = require(script.Parent.PlayerTracker)
local WildPetSpawner = require(script.Parent.WildPetSpawner)
local CarryService = require(script.Parent.CarryService)
local PenService = require(script.Parent.PenService)
local EventService = require(script.Parent.EventService)

local MonetizationService = {}

local SF = Config.monetization.superFreeze
local randomItemsOk: { [Player]: boolean } = {}
local passes: { [Player]: { [string]: boolean } } = {} -- the game passes each player owns, by shop item id

function MonetizationService.owns(player: Player, id: string): boolean
	local mine = passes[player]
	return mine ~= nil and mine[id] == true
end

local function setPass(player: Player, id: string)
	local mine = passes[player] or {}
	passes[player] = mine
	mine[id] = true
	player:SetAttribute("Pass_" .. id, true)
	if id == "doubleCoins" then
		PenService.setDoubleCoins(player, true)
	end
end

-- paid random items (Frozen Crates, a later layer) are hidden where they're restricted. A failed
-- policy lookup counts as restricted: the safe answer for a child.
function MonetizationService.randomItemsAllowed(player: Player): boolean
	return randomItemsOk[player] == true
end

local function loadPolicy(player: Player)
	local ok, info = pcall(function()
		return PolicyService:GetPolicyInfoForPlayerAsync(player)
	end)
	randomItemsOk[player] = ok and typeof(info) == "table" and info.ArePaidRandomItemsRestricted == false
end

local function offerPet(player: Player, petId: any): WildPetSpawner.WildPet?
	if not Remotes.isId(petId, 16) then
		return nil
	end
	local pet = WildPetSpawner.get(petId)
	local pos = PlayerTracker.position(player)
	if not pet or pet.offerFor ~= player or pet.state ~= "dazed" or not pos then
		return nil
	end
	if (pos - pet.root.Position).Magnitude > SF.walkAwayStuds then
		return nil
	end
	return pet
end

local function grantSuperFreeze(player: Player): boolean
	local ok = CarryService.superFreezeOffer(player)
	if not ok then
		DataService.mutate(player, function(d)
			d.superFreezeCharges += 1
		end)
		Remotes.fire(player, "Notify", "chargeSaved", {})
	end
	return ok
end

local function requestSuperFreeze(player: Player, petId: any)
	local d = DataService.get(player)
	local pet = offerPet(player, petId)
	if not d or not pet then
		return
	end
	if CarryService.load(player) >= CarryService.capacity(player) then
		Remotes.notYet(player, "Backpack full", "offer")
		return
	end
	if d.superFreezeCharges > 0 then
		-- a charge bought earlier (or saved from a missed offer): used with a tap, no purchase
		DataService.mutate(player, function(x)
			x.superFreezeCharges -= 1
		end)
		if not CarryService.superFreezeOffer(player) then
			DataService.mutate(player, function(x)
				x.superFreezeCharges += 1
			end)
		end
		DataService.saveNow(player)
		return
	end
	if SF.productId == 0 then
		if RunService:IsStudio() then
			grantSuperFreeze(player) -- Studio test until the owner creates the product
			DataService.saveNow(player)
		else
			Remotes.notYet(player, "Not available yet", "offer")
		end
		return
	end
	MarketplaceService:PromptProductPurchase(player, SF.productId)
end

-- ---------- the Shop's Robux tab ----------
local function productItem(productId: number): Config.RobuxItem?
	if productId == 0 then
		return nil
	end
	for _, item in Config.monetization.shop do
		if item.kind ~= "pass" and item.productId == productId then
			return item
		end
	end
	return nil
end

-- puts one Robux shop product into the save; returns what to tell the player once it's saved.
-- Coin packs are worth minutes of the income you have right now. Bought coins go straight onto your
-- coins, not through PenService.addCoins, so they never count on the weekly "coins earned" board.
local function grantItem(player: Player, item: Config.RobuxItem): { [string]: any }?
	local d = DataService.get(player)
	if not d then
		return nil
	end
	local coins = if item.kind == "coins" then Config.robuxCoins(item, PenService.incomePerSecond(d)) else 0
	local charges = if item.kind == "charges" then item.charges or 0 else 0
	local power = if item.kind == "power" then Config.powerPack(item, d.coldPower) else 0 -- sized from the Cold Power you have right now
	DataService.mutate(player, function(x)
		x.coins = math.min(x.coins + coins, 1e15)
		x.superFreezeCharges = math.min(x.superFreezeCharges + charges, 999)
		x.coldPower = math.min(x.coldPower + power, Config.coldPower.max)
	end)
	local chill = item.kind == "chill"
	if chill then
		EventService.startBought(player.DisplayName) -- for everyone, at once; its shout-out is the thank-you
	end
	return { name = item.name, coins = coins, charges = charges, chill = chill, power = power }
end

-- every game pass in the shop, asked of Roblox once the save is loaded
local function checkPass(player: Player)
	for _, item in Config.monetization.shop do
		local passId = item.passId or 0
		if item.kind == "pass" and passId ~= 0 then
			local ok, has = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, passId)
			end)
			if ok and has and player.Parent then
				setPass(player, item.id)
			end
		end
	end
end

local function buyRobux(player: Player, id: any)
	if not Remotes.isId(id) then
		return
	end
	local item = Config.robuxItem(id)
	if not item or not DataService.get(player) then
		return
	end
	if item.kind == "pass" then
		if MonetizationService.owns(player, item.id) then
			return
		end
		if (item.passId or 0) ~= 0 then
			MarketplaceService:PromptGamePassPurchase(player, item.passId :: number)
		elseif RunService:IsStudio() then
			setPass(player, item.id) -- Studio test until the owner makes the pass (not saved)
			Remotes.fire(player, "Notify", "robuxBought", { name = item.name, coins = 0, charges = 0 })
		else
			Remotes.notYet(player, "Not available yet")
		end
		return
	end
	if (item.productId or 0) ~= 0 then
		MarketplaceService:PromptProductPurchase(player, item.productId :: number)
	elseif RunService:IsStudio() then
		local note = grantItem(player, item) -- Studio test until the owner makes the product
		if note and DataService.saveNow(player) then
			Remotes.fire(player, "Notify", "robuxBought", note)
		end
	else
		Remotes.notYet(player, "Not available yet")
	end
end

local function processReceipt(receipt: { [string]: any }): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	local d = player and DataService.get(player)
	if not player or not d then
		return Enum.ProductPurchaseDecision.NotProcessedYet -- Roblox retries when they're back
	end
	local purchaseId = tostring(receipt.PurchaseId)
	if table.find(d.receipts, purchaseId) then
		return Enum.ProductPurchaseDecision.PurchaseGranted -- already granted (a retry)
	end
	local item = productItem(receipt.ProductId)
	if item then
		local note = grantItem(player, item)
		DataService.mutate(player, function(x)
			table.insert(x.receipts, purchaseId)
			while #x.receipts > Config.data.receiptsKept do
				table.remove(x.receipts, 1)
			end
		end)
		if not note or not DataService.saveNow(player) then
			return Enum.ProductPurchaseDecision.NotProcessedYet -- not saved: Roblox asks again, the receipt id stops a double grant
		end
		Remotes.fire(player, "Notify", "robuxBought", note)
		AnalyticsSvc.event(player, "offer_bought", { offer = item.id, robux = item.robux })
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	if receipt.ProductId ~= SF.productId or SF.productId == 0 then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	grantSuperFreeze(player)
	DataService.mutate(player, function(x)
		table.insert(x.receipts, purchaseId)
		while #x.receipts > Config.data.receiptsKept do
			table.remove(x.receipts, 1)
		end
	end)
	if not DataService.saveNow(player) then
		return Enum.ProductPurchaseDecision.NotProcessedYet -- not saved: Roblox asks again, and the receipt id stops a double grant
	end
	AnalyticsSvc.event(player, "offer_bought", { offer = "super_freeze", robux = SF.robux })
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

function MonetizationService.Init() end

function MonetizationService.Start()
	MarketplaceService.ProcessReceipt = processReceipt
	Remotes.on("RequestSuperFreeze", requestSuperFreeze)
	Remotes.on("BuyRobux", buyRobux)
	Players.PlayerAdded:Connect(loadPolicy)
	for _, p in Players:GetPlayers() do
		task.spawn(loadPolicy, p)
	end
	-- 2x Coins: asked of Roblox once the save is loaded (the flag lives with the save's session)
	DataService.Loaded:Connect(function(player: Player)
		task.spawn(checkPass, player)
	end)
	for _, p in Players:GetPlayers() do
		if DataService.get(p) then
			task.spawn(checkPass, p) -- loaded before this service started
		end
	end
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player: Player, passId: number, bought: boolean)
		if not bought or passId == 0 then
			return
		end
		for _, item in Config.monetization.shop do
			if item.kind == "pass" and item.passId == passId then
				setPass(player, item.id)
				Remotes.fire(player, "Notify", "robuxBought", { name = item.name, coins = 0, charges = 0 })
				AnalyticsSvc.event(player, "offer_bought", { offer = item.id, robux = item.robux })
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(p)
		randomItemsOk[p] = nil
		passes[p] = nil
	end)
end

return MonetizationService
