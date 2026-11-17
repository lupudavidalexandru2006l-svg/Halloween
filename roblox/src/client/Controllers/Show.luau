--!strict
-- Show: the one owner of every show (Animation Rules 3). It plays the freeze shows for Legendary,
-- Mythic and Secret pets in the world, at the pet's spot (no pocket stage), from the beat lists in
-- Config.show.<name>. The server has already decided and stored the freeze (the pet is in your hands);
-- the show only plays it. While a show runs it borrows the camera (CameraController), hides the HUD
-- (Screen) and holds your character still (its Humanoid); finish() gives all of it back, is safe to call twice and
-- always runs, even if a beat errors. SKIP shows from the second viewing on and jumps to the reveal.
-- Reduced motion halves every beat and drops the camera kick; the one flash becomes a soft fade.
-- It also plays the gun buy show (Round 4 phase 4, Config.show.gunBuy): the new gun spins in, its stat
-- bars fill from your old gun's values, and the old gun drops into your locker. The server has already
-- charged and given the gun; the show only plays it. It hides the HUD but doesn't hold the character.
-- And the pan upgrade show (Round 4 phase 5, Config.show.panUpgrade), at your pan, with PanLooks, and
-- the fast upgrade's front view of the pan (Show.panTrip, timed by UpgradeMotion).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Theme = require(ReplicatedStorage.Shared.Theme)
local PetDefs = require(ReplicatedStorage.Shared.PetDefs)
local Ui = require(script.Parent.Parent.Lib.Ui)
local State = require(script.Parent.State)
local Screen = require(script.Parent.Screen)
local CameraController = require(script.Parent.CameraController)
local SettingsController = require(script.Parent.SettingsController)
local SoundController = require(script.Parent.SoundController)
local EffectsController = require(script.Parent.EffectsController)
local PetVisuals = require(script.Parent.PetVisuals)
local InputController = require(script.Parent.InputController)
local RayController = require(script.Parent.RayController)
local EquipmentPopup = require(script.Parent.EquipmentPopup)
local PanLooks = require(script.Parent.PanLooks)
local LuckReveal = require(script.Parent.LuckReveal)

local Show = {}
local me = Players.LocalPlayer
local U = Config.show.ui

type Ctx = {
	name: string, cfg: any, data: any, def: PetDefs.PetDef?, reduced: boolean, -- def: the pet (nil in the gun show) skipped: boolean, finished: boolean,
	model: Model?, cube: Part?, real: BasePart?, at: CFrame, size: number, color: Color3,
	gui: ScreenGui?, cam: Camera?, frost: Highlight?,
	controls: { hum: Humanoid, walk: number, jump: number, jumpH: number, rotate: boolean }?, -- the character, held still
	conn: RBXScriptConnection?, -- a per-frame spin (the gun show)
	extra: BasePart?, -- the pan upgrade show's glow
	reveal: LuckReveal.Reveal?, -- the luck roll's words (Mythic / Secret freeze, Secret thaw)
}
local running: Ctx? = nil

-- wait out a beat; a skip cuts it short unless the beat is kept on skip
local function hold(ctx: Ctx, seconds: number, keep: boolean)
	local t0 = os.clock()
	while os.clock() - t0 < seconds and not ctx.finished do
		if ctx.skipped and not keep then
			return
		end
		RunService.RenderStepped:Wait()
	end
end

-- move the borrowed camera smoothly to `to` (a push, never a spin round the player)
local function moveCamera(ctx: Ctx, to: CFrame, seconds: number)
	local cam = ctx.cam
	if not cam then
		return
	end
	TweenService:Create(cam, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = to }):Play()
end

local BEATS: { [string]: (Ctx, number, boolean) -> () } = {}

BEATS.pillar = function(ctx, seconds, keep)
	local total = 0
	for _, b in ctx.cfg.beats do
		total += b.time
	end
	local ground = ctx.at.Position - Vector3.new(0, ctx.size / 2, 0)
	EffectsController.pillar(ground, ctx.color, total * (if ctx.reduced then 0.5 else 1), seconds * 0.7)
	hold(ctx, seconds, keep)
end

-- the camera comes round to the far side of the pet and pushes in, so you see the pet with you behind it
BEATS.push = function(ctx, seconds, keep)
	local cam = ctx.cam
	local char = me.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if cam and hrp then
		local pet = ctx.at.Position
		local away = Vector3.new(pet.X - hrp.Position.X, 0, pet.Z - hrp.Position.Z)
		local dir = if away.Magnitude > 0.1 then away.Unit else -(cam.CFrame.LookVector * Vector3.new(1, 0, 1)).Unit
		-- 2026-11-16: a little to one side, so you don't stand straight behind the pet and hide it
		dir = CFrame.Angles(0, math.rad(ctx.cfg.pushSide or 0), 0):VectorToWorldSpace(dir)
		local from = pet + dir * ctx.cfg.pushDistance * 1.6 + Vector3.new(0, ctx.cfg.pushHeight * 1.5, 0)
		local to = pet + dir * ctx.cfg.pushDistance + Vector3.new(0, ctx.cfg.pushHeight, 0)
		-- looking at a point under the pet puts the pet in the upper half of the shot, above the reveal's words
		local look = pet + Vector3.new(0, 0.5 - (ctx.cfg.lookDrop or 0), 0)
		cam.CFrame = CFrame.lookAt(from, look)
		moveCamera(ctx, CFrame.lookAt(to, look), seconds)
	end
	hold(ctx, seconds, keep)
end

-- the ice slams shut: the cube drops onto the pet, squashes, and the camera gets one small kick
BEATS.slam = function(ctx, seconds, keep)
	local model, cube = ctx.model, ctx.cube
	if not model or not cube then
		return
	end
	SoundController.play("slam")
	local drop = ctx.cfg.slamDrop
	local t0 = os.clock()
	while not ctx.finished do
		local u = math.min(1, (os.clock() - t0) / math.max(0.01, seconds))
		model:PivotTo(ctx.at * CFrame.new(0, drop * (1 - u * u), 0))
		cube.Transparency = 1 - 0.55 * u
		if u >= 1 then
			break
		end
		RunService.RenderStepped:Wait()
	end
	local edges = cube:FindFirstChildOfClass("SelectionBox")
	if edges then
		edges.Transparency = Config.petFx.edgeTransparency
	end
	if ctx.frost then
		ctx.frost.FillTransparency = 0.65
	end
	-- squash on landing
	cube.Size = Vector3.new(ctx.size * 1.15, ctx.size * 0.85, ctx.size * 1.15)
	TweenService:Create(cube, TweenInfo.new(seconds * 0.6, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = Vector3.one * ctx.size }):Play()
	-- one short kick, never with reduced motion (Animation Rules 6)
	local cam = ctx.cam
	if cam and not ctx.reduced then
		local base = cam.CFrame
		local k0 = os.clock()
		while os.clock() - k0 < ctx.cfg.kick and not ctx.finished do
			local f = 1 - (os.clock() - k0) / ctx.cfg.kick
			cam.CFrame = base * CFrame.new(math.sin(os.clock() * 60) * 0.25 * f, math.cos(os.clock() * 47) * 0.2 * f, 0)
			RunService.RenderStepped:Wait()
		end
		cam.CFrame = base
	end
end

BEATS.burst = function(ctx, seconds, keep)
	local pos = ctx.at.Position
	EffectsController.burst(pos - Vector3.new(0, 2, 0), ctx.color, ctx.cfg.burstParts)
	EffectsController.burst(pos - Vector3.new(0, 2, 0), Theme.fx.frost, math.floor(ctx.cfg.burstParts / 2))
	if ctx.cfg.rays > 0 then
		EffectsController.rays(pos, ctx.color, ctx.cfg.rays, seconds * 4)
	end
	if ctx.cfg.flash then
		EffectsController.flash() -- one flash per show
	end
	if typeof(ctx.data.touch) == "string" then
		EffectsController.touch(ctx.data.touch, ctx.at, ctx.size)
	end
	hold(ctx, seconds, keep)
end

-- the reveal: the tier and the pet's name slam in (the true result, never a tease)
BEATS.name = function(ctx, seconds, keep)
	local gui = ctx.gui
	if not gui then
		return
	end
	if ctx.name == "secretFreeze" then
		SoundController.play("reveal_secret")
	end
	local box = Instance.new("Frame")
	box.Name = "Reveal"
	box.BackgroundTransparency = 1
	box.AnchorPoint = Vector2.new(0.5, 0.5)
	box.Position = UDim2.fromScale(0.5, U.titleY)
	box.Size = UDim2.fromScale(U.titleSize[1], U.titleSize[2] + U.nameSize[2])
	local scale = Instance.new("UIScale")
	scale.Scale = U.slamFrom
	scale.Parent = box
	local def = ctx.def :: PetDefs.PetDef
	local title = Ui.label(box, ctx.cfg.title, UDim2.fromScale(1, U.titleSize[2] / (U.titleSize[2] + U.nameSize[2])), UDim2.fromScale(0, 0))
	title.TextColor3 = ctx.color
	local stroke = title:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Thickness = 4
		stroke.Color = if def.tier == "Secret" then Theme.tiers.Secret else Theme.ink
	end
	local nameH = U.nameSize[2] / (U.titleSize[2] + U.nameSize[2])
	Ui.label(box, def.name, UDim2.fromScale(U.nameSize[1] / U.titleSize[1], nameH), UDim2.fromScale((1 - U.nameSize[1] / U.titleSize[1]) / 2, 1 - nameH))
	box.Parent = gui
	TweenService:Create(scale, TweenInfo.new(math.min(0.3, seconds * 0.25), Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	hold(ctx, seconds, keep)
end

-- the luck roll (owner 2026-11-13): "1 in N" climbs to the real odds, luck words step up, the name freezes
-- in letter by letter; the frozen pet shivers harder as it nears the end. SKIP jumps to the real number.
BEATS.odds = function(ctx, seconds, keep)
	local gui, def = ctx.gui, ctx.def
	if not gui or not def then
		return
	end
	local r = LuckReveal.new(gui, def, ctx.reduced)
	ctx.reveal = r
	SoundController.play("ray_charge")
	local base = ctx.at
	local amp = Config.show.reveal.cubeShiver
	r:roll(seconds, function()
		return ctx.skipped or ctx.finished
	end, function(u: number)
		local model = ctx.model
		if model and not ctx.reduced and ctx.name ~= "thawReveal" then
			local tt = os.clock() * 31
			model:PivotTo(base * CFrame.new(math.sin(tt) * amp * u, 0, math.cos(tt * 1.3) * amp * u))
		end
	end)
	if ctx.model and ctx.name ~= "thawReveal" then
		ctx.model:PivotTo(base)
	end
end

-- the reveal: rarity, the name slams in over a sunburst, "1 in N", confetti; then Continue
BEATS.title = function(ctx, seconds, keep)
	local r, gui = ctx.reveal, ctx.gui
	if not r or not gui then
		return
	end
	local skip = gui:FindFirstChild("Skip")
	if skip then
		skip:Destroy() -- Continue is the one button now
		ContextActionService:UnbindAction("IceRay_ShowSkip")
	end
	SoundController.play(if ctx.def and ctx.def.tier == "Secret" then "reveal_secret" else "rebirth_hit")
	r:finale()
	if ctx.cfg.stats and ctx.def then
		Show.statsCard(ctx, gui, ctx.def)
	end
	hold(ctx, seconds, true)
	r:waitContinue(function()
		return not ctx.finished
	end)
end

-- the Secret thaw: the camera comes round to the front of your Thaw Machine
BEATS.aim = function(ctx, seconds, keep)
	local cam = ctx.cam
	if cam then
		local at = ctx.at.Position
		local look = at + Vector3.new(0, ctx.cfg.lookUp, 0)
		cam.CFrame = CFrame.lookAt(at + Vector3.new(0, ctx.cfg.camUp * 1.6, ctx.cfg.camBack * 1.5), look)
		moveCamera(ctx, CFrame.lookAt(at + Vector3.new(0, ctx.cfg.camUp, ctx.cfg.camBack), look), seconds)
	end
	hold(ctx, seconds, keep)
end

-- the machine charges up: countable pulses of light and sparks, each a little bigger
BEATS.charge = function(ctx, seconds, keep)
	local n = math.max(1, ctx.cfg.chargePulses)
	for i = 1, n do
		if ctx.finished or (ctx.skipped and not keep) then
			return
		end
		EffectsController.burst(ctx.at.Position, if i == n then ctx.color else Theme.ice, 8 + i * 6)
		SoundController.play("upgrade_hit", 0.8 + i * 0.15)
		hold(ctx, seconds / n, keep)
	end
end

-- the cube flies into your hands and the camera comes home
BEATS.fly = function(ctx, seconds, keep)
	local gui = ctx.gui
	local reveal = gui and gui:FindFirstChild("Reveal")
	if reveal then
		reveal:Destroy()
	end
	if ctx.reveal then
		ctx.reveal:destroy()
		ctx.reveal = nil
	end
	local home = CameraController.homeCFrame()
	if ctx.cam and home then
		local char = me.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		-- back behind the player, at the distance the player had
		local to = if hrp then CFrame.new(hrp.Position + (home.Position - hrp.Position)) * home.Rotation else home
		moveCamera(ctx, to, seconds)
	end
	local model = ctx.model
	if model then
		ctx.model = nil
		EffectsController.flyHome(model, ctx.real, seconds)
		ctx.real = nil
	end
end

-- ---------- the Secret catch, v3 (owner 2026-11-16: "improve the secret catching animation by miles") ----------
-- From the owner's reference clips (not copied): the screen drops into a neon night stage; "1 in N" climbs
-- while glowing outlines of pets flick past in the middle, slowing down, until the outline is YOUR pet; the
-- words go dark but a small white ring that pulses twice, a slash of light, a white-out; then back in the world
-- the ice slams on the pet, rainbow ribbons swirl round it, the name fills in and a stat card shows what it is.
-- Numbers in Config.show.secretCinema. Candy neon on deep violet, never scary. Reduced motion: no spin or
-- shake, a soft fade instead of the white-out. Everything here goes in finish(), even if a beat fails.
local function cinemaFrame(parent: Instance, name: string, z: number): Frame
	-- full screen and past the safe-area edges (notches, the top bar), so it never shows a gap on a phone
	local f = Instance.new("Frame")
	f.Name = name
	f.BorderSizePixel = 0
	f.Size = UDim2.new(1, 600, 1, 600)
	f.Position = UDim2.new(0, -300, 0, -300)
	f.ZIndex = z
	f.Parent = parent
	return f
end

-- a full-screen layer of its own for the stage, the ring and the white-out: the show's ScreenGui keeps to the
-- phone's safe area, so on a phone a stage inside it left the world showing round the edges (2-player phone
-- test 2026-11-16). order: under the show's words (9), over them (11), over everything (12). Gone in finish().
local function fullGui(ctx: Ctx, name: string, order: number): ScreenGui
	local g = Instance.new("ScreenGui")
	g.Name = name
	g.ResetOnSpawn = false
	g.IgnoreGuiInset = true
	g.ScreenInsets = Enum.ScreenInsets.None
	g.ClipToDeviceSafeArea = false
	g.DisplayOrder = order
	g.Parent = me:WaitForChild("PlayerGui")
	local list = (ctx :: any).layers or {}
	;(ctx :: any).layers = list
	table.insert(list, g)
	return g
end

local function petPictures(): { string }
	local list = {}
	for _, img in Config.images.pets do
		if typeof(img) == "string" and img ~= "" then
			table.insert(list, img)
		end
	end
	return list
end

-- the stage: deep violet, neon orbs drifting, snowflakes falling. Fades in over the world.
BEATS.blackout = function(ctx, seconds, keep)
	local gui = ctx.gui
	if not gui then
		return
	end
	local SC = Config.show.secretCinema
	local st = Instance.new("CanvasGroup")
	st.Name = "Stage"
	st.BorderSizePixel = 0
	st.BackgroundColor3 = Theme.white
	st.Size = UDim2.new(1, 600, 1, 600)
	st.Position = UDim2.new(0, -300, 0, -300)
	st.ZIndex = 1
	st.GroupTransparency = 1
	local sky = Instance.new("UIGradient")
	sky.Rotation = 90
	sky.Color = ColorSequence.new(SC.skyTop, SC.skyBottom)
	sky.Parent = st
	st.Parent = fullGui(ctx, "ShowStage", 9)
	;(ctx :: any).stage = st
	local inner = Instance.new("Frame")
	inner.Name = "Inner"
	inner.BackgroundTransparency = 1
	inner.Position = UDim2.new(0, 300, 0, 300)
	inner.Size = UDim2.new(1, -600, 1, -600)
	inner.Parent = st
	local rng = Random.new()
	for i = 1, SC.orbs do
		local o = Instance.new("Frame")
		o.Name = "Orb"
		o.BorderSizePixel = 0
		o.BackgroundColor3 = SC.orbColors[(i % #SC.orbColors) + 1]
		o.AnchorPoint = Vector2.new(0.5, 0.5)
		local s = rng:NextNumber(SC.orbSize[1], SC.orbSize[2])
		o.Size = UDim2.fromScale(s, s)
		o.SizeConstraint = Enum.SizeConstraint.RelativeYY
		local x, y = rng:NextNumber(0.02, 0.98), rng:NextNumber(0.3, 1.02)
		o.Position = UDim2.fromScale(x, y)
		Ui.corner(o, 0.5)
		local glow = Instance.new("UIGradient") -- a bright middle, soft edges
		glow.Color = ColorSequence.new(Theme.white, o.BackgroundColor3)
		glow.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(1, 0.55),
		})
		glow.Parent = o
		o.Parent = inner
		if not ctx.reduced then
			TweenService:Create(o, TweenInfo.new(rng:NextNumber(2.4, 4.4), Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
				{ Position = UDim2.fromScale(x + rng:NextNumber(-0.05, 0.05), y - rng:NextNumber(0.04, 0.12)) }):Play()
		end
	end
	for i = 1, (if ctx.reduced then math.floor(SC.flakes / 3) else SC.flakes) do
		local f = Instance.new("Frame")
		f.Name = "Flake"
		f.BorderSizePixel = 0
		f.BackgroundColor3 = if i % 3 == 0 then SC.flakeMint else Theme.white
		f.BackgroundTransparency = rng:NextNumber(0.05, 0.4)
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		local s = rng:NextNumber(0.008, 0.02)
		f.Size = UDim2.fromScale(s, s)
		f.SizeConstraint = Enum.SizeConstraint.RelativeYY
		f.Rotation = 45
		local x = rng:NextNumber()
		f.Position = UDim2.fromScale(x, rng:NextNumber(-0.1, 1))
		f.Parent = inner
		if not ctx.reduced then
			TweenService:Create(f, TweenInfo.new(rng:NextNumber(2.5, 5), Enum.EasingStyle.Linear, Enum.EasingDirection.In, -1),
				{ Position = UDim2.fromScale(x + rng:NextNumber(-0.05, 0.05), 1.08), Rotation = 405 }):Play()
		end
	end
	TweenService:Create(st, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { GroupTransparency = 0 }):Play()
	SoundController.play("ray_charge")
	hold(ctx, seconds, keep)
end

-- the luck roll over the stage: glowing outlines of pets flick past in the middle, slowing down, and the last
-- one is your pet (the counter and the name come from LuckReveal, as before)
BEATS.silhouettes = function(ctx, seconds, keep)
	local gui, def = ctx.gui, ctx.def
	if not gui or not def then
		return
	end
	local SC = Config.show.secretCinema
	local st = (ctx :: any).stage :: Instance?
	local inner = (st and st:FindFirstChild("Inner")) or gui
	local box = Instance.new("Frame")
	box.Name = "Silhouette"
	box.BackgroundTransparency = 1
	box.AnchorPoint = Vector2.new(0.5, 0.5)
	box.Position = UDim2.fromScale(0.5, SC.silY)
	box.Size = UDim2.fromScale(SC.silSize, SC.silSize)
	box.SizeConstraint = Enum.SizeConstraint.RelativeYY
	box.ZIndex = 2
	box.Parent = inner
	local function pic(z: number, color: Color3, x: number, y: number): ImageLabel
		local i = Instance.new("ImageLabel")
		i.BackgroundTransparency = 1
		i.ScaleType = Enum.ScaleType.Fit
		i.AnchorPoint = Vector2.new(0.5, 0.5)
		i.Position = UDim2.fromScale(0.5 + x, 0.5 + y)
		i.Size = UDim2.fromScale(1, 1)
		i.ImageColor3 = color
		i.ZIndex = z
		i.Parent = box
		return i
	end
	-- the neon outline: the same picture nudged eight ways in the glow colour, the black shape on top
	local glows: { ImageLabel } = {}
	for k = 1, 8 do
		local a = k * math.pi / 4
		table.insert(glows, pic(2, SC.outlineColors[1], math.cos(a) * SC.outline, math.sin(a) * SC.outline))
	end
	local core = pic(3, SC.silhouette, 0, 0)
	local pictures = petPictures()
	local final = Config.images.pets[def.key] or pictures[1] or ""
	local function show(img: string, color: Color3)
		core.Image = img
		for _, g in glows do
			g.Image = img
			g.ImageColor3 = color
		end
	end
	local pop = Instance.new("UIScale")
	pop.Parent = box
	local function bump(to: number)
		if ctx.reduced then
			return
		end
		pop.Scale = to
		TweenService:Create(pop, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end
	show(if #pictures > 0 then pictures[math.random(#pictures)] else final, SC.outlineColors[1])
	local r = LuckReveal.new(gui, def, ctx.reduced)
	ctx.reveal = r
	-- its dark bands (for reading the words over the world) aren't needed on the stage, and on a phone they showed
	-- as a darker box inside the safe area: hidden here, back for the title over the world (whiteout)
	for _, c in r.root:GetChildren() do
		if c:IsA("Frame") and c.ZIndex == 1 then
			c.Visible = false
		end
	end
	local nextSwap, swaps, landed = 0, 0, false
	r:roll(seconds, function()
		return ctx.skipped or ctx.finished
	end, function(u: number)
		local now = os.clock()
		if u < SC.landAt and now >= nextSwap and #pictures > 0 then
			-- quick at first, slower and slower: the next outline comes later each time
			nextSwap = now + SC.swapFrom + (SC.swapTo - SC.swapFrom) * u * u
			swaps += 1
			show(pictures[math.random(#pictures)], SC.outlineColors[(swaps % #SC.outlineColors) + 1])
			bump(1.12)
		elseif u >= SC.landAt and not landed then
			landed = true
			show(final, Theme.tierGlow[def.tier] or SC.outlineColors[1])
			bump(1.35)
			SoundController.play("upgrade_hit", 1.3)
		end
		if not ctx.reduced then
			box.Rotation = math.sin(now * 2.2) * 3 * (1 - u)
		end
	end)
	show(final, Theme.tierGlow[def.tier] or SC.outlineColors[1])
	box.Rotation = 0
	hold(ctx, SC.holdFinal * (if ctx.reduced then 0.5 else 1), keep)
end

-- everything goes dark but a small white ring that pulses twice, then a slash of light opens down the middle
BEATS.ring = function(ctx, seconds, keep)
	local gui = ctx.gui
	if not gui then
		return
	end
	local SC = Config.show.secretCinema
	local parts: { Instance } = {}
	;(ctx :: any).ringParts = parts
	local rg = fullGui(ctx, "ShowRing", 11)
	local dark = cinemaFrame(rg, "Dark", 20)
	dark.BackgroundColor3 = SC.dark
	dark.BackgroundTransparency = 1
	table.insert(parts, dark)
	TweenService:Create(dark, TweenInfo.new(seconds * 0.18), { BackgroundTransparency = 0 }):Play()
	local function circle(size: number, thick: number): Frame
		local c = Instance.new("Frame")
		c.BackgroundTransparency = 1
		c.AnchorPoint = Vector2.new(0.5, 0.5)
		c.Position = UDim2.fromScale(0.5, 0.5)
		c.Size = UDim2.fromScale(size, size)
		c.SizeConstraint = Enum.SizeConstraint.RelativeYY
		c.ZIndex = 21
		Ui.corner(c, 0.5)
		local s = Instance.new("UIStroke")
		s.Color = Theme.white
		s.Thickness = thick
		s.Parent = c
		c.Parent = rg
		table.insert(parts, c)
		return c
	end
	local dot = circle(0.012, 0)
	dot.BackgroundTransparency = 0
	dot.BackgroundColor3 = Theme.white
	hold(ctx, seconds * 0.18, keep)
	for p = 1, 2 do
		if ctx.finished or (ctx.skipped and not keep) then
			return
		end
		local ring = circle(SC.ringFrom, 2.5)
		local stroke = ring:FindFirstChildOfClass("UIStroke") :: UIStroke
		local grow = seconds * 0.24
		TweenService:Create(ring, TweenInfo.new(grow, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = UDim2.fromScale(SC.ringTo * p, SC.ringTo * p) }):Play()
		TweenService:Create(stroke, TweenInfo.new(grow, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Transparency = 0.6 }):Play()
		SoundController.play("tink", 0.7 + p * 0.25)
		hold(ctx, grow, keep)
	end
	-- the slash: a thin white line top to bottom, opening
	local line = Instance.new("Frame")
	line.BorderSizePixel = 0
	line.BackgroundColor3 = Theme.white
	line.AnchorPoint = Vector2.new(0.5, 0.5)
	line.Position = UDim2.fromScale(0.5, 0.5)
	line.Size = UDim2.new(0, 3, 0, 0)
	line.ZIndex = 22
	local lg = Instance.new("UIGradient")
	lg.Rotation = 90
	lg.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(1, 1) })
	lg.Parent = line
	line.Parent = rg
	table.insert(parts, line)
	SoundController.play("ray_fire")
	TweenService:Create(line, TweenInfo.new(seconds * 0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = UDim2.new(0, 6, 1.4, 0) }):Play()
	hold(ctx, seconds * 0.16, keep)
end

-- white-out (a soft fade with reduced motion): behind it the stage goes and the world comes back. Kept on SKIP:
-- it's what clears the stage away
BEATS.whiteout = function(ctx, seconds, keep)
	local gui = ctx.gui
	if not gui then
		return
	end
	local SC = Config.show.secretCinema
	local w = cinemaFrame(fullGui(ctx, "ShowWhite", 12), "WhiteOut", 40)
	w.BackgroundColor3 = Theme.white
	w.BackgroundTransparency = 1
	local peak = if ctx.reduced then SC.softPeak else 0
	TweenService:Create(w, TweenInfo.new(seconds * 0.25), { BackgroundTransparency = peak }):Play()
	SoundController.play("reveal_secret")
	hold(ctx, seconds * 0.3, true)
	local st = (ctx :: any).stage :: Instance?
	if st then
		st:Destroy()
		;(ctx :: any).stage = nil
	end
	for _, p in ((ctx :: any).ringParts or {}) :: { Instance } do
		p:Destroy()
	end
	;(ctx :: any).ringParts = nil
	if ctx.reveal then
		for _, c in ctx.reveal.root:GetChildren() do
			if c:IsA("Frame") and c.ZIndex == 1 then
				c.Visible = true -- the words' dark bands again, over the world
			end
		end
	end
	TweenService:Create(w, TweenInfo.new(seconds * 0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { BackgroundTransparency = 1 }):Play()
	task.delay(seconds * 0.7, function()
		w:Destroy()
	end)
end

-- rainbow ribbons swirling round the pet (3D beams on a turning hub), until the show ends
BEATS.ribbons = function(ctx, seconds, keep)
	local SC = Config.show.secretCinema
	local folder = Instance.new("Folder")
	folder.Name = "ShowRibbons"
	folder.Parent = workspace
	;(ctx :: any).fxFolder = folder
	local center = ctx.at.Position
	local hub = Instance.new("Part")
	hub.Anchored, hub.CanCollide, hub.CanQuery, hub.CanTouch, hub.CastShadow = true, false, false, false, false
	hub.Transparency = 1
	hub.Size = Vector3.one
	hub.CFrame = CFrame.new(center)
	hub.Parent = folder
	local rainbow = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromHex("ff5a8a")), ColorSequenceKeypoint.new(0.2, Color3.fromHex("ffbf1f")),
		ColorSequenceKeypoint.new(0.4, Color3.fromHex("5dffb0")), ColorSequenceKeypoint.new(0.6, Color3.fromHex("5fd0ff")),
		ColorSequenceKeypoint.new(0.8, Color3.fromHex("9b7bff")), ColorSequenceKeypoint.new(1, Color3.fromHex("ff4fd8")),
	})
	local r = SC.ribbonRadius + ctx.size * 0.5
	for k = 1, SC.ribbons do
		local a = (k - 1) * math.pi * 2 / SC.ribbons
		local b = a + math.rad(SC.ribbonArc)
		local y0 = -ctx.size * 0.4 + (k - 1) * SC.ribbonRise
		local function att(angle: number, y: number): Attachment
			local at = Instance.new("Attachment")
			at.Position = Vector3.new(math.cos(angle) * r, y, math.sin(angle) * r)
			at.Axis = Vector3.new(-math.sin(angle), 0, math.cos(angle)) -- along the circle, so the curve hugs it
			at.SecondaryAxis = Vector3.yAxis
			at.Parent = hub
			return at
		end
		local beam = Instance.new("Beam")
		beam.Attachment0 = att(a, y0)
		beam.Attachment1 = att(b, y0 + SC.ribbonRise * 1.5)
		beam.CurveSize0 = r * 0.9
		beam.CurveSize1 = -r * 0.9
		beam.Width0, beam.Width1 = SC.ribbonWidth, SC.ribbonWidth * 0.6
		beam.Color = rainbow
		beam.LightEmission = 0.8
		beam.LightInfluence = 0
		beam.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(0.3, 0.15), NumberSequenceKeypoint.new(0.8, 0.15), NumberSequenceKeypoint.new(1, 0.9) })
		beam.Segments = 24
		beam.FaceCamera = true
		beam.Parent = hub
	end
	if not ctx.reduced then
		if ctx.conn then
			ctx.conn:Disconnect()
		end
		ctx.conn = RunService.RenderStepped:Connect(function()
			hub.CFrame = CFrame.new(center) * CFrame.Angles(0, os.clock() * SC.ribbonSpin, 0)
		end)
	end
	hold(ctx, seconds, keep)
end

-- the stat card at the top of the reveal (the references' size / mutation / income card): what it is, where
-- it lives and what it earns, in a dark pill with a rainbow rim
function Show.statsCard(ctx: Ctx, gui: ScreenGui, def: PetDefs.PetDef)
	local SC = Config.show.secretCinema
	local card = Instance.new("Frame")
	card.Name = "Stats"
	card.AnchorPoint = Vector2.new(0.5, 0)
	card.Position = UDim2.fromScale(0.5, SC.statsY)
	card.Size = UDim2.fromScale(SC.statsSize[1], SC.statsSize[2])
	card.BackgroundColor3 = Theme.alert.back
	card.BorderSizePixel = 0
	card.ZIndex = 6
	Ui.corner(card, 0.3)
	local rim = Instance.new("UIStroke")
	rim.Thickness = 4
	rim.Color = Theme.white
	rim.Parent = card
	local rg = Instance.new("UIGradient")
	rg.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromHex("ff5a8a")), ColorSequenceKeypoint.new(0.33, Color3.fromHex("ffbf1f")),
		ColorSequenceKeypoint.new(0.66, Color3.fromHex("5fd0ff")), ColorSequenceKeypoint.new(1, Color3.fromHex("9b7bff")),
	})
	rg.Parent = rim
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.Padding = UDim.new(0.02, 0)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = card
	local mut = if ctx.data and typeof(ctx.data.mut) == "string" then ctx.data.mut else nil
	local bonus = if mut and Config.mutations[mut] then Config.mutations[mut].bonus else 1
	local tier = Config.tier(def.tier)
	local income = (tier.income or 0) * Config.incomeZoneMultiplier ^ math.max(0, def.zone - 1) * bonus
	local zone = Config.zone(def.zone)
	local cells = {
		{ head = "RARITY", value = string.upper(def.tier), color = Theme.tierGlow[def.tier] or Theme.white },
		{ head = "MUTATION", value = if mut then string.upper(mut) else "NONE", color = if mut then (Theme.mut and (Theme.mut :: any)[mut]) or Theme.coin else Theme.white },
		{ head = "EARNS", value = `+{Ui.short(income)}/s`, color = Theme.coin },
		{ head = "ISLAND", value = if zone then zone.name else "?", color = Theme.ice },
	}
	for i, c in cells do
		local cell = Instance.new("Frame")
		cell.BackgroundColor3 = Theme.ink
		cell.BackgroundTransparency = 0.35
		cell.BorderSizePixel = 0
		cell.Size = UDim2.fromScale(0.225, 0.8)
		cell.LayoutOrder = i
		cell.ZIndex = 7
		Ui.corner(cell, 0.25)
		cell.Parent = card
		local h = Ui.label(cell, c.head, UDim2.fromScale(0.9, 0.3), UDim2.fromScale(0.05, 0.06))
		h.ZIndex = 8
		h.TextColor3 = Theme.white
		local v = Ui.label(cell, c.value, UDim2.fromScale(0.9, 0.52), UDim2.fromScale(0.05, 0.4))
		v.ZIndex = 8
		v.TextColor3 = c.color
	end
	local s = Instance.new("UIScale")
	s.Scale = if ctx.reduced then 1 else 0.3
	s.Parent = card
	card.Parent = gui
	if not ctx.reduced then
		TweenService:Create(s, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out, 0, false, 0.25), { Scale = 1 }):Play()
	end
end

-- Safe to call any number of times: each thing the show holds is given back once, whenever it was
-- taken (a show finished early by a newer one may still be setting up, and runs this again at its end)
local function finish(ctx: Ctx)
	local first = not ctx.finished
	ctx.finished = true
	if running == ctx then
		running = nil
	end
	local fx = (ctx :: any).fxFolder :: Instance?
	if fx then
		fx:Destroy()
		;(ctx :: any).fxFolder = nil
	end
	for _, layer in ((ctx :: any).layers or {}) :: { Instance } do
		layer:Destroy()
	end
	;(ctx :: any).layers = nil
	if ctx.model then
		ctx.model:Destroy()
		ctx.model = nil
	end
	if ctx.real then
		ctx.real:SetAttribute("ShowHidden", nil)
		ctx.real = nil
	end
	if ctx.frost then
		ctx.frost:Destroy()
		ctx.frost = nil
	end
	if ctx.reveal then
		ctx.reveal:destroy()
		ctx.reveal = nil
	end
	if ctx.conn then
		ctx.conn:Disconnect()
		ctx.conn = nil
	end
	if ctx.gui then
		ctx.gui:Destroy()
		ctx.gui = nil
		ContextActionService:UnbindAction("IceRay_ShowSkip")
		if not running then
			Screen.setHidden(false) -- a newer show keeps the HUD hidden
		end
	end
	if ctx.cam then
		ctx.cam = nil
		CameraController.giveBack()
	end
	for _, d in ((ctx :: any).hiddenSelf or {}) :: { Instance } do
		if d.Parent then
			(d :: any).LocalTransparencyModifier = 0
		end
	end
	;(ctx :: any).hiddenSelf = nil
	local c = ctx.controls
	if c then
		ctx.controls = nil
		if c.hum.Parent then
			c.hum.WalkSpeed, c.hum.JumpPower, c.hum.JumpHeight, c.hum.AutoRotate = c.walk, c.jump, c.jumpH, c.rotate
		end
	end
	if first and ctx.data.uid then
		State.send("ShowDone", ctx.data.uid) -- the cube melts normally again, and SKIP shows next time
	end
end

local function skipButton(ctx: Ctx)
	local gui = ctx.gui
	if not gui then
		return
	end
	local function skip()
		ctx.skipped = true
		local b = gui:FindFirstChild("Skip")
		if b then
			b:Destroy()
		end
	end
	local b = Ui.block(gui, "Skip", Theme.info, "SKIP", skip)
	b.root.AnchorPoint = Vector2.new(0.5, 0.5)
	b.root.Position = UDim2.fromScale(0.5, U.skipY)
	b.root.Size = UDim2.fromScale(U.skipSize[1], U.skipSize[2])
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = U.skipSize[1] / U.skipSize[2] * 16 / 9
	aspect.Parent = b.root
	InputController.select(b.face)
	-- keyboard and gamepad too (every action on every input)
	ContextActionService:BindActionAtPriority("IceRay_ShowSkip", function(_, state: Enum.UserInputState)
		if state == Enum.UserInputState.Begin then
			skip()
			return Enum.ContextActionResult.Sink
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.ContextActionPriority.High.Value + 10, Config.ui.keys.skip, Config.ui.gamepadKeys.skip)
end

function Show.play(name: string, data: any)
	local cfg = (Config.show :: any)[name]
	local def = PetDefs.get(data.key)
	if not cfg or not def or typeof(data.at) ~= "Vector3" then
		State.send("ShowDone", data.uid)
		return
	end
	local real = EffectsController.realCube(data.uid) -- may wait a moment, so the check below comes after it
	if running then
		finish(running) -- one show at a time; the newer one plays
	end
	local size = if real then real.Size.X else PetDefs.cubeSize[def.size] * Config.carry.scale
	local ctx: Ctx = {
		name = name, cfg = cfg, data = data, def = def, reduced = SettingsController.get("reducedMotion") == true,
		skipped = false, finished = false, model = nil, cube = nil, real = real, at = CFrame.new(), size = size,
		color = Theme.tierGlow[def.tier] or Theme.coin, gui = nil, cam = nil, frost = nil, controls = nil, conn = nil,
	}
	running = ctx
	local ok, err = pcall(function()
		if real then
			real:SetAttribute("ShowHidden", true) -- it's in your hands already; it appears there when the show ends
		end
		-- the pet stands where it was frozen, frosted over; the ice comes down in the slam
		local model, cube = PetVisuals.frozenCube(data.key, size)
		ctx.model, ctx.cube = model, cube
		ctx.at = EffectsController.cubeAt(data, size)
		if model and cube then
			model:PivotTo(ctx.at)
			cube.Transparency = 1
			local edges = cube:FindFirstChildOfClass("SelectionBox")
			if edges then
				edges.Transparency = 1
			end
			local frost = Instance.new("Highlight")
			frost.Adornee = model
			frost.FillColor = Theme.fx.frostTint
			frost.FillTransparency = 0.5
			frost.OutlineTransparency = 1
			frost.DepthMode = Enum.HighlightDepthMode.Occluded
			frost.Parent = model
			ctx.frost = frost
		end
		local gui = Instance.new("ScreenGui")
		gui.Name = "Show"
		gui.ResetOnSpawn = false
		gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
		gui.DisplayOrder = 10
		gui.Parent = me:WaitForChild("PlayerGui")
		ctx.gui = gui
		Screen.setHidden(true)
		-- hold the character still (this place runs Roblox's engine controls, so there's no
		-- PlayerModule to switch off): the Humanoid's own speed and jump, put back in finish()
		local hum = me.Character and me.Character:FindFirstChildOfClass("Humanoid")
		if hum then
			ctx.controls = { hum = hum, walk = hum.WalkSpeed, jump = hum.JumpPower, jumpH = hum.JumpHeight, rotate = hum.AutoRotate }
			hum.WalkSpeed, hum.JumpPower, hum.JumpHeight, hum.AutoRotate = 0, 0, 0, false
		end
		if cfg.camera then
			ctx.cam = CameraController.borrow()
		end
		if State.view and State.view.seenShows and State.view.seenShows[name] then
			skipButton(ctx)
		end
		local scale = if ctx.reduced then 0.5 else 1
		for _, beat in cfg.beats do
			if ctx.finished then
				break
			end
			if ctx.skipped and not beat.keepOnSkip then
				continue
			end
			local play = BEATS[beat.name]
			if play then
				play(ctx, beat.time * scale, beat.keepOnSkip == true)
			end
		end
	end)
	finish(ctx)
	if not ok then
		warn("[Show] beat failed:", err)
	end
end

-- a Secret comes out of your Thaw Machine (Config.show.thawReveal): the server has already put it in your
-- pan; this only plays it, at the machine
-- (and your very first pet, any tier: Config.show.firstReveal, a shorter cut)
function Show.thawReveal(data: any)
	local cfg = if data.first then Config.show.firstReveal else Config.show.thawReveal
	local def = PetDefs.get(data.key)
	if not def or not (data.first or cfg.tiers[def.tier]) or typeof(data.at) ~= "Vector3" then
		return
	end
	if running then
		finish(running)
	end
	local ctx: Ctx = {
		name = "thawReveal", cfg = cfg, data = { key = data.key }, def = def, reduced = SettingsController.get("reducedMotion") == true,
		skipped = false, finished = false, model = nil, cube = nil, real = nil, at = CFrame.new(data.at), size = 3,
		color = Theme.tierGlow[def.tier] or Theme.coin, gui = nil, cam = nil, frost = nil, controls = nil, conn = nil,
	}
	running = ctx
	local ok, err = pcall(function()
		local gui = Instance.new("ScreenGui")
		gui.Name = "Show"
		gui.ResetOnSpawn = false
		gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
		gui.DisplayOrder = 10
		gui.Parent = me:WaitForChild("PlayerGui")
		ctx.gui = gui
		Screen.setHidden(true)
		local hum = me.Character and me.Character:FindFirstChildOfClass("Humanoid")
		if hum then
			ctx.controls = { hum = hum, walk = hum.WalkSpeed, jump = hum.JumpPower, jumpH = hum.JumpHeight, rotate = hum.AutoRotate }
			hum.WalkSpeed, hum.JumpPower, hum.JumpHeight, hum.AutoRotate = 0, 0, 0, false
		end
		ctx.cam = CameraController.borrow()
		-- you stand between the camera and your machine: your avatar steps out of the shot so it never
		-- hides the new pet (QA IR-18); finish() brings it back
		local hiddenSelf: { Instance } = {}
		for _, d in (if me.Character then me.Character:GetDescendants() else {}) do
			if d:IsA("BasePart") or d:IsA("Decal") then
				d.LocalTransparencyModifier = 1
				table.insert(hiddenSelf, d)
			end
		end
		;(ctx :: any).hiddenSelf = hiddenSelf
		local scale = if ctx.reduced then 0.5 else 1
		for _, beat in cfg.beats do
			if ctx.finished then
				break
			end
			local play = BEATS[beat.name]
			if play then
				play(ctx, beat.time * scale, beat.keepOnSkip == true)
			end
		end
	end)
	finish(ctx)
	if not ok then
		warn("[Show] thaw reveal failed:", err)
	end
end

-- ---------- the gun buy show (Config.show.gunBuy) ----------

-- a gun turning in its own little window (the same model the hand holds)
local function gunView(parent: Instance, tier: number, size: number, pos: UDim2): (ViewportFrame, Model)
	local vf = Instance.new("ViewportFrame")
	vf.Name = "Gun" .. tier
	vf.BackgroundTransparency = 1
	vf.AnchorPoint = Vector2.new(0.5, 0.5)
	vf.Position = pos
	vf.Size = UDim2.fromScale(size, size)
	vf.Ambient = Theme.ink:Lerp(Theme.white, 0.45) -- dim fill, so the light from the top-left shades it (all-white went flat)
	vf.LightColor = Theme.white
	vf.LightDirection = Vector3.new(1, -1, -1)
	local a = Instance.new("UIAspectRatioConstraint")
	a.AspectRatio = 1
	a.DominantAxis = Enum.DominantAxis.Height
	a.Parent = vf
	local cam = Instance.new("Camera")
	cam.FieldOfView = 30
	cam.Parent = vf
	vf.CurrentCamera = cam
	local m = RayController.buildGun(tier)
	m:PivotTo(CFrame.new())
	local r = m:GetExtentsSize().Magnitude
	cam.CFrame = CFrame.lookAt(Vector3.new(0, r * 0.45, r * 1.55), Vector3.zero)
	m.Parent = vf
	vf.Parent = parent
	return vf, m
end

local GUN_BEATS: { [string]: (Ctx, number, boolean) -> () } = {}

-- the new gun flies in, turning, and its name slams in over it
GUN_BEATS.spinIn = function(ctx, seconds, keep)
	local gui = ctx.gui
	if not gui then
		return
	end
	local cfg = ctx.cfg
	local tier = ctx.data.gun :: number
	local vf, model = gunView(gui, tier, cfg.viewSize, UDim2.fromScale(0.5, 0.36))
	ctx.model = model
	local scale = Instance.new("UIScale")
	scale.Scale = 0
	scale.Parent = vf
	TweenService:Create(scale, TweenInfo.new(seconds, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	local t0 = os.clock()
	ctx.conn = RunService.RenderStepped:Connect(function()
		local t = os.clock() - t0
		local u = math.min(1, t / math.max(0.01, seconds))
		-- fast turns while it flies in, then a slow show-off spin
		local angle = (1 - (1 - u) ^ 2) * cfg.turns * math.pi * 2 + math.max(0, t - seconds) * cfg.slowSpin * math.pi * 2
		if model.Parent then
			model:PivotTo(CFrame.Angles(0, angle, 0) * CFrame.Angles(0, 0, 0.25)) -- muzzle tipped up a little
		end
	end)
	local title = Ui.label(gui, cfg.title, UDim2.fromScale(U.titleSize[1], U.titleSize[2] * 0.7), UDim2.fromScale((1 - U.titleSize[1]) / 2, 0.04))
	title.TextColor3 = ctx.color
	local name = Ui.label(gui, Config.gun(tier).name, UDim2.fromScale(U.nameSize[1], U.nameSize[2]), UDim2.fromScale((1 - U.nameSize[1]) / 2, 0.04 + U.titleSize[2] * 0.7))
	name.Name = "GunName"
	for _, t in { title, name } do
		local s = Instance.new("UIScale")
		s.Scale = U.slamFrom
		s.Parent = t
		TweenService:Create(s, TweenInfo.new(math.min(0.3, seconds * 0.4), Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end
	SoundController.play("slam")
	hold(ctx, seconds, keep)
end

-- the stat bars fill from the old gun's values to the new one's (scaled to the 20-island maximum)
GUN_BEATS.bars = function(ctx, seconds, keep)
	local gui = ctx.gui
	if not gui then
		return
	end
	local cfg = ctx.cfg
	local G = Config.guns
	local new, old = Config.gun(ctx.data.gun), Config.gun(ctx.data.old)
	local top = 0.36 + cfg.viewSize / 2 + cfg.barGap
	for i, stat in G.stats do
		local y = top + (i - 1) * (cfg.barHeight + cfg.barGap)
		local row = Instance.new("Frame")
		row.Name = "Bar_" .. stat
		row.BackgroundTransparency = 1
		row.Position = UDim2.fromScale((1 - cfg.barWidth) / 2, y)
		row.Size = UDim2.fromScale(cfg.barWidth, cfg.barHeight)
		row.Parent = gui
		local label = Ui.label(row, G.statLabels[stat], UDim2.fromScale(0.24, 1), UDim2.fromScale(0, 0))
		label.TextXAlignment = Enum.TextXAlignment.Right
		local track = Instance.new("Frame")
		track.BackgroundColor3 = Theme.snowFar
		track.Position = UDim2.fromScale(0.27, 0.15)
		track.Size = UDim2.fromScale(0.56, 0.7)
		Ui.corner(track, 0.5)
		Ui.stroke(track)
		track.Parent = row
		local fill = Instance.new("Frame")
		fill.Name = "Fill"
		fill.BackgroundColor3 = ctx.color
		fill.Size = UDim2.fromScale(Config.gunStatShare(stat, (old :: any)[stat]), 1)
		Ui.corner(fill, 0.5)
		fill.Parent = track
		Ui.label(row, EquipmentPopup.statText(stat, new), UDim2.fromScale(0.15, 1), UDim2.fromScale(0.85, 0))
		local to = Config.gunStatShare(stat, (new :: any)[stat])
		TweenService:Create(fill, TweenInfo.new(seconds * 0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = UDim2.fromScale(to, 1) }):Play()
	end
	hold(ctx, seconds, keep)
end

-- the old gun shrinks down into the locker (it stays yours: equip it again at the booth)
GUN_BEATS.locker = function(ctx, seconds, keep)
	local gui = ctx.gui
	local old = ctx.data.old
	if not gui or typeof(old) ~= "number" or old == ctx.data.gun then
		return
	end
	local locker = Ui.block(gui, "Locker", Theme.info, "Locker", nil)
	locker.root.AnchorPoint = Vector2.new(0.5, 0.5)
	locker.root.Position = UDim2.fromScale(0.82, 0.8)
	locker.root.Size = UDim2.fromScale(0.14, 0.09)
	local vf = gunView(gui, old, ctx.cfg.viewSize * 0.45, UDim2.fromScale(0.22, 0.62))
	TweenService:Create(vf, TweenInfo.new(seconds * 0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Position = locker.root.Position, Size = UDim2.fromScale(0.02, 0.02),
	}):Play()
	hold(ctx, seconds, keep)
	vf:Destroy()
end

GUN_BEATS.rest = function(ctx, seconds, keep)
	hold(ctx, seconds, keep)
end

function Show.gunBuy(data: any)
	local cfg = Config.show.gunBuy
	if typeof(data) ~= "table" or typeof(data.gun) ~= "number" then
		return
	end
	if running then
		finish(running) -- one show at a time
	end
	local ctx: Ctx = {
		name = "gunBuy", cfg = cfg, data = data, def = nil, reduced = SettingsController.get("reducedMotion") == true,
		skipped = false, finished = false, model = nil, cube = nil, real = nil, at = CFrame.new(), size = 0,
		color = (Theme.guns[data.gun] or Theme.guns[1]).glow, gui = nil, cam = nil, frost = nil, controls = nil, conn = nil,
	}
	running = ctx
	local ok, err = pcall(function()
		local gui = Instance.new("ScreenGui")
		gui.Name = "Show"
		gui.ResetOnSpawn = false
		gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
		gui.DisplayOrder = 10
		gui.Parent = me:WaitForChild("PlayerGui")
		ctx.gui = gui
		Screen.setHidden(true)
		-- a soft dim behind the gun, so it reads on any background
		local dim = Instance.new("Frame")
		dim.Name = "Dim"
		dim.BackgroundColor3 = Theme.ink
		dim.BackgroundTransparency = 0.45
		dim.Size = UDim2.fromScale(1, 1)
		dim.ZIndex = 0
		dim.Parent = gui
		if State.view and State.view.seenShows and State.view.seenShows.gunBuy then
			skipButton(ctx)
		end
		local scale = if ctx.reduced then 0.5 else 1
		for _, beat in cfg.beats do
			if ctx.finished then
				break
			end
			if ctx.skipped and not beat.keepOnSkip then
				continue
			end
			local play = GUN_BEATS[beat.name]
			if play then
				play(ctx, beat.time * scale, beat.keepOnSkip == true)
			end
		end
	end)
	finish(ctx)
	if not ok then
		warn("[Show] gun show failed:", err)
	end
end

-- ---------- the pan upgrade show (Config.show.panUpgrade, Round 4 phase 5) ----------
-- The camera looks at your pan from the plaza: a glow builds up, the old pieces pop off, the new ones
-- drop in with a squash, a burst, the title, and coins fly from your counter into the pan. Bigger
-- upgrades (a new Look, higher levels) play longer. The server has already charged and upgraded.

local PAN_TEXT: { [string]: (number) -> string } = {
	slots = function(level)
		return `Holds {Config.panSlots(level, if State.view then State.view.rebirths else 0)} pets`
	end,
	cold = function(level)
		local isl = Config.world.islands[level]
		return if isl then `Cold Level {level}: {isl.name} pets stay frozen` else `Cold Level {level}`
	end,
	look = function(level)
		local l = Config.pan.looks[level]
		return if l then l.name else ""
	end,
}

local PAN_BEATS: { [string]: (Ctx, number, boolean) -> () } = {}

PAN_BEATS.glow = function(ctx, seconds, keep)
	local plot = ctx.data.plot :: number
	local cam = ctx.cam
	if cam then
		local cfg = ctx.cfg
		local pl = Config.world.plots[plot]
		local W = Config.world.pans
		local target = Vector3.new(pl.x, cfg.camLookUp, W.frontZ - W.length * 0.35)
		local from = Vector3.new(pl.x, cfg.camUp, W.frontZ + cfg.camBack)
		moveCamera(ctx, CFrame.lookAt(from, target), math.max(0.2, seconds * 0.8)) -- a smooth push, never a spin
	end
	local glow = PanLooks.glow(plot, ctx.color, seconds)
	ctx.extra = glow
	hold(ctx, seconds, keep)
end

PAN_BEATS.popOff = function(ctx, seconds, keep)
	PanLooks.popOff(ctx.data.plot, seconds)
	hold(ctx, seconds, keep)
end

PAN_BEATS.dropIn = function(ctx, seconds, keep)
	local plot = ctx.data.plot :: number
	local look = if ctx.data.kind == "look" then ctx.data.level else PanLooks.lookOf(plot)
	if ctx.skipped then
		PanLooks.popOff(plot, 0) -- SKIP cut the pop: the old pieces go at once
	end
	PanLooks.dropIn(plot, look, seconds)
	hold(ctx, seconds, keep)
end

PAN_BEATS.burst = function(ctx, seconds, keep)
	local cfg = ctx.cfg
	local plot = ctx.data.plot :: number
	local glow = ctx.extra
	if glow then
		ctx.extra = nil
		TweenService:Create(glow, TweenInfo.new(seconds), { Transparency = 1 }):Play()
		task.delay(seconds, function()
			glow:Destroy()
		end)
	end
	SoundController.play("pan_up")
	local at = PanLooks.center(plot) + Vector3.new(0, 3, 0)
	EffectsController.burst(at, ctx.color, cfg.burstParts)
	EffectsController.burst(at, Theme.fx.frost, math.floor(cfg.burstParts / 2))
	local gui = ctx.gui
	if gui then
		local title = Ui.label(gui, cfg.title[ctx.data.kind] or "", UDim2.fromScale(U.titleSize[1], U.titleSize[2] * 0.7), UDim2.fromScale((1 - U.titleSize[1]) / 2, 0.06))
		title.Name = "PanTitle"
		title.TextColor3 = ctx.color
		local fn = PAN_TEXT[ctx.data.kind]
		local sub = Ui.label(gui, if fn then fn(ctx.data.level) else "", UDim2.fromScale(U.nameSize[1], U.nameSize[2] * 0.8), UDim2.fromScale((1 - U.nameSize[1]) / 2, 0.06 + U.titleSize[2] * 0.7))
		sub.Name = "PanText"
		for _, t in { title, sub } do
			local s = Instance.new("UIScale")
			s.Scale = U.slamFrom
			s.Parent = t
			TweenService:Create(s, TweenInfo.new(math.min(0.3, seconds * 0.6), Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		end
	end
	hold(ctx, seconds, keep)
end

-- coins fly from the coin counter (bottom left) into the pan, a small pop when each lands
PAN_BEATS.coins = function(ctx, seconds, keep)
	local gui, cam = ctx.gui, workspace.CurrentCamera
	if not gui or not cam or (ctx.data.price or 0) <= 0 then
		hold(ctx, seconds, keep)
		return
	end
	local cfg = ctx.cfg
	local view = cam.ViewportSize
	local p = cam:WorldToViewportPoint(PanLooks.center(ctx.data.plot :: number) + Vector3.new(0, 2, 0))
	local to = UDim2.fromScale(math.clamp(p.X / view.X, 0.05, 0.95), math.clamp(p.Y / view.Y, 0.05, 0.95))
	local from = UDim2.fromScale(Config.ui.sideInset + Config.ui.coinsSize[1] * 0.2, 0.92)
	local fly = seconds * 0.8
	for k = 1, cfg.coins do
		local img = Ui.image(gui, Config.images.icons.coin, UDim2.fromScale(cfg.coinSize, cfg.coinSize), from)
		img.AnchorPoint = Vector2.new(0.5, 0.5)
		local a = Instance.new("UIAspectRatioConstraint")
		a.Parent = img
		task.delay((k - 1) / cfg.coins * (seconds - fly), function()
			local t = TweenService:Create(img, TweenInfo.new(fly, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = to })
			t.Completed:Once(function()
				img:Destroy()
			end)
			t:Play()
		end)
	end
	hold(ctx, seconds, keep)
end

PAN_BEATS.rest = function(ctx, seconds, keep)
	hold(ctx, seconds, keep)
end

function Show.panUpgrade(data: any)
	local cfg = Config.show.panUpgrade
	if typeof(data) ~= "table" or typeof(data.plot) ~= "number" or not Config.world.plots[data.plot] or typeof(data.level) ~= "number" then
		return
	end
	if running then
		finish(running) -- one show at a time
	end
	local look = if data.kind == "look" then data.level else PanLooks.lookOf(data.plot)
	local ctx: Ctx = {
		name = "panUpgrade", cfg = cfg, data = data, def = nil, reduced = SettingsController.get("reducedMotion") == true,
		skipped = false, finished = false, model = nil, cube = nil, real = nil, at = CFrame.new(), size = 0,
		color = PanLooks.style(look).glow, gui = nil, cam = nil, frost = nil, controls = nil, conn = nil,
	}
	running = ctx
	local ok, err = pcall(function()
		local gui = Instance.new("ScreenGui")
		gui.Name = "Show"
		gui.ResetOnSpawn = false
		gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
		gui.DisplayOrder = 10
		gui.Parent = me:WaitForChild("PlayerGui")
		ctx.gui = gui
		Screen.setHidden(true)
		local hum = me.Character and me.Character:FindFirstChildOfClass("Humanoid")
		if hum then
			ctx.controls = { hum = hum, walk = hum.WalkSpeed, jump = hum.JumpPower, jumpH = hum.JumpHeight, rotate = hum.AutoRotate }
			hum.WalkSpeed, hum.JumpPower, hum.JumpHeight, hum.AutoRotate = 0, 0, 0, false
		end
		ctx.cam = CameraController.borrow()
		if State.view and State.view.seenShows and State.view.seenShows.panUpgrade then
			skipButton(ctx)
		end
		-- bigger upgrades get longer shows (Animation Rules 3); reduced motion halves it all
		local scale = (cfg.kindScale[data.kind] or 1) * math.min(cfg.maxScale, 1 + cfg.perLevel * (data.level - 1))
		if ctx.reduced then
			scale *= 0.5
		end
		for _, beat in cfg.beats do
			if ctx.finished then
				break
			end
			if ctx.skipped and not beat.keepOnSkip then
				continue
			end
			local play = PAN_BEATS[beat.name]
			if play then
				play(ctx, beat.time * scale, beat.keepOnSkip == true)
			end
		end
	end)
	local glow = ctx.extra
	if glow then
		glow:Destroy()
		ctx.extra = nil
	end
	PanLooks.settle(data.plot, look) -- every piece back in place, whatever happened
	finish(ctx)
	if not ok then
		warn("[Show] pan upgrade show failed:", err)
	end
end

-- ---------- the fast upgrade's front view (Config.motion.upgrade.trip, owner 2026-11-07) ----------
-- UpgradeMotion calls this when the server's answer lands: the popup and HUD hide, the camera glides
-- to the front of your pan, onArrive() plays the pan's upgrade there, the camera glides back and
-- everything comes back. rm: the time scale (0.5 with reduced motion). Fixed length, so UpgradeMotion
-- can time the card's pop for the moment the popup returns.
function Show.panTrip(data: any, rm: number, onArrive: () -> ())
	local T = Config.motion.upgrade.trip
	local pl = typeof(data) == "table" and typeof(data.plot) == "number" and Config.world.plots[data.plot]
	if not pl then
		onArrive()
		return
	end
	if running then
		finish(running) -- one show at a time
	end
	local ctx: Ctx = {
		name = "panTrip", cfg = T, data = {}, def = nil, reduced = rm < 1,
		skipped = false, finished = false, model = nil, cube = nil, real = nil, at = CFrame.new(), size = 0,
		color = Theme.coin, gui = nil, cam = nil, frost = nil, controls = nil, conn = nil,
	}
	running = ctx
	local arrived = false
	local ok, err = pcall(function()
		local gui = Instance.new("ScreenGui")
		gui.Name = "Show"
		gui.ResetOnSpawn = false
		gui.Parent = me:WaitForChild("PlayerGui")
		ctx.gui = gui
		Screen.setHidden(true) -- the popup stays open underneath and comes back as it was
		local hum = me.Character and me.Character:FindFirstChildOfClass("Humanoid")
		if hum then
			ctx.controls = { hum = hum, walk = hum.WalkSpeed, jump = hum.JumpPower, jumpH = hum.JumpHeight, rotate = hum.AutoRotate }
			hum.WalkSpeed, hum.JumpPower, hum.JumpHeight, hum.AutoRotate = 0, 0, 0, false
		end
		ctx.cam = CameraController.borrow()
		local W = Config.world.pans
		local target = Vector3.new(pl.x, T.lookUp, W.frontZ - W.length * T.lookIn)
		local from = Vector3.new(pl.x, T.camUp, W.frontZ + T.camBack)
		local function glide(to: CFrame, seconds: number)
			local cam = ctx.cam
			if cam then
				TweenService:Create(cam, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), { CFrame = to }):Play()
			end
		end
		glide(CFrame.lookAt(from, target), T.go * rm) -- a smooth glide, never a spin round the player
		hold(ctx, T.go * rm, true)
		arrived = true
		onArrive()
		hold(ctx, T.watch * rm, true)
		local home = CameraController.homeCFrame()
		if home then
			glide(home, T.back * rm)
		end
		hold(ctx, T.back * rm, true)
	end)
	if not arrived then
		onArrive() -- the pan still upgrades in the world
	end
	finish(ctx)
	if not ok then
		warn("[Show] pan front view failed:", err)
	end
end

-- ---------- the Trainer's transformation (Config.motion.upgrade.trainerTrip, owner 2026-11-13) ----------
-- UpgradeMotion calls this when a Trainer upgrade lands. The popup and HUD hide, the camera glides to
-- where you stand at your trainer, the old trainer glows white and shivers, shrinks into a flash and a
-- burst, the new one grows in with a spring as the glow leaves it, its name and "xN Cold Power" pop up,
-- and the camera glides home. Both trainers in the show are still copies; while it plays, the server's
-- real trainer folders for that pan are kept out of the world on this client only, so the server's
-- rebuild never pops in early, and the new one goes back at the end. Fixed length, so UpgradeMotion
-- can time the card's pop for when the popup returns.

local function trainerFolder(plot: number): Instance?
	local f = workspace:FindFirstChild("Trainers")
	return if f then f:FindFirstChild("Trainer" .. plot) else nil
end

-- a still copy of a trainer: no prompts, no tags (nothing else takes it for a trainer or animates it),
-- nothing solid
local function stillCopy(src: Instance): Instance
	local c = src:Clone()
	for _, d in c:GetDescendants() do
		for _, tag in d:GetTags() do
			d:RemoveTag(tag)
		end
		if d:IsA("ProximityPrompt") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored, d.CanCollide, d.CanQuery, d.CanTouch = true, false, false, false
		end
	end
	for _, tag in c:GetTags() do
		c:RemoveTag(tag)
	end
	return c
end

-- UpgradeMotion takes this on the Trainer card's press, before the server swaps the trainer
function Show.trainerSnapshot(plot: number): Instance?
	local f = trainerFolder(plot)
	return if f then stillCopy(f) else nil
end

-- calls fn(u) every frame, u from 0 to 1 over `seconds` (ends on fn(1) unless the show was cut)
local function animate(ctx: Ctx, seconds: number, fn: (number) -> ())
	local t0 = os.clock()
	while not ctx.finished do
		local u = if seconds > 0 then math.min(1, (os.clock() - t0) / seconds) else 1
		fn(u)
		if u >= 1 then
			return
		end
		RunService.RenderStepped:Wait()
	end
end

function Show.trainerTrip(data: any, rm: number, old: Instance?)
	local T = Config.motion.upgrade.trainerTrip
	local plot = if typeof(data) == "table" then data.plot else nil
	local level = if typeof(data) == "table" then data.level else nil
	if typeof(plot) ~= "number" or not Config.world.plots[plot] or typeof(level) ~= "number" then
		if old then
			old:Destroy()
		end
		return
	end
	if running then
		finish(running) -- one show at a time
	end
	local ctx: Ctx = {
		name = "trainerTrip", cfg = T, data = {}, def = nil, reduced = rm < 1,
		skipped = false, finished = false, model = nil, cube = nil, real = nil, at = CFrame.new(), size = 0,
		color = Theme.coin, gui = nil, cam = nil, frost = nil, controls = nil, conn = nil,
	}
	running = ctx
	local stations = Config.training.stations
	local st = stations[level] or stations[1]
	local look = Theme.training.stations[st.kind]
	local neon = if look then look.neon else Theme.training.power
	local centre = Config.trainerCentre(plot)
	local pivot = CFrame.new(centre)
	local name = "Trainer" .. plot
	local trainers = workspace:FindFirstChild("Trainers")
	local hidden: { Instance } = {}
	local fresh: Instance? = nil -- the server's new trainer, once it has arrived
	-- keep the real trainer(s) of this pan out of the world (this client only) while the show runs
	local function sweep()
		if not trainers then
			return
		end
		for _, ch in trainers:GetChildren() do
			if ch.Name == name then
				if ch:GetAttribute("Tier") == level then
					fresh = ch
				end
				table.insert(hidden, ch)
				ch.Parent = nil
			end
		end
	end
	local ok, err = pcall(function()
		local standing = trainerFolder(plot)
		if not old and standing and standing:GetAttribute("Tier") == data.old then
			old = stillCopy(standing) -- bought without a press here: the old one is still standing
		end
		sweep()
		ctx.conn = RunService.RenderStepped:Connect(function()
			sweep()
		end)
		local stage = Instance.new("Model")
		stage.Name = "TrainerShow"
		stage.Parent = workspace
		ctx.model = stage
		-- a copy stood in the trainer's place, with a highlight for its glow
		local function place(src: Instance): (Model, Highlight)
			local m = Instance.new("Model")
			src.Parent = m
			m.WorldPivot = pivot
			m.Parent = stage
			local h = Instance.new("Highlight")
			h.Adornee = m
			h.FillColor = Color3.new(1, 1, 1)
			h.OutlineColor = neon
			h.FillTransparency = 1
			h.OutlineTransparency = 1
			h.DepthMode = Enum.HighlightDepthMode.Occluded
			h.Parent = m
			return m, h
		end
		local oldM: Model?, oldH: Highlight? = nil, nil
		if old then
			oldM, oldH = place(old)
			old = nil
		end
		local gui = Instance.new("ScreenGui")
		gui.Name = "Show"
		gui.ResetOnSpawn = false
		gui.IgnoreGuiInset = true
		gui.Parent = me:WaitForChild("PlayerGui")
		ctx.gui = gui
		Screen.setHidden(true) -- the popup stays open underneath and comes back as it was
		local hum = me.Character and me.Character:FindFirstChildOfClass("Humanoid")
		if hum then
			ctx.controls = { hum = hum, walk = hum.WalkSpeed, jump = hum.JumpPower, jumpH = hum.JumpHeight, rotate = hum.AutoRotate }
			hum.WalkSpeed, hum.JumpPower, hum.JumpHeight, hum.AutoRotate = 0, 0, 0, false
		end
		ctx.cam = CameraController.borrow()
		-- a smooth glide that rises in the middle (over the pan's fence, never through it); never a spin
		local function glide(to: CFrame, seconds: number)
			local cam = ctx.cam
			if not cam then
				hold(ctx, seconds, true)
				return
			end
			local a = cam.CFrame
			animate(ctx, seconds, function(u)
				local k = if u < 0.5 then 2 * u * u else 1 - (-2 * u + 2) ^ 2 / 2 -- Quad InOut
				local c = a:Lerp(to, k)
				cam.CFrame = c + Vector3.new(0, T.arc * math.sin(math.pi * u), 0)
			end)
		end
		-- from where you stand at the trainer (its open side), looking at the target and the arch behind it
		local lookAt = centre + Vector3.new(0, T.lookUp, Config.training.targetZ * 0.5)
		local from = centre + Vector3.new(T.camSide, T.camUp, -T.camBack)
		glide(CFrame.lookAt(from, lookAt), T.go * rm)

		-- charge: the old trainer glows white and shivers, harder toward the end
		SoundController.play("upgrade_charge")
		local shiver = if ctx.reduced then 0 else T.shiverDeg
		local t0 = os.clock()
		animate(ctx, T.charge * rm, function(u)
			if oldM and oldH then
				local k = u * u
				oldH.FillTransparency = 1 - T.glow * k
				oldH.OutlineTransparency = 1 - k
				local a = math.sin((os.clock() - t0) * math.pi * 2 * T.shiverHz) * shiver * k
				oldM:PivotTo(pivot * CFrame.Angles(0, 0, math.rad(a)))
			end
		end)

		-- swap: it shrinks into a flash and a burst
		SoundController.play("upgrade_hit")
		animate(ctx, T.swap * rm, function(u)
			if oldM and oldH then
				oldH.FillTransparency = 0
				oldM:PivotTo(pivot)
				oldM:ScaleTo(1 + (T.shrinkTo - 1) * u * u)
			end
		end)
		if oldM then
			oldM:Destroy()
		end
		EffectsController.flash()
		local burstAt = centre + Vector3.new(0, 2, Config.training.targetZ)
		EffectsController.burst(burstAt, neon, T.burst)
		EffectsController.burst(burstAt, Theme.white, math.floor(T.burst / 3))

		-- grow: the new trainer springs up from small as the glow leaves it
		local waited = os.clock()
		while not fresh and not ctx.finished and os.clock() - waited < T.waitNew do
			RunService.RenderStepped:Wait()
		end
		local src = fresh
		if src then
			local newM, newH = place(stillCopy(src))
			newH.FillTransparency = 0
			newH.OutlineTransparency = 0
			newM:ScaleTo(T.growFrom)
			SoundController.play("pan_up")
			animate(ctx, T.grow * rm, function(u)
				local c1 = 1.70158
				local k = 1 + (c1 + 1) * (u - 1) ^ 3 + c1 * (u - 1) ^ 2 -- Back Out
				newM:ScaleTo(math.max(0.05, T.growFrom + (1 - T.growFrom) * k))
				newH.FillTransparency = u
				newH.OutlineTransparency = u
			end)
			newM:ScaleTo(1)
			newH:Destroy()
		else
			hold(ctx, T.grow * rm, true)
		end
		-- its name and what it's worth
		local title = Ui.label(gui, st.name, UDim2.fromScale(U.titleSize[1], U.titleSize[2] * 0.7), UDim2.fromScale((1 - U.titleSize[1]) / 2, 0.06))
		title.Name = "TrainerTitle"
		title.TextColor3 = if look then look.title else Theme.white
		local sub = Ui.label(gui, "x" .. st.mult .. " Cold Power", UDim2.fromScale(U.nameSize[1], U.nameSize[2] * 0.8), UDim2.fromScale((1 - U.nameSize[1]) / 2, 0.06 + U.titleSize[2] * 0.7))
		sub.Name = "TrainerText"
		for _, t in { title, sub } do
			local s = Instance.new("UIScale")
			s.Scale = U.slamFrom
			s.Parent = t
			TweenService:Create(s, TweenInfo.new(0.3 * rm, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		end
		hold(ctx, T.watch * rm, true)

		-- back: the words go, the camera glides home
		for _, t in { title, sub } do
			TweenService:Create(t, TweenInfo.new(0.2 * rm), { TextTransparency = 1 }):Play()
			local s = t:FindFirstChildOfClass("UIStroke")
			if s then
				TweenService:Create(s, TweenInfo.new(0.2 * rm), { Transparency = 1 }):Play()
			end
		end
		local home = CameraController.homeCFrame()
		if home then
			glide(home, T.back * rm)
		else
			hold(ctx, T.back * rm, true)
		end
	end)
	finish(ctx) -- stops the sweep, removes the copies, gives back camera, HUD and controls
	if old then
		old:Destroy()
	end
	-- the trainer the map says this pan has goes back into the world (an older one the server replaced is gone)
	local map = workspace:FindFirstChild("Map")
	local want = map and map:GetAttribute("PanTrainer" .. plot)
	local tier = if typeof(want) == "number" and stations[want] then want else 1
	for i = #hidden, 1, -1 do
		local h = hidden[i]
		if h:GetAttribute("Tier") == tier then
			pcall(function()
				h.Parent = trainers
			end)
			break
		end
	end
	if not ok then
		warn("[Show] trainer view failed:", err)
	end
end

-- ---------- the rebirth show (Config.show.rebirth) ----------
-- Remade 2026-11-12 (owner: "it needs to be very good, sfx vfx all the things"; references in the vault:
-- Research/Reference Clips 2026-11-12, the supernova crown aura and the rare-roll star flare). At the booth:
--   title   a dark card, R E B I R T H letter-spaced over a line of light growing from the middle
--   gather  a rune stage lights up under you (a glowing disc, three rings turning, sparks rising); the
--           camera starts low and wide and drifts round you
--   drain   your coins fly in from all round and melt into you (they're what the rebirth spends)
--   charge  three countable pulses: a shockwave ring, the rings spin faster, the star over your head
--           grows, the hum climbs, the camera creeps closer; then the reverse-cymbal suck
--   burst   one flash, a light pillar, rays, confetti, the rings fly outward
--   reveal  a turning sunburst, "NEW REBIRTH" small over REBIRTH n slamming in letter by letter, then
--           coin x1 -> coin x1.5 and anything else that came with it; low on the screen so you stay in view
--   back    the camera comes home and the stage fades
-- The server has already rebirthed and saved; the show only plays it. Everything it makes lives in one
-- stage that is cleaned up whatever happens (an error, a newer show, a respawn).

type Ring = { parts: { BasePart }, radius: number, target: number, spin: number, angle: number, alpha: number, alphaTarget: number, y: number }
type Stage = {
	folder: Folder, ground: Vector3, center: Vector3, rings: { Ring }, speed: number,
	disc: BasePart?, motes: ParticleEmitter?, light: PointLight?, glow: Highlight?, star: BillboardGui?, hum: Sound?,
	orbit: { base: number, t: number, angle: number, radius: number, height: number, radiusTo: number, heightTo: number, look: number, lookTo: number }?, kickUntil: number,
	conn: RBXScriptConnection?,
}
local stages: { [Ctx]: Stage } = {}
local REBIRTH_BEATS: { [string]: (Ctx, number, boolean) -> () } = {}

local function rebirthColours(): { [string]: Color3 }
	return { rebirth = Theme.booths.rebirth, gold = Theme.coin, ice = Theme.fx.beamGlow }
end

local function stagePart(st: Stage, size: Vector3, color: Color3, alpha: number): Part
	local p = Instance.new("Part")
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Size = size
	p.Transparency = alpha
	p.Parent = st.folder
	return p
end

-- a flat glowing disc on the ground (a cylinder lying on its side)
local function flatDisc(st: Stage, radius: number, color: Color3, alpha: number, y: number): Part
	local p = stagePart(st, Vector3.new(0.12, radius * 2, radius * 2), color, alpha)
	p.Shape = Enum.PartType.Cylinder
	p.CFrame = CFrame.new(st.ground + Vector3.new(0, y, 0)) * CFrame.Angles(0, 0, math.rad(90))
	return p
end

local function sizeDisc(p: BasePart, st: Stage, radius: number, y: number)
	p.Size = Vector3.new(0.12, radius * 2, radius * 2)
	p.CFrame = CFrame.new(st.ground + Vector3.new(0, y, 0)) * CFrame.Angles(0, 0, math.rad(90))
end

-- a shockwave: a thin disc that grows out from you and fades
local function shockwave(st: Stage, color: Color3, toRadius: number, seconds: number)
	local p = flatDisc(st, 1, color, 0.25, 0.3)
	local t0 = os.clock()
	task.spawn(function()
		while p.Parent do
			local u = math.min(1, (os.clock() - t0) / math.max(0.05, seconds))
			sizeDisc(p, st, 1 + (toRadius - 1) * (1 - (1 - u) ^ 3), 0.3)
			p.Transparency = 0.25 + 0.75 * u
			if u >= 1 then
				break
			end
			RunService.RenderStepped:Wait()
		end
		p:Destroy()
	end)
end

-- the star flare over your head: a long bright cross with a soft middle, made of fading bars
local function starFlare(st: Stage, color: Color3): BillboardGui
	local S = Config.show.rebirth.star
	local holder = stagePart(st, Vector3.one * 0.2, color, 1)
	holder.CFrame = CFrame.new(st.center + Vector3.new(0, S.height, 0))
	local g = Instance.new("BillboardGui")
	g.Name = "Star"
	g.Size = UDim2.fromScale(S.from, S.from)
	g.LightInfluence = 0
	g.Adornee = holder
	g.Parent = holder
	local fade = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(1, 1) })
	for i, spec in { { 1, 0.07, 0 }, { 0.07, 1, 0 }, { 0.55, 0.04, 45 }, { 0.55, 0.04, -45 } } do
		local bar = Instance.new("Frame")
		bar.Name = "Bar" .. i
		bar.AnchorPoint = Vector2.new(0.5, 0.5)
		bar.Position = UDim2.fromScale(0.5, 0.5)
		bar.Size = UDim2.fromScale(spec[1], spec[2])
		bar.Rotation = spec[3]
		bar.BackgroundColor3 = Theme.white
		bar.BorderSizePixel = 0
		local grad = Instance.new("UIGradient")
		grad.Transparency = fade
		grad.Rotation = if spec[2] > spec[1] then 90 else 0
		grad.Parent = bar
		bar.Parent = g
	end
	local core = Instance.new("ImageLabel")
	core.Name = "Core"
	core.BackgroundTransparency = 1
	core.Image = Config.images.icons.sunburst
	core.ImageColor3 = color
	core.AnchorPoint = Vector2.new(0.5, 0.5)
	core.Position = UDim2.fromScale(0.5, 0.5)
	core.Size = UDim2.fromScale(0.7, 0.7)
	core.Parent = g
	return g
end

-- the camera: drifts round you while the stage plays; anything solid in the way pulls it in front of it
local function placeCamera(ctx: Ctx, st: Stage)
	local cam, o = ctx.cam, st.orbit
	if not cam or not o then
		return
	end
	local O = Config.show.rebirth.orbit
	local look = st.center + Vector3.new(0, o.look - 1, 0)
	local want = st.center + Vector3.new(math.cos(o.angle) * o.radius, o.height, math.sin(o.angle) * o.radius)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { me.Character :: Model, st.folder }
	local hit = workspace:Raycast(look, want - look, params)
	if hit then
		want = look + (want - look).Unit * math.max(3, hit.Distance - 1)
	end
	local cf = CFrame.lookAt(want, look)
	if os.clock() < st.kickUntil and not ctx.reduced then
		local k = Config.show.rebirth.kick
		cf *= CFrame.new((math.random() - 0.5) * k, (math.random() - 0.5) * k, 0)
	end
	cam.CFrame = cf
end

-- build the stage and the per-frame driver (rings turning, camera drifting)
local function buildStage(ctx: Ctx): Stage?
	local hrp = me.Character and me.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then
		return nil
	end
	local cfg = Config.show.rebirth
	local folder = Instance.new("Folder")
	folder.Name = "RebirthStage"
	folder.Parent = workspace
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { me.Character :: Model, folder }
	local down = workspace:Raycast(hrp.Position, Vector3.new(0, -12, 0), params)
	local ground = if down then down.Position else hrp.Position - Vector3.new(0, 3, 0)
	local st: Stage = {
		folder = folder, ground = ground, center = hrp.Position, rings = {}, speed = 1, kickUntil = 0,
	}
	-- start the camera away from the booth at a three-quarter angle (never into its wall)
	local booth = hrp.Position + hrp.CFrame.LookVector
	for _, b in Config.world.booths do
		if b.id == "rebirth" then
			booth = b.pos
		end
	end
	local away = (hrp.Position - booth) * Vector3.new(1, 0, 1)
	local base = if away.Magnitude > 0.1 then away.Unit else Vector3.new(0, 0, -1)
	local dir = CFrame.Angles(0, math.rad(cfg.angle), 0) * base
	local O = cfg.orbit
	local base0 = math.atan2(dir.Z, dir.X)
	st.orbit = { base = base0, t = 0, angle = base0, radius = O.startRadius, height = O.startHeight, radiusTo = O.startRadius, heightTo = O.startHeight, look = O.lookHeight, lookTo = O.lookHeight }
	-- you turn to face the camera (the open side), so the show sees your face, not your back
	hrp.CFrame = CFrame.lookAt(hrp.Position, hrp.Position + Vector3.new(dir.X, 0, dir.Z))
	local last = os.clock()
	st.conn = RunService.RenderStepped:Connect(function()
		local now = os.clock()
		local dt = math.min(0.1, now - last)
		last = now
		if not folder.Parent then
			return
		end
		local slow = if ctx.reduced then 0.4 else 1
		for _, r in st.rings do
			r.angle += r.spin * st.speed * slow * dt * math.pi * 2
			r.radius += (r.target - r.radius) * math.min(1, dt * 6)
			r.alpha += (r.alphaTarget - r.alpha) * math.min(1, dt * 5)
			local n = #r.parts
			for i, p in r.parts do
				local a = r.angle + (i - 1) * (math.pi * 2 / n)
				p.CFrame = CFrame.new(ground + Vector3.new(0, r.y, 0)) * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -r.radius)
				p.Transparency = r.alpha
			end
		end
		local o = st.orbit
		if o then
			o.t += dt * math.min(2, st.speed)
			local swing = math.rad(if ctx.reduced then O.reducedSwing else O.swing)
			o.angle = o.base + swing * math.sin(o.t / O.swingSeconds * math.pi * 2 - math.pi / 2) -- starts at one side, sways across
			local f = math.min(1, dt * O.follow)
			o.radius += (o.radiusTo - o.radius) * f
			o.height += (o.heightTo - o.height) * f
			o.look += (o.lookTo - o.look) * f
			placeCamera(ctx, st)
		end
	end)
	stages[ctx] = st
	return st
end

local function clearStage(ctx: Ctx)
	local st = stages[ctx]
	if not st then
		return
	end
	stages[ctx] = nil
	if st.conn then
		st.conn:Disconnect()
	end
	if st.hum then
		st.hum:Destroy()
	end
	if st.glow then
		st.glow:Destroy()
	end
	-- the stage fades rather than popping out (it's gone in half a second either way)
	local folder = st.folder
	for _, d in folder:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 1 then
			TweenService:Create(d, TweenInfo.new(0.4), { Transparency = 1 }):Play()
		elseif d:IsA("ParticleEmitter") then
			d.Enabled = false
		elseif d:IsA("PointLight") then
			TweenService:Create(d, TweenInfo.new(0.4), { Brightness = 0 }):Play()
		end
	end
	task.delay(0.5, function()
		folder:Destroy()
	end)
end

-- letter-spaced capitals (title card, small words)
local function spaced(s: string): string
	return (s:gsub("(.)", "%1 "):sub(1, -2))
end

REBIRTH_BEATS.title = function(ctx, seconds, keep)
	local gui = ctx.gui
	local TC = Config.show.rebirth.titleCard
	if not gui then
		return
	end
	local card = Instance.new("Frame")
	card.Name = "TitleCard"
	card.BackgroundColor3 = Theme.ink
	card.BorderSizePixel = 0
	card.Position = UDim2.fromScale(-0.1, -0.2) -- past the safe area's edges, so it covers the whole screen
	card.Size = UDim2.fromScale(1.2, 1.4)
	card.ZIndex = 0
	card.Parent = gui
	local word = Ui.label(card, spaced(TC.word), UDim2.fromScale(0.5, 0.09), UDim2.fromScale(0.25, 0.36))
	word.Name = "Word"
	word.TextColor3 = Theme.coin
	word.TextTransparency = 1
	local line = Instance.new("Frame")
	line.Name = "Line"
	line.AnchorPoint = Vector2.new(0.5, 0.5)
	line.Position = UDim2.fromScale(0.5, 0.465)
	line.Size = UDim2.fromScale(0, 0.004)
	line.BackgroundColor3 = Theme.white
	line.BorderSizePixel = 0
	local grad = Instance.new("UIGradient")
	grad.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(1, 1) })
	grad.Parent = line
	line.Parent = card
	local cap = Ui.label(card, TC.caption, UDim2.fromScale(0.5, 0.04), UDim2.fromScale(0.25, 0.72))
	cap.Name = "Caption"
	cap.TextTransparency = 1
	SoundController.play("island")
	SoundController.play("chill")
	local ti = TweenInfo.new(seconds * 0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local late = TweenInfo.new(seconds * 0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, seconds * 0.25)
	TweenService:Create(line, ti, { Size = UDim2.fromScale(TC.line / 1.2, 0.004) }):Play()
	for _, pair in { { word, ti, 0 }, { cap, late, 0.15 } } do
		local t = pair[1] :: TextLabel
		local s = t:FindFirstChildOfClass("UIStroke")
		if s then
			s.Transparency = 1 -- the outline fades in with its words (an outline alone read as ghost text)
			TweenService:Create(s, pair[2] :: TweenInfo, { Transparency = 0 }):Play()
		end
		TweenService:Create(t, pair[2] :: TweenInfo, { TextTransparency = pair[3] :: number }):Play()
	end
	hold(ctx, seconds, keep)
end

local function dropTitleCard(ctx: Ctx, seconds: number)
	local gui = ctx.gui
	local card = gui and gui:FindFirstChild("TitleCard") :: Frame?
	if not card then
		return
	end
	card.Name = "TitleCardOut"
	local ti = TweenInfo.new(seconds)
	TweenService:Create(card, ti, { BackgroundTransparency = 1 }):Play()
	for _, d in card:GetDescendants() do
		if d:IsA("TextLabel") then
			TweenService:Create(d, ti, { TextTransparency = 1 }):Play()
			local s = d:FindFirstChildOfClass("UIStroke")
			if s then
				TweenService:Create(s, ti, { Transparency = 1 }):Play()
			end
		elseif d:IsA("Frame") then
			TweenService:Create(d, ti, { BackgroundTransparency = 1 }):Play()
		end
	end
	task.delay(seconds, function()
		card:Destroy()
	end)
end

REBIRTH_BEATS.gather = function(ctx, seconds, keep)
	local cfg = Config.show.rebirth
	local st = stages[ctx]
	dropTitleCard(ctx, math.min(0.4, seconds * 0.35))
	if not st then
		hold(ctx, seconds, keep)
		return
	end
	local C = rebirthColours()
	-- the rune disc fades up under you
	local disc = flatDisc(st, cfg.discRadius, C.rebirth, 1, 0.08)
	st.disc = disc
	TweenService:Create(disc, TweenInfo.new(seconds * 0.6), { Transparency = cfg.discAlpha }):Play()
	-- three rings, each switching on as a circle of glowing segments
	for i, spec in cfg.rings do
		local parts: { BasePart } = {}
		local n = spec.segments
		local len = 2 * math.pi * spec.radius / n * (if spec.dashed then 0.55 else 1.06)
		for k = 1, n do
			table.insert(parts, stagePart(st, Vector3.new(len, 0.16, spec.width), C[spec.colour] or C.rebirth, 1))
		end
		table.insert(st.rings, { parts = parts, radius = spec.radius * 0.6, target = spec.radius, spin = spec.spin, angle = i, alpha = 1, alphaTarget = 0.05, y = 0.18 + i * 0.04 })
	end
	-- sparks rising off the disc
	local lowG = SettingsController.get("lowGraphics") == true
	local emitterPart = stagePart(st, Vector3.new(cfg.discRadius * 1.6, 0.2, cfg.discRadius * 1.6), C.rebirth, 1)
	emitterPart.CFrame = CFrame.new(st.ground + Vector3.new(0, 0.3, 0))
	local e = Instance.new("ParticleEmitter")
	e.Name = "Motes"
	e.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, C.rebirth), ColorSequenceKeypoint.new(0.5, C.gold), ColorSequenceKeypoint.new(1, C.ice) })
	e.LightEmission = 1
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) })
	e.Transparency = NumberSequence.new(0.1, 1)
	e.Speed = NumberRange.new(2.5, 5)
	e.Lifetime = NumberRange.new(1.4, 2.4)
	e.EmissionDirection = Enum.NormalId.Top
	e.Shape = Enum.ParticleEmitterShape.Box
	e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	e.Rate = cfg.motes * (if lowG then 0.5 else 1) * (if ctx.reduced then 0.5 else 1)
	e.Parent = emitterPart
	st.motes = e
	-- a light on you in the rebirth colour, and the hum starting low
	local lp = stagePart(st, Vector3.one * 0.2, C.rebirth, 1)
	lp.CFrame = CFrame.new(st.center)
	local light = Instance.new("PointLight")
	light.Color = C.rebirth
	light.Range = 18
	light.Brightness = 0.5
	light.Shadows = false
	light.Parent = lp
	st.light = light
	local hum = SoundController.loop("ray_hum")
	if hum then
		hum.PlaybackSpeed = cfg.hum.from
		st.hum = hum
	end
	SoundController.play("bridge")
	hold(ctx, seconds, keep)
end

REBIRTH_BEATS.drain = function(ctx, seconds, keep)
	local cfg = Config.show.rebirth
	local st = stages[ctx]
	if not st then
		hold(ctx, seconds, keep)
		return
	end
	-- your coins fly in from all round, spiral, and melt into you
	local n = cfg.coins
	local fly = math.min(cfg.coinFly, seconds * 0.7)
	for i = 1, n do
		task.delay((i - 1) / n * math.max(0.05, seconds - fly), function()
			if ctx.finished or not st.folder.Parent then
				return
			end
			local a0 = (i / n) * math.pi * 2 + math.random() * 0.4
			local h0 = 2 + math.random() * 4
			local C0 = cfg.coinSize
			local coin = stagePart(st, Vector3.new(C0 * 0.18, C0, C0), Theme.coin, 0)
			coin.Shape = Enum.PartType.Cylinder
			coin.Material = Enum.Material.SmoothPlastic
			-- the painted coin on both faces, so it reads as the game's coin (a bare disc read as a yellow plate)
			for _, faceId in { Enum.NormalId.Left, Enum.NormalId.Right } do
				local dcl = Instance.new("Decal")
				dcl.Texture = Config.images.icons.coin
				dcl.Face = faceId
				dcl.Parent = coin
			end
			local t0 = os.clock()
			while coin.Parent and not ctx.finished do
				local u = math.min(1, (os.clock() - t0) / fly)
				local e = u * u
				local r = cfg.coinRadius * (1 - e)
				local a = a0 + e * math.pi * 1.4
				local pos = st.center + Vector3.new(math.cos(a) * r, h0 * (1 - e) + 0.5 * e, math.sin(a) * r)
				coin.CFrame = CFrame.new(pos) * CFrame.Angles(0, os.clock() * 8 + i, 0) -- standing on its edge, spinning
				coin.Size = Vector3.new(C0 * 0.18, C0, C0) * (1 - 0.6 * e)
				if u >= 1 then
					break
				end
				RunService.RenderStepped:Wait()
			end
			coin:Destroy()
			if not ctx.finished then
				SoundController.play("coin")
				if st.light then
					st.light.Brightness += 0.12
				end
			end
		end)
	end
	if st.orbit then
		local O = cfg.orbit
		st.orbit.radiusTo = O.startRadius - (O.startRadius - O.endRadius) * 0.25
	end
	hold(ctx, seconds, keep)
end

REBIRTH_BEATS.charge = function(ctx, seconds, keep)
	local cfg = Config.show.rebirth
	local st = stages[ctx]
	if not st then
		hold(ctx, seconds, keep)
		return
	end
	local C = rebirthColours()
	local star = starFlare(st, C.rebirth)
	st.star = star
	-- you start to glow
	local char = me.Character
	if char then
		local glow = Instance.new("Highlight")
		glow.Name = "RebirthGlow"
		glow.FillColor = Theme.white
		glow.OutlineColor = C.rebirth
		glow.FillTransparency = 1
		glow.OutlineTransparency = 0.2
		glow.DepthMode = Enum.HighlightDepthMode.Occluded
		glow.Adornee = char
		glow.Parent = st.folder
		st.glow = glow
		TweenService:Create(glow, TweenInfo.new(seconds), { FillTransparency = 0.45 }):Play()
	end
	local O = cfg.orbit
	local P = cfg.pulses
	local hum = st.hum
	if hum then
		TweenService:Create(hum, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { PlaybackSpeed = cfg.hum.to }):Play()
	end
	local suckAt = seconds * 0.72
	local t0 = os.clock()
	local fired = 0
	local sucked = false
	while not ctx.finished and os.clock() - t0 < seconds do
		if ctx.skipped and not keep then
			break
		end
		local t = os.clock() - t0
		local due = math.min(P, math.floor(t / (seconds * 0.7 / P)) + 1)
		while fired < due do
			fired += 1
			local k = fired / P
			shockwave(st, if fired == P then C.gold else C.rebirth, cfg.pulseRadius * (0.7 + 0.3 * k), 0.55)
			SoundController.play("upgrade_hit", 1 + 0.14 * (fired - 1))
			SoundController.play("tink", 1 + 0.2 * (fired - 1))
			st.speed = 1 + cfg.pulseSpin * fired
			st.kickUntil = os.clock() + 0.12
			local size = cfg.star.from + (cfg.star.to - cfg.star.from) * k
			TweenService:Create(star, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = UDim2.fromScale(size, size) }):Play()
			if st.light then
				st.light.Brightness = 1 + 1.5 * k
			end
			if st.orbit then
				st.orbit.radiusTo = O.startRadius - (O.startRadius - O.endRadius) * (0.25 + 0.75 * k)
				st.orbit.heightTo = O.startHeight + (O.endHeight - O.startHeight) * k
			end
		end
		if not sucked and t >= suckAt then
			sucked = true
			SoundController.play("ray_charge") -- the reverse-cymbal suck right before the burst
			for _, r in st.rings do
				r.target *= 0.55 -- the rings pull in toward you
			end
		end
		RunService.RenderStepped:Wait()
	end
end

REBIRTH_BEATS.burst = function(ctx, seconds, keep)
	local cfg = Config.show.rebirth
	local st = stages[ctx]
	local C = rebirthColours()
	SoundController.play("slam")
	SoundController.play("reveal_secret")
	SoundController.play("rebirth_hit")
	if not ctx.reduced then
		EffectsController.flash() -- the one flash of the show
	end
	if st then
		local pos = st.center
		if st.hum then
			st.hum:Destroy()
			st.hum = nil
		end
		-- a light pillar of our own: thinner and more see-through than the freeze shows' one, so you stay in view
		local PL = cfg.pillar
		local pillar = stagePart(st, Vector3.new(0.1, PL.width, PL.width), C.rebirth, PL.alpha)
		pillar.Shape = Enum.PartType.Cylinder
		task.spawn(function()
			local t0 = os.clock()
			while pillar.Parent do
				local u = (os.clock() - t0)
				local h = PL.height * math.min(1, 1 - (1 - math.min(1, u / PL.rise)) ^ 2)
				pillar.Size = Vector3.new(math.max(0.1, h), PL.width, PL.width)
				pillar.CFrame = CFrame.new(st.ground + Vector3.new(0, h / 2, 0)) * CFrame.Angles(0, 0, math.rad(90))
				pillar.Transparency = PL.alpha + (1 - PL.alpha) * math.clamp((u - PL.rise) / PL.seconds, 0, 1)
				if u > PL.rise + PL.seconds then
					break
				end
				RunService.RenderStepped:Wait()
			end
			pillar:Destroy()
		end)
		EffectsController.rays(pos, C.gold, cfg.rays, seconds * 5)
		EffectsController.burst(pos - Vector3.new(0, 1, 0), C.rebirth, cfg.burstParts)
		EffectsController.burst(pos - Vector3.new(0, 1, 0), C.gold, math.floor(cfg.burstParts / 2))
		shockwave(st, Theme.white, cfg.pulseRadius * 1.6, 0.7)
		-- confetti: every colour of the game's palette
		local lowG = SettingsController.get("lowGraphics") == true
		local cp = stagePart(st, Vector3.one * 0.5, C.gold, 1)
		cp.CFrame = CFrame.new(pos + Vector3.new(0, 2, 0))
		local conf = Instance.new("ParticleEmitter")
		conf.Name = "Confetti"
		conf.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Theme.tiles.pets), ColorSequenceKeypoint.new(0.25, Theme.coin),
			ColorSequenceKeypoint.new(0.5, Theme.go), ColorSequenceKeypoint.new(0.75, Theme.info), ColorSequenceKeypoint.new(1, C.rebirth),
		})
		conf.Size = NumberSequence.new(0.35)
		conf.Speed = NumberRange.new(16, 30)
		conf.Drag = 2.5
		conf.Acceleration = Vector3.new(0, -18, 0)
		conf.Lifetime = NumberRange.new(1.6, 2.6)
		conf.SpreadAngle = Vector2.new(70, 70)
		conf.EmissionDirection = Enum.NormalId.Top
		conf.RotSpeed = NumberRange.new(-300, 300)
		conf.Rotation = NumberRange.new(0, 360)
		conf.LightEmission = 0.3
		conf.Rate = 0
		conf.Parent = cp
		conf:Emit(math.floor(cfg.confetti * (if lowG then 0.5 else 1) * (if ctx.reduced then 0.5 else 1)))
		-- the rings fly outward and fade; the star pops
		for _, r in st.rings do
			r.target = r.radius * 2.6
			r.alphaTarget = 1
		end
		if st.disc then
			TweenService:Create(st.disc, TweenInfo.new(0.8), { Transparency = 0.9 }):Play()
		end
		if st.motes then
			st.motes.Rate *= 0.4
		end
		local star = st.star
		if star then
			TweenService:Create(star, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = UDim2.fromScale(cfg.star.to * 2.2, cfg.star.to * 2.2) }):Play()
			for _, d in star:GetDescendants() do
				if d:IsA("Frame") then
					TweenService:Create(d, TweenInfo.new(0.5), { BackgroundTransparency = 1 }):Play()
				elseif d:IsA("ImageLabel") then
					TweenService:Create(d, TweenInfo.new(0.5), { ImageTransparency = 1 }):Play()
				end
			end
		end
		if st.glow then
			TweenService:Create(st.glow, TweenInfo.new(1.2), { FillTransparency = 0.85 }):Play()
		end
		st.speed = 0.6
	end
	hold(ctx, seconds, keep)
end

-- one line of the reveal: icons and words laid out left to right by their real widths, centred
local function revealRow(parent: GuiObject, y: number, h: number, items: { { kind: string, value: string, color: Color3? } }): Frame
	local row = Instance.new("Frame")
	row.Name = "Row"
	row.BackgroundTransparency = 1
	row.AnchorPoint = Vector2.new(0.5, 0)
	row.Position = UDim2.fromScale(0.5, y)
	row.Size = UDim2.fromScale(1, h)
	row.Parent = parent
	local parts: { GuiObject } = {}
	for _, it in items do
		if it.kind == "text" then
			local t = Ui.label(row, it.value, UDim2.fromScale(0.6, 1), UDim2.fromScale(0, 0))
			t.TextXAlignment = Enum.TextXAlignment.Left
			if it.color then
				t.TextColor3 = it.color
			end
			table.insert(parts, t)
		else
			local img = Ui.image(row, it.value, UDim2.fromScale(0.2, if it.kind == "arrow" then 0.8 else 1.05), UDim2.fromScale(0, 0))
			if it.kind == "arrow" then
				local a = img:FindFirstChildOfClass("UIAspectRatioConstraint")
				if a then
					a.AspectRatio = 512 / 384
				end
			end
			table.insert(parts, img)
		end
	end
	task.defer(function()
		local w = math.max(1, row.AbsoluteSize.X)
		local gap = 0.008
		local widths: { number } = {}
		local total = -gap
		for _, p in parts do
			local pw = if p:IsA("TextLabel") then p.TextBounds.X / w else p.AbsoluteSize.X / w
			table.insert(widths, pw)
			total += pw + gap
		end
		local x = 0.5 - total / 2
		for i, p in parts do
			p.AnchorPoint = Vector2.new(0, 0.5)
			p.Position = UDim2.fromScale(x, 0.5)
			if p:IsA("TextLabel") then
				p.Size = UDim2.fromScale(widths[i] + 0.01, 1)
			end
			x += widths[i] + gap
		end
	end)
	return row
end

REBIRTH_BEATS.reveal = function(ctx, seconds, keep)
	local cfg = Config.show.rebirth
	local R = cfg.reveal
	local gui = ctx.gui
	local d = ctx.data
	local C = rebirthColours()
	dropTitleCard(ctx, 0.2) -- after a SKIP the card may still be up
	local st = stages[ctx]
	if st and st.orbit then
		st.orbit.radiusTo = cfg.orbit.endRadius
		st.orbit.lookTo = cfg.orbit.revealLook
	end
	local skip = gui and gui:FindFirstChild("Skip")
	if skip then
		skip:Destroy() -- nothing left to skip, and it sat on the reveal's last line
	end
	if not gui then
		hold(ctx, seconds, keep)
		return
	end
	SoundController.play("rebirth_fanfare")
	local group = Instance.new("CanvasGroup")
	group.Name = "Reveal"
	group.BackgroundTransparency = 1
	group.Size = UDim2.fromScale(1, 1)
	group.Parent = gui
	-- the sunburst behind the words, turning slowly (still with reduced motion)
	local sun = Instance.new("ImageLabel")
	sun.Name = "Sunburst"
	sun.BackgroundTransparency = 1
	sun.Image = Config.images.icons.sunburst
	sun.ImageColor3 = C.gold
	sun.ImageTransparency = 1
	sun.AnchorPoint = Vector2.new(0.5, 0.5)
	sun.Position = UDim2.fromScale(0.5, R.y)
	sun.Size = UDim2.fromScale(R.sunburst, R.sunburst)
	sun.SizeConstraint = Enum.SizeConstraint.RelativeYY
	sun.ZIndex = 0
	sun.Parent = group
	TweenService:Create(sun, TweenInfo.new(0.35), { ImageTransparency = 0.25 }):Play()
	if not ctx.reduced then
		local t0 = os.clock()
		local conn: RBXScriptConnection
		conn = RunService.RenderStepped:Connect(function()
			if not sun.Parent then
				conn:Disconnect()
				return
			end
			sun.Rotation = (os.clock() - t0) * R.sunSpin * 360
		end)
	end
	-- small word above
	local small = Ui.label(group, spaced("NEW REBIRTH"), UDim2.fromScale(0.5, R.small), UDim2.fromScale(0.25, R.y - R.big / 2 - R.small - 0.01))
	small.Name = "Small"
	small.TextColor3 = C.gold
	-- REBIRTH n, letter by letter
	local word = `REBIRTH {d.rebirths}`
	local letters: { string } = {}
	for _, cp in utf8.codes(word) do
		table.insert(letters, utf8.char(cp))
	end
	local big = Instance.new("Frame")
	big.Name = "Big"
	big.BackgroundTransparency = 1
	big.AnchorPoint = Vector2.new(0.5, 0.5)
	big.Position = UDim2.fromScale(0.5, R.y)
	big.Size = UDim2.fromScale(1, R.big)
	big.Parent = group
	local vh = math.max(1, gui.AbsoluteSize.Y)
	local vw = math.max(1, gui.AbsoluteSize.X)
	local letterW = R.big * vh * 0.62 / vw -- each letter's box, a share of the screen width
	local gapW = letterW * R.letterGap
	local function boxW(ch: string): number
		return if ch == " " then letterW * R.spaceWidth else letterW
	end
	local totalW = -gapW
	for _, ch in letters do
		totalW += boxW(ch) + gapW
	end
	local fit = math.min(1, 0.92 / totalW) -- a phone in portrait: the word shrinks to fit
	letterW *= fit
	gapW *= fit
	totalW *= fit
	local x = 0.5 - totalW / 2
	local per = math.min(0.09, seconds * 0.4 / #letters)
	for i, ch in letters do
		local isNumber = ch:match("%d") ~= nil
		local w = boxW(ch)
		local t = Ui.label(big, ch, UDim2.fromScale(w, fit), UDim2.fromScale(x, (1 - fit) / 2))
		x += w + gapW
		t.Name = "Letter" .. i
		t.TextColor3 = if isNumber then C.gold else Theme.white
		local s = t:FindFirstChildOfClass("UIStroke")
		if s then
			s.Thickness = 3
		end
		t.Visible = false
		local sc = Instance.new("UIScale")
		sc.Scale = U.slamFrom
		sc.Parent = t
		task.delay((i - 1) * per, function()
			if ctx.finished or not t.Parent then
				return
			end
			t.Visible = ch ~= " "
			if ch ~= " " then
				SoundController.play("upgrade_chime", 1 + 0.05 * i)
			end
			TweenService:Create(sc, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		end)
	end
	-- what you got: coin x1 [arrow] coin x1.5, then the gun / island it brings
	local before = Config.rebirthIncome(d.rebirths - 1)
	local lineY = R.y + R.big / 2 + 0.02
	local row = revealRow(group, lineY, R.line, {
		{ kind = "image", value = Config.images.icons.coin },
		{ kind = "text", value = `x{before}` },
		{ kind = "arrow", value = Config.images.icons.arrow },
		{ kind = "image", value = Config.images.icons.coin },
		{ kind = "text", value = `x{d.mult}`, color = C.gold },
		{ kind = "text", value = "  coins + training" },
	})
	row.Name = "Mult"
	local extras: { string } = {}
	local g = typeof(d.gun) == "number" and Config.guns.list[d.gun]
	if g then
		table.insert(extras, `New gun: {g.name}`)
	end
	for id, need in Config.world.rebirthGates do
		local isl = Config.world.islands[id]
		if need == d.rebirths and isl and isl.ready then
			-- the gate also needs its Cold Power, and a rebirth always resets Cold Power to 0 (RebirthService),
			-- so the show says what's still missing instead of "New island" (QA IR-19)
			local cp = Config.need(id)
			table.insert(extras, if cp <= 0 then `New island: {isl.name}` else `{isl.name} opens at {Config.powerText(cp)} Cold Power`)
		end
	end
	local extraRow: Frame? = nil
	if #extras > 0 then
		extraRow = revealRow(group, lineY + R.line + 0.01, R.line * 0.8, { { kind = "text", value = table.concat(extras, "   "), color = C.ice } })
		;(extraRow :: Frame).Name = "Extra"
	end
	for _, r in { row, extraRow } do
		if r then
			r.Visible = false
			local sc = Instance.new("UIScale")
			sc.Scale = 0.6
			sc.Parent = r
			task.delay(#letters * per + 0.15, function()
				if ctx.finished or not r.Parent then
					return
				end
				r.Visible = true
				TweenService:Create(sc, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
			end)
		end
	end
	hold(ctx, seconds, keep)
end

REBIRTH_BEATS.back = function(ctx, seconds, keep)
	local st = stages[ctx]
	if st then
		st.orbit = nil -- the camera tween below takes over
	end
	local gui = ctx.gui
	local group = gui and gui:FindFirstChild("Reveal") :: CanvasGroup?
	if group then
		TweenService:Create(group, TweenInfo.new(seconds * 0.8), { GroupTransparency = 1 }):Play()
	end
	local home = CameraController.homeCFrame()
	if ctx.cam and home then
		moveCamera(ctx, home, seconds)
	end
	clearStage(ctx)
	hold(ctx, seconds, keep)
end

function Show.rebirth(data: any)
	local cfg = Config.show.rebirth
	if typeof(data) ~= "table" or typeof(data.rebirths) ~= "number" or typeof(data.mult) ~= "number" then
		return
	end
	if running then
		finish(running) -- one show at a time
	end
	local ctx: Ctx = {
		name = "rebirth", cfg = cfg, data = data, def = nil, reduced = SettingsController.get("reducedMotion") == true,
		skipped = false, finished = false, model = nil, cube = nil, real = nil, at = CFrame.new(), size = 0,
		color = Theme.booths.rebirth, gui = nil, cam = nil, frost = nil, controls = nil, conn = nil,
	}
	running = ctx
	-- owner 2026-11-12: the gun goes away for the show (hands free for the glow-up) and comes back after.
	-- Asked through SetGear like a hotbar tap, so the server decides and everyone sees it.
	local heldBefore = me:GetAttribute("Held")
	local putAway = typeof(heldBefore) == "string" and heldBefore ~= "none"
	if putAway then
		State.send("SetGear", "none")
	end
	local ok, err = pcall(function()
		local gui = Instance.new("ScreenGui")
		gui.Name = "Show"
		gui.ResetOnSpawn = false
		gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
		gui.DisplayOrder = 10
		gui.Parent = me:WaitForChild("PlayerGui")
		ctx.gui = gui
		Screen.setHidden(true)
		local hum = me.Character and me.Character:FindFirstChildOfClass("Humanoid")
		if hum then
			ctx.controls = { hum = hum, walk = hum.WalkSpeed, jump = hum.JumpPower, jumpH = hum.JumpHeight, rotate = hum.AutoRotate }
			hum.WalkSpeed, hum.JumpPower, hum.JumpHeight, hum.AutoRotate = 0, 0, 0, false
		end
		ctx.cam = CameraController.borrow()
		buildStage(ctx)
		if State.view and State.view.seenShows and State.view.seenShows.rebirth then
			skipButton(ctx)
		end
		local scale = if ctx.reduced then 0.5 else 1
		for _, beat in cfg.beats do
			if ctx.finished then
				break
			end
			if ctx.skipped and not beat.keepOnSkip then
				continue
			end
			local play = REBIRTH_BEATS[beat.name]
			if play then
				play(ctx, beat.time * scale, beat.keepOnSkip == true)
			end
		end
	end)
	clearStage(ctx) -- always, even when a beat errored or a newer show ended this one
	finish(ctx)
	-- the gun back in your hand, unless you picked something else on the hotbar meanwhile
	if putAway and me:GetAttribute("Held") == "none" then
		State.send("SetGear", heldBefore)
	end
	if not ok then
		warn("[Show] rebirth show failed:", err)
	end
end

function Show.Init() end

function Show.Start()
	State.Notify:Connect(function(kind: string, data: any)
		if kind == "frozen" and typeof(data) == "table" and typeof(data.show) == "string" then
			task.spawn(Show.play, data.show, data)
		elseif kind == "thawed" and typeof(data) == "table" and (data.first or Config.show.thawReveal.tiers[data.tier]) then
			task.spawn(Show.thawReveal, data)
		elseif kind == "gunBought" then
			task.spawn(Show.gunBuy, data)
		elseif kind == "rebirthed" then
			task.spawn(Show.rebirth, data)
		elseif kind == "panUpgraded" and not Config.motion.upgrade.fastPan then -- the fast one is UpgradeMotion's
			task.spawn(Show.panUpgrade, data)
		end
	end)
	-- a respawn mid-show ends it cleanly
	me.CharacterRemoving:Connect(function()
		if running then
			finish(running)
		end
	end)
end

return Show

