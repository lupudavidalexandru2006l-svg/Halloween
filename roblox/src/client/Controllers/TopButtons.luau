--!strict
-- TopButtons (owner 2026-11-12, from a reference): chunky labelled blocks at the very top, inside Roblox's
-- top bar (owner 2026-11-13; Screen falls back to the top centre where there is no top bar), that
-- take you somewhere in the hub (Config.ui.topButtons; TravelService decides). Equipment wears its
-- booth's blue; Pan is plain soil brown (owner 2026-11-12: no green strip on top, green means "go"). They go away while a cube
-- is in your hands ("GunLocked") and come back only once you've walked into your own pan with empty
-- hands. Screen places them (and hides them while a popup is open).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Theme = require(ReplicatedStorage.Shared.Theme)
local WorldRules = require(ReplicatedStorage.Shared.WorldRules)
local Ui = require(script.Parent.Parent.Lib.Ui)
local State = require(script.Parent.State)
local Screen = require(script.Parent.Screen)
local SoundController = require(script.Parent.SoundController)

local TopButtons = {}
local TB = Config.ui.topButtons
local me = Players.LocalPlayer
local frame: Frame
local away = false -- a cube was in your hands: hidden until you're home

local function inMyPan(): boolean
	local v = State.view
	local plot = v and v.plot
	local hrp = me.Character and me.Character:FindFirstChild("HumanoidRootPart")
	return plot ~= nil and hrp ~= nil and hrp:IsA("BasePart") and WorldRules.inPlot(plot, hrp.Position)
end

local function update()
	local carrying = me:GetAttribute("GunLocked") == true
	if carrying then
		away = true
	elseif away and inMyPan() then
		away = false
	end
	local want = not away
	if frame:GetAttribute("Want") ~= want then
		frame:SetAttribute("Want", want)
	end
end

local function makeButton(i: number, b: { id: string, label: string, icon: string })
	local n = #TB.list
	local colour = if b.id == "pan" then Theme.topButtons.soil else Theme.topButtons.equipment
	local block = Ui.block(frame, "Top_" .. b.id, colour, b.label, function()
		SoundController.play("click")
		State.send("Teleport", b.id)
	end)
	-- each button's share of the row, the gap between them a share of the same short-side units
	local unit = 1 / (n * TB.size[1] + (n - 1) * TB.gap)
	block.root.Size = UDim2.fromScale(TB.size[1] * unit, 1)
	block.root.Position = UDim2.fromScale((i - 1) * (TB.size[1] + TB.gap) * unit, 0)
	local icon = Config.images.icons[b.icon]
	if icon then
		local img = Ui.image(block.face, icon, UDim2.fromScale(0.3, TB.iconSize), UDim2.fromScale(0.02, (1 - TB.iconSize) / 2))
		img.ZIndex = 2
	end
	block.text.Size = UDim2.fromScale(0.68, 0.78)
	block.text.Position = UDim2.fromScale(0.28, 0.11)
	block.text.ZIndex = 2
	local s = block.text:FindFirstChildOfClass("UIStroke") :: UIStroke
	s.Thickness = Config.ui.floatingStroke -- big words over a busy face read with a firmer outline
end

function TopButtons.Init() end

function TopButtons.Start()
	frame = Instance.new("Frame")
	frame.Name = "TopButtons"
	frame.BackgroundTransparency = 1
	frame:SetAttribute("Want", true)
	for i, b in TB.list do
		makeButton(i, b)
	end
	Screen.register("top", frame)
	me:GetAttributeChangedSignal("GunLocked"):Connect(update)
	task.spawn(function()
		while true do
			update()
			task.wait(0.25)
		end
	end)
end

return TopButtons
