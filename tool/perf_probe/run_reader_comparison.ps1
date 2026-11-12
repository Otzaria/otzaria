#Requires -Version 7.4
param(
  [string]$BaselineRef = '',
  [string]$CandidateRef = 'HEAD',
  [string]$OutputDirectory = '',
  [ValidateRange(1, 10)][int]$Cycles = 1,
  [ValidateRange(0, 10)][int]$Warmup = 1,
  [ValidateRange(1, 100)][int]$Repetitions = 2,
  [string]$BookLines = '2000,50000,1000000',
  [string]$HardwareId = '',
  [ValidateRange(60, 7200)][int]$TimeoutSeconds = 900,
  [switch]$DefinitionsOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$readerHarnessPaths = @(
  'integration_test/perf_resource_probe_test.dart',
  'integration_test/support/perf_fixture.dart',
  'integration_test/support/perf_recorder.dart',
  'integration_test/support/perf_reader_probe.dart',
  'integration_test/support/perf_reader_scroll.dart',
  'test/helpers/seforim_fixture_db.dart',
  'tool/perf_probe/analyze.dart',
  'tool/perf_probe/src/report.dart',
  'tool/perf_probe/lockfile_quoting.ps1',
  'tool/perf_probe/runner.ps1',
  'tool/perf_probe/run_perf_probe.ps1',
  'tool/perf_probe/sample_resources.ps1',
  'tool/perf_probe/run_reader_comparison.ps1'
)

function Invoke-ReaderGit([string]$Repository, [string[]]$Arguments) {
  $result = @(& git -C $Repository -c core.autocrlf=false @Arguments)
  if ($LASTEXITCODE -ne 0) { throw "git $($Arguments[0]) failed in $Repository ($LASTEXITCODE)." }
  return $result
}

function Assert-ReaderClean([string]$Repository) {
  $status = Invoke-ReaderGit $Repository @('status', '--porcelain=v1', '--untracked-files=all')
  if (-not [string]::IsNullOrWhiteSpace(($status | Out-String))) {
    throw "Unverified source checkout: $Repository`n$($status -join "`n")"
  }
}

function Get-ReaderLaunchPlan([int]$Cycles) {
  $indices = @{ baseline = 0; candidate = 0 }
  for ($cycle = 0; $cycle -lt $Cycles; $cycle++) {
    foreach ($side in @('baseline', 'candidate', 'candidate', 'baseline')) {
      [ordered]@{ side = $side; launchIndex = $indices[$side]; cycle = $cycle }
      $indices[$side]++
    }
  }
}

function Get-ReaderHarnessEntries([string]$Repository, [string]$Revision, [string[]]$Paths) {
  $entries = @(Invoke-ReaderGit $Repository (@('ls-tree', $Revision, '--') + $Paths) | Sort-Object)
  if ($entries.Count -ne $Paths.Count -or @($entries | Where-Object { $_ -notmatch '^100(644|755) blob [0-9a-f]{40}\t' }).Count) {
    throw 'Every harness path must identify one regular tracked file.'
  }
  return $entries
}

function Set-ReaderBaselineHarness([string]$Repository, [string]$Candidate,
                                   [string]$Baseline, [string[]]$Paths) {
  Assert-ReaderClean $Repository
  Invoke-ReaderGit $Repository (@('checkout', $Candidate, '--') + $Paths) | Out-Null
  $tree = @(Invoke-ReaderGit $Repository @('write-tree'))[-1]
  $commit = @(Invoke-ReaderGit $Repository @(
    '-c', 'user.name=Otzaria performance harness', '-c', 'user.email=perf-harness@localhost',
    'commit-tree', $tree, '-p', $Baseline, '-m', 'test(perf): apply the identical reader measurement harness'
  ))[-1]
  Invoke-ReaderGit $Repository @('reset', '--hard', $commit) | Out-Null
  Assert-ReaderClean $Repository
  $changed = @(Invoke-ReaderGit $Repository @('diff-tree', '--no-commit-id', '--name-only', '-r', $Baseline, $commit))
  if (@($changed | Where-Object { $_ -notin $Paths }).Count) { throw 'The baseline overlay changed a non-harness path.' }
  $expected = @(Get-ReaderHarnessEntries $Repository $Candidate $Paths)
  $actual = @(Get-ReaderHarnessEntries $Repository $commit $Paths)
  if (($expected -join "`n") -cne ($actual -join "`n")) { throw 'Harness blob or file-mode mismatch.' }
  return $commit
}

function Write-ReaderJson([string]$Path, $Value) {
  $Value | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath $Path -Encoding utf8
}

function Merge-ReaderObservations([string]$Destination, [string[]]$Directories) {
  New-Item -ItemType Directory -Path $Destination -Force | Out-Null
  foreach ($name in @('phases.jsonl', 'samples.csv', 'samples.csv.errors.jsonl')) {
    $writer = [IO.StreamWriter]::new((Join-Path $Destination $name), $false, [Text.UTF8Encoding]::new($false))
    $header = $null
    try {
      foreach ($directory in $Directories) {
        $path = Join-Path $directory $name
        if (-not (Test-Path -LiteralPath $path)) { continue }
        $first = $true
        $reader = [IO.File]::OpenText($path)
        try {
          while ($null -ne ($line = $reader.ReadLine())) {
            if ($name -eq 'samples.csv' -and $first) {
              if ($null -ne $header) {
                if ($line -cne $header) { throw 'Process sample headers differ between launches.' }
                $first = $false
                continue
              }
              $header = $line
            }
            $writer.WriteLine($line)
            $first = $false
          }
        } finally { $reader.Dispose() }
      }
    } finally { $writer.Dispose() }
  }
}

function Assert-ReaderComparison($Report, [int]$ExpectedSamples) {
  if (-not $Report.complete -or -not $Report.successful -or -not $Report.comparison.comparable) {
    throw 'The reports are incomplete, unsuccessful, or ineligible for comparison. Inspect report.json.'
  }
  foreach ($kind in @('short', 'medium', 'long')) {
    foreach ($action in @('open', 'scroll', 'jump_forward', 'jump_backward', 'warmup_complete', 'steady_scroll', 'close')) {
      $name = "book.$kind.$action"
      $rows = @($Report.scenarios | Where-Object { $_.name -eq $name })
      if ($rows.Count -ne 1 -or $rows[0].status -ne 'passed' -or $rows[0].measured -ne $ExpectedSamples) {
        throw "Missing complete reader observations: $name"
      }
      $compared = @($Report.comparison.scenarios | Where-Object { $_.name -eq $name })
      if ($compared.Count -ne 1 -or $compared[0].status -ne 'compared') { throw "Scenario cannot be compared: $name" }
      if ($action -in @('scroll', 'steady_scroll') -and ($rows[0].frames.count -eq 0 -or $rows[0].frames.truncatedIterations -gt 0 -or
          -not $compared[0].metrics.'frames.totalMs.p95'.available)) {
        throw "Incomplete scroll FrameTiming observations: $name"
      }
    }
  }
}

if ($DefinitionsOnly) { return }
if (-not $IsWindows) { throw 'The paired reader benchmark requires Windows.' }
if ($BaselineRef -notmatch '^[0-9a-f]{40}$') { throw 'BaselineRef must be a full pinned commit SHA.' }
if ($BookLines -notmatch '^\d+,\d+,\d+$') { throw 'BookLines must contain three comma-separated line counts.' }
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$candidate = @(Invoke-ReaderGit $repo @('rev-parse', '--verify', "$CandidateRef^{commit}"))[-1]
$baseline = @(Invoke-ReaderGit $repo @('rev-parse', '--verify', "$BaselineRef^{commit}"))[-1]
if (@(Invoke-ReaderGit $repo @('rev-parse', 'HEAD'))[-1] -ne $candidate) { throw 'Run the harness from the candidate checkout.' }
Assert-ReaderClean $repo
$output = if ($OutputDirectory) { [IO.Path]::GetFullPath($OutputDirectory, $PWD.Path) } else {
  Join-Path $env:TEMP ('otzaria-reader-' + [guid]::NewGuid().ToString('N'))
}
if (Test-Path -LiteralPath $output) { throw "Output directory already exists: $output" }
$relativeOutput = [IO.Path]::GetRelativePath($repo, $output)
if (-not [IO.Path]::IsPathRooted($relativeOutput) -and $relativeOutput -ne '..' -and
    -not $relativeOutput.StartsWith('../') -and -not $relativeOutput.StartsWith('..\')) {
  throw 'Keep comparison output outside the source checkout.'
}
New-Item -ItemType Directory -Path $output | Out-Null
$plan = @(Get-ReaderLaunchPlan $Cycles)
$entries = @(Get-ReaderHarnessEntries $repo $candidate $readerHarnessPaths)
$harnessSha = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData(
  [Text.Encoding]::UTF8.GetBytes(($entries -join "`n") + "`n"))).ToLowerInvariant()
$provenance = [ordered]@{
  baselineSourceCommit = $baseline; candidateSourceCommit = $candidate
  harnessSourceCommit = $candidate; harnessSha256 = $harnessSha; harnessEntries = $entries
  launchOrder = $plan; cycles = $Cycles; bookLines = $BookLines; status = 'running'
  coldDefinition = 'fresh application data; OS file cache is not flushed'
  buildTiming = 'both builds and all fixture preparation precede their measured process launches'
}
$checkouts = @{}
$runs = @{ baseline = [Collections.Generic.List[string]]::new(); candidate = [Collections.Generic.List[string]]::new() }
$failure = $null

function Invoke-ReaderRunner([string]$Side, [string]$Destination, [string[]]$Extra) {
  $script = Join-Path $checkouts[$Side] 'tool/perf_probe/run_perf_probe.ps1'
  $arguments = @('-NoProfile', '-File', $script, '-Mode', 'profile', '-CacheState', 'cold',
    '-ReaderOnly', '-BookLines', $BookLines, '-Warmup', "$Warmup", '-Repetitions', "$Repetitions",
    '-Launches', '1', '-OutputDirectory', $Destination, '-TimeoutSeconds', "$TimeoutSeconds")
  if ($HardwareId) { $arguments += @('-HardwareId', $HardwareId) }
  & pwsh @arguments @Extra 2>&1 | Tee-Object -FilePath "$Destination.runner.log"
  if ($LASTEXITCODE -ne 0) { throw "$Side runner failed ($LASTEXITCODE)." }
  Assert-ReaderClean $checkouts[$Side]
}

try {
  foreach ($side in @('baseline', 'candidate')) {
    $checkout = Join-Path $output "worktrees/$side"
    $revision = if ($side -eq 'baseline') { $baseline } else { $candidate }
    Invoke-ReaderGit $repo @('worktree', 'add', '--detach', $checkout, $revision) | Out-Null
    $checkouts[$side] = $checkout
    if ($side -eq 'baseline') {
      $provenance.baselineMeasuredCommit = Set-ReaderBaselineHarness $checkout $candidate $baseline $readerHarnessPaths
    } else { $provenance.candidateMeasuredCommit = $candidate }
    Write-ReaderJson (Join-Path $output 'provenance.json') $provenance
    Invoke-ReaderRunner $side (Join-Path $output "build-$side") @('-BuildOnly')
    $built = Get-Content -LiteralPath (Join-Path $output "build-$side/manifest.json") -Raw | ConvertFrom-Json -AsHashtable
    if ($built.status -ne 'built' -or $built.dirty) { throw "$side did not produce a verified clean build." }
    # Only exported bundles are needed during the interleaved launches.
    foreach ($relative in @('build', '.dart_tool/hooks_runner/shared')) {
      $owned = Join-Path $checkout $relative
      if (Test-Path -LiteralPath $owned) { Remove-Item -LiteralPath $owned -Recurse -Force }
    }
  }
  for ($step = 0; $step -lt $plan.Count; $step++) {
    $entry = $plan[$step]
    $directory = Join-Path $output ('step-{0:d2}-{1}' -f $step, $entry.side)
    $runs[$entry.side].Add($directory)
    Invoke-ReaderRunner $entry.side $directory @(
      '-ReuseBuild', (Join-Path $output "build-$($entry.side)"),
      '-LaunchIndexOffset', "$($entry.launchIndex)", '-SkipAnalysis')
  }
  $provenance.status = 'passed'
} catch {
  $failure = $_
  $provenance.status = 'failed'
  $provenance.error = $_.Exception.Message
} finally {
  try {
    foreach ($side in @('baseline', 'candidate')) {
      if ($runs[$side].Count -eq 0) { continue }
      $destination = Join-Path $output $side
      Merge-ReaderObservations $destination $runs[$side].ToArray()
      $manifest = Get-Content -LiteralPath (Join-Path $runs[$side][0] 'manifest.json') -Raw | ConvertFrom-Json -AsHashtable
      $manifest.launchCount = $Cycles * 2
      $manifest.status = $provenance.status
      $manifest.sourceCommit = if ($side -eq 'baseline') { $baseline } else { $candidate }
      $manifest.baseCommit = $baseline
      $manifest.harnessCommit = $candidate
      $manifest.harnessSha256 = $harnessSha
      $manifest.launchOrder = $plan
      $manifest.launchDirectories = @()
      foreach ($directory in $runs[$side]) {
        $observed = Get-Content -LiteralPath (Join-Path $directory 'manifest.json') -Raw | ConvertFrom-Json -AsHashtable
        if ($observed.dirty -or $observed.status -ne 'passed') { $manifest.status = 'failed'; $manifest.dirty = $manifest.dirty -or $observed.dirty }
        foreach ($key in @('commit', 'binarySha256', 'buildMode', 'cacheState', 'hardwareId', 'os', 'flutterVersion', 'warmup', 'repetitions')) {
          if ($manifest[$key] -cne $observed[$key]) { throw "Inconsistent $key between $side launches." }
        }
        $manifest.endedAtUtc = $observed.endedAtUtc
        $stepDirectory = [IO.Path]::GetRelativePath($output, $directory)
        $manifest.launchDirectories += [ordered]@{
          launchIndex = $observed.launchIndexOffset; stepDirectory = $stepDirectory
          launchDirectory = Join-Path $stepDirectory ('launch-{0:d3}' -f $observed.launchIndexOffset)
        }
      }
      Write-ReaderJson (Join-Path $destination 'manifest.json') $manifest
      $arguments = @((Join-Path $repo 'tool/perf_probe/analyze.dart'), $destination)
      if ($side -eq 'candidate' -and (Test-Path -LiteralPath (Join-Path $output 'baseline/report.json'))) {
        $arguments += @('--baseline', (Join-Path $output 'baseline'))
      }
      & dart @arguments
      if ($LASTEXITCODE -ne 0) { throw "$side report analysis failed ($LASTEXITCODE)." }
    }
    if ($null -eq $failure) {
      $report = Get-Content -LiteralPath (Join-Path $output 'candidate/report.json') -Raw | ConvertFrom-Json
      Assert-ReaderComparison $report ($Cycles * 2 * $Repetitions)
    }
  } catch {
    if ($null -eq $failure) { $failure = $_ }
    $provenance.status = 'failed'
    $provenance.error = $_.Exception.Message
  } finally {
    Write-ReaderJson (Join-Path $output 'provenance.json') $provenance
    foreach ($side in $checkouts.Keys) {
      Invoke-ReaderGit $checkouts[$side] @('rev-parse', 'HEAD') | Set-Content -LiteralPath (Join-Path $output "$side-head.txt")
      Invoke-ReaderGit $checkouts[$side] @('status', '--porcelain=v1', '--untracked-files=all') | Set-Content -LiteralPath (Join-Path $output "$side-status.txt")
      Invoke-ReaderGit $checkouts[$side] @('diff', '--no-ext-diff') | Set-Content -LiteralPath (Join-Path $output "$side-diff.patch")
      Invoke-ReaderGit $repo @('worktree', 'remove', '--force', $checkouts[$side]) | Out-Null
    }
  }
}
Write-Host "Reader comparison: $output"
if ($null -ne $failure) { Write-Error $failure; exit 1 }
