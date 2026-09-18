# issue #1417 — האייקון של "הסתר ניווט" הציג את אותו חץ כמו "הצג ניווט"

**ענף:** `fix/nav-toggle-arrow-1417` על `upstream/dev` 15a654476 · **worktree:** otzaria-wt5 · **תאריך:** 17.9.2026

## השורש
`NavPanelToggleButton` מציג את גליף `OtzariaIcons.text_continuous` — שורות טקסט עם חץ קבוע (שמאלה בציור המקורי).
שני מצבי הכפתור נבדלו רק בעובי הקו (`filled`/`regular`), ולכן כשהחלונית פתוחה החץ המשיך להצביע לכיוון
הפתיחה. הגליף אינו מסומן `matchTextDirection`, כך שגם כיוון הממשק לא השפיע עליו.

## התיקון
שיקוף אופקי של הגליף (`Transform.flip`) לפי המצב וכיוון הממשק — `NavPanelToggleButton.shouldMirror`:
חלונית בצד הסוף של RTL (ימין) נפתחת שמאלה, לכן במצב סגור הגליף מוצג כפי שהוא ובמצב פתוח מתהפך
(חץ ימינה = נסגרת ימינה); בממשק LTR, שבו צד הסוף הוא שמאל, שני המצבים מתהפכים. אין שינוי בגליפים עצמם
ובחבילת האייקונים.

## בדיקות — `test/widgets/nav_panel_toggle_arrow_test.dart`

| בדיקה (issue #1417) | לפני | אחרי |
|---|---|---|
| RTL: החץ מתהפך בין חלונית סגורה לפתוחה | ❌ (אין שיקוף; אותו אייקון בשני המצבים) | ✅ |
| LTR: החלונית בצד שמאל, ולכן שני המצבים מתהפכים | ❌ | ✅ |
| `shouldMirror` — טבלת האמת של ארבעת המצבים | — | ✅ |

`test/widgets/nav_side_panel_test.dart` — עובר ללא שינוי (האייקונים והכיתובים נשמרו). `flutter analyze` — No issues found.

## סוויטה מלאה (otzaria-wt5, 27:38 דק', 13,252 בדיקות)
13 כשלים: 12 בבסיס הסביבתי המוכר שנכשל גם על dev נקי (`installer/release_packaging_test` ×2,
`migration/sync/file_sync_service_compaction_test` ×3, `data_providers/database_library_provider_test`,
`tools/calendar/helpers/calendar_print_pdf_test` ×4, `settings/dialogs/change_location_dialog_test`,
`shamor_zachor/shamor_zachor_data_provider_test`), ו-`navigation/tab_context_menu_test` ("העברת הכרטיסיה האחרונה
בחלון לחלון קיים") — flake תחת עומס מוכר, עובר בהרצה מבודדת (8/8). אין כשל חדש.

## אימות חזותי
רינדור הכפתור בשני המצבים עם גופן האייקונים האמיתי (widget test + `matchesGoldenFile`):

- לפני: https://raw.githubusercontent.com/dudua99/otzaria/pr-screenshots/1417/before.png — חץ שמאלה בשני המצבים.
- אחרי: https://raw.githubusercontent.com/dudua99/otzaria/pr-screenshots/1417/after.png — סגורה: חץ שמאלה (נפתחת שמאלה); פתוחה: חץ ימינה (נסגרת ימינה).
