--!strict
-- SoundController: the only thing that plays sounds and music. Ids live in Config.sounds (0 = silent
-- until the owner uploads or picks one). At most Config.sounds.maxSame copies of a sound at once.
-- Music follows the zone you stand in.

local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local WorldRules = require(ReplicatedStorage.Shared.WorldRules)
local State = require(script.Parent.State)

local SoundController = {}
local S = Config.sounds
local sfxOn, musicOn = true, true
local playing: { [string]: number } = {}
local music: Sound? = nil
local musicName = ""

function SoundController.play(name: string)
	local id = S.ids[name]
	if not sfxOn or not id or id == 0 or (playing[name] or 0) >= S.maxSame then
		return
	end
	local s = Instance.new("Sound")
	s.SoundId = "rbxassetid://" .. id
	s.Volume = S.sfx
	s.Parent = SoundService
	playing[name] = (playing[name] or 0) + 1
	s.Ended:Once(function()
		playing[name] -= 1
		s:Destroy()
	end)
	s:Play()
end

local function setMusic(name: string)
	if name == musicName then
		return
	end
	musicName = name
	if music then
		music:Destroy()
		music = nil
	end
	local id = S.ids[name]
	if not musicOn or not id or id == 0 then
		return
	end
	local s = Instance.new("Sound")
	s.SoundId = "rbxassetid://" .. id
	s.Looped = true
	s.Volume = S.music
	s.Parent = SoundService
	s:Play()
	music = s
end

-- SettingsController calls this
function SoundController.setEnabled(musicEnabled: boolean, soundEnabled: boolean)
	sfxOn = soundEnabled
	if musicEnabled ~= musicOn then
		musicOn = musicEnabled
		local name = musicName
		musicName = ""
		setMusic(name)
	end
end

local NOTIFY_SOUNDS: { [string]: string } = {
	frozen = "freeze", banked = "bank", melted = "melt", notYet = "no", upgraded = "buy",
	giftClaimed = "gift", welcomeCollected = "coin", zoneUnlocked = "unlock", bridge = "bridge",
	chillStart = "chill", bigWin = "reveal_rare", pageDone = "reveal_rare",
}

function SoundController.Init() end

function SoundController.Start()
	State.Notify:Connect(function(kind: string)
		local name = NOTIFY_SOUNDS[kind]
		if name then
			SoundController.play(name)
		end
	end)
	task.spawn(function()
		while true do
			local c = Players.LocalPlayer.Character
			local root = c and c:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root then
				setMusic(if WorldRules.zoneAt(root.Position) == 2 then "music_forest" else "music_meadow")
			end
			task.wait(1)
		end
	end)
end

return SoundController
