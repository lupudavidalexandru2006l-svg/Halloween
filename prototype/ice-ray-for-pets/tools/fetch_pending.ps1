# Windows PowerShell version of fetch_pending.sh, for the owner's PC (no bash, Python or Node there).
# Downloads the 4 full-size Sunny Beach concepts the cloud session could not fetch.
# The links were made on 2026-10-30 and expire after 7 days (about 2026-11-06).
# Run from the repo:  powershell -NoProfile -ExecutionPolicy Bypass -File prototype\ice-ray-for-pets\tools\fetch_pending.ps1
$ErrorActionPreference = 'Stop'
$pets = Join-Path $PSScriptRoot '..\pets'
$items = [ordered]@{
  'glowfin-v1.png'         = '7bbe1899-25ea-4460-ad01-fa3873da4590'
  'reefback-turtle-v1.png' = '4b125f50-8af2-493d-8f9a-9a6bf10f85d2'
  'prismapus-v1.png'       = '2d290e2a-9ffc-4312-940f-a4236822bbf9'
  'beacon-orca-v1.png'     = 'fe1414f2-5dde-4f03-9bd6-05709267dca4'
}
foreach ($name in $items.Keys) {
  $out = Join-Path $pets $name
  Invoke-WebRequest -UseBasicParsing -Uri "https://www.figma.com/api/mcp/asset/$($items[$name]).png" -OutFile $out
  Write-Output "saved $name"
}
# Waddles 3D (Rodin V2, prediction f700b615-bd5b-40f2-85bf-8a343bc50609) can only be fetched with the
# Figma MCP tool weave_get_model_run_output once the plan limit resets.
