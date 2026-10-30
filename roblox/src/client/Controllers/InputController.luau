--!strict
-- InputController: the one owner of input. Movement is Roblox's own (WASD, thumbstick, gamepad stick);
-- freezing is the world's ProximityPrompts (E, a tap on the prompt, gamepad X / A). This adds the menu
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

local function fromInputType(t: Enum.UserInputType)
	if t == Enum.UserInputType.Touch then
		setDevice("touch")
	elseif t.Name:find("Gamepad") then
		setDevice("gamepad")
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
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		device = "touch"
	elseif UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled then
		device = "gamepad"
	end
end

function InputController.Start()
	UserInputService.LastInputTypeChanged:Connect(fromInputType)
	local K, G = Config.ui.keys, Config.ui.gamepadKeys
	local binds: { [string]: { Enum.KeyCode } } = {
		pets = { K.pets },
		shop = { K.shop },
		index = { K.index },
		close = { K.close, G.close },
		superFreeze = { K.superFreeze, G.superFreeze },
		menu = { G.menu },
	}
	for name, keys in binds do
		ContextActionService:BindAction("IceRay_" .. name, function(_, state: Enum.UserInputState)
			if state == Enum.UserInputState.Begin then
				if UserInputService:GetFocusedTextBox() then
					return Enum.ContextActionResult.Pass
				end
				action:Fire(name)
				-- B only closes when something is open, otherwise Roblox keeps it
				return if name == "close" and GuiService.SelectedObject == nil then Enum.ContextActionResult.Pass else Enum.ContextActionResult.Sink
			end
			return Enum.ContextActionResult.Pass
		end, false, table.unpack(keys))
	end
end

-- gamepad menus: put the selection on a button (nil clears it)
function InputController.select(obj: GuiObject?)
	if device == "gamepad" or obj == nil then
		GuiService.SelectedObject = obj
	end
end

return InputController
