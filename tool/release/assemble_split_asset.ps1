$ErrorActionPreference = 'Stop'

if ($args.Count -lt 1 -or $args.Count -gt 3) {
  throw 'usage: assemble_split_asset.ps1 <manifest.json> [output-file] [parts-directory]'
}

$manifestPath = (Resolve-Path -LiteralPath $args[0]).Path
$manifestDir = Split-Path -Parent $manifestPath
$partsDir = if ($args.Count -eq 3) {
  (Resolve-Path -LiteralPath $args[2]).Path
} else {
  $manifestDir
}
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$archiveName = [string]$manifest.archive
if ([IO.Path]::GetFileName($archiveName) -ne $archiveName) {
  throw "unsafe archive name in manifest: $archiveName"
}
if (-not $manifest.parts -or $manifest.parts.Count -eq 0) {
  throw 'manifest contains no parts'
}

$outputPath = if ($args.Count -ge 2) {
  [IO.Path]::GetFullPath($args[1])
} else {
  Join-Path $manifestDir $archiveName
}
if (Test-Path -LiteralPath $outputPath) {
  throw "output already exists: $outputPath"
}

try {
  $archiveHasher = [Security.Cryptography.IncrementalHash]::CreateHash(
    [Security.Cryptography.HashAlgorithmName]::SHA256
  )
  $output = [IO.File]::Open(
    $outputPath,
    [IO.FileMode]::CreateNew,
    [IO.FileAccess]::Write
  )
  try {
    $buffer = [byte[]]::new(4MB)
    foreach ($part in $manifest.parts) {
      $partName = [string]$part.name
      if ([IO.Path]::GetFileName($partName) -ne $partName) {
        throw "unsafe part name in manifest: $partName"
      }
      $partPath = Join-Path $partsDir $partName
      if (-not (Test-Path -LiteralPath $partPath -PathType Leaf)) {
        throw "missing part: $partName"
      }

      $partHasher = [Security.Cryptography.IncrementalHash]::CreateHash(
        [Security.Cryptography.HashAlgorithmName]::SHA256
      )
      $input = [IO.File]::OpenRead($partPath)
      try {
        while (($read = $input.Read($buffer, 0, $buffer.Length)) -gt 0) {
          $partHasher.AppendData($buffer, 0, $read)
          $archiveHasher.AppendData($buffer, 0, $read)
          $output.Write($buffer, 0, $read)
        }
      } finally {
        $input.Dispose()
      }

      $partHash = [BitConverter]::ToString(
        $partHasher.GetHashAndReset()
      ).Replace('-', '').ToLowerInvariant()
      $partHasher.Dispose()
      if ($partHash -ne ([string]$part.sha256).ToLowerInvariant()) {
        throw "checksum mismatch: $partName"
      }
    }
  } finally {
    $output.Dispose()
  }

  $archiveHash = [BitConverter]::ToString(
    $archiveHasher.GetHashAndReset()
  ).Replace('-', '').ToLowerInvariant()
  $archiveHasher.Dispose()
  if ($archiveHash -ne ([string]$manifest.sha256).ToLowerInvariant()) {
    throw "archive checksum mismatch: $outputPath"
  }
} catch {
  Remove-Item -LiteralPath $outputPath -Force -ErrorAction SilentlyContinue
  throw
}

Write-Host "Reassembled and verified: $outputPath"
