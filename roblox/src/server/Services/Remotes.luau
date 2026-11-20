--!strict
-- Remotes: the owner of every RemoteEvent (created in Init). Every client call goes through
-- Remotes.on, which rate-limits per player and swallows errors quietly (Code Rules 6).
-- Clients send intent only; outcomes are decided by the services.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)

local Remotes = {}

local NAMES = {
	-- client -> server (intent)
	"BuyUpgrade", "CollectWelcome", "RequestSuperFreeze", "SetMenuOpen", "ShopOpened",
	"EquipPet", "EquipBest", "SetSetting", "Tester", "ShowDone", "BuyGun", "EquipGun", "BuyPanUpgrade", "SellPets",
	"Aim", "SetGear", "ThrowGel", "BuyGear", "RedeemCode", -- Round 5: shooting the ray, the hotbar, Slow Gel, codes
	"PlaceBomb", "BreakIce", -- PvP 2026-11-19: place a Frost Bomb at your feet; tap to break out of the ice (BombService, TagService)
	"Rebirth", -- Round 4 phase 7: the Rebirth Booth
	"ThawPet", -- put a frozen pet from your Pets in your Thaw Machine (owner 2026-11-09)
	"BuyRobux", -- the Shop's Robux tab (MonetizationService shows Roblox's own prompt)
	"ClaimPage", -- claim a full Index page's +10% (IndexService, 2026-11-09)
	"ClaimChallenge", -- claim a finished daily challenge (ChallengeService, 2026-11-09)
	"Tutorial", -- the tutorial: "next" on a talk step, "skip", "replay" (TutorialService, 2026-11-10)
	"Train", -- one click shot at the training station you stand on (TrainingService, 2026-11-10)
	"GetBoard", -- ask for a leaderboard's top 100 (LeaderboardService answers with "BoardRows", 2026-11-12)
	"ClaimGift", -- the one-time Free Gift's Claim (PenService checks the community join, 2026-11-12)
	"SkipThaw", -- skip a Thaw Machine's wait with Robux (MonetizationService, 2026-11-12)
	"SkipThawAll", -- thaw every frozen pet at once with Robux (MonetizationService, owner 2026-11-16)
	"ClaimThaw", -- take a thawed pet out of its machine (PenService, owner 2026-11-13)
	"Teleport", -- the top buttons: to the Equipment Booth or your pan (TravelService, 2026-11-12)
	"SendFeedback", -- the Feedback mailbox: a mood and a short message (FeedbackService, owner 2026-11-17 night)
	"Extras", -- login calendar, weekly quests, chests, ray skins, mute (ExtrasService, 2026-11-19)
	"Trade", -- trading (TradeService, 2026-11-19)
	"VisitPan", -- look at a top-100 player's pan, read-only (LeaderboardService answers with Notify "panVisit", 2026-11-20)
	-- server -> client (what happened)
	"Data", "Notify", "BoardRank", "BoardRows",
}
local events: { [string]: RemoteEvent } = {}
local calls: { [Player]: { [string]: { number } } } = {} -- per player: bucket ("*" or a remote's name) -> call times
local notYetAt: { [Player]: { [string]: number } } = {}

function Remotes.Init()
	local folder = Instance.new("Folder")
	folder.Name = "Remotes"
	for _, name in NAMES do
		local e = Instance.new("RemoteEvent")
		e.Name = name
		e.Parent = folder
		events[name] = e
	end
	folder.Parent = ReplicatedStorage
end

function Remotes.Start()
	Players.PlayerRemoving:Connect(function(p)
		calls[p] = nil
		notYetAt[p] = nil
	end)
end

-- each player has one shared budget per second, and a remote listed in Config.player.rateLimits has its
-- own, so a burst of aiming (or calls bunched up by a phone's lag spike) can't crowd out "Aim none" or
-- "SetMenuOpen" (mobile QA 2026-11-10)
local function allowed(player: Player, name: string): boolean
	local own = Config.player.rateLimits[name]
	local bucket = if own then name else "*"
	local limit = own or Config.player.rateLimitPerSecond
	local now = os.clock()
	local buckets = calls[player] or {}
	calls[player] = buckets
	local list: { number } = buckets[bucket] or {}
	local kept: { number } = {}
	for _, t in list do
		if now - t < 1 then
			table.insert(kept, t)
		end
	end
	buckets[bucket] = kept
	if #kept >= limit then
		return false -- dropped quietly
	end
	table.insert(kept, now)
	return true
end

-- handler gets (player, ...) exactly as sent; it must type-check every argument itself
function Remotes.on(name: string, handler: (Player, ...any) -> ...any)
	local e = events[name]
	assert(e, "unknown remote " .. name)
	e.OnServerEvent:Connect(function(player: Player, ...)
		if not allowed(player, name) then
			return
		end
		local ok, err = pcall(handler, player, ...)
		if not ok then
			warn(`[Remotes] {name} from {player.UserId}: {err}`)
		end
	end)
end

function Remotes.fire(player: Player, name: string, ...: any)
	events[name]:FireClient(player, ...)
end

function Remotes.fireAll(name: string, ...: any)
	events[name]:FireAllClients(...)
end

-- "not yet" answers ("Need 120 more", "Pen full"): the same message at most once per cooldown,
-- so standing in a full pen or mashing a button never spams (prototype QA)
function Remotes.notYet(player: Player, reason: string, at: string?)
	local list = notYetAt[player] or {}
	notYetAt[player] = list
	local now = os.clock()
	if now - (list[reason] or -math.huge) < Config.notYetCooldown then
		return
	end
	list[reason] = now
	events.Notify:FireClient(player, "notYet", { reason = reason, at = at })
end

-- small shared validators
function Remotes.isId(v: any, maxLen: number?): boolean
	return typeof(v) == "string" and #v > 0 and #v <= (maxLen or 32)
end

return Remotes
