#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not ('InstalledPluginProbe.ControlledProcessFactory' -as [type])) {
    Add-Type -Path @((Join-Path $PSScriptRoot 'installed_plugin_windows_lifetime.cs'),
        (Join-Path $PSScriptRoot 'test_installed_plugin_windows_lifetime.cs'))
}
$modulePath = Join-Path $PSScriptRoot 'installed_plugin_windows_control.psm1'
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('installed-control-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temporary | Out-Null
$previousCreation = [Environment]::GetEnvironmentVariable('INSTALLED_PROBE_TEST_CREATION')
$foreignId = 'control-suite-foreign-' + [guid]::NewGuid().ToString('N')
$timer = [Timers.Timer]::new(60000)
$script:assertions = 0
function Assert-Equal($Expected, $Actual, [string]$Message) {
    $script:assertions++
    if ($Expected -cne $Actual) { throw "$Message; expected=$Expected actual=$Actual" }
}
try {
    Register-ObjectEvent -InputObject $timer -EventName Elapsed -SourceIdentifier $foreignId | Out-Null
    New-Event -SourceIdentifier $foreignId | Out-Null
    foreach ($mode in @('pass', 'provider-unavailable', 'collection-error', 'child-exit-23',
        'partial-report', 'foreign-report-pid', 'oversized-report', 'script-path-collision',
        'receipt-path-error', 'partial-and-receipt-error', 'earlier-evidence')) {
        $directory = Join-Path $temporary $mode
        New-Item -ItemType Directory -Path $directory | Out-Null
        $module = Import-Module $modulePath -Force -PassThru
        & $module {
            param($Mode)
            $script:mode = $Mode; $script:observer = $null; $script:factory = $null
            $script:originalChild = (Get-Command New-InstalledPluginControlChildScript).ScriptBlock
            $script:originalStop = (Get-Command Stop-InstalledPluginLifetimeObserver).ScriptBlock
            function script:Start-InstalledPluginLifetimeObserver {
                param([string]$Executable, [string]$CampaignId, [string]$Token, [int]$StartupTimeoutMilliseconds)
                $script:factory = [InstalledPluginProbe.ControlledProcessFactory]::new()
                $script:factory.Executable = $Executable
                $script:observer = [InstalledPluginProbe.LifetimeObserver]::new(
                    $Executable, $CampaignId, $Token, $StartupTimeoutMilliseconds, $script:factory)
                $script:factory.Creation = $script:observer.ArmedAtUtc.ToFileTimeUtc() + 1
                $env:INSTALLED_PROBE_TEST_CREATION = $script:factory.Creation.ToString([Globalization.CultureInfo]::InvariantCulture)
                return $script:observer
            }
            function script:Stop-InstalledPluginLifetimeObserver {
                param($Observer)
                if ($script:mode -eq 'collection-error') { throw 'controlled original collection failure' }
                $trace = & $script:originalStop $Observer
                if ($script:mode -eq 'provider-unavailable') {
                    $trace.availability = 'unavailable'; $trace.errors = @('controlled native provider unavailable')
                }
                return $trace
            }
            function script:New-InstalledPluginControlChildScript {
                $source = & $script:originalChild
                $nativeIdentity = '$identity = [InstalledPluginProbe.WindowsProcess]::CurrentIdentity()'
                if (-not $source.Contains($nativeIdentity)) { throw 'The portable child must replace the exact native identity call.' }
                $source = $source.Replace($nativeIdentity, '$identity = @{ CreationFileTime = [long]$env:INSTALLED_PROBE_TEST_CREATION }')
                if ($script:mode -eq 'child-exit-23') { $source = $source.Replace('exit 37', 'exit 23') }
                if ($script:mode -eq 'foreign-report-pid') {
                    $source = $source.Replace('pid = $PID; runId = $runId; platform', 'pid = ($PID + 1); runId = $runId; platform')
                }
                $marker = '    $ack.Remove(''token'')'
                if ($script:mode -in @('partial-report', 'partial-and-receipt-error')) {
                    $source = $source.Replace($marker, $marker + [Environment]::NewLine +
                        '    [IO.File]::WriteAllText($args[1], ''{ partial JSON''); exit 37')
                }
                if ($script:mode -eq 'oversized-report') {
                    $source = $source.Replace($marker, $marker + [Environment]::NewLine +
                        '    [IO.File]::WriteAllText($args[1], (''x'' * 20000)); exit 37')
                }
                return $source
            }
        } $mode
        $reportPath = Join-Path $directory 'native-exit-control.json'
        if ($mode -eq 'script-path-collision') {
            [IO.File]::WriteAllText((Join-Path $directory 'native-control.ps1'), 'preserved earlier script')
        }
        if ($mode -in @('receipt-path-error', 'partial-and-receipt-error')) {
            $blocker = Join-Path $directory 'receipt-parent'
            [IO.File]::WriteAllText($blocker, 'preserved parent file')
            $reportPath = Join-Path $blocker 'native-exit-control.json'
        }
        if ($mode -eq 'earlier-evidence') { [IO.File]::WriteAllText($reportPath, 'preserved earlier receipt') }
        $caught = $null; $returned = $null
        $priorErrorWriter = [Console]::Error
        $captured = [IO.StringWriter]::new()
        try {
            [Console]::SetError($captured)
            try { $returned = Invoke-InstalledPluginExitControl -Directory $directory -ReportPath $reportPath }
            catch { $caught = $_ }
        } finally { [Console]::SetError($priorErrorWriter) }
        try {
            Assert-Equal $(if ($mode -eq 'pass') { $false } else { $true }) ($null -ne $caught) "$mode fails exactly when required"
            if ($mode -eq 'earlier-evidence') {
                Assert-Equal 'preserved earlier receipt' ([IO.File]::ReadAllText($reportPath)) 'Earlier evidence is immutable'
                Assert-Equal $null (& $module { $script:observer }) 'Receipt collisions precede observer acquisition'
            } else {
                if ($mode -in @('receipt-path-error', 'partial-and-receipt-error')) {
                    $saved = $captured.ToString().Trim() | ConvertFrom-Json -AsHashtable
                    Assert-Equal $true $saved.diagnosticFallback 'Failed receipt writes preserve bounded stderr evidence'
                    Assert-Equal $true ([Text.Encoding]::UTF8.GetByteCount($captured.ToString()) -le 256KB) 'Fallback stays bounded'
                    Assert-Equal 'preserved parent file' ([IO.File]::ReadAllText($blocker)) 'Failed writes preserve the colliding path'
                } else {
                    $saved = Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json -AsHashtable
                    Assert-Equal $true ((Get-Item -LiteralPath $reportPath).Length -le 256KB) 'The saved control evidence is bounded'
                }
                Assert-Equal $(if ($mode -eq 'pass') { 'passed' } else { 'failed' }) $saved.status 'The receipt retains failed controls'
                Assert-Equal $true $saved.cleanup.observerDisposed 'Observer cleanup runs independently of diagnostics'
                Assert-Equal 0 $saved.cleanup.subscriptionsRemaining.Count 'No control subscriptions remain'
                Assert-Equal 0 $saved.cleanup.eventsRemaining.Count 'No control events remain'
                Assert-Equal 0 $saved.cleanup.errors.Count 'Cleanup succeeds even when collection or receipt writes fail'
                if ($mode -eq 'script-path-collision') {
                    Assert-Equal $false $saved.child.started 'A script path collision never starts a child'
                    Assert-Equal 'preserved earlier script' ([IO.File]::ReadAllText((Join-Path $directory 'native-control.ps1'))) 'Earlier scripts are preserved'
                    Assert-Equal 0 (& $module { $script:factory.Opens }) 'A cancelled bootstrap never opens a foreign process'
                } else {
                    Assert-Equal $true $saved.child.started 'The control uses a real owned child'
                    Assert-Equal $true $saved.cleanup.childExited 'The owned child has exited before receipt I/O'
                    Assert-Equal $false $saved.child.terminatedByControl 'Normally completed controls do not require a kill'
                    Assert-Equal $(if ($mode -eq 'child-exit-23') { 23 } else { 37 }) $saved.child.exitCode 'The actual child exit survives diagnostic failures'
                    Assert-Equal 1 (& $module { $script:factory.Opens }) 'Only one exact process identity is opened'
                    Assert-Equal 1 (& $module { $script:factory.Disposals }) 'The retained handle is disposed once'
                    Assert-Equal $true $saved.trace.cleanup.handleClosed 'Partial traces retain completed handle cleanup'
                    Assert-Equal 'InstalledPluginProbe.ControlledProcessFactory' $saved.trace.nativeAdapter 'Portable tests identify their controlled native adapter'
                }
                if ($mode -eq 'pass') {
                    Assert-Equal 'passed' $returned.status 'The successful control returns its saved result'
                    Assert-Equal 'collected' $saved.observation.availability 'Successful controls collect the exact lifetime'
                    Assert-Equal 37 $saved.observation.exitStatus 'Observed retained exit matches actual child exit'
                    Assert-Equal $saved.child.pid $saved.observation.processId 'The acknowledged identity is the owned child'
                } elseif ($mode -eq 'collection-error') {
                    Assert-Equal 'controlled original collection failure' $saved.error.message 'Cleanup cannot replace the original collection failure'
                } elseif ($mode -eq 'provider-unavailable') {
                    Assert-Equal 'unavailable' $saved.observation.availability 'Missing native evidence cannot become success'
                    Assert-Equal 'controlled native provider unavailable' $saved.trace.errors[0] 'The provider cause remains visible'
                } elseif ($mode -in @('partial-report', 'partial-and-receipt-error')) {
                    Assert-Equal '{ partial JSON' $saved.childReportRaw 'Raw partial child report survives parsing and saving failures'
                    Assert-Equal $caught.Exception.Message $saved.error.message 'A later receipt failure does not replace the report failure'
                } elseif ($mode -eq 'foreign-report-pid') {
                    Assert-Equal $true $saved.error.message.Contains('does not belong to the owned child') 'Foreign reports are rejected'
                } elseif ($mode -eq 'oversized-report') {
                    Assert-Equal 20000 (Get-Item -LiteralPath (Join-Path $directory 'control-report.json')).Length 'Oversized original evidence remains intact'
                    Assert-Equal $null $saved.childReportRaw 'Oversized reports are not copied into bounded diagnostics'
                    Assert-Equal $true $saved.error.message.Contains('exceeds 16 KiB') 'Oversized reports fail explicitly'
                }
            }
            Assert-Equal 1 @(Get-EventSubscriber -SourceIdentifier $foreignId).Count 'Foreign subscriptions are untouched'
            Assert-Equal 1 @(Get-Event -SourceIdentifier $foreignId).Count 'Foreign queued events are untouched'
            Write-Host "Passed native control case: $mode"
        } finally {
            $captured.Dispose()
            Remove-Module $module
        }
    }
} finally {
    [Environment]::SetEnvironmentVariable('INSTALLED_PROBE_TEST_CREATION', $previousCreation)
    Unregister-Event -SourceIdentifier $foreignId -ErrorAction SilentlyContinue
    Get-Event -SourceIdentifier $foreignId -ErrorAction SilentlyContinue | Remove-Event -ErrorAction SilentlyContinue
    $timer.Dispose()
    Get-Module installed_plugin_windows_control | Remove-Module
    Remove-Item -LiteralPath $temporary -Recurse -Force
}
Write-Host "Passed $script:assertions control assertions (real owned child and TCP; controlled native process adapter)."
exit 0
