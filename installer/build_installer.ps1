# Builds Lumen and its installer: build\installer\Lumen-Setup-<version>.exe
# Needs Flutter on PATH and Inno Setup 6.
param([string]$Version = "0.1.1-beta")
$ErrorActionPreference = "Stop"
Set-Location (Join-Path $PSScriptRoot "..")
flutter build windows --release
if ($LASTEXITCODE) { throw "flutter build failed" }
$iscc = @("${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe", "$env:ProgramFiles\Inno Setup 6\ISCC.exe",
          "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $iscc) { throw "Inno Setup 6 not found" }
& $iscc /Q "/DAppVersion=$Version" installer\lumen.iss
if ($LASTEXITCODE) { throw "ISCC failed" }
Get-ChildItem build\installer
