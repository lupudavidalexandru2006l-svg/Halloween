--!strict
-- AfkController (owner 2026-11-22): Roblox kicks a player idle for 20 minutes. Player.Idled tells us how long
-- we've been idle (from 2 minutes on); once that reaches Config.afk.rejoinSeconds we ask the server
-- ("AfkRejoin") to move us to another server instead. Any input starts the count again. The server decides
-- the rest (AfkService), including putting us back on our trainer if we were training.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local State = require(script.Parent.State)

local AfkController = {}
local idleSince: number? = nil -- os.clock() when the idle began, nil while active
local asked = false

function AfkController.Init() end

function AfkController.Start()
	Players.LocalPlayer.Idled:Connect(function(seconds: number)
		idleSince = os.clock() - seconds
	end)
	local function active()
		idleSince, asked = nil, false
	end
	UserInputService.InputBegan:Connect(active)
	UserInputService.InputChanged:Connect(active) -- a mouse move or a stick ends the idle too, as for Roblox
	task.spawn(function()
		while true do
			task.wait(5)
			if idleSince and not asked and os.clock() - idleSince >= Config.afk.rejoinSeconds then
				asked = true
				State.send("AfkRejoin")
				-- if the move didn't happen (a full server), ask again a little later
				task.delay(Config.afk.minGap + 5, function()
					asked = false
				end)
			end
		end
	end)
end

return AfkController
