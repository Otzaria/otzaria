# מדידות ביצועים שחזוריות

לתרחיש WebView ייעודי בחמש מערכות, כולל הסתרה, חידוש, כמה מופעים ורקע,
ראו [WEBVIEW_RESOURCE_PROBE.md](WEBVIEW_RESOURCE_PROBE.md). הוא נפרד מתרחיש
האפליקציה הכללי המתואר כאן ומסמן במפורש מדדים שאינם זמינים.

למדידת החימום המוקדם של WebView ב־Android, ראו את
[התרחיש הייעודי בהמשך](#android--חימום-מוקדם-ועלייה-במסלול-האפליקציה).

הפקודה הראשית היא `run_perf_probe.ps1`. היא בונה את יעד האינטגרציה פעם אחת,
מכינה ספרייה סינתטית בתהליך נפרד, ומריצה את האפליקציה בתהליכים חדשים עם
נתונים מבודדים. הקוד נמצא ביעד הבדיקה בלבד: אין טיימרים, דוגמים או איסוף
נוספים בבינארי הרגיל של משתמשי האפליקציה.

## הרצה ב-Windows

דרושים PowerShell 7.4 ומעלה, Git, Flutter בגרסה הנעולה ב-CI, ותלויות הבנייה
הרגילות של האפליקציה ל-Windows x64. סגור מופע קיים של אוצריא לפני ההרצה,
בגלל מנגנון single-instance של הבינארי. אין צורך בספרייה מותקנת.

```powershell
# מתוך שורש המאגר; הנתיב לפלט חייב להיות חדש.
pwsh -File tool/perf_probe/run_perf_probe.ps1 `
  -Mode profile -CacheState cold -Warmup 1 -Repetitions 5 -Launches 3 `
  -OutputDirectory C:\perf\baseline-cold

pwsh -File tool/perf_probe/run_perf_probe.ps1 `
  -Mode profile -CacheState warm -Warmup 1 -Repetitions 5 -Launches 3 `
  -OutputDirectory C:\perf\baseline-warm
```

ברירת המחדל היא `profile`, חימום אחד, חמש חזרות לכל פעולה ושלוש הפעלות
נמדדות של התהליך. `-Launches` קובע גם את מספר דגימות העלייה; מספר דגימות
הפעולות גדול יותר. כל חימום מתועד אך אינו נכנס לאחוזוני המדידה.
פלט ברירת המחדל נשמר בתיקייה ייחודית תחת `build/perf_probe`.
`-TimeoutSeconds` מגביל כל הפעלה (ברירת מחדל: 1,200 שניות); כשל או timeout
שומרים פלט חלקי ומחזירים קוד יציאה שאינו אפס. אין סף ביצועים שמעביר או
מכשיל הרצה.

| אפשרות | משמעות |
|---|---|
| `-Mode debug` | אבחון פונקציונלי; אין להשוות את זמניו ל-profile/release |
| `-Mode profile` | מסלול המדידות הרגיל; Dart heap זמין רק אם VM service זמין בפועל |
| `-Mode release` | אותו יעד בדיקה נבנה ב-release ומופעל ישירות; אין תלות ב-flutter drive או ב-VM service |
| `-CacheState cold` | שורש נתוני אפליקציה חדש לכל הפעלה, עם fixture מוכן וללא אינדקס קודם |
| `-CacheState warm` | הכנת fixture, הפעלה מלאה שאינה נספרת, ואז הפעלות חדשות על אותם נתונים ואינדקס |
| `-HardwareId` | מזהה קבוע לבעל מחשב שמנהל מדידות; כברירת מחדל נגזר fingerprint מקומי יציב |

**Cold אינו disk-cold.** הכנת הקלט עצמה קוראת וכותבת לדיסק. הכלי אינו מרוקן
מטמון מערכת הפעלה, אינו משנה power plan ואינו מדמה אתחול מחשב. Warm מתייחס
לנתונים ולמטמוני הדיסק הקיימים; כל הפעלה מקבלת Dart VM ותהליך חדשים.

הספרייה כוללת שלושה ספרים סינתטיים עם 128, 4,096 ו-65,536 שורות, שאילתת
חיפוש קבועה ותוסף HTML מקומי שאינו מבצע בקשות רשת. SHA-256 של קובצי הקלט
נשמר ב-fixture marker ובמטא-נתונים. שינוי בקלט, ניסיון להשתמש בתיקייה קיימת
ללא marker, או ניסיון לערבב את תיקיית הפלט עם תיקיית הנתונים מכשילים את
ההרצה. אינדקס, הגדרות, הערות, טאבים וגיבויים מופנים לשורש המבודד. מצב
offline מופעל, עדכונים וסנכרון אוטומטיים כבויים ו-Sentry DSN ריק.

## מה נמדד ובאיזה גבול

| תרחיש | תחילת וסיום המדידה |
|---|---|
| `startup.window_useful` | `app.main()` עד reveal המתועד ב-`StartupTimeline` |
| `startup.first_content` | קריאה ל-`app.main()` עד הצגת שורה בספר הקצר |
| `book.short/medium/long.open` | יצירת טאב עד טעינת השורה, חיבור ה-controller והופעתה במיקום הגלוי |
| `book.*.scroll` | 60 צעדי גלילה בני 30 פיקסלים, עם pump לכל צעד; זמן תרחיש גלילה קבוע |
| `book.*.jump_forward/jump_backward` | קפיצה ל-75% ול-10% מהספר, בנפרד, עד שהשורה המבוקשת טעונה וגלויה |
| `book.*.close` | הסרת הטאבים ועדכון העץ, כולל המתנה ל-dispose הנצפה של TextBookBloc/SearchBloc |
| `search.normal` | חיפוש exact קבוע עם עד 100 תוצאות, עד תוצאות לא ריקות וסיום טעינה וספירה |
| `search.while_indexing` | אותו חיפוש כשפעולת אינדוקס אמיתית פעילה; אין תוצאה אם לא אומתה חפיפה |
| `notes.open/edit/caret/close` | העורך האמיתי: פתיחה, שינוי תוכן ב-Quill, תנועת סמן וסגירה |
| `plugin.open/close` | תוסף מקומי דרך מסלול התוספים האמיתי, עד readiness של DOM/paint וסגירת הטאב |
| `pdf.preview_first_page/preview_close` | מסך ההדפסה האמיתי עד תמונת העמוד הראשון, ולא המתנה קבועה של 20 שניות |
| `lifecycle.tabs_cycle` | פתיחת ספרים, מעבר טאב וסגירה במחזורים חוזרים |
| `lifecycle.idle_after_close` | חלון תצפית קבוע של שנייה אחרי סגירה; משכו אינו latency של פעולה |

הזמנים הם עד תנאי מוכנות עסקי או UI שנבדק בקוד, עם רזולוציית polling של
16ms. הם אינם מדידת input-to-photon. זמני בנייה ורינדור של פריימים נאספים
בנפרד. גם מדדי העלייה מתחילים בתוך harness שכבר אתחל את Flutter binding;
הם **אינם** זמן מהפעלת קובץ ההפצה עד הפריים הראשון, ואינם כוללים native/engine
startup. לא מוסיפים את זמן הכנת ה-fixture לזמן העלייה.

תנאי מוכנות שלא התקיים מסתיים בכשל, עם timeout מפורש. דילוג מפורש מקבל
`status: skipped` וסיבה; הוא אינו תוצאה מהירה או מוצלחת. אינדוקס שהסתיים
לפני החיפוש או במהלכו אינו מוצג כמדידת חיפוש בזמן אינדוקס.

### מדדים

- latency: דגימות גולמיות לכל שלב, `p50/p95/p99`, מינימום, ממוצע ומקסימום.
- פריימים: `buildDuration`, `rasterDuration`, `totalSpan` ומספר פריימים.
  השיוך נעשה לפי timestamps של המנוע, לא לפי זמן הגעת callback באצווה.
  ההמתנה לקבלת האצווה אינה נכללת ב-latency. איסוף שנחתך מדווח ואינו מפיק
  אחוזוני פריימים כאילו היה מלא.
- RSS: לפני ואחרי הפעולה ושיא שנדגם כל 250ms. זהו שיא דגימה, לא שיא כל
  ההקצאות שהתרחשו בין שתי דגימות.
- Dart heap: שימוש, קיבולת, external memory ומספר isolates, מחוץ לחלון
  הפעולה וללא GC כפוי. `release`, שירות VM חסר או דגימה שנכשלה מניבים `null`
  עם סיבה, ולא אפס.
- Windows: CPU מצטבר, working set, private commit, handles, threads ומספר
  תהליכים בעץ; דגימה כל 500ms וגילוי עץ כל 2s. זהות תהליך היא PID יחד עם
  זמן יצירתו. אין שיוך תהליך שנולד לפני ההורה הנוכחי, ואין צירוף מוני CPU
  של תהליכים שונים שקיבלו אותו PID.
- CPU מחושב רק בין דגימות בעלות זהויות תואמות בתוך גבולות השלב. 100% הם
  ליבה אחת; ערך העץ יכול לעבור 100%. כיסוי חלקי או churn מוצגים כחסר מדידה
  מלאה. תהליכים קצרים משך הדגימה עלולים לא להיראות כלל.
- מוני אפליקציה: מספר טאבים, פריטי עבודה במצב running, האם מתבצע אינדוקס,
  ו-transient callbacks של scheduler. אלה אינם אומדן של כל העבודה הפנימית.

Private commit הוא זיכרון פרטי של התהליך, כולל זיכרון מנוהל; אינו
native-only memory. גם הפרש RSS פחות Dart heap אינו מדד native מהימן, ולכן
הכלי אינו מחשב אותו. working set מסוכם של תהליכים יכול לספור דפים משותפים
יותר מפעם אחת. הצגת שיא handles אינה כשלעצמה הוכחה לדליפה.

האחוזונים משתמשים ב-nearest-rank: האיבר `ceil(p*n)-1` ברשימה ממוינת.
במדגם קטן, ובפרט שלוש הפעלות startup, `p95/p99` בדרך כלל הם המקסימום שנצפה;
הם אינם אומדן יציב של זנב ההתפלגות. הדוח מציג `n` ואזהרה מתאימה. אין
ממוצע של אחוזונים: אחוזוני הפריימים מחושבים מהדגימות הגולמיות.

## מגבלות מפורשות

- פתיחה וסגירה של חלונות native נוספים מסומנות `skipped`. האפליקציה דורשת
  `hasRealPlatformDispatcher()` לצורך `installWindowingOwner`; binding הבדיקה
  משתמש ב-`TestPlatformDispatcher`. עקיפת השומר יכולה להעביר engine ID מדומה
  ל-FFI ולקרוס. לצורך אבחון זה יש להריץ את האפליקציה הרגילה עם
  `--dev-diagnostics=log`; אין לערבב את נתוניה עם התרחיש האוטומטי.
- עומקי התורים הפנימיים המלאים אינם חשופים ב-API יציב. `queues.depth`
  מסומן `skipped`; מוני העבודה הפעילה נשמרים בנפרד.
- אין כאן מדידת GPU, native allocations לפי allocator, או pre-main startup.
- הדוגם וה-runner האוטומטי מיועדים ל-Windows x64. המנתח ובדיקות החוזה ניידים;
  אין להציג תוצאות Windows כאילו נמדדו ב-macOS, Linux או מכשיר נייד.
- תוסף HTML סינתטי, מסד נתונים קטן ומבנה טקסט קבוע עוזרים לשחזור אך אינם
  תחליף למדידה עם קלט אמיתי כשחוקרים באג תלוי ספר או תוסף מסוים.

## דוחות ו-baseline בין commits

כל הרצה שומרת `manifest.json`, יומן `phases.jsonl`, דגימות `samples.csv`,
דוחות `report.json` ו-`report.md`, לוגי build והרצה, ותיקיות נפרדות לכל
launch. פלטי הכנת הנתונים והפעלת החימום של warm נשמרים לצורכי חקירה, אך
אינם מצורפים לנתונים הנמדדים. שגיאות דגימה נשמרות ב-
`samples.csv.errors.jsonl`. פלט חסר או הרצה שנכשלה נשארים זמינים לאבחון.

להשוואה, הרץ את שני הקומיטים על אותו מחשב, עם אותו SDK, מצב בנייה,
מצב cache, viewport, הגדרות, קלט ומספר חזרות. השתמש ב-checkouts נקיים
ובגרסת protocol זהה. אפשר להשתמש בשני `git worktree` או להחליף קומיט אחרי
סיום כל הרצה. שמור את תוצאות ה-baseline מחוץ לתיקייה שתחליף.

```powershell
# לאחר מעבר לקומיט המועמד, עם אותה תצורה כמו baseline-cold:
pwsh -File tool/perf_probe/run_perf_probe.ps1 `
  -Mode profile -CacheState cold -Warmup 1 -Repetitions 5 -Launches 3 `
  -OutputDirectory C:\perf\candidate-cold `
  -Baseline C:\perf\baseline-cold

# ניתוח מחדש אינו מפעיל את האפליקציה ואינו דורש ספרייה או native build.
dart tool/perf_probe/analyze.dart C:\perf\candidate-cold `
  --baseline C:\perf\baseline-cold\report.json
```

מותר להריץ על עץ עם שינויים לצורכי פיתוח, אך הוא מסומן `dirty` ואינו baseline
תקין להשוואה אוטומטית. כשל, העדר סיום של launch, סתירה במטא-נתונים, שינוי
חומרה/SDK/fixture/protocol/תצורה או שגיאות sampler חוסמים השוואה מספרית.
הדוח מסביר את הסיבה. מדד חסר אינו מוחלף באפס, ושינוי באחוזים אינו מחושב
מ-baseline ששווה אפס. הבדלי זמני ריצה אינם גורמים לקוד יציאה של כשל.

ה-baseline נוצר מהרצה אמיתית ונשמר מחוץ למקורות. אין במאגר baseline מספרי
מומצא, ואין מספרי ביצועים אוניברסליים שאמורים להתאים לכל חומרה.

## CI ובדיקות

ה-workflow `Performance probe tools` מריץ ב-PR רק בדיקות חוזה של PowerShell,
ללא דגימת חומרה או ספי זמן. בדיקות Dart של הדוח, ה-fixture וה-recorder הן
בדיקות תקינות רגילות. המדידה המלאה ב-Windows מופעלת רק ב-`workflow_dispatch`;
היא מעלה גם תוצאות חלקיות כ-artifact ואינה required performance check.
מחשבי GitHub hosted מקבלים מזהה שונה בכל run, כך שלא תוצג השוואה מטעה בין
שתי מכונות אירוח שונות. עבור השוואת commits השתמש באותו מחשב מקומי.

```powershell
pwsh -File tool/perf_probe/test_sample_resources.ps1
flutter test test/tool/perf_probe/
flutter analyze --no-pub
```

### התאמה לתשתיות שכבר קיימות

| תשתית קיימת | תפקידה |
|---|---|
| `StartupTimeline` | מקור reveal/phases של bootstrap; נעשה בו שימוש בלי לשנות production |
| `DeveloperDiagnostics` | אבחון opt-in של האפליקציה הרגילה: context, פריימים, startup וזיכרון |
| `reader_scroll_probe_test.dart` | חקירת גלילה עם ספרייה מותקנת ומוני SmartText |
| `memory_retention_probe_test.dart` | חקירת הקצאות ו-GC; אינו אותו ניסוי latency ללא GC |
| `pdf_real_file_open_probe.dart` | בדיקת פתיחת PDF אמיתי; נשאר כלי נפרד |
| `perf_resource_probe_test.dart` | התרחיש השחזורי המבודד המתואר כאן |

העברת `-Target` מפורש ליעד ישן ב-`run_perf_probe.ps1` משאירה את מסלול האבחון
הישן לצורכי תאימות. הוא משתמש בספרייה המותקנת, חולק קובצי temp, ומגבה רק
חלק מקובצי Hive; אין להריצו במקביל או על פרופיל שלא ניתן לשחזר מגיבוי מלא.
קלט זה מזוהה כ-legacy במנתח ואינו baseline. ברירת המחדל החדשה אינה משתמשת
במסלול זה או בנתוני המשתמש.

מקורות להגדרות המדידה: [Flutter profiling](https://docs.flutter.dev/cookbook/testing/integration/profiling),
[FrameTiming](https://api.flutter.dev/flutter/dart-ui/FrameTiming-class.html),
[batching של addTimingsCallback](https://api.flutter.dev/flutter/scheduler/SchedulerBinding/addTimingsCallback.html),
[Windows PrivateMemorySize64](https://learn.microsoft.com/en-us/dotnet/api/system.diagnostics.process.privatememorysize64).

## Android — חימום מוקדם ועלייה במסלול האפליקציה

`android_startup_probe.py` בונה APK אחד ומפעיל אותו שוב בתהליכים חדשים, עם
תצורה שנמסרת ל־Dart באמצעות `dart_entrypoint_args`. נדרשים Python 3.11 ומעלה,
Flutter בגרסת ה־CI, כלי הבנייה הרגילים ל־Android, Rust וה־target המתאים
למכשיר, `adb` ו־`aapt2` מתוך Android SDK. למדידות משתמשים במכשיר פיזי
וב־`profile`; `debug` באמולטור מיועד לבדיקת התרחיש בלבד.

```sh
# מתוך checkout נקי; הפלט חייב להיות בתיקייה חדשה או ריקה.
python3 tool/perf_probe/android_startup_probe.py \
  --device DEVICE_SERIAL --mode profile --repetitions 5 --observation-ms 5000 \
  --output build/android-startup-profile

# בדיקת חוזים באמולטור — אינה ראיית ביצועים של מכשיר פיזי.
python3 tool/perf_probe/android_startup_probe.py \
  --device emulator-5554 --mode debug --repetitions 2 --observation-ms 1000 \
  --output build/android-startup-debug
```

הכלי בונה את ה־flavor `direct` עם מאפיין Gradle הייעודי
`otzariaStartupProbe=true`. לפני התקנה, הכלי בודק ב־APK עצמו
שה־application ID הוא בדיוק `org.otzaria.otzaria.startupprobe`, שה־Activity
תואם ושהבנייה מאפשרת `run-as`. הוא מפעיל ועוצר רק חבילה קבועה זו; אין
פרמטר לבחירת חבילת משתמש ואין `pm clear`. גם יעד ה־Dart בודק את זהות החבילה
לפני כתיבה. `release` אינו מסלול נתמך כאן, משום שקריאת הדוחות נעשית דרך
`run-as` בלי לשנות הרשאות של אפליקציה רגילה. נתוני התרחיש נשארים בתיקייה
ייחודית בתוך החבילה הייעודית, כך שניתן לבדוק אותם גם לאחר כשל.

### קלט, תרחישים וסדר הרצה

ה־fixture מכין ספרייה סינתטית והגדרות offline בתהליך הכנה נפרד. הוא רושם
תוסף מקומי והרשאותיו במסד התוספים **לפני** הקריאה ל־`app.main()` בתהליך
הנמדד. הכנת הרישום ואימותו רצים ב־isolate קצר שסוגר Hive ו־SQLite, כדי לא
לאתחל מראש את `Settings` של ה־isolate הראשי. המסד נפתח מחדש דרך נתיב
האפליקציה הרגיל; אין רישום תוסף מאוחר
שמפספס את בדיקת `hasEnabledPlugin`. לתוסף אירוע הפעלה ייעודי, ללא
`app.startup`, ולכן תרחישי אי־פתיחה אינם יוצרים WebView ברקע. ה־fixture
מסרב לנתיב לא מוכן, תוכן שהשתנה, תווית שימוש שגויה או symlink.

גרסת `android-startup-v2` מאפסת, אחרי האימות ולפני המדידה, רק סשנים של
חלונות במשבצות חיוביות. כך `force-stop` קודם אינו משחזר לשונית תוסף לפני
הפתיחה המתוזמנת. האיפוס נעשה במסדי `user_state.db` קיימים בלבד, הן בתיקיית
המסדים המוגדרת של ה־fixture והן בתיקיית ה־fallback הפנימית שלו; מסד חסר
אינו נוצר מראש. היסטוריה, הרשאות, רישום התוסף, מטמונים ומונה ההפעלות
נשמרים. הבדיקה דורשת אפס מופעים לפני הפתיחה ובדיוק מופע קדמה אחד אחרי
מוכנותו בתרחישי `foreground` ו־`overlap`. fixture מגרסת `android-startup-v1`
נדחה ומחייב הכנה חדשה.

הספרייה הסינתטית משתמשת ב־`synthetic-v2` ובסימון `settings_initialized`
מהתיקון הציבורי של [#4417](https://github.com/Otzaria/otzaria/pull/4417).
הסימון משמר את הגדרות המדידה בעת טעינת `SettingsRepository` האמיתית,
לרבות ביטול עדכונים ואינדוקס אוטומטי. הכנת הקבצים אינה מאתחלת את
`Settings` ב־isolate הראשי. נתונים מהגרסה הקודמת נדחים ומחייבים הכנה חדשה.

| תרחיש | פעולה נמדדת |
|---|---|
| `noEnabled` | עלייה ללא תוסף פעיל, ללא פתיחת WebView; שער הזכאות האמיתי צריך לדלג על החימום |
| `noOpen` | עלייה עם תוסף פעיל, ללא פתיחה; מאפשר השוואת עלות זיכרון host של חימום מוקדם |
| `foreground` | פתיחת לשונית התוסף דרך `TabsBloc` ו־`PluginTabPage`, עד SDK אמיתי ושני callbacks של rAF |
| `background` | מסירת אירוע ייעודי דרך ה־dispatcher וההפעלה העצלה, עד SDK אמיתי וקבלת `runId` של ההרצה |
| `overlap` | בקשת פתיחה מיד כשנתיב החימום האמיתי נצפה; `notObserved` אם כבר הסתיים, בלי לעכב אותו מלאכותית |

כל תרחיש רץ פעם עם `native` ופעם עם `bypass`, בסדר AB ואחריו BA לסירוגין.
בשני המצבים פועלים `main.dart`, שער התוספים, ה־coordinator ומחסומי ההמתנה
של המארח הקיימים. `native` עוטף את קריאת `WebViewEnvironment.prewarm`
האמיתית לצורכי תיעוד; `bypass` משתמש בנקודת הבדיקה הקיימת לדילוג מתועד
על הקריאה בלבד, ואינו מתואר כחימום מוצלח. אין שינוי ב־ProcessGlobalConfig,
ב־AndroidX WebKit 1.14.0, בברירת המחדל של הגדרות Android, או ב־timeout של
30 שניות. אין השהיה או ביטול של פעולת החימום כדי לייצר חפיפה.

ולידטור המארח דורש בתרחישי foreground/overlap חשיפה ראשונית ללא לשונית,
ובסיום בקר foreground יחיד התואם למופע שנפתח, ללא בקרי רקע. דוח עם
לשונית משוחזרת או בקר נוסף נדחה גם אם מסגרת הבדיקה דיווחה הצלחה.

ההפעלה הראשונה של כל fixture מסומנת `prepared`, והבאות `reused`. אלו
תוויות היסטוריית הנתונים המבודדים בלבד: אימות SHA-256 וקריאת רישום התוסף
מחממים מטמון קבצים עוד לפני `app.main()`. מטמוני מערכת ההפעלה, ה־provider
ונתוני WebView של החבילה הייעודית משותפים בין ההפעלות ואינם נמחקים.
הפסקת התהליך הקודם, PID ו־boot ID נבדקים ונשמרים; תהליך חדש אינו דיסק או
provider קרים. להכנה אין `app.main()` ואין קריאה לחימום מוקדם.

### משמעות הדוח ומגבלות המדידה

`StartupTimeline.revealMs` מתחיל בתוך `main` ומסתיים ב־reveal. הוא אינו כולל
את כל הזמן מלפני Dart או עבודה אחרי reveal. `revealObservedAtUs` נמדד
בנפרד מהקריאה ל־`app.main`, באמצעות polling; אין לאחד את שני השעונים.
הדוח שומר גם את מצב reveal ברגע כניסת החימום, כדי לזהות מסלול fallback
שהחל לפני reveal. `am start -W` נשמר כנתון Android נפרד ואינו מדד למוכנות
התוסף. מדדי controller/SDK הם זמן עד **תצפית** במוכנות, עם polling של 16ms
ופקודות JavaScript רק במהלך הפתיחה. בתרחישי אי־פתיחה אין polling ב־JS
ונבדק שמספר מארחי foreground/background הוא אפס.

לפני תחילת המדידה נפתח חיבור TCP יחיד דרך `adb reverse` עם פורט שהוקצה
להרצה. אותו מספר פורט מפורש משמש ב־listener של המארח ובמכשיר, עם
`--no-rebind`, כך שמפתח הבעלות תואם גם לרשימת ההרשאות של ADB. התנגשות
בפורט גורמת לבחירת listener חדש, עד שמונה ניסיונות לפני הפעלת האפליקציה;
מיפוי קיים נשאר שלם. הפורט המפורש מונע השארת מפתח `tcp:0`
ב־[רשימת ההרשאות של ADB](https://android.googlesource.com/platform/packages/modules/adb/+/1cf2f017d312f73b3dc53bda85ef2610e35a80e9/transport.cpp).
גרסת ADB נשמרת מראש ב־`adb-version.txt` ובקמפיין.
בזמן המדידה המארח ממתין בחסימה; האפליקציה שולחת אות רק לאחר כתיבה
אטומית של `ready.json` ושל `completion.json`, ואז המארח קורא את הדוח פעם
אחת דרך `run-as`. האותות כוללים campaign/run/boot/PID; דוח זר, אות כפול,
ניתוק מוקדם או חריגה מהזמן המוקצב מכשילים את ההרצה. אין תשאול קבצים
ב־ADB בזמן המדידה. החיבור הסרק והפורט מוסרים בניקוי של כל הרצה.

`campaign.json` שומר את הכשל הראשון ואת המחסנית שלו. כשלי איסוף logcat,
עצירת התהליך או הסרת החיבור נשמרים בנפרד ב־`cleanupErrors`; הם מכשילים
הרצה שהצליחה, אך אינם מחליפים כשל מדידה קודם.

דגימות Flutter FrameTiming הן הפריימים שנמסרו בתוך החלון, עם מונה חיתוך;
callbacks שמגיעים לאחר הגבול אינם נכללים. הן אינן זמני presentation של
WebView. heartbeat של 100ms מודד את Dart isolate בלבד. ה־rAF של התוסף אינו
input-to-photon. CPU native ותגובתיות thread ה־UI של Android מסומנים
`notCollected`; כדי לאשר אותן נדרשת מדידה נוספת במכשיר, למשל trace מתאים
ב־Perfetto. בדיקת יחידה, Node או אמולטור אינה מחליפה זאת.

לאחר גבול המדידה האפליקציה נשארת חיה וממתינה לאישור ייחודי. בזמן זה הכלי
שומר פלט גולמי של `adb shell dumpsys meminfo -d PID` ומחלץ `TOTAL PSS` רק
כשכותרת הפלט תואמת ל־PID ולחבילה, וה־PID נותר חי. המדד הוא KiB של תהליך
ה־host, עם זמני הדגימה וההשהיה מההשקה. אין שיוך ניחושי של renderer ואין
טענת זיכרון כולל של המנוע. פלט חסר, עמום או זהות שהשתנתה נשמרים כ־`null`
וסיבה; אפס אמיתי נשמר כאפס. הזיכרון יכול להשתנות בין הגבול לדגימת `adb`,
ובפרט כשהחימום עדיין pending. אישור הדגימה נכתב ומפורסם באופן אטומי.

רק **לאחר** המדידה ודגימת הזיכרון נקרא `dumpsys webviewupdate`. אין שאילתת
provider, גרסת UA או feature של WebView לפני המדידה. הדוח שומר גרסת
provider שנצפתה בסוף, fingerprint/ABI/SDK של המכשיר, viewport, גרסאות
Flutter/Dart, commit ומצב העץ, hash של אותו APK, זהות קלט ופלט logcat של
התהליך הנוכחי. אין מנגנון לשינוי provider או לכוונון ספי production.

`campaign.json` כולל את הנתונים הגולמיים וזוגות ההשוואה. `comparableInputs`
חסום כשמקור/חומרה/provider/קלט שונים או לא ידועים, העץ מלוכלך, התהליך
אינו חדש, החימום התחיל לפני reveal, לא נצפתה הצלחה native עד סוף החלון,
או שבתרחיש חפיפה לא נצפתה חפיפה. `hostPssComparableInputs` דורש בנוסף שתי
דגימות host PSS זמינות. כשל provider, `timeout` או API חסר יכולים לשחרר את
ה־coordinator כמתוכנן, אך נשמרים כתוצאות אלו וחוסמים הסקת תועלת מחימום.
אין כאן סף זמן, baseline מספרי או אישור ביצועים אוטומטי;
`physicalDeviceAcceptance` ו־`performanceAcceptance` נשארים `false`.

כל שמונה חבילות ה־WebView נעולות לאותו commit של ה־fork, הכולל את
[תיקון בעלות ה־GlobalKey ב־Android](https://github.com/Otzaria/flutter_inappwebview/pull/56)
ואת [ממשק תצפיות Apple](https://github.com/Otzaria/flutter_inappwebview/pull/55).
כך widget המעטפת וה־PlatformView הילד אינם נרשמים עם אותו GlobalKey,
ותצורת החבילות נשארת אחידה בין הפלטפורמות. אימות האמולטור ב־workflow
נדרש גם לאחר עדכון ה־pin; הצלחת בדיקות החבילה אינה תוצאת ביצועים של האפליקציה.

### בדיקות ו־CI של Android

```sh
python3 -m unittest tool/perf_probe/test_android_startup_probe.py
flutter test --concurrency=1 \
  test/tool/perf_probe/android_startup_protocol_test.dart \
  test/tool/perf_probe/android_startup_fixture_test.dart \
  test/tool/perf_probe/perf_fixture_test.dart \
  test/tool/perf_probe/perf_fixture_startup_settings_test.dart \
  test/plugins/view/webview_android_prewarm_test.dart \
  test/plugins/view/webview_environment_holder_test.dart
```

בדיקות ה־fixture דורשות Node ובודקות גם את קוד JavaScript של התוסף עם
ה־stub וה־SDK הקיימים. בדיקות חוזה נפרדות מאמתות unsupported/error/timeout
ושחרור מחסומי המתנה; הן אינן תוצאות provider במכשיר. ה־workflow
`Android WebView startup contracts` מריץ את חמשת התרחישים בבניית `debug`
על אמולטור API 34 x86_64, בשני סבבי AB/BA, ושומר גם פלט חלקי כ־artifact.
זהו אימות אינטגרציה של הנתיב האמיתי, ללא קבלה של טענות ביצועים במכשיר.

מקורות: [Android: Optimize WebView startup](https://developer.android.com/develop/ui/views/layout/webapps/optimize-webview-startup),
[WebViewStartUpConfig](https://developer.android.com/reference/androidx/webkit/WebViewStartUpConfig),
[ניהול זיכרון WebView](https://developer.android.com/develop/ui/views/layout/webapps/manage-webview-memory),
[מימוש החימום ב־fork הנעול](https://github.com/Otzaria/flutter_inappwebview/blob/ce3a8ba720081d9f0ad1f5dcf77e80a354b97cd8/flutter_inappwebview_android/android/src/main/java/com/pichillilorenzo/flutter_inappwebview_android/webview_environment/WebViewEnvironmentManager.java),
[FlutterActivity: ארגומנטים ל־Dart](https://github.com/flutter/flutter/blob/3.47.7/engine/src/flutter/shell/platform/android/io/flutter/embedding/android/FlutterActivity.java),
[Flutter Gradle: תצורת profile](https://github.com/flutter/flutter/blob/3.47.7/packages/flutter_tools/gradle/src/main/kotlin/FlutterPlugin.kt).
דוגמאות Android העדכניות עשויות להשתמש ב־API חדש יותר; המדידה כאן משתמשת
ב־API הנעול במאגר, עם `setShouldRunUiThreadStartUpTasks(false)`.
