# Pushes Luau files from roblox/src into the open Studio place through studio_bridge.ps1, the
# same mapping as default.project.json (use it when Rojo isn't connected). The repo stays the source.
#   studio_sync.ps1 -Dir <bridge dir> -Files src/server/Services/WorldService.luau,src/shared/Config.luau
#   studio_sync.ps1 -Dir <bridge dir> -Changed     (every file git sees as changed or new)
#   studio_sync.ps1 -Dir <bridge dir> -Remove ServerScriptService.Server.Services.DevService
# A script that was changed in Studio (it matches neither the repo's last commit nor the file) is left
# alone: pull that work into the repo first, or pass -Force. Twice on 2026-11-09 a sync wiped Studio-only work.
param([Parameter(Mandatory)][string]$Dir, [string[]]$Files = @(), [switch]$Changed, [string[]]$Remove = @(), [switch]$Force)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$call = Join-Path $PSScriptRoot 'studio_call.ps1'
$utf8 = New-Object Text.UTF8Encoding($false)
$map = @{ 'src/server' = 'game:GetService("ServerScriptService"):FindFirstChild("Server")'
          'src/shared' = 'game:GetService("ReplicatedStorage"):FindFirstChild("Shared")'
          'src/client' = 'game:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts"):FindFirstChild("Client")' }

if ($Changed) {
    Push-Location $root
    $Files += (git status --porcelain --untracked-files=all -- src | ForEach-Object { $_.Substring(3).Trim('"') -replace '^roblox/', '' } | Where-Object { $_ -like '*.luau' -and (Test-Path $_) })
    Pop-Location
}
$work = Join-Path $Dir 'work'; New-Item -ItemType Directory -Force $work | Out-Null

foreach ($f in ($Files | Select-Object -Unique)) {
    $rel = $f -replace '\\', '/'
    $base = $map.Keys | Where-Object { $rel.StartsWith($_ + '/') } | Select-Object -First 1
    if (-not $base) { Write-Output "SKIP (not under a Rojo root): $rel"; continue }
    $inner = $rel.Substring($base.Length + 1)
    $class = 'ModuleScript'
    if ($inner -like '*.server.luau') { $class = 'Script'; $inner = $inner -replace '\.server\.luau$', '' }
    elseif ($inner -like '*.client.luau') { $class = 'LocalScript'; $inner = $inner -replace '\.client\.luau$', '' }
    else { $inner = $inner -replace '\.luau$', '' }
    $parts = $inner -split '/'
    $src = [IO.File]::ReadAllText((Join-Path $root $rel), $utf8) -replace "`r`n", "`n"
    # a new file isn't in HEAD yet: git's "not in HEAD" goes to stderr, which must not stop the script
    $ErrorActionPreference = 'Continue'
    $head = (git -C $root show "HEAD:./$rel" 2>$null) -join "`n"
    $ErrorActionPreference = 'Stop'
    $eq = '='; while ($src.Contains("]$eq]") -or $head.Contains("]$eq]")) { $eq += '=' }
    $guard = if ($Force) { 'false' } else { 'true' }
    $names = ($parts | ForEach-Object { '"' + $_ + '"' }) -join ', '
    $code = @"
local node = $($map[$base])
local names = { $names }
for i, n in names do
	local child = node:FindFirstChild(n)
	if i == #names then
		if child and child.ClassName ~= "$class" then child:Destroy() child = nil end
		local new = [$eq[
$src]$eq]
		local head = [$eq[
$head]$eq]
		local function same(a, b) return (a:gsub("%s+$", "")) == (b:gsub("%s+$", "")) end
		if $guard and child and #head > 0 and not same(child.Source, head) and not same(child.Source, new) then
			return "REFUSED: changed in Studio (not the repo's last commit); pull it into the repo first, or -Force"
		end
		if not child then child = Instance.new("$class") child.Name = n child.Parent = node end
		child.Source = new
		return "ok " .. child:GetFullName() .. " " .. #child.Source
	end
	if not child then child = Instance.new("Folder") child.Name = n child.Parent = node end
	node = child
end
"@
    $tmp = Join-Path $work 'sync.luau'
    [IO.File]::WriteAllText($tmp, $code, $utf8)
    $out = & $call -Dir $Dir -Tool execute_luau -ArgsJson '{"datamodel_type":"Edit"}' -CodeFile $tmp
    Write-Output "$rel -> $out"
}
foreach ($r in $Remove) {
    $code = "local o = game; for _, n in string.split(`"$r`", `".`") do o = o and o:FindFirstChild(n) end; if o then o:Destroy() return `"removed $r`" end return `"not found $r`""
    $tmp = Join-Path $work 'sync.luau'
    [IO.File]::WriteAllText($tmp, $code, $utf8)
    & $call -Dir $Dir -Tool execute_luau -ArgsJson '{"datamodel_type":"Edit"}' -CodeFile $tmp
}
