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

local GearService = {}
local G = Config.gel
local held: { [Player]: string } = {}
local lastThrow: { [Player]: number } = {}
local lastBuy: { [Player]: number } = {}
local stowed: { [Player]: boolean } = {} -- the game put the ray away (after a freeze); it brings it back
type Puddle = { pos: Vector3, untilT: number, part: BasePart }
local puddles: { Puddle } = {}
local folder: Folder
local changed = Instance.new("BindableEvent")
GearService.Changed = changed.Event -- (player) what they hold changed

function GearService.held(player: Player): string
	return held[player] or "ray"
end

local function owns(player: Player, id: string): boolean
	if id == "ray" or id == "none" then
		return true
	end
	local d = DataService.get(player)
	return d ~= nil and id == "gel" and d.gear.gel
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

function GearService.isStowed(player: Player): boolean
	return stowed[player] == true
end

local function onSetGear(player: Player, id: any)
	if typeof(id) ~= "string" or (id ~= "ray" and id ~= "gel" and id ~= "none") then
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

local function onBuy(player: Player, key: any)
	if key ~= "gel" then
		return
	end
	local d = DataService.get(player)
	local p, b = PlayerTracker.position(player), boothPos()
	if not d or not p or not b or (Vector3.new(p.X, 0, p.Z) - Vector3.new(b.X, 0, b.Z)).Magnitude > Config.guns.boothRange then
		return
	end
	local now = os.clock()
	if now - (lastBuy[player] or -math.huge) < Config.guns.buyCooldown or d.gear.gel then
		return
	end
	if d.coins < G.price then
		Remotes.notYet(player, `Need {math.ceil(G.price - d.coins)} more`, "gear")
		return
	end
	lastBuy[player] = now
	local bought = false
	DataService.mutate(player, function(x)
		if x.gear.gel or x.coins < G.price then -- checked again inside the one change that charges
			return
		end
		x.coins -= G.price
		x.gear.gel = true
		bought = true
	end)
	if bought then
		AnalyticsSvc.funnel(player, "first_coins_spent")
		DataService.saveNow(player)
		setHeld(player, "gel") -- straight into your hands, so you see the new slot light up
		Remotes.fire(player, "Notify", "gearBought", { key = "gel" })
	end
end

local function setOwned(player: Player)
	local d = DataService.get(player)
	if d then
		player:SetAttribute("GearGel", d.gear.gel) -- the hotbar unlocks its slot from it
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
		stowed[player] = nil
		setHeld(player, "ray")
		setOwned(player)
	end)
	DataService.Changed:Connect(setOwned)
	Players.PlayerRemoving:Connect(function(p)
		held[p] = nil
		stowed[p] = nil
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
