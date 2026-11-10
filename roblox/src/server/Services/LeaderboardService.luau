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
local WorldText = require(ReplicatedStorage.Shared.WorldText)
local Remotes = require(script.Parent.Remotes)
local DataService = require(script.Parent.DataService)
local WorldService = require(script.Parent.WorldService)

type Board = { id: string, title: string, subtitle: string, icon: string, kind: string }
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

local cleared: { [number]: boolean } = {}

local function writeScores(player: Player)
	local d = DataService.get(player)
	if not d then
		return
	end
	lastWrite[player] = os.clock()
	-- tester accounts keep the Tester panel on live servers (x10,000 coins, +1B), so their scores would
	-- push real players off the boards: they never rank, and an old entry is taken off once (QA 2026-11-05, CA-05)
	if Config.isTester(player.UserId) and not RunService:IsStudio() then
		if not cleared[player.UserId] then
			cleared[player.UserId] = true
			for _, board in LB.boards :: { Board } do
				local store = storeFor(board)
				withRetries(function()
					store:RemoveAsync(tostring(player.UserId))
					return true
				end)
			end
		end
		return
	end
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
	elseif board.id == "coins_week" then
		return Config.coinText(score) -- weekly coins run into the trillions: 1.2T, never 1,200,000,000,000
	end
	local s = tostring(math.floor(score))
	return (s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end

-- The board's look (reference from the owner 2026-11-10): a Chunky Pop header block in the board's
-- colour with its painted icon, title and subtitle; ten rows as rounded blocks, the top 3 in gold,
-- silver and bronze; a rank circle, the player's avatar head and name on the left, the score on the right.
local BS = Config.worldText.board
local built: { [BasePart]: Frame } = {} -- each board's row list, built once per server

local function px(studs: number): number
	return math.floor(studs * BS.pixelsPerStud)
end

local function corner(g: GuiObject, scale: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(scale, 0)
	c.Parent = g
end

local function outline(g: GuiObject, thickness: number, color: Color3?)
	local s = Instance.new("UIStroke")
	s.Thickness = thickness
	s.Color = color or Theme.ink
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.LineJoinMode = Enum.LineJoinMode.Round
	s.Parent = g
end

local function frame(parent: Instance, name: string, color: Color3, size: UDim2, pos: UDim2?): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundColor3 = color
	f.BorderSizePixel = 0
	f.Size = size
	f.Position = pos or UDim2.fromScale(0, 0)
	f.Parent = parent
	return f
end

-- a Chunky Pop block (as Ui.block): a darker lip, one ink outline round the whole block, and a face
-- with a lighter top and a richer bottom. Returns the face, for the content.
local function block(parent: Instance, name: string, color: Color3, size: UDim2, pos: UDim2, round: number, fade: number?): Frame
	local root = frame(parent, name, color:Lerp(Theme.ink, Theme.lipDarken), size, pos)
	corner(root, round)
	outline(root, BS.strokePx)
	local face = frame(root, "Face", color, UDim2.fromScale(1, 1 - BS.lip))
	corner(face, round)
	local shade = Instance.new("UIGradient") -- the bottom of the face a little deeper
	shade.Rotation = 90
	shade.Color = ColorSequence.new(Theme.white, Theme.white:Lerp(Theme.ink, 1 - Config.ui.face.bottomShade))
	shade.Parent = face
	local light = frame(face, "Light", Theme.white, UDim2.fromScale(1, 1))
	light.ZIndex = 0
	corner(light, round)
	local lg = Instance.new("UIGradient") -- a soft white wash across the top
	lg.Rotation = 90
	lg.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, Config.ui.face.topLight), NumberSequenceKeypoint.new(0.55, 1), NumberSequenceKeypoint.new(1, 1),
	})
	lg.Parent = light
	if fade then
		root.BackgroundTransparency = fade
		face.BackgroundTransparency = fade
		light.Visible = false
	end
	return face
end

-- a circle of height h (share of its parent's height), left edge at x (share of the parent's width)
local function circle(parent: Instance, name: string, color: Color3, h: number, x: number): Frame
	local c = frame(parent, name, color, UDim2.fromScale(1, h))
	c.AnchorPoint = Vector2.new(0, 0.5)
	c.Position = UDim2.fromScale(x, 0.5)
	local a = Instance.new("UIAspectRatioConstraint")
	a.DominantAxis = Enum.DominantAxis.Height
	a.Parent = c
	corner(c, 0.5)
	outline(c, BS.strokePx * 0.75)
	return c
end

-- text that shrinks only when a long name won't fit (WorldText.fitSign's rule), never past maxPx
local function text(parent: Instance, s: string, maxPx: number, color: Color3, size: UDim2, pos: UDim2, xAlign: Enum.TextXAlignment, outlined: boolean?): TextLabel
	local t = WorldText.label(parent, s, maxPx, color, outlined ~= false, size, pos)
	t.TextXAlignment = xAlign
	t.TextScaled = true
	local c = Instance.new("UITextSizeConstraint")
	c.MaxTextSize = maxPx
	c.Parent = t
	return t
end

-- the parts of the board that never change: background, header, footer and an empty row list
local function build(part: BasePart, board: Board): Frame
	local old = part:FindFirstChild("Board") -- the old plain-text board (a saved map keeps it)
	if old then
		old:Destroy()
	end
	local sg = WorldText.surface(part, "Board")
	sg.PixelsPerStud = BS.pixelsPerStud
	local accent = Theme.boards[board.id] or Theme.info
	local bg = frame(sg, "Background", Theme.board, UDim2.fromScale(1, 1))
	local depth = Instance.new("UIGradient")
	depth.Rotation = 90
	depth.Color = ColorSequence.new(Theme.white, Theme.white:Lerp(Theme.ink, 0.35))
	depth.Parent = bg
	local rim = frame(bg, "Rim", Theme.white, UDim2.new(1, -BS.rimPx * 2, 1, -BS.rimPx * 2), UDim2.fromOffset(BS.rimPx, BS.rimPx))
	rim.BackgroundTransparency = 1
	corner(rim, 0.02)
	outline(rim, BS.rimPx * 0.5, accent) -- a thin line in the board's colour, so the three boards tell apart

	local w = 1 - BS.padX * 2
	local head = block(bg, "Header", accent, UDim2.fromScale(w, BS.header), UDim2.fromScale(BS.padX, BS.padY), 0.22)
	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.BackgroundTransparency = 1
	icon.Image = Config.images.icons[board.icon] or ""
	icon.ScaleType = Enum.ScaleType.Fit
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Size = UDim2.fromScale(BS.iconScale * 0.9, BS.iconScale * 0.9)
	icon.Position = UDim2.fromScale(0.12, 0.5)
	local ia = Instance.new("UIAspectRatioConstraint")
	ia.DominantAxis = Enum.DominantAxis.Height
	ia.Parent = icon
	icon.Parent = head
	local T = BS.text
	text(head, board.title, px(T.title), Theme.white, UDim2.fromScale(0.72, 0.56), UDim2.fromScale(0.245, 0.06), Enum.TextXAlignment.Left)
	text(head, board.subtitle, px(T.subtitle), Theme.white, UDim2.fromScale(0.72, 0.3), UDim2.fromScale(0.245, 0.6), Enum.TextXAlignment.Left)

	local note = if board.kind == "weekly" then `{LB.weeklyResetLabel}, {string.lower(LB.updatesLabel)}` else LB.updatesLabel
	text(bg, note, px(T.note), Theme.ice, UDim2.fromScale(w, BS.note * 0.8), UDim2.fromScale(BS.padX, BS.padY + BS.header + BS.note * 0.15), Enum.TextXAlignment.Center)
	local list = frame(bg, "Rows", Theme.board, UDim2.fromScale(w, 1), UDim2.fromScale(BS.padX, BS.padY + BS.header + BS.note))
	list.BackgroundTransparency = 1
	sg.Parent = part
	return list
end

-- one row: rank circle, avatar, name, score. Empty places keep the table's shape, faded.
local function drawRow(list: Frame, board: Board, place: number, r: Row?)
	local T = BS.text
	local medal = if r and place <= #Theme.medals then Theme.medals[place] else nil -- an empty place gets no medal
	-- the list is as tall as the board, so row sizes are shares of the board
	local face = block(list, "Row" .. place, medal or Theme.boardRow, UDim2.fromScale(1, BS.row), UDim2.fromScale(0, (place - 1) * (BS.row + BS.rowGap)), 0.32,
		if r or place == 1 then nil else BS.emptyFade)

	-- rank: a light circle with an ink number on medal rows, a dark one with a white number below
	local badge = circle(face, "Rank", if medal then Theme.white:Lerp(medal, 0.3) else Theme.board, 0.8, 0.012)
	text(badge, tostring(place), px(T.rank), if medal then Theme.ink else Theme.white, UDim2.fromScale(1, 0.9), UDim2.fromScale(0, 0.05),
		Enum.TextXAlignment.Center, medal == nil)
	if not r then
		if place == 1 then
			text(face, "Be the first!", px(T.row), Theme.white, UDim2.fromScale(0.7, 0.8), UDim2.fromScale(0.1, 0.08), Enum.TextXAlignment.Left)
		end
		return
	end
	local head = circle(face, "Avatar", Theme.ice, 0.8, 0.098)
	local img = Instance.new("ImageLabel")
	img.BackgroundTransparency = 1
	img.Size = UDim2.fromScale(1, 1)
	img.Image = `rbxthumb://type=AvatarHeadShot&id={r.userId}&w=150&h=150` -- Roblox draws it, no web call
	corner(img, 0.5)
	img.Parent = head

	local score = scoreText(board, r.score)
	text(face, displayName(r.userId), px(T.row), Theme.white, UDim2.fromScale(0.47, 0.72), UDim2.fromScale(0.19, 0.12), Enum.TextXAlignment.Left)
	if board.id == "rarest_pet" then
		-- the tier as a pill in its own colour, like a pet's name tag (Secret's near-black text vanished on navy)
		local tier = Theme.tiers[score] or Theme.tiers.Common
		local pill = block(face, "Tier", tier, UDim2.fromScale(0.3, 0.72), UDim2.fromScale(0.685, 0.14), 0.5)
		text(pill, score, px(T.row * 0.85), Theme.white, UDim2.fromScale(0.9, 0.86), UDim2.fromScale(0.05, 0.04), Enum.TextXAlignment.Center)
	else
		-- on a medal row the score is white; on plain rows it's in the board's colour (ice for freezes, gold for coins)
		local color = if medal then Theme.white elseif board.id == "coins_week" then Theme.coin else Theme.ice
		local right = if board.id == "coins_week" then 0.9 else 0.975 -- the coin sits in the last strip
		text(face, score, px(T.row), color, UDim2.fromScale(0.3, 0.72), UDim2.fromScale(right - 0.3, 0.12), Enum.TextXAlignment.Right)
		if board.id == "coins_week" then
			local coin = Instance.new("ImageLabel") -- every coin amount shows the coin (UI Rules)
			coin.Name = "Coin"
			coin.BackgroundTransparency = 1
			coin.Image = Config.images.icons.coin
			coin.ScaleType = Enum.ScaleType.Fit
			coin.AnchorPoint = Vector2.new(1, 0.5)
			coin.Size = UDim2.fromScale(1, 0.78)
			coin.Position = UDim2.fromScale(0.985, 0.5)
			local a = Instance.new("UIAspectRatioConstraint")
			a.DominantAxis = Enum.DominantAxis.Height
			a.Parent = coin
			coin.Parent = face
		end
	end
end

local function draw(index: number, board: Board, rows: { Row })
	local part = WorldService.boards[index]
	if not part then
		return
	end
	local list = built[part]
	if not list or not list.Parent then
		list = build(part, board)
		built[part] = list
	end
	list:ClearAllChildren()
	for place = 1, LB.size do
		drawRow(list, board, place, rows[place])
	end
end

-- QA: fills every board with sample rows (Studio only; the next refresh puts the real scores back).
-- Run from the server: require(ServerScriptService.Server.Services.LeaderboardService).preview()
function LeaderboardService.preview(count: number?)
	if not RunService:IsStudio() then
		return
	end
	local ids = { 1, 156, 261, 2032622, 21557, 4416634, 7210880, 9876543, 3333, 98765 }
	for index, board in LB.boards :: { Board } do
		local rows: { Row } = {}
		for i = 1, math.min(count or LB.size, #ids) do
			local score = if board.id == "rarest_pet" then math.max(1, #Config.tiers + 1 - i) else math.floor(98765432 / i ^ 1.7)
			if board.id == "coins_week" then
				score *= 40000
			end
			table.insert(rows, { userId = ids[i], score = score })
		end
		fetchNames(ids)
		draw(index, board, rows)
	end
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
