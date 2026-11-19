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
local BoostService = require(script.Parent.BoostService)

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
		Remotes.notYet(player, "Take your pet home first!", "offer")
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

-- ---------- skipping a Thaw Machine's wait (owner 2026-11-12; at the machine only, not in the Shop) ----------
-- The price steps with the time left (Config.thaw.skip.tiers). The receipt finishes the pet that was in
-- that machine when the player asked; if it already came out by itself, the skip is kept (thawSkips)
-- and used free next time. Saved before PurchaseGranted, like every product.
local skipAsked: { [Player]: { machine: number, at: number } } = {}

local function thawingIn(d: any, m: number): any?
	for _, p in d.pets do
		if p.thawM == m and (p.thawEnd or 0) > os.time() then
			return p
		end
	end
	return nil
end

-- the Robux price of the skip tier sold as this product (nil = not a skip)
local function skipTierRobux(productId: number): number?
	if productId == 0 then
		return nil
	end
	for _, t in Config.thaw.skip.tiers do
		if t.productId == productId then
			return t.robux
		end
	end
	return Config.thaw.skip.retired[productId]
end

-- inside a data change: the pet in machine m comes out on the next machine tick (PenService), or the
-- skip is kept for later. Returns "done" or "kept".
local function applySkip(x: any, m: number?): string
	local p = if m then thawingIn(x, m) else nil
	if p then
		p.thawEnd = os.time()
		return "done"
	end
	x.thawSkips = math.min(x.thawSkips + 1, 999)
	return "kept"
end

local function requestSkip(player: Player, m: any)
	local d = DataService.get(player)
	if not d or typeof(m) ~= "number" or m ~= math.floor(m) or m < 1 or m > 2 then
		return
	end
	local asked = skipAsked[player]
	if asked and os.clock() - asked.at < Config.thaw.skip.cooldown then
		return
	end
	local p = thawingIn(d, m)
	if not p then
		return
	end
	skipAsked[player] = { machine = m, at = os.clock() }
	if d.thawSkips > 0 then -- one bought earlier: used with a tap, no purchase
		DataService.mutate(player, function(x)
			if x.thawSkips > 0 and thawingIn(x, m) then
				x.thawSkips -= 1
				applySkip(x, m)
			end
		end)
		DataService.saveNow(player)
		return
	end
	local tier = Config.thawSkipTier((p.thawEnd or 0) - os.time())
	if tier.productId ~= 0 then
		MarketplaceService:PromptProductPurchase(player, tier.productId)
	elseif RunService:IsStudio() then
		DataService.mutate(player, function(x) -- Studio test until the owner makes the products
			applySkip(x, m)
		end)
		DataService.saveNow(player)
	else
		Remotes.notYet(player, "Not available yet", "thaw")
	end
end

-- ---------- Skip all (owner 2026-11-16): one product thaws every frozen pet at once ----------
-- a pet still in its cube: thawing in a machine, or waiting in your Pets for one
local function stillFrozen(p: any, now: number): boolean
	return p.frozen == true and (not p.thawM or (p.thawEnd or 0) > now)
end

local function frozenCount(d: any): number
	local n, now = 0, os.time()
	for _, p in d.pets do
		if stillFrozen(p, now) then
			n += 1
		end
	end
	return n
end

-- inside a data change: every frozen pet's time is up, so the next machine tick (PenService) lets them
-- all out, a pet that was waiting in your Pets through machine 1. Nothing left frozen = kept for later.
local function applySkipAll(x: any): string
	local now, n = os.time(), 0
	for _, p in x.pets do
		if stillFrozen(p, now) then
			p.thawM = p.thawM or 1
			p.thawTotal = p.thawTotal or 1
			p.thawEnd = now
			n += 1
		end
	end
	if n > 0 then
		return "done"
	end
	x.thawSkipAlls = math.min(x.thawSkipAlls + 1, 99)
	return "kept"
end

local skipAllAt: { [Player]: number } = {}
local function requestSkipAll(player: Player)
	local d = DataService.get(player)
	if not d then
		return
	end
	local now = os.clock()
	if now - (skipAllAt[player] or -math.huge) < Config.thaw.skip.cooldown then
		return
	end
	skipAllAt[player] = now
	local A = Config.thaw.skip.all
	local kept = d.thawSkipAlls > 0
	if frozenCount(d) < (if kept then 1 else A.minPets) then
		return
	end
	if kept then -- one bought earlier: used with a tap, no purchase
		DataService.mutate(player, function(x)
			if x.thawSkipAlls > 0 and frozenCount(x) > 0 then
				x.thawSkipAlls -= 1
				applySkipAll(x)
			end
		end)
		DataService.saveNow(player)
	elseif A.productId ~= 0 then
		MarketplaceService:PromptProductPurchase(player, A.productId)
	elseif RunService:IsStudio() then
		DataService.mutate(player, function(x) -- Studio test until the owner makes the product
			applySkipAll(x)
		end)
		DataService.saveNow(player)
	else
		Remotes.notYet(player, "Not available yet", "pets")
	end
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
	local kind = item.kind
	local coins = if kind == "coins" then Config.robuxCoins(item, PenService.incomePerSecond(d)) else 0
	local charges = if kind == "charges" then item.charges or 0 else 0
	local power = if kind == "power" then Config.powerPack(item, d.coldPower) else 0 -- sized from the Cold Power you have right now
	local now = os.time()
	local minutes = (item.minutes or 0) * 60
	-- the 2026-11-18 boosts (BoostService runs them)
	if kind == "deal" then
		local bag = Config.robuxItem("coinsSmall")
		coins = if bag then Config.robuxCoins(bag, PenService.incomePerSecond(d)) else 0
		charges = 3
	elseif kind == "welcomeDouble" then
		-- still on the card: collected now at x2; already collected: that amount once more
		coins = if d.welcome then d.welcome.coins * 2 else d.boosts.lastWelcome
	end
	local kept = false -- Keep It Frozen with no cube left to freeze: a Super Freeze charge instead
	if kind == "keepFrozen" and not CarryService.keepFrozen(player) then
		charges = 1
		kept = true
	end
	DataService.mutate(player, function(x)
		x.coins = math.min(x.coins + coins, 1e15)
		x.superFreezeCharges = math.min(x.superFreezeCharges + charges, 999)
		x.coldPower = math.min(x.coldPower + power, Config.coldPower.max)
		local b = x.boosts
		if kind == "speed" then
			local mult = 1 + (item.speed or 0)
			if now < b.speedUntil and b.speedMult >= mult then
				b.speedUntil += minutes -- the same or a stronger one already running: it lasts longer
			else
				b.speedMult, b.speedUntil = mult, now + minutes
			end
		elseif kind == "luck" then
			b.luckUntil = math.max(now, b.luckUntil) + minutes
		elseif kind == "shield" then
			b.shields = math.min(b.shields + (item.charges or 0), 999)
		elseif kind == "deal" then
			b.deal = true
			b.luckUntil = math.max(now, b.luckUntil) + 30 * 60
		elseif kind == "welcomeDouble" then
			x.welcome = nil
			b.lastWelcome = 0
		end
	end)
	if kind == "serverLuck" then
		local cur = workspace:GetAttribute("BoughtLuckUntil")
		local from = math.max(workspace:GetServerTimeNow(), if typeof(cur) == "number" then cur else 0)
		workspace:SetAttribute("BoughtLuckUntil", from + minutes)
		Remotes.fireAll("Notify", "adminAbuse", { text = `{player.DisplayName} bought SERVER LUCK! 2x luck for everyone for {item.minutes} min!`, color = "luck", seconds = 6 })
	end
	if kind == "welcomeDouble" and coins > 0 then
		Remotes.fire(player, "Notify", "welcomeCollected", { coins = coins })
	end
	if kind == "keepFrozen" and kept then
		Remotes.fire(player, "Notify", "chargeSaved", {})
	end
	AnalyticsSvc.coinsIn(player, coins, "robux_pack")
	BoostService.refresh(player)
	local chill = kind == "chill"
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
	local d0 = DataService.get(player) :: any
	if item.kind == "deal" and d0.boosts.deal then
		Remotes.notYet(player, "You already have the Welcome Deal")
		return
	end
	if item.kind == "welcomeDouble" and not d0.welcome then
		return -- nothing waiting on the card
	end
	if item.kind == "keepFrozen" and CarryService.count(player) == 0 then
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
		-- already granted (a retry): only say so once that grant is really saved (review 2026-11-10: the
		-- first try may have failed to save, and "granted" would then end Roblox's retries with nothing stored)
		return if DataService.saveNow(player) then Enum.ProductPurchaseDecision.PurchaseGranted else Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local all = Config.thaw.skip.all
	if all.productId ~= 0 and receipt.ProductId == all.productId then
		local result = "kept"
		DataService.mutate(player, function(x)
			result = applySkipAll(x)
			table.insert(x.receipts, purchaseId)
			while #x.receipts > Config.data.receiptsKept do
				table.remove(x.receipts, 1)
			end
		end)
		if not DataService.saveNow(player) then
			return Enum.ProductPurchaseDecision.NotProcessedYet -- not saved: Roblox asks again, the receipt id stops a double grant
		end
		if result == "kept" then
			Remotes.fire(player, "Notify", "skipAllKept", {})
		end
		AnalyticsSvc.event(player, "offer_bought", { offer = "thaw_skip_all", robux = all.robux })
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	local skipRobux = skipTierRobux(receipt.ProductId)
	if skipRobux then
		local asked = skipAsked[player]
		skipAsked[player] = nil
		local result = "kept"
		DataService.mutate(player, function(x)
			result = applySkip(x, if asked then asked.machine else nil)
			table.insert(x.receipts, purchaseId)
			while #x.receipts > Config.data.receiptsKept do
				table.remove(x.receipts, 1)
			end
		end)
		if not DataService.saveNow(player) then
			return Enum.ProductPurchaseDecision.NotProcessedYet -- not saved: Roblox asks again, the receipt id stops a double grant
		end
		if result == "kept" then
			Remotes.fire(player, "Notify", "skipKept", {})
		end
		AnalyticsSvc.event(player, "offer_bought", { offer = "thaw_skip", robux = skipRobux })
		return Enum.ProductPurchaseDecision.PurchaseGranted
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
	-- 2x Welcome Back closed without buying: the card's coins are collected as usual, so they're never left behind
	local wd = Config.robuxItem("welcomeDouble")
	MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId: number, productId: number, bought: boolean)
		if bought or not wd or productId ~= wd.productId then
			return
		end
		local p = Players:GetPlayerByUserId(userId)
		if p then
			PenService.collectWelcome(p)
		end
	end)
	Remotes.on("RequestSuperFreeze", requestSuperFreeze)
	Remotes.on("BuyRobux", buyRobux)
	Remotes.on("SkipThaw", requestSkip)
	Remotes.on("SkipThawAll", requestSkipAll)
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
				-- this signal comes from the client, so ask Roblox before giving the pass (review 2026-11-10).
				-- Roblox's own answer can lag a few seconds behind a purchase: a few tries.
				task.spawn(function()
					for _ = 1, Config.monetization.passCheck.tries do
						local ok, has = pcall(function()
							return MarketplaceService:UserOwnsGamePassAsync(player.UserId, passId)
						end)
						if not player.Parent then
							return
						end
						if ok and has then
							setPass(player, item.id)
							Remotes.fire(player, "Notify", "robuxBought", { name = item.name, coins = 0, charges = 0 })
							AnalyticsSvc.event(player, "offer_bought", { offer = item.id, robux = item.robux })
							return
						end
						task.wait(Config.monetization.passCheck.seconds)
					end
				end)
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(p)
		randomItemsOk[p] = nil
		passes[p] = nil
		skipAsked[p] = nil
		skipAllAt[p] = nil
	end)
end

return MonetizationService
