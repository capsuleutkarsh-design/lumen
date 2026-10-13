# Flutter links Windows plugins with symlinks, which need Developer Mode.
# Directory junctions need no special rights, and Flutter skips links that
# already exist, so run this after `flutter pub get` if it complains:
#   powershell -ExecutionPolicy Bypass -File tool\link_plugins.ps1
$root = Split-Path $PSScriptRoot -Parent
$deps = Get-Content "$root\.flutter-plugins-dependencies" -Raw | ConvertFrom-Json
$dir = "$root\windows\flutter\ephemeral\.plugin_symlinks"
New-Item -ItemType Directory -Force $dir | Out-Null
foreach ($p in $deps.plugins.windows) {
  $link = Join-Path $dir $p.name
  if (-not (Test-Path $link)) { cmd /c mklink /J "$link" "$($p.path.TrimEnd('\'))" | Out-Null }
}
Get-ChildItem $dir | Select-Object Name, Target
