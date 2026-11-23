--!strict
-- Hooks (2026-11-19): plain signals other services fire, so ExtrasService can listen without a require loop.
--   Banked(player, pets)  pets = { { key, tier, rank, mut } } just brought home (PenService.bank)
--   Melted(player)        a carried cube melted (CarryService.melt)
--   Lost(player, why)     a pet left your hands any other way: "night" (Night Reset), "critter" (knocked loose),
--                         "dropped" (PvP hit / Frost Bomb), "gone" (a ground cube left too long). The streak breaks
--                         on every one (owner 2026-11-23: "after you lose a pet from anything the streak should reset")
local Hooks = {}

local banked = Instance.new("BindableEvent")
local melted = Instance.new("BindableEvent")
local lost = Instance.new("BindableEvent")
Hooks.Banked = banked.Event
Hooks.Melted = melted.Event
Hooks.Lost = lost.Event

function Hooks.banked(player: Player, pets: { { key: string, tier: string, rank: number, mut: string? } })
	banked:Fire(player, pets)
end
function Hooks.melted(player: Player)
	melted:Fire(player)
end
function Hooks.lost(player: Player, why: string)
	lost:Fire(player, why)
end

return Hooks
