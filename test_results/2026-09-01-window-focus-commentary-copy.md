# issue #1071 — העתקת Ctrl+C ממפרשים בצורת הדף מפסיקה לעבוד אחרי יציאה וחזרה

תאריך: 2026-09-01 | ענף: `fix/window-focus-keeps-key-handlers-1071` | קומיט קוד: `345e70cf`

## שורש הבאג

‏Ctrl+C ממפרש בצורת הדף עובר דרך handler גלובלי שכל חלונית מפרש רושמת
ב-`HardwareKeyboard.instance.addHandler` (המפרשים לוכדים את הקיצור בלי
פוקוס). במקביל, `AppWindowListener.onWindowFocus` קרא ל-
`HardwareKeyboard.instance.clearState()` כדי לשחרר מקש "תקוע" ממעבר
חלונות — אבל clearState הוא API של מסגרת הבדיקות (`@visibleForTesting`)
שמוחק גם את **כל רשימת ה-handlers**. לכן ההעתקה עבדה רק עד היציאה
הראשונה מהחלון; אחרי חזרה, Ctrl+C נפל אל הטקסט הראשי והציג
"אנא בחר טקסט להעתקה" לצמיתות — בעוד העתקה מתפריט לחצן-ימני המשיכה
לעבוד (קריאה ישירה, בלי handler), בדיוק כפי שדווח.

## מהלך האימות (בנייה מקומית, פרוטוקול sentinel בלוח ההעתקה)

1. שוחזר חי: בחירה גלויה במפרש ← Ctrl+C ← הלוח נשאר עם ה-sentinel
   ("COPY-FAILED") והוצג "אנא בחר טקסט להעתקה".
2. חיישני debugPrint זמניים תחת flutter run הוכיחו את השרשרת:
   `addHandler` נרשם בעליית החלונית; אחרי מחזור פוקוס-חלון האירוע כלל לא
   הגיע ל-handler (השורה לא הודפסה) בעוד ה-fallback של הטקסט הראשי רץ
   (`saved=null`). מקור ה-SDK מאשר: `clearState()` מבצע `_handlers.clear()`.
3. טריגרים שנשללו בבדיקה מבוקרת: מעבר לשוניות, מעבר מסכים, החלפת מצב
   תצוגה, דאבל-קליק — כולם עברו; רק מחזור פוקוס-חלון שבר.

## הפתרון

‏`onWindowFocus` משחרר את המקשים התקועים בלבד — `KeyUpEvent` סינתטי לכל
מקש לחוץ, דרך `handleKeyEvent` הציבורי — במקום clearState. ההגנה המקורית
(מניעת ה-assertion ממקש שהוחזק במעבר חלון) נשמרת, וה-handlers שורדים.
מסנן ה-fallback לאותו assertion ב-main.dart נשאר כרשת ביטחון.

## בדיקות

`test/core/window_listener_focus_keyboard_test.dart` — מדמה מקש תקוע,
מריץ `onWindowFocus`, ומוודא שהמקש שוחרר **וש-handler רשום ממשיך לקבל
אירועים**. נכשלת מול clearState (אומת בהחלפה זמנית) ועוברת עם התיקון.
בנוסף עברו כל בדיקות ההעתקה/בחירה של צורת הדף (53 בדיקות:
`simple_text_viewer_copy_after_right_click`, `simple_text_viewer`,
`page_shape_commentary_selection`).

## אימות ויזואלי (ברכות דף ב, צורת הדף, אחרי מחזורי פוקוס-חלון)

| גרסה | Ctrl+C ממפרש | צילום |
|---|---|---|
| לפני (בסיס) | הלוח לא השתנה, "אנא בחר טקסט להעתקה" למרות בחירה גלויה | `img/1071-before-copy-failed.jpg` |
| אחרי (הענף) | הלוח קיבל את הטקסט + "הטקסט המעוצב הועתק ללוח" | `img/1071-after-copy-ok.jpg` |

## סוויטה מלאה

`flutter test`: **11,104 עברו, 8 נכשלו, 7 דולגו** — בדיוק שמונת הכשלים
הסביבתיים/קיימים-מראש המוכרים (release_packaging, ‏3×file_sync_compaction,
‏DOCX personal_notes, ‏plugin_spec_freshness, ‏search_scope_menu flake,
‏custom_folder_model). אפס רגרסיות.
