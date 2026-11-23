--!strict
-- AfkService (owner 2026-11-22): Roblox disconnects a player idle for 20 minutes. Before that, the client
-- (AfkController, on Player.Idled) sends "AfkRejoin"; this service saves them and teleports them to another
-- server of this place, so they're never kicked. Whether they were on their trainer is decided here (the
-- server's own TrainLocked mark), carried in the teleport data, and on arrival TrainingService.resume puts
-- them back on their own trainer. The teleport data only ever asks for that: no coins, no pets, nothing
-- that the save doesn't already hold. In Studio (no teleports) the same request respawns them here instead.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(script.Parent.Remotes)
local DataService = require(script.Parent.DataService)
local TrainingService = require(script.Parent.TrainingService)

local AfkService = {}
local A = Config.afk
local lastAsk: { [Player]: number } = {}
local moving: { [Player]: boolean } = {}

local function resumeLater(player: Player)
	task.spawn(function()
		local ok = TrainingService.resume(player)
		print(`[AfkService] {player.Name} back on their trainer: {ok}`)
	end)
end

local function rejoin(player: Player)
	local now = os.clock()
	if moving[player] or now - (lastAsk[player] or -math.huge) < A.minGap or not DataService.isLoaded(player) then
		return
	end
	lastAsk[player] = now
	local training = player:GetAttribute("TrainLocked") == true
	if RunService:IsStudio() then
		-- Studio can't teleport: a respawn stands in for the new server, then the same resume
		print(`[AfkService] {player.Name} idle: Studio rejoin (training {training})`)
		player:LoadCharacter()
		if training then
			resumeLater(player)
		end
		return
	end
	moving[player] = true
	DataService.saveNow(player) -- written before they leave; the session lock covers the new server's load
	local opts = Instance.new("TeleportOptions")
	opts:SetTeleportData({ afk = true, train = training })
	local ok, err = pcall(function()
		TeleportService:TeleportAsync(game.PlaceId, { player }, opts)
	end)
	if not ok then
		warn("[AfkService] teleport failed:", err)
		moving[player] = nil
	end
end

function AfkService.Init() end

function AfkService.Start()
	Remotes.on("AfkRejoin", rejoin)
	-- a teleport that fails after it started (full server, Roblox hiccup): they stay here, free to ask again
	TeleportService.TeleportInitFailed:Connect(function(player: Player)
		moving[player] = nil
		lastAsk[player] = nil
	end)
	local function arrived(player: Player)
		local ok, join = pcall(function()
			return player:GetJoinData()
		end)
		local data = ok and join and join.TeleportData
		if typeof(data) == "table" and data.afk == true and data.train == true then
			resumeLater(player)
		end
	end
	Players.PlayerAdded:Connect(arrived)
	for _, p in Players:GetPlayers() do
		arrived(p)
	end
	Players.PlayerRemoving:Connect(function(p)
		lastAsk[p] = nil
		moving[p] = nil
	end)
end

return AfkService
