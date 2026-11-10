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

-- the gauge at each pan's door: a thermometer drawn from UI shapes showing its owner's Cold Power
-- (the map's PanPower<i>, set by PanService): the number, and the tube filled by how far it is toward
-- the next island's need.
type Gauge = { label: TextLabel, fill: Frame, tube: Frame, bulb: Frame, flashing: boolean }
local gauges: { [number]: Gauge } = {}
local function buildGauge(i: number)
	local map = workspace:FindFirstChild("Map")
	local plot = map and map:FindFirstChild("Plot" .. i)
	local part = plot and plot:FindFirstChild("PanGauge")
	if not part or not part:IsA("BasePart") or gauges[i] then
		return
	end
	local g = Instance.new("SurfaceGui")
	g.Name = "Gauge"
	g.Face = Enum.NormalId.Front
	g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	g.PixelsPerStud = 40
	g.Adornee = part
	local HA = Theme.hubArt
	local tube = Instance.new("Frame")
	tube.AnchorPoint = Vector2.new(0.5, 0)
	tube.Position = UDim2.fromScale(0.5, 0.06)
	tube.Size = UDim2.fromScale(0.3, 0.58)
	tube.BackgroundColor3 = HA.gaugeTube
	Ui.corner(tube, 1)
	Ui.stroke(tube, 3)
	tube.Parent = g
	local fill = Instance.new("Frame")
	fill.AnchorPoint = Vector2.new(0.5, 1)
	fill.Position = UDim2.fromScale(0.5, 1)
	fill.Size = UDim2.fromScale(0.6, 0.35)
	fill.BackgroundColor3 = HA.gaugeFill
	Ui.corner(fill, 1)
	fill.Parent = tube
	local bulb = Instance.new("Frame")
	bulb.AnchorPoint = Vector2.new(0.5, 0.5)
	bulb.Position = UDim2.fromScale(0.5, 0.64)
	bulb.Size = UDim2.fromScale(0.5, 0.5)
	bulb.BackgroundColor3 = HA.gaugeFill
	local a = Instance.new("UIAspectRatioConstraint")
	a.Parent = bulb
	Ui.corner(bulb, 1)
	Ui.stroke(bulb, 3)
	bulb.Parent = g
	gauges[i] = { label = Ui.label(g, "", UDim2.fromScale(1, 0.22), UDim2.fromScale(0, 0.77)), fill = fill, tube = tube, bulb = bulb, flashing = false }
	g.Parent = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
end

local function powerOf(i: number): number
	local map = workspace:FindFirstChild("Map")
	local v = map and map:GetAttribute("PanPower" .. i)
	return if typeof(v) == "number" then v else 0
end

local function setGauge(gauge: Gauge, share: number, color: Color3, text: string)
	gauge.label.Text = text
	gauge.fill.Size = UDim2.fromScale(0.6, math.clamp(share, 0.12, 1))
	gauge.fill.BackgroundColor3 = color
	gauge.bulb.BackgroundColor3 = color
end

local function drawGauges()
	for i in Config.world.plots do
		buildGauge(i)
		local gauge = gauges[i]
		if gauge and not gauge.flashing then
			local power = powerOf(i)
			setGauge(gauge, power / Config.nextNeed(power), Theme.rink.power, Config.coinText(power))
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
	-- the pans are in the hub, which streams in first; look again a few times in case it's late
	task.spawn(function()
		for _ = 1, 10 do
			drawGauges()
			task.wait(2)
		end
	end)
end

return SignsController
