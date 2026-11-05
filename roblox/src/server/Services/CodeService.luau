--!strict
-- CodeService (Round 5): redeems codes typed in Settings. Locked until you've caught
-- Config.codes.needPets pets; each code once per player (saved in d.codes, stamped in the same save as
-- the coins); a cooldown against guessing. The codes live in ServerStorage.Codes (server only).

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(script.Parent.Remotes)
local DataService = require(script.Parent.DataService)
local PenService = require(script.Parent.PenService)

local CodeService = {}
local codes: { [string]: { coins: number } } = {}
local lastTry: { [Player]: number } = {}

local function answer(player: Player, ok: boolean, text: string, coins: number?)
	Remotes.fire(player, "Notify", "codeResult", { ok = ok, text = text, coins = coins })
end

local function redeem(player: Player, raw: any)
	if typeof(raw) ~= "string" or #raw == 0 or #raw > Config.codes.maxLength then
		return
	end
	local d = DataService.get(player)
	if not d then
		return
	end
	local now = os.clock()
	if now - (lastTry[player] or -math.huge) < Config.codes.cooldown then
		return -- guessing fast is dropped quietly
	end
	lastTry[player] = now
	if d.stats.frozen < Config.codes.needPets then
		answer(player, false, `Catch {Config.codes.needPets} pets first`)
		return
	end
	local key = raw:upper():gsub("[^%w]", "")
	local reward = codes[key]
	if not reward then
		answer(player, false, "That code doesn't work")
		return
	end
	if d.codes[key] then
		answer(player, false, "Already used")
		return
	end
	local granted = false
	DataService.mutate(player, function(x)
		if x.codes[key] then
			return -- checked again inside the one change that pays
		end
		x.codes[key] = true
		PenService.addCoins(x, reward.coins)
		granted = true
	end)
	if granted then
		DataService.saveNow(player) -- the coins and the "used" stamp in the same save
		answer(player, true, "Code redeemed!", reward.coins)
	end
end

function CodeService.Init()
	local m = ServerStorage:FindFirstChild("Codes")
	if m and m:IsA("ModuleScript") then
		local list = require(m) :: any
		for k, v in list do
			if typeof(k) == "string" and typeof(v) == "table" and typeof(v.coins) == "number" then
				codes[k:upper()] = { coins = v.coins }
			end
		end
	else
		warn("[CodeService] ServerStorage.Codes is missing: no codes work")
	end
end

function CodeService.Start()
	Remotes.on("RedeemCode", redeem)
	Players.PlayerRemoving:Connect(function(p)
		lastTry[p] = nil
	end)
end

return CodeService
