# מוריד את התוספים שברשימת ההיתר אל installer\bundled_plugins, כדי שהמתקין
# יארוז אותם ואוצריא תרשום אותם בעלייה הראשונה (docs/bundled_plugins.md).
#
# רשימת ההיתר היא lib/plugins/services/bundled_plugin_ids.dart — אותו קובץ
# שנקמפל אל תוך האפליקציה, כדי שלא תיווצר רשימה שנייה שיוצאת מסינכרון.
# כל רשומה היא זוג 'מזהה-חנות': 'מזהה-מניפסט' — ההורדה לפי מזהה החנות,
# והקובץ נשמר בשם מזהה המניפסט, שמולו האפליקציה מאמתת את הארכיון.
# רשימה ריקה = לא נוצרת תיקייה, וה-Source במתקין מדלג עליה.

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$allowlistFile = Join-Path $repoRoot 'lib\plugins\services\bundled_plugin_ids.dart'
$outputDir = Join-Path $PSScriptRoot 'bundled_plugins'
$storeBaseUrl = 'https://otzaria.org'

if (-not (Test-Path $allowlistFile)) {
    throw "Bundled plugin allowlist not found: $allowlistFile"
}

# זוג יחיד במרכאות בשורה שאינה הערה — הפורמט שהקובץ מתחייב לו.
$plugins = @()
foreach ($line in Get-Content $allowlistFile) {
    $trimmed = $line.Trim()
    if ($trimmed.StartsWith('//') -or $trimmed.StartsWith('///')) { continue }
    $match = [regex]::Match($trimmed, "^'([^']+)':\s*'([^']+)',?$")
    if ($match.Success) {
        $plugins += [pscustomobject]@{
            StoreId    = $match.Groups[1].Value
            ManifestId = $match.Groups[2].Value
        }
    }
}

if ($plugins.Count -eq 0) {
    Write-Host 'No bundled plugins configured - skipping.'
    if (Test-Path $outputDir) { Remove-Item -Path $outputDir -Recurse -Force }
    exit 0
}

# גרסת האוצריא נשלחת לחנות כדי לקבל את גרסת התוסף התואמת ולא את האחרונה.
$versionLine = Select-String -Path (Join-Path $repoRoot 'pubspec.yaml') `
    -Pattern '^version:\s*(.+)$' | Select-Object -First 1
if (-not $versionLine) { throw 'Could not read version from pubspec.yaml' }
$appVersion = $versionLine.Matches[0].Groups[1].Value.Trim().Split('+')[0]
Write-Host "Downloading $($plugins.Count) bundled plugin(s) for Otzaria $appVersion"

if (Test-Path $outputDir) { Remove-Item -Path $outputDir -Recurse -Force }
New-Item -ItemType Directory -Path $outputDir -Force | Out-Null

foreach ($plugin in $plugins) {
    if ($plugin.StoreId -notmatch '^[A-Za-z0-9._-]+$') {
        throw "Invalid store id in allowlist: '$($plugin.StoreId)'"
    }
    if ($plugin.ManifestId -notmatch '^[A-Za-z0-9._-]+$') {
        throw "Invalid manifest id in allowlist: '$($plugin.ManifestId)'"
    }

    $target = Join-Path $outputDir "$($plugin.ManifestId).otzplugin"
    $url = "$storeBaseUrl/api/plugins/$($plugin.StoreId)/download?appVersion=$appVersion"
    Write-Host "  $($plugin.ManifestId) <- $url"
    Invoke-WebRequest -Uri $url -OutFile $target -UseBasicParsing

    # תשובת שגיאה שהוגשה כ-200 (דף HTML) נשמרת כארכיון תקין למראה ונכשלת רק
    # אצל המשתמש — בודקים את חתימת ה-ZIP כאן.
    $magic = [System.IO.File]::ReadAllBytes($target)[0..1]
    if ($magic[0] -ne 0x50 -or $magic[1] -ne 0x4B) {
        throw "Downloaded file for '$($plugin.ManifestId)' is not a zip archive"
    }

    # אימות מוקדם של החוזה מול האפליקציה: מזהה המניפסט שבארכיון חייב להתאים
    # לרשומה — אחרת ה-seeder ידחה את הארכיון בשקט אצל המשתמש.
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [System.IO.Compression.ZipFile]::OpenRead($target)
    try {
        $entry = $zip.GetEntry('manifest.json')
        if (-not $entry) { throw "No manifest.json in archive for '$($plugin.ManifestId)'" }
        $reader = New-Object System.IO.StreamReader($entry.Open())
        $manifest = $reader.ReadToEnd() | ConvertFrom-Json
        $reader.Dispose()
    } finally {
        $zip.Dispose()
    }
    if ($manifest.id -ne $plugin.ManifestId) {
        throw "Manifest id mismatch for store id '$($plugin.StoreId)': allowlist says '$($plugin.ManifestId)' but archive declares '$($manifest.id)'"
    }

    $sizeKb = [math]::Round((Get-Item $target).Length / 1KB, 1)
    Write-Host "    ok ($sizeKb KB, v$($manifest.version))"
}
