# פעילות תוספי Apple בתוך האפליקציה

ניסוי עבור [#4120](https://github.com/Otzaria/otzaria/issues/4120), במסגרת
[#4124](https://github.com/Otzaria/otzaria/issues/4124). היעד מפעיל את `app.main`,
מתקין תוספים מקומיים ב־`PluginRegistryRepository` ומשתמש ב־`PluginTabPage`,
ב־`PluginBackgroundHost`, ב־SDK וב־`PluginRuntimeDispatcher` הרגילים.
הוא אינו מוסיף מסלול למוצר או משנה מדיניות השהיה.

`passed` בדוח פירושו שהתרחיש והבקרות הושלמו. הוא **אינו** קביעה ש־WebKit
ממשיך לפעול ברקע, שהמנוע הושהה, או שהושג חיסכון במשאבים. אין במסמך תוצאת
הרצה נייטיבית: תוצאה כזו קיימת רק בדוחות וביומנים של ריצה מזוהה.

## הכנה והרצה אוטומטית

נדרשים Flutter 3.47.7, Xcode וכלי שורת הפקודה שלו, Python 3 ו־CocoaPods
עם gem בשם `xcodeproj`. אם למנוע החיפוש המוצמד אין בינארי מפורסם, נדרש גם
Rust לבנייה הרגילה מהמקור. אין לעקוף את ה־hook או לשנות את ה־SDK.

```sh
flutter pub get --enforce-lockfile

python3 tool/perf_probe/apple_plugin_activity/run.py \
  --platform macos --mode profile --device macos \
  --output "$PWD/build/apple-quiet-macos"

# יש להחליף את המזהה ב־UDID של iPhone Simulator שכבר הופעל.
python3 tool/perf_probe/apple_plugin_activity/run.py \
  --platform ios --mode debug --device "$APPLE_SIMULATOR_ID" \
  --output "$PWD/build/apple-quiet-ios-simulator"
```

כל תיקיית פלט חייבת להיות חדשה וריקה, וללא symlink באבותיה. קלט האפליקציה
נוצר בתיקייה פרטית חדשה באמצעות `PerfFixture`, לפני `app.main`: ספרים
סינתטיים, מסדי נתונים והגדרות offline. נתוני משתמש אינם חלק מהניסוי.
התיקייה נשארת זמינה לבדיקה עד סיום התהליך; מוחקים אותה רק אחרי סגירתו.
גרסת `synthetic-v2` שומרת באחסון גם את הסימון `settings_initialized`,
כדי שהעלייה הרגילה לא תדרוס את ההגדרות שנזרעו. ההכנה אינה מאתחלת את
ה־Settings singleton של התהליך. קלט warm שהוכן בגרסה ישנה נדחה.

לפני חלון השקט הראשון נשמר צילום חד־פעמי `settingsAfterStartup` של
מפתחות הבידוד והעיצוב שנזרעו. הוא נקרא מה־Settings הפעיל לאחר עליית
האפליקציה ומוכנות התוסף, בלי לאתחל או לשנות הגדרות. ה־checkpoint נשמר
לפני האימות; ערך חסר או שונה מכשיל את התרחיש לפני `arm`. צילום זה אינו
polling בזמן השקט או הבטחה שאין פעילות מערכת אחרת.

ה־CI ב־`apple-plugin-activity.yml` מריץ macOS **profile** ואת iOS Simulator
ב־**debug**. Flutter אינו תומך ב־profile ב־Simulator. ה־runner אינו מחליף
profile ב־debug בשקט ואינו מייחס תוצאת Simulator למכשיר פיזי.

הכנת פרויקט הבקרה ב־Ruby מקבלת תקציב תשתית נפרד של 120 שניות, לפני
בניית האפליקציה. `create-control-project.json` שומר זמן, קוד יציאה ותוצאת
timeout; שני יומני הפלט נשמרים גם בכשל, עד 64KiB לכל זרם, עם מספר הבתים
וסימון חיתוך. הודעות השלב ב־stderr מזהות כניסה ל־Ruby, טעינת ספריות,
כתיבת מקורות, שמירת הפרויקט ושמירת ה־scheme. אין retry או המרת timeout
להצלחה. תקציב זה אינו משנה את זמני השקט או המעברים.

ב־macOS נשמר אותו אובייקט `NSRunningApplication` לאורך כל שלב, והבקר
מאמת אותו מול האפליקציה הנוכחית באמצעות `isEqual`, כמתואר ב־
[תיעוד Apple לזהות תהליך](https://developer.apple.com/documentation/appkit/nsrunningapplication/processidentifier).
`launchDate` נשמר כנתון אופציונלי: Apple מתעדת שהוא זמין רק להפעלה דרך
[LaunchServices](https://developer.apple.com/documentation/appkit/nsrunningapplication/launchdate),
בעוד Flutter יכול להפעיל את ה־executable ישירות. האימות מחייב גם PID,
נתיב executable, זהות בקר ואסימון session קבועים. החלפת תהליך או סיום
התהליך המקורי מכשילים את השלב. הבקר מפעיל `NSApplication.run()` על ה־main thread, עם מדיניות הפעלה
שאינה לוקחת focus מהאפליקציה. קריאת stdin מתבצעת ב־thread נפרד;
פקודות הגבול חוזרות ל־main thread. לפי
[תיעוד NSRunningApplication](https://developer.apple.com/documentation/appkit/nsrunningapplication),
תכונות משתנות מתרעננות אחרי סיבוב של ה־main run loop. אין timer של
ה־probe, שאילתת target או פקודת אפליקציה בין פקודות הגבול. לולאת AppKit
עצמה נשארת פעילה והיא חלק מתקורת הבקר החיצוני.

הסתרה חיצונית מחייבת גם `hide() == true` וגם `isHidden == true`, בתוך
חמש שניות. חזרה מחייבת אישור הפעלה ואותה זהות תהליך, ללא relaunch.
ה־Python verifier דורש גם הוכחה של event loop פעיל. הצלחה של הסתרה
עצמית אינה מחליפה את התנאים האלה.

בקרות העזר מריצות את **אותו bundle** בשני אופנים: executable ישיר
ו־`NSWorkspace.openApplication` דרך LaunchServices, עם instance חדש
וללא החלפתו באפליקציה קיימת. בקר LaunchServices מחזיק את האובייקט
שה־API החזיר ומסיים רק אותו, עם ניקוי מוגבל וזהות שמורה. התוצאות של
`direct-execution.json`, `launch-services-execution.json`, `self-hide.json`
ובקרת תהליך שהסתיים נפרדות. שדות `launchDate`, activation policy,
`isFinishedLaunching` ו־event loop נשמרים כאבחון; היעדר launchDate
במסלול הישיר אינו כשלעצמו הוכחה לסיבת סירוב hide.

אוצריא עצמה ממשיכה להיבדק דרך Flutter drive והפעלת ה־executable
הרגילה שלו. ה־CI מריץ את מסלול היישום גם אחרי כשל בבקרת עזר, כל עוד
פתרון התלויות ובחירת המערכת הושלמו; כשל העזר עדיין מכשיל את ה־job.
כך אין קבלת אפליקציה מתוך fixture בלבד. הצלחת LaunchServices אינה
fallback שמחליף כשל בהפעלה הישירה. דוחות הכשל הישנים של הבקר ללא
event loop ושל הבקר עם `NSApplication.shared` בלבד נשארים ראיות
היסטוריות; סיבת ה־hide שסירב בהם אינה מוכרעת על ידי השינוי הזה.

ה־pin של `window_manager` הוא `88a433a7be43ed0213da12b561bf0d8d070c6d68`.
המאזין הכללי ל־show/hide ובדיקותיו זהים ל־#4424; הם מחברים את אירועי
הנראות הנייטיביים ל־dispatcher בלי להקל את תנאי המדידה. בדיקות הפורק
אינן הוכחת external-hide של אוצריא.

שירות ההפעלות החיצוניות בודק `FileSystemEntity.isWatchSupported` לפני
יצירת watcher ברירת המחדל. כשמעקב קבצים אינו נתמך, כמו בריצת iOS,
הערוץ הנייטיבי וניקוז התור ממשיכים לפעול. בפלטפורמה שתומכת במעקב נשמרים
אירועי התיקייה הרגילים, ושגיאת יצירה אינה נבלעת.

`--seconds` קובע מינימום שקט של 6–60 שניות לתרחישים הקצרים; ברירת המחדל
היא 12. בקר iOS עשוי להאריך את החלון בתוך תקציב המעבר המוצהר. משתמשים
בגבולות שנמדדו, ולא במספר המבוקש, לחישוב התוצאה. בקרת התפוגה משתמשת
ב־190 שניות לפחות ובטיימר האמיתי של אוצריא, ללא האצת זמן.

## חיי הבקר, זהות המקור וכשלים

ב־iOS Simulator נבנה תחילה היעד המדויק ב־DEBUG, עם `--simulator`,
`--no-pub`, ה־target וקובץ ה־defines של הריצה. רק אחרי הבנייה ואימות
ה־bundle מתחיל XCUITest. Flutter drive מקבל את אותו `Runner.app` דרך
`--use-application-binary`. מסלול `.app` נתמך במימוש Flutter 3.47.7 של
[IOSApp.fromPrebuiltApp](https://github.com/flutter/flutter/blob/abaf9c523780a608bd46686fd5e53740a07077f8/packages/flutter_tools/lib/src/ios/application_package.dart).
מספר ניסיונות העלייה הפנימיים של Flutter לא שונה. Manifest של תוכן
ה־bundle ושל ה־defines נבדק שוב לפני drive; גם executable האפליקציה
שהותקנה חייב להתאים ל־hash שנבנה.

כל `arm` דורש challenge חדש בתוך חמש שניות, מאותו run, PID, boot token
ו־session של XCUITest. בדיקת תהליך xcodebuild החי מתבצעת לפני חלון
השקט. Event ישן של readiness אינו מספיק. אחרי arm הבקר מפסיק בקשות
בזמן השקט; תגובת הגבול מתקבלת פעם אחת בתוך deadline שמתאים להמתנה
החד־פעמית של האפליקציה. אין ניסיון חוזר או polling בזמן השקט. סיבת
ה־HTTP timeout בריצה הישנה אינה ידועה; הקדמת הבנייה מתקנת את סדר חיי
התהליכים ואינה טוענת שסיבת timeout זו הוכחה.

ה־runner קורא את ה־lock וה־pubspec מתוך commit נקי, ודורש זהות לקבצים
המקומיים. כל שמונת רכיבי WebView חייבים להיפתר לאותו Git ref ולקובצי
המקור המחויבים של כל root. הבדיקה חוזרת אחרי הבנייה ואחרי הסגירה.
`nativeFork` ו־`lockSha256` בדוח Dart מגיעים מ־defines של מקור מאומת זה;
השרת דוחה דוח ישן או pin מעורב. אין SHA נייטיבי קשיח בתוך דוח האפליקציה.

קובצי הפרויקט של iOS כוללים את migration ה־SwiftPM הדטרמיניסטי של
Flutter 3.47.7. זהו אותו migration ש־Flutter מוסיף בעת build, כפי
שמתואר ב־[תיעוד Flutter](https://docs.flutter.dev/packages-and-plugins/swift-package-manager/for-app-developers).
הקבצים הופקו באמצעות מחלקת ה־SDK המקורית ונבדקו להעדר שינוי במעבר
שני. היצירה המקומית אינה Xcode validation; בניית Apple ובדיקת מקור
נקי אחריה נדרשות ב־CI. אין opt-out, reset או היתר לשינוי שרירותי במקור.

שגיאה ראשונה נשמרת כאובייקט המקורי; כשלים נוספים בכתיבת ראיות ובניקוי
נרשמים לפי סדרם. ניקוי אפליקציה, בקר, עובדי quiet ושרת ננסה בנפרד ובזמן
מוגבל. ביטול בזמן quiet מעיר רק את ההמתנה המקומית, מסמן חלון חלקי
ומנקז את הבקר שבבעלות העובד. כשל בראיות בלבד עדיין מכשיל את הריצה.
כאשר גם קובץ הסיכום אינו ניתן לכתיבה, תיאור שגיאות מוגבל נשמר ב־stderr
ובאובייקט השגיאה. דוחות ישנים אינם מאופסים או מחליפים את התוצאה החדשה.

## התרחישים והבקרות

| שלב | פעולה | מה ניתן לבדוק |
|---|---|---|
| `visible` | לשונית תוסף אמיתית בחזית | בקרת חיוב: interval, rAF ועבודה אסינכרונית מקומית חייבים להתקדם בתוך חלון השקט |
| `offstage` | מעבר למסך הספרייה וחזרה לקריאה בלי לסגור את הלשונית | זהות controller, מסמך ו־canary נשמרת מלפני ההסתרה, דרך המצב המוסתר ועד אחרי ההצגה מחדש |
| `minimize` / `hide` | מזעור/הסתרת החלון דרך `window_manager` ואימות נייטיבי | התנהגות חלון macOS; פעולות אלה מסומנות `notSupported` ב־iOS |
| `neverShownBackground` | הפעלה עצלה אמיתית דרך `app.startup`, בלי פתיחת לשונית | מופע עם `startup.keepAlive: true` והרשאת `app.background_keep_alive` שמורה ומאומתת |
| `osBackground` | macOS: `NSRunningApplication.hide`; iOS: `XCUIDevice.press(.home)` | מצב חיצוני בגבולות, חזרה באמצעות API ציבורי ושימור זהות/מצב |
| `idleExpiryControl` | אותו HTML ברקע, בלי הצהרת keepAlive ובלי ההרשאה, לצד מופע keepAlive | פינוי על ידי טיימר שלוש הדקות של אוצריא, בנפרד מהשהיה של WebKit |

ה־fixture מפעיל `setInterval` כל 250ms, `requestAnimationFrame`, ולולאה
מקומית של `setTimeout` + המשך Promise + חישוב. העבודה האסינכרונית אינה
קריאת SDK ואינה מאריכה את זמן החיים של מופע הרקע. אין בו fetch, מדיה,
הדפסה לקונסול או RPC מחזורי. הוא מתעלם במכוון מ־`plugin.suspended` כדי
לבדוק את התזמון הנייטיבי; תוסף מוצר אמור לעצור את עבודתו בעקבות האירוע.

לפני השקט ממתינים לסיום boot ועבודת SDK של הרקע, ולמצב dispatcher יציב
בלשונית. קוראים פעם אחת את מוני הדף ואת הגטר הציבורי
`getAppleWebViewActivitySnapshot`. כל שמונת רכיבי הפורק מוצמדים ל־
`124bb8e63f345ffd0b0f2ea7190c24b19e69897d` — reference ציבורי יציב הכולל את
הגטר של [native #55](https://github.com/Otzaria/flutter_inappwebview/pull/55)
ואת תיקון הבעלות על GlobalKey ב־Android של
[#56](https://github.com/Otzaria/flutter_inappwebview/pull/56), לצד ברירת
המחדל המאושרת של #53. אין כאן הפעלה של WithReply או שינוי
`inactiveSchedulingPolicy` / `pauseTimers`.

בקשת `arm` לתיאום מסתיימת ונסגרת לפני תחילת השקט. במהלך החלון אין מצד
הניסוי קריאות JS, גשר/IPC, polling, פקודות, רשימת תהליכים או דגימת CPU.
גם בקר ה־XCUITest מפסיק את תיאום ה־HTTP בכל חלון שקט, לרבות החלונות שבהם
לא נלחץ Home. טיימרים ואירועי lifecycle רגילים של **המוצר** נשארים פעילים
לפי מדיניותו; הניסוי אינו טוען שכל תעבורת המערכת הופסקה.

הבקר החיצוני מסיים את המדידה לפני activate/הצגת החלון. לאחר מכן הגטר
הנייטיבי נקרא שוב. **קריאת JS הראשונה שהניסוי יוזם** היא מסירת פקודת אפליקציה דרך
ה־Dispatcher וה־SDK, ורק אחריה נקראים המונים והאישור. כך הקריאה לצורך
מדידה אינה מעירה קודם את הדף. אירועי lifecycle של המוצר נשארים ללא שינוי.
בזמן Home, חזרת האפליקציה
באמצעות activate כבר קדמה לפקודה; הדוח מפריד בין שני האירועים.

ב־`offstage` ה־canary נוצר פעם אחת לפני ההסתרה. זהות המופע והמסמך נבדקת
גם כשהלשונית מוסתרת וגם לאחר החזרה לקריאה. הפקודה שאחרי השקט נמסרת
עדיין במצב מוסתר; בדיקת ההצגה מחדש נפרדת ממנה, והשלב מסומן כהצלחה רק
אחרי שתיהן. אין הנחה ש־Offstage משאיר את ה־view מחובר לחלון.

## פירוש הדוח

- `environment.json`: commit/tree, מצב מקורות, Flutter/Dart/Xcode/SDK, OS,
  מצב הבנייה, בחירת Simulator, מקור entitlements ותוצאת `codesign` של
  האפליקציה שנבנתה. Sandbox של `DebugProfile` ב־macOS כבר כבוי במקור;
  ה־runner אינו משנה אותו או את ATS כדי להשיג הצלחה.
- `partial-app.json`, `app-report.json`, `complete.json`: זהות תהליך
  האפליקציה, boot של האפליקציה, controller, document token, מספר אירועי
  boot, שמירת מצב, רשות keepAlive, מונים ופקודות. שינוי זהות, reload,
  dispose בלתי צפוי או relaunch אינם מוצגים כ־resume תקין.
- `driver-*.json`: תחילת/סוף שקט בשעון חיצוני ובשעון מונוטוני, תקציב
  התיאום, פעולת OS, מצב לפני/אחרי ותוצאת CPU. קבצים חלקיים נשמרים גם
  בכשל; timeout אינו מסומן כהצלחה.
- `nativeBefore` / `nativeAfterResume`: זמן בקשה, זמן capture נייטיבי,
  עיכוב מסירה, `view.window`, נראות ה־view והאבות, מצב האפליקציה,
  חלון macOS או scene של iOS, וזמינות מדיניות WebKit בגרסת OS זו.
  בזמן מעבר OS אין בקשת גטר באמצע השקט; מצב היסטורי של ה־view ברקע
  מסומן `unavailable`. צילום אחרי חזרה אינו משחזר אותו.
- `streams`: כל callback מקבל `Date.now()` ו־`performance.now()` **כשהוא
  מבוצע**. גבולות הפרש השעונים נמדדים בבקשת התיאום, ונוספת רצועת אי־ודאות
  של שנייה בכל קצה. callbacks שהורצו אחרי החזרה אינם נספרים בתוך השקט.
  חוסר התאמה בין שעון קיר למונוטוני מבטל מסקנות זמניות. יש מונה dropped
  מפורש מעל 32,768 רשומות לכל stream, וכן גיל קריאה מאוחרת.
- יחס שעון הקיר למונוטוני נבדק גם בכל callback שנשמר, מול שתי קריאות
  הגבול. קפיצה זמנית וחזרה של שעון הקיר אינה נעלמת בגלל הסכמת הקצוות:
  סתירה מעל סף 250ms הקיים מסמנת את כל streams כ־`clockUncertain`,
  ומחליפה את מסקנות חלון הזמן ב־null. הרשומות הגולמיות, totals ו־dropped
  נשמרים, ו־`maxCallbackClockDriftMs` מתעד את הפער הגדול ביותר שנצפה.
  גבולות הפרש השעונים ורצועת אי־הוודאות אינם משתנים.
- `identityWhileHidden` / `whileHidden` ו־`identityAfterShow` / `afterShow`
  משמרים את שתי תצפיות ה־Offstage מול `identityBefore` / `before` מלפני
  ההסתרה. `nativeAfterShow` הוא גבול נוסף אחרי הצגה; קריאת המונים בשלב
  זה אינה משנה בדיעבד את ניתוח חלון השקט.
- `hostCpuEnvelope`: CPU מצטבר ו־RSS של PID האפליקציה בלבד, דרך `/bin/ps`
  אחרי אימות נתיב executable וזמן התחלת התהליך. ב־macOS נתיב האפליקציה
  מאומת גם באמצעות `NSRunningApplication` שזהותו נשמרת; ב־Simulator נבדק
  הנתיב שהאפליקציה דיווחה. החלון כולל את המעברים
  ואת תקורת הגבולות; זה אינו CPU נקי של השקט. אין הסקה על CPU או זיכרון
  של WebContent/GPU/network services. ללא שיוך ציבורי מאומת הנתון חסר,
  ואינו מוחלף ב־0 או ב־PID שנבחר לפי שם תהליך.

אין callbacks שנצפו אינו הוכחת suspension; callbacks שנצפו אינם הוכחת
ריצה רציפה. `longestRecordedInteriorGapMs` מתייחס רק לרווחים שבין רשומות
שנשמרו בתוך החלון. לוג נפילת תהליך התוכן הוא הלוג הרגיל של המארח, עם
הגבלת הקצב שלו; אין להסיק מהיעדר שורה שמספר הנפילות היה אפס.

`DeveloperDiagnostics` חייב להיות כבוי. היעד משתמש במפורש ב־
`LiveTestWidgetsFlutterBindingFramePolicy.fullyLive`, כדי לא למנוע פריימים
אמיתיים של platform views. עצם ה־integration test, מדידות הגבול, ה־fixture,
Flutter driver/VM service וה־XCUITest הם תקורת תצפית. תוצאה זו אינה
baseline של מוצר ללא מכשור.

## מכשיר iOS פיזי — profile ו־release בנפרד

אלה פקודות מעבדה, **לא הרצה שבוצעה או תוצאת CI**. נדרשים מכשיר מצומד,
Developer Mode וצוות חתימה עם provisioning מתאים. לצורך תיאום חייב
להיות כבר endpoint HTTPS מהימן במעבדה, שמעביר את הבקשות ל־loopback של
ה־Mac. ה־runner אינו מקים שירות חיצוני, מוסיף חריג ATS, מחליף אימות TLS
או מתקין תעודת אמון. כתובת `.example` להלן היא מציין מקום שיש להחליף.

בטרמינל הראשון, מתוך תיקיית המאגר:

```sh
python3 tool/perf_probe/apple_plugin_activity/run.py \
  --serve-only --platform ios --mode profile --device "$APPLE_DEVICE_ID" \
  --public-url 'https://trusted-lab.example' --port 8765 \
  --output "$PWD/build/apple-quiet-physical-profile"
```

כאשר הודעת ההכנה מופיעה, בונים תחילה את האפליקציה באמצעות פקודות
הבנייה שלהלן. רק לאחר סיום הבנייה מתחילים את בקר XCUITest בטרמינל נפרד:

```sh
PROBE_OUTPUT="$PWD/build/apple-quiet-physical-profile"
xcodebuild test \
  -project "$PROBE_OUTPUT/control/Control.xcodeproj" \
  -scheme AppleQuietControl -destination "platform=iOS,id=$APPLE_DEVICE_ID" \
  -derivedDataPath "$PROBE_OUTPUT/control-build" \
  -resultBundlePath "$PROBE_OUTPUT/control.xcresult" \
  -parallel-testing-enabled NO -allowProvisioningUpdates \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM="$APPLE_TEAM_ID"
```

את פקודות הבנייה הבאות יש להשלים לפני התחלת XCUITest; את שתי פקודות
`devicectl` האחרונות מפעילים רק אחרי שהבקר מוכן. כך גם במסלול הידני
אין המתנה של בקר חי לבנייה ארוכה:

```sh
PROBE_OUTPUT="$PWD/build/apple-quiet-physical-profile"
rustup target add aarch64-apple-ios
flutter build ios --profile --no-codesign \
  --target=integration_test/apple_plugin_activity_probe_test.dart \
  --dart-define-from-file="$PROBE_OUTPUT/defines.json"
xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner \
  -configuration Profile -sdk iphoneos -destination "platform=iOS,id=$APPLE_DEVICE_ID" \
  -derivedDataPath "$PROBE_OUTPUT/app-build" -allowProvisioningUpdates \
  CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM="$APPLE_TEAM_ID"
PROBE_APP="$PROBE_OUTPUT/app-build/Build/Products/Profile-iphoneos/Runner.app"
codesign -d --entitlements :- "$PROBE_APP" > "$PROBE_OUTPUT/signed-entitlements.txt" 2>&1
xcrun devicectl device install app --device "$APPLE_DEVICE_ID" "$PROBE_APP"
xcrun devicectl device process launch --device "$APPLE_DEVICE_ID" com.mendelg.otzaria
```

לריצת **release** מתחילים ריצה חדשה עם תיקיית פלט חדשה, `--mode release`
בבקר, `flutter build ios --release`, `-configuration Release` ו־
`Release-iphoneos/Runner.app`. אין Flutter driver או debugger מחובר במסלול
ההפעלה הידני; הדוח הסופי נשלח רק אחרי תוצאת מסגרת הבדיקה. בניית profile
עדיין כוללת VM service, ולכן נשמרת ההבחנה בינו לבין release.

`devicectl process launch` משמש רק להפעלה הראשונית. מעברי הרקע בניסוי
משתמשים ב־Home וב־`XCUIApplication.activate()`. מאחר ש־activate יכול
להפעיל תהליך מת מחדש, ה־coordinator דוחה PID/boot חדשים. אין שימוש
ב־terminate/launch כתחליף ל־resume או ב־`UIApplication.suspend` פרטי.
CPU של תהליך iOS פיזי מסומן חסר: `ps` של ה־Mac אינו מודד אותו. לשם הערכת
CPU/אנרגיה פיזית נדרש מכשור נוסף בריצה נפרדת ותיעוד התקורה שלו.

## גבולות אימות ומקורות

| מערכת | מסלול כאן | גבול המסקנה |
|---|---|---|
| macOS | actual app profile ב־CI | רק ה־OS/SDK ומצב החלון שנמדדו; ללא CPU כולל של WebKit |
| iOS Simulator | actual app debug + XCUITest | התנהגות פונקציונלית, ללא מסקנת השעיה או אנרגיה במכשיר פיזי |
| iOS פיזי | פקודות מעבדה נפרדות profile/release | `notRun` עד לצירוף תוצאה מזוהה; אין תוצאת CPU פיזי אוטומטית |
| Windows / Linux / Android | לא נתמכים ביעד Apple הזה | נשארים `notRun` במטריצת חמש המערכות; אין העתקת תוצאת Apple אליהם |

מקורות ראשוניים לבדיקה מול גרסת המערכת שנמדדה:

- [W3C: High Resolution Time](https://www.w3.org/TR/hr-time-3/#clocks):
  טיוטת העבודה מבחינה בין שעון קיר שניתן לתקן לבין שעון מונוטוני.
  בדיקת זוג הזמנים בכל רשומה אינה מניחה סנכרון מושלם עם הבקר החיצוני.
- [Apple: inactiveSchedulingPolicy](https://developer.apple.com/documentation/webkit/wkpreferences/inactiveschedulingpolicy-swift.property):
  תיאור המדיניות עבור view שאינו בחלון, ברירת המחדל והחריגים; זמינות החל
  מ־iOS 17 / macOS 14. הגטר קורא את ההעדפה ואינו מדווח על השעיה בפועל.
- [Apple: activate](https://developer.apple.com/documentation/xcuiautomation/xcuiapplication/activate()):
  בפסקת Discussion מוסבר שיישום שאינו רץ יופעל מחדש.
- [Apple: Home](https://developer.apple.com/documentation/xcuiautomation/xcuidevice/button/home)
  ו־[press](https://developer.apple.com/documentation/xcuiautomation/xcuidevice/press(_:)):
  פעולת המכשיר הציבורית שבה משתמש הבקר.
- [Apple: NSAllowsLocalNetworking](https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nsallowslocalnetworking):
  ב־Discussion מובחנים שמות מקומיים לא מסויגים מכתובות IP, ובפסקה המתחילה
  `In iOS 17` מתוארת הגבלת IP החדשה. לכן ב־Simulator משתמשים ב־`localhost`
  ללא שינוי ATS. זהו נימוק לבחירת הכתובת; רק הריצה מוכיחה שהמסלול עובד
  ב־OS/SDK המסוימים.
- [Apple: כלי שורת הפקודה למכשירים](https://developer.apple.com/documentation/xcode/interacting-with-devices-using-the-command-line):
  התקנה והפעלה ראשונית עם devicectl.
- [Flutter 3.47.7, macOS compositor](https://github.com/flutter/flutter/blob/abaf9c523780a608bd46686fd5e53740a07077f8/engine/src/flutter/shell/platform/darwin/macos/framework/Source/FlutterCompositor.mm)
  ו־[iOS platform views](https://github.com/flutter/flutter/blob/abaf9c523780a608bd46686fd5e53740a07077f8/engine/src/flutter/shell/platform/darwin/ios/framework/Source/FlutterPlatformViewsController.mm):
  הסרת views שאינם בקומפוזיציה. עדיין יש למדוד `windowAttached` באפליקציה,
  ולא להסיק אותו רק מקריאת הקוד.

בדיקות מקומיות של החוזה אינן תחליף להרצת Apple:

```sh
node --test tool/perf_probe/apple_plugin_activity/test_fixture.mjs
python3 -m unittest discover -s tool/perf_probe/apple_plugin_activity -p 'test_*.py' -v
flutter test --no-pub test/tool/perf_probe/apple_plugin_activity_contract_test.dart
flutter analyze --no-pub
```
