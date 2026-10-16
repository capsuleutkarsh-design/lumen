# Builds Gleo with the version from pubspec.yaml, then in build\installer:
#   Gleo-Setup-<version>.exe, Gleo-<version>-portable.zip and SHA256SUMS.txt
# Needs Flutter on PATH and Inno Setup 6.
$ErrorActionPreference = "Stop"
Set-Location (Join-Path $PSScriptRoot "..")

# pubspec.yaml is the one place the version is set: "0.2.0-beta+3" gives 0.2.0-beta and file version 0.2.0.3.
$full = (Select-String -Path pubspec.yaml -Pattern '^version:\s*(\S+)').Matches[0].Groups[1].Value
$version = $full.Split('+')[0]
$build = if ($full.Contains('+')) { $full.Split('+')[1] } else { '0' }
$fileVersion = "$($version.Split('-')[0]).$build"
Write-Host "Gleo $version (file version $fileVersion)"

flutter build windows --release
if ($LASTEXITCODE) { throw "flutter build failed" }
$release = "build\windows\x64\runner\Release"
$out = New-Item -ItemType Directory -Force build\installer

# The setup wizard shows plain text, so LICENSE.md becomes LICENSE.txt (UTF-8 with BOM, which Inno Setup reads).
$md = [IO.File]::ReadAllText("$PWD\LICENSE.md", [Text.Encoding]::UTF8)
$txt = $md -replace '<[^>]+>', '' -replace '\[([^\]]*)\]\(mailto:[^)]*\)', '$1' -replace '\[([^\]]*)\]\(([^)]*)\)', '$1 ($2)' `
           -replace '(?m)^#+\s*', '' -replace '(?m)^>\s?', '' -replace '[*`]', '' `
           -replace '[\u2600-\u27BF\uFE0F]|\p{Cs}', '' -replace '(?m)^[ \t]+', '' -replace '(\r?\n){3,}', "`r`n`r`n"
[IO.File]::WriteAllText("$PWD\build\LICENSE.txt", $txt.Trim() + "`r`n", (New-Object Text.UTF8Encoding $true))

$iscc = @("${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe", "$env:ProgramFiles\Inno Setup 6\ISCC.exe",
          "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $iscc) { throw "Inno Setup 6 not found" }
& $iscc /Q "/DAppVersion=$version" "/DFileVersion=$fileVersion" installer\gleo.iss
if ($LASTEXITCODE) { throw "ISCC failed" }

# The portable zip: only what the app needs (never a stale exe from an older build), plus portable.txt.
$stage = "build\portable\Gleo"
if (Test-Path build\portable) { Remove-Item -Recurse -Force build\portable }   # a plain folder made here, no junctions
New-Item -ItemType Directory -Force $stage | Out-Null
Copy-Item "$release\gleo.exe", "$release\*.dll", "$release\*.txt", LICENSE.md, THIRD_PARTY_NOTICES.md, assets\fonts\Inter-OFL.txt $stage
Copy-Item -Recurse "$release\data" $stage
Set-Content -Encoding ascii "$stage\portable.txt" @(
  'Portable mode: Gleo keeps its library, playlists, play counts and log in the "userdata"',
  'folder next to gleo.exe, not in %APPDATA%\Utkarsh Tripathi\Gleo.',
  'Delete this file to use %APPDATA% instead.')
$zip = "$out\Gleo-$version-portable.zip"
if (Test-Path $zip) { Remove-Item $zip }
# Windows' own bsdtar writes zip entries with forward slashes (Compress-Archive in PowerShell 5.1
# writes backslashes, which unzip on Linux and some tools turn into odd file names).
& "$env:SystemRoot\System32\tar.exe" -a -cf $zip -C build\portable Gleo
if ($LASTEXITCODE) { throw "zip failed" }

$files = @("$out\Gleo-Setup-$version.exe", $zip)
$sums = foreach ($f in $files) { "$((Get-FileHash -Algorithm SHA256 $f).Hash.ToLower())  $(Split-Path $f -Leaf)" }
Set-Content -Encoding ascii "$out\SHA256SUMS.txt" $sums
$sums
