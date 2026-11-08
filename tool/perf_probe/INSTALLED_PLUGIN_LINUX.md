# תרחיש התוסף המותקן ב־Linux WPE

ה־workflow `installed_plugin_probe_linux.yml` מריץ את אותו
`installed_plugin_resource_probe_test.dart` של האפליקציה ב־profile. הוא
ממשיך את תרחיש [התוסף המותקן](WEBVIEW_RESOURCE_PROBE.md):
`app.main`, רישום תוספים, BLoC, מארח הכרטיסיה, `PluginBackgroundHost`, ה־SDK
וה־dispatcher אמיתיים. חמשת קובצי Store 2.13 נשארים מקובעים ומאומתים ב־SHA;
הקטלוג המבוקר, שתי בקשות ה־bootstrap החסומות, ההרשאות וה־audit הסופי נשארים
חלק מחוזה התרחיש המשותף.

## סביבת ההרצה

הבנייה משתמשת במתכון `build_linux` מתוך `flutter_tests.yml`: מארח
`ubuntu-26.04`, קונטיינר `debian:bookworm-slim`, Flutter 3.47.7, Clang 14,
JDK 17, תלויות GTK3 וה־SDK של WPE 2.48.7 תחת `/opt/wpe-sdk`. הנכס
`wpe-runtime-2.48.7-linux-x86_64.tar.zst` מה־release
`wpe-2.48.7-print-to-pdf` נבדק מול
`ca7e706c0ec2f66623fede2c369e3e13339448843e125f2ccd1553f4a3c4bcaf`.
`PKG_CONFIG_PATH`, `LD_LIBRARY_PATH` ו־`LIBRARY_PATH` מפנים ל־SDK הזה.
`VERSIONS` המקורי נשמר ב־artifact, כולל דגלי הבנייה של ה־SDK. התרחיש אינו
משנה את ה־SDK, את המנוע הנעול או את מדיניות התוספים של האפליקציה.

אחרי בניית profile, ה־runner מפעיל את ה־binary מאותה תיקיית bundle בעזרת
`flutter drive --use-application-binary`. הוא דורש את ספריות WPE, ה־injected
bundle ותהליכי העזר שה־CMake של המוצר אורז, בודק execute bits ותלויות
`ldd`, ואינו מתקן הרשאות או מחליף ספריות כדי לעבור את הבדיקה.

`xvfb-run` מקצה תצוגת X11 נפרדת עם אימות Xauthority; `dbus-run-session`
מקצה session bus נפרד. Openbox נדרש ומזוהה דרך `wmctrl` לפני התחלת
האפליקציה. כך בדיקות minimize/hide יכולות לקבל אישור אמיתי מ־GTK וממנהל
החלונות. אישור חסר, deadline או יציאת מנהל החלונות מכשילים את הריצה.
ה־runner מקצה קבוצת תהליכים בבעלותו ומנקה רק אותה בסיום או בכשל. תיקיית
`XDG_RUNTIME_DIR` פרטית להרצה, במצב `0700`.

אירועי `hide` ו־`show` הנייטיביים מגיעים מ־`window_manager` אל
`AppWindowListener.onWindowEvent`. המאזין מעדכן באמצעותם את נראות החלון
ב־dispatcher, גם כאשר לא נשלח אירוע focus. מצב המיזעור, נראות מסך הקריאה
ומצב חלונות אחרים נשארים תנאים נפרדים. בדיקת הרגרסיה שולחת אירועים דרך
ערוץ הפלטפורמה של החבילה; היא אינה תחליף לאישור GTK בתרחיש המלא.

ה־fixture משתמש ב־`synthetic-v2` ובסימון האתחול של ההגדרות, כפי
שנוסף ב־[#4417](https://github.com/Otzaria/otzaria/pull/4417). כך טעינת
`SettingsRepository` האמיתית משמרת את הגדרות המדידה המוכנות, ובהן ביטול
עדכונים ואינדוקס אוטומטי. הכנת הקבצים אינה מאתחלת את `Settings` הגלובלי;
בדיקת Hive מפעילה את מסלול הטעינה האמיתי ומאמתת את הערכים. נתוני fixture
מגרסה קודמת מחייבים הכנה חדשה.

## הרצה באותה סביבת Linux

יש להתקין תחילה את כל התלויות ואת ה־SDK כפי שמפורטים ב־workflow. נדרשים גם
Xvfb, xauth, DBus, Openbox, wmctrl, כלי X11 ו־Mesa. אין להריץ את הפקודות
באותה תיקיית נתונים של התקנת אוצריא קיימת.

```bash
installedLinuxRun=$(mktemp -d)
export INSTALLED_PROBE_DATA="$installedLinuxRun/data"
export INSTALLED_PROBE_OUTPUT="$installedLinuxRun/device"
export INSTALLED_PROBE_REPORTS="$installedLinuxRun/host"
export INSTALLED_PROBE_STORE_SOURCE="$installedLinuxRun/source"
export INSTALLED_PROBE_MACHINE_ID=local-linux-session-1
python3 tool/perf_probe/prepare_installed_plugin_source.py \
  --output "$INSTALLED_PROBE_STORE_SOURCE"
flutter pub get --enforce-lockfile
flutter build linux --profile --no-pub \
  --target=integration_test/installed_plugin_resource_probe_test.dart \
  --dart-define=INSTALLED_PROBE_FLUTTER_VERSION=3.47.7 \
  --dart-define="INSTALLED_PROBE_COMMIT=$(git rev-parse HEAD)" \
  --dart-define=INSTALLED_PROBE_IDLE_MS=1000
python3 tool/perf_probe/run_installed_plugin_linux.py \
  --output "$installedLinuxRun/session"
```

תיקיית session חייבת להיות חדשה. תיקיית `INSTALLED_PROBE_REPORTS` חייבת
להיות חסרה או ריקה לפני ההפעלה; ראיות קיימות מכשילות את ההכנה ונשמרות.
ברירת המחדל היא deadline של 22 דקות,
מעבר לתקציב 18 הדקות של התרחיש עצמו. ה־workflow מקצה זמן נפרד לבנייה
ולשמירת artifacts. `sessionExitCode=124` הוא כשל timeout, ואינו `unsupported`.

## ראיות וגבולות פירוש

ה־artifact `installed-plugin-linux-wpe-profile` מכיל לוגי הכנה, בנייה ו־drive,
מטא־נתוני מערכת וכלים, BOM של ה־SDK ומקור החנות, אבחוני CMake ככל שנוצרו,
`session/session.json`, לוגי Xvfb/Openbox ודוחות המארח והמכשיר. צעדי האיסוף
וההעלאה רצים גם בכשל; כשל מוקדם עשוי להשאיר רק חלק מהקבצים. ה־checkpoint
של התרחיש נשמר בכל שלב, וה־driver שומר דוח גם כאשר assertion נכשל.

`session.json` מפריד בין מסך ו־DPI שנמדדו ב־`xdpyinfo`, פרטי GLX של
התצוגה, גרסאות SDK דרך `pkg-config`, ותצפיות האפליקציה. הפרטים האלה אינם
אימות להאצת חומרה או למסלול software של WPE. בהיעדר API נייטיבי מתאים,
`nativeRenderMode`, `nativeRuntimeVersion` ו־`appGpuAndSoftwareRoute`
מסומנים `unavailable`; ה־user agent שנקרא מהמסמך נשמר בדוח התרחיש.
ה־viewport ו־device pixel ratio של Flutter נשמרים שם בנפרד.

הצלחה מחייבת exit code אפס, דוח Linux חדש ב־profile שעבר את החוזה המשותף,
מזהה הרצה שאינו ריק, שמות שלבים ללא כפילויות, מינימיזציה והסתרה שעברו,
והחזרת המדיניות. בנייה, בדיקות Python או בדיקות
חוזה אינן ראיית הרצת WebView. הריצה הראשונה על המקור
`2cdd6882a2358dbd28402396254e2f00ce4f2af0`
([Actions 42277725161](https://github.com/Otzaria/otzaria/actions/runs/42277725161))
עברה startup, פתיחה ראשונה, idle גלוי, מצב וגלילה ומיזעור עם חידוש אותו
מסמך. היא נכשלה בהסתרה: GTK אישר חלון מוסתר, אך ה־dispatcher עדיין דיווח
שהחלון גלוי. בנוסף נשמרו בקשות עדכון חסומות ואינדוקס לא מתוכנן, לפני תיקון
ה־fixture. שלבי התרחיש הבאים לא הורצו. אלה ממצאי כשל חלקיים; קבלת התרחיש
המלא אחרי התיקונים מחייבת artifact חדש שעבר. Xvfb ב־CI אינו מסך פיזי או
מדידת ביצועים של חומרת משתמש.

זיכרון המארח מסוג `RssAnon` וזיכרון תהליכי המנוע שנצפו חלקית נשארים
מדדים נפרדים, ללא ייחוס PID של renderer לכל כרטיסיה. אין כאן מדידת CPU,
GPU, PSS או קביעת חיסכון; אין להשוות את הריצה למערכות הפעלה אחרות או
למארח CI אחר. שלב `osBackground` ו־release נשארים `notRun` בהתאם לתרחיש
המשותף; מארח background נסתר בתוך האפליקציה אינו רקע של מערכת ההפעלה.
