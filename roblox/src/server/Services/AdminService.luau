--!strict
-- AdminService (owner 2026-11-18: "add an admin abuse category where i can spawn shit in all of the servers: things
-- go from events to pets sizes mutation etc"): the Tester panel's ADMIN tab. A tester's request (TesterService
-- "admin") is checked here, run in this server at once, then sent to every other server of the game with
-- MessagingService (Config.admin.topic) and checked again when it lands there. Only presets from Config.admin are
-- accepted, and shouts are fixed lines: no free text ever reaches players.
-- What it can do: start or end a server event, a boost (luck / coins / golden / big sizes, x2-x25 for 5-60 min),
-- pet rain on every island (any rarity, forced size and mutation), one pet next to every player, a pet gift into
-- everyone's Pets, night / morning, a Secret, a fresh wave, a shout. Boosts are workspace attributes that
-- EventService.mult reads; they are also kept in MemoryStore until they end, so a server opening mid-boost joins in.
-- msg.here = this server only (to try a thing before sending it everywhere).
-- "message" (owner 2026-11-18: "so i can write a message across all servers"): the admin's own words. Filtered
-- by Roblox's TextService here, in the sending server, before it is shown or sent; only the filtered text travels.

local Players = game:GetService("Players")
local MessagingService = game:GetService("MessagingService")
local MemoryStoreService = game:GetService("MemoryStoreService")
local HttpService = game:GetService("HttpService")
local TextService = game:GetService("TextService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local PetDefs = require(ReplicatedStorage.Shared.PetDefs)
local WorldRules = require(ReplicatedStorage.Shared.WorldRules)
local Remotes = require(script.Parent.Remotes)
local DataService = require(script.Parent.DataService)
local PenService = require(script.Parent.PenService)
local EventService = require(script.Parent.EventService)
local WildPetSpawner = require(script.Parent.WildPetSpawner)

local AdminService = {}
local A = Config.admin
local serverId = HttpService:GenerateGUID(false) -- our own messages come back to us too: skip them
local lastAt: { [Player]: number } = {}
local boostStore: MemoryStoreSortedMap? = nil
local wasOn: { [string]: boolean } = {} -- boosts running on the last tick (for the "boost over" alert)

export type Msg = { op: string, t: number, from: string?, here: boolean?, filtered: boolean?, a: any, b: any, c: any, d: any }

local function tierName(v: any): string?
	if typeof(v) ~= "string" then
		return nil
	end
	for _, t in Config.tiers do
		if t.name == v then
			return t.name
		end
	end
	return nil
end

local function eventDef(id: any): (number?, Config.ServerEvent?)
	for i, e in Config.events.list do
		if e.id == id then
			return i, e
		end
	end
	return nil, nil
end

local function boostDef(id: any): { id: string, label: string, line: string }?
	for _, b in A.boosts do
		if b.id == id then
			return b
		end
	end
	return nil
end

local function petOk(v: any): boolean
	return typeof(v) == "string" and PetDefs.get(v) ~= nil
end

local function mutOk(v: any): boolean
	return v == "" or (typeof(v) == "string" and Config.mutations[v] ~= nil)
end

local function sizeOk(v: any): boolean
	return v == "" or (typeof(v) == "string" and Config.sizes[v] ~= nil)
end

-- the message, checked the same way when a tester sends it and when another server's copy lands here
local function valid(m: any): boolean
	if typeof(m) ~= "table" or typeof(m.op) ~= "string" or typeof(m.t) ~= "number" or m.t ~= m.t then
		return false
	end
	local op, a, b, c, d = m.op, m.a, m.b, m.c, m.d
	if op == "event" then
		return (eventDef(a)) ~= nil
	elseif op == "endEvent" or op == "secret" or op == "wave" or op == "clearBoosts" then
		return true
	elseif op == "night" then
		return typeof(a) == "boolean"
	elseif op == "boost" then
		return boostDef(a) ~= nil and table.find(A.boostMults, b) ~= nil and table.find(A.boostMinutes, c) ~= nil
	elseif op == "rain" then
		return (a == "" or tierName(a) ~= nil) and table.find(A.rainCounts, b) ~= nil and mutOk(c) and sizeOk(d)
	elseif op == "petAll" or op == "giveAll" then
		return petOk(a) and mutOk(b) and sizeOk(c)
	elseif op == "shout" then
		return typeof(a) == "number" and A.shouts[a] ~= nil
	elseif op == "message" then
		-- already filtered by the server that sent it (only this game's servers can publish to the topic)
		return typeof(a) == "string" and #a > 0 and #a <= A.messageMax * 4 and m.filtered == true
			and typeof(b) == "string" and #b > 0 and #b <= 40
	end
	return false
end

-- the admin's text as Roblox's filter lets everyone see it; nil if the filter can't be reached (then nothing is sent)
local function filterFor(player: Player, raw: string): string?
	local ok, out = pcall(function()
		local r = TextService:FilterStringAsync(raw, player.UserId, Enum.TextFilterContext.PublicChat)
		return r:GetNonChatStringForBroadcastAsync()
	end)
	return if ok and typeof(out) == "string" and out ~= "" then out else nil
end

local function shout(text: string, color: string, seconds: number?)
	Remotes.fireAll("Notify", "adminAbuse", { text = text, color = color, seconds = seconds })
end

-- "Huge Golden Snow Bunny": the words a banner uses for a forced pet
local function petWords(key: string?, mut: string, sz: string): string
	local parts: { string } = {}
	if sz ~= "" then
		table.insert(parts, sz)
	end
	if mut ~= "" then
		table.insert(parts, mut)
	end
	local def = if key then PetDefs.get(key) else nil
	table.insert(parts, if def then def.name else "pets")
	return table.concat(parts, " ")
end

local function forced(mut: string, sz: string): WildPetSpawner.Forced
	return { mut = if mut ~= "" then mut else nil, sz = if sz ~= "" then sz else nil }
end

local function setBoost(kind: string, mult: number, untilAt: number)
	workspace:SetAttribute("Admin_" .. kind, mult)
	workspace:SetAttribute("AdminUntil_" .. kind, untilAt)
end

-- the event clock (WorldRules.eventAt) jumped so this event starts now: the same jump in every server, worked out
-- from the time the message was sent, so they all agree
local function startEvent(idx: number, sentAt: number)
	local E = Config.events
	local n = #E.list
	local off = workspace:GetAttribute("EventOffset")
	local shift = if typeof(off) == "number" then off else 0
	local t = sentAt + shift
	local slot = math.floor((t - E.offsetSeconds) / E.everySeconds)
	local k = slot + ((idx - 1 - slot) % n)
	workspace:SetAttribute("EventOffset", shift + (k * E.everySeconds + E.offsetSeconds - t) + 0.5)
end

local function run(m: Msg)
	local op = m.op
	if op == "event" then
		local idx, e = eventDef(m.a)
		if not idx or not e then
			return
		end
		local before = EventService.current()
		startEvent(idx, m.t)
		if e.id == "chill" then
			EventService.startNow() -- snow and no melting right away, not on the next tick
		end
		if before and before.id == e.id then
			-- the same event again: the clock restarts it quietly, so say it here
			shout(`ADMIN restarted {e.name}! {e.line}`, e.id)
		end
	elseif op == "endEvent" then
		local now = workspace:GetServerTimeNow()
		local cur, ends = WorldRules.eventAt(now)
		if cur then
			local off = workspace:GetAttribute("EventOffset")
			workspace:SetAttribute("EventOffset", (if typeof(off) == "number" then off else 0) + (ends - now) + 0.5)
		end
	elseif op == "boost" then
		local b = boostDef(m.a)
		if b then
			setBoost(b.id, m.b, m.t + m.c * 60)
			shout(`ADMIN ABUSE! x{m.b} {string.upper(b.label)} for {m.c} min! ` .. string.gsub(b.line, "{m}", tostring(m.b)), b.id)
		end
	elseif op == "clearBoosts" then
		for _, b in A.boosts do
			setBoost(b.id, 1, 0)
		end
	elseif op == "night" then
		EventService.setNight(m.a)
	elseif op == "secret" then
		local names = WildPetSpawner.spawnSecrets()
		if #names > 0 then
			Remotes.fireAll("Notify", "secretSpawned", { islands = names, count = #names })
		end
	elseif op == "wave" then
		WildPetSpawner.newWave()
		shout("ADMIN: fresh pets on every island!", "luck")
	elseif op == "rain" then
		local made = WildPetSpawner.rain(m.a, m.b, forced(m.c, m.d))
		if made > 0 then
			local what = petWords(nil, m.c, m.d)
			shout(`PET RAIN! {if m.a ~= "" then m.a .. " " else ""}{what} on every island!`, "secret")
		end
	elseif op == "petAll" then
		for _, p in Players:GetPlayers() do
			if DataService.isLoaded(p) then
				WildPetSpawner.devSpawnPet(p, m.a, 0, forced(m.b, m.c), true)
			end
		end
		shout(`ADMIN ABUSE! A {petWords(m.a, m.b, m.c)} appeared next to you! Zap it!`, "secret")
	elseif op == "giveAll" then
		for _, p in Players:GetPlayers() do
			if DataService.isLoaded(p) and DataService.mutate(p, function(d)
				PenService.addPet(d, m.a, "idle", if m.b ~= "" then m.b else nil, nil, if m.c ~= "" then m.c else nil)
			end) then
				PenService.markDirty(p)
			end
		end
		shout(`ADMIN GIFT! Everyone got a {petWords(m.a, m.b, m.c)}! Look in your Pets`, "golden")
	elseif op == "shout" then
		shout(A.shouts[m.a], "secret")
	elseif op == "message" then
		-- like Grow a Garden (owner 2026-11-18: "the alert is not it"): no boxed banner, only the chat-style line
		-- "Name [verified]: text" on screen and in chat (HudController "adminChat")
		Remotes.fireAll("Notify", "adminChat", { name = m.b, text = m.a, seconds = A.messageSeconds })
	end
end

-- a boost that just ran out says so (checked every second)
local function boostTick()
	for _, b in A.boosts do
		local on = EventService.adminMult(b.id) ~= 1
		if wasOn[b.id] and not on then
			shout(`The {b.label} boost is over. Thanks for playing!`, "night")
		end
		wasOn[b.id] = on
	end
end

-- TesterService "admin": the tester's own server runs it now, then every other server gets it
function AdminService.request(player: Player, m: any)
	if not Config.isTester(player.UserId) or typeof(m) ~= "table" then
		return
	end
	local now = os.clock()
	if now - (lastAt[player] or -math.huge) < A.cooldown then
		return
	end
	lastAt[player] = now
	local msg: Msg = { op = m.op, t = workspace:GetServerTimeNow(), from = serverId, a = m.a, b = m.b, c = m.c, d = m.d }
	if msg.op == "message" then
		-- the admin's own words: one line, at most messageMax characters, then Roblox's filter
		if typeof(m.a) ~= "string" then
			return
		end
		local raw = string.gsub(m.a, "%c", " ")
		raw = string.match(raw, "^%s*(.-)%s*$") or ""
		if raw == "" or utf8.len(raw) == nil then
			return
		end
		if (utf8.len(raw) :: number) > A.messageMax then
			raw = string.sub(raw, 1, (utf8.offset(raw, A.messageMax + 1) :: number) - 1)
		end
		local clean = filterFor(player, raw)
		if not clean then
			Remotes.notYet(player, "The text filter didn't answer. Try again")
			return
		end
		msg.a, msg.b, msg.c, msg.d = clean, player.DisplayName, nil, nil -- the admin's name goes with it
		msg.filtered = true
	end
	if not valid(msg) then
		return
	end
	local ok, err = pcall(run, msg)
	if not ok then
		warn("[AdminService] run:", err)
	end
	if msg.op == "boost" and not m.here and boostStore then
		local store = boostStore :: MemoryStoreSortedMap
		task.spawn(pcall, function()
			store:SetAsync(msg.a, { m = msg.b, u = msg.t + msg.c * 60 }, msg.c * 60 + 5)
		end)
	elseif msg.op == "clearBoosts" and not m.here and boostStore then
		local store = boostStore :: MemoryStoreSortedMap
		task.spawn(pcall, function()
			for _, b in A.boosts do
				store:RemoveAsync(b.id)
			end
		end)
	end
	if m.here then
		Remotes.notYet(player, "Done in this server only")
		return
	end
	task.spawn(function()
		local sent = pcall(function()
			MessagingService:PublishAsync(A.topic, msg)
		end)
		if not sent then
			Remotes.notYet(player, "Other servers didn't get it (this one did)")
		end
	end)
end

function AdminService.Init()
	local ok, map = pcall(function()
		return MemoryStoreService:GetSortedMap("AdminBoosts")
	end)
	boostStore = if ok then map else nil
end

function AdminService.Start()
	Players.PlayerRemoving:Connect(function(p)
		lastAt[p] = nil
	end)
	local ok, err = pcall(function()
		MessagingService:SubscribeAsync(A.topic, function(packet: any)
			local m = if typeof(packet) == "table" then packet.Data else nil
			if typeof(m) == "table" and m.from ~= serverId and not m.here and valid(m) then
				local good, why = pcall(run, m :: Msg)
				if not good then
					warn("[AdminService] message:", why)
				end
			end
		end)
	end)
	if not ok then
		warn("[AdminService] no cross-server messages:", err)
	end
	-- a boost already running in the other servers: join it
	if boostStore then
		local store = boostStore :: MemoryStoreSortedMap
		for _, b in A.boosts do
			local got, v = pcall(function()
				return store:GetAsync(b.id)
			end)
			if got and typeof(v) == "table" and table.find(A.boostMults, v.m) and typeof(v.u) == "number"
				and v.u > workspace:GetServerTimeNow() then
				setBoost(b.id, v.m, v.u)
			end
		end
	end
	task.spawn(function()
		while true do
			task.wait(1)
			pcall(boostTick)
		end
	end)
end

return AdminService
