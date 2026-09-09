# issue #1236 — ציוני הערות מקובצי וורד: רק 1–3 בגופן הנכון

תאריך: 2026-09-09 | ענף: `fix/footnote-marker-digits-font-1236` | קומיט אימות: `57af7ea77`

## הבאג שאומת

מרקר הערה מספרי (`<sup class="footnote-marker">N</sup>`, וגם `<sup>N</sup>`
חשוף ומרקר הערה מוטבעת) הומר ב-`TextRendererService` וב-`inline_notes_utils`
לגליפי ספרות-עיליות יוניקוד (`superscript_digits.dart`). ¹ ² ³ יושבות
בבלוק Latin-1 (U+00B9/B2/B3) שקיים בכל גופן, ואילו ⁰ ו-⁴–⁹ בבלוק
Superscripts (U+2070, U+2074–U+2079) שחסר ברוב גופני המערכת — Flutter נופל
לגופן אחר עבורן. זה מסביר במדויק את הדיווח: "123 בלבד מופיעים בגופן המתאים
וכל השאר מופיעים במראה אחר", ולמה בגופנים המצורפים לתוכנה (שמכילים את הבלוק)
הכול אחיד.

## הפתרון (הסרה)

ההמרה לגליפים עיליים הוסרה. מרקר מספרי עובר עכשיו באותו מסלול שכבר שימש
מרקר-אות: span טקסט טהור (`footnote-marker-number` / `raised-sup`, ולהערה
מוטבעת `book-note-marker`) שהספרות בו הן ספרות רגילות של גופן הספר,
מוקטנות ומורמות בציור ע"י `RaisedMarkerOverlay` (כפי שתועד ב-raised_markers.dart).
הענף `book-note-marker-sup` ב-`SmartTextWidget` וב-`ContinuousReadingParagraph`
והקובץ `superscript_digits.dart` נותרו בלי שימוש והוסרו. הגליפים התחתיים
(issue #842) לא נגעו — כל ₀–₉ יושבות בבלוק אחד ואינן מפוצלות בין גופנים.

## בדיקות

| קובץ | מה נבדק |
|---|---|
| `test/widgets/smart_text/text_renderer_service_test.dart` | חדש: מרקר מספרי ו-sup מספרי חשוף נפלטים כ-span עם ספרות רגילות ובלי גליפים עיליים (נכשלו על הבסיס); הבדיקות הקיימות של הסדר, הבידוד הדו-כיווני ו-sup חשוף עודכנו לחוזה החדש |
| `test/text_book/utils/inline_notes_utils_test.dart` | חדש: מרקר הערה מוטבעת מספרי → `book-note-marker` עם הספרה כפי שהיא (נכשל על הבסיס); הבדיקה הקיימת עודכנה |
| `test/widgets/smart_text/raised_markers_test.dart` | sup מספרי הוא span ועובר בשכבת הציור כמו סימון-אות |
| `test/widgets/smart_text/smart_text_marker_no_placeholder_test.dart` | מקרה המרקר המספרי עבר ל-`book-note-marker` (בלי WidgetSpan) |

`test/widgets/smart_text/` + `inline_notes_utils_test`: 180 עברו. בדיקות ממוקדות
`test/widgets/smart_text/`, `test/text_book/`, `test/utils/file/`: **2,794 עברו, 0 נכשלו**.

## הערה על הבסיס

הענף מבוסס על `d4503f480` (Merge #1220): ראש `dev` (511529810) אינו מתקמפל
(ה-API של `seforim_library_updater` טרם פורסם ל-`main` של החבילה).

## סוויטה מלאה

`flutter test` על הענף (worktree נקי, עם מנוע החיפוש): **12,399 עברו, 9 דולגו,
9 נכשלו** — כולן כשלי הבסיס המוכרים, ללא קשר לשינוי:

| בדיקה | סטטוס |
|---|---|
| `installer/release_packaging_test` | בסיס (חבילת הפצה, תלוי-מכונה) |
| `migration/sync/file_sync_service_compaction_test` ×3 | בסיס |
| `navigation/tab_context_menu_test` "לחלון קיים — עוברת" | בסיס (מהבהב) |
| `personal_notes/personal_notes_file_backed_book_test` DOCX | בסיס |
| `search/search_scope_menu_search_actions_test` (#933) | בסיס (מהבהב) |
| `settings/dialogs/change_location_dialog_test` uninstaller | בסיס |
| `shamor_zachor/shamor_zachor_data_provider_test` fallback | בסיס (נכשל זהה על d4503f480) |

## אימות ויזואלי (לפני/אחרי)

בנייה `flutter build windows --debug` של הבסיס (`d4503f480`) ושל הענף, אותו ספר
("נחלת אבות על אבות", `otzaria://open/book/889?index=144`) ואותו גופן ספר — **David**
של Windows, שכמו FrankRuehl/Narkisim/Miriam מכיל ¹²³ (Latin-1) אך לא ⁰⁴–⁹
(אומת עם fontTools על קובצי הגופנים).

| | תמונה |
|---|---|
| לפני — 3 בגופן הספר, 4/5/6/10 בגופן fallback דק (Segoe UI) | [before](https://raw.githubusercontent.com/dudua99/otzaria/pr-screenshots/1236/before.png) |
| אחרי — כל המרקרים ספרות של גופן הספר, מוקטנות ומורמות בציור | [after](https://raw.githubusercontent.com/dudua99/otzaria/pr-screenshots/1236/after.png) |
| השוואה מוגדלת, אותם אזורים בשתי התמונות | [compare](https://raw.githubusercontent.com/dudua99/otzaria/pr-screenshots/1236/compare.png) |
