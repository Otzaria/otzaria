#Requires -Version 7.4
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'probe_binding.psm1') -Force
$count = 0

function Check([scriptblock]$Action, [bool]$ShouldThrow = $false) {
  $thrown = $false
  try { & $Action } catch { $thrown = $true }
  if ($thrown -ne $ShouldThrow) { throw "Unexpected contract result: $Action" }
  $script:count++
}

function Copy-Value($Value) {
  $Value | ConvertTo-Json -Depth 20 | ConvertFrom-Json
}

foreach ($mode in @('integration', 'framework')) {
  $identity = Get-PerfBindingIdentity $mode
  Check { Assert-PerfBindingIdentity $identity $mode }
  foreach ($key in $identity.Keys) {
    $missing = Copy-Value $identity
    $missing.PSObject.Properties.Remove($key)
    Check { Assert-PerfBindingIdentity $missing $mode } $true
  }
}
Check { Get-PerfBindingIdentity 'benchmarkLive' } $true
Check { Assert-PerfBindingIdentity (Get-PerfBindingIdentity 'integration') 'framework' } $true

$note = [pscustomobject]@{
  type = 'note'; name = 'framework.scheduler_contract'; launchIndex = 0
  frameworkScheduler = [pscustomobject]@{
    status = 'passed'
    source = 'Timer -> SchedulerBinding.scheduleFrame -> postFrameCallback'
    deferredFrameDelivered = $true; nativePlatformDispatcher = $true
    bindingClass = 'WidgetsFlutterBinding'
    requestedAtUs = 25000; completedAtUs = 30000; frameTimestampUs = 45000
  }
}
Check { Assert-PerfFrameworkScheduler @($note) 1 }
Check { Assert-PerfFrameworkScheduler @([pscustomobject]@{ type = 'note'; detail = 'unrelated' }, $note) 1 }
Check { Assert-PerfFrameworkScheduler @() 1 } $true
Check { Assert-PerfFrameworkScheduler @($note, $note) 1 } $true
foreach ($key in $note.frameworkScheduler.PSObject.Properties.Name) {
  $missing = Copy-Value $note
  $missing.frameworkScheduler.PSObject.Properties.Remove($key)
  Check { Assert-PerfFrameworkScheduler @($missing) 1 } $true
}
foreach ($mutation in @(
  @{ key = 'requestedAtUs'; value = $true },
  @{ key = 'completedAtUs'; value = 1 },
  @{ key = 'frameTimestampUs'; value = -1 },
  @{ key = 'nativePlatformDispatcher'; value = $false },
  @{ key = 'deferredFrameDelivered'; value = 1 },
  @{ key = 'bindingClass'; value = 'IntegrationTestWidgetsFlutterBinding' }
)) {
  $invalid = Copy-Value $note
  $invalid.frameworkScheduler.($mutation.key) = $mutation.value
  Check { Assert-PerfFrameworkScheduler @($invalid) 1 } $true
}
foreach ($index in @($true, 1, -1, 0.0)) {
  $invalid = Copy-Value $note
  $invalid.launchIndex = $index
  Check { Assert-PerfFrameworkScheduler @($invalid) 1 } $true
}
foreach ($launchCount in @($true, 1.0, $null, 0)) {
  Check { Assert-PerfFrameworkScheduler @($note) $launchCount } $true
}
Write-Output "$count binding and scheduling contracts passed."
