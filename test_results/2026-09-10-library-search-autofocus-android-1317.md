# issue #1317 — המקלדת נפתחת מעצמה במסך הספרייה באנדרואיד

תאריך: 2026-09-10 | ענף: `fix/library-search-autofocus-android-1317` | בסיס: `upstream/dev` (8c365b5cd) | קומיט אימות: `2bfc89011`

## הבאג שאומת

אמולטור Android 14: בכל הצגה של מסך הספרייה (הפעלה, דילוג על הסיור, חזרה מהגדרות) המקלדת הווירטואלית נפתחת
ומכסה מחצית מהמסך. המקור: `OtzariaSearchField` של הספרייה נבנה עם `autofocus: true` ב-`library_browser.dart`.

## התיקון

`shouldAutofocusLibrarySearch(TargetPlatform)` — פוקוס אוטומטי רק בפלטפורמות עם מקלדת פיזית; באנדרואיד ו-iOS
השדה מקבל פוקוס רק בלחיצה. שאר ההתמקדות היזומה (ניקוי חיפוש, קיצורי מקלדת) לא השתנתה.

## בדיקות

| קובץ | מה נבדק |
|---|---|
| `test/library/view/library_search_autofocus_test.dart` | חדש: android/iOS → false; windows/linux/macOS → true. על הבסיס הפונקציה אינה קיימת (כשל קומפילציה). |

`flutter test test/library/view/library_search_autofocus_test.dart test/library/view/library_backspace_focus_test.dart`:
**5 עברו**. `flutter analyze` נקי, `dart format` ללא שינויים.

## אימות ויזואלי

APK debug של הבסיס ושל הענף על האמולטור: מסך הספרייה מיד אחרי העלייה. לפני: מקלדת פתוחה; אחרי: ללא מקלדת.
הצילומים בענף `pr-screenshots` (תיקייה `1317`).

## סוויטה מלאה

`flutter test` על הענף (במקביל לסוויטה נוספת, לבניית APK ולאמולטור): **12,621 עברו, 23 דולגו, 11 נכשלו** —
תשעת כשלי הבסיס המוכרים + שניים רגישי-עומס שעברו בבידוד (`find_ref_db_isolate_shared_queries_test`,
`tab_context_menu_test`: 9 עברו).
