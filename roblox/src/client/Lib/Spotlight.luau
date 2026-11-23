--!strict
-- Spotlight (owner 2026-11-21): the tutorial darkens the whole screen except one button, with a pulsing white ring
-- round it, so a new player sees exactly what to press ("a black transparent thing over the whole gameplay and the
-- equipment button you should see"). Four dark panes frame the hole; they swallow clicks, the hole lets them
-- through. Spotlight.show(button) each frame; Spotlight.show(nil) hides it.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Spotlight = {}

local DIM = 0.45 -- pane transparency: the game still shows through
local PAD = 8 -- pixels of room round the button

local gui: ScreenGui? = nil
local panes: { Frame } = {}
local ring: Frame
local pulse: Tween? = nil

local function build()
	local g = Instance.new("ScreenGui")
	g.Name = "Spotlight"
	g.ResetOnSpawn = false
	g.DisplayOrder = 15 -- over the HUD and the popups, under the screen flash
	g.IgnoreGuiInset = true
	g.ScreenInsets = Enum.ScreenInsets.None
	g.Enabled = false
	for i = 1, 4 do
		local f = Instance.new("Frame")
		f.Name = "Pane" .. i
		f.BackgroundColor3 = Color3.new(0, 0, 0)
		f.BackgroundTransparency = DIM
		f.BorderSizePixel = 0
		f.Active = true -- swallows clicks outside the hole
		f.Parent = g
		panes[i] = f
	end
	ring = Instance.new("Frame")
	ring.Name = "Ring"
	ring.BackgroundTransparency = 1
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0.3, 0)
	c.Parent = ring
	local s = Instance.new("UIStroke")
	s.Color = Color3.new(1, 1, 1)
	s.Thickness = 4
	s.Parent = ring
	local sc = Instance.new("UIScale")
	sc.Parent = ring
	ring.Parent = g
	pulse = TweenService:Create(sc, TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Scale = 1.12 })
	g.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	gui = g
	return g
end

-- ringOnly (owner 2026-11-22: "after you press it, you can see the gameplay"): no dark panes, just the ring
function Spotlight.show(target: GuiObject?, ringOnly: boolean?)
	local g = gui or (if target then build() else nil)
	if not g then
		return
	end
	-- off screen too (the top buttons slide up while a popup is open): no dark screen over nothing
	local onScreen = target ~= nil and target.AbsolutePosition.Y + target.AbsoluteSize.Y > 0
	if not target or not onScreen or not target.Visible or target.AbsoluteSize.X <= 0 then
		if g.Enabled then
			g.Enabled = false
			if pulse then
				pulse:Cancel()
			end
		end
		return
	end
	local pos = target.AbsolutePosition - g.AbsolutePosition
	local size = target.AbsoluteSize
	local x0, y0 = pos.X - PAD, pos.Y - PAD
	local x1, y1 = pos.X + size.X + PAD, pos.Y + size.Y + PAD
	local w, h = g.AbsoluteSize.X, g.AbsoluteSize.Y
	-- top, bottom, left, right of the hole
	panes[1].Position, panes[1].Size = UDim2.fromOffset(0, 0), UDim2.fromOffset(w, math.max(0, y0))
	panes[2].Position, panes[2].Size = UDim2.fromOffset(0, y1), UDim2.fromOffset(w, math.max(0, h - y1))
	panes[3].Position, panes[3].Size = UDim2.fromOffset(0, y0), UDim2.fromOffset(math.max(0, x0), y1 - y0)
	panes[4].Position, panes[4].Size = UDim2.fromOffset(x1, y0), UDim2.fromOffset(math.max(0, w - x1), y1 - y0)
	for _, f in panes do
		f.Visible = not ringOnly
	end
	-- over a light popup a white ring disappears: ring-only mode glows yellow (QA 2026-11-22)
	local stroke = ring:FindFirstChildOfClass("UIStroke") :: UIStroke
	stroke.Color = if ringOnly then Color3.fromRGB(255, 214, 10) else Color3.new(1, 1, 1)
	stroke.Thickness = if ringOnly then 6 else 4
	ring.Position = UDim2.fromOffset((x0 + x1) / 2, (y0 + y1) / 2)
	ring.Size = UDim2.fromOffset(x1 - x0, y1 - y0)
	if not g.Enabled then
		g.Enabled = true
		if pulse then
			pulse:Play()
		end
	end
end

return Spotlight
