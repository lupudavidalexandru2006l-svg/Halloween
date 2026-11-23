--!strict
-- ClientHooks: places where one controller lets another add to its UI without requiring it (no require
-- loops). Set by EggController (2026-11-22); PopupController calls them if they are set.
--   shopTop(scroll, order) -> order: add rows at the top of the Shop's list (the limited egg banner)
--   indexExtra(list, order, view, helpers): add a page after the island pages (the Limited page)
local ClientHooks = {
	shopTop = nil :: ((Instance, number) -> number)?,
	indexExtra = nil :: ((Instance, number, any, any) -> ())?,
}
return ClientHooks
