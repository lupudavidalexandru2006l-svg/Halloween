--!strict
-- GearController (Round 5): the hotbar at the bottom middle. One slot per thing you own (the Ice Ray,
-- Slow Gel once bought): tap / click a slot, press 1-2, or gamepad L1 / R1 to hold it; tap the held
-- one again to put it away. The server decides what you hold (GearService, the "Held" attribute).
-- While Slow Gel is held, a click / tap on the ground throws a puddle (the server checks reach and the
-- cooldown; the slot drains while it cools down). Above the slots: your shield pill while you're safe
-- from ray-tag (TagService, the "ShieldUntil" attribute).
-- Frost Bombs (2026-11-19): slot 2 once bought; a click / tap / R2 places one at your feet (BombService). Frozen by
-- a bomb (the "CanBreak" attribute): a big "TAP!" card in the middle; every tap, click or key cracks the ice.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Theme = require(ReplicatedStorage.Shared.Theme)
local Ui = require(script.Parent.Parent.Lib.Ui)
local State = require(script.Parent.State)
local Screen = require(script.Parent.Screen)
local InputController = require(script.Parent.InputController)
local SoundController = require(script.Parent.SoundController)
local EffectsController = require(script.Parent.EffectsController)
local RayController = require(script.Parent.RayController)
local SettingsController = require(script.Parent.SettingsController)

local GearController = {}
local H = Config.hotbar
local me = Players.LocalPlayer
local bar: Frame
local slots: { [string]: { block: Ui.Block, key: TextLabel, cool: Frame, coolFill: UIGradient } } = {}
local shieldPill: Frame
local shieldText: TextLabel
local coolUntil = 0

local ICONS = { ray = Config.images.icons.ray, gel = Config.gearIcons.gel or Config.images.icons.motion,
	bomb = Config.gearIcons.frost_bombs or Config.images.icons.temp } :: { [string]: string } -- gel: its own painted flask (2026-11-15); bomb: placeholder until its painted icon

local function held(): string
	local h = me:GetAttribute("Held")
	return if typeof(h) == "string" then h else "ray"
end

local function owned(): { string }
	local list = {}
	for _, s in H.slots do
		if s.id == "ray" or (s.id == "gel" and me:GetAttribute("GearGel") == true) or (s.id == "bomb" and me:GetAttribute("GearBomb") == true) then
			table.insert(list, s.id)
		end
	end
	return list
end

local function choose(id: string)
	if not table.find(owned(), id) then
		return
	end
	SoundController.play("click")
	State.send("SetGear", if held() == id then "none" else id)
end

-- the cube is in your hands: true only once it has flown there (owner 2026-11-16: the HUD vanished half a
-- second before the cube arrived and looked weird), so the hotbar steps aside as the cube lands
local lockedAt = 0
local function handsFull(): boolean
	return me:GetAttribute("GunLocked") == true and os.clock() - lockedAt >= Config.show.freeze.flySeconds
end
GearController.handsFull = handsFull

local function refresh()
	local list = owned()
	bar:SetAttribute("Slots", #list)
	-- a cube in your hands: the whole hotbar goes away until it's home (GearService refuses it too)
	bar:SetAttribute("Locked", handsFull())
	local n = #list
	for _, s in H.slots do
		local slot = slots[s.id]
		local i = table.find(list, s.id)
		slot.block.root.Visible = i ~= nil
		if i then
			local w = 1 / (n + (n - 1) * H.gap / H.size)
			slot.block.root.Size = UDim2.fromScale(w, 1 / 1.45)
			slot.block.root.Position = UDim2.fromScale((i - 1) * w * (1 + H.gap / H.size), 1 - 1 / 1.45)
			local on = held() == s.id
			slot.block.face.BackgroundColor3 = if on then Theme.round5.hotbarOn else Theme.round5.hotbar
			slot.block.root.BackgroundColor3 = Ui.darker(slot.block.face.BackgroundColor3)
		end
		slot.key.Visible = InputController.device() == "keyboard"
	end
end

local function makeSlot(s: { id: string, label: string, key: Enum.KeyCode })
	local b = Ui.block(bar, "Slot_" .. s.id, Theme.round5.hotbar, s.label, function()
		choose(s.id)
	end)
	-- tile style: a big icon in the middle, the name on the bottom edge
	b.text.Size = UDim2.fromScale(1, 0.26)
	b.text.Position = UDim2.fromScale(0, 0.72)
	Ui.image(b.face, ICONS[s.id], UDim2.fromScale(0.72, 0.66), UDim2.fromScale(0.14, 0.05))
	local key = Ui.label(b.face, tostring(table.find(H.slots, s) or ""), UDim2.fromScale(0.26, 0.26), UDim2.fromScale(0.04, 0.03))
	key.Name = "Key"
	-- the cooldown: a dark sheet that drains from the top. It always covers the whole face with the face's own
	-- corners, and a hard-edged gradient shows only the bottom part: a shrinking box got rounded corners of its
	-- own at the cut and didn't follow the tile's shape (owner 2026-11-23)
	local cool = Instance.new("Frame")
	cool.Name = "Cooldown"
	cool.BackgroundColor3 = Theme.ink
	cool.BackgroundTransparency = 0.45
	cool.BorderSizePixel = 0
	cool.Size = UDim2.fromScale(1, 1)
	cool.ZIndex = 5
	cool.Visible = false
	Ui.corner(cool)
	local fill = Instance.new("UIGradient")
	fill.Rotation = 90 -- top to bottom
	fill.Parent = cool
	cool.Parent = b.face
	slots[s.id] = { block = b, key = key, cool = cool, coolFill = fill }
end

local function step()
	-- owner 2026-11-16 (QA IR-06): the SAFE countdown is hidden; it was one timer too many on a new player's
	-- HUD. The shield still works, and "Your shield is off" still shows when it ends.
	shieldPill.Visible = false
	local bomb = slots.bomb
	if bomb then
		local c = math.clamp((coolUntil - os.clock()) / Config.bombs.cooldown, 0, 1)
		bomb.cool.Visible = c > 0
		if c > 0 then
			-- clear above the edge, dark below it (the frame's own transparency sets how dark)
			local edge = math.clamp(1 - c, 0.001, 0.998)
			bomb.coolFill.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(edge, 1),
				NumberSequenceKeypoint.new(edge + 0.001, 0), NumberSequenceKeypoint.new(1, 0),
			})
		end
	end
end

-- Frost Bomb: placed at your feet (the server finds the ground and checks the cooldown and the max)
local function placeBomb()
	if os.clock() < coolUntil then
		return
	end
	coolUntil = os.clock() + Config.bombs.cooldown
	State.send("PlaceBomb")
end

-- a placed Frost Bomb is tossed from its owner's hand onto its spot (owner 2026-11-23: "they just appear, it looks
-- cheap"). Client-only look over the server's spot (Animation Rules: client-only looks over server truth): it
-- leaves the hand at the hand's size, flies on an arc with a spin that unwinds as it lands, lands with a squash and
-- a little hop that settles (the damped spring), and only then does the ring spread out and the glow come on, with
-- a puff of snow. Every client sees it, from that player's hand. Timings: Config.bombs.place.
local function backOut(x: number): number
	return 1 + 2.70158 * (x - 1) ^ 3 + 1.70158 * (x - 1) ^ 2
end
local function settle(x: number): number
	return math.exp(-4 * x) * math.cos(math.pi * 1.5 * x)
end
local function tossBomb(core: BasePart)
	local P = Config.bombs.place
	local cam = workspace.CurrentCamera
	if not core:IsA("BasePart") or (cam and (cam.CFrame.Position - core.Position).Magnitude > P.farDistance) then
		return -- far away: it's simply there
	end
	local reduced = SettingsController.get("reducedMotion") == true
	local ts = if reduced then 0.5 else 1
	local final = core.CFrame
	local ring = core:FindFirstChild("Ring") :: BasePart?
	local light = core:FindFirstChildOfClass("PointLight")
	-- every part's place and size relative to the orb (the ring stays on the ground and grows by itself)
	local parts: { { p: BasePart, off: CFrame, size: Vector3 } } = { { p = core, off = CFrame.identity, size = core.Size } }
	for _, d in core:GetDescendants() do
		if d:IsA("BasePart") and d ~= ring then
			table.insert(parts, { p = d, off = final:ToObjectSpace(d.CFrame), size = d.Size })
		end
	end
	local ringSize = if ring then ring.Size else Vector3.zero
	local ringTr = if ring then ring.Transparency else 0
	local lightOn = if light then light.Brightness else 0
	-- where it leaves from: the bomb in its owner's hand, else the hand, else a little above the spot
	local owner = Players:GetPlayerByUserId(core:GetAttribute("OwnerUserId") :: number? or 0)
	local char = owner and owner.Character
	local held = char and char:FindFirstChild("FrostBombHeld")
	local heldCore = held and held:IsA("Model") and held.PrimaryPart
	local hand = char and char:FindFirstChild("RightHand")
	local from = if heldCore then heldCore.Position
		elseif hand and hand:IsA("BasePart") then hand.Position
		else final.Position + Vector3.new(0, 3, 0)
	if (from - final.Position).Magnitude > 12 then
		from = final.Position + Vector3.new(0, 3, 0) -- a stale hand far away: drop it in from just above instead
	end
	if char then
		RayController.bombTossed(char)
	end
	local startScale = Config.bombs.held.size / Config.bombs.size
	local axis = (final.Position - from) * Vector3.new(1, 0, 1)
	axis = if axis.Magnitude > 0.01 then axis.Unit:Cross(Vector3.yAxis) else Vector3.xAxis
	local r = core.Size.Y / 2
	local function draw(pos: Vector3, rot: CFrame, s: number)
		local root = CFrame.new(pos) * rot * final.Rotation
		for _, e in parts do
			e.p.Size = e.size * s
			e.p.CFrame = root * (e.off - e.off.Position + e.off.Position * s)
		end
	end
	local function setRing(x: number)
		if ring then
			local g = P.ringFrom + (1 - P.ringFrom) * backOut(x)
			ring.Size = Vector3.new(ringSize.X, ringSize.Y * g, ringSize.Z * g)
			ring.Transparency = ringTr + (1 - ringTr) * (1 - math.clamp(x * 2, 0, 1))
		end
		if light then
			light.Brightness = lightOn * math.clamp(x, 0, 1)
		end
	end
	setRing(0)
	if ring then
		ring.Transparency = 1
	end
	draw(from, CFrame.identity, startScale)
	local toss, land, ringT = P.toss * ts, P.land * ts, P.ring * ts
	local t0 = os.clock()
	local landed = false
	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(function()
		if not core.Parent then
			conn:Disconnect()
			return
		end
		local t = os.clock() - t0
		if t < toss then
			local u = t / toss
			local pos = from:Lerp(final.Position, u) + Vector3.new(0, P.arc * 4 * u * (1 - u), 0)
			local spin = if reduced then CFrame.identity else CFrame.fromAxisAngle(axis, P.spin * (1 - u))
			draw(pos, spin, startScale + (1 - startScale) * u)
			return
		end
		if not landed then
			landed = true
			if ring then
				EffectsController.burst(ring.Position, Theme.ice, P.puff)
			end
		end
		local x = math.clamp((t - toss) / land, 0, 1)
		-- a little hop off the snow, then a squash-pulse that overshoots once and rests
		local hop = if x < 0.45 then P.hop * math.sin(math.pi * x / 0.45) else 0
		local s = 1 + P.squash * settle(x) * (if reduced then 0.35 else 1)
		draw(final.Position + Vector3.new(0, hop + r * (s - 1), 0), CFrame.identity, s)
		setRing(math.clamp((t - toss) / ringT, 0, 1))
		if x >= 1 and t - toss >= ringT then
			draw(final.Position, CFrame.identity, 1)
			setRing(1)
			if ring then
				ring.Size, ring.Transparency = ringSize, ringTr
			end
			conn:Disconnect()
		end
	end)
end

-- frozen by a bomb: the TAP card and its countdown
local breakGui: ScreenGui
local breakCard: TextLabel
local breakLeft: TextLabel
local function frozenStep()
	local on = me:GetAttribute("CanBreak") == true
	breakGui.Enabled = on
	if on then
		local u = me:GetAttribute("FrozenUntil")
		local left = if typeof(u) == "number" then math.max(0, u - workspace:GetServerTimeNow()) else 0
		breakLeft.Text = string.format("%.1f s", left)
	end
end
local function crack()
	if me:GetAttribute("CanBreak") ~= true then
		return false
	end
	State.send("BreakIce")
	SoundController.play("ice_tap")
	-- a little shake of the card: you can see every tap land
	breakCard.Rotation = (math.random() < 0.5 and -1 or 1) * 6
	TweenService:Create(breakCard, TweenInfo.new(0.12), { Rotation = 0 }):Play()
	return true
end

-- Slow Gel: throw at the spot under the pointer (the server clamps it to the throw's reach)
local function throwAt(screen: Vector2)
	local cam = workspace.CurrentCamera
	if not cam or os.clock() < coolUntil then
		return
	end
	local ray = cam:ViewportPointToRay(screen.X, screen.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { me.Character :: Instance }
	local hit = workspace:Raycast(ray.Origin, ray.Direction * 300, params)
	local at = if hit then hit.Position else ray.Origin + ray.Direction * 40
	coolUntil = os.clock() + Config.gel.cooldown
	State.send("ThrowGel", at)
	-- a gel blob is shot out of the ray gun's barrel to the spot (owner 2026-11-03; the puddle is the
	-- server's). The gun stays in the hand while the gel is held (RayController); the hand is the fallback.
	local c = me.Character
	local gun = c and c:FindFirstChild("IceRay")
	local tip = gun and gun:FindFirstChild("RayTip", true)
	local hand = c and c:FindFirstChild("RightHand")
	local from = if tip and tip:IsA("Attachment") then CFrame.new(tip.WorldPosition) elseif hand and hand:IsA("BasePart") then hand.CFrame else nil
	if from then
		local blob = Instance.new("Part")
		blob.Shape = Enum.PartType.Ball
		blob.Size = Vector3.one * 1.2
		blob.Color = Theme.round5.gel
		blob.Material = Enum.Material.Glass
		blob.Anchored, blob.CanCollide, blob.CanQuery, blob.CanTouch = true, false, false, false
		blob.CFrame = from
		blob.Parent = workspace
		TweenService:Create(blob, TweenInfo.new(Config.gel.flySeconds, Enum.EasingStyle.Quad), { CFrame = CFrame.new(at) }):Play()
		task.delay(Config.gel.flySeconds, function()
			blob:Destroy()
		end)
	end
end

function GearController.Init() end

function GearController.Start()
	bar = Instance.new("Frame")
	bar.Name = "Hotbar"
	bar.BackgroundTransparency = 1
	bar:SetAttribute("Slots", 1)
	for _, s in H.slots do
		makeSlot(s)
	end
	-- the shield pill above the slots (ray-tag: you're safe for your first minutes in the game)
	local pill = Ui.block(bar, "Shield", Theme.round5.shield, "", nil)
	pill.root.AnchorPoint = Vector2.new(0.5, 0)
	pill.root.Position = UDim2.fromScale(0.5, 0)
	pill.root.Size = UDim2.fromScale(0.9, 0.24)
	Ui.roundBlock(pill, 0.5)
	shieldPill = pill.root
	shieldText = pill.text
	shieldPill.Visible = false
	Screen.register("hotbar", bar)
	refresh()
	-- the TAP card (frozen by a Frost Bomb)
	breakGui = Instance.new("ScreenGui")
	breakGui.Name = "BreakFree"
	breakGui.ResetOnSpawn = false
	breakGui.DisplayOrder = 20
	breakGui.Enabled = false
	breakCard = Ui.label(breakGui, "TAP TAP TAP!", UDim2.fromScale(0.5, 0.12), UDim2.fromScale(0.25, 0.3))
	breakCard.Name = "Tap"
	breakCard.TextColor3 = Theme.white
	breakLeft = Ui.label(breakGui, "", UDim2.fromScale(0.3, 0.07), UDim2.fromScale(0.35, 0.43))
	breakLeft.Name = "Left"
	breakLeft.TextColor3 = Theme.white
	-- a dark rounded plate behind the words: bare white text was lost on snow and under world prompts
	-- (phone check 2026-11-19, 784x361)
	local plate = Instance.new("Frame")
	plate.Name = "Plate"
	plate.BackgroundColor3 = Theme.ink
	plate.BackgroundTransparency = 0.25
	plate.BorderSizePixel = 0
	plate.Position = UDim2.fromScale(0.23, 0.28)
	plate.Size = UDim2.fromScale(0.54, 0.24)
	Ui.corner(plate)
	plate.Parent = breakGui
	breakCard.ZIndex, breakLeft.ZIndex = 2, 2
	breakGui.Parent = me:WaitForChild("PlayerGui")
	RunService.RenderStepped:Connect(frozenStep)
	for _, attr in { "Held", "GearGel", "GearBomb" } do
		me:GetAttributeChangedSignal(attr):Connect(refresh)
	end
	me:GetAttributeChangedSignal("GunLocked"):Connect(function()
		if me:GetAttribute("GunLocked") == true then
			lockedAt = os.clock()
			task.delay(Config.show.freeze.flySeconds + 0.02, refresh)
		end
		refresh()
	end)
	InputController.DeviceChanged:Connect(refresh)
	RunService.RenderStepped:Connect(step)
	-- keys: 1 / 2 pick a slot; gamepad L1 / R1 step through them
	ContextActionService:BindActionAtPriority("IceRay_hotbar", function(_, st: Enum.UserInputState, input: InputObject)
		if st ~= Enum.UserInputState.Begin or UserInputService:GetFocusedTextBox() then
			return Enum.ContextActionResult.Pass
		end
		if me:GetAttribute("GunLocked") == true then
			return Enum.ContextActionResult.Sink -- hands full: 1 / 2 / L1 / R1 do nothing
		end
		local list = owned()
		if input.KeyCode == H.gamepadPrev or input.KeyCode == H.gamepadNext then
			local i = table.find(list, held()) or 0
			local dir = if input.KeyCode == H.gamepadNext then 1 else -1
			local nextId = list[(i - 1 + dir) % #list + 1]
			if nextId then
				choose(nextId)
			end
		else
			for _, s in H.slots do
				if s.key == input.KeyCode then
					choose(s.id)
				end
			end
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.ContextActionPriority.High.Value, H.gamepadPrev, H.gamepadNext, table.unpack((function()
		local keys = {}
		for _, s in H.slots do
			table.insert(keys, s.key)
		end
		return keys
	end)()))
	-- frozen by a bomb: any tap, click or key cracks the ice (before anything else reads it)
	UserInputService.InputBegan:Connect(function(input: InputObject)
		local t = input.UserInputType
		if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch or t == Enum.UserInputType.Keyboard
			or t == Enum.UserInputType.Gamepad1 then
			crack()
		end
	end)
	-- placing a Frost Bomb: click / tap / R2 while it's held
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed or me:GetAttribute("CanBreak") == true then
			return
		end
		if held() == "bomb" then
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.KeyCode == Enum.KeyCode.ButtonR2 then
				placeBomb()
			end
			return
		end
		if held() ~= "gel" then
			return
		end
		-- a finger throws on a tap (TouchTap below), not when it lands: every camera drag threw a puddle
		-- and started the cooldown (mobile QA 2026-11-10)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			throwAt(Vector2.new(input.Position.X, input.Position.Y))
		elseif input.KeyCode == Enum.KeyCode.ButtonR2 then
			local cam = workspace.CurrentCamera
			if cam then
				throwAt(cam.ViewportSize / 2)
			end
		end
	end)
	UserInputService.TouchTap:Connect(function(positions: { Vector2 }, processed: boolean)
		if processed or not positions[1] or me:GetAttribute("CanBreak") == true then
			return
		end
		if held() == "bomb" then
			placeBomb()
		elseif held() == "gel" then
			throwAt(positions[1])
		end
	end)
	-- every bomb placed from now on is tossed in (the ones already out when you join are just there)
	task.spawn(function()
		local folder = workspace:WaitForChild("FrostBombs", 30)
		if folder then
			folder.ChildAdded:Connect(function(child: Instance)
				if child:IsA("BasePart") then
					tossBomb(child)
				end
			end)
		end
	end)
	State.Notify:Connect(function(kind: string, data: any)
		if kind == "gearBought" then
			refresh()
		elseif kind == "bombPop" and typeof(data) == "table" and typeof(data.at) == "Vector3" then
			EffectsController.burst(data.at, Theme.ice) -- a puff of snow, never a boom
		end
	end)
end

return GearController
