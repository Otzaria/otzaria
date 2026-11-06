# מדידות ביצועים שחזוריות

לתרחיש WebView ייעודי בחמש מערכות, כולל הסתרה, חידוש, כמה מופעים ורקע,
ראו [WEBVIEW_RESOURCE_PROBE.md](WEBVIEW_RESOURCE_PROBE.md). הוא נפרד מתרחיש
האפליקציה הכללי המתואר כאן ומסמן במפורש מדדים שאינם זמינים.

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
