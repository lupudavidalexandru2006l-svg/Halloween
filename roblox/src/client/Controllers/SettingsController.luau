--!strict
-- SettingsController: music, sound, reduced motion, low graphics and C or F. The server saves them
-- (SetSetting); this keeps the local copy, applies them at once and tells the others.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local State = require(script.Parent.State)
local SoundController = require(script.Parent.SoundController)

local SettingsController = {}
local current: { [string]: any } = table.clone(Config.settingsDefault)
local changed = Instance.new("BindableEvent")
SettingsController.Changed = changed.Event
local gotServer = false

local function apply()
	SoundController.setEnabled(current.music == true, current.sound == true)
	Lighting.GlobalShadows = not current.lowGraphics -- local only: other players keep their own setting
	changed:Fire(current)
end

function SettingsController.get(key: string): any
	return current[key]
end

function SettingsController.set(key: string, value: any)
	if (Config.settingsDefault :: any)[key] == nil then
		return
	end
	current[key] = value
	State.send("SetSetting", key, value)
	apply()
end

function SettingsController.Init() end

function SettingsController.Start()
	State.Changed:Connect(function(v: State.View)
		if not gotServer and v.settings then
			gotServer = true -- the save's settings win once; after that the local copy leads
			for k, val in v.settings :: any do
				current[k] = val
			end
			apply()
		end
	end)
	apply()
end

return SettingsController
