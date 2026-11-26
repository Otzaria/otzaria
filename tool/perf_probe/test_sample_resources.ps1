# Pure contract checks; no timing thresholds, CIM or Windows process required.
#Requires -Version 7.4
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

foreach ($name in @('sample_resources.ps1', 'runner.ps1', 'run_perf_probe.ps1', 'source_provenance.ps1')) {
  $tokens = $null
  $errors = $null
  [void][Management.Automation.Language.Parser]::ParseFile(
    (Join-Path $PSScriptRoot $name), [ref]$tokens, [ref]$errors)
  if ($errors.Count) { throw ($errors | Out-String) }
}
. (Join-Path $PSScriptRoot 'sample_resources.ps1') -OutCsv unused -StopFile unused -DefinitionsOnly
. (Join-Path $PSScriptRoot 'source_provenance.ps1')

function Assert-PerfEqual($Actual, $Expected, [string]$Label) {
  if ($Actual -cne $Expected) { throw "${Label}: expected '$Expected', got '$Actual'." }
}

$born = [datetime]::new(2026, 1, 1, 0, 0, 0, [DateTimeKind]::Utc)
$rootTicks = Get-PerfIdentityTicks $born
function Row([int]$Id, [int]$ParentId, [int]$Offset) {
  [pscustomobject]@{ ProcessId = $Id; ParentProcessId = $ParentId; CreationDate = $born.AddSeconds($Offset) }
}
$snapshot = @((Row 10 1 0), (Row 20 10 1), (Row 30 20 2), (Row 40 10 -1), (Row 50 20 0))
$tree = Get-PerfProcessTree $snapshot 10 $rootTicks
Assert-PerfEqual (($tree.Keys | Sort-Object) -join ',') '10,20,30' 'ancestry and creation order'
Assert-PerfEqual (Get-PerfProcessTree $snapshot 10 ($rootTicks + 10000)).Count 0 'reused root PID'
$orphaned = @((Row 10 1 0), (Row 30 20 2))
$retained = Get-PerfProcessTree $orphaned 10 $rootTicks $tree
Assert-PerfEqual (($retained.Keys | Sort-Object) -join ',') '10,30' 'known live orphan retained'
$reused = @((Row 10 1 0), (Row 20 1 5), (Row 30 20 6))
$newTree = Get-PerfProcessTree $reused 10 $rootTicks $tree
Assert-PerfEqual (($newTree.Keys | Sort-Object) -join ',') '10' 'reused child excluded with its descendants'
Assert-PerfEqual (Get-PerfIdentityTicks $born.AddTicks(9999)) $rootTicks 'CIM timestamp precision'

$culture = [cultureinfo]::CurrentCulture
try {
  foreach ($name in @('en-US', 'de-DE', 'fr-FR', 'he-IL')) {
    [cultureinfo]::CurrentCulture = [cultureinfo]::new($name)
    Assert-PerfEqual (ConvertTo-PerfCsvNumber 1.25) '1.25' "decimal separator $name"
    Assert-PerfEqual (ConvertTo-PerfCsvNumber $null) '' "missing value $name"
    Assert-PerfEqual (ConvertTo-PerfCsvNumber 0) '0' "observed zero $name"
  }
} finally { [cultureinfo]::CurrentCulture = $culture }

$sourceRepo = Join-Path ([IO.Path]::GetTempPath()) ('perf-source-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $sourceRepo | Out-Null
function Invoke-SourceGit([string[]]$Arguments) {
  & git -C $sourceRepo @Arguments | Out-Null
  if ($LASTEXITCODE -ne 0) { throw 'Cannot prepare source provenance fixture.' }
}
try {
  Invoke-SourceGit @('init', '--quiet')
  Invoke-SourceGit @('config', 'core.autocrlf', 'false')
  [IO.File]::WriteAllText((Join-Path $sourceRepo '.gitignore'), "build/`n")
  [IO.File]::WriteAllText((Join-Path $sourceRepo 'tracked.txt'), "original`n")
  Invoke-SourceGit @('add', '.')
  Invoke-SourceGit @('-c', 'user.name=Perf fixture', '-c', 'user.email=perf-fixture@example.invalid',
    'commit', '--quiet', '--no-gpg-sign', '-m', 'fixture')
  New-Item -ItemType Directory -Path (Join-Path $sourceRepo 'build') | Out-Null
  [IO.File]::WriteAllText((Join-Path $sourceRepo 'build/observations.json'), '{}')
  $clean = @{}
  Add-PerfSourceProvenance $sourceRepo $clean 'beforeBuild'
  Assert-PerfEqual $clean.dirty $false 'clean sources and ignored build output'
  Assert-PerfEqual $clean.sourceProvenance.beforeBuild.statusPorcelain.Count 0 'empty source status is recorded'
  Assert-PerfEqual $clean.sourceProvenance.beforeBuild.trackedDiffSummary.Count 0 'empty source diff is recorded'

  $repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
  Copy-Item -LiteralPath (Join-Path $repo '.gitattributes') -Destination $sourceRepo
  $headers = @('linux/flutter/generated_plugin_registrant.h', 'windows/flutter/generated_plugin_registrant.h')
  foreach ($header in $headers) {
    $destination = Join-Path $sourceRepo $header
    New-Item -ItemType Directory -Path (Split-Path $destination) -Force | Out-Null
    [IO.File]::WriteAllText($destination, "// Generated header`nvoid RegisterPlugins();`n")
  }
  Invoke-SourceGit @('add', '.')
  Invoke-SourceGit @('-c', 'user.name=Perf fixture', '-c', 'user.email=perf-fixture@example.invalid',
    'commit', '--quiet', '--no-gpg-sign', '-m', 'generated headers')
  Invoke-SourceGit @('config', 'core.autocrlf', 'true')
  foreach ($header in $headers) {
    $destination = Join-Path $sourceRepo $header
    Remove-Item -LiteralPath $destination
    Invoke-SourceGit @('checkout', '--', $header)
    Assert-PerfEqual ([IO.File]::ReadAllText($destination).Contains("`r")) $false "LF checkout for $header"
    [IO.File]::WriteAllText($destination, "// Generated header`nvoid RegisterPlugins();`n")
  }
  $regenerated = @{}
  Add-PerfSourceProvenance $sourceRepo $regenerated 'beforeBuild'
  Assert-PerfEqual $regenerated.dirty $false 'identical Flutter LF headers keep provenance clean'
  [IO.File]::AppendAllText((Join-Path $sourceRepo $headers[0]), "// real content change`n")
  Add-PerfSourceProvenance $sourceRepo $regenerated 'afterBuild'
  Assert-PerfEqual $regenerated.dirty $true 'real generated-header changes still block comparison'
  Assert-PerfEqual (($regenerated.sourceProvenance.afterBuild.trackedDiffSummary -join "`n") -match 'generated_plugin_registrant.h') $true 'real header changes remain in the diff'
  Invoke-SourceGit @('restore', '--', $headers[0])
  Invoke-SourceGit @('config', 'core.autocrlf', 'false')

  [IO.File]::WriteAllText((Join-Path $sourceRepo 'tracked.txt'), "private-content-must-not-be-uploaded`n")
  $tracked = @{}
  Add-PerfSourceProvenance $sourceRepo $tracked 'beforeBuild'
  Assert-PerfEqual $tracked.dirty $true 'tracked change blocks comparison'
  Assert-PerfEqual ($tracked.sourceProvenance.beforeBuild.statusPorcelain -join "`n") ' M tracked.txt' 'tracked status includes path'
  Assert-PerfEqual (($tracked.sourceProvenance.beforeBuild.trackedDiffSummary -join "`n") -match 'tracked.txt') $true 'tracked diff summary includes path'
  Assert-PerfEqual (($tracked | ConvertTo-Json -Depth 10) -match 'private-content-must-not-be-uploaded') $false 'source contents are not captured'
  Invoke-SourceGit @('restore', '--', 'tracked.txt')
  Add-PerfSourceProvenance $sourceRepo $tracked 'afterBuild'
  Assert-PerfEqual $tracked.dirty $true 'restoring sources cannot erase earlier dirty evidence'
  Assert-PerfEqual $tracked.sourceProvenance.afterBuild.statusPorcelain.Count 0 'later clean snapshot remains visible'

  $postRun = @{}
  Add-PerfSourceProvenance $sourceRepo $postRun 'beforeBuild'
  Add-PerfSourceProvenance $sourceRepo $postRun 'afterBuild'
  [IO.File]::AppendAllText((Join-Path $sourceRepo 'tracked.txt'), 'changed while the app ran')
  Add-PerfSourceProvenance $sourceRepo $postRun 'afterRuns'
  Assert-PerfEqual $postRun.dirty $true 'a source edit during native launch blocks comparison'
  Assert-PerfEqual $postRun.sourceProvenance.afterRuns.statusPorcelain.Count 1 'post-run changed path is recorded'
  Invoke-SourceGit @('restore', '--', 'tracked.txt')
  Add-PerfSourceProvenance $sourceRepo $postRun 'afterRuns'
  Assert-PerfEqual $postRun.dirty $true 'later cleanup cannot erase post-run source changes'
  Assert-PerfEqual $postRun.sourceProvenance.afterRuns.statusPorcelain.Count 0 'a later clean post-run observation remains explicit'

  $newFile = 'untracked notes.txt'
  [IO.File]::WriteAllText((Join-Path $sourceRepo $newFile), "untracked-private-content`n")
  Add-PerfSourceProvenance $sourceRepo $clean 'afterBuild'
  Assert-PerfEqual $clean.dirty $true 'new untracked file during build blocks comparison'
  Assert-PerfEqual (($clean.sourceProvenance.afterBuild.statusPorcelain -join "`n") -match 'untracked notes.txt') $true 'untracked status includes spaced path'
  Assert-PerfEqual $clean.sourceProvenance.afterBuild.trackedDiffSummary.Count 0 'untracked contents are not included in diff summary'
  Assert-PerfEqual (($clean | ConvertTo-Json -Depth 10) -match 'untracked-private-content') $false 'untracked contents are not captured'
  Remove-Item -LiteralPath (Join-Path $sourceRepo $newFile)

  Invoke-SourceGit @('mv', 'tracked.txt', 'renamed file.txt')
  $renamed = @{}
  Add-PerfSourceProvenance $sourceRepo $renamed 'beforeBuild'
  Assert-PerfEqual $renamed.dirty $true 'staged rename blocks comparison'
  $renameStatus = $renamed.sourceProvenance.beforeBuild.statusPorcelain -join "`n"
  Assert-PerfEqual ($renameStatus -match '^R .*tracked.txt.*renamed file.txt') $true 'rename records both paths'
  Assert-PerfEqual (($renamed.sourceProvenance.beforeBuild.trackedDiffSummary -join "`n") -match 'rename .*tracked.txt.*renamed file.txt') $true 'rename diff summary is retained'
  $roundTrip = $renamed | ConvertTo-Json -Depth 10 | ConvertFrom-Json
  Assert-PerfEqual $roundTrip.dirty $true 'JSON preserves the comparison guard'
  Assert-PerfEqual ($roundTrip.sourceProvenance.beforeBuild.statusPorcelain -is [array]) $true 'single status remains an array in JSON'
  Assert-PerfEqual $roundTrip.sourceProvenance.beforeBuild.statusPorcelain.Count 1 'JSON preserves the single changed path'

  $missing = @{}
  $failure = $null
  try { Add-PerfSourceProvenance (Join-Path $sourceRepo 'missing') $missing 'beforeBuild' 2>$null }
  catch { $failure = $_ }
  Assert-PerfEqual ($null -ne $failure) $true 'failed git inspection is not accepted as a clean worktree'
  Assert-PerfEqual $missing.ContainsKey('dirty') $false 'failed inspection never records dirty=false'
} finally { Remove-Item -LiteralPath $sourceRepo -Recurse -Force }
Write-Host 'PASS: PowerShell parsing, process identity/ancestry, orphan retention, locale, missing-data and source provenance contracts.'
# Handled native failures above must not become the Actions step's exit code.
exit 0
