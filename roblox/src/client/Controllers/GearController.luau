--!strict
-- GearController (Round 5): the hotbar at the bottom middle. One slot per thing you own (the Ice Ray,
-- Slow Gel once bought): tap / click a slot, press 1-2, or gamepad L1 / R1 to hold it; tap the held
-- one again to put it away. The server decides what you hold (GearService, the "Held" attribute).
-- While Slow Gel is held, a click / tap on the ground throws a puddle (the server checks reach and the
-- cooldown; the slot drains while it cools down). Above the slots: your shield pill while you're safe
-- from ray-tag (TagService, the "ShieldUntil" attribute).

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

local GearController = {}
local H = Config.hotbar
local me = Players.LocalPlayer
local bar: Frame
local slots: { [string]: { block: Ui.Block, key: TextLabel, cool: Frame } } = {}
local shieldPill: Frame
local shieldText: TextLabel
local coolUntil = 0

local ICONS = { ray = Config.images.icons.ray, gel = Config.images.icons.motion } :: { [string]: string } -- gel: the snail (slow) until its own painted icon

local function held(): string
	local h = me:GetAttribute("Held")
	return if typeof(h) == "string" then h else "ray"
end

local function owned(): { string }
	local list = {}
	for _, s in H.slots do
		if s.id == "ray" or (s.id == "gel" and me:GetAttribute("GearGel") == true) then
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

local function refresh()
	local list = owned()
	bar:SetAttribute("Slots", #list)
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
	-- the gel's cooldown: a dark sheet that drains from the top
	local cool = Instance.new("Frame")
	cool.Name = "Cooldown"
	cool.BackgroundColor3 = Theme.ink
	cool.BackgroundTransparency = 0.45
	cool.BorderSizePixel = 0
	cool.AnchorPoint = Vector2.new(0, 1)
	cool.Position = UDim2.fromScale(0, 1)
	cool.Size = UDim2.fromScale(1, 0)
	cool.ZIndex = 5
	Ui.corner(cool)
	cool.Parent = b.face
	slots[s.id] = { block = b, key = key, cool = cool }
end

local function shieldLeft(): number
	local u = me:GetAttribute("ShieldUntil")
	return if typeof(u) == "number" then u - workspace:GetServerTimeNow() else 0
end

local function step()
	local left = shieldLeft()
	shieldPill.Visible = left > 0
	if left > 0 then
		local m = math.floor(left / 60)
		shieldText.Text = string.format("SAFE %d:%02d", m, math.floor(left % 60))
	end
	local gel = slots.gel
	if gel then
		local c = math.clamp((coolUntil - os.clock()) / Config.gel.cooldown, 0, 1)
		gel.cool.Size = UDim2.fromScale(1, c)
	end
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
	for _, part in { pill.root, pill.face } do
		(part:FindFirstChildOfClass("UICorner") :: UICorner).CornerRadius = UDim.new(0.5, 0)
	end
	shieldPill = pill.root
	shieldText = pill.text
	shieldPill.Visible = false
	Screen.register("hotbar", bar)
	refresh()
	for _, attr in { "Held", "GearGel" } do
		me:GetAttributeChangedSignal(attr):Connect(refresh)
	end
	InputController.DeviceChanged:Connect(refresh)
	RunService.RenderStepped:Connect(step)
	-- keys: 1 / 2 pick a slot; gamepad L1 / R1 step through them
	ContextActionService:BindActionAtPriority("IceRay_hotbar", function(_, st: Enum.UserInputState, input: InputObject)
		if st ~= Enum.UserInputState.Begin or UserInputService:GetFocusedTextBox() then
			return Enum.ContextActionResult.Pass
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
	-- throwing gel: click / tap while it's held
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed or held() ~= "gel" then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			throwAt(Vector2.new(input.Position.X, input.Position.Y))
		elseif input.KeyCode == Enum.KeyCode.ButtonR2 then
			local cam = workspace.CurrentCamera
			if cam then
				throwAt(cam.ViewportSize / 2)
			end
		end
	end)
	State.Notify:Connect(function(kind: string)
		if kind == "gearBought" then
			refresh()
		end
	end)
end

return GearController
