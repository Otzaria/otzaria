# מוריד את התוספים שברשימת ההיתר אל installer\bundled_plugins, כדי שהמתקין
# יארוז אותם ואוצריא תרשום אותם בעלייה הראשונה (docs/bundled_plugins.md).
#
# רשימת ההיתר היא lib/plugins/services/bundled_plugin_ids.dart — אותו קובץ
# שנקמפל אל תוך האפליקציה, כדי שלא תיווצר רשימה שנייה שיוצאת מסינכרון.
# רשימה ריקה = לא נוצרת תיקייה, וה-Source במתקין מדלג עליה.

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$allowlistFile = Join-Path $repoRoot 'lib\plugins\services\bundled_plugin_ids.dart'
$outputDir = Join-Path $PSScriptRoot 'bundled_plugins'
$storeBaseUrl = 'https://otzaria.org'

if (-not (Test-Path $allowlistFile)) {
    throw "Bundled plugin allowlist not found: $allowlistFile"
}

# מזהה יחיד במרכאות בשורה שאינה הערה — הפורמט שהקובץ מתחייב לו.
$pluginIds = @()
foreach ($line in Get-Content $allowlistFile) {
    $trimmed = $line.Trim()
    if ($trimmed.StartsWith('//') -or $trimmed.StartsWith('///')) { continue }
    $match = [regex]::Match($trimmed, "^'([^']+)',?$")
    if ($match.Success) { $pluginIds += $match.Groups[1].Value }
}

if ($pluginIds.Count -eq 0) {
    Write-Host 'No bundled plugins configured - skipping.'
    if (Test-Path $outputDir) { Remove-Item -Path $outputDir -Recurse -Force }
    exit 0
}

# גרסת האוצריא נשלחת לחנות כדי לקבל את גרסת התוסף התואמת ולא את האחרונה.
$versionLine = Select-String -Path (Join-Path $repoRoot 'pubspec.yaml') `
    -Pattern '^version:\s*(.+)$' | Select-Object -First 1
if (-not $versionLine) { throw 'Could not read version from pubspec.yaml' }
$appVersion = $versionLine.Matches[0].Groups[1].Value.Trim().Split('+')[0]
Write-Host "Downloading $($pluginIds.Count) bundled plugin(s) for Otzaria $appVersion"

if (Test-Path $outputDir) { Remove-Item -Path $outputDir -Recurse -Force }
New-Item -ItemType Directory -Path $outputDir -Force | Out-Null

foreach ($pluginId in $pluginIds) {
    if ($pluginId -notmatch '^[A-Za-z0-9._-]+$') {
        throw "Invalid plugin id in allowlist: '$pluginId'"
    }

    $target = Join-Path $outputDir "$pluginId.otzplugin"
    $url = "$storeBaseUrl/api/plugins/$pluginId/download?appVersion=$appVersion"
    Write-Host "  $pluginId <- $url"
    Invoke-WebRequest -Uri $url -OutFile $target -UseBasicParsing

    # תשובת שגיאה שהוגשה כ-200 (דף HTML) נשמרת כארכיון תקין למראה ונכשלת רק
    # אצל המשתמש — בודקים את חתימת ה-ZIP כאן.
    $magic = [System.IO.File]::ReadAllBytes($target)[0..1]
    if ($magic[0] -ne 0x50 -or $magic[1] -ne 0x4B) {
        throw "Downloaded file for '$pluginId' is not a zip archive"
    }
    $sizeKb = [math]::Round((Get-Item $target).Length / 1KB, 1)
    Write-Host "    ok ($sizeKb KB)"
}
