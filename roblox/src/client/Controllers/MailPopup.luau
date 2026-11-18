--!strict
-- MailPopup (owner 2026-11-17 night): the Feedback mailbox's popup. Four big mood tiles with pictures (Love it,
-- Idea, Too hard, Bug: Config.feedback.kinds), an optional short message, one green Send. Icons first, few words.
-- The client only sends intent ("SendFeedback", kind, text); FeedbackService checks, filters and saves it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Theme = require(ReplicatedStorage.Shared.Theme)
local Ui = require(script.Parent.Parent.Lib.Ui)
local State = require(script.Parent.State)
local SoundController = require(script.Parent.SoundController)
local EquipmentPopup = require(script.Parent.EquipmentPopup)

local MailPopup = {}
local F = Config.feedback
local picked: string? = nil -- kept while the popup redraws
local draft = ""

function MailPopup.sent()
	picked, draft = nil, ""
end

function MailPopup.fill(o: any, _v: State.View, h: EquipmentPopup.Helpers)
	local head = h.text(o.body, "How do you like the game?", 0, 1, Theme.infoDeep, "body")
	head.TextXAlignment = Enum.TextXAlignment.Center
	head.Position = UDim2.fromScale(0, 0)
	head.Size = UDim2.fromScale(1, 0.1)
	-- the mood tiles: big pictures, one word each; the picked one is bigger with a white outline
	local tiles = Instance.new("Frame")
	tiles.Name = "Moods"
	tiles.BackgroundTransparency = 1
	tiles.Position = UDim2.fromScale(0, 0.12)
	tiles.Size = UDim2.fromScale(1, 0.36)
	tiles.Parent = o.body
	local n = #F.kinds
	local gap = 0.025
	local w = (1 - gap * (n - 1)) / n
	for i, k in F.kinds do
		local color = (Theme :: any)[k.color] or Theme.info
		local on = picked == k.id
		local b = Ui.block(tiles, "Mood_" .. k.id, if picked and not on then color:Lerp(Theme.white, 0.45) else color, k.label, function()
			SoundController.play("click")
			picked = k.id
			h.refresh()
		end)
		b.root.Position = UDim2.fromScale((i - 1) * (w + gap), 0)
		b.root.Size = UDim2.fromScale(w, 1)
		b.text.Size = UDim2.fromScale(0.92, 0.26)
		b.text.Position = UDim2.fromScale(0.04, 0.7)
		if h.sized then
			h.sized(b.text, "small")
		end
		Ui.image(b.face, Config.images.icons[k.icon] or "", UDim2.fromScale(0.7, 0.62), UDim2.fromScale(0.15, 0.05))
		if on then
			local s = b.root:FindFirstChildOfClass("UIStroke")
			if s then
				s.Color = Theme.white
				s.Thickness = Config.ui.stroke + 2
			end
			local sc = Instance.new("UIScale")
			sc.Scale = 1.06
			sc.Parent = b.root
		end
	end
	-- the message box (optional, short)
	local box = Instance.new("TextBox")
	box.Name = "Message"
	box.Position = UDim2.fromScale(0, 0.52)
	box.Size = UDim2.fromScale(1, 0.24)
	box.BackgroundColor3 = Theme.white
	box.TextColor3 = Theme.ink
	box.PlaceholderText = "Tell us more (you can skip this)"
	box.PlaceholderColor3 = Theme.ink:Lerp(Theme.white, 0.55)
	box.Font = Theme.font
	-- a steady text size (2026-11-18): TextScaled shrank and jumped the words with every letter typed.
	-- Worked out from the box's height once it's measured: about 3 lines fit.
	box.TextScaled = false
	box.TextSize = 20
	box.TextWrapped = true
	box.MultiLine = true
	box.ClipsDescendants = true
	box.ClearTextOnFocus = false
	box.TextXAlignment = Enum.TextXAlignment.Left
	box.TextYAlignment = Enum.TextYAlignment.Top
	box.Text = draft
	local function fit()
		local h = box.AbsoluteSize.Y
		if h > 0 then
			box.TextSize = math.clamp(math.floor(h / 4), 14, 28)
		end
	end
	box:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	task.defer(fit)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0.02, 0)
	pad.PaddingRight = UDim.new(0.02, 0)
	pad.PaddingTop = UDim.new(0.08, 0)
	pad.Parent = box
	Ui.corner(box)
	Ui.stroke(box, Config.ui.cardStroke)
	box:GetPropertyChangedSignal("Text"):Connect(function()
		if #box.Text > F.maxLength then
			-- cut on a whole character (an emoji cut in half left junk), and keep the cursor at the end
			local fixed = string.sub(box.Text, 1, F.maxLength)
			while #fixed > 0 and utf8.len(fixed) == nil do
				fixed = string.sub(fixed, 1, #fixed - 1)
			end
			box.Text = fixed
			box.CursorPosition = #fixed + 1
			return
		end
		draft = box.Text
	end)
	box.Parent = o.body
	-- who reads it, in one quiet line
	local note = h.text(o.body, "Only the game makers see this. Never type your name or address.", 0, 1, Theme.ink:Lerp(Theme.white, 0.35), "small")
	note.TextXAlignment = Enum.TextXAlignment.Center
	note.Position = UDim2.fromScale(0, 0.77)
	note.Size = UDim2.fromScale(1, 0.07)
	-- the one focal point: Send, green and breathing once a mood is picked
	local foot = Instance.new("Frame")
	foot.Name = "Foot"
	foot.BackgroundTransparency = 1
	foot.Position = UDim2.fromScale(0, 0.85)
	foot.Size = UDim2.fromScale(1, 0.15)
	foot.Parent = o.body
	local send = h.button(foot, if picked then Theme.go else Theme.tiers.Common, "Send", 0.3, 0.4, function()
		if not picked then
			return
		end
		State.send("SendFeedback", picked, draft)
	end)
	send.root.Name = "SendButton"
	send.root.Position = UDim2.fromScale(0.3, 0)
	send.root.Size = UDim2.fromScale(0.4, 1)
	if picked and h.pulse then
		h.pulse(send.root)
	end
	o.first = send.face
end

return MailPopup
