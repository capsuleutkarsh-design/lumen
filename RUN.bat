@echo off
rem ------------------------------------------------------------------
rem  Runs Lumen from the source code, to try your changes.
rem  In the console window: r = reload code, R = restart app, q = quit.
rem  Needs Flutter (C:\dev\flutter) and Visual Studio 2022 with C++.
rem ------------------------------------------------------------------
setlocal
pushd "%~dp0"
where flutter >nul 2>nul || set "PATH=C:\dev\flutter\bin;%PATH%"
where flutter >nul 2>nul || (echo Flutter was not found. Install it to C:\dev\flutter. & goto :failed)

echo Getting packages ...
call flutter pub get || goto :failed
powershell -NoProfile -ExecutionPolicy Bypass -File tool\link_plugins.ps1 >nul

echo Starting Lumen ...
call flutter run -d windows || goto :failed
popd
exit /b 0

:failed
popd
echo.
echo RUN FAILED - see the messages above.
pause
exit /b 1
