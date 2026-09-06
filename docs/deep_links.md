# קישורי עומק (Deep Links) — סכמת `otzaria://`

## סקירה כללית

אוצריא רשומה במערכת ההפעלה כמטפלת בסכמת ה‑URI `otzaria://`, כך שכל לחיצה על קישור כזה — בדפדפן, באפליקציה אחרת, בקיצור דרך, ב‑PowerShell, או ב‑system tray — פותחת את אוצריא ומבצעת פעולה מוגדרת מראש (פתיחת מסך, פתיחת ספר, התקנת תוסף).

מטרת המסמך: לתעד את כל הכתובות הנתמכות, איך הן עובדות מאחורי הקלעים, ואיך מוסיפים יעדים חדשים.

## איפה הסכמה נרשמת

נייד (Android/iOS/macOS) — רישום סטטי דרך קונפיגורציית הפלטפורמה:

- **Android** — [`android/app/src/main/AndroidManifest.xml`](../android/app/src/main/AndroidManifest.xml) (`<intent-filter>` עם `<data android:scheme="otzaria"/>`).
- **iOS** — [`ios/Runner/Info.plist`](../ios/Runner/Info.plist) (`CFBundleURLSchemes`).
- **macOS** — [`macos/Runner/Info.plist`](../macos/Runner/Info.plist) (זהה ל‑iOS).

דסקטופ (Windows/Linux) — **רישום דינמי בזמן ריצה** דרך [`PluginProtocolRegistrationService.ensureRegistered`](../lib/plugins/services/plugin_protocol_registration_service.dart). השם ההיסטורי מטעה — השירות אינו ספציפי לתוספים, הוא רושם את כל סכמת `otzaria://`:

- **Windows** — קריאה ל‑`reg.exe` שכותבת ל‑`HKCU\Software\Classes\otzaria` עם `shell\open\command` שמכוון ל‑exe הפעיל ([`buildWindowsRegistrationCommands`](../lib/plugins/services/plugin_protocol_registration_service.dart#L136-L153)). [`windows/runner/main.cpp`](../windows/runner/main.cpp) אחראי רק על מה שקורה אחרי שה‑OS הפעיל את אוצריא עם הארגומנט (forwarding למופע קיים), לא על הרישום עצמו.
- **Linux** — יצירה דינמית של `~/.local/share/applications/otzaria.desktop` עם `MimeType=x-scheme-handler/otzaria;`, ואז `update-desktop-database` ו‑`xdg-mime default` ([`_ensureLinuxRegistration`](../lib/plugins/services/plugin_protocol_registration_service.dart#L49-L85)). אין קובץ `.desktop` סטטי במאגר.

## כתובות נתמכות

### `otzaria://open/...` — ניווט פנימי

| כתובת | תוצאה |
|--------|--------|
| `otzaria://open/calendar` | פותח את לוח השנה (לשונית במסך הכלים) |
| `otzaria://open/gematria` | פותח את כלי הגימטריה |
| `otzaria://open/notes` | פותח הערות אישיות |
| `otzaria://open/shamor_zachor` | פותח שמור וזכור |
| `otzaria://open/measurements` | פותח מדות ושיעורים |
| `otzaria://open/aramaic_dictionary` | פותח מילון ארמי-עברי |
| `otzaria://open/acronyms_dictionary` | פותח ראשי תיבות |
| `otzaria://open/library` | פותח את מסך הספרייה |
| `otzaria://open/search` | פותח את מסך החיפוש (ללא הפעלת חיפוש) |
| `otzaria://open/search?q=<text>` | פותח לשונית חיפוש חדשה ומפעיל חיפוש מיידית בכל הספרים, עם ברירות המחדל (מצב מתקדם, scope `/`) |
| `otzaria://open/search?q=<text>&mode=<mode>` | כנ"ל, עם קביעת מצב החיפוש ללשונית: `advanced` (מתקדם), `exact` (מדויק) או `fuzzy` (מקורב). ערך לא מוכר מתעלם — מצב מתקדם |
| `otzaria://open/settings` | פותח את ההגדרות (הלשונית הנוכחית) |
| `otzaria://open/settings/design` | פותח הגדרות › מראה |
| `otzaria://open/settings/text` | פותח הגדרות › כתב |
| `otzaria://open/settings/library` | פותח הגדרות › ספרייה |
| `otzaria://open/settings/tools` | פותח הגדרות › כלים |
| `otzaria://open/settings/shortcuts` | פותח הגדרות › קיצורים |
| `otzaria://open/settings/system` | פותח הגדרות › מערכת |
| `otzaria://open/settings/about` | פותח הגדרות › אודות |
| `otzaria://open/tools` | פותח את פאנל הכלים (רשת הקוביות עם חיפוש) |
| `otzaria://open/history` | פותח את דיאלוג ההיסטוריה |
| `otzaria://open/bookmarks` | פותח את דיאלוג הסימניות |
| `otzaria://open/detection?q=<text>` | פותח את דיאלוג איתור מקורות עם טקסט מילוי-מראש ומפעיל חיפוש מיידית |
| `otzaria://open/detection` | פותח את דיאלוג איתור מקורות ריק |
| `otzaria://open/inspection` | פותח את מסך העיון (הספר האחרון שנפתח) |
| `otzaria://open/sdk` | פותח את הגדרות › כלים (ניהול תוספים) |
| `otzaria://open/daily_page` | פותח את הדף היומי (PDF תלמוד בבלי בדף הנכון ליום) |
| `otzaria://open/tool/<tool-id>` | פותח כרטיסיית כלי בעיון לפי מזהה מלא — תומך גם בתוספים |
| `otzaria://open/plugin/<plugin-id>` | פותח כרטיסיית תוסף בעיון לפי מזהה התוסף |
| `otzaria://open/tab/<index>` | מעבר לטאב פתוח לפי מיקומו (0-based). אינו פותח טאב חדש; אם המיקום לא קיים — מתעלם. נבנה אוטומטית ב-Jump List של שורת המשימות (Windows) |
| `otzaria://open/book/<id>` | פותח ספר בעיון לפי מזהה מסד הנתונים |
| `otzaria://open/book/<id>?index=<n>` | פותח את הספר בסעיף `n` (אינדקס לא שלילי). |
| `otzaria://open/book/<id>?q=<text>` | פותח את הספר עם מחרוזת חיפוש להדגשה. ניתן לשלב עם `index`. |
| `otzaria://open/book/<id>?index=<n>&mark` | פותח את הספר בסעיף `n` ומדגיש את כל רקע המקטע בצהוב. |
| `otzaria://open/book/<id>?index=<n>&m=<text>` | פותח את הספר בסעיף `n` ומדגיש את הטקסט `text` בצהוב בתוך המקטע. |
| `otzaria://open/pdf/<id>` | פותח ספר PDF לפי מזהה משותף עם ה-TextBook במסד הנתונים |
| `otzaria://open/pdf/<id>?index=<n>` | פותח את ספר ה-PDF בעמוד `n` (מספר עמוד חיובי). |

**דוגמאות:**

```text
otzaria://open/calendar
otzaria://open/shamor_zachor
otzaria://open/measurements
otzaria://open/aramaic_dictionary
otzaria://open/acronyms_dictionary
otzaria://open/library
otzaria://open/history
otzaria://open/bookmarks
otzaria://open/settings
otzaria://open/detection
otzaria://open/detection?q=%D7%91%D7%A8%D7%90%D7%A9%D7%99%D7%AA
otzaria://open/inspection
otzaria://open/sdk
otzaria://open/daily_page
otzaria://open/settings/design
otzaria://open/settings/text
otzaria://open/settings/library
otzaria://open/settings/tools
otzaria://open/settings/shortcuts
otzaria://open/settings/system
otzaria://open/settings/about
otzaria://open/tool/builtin.gematria
otzaria://open/tool/com.example.myplugin
otzaria://open/plugin/com.example.myplugin
otzaria://open/book/1234
otzaria://open/book/1234?index=42
otzaria://open/book/1234?q=%D7%91%D7%A8%D7%90%D7%A9%D7%99%D7%AA
otzaria://open/book/1234?index=42&q=%D7%91%D7%A8%D7%90%D7%A9%D7%99%D7%AA
otzaria://open/book/1234?index=42&mark
otzaria://open/book/1234?index=42&m=%D7%91%D7%A8%D7%90%D7%A9%D7%99%D7%AA
otzaria://open/search?q=%D7%91%D7%A8%D7%90%D7%A9%D7%99%D7%AA
otzaria://open/search?q=%D7%91%D7%A8%D7%90%D7%A9%D7%99%D7%AA&mode=exact
otzaria://open/search?q=%D7%91%D7%A8%D7%90%D7%A9%D7%99%D7%AA&mode=fuzzy
otzaria://open/pdf/120
otzaria://open/pdf/120?index=17
otzaria://open/detection?q=%D7%91%D7%A8%D7%90%D7%A9%D7%99%D7%AA
```

**הערות על קידוד:** טקסט בעברית ב‑`q=` ו-`m=` מומלץ לקודד URL‑encoded (UTF‑8). עם זאת, הראוטר סלחני: עברית גולמית לא-מקודדת עוברת כמו שהיא, ואחוזי-קידוד בקידוד ANSI ישן (Windows‑1255 / ISO‑8859‑8 / CP862 — כפי שמייצרים מאקרו/VBA ותיקים של Office, למשל `?q=%F9%EC%E5%ED`) מזוהים ומפוענחים אוטומטית. ערך `index` שלילי או לא מספרי מתעלם — הספר ייפתח בתחילתו. `q=` ריק מתעלם. `m=` ריק או רווחים בלבד מתעלם. לגבי `detection?q=` — חובה לספק ערך לא-ריק; קישור ללא `q=` מתעלם לחלוטין.

**הבדל בין `mark` ל-`m=`:**
- `?mark` — מדגיש את **כל רקע המקטע** בצהוב (הדגשת שורה שלמה).
- `?m=<text>` — מדגיש **טקסט ספציפי** בתוך המקטע בצהוב (הדגשת מילים בלבד).
- ניתן לשלב `mark` עם `q=` (חיפוש פעיל + הדגשת שורה).
- ניתן לשלב `m=` עם `q=` (חיפוש פעיל + הדגשת טקסט ספציפי).

**`tool/<id>` מול `plugin/<id>`:** שניהם מנותבים כיום לאותה פונקציה — `openToolTabById` — ופותחים כרטיסיית כלי במסך העיון. ההבחנה נשמרה לתאימות אחורה בלבד. כלי שכבר פתוח מקבל מיקוד במקום כרטיסיה נוספת. כלי מוסתר, תוסף מושבת או תוסף שדורש רשת במצב מנותק — מציגים `UiSnack.showError` עם הסיבה. כשמערכת התוספים עדיין נטענת הכרטיסיה נפתחת מיד ומציגה מחוון טעינה עד שהמצב ידוע.

**רגישות לאותיות גדולות/קטנות:** הסכמה, ה‑host, ושמות הפעולה (`calendar`, `library`, `book`, `tool`, `plugin`, וכד') כולם case‑insensitive — `OTZARIA://OPEN/CALENDAR` ו‑`otzaria://Open/Book/1234` תקפים בדיוק כמו הצורה הקטנה. הערכים (tool id, plugin id, מזהי ספרים, כתובות `url=`) נשמרים כפי שהם.

### `otzaria://plugin/install?url=...` — התקנת תוסף

קישור התקנת תוסף מהמאגר. תומך גם ב‑download URLs חיצוניים.

| פרמטר | תיאור |
|--------|--------|
| `url` (חובה) | כתובת ה‑download של חבילת ה‑`.otzplugin`. חייב להיות `http`/`https`. |
| `overwrite` (אופציונלי) | `true`/`1`/`yes`/`on` — דרוס תוסף קיים בלי לשאול. ברירת מחדל `false`. |

**דוגמה:**

```text
otzaria://plugin/install?url=https%3A%2F%2Fexample.com%2Fmyplugin.otzplugin&overwrite=true
```

לאחר קבלת הקישור, אוצריא עוברת למסך הכלים ויוזמת זרימת התקנה (כולל בקשת אישור הרשאות אם נחוץ).

### `otzaria://library/reindex` — רענון הספרייה ועדכון האינדקס

מיועד לתוכנה חיצונית שמעדכנת את קבצי הספרייה (הוספה/עדכון של ספרים) ומבקשת מאוצריא לקלוט את השינויים:

1. הקטלוג נטען מחדש מהדיסק (`RefreshLibrary`).
2. ספרים חדשים מתווספים לאינדקס החיפוש (`StartIndexing` — מדלג על ספרים שכבר מאונדקסים).
3. ספרים שתוכנם השתנה מזוהים לפי השוואת טביעות-אצבע ומאונדקסים מחדש (`ReconcileIndex`).

הקישור מפעיל את האינדוקס **גם כשההגדרה "עדכון אינדקס אוטומטי" כבויה** — הבקשה החיצונית נחשבת מפורשת. אין כאן מחיקת אינדקס מלאה: איפוס מלא נשאר פעולה ידנית בהגדרות › ספרייה.

```text
otzaria://library/reindex
```

הערה למחליפי `seforim.db`: החלפת קובץ ה-DB עצמו נתמכת רק כשאוצריא סגורה (הקובץ נעול בזמן ריצה). לאחר ההחלפה, הפעלת הקישור תפתח את אוצריא והאינדקס יעודכן מול ה-DB החדש.

### `otzaria://info/...` — שאילתת מידע (פלט JSON)

בשונה מכל שאר הכתובות, קישור `info` **אינו יעד ניווט** — הוא שאילתה. אוצריא אוספת דוח JSON ומציגה אותו בפופאפ קטן ומעוצב, בלי לפתוח טאב, בלי לעבור מסך ובלי לשנות שום מצב באפליקציה.

השימוש העיקרי: הדבקת הכתובת **בתוך התוכנה** — בשדה "איתור ספר" בספרייה או בדיאלוג "איתור מקורות" — ואז הפופאפ נפתח מיד. הכתובת עובדת גם מבחוץ (דפדפן, שורת פקודה); אז החלון מוצף לחזית והפופאפ מוצג בו.

> **הפעלת URI אינה מחזירה ערך — לעולם.** סכמת `otzaria://` היא חד-כיוונית: הדפדפן/ה-OS מפעילים את ה-exe ואין ערוץ חזרה — לא stdout, לא קוד יציאה, לא גוף תגובה. לכן תוכנה שרוצה **לשאוב** את הדוח לא יכולה לעשות זאת דרך הקישור; היא משתמשת בפקודת ה-CLI שלהלן. (מאותה סיבה `plugin/install` מדווח דרך `callback=` ולא בערך מוחזר.)

#### `otzaria info` — אותו דוח, כפלט CLI לתוכנות חיצוניות

פקודת headless שמדפיסה את ה-JSON הגולמי ל-stdout ויוצאת. אין חלון, אין splash, ואין מעבר דרך ה-mutex של מופע-יחיד — לכן היא עובדת גם כשאוצריא פתוחה, בלי לגעת בחלון שלה.

> הדילוג על החלון וה-splash מוגדר ב-`IsCliInvocation` שב-runner של **Windows** בלבד. בלינוקס הפקודה תעבוד ותדפיס את ה-JSON, אבל ה-splash כן יוצג.

הפקודה מזוהה גם כ-`--info` וכ-`/info`. הנרמול חייב להישאר זהה בשני הצדדים — `normalizeCliCommand` ב-[`lib/core/cli_command.dart`](../lib/core/cli_command.dart) מול `IsCliInvocation` ב-[`windows/runner/main.cpp`](../windows/runner/main.cpp); פער ביניהם מייצר מופע שני שדילג על המנעול ועולה כאפליקציה מלאה בלי חלון, ולכן [`test/core/cli_command_test.dart`](../test/core/cli_command_test.dart) קורא את קובץ ה-C++ ואוכף את השקילות.

```text
otzaria.exe info                     # דוח מלא
otzaria.exe info app                 # מקטע אחד
otzaria.exe info errors --limit=20
otzaria.exe info folders             # תיקיות אישיות + קובצי הספרים שבהן
otzaria.exe info folders --files=0   # ספירות בלבד, בלי רשימת קבצים
otzaria.exe info --compact           # שורה אחת, לצינור לתוך מפענח
otzaria.exe info --out=report.json   # מטען נקי לקובץ
otzaria.exe info --help
```

| דגל | משמעות |
|--------|--------|
| `--limit=<n>` | מספר רשומות השגיאה. **אין תקרה כאן** — בשונה מ-`?limit=` בכתובת ה-URI שנחסם ב-50, הקורא בשורת הפקודה מהימן ומקבל בדיוק מה שביקש |
| `--files=<n>` | מספר הקבצים לכל תיקייה אישית (ברירת מחדל 50; `0` = ספירות בלבד). גם כאן **אין תקרה**, בשונה מ-`?files=` שנחסם ב-500 |
| `--compact` | JSON בשורה אחת |
| `--out=<path>` | כתיבת ה-JSON לקובץ במקום ל-stdout |
| `-h`, `--help` | מסך עזרה |

| קוד יציאה | משמעות |
|--------|--------|
| `0` | הצלחה — ה-JSON ב-stdout (או בקובץ `--out`). גם `--help`, שמדפיס טקסט עזרה ולא JSON |
| `1` | האיסוף או הכתיבה לקובץ נכשלו — הסיבה ב-stderr |
| `64` | שגיאת שימוש (נושא/דגל לא מוכר, שני נושאים, `--limit`/`--out` לא חוקי) |

**stdout אינו נקי לחלוטין ב-Windows.** `irondash_engine_context_plugin.dll` מדפיס `P ATTACH` מ-`DllMain` בזמן טעינת התהליך — לפני שקוד Dart רץ בכלל, ולכן אין דרך לחסום זאת מתוך האפליקציה. בבניית debug מצטרפות אליו שורת ה-Dart VM service והבאנר של `flutter_inappwebview` (שניהם `kDebugMode` בלבד).

מה שכן מובטח: **שום דבר אינו מודפס אחרי ה-JSON.** לכן שתי דרכי קריאה אמינות:

```csharp
// א' — השורה האחרונה, עם --compact (ה-JSON תמיד שורה אחת)
var psi = new ProcessStartInfo("otzaria.exe", "info app --compact") {
  RedirectStandardOutput = true, UseShellExecute = false,
};
using var proc = Process.Start(psi);
var lines = proc.StandardOutput.ReadToEnd()
  .Split('\n', StringSplitOptions.RemoveEmptyEntries);
var json = lines[^1].Trim();

// ב' — מטען מובטח בקובץ (מומלץ לאוטומציה)
Process.Start(new ProcessStartInfo("otzaria.exe",
  $"info app --out=\"{path}\"") { UseShellExecute = false }).WaitForExit();
var json2 = File.ReadAllText(path);   // רק ה-JSON, בלי newline נגרר
```

`print` שנורה מתוך קוד האפליקציה *במהלך* האיסוף (למשל `debugPrint` בשירותים) מנותב ל-stderr דרך `ZoneSpecification`, כך שהוא אינו מזהם את ה-JSON. ב-release `debugPrint` ממילא מנוטרל ב-`main.dart`, ולכן ה-Zone היא הרשת שמכסה תלויות ואת מצב ה-debug.

הפלט זהה בדיוק לזה שבפופאפ — שני הערוצים קוראים ל-[`AppInfoService.collect`](../lib/core/info/app_info_service.dart), ורק מקור רשימת התוספים שונה (BLoC בממשק, `PluginRegistryRepository` ב-CLI).

**בחירת הנושא היא גם בקרת הביצועים:** `app`, `plugins` ו-`errors` אינם נוגעים בספרייה ומחזירים מיד. `library` טוען את קטלוג הספרייה מ-`seforim.db`, ולכן לוקח כמה שניות. `folders` אינו נוגע ב-DB כלל אך **סורק את הדיסק** — הוא עובר רקורסיבית על כל תיקייה אישית, ולכן משכו נגזר ממספר הקבצים שבהן. `all` כולל את שניהם. להאצה: `--files=0` (או `?files=0`) חוסך את בניית רשימת הקבצים, אבל לא את המעבר עצמו — הספירות דורשות אותו.

**איך ה-CLI קורא את ההגדרות בזמן שאוצריא פתוחה:** Hive נועל את תיבת ההגדרות בלעדית לכל התהליך (`app_preferences.lock` לצד הקובץ), ולכן תהליך שני שינסה לפתוח אותה ייכשל. [`SettingsSnapshot`](../lib/core/info/settings_snapshot.dart) מעתיק את קובץ התיבה לתיקייה זמנית ופותח את **העותק**; ה-`Settings` שנבנה מעליו הוא קריאה-בלבד (`ReadOnlySettingsCache`, כל ה-setters הם no-op). התיבה החיה אינה נפתחת ואינה משתנה. אם אין תיבה או שהקריאה נכשלה — `Settings` מאותחל ריק, הדוח נופל לנתיבי ברירת המחדל, ו-`settingsLoaded: false` מסמן זאת.

שתי מלכודות באותו מנגנון: (א) `Hive.openBox` מחזיר תיבה פתוחה קיימת **לפי שם, בהתעלם מהנתיב** — ולכן `SettingsSnapshot.read` מסרב לפעול בתהליך שבו התיבה כבר פתוחה, אחרת היה קורא את התיבה החיה וסוגר אותה. (ב) העותק חייב להיסגר לפני מחיקת התיקייה הזמנית: תיבה פתוחה מחזיקה את הקובץ ב-Windows, המחיקה נכשלת, והעותק — שמכיל גם hash של סיסמת המצב המוגן ואישורי Google Calendar — היה נשאר ב-`%TEMP%`.

מכיוון שההגדרות אינן כתיבות בתהליך הזה, `AppPaths.getLibraryPath()` אינו יכול לשמור תיקון נתיב. לכן מקטע `library` גוזר את `databasePath` מנתיב הספרייה ה**מפוענח** ולא מ-`Settings` הגולמי — אחרת `path` ו-`databasePath` באותו JSON היו יכולים לסתור זה את זה.

הרישום ב-`main.cpp` הוא `IsCliInvocation`, שמדלג על ה-mutex ועל ה-splash ובונה את `FlutterWindow` עם `headless=true` כך שהחלון לא מוצג לעולם; `AttachConsole(ATTACH_PARENT_PROCESS)` בראש `wWinMain` הוא מה שמחבר את stdout לקורא.

| כתובת | תוצאה |
|--------|--------|
| `otzaria://info` | דוח מלא — תוכנה + ספרייה + תיקיות אישיות + תוספים + שגיאות |
| `otzaria://info/all` | זהה ל-`otzaria://info` |
| `otzaria://info/app` | מידע על התוכנה |
| `otzaria://info/library` | מידע על הספרייה |
| `otzaria://info/folders` | התיקיות שהוגדרו כספרים אישיים, וקובצי הספרים הנתמכים שקיימים בהן בפועל |
| `otzaria://info/plugins` | מידע על התוספים |
| `otzaria://info/errors` | השגיאות האחרונות מקובצי הלוג |
| `?limit=<n>` | מספר רשומות השגיאה — ברירת מחדל 5, תקרה 50; ערך לא חוקי → ברירת המחדל. מתקבל בכל נושא, אך משפיע רק על מקטע `errors` |
| `?files=<n>` | מספר הקבצים המפורטים **לכל תיקייה** — ברירת מחדל 50, תקרה 500. `0` הוא ערך תקף ומשמעו ספירות בלבד בלי רשימת קבצים; ערך שלילי או לא-מספרי → ברירת המחדל. מתקבל בכל נושא, אך משפיע רק על מקטע `folders` |

**Aliases לנושאים:** `software`/`version` → `app`, `books` → `library`, `folder`/`personal`/`personal_books`/`personal_folders`/`custom_folders` → `folders`, `plugin` → `plugins`, `error`/`log`/`logs` → `errors`. נושא לא מוכר או נתיב עמוק (`info/app/extra`) מוחזרים `null` ומתעלמים בשקט, כמו כל כתובת לא מוכרת.

**שדות השורש** (בכל דוח, בשני הערוצים): `topic`, `generatedAt` (UTC עם סיומת `Z`), ו-`settingsLoaded` — `false` מסמן שהגדרות המשתמש לא נקראו ולכן כל הנתיבים והספירות הם ברירות מחדל ולא המצב בפועל. **מקטע שאיסופו נכשל מוחזר כ-`{"error": "<סיבה>"}`** במקום שדותיו, ובפופאפ מוצג כשורת "שגיאה באיסוף" — כך כשל בחלק אחד אינו מבטל את שאר הדוח.

**מה כל מקטע מחזיר:**

| מקטע | שדות |
|--------|--------|
| `app` | `version`, `buildNumber`, `fullVersion` (`version+build` — הפורמט שבו נשמר `previousVersion`), `installedAt` + `installedAtSource`, `updatedAt`, `previousVersion`, `installType` (`portable`/`allUsers`/`perUser`), `accountType` (`administrator`/`standard`/`unknown`), `elevated`, `platform`, `operatingSystem`, `dataRootPath`, `name`, `packageName` |
| `library` | `version` (מ-`schema_meta.db_version`), `lastUpdatedAt`, `totalBooks`, `personalBooks`, `officialBooks`, `pdfBooks`, `path`, `indexPath`, `databasePath`, `databaseExists`, `databaseSizeBytes` |
| `folders` | `configuredCount`, `existingCount`, `totalFiles`, `totalSizeBytes`, `fileLimit`, `supportedExtensions[]`, `folders[]` |
| `plugins` | `webViewVersion` (WebView2 — Windows בלבד), `installedCount`, `enabledCount`, `installed[]` עם `id`, `name`, `version`, `enabled`, `source`, `installedAt`, `updatedAt` |
| `errors` | `totalEntries`, `returnedEntries`, `files[]`, `recent[]` |

`files[]` — `path` ו-`exists` תמיד; `sizeBytes`, `modifiedAt`, `entryCount` רק לקובץ קיים; `readError` רק כשקובץ קיים לא נקרא/נפענח (בלעדיו מכונה שקורסת הייתה מקבלת דוח שמצהיר "אין שגיאות"). `recent[]` — `source` ו-`title` תמיד; `timestamp`, `version`, `message`, `stack` (3 פריימים ראשונים) מושמטים כשאין להם ערך, ולא מוחזרים כ-`null`.

**מקטע `folders` — רשומה לכל תיקייה** ב-`folders[]`:

| שדה | משמעות |
|--------|--------|
| `path`, `name` | הנתיב כפי שהמשתמש הגדיר אותו, ושם התיקייה בלבד (זהו גם שם הקטגוריה בעץ) |
| `exists` | האם התיקייה קיימת בדיסק כרגע. `false` = כונן חיצוני מנותק או תיקייה שנמחקה, והספירות שלה אפסיות |
| `addToDatabase` | האם תוכן התיקייה נסרק לתוך `user_books.db` (מול קריאה ישירה מהקבצים) |
| `mergeIntoLibrary` | הערך **האפקטיבי** — חריגת התיקייה, ובהיעדרה ההגדרה הגלובלית. `mergeIntoLibrarySource` מבחין בין השניים (`folder`/`default`), כי `null` גולמי אינו ניתן לפענוח בלי ההגדרה |
| `hidden` | התיקייה מוסתרת מעץ הספרייה (הספרים נשארים ב-DB) |
| `addedAt` | מתי נוספה, UTC |
| `fileCount`, `sizeBytes` | ספירת קובצי הספרים ונפחם — **תמיד מלאות**, גם כש-`files[]` קוצץ |
| `filesByType` | ספירה לפי סיומת, ממוינת: `{"pdf": 20, "txt": 100}` |
| `files[]` | הקבצים עצמם (עד `files=`), ממוינים לפי נתיב: `path`, `name`, `fileType`, `sizeBytes`, `modifiedAt`. מושמט לגמרי כש-`files=0` |
| `filesTruncated` | `true` כשיש בתיקייה יותר קבצים משפורטו |
| `scanTruncated` | הסריקה נעצרה בתקרת הרשומות של התיקייה — הספירות חלקיות. מוחזר רק כשקרה |
| `scanError` | שגיאת מערכת קבצים ראשונה (הרשאות וכד'). תת-תיקייה שנחסמה אינה מבטלת את שאר הסריקה. מוחזר רק כשקרה |

**מה נחשב "קובץ ספר" כאן:** אותם כללים בדיוק של סורק הספרייה, ולא רשימת סיומות מקבילה — הסיומות נגזרות מ-[`kProductionBookFormats`](../lib/utils/file/document_format.dart) (מוחזרות ב-`supportedExtensions`), קבצים ותיקיות מוסתרים/מערכת מדולגים, ו-‎.xml‎/‎.wbk‎ נספרים רק אם **תוכנם** אכן מסמך Word. בלי ההצמדה הזו הדוח היה מבטיח ספרים שהסורק לעולם לא יקלוט.

כל חותמות הזמן ב-JSON הן UTC עם סיומת `Z`. הפופאפ ממיר אותן לשעון מקומי לתצוגה.

הפופאפ מציג את השדות המרכזיים בעברית; ה-JSON המלא זמין בכפתור "הצג JSON" ובכפתור ההעתקה שבראש הפופאפ.

**נתוני התוספים** נקראים מ-`PluginRegistryRepository` בשני הערוצים. בממשק, כשמערכת התוספים עדיין נטענת, הדוח פונה למרשם ישירות במקום לדווח `installedCount: 0` — כך הפופאפ וה-CLI לא מציגים מספרים שונים על אותה התקנה.

**מאיפה מגיעים תאריכי ההתקנה והעדכון:** [`AppInstallTimelineStore`](../lib/core/info/app_install_timeline.dart) נקרא ב-`main.dart` מיד לאחר `Settings.init`, רושם את תאריך ההתקנה בהפעלה הראשונה, ומעדכן `updatedAt` + `previousVersion` בכל שינוי גרסה. בהתקנות שקדמו למנגנון אין רישום, ולכן ב-Windows התאריך נגזר מזמן היצירה של תיקיית הנתונים ומסומן `installedAtSource: derived` (בפופאפ: "מוערך"). ב-Linux/macOS `st_ctime` אינו זמן יצירה, ולכן אין גזירה והתאריך נרשם בהפעלה הראשונה שראתה את המנגנון.

**מאיפה מגיע סוג החשבון:** [`SystemAccountProbe`](../lib/core/info/system_account_info.dart) מריץ תהליך חד-פעמי לפי דרישה (לא בעלייה): ב-Windows `whoami /groups /fo csv /nh` — קיום `S-1-5-32-544` מעיד על חשבון מנהל (גם ב-token מפוצל), ו-`S-1-16-12288`/`S-1-16-16384` מעידים על ריצה elevated. ב-POSIX `id -u` ו-`id -Gn` (`sudo`/`wheel`/`admin`).

**קובצי הלוג הנסרקים:** `<dataRoot>/logs/errors.txt` (פורמט הבלוקים של [`ErrorLogFile`](../lib/core/error_log_file.dart) — שגיאות Flutter, כשלי אינדוקס, כשלי WebView של תוספים) ו-`%TEMP%\otzaria_shutdown_errors.log` ב-Windows (שורה לרשומה). קובץ נעול או פגום מדולג בלי לבטל את שאר הדוח.

```text
otzaria://info
otzaria://info/app
otzaria://info/library
otzaria://info/folders
otzaria://info/folders?files=0
otzaria://info/folders?files=200
otzaria://info/plugins
otzaria://info/errors
otzaria://info/errors?limit=20
```

## איך משתמשים בקישור

### מהדפדפן

```html
<a href="otzaria://open/calendar">פתח לוח שנה</a>
```

הדפדפן יציע למשתמש לפתוח את אוצריא בפעם הראשונה ויזכור את ההסכמה לאחר מכן.

### משורת פקודה

```powershell
# Windows
Start-Process "otzaria://open/calendar"

# או דרך ShellExecute
explorer "otzaria://open/calendar"
```

```bash
# Linux
xdg-open "otzaria://open/calendar"

# macOS
open "otzaria://open/calendar"
```

### מקיצור דרך בדסקטופ (Windows)

יוצרים קובץ `.lnk` שה‑target שלו הוא:

```text
explorer.exe otzaria://open/calendar
```

או, לחלופין, קובץ `.url`:

```ini
[InternetShortcut]
URL=otzaria://open/calendar
```

### מאפליקציה אחרת

כל קוד שיכול לבצע "פתיחת URL במערכת ההפעלה" יעבוד. למשל:

```dart
// Flutter / Dart
await launchUrl(Uri.parse('otzaria://open/book/1234'));
```

```javascript
// Web
window.location.href = 'otzaria://open/calendar';
```

```csharp
// C# / .NET
System.Diagnostics.Process.Start(new ProcessStartInfo {
  FileName = "otzaria://open/calendar",
  UseShellExecute = true,
});
```

### ממגש מערכת / כפתור משולב

תשתית הקישורים זמינה — אם תרצה להוסיף קיצור דרך במגש המערכת או להטמיע כפתור באפליקציה אחרת, פשוט קרא ל‑`ShellExecute`/`launchUrl` עם הכתובת המתאימה. אין צורך בקוד מיוחד מצד אוצריא.

## איך זה עובד מאחורי הקלעים

הזרימה זהה בכל הפלטפורמות, עם הבדל אחד מרכזי בין אינסטנס יחיד לחדש:

```
            ┌──────────────────────┐
            │ Click otzaria://...  │
            └──────────┬───────────┘
                       ▼
        ┌──────────────────────────────┐
        │ OS מפעיל את אוצריא עם הארגומנט │
        └──────────────┬───────────────┘
                       ▼
            ┌──────────────────────┐
            │ אוצריא כבר רצה?      │
            └──────┬─────────┬─────┘
                  לא│        │כן
                    ▼        ▼
         ┌───────────┐   ┌────────────────────────────┐
         │ הפעלה רגילה│   │ הפרוסס המשני כותב          │
         │ + טיפול   │   │ pending_external_activations│
         │ בארגומנטים│   │ ויוצא מיד                  │
         └─────┬─────┘   └─────────────┬──────────────┘
               │                       ▼
               │       ┌─────────────────────────────────┐
               │       │ המופע הקיים זוהה את השינוי בקובץ │
               │       │ דרך file watcher                 │
               │       └─────────────┬───────────────────┘
               ▼                     ▼
         ┌────────────────────────────────────────────┐
         │ _handleExternalActivationUriString(uri)    │
         │   ↓                                        │
         │   ExternalUriRouter.parseUri               │
         │   → ExternalUriAction (sealed)             │
         └─────────────────┬──────────────────────────┘
                           ▼
                 ┌───────────────────┐
                 │ פעולה (ניווט/     │
                 │  פתיחת ספר/התקנה) │
                 └───────────────────┘
```

### Single‑instance ב‑Windows

ב‑[`windows/runner/main.cpp:104-121`](../windows/runner/main.cpp#L104-L121) משתמשים ב‑Mutex בשם `OtzariaAppSingleInstance`. אם המופע השני מזהה שהמופע הראשון כבר חי, הוא:

1. מוציא מהארגומנטים את ה‑URIs שמתחילים ב‑`otzaria:`.
2. מוסיף אותם לקובץ `%APPDATA%\otzaria\pending_external_activations.jsonl` כשורות JSONL.
3. יוצא מיד עם `EXIT_SUCCESS`.

המופע הראשון מאזין לשינויים בקובץ דרך [`ExternalActivationQueue`](../lib/core/external_activation_queue.dart) ב־[`main_window_screen.dart`](../lib/navigation/view/main_window_screen.dart):

```dart
_externalActivationWatchSub = queueFile.parent.watch().listen((event) {
  if (normalizedPath != normalizedQueuePath) return;
  unawaited(_processPendingExternalActivations());
});
```

הקובץ עובר rename ל‑`.processing` בזמן הקריאה — כך שלא נאבדים URIs אם המופע הראשון נסגר באמצע.

### פענוח URI

ראוטר יחיד — [`ExternalUriRouter`](../lib/core/external_uri_router.dart) — מנתב את כל הסכמות (`open` ו‑`plugin`) לאותו `sealed class ExternalUriAction`:

| variant | מאיפה | תוכן |
|---------|--------|------|
| `OpenScreenAction(Screen)` | `otzaria://open/library`, ... | מסך עליון |
| `OpenToolAction(String toolId)` | `otzaria://open/calendar`, `/daily`, `/shamor_zachor`, `/measurements`, `/aramaic_dictionary`, `/acronyms_dictionary`, `/gematria`, `/notes`, `/tool/<id>`, ... | לשונית כלי |
| `OpenPluginAction(String pluginId)` | `otzaria://open/plugin/<plugin-id>` | פתיחת תוסף ישירות (גם לא-מוצמד) |
| `SwitchToTabAction(int index)` | `otzaria://open/tab/<index>` | מעבר לטאב פתוח קיים לפי מיקומו (Jump List של Windows) |
| `OpenBookAction(int bookId, {int? index, String? searchQuery, bool markSection, String? markText})` | `otzaria://open/book/<id>?index=<n>&q=<text>&mark&m=<text>` | ספר בעיון |
| `OpenSettingsTabAction({SettingsTab? tab})` | `otzaria://open/settings`, `/settings/design`, `/settings/text`, ... | פתיחת הגדרות, אופציונלית עם ניווט לטאב |
| `OpenHistoryAction()` | `otzaria://open/history` | דיאלוג היסטוריה |
| `OpenBookmarksAction()` | `otzaria://open/bookmarks` | דיאלוג סימניות |
| `RunSearchAction(String query, {SearchMode? mode})` | `otzaria://open/search?q=<text>&mode=<advanced\|exact\|fuzzy>` | חיפוש מלא בלשונית חדשה, אופציונלית עם מצב חיפוש |
| `RunDetectionAction(String query)` | `otzaria://open/detection?q=<text>`, `otzaria://open/detection` | פתיחת דיאלוג איתור מקורות (ריק או עם טקסט) |
| `OpenInspectionAction()` | `otzaria://open/inspection` | מסך העיון (ספר אחרון) |
| `OpenSdkAction()` | `otzaria://open/sdk` | פתיחת דיאלוג ניהול תוספים |
| `OpenDailyPageAction()` | `otzaria://open/daily_page` | פתיחת ה-PDF של תלמוד בבלי בדף הנכון ליום |
| `ShowInfoAction(InfoTopic topic, {int errorLimit, int fileLimit})` | `otzaria://info`, `otzaria://info/app`, `/library`, `/folders?files=<n>`, `/plugins`, `/errors?limit=<n>` | שאילתת מידע — אוסף דוח JSON ומציג בפופאפ, ללא ניווט |
| `InstallPluginAction(PluginStoreInstallRequest)` | `otzaria://plugin/install?url=...` | התקנת תוסף מהחנות |
| `InstallLocalPluginAction(String archivePath)` | `otzaria://plugin/install-local?path=<abs>` | התקנת תוסף מקובץ `.otzplugin` מקומי (לחיצה כפולה על קובץ משויך) |

לפענוח `plugin/install` הראוטר מעביר את ה‑URI ל‑[`PluginStoreLinkParser.parseUri`](../lib/plugins/services/plugin_store_link_parser.dart) (שמרנו אותו עצמאי כדי לא לשבור את הבדיקות הקיימות), ועוטף את התוצאה ב‑`InstallPluginAction`. אין יותר נפילה אחורה בין שני פרסרים — `ExternalUriRouter.parseUri` הוא נקודת הכניסה היחידה.

### דיספצ׳ר

ב‑[`main_window_screen.dart`](../lib/navigation/view/main_window_screen.dart) הפונקציה `_handleExternalActivationUriString`:

1. מנסה לפענח דרך `ExternalUriRouter.parseUri`. אם `null` — מתעלמת בשקט.
2. מציפה את החלון לפני־כל (`_bringWindowToFront`) ב‑Windows/Linux/macOS.
3. `_dispatchExternalUriAction` עם `switch` יחיד על ה‑sealed class:
   - **`OpenScreenAction`** — שולח `NavigateToScreen` ל‑NavigationBloc.
   - **`OpenToolAction`** — קורא ל‑[`openToolTabById`](../lib/tools/open_tool_tab.dart), שפותח `ToolTab` דרך `OpenOrFocusTab` ומנווט ל‑`Screen.reading`. ה‑`dedupeKey` (`tool:<id>`) ממקד כרטיסיה קיימת במקום להכפיל. אין תור pending ואין retry — כשמערכת התוספים עדיין נטענת הכרטיסיה נפתחת אופטימיסטית ו‑`ToolTabScreen` מציג טעינה.
   - **`OpenPluginAction`** — זהה ל‑`OpenToolAction`: `openToolTabById(pluginId)`. תוסף שלא נמצא, מושבת, מוסתר מהממשק או חסום במצב מנותק — מציג `UiSnack.showError` עם הסיבה המדויקת ([`lookupTool`](../lib/tools/tool_catalog_entry.dart)).
   - **`OpenToolsLauncherAction`** — פותח את פאנל הכלים דרך `ToolsLauncherController.instance.open()`, בלי לנווט.
   - **`OpenSettingsTabAction`** — שולח `NavigateToScreen(Screen.settings)`. אם `tab != null` — קורא ל‑`_settingsScreenController.openTab(tab)` לניווט לטאב הרצוי.
   - **`OpenHistoryAction`** — פותח `HistoryDialog` דרך `showDialog`.
   - **`OpenBookmarksAction`** — פותח `BookmarksDialog` דרך `showDialog`.
   - **`OpenBookAction`** — `await DataRepository.instance.library`, מחפש לפי `b.id`. אם נמצא — `openBook(context, book, index ?? 0, searchQuery ?? '', markSection: markSection, markText: markText)`. אם לא — `UiSnack.showError`.
   - **`RunSearchAction`** — יוצר `SearchingTab` חדש עם הקוורי, מוסיף ל‑`HistoryBloc` ול‑`TabsBloc`, ומנווט ל‑`Screen.search`. ה‑`UpdateSearchQuery` מופעל אוטומטית מ‑`TantivyFullTextSearch.initState` ברגע שהלשונית מוצגת.
   - **`ShowInfoAction`** — `AppInfoService.collect` ואז `showAppInfoDialog`. אין ניווט ואין שינוי מצב. הדיאלוג נדחה לפוסט‑פריים ואינו מומתן, משתי סיבות: המתנה לסגירתו הייתה חוסמת את `_processPendingExternalActivations` (שמתנקז רק בעקבות אירוע קובץ, כך ש‑URI שנכנס בזמן שהפופאפ פתוח לא היה מטופל), וה‑`Navigator.pop` של דיאלוג איתור מקורות היה סוגר את הפופאפ הזה במקום את עצמו.
   - **`InstallPluginAction`** — `InstallRemotePluginRequested` ל‑PluginSystemBloc (ללא ניווט).
   - **`InstallLocalPluginAction`** — `InstallPluginRequested(archivePath)` ל‑PluginSystemBloc. הדיאלוג נפתח אוטומטית דרך `BlocListener` כשמתקבל `PluginSystemInstallRequiresPermissions`.

## הוספת יעד חדש

נניח שרוצים להוסיף `otzaria://open/myfeature` שיבצע פעולה חדשה לגמרי.

### 1. הגדרת פעולה בראוטר

אם זו פעולה חדשה (לא מסך/כלי/ספר), צור variant חדש ב‑`sealed class ExternalUriAction`:

```dart
class OpenMyFeatureAction extends ExternalUriAction {
  const OpenMyFeatureAction();
}
```

ועדכן את `_parseOpen` ב‑[`lib/core/external_uri_router.dart`](../lib/core/external_uri_router.dart) להחזיר אותו:

```dart
if (firstLower == 'myfeature') {
  return const OpenMyFeatureAction();
}
```

אם זה כלי מובנה חדש — מספיק להוסיף alias ב‑`_toolAliases`:

```dart
'myalias': 'builtin.my_tool_id',
```

### 2. דיספצ׳ר

ב‑[`main_window_screen.dart`](../lib/navigation/view/main_window_screen.dart) ב‑`_dispatchExternalUriAction`, הוסף `case`:

```dart
case OpenMyFeatureAction():
  // לוגיקת הפתיחה כאן
  return true;
```

הקומפיילר אוכף exhaustive matching על ה‑`sealed class`, אז אם תשכח להוסיף — תקבל שגיאת קומפילציה.

### 3. בדיקות

הוסף ב‑[`test/core/external_uri_router_test.dart`](../test/core/external_uri_router_test.dart) מקרי בדיקה — כתובת תקינה, כתובות שאמורות להידחות, ובדיקת case‑insensitivity.

### 4. עדכון תיעוד

הוסף שורה לטבלת ה‑"כתובות נתמכות" במסמך זה.

## אבטחה ושיקולי שימוש

- **אין התקנה אוטומטית של תוספים ללא אישור משתמש.** גם עם `overwrite=true`, המשתמש רואה את שמות הקבצים והרשאות התוסף לפני ההתקנה בפועל.
- **`plugin/install` (הורדה מרשת)** מקבל רק `url=` בסכמת `http`/`https` — `file://` וכל סכמה אחרת נדחות בכוונה.
- **`plugin/install-local` (קובץ מקומי)** מקבל `path=` שחייב להיות **נתיב מוחלט**, להסתיים ב‑`.otzplugin`, ואינו נתיב UNC/התקן (`\\server\share`, `\\.\`, `\\?\`, `//host`). מאחר שקישור `otzaria://` ניתן להפעלה מדף אינטרנט, החסימה מונעת קריאת קובץ שרירותי מהדיסק, שימוש בנתיב יחסי בלתי-צפוי (הנפתר מול תיקיית העבודה), ודליפת אישורי SMB בעצם הגישה לנתיב.
- **`otzaria://info` אינו ערוץ יציאה.** הדוח נאסף ומוצג בפופאפ מקומי בלבד — הוא אינו נשלח לשום מקום, ו-`_parseInfo` קורא רק `limit=` ו-`files=` (בשונה מ-`plugin/install`, אין כאן `callback=`/`token=`). דף אינטרנט יכול לפתוח את הפופאפ אבל לא לקרוא את תוכנו; ההוצאה היחידה היא העתקה שהמשתמש יוזם בעצמו. הפעולה היא קריאה בלבד ואינה משנה שום מצב באפליקציה.
- **מקטע `folders` סורק את הדיסק, ולכן הוא היחיד ש-URI חיצוני יכול לגרום לו לעבוד קשה.** התיקיות הן אלו שהמשתמש הגדיר בלבד — אין כאן פרמטר נתיב שדף אינטרנט יכול לכוון לתיקייה שרירותית — והסריקה עצמה מוגבלת: עומק (`maxDepth`) חוסם לולאות junction, ותקרת רשומות לתיקייה (`maxEntriesPerFolder`) חוסמת תיקייה חריגה ומסמנת `scanTruncated`. `files=` נחסם ב-500 כדי שדף לא יבנה פופאפ ענק. הפעולה נשארת קריאה בלבד: אין כאן `stat`+פתיחה של תוכן קובץ, למעט חלון הכותרת של ‎.xml‎/‎.wbk‎ שנדרש כדי לא לספור קובצי הגדרות כספרים. **`--out=` של ה-CLI כן כותב לקובץ — אבל הוא אינו נגיש מכתובת `otzaria://`:** שני הפרסרים בודקים רק את הארגומנט הראשון, ובהפעלת URI הוא תמיד מתחיל ב-`otzaria:`, כך שאין כאן primitive של כתיבת קובץ שרירותי מהרשת.
- **`otzaria://info` הוא הקישור הראשון שמריץ תהליך** (`whoami`/`id` לזיהוי סוג החשבון). שמות ההרצה מוסמכים לנתיב מוחלט — `%SystemRoot%\System32\whoami.exe` ו-`/usr/bin/id` — כי `Process.run` עם שם לא מוסמך מחפש קודם בתיקיית ה-exe וב-CWD, ובהתקנה פר-משתמש התיקייה כתיבה למשתמש. כמו כן פופאפ מידע אחד פתוח חוסם פתיחת נוספים, כדי שדף לא יערים עשרות פופאפים.
- **קישור ל‑URL לא קיים** (למשל `otzaria://open/banana`) פשוט מוחזר `null` ואוצריא מתעלמת בשקט. אין הודעת שגיאה — זה עיצובית מכוון, כדי לא להפחיד משתמשים שלחצו על קישור עתידי.
- **קישור לספר עם ID לא קיים** מציג `UiSnack.showError` בעברית. זאת בכוונה כדי שהמשתמש יבין שהקישור לא תקף בספרייה שלו.

## קבצים מרכזיים

| קובץ | תפקיד |
|--------|--------|
| [`lib/core/external_uri_router.dart`](../lib/core/external_uri_router.dart) | ראוטר אחיד + sealed `ExternalUriAction` (כולל `OpenTool`/`OpenScreen`/`OpenSettingsTab`/`OpenHistory`/`OpenBookmarks`/`OpenBook`/`InstallPlugin`) |
| [`lib/plugins/services/plugin_store_link_parser.dart`](../lib/plugins/services/plugin_store_link_parser.dart) | פענוח פנימי של `plugin/install` (משמש את הראוטר) |
| [`lib/core/info/info_topic.dart`](../lib/core/info/info_topic.dart) | `InfoTopic` — נושאי `otzaria://info/<topic>`, ה‑aliases והפריסה של `all` |
| [`lib/core/info/app_info_service.dart`](../lib/core/info/app_info_service.dart) | `AppInfoService` — איסוף דוח המידע (`AppInfoReport`), מקטע‑מקטע ועמיד לכשלים |
| [`lib/core/info/personal_folders_info.dart`](../lib/core/info/personal_folders_info.dart) | `PersonalFoldersInfo` — מקטע `folders`: קריאת התיקיות מההגדרות וסריקת קובצי הספרים שבהן |
| [`lib/core/info/app_install_timeline.dart`](../lib/core/info/app_install_timeline.dart) | רישום/קריאה של תאריך ההתקנה, תאריך העדכון והגרסה הקודמת |
| [`lib/core/info/system_account_info.dart`](../lib/core/info/system_account_info.dart) | זיהוי סוג חשבון המשתמש (מנהל/רגיל) וריצה elevated |
| [`lib/core/info/error_log_reader.dart`](../lib/core/info/error_log_reader.dart) | קריאה ופענוח של קובצי הלוג לרשומות השגיאה האחרונות |
| [`lib/core/info/app_info_cli.dart`](../lib/core/info/app_info_cli.dart) | `otzaria info` — פקודת headless שמדפיסה את הדוח כ-JSON ל-stdout |
| [`lib/core/cli_command.dart`](../lib/core/cli_command.dart) | `normalizeCliCommand` — נרמול שם פקודת CLI, חייב להישאר זהה ל-`IsCliInvocation` |
| [`lib/core/info/settings_snapshot.dart`](../lib/core/info/settings_snapshot.dart) | קריאת הגדרות המשתמש מתצלום, בלי להתנגש במנעול Hive של המופע הגרפי |
| [`lib/core/info/view/app_info_dialog.dart`](../lib/core/info/view/app_info_dialog.dart) | הפופאפ המעוצב + `showAppInfoDialog` |
| [`lib/core/info/view/info_section_fields.dart`](../lib/core/info/view/info_section_fields.dart) | תוויות השדות בעברית, סדר התצוגה ועיצוב הערכים |
| [`lib/plugins/services/plugin_protocol_registration_service.dart`](../lib/plugins/services/plugin_protocol_registration_service.dart) | רישום דינמי של סכמת `otzaria://` ב‑Windows ובלינוקס בזמן ריצה |
| [`lib/core/external_activation_queue.dart`](../lib/core/external_activation_queue.dart) | תור JSONL להעברת URIs בין מופעים |
| [`lib/core/external_activation_channel.dart`](../lib/core/external_activation_channel.dart) | ערוץ פלטפורמה ל‑URIs שמגיעים בזמן ריצה (Android/iOS) |
| [`lib/navigation/view/main_window_screen.dart`](../lib/navigation/view/main_window_screen.dart) | מאזין, פענוח ודיספצ׳ר (ראה `_handleExternalActivationUriString` ו‑`_dispatchExternalUriAction`) |
| [`lib/settings/view/settings_screen.dart`](../lib/settings/view/settings_screen.dart) | מגדיר `SettingsTab` enum ו‑`SettingsScreenController` לניווט לטאב |
| [`lib/history/view/history_screen.dart`](../lib/history/view/history_screen.dart) | `HistoryDialog` — נפתח דרך `showDialog` |
| [`lib/bookmarks/view/bookmark_screen.dart`](../lib/bookmarks/view/bookmark_screen.dart) | `BookmarksDialog` — נפתח דרך `showDialog` |
| [`lib/tools/open_tool_tab.dart`](../lib/tools/open_tool_tab.dart) | `openToolTab` / `openToolTabById` — פתיחת כרטיסיית כלי בעיון |
| [`lib/tools/tool_catalog_entry.dart`](../lib/tools/tool_catalog_entry.dart) | `buildToolCatalog` / `lookupTool` — קטלוג הכלים וסיבות אי-זמינות |
| [`windows/runner/main.cpp`](../windows/runner/main.cpp) | זיהוי single‑instance + העברת ארגומנטים לתור (לא רישום); `IsCliInvocation` מזהה `pack-plugin` ו‑`info` ומריץ אותם headless |
| [`test/core/external_uri_router_test.dart`](../test/core/external_uri_router_test.dart) | בדיקות הראוטר האחיד |
| [`test/core/info/`](../test/core/info/) | בדיקות נושאי המידע, ציר הזמן, זיהוי החשבון, פענוח הלוג, חוזה ה-JSON, ה-CLI והפופאפ |
| [`test/core/cli_command_test.dart`](../test/core/cli_command_test.dart) | אכיפת שקילות הנרמול מול `IsCliInvocation` ב-`main.cpp` |
| [`test/plugins/services/plugin_store_link_parser_test.dart`](../test/plugins/services/plugin_store_link_parser_test.dart) | בדיקות פרסר התקנת תוסף |
