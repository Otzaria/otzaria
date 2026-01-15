@echo off
REM Unregister otzaria:// URL scheme for Windows
REM This script must be run as Administrator

echo Unregistering otzaria:// URL scheme...

REM Remove the URL scheme from Windows Registry
reg delete "HKEY_CLASSES_ROOT\otzaria" /f

if %errorlevel% equ 0 (
    echo Successfully unregistered otzaria:// URL scheme!
) else (
    echo Failed to unregister URL scheme or it was not registered.
)

pause