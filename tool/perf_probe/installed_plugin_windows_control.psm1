#Requires -Version 7.0
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'installed_plugin_windows_exit.psm1')

function Copy-LimitedControlDiagnostic {
    param($Value)
    if ($Value -is [string]) { return $Value.Substring(0, [Math]::Min(1024, $Value.Length)) }
    if ($Value -is [Collections.IDictionary]) {
        $copy = @{}
        foreach ($key in $Value.Keys) { $copy[$key] = Copy-LimitedControlDiagnostic $Value[$key] }
        return $copy
    }
    if ($Value -is [Collections.IEnumerable]) {
        return ,@($Value | Select-Object -First 8 | ForEach-Object { Copy-LimitedControlDiagnostic $_ })
    }
    return $Value
}

function Save-InstalledPluginControlReport {
    param([hashtable]$Result, [string]$Path)
    $json = $Result | ConvertTo-Json -Depth 16 -Compress
    if ([Text.Encoding]::UTF8.GetByteCount($json) + 1 -gt 256KB) {
        $limited = Copy-LimitedControlDiagnostic $Result
        $limited.status = 'failed'
        $limited.diagnosticTruncated = $true
        $limited.reason = 'Native control report exceeds the 256 KiB limit.'
        $limited.originalBytes = [Text.Encoding]::UTF8.GetByteCount($json) + 1
        $limited.diagnosticLimits = @{ stringCharacters = 1024; arrayItems = 8 }
        $json = $limited | ConvertTo-Json -Depth 16 -Compress
        if ([Text.Encoding]::UTF8.GetByteCount($json) + 1 -gt 256KB) { throw 'The limited native control diagnostic still exceeds 256 KiB.' }
        [IO.File]::WriteAllText($Path, $json + "`n", [Text.UTF8Encoding]::new($false))
        throw 'Native control report exceeds the 256 KiB limit.'
    }
    [IO.File]::WriteAllText($Path, $json + "`n", [Text.UTF8Encoding]::new($false))
}

function Invoke-InstalledPluginExitControl {
    param([Parameter(Mandatory)][string]$Directory, [Parameter(Mandatory)][string]$ReportPath)
    $result = @{
        schemaVersion = 1; status = 'running'; stage = 'subscribe'; error = $null
        hostPlatform = [Runtime.InteropServices.RuntimeInformation]::OSDescription
        powerShellVersion = $PSVersionTable.PSVersion.ToString()
        startedAtUtc = [datetime]::UtcNow; finishedAtUtc = $null
        trace = $null; observation = $null; childReport = $null; childReportRaw = $null
        child = @{ pid = $null; started = $false; exited = $false; exitCode = $null; terminatedByControl = $false }
        cleanup = @{ childExited = $false; subscriptionsRemaining = @(); eventsRemaining = @(); errors = @() }
    }
    $failure = $null
    $child = [Diagnostics.Process]::new()
    $foreignId = 'foreign-test-' + [guid]::NewGuid().ToString('N')
    $timer = [Timers.Timer]::new(60000)
    $controlReport = Join-Path $Directory 'control-report.json'
    try {
        Register-ObjectEvent -InputObject $timer -EventName Elapsed -SourceIdentifier $foreignId | Out-Null
        New-Event -SourceIdentifier $foreignId | Out-Null
        $result.trace = Start-InstalledPluginExitTrace -ProcessName 'pwsh.exe'
        if ($result.trace.availability -ne 'armed') { throw 'Both actual CIM subscriptions must be ready before the controlled child starts.' }
        $controlPath = Join-Path $Directory 'native-control.ps1'
        @'
$microseconds = [long](([datetime]::UtcNow.Ticks - [datetime]::UnixEpoch.Ticks) / 10)
@{ pid = $PID; runId = "$PID-$microseconds"; platform = 'windows'; buildMode = 'profile' } |
    ConvertTo-Json | Set-Content -LiteralPath $args[0] -Encoding utf8
exit 37
'@ | Set-Content -LiteralPath $controlPath -Encoding utf8
        $result.stage = 'child'
        $executable = Join-Path $PSHOME $(if ($IsWindows) { 'pwsh.exe' } else { 'pwsh' })
        $child.StartInfo = [Diagnostics.ProcessStartInfo]::new($executable)
        $child.StartInfo.UseShellExecute = $false
        foreach ($argument in @('-NoLogo', '-NoProfile', '-File', $controlPath, $controlReport)) { $child.StartInfo.ArgumentList.Add($argument) }
        $result.child.started = $child.Start()
        if (-not $result.child.started) { throw 'The native control could not start its child process.' }
        $result.child.pid = $child.Id
        $result.child.exited = $child.WaitForExit(15000)
        if (-not $result.child.exited) { throw 'The native control child exceeded 15 seconds.' }
        $result.child.exitCode = $child.ExitCode
        if ($child.ExitCode -ne 37) { throw "The native control child exited $($child.ExitCode), expected 37." }
        $result.stage = 'observe'
        Stop-InstalledPluginExitTrace $result.trace
        if ((Get-Item -LiteralPath $controlReport).Length -gt 16KB) { throw 'The native control child report exceeds 16 KiB.' }
        $result.childReportRaw = Get-Content -LiteralPath $controlReport -Raw
        $result.childReport = $result.childReportRaw | ConvertFrom-Json -AsHashtable
        if ($result.childReport.pid -ne $child.Id) { throw 'The native control report does not belong to the owned child.' }
        $result.observation = Get-InstalledPluginExitEvidence $result.trace $result.childReport
        if ($result.observation.availability -ne 'collected') {
            throw "Real Windows process start and stop events did not identify the controlled child: $($result.observation.reason)"
        }
        if ($result.observation.exitStatus -ne 37) { throw "Kernel-reported child exit status was $($result.observation.exitStatus), expected 37." }
        $result.stage = 'verify-cleanup'
        if (@(Get-EventSubscriber -SourceIdentifier $foreignId).Count -ne 1 -or
            @(Get-Event -SourceIdentifier $foreignId).Count -ne 1) { throw 'Observer cleanup changed a foreign subscription or queued event.' }
        foreach ($source in $result.trace.subscriptions.Values) {
            if (@(Get-EventSubscriber -SourceIdentifier $source -ErrorAction SilentlyContinue).Count -ne 0) {
                throw 'An owned native subscription remains after collection.'
            }
        }
        $result.status = 'passed'
    } catch {
        $failure = $_
        $result.status = 'failed'
        $result.error = @{ message = $_.Exception.Message; type = $_.Exception.GetType().FullName; stack = $_.ScriptStackTrace }
    } finally {
        try {
            if ($result.child.started) {
                if (-not $child.HasExited) {
                    $result.child.terminatedByControl = $true
                    $child.Kill($true)
                    if (-not $child.WaitForExit(2000)) { throw 'The owned native control child did not exit after termination.' }
                }
                $result.cleanup.childExited = $child.HasExited
                $result.child.exitCode = $child.ExitCode
            }
        } catch { $result.cleanup.errors += $_.Exception.Message }
        try {
            if ($null -ne $result.trace -and $result.trace.availability -eq 'armed') { Stop-InstalledPluginExitTrace $result.trace }
        } catch { $result.cleanup.errors += $_.Exception.Message }
        $ownedSources = @($foreignId)
        if ($null -ne $result.trace) { $ownedSources += @($result.trace.subscriptions.Values) }
        foreach ($source in $ownedSources) {
            try {
                Unregister-Event -SourceIdentifier $source -ErrorAction SilentlyContinue
                Get-Event -SourceIdentifier $source -ErrorAction SilentlyContinue | Remove-Event -ErrorAction SilentlyContinue
                if (@(Get-EventSubscriber -SourceIdentifier $source -ErrorAction SilentlyContinue).Count -ne 0) {
                    $result.cleanup.subscriptionsRemaining += $source
                }
                if (@(Get-Event -SourceIdentifier $source -ErrorAction SilentlyContinue).Count -ne 0) {
                    $result.cleanup.eventsRemaining += $source
                }
            } catch { $result.cleanup.errors += $_.Exception.Message }
        }
        try { $child.Dispose() } catch { $result.cleanup.errors += $_.Exception.Message }
        try { $timer.Dispose() } catch { $result.cleanup.errors += $_.Exception.Message }
        if ($null -eq $result.childReportRaw -and (Test-Path -LiteralPath $controlReport)) {
            try {
                if ((Get-Item -LiteralPath $controlReport).Length -le 16KB) { $result.childReportRaw = Get-Content -LiteralPath $controlReport -Raw }
            } catch { $result.cleanup.errors += "Partial report: $($_.Exception.Message)" }
        }
        if ($result.cleanup.errors.Count -gt 0 -or $result.cleanup.subscriptionsRemaining.Count -gt 0 -or
            $result.cleanup.eventsRemaining.Count -gt 0) {
            $result.status = 'failed'
            if ($null -eq $failure) {
                $failure = [InvalidOperationException]::new('Native control cleanup did not complete.')
                $result.error = @{ message = $failure.Message; type = $failure.GetType().FullName; stack = $null }
            }
        }
        $result.finishedAtUtc = [datetime]::UtcNow
        try { Save-InstalledPluginControlReport -Result $result -Path $ReportPath }
        catch {
            if ($null -eq $failure) { $failure = $_ }
            else { [Console]::Error.WriteLine("Native control report error: $($_.Exception.Message)") }
        }
    }
    if ($null -ne $failure) { throw $failure }
    return $result
}

Export-ModuleMember -Function Invoke-InstalledPluginExitControl
