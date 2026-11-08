#Requires -Version 7.0
Set-StrictMode -Version Latest

$script:traceStates = [Runtime.CompilerServices.ConditionalWeakTable[hashtable, object]]::new()

function Start-InstalledPluginExitTrace {
    param([ValidatePattern('^[A-Za-z0-9_.-]+\.exe$')][string]$ProcessName = 'otzaria.exe',
        [ValidateRange(1, 3600)][uint32]$SubscriptionTimeoutSeconds = 3600)
    $trace = @{
        source = 'Win32_ProcessStartTrace / Win32_ProcessStopTrace with retained native process handle'
        processName = $ProcessName; availability = 'unavailable'; subscriptionTimeoutSeconds = $SubscriptionTimeoutSeconds
        armedAtUtc = [datetime]::UtcNow; finishedAtUtc = $null
        subscriptions = @{}; events = @(); eventErrors = @(); errors = [Collections.Generic.List[string]]::new()
        limitPerKind = 64; truncated = $false
    }
    $state = @{
        records = [Collections.Concurrent.ConcurrentQueue[object]]::new()
        handles = [Collections.Concurrent.ConcurrentQueue[object]]::new()
        errors = [Collections.Concurrent.ConcurrentQueue[object]]::new()
        jobs = [Collections.Generic.List[object]]::new()
        signal = 'installed-plugin-delivered-' + [guid]::NewGuid().ToString('N')
    }
    $script:traceStates.Add($trace, $state)
    try {
        foreach ($kind in @('Start', 'Stop')) {
            $source = 'installed-plugin-' + [guid]::NewGuid().ToString('N')
            $trace.subscriptions[$kind] = $source
            # Cover the 60-minute workflow between subscription responses;
            # the separate wait for a delivered process event remains 15 seconds.
            $job = Register-CimIndicationEvent -Namespace root/cimv2 `
                -Query "SELECT * FROM Win32_Process${kind}Trace WHERE ProcessName='$ProcessName'" `
                -SourceIdentifier $source -OperationTimeoutSec $SubscriptionTimeoutSeconds -MaxTriggerCount 65 -ErrorAction Stop `
                -MessageData @{ state = $state; kind = $kind } -Action {
                    $state = $event.MessageData.state
                    $process = $null
                    $delivery = @{
                        kind = $event.MessageData.kind; receivedAtUtc = [datetime]::UtcNow
                        eventArgsType = $null; providerException = $null; nativeEvent = @{}; error = $null
                    }
                    try {
                        $eventArgs = $event.SourceEventArgs
                        if ($null -eq $eventArgs) { throw 'The native subscription delivered no event arguments.' }
                        $delivery.eventArgsType = $eventArgs.GetType().FullName
                        # CIM sends provider exceptions through the same callback as process events.
                        $exceptionProperty = $eventArgs.PSObject.Properties['Exception']
                        if ($null -ne $exceptionProperty -and $null -ne $exceptionProperty.Value) {
                            $exception = $exceptionProperty.Value
                            $delivery.providerException = @{
                                type = $exception.GetType().FullName; message = $exception.Message; hresult = $exception.HResult
                            }
                            foreach ($name in @('NativeErrorCode', 'StatusCode', 'MessageId')) {
                                $property = $exception.PSObject.Properties[$name]
                                if ($null -ne $property) { $delivery.providerException[$name] = $property.Value }
                            }
                            throw $exception
                        }
                        $newEventProperty = $eventArgs.PSObject.Properties['NewEvent']
                        if ($null -eq $newEventProperty -or $null -eq $newEventProperty.Value) { throw 'The native subscription delivered no process event.' }
                        $native = $newEventProperty.Value
                        foreach ($name in @('ProcessName', 'ProcessID', 'ParentProcessID', 'SessionID', 'TIME_CREATED', 'ExitStatus')) {
                            $property = $native.PSObject.Properties[$name]
                            $delivery.nativeEvent[$name] = if ($null -ne $property) { $property.Value } else { $null }
                        }
                        foreach ($name in @('ProcessName', 'ProcessID', 'ParentProcessID', 'SessionID', 'TIME_CREATED')) {
                            if ($null -eq $native.$name) { throw "Missing native process event field: $name" }
                        }
                        $record = @{
                            kind = $event.MessageData.kind; processName = [string]$native.ProcessName
                            processId = [uint32]$native.ProcessID; parentProcessId = [uint32]$native.ParentProcessID
                            sessionId = [uint32]$native.SessionID
                            utc = [datetime]::FromFileTimeUtc([long]$native.TIME_CREATED)
                        }
                        if ($record.kind -eq 'Stop') {
                            if ($null -eq $native.ExitStatus) { throw 'A missing native exit status cannot be zero.' }
                            $record.exitStatus = [uint32]$native.ExitStatus
                        } else {
                            $record.nativeIdentity = @{ availability = 'unavailable'; error = $null }
                            try {
                                $process = [Diagnostics.Process]::GetProcessById([int]$native.ProcessID)
                                $null = $process.Handle
                                if ($process.HasExited) { throw 'The process exited before its native handle was captured.' }
                                $identity = @{
                                    availability = 'captured'; processId = $process.Id
                                    processName = $process.ProcessName + '.exe'; sessionId = $process.SessionId
                                    createdAtUtc = $process.StartTime.ToUniversalTime(); capturedAtUtc = [datetime]::UtcNow
                                    exitedAtUtc = $null; exitStatus = $null; error = $null
                                }
                                $record.nativeIdentity = $identity
                                $state.handles.Enqueue(@{ process = $process; identity = $identity })
                                $process = $null
                            } catch { $record.nativeIdentity.error = $_.Exception.Message }
                        }
                        $state.records.Enqueue($record)
                    } catch {
                        $delivery.error = @{ message = $_.Exception.Message; type = $_.Exception.GetType().FullName; hresult = $_.Exception.HResult }
                        $state.errors.Enqueue($delivery)
                    }
                    finally {
                        if ($null -ne $process) { $process.Dispose() }
                        New-Event -SourceIdentifier $state.signal | Out-Null
                    }
                }
            $state.jobs.Add($job)
            if (@(Get-EventSubscriber -SourceIdentifier $source -ErrorAction Stop).Count -ne 1) {
                throw "The $kind process subscription was not ready."
            }
        }
        $trace.armedAtUtc = [datetime]::UtcNow
        $trace.availability = 'armed'
    } catch {
        $trace.errors.Add($_.Exception.Message)
        Stop-InstalledPluginExitTrace $trace
    }
    return $trace
}

function Wait-InstalledPluginProcessEvent {
    param([Parameter(Mandatory)][hashtable]$Trace, [ValidateSet('Start', 'Stop')][string]$Kind,
        [Parameter(Mandatory)][int]$ProcessId, [int]$TimeoutSeconds = 15)
    $state = $null
    if (-not $script:traceStates.TryGetValue($Trace, [ref]$state)) { throw 'The process observer is not active.' }
    $clock = [Diagnostics.Stopwatch]::StartNew()
    while ($true) {
        if (@($state.records.ToArray() | Where-Object { $_.kind -eq $Kind -and $_.processId -eq $ProcessId }).Count -gt 0) { return }
        if (-not $state.errors.IsEmpty) { throw 'The process observer failed while waiting for delivery.' }
        if ($clock.Elapsed.TotalSeconds -ge $TimeoutSeconds) { throw "No $Kind event was delivered for process $ProcessId within $TimeoutSeconds seconds." }
        Wait-Event -SourceIdentifier $state.signal -Timeout 1 | Remove-Event -ErrorAction SilentlyContinue
    }
}

function Stop-InstalledPluginExitTrace {
    param([Parameter(Mandatory)][hashtable]$Trace, [AllowNull()][Nullable[int]]$ProcessId = $null)
    $state = $null
    if (-not $script:traceStates.TryGetValue($Trace, [ref]$state)) { return }
    if ($Trace.availability -eq 'armed' -and $null -ne $ProcessId) {
        try { Wait-InstalledPluginProcessEvent -Trace $Trace -Kind Stop -ProcessId $ProcessId }
        catch { $Trace.errors.Add($_.Exception.Message) }
    }
    foreach ($source in $Trace.subscriptions.Values) {
        try {
            Unregister-Event -SourceIdentifier $source -ErrorAction SilentlyContinue
            if (@(Get-EventSubscriber -SourceIdentifier $source -ErrorAction SilentlyContinue).Count -ne 0) {
                throw 'An owned process subscription could not be removed.'
            }
        } catch { $Trace.errors.Add($_.Exception.Message) }
    }
    foreach ($job in $state.jobs) {
        try { Remove-Job -Job $job -Force -ErrorAction Stop }
        catch { $Trace.errors.Add($_.Exception.Message) }
    }
    foreach ($held in $state.handles.ToArray()) {
        try {
            if (-not $held.process.HasExited) { throw 'The retained process handle is still alive after the driver returned.' }
            $held.identity.exitedAtUtc = $held.process.ExitTime.ToUniversalTime()
            $held.identity.exitStatus = [uint32]([long]$held.process.ExitCode -band 0xffffffffL)
            $held.identity.availability = 'collected'
        } catch {
            $held.identity.availability = 'unavailable'
            $held.identity.error = $_.Exception.Message
        } finally { $held.process.Dispose() }
    }
    $eventErrors = $state.errors.ToArray()
    foreach ($failure in $eventErrors) { $Trace.errors.Add($failure.error.message) }
    $Trace.eventErrors = @($eventErrors | Select-Object -First ($Trace.limitPerKind * 2))
    if ($eventErrors.Count -gt $Trace.limitPerKind * 2) { $Trace.truncated = $true }
    $records = $state.records.ToArray()
    foreach ($kind in @('Start', 'Stop')) {
        $matching = @($records | Where-Object { $_.kind -eq $kind })
        if ($matching.Count -gt $Trace.limitPerKind) { $Trace.truncated = $true }
        $Trace.events += @($matching | Select-Object -First $Trace.limitPerKind)
    }
    foreach ($source in @($Trace.subscriptions.Values) + @($state.signal)) {
        Get-Event -SourceIdentifier $source -ErrorAction SilentlyContinue | Remove-Event -ErrorAction SilentlyContinue
    }
    $null = $script:traceStates.Remove($Trace)
    $Trace.finishedAtUtc = [datetime]::UtcNow
    if ($Trace.availability -eq 'armed') { $Trace.availability = 'collected' }
    if ($Trace.errors.Count -gt 0 -or $Trace.truncated) { $Trace.availability = 'unavailable' }
}

function Get-InstalledPluginExitEvidence {
    param([Parameter(Mandatory)][hashtable]$Trace, [AllowNull()][System.Collections.IDictionary]$Report)
    $evidence = @{
        availability = 'unavailable'; reason = $null; processId = $null; runId = $null
        bootstrapUtc = $null; processCreatedUtc = $null; start = $null; stop = $null; exitStatus = $null; exitStatusHex = $null
        stopAuxiliaryIdentity = $null
        terminationCause = 'Not inferred: flutter drive can stop the app after the test.'
    }
    try {
        if ($null -eq $Report -or $Report['platform'] -ne 'windows' -or $Report['buildMode'] -ne 'profile') {
            throw 'A readable Windows profile device report is required.'
        }
        if ($Report['pid'] -isnot [long] -and $Report['pid'] -isnot [int]) { throw 'The report PID must be an integer.' }
        if ($Report['pid'] -le 0 -or $Report['pid'] -gt [uint32]::MaxValue) { throw 'The report PID is out of range.' }
        if ($Report['runId'] -isnot [string] -or $Report['runId'] -notmatch '^([1-9][0-9]*)-([0-9]{16})$') {
            throw 'The report run identity is missing or invalid.'
        }
        if ([long]$Matches[1] -ne $Report['pid']) { throw 'The report PID and run identity disagree.' }
        $boot = [datetime]::UnixEpoch.AddTicks([long]$Matches[2] * 10)
        if ($boot -lt $Trace.armedAtUtc -or $boot -gt $Trace.finishedAtUtc) { throw 'The report is outside this observer run.' }
        $evidence.processId = $Report['pid']; $evidence.runId = $Report['runId']; $evidence.bootstrapUtc = $boot
        if ($Trace.availability -ne 'collected' -or $Trace.truncated -or $Trace.errors.Count -gt 0) {
            throw 'Process observations are unavailable or incomplete.'
        }
        $samePid = @($Trace.events | Where-Object {
            $_.processId -eq $Report['pid'] -and $_.processName -ieq $Trace.processName
        })
        # Keep every same-PID event so an earlier stop or another lifetime cannot disappear.
        $starts = @($samePid | Where-Object { $_.kind -eq 'Start' })
        $stops = @($samePid | Where-Object { $_.kind -eq 'Stop' })
        if ($starts.Count -ne 1 -or $stops.Count -ne 1) {
            throw 'A unique matching stop and start were not observed, or the PID was reused.'
        }
        $evidence.start = $starts[0]
        # TIME_CREATED may follow bootstrap; the retained handle supplies the
        # actual creation time and prevents substituting another process instance.
        $identity = $starts[0].nativeIdentity
        if ($null -eq $identity -or $identity.availability -ne 'collected' -or
            $identity.processId -ne $Report['pid'] -or $identity.processName -ine $Trace.processName -or
            $identity.sessionId -ne $starts[0].sessionId) {
            throw 'A retained native process identity is required.'
        }
        if ($identity.createdAtUtc -isnot [datetime] -or $identity.capturedAtUtc -isnot [datetime] -or
            $identity.exitedAtUtc -isnot [datetime] -or
            $identity.createdAtUtc -lt $Trace.armedAtUtc -or $identity.createdAtUtc -gt $boot -or
            $identity.capturedAtUtc -lt $identity.createdAtUtc -or $identity.capturedAtUtc -gt $identity.exitedAtUtc -or
            $identity.exitedAtUtc -le $boot -or $identity.exitedAtUtc -gt $Trace.finishedAtUtc) {
            throw 'The retained process lifetime must contain the reported bootstrap and stay inside this observer run.'
        }
        # The provider does not promise that stop event generation follows the
        # final ExitTime field. Verify each inside the lifetime/run independently.
        $zeroStopAuxiliary = $stops[0].parentProcessId -eq 0 -and $stops[0].sessionId -eq 0
        if ($starts[0].utc -lt $identity.createdAtUtc -or $starts[0].utc -gt $Trace.finishedAtUtc -or
            $stops[0].utc -le $boot -or $stops[0].utc -lt $starts[0].utc -or
            $stops[0].utc -gt $Trace.finishedAtUtc -or
            (-not $zeroStopAuxiliary -and
                ($stops[0].parentProcessId -ne $starts[0].parentProcessId -or $stops[0].sessionId -ne $starts[0].sessionId))) {
            throw 'Process notifications must match the retained lifetime, parent and session.'
        }
        # A retained live handle prevents PID reuse even when the stop provider
        # omits both auxiliary IDs; the raw zero values remain in the stop record.
        $evidence.stopAuxiliaryIdentity = @{
            availability = $(if ($zeroStopAuxiliary) { 'unavailable' } else { 'collected' })
            reason = $(if ($zeroStopAuxiliary) { 'Stop provider returned zero for both parent and session; identity is verified by the retained process handle.' } else { $null })
        }
        foreach ($status in @($stops[0].exitStatus, $identity.exitStatus)) {
            if ($null -eq $status -or ($status -isnot [int] -and $status -isnot [long] -and $status -isnot [uint32]) -or
                $status -lt 0 -or $status -gt [uint32]::MaxValue) {
                throw 'Both native exit statuses must be observed unsigned integers.'
            }
        }
        if ($stops[0].exitStatus -ne $identity.exitStatus) { throw 'The retained process and stop event exit statuses disagree.' }
        $evidence.processCreatedUtc = $identity.createdAtUtc
        $evidence.stop = $stops[0]
        $evidence.exitStatus = [uint32]$stops[0].exitStatus
        $evidence.exitStatusHex = '0x{0:X8}' -f $evidence.exitStatus
        $evidence.availability = 'collected'
    } catch { $evidence.reason = $_.Exception.Message }
    return $evidence
}

function Select-InstalledPluginApplicationErrors {
    param(
        [Parameter(Mandatory)][xml]$Events,
        [Parameter(Mandatory)][hashtable]$Identity,
        [Parameter(Mandatory)][datetime]$ArmedAtUtc,
        [Parameter(Mandatory)][datetime]$FinishedAtUtc,
        [string]$ProcessName = 'otzaria.exe'
    )
    if ($null -eq $Identity.processId -or $null -eq $Identity.bootstrapUtc) { return }
    foreach ($event in $Events.SelectNodes('/*/*[local-name()="Event"]')) {
        try {
            $data = @{}
            foreach ($field in $event.SelectNodes('./*[local-name()="EventData"]/*[local-name()="Data"]')) {
                $data[$field.GetAttribute('Name')] = $field.InnerText
            }
            $system = $event.SelectSingleNode('./*[local-name()="System"]')
            $provider = $system.SelectSingleNode('./*[local-name()="Provider"]').GetAttribute('Name')
            $eventId = $system.SelectSingleNode('./*[local-name()="EventID"]').InnerText
            if ($provider -ne 'Application Error' -or $eventId -ne '1000' -or $data['AppName'] -ine $ProcessName) { continue }
            if ($data['ProcessId'] -notmatch '^0x[0-9a-fA-F]+$' -or $data['ProcessCreationTime'] -notmatch '^0x[0-9a-fA-F]+$') { continue }
            $processId = [Convert]::ToUInt32($data['ProcessId'].Replace('0x', ''), 16)
            $created = [datetime]::FromFileTimeUtc([Convert]::ToInt64($data['ProcessCreationTime'].Replace('0x', ''), 16))
            $utc = [datetime]::Parse($system.SelectSingleNode('./*[local-name()="TimeCreated"]').GetAttribute('SystemTime')).ToUniversalTime()
            if ($processId -ne $Identity.processId -or $created -lt $ArmedAtUtc -or $created -gt $Identity.bootstrapUtc -or
                ($null -ne $Identity.processCreatedUtc -and $created -ne $Identity.processCreatedUtc) -or
                $utc -lt $Identity.bootstrapUtc -or $utc -gt $FinishedAtUtc) { continue }
            @{
                provider = $provider; eventId = 1000; utc = $utc; processId = $processId; processCreatedUtc = $created
                appName = $data['AppName']; appPath = $data['AppPath']; moduleName = $data['ModuleName']
                modulePath = $data['ModulePath']; exceptionCode = $data['ExceptionCode']; faultOffset = $data['FaultingOffset']
                reportId = $data['IntegratorReportId']
            }
        } catch { throw "Application Error record could not be correlated: $($_.Exception.Message)" }
    }
}

function Read-InstalledPluginApplicationErrors {
    param([Parameter(Mandatory)][hashtable]$Trace, [Parameter(Mandatory)][hashtable]$Identity)
    $result = @{ availability = 'unavailable'; reason = $null; events = @(); limit = 64; truncated = $false }
    if ($null -eq $Identity.processId) { $result.reason = 'No verified report identity.'; return $result }
    $process = [Diagnostics.Process]::new()
    $started = $false
    try {
        $end = [datetime]::UtcNow
        $startText = $Trace.armedAtUtc.ToString('yyyy-MM-ddTHH:mm:ss.fffffffZ')
        $endText = $end.ToString('yyyy-MM-ddTHH:mm:ss.fffffffZ')
        $query = "*[System[Provider[@Name='Application Error'] and EventID=1000 and TimeCreated[@SystemTime>='$startText' and @SystemTime<='$endText']]]"
        $process.StartInfo = [Diagnostics.ProcessStartInfo]::new('wevtutil.exe')
        $process.StartInfo.UseShellExecute = $false
        $process.StartInfo.CreateNoWindow = $true
        $process.StartInfo.RedirectStandardOutput = $true
        $process.StartInfo.RedirectStandardError = $true
        foreach ($argument in @('qe', 'Application', "/q:$query", '/c:65', '/rd:true', '/f:xml', '/e:Events')) {
            $process.StartInfo.ArgumentList.Add($argument)
        }
        $started = $process.Start()
        if (-not $started) { throw 'Could not start the bounded Application Error query.' }
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(15000)) { throw 'Application Error query timed out after 15 seconds.' }
        if (-not $stdout.Wait(2000) -or -not $stderr.Wait(2000)) { throw 'Application Error output did not close.' }
        if ($process.ExitCode -ne 0) { throw "Application Error query exited $($process.ExitCode): $($stderr.Result)" }
        $xml = [xml]$stdout.Result
        $result.truncated = $xml.SelectNodes('/*/*[local-name()="Event"]').Count -gt $result.limit
        $result.events = @(Select-InstalledPluginApplicationErrors -Events $xml -Identity $Identity `
            -ArmedAtUtc $Trace.armedAtUtc -FinishedAtUtc $end -ProcessName $Trace.processName | Select-Object -First $result.limit)
        $result.availability = 'collected'
        if ($result.events.Count -eq 0) { $result.reason = 'No matching Application Error event was observed in the bounded query.' }
    } catch { $result.reason = $_.Exception.Message }
    finally {
        try {
            if ($started -and -not $process.HasExited) {
                $process.Kill($true)
                if (-not $process.WaitForExit(2000)) { throw 'The owned Application Error query did not exit after termination.' }
            }
        } catch { $result.reason = "$($result.reason) Query cleanup: $($_.Exception.Message)" }
        $process.Dispose()
    }
    return $result
}

function Invoke-InstalledPluginLoggedCommand {
    param([Parameter(Mandatory)][string]$Command, [string[]]$Arguments, [Parameter(Mandatory)][string]$LogPath)
    $PSNativeCommandUseErrorActionPreference = $false
    # Windows Flutter exposes both flutter.bat and flutter. Keep the first
    # application in normal resolution order, rather than invoking an array.
    $nativeCommand = Get-Command $Command -CommandType Application -TotalCount 1 -ErrorAction Stop
    & $nativeCommand @Arguments 2>&1 | Tee-Object -FilePath $LogPath | Out-Host
    if ($null -eq $LASTEXITCODE) { throw 'The driver did not return a native exit code.' }
    return [int]$LASTEXITCODE
}

function Get-InstalledPluginRunExitCode {
    param([AllowNull()][Nullable[int]]$DriverExitCode, [AllowNull()][System.Collections.IDictionary]$Report,
        [Parameter(Mandatory)][hashtable]$ExitEvidence, [AllowNull()][System.Collections.IDictionary]$ApplicationErrors = $null)
    if ($null -ne $DriverExitCode -and $DriverExitCode -ne 0) { return [int]$DriverExitCode }
    if ($null -eq $DriverExitCode -or $null -eq $Report -or $Report['status'] -ne 'passed' -or
        $Report['errors'] -isnot [array] -or $Report['errors'].Count -ne 0 -or
        $Report['testFailures'] -isnot [array] -or $Report['testFailures'].Count -ne 0 -or
        $ExitEvidence.availability -ne 'collected') { return 1 }
    # Dart Process::Kill on Windows uses TerminateProcess(handle, -1).
    if ($ExitEvidence.exitStatus -notin @(0, [uint32]::MaxValue)) { return 1 }
    if ($null -ne $ApplicationErrors -and $ApplicationErrors['events'].Count -gt 0) { return 1 }
    return 0
}

function Save-InstalledPluginRunReceipt {
    param([Parameter(Mandatory)][hashtable]$Receipt, [Parameter(Mandatory)][string]$Path, [int]$ExitCode)
    $Receipt.status = if ($ExitCode -eq 0) { 'passed' } else { 'failed' }
    $Receipt.stepExitCode = $ExitCode
    try {
        $Receipt | ConvertTo-Json -Depth 15 | Set-Content -LiteralPath $Path -Encoding utf8 -ErrorAction Stop
    } catch {
        if ($ExitCode -eq 0) { $ExitCode = 1 }
        try { [Console]::Error.WriteLine("Native exit receipt write failed: $($_.Exception.Message)") } catch { }
    }
    return $ExitCode
}

Export-ModuleMember -Function Start-InstalledPluginExitTrace, Stop-InstalledPluginExitTrace, Wait-InstalledPluginProcessEvent,
    Get-InstalledPluginExitEvidence, Select-InstalledPluginApplicationErrors, Read-InstalledPluginApplicationErrors,
    Invoke-InstalledPluginLoggedCommand, Get-InstalledPluginRunExitCode, Save-InstalledPluginRunReceipt
