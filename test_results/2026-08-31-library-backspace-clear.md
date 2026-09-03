# issue #1061 — Backspace בחיפוש הספרייה מוחק תו אחד, לא את כל השורה

תאריך: 2026-08-31 | ענף: `fix/library-backspace-clear-1061` | קומיטים: `b864ef27`, `f618950d`

## שורש הבאג

‏#899 (קומיט `d526e3e6`, הקומיט היחיד שנגע במנגנון — תואם את הדיווח
"התחיל בגרסה האחרונה") הוסיף שומר Backspace לספרייה שמכריע לפי
`primaryFocus.context.widget is EditableText / TextField`. הבדיקה הזו
מחזירה false **תמיד**: צומת הפוקוס של TextField נקשר לווידג'ט Focus
פנימי, לא ל-TextField עצמו. לכן כל Backspace בשדה עם טקסט סווג
כ"פוקוס מחוץ לשדה" → `clearSearch` → כל החיפוש נמחק והרשת התאפסה,
והמקש נבלע לפני שהגיע למחיקת התו של מנגנון עריכת הטקסט.

## הפתרון

`isEditableTextFocusTarget()` ב-`lib/utils/ui/editable_focus.dart`:
אחרי בדיקת הווידג'ט עצמו נבדק גם `EditableText` כאב-קדמון של הקשר
הפוקוס. הספרייה (`_handleLibraryKey`) עברה להשתמש בו, וכך גם
`KeyboardNavigator` שנשא את אותו פגם בדיוק (Backspace בתוך שדה טקסט
בהגדרות/דיאלוג הפעיל `onBack`). התנהגות #899 הרצויה נשמרה: שדה ריק
וממוקד — עולים תיקייה; פוקוס מחוץ לשדה — חיפוש פעיל נסגר תחילה.

## בדיקות

`test/library/view/library_backspace_focus_test.dart` — 4 בדיקות: זיהוי
שדה ממוקד (נכשלה לפני התיקון), שדה ריק עדיין מנווט, פוקוס חיצוני מזוהה
כ-false, ובדיקת שיגור-מקשים אמיתי (enterText + sendKeyEvent) המוכיחה
ש-Backspace מוחק תו אחד ואינו מסווג כניקוי חיפוש.
`test/widgets/navigation/keyboard_navigator_backspace_test.dart` — 2
בדיקות: בשדה ממוקד אין `onBack` והתו נמחק; מחוץ לשדה `onBack` נורה.
כל השש נכשלות מול הזיהוי הישן (אומת בהחלפה זמנית) ועוברות עם התיקון.

## אימות ויזואלי (Windows, בנייה מקומית)

| שלב | בסיס (לפני) | הענף (אחרי) |
|---|---|---|
| הקלדה בשדה | `img/1061-before-typed.jpg` — "חידושי הרשבע" | `img/1061-after-typed.jpg` — "yzq" |
| ‏Backspace אחד | `img/1061-before-backspace-cleared.jpg` — **השדה התרוקן כולו** והרשת התאפסה | `img/1061-after-backspace-one-char.jpg` — **נמחק תו אחד בלבד** ("yz" נשאר) |

## סוויטה מלאה

`flutter test`: **11,110 עברו, 8 נכשלו, 7 דולגו** — בדיוק שמונת הכשלים
הסביבתיים/קיימים-מראש המוכרים (release_packaging, ‏3×file_sync_compaction,
‏DOCX personal_notes, ‏plugin_spec_freshness, ‏search_scope_menu flake,
‏custom_folder_model). אפס רגרסיות.
