#Requires -Version 7.0
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'installed_plugin_windows_exit.psm1')

function New-InstalledPluginControlChildScript {
    return @'
$ErrorActionPreference = 'Stop'
Import-Module $args[0]
$identity = [InstalledPluginProbe.WindowsProcess]::CurrentIdentity()
$micros = [long](([datetime]::UtcNow.Ticks - [datetime]::UnixEpoch.Ticks) / 10)
$runId = "$PID-$micros"
$hello = @{
    version = 1; kind = 'hello'; campaignId = $env:INSTALLED_PROBE_WINDOWS_CAMPAIGN
    token = $env:INSTALLED_PROBE_WINDOWS_TOKEN; pid = $PID; runId = $runId
    creationFileTime = $identity.CreationFileTime.ToString([Globalization.CultureInfo]::InvariantCulture)
}
$client = [Net.Sockets.TcpClient]::new()
$cancellation = [Threading.CancellationTokenSource]::new(15000)
try {
    $client.ConnectAsync([Net.IPAddress]::Loopback, [int]$env:INSTALLED_PROBE_WINDOWS_PORT, $cancellation.Token).AsTask().GetAwaiter().GetResult() | Out-Null
    $stream = $client.GetStream()
    $bytes = [Text.Encoding]::UTF8.GetBytes(($hello | ConvertTo-Json -Compress))
    $stream.Write($bytes, 0, $bytes.Length)
    $client.Client.Shutdown([Net.Sockets.SocketShutdown]::Send)
    $response = [InstalledPluginProbe.LifetimeObserver]::ReadBoundedAsync($stream, $cancellation.Token).GetAwaiter().GetResult()
    $ack = [Text.Encoding]::UTF8.GetString($response) | ConvertFrom-Json -AsHashtable
    if ($ack.kind -ne 'ready' -or $ack.version -ne 1 -or $ack.pid -ne $PID -or $ack.runId -cne $runId -or
        $ack.campaignId -cne $hello.campaignId -or $ack.token -cne $hello.token -or
        $ack.creationFileTime -cne $hello.creationFileTime -or $ack.bootstrapQuiescent -ne $true) {
        throw 'The native child did not receive its exact lifetime acknowledgement.'
    }
    $ack.Remove('token')
    Save-InstalledPluginJson -Path $args[1] -Value @{
        pid = $PID; runId = $runId; platform = 'windows'; buildMode = 'profile'; windowsLifetime = $ack
    }
} finally { $client.Dispose(); $cancellation.Dispose() }
exit 37
'@
}

function Invoke-InstalledPluginExitControl {
    param([Parameter(Mandatory)][string]$Directory, [Parameter(Mandatory)][string]$ReportPath)
    if (Test-Path -LiteralPath $ReportPath) { throw 'The native control evidence must not already exist.' }
    $result = @{
        schemaVersion = 2; status = 'running'; stage = 'arm'; error = $null
        hostPlatform = [Runtime.InteropServices.RuntimeInformation]::OSDescription
        powerShellVersion = $PSVersionTable.PSVersion.ToString()
        startedAtUtc = [datetime]::UtcNow; finishedAtUtc = $null
        trace = $null; observation = $null; childReport = $null; childReportRaw = $null
        child = @{ pid = $null; started = $false; exited = $false; exitCode = $null; terminatedByControl = $false }
        cleanup = @{ childExited = $false; observerDisposed = $false; subscriptionsRemaining = @(); eventsRemaining = @(); errors = @() }
    }
    $failure = $null
    $observer = $null
    $child = [Diagnostics.Process]::new()
    $foreignId = 'foreign-test-' + [guid]::NewGuid().ToString('N')
    $timer = [Timers.Timer]::new(60000)
    $controlReport = Join-Path $Directory 'control-report.json'
    try {
        Register-ObjectEvent -InputObject $timer -EventName Elapsed -SourceIdentifier $foreignId | Out-Null
        New-Event -SourceIdentifier $foreignId | Out-Null
        $executable = Join-Path $PSHOME $(if ($IsWindows) { 'pwsh.exe' } else { 'pwsh' })
        $campaign = [guid]::NewGuid().ToString('N')
        $token = [Convert]::ToHexString([Security.Cryptography.RandomNumberGenerator]::GetBytes(32)).ToLowerInvariant()
        $observer = Start-InstalledPluginLifetimeObserver -Executable $executable -CampaignId $campaign -Token $token -StartupTimeoutMilliseconds 15000
        $controlPath = Join-Path $Directory 'native-control.ps1'
        $scriptBytes = [Text.UTF8Encoding]::new($false).GetBytes((New-InstalledPluginControlChildScript))
        $scriptFile = $null
        try {
            $scriptFile = [IO.File]::Open($controlPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
            $scriptFile.Write($scriptBytes, 0, $scriptBytes.Length)
        } finally { if ($null -ne $scriptFile) { $scriptFile.Dispose() } }
        $result.stage = 'child'
        $child.StartInfo = [Diagnostics.ProcessStartInfo]::new($executable)
        $child.StartInfo.UseShellExecute = $false
        $child.StartInfo.Environment['INSTALLED_PROBE_WINDOWS_PORT'] = $observer.Port.ToString()
        $child.StartInfo.Environment['INSTALLED_PROBE_WINDOWS_CAMPAIGN'] = $campaign
        $child.StartInfo.Environment['INSTALLED_PROBE_WINDOWS_TOKEN'] = $token
        foreach ($argument in @('-NoLogo', '-NoProfile', '-File', $controlPath,
            (Join-Path $PSScriptRoot 'installed_plugin_windows_exit.psm1'), $controlReport)) { $child.StartInfo.ArgumentList.Add($argument) }
        $result.child.started = $child.Start()
        if (-not $result.child.started) { throw 'The native control could not start its child process.' }
        $result.child.pid = $child.Id
        $result.child.exited = $child.WaitForExit(20000)
        if (-not $result.child.exited) { throw 'The native control child exceeded its bootstrap and exit deadline.' }
        $result.child.exitCode = $child.ExitCode
        if ($child.ExitCode -ne 37) { throw "The native control child exited $($child.ExitCode), expected 37." }
        $result.stage = 'observe'
        $result.trace = Stop-InstalledPluginLifetimeObserver $observer
        if ((Get-Item -LiteralPath $controlReport).Length -gt 16KB) { throw 'The native control child report exceeds 16 KiB.' }
        $result.childReportRaw = Get-Content -LiteralPath $controlReport -Raw
        $result.childReport = $result.childReportRaw | ConvertFrom-Json -AsHashtable
        if ($result.childReport.pid -ne $child.Id) { throw 'The native control report does not belong to the owned child.' }
        $result.observation = Get-InstalledPluginExitEvidence $result.trace $result.childReport
        if ($result.observation.availability -ne 'collected') {
            throw "The retained handle did not identify the controlled child: $($result.observation.reason)"
        }
        if ($result.observation.exitStatus -ne 37) { throw "Native child exit status was $($result.observation.exitStatus), expected 37." }
        $result.stage = 'verify-cleanup'
        if (@(Get-EventSubscriber -SourceIdentifier $foreignId).Count -ne 1 -or
            @(Get-Event -SourceIdentifier $foreignId).Count -ne 1) { throw 'Observer cleanup changed a foreign subscription or queued event.' }
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
        if ($null -ne $observer) {
            try { $observer.Dispose(); $result.cleanup.observerDisposed = $true }
            catch { $result.cleanup.errors += $_.Exception.Message }
            try { if ($null -eq $result.trace) { $result.trace = $observer.SnapshotJson() | ConvertFrom-Json -AsHashtable } }
            catch { $result.cleanup.errors += "Partial observer: $($_.Exception.Message)" }
        }
        try {
            Unregister-Event -SourceIdentifier $foreignId -ErrorAction SilentlyContinue
            Get-Event -SourceIdentifier $foreignId -ErrorAction SilentlyContinue | Remove-Event -ErrorAction SilentlyContinue
            if (@(Get-EventSubscriber -SourceIdentifier $foreignId -ErrorAction SilentlyContinue).Count -ne 0) {
                $result.cleanup.subscriptionsRemaining += $foreignId
            }
            if (@(Get-Event -SourceIdentifier $foreignId -ErrorAction SilentlyContinue).Count -ne 0) {
                $result.cleanup.eventsRemaining += $foreignId
            }
        } catch { $result.cleanup.errors += $_.Exception.Message }
        try { $child.Dispose() } catch { $result.cleanup.errors += $_.Exception.Message }
        try { $timer.Dispose() } catch { $result.cleanup.errors += $_.Exception.Message }
        try {
            if ($null -eq $result.childReportRaw -and (Test-Path -LiteralPath $controlReport) -and
                (Get-Item -LiteralPath $controlReport).Length -le 16KB) { $result.childReportRaw = Get-Content -LiteralPath $controlReport -Raw }
        } catch { $result.cleanup.errors += "Partial report: $($_.Exception.Message)" }
        if ($result.cleanup.errors.Count -gt 0 -or $result.cleanup.subscriptionsRemaining.Count -gt 0 -or $result.cleanup.eventsRemaining.Count -gt 0) {
            $result.status = 'failed'
            if ($null -eq $failure) {
                $failure = [InvalidOperationException]::new('Native control cleanup did not complete.')
                $result.error = @{ message = $failure.Message; type = $failure.GetType().FullName; stack = $null }
            }
        }
        $result.finishedAtUtc = [datetime]::UtcNow
        try { Save-InstalledPluginJson -Value $result -Path $ReportPath }
        catch {
            $saveError = $_.Exception.Message
            $result.status = 'failed'
            if ($null -eq $failure) {
                $failure = $_
                $result.error = @{ message = $saveError; type = $_.Exception.GetType().FullName; stack = $_.ScriptStackTrace }
            }
            try { Write-InstalledPluginDiagnosticFallback -Value $result -SaveError $saveError }
            catch {
                $primary = if ($failure -is [Management.Automation.ErrorRecord]) { $failure.Exception } else { $failure }
                $primary.Data['diagnosticFallbackError'] = $_.Exception.Message
            }
        }
    }
    if ($null -ne $failure) { throw $failure }
    return $result
}

Export-ModuleMember -Function Invoke-InstalledPluginExitControl
