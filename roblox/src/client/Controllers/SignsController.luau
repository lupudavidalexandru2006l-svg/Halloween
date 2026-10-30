--!strict
-- SignsController: each zone sign shows YOUR odds (personal rares with your own pity), so the server
-- sends them to each player ("odds") and this client draws them on its own copy of the sign.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Theme = require(ReplicatedStorage.Shared.Theme)
local WorldRules = require(ReplicatedStorage.Shared.WorldRules)
local Ui = require(script.Parent.Parent.Lib.Ui)
local State = require(script.Parent.State)
local SettingsController = require(script.Parent.SettingsController)

local SignsController = {}
local rows: { [number]: { [string]: TextLabel } } = {}
local heat: { [number]: TextLabel } = {}

local function build(zone: Config.Zone)
	local map = workspace:FindFirstChild("Map")
	local part = map and map:FindFirstChild("ZoneSign" .. zone.id, true)
	if not part or not part:IsA("BasePart") or rows[zone.id] then
		return
	end
	local g = Instance.new("SurfaceGui")
	g.Name = "MyOdds"
	g.Face = Enum.NormalId.Front
	g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	g.PixelsPerStud = 40
	g.Adornee = part
	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = Theme.board
	frame.Parent = g
	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = frame
	local function line(order: number, s: string, h: number, color: Color3): TextLabel
		local t = Ui.label(frame, s, UDim2.fromScale(1, h))
		t.LayoutOrder = order
		t.TextColor3 = color
		return t
	end
	line(0, zone.name, 0.14, Theme.white)
	heat[zone.id] = line(1, "", 0.09, Theme.ice)
	local byTier = {}
	for i, t in Config.tiers do
		byTier[t.name] = line(i + 1, t.name, 0.095, Theme.tiers[t.name])
	end
	rows[zone.id] = byTier
	g.Parent = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
end

local function percent(o: number): string
	return if o >= 1 then string.format("%.1f%%", o) elseif o >= 0.01 then string.format("%.2f%%", o) else `1 in {math.round(100 / o)}`
end

local function draw()
	for _, z in Config.world.zones do
		build(z)
		local labels = rows[z.id]
		local odds = State.odds[tostring(z.id)]
		if labels and odds then
			for name, label in labels do
				local o = odds[name]
				if typeof(o) == "number" and o > 0 then
					label.Text = `{name}   {percent(o)}` -- the true odds, your pity included
				end
			end
		end
		if heat[z.id] then
			local c = WorldRules.zoneTemperature(z.id)
			heat[z.id].Text = if SettingsController.get("unit") == "F" then `{WorldRules.toFahrenheit(c)}°F` else `{c}°C`
		end
	end
end

function SignsController.Init() end

function SignsController.Start()
	State.Notify:Connect(function(kind: string)
		if kind == "odds" then
			draw()
		end
	end)
	SettingsController.Changed:Connect(draw)
end

return SignsController
