--!strict
-- MonetizationService: the one ProcessReceipt in the game, plus the PolicyService check.
-- Super Freeze (15 R$, Rare and up, at most once per run, no timer, Game Plan 15): the cube is
-- written into the save (superCubes) and saved BEFORE PurchaseGranted. If the pet is gone by the
-- time the receipt arrives, the player gets a Super Freeze charge instead, so Robux is never lost.

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

local MonetizationService = {}

local SF = Config.monetization.superFreeze
local randomItemsOk: { [Player]: boolean } = {}

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
	if CarryService.count(player) >= CarryService.capacity(player) then
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
	Players.PlayerAdded:Connect(loadPolicy)
	for _, p in Players:GetPlayers() do
		task.spawn(loadPolicy, p)
	end
	Players.PlayerRemoving:Connect(function(p)
		randomItemsOk[p] = nil
	end)
end

return MonetizationService
