# Source diagnostics only: keep file contents out of uploaded observations.
function Add-PerfSourceProvenance {
  param(
    [string]$Repository,
    [hashtable]$Manifest,
    [ValidateSet('beforeBuild', 'afterBuild', 'afterRuns')][string]$Stage
  )

  $status = @(& git -C $Repository -c core.quotepath=false status --porcelain=v1 --untracked-files=all)
  if ($LASTEXITCODE -ne 0) { throw "Cannot inspect source status ($Stage)." }
  $summary = @(& git -C $Repository -c core.quotepath=false diff --no-ext-diff --no-textconv --stat --summary HEAD --)
  if ($LASTEXITCODE -ne 0) { throw "Cannot summarize source changes ($Stage)." }

  if (-not $Manifest.ContainsKey('sourceProvenance')) { $Manifest.sourceProvenance = @{} }
  $Manifest.sourceProvenance[$Stage] = @{
    observedAtUtc = [DateTime]::UtcNow.ToString('o')
    statusPorcelain = $status
    trackedDiffSummary = $summary
  }
  # A later clean snapshot must not erase changes that affected the build.
  $Manifest.dirty = ($Manifest['dirty'] -eq $true) -or $status.Count -gt 0
}
