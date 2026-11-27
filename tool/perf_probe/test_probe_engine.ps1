#Requires -Version 7.4
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'probe_engine.psm1') -Force

$root = Join-Path ([IO.Path]::GetTempPath()) ('otzaria-engine-contract-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root | Out-Null
$executable = Join-Path $root 'otzaria.exe'
$dll = Join-Path $root 'flutter_windows.dll'
$revision = 'deb287481e3ce9468f3434937ced4240a70539ca'
$checks = 0
function Require([bool]$Condition, [string]$Message) {
  if (-not $Condition) { throw $Message }
  $script:checks++
}
function Reject([scriptblock]$Action, [string]$Message) {
  $failed = $false
  try { & $Action } catch { $failed = $true }
  Require $failed $Message
}
try {
  [IO.File]::WriteAllBytes($executable, [byte[]](1, 2, 3))
  Reject { Get-PerfWindowsEngineIdentity $executable release $revision } 'Missing bundle DLL was accepted.'
  [IO.File]::WriteAllBytes($dll, [byte[]](8, 16, 32, 64))
  $hash = (Get-FileHash -LiteralPath $dll -Algorithm SHA256).Hash.ToLowerInvariant()
  $release = Get-PerfWindowsEngineIdentity $executable release $revision ($hash.ToUpperInvariant())
  Require ($release.buildMode -eq 'release' -and $release.bundleSha256 -ceq $hash) 'Actual bundle hash was not recorded.'
  Require ($release.verification -eq 'patched-action-sha256' -and $release.expectedSha256 -ceq $hash) 'Patch verification was not recorded.'
  Assert-PerfWindowsEngineUnchanged $executable $release
  $checks++
  foreach ($mode in 'debug', 'profile', 'release') {
    $identity = Get-PerfWindowsEngineIdentity $executable $mode $revision
    Require ($identity.verification -eq 'bundle-sha256' -and -not $identity.Contains('expectedSha256')) 'An ordinary bundle claimed a patched action.'
    Assert-PerfWindowsEngineUnchanged $executable $identity
    $checks++
  }
  Reject { Get-PerfWindowsEngineIdentity $executable profile $revision $hash } 'A release patch was accepted for profile.'
  Reject { Get-PerfWindowsEngineIdentity $executable release 'invalid' $hash } 'An invalid engine revision was accepted.'
  Reject { Get-PerfWindowsEngineIdentity $executable release $revision 'invalid' } 'An invalid expected hash was accepted.'
  Reject { Get-PerfWindowsEngineIdentity $executable release $revision ('0' * 64) } 'A mismatched patched DLL was accepted.'
  $profile = Get-PerfWindowsEngineIdentity $executable profile $revision
  [IO.File]::WriteAllBytes($dll, [byte[]](9, 16, 32, 64))
  Reject { Assert-PerfWindowsEngineUnchanged $executable $release } 'A changed patched DLL was accepted before launch.'
  Reject { Assert-PerfWindowsEngineUnchanged $executable $profile } 'A changed ordinary DLL was accepted before launch.'
  Remove-Item -LiteralPath $dll
  Reject { Assert-PerfWindowsEngineUnchanged $executable $profile } 'A removed DLL was accepted before launch.'
  Write-Host "Passed $checks engine bundle identity assertions."
} finally {
  Remove-Item -LiteralPath $root -Recurse -Force
}
