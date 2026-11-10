--!strict
-- GunService (Round 4 phase 4): owns the guns. Which guns a player has (bought in order, so it's just
-- the best one: d.guns.best) and which one they hold (d.guns.equipped), buying and equipping. Stats,
-- prices and rebirth locks live in Config.guns.list; the freeze itself reads the held gun through
-- FreezeService.gunTier (which also sets the GunTier attribute every client draws the gun from).
-- Buying is decided here: at the Equipment Booth (the server's own position), in order, the rebirth
-- lock, coins looked up on the server. The check and the charge run in one go with nothing that can
-- yield between them, so spam-buying can't charge twice; a short cooldown drops the spam anyway.
-- The client then plays the buy show (Show, Config.show.gunBuy).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(script.Parent.Remotes)
local DataService = require(script.Parent.DataService)
local AnalyticsSvc = require(script.Parent.AnalyticsSvc)
local PlayerTracker = require(script.Parent.PlayerTracker)

local GunService = {}
local G = Config.guns
local lastBuy: { [Player]: number } = {}

-- the gun this player holds (1 until their data has loaded)
function GunService.equipped(player: Player): number
	local d = DataService.get(player)
	return if d then math.clamp(d.guns.equipped, 1, #G.list) else 1
end

local function boothPos(): Vector3?
	for _, b in Config.world.booths do
		if b.id == "equipment" then
			return b.pos
		end
	end
	return nil
end

local function atBooth(player: Player): boolean
	local p, b = PlayerTracker.position(player), boothPos()
	return p ~= nil and b ~= nil and (Vector3.new(p.X, 0, p.Z) - Vector3.new(b.X, 0, b.Z)).Magnitude <= G.boothRange
end

-- what stops this player buying gun `index` right now (nil = they can)
function GunService.blocker(d: any, index: number): string?
	local g = G.list[index]
	if not g then
		return "No such gun"
	elseif index <= d.guns.best then
		return "Owned"
	elseif index > d.guns.best + 1 then
		return "Buy the one before first"
	elseif d.rebirths < g.rebirths then
		return `Needs Rebirth {g.rebirths}`
	elseif d.coins < g.price then
		return `Need {Config.coinText(g.price - d.coins)} more`
	end
	return nil
end

local function buy(player: Player, index: any)
	if typeof(index) ~= "number" or index ~= index or index % 1 ~= 0 or index < 1 or index > #G.list then
		return
	end
	local d = DataService.get(player)
	if not d or not atBooth(player) then
		return
	end
	local now = os.clock()
	if now - (lastBuy[player] or -math.huge) < G.buyCooldown then
		return -- spam: dropped quietly
	end
	local why = GunService.blocker(d, index)
	if why then
		if why ~= "Owned" then
			Remotes.notYet(player, why, "gun") -- a button press is always answered
		end
		return
	end
	lastBuy[player] = now
	local g = G.list[index]
	local old = d.guns.equipped
	local bought = false
	DataService.mutate(player, function(x)
		-- checked again inside the change itself: nothing runs between this check and the charge
		if GunService.blocker(x, index) then
			return
		end
		x.coins -= g.price
		x.guns.best = index
		x.guns.equipped = index -- a new gun goes straight into your hand; the old one waits in the locker
		bought = true
	end)
	if not bought then
		return
	end
	if g.price > 0 then
		AnalyticsSvc.funnel(player, "first_coins_spent")
	end
	player:SetAttribute("GunBest", index)
	-- the show plays first, then the save marks it seen (SKIP from the second buy on)
	Remotes.fire(player, "Notify", "gunBought", { gun = index, old = old, price = g.price })
	DataService.mutate(player, function(x)
		x.seenShows.gunBuy = true
	end)
	DataService.saveNow(player) -- a purchase is written at once
end

local function equip(player: Player, index: any)
	local d = DataService.get(player)
	if not d or typeof(index) ~= "number" or index ~= index or index % 1 ~= 0 or index < 1 or index > d.guns.best then
		return
	end
	if index == d.guns.equipped then
		return
	end
	DataService.mutate(player, function(x)
		x.guns.equipped = index
	end)
	Remotes.fire(player, "Notify", "gunEquipped", { gun = index })
end

-- ---------- the heat bar (Cold Power remake, 2026-11-10; Config.guns.heatBar) ----------
-- One bar per player, 0-1, kept here. FreezeService and TrainingService push it while the ray fires;
-- full = the gun steams for steamSeconds and can't fire, then the bar is empty again. Left alone it
-- cools. Clients draw it from the GunHeat / GunSteam attributes (the arc round the aim ring).
local HB = G.heatBar
type Heat = { value: number, pushedAt: number, steamUntil: number }
local heat: { [Player]: Heat } = {}

local function publishHeat(player: Player, h: Heat)
	local stepped = math.round(h.value / HB.step) * HB.step
	if player:GetAttribute("GunHeat") ~= stepped then
		player:SetAttribute("GunHeat", stepped)
	end
	local steam = h.steamUntil > 0
	if player:GetAttribute("GunSteam") ~= steam then
		player:SetAttribute("GunSteam", steam)
	end
end

-- the gun is steaming: it can't fire until it has cooled
function GunService.steaming(player: Player): boolean
	local h = heat[player]
	return h ~= nil and h.steamUntil > 0
end

-- adds to the bar; true when this push filled it (the steam starts now)
function GunService.addHeat(player: Player, amount: number): boolean
	local h = heat[player]
	if not h then
		h = { value = 0, pushedAt = 0, steamUntil = 0 }
		heat[player] = h
	end
	if h.steamUntil > 0 then
		return false
	end
	local now = os.clock()
	h.pushedAt = now
	h.value = math.min(1, h.value + math.max(0, amount))
	local full = h.value >= 1
	if full then
		h.steamUntil = now + HB.steamSeconds
	end
	publishHeat(player, h)
	return full
end

local function coolHeat(dt: number)
	local now = os.clock()
	for player, h in heat do
		if h.steamUntil > 0 then
			if now >= h.steamUntil then
				h.steamUntil = 0
				h.value = 0
				publishHeat(player, h)
			end
		elseif h.value > 0 and now - h.pushedAt > HB.coolAfter then
			h.value = math.max(0, h.value - dt / HB.coolSeconds)
			publishHeat(player, h)
		end
	end
end

local function setAttribute(player: Player)
	local d = DataService.get(player)
	if d then
		player:SetAttribute("GunBest", d.guns.best) -- the Equipment Booth draws owned / next from it
	end
end

function GunService.Init() end

function GunService.Start()
	Remotes.on("BuyGun", buy)
	Remotes.on("EquipGun", equip)
	DataService.Loaded:Connect(setAttribute)
	DataService.Changed:Connect(setAttribute) -- a tester wipe or rejoin puts it back too
	for _, p in Players:GetPlayers() do
		setAttribute(p)
	end
	Players.PlayerRemoving:Connect(function(p)
		lastBuy[p] = nil
		heat[p] = nil
	end)
	task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(0.1)
			local now = os.clock()
			coolHeat(now - last)
			last = now
		end
	end)
end

return GunService
