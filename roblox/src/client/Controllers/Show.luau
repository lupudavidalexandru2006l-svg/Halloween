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
		local from = pet + dir * ctx.cfg.pushDistance * 1.6 + Vector3.new(0, ctx.cfg.pushHeight * 1.5, 0)
		local to = pet + dir * ctx.cfg.pushDistance + Vector3.new(0, ctx.cfg.pushHeight, 0)
		cam.CFrame = CFrame.lookAt(from, pet)
		moveCamera(ctx, CFrame.lookAt(to, pet + Vector3.new(0, 0.5, 0)), seconds)
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

-- the cube flies into your hands and the camera comes home
BEATS.fly = function(ctx, seconds, keep)
	local gui = ctx.gui
	local reveal = gui and gui:FindFirstChild("Reveal")
	if reveal then
		reveal:Destroy()
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

-- Safe to call any number of times: each thing the show holds is given back once, whenever it was
-- taken (a show finished early by a newer one may still be setting up, and runs this again at its end)
local function finish(ctx: Ctx)
	local first = not ctx.finished
	ctx.finished = true
	if running == ctx then
		running = nil
	end
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

-- ---------- the rebirth show (Config.show.rebirth, Round 4 phase 7) ----------
-- At the Rebirth Booth: the camera pushes in to face you, an ice burst (one flash), then the new
-- rebirth and coin multiplier slam in, with the free gun if one came with it. The server has already
-- rebirthed and saved; the show only plays it. SKIP from the second rebirth; reduced motion halves it.

local REBIRTH_BEATS: { [string]: (Ctx, number, boolean) -> () } = {}

REBIRTH_BEATS.push = function(ctx, seconds, keep)
	local cam = ctx.cam
	local hrp = me.Character and me.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if cam and hrp then
		local cfg = ctx.cfg
		local at = hrp.Position + Vector3.new(0, 1, 0)
		-- you face the booth when you use it, so the camera swings round to the open side: away from
		-- the booth at a three-quarter angle (never into its wall)
		local booth = at + hrp.CFrame.LookVector
		for _, b in Config.world.booths do
			if b.id == "rebirth" then
				booth = b.pos
			end
		end
		local away = (at - booth) * Vector3.new(1, 0, 1)
		local base = if away.Magnitude > 0.1 then away.Unit else Vector3.new(0, 0, -1)
		local dir = (CFrame.Angles(0, math.rad(cfg.angle), 0) * base).Unit
		-- anything in the way (a wall, a lamp) pulls the camera in front of it
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { me.Character :: Model }
		local function clear(offset: Vector3): Vector3
			local hit = workspace:Raycast(at, offset, params)
			return if hit then at + offset.Unit * math.max(2, hit.Distance - 1) else at + offset
		end
		local from = clear(dir * cfg.pushDistance * 1.7 + Vector3.new(0, cfg.pushHeight * 1.6, 0))
		local to = clear(dir * cfg.pushDistance + Vector3.new(0, cfg.pushHeight, 0))
		cam.CFrame = CFrame.lookAt(from, at)
		moveCamera(ctx, CFrame.lookAt(to, at), seconds)
		ctx.at = CFrame.new(at)
	end
	hold(ctx, seconds, keep)
end

REBIRTH_BEATS.burst = function(ctx, seconds, keep)
	local cfg = ctx.cfg
	local pos = ctx.at.Position
	SoundController.play("slam")
	EffectsController.burst(pos, Theme.fx.frost, cfg.burstParts)
	EffectsController.burst(pos, ctx.color, math.floor(cfg.burstParts / 2))
	if cfg.rays > 0 then
		EffectsController.rays(pos, ctx.color, cfg.rays, seconds * 4)
	end
	if cfg.flash then
		EffectsController.flash() -- one flash per show
	end
	hold(ctx, seconds, keep)
end

REBIRTH_BEATS.slam = function(ctx, seconds, keep)
	local gui = ctx.gui
	if gui then
		local d = ctx.data
		local title = Ui.label(gui, `REBIRTH {d.rebirths}!`, UDim2.fromScale(U.titleSize[1], U.titleSize[2]), UDim2.fromScale((1 - U.titleSize[1]) / 2, U.titleY - U.titleSize[2]))
		title.Name = "RebirthTitle"
		title.TextColor3 = ctx.color
		local mult = Ui.label(gui, `x{d.mult} COINS`, UDim2.fromScale(U.titleSize[1], U.titleSize[2] * 0.8), UDim2.fromScale((1 - U.titleSize[1]) / 2, U.titleY))
		mult.Name = "RebirthMult"
		mult.TextColor3 = Theme.coin
		local lines = { title, mult }
		local g = typeof(d.gun) == "number" and Config.guns.list[d.gun]
		local gifts: { string } = {}
		if Config.rebirth.slotsPer > 0 then
			table.insert(gifts, `+{Config.rebirth.slotsPer} pan slot`)
		end
		if g then
			table.insert(gifts, `New gun: {g.name}`)
		end
		local extra = table.concat(gifts, "   ")
		local sub = Ui.label(gui, extra, UDim2.fromScale(U.nameSize[1], U.nameSize[2] * 0.8), UDim2.fromScale((1 - U.nameSize[1]) / 2, U.titleY + U.titleSize[2] * 0.85))
		sub.Name = "RebirthGift"
		table.insert(lines, sub)
		for i, t in lines do
			local s = Instance.new("UIScale")
			s.Scale = U.slamFrom
			s.Parent = t
			t.Visible = false
			task.delay((i - 1) * math.min(0.25, seconds * 0.15), function()
				t.Visible = true
				TweenService:Create(s, TweenInfo.new(math.min(0.3, seconds * 0.2), Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
			end)
		end
		SoundController.play("pan_up")
	end
	hold(ctx, seconds, keep)
end

REBIRTH_BEATS.back = function(ctx, seconds, keep)
	local home = CameraController.homeCFrame()
	if ctx.cam and home then
		moveCamera(ctx, home, seconds)
	end
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
	finish(ctx)
	if not ok then
		warn("[Show] rebirth show failed:", err)
	end
end

function Show.Init() end

function Show.Start()
	State.Notify:Connect(function(kind: string, data: any)
		if kind == "frozen" and typeof(data) == "table" and typeof(data.show) == "string" then
			task.spawn(Show.play, data.show, data)
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

