# Regenerates chassis_svg_b64.json from assets/layouts/*.svg
# Then re-pack templates with: python tools/inject_visual_editor.py (if present)
# Or manually set visual_editor.chassis_svg_b64 in META.
#
# IMPORTANT: META JSON must not contain the raw digraph "}}" — Mustache comments
# end at the first "}}". When dumping JSON, replace "}}" with "} }".

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
if (-not (Test-Path "$root\assets\layouts")) { $root = (Resolve-Path "$PSScriptRoot\..").Path }

$map = @{
  yealink = 'yealink_physical.svg'
  cisco   = 'cisco_88xx.svg'
  poly    = 'poly_vvx.svg'
}
$out = @{}
foreach ($k in $map.Keys) {
  $path = Join-Path $root "assets\layouts\$($map[$k])"
  if (-not (Test-Path $path)) { throw "Missing $path" }
  $bytes = [IO.File]::ReadAllBytes($path)
  $out[$k] = [Convert]::ToBase64String($bytes)
}
$jsonPath = Join-Path $PSScriptRoot 'chassis_svg_b64.json'
($out | ConvertTo-Json -Compress) | Set-Content -Encoding ascii $jsonPath
Write-Output "Wrote $jsonPath"
