--!strict
-- CoinPops: the "+N" that shoots out over each thawed pet in your pan as it earns (owner's reference
-- clip 2026-11-07). PetVisuals calls CoinPops.tick for every strolling pan pet each frame; each of my
-- pets pops every Config.coinPop.every seconds with its real income for that time. A pop is the coin
-- image and a lime-to-green "+N" with an ink outline: it shoots out of the spot over the pet's head to
-- one side and up (Back Out, tilting that way), hangs there rising a little, then shrinks and fades.
-- One RenderStepped loop moves every live pop; finished pops go back to a pool.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Theme = require(ReplicatedStorage.Shared.Theme)
local Ui = require(script.Parent.Parent.Lib.Ui)
local State = require(script.Parent.State)
local SettingsController = require(script.Parent.SettingsController)

local CoinPops = {}
local me = Players.LocalPlayer
local C = Config.coinPop

type Pop = { gui: BillboardGui, group: Frame, scale: UIScale, img: ImageLabel, text: TextLabel, stroke: UIStroke,
	born: number, side: number, dx: number, dy: number, reduced: boolean }
local live: { Pop } = {}
local spare: { Pop } = {}
-- per pet: when it pops next and which side it went last (sides alternate)
local timers: { [BasePart]: { next: number, side: number } } = setmetatable({}, { __mode = "k" }) :: any

local function backOut(x: number): number
	return 1 + 2.70158 * (x - 1) ^ 3 + 1.70158 * (x - 1) ^ 2
end

local function between(r: { number }): number
	return r[1] + math.random() * (r[2] - r[1])
end

local function build(): Pop
	local g = Instance.new("BillboardGui")
	g.Name = "CoinPop"
	g.Size = UDim2.fromOffset(C.boxPx[1], C.boxPx[2])
	g.LightInfluence = 0
	g.MaxDistance = C.maxDistance
	g.ResetOnSpawn = false
	g.ClipsDescendants = false
	g.Enabled = false
	local group = Instance.new("Frame")
	group.Name = "Pop"
	group.BackgroundTransparency = 1
	group.AnchorPoint = Vector2.new(0.5, 0.5)
	group.Parent = g
	local scale = Instance.new("UIScale")
	scale.Parent = group
	local img = Instance.new("ImageLabel")
	img.Name = "Coin"
	img.BackgroundTransparency = 1
	img.Image = Config.images.icons.coin
	img.AnchorPoint = Vector2.new(0, 0.5)
	img.Size = UDim2.fromOffset(C.coinPx, C.coinPx)
	img.Position = UDim2.fromScale(0, 0.5)
	img.Parent = group
	local text = Ui.label(group, "")
	text.Name = "Amount"
	text.TextScaled = false
	text.TextSize = C.textPx
	text.TextXAlignment = Enum.TextXAlignment.Left
	text.AnchorPoint = Vector2.new(0, 0.5)
	local grad = Instance.new("UIGradient") -- lime at the top fading to go-green, like the clip's "+$2"
	grad.Rotation = 90
	grad.Color = ColorSequence.new(Theme.fx.coinPopTop, Theme.fx.coinPopBottom)
	grad.Parent = text
	local stroke = text:FindFirstChildOfClass("UIStroke") :: UIStroke
	stroke.Thickness = math.max(2, C.textPx * C.strokeRatio)
	g.Parent = me:WaitForChild("PlayerGui")
	return { gui = g, group = group, scale = scale, img = img, text = text, stroke = stroke, born = 0, side = 1, dx = 0, dy = 0, reduced = false }
end

-- move a pop to its pose at this age; true once it's over
local function place(p: Pop, age: number): boolean
	local k = if p.reduced then 0.5 else 1 -- reduced motion halves every time
	local out, hold, exit = C.out * k, C.hold * k, C.exit * k
	local x, y, s, r, a
	if p.reduced then
		-- no flight: it fades in where it would land, then fades out
		x, y, s, r = p.dx, p.dy, 1, C.tilt * p.side
		a = if age < C.reducedFade then 1 - age / C.reducedFade else math.clamp((age - out - hold) / exit, 0, 1)
	elseif age < out then
		local f = backOut(age / out)
		x, y = p.dx * f, p.dy * f
		s = C.startScale + (1 - C.startScale) * f -- grows from small, overshoots a touch, settles
		r = C.tilt * p.side * math.min(f, 1)
		a = 0
	elseif age < out + hold then
		local f = (age - out) / hold
		f = 1 - (1 - f) * (1 - f)
		x, y, s, r, a = p.dx, p.dy - C.drift * f, 1, C.tilt * p.side, 0
	else
		local f = math.clamp((age - out - hold) / exit, 0, 1)
		f *= f
		x, y = p.dx, p.dy - C.drift * (1 + 0.6 * f)
		s, r, a = 1 + (C.exitScale - 1) * f, C.tilt * p.side, f
	end
	p.group.Position = UDim2.new(0.5, x, 0.5, y)
	p.group.Rotation = r
	p.scale.Scale = s
	p.text.TextTransparency = a
	p.stroke.Transparency = a
	p.img.ImageTransparency = a
	return age >= out + hold + exit
end

-- what this pet of mine earns in one pop's time (its own income x pages, rebirths, 2x pass)
local function amountFor(id: any): number
	local v = State.view
	if not v or typeof(id) ~= "string" then
		return 0
	end
	for _, p in v.pets do
		if p.id == id then
			return math.floor(p.income * (v.incomeMult or 1) * C.every)
		end
	end
	return 0
end

local function spawn(root: BasePart, height: number, amount: number, side: number)
	if #live >= C.maxActive then
		return
	end
	local p = table.remove(spare) or build()
	local label = "+" .. Ui.short(amount)
	p.text.Text = label
	-- size the group to what's drawn (coin + gap + text) so the visible pop is centred, not its box
	local w = TextService:GetTextSize(label, C.textPx, Theme.font, Vector2.new(1000, 200)).X
	local h = math.max(C.coinPx, C.textPx * 1.3)
	p.group.Size = UDim2.fromOffset(C.coinPx + C.gapPx + w, h)
	p.text.Size = UDim2.fromOffset(w + 4, h)
	p.text.Position = UDim2.new(0, C.coinPx + C.gapPx, 0.5, 0)
	p.gui.Adornee = root
	p.gui.StudsOffset = Vector3.new(0, height / 2 + C.lift, 0)
	p.side = side
	p.dx = between(C.outX) * side
	p.dy = -between(C.outY)
	p.reduced = SettingsController.get("reducedMotion") == true
	p.born = os.clock()
	place(p, 0)
	p.gui.Enabled = true
	table.insert(live, p)
end

-- called every frame for each thawed pet strolling round a pan (PetVisuals)
function CoinPops.tick(root: BasePart, height: number, now: number)
	if root:GetAttribute("PenOwner") ~= me.UserId then
		return -- only my own pets: other pans stay quiet
	end
	local tm = timers[root]
	if not tm then
		timers[root] = { next = now + math.random() * C.firstDelay, side = if math.random() < 0.5 then -1 else 1 }
		return
	end
	if now < tm.next then
		return
	end
	tm.next = math.max(tm.next + C.every, now + C.every * 0.5) -- keeps the beat, no burst after a hitch
	tm.side = -tm.side
	local cam = workspace.CurrentCamera
	if not cam or (cam.CFrame.Position - root.Position).Magnitude > C.maxDistance then
		return
	end
	local amount = amountFor(root:GetAttribute("PetId"))
	if amount >= 1 then
		spawn(root, height, amount, tm.side)
	end
end

function CoinPops.Start()
	RunService.RenderStepped:Connect(function()
		local now = os.clock()
		for i = #live, 1, -1 do
			local p = live[i]
			local root = p.gui.Adornee
			if not root or not root.Parent or place(p, now - p.born) then
				p.gui.Enabled = false
				p.gui.Adornee = nil
				table.remove(live, i)
				table.insert(spare, p)
			end
		end
	end)
end

return CoinPops
