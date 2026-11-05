# Windows process-tree samples. Empty cells mean unavailable, never zero.
param(
  [Parameter(Mandatory = $true)][string]$OutCsv,
  [Parameter(Mandatory = $true)][string]$StopFile,
  [int]$RootProcessId = 0,
  [long]$RootStartTicks = 0,
  [string]$ProcessName = "otzaria",
  [ValidateRange(100, 60000)][int]$IntervalMs = 500,
  [ValidateRange(100, 60000)][int]$TreeRefreshMs = 2000,
  [int]$LaunchIndex = 0,
  [switch]$DefinitionsOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-PerfIdentityTicks([datetime]$Created) {
  $ticks = $Created.ToUniversalTime().Ticks
  # CIM creation dates have less precision than Process.StartTime.
  return $ticks - ($ticks % 10000)
}

function Get-PerfProcessTree([object[]]$Snapshot, [int]$RootId,
                            [long]$CreatedTicks, [hashtable]$Known = @{}) {
  $alive = @{}
  foreach ($item in $Snapshot) {
    if ($null -eq $item.CreationDate) { continue }
    $id = [int]$item.ProcessId
    $alive[$id] = @{
      id = $id; parent = [int]$item.ParentProcessId
      born = Get-PerfIdentityTicks $item.CreationDate
    }
  }
  $tree = @{}
  if (-not $alive.ContainsKey($RootId) -or $alive[$RootId].born -ne $CreatedTicks) {
    return $tree
  }
  $tree[$RootId] = $CreatedTicks
  foreach ($id in $Known.Keys) {
    if ($alive.ContainsKey($id) -and $alive[$id].born -eq $Known[$id]) {
      $tree[$id] = $Known[$id]
    }
  }
  do {
    $changed = $false
    foreach ($item in $alive.Values) {
      if (-not $tree.ContainsKey($item.id) -and $tree.ContainsKey($item.parent) -and
          $item.born -ge $tree[$item.parent]) {
        $tree[$item.id] = $item.born
        $changed = $true
      }
    }
  } while ($changed)
  return $tree
}

function ConvertTo-PerfCsvNumber($Value) {
  if ($null -eq $Value) { return '' }
  return ([System.IFormattable]$Value).ToString($null, [cultureinfo]::InvariantCulture)
}

if ($DefinitionsOnly) { return }
if (-not $IsWindows) { throw 'sample_resources.ps1 requires Windows and PowerShell 7.' }

function Write-PerfSampleError([string]$Operation, [string]$Detail) {
  $script:sampleErrors++
  @{ epoch_ms = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
     operation = $Operation; detail = $Detail } |
    ConvertTo-Json -Compress | Add-Content -LiteralPath "$OutCsv.errors.jsonl" -Encoding utf8
}

$header = 'epoch_ms,pid,name,cpu_total_s,ws_mb,priv_mb,identity_start_ticks,handles,threads,root_pid,monotonic_ms,launch_index,tree_age_ms'
$writer = [IO.StreamWriter]::new($OutCsv, $false, [Text.UTF8Encoding]::new($false))
$clock = [Diagnostics.Stopwatch]::StartNew()
$tree = @{}
$lastTreeAt = -$TreeRefreshMs
$reason = 'stopped'
$sampleCount = 0
$sawRoot = $false
$script:sampleErrors = 0
try {
  $writer.WriteLine($header)
  $writer.Flush()
  while (-not (Test-Path -LiteralPath $StopFile)) {
    $tick = $clock.ElapsedMilliseconds
    if ($RootProcessId -eq 0) {
      $roots = @(Get-Process -Name $ProcessName -ErrorAction SilentlyContinue)
      if ($roots.Count -gt 1) { throw 'More than one root process; pass -RootProcessId.' }
      if ($roots.Count -eq 0) {
        Start-Sleep -Milliseconds $IntervalMs
        continue
      }
      $RootProcessId = $roots[0].Id
      $RootStartTicks = Get-PerfIdentityTicks $roots[0].StartTime
      foreach ($item in $roots) { $item.Dispose() }
    }
    try {
      $root = [Diagnostics.Process]::GetProcessById($RootProcessId)
      try {
        $birth = Get-PerfIdentityTicks $root.StartTime
        if ($RootStartTicks -eq 0) { $RootStartTicks = $birth }
        if ($birth -ne $RootStartTicks) { $reason = 'root_identity_changed'; break }
        $sawRoot = $true
      } finally { $root.Dispose() }
    } catch [ArgumentException] { $reason = 'root_exited'; break }

    if ($tick - $lastTreeAt -ge $TreeRefreshMs) {
      try {
        $snapshot = @(Get-CimInstance Win32_Process -Property ProcessId, ParentProcessId, CreationDate)
        $tree = Get-PerfProcessTree $snapshot $RootProcessId $RootStartTicks $tree
        foreach ($item in $snapshot) {
          if ($null -eq $item.CreationDate -and $tree.ContainsKey([int]$item.ParentProcessId)) {
            Write-PerfSampleError 'process_identity' "Creation time unavailable for child $($item.ProcessId)."
          }
        }
        $lastTreeAt = $clock.ElapsedMilliseconds
      } catch { Write-PerfSampleError 'process_tree' $_.Exception.Message }
    }
    if (-not $tree.ContainsKey($RootProcessId)) { $tree[$RootProcessId] = $RootStartTicks }
    $epoch = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    $monotonic = $clock.ElapsedMilliseconds
    foreach ($id in @($tree.Keys | Sort-Object)) {
      $process = $null
      try {
        $process = [Diagnostics.Process]::GetProcessById($id)
        $process.Refresh()
        if ((Get-PerfIdentityTicks $process.StartTime) -ne $tree[$id]) { continue }
        $cpu = $ws = $private = $handles = $threads = $null
        $readErrors = [Collections.Generic.List[string]]::new()
        try { $cpu = $process.TotalProcessorTime.TotalSeconds }
        catch { $readErrors.Add("cpu: $($_.Exception.Message)") }
        try { $ws = $process.WorkingSet64 / 1MB; $private = $process.PrivateMemorySize64 / 1MB }
        catch { $readErrors.Add("memory: $($_.Exception.Message)") }
        try { $handles = $process.HandleCount; $threads = $process.Threads.Count }
        catch { $readErrors.Add("handles_threads: $($_.Exception.Message)") }
        if ($process.HasExited) { continue }
        foreach ($errorText in $readErrors) { Write-PerfSampleError 'metric' "${id}: $errorText" }
        $name = $process.ProcessName.Replace(',', '_').Replace('"', '_')
        $values = @($epoch, $id, $name, (ConvertTo-PerfCsvNumber $cpu),
          (ConvertTo-PerfCsvNumber $ws), (ConvertTo-PerfCsvNumber $private),
          $tree[$id], (ConvertTo-PerfCsvNumber $handles), (ConvertTo-PerfCsvNumber $threads),
          $RootProcessId, $monotonic, $LaunchIndex, ($monotonic - $lastTreeAt))
        $writer.WriteLine(($values -join ','))
        $sampleCount++
      } catch [ArgumentException] {
        # Exits between enumeration and sampling are expected; do not invent a row.
      } catch { Write-PerfSampleError 'process' "${id}: $($_.Exception.Message)" }
      finally { if ($null -ne $process) { $process.Dispose() } }
    }
    $writer.Flush()
    $remaining = $IntervalMs - ($clock.ElapsedMilliseconds - $tick)
    if ($remaining -gt 0) { Start-Sleep -Milliseconds $remaining }
  }
} catch {
  $reason = 'error'
  Write-PerfSampleError 'sampler' $_.Exception.Message
  throw
} finally {
  $writer.Dispose()
  @{ complete = ($reason -eq 'stopped' -and $sawRoot -and $sampleCount -gt 0 -and $script:sampleErrors -eq 0)
     reason = $reason; samples = $sampleCount; errors = $script:sampleErrors; launchIndex = $LaunchIndex } |
    ConvertTo-Json | Set-Content -LiteralPath "$OutCsv.status.json" -Encoding utf8
}
