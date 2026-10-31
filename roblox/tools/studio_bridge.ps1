# Keeps Roblox Studio's own MCP server (StudioMCP.exe --stdio) running and passes it
# tool calls dropped as JSON files into a folder. Used when the Studio connector isn't
# attached to a Claude session.
#   Start:  powershell -NoProfile -ExecutionPolicy Bypass -File studio_bridge.ps1 -Dir <folder>
#   Call:   studio_call.ps1 -Dir <folder> -Tool <name> -ArgsJson '{...}'
param([Parameter(Mandatory)][string]$Dir)

$ErrorActionPreference = 'Stop'
$inbox = Join-Path $Dir 'inbox'; $outbox = Join-Path $Dir 'outbox'
New-Item -ItemType Directory -Force $inbox, $outbox | Out-Null

$exe = Get-ChildItem "$env:LOCALAPPDATA\Roblox\Versions" -Recurse -Filter StudioMCP.exe |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $exe) { throw 'StudioMCP.exe not found' }

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $exe.FullName
$psi.Arguments = '--stdio'
$psi.UseShellExecute = $false
$psi.RedirectStandardInput = $true
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.StandardOutputEncoding = [Text.Encoding]::UTF8
$proc = [Diagnostics.Process]::Start($psi)
$utf8 = New-Object Text.UTF8Encoding($false)
$stdin = New-Object IO.StreamWriter($proc.StandardInput.BaseStream, $utf8)
$stdin.AutoFlush = $true
$proc.BeginErrorReadLine()

$script:nextId = 1
function Send-Rpc([string]$method, $params) {
    $id = $script:nextId; $script:nextId++
    $msg = @{ jsonrpc = '2.0'; id = $id; method = $method; params = $params } | ConvertTo-Json -Depth 50 -Compress
    $stdin.WriteLine($msg)
    while ($true) {
        $line = $proc.StandardOutput.ReadLine()
        if ($null -eq $line) { throw 'StudioMCP closed its output' }
        if ($line -match ('"id"\s*:\s*' + $id + '\b')) { return $line }
    }
}

Send-Rpc 'initialize' @{ protocolVersion = '2024-11-05'; capabilities = @{}; clientInfo = @{ name = 'studio-bridge'; version = '1' } } | Out-Null
$stdin.WriteLine('{"jsonrpc":"2.0","method":"notifications/initialized"}')
Set-Content -Path (Join-Path $Dir 'ready') -Value $proc.Id

while (-not $proc.HasExited) {
    $req = Get-ChildItem $inbox -Filter *.json -ErrorAction SilentlyContinue | Sort-Object Name | Select-Object -First 1
    if (-not $req) { Start-Sleep -Milliseconds 150; continue }
    $out = Join-Path $outbox $req.Name
    try {
        $body = [IO.File]::ReadAllText($req.FullName, $utf8) | ConvertFrom-Json
        if ($body.method) { $resp = Send-Rpc $body.method $body.params }
        else { $resp = Send-Rpc 'tools/call' @{ name = $body.name; arguments = $body.arguments } }
    } catch { $resp = (@{ error = "$_" } | ConvertTo-Json -Compress) }
    Remove-Item $req.FullName -Force
    [IO.File]::WriteAllText("$out.tmp", $resp, $utf8)
    Move-Item "$out.tmp" $out -Force
}
