# Sends one tool call to a running studio_bridge.ps1 and prints the text result.
#   -Tool execute_luau -ArgsJson '{"code":"print(1)"}'
#   -Tool run_code -CodeFile some.luau   (puts the file's text into the "code" argument)
#   -Method tools/list                   (raw JSON-RPC method instead of a tool)
param(
    [Parameter(Mandatory)][string]$Dir,
    [string]$Tool, [string]$ArgsJson = '{}', [string]$CodeFile, [string]$CodeArg = 'code',
    [string]$Method, [int]$TimeoutSec = 180
)
$ErrorActionPreference = 'Stop'
$utf8 = New-Object Text.UTF8Encoding($false)
$a = $ArgsJson | ConvertFrom-Json
if ($CodeFile) { $a | Add-Member -NotePropertyName $CodeArg -NotePropertyValue ([IO.File]::ReadAllText($CodeFile, $utf8)) -Force }
# Default Studio window: the id stored in <Dir>\studio.txt
$studioFile = Join-Path $Dir 'studio.txt'
if ($Tool -and $Tool -ne 'list_roblox_studios' -and -not $a.studio_id -and (Test-Path $studioFile)) {
    $a | Add-Member -NotePropertyName studio_id -NotePropertyValue ((Get-Content $studioFile -Raw).Trim()) -Force
}
$name = '{0:D13}-{1}.json' -f [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds(), [Guid]::NewGuid().ToString('N').Substring(0, 6)
if ($Method) { $req = @{ method = $Method; params = $a } } else { $req = @{ name = $Tool; arguments = $a } }
[IO.File]::WriteAllText((Join-Path $Dir "inbox\$name.tmp"), ($req | ConvertTo-Json -Depth 50 -Compress), $utf8)
Move-Item (Join-Path $Dir "inbox\$name.tmp") (Join-Path $Dir "inbox\$name")
$out = Join-Path $Dir "outbox\$name"
$deadline = (Get-Date).AddSeconds($TimeoutSec)
while (-not (Test-Path $out)) {
    if ((Get-Date) -gt $deadline) { throw "timed out after $TimeoutSec s" }
    Start-Sleep -Milliseconds 100
}
$raw = [IO.File]::ReadAllText($out, $utf8); Remove-Item $out
$resp = $raw | ConvertFrom-Json
if ($resp.result.content) {
    $resp.result.content | ForEach-Object {
        if ($_.type -eq 'image' -and $_.data) {
            $shots = Join-Path $Dir 'shots'; New-Item -ItemType Directory -Force $shots | Out-Null
            $ext = if ($_.mimeType -match 'jpeg') { 'jpg' } else { 'png' }
            $file = Join-Path $shots ("{0}.{1}" -f [IO.Path]::GetFileNameWithoutExtension($name), $ext)
            [IO.File]::WriteAllBytes($file, [Convert]::FromBase64String($_.data))
            "IMAGE: $file"
        } elseif ($_.text) { $_.text } else { "[$($_.type)]" }
    }
}
elseif ($resp.result) { $resp.result | ConvertTo-Json -Depth 20 }
else { $raw }
