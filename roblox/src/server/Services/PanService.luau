--!strict
-- PanService (Round 4 phase 5): owns the pan upgrades, bought at your own pan's Pan Upgrades stand.
--   Slots      = upgrades.pen (how many pets the pan holds; rebirth resets it)
--   Look       = pan.look (straw -> wood -> stone -> crystal ice -> aurora; rebirth keeps it)
-- (Cold Level was removed with the Cold Power remake, 2026-11-10: the pan keeps every pet frozen.)
-- Prices and levels: Config.pan / Config.panPrice / Config.panMax. Buying follows GunService: decided
-- here, at the stand (the server's own position), price looked up on the server, checked again inside
-- the one DataService.mutate that charges (nothing can run in between), plus a short cooldown.
-- It also puts each pan's Look and its owner's Cold Power on the map (attributes PanLook<i> /
-- PanPower<i>), so every client draws every pan's look and gauge; the buyer's client then plays the
-- upgrade show (Show).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(script.Parent.Remotes)
local DataService = require(script.Parent.DataService)
local AnalyticsSvc = require(script.Parent.AnalyticsSvc)
local PlayerTracker = require(script.Parent.PlayerTracker)
local WorldService = require(script.Parent.WorldService)
local PenService = require(script.Parent.PenService)

type Data = DataService.Data

local PanService = {}
local P = Config.pan
local lastBuy: { [Player]: number } = {}
local shownOn: { [Player]: number } = {} -- the plot whose attributes this player set

function PanService.level(d: Data, kind: string): number
	if kind == "slots" then
		return d.upgrades.pen
	end
	return d.pan.look
end

-- what stops this player buying the next level of `kind` right now (nil = they can)
function PanService.blocker(d: Data, kind: string): string?
	local level = PanService.level(d, kind)
	local price = Config.panPrice(kind, level, d.rebirths)
	if not price then
		return "Max level"
	elseif d.coins < price then
		return `Need {Config.coinText(price - d.coins)} more`
	end
	return nil
end

local function atStand(player: Player): boolean
	local plot = WorldService.plotOf(player)
	local pl = plot and Config.world.plots[plot]
	local pos = PlayerTracker.position(player)
	if not pl or not pos then
		return false
	end
	local W = Config.world.pans
	local stand = Vector3.new(pl.x + W.boothOffset, 0, W.frontZ + 2.5) -- WorldService's stand, left of the door
	return (Vector3.new(pos.X, 0, pos.Z) - stand).Magnitude <= P.standRange
end

-- every client draws each pan's gauge and look from these
local function publish(player: Player)
	local d = DataService.get(player)
	local plot = WorldService.plotOf(player)
	local map = workspace:FindFirstChild("Map")
	if not d or not plot or not map then
		return
	end
	shownOn[player] = plot
	-- the owner's Cold Power on their pan's gauge, to 2 digits (it changes many times a second in the rink)
	local power = d.coldPower
	if power >= 100 then
		local unit = 10 ^ (math.floor(math.log10(power)) - 1)
		power = math.floor(power / unit) * unit
	end
	if map:GetAttribute("PanPower" .. plot) ~= power then
		map:SetAttribute("PanPower" .. plot, power)
	end
	if map:GetAttribute("PanLook" .. plot) ~= d.pan.look then
		map:SetAttribute("PanLook" .. plot, d.pan.look)
	end
end

local function buy(player: Player, kind: any)
	if typeof(kind) ~= "string" or not table.find(P.order, kind) then
		return
	end
	local d = DataService.get(player)
	if not d or not atStand(player) then
		return
	end
	local now = os.clock()
	if now - (lastBuy[player] or -math.huge) < P.buyCooldown then
		return -- spam: dropped quietly
	end
	local why = PanService.blocker(d, kind)
	if why then
		Remotes.notYet(player, why, "pan") -- a button press is always answered
		return
	end
	lastBuy[player] = now
	local old = PanService.level(d, kind)
	local paid, bought = 0, false
	DataService.mutate(player, function(x)
		-- checked again inside the change itself: nothing runs between this check and the charge
		if PanService.level(x, kind) ~= old or PanService.blocker(x, kind) then
			return
		end
		local price = Config.panPrice(kind, old, x.rebirths) :: number
		x.coins -= price
		paid, bought = price, true
		if kind == "slots" then
			x.upgrades.pen = old + 1
			PenService.fillEmptySlots(x) -- the new slots take the best pets from Storage
		else
			x.pan.look = old + 1
		end
	end)
	if not bought then
		return
	end
	AnalyticsSvc.funnel(player, "first_coins_spent")
	publish(player)
	-- the show plays first, then the save marks it seen (SKIP from the second upgrade on)
	Remotes.fire(player, "Notify", "panUpgraded", { kind = kind, level = old + 1, old = old, price = paid, plot = WorldService.plotOf(player) })
	DataService.mutate(player, function(x)
		x.seenShows.panUpgrade = true
	end)
	DataService.saveNow(player) -- a purchase is written at once
end

function PanService.Init() end

function PanService.Start()
	Remotes.on("BuyPanUpgrade", buy)
	DataService.Loaded:Connect(function(player: Player)
		task.defer(publish, player) -- after PenService has given the player a pan
	end)
	DataService.Changed:Connect(publish) -- a tester change or a rejoin puts it back too
	Players.PlayerRemoving:Connect(function(player)
		lastBuy[player] = nil
		local plot = shownOn[player]
		shownOn[player] = nil
		local map = workspace:FindFirstChild("Map")
		if plot and map then
			map:SetAttribute("PanPower" .. plot, nil) -- a free pan looks like a new one
			map:SetAttribute("PanLook" .. plot, nil)
		end
	end)
end

return PanService

