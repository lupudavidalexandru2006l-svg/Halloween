--!strict
-- TrainingService (owner 2026-11-10; replaces the sky rink): owns Cold Power training. Every pan has its
-- own trainer in its front right corner (Config.training; TrainingArt draws it), at its owner's level
-- (pan.trainer, a pan upgrade bought at the Pan Upgrades stand: PanService publishes PanTrainer<i> on the
-- map, and this service rebuilds that pan's trainer when it changes; a free pan shows level 1).
-- With its own position of each player, the server works out whether they stand on their own pan's
-- trainer and marks it on the player ("TrainStation" = their pan, 0 = none). There, the gun shoots the
-- target by itself every autoEvery seconds (autoPass with the Full-Speed Auto-Train pass), and each
-- "Train" call (a click / tap / R2 / E on the client) is one more shot, at most clickMax a second. Every
-- shot's Cold Power is decided and saved here (Config.trainGain); every shatterHits shots the target
-- freezes solid and shatters for shatterBonus shots more. The shooter hears each shot (Notify "train":
-- gain, bonus, meter); everyone else sees it through the shooter's "TrainShots" counter, so every
-- client draws every bolt. Nothing is lost and there's no clock: step off and the frost is kept.
-- Lock mode (owner 2026-11-11, Config.training.lock): pressing E on your trainer's prompt (owner
-- 2026-11-13: walking over the pad snapped you in, which was annoying) snaps you to its stand spot facing
-- the target and holds you there ("TrainLocked"; PlayerTracker drops your walk speed to 0) until you
-- jump ("Train" "stop"; the client hops you off the pad). Walking over the pad does nothing.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(script.Parent.Remotes)
local DataService = require(script.Parent.DataService)
local AnalyticsSvc = require(script.Parent.AnalyticsSvc)
local PlayerTracker = require(script.Parent.PlayerTracker)
local CarryService = require(script.Parent.CarryService)
local GunService = require(script.Parent.GunService)
local GearService = require(script.Parent.GearService)
local WorldService = require(script.Parent.WorldService)
local TrainingArt = require(script.Parent.TrainingArt)
local TutorialService = require(script.Parent.TutorialService)
local EventService = require(script.Parent.EventService)

local TrainingService = {}
local T = Config.training

type State = {
	station: number, -- the pan whose trainer they stand on (0 = none; only ever their own)
	ready: boolean, -- they can train there now (hands free, gun out)
	wantGun: boolean, -- they just stepped on: put the gun in their hand once (never again if they put it away)
	hits: number, -- shots toward the next shatter (kept while they step off)
	autoAt: number, -- when the gun's own next shot goes
	clicks: { number }, -- click shots counted in the last second
	gained: number, -- Cold Power since they stepped on (analytics)
	shots: number,
	locked: boolean, -- held at the stand spot until they jump off
}
local states: { [Player]: State } = {}
local folder: Folder
local built: { [number]: { tier: number, f: Folder, admin: number } } = {}

local function hasPass(player: Player, id: string): boolean
	return player:GetAttribute("Pass_" .. id) == true -- set by MonetizationService
end

local function setAttr(inst: Instance, name: string, value: any)
	if inst:GetAttribute(name) ~= value then
		inst:SetAttribute(name, value)
	end
end

local function stateOf(player: Player): State
	local s = states[player]
	if not s then
		s = { station = 0, ready = false, wantGun = false, hits = 0, autoAt = 0, clicks = {}, gained = 0, shots = 0, locked = false }
		states[player] = s
	end
	return s
end

local function tierOf(player: Player): number
	local d = DataService.get(player)
	return if d then math.clamp(d.pan.trainer, 1, #T.stations) else 1
end

-- where you stand on pan i's trainer (standZ from its middle), facing its target, at height y
local function standFrame(i: number, y: number): CFrame
	local p = (Config.trainerFrame(i) * CFrame.new(0, 0, T.standZ)).Position
	local at = Config.trainerTarget(i)
	return CFrame.lookAt(Vector3.new(p.X, y, p.Z), Vector3.new(at.X, y, at.Z))
end

local function setLocked(player: Player, s: State, on: boolean)
	if s.locked == on then
		return
	end
	s.locked = on
	setAttr(player, "TrainLocked", on)
	PlayerTracker.updateSpeed(player) -- 0 while locked
end

-- why this player can't train right now (nil = they can)
local function blocker(player: Player): string?
	if CarryService.count(player) > 0 then -- hands only: frozen pets waiting on the ground don't block training
		return "Bring your pets home first"
	end
	if player:GetAttribute("Tagged") then
		return "no" -- tumbling over
	end
	return nil
end

-- E on your own trainer: the server checks it's your pan, you're at it and your hands are free, then
-- snaps you to the stand spot and locks you in (the client shows the prompt only at your own pan)
local function onPrompt(player: Player, i: number)
	if WorldService.plotOf(player) ~= i or not DataService.isLoaded(player) then
		return
	end
	local s = stateOf(player)
	local pos = PlayerTracker.position(player)
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if s.locked or not pos or not hum or hum.Health <= 0 then
		return
	end
	local c = Config.trainerCentre(i)
	if Vector3.new(pos.X - c.X, 0, pos.Z - c.Z).Magnitude > T.prompt.range + T.padSize[2] / 2 then
		return
	end
	local why = blocker(player)
	if why then
		if why ~= "no" then
			Remotes.fire(player, "Notify", "notYet", { reason = why })
		end
		return
	end
	s.station = i
	s.autoAt = os.clock() + T.autoEvery * 0.5 -- the first shot comes quickly
	s.wantGun = true
	setLocked(player, s, true)
	-- from the ground beside the pad: up onto it, never into it
	local y = if Config.trainerAt(pos) == i then pos.Y else pos.Y + T.padHeight
	PlayerTracker.teleport(player, standFrame(i, y))
	AnalyticsSvc.funnel(player, "first_train")
	TutorialService.did(player, "trainStart") -- Lesson 2: on the pad
end

-- the "Train" E prompt over a trainer's stand spot (drawn by the client's PromptController)
local function addPrompt(f: Folder, i: number)
	local a = Instance.new("Attachment")
	a.Name = "TrainPromptSpot"
	a.Position = (Config.trainerFrame(i) * CFrame.new(0, T.padHeight + T.prompt.lift, T.standZ)).Position
	a.Parent = workspace.Terrain -- an attachment needs a part: Terrain is one that never moves
	f.Destroying:Once(function()
		a:Destroy()
	end)
	local pp = Instance.new("ProximityPrompt")
	pp.Name = "TrainPrompt"
	pp.ActionText = "Train"
	pp.ObjectText = "Cold Power"
	pp.HoldDuration = 0
	pp.MaxActivationDistance = T.prompt.range
	pp.RequiresLineOfSight = false
	pp.Style = Enum.ProximityPromptStyle.Custom
	pp:SetAttribute("Trainer", i)
	pp.Parent = a
	pp.Triggered:Connect(function(player: Player)
		local ok, err = pcall(onPrompt, player, i)
		if not ok then
			warn("[TrainingService] prompt:", err)
		end
	end)
end

-- each pan's trainer at its owner's level (PanTrainer<i>, PanService); a free pan shows level 1
local function syncTrainers()
	local map = workspace:FindFirstChild("Map")
	local admin = EventService.adminMult("trainer") -- the ADMIN TRAINER (AdminService): 1 = none
	for i in Config.world.plots do
		local want = map and map:GetAttribute("PanTrainer" .. i)
		local tier = if typeof(want) == "number" and T.stations[want] then want else 1
		local b = built[i]
		if not b or b.tier ~= tier or b.admin ~= admin or not b.f.Parent then
			if b then
				b.f:Destroy()
			end
			local f = TrainingArt.build(folder, i, tier)
			if admin > 1 then
				TrainingArt.adminDress(f, i, admin)
			end
			addPrompt(f, i)
			built[i] = { tier = tier, f = f, admin = admin }
		end
	end
end

-- one shot: the Cold Power is decided and saved here, then the shooter hears about it
local function shoot(player: Player, s: State, click: boolean)
	local d = DataService.get(player)
	if not d then
		return
	end
	local tier = tierOf(player)
	-- the ADMIN TRAINER (owner 2026-11-18): xN on top of your own best trainer while an admin runs it
	local gain = math.min(Config.coldPower.max, Config.trainGain(tier, GunService.equipped(player), d.rebirths, hasPass(player, "doublePower"))
		* EventService.adminMult("trainer"))
	s.hits += 1
	local bonus = 0
	if s.hits >= T.shatterHits then
		s.hits = 0
		bonus = math.min(Config.coldPower.max, gain * T.shatterBonus)
	end
	local total = gain + bonus
	DataService.mutate(player, function(x)
		x.coldPower = math.min(Config.coldPower.max, x.coldPower + total)
	end)
	if d.coldPower >= Config.need(d.reach + 1) then
		-- enough for the next island: Lesson 2 sends you to its gate (every shot, so power from a gift or a
		-- pack counts on the next one; both calls do nothing after the first time)
		AnalyticsSvc.funnel(player, "first_power_ready")
		TutorialService.did(player, "powerReady")
	end
	s.gained += total
	s.shots += 1
	player:SetAttribute("TrainShots", s.shots) -- every client draws this player's bolt
	Remotes.fire(player, "Notify", "train", { station = s.station, tier = tier, gain = gain, bonus = bonus, meter = s.hits / T.shatterHits, click = click })
end

local function leave(player: Player, s: State)
	setLocked(player, s, false)
	if s.station ~= 0 and s.gained > 0 then
		local d = DataService.get(player)
		AnalyticsSvc.event(player, "train_session", { gain = s.gained, station = T.stations[tierOf(player)].id, level = tostring(Config.powerLevel(if d then d.coldPower else 0)) })
	end
	s.station = 0
	s.ready = false
	s.gained = 0
end

local function tickPlayer(player: Player, now: number)
	local s = stateOf(player)
	local pos = PlayerTracker.position(player)
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	local alive = pos ~= nil and hum ~= nil and hum.Health > 0
	local mine = WorldService.plotOf(player)
	if s.locked then
		-- held at the stand spot; dying, losing the pan or being pulled away (a teleport, a fling) lets go
		local spot = standFrame(s.station, 0).Position
		local away = if pos then Vector3.new(pos.X - spot.X, 0, pos.Z - spot.Z).Magnitude else math.huge
		if not alive or s.station ~= mine or away > T.lock.breakStuds then
			setLocked(player, s, false)
		end
	end
	-- you train only while locked in (E on the prompt, onPrompt); letting go ends it
	local i = if s.locked then s.station else 0
	if i ~= s.station then
		leave(player, s)
	end
	local ready = i ~= 0 and blocker(player) == nil
	if ready and (s.wantGun or s.locked) then
		s.wantGun = false
		if GearService.held(player) ~= "ray" then
			GearService.equipRay(player) -- training is done with the gun: it stays in your hand while locked in
		end
	end
	ready = ready and GearService.held(player) == "ray"
	s.ready = ready
	setAttr(player, "TrainStation", i)
	setAttr(player, "TrainReady", ready)
	setAttr(player, "TrainMeter", s.hits / T.shatterHits)
	if ready and now >= s.autoAt then
		s.autoAt = now + (if hasPass(player, "autoTrain") then T.autoPass else T.autoEvery)
		shoot(player, s, false)
	end
end

-- a click shot: counted only on your trainer when you can train, at most clickMax a second
local function onTrain(player: Player, action: any)
	if action == "stop" then -- they jumped off: let go and stay free until they step off the pad
		local s = states[player]
		if s and s.locked then
			setLocked(player, s, false)
		end
		return
	end
	if action ~= "shot" then
		return
	end
	local s = states[player]
	if not s or s.station == 0 or not s.ready then
		return
	end
	local now = os.clock()
	local kept: { number } = {}
	for _, t in s.clicks do
		if now - t < 1 then
			table.insert(kept, t)
		end
	end
	s.clicks = kept
	if #kept >= T.clickMax then
		return -- faster than counted: dropped quietly
	end
	table.insert(kept, now)
	shoot(player, s, true)
end

function TrainingService.Init()
	folder = Instance.new("Folder")
	folder.Name = "Trainers"
	folder.Parent = workspace
end

function TrainingService.Start()
	Remotes.on("Train", onTrain)
	Players.PlayerRemoving:Connect(function(p)
		local s = states[p]
		if s then
			leave(p, s)
		end
		states[p] = nil
	end)
	task.spawn(function()
		while true do
			local ok, err = pcall(syncTrainers)
			if not ok then
				warn("[TrainingService] trainers:", err)
			end
			local now = os.clock()
			for _, p in Players:GetPlayers() do
				if DataService.isLoaded(p) then
					local ok2, err2 = pcall(tickPlayer, p, now)
					if not ok2 then
						warn("[TrainingService] tick:", err2)
					end
				end
			end
			task.wait(T.tickSeconds)
		end
	end)
end

return TrainingService
