--!strict
-- GearService (Round 5): what each player holds from the hotbar ("ray", "gel" or "none": a session
-- choice, the ray by default, published as the "Held" attribute every client draws from), buying gear
-- at the Equipment Booth's Gear tab (saved in d.gear), and Slow Gel: a thrown puddle where pets and
-- Heat Critters move at Config.gel.slow. The server checks the throw's distance and the cooldown.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Theme = require(ReplicatedStorage.Shared.Theme)
local Remotes = require(script.Parent.Remotes)
local DataService = require(script.Parent.DataService)
local PlayerTracker = require(script.Parent.PlayerTracker)
local AnalyticsSvc = require(script.Parent.AnalyticsSvc)
local TutorialService = require(script.Parent.TutorialService)

local GearService = {}
local G = Config.gel
local held: { [Player]: string } = {}
local lastThrow: { [Player]: number } = {}
local lastBuy: { [Player]: number } = {}
local stowed: { [Player]: boolean } = {} -- the game put the ray away (after a freeze); it brings it back
-- a cube is in your hands (CarryService): nothing on the hotbar can come out until it's home or gone
-- (owner 2026-11-12: you could pick the ray back up and freeze more pets on the way home)
local locked: { [Player]: boolean } = {}
type Puddle = { pos: Vector3, untilT: number, part: BasePart }
local puddles: { Puddle } = {}
local folder: Folder
local changed = Instance.new("BindableEvent")
GearService.Changed = changed.Event -- (player) what they hold changed

function GearService.held(player: Player): string
	return held[player] or "ray"
end

-- Slow Gel was removed (owner 2026-11-17): the ray, nothing, or Frost Bombs once bought (2026-11-19, BombService)
local function owns(player: Player, id: string): boolean
	if id == "bomb" then
		local d = DataService.get(player)
		local lv = d and d.gear.frost_bombs
		return typeof(lv) == "number" and lv > 0
	end
	return id == "ray" or id == "none"
end

local function setHeld(player: Player, id: string)
	if held[player] == id then
		return
	end
	held[player] = id
	player:SetAttribute("Held", id)
	changed:Fire(player)
end

-- how much slower a pet or critter standing here moves (1 = not in any gel)
function GearService.slowAt(pos: Vector3): number
	for _, p in puddles do
		if (Vector3.new(pos.X - p.pos.X, 0, pos.Z - p.pos.Z)).Magnitude <= G.radius then
			return G.slow
		end
	end
	return 1
end

-- FreezeService: you just froze a pet, so the ray goes away by itself (owner 2026-11-05)
function GearService.stowRay(player: Player)
	if GearService.held(player) == "ray" then
		stowed[player] = true
		setHeld(player, "none")
	end
end

-- ...and comes back out once you carry nothing (banked, melted, knocked loose), unless the player
-- picked something on the hotbar since
function GearService.unstowRay(player: Player)
	if stowed[player] then
		stowed[player] = nil
		if GearService.held(player) == "none" then
			setHeld(player, "ray")
		end
	end
end

-- CarryService: your hands are full (on) or empty again (off). The client hides the hotbar from
-- "GunLocked"; the server refuses SetGear while it's on, so a faked call can't bring the ray out
function GearService.setLocked(player: Player, on: boolean)
	if (locked[player] == true) == on then
		return
	end
	locked[player] = if on then true else nil
	player:SetAttribute("GunLocked", on)
	if on and GearService.held(player) ~= "none" then
		stowed[player] = true -- it comes back out by itself once your hands are empty (FreezeService)
		setHeld(player, "none")
	end
end

-- TrainingService: training is done with the gun, so stepping onto a station puts it in your hand
function GearService.equipRay(player: Player)
	if locked[player] then
		return
	end
	stowed[player] = nil
	setHeld(player, "ray")
end

function GearService.isStowed(player: Player): boolean
	return stowed[player] == true
end

local function onSetGear(player: Player, id: any)
	if typeof(id) ~= "string" or (id ~= "ray" and id ~= "none" and id ~= "bomb") then
		return
	end
	if locked[player] and id ~= "none" then
		Remotes.notYet(player, "Bring your pet home first", "hotbar")
		return
	end
	stowed[player] = nil -- the player's own choice wins
	if not owns(player, id) then
		Remotes.notYet(player, "Buy it at the Equipment Booth", "hotbar")
		return
	end
	setHeld(player, id)
end

local function onThrow(player: Player, at: any)
	if typeof(at) ~= "Vector3" then
		return
	end
	for _, v in { at.X, at.Y, at.Z } do
		if v ~= v or math.abs(v) > 1e5 then
			return -- NaN or far off the map: a broken or faked throw
		end
	end
	local pos = PlayerTracker.position(player)
	if not pos or GearService.held(player) ~= "gel" or not owns(player, "gel") then
		return
	end
	local now = os.clock()
	if now - (lastThrow[player] or -math.huge) < G.cooldown then
		return
	end
	-- never farther than the throw's reach (a far click lands at the edge of it)
	local flat = Vector3.new(at.X - pos.X, 0, at.Z - pos.Z)
	if flat.Magnitude > G.throwRange then
		flat = flat.Unit * G.throwRange
	end
	lastThrow[player] = now
	local land = Vector3.new(pos.X + flat.X, 0, pos.Z + flat.Z)
	local part = Instance.new("Part")
	part.Name = "GelPuddle"
	part.Shape = Enum.PartType.Cylinder
	part.Size = Vector3.new(0.3, G.radius * 2, G.radius * 2)
	part.CFrame = CFrame.new(land + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, 0, math.pi / 2)
	part.Color = Theme.round5.gel
	part.Material = Enum.Material.Glass
	part.Transparency = 0.35
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part:SetAttribute("From", pos)
	part:SetAttribute("Until", workspace:GetServerTimeNow() + G.seconds)
	part.Parent = folder
	table.insert(puddles, { pos = land, untilT = now + G.seconds, part = part })
	Remotes.fire(player, "Notify", "gelThrown", { cooldown = G.cooldown })
end

local function boothPos(): Vector3?
	for _, b in Config.world.booths do
		if b.id == "equipment" then
			return b.pos
		end
	end
	return nil
end

-- the always-on gear (Config.gear, reworked 2026-11-17): one level per press at the booth, up to
-- Config.gearMax. The price comes from the server's own level and is checked again inside the one change
-- that charges; the GearLv_<key> / Gear_<key> attributes (publish) switch the effect on in the other services
local function level(d: any, key: string): number
	local v = d.gear[key]
	return if typeof(v) == "number" then v else 0
end

local function publish(player: Player, key: string, lv: number)
	player:SetAttribute("GearLv_" .. key, lv)
	player:SetAttribute("Gear_" .. key, lv > 0)
end

local function buyItem(player: Player, item: Config.GearItem)
	local d = DataService.get(player)
	local p, b = PlayerTracker.position(player), boothPos()
	if not d or not p or not b or (Vector3.new(p.X, 0, p.Z) - Vector3.new(b.X, 0, b.Z)).Magnitude > Config.guns.boothRange then
		return
	end
	local now = os.clock()
	if now - (lastBuy[player] or -math.huge) < Config.guns.buyCooldown then
		return
	end
	local old = level(d, item.key)
	local price = Config.gearPrice(item.key, old)
	if not price then
		Remotes.notYet(player, "Max level", "gear")
		return
	end
	if d.coins < price then
		Remotes.notYet(player, `Need {Config.coinText(price - d.coins)} more`, "gear")
		return
	end
	lastBuy[player] = now
	local bought = false
	DataService.mutate(player, function(x)
		if level(x, item.key) ~= old or x.coins < price then
			return
		end
		x.coins -= price
		x.gear[item.key] = old + 1
		bought = true
	end)
	if bought then
		AnalyticsSvc.funnel(player, "first_coins_spent")
		AnalyticsSvc.coinsOut(player, price, "gear")
		DataService.saveNow(player)
		publish(player, item.key, old + 1)
		PlayerTracker.updateSpeed(player) -- Frost Boots
		Remotes.fire(player, "Notify", "gearBought", { key = item.key, name = item.name, level = old + 1 })
		TutorialService.did(player, "gearBuy") -- the tutorial's gear step (2026-11-18)
	end
end

local function onBuy(player: Player, key: any)
	if typeof(key) ~= "string" then
		return
	end
	local item = Config.gearItem(key) -- anything else (Slow Gel, removed 2026-11-17) is refused
	if item then
		buyItem(player, item)
	end
end

local function setOwned(player: Player)
	local d = DataService.get(player)
	if d then
		player:SetAttribute("GearGel", false) -- Slow Gel removed 2026-11-17
		player:SetAttribute("GearBomb", owns(player, "bomb")) -- hotbar slot 2 (2026-11-19)
		for _, g in Config.gear do
			publish(player, g.key, level(d, g.key))
		end
		PlayerTracker.updateSpeed(player) -- a rejoin or a tester change: the boots' speed comes back
		if held[player] == "gel" and not d.gear.gel then
			setHeld(player, "ray")
		end
	end
end

function GearService.Init()
	folder = Instance.new("Folder")
	folder.Name = "GelPuddles"
	folder.Parent = workspace
end

function GearService.Start()
	Remotes.on("SetGear", onSetGear)
	Remotes.on("ThrowGel", onThrow)
	Remotes.on("BuyGear", onBuy)
	DataService.Loaded:Connect(function(player: Player)
		-- a saved Super Freeze cube may already be back in your hands (CarryService): then the ray waits
		stowed[player] = if locked[player] then true else nil
		setHeld(player, if locked[player] then "none" else "ray")
		setOwned(player)
	end)
	DataService.Changed:Connect(setOwned)
	Players.PlayerRemoving:Connect(function(p)
		held[p] = nil
		stowed[p] = nil
		locked[p] = nil
		lastThrow[p] = nil
		lastBuy[p] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(0.25)
			local now = os.clock()
			for i = #puddles, 1, -1 do
				if now >= puddles[i].untilT then
					puddles[i].part:Destroy()
					table.remove(puddles, i)
				end
			end
		end
	end)
end

return GearService
