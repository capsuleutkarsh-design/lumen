# Runs every integration test in one command, one `flutter test` per file, and waits for the
# previous test app to be gone before the next starts. Two things broke a plain
# `flutter test integration_test`: flutter's Windows device serves one app per run (its log
# reader closes when the first app exits: "The log reader stopped unexpectedly"), and a test app
# still closing makes the next one find its media_kit handles ("NativeReferenceHolder: Located")
# and die after two seconds, or meet the single-instance check.
# Usage (data never goes to the real library):
#   powershell -ExecutionPolicy Bypass -File tool\integration.ps1 -Data <scratch>\appdata [-Music <folder with testlib and real_music>] [-Shots <folder>]
param([Parameter(Mandatory = $true)][string]$Data, [string]$Music, [string]$Shots)
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root
$defines = @("--dart-define=MP_DATA=$Data", "--dart-define=MP_ROOT=$root")
if ($Music) { $defines += "--dart-define=MP_MUSIC=$Music" }
if ($Shots) { $defines += "--dart-define=MP_SHOTS=$Shots" }
$exe = Join-Path $root 'build\windows\x64\runner\Debug\lumen.exe'
function Wait-TestAppGone {
  for ($i = 0; $i -lt 40; $i++) {
    $left = Get-CimInstance Win32_Process -Filter "Name='lumen.exe'" | Where-Object { $_.ExecutablePath -eq $exe }
    if (-not $left) { return }
    Start-Sleep -Milliseconds 500
  }
  $left | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }   # only this worktree's Debug test app
}
$failed = @()
foreach ($f in Get-ChildItem integration_test\*_test.dart | Sort-Object Name) {
  Wait-TestAppGone
  Write-Host "== $($f.Name)"
  & flutter test "integration_test\$($f.Name)" -d windows @defines
  if ($LASTEXITCODE) { $failed += $f.Name }
}
Wait-TestAppGone
if ($failed) { Write-Host "FAILED: $($failed -join ', ')"; exit 1 }
Write-Host "All integration tests passed."
