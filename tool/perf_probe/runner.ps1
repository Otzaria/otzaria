# Invoked by run_perf_probe.ps1. Build once, then launch only the owned binary.
#Requires -Version 7.4
param(
  [ValidateSet('profile', 'debug', 'release')][string]$Mode = 'profile',
  [ValidateSet('cold', 'warm')][string]$CacheState = 'cold',
  [ValidateSet('all', 'pdf-reader', 'pdf-book-view', 'pdf-multi-window')][string]$ScenarioSet = 'all',
  [ValidateSet('integration', 'framework')][string]$BindingMode = 'integration',
  [string]$PdfCase = '',
  [string]$ExpectedEngineSha256 = '',
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
. (Join-Path $PSScriptRoot 'source_provenance.ps1')
Import-Module (Join-Path $PSScriptRoot 'probe_binding.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'probe_engine.psm1') -Force
$bindingIdentity = Get-PerfBindingIdentity $BindingMode
if ($BindingMode -eq 'framework' -and $ScenarioSet -eq 'all') {
  throw 'The framework target accepts pdf-reader or pdf-book-view.'
}
if ($ScenarioSet -eq 'pdf-multi-window' -and $BindingMode -ne 'framework') {
  throw 'The multi-window scenario requires the framework binding.'
}
if ($ExpectedEngineSha256 -and ($Mode -ne 'release' -or $ExpectedEngineSha256 -notmatch '^[a-fA-F0-9]{64}$')) {
  throw 'ExpectedEngineSha256 requires a release build and a SHA-256 digest.'
}
if (-not $IsWindows) { throw 'The automated desktop runner requires Windows. See README.md for other platforms.' }
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
if ($Baseline) { $Baseline = [IO.Path]::GetFullPath($Baseline, $PWD.Path) }
if ($PdfCase) { $PdfCase = [IO.Path]::GetFullPath($PdfCase, $PWD.Path) }
$pdfCaseSnapshot = ''
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

function Write-PerfFrameworkFailureDiagnostics([string]$Directory) {
  # Read only this launch's owned files, at most 16 KiB per file.
  foreach ($name in @('completion.json', 'stdout.log', 'stderr.log')) {
    try {
      $stream = [IO.File]::Open(
        (Join-Path $Directory $name), [IO.FileMode]::Open,
        [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
      try {
        $length = $stream.Length
        $offset = if ($name -eq 'completion.json') { 0L } else { [Math]::Max(0L, $length - 16384L) }
        [void]$stream.Seek($offset, [IO.SeekOrigin]::Begin)
        $count = [int][Math]::Min(16384L, $length - $offset)
        $buffer = [byte[]]::new($count)
        $read = 0
        while ($read -lt $count) {
          $received = $stream.Read($buffer, $read, $count - $read)
          if ($received -eq 0) { break }
          $read += $received
        }
      } finally { $stream.Dispose() }
      Write-Host "Framework failure evidence: $name (offset $offset, $read of $length bytes)"
      Write-Host ([Text.Encoding]::UTF8.GetString($buffer, 0, $read))
    } catch {
      # Diagnostics must never replace the benchmark's original failure.
      Write-Host ('Framework failure evidence unavailable for {0}: {1}' -f $name, $_.Exception.Message)
    }
  }
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
    Assert-PerfWindowsEngineUnchanged -Executable $Executable -Identity $manifest.engineIdentity
    $process = Start-Process -FilePath $Executable -WorkingDirectory (Split-Path $Executable) `
      -PassThru -RedirectStandardOutput (Join-Path $Directory 'stdout.log') `
      -RedirectStandardError (Join-Path $Directory 'stderr.log') -Environment @{
        PERF_OUTPUT_DIR = $Directory; PERF_DATA_DIR = $DataDirectory
        PERF_CACHE_STATE = $Cache; PERF_LAUNCH_INDEX = "$Index"
        PERF_WARMUP = "$Warmup"; PERF_REPETITIONS = "$Repetitions"
        PERF_SCENARIO_SET = $ScenarioSet
        PERF_ENGINE_IDENTITY = ($manifest.engineIdentity | ConvertTo-Json -Depth 10 -Compress)
        PERF_PDF_CASE = $pdfCaseSnapshot
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
    Assert-PerfBindingIdentity $result $BindingMode
    if ($result.status -ne 'passed') { throw "Benchmark failed; inspect $completion" }
    $process.Refresh()
    if ($process.HasExited -and $process.ExitCode -ne 0) {
      throw "Benchmark exited unsuccessfully (exit $($process.ExitCode))."
    }
  } catch {
    if ($BindingMode -eq 'framework') {
      Write-PerfFrameworkFailureDiagnostics $Directory
    }
    throw
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
  if ($PdfCase) {
    $pdfCaseSnapshot = Join-Path $runDir 'pdf-case.json'
    & dart tool/perf_probe/prepare_pdf_case.dart $PdfCase $pdfCaseSnapshot
    if ($LASTEXITCODE -ne 0) { throw 'PDF case validation failed.' }
  }
  $commit = (& git rev-parse HEAD).Trim()
  if ($LASTEXITCODE -ne 0) { throw 'Cannot identify source commit.' }
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
    schemaVersion = 2; protocolVersion = 2; commit = $commit
    buildMode = $Mode; cacheState = $CacheState; hardwareId = $HardwareId
    scenarioSet = $ScenarioSet; bindingMode = $BindingMode; probeTarget = $bindingIdentity.probeTarget
    os = "windows-$($os.Version)-$($os.BuildNumber)"; flutterVersion = $sdk.frameworkRevision
    warmup = $Warmup; repetitions = $Repetitions; launchCount = $Launches
    sampling = @{ intervalMs = 500; treeRefreshMs = 2000; heap = ($Mode -ne 'release') }
    machine = @{ cpu = $cpu; gpu = $gpu; memoryBytes = $system.TotalPhysicalMemory }
    startedAtUtc = [DateTime]::UtcNow.ToString('o'); status = 'running'
    coldDefinition = 'fresh application data; OS file cache is not flushed'
    startupOrigin = 'Dart main; fixture preparation and native pre-main are excluded'
  }
  Add-PerfSourceProvenance $repo $manifest 'beforeBuild'
  Write-PerfJson (Join-Path $runDir 'manifest.json') $manifest
  try {
    & flutter build windows "--$Mode" --no-pub "--target=$($bindingIdentity.probeTarget)" `
      --dart-define=SENTRY_DSN= --dart-define=INTEGRATION_TEST_SHOULD_REPORT_RESULTS_TO_NATIVE=false `
      2>&1 | Tee-Object -FilePath (Join-Path $runDir 'build.log')
    $buildExitCode = $LASTEXITCODE
  } finally {
    Add-PerfSourceProvenance $repo $manifest 'afterBuild'
    Write-PerfJson (Join-Path $runDir 'manifest.json') $manifest
  }
  if ($buildExitCode -ne 0) { throw "Flutter build failed ($buildExitCode)." }
  if ((& git rev-parse HEAD).Trim() -ne $commit) { throw 'HEAD changed while building; rerun on a stable checkout.' }
  $modeFolder = (Get-Culture).TextInfo.ToTitleCase($Mode)
  $executable = Join-Path $repo "build/windows/x64/runner/$modeFolder/otzaria.exe"
  if (-not (Test-Path -LiteralPath $executable)) { throw "Built executable not found: $executable" }
  $manifest.binarySha256 = (Get-FileHash -LiteralPath $executable -Algorithm SHA256).Hash.ToLowerInvariant()
  $manifest.engineIdentity = Get-PerfWindowsEngineIdentity -Executable $executable -Mode $Mode -EngineRevision $sdk.engineRevision -ExpectedSha256 $ExpectedEngineSha256
  Write-PerfJson (Join-Path $runDir 'manifest.json') $manifest
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
  Add-PerfSourceProvenance $repo $manifest 'afterRuns'
  $manifest.endedAtUtc = [DateTime]::UtcNow.ToString('o')
  Write-PerfJson (Join-Path $runDir 'manifest.json') $manifest
  Merge-PerfOutputs $launchDirs.ToArray()
  try {
    if ((Get-Item -LiteralPath (Join-Path $runDir 'phases.jsonl')).Length -gt 0) {
      $arguments = @('tool/perf_probe/analyze.dart', $runDir)
      if ($Baseline) { $arguments += @('--baseline', $Baseline) }
      & dart @arguments
      if ($LASTEXITCODE -ne 0 -and $null -eq $failure) { $failure = "Report analysis failed ($LASTEXITCODE)." }
      if ($null -eq $failure -and $BindingMode -eq 'framework') {
        try {
          $report = Get-Content -LiteralPath (Join-Path $runDir 'report.json') -Raw | ConvertFrom-Json
          if ($report.complete -ne $true -or $report.successful -ne $true) {
            throw 'Analysis did not confirm a complete successful run.'
          }
          Assert-PerfBindingIdentity $report.metadata.settings $BindingMode
          Assert-PerfFrameworkScheduler $report.notes $Launches
        } catch {
          $failure = $_
          $manifest.status = 'failed'
          $manifest.analysisError = $_.Exception.Message
          Write-PerfJson (Join-Path $runDir 'manifest.json') $manifest
        }
      }
    }
  } finally { Pop-Location }
  Write-Host "Results: $runDir"
}
if ($null -ne $failure) { Write-Error $failure; exit 1 }
exit 0
