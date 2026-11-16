--!strict
-- InputController: the one owner of input. Movement is Roblox's own (WASD, thumbstick, gamepad stick);
-- shooting the ray is RayController's (hold mouse / finger on a target, or E / R2), the hotbar is
-- GearController's (1-2, L1 / R1), world prompts open booths and gates (E, a tap, gamepad X). This adds the menu
-- actions on every input: keyboard shortcuts, gamepad B closes, Y presses Super Freeze, Select picks
-- the menu tiles (GuiService.SelectedObject). Other controllers listen to Action.

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)

local InputController = {}
local action = Instance.new("BindableEvent")
InputController.Action = action.Event -- (name): "pets" | "shop" | "index" | "close" | "superFreeze" | "menu"

export type Device = "touch" | "gamepad" | "keyboard"
local device: Device = "keyboard"
local deviceChanged = Instance.new("BindableEvent")
InputController.DeviceChanged = deviceChanged.Event -- (device)

function InputController.device(): Device
	return device
end

local function setDevice(d: Device)
	if d ~= device then
		device = d
		deviceChanged:Fire(d)
	end
end

local forced = false -- Studio-only device QA: DevDevice pins the device (the phone emulator still reports a keyboard)

-- a touch screen that is only touch, or phone-sized (Config.ui.phoneShortPx): a phone. Owner 2026-11-15 (2-player
-- test log): each thumbstick touch switched to the touch layout (coins lifted over the stick, tiles smaller) and
-- the next stray keyboard/mouse event (the emulator and some phones report a keyboard) switched it back, so the
-- HUD jumped up and down while walking. On a phone the device stays "touch"; only a gamepad changes it.
local function phone(): boolean
	if not UserInputService.TouchEnabled then
		return false
	end
	if not UserInputService.KeyboardEnabled and not UserInputService.MouseEnabled then
		return true
	end
	local cam = workspace.CurrentCamera
	local v = if cam then cam.ViewportSize else Vector2.zero
	return v.X > 1 and math.min(v.X, v.Y) < Config.ui.phoneShortPx
end

local function fromInputType(t: Enum.UserInputType)
	if forced then
		return
	end
	if t == Enum.UserInputType.Touch then
		setDevice("touch")
	elseif t.Name:find("Gamepad") then
		setDevice("gamepad")
	elseif device == "touch" and phone() then
		return -- see phone(): stray keyboard / mouse input never leaves the touch layout on a phone
	elseif t == Enum.UserInputType.Keyboard or t.Name:find("Mouse") then
		setDevice("keyboard")
	end
end

-- the prompt key hint: "E" on PC, "X" on a controller, "Hold" on touch
function InputController.keyHint(prompt: ProximityPrompt): string
	if device == "touch" then
		return if prompt.HoldDuration > 0 then "Hold" else "Tap"
	elseif device == "gamepad" then
		return prompt.GamepadKeyCode.Name:gsub("Button", "")
	end
	return prompt.KeyboardKeyCode.Name
end

function InputController.Init()
	if phone() or (UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled) then
		device = "touch" -- a phone starts in the touch layout, so it never jumps on the first thumbstick touch
	elseif UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled then
		device = "gamepad"
	end
end

function InputController.Start()
	UserInputService.LastInputTypeChanged:Connect(fromInputType)
	-- the screen became phone-sized (a phone rotating, the Studio emulator switching device): touch layout now
	local function checkPhone()
		if not forced and device == "keyboard" and phone() then
			setDevice("touch")
		end
	end
	local function watchCam()
		local cam = workspace.CurrentCamera
		if cam then
			cam:GetPropertyChangedSignal("ViewportSize"):Connect(checkPhone)
		end
		checkPhone()
	end
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watchCam)
	watchCam()
	-- Studio-only test hook (device QA 2026-11-13): the player attribute DevDevice = "touch" | "gamepad" |
	-- "keyboard" pins the device, "" lets input decide again. Off in live servers.
	if game:GetService("RunService"):IsStudio() then
		local lp = game:GetService("Players").LocalPlayer
		lp:GetAttributeChangedSignal("DevDevice"):Connect(function()
			local v = lp:GetAttribute("DevDevice")
			forced = v == "touch" or v == "gamepad" or v == "keyboard"
			if forced then
				setDevice(v :: Device)
			end
		end)
	end
	local K, G = Config.ui.keys, Config.ui.gamepadKeys
	local binds: { [string]: { Enum.KeyCode } } = {
		pets = { K.pets },
		shop = { K.shop },
		index = { K.index },
		tester = { K.tester }, -- PopupController ignores it for anyone who isn't a tester
		close = { K.close, G.close },
		superFreeze = { K.superFreeze, G.superFreeze },
		menu = { G.menu },
	}
	for name, keys in binds do
		-- above Roblox's camera keys: I and O zoom the camera by default, so I would never reach the Index
		ContextActionService:BindActionAtPriority("IceRay_" .. name, function(_, state: Enum.UserInputState)
			if state == Enum.UserInputState.Begin then
				if UserInputService:GetFocusedTextBox() then
					return Enum.ContextActionResult.Pass
				end
				action:Fire(name)
				-- B only closes when something is open, otherwise Roblox keeps it
				return if name == "close" and GuiService.SelectedObject == nil then Enum.ContextActionResult.Pass else Enum.ContextActionResult.Sink
			end
			return Enum.ContextActionResult.Pass
		end, false, Enum.ContextActionPriority.High.Value, table.unpack(keys))
	end
end

-- gamepad menus: put the selection on a button (nil clears it)
function InputController.select(obj: GuiObject?)
	if device == "gamepad" or obj == nil then
		GuiService.SelectedObject = obj
	end
end

return InputController
