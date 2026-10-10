# מוריד את נכסי הספרייה וכלי החילוץ שמתקין ה-FULL אורז (otzaria_full.iss),
# אל installer\library_db ו-installer\{zstd,7za}.exe. משותף ל-x64 ול-ARM64.

Set-Location (Split-Path -Parent $PSScriptRoot)

Write-Host "Downloading bundled library assets for full installer..."
$ErrorActionPreference = "Stop"
# אימות מונע רייט-לימיט של api.github.com (ה-IP של ה-runner משותף עם משתמשים אחרים)
$apiHeaders = @{ Authorization = "Bearer $env:GH_TOKEN" }

try {
  # הורדת מסד הספרייה הראשי. LIBRARY_DB_RELEASE_TAG מצמיד את כל ה-jobs של
  # ריצת build-and-announce לאותו release; בלעדיו נלקח האחרון.
  $libraryReleases = "https://api.github.com/repos/Otzaria/SeforimLibrary/releases"
  $libraryTag = $env:LIBRARY_DB_RELEASE_TAG
  $libraryReleaseApi = if ($libraryTag) { "$libraryReleases/tags/$libraryTag" } else { "$libraryReleases/latest" }
  $libraryRelease = Invoke-RestMethod -Uri $libraryReleaseApi -Headers $apiHeaders
  if ($libraryTag -and $libraryRelease.tag_name -cne $libraryTag) {
    Write-Host "::error::$libraryReleaseApi is release $($libraryRelease.tag_name), not the pinned $libraryTag"
    exit 1
  }
  # מסכמה 6 ה-DB מתפרסם בשם משלו; seforim.db.zst שמור לסכמה 5 ומטה.
  # DB מעל מגבלת הנכס של GitHub מתפרסם כ-<name>.part-NNN ולצדם <name>.manifest.json.
  $dbAsset = $null
  $dbManifest = $null
  foreach ($name in @("seforim-schema6.db.zst", "seforim.db.zst")) {
    $dbAsset = $libraryRelease.assets | Where-Object { $_.name -eq $name }
    if ($dbAsset) { break }
    $dbManifest = $libraryRelease.assets | Where-Object { $_.name -eq "$name.manifest.json" }
    if ($dbManifest) { break }
  }

  if (-not $dbAsset -and -not $dbManifest) {
    Write-Host "::error::Could not find seforim-schema6.db.zst or seforim.db.zst, whole or split, in release $($libraryRelease.tag_name)"
    exit 1
  }

  Write-Host "Library version: $($libraryRelease.tag_name)"

  if (Test-Path "installer\library_db") {
    Remove-Item -Path "installer\library_db" -Recurse -Force
  }
  New-Item -ItemType Directory -Path "installer\library_db" -Force | Out-Null

  # הורדת ה-DB הדחוס שה-installer יחלץ בזמן ההתקנה
  $ProgressPreference = 'SilentlyContinue'
  if ($dbAsset) {
    Write-Host "Downloading from: $($dbAsset.browser_download_url)"
    Write-Host "Size: $([math]::Round($dbAsset.size / 1MB, 2)) MB"
    Invoke-WebRequest -Uri $dbAsset.browser_download_url -OutFile "installer\library_db\seforim.db.zst" -UseBasicParsing
  } else {
    $partsDir = "installer\library_db_parts"
    if (Test-Path $partsDir) { Remove-Item -Path $partsDir -Recurse -Force }
    New-Item -ItemType Directory -Path $partsDir -Force | Out-Null
    $manifestPath = Join-Path $partsDir $dbManifest.name
    Invoke-WebRequest -Uri $dbManifest.browser_download_url -OutFile $manifestPath -UseBasicParsing
    foreach ($part in (Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json).parts) {
      $partAsset = $libraryRelease.assets | Where-Object { $_.name -eq $part.name }
      if (-not $partAsset) {
        Write-Host "::error::$($dbManifest.name) lists $($part.name), which the release does not carry"
        exit 1
      }
      Write-Host "Downloading part: $($part.name) ($([math]::Round($part.size / 1MB, 2)) MB)"
      Invoke-WebRequest -Uri $partAsset.browser_download_url -OutFile (Join-Path $partsDir $part.name) -UseBasicParsing
    }
    # מאמת כל חלק ואת השלם לפי ה-sha256 שבמניפסט.
    & "$PSScriptRoot\..\tool\release\assemble_split_asset.ps1" $manifestPath "installer\library_db\seforim.db.zst"
    Remove-Item -Path $partsDir -Recurse -Force
  }
  Write-Host "Compressed library DB downloaded successfully"

  # הורדת מסד הקטלוגים החיצוני
  Write-Host "Downloading external catalog DB for full installer from Otzaria/otzar-HB_catalog..."
  $catalogRelease = Invoke-RestMethod -Uri "https://api.github.com/repos/Otzaria/otzar-HB_catalog/releases/latest" -Headers $apiHeaders
  $catalogAsset = $catalogRelease.assets | Where-Object { $_.name -eq "otzar-HB_catalog.db.zst" }

  if (-not $catalogAsset) {
    Write-Host "::error::Could not find otzar-HB_catalog.db.zst in latest release"
    exit 1
  }

  Write-Host "Catalog version: $($catalogRelease.tag_name)"
  Write-Host "Downloading from: $($catalogAsset.browser_download_url)"
  Write-Host "Size: $([math]::Round($catalogAsset.size / 1MB, 2)) MB"
  Invoke-WebRequest -Uri $catalogAsset.browser_download_url -OutFile "installer\library_db\otzar-HB_catalog.db.zst" -UseBasicParsing
  Write-Host "Compressed external catalog DB downloaded successfully"

  # הורדת ארכיון ה-PDFים של תלמוד בבלי
  $talmudArchiveUrl = "https://github.com/Otzaria/otzaria-library/releases/latest/download/talmud_bavli_latest.tar.zst"
  Write-Host "Downloading bundled Talmud Bavli PDFs for full installer..."
  Write-Host "Downloading from: $talmudArchiveUrl"
  Invoke-WebRequest -Uri $talmudArchiveUrl -OutFile "installer\library_db\talmud_bavli_latest.tar.zst" -UseBasicParsing
  Write-Host "Compressed Talmud Bavli PDFs downloaded successfully"

  # הורדת כלי החילוץ כדי שה-installer יוכל לחלץ את קבצי הספרייה בזמן ההתקנה
  $zstdRelease = Invoke-RestMethod -Uri "https://api.github.com/repos/facebook/zstd/releases/latest" -Headers $apiHeaders
  $zstdAsset = $zstdRelease.assets | Where-Object { $_.name -like "zstd-*-win64.zip" } | Select-Object -First 1
  $sevenZipRelease = Invoke-RestMethod -Uri "https://api.github.com/repos/ip7z/7zip/releases/latest" -Headers $apiHeaders
  $sevenZipBootstrap = $sevenZipRelease.assets | Where-Object { $_.name -eq "7zr.exe" } | Select-Object -First 1
  $sevenZipExtra = $sevenZipRelease.assets | Where-Object { $_.name -like "7z*-extra.7z" } | Select-Object -First 1

  if (-not $zstdAsset) {
    Write-Host "::error::Could not find win64 zstd asset in latest release"
    exit 1
  }

  if ((-not $sevenZipBootstrap) -or (-not $sevenZipExtra)) {
    Write-Host "::error::Could not find 7-Zip bootstrap assets in latest release"
    exit 1
  }

  Write-Host "Downloading zstd from: $($zstdAsset.browser_download_url)"
  Invoke-WebRequest -Uri $zstdAsset.browser_download_url -OutFile "installer\zstd-win64.zip" -UseBasicParsing

  if (Test-Path "installer\zstd_tmp") {
    Remove-Item -Path "installer\zstd_tmp" -Recurse -Force
  }
  Expand-Archive -Path "installer\zstd-win64.zip" -DestinationPath "installer\zstd_tmp" -Force

  $zstdExe = Get-ChildItem -Path "installer\zstd_tmp" -Filter "zstd.exe" -Recurse | Select-Object -First 1 -ExpandProperty FullName
  if (-not $zstdExe) {
    Write-Host "::error::zstd.exe was not found inside downloaded archive"
    exit 1
  }

  Copy-Item -Path $zstdExe -Destination "installer\zstd.exe" -Force

  Write-Host "Downloading 7zr from: $($sevenZipBootstrap.browser_download_url)"
  Invoke-WebRequest -Uri $sevenZipBootstrap.browser_download_url -OutFile "installer\7zr.exe" -UseBasicParsing
  Write-Host "Downloading 7-Zip extra package from: $($sevenZipExtra.browser_download_url)"
  Invoke-WebRequest -Uri $sevenZipExtra.browser_download_url -OutFile "installer\7zip-extra.7z" -UseBasicParsing

  if (Test-Path "installer\7zip_tmp") {
    Remove-Item -Path "installer\7zip_tmp" -Recurse -Force
  }

  & "installer\7zr.exe" x "installer\7zip-extra.7z" "-oinstaller\7zip_tmp" -y
  if ($LASTEXITCODE -ne 0) {
    Write-Host "::error::Failed to extract 7-Zip extra package"
    exit 1
  }

  $sevenZipExe = Get-ChildItem -Path "installer\7zip_tmp" -Filter "7za.exe" -Recurse | Select-Object -First 1 -ExpandProperty FullName
  if (-not $sevenZipExe) {
    Write-Host "::error::7za.exe was not found inside 7-Zip extra package"
    exit 1
  }

  Copy-Item -Path $sevenZipExe -Destination "installer\7za.exe" -Force
  Remove-Item -Path "installer\zstd-win64.zip" -Force
  Remove-Item -Path "installer\zstd_tmp" -Recurse -Force
  Remove-Item -Path "installer\7zip-extra.7z" -Force
  Remove-Item -Path "installer\7zip_tmp" -Recurse -Force
  Write-Host "zstd.exe and 7za.exe prepared successfully"

  # מילון המורפולוגיה (lexical.db) של החיפוש המקורב. ב-release הוא אינו
  # דחוס, לכן דוחסים כאן עם zstd שכבר הוכן, כדי שה-installer יחלץ אותו
  # כמו שאר מסדי הנתונים.
  # lexical-v2.db הוא המילון המתוקן; lexical.db קפוא לגרסאות ישנות של התוכנה.
  # מקומית הוא נשמר תמיד כ-lexical.db.
  Write-Host "Downloading morphology dictionary (lexical-v2.db) from Otzaria/SeforimMagicIndexer..."
  $lexicalBase = "https://github.com/Otzaria/SeforimMagicIndexer/releases/latest/download"
  try {
    Invoke-WebRequest -Uri "$lexicalBase/lexical-v2.db" -OutFile "installer\library_db\lexical.db" -UseBasicParsing
  }
  catch {
    Write-Host "lexical-v2.db unavailable, falling back to lexical.db"
    Invoke-WebRequest -Uri "$lexicalBase/lexical.db" -OutFile "installer\library_db\lexical.db" -UseBasicParsing
  }
  & "installer\zstd.exe" -19 --long=31 -T0 -f "installer\library_db\lexical.db" -o "installer\library_db\lexical.db.zst"
  if ($LASTEXITCODE -ne 0) {
    Write-Host "::error::Failed to compress lexical.db"
    exit 1
  }
  Remove-Item -Path "installer\library_db\lexical.db" -Force
  Write-Host "Morphology dictionary compressed successfully"
}
catch {
  Write-Host "::error::Failed to download library: $_"
  exit 1
}
