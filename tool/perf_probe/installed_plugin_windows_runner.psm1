#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'installed_plugin_windows_exit.psm1')

function Add-InstalledPluginRunError {
    param([hashtable]$Receipt, [string]$Stage, [string]$Message)
    $bounded = $Message.Substring(0, [Math]::Min(2048, $Message.Length))
    $Receipt.diagnosticErrors += "$($Stage): $bounded"
    if ($null -eq $Receipt.firstError) { $Receipt.firstError = @{ stage = $Stage; message = $bounded } }
}

function Copy-InstalledPluginFixtureErrors {
    param([string]$Source, [string]$Destination)
    if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) {
        return @{ availability = 'notProduced'; reason = 'The isolated fixture did not produce errors.txt.' }
    }
    $inputFile = $null; $outputFile = $null
    try {
        $inputFile = [IO.File]::OpenRead($Source)
        $outputFile = [IO.File]::Open($Destination, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::Read)
        $buffer = [byte[]]::new(16384); $remaining = 1MB
        while ($remaining -gt 0) {
            $count = $inputFile.Read($buffer, 0, [Math]::Min($buffer.Length, $remaining))
            if ($count -eq 0) { break }
            $outputFile.Write($buffer, 0, $count); $remaining -= $count
        }
        $outputFile.Flush($true)
        return @{ availability = 'collected'; truncated = $inputFile.Position -lt $inputFile.Length }
    } finally {
        try { if ($null -ne $outputFile) { $outputFile.Dispose() } }
        finally { if ($null -ne $inputFile) { $inputFile.Dispose() } }
    }
}

function Invoke-InstalledPluginWindowsRun {
    param([Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{40}$')][string]$Commit,
        [string]$FlutterVersion = '3.47.7',
        [string]$Executable = ([IO.Path]::GetFullPath((Join-Path (Get-Location).Path 'build/windows/x64/runner/Profile/otzaria.exe'))))
    foreach ($name in @('INSTALLED_PROBE_DATA', 'INSTALLED_PROBE_OUTPUT', 'INSTALLED_PROBE_REPORTS')) {
        $value = [Environment]::GetEnvironmentVariable($name)
        if ([string]::IsNullOrWhiteSpace($value) -or -not [IO.Path]::IsPathFullyQualified($value)) {
            throw "$name must be an absolute, isolated probe path."
        }
    }
    $output = Split-Path -Parent $env:INSTALLED_PROBE_OUTPUT
    $reportPath = Join-Path $env:INSTALLED_PROBE_OUTPUT 'installed-plugin-report.json'
    New-Item -ItemType Directory -Force $output | Out-Null
    $receiptPath = Join-Path $output 'windows-native-exit.json'
    $startPath = Join-Path $output 'windows-native-exit-start.json'
    $snapshotPath = Join-Path $output 'windows-device-report.json'
    foreach ($path in @($reportPath, $receiptPath, $startPath, $snapshotPath, (Join-Path $output 'run.log'), (Join-Path $output 'fixture-errors.txt'))) {
        if (Test-Path -LiteralPath $path) { throw "A fresh launch must preserve existing evidence: $path" }
    }
    $receipt = @{
        schemaVersion = 2; status = 'running'; commit = $Commit; observer = $null
        driverExitCode = $null; driverError = $null; reportReadError = $null; firstError = $null; diagnosticErrors = @()
        reportSha256 = $null; deviceStatus = $null; nativeExit = $null; applicationErrors = $null; stepExitCode = $null
        fixtureErrorLog = @{ availability = 'unavailable'; reason = 'Not collected yet.' }
        observerContract = 'One authenticated bootstrap, exact native creation time and retained handle; no observer work during measured windows; bounded wait only after flutter drive.'
        successRequirements = 'Driver exit 0, final passing framework report for this commit, exact acknowledged native lifetime, exit 0 or 0xFFFFFFFF, complete diagnostics and no correlated Application Error.'
    }
    $observer = $null; $report = $null; $exitCode = 1
    $previousEnvironment = @{}
    try {
        $campaign = [guid]::NewGuid().ToString('N')
        $token = [Convert]::ToHexString([Security.Cryptography.RandomNumberGenerator]::GetBytes(32)).ToLowerInvariant()
        $observer = Start-InstalledPluginLifetimeObserver -Executable $Executable -CampaignId $campaign -Token $token
        $launchEnvironment = @{
            INSTALLED_PROBE_WINDOWS_PORT = $observer.Port.ToString()
            INSTALLED_PROBE_WINDOWS_CAMPAIGN = $campaign
            INSTALLED_PROBE_WINDOWS_TOKEN = $token
        }
        foreach ($name in $launchEnvironment.Keys) {
            $previousEnvironment[$name] = [Environment]::GetEnvironmentVariable($name)
            [Environment]::SetEnvironmentVariable($name, $launchEnvironment[$name])
        }
        Save-InstalledPluginJson -Path $startPath -Value @{
            schemaVersion = 2; status = 'armed'; commit = $Commit; campaignId = $campaign
            armedAtUtc = $observer.ArmedAtUtc; expectedExecutable = $Executable
        }
        $driver = Invoke-InstalledPluginLoggedCommand -Command flutter -LogPath (Join-Path $output 'run.log') -Arguments @(
            'drive', '--profile', '-d', 'windows', '--no-pub',
            '--driver=test_driver/installed_plugin_resource_probe.dart',
            '--target=integration_test/installed_plugin_resource_probe_test.dart',
            "--dart-define=INSTALLED_PROBE_FLUTTER_VERSION=$FlutterVersion",
            "--dart-define=INSTALLED_PROBE_COMMIT=$Commit", '--dart-define=INSTALLED_PROBE_IDLE_MS=1000'
        )
        $receipt.driverExitCode = $driver.exitCode
        if ($null -ne $driver.exitCode -and $driver.exitCode -ne 0) {
            $receipt.firstError = @{ stage = 'driver'; message = "flutter drive exited $($driver.exitCode)."; exitCode = $driver.exitCode }
        }
        $receipt.driverError = $driver.error
        if ($null -ne $driver.error) { Add-InstalledPluginRunError $receipt 'driver-log' $driver.error }
    } catch { Add-InstalledPluginRunError $receipt 'launch' $_.Exception.Message }
    finally {
        if ($null -ne $observer) {
            try { $receipt.observer = Stop-InstalledPluginLifetimeObserver $observer }
            catch { Add-InstalledPluginRunError $receipt 'observer' $_.Exception.Message }
            try { $observer.Dispose() }
            catch { Add-InstalledPluginRunError $receipt 'observer-cleanup' $_.Exception.Message }
            try {
                if ($null -eq $receipt.observer) { $receipt.observer = $observer.SnapshotJson() | ConvertFrom-Json -AsHashtable }
            } catch { Add-InstalledPluginRunError $receipt 'partial-observer' $_.Exception.Message }
        }
        foreach ($name in $previousEnvironment.Keys) {
            try { [Environment]::SetEnvironmentVariable($name, $previousEnvironment[$name]) }
            catch { Add-InstalledPluginRunError $receipt 'environment-cleanup' $_.Exception.Message }
        }
        try {
            if ((Get-Item -LiteralPath $reportPath).Length -gt 16MB) { throw 'The device report exceeds 16 MiB; the original remains in the device directory.' }
            [IO.File]::Copy($reportPath, $snapshotPath, $false)
            $receipt.reportSha256 = (Get-FileHash -LiteralPath $snapshotPath -Algorithm SHA256).Hash.ToLowerInvariant()
            $decoded = Get-Content -LiteralPath $snapshotPath -Raw | ConvertFrom-Json -AsHashtable
            if ($decoded -isnot [Collections.IDictionary]) { throw 'The device report must be a JSON object.' }
            $report = $decoded; $receipt.deviceStatus = $report['status']
            if ($report['commit'] -cne $Commit) { throw 'The device report does not identify the requested source commit.' }
        } catch {
            $receipt.reportReadError = $_.Exception.Message
            Add-InstalledPluginRunError $receipt 'device-report' $_.Exception.Message
        }
        try { $receipt.nativeExit = Get-InstalledPluginExitEvidence -Trace $receipt.observer -Report $report }
        catch {
            $receipt.nativeExit = @{ availability = 'unavailable'; reason = $_.Exception.Message }
            Add-InstalledPluginRunError $receipt 'exit-evidence' $_.Exception.Message
        }
        if ($receipt.nativeExit.availability -ne 'collected') {
            $detail = [string]$receipt.nativeExit.reason
            if ($null -ne $receipt.observer -and $receipt.observer.ContainsKey('errors')) {
                $detail += ' ' + ($receipt.observer.errors -join '; ')
            }
            Add-InstalledPluginRunError $receipt 'native-exit' $detail
        }
        try { $receipt.applicationErrors = Read-InstalledPluginApplicationErrors -Trace $receipt.observer -Identity $receipt.nativeExit }
        catch {
            $receipt.applicationErrors = @{ availability = 'unavailable'; reason = $_.Exception.Message; events = @(); truncated = $false }
            Add-InstalledPluginRunError $receipt 'application-errors' $_.Exception.Message
        }
        try {
            $receipt.fixtureErrorLog = Copy-InstalledPluginFixtureErrors -Source (Join-Path $env:INSTALLED_PROBE_DATA 'app-fixture/app-data/logs/errors.txt') -Destination (Join-Path $output 'fixture-errors.txt')
            if ($receipt.fixtureErrorLog.availability -eq 'collected' -and $receipt.fixtureErrorLog.truncated) {
                Add-InstalledPluginRunError $receipt 'fixture-errors' 'The fixture error log exceeds 1 MiB; bounded partial evidence was saved.'
            }
        } catch {
            $receipt.fixtureErrorLog.reason = $_.Exception.Message
            Add-InstalledPluginRunError $receipt 'fixture-errors' $_.Exception.Message
        }
        $exitCode = Get-InstalledPluginRunExitCode -DriverExitCode $receipt.driverExitCode -Report $report `
            -ExitEvidence $receipt.nativeExit -ApplicationErrors $receipt.applicationErrors -DiagnosticErrors $receipt.diagnosticErrors
        if ($exitCode -ne 0 -and $null -eq $receipt.firstError) {
            Add-InstalledPluginRunError $receipt 'validation' 'The final framework, native exit or Application Error evidence did not satisfy the run contract.'
        }
        $receipt.status = if ($exitCode -eq 0) { 'passed' } else { 'failed' }
        $receipt.stepExitCode = $exitCode
        try { Save-InstalledPluginJson -Path $receiptPath -Value $receipt }
        catch {
            Add-InstalledPluginRunError $receipt 'final-receipt' $_.Exception.Message
            if ($exitCode -eq 0) { $exitCode = 1 }
            $receipt.status = 'failed'; $receipt.stepExitCode = $exitCode
            try { Write-InstalledPluginDiagnosticFallback -Value $receipt -SaveError $receipt.diagnosticErrors[-1] }
            catch { Add-InstalledPluginRunError $receipt 'stderr-fallback' $_.Exception.Message }
        }
    }
    return $exitCode
}

Export-ModuleMember -Function Invoke-InstalledPluginWindowsRun
