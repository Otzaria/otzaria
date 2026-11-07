#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'installed_plugin_windows_exit.psm1') -Force
$script:assertions = 0
function Assert-Equal($Expected, $Actual, [string]$Message) {
    $script:assertions++
    if ($Expected -cne $Actual) { throw "$Message; expected=$Expected actual=$Actual" }
}
$armed = ([datetime]'2026-11-06T18:00:00Z').ToUniversalTime()
$boot = $armed.AddSeconds(2)
$micros = [long](($boot.Ticks - [datetime]::UnixEpoch.Ticks) / 10)
function New-Report {
    return @{ pid = 42; runId = "42-$micros"; platform = 'windows'; buildMode = 'profile'; status = 'passed'; errors = @(); testFailures = @() }
}
function New-Trace {
    return @{
        processName = 'otzaria.exe'; availability = 'collected'; armedAtUtc = $armed; finishedAtUtc = $armed.AddSeconds(4)
        truncated = $false; errors = @(); events = @(
            @{ kind = 'Start'; processName = 'otzaria.exe'; processId = 42; parentProcessId = 7; sessionId = 1; utc = $armed.AddSeconds(1) },
            @{ kind = 'Stop'; processName = 'otzaria.exe'; processId = 42; parentProcessId = 7; sessionId = 1; utc = $armed.AddSeconds(3); exitStatus = [uint32]3221225477 }
        )
    }
}
$trace = New-Trace
$report = New-Report
$evidence = Get-InstalledPluginExitEvidence $trace $report
Assert-Equal 'collected' $evidence.availability 'A matching native process pair is collected'
Assert-Equal ([uint32]3221225477) $evidence.exitStatus 'The unsigned native exit status is retained'
Assert-Equal '0xC0000005' $evidence.exitStatusHex 'An NTSTATUS remains identifiable'
Assert-Equal 37 (Get-InstalledPluginRunExitCode 37 $null @{ availability = 'unavailable' }) 'Driver failure remains exact when all diagnostics fail'
Assert-Equal 37 (Get-InstalledPluginRunExitCode 37 $report $evidence) 'Native evidence cannot turn a failing driver green'
Assert-Equal 1 (Get-InstalledPluginRunExitCode $null $report $evidence) 'A missing driver result cannot pass'
Assert-Equal 1 (Get-InstalledPluginRunExitCode 0 $null $evidence) 'Driver success without a device report cannot pass'
Assert-Equal 1 (Get-InstalledPluginRunExitCode 0 $report @{ availability = 'unavailable' }) 'Missing process evidence cannot pass'
Assert-Equal 1 (Get-InstalledPluginRunExitCode 0 $report $evidence) 'A native exception status fails even if the driver and device report passed'
foreach ($status in @('running', 'failed', 'notRun')) {
    $report = New-Report; $report.status = $status
    Assert-Equal 1 (Get-InstalledPluginRunExitCode 0 $report $evidence) "A $status device report cannot pass"
}
foreach ($key in @('errors', 'testFailures')) {
    $report = New-Report; $report[$key] = @('actual failure')
    Assert-Equal 1 (Get-InstalledPluginRunExitCode 0 $report $evidence) "$key remain fatal"
    $report.Remove($key)
    Assert-Equal 1 (Get-InstalledPluginRunExitCode 0 $report $evidence) "Missing $key is not empty evidence"
}
foreach ($change in @(
    { param($t, $r) $t.events = @() },
    { param($t, $r) $t.events = @($t.events[0]) },
    { param($t, $r) $t.events = @($t.events[1]) },
    { param($t, $r) $t.events += $t.events[0].Clone() },
    { param($t, $r) $t.events += $t.events[1].Clone() },
    { param($t, $r) $t.events[1].parentProcessId = 8 },
    { param($t, $r) $t.events[1].sessionId = 2 },
    { param($t, $r) $t.events[1].utc = $armed.AddMilliseconds(500) },
    { param($t, $r) $t.events[1].processId = 99 },
    { param($t, $r) $t.events[1].processName = 'unrelated.exe' },
    { param($t, $r) $t.events[1].exitStatus = $null },
    { param($t, $r) $t.events[1].exitStatus = 1.5 },
    { param($t, $r) $t.truncated = $true },
    { param($t, $r) $t.errors = @('permission denied') },
    { param($t, $r) $t.availability = 'unavailable' },
    { param($t, $r) $r.pid = 99 },
    { param($t, $r) $r.pid = 42.5 },
    { param($t, $r) $r.platform = 'linux' },
    { param($t, $r) $r.buildMode = 'debug' },
    { param($t, $r) $r.runId = '42-invalid' },
    { param($t, $r) $t.armedAtUtc = $boot.AddSeconds(1) },
    { param($t, $r) $t.finishedAtUtc = $boot.AddSeconds(-1) },
    {
        param($t, $r)
        $t.events[1].exitStatus = 0
        $ended = $t.events[1].Clone()
        $ended.utc = $armed.AddMilliseconds(1500)
        $ended.exitStatus = [uint32]3221225477
        $t.events += $ended
    },
    {
        param($t, $r)
        $t.events[1].exitStatus = 0
        $conflict = $t.events[1].Clone()
        $conflict.parentProcessId = 8
        $conflict.exitStatus = [uint32]3221225477
        $t.events += $conflict
    },
    {
        param($t, $r)
        $t.events[1].exitStatus = 0
        $conflict = $t.events[1].Clone()
        $conflict.sessionId = 2
        $conflict.exitStatus = [uint32]3221225477
        $t.events += $conflict
    },
    {
        param($t, $r)
        $t.events[1].exitStatus = 0
        $ended = $t.events[1].Clone()
        $ended.utc = $armed.AddMilliseconds(1500)
        $next = $t.events[0].Clone()
        $next.utc = $armed.AddMilliseconds(1750)
        $t.events += @($ended, $next)
    },
    { param($t, $r) $next = $t.events[0].Clone(); $next.utc = $armed.AddSeconds(3.5); $t.events += $next }
)) {
    $trace = New-Trace; $report = New-Report; & $change $trace $report
    $rejected = Get-InstalledPluginExitEvidence $trace $report
    Assert-Equal 'unavailable' $rejected.availability "Missing, foreign, reused or invalid evidence: $change"
    Assert-Equal $null $rejected.exitStatus 'Unavailable exit evidence has no synthetic zero'
    Assert-Equal 1 (Get-InstalledPluginRunExitCode 0 $report $rejected) 'Rejected lifetime evidence cannot pass the wrapper'
}
foreach ($end in @($boot.AddTicks(-1), $boot)) {
    $trace = New-Trace
    $trace.events[1].utc = $end
    $trace.events[1].exitStatus = 0
    $rejected = Get-InstalledPluginExitEvidence $trace (New-Report)
    Assert-Equal 'unavailable' $rejected.availability 'A lifetime ending before or exactly at bootstrap cannot contain that bootstrap'
    Assert-Equal $null $rejected.exitStatus 'An ended lifetime cannot supply a later app exit status'
    Assert-Equal 1 (Get-InstalledPluginRunExitCode 0 (New-Report) $rejected) 'An ended lifetime cannot pass the wrapper'
}
$trace = New-Trace; $trace.events[1].exitStatus = 0
$trace.events[1].utc = $boot.AddTicks(1)
$justAfter = Get-InstalledPluginExitEvidence $trace (New-Report)
Assert-Equal 'collected' $justAfter.availability 'A unique lifetime that ends strictly after bootstrap remains observable'
Assert-Equal 0 (Get-InstalledPluginRunExitCode 0 (New-Report) $justAfter) 'The first timestamp after bootstrap is inside the accepted boundary'
$trace = New-Trace; $trace.events[1].exitStatus = 0
$zero = Get-InstalledPluginExitEvidence $trace (New-Report)
Assert-Equal 0 $zero.exitStatus 'An actually observed zero remains zero'
Assert-Equal 0 (Get-InstalledPluginRunExitCode 0 (New-Report) $zero) 'Driver, report and observed normal native exit can pass'
$trace.events[1].exitStatus = [uint32]::MaxValue
$teardown = Get-InstalledPluginExitEvidence $trace (New-Report)
Assert-Equal 0 (Get-InstalledPluginRunExitCode 0 (New-Report) $teardown) 'The pinned Dart Windows kill status is compatible with completed driver teardown'
Assert-Equal 1 (Get-InstalledPluginRunExitCode 0 (New-Report) $teardown @{ events = @(@{ exceptionCode = 'c0000005' }) }) 'A matching Application Error still fails an otherwise completed run'
foreach ($status in @(1, 37, [uint32]2147483648)) {
    $trace.events[1].exitStatus = $status
    Assert-Equal 1 (Get-InstalledPluginRunExitCode 0 (New-Report) (Get-InstalledPluginExitEvidence $trace (New-Report))) 'Other native exit statuses do not become success'
}
$trace.events += @{ kind = 'Start'; processName = 'otzaria.exe'; processId = 99; parentProcessId = 7; sessionId = 1; utc = $armed.AddSeconds(1) }
Assert-Equal 'collected' (Get-InstalledPluginExitEvidence $trace (New-Report)).availability 'An unrelated process cannot steal the observed app identity'

function New-ApplicationEvent([int]$AppPid = 42, [datetime]$Created = $armed.AddMilliseconds(900), [string]$AppName = 'otzaria.exe') {
    $createdHex = '0x{0:x}' -f $Created.ToFileTimeUtc()
    $processHex = '0x{0:x}' -f $AppPid
    return @"
<Event xmlns="http://schemas.microsoft.com/win/2004/08/events/event">
<System><Provider Name="Application Error"/><EventID>1000</EventID><Execution ProcessID="42"/><TimeCreated SystemTime="$($armed.AddSeconds(3).ToString('o'))"/></System>
<EventData><Data Name="AppName">$AppName</Data><Data Name="ProcessId">$processHex</Data><Data Name="ProcessCreationTime">$createdHex</Data>
<Data Name="AppPath">C:\probe\otzaria.exe</Data><Data Name="ModuleName">flutter_windows.dll</Data><Data Name="ExceptionCode">c0000005</Data></EventData></Event>
"@
}
$xml = [xml]('<Events>' + (New-ApplicationEvent) + (New-ApplicationEvent -AppPid 99) +
    (New-ApplicationEvent -Created $armed.AddSeconds(-1)) + (New-ApplicationEvent -Created $boot.AddSeconds(1)) +
    (New-ApplicationEvent -AppName 'foreign.exe') + '</Events>')
$events = @(Select-InstalledPluginApplicationErrors -Events $xml -Identity $evidence -ArmedAtUtc $armed -FinishedAtUtc $armed.AddSeconds(4))
Assert-Equal 1 $events.Count 'Application Error requires app PID, name, lifetime and report time, not the event writer PID'
Assert-Equal 'flutter_windows.dll' $events[0].moduleName 'The faulting module is preserved'
Assert-Equal 'c0000005' $events[0].exceptionCode 'The native exception code is preserved'
Assert-Equal 0 (@(Select-InstalledPluginApplicationErrors -Events $xml -Identity @{ processId = $null; bootstrapUtc = $null } `
    -ArmedAtUtc $armed -FinishedAtUtc $armed.AddSeconds(4))).Count 'Unidentified app processes cannot claim event log records'

$temporary = Join-Path ([IO.Path]::GetTempPath()) ('installed-exit-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temporary | Out-Null
try {
    $executable = Join-Path $PSHOME $(if ($IsWindows) { 'pwsh.exe' } else { 'pwsh' })
    $logPath = Join-Path $temporary 'driver.log'
    $code = Invoke-InstalledPluginLoggedCommand -Command $executable -LogPath $logPath `
        -Arguments @('-NoLogo', '-NoProfile', '-Command', "[Console]::Out.WriteLine('owned stdout'); [Console]::Error.WriteLine('owned stderr'); exit 37")
    Assert-Equal 37 $code 'The actual child exit code survives merged output capture'
    $log = Get-Content -LiteralPath $logPath -Raw
    Assert-Equal $true $log.Contains('owned stdout') 'Driver stdout is retained'
    Assert-Equal $true $log.Contains('owned stderr') 'Driver stderr is retained'

    if ($IsWindows) {
        $foreignId = 'foreign-test-' + [guid]::NewGuid().ToString('N')
        $timer = [Timers.Timer]::new(60000)
        Register-ObjectEvent -InputObject $timer -EventName Elapsed -SourceIdentifier $foreignId | Out-Null
        New-Event -SourceIdentifier $foreignId | Out-Null
        $nativeTrace = Start-InstalledPluginExitTrace -ProcessName 'pwsh.exe'
        $child = [Diagnostics.Process]::new()
        try {
            Assert-Equal 'armed' $nativeTrace.availability 'Both actual CIM subscriptions are ready before the controlled child starts'
            $controlPath = Join-Path $temporary 'native-control.ps1'
            @'
$microseconds = [long](([datetime]::UtcNow.Ticks - [datetime]::UnixEpoch.Ticks) / 10)
@{ pid = $PID; runId = "$PID-$microseconds"; platform = 'windows'; buildMode = 'profile' } |
    ConvertTo-Json | Set-Content -LiteralPath $args[0] -Encoding utf8
exit 37
'@ | Set-Content -LiteralPath $controlPath -Encoding utf8
            $controlReport = Join-Path $temporary 'control-report.json'
            $child.StartInfo = [Diagnostics.ProcessStartInfo]::new($executable)
            $child.StartInfo.UseShellExecute = $false
            foreach ($argument in @('-NoLogo', '-NoProfile', '-File', $controlPath, $controlReport)) { $child.StartInfo.ArgumentList.Add($argument) }
            Assert-Equal $true $child.Start() 'The native control owns its child process'
            Assert-Equal $true $child.WaitForExit(15000) 'The native control child is bounded'
            Assert-Equal 37 $child.ExitCode 'The native control exits with the requested status'
            Stop-InstalledPluginExitTrace $nativeTrace
            $observed = Get-InstalledPluginExitEvidence $nativeTrace (Get-Content -LiteralPath $controlReport -Raw | ConvertFrom-Json -AsHashtable)
            Assert-Equal 'collected' $observed.availability 'Real Windows process start and stop events identify the controlled child'
            Assert-Equal 37 $observed.exitStatus 'The kernel-reported exit status matches the child exit status'
            Assert-Equal 1 (@(Get-EventSubscriber -SourceIdentifier $foreignId)).Count 'Observer cleanup preserves foreign subscriptions'
            Assert-Equal 1 (@(Get-Event -SourceIdentifier $foreignId)).Count 'Observer cleanup preserves foreign queued events'
            foreach ($source in $nativeTrace.subscriptions.Values) {
                Assert-Equal 0 (@(Get-EventSubscriber -SourceIdentifier $source -ErrorAction SilentlyContinue)).Count 'Owned native subscriptions are removed'
            }
            Write-Host 'Native Windows event control: passed'
        } finally {
            if ($nativeTrace.availability -eq 'armed') { Stop-InstalledPluginExitTrace $nativeTrace }
            try { if ($child.Id -and -not $child.HasExited) { $child.Kill($true); [void]$child.WaitForExit(2000) } } catch { }
            $child.Dispose()
            Unregister-Event -SourceIdentifier $foreignId -ErrorAction SilentlyContinue
            Get-Event -SourceIdentifier $foreignId -ErrorAction SilentlyContinue | Remove-Event -ErrorAction SilentlyContinue
            $timer.Dispose()
        }
    } else {
        $missingProvider = Start-InstalledPluginExitTrace
        Stop-InstalledPluginExitTrace $missingProvider
        Assert-Equal 'unavailable' $missingProvider.availability 'An unavailable native provider remains unavailable'
        Assert-Equal $true ($missingProvider.errors.Count -gt 0) 'Observer initialization failure retains its reason'
        $missingQuery = Read-InstalledPluginApplicationErrors -Trace (New-Trace) -Identity $evidence
        Assert-Equal 'unavailable' $missingQuery.availability 'A missing event log tool is not a successful empty query'
        Assert-Equal 0 $missingQuery.events.Count 'No event log records are invented'
        Write-Host 'Native Windows event control: notRun (requires Windows CIM provider)'
    }
} finally { Remove-Item -LiteralPath $temporary -Recurse -Force }
Write-Host "Passed $script:assertions Windows exit evidence assertions."
exit 0
