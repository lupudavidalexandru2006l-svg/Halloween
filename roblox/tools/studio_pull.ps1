# studio_pull.ps1: the opposite of studio_sync.ps1. Copies every script under the Rojo roots from the open
# Studio place into roblox/src, byte for byte (hex-encoded, so non-ASCII survives), through studio_bridge.ps1.
#   studio_pull.ps1 -Dir <bridge dir> -Repo <path to roblox> [-Model Edit|Server]
# Studio's replies are cut at about 100 KB, so sources come over in 40 KB chunks. Review git diff before committing.
param([string]$Dir, [string]$Repo, [string]$Model = 'Server')
$ErrorActionPreference = 'Stop'
$call = Join-Path $Repo 'tools\studio_call.ps1'
$utf8 = New-Object Text.UTF8Encoding($false)

function Invoke-Luau([string]$code) {
    $tmp = Join-Path $Dir 'code.luau'
    [IO.File]::WriteAllText($tmp, $code, $utf8)
    $argj = '{"datamodel_type":"' + $Model + '"}'
    $out = (& $call -Dir $Dir -Tool execute_luau -ArgsJson $argj -CodeFile $tmp) -join "`n"
    if ($out -match 'datamodel is not available') {
        # Studio switched between Edit and Play: read from the other copy (same sources)
        $script:Model = if ($script:Model -eq 'Edit') { 'Server' } else { 'Edit' }
        $argj = '{"datamodel_type":"' + $script:Model + '"}'
        $out = (& $call -Dir $Dir -Tool execute_luau -ArgsJson $argj -CodeFile $tmp) -join "`n"
    }
    if ($out -match 'datamodel is not available|error|Error') { if ($out.Length -lt 400) { throw "Studio: $out" } }
    return $out
}

$list = Invoke-Luau @'
local roots = {
  { game:GetService("ReplicatedStorage"):FindFirstChild("Shared"), "src/shared" },
  { game:GetService("ServerScriptService"):FindFirstChild("Server"), "src/server" },
  { game:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts"):FindFirstChild("Client"), "src/client" },
}
local out = {}
local function walk(inst, path, names)
  for _, c in inst:GetChildren() do
    local nm = table.clone(names)
    table.insert(nm, c.Name)
    if c:IsA("LuaSourceContainer") then
      local ext = if c:IsA("ModuleScript") then ".luau" elseif c:IsA("LocalScript") then ".client.luau" else ".server.luau"
      if #c:GetChildren() > 0 then error("script with children: " .. c:GetFullName()) end
      table.insert(out, path .. "/" .. c.Name .. ext .. "|" .. table.concat(nm, "/") .. "|" .. #c.Source)
    elseif c:IsA("Folder") then
      walk(c, path .. "/" .. c.Name, nm)
    end
  end
end
for i, r in roots do walk(r[1], r[2], { tostring(i) }) end
return table.concat(out, "\n")
'@
$lines = $list -split "`n" | Where-Object { $_ -match '\|' }
"scripts: $($lines.Count)"
$CHUNK = 40000
foreach ($l in $lines) {
    $p = $l.Trim() -split '\|'
    $rel, $names, $len = $p[0], $p[1], [int]$p[2]
    $parts = $names -split '/'
    $rootIdx = $parts[0]
    $chain = ($parts | Select-Object -Skip 1 | ForEach-Object { ':FindFirstChild("' + $_ + '")' }) -join ''
    $rootExpr = @{ '1' = 'game:GetService("ReplicatedStorage"):FindFirstChild("Shared")'
                   '2' = 'game:GetService("ServerScriptService"):FindFirstChild("Server")'
                   '3' = 'game:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts"):FindFirstChild("Client")' }[$rootIdx]
    $bytes = New-Object System.Collections.Generic.List[byte]
    for ($a = 1; $a -le [Math]::Max($len, 1); $a += $CHUNK) {
        $b = $a + $CHUNK - 1
        $hex = Invoke-Luau ("local s = $rootExpr$chain.Source`nreturn (s:sub($a, $b):gsub('.', function(c) return string.format('%02x', c:byte()) end))")
        $hex = ($hex -replace '[^0-9a-f]', '')
        if ($hex.Length % 2 -ne 0) { throw "odd hex for $rel at $a" }
        for ($i = 0; $i -lt $hex.Length; $i += 2) { $bytes.Add([Convert]::ToByte($hex.Substring($i, 2), 16)) }
    }
    if ($bytes.Count -ne $len) { throw "length mismatch for $rel : got $($bytes.Count), want $len" }
    $target = Join-Path $Repo $rel
    New-Item -ItemType Directory -Force (Split-Path $target -Parent) | Out-Null
    [IO.File]::WriteAllBytes($target, $bytes.ToArray())
    "ok $rel $len"
}
