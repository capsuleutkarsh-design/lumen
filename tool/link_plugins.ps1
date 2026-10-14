# Flutter links Windows plugins with symlinks, which need Developer Mode.
# Directory junctions need no special rights, and Flutter skips links that
# already exist, so run this after `flutter pub get` if it complains:
#   powershell -ExecutionPolicy Bypass -File tool\link_plugins.ps1
# A link that points at an old plugin version is replaced. Links are removed with
# `cmd /c rmdir`, which removes only the link: Remove-Item -Recurse on a junction
# in Windows PowerShell 5.1 deletes the files it points to.
$root = Split-Path $PSScriptRoot -Parent
$deps = Get-Content "$root\.flutter-plugins-dependencies" -Raw | ConvertFrom-Json
$dir = "$root\windows\flutter\ephemeral\.plugin_symlinks"
New-Item -ItemType Directory -Force $dir | Out-Null
foreach ($p in $deps.plugins.windows) {
  $link = Join-Path $dir $p.name
  $target = $p.path.TrimEnd('\')
  $item = Get-Item -LiteralPath $link -Force -ErrorAction SilentlyContinue
  if ($item -and "$($item.Target)" -eq $target) { continue }
  if ($item) { cmd /c rmdir "$link" }
  cmd /c mklink /J "$link" "$target" | Out-Null
}
Get-ChildItem $dir | Select-Object Name, Target
