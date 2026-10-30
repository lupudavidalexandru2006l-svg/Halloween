# Writes roblox/assets/meshes/<Shape>.obj: the few low-poly shapes Roblox has no primitive for.
# Studio merges a multi-object OBJ into one mesh, so each shape is its own file. Import each once
# (Home > Import 3D) and put the MeshParts in ReplicatedStorage.SceneryMeshes, named after the file.
# Every shape fills a unit box centred on the origin; MapArt sets the real Size and Color.
$ErrorActionPreference = "Stop"
$inv = [System.Globalization.CultureInfo]::InvariantCulture
$sb = New-Object System.Text.StringBuilder
$script:vi = 0
$script:cur = ""
$outDir = Join-Path $PSScriptRoot "../assets/meshes"
New-Item -ItemType Directory -Force $outDir | Out-Null
function Flush { if ($script:cur) { [System.IO.File]::WriteAllText((Join-Path $outDir "$($script:cur).obj"), $sb.ToString(), (New-Object System.Text.UTF8Encoding($false))); "wrote $($script:cur).obj" } }
function StartShape($name) { Flush; [void]$sb.Clear(); $script:vi = 0; $script:ni = 0; $script:cur = $name; [void]$sb.AppendLine("o $name") }
$script:ni = 0
function F([double]$x) { $x.ToString("0.#####", $inv) }
function V([double]$x, [double]$y, [double]$z) { [void]$sb.AppendLine("v $(F $x) $(F $y) $(F $z)"); $script:vi++; return $script:vi }
function N([double]$x, [double]$y, [double]$z) { $l = [Math]::Sqrt($x*$x + $y*$y + $z*$z); if ($l -eq 0) { $l = 1 }; [void]$sb.AppendLine("vn $(F ($x/$l)) $(F ($y/$l)) $(F ($z/$l))"); $script:ni++; return $script:ni }
function Tri($a, $b, $c, $na, $nb, $nc) { [void]$sb.AppendLine("f $a//$na $b//$nb $c//$nc") }
# flat triangle: normal from the winding (counter-clockwise seen from outside)
function FlatTri($p, $q, $r) {
  $ux = $q[0]-$p[0]; $uy = $q[1]-$p[1]; $uz = $q[2]-$p[2]
  $wx = $r[0]-$p[0]; $wy = $r[1]-$p[1]; $wz = $r[2]-$p[2]
  $n = N ($uy*$wz - $uz*$wy) ($uz*$wx - $ux*$wz) ($ux*$wy - $uy*$wx)
  $a = V $p[0] $p[1] $p[2]; $b = V $q[0] $q[1] $q[2]; $c = V $r[0] $r[1] $r[2]
  Tri $a $b $c $n $n $n
}

# ---- Cone: radius 0.5 base at y -0.5, tip at y 0.5, 12 sides, smooth sides, flat base
StartShape "Cone"
$seg = 12
$tip = V 0 0.5 0
$base = @(); $norms = @()
for ($i = 0; $i -lt $seg; $i++) { $a = 2*[Math]::PI*$i/$seg; $base += V (0.5*[Math]::Cos($a)) -0.5 (0.5*[Math]::Sin($a)); $norms += N ([Math]::Cos($a)) 0.5 ([Math]::Sin($a)) }
for ($i = 0; $i -lt $seg; $i++) { $j = ($i + 1) % $seg; $tn = N ([Math]::Cos(2*[Math]::PI*($i+0.5)/$seg)) 0.5 ([Math]::Sin(2*[Math]::PI*($i+0.5)/$seg)); Tri $base[$j] $base[$i] $tip $norms[$j] $norms[$i] $tn }
$c = V 0 -0.5 0; $dn = N 0 -1 0
for ($i = 0; $i -lt $seg; $i++) { $j = ($i + 1) % $seg; Tri $base[$i] $base[$j] $c $dn $dn $dn }

# ---- Octa: ice crystal, points at +-0.5 on each axis, flat shaded
StartShape "Octa"
$px = @(0.5,0,0); $nx = @(-0.5,0,0); $py = @(0,0.5,0); $ny = @(0,-0.5,0); $pz = @(0,0,0.5); $nz = @(0,0,-0.5)
foreach ($t in @(@($px,$py,$pz), @($pz,$py,$nx), @($nx,$py,$nz), @($nz,$py,$px), @($pz,$ny,$px), @($nx,$ny,$pz), @($nz,$ny,$nx), @($px,$ny,$nz))) { FlatTri $t[0] $t[1] $t[2] }

# ---- Rock: icosahedron, flat shaded (fits a unit box)
StartShape "Rock"
$g = (1 + [Math]::Sqrt(5)) / 2; $s = 0.5 / $g
$P = @(@(-1,$g,0),@(1,$g,0),@(-1,-$g,0),@(1,-$g,0),@(0,-1,$g),@(0,1,$g),@(0,-1,-$g),@(0,1,-$g),@($g,0,-1),@($g,0,1),@(-$g,0,-1),@(-$g,0,1)) | ForEach-Object { ,@(($_[0]*$s),($_[1]*$s),($_[2]*$s)) }
$faces = @(@(0,11,5),@(0,5,1),@(0,1,7),@(0,7,10),@(0,10,11),@(1,5,9),@(5,11,4),@(11,10,2),@(10,7,6),@(7,1,8),@(3,9,4),@(3,4,2),@(3,2,6),@(3,6,8),@(3,8,9),@(4,9,5),@(2,4,11),@(6,2,10),@(8,6,7),@(9,8,1))
foreach ($f in $faces) { FlatTri $P[$f[0]] $P[$f[2]] $P[$f[1]] }

# ---- Dome: half sphere, flat bottom at y -0.5, top at y 0.5 (mushroom caps, mounds), smooth
StartShape "Dome"
$seg = 16; $rings = 6; $grid = @{}; $gn = @{}
for ($r = 0; $r -le $rings; $r++) {
  $phi = ([Math]::PI/2) * $r / $rings
  for ($i = 0; $i -lt $seg; $i++) {
    $a = 2*[Math]::PI*$i/$seg
    $x = [Math]::Cos($phi)*[Math]::Cos($a); $y = [Math]::Sin($phi); $z = [Math]::Cos($phi)*[Math]::Sin($a)
    $grid["$r,$i"] = V (0.5*$x) ($y - 0.5) (0.5*$z); $gn["$r,$i"] = N $x $y $z
  }
}
for ($r = 0; $r -lt $rings; $r++) { for ($i = 0; $i -lt $seg; $i++) { $j = ($i+1) % $seg
  Tri $grid["$r,$j"] $grid["$r,$i"] $grid["$($r+1),$i"] $gn["$r,$j"] $gn["$r,$i"] $gn["$($r+1),$i"]
  Tri $grid["$r,$j"] $grid["$($r+1),$i"] $grid["$($r+1),$j"] $gn["$r,$j"] $gn["$($r+1),$i"] $gn["$($r+1),$j"] } }
$c = V 0 -0.5 0; $dn = N 0 -1 0
for ($i = 0; $i -lt $seg; $i++) { $j = ($i+1) % $seg; Tri $grid["0,$i"] $grid["0,$j"] $c $dn $dn $dn }

# ---- Torus: flat ring around the Y axis, tube = 0.1 of the width (spawn ring, scarf)
function Torus($name, [double]$R, [double]$tube, [double]$sweep, [string]$plane) {
  StartShape "$name"
  $seg = 32; $ts = 8; $grid = @{}; $gn = @{}
  $closed = $sweep -ge 2*[Math]::PI - 0.001
  $nseg = if ($closed) { $seg } else { $seg + 1 }
  for ($i = 0; $i -lt $nseg; $i++) {
    $a = $sweep * $i / $seg
    for ($k = 0; $k -lt $ts; $k++) {
      $b = 2*[Math]::PI*$k/$ts
      $cx = [Math]::Cos($a); $cy = [Math]::Sin($a)
      $x = ($R + $tube*[Math]::Cos($b))*$cx; $y = ($R + $tube*[Math]::Cos($b))*$cy; $z = $tube*[Math]::Sin($b)
      $nx_ = [Math]::Cos($b)*$cx; $ny_ = [Math]::Cos($b)*$cy; $nz_ = [Math]::Sin($b)
      if ($plane -eq "XZ") { $grid["$i,$k"] = V $x $z $y; $gn["$i,$k"] = N $nx_ $nz_ $ny_ }
      else { $grid["$i,$k"] = V $x $y $z; $gn["$i,$k"] = N $nx_ $ny_ $nz_ }
    }
  }
  $last = if ($closed) { $seg } else { $seg }
  for ($i = 0; $i -lt $last; $i++) { $i2 = if ($closed) { ($i+1) % $seg } else { $i+1 }
    for ($k = 0; $k -lt $ts; $k++) { $k2 = ($k+1) % $ts
      if ($plane -eq "XZ") {
        Tri $grid["$i,$k"] $grid["$i,$k2"] $grid["$i2,$k"] $gn["$i,$k"] $gn["$i,$k2"] $gn["$i2,$k"]
        Tri $grid["$i2,$k"] $grid["$i,$k2"] $grid["$i2,$k2"] $gn["$i2,$k"] $gn["$i,$k2"] $gn["$i2,$k2"]
      } else {
        Tri $grid["$i,$k"] $grid["$i2,$k"] $grid["$i,$k2"] $gn["$i,$k"] $gn["$i2,$k"] $gn["$i,$k2"]
        Tri $grid["$i2,$k"] $grid["$i2,$k2"] $grid["$i,$k2"] $gn["$i2,$k"] $gn["$i2,$k2"] $gn["$i,$k2"]
      }
    } }
}
Torus "Ring" 0.4 0.1 (2*[Math]::PI) "XZ"
# ---- Arch: upright half ring in the XY plane (the Forest gate), tube 0.09 of the radius
Torus "Arch" 1.0 0.09 ([Math]::PI) "XY"

Flush
