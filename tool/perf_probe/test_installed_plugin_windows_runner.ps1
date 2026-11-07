#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not ('InstalledPluginProbe.ControlledRunnerObserver' -as [type])) {
    Add-Type -Path @((Join-Path $PSScriptRoot 'installed_plugin_windows_lifetime.cs'), (Join-Path $PSScriptRoot 'test_installed_plugin_windows_lifetime.cs'))
}
$modulePath = Join-Path $PSScriptRoot 'installed_plugin_windows_runner.psm1'
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('installed-runner-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temporary | Out-Null
$script:assertions = 0
function Assert-Equal($Expected, $Actual, [string]$Message) {
    $script:assertions++
    if ($Expected -cne $Actual) { throw "$Message; expected=$Expected actual=$Actual" }
}
$previousEnvironment = @{}
foreach ($name in @('INSTALLED_PROBE_DATA', 'INSTALLED_PROBE_OUTPUT', 'INSTALLED_PROBE_REPORTS',
    'INSTALLED_PROBE_WINDOWS_PORT', 'INSTALLED_PROBE_WINDOWS_CAMPAIGN', 'INSTALLED_PROBE_WINDOWS_TOKEN')) {
    $previousEnvironment[$name] = [Environment]::GetEnvironmentVariable($name)
}
try {
    foreach ($mode in @('pass', 'driver-failure', 'driver-and-receipt-error', 'receipt-only-error', 'start-receipt-error',
        'raw-log-error', 'native-error', 'native-and-receipt-error', 'partial-report', 'snapshot-path-error',
        'missing-crash-query', 'correlated-crash', 'fixture-read-error', 'observer-collect-error', 'diagnostics-cascade', 'stale-commit', 'earlier-evidence')) {
        $directory = Join-Path $temporary $mode
        New-Item -ItemType Directory -Path $directory | Out-Null
        $env:INSTALLED_PROBE_DATA = Join-Path $directory 'data'
        $env:INSTALLED_PROBE_OUTPUT = Join-Path $directory 'device'
        $env:INSTALLED_PROBE_REPORTS = Join-Path $directory 'host'
        $env:INSTALLED_PROBE_WINDOWS_PORT = 'earlier port'
        $env:INSTALLED_PROBE_WINDOWS_CAMPAIGN = 'earlier campaign'
        $env:INSTALLED_PROBE_WINDOWS_TOKEN = 'earlier token'
        $module = Import-Module $modulePath -Force -PassThru
        & $module {
            param($Mode, $Directory)
            $script:mode = $Mode; $script:directory = $Directory; $script:observer = $null
            $script:driverCalls = 0; $script:finalSaveAttempted = $false
            $script:save = (Get-Command Save-InstalledPluginJson).ScriptBlock
            function script:Start-InstalledPluginLifetimeObserver {
                param([string]$Executable, [string]$CampaignId, [string]$Token)
                $now = [datetime]::UtcNow
                $micros = [long](($now.Ticks - [datetime]::UnixEpoch.Ticks) / 10)
                $script:trace = @{
                    availability = 'collected'; errors = @(); campaignId = $CampaignId; runId = "42-$micros"
                    armedAtUtc = $now.AddSeconds(-2); bootstrapUtc = $now; acknowledgedAtUtc = $now.AddMilliseconds(1)
                    finishedAtUtc = $now.AddSeconds(1); processName = 'otzaria.exe'; bootstrapQuiescent = $true; identityVerified = $true
                    identity = @{ pid = 42; creationFileTime = $now.AddSeconds(-1).ToFileTimeUtc().ToString(); executable = $Executable }
                    exitStatus = 0; exitFileTime = $now.AddMilliseconds(10).ToFileTimeUtc().ToString(); waitResult = 0
                    cleanup = @{ handleAcquired = $true; handleClosed = $true; listenerStopped = $true; channelClosed = $true; bootstrapTaskCompleted = $true }
                }
                $script:observer = [InstalledPluginProbe.ControlledRunnerObserver]::new()
                $script:observer.Snapshot = $script:trace | ConvertTo-Json -Depth 10 -Compress
                return $script:observer
            }
            function script:Invoke-InstalledPluginLoggedCommand {
                param([string]$Command, [string[]]$Arguments, [string]$LogPath)
                $script:driverCalls++
                $t = $script:trace
                $report = @{
                    pid = 42; runId = $t.runId; platform = 'windows'; buildMode = 'profile'; status = 'passed'; errors = @(); testFailures = @()
                    commit = $(if ($script:mode -eq 'stale-commit') { 'b' * 40 } else { 'a' * 40 })
                    windowsLifetime = @{
                        version = 1; kind = 'ready'; pid = 42; runId = $t.runId; campaignId = $t.campaignId
                        creationFileTime = $t.identity.creationFileTime; executable = $t.identity.executable
                        acknowledgedAtUtc = $t.acknowledgedAtUtc; bootstrapQuiescent = $true
                    }
                }
                New-Item -ItemType Directory -Path $env:INSTALLED_PROBE_OUTPUT | Out-Null
                $path = Join-Path $env:INSTALLED_PROBE_OUTPUT 'installed-plugin-report.json'
                if ($script:mode -eq 'partial-report') { [IO.File]::WriteAllText($path, '{ incomplete JSON') }
                else { $report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $path }
                if ($script:mode -in @('snapshot-path-error', 'diagnostics-cascade')) {
                    New-Item -ItemType Directory -Path (Join-Path $script:directory 'windows-device-report.json') | Out-Null
                }
                $code = if ($script:mode -in @('driver-failure', 'driver-and-receipt-error', 'diagnostics-cascade')) { 37 } else { 0 }
                return @{ exitCode = $code; error = $(if ($script:mode -eq 'raw-log-error') { 'controlled raw log write failure' } else { $null }) }
            }
            function script:Stop-InstalledPluginLifetimeObserver {
                param($Observer)
                if ($script:mode -in @('observer-collect-error', 'diagnostics-cascade')) { throw 'controlled original observer collection error' }
                if ($script:mode -in @('native-error', 'native-and-receipt-error')) {
                    $script:trace.availability = 'unavailable'; $script:trace.errors = @('controlled native query failure')
                }
                return $script:trace
            }
            function script:Read-InstalledPluginApplicationErrors {
                param($Trace, $Identity)
                if ($script:mode -eq 'diagnostics-cascade') { throw 'controlled crash query error' }
                return @{
                    availability = $(if ($script:mode -eq 'missing-crash-query') { 'unavailable' } else { 'collected' })
                    events = @(if ($script:mode -eq 'correlated-crash') { @{ exceptionCode = 'c0000005' } })
                    truncated = $false; reason = 'controlled event provider'
                }
            }
            function script:Copy-InstalledPluginFixtureErrors {
                param([string]$Source, [string]$Destination)
                if ($script:mode -in @('fixture-read-error', 'diagnostics-cascade')) { throw 'controlled fixture read error' }
                return @{ availability = 'notProduced'; reason = 'controlled fixture' }
            }
            function script:Save-InstalledPluginJson {
                param([hashtable]$Value, [string]$Path)
                if ([IO.Path]::GetFileName($Path) -eq 'windows-native-exit-start.json' -and $script:mode -eq 'start-receipt-error') {
                    throw 'controlled initial receipt write failure'
                }
                if ([IO.Path]::GetFileName($Path) -eq 'windows-native-exit.json') {
                    $script:finalSaveAttempted = $true
                    $script:lastReceipt = $Value.Clone()
                    if ($script:observer.Disposals -eq 0) { throw 'Native cleanup must precede final receipt I/O.' }
                    if ($script:mode -in @('driver-and-receipt-error', 'receipt-only-error', 'native-and-receipt-error', 'diagnostics-cascade')) {
                        throw 'controlled final receipt write failure'
                    }
                }
                & $script:save -Value $Value -Path $Path
            }
        } $mode $directory
        $receiptPath = Join-Path $directory 'windows-native-exit.json'
        if ($mode -eq 'earlier-evidence') { [IO.File]::WriteAllText($receiptPath, 'unchanged earlier receipt') }
        if ($mode -eq 'earlier-evidence') {
            $caught = $null
            try { Invoke-InstalledPluginWindowsRun -Commit ('a' * 40) -Executable (Join-Path $directory 'otzaria.exe') | Out-Null }
            catch { $caught = $_ }
            Assert-Equal $true ($null -ne $caught) 'An earlier receipt prevents a new run'
            Assert-Equal 'unchanged earlier receipt' ([IO.File]::ReadAllText($receiptPath)) 'Earlier evidence is preserved byte-for-byte'
            Assert-Equal $null (& $module { $script:observer }) 'Evidence collision occurs before native acquisition'
        } else {
            $code = Invoke-InstalledPluginWindowsRun -Commit ('a' * 40) -Executable (Join-Path $directory 'otzaria.exe')
            $expected = if ($mode -eq 'pass') { 0 } elseif ($mode -in @('driver-failure', 'driver-and-receipt-error', 'diagnostics-cascade')) { 37 } else { 1 }
            Assert-Equal $expected $code "The $mode runner returns the original failure or fails evidence-only errors"
            Assert-Equal 1 (& $module { $script:observer.Disposals }) 'Owned native cleanup runs independently of diagnostic I/O'
            Assert-Equal $true (& $module { $script:finalSaveAttempted }) 'Final partial receipt is attempted independently'
            Assert-Equal $(if ($mode -eq 'start-receipt-error') { 0 } else { 1 }) (& $module { $script:driverCalls }) 'Initial receipt failure prevents the driver but still cleans up'
            if ($mode -eq 'native-and-receipt-error') {
                $partial = & $module { $script:lastReceipt }
                Assert-Equal 'native-exit' $partial.firstError.stage 'A receipt failure does not become the first failure after native observation failed'
                Assert-Equal $true $partial.firstError.message.Contains('controlled native query failure') 'The underlying native error survives failed receipt I/O'
            }
            if ($mode -notin @('driver-and-receipt-error', 'receipt-only-error', 'native-and-receipt-error', 'diagnostics-cascade')) {
                $saved = Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json -AsHashtable
                Assert-Equal $code $saved.stepExitCode 'The final receipt retains the actual gate exit'
                Assert-Equal $(if ($mode -eq 'pass') { 'passed' } else { 'failed' }) $saved.status 'The receipt does not hide a failed run'
                if ($mode -eq 'driver-failure') { Assert-Equal 37 $saved.firstError.exitCode 'Original driver failure remains first'
                } elseif ($mode -eq 'observer-collect-error') {
                    Assert-Equal $true $saved.firstError.message.Contains('original observer') 'Snapshot fallback cannot erase original collection failure'
                } elseif ($mode -eq 'start-receipt-error') {
                    Assert-Equal 'controlled initial receipt write failure' $saved.firstError.message 'Missing report after skipped launch does not replace initial I/O failure'
                } elseif ($mode -eq 'partial-report') {
                    Assert-Equal '{ incomplete JSON' ([IO.File]::ReadAllText((Join-Path $directory 'windows-device-report.json'))) 'Malformed report raw bytes survive parsing failure'
                }
            }
        }
        Assert-Equal 'earlier port' $env:INSTALLED_PROBE_WINDOWS_PORT 'Original observer port environment is restored'
        Assert-Equal 'earlier campaign' $env:INSTALLED_PROBE_WINDOWS_CAMPAIGN 'Original campaign environment is restored'
        Assert-Equal 'earlier token' $env:INSTALLED_PROBE_WINDOWS_TOKEN 'Original token environment is restored'
        Remove-Module $module
    }
} finally {
    foreach ($name in $previousEnvironment.Keys) { [Environment]::SetEnvironmentVariable($name, $previousEnvironment[$name]) }
    Get-Module installed_plugin_windows_runner | Remove-Module
    Remove-Item -LiteralPath $temporary -Recurse -Force
}
Write-Host "Passed $script:assertions Windows runner transaction assertions (controlled command, reports and native adapter)."
exit 0
