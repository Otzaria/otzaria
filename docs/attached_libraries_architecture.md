# מסדים מצורפים — הערות ארכיטקטורה למפתחים

תיעוד המשתמש ובוני המסדים: [personal_databases.md](personal_databases.md).
כאן: איך הפיצ'ר בנוי ואיפה נוגעים כשמרחיבים אותו.

## זהות ומפתחות

| שכבה | ערכים |
|---|---|
| `BookSource` | `official` / `user` / `attached(slug)` |
| מפתח wire | `o` / `u` / `d:<slug>` |
| `BookCompositeKey` | סיומת מקור על מפתח הספר |
| מפתח אינדקס החיפוש | `id:` / `uid:` / `ext:` / `db:<slug>:<id>` |
| הערות אישיות | `"<title>|db:<slug>"` |
| `bookUid` לתוספים | `db:<slug>:<id>`, `source: "attached"` |

- slug: `schema_meta.library_id`, אחרת שם הקובץ אחרי ניקוי; אותיות (כולל עברית), ספרות,
  `._-`, עד 64 תווים. התנגשות slug ← הקובץ השני נדחה.
- ספרים מצורפים נוספים **בסוף** סדר הקטלוג של האינדקס, כך שצירוף מסד לא מזיז מפתחות של
  ספרים אחרים ולא גורם לאינדוקס מחדש שלהם. החלפת קובץ באותו slug ← אינדוקס מחדש רק שלו.

## מבנה הקוד

```
lib/attached_libraries/
├── bloc/          # מצב המסדים בהגדרות (צירוף, הסרה, עדיפות, מיקום, הסתרה)
├── models/
└── repository/
    ├── registry            # פתיחה עצלה ומוקשחת, סגירה בזמן סרק, closeAll
    ├── probe (isolate)     # בדיקת קובץ לפני צירוף: slug, WAL/journal, טבלאות
    ├── store               # שמירת רשימת המסדים והגדרותיהם
    └── external_link_core / external_link_repository
lib/migration/database/
├── db_capabilities.dart    # מקור אמת יחיד לקיום טבלאות/עמודות
└── untrusted_database.dart # openUntrustedReadOnlyDatabase, ReadOnlyDbTarget
```

- **`DbCapabilities`** — רשימת היתר של טבלאות, getter יכולת לכל טבלה/זוג. נשמר במטמון
  לפי נתיב + `PRAGMA schema_version`. שם מוכר שהוא VIEW/וירטואלי נחשב חסר.
- **`openUntrustedReadOnlyDatabase`** — read-only, `query_only`, `trusted_schema=OFF`,
  defensive, ללא הרחבות, mmap כבוי. `ReadOnlyDbTarget` מעביר את אותה פתיחה ל-isolates.
- **קטלוג המסדים** נקרא ב-isolate עם timeout לכל מסד; מסד שלא עונה מסומן לא זמין
  והעץ ממשיך.
- **איתור מקורות** במסדים מצורפים רץ ב-isolate עובד ברקע.
- **`external_link`** — אינדקס צד של קישורים הפוכים ב-`cache.db`, נבנה מחדש כשהקובץ או
  גרסת הספרייה הרשמית משתנים. מגבלה: 5,000,000 שורות למסד (נבנה בזרם, במנות), חיתוך כותרת/הפניה ב-512.
- **גרסאות של ספר מצורף** — לפי קדימות: `user_attached_book_version` ב-user_books.db
  (קובץ גרסאות של המשתמש, slug+כותרת), ו-`book_version_link` שבמסד (נקרא עם הקטלוג
  ב-`readAttachedCatalogSync`), ובמיזוג — ספר זהה לרשמי באותה קטגוריה (מפת כותרות של
  הקטגוריה ב-`_addAttachedBooks`, בלי שאילתות). כולם נפתרים ב-`_resolveAttachedVersions` דרך
  `resolveCatalogPrimary`, וספר הגרסה יורד מהעץ ל-`offTreeBooks`.
- **קישורי משתמש (`user_link`)** — צד במסד מצורף נשמר ב-`sourceDb`/`targetDb` (slug)
  וכותרת, בלי קטגוריה. הייבוא פותח את המסדים ב-isolate דרך `AttachedLinkBooks`.

## עלייה

`_runDeferredAttachedLibraries` ב-`main.dart` רץ אחרי חשיפת החלון (שער reveal עם
timeout), פעם אחת לתהליך, ונכשל ללא הפלה
(`_logNonFatalInitializationError`). שום דבר מהפיצ'ר לא נוסף למסלול לפני הפריים הראשון.

## כלל היתומים באינדקס

מפתחות `db:` נמחקים מהאינדקס **רק** כש:
1. המסד הוסר מהרשימה, או
2. הספר נעלם ממסד שנטען, גלוי ונגיש.

מסד לא זמין או מוסתר לעולם לא גורם למחיקה — אחרת ניתוק כונן היה מוחק את האינדקס,
הסימניות וההערות.

## הוספת טבלה חדשה לתמיכה

1. **רשימת היתר ב-`DbCapabilities`** — הוסיפו את שם הטבלה (וגם את בת הזוג אם הן
   חייבות לבוא יחד).
2. **getter יכולת** — `hasX` שבודק קיום (ועמודות נדרשות); לזוג — שתי הטבלאות.
3. **שער בנקודת השאילתה** — כל שאילתה על הטבלה נשמרת ב-getter, והחזרה ריקה כשהיכולת
   חסרה. אין להניח קיום טבלה במסד מצורף.
4. עדכנו את `tool/validate_personal_db.dart` ואת קטלוג הטבלאות ב-
   [personal_databases.md](personal_databases.md).

טבלה שאינה ברשימת ההיתר לעולם לא נקראת — זה חלק ממודל האבטחה, לא מגבלה זמנית.

## אבטחה — עקרונות שאסור לשבור

- המסד לעולם לא נכתב; עותק מנוהל (מובייל) הוא היחיד שה-journal שלו מנורמל.
- שום דבר מהמסד לא מותקן או מורץ (תוספים, סקריפטים, גופנים).
- קישורים בטקסט הספר — ניווט בלבד.
- `book.filePath` — יחסי לתיקיית המסד בלבד; נדחים נתיב מוחלט, אות כונן, UNC, `..`,
  רכיב של נקודות/רווחים בלבד, `:`, NUL.

## עדכונים (שלב U1: מודל, אימות ורשת)

- **נעיצה (TOFU):** `AttachedLibraryProbe` קורא `update_manifest_url`/`update_public_key` עם `library_id` ל-`AttachedLibraryUpdateSource`. `_applyProbe` נועץ אותו ב-`AttachedLibrary.updateSource` בצירוף. בבדיקה חוזרת של אותו slug הנעוץ נשמר, וכל סטייה (גם הסרה) מסמנת `updateSourceMismatch` — בלי רשת. slug אחר הוא מסד אחר ונעוץ מחדש. `updateSourceProbed` גורם למסד שצורף לפני התכונה להיבדק שוב פעם אחת.
- **מניפסט:** `models/attached_update_manifest.dart` — פענוח קפדני אחרי אימות החתימה בלבד. `checkApplicable` דוחה `library_id` שונה ו-`db_version` שאינו גדול מהמותקן (או מותקן שאינו מספר שלם).
- **חתימה:** `repository/update/attached_update_signature.dart` — ed25519 דרך `pinenacl` (Dart טהור, בלי תלויות). נבדקת תמיד מול המפתח הנעוץ, לעולם לא מול מפתח מקובץ שהורד.
- **רשת:** `AttachedUpdateHostPolicy` (https, שם מארח ולא IP, בלי שמות מקומיים, כל כתובות ה-DNS ציבוריות) ו-`AttachedUpdateFetcher`: `connectionFactory` מתחבר לכתובות שהמדיניות אישרה ומקים TLS מול שם המארח (אין תרגום DNS שני), הפניות מטופלות ידנית ונבדקות, `findProxy` = `HttpClient.findProxyFromEnvironment` (כמו `http.Client` של המעדכן הרשמי; דרך פרוקסי נדחית רק כתובת שנפתרת מקומית לטווח פרטי), timeouts לחיבור ולכל נתח. תעודות נטפרי מגיעות מה-SecurityContext הגלובלי שנטען בעלייה. dart:io בלבד — אפשר להריץ ב-isolate.
- **הורדה ובנייה:** `downloadParts` משרשר את החלקים לקובץ אחד עם sha256 לכל חלק, ממשיך ב-Range אחרי אימות מה שכבר בדיסק, וחלק פגום נחתך. `AttachedUpdateArtifactBuilder` פורס zstd בזרם דרך `ZstdStreamExtractor` (אותו FFI של עדכון הספרייה) ובודק גודל ו-sha256.
- **delta:** מפוענח בלבד. ה-`PatchApplier` של seforim_library_updater מקבל נתיב מסד, אבל קשור לרשימת הטבלאות ולגיבוב הלוגי של הספרייה הרשמית ולקובצי patch שמיוצרים ב-SeforimLibrary — אין למפרסם אישי דרך לייצר אותם. נדחה ל-v2.
- **לבדיקות:** `AttachedUpdateHostPolicy.allowLoopbackForTesting` מתיר http ל-127.0.0.1 בפורטים שנמסרו בלבד; מדיניות הייצור אינה משתנה.

## עדכונים (שלב U2: בדיקה, הורדה, התקנה)

- **שירות:** `repository/update/attached_library_update_service.dart` — מצב לכל מסד (לפי נתיב) ב-`ValueListenable`, שה-BLoC מעביר ל-`AttachedLibrariesState.updates`. מסד בלי מקור נעוץ או עם `updateSourceMismatch` לא נבדק כלל.
- **תזמון:** `_runDeferredAttachedLibraryUpdates()` ב-`main.dart` רץ אחרי סריקת המסדים, בחלון הראשי בלבד. אותם שערים כמו בדיקת הספרייה הרשמית: לא במצב לא מקוון, `keySoftwareAndBookUpdatesEnabled`, `keyAutoSync`, ותדירות `keyUpdateCheckFrequency` מול `keyLastAttachedLibraryUpdateCheck` (נרשם רק כשכל המקורות נענו). בדיקה ידנית מכבדת את מצב לא מקוון ואת כיבוי העדכונים.
- **הצעה שמורה:** המניפסט והחתימה כפי שהורדו נשמרים ב-`keyAttachedLibraryPendingUpdates` (לא מגובה, חסום לתוספים), ובטעינה מאומתים שוב מול המפתח הנעוץ והגרסה המותקנת. גם לפני ההתקנה החתימה נבדקת שוב.
- **הורדה:** `AttachedUpdateDownloader` מריץ את ההורדה, ה-sha256 של כל חלק, zstd וה-sha256 הסופי ב-isolate אחד. `SecurityContext.defaultContext` הוא פר-isolate, לכן בתי התעודות של נטפרי נקראים ב-UI isolate (`loadNetfreeCaBytes`) ונטענים ב-isolate. ביטול עובר בפורט בקרה. קובץ ההורדה הדחוס נשמר ב-`<תיקיית העותקים>/.updates` (חידוש אחרי כשל רשת; נמחק בביטול); הקובץ המורכב נכתב ליד קובץ היעד (`.<שם>.update-new`) כדי שההחלפה תהיה rename באותו כונן. ארטיפקט לא דחוס מורד ישר ליד היעד.
- **לפני ההורדה:** בדיקת כתיבה בתיקיית היעד (תיקייה לקריאה בלבד / כונן מנותק נכשלים כאן) ובדיקת מקום פנוי לכל כונן (`getDiskSpaceInfo`), עם מרווח 32MB.
- **התקנה (`AttachedLibrariesRepository.installUpdate`, בתור הסדרתי של המאגר):** `registry.close(slug)` משחרר את הנעילות, `AttachedUpdateFileSwap.swapIn` מעביר את הקובץ הישן וקבצי הצד שלו (`-wal`/`-shm`/`-journal`) ל-`<file>.bak-update` ומכניס את החדש. הקובץ החדש נבדק פעמיים — לפני ההחלפה ואחריה — ב-`AttachedLibraryProbe`: אותו `library_id`, אותו `update_public_key` ו-`db_version` שווה בדיוק לגרסת המניפסט. כשל ⇒ שחזור הגיבוי. הגיבוי נמחק רק אחרי הצלחה, ואז `_commit` עם טביעת האצבע החדשה מפעיל את מסלול הרענון הקיים (עץ, אינדוקס של המקור בלבד, אינדקס `external_link`, מטמונים).
- **קריסה באמצע:** `recoverInterruptedUpdates()` רץ ב-`_runDeferredAttachedLibraries` לפני `rescan`: `.bak-update` קיים ⇒ הוא מוחזר למקום (גם אם הקובץ החדש כבר במקומו — שמרני: העדכון יוצע שוב), וקובץ `.update-new` יתום נמחק. קבצים שמתחילים בנקודה ו-`.bak-update` אינם נסרקים כמסדים.
- **נעילות ב-Windows:** שינוי שם שנכשל ב-ERROR_SHARING_VIOLATION מנוסה שוב כמה פעמים (isolate של אינדוקס או של הקישורים שמסיים קריאה), ואז "קובץ המסד תפוס".
- **ממשק:** `view/attached_library_update_view.dart` — צ'יפ מקור (אין / חתום · דומיין / השתנה), שורת עדכון (בדיקה, "עדכון זמין", התקדמות וביטול, שגיאות), דיאלוג אישור (דומיין, גרסה, גודל, הערות כטקסט פשוט) ודיאלוג סיכום אחרי צירוף מסד עם מקור.

## עדכונים (שלב U4: דלתא)

- **הפורמט:** ערך ב-`delta[]` של המניפסט עם `compression: "zstd-patch"` — פלט `zstd --patch-from=<old.db> <new.db>`, מפוצל לחלקים כמו הקובץ המלא. `size` ו-`sha256` הם של ה-`.db` המתקבל, זהים לאלה של `full`, ולכן מסלול הדלתא נבדק בדיוק באותו שער. `zstd-patch` תקף רק בתוך `delta`; ב-`full` הוא נדחה.
- **תאימות קדימה:** `AttachedUpdateManifest.parse` מדלג על ערך דלתא שאינו נקרא (פורמט תיקון עתידי, שדה חסר) במקום להפיל את המניפסט. `full` נשאר קפדני, ולכן אי אפשר להבריח דרך זה ארטיפקט שלא נחתם.
- **הבחירה (`AttachedUpdateArtifactPlanner`):** תיקון נבחר רק אם התהליך 64 סיביות, הקובץ המותקן קיים וקטן מ-2GiB (תקרת חלון ה-zstd), `from_db_version` שווה לגרסה המותקנת, וסך ההורדה קטן מזה של הקובץ המלא. אם נותרו כמה מועמדות, מחושב SHA-256 של הבסיס פעם אחת ב-isolate דרך המימוש המהיר (BCrypt ב-Windows ו-CommonCrypto ב-macOS), ונבחרת הקטנה ביותר שה-`from_sha256` שלה תואם. התוצאה נשמרת לפי נתיב, גודל ומועד שינוי, כדי שההתקנה לא תקרא שוב בסיס שלא השתנה. בלי התאמה נבחר הקובץ המלא. כל ספק ⇒ הקובץ המלא, בלי שגיאה למשתמש.
- **דלתא יחידה בלי קריאת הבסיס:** כשנותרת מועמדת אחת אחרי סינון הגרסה, הדחיסה והגודל, הבחירה אינה מחשבת SHA-256 של הקובץ המותקן. `from_sha256` משמש רק להבחנה בין כמה מועמדות. תיקון שהוחל על בסיס שאינו תואם נכשל באימות הפלט מול ה-sha256 של המניפסט החתום (או בפענוח), וההתקנה חוזרת אז לקובץ המלא (ראו "נפילה חזרה"). הדיאלוג מציג את גודל ההורדה של הארטיפקט שנבחר.
- **ההחלה (`AttachedUpdateDeltaApplier`, ב-isolate ההורדה):** `ZSTD_DCtx_refPrefix` על הקובץ המותקן כשהוא ממופה לזיכרון לקריאה בלבד (`MappedFile`, `lib/utils/file/mapped_file.dart`) ו-`ZSTD_d_windowLogMax = 31`; הפלט נכתב לאותו `.<שם>.update-new` של המסלול המלא, עם אותה תקרת גודל ואותה בדיקת sha256 מול המניפסט החתום. קריאת המסד ל-heap הייתה מפילה מכונות של 8GB, והמיפוי משוחרר תמיד ב-`finally` — מיפוי שנשאר פתוח נועל את הקובץ ב-Windows ומונע את ההחלפה.
- **נפילה חזרה:** כשל בהורדת התיקון או בהחלתו מוחק את ההורדה החלקית ומוריד את הקובץ המלא באותו ניסיון התקנה (כולל HTTP 404 של תיקון חסר; ניתוק רשת, דחיית מדיניות וביטול המשתמש אינם מפעילים נפילה כזאת). הורדת תיקון נשמרת בשם נפרד לכל גרסת מקור, כדי שחידוש חלקי לא ייקרא כקלט של תיקון אחר.
- **המפרסם:** `pack --delta-from <old.db>` (עד 4) ו-`verify`, שמחיל כל תיקון עם אותו applier של התוכנה. ראו `docs/personal_databases.md`.

## מסדים רשמיים

- **הקטלוג:** `models/official_attached_library.dart` — `OfficialAttachedLibraries.builtIn`: `libraryId`, שם, `manifestUrl` ו-`publicKey` קבועים בקוד. רשומה עם מפתח לא תקין (`source == null`) אינה פעילה: אין הצעה ואין עדכון.
- **מודל האמון:** `AttachedLibrary.official` (`AttachedOfficialInstall`: מזהה, גרסה ו-sha256 שהותקנו) נקבע רק ב-`AttachedLibrariesRepository.installOfficial` ובעדכון שעבר דרך `installUpdate`, אף פעם לא מתוכן הקובץ. בעותק רשמי `_applyProbe` לוקח את `updateSource` ואת שם התצוגה מהקטלוג, ולא מסמן `updateSourceMismatch`. `AttachedLibraryUpdateService.sourceOf` מחזיר את מקור הקטלוג גם אם הרשומה השמורה שונתה. קובץ שה-slug שלו שונה מהמזהה מאבד את הסימון. `forgetUpdatePins` (שחזור גיבוי) מוחק אותו.
- **קובץ ידני עם אותו `library_id`:** מצורף כמסד אישי רגיל (TOFU, עדכון רק באישור). `_slugTaken` אינו דוחה מזהה שנמצא בקטלוג; `_commit` משאיר עותק אחד פעיל לכל slug לפי `_slugRank`: רשמי מאומת (4), רשמי שאינו מאומת (2), ובכל אחד מהם +1 לעותק מנוהל (`copy`); בתיקו — הראשון בסדר. מסד שאינו רשמי מדורג 0, ולכן בין מסדים רגילים נשאר "הראשון בסדר". העותק הרשמי נשמר ב-`<תיקיית העותקים>/official/<id>.db`, ולכן אינו מתנגש בעותק ידני (`<slug>.db`).
- **זיהוי עותק ידני (`adoptManualCopies`):** רץ ב-`_runDeferredAttachedLibraryUpdates` (אחרי reveal, פעם לתהליך), ואחרי ייבוא, הוספת תיקייה וסריקה מהכרטיס. דרוש: לא במצב לא מקוון ועדכונים פעילים (בלי שער התדירות והסינכרון האוטומטי — זו פנייה אחת לקובץ). המועמדים: slug שיש לו רשומה פעילה בקטלוג, סטטוס ok או duplicateSlug, ואין עותק מאומת אחר. כתובת המניפסט באה מ-`releaseManifestUrlTemplate` עם `db_version` של הקובץ (`https://github.com/Otzaria/zmanenu-library/releases/download/v<db_version>/manifest.json`, והחתימה ב-`.sig`), כי "latest" מכסה רק את הגרסה האחרונה. ההתאמה נבדקת ב-`adoptIfSignedMatch` (חתימה במפתח שבקוד, אותה גרסה, sha256 ב-isolate), ו-`adoptOfficial` מסמן את הרשומה במקומה — גם במצב link, בלי לכתוב לקובץ. `adoptOfficial` נמנע רק כשיש עותק **מאומת** אחר.
- **הגבלת ניסיונות:** `keyOfficialAdoptionAttempts` (לא מגובה, חסום לתוספים) שומר לכל נתיב את טביעת האצבע (גודל, mtime, גרסה) ומועד הניסיון. אותו קובץ נבדק שוב רק אחרי `adoptionRetryInterval` (7 ימים); קובץ שהשתנה נבדק מיד. 404 ואי-התאמה נרשמים בשקט. ניתוק רשת אינו נרשם, וחוזר בתהליך הבא. הבחירה: גיבוב של קובץ גדול ופנייה לרשת אינם כדאיים בכל עלייה, ושבוע מכסה רילייס שפורסם אחרי שהקובץ צורף.
- **עדכון של עותק מקושר שאומץ:** `install` אינו מחליף קובץ במצב link של מסד רשמי (`installUpdate` היה כותב לקובץ המשתמש). ההורדה (גם דלתא, שקוראת את קובץ המשתמש כבסיס בלבד) נבנית ב-`officialPathFor`, ו-`installOfficial(replacing:)` מוסיף עותק מנוהל עם העדיפות, המיקום וההסתרה של הרשומה המקושרת ומסיר ממנה את הסימון. הרשומה המקושרת נשארת ומסומנת כפולה; ה-slug נשלח ב-`changes` לאינדוקס מחדש.
- **הצעה והורדה:** `checkOfficialOffers` (רק כשכרטיס ההגדרות נפתח, לא בעלייה) מביא את המניפסט החתום של כל רשומה פעילה שלא הותקנה ולא נדחתה. `installOfficial` מוריד את `full` באותו `AttachedUpdateDownloader`, בודק את הקובץ (`acceptsOfficial`: אותו slug ובדיוק גרסת המניפסט) ומצרף אותו במצב copy. המצב נשמר באותו `statuses` במפתח `officialKey(id)`. סירוב או הסרה נשמרים ב-`keyDeclinedOfficialLibraries`.
- **עדכון אוטומטי:** `runScheduledCheck` (בתוך `_runDeferredAttachedLibraryUpdates`, אחרי reveal) מתקין מיד עדכון שנמצא לעותק רשמי. לפני התכנון `install` בודק שגרסת הקובץ וה-sha256 שלו (`planner.installedSha256`, אותו מטמון של בחירת הדלתא) תואמים ל-`official`. אי-התאמה ⇒ `AttachedUpdateError.integrityMismatch`, בלי הורדה. `install(forceFull: true)` מוריד את `full` בלבד. אחרי התקנה נרשם ה-sha256 של הארטיפקט שאומת בפועל.

- **חבילה לא-מקוונת (`importOfflinePackage`, `official_offline_package.dart`):** `<offlineName>-offline.tar.zst`, כמו ארכיון הספרייה. בשורש ה-tar: `<offlineName>.db` (המסד המלא, לא דחוס בתוך ה-tar), `manifest.json` ו-`manifest.json.sig` (הבתים החתומים, כמו ברילייס); zstd ‏-19, בלי `--long`. מתחת לסף — קובץ אחד; מעליו — `.part-000` ואילך (עד 1992294400 בתים לחלק) ו-`<name>.manifest.json` במוסכמה של `tool/release/split_release_asset.sh`. המשתמש בוחר את הקובץ השלם, את `part-000` או את מניפסט החלקים. הקבצים נאספים ב-`scanNamedArchive` (אותם כללים של `scanLibraryPackages`: חלקים רציפים, גודל ו-sha256 לכל חלק ולשלם כשיש מניפסט, אחרת checksum של ה-frame), ונפרסים ב-`extractLibraryPackage(anyRoot: true)` ב-isolate, בזרם אחד, אל `<תיקיית העותקים>/official/.offline-<זמן>` (אותו כונן כמו היעד), שנמחקת בסוף; תיקיות `.offline-*` שנשארו מקריסה נמחקות בייבוא הבא. ייבוא, `installOfficial` ו-`install` רצים בתור אחד, כי הם עשויים לכתוב לאותו קובץ staged. חלק חסר או פגום ⇒ `notPackage`. החתימה נבדקת מול המפתח של כל רשומה בקטלוג שהמסד שלה בחבילה, ורק אחרי האימות נקרא `library_id`. אחר כך: גודל ו-sha256 של המסד מול `full`, `acceptsOfficial` על הקובץ, וגרסה: נמוכה מהמותקנת ⇒ `olderVersion`; זהה ומאומתת עם אותו sha256 ⇒ `alreadyInstalled`. ההתקנה: עותק מנוהל קיים ⇒ `installUpdate` (החלפה עם גיבוי); עותק מקושר ⇒ `installOfficial(replacing:)`; אחרת ⇒ `installOfficial`. המסד שנפרס עובר ב-rename ל-`.<שם>.update-new` ליד היעד.
- **מיקום האיסוף (לסוכן מסייע ההורדה):** `<data root>/מסדים אישיים/להתקנה/`, ובה `zmanenu-offline.tar.zst` שלם, או `zmanenu-offline.tar.zst.part-000`, `part-001`… עם `zmanenu-offline.tar.zst.manifest.json` (אותם שמות כמו בפרסום). `<data root>` הוא `AppPaths.getDataRootPath()`:
  - Windows: `%APPDATA%\otzaria` (בהתקנה ניידת: `<תיקיית ה-exe>\otzaria_data`).
  - macOS: `~/Library/Application Support/otzaria`.
  - Linux: `~/.local/share/otzaria`.
  - Android/iOS: תיקיית המסמכים של האפליקציה (המסייע אינו כותב לשם).

  `importDroppedPackages` רץ ב-`_runDeferredAttachedLibraryUpdates`, פעם לתהליך אחרי reveal, גם במצב לא מקוון. חבילה שהותקנה, שכבר מותקנת או ישנה מהמותקנת נמחקת (רק הקבצים ששימשו לייבוא ולא השתנו); חבילה שנדחתה נשארת, ומוצגת הודעת `UiSnack` פעם אחת: טביעתה (שם, גודל ומועד של כל קובץ) נשמרת ב-`keyRejectedOfficialPackages`, והיא אינה נפרסת שוב עד שקובציה משתנים. המסייע צריך לכתוב כל קובץ לשם זמני (למשל `<שם>.tmp`) ולשנות שם בסוף, ולהניח את מניפסט החלקים אחרון; כך חבילה חלקית אינה נקראת כשלמה (בלי מניפסט נבדק רק ה-checksum של zstd). אפשר גם להניח את החבילה ליד קובצי הספרייה בתיקיית הפלט של המסייע: בייבוא הספרייה מתיקייה בהגדרת הספרייה, `zmanenu-offline.tar.zst` (שלם או בחלקים) שבאותה תיקייה מותקן אחרי הספרייה ואינו נמחק.
- **מסך הגדרת הספרייה:** תיבת "הורד גם את <שם>" (כבויה כברירת מחדל) ליד "הורדת הספרייה". אחרי `EmptyLibraryDirectorySelected` היא מפעילה את `downloadOfficial` ברקע: אותה הצעה חתומה ו-`installOfficial`.

## מפרש ממסד מצורף כברירת מחדל לספר במסד אחר

- `external_default_commentator` ברשימת ההיתר, עם `DbCapabilities.hasExternalDefaultCommentators` (כל חמש העמודות) ושאילתת `selectExternalDefaultCommentators` ב-`LinkDao`.
- `DefaultCommentators.fetchDefaults` מוסיף אחרי ברירות המחדל של הספר את `_externalDefaults`: קודם `ExternalLinkRepository.commentatorSources` של הספר (רשימת המפרשים מקישורים חוצי-מסדים, במטמון), ונפתחים רק מסדים גלויים ש-`BookSource.attached(slug)` שלהם מופיע בה, לפי סדר העדיפות. שורה נכללת רק כש-`commentatorSources[title]` הוא אותו מסד — כלומר הספר מקושר ליעד ומוצג ברשימה. `targetSource` מסנן לפי מקור הספר (`official`, slug, או NULL).
- מפרשים מקבלים position רציף אחרי המקסימום של הספר, ולכן צורת הדף ממקמת אותם אחרי מפרשי הספר עצמו.

### הוספת מסד רשמי חדש

1. מוסיפים רשומה ל-`OfficialAttachedLibraries.builtIn`: `libraryId` זהה ל-`schema_meta.library_id` של המסד, שם תצוגה, כתובת מניפסט קבועה (https), מפתח ציבורי ed25519 ב-base64, `releaseManifestUrlTemplate` (עם `{version}`) לזיהוי עותקים ידניים, ו-`offlineName` לחבילה הלא-מקוונת.
2. המפתח הפרטי נשמר אצל המפרסם בלבד. החלפת מפתח מחייבת גרסת תוכנה חדשה.
3. המסד מתפרסם בכלי המפרסם הרגיל (`pack`/`sign`); ה-`library_id` במניפסט חייב להיות זהה לזה שבקטלוג.
4. מוסיפים בדיקה ל-`test/attached_libraries/update/official_attached_library_test.dart` אם הרשומה צריכה התנהגות מיוחדת.
