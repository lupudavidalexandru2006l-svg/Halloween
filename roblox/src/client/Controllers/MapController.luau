--!strict
-- MapController: what this player sees of the map's state (prototype client.js render), all local:
--  - the Forest gate's ice bars slide into the ground once you've opened it
--  - the gate sign says "OPEN FOR 1000 COINS" (green when you can pay) until then, "PINE FOREST" after
--  - the gift box bobs while a gift waits, with a "DAILY GIFT" / "NEXT GIFT TOMORROW" label
--  - the ice bridge flashes in its last seconds
-- The server owns the real gate, gift and bridge; this only draws them.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Theme = require(ReplicatedStorage.Shared.Theme)
local Ui = require(script.Parent.Parent.Lib.Ui)
local State = require(script.Parent.State)
local SettingsController = require(script.Parent.SettingsController)

local MapController = {}
local M = Config.mapFx
local barsDown: boolean? = nil
local giftParts: { { part: BasePart, cf: CFrame } } = {}
local giftLabel: Ui.Block? = nil
local giftGui: BillboardGui? = nil
local bridgeUntil = 0

local function map(): Instance?
	return workspace:FindFirstChild("Map")
end

local function setBars(down: boolean)
	if barsDown == down then
		return
	end
	local first = barsDown == nil
	barsDown = down
	local m = map()
	local bars = m and m:FindFirstChild("GateBars", true)
	if not bars then
		barsDown = nil
		return
	end
	for _, bar in bars:GetChildren() do
		if bar:IsA("BasePart") then
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

local function gateSign(v: State.View)
	local m = map()
	local sign = m and m:FindFirstChild("GateSign", true)
	local label = sign and sign:FindFirstChild("Text", true)
	if not sign or not sign:IsA("BasePart") or not label or not label:IsA("TextLabel") then
		return
	end
	local price = (Config.zone(2) :: Config.Zone).gateCoins
	local color = if v.forestUnlocked or v.coins >= price then Theme.go else Theme.info
	label.Text = if v.forestUnlocked then "PINE FOREST" else `OPEN FOR {Ui.commas(price)} COINS`
	label.BackgroundColor3 = color
	sign.Color = color
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
		local g = Instance.new("BillboardGui")
		g.Name = "GiftLabel"
		g.Size = UDim2.fromScale(6.5, 1.7)
		g.StudsOffset = Vector3.new(0, 4.6, 0)
		g.Adornee = box
		g.MaxDistance = 80
		g.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
		local b = Ui.block(g, "Label", Theme.fx.giftBody, "", nil)
		b.root.Size = UDim2.fromScale(1, 1)
		giftGui, giftLabel = g, b
	end
	local g, b = giftGui :: BillboardGui, giftLabel :: Ui.Block
	g.Enabled = not v.gift.locked
	local color = if v.gift.ready then Theme.fx.giftBody else Theme.tiers.Common
	b.text.Text = if v.gift.ready then "DAILY GIFT" else "NEXT GIFT TOMORROW"
	b.face.BackgroundColor3 = color
	b.root.BackgroundColor3 = Ui.darker(color)
end

local function refresh(v: State.View)
	setBars(v.forestUnlocked)
	gateSign(v)
	gift(v)
end

function MapController.Init() end

function MapController.Start()
	State.Changed:Connect(refresh)
	if State.view then
		refresh(State.view)
	end
	State.Notify:Connect(function(kind: string, data: any)
		if kind == "bridge" and typeof(data.seconds) == "number" then
			bridgeUntil = os.clock() + data.seconds
		end
	end)
	RunService.RenderStepped:Connect(function()
		local t = os.clock()
		local v = State.view
		local bob = v ~= nil and v.gift.ready and not SettingsController.get("reducedMotion")
		local c = Config.world.giftBox
		local pivot = CFrame.new(c.X, 0, c.Z)
		local move = if bob then pivot * CFrame.new(0, math.abs(math.sin(t * 3)) * M.giftBob, 0) * CFrame.Angles(0, math.sin(t * 2) * M.giftSway, 0) * pivot:Inverse() else CFrame.identity
		for _, g in giftParts do
			g.part.CFrame = move * g.cf -- the whole box hops and sways round its middle
		end
		-- the ice bridge blinks in its last seconds, so nobody is surprised by the splash
		local m = map()
		local bridge = m and m:FindFirstChild("IceBridge", true)
		if bridge and bridge:IsA("BasePart") then
			local left = bridgeUntil - t
			bridge.LocalTransparencyModifier = if left > 0 and left < M.bridgeFlashSeconds and math.sin(t * 12) > 0 then 0.6 else 0
		end
	end)
end

return MapController
