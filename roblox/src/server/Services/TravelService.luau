--!strict
-- TravelService (owner 2026-11-12): the top buttons take you to the Equipment Booth or your own pan.
-- Decided here with the server's own checks: never with a cube in your hands (the trip home is the
-- game), never while tumbling or locked on a trainer, and at most once every Config.ui.topButtons.cooldown.
-- Night close (owner 2026-11-16, Config.nightClose): as the Night Reset falls, glowing walls rise across the
-- tunnel mouth and anyone out on the islands is brought home to their pan with empty hands (owner 2026-11-18:
-- the cubes they hadn't got home are lost; a bought Super Freeze cube stays). The walls go at sunrise.

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

-- a look-only part of the night wall (no collision, no shadow)
local function deco(m: Model, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	if shape then
		p.Shape = shape
	end
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material
	p.Parent = m
	return p
end

-- owner 2026-11-17 (later): "improve the night wall". Like the big sim games' night gates: a starry
-- violet curtain in a chunky frame, a big glowing crescent moon over the middle, star lights along the
-- top and slow twinkles. Bright candy night, never dark or scary.
local function buildWall(): Model
	local NC = Config.nightClose
	local W = Config.world
	local F = Theme.fx
	local m = Instance.new("Model")
	m.Name = "NightWall"
	local width = W.tunnel.width + W.tunnel.wallThick * 2
	local h = NC.wallHeight
	local z = W.hubZMax + NC.wallZ
	local wall = Instance.new("Part")
	wall.Name = "Wall"
	wall.Anchored = true
	wall.CanCollide = true
	wall.CanQuery = false
	wall.CanTouch = false
	wall.CastShadow = false
	wall.Material = Enum.Material.SmoothPlastic
	wall.Color = F.nightWallDeep
	wall.Transparency = 0.25
	wall.Size = Vector3.new(width, h, 1)
	wall.CFrame = CFrame.new(0, h / 2, z)
	wall.Parent = m
	-- a shimmer layer just behind it (in front it would cover the words)
	deco(m, Vector3.new(width, h, 0.2), CFrame.new(0, h / 2, z + 0.7), F.nightWall, Enum.Material.ForceField).Transparency = 0.1
	-- the chunky frame: two posts and a top beam, with star lights along it
	for _, x in { -width / 2, width / 2 } do
		deco(m, Vector3.new(4, h + 2, 4), CFrame.new(x, (h + 2) / 2, z), F.nightFrame, Enum.Material.SmoothPlastic)
		deco(m, Vector3.new(4.6, 4.6, 4.6), CFrame.new(x, h + 3.5, z), F.nightMoon, Enum.Material.Neon, Enum.PartType.Ball)
	end
	deco(m, Vector3.new(width, 3, 3), CFrame.new(0, h + 1, z), F.nightFrame, Enum.Material.SmoothPlastic)
	for k = 0, 10 do
		local x = -width / 2 + 6 + k * (width - 12) / 10
		local star = deco(m, Vector3.new(1.6, 1.6, 1.6), CFrame.new(x, h + 1, z - 1.7) * CFrame.Angles(0, 0, math.pi / 4), F.nightStar, Enum.Material.Neon)
		star.Name = "StarLight"
	end
	-- the crescent moon: a glowing disc with a curtain-coloured disc over its side
	local my = h * 0.42 -- under the tunnel arch's beam, so the whole moon shows
	local moon = deco(m, Vector3.new(0.6, 13, 13), CFrame.new(0, my, z - 1) * CFrame.Angles(0, math.pi / 2, 0), F.nightMoon, Enum.Material.Neon, Enum.PartType.Cylinder)
	local ml = Instance.new("PointLight")
	ml.Color, ml.Range, ml.Brightness, ml.Shadows = F.nightMoon, 40, 1.5, false
	ml.Parent = moon
	deco(m, Vector3.new(0.6, 10.6, 10.6), CFrame.new(3.3, my + 1.8, z - 1.4) * CFrame.Angles(0, math.pi / 2, 0), F.nightWallDeep, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	-- twinkling stars drifting over the curtain
	local pe = Instance.new("ParticleEmitter")
	pe.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	pe.Color = ColorSequence.new(F.nightStar)
	pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, 1.4), NumberSequenceKeypoint.new(1, 0) })
	pe.Lifetime = NumberRange.new(2.5, 4)
	pe.Rate = 14
	pe.Speed = NumberRange.new(0.3, 1)
	pe.SpreadAngle = Vector2.new(180, 180)
	pe.LightEmission = 1
	pe.Parent = wall
	-- the hub side says why, in plain words
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Front -- faces -Z, toward the hub
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 20
	sg.LightInfluence = 0
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.AnchorPoint = Vector2.new(0.5, 0.5)
	t.Position = UDim2.fromScale(0.5, 0.86)
	t.Size = UDim2.fromScale(0.6, 0.14)
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
				-- you didn't make it home: the pets in your hands stay behind (owner 2026-11-18)
				local lost = CarryService.loseCarried(player)
				-- home at once (owner 2026-11-18: "when it is night the teleport back to the pan isn't instant")
				PlayerTracker.teleport(player, cf)
				task.delay(Config.nightClose.homeDelay, function()
					if player.Parent then
						-- after the server-wide nightStart banner, so this one (with "your pet got away") is the one seen
						Remotes.fire(player, "Notify", "nightHome", { lost = lost })
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
