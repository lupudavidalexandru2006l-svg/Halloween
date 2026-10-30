--!strict
-- FreezeService: decides every freeze. Prompts are server ProximityPrompts (the hold is timed by
-- Roblox on the server); this service checks distance from the server's own character position,
-- cooldown, backpack space and pet state, then captures the pose at the moment the hold finished.
-- Also owns the ice bridge and the gift-box prompt hand-off.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local WorldRules = require(ReplicatedStorage.Shared.WorldRules)
local Remotes = require(script.Parent.Remotes)
local DataService = require(script.Parent.DataService)
local AnalyticsSvc = require(script.Parent.AnalyticsSvc)
local PlayerTracker = require(script.Parent.PlayerTracker)
local WorldService = require(script.Parent.WorldService)
local WildPetSpawner = require(script.Parent.WildPetSpawner)
local CarryService = require(script.Parent.CarryService)
local EventService = require(script.Parent.EventService)

local FreezeService = {}
local lastFreeze: { [Player]: number } = {}
local bridgeUntil = 0

local function inRange(player: Player, pos: Vector3, extra: number): boolean
	local p = PlayerTracker.position(player)
	return p ~= nil and (Vector3.new(p.X, 0, p.Z) - Vector3.new(pos.X, 0, pos.Z)).Magnitude <= Config.player.freezeRange + extra
end

function FreezeService.onHoldBegan(player: Player, id: string)
	local pet = WildPetSpawner.get(id)
	if not pet or not DataService.isLoaded(player) then
		return
	end
	PlayerTracker.setZapping(player, true)
	AnalyticsSvc.funnel(player, "first_zap")
end

function FreezeService.onHoldEnded(player: Player, _id: string)
	PlayerTracker.setZapping(player, false)
end

function FreezeService.onPetTriggered(player: Player, id: string)
	PlayerTracker.setZapping(player, false)
	local data = DataService.get(player)
	local pet = WildPetSpawner.get(id)
	if not data or not pet then
		return
	end
	if os.clock() - (lastFreeze[player] or 0) < Config.player.freezeCooldown then
		return
	end
	if not inRange(player, pet.root.Position, 2) then
		return
	end
	if pet.state == "dazed" and pet.dazedOwner and pet.dazedOwner ~= player then
		return -- only the player who carried it can zap a dazed pet back (nobody takes it from them)
	end
	if CarryService.count(player) >= CarryService.capacity(player) then
		Remotes.fire(player, "Notify", "notYet", { reason = "Backpack full" })
		return
	end
	if pet.zone == 2 and not data.forestUnlocked then
		return -- can't happen through the gate, but never trust a position
	end
	lastFreeze[player] = os.clock()
	local pose = if pet.state == "dazed" then pet.pose or "idle" else pet.action -- the pose when the hold finished
	local mut = if pet.state == "dazed" then pet.mut elseif EventService.isChill() then "Frosty" else nil
	local info = { key = pet.def.key, zone = pet.zone, pose = pose, mut = mut, superFrozen = false, superUsed = pet.superUsed }
	local at = pet.root.Position
	WildPetSpawner.remove(id)
	CarryService.addCube(player, info)
	DataService.mutate(player, function(d)
		d.stats.frozen += 1
	end)
	AnalyticsSvc.funnel(player, "first_freeze")
	Remotes.fire(player, "Notify", "frozen", { key = info.key, pose = pose, mut = mut, at = at })
end

local function onBridge(player: Player)
	local data = DataService.get(player)
	if not data or not inRange(player, WorldRules.iceBridgeCenter(), 3) then
		return
	end
	local secs = Config.bridge.baseSeconds + Config.upgrades.ray.bridgeBonus * (data.upgrades.ray - 1)
	bridgeUntil = math.max(bridgeUntil, os.clock() + secs)
	WorldService.setIceBridge(true)
	Remotes.fireAll("Notify", "bridge", { seconds = secs, by = player.DisplayName })
end

function FreezeService.Init() end

function FreezeService.Start()
	local bp = WorldService.bridgePrompt
	if bp then
		bp.Triggered:Connect(onBridge)
	end
	-- every pet prompt goes through here; the gift box prompt belongs to PenService
	ProximityPromptService.PromptButtonHoldBegan:Connect(function(prompt: ProximityPrompt, player: Player)
		local id = WildPetSpawner.idFromPrompt(prompt)
		if id then
			FreezeService.onHoldBegan(player, id)
		end
	end)
	ProximityPromptService.PromptButtonHoldEnded:Connect(function(prompt: ProximityPrompt, player: Player)
		local id = WildPetSpawner.idFromPrompt(prompt)
		if id then
			FreezeService.onHoldEnded(player, id)
		end
	end)
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt, player: Player)
		local id = WildPetSpawner.idFromPrompt(prompt)
		if id then
			FreezeService.onPetTriggered(player, id)
		end
	end)
	Players.PlayerRemoving:Connect(function(p)
		lastFreeze[p] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(0.5)
			if bridgeUntil > 0 and os.clock() >= bridgeUntil then
				bridgeUntil = 0
				WorldService.setIceBridge(false)
			end
		end
	end)
end

return FreezeService
