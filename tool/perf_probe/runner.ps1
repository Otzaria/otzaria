# Invoked by run_perf_probe.ps1. Build once, then launch only the owned binary.
#Requires -Version 7.4
param(
  [ValidateSet('profile', 'debug', 'release')][string]$Mode = 'profile',
  [ValidateSet('cold', 'warm')][string]$CacheState = 'cold',
  [ValidateRange(0, 10)][int]$Warmup = 1,
  [ValidateRange(1, 100)][int]$Repetitions = 5,
  [ValidateRange(1, 30)][int]$Launches = 3,
  [string]$OutputDirectory = '',
  [string]$Baseline = '',
  [string]$HardwareId = '',
  [ValidateRange(60, 7200)][int]$TimeoutSeconds = 1200
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not $IsWindows) { throw 'The automated desktop runner requires Windows. See README.md for other platforms.' }
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
if ($Baseline) { $Baseline = [IO.Path]::GetFullPath($Baseline, $PWD.Path) }
$runDir = if ($OutputDirectory) { [IO.Path]::GetFullPath($OutputDirectory, $PWD.Path) } else {
  Join-Path $repo ("build/perf_probe/run_" + (Get-Date -Format 'yyyyMMdd_HHmmss') + '_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
}
if (Test-Path -LiteralPath $runDir) { throw "Output directory already exists: $runDir" }
if (Get-Process -Name otzaria -ErrorAction SilentlyContinue) {
  throw 'Close Otzaria first: the native single-instance guard is shared with benchmark builds.'
}
New-Item -ItemType Directory -Path $runDir | Out-Null

function Write-PerfJson([string]$Path, $Value) {
  $Value | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $Path -Encoding utf8
}

function Merge-PerfOutputs([string[]]$Directories) {
  $journal = [IO.StreamWriter]::new((Join-Path $runDir 'phases.jsonl'), $false, [Text.UTF8Encoding]::new($false))
  $samples = [IO.StreamWriter]::new((Join-Path $runDir 'samples.csv'), $false, [Text.UTF8Encoding]::new($false))
  $errors = [IO.StreamWriter]::new((Join-Path $runDir 'samples.csv.errors.jsonl'), $false, [Text.UTF8Encoding]::new($false))
  $hasHeader = $false
  try {
    foreach ($directory in $Directories) {
      $phases = Join-Path $directory 'phases.jsonl'
      if (Test-Path -LiteralPath $phases) {
        foreach ($line in [IO.File]::ReadLines($phases)) { $journal.WriteLine($line) }
      }
      $csv = Join-Path $directory 'samples.csv'
      if (Test-Path -LiteralPath "$csv.errors.jsonl") {
        foreach ($line in [IO.File]::ReadLines("$csv.errors.jsonl")) { $errors.WriteLine($line) }
      }
      if (Test-Path -LiteralPath $csv) {
        $first = $true
        foreach ($line in [IO.File]::ReadLines($csv)) {
          if (-not $first -or -not $hasHeader) { $samples.WriteLine($line) }
          $first = $false
          $hasHeader = $true
        }
      }
    }
  } finally { $journal.Dispose(); $samples.Dispose(); $errors.Dispose() }
}

function Invoke-PerfLaunch([string]$Executable, [string]$Directory,
                           [string]$DataDirectory, [string]$Cache, [int]$Index,
                           [bool]$PreparationOnly = $false) {
  New-Item -ItemType Directory -Path $Directory | Out-Null
  $csv = Join-Path $Directory 'samples.csv'
  $stop = Join-Path $Directory 'sampler.stop'
  $completion = Join-Path $Directory 'completion.json'
  $sampler = $null
  $process = $null
  try {
    $process = Start-Process -FilePath $Executable -WorkingDirectory (Split-Path $Executable) `
      -PassThru -RedirectStandardOutput (Join-Path $Directory 'stdout.log') `
      -RedirectStandardError (Join-Path $Directory 'stderr.log') -Environment @{
        PERF_OUTPUT_DIR = $Directory; PERF_DATA_DIR = $DataDirectory
        PERF_CACHE_STATE = $Cache; PERF_LAUNCH_INDEX = "$Index"
        PERF_WARMUP = "$Warmup"; PERF_REPETITIONS = "$Repetitions"
        PERF_PREPARE_ONLY = $(if ($PreparationOnly) { '1' } else { '0' })
      }
    $ticks = $process.StartTime.ToUniversalTime().Ticks
    $ticks -= $ticks % 10000
    Write-PerfJson (Join-Path $Directory 'launch.json') @{
      pid = $process.Id; identityStartTicks = "$ticks"; launchIndex = $Index
      processStartEpochMs = ([DateTimeOffset]$process.StartTime).ToUnixTimeMilliseconds()
    }
    if (-not $PreparationOnly) {
      $sampler = Start-Job -FilePath (Join-Path $PSScriptRoot 'sample_resources.ps1') `
        -ArgumentList $csv, $stop, $process.Id, $ticks, 'otzaria', 500, 2000, $Index
    }
    $clock = [Diagnostics.Stopwatch]::StartNew()
    while (-not (Test-Path -LiteralPath $completion)) {
      $process.Refresh()
      if ($process.HasExited) { throw "Benchmark exited before completion (exit $($process.ExitCode))." }
      if ($clock.Elapsed.TotalSeconds -gt $TimeoutSeconds) { throw "Benchmark exceeded ${TimeoutSeconds}s." }
      if ($null -ne $sampler -and $sampler.State -in @('Failed', 'Completed', 'Stopped')) {
        Receive-Job $sampler -ErrorAction Continue
        throw 'Resource sampler exited before benchmark completion.'
      }
      Start-Sleep -Milliseconds 200
    }
    $result = Get-Content -LiteralPath $completion -Raw | ConvertFrom-Json
    if ($result.status -ne 'passed') { throw "Benchmark failed; inspect $completion" }
    $process.Refresh()
    if ($process.HasExited -and $process.ExitCode -ne 0) {
      throw "Benchmark exited unsuccessfully (exit $($process.ExitCode))."
    }
  } finally {
    try {
      New-Item -ItemType File -Path $stop -Force | Out-Null
      if ($null -ne $sampler) {
        try {
          $finished = Wait-Job $sampler -Timeout 15
          if ($null -eq $finished) { Stop-Job $sampler }
          Receive-Job $sampler -ErrorAction Continue
        } finally { Remove-Job $sampler -Force }
      }
    } finally {
      if ($null -ne $process) {
        try {
          if (-not $process.HasExited) {
            [void]$process.CloseMainWindow()
            if (-not $process.WaitForExit(5000)) { $process.Kill($true); [void]$process.WaitForExit(5000) }
          }
        } finally { $process.Dispose() }
      }
    }
  }
  if ($PreparationOnly) { return }
  $statusPath = "$csv.status.json"
  if (-not (Test-Path -LiteralPath $statusPath) -or
      -not (Get-Content -LiteralPath $statusPath -Raw | ConvertFrom-Json).complete) {
    throw "Resource sampling was incomplete; inspect $Directory"
  }
}

$failure = $null
$launchDirs = [Collections.Generic.List[string]]::new()
$manifest = @{}
Push-Location $repo
try {
  & flutter pub get --enforce-lockfile
  if ($LASTEXITCODE -ne 0) { throw 'Pinned dependency resolution failed.' }
  $commit = (& git rev-parse HEAD).Trim()
  if ($LASTEXITCODE -ne 0) { throw 'Cannot identify source commit.' }
  $dirty = -not [string]::IsNullOrWhiteSpace((& git status --porcelain | Out-String))
  $sdk = (& flutter --version --machine | Out-String | ConvertFrom-Json)
  if ($LASTEXITCODE -ne 0) { throw 'Cannot identify Flutter SDK.' }
  $cpu = @(Get-CimInstance Win32_Processor | Sort-Object Name, NumberOfLogicalProcessors |
    ForEach-Object { [ordered]@{ name = $_.Name; logicalProcessors = $_.NumberOfLogicalProcessors } })
  $gpu = @(Get-CimInstance Win32_VideoController | Sort-Object Name, DriverVersion |
    ForEach-Object { [ordered]@{ name = $_.Name; driverVersion = $_.DriverVersion } })
  $system = Get-CimInstance Win32_ComputerSystem
  $os = Get-CimInstance Win32_OperatingSystem
  if (-not $HardwareId) {
    $fingerprint = [ordered]@{ machine = $env:COMPUTERNAME; cpu = $cpu; gpu = $gpu
      memory = $system.TotalPhysicalMemory } | ConvertTo-Json -Depth 10 -Compress
    $HardwareId = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($fingerprint))).ToLowerInvariant()
  }
  $manifest = @{
    schemaVersion = 2; protocolVersion = 2; commit = $commit; dirty = $dirty
    buildMode = $Mode; cacheState = $CacheState; hardwareId = $HardwareId
    os = "windows-$($os.Version)-$($os.BuildNumber)"; flutterVersion = $sdk.frameworkRevision
    warmup = $Warmup; repetitions = $Repetitions; launchCount = $Launches
    sampling = @{ intervalMs = 500; treeRefreshMs = 2000; heap = ($Mode -ne 'release') }
    machine = @{ cpu = $cpu; gpu = $gpu; memoryBytes = $system.TotalPhysicalMemory }
    startedAtUtc = [DateTime]::UtcNow.ToString('o'); status = 'running'
    coldDefinition = 'fresh application data; OS file cache is not flushed'
    startupOrigin = 'Dart main; fixture preparation and native pre-main are excluded'
  }
  Write-PerfJson (Join-Path $runDir 'manifest.json') $manifest
  & flutter build windows "--$Mode" --no-pub --target=integration_test/perf_resource_probe_test.dart `
    --dart-define=SENTRY_DSN= --dart-define=INTEGRATION_TEST_SHOULD_REPORT_RESULTS_TO_NATIVE=false `
    2>&1 | Tee-Object -FilePath (Join-Path $runDir 'build.log')
  if ($LASTEXITCODE -ne 0) { throw "Flutter build failed ($LASTEXITCODE)." }
  if ((& git rev-parse HEAD).Trim() -ne $commit) { throw 'HEAD changed while building; rerun on a stable checkout.' }
  $manifest.dirty = $dirty -or -not [string]::IsNullOrWhiteSpace((& git status --porcelain | Out-String))
  $modeFolder = (Get-Culture).TextInfo.ToTitleCase($Mode)
  $executable = Join-Path $repo "build/windows/x64/runner/$modeFolder/otzaria.exe"
  if (-not (Test-Path -LiteralPath $executable)) { throw "Built executable not found: $executable" }
  $manifest.binarySha256 = (Get-FileHash -LiteralPath $executable -Algorithm SHA256).Hash.ToLowerInvariant()
  $warmData = Join-Path $runDir 'data/warm'
  if ($CacheState -eq 'warm') {
    Invoke-PerfLaunch $executable (Join-Path $runDir 'prepare-data') $warmData 'cold' -1 $true
    Invoke-PerfLaunch $executable (Join-Path $runDir 'prepare-warm') $warmData 'cold' -1
  }
  for ($index = 0; $index -lt $Launches; $index++) {
    $directory = Join-Path $runDir ('launch-{0:d3}' -f $index)
    $launchDirs.Add($directory)
    $data = if ($CacheState -eq 'warm') { $warmData } else { Join-Path $runDir "data/cold-$index" }
    if ($CacheState -eq 'cold') {
      Invoke-PerfLaunch $executable (Join-Path $runDir "prepare-data-$index") $data 'cold' -1 $true
    }
    Invoke-PerfLaunch $executable $directory $data $CacheState $index
  }
  $manifest.status = 'passed'
} catch {
  $failure = $_
  $manifest.status = 'failed'
  $manifest.error = $_.Exception.Message
} finally {
  $manifest.endedAtUtc = [DateTime]::UtcNow.ToString('o')
  Write-PerfJson (Join-Path $runDir 'manifest.json') $manifest
  Merge-PerfOutputs $launchDirs.ToArray()
  try {
    if ((Get-Item -LiteralPath (Join-Path $runDir 'phases.jsonl')).Length -gt 0) {
      $arguments = @('tool/perf_probe/analyze.dart', $runDir)
      if ($Baseline) { $arguments += @('--baseline', $Baseline) }
      & dart @arguments
      if ($LASTEXITCODE -ne 0 -and $null -eq $failure) { $failure = "Report analysis failed ($LASTEXITCODE)." }
    }
  } finally { Pop-Location }
  Write-Host "Results: $runDir"
}
if ($null -ne $failure) { Write-Error $failure; exit 1 }
exit 0
