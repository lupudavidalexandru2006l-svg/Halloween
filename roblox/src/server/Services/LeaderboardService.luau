--!strict
-- LeaderboardService: owns the three boards (OrderedDataStore) and leaderstats (Coins, Pets).
-- Every DataStore call is in pcall with retries. Scores come from the server's own counters and are
-- clamped to what's possible before writing. The weekly board's store carries the week id, so it
-- resets on the Monday UTC calendar day. Display names only; "A player" when a name can't be fetched.

local BadgeService = game:GetService("BadgeService")
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserService = game:GetService("UserService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Theme = require(ReplicatedStorage.Shared.Theme)
local WorldRules = require(ReplicatedStorage.Shared.WorldRules)
local Remotes = require(script.Parent.Remotes)
local DataService = require(script.Parent.DataService)
local WorldService = require(script.Parent.WorldService)

type Board = { id: string, title: string, kind: string }
type Row = { userId: number, score: number }

local LeaderboardService = {}
local LB = Config.leaderboards
local names: { [number]: string } = {}
local lastWrite: { [Player]: number } = {}
local suffix = ""

local function withRetries<T>(fn: () -> T): (boolean, T?)
	local wait = Config.data.retryBase
	for _ = 1, Config.data.retries do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		task.wait(wait)
		wait *= 2
	end
	return false, nil
end

local function storeFor(board: Board): OrderedDataStore
	local name = LB.storePrefix .. board.id .. suffix
	if board.kind == "weekly" then
		name ..= "_" .. WorldRules.weekId(os.time())
	end
	return DataStoreService:GetOrderedDataStore(name)
end

-- the server's own counters, clamped to what's possible (an integer under 2^63)
local function scoreFor(board: Board, d: DataService.Data): number
	if board.id == "pets_frozen" then
		local possible = math.max(0, os.time() - d.createdAt) * LB.limits.freezesPerSecond
		return math.floor(math.clamp(d.stats.frozen, 0, math.min(LB.limits.frozen, possible)))
	elseif board.id == "rarest_pet" then
		return math.floor(math.clamp(d.rarest.rank, 0, #Config.tiers))
	elseif board.id == "coins_week" then
		if d.week.id ~= WorldRules.weekId(os.time()) then
			return 0 -- only this week's coins count
		end
		return math.floor(math.clamp(d.week.coins, 0, LB.limits.weekCoins))
	end
	return 0
end

local function writeScores(player: Player)
	local d = DataService.get(player)
	if not d then
		return
	end
	lastWrite[player] = os.clock()
	for _, board in LB.boards :: { Board } do
		local score = scoreFor(board, d)
		if score > 0 then
			local store = storeFor(board)
			withRetries(function()
				store:SetAsync(tostring(player.UserId), score)
				return true
			end)
		end
	end
end

local function displayName(userId: number): string
	local p = Players:GetPlayerByUserId(userId)
	if p then
		return p.DisplayName
	end
	return names[userId] or LB.hiddenName
end

local function fetchNames(ids: { number })
	local missing = {}
	for _, id in ids do
		if not names[id] and not Players:GetPlayerByUserId(id) then
			table.insert(missing, id)
		end
	end
	if #missing == 0 then
		return
	end
	local ok, infos = withRetries(function()
		return UserService:GetUserInfosByUserIdsAsync(missing)
	end)
	if ok and infos then
		for _, info in infos :: { any } do
			if typeof(info.Id) == "number" and typeof(info.DisplayName) == "string" then
				names[info.Id] = info.DisplayName
			end
		end
	end
end

local function scoreText(board: Board, score: number): string
	if board.id == "rarest_pet" then
		local t = Config.tiers[score]
		return if t then t.name else "-"
	end
	local s = tostring(math.floor(score))
	return s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
end

local function draw(index: number, board: Board, rows: { Row })
	local part = WorldService.boards[index]
	if not part then
		return
	end
	local sg = part:FindFirstChild("Board") :: SurfaceGui?
	if not sg then
		local g = Instance.new("SurfaceGui")
		g.Name = "Board"
		g.Face = Enum.NormalId.Front
		g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		g.PixelsPerStud = 30
		local frame = Instance.new("Frame")
		frame.Name = "List"
		frame.Size = UDim2.fromScale(1, 1)
		frame.BackgroundColor3 = Theme.board
		frame.Parent = g
		local layout = Instance.new("UIListLayout")
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Parent = frame
		g.Parent = part
		sg = g
	end
	local frame = (sg :: SurfaceGui):FindFirstChild("List") :: Frame
	for _, c in frame:GetChildren() do
		if c:IsA("TextLabel") then
			c:Destroy()
		end
	end
	local lines = 2 + LB.size
	local function line(order: number, text: string, color: Color3)
		local t = Instance.new("TextLabel")
		t.LayoutOrder = order
		t.Size = UDim2.fromScale(1, 1 / lines)
		t.BackgroundTransparency = 1
		t.TextScaled = true
		t.Font = Theme.font
		t.TextColor3 = color
		t.Text = text
		local stroke = Instance.new("UIStroke")
		stroke.Color = Theme.ink
		stroke.Thickness = 2
		stroke.Parent = t
		t.Parent = frame
	end
	line(0, board.title, Theme.coin)
	for i, r in rows do
		if i > LB.size then
			break
		end
		line(i, `{i}. {displayName(r.userId)}   {scoreText(board, r.score)}`, Theme.white)
	end
	if #rows == 0 then
		line(1, "Be the first!", Theme.white)
	end
	line(LB.size + 1, if board.kind == "weekly" then LB.weeklyResetLabel else "All time", Theme.ice)
end

local function refresh()
	local ranks: { [Player]: { [string]: number? } } = {}
	for _, p in Players:GetPlayers() do
		ranks[p] = {}
	end
	for index, board in LB.boards :: { Board } do
		local store = storeFor(board)
		local ok, pages = withRetries(function()
			return store:GetSortedAsync(false, LB.rankScanSize)
		end)
		local rows: { Row } = {}
		if ok and pages then
			local got, page = pcall(function()
				return (pages :: DataStorePages):GetCurrentPage()
			end)
			if got then
				for _, entry in page :: { any } do
					local id = tonumber(entry.key)
					if id and typeof(entry.value) == "number" then
						table.insert(rows, { userId = id, score = entry.value })
					end
				end
			end
		end
		local top = {}
		for i = 1, math.min(LB.size, #rows) do
			table.insert(top, rows[i].userId)
		end
		fetchNames(top)
		draw(index, board, rows)
		for i, r in rows do
			local p = Players:GetPlayerByUserId(r.userId)
			if p and ranks[p] then
				ranks[p][board.id] = i
				if board.kind == "weekly" then
					-- cosmetic only: a glowing name for the weekly top 3 (never coins or pets)
					p:SetAttribute("WeeklyTop", if i <= LB.weeklyTopReward then i else 0)
					if i <= LB.weeklyTopReward and LB.weeklyBadgeId ~= 0 then
						pcall(function()
							BadgeService:AwardBadge(p.UserId, LB.weeklyBadgeId)
						end)
					end
				end
			end
		end
	end
	for p, r in ranks do
		Remotes.fire(p, "BoardRank", r) -- a missing board id = "not in the top 100 yet"
	end
end

local function makeLeaderstats(player: Player)
	local folder = Instance.new("Folder")
	folder.Name = "leaderstats"
	local coins = Instance.new("IntValue")
	coins.Name = "Coins"
	coins.Parent = folder
	local pets = Instance.new("IntValue")
	pets.Name = "Pets"
	pets.Parent = folder
	folder.Parent = player
end

local function updateLeaderstats(player: Player)
	local d = DataService.get(player)
	local ls = player:FindFirstChild("leaderstats")
	if not d or not ls then
		return
	end
	local coins = ls:FindFirstChild("Coins") :: IntValue?
	local pets = ls:FindFirstChild("Pets") :: IntValue?
	if coins then
		coins.Value = math.floor(d.coins)
	end
	if pets then
		pets.Value = #d.pets
	end
end

function LeaderboardService.Init()
	suffix = if RunService:IsStudio() then Config.data.qaStoreSuffix else ""
end

function LeaderboardService.Start()
	DataService.Loaded:Connect(function(player: Player)
		makeLeaderstats(player)
		updateLeaderstats(player)
		lastWrite[player] = os.clock()
	end)
	DataService.Changed:Connect(updateLeaderstats)
	Players.PlayerRemoving:Connect(function(player)
		writeScores(player) -- DataService saves after this (deferred), so the data is still there
		lastWrite[player] = nil
	end)
	task.spawn(function()
		while true do
			for player, at in lastWrite do
				if os.clock() - at >= LB.writeSeconds then
					task.spawn(writeScores, player)
				end
			end
			task.wait(5)
		end
	end)
	task.spawn(function()
		while true do
			refresh()
			task.wait(LB.refreshSeconds)
		end
	end)
end

return LeaderboardService
