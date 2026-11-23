--!strict
-- TutorialService: the one owner of each player's tutorial progress, saved in their data as
-- tutorial = { step, done, gift, paid } (Config.tutorial). The game's services report what a player really did
-- (TutorialService.did, called where the server decides it: FreezeService, CarryService, PenService,
-- PanService); this moves the step on and the client shows it (TutorialController). The client
-- only sends intent through the Tutorial remote: "next" on a talk step, "skip", "replay" (Code Rules 6).
-- Each player's progress is their own, so any number of players can be on different steps at once.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local DataService = require(script.Parent.DataService)
local Remotes = require(script.Parent.Remotes)
local AnalyticsSvc = require(script.Parent.AnalyticsSvc)

local TutorialService = {}
local T = Config.tutorial
local lastNext: { [Player]: number } = {}

-- a Pan Upgrade's level in a save (the same places PanService keeps them)
local function panLevel(d: any, kind: string): number
	if kind == "slots" then
		return d.upgrades.pen or 1
	elseif kind == "thaw" then
		return d.pan.thaw or 1
	end
	return 1
end

local function indexOf(id: string): number?
	for i, s in T.steps do
		if s.id == id then
			return i
		end
	end
	return nil
end

local autoAdvance: (Player) -> ()

-- true while a new player is on the first island lesson (zap .. carry home): their cube never melts or wakes up
-- and Night doesn't send them home (QA PT-02 / PT-03, 2026-11-19: the tutorial pet melted away when a 7-year-old
-- stopped to look around, and Night pulled them home ~90 s in)
function TutorialService.learning(player: Player): boolean
	local d = DataService.get(player)
	if not d or not d.tutorial or d.tutorial.done then
		return false
	end
	return (d.tutorial.step or 1) <= (indexOf("carry") or 0)
end

-- why: "did" (an action), "next", "skip", "replay"
local function setStep(player: Player, step: number, done: boolean, why: string)
	step = math.clamp(step, 1, #T.steps)
	local gift, reward = 0, 0
	local changed = DataService.mutate(player, function(d)
		d.tutorial.step = step
		d.tutorial.done = done
		-- a lesson's last step: its reward, once per save (the TUTORIAL COMPLETE card shows it). Only when the
		-- player got there (an action or Next), never on a skip or a replay's restart
		local r = T.steps[step]
		if not done and r and r.reward and (why == "did" or why == "next") then
			d.tutorial.paid = d.tutorial.paid or {}
			local paid = d.tutorial.paid :: { [string]: boolean }
			if not paid[r.id] then
				paid[r.id] = true
				reward = r.reward
				d.coins = math.min(d.coins + reward, 1e15)
			end
		end
		-- the upgrade step: coins topped up to the price of that upgrade's next level, once per save (a
		-- replay can't farm it), so the first upgrade is bought right away (Game Psychology: endowed progress)
		local s = T.steps[step]
		-- the gear step (2026-11-18): coins topped up to that gear's next level, once per save
		if not done and s.gearGift then
			d.tutorial.paid = d.tutorial.paid or {}
			local paid = d.tutorial.paid :: { [string]: boolean }
			if not paid.gearGift then
				paid.gearGift = true
				local lv = d.gear[s.gearGift]
				local price = Config.gearPrice(s.gearGift, if typeof(lv) == "number" then lv else 0)
				if price and d.coins < price then
					gift = price - math.floor(d.coins)
					d.coins += gift
				end
			end
		end
		if not done and s.gift and not d.tutorial.gift then
			local price = Config.panPrice(s.gift, panLevel(d, s.gift), d.rebirths)
			d.tutorial.gift = true
			if price and d.coins < price then
				gift = price - math.floor(d.coins)
				d.coins += gift
			end
		end
	end)
	if not changed then
		return
	end
	AnalyticsSvc.coinsIn(player, gift + reward, "tutorial")
	if why == "did" or why == "next" then
		local st = T.steps[step]
		-- QA CA-01: the last step was logged as you reached it; closing it (done) doesn't send it again
		if not done then
			AnalyticsSvc.tutorialStep(player, step, if st then st.id else "?")
		end
		-- funnel step 11 (QA 2026-11-19: it was never sent): the Cold Power lesson starts at the "peek" step
		if st and st.id == "peek" then
			AnalyticsSvc.funnel(player, "lesson2_start")
		end
	elseif why == "skip" then
		local st = T.steps[step]
		AnalyticsSvc.tutorialStep(player, #T.steps + 1, "skipped_at_" .. (if st then st.id else "?"))
	end
	Remotes.fire(player, "Notify", "tutorial", { step = step, done = done, why = why, gift = if gift > 0 then gift else nil, reward = if reward > 0 then reward else nil })
	if done or why == "replay" or gift > 0 or reward > 0 then
		task.spawn(DataService.saveNow, player) -- finishing, skipping or a gift is remembered at once, not at the next autosave
	end
	if why ~= "skip" and why ~= "replay" and done then
		AnalyticsSvc.funnel(player, "tutorial_done") -- the whole run, catch to the next island
	end
	if not done then
		autoAdvance(player)
	end
end

-- the Cold Power steps: one that's already true moves on by itself (power from the Free Gift or a pack;
-- island 2 opened some other way), so the tutorial never asks for something you've done
autoAdvance = function(player: Player)
	local d = DataService.get(player)
	if not d or d.tutorial.done then
		return
	end
	local i = d.tutorial.step
	local s = T.steps[i]
	if not s then
		return
	end
	local ready = d.coldPower >= Config.need(d.reach + 1)
	if s.on == "gateOpen" and d.reach >= 2 then
		setStep(player, i + 1, i + 1 > #T.steps, "did")
	elseif (s.on == "trainStart" or s.on == "powerReady") and (ready or d.reach >= 2) then
		setStep(player, indexOf("gate") or i + 1, false, "did")
	end
end

-- a player did something the tutorial teaches. The current step or any later one counts, so a kid who
-- already froze a pet while aiming goes straight on to picking it up. An `only` step counts only while
-- it's the current one (a Pan Upgrade or a training session mid-catch skips nothing).
function TutorialService.did(player: Player, action: string)
	if not T.actions[action] then
		return
	end
	local d = DataService.get(player)
	if not d or d.tutorial.done then
		return
	end
	for i = d.tutorial.step, #T.steps do
		local s = T.steps[i]
		if s.on == action and (i == d.tutorial.step or not s.only) then
			local nextStep = i + 1
			setStep(player, nextStep, nextStep > #T.steps, "did")
			return
		end
	end
end

local function onTutorial(player: Player, what: any)
	if typeof(what) ~= "string" then
		return
	end
	local d = DataService.get(player)
	if not d then
		return
	end
	local tu = d.tutorial
	if what == "next" then
		-- only a talk step moves on with Next; an action step needs the action itself
		local step = T.steps[tu.step]
		local now = os.clock()
		if tu.done or not step or step.on ~= "next" or now - (lastNext[player] or -math.huge) < T.nextCooldown then
			return
		end
		lastNext[player] = now
		setStep(player, tu.step + 1, tu.step + 1 > #T.steps, "next")
	elseif what == "skip" then
		if not tu.done then
			setStep(player, tu.step, true, "skip")
		end
	elseif what == "replay" then
		if tu.done then
			setStep(player, 1, false, "replay")
		end
	end
end

function TutorialService.Init() end

function TutorialService.Start()
	Remotes.on("Tutorial", onTutorial)
	Players.PlayerRemoving:Connect(function(p)
		lastNext[p] = nil
	end)
end

return TutorialService
