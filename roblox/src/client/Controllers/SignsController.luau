--!strict
-- SignsController: draws the gauge at every pan's door: its owner's Cold Power (2026-11-10; it showed the pan's Cold Level before).
-- (The zone odds signs it also drew were removed, owner 2026-11-03.)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Theme = require(ReplicatedStorage.Shared.Theme)
local Ui = require(script.Parent.Parent.Lib.Ui)
local State = require(script.Parent.State)
local SettingsController = require(script.Parent.SettingsController)

local SignsController = {}

-- the gauge at each pan's door: its owner's Cold Power (the map's PanPower<i>, set by PanService).
-- owner 2026-11-17 ("improve these small details from the pan"): was a thermometer drawn from plain UI
-- shapes; now an ice-trimmed panel with the painted Power icon, the number big, and a bar filled by how
-- far it is toward the next island's need.
type Gauge = { gui: SurfaceGui, label: TextLabel, fill: Frame, flashing: boolean }
local gauges: { [number]: Gauge } = {}

-- QA 2026-11-20: a respawn deleted these (ResetOnSpawn) and a part that streamed out and back in left them on a
-- dead part, so the door gauges and stand coins went blank for good. A gui still drawing on this part is kept.
local function stillOn(g: SurfaceGui?, part: BasePart): boolean
	return g ~= nil and g.Parent ~= nil and g.Adornee == part
end

local function buildGauge(i: number)
	local map = workspace:FindFirstChild("Map")
	local plot = map and map:FindFirstChild("Plot" .. i)
	local part = plot and plot:FindFirstChild("PanGauge")
	if not part or not part:IsA("BasePart") then
		return
	end
	local old = gauges[i]
	if old and stillOn(old.gui, part) then
		return
	end
	if old then
		old.gui:Destroy()
	end
	local g = Instance.new("SurfaceGui")
	g.Name = "Gauge"
	g.ResetOnSpawn = false
	g.Face = Enum.NormalId.Front
	g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	g.PixelsPerStud = 40
	g.Adornee = part
	local HA = Theme.hubArt
	-- an ice-white trim round the navy board (the board itself is the part)
	local trim = Instance.new("Frame")
	trim.BackgroundTransparency = 1
	trim.AnchorPoint = Vector2.new(0.5, 0.5)
	trim.Position = UDim2.fromScale(0.5, 0.5)
	trim.Size = UDim2.new(1, -10, 1, -10)
	Ui.corner(trim, 0.08)
	local ts = Instance.new("UIStroke")
	ts.Color = Theme.white
	ts.Thickness = 5
	ts.Parent = trim
	trim.Parent = g
	-- the painted Power icon (the same one as the HUD's Power), top
	local icon = Ui.image(g, Config.images.icons.power, UDim2.fromScale(0.62, 0.36), UDim2.fromScale(0.19, 0.07))
	icon.ScaleType = Enum.ScaleType.Fit
	-- the number, big, under it
	local label = Ui.label(g, "", UDim2.fromScale(0.84, 0.27), UDim2.fromScale(0.08, 0.44))
	-- the progress bar toward the next island
	local tube = Instance.new("Frame")
	tube.Position = UDim2.fromScale(0.14, 0.78)
	tube.Size = UDim2.fromScale(0.72, 0.1)
	tube.BackgroundColor3 = HA.gaugeTube
	Ui.corner(tube, 1)
	Ui.stroke(tube, 3)
	tube.Parent = g
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(0.35, 1)
	fill.BackgroundColor3 = HA.gaugeFill
	Ui.corner(fill, 1)
	fill.Parent = tube
	gauges[i] = { gui = g, label = label, fill = fill, flashing = false }
	g.Parent = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
end

-- the Pan Upgrades stand's front (owner 2026-11-17): a painted coin on the plain green box, so it reads as
-- "spend coins here". PanUpgrade is the stand's invisible collider, built without a turn: +Z (Back) faces the plaza.
local stands: { [number]: SurfaceGui } = {}
local function buildStand(i: number)
	local map = workspace:FindFirstChild("Map")
	local plot = map and map:FindFirstChild("Plot" .. i)
	local part = plot and plot:FindFirstChild("PanUpgrade")
	if not part or not part:IsA("BasePart") or stillOn(stands[i], part) then
		return
	end
	if stands[i] then
		stands[i]:Destroy()
	end
	local g = Instance.new("SurfaceGui")
	stands[i] = g
	g.Name = "StandFront"
	g.ResetOnSpawn = false
	g.Face = Enum.NormalId.Back
	g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	g.PixelsPerStud = 50
	g.LightInfluence = 0.4
	g.MaxDistance = 120
	g.ZOffset = 1 -- the green box's front is in the same plane
	g.Adornee = part
	local coin = Ui.image(g, Config.images.icons.coin, UDim2.fromScale(0.6, 0.55), UDim2.fromScale(0.2, 0.32))
	coin.ScaleType = Enum.ScaleType.Fit
	g.Parent = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
end

local function powerOf(i: number): number
	local map = workspace:FindFirstChild("Map")
	local v = map and map:GetAttribute("PanPower" .. i)
	return if typeof(v) == "number" then v else 0
end

local function setGauge(gauge: Gauge, share: number, color: Color3, text: string)
	gauge.label.Text = text
	gauge.fill.Size = UDim2.fromScale(math.clamp(share, 0.12, 1), 1)
	gauge.fill.BackgroundColor3 = color
end

local function drawGauges()
	for i in Config.world.plots do
		buildGauge(i)
		buildStand(i)
		local gauge = gauges[i]
		if gauge and not gauge.flashing then
			-- your own pan shows your exact Cold Power, the same number as the HUD (the map's PanPower is cut to
			-- 2 digits for everyone, so your gauge read 1,100 beside a HUD of 1,175)
			local v = State.view
			local power = if v and v.plot == i then (v.coldPower or 0) else powerOf(i)
			setGauge(gauge, power / Config.nextNeed(power), Theme.training.power, Config.powerText(power))
		end
	end
end

local function watchGauges()
	task.spawn(function()
		local map = workspace:WaitForChild("Map", 30)
		if map then
			map.AttributeChanged:Connect(function(name: string)
				if string.sub(name, 1, 8) == "PanPower" then
					drawGauges()
				end
			end)
		end
	end)
end
function SignsController.Init() end

function SignsController.Start()
	watchGauges()
	SettingsController.Changed:Connect(drawGauges)
	State.Changed:Connect(drawGauges)
	-- the pans are in the hub, which streams in first; keep looking, so a gauge whose part streamed out on a far
	-- island and back in is drawn again (a kept gauge just gets its text set again)
	task.spawn(function()
		while true do
			drawGauges()
			task.wait(2)
		end
	end)
end

return SignsController
