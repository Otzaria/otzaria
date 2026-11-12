param([string]$OriginalBytesPath, [string]$ProofPath)
$ErrorActionPreference = 'Stop'
. ./tool/perf_probe/lockfile_quoting.ps1
$proof = Restore-PerfLockfileQuoting (Join-Path $PWD 'pubspec.lock') ([IO.File]::ReadAllBytes($OriginalBytesPath))
$proof | ConvertTo-Json | Set-Content -LiteralPath $ProofPath -Encoding utf8
