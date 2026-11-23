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
-- the run home (PvP Plan 2026-11-18: thrilling = fast and playful, never tense): PetVisuals reports how many
-- cubes you carry and the lowest ice left each frame
local carryCount, carryLife = 0, 1
local zoneMusic = "music_meadow"

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
	if not sfxOn or not id or id == 0 or (playing[name] or 0) >= (S.maxSameFor[name] or S.maxSame) then
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

-- another player close while you carry (PvP Plan: "you can hear that it's getting close")
local nearOther = false

local function wantedMusic(): string
	if carryCount > 0 then
		return if carryLife < S.carryHotBelow or nearOther then "carry_chase_hot" else "carry_chase_calm"
	end
	return zoneMusic
end

-- PetVisuals calls this every frame
function SoundController.setCarry(count: number, lowestLife: number)
	carryCount, carryLife = count, lowestLife
	local want = wantedMusic()
	if want ~= musicName then
		setMusic(want)
	end
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
	frozen = "freeze", melted = "melt", pickedUp = "snag",
	-- PvP (2026-11-19): ElevenLabs batch 1
	-- thawed: handled in Start (a PvP break-free only; a Thaw Machine's thaw plays thaw_done in ThawMachines)
	tagged = "player_frozen", bombFrozen = "player_frozen", tagHit = "ice_tap", bombHit = "ice_tap",
	-- banked: EffectsController's tally plays "bank" at its finale
	bombPlaced = "bomb_arm", gotBack = "got_back", notYet = "no", upgraded = "buy",
	giftClaimed = "gift", welcomeCollected = "coin", zoneUnlocked = "unlock", bridge = "bridge",
	chillStart = "chill", bigWin = "reveal_rare", pageDone = "reveal_rare", gunBought = "buy", gunEquipped = "click",
	friendJoined = "friend", challengeDone = "challenge", challengeClaimed = "coin",
}

function SoundController.Init() end

function SoundController.Start()
	State.Notify:Connect(function(kind: string, data: any)
		if kind == "frozen" and typeof(data) == "table" and data.show == nil then
			return -- a plain snap: EffectsController plays the freeze after its hit-stop (Sound Rules 11)
		end
		if kind == "bombPop" then
			-- every client hears a bomb pop, but only near it
			local c = Players.LocalPlayer.Character
			local root = c and c:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root and typeof(data) == "table" and typeof(data.at) == "Vector3" and (root.Position - data.at).Magnitude < S.popHearStuds then
				SoundController.play("bomb_pop")
			end
			return
		end
		if kind == "thawed" then
			-- QA 2026-11-23: this mapped to "ice_free", renamed thaw_done in Config, so breaking out of PvP ice was silent.
			-- TagService sends {} on a break-free; PenService's machine thaw carries a key and plays its own sound.
			if typeof(data) == "table" and data.key == nil then
				SoundController.play("thaw_done")
			end
			return
		end
		local name = NOTIFY_SOUNDS[kind]
		if name then
			SoundController.play(name)
		end
	end)
	-- is another player within nearStuds while you carry? (twice a second is plenty)
	task.spawn(function()
		while true do
			local near = false
			local c = Players.LocalPlayer.Character
			local root = c and c:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root and carryCount > 0 then
				for _, p in Players:GetPlayers() do
					local r = p ~= Players.LocalPlayer and p.Character and p.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
					if r and (r.Position - root.Position).Magnitude < S.nearStuds then
						near = true
						break
					end
				end
			end
			if near ~= nearOther then
				nearOther = near
				SoundController.setCarry(carryCount, carryLife)
			end
			task.wait(0.5)
		end
	end)
	-- the first minute's sounds load before they're needed, so the first catch isn't silent (Sound Rules 9)
	task.spawn(function()
		local list = {}
		for _, name in { "click", "ray_charge", "ray_clack", "ray_fire", "ray_hum", "tink", "freeze", "bank", "coin", "music_meadow", "snag", "made_it_home", "carry_chase_calm" } do
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
				zoneMusic = if WorldRules.zoneAt(root.Position) == 2 then "music_forest" else "music_meadow"
				setMusic(wantedMusic())
			end
			task.wait(1)
		end
	end)
	-- a carried cube running low ticks softly, faster near the end (the flashing ice is its visual partner)
	task.spawn(function()
		local last = 0
		while true do
			if carryCount > 0 and carryLife < S.tickBelow then
				local every = if carryLife < S.tickBelow / 2 then S.tickEvery / 2 else S.tickEvery
				if os.clock() - last >= every then
					last = os.clock()
					SoundController.play("melt_tick")
				end
			end
			task.wait(0.1)
		end
	end)
end

return SoundController
