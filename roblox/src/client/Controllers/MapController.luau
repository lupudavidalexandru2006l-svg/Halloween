--!strict
-- MapController: what this player sees of the map's state (all local; the server owns the real
-- gate, doors and gift):
--  - every island's gate (Round 4 phase 6): its ice bars slide into the ground once you've opened it,
--    its wall lets you through (on your screen only; PlayerTracker guards the real thing), and its sign
--    shows how close you are ("OPEN FOR 5,000 COINS" over a coin bar, "NEEDS REBIRTH 1", or
--    "COMING SOON" for an island whose pets aren't ready)
--  - the gates' glowing beams and the end cap breathe (the next goal glows)
--  - your own pan's door opens for you (its collider is off on your screen only) and glows green;
--    other pans' doors stay shut and ice-blue
--  - each island's own light: the camera's tint and haze fade to the section you're in
--  - the gift box bobs while a gift waits, with a "DAILY GIFT" / "NEXT GIFT TOMORROW" label

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Theme = require(ReplicatedStorage.Shared.Theme)
local WorldRules = require(ReplicatedStorage.Shared.WorldRules)
local Ui = require(script.Parent.Parent.Lib.Ui)
local State = require(script.Parent.State)
local SettingsController = require(script.Parent.SettingsController)

local MapController = {}
local M = Config.mapFx
local me = Players.LocalPlayer
local giftParts: { { part: BasePart, cf: CFrame } } = {}
local giftLabel: Ui.Block? = nil
local giftGui: BillboardGui? = nil
local glows: { BasePart } = {}
local lightZone = -1
local gateBars: { [number]: Frame } = {} -- each gate sign's progress fill

local function map(): Instance?
	return workspace:FindFirstChild("Map")
end

local function reachOf(v: State.View?): number
	return if v then v.reach or (if v.forestUnlocked then 2 else 1) else 1
end

-- a gate's art folder (MapArt: Art.Tunnel.Section<id>.Gate<id>), found by path, not by a deep search
local function gateArt(id: number): Instance?
	local m = map()
	local art = m and m:FindFirstChild("Art")
	local tunnel = art and art:FindFirstChild("Tunnel")
	local sec = tunnel and tunnel:FindFirstChild("Section" .. id)
	return sec and sec:FindFirstChild("Gate" .. id)
end

local function setBars(id: number, down: boolean)
	local g = gateArt(id)
	local bars = g and g:FindFirstChild("GateBars" .. id)
	if not bars then
		return -- not streamed in yet: try again on the next refresh
	end
	-- each bar remembers (on this screen only) where it is; one streamed in again starts fresh
	for _, bar in bars:GetChildren() do
		local was = bar:GetAttribute("Down")
		if bar:IsA("BasePart") and was ~= down then
			bar:SetAttribute("Down", down)
			local first = was == nil
			local home = bar:GetAttribute("Home") :: CFrame?
			if not home then
				home = bar.CFrame
				bar:SetAttribute("Home", home)
			end
			local goal = if down then (home :: CFrame) - Vector3.new(0, M.gateBarsDrop, 0) else home :: CFrame
			if first or SettingsController.get("reducedMotion") then
				bar.CFrame = goal
			else
				TweenService:Create(bar, TweenInfo.new(M.gateBarsSeconds, Enum.EasingStyle.Quad), { CFrame = goal }):Play()
			end
		end
	end
end

-- a gate sign: what it costs and how close you are, as a bar under the words
local function gateSign(id: number, v: State.View)
	local m = map()
	local sec = m and m:FindFirstChild("Section" .. id) -- WorldService's section: the sign, wall and prompt
	local sign = sec and sec:FindFirstChild("GateSign" .. id)
	local label = sign and sign:FindFirstChild("Text", true)
	local zone = Config.zone(id)
	if not zone or not sign or not sign:IsA("BasePart") or not label or not label:IsA("TextLabel") then
		return
	end
	local price = zone.gateCoins
	local gateBar = gateBars[id]
	if not gateBar or not gateBar.Parent then
		label.Size = UDim2.fromScale(1, 0.7)
		local back = Instance.new("Frame")
		back.Name = "Progress"
		back.AnchorPoint = Vector2.new(0.5, 0)
		back.Position = UDim2.fromScale(0.5, 0.74)
		back.Size = UDim2.fromScale(0.86, 0.2)
		back.BackgroundColor3 = Theme.ink
		Ui.corner(back, 1)
		local fill = Instance.new("Frame")
		fill.Name = "Fill"
		fill.BackgroundColor3 = Theme.coin
		fill.Size = UDim2.fromScale(0, 1)
		Ui.corner(fill, 1)
		fill.Parent = back
		back.Parent = label.Parent
		gateBar = fill
		gateBars[id] = fill
	end
	local open = reachOf(v) >= id
	local needRebirth = not open and zone.ready and v.rebirths < zone.gateRebirth
	local ready = open or (zone.ready and not needRebirth and v.coins >= price)
	local color = if ready then Theme.go else Theme.info
	label.Text = if open then string.upper(zone.name) elseif not zone.ready then "COMING SOON"
		elseif needRebirth then `NEEDS REBIRTH {zone.gateRebirth}` else `OPEN FOR {Ui.commas(price)} COINS`
	label.BackgroundColor3 = color
	sign.Color = color
	local bar = gateBar :: Frame
	local frac = if needRebirth then v.rebirths / math.max(1, zone.gateRebirth) else v.coins / math.max(1, price)
	bar.Size = UDim2.fromScale(if open then 1 else math.clamp(frac, 0, 1), 1)
	bar.BackgroundColor3 = if ready then Theme.go elseif needRebirth then Theme.booths.rebirth else Theme.coin
	local back = bar.Parent :: Frame
	local showBar = not open and zone.ready
	back.Visible = showBar
	label.Size = UDim2.fromScale(1, if showBar then 0.7 else 1)
end

-- the gates' walls: solid until you open them, and never behind you (stand past one and it lets you
-- walk back). Only on this screen; the server's PlayerTracker checks where you really are.
local function gateWalls()
	local m = map()
	local c = me.Character
	local root = c and c:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not m then
		return
	end
	local reach = reachOf(State.view)
	local myZ = if root then root.Position.Z else -math.huge
	for _, z in Config.world.zones do
		local sec = if z.id > 1 then m:FindFirstChild("Section" .. z.id) else nil
		local wall = sec and sec:FindFirstChild("Gate" .. z.id)
		if wall and wall:IsA("BasePart") then
			local open = reach >= z.id or myZ > wall.Position.Z + wall.Size.Z / 2
			if wall.CanCollide == open then
				wall.CanCollide = not open
			end
		end
	end
end

-- your own pan's door lets you through and glows green; every other door stays shut
local function doors(v: State.View?)
	local m = map()
	if not m then
		return
	end
	for i in Config.world.plots do
		local mine = m:GetAttribute("PlotOwner" .. i) == me.UserId or (v ~= nil and v.plot == i)
		local plot = m:FindFirstChild("Plot" .. i)
		local door = plot and plot:FindFirstChild("PanDoor")
		if door and door:IsA("BasePart") then
			door.CanCollide = not mine
		end
		local art = m:FindFirstChild("Art")
		local hubArt = art and art:FindFirstChild("Hub")
		local pan = hubArt and hubArt:FindFirstChild("Pan" .. i)
		local glow = pan and pan:FindFirstChild("DoorGlow")
		if glow and glow:IsA("BasePart") then
			glow.Color = if mine then Theme.go else Theme.hubArt.door
		end
	end
end

local function gift(v: State.View)
	local m = map()
	local box = m and m:FindFirstChild("GiftBox", true)
	if not box or not box:IsA("BasePart") then
		return
	end
	if #giftParts == 0 then
		local art = m and m:FindFirstChild("GiftArt", true)
		for _, p in (if art then art:GetChildren() else {}) do
			if p:IsA("BasePart") then
				table.insert(giftParts, { part = p, cf = p.CFrame })
			end
		end
	end
	if not giftGui then
		local g, b = Ui.pill("", Theme.fx.giftBody, Config.worldText.gift)
		g.Name = "GiftLabel"
		g.StudsOffset = Vector3.new(0, 4.6, 0)
		g.Adornee = box
		g.Parent = me:WaitForChild("PlayerGui")
		giftGui, giftLabel = g, b
	end
	local g, b = giftGui :: BillboardGui, giftLabel :: Ui.Block
	g.Enabled = not v.gift.locked
	local color = if v.gift.ready then Theme.fx.giftBody else Theme.tiers.Common
	Ui.fitPill(g, b, if v.gift.ready then "Daily gift" else "Next gift tomorrow", Config.worldText.gift)
	b.face.BackgroundColor3 = color
	b.root.BackgroundColor3 = Ui.darker(color)
end

local function findGlows()
	local m = map()
	glows = {}
	if m then
		for _, d in m:GetDescendants() do
			if d.Name == "GateGlow" and d:IsA("BasePart") then
				d:SetAttribute("BaseTransparency", d:GetAttribute("BaseTransparency") or d.Transparency)
				table.insert(glows, d)
			end
		end
	end
end

-- each island's own light: tint and haze fade to the section you're standing in
local function islandLight()
	local c = me.Character
	local root = c and c:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	local zone = WorldRules.zoneAt(root.Position)
	if zone == lightZone then
		return
	end
	lightZone = zone
	local tint, haze = Theme.hubTint, Theme.ice
	if zone > 0 then
		local z = Config.zone(zone)
		for _, isl in Config.world.islands do
			if z and isl.key == z.key then
				local look = Theme.islands[isl.theme]
				if look then
					tint, haze = look.tint, look.haze
				end
			end
		end
	end
	local seconds = if SettingsController.get("reducedMotion") then M.lightTweenSeconds * 0.5 else M.lightTweenSeconds
	local cc = Lighting:FindFirstChildOfClass("ColorCorrectionEffect")
	if cc then
		TweenService:Create(cc, TweenInfo.new(seconds), { TintColor = tint }):Play()
	end
	local atmo = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmo then
		TweenService:Create(atmo, TweenInfo.new(seconds), { Color = haze }):Play()
	end
end

local function refresh(v: State.View)
	local reach = reachOf(v)
	local m = map()
	for _, z in Config.world.zones do
		if z.id > 1 then
			setBars(z.id, reach >= z.id)
			gateSign(z.id, v)
			-- a "Coming soon" gate's frosted glass clears once a tester has opened it
			local g = gateArt(z.id)
			local panel = g and g:FindFirstChild("SoonPanel" .. z.id)
			if panel and panel:IsA("BasePart") then
				panel.LocalTransparencyModifier = if reach >= z.id then 1 else 0
			end
		end
	end
	gift(v)
	doors(v)
end

function MapController.Init() end

function MapController.Start()
	State.Changed:Connect(refresh)
	if State.view then
		refresh(State.view)
	end
	findGlows()
	-- map parts can stream in late: look again now and then (cheap)
	task.spawn(function()
		while true do
			task.wait(1)
			if State.view then
				refresh(State.view)
			end
			if #glows == 0 then
				findGlows()
			end
		end
	end)
	RunService.Heartbeat:Connect(gateWalls)
	RunService.RenderStepped:Connect(function()
		local t = os.clock()
		local v = State.view
		local still = SettingsController.get("reducedMotion") == true
		local bob = v ~= nil and v.gift.ready and not still
		local c = Config.world.giftBox
		local pivot = CFrame.new(c.X, 0, c.Z)
		local move = if bob then pivot * CFrame.new(0, math.abs(math.sin(t * 3)) * M.giftBob, 0) * CFrame.Angles(0, math.sin(t * 2) * M.giftSway, 0) * pivot:Inverse() else CFrame.identity
		for _, g in giftParts do
			g.part.CFrame = move * g.cf -- the whole box hops and sways round its middle
		end
		-- the gates breathe slowly (well under the 3 flashes a second limit); still with reduced motion
		local breath = if still then 0 else (math.sin(t * math.pi * 2 / M.gateGlowPulse) * 0.5 + 0.5) * 0.35
		for _, g in glows do
			local base = g:GetAttribute("BaseTransparency")
			g.Transparency = (if typeof(base) == "number" then base else 0) + breath
		end
		islandLight()
	end)
end

return MapController
