# Audit תלויות וביצועים — מצב פעולה, 8 בנובמבר 2026

> בסיס: `dev@46b4af5313c8c550ace1b72f90aa26fa9455a320`. מסמך המקור מ־4 בנובמבר סקר 61 מאגרים, 70 תלויות runtime ישירות (כולל SDK) ו־274 רשומות lock. מסמך זה מעדכן את **מצב הביצוע** מול GitHub ולא מתיימר להציג סקירה מחדש של כל 274 החבילות. הסטטוסים, ה־pins ותוצאות ה־CI להלן הם תמונות מצב היסטוריות מ־8 בנובמבר, אלא אם נאמר אחרת. אין להסיק מהם מצב PR או אישור מיזוג נוכחי.

## עדכון מאומת — 9 בנובמבר 2026

- בבסיס `dev@049247dc2af92af8c38e04cac9af3a36980d2f10`, חבילות pdfrx נעולות ל־`d898e52b1526532c8d66a5f7fee0ca6b867a77d0`: ה־hook כולל fallback דרך GitHub API ואימות SHA-256 לפני חילוץ. Otzaria/pdfrx #3 ו־app #4516 מוזגו; #4517 נסגר ללא מיזוג. #4482 פתוח לביקורת ואינו Draft.
- הוסרה מ־workflow המדידה שתילה ידנית של PDFium ב־hook cache, גם בגנרטור Linux וגם בבניית Android. כשל build, לרבות כשל checksum, חייב לעצור את המדידה. לא שונו כלי המדידה או המספרים ההיסטוריים. לאחר הוספת flavors ב־#4500, המדידה בוחרת `direct`; יעד ARM64, דגל `analyze-size` ו־artifact ה־JSON ללא שינוי.
- מדידת ARM64 המוצלחת שלהלן היא תוצאת הריצה ההיסטורית, שבה היה מסלול השתילה. היא אינה אישור לבנייה עם ה־workflow המתוקן; בנייה מלאה שלו טרם אומתה.

## סיכום מנהל

1. מרבית P1 של מסמך המקור כבר תוקנו ומוזגו בנפרד. לא לפתוח עבודות כפולות.
2. שיפור גודל מדוד: WPE runtime יכול להצטמצם ב־**42,586,800 bytes ב־x64** וב־**46,794,240 bytes ב־arm64**, במדידת `strip --strip-unneeded` על ELF; זה **לפני דחיסת ההפצה**, ולא חיסכון מותקן שנמדד מחדש. PR יישום #4519.
3. תיקון Linux נוסף: אייקון 256px שכבר קיים חוסך צפוי **2,145,630 bytes לא דחוסים** בשני נתיבי package icon, PR #4521; טרם נבדק כחבילת release חדשה.
4. זוהה סיכון גרסאות PDFium אמיתי: printing Linux נבנה מול Chromium 5200, אך ב-release נכלל בדיוק PDFium 8125 של pdfrx. אין עדיין ראיה לקריסה. [Issue #4527](https://github.com/Otzaria/otzaria/issues/4527).
5. אין הצדקה כעת להסיר את Flutter, Bloc, SQLite, Tantivy, PDFium, Quill או WebView, או לחזור אוטומטית ל-upstream של forks שנשענים על patches שלא שוחררו.

## PRים חדשים במסגרת audit התלויות

| רכיב | PR | שינוי | QA עד כה | שלב |
|---|---|---|---|---|
| מדידת release | [#4482](https://github.com/Otzaria/otzaria/pull/4482) | גדלי ZIP/DEB/APK, install-root, זהות PDFium, ניסיון analyze-size | יחידות Python ב־3 מערכות עברו בעבר; 5 מניפסטי התקנה עברו; מדידת PDFium עברה; הורדות release וה־native hooks מחייבות QA חוזר | Draft |
| Markdown | [#4515](https://github.com/Otzaria/otzaria/pull/4515) | `flutter_markdown` לא מתוחזק → `flutter_markdown_plus 1.0.12`, שני imports ו־lock | Lockfile, Analyze, Linux/Windows builds וכל 5 shards עברו; native Windows/macOS נכשלו ב־checksum/הורדה חיצוניים | Draft |
| Windows notifications | [#4516](https://github.com/Otzaria/otzaria/pull/4516) | נעיצה לתיקון `delete[]` ב־FFI | fork#4 עבר ASan/UBSan; app Analyze/5 shards/Linux עברו; Windows native blocked ב־ONNX download ו־macOS sqlite checksum | Draft |
| pdfrx | [#4517](https://github.com/Otzaria/otzaria/pull/4517) | pin לענף upstream #798 המלא, בסיס 2.12.0 + `pdfrx_engine 0.9.1` | Lockfile Guard עבר; עוד אין CI אפליקטיבי ירוק עקב PDFium 504, WPE release download ו־sqlite checksum | Draft |
| WPE strip | [#4519](https://github.com/Otzaria/otzaria/pull/4519) | strip רק לבינארי WPE בתוך bundle, עם `NEEDED/SONAME` ו־dependency checks | QA ייעודי ב־x64 + ARM64 **עבר**; full release smoke עדיין נדרש | Draft |
| Linux icon | [#4521](https://github.com/Otzaria/otzaria/pull/4521) | שימוש ב־`icon_256.png` לאריזת DEB/RPM | Lockfile Guard עבר; full Flutter CI נפגע מהורדות PDFium/WPE | Draft |
| Linux printing | [#4522](https://github.com/Otzaria/otzaria/pull/4522) | צריכת `Otzaria/dart_pdf#1` | fork: 60-page native integration ב־x64/ARM64 עבר; app CI חסום בהורדות חיצוניות | Draft |

PRים נפרדים של forks וכלים:
- [WPE runtime #8](https://github.com/Otzaria/otzaria-wpe-runtime/pull/8) — מדידת strip מלאה ותקינה בשתי הארכיטקטורות; אינה משנה SDK;
- [dart_pdf #1](https://github.com/Otzaria/dart_pdf/pull/1) — raster ב־worker, lifetime ל־print_job ול־channel, ומקור PDFium נתון ב־CMake; CI x64+ARM64 **עבר**;
- [flutter_local_notifications #5](https://github.com/Otzaria/flutter_local_notifications/pull/5) — helper isolate לשאילתות הסינכרוניות + deferred dispose ו־NativeCallable lifetime; Windows builds/unit tests ו־analyzer עברו לפני תיקון format; מסלול format תוקן, נדרש אישור CI חוזר; Android Gradle download הוא כשל תשתית;
- [win11-oneocr #1](https://github.com/Otzaria/win11-oneocr/pull/1) — HTTP admission קשיח, קובץ זמני בזרימה, SHA וגודל במהלך כתיבה, שמירת קובץ אטומית; **4/4 עבודות CI עברו** (Linux/Windows × Python 3.11/3.13);
- [Otzaria_Website #257](https://github.com/Otzaria/Otzaria_Website/pull/257) — benchmark production converter ו־CI; **עבר**, נתוני baseline להלן.

## מצב P1/P2 של האפליקציה המקורית

| ממצא מקורי | מה קיים עכשיו | הכרעה |
|---|---|---|
| ShaperFont attached buffers ו־owner lifetime | [#4302](https://github.com/Otzaria/otzaria/pull/4302) מוזג; מסלולי printing/calendar/tikkun מחזיקים dispose/finally | טופל בקוד; רצוי להמשיך native lifecycle stress במכשיר |
| PDF preview קורא קובץ מלא, מרנדר 60 עמודים | [#4301](https://github.com/Otzaria/otzaria/pull/4301), [#4315](https://github.com/Otzaria/otzaria/pull/4315), [#4316](https://github.com/Otzaria/otzaria/pull/4316) מוזגו | path/viewport/byte-bounded UI כבר מיושמים; לא לפתוח חלופה |
| Quill serialization בשינוי selection, controllers ללא dispose | PR [#4303](https://github.com/Otzaria/otzaria/pull/4303) נסגר ללא מיזוג, אך קוד `dev` כבר מאזין ל־`quillController.changes` ומשחרר controllers בדיאלוג וב-inline | בדיקת קוד מראה תיקון התנהגות נצרכת; לא להסיק ש־#4303 מוזג |
| PluginDownloadService ללא unregister/dispose | ב־`dev`: `_ownsClient`, `HttpClientRegistry.unregister`, `dispose` מתוך `PluginSystemBloc.close()` | טופל; שמירה על ownership של client מוזרק |
| DB fallback ותורים חיים | [#4390](https://github.com/Otzaria/otzaria/pull/4390), [#4423](https://github.com/Otzaria/otzaria/pull/4423) מוזגו | שומר גבולות ועומסים תקועים; לא להחליף בתיקון נוסף |
| קורא ספר ארוך עם O(n) copies | [#4307](https://github.com/Otzaria/otzaria/pull/4307) פתוח | אבטיפוס נפרד; נדרש למדוד parity/latency לפני merge |
| תיאום פינוי זיכרון | [#4297](https://github.com/Otzaria/otzaria/pull/4297) ו־[#4412](https://github.com/Otzaria/otzaria/pull/4412) מוזגו | טופל |
| סגירת IndexWriter על UI | [engine #77](https://github.com/Otzaria/otzaria_search_engine/pull/77) ו־[app #3981](https://github.com/Otzaria/otzaria/pull/3981) **מוזגו שניהם** | טופל; שימור קריאות close/reset |
| תקצוב CPU אינדוקס | engine [#80](https://github.com/Otzaria/otzaria_search_engine/pull/80) מוזג, app [#4416](https://github.com/Otzaria/otzaria/pull/4416) פתוח | לא לפתוח PR מתחרה; שינויים משפרים latency במחיר throughput |
| ORT 2.0.0-rc.15 | engine [#79](https://github.com/Otzaria/otzaria_search_engine/pull/79) מוזג, אבל `dev` עדיין צורך b78/rc.13 | המעבר באפליקציה הופרד במכוון ב־#4416 בעקבות רגרסיית חיפוש במירכאות; לא לבצע pin עיוור |
| WebView suspend/discard/snapshot | [#4475](https://github.com/Otzaria/otzaria/pull/4475) **מוזג**; patches של upstream עדיין לא שולבו כולם | fork נשאר נדרש; לא לשכתב wrapper |
| Streaming library updater | [updater #42](https://github.com/Otzaria/otzaria_library_updater/pull/42) מוזג; האפליקציה ו־Offline Update משתמשות באותו SHA `6bfd33c` | drift מול Yehuda-Zakesh תוקן |

## גודל release: מדידות והגדרות נכונות

החבילות שנמדדו הן `0.9.98.3+809` מ־2 בנובמבר 2026, לא dev חדש.

| יעד | גודל הורדה אם נמדד | קובצי שורש ההתקנה מה־manifest |
|---|---:|---:|
| Windows x64 | לא נמדד באותה מטריצה | **142,639,143 bytes** |
| Windows arm64 | לא נמדד באותה מטריצה | **138,383,571 bytes** |
| Linux x64 | 112,788,296 bytes (DEB) | **394,002,787 bytes** |
| Linux arm64 | 104,065,576 bytes (DEB) | **377,115,615 bytes** |
| macOS universal | 102,831,750 bytes (ZIP) | **239,739,558 bytes** |
| Android universal | 108,738,427 bytes (APK) | דורש התקנה על מכשיר/אמולטור; אין להסיק מה־APK |

`install-root` הוא סכום קובצי האפליקציה כפי שמוצהרים במניפסט השחרור, ואינו כולל dependencies שמותקנות ע"י OS מחוץ לשורש, נתוני משתמש, cache, overhead של filesystem או dexopt. ב־Android הקוד AOT הוא 103,745,880 bytes לכל שלוש הארכיטקטורות יחד; זה אינו גודל runtime של ABI יחיד.

WPE מדידה נפרדת: x64 ‏172,907,408→130,320,608 (24.63%), ARM64 ‏170,335,920→123,541,680 (27.47%) בסך ELF שנבדקו. PR #4519 מפעיל strip רק ב־package כדי לשמר SDK עם סמלים. בדיקת החוזה בשתי הארכיטקטורות ירוקה.


### Android ARM64 — attribution שנמדד בבנייה חדשה

[Flutter analyze-size run 42478124363](https://github.com/Otzaria/otzaria/actions/runs/42478124363) **עבר**, כולל פתרון dependencies, יצירת catalogs, build release עם ABI יחיד, ושמירת JSON ([artifact 13617460399](https://github.com/Otzaria/otzaria/actions/runs/42478124363/artifacts/13617460399)).

ה־APK שנבנה הוא **39.5 MB** (Flutter CLI); ניתוח הגודל מדווח `Dart AOT symbols accounted decompressed size` של **33 MB**. פירוק חבילות בולט בקירוב: `package:otzaria` ‏13 MB, `package:flutter` ‏4 MB, `package:image` ‏817 KB, `package:archive` ‏688 KB, `package:timezone` ‏451 KB, `package:flutter_quill` ‏407 KB, `package:flutter_widget_from_html_core` ‏320 KB, `package:sentry_flutter` ‏313 KB, `package:pdfrx` ‏303 KB.

זהו **release build של ענף המדידה** ל־ARM64 בלבד, לא גרסת הפצה חתומה למשתמש, ולא מספר RAM או שלוש הארכיטקטורות יחד. לפני הסרת חבילות יש למדוד גם tree-shaking, parity ו־download size מול baseline זהה.

## Linux PDFium — ראיות לסיכון חדש

- `printing/linux/CMakeLists.txt` ב־Otzaria/dart_pdf משתמש ב־`PDFIUM_VERSION=5200`, ו־`pdfium_dart 0.4.1` מוריד `chromium/8125`.
- [QA של זהות ה-release](https://github.com/Otzaria/otzaria/actions/runs/42466419382) השווה SHA של שני artifacts והוכיח שהקובץ שנארז ב־Linux x64 וב־ARM64 הוא **8125**.
- Windows כולל `pdfium.dll` ו־`pdfium_printing.dll` פרטי. Linux כולל `libpdfium.so` אחד ו־`libpdfrx_pdfium_gate.so`.
- השאלה הפתוחה היא ABI/thread-safety במקביל, **לא טענה שקריסה כבר נצפתה**. תוכנית הבדיקה ב־[Issue #4527](https://github.com/Otzaria/otzaria/issues/4527).

## ריפואים נלווים: סגירת כיסוי

| ריפו/תחום | עבודה קיימת | מצב |
|---|---|---|
| SeforimLibrary generator | [#116](https://github.com/Otzaria/SeforimLibrary/pull/116) bounded byte/spill pipeline | מוזג |
| SeforimLibrary Lucene | [#114](https://github.com/Otzaria/SeforimLibrary/pull/114) reuse/refreshed searchers | מוזג |
| SeforimLibrary ONNX/JVM | [#115](https://github.com/Otzaria/SeforimLibrary/pull/115) SessionOptions lifetime | מוזג |
| MCP | [#4](https://github.com/Otzaria/otzaria_mcp/pull/4) admission לפני spawn | מוזג |
| MCP core | [#5](https://github.com/Otzaria/otzaria_mcp/pull/5) מעבר ל־Rust core משותף | Draft פתוח |
| SeforimMagicIndexer | [#2](https://github.com/Otzaria/SeforimMagicIndexer/pull/2) bounded batches | פתוח |
| books_db | [#1](https://github.com/Otzaria/books_db/pull/1) staging + atomic catalogue | פתוח |
| nodebb-plugin-web-push | [#1](https://github.com/Otzaria/nodebb-plugin-web-push/pull/1) bounded delivery | פתוח |
| SefariaExport | [#6](https://github.com/Otzaria/SefariaExport/pull/6) verify query plan | מוזג |
| otzaria-editor-metadata | [#1](https://github.com/Otzaria/otzaria-editor-metadata/pull/1) offline styles | פתוח |
| download-tracker | [#4](https://github.com/Otzaria/otzaria-download-tracker/pull/4) bounded history | מוזג |
| tashma | [#1](https://github.com/Otzaria/tashma/pull/1) HTTP session reuse/timeout | פתוח |
| Hebrew books catalogue | [#1](https://github.com/Otzaria/hebrew_books_and_otzar_hahochma_updater/pull/1) bounded network/checkpoints | פתוח |
| magiah | [#1](https://github.com/Otzaria/magiah/pull/1) SQLite streaming | פתוח |
| Header processor | [#17](https://github.com/Otzaria/Header-processor-and-file-splitter/pull/17) undo history fast path | פתוח; DOMParser עדיין סינכרוני — שינוי נפרד דורש QA |
| Website PDF | [#257](https://github.com/Otzaria/Otzaria_Website/pull/257) benchmark | CI עבר: 6 עמודים, 3 חזרות; 1095/913/885 ms, output SHA זהה; אין השוואת pipeline A/B |
| Website Tesseract | `useLocalWordBoxes` יוצר worker/מבטל מיידית | ניסוי reusable worker + idle eviction טרם בוצע; לא להחליף ללא מדידה |
| win11-oneocr | [#1](https://github.com/Otzaria/win11-oneocr/pull/1) streaming upload/admission | 4/4 CI עברו; resident-process experiment נפרד |
| OCR/local-ocr-service | קיימים model/session reuse ו־limits | לא נמצאה הצדקה למימוש מתחרה ללא profile |

## Forks והחלטות מעבר

להשאיר לפי ה־pins הנצרכים עד בדיקת parity אחרי release רשמי:
- `flutter_inappwebview`: Windows/Linux lifecycle, suspension ו־multiwindow; upstream PRים נסגרו ללא merge;
- `window_manager`: HWND/RTL/multi-window patches; שינוי `dev` לנעיצה החדשה כבר קיים;
- `Otzaria/pdfrx`: #798 פתוח; #789 מוזג upstream ב־2.12.0, ולכן PR #4517 שומר רק את patch #798;
- [Otzaria/pdfrx #3](https://github.com/Otzaria/pdfrx/pull/3): fallback לאחר HTTP 5xx להורדת אותו PDFium דרך GitHub release-assets API, עם אימות host/asset/binary; Draft, CI מתבצע. הוא אינו pin נצרך עדיין, ולא מחליף את #798;
- `Otzaria/dart_pdf`: תיקוני פלטפורמות שאינם קיימים ב־pub.dev; PR #4522 עובר ל־HEAD שנבדק;
- `Otzaria/sentry-dart`: init/scope native מחוץ ל־UI; אין להסיר fork ללא parity;
- `Otzaria/flutter_widget_from_html`: כל ששת commits #1658–#1663 **כבר** ב־pin `570804...`; אין צורך ב־PR אינטגרציה נוסף; upstream #1658/#1660 טרם מוזגו;
- `Otzaria/tantivy`: writer merge drain וחוזה search; לא להחליף ב־crates.io עד שכל תיקוני upstream ישוחררו;
- `positioned_sliver_list 0.2.4`: batch extent/Fenwick/timeline probes כבר קיימים; אין הצדקה להסרה או החלפה ב־ListView פשוט.

## חסימות QA שאינן שקולות לכשל קוד

- GitHub release CDN החזיר 504 בהורדות `pdfium-linux-x64` ו־WPE SDK. במדידת WPE עברנו להורדת asset דרך GitHub API ואימות SHA, והבדיקה ירוקה. מעבר מקביל ב־bundle size audit נשלח ל־CI חוזר.
- Windows/macOS native asset hooks קיבלו checksum שגוי ל־`sqlite3` מהורדה חיצונית; הקוד לא שינה את sqlite3.
- Android Gradle wrapper נכשל בהורדת הפצה חיצונית גם בבדיקות fork notifications; Windows unit tests עברו.
- חסימת `flutter build --analyze-size` של Android בגלל PDFium 504 הייתה היסטורית: ריצה 42478124363 השלימה בנייה ושמרה attribution, כמפורט לעיל. יש לאמת בנפרד בנייה עם ה־workflow המתוקן ללא שתילת cache.
- מדידת `flutter test` בריפו הראשי עלולה להיות אדומה בגלל network; יש להפריד failure בגנרטור/הורדה מ־assertion שהגיע למסלול הקוד ששונה.

## סדר סגירה

1. להעביר CI מחדש לאחר תיקוני format/download, ולתעד לכל PR את ה־HEAD שנבדק. Draft נשאר עד סקירה עצמאית.
2. לקשור תיקוני fork → PR צרכן רק אחרי passing native/test/lockfile, כולל גרסה מוחתמת ושמירת שינויי המתחזק.
3. לבצע mixed-PDFium integration/stress לפני שינוי loader/SONAME; לא לשלב עם #4522.
4. לחזור על Android analyze-size ללא שתילת cache; מדידת ARM64 היסטורית כבר הושלמה. ניסוי Tesseract worker reuse דורש parity ו־memory plateau.
5. למזג לפי סדר נקודתי ובאישור המתחזק; לא לפתוח שינויים כפולים בתחומי #4307, #4416, #4475, #4301 או #4315.

## QA follow-up — 8.11.2026, מעקב לקראת review

### תיקון רגרסיית Markdown
- רענון #4515 ל־dev הציג כשל חדש: `pubspec.lock` הכיל key בשם `flutter_markdown_plus` אך metadata וגרסה של `flutter_markdown`. הדבר הוכח בלוגי `flutter pub get --enforce-lockfile` של שישה workflows, למרות Lockfile Guard ירוק. **תיקון מדויק ב־[#4515, commit 38c8ac45](https://github.com/Otzaria/otzaria/commit/38c8ac450fcaa817c338d0ebc01abee4cb64f770)** מחזיר name/1.0.12/SHA-256 תקינים בלי שינוי יתר ה־pins; CI של הראש המתוקן בתור.
- [PR #4565](https://github.com/Otzaria/otzaria/pull/4565): check חדש ללא תלות Flutter שמוודא לכל source: hosted ש־description.name זהה למפתח ויש version; תשע בדיקות, כולל השגיאה ההיסטורית. נבדקו סטטית 243 רשומות hosted נצרכות, כולן התאימו. ה־PR Ready לביקורת; QA עצמאי ב־Actions עדיין נדרש.

### רענון בסיסי PR
כל שבעת PRי התלויות/אריזה האפליקטיביים הועברו ל־base `dev@e9d23b1` בעזרת Git commits עם שני parents ועדכון refs לפי expected SHA, ללא מיזוג ב־dev. כל diff נבדק ונשאר ממוקד:
- #4482 `8859d812`
- #4515 `38c8ac45` (כולל תיקון lock לאחר refresh)
- #4516 `01d1beca`
- #4517 `ef1bdff4`
- #4519 `e849978e`
- #4521 `8ccd0808`
- #4522 `b89aa0dd`

### PRים שהועברו מ־Draft ל־Ready for review
- #4416 (מדיניות אינדוקס): Windows/Linux builds, Analyze, Windows tests וכל shards עברו; macOS integration עדיין חסום ב־ONNX 503.
- #4307 (קורא מקטעים): **ניסוי שאינו merge-approved** — שיפור פתיחת ספר גדול לצד החמרה בקפיצות/FrameTiming; דורש החלטת reviewer אם לפצל או לתקן.
- Otzaria/pdfrx #3: fallback לאחר 5xx, Linux/Windows unit/format עברו; builds Android/Windows/Linux/Web עברו; עבודות Apple עדיין בתור בעת עדכון זה.
- [#4563](https://github.com/Otzaria/otzaria/pull/4563): fallback דרך GitHub CLI להורדת ORT 1.28.0 במק עם SHA-256, כולל בדיקת חוזה offline ו־macOS smoke — נפתח והועבר ל־Ready לביקורת **לפני אישור CI**, כמסומן ב־PR.
- [#4565](https://github.com/Otzaria/otzaria/pull/4565): metadata guard חדש, Ready לביקורת **לפני אישור CI**, כמסומן ב־PR.

**כל ה־PRים הללו אינם מאושרים למיזוג עד לשערי QA והסקירה הרלוונטיים.** לא נפתחו PRים כפולים לעבודות שכבר מוזגו ב־dev.
