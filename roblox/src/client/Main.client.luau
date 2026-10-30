--!strict
-- Client loader (Code Rules 2): require every controller, call every Init() first, then every Start().

type Controller = { Init: (() -> ...any)?, Start: (() -> ...any)?, Name: string? }

local controllers: { Controller } = {}
local folder = script.Parent:WaitForChild("Controllers", 10)
assert(folder, "Controllers folder missing")
for _, m in folder:GetChildren() do
	if m:IsA("ModuleScript") then
		local c = require(m) :: Controller
		c.Name = m.Name
		table.insert(controllers, c)
	end
end
for _, c in controllers do
	if c.Init then
		local ok, err = pcall(c.Init)
		if not ok then
			warn(`[Init] {c.Name} failed: {err}`)
		end
	end
end
for _, c in controllers do
	if c.Start then
		task.spawn(function()
			local ok, err = pcall(c.Start :: () -> ...any)
			if not ok then
				warn(`[Start] {c.Name} failed: {err}`)
			end
		end)
	end
end
