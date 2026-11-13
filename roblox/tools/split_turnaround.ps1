# split_turnaround.ps1: cut a 4-view turnaround sheet (front, left, back, right) into four square images on white,
# the input for TRELLIS's multi-image mode.
#   powershell -File split_turnaround.ps1 -Sheet <pet-turnaround-vN.png> -OutDir <dir> -Key <key> [-CutBelow <0-1>]
# Writes <OutDir>/<key>-front.png, -left.png, -back.png, -right.png (768 px). The cuts between views go at the
# emptiest column near 25 / 50 / 75 % of the sheet (views can touch, e.g. Fenny's ears). -CutBelow whites out
# everything under that fraction of the sheet's height (Mirage Manta's sand swirl).
param([Parameter(Mandatory)][string]$Sheet, [Parameter(Mandatory)][string]$OutDir, [Parameter(Mandatory)][string]$Key,
      [double]$CutBelow = 1.0)
Add-Type -AssemblyName System.Drawing
$src = New-Object Drawing.Bitmap $Sheet
$W = $src.Width; $H = $src.Height; $limit = [int]($H * $CutBelow)
function ink($c) { [Math]::Min([Math]::Min($c.R, $c.G), $c.B) -lt 215 }
$count = @{}
for ($x = 0; $x -lt $W; $x += 2) { $n = 0; for ($y = 0; $y -lt $limit; $y += 3) { if (ink $src.GetPixel($x, $y)) { $n++ } }; $count[$x] = $n }
$cuts = @(0)
foreach ($f in 0.25, 0.5, 0.75) {
    $best = 1e9; $at = [int]($W * $f)
    for ($x = [int]($W * ($f - 0.08)) -band -2; $x -lt [int]($W * ($f + 0.08)); $x += 2) { if ($count[$x] -lt $best) { $best = $count[$x]; $at = $x } }
    $cuts += $at
}
$cuts += $W
New-Item -ItemType Directory -Force $OutDir | Out-Null
$names = 'front', 'left', 'back', 'right'
for ($v = 0; $v -lt 4; $v++) {
    # keep the biggest run of inked columns (gaps under 6 px bridged): drops slivers of the neighbouring views
    $runs = @(); $start = -1; $gap = 0; $sum = 0
    for ($x = $cuts[$v] -band -2; $x -lt $cuts[$v + 1]; $x += 2) {
        if ($count[$x] -gt 0) { if ($start -lt 0) { $start = $x; $sum = 0 }; $last = $x; $gap = 0; $sum += $count[$x] }
        elseif ($start -ge 0) { $gap += 2; if ($gap -ge 6) { $runs += , @($start, $last, $sum); $start = -1 } }
    }
    if ($start -ge 0) { $runs += , @($start, $last, $sum) }
    $big = $runs | Sort-Object { $_[2] } -Descending | Select-Object -First 1
    $rx0 = $big[0]; $rx1 = $big[1] + 1
    $x0 = $rx1; $x1 = $rx0; $y0 = $limit; $y1 = 0
    for ($y = 0; $y -lt $limit; $y += 2) { for ($x = $rx0; $x -le $rx1; $x += 2) {
        if (ink $src.GetPixel($x, $y)) { if ($x -lt $x0) { $x0 = $x }; if ($x -gt $x1) { $x1 = $x }; if ($y -lt $y0) { $y0 = $y }; if ($y -gt $y1) { $y1 = $y } } } }
    $bw = $x1 - $x0 + 8; $bh = $y1 - $y0 + 8; $side = [int]([Math]::Max($bw, $bh) * 1.12)
    $out = New-Object Drawing.Bitmap $side, $side
    $g = [Drawing.Graphics]::FromImage($out); $g.Clear([Drawing.Color]::White); $g.InterpolationMode = 'HighQualityBicubic'
    $g.DrawImage($src, (New-Object Drawing.Rectangle ([int](($side - $bw) / 2)), ([int](($side - $bh) / 2)), $bw, $bh),
        (New-Object Drawing.Rectangle ($x0 - 4), ($y0 - 4), $bw, $bh), 'Pixel')
    $g.Dispose()
    $fin = New-Object Drawing.Bitmap $out, 768, 768
    $fin.Save((Join-Path $OutDir "$Key-$($names[$v]).png"), [Drawing.Imaging.ImageFormat]::Png)
    $out.Dispose(); $fin.Dispose()
}
$src.Dispose()
"$Key cuts: $($cuts -join ', ')"
