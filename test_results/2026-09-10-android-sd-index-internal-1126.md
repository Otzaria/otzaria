# issue #1126 — אינדוקס נכשל אחרי העברת הספרייה לכרטיס SD באנדרואיד

תאריך: 2026-09-10 | ענף: `fix/android-sd-index-internal-1126` | בסיס: `upstream/dev` (8c365b5cd) | קומיט אימות: `f5c8b87fb`

## הבאג שאומת

אמולטור Android 14 (API 34) עם כרטיס SD מדומה בפורמט exFAT (FUSE ב-`/storage/7BF6-EB05`). ספרייה מינימלית
יובאה לאחסון הפנימי, ואז הגדרות ← ספרייה ← "מיקום אחסון הספרייה" ← כרטיס SD ← העבר. ההעברה הצליחה, אך:

```
❌ Failed to initialize search engine: PanicException(Failed to create index reader:
   LockFailure(IoError(Os { code: 38, kind: Unsupported, message: "Function not implemented" })))
⚠️ Falling back to temporary in-memory index
⚠️ המנוע על אינדקס זמני — האינדוקס מושהה כדי לא לאבד עבודה
```

בממשק: "האינדקס לא מעודכן", ולחיצה על "עדכן" → "פתיחת אינדקס החיפוש נכשלה — האינדוקס הושהה. נסה להפעיל מחדש
את התוכנה". גם אחרי הפעלה מחדש.

## המקור

`performLibraryMove` מעביר את תיקיית `index` אל הכרטיס ומקבע `keyIndexPath` אליה. Tantivy נועל את קבצי האינדקס
ב-`flock`, ו-FUSE של אחסון חיצוני באנדרואיד מחזיר ENOSYS. seforim.db ומסדי הנתונים האישיים (SQLite, נעילות POSIX)
עובדים מהכרטיס.

## התיקון

- `AppPaths`: באנדרואיד ברירת המחדל של האינדקס היא `<dataRoot>/index` תמיד (`androidInternalIndexPath`), ונתיב
  שמור מחוץ לאחסון הפנימי נדחה ומתנקה (`isIndexPathAllowedOnAndroid`). hook `debugIsAndroidOverride` לבדיקות.
- `performLibraryMove`: באנדרואיד יעד האינדקס הוא הנתיב הפנימי — אין העברה של האינדקס לכרטיס.
- `AndroidStorageLocationCard`: טקסט האישור מציין שהאינדקס נשאר באחסון הפנימי (ARB + קטלוג נוצר מחדש).

## בדיקות

| קובץ | מה נבדק |
|---|---|
| `test/core/app_paths_test.dart` | חדש (קבוצה "issue #1126"): ספרייה על SD → אינדקס פנימי; נתיב שמור על SD נדחה ומתנקה; נתיב שמור פנימי נשמר; שלא באנדרואיד האינדקס ליד הספרייה כמו קודם. על הבסיס הקבוצה נכשלת. |

`flutter test test/core/app_paths_test.dart test/settings/l10n/ test/settings/dialogs/change_location_dialog_test.dart`:
**217 עברו**. `flutter analyze` נקי, `dart format` ללא שינויים.

## אימות ויזואלי

APK debug של הבסיס: העברה לכרטיס → "עדכן" נכשל (צילום). APK של הענף הותקן **מעל אותו מצב** (הספרייה על הכרטיס,
`keyIndexPath` מצביע לכרטיס): בהפעלה המנוע נפתח על `app_flutter/index` הפנימי בלי כשל, "עדכן" בנה את האינדקס
(קובצי segment נכתבו לפנימי) והסטטוס "האינדקס מעודכן". הצילומים בענף `pr-screenshots` (תיקייה `1126`).

## סוויטה מלאה

`flutter test` על הענף (במקביל לאמולטור): **12,627 עברו, 23 דולגו, 8 נכשלו** — כולם כשלי הבסיס המוכרים:
release_packaging, compaction ×3, personal_notes_file_backed_book, search_scope_menu (flaky), shamor_zachor,
database_library_provider "buildLibraryCatalog".
