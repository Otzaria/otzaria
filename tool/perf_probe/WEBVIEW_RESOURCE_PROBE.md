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
- ב־Windows כל `onWebViewCreated` קורא את ה־getter הציבורי
  `WindowsInAppWebViewController.creationDetails` ורושם `webviewBackend`
  עם run/PID ומזהה ההצמדה של ה־fixture. mode יצירה חסר או לא מאומת מכשיל
  את התרחיש ב־Windows; בפלטפורמות אחרות הוא unsupported. בקשת HWND
  חייבת לקבל HWND ו־stage `forced`; בקשת composition רשאית לקבל HWND עם
  סיבת fallback מפורשת. סיבת הבחירה אינה נגזרת מהיעדר אירוע fallback.
  כל תצפית היא `nativeCreation`, עם `ongoingModeVerified=false`: אין כאן
  בדיקת מצב מחזורית, אין פניות נוספות לדף בחלונות idle ואין קיבוץ לפי
  nativeViewId. יצירה מחדש מקבלת זהות fixture חדשה גם אם native מחזר מזהה.
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

חוזה השגיאות המפורש של `getProcessInfos` מ־Otzaria/flutter_inappwebview#52
נוסף בקומיט `66ed7ec924d6ce5366a79acf0f90b0932a334b0f`, ונשמר גם בצאצא
`c709de98711cf34350c48df4c75e24d0879d5876` הנעול בבסיס התרחיש החדש. לכן
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
אין ריקון מטמוני OS או טענה ל־cold engine. בקשת FORCE_HWND או default
אינה הוכחה למסלול שנבחר; ב־Windows משתמשים ברשומת היצירה של כל מופע.
בפלטפורמות אחרות אין API מקביל בפורק הזה והנתון נשאר unsupported.

## CI ובדיקות חוזה

`Performance probe tools` מריץ את בדיקות JavaScript ללא דפדפן, וב־Windows
job נפרד מפעיל את אותו תרחיש עם WebView2 חי וב־profile, פעמיים בתהליכים
טריים: בקשה `0` ואז בקשה `1`. הוא משתמש בשלושה מופעים ובחלונות idle של
שנייה, ללא ספי זמן או זיכרון. אי־התאמה בבקשת HWND מכשילה את הבדיקה;
fallback תקין בבקשת composition נשמר HWND ואינו הופך להשוואה בין מסלולים.
JSON, JSONL ולוג נפרדים לשתי ההפעלות נשמרים כ־artifact גם בכשל.
נתוני GitHub hosted הם תצפית סינתטית; הם אינם
ראיה לחיסכון במחשב משתמש או להצלחה בארבע המערכות האחרות.

```bash
node --test tool/perf_probe/test_webview_probe_fixture.mjs
flutter test test/tool/perf_probe/webview_probe_metrics_test.dart \
  test/plugins/services/webview_backend_observation_test.dart \
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

## תוספים מותקנים באפליקציה האמיתית — #4108 / #4112

`integration_test/installed_plugin_resource_probe_test.dart` הוא יעד נוסף
המפעיל את `app.main`, את `PluginSystemBloc`, את הכרטיסיות והמארחים
`PluginTabPage` ו־`PluginBackgroundHost`. הרישום עובר דרך
`PluginRegistryRepository`; ה־SDK, ה־bridge, תהליך ה־boot והפינוי עוברים
בקוד המוצר הרגיל. התרחיש הקודם נשאר בעל הגבולות המתועדים לעיל.

ה־fixture החדש מרכיב את `PerfFixture` הקיים, ובוחר תיקיות מוחלטות, חדשות
ונפרדות לנתוני האפליקציה, למקור החנות ולדוח. הוא מסרב לתיקייה מאוכלסת,
לנתיבים חופפים ולמעבר דרך symlink. ספרייה, הגדרות, מסדי נתונים, הרשאות
ותוספים נכתבים רק בתוך תיקיית הבדיקה. עדכונים, סנכרון, דיווחי קריסה
וגיבויים אוטומטיים נשארים כבויים. מצב offline כבוי רק בנתוני בדיקה אלה,
כדי שהחנות תוכל להשתמש בהרשאת הרשת מול שירות הקטלוג המקומי המבוקר.

### מה נבדק

| שלב | הראיה שנדרשת להצלחה |
|---|---|
| פתיחה ראשונה ושינוי מצב | SDK אמיתי שהשלים boot, שדה קלט גלוי, גלילה ו־ACK של `plugin.setRestoreState` |
| ריבוי מופעים | מספר מופעים זכאים מעל תקרת הפלטפורמה, לצד כרטיסיה גלויה ובקרות הגנה |
| לחץ זיכרון | קריאה אחת ל־`checkDiscard(memoryPressure: true)` לכל המועמדים והבקרות יחד |
| פינוי ושחזור | בקר חסר ו־released, וה־widget הוסר אחרי הפינוי; לאחר בחירת אותה כרטיסיה נדרשים אותו instance ID, בקר ואובייקט מסמך חדשים ומצב DOM משוחזר. מזהה ה־native view נרשם כתצפית בלבד, כי מותר למחזר אותו |
| הגנות | `noRestoreState`, `unsavedChanges`, `busyRpc` ו־`contextMenu` הם החסמים הראשונים שנצפו, והבקרים נשארים זהים לאחר אותה בקשת פינוי |
| כמות וגיל | מדיניות הכמות האמיתית מול מספר גדול מהתקרה; במקרה הגיל בלבד מקדמים את שעון הדיספצ'ר מעבר לגיל האמיתי. כל override משוחזר |
| חלון desktop | בקשת minimize וגם hide, ACK משאילתות חלון נייטיביות, מעבר מוסתר במארח, idle וחידוש אותו מסמך |
| רקע | הפעלה עצלה של `PluginBackgroundHost`, boot במצב background, idle וסגירה דרך `plugin.backgroundDone` |

בקרת `busyRpc` פותחת דיאלוג אישור דרך `ui.showConfirm` של התוסף ומשאירה
את ה־RPC ממתין בזמן בקשת הפינוי. ה־runner סוגר את הדיאלוג לאחר אימות
ההגנה. זו בקרת תקינות מבוקרת, ואינה עומס חיפוש, הורדה או עבודת משתמש.
רישום השירות נעשה דרך ה־SDK לתפריט הקשר, ומוסר לפני סגירת הכרטיסיה.
`firstBlockingReason` ו־`firstBlockerCounts` מתארים את החסם הראשון לפי סדר
המדיניות; אין להסיק מהם שכל סיבות הפטור האפשריות נמנו.

בשלב הכנת המופעים בלבד משתמשים בתקרת כמות וגיל גבוהה ומפורשת, כדי
ששעון הפינוי הרגיל לא יקדים את בקשת הבדיקה. שעוני המוצר, השהיית מחזור
החיים ופעילות הרקע אינם מבוטלים. מקרה הגיל המואץ ומקרה לחץ הזיכרון אינם
הוכחה לזמני פינוי תחת מדיניות ברירת המחדל בשימוש רגיל.

### חנות 2.13 עם שירות קטלוג מבוקר

המקור הנבדק הוא
[`Otzaria/otzaria-plugins-store@4517d39`](https://github.com/Otzaria/otzaria-plugins-store/tree/4517d39c4ecab632aff98e1c0e414881695961aa),
המכיל את שחזור המצב מ־[PR #4](https://github.com/Otzaria/otzaria-plugins-store/pull/4).
סקריפט ההכנה מוריד חמישה קבצים מהקומיט ומאמת SHA-256 לכל קובץ; ה־fixture
מאמת אותם שוב לאחר ההעתקה. קוד החנות ו־`restore-state.js` אינם משוכתבים.
אין תחליף JavaScript ל־SDK או לנתיב השחזור של החנות.

החנות נבחרה בעקבות רשימת ההורדות הציבורית; מספר הורדות אינו מספר
משתמשים פעילים. בזמן הכנת התרחיש הקטלוג הציבורי החזיר 503. הרצת הבדיקה
עצמה אינה טוענת שדירוג ההורדות עדכני ואינה תלויה בזמינות הקטלוג.
לצורך בדיקה שחוזרת על עצמה ניתנת לחנות רק ההרשאה האופציונלית
`network.access`; הרשאות פתיחת תוספים והרצה ברקע אינן ניתנות לה.

`InstalledProbeCatalog` מנתב את בקשות ה־HTTP של האפליקציה רק עבור GET
ל־`/api/plugins`, `/api/plugins/search` ו־`/api/plugins/store-home` אל שרת
loopback מקומי. הנתונים הם 36 רשומות בדיקה קבועות. שאר היעדים, שיטות
הכתיבה, הורדות ויצירת install-token נחסמים לפני פתיחת תעבורה. נתיב
ההרשאות ו־`network.fetchStream` המקורי נשארים פעילים. שתי בקשות ה־GET
המדויקות לרענון רשימת ההיתר הרשמית נחסמות גם הן ונרשמות כ־
`expectedPolicyBootstrap`; ה־resolver האמיתי יכול להמשיך לגיבוי המקומפל.
מותר לכל היותר זוג חסום אחד, בסדר raw ואז Contents API; כפילות, סדר שגוי,
רענון נוסף או כל חסימה אחרת מכשילים את הניסוי. כך גם ריצה ארוכה
שמחדשת את המדיניות דורשת בירור ואינה מוצגת כהצלחת האתחול הקר.
הדוח שומר את כל הבקשות החסומות ואת הספירות לפי סיווג, ללא השמטה.
הספירות נבדקות שוב בסיום, אחרי ניקוי התוספים וסגירת לקוחות ה־HTTP;
חסימה מאוחרת מסמנת כישלון ונשמרת בדוח הסופי.

הניתוב חל על לקוחות Dart HTTP ב־isolate של הבדיקה, ואינו הופך את כל
האפליקציה או מערכת ההפעלה ללא מקוונת; משאבים של החנות המקורית עשויים
להשתמש ברשת דרך מנוע ה־WebView. הדוח אינו ראיה לביצועי שרת הקטלוג או
לעומס של התקנת תוספים אמיתית. אין בדיקה של כל התוספים הנפוצים.

במופע החנות משנים חיפוש, מסנן מצב, מיון, העדפת הסתרה וגלילה; לאחר פינוי
נבדקים אותם ערכי DOM במסמך חדש. סמן מסמך מקומי נקרא ונוצר רק בגבולות
המדידה. החנות המקורית אינה חושפת את payload ה־boot, ולכן שדה זה מסומן
`unavailable` בדוח החנות; ה־SDK המאותחל, הבקר והמסמך החדשים וה־DOM המשוחזר
נבדקים בפועל. ב־fixture המבוקר נבדק גם `boot.restore.reason=discarded`
והמצב שנמסר ב־boot.

מסנני החנות נקבעים לפני החיפוש האחרון. מוכנות לגלילה דורשת גם
`pendingScroll === null` מהמקור המקובע: DOM מלא ואישור מצב דרך ה־SDK
יכולים להקדים את החיפוש המושהה ואת שתי מסגרות הרינדור שלו. התרחיש קורא
את הסמן בלבד, שומר את מצב הרינדור ואת גובה התוכן והחלון, ומבקש גלילה
של 420. אישור ה־SDK לגלילה מעל 200 עדיין נדרש בתוך 45 שניות.
`test_installed_plugin_store.mjs` מפעיל את קטעי התרחיש מול פונקציות החנות
ו־`restore-state.js` המקובעים, עם שעון ורינדור מבוקרים. זו בדיקת מקור;
הצלחת שחזור המצב ב־WebView אמיתי דורשת את הריצה הנייטיבית.

### הרצה מקומית ו־CI

ה־workflow `installed_plugin_probe.yml` בונה ומפעיל את האפליקציה ב־profile
ב־Windows. לפניו נבדקים חוזי הדוח, בקרות הכשל וה־fixture.
ה־driver שומר נתוני `reportData` גם בכשל, ובתיקיית הפלט נכתב checkpoint
אחרי כל שלב. artifacts כוללים דוח גולמי, לוגים, SHA של מקור החנות וגרסאות
כלים; כשל בנייה או ניתוק מוקדם עשוי להשאיר רק חלק מהם.

ב־Linux ה־workflow הנפרד `installed_plugin_probe_linux.yml` מפעיל את אותו
תרחיש ב־profile בסביבת Debian/WPE נתמכת, עם Xvfb, DBus ו־Openbox. פרטי
ההכנה, ההרצה והראיות מתועדים ב־[תרחיש Linux WPE](INSTALLED_PLUGIN_LINUX.md).

אירועי `show/hide` הגנריים של `window_manager` מעדכנים את נראות החלון
ב־dispatcher, בלי להמתין לאירוע focus. מצב המיזעור, מסך הקריאה והחלונות
האחרים נבדקים בנפרד. בדיקת ערוץ Flutter אינה מאמתת את מפיק האירועים
הנייטיבי: ב־macOS הגרסה המקובעת עדיין אינה שולחת אירועי `hide/show`,
ולכן קבלת מסלול ההסתרה שם חסומה עד תיקון התלות ואימות AppKit נפרד.

ב־Windows מפעיל `run_installed_plugin_windows.ps1` את אותה פקודת `flutter drive`
לאחר רישום שני מאזינים פסיביים לאירועי התחלה וסיום של `otzaria.exe`.
אין סריקת תהליכים, פנייה לאפליקציה או תשאול WebView בזמן חלונות השקט.
בסיום נשמר `windows-native-exit.json`: זהות ה־PID וזמן ה־bootstrap מדוח
המכשיר מותאמים לאירועי התהליך, להורה ול־session. נשמרים קוד היציאה
הנייטיבי העשרוני וההקסדצימלי, בלי להסיק אם האפליקציה קרסה או שה־driver
עצר אותה לאחר הבדיקה. PID ממוחזר, אירוע חסר או איסוף שנחתך נשארים
`unavailable`; אין המרה לאפס.

המאזינים מוגבלים ל־64 רשומות מכל סוג ועוד אירוע לזיהוי חיתוך. הניקוי
מסיר רק את המנויים והתורים שנוצרו לריצה הזאת. לאחר חזרת ה־driver בלבד
מתבצעת שאילתת `Application Error` מוגבלת ל־15 שניות ול־64 רשומות ועוד
אירוע לזיהוי חיתוך. נשמרים רק אירועים שזהות התהליך ומועד יצירתו תואמים
לריצה. היעדר אירוע אינו הוכחה שלא אירעה קריסה. פרטי המנגנון מתועדים ב־
[Win32_ProcessStopTrace](https://learn.microsoft.com/en-us/previous-versions/windows/desktop/krnlprov/win32-processstoptrace)
וב־[wevtutil](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/wevtutil).

`run.log` כולל את פלט ה־driver ואת stderr; נשמרים גם עותק של הדוח החלקי
ולוג השגיאות מתיקיית הנתונים המבודדת, כאשר הם קיימים. קוד כשל של ה־driver
נשמר גם אם האבחון נכשל. יציאה מוצלחת של ה־driver דורשת גם דוח מכשיר סופי
מוצלח ותצפית תהליך מזוהה. לפני התרחיש רצה ב־Windows בקרת ילד אמיתי שיוצא
בקוד 37; בדיקות החוזה כוללות גם כשל איסוף, זהויות סותרות ושמירת stderr.
במערכת אחרת בקרת Windows הנייטיבית מדווחת `notRun`.

הבקרה שומרת `native-exit-control.json` גם בכשל, לפני מחיקת תיקיית הילד:
האירועים שנאספו, סיבת הדחייה, זהות הילד, דוח חלקי, קוד היציאה ותוצאות
הניקוי. הדוח מוגבל ל־256 KiB; חריגה משמרת אבחון מקוצר ומפורש ומכשילה
את הבקרה. כשל שמירה או ניקוי אינו מחליף כשל קודם. בדיקות ניידות מפעילות
ילד PowerShell אמיתי עם אירועים מבוקרים, ואינן תחליף לבקרת CIM האמיתית
ב־Windows. `unavailable` עדיין מכשיל, ואינו מזהה לבדו את סיבת כשל הספק.

קוד נייטיבי שאינו 0 או `0xFFFFFFFF`, או אירוע `Application Error` תואם,
מכשילים גם דוח שהושלם. `0xFFFFFFFF` מתקבל רק עם driver ודוח מוצלחים:
`DesktopDevice.stopApp` ב־Flutter קורא ל־`Process.killPid`, וב־
[Dart הנעול](https://github.com/dart-lang/sdk/blob/04bcd1036cdc799ac6564988f159ee454d42c822/runtime/bin/process_win.cc)
הוא משתמש ב־`TerminateProcess(handle, -1)`. המספר הזה לבדו אינו מוכיח
שה־driver גרם לסיום התהליך.

ה־fixture המשותף משתמש ב־`synthetic-v2` ובסימון האתחול של מאגר ההגדרות,
כמו התיקון ב־[#4417](https://github.com/Otzaria/otzaria/pull/4417).
כך טעינת ההגדרות האמיתית שומרת על העדכונים והאינדקס הכבויים. ההכנה סוגרת
את Hive ומשאירה את `Settings` לא מאותחל עד `main`; בדיקת הרגרסיה טוענת
את מאגר ההגדרות האמיתי פעמיים. נתונים מוכנים מגרסה קודמת נדחים.
`setupStep` נשמר לפני התקנת כל fixture ולפני טעינת רשימת התוספים, מחוץ
לחלונות השקט, כדי להשאיר גבול התקדמות גם בניתוק מוקדם.

```powershell
# Windows; ב־macOS החלף windows ב־macos. נדרש PowerShell לפקודות דוגמה אלה.
$installedProbeRun = Join-Path ([IO.Path]::GetTempPath()) ('installed-plugin-' + [guid]::NewGuid())
$env:INSTALLED_PROBE_DATA = Join-Path $installedProbeRun 'data'
$env:INSTALLED_PROBE_OUTPUT = Join-Path $installedProbeRun 'device'
$env:INSTALLED_PROBE_REPORTS = Join-Path $installedProbeRun 'host'
$env:INSTALLED_PROBE_STORE_SOURCE = Join-Path $installedProbeRun 'source'
$env:INSTALLED_PROBE_MACHINE_ID = 'local-machine-session-1'
python tool/perf_probe/prepare_installed_plugin_source.py --output $env:INSTALLED_PROBE_STORE_SOURCE
flutter pub get --enforce-lockfile
flutter drive --profile -d windows --no-pub `
  --driver=test_driver/installed_plugin_resource_probe.dart `
  --target=integration_test/installed_plugin_resource_probe_test.dart `
  --dart-define=INSTALLED_PROBE_FLUTTER_VERSION=3.47.7 `
  --dart-define="INSTALLED_PROBE_COMMIT=$(git rev-parse HEAD)" `
  --dart-define=INSTALLED_PROBE_IDLE_MS=3000
```

`INSTALLED_PROBE_IDLE_MS` חייב להיות בין 1,000 ל־60,000; ב־CI הוא 1,000.
זהו חלון בדיקת פרוטוקול קצר. מדידה לצורך החלטות על צריכת משאבים מחייבת
חלונות ארוכים יותר וחזרות באותו מחשב ובאותה בנייה. אין להשוות בין שתי
מכונות hosted, בין profile ו־release או בין סטים שונים של הגדרות/backend.
`machineId` הוא תווית המסופקת לריצה, ואינו זיהוי חומרה מאומת.

להרצה על Linux או macOS, ועל מכשיר Android/iOS מחובר, אפשר להעביר את
אותם קובצי מקור מאומתים בקלט הבנייה. כך אין צורך ב־adb push לתיקיית
האפליקציה או בהעתקת נתיב מהמחשב לתוך המכשיר. הדוגמה הבאה משתמשת
ב־Bash ובמחשב מארח Linux/macOS; ב־iOS נדרשים macOS, Xcode וחתימה:

```bash
installedProbeHost=$(python3 -c 'import pathlib,tempfile; print(pathlib.Path(tempfile.mkdtemp(prefix="installed-probe-")).resolve())')
python3 tool/perf_probe/prepare_installed_plugin_source.py \
  --output "$installedProbeHost/source" \
  --defines-output "$installedProbeHost/store-defines.json"
flutter pub get --enforce-lockfile
flutter devices
installedProbeDevice=linux # macos, או מזהה מכשיר Android/iOS פיזי מהרשימה
unset INSTALLED_PROBE_DATA INSTALLED_PROBE_OUTPUT INSTALLED_PROBE_STORE_SOURCE
flutter drive --profile -d "$installedProbeDevice" --no-dds --no-pub \
  --driver=test_driver/installed_plugin_resource_probe.dart \
  --target=integration_test/installed_plugin_resource_probe_test.dart \
  --dart-define-from-file="$installedProbeHost/store-defines.json" \
  --dart-define=INSTALLED_PROBE_FLUTTER_VERSION=3.47.7 \
  --dart-define="INSTALLED_PROBE_COMMIT=$(git rev-parse HEAD)" \
  --dart-define=INSTALLED_PROBE_IDLE_MS=3000
```

במכשיר Android הוסף לפקודת `flutter drive` את `--flavor direct`.

ההובלה משתמשת ב־gzip/JSON, עם גבולות של 256 KiB לטקסט המקודד,
128 KiB לקלט הדחוס ו־512 KiB לתוכן המפוענח. רק חמשת הנתיבים המקובעים
מותרים, וכל ה־SHA נבדקים לפני כתיבת קובץ. המכשיר מקצה תיקיית temp
קנונית וחדשה, וה־driver מחזיר את הדוח למחשב המארח. קובצי הבדיקה נשמרים
לאבחון כל עוד תהליך האפליקציה מחזיק מסדי נתונים פתוחים; אפשר להסיר את
תיקיית הריצה לאחר יציאת התהליך. שרת הקטלוג וחיבורי HTTP נסגרים ב־finally,
וכך גם מארחי הבדיקה אם נשארו פתוחים בעקבות כשל. בוני Windows הכפופים
למגבלת אורך שורת פקודה יכולים להשתמש במסלול תיקיית המקור המקומית
המתועד למעלה במקום להעביר payload בקלט הבנייה.

מסלול האיסוף האוטומטי כאן הוא profile. ריצת release אינה מסופקת על ידי
ה־driver הזה: היא דורשת רתמת בדיקה נייטיבית המתאימה לפלטפורמה ללא
הסתמכות על VM service. בכל חמש המערכות תוצאות release נשארות `notRun`
עד הרצה כזאת. בנייה מוצלחת לבדה אינה דוח תוצאות. גם profile על סימולטור
או emulator אינו קבלת ביצועים של מכשיר פיזי.

| מערכת | המסלול בתרחיש החדש | גבול קבלה |
|---|---|---|
| Windows | CI של האפליקציה ב־profile; backend נצפה דרך אבחון יצירת ה־native view | רק artifact של ריצה שעברה הוא ראיית ביצוע; אין סף חיסכון |
| macOS | CI של האפליקציה ב־profile | RSS של המארח; זיכרון מנוע מלא ו־backend אבחוני מסומנים לפי זמינותם |
| Linux | CI נפרד ב־profile עם Debian/WPE ו־Xvfb/DBus/Openbox | רק artifact של תרחיש שעבר הוא ראיית ביצוע; פרטי GPU ותצוגת CI אינם קבלת חומרה |
| Android | פקודת profile משותפת עם payload מקור; `notRun` במסגרת workflow זה | נדרשים מכשיר מתאים ואוטומציית רקע במכשיר אמיתי למדידת ביצועים |
| iOS | פקודת profile משותפת עם payload מקור; `notRun` במסגרת workflow זה | נדרשים מכשיר, חתימה ואוטומציית רקע; סימולטור אינו קבלת חומרה |

כל דוח מסמן רק את מערכת ההפעלה שהריצה אותו. ארבע האחרות נשארות
`notRun`. פעולות minimize/hide מסומנות `unsupported` במובייל; שלב רקע
של מערכת ההפעלה מסומן `notRun`. מופע `PluginBackgroundHost` הנסתר בתוך
האפליקציה אינו שקול להעברת האפליקציה עצמה לרקע.

### פירוש המדדים

כל גבול שלב שומר `describeForegroundResources()` הסינכרוני, שאינו פונה
ל־JS, ל־native או למסד הנתונים, לצד דגימת תהליכים נפרדת. RSS של המארח
נמדד בבתים דרך `ProcessInfo.currentRss`. הדוגם הקיים מוסיף את המדד הזמין
של המארח ואת תהליכי המנוע שנצפו, עם מקור, יחידה, סטטוס איסוף וכיסוי.
`complete` של המנוע נשאר לא ידוע; אין PID משוער לכל כרטיסיה ואין חיבור
של מדדים שונים ל״זיכרון כולל״. נתוני CPU, PSS, זיכרון GPU ומשך ציור
נייטיבי מסומנים חסרים כאשר לא נאספו.

שאילתות JS, רשימות תהליכים ופעולות חלון נעשות בגבולות בלבד ועלולות
להעיר את המנוע. חלון שקט מתחיל אחרי ACK ומסתיים לפני הקריאה הבאה;
מונה פעולות הבדיקה חייב להישאר אפס. דגימה שנותרה תלויה אחרי timeout
מונעת הצגת חלון שקט תקין. פעילות timers ו־bridge של המוצר עצמו אינה
מנוטרלת. איסוף `DeveloperDiagnostics` נשאר כבוי, ולכן הבדיקה אינה
מפעילה את הרחבת כל רמות ה־console שבאה עם מצב האיסוף.

זמן החידוש כולל בחירת כרטיסיה, יצירת בקר/מסמך, SDK וקריאת DOM מאמתת;
זו אינה מדידת compositor. `FrameTiming` נאסף באופן פסיבי ובכמות חסומה,
ושייך ל־Flutter בלבד. המדידות נשמרות גם בלי הבטחה לחיסכון בזיכרון.
בחירת פרופיל חסכוני או שינוי ברירות מחדל נשארים תלויים בנתוני RAM,
זמן חידוש וחוויית שימוש ממכשירים מתאימים.
