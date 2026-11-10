--!strict
-- TagService (Round 5, owner 2026-11-02): ray-tag. A player who carries a cube outside the hub can be
-- shot like a pet: their meter fills (Config.tag.freezeSeconds / the shooter's gun power), and at 1
-- they tumble over for Config.tag.ragdollSeconds and their top cube pops out as a dazed pet anyone
-- can zap (CarryService.knockOff). Only cubes in hands; banked pets are never at risk.
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

local TagService = {}
local T = Config.tag
type Victim = { meter: number, pushedAt: number, by: Player? }
local victims: { [Player]: Victim } = {}
local ragdoll: { [Player]: { Instance } } = {}

local function shielded(p: Player): boolean
	local u = p:GetAttribute("ShieldUntil")
	return typeof(u) == "number" and workspace:GetServerTimeNow() < u
end

local function byId(id: string): Player?
	local n = tonumber(id)
	return if n then Players:GetPlayerByUserId(n) else nil
end

local function hrpOf(p: Player): BasePart?
	return PlayerTracker.rootPart(p)
end

-- can be tagged right now: carrying, outside the hub, no shield, not already tumbling
local function taggable(p: Player): boolean
	local pos = PlayerTracker.position(p)
	return pos ~= nil and CarryService.count(p) > 0 and not WorldRules.inHub(pos) and not shielded(p) and p:GetAttribute("Tagged") ~= true
end

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

-- the tumble: every limb joint swaps to a loose ball joint, then back (the neck stays, so the
-- character is never hurt); the victim's own client lies the Humanoid down (it owns its physics)
local function tumble(p: Player, on: boolean)
	local c = p.Character
	if not c then
		return
	end
	if on then
		local made: { Instance } = {}
		for _, m in c:GetDescendants() do
			if m:IsA("Motor6D") and m.Name ~= "Neck" and m.Name ~= "RootJoint" and m.Name ~= "Root" and m.Part0 and m.Part1 then
				local a0 = Instance.new("Attachment")
				a0.Name = "TagA0"
				a0.CFrame = m.C0
				a0.Parent = m.Part0
				local a1 = Instance.new("Attachment")
				a1.Name = "TagA1"
				a1.CFrame = m.C1
				a1.Parent = m.Part1
				local b = Instance.new("BallSocketConstraint")
				b.Name = "TagJoint"
				b.Attachment0 = a0
				b.Attachment1 = a1
				b.LimitsEnabled = true
				b.UpperAngle = 60
				b.Parent = m.Part0
				m.Enabled = false
				table.insert(made, a0)
				table.insert(made, a1)
				table.insert(made, b)
				table.insert(made, m)
			end
		end
		ragdoll[p] = made
	else
		for _, x in ragdoll[p] or {} do
			if x:IsA("Motor6D") then
				x.Enabled = true
			else
				x:Destroy()
			end
		end
		ragdoll[p] = nil
	end
end

local function tag(victim: Player, by: Player)
	local v = victims[victim]
	if v then
		setMeter(victim, v, 0, nil)
	end
	victims[victim] = nil
	victim:SetAttribute("Tagged", true)
	victim:SetAttribute("ShieldUntil", workspace:GetServerTimeNow() + T.ragdollSeconds + T.afterTagShield)
	local key = CarryService.knockOff(victim, true)
	tumble(victim, true)
	Remotes.fire(victim, "Notify", "tagged", { by = by.DisplayName, seconds = T.ragdollSeconds, key = key })
	Remotes.fire(by, "Notify", "tagHit", { name = victim.DisplayName, key = key })
	task.delay(T.ragdollSeconds, function()
		if victim.Parent then
			tumble(victim, false)
			victim:SetAttribute("Tagged", false)
		end
	end)
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
	Players.PlayerRemoving:Connect(function(p)
		victims[p] = nil
		ragdoll[p] = nil
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
				-- everyone sees who is safe: Roblox's own sparkly force field around a shielded player
				local c = p.Character
				local ff = c and c:FindFirstChild("TagShield")
				if c and sh and not ff then
					local f = Instance.new("ForceField")
					f.Name = "TagShield"
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
