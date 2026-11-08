#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$modulePath = Join-Path $PSScriptRoot 'installed_plugin_windows_control.psm1'
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('installed-control-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temporary | Out-Null
$script:assertions = 0
function Assert-Equal($Expected, $Actual, [string]$Message) {
    $script:assertions++
    if ($Expected -cne $Actual) { throw "$Message; expected=$Expected actual=$Actual" }
}

try {
    $timingModule = Import-Module $modulePath -Force -PassThru
    try {
        $timingResults = & $timingModule {
            function script:Start-Sleep {
                param([int]$Milliseconds)
                if ($Milliseconds -le 0) { throw 'The idle deadline must not busy-wait.' }
                $script:idleSleepRequests.Add($Milliseconds)
                if ($script:idleWakeTimes.Count -eq 0) { throw 'The control slept after its deadline.' }
                $script:idleClock.Elapsed.TotalMilliseconds = $script:idleWakeTimes.Dequeue()
            }
            foreach ($idleCase in @(
                @{ name = 'zero'; seconds = 0; wakes = @(); expected = '' },
                @{ name = 'early'; seconds = 1; wakes = @(984.5, 999.75, 1000.125); expected = '1000,16,1' },
                @{ name = 'overshoot'; seconds = 1; wakes = @(1040.0); expected = '1000' },
                @{ name = 'native-idle'; seconds = 35; wakes = @(34999.5, 35000.25); expected = '35000,1' }
            )) {
                $script:idleClock = @{ Elapsed = @{ TotalMilliseconds = 0.0 } }
                $script:idleSleepRequests = [Collections.Generic.List[int]]::new()
                $script:idleWakeTimes = [Collections.Generic.Queue[double]]::new()
                foreach ($wake in $idleCase.wakes) { $script:idleWakeTimes.Enqueue($wake) }
                Wait-InstalledPluginControlIdle -Clock $script:idleClock -Seconds $idleCase.seconds
                @{
                    name = $idleCase.name; seconds = $idleCase.seconds; expected = $idleCase.expected
                    requests = $script:idleSleepRequests -join ','; elapsedMs = $script:idleClock.Elapsed.TotalMilliseconds
                    remainingWakes = $script:idleWakeTimes.Count
                }
            }
        }
    } finally { Remove-Module $timingModule }
    foreach ($timing in $timingResults) {
        Assert-Equal $timing.expected $timing.requests "The $($timing.name) deadline waits only for the rounded-up remainder"
        Assert-Equal $true ($timing.elapsedMs -ge $timing.seconds * 1000) "The $($timing.name) deadline cannot release its child early"
        Assert-Equal 0 $timing.remainingWakes "The $($timing.name) deadline consumes every early wake"
    }
    foreach ($mode in @('pass', 'idle', 'missing-stop', 'provider-error', 'throw-stop', 'invalid-report', 'foreign-report', 'startup-error', 'cleanup-failure', 'oversized', 'save-error', 'primary-and-save-error')) {
        $directory = Join-Path $temporary $mode
        New-Item -ItemType Directory -Path $directory | Out-Null
        $reportPath = Join-Path $temporary "$mode.json"
        if ($mode -in @('save-error', 'primary-and-save-error')) { $reportPath = Join-Path $directory 'absent/report.json' }
        $module = Import-Module $modulePath -Force -PassThru
        & $module {
            param($Mode, $Directory)
            $script:controlMode = $Mode
            $script:controlDirectory = $Directory
            $script:ownedTimers = @()
            $script:childIdentity = $null
            $script:controlProcessTimes = @{}
            function script:Start-InstalledPluginExitTrace {
                param([string]$ProcessName, [uint32]$SubscriptionTimeoutSeconds)
                $trace = @{
                    source = 'Controlled portable provider, not native CIM'; processName = $ProcessName
                    availability = 'armed'; armedAtUtc = [datetime]::UtcNow; finishedAtUtc = $null
                    subscriptionTimeoutSeconds = $SubscriptionTimeoutSeconds
                    subscriptions = @{}; events = @(); errors = @(); limitPerKind = 64; truncated = $false
                }
                foreach ($kind in @('Start', 'Stop')) {
                    $id = 'controlled-' + [guid]::NewGuid().ToString('N')
                    $timer = [Timers.Timer]::new(60000)
                    $script:ownedTimers += $timer
                    Register-ObjectEvent -InputObject $timer -EventName Elapsed -SourceIdentifier $id | Out-Null
                    New-Event -SourceIdentifier $id | Out-Null
                    $trace.subscriptions[$kind] = $id
                }
                if ($script:controlMode -eq 'startup-error') {
                    $trace.availability = 'unavailable'; $trace.errors = @('controlled subscription failure')
                }
                return $trace
            }
            function script:Read-InstalledPluginControlProcessTime {
                param($Process, [string]$Property)
                # The portable provider supplies identity times; real CIM verifies native times on Windows.
                $script:controlProcessTimes[$Property] = [datetime]::UtcNow
                return $script:controlProcessTimes[$Property]
            }
            function script:Wait-InstalledPluginProcessEvent {
                param([hashtable]$Trace, [string]$Kind, [int]$ProcessId)
                if ($Kind -ne 'Start') { throw 'The control must acknowledge startup before releasing the child.' }
                $script:childIdentity = @{
                    availability = 'captured'; processId = $ProcessId; processName = $Trace.processName; sessionId = 1
                    createdAtUtc = $script:controlProcessTimes.StartTime; capturedAtUtc = [datetime]::UtcNow
                    exitedAtUtc = $null; exitStatus = $null
                }
            }
            function script:Stop-InstalledPluginExitTrace {
                param([hashtable]$Trace, [Nullable[int]]$ProcessId)
                if ($script:controlMode -eq 'throw-stop') { throw [IO.IOException]::new('controlled original stop failure') }
                $reportPath = Join-Path $script:controlDirectory 'control-report.json'
                $report = Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json -AsHashtable
                if ($script:controlMode -eq 'foreign-report') {
                    $report.pid += 999999
                    $report.runId = "$($report.pid)-$($report.runId.Split('-')[1])"
                    $report | ConvertTo-Json | Set-Content -LiteralPath $reportPath
                }
                $script:childIdentity.exitedAtUtc = $script:controlProcessTimes.ExitTime
                $script:childIdentity.exitStatus = 37
                $script:childIdentity.availability = 'collected'
                $Trace.finishedAtUtc = [datetime]::UtcNow
                $Trace.events = @(
                    @{ kind = 'Start'; processName = $Trace.processName; processId = $report.pid; parentProcessId = $PID; sessionId = 1; utc = $script:childIdentity.capturedAtUtc; nativeIdentity = $script:childIdentity },
                    @{ kind = 'Stop'; processName = $Trace.processName; processId = $report.pid; parentProcessId = $PID; sessionId = 1; utc = $Trace.finishedAtUtc; exitStatus = [uint32]37 }
                )
                $Trace.availability = 'collected'
                if ($script:controlMode -eq 'missing-stop') { $Trace.events = @($Trace.events[0]) }
                if ($script:controlMode -in @('provider-error', 'primary-and-save-error')) {
                    $Trace.availability = 'unavailable'; $Trace.errors = @('controlled provider field failure')
                }
                if ($script:controlMode -eq 'invalid-report') { '{ incomplete JSON' | Set-Content -LiteralPath $reportPath }
                if ($script:controlMode -eq 'oversized') {
                    $Trace.availability = 'unavailable'; $Trace.errors = @('א' * 150000)
                }
                foreach ($source in $Trace.subscriptions.Values) {
                    Microsoft.PowerShell.Utility\Unregister-Event -SourceIdentifier $source -ErrorAction SilentlyContinue
                    Get-Event -SourceIdentifier $source -ErrorAction SilentlyContinue | Remove-Event -ErrorAction SilentlyContinue
                }
            }
            function script:Unregister-Event {
                param([string]$SourceIdentifier, $ErrorAction)
                if ($script:controlMode -eq 'cleanup-failure' -and $SourceIdentifier.StartsWith('foreign-test-')) { return }
                Microsoft.PowerShell.Utility\Unregister-Event -SourceIdentifier $SourceIdentifier -ErrorAction SilentlyContinue
            }
        } $mode $directory
        $caught = $null
        $controlOptions = @{ Directory = $directory; ReportPath = $reportPath }
        if ($mode -eq 'idle') { $controlOptions.IdleSeconds = 1; $controlOptions.SubscriptionTimeoutSeconds = 30 }
        try { Invoke-InstalledPluginExitControl @controlOptions | Out-Null }
        catch { $caught = $_ }
        if ($mode -in @('save-error', 'primary-and-save-error')) {
            Assert-Equal $true ($null -ne $caught) 'A report write failure cannot pass the control'
            Assert-Equal $false (Test-Path -LiteralPath $reportPath) 'A failed write does not invent a report'
            Assert-Equal $($mode -eq 'primary-and-save-error') ($caught.Exception.Message.Contains('Process observations are unavailable')) 'A secondary write failure preserves the first observation failure'
            Assert-Equal 0 (@(Get-EventSubscriber)).Count 'A report write failure does not leave owned subscriptions'
            Assert-Equal 0 (@(Get-Event)).Count 'A report write failure does not leave owned queued events'
        } else {
            $saved = Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json -AsHashtable
            Assert-Equal $true ((Get-Item -LiteralPath $reportPath).Length -le 256KB) 'The saved control evidence is bounded'
            if ($mode -in @('pass', 'idle')) {
                Assert-Equal $null $caught 'A fully observed child succeeds'
                Assert-Equal 'passed' $saved.status 'The successful control report is saved'
                Assert-Equal 37 $saved.observation.exitStatus 'The observed exit status is preserved'
                Assert-Equal $saved.child.pid $saved.childReport.pid 'The report identifies the owned child'
                if ($mode -eq 'idle') {
                    Assert-Equal 30 $saved.trace.subscriptionTimeoutSeconds 'The subscription response budget is forwarded independently of delivery waits'
                    Assert-Equal $true ($saved.idle.elapsedMs -ge 1000) 'The controlled child stays alive through the requested idle period'
                    Assert-Equal $true ([datetime]$saved.idle.startedAtUtc -ge [datetime]$saved.observation.start.nativeIdentity.capturedAtUtc) 'Idling starts only after the native handle has been captured'
                    Assert-Equal $false $saved.child.terminatedByControl 'The idled child still exits with its own status37'
                }
            } else {
                Assert-Equal $true ($null -ne $caught) "The $mode control still fails after saving"
                Assert-Equal 'failed' $saved.status 'A failed control never becomes a passed report'
            }
            if ($mode -eq 'oversized') {
                Assert-Equal $true $saved.diagnosticTruncated 'An oversized report is explicit and remains failure'
                Assert-Equal $true ($caught.Exception.Message.Contains('Process observations are unavailable')) 'A save limit cannot replace the original observation failure'
                Assert-Equal 37 $saved.child.exitCode 'A bounded fallback retains the actual child exit'
                Assert-Equal $saved.child.pid $saved.childReport.pid 'A bounded fallback retains the owned identity'
                Assert-Equal 'unavailable' $saved.observation.availability 'A bounded fallback retains the observation result'
                Assert-Equal 2 $saved.trace.events.Count 'A bounded fallback retains partial trace records'
                Assert-Equal 1024 $saved.trace.errors[0].Length 'A bounded fallback truncates the provider error explicitly'
                Assert-Equal 0 $saved.cleanup.errors.Count 'A bounded fallback retains cleanup outcomes'
            } else {
                Assert-Equal $(if ($mode -eq 'throw-stop') { 1 } else { 0 }) $saved.cleanup.errors.Count 'Cleanup retains a stop exception without inventing other errors'
                if ($mode -ne 'startup-error') {
                    Assert-Equal 37 $saved.child.exitCode 'A diagnostic failure preserves the actual child exit code'
                    Assert-Equal $true $saved.cleanup.childExited 'The owned child is drained'
                    Assert-Equal $true ($saved.childReportRaw.Length -gt 0) 'The raw or partial child report survives the failure'
                } else {
                    Assert-Equal $false $saved.child.started 'A subscription failure never starts a child'
                    Assert-Equal $null $saved.child.exitCode 'No exit status is invented for an unstarted child'
                    Assert-Equal 'controlled subscription failure' $saved.trace.errors[0] 'The provider setup error is retained'
                }
                if ($mode -eq 'cleanup-failure') {
                    Assert-Equal 1 $saved.cleanup.subscriptionsRemaining.Count 'An owned subscription leak is retained'
                    Assert-Equal $true ($caught.Exception.Message.Contains('cleanup did not complete')) 'Cleanup failure cannot pass a successful observation'
                } else {
                    Assert-Equal 0 $saved.cleanup.subscriptionsRemaining.Count 'Owned subscriptions were removed'
                    Assert-Equal 0 $saved.cleanup.eventsRemaining.Count 'Owned queued events were removed'
                }
            }
            if ($mode -eq 'missing-stop') {
                Assert-Equal 'unavailable' $saved.observation.availability 'Unavailable matching is retained'
                Assert-Equal $true ($saved.observation.reason.Contains('unique matching stop')) 'The matcher reason is retained'
                Assert-Equal 1 $saved.trace.events.Count 'Partial observed events are retained'
            }
            if ($mode -eq 'provider-error') { Assert-Equal 'controlled provider field failure' $saved.trace.errors[0] 'Raw provider failures remain visible' }
            if ($mode -eq 'throw-stop') {
                Assert-Equal 'controlled original stop failure' $saved.error.message 'The original thrown failure is retained'
                Assert-Equal 'controlled original stop failure' $caught.Exception.Message 'Cleanup cannot replace the first failure'
            }
            if ($mode -eq 'foreign-report') { Assert-Equal $true ($saved.error.message.Contains('owned child')) 'A report from another child cannot pass' }
            if ($mode -eq 'invalid-report') { Assert-Equal $true ($saved.childReportRaw.Contains('incomplete JSON')) 'Invalid JSON remains available without a synthetic parsed report' }
        }
        & $module {
            foreach ($timer in $script:ownedTimers) { $timer.Dispose() }
        }
        Get-EventSubscriber | Where-Object { $_.SourceIdentifier.StartsWith('foreign-test-') } |
            Microsoft.PowerShell.Utility\Unregister-Event
        Get-Event | Where-Object { $_.SourceIdentifier.StartsWith('foreign-test-') } | Remove-Event
        Remove-Module $module
    }
} finally {
    Get-Module installed_plugin_windows_control | Remove-Module
    Remove-Item -LiteralPath $temporary -Recurse -Force
}
Write-Host "Passed $script:assertions portable native-control report assertions; actual CIM is tested separately on Windows."
exit 0
