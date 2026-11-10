--!strict
-- State: the client's copy of its own data (sent by the server's PenService, never decided here),
-- the remotes, and the Notify stream every other controller listens to.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- frozen = still in its cube, waiting in your Pets for the Thaw Machine; thawM = the machine it's in,
-- thawAt = when it comes out (workspace:GetServerTimeNow() clock)
export type PetView = { id: string, key: string, pose: string, mut: string?, eq: boolean, income: number,
	frozen: boolean?, thawM: number?, thawAt: number? }
export type Page = { zone: number, found: number, total: number, complete: boolean, secretFound: boolean, claimed: boolean }
-- text has "{n}" where the goal goes; coins = what one claim pays; resetsAt on the server clock
export type Challenge = { text: string, goal: number, have: number, done: boolean, claimed: boolean }
export type Daily = { list: { Challenge }, coins: number, resetsAt: number }
export type View = {
	coins: number,
	income: number,
	incomeMult: number?, -- each pet's own income is multiplied by this (pages, rebirths, 2x pass, friends)
	friends: number?, -- Roblox friends in the server (each +Config.friends.perFriend coins)
	daily: Daily?, -- today's challenges (ChallengeService)
	upgrades: { [string]: number },
	pets: { PetView },
	slots: number,
	machines: number?, -- Thaw Machines in your pan
	found: { [string]: boolean },
	pages: { Page },
	gift: { ready: boolean, locked: boolean, streak: number, nextStreak: number, coins: number },
	forestUnlocked: boolean,
	reach: number?, -- Round 4 phase 6: islands 1..reach have their gates open
	coldPower: number?, -- the endless stat trained in the Training Rink (decided on the server)
	welcome: { coins: number, awaySeconds: number, capped: boolean, best: string? }?,
	settings: { music: boolean, sound: boolean, reducedMotion: boolean, lowGraphics: boolean, unit: string },
	superFreezeCharges: number,
	doubleCoins: boolean?, -- owns the 2x Coins game pass (the server checks it with Roblox)
	stats: { frozen: number, banked: number, melts: number, coinsEarned: number },
	plot: number?,
	rebirths: number,
	seenShows: { [string]: boolean }?, -- shows watched once (SKIP shows after that)
	pan: { look: number }?, -- the pan's Look (Round 4 phase 5; Slots = slots)
	tutorial: { step: number, done: boolean }?, -- Ranger Bo's tutorial (TutorialService): the step you're on, or done
	tester: { mult: number, walk: number, instantFreeze: boolean, noMelt: boolean }?, -- only sent to testers
}

local State = {}
State.view = nil :: View?
State.ranks = {} :: { [string]: number }

local changed = Instance.new("BindableEvent")
local notify = Instance.new("BindableEvent")
State.Changed = changed.Event -- (view)
State.Notify = notify.Event -- (kind, data)

local remotes: Folder

function State.send(name: string, ...: any)
	local r = remotes and remotes:FindFirstChild(name) :: RemoteEvent?
	if r then
		r:FireServer(...)
	end
end

-- a local notice from another controller (same stream as the server's)
function State.local_(kind: string, data: any)
	notify:Fire(kind, data)
end

function State.Init()
	remotes = ReplicatedStorage:WaitForChild("Remotes", 30) :: Folder
	assert(remotes, "Remotes folder missing")
end

function State.Start()
	local data = remotes:WaitForChild("Data", 10) :: RemoteEvent
	local note = remotes:WaitForChild("Notify", 10) :: RemoteEvent
	local rank = remotes:WaitForChild("BoardRank", 10) :: RemoteEvent
	-- connect after every other controller's Start has run, so early messages (welcome back) aren't
	-- passed on before anyone listens; Roblox holds remote events until this connects
	task.defer(function()
		State.connect(data, note, rank)
	end)
end

function State.connect(data: RemoteEvent, note: RemoteEvent, rank: RemoteEvent)
	data.OnClientEvent:Connect(function(v: View)
		State.view = v
		changed:Fire(v)
	end)
	note.OnClientEvent:Connect(function(kind: string, payload: any)
		notify:Fire(kind, payload)
	end)
	rank.OnClientEvent:Connect(function(r: { [string]: number })
		State.ranks = r
	end)
end

return State
