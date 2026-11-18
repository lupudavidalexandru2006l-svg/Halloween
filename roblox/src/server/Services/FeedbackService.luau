--!strict
-- FeedbackService (owner 2026-11-17 night: "have a mailbox where you can send feedback"): the Feedback mailbox
-- beside the Free Gift. A player picks a mood (Config.feedback.kinds) and may add a short message. Decided here:
-- at the mailbox (the server's own position), a known kind, a string of at most maxLength, one message per
-- cooldown and perDay a UTC day. The text goes through Roblox's TextService filter (if the filter fails, the
-- text is dropped and only the mood is kept). Saved with no name and no user id: the mood, the filtered text,
-- how far they'd got ("R2 I5") and the time, in a DataStore key per UTC day. Nobody but the owner reads it
-- (the Tester panel's Mail tab, TesterService "mail"). Never shown to other players.

local Players = game:GetService("Players")
local TextService = game:GetService("TextService")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(script.Parent.Remotes)
local PlayerTracker = require(script.Parent.PlayerTracker)
local AnalyticsSvc = require(script.Parent.AnalyticsSvc)

local FeedbackService = {}
local F = Config.feedback
local lastAt: { [Player]: number } = {}
local sentToday: { [Player]: { day: string, n: number } } = {}
local store: DataStore? = nil

export type Mail = { t: number, k: string, m: string, s: string }

local function dayKey(t: number?): string
	return "day" .. os.date("!%Y%m%d", t or os.time())
end

local function kindOk(k: any): boolean
	if typeof(k) ~= "string" then
		return false
	end
	for _, d in F.kinds do
		if d.id == k then
			return true
		end
	end
	return false
end

local function atMailbox(player: Player): boolean
	local p = PlayerTracker.position(player)
	local at = Config.world.mailbox
	return p ~= nil and (Vector3.new(p.X, 0, p.Z) - Vector3.new(at.X, 0, at.Z)).Magnitude <= F.range
end

-- the text as Roblox's filter lets everyone see it ("" when empty, or when the filter can't be reached)
local function filtered(player: Player, text: string): string
	if text == "" then
		return ""
	end
	local ok, out = pcall(function()
		local r = TextService:FilterStringAsync(text, player.UserId, Enum.TextFilterContext.PublicChat)
		return r:GetNonChatStringForBroadcastAsync()
	end)
	return if ok and typeof(out) == "string" then out else ""
end

local function save(mail: Mail): boolean
	if not store then
		return false
	end
	for attempt = 1, 3 do
		local ok = pcall(function()
			(store :: DataStore):UpdateAsync(dayKey(mail.t), function(old: any)
				local list = if typeof(old) == "table" then old else {}
				table.insert(list, mail)
				while #list > F.keep do
					table.remove(list, 1)
				end
				return list
			end)
		end)
		if ok then
			return true
		end
		task.wait(attempt)
	end
	return false
end

local function send(player: Player, kind: any, text: any)
	if not kindOk(kind) or (text ~= nil and typeof(text) ~= "string") or not atMailbox(player) then
		return
	end
	local now = os.clock()
	if now - (lastAt[player] or -math.huge) < F.cooldown then
		Remotes.notYet(player, "Thanks! You can send another one in a minute", "mail")
		return
	end
	local day = dayKey()
	local count = sentToday[player]
	if count and count.day == day and count.n >= F.perDay then
		Remotes.notYet(player, "That's all the mail for today. Thank you!", "mail")
		return
	end
	lastAt[player] = now
	sentToday[player] = { day = day, n = (if count and count.day == day then count.n else 0) + 1 }
	local raw = string.sub(string.gsub(text or "", "[%c]", " "), 1, F.maxLength)
	local stage = AnalyticsSvc.stage(player)
	local mail: Mail = { t = os.time(), k = kind, m = filtered(player, raw), s = stage }
	Remotes.fire(player, "Notify", "feedbackSent", { kind = kind })
	AnalyticsSvc.event(player, "feedback_sent", { kind = kind, stage = stage })
	if not save(mail) then
		warn("[FeedbackService] could not save a message (DataStore off in Studio?)")
	end
end

-- the newest messages, newest first, from today and the days before (the Tester panel's Mail tab)
function FeedbackService.latest(n: number): { Mail }
	local out: { Mail } = {}
	if not store then
		return out
	end
	for back = 0, 6 do
		local ok, list = pcall(function()
			return (store :: DataStore):GetAsync(dayKey(os.time() - back * 86400))
		end)
		if ok and typeof(list) == "table" then
			for i = #list, 1, -1 do
				table.insert(out, list[i])
				if #out >= n then
					return out
				end
			end
		end
	end
	return out
end

function FeedbackService.Init()
	local ok, ds = pcall(function()
		return DataStoreService:GetDataStore(F.store)
	end)
	store = if ok then ds else nil
end

function FeedbackService.Start()
	Remotes.on("SendFeedback", send)
	Players.PlayerRemoving:Connect(function(p)
		lastAt[p] = nil
		sentToday[p] = nil
	end)
end

return FeedbackService
