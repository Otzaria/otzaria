@echo off
REM Register otzaria:// URL scheme for Windows
REM This script must be run as Administrator

echo Registering otzaria:// URL scheme...

REM Get the current directory where the executable is located
set "APP_PATH_DEBUG=%~dp0..\build\windows\x64\runner\Debug\otzaria.exe"
set "APP_PATH_RELEASE=%~dp0..\build\windows\x64\runner\Release\otzaria.exe"

REM Check which executable exists - prefer Debug for testing
if exist "%APP_PATH_DEBUG%" (
    set "APP_PATH=%APP_PATH_DEBUG%"
    echo Using Debug build: %APP_PATH%
) else if exist "%APP_PATH_RELEASE%" (
    set "APP_PATH=%APP_PATH_RELEASE%"
    echo Using Release build: %APP_PATH%
) else (
    echo Error: otzaria.exe not found in either Release or Debug directories
    echo Please build the application first using: flutter build windows
    pause
    exit /b 1
)

REM Register the URL scheme in Windows Registry
reg add "HKEY_CLASSES_ROOT\otzaria" /ve /d "URL:Otzaria Protocol" /f
reg add "HKEY_CLASSES_ROOT\otzaria" /v "URL Protocol" /d "" /f
reg add "HKEY_CLASSES_ROOT\otzaria\DefaultIcon" /ve /d "\"%APP_PATH%\",0" /f
reg add "HKEY_CLASSES_ROOT\otzaria\shell" /f
reg add "HKEY_CLASSES_ROOT\otzaria\shell\open" /f
reg add "HKEY_CLASSES_ROOT\otzaria\shell\open\command" /ve /d "\"%APP_PATH%\" \"%%1\"" /f

if %errorlevel% equ 0 (
    echo Successfully registered otzaria:// URL scheme!
    echo You can now open otzaria:// links from web browsers.
) else (
    echo Failed to register URL scheme. Make sure you run this as Administrator.
)

pause