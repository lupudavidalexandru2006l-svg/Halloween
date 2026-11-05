--!strict
-- WorldText: the one look for text out in the 3D world (zone signs, leaderboards, pen and gate signs,
-- pet name tags, the gift label). Server and client both use it, so a server-built sign and a
-- client-built sign match. The rules (UI Rules, 2026-10-31):
--  - crisp: SurfaceGuis render at Config.worldText.pixelsPerStud (40 looked soft and blurry up close)
--  - one fixed text size per role, given in studs, never TextScaled per label (rows came out in
--    different sizes and "60.0%" dwarfed "Common")
--  - the outline grows with the text (a fixed 2 px was too thin on big signs, too thick on tags)

local Config = require(script.Parent.Config)
local Theme = require(script.Parent.Theme)

local W = Config.worldText
local WorldText = {}

-- a size in studs as pixels on a SurfaceGui
function WorldText.px(studs: number): number
	return studs * W.pixelsPerStud
end

-- a SurfaceGui on one face of a part at the shared resolution; also returns its canvas size in pixels
function WorldText.surface(part: BasePart, name: string, face: Enum.NormalId?): (SurfaceGui, Vector2)
	local f = face or Enum.NormalId.Front
	local sg = Instance.new("SurfaceGui")
	sg.Name = name
	sg.Face = f
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = W.pixelsPerStud
	sg.LightInfluence = W.lightInfluence
	local s = part.Size
	local w, h = s.X, s.Y
	if f == Enum.NormalId.Left or f == Enum.NormalId.Right then
		w = s.Z
	elseif f == Enum.NormalId.Top or f == Enum.NormalId.Bottom then
		h = s.Z
	end
	return sg, Vector2.new(w, h) * W.pixelsPerStud
end

-- font, a fixed pixel size and an outline in proportion (outline = false for dark text on light boards)
function WorldText.style(t: TextLabel, sizePx: number, color: Color3?, outline: boolean?)
	t.Font = Theme.font
	t.TextScaled = false
	t.TextWrapped = false
	t.TextSize = sizePx
	if color then
		t.TextColor3 = color
	end
	local s = t:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke")
	s.Color = Theme.ink
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	s.LineJoinMode = Enum.LineJoinMode.Round
	s.Thickness = math.max(1, sizePx * W.outlineRatio)
	s.Enabled = outline ~= false
	s.Parent = t
end

-- a transparent label filling its parent unless size/pos say otherwise
function WorldText.label(parent: Instance, text: string, sizePx: number, color: Color3?, outline: boolean?, size: UDim2?, pos: UDim2?): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = size or UDim2.fromScale(1, 1)
	t.Position = pos or UDim2.fromScale(0, 0)
	t.Text = text
	WorldText.style(t, sizePx, color or Theme.white, outline)
	t.Parent = parent
	return t
end

-- a sign whose text changes (pen owner names, the gate price): fills the board, shrinks only when a
-- long name wouldn't fit, never grows past maxPx; the outline follows maxPx
function WorldText.fitSign(sg: SurfaceGui, t: TextLabel, maxPx: number)
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = W.pixelsPerStud
	-- Roblox caps text at 100 px: letters taller than 1 stud need a coarser canvas (2026-11-02: every
	-- big sign was stuck at 1-stud letters, and the biggest canvases didn't draw at all)
	if maxPx > 100 then
		sg.PixelsPerStud = W.pixelsPerStud * 100 / maxPx
		maxPx = 100
	end
	sg.LightInfluence = W.lightInfluence
	WorldText.style(t, maxPx, nil, true)
	t.TextScaled = true
	local c = t:FindFirstChildOfClass("UITextSizeConstraint") or Instance.new("UITextSizeConstraint")
	c.MaxTextSize = math.floor(maxPx)
	c.Parent = t
	local pad = t:FindFirstChildOfClass("UIPadding") or Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(W.signPadding, 0)
	pad.PaddingRight = UDim.new(W.signPadding, 0)
	pad.PaddingTop = UDim.new(W.signPadding, 0)
	pad.PaddingBottom = UDim.new(W.signPadding, 0)
	pad.Parent = t
end

return WorldText
