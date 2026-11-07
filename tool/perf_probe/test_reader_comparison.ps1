#Requires -Version 7.4
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

foreach ($name in @('runner.ps1', 'run_perf_probe.ps1', 'run_reader_comparison.ps1', 'lockfile_quoting.ps1')) {
  $tokens = $null
  $errors = $null
  [void][Management.Automation.Language.Parser]::ParseFile(
    (Join-Path $PSScriptRoot $name), [ref]$tokens, [ref]$errors)
  if ($errors.Count) { throw ($errors | Out-String) }
}
. (Join-Path $PSScriptRoot 'run_reader_comparison.ps1') -DefinitionsOnly
. (Join-Path $PSScriptRoot 'lockfile_quoting.ps1')

function Assert-ReaderEqual($Actual, $Expected, [string]$Label) {
  if ($Actual -cne $Expected) { throw "${Label}: expected '$Expected', got '$Actual'." }
}

function Assert-ReaderThrows([scriptblock]$Action, [string]$Label) {
  $caught = $false
  try { & $Action } catch { $caught = $true }
  if (-not $caught) { throw "$Label did not reject invalid input." }
}

foreach ($cycles in @(1, 2)) {
  $plan = @(Get-ReaderLaunchPlan $cycles)
  Assert-ReaderEqual $plan.Count ($cycles * 4) 'launch count'
  Assert-ReaderEqual (($plan | ForEach-Object side) -join ',') ((@('baseline,candidate,candidate,baseline') * $cycles) -join ',') 'ABBA order'
  foreach ($side in @('baseline', 'candidate')) {
    Assert-ReaderEqual (($plan | Where-Object { $_.side -eq $side } | ForEach-Object launchIndex) -join ',') ((0..($cycles * 2 - 1)) -join ',') 'per-side logical indices'
  }
}

$scenarioNames = @(
  foreach ($kind in @('short', 'medium', 'long')) {
    foreach ($action in @('open', 'scroll', 'jump_forward', 'jump_backward', 'warmup_complete', 'steady_scroll', 'close')) { "book.$kind.$action" }
  }
)
$rows = @($scenarioNames | ForEach-Object {
  @{ name = $_; status = 'passed'; measured = 4; frames = @{ count = 1; truncatedIterations = 0 } }
})
$report = @{
  complete = $true; successful = $true; scenarios = $rows
  comparison = @{ comparable = $true; scenarios = @($scenarioNames | ForEach-Object {
    @{ name = $_; status = 'compared'; metrics = @{ 'frames.totalMs.p95' = @{ available = $true } } }
  }) }
}
Assert-ReaderComparison $report 4
foreach ($missing in @('book.long.warmup_complete', 'book.long.steady_scroll')) {
  $report.scenarios = @($rows | Where-Object { $_.name -ne $missing })
  Assert-ReaderThrows { Assert-ReaderComparison $report 4 } "missing $missing"
}
$report.scenarios = $rows
$report.comparison.comparable = $false
Assert-ReaderThrows { Assert-ReaderComparison $report 4 } 'comparison metadata guard'

$root = Join-Path ([IO.Path]::GetTempPath()) ('reader-contract-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root | Out-Null
try {
  $lockfilePath = Join-Path $root 'pubspec.lock'
  $sha = 'b78d36eaffcb2a5fa679d34a52133512ee55c084'
  $original = "packages:`n  engine:`n    ref: `"$sha`"`n    resolved-ref: '$sha'`n    version: 1.0.0`n"
  $originalBytes = [Text.Encoding]::UTF8.GetBytes($original)
  $unquoted = $original.Replace("`"$sha`"", $sha).Replace("'$sha'", $sha)
  foreach ($text in @($original, $unquoted)) {
    [IO.File]::WriteAllText($lockfilePath, $text, [Text.UTF8Encoding]::new($false))
    $proof = Restore-PerfLockfileQuoting $lockfilePath $originalBytes
    Assert-ReaderEqual ([IO.File]::ReadAllText($lockfilePath)) $original 'exact lockfile source bytes'
    Assert-ReaderEqual $proof.originalSha256 $proof.restoredSha256 'lockfile restoration hash'
    Assert-ReaderEqual $proof.restoredQuotingOnly ($text -cne $original) 'quoting-only evidence'
  }
  foreach ($invalid in @(
    $unquoted.Replace($sha, ('0' * 40)),
    $unquoted.Replace('1.0.0', '1.0.1'),
    $unquoted.Replace('packages:', 'packages: '),
    $unquoted.TrimEnd(),
    $unquoted.Replace("`n", "`r`n")
  )) {
    [IO.File]::WriteAllText($lockfilePath, $invalid, [Text.UTF8Encoding]::new($false))
    Assert-ReaderThrows { Restore-PerfLockfileQuoting $lockfilePath $originalBytes } 'lockfile dependency/text change'
    Assert-ReaderEqual ([IO.File]::ReadAllText($lockfilePath)) $invalid 'rejected dependency change remains visible'
  }
  $source = Join-Path $root 'source'
  New-Item -ItemType Directory -Path $source | Out-Null
  Invoke-ReaderGit $source @('init', '--quiet') | Out-Null
  Invoke-ReaderGit $source @('config', 'user.name', 'Reader contract') | Out-Null
  Invoke-ReaderGit $source @('config', 'user.email', 'reader-contract@localhost') | Out-Null
  Set-Content -LiteralPath (Join-Path $source 'product.txt') -Value 'original product'
  Set-Content -LiteralPath (Join-Path $source 'harness.txt') -Value 'old measurement'
  Invoke-ReaderGit $source @('add', '.') | Out-Null
  Invoke-ReaderGit $source @('commit', '--quiet', '-m', 'baseline fixture') | Out-Null
  $baseline = @(Invoke-ReaderGit $source @('rev-parse', 'HEAD'))[-1]
  Set-Content -LiteralPath (Join-Path $source 'product.txt') -Value 'changed product'
  Set-Content -LiteralPath (Join-Path $source 'harness.txt') -Value 'identical measurement'
  Set-Content -LiteralPath (Join-Path $source 'helper.ps1') -Value 'Write-Output helper'
  Invoke-ReaderGit $source @('add', '.') | Out-Null
  Invoke-ReaderGit $source @('update-index', '--chmod=+x', 'helper.ps1') | Out-Null
  Invoke-ReaderGit $source @('commit', '--quiet', '-m', 'candidate fixture') | Out-Null
  $candidate = @(Invoke-ReaderGit $source @('rev-parse', 'HEAD'))[-1]
  $overlay = Join-Path $root 'overlay'
  Invoke-ReaderGit $source @('worktree', 'add', '--detach', $overlay, $baseline) | Out-Null
  $paths = @('harness.txt', 'helper.ps1')
  $measured = Set-ReaderBaselineHarness $overlay $candidate $baseline $paths
  Assert-ReaderEqual ([bool]($measured -match '^[0-9a-f]{40}$')) $true 'measured commit SHA'
  Assert-ReaderEqual (@(Invoke-ReaderGit $overlay @('show', "${measured}:product.txt"))[-1]) 'original product' 'baseline product preserved'
  Assert-ReaderEqual ((Get-ReaderHarnessEntries $overlay $measured $paths) -join "`n") ((Get-ReaderHarnessEntries $source $candidate $paths) -join "`n") 'identical harness blobs and modes'
  Assert-ReaderClean $overlay
  Set-Content -LiteralPath (Join-Path $overlay 'harness.txt') -Value 'uncommitted mutation'
  Assert-ReaderThrows { Assert-ReaderClean $overlay } 'dirty source guard'
  Assert-ReaderThrows { Get-ReaderHarnessEntries $source $candidate @('missing.ps1') } 'missing harness path'

  $directories = @()
  for ($index = 0; $index -lt 2; $index++) {
    $directory = Join-Path $root "launch-$index"
    New-Item -ItemType Directory -Path $directory | Out-Null
    Set-Content -LiteralPath (Join-Path $directory 'phases.jsonl') -Value "{`"launchIndex`":$index}"
    Set-Content -LiteralPath (Join-Path $directory 'samples.csv') -Value @('launch_index,pid', "$index,100")
    $directories += $directory
  }
  $merged = Join-Path $root 'merged'
  Merge-ReaderObservations $merged $directories
  Assert-ReaderEqual ((Get-Content -LiteralPath (Join-Path $merged 'samples.csv')) -join '|') 'launch_index,pid|0,100|1,100' 'one CSV header and original logical indices'
  Assert-ReaderEqual ((Get-Content -LiteralPath (Join-Path $merged 'phases.jsonl')) -join '|') '{"launchIndex":0}|{"launchIndex":1}' 'raw phase records preserved'
  Set-Content -LiteralPath (Join-Path $directories[1] 'samples.csv') -Value @('unexpected,header', '1,100')
  try {
    Merge-ReaderObservations (Join-Path $root 'mismatch') $directories
    throw 'Expected incompatible CSV schemas to be rejected.'
  } catch {
    Assert-ReaderEqual $_.Exception.Message 'Process sample headers differ between launches.' 'CSV schema error preserved'
  }
  foreach ($path in @((Join-Path $directories[1] 'samples.csv'), (Join-Path $root 'mismatch/samples.csv'))) {
    $exclusive = [IO.File]::Open($path, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    $exclusive.Dispose()
  }
} finally {
  Remove-Item -LiteralPath $root -Recurse -Force
}
Write-Host 'PASS: parsing, ABBA order, complete warmup/scroll coverage, narrow lockfile quote restoration, clean source overlay, file modes, original baseline product, logical indices and raw observation merging.'
