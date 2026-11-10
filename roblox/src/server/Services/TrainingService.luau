--!strict
-- TrainingService (Cold Power remake, 2026-11-10): owns the Training Rink, where Cold Power comes from.
-- Every pan slot has its own rink floating in the sky (RinkArt, Config.rink). The door is the rink
-- booth in the hub: its prompt sends "Rink enter", and this service checks the player really stands
-- there, carries nothing, and takes them up. A wave is Config.rink.waveSize fire sprites that hop in
-- over the front arc toward the ice sculpture. No clock: the wave ends when every sprite is frozen or
-- has reached the sculpture (it runs off; nothing is lost).
-- The rink is played with the ray: a sprite is one more FreezeService target (like a Heat Critter),
-- so the client's "Aim" and the server's own range check are the ones every shot already goes
-- through. Everything is decided here: which sprites exist, where they are, their ice meters, the
-- combo (sprites frozen in a row; one that gets through resets it), the gun's heat, Auto, and the
-- Cold Power each one gives (Config.rinkGain). Clients only draw: sprite roots are invisible parts in
-- workspace.RinkSprites (attributes SpriteId, OwnerUserId, Kind, Golden, Meter), and the HUD reads the
-- player's InRink / RinkLeft / RinkCombo / RinkAuto / RinkLevel / RinkState attributes.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(script.Parent.Remotes)
local DataService = require(script.Parent.DataService)
local AnalyticsSvc = require(script.Parent.AnalyticsSvc)
local PlayerTracker = require(script.Parent.PlayerTracker)
local WorldService = require(script.Parent.WorldService)
local CarryService = require(script.Parent.CarryService)
local FreezeService = require(script.Parent.FreezeService)
local GunService = require(script.Parent.GunService)
local GearService = require(script.Parent.GearService)
local RinkArt = require(script.Parent.RinkArt)

local TrainingService = {}
local R = Config.rink
local HB = Config.guns.heatBar
local FRONT = Vector3.zAxis -- the sprites' side of every rink (RinkArt)

-- dist = studs from the sculpture's middle; angle = radians from FRONT
type Sprite = { id: string, root: BasePart, kind: string, golden: boolean, meter: number, dist: number, angle: number, pushedAt: number }
type Session = {
	player: Player, index: number, centre: Vector3, level: number,
	state: string, -- "entering" (being taken up) | "wave" | "result" (the wave is over: AGAIN, or Auto restarts it)
	toSpawn: number, alive: { [string]: Sprite }, aliveCount: number, nextSpawn: number,
	hits: number, -- sprites frozen in a row by hand (the combo)
	gained: number, frozen: number, auto: boolean, restartAt: number?,
	autoTarget: string?, -- the sprite Auto is freezing (it stays on one until it's done)
	conns: { RBXScriptConnection },
}
local sessions: { [Player]: Session } = {}
local owners: { [string]: Session } = {} -- sprite id -> its session
local lastEnter: { [Player]: number } = {}
local rinks: Folder
local spritesFolder: Folder
local rng = Random.new()
local nextId = 0

function TrainingService.inRink(player: Player): boolean
	return sessions[player] ~= nil
end

-- game passes are checked with Roblox by MonetizationService, which marks the player (server-set attributes)
local function hasPass(player: Player, id: string): boolean
	return player:GetAttribute("Pass_" .. id) == true
end

local function boothPos(): Vector3?
	for _, b in Config.world.booths do
		if b.id == "rink" then
			return b.pos
		end
	end
	return nil
end

local function setAttr(inst: Instance, name: string, value: any)
	if inst:GetAttribute(name) ~= value then
		inst:SetAttribute(name, value)
	end
end

local function comboMult(s: Session): number
	return 1 + math.min(s.hits * R.combo.perHit, R.combo.max - 1)
end

local function publish(s: Session)
	local p = s.player
	setAttr(p, "RinkLeft", s.toSpawn + s.aliveCount)
	setAttr(p, "RinkCombo", math.round(comboMult(s) * 10) / 10)
	setAttr(p, "RinkAuto", s.auto)
	setAttr(p, "RinkLevel", s.level)
	setAttr(p, "RinkState", s.state)
end

local function spritePos(s: Session, sp: Sprite): Vector3
	local size = R.kinds[sp.kind].size
	return s.centre + Vector3.new(math.sin(sp.angle) * sp.dist, size / 2, math.cos(sp.angle) * sp.dist)
end

local function setMeter(sp: Sprite, m: number, by: Player?)
	sp.meter = m
	local step = Config.aim.step
	local shown = if m <= 0 then 0 else math.max(step, math.floor(m / step) * step)
	setAttr(sp.root, "Meter", shown)
	setAttr(sp.root, "AimedBy", if by then by.UserId else 0)
end

local function removeSprite(s: Session, sp: Sprite)
	if s.alive[sp.id] then
		s.alive[sp.id] = nil
		s.aliveCount -= 1
	end
	owners[sp.id] = nil
	sp.root:Destroy()
end

local function spawnSprite(s: Session)
	local kinds: { string } = {}
	local total = 0
	for _, name in R.kindOrder do
		local k = R.kinds[name]
		if k.fromLevel <= s.level then
			total += k.weight
			table.insert(kinds, name)
		end
	end
	local roll, kind = rng:NextNumber() * total, kinds[1]
	for _, name in kinds do
		roll -= R.kinds[name].weight
		if roll <= 0 then
			kind = name
			break
		end
	end
	local golden = rng:NextNumber() < R.goldenChance
	if golden then
		kind = "small" -- a golden sprite is a small one worth more
	end
	nextId += 1
	local id = "s" .. nextId
	local size = R.kinds[kind].size
	local root = Instance.new("Part")
	root.Name = "SpriteRoot"
	root.Size = Vector3.new(size, size, size)
	root.Anchored = true
	root.CanCollide = false
	root.CanTouch = false
	root.Transparency = 1
	local a = Instance.new("Attachment") -- the beam lands here
	a.Name = "Aim"
	a.Parent = root
	local half = math.rad(R.arc / 2)
	local sp: Sprite = { id = id, root = root, kind = kind, golden = golden, meter = 0, dist = R.radius - 2, angle = rng:NextNumber(-half, half), pushedAt = 0 }
	root.CFrame = CFrame.new(spritePos(s, sp))
	root:SetAttribute("SpriteId", id)
	root:SetAttribute("OwnerUserId", s.player.UserId)
	root:SetAttribute("Kind", kind)
	root:SetAttribute("Golden", golden)
	root:SetAttribute("Meter", 0)
	root:SetAttribute("AimedBy", 0)
	s.alive[id] = sp
	s.aliveCount += 1
	owners[id] = s
	root.Parent = spritesFolder
end

local function startWave(s: Session)
	local d = DataService.get(s.player)
	s.level = Config.rinkLevel(if d then d.coldPower else 0) -- fixed for the wave: it grows with you
	s.state = "wave"
	s.toSpawn = R.waveSize
	s.hits = 0
	s.gained = 0
	s.frozen = 0
	s.restartAt = nil
	s.nextSpawn = os.clock() + R.firstSpawn
	publish(s)
	Remotes.fire(s.player, "Notify", "rink", { what = "wave", level = s.level, total = R.waveSize })
end

local function finishWave(s: Session, now: number)
	s.state = "result"
	if s.auto then
		s.restartAt = now + R.autoRestart
	end
	publish(s)
	Remotes.fire(s.player, "Notify", "rink", { what = "done", gained = s.gained, frozen = s.frozen, total = R.waveSize, auto = s.auto })
	AnalyticsSvc.event(s.player, "rink_wave", { gain = s.gained, level = tostring(s.level) })
end

-- a sprite's ice is full: the Cold Power is decided and stored here, then the client hears about it
local function freezeSprite(s: Session, sp: Sprite, auto: boolean)
	local player = s.player
	local d = DataService.get(player)
	if not d then
		return
	end
	local combo = if auto then 1 else comboMult(s) -- Auto never builds or uses a combo
	local gain = Config.rinkGain(sp.kind, sp.golden, s.level, GunService.equipped(player), d.rebirths, combo, hasPass(player, "doublePower"))
	DataService.mutate(player, function(x)
		x.coldPower = math.min(Config.coldPower.max, x.coldPower + gain)
	end)
	if not auto then
		s.hits += 1
	end
	s.gained += gain
	s.frozen += 1
	local at = sp.root.Position
	local id, golden, kind = sp.id, sp.golden, sp.kind
	removeSprite(s, sp)
	Remotes.fire(player, "Notify", "rink", { what = "gain", id = id, gain = gain, combo = comboMult(s), at = at, golden = golden, kind = kind })
end

-- `seconds` of ray on a sprite (by hand, or Auto's share of the tick)
local function push(s: Session, sp: Sprite, seconds: number, auto: boolean)
	sp.pushedAt = os.clock()
	local m = sp.meter + seconds / R.kinds[sp.kind].hold
	if m >= 1 then
		freezeSprite(s, sp, auto)
	else
		setMeter(sp, m, if auto then nil else s.player)
	end
end

local function endSession(player: Player, back: boolean)
	local s = sessions[player]
	if not s then
		return
	end
	sessions[player] = nil
	for _, c in s.conns do
		c:Disconnect()
	end
	for id, sp in s.alive do
		owners[id] = nil
		sp.root:Destroy()
	end
	s.alive = {}
	s.aliveCount = 0
	if not player.Parent then
		return -- they left the game: nothing more to tell them
	end
	FreezeService.stopAim(player)
	for _, name in { "RinkLeft", "RinkCombo", "RinkAuto", "RinkLevel", "RinkState", "RinkIndex" } do
		player:SetAttribute(name, nil)
	end
	player:SetAttribute("InRink", false)
	Remotes.fire(player, "Notify", "rink", { what = "leave" })
	local booth = boothPos()
	if back and booth then -- back in front of the door, facing the plaza
		local at = booth + Vector3.new(0, 4, -10)
		PlayerTracker.teleport(player, CFrame.lookAt(at, at - Vector3.zAxis))
	end
end

local function enter(player: Player)
	local d = DataService.get(player)
	if not d or sessions[player] then
		return
	end
	local now = os.clock()
	if now - (lastEnter[player] or -math.huge) < R.cooldown then
		return -- spam: dropped quietly
	end
	lastEnter[player] = now
	local booth, pos = boothPos(), PlayerTracker.position(player)
	if not booth or not pos or (Vector3.new(pos.X, 0, pos.Z) - Vector3.new(booth.X, 0, booth.Z)).Magnitude > R.boothRange then
		return -- not at the door (the server's own position)
	end
	local character = player.Character
	local hum = character and character:FindFirstChildOfClass("Humanoid")
	local index = WorldService.plotOf(player)
	if not hum or hum.Health <= 0 or not index then
		return
	end
	if CarryService.load(player) > 0 then
		Remotes.notYet(player, "Bring your pets home first", "rink")
		return
	end
	local centre = Config.rinkCentre(index)
	local s: Session = {
		player = player, index = index, centre = centre, level = 0, state = "entering",
		toSpawn = 0, alive = {}, aliveCount = 0, nextSpawn = 0,
		hits = 0, gained = 0, frozen = 0, auto = false, restartAt = nil, autoTarget = nil, conns = {},
	}
	sessions[player] = s -- before anything yields, so a second "enter" is refused
	pcall(function()
		player:RequestStreamAroundAsync(centre, 4) -- the rink is far up: have it there before they arrive
	end)
	if sessions[player] ~= s then
		return -- they left meanwhile
	end
	local stand = centre + FRONT * R.playerAt + Vector3.new(0, 3, 0)
	if hum.Health <= 0 or not PlayerTracker.teleport(player, CFrame.lookAt(stand, stand + FRONT)) then
		sessions[player] = nil
		return
	end
	GearService.equipRay(player)
	table.insert(s.conns, hum.Died:Connect(function()
		endSession(player, false) -- they respawn in the hub by themselves; what they trained is kept
	end))
	table.insert(s.conns, player.CharacterAdded:Connect(function()
		endSession(player, false)
	end))
	player:SetAttribute("RinkIndex", index)
	player:SetAttribute("InRink", true)
	Remotes.fire(player, "Notify", "rink", { what = "enter", index = index })
	startWave(s)
end

local function tickSession(s: Session, dt: number, now: number)
	if s.state == "entering" then
		return
	end
	local pos = PlayerTracker.position(s.player)
	if pos and (pos - s.centre).Magnitude > R.radius + R.leaveAt then
		endSession(s.player, false) -- somewhere else (a tester teleport, a fall): the rink is over
		return
	end
	if s.state == "result" then
		if s.auto and s.restartAt and now >= s.restartAt then
			startWave(s)
		end
		return
	end
	if s.toSpawn > 0 and s.aliveCount < R.maxAlive and now >= s.nextSpawn then
		s.toSpawn -= 1
		s.nextSpawn = now + R.spawnEvery
		spawnSprite(s)
	end
	local speed = math.min(R.speed + R.speedPerLevel * s.level, R.speedMax)
	for _, sp in s.alive do
		sp.dist -= speed * dt
		if sp.dist <= R.sculptureRadius then
			-- it reached the sculpture: it runs off, you lose nothing, the combo starts over
			local id = sp.id
			removeSprite(s, sp)
			s.hits = 0
			Remotes.fire(s.player, "Notify", "rink", { what = "escaped", id = id })
			continue
		end
		sp.root.CFrame = CFrame.new(spritePos(s, sp))
		if sp.meter > 0 and now - sp.pushedAt > R.thawAfter then
			setMeter(sp, math.max(0, sp.meter - R.thawPerSecond * dt), nil)
		end
	end
	if s.auto then
		-- Auto stays on one sprite until it's frozen. It picks the one closest to the sculpture that it
		-- can still finish in time (switching to whichever is nearest froze almost none at the free speed).
		local rate = if hasPass(s.player, "autoTrain") then R.autoPass else R.autoFree
		local target = if s.autoTarget then s.alive[s.autoTarget] else nil
		if not target then
			for _, sp in s.alive do
				local timeLeft = (sp.dist - R.sculptureRadius) / speed
				local needs = (1 - sp.meter) * R.kinds[sp.kind].hold / rate
				if needs <= timeLeft and (not target or sp.dist < target.dist) then
					target = sp
				end
			end
			s.autoTarget = if target then target.id else nil
		end
		if target then
			push(s, target, dt * rate, true)
		end
	end
	if s.toSpawn == 0 and s.aliveCount == 0 then
		finishWave(s, now)
		return
	end
	publish(s)
end

local function onRink(player: Player, action: any, arg: any)
	if action == "enter" then
		enter(player)
		return
	end
	local s = sessions[player]
	if not s or s.state == "entering" then
		return
	end
	if action == "leave" then
		endSession(player, true)
	elseif action == "again" then
		if s.state == "result" then
			startWave(s)
		end
	elseif action == "auto" and typeof(arg) == "boolean" then
		s.auto = arg
		s.restartAt = if arg and s.state == "result" then os.clock() + R.autoRestart else nil
		publish(s)
	end
end

function TrainingService.Init()
	rinks = Instance.new("Folder")
	rinks.Name = "Rinks"
	rinks.Parent = workspace
	spritesFolder = Instance.new("Folder")
	spritesFolder.Name = "RinkSprites"
	spritesFolder.Parent = workspace
end

function TrainingService.Start()
	for i in Config.world.plots do
		RinkArt.build(rinks, Config.rinkCentre(i), i)
	end
	FreezeService.registerTarget("sprite", {
		pos = function(id: string): Vector3?
			local s = owners[id]
			local sp = s and s.alive[id]
			return if sp then sp.root.Position else nil
		end,
		-- only your own sprites, only in your own running wave, and not while the gun steams
		canAim = function(player: Player, id: string): boolean
			local s = owners[id]
			return s ~= nil and s.player == player and s.state == "wave" and s.alive[id] ~= nil and not GunService.steaming(player)
		end,
		tick = function(player: Player, id: string, dt: number, _gun: number)
			local s = owners[id]
			local sp = s and s.alive[id]
			if not s or not sp or s.player ~= player then
				return
			end
			-- firing nonstop heats the gun here too: practice for the hot islands
			if GunService.addHeat(player, dt / HB.rinkSeconds) then
				Remotes.notYet(player, "Gun too hot!", "pet")
				FreezeService.stopAim(player)
				return
			end
			push(s, sp, dt, false)
		end,
	})
	Remotes.on("Rink", onRink)
	Players.PlayerRemoving:Connect(function(p)
		endSession(p, false)
		lastEnter[p] = nil
	end)
	task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(R.tickSeconds)
			local now = os.clock()
			local dt = now - last
			last = now
			for _, s in sessions do
				local ok, err = pcall(tickSession, s, dt, now)
				if not ok then
					warn("[TrainingService] tick:", err)
				end
			end
		end
	end)
end

return TrainingService
