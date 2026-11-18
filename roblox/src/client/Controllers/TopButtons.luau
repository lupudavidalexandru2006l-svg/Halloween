--!strict
-- TopButtons (owner 2026-11-12, from a reference): chunky labelled blocks at the very top, inside Roblox's
-- top bar (owner 2026-11-13; Screen falls back to the top centre where there is no top bar), that
-- take you somewhere in the hub (Config.ui.topButtons; TravelService decides). Equipment wears its
-- booth's blue; Pan is plain soil brown (owner 2026-11-12: no green strip on top, green means "go"). They go away while a cube
-- is in your hands ("GunLocked") and come back as soon as your hands are empty again: banked, melted or
-- grabbed by a Heat Critter (owner 2026-11-18: they waited until you walked into your pan, so after a critter
-- took your cube Pan and Equipment seemed broken). Screen places them (and hides them while a popup is open).

local Players = game:GetService("Players")
local TextService = game:GetService("TextService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Theme = require(ReplicatedStorage.Shared.Theme)
local Ui = require(script.Parent.Parent.Lib.Ui)
local State = require(script.Parent.State)
local Screen = require(script.Parent.Screen)
local SoundController = require(script.Parent.SoundController)

local TopButtons = {}
local TB = Config.ui.topButtons
local me = Players.LocalPlayer
local frame: Frame
local away = false -- a cube is in your hands: hidden until they're empty
local labels: { TextLabel } = {}
local widthPer100: { [TextLabel]: number } = {} -- each word's width at text size 100

-- owner 2026-11-13: "PAN is bigger than EQUIPMENT". TextScaled grew the short word; now every label
-- uses the one size the longest word still fits at.
local function syncTextSize()
	local size = math.huge
	-- the menus' pop-in (Screen.lockMenus' UnlockPop UIScale) shrinks every AbsoluteSize while it plays: undo it,
	-- or the words were measured at 30% and stayed tiny (QA 2026-11-16, after the tutorial unlocked the menus)
	local pop = frame and frame:FindFirstChild("UnlockPop") :: UIScale?
	local k = if pop and pop.Scale > 0.05 then pop.Scale else 1
	for _, l in labels do
		local box = l.AbsoluteSize / k
		local w = widthPer100[l]
		if box.X <= 0 or not w then
			return
		end
		size = math.min(size, box.Y, box.X / w * 100)
	end
	for _, l in labels do
		l.TextScaled = false
		l.TextSize = math.floor(size)
	end
end

local function measure(l: TextLabel)
	local p = Instance.new("GetTextBoundsParams")
	p.Text = l.Text
	p.Font = l.FontFace
	p.Size = 100
	p.Width = 1e5
	local ok, bounds = pcall(TextService.GetTextBoundsAsync, TextService, p)
	widthPer100[l] = if ok then bounds.X * 1.06 else #l.Text * 62 -- a little room for the outline
end

local lockedAt = 0
local function update()
	-- hidden only once the cube has flown into your hands (owner 2026-11-16: it vanished before the cube arrived)
	local carrying = me:GetAttribute("GunLocked") == true and os.clock() - lockedAt >= Config.show.freeze.flySeconds
	if carrying then
		away = true
	elseif away and me:GetAttribute("GunLocked") ~= true then
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
	table.insert(labels, block.text)
	block.text:GetPropertyChangedSignal("AbsoluteSize"):Connect(syncTextSize)
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
	task.spawn(function()
		for _, l in labels do
			measure(l)
		end
		syncTextSize()
	end)
	me:GetAttributeChangedSignal("GunLocked"):Connect(function()
		if me:GetAttribute("GunLocked") == true then
			lockedAt = os.clock()
			task.delay(Config.show.freeze.flySeconds + 0.02, update)
		end
		update()
	end)
	task.spawn(function()
		while true do
			update()
			task.wait(0.25)
		end
	end)
end

return TopButtons
