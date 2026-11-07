#Requires -Version 7.0
param(
    [Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{40}$')][string]$Commit,
    [string]$FlutterVersion = '3.47.7'
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not $IsWindows -or [Runtime.InteropServices.RuntimeInformation]::OSArchitecture -ne [Runtime.InteropServices.Architecture]::X64) {
    throw 'The installed-plugin native runner requires Windows x64.'
}
Import-Module (Join-Path $PSScriptRoot 'installed_plugin_windows_runner.psm1')
exit (Invoke-InstalledPluginWindowsRun -Commit $Commit -FlutterVersion $FlutterVersion)
