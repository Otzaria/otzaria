# תכנון מערכת קישורים נוצרים מקומית בתוך ספרים

## מטרת המסמך

מסמך זה מתאר איך לממש מערכת קישורים שנוצרים מקומית בתוך טקסט הספרים באוצריא, כך שמפתח ג'וניור יוכל לעבוד לפי שלבים ברורים בלי לנחש את הארכיטקטורה.

המערכת צריכה לזהות מראי מקומות בתוך שורות הספר, למשל `בראשית א א` או `ברכות ב.`, לצבוע את המילים הרלוונטיות בכחול, ולאפשר לחיצה לפתיחת מקור היעד בטאב חדש.

שני כללים בסיסיים שאסור לשבור:

1. המשתמשים לא מורידים קובץ קישורים מוכן מראש.
2. הקישורים שנוצרים מקומית לא נשמרים ב-DB הראשי ולא מרחיבים את סכמת ה-DB עבורם.

הקישורים נוצרים מקומית אצל המשתמש ב-isolate, נשלחים חזרה לטקסט לצביעה ולהפיכה ללינק, ונשמרים בקבצי cache מקומיים בלבד. לאחר שקישור נוצר ונשמר הוא לא "דינמי" יותר מבחינת המערכת; הוא נתון סטטי מקומי שנטען מה-cache בפעמים הבאות.

## מסקנות מהקוד והקומיטים הקיימים

### מה כבר קיים בריפו

יש כבר תשתית להצגת קישורי inline כאשר אובייקט `Link` כולל `start` ו-`end`:

- `lib/models/links.dart` כולל `start` ו-`end`.
- `lib/utils/text_with_inline_links.dart` יודע להזריק תגי `<a>` לפי מיקום תווים.
- `lib/utils/html_link_handler.dart` יודע לפתוח קישור מסוג `otzaria://inline-link`.
- `lib/text_book/view/combined_view/combined_book_screen.dart` מוסיף קישורים כאלה לפני רינדור הטקסט.

אבל התשתית הזו מניחה שהקישורים כבר קיימים ב-`state.links`. היא לא יוצרת אותם.

בנוסף, בגרסה הנוכחית `DatabaseLibraryProvider` אינו קורא `start/end` בשאילתות הקישורים מה-DB. זה לא הבעיה המרכזית כאן, כי הדרישה החדשה היא לא לשמור קישורים שנוצרים מקומית ב-DB, אבל זה מסביר למה הקומיטים הישנים לא הפכו למערכת עובדת בפועל.

### הקומיטים הישנים שנכנסו

`42de1ec101fcf4ddf1cc5bed3c581a0221ad212d` הוסיף תמיכה בלחיצה על קישורי HTML בתוך הטקסט.

`7fa6da63d4de205b78d0013747f9fff4163fee2b` הוסיף תמיכה בקישורי inline לפי `start/end`.

`0829f43517bd2520e933380f16d7efd97094f6af` הסתיר קישורי inline מחלונית הקישורים, כדי שיופיעו רק בתוך הטקסט.

המסקנה: צריך לשמר את רעיון התצוגה והלחיצה, אבל לא להסתמך על DB או על קובץ קישורים חיצוני.

### ארבעת הקומיטים המסודרים מה-fork

הקומיטים `9b2848068`, `a18758420`, `f03a4f49`, `d75b8bae` מכילים רעיונות טובים ללוגיקת זיהוי:

- זיהוי הפניות גמרא לפי מסכת ודף.
- תמיכה באותיות שימוש לפני שם מסכת: `ב`, `ד`, `מ`, `ל`, `כ`, `ש`.
- המרת מספרים עבריים למספרים.
- בדיקת גבולות לפי מספר הדפים במסכת.
- זיהוי `(שם)` כהפניה יחסית למראה מקום קודם.
- פילטר שמונע false positives של `(שם)` כאשר יש סוגריים אחרים בין ההפניה הקודמת לבין `שם`.

אבל אסור לאמץ את המימוש כפי שהוא, כי הוא:

- מכניס קישורים ל-DB.
- מוסיף עמודות `start/end` ל-DB.
- מייצא ומייבא JSON.
- מערבב זיהוי עם HTML.
- משתמש בצבע קשיח `#0000FF`.
- מאתר מיקום עם `text.indexOf`, מה שעלול לקשר את המופע הלא נכון כאשר אותה הפניה מופיעה פעמיים בשורה.

### הקומיט המבולגן

`61d396b71ead6934ba02a280e5339ca5593800f1` לא מתאים ל-cherry-pick. יש בו יותר מדי קבצים לא קשורים, מערכת פלאגינים, סקריפטים כפולים ושינויים ניסיוניים.

כן כדאי להציל ממנו רעיונות בלבד:

- כללי תנ"ך בסיסיים.
- כללי `שם` לתנ"ך.
- רשימות ספרים, ראשי תיבות, והמרת מספרים.
- הבנה ש-regex כבד צריך לרוץ ברקע או ב-cache, לא בזמן כל build של שורת טקסט.

## שמות

לא לקרוא למודל `DynamicLink`. השם `dynamic` מטעה, כי הקישור דינמי רק במובן שהוא לא הגיע מוכן מראש. אחרי יצירתו הוא נשמר ב-cache והוא סטטי.

שם מומלץ:

- `GeneratedInlineLink`: קישור inline שנוצר מקומית.
- `GeneratedLinkTarget`: יעד הקישור.
- `GeneratedLinksCache`: cache מקומי של קישורים שנוצרו.
- `GeneratedLinksProcessor`: מנוע יצירת הקישורים.

אם רוצים שם קצר יותר בקוד, אפשר להשתמש ב-`LocalInlineLink`, אבל במסמך הזה נשתמש ב-`GeneratedInlineLink`.

## ארכיטקטורה מוצעת

להוסיף feature חדש:

```text
lib/generated_links/
├── bloc/
│   ├── generated_links_bloc.dart
│   ├── generated_links_event.dart
│   └── generated_links_state.dart
├── models/
│   ├── generated_inline_link.dart
│   ├── generated_link_target.dart
│   ├── generated_links_cache.dart
│   └── generated_links_processing_status.dart
├── repository/
│   ├── generated_links_repository.dart
│   ├── generated_links_cache_store.dart
│   └── generated_links_book_resolver.dart
├── rules/
│   ├── generated_link_rule.dart
│   ├── generated_link_rules_registry.dart
│   ├── gemara_reference_rule.dart
│   ├── gemara_sham_reference_rule.dart
│   ├── tanach_reference_rule.dart
│   └── tanach_sham_reference_rule.dart
└── services/
    ├── generated_links_scheduler.dart
    ├── generated_links_processor.dart
    ├── generated_links_work_gate.dart
    └── generated_links_text_mapper.dart
```

הסיבה להפרדה הזו:

- `rules/` מכיל רק כללים לזיהוי "מה הוא לינק".
- `services/` מכיל תזמון, עיבוד, איזולייטים ותעדוף.
- `repository/` מכיל שמירה וטעינה מקובצי cache.
- `bloc/` מחבר את התוצאה ל-UI.
- `models/` מגדיר חוזים יציבים.

## מודל נתונים

### GeneratedInlineLink

זהו המודל הפנימי של קישור inline שנוצר מקומית. לא להשתמש ישירות במודל `Link` בזמן הזיהוי, כי `Link` מייצג גם קישורי DB קיימים.

שדות נדרשים:

- `sourceBookId`: ה-ID היציב של ספר המקור.
- `sourceLineIndex`: מספר שורה 0-based.
- `start`: מיקום התחלה בתוך השורה, 0-based.
- `end`: מיקום סוף בתוך השורה, exclusive.
- `matchedText`: הטקסט שהפך לקישור.
- `target`: אובייקט יעד.
- `ruleId`: למשל `gemara.reference.v1`.
- `confidence`: ערך בין 0 ל-1.
- `createdAt`: זמן יצירה.

### GeneratedLinkTarget

שדות:

- `bookTitle`: שם ספר היעד.
- `categoryId`: אם ידוע.
- `fileType`: בדרך כלל `txt`.
- `targetIndex`: שורת יעד 0-based.
- `displayRef`: טקסט להצגה, למשל `ברכות דף ב א`.

אם הכלל זיהה הפניה אבל לא הצליח לפתור יעד אמיתי בספרייה, לא לשמור קישור פעיל. אפשר לשמור סטטיסטיקה פנימית, אבל לא להציג קישור שבור.

### GeneratedLinksCache

קובץ cache של ספר צריך לכלול:

- `schemaVersion`.
- `rulesVersion`.
- `appVersion`, אם זמין.
- `sourceBookId`.
- `sourceFingerprint`.
- `status`.
- `processedRanges`.
- `links`.
- `updatedAt`.

`sourceFingerprint` צריך להיגזר ממידע יציב:

- עבור ספר DB: `title`, `categoryId`, `fileType`, מספר שורות, ואם יש מועד עדכון או גרסת DB זמינה.
- עבור ספר קובץ: `filePath`, `fileSize`, `lastModified`.

אם ה-fingerprint השתנה, ה-cache לא תקף.

## איפה לשמור את ה-cache

להוסיף ל-`AppPaths` מתודה:

```dart
Future<String> getGeneratedLinksCachePath()
```

הנתיב חייב להיות תחת `AppPaths.getDataRootPath()`, כדי שכל קבצי ה-JSON וכל קבצי העזר של המערכת יישמרו באזור הנתונים הסטנדרטי של אוצריא בכל פלטפורמה.

בווינדוס, לפי `AppPaths`, השורש הוא:

```text
C:\Users\user\AppData\Roaming\otzaria
```

לכן קבצי הקישורים צריכים להישמר בתיקייה פנימית תחת השורש הזה, למשל:

```text
C:\Users\user\AppData\Roaming\otzaria\links\generated\
```

ובאופן כללי:

```text
{dataRoot}/links/generated/
```

לכל ספר ליצור קובץ JSON נפרד בשם ה-ID של הספר. לא ליצור hash ולא להשתמש בשם הספר.

```text
{dataRoot}/links/generated/books/12345.json
```

ה-ID הוא המזהה היציב של הספר בקטלוג/DB, ולכן הוא מתאים לשם קובץ: קצר, ASCII, וייחודי. אם ספר עדיין לא קיבל ID יציב, לא מתחילים ליצור לו קישורים ולא כותבים cache זמני בשם אחר.

## כתיבה בטוחה לקבצי cache

אסור לכתוב ישירות לקובץ הסופי.

תהליך כתיבה:

1. לכתוב לקובץ זמני: `{bookId}.json.tmp`.
2. לבצע flush.
3. להחליף את הקובץ הסופי באמצעות rename.
4. רק אחרי rename מוצלח לעדכן manifest אם יש.

אם האפליקציה נסגרת באמצע:

- קובץ `.tmp` לא נחשב.
- קובץ עם `status: processing` לא נחשב כטופל במלואו.
- רק `status: complete` אומר שכל הספר עובד.

## סטטוסים

להגדיר סטטוס עיבוד:

- `notStarted`: אין cache.
- `processing`: יש עיבוד חלקי.
- `partial`: יש טווחים שעובדו ונשמרו, אבל הספר לא הושלם.
- `complete`: כל השורות עובדו לפי גרסת הכללים הנוכחית.
- `stale`: ה-cache קיים אבל לא מתאים ל-fingerprint או ל-rulesVersion.
- `failed`: אירעה שגיאה חוזרת, עם זמן ניסיון אחרון.

חשוב: אם המשתמש פתח ספר, העיבוד התחיל, ואז האפליקציה נסגרה, הספר יישאר `partial` או `processing`, לא `complete`.

בטעינה הבאה:

- טווחים שכבר נשמרו נטענים מיד.
- הטווחים החסרים נכנסים שוב לתור.

## תור עיבוד ותעדוף

העיבוד צריך להיות מנוהל על ידי `GeneratedLinksScheduler`.

סוגי משימות:

1. `visibleWindow`: הטווח שהמשתמש קורא עכשיו, עדיפות גבוהה.
2. `nearVisibleWindow`: כמה עשרות שורות לפני ואחרי, עדיפות בינונית.
3. `openedBookRemainder`: שאר הספר שנפתח, עדיפות נמוכה.
4. `historyBookWarmup`: ספרים מההיסטוריה, עדיפות נמוכה מאוד.

בפתיחת ספר:

1. נטען תוכן הספר כרגיל.
2. נטען cache קיים באופן מיידי.
3. מציגים מיד קישורים שכבר קיימים ב-cache.
4. לאחר סיום טעינת הספר, מפעילים משימת `visibleWindow`.
5. לאחר מכן `nearVisibleWindow`.
6. לאחר מכן שאר הספר, רק אם אין עומס.

בגלילה:

- לא להריץ עיבוד בכל אירוע גלילה.
- להשתמש debounce של כ-300 עד 600ms.
- אם הטווח החדש כבר עובד או כבר ב-cache, לא להוסיף משימה כפולה.
- אם יש משימה נמוכה שרצה, לא חייבים לעצור אותה, אבל לא להתחיל משימה נמוכה חדשה לפני טווח הקריאה הנוכחי.

## זיהוי עומס

צריך service קטן: `GeneratedLinksWorkGate`.

הוא מחזיר `canRunGeneratedLinksNow`.

הוא צריך לבדוק:

- האם `IndexingBloc.state is IndexingInProgress`.
- האם `WorkStatusCubit.state.hasActiveItems`.
- האם `FileSyncBloc` באמצע סנכרון, אם יש state כזה.
- האם הספרייה עדיין נטענת.
- האם האפליקציה בדיוק ב-startup לפני ש-`StartupWorkGate` שחרר עבודות רקע.

אם יש פעילות כבדה:

- לא מתחילים עיבוד חדש.
- לא מוחקים cache קיים.
- לא חוסמים טעינת ספר.
- אפשר לטעון cache קיים מהדיסק, כי זו פעולה קלה יחסית.

כאשר העומס מסתיים, scheduler יכול להמשיך משימות ממתינות.

## חיבור ל-TextBookBloc

לא להעמיס את כל הלוגיקה על `TextBookBloc`.

כן צריך להוסיף לו נקודות חיבור:

1. לאחר `TextBookLoaded` ראשוני, לשלוח ל-`GeneratedLinksBloc` אירוע `BookOpened`.
2. כאשר `visibleIndices` משתנים, לשלוח `VisibleRangeChanged`.
3. כאשר מתקבלים קישורים שנוצרו ב-isolate, להעביר אותם למודל תצוגה מתאים ולהוסיף אותם ל-state.

המלצה מעשית:

- לשמור את `state.links` לקישורי DB קיימים.
- להוסיף ל-`TextBookLoaded` שדה נפרד:

```dart
final Map<int, List<GeneratedInlineLink>> generatedLinksByLine;
```

ואז ב-UI להשתמש בשני המקורות:

- קישורי DB רגילים לחלונית קישורים ומפרשים.
- קישורי inline שנוצרו מקומית רק בתוך הטקסט.

כך לא מערבבים בין קישורי DB לבין קישורים שנוצרו מקומית.

אם רוצים לחסוך שינוי UI גדול, אפשר בשלב ראשון להמיר `GeneratedInlineLink` ל-`Link` רק בשכבת התצוגה, אבל לא לשמור אותם ב-`state.links` הכללי.

## רינדור קישורים בתוך הטקסט

הפונקציה הקיימת `addInlineLinksToText` היא בסיס טוב, אבל צריך לשפר:

1. לא להשתמש ב-style קשיח.
2. להוסיף class, למשל:

```html
<a class="generated-inline-link" href="otzaria://generated-link?...">
```

3. להגדיר צבע דרך `HtmlWidget.customStylesBuilder` או theme.
4. לוודא ש-`start/end` מתייחסים לטקסט המקורי לפני הסרת ניקוד/טעמים.
5. אם המשתמש בחר להסיר ניקוד/טעמים, הקישור עדיין צריך לעטוף את הטקסט המקורי לפני העיבוד, ואז `TextRendererService` ימשיך לעבד את התוכן.

חשוב: קישורים צריכים להיות מוזרקים לפני `TextRendererService.render`, כמו שכבר נעשה היום ב-`combined_book_screen.dart`.

## פתיחת קישור

להרחיב את `HtmlLinkHandler` לתמוך ב:

```text
otzaria://generated-link?book=...&categoryId=...&fileType=txt&index=...
```

כללים:

- לפתוח בטאב חדש או למקד טאב קיים לפי ההתנהגות הקיימת של `OpenOrFocusTab`.
- `index` צריך להיות 0-based או 1-based באופן עקבי. מומלץ שה-URL יהיה 0-based בשם `index0`, כדי למנוע בלבול.
- אם הספר לא נמצא, להציג `UiSnack.showError`.
- לא להשתמש ב-`ScaffoldMessenger` ישירות.

## קובץ הכללים

הכללים חייבים להיות מופרדים מהתזמון, מה-cache ומה-UI.

ממשק מומלץ:

```dart
abstract class GeneratedLinkRule {
  String get id;
  int get version;
  Future<List<DetectedReference>> detect(
    GeneratedLinkRuleContext context,
    List<String> lines,
    Range<int> lineRange,
  );
}
```

`DetectedReference` צריך להכיל:

- `sourceLineIndex`.
- `start`.
- `end`.
- `matchedText`.
- `targetBookTitle`.
- `targetRefText`.
- `ruleId`.
- `confidence`.

ה-rule לא פותח ספר, לא כותב cache, ולא מייצר HTML.

### סדר כללים מומלץ

שלב ראשון:

1. `GemaraReferenceRule`.
2. `GemaraShamReferenceRule`.
3. `TanachReferenceRule`.
4. `TanachShamReferenceRule`.

שלב שני, לאחר שהמערכת יציבה:

- הפניות לרמב"ם.
- טור/שו"ע.
- משנה.
- מדרשים.

לא להתחיל עם כל סוגי המקורות יחד. קודם להעמיד תשתית יציבה עם שני סוגים.

## כללי גמרא

להתבסס על הרעיונות מה-fork, אבל להחזיר טווחים מובנים ולא HTML.

תמיכה נדרשת בשלב ראשון:

- `ברכות ב.`
- `ברכות ב:`
- `ברכות ב א`
- `ברכות ב ב`
- `ברכות דף ב ע"א`
- `בברכות דף ב ע"א`
- `דברכות`, `מברכות`, `לברכות`, `כברכות`, `שברכות`, כאשר ברור שזה שם מסכת.

בדיקות חובה:

- `כו'.` לא מזוהה כדף כו.
- דף גדול ממספר הדפים במסכת לא מזוהה.
- מילה רגילה שמכילה שם מסכת לא מזוהה.
- שני מראי מקום באותה שורה מקבלים `start/end` נכונים לפי `match.start/end`, לא לפי `indexOf`.

## כללי "שם" בגמרא

`GemaraShamReferenceRule` לא צריך לחפש HTML קודם. הוא צריך לקבל מה-context את ההפניות שכבר זוהו באותו חלון עיבוד.

כללים:

- `(שם)` מתייחס למראה המקום האחרון לפניו.
- `(שם צב ב)` מתייחס לאותה מסכת, דף אחר.
- אם בין ההפניה הקודמת לבין `שם` יש זוג סוגריים או מרובעים עם תוכן אחר, לדלג.
- אם אין הפניה קודמת באותו טווח, אפשר להסתכל כמה שורות אחורה, אבל רק בתוך טווח look-behind מוגדר.

## כללי תנ"ך

להתחיל שמרני:

- `(בראשית א, א)`
- `(בראשית א א)`
- `[בראשית א, א]`
- `בראשית פרק א פסוק א`
- ראשי תיבות נפוצים: `שמ"א`, `שמ"ב`, `מל"א`, `מל"ב`, `דה"א`, `דה"ב`.

לא לזהות בהתחלה כל הופעה חופשית של `בראשית א א` בלי סוגריים, כי זה עלול לגרום להרבה false positives. אפשר להוסיף זאת רק אחרי בדיקות.

צריך לפתור יעד לפי תוכן העניינים או לפי `refFromIndex` ההפוך אם קיים כלי מתאים. אם אין דרך אמינה למצוא פסוק, לא יוצרים קישור פעיל.

## פתרון יעד

להוסיף `GeneratedLinksBookResolver`.

אחריות:

- לקבל `targetBookTitle` ו-`targetRefText`.
- למצוא ספר בספרייה דרך `LibraryProviderManager`/`BookLocator`.
- למצוא `targetIndex`.
- להחזיר `GeneratedLinkTarget`.

ה-resolver חייב להיות נפרד מה-rule, כי rule אמור לזהות טקסט, לא להכיר DB או providers.

אם פתרון היעד יקר:

- להחזיק cache בזיכרון לפי `bookTitle + refText`.
- להגביל מספר ניסיונות כושלים.
- לשמור בקובץ cache רק קישורים שהיעד שלהם נפתר.

## יצירה ב-isolate

`GeneratedLinksProcessor` חייב ליצור את הקישורים ב-isolate. אין להריץ את regex, כללי הזיהוי, חישוב `start/end`, או יצירת אובייקטי `GeneratedInlineLink` על ה-main isolate.

זרימת החובה:

1. ה-UI או `TextBookBloc` מדווחים על ספר וטווח שורות.
2. `GeneratedLinksScheduler` בודק עומס ותעדוף.
3. `GeneratedLinksProcessor` שולח ל-isolate payload סריאלי בלבד: מזהה ספר, fingerprint, טווח שורות, הטקסט הגולמי של השורות, גרסת כללים, ונתוני עזר מינימליים לפתרון יעדים.
4. ה-isolate מפעיל את `GeneratedLinkRule`-ים, מחשב `start/end`, פותר יעד ככל האפשר, ובונה רשימת `GeneratedInlineLink`.
5. ה-isolate מחזיר את הרשימה ל-main isolate.
6. ה-main isolate שומר את התוצאה ב-cache ומעדכן את `GeneratedLinksBloc`.
7. שכבת הטקסט מקבלת `generatedLinksByLine`, מזריקה `<a>` סביב הטווחים, והטקסט נצבע והופך ללחיץ.

כללים חשובים:

- גם טווח קטן חייב לעבור דרך isolate. זה מונע תקיעות UI ומבטיח שהתנהגות המערכת עקבית.
- לא להעביר ל-isolate אובייקטי Flutter, `BuildContext`, BLoC, controllers, או מחלקות שאינן sendable.
- אם פתרון יעד דורש provider שאינו יכול לרוץ ב-isolate, להכין מראש ב-main isolate מפת עזר סריאלית קטנה, או לבצע שלב resolve נפרד שאינו מריץ regex כבד. בכל מקרה, אובייקט `GeneratedInlineLink` שנשלח ל-UI צריך להיות אחרי פתרון יעד תקין.
- אם היעד לא נפתר, ה-isolate מחזיר רשומת debug/סטטיסטיקה אופציונלית, אבל לא מחזיר קישור פעיל לצביעה.

מנת עיבוד מומלצת:

- 50 עד 200 שורות בכל batch.
- אחרי כל batch מוצלח, לשמור cache חלקי.
- אחרי כל batch, לבדוק cancellation token.

## ביטול וסגירת אפליקציה

לכל משימה יהיה `jobId` ו-`cancellationToken`.

כאשר:

- המשתמש סוגר טאב.
- המשתמש פותח ספר אחר באותו bloc.
- האפליקציה נסגרת.
- מתחיל אינדוקס או סנכרון כבד.

צריך:

1. לעצור התחלת batch חדש.
2. לתת ל-batch הנוכחי להסתיים או לבטל אותו אם אפשר.
3. לשמור את מה שכבר הושלם כ-`partial`.
4. לא לסמן `complete`.

להירשם ל-`PreCloseRegistry` ולבצע flush מהיר של התוצאות שכבר מוכנות. לא להתחיל עיבוד חדש בזמן pre-close.

## עיבוד ספרים מהיסטוריה

לאחר שהאפליקציה סיימה startup ואין עומס:

1. לטעון `HistoryRepository.loadHistory`.
2. לקחת עד N ספרי טקסט אחרונים, למשל 10.
3. לדלג על ספרים עם cache תקף `complete`.
4. לדלג על ספרים גדולים במיוחד אם המחשב בעומס.
5. לעבד בעדיפות נמוכה.

חשוב: עיבוד היסטוריה לא אמור להתחרות בספר שהמשתמש קורא כרגע. אם נפתח ספר חדש, משימות ההיסטוריה יורדות לתחתית התור.

## עדכון UI בזמן אמת

כאשר batch הסתיים:

1. לשמור ל-cache.
2. לשלוח ל-`GeneratedLinksBloc` state חדש עם הקישורים שנוספו.
3. `TextBookBloc` או widget מקבל את הקישורים.
4. רק שורות שיש להן קישורים חדשים צריכות להיבנות מחדש.

בפועל, אם משתמשים ב-`BlocBuilder` רחב, כל הרשימה עלולה להיבנות. לכן עדיף:

- להחזיק `generatedLinksByLine`.
- להשתמש ב-`ValueListenable`/selector לשורה בודדת, או לפחות ב-`buildWhen` שמצמצם rebuild.

שלב ראשון יכול להיות פשוט יותר, אבל לבדוק ביצועים בספר עם אלפי שורות.

## הגדרות משתמש

להוסיף תחת הגדרות טקסט:

- הפעלת קישורים שנוצרים מקומית: on/off.
- עיבוד ברקע לספרים מהיסטוריה: on/off.
- סוגי קישורים: תנ"ך, גמרא.

להשתמש ב-`SettingsCard` וב-`SegmentedSettingsTile`/מתגים קיימים לפי הנחיות הפרויקט.

לא להציג הודעות קופצות על כל עיבוד. זו עבודה שקטה.

## שלבי מימוש

### שלב 1: תשתית cache ומודלים

קבצים:

- `lib/generated_links/models/*`
- `lib/generated_links/repository/generated_links_cache_store.dart`
- הרחבה קטנה ל-`AppPaths`.

בדיקות:

- כתיבה אטומית.
- טעינת cache תקף.
- דחיית cache עם fingerprint שונה.
- קובץ `processing` לא נחשב `complete`.

### שלב 2: מנוע rules טהור

קבצים:

- `lib/generated_links/rules/*`

בדיקות:

- גמרא רגיל.
- אותיות שימוש.
- `שם`.
- תנ"ך בסיסי.
- false positives.
- שני matches זהים באותה שורה.

אין UI ואין cache בשלב הזה.

### שלב 3: resolver

קבצים:

- `generated_links_book_resolver.dart`

בדיקות:

- ספר יעד קיים.
- ספר יעד לא קיים.
- ref שלא נמצא.
- cache בזיכרון לפתרון חוזר.

### שלב 4: processor ו-scheduler

קבצים:

- `generated_links_processor.dart`
- `generated_links_scheduler.dart`
- `generated_links_work_gate.dart`

בדיקות:

- visible range מקבל עדיפות.
- עומס עוצר התחלת עבודה.
- partial נשמר אחרי batch.
- cancellation לא מסמן complete.

### שלב 5: חיבור ל-reader

קבצים צפויים:

- `lib/text_book/bloc/text_book_bloc.dart`
- `lib/text_book/bloc/text_book_state.dart`
- `lib/text_book/view/combined_view/combined_book_screen.dart`
- `lib/utils/html_link_handler.dart`

בדיקות:

- ספר נטען מיד גם בלי cache.
- cache קיים מוצג מיד.
- קישורים חדשים מופיעים לאחר batch.
- לחיצה פותחת טאב ליעד.
- חלונית קישורים לא מציגה generated inline links.

### שלב 6: היסטוריה ו-startup

קבצים צפויים:

- `MainWindowScreen` או service שיופעל ממנו לאחר `StartupWorkGate`.
- `HistoryRepository`.

בדיקות:

- אם אינדוקס רץ, לא מתחיל עיבוד.
- אחרי אינדוקס, משימות היסטוריה מתחילות.
- פתיחת ספר חדש מקדמת אותו מעל משימות היסטוריה.

## בדיקות רלוונטיות להרצה

לאחר שינויי generated links:

```bash
dart format lib/generated_links/... test/generated_links/...
flutter analyze
flutter test test/generated_links/
flutter test test/inline_links_test.dart
flutter test test/text_book/bloc/text_book_bloc_test.dart
```

לא להריץ full suite כברירת מחדל אם לא נגעו בתשתית רחבה, אבל אם משנים את `TextBookBloc`, `HtmlLinkHandler` או `SmartTextWidget`, להריץ גם בדיקות reader רלוונטיות.

## טעויות שחשוב להימנע מהן

- לא לעשות cherry-pick לקומיטים מה-fork.
- לא להוסיף עמודות ל-DB.
- לא לשמור קישורים שנוצרים מקומית בטבלת `link`.
- לא לייצר JSON שמשתמשים יורידו.
- לא להריץ regex בכל build של שורה.
- לא לערבב זיהוי עם HTML.
- לא להשתמש בצבעים קשיחים.
- לא לסמן ספר כ-`complete` לפני שכל השורות עובדו ונשמרו.
- לא לבלוע שגיאות בלי debug log.
- לא להשתמש ב-`text.indexOf` למציאת match כאשר יש `match.start`.

## הגדרה של Done

המערכת נחשבת מוכנה לשלב ראשון כאשר:

1. פתיחת ספר אינה מתעכבת בגלל יצירת קישורים.
2. cache קיים נטען ומוצג מיד.
3. הטווח הנראה מקבל קישורים תוך זמן קצר ברקע.
4. סגירת אפליקציה באמצע משאירה cache חלקי ולא מסמנת complete.
5. אין כתיבה ל-DB ואין תלות בקובץ קישורים שהמשתמש הוריד.
6. כללי גמרא ותנ"ך נמצאים בקבצים נפרדים וניתנים לשיפור ללא נגיעה ב-UI.
7. `flutter analyze` עובר ללא שגיאות.
