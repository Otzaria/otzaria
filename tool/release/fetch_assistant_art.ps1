# Fetch the pinned Download Assistant art (Otzaria/otzaria-design) into
# installer\assistant_art before ISCC compiles installer\download_assistant.iss or the
# Otzaria installers (installer\otzaria*.iss), which share the same UI layer and art.
#
#   pwsh tool/release/fetch_assistant_art.ps1 [-PinFile <pin.json>] [-Destination <dir>]
#
# installer\assistant_art.pin.json is the only place that names the version.
param(
  [string]$PinFile = (Join-Path $PSScriptRoot '..\..\installer\assistant_art.pin.json'),
  [string]$Destination = (Join-Path $PSScriptRoot '..\..\installer\assistant_art')
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$pin = Get-Content -LiteralPath $PinFile -Raw | ConvertFrom-Json
$version = [string]$pin.version
$url = [string]$pin.url
$sha256 = ([string]$pin.sha256).ToLowerInvariant()
if ($version -notmatch '^\d+\.\d+\.\d+$') { throw "bad version in ${PinFile}: '$version'" }
if ($sha256 -notmatch '^[0-9a-f]{64}$') { throw "bad sha256 in ${PinFile}: '$sha256'" }
if (-not $url.StartsWith('https://github.com/Otzaria/')) { throw "url in $PinFile is not an Otzaria GitHub release: $url" }

$Destination = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Destination)
# The stamp, not the files' presence, says which zip the folder came from.
$stampName = '.pinned-sha256'
$stamp = Join-Path $Destination $stampName
if ((Test-Path -LiteralPath $stamp -PathType Leaf) -and
    (Get-Content -LiteralPath $stamp -Raw).Trim() -eq $sha256) {
  Write-Host "Assistant art $version is already in $Destination"
  exit 0
}

$work = Join-Path (Split-Path -Parent $Destination) ('.assistant-art.' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work | Out-Null
try {
  $zip = Join-Path $work 'art.zip'
  for ($attempt = 1; ; $attempt++) {
    try {
      Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing -TimeoutSec 120
      break
    } catch {
      if ($attempt -ge 3) { throw "cannot download assistant art $version from ${url}: $_" }
      Write-Host "Download attempt $attempt failed ($_); retrying..."
      Start-Sleep -Seconds (5 * $attempt)
    }
  }

  $actual = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
  if ($actual -ne $sha256) {
    throw "SHA-256 mismatch for ${url}: pinned $sha256, downloaded $actual. The release asset is not the pinned one; update $PinFile only from pack_release.py's output."
  }

  $staged = Join-Path $work 'assistant_art'
  Expand-Archive -LiteralPath $zip -DestinationPath $staged
  $isi = Join-Path $staged 'assistant_art.isi'
  if (-not (Test-Path -LiteralPath $isi -PathType Leaf)) { throw "the art zip has no assistant_art.isi at its root" }
  $declared = Select-String -LiteralPath $isi -Pattern '^#define AA_ART_VERSION "([^"]*)"' | Select-Object -First 1
  $artVersion = if ($declared) { $declared.Matches[0].Groups[1].Value } else { '' }
  if ($artVersion -ne $version) { throw "assistant_art.isi declares AA_ART_VERSION '$artVersion', but the pin is $version" }
  [IO.File]::WriteAllText((Join-Path $staged $stampName), $sha256)

  $previous = Join-Path $work 'previous'
  if (Test-Path -LiteralPath $Destination) { Move-Item -LiteralPath $Destination -Destination $previous }
  try {
    Move-Item -LiteralPath $staged -Destination $Destination
  } catch {
    if (Test-Path -LiteralPath $previous) { Move-Item -LiteralPath $previous -Destination $Destination }
    throw
  }
  Write-Host "Assistant art $version ($((Get-ChildItem -LiteralPath $Destination -File).Count) files) is in $Destination"
} finally {
  Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
