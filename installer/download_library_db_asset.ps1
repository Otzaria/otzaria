# מוריד את מסד הספרייה המלא של release של SeforimLibrary ומאמת אותו, כמו
# tool/release/library_db_asset.sh: עד סכמה 5 seforim.db.zst, ומסכמה 6
# seforim-schema<N>.zdb עם <name>.manifest.json. נבחרת הסכמה הגבוהה שהתוכנה קוראת.
# נשמר כ-<OutDir>\seforim.db.zst או <OutDir>\seforim.zdb, והנתיב מודפס בסוף.
param(
  [Parameter(Mandatory = $true)] [string]$OutDir,
  [string]$ReleaseApi = 'https://api.github.com/repos/Otzaria/SeforimLibrary/releases/latest'
)

$ErrorActionPreference = 'Stop'

function Fail([string]$Message) {
  Write-Host "::error::$Message"
  exit 1
}

function Get-Sha256([string]$Path) {
  (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

# curl ולא Invoke-WebRequest: קורא גם file:// (בטסטים) ומהיר בהרבה בקובץ של ~2GB.
$curl = Get-Command curl.exe -CommandType Application -ErrorAction SilentlyContinue |
  Select-Object -First 1
if (-not $curl) {
  $curl = Get-Command curl -CommandType Application -ErrorAction SilentlyContinue |
    Select-Object -First 1
}
if (-not $curl) { Fail 'curl was not found' }

function Invoke-Fetch([string]$Url, [string]$OutFile) {
  $curlArgs = @('-fsSL', '--retry', '3', '--retry-delay', '5', '-o', $OutFile)
  if ($env:GH_TOKEN -and $Url.StartsWith('https://api.github.com/')) {
    $curlArgs += @('-H', "Authorization: Bearer $env:GH_TOKEN")
  }
  & $curl.Source @curlArgs $Url
  if ($LASTEXITCODE -ne 0) { Fail "cannot download $Url (curl exit $LASTEXITCODE)" }
}

$constants = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot '..\lib\data\constants\database_constants.dart')
if ($constants -notmatch 'static const int readableDbSchemaVersion = (\d+);') {
  Fail 'cannot read readableDbSchemaVersion from lib/data/constants/database_constants.dart'
}
$maxSchema = [int]$Matches[1]

New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
$work = Join-Path $OutDir ('.library-db.' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work | Out-Null
try {
  $releasePath = Join-Path $work 'release.json'
  Invoke-Fetch $ReleaseApi $releasePath
  $release = Get-Content -Raw -LiteralPath $releasePath -Encoding utf8 | ConvertFrom-Json

  $best = $null
  $bestSchema = -1
  foreach ($asset in $release.assets) {
    if ($asset.name -ceq 'seforim.db.zst') {
      $schema = 0  # סכמה 5 ומטה; השם שמור לה
    } elseif ($asset.name -cmatch '^seforim-schema([1-9][0-9]*)\.zdb$') {
      $schema = [int]$Matches[1]
      if ($schema -gt $maxSchema) { continue }
    } else {
      continue
    }
    if ($schema -gt $bestSchema) { $best = $asset; $bestSchema = $schema }
  }
  if (-not $best) {
    Fail "release $($release.tag_name) has no seforim.db.zst or seforim-schema<N>.zdb asset this app reads (schema <= $maxSchema)"
  }

  $localName = if ($bestSchema -eq 0) { 'seforim.db.zst' } else { 'seforim.zdb' }
  $localPath = Join-Path $work $localName
  Write-Host "Library DB: $($best.name) from release $($release.tag_name) ($([math]::Round($best.size / 1MB, 2)) MB)"
  Invoke-Fetch $best.browser_download_url $localPath

  $size = (Get-Item -LiteralPath $localPath).Length
  if ($size -ne [int64]$best.size) { Fail "$($best.name) downloaded as $size bytes but the release lists $($best.size)" }
  $sha256 = Get-Sha256 $localPath
  if ($best.digest -and $best.digest -ne "sha256:$sha256") {
    Fail "$($best.name) hashes sha256:$sha256 but the release publishes $($best.digest)"
  }

  if ($bestSchema -ne 0) {
    $manifestName = "$($best.name).manifest.json"
    $manifestAsset = $release.assets | Where-Object { $_.name -ceq $manifestName } | Select-Object -First 1
    if (-not $manifestAsset) { Fail "release $($release.tag_name) publishes $($best.name) without $manifestName" }
    $manifestPath = Join-Path $work 'manifest.json'
    Invoke-Fetch $manifestAsset.browser_download_url $manifestPath
    if ($manifestAsset.digest -and $manifestAsset.digest -ne "sha256:$(Get-Sha256 $manifestPath)") {
      Fail "$manifestName does not match the digest the release publishes"
    }
    $manifest = Get-Content -Raw -LiteralPath $manifestPath -Encoding utf8 | ConvertFrom-Json
    $expected = [ordered]@{
      manifestVersion = 1
      file = $best.name
      size = $size
      sha256 = $sha256
      dbSchemaVersion = $bestSchema
    }
    foreach ($key in $expected.Keys) {
      if ("$($manifest.$key)" -cne "$($expected[$key])") {
        Fail "$manifestName has $key '$($manifest.$key)', expected '$($expected[$key])'"
      }
    }
  }

  foreach ($stale in @('seforim.db.zst', 'seforim.zdb')) {
    Remove-Item -LiteralPath (Join-Path $OutDir $stale) -Force -ErrorAction SilentlyContinue
  }
  $target = Join-Path $OutDir $localName
  Move-Item -LiteralPath $localPath -Destination $target
  Write-Output $target
}
finally {
  Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
