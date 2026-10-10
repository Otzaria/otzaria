# אשף ההורדות של אוצריא — מסמך תכנון

אשף ההורדות (`Otzaria-Download-Assistant-windows.exe`) הוא כלי עזר בעברית שמסייע
למשתמש להוריד את רכיבי אוצריא ולהכין התקנה למחשב **מנותק**. הוא נכס נוסף
ב-release ואינו משנה שום מתקין, שם נכס או נתיב בנייה קיים.

* **שלב 1** — חוזה המניפסט: הגנרטור, הסכמה והבדיקות (הפרק "הסכמה" למטה).
* **שלב 2** — האשף עצמו: `installer/download_assistant.iss` (הפרק "האשף" למטה).
* **שלב 3** — חיווט ל-workflow (הפרק "החיווט ל-CI" למטה).
* **שלב 4** — מסייעים ל-macOS ול-Linux ובחירת פלטפורמת יעד בכל השלושה (הפרק
  "חוזה משותף לכל המסייעים" למטה).

## המצב שנמצא

* `tool/release/split_release_asset.sh` מפצל נכס לחלקים של עד 1,992,294,400
  בתים וכותב `<name>.manifest.json` בצורה
  `{schemaVersion, archive, size, sha256, partSizeLimit, githubAssetLimit, parts[]}`.
  `assemble_split_asset.sh`/`.ps1` מרכיבים ומאמתים. **הצורה הזאת נשמרת** —
  המניפסט החדש משקף אותה ואינו ממציא צורה שנייה לאותו מידע.
* `tool/release/fetch_prebuilt_library_index.sh` מאמת אינדקס בנוי מראש מול
  `otzaria-library-index.provenance.json` לפי שלושה מפתחות:
  `seforimDbZstSha256`, `searchEngineVersion`, `talmudVolumesDigest`. אותם
  מפתחות בדיוק הם מטא-דאטת ההתאמה במניפסט — לא הומצאו חדשים.
* `otzaria-0.9.97-windows-full.exe` שוקל 2,012,390,081 בתים — ‎93.7%‎ ממגבלת
  ה-2 GiB לנכס בודד ב-GitHub. זו הסיבה שחייבת להיות תמיכה בנכס מפוצל.
* **באג רדום שתוקן כאן:** `pickWindowsAssetUrl`
  (`lib/update/my_update_widget.dart`) בחר כל `.exe` שאינו `full` כמתקין
  העדכון, והריץ אותו עם מתגי Inno שקטים. הוספת האשף ל-release הייתה גורמת
  לעדכון מתוך התוכנה להריץ את **האשף** במקום את המתקין. נוסף הפרדיקט
  `isDownloadAssistantAsset` שמחריג אותו.

## הסכמה

הגנרטור: `tool/release/generate_release_manifest.dart`
הסכמה הפורמלית: `tool/release/release_manifest.schema.json`
הבדיקות: `test/release/release_manifest_test.dart`

```bash
dart run tool/release/generate_release_manifest.dart \
  --tag 0.9.97+789 --version 0.9.97 --dir release-files \
  [--out release-files/otzaria-release-manifest.json] \
  [--external external-components.json]
```

הגנרטור גוזר את הרכיבים **ממה שקיים בפועל** בתיקייה, מצטלב מול טבלה
דקלרטיבית של רכיבים ידועים (`kKnownComponents`). רכיב שכל נכסיו חסרים מושמט —
לעולם לא נכתב מציין מקום מסוג "בקרוב". קלט פגום (מניפסט פיצול בגרסת סכמה
אחרת, חלק חסר מהתיקייה, גודל שאינו תואם, hash לא תקין, שם חלק לא בטוח)
מפיל את הבנייה ולא מייצר מניפסט חלקי.

```jsonc
{
  "schemaVersion": 1,            // צרכן חייב לדחות גרסה גבוהה יותר
  "releaseTag": "0.9.97+789",    // התג ב-GitHub
  "releaseVersion": "0.9.97",
  "components": [                // ממוין לפי installOrder ואז id
    {
      "id": "otzaria-windows-x64",          // מזהה יציב, לא שם קובץ
      "name": "אוצריא ל-Windows",            // עברית — מוצג למשתמש
      "nameEn": "Otzaria for Windows",      // אופציונלי — למסייע באנגלית
      "description": "התוכנה עצמה, ללא ספרייה.",
      "descriptionEn": "Otzaria itself, without the library.", // אופציונלי
      "type": "application",                // טקסט חופשי בכוונה
      "required": true,                     // חובה או רשות
      "origin": "built",                    // built | imported — תיעוד בלבד
      "platform": "windows",
      "architecture": "x64",
      "installOrder": 10,
      "dependsOn": [],                      // מזהי רכיבים אחרים במניפסט
      "downloadSize": 39475765,             // סך הבתים שיורדו בפועל
      "installedSize": 120000000,           // אופציונלי
      "assets": [
        {
          "kind": "single",
          "repository": "Otzaria/otzaria",  // תמיד owner/repo בארגון Otzaria
          "releaseTag": "0.9.97+789",
          "name": "otzaria-0.9.97-windows.exe",
          "size": 39475765,
          "sha256": "…64 תווי hex קטנים…"
        }
      ]
    },
    {
      "id": "library-full",
      "type": "library",
      "installedBy": ["otzaria-windows-x64", "otzaria-windows-arm64"], // מי שקורא אותו מהתיקייה
      "downloadSize": 3200000000,           // סכום החלקים
      "compatibility": {                    // מפה גנרית; מפתחות מה-provenance
        "libraryReleaseTag": "v27",
        "seforimDbZstSha256": "…",
        "searchEngineVersion": "0.8.4",
        "talmudVolumesDigest": "…"
      },
      "assets": [
        {
          "kind": "split",
          "repository": "Otzaria/otzaria",
          "releaseTag": "0.9.97+789",
          "name": "otzaria-0.9.97-library.tar.zst", // הקובץ השלם
          "size": 3200000000,               // גודל ו-hash של הקובץ השלם
          "sha256": "…",
          "manifestAsset": "otzaria-…tar.zst.manifest.json",
          "partSizeLimit": 1992294400,
          "githubAssetLimit": 2147483648,
          "parts": [                        // מסודרים; כל חלק הוא נכס ב-release
            { "name": "…part-000", "size": 1992294400, "sha256": "…" },
            { "name": "…part-001", "size": 1207705600, "sha256": "…" }
          ]
        }
      ]
    }
  ]
}
```

### כללים שהחוזה אוכף

* **כתובת נכס היא תמיד `repository` + `releaseTag` + `name`** — מאגר בארגון
  Otzaria בלבד (`^Otzaria/[A-Za-z0-9._-]+$`). אין URL חופשי בשום מקום, ולכן
  רכיב שמגיע מ-`Otzaria/SeforimLibrary` נושא את המאגר שלו במפורש ואינו מניח
  את מאגר ברירת המחדל. הצרכן בונה
  `https://github.com/<repository>/releases/download/<releaseTag>/<name>`.
* **נכס מפוצל הוא נכס אחד**, לא רשימת רכיבים. ה-hash והגודל של הקובץ השלם
  נמצאים על הנכס, והחלקים מתחתיו — אותה צורה של `split_release_asset.sh`.
* **שדות לא מוכרים נסבלים** בכל רמה. `type` הוא טקסט חופשי: צרכן שנתקל
  בסוג שאינו מוכר לו מציג אותו לפי `name`/`description` ואינו נופל.
* `origin` הוא תיעוד רישוי/ייחוס בלבד ואינו משפיע על נתיב ההורדה.
* `dependsOn` מצביע רק על מזהים שקיימים באותו מניפסט — נאכף באימות.
* **`installedBy`** (אופציונלי) — הרכיבים שמתקינים את הרכיב הזה: מתקין שקורא
  אותו מהתיקייה שלצדו. **רכיב מסוג `library` חייב לשאת אותו**, כל מזהה בו קיים
  במניפסט, ומתקין שמופיע בו אינו נושא `installedBy` בעצמו (אין שרשראות) — נאכף
  באימות. הגנרטור משמיט רכיב שאף מתקין שלו לא נבנה, או שאחת מתלויות ה-`dependsOn`
  שלו לא נבנתה (אינדקס בלי ספרייה), כמו רכיב שנכסיו חסרים. הכלל חל גם על
  `library-index` (`kInstalledByRequiredTypes`).
  המשמעות למסייעים בפרק "ההצעות" שבחוזה המשותף.
* **שדות הסינון** `platform`, `architecture` ו-`packageFormat` אופציונליים,
  ואם קיימים — מחרוזת לא ריקה (נאכף). המשמעות שלהם בפרק "חוזה משותף".
* **`outputFolder`** (אופציונלי) — תיקייה יחסית בתוך תיקיית הפלט של המסייע שבה
  נכתבים קובצי הרכיב, שמות `[A-Za-z0-9._-]` מופרדים ב-`/`, בלי מקטע ריק או של
  נקודות בלבד (נאכף בגנרטור ובשלושת המסייעים — הוא נתיב כתיבה). חסר = ישירות
  בתיקיית הפלט. **`outputNote`** (אופציונלי) — משפט בעברית שעמוד הסיום מוסיף
  כשהרכיב הוכן, פעם אחת גם כשכמה רכיבים נושאים אותו.
* **`partOf`** (אופציונלי) — מזהה הרכיב שהרכיב הזה הוא חלק ממנו, ושחייב להופיע
  ב-`dependsOn` שלו (נאכף באימות). בבחירה האישית אין לחלק שורה משלו: הוא מגיע
  עם השלם, וגודלו נוסף לשורה של השלם (`customChoices` במימוש הייחוס
  וב-`expected-selections.json`). מסייע ישן שאינו מכיר את השדה
  מציג את החלק כשורה נפרדת, וההורדה זהה.
* **טקסט באנגלית** — `nameEn`, `descriptionEn`, `outputNoteEn` (אופציונליים; אם
  קיימים — מחרוזת לא ריקה, נאכף) לצד השדות העבריים, שנשארים חובה כרגיל. מסייע
  שמוצג באנגלית לוקח אותם, ובהיעדרם (release ישן) — את השדה העברי
  (`componentText` במימוש הייחוס). כל רכיב ב-`kKnownComponents` נושא את שני
  הראשונים, ורכיבי החיפוש החכם את שלושתם (נבדק).

## איך מוסיפים רכיב חדש (בעתיד)

שורה אחת ב-`kKnownComponents` בתוך `tool/release/generate_release_manifest.dart`:

```dart
ComponentSpec(
  id: 'my-component',
  name: 'שם בעברית',
  description: 'תיאור בעברית.',
  nameEn: 'Name in English',
  descriptionEn: 'Description in English.',
  type: 'dependency',
  required: false,
  installOrder: 50,
  assets: [AssetSpec(pattern: r'^otzaria-.+-my-component\.zip$')],
),
```

אם הנכס יושב ב-release של מאגר אחר בארגון, מוסיפים `repository:` ל-`AssetSpec`
(כשהקובץ נארז לתוך `release-files/`), או מעבירים אותו כרכיב מוכן דרך
`--external` — קובץ JSON ובו רשימת רכיבים בצורה הסופית, שעוברים את אותו אימות.

**אין שינוי קוד בצד הצרכן.** האשף קורא את `components` כפי שהם.

רכיב שאינו מותקן בעצמו — ספרייה, אינדקס — נושא `installedBy` עם המתקינים
שקוראים אותו. בלעדיו המסייע היה מצרף אותו למתקין שמתעלם ממנו.

## איך מוסיפים נכס מפוצל (בעתיד)

1. ב-CI: `bash tool/release/split_release_asset.sh <archive> <out-dir>`.
2. להעלות ל-release את כל החלקים **וגם** את `<archive>.manifest.json`.
3. ב-`ComponentSpec` להגדיר `AssetSpec(pattern: r'…\.manifest\.json$', split: true)`.

הגנרטור קורא את מניפסט הפיצול, מאמת שכל חלק קיים בתיקייה ושגודלו תואם,
ומשקף אותו פנימה. `downloadSize` של הרכיב הוא סכום החלקים.

## נתוני החיפוש החכם (`semantic-model`, `semantic-vectors`)

מצב "חיפוש חכם" (`kSemanticSearchModeName`, `lib/semantic_search/`) צריך שני
רכיבים, ושניהם אינם נבנים ב-release הזה — הם נכסים של מאגרים אחרים בארגון,
ולכן `origin: 'imported'` וכתובת חיצונית מלאה (`repository` + `releaseTag` +
`name`, אותו חוזה של כל נכס — שלושת המסייעים כבר בונים ממנו את הכתובת):

| רכיב | `type` | מקור | `installOrder` | `compatibility` |
|---|---|---|---|---|
| `semantic-model-<פלטפורמה>` | `semantic-model` | `Otzaria/otzaria-semantic-search`, תג `model-meivin-round2-int8-v1`: הגרף, `tokenizer.json`, `model.json`, `LICENSE` — גודל ו-SHA-256 מ-`kSemanticModelReleases` | 40 | `modelFamilyId` |
| `semantic-vectors-<פלטפורמה>` | `semantic-vectors` | `Otzaria/SeforimLibrary`, תג `vectors-<תג הספרייה>`: קובצי ה-segment (או חלקיו) לפי המניפסט, וגם המניפסט עצמו | 41 | `libraryReleaseTag`, `libraryVersion`, `modelFamilyId`, `vectorsManifestSha256` |

* **זוג לכל פלטפורמה נתמכת** (`windows`, `linux`, `macos` — כמו
  `isSemanticSearchPlatformSupported`), כי `platform` מקבל ערך אחד; ל-Android
  אין רכיב. ב-macOS התיאור אומר שנדרשים Apple Silicon ו-macOS 14 — שדה
  הארכיטקטורה של macOS ריק (Universal) ואינו מבחין בזה.
* הווקטורים `dependsOn` המודל, והמודל `partOf` הווקטורים: בלי הנתונים המודל
  אינו שמיש, ולכן בבחירה האישית שניהם שורה אחת.
* **התג**: אותו `needs.bump_version.outputs.library_tag` שממנו נארזו כל חבילות
  ה-FULL — הווקטורים תואמים בדיוק לספרייה שבהתקנה המלאה.

### ב-CI — `tool/release/semantic_release_components.dart`

השלב "Resolve semantic search components" (לפני "Generate release manifest",
`continue-on-error: true`) כותב `$RUNNER_TEMP/semantic-components.json`, והגנרטור
מקבל אותו ב-`--external` רק כשהקובץ לא ריק. הכלי משתמש באותו
`SemanticVectorsReleaseLocator` של האפליקציה (digest המניפסט מול הערות ה-release
ומול ה-digest של הנכס), ובנוסף מוודא:

* כל קובץ שהמניפסט מונה קיים כנכס, בגודל ובאותו digest;
* `identity.model.family_id` ו-`tokenizer_checksum` של הווקטורים שווים ל-`model.json`
  שמצורף לאפליקציה;
* כל קובץ מודל נעוץ קיים ב-release המודל באותו גודל ו-digest.

**כשאין `vectors-<תג>`** (או כל כשל אחר — רשת, נכס שאינו תואם, מודל אחר) הכלי
מדפיס `::warning::Semantic search data omitted from the release manifest (library <tag>): <סיבה>`,
כותב `[]` ויוצא ב-0: שני הרכיבים מושמטים יחד (מודל בלי וקטורים אינו שמיש בלי
אינטרנט), והשחרור יוצא כרגיל. הטוקן של ה-workflow נשלח רק ל-`api.github.com`.

### במסייעים

* **"מלאה" ו"מלאה + אינדקס חיפוש" כוללות אותם** (`kOfflineDataTypes` במימוש
  הייחוס): הן ההצעות למחשב בלי אינטרנט, כמו הספרייה. "בסיסית" (ברירת המחדל)
  ו"עדכון בלבד" אינן — במחשב עם אינטרנט התוכנה מורידה אותם בעצמה אחרי ההסכמה.
  בבחירה האישית הם שורה אחת, "חיפוש חכם (ניסיוני)"
  (`kSemanticSearchModeLabel`), בגודל של שניהם.
* **"כמו המחשב הזה" (Inno)** — כמו בכל יעד: גם שם הפלט הוא תיקייה, ומתקין ה-FULL
  שמופעל ממנה ("התקן עכשיו") מעתיק אותם.
* **הפלט** (`outputFolder`):

  ```text
  <תיקיית הפלט>/semantic-import/meivin-round2-onnx/   seforim-embed-round2-int8.onnx, tokenizer.json, model.json, LICENSE
  <תיקיית הפלט>/semantic-import/vectors/              otzaria-vectors-…oxv.zst, otzaria-vectors-…manifest.json
  ```

  ב-Windows המתקינים מעתיקים אותה בעצמם: ב-`otzaria_full.iss` וב-`otzaria.iss`
  (הרגיל, x64 ו-ARM64) שורת `[Files]`
  `external recursesubdirs createallsubdirs skipifsourcedoesntexist` מ-
  `{src}\semantic-import\*` אל `GetSemanticImportDir` — ההורה של תיקיית הספרייה
  (`GetSelectedBooksPath('')` ב-FULL, `GetLibraryBooksPath` ברגיל), שהוא
  `SemanticPaths.root` באפליקציה (גם במצב נייד). בלי התיקייה לצד המתקין השורה
  אינה עושה דבר. `outputNote` של רכיבי Windows אומר זאת, ומוסיף שבהתקנה מה-ZIP
  הנייד מעתיקים ידנית; ב-Linux וב-macOS ההעתקה ידנית תמיד, אל התיקייה שמכילה את
  תיקיית הספרייה.

### באפליקציה — `lib/semantic_search/repository/semantic_staged_import.dart`

התיקייה מזוהה ב-`<root>/semantic-import` (`SemanticPaths.root`, ההורה של תיקיית
הספרייה; הקבועים ב-`semantic_import_layout.dart`, שגם כלי ה-CI קורא). **שום דבר
אינו רץ בעלייה ושום דבר אינו מותקן בלי הסכמה**: הנתונים משמשים רק בתוך עבודת
ההורדה של `SemanticSearchRepository` (`enableAndDownload` או העדכון שאחרי עדכון
ספרייה), שבודקת הסכמה לפני כל דבר.

* כל הורדה של קובץ מודל או וקטורים עוברת דרך `SemanticStagedImport.wrap`: קובץ
  באותו שם בתיקייה המוכנה, באותו גודל ו-SHA-256 (המודל — הנעוץ; הוקטורים — מהמניפסט)
  מועבר (`rename`, ובין כוננים העתקה) ליעד ההורדה במקום הורדה. קובץ שאינו תואם נשאר
  במקומו והקובץ יורד מהרשת.
* `SemanticStagedImport.locate`: ה-release נמצא ברשת כרגיל; כשהרשת אינה זמינה
  (`IOException`, `ClientException`, timeout, מגבלת קצב) או במצב לא מקוון — ממניפסט
  הוקטורים המוכן, ורק אם הוא של גרסת הספרייה המותקנת. ה-digest שנמסר למנוע הוא ה-SHA-256
  של בתי המניפסט: המסייע אימת אותם מול מניפסט ה-release, וה-CI אימת אותו מול ה-digest שפורסם.
* במצב לא מקוון העבודה רצה רק כשיש נתונים מוכנים, וקובץ חסר נכשל ב-`offline`
  ואינו פונה לרשת.
* **התקדמות**: קובץ מוכן נספר בסך הבתים של העבודה כמו קובץ שירד. בזמן בדיקת
  ה-hash שלו ההתקדמות מסומנת `checking` (באותו שלב), ולכן התווית היא "שלב N מתוך M —
  בודק את הקבצים שהוכנו מראש" (`SemanticSearchMessages.checkingStagedFiles`) והפס
  בכרטיס, בהגדרות ובחיווי העבודה הוא בלי ערך.
* **מקום פנוי**: `_ensureDiskSpace` אינו סופר קובץ וקטורים מוכן שנמצא באותו כונן
  (לפי `volumeId`) — הוא עובר ב-`rename`. קובץ בכונן אחר מועתק ולכן נספר.

הנקודות ב-`semantic_search_repository.dart`: השדות `_staged` ו-`_fetch`, שתי
קריאות ההורדה (`_fetch` במקום `_download`), בדיקת מצב לא מקוון ב-`_performJob`,
ואיתור ה-release ב-`_staged.locate`. בדיקות:
`test/semantic_search/semantic_staged_import_test.dart`,
`test/release/semantic_release_components_test.dart`.

סוג חדש אחר אינו דורש שינוי בצרכן — הבדיקה `a future component type round-trips
with no consumer change` שומרת על כך; הוא נכנס להצעות המלאות רק כשהוא ב-`kOfflineDataTypes`.

## חוזה משותף לכל המסייעים (Windows, macOS, Linux)

שלושה מימושים, חוזה אחד: `installer/download_assistant.iss` (Inno),
`tool/download_assistant/macos/` (SwiftUI) ו-`tool/download_assistant/linux/`
(C + GTK3). כל אחד מהם יכול להכין התקנה **לכל** פלטפורמה — משתמש עם מחשב
Windows מחובר מכין דיסק-און-קי ל-Linux מנותק, וכן הלאה.

**מימוש הייחוס** של כללי הבחירה הוא `tool/release/download_assistant_selection.dart`.
ממנו נגזרים קובצי הייחוס `tool/download_assistant/fixtures/release-manifest.json`
ו-`expected-selections.json`, וזוג הווריאנט `release-manifest-large-full.json` /
`expected-selections-large-full.json` — אותו release כששני מתקיני ה-FULL מפוצלים
בגודל 4 GiB בדיוק (בפקודה
`dart run tool/download_assistant/fixtures/generate_fixtures.dart`), ו-
`test/release/download_assistant_selection_test.dart` נכשל כשהם מתיישנים. מסייעי
macOS ו-Linux מריצים בבדיקות שלהם את שני המניפסטים ומשווים לקובצי ה-`expected-selections`
— אותם רכיבים מוצעים, אותן הצעות, אותם קובצי פלט ואותה תת-תיקייה. במסייע Inno
אין הרצת בדיקות, והוא מאומת מולם ידנית.

### נכסי המסייעים

| מסייע | שם הנכס | ארטיפקט ב-CI |
|---|---|---|
| Windows (x64 ו-ARM64 באמולציה) | `Otzaria-Download-Assistant-windows.exe` | `otzaria-download-assistant` |
| macOS (Universal) | `Otzaria-Download-Assistant-macos.zip` | `otzaria-download-assistant-macos` |
| Linux x64 | `Otzaria-Download-Assistant-linux-x64.tar.gz` | `otzaria-download-assistant-linux-x64` |
| Linux ARM64 | `Otzaria-Download-Assistant-linux-arm64.tar.gz` | `otzaria-download-assistant-linux-arm64` |

* **אינם רכיבים במניפסט**: אין להם `ComponentSpec`, וה-`O` הגדול דוחה כל תבנית
  `^otzaria-`. נבדק ב-`the assistants of every platform are tools, never components`.
* **המעדכן שבתוך אוצריא לעולם אינו בוחר בהם**: `isDownloadAssistantAsset` מוחרג
  ב-`pickWindowsAssetUrl`, ב-`pickMacAssetUrl` (שם המסייע מכיל `macos` ומסתיים
  ב-zip — בלי ההחרגה הוא היה נבחר לפני `otzaria-macos.zip`) וב-`pickLinuxAssetUrl`.
* **אינם חוסמים שחרור**: כל שלב בנייה שלהם נושא `continue-on-error: true`, וכל
  שלב העלאה מותנה בהצלחתו.

### שדות הסינון במניפסט

| שדה | ערכים | חסר / `any` |
|---|---|---|
| `platform` | `windows` / `macos` / `linux` / `android` | מתאים לכל יעד |
| `architecture` | `x64` / `arm64` | מתאים לכל ארכיטקטורה (Universal Binary של macOS, APK של כל ה-ABI) |
| `packageFormat` | `deb` / `rpm` | מתאים לכל פורמט שנבחר |

רכיב מתאים ליעד כששלושת השדות מתאימים. ערך שאינו מוכר (פלטפורמה עתידית) אינו
שגיאה — הוא פשוט אינו מתאים לאף יעד מוכר. `packageFormat` קיים רק על חבילת מנהל
חבילות; ארכיון נייד וחבילה מלאה אינם נושאים אותו ולכן מתאימים לכל בחירה.

הרכיבים לכל פלטפורמה (נגזרים מהנכסים של 0.9.97):

| פלטפורמה | `application` | `application-portable` | `application-bundle` |
|---|---|---|---|
| Windows | מתקין x64 / ARM64 | ZIP x64 / ARM64 | מתקין FULL x64 / ARM64 |
| Linux | DEB x64/ARM64, RPM x64/ARM64 | ZIP raw (רק כשה-DEB נכשל) | `otzaria-linux-full[-arm64].tar.zst` |
| macOS | `otzaria-macos.dmg` | — | `otzaria-macos-full.tar.zst` |
| Android | ה-APK | — | — (כרכי `otzaria-android-full*.zip` אינם רכיב — ראו למטה) |

**הספרייה והאינדקס** — שני רכיבים, `any` בשדות הסינון:

| רכיב | `type` | נכס | `dependsOn` | `installedBy` |
|---|---|---|---|---|
| `library-full` ("ספרייה מלאה") | `library` | `otzaria-<ver>-library.tar.zst` בחלקים — `books/` | — | `otzaria-windows-x64`, `otzaria-windows-arm64`, `otzaria-android` |
| `library-index` ("אינדקס חיפוש מוכן (למחשבים חלשים)") | `library-index` | `otzaria-<ver>-library-index.tar.zst` בחלקים — `index/` עם `.otzaria_prebuilt_index` | `library-full` | אותם מתקינים |

בדרך כלל מורידים את הספרייה בלבד, והתוכנה בונה את האינדקס בעצמה אחרי ההתקנה;
האינדקס מיועד למחשב חלש, ושמו ותיאורו אומרים זאת. הוא נושא סוג משלו כדי ש"מלאה"
(שאוספת `library`) לא תכלול אותו. המתקינים הרגילים של Windows פורסים את החלקים
שלצדם (`PrepareLibraryParts` ב-`otzaria.iss`, הפרק "המתקין הרגיל וחלקי הספרייה"
למטה), וב-Android "ייבוא מתיקיית קובצי הספרייה" באוצריא קורא אותם
(`lib/empty_library/services/library_package`), ולכן שניהם מוצעים ל-Windows
ול-Android. מתקין ה-FULL אינו נוגע בהם; ב-Linux וב-macOS אין מי שיתקין אותם. אין
מתקין מאונדקס נפרד (issue #1890).
`otzaria-macos.zip` אינו רכיב — הוא ערוץ העדכון הפנימי. גם כרכי ה-ZIP של Android
FULL אינם רכיב: הם להורדה ידנית מעמוד השחרור, והמסייע מוריד את ה-APK ואת חלקי
הספרייה עצמם. לכל חבילה מלאה יש גם תבנית `split`, כמו ל-Windows FULL, כדי שלא
תיעלם מהמניפסט ביום שתחצה את הסף.

### בחירת היעד

סדר העמודים: פלטפורמה ← ארכיטקטורה ← פורמט חבילה ← הצעות ← בחירה אישית ←
תיקייה ← הורדה ← סיום. **עמוד שיש בו אפשרות אחת בלבד אינו מוצג** (ארכיטקטורה
ל-macOS ול-Android; פורמט לכל מה שאינו Linux).

| עמוד | אפשרויות | ברירת מחדל |
|---|---|---|
| פלטפורמה | `platformChoices` — רק פלטפורמות שיש להן רכיב ייעודי | **הפלטפורמה שהמסייע רץ עליה** |
| ארכיטקטורה | `architectureChoices` — x64 תמיד ראשונה | היעד = המחשב הזה: המעבד שלו (Windows: `IsArm64`; Linux: `uname -m`, `aarch64`→`arm64`, `x86_64`→`x64`). אחרת `x64` |
| פורמט (Linux) | `packageFormatChoices` — `deb`, `rpm`, ו-`portable` כשיש רכיב תוכנה בלי פורמט | `defaultPackageFormat`: ב-Linux לפי `/etc/os-release` — `ID` ואז `ID_LIKE` (משפחת debian/ubuntu → `deb`, fedora/rhel/suse → `rpm`, לא מוכרת → `portable`). מחוץ ל-Linux → `deb` |

**למה os-release:** הוא הקובץ היחיד שקיים בכל הפצה מודרנית (systemd וגם בלעדיו),
ו-`ID_LIKE` מכסה נגזרות (Mint → `ubuntu debian`) בלי רשימה אינסופית. בדיקת
`dpkg`/`rpm` ב-PATH שגויה: Fedora מתקינה `dpkg` לפעמים, ו-Ubuntu `rpm`.
`deb` כברירת מחדל מחוץ ל-Linux — משפחת Ubuntu/Mint/Debian היא רוב המשתמשים.

שמות לתצוגה: הפלטפורמות באותיות לטיניות (Windows, macOS, Linux, Android — כמו
בשמות הרכיבים); הארכיטקטורות כמו היום ("מחשב רגיל" / "מחשב עם מעבד מסוג ARM");
הפורמטים "Ubuntu, Debian, Mint והפצות דומות (DEB)", "Fedora, openSUSE והפצות
דומות (RPM)", "הפצה אחרת — ללא התקנה".

**ב-Windows אין שלושה עמודים.** המסך הראשון הוא "Windows — כמו המחשב הזה" (Windows +
המעבד של המחשב, `IsArm64`; התיאור אומר שהוא מתאים לכל מחשב מאותו סוג) מול "סוג
מחשב אחר". "אחר" פותח **רשימה אחת**
של כל יעד שהמניפסט מציע מלבד המחשב הזה: הצירופים של `platformChoices` ×
`architectureChoices` × `packageFormatChoices`, רק כאלה שמוצע בהם רכיב, בסדר שבו
`DevSelectionDump` עובר עליהם (שורה אחת ל-macOS, Universal). אין בה בחירה מראש —
אין יעד "אחר" שמתאים לרוב המשתמשים — ו"המשך" בלי בחירה מבקש לבחור. בשני
המצבים הקבצים יורדים לתיקייה שנבחרה; במחשב הזה עמוד הסיום מציע "התקן עכשיו
במחשב הזה" ו"פתח את תיקיית ההתקנה". מחשב אחר מאותו סוג בוחר "כמו המחשב הזה" ומעתיק את
התיקייה. מסייע macOS עובד באותה צורה ("macOS — כמו המחשב הזה" / "סוג מחשב אחר"); "התקן
עכשיו" מוצע בו רק כשנוצר DMG יחיד, והוא פותח אותו. מסייע Linux מכין תיקייה בלבד, באותם
שני מסלולים: "Linux — כמו המחשב הזה" הוא `linux` עם המעבד (`uname`) ופורמט החבילה
(`defaultPackageFormat` מ-os-release) של המחשב, ו"סוג מחשב אחר" — אותה רשימה אחת בלי
הצירוף הזה; כשהמניפסט אינו מציע דבר למחשב הזה מוצג רק "סוג מחשב אחר".

### ההצעות

**אותה גזירה בדיוק** של הטבלה ב"ההצעות נגזרות מהמניפסט" למטה, על הרכיבים
**המוצעים** ליעד (`componentIsOffered`). המזהים, **בסדר ההצגה**
(`kPresetDisplayOrder`):

| מזהה | הצעה | הרכיבים |
|---|---|---|
| `basic` | התקנה בסיסית (מומלצת) — **מסומנת מראש** | כל `application` + כל רכיב `required` |
| `full-indexed` | התקנה מלאה + אינדקס חיפוש | החבילה המאונדקסת עם מה שהיא מתקינה (`library-full-indexed`) + נתוני החיפוש החכם |
| `full` | התקנה מלאה | החבילה הגדולה ביותר עם מה שהיא מתקינה + נתוני החיפוש החכם (ראו למטה) |
| `update` | עדכון התוכנה בלבד | כל `application` |

"בחירה אישית" אינה נגזרת ותמיד אחרונה. רכיב **מוצע** ליעד כש:

1. מתאים ליעד בשלושת שדות הסינון;
2. אין בו exe בגודל 4 GiB ומעלה — Windows אינו מריץ אותו, ולכן רכיב כזה אינו
   מוצע גם בבחירה האישית;
3. אם יש לו `installedBy` — אחד ממתקיניו עומד בשני התנאים הקודמים.

`buildPresets` היא ההגדרה המדויקת: "מלאה" היא החבילה הגדולה ביותר (לפי הגודל
שלה עצמה) **יחד עם כל רכיב מוצע שהיא ב-`installedBy` שלו**, ועם כל רכיב מוצע
מ-`kOfflineDataTypes` (`semantic-model`, `semantic-vectors`); בלי חבילה — התוכנה
עם הספרייה ונתוני החיפוש החכם, ו**בלי ספרייה אין "מלאה"** (אחרת "התקנה מלאה"
הייתה התוכנה לבדה). **החבילה המאונדקסת** היא `application-bundle` מוצע שספרייה
מוצעת מונה אותו ב-`installedBy` שלה (במניפסטים ישנים: `otzaria-windows-full-indexed` עם
`library-full-indexed`, ב-Windows x64 בלבד); כשיש כמה — הגדולה בסך הכול, עם מה
שהיא מתקינה. "מלאה + אינדקס חיפוש" היא החבילה הזו, מה שהיא מתקינה ונתוני החיפוש
החכם; בלי חבילה כזו אין הצעה כזו (macOS, Linux ו-ARM64). ב-Android, שאין לו
חבילה, "מלאה + אינדקס חיפוש" היא התוכנה עם הספרייה והאינדקס — בטלפון בניית
האינדקס איטית מאוד. הסגירה
(`withDependencies`) מוסיפה כל `dependsOn` מוצע, ולכל רכיב שאף מתקין שלו אינו
בבחירה — את הראשון המוצע ב-`installedBy` (`installerFor`). אותה סגירה חלה על
הבחירה האישית, כך שספרייה שסומנה לבדה מגיעה עם המתקין שקורא אותה.

**כפולות.** הצעה ריקה אינה מוצגת, וגם הצעה שאחרי הסגירה זהה להצעה שהוערכה
לפניה. סדר ההערכה שונה מסדר ההצגה — `full-indexed`, `full`, `basic`, `update` —
כדי שהשם המפורט יותר יישאר. לכן כשמתקין ה-FULL הרגיל אינו רץ ו"מלאה" עוברת
לחבילה המאונדקסת, ההצעה מוצגת כ"מלאה + אינדקס חיפוש"; ובמניפסט הנוכחי `update`
זהה ל-`basic`.

**"בסיסית" מסומנת מראש** (`kDefaultPresetId`) בשלושת המסייעים, לפי המזהה ולא לפי
המקום: במחשב עם אינטרנט הספרייה יורדת מתוך התוכנה, ו"מלאה" מיועדת למחשב בלי
אינטרנט. כשאין "בסיסית" (Linux נייד) מסומנת "מלאה" — לא "מלאה + אינדקס חיפוש"
הגדולה ממנה; בלי שתיהן — הראשונה (`defaultPresetIdFor`; ב-Swift אותו שם, ב-C
`otz_default_preset_index`). ב-Android: "מלאה + אינדקס חיפוש" = ה-APK, הספרייה
והאינדקס (אותה קבוצה כמו חבילת ה-FULL), "מלאה" = ה-APK והספרייה, "בסיסית" = ה-APK;
בלי נתוני חיפוש חכם — אין כאלה ל-Android. הנכסים המפוצלים מורכבים לקובץ אחד
(`shouldAssembleSplitAsset`), והייבוא באוצריא מקבל גם ארכיון שלם. ב-Linux עם `portable`:
רק "מלאה" (החבילה הניידת עם הספרייה), כי אין רכיב תוכנה נייד בלי ספרייה.

**החוזה נבדק על כל יעד** (`כל הצעה ניתנת להתקנה` ב-
`test/release/download_assistant_selection_test.dart`, על שני זוגות הייחוס): כל
חבר בהצעה מוצע ביעד, כל ספרייה נושאת `installedBy`, כל רכיב עם `installedBy`
נמצא באותה הצעה עם אחד ממתקיניו, "מלאה" ו"מלאה + אינדקס חיפוש" מכילות חבילה או
ספרייה (השנייה — ספרייה), ונתוני החיפוש החכם אינם ב"בסיסית" ולא ב"עדכון".

**Windows ARM64.** "מלאה" היא `otzaria-windows-full-arm64`
(`otzaria-<ver>-windows_arm64-full.exe`, מתקין ARM64 נייטיבי עם הספרייה). כל עוד
הנכס אינו ב-release, "מלאה" היא המתקין הרגיל של ARM64 עם הספרייה — מתקין ה-ARM64
הרגיל פורס את החלקים בדיוק כמו של x64. המסייע אינו נופל למתקין x64:
`otzaria_full.iss` הוא `x64compatible` ורץ באמולציה, אבל תוספים (WebView2 במסלול
composition) אינם עובדים באוצריא x64 על ARM, ומשתמש ARM מקבל ממילא את המתקין
הנייטיבי.

**מתקין FULL של 4 GiB ומעלה.** הוא נשאר חלקים (`shouldAssembleSplitAsset`) ואינו
רץ, ולכן אינו מוצע. בלי חבילה מוצעת, "מלאה" היא ענף "התוכנה עם הספרייה" של
`buildPresets`: המתקין הרגיל של אותה ארכיטקטורה יחד עם `library-full` ונתוני
החיפוש החכם — **בלי האינדקס**, שאינו מסוג `library`. התוצאה היא תיקייה ובה המתקין
הרגיל וחלקי הספרייה, שהוא מאמת ופורס בלי אינטרנט. אין כאן קוד ייעודי — זו אותה
גזירה של כל יעד בלי חבילה.

**"מלאה" כשמתקין ה-FULL רץ** נשארת `otzaria-windows-full` בלי אינדקס:
`library-full` ו-`library-index` אינם ב-`installedBy` שלה, ולכן אינם מצטרפים
אליה.

### הבחירה האישית

רק הדרך להתקין את התוכנה ורכיבי הרשות — לא מתקינים נוספים. ההגדרה המדויקת היא
`customChoices` במימוש הייחוס, ו-`expected-selections*.json` נושאים אותה לכל יעד
(`{id, downloadSize, locked, group}`), כך ששלושת המסייעים נבדקים מולה:

1. **רכיבים מוצעים בלבד**, בסדר המניפסט, **בלי `application-portable`** בשום
   פלטפורמה — הגרסה הניידת היא צורה חלופית של אותה תוכנה. (`portable` כפורמט
   חבילה ב-Linux לא השתנה: זו ההפצה הלא-מוכרת, שמקבלת את חבילת ה-FULL.)
2. **כשהמתקין הרגיל פורס ספרייה שלצדו** (יש רכיב מוצע ש-`installerFor` שלו מסוג
   `application`) — החבילה המלאה אינה מוצגת, והמתקין **נעול** (`locked`: מסומן,
   "(נדרש)", אי אפשר לבטל). ב-Windows x64 וב-ARM64: המתקין הרגיל, "ספרייה מלאה",
   "אינדקס חיפוש מוכן (למחשבים חלשים)" והחיפוש החכם.
3. **אחרת**, כשיש יותר מדרך אחת להתקין את התוכנה (`application` ו-
   `application-bundle`) — הן קבוצת רדיו (`group: "application"`), כדי שלא יורדו
   שתיהן: Linux DEB/RPM ו-macOS — "מתקין" או "מתקין עם הספרייה". דרך אחת
   בלבד (Linux בלי מנהל חבילות: חבילת ה-FULL) — נעולה.
4. שאר הרכיבים (החיפוש החכם) — תיבות סימון.

ברירת המחדל ברדיו היא מה שסומן בהצעה שקדמה, ובלעדיה המתקין (`application`).
סימון שורה מסמן את ה-`dependsOn` שלה, וביטול שורה מבטל את מי שתלוי בה — אינדקס
מסמן את הספרייה, וביטול הספרייה מבטל את האינדקס. הסגירה (`withDependencies`)
חלה בכל מקרה גם על הבחירה האישית.

**האיחוד עם `partOf` (PR #1889).** שם הפונקציה והשדה זהים (`customChoices`), ו-
#1889 מוסיף להם שני דברים: רכיב עם `partOf` אינו שורה, וגודלו נוסף ל-
`downloadSize` של השלם. באיחוד המסנן של שורה הוא שלושת התנאים יחד (מוצע, לא נייד
ולא חבילה מיותרת, ובלי `partOf`), והשדות `locked`/`group` נשארים. ב-Inno —
`IsCustomChoice` מקבל את תנאי ה-`partOf` ו-`CustomChoiceSize` מחליף את
`CompDownloadSize[I]`; שורת ה-`custom` ב-`DevSelectionDump` היא
`id:size:locked:group`.

### הפלט

* **תיקיית הבסיס** — התיקייה שבה נמצא המסייע: Windows — תיקיית ה-exe; macOS —
  התיקייה **שמכילה** את ה-`.app` (לא תוכו); Linux — תיקיית `/proc/self/exe`.
  הכתיבוּת נבדקת בכתיבה ממשית של `otzaria_write_test.tmp`. כשלא ניתן —
  `<מסמכים>/אוצריא-להתקנה` (Windows `{userdocs}`; macOS `~/Documents`; Linux
  `g_get_user_special_dir(G_USER_DIRECTORY_DOCUMENTS)`, ובהיעדרה `$HOME`), עם משפט
  שמסביר למה. macOS מריץ אפליקציה שהורדה מהרשת מנתיב אקראי לקריאה בלבד (App
  Translocation), ולכן שם זה המקרה הרגיל. התיקייה גלויה וניתנת לשינוי לפני
  תחילת ההורדה.
* **קובץ אחד** — ישירות בתיקיית הבסיס. **יותר מקובץ אחד** — בתת-תיקייה
  `אוצריא להתקנה ל-<פלטפורמה>` (`outputSubfolderName`). הפלטפורמה בשם כדי שהכנה
  לשני יעדים באותו דיסק-און-קי לא תערבב קבצים. **חריג של Windows, macOS ו-Linux:** כשהממשק
  באנגלית התיקייה היא `Otzaria setup for <Platform>` (וגם תיקיית הנסיגה —
  `Otzaria setup`); `DevSelectionDump` מדפיס תמיד את שם החוזה. קובץ של רכיב עם `outputFolder`
  נכתב בתוכה בתיקייה הזאת, ו-`plannedOutputFiles` מחזיר אותו כ-`<folder>/<name>`.
* **נכס מפוצל** (`shouldAssembleSplitAsset`): יעד Windows — מורכב רק exe מתחת
  ל-4 GiB, וארכיון נשאר חלקים (המתקין קורא אותם). כל יעד אחר — כל נכס מתחת
  ל-4 GiB מורכב, כי המשתמש פורס אותו בעצמו; מ-4 GiB ומעלה (FAT32 אינו מחזיק קובץ
  כזה) החלקים נשארים, ועמוד הסיום מציג את פקודת החיבור (`cat …part-* > <שם>`).
* **סיום** — הניסוח נגזר ממספר הקבצים שנוצרו בפועל, כמו ב-Windows. בתיקייה
  של כמה קבצים הוא נוקב בשם ה-exe שמפעילים (המתקין הרגיל לצד חלקי הספרייה
  והאינדקס), ובהיעדרו — "קובץ ההתקנה". תיבת "הצג את
  הקובץ/התיקייה שהוכנו" **מסומנת מראש**: Windows `explorer /select`; macOS
  `NSWorkspace.activateFileViewerSelecting`; Linux
  `org.freedesktop.FileManager1.ShowItems` ב-D-Bus (GDBus, חלק מ-GIO), ובכישלון
  פתיחת התיקייה ב-`g_app_info_launch_default_for_uri`. כישלון שקט.

### מקור ההורדה והתג

* **התג המוטבע**: כל מסייע נבנה עם התג שממנו נבנה (אותו כלל של `create_release`:
  ענף `main` → `<version>`, אחרת `<version>+<run_number>`). ב-runtime: אם
  `/releases/latest` מחזיר גרסת `X.Y.Z` **גבוהה יותר** — הוא נבחר; אחרת התג
  המוטבע. בלי תג מוטבע (בנייה מקומית) — latest. התג ננעל לכל הריצה.
* **הטמעה בזמן בנייה — תמיד דרך משתנה סביבה**, `OTZARIA_ASSISTANT_RELEASE_TAG`,
  לעולם לא כארגומנט עם מרכאות בשורת הפקודה (ה-`/D` של ISCC הגיע עטוף
  בלוכסנים). סקריפט הבנייה בודק את הערך מול `^[0-9A-Za-z.+_-]*$`, נכשל על כל
  תו אחר, וכותב קובץ מקור שנוצר: Swift — `let embeddedReleaseTag = "0.10.3+143"`;
  C — `#define OTZ_EMBEDDED_RELEASE_TAG "0.10.3+143"`. הבדיקה מבטיחה שאין בערך
  מרכאות או לוכסן, ולכן ה-`+` עובר כפי שהוא.
* **כתובות**: מניפסט — רק מ-`Otzaria/otzaria`; נכס —
  `https://github.com/<repository>/releases/download/<tag>/<name>`, כש-
  `repository` תואם `^Otzaria/[A-Za-z0-9._-]+$`, והתג והשם תואמים
  `^[A-Za-z0-9._+-]+$` (ה-`+` נשאר כפי שהוא — תו חוקי בנתיב). API —
  `https://api.github.com/repos/Otzaria/otzaria/releases/...` עם `User-Agent`.
* **הפניות**: רק `https`, ורק למארחים `github.com`, `api.github.com`,
  `objects.githubusercontent.com`, `release-assets.githubusercontent.com`. ב-
  `github.com` הנתיב חייב להתחיל ב-`/Otzaria/`. כל הפניה אחרת — עצירה בשגיאה.
  macOS ו-Linux אוכפים זאת בכל קפיצה; Inno עוקב אחר הפניות בעצמו ואינו חושף
  אותן, ולכן אצלו האכיפה היא על הכתובת ההתחלתית ועל ה-TLS.
* **אימות**: כל קובץ מאומת בגודל ו-sha256 מהמניפסט. אין הורדה של רכיב בלי hash.

### מטמון

| מסייע | מיקום |
|---|---|
| Windows | `{localappdata}\Otzaria\DownloadAssistant\cache` |
| macOS | `~/Library/Caches/Otzaria/DownloadAssistant` |
| Linux | `${XDG_CACHE_HOME:-~/.cache}/otzaria/download-assistant` |

* קובץ בתהליך הורדה: `<name>.download`. אחרי אימות הוא מקבל את שמו הסופי `<name>`,
  ולצדו נכתב **חותם** `<name>.sha256` בפורמט של `sha256sum`
  (`<hex>  <name>\n`).
* **שימוש חוזר בלי hash נוסף**: הקובץ נחשב מוכן כשהחותם קיים, ה-hex שבו שווה
  ל-sha256 שבמניפסט, גודל הקובץ שווה לגודל שבמניפסט, וזמן השינוי של הקובץ אינו
  מאוחר מזה של החותם. קובץ בלי חותם (מטמון של גרסה קודמת) נבדק ב-hash **פעם
  אחת**, ואז נכתב לו חותם.
* חלקים שהורכבו נמחקים מהמטמון מיד אחרי שנוספו (שיא הדיסק = הקובץ המורכב + חלק
  אחד). קובץ בודד נשאר במטמון — הכנה נוספת שלו מיידית.

### מהירות — אחרי שהבתים הגיעו

נמדד: מהירות חיבור בודד זהה ב-Inno, ב-Dart וב-curl (~‎7-8MB/s‎ כאן, מוגבל-קו).
הבזבוז הוא אחרי ההורדה: `GetSHA256OfFile` עולה ~‎17‎ שניות ל-2GB, והאשף הישן
חישב אותו פעמיים לכל קובץ, העתיק מטמון→יעד, וחישב hash שלישי לקובץ המורכב.

1. **הורדה נבדקת בזרימה.** macOS ו-Linux מחשבים hash תוך כדי כתיבה; ב-Inno
   עמוד ההורדה בודק את ה-sha256. `PromoteToCache` אינו מחשב אותו שוב.
2. **קובץ מורכב נבדק גם כשלם.** גודל חלקי וקובץ זמני בשם תלוי-hash אינם
   מוכיחים שתוכן קודם שנשמר בדיסק לא נפגם. לפני פרסום הקובץ קוראים אותו
   בזרימה ומאמתים SHA-256 מול המניפסט. הקריאה הנוספת נעשית רק לנכס מפוצל.
3. **מטמון→יעד בקישור קשיח**, ובכישלון (כונן אחר, FAT32/exFAT) — העתקה. Windows
   `CreateHardLinkW`; macOS `link(2)` (ואז `FileManager.copyItem`, שמשכפל ב-APFS);
   Linux `link(2)` ואז העתקה בזרימה. קובץ שהורכב נכתב ישר ליעד ואינו מועתק.
4. **ממשק**: בזמן הורדה — סך הבתים, **מהירות** (ממוצע נע על ~5 שניות) ו**זמן
   משוער לסיום**. לכל שלב אחר (בדיקת מטמון בלי חותם, הרכבה, העתקה) — פס משלו עם
   כותרת בעברית ("מחבר את הקבצים", "מעתיק לתיקייה שנבחרה") והתקדמות בבתים. אף פס
   אינו נשאר קפוא על 100% בזמן שעבודה נמשכת; כשאין דרך למדוד (hash פנימי של Inno)
   הכותרת מתחלפת ל"בודק את הקובץ שירד" לפני שהוא מתחיל.

### מקביליות

נמדד ברשת המסוננת כאן: בקשה עם `Range: bytes=0-999` ל-CDN של GitHub מחזירה **200
עם כל 91MB**, אף שהשרת מכריז `Accept-Ranges: bytes`. מוריד מפוצל תמים היה מוריד
את הקובץ N פעמים. הורדה של **קבצים שונים** במקביל עובדת: קובץ אחד ‎7.8MB/s‎ מול
שלושה יחד ‎9.4MB/s‎ (הקו כמעט רווי; בקו מהיר ולא מסונן הרווח גדול בהרבה).

**macOS ו-Linux:**

* עד **3 חיבורים** בו-זמנית בסך הכול, כל אחד לקובץ אחר. חלקים של נכס מפוצל הם
  קבצים נפרדים — מקביליות בלי Range.
* **חידוש קובץ חלקי**: בקשה עם `Range: bytes=<קיים>-`. רק תשובת **206** שה-
  `Content-Range` שלה `bytes <קיים>-<size-1>/<size>` בדיוק ממשיכה את הקובץ (ה-hash
  של החלק הקיים מחושב מהדיסק פעם אחת לפני ההמשך). **200** — הקובץ החלקי מקוצץ
  לאפס והגוף של אותה תשובה נכתב מההתחלה: אין בקשה שנייה ואין בית שירד פעמיים.
  כל תשובה אחרת — הקובץ החלקי נמחק ומנסים מחדש.
* **פיצול קובץ אחד לקטעים** — רשות, שלב ב'. מותר רק אחרי שתשובה על אותו מארח
  בריצה הזאת הייתה 206 עם `Content-Range` תואם; קטע שמקבל **200** נסגר מיד (אחרי
  הכותרות, לפני הגוף), והפיצול מבוטל לשארית הריצה. ה-hash עוקב אחרי "חזית רציפה":
  הקטע הראשון נבדק בזרימה, והמשכו נקרא מהדיסק כשהחזית מגיעה אליו — עדיין hash
  אחד לכל בית. תקרת 3 החיבורים משותפת לקבצים ולקטעים.
* ניסיון חוזר: עד 3 פעמים לקובץ, עם המתנה 2/5/10 שניות, רק על שגיאת רשת או 5xx.

**Windows (Inno) — סדרתי, בכוונה.** עמוד ההורדה של Inno מוריד קובץ אחד בכל פעם
ואינו חושף API מקבילי. החלופה היחידה — הפעלת `curl.exe` כתהליכים ומעקב אחר
קבציהם — מוסיפה ניהול תהליכים, ביטול וניתוח פלט לקוד Pascal, תמורת ~20% כאן.
הרווח של Windows בא מביטול ה-hash הכפול וההעתקה (הסעיף הקודם).

### שפה ושגיאות

כמו ב-Windows (הפרק "שפה" למטה): אין "מניפסט", "נכס", "hash" בעמודים הרגילים;
שגיאה מנוסחת בעברית עם "פרטים טכניים"; בהיעדר מניפסט — ההצעה היחידה היא לפתוח את
עמוד ההורדות בדפדפן. כל המסייעים — Windows, macOS ו-Linux — דו-לשוניים (עברית כששפת
המערכת עברית, אחרת אנגלית).

## האשף — `installer/download_assistant.iss`

```powershell
.\tool\release\fetch_assistant_art.ps1    # העיצוב הנעוץ -> installer\assistant_art (מדלג כשכבר שם)
ISCC installer\download_assistant.iss     # -> installer\Otzaria-Download-Assistant-windows.exe
```

סקריפט Inno שלישי, נפרד לגמרי משני המתקינים. הוא **אינו מתקין**:
`CreateAppDir=no`, `Uninstallable=no`, `CreateUninstallRegKey=no`, ואין בו
מקטעי `[Icons]`, `[Registry]`, `[Dirs]` או `[INI]`. מקטע `[Files]` קיים רק
לתמונות העיצוב, וכל רשומה בו נושאת `dontcopy`: התמונות נשלפות לתיקייה הזמנית
בזמן ריצה ונמחקות ביציאה. מסך הפתיחה ועמוד הבחירה הראשון אומרים את זה במפורש.

### התג המוטבע

הכלי היה **חסר-גרסה** — הוא קרא את `/releases/latest` וזהו. זה נשבר: GitHub
מדלג ב-`/releases/latest` על prerelease, ובפורק כל שחרור הוא prerelease, ולכן
הנקודה הזאת החזירה שחרור עתיק שאין בו מניפסט והכלי הודיע "לא נמצא".

לכן הכלי נבנה עם **התג שממנו נבנה**, שמועבר ל-ISCC ב-
`/DAssistantReleaseTag="<tag>"` — בדיוק כפי ש-`otzaria_full.iss` מקבל
`/DIndexedReleaseTag`. התג מחושב ב-workflow באותו כלל שבו `create_release`
מחשב אותו (ענף `main` → `<version>`, אחרת `<version>+<run_number>`), ולכן הוא
מצביע תמיד על שחרור שבוודאי נושא מניפסט.

בבנייה מקומית בלי ההגדרה התג המוטבע ריק, והכלי נופל חזרה להתנהגות הישנה:
`/releases/latest` בלבד.

### מסלול הריצה

0. **החלון מופיע מיד.** `InitializeSetup` אינו פונה לרשת (רק מסלול הפיתוח
   `DevSelectionDump`, שיוצא בלי חלון, טוען בו). המניפסט נטען כשהמשתמש לוחץ
   "בואו נתחיל" (`NextButtonClick(wpWelcome)` → `LoadManifestStep`), בעמוד
   "מתחבר לאתר אוצריא" שמעבד הודעות ואפשר לבטל בו. כל בקשה בלי hash — רשימת
   ה-release והמניפסט, ורק הן — עוברת ב-`FetchToTemp`. ל-Inno 6.7 אין הגדרת
   זמן קצוב להורדה; חיבור לכתובת שאינה עונה נכשל אחרי כ-21 שניות (WinHTTP,
   ‏12002, נמדד).
1. שלב הטעינה קובע את התג: ברירת המחדל היא התג המוטבע. הוא פונה
   ל-`api.github.com/repos/<owner>/otzaria/releases/latest`, ואם `tag_name`
   שם הוא **גרסה גבוהה יותר** — הוא זה שנבחר. שווה או נמוך → התג המוטבע.
   ההשוואה היא על החלק המספרי `X.Y.Z` בלבד; סיומת `+build` אינה משתתפת בה,
   שכן סדר מספרי ה-run אינו סדר גרסאות. `/releases/latest` שאינו זמין או
   שאינו ניתן לפענוח אינו כישלון: נשאר התג המוטבע.
2. כשהתג הוא ה-latest, הנכס שמסתיים ב-`release-manifest.json` מאותר ברשימת
   הנכסים שכבר נקראה. כשהתג הוא המוטבע, **אין קריאת API נוספת**: המניפסט יורד
   ישירות מ-`…/releases/download/<tag>/otzaria-release-manifest.json` (השם
   שה-workflow כותב; ה-`+` נשאר כפי שהוא — נבדק: 200). כך מגבלת הקצב של
   api.github.com (403/429, משותפת לכל יוצאי אותה כתובת בנטפרי) אינה מפילה
   את הטעינה; היא רק מבטלת את בדיקת "גרסה גבוהה יותר". ההגדרה `DevApiBase`
   (פיתוח בלבד) מפנה את ה-API לכתובת אחרת כדי לבדוק זאת — גם לשם שאינו נפתר
   או לכתובת שאינה עונה, וכך נבדק מסך "אין חיבור" בלי לגעת ברשת.
   התג **ננעל לכל הריצה**: אחרי טעינה שהצליחה "בואו נתחיל" אינו טוען שוב, ו-
   release שמתעדכן באמצע הורדה אינו יכול לערבב קבצים משתי גרסאות.
3. כישלון מוצג **בעמוד שגיאה בתוך החלון** ולא ב-MsgBox: "נסה שוב", "פתח את
   עמוד ההורדות" (הנסיגה הקיימת לדפדפן), "סגור", ו"פרטים טכניים" שמציג את
   `LoadErrorTech` בטקסט שאפשר לבחור ולהעתיק. כשכל הבקשות נכשלו בשגיאת רשת
   (WinHTTP ‏12002/12007/12029/12030/12031) הכותרת היא "אין חיבור לאינטרנט";
   מניפסט חסר, פגום או בגרסת סכמה אחרת — הנוסח הקיים. "נסה שוב" מסתיר את העמוד
   ולוחץ שוב על "הבא" של העמוד שבו קרה הכישלון: בטעינה — טעינה חוזרת; בהורדה,
   באימות, בהרכבה או בהעתקה — אותו תג ננעל ואותו מטמון, בדיוק כמו לחיצה חוזרת
   על "התחל", ומה שכבר ירד נשמר. האשף לעולם אינו מוריד רכיב שאין לו ממנו hash.
   **עצירה של המשתמש אינה תקלה**: "עצור הורדה" (או כפתור העצירה של Inno,
   `AbortedByUser`) מסומן ב-`StopRequested`, ו-`ShowFailure(RunStopped)` מציג
   עמוד רגוע — "ההורדה הופסקה", תג השהיה בגווני הכרטיס, "המשך" ו"סגור" בלבד.
   "המשך" עובד בדיוק כמו "נסה שוב". `StopRequested` מתאפס לפני כל ריצה, כדי
   שעצירה קודמת לא תציג כישלון מאוחר יותר כעצירה.
4. העמודים: פתיחה (מסך מונפש) ← "Windows — כמו המחשב הזה" / "סוג מחשב אחר" ←
   רשימת היעדים (רק לסוג מחשב אחר) ← הצעות ← בחירה אישית (רק אם נבחרה) ←
   תיקיית היעד ← מוכן ← הורדה ← סיום. כל שאלת אישור (רכיב או מחשב שלא נבחרו,
   תיקייה שאי אפשר לכתוב אליה, מקום פנוי, הפסקת החיבור, עצירת הורדה ויציאה)
   מוצגת בחלון דו-שיח מעוצב; שאלת העצירה המובנית של עמוד ההורדה של Inno
   (`msgStopDownload`) אינה מוצגת לעולם: גם בעמוד החיבור "ביטול" כותב
   `StopRequested`, ופונקציית ההתקדמות של העמוד (`OnConnectProgress`) עוצרת. ביטול
   החיבור מחזיר למסך הפתיחה. לחיצה על כפתור בזמן שדו-שיח פתוח נבלעת.
5. **סגירה (X) בכל מצב.** Inno מקבל סגירה רק בעמוד שיש בו "ביטול"; בעמודי
   ההתקדמות (חיבור, הורדה, בדיקה, הרכבה) הוא מתעלם ממנה. לכן `UiRequestClose`
   שואל בעצמו באותו חלון מעוצב, ואם אושר — מסמן `UiClosing` ו-`StopRequested`,
   והסגירה מתבצעת כשהשלב חוזר לעמוד רגיל (`UiCloseIfRequested`, בלי שאלה שנייה
   ובלי עמוד שגיאה). בהורדה זה מיידי; שלב שאי אפשר לעצור (hash, הרכבה) מסתיים
   קודם. בעמוד הסיום X פשוט מסיים.

### היעד בסקריפט

`UpdateTarget` הוא המקום היחיד שקובע את `TargetPlatform` / `TargetArchitecture` /
`TargetFormat`, וכל כלל בחירה קורא רק אותם — לא את העמודים. "כמו המחשב הזה" =
`windows` + `RunningArchitecture()` (`IsArm64`). אחרת: השורה שנבחרה ב-`OtherPage`,
מתוך `OtherPlatform` / `OtherArch` / `OtherFormat` ש-`FillOtherPage` בונה אחרי
טעינת המניפסט. כשאין לפלטפורמה רכיבים תלויי-ארכיטקטורה (macOS, Android) היעד
נושא ארכיטקטורה ריקה, כמו ב-`AssistantTarget` של מימוש הייחוס. כללי הבחירה אינם
תלויים במצב: גם "כמו המחשב הזה" מקבל את מה שמימוש הייחוס נותן ל-Windows באותו
מעבד, כולל נתוני החיפוש החכם בשתי ההצעות המלאות — הפלט הוא תיקייה גם שם.

`ComponentFitsTarget` בודק את שלושת השדות דרך `IsWildcard` (ריק או `any` מתאים
לכל יעד; ערך לא מוכר אינו מתאים לאף יעד). `ComponentIsOffered` מוסיף עליו את
`ComponentIsRunnable` (אין exe של 4 GiB ומעלה) ואת `InstallerFor`, וכל רשימה
שהמשתמש רואה — ההצעות, `CollectByTypes`, הבחירה האישית — נבנית ממנו. `PlatformChoices`,
`ArchitectureChoices`, `PackageFormatChoices`, `BuildPresets`,
`ShouldAssembleSingleFile`, `OutputSubFolderName`, `PlannedOutputNames` ו-`IsCustomChoice` הם
התרגום של הפונקציות באותו שם ב-`download_assistant_selection.dart`.

**אימות מול הייחוס — הגדרות פיתוח.** Inno אינו מריץ בדיקות, ולכן יש שתי הגדרות
`#ifdef` שה-CI לעולם אינו מגדיר (נבדק ב-`הגדרות הפיתוח לעולם אינן מוגדרות ב-CI`):

```powershell
ISCC /DDevManifestFile=C:\...\fixtures\release-manifest.json `
     /DDevSelectionDump=C:\...\selections.txt installer\download_assistant.iss
```

`DevManifestFile` קורא את המניפסט מקובץ מקומי במקום מ-GitHub (גם להרצה אמיתית
מול מניפסט שנבנה ידנית). `DevSelectionDump` מריץ את כללי הבחירה של הסקריפט
עצמו על כל יעד, כותב את הרכיבים המתאימים, ההצעות, קובצי הפלט ותת-התיקייה לקובץ,
ויוצא בלי אשף — להשוואה מול `expected-selections.json`, כולל שורות הבחירה
האישית (`custom id:size:locked:group`). כל עשרת היעדים תואמים,
וגם שני היעדים של `expected-selections-large-full.json` (הרצה שנייה עם
`DevManifestFile` של הווריאנט).

### ההצעות נגזרות מהמניפסט

אין רשימת שמות קבצים בסקריפט. ההצעות נבנות מ-`type` ומ-`required` של הרכיבים,
ולכן רכיב חדש במניפסט נוחת בהצעה הנכונה **בלי שינוי קוד**:

| הצעה (בסדר ההצגה) | הכלל |
|---|---|
| התקנה בסיסית (מומלצת) — מסומנת מראש (`kDefaultPresetId`) | כל `application` תואם + כל רכיב `required` |
| התקנה מלאה + אינדקס חיפוש (`full-indexed`) | `IndexedPresetBundle`: רכיב `application-bundle` מוצע שספרייה מוצעת מונה אותו ב-`installedBy` שלה (`InstallsLibrary`), הגדול ביותר יחד עם מה שהוא מתקין (`WithInstalled`); עם מה שהוא מתקין, ועם כל רכיב מוצע מסוג `semantic-model`/`semantic-vectors` (`OfflineDataTypes`). בלי חבילה כזו — אין הצעה |
| התקנה מלאה | `FullPresetBundle`: רכיב `application-bundle` הגדול ביותר שמוצע ליעד, עם כל רכיב מוצע שהוא ב-`installedBy` שלו; אם אין — כל ה-`application` + `library` + `dependency`, ורק כשיש ביניהם ספרייה. בשני המקרים — גם `OfflineDataTypes` |
| עדכון התוכנה בלבד | כל `application` תואם |
| בחירה אישית | האפשרות היחידה שאינה נגזרת; תמיד אחרונה |

`BuildPresets` מוסיף אותן בסדר ההערכה של מימוש הייחוס — מלאה + אינדקס, מלאה,
בסיסית, עדכון — כי הסדר הזה קובע איזו כפולה מושמטת (השם המפורט נשאר). `AddPreset`
מכניס כל הצעה למקומה לפי `PresetDisplayOrder` (`DisplayRank`), שהוא `kPresetDisplayOrder`,
ו-`CustomPresetIndex` הוא מספר ההצעות. בחירת החבילה של כל הצעה מלאה היא פונקציה
נפרדת, כך שאפשר להחליף אותה בלי לגעת בשאר. מסומנת מראש "בסיסית", בלעדיה "מלאה"
(לא "מלאה + אינדקס" הגדולה ממנה), ובלי שתיהן — הראשונה (`RefreshPresetPage`, כמו
`defaultPresetIdFor`).

סוג שאינו ברשימת הסוגים של ההצעה אינו נכנס אליה. לכן הגרסה הניידת נושאת סוג
משלה, `application-portable`: היא צורה חלופית של אותה תוכנה, וצירופה יחד עם
המתקין היה מוריד קובץ מיותר והופך את התוצאה מקובץ אחד לתיקייה. רכיב `required`
נכנס ל"בסיסית" בכל מקרה, גם אם סוגו חדש ואינו מוכר לסקריפט.

על כל הצעה נסגרת גם סגירת ה-`dependsOn` וה-`installedBy` שלה — וכך גם הבחירה
האישית (`NextButtonClick` מריץ עליה `WithDependencies`), כדי שספרייה שסומנה
לבדה תגיע עם המתקין שקורא אותה. הצעה שיצאה **ריקה**, או שיצאה
**זהה** להצעה קודמת אחרי נרמול, אינה מוצגת — בדיוק כמו רכיב שאינו במניפסט,
שהוא פשוט נעדר ולא שורה מעומעמת. במניפסט הנוכחי "בסיסית" ו"עדכון בלבד"
מכילות אותו רכיב, ולכן ב-Windows x64 מוצגות שלוש הצעות ו"בחירה אישית" (ב-0.9.98:
45 MB, 5.4 GB, 3.8 GB); בשאר היעדים אין ספרייה מאונדקסת, ולכן שתיים.

### מטמון ואימות

המטמון יושב ב-`%LOCALAPPDATA%\Otzaria\DownloadAssistant\cache`.

* כל הורדה מעבירה את ה-sha256 מהמניפסט לעמוד ההורדה של Inno, **תמיד**. זה
  ה-hash היחיד של קובץ שירד.
* `PromoteToCache` בודק **גודל בלבד**, מעביר ל-`<שם>.download` ומשם לשם הסופי,
  ורק אחרי זה כותב את החותם `<שם>.sha256` (פורמט `sha256sum`). חותם ישן נמחק
  לפני ההחלפה. קובץ חלקי לעולם אינו נספר כמי שהורד.
* `CachedFileIsGood` / `FileMatchesMarker`: גודל תואם + חותם שה-hex שבו שווה
  למניפסט + זמן השינוי של הקובץ אינו מאוחר מזה של החותם → מוכן, בלי hash. חותם
  שמעיד על תוכן אחר → לא מוכן (בלי hash). בלי חותם → hash אחד, ואם תואם — חותם.
  קובץ שיש לו יותר מקישור אחד (`GetFileInformationByHandle` →
  `nNumberOfLinks > 1`, כלומר הקישור הקשיח לתיקיית היעד עדיין קיים) אינו נסמך
  על החותם ועובר hash: דריסה של הקובץ ביעד (סייר, `Copy-Item`) משנה גם את המטמון
  ואינה מקדמת את זמן השינוי.
* תג, שם נכס ושם חלק חייבים להתאים ל-`^[A-Za-z0-9._+-]+$` ולא להיות נקודות בלבד
  (`IsSafeName`) — הם משמשים גם כנתיבים; מניפסט אחר נדחה.
* `HashFile` הוא המקום היחיד שקורא ל-`GetSHA256OfFile`, וכל קריאה נרשמת ללוג
  (`hashed <name> in <ms>`), כך שבלוג רואים כמה פעמים חושב hash לכל קובץ.

**נמדד לקובץ יחיד, ללא הרכבת חלקים** (`/LOG`, אותו מחשב, מתקין FULL של 0.9.97 — ‎2,012,390,081‎ בתים):

| שלב אחרי הבית האחרון | לפני | אחרי |
|---|---|---|
| אימות בעמוד ההורדה (hash של Inno) | 20.4 ש׳ | 22.7 ש׳ |
| `PromoteToCache` | 24.5 ש׳ (hash שני) | אלפיות שנייה (גודל + שינוי שם + חותם) |
| מטמון→יעד | 11.5 ש׳ (העתקה) | 7 מ״ש (קישור קשיח) |
| **סה״כ** | **56.4 ש׳, 2 hash** | **22.7 ש׳, hash אחד** |

מטמון ישן בלי חותם: hash אחד (19.6 ש׳) ואז חותם; ההפעלה הבאה — אפס hash, 1.2 ש׳
לכל הריצה. הרכבה של אותו קובץ משני חלקים (1.2GB + 0.75GB) נמדדה בעבר
ב-10.7 ש׳ בלי אימות הקובץ השלם; כעת ההרכבה מוסיפה מעבר SHA-256 כדי לזהות
גם פגימה בקובץ חלקי שנשמר מהרצה קודמת. הפעלה חוזרת מזהה קובץ שהושלם לפי
החותם בלי hash נוסף.

### הרכבת נכס מפוצל

השרשור הוא בתים טהורים דרך `TFileStream` של Inno:
`Seek(0, soFromEnd)` על היעד ואז `CopyFrom(Source, 0, 4MB)`. **בלי PowerShell,
בלי `copy /b` ובלי כלי עזר** — התוצאה חייבת להיווצר גם במחשב שאין בו כלום.
הקיצוץ בחידוש הרכבה נעשה ב-`Seek` של 64 סיביות ואז `SetEndOfFile`, כי
`TStream.Size` הוא 32 סיביות ואינו מסוגל לגעת בקובץ מעל 2GB.

נמדד על המכונה הזאת: שני חלקים של 1.2GB → 2.4GB תוך **6.5 שניות**, וה-sha256
של התוצאה זהה לשרשור שחושב בכלי חיצוני. `GetSHA256OfFile` של Inno החזיר את
אותו ערך על הקובץ המלא (32 שניות).

* **שיא הדיסק הוא הקובץ המורכב ועוד חלק אחד**: כל חלק (וחותמו) נמחק מיד אחרי
  שנוסף.
* **חידוש הרכבה**: חלק נמחק רק אחרי שהוספתו הושלמה, ולכן גודל קובץ ה-`.tmp`
  מזהה בדיוק כמה חלקים כבר נבלעו. בהפעלה חוזרת הקובץ מקוצץ לגבול החלק האחרון
  השלם וההרכבה ממשיכה משם.
* **ה-`.tmp` קשור לנכס**: לפני הבית הראשון נכתב לצדו `<שם>.tmp.sha256` עם
  ה-sha256 של הנכס. `.tmp` בלי חותם צד, או עם sha אחר, נמחק וההרכבה מתחילה
  מאפס — שם הנכס (`otzaria-<X.Y.Z>-windows-full.exe`) חוזר בין בניות של אותה
  גרסה וגודל החלק קבוע, ובלי זה `.tmp` של בנייה אחרת היה נספר כחלקים שנבלעו
  ומקבל חותם של הבנייה החדשה.
* **אימות הקובץ המורכב**: `AppendFileTo` מעתיק בפרוסות של 64MB ומוודא שכל
  פרוסה הועתקה במלואה. אחרי בדיקת הגודל, SHA-256 של הקובץ המורכב נבדק מול
  המניפסט. רק לאחר מכן הקובץ מקבל את שמו הסופי ונכתב לו חותם במטמון
  (`<שם>.sha256`) — עליו נשען `AssembledIsReady` בהפעלה הבאה.

#### מתי לא מרכיבים לקובץ אחד

הכלל מחושב מהנכס ומפלטפורמת היעד (`shouldAssembleSplitAsset`), לא מרשימת רכיבים:

```
גודל >= 4 GiB                    →  לא מרכיבים (בכל יעד)
יעד Windows                      →  מרכיבים רק .exe
כל יעד אחר                       →  מרכיבים
```

* **`>= 4 GiB`** — Windows מסרב להריץ קובץ הפעלה בגודל 4 GiB ומעלה
  (`ERROR_BAD_EXE_FORMAT`; נבדק: ‎2^32-1‎ רץ, ‎2^32‎ נכשל), ו-FAT32 אינו מחזיק
  קובץ כזה. החלקים נשארים כפי שהם בתיקיית היעד; ביעד שאינו Windows עמוד הסיום
  מציג את פקודת החיבור (`cat <שם>.part-* > <שם>`). **exe** כזה אינו מוצע כלל
  (`ComponentIsRunnable`) — חלקים של מתקין שאי אפשר להריץ אינם התקנה, ו"מלאה"
  עוברת למתקין הרגיל עם חלקי הספרייה (פרק "ההצעות" בחוזה המשותף).
* **יעד Windows, נכס שאינו `.exe`** (למשל `…tar.zst` של הספרייה) אינו מורכב:
  המתקין שצורך אותו מצפה למצוא את **החלקים** לצדו, בדיוק כפי ש-`otzaria.iss`
  קורא אותם (`PrepareLibraryParts`).

`otzaria-<ver>-windows-full.exe` שוקל 2,012,390,081 בתים — ‎93.7%‎ ממגבלת ה-2
GiB — ולכן הוא המקרה הראשון שיתפצל, והוא נופל בדיוק בענף "מרכיבים": `.exe`
ומתחת ל-4 GiB. הגידול שאחריו, 4 GiB ומעלה, מדומה בזוג הייחוס
`*-large-full.json`.

### תוצאה במחשב המנותק

תיקיית היעד מכילה קובצי הפעלה בלבד — או, כשמתקין ה-FULL גדול מכדי לרוץ, את
המתקין הרגיל ולצדו חלקי הספרייה (ואם נבחר — האינדקס) שהוא קורא.
אין צורך באינטרנט, ב-7-Zip, ב-PowerShell או בקובץ נוסף כלשהו לצידם.

**לאן נשמר.** ברירת המחדל היא התיקייה שממנה הופעל המסייע
(`ExtractFileDir({srcexe})`), והמשתמש עדיין רשאי לבחור אחרת. הכתיבוּת נבדקת
בכתיבה ממשית של קובץ בדיקה ולא לפי הנתיב — דיסק-און-קי לקריאה בלבד, שיתוף רשת
ותיקייה מוגנת נראים תקינים עד לניסיון הכתיבה. כשהיא נכשלת ברירת המחדל נופלת
ל-`{userdocs}\אוצריא-להתקנה`, עם משפט עברי שמסביר למה; הריצה לעולם אינה נכשלת
בגלל זה.

**צורת הפלט ולשון הסיום.** שתיהן נגזרות ממספר הקבצים שנוצרו בפועל
(`ProducedFileCount` לפני ההעתקה, `Produced` אחריה), ולא מהרכיב שנבחר. קובץ
אחד יושב ישירות בתיקייה שנבחרה, ועמוד הסיום מדבר על **קובץ**, נוקב בשמו ובמערכת
היעד, ואומר מה עושים בו שם לפי הסיומת (`OpenHint`: הפעלה, DMG, DEB/RPM, APK,
או חילוץ ארכיון). כמה קבצים שחייבים להישאר יחד מקבלים תת-תיקייה בשם
`אוצריא להתקנה ל-<פלטפורמה>`, ועמוד הסיום מדבר על **תיקייה** שמעתיקים כולה.

**מטמון→יעד** (`CopyToOutput`): קודם `CreateHardLinkW` (אותו כונן — מיידי, בלי
להכפיל מקום), ובכישלון (כונן אחר, FAT32/exFAT) — `CopyFile`. קובץ שהורכב נכתב
ישר ליעד ואינו מועתק. `RunAfterExe` נקבע רק במצב "כמו המחשב הזה" (גם המתקין
המאונדקס שליד חלקי הספרייה), והוא רץ רק בלחיצה על "התקן עכשיו במחשב הזה" בעמוד
הסיום (`RunInstaller`; בכישלון — דו-שיח עם התיקייה שממנה מפעילים ידנית). לצדו
"פתח את תיקיית ההתקנה" (`OpenOutputFolder`) ו"סגור". ב"סוג מחשב אחר" יש במקומם
תיבת סימון מסומנת מראש שפותחת בסיום את הסייר עם הקובץ/התיקייה מסומנים
(`explorer.exe /select,"<path>"` דרך `ExecAsOriginalUser`); כישלון שלה שקט —
התוצאה כבר מוכנה.

### שפה

**עברית או אנגלית — לפי שפת הממשק של Windows.** `[Languages]` מונה את `english`
(ראשונה, ולכן הנסיגה של Inno) ואת `hebrew`; `LanguageDetectionMethod=uilanguage`
ו-`ShowLanguageDialog=no`: ממשק Windows בעברית — עברית, כל שפה אחרת — אנגלית,
בלי שאלה. לבדיקה בלי לשנות את המערכת: `/LANG=english` או `/LANG=hebrew` בשורת
הפקודה (Inno מעדיף אותם על הזיהוי). העברית לא השתנתה בפיקסל.

**איפה הטקסטים.** אין טקסט גלוי מילולי ב-`[Code]`: כל משפט נמצא ב-`[CustomMessages]`
עם `english.` ו-`hebrew.` — הלוגיקה ב-`download_assistant.iss`, ושכבת התצוגה
בשלה — והקוד קורא `CustomMessage('…')` (או `Msg1`/`FmtMessage` עם ‎%1‎). ברירות
המחדל של Inno נדרסות ב-`[Messages]` לשתי השפות. הפרטים הטכניים והלוג נשארים
באנגלית בשתיהן. שמות הרכיבים, התיאורים וה-`outputNote` באנגלית מגיעים מהמניפסט
(`nameEn`, `descriptionEn`, `outputNoteEn`), ובהיעדרם (release ישן) — העברית,
כמו `componentText` במימוש הייחוס.

אין בעמודים הרגילים "מניפסט", "נכס", "hash" או "ארטיפקט". שגיאה נקראת
"לא ניתן להכין את ההתקנה משום שאחד הקבצים הדרושים אינו זמין", ומאחוריה
כפתור "פרטים טכניים" שמציג את הסיבה האמיתית (שנרשמת גם ללוג).

שם רכיב מוצג למשתמש, ולכן שם מערכת ההפעלה נכתב בו **Windows** באותיות
לטיניות — "חלונות" אינו שם מוצר.

ברירות המחדל של Inno מנוסחות כמתקין ("מתקין את...", "תוכנת ההתקנה"), והכלי
אינו מתקין דבר, ולכן מקטע `[Messages]` דורס את כולן: `SetupAppTitle`,
`SetupWindowTitle`, `SetupLdrStartupMessage`, `ButtonInstall`, `WizardReady`,
`ReadyLabel1/2a/2b`, `WizardPreparing`, `PreparingDesc`, `WizardInstalling`,
`InstallingLabel`, `StatusCreateDirs`, `StatusExtractFiles`,
`StatusSavingUninstall`, `StatusRunProgram`, `FinishedHeadingLabel`,
`FinishedLabel`, `FinishedLabelNoIcons`, `ClickFinish`, `SetupAborted`,
`ExitSetupTitle`, `ExitSetupMessage`, וגם `WelcomeLabel1/2` (כותרת החלון והשורה
שבמסך הפתיחה), `ButtonNext/Back/Finish` ("המשך", "חזרה", "סיום") ו-`ButtonStopDownload`
— כל אחד ב-`english.` וב-`hebrew.`. המסך הראשון
אומר שהמסייע מוריד את הקבצים ואינו מתקין דבר; גם במסלול "כמו המחשב הזה" הוא
מפעיל את המתקין הרשמי רק כשהמשתמש לוחץ "התקן עכשיו במחשב הזה".

**שם הקובץ מול שמו לעין.** GitHub מסנן שם נכס ל-`[A-Za-z0-9._-]`, ושם עברי
נמחק ולא מתועתק — ולכן שם הקובץ נשאר ASCII. הזיהוי מגיע ממאפייני הקובץ, שאינם
תלויים בשפת הממשק ולכן כתובים בשתי השפות: `VersionInfoProductName`
(`Otzaria Download Assistant · מסייע הורדה לאוצריא`), `VersionInfoDescription` שאומר
שהוא מוריד ואינו מתקין (כל ערך עד 60 תווים — Inno קוטע את השאר), ו-`VersionInfoProductTextVersion` מחלק ה-‎X.Y.Z‎
של התג המוטבע (כשיש כזה).

### התצוגה — שלושה קבצים

החלון מצויר כולו בשכבה נפרדת, שמשותפת למסייע ולמתקינים של אוצריא:

| קובץ | תוכן |
|---|---|
| `installer/otzaria_ui_art.iss` | דרישת Inno 6.7.x (מ-6.7.1, ו-7 נעצר ב-`#error` עד שייבדק), ה-`.isi` של העיצוב ובדיקות הגרסה שלו, ו-`[Files]` של התמונות (`dontcopy`). נכלל לפני כל `[Files]` אחר: עם `SolidCompression` הפתיחה הייתה ממתינה לפריסת מה שקודם לתמונות |
| `installer/otzaria_ui_core.iss` | הליבה, בלי אף עמוד או מצב של מוצר: יסודות, ציור, כפתורים, כרטיסי בחירה (`UiAddCard`/`UiEndCards`), גלילה, שדה תיקייה (`UiBuildFolderField`), שורות סיכום (`UiAddRow`/`UiPlaceSummary`), התקדמות (`UiBuildProgress`, `UiBuildInstalling`, וחלון ההתקדמות המצומצם `UiInitializeCompact`), פרטים טכניים (`UiRtf`), נקודות שלבים וכותרת, הפתיחה המונפשת, שורת הכותרת, דו-שיח (`UiAsk`/`UiAskDialog`/`UiTell`/`UiAskExit`), עכבר, שעון, שיקוף (`UiX`), ו-`EnglishUi`/`LtrUnit`/`Msg1`. ב-`[CustomMessages]` שלה רק טקסטים שהיא עצמה מציגה |
| `installer/download_assistant_ui.iss` | המתאם של המסייע: הכרטיסים מעמודי האפשרויות, הסיכום, ההורדה וההכנה, עמוד הסיום ועמוד השגיאה, והטקסטים שלהם |
| `installer/otzaria_ui_installer.iss` | המתאם של מתקיני אוצריא — ראה "מתקיני אוצריא בשכבת התצוגה" |

`download_assistant.iss` כולל את העיצוב ואת הליבה לפני `[Code]` שלו (הליבה מגדירה
את `EnglishUi`, ולכן קודמת לכל הקוד), ואת המתאם מתוך `[Code]` לפני
`InitializeWizard`, אחרי העמודים שהוא קורא. **חוזה המתאם** מוצהר ב-`forward` בראש
`[Code]` של הליבה, וכל מוצר מממש את כולו: `UiButtonClick` (מעביר ל-`UiCoreButtonClick`
את "הבא", "חזרה", העיון והמזעור), `UiAdapterStepOf`, `UiAdapterLeavePage`,
`UiAdapterPageHint`, `UiAdapterBuildPage`, `UiAdapterBuildFinish`, `UiAdapterProgress`,
`UiAdapterSyncFooter`, `UiAdapterPollMouse`, `UiAdapterCardSelected`, `UiAdapterCardClick`,
ושלושה של המקלדת: `UiAdapterCardFocused` (הכרטיס שהפקד האמיתי שבמוקד עומד עליו),
`UiAdapterFocusTarget` (לאיזה כפתור מצויר עובר המוקד של פקד אמיתי) ו-`UiAdapterEnterGoesNext`.
מספרי הכפתורים והמקורות של המתאם מתחילים ב-`UiBtnFirstAdapter` וב-`UiSrcFirstAdapter`.
`UiInitializeWizard(TitleArt, TitleArtEn, StartCaption)` מקבל את קידומת הכותרת של
הפתיחה בעיצוב ואת הכפתור שמתחתיה. `UiAsk` עובד גם לפני האשף (ב-`InitializeSetup`):
ממורכז במסך, בלי שכבת הצל. בו Esc וסגירה עונים "לא"; `UiAskDialog(..., NoCancel=True)` מתנהג
כמו `MsgBox` של כן/לא — רק אחד הכפתורים סוגר אותו.

הלוגיקה אינה יודעת על השכבה דבר מלבד שלוש קריאות:
`UiAssistantInitializeWizard` בסוף `InitializeWizard`, `UiCurPageChanged` בסוף
`CurPageChanged` ו-`UiDeinitializeSetup` בתחילת `DeinitializeSetup`. עמודי Inno
(`ModePage`, `PresetPage`, `FolderPage`, `DownloadPage`...) נשארים מודל הנתונים:
כרטיס שנלחץ כותב ל-`SelectedValueIndex` או ל-`Values[i]`, והכרטיסים מסתנכרנים
מהם בכל פעימה — ולכן כל כלל, כל דילוג וכל בדיקה נשארו כפי שהיו. בבחירה האישית
יש כרטיס לכל שורה של `RefreshCustomPage` (`CustomIndex`), בגודל `CustomChoiceSize`:
חלק (`partOf`) אין לו כרטיס, והוא נבחר עם השלם דרך `WithDependencies`.

* **חלון.** `bsNone` בגודל לקוח 400×660 (ביחידות 100%), שורת כותרת משלה עם מזעור
  וסגירה (`SC_CLOSE`, כלומר אותה שאלת יציאה), פינות מעוגלות ב-Windows 11 וצל.
  `FlipControlsOnShow := False`: כל פקד ממוקם ישירות במקומו הסופי, ואין הבדל בין
  פקדים שנוצרו לפני ההצגה לאלה שאחריה. **הפריסה כתובה מימין לשמאל**, ובאנגלית
  (`UiRtl = False`) כל מיקום אופקי עובר ב-`UiX` לצד השני: כותרת החלון משמאל
  והמזעור והסגירה מימין, טקסט מיושר לשמאל, סימון ואריח הסמל משמאל לכרטיס, פס הגלילה
  מימין, ההתקדמות מתמלאת משמאל לימין, "המשך" מימין ו"חזרה" משמאל, ובדו-שיח הכפתורים
  בצד ימין. כותרת הפתיחה באנגלית היא `title_en_*` (כשהעיצוב מגדיר `AA_TITLE_EN`).
  Inno ממרכז אותו באזור
  העבודה בהצגה הראשונה, ו-`UiKeepOnScreen` (בכל פעימה, לא בזמן לחיצת עכבר)
  מחזיר אותו כולו לאזור העבודה של המסך שעליו הוא — אחרי גרירה, שחזור ממזעור
  או שינוי מסך. בגובה 660 מסך של 768 משאיר רק 68 פיקסלים של מרווח.
* **עמודים.** מסך פתיחה מונפש (ספר נפתח, עולה, והכותרת נחשפת; לחיצה מדלגת לסוף,
  ובלי אנימציות מערכת מוצג המצב הסופי מיד), נקודות שלבים, כותרת ושאלה מהעמוד
  עצמו, כרטיסים עם סמל, סיכום לפני ההורדה, תצוגת התקדמות עם אחוז ופס, ועמוד
  סיום עם תג הצלחה — ובו, במחשב הזה, "התקן עכשיו" / "פתח את תיקיית ההתקנה" /
  "סגור", ולמחשב אחר תיבת "הצג" כשורת כרטיס. תקלה מוצגת בעמוד שגיאה בתוך החלון;
  עצירה של המשתמש — בעמוד רגוע עם תג השהיה (`badge_paused`). רשימה ארוכה נגללת
  בגלגלת (hook של העכבר, כי הגלגלת מגיעה לפקד שבמוקד) ובגרירת הפס הדק שמשמאל.
* **סמלי ההצעות.** `UiOptionIcon` נותן לכל הצעה את `ico_preset_<מזהה>`, עם קו תחתון
  במקום מקף (`full-indexed` ← `preset_full_indexed`: מדף הספרים של "מלאה" עם זכוכית
  מגדלת); הסיכום לפני ההורדה משתמש באותו סמל. העיצוב חייב להכיל אותו: עיצוב שקודם
  ל-1.4.0 נעצר ב-`#error`. העמוד נגלל כשהכרטיסים אינם נכנסים.
* **יחידות.** גדלים ומהירויות באותן יחידות כמו בתוכנה — GB, MB, KB, MB/s, KB/s
  (`HumanSize`, `HumanRate`) — בעברית עטופים ב-LRE…PDF (`LtrUnit`), אחרת "37 MB"
  בתוך משפט עברי מוצג הפוך. ב-`HumanSize` בין המספר ליחידה רווח קשיח (U+00A0), כדי ששבירת שורה
  לא תפריד ביניהם.
* **ציור.** כרטיסים וכפתורים הם מפות סיביות שמורכבות בזמן ריצה: פרוסות PNG
  דרך `AlphaBlend` (ל-`TCanvas` של Pascal Script אין `Draw`) וטקסט דרך
  `DrawTextW`, עם `DT_RTLREADING` לטקסט עברי. אין תווית מעל תמונה, ולכן אין אי-התאמה של צבע
  רקע. שורת נתיב או שם קובץ נקראת משמאל לימין גם כשהיא מיושרת לימין, ונתיב ארוך
  מקוצר באמצע (`MinimizePathName`) כך שהכונן והתיקייה האחרונה נשארים גלויים.
* **הכפתורים האמיתיים** נשארים פעילים מחוץ לחלון, והלחיצה
  נשלחת אליהם ב-`PostMessage(WM_COMMAND)` — "הבא" מריץ את כל ההורדה, וקריאה
  ישירה הייתה מקננת אותה בתוך אירוע הלחיצה.
* **מקלדת.** כל כפתור מצויר הוא `TBitmapButton` עם כיתוב (גם המזעור והסגירה), ולכן
  הוא יעד Tab עם מסגרת מוקד ושם לקורא מסך; הכפתורים האמיתיים אינם יעדי Tab ואינם
  Default. `UiKeyDown` (KeyPreview של החלון ושל הדו-שיח) שולח Enter לכפתור המצויר שבמוקד,
  ובלעדיו ל"הבא"; Esc נשאר של "ביטול" האמיתי. `UiFocusAction` מעביר בכל פעימה את
  המוקד שהאשף נותן לפקד אמיתי אל הכפתור המצויר שלו. רשימות הבחירה נשארות במוקד
  מחוץ לחלון: חצים ו-Space עובדים עליהן, והכרטיס שהן עומדות עליו מקבל מסגרת מוקד
  ונגלל לתצוגה. קנה המידה נבחר כך שהחלון נכנס לכל המסכים המחוברים, ברוחב ובגובה.
* **אתחול.** לפני ההצגה נקבעים רק הגיאומטריה והצבעים. התמונות נשלפות בפעימה
  הראשונה של הטיימר, כשהחלון כבר מוצג בצבע הרקע בלבד, ב-`ExtractTemporaryFiles`
  אחת לקנה המידה שנבחר (`UiExtractArt`, בתבנית שמעוגנת ל-`{tmp}`, שם יושבות רשומות
  `dontcopy`); בחלון המצומצם — מיד ב-`UiInitializeCompact`, כי ההתקנה מתחילה מיד. הספר והכותרת (רק ב-250%) נשלפים כל תמונה כשמגיע תורה
  (`ExtractTemporaryFile`). הטיימר וה-hook נעצרים ב-`DeinitializeSetup`; חריגה
  בשכבת התצוגה נרשמת ללוג ומפסיקה רק את העדכונים, לא את האשף.

**העיצוב אינו במאגר.** `installer/assistant_art/` (מסונן ב-`.gitignore`) מגיע
מ-Release של [Otzaria/otzaria-design](https://github.com/Otzaria/otzaria-design)
בגרסה שנעוצה ב-`installer/assistant_art.pin.json` (גרסה, כתובת, SHA-256 — המקום
היחיד שמשתנה). `tool/release/fetch_assistant_art.ps1` (pwsh, וגם Windows PowerShell)
מוריד את ה-zip לתיקייה זמנית ליד היעד, עם timeout ושלושה ניסיונות, מאמת SHA-256
**לפני** הפריסה, מוודא ש-`AA_ART_VERSION` שב-`.isi` שווה לגרסה הנעוצה, ומחליף את
התיקייה בבת אחת. בתיקייה נכתבת חותמת `.pinned-sha256`, והריצה הבאה מדלגת רק כשהיא
שווה ל-hash הנעוץ — לא לפי קיום קבצים. בנייה מקומית: הפקודה שבראש הפרק.

**העלאת גרסה:** בריפו העיצוב לפי ה-README שלו (`download-assistant/README.md`,
"פרסום גרסה חדשה"): `ART_VERSION`, הפקה, `py pack_release.py` שמדפיס גרסה ו-SHA-256,
ו-Release בתגית `download-assistant-art-v<גרסה>` עם
`download-assistant-art-<גרסה>.zip`. כאן מעדכנים את שלושת השדות ב-`assistant_art.pin.json`
ומריצים את הסקריפט ואת הבדיקות (הכתובת נבדקת מול הגרסה). דרישה חדשה מהעיצוב נאכפת
ב-`#error`: כללית ב-`otzaria_ui_art.iss`, ושל המסייע בלבד בראש `download_assistant_ui.iss`.

בעיצוב יש גם `assistant_art.isi` עם קני המידה,
הגדלים, הזמנים והצבעים (`AA_*`, צבעים כ-`0xBBGGRR` — ISPP אינו מקבל `$`).
בלעדיו הקומפילציה נעצרת ב-`#error` מוסבר. קנה המידה נבחר מה-DPI (100–250%)
כך שכל תמונה מוצגת פיקסל-לפיקסל, וכשהחלון לא נכנס במסך — קנה מידה קטן יותר.
**חריג: הספר והכותרת** (רוב הגודל) מוטמעים רק ב-250% (`AA_BOOK_SRC_SCALE`) ומוקטנים
ב-`Stretch` של `TBitmapImage` (SPLINE16; 42–47 dB מול רינדור לכל קנה מידה) — ה-exe ירד
מ-18.4MB ל-7.8MB. ההקטנה עצמה (כ-10ms) נעשית בציור.

**הפתיחה מפענחת בזרימה.** פריסת תמונה כזו (30–50ms כאן, כולל השליפה) ארוכה מפריים,
ולכן נפרסת לכל היותר אחת בכל פעימה, ומה שהשתנה מצויר לפני הפריסה. הספר הסגור מוצג
כבר אחרי הראשונה, בדהייה של 250ms (שכבה בצבע הדף מעליו), כך שאין עמוד ריק בזמן
ההמתנה. הניגון מתחיל רק כשהפריסה לא תעצור אותו: כל התמונות מוכנות, או שפריסה
(האיטית שנמדדה ועוד רבע) נכנסת גם בפעימה שמחליפה פריים. השעון מתקדם לכל היותר
פריים אחד בפעימה ונעצר אם התמונה הבאה חסרה — פריים לעולם אינו מדולג. כל תמונה
משוחררת ברגע שהוצגה (הפקד מחזיק עותק משותף משלו), ולחיצה, אנימציות כבויות או
יציאה מהעמוד עוצרות את הפריסה ומשחררות את השאר. נמדד כאן ב-100%: הספר נראה כ-0.2
שניות אחרי הופעת החלון (במקום כ-1.5 עם עמוד ריק), והזיכרון הפרטי אחרי הפתיחה
15MB במקום 49MB.

מלכודות שנמצאו: הערות `;` אינן הערות בתוך `[Code]` (ולכן ה-`.isi` נכלל אחרי
`[Files]`); שורה ב-`[Code]` שמתחילה (אחרי הזחה) ב-`[` נקראת ככותרת מקטע, וב-`#` —
כדירקטיבת ISPP; `PromptLabels[0]` של עמוד תיקייה עם הנחיה ריקה הוא `nil`;
`TWinControl.Focused` אינו ניתן לקריאה מהסקריפט (`ActiveControl` כן); גלגלת
שנשלחת ב-`PostMessage` אינה עוברת ב-hook, רק גלגלת אמיתית; `/` בין שני שלמים הוא
חילוק שלמים; `TBitmapImage.Opacity` אינו חשוף לסקריפט (ולכן הדהייה היא שכבה), וב-6.7.3
`Stretch` נכשל בתמונה בגובה שורה אחת.

### בדיקות

`test/installer/installer_scripts_test.dart`, קבוצה "מסייע ההורדה — אינו
מתקין". הסקריפט **אינו** נכלל ב-`_scripts`: האינוריאנטות של המתקינים (מסמנים,
רישום, הסרה, שיגור-מחדש) אינן חלות עליו. כל סקריפט נקרא יחד עם מה שהוא כולל
(`#include` מילולי, מורחב ברקורסיה), כך שכל אינוריאנטה חלה גם על הליבה ועל המתאם. הקבוצה הייעודית מאמתת
שהוא אינו מתקין דבר (כל רשומת `[Files]` נושאת `dontcopy`, ומקורה תחת
`assistant_art\`), שאין בו שם נכס קשיח, שכל כתובת היא `github.com` בארגון Otzaria,
שלהורדה תמיד מועבר hash, שקובץ זמני מקבל שם סופי רק אחרי אימות ושהחותם נכתב
אחריו, ש-`GetSHA256OfFile` נקרא ממקום אחד בלבד, שהמטמון וההרכבה נשענים על
החותם ולא על hash נוסף, שהעתקה מתחילה בקישור קשיח, שפס ההורדה מציג מהירות
וזמן ומחליף כותרת ב-100%, שהיעד הוא המחשב הזה או שורה מרשימה אחת שנגזרת
מהמניפסט (בלי בחירה מראש), ששני המצבים מורידים לתיקייה והמתקין רץ רק בלחיצה,
שעצירה של המשתמש מוצגת בנפרד מתקלה, שהחלון נשמר בתוך אזור העבודה, שכלל
ה-4 GiB קיים ותלוי בפלטפורמת היעד, שהפלט נקרא בדיוק `Otzaria-Download-Assistant-windows` — ASCII, ועם
`download-assistant` שעליו נשענת ההחרגה ב-`isDownloadAssistantAsset` — ושמאפייני
הקובץ (`VersionInfoProductName` / `VersionInfoDescription`) בשתי השפות. לשפה: כל
מפתח ב-`[CustomMessages]` וב-`[Messages]` קיים באנגלית ובעברית וכל קריאה מוצאת
אותו, אין מחרוזת עברית או משפט אנגלי מילולי ב-`[Code]` מחוץ ללוג ולפרטים הטכניים,
שם תת-התיקייה של החוזה נשמר ב-`DevSelectionDump`, והפריסה משתקפת רק דרך `UiX`.

`test/installer/download_assistant_presets_test.dart` קורא מהסקריפט את כללי
`BuildPresets` ו-`ComponentFitsTarget` (כולל בחירת שתי החבילות, סדר ההערכה, סדר ההצגה
וברירת המחדל) ומשווה אותם לכללים של מימוש הייחוס; את
ההצעות על טבלת `kKnownComponents` הוא מחשב דרך `download_assistant_selection.dart`
עצמו, בלי שכפול של הלוגיקה בבדיקה.

## מתקיני אוצריא בשכבת התצוגה — `installer/otzaria_ui_installer.iss`

המתקינים (`otzaria.iss` ו-`otzaria_full.iss`, כל אחד גם ל-ARM64) מצוירים באותה שכבה כמו
המסייע. מתאם אחד משמש את שניהם; מה שקיים רק במלא עטוף ב-`#ifdef InstallerFull`, ופריסת
חלקי הספרייה שליד המתקין הרגיל (#1890) ב-`#ifdef LibraryParts`.

**הכללה.** כל מתקין מגדיר `OtzariaUiProduct "installer"` ומכליל את `otzaria_ui_art.iss`
לפני `[Files]` שלו (עם `SolidCompression` הפתיחה אינה ממתינה לפריסת האפליקציה), ואת
הליבה לפני `[Code]`. המתאם נכלל בתוך `[Code]` אחרי משתני מודל הנתונים, ושגרות של
הסקריפט שמוגדרות אחריו מוצהרות בו ב-`forward`. העיצוב מטמיע לכל מוצר רק את כותרת
הפתיחה שלו (`title_inst_*` למתקינים, `title_*` בלעדיה למסייע) ואת הסמלים שלו; מתקין
עם עיצוב שאין בו `AA_TITLE_INST` ו-`AA_LOGO_SM_SIZE` (לפני 1.5.0) נעצר ב-`#error`.

**הזרימה.** פתיחה מונפשת עם "אוצריא" / "ספרייה תורנית חינמית", שורת הגרסה
(`WelcomeLabel2`) ו"התקנה" → **איך להתקין** (`wpSelectDir`): שלושה כרטיסים (רק בשבילי / לכל
המשתמשים / ניידת) מעל `TNewRadioButton` מחוץ לחלון, בפאנל משלהם כדי שהחצים יעברו רק
ביניהם; רדיו שמקבל מוקד מהמקלדת מסמן את עצמו, ו-`UiModeRadioClick` מעביר את הבחירה כמו
לחיצה על הכרטיס. מתחתם `DirEdit` כשדה
תיקייה עם "שינוי" ושורת המקום הפנוי של Inno. העמוד הוא `wpSelectDir` כדי שהבדיקות של
Inno לתיקייה ירוצו בו. בחירה בכרטיס קובעת את `PortableMode` ואת ברירת המחדל של התיקייה
מיד (`ApplyInstallModeChoice`); בחירה שמחייבת שיגור-מחדש (`ModeChangeNeedsRelaunch`)
מחליפה את השדה בהסבר, כי התיקייה נבחרת בחלון החדש. השיגור מרים גם את `UiClosing`, ולכן
החלון נסגר בלי שאלת "לצאת?"; הריצה המשוגרת-מחדש מדלגת על הפתיחה בלבד ונפתחת ב"איך
להתקין" עם הבחירה מסומנת → (מלא) **היכן לשמור את הספרים** (`BooksPage`, שדה ואזהרה על
תיקייה קיימת) → **אפשרויות נוספות** (`wpSelectTasks`): כרטיסי סימון דרך
`WizardSelectTasks`, ובמלא גם WebView2 (`WV2Check`, נעול כשהוא מותקן); בניידת העמוד מדולג
(במלא — אלא אם WebView2 חסר) → **מוכנים להתקין**: שורות סיכום → **רגע לפני ההתקנה**
(`wpPreparing`, כש-Restart Manager מצא תוכנה פתוחה): הרשימה ושני כרטיסים מעל
`PreparingYesRadio`/`NoRadio`; התיאור ניטרלי ("מכין את ההתקנה..."), ו"אוצריא פתוחה כרגע"
מחליף אותו רק כשיש רשימה, כי הכותרת מוצגת כבר בזמן ש-Restart Manager בודק → (רגיל, כשיש
לצדו חלקי ספרייה) **מכין את הספרייה** (`LibraryPrepPage`, רק באשף): "מחבר ומאמת את חלקי
הספרייה/אינדקס החיפוש" עם התקדמות אמיתית — גודל הארכיון שנכתב (`GetFileAttributesExW`, כי
רשומת התיקייה מתעדכנת רק בסגירה) מול סכום החלקים → **מתקין**: אחוז, הסטטוס והקובץ
הנוכחי; פריסת הספרייה רצה בו עם פס נע → **סיום**: "פתח את אוצריא" ו"סגור" מסמנים או
מנקים את רשומת `postinstall` ב-`RunList` ולוחצים "סיום" — אותה רשומת `[Run]`. כשהייתה
התקנה קודמת (`InstIsUpdate`, נקבע בפתיחה — אחרי ההתקנה הרישום כבר מראה את הגרסה החדשה)
הכפתור בפתיחה הוא "עדכון" והכותרת בסיום "אוצריא עודכנה".

**כישלון.** `Abort` ב-`ssPostInstall` אינו עוצר את Inno: הוא רושם "CurStepChanged raised an
exception" וממשיך לעמוד הסיום. לכן `InstReportFailure` שומר את ההודעה, ועמוד הסיום מוצג
כמצב כישלון (`badge_err`, ההודעה, "פרטים טכניים" עם קוד היציאה והפלט הגולמי של zstd/7za,
ו"סגור"). מתחת להודעה — "אפשר להריץ את ההתקנה שוב", ובמלא גם "ספרייה שכבר הייתה במחשב לא
שונתה" כל עוד `LibrarySwapStarted` לא הורם (הוא מורם רק אחרי שהספרייה הקודמת הוזזה לגיבוי).
ברגיל, ספרייה מהחלקים שלא נפרסה (`InstReportLibraryFailure`) מוצגת כך גם היא, תמיד עם
"ספרייה שכבר הייתה במחשב לא שונתה" — כל כשל שם מחזיר את הקודמת; קוד היציאה 9 לא השתנה.
בכישלון `RunList` מנוקה ו-`NoRadio` מסומן, כך שגם Enter לא יפעיל את התוכנה ולא יאתחל את המחשב.

**הודעות.** כל `MsgBox` של המתקין עובר דרך `InstTell`, `InstAskYesNo`,
`InstAskYesNoSuppressible`, `InstTellSuppressible`, `InstReportFailure` או
`InstReportLibraryFailure`: באשף — הדו-שיח המעוצב, ובהתקנה שקטה — בדיוק הקריאה שהייתה
(`MsgBox`/`SuppressibleMsgBox`, אותם דגלים). `UiAsk` אינו מושפע מ-`/SUPPRESSMSGBOXES`,
ולכן כל קריאה של המתקין אליו שמורה מאחורי `not WizardSilent`. היוצא מן הכלל הוא שאלת
היציאה של הליבה (`UiCancelButtonClick`): היא נשאלת גם ב-`/SILENT`, כי רק לחיצה של המשתמש
על X מפעילה אותה — כמו ה-MsgBox של Inno, שגם הוא אינו ניתן לדיכוי. `InstAskYesNo`
מבקש `NoCancel`, ולכן Esc אינו עונה "לא" במקום שבו ה-MsgBox הישן התעלם ממנו. שאלת "התיקייה קיימת" של Inno נשאלת
בדו-שיח המעוצב (`DirExistsWarning=no` ו-`DirExistsDifferentFromPrevious`, כמו `auto`).
נשארו של המערכת: אזהרת המקום הפנוי, שגיאות העתקה של Inno (נסה שוב/בטל/התעלם) והמסיר.

**התקנה שקטה.** `/VERYSILENT` — שכבת התצוגה אינה מאותחלת כלל. `/SILENT` (העדכון מתוך
התוכנה, השדרוג האוטומטי ו"התקן עכשיו" במסייע) — חלון התקדמות מצומצם בגובה 260
(`UiInitializeCompact` בליבה): סמל אוצריא (`logo_sm`), "מעדכן את אוצריא <גרסה>" (או "מתקין"
כשאין התקנה קודמת), אחוז, פס, ושורות הסטטוס והקובץ; בלי פתיחה, שלבים וכפתורים מלבד
הסגירה, שהיא אותה שאלת יציאה.

**שפה.** `english` ראשונה ו-`hebrew`, לפי שפת הממשק של Windows; בשדרוג Inno שומר את שפת
ההתקנה הקודמת. שם התוכנה (`AppName`), הקבוצה, שמות הקיצורים, הרישום ושמות הקבצים אינם
מתורגמים — שדרוג בממשק אנגלי חייב למצוא את אותה רשומה ואת אותם קיצורים. כל טקסט אחר
ב-`[CustomMessages]`, ובעברית בנוסח שהיה בקוד; ההודעות של Inno שמזכירות את שם התוכנה
(כולל ההסרה) נדרסות באנגלית ב-`[Messages]`.

**מקלדת.** כמו במסייע (ראה "מקלדת" בפרק התצוגה): Tab עובר בין הכפתורים המצוירים, Enter
מפעיל את זה שבמוקד, ובלעדיו "הבא"/"התקן". מאחורי כל כרטיס יש פקד אמיתי מחוץ לחלון
(`UiAdapterCardFocused`): רדיו "איך להתקין", שורה ב-`TasksList`, `WV2Check`,
`PreparingYesRadio`/`NoRadio` ו-`YesRadio`/`NoRadio` של האתחול. בנייד `TasksList` אינו
יעד Tab (אין כרטיסי משימות), ו-`PreparingMemo` ו-`RunList` אינם מקבלים מוקד.

**ההסרה** נשארת בלי עיצוב (למסיר אין גישה לתמונות), עם הטקסטים בשתי השפות. AppId משותף,
ולכן קוד ההסרה זהה בשני המתקינים, והבדיקות משוות אותו.

**CI.** כל שלב שמקמפל `otzaria*.iss` מריץ את `fetch_assistant_art.ps1` לפני ISCC, וכישלון
קטלני שם (חוץ מ-FULL ל-ARM64, שאינו חוסם ממילא). הנעיצה חייבת להיות 1.5.0 ומעלה. Inno
Setup נעוץ ל-6.7.1 (`install_inno_setup.ps1` והנסיגות ל-winget ול-choco), ו-ISCC נבחר
מתיקיית `Inno Setup 6`. גם `create.bat` מושך את העיצוב לפני ISCC.

**בדיקה ידנית.** AppId משותף: התקנת בדיקה על מחשב שמותקנת בו אוצריא תשדרג אותה. בונים עותק
של הסקריפטים עם AppId, תיקיות נתונים, פרוטוקול וקיצורים אחרים, ומתקינים לתיקייה זמנית.

## החיווט ל-CI

כל השינויים ב-`.github/workflows/build-and-announce.yml` הם **תוספת בלבד**: אף
שלב, שם ארטיפקט או שם נכס קיים לא שונה. מחוץ לשלבי המסייעים עצמם נערכו רק תנאי
`if` בהערות השחרור, שהורחבו ב-`||` על מערך שהוא ריק היום.

### בניית האשף — ב-`build_windows`, לא ב-job נפרד

השלב יושב ב-`build_windows` ולא ב-job ייעודי משתי סיבות: ה-job הזה כבר פתר את
`$env:ISCC` בשלב "Install Inno Setup", ו-job נפרד היה מחייב התקנה שנייה של Inno
Setup ורץ Windows שלם בשביל קומפילציה של שניות.

**מדיניות הכישלון: האשף אינו חוסם שחרור.** הוא כלי עזר, לא רכיב של הגרסה, ולכן
שלב הבנייה נושא `continue-on-error: true` וההעלאה שלו מותנית ב-
`steps.download_assistant.outcome == 'success'`. משיכת העיצוב
(`fetch_assistant_art.ps1`) רצה בתוך אותו שלב לפני ISCC, ולכן גם כישלון שלה (רשת,
hash שאינו תואם) מפיל רק את המסייע. ב-`create_release` השלב
"Stage Download Assistant" מעתיק את ארבעת המסייעים (Windows, macOS, Linux x64,
Linux ARM64 — הטבלה ב"נכסי המסייעים") כל אחד בנפרד, ועל כל קובץ חסר מדפיס
`::warning::` משלו וממשיך. גרסה
שיוצאת בלי מסייע ההורדה חסרה כלי נוחות; גרסה שלא יוצאת כלל חוסמת את כל
המשתמשים.

### המניפסט — כישלון רועש, שאינו חוסם שחרור

`Generate release manifest` רץ **אחרי** `Organize release files` (ואחרי הפיצול
המותנה, כדי שישקף את הצורה שתעלה בפועל) וכותב ל-
`release-files/otzaria-release-manifest.json` — כך הוא עולה עם שאר הנכסים.
השם חייב להסתיים ב-`release-manifest.json`, כי זה מה ש-
`LoadReleaseManifest` בסקריפט מחפש ברשימת הנכסים.

הגנרטור עצמו **נכשל ברעש** ואינו כותב מניפסט חלקי: מניפסט שבור שולח את האשף
להוריד קבצים שאין לו מהם hash, וזה גרוע מהיעדר מניפסט.

השלב ב-workflow, לעומתו, נושא `continue-on-error: true` — אותה מדיניות של
האשף עצמו. הגנרטור זורק גם על קלט שקודם לכן רק חסר נכס (שני קבצים תואמים
לתבנית אחת, חלק שרשום במניפסט פיצול ואינו בתיקייה — ההעתקות ל-`release-files`
נושאות `|| true` ולכן העתקה חלקית נבלעת, או `flutter pub get` שנכשל), ולכן
כישלון שלו היה מבטל release שלם בגלל נכס עזר אחד. השלב שאחריו מוחק מניפסט
חלקי אם נותר, ומדפיס `::warning::`. האשף מציג במקרה כזה הודעה ידידותית ואינו
קורס — סעיף 2 ב"מסלול הריצה" למעלה.

האשף עצמו **אינו רכיב במניפסט**: אין לו `ComponentSpec`, ושמו
(`Otzaria-Download-Assistant-windows.exe`) אינו נתפס בשום תבנית — הן פותחות ב-
`^otzaria-` באותיות קטנות, וההתאמה רגישה לרישיות, ולכן ה-`O` הגדול שבשם דוחה
אותן. גם בהערות השחרור המסייעים מסווגים בענף ייעודי,
`otzaria-download-assistant-*)`, שהוא **הראשון** ב-`case` — אחרת
`…-macos.zip`, `…-linux-*.tar.gz` ו-`…-windows.exe` היו נבלעים בתבניות של
מק, לינוקס וחלונות.

### פיצול דינמי של נכסים גדולים — לפי גודל בלבד

הכלל אחד בכל הארגון: נכס **מעל 1.9 GiB** (2,040,109,465 בתים) מתפרסם כ-
`<שם>.part-NNN` בחלקים של 1900 MiB ולצדם `<שם>.manifest.json` (גודל ו-sha256
לכל חלק ולשלם) — הצורה של `split_release_asset.sh`. נכס קטן ממנו נשאר קובץ אחד,
בית-בבית. מספר החלקים נגזר מהגודל ואינו קבוע. המרווח מתחת ל-2 GiB הוא בכוונה:
נכס שקרוב לגבול נכשל בהעלאה, והספרייה גדלה בכמה אחוזים בין גרסאות.

* **Windows / Linux / macOS FULL** — השלב "Split FULL packages that exceed
  GitHub's asset limit" מריץ `tool/release/split_oversized_assets.sh` על
  `release-files` עם תבניות החבילות המלאות. כשמשהו פוצל, הוא מצרף את
  `assemble_split_asset.sh`/`.ps1` להרכבה ידנית. אריזת Linux/macOS אינה נכשלת
  עוד על הגודל — הפיצול בשלב השחרור הוא שמטפל בו.
* **Android FULL** — המשימה `build_android_full` אוספת את ה-APK ואת חלקי חבילת
  הספרייה והאינדקס עם המניפסטים שלהם (`otzaria-library-parts` מ-Linux x86_64),
  ו-`tool/release/pack_android_full.sh` אורז אותם בלי דחיסה (`zip -0`; החלקים
  כבר zstd) ל-ZIP אחד, או מעל הסף לכרכי ZIP **עצמאיים**
  `otzaria-android-full-partN.zip` (first-fit לפי גודל, ה-APK בכרך הראשון,
  ה-README בכל כרך). כל קובץ שלם בכרך אחד — חלק של 1992294400 בתים נכנס בתקציב
  הכרך (2040109465 פחות 8 MiB), והכרך נשאר מתחת ל-2 GiB; קובץ גדול מהתקציב מפיל
  את האריזה. מחלצים את כולם לאותה תיקייה, ו"ייבוא מתיקיית קובצי הספרייה" באוצריא מזהה את
  החלקים ומאמת אותם לפי המניפסט.
* **מסד הספרייה מ-SeforimLibrary** — אותו כלל בצד SL. כל אריזות ה-FULL מורידות
  אותו דרך `tool/release/download_library_db.sh` (וב-Windows
  `download_full_installer_assets.ps1`): קובץ יחיד, או מניפסט וחלקים מאותו תג,
  שמחוברים ומאומתים לפני השימוש.

נגזרות לחוזה:

* לכל חבילה מלאה שתי תבניות נכס זרות זו לזו — הקובץ ותבנית ה-`split`. בדיוק אחת
  מתקיימת, ובלעדי זה הרכיב היה נעלם מהמניפסט ביום שהפיצול נדרש.
* הסיווג בהערות השחרור רגיש לסדר: החלקים ומניפסטי הפיצול נתפסים **לפני**
  `*windows-full*.exe`, `*linux-full*.tar.*` ו-`*macos-full*.tar.*`.

### מתקין FULL ל-ARM64

`otzaria-<ver>-windows_arm64-full.exe` נבנה בסוף `build_windows_arm64` מאותו
`otzaria_full.iss` עם `/DAppArch=arm64`, ונכסי הספרייה יורדים לשתי הארכיטקטורות
מ-`installer/download_full_installer_assets.ps1`. השלב **אינו חוסם שחרור**
(`continue-on-error` + `timeout-minutes`): כישלון מוציא גרסה בלי הנכס הזה ועם
אזהרה ב-"Organize release files". לולאת הפיצול מכסה אותו כמו את ה-x64, ובהערות
השחרור שלושת הענפים שלו (`.part-*`, `.manifest.json`, `.exe`) קודמים ל-
`*windows_arm64*.exe` — אחרת הוא היה מוצג כמתקין ה-ARM הרגיל. בדיקות:
`test/installer/installer_scripts_test.dart` ("מתקין FULL ל-Windows ARM64") ו-
`test/installer/release_packaging_test.dart` ("מתקין FULL ל-ARM64 בשחרור").

### המתקין הרגיל וחלקי הספרייה

`otzaria-<ver>-windows.exe` (x64) ו-`otzaria-<ver>-windows_arm64.exe` פורסים את
`library-full` כשהחלקים `otzaria-<ver>-library.tar.zst.part-NNN` יושבים לצדם, ואת
`library-index` כשגם `otzaria-<ver>-library-index.tar.zst.part-NNN` שם. הם **אינם
מורידים** אותם; בלעדיהם ההתקנה רגילה לגמרי, כולל העדכון השקט.

* **נכסים** — ב-`build_linux` (x86_64, אחרי `fetch_prebuilt_library_index.sh`)
  `pack_library_asset` אורז את `books/` ואת `index/` (עם `.otzaria_prebuilt_index`)
  לשני ארכיונים, כל אחד **תמיד בחלקים** (`split_release_asset.sh`, גם מתחת לסף:
  המתקין מזהה נכס לפי `.part-*`), ומעלה אותם כ-`otzaria-library-parts` ואת שני
  המניפסטים כ-`otzaria-library-manifests`. אינדקס SeforimLibrary
  (`otzaria-library-index.tar.zst`) אינו מקושר ישירות: שמו חסר גרסה, ולכן חלקים
  ישנים לצד מתקין חדש היו נכשלים באימות במקום להיות מושמטים, והוא חסר את הסמן.
  `library-full-indexed` (ספרייה ואינדקס בארכיון אחד) **הוסר**: שני הנכסים
  החדשים מכסים אותו, והשארתו הייתה מכפילה כ-3 GB בעמוד ה-release. מסייע 0.9.98
  שקורא את המניפסט החדש אינו נשבר — רכיב חסר פשוט אינו מוצע, `library-full` הוא
  `library` רגיל עם `installedBy`, ו-`library-index` הוא סוג לא מוכר שמוצע רק
  בבחירה האישית ונסגר עם הספרייה והמתקין.
* **בנייה** — ה-job `build_windows_installer` (אחרי `build_windows`,
  `build_windows_arm64` ו-`build_linux`) פורס את `otzaria-windows.zip` ואת
  `otzaria-windows_arm64.zip` לתיקיות הבנייה בלי `portable.marker`, מניח ב-
  `installer\` את `library.manifest.json`, `library_index.manifest.json`,
  `zstd.exe` ו-`7za.exe` (של x64, מ-`build_windows`), ומקמפל את `otzaria.iss` לשתי
  הארכיטקטורות (ISCC רק אורז, ולכן גם ARM64 נבנה על x64). ה-ISPP מגדיר
  `LibraryParts` רק כשמניפסט הספרייה קיים, ו-`LibraryIndexParts` רק כשגם מניפסט
  האינדקס קיים — בנייה מקומית וריצה ש-`build_linux` נכשל בה מקבלות מתקין בלי הקוד
  הזה. `build_windows` בונה את מתקין ה-FULL בלבד, ו-`build_windows_arm64` את ה-FULL
  של ARM64 ואת ה-ZIP.
* **ARM64** — אותם `zstd.exe`/`7za.exe` של x64: ל-`facebook/zstd` אין בינארי
  Windows ARM64, ו-Windows 11 על ARM מריץ x64 באמולציה (כמו מתקין ה-FULL של ARM64
  והעדכון המצומצם). Windows 10 על ARM מאמלץ רק x86, ולכן כשיש חלקים לצד המתקין
  והגרסה מתחת ל-10.0.22000 — הודעה ועצירה לפני ההתקנה; בלי חלקים המתקין ממשיך
  לרוץ שם כרגיל (אין `MinVersion`).
* **זיהוי** — ב-`NextButtonClick(wpReady)`, שנקרא גם בהתקנה שקטה. חיפוש
  `.part-*` של הספרייה שליד `{srcexe}` מפעיל אימות של כל החלקים, גם כאשר
  `part-000` חסר. בלי חלקי ספרייה יוצאים בלי חילוץ קבצים זמניים ובלי
  PowerShell; חלקים של גרסה אחרת מזוהים באותו אופן.
* **חלקים של גרסה אחרת** — שם החלקים כולל את הגרסה, ולכן הם אינם נפרסים. במקום
  להתעלם בשקט, המתקין מציג את שם הקובץ ושואל אם להתקין את התוכנה בלבד; בהתקנה
  שקטה התשובה היא "לא", וההתקנה נעצרת.
* **אינדקס בלי ספרייה** — מתעלמים ממנו, עם שורת לוג בלבד. המסייע מוריד אותו תמיד
  עם הספרייה (`dependsOn`), והמתקין אינו יכול לוודא שהוא מתאים לספרייה שכבר מותקנת;
  התוכנה בונה אינדקס בעצמה ממילא.
* **אימות** — כל מניפסט מוטמע נקרא ב-`read_split_manifest.ps1` ושם הארכיון מושווה
  לגרסת המתקין; `assemble_split_asset.ps1` מחבר את החלקים ל-`{tmp}` ומאמת SHA-256
  של כל חלק ושל הארכיון — קודם הספרייה, ואז האינדקס. חלק חסר או פגום באחד מהם
  עוצר את ההתקנה עם הודעה שמציעה להכין את התיקייה מחדש, או להעביר את המתקין כדי
  להתקין את התוכנה בלבד. בהתקנה שקטה ההודעות הן `SuppressibleMsgBox`, ולכן
  `/SUPPRESSMSGBOXES` אינו נתקע עליהן; באשף הן בדו-שיח המעוצב, והאימות רץ בעמוד
  "מכין את הספרייה" של שכבת התצוגה (ראה "מתקיני אוצריא בשכבת התצוגה").
* **פריסה** — ב-`ssPostInstall`, אחרי ש-`[Dirs]` נתנה למשתמשים הרשאה על תיקיית
  הנתונים: `zstd` ואז `7za` של כל ארכיון ל-staging ליד תיקיית הספרייה, בדיקת
  `seforim.db` (ו-`.otzaria_prebuilt_index` כשיש אינדקס), והחלפת `books` (ו-`index`
  הצמודה, כשיש אינדקס) רק אחרי חילוץ מלא. בלי אינדקס, `index` הקיימת אינה נוגעת —
  כמו במתקין ה-FULL. היעד כולל את `folderName`: רשומת תיקיית ה-DB נפרדת
  משמרת את `library_path.txt` לצורך הסרה; ברשומה ישנה מזוהה תת-תיקייה יחידה
  עם `seforim.db`, וכמה מועמדות עוצרות את ההתקנה לפני פריסה. במקרה כזה מעדכנים
  תחילה את התוכנה בלבד מתיקייה ללא קובצי ספרייה, ובוחרים בה את הספרייה הפעילה.
  גם נתיב יחסי, שורש כונן או שורש שיתוף נעצרים לפני פריסה, אפילו אם מכילים DB;
  יש לבחור תיקיית ספרייה מוחלטת בתוך הכונן או השיתוף. התקנת התוכנה בלבד אפשרית.
  רשומת DB חסרה או stale אינה גוברת על DB קיים בתת-תיקייה אחרת. בהיעדר ספרייה
  קיימת היעד הוא `GetDataDir\books`, ובמצב נייד `{app}\otzaria_data\books`.
  `index` מותקנת לפי שורש הספרייה המוגדר (או ProgramData לכל המשתמשים), עם
  `.otzaria_prebuilt_index`; `semantic-import` לפי ההורה של תיקיית ה-DB.
* **שטח דיסק** — בשיא: שני הארכיונים המורכבים ב-`{tmp}`, ה-tar שנפתח מאחד מהם,
  ואז ה-tar והספרייה ב-staging. כל ארכיון נמחק מיד אחרי `zstd` וה-tar אחרי `7za`.
  אין בדיקה מראש; כשל מוצג עם הסבר (`FriendlyErrorHint`).
* **כשל בפריסה** אינו מבטל את התקנת התוכנה (`Abort` אינו פועל ב-`ssPostInstall`):
  ההודעה אומרת שהתוכנה הותקנה והספרייה לא, והספרייה הקודמת נשארת במקומה. כשההודעה
  מושתקת (`/SUPPRESSMSGBOXES`) המתקין יוצא בקוד 9 (`GetCustomSetupExitCode`), ולא 0.
* **השקה שקטה** — רשומת `[Run]` רצה לפני `ssPostInstall`, ולכן כשהוכנה ספרייה
  `ShouldLaunchAppAfterSilentInstall` מחזיר False, ואוצריא נפתחת בסוף הפריסה.
* **גודל** — `zstd.exe` ו-`7za.exe` מוסיפים כ-1.1 MB דחוסים לכל מתקין (ארטיפקט הכלים
  ב-CI שוקל 1,176,819 בתים ב-ZIP).
* **עמוד הסיום של המסייע** — `outputNote` של `library-full` ("מתקין אוצריא שבתיקייה
  פורס את הספרייה מהחלקים שלצדו בזמן ההתקנה, בלי אינטרנט.") ושל `library-index`
  ("אינדקס החיפוש המוכן נפרס יחד עם הספרייה, ולכן התוכנה אינה בונה אותו אחרי
  ההתקנה.").

בדיקות: `test/installer/installer_scripts_test.dart`, הקבוצה "חלקי הספרייה
והאינדקס לצד המתקין הרגיל".

### הערות השחרור

החלקים של `library-full` ושל `library-index` עולים כנכסים ואינם מקושרים
(`*-library.tar.zst.part-*|*-library-index.tar.zst.part-*`): בפרק Windows יש
שורה אחת שמפנה למסייע ההורדה (בחירה אישית) — הספרייה, ולמחשב חלש גם האינדקס.

המסייעים מקושרים במקטע נפרד בסופן, "## כלי עזר": משפט הסבר אחד שאינו משתמע
לשתי פנים ("מסייע הורדה — כלי עזר להורדת אוצריא ולהכנת התקנה למחשב ללא אינטרנט.
זהו אינו קובץ ההתקנה עצמו"), ואחריו שורה לכל מערכת — "מסייע הורדה למחשב Windows",
"למק", "ללינוקס", "ללינוקס במחשב עם מעבד ARM" — בסדר הזה ולא בסדר האלפביתי של
`release-files`. מסייע שלא נבנה פשוט חסר מהרשימה.

### בדיקות החיווט

`test/installer/release_packaging_test.dart`, קבוצה "מסייע ההורדה ומניפסט
ה-release ב-workflow": ה-`.iss` נבנה עם ה-ISCC הקיים ולא נוספה התקנה שנייה,
הבנייה אינה פטאלית, הגנרטור רץ אחרי ארגון הקבצים וכותב ל-`release-files`, שם
נכס המניפסט נקרא מה-`.iss` עצמו ומושווה לשם שב-workflow, הפיצול מותנה
במגבלה ואינו מתקיים בגודל של היום, ענף המסייעים הוא הראשון ב-`case`, ו-"Stage
Download Assistant" מעתיק את ארבעת המסייעים עם אזהרה נפרדת לכל חסר ובלי כישלון.

## מסייע ההורדה ל-macOS — `tool/download_assistant/macos/`

**ההחלטות (החוזה):**

* **SwiftUI, macOS 12 ומעלה** — אותה רצפה של אוצריא (`MACOSX_DEPLOYMENT_TARGET = 12.0`).
  רשת: `URLSession` עם delegate (`didReceive data` בנתחים — לא `bytes(for:)`, שמתקדם
  בית-בית); hash: `CryptoKit.SHA256` מצטבר. אין תלות חיצונית. אמון TLS מ-Keychain
  של המערכת, ולכן תעודת נטפרי שהותקנה במערכת עובדת.
* **Universal Binary** (arm64 + x86_64) דרך SwiftPM על ה-runner של `build_macos`,
  חתימה **ad-hoc** (`codesign --sign -`) כמו אוצריא עצמה.
* **zip ולא DMG** (`ditto -c -k --keepParent`). מול Gatekeeper השניים שקולים — שניהם
  מסומנים quarantine ואינם חתומים ב-Developer ID, ולכן בפתיחה הראשונה נדרש "פתח
  בכל זאת" בהגדרות (ב-macOS 15 אין עוד מעקף בקליק ימני) — אותו מסלול שמשתמשי ה-DMG
  של אוצריא כבר מכירים. אבל DMG מריץ את המסייע מכרך לקריאה בלבד, ולכן "ליד המסייע"
  לעולם אינו אפשרי שם, והוא דורש `create-dmg`. zip נפתח בלחיצה כפולה ליד ההורדה.
* קבצים ש-`URLSession` כותב **אינם** מסומנים quarantine, ולכן ה-DMG שהוכן נפתח
  במחשב המנותק בלי אזהרת Gatekeeper של "הורד מהאינטרנט".

### המבנה

חבילת SwiftPM (`swift-tools-version:5.9`, מצב שפה Swift 5 — בדיקות ה-concurrency
המחמירות של Swift 6 היו מפילות את הבנייה על ה-runner) עם המטרות:

| מטרה | תפקיד |
|---|---|
| `AssistantCore` | כל הלוגיקה, בלי ממשק: פענוח המניפסט (דוחה `schemaVersion != 1`, רכיב בלי hash, מאגר מחוץ לארגון, חלקים שסכומם אינו הנכס), העתק נאמן של כל פונקציה ב-`download_assistant_selection.dart` (`Selection.swift`), בחירת התג, כתובות ובדיקת הפניות (`Endpoints.swift`), חותם המטמון, התוכנית, ההרכבה, מנוע ההורדה ומנצח הריצה |
| `AssistantUI` | הממשק (ספרייה): `AssistantModel` (`ObservableObject` ומכונת מצבים), העמודים, הרכיבים, הטקסטים (`Strings.swift`, עברית ואנגלית), החלון והתפריט, ו-`Scenarios.swift` — כל מסך במצב קבוע לצילום. ממשקי macOS 12 בלבד — בלי `NavigationStack` ובלי `@Observable` |
| `DownloadAssistant` | `main.swift`: ‏`NSApplication` עם חלון יחיד (בלי `WindowGroup`, שהיה פותח מסייע שני על אותו מטמון), ו-`BuildInfo.generated.swift` |
| `AssistantSnapshots` | מצלם כל מסך ל-PNG (ראו "צילומי מסך") |
| `AssistantCoreTests`, `AssistantUITests` | XCTest |

* **מנוע ההורדה** (`DownloadEngine`): תור delegate סדרתי אחד מחזיק את כל המצב.
  בקשת המשך מחשבת את ה-hash של החלק הקיים רק **אחרי** שהתקבל 206 תואם — ה-
  completion handler של התשובה נקרא אחרי שה-hash מהדיסק הסתיים, על תור צדדי, כך
  שהורדות אחרות אינן נעצרות. על 200 לא מחושב דבר מהדיסק. אם המשימה הסתיימה בזמן
  ה-hash (timeout), ההמשך מבוטל — ניסיון חוזר אולי כבר פתח את אותו קובץ.
* **קובץ בתהליך הורדה**: `<name>.<12 תווי sha>.download` ולא `<name>.download` —
  נכסים באותו שם בכמה גרסאות (`otzaria-macos-full.tar.zst`, `…part-000`) היו מחדשים
  קובץ חלקי זר ונכשלים באימות. חותם תקף עם hash אחר מהמניפסט — הקובץ נמחק בלי hash.
* **הרכבה**: ישר לתיקיית היעד, לקובץ עבודה באותה צורת שם. בהפעלה חוזרת גודל קובץ
  העבודה קובע כמה חלקים כבר נבלעו; הם אינם יורדים שוב, והשם מבטיח שאין ערבוב גרסאות
  ובסיום ה-SHA-256 של הקובץ המורכב נבדק מול המניפסט. קובץ פגום נמחק.
* **העתקה**: `FileManager.linkItem` (‏`link(2)`) ובכישלון (כונן אחר) העתקה בנתחים של
  4MB, עם התקדמות ועצירה בביטול; עותק חלקי נמחק.
* **מקום פנוי**: נבדק בכרך של המטמון (הורדות שעוד אינן בו) ובכרך היעד (מה שייכתב
  שם); באותו כרך קישור קשיח חינם והרכבה מוסיפה לכל היותר חלק אחד.
* **API במגבלת קצב** (403/429, נפוץ ב-IP משותף): עם תג מוטבע המניפסט יורד ישר מ-
  `…/releases/download/<tag>/otzaria-release-manifest.json` (ה-`+` כ-`%2B`), בלי
  בדיקת "latest גבוה יותר".
* **הודעות**: אותו ניסוח של המסייע ל-Windows (`installer/download_assistant.iss`);
  נתיבים ופקודות מוצגים משמאל לימין וניתנים לבחירה.

### הממשק — `Sources/AssistantUI/`

אותו עיצוב, אותו מסלול ואותו ניסוח של המסייע ל-Windows (הפרק "התצוגה" למעלה), בחלון
macOS אמיתי:

* **חלון.** 400×660 נקודות (התוכן 400×632 מתחת לשורת הכותרת), בגודל קבוע, בלי מסך
  מלא. שורת הכותרת של macOS נשארת עם הרמזורים, שקופה, בגוון שורת הכותרת של העיצוב
  (`#F3E6DA`), עם הקו `#E1D4C8` מתחתיה. הכותרת המרוכזת של המערכת מוסתרת
  (`titleVisibility = .hidden`; `window.title` נשאר בשביל VoiceOver), ובמקומה תווית
  בגופן רגיל כאביזר של שורת הכותרת — בעברית צמודה לימין, באנגלית אחרי הרמזורים, כמו
  ב-Windows. גרירה דרכה מזיזה את החלון (`mouseDownCanMoveWindow`). בהיר בלבד (`NSAppearance.aqua`), גם
  כשהמערכת במצב כהה. הצבעים והמידות ב-`Theme.swift` הם אלה של `assistant_art.isi`.
* **טקסט.** כל הטקסט מצויר בגופן המערכת (SF / SF Hebrew), כמו אוצריא ב-macOS — גם
  הכותרת של מסך הפתיחה, שב-Windows היא תמונה. מהעיצוב נלקחות רק תמונות: סמלי
  הכרטיסים (`ico_*`), תגי המצב (`badge_*`) ופריימי הספר (`book_*`).
* **שפה.** `UILanguage.detect`: עברית כששפת macOS המועדפת הראשונה עברית, אחרת
  אנגלית; `OTZARIA_ASSISTANT_LANG=he|en` גובר (לבדיקה). בעברית כל העמוד RTL; משפט
  שפותח במילה לטינית ("macOS — כמו המחשב הזה") מקבל RLM, ואחרי כל פסיק ברשימה לטינית
  בא RLM (`bidi`). גדלים ומהירויות — GB, MB, KB, MB/s, KB/s (`humanSize`, `humanSpeed`),
  בעברית עטופים ב-LRE…PDF. שמות הרכיבים וההסברים מגיעים מ-`nameEn`/`descriptionEn`/
  `outputNoteEn`, ובהיעדרם — העברית. משפטי הלוגיקה נשארים בעברית ב-`AssistantCore`
  (קבועים ב-`AssistantError` וב-`PreparationStatus`), ולכל אחד תרגום באותו מקום.
* **המסלול.** פתיחה מונפשת ← מתחבר ← "macOS — כמו המחשב הזה" / "סוג מחשב אחר" (עם
  שורת הגרסה) ← רשימת היעדים (רק לסוג אחר, בלי בחירה מראש) ← מה להוריד ← בחירה אישית
  ← לאן לשמור ← מוכנים להתחיל ← הורדה ← סיום. נקודות השלבים כמו `UiStepOf`. "המחשב
  הזה" = `macos` בלי ארכיטקטורה. בסיום, כשנוצר DMG יחיד במחשב הזה: "התקן עכשיו במחשב
  הזה" (פותח את ה-DMG — macOS מציג את חלון הגרירה ליישומים), "פתח את תיקיית ההתקנה"
  ו"סגור"; אחרת "פתח את תיקיית ההתקנה" ו"סגור". למחשב אחר — שורת "הצג את
  הקובץ/התיקייה שהוכנו" (מסומנת) ו"סיום".
* **תקלות.** בתוך החלון: תג, כותרת, הסבר, "פרטים טכניים" (טקסט שניתן לבחור), ו"נסה
  שוב" / "פתח את עמוד ההורדות" / "סגור". בטעינה — "אין חיבור לאינטרנט" כשהבקשה לא
  הגיעה לשרת (`AssistantError.offline`, לפי קוד ה-`URLError`). "עצור הורדה" שואל,
  ואז עמוד רגוע עם תג השהיה, "המשך" (אותה תוכנית ואותו מטמון) ו"סגור".
* **שאלות.** בחלון מעוצב בתוך המסייע, לא `NSAlert`: לא נבחר מחשב, לא נבחר רכיב,
  תיקייה שאי אפשר לכתוב אליה, מקום פנוי, עצירת ההורדה, הפסקת החיבור, ויציאה — הרמזור
  האדום או Cmd-Q בזמן חיבור או הורדה (`windowShouldClose`, `applicationShouldTerminate`).
* **מקלדת ו-VoiceOver.** כל פעולה היא `Button`: Return מפעיל את הפעולה הראשית, Esc —
  חזרה, ביטול או עצירה, ובדו-שיח את הכפתור הבטוח; חיצים מעבירים בחירה בכרטיסי רדיו.
  טבעת מוקד בצבע הראשי מצוירת סביב כפתור או כרטיס במוקד (ב-macOS 14 ומעלה בלי טבעת
  המערכת מעליה). כרטיס הוא אלמנט נגישות אחד (כותרת, תיאור, גודל) עם `isSelected`;
  מתחת לדו-שיח העמוד מושבת ומוסתר מ-VoiceOver.
* **פתיחה.** הזמנים של `assistant_art.isi`: דהייה של 250ms, 24 פריימים של 42ms, עלייה
  של 650ms מפריים 17, וחשיפת הכותרת ב-400ms. קליק מדלג לסוף; Reduce Motion או בלי
  תמונות — המצב הסופי מיד. בחזרה למסך הפתיחה היא אינה מתנגנת שוב.
* **התמונות.** `Art.swift` קורא מ-`Contents/Resources/Art` (או מ-`OTZARIA_ASSISTANT_ART`).
  בלעדיהן המסייע עובד: אריח בלי סמל ותג מצויר.

### בנייה

```bash
OTZARIA_ASSISTANT_RELEASE_TAG=0.10.3+143 bash tool/download_assistant/macos/build_app.sh [out-dir]
# -> <out-dir>/Otzaria-Download-Assistant-macos.zip   (ברירת מחדל: tool/download_assistant/macos/build)
cd tool/download_assistant/macos && swift test
```

`build_app.sh` בודק את התג מול `^[0-9A-Za-z.+_-]*$`, כותב אותו ל-
`Sources/DownloadAssistant/BuildInfo.generated.swift` ומחזיר את הקובץ לתג ריק ביציאה
(הגרסה שבמאגר היא של בנייה מקומית — latest בלבד). אחר כך `fetch_art.sh` מושך את
העיצוב הנעוץ ל-`build/art`: אותה נעיצה של Windows (`installer/assistant_art.pin.json`,
המקום היחיד שנוקב בגרסה), `curl` עם ניסיונות חוזרים, SHA-256 **לפני** הפריסה, בדיקת
`AA_ART_VERSION`, ופריסה של `ico_*_200`, `badge_*_200` ו-`book_*_250` (מוקטנים ב-`sips`
ל-440 פיקסלים — 220 נקודות ב-Retina) בלבד; חותמת `.pinned-sha256` מדלגת על משיכה
חוזרת. בלי העיצוב אין בנייה, כמו ב-Windows. אחר כך `swift build --product
DownloadAssistant` ל-arm64 ו-x86_64, בדיקת `lipo -archs`, `.app` עם
`CFBundleDevelopmentRegion=he`, `CFBundleLocalizations` עברית ואנגלית ו-`InfoPlist.strings`
לכל אחת (השם ב-Finder: "מסייע הורדה לאוצריא" / "Otzaria Download Assistant"),
`LSMinimumSystemVersion=12.0`, התמונות ב-`Contents/Resources/Art`, אייקון מ-
`assets/icon/iconnew.png` (`sips`+`iconutil`; כישלון בו קוסמטי), `codesign --sign -`
ו-`ditto`.

**ב-CI** — שלושה שלבים בסוף `build_macos`: `swift test`, הבנייה (רק כשהבדיקות עברו —
כלל בחירה שבור היה מוריד קבצים שגויים) והעלאת `otzaria-download-assistant-macos`
(רק כשהבנייה הצליחה). כולם `continue-on-error: true`. התג מחושב באותו כלל של שלב
המסייע ל-Windows. נבדק ב-`test/installer/download_assistant_macos_workflow_test.dart`.

### בדיקות (XCTest)

* `FixtureTests` — `release-manifest.json` מול `expected-selections.json`: הפלטפורמות,
  הארכיטקטורות, הפורמטים, ברירת המחדל מ-os-release, והרכיבים המוצעים, ההצעות, קובצי
  הפלט ותת-התיקייה לכל אחד מעשרת היעדים — וגם שהתוכנית שהמסייע מבצע מפיקה בדיוק את
  אותם קבצים. `testLargeFullVariant` עושה את אותו הדבר מול זוג ה-`-large-full`, ו-
  `testLibraryBringsItsInstaller` בודק שספרייה שנבחרה לבדה מגיעה עם המתקין שלה. דוגמאות ה-os-release מועתקות מ-`generate_fixtures.dart`, והבדיקה נכשלת
  כשהמפתחות נפרדים.
* המשך מול 200/206 (כולל כתיבת גוף ה-200 על קובץ חלקי ישן), כללי Content-Range
  וניסיונות חוזרים, חותם המטמון ומצביו, הרכבה (שרשור, מחיקת חלקים, המשך אחרי קטיעה,
  חלק קצר), בדיקת המארחים בהפניות, בחירת התג (כולל `0.10.3+143`), גדלים, מהירות
  ומיקום ברירת המחדל (App Translocation).
* `AssistantUITests` — כל מפתח טקסט קיים בעברית ובאנגלית עם אותם ‎%1‎/‎%2‎, לכל משפט
  של הלוגיקה יש תרגום, זיהוי השפה, המסלול של "המחשב הזה" (חמישה שלבים, "בסיסית"
  מסומנת, חזרה עד מסך הפתיחה), רשימת היעדים האחרים (בלי macOS, בלי בחירה מראש, ו"המשך"
  בלי בחירה מבקש לבחור), בחירה אישית ריקה, ותוכנית באנגלית (שמות ותת-תיקייה).

### צילומי מסך

`AssistantSnapshots` בונה כל מסך מ-`SnapshotScenarios` (דרך הניווט האמיתי של המודל, על
`fixtures/release-manifest.json` שהגדלים בו מוכפלים ב-MiB), פותח אותו בחלון האמיתי
ושומר את כל המסגרת — כולל שורת הכותרת — ב-2x, בעברית ובאנגלית; `--hero` מוסיף את
פריימי הפתיחה ב-1x. ה-workflow `.github/workflows/macos-assistant-screenshots.yml`
(הפעלה ידנית) מריץ `swift test`, מושך את העיצוב, מצלם, בונה את ה-`.app` ומעלה את
הארטיפקטים `macos-assistant-screenshots` ו-`macos-assistant-app`.

```bash
cd tool/download_assistant/macos && bash fetch_art.sh build/art
OTZARIA_ASSISTANT_ART="$PWD/build/art" swift run AssistantSnapshots ../fixtures/release-manifest.json /tmp/shots --hero
```

## מסייע ההורדה ל-Linux — `tool/download_assistant/linux/`

**ההחלטות (החוזה):**

* **C + GTK3.** התלויות של חבילות אוצריא עצמן (`linux/packaging/deb/make_config.yaml`)
  הן `libgtk-3-0`, `libsecret-1-0`, `libharfbuzz-icu0` בלבד. GTK3 מושך GLib/GIO,
  Pango ו-Cairo, וזה כל מה שהמסייע מקושר אליו. Python + PyGObject אינו מובטח
  (אינו בתלויות, ואינו מותקן במחשבים רבים); Vala דורש מהדר שני ב-CI בלי רווח
  בזמן ריצה.
* **HTTPS דרך GIO** (`GSocketClient` עם `g_socket_client_set_tls`), וקוד HTTP/1.1
  מינימלי משלנו (GET, `Content-Length`, `chunked`, הפניות, `Range`); hash דרך
  `GChecksum` (SHA-256, חלק מ-GLib). libcurl ו-libsoup **אינם** בתלויות של
  אוצריא — אוצריא אורזת libsoup משלה בתוך ה-WPE runtime, ומחשב שמכין התקנה אינו
  בהכרח מחשב שאוצריא מותקנת בו. ה-TLS של GIO מגיע מהמודול `glib-networking`,
  שאינו קישור אלא מודול זמן ריצה — ה-WebView של אוצריא עצמה נשען עליו
  (ה-libsoup הארוז טוען את ה-GIO של המארח; ראה רשימת ההחרגה של `libgio` ב-workflow).
  בהפעלה המסייע בודק `g_tls_backend_supports_tls(g_tls_backend_get_default())`,
  ואם אין — "בואו נתחיל" מוביל לעמוד בתוך החלון עם שם החבילה (`glib-networking`)
  והפקודה להתקנתה, במקום קריסה. אמון TLS
  ממאגר התעודות של המערכת, כולל תעודת נטפרי שהותקנה בה.
* **נבנה ב-`build_linux`, במטריצה `target == 'raw'`** — בקונטיינר `debian:bookworm-slim`
  שכבר מתקין `libgtk-3-dev` ו-`build-essential`, פעם לכל ארכיטקטורה (x64 על
  `ubuntu-latest`, ARM64 על `ubuntu-24.04-arm`). רצפת glibc 2.36 זהה לזו של אוצריא.
  מקושר דינמית ל-GTK3 בלבד (נבדק ב-`ldd`/`readelf -d` ב-CI).
* **`tar.gz` ולא ELF גולמי ולא AppImage.** דפדפן מוחק את סיבית ההרצה מקובץ שירד,
  ו-tar שומר אותה; פריסה היא לחיצה כפולה בכל מנהל קבצים. AppImage דורש FUSE 2,
  שאינו מותקן כברירת מחדל מ-Ubuntu 22.04. הארכיון מכיל תיקייה
  `Otzaria-Download-Assistant/` ובה קובץ ההרצה `Otzaria-Download-Assistant`.

### הקבצים

| קובץ | תפקיד |
|---|---|
| `json.c` | קורא JSON משלנו: UTF-8 מאומת, `\uXXXX` כולל זוגות surrogate (שמות הרכיבים בעברית), מספרים שלמים של 64 סיביות, תקרת עומק |
| `manifest.c` | המניפסט ואימותו — גרסת סכמה 1 בלבד; לכל נכס וחלק גודל ו-sha256; מאגר, תג ושם בטוחים; `dependsOn` קיים |
| `selection.c` | העתקה אחד-לאחד של `download_assistant_selection.dart` |
| `release.c` | בחירת התג (מוטבע מול `/releases/latest`) וטעינת המניפסט |
| `http.c` | HTTP/1.1 מעל `GSocketClient` עם TLS: הפניות (עד 5, בדיקת מארח בכל קפיצה), `Range`, `Content-Length`/`chunked`, timeout של 30 שניות לשקע, `GCancellable` |
| `download.c` | המטמון, החותם, ההורדה המקבילית, הניסיונות החוזרים והפלט |
| `assemble.c` | קישור קשיח או העתקה ליעד, ושרשור חלקים עם בדיקת בתים |
| `paths.c` | מטמון, תיקיית בסיס, `uname`, `os-release`, "הצג" ב-D-Bus |
| `texts.c` | כל טקסט גלוי, בעברית ובאנגלית (טבלת `OTZ_STRING_KEYS`), זיהוי השפה, גדלים/מהירות/זמן, ועטיפת כיווניות |
| `widgets.c` | התמה הבהירה (CSS), העיצוב המוטמע, והפקדים המצוירים: כרטיסים, כפתורים, נקודות, פס, תגים, סיכום, דו-שיח |
| `ui.c`, `main.c` | מכונת המצבים והעמודים, ההורדה מתוך הממשק, דו-שיח בתוך החלון, ו-`--dev-screenshot` |
| `fetch_art.sh` | מושך את העיצוב הנעוץ ל-`build/art` (ראו "ממשק") |

```bash
cd tool/download_assistant/linux
make                 # build/Otzaria-Download-Assistant (מושך את העיצוב פעם אחת)
make test            # מול שני זוגות ה-fixtures, JSON, HTTP, חותם, הרכבה, טקסטים
make check-needed    # נכשל על כל NEEDED מחוץ ל-GTK/GLib/GIO/Pango/Cairo/GDK/libc
make test-asan       # אותן בדיקות תחת AddressSanitizer/UBSan
make dist DIST_ARCH=x64
```

התג נכתב ל-`build/build_info.h` על ידי `gen_build_info.sh` מ-`OTZARIA_ASSISTANT_RELEASE_TAG`
בלבד, אחרי בדיקה מול `^[0-9A-Za-z.+_-]*$` (נבדק גם ב-`make test`: `0.10.3+143` עובר
שלם, מרכאה נדחית). הקישור ב-`-Wl,--as-needed`, ולכן harfbuzz, atk ו-zlib שמופיעים
ב-`pkg-config --libs gtk+-3.0` אינם נכנסים ל-NEEDED. בפועל: `libgtk-3`, `libgdk-3`,
`libpangocairo-1.0`, `libpango-1.0`, `libcairo`, `libgio-2.0`, `libgobject-2.0`,
`libglib-2.0`, `libm`, `libc`. השמות והתיאורים הנגישים נקבעים במאפייני `AtkObject`
דרך `g_object_set`, כך ש-libatk אינו נכנס.

### ההורדה

* עד 3 threads, כל אחד לקובץ אחר; חלקי נכס מפוצל הם קבצים נפרדים בתור.
* **קבצי ביניים קשורים לגרסה**: `<name>.<12 תווי sha256>.download` במטמון ו-
  `<name>.<12 תווי sha256>.partial` בתיקיית היעד. שמות נכסים אינם נושאים גרסה
  (`otzaria-linux-full.tar.zst`), ובלי זה שארית של גרסה קודמת הייתה ממשיכה
  כאילו היא הקובץ הנוכחי — ומוכרזת תקינה. שארית של גרסה אחרת נמחקת.
* כל בית נכתב ל-`.download` ונכנס ל-`GChecksum` באותה לולאה. ב-206 תואם
  ה-hash של החלק הקיים נקרא מהדיסק פעם אחת; ב-200 הקובץ מקוצץ ואותו גוף נכתב
  מבית 0; 206 אחר או 416 — הקובץ נמחק ומבקשים שוב בלי `Range`. ההכרעה ב-
  `otz_classify_range_reply`, והיא שנבדקת בבדיקות היחידה. המשך שהסתיים ב-hash
  שגוי יורד פעם אחת נוספת מבית 0. `.download` שכבר בגודל המלא עובר hash פעם אחת
  ומקודם אם הוא תקין, בלי בקשה.
* ניסיון חוזר: שגיאת רשת, ניתוק באמצע הגוף ו-5xx בלבד, אחרי 2/5/10 שניות. שגיאת
  TLS, 4xx, הפניה אסורה או hash שגוי — עצירה מיידית.
* קובץ שנכשל מבטל את שאר ה-threads דרך `GCancellable` פנימי; סוג הכישלון שמוצג
  הוא של הכישלון הראשון. "ההורדה הופסקה" מוצג רק כשהמשתמש ביטל.
* חלק נמחק מהמטמון (יחד עם החותם שלו) רק אחרי שהוספתו ל-`.partial` הושלמה, ולכן
  בהפעלה חוזרת גודל ה-`.partial` מזהה כמה חלקים כבר נבלעו — הם אינם יורדים
  שוב, והקובץ מקוצץ לגבול החלק האחרון.
  לפני פרסום הקובץ המורכב נבדק ה-SHA-256 שלו; בכשל קובץ העבודה נמחק.
* **מקום פנוי** נבדק בשתי מערכות הקבצים: המטמון (מה שעוד יורד) והיעד (קבצים
  מורכבים, והעתקות כשאין קישור קשיח). על אותה מערכת קבצים הסכום נבדק מול הפנוי,
  וקישור קשיח אינו עולה דבר.
* **כשל ב-API** (כולל 403/429 וניתוקי רשת): אם
  יש תג מוטבע, המניפסט נטען ישירות מ-
  `https://github.com/Otzaria/otzaria/releases/download/<tag>/otzaria-release-manifest.json`
  (`+` מקודד), ובדיקת "האם יש גרסה חדשה יותר" מדולגת עם שורת לוג. בלי תג מוטבע
  — הודעת השגיאה הרגילה.

### ממשק

אותו עיצוב, אותו מסלול ואותו ניסוח של המסייע ל-Windows (הפרק "התצוגה" למעלה) ושל
המסייע ל-macOS, בחלון GTK3:

* **חלון.** 400×660 בגודל קבוע: שורת כותרת של GTK (`GtkHeaderBar`, CSD) בגובה 32 בגוון
  `#F3E6DA` עם הקו `#E1D4C8`, ותוכן 400×628. כפתורי החלון הם של GTK, לפי
  `gtk-decoration-layout` של המערכת. כותרת החלון היא תווית בגופן **רגיל** ב-`pack_start`
  — בעברית מימין והכפתורים משמאל, באנגלית להפך. `gtk_window_set_title` נקרא **לפני**
  `gtk_window_set_titlebar`, אחרת GTK מעתיק את השם לכותרת מרוכזת ומודגשת.
* **בהיר בלבד.** `GTK_THEME` נמחק לפני האתחול, `gtk-theme-name=Adwaita` ו-
  `gtk-application-prefer-dark-theme=FALSE`, ו-CSS בעדיפות `USER + 1` מאפס
  (`all: unset`) כל צומת בתוך `window.otz` ומגדיר מחדש רק את מה שהמסייע מצייר. רקעים,
  כרטיסים, כפתורים, נקודות, פס ההתקדמות, הסימונים וטבעת המוקד מצוירים ב-cairo
  (`widgets.c`); הצבעים והמידות הם של `assistant_art.isi`.
* **טקסט.** כל הטקסט ב-Pango בגופן הממשק של המערכת (`gtk-font-name`), כולל הכותרת של
  מסך הפתיחה. מהעיצוב נלקחות רק תמונות: `ico_*_200`, `badge_*_200`, `logo_200` (סמל
  החלון) ו-`book_*_250`. `fetch_art.sh` מושך אותן מאותה נעיצה של Windows
  (`installer/assistant_art.pin.json`), מאמת SHA-256 **לפני** הפריסה ואת `AA_ART_VERSION`,
  וכותב חותמת `.pinned-sha256`; ה-Makefile מטמיע אותן ב-GResource
  (`glib-compile-resources --generate-source`), כך שהארכיון נשאר קובץ הרצה אחד. בלי
  התמונות המסייע עובד: אריח בלי סמל ותג מצויר. כל תמונה נדגמת מחדש פעם אחת לקנה המידה של
  המסך (`CAIRO_FILTER_BEST`); פריימי הספר — ב-thread לפני שהפתיחה מתחילה.
* **שפה.** עברית כששפת הממשק (`g_get_language_names`: `LANGUAGE`, `LC_ALL`,
  `LC_MESSAGES`, `LANG`) עברית, אחרת אנגלית; `OTZARIA_ASSISTANT_LANG=he|en` גובר. בעברית
  `gtk_widget_set_default_direction(RTL)`, וכל שורה נפתחת ב-RLM (`otz_bidi`), עם RLM אחרי
  כל פסיק ברשימה לטינית. Pango קובע כיוון לכל שורה לפי התו החזק הראשון, ובלי זה "Linux —
  כמו המחשב הזה" היה מיושר לשמאל. גדלים ומהירויות — GB, MB, KB, MB/s, KB/s עם רווח קשיח,
  בעברית עטופים ב-U+2066…U+2069. נתיב ארוך מוצג בשתי שורות — התיקייה שמעליו ושמה —
  ולא נחתך באמצע: שם עברי חתוך בתוך נתיב LTR נקרא מבולבל. שמות הרכיבים וההסברים מגיעים
  מ-`nameEn`/`descriptionEn`/`outputNoteEn`; משפטי הליבה נשארים בעברית ומתורגמים
  ב-`otz_tr_message`.
* **המסלול.** פתיחה מונפשת ← מתחבר ← "Linux — כמו המחשב הזה" / "סוג מחשב אחר" (עם שורת
  הגרסה) ← רשימת היעדים (בלי בחירה מראש) ← מה להוריד ← בחירה אישית ← לאן לשמור ←
  מוכנים להתחיל ← הורדה ← סיום. בסיום במחשב הזה: "פתח את תיקיית ההתקנה" ו"סגור"; למחשב
  אחר — שורת "הצג את הקובץ/התיקייה שהוכנו" (מסומנת) ו"סיום". מקום פנוי נבדק לפני ההתחלה.
* **תקלות ושאלות.** בתוך החלון: "אין חיבור לאינטרנט" כשהבקשה לא הגיעה לשרת
  (`otz_error_is_offline`), תקלה עם "פרטים טכניים", עצירה רגועה עם "המשך" (אותו תג, אותה
  בחירה ואותו מטמון), ו-glib-networking חסר (בדיקת ה-TLS עברה מדו-שיח לפני החלון לעמוד
  בתוכו). כל שאלה היא כרטיס מעוצב מעל הצללה של 13% — יציאה בזמן חיבור או הורדה,
  עצירה, הפסקת חיבור, מקום פנוי, לא נבחר מחשב/רכיב, תיקייה שאי אפשר לכתוב אליה.
  ביציאה בזמן הורדה החלון נסגר רק אחרי שה-threads הפסיקו לכתוב.
* **מקלדת ונגישות.** כרטיסי בחירה הם `GtkRadioButton`/`GtkCheckButton` אמיתיים (תפקיד,
  מצב מסומן, Tab נכנס לקבוצה ויוצא ממנה, חיצים מעבירים בחירה, רווח מסמן), עם שם ותיאור
  נגישים (`otz_accessible`); ברשימת היעדים רדיו נסתר עומד על "אין בחירה". Return מפעיל
  את הפעולה הראשית אלא אם כפתור במוקד, Esc — חזרה, ביטול או עצירה, ובדו-שיח את הכפתור
  הבטוח. טבעת מוקד בצבע הראשי מצוירת בתוך 4 פיקסלים ששמורים סביב כל פקד, ומופיעה רק
  בניווט מקלדת (`gtk_widget_has_visible_focus`).
* **פתיחה.** הזמנים של `assistant_art.isi` (דהייה 250ms, 24 פריימים של 42ms, עלייה של
  650ms מפריים 17, כותרת ב-400ms). קליק מדלג לסוף; `gtk-enable-animations=FALSE` או בלי
  תמונות — המצב הסופי מיד.

### דגלים

`--self-test` פותח את החלון לחצי שנייה ויוצא (ב-CI תחת `xvfb-run`). דגלי `--dev-*`
מיועדים לפיתוח בלבד ואינם פעילים בלי שמעבירים אותם במפורש: `--dev-owner` (ארגון
אחר במקום Otzaria — לבדיקה מול fork), `--dev-manifest` (מניפסט מקובץ מקומי),
`--dev-auto-preset`/`--dev-platform`/`--dev-output` (מעבר אוטומטי על העמודים,
הדפסת דוח ויציאה), ו-`--dev-screenshot <dir>` (ראו "צילומי מסך").

### צילומי מסך

`--dev-screenshot <dir> --dev-manifest <manifest>` בונה כל מסך דרך הניווט האמיתי, על
מניפסט שהגדלים בו מוכפלים ב-MiB, ומצייר את החלון כולו (כולל שורת הכותרת) ב-
`gtk_widget_draw` ל-PNG — 26 מסכים בעברית ובאנגלית, ופריימי הפתיחה ב-`hero_he`/`hero_en`.
ה-workflow `.github/workflows/linux-assistant-screenshots.yml` (הפעלה ידנית) בונה, מריץ
`make test`, `make check-needed` ו-`--self-test`, מצלם תחת `xvfb-run` עם `GDK_SCALE=2`
ו-Noto Sans, נכשל על כל אזהרת GTK, ומעלה ארכיון `linux-assistant-screenshots`. job שני
בונה ובודק בקונטיינר `debian:bookworm-slim` של `build_linux`.

```bash
cd tool/download_assistant/linux && make
GDK_SCALE=2 xvfb-run -a ./build/Otzaria-Download-Assistant \
  --dev-manifest ../fixtures/release-manifest.json --dev-screenshot /tmp/shots
```

### נמדד (WSL, הרשת המסוננת, release של ה-fork `0.10.3+143`)

| תרחיש | תוצאה |
|---|---|
| קובץ אחד, 42MB | ‎3.7MB/s‎; ‏hashed = downloaded = 42,127,056 |
| אותו קובץ שוב | 0 בתים ירדו, 0 עברו hash (החותם) |
| המשך מ-10MB עם `Range` | תשובה 200 — נכתבה מבית 0 בבקשה אחת; sha256 תקין |
| 3 קבצים (134MB) במקביל ורביעי מהמטמון; נכס מפוצל אחד הורכב | ‎6.6MB/s‎ במצטבר מול ‎3.7MB/s‎ לקובץ בודד; hashed = downloaded; החלקים נמחקו מהמטמון, הקבצים הבודדים קושרו (link count 3) |

## רישוי — WebView2

WebView2 Runtime **מותר** להיות מוטמע (embedded) בתוך מתקין שנבנה אצלנו
ב-CI, כפי שקורה היום. **אסור** לפרסם אותו כנכס עצמאי ב-release שכלי צד
שלישי מוריד ממנו: סעיף 2(c)(iii) ברישיון WebView2 של Microsoft אוסר להעמיד
אתר הורדה של הרכיב לצדדים שלישיים.

לכן האשף אינו כולל רכיב WebView2 במניפסט. אם נדרשת התקנה במחשב מנותק, האשף
מפנה את המשתמש להוריד את ה-Evergreen Standalone Installer מהאתר של Microsoft
בעצמו, או מסתמך על ההטמעה שכבר קיימת במתקין.

## העדכון המצומצם (דיפרנציאלי)

עדכון מתוך התוכנה מוריד היום את המתקין המלא (‎39MB‎). העדכון המצומצם מוריד
במקומו חבילה של כ-‎8MB‎ ומחליף את קובצי ההתקנה בעצמו. **הוא אופטימיזציה
בלבד**: כל כשל בו — ולו הקטן ביותר — מחזיר את המשתמש למסלול המתקין המלא
כפי שהוא פועל היום, בלי שינוי בהתנהגותו.

### שתי חבילות לכל מעבר גרסה

`tool/release/generate_update_package.dart` מפיק בכל הרצה **שתי** חבילות
לאותו מעבר ולאותה ארכיטקטורה:

| חבילה | שם הנכס | מה יש בה | נמדד |
|---|---|---|---|
| patch | `otzaria-update-windows-<arch>-<from>-to-<to>.zip` | `--patch-from` לכל קובץ שהשתלם, קובץ דחוס מלא לשאר | ‎8.2MB‎ |
| קבצים מלאים | אותו שם עם סיומת `-files.zip` | **כל** קובץ שהשתנה או נוסף, דחוס במלואו | ‎16.7MB‎ |

מניפסט חבילת ה-patch נושא `variant: "patch"` ואת `fallbackAssetName` של
החבילה השנייה, כך שהלקוח אינו מרכיב את השם בעצמו. מניפסט החבילה המלאה נושא
`variant: "full"`, ואימות המניפסט דוחה בה כל ערך שאינו `method: "full"`.

### הנסיגה היא פר-קובץ, לא פר-עדכון

`patch` נשען על כך שהקובץ המקומי זהה-בית לקובץ שממנו נבנה. אנטי-וירוס
שהסיר חתימה, התקנה מתוקנת ידנית או קובץ שנפגם שוברים את ההנחה הזאת —
**לקובץ אחד**. לכן ערך כזה אינו מפיל את העדכון:

1. `planFor` מסמן קובץ מקומי שאינו הבסיס ואינו התוצאה כ-`fromFallbackPackage`.
2. `stage` כותב כל ערך ומאמת אותו **מיד** מול ה-hash שבמניפסט. כשל שניתן
   להשלמה (payload פגום, patch שנכשל, תוצאה שאינה תואמת) מוחק את הקובץ
   החלקי ודוחה גם אותו לנסיגה. כשל סביבה (zstd חסר, דיסק מלא) אינו נדחה —
   הורדה נוספת רק הייתה נכשלת גם היא.
3. רק אם נותר ערך דחוי אחד לפחות, **ורק אז**, נקרא `FallbackPackageResolver`
   ומוריד את חבילת הקבצים המלאים. עדכון שכל ה-patch שלו הוחל אינו מוריד
   אותה כלל.
4. החבילה המלאה נבדקת שהיא של אותו מעבר בדיוק (פלטפורמה, ארכיטקטורה, שני
   התגים) ושיש בה עותק עם אותו `newSha256`. אין נסיגה שנייה: כשל כאן הוא
   `fallbackUnavailable`, וממנו חוזרים למתקין המלא.

בכל אחד מהמסלולים האלה ההתקנה החיה **אינה נוגעת**: הכול נבנה ב-staging,
נסרק פעם נוספת במלואו, ורק אז נכתבת תוכנית ההחלפה.

### zstd — נארז לצד התוכנה

פענוח החבילה והחלת ה-patch דורשים את ה-CLI של zstd. הוא **אינו** מורד אצל
המשתמש ואינו מבוקש מה-PATH:

* ב-CI, השלב "Stage zstd for small updates (x64)" מעתיק את `installer\zstd.exe`
  — **הבינארי שכבר ירד עבור המתקין המלא**, לא הורדה שנייה — אל
  `build\windows\x64\runner\Release\`. מכאן הוא נכנס למתקין (`otzaria.iss`
  אורז `Release\*`), לארכיון הנייד ולמניפסט קובצי ההתקנה **בלי שינוי בשום
  סקריפט**. אותו מנגנון בדיוק של `otzaria_updater.exe`.
* ה-ZIP נארז לפני שה-zstd הוכן, ולכן השלב מוסיף אותו אליו ב-
  `Compress-Archive -Update`: המניפסט נגזר מתיקיית הבנייה, והשניים חייבים
  לתאר את אותה קבוצת קבצים, אחרת בניית החבילה מהשחרור הזה תיכשל בעתיד.
* `ZstdRunner.bundled()` (ברירת המחדל של המנוע) מחפש את `zstd.exe` ליד
  `Platform.resolvedExecutable` בלבד. אם אינו שם — `isAvailable` הוא `false`
  לפני שנוצר תהליך כלשהו, והמסלול מדווח שאינו זמין.
* **ARM64**: ל-`facebook/zstd` אין בינארי Windows ARM64, אבל Windows on ARM
  מריץ x64 באמולציה — ולכן השלב "Stage zstd for small updates (ARM64)" מוריד
  את **אותו** `zstd-*-win64.zip` ומעתיק את `zstd.exe` ל-
  `build\windows\arm64\runner\Release\`. הוא פורס כמה מגה-בתים בעדכון, והאטת
  האמולציה חסרת משמעות. השלב רץ **לפני** האריזה, ולכן ה-ZIP, המתקין ומניפסט
  קובצי ההתקנה מתארים כולם את אותה קבוצת קבצים. הורדה נפרדת ולא העתקה מה-job
  של x64: ה-job של ARM64 אינו תלוי בו, ותלות כזו הייתה מטרילה את שתי בניות
  Windows זו אחר זו. נאכף ב-`test/release/update_packages_workflow_test.dart`.
* **השחרור הראשון**: המשתמש מגיע מגרסה שאין בה zstd, ולכן עדכון **אליה**
  עדיין רץ במתקין המלא. מהשחרור שאחריו והלאה המסלול פעיל.

### מסלול המשתמש

`lib/update/my_update_widget.dart` מנסה את המסלול המצומצם **לפני** המסלול
הקיים, ו-`tryPrepareDifferentialUpdate` בולע כל כשל ומחזיר `null` — ומשם
הקוד ממשיך בדיוק לזרימת המתקין המלא, ללא שינוי בה.

המסלול נדרס מראש כשאחד מאלה אינו מתקיים (`differentialUpdateSupported`):
Windows, תיקיית ההתקנה **ברת-כתיבה** (התקנת מנהל נשארת על המתקין, שמסליק
את עצמו ב-runas), zstd ארוז, ו-`otzaria_updater.exe` ארוז.

1. איתור `otzaria-update-windows-<arch>-<installed>-to-<new>.zip` ב-release
   של הגרסה החדשה ב-`Otzaria/otzaria`. שם שאינו קיים = אין מסלול, בלי ניחוש.
   הארכיטקטורה היא זו של **התהליך** (`installedWindowsArchitecture`): בנייית
   x64 באמולציה על מחשב ARM היא עדיין התקנת x64.
2. הורדה ← אימות מניפסט ← בנייה ב-staging ← אימות כל קובץ ← סריקה כוללת.
3. ההכנה שקטה — בלי הודעה על גודל או על המסלול שנבחר.
4. הסטטוס עובר ל-`readyToInstall` ("העדכון מוכן"), ולחיצה פותחת
   `showTwoActionsDialog`: "לא עכשיו" / "סגור והתקן". האישור סוגר גם חלונות
   משניים (`MultiWindowService.closePeers`); חלון שסירב לסגירה מציג
   "סגור את החלונות שנותרו", והעדכון מושלם כשהתהליך יוצא.
5. נכתבת תוכנית ההחלפה, ו-`otzaria_updater.exe` משוגר דרך **אותו**
   `launchWindowsDetachedProcess` של `windows_installer_io.dart`
   (`CREATE_BREAKAWAY_FROM_JOB` — בלעדיו ה-Job Object של אוצריא היה הורג
   אותו ביציאתה). הוא קיבל פרמטר `arguments`; אין משגר שני.
6. אוצריא נסגרת, המעדכן ממתין ל-pid שלה, מחליף, ומפעיל מחדש.

כל הטקסטים יושבים ב-`lib/core/messages/library_messages.dart`
(`smallUpdateDialog*`, `smallUpdateAwaitingClose*`, `smallUpdateGaveUp`) — אין
ליטרל בנקודת הקריאה.

**כשחלון מסרב להיסגר.** המעדכן ממתין `waitTimeout` (2 דקות) ומוותר **לפני**
שנגע בדבר: הוא כותב `updater-gave-up` לצד התוכנית ואינו מפעיל את אוצריא
(היא עדיין רצה). החלון הראשי, שמציג "סגור את החלונות שנותרו", בודק את הסימן
(`watchForUpdaterGiveUp`), חוזר ל-"מוכן להתקנה" עם אותו staging ומודיע
`smallUpdateGaveUp`. שיגור חוזר כותב תוכנית חדשה ומוחק סימן ישן.

### ההחלפה — אף רגע בלי קובץ, ושחזור שאינו תלוי באוצריא

המעדכן (`tool/updater/updater_swap.dart`) נהרג לפעמים באמצע — כיבוי, קריסה,
אנטי-וירוס. שני כללים מבטיחים שההתקנה תסתיים בגרסה אחת שלמה:

* **הנתיב לעולם אינו ריק.** לכל קובץ: הישן **מועתק** לגיבוי, החדש מועתק
  לצדו (`<file>.otzaria-incoming`, אותו כונן), ו-`rename` אחד מחליף ביניהם.
  ב-Windows `File.rename` הוא `MoveFileEx` עם `REPLACE_EXISTING`: ניסוי של
  3000 החלפות מול בודק מקביל (33,772 בדיקות קיום) לא מצא אף רגע שבו היעד
  חסר; החלפה שנכשלה (קובץ פתוח) משאירה את הישן שלם. ה-staging נשאר מלא,
  ולכן אפשר תמיד להשלים קדימה. ה-exe בשורש מוחלף אחרון, וההסרות אחריו.
* **השחזור אינו צריך את אוצריא.** תערובת גרסאות (DLL חדש ו-exe ישן) עלולה
  לקרוס לפני `main()`, ולכן השחזור מ-`_runDeferredSwapRecovery` לבדו אינו
  רשת ביטחון. לפני השינוי הראשון המעדכן רושם `HKCU\…\RunOnce`
  (`!OtzariaUpdateRecovery`) שמריץ את **העותק שב-temp** — זה שבהתקנה עשוי
  להיות באמצע ההחלפה — עם `--recover`. ה-`!` משאיר את הערך עד שהפקודה
  הסתיימה. כשל ברישום מבטל את ההחלפה לפני כל שינוי; הערך נמחק בכל סיום
  שאינו `corrupted`.

השחזור (`recoverInterruptedSwap`) גוזר את המצב מהדיסק בלבד, וכל צעד בו ניתן
להרצה חוזרת: קדימה כשכל קובץ מותקן או זמין ב-staging, אחרת אחורה — ורק
לקבצים שכבר השתנו, כי גיבוי שנקטע יושב תמיד לצד יעד שלם. קובץ מוחזק בידי
תהליך חי (אוצריא שעלתה לפני ה-RunOnce) מחזיר `busy` בלי לגעת בדבר.
`test/update/updater_swap_test.dart` הורג את התהליך בכל צעד של ההחלפה ובכל
צעד של השחזור שאחריה, ובודק שאף יעד אינו חסר ושהסוף ישן כולו או חדש כולו.

נותר: RunOnce רץ רק בכניסה למערכת. מעדכן שנהרג בזמן שהמשתמש מחובר (בלי
כיבוי) משאיר תערובת עד הכניסה הבאה — או עד שאוצריא עולה ומשחזרת בעצמה.

### בחירת הבסיסים

החבילות נבנות מול שני השחרורים הקודמים (לפי גרסה, dev ויציב יחד), **ובנוסף
מול היציב האחרון** אם אינו ביניהם. בין שני יציבים יש לעיתים כמה שחרורי dev
(לפני 0.9.91 היו שלושה), ובלעדיו משתמשי היציב לא היו מוצאים חבילה. התג
המותקן נקרא מ-`otzaria-release.json`, ולכן גם `+<run_number>` של dev מזוהה.

### עדכון עץ — macOS ו-Linux נייד

ב-Windows ההחלפה היא קובץ-קובץ. ב-macOS ובעותק ה-FULL של Linux היא **תיקייה
שלמה**: bundle של macOS נחתם כיחידה אחת (קובץ נוסף, חסר או symlink שגוי
שוברים את `codesign --verify --deep`), ו-framework חדש מגיע עם symlinks
(`Versions/Current`) וביט הרצה. נמדד: חבילות ה-patch של macOS חוסכות 61–76%
מה-zip המלא, ושל Linux ‏66–89%.

**מה בחבילה.** מניפסט קובצי האפליקציה בסכמה 2 (`platform` שאינו `windows`)
נושא `mode` לכל קובץ ו-`links` (נתיב + יעד יחסי שנשאר בתוך העץ). חבילת עץ
היא `schemaVersion: 2` ומוסיפה `links` (ליצירה או לשינוי יעד), `linkRemovals`,
ו-`newTree` — העץ החדש המלא. חבילות Windows נשארות בסכמה 1 בדיוק, ולקוח
Windows קיים ממשיך לדחות כל גרסה אחרת. הארכיטקטורה ב-macOS היא `universal`.

**ההכנה** (`DifferentialUpdateEngine` עם `preparedRoot`, `lib/update/differential/tree_fs.dart`):
1. ההתקנה מועתקת לצידה — `.<שם>.otzaria-update` באותה תיקייה ולכן באותו כרך
   (`cp -cRp`/clonefile ב-APFS, `cp -a --reflink=auto` ב-Linux).
2. על העותק: הסרת symlinks וקבצים שהוסרו וניקוי תיקיות שהתרוקנו (תיקיית
   framework ריקה נחשבת קוד לא חתום), כתיבת הערכים באותו מסלול של Windows
   (patch, קובץ מלא, נסיגה לחבילת הקבצים המלאים), יצירת symlinks, ויישור
   ביט ההרצה לפי `newTree`.
3. העותק כולו מושווה ל-`newTree`: כל קובץ בגודל וב-hash (מחוץ ל-isolate
   הראשי), כל symlink ביעדו, ביט ההרצה, ובמק — שום קובץ נוסף. ההרשאות
   מושוות לפי ביט ההרצה בלבד: חילוץ tar מחיל את ה-umask של המשתמש על השאר.
4. כל כשל מוחק את העותק וחוזר למסלול המלא.

**ההחלפה** (`lib/update/tree_swap.dart`) היא סקריפט sh שממתין ל-pid:
כלי עזר נייטיבי מחליף אטומית את `app` ואת `prepared` באותו כרך; בכשל
ההתקנה הישנה נשארת בנתיבה, ובהצלחה היא נמחקת מתוך `prepared` יחד עם
תיקיית העבודה. בהיעדר כלי העזר משתמשים במסלול ההתקנה המלא. אוצריא
שלא יצאה תוך 2 דקות — הסקריפט כותב
`updater-gave-up` לפני שנגע בדבר, והממשק חוזר ל"מוכן להתקנה" כמו ב-Windows.
ב-macOS הוא משוגר כ-`.command` דרך `open` (כמו עדכון ה-zip הקיים); ב-Linux
כתהליך מנותק שכותב `swap.log` לתיקיית העבודה, ומפעיל מחדש את ה-launcher
`otzaria` ולא את `otzaria.bin`.

**מתי המסלול פעיל** (`treeUpdateSupported`): חותם שחרור תואם, zstd ארוז
(ב-macOS `Contents/MacOS/zstd`, ב-Linux ליד קובץ ההרצה — לעולם לא מה-PATH),
ההתקנה **והתיקייה שמכילה אותה** ברות-כתיבה, ואין בשורש ההתקנה נתוני משתמש —
הם היו מועתקים ונדרסים בהחלפה. ב-macOS החותם ב-`Contents/Resources` וה-bundle
אינו רץ מ-DMG או מ-App Translocation. ב-Linux ההתקנה היא עותק ה-FULL
(`isLinuxPortableInstall`: חותם, ולא תחת ‎/opt/otzaria‎ או ‎/usr‎). deb/rpm
נשארים על מנהל החבילות.

**התקנת Linux ניידת לעולם אינה מקבלת deb/rpm** (`pickLinuxAssetUrl` עם
`isPortableInstall`): deb היה מתקין עותק נפרד ב-‎/opt‎, והעותק שהמשתמש מריץ
לא היה מתעדכן לעולם. כשאין חבילה מצומצמת נפתח דף ההורדות בדפדפן.

**CI.** zstd נבנה מקוד המקור של `facebook/zstd` בגרסה ובגיבוב נעולים
(`tool/release/build_zstd.sh`) — ל-macOS אין בינארי רשמי, וה-zstd של Debian
תלוי בספריות משותפות. ב-macOS הוא universal, בלי zlib/lzma/lz4, נכנס
ל-bundle יחד עם החותם **לפני** החתימה, ונחתם לפניה; גם כלי ההחלפה האטומית
נבנה כ-universal ונחתם לפני ה-bundle. המניפסט נסרק מה-bundle החתום.
ב-Linux כלי ההחלפה, zstd וחותם השחרור נכנסים ל-`app/` של חבילת ה-FULL (x64,
arm64), והמניפסט נסרק מה-`app/` שנארז. החבילות נבנות בשלב נפרד אחרי יצירת
השחרור (`UPDATE_PACKAGES_PLATFORM=macos|linux`, אותו סקריפט ואותה מדיניות
בסיסים); עץ הבסיס של Linux נפרס בזרם מחבילת ה-FULL — `app/` בלבד. שחרורים
שקדמו לשינוי אין להם מניפסט, ולכן העדכון **אליהם** נשאר המסלול המלא.

ההחלפה האטומית משאירה את נתיב ההתקנה קיים גם אם התהליך נהרג ברגע ההחלפה.
