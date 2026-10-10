REM Clean Flutter build
call flutter clean

REM Build Flutter Windows app
call flutter build windows

REM The installers' UI art is not in the repo: fetch the pinned version before ISCC
powershell -NoProfile -ExecutionPolicy Bypass -File tool\release\fetch_assistant_art.ps1
if errorlevel 1 exit /b 1

REM Run Inno Setup scripts
call iscc installer\otzaria.iss
call iscc installer\otzaria_full.iss

REM Build Flutter Android app
call flutter build apk 

REM build Flutter linux binaries
call flutter build linux

echo Build and packaging complete.
pause