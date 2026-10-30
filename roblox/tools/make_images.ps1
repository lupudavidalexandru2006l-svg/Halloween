# Makes roblox/assets/images/*.png (transparent PNGs for Roblox) from the prototype's art.
# This PC's WebP decoder drops transparency, so:
#  - pet sprites: cut out the concept PNG's white background (flood fill from the edges, like
#    prototype tools/make_sprites.py), fit into 320 px with the feet on the bottom edge
#  - icons: the WebP's transparent area decodes as pure black around the ink outline; flood fill
#    that black from the edges
# Run: powershell -NoProfile -ExecutionPolicy Bypass -File roblox/tools/make_images.ps1
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName PresentationCore
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @"
using System; using System.Collections.Generic; using System.Drawing; using System.Drawing.Imaging; using System.Runtime.InteropServices;
public static class CutOut {
  // pixels connected to the border and within tol of bg become transparent; their neighbours fade
  public static Bitmap Run(Bitmap src, int bgR, int bgG, int bgB, int tol) {
    int w = src.Width, h = src.Height;
    var bmp = new Bitmap(w, h, PixelFormat.Format32bppArgb);
    using (var g = Graphics.FromImage(bmp)) g.DrawImage(src, 0, 0, w, h);
    var data = bmp.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.ReadWrite, PixelFormat.Format32bppArgb);
    var px = new byte[w * h * 4]; Marshal.Copy(data.Scan0, px, 0, px.Length);
    Func<int, int> dist = i => Math.Max(Math.Abs(px[i*4+2]-bgR), Math.Max(Math.Abs(px[i*4+1]-bgG), Math.Abs(px[i*4]-bgB)));
    var bg = new bool[w * h]; var q = new Queue<int>();
    for (int x = 0; x < w; x++) { q.Enqueue(x); q.Enqueue((h-1)*w + x); }
    for (int y = 0; y < h; y++) { q.Enqueue(y*w); q.Enqueue(y*w + w - 1); }
    while (q.Count > 0) {
      int i = q.Dequeue(); if (bg[i] || dist(i) > tol) continue; bg[i] = true;
      int x = i % w, y = i / w;
      if (x > 0) q.Enqueue(i-1); if (x < w-1) q.Enqueue(i+1); if (y > 0) q.Enqueue(i-w); if (y < h-1) q.Enqueue(i+w);
    }
    for (int i = 0; i < w*h; i++) {
      if (bg[i]) { px[i*4+3] = 0; continue; }
      int x = i % w, y = i / w; bool edge = false;
      for (int dy = -1; dy <= 1 && !edge; dy++) for (int dx = -1; dx <= 1; dx++) { int xx = x+dx, yy = y+dy; if (xx>=0 && yy>=0 && xx<w && yy<h && bg[yy*w+xx]) { edge = true; break; } }
      if (edge) { int d = dist(i); px[i*4+3] = (byte)Math.Min(255, 60 + d * 3); } // soft edge: closer to bg = more see-through
    }
    Marshal.Copy(px, 0, data.Scan0, px.Length); bmp.UnlockBits(data); return bmp;
  }
  public static Rectangle Bounds(Bitmap b) {
    int minX = b.Width, minY = b.Height, maxX = -1, maxY = -1;
    var data = b.LockBits(new Rectangle(0, 0, b.Width, b.Height), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
    var px = new byte[b.Width * b.Height * 4]; Marshal.Copy(data.Scan0, px, 0, px.Length); b.UnlockBits(data);
    for (int y = 0; y < b.Height; y++) for (int x = 0; x < b.Width; x++) if (px[(y*b.Width+x)*4+3] > 20) { if (x<minX) minX=x; if (x>maxX) maxX=x; if (y<minY) minY=y; if (y>maxY) maxY=y; }
    return maxX < 0 ? new Rectangle(0, 0, b.Width, b.Height) : new Rectangle(minX, minY, maxX-minX+1, maxY-minY+1);
  }
  // fit the cut-out into a size x size canvas; feet = sit on the bottom edge (sprites), else centred (icons)
  public static Bitmap Fit(Bitmap cut, int size, bool feet, double fill) {
    var r = Bounds(cut); double s = size * fill / Math.Max(r.Width, r.Height);
    int w = (int)Math.Round(r.Width * s), h = (int)Math.Round(r.Height * s);
    var outB = new Bitmap(size, size, PixelFormat.Format32bppArgb);
    using (var g = Graphics.FromImage(outB)) {
      g.InterpolationMode = System.Drawing.Drawing2D.InterpolationMode.HighQualityBicubic; g.Clear(Color.Transparent);
      int x = (size - w) / 2, y = feet ? size - h : (size - h) / 2;
      g.DrawImage(cut, new Rectangle(x, y, w, h), r, GraphicsUnit.Pixel);
    }
    return outB;
  }
}
"@
$proto = Join-Path $PSScriptRoot "..\..\prototype\ice-ray-for-pets"
$out = Join-Path $PSScriptRoot "..\assets\images"
New-Item -ItemType Directory -Force $out | Out-Null

# pet sprites from the approved concepts (key = file name with - instead of _)
foreach ($s in Get-ChildItem "$proto\assets\sprites" -Filter *.webp) {
  $key = $s.BaseName
  $concept = Join-Path "$proto\pets" (($key -replace "_", "-") + "-v1.png")
  if ($key -eq "bloomhorn_stag") { $concept = Join-Path "$proto\pets" "bloomhorn-stag-v2.png" }
  if (-not (Test-Path $concept)) { "skip $key (no concept)"; continue }
  $src = [System.Drawing.Bitmap]::FromFile((Resolve-Path $concept))
  $cut = [CutOut]::Run($src, 255, 255, 255, 18)
  $fit = [CutOut]::Fit($cut, 320, $true, 1.0)
  $fit.Save((Join-Path $out "$key.png"), [System.Drawing.Imaging.ImageFormat]::Png)
  $src.Dispose(); $cut.Dispose(); $fit.Dispose(); "sprite $key"
}

# icons: decode the WebP (black where it was transparent), flood fill the black from the edges
foreach ($n in @("coin", "bag", "book", "gear", "gift", "trophy")) {
  $dec = [System.Windows.Media.Imaging.BitmapDecoder]::Create([Uri](Resolve-Path "$proto\assets\icons\$n.webp").Path, [System.Windows.Media.Imaging.BitmapCreateOptions]::None, [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad)
  $enc = New-Object System.Windows.Media.Imaging.BmpBitmapEncoder
  $enc.Frames.Add($dec.Frames[0])
  $ms = New-Object System.IO.MemoryStream; $enc.Save($ms); $ms.Position = 0
  $src = New-Object System.Drawing.Bitmap($ms)
  $cut = [CutOut]::Run($src, 0, 0, 0, 10)
  $cut.Save((Join-Path $out "$n.png"), [System.Drawing.Imaging.ImageFormat]::Png)
  $src.Dispose(); $cut.Dispose(); "icon $n"
}
