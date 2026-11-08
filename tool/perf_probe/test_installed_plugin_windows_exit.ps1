#Requires -Version 7.0
param([string]$NativeControlReportPath)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'installed_plugin_windows_exit.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'installed_plugin_windows_control.psm1') -Force
$script:assertions = 0
function Assert-Equal($Expected, $Actual, [string]$Message) {
    $script:assertions++
    if ($Expected -cne $Actual) { throw "$Message; expected=$Expected actual=$Actual" }
}
$parseErrors = $null; $tokens = $null
$sourceAst = [Management.Automation.Language.Parser]::ParseFile(
    (Join-Path $PSScriptRoot 'installed_plugin_windows_exit.psm1'), [ref]$tokens, [ref]$parseErrors)
Assert-Equal 0 $parseErrors.Count 'The process observer source parses before its callback is exercised'
$subscription = $sourceAst.Find({ param($node)
    $node -is [Management.Automation.Language.CommandAst] -and $node.GetCommandName() -eq 'Register-CimIndicationEvent'
}, $true)
$actionIndex = 0
while ($subscription.CommandElements[$actionIndex] -isnot [Management.Automation.Language.CommandParameterAst] -or
    $subscription.CommandElements[$actionIndex].ParameterName -ne 'Action') { $actionIndex++ }
$callback = $subscription.CommandElements[$actionIndex + 1].ScriptBlock.GetScriptBlock()
function New-CallbackState {
    return @{
        records = [Collections.Concurrent.ConcurrentQueue[object]]::new()
        handles = [Collections.Concurrent.ConcurrentQueue[object]]::new()
        errors = [Collections.Concurrent.ConcurrentQueue[object]]::new(); jobs = @()
        signal = 'controlled-provider-' + [guid]::NewGuid().ToString('N')
    }
}
foreach ($kind in @('Start', 'Stop')) {
    $providerException = [InvalidOperationException]::new("Controlled $kind provider failure")
    $providerException | Add-Member -NotePropertyName NativeErrorCode -NotePropertyValue 'Failed'
    $providerException | Add-Member -NotePropertyName StatusCode -NotePropertyValue 1
    $providerException | Add-Member -NotePropertyName MessageId -NotePropertyValue 'HRESULT 0x80041001'
    $state = New-CallbackState
    $event = [pscustomobject]@{
        MessageData = @{ state = $state; kind = $kind }
        SourceEventArgs = [pscustomobject]@{ Exception = $providerException }
    }
    $beforeDelivery = [datetime]::UtcNow
    & $callback
    $failure = $state.errors.ToArray()[0]
    $actualMessage = if ($failure -is [string]) { $failure } else { $failure.error.message }
    Assert-Equal $providerException.Message $actualMessage 'Provider errors retain their original message instead of a missing ProcessName error'
    Assert-Equal $kind $failure.kind 'Provider errors identify the failing subscription, not the event the host was waiting for'
    Assert-Equal 'System.Management.Automation.PSCustomObject' $failure.eventArgsType 'The delivered argument type is retained'
    Assert-Equal $providerException.GetType().FullName $failure.providerException.type 'The original provider exception type is retained'
    Assert-Equal $providerException.HResult $failure.providerException.hresult 'The original provider HRESULT remains exact'
    Assert-Equal 'HRESULT 0x80041001' $failure.providerException.messageId 'The native provider message ID is retained'
    Assert-Equal 'Failed' $failure.providerException.nativeErrorCode 'The native provider error code is retained'
    Assert-Equal 1 $failure.providerException.statusCode 'The native provider status code is retained'
    Assert-Equal $true ($failure.receivedAtUtc -ge $beforeDelivery -and $failure.receivedAtUtc -le [datetime]::UtcNow) 'Receipt time does not substitute for native event time'
    Assert-Equal 0 $state.records.Count 'An exception indication never becomes a native process event'
    $failedTrace = @{
        availability = 'armed'; subscriptions = @{}; errors = [Collections.Generic.List[string]]::new()
        events = @(); eventErrors = @(); limitPerKind = 64; truncated = $false; finishedAtUtc = $null
    }
    & (Get-Module installed_plugin_windows_exit) { param($trace, $state) $script:traceStates.Add($trace, $state) } $failedTrace $state
    Stop-InstalledPluginExitTrace $failedTrace
    Assert-Equal 'unavailable' $failedTrace.availability 'A provider exception still invalidates native evidence'
    Assert-Equal $providerException.Message $failedTrace.errors[0] 'The original provider message survives observer cleanup'
    Assert-Equal $failure $failedTrace.eventErrors[0] 'Typed provider diagnostics survive observer cleanup'
}
foreach ($shape in @('valid-stop', 'missing-name', 'missing-event')) {
    $state = New-CallbackState
    $native = [pscustomobject]@{ ProcessName = 'otzaria.exe'; ProcessID = [uint32]42; ParentProcessID = [uint32]0
        SessionID = [uint32]0; TIME_CREATED = [datetime]::UtcNow.ToFileTimeUtc(); ExitStatus = [uint32]::MaxValue }
    if ($shape -eq 'missing-name') { $native.ProcessName = $null }
    $event = [pscustomobject]@{ MessageData = @{ state = $state; kind = 'Stop' }
        SourceEventArgs = [pscustomobject]@{ NewEvent = $(if ($shape -eq 'missing-event') { $null } else { $native }) } }
    try {
        & $callback
        if ($shape -eq 'valid-stop') {
            Assert-Equal 0 $state.errors.Count 'An ordinary native event is not mistaken for an exception indication'
            Assert-Equal 1 $state.records.Count 'One native stop event produces one scalar record'
            $native.ProcessName = 'changed.exe'; $native.ExitStatus = 37
            Assert-Equal 'otzaria.exe' $state.records.ToArray()[0].processName 'The process payload is copied before its event lifetime ends'
            Assert-Equal ([uint32]::MaxValue) $state.records.ToArray()[0].exitStatus 'The observed native exit status is copied without replacement'
        } else {
            Assert-Equal 0 $state.records.Count 'Missing native payload or name remains fatal'
            $failure = $state.errors.ToArray()[0]
            Assert-Equal $null $failure.providerException 'Malformed payload is distinguished from a provider exception'
            if ($shape -eq 'missing-name') {
                Assert-Equal 'Missing native process event field: ProcessName' $failure.error.message 'A genuinely missing name retains its own error'
                Assert-Equal 42 $failure.nativeEvent.ProcessID 'Available identity fields are retained for diagnosis, not accepted as success'
                Assert-Equal $null $failure.nativeEvent.ProcessName 'A missing name is never synthesized from the subscription filter'
            } else {
                Assert-Equal 'The native subscription delivered no process event.' $failure.error.message 'Absent payload is diagnosed independently'
            }
        }
    } finally { Get-Event -SourceIdentifier $state.signal -ErrorAction SilentlyContinue | Remove-Event }
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
            @{ kind = 'Start'; processName = 'otzaria.exe'; processId = 42; parentProcessId = 7; sessionId = 1; utc = $armed.AddSeconds(1)
                nativeIdentity = @{ availability = 'collected'; processId = 42; processName = 'otzaria.exe'; sessionId = 1
                    createdAtUtc = $armed.AddSeconds(1); capturedAtUtc = $armed.AddMilliseconds(1500)
                    exitedAtUtc = $armed.AddSeconds(3); exitStatus = [uint32]3221225477 } },
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
$delayed = New-Trace
$delayed.events[0].utc = $boot.AddMilliseconds(733)
$delayed.events[0].nativeIdentity.capturedAtUtc = $boot.AddMilliseconds(740)
$delayedEvidence = Get-InstalledPluginExitEvidence $delayed $report
Assert-Equal 'collected' $delayedEvidence.availability 'A delayed CIM start notification is accepted only with the retained process creation identity'
Assert-Equal $armed.AddSeconds(1) $delayedEvidence.processCreatedUtc 'Event generation time does not replace the actual native creation time'
$earlyStop = New-Trace
$earlyStop.events[1].utc = $boot.AddMilliseconds(900)
Assert-Equal 'collected' (Get-InstalledPluginExitEvidence $earlyStop $report).availability 'Stop notification generation need not follow the retained handle final ExitTime'

function New-ZeroStopTrace {
    return @{
        processName = 'pwsh.exe'; availability = 'collected'; truncated = $false; errors = @()
        armedAtUtc = ([datetime]'2026-11-07T20:15:07.3635818Z').ToUniversalTime()
        finishedAtUtc = ([datetime]'2026-11-07T20:15:09.8035653Z').ToUniversalTime()
        events = @(
            @{ kind = 'Start'; processName = 'pwsh.exe'; processId = 1280; parentProcessId = 5040; sessionId = 2
                utc = ([datetime]'2026-11-07T20:15:08.380313Z').ToUniversalTime()
                nativeIdentity = @{ availability = 'collected'; processId = 1280; processName = 'pwsh.exe'; sessionId = 2
                    createdAtUtc = ([datetime]'2026-11-07T20:15:07.3657007Z').ToUniversalTime()
                    capturedAtUtc = ([datetime]'2026-11-07T20:15:08.4264675Z').ToUniversalTime()
                    exitedAtUtc = ([datetime]'2026-11-07T20:15:08.4926266Z').ToUniversalTime(); exitStatus = 37 } },
            @{ kind = 'Stop'; processName = 'pwsh.exe'; processId = 1280; parentProcessId = 0; sessionId = 0
                utc = ([datetime]'2026-11-07T20:15:09.5822065Z').ToUniversalTime(); exitStatus = 37 }
        )
    }
}
$zeroStopReport = @{ pid = 1280; runId = '1280-1794082507650431'; platform = 'windows'; buildMode = 'profile' }
$zeroStop = New-ZeroStopTrace
$zeroStopEvidence = Get-InstalledPluginExitEvidence $zeroStop $zeroStopReport
Assert-Equal 'collected' $zeroStopEvidence.availability 'The real Windows control shape retains verified exit evidence when both stop auxiliary IDs are zero'
Assert-Equal 'collected' $evidence.stopAuxiliaryIdentity.availability 'Matching nonzero stop metadata remains observed'
Assert-Equal 37 $zeroStopEvidence.exitStatus 'Zero auxiliary metadata cannot replace the actual native exit status'
Assert-Equal 'unavailable' $zeroStopEvidence.stopAuxiliaryIdentity.availability 'Missing stop auxiliary metadata is explicitly unavailable'
Assert-Equal 0 $zeroStopEvidence.stop.parentProcessId 'The raw stop parent is not rewritten to the expected parent'
Assert-Equal 0 $zeroStopEvidence.stop.sessionId 'The raw stop session is not rewritten to the expected session'
Assert-Equal 2 $zeroStopEvidence.start.nativeIdentity.sessionId 'The retained handle still verifies the start session'
foreach ($change in @(
    { param($t) $t.events[0].Remove('nativeIdentity') },
    { param($t) $t.events[0].nativeIdentity.availability = 'captured' },
    { param($t) $t.events[0].nativeIdentity.sessionId = 3 },
    { param($t) $t.events[0].nativeIdentity.createdAtUtc = ([datetime]'2026-11-07T20:15:08Z').ToUniversalTime() },
    { param($t) $t.events[0].nativeIdentity.exitStatus = 0 },
    { param($t) $t.events[1].exitStatus = $null },
    { param($t) $t.events += $t.events[0].Clone() },
    { param($t) $t.events += $t.events[1].Clone() },
    { param($t) $old = $t.events[1].Clone(); $old.utc = $t.armedAtUtc; $t.events += $old },
    { param($t) $t.events[1].parentProcessId = 5040 },
    { param($t) $t.events[1].sessionId = 2 },
    { param($t) $t.events[1].parentProcessId = 5041; $t.events[1].sessionId = 2 },
    { param($t) $t.events[1].parentProcessId = 5040; $t.events[1].sessionId = 3 }
)) {
    $invalidZeroStop = New-ZeroStopTrace
    & $change $invalidZeroStop
    $rejected = Get-InstalledPluginExitEvidence $invalidZeroStop $zeroStopReport
    Assert-Equal 'unavailable' $rejected.availability "Zero stop metadata cannot hide a missing handle, reused PID or contradictory evidence: $change"
    Assert-Equal $null $rejected.exitStatus 'Rejected zero-metadata evidence has no synthetic success status'
}

Assert-Equal 37 (Get-InstalledPluginRunExitCode 37 $null @{ availability = 'unavailable' }) 'Driver failure remains exact when all diagnostics fail'
Assert-Equal 37 (Get-InstalledPluginRunExitCode 37 $report $evidence) 'Native evidence cannot turn a failing driver green'
$receiptDirectory = Join-Path ([IO.Path]::GetTempPath()) ('installed-receipt-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $receiptDirectory | Out-Null
try {
    foreach ($driverCode in @(0, 37)) {
        $receiptPath = Join-Path $receiptDirectory "$driverCode.json"
        Assert-Equal $driverCode (Save-InstalledPluginRunReceipt -Receipt @{} -Path $receiptPath -ExitCode $driverCode) 'Saving a receipt preserves the actual driver exit'
        $saved = Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json -AsHashtable
        Assert-Equal $driverCode $saved.stepExitCode 'The receipt records the actual exit code'
        Assert-Equal $(if ($driverCode -eq 0) { 'passed' } else { 'failed' }) $saved.status 'Receipt status follows the exit code'
        $missingParent = Join-Path $receiptDirectory 'absent/receipt.json'
        Assert-Equal $(if ($driverCode -eq 0) { 1 } else { $driverCode }) `
            (Save-InstalledPluginRunReceipt -Receipt @{} -Path $missingParent -ExitCode $driverCode) `
            'A real filesystem write error fails success and preserves the first driver failure'
        Assert-Equal $false (Test-Path -LiteralPath $missingParent) 'A failed write does not create successful evidence'
    }
} finally {
    Remove-Item -LiteralPath $receiptDirectory -Recurse -Force
}
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
    { param($t, $r) $t.events[0].Remove('nativeIdentity') },
    { param($t, $r) $t.events[0].nativeIdentity.availability = 'captured' },
    { param($t, $r) $t.events[0].nativeIdentity.createdAtUtc = $boot.AddTicks(1) },
    { param($t, $r) $t.events[0].nativeIdentity.createdAtUtc = $armed.AddTicks(-1) },
    { param($t, $r) $t.events[0].nativeIdentity.exitedAtUtc = $boot },
    { param($t, $r) $t.events[0].nativeIdentity.capturedAtUtc = $armed.AddSeconds(4) },
    { param($t, $r) $t.events[0].nativeIdentity.processId = 99 },
    { param($t, $r) $t.events[0].nativeIdentity.sessionId = 2 },
    { param($t, $r) $t.events[0].nativeIdentity.processName = 'foreign.exe' },
    { param($t, $r) $t.events[0].nativeIdentity.exitStatus = $null },
    { param($t, $r) $t.events[0].nativeIdentity.exitStatus = 0 },
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
$trace.events[0].nativeIdentity.exitStatus = 0
$trace.events[0].nativeIdentity.exitedAtUtc = $boot.AddTicks(1)
$trace.events[1].utc = $boot.AddTicks(1)
$justAfter = Get-InstalledPluginExitEvidence $trace (New-Report)
Assert-Equal 'collected' $justAfter.availability 'A unique lifetime that ends strictly after bootstrap remains observable'
Assert-Equal 0 (Get-InstalledPluginRunExitCode 0 (New-Report) $justAfter) 'The first timestamp after bootstrap is inside the accepted boundary'
$trace = New-Trace; $trace.events[1].exitStatus = 0
$trace.events[0].nativeIdentity.exitStatus = 0
$zero = Get-InstalledPluginExitEvidence $trace (New-Report)
Assert-Equal 0 $zero.exitStatus 'An actually observed zero remains zero'
Assert-Equal 0 (Get-InstalledPluginRunExitCode 0 (New-Report) $zero) 'Driver, report and observed normal native exit can pass'
$trace.events[1].exitStatus = [uint32]::MaxValue
$trace.events[0].nativeIdentity.exitStatus = [uint32]::MaxValue
$teardown = Get-InstalledPluginExitEvidence $trace (New-Report)
Assert-Equal 0 (Get-InstalledPluginRunExitCode 0 (New-Report) $teardown) 'The pinned Dart Windows kill status is compatible with completed driver teardown'
Assert-Equal 1 (Get-InstalledPluginRunExitCode 0 (New-Report) $teardown @{ events = @(@{ exceptionCode = 'c0000005' }) }) 'A matching Application Error still fails an otherwise completed run'
foreach ($status in @(1, 37, [uint32]2147483648)) {
    $trace.events[1].exitStatus = $status
    $trace.events[0].nativeIdentity.exitStatus = $status
    Assert-Equal 1 (Get-InstalledPluginRunExitCode 0 (New-Report) (Get-InstalledPluginExitEvidence $trace (New-Report))) 'Other native exit statuses do not become success'
}
$trace.events += @{ kind = 'Start'; processName = 'otzaria.exe'; processId = 99; parentProcessId = 7; sessionId = 1; utc = $armed.AddSeconds(1) }
Assert-Equal 'collected' (Get-InstalledPluginExitEvidence $trace (New-Report)).availability 'An unrelated process cannot steal the observed app identity'

function New-ApplicationEvent([int]$AppPid = 42, [datetime]$Created = $armed.AddSeconds(1), [string]$AppName = 'otzaria.exe') {
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
    (New-ApplicationEvent -Created $armed.AddMilliseconds(900)) + (New-ApplicationEvent -Created $armed.AddSeconds(-1)) + (New-ApplicationEvent -Created $boot.AddSeconds(1)) +
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

    # Flutter on Windows provides both flutter.bat and flutter. Application
    # discovery can return both; invoking the array joins their names together.
    $lookup = Join-Path $temporary 'command lookup with spaces'
    $firstDirectory = Join-Path $lookup 'first'
    $secondDirectory = Join-Path $lookup 'second'
    New-Item -ItemType Directory -Path $firstDirectory, $secondDirectory | Out-Null
    $commandName = 'installed-probe-driver-' + [guid]::NewGuid().ToString('N')
    if ($IsWindows) {
        $firstPath = Join-Path $firstDirectory "$commandName.bat"
        Set-Content -LiteralPath $firstPath -Encoding ascii -Value "@echo off`r`necho selected stdout`r`necho selected stderr 1>&2`r`nexit /b 37"
        Set-Content -LiteralPath (Join-Path $firstDirectory $commandName) -Encoding ascii -Value '#!/bin/sh'
    } else {
        $firstPath = Join-Path $firstDirectory $commandName
        $secondPath = Join-Path $secondDirectory $commandName
        Set-Content -LiteralPath $firstPath -Encoding ascii -Value "#!/bin/sh`necho selected stdout`necho selected stderr >&2`nexit 37"
        Set-Content -LiteralPath $secondPath -Encoding ascii -Value "#!/bin/sh`necho unselected driver`nexit 99"
        $mode = [IO.UnixFileMode]::UserRead -bor [IO.UnixFileMode]::UserWrite -bor [IO.UnixFileMode]::UserExecute
        [IO.File]::SetUnixFileMode($firstPath, $mode)
        [IO.File]::SetUnixFileMode($secondPath, $mode)
    }
    $priorPath = $env:PATH
    try {
        $env:PATH = (@($firstDirectory, $secondDirectory, $priorPath) -join [IO.Path]::PathSeparator)
        $matches = @(Get-Command $commandName -CommandType Application -ErrorAction Stop)
        Assert-Equal 2 $matches.Count 'The fixture reproduces multiple native application matches'
        Assert-Equal $firstPath $matches[0].Path 'The first match has ordinary PowerShell execution precedence'
        $lookupLogPath = Join-Path $temporary 'lookup-driver.log'
        $code = Invoke-InstalledPluginLoggedCommand -Command $commandName -LogPath $lookupLogPath
        Assert-Equal 37 $code 'A bare command selects one application and preserves its native exit code'
        $lookupLog = Get-Content -LiteralPath $lookupLogPath -Raw
        Assert-Equal $true $lookupLog.Contains('selected stdout') 'Selected driver stdout is retained'
        Assert-Equal $true $lookupLog.Contains('selected stderr') 'Selected driver stderr is retained'
        Assert-Equal $false $lookupLog.Contains('unselected driver') 'Later application matches are not executed'
    } finally { $env:PATH = $priorPath }

    if ($IsWindows) {
        if (-not $NativeControlReportPath) {
            $NativeControlReportPath = Join-Path ([IO.Path]::GetTempPath()) ('installed-native-control-' + [guid]::NewGuid().ToString('N') + '.json')
        }
        $native = Invoke-InstalledPluginExitControl -Directory $temporary -ReportPath $NativeControlReportPath
        Assert-Equal 'passed' $native.status 'The real Windows process control completed'
        Write-Host "Native Windows event control: passed; evidence: $NativeControlReportPath"
        function Assert-HeldNativeChild($Result) {
            Assert-Equal $true $Result.child.started 'The idle control actually started its owned child'
            Assert-Equal $true $Result.child.exited 'The idle control child exited'
            Assert-Equal $false $Result.child.terminatedByControl 'The child was not killed to manufacture completion'
            Assert-Equal 37 $Result.child.exitCode 'The owned child retains its explicit exit37'
            Assert-Equal 35 $Result.idle.requestedSeconds 'The control spans more than the old15-second response budget'
            Assert-Equal $true ($Result.idle.elapsedMs -ge 35000) 'The controlled idle duration is measured with a monotonic clock'
            Assert-Equal $Result.child.pid $Result.childReport.pid 'The report belongs to the held child'
            $starts = @($Result.trace.events | Where-Object { $_.kind -eq 'Start' -and $_.processId -eq $Result.child.pid })
            Assert-Equal 1 $starts.Count 'Exactly one start belongs to the held child'
            $held = $starts[0].nativeIdentity
            Assert-Equal 'collected' $held.availability 'A live-captured native handle supplies the actual lifetime'
            Assert-Equal $Result.child.pid $held.processId 'The retained handle identifies the owned child'
            Assert-Equal $Result.child.createdAtUtc $held.createdAtUtc 'The controlled and observed creation times agree exactly'
            Assert-Equal $Result.child.exitedAtUtc $held.exitedAtUtc 'The controlled and observed exit times agree exactly'
            Assert-Equal 37 $held.exitStatus 'The retained handle independently observes exit37'
            Assert-Equal $true ([datetime]$Result.idle.startedAtUtc -ge [datetime]$held.capturedAtUtc) 'Idling begins after the native handle was captured'
            Assert-Equal $true ([datetime]$held.exitedAtUtc -ge [datetime]$Result.idle.finishedAtUtc) 'The held process remains alive for the whole idle period'
            Assert-Equal 0 $Result.cleanup.errors.Count 'No cleanup failure is accepted as a timeout regression'
            Assert-Equal 0 $Result.cleanup.subscriptionsRemaining.Count 'Every owned subscription is removed'
            Assert-Equal 0 $Result.cleanup.eventsRemaining.Count 'Every owned queued event is removed'
        }
        $timeoutDirectory = Join-Path $temporary 'native-timeout'
        New-Item -ItemType Directory -Path $timeoutDirectory | Out-Null
        $timeoutReportPath = [IO.Path]::ChangeExtension($NativeControlReportPath, 'timeout.json')
        $expectedTimeout = $null
        try {
            Invoke-InstalledPluginExitControl -Directory $timeoutDirectory -ReportPath $timeoutReportPath `
                -IdleSeconds 35 -SubscriptionTimeoutSeconds 15 | Out-Null
        } catch { $expectedTimeout = $_ }
        Assert-Equal $true ($null -ne $expectedTimeout) 'The legacy subscription budget must fail after an idle child was identified'
        $timeoutControl = Get-Content -LiteralPath $timeoutReportPath -Raw | ConvertFrom-Json -AsHashtable
        Assert-HeldNativeChild $timeoutControl
        Assert-Equal 'failed' $timeoutControl.status 'The legacy response timeout remains a failed control'
        Assert-Equal 'observe' $timeoutControl.stage 'Bootstrap failures do not count as reproducing the native timeout'
        Assert-Equal 15 $timeoutControl.trace.subscriptionTimeoutSeconds 'The negative control uses the original response budget'
        Assert-Equal 'unavailable' $timeoutControl.observation.availability 'A timeout cannot supply native exit evidence'
        Assert-Equal $null $timeoutControl.observation.exitStatus 'Unavailable evidence has no manufactured exit status'
        Assert-Equal 1 $timeoutControl.trace.eventErrors.Count 'Only the expected provider indication may fail'
        $timeoutEvent = $timeoutControl.trace.eventErrors[0]
        Assert-Equal 'Start' $timeoutEvent.kind 'The legacy response timeout belongs to the Start subscription'
        Assert-Equal 'Microsoft.Management.Infrastructure.CimCmdlets.CimIndicationEventExceptionEventArgs' $timeoutEvent.eventArgsType 'The provider delivered an exception indication'
        Assert-Equal 'Microsoft.Management.Infrastructure.CimException' $timeoutEvent.providerException.type 'The original CIM exception type remains visible'
        Assert-Equal 'HRESULT 0x40004' $timeoutEvent.providerException.MessageId 'Only WBEM_S_TIMEDOUT reproduces the observed failure'
        $unexpectedErrors = @($timeoutControl.trace.errors | Where-Object {
            $_ -ne $timeoutEvent.error.message -and $_ -ne 'The process observer failed while waiting for delivery.'
        })
        Assert-Equal 0 $unexpectedErrors.Count 'Unrelated observation failures cannot satisfy the negative control'
        Write-Host "Native Windows legacy response timeout: expected Start WBEM_S_TIMEDOUT; evidence: $timeoutReportPath"
        $idleDirectory = Join-Path $temporary 'native-idle'
        New-Item -ItemType Directory -Path $idleDirectory | Out-Null
        $idleReportPath = [IO.Path]::ChangeExtension($NativeControlReportPath, 'idle.json')
        $idleControl = Invoke-InstalledPluginExitControl -Directory $idleDirectory -ReportPath $idleReportPath -IdleSeconds 35
        Assert-HeldNativeChild $idleControl
        Assert-Equal 'passed' $idleControl.status 'The workflow-sized subscription budget survives the same idle period'
        Assert-Equal 3600 $idleControl.trace.subscriptionTimeoutSeconds 'The production response budget covers the60-minute workflow'
        Assert-Equal 37 $idleControl.observation.exitStatus 'The long-lived subscription still requires the actual native exit37'
        Assert-Equal 0 $idleControl.trace.eventErrors.Count 'No provider error is ignored in the successful idle control'
        Write-Host "Native Windows idle control: passed; evidence: $idleReportPath"
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
