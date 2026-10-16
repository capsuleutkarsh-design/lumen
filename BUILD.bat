@echo off
rem ------------------------------------------------------------------
rem  Builds Gleo for release, with the version from pubspec.yaml:
rem    build\windows\x64\runner\Release\gleo.exe        the program
rem    build\installer\Gleo-Setup-<version>.exe         the installer
rem    build\installer\Gleo-<version>-portable.zip      the portable zip
rem    build\installer\SHA256SUMS.txt                    their checksums
rem  Needs Flutter (C:\dev\flutter), Visual Studio 2022 with C++ and Inno Setup 6.
rem ------------------------------------------------------------------
setlocal
pushd "%~dp0"
where flutter >nul 2>nul || set "PATH=C:\dev\flutter\bin;%PATH%"
where flutter >nul 2>nul || (echo Flutter was not found. Install it to C:\dev\flutter. & goto :failed)

echo Getting packages ...
rem Without Developer Mode the first pub get stops at the plugin links;
rem link_plugins makes them as junctions, then pub get runs again.
call flutter pub get >nul 2>nul
powershell -NoProfile -ExecutionPolicy Bypass -File tool\link_plugins.ps1 >nul || goto :failed
call flutter pub get || goto :failed

echo Checking the code and running the tests ...
call flutter analyze || goto :failed
call flutter test --exclude-tags mpv || goto :failed
rem The tests that drive libmpv run one file at a time (see dart_test.yaml).
call flutter test --tags mpv --concurrency=1 || goto :failed

echo Building the program, the installer and the zip ...
powershell -NoProfile -ExecutionPolicy Bypass -File installer\build_installer.ps1 || goto :failed

echo.
echo DONE. Opening the installer folder ...
if not defined GLEO_NO_PAUSE start "" "%~dp0build\installer"
popd
if not defined GLEO_NO_PAUSE pause
exit /b 0

:failed
popd
echo.
echo BUILD FAILED - see the messages above.
if not defined GLEO_NO_PAUSE pause
exit /b 1
