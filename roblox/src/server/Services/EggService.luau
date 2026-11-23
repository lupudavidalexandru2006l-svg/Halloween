--!strict
-- EggService: the limited Robux egg (LimitedEgg, owner 2026-11-22). The server decides everything:
--   * "Egg" remote { op = "buy", pack = "egg1" | "egg3" | "egg10" } or { op = "direct" } only asks; Roblox's
--     own purchase prompt shows, and the eggs are rolled and saved in ProcessReceipt (MonetizationService
--     hands every egg product here), in the same save as the receipt id, before "granted" goes back.
--     { op = "view" } answers with Notify "eggView" (your pity odds and incomes, for the Shop banner).
--   * Rolls use LimitedEgg.pick with the soft pity (data.egg.dry); a Legendary or better resets it.
--   * A hatched pet earns LimitedEgg pct x your best non-limited pet's income at that moment (fixed, saved as
--     PetEntry.inc), so eggs never stack on eggs.
--   * Paid random items only where PolicyService allows them (MonetizationService.randomItemsAllowed);
--     the hub stand's straight buy is not random, so it is always allowed.
--   * The client then plays the hatch show (Notify "eggHatch"); the show never decides anything.
-- Studio test: while a product id is 0, Studio grants it for free (like the other shop items).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local RunService = game:GetService("RunService")
local Config = require(ReplicatedStorage.Shared.Config)
local PetDefs = require(ReplicatedStorage.Shared.PetDefs)
local LimitedEgg = require(ReplicatedStorage.Shared.LimitedEgg)
local Remotes = require(script.Parent.Remotes)
local DataService = require(script.Parent.DataService)
local PenService = require(script.Parent.PenService)
local IndexService = require(script.Parent.IndexService)
local AnalyticsSvc = require(script.Parent.AnalyticsSvc)

type Data = DataService.Data

local EggService = {}
local rng = Random.new()
local busy: { [Player]: boolean } = {} -- a hatch is being saved (stops a double tap granting twice in Studio)

-- the best income among your non-limited pets right now (frozen ones count: they are yours)
function EggService.bestIncome(d: Data): number
	local best = 0
	for _, p in d.pets do
		if not PetDefs.isLimited(p.key) then
			local def = PetDefs.get(p.key)
			if def then
				best = math.max(best, PetDefs.income(def, p.pose, p.mut, p.sz))
			end
		end
	end
	return math.max(best, LimitedEgg.minIncome)
end

local function freeRoom(d: Data): number
	return Config.pen.storageMax - #d.pets
end

-- roll `n` eggs into the save (inside DataService.mutate). Returns what hatched.
local function hatchInto(x: Data, n: number, direct: string?): { { key: string, inc: number, tier: string, odds: number, new: boolean } }
	local base = EggService.bestIncome(x)
	local out = {}
	for _ = 1, n do
		local key: string
		local odds: number
		if direct then
			key, odds = direct, 100
		else
			local shown = LimitedEgg.odds(x.egg.dry)
			local i = LimitedEgg.pick(x.egg.dry, rng:NextNumber(0, 100))
			key, odds = LimitedEgg.pets[i].key, shown[i]
		end
		local e = LimitedEgg.pet(key) :: LimitedEgg.EggPet
		local rank = Config.tier(e.tier).rank
		if not direct then
			x.egg.opened += 1
			if rank >= Config.tier("Legendary").rank then
				x.egg.dry = 0
			else
				x.egg.dry += 1
			end
		end
		local inc = math.floor(base * e.pct * 100 + 0.5) / 100
		local new = not x.found[key]
		local eq = PenService.equippedCount(x) < PenService.slots(x)
		table.insert(x.pets, { id = "q" .. x.nextPetId, key = key, pose = "idle", at = os.time(), eq = eq, inc = inc })
		x.nextPetId += 1
		x.found[key] = true
		x.egg.got[key] = (x.egg.got[key] or 0) + 1
		table.insert(out, { key = key, inc = inc, tier = e.tier, odds = odds, new = new })
	end
	PenService.fitSlots(x) -- the best pets sit in the pan (a 250% pet goes straight in)
	return out
end

-- after the save: tell the client (hatch show), the Index, analytics and everyone for a Mythic
local function announce(player: Player, results: { any }, how: string)
	local d = DataService.get(player)
	if d then
		for _, r in results do
			if r.new then
				IndexService.onFound(player, r.key, d.found, d.indexClaimed)
			end
		end
	end
	-- best last, so the show ends on the best pet
	table.sort(results, function(a, b)
		return Config.tier(a.tier).rank < Config.tier(b.tier).rank
	end)
	Remotes.fire(player, "Notify", "eggHatch", { egg = LimitedEgg.id, results = results, how = how })
	for _, r in results do
		AnalyticsSvc.event(player, "egg_hatch", { pet = r.key, tier = r.tier, how = how })
		if Config.tier(r.tier).rank >= Config.tier("Mythic").rank then
			local e = LimitedEgg.pet(r.key)
			Remotes.fireAll("Notify", "adminAbuse", { text = `{player.DisplayName} hatched the {if e then e.name else r.key}!`, color = "luck", seconds = 6 })
		end
	end
	PenService.markDirty(player)
	local d2 = DataService.get(player)
	if d2 then
		Remotes.fire(player, "Notify", "eggView", EggService.view(d2))
	end
end

-- Studio while a product isn't made yet: grant straight away (no Robux)
local function studioGrant(player: Player, n: number, direct: string?)
	if busy[player] then
		return
	end
	busy[player] = true
	local results = {}
	DataService.mutate(player, function(x)
		results = hatchInto(x, n, direct)
	end)
	if DataService.saveNow(player) then
		announce(player, results, "studio")
	end
	busy[player] = nil
end

local function ask(player: Player, msg: any)
	if typeof(msg) ~= "table" then
		return
	end
	local d = DataService.get(player)
	if not d then
		return
	end
	if msg.op == "view" then -- the Shop banner asks for your pity odds and incomes
		Remotes.fire(player, "Notify", "eggView", EggService.view(d))
		return
	end
	if msg.op == "seen" then -- the hatch show played once: SKIP shows from now on
		if not d.seenShows.egg then
			DataService.mutate(player, function(x)
				x.seenShows.egg = true
			end)
		end
		return
	end
	if not LimitedEgg.onSale(os.time()) then
		Remotes.notYet(player, `The {LimitedEgg.name} has left`)
		return
	end
	local n, productId, direct = 0, 0, nil
	if msg.op == "buy" and typeof(msg.pack) == "string" then
		local pack = LimitedEgg.pack(msg.pack)
		if not pack then
			return
		end
		if not require(script.Parent.MonetizationService).randomItemsAllowed(player) then
			Remotes.notYet(player, "Not available here")
			return
		end
		n, productId = pack.eggs, pack.productId
	elseif msg.op == "direct" then
		n, productId, direct = 1, LimitedEgg.direct.productId, LimitedEgg.direct.key
	else
		return
	end
	if freeRoom(d) < n then
		Remotes.notYet(player, `Make room first: {n} free spot{if n == 1 then "" else "s"} in your Pets`, "pets")
		return
	end
	-- msg.test (Studio play tests only): hatch for free, so the show can be filmed without a purchase
	if productId ~= 0 and not (RunService:IsStudio() and msg.test == true) then
		MarketplaceService:PromptProductPurchase(player, productId)
	elseif RunService:IsStudio() then
		studioGrant(player, n, direct)
	else
		Remotes.notYet(player, "Not available yet")
	end
end

-- MonetizationService's ProcessReceipt asks this first. Returns nil when the product isn't an egg one;
-- otherwise the decision. The receipt id is saved in the same save as the pets.
function EggService.receipt(player: Player, receipt: { [string]: any }): Enum.ProductPurchaseDecision?
	local pid = receipt.ProductId
	local n, direct = 0, nil
	for _, p in LimitedEgg.packs do
		if p.productId ~= 0 and p.productId == pid then
			n = p.eggs
		end
	end
	if LimitedEgg.direct.productId ~= 0 and LimitedEgg.direct.productId == pid then
		n, direct = 1, LimitedEgg.direct.key
	end
	if n == 0 then
		return nil
	end
	local d = DataService.get(player)
	if not d then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	-- a bought egg is always granted, even past the leave date or with full Pets (never lose a paid pet):
	-- Storage may go over its usual cap by these few pets
	local purchaseId = tostring(receipt.PurchaseId)
	local results = {}
	DataService.mutate(player, function(x)
		results = hatchInto(x, n, direct)
		table.insert(x.receipts, purchaseId)
		while #x.receipts > Config.data.receiptsKept do
			table.remove(x.receipts, 1)
		end
	end)
	if not DataService.saveNow(player) then
		return Enum.ProductPurchaseDecision.NotProcessedYet -- Roblox asks again; the receipt id stops a double grant
	end
	announce(player, results, if direct then "direct" else "egg")
	local robux = if direct then LimitedEgg.direct.robux else 0
	for _, p in LimitedEgg.packs do
		if p.productId == pid then
			robux = p.robux
		end
	end
	AnalyticsSvc.event(player, "offer_bought", { offer = if direct then "egg_direct" else `egg{n}`, robux = robux })
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

-- the shop needs these numbers: your pity odds and the income each pet would hatch with right now
function EggService.view(d: Data): { [string]: any }
	local base = EggService.bestIncome(d)
	local incomes = {}
	for i, e in LimitedEgg.pets do
		incomes[i] = math.floor(base * e.pct * 100 + 0.5) / 100
	end
	return { odds = LimitedEgg.odds(d.egg.dry), incomes = incomes, opened = d.egg.opened, got = d.egg.got }
end

-- the hub stand (owner screenshot 2026-11-22: the best pet on a stepped plinth, "250% Of Best Pet! Only 499").
-- Built here so it lives in code; the pet stands still on top, a glow ring turns under it (client-free).
-- Its prompt buys the pet straight (no roll). After the leave date it says ENDED! and the prompt goes.
-- Owner 2026-11-22: moved from the spawn (28, 0, -5) to the open snow beside the Feedback mailbox (121, -10).
local STAND = { pos = Vector3.new(138, 0, -12), faceTo = Vector3.new(0, 0, -34), petHeight = 9 }

local function buildStand()
	local e = LimitedEgg.pet(LimitedEgg.direct.key) :: LimitedEgg.EggPet
	local old = workspace:FindFirstChild("LimitedEggStand")
	if old then
		old:Destroy()
	end
	local m = Instance.new("Model")
	m.Name = "LimitedEggStand"
	local look = CFrame.lookAt(STAND.pos, Vector3.new(STAND.faceTo.X, STAND.pos.Y, STAND.faceTo.Z))
	local function block(size: Vector3, y: number, color: Color3, mat: Enum.Material): Part
		local p = Instance.new("Part")
		p.Anchored = true
		p.Size = size
		p.CFrame = look * CFrame.new(0, y, 0)
		p.Color = color
		p.Material = mat
		p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
		p.Parent = m
		return p
	end
	-- stepped plinth: dark ice, gold trim, a glowing aurora band, the top step
	block(Vector3.new(14, 1.2, 14), 0.6, Color3.fromRGB(28, 34, 80), Enum.Material.SmoothPlastic)
	block(Vector3.new(14.6, 0.35, 14.6), 1.3, Color3.fromRGB(255, 200, 60), Enum.Material.SmoothPlastic)
	block(Vector3.new(11, 1.4, 11), 2.15, Color3.fromRGB(40, 50, 120), Enum.Material.SmoothPlastic)
	local band = block(Vector3.new(11.3, 0.45, 11.3), 2.4, Color3.fromRGB(80, 230, 210), Enum.Material.Neon)
	band.Transparency = 0.1
	local top = block(Vector3.new(8.5, 0.8, 8.5), 3.25, Color3.fromRGB(150, 210, 255), Enum.Material.Ice)
	local light = Instance.new("PointLight")
	light.Color, light.Range, light.Brightness = Color3.fromRGB(150, 200, 255), 16, 1.5
	light.Parent = top
	local sp = Instance.new("ParticleEmitter")
	sp.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sp.LightEmission, sp.Rate = 1, 6
	sp.Lifetime = NumberRange.new(1, 2)
	sp.Speed = NumberRange.new(1, 3)
	sp.Color = ColorSequence.new(Color3.fromRGB(120, 230, 255), Color3.fromRGB(255, 150, 230))
	sp.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) })
	sp.Parent = top
	-- the pet, standing on top and facing the spawn
	local models = ReplicatedStorage:FindFirstChild("PetModels")
	local src = models and models:FindFirstChild(e.key)
	if src and src:IsA("Model") then
		local pet = src:Clone()
		for _, d in pet:GetDescendants() do
			if d:IsA("BasePart") then
				d.Anchored, d.CanCollide = true, false
			end
		end
		local rh = pet:GetAttribute("RigHeight")
		local h0 = if typeof(rh) == "number" and rh > 0 then rh else pet:GetExtentsSize().Y
		pet:ScaleTo(pet:GetScale() * STAND.petHeight / math.max(0.01, h0))
		pet:PivotTo(look * CFrame.new(0, 3.65 + STAND.petHeight / 2, 0)) -- pets face -Z, so does `look`
		pet.Name = "Pet"
		pet.Parent = m
	end
	-- the sign over it: name, power, price, and the leave date when the owner has set one
	local anchor = block(Vector3.one * 0.2, 3.65 + STAND.petHeight + 3, Color3.new(1, 1, 1), Enum.Material.SmoothPlastic)
	anchor.Transparency, anchor.CanCollide, anchor.CanQuery = 1, false, false
	anchor.Name = "SignAnchor"
	local g = Instance.new("BillboardGui")
	g.Name = "Sign"
	g.Size = UDim2.fromScale(16, 7)
	g.MaxDistance = 140
	g.LightInfluence = 0
	g.Parent = anchor
	local function line(text: string, y: number, h: number, color: Color3)
		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1
		t.Size = UDim2.fromScale(1, h)
		t.Position = UDim2.fromScale(0, y)
		t.Font = Enum.Font.FredokaOne
		t.TextScaled = true
		t.Text = text
		t.TextColor3 = color
		local s = Instance.new("UIStroke")
		s.Thickness = 3
		s.Color = Color3.fromRGB(20, 22, 50)
		s.Parent = t
		t.Parent = g
		return t
	end
	local onSale = LimitedEgg.onSale(os.time())
	local leaves = LimitedEgg.leavesText()
	line(if onSale then (leaves or "LIMITED!") else "ENDED!", 0, 0.2, if onSale then Color3.fromRGB(255, 120, 210) else Color3.fromRGB(255, 80, 80))
	line(e.name, 0.2, 0.26, Color3.new(1, 1, 1))
	line(`{math.floor(e.pct * 100)}% Of Best Pet!`, 0.46, 0.24, Color3.fromRGB(255, 220, 80))
	line(`Only R$ {LimitedEgg.direct.robux}!`, 0.7, 0.28, Color3.fromRGB(120, 255, 140))
	if onSale then
		local pp = Instance.new("ProximityPrompt")
		pp.ActionText = `Buy {e.name}`
		pp.ObjectText = `R$ {LimitedEgg.direct.robux}`
		pp.HoldDuration = 0
		pp.MaxActivationDistance = 14
		pp.RequiresLineOfSight = false
		pp.Parent = top
		pp.Triggered:Connect(function(player)
			ask(player, { op = "direct" })
		end)
	end
	m.Parent = workspace
end

function EggService.Init() end

function EggService.Start()
	Remotes.on("Egg", ask)
	task.defer(buildStand)
	Players.PlayerRemoving:Connect(function(p)
		busy[p] = nil
	end)
end

return EggService
