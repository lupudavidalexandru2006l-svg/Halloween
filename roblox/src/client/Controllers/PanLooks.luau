--!strict
-- PanLooks (Round 4 phase 5): owns how each pan looks for its Look level (Config.pan.looks: garden ->
-- wood -> stone -> crystal ice -> aurora; colours and materials in Theme.panLooks). Round 5: the garden
-- look is white rail fences on a striped lawn (the stripes only show on that look), and the second
-- Thaw Machine shows once its pan has it (the Plot's "Machines" attribute, PenService). Every client draws
-- every pan from the map's PanLook<i> (set by PanService). MapArt still builds the pan once; this module
-- restyles its fence posts, rails and floor on this client only and adds the extras (crystals on crystal
-- ice, glowing colour-drifting rails on aurora). It also gives the upgrade show (Show.panUpgrade) its
-- pieces: a build-up glow, the old pieces popping off and the new ones dropping in with a squash.
-- And the "too hot for your pan" bounce: you're pushed back out of the door and your cubes shake.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Theme = require(ReplicatedStorage.Shared.Theme)
local State = require(script.Parent.State)
local SettingsController = require(script.Parent.SettingsController)
local SoundController = require(script.Parent.SoundController)

local PanLooks = {}
local me = Players.LocalPlayer
local P = Config.pan
local W = Config.world.pans

type Piece = { part: BasePart, kind: string, cf: CFrame, size: Vector3 }
type Pan = { pieces: { Piece }, look: number, extras: Folder?, busy: boolean }
local pans: { [number]: Pan } = {}

local function near(a: number, b: number): boolean
	return math.abs(a - b) < 0.05
end

-- MapArt's own pan pieces, by name: fence posts and their caps, rails, the lawn and its stripes
local KINDS: { [string]: string } = { FencePost = "post", PostCap = "post", FenceRail = "rail", PanFloor = "floor", LawnStripe = "stripe" }
local function scan(i: number): { Piece }?
	local map = workspace:FindFirstChild("Map")
	local folder = map and map:FindFirstChild("Pan" .. i, true)
	if not folder then
		return nil
	end
	local out: { Piece } = {}
	for _, c in folder:GetChildren() do
		local kind = KINDS[c.Name]
		if kind and c:IsA("BasePart") then
			table.insert(out, { part = c, kind = kind, cf = c.CFrame, size = c.Size })
		end
	end
	return if #out > 0 then out else nil
end

-- the second Thaw Machine: only on pans that have it
local function machines(i: number)
	local map = workspace:FindFirstChild("Map")
	local plot = map and map:FindFirstChild("Plot" .. i)
	local pan = map and map:FindFirstChild("Pan" .. i, true)
	local second = pan and pan:FindFirstChild("ThawMachine2")
	if not plot or not second then
		return
	end
	local on = plot:GetAttribute("Machines") == 2
	for _, d in second:GetDescendants() do
		if d:IsA("BasePart") then
			d.LocalTransparencyModifier = if on then 0 else 1
			d.CanCollide = false
		elseif d:IsA("Light") or d:IsA("ParticleEmitter") then
			(d :: any).Enabled = on
		end
	end
end

function PanLooks.lookOf(i: number): number
	local map = workspace:FindFirstChild("Map")
	local v = map and map:GetAttribute("PanLook" .. i)
	return if typeof(v) == "number" then math.clamp(math.floor(v), 1, #P.looks) else 1
end

function PanLooks.style(look: number): { [string]: any }
	local entry = P.looks[look] or P.looks[1]
	return Theme.panLooks[entry.key] or Theme.panLooks.garden
end

local function paint(piece: Piece, st: { [string]: any })
	local p = piece.part
	if piece.kind == "post" then
		p.Color, p.Material = st.post, st.postMat
	elseif piece.kind == "rail" then
		p.Color, p.Material = st.rail, st.railMat
	elseif piece.kind == "stripe" then
		-- mowed stripes only on the lawn look; the other floors are plain
		p.Color = st.stripe or st.floor
		p.Transparency = if st.stripe then 0 else 1
	else
		p.Color, p.Material = st.floor, st.floorMat
	end
end

-- crystals on the posts (crystal ice, aurora): made on this client, drawn over MapArt's posts
local function extras(pan: Pan, i: number, st: { [string]: any }): Folder?
	if pan.extras then
		pan.extras:Destroy()
		pan.extras = nil
	end
	if not st.crystal then
		return nil
	end
	local f = Instance.new("Folder")
	f.Name = "PanLook" .. i
	local n = 0
	for _, piece in pan.pieces do
		if piece.kind == "post" then
			n += 1
			if n % P.crystalEvery == 0 then
				local c = Instance.new("Part")
				c.Name = "Crystal"
				c.Anchored, c.CanCollide, c.CanQuery, c.CanTouch, c.CastShadow = true, false, false, false, false
				c.Material = Enum.Material.Glass
				c.Transparency = 0.15
				c.Color = st.crystal
				c.Size = Vector3.new(0.55, 1.1, 0.55)
				c.CFrame = piece.cf * CFrame.new(0, piece.size.Y / 2 + 0.45, 0) * CFrame.Angles(0, math.rad(45), math.rad(12))
				c.Parent = f
			end
		end
	end
	f.Parent = workspace
	pan.extras = f
	return f
end

-- draw pan i in a look (instantly)
function PanLooks.apply(i: number, look: number)
	local pan = pans[i]
	if not pan then
		local pieces = scan(i)
		if not pieces then
			return
		end
		pan = { pieces = pieces, look = 0, extras = nil, busy = false }
		pans[i] = pan
	end
	local st = PanLooks.style(look)
	for _, piece in pan.pieces do
		paint(piece, st)
	end
	extras(pan, i, st)
	pan.look = look
end

function PanLooks.center(i: number): Vector3
	local pl = Config.world.plots[i]
	return Vector3.new(pl.x, W.soilHeight, pl.z)
end

-- the show's build-up: a soft glowing box round the pan that brightens over `seconds`
function PanLooks.glow(i: number, color: Color3, seconds: number): BasePart
	local pl = Config.world.plots[i]
	local g = Instance.new("Part")
	g.Name = "PanUpgradeGlow"
	g.Anchored, g.CanCollide, g.CanQuery, g.CanTouch, g.CastShadow = true, false, false, false, false
	g.Material = Enum.Material.ForceField
	g.Color = color
	g.Transparency = 1
	g.Size = Vector3.new(W.width + 1, W.fenceHeight + 1.4, W.length + 1)
	g.CFrame = CFrame.new(pl.x, W.soilHeight + g.Size.Y / 2, pl.z)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 30
	light.Brightness = 0
	light.Parent = g
	g.Parent = workspace
	TweenService:Create(g, TweenInfo.new(seconds, Enum.EasingStyle.Sine, Enum.EasingDirection.In), { Transparency = Config.show.panUpgrade.glowTransparency }):Play()
	TweenService:Create(light, TweenInfo.new(seconds, Enum.EasingStyle.Sine, Enum.EasingDirection.In), { Brightness = 3 }):Play()
	return g
end

-- the old pieces pop off: copies fly up and away, spinning, and fade; the real ones hide until the drop
function PanLooks.popOff(i: number, seconds: number)
	local pan = pans[i]
	if not pan then
		return
	end
	pan.busy = true
	local cfg = Config.show.panUpgrade
	local rng = Random.new()
	local copies: { BasePart } = {}
	for _, piece in pan.pieces do
		if piece.kind ~= "floor" and piece.kind ~= "stripe" then
			local c = piece.part:Clone()
			c.Anchored = true
			c.CanCollide, c.CanQuery, c.CanTouch = false, false, false
			c.Parent = workspace
			table.insert(copies, c)
			local out = (piece.cf.Position - PanLooks.center(i)) * Vector3.new(1, 0, 1)
			local dir = if out.Magnitude > 0.1 then out.Unit else Vector3.new(0, 0, 1)
			local to = piece.cf.Position + dir * cfg.popSpeed * seconds + Vector3.new(0, cfg.popUp * seconds + rng:NextNumber(0, 2), 0)
			local spin = CFrame.Angles(rng:NextNumber(-1, 1) * cfg.popSpin * seconds, rng:NextNumber(-1, 1) * cfg.popSpin * seconds, 0)
			TweenService:Create(c, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				CFrame = CFrame.new(to) * piece.cf.Rotation * spin, Transparency = 1,
			}):Play()
			piece.part.Transparency = 1
		end
	end
	if pan.extras then
		pan.extras:Destroy()
		pan.extras = nil
	end
	task.delay(seconds + 0.05, function()
		for _, c in copies do
			c:Destroy()
		end
	end)
end

-- the new pieces drop in from above, one after another along the fence, and squash as they land
function PanLooks.dropIn(i: number, look: number, seconds: number)
	local pan = pans[i]
	if not pan then
		return
	end
	local cfg = Config.show.panUpgrade
	local st = PanLooks.style(look)
	local fall = seconds * 0.45
	local n = #pan.pieces
	for k, piece in pan.pieces do
		paint(piece, st)
		local p = piece.part
		if piece.kind == "floor" or piece.kind == "stripe" then
			continue -- the floor changes under the falling pieces
		end
		local delay = (k - 1) / math.max(1, n - 1) * (seconds - fall) * 0.9
		p.CFrame = piece.cf + Vector3.new(0, cfg.dropHeight, 0)
		task.delay(delay, function()
			p.Transparency = 0
			local t = TweenService:Create(p, TweenInfo.new(fall * 0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { CFrame = piece.cf })
			t.Completed:Once(function()
				-- squash on landing, then spring back
				local squash = piece.size * Vector3.new(1 + cfg.squash * 0.5, 1 - cfg.squash, 1 + cfg.squash * 0.5)
				p.Size = squash
				p.CFrame = piece.cf * CFrame.new(0, -(piece.size.Y - squash.Y) / 2, 0)
				TweenService:Create(p, TweenInfo.new(fall * 0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = piece.size, CFrame = piece.cf }):Play()
			end)
			t:Play()
		end)
	end
	task.delay(seconds, function()
		PanLooks.settle(i, look)
	end)
end

-- put every piece back exactly in place (end of a show, or a show cut short)
function PanLooks.settle(i: number, look: number)
	local pan = pans[i]
	if not pan then
		return
	end
	for _, piece in pan.pieces do
		piece.part.CFrame = piece.cf
		piece.part.Size = piece.size
		if piece.kind ~= "stripe" then
			piece.part.Transparency = 0
		end
	end
	pan.busy = false
	PanLooks.apply(i, look)
end

function PanLooks.isBusy(i: number): boolean
	local pan = pans[i]
	return pan ~= nil and pan.busy
end

-- a cube too hot for your pan: pushed back out of the door, the cubes in your hands shake
local function bounce()
	local char = me.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then
		return
	end
	local B = P.bounce
	hrp.AssemblyLinearVelocity = Vector3.new(0, B.up, B.push) -- the doors face the plaza (+Z)
	SoundController.play("bounce")
	task.wait(0.1) -- the cubes are handed back as new parts; let them arrive
	local S = Config.guns.tooWarmShake
	local reduced = SettingsController.get("reducedMotion") == true
	local folder = workspace:FindFirstChild("Cubes")
	local welds: { { w: Weld, c0: CFrame } } = {}
	for _, c in (if folder then folder:GetChildren() else {}) do
		if c:GetAttribute("OwnerUserId") == me.UserId then
			local w = c:FindFirstChildOfClass("Weld")
			if w then
				table.insert(welds, { w = w, c0 = w.C0 })
			end
		end
	end
	local t0 = os.clock()
	while os.clock() - t0 < S.seconds do
		local left = 1 - (os.clock() - t0) / S.seconds
		local side = math.sin(os.clock() * S.speed) * S.amp * 2 * left * (if reduced then 0.5 else 1)
		for _, e in welds do
			if e.w.Parent then
				e.w.C0 = e.c0 * CFrame.new(side, 0, 0)
			end
		end
		RunService.RenderStepped:Wait()
	end
	for _, e in welds do
		if e.w.Parent then
			e.w.C0 = e.c0
		end
	end
end

function PanLooks.Init() end

function PanLooks.Start()
	-- every pan follows its PanLook<i>, unless its own upgrade show is drawing it right now
	local function refresh()
		for i in Config.world.plots do
			local pan = pans[i]
			local look = PanLooks.lookOf(i)
			if not pan or (not pan.busy and pan.look ~= look) then
				PanLooks.apply(i, look)
			end
			machines(i)
		end
	end
	task.spawn(function()
		local map = workspace:WaitForChild("Map", 30)
		if not map then
			return
		end
		map.AttributeChanged:Connect(function(name: string)
			if string.sub(name, 1, 7) == "PanLook" then
				refresh()
			end
		end)
		for i in Config.world.plots do
			local plot = map:WaitForChild("Plot" .. i, 10)
			if plot then
				plot:GetAttributeChangedSignal("Machines"):Connect(function()
					machines(i)
				end)
			end
		end
		for _ = 1, 10 do -- the hub streams in first; look again a few times in case it's late
			refresh()
			task.wait(2)
		end
	end)
	-- aurora: the rails' colours drift slowly (only pans near enough to see)
	RunService.Heartbeat:Connect(function()
		local cam = workspace.CurrentCamera
		for i, pan in pans do
			local st = PanLooks.style(pan.look)
			if st.aurora and not pan.busy and cam and (cam.CFrame.Position - PanLooks.center(i)).Magnitude < P.drawDistance then
				local cols = st.aurora :: { Color3 }
				local t = (os.clock() * P.auroraSpeed) % 1 * #cols
				local a = math.floor(t)
				local c = cols[a % #cols + 1]:Lerp(cols[(a + 1) % #cols + 1], t - a)
				for _, piece in pan.pieces do
					if piece.kind == "rail" then
						piece.part.Color = c
					end
				end
			end
		end
	end)
	State.Notify:Connect(function(kind: string)
		if kind == "panBounce" then
			task.spawn(bounce)
		end
	end)
end

return PanLooks
