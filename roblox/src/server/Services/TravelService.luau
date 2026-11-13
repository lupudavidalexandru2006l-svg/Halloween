--!strict
-- TravelService (owner 2026-11-12): the top buttons take you to the Equipment Booth or your own pan.
-- Decided here with the server's own checks: never with a cube in your hands (the trip home is the
-- game), never while tumbling or locked on a trainer, and at most once every Config.ui.topButtons.cooldown.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(script.Parent.Remotes)
local DataService = require(script.Parent.DataService)
local PlayerTracker = require(script.Parent.PlayerTracker)
local CarryService = require(script.Parent.CarryService)
local WorldService = require(script.Parent.WorldService)

local TravelService = {}
local TB = Config.ui.topButtons
local last: { [Player]: number } = {}

-- where a button takes this player (nil = nowhere right now)
local function destination(player: Player, id: string): CFrame?
	if id == "equipment" then
		return CFrame.lookAt(TB.equipment.at, TB.equipment.face)
	elseif id == "pan" then
		local plot = WorldService.plotOf(player)
		local pl = plot and Config.world.plots[plot]
		if not pl then
			return nil
		end
		local front = Config.world.pans.frontZ
		local at = Vector3.new(pl.x, 3, front + TB.panFront)
		return CFrame.lookAt(at, Vector3.new(pl.x, 3, front - 10)) -- facing in through the door
	end
	return nil
end

local function onTravel(player: Player, id: any)
	if typeof(id) ~= "string" or not DataService.get(player) then
		return
	end
	local now = os.clock()
	if now - (last[player] or -math.huge) < TB.cooldown then
		return
	end
	if CarryService.count(player) > 0 then
		Remotes.notYet(player, "Bring your pet home first", "travel")
		return
	end
	if player:GetAttribute("Tagged") or player:GetAttribute("TrainLocked") then
		return
	end
	local cf = destination(player, id)
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not cf or not hum or hum.Health <= 0 then
		return
	end
	last[player] = now
	PlayerTracker.teleport(player, cf)
end

function TravelService.Init() end

function TravelService.Start()
	Remotes.on("Teleport", onTravel)
	Players.PlayerRemoving:Connect(function(p)
		last[p] = nil
	end)
end

return TravelService
