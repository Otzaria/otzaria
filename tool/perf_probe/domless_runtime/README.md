# ניסוי runtime ללא DOM לתוספי רקע (#4111)

**החלטה: NO-GO להפעלה במוצר.** הוכחה מוגבלת על Linux מראה שקוד הרקע המקורי של חנות התוספים יכול להשלים עבודה דרך ה־SDK המשותף במנוע ללא DOM. חסרים עדיין אחסון מתמשך ותיאום עם דף התוסף, אריזה ובדיקות בכל חמש המערכות, חיבור מלא ל־dispatcher ולשירותים, והשוואת משאבים על חומרה אמיתית. זהו תוצר ניסויי עבור [#4111](https://github.com/Otzaria/otzaria/issues/4111) ו־[#4124](https://github.com/Otzaria/otzaria/issues/4124); הוא אינו סוגר את דרישות הקבלה שלהן.

מארח הרקע הרגיל ממשיך להשתמש ב־WebView. ההפעלה כאן מפורשת דרך `prepare.py` והבדיקות, עם קוד וגרסה מקובעים. לא נוסף dependency לאפליקציה, שדה מניפסט פעיל או מסלול בחירת runtime בעת startup.

## מה יש בניסוי

- `host.c`: embedding של QuickJS-NG בתהליך נפרד לכל מופע, ללא ספריית `quickjs-libc`, מודולי `std`/`os`, loader למודולים או טעינת bytecode.
- `domless_process.dart`: בקשות ותשובות אסינכרוניות ב־JSON, אירועי stream, ביטול עבודה בסגירה והתעלמות מתשובות של מופע שנסגר.
- `environment.js`: מעטפת מוגבלת ל־`window`, אירועים ואחסון בזיכרון. אין `document`, timers או `fetch` של הדפדפן.
- `fixture_services.dart`: נתונים מלאכותיים משותפים לשני המנועים. הרשימה המותקנת, הקטלוג וההתראות אינם נתוני משתמש; אין פנייה אמיתית לחנות בזמן הבדיקה.
- `domless_runtime_test.dart`: הקוד המקורי של החנות, ה־SDK האמיתי, `PluginBridgeHandler` ושער הרשאות הרשת האמיתי, עם שירותי fixture. בדיקות נוספות מפעילות קוד עוין מבחינת משאבים בגבולות הניסוי.
- `domless_webview_reference_test.dart`: אותו workload בשני backends לבחירה, בתוך אותו target של אפליקציית Flutter. ברירת המחדל היא WebView מוסתר בגודל 1×1; הגדרת executable מפעילה את המנוע הניסויי בדסקטופ. המסלול הזה טרם הורץ כאן על runner נייטיבי של האפליקציה.

השינוי בקוד המוצר מצומצם לשתי נקודות: `PluginBridgeHandler.handleRpc` חושף את נתיב הטיפול הקיים בלי להחתים nonce בשביל המתקשר; `buildPluginBootScript` מקבל פונקציית תעבורה מטעם המארח המהימן. ברירת המחדל נשארת `flutter_inappwebview.callHandler`. הקוד של streams, שגיאות, רישום אירועים, בדיקת nonce, הרשאות ו־throttle משותף. זהות התוסף נקבעת בעת בניית ה־handler, ואינה נלקחת משדה שהגיע מ־JS.

## מיפוי מקורות בפועל

הבדיקה נערכה ב־2026-11-06 על בסיס אפליקציה `a675adc068916c01523d32011bcf28c192541fd3`. המדגם המקדים כלל שמונה ארכיונים מאומתים מתוך קטלוג של 82 רשומות; שני מסלולי הרקע הבאים נבדקו. זה אינו סקר מלא של כל התוספים בחנות.

| מקור | גרסה ו־SHA-256 של הארכיון | גרף הסקריפטים שנבדק | תוצאה |
|---|---|---|---|
| חנות התוספים, `otzaria.plugins_directory` | `2.12.0`; `2701902bd81baf006b9d73d00f8e125de5a9abdd251ea42e6b6fee52542b8945` | `background.html` → `i18n/en.js` וסקריפט inline קלאסי | מועמד לניסוי המצומצם; הורץ הקוד המקורי |
| מרקר, `com.otzaria-marker` | `0.9.6`; `f375ff9373a6fe70e61012cc10791dc8e54552c043997c3804fdbe63e0257b03` | `marker-domain.js`, `marker-i18n.js`, `i18n/en.js`, `marker-runtime.js`, `marker-core.js`, `marker-background.js` | אינו מתאים לפרופיל הניסוי הנוכחי; נבדק מקור בלבד |

ה־hash של כל קובץ ושל המניפסט נמצא ב־[`audited_sources.json`](audited_sources.json). מקורות החנות זהים byte-for-byte ל־[commit הרשמי `33a3b218`](https://github.com/Otzaria/otzaria-plugins-store/tree/33a3b218b81ac6f51393a243e6002ddd04c9c2b8). מקורות המרקר הגיעו מהארכיון המאומת; [מאגר המחבר](https://github.com/mmichaelush/otzaria-marker-plugin) הוא מקור ההקשר. הניסוי אינו מעתיק את מימוש המרקר או את המסלול הנייטיבי של [PR #3036](https://github.com/Otzaria/otzaria/pull/3036).

| תחום | חנות התוספים: נתיב הרקע שהורץ | מרקר: נתיבים הנגישים מהסקריפטים הנטענים |
|---|---|---|
| DOM | `checkAndNotify` אינו נוגע ב־DOM; `window.TRANSLATIONS` משמש מילון | `MarkerI18n` מייצא פונקציות DOM מוגנות, אך `MarkerCore.start → boot` אינו דורש אותן. קיום המילה `document` בקובץ אינו פוסל לבדו |
| Timers | אין במסלול הרקע | `boot → startRevisionWatch` מפעיל `setInterval` כל 1,500ms; pacing/retry ב־`MarkerRuntime` ו־`whenBooted`, selection debounce וגיבויים משתמשים ב־`setTimeout` ובביטולו |
| Fetch | `fetchText` צורך `network.fetchStream` דרך SDK, כולל response ומקטעי data | גיבוי אוטומטי משתמש ב־RPC של `fs`; הפונקציה המיוצאת `saveFileAs` דורשת `Blob` ו־`fetch` לערוץ upload. אין להניח שכל פונקציה מיוצאת רצה ב־boot |
| Storage | `localStorage` למפתח `otzaria_store_bg_seen_ids_v1`; רשימת מותקנים דרך RPC | `storage.get/set/list/remove`, קובצי גיבוי ו־revision משותף בין מופעים. polling מחדש הוא חלק מההתנהגות, לא פרט שניתן להסיר בשקט |
| Events | `plugin.boot`, ולאחר העבודה `plugin.backgroundDone` | `MarkerCore.start` רושם אירועי קורא, תפריטים, פקודות, הרשאות והגדרות; נדרש keepAlive לשימור מצב הסימונים |
| RPC | `network.fetchStream`, `plugin.listInstalled`, `notifications.showInApp`, `plugin.backgroundDone` | שכבת `MarkerRuntime` עוטפת תשובות, pacing, retry מוגבל של rate-limit ותורי כתיבה; `MarkerCore` מפעיל storage/reader/settings/fs/UI |
| Modules | שני scripts קלאסיים בסדר קבוע, ללא imports | שישה scripts קלאסיים בסדר קבוע; קובצי UI אינם בגרף הרקע |
| Web APIs / JS | async/await, async iterator, Promise.all, Map/Set, JSON, Date, encodeURIComponent | `Intl.Segmenter` ו־`crypto.getRandomValues` אופציונליים עם fallbacks בקוד; timers נדרשים. יש לבחון גם נתיבי שינוי/ייצוא, מעבר לטעינה הראשונית |

### התלות של ה־SDK במארח

ב־[`plugin_sdk_scripts.dart`](../../../lib/plugins/view/plugin_sdk_scripts.dart), ה־background stub רושם callbacks עד ל־boot, משתמש ב־`window` וב־`CustomEvent`, וחוסם `window.open`. ה־SDK המלא מנהל streams ומסירת אירועים על אותו event target. הזרקת גופנים משתמשת ב־`document`; היא מושמטת בניסוי. קיצורי מקלדת שייכים ל־stub של לשונית ואינם נטענים כאן.

מימוש האירועים הניסויי מכסה את פעולות ה־SDK הזה: `on/off`, callback זהה, `detail` ומסירה סינכרונית. הוא אינו הבטחת תאימות ל־DOM EventTarget המלא: אין bubbling, capture, `AbortSignal`, אירועי אחסון בין דפים או כללי שגיאות של הדפדפן. גם raw JSON שמוחזר במיוחד ל־WebView ופעולות אחרות בקטלוג ה־SDK לא הופעלו על המנוע הניסויי; נדרש חוזה serialization ובדיקות עבורן לפני הרחבת הפרופיל.

[`PluginRuntimeDispatcher`](../../../lib/plugins/services/plugin_runtime_dispatcher.dart) עדיין שומר `InAppWebViewController`, רושם אותו ב־`registerController` ומוסר אירועים באמצעות `evaluateJavascript`. גם `beginInstanceWork` שלו קשור לבעלות על controller. הניסוי אינו מזייף controller ואינו נרשם שם: הוא בודק את `PluginLazyActivationService.beginWork` דרך callback ייעודי. מסירת broadcasts, ping, ready/reload ותורי resume דרך dispatcher דורשת ממשק runtime נוסף לפני שילוב במוצר.

## בחינת מנועים לפני הבחירה

המקורות הראשוניים נבדקו ב־2026-11-06. “מוצהר” בטבלה הוא טענת הפרויקט, ולא בדיקת אריזה של אוצריא. הבחירה נעשתה לאחר המיפוי: QuickJS-NG מספק API מפורש למגבלות, JavaScript המתאים לקוד החנות והצהרת פלטפורמות מסודרת. כאן נבחר **מועמד לניסוי**; לא מנוע מוצר.

| מועמד | Windows | Linux | Android | iOS | macOS |
|---|---|---|---|---|---|
| QuickJS-NG 0.18.0 | מוצהר, VS2022+/Clang | מוצהר, glibc/musl; נבדק כאן x64 | מוצהר, NDK26+; upstream מציין בדיקות מוגבלות | מוצהר עם בדיקות מוגבלות | מוצהר, macOS11+ |
| QuickJS המקורי, 2026-06-04 | build/binaries מתועדים | מתועד | לא אומתה אריזת Flutter רשמית בחומר שנבדק | לא אומתה אריזת Flutter רשמית | build/binaries מתועדים |
| flutter_js 0.8.7 | מוצהר, QuickJS | מוצהר, QuickJS | מוצהר, QuickJS | מוצהר, JavaScriptCore של המערכת | מוצהר, JavaScriptCore של המערכת |
| Duktape | ניידות C; לא אומתה אריזה ליישום | ניידות C; לא אומתה אריזה ליישום | לא אומתה אריזה | לא אומתה אריזה | לא אומתה אריזה |

| מועמד | רישיון / תחזוקה | Interrupt, זיכרון ובידוד | מסקנה לניסוי |
|---|---|---|---|
| QuickJS-NG | MIT. release מקובע 0.18.0 מ־2026-11-01, commit `d7215b0a`; עדיין נדרש בעל תחזוקה שיעקוב אחר תיקוני מנוע | `JS_SetMemoryLimit`, `JS_SetMaxStackSize`, `JS_SetInterruptHandler`; runtime נפרד לכל heap, לא רק context נוסף | נבחר; הניסוי בונה core בלבד ומנהל jobs ו־RPC בעצמו |
| QuickJS המקורי | MIT; release מתועד מיוני 2026 | אותם סוגי מגבלות C; מודולים ו־async generators מתועדים | חלופה ראויה; חסרה לנו הוכחת אריזה אחידה בחמש המערכות |
| flutter_js | MIT; wrapper שמפצל בין מנועים ו־native bridges בכמה מאגרים | FFI סינכרוני ומנגנוני Promise/fetch מתועדים. לא אומת API אחיד למגבלת heap ול־interrupt בשני backends | לא נוספה תלות: לפני בחירה נדרשת ביקורת pin/בינאריים ושקילות תקציבים. אין להסיק שהפרויקט לא מתוחזק |
| Duktape | MIT; יש להעריך cadence ו־patches לפני אימוץ | allocator מותאם ומנגנון execution-timeout ניסויי מתועדים; heaps נפרדים | ES5/5.1 ותמיכה חלקית ב־ES2015/16 אינם מריצים את קוד ה־async iterator המקורי בלי שינוי מהותי |

מקורות: [פלטפורמות QuickJS-NG](https://quickjs-ng.github.io/quickjs/supported_platforms/), [C API וגבולות](https://quickjs-ng.github.io/quickjs/developer-guide/intro/), [release המקובע](https://github.com/quickjs-ng/quickjs/releases/tag/v0.18.0), [הרישיון המקובע](https://github.com/quickjs-ng/quickjs/blob/d7215b0ad3fc2c562e8317fd9bca058fd4863804/LICENSE), [QuickJS המקורי](https://bellard.org/quickjs/), [מדריך QuickJS](https://bellard.org/quickjs/quickjs.html), [flutter_js](https://github.com/abner/flutter_js), [pubspec של ה־wrapper](https://github.com/abner/flutter_js/blob/master/pubspec.yaml), [Duktape](https://duktape.org/), [מדריך Duktape](https://duktape.org/guide), [timeout configuration](https://wiki.duktape.org/configoptions#DUK_USE_EXEC_TIMEOUT_CHECK).

## חוזה התאימות וה־opt-in

### הפרופיל הממומש בכלי

1. הקלט הוא חנות התוספים 2.12.0 עם hash תואם. `prepare.py` מאמת גם את שלושת קובצי המקור, את סדר הסקריפטים ואת סוגם. הורדה שונה אינה מועמד ל־fallback או להרצה.
2. כל תהליך מחזיק `JSRuntime` ו־context יחידים. רק פונקציית RPC של המארח נחשפת; זהות התוסף וה־registry שייכים למארח. nonce עובר מה־SDK המקורי לשער המקורי. JS אינו רשאי לבחור handler של תוסף אחר.
3. ה־RPC משמר תשובות ו־async streams. אירוע נמסר רק למופע שיצר את הבקשה. `iterator.return()` שולח cancellation דרך ה־SDK, כולל ההחרגה הקיימת מ־throttle.
4. `localStorage` הוא מפת מחרוזות פרטית למופע, עם 64KiB של תוכן UTF-16 כולל מפתחות. הוא מתאפס בסגירה. זה מספיק ל־fixture חד־פעמי של עדכון; **אינו ממלא את דרישת ההתמדה של החנות במוצר**.
5. הניסוי אינו מספק timers, native fetch, DOM, workers, Blob, IndexedDB, WebSocket, module loader או `Intl`. טעינת scripts קלאסיים מבוצעת בידי המארח בסדר מאומת.
6. ה־registry ושירותי הנתונים הם fixtures; שיקול הרשאות ה־handler ושער הרשת משותף למוצר. בדיקות אלה אינן אישור למסלול HTTP אמיתי, redirects, קבצי משתמש, דיאלוגים או מסדי הנתונים של התוספים.

### מגבלות שנאכפות

| משאב | גבול בניסוי | פעולה בכשל |
|---|---|---|
| הקצאות JS | 16MiB ל־runtime | כשל הקצאה; חריגה לא מטופלת מסיימת את המופע |
| Stack של המנוע | 512KiB | חריגת stack מסיימת evaluation והמופע נסגר |
| תור הרצה | 100ms של wall time ו־2,048 jobs לכל פקודה | interrupt / סגירה; אינו deadline של עסקת RPC שכבר התקבלה ב־Dart |
| RPC ממתין | 64 בקשות | הבקשה העודפת נדחית לפני שליחתה למארח |
| JSON של בקשת RPC | 64KiB UTF-8 | דחייה לפני שליחה |
| פקודת host / תוצאת evaluation | עד 1MiB | סגירה במעבר הגבול |
| פקודת תהליך ב־Dart | 5 שניות | סיום התהליך וביטול callbacks |

מגבלת heap אינה מגבלת RSS כוללת. תהליך נפרד ובידוד heaps אינם sandbox של מערכת ההפעלה; הניסוי משתמש במקור מקובע ומבוקר, ואינו מסלול התקנת תוספים לא מהימנים. אין שימוש ב־Node `vm` כגבול אבטחה. logging של console, unhandled Promise rejections והקשחת מעטפת התהליך עדיין דורשים תכנון למוצר.

המארח מאזין ל־`stdin.done` מתחילת חיי התהליך, כי כשל כתיבה יכול להופיע אחרי החזרה מ־`writeln`. כשל מעביר את הפקודות הממתינות למסלול שגיאה ומבטל את עבודת המארח. קריאות `close()` חוזרות חולקות אותה השלמה, שממתינה ליציאת התהליך ולסיום זרמי הקלט והפלט. בדיקות הכשל כוללות תור כתיבות, חריגת guest ויציאת תהליך פתאומית.

### חוזה נדרש לפני rollout

- opt-in דו־צדדי: הצהרת פרופיל וגרסת capabilities של מחבר התוסף, ובחירת משתמש/feature flag. התיאור כאן הוא הצעת חוזה; אין כרגע שדה מניפסט שמפעיל את המנוע. גם גרף scripts ללא DOM אינו מוכיח התאמה.
- lifecycle נשאר בבעלות השירותים הקיימים: הרשאת startup לפני יצירה, ההשהיה הקיימת, אירועי הפעלה עצלה ותורים, `keepAlive` רק אחרי הצהרה והרשאה, ו־runtime token חדש לכל מופע. בדיקות הכלי מחברות callback עצל ו־`beginWork`; חיבור dispatcher ו־host במוצר עדיין חסר.
- עבודה ממתינה חוסמת פינוי מחמת חוסר פעילות. סגירה מפורשת/כשל מסמנים cancellation ומשחררים callbacks. פעולה שכבר אושרה במארח עלולה להשלים; הריגת JS אינה rollback של כתיבה.
- fallback ל־WebView מותר רק לפני התחלת עבודה שהתקבלה במארח. הכלי מחשיב כל RPC שנצפה כמחסום שמרני ל־replay (`canFallbackWithoutReplay`). אחרי RPC אין נסיון אוטומטי באותו אירוע במנוע אחר; נשמר הכשל ונדרש אירוע חדש עם מדיניות dedup מתאימה.
- התמדה חייבת לשמור על namespace של תוסף, atomicity, quota, הסרה ושלילת הרשאות, ולעבוד יחד עם דף WebView קיים. יש לקבוע מעבר וחזרה בלי לאבד את baseline של החנות או לייצר התראות כפולות.

## הרצה חוזרת

נדרשים Python3.12+, CMake, קומפיילר C, וה־Flutter SDK של הפרויקט. ב־Windows הבנייה הרגילה של CMake משתמשת ב־Visual Studio; ב־Linux/macOS היא יוצרת executable תחת `build/`. cache חייב להיות מחוץ לריפו. אין צורך בחשבון לחנות או בנתוני משתמש.

```bash
python3 -m unittest discover -s tool/perf_probe/domless_runtime -p prepare_test.py -v
python3 tool/perf_probe/domless_runtime/prepare.py --cache /tmp/otzaria-domless
OTZARIA_DOMLESS_CACHE=/tmp/otzaria-domless OTZARIA_DOMLESS_MEASURE=1 \
  flutter test --no-pub --reporter expanded \
  test/tool/perf_probe/domless_runtime_test.dart
```

`--engine-archive` ו־`--plugin-archive` מאפשרים להשתמש בהורדה מקומית; גם במסלול זה ה־hash נבדק. הארכיון המקובע של החנות ניתן להורדה ב־[URL הגרסה](https://otzaria.org/api/plugins/6a01cd9954ae49eaed8dab2a@2.12.0/download). מקורות/בינאריים אינם נשמרים ב־git. לא נמצא קובץ רישיון בארכיוני התוספים שנבדקו, ולכן הכלי מוריד אותם לניסוי מקומי ואינו מפיץ עותק שלהם כחלק מה־PR.

קובצי JSON ו־JS נקראים ונכתבים ב־UTF-8 במפורש, בלי תלות ב־locale של Python. בדיקות ההכנה משתמשות בארכיונים קטנים שנוצרו לבדיקה, משביתות UTF-8 mode ומוודאות שארכיון פגום או hash שגוי של קובץ נדחים; רק שלב הקומפילציה מוחלף בהן. בניית הניסוי והרצת התוסף משתמשות בנפרד בארכיונים האמיתיים וב־hashes המקובעים.

תוצאת המדידה נכתבת ל־`native-measurements.json` בתוך ה־cache. בלי `OTZARIA_DOMLESS_CACHE` קבוצת הבדיקות מסומנת כמדולגת במפורש; ה־workflow הייעודי בונה את המנוע ומפעיל אותה ב־Linux, Windows ו־macOS. CI זה בודק את ניסוי ה־native וה־SDK, ולא את מוצר ה־WebView הנייטיבי או את המובייל.

### Target להשוואת workload באפליקציה

`prepare.py` כותב גם `defines.json`, הכולל את המקור המקובע לצורך bundling מקומי של בדיקת האינטגרציה. יש להריץ שני תהליכי אפליקציה נפרדים על אותה חומרה, באותו build mode ובאותם תנאי מדידה:

```bash
flutter test integration_test/domless_webview_reference_test.dart -d linux \
  --dart-define-from-file=/tmp/otzaria-domless/defines.json

flutter test integration_test/domless_webview_reference_test.dart -d linux \
  --dart-define-from-file=/tmp/otzaria-domless/defines.json \
  --dart-define=OTZARIA_DOMLESS_EXECUTABLE=/tmp/otzaria-domless/build/otzaria_domless_probe
```

אלו פקודות smoke ב־debug. מדידה לפרסום דורשת runner ב־profile, למשל `flutter drive --profile` עם driver האינטגרציה של הפרויקט. אין להשוות תוצאת debug ל־profile. `OTZARIA_DOMLESS_EXECUTABLE` הוא נתיב מקומי ל־executable שנבנה למערכת המארחת; ב־Windows הנתיב הרגיל הוא `build/Release/otzaria_domless_probe.exe`. תהליך חיצוני זה אינו אריזת Android/iOS; במובייל target ה־WebView יכול לשמש ייחוס, אך צד ה־native דורש embedding אחר.

שני המצבים משתמשים באותו קוד חנות, SDK, handler, שער רשת, שלוש רשומות קטלוג, תוסף מותקן אחד ונתוני boot קבועים. יש 1/5/10 מופעים, שלוש חזרות, ו־1s מנוחה ללא פניות JS. ההמתנה מסתיימת רק אחרי התראת עדכון אחת ו־`backgroundDone`. לצורך מדידת idle מחזיקים את המופעים אחרי `backgroundDone` בשני המצבים; במוצר בקשה זו מובילה לכיבוי מוקדם.

נמדד הזמן מיצירת קבוצת המופעים עד קבלת `backgroundDone` לכל אחד. סביבת WebView משותפת מאותחלת לפני המדידה וזמנה מדווח בנפרד; לכל מופע native מנוע חדש. לכל WebView origin loopback נפרד ואחסון נקי. תחנות דגימה של process-tree נמצאות מחוץ לחלון המנוחה. הנתונים יוצאים ב־`reportData` ובשורות `OTZARIA_DOMLESS_REFERENCE`.

סכמת הפלט היא גרסה 3. `hostPid` ו־`instanceOrder` קושרים כל אינדקס של startup/CPU/memory ל־`instanceId`, ל־`pluginId` ול־PID של תהליך native; הסדר נשמר גם כשיצירת התהליכים מסתיימת בסדר אחר. PID של WebView אינו מיוחס למופע בלי מידע נייטיבי שמאפשר זאת. בדיקת הייחוס משתמשת ברישום וב־lister הציבוריים של אבחון התוספים ומשחזרת את הרישום שהיה לפניה.

דוגם האפליקציה מדווח private commit ב־Windows ו־RssAnon ב־Linux; אלו מדדים שונים. נתוני native child כוללים heap וזמן CPU; peak RSS זמין ב־Windows וב־Linux, ובמערכות אחרות מוחזר null. ב־macOS לא מפרשים ru_maxrss אחרי fork/exec כשיא שנוצר רק במנוע. אין להפחית peak RSS של native מ־private commit/RssAnon של WebView. ב־Apple ובמובייל חלק משדות process-tree אינם זמינים, והם מדווחים כחסרים. CPU של **כל** תהליכי המארח והמנוע דורש דגימה נייטיבית נוספת. `comparisonReady` נשאר false עד איסוף שקול; הנתונים אינם דירוג אוטומטי של חיסכון.

## מה נמדד כאן

נמדד רק runner ה־native בתוך Linux x64 משותף, CPU מדווח AMD EPYC9V74, תשעה מעבדים זמינים, GCC13.3, CMake Release, Flutter3.47.7 / Dart3.13.5. הדגימה ב־2026-11-06 בשעה 10:04:58 UTC משתמשת במקורות שטביעותיהם נשמרו עם התוצאות. זהו host בדיקות חם עם מופעי מנוע חדשים, לא הפעלה קרה של אפליקציית אוצריא. נתוני הסביבה נמצאים ב־[`results/linux-native-environment.json`](results/linux-native-environment.json), ו־48 התצפיות, כולל מזהי התהליכים והמופעים, ב־[`results/linux-native-samples.csv`](results/linux-native-samples.csv).

| מופעים בו־זמנית | זמן עד סיום: min / median / max, ms | סכום peak RSS לתהליכי המנוע, MiB | סכום heap JS אחרי העבודה, KiB | סכום CPU של המנועים בחלון מנוחה, שניות |
|---|---|---|---|---|
| 1 | 27.3 / 29.1 / 29.2 | 2.238–2.250 | 163.0 | 0.000048–0.000810 |
| 5 | 45.2 / 108.4 / 111.1 | 11.195–11.281 | 815.0 | 0.001812–0.005464 |
| 10 | 161.9 / 197.3 / 208.4 | 22.363–22.465 | 1,629.9 | 0.000410–0.011244 |

סכום שיאים אינו מדידת RSS סימולטנית. ב־Linux נקרא `VmHWM` של התהליך אחרי exec; `getrusage.ru_maxrss` עלול לשמר שיא מלפני exec ולכן אינו מקור ה־RSS כאן. CPU נדגם בפקודות counter נפרדות וקלות, וסריקת heap וקריאת RSS מתבצעות מחוץ לחלון הזה. נתוני CPU עדיין כוללים את תקורת הפקודות בקצוות; המספרים קטנים ואינם הוכחה ל־CPU אפס. המארח, שירותי Flutter, רשת אמיתית וקטלוג מלא אינם כלולים במדדי child. **אין כאן תוצאת WebView מקבילה או נתון חיסכון באפליקציה.**

## תנאים להמשך והחלטה

הניסוי מצדיק המשך מחקר של פרופיל רקע צר. לפני הצעת rollout יש להשלים:

1. להריץ את target ההשוואה בשני backends ב־profile על Windows/Linux/macOS, ולבנות embedding מתאים ל־Android/iOS. לבדוק build, עבודה, cancellation, OOM/interrupt, suspend/shutdown ותורי jobs בכל מערכת, ולא להסתפק בהצהרת התמיכה של המנוע.
2. למדוד על אותה חומרה startup, זיכרון בתהליך המארח ובכל תהליכי המנוע, CPU במנוחה ו־N מופעים; להשתמש גם בקטלוג/רשימת מותקנים מציאותיים. להפריד מנועים קרים/חמים, preload, teardown ושימוש חוזר.
3. להשלים התמדה/תיאום אחסון, רישום אירועים דרך dispatcher, generation/runtime-token, startup authorization, failure budget, `keepAlive` ופינוי בזמן RPC מול השירותים האמיתיים. הבדיקות כאן מוכיחות את הגבולות שנחברו, לא אינטגרציה שלא נכתבה.
4. להגדיר ולבדוק API חסרים, JSON raw ו־logging; לדחות capabilities שאינם נתמכים לפני תחילת העבודה. לבחון את שאר תוספי הרקע בפועל. המרקר דורש timers ומצב מתמשך, ולגביו יש לתאם את ההחלטה עם #3036.
5. למנות תחזוקה ל־engine pin, עדכוני אבטחה, בניות וכללי רישוי, ולבדוק בידוד מול קוד לא מהימן לפני מוצר. תהליך כלי הבדיקה והמגבלות המוכחות אינם ארכיטקטורת sandbox מלאה למובייל/דסקטופ.

עד להשלמת תנאים אלה, החלטת ההפעלה במוצר היא **NO-GO**. ה־PR מוסיף ניסוי משוחזר וחיבור תעבורה משותף שניתן לסקור, ומשאיר את החלטת המנוע וההפצה לשלב הבא.
