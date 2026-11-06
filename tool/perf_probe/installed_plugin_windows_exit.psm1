#Requires -Version 7.0
Set-StrictMode -Version Latest

function Start-InstalledPluginExitTrace {
    param([ValidatePattern('^[A-Za-z0-9_.-]+\.exe$')][string]$ProcessName = 'otzaria.exe')
    $trace = @{
        source = 'Win32_ProcessStartTrace / Win32_ProcessStopTrace'
        processName = $ProcessName; availability = 'unavailable'
        armedAtUtc = [datetime]::UtcNow; finishedAtUtc = $null
        subscriptions = @{}; events = @(); errors = [Collections.Generic.List[string]]::new()
        limitPerKind = 64; truncated = $false
    }
    try {
        foreach ($kind in @('Start', 'Stop')) {
            $source = 'installed-plugin-' + [guid]::NewGuid().ToString('N')
            $trace.subscriptions[$kind] = $source
            Register-CimIndicationEvent -Namespace root/cimv2 `
                -Query "SELECT * FROM Win32_Process${kind}Trace WHERE ProcessName='$ProcessName'" `
                -SourceIdentifier $source -OperationTimeoutSec 15 -MaxTriggerCount 65 -ErrorAction Stop | Out-Null
            if (@(Get-EventSubscriber -SourceIdentifier $source -ErrorAction Stop).Count -ne 1) {
                throw "The $kind process subscription was not ready."
            }
        }
        $trace.armedAtUtc = [datetime]::UtcNow
        $trace.availability = 'armed'
    } catch {
        $trace.errors.Add($_.Exception.Message)
        foreach ($source in $trace.subscriptions.Values) {
            Unregister-Event -SourceIdentifier $source -ErrorAction SilentlyContinue
            Get-Event -SourceIdentifier $source -ErrorAction SilentlyContinue | Remove-Event -ErrorAction SilentlyContinue
        }
    }
    return $trace
}

function Stop-InstalledPluginExitTrace {
    param([Parameter(Mandatory)][hashtable]$Trace)
    # Delivery grace is after flutter drive has returned, outside measured windows.
    if ($Trace.availability -eq 'armed') { Start-Sleep -Milliseconds 1000 }
    foreach ($kind in $Trace.subscriptions.Keys) {
        $source = $Trace.subscriptions[$kind]
        try {
            Unregister-Event -SourceIdentifier $source -ErrorAction SilentlyContinue
            if (@(Get-EventSubscriber -SourceIdentifier $source -ErrorAction SilentlyContinue).Count -ne 0) {
                throw 'An owned process subscription could not be removed.'
            }
            $queued = @(Get-Event -SourceIdentifier $source -ErrorAction SilentlyContinue)
            if ($queued.Count -gt $Trace.limitPerKind) { $Trace.truncated = $true }
            foreach ($item in ($queued | Select-Object -First $Trace.limitPerKind)) {
                $native = $item.SourceEventArgs.NewEvent
                foreach ($name in @('ProcessName', 'ProcessID', 'ParentProcessID', 'SessionID', 'TIME_CREATED')) {
                    if ($null -eq $native.$name) { throw "Missing native process event field: $name" }
                }
                $record = @{
                    kind = $kind; processName = [string]$native.ProcessName
                    processId = [uint32]$native.ProcessID; parentProcessId = [uint32]$native.ParentProcessID
                    sessionId = [uint32]$native.SessionID
                    utc = [datetime]::FromFileTimeUtc([long]$native.TIME_CREATED)
                }
                if ($kind -eq 'Stop') {
                    if ($null -eq $native.ExitStatus) { throw 'A missing native exit status cannot be zero.' }
                    $record.exitStatus = [uint32]$native.ExitStatus
                }
                $Trace.events += $record
            }
        } catch {
            $Trace.errors.Add($_.Exception.Message)
        } finally {
            Get-Event -SourceIdentifier $source -ErrorAction SilentlyContinue | Remove-Event -ErrorAction SilentlyContinue
        }
    }
    $Trace.finishedAtUtc = [datetime]::UtcNow
    if ($Trace.availability -eq 'armed') { $Trace.availability = 'collected' }
    if ($Trace.errors.Count -gt 0 -or $Trace.truncated) { $Trace.availability = 'unavailable' }
}

function Get-InstalledPluginExitEvidence {
    param([Parameter(Mandatory)][hashtable]$Trace, [AllowNull()][System.Collections.IDictionary]$Report)
    $evidence = @{
        availability = 'unavailable'; reason = $null; processId = $null; runId = $null
        bootstrapUtc = $null; start = $null; stop = $null; exitStatus = $null; exitStatusHex = $null
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
        $starts = @($Trace.events | Where-Object {
            $_.kind -eq 'Start' -and $_.processId -eq $Report['pid'] -and
            $_.processName -ieq $Trace.processName -and $_.utc -ge $Trace.armedAtUtc -and $_.utc -le $boot
        })
        if ($starts.Count -ne 1) { throw 'A unique process start before the reported bootstrap was not observed.' }
        $evidence.start = $starts[0]
        $samePid = @($Trace.events | Where-Object {
            $_.processId -eq $Report['pid'] -and $_.processName -ieq $Trace.processName
        })
        # Earlier or conflicting stops must not be filtered out of a PID's lifetime.
        $stops = @($samePid | Where-Object { $_.kind -eq 'Stop' })
        if ($stops.Count -ne 1 -or @($samePid | Where-Object { $_.kind -eq 'Start' }).Count -ne 1) {
            throw 'A unique matching stop was not observed, or the PID was reused.'
        }
        if ($stops[0].utc -le $boot -or $stops[0].utc -gt $Trace.finishedAtUtc -or
            $stops[0].parentProcessId -ne $starts[0].parentProcessId -or $stops[0].sessionId -ne $starts[0].sessionId) {
            throw 'The unique process stop must follow bootstrap and match the observed start identity.'
        }
        if ($null -eq $stops[0].exitStatus -or
            ($stops[0].exitStatus -isnot [int] -and $stops[0].exitStatus -isnot [long] -and $stops[0].exitStatus -isnot [uint32])) {
            throw 'The native exit status must be an observed integer.'
        }
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
    $nativeCommand = Get-Command $Command -CommandType Application -ErrorAction Stop
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

Export-ModuleMember -Function Start-InstalledPluginExitTrace, Stop-InstalledPluginExitTrace,
    Get-InstalledPluginExitEvidence, Select-InstalledPluginApplicationErrors, Read-InstalledPluginApplicationErrors,
    Invoke-InstalledPluginLoggedCommand, Get-InstalledPluginRunExitCode
