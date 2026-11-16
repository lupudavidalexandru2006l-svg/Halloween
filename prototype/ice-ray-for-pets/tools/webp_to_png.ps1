# webp_to_png.ps1 -Files a.png.webp,b.png.webp : decode with Windows' WebP codec (WIC), write a real PNG next to
# each (a trailing ".png.webp" becomes ".png"), delete the .webp. Blender 5.2's loader refused FLUX's WebP.
param([Parameter(Mandatory)][string[]]$Files)
Add-Type -AssemblyName PresentationCore
foreach ($f in $Files) {
    $src = (Resolve-Path $f).Path
    $dst = if ($src.EndsWith('.png.webp')) { $src.Substring(0, $src.Length - 5) } else { [IO.Path]::ChangeExtension($src, '.png') }
    $in = [IO.File]::OpenRead($src)
    $dec = [Windows.Media.Imaging.BitmapDecoder]::Create($in, 'PreservePixelFormat', 'OnLoad')
    $enc = New-Object Windows.Media.Imaging.PngBitmapEncoder
    $enc.Frames.Add($dec.Frames[0])
    $out = [IO.File]::Create($dst); $enc.Save($out); $out.Close(); $in.Close()
    Remove-Item $src
    "PNG $dst $($dec.Frames[0].PixelWidth)x$($dec.Frames[0].PixelHeight)"
}
