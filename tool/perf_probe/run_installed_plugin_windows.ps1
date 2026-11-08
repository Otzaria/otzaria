#Requires -Version 7.0
param(
    [Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{40}$')][string]$Commit,
    [string]$FlutterVersion = '3.47.7'
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not $IsWindows) { throw 'This launcher requires Windows process trace events.' }
Import-Module (Join-Path $PSScriptRoot 'installed_plugin_windows_exit.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'installed_plugin_windows_diagnostics.psm1') -Force

foreach ($name in @('INSTALLED_PROBE_DATA', 'INSTALLED_PROBE_OUTPUT', 'INSTALLED_PROBE_REPORTS')) {
    $value = [Environment]::GetEnvironmentVariable($name)
    if ([string]::IsNullOrWhiteSpace($value) -or -not [IO.Path]::IsPathFullyQualified($value)) {
        throw "$name must be an absolute, isolated probe path."
    }
}
$output = Split-Path -Parent $env:INSTALLED_PROBE_OUTPUT
$reportPath = Join-Path $env:INSTALLED_PROBE_OUTPUT 'installed-plugin-report.json'
if (Test-Path -LiteralPath $reportPath) { throw 'The device report must not exist before this launch.' }
New-Item -ItemType Directory -Force $output | Out-Null
$receiptPath = Join-Path $output 'windows-native-exit.json'
if (Test-Path -LiteralPath $receiptPath) { throw 'The native receipt must not exist before this launch.' }
$trace = Start-InstalledPluginExitTrace
$receipt = @{
    schemaVersion = 1; status = 'running'; commit = $Commit; observer = $trace
    driverExitCode = $null; driverError = $null; reportReadError = $null
    reportSha256 = $null; deviceStatus = $null; nativeExit = $null; applicationErrors = $null
    fixtureErrorLog = @{ availability = 'unavailable'; reason = 'Not collected yet.' }
    observerContract = 'Kernel events and a retained process handle during flutter drive; no app polling or quiet-window queries.'
    successRequirements = 'Driver exit 0, final passing device report, identified native exit 0 or Dart teardown 0xFFFFFFFF, and no matching Application Error record.'
}
$report = $null
$exitCode = 1
$diagnostics = Start-InstalledPluginCrashDiagnostics -Directory (Join-Path $output 'windows-crash')
$receipt.crashDiagnostics = $diagnostics
try {
    $receipt | ConvertTo-Json -Depth 15 | Set-Content -LiteralPath $receiptPath -Encoding utf8
    $receipt.driverExitCode = Invoke-InstalledPluginLoggedCommand -Command flutter -LogPath (Join-Path $output 'run.log') -Arguments @(
        'drive', '--profile', '-d', 'windows', '--no-pub',
        '--driver=test_driver/installed_plugin_resource_probe.dart',
        '--target=integration_test/installed_plugin_resource_probe_test.dart',
        "--dart-define=INSTALLED_PROBE_FLUTTER_VERSION=$FlutterVersion",
        "--dart-define=INSTALLED_PROBE_COMMIT=$Commit",
        '--dart-define=INSTALLED_PROBE_IDLE_MS=1000'
    )
} catch { $receipt.driverError = $_.Exception.Message }
finally {
    try {
        try {
            $snapshotPath = Join-Path $output 'windows-device-report.json'
            Copy-Item -LiteralPath $reportPath -Destination $snapshotPath -ErrorAction Stop
            $receipt.reportSha256 = (Get-FileHash -LiteralPath $snapshotPath -Algorithm SHA256).Hash.ToLowerInvariant()
            $decoded = Get-Content -LiteralPath $snapshotPath -Raw | ConvertFrom-Json -AsHashtable
            if ($decoded -isnot [System.Collections.IDictionary]) { throw 'The device report must be a JSON object.' }
            $report = $decoded
            $receipt.deviceStatus = $report['status']
        } catch { $receipt.reportReadError = $_.Exception.Message }
        $observedPid = $null
        if ($null -ne $report -and ($report['pid'] -is [int] -or $report['pid'] -is [long]) -and
            $report['pid'] -gt 0 -and $report['pid'] -le [int]::MaxValue) { $observedPid = [int]$report['pid'] }
        try { Stop-InstalledPluginExitTrace -Trace $trace -ProcessId $observedPid }
        catch { $trace.availability = 'unavailable'; $trace.errors.Add($_.Exception.Message) }
        $receipt.nativeExit = Get-InstalledPluginExitEvidence -Trace $trace -Report $report
        $receipt.applicationErrors = Read-InstalledPluginApplicationErrors -Trace $trace -Identity $receipt.nativeExit
        try {
            $source = Join-Path $env:INSTALLED_PROBE_DATA 'app-fixture/app-data/logs/errors.txt'
            if (Test-Path -LiteralPath $source -PathType Leaf) {
                $destination = Join-Path $output 'fixture-errors.txt'
                Copy-Item -LiteralPath $source -Destination $destination -ErrorAction Stop
                $receipt.fixtureErrorLog = @{
                    availability = 'collected'; sha256 = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash.ToLowerInvariant()
                }
            } else { $receipt.fixtureErrorLog.reason = 'The isolated fixture did not produce an errors.txt file.' }
        } catch { $receipt.fixtureErrorLog.reason = $_.Exception.Message }
        $exitCode = Get-InstalledPluginRunExitCode -DriverExitCode $receipt.driverExitCode -Report $report `
            -ExitEvidence $receipt.nativeExit -ApplicationErrors $receipt.applicationErrors
    } finally {
        Complete-InstalledPluginCrashDiagnostics -State $diagnostics -RepositoryRoot (Get-Location).Path `
            -Identity $receipt.nativeExit -Failed ($exitCode -ne 0)
    }
    $exitCode = Save-InstalledPluginRunReceipt -Receipt $receipt -Path $receiptPath -ExitCode $exitCode
}
exit $exitCode
