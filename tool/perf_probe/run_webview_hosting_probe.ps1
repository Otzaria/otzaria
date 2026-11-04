#Requires -Version 7.0
<##
Paired manual-workload probe for #4110. No change to application defaults.
Run on a test profile; normal application activity can save tabs/documents.
The requested 'default' mode can fall back to HWND. Backend confirmation,
GPU/latency measurements and UI compatibility checks are separate requirements.
##>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Executable,
    [Parameter(Mandatory)][string]$OutDirectory,
    [Parameter(Mandatory)][string]$Scenario,
    [Parameter(Mandatory)][string]$DisplaySetup,
    [ValidateRange(1, 10)][int]$Pairs = 2,
    [ValidateRange(2, 600)][int]$Seconds = 30,
    [ValidateRange(250, 5000)][int]$IntervalMs = 1000
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not $IsWindows) { throw 'This collector requires Windows and PowerShell 7.' }
Import-Module (Join-Path $PSScriptRoot 'webview_hosting_probe.psm1') -Force
$exe = (Get-Item -LiteralPath $Executable).FullName
if (-not [System.IO.File]::Exists($exe)) { throw 'Executable must be a file.' }
$processName = [System.IO.Path]::GetFileNameWithoutExtension($exe)
if (Get-Process -Name $processName -ErrorAction SilentlyContinue) {
    throw 'Close existing application instances before starting the probe.'
}
$output = [System.IO.Path]::GetFullPath($OutDirectory)
if (Test-Path -LiteralPath $output) { throw 'Output directory already exists; refusing to overwrite it.' }
[void][System.IO.Directory]::CreateDirectory($output)
$metadata = [ordered]@{
    schemaVersion = 1
    createdUtc = [DateTimeOffset]::UtcNow.ToString('o')
    executableSha256 = (Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash
    scenario = $Scenario
    displaySetup = $DisplaySetup
    os = [System.Environment]::OSVersion.VersionString
    logicalProcessors = [System.Environment]::ProcessorCount
    pairs = $Pairs
    seconds = $Seconds
    intervalMs = $IntervalMs
    memoryUnit = 'bytes'
    cpuUnit = 'percentOfOneCore'
    actualBackend = 'not verified by this tool'
    gpuMeasurement = 'not collected'
    startupLatency = 'not collected: measurement starts after manual setup'
    frameLatency = 'not collected: use the application diagnostics log'
    gpuAdapters = @()
}
try {
    $metadata.gpuAdapters = @(Get-CimInstance Win32_VideoController |
        Select-Object Name, DriverVersion, CurrentHorizontalResolution, CurrentVerticalResolution)
} catch {
    $metadata.gpuAdapters = @(@{ error = 'GPU metadata unavailable' })
}
$metadata | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $output 'metadata.json') -Encoding utf8

for ($pair = 0; $pair -lt $Pairs; $pair++) {
    # AB/BA reduces order bias; it does not eliminate cache or workload effects.
    $modes = if ($pair % 2 -eq 0) { @('default', 'hwnd') } else { @('hwnd', 'default') }
    foreach ($mode in $modes) {
        if (Get-Process -Name $processName -ErrorAction SilentlyContinue) {
            throw 'An application instance is still running. No process was terminated.'
        }
        $trialName = ('{0:D2}-{1}' -f ($pair + 1), $mode)
        $writer = $null
        $app = $null
        try {
            $app = [System.Diagnostics.Process]::Start((New-WebViewHostingStartInfo -Executable $exe -Mode $mode))
            if ($null -eq $app) { throw 'Could not launch the application.' }
            Write-Host "Trial $trialName; PID $($app.Id). Prepare exactly this workload: $Scenario"
            Write-Host 'Keep the same plugins, documents, viewport, DPI and window state in both modes.'
            [void](Read-Host 'Press Enter when setup is complete; sampling starts immediately')
            $app.Refresh()
            if ($app.HasExited) { throw 'The launched process exited during setup (possibly single-instance forwarding).' }
            $rootStart = $app.StartTime.ToUniversalTime().ToString('o')
            $writer = [System.IO.StreamWriter]::new((Join-Path $output "$trialName.jsonl"), $false, [System.Text.UTF8Encoding]::new($false))
            $writer.WriteLine((@{
                type = 'trial'; requestedMode = $mode; processId = $app.Id
                startedUtc = $rootStart; scenario = $Scenario
                actualBackend = $null
            } | ConvertTo-Json -Compress))
            $clock = [System.Diagnostics.Stopwatch]::StartNew()
            $previous = $null
            while ($clock.Elapsed.TotalSeconds -lt $Seconds) {
                $iterationStart = $clock.Elapsed.TotalMilliseconds
                $app.Refresh()
                if ($app.HasExited) { throw 'The application exited while sampling; trial is incomplete.' }
                $all = @(Get-CimInstance Win32_Process | Select-Object ProcessId, ParentProcessId)
                $ids = @(Get-WebViewHostingTreeIds -RootProcessId $app.Id -Processes $all)
                $missing = 0
                $records = @(foreach ($processId in $ids) {
                    $process = $null
                    try {
                        $process = Get-Process -Id $processId -ErrorAction Stop
                        $started = $process.StartTime.ToUniversalTime().ToString('o')
                        if ($processId -eq $app.Id -and $started -ne $rootStart) {
                            throw 'Root process identity changed.'
                        }
                        [pscustomobject]@{
                            processId = $processId; startedUtc = $started
                            name = $process.ProcessName
                            cpuSeconds = $process.TotalProcessorTime.TotalSeconds
                            privateCommitBytes = $process.PrivateMemorySize64
                            workingSetBytes = $process.WorkingSet64
                        }
                    } catch {
                        $missing++
                    } finally {
                        if ($null -ne $process) { $process.Dispose() }
                    }
                })
                $sample = [pscustomobject]@{
                    type = 'sample'
                    utc = [DateTimeOffset]::UtcNow.ToString('o')
                    elapsedSeconds = $clock.Elapsed.TotalSeconds
                    missingProcesses = $missing
                    processes = $records
                }
                $cpu = Get-WebViewHostingCpuPercent -Previous $previous -Current $sample
                $sample | Add-Member -NotePropertyName observedCpuPercentOfOneCore -NotePropertyValue $cpu
                $writer.WriteLine(($sample | ConvertTo-Json -Depth 6 -Compress))
                $writer.Flush()
                $previous = $sample
                $delay = [math]::Max(0, $IntervalMs - ($clock.Elapsed.TotalMilliseconds - $iterationStart))
                if ($delay -gt 0) { Start-Sleep -Milliseconds ([int]$delay) }
            }
            $writer.WriteLine((@{ type = 'end'; complete = $true; elapsedSeconds = $clock.Elapsed.TotalSeconds } | ConvertTo-Json -Compress))
            $writer.Flush()
            Write-Host "Saved $trialName. Close the application normally, including any save prompts."
            [void](Read-Host 'Press Enter after the application has closed')
            $app.Refresh()
            if (-not $app.HasExited) { throw 'Application is still running. No process was terminated.' }
        } finally {
            if ($null -ne $writer) { $writer.Dispose() }
            if ($null -ne $app) { $app.Dispose() }
        }
    }
}
Write-Host "Raw results: $output. A trial without a complete end record must not be compared."
