Set-StrictMode -Version Latest

function Get-PerfWindowsEngineIdentity {
  param(
    [Parameter(Mandatory)][string]$Executable,
    [Parameter(Mandatory)][ValidateSet('debug', 'profile', 'release')][string]$Mode,
    [Parameter(Mandatory)][string]$EngineRevision,
    [string]$ExpectedSha256 = ''
  )
  if ($EngineRevision -cnotmatch '^[a-f0-9]{40}$') {
    throw 'Flutter engine revision must be a lowercase Git SHA.'
  }
  if ($ExpectedSha256 -and ($Mode -ne 'release' -or $ExpectedSha256 -notmatch '^[a-fA-F0-9]{64}$')) {
    throw 'An expected patched engine SHA-256 is supported only for a release build.'
  }
  $dll = Join-Path ([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($Executable))) 'flutter_windows.dll'
  if (-not (Test-Path -LiteralPath $dll -PathType Leaf)) {
    throw "Bundled Flutter engine is missing: $dll"
  }
  $actual = (Get-FileHash -LiteralPath $dll -Algorithm SHA256).Hash.ToLowerInvariant()
  if ($ExpectedSha256 -and $actual -ne $ExpectedSha256.ToLowerInvariant()) {
    throw "Bundled Flutter engine does not match the patched action hash: $actual"
  }
  $identity = [ordered]@{
    schemaVersion = 1
    platform = 'windows'
    architecture = 'x64'
    buildMode = $Mode
    engineRevision = $EngineRevision
    bundleSha256 = $actual
    verification = 'bundle-sha256'
  }
  if ($ExpectedSha256) {
    $identity['verification'] = 'patched-action-sha256'
    $identity['expectedSha256'] = $ExpectedSha256.ToLowerInvariant()
  }
  return $identity
}

function Assert-PerfWindowsEngineUnchanged {
  param(
    [Parameter(Mandatory)][string]$Executable,
    [Parameter(Mandatory)]$Identity
  )
  $expected = if ($Identity.verification -eq 'patched-action-sha256') {
    $Identity.expectedSha256
  } else { '' }
  $current = Get-PerfWindowsEngineIdentity -Executable $Executable -Mode $Identity.buildMode -EngineRevision $Identity.engineRevision -ExpectedSha256 $expected
  if ($current.bundleSha256 -ne $Identity.bundleSha256) {
    throw 'The bundled Flutter engine changed before launch.'
  }
}

Export-ModuleMember -Function Get-PerfWindowsEngineIdentity, Assert-PerfWindowsEngineUnchanged
