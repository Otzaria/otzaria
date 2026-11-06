# תרחיש משאבים חוזר ל־WebView

`integration_test/webview_resource_probe_test.dart` מפעיל דף HTML סינתטי זהה
ב־Windows, Linux, Android, iOS ו־macOS, באמצעות חבילת ה־WebView הנעולה של
האפליקציה. הוא משלים את תשתית #4112: פתיחה, ריבוי מופעים, גלילה,
הסתרה/חידוש, שחזור מצב ומופע רקע. הדף מקומי ואינו מבצע בקשות רשת.

זהו יעד בדיקה נפרד. הוא אינו מפעיל את האפליקציה, את ה־SDK או את
`PluginRuntimeDispatcher`, ואינו קורא ספרייה, תוספים או הגדרות של המשתמש.
`discardWidget` בודק הסרת widget ו־`recreateAndRestore` בודק שחזור מפורש של
ה־fixture; הם אינם אימות למדיניות הפינוי או לשחזור של תוסף מותקן.
אין שינוי בבינארי האפליקציה הרגיל.

ב־desktop התרחיש חושף במפורש את חלון המארח לפני יצירת ה־WebView הראשון,
מבקש גודל חלון של 1,000×700 יחידות לוגיות וסוגר את ה־splash הנייטיבי.
ב־Windows ו־Linux ה־runner מתחיל בחלון מוסתר; ב־macOS הוא מתחיל שקוף.
הניסוי ממתין, עד עשר שניות, לחלון גלוי שאינו ממוזער ול־alpha=1 ב־macOS.
כשל או timeout מפסיקים את התרחיש. החשיפה וההמתנה אינן נכללות ב־firstOpen.

## הרצה

השתמש ב־Flutter הנעול ב־CI ובתלויות הבנייה הרגילות של הפלטפורמה. הרץ
`flutter pub get --enforce-lockfile` קודם. המסלול האוטומטי הוא profile;
במכשירים ניידים השתמש במכשיר פיזי ולא בסימולטור לצורך השוואת ביצועים.
ראו [הנחיות Flutter למדידות אינטגרציה](https://docs.flutter.dev/cookbook/testing/integration/profiling)
ו[מצבי הבנייה](https://docs.flutter.dev/testing/build-modes).

```bash
# macOS; החלף את macos ב-linux כשמריצים על Linux.
flutter drive --profile -d macos \
  --driver=test_driver/webview_resource_probe.dart \
  --target=integration_test/webview_resource_probe_test.dart \
  --dart-define=WEBVIEW_PROBE_FLUTTER_VERSION=3.47.7 \
  --dart-define=WEBVIEW_PROBE_COMMIT="$(git rev-parse HEAD)" \
  --dart-define=WEBVIEW_PROBE_TABS=3 \
  --dart-define=WEBVIEW_PROBE_IDLE_MS=3000
```

```powershell
# Windows
$probeCommit = git rev-parse HEAD
flutter drive --profile -d windows `
  --driver=test_driver/webview_resource_probe.dart `
  --target=integration_test/webview_resource_probe_test.dart `
  --dart-define=WEBVIEW_PROBE_FLUTTER_VERSION=3.47.7 `
  --dart-define="WEBVIEW_PROBE_COMMIT=$probeCommit" `
  --dart-define=WEBVIEW_PROBE_TABS=3 `
  --dart-define=WEBVIEW_PROBE_IDLE_MS=3000
```

ב־Android וב־iOS בחר מזהה מכשיר מ־`flutter devices`, השתמש באותה פקודה עם
`-d DEVICE_ID` והוסף `--no-dds`. בניית iOS דורשת macOS, Xcode וחתימה מתאימה.
אין צורך להמציא נתיב קבצים של המחשב בתוך sandbox המכשיר: ה־driver מקבל
את `reportData` ושומר אותו במחשב המארח.

| אפשרות | ברירת מחדל ופירוש |
|---|---|
| `WEBVIEW_PROBE_TABS` | 3, בטווח 1–10; מספר מופעי foreground בשלב הריבוי |
| `WEBVIEW_PROBE_IDLE_MS` | 3,000, בטווח 250–60,000; משך חלונות התצפית |
| `WEBVIEW_PROBE_FLUTTER_VERSION` | `unavailable`; מסור את גרסת ה־SDK ששימשה לבנייה |
| `WEBVIEW_PROBE_COMMIT` | `unavailable`; מסור SHA של המקורות שנבנו |
| `WEBVIEW_PROBE_REPORTS` | משתנה סביבה במחשב המארח; ברירת מחדל `build/webview_probe` |
| `WEBVIEW_PROBE_DEVICE_OUTPUT` | נתיב מוחלט אופציונלי במכשיר הנמדד; אחרת תיקיית temp של המכשיר |

ה־driver יוצר תיקיית `run-*` חדשה בכל הרצה ושומר בה `report.json`, גם
כשהבדיקה נכשלת והחיבור למכשיר עדיין זמין. היעד שומר גם `phases.jsonl`
ו־`report.json` בתיקייה חדשה במכשיר ומדפיס `WEBVIEW_PROBE_REPORT` עם נתיבה.
תיקיית WebView2 זמנית ונפרדת נשמרת לצדה ב־Windows. אפשר למחוק את תיקיית
הריצה לאחר יציאת תהליך הבדיקה ושמירת הנתונים הרצויים.
בקריסה או בניתוק מוקדם ייתכן שיש רק יומן חלקי; אין לפרש זאת כהצלחה.

## גבולות התרחיש

| שלב | הפעולה והמשמעות |
|---|---|
| `environment` | יצירת סביבת WebView2 מבודדת ב־Windows; במערכות אחרות מסומן unsupported |
| `firstOpen` | יצירת widget עד טעינת הדף ושני `requestAnimationFrame` בדף הגלוי |
| `visibleIdle` | חלון ללא timers של ה־fixture וללא פניות ל־WebView |
| `multipleOpen` / `multipleIdle` | הוספת מופעים; הקוד מסתיר את הקודם לפני הצגת הבא |
| `scroll` | 60 צעדי גלילה בני 24 CSS pixels מתוך rAF; תשובה אחת לאחר העדכון האחרון |
| `activeHeartbeat` | מונה interval כל 100ms ומונה rAF, ללא הודעות גשר מחזוריות |
| `hide` / `hiddenIdle` | Offstage והפעלת API הפלטפורמה המתאים, ואז המתנה ללא פניות לדף |
| `resume` | החזרה לתצוגה, API חידוש כשנתמך ושני rAF; אימות טיוטה, revision וללא reload |
| `discardWidget` / `recreateAndRestore` | הסרת widget, יצירת מופע חדש ושחזור גרסת snapshot, טיוטה וגלילה |
| `backgroundOpen` / `backgroundIdle` | WebView ב־Offstage בגודל 1×1, שמעולם לא הוצג; אינו runtime ללא DOM |
| `closeWidgets` / `closedIdle` | הסרת כל ה־widgets והמתנה נוספת; אין כאן אישור native disposal או יציאת תהליכים |

ב־Windows רק הצלחת `pause()` מסומנת `suspendConfirmed`; סירוב או API חסר
נשמרים בקוד השגיאה המקורי. ב־Android מדובר ב־`onPause`, שאינו מקפיא את
JavaScript, וב־Linux ב־`setVisible(false)`. ב־Apple מבוצע Offstage בלבד;
הפלט אינו קובע אם WebKit השהה את המנוע בעצמו. אין שימוש ב־`pauseTimers`.

בכל חלון idle אין `evaluateJavascript`, פקודת fixture או בדיקת מוכנות
מחזורית. קריאות הדף מתבצעות רק מחוץ לחלונות האלה. מוני heartbeat נקראים
לפני ההסתרה ואחרי החזרה; הטווח כולל גם את פעולות ההסתרה והחידוש, ולכן
ההפרש אינו מדידה של `hiddenIdle` בלבד. הקריאה למופע הרקע אחרי ההמתנה
מסומנת `readAfterExplicitWake`: עצם הקריאה עשויה להעיר אותו.

יש להשאיר את חלון המארח גלוי במשך הריצה. רשומות `nativeWindow` בודקות את
נראות החלון, מצב המזעור והגבולות הלוגיים לפני ואחרי כל שלב בדסקטופ;
ב־macOS נבדקת גם האטימות. השאילתות נמצאות מחוץ לזמן הפעולה הנמדד ואינן
פונות ל־WebView. מצב שאינו מוכן מכשיל את השלב ואת התרחיש. אלה דגימות גבול,
לא הוכחה לנראות רציפה או להיעדר כיסוי בידי חלון אחר. `document.visibility`
של הדף אינו בדיקת נראות של חלון מערכת ההפעלה. במובייל בדיקת חלון דסקטופ
מסומנת unsupported, וה־viewport הנמדד הוא של המכשיר.

מזעור חלון, מעבר האפליקציה לרקע ושחזור תוסף אמיתי מסומנים `notRun`.
Offstage אינו מדמה פעולות מערכת אלה. המשך אימות Apple נמצא ב־#4120,
והשוואת HWND/composition ותאימות חלונות ב־#4110.

## הפלט והמדדים

`report.json` של ה־driver מכיל `webviewResourceProbe`. `scenarioStatus`
מתאר את גוף התרחיש; קוד היציאה ותוצאת integration_test הם הסמכות להצלחת
הריצה כולה. שלב שהתחיל ונכשל נשמר `failed`; שלבים שלא הגיעו אליהם נשארים
`notRun`. timeout אינו מדידה מוצלחת.

- מטא־נתונים: OS, מספר מעבדים, PID, מצב בנייה, viewport פיזי ו־DPR, גרסת
  Flutter ו־commit שנמסרו, SHA-256 של ה־HTML ופרמטרי התרחיש. נשמר גם UA
  מהדף; ב־Android נאסף provider package וב־Windows גרסת runtime זמינה.
  ב־Apple/Linux יש לצרף את גרסת WebKit/WPE מבחוץ. UA אינו תחליף לגרסה זו.
  ה־viewport נשמר אחרי חשיפת החלון; הגבולות בפלט עשויים להיות שונים מהגודל
  המבוקש בגלל מסגרת החלון, DPI או מגבלות מנהל החלונות.
- latency, RSS ופריימי Flutter נאספים ב־`PerfRecorder` הקיים. זיכרון התהליך
  הנוכחי הוא `ProcessInfo.currentRss` בבייטים, עם שיא דגימה כל 250ms.
  הקלט הגולמי נשמר; אחוזוני `flutterFrameSummary` משתמשים ב־nearest-rank
  ומחזירים null אם אין פריימים או אם האיסוף נחתך. זה אינו זמן ציור של
  WebView או input-to-photon. זמן idle הוא משך חלון, לא latency של פעולה.
- דגימות תהליכים לפני ואחרי שלב נמצאות מחוץ ל־latency, כולל ניקוז אצוות
  פריימים של ה־recorder, וכוללות `sampledAtMs` משלהן. הן אינן רצף דגימות
  CPU או peak memory של כל המנוע.
- ב־Windows המקור הוא private commit; ב־Linux הוא anonymous RSS. הסכמה
  שומרת metric, source, unit ו־scope. אין להשוות את המספרים בין מערכות
  כאילו היו אותו מדד, או לחסר Dart heap מ־RSS כדי לחשב native memory.
- בסכמה 2, `observedProcessCount` סופר את כל התצפיות, כולל PID חסר;
  `measuredProcessCount` ו־`unavailableProcessCount` מפרידים קריאות שהצליחו
  מקריאות חסרות. `observedReadableProcessCount` נשמר ככינוי למספר המדידות
  שהצליחו; גם `webview.<KIND>.count` ביומן האבחון שומר משמעות זו לתאימות.
- `webviewCollection` מתאר את זמינות מקור המנייה בנפרד מהזיכרון. כשמקור
  Windows חסר או נכשל, נשמרים reason, stage ו־HRESULT חתום כשקיימים,
  וה־host עדיין נמדד. הפורק הנעול מחזיר שגיאה מפורשת בכשל מנייה;
  רשימה ריקה מוצלחת מדווחת collected ואפס תצפיות. זיכרון המנוע נשאר
  חסר במקרה זה; אפס תצפיות אינו מדידת אפס זיכרון של המנוע.
- `engineObserved` מסכם רק קריאות שהצליחו. `memoryCoverage` הוא
  `allObserved`, `partial` או `unavailable`; הראשון מתייחס לתצפיות בלבד.
  `complete` נשאר null, וכך גם `engineComplete` ביומן האבחון. ב־Linux,
  כשל בקריאת רשומת stat מסומן גם `webviewCollection.partial`; אין הבטחה
  שסריקת צאצאי WPE גילתה את כל המנוע. אין התאמה של renderer יחיד לכל טאב.
  `webviewCollection.partial` נשאר null כשאין מידע על שלמות מקור המנייה,
  לרבות רשימה ריקה או לא ריקה מהפורק הנעול ב־Windows.
- סכומי הזיכרון והספירות כוללים את כל התצפיות. `eachMb` ו־`pages` מוגבלים
  בנפרד ל־12, עם `eachMbTruncated`, `pagesTruncated` ו־`measuredPageCount`.
  ה־probe שומר את מטא־נתוני הפירוט בלי כתובות עמודים. מידע חסר נשאר null
  או אינו נכתב בשדה המספרי הישן; מדידה אמיתית של אפס נשמרת.
- קריאת host מתחילה במקביל למניית Windows. למניית המנוע יש deadline
  אסינכרוני של שנייה, בתוך מגבלת שתי השניות של אבחון האפליקציה. בקשה
  שטרם הסתיימה נשארת יחידה לכל סביבת WebView; דגימה נוספת מסמנת pending
  וקוראת host, וסביבה חלופית אינה נחסמת. אין polling נוסף או פניות לדף.
  timeout אינו יכול לעצור קריאה נייטיבית סינכרונית שחוסמת את ה־platform thread.
- המונים `fixtureCommands/Replies` ובייטי ה־JSON שלהם סופרים את תעבורת
  פקודות המדידה בלבד. הם אינם כוללים codecs של platform channel, תשובות
  תשתית הגשר, console, scroll callbacks או RPC של ה־SDK. אין להסיק מהם את
  כל תעבורת הגשר של האפליקציה.

`collected` דורש ערך סופי ומקור. `unsupported` מציין שאין כאן דוגם מתאים,
`unavailable` מציין איסוף חסר/כושל, ו־`notRun` מציין פעולה שלא בוצעה.
ערך חסר הוא null; אפס מותר רק כשזה ערך שנמדד. CPU, PSS וזיכרון GPU
מסומנים unsupported בתוך ה־probe ויש לצרף עבורם איסוף חיצוני.

ה־pin `66ed7ec924d6ce5366a79acf0f90b0932a334b0f` כולל את חוזה השגיאות
המפורש של `getProcessInfos` מ־Otzaria/flutter_inappwebview#52. לכן
`pluginWebViewProcessSnapshot` מקבל רשימה ריקה מוצלחת כ־`collected`.
אין להחיל פירוש זה על גרסה ישנה שבה כשל יכול להחזיר רשימה ריקה.
גם בחוזה הנוכחי, אפס תצפיות אינו הוכחה לזיכרון כולל אפס או לכיסוי מלא
של המנוע.

## איסוף חיצוני ומטריצת האימות

| פלטפורמה | נתון מובנה נוסף ל־RSS של host | איסוף חיצוני והשלמה | מצב תרחיש native לפני CI |
|---|---|---|---|
| Windows | private commit של host ושל תהליכי WebView2 הקריאים | כלי ה־PowerShell הקיימים, WPR/WPA; לאמת backend ו־GPU | notRun מקומית; job profile ייעודי ב־CI |
| Linux | RssAnon של host ותהליכי WPE שהתגלו | `/proc`, `pidstat`/`perf` כשזמינים; לתעד FDO לעומת WPEPlatform | notRun: אין toolchain GUI/WPE מקומי |
| Android | אין דוגם תהליכי WebView ב־Dart | `dumpsys meminfo`, Perfetto והקישור לתהליך renderer בכלי המערכת | notRun: דרוש מכשיר |
| iOS | אין דוגם תהליכי WebView ב־Dart | Instruments: Time Profiler, Allocations/VM Tracker לפי זמינות | notRun: דרוש מכשיר ו־Xcode |
| macOS | אין דוגם תהליכי WebView ב־Dart | Instruments/`vmmap` לפי הרשאות; לתעד שיוך תהליכי WebKit | notRun: דרוש macOS |

ב־Android, דגימת חבילת האפליקציה לבדה אינה כוללת בהכרח את renderer של
WebView. אין לנחש PID לפי מספר הטאבים או לייחס את כל תהליכי WebView במכשיר
לאפליקציה. זהות שלא אומתה, הרשאה חסרה או נתון שאינו חשוף נשארים unavailable.
ראו [כלי Android ל־WebView וזיכרון](https://developer.android.com/topic/performance/memory/guide/webview-memory),
[dumpsys](https://developer.android.com/tools/dumpsys),
[כלי המדידה של Windows](https://learn.microsoft.com/en-us/windows/apps/develop/performance/profiling-tools),
ו[איסוף נתוני זיכרון ב־Apple](https://developer.apple.com/documentation/xcode/gathering-information-about-memory-use).

לפני/אחרי יש להריץ על אותה מכונה, OS, runtime, Flutter, build mode,
viewport ו־DPR, עם אותו hash של fixture ופרמטרים. בצע כמה הפעלות חדשות,
החלף את סדר הבסיס והמועמד, ושמור raw data; הרצה יחידה אינה אומדן p95 של
startup/resume. לבדיקת 1/5/10 מופעים שנה רק את `WEBVIEW_PROBE_TABS`.
אין ריקון מטמוני OS או טענה ל־cold engine. backend בפלט מסומן unavailable
עד אימות חיצוני: בקשת FORCE_HWND או בחירת default אינה הוכחה למסלול שנבחר.

## CI ובדיקות חוזה

`Performance probe tools` מריץ את בדיקות JavaScript ללא דפדפן, וב־Windows
job נפרד מפעיל את אותו תרחיש עם WebView2 חי וב־profile. הוא משתמש בשלושה
מופעים ובחלונות idle של שנייה, ללא ספי זמן או זיכרון. JSON, JSONL ולוג
נשמרים כ־artifact גם בכשל. נתוני GitHub hosted הם תצפית סינתטית; הם אינם
ראיה לחיסכון במחשב משתמש או להצלחה בארבע המערכות האחרות.

```bash
node --test tool/perf_probe/test_webview_probe_fixture.mjs
flutter test test/tool/perf_probe/webview_probe_metrics_test.dart \
  test/tool/perf_probe/webview_probe_window_test.dart \
  test/tool/perf_probe/perf_recorder_test.dart \
  test/core/diagnostics/process_tree_sampler_test.dart
flutter analyze --no-pub
```

בדיקות ה־fixture מריצות את ה־JavaScript המוטבע עצמו עם scheduler ו־DOM
מצומצמים: אין תעבורה יזומה ב־idle, העבודה מוגבלת למונה/interval/rAF אחד,
גלילה מגיעה למיקום הסופי, restore שומר עברית וגרסה, ו־pagehide משחרר
משימות. אלה בדיקות חוזה ואינן מדמות renderer אמיתי. בדיקות Dart מכסות
הבדלי מדדים, חסר מול אפס, כשל איסוף, metric לא מוכר ופירוט של יותר מ־12
renderers. מקור `sampleProcessTree` עצמו לא שונה במסגרת PR זה.
בדיקות החלון משתמשות ב־method channels מדומים: נבדקים חלון מוסתר,
תשובת show שקודמת לחשיפה בפועל, fade ב־macOS, כשל/timeout ודילוג במובייל.
הן אינן מדמות קומפוזיטור או מחליפות את הרצת תרחיש ה־profile במערכת היעד.
