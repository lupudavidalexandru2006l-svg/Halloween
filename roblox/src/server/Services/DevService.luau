--!strict
-- DevService: test switches that only exist in Studio (RunService:IsStudio()), never on a live server.
-- Chat "/dev <command> [number]":
--   coins N    give N coins            epic | legendary | mythic | secret   a personal pet next to you
--   chill      start a Big Chill now   heat N   set the Pine Forest's heat (hot runs)
--   ray N      set your Ice Ray level  away N   pretend you were away N seconds (welcome back)
--   wipe       really wipe your save (saving is blocked first) and kick

local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local DataService = require(script.Parent.DataService)
local PenService = require(script.Parent.PenService)
local EventService = require(script.Parent.EventService)
local WildPetSpawner = require(script.Parent.WildPetSpawner)

local DevService = {}

local TIERS = { epic = "Epic", legendary = "Legendary", mythic = "Mythic", secret = "Secret", rare = "Rare" }

local function run(player: Player, text: string)
	local words = string.split(string.lower(text), " ")
	local cmd, n = words[2], tonumber(words[3])
	if cmd == "coins" and n then
		local amount = math.clamp(n, 0, Config.dev.maxCoins)
		DataService.mutate(player, function(d)
			PenService.addCoins(d, amount)
		end)
	elseif cmd and TIERS[cmd] then
		WildPetSpawner.devSpawn(player, TIERS[cmd])
	elseif cmd == "chill" then
		EventService.startNow()
	elseif cmd == "heat" and n then
		local forest = Config.zone(2)
		if forest then
			forest.heat = math.clamp(n, 0, Config.dev.heatMax)
		end
	elseif cmd == "ray" and n then
		DataService.mutate(player, function(d)
			d.upgrades.ray = math.clamp(math.floor(n), 1, Config.upgrades.ray.maxLevel)
		end)
	elseif cmd == "away" and n then
		PenService.devAway(player, math.clamp(n, 0, Config.dev.awayMax))
	elseif cmd == "wipe" then
		DataService.wipe(player)
	end
end

function DevService.Init() end

function DevService.Start()
	if not RunService:IsStudio() then
		return
	end
	local command = Instance.new("TextChatCommand")
	command.Name = "DevCommand"
	command.PrimaryAlias = "/dev"
	command.Triggered:Connect(function(source: TextSource, text: string)
		local player = Players:GetPlayerByUserId(source.UserId)
		if player and DataService.isLoaded(player) then
			run(player, text)
		end
	end)
	command.Parent = TextChatService
end

return DevService
