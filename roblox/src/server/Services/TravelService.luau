--!strict
-- TravelService (owner 2026-11-12): the top buttons take you to the Equipment Booth or your own pan.
-- Decided here with the server's own checks: never with a cube in your hands (the trip home is the
-- game), never while tumbling or locked on a trainer, and at most once every Config.ui.topButtons.cooldown.
-- Night close (owner 2026-11-16, Config.nightClose): as the Night Reset falls, glowing walls rise across the
-- tunnel mouth and anyone out on the islands is brought home to their pan, cubes in hand and all (nothing is
-- lost; the cubes don't melt in the hub). The walls go at sunrise.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(script.Parent.Remotes)
local DataService = require(script.Parent.DataService)
local PlayerTracker = require(script.Parent.PlayerTracker)
local CarryService = require(script.Parent.CarryService)
local WorldService = require(script.Parent.WorldService)
local EventService = require(script.Parent.EventService)
local WorldRules = require(ReplicatedStorage.Shared.WorldRules)
local Theme = require(ReplicatedStorage.Shared.Theme)

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

local nightWall: Model? = nil

local function buildWall(): Model
	local NC = Config.nightClose
	local W = Config.world
	local m = Instance.new("Model")
	m.Name = "NightWall"
	local width = W.tunnel.width + W.tunnel.wallThick * 2
	local wall = Instance.new("Part")
	wall.Name = "Wall"
	wall.Anchored = true
	wall.CanCollide = true
	wall.CanQuery = false
	wall.CanTouch = false
	wall.CastShadow = false
	wall.Material = Enum.Material.ForceField
	wall.Color = Theme.fx.nightWall
	wall.Transparency = 0.15
	wall.Size = Vector3.new(width, NC.wallHeight, 1)
	wall.CFrame = CFrame.new(0, NC.wallHeight / 2, W.hubZMax + NC.wallZ)
	wall.Parent = m
	-- the hub side says why, in plain words
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Front -- faces -Z, toward the hub
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 20
	sg.LightInfluence = 0
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.AnchorPoint = Vector2.new(0.5, 0.5)
	t.Position = UDim2.fromScale(0.5, 0.3)
	t.Size = UDim2.fromScale(0.5, 0.18)
	t.Font = Theme.font
	t.TextScaled = true
	t.TextColor3 = Theme.white
	t.Text = "Night! Islands open at sunrise"
	local s = Instance.new("UIStroke")
	s.Color = Theme.ink
	s.Thickness = 6
	s.Parent = t
	t.Parent = sg
	sg.Parent = wall
	m.Parent = workspace
	return m
end

-- night falls: walls up, everyone on the islands home; sunrise: walls down
function TravelService.nightClose(night: boolean)
	if not night then
		if nightWall then
			nightWall:Destroy()
			nightWall = nil
		end
		return
	end
	if not nightWall then
		nightWall = buildWall()
	end
	for _, player in Players:GetPlayers() do
		local pos = PlayerTracker.position(player)
		if pos and WorldRules.zoneAt(pos) > 0 and not player:GetAttribute("TrainLocked") then
			local cf = destination(player, "pan")
			if cf then
				Remotes.fire(player, "Notify", "nightHome", {})
				task.delay(Config.nightClose.homeDelay, function()
					if player.Parent then
						PlayerTracker.teleport(player, cf)
					end
				end)
			end
		end
	end
end

function TravelService.Init() end

function TravelService.Start()
	Remotes.on("Teleport", onTravel)
	EventService.NightChanged:Connect(TravelService.nightClose)
	if EventService.isNight() then
		TravelService.nightClose(true)
	end
	Players.PlayerRemoving:Connect(function(p)
		last[p] = nil
	end)
end

return TravelService
