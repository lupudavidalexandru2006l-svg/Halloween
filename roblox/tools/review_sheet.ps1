# review_sheet.ps1: one picture with the concept next to the 3D renders (front, 3/4, side, back),
# so a pet can be judged against its painting from every side (Pet Rules 5).
#   powershell -File review_sheet.ps1 -Concept <png> -Dir <folder with <key>_*_render.png> -Key <key>
param([Parameter(Mandatory)][string]$Concept, [Parameter(Mandatory)][string]$Dir, [Parameter(Mandatory)][string]$Key)
Add-Type -AssemblyName System.Drawing
$cell = 384
$files = @($Concept) + (@('front', '34', 'side', 'back') | ForEach-Object { Join-Path $Dir "${Key}_${_}_render.png" })
$sheet = New-Object System.Drawing.Bitmap ($cell * $files.Count), $cell
$g = [System.Drawing.Graphics]::FromImage($sheet)
$g.Clear([System.Drawing.Color]::White)
$g.InterpolationMode = 'HighQualityBicubic'
for ($i = 0; $i -lt $files.Count; $i++) {
    $img = [System.Drawing.Image]::FromFile($files[$i])
    $g.DrawImage($img, $i * $cell, 0, $cell, $cell)
    $img.Dispose()
}
$out = Join-Path $Dir "_review_$Key.png"
$sheet.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $sheet.Dispose()
$out
