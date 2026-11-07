--!strict
-- Ui: small builders for the Chunky Pop look (UI Rules): a block is a coloured face on a darker lip
-- with one thick ink outline; pressing pushes the face down, then it springs back.
-- Builders only make instances; the Screen module decides where HUD pieces go.

local TweenService = game:GetService("TweenService")
local TextService = game:GetService("TextService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Theme = require(ReplicatedStorage.Shared.Theme)

local Ui = {}

-- the lip colour: the face colour mixed toward ink (the demo's look; only dimming it went muddy grey)
function Ui.darker(c: Color3): Color3
	return c:Lerp(Theme.ink, Theme.lipDarken)
end

-- no scale = the one shared radius: a fixed share of the screen's short side, the same on a button,
-- a card and a popup. (A share of each block's own size made big panels almost pill-shaped next to
-- small buttons, QA 2026-10-31.) A scale (0.5 = pill, 1 = circle) is for shapes that should stay round.
function Ui.corner(parent: Instance, scale: number?)
	local c = Instance.new("UICorner")
	if scale then
		c.CornerRadius = UDim.new(scale, 0)
	else
		local cam = workspace.CurrentCamera
		local short = if cam then math.min(cam.ViewportSize.X, cam.ViewportSize.Y) else 720
		c.CornerRadius = UDim.new(0, math.max(4, math.round(short * Config.ui.radius)))
	end
	c.Parent = parent
end

function Ui.stroke(parent: Instance, thickness: number?)
	local s = Instance.new("UIStroke")
	s.Color = Theme.ink
	s.Thickness = thickness or Config.ui.stroke
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.LineJoinMode = Enum.LineJoinMode.Round -- Miter draws square dark corners around a rounded block
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
	s.Thickness = Config.ui.textStroke
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	s.LineJoinMode = Enum.LineJoinMode.Round
	s.Parent = t
	t.Parent = parent
	return t
end

-- dark text with no outline, for light panels (the cream popup body, signs): white on cream washes out
function Ui.inkLabel(parent: Instance, text: string, size: UDim2?, pos: UDim2?): TextLabel
	local t = Ui.label(parent, text, size, pos)
	t.TextColor3 = Theme.ink
	local stroke = t:FindFirstChildOfClass("UIStroke") :: UIStroke
	stroke.Enabled = false
	return t
end

-- a painted icon or sprite (uploaded image), kept square; silhouette = a dark shape for "not found yet"
function Ui.image(parent: Instance, image: string, size: UDim2, pos: UDim2, silhouette: boolean?): ImageLabel
	local i = Instance.new("ImageLabel")
	i.Name = "Icon"
	i.BackgroundTransparency = 1
	i.Image = image
	i.Size = size
	-- centred in the box it's given: the square constraint shrinks one side, and anchored at the
	-- top-left the picture hugged the box's left edge (owner 2026-10-31: centre all the icons)
	i.AnchorPoint = Vector2.new(0.5, 0.5)
	i.Position = UDim2.fromScale(pos.X.Scale + size.X.Scale / 2, pos.Y.Scale + size.Y.Scale / 2)
	i.ScaleType = Enum.ScaleType.Fit
	if silhouette then
		i.ImageColor3 = Theme.silhouette -- solid black: the shape only, no colours showing through (owner 2026-10-31)
		i.ImageTransparency = Config.ui.silhouetteTransparency
	end
	local a = Instance.new("UIAspectRatioConstraint")
	a.AspectRatio = 1
	a.Parent = i
	i.Parent = parent
	return i
end

export type Block = { root: Frame, face: TextButton, text: TextLabel }

-- the face's dressing: a lighter top fading into the colour, a soft shade toward the lip, and a thin
-- bevel line inside the edge. All under the icons and text (ZIndex 0).
-- QA 2026-10-31: the old grey-and-see-through gradient made every tile look dirty at the bottom; the
-- owner then called the dot pattern + gloss band "very AI", so those are gone.
local function dress(face: GuiObject)
	local F = Config.ui.face
	local function layer(name: string): Frame
		local f = Instance.new("Frame")
		f.Name = name
		f.BackgroundColor3 = Theme.white
		f.BorderSizePixel = 0
		f.ZIndex = 0
		f.Parent = face
		return f
	end
	local light = layer("Light")
	light.Size = UDim2.fromScale(1, 1)
	Ui.corner(light)
	local lg = Instance.new("UIGradient")
	lg.Rotation = 90
	lg.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, F.topLight), NumberSequenceKeypoint.new(0.55, 1), NumberSequenceKeypoint.new(1, 1),
	})
	lg.Parent = light
	-- depth: a soft ink shade over the lower part, so the colour gets richer toward the lip
	local shade = layer("Shade")
	shade.BackgroundColor3 = Theme.ink
	shade.Size = UDim2.fromScale(1, 1)
	Ui.corner(shade)
	local sg = Instance.new("UIGradient")
	sg.Rotation = 90
	sg.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 1), NumberSequenceKeypoint.new(1, F.bottomShade),
	})
	sg.Parent = shade
	-- bevel: a thin white line just inside the outline, brightest along the top
	local rim = layer("Rim")
	rim.BackgroundTransparency = 1
	rim.AnchorPoint = Vector2.new(0.5, 0.5)
	rim.Position = UDim2.fromScale(0.5, 0.5)
	rim.Size = UDim2.fromScale(1 - F.rimInset * 2, 1 - F.rimInset * 2)
	Ui.corner(rim)
	local rs = Instance.new("UIStroke")
	rs.Color = Theme.white
	rs.Thickness = F.rimThickness
	rs.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	rs.LineJoinMode = Enum.LineJoinMode.Round
	rs.Parent = rim
	local rg = Instance.new("UIGradient")
	rg.Rotation = 90
	rg.Transparency = NumberSequence.new(F.rimTop, 1)
	rg.Parent = rs
end

-- a pressable block; onPress runs on click / tap / gamepad A. plain = no dressing (big panels and
-- list cards, where the content should be the loudest thing)
function Ui.block(parent: Instance, name: string, color: Color3, text: string, onPress: (() -> ())?, plain: boolean?): Block
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
	-- the lip is the same few pixels on every block (a share of the screen's short side), worked out
	-- as Scale of this block's height, so a big popup panel doesn't get a thick slab under it
	local function lipShare(): number
		local cam = workspace.CurrentCamera
		local short = if cam then math.min(cam.ViewportSize.X, cam.ViewportSize.Y) else 720
		return math.clamp(short * Config.ui.lipDepth / math.max(1, root.AbsoluteSize.Y), 0.02, 0.15)
	end
	local pressing = false
	local function fit()
		if not pressing then
			face.Size = UDim2.fromScale(1, 1 - lipShare())
		end
	end
	root:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	face.Size = UDim2.fromScale(1, 1 - Config.ui.pressDepth * 1.5)
	face.Selectable = onPress ~= nil
	Ui.corner(face) -- one outline only, round the whole block (a second one on the face made every edge heavy)
	if not plain then
		dress(face)
	end
	face.Parent = root
	local label = Ui.label(face, text, UDim2.fromScale(0.9, 0.8), UDim2.fromScale(0.05, 0.1))
	root.Parent = parent
	if onPress then
		local info = TweenInfo.new(Config.ui.pressSeconds)
		face.Activated:Connect(function()
			-- the face drops onto the lip, then springs back up
			local lip = lipShare()
			pressing = true
			face.Position = UDim2.fromScale(0, lip)
			face.Size = UDim2.fromScale(1, 1 - lip)
			local back = TweenService:Create(face, info, { Position = UDim2.fromScale(0, 0) })
			back.Completed:Connect(function()
				pressing = false
				fit()
			end)
			back:Play()
			onPress()
		end)
	end
	return { root = root, face = face, text = label }
end

-- a world label as a Chunky Pop pill: a BillboardGui sized in pixels (the same size on screen at
-- any distance, unlike stud sizes that shrank far-off names to smudges), fitted to its text.
-- spec = Config.worldText.tag / .gift. Returns the gui and the block (to recolour or retext it).
function Ui.pill(text: string, color: Color3, spec: { textPx: number, heightPx: number, padPx: number, maxDistance: number }): (BillboardGui, Block)
	local g = Instance.new("BillboardGui")
	g.MaxDistance = spec.maxDistance
	g.LightInfluence = 0
	local b = Ui.block(g, "Pill", color, text, nil)
	b.root.Size = UDim2.fromScale(1, 1)
	b.text.Size = UDim2.fromScale(1, 0.84)
	b.text.Position = UDim2.fromScale(0, 0.08)
	b.text.TextScaled = false
	b.text.TextSize = spec.textPx
	local s = b.text:FindFirstChildOfClass("UIStroke") :: UIStroke
	s.Thickness = math.max(1, spec.textPx * Config.worldText.outlineRatio)
	for _, part in { b.root, b.face } do
		local c = part:FindFirstChildOfClass("UICorner") :: UICorner
		c.CornerRadius = UDim.new(0.5, 0) -- fully round ends
	end
	Ui.fitPill(g, b, text, spec)
	return g, b
end

-- re-fit a pill after its text changes
function Ui.fitPill(g: BillboardGui, b: Block, text: string, spec: { textPx: number, heightPx: number, padPx: number })
	b.text.Text = text
	local w = TextService:GetTextSize(text, spec.textPx, Theme.font, Vector2.new(1000, 100)).X
	g.Size = UDim2.fromOffset(w + spec.padPx * 2, spec.heightPx)
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

-- a price: 750 / 2.5K / 1.2M (owner 2026-11-07: prices read short, never 2,500,000). Config.coinText
-- so the server's "Need 1.2M more" reads the same
function Ui.price(n: number): string
	return Config.coinText(n)
end

function Ui.commas(n: number): string
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

return Ui
