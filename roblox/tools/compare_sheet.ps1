# compare_sheet.ps1: the comparison check (Pet Rules 12.2): a new pet's review sheet stacked over the review sheets
# of the same tier on the previous island, each row labelled, so "at least as good?" is one look.
#   powershell -File compare_sheet.ps1 -Dir <pets_trellis> -New <key> -Old <key>[,<key>...]
# Reads <Dir>/_review_<key>.png (review_sheet.ps1), writes <Dir>/_compare_<new>.png.
param([Parameter(Mandatory)][string]$Dir, [Parameter(Mandatory)][string]$New, [Parameter(Mandatory)][string[]]$Old)
Add-Type -AssemblyName System.Drawing
$keys = @($New) + ($Old | ForEach-Object { $_ -split ',' } | Where-Object { $_ })
$label = 34
$imgs = $keys | ForEach-Object { [System.Drawing.Image]::FromFile((Resolve-Path (Join-Path $Dir "_review_$_.png")).Path) }
$w = [int](($imgs | ForEach-Object { $_.Width } | Measure-Object -Maximum).Maximum)
$h = [int](($imgs | ForEach-Object { $_.Height + $label } | Measure-Object -Sum).Sum)
$sheet = New-Object System.Drawing.Bitmap $w, $h
$g = [System.Drawing.Graphics]::FromImage($sheet)
$g.Clear([System.Drawing.Color]::White)
$font = New-Object System.Drawing.Font 'Arial', 16, ([System.Drawing.FontStyle]::Bold)
$y = 0
for ($i = 0; $i -lt $imgs.Count; $i++) {
    $text = if ($i -eq 0) { "NEW: $($keys[$i])" } else { "previous island, same tier: $($keys[$i])" }
    $brush = if ($i -eq 0) { [System.Drawing.Brushes]::DarkGreen } else { [System.Drawing.Brushes]::DimGray }
    $g.DrawString($text, $font, $brush, 8, $y + 6)
    $g.DrawImage($imgs[$i], 0, $y + $label, $imgs[$i].Width, $imgs[$i].Height)
    $y += $imgs[$i].Height + $label
    $imgs[$i].Dispose()
}
$out = Join-Path $Dir "_compare_$New.png"
$sheet.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $sheet.Dispose()
$out
