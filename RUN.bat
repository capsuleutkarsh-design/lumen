@echo off
rem ------------------------------------------------------------------
rem  Runs Gleo from the source code, to try your changes.
rem  In the console window: r = reload code, R = restart app, q = quit.
rem  Needs Flutter (C:\dev\flutter) and Visual Studio 2022 with C++.
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

echo Starting Gleo ...
call flutter run -d windows || goto :failed
popd
exit /b 0

:failed
popd
echo.
echo RUN FAILED - see the messages above.
pause
exit /b 1
