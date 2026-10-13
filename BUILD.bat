@echo off
rem ------------------------------------------------------------------
rem  Builds Lumen for release:
rem    build\windows\x64\runner\Release\lumen.exe     the program
rem    build\installer\Lumen-Setup-<version>.exe      the installer
rem  Needs Flutter (C:\dev\flutter), Visual Studio 2022 with C++ and Inno Setup 6.
rem  Optional: BUILD.bat 0.2.0-beta   (the version shown by the installer)
rem ------------------------------------------------------------------
setlocal
pushd "%~dp0"
where flutter >nul 2>nul || set "PATH=C:\dev\flutter\bin;%PATH%"
where flutter >nul 2>nul || (echo Flutter was not found. Install it to C:\dev\flutter. & goto :failed)

echo Getting packages ...
call flutter pub get || goto :failed
powershell -NoProfile -ExecutionPolicy Bypass -File tool\link_plugins.ps1 >nul

echo Checking the code and running the tests ...
call flutter analyze || goto :failed
call flutter test || goto :failed

echo Building the program and the installer ...
if "%~1"=="" (
    powershell -NoProfile -ExecutionPolicy Bypass -File installer\build_installer.ps1 || goto :failed
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -File installer\build_installer.ps1 -Version %1 || goto :failed
)

echo.
echo DONE. Opening the installer folder ...
start "" "%~dp0build\installer"
popd
pause
exit /b 0

:failed
popd
echo.
echo BUILD FAILED - see the messages above.
pause
exit /b 1
