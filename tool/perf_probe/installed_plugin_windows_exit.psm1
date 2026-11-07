#Requires -Version 7.0
Set-StrictMode -Version Latest
if (-not ('InstalledPluginProbe.LifetimeObserver' -as [type])) {
    Add-Type -Path (Join-Path $PSScriptRoot 'installed_plugin_windows_lifetime.cs')
}

function Start-InstalledPluginLifetimeObserver {
    param([Parameter(Mandatory)][string]$Executable, [Parameter(Mandatory)][string]$CampaignId,
        [Parameter(Mandatory)][string]$Token, [int]$StartupTimeoutMilliseconds = 1200000)
    return [InstalledPluginProbe.LifetimeObserver]::new($Executable, $CampaignId, $Token, $StartupTimeoutMilliseconds)
}

function Stop-InstalledPluginLifetimeObserver {
    param([Parameter(Mandatory)]$Observer, [uint32]$ExitTimeoutMilliseconds = 10000)
    $Observer.Complete($ExitTimeoutMilliseconds)
    return $Observer.SnapshotJson() | ConvertFrom-Json -AsHashtable
}

function Get-InstalledPluginExitEvidence {
    param([AllowNull()][hashtable]$Trace, [AllowNull()][System.Collections.IDictionary]$Report)
    $evidence = @{
        availability = 'unavailable'; reason = $null; processId = $null; runId = $null
        bootstrapUtc = $null; creationFileTime = $null; executable = $null; exitFileTime = $null
        exitStatus = $null; exitStatusHex = $null
        terminationCause = 'Not inferred: flutter drive can stop the app after the test.'
    }
    try {
        if ($null -ne $Trace -and $Trace.identityVerified) {
            $evidence.processId = $Trace.identity.pid; $evidence.runId = $Trace.runId
            $evidence.bootstrapUtc = [datetime]$Trace.bootstrapUtc
            $evidence.creationFileTime = $Trace.identity.creationFileTime; $evidence.executable = $Trace.identity.executable
        }
        if ($null -eq $Trace -or $Trace.availability -ne 'collected' -or $Trace.errors.Count -gt 0 -or
            -not $Trace.identityVerified -or -not $Trace.bootstrapQuiescent -or $Trace.waitResult -ne 0 -or
            -not $Trace.cleanup.handleAcquired -or -not $Trace.cleanup.handleClosed -or
            -not $Trace.cleanup.listenerStopped -or -not $Trace.cleanup.channelClosed -or -not $Trace.cleanup.bootstrapTaskCompleted) {
            throw 'The retained native lifetime or its cleanup is unavailable or incomplete.'
        }
        if ($null -eq $Report -or $Report['platform'] -ne 'windows' -or $Report['buildMode'] -ne 'profile') {
            throw 'A readable Windows profile device report is required.'
        }
        if (($Report['pid'] -isnot [long] -and $Report['pid'] -isnot [int]) -or
            $Report['pid'] -le 0 -or $Report['pid'] -gt [uint32]::MaxValue) { throw 'The report PID must be a valid integer.' }
        $ack = $Report['windowsLifetime']
        if ($ack -isnot [Collections.IDictionary] -or $ack['kind'] -ne 'ready' -or $ack['version'] -ne 1 -or
            $ack['campaignId'] -cne $Trace.campaignId -or $ack['runId'] -cne $Trace.runId -or
            $Report['runId'] -cne $Trace.runId -or $ack['pid'] -ne $Trace.identity.pid -or $Report['pid'] -ne $Trace.identity.pid -or
            $ack['creationFileTime'] -cne $Trace.identity.creationFileTime -or
            $ack['executable'] -cne $Trace.identity.executable -or $ack['bootstrapQuiescent'] -ne $true -or
            [datetime]$ack['acknowledgedAtUtc'] -ne [datetime]$Trace.acknowledgedAtUtc) {
            throw 'The final device report does not acknowledge this exact native lifetime.'
        }
        if ($null -eq $Trace.exitStatus -or
            ($Trace.exitStatus -isnot [int] -and $Trace.exitStatus -isnot [long] -and $Trace.exitStatus -isnot [uint32])) {
            throw 'The native exit status must be an observed unsigned integer.'
        }
        $evidence.exitFileTime = $Trace.exitFileTime
        $evidence.exitStatus = [uint32]$Trace.exitStatus
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
    if ($null -eq $Identity.processId -or $null -eq $Identity.creationFileTime) { return }
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
            if ($processId -ne $Identity.processId -or $created.ToFileTimeUtc() -ne [long]$Identity.creationFileTime -or
                $data['AppPath'] -ine $Identity.executable -or
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

function Copy-LimitedInstalledPluginDiagnostic {
    param($Value)
    if ($Value -is [string]) { return $Value.Substring(0, [Math]::Min(1024, $Value.Length)) }
    if ($Value -is [Collections.IDictionary]) {
        $copy = @{}
        foreach ($key in $Value.Keys) { $copy[$key] = Copy-LimitedInstalledPluginDiagnostic $Value[$key] }
        return $copy
    }
    if ($Value -is [Collections.IEnumerable]) {
        return ,@($Value | Select-Object -First 8 | ForEach-Object { Copy-LimitedInstalledPluginDiagnostic $_ })
    }
    return $Value
}

function Save-InstalledPluginJson {
    param([Parameter(Mandatory)][hashtable]$Value, [Parameter(Mandatory)][string]$Path)
    $json = $Value | ConvertTo-Json -Depth 20 -Compress
    $truncated = [Text.Encoding]::UTF8.GetByteCount($json) + 1 -gt 256KB
    if ($truncated) {
        $limited = Copy-LimitedInstalledPluginDiagnostic $Value
        $limited.status = 'failed'; $limited.diagnosticTruncated = $true
        $limited.originalBytes = [Text.Encoding]::UTF8.GetByteCount($json) + 1
        $limited.diagnosticLimits = @{ stringCharacters = 1024; arrayItems = 8 }
        $json = $limited | ConvertTo-Json -Depth 20 -Compress
        if ([Text.Encoding]::UTF8.GetByteCount($json) + 1 -gt 256KB) { throw 'Limited native evidence still exceeds 256 KiB.' }
    }
    $stream = $null
    try {
        $stream = [IO.File]::Open($Path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        $bytes = [Text.UTF8Encoding]::new($false).GetBytes($json + "`n")
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.Flush($true)
    } finally { if ($null -ne $stream) { $stream.Dispose() } }
    if ($truncated) { throw 'Native evidence exceeds the 256 KiB limit; bounded partial evidence was saved.' }
}

function Write-InstalledPluginDiagnosticFallback {
    param([hashtable]$Value, [string]$SaveError)
    $limited = Copy-LimitedInstalledPluginDiagnostic $Value
    $limited.status = 'failed'; $limited.diagnosticFallback = $true
    $limited.diagnosticSaveError = Copy-LimitedInstalledPluginDiagnostic $SaveError
    $limited.diagnosticLimits = @{ stringCharacters = 1024; arrayItems = 8 }
    $json = $limited | ConvertTo-Json -Depth 20 -Compress
    if ([Text.Encoding]::UTF8.GetByteCount($json) -gt 256KB) {
        $json = @{ status = 'failed'; diagnosticFallback = $true; diagnosticTruncated = $true;
            firstError = $limited['firstError']; error = $limited['error']; child = $limited['child'];
            driverExitCode = $limited['driverExitCode']; stepExitCode = $limited['stepExitCode'];
            diagnosticSaveError = $limited.diagnosticSaveError } | ConvertTo-Json -Depth 10 -Compress
    }
    [Console]::Error.WriteLine($json)
}

function New-InstalledPluginLogWriter {
    param([IO.Stream]$Stream)
    return [IO.StreamWriter]::new($Stream, [Text.UTF8Encoding]::new($false))
}

function Invoke-InstalledPluginLoggedCommand {
    param([Parameter(Mandatory)][string]$Command, [string[]]$Arguments, [Parameter(Mandatory)][string]$LogPath)
    $PSNativeCommandUseErrorActionPreference = $false
    # SDK directories can contain both flutter.bat and extensionless flutter.
    # Invoke only the first application in PowerShell's normal search order.
    $nativeCommand = Get-Command $Command -CommandType Application -TotalCount 1 -ErrorAction Stop
    $result = @{ exitCode = $null; error = $null; logTruncated = $false }
    $stream = $null
    $writer = $null
    $loggingFailed = $false
    try {
        $stream = [IO.File]::Open($LogPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::Read)
        $writer = New-InstalledPluginLogWriter $stream
        $global:LASTEXITCODE = $null
        & $nativeCommand.Path @Arguments 2>&1 | ForEach-Object {
            $line = $_.ToString()
            if (-not $loggingFailed) {
                try {
                    if ($stream.Position + [Text.Encoding]::UTF8.GetByteCount($line) + 2 -gt 16MB) {
                        $result.logTruncated = $true
                        throw 'The driver log exceeds 16 MiB.'
                    }
                    $writer.WriteLine($line); $writer.Flush()
                } catch {
                    $loggingFailed = $true
                    if ($null -eq $result.error) { $result.error = $_.Exception.Message }
                }
            }
            try { Write-Host $line }
            catch { if ($null -eq $result.error) { $result.error = $_.Exception.Message } }
        }
        if ($null -eq $global:LASTEXITCODE) { throw 'The driver did not return a native exit code.' }
        $result.exitCode = [int]$global:LASTEXITCODE
    } catch { if ($null -eq $result.error) { $result.error = $_.Exception.Message } }
    finally {
        try { if ($null -ne $writer) { $writer.Dispose() } }
        catch { if ($null -eq $result.error) { $result.error = $_.Exception.Message } }
        try { if ($null -ne $stream) { $stream.Dispose() } }
        catch { if ($null -eq $result.error) { $result.error = $_.Exception.Message } }
    }
    return $result
}

function Get-InstalledPluginRunExitCode {
    param([AllowNull()][Nullable[int]]$DriverExitCode, [AllowNull()][System.Collections.IDictionary]$Report,
        [Parameter(Mandatory)][hashtable]$ExitEvidence, [AllowNull()][System.Collections.IDictionary]$ApplicationErrors = $null,
        [string[]]$DiagnosticErrors = @())
    if ($null -ne $DriverExitCode -and $DriverExitCode -ne 0) { return [int]$DriverExitCode }
    if ($null -eq $DriverExitCode -or $null -eq $Report -or $Report['status'] -ne 'passed' -or
        $Report['errors'] -isnot [array] -or $Report['errors'].Count -ne 0 -or
        $Report['testFailures'] -isnot [array] -or $Report['testFailures'].Count -ne 0 -or
        $ExitEvidence.availability -ne 'collected' -or $DiagnosticErrors.Count -gt 0) { return 1 }
    # Dart Process::Kill on Windows uses TerminateProcess(handle, -1).
    if ($ExitEvidence.exitStatus -notin @(0, [uint32]::MaxValue)) { return 1 }
    if ($null -eq $ApplicationErrors -or $ApplicationErrors['availability'] -ne 'collected' -or
        $ApplicationErrors['truncated'] -ne $false -or $ApplicationErrors['events'] -isnot [array] -or
        $ApplicationErrors['events'].Count -gt 0) { return 1 }
    return 0
}

Export-ModuleMember -Function Start-InstalledPluginLifetimeObserver, Stop-InstalledPluginLifetimeObserver,
    Get-InstalledPluginExitEvidence, Select-InstalledPluginApplicationErrors, Read-InstalledPluginApplicationErrors,
    Invoke-InstalledPluginLoggedCommand, Get-InstalledPluginRunExitCode, Save-InstalledPluginJson, Write-InstalledPluginDiagnosticFallback
