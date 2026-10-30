--!strict
-- Server loader (Code Rules 2): require every service, call every Init() first, then every Start().
-- No service does work at require time, so file order never matters.

type Service = { Init: (() -> ())?, Start: (() -> ())?, Name: string? }

local services: { Service } = {}
local folder = script.Parent:WaitForChild("Services")
for _, m in folder:GetChildren() do
	if m:IsA("ModuleScript") then
		local s = require(m) :: Service
		s.Name = m.Name
		table.insert(services, s)
	end
end
for _, s in services do
	if s.Init then
		local ok, err = pcall(s.Init)
		if not ok then
			warn(`[Init] {s.Name} failed: {err}`)
		end
	end
end
for _, s in services do
	if s.Start then
		task.spawn(function()
			local ok, err = pcall(s.Start :: () -> ())
			if not ok then
				warn(`[Start] {s.Name} failed: {err}`)
			end
		end)
	end
end
