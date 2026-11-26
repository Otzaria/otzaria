Set-StrictMode -Version Latest

function Get-PerfBindingIdentity {
  param([ValidateSet('integration', 'framework')][string]$BindingMode)
  if ($BindingMode -eq 'framework') {
    return @{
      bindingMode = 'framework'; bindingClass = 'WidgetsFlutterBinding'
      framePolicy = 'frameworkRequested'; platformDispatcher = 'native'
      probeTarget = 'tool/perf_probe/framework_pdf_probe.dart'
    }
  }
  return @{
    bindingMode = 'integration'; bindingClass = 'IntegrationTestWidgetsFlutterBinding'
    framePolicy = 'fullyLive'; platformDispatcher = 'test'
    probeTarget = 'integration_test/perf_resource_probe_test.dart'
  }
}

function Assert-PerfBindingIdentity {
  param($Value, [ValidateSet('integration', 'framework')][string]$BindingMode)
  $expected = Get-PerfBindingIdentity $BindingMode
  foreach ($key in $expected.Keys) {
    if ($null -eq $Value -or $Value.$key -isnot [string] -or $Value.$key -cne $expected[$key]) {
      throw "Missing or unexpected $BindingMode binding identity: $key"
    }
  }
}

function Assert-PerfFrameworkScheduler {
  param($Notes, $LaunchCount)
  $evidence = @($Notes | Where-Object {
    $null -ne $_ -and (
      ($_ -is [Collections.IDictionary] -and $_.Contains('name')) -or
      $null -ne $_.PSObject.Properties['name']
    ) -and $_.name -eq 'framework.scheduler_contract'
  })
  if (($LaunchCount -isnot [int] -and $LaunchCount -isnot [long]) -or
      $LaunchCount -lt 1 -or $evidence.Count -ne $LaunchCount) {
    throw 'Expected one framework scheduling check per measured launch.'
  }
  $seen = [Collections.Generic.HashSet[long]]::new()
  foreach ($note in $evidence) {
    $index = $note.launchIndex
    if (($index -isnot [int] -and $index -isnot [long]) -or $index -lt 0 -or
        $index -ge $LaunchCount -or -not $seen.Add($index)) {
      throw 'Foreign or duplicate framework scheduling launch.'
    }
    $record = $note.frameworkScheduler
    if ($record.status -cne 'passed' -or
        $record.source -cne 'Timer -> SchedulerBinding.scheduleFrame -> postFrameCallback' -or
        $record.deferredFrameDelivered -isnot [bool] -or -not $record.deferredFrameDelivered -or
        $record.nativePlatformDispatcher -isnot [bool] -or -not $record.nativePlatformDispatcher -or
        $record.bindingClass -cne 'WidgetsFlutterBinding') {
      throw 'The native framework did not deliver a deferred frame.'
    }
    foreach ($key in @('requestedAtUs', 'completedAtUs', 'frameTimestampUs')) {
      if (($record.$key -isnot [int] -and $record.$key -isnot [long]) -or $record.$key -lt 0) {
        throw "Missing framework scheduling timestamp: $key"
      }
    }
    if ($record.completedAtUs -lt $record.requestedAtUs) { throw 'The frame predates its request.' }
  }
}

Export-ModuleMember -Function Get-PerfBindingIdentity, Assert-PerfBindingIdentity, Assert-PerfFrameworkScheduler
