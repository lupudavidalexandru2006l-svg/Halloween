--!strict
-- PanService (Round 4 phase 5): owns the pan upgrades, bought at your own pan's Pan Upgrades stand.
--   Slots      = upgrades.pen (how many pets the pan holds, and Thaw Machines 2-3; kept through rebirth since 2026-11-17)
--   Look       = pan.look (garden -> wood -> stone -> crystal ice -> aurora; rebirth keeps it). Not bought since
--                2026-11-17: the Slots levels in Config.pan.lookAtSlots each bring the next one, with its show
--   Trainer    = pan.trainer (snowman -> peppermint ... -> north star: x1 -> x100 Cold Power;
--                rebirth keeps it; TrainingService builds it)
-- (Cold Level was removed with the Cold Power remake, 2026-11-10: the pan keeps every pet frozen.)
-- Prices and levels: Config.pan / Config.panPrice / Config.panMax. Buying follows GunService: decided
-- here, at the stand (the server's own position), price looked up on the server, checked again inside
-- the one DataService.mutate that charges (nothing can run in between), plus a short cooldown.
-- It also puts each pan's Look and its owner's Cold Power on the map (attributes PanLook<i> /
-- PanPower<i> / PanTrainer<i>), so every client draws every pan's look and gauge; the buyer's client then plays the
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
local TutorialService = require(script.Parent.TutorialService)

type Data = DataService.Data

local PanService = {}
local P = Config.pan
local lastBuy: { [Player]: number } = {}
local shownOn: { [Player]: number } = {} -- the plot whose attributes this player set

function PanService.level(d: Data, kind: string): number
	if kind == "slots" then
		return d.upgrades.pen
	end
	if kind == "trainer" then
		return d.pan.trainer
	end
	if kind == "thaw" then
		return d.pan.thaw
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
	-- the owner's Cold Power on their pan's gauge, to 2 digits (it changes several times a second while training)
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
	if map:GetAttribute("PanTrainer" .. plot) ~= d.pan.trainer then
		map:SetAttribute("PanTrainer" .. plot, d.pan.trainer)
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
	local newLook: number? = nil
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
			-- some Slots levels bring the pan's next fence type for free (Config.pan.lookAtSlots)
			local nextLook = x.pan.look + 1
			if P.lookAtSlots[nextLook] and old + 1 >= P.lookAtSlots[nextLook] then
				x.pan.look = nextLook
				newLook = nextLook
			end
		elseif kind == "trainer" then
			x.pan.trainer = old + 1 -- TrainingService rebuilds the pan's trainer from PanTrainer<i>
		elseif kind == "thaw" then
			x.pan.thaw = old + 1 -- every thaw started from now on is shorter
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
	AnalyticsSvc.coinsOut(player, paid, "pan")
	Remotes.fire(player, "Notify", "panUpgraded", { kind = kind, level = old + 1, old = old, price = paid, plot = WorldService.plotOf(player) })
	if newLook then
		Remotes.fire(player, "Notify", "panUpgraded", { kind = "look", level = newLook, old = newLook - 1, price = 0, plot = WorldService.plotOf(player) })
	end
	DataService.mutate(player, function(x)
		x.seenShows.panUpgrade = true
	end)
	TutorialService.did(player, "upgrade") -- the tutorial's first-upgrade step (after the show's Notify, before the save waits on the DataStore)
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
			map:SetAttribute("PanTrainer" .. plot, nil)
		end
	end)
end

return PanService

