--!strict
-- State: the client's copy of its own data (sent by the server's PenService, never decided here),
-- the remotes, and the Notify stream every other controller listens to.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

export type PetView = { id: string, key: string, pose: string, mut: string?, eq: boolean, income: number }
export type Page = { zone: number, found: number, total: number, complete: boolean, secretFound: boolean }
export type View = {
	coins: number,
	income: number,
	upgrades: { [string]: number },
	pets: { PetView },
	slots: number,
	found: { [string]: boolean },
	pages: { Page },
	gift: { ready: boolean, locked: boolean, streak: number, nextStreak: number, coins: number },
	forestUnlocked: boolean,
	welcome: { coins: number, awaySeconds: number, capped: boolean, best: string? }?,
	settings: { music: boolean, sound: boolean, reducedMotion: boolean, lowGraphics: boolean, unit: string },
	superFreezeCharges: number,
	stats: { frozen: number, banked: number, melts: number, coinsEarned: number },
	plot: number?,
}

local State = {}
State.view = nil :: View?
State.ranks = {} :: { [string]: number }
State.odds = {} :: { [string]: { [string]: number } }

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
		if kind == "odds" then
			State.odds = payload
		end
		notify:Fire(kind, payload)
	end)
	rank.OnClientEvent:Connect(function(r: { [string]: number })
		State.ranks = r
	end)
end

return State
