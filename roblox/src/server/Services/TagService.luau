--!strict
-- TagService (Round 5, owner 2026-11-02; PvP final plan 2026-11-19): ray-tag. The gun works like a bat: one
-- click on a player who carries a cube outside the hub freezes them in an ice block for Config.tag.frozenSeconds
-- and their cube drops to the ground for anyone to grab (CarryService.dropOpen; owner 2026-11-19: carried cubes
-- can really be stolen). Frost Bombs (BombService) freeze the same way, longer, and you can tap to break out
-- (BreakIce). Only cubes in hands; banked pets are never at risk. Nobody on the first tutorial lesson.
-- Safe: the hub; a new player's first Config.tag.shieldMinutes of play, across visits (saved as
-- data.shieldLeft; a two-way shield: you can't tag anyone while you have it); a short shield after being tagged. Attributes every client reads:
-- Player "Taggable", "Shielded", "ShieldUntil" (server time), "Tagged"; the victim's
-- HumanoidRootPart "Meter" and "AimedBy" (the beam and the ice on them).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local WorldRules = require(ReplicatedStorage.Shared.WorldRules)
local Remotes = require(script.Parent.Remotes)
local DataService = require(script.Parent.DataService)
local PlayerTracker = require(script.Parent.PlayerTracker)
local CarryService = require(script.Parent.CarryService)
local FreezeService = require(script.Parent.FreezeService)
local TutorialService = require(script.Parent.TutorialService)
local Theme = require(ReplicatedStorage.Shared.Theme)

local TagService = {}
local T = Config.tag
type Victim = { meter: number, pushedAt: number, by: Player? }
local victims: { [Player]: Victim } = {}
type Frozen = { untilT: number, minT: number, block: BasePart? }
local frozen: { [Player]: Frozen } = {}
local lastHit: { [Player]: number } = {} -- the shooter's last hit (Config.tag.hitCooldown)

local function shielded(p: Player): boolean
	local u = p:GetAttribute("ShieldUntil")
	return typeof(u) == "number" and workspace:GetServerTimeNow() < u
end

-- seconds before this shooter can tag again (Config.tag.hitCooldown); for the Studio tester hook
function TagService.cooldownLeft(shooter: Player): number
	return math.max(0, T.hitCooldown - (os.clock() - (lastHit[shooter] or -math.huge)))
end

local function byId(id: string): Player?
	local n = tonumber(id)
	return if n then Players:GetPlayerByUserId(n) else nil
end

local function hrpOf(p: Player): BasePart?
	return PlayerTracker.rootPart(p)
end

-- can be tagged right now: carrying a cube that can be knocked loose (never only a Super Freeze cube), outside the
-- hub, no shield, not already tumbling
local function taggable(p: Player): boolean
	local pos = PlayerTracker.position(p)
	return pos ~= nil and CarryService.knockable(p) and not WorldRules.inHub(pos) and not shielded(p) and p:GetAttribute("Tagged") ~= true
		and not TutorialService.learning(p)
end
TagService.taggable = taggable

local function setMeter(p: Player, v: Victim, meter: number, by: Player?)
	v.meter = meter
	local hrp = hrpOf(p)
	if hrp then
		local shown = if meter <= 0 then 0 else math.max(Config.aim.step, math.floor(meter / Config.aim.step) * Config.aim.step)
		if hrp:GetAttribute("Meter") ~= shown then
			hrp:SetAttribute("Meter", shown)
		end
		local id = if by then by.UserId else 0
		if hrp:GetAttribute("AimedBy") ~= id then
			hrp:SetAttribute("AimedBy", id)
		end
	end
end

local function thaw(p: Player, f: Frozen)
	if frozen[p] ~= f then
		return
	end
	frozen[p] = nil
	if f.block then
		f.block:Destroy()
	end
	local hrp = hrpOf(p)
	if hrp then
		hrp.Anchored = false
	end
	if p.Parent then
		p:SetAttribute("FrozenUntil", nil)
		p:SetAttribute("CanBreak", nil)
		p:SetAttribute("Tagged", false)
		-- a short shield from the moment you thaw (1.5 s: enough to grab your cube and run, short enough that
		-- a fight goes back and forth)
		local u = p:GetAttribute("ShieldUntil")
		p:SetAttribute("ShieldUntil", math.max(if typeof(u) == "number" then u else 0, workspace:GetServerTimeNow() + T.afterTagShield))
		Remotes.fire(p, "Notify", "thawed", {})
	end
end

-- freeze a player in a cartoon ice block (no damage, no knock-out: a funny pose for a moment). minSeconds:
-- tapping (BreakIce) can bring it down to this; nil = no breaking out (a ray hit is only a second anyway)
function TagService.freeze(p: Player, seconds: number, minSeconds: number?): boolean
	local hrp = hrpOf(p)
	if frozen[p] or not hrp then
		return false
	end
	local now = os.clock()
	local f: Frozen = { untilT = now + seconds, minT = now + (minSeconds or seconds), block = nil }
	frozen[p] = f
	local v = victims[p]
	if v then
		setMeter(p, v, 0, nil)
	end
	victims[p] = nil
	p:SetAttribute("Tagged", true)
	p:SetAttribute("FrozenUntil", workspace:GetServerTimeNow() + seconds)
	p:SetAttribute("CanBreak", minSeconds ~= nil and minSeconds < seconds)
	hrp.AssemblyLinearVelocity = Vector3.zero
	hrp.Anchored = true
	local c = p.Character
	if c then
		local ok, cf, size = pcall(function()
			return c:GetBoundingBox()
		end)
		local block = Instance.new("Part")
		block.Name = "FrozenBlock"
		block.Size = if ok and size.Magnitude < 20 then size + Vector3.new(1, 0.6, 1) else Vector3.new(5, 6.5, 4)
		block.CFrame = if ok then cf else hrp.CFrame
		block.Color = Theme.ice
		block.Material = Enum.Material.SmoothPlastic -- not Glass (World Rules)
		block.Transparency = 0.45
		block.Anchored = true
		block.CanCollide = false
		block.CanQuery = false
		block.CanTouch = false
		block.CastShadow = false
		block.Parent = c
		f.block = block
	end
	task.spawn(function()
		while frozen[p] == f and p.Parent and os.clock() < f.untilT do
			task.wait(0.05)
		end
		thaw(p, f)
	end)
	return true
end

-- a tap, key or click while frozen by a bomb: the ice cracks a little faster (never below its minimum)
local function onBreak(player: Player)
	local f = frozen[player]
	if not f or player:GetAttribute("CanBreak") ~= true then
		return
	end
	f.untilT = math.max(f.minT, f.untilT - Config.bombs.tapCut)
	player:SetAttribute("FrozenUntil", workspace:GetServerTimeNow() + math.max(0, f.untilT - os.clock()))
end

local function tag(victim: Player, by: Player)
	lastHit[by] = os.clock()
	local key = CarryService.dropOpen(victim)
	TagService.freeze(victim, T.frozenSeconds, nil)
	Remotes.fire(victim, "Notify", "tagged", { by = by.DisplayName, seconds = T.frozenSeconds, key = key })
	Remotes.fire(by, "Notify", "tagHit", { name = victim.DisplayName, key = key })
end

function TagService.Init() end

function TagService.Start()
	FreezeService.registerTarget("player", {
		pos = function(id: string): Vector3?
			local p = byId(id)
			return if p then PlayerTracker.position(p) else nil
		end,
		canAim = function(shooter: Player, id: string): boolean
			local p = byId(id)
			local from = PlayerTracker.position(shooter)
			return p ~= nil and p ~= shooter and from ~= nil and not WorldRules.inHub(from) and not shielded(shooter)
				and shooter:GetAttribute("Tagged") ~= true and taggable(p)
				and os.clock() - (lastHit[shooter] or -math.huge) >= T.hitCooldown
		end,
		tick = function(shooter: Player, id: string, dt: number, gun: number)
			local p = byId(id)
			if not p then
				return
			end
			local v = victims[p] or { meter = 0, pushedAt = 0, by = nil }
			victims[p] = v
			v.pushedAt = os.clock()
			local seconds = T.freezeSeconds -- the same for everyone: no gun or Cold Power makes tagging faster
			setMeter(p, v, math.min(1, v.meter + dt / seconds), shooter)
			if v.meter >= 1 then
				tag(p, shooter)
			end
		end,
	})
	DataService.Loaded:Connect(function(player: Player, data: DataService.Data)
		-- new to the game: safe for what's left of the first minutes (once they're used up, never again)
		player:SetAttribute("ShieldUntil", workspace:GetServerTimeNow() + data.shieldLeft)
		player:SetAttribute("Shielded", data.shieldLeft > 0)
		player:SetAttribute("Tagged", false)
	end)
	Remotes.on("BreakIce", onBreak)
	Players.PlayerRemoving:Connect(function(p)
		victims[p] = nil
		frozen[p] = nil
		lastHit[p] = nil
	end)
	-- a new character (a reset while frozen) starts unfrozen
	Players.PlayerAdded:Connect(function(p)
		p.CharacterAdded:Connect(function()
			local f = frozen[p]
			if f then
				thaw(p, f)
			end
		end)
	end)
	task.spawn(function()
		while true do
			task.wait(0.1)
			for _, p in Players:GetPlayers() do
				if not DataService.isLoaded(p) then
					continue
				end
				local sh = shielded(p)
				-- use up the new-player shield as they play (no change event: it rides along with the next save)
				local data = DataService.get(p)
				if data and data.shieldLeft > 0 then
					local u = p:GetAttribute("ShieldUntil")
					data.shieldLeft = if typeof(u) == "number" then math.max(0, u - workspace:GetServerTimeNow()) else 0
				end
				-- a force field while shielded, but invisible (owner 2026-11-12: "remove the bubble around the
				-- character"); your own SAFE pill over the hotbar still shows it
				local c = p.Character
				local ff = c and c:FindFirstChild("TagShield")
				if c and sh and not ff then
					local f = Instance.new("ForceField")
					f.Name = "TagShield"
					f.Visible = false
					f.Parent = c
				elseif ff and not sh then
					ff:Destroy()
				end
				if p:GetAttribute("Shielded") ~= sh then
					p:SetAttribute("Shielded", sh)
					if not sh and p:GetAttribute("Tagged") ~= true then
						Remotes.fire(p, "Notify", "shieldOff", {})
					end
				end
				local t = taggable(p)
				if p:GetAttribute("Taggable") ~= t then
					p:SetAttribute("Taggable", t)
				end
				-- nobody shooting: the ice on them melts back
				local v = victims[p]
				if v and os.clock() - v.pushedAt > 0.2 then
					local m = v.meter - T.thawPerSecond * 0.1
					if m <= 0 or not t then
						setMeter(p, v, 0, nil)
						victims[p] = nil
					else
						setMeter(p, v, m, nil)
					end
				end
			end
		end
	end)
end

return TagService
