--!strict
-- Ui: small builders for the Chunky Pop look (UI Rules): a block is a coloured face on a darker lip
-- with one thick ink outline; pressing pushes the face down, then it springs back.
-- Builders only make instances; the Screen module decides where HUD pieces go.

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Theme = require(ReplicatedStorage.Shared.Theme)

local Ui = {}

function Ui.darker(c: Color3): Color3
	local h, s, v = c:ToHSV()
	return Color3.fromHSV(h, s, v * (1 - Theme.lipDarken))
end

function Ui.corner(parent: Instance, scale: number?)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(scale or Config.ui.corner, 0)
	c.Parent = parent
end

function Ui.stroke(parent: Instance, thickness: number?)
	local s = Instance.new("UIStroke")
	s.Color = Theme.ink
	s.Thickness = thickness or Config.ui.stroke
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.LineJoinMode = Enum.LineJoinMode.Miter
	s.Parent = parent
end

-- white text with a dark outline (readable over anything)
function Ui.label(parent: Instance, text: string, size: UDim2?, pos: UDim2?): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = size or UDim2.fromScale(1, 1)
	t.Position = pos or UDim2.fromScale(0, 0)
	t.Font = Theme.font
	t.TextScaled = true
	t.TextColor3 = Theme.white
	t.Text = text
	local s = Instance.new("UIStroke")
	s.Color = Theme.ink
	s.Thickness = 2
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	s.Parent = t
	t.Parent = parent
	return t
end

export type Block = { root: Frame, face: TextButton, text: TextLabel }

-- a pressable block; onPress runs on click / tap / gamepad A
function Ui.block(parent: Instance, name: string, color: Color3, text: string, onPress: (() -> ())?): Block
	local root = Instance.new("Frame")
	root.Name = name
	root.BackgroundColor3 = Ui.darker(color) -- the lip
	root.BorderSizePixel = 0
	Ui.corner(root)
	Ui.stroke(root)
	local face = Instance.new("TextButton")
	face.Name = "Face"
	face.Text = ""
	face.AutoButtonColor = false
	face.BackgroundColor3 = color
	face.BorderSizePixel = 0
	face.Size = UDim2.fromScale(1, 1 - Config.ui.pressDepth * 1.5)
	face.Selectable = onPress ~= nil
	Ui.corner(face)
	local shine = Instance.new("UIGradient") -- the soft top shine
	shine.Rotation = 90
	shine.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 0.25) })
	shine.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.new(0.85, 0.85, 0.85))
	shine.Parent = face
	face.Parent = root
	local label = Ui.label(face, text, UDim2.fromScale(0.9, 0.8), UDim2.fromScale(0.05, 0.1))
	root.Parent = parent
	if onPress then
		local up = face.Size
		local down = UDim2.new(up.X, UDim.new(up.Y.Scale, 0))
		local info = TweenInfo.new(Config.ui.pressSeconds)
		face.Activated:Connect(function()
			face.Position = UDim2.fromScale(0, Config.ui.pressDepth)
			face.Size = down
			TweenService:Create(face, info, { Position = UDim2.fromScale(0, 0), Size = up }):Play()
			onPress()
		end)
	end
	return { root = root, face = face, text = label }
end

-- 12,400 / 1.2K / 3.4M: short numbers for small spaces
function Ui.short(n: number): string
	n = math.floor(n)
	if n < 10000 then
		return Ui.commas(n)
	end
	local units: { { size: number, suffix: string } } = {
		{ size = 1e12, suffix = "T" }, { size = 1e9, suffix = "B" }, { size = 1e6, suffix = "M" }, { size = 1e3, suffix = "K" },
	}
	for _, u in units do
		if n >= u.size then
			local text = string.format("%.1f", n / u.size):gsub("%.0$", "")
			return text .. u.suffix
		end
	end
	return tostring(n)
end

function Ui.commas(n: number): string
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

return Ui
