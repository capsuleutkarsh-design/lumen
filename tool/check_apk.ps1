# Checks a release APK still holds audio_service's notification icons. Release builds shrink unused
# resources, and without them Android 8-12 shows no play / pause / next / previous on the notification
# and lock screen (android/app/src/main/res/raw/keep.xml keeps them). Run after `flutter build apk --release`:
#   powershell -ExecutionPolicy Bypass -File tool\check_apk.ps1 [-Apk <path>]
param([string]$Apk = "$PSScriptRoot\..\build\app\outputs\flutter-apk\app-release.apk")
$tools = Get-ChildItem "$env:LOCALAPPDATA\Android\Sdk\build-tools" | Sort-Object { [version]$_.Name } | Select-Object -Last 1
$dump = & "$($tools.FullName)\aapt2.exe" dump resources $Apk
if ($LASTEXITCODE) { Write-Host "aapt2 could not read $Apk"; exit 1 }
$missing = 'audio_service_play_arrow', 'audio_service_pause', 'audio_service_skip_next', 'audio_service_skip_previous' |
  Where-Object { -not ($dump -match "drawable/$_\b") }
if ($missing) { Write-Host "MISSING from the APK: $($missing -join ', ')"; exit 1 }
Write-Host "OK: the notification icons are in $Apk"
