# Pure contract checks; no timing thresholds, CIM or Windows process required.
#Requires -Version 7.4
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

foreach ($name in @('sample_resources.ps1', 'runner.ps1', 'run_perf_probe.ps1')) {
  $tokens = $null
  $errors = $null
  [void][Management.Automation.Language.Parser]::ParseFile(
    (Join-Path $PSScriptRoot $name), [ref]$tokens, [ref]$errors)
  if ($errors.Count) { throw ($errors | Out-String) }
}
. (Join-Path $PSScriptRoot 'sample_resources.ps1') -OutCsv unused -StopFile unused -DefinitionsOnly

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
Write-Host 'PASS: PowerShell parsing, process identity/ancestry, orphan retention, locale and missing-data contracts.'
