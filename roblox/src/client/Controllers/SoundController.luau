--!strict
-- SoundController: the only thing that plays sounds and music. Ids live in Config.sounds (0 = silent).
-- At most Config.sounds.maxSame copies of a sound at once; long library sounds are cut (trim) and
-- leveled (volume); coin-like sounds climb a semitone on a quick streak and the rest vary a little
-- in pitch (Sound Rules 3). Music follows the zone you stand in and crossfades (Sound Rules 5).

local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")
local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local WorldRules = require(ReplicatedStorage.Shared.WorldRules)
local State = require(script.Parent.State)

local SoundController = {}
local S = Config.sounds
local sfxOn, musicOn = true, true
local playing: { [string]: number } = {}
local streaks: { [string]: { at: number, n: number } } = {}
local music: Sound? = nil
local musicName = ""
local CROSSFADE = 1.5

-- volume ramps on task.wait, not TweenService: tweens only step while the client renders, and music
-- must never get stuck silent (seen in Studio with the play window in the background)
local rampId = 0
local function ramp(s: Sound, to: number, seconds: number, thenDestroy: boolean)
	rampId += 1
	local id = rampId
	s:SetAttribute("Ramp", id) -- a newer ramp on the same sound takes over
	task.spawn(function()
		local from, t0 = s.Volume, os.clock()
		while s.Parent and s:GetAttribute("Ramp") == id do
			local k = math.min(1, (os.clock() - t0) / math.max(seconds, 1e-3))
			s.Volume = from + (to - from) * k
			if k >= 1 then
				break
			end
			task.wait(0.05)
		end
		if thenDestroy then
			s:Destroy()
		end
	end)
end

local function fadeOut(s: Sound, seconds: number)
	ramp(s, 0, seconds, true)
end

function SoundController.play(name: string, speed: number?)
	local id = S.ids[name]
	if not sfxOn or not id or id == 0 or (playing[name] or 0) >= S.maxSame then
		return
	end
	local pitch = speed
	if not pitch then
		if S.streak[name] then
			local now = os.clock()
			local st = streaks[name]
			local n = if st and now - st.at < S.streakReset then math.min(S.streakMax, st.n + 1) else 0
			streaks[name] = { at = now, n = n }
			pitch = 2 ^ (n / 12)
		else
			pitch = 1 + (math.random() * 2 - 1) * S.pitchJitter
		end
	end
	local s = Instance.new("Sound")
	s.SoundId = "rbxassetid://" .. id
	s.Volume = S.sfx * (S.volume[name] or 1)
	s.PlaybackSpeed = pitch or 1
	s.Parent = SoundService
	playing[name] = (playing[name] or 0) + 1
	local done = false
	local function finish()
		if done then
			return
		end
		done = true
		playing[name] -= 1
	end
	s.Ended:Once(function()
		finish()
		s:Destroy()
	end)
	s:Play()
	local trim = S.trim[name]
	if trim then
		task.delay(trim / (pitch or 1), function()
			if not done and s.Parent then
				finish()
				fadeOut(s, S.fadeSeconds)
			end
		end)
	end
end

-- a looped sound the caller tunes (PlaybackSpeed) and stops with :Destroy(); nil when it's silent or sound is off
function SoundController.loop(name: string): Sound?
	local id = S.ids[name]
	if not sfxOn or not id or id == 0 then
		return nil
	end
	local s = Instance.new("Sound")
	s.SoundId = "rbxassetid://" .. id
	s.Volume = S.sfx * (S.volume[name] or 1)
	s.Looped = true
	s.Parent = SoundService
	s:Play()
	return s
end

local function setMusic(name: string)
	if name == musicName then
		return
	end
	musicName = name
	if music then
		fadeOut(music, CROSSFADE)
		music = nil
	end
	local id = S.ids[name]
	if not musicOn or not id or id == 0 then
		return
	end
	local s = Instance.new("Sound")
	s.SoundId = "rbxassetid://" .. id
	s.Looped = true
	s.Volume = 0
	s.Parent = SoundService
	s:Play()
	ramp(s, S.music, CROSSFADE, false)
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
	chillStart = "chill", bigWin = "reveal_rare", pageDone = "reveal_rare", gunBought = "buy", gunEquipped = "click",
	friendJoined = "friend", challengeDone = "challenge", challengeClaimed = "coin",
}

function SoundController.Init() end

function SoundController.Start()
	State.Notify:Connect(function(kind: string)
		local name = NOTIFY_SOUNDS[kind]
		if name then
			SoundController.play(name)
		end
	end)
	-- the first minute's sounds load before they're needed, so the first catch isn't silent (Sound Rules 9)
	task.spawn(function()
		local list = {}
		for _, name in { "click", "ray_charge", "ray_clack", "ray_fire", "ray_hum", "tink", "freeze", "bank", "coin", "music_meadow" } do
			local id = S.ids[name]
			if id and id ~= 0 then
				local s = Instance.new("Sound")
				s.SoundId = "rbxassetid://" .. id
				table.insert(list, s)
			end
		end
		pcall(function()
			ContentProvider:PreloadAsync(list)
		end)
		for _, s in list do
			s:Destroy()
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
