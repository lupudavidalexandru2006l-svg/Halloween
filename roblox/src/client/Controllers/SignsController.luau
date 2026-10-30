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
	-- the prototype's sign: a cream panel inside the wooden frame (the part), dark text, a coloured dot
	-- per rarity and its odds on the right
	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(0.9, 0.88)
	frame.Position = UDim2.fromScale(0.05, 0.06)
	frame.BackgroundColor3 = Theme.panel
	Ui.corner(frame, 0.04)
	frame.Parent = g
	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.Parent = frame
	local function inkLabel(parent: Instance, s: string, size: UDim2, pos: UDim2?): TextLabel
		local t = Ui.label(parent, s, size, pos)
		t.TextColor3 = Theme.ink
		local st = t:FindFirstChildOfClass("UIStroke")
		if st then
			st.Enabled = false
		end
		return t
	end
	inkLabel(frame, zone.name, UDim2.fromScale(0.9, 0.15)).LayoutOrder = 0
	local h = inkLabel(frame, "", UDim2.fromScale(0.9, 0.08))
	h.LayoutOrder = 1
	h.TextTransparency = 0.25
	heat[zone.id] = h
	local byTier = {}
	for i, t in Config.tiers do
		local row = Instance.new("Frame")
		row.BackgroundTransparency = 1
		row.Size = UDim2.fromScale(0.9, 0.1)
		row.LayoutOrder = i + 1
		row.Parent = frame
		local dot = Instance.new("Frame")
		dot.BackgroundColor3 = Theme.tiers[t.name]
		dot.Size = UDim2.fromScale(0.07, 0.6)
		dot.Position = UDim2.fromScale(0, 0.2)
		Ui.corner(dot, 1)
		Ui.stroke(dot, 2)
		local a = Instance.new("UIAspectRatioConstraint")
		a.Parent = dot
		dot.Parent = row
		local name = inkLabel(row, t.name, UDim2.fromScale(0.5, 0.8), UDim2.fromScale(0.1, 0.1))
		name.TextXAlignment = Enum.TextXAlignment.Left
		local value = inkLabel(row, "", UDim2.fromScale(0.4, 0.8), UDim2.fromScale(0.6, 0.1))
		value.TextXAlignment = Enum.TextXAlignment.Right
		byTier[t.name] = value
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
					label.Text = percent(o) -- the true odds, your pity included
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
