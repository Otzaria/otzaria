# issue #1430 — האות הראשונה שהוקלדה במקום חיפוש קיים בספר נמחקה

**ענף:** `fix/in-book-search-echo-1430` על `upstream/dev` 97a4d548a · **worktree:** otzaria-wt4 · **תאריך:** 18.9.2026

## השורש
שני קומיטים נכונים לעצמם שהתנגשו:
- **81d8bbd3c** (מרץ): `didUpdateWidget` של חלונית החיפוש בספר מסנכרן את השדה ל-`initialQuery` (טקסט החיפוש
  מ-state ה-BLoC) כשהוא שונה מהטקסט בשדה — כדי שסרגל החיפוש העליון וחיפוש מתקדם יעדכנו את השדה.
- **252992b54** (31.8, "התאמה חלקית מתחילה משני תווים"): `onSearchTextChanged` שולח ל-BLoC את השאילתה **המנורמלת**
  (`_searchableQuery(value) ?? ''`) — אות בודדת בהתאמה חלקית הופכת לשאילתה ריקה, כדי שהספר לא ייצבע ולא יוצג
  "אין תוצאות".

מאז, ההד שחוזר מה-BLoC אחרי הקלדת אות אחת (`''`) שונה מהטקסט הגולמי בשדה (`ד`); `didUpdateWidget` מסיק
"שינוי חיצוני" וקורא ל-`syncSearchControllerQuery(controller, '')` — האות נמחקת. זה קורה רק כשקדם חיפוש אחר,
כי אז ה-state באמת משתנה (`אבג` → `''`); בהקלדה השנייה ה-state כבר ריק, אין `queryChanged`, והאות נשארת —
בדיוק התסמין שדווח. חלונית החיפוש ב-PDF אינה מסנכרנת את השדה מה-state ולכן אינה מושפעת.

## התיקון
ב-`didUpdateWidget`: ערך שתואם ל**צורה המנורמלת** של הטקסט בשדה (`_searchableQuery(controller.text) ?? ''`) הוא הד
של השדה עצמו ואינו מסונכרן חזרה; רק ערך אחר מגיע מבחוץ ומסונכרן כמו קודם. שתי ההתנהגויות שהקומיטים הקודמים
נועדו להן נשמרות: סנכרון משאילתה חיצונית (בדיקה ייעודית), ומינימום שני תווים להתאמה חלקית (לא נגעתי).

## בדיקות — `test/text_book/view/text_book_search_typing_echo_test.dart`
החלונית נבנית כמו במסך הספר: `initialQuery` נגזר מ-state ה-BLoC, וה-BLoC מהדהד כל `UpdateSearchText`.

| בדיקה (issue #1430) | לפני | אחרי |
|---|---|---|
| האות הראשונה של המילה החדשה נשארת בשדה אחרי הד ה-BLoC | ❌ `Expected: 'ד' / Actual: ''` | ✅ |
| שינוי חיצוני אמיתי של השאילתה עדיין מסונכרן לשדה | ✅ | ✅ |

כל `test/text_book/view/` — 1,074 עברו. `flutter analyze` — No issues found. `dart format` — ללא שינוי.

## סוויטה מלאה (otzaria-wt4, 35:00 דק', 13,250 בדיקות)
14 כשלים: 12 בבסיס הסביבתי המוכר שנכשל גם על dev נקי (`installer/release_packaging_test` ×2,
`migration/sync/file_sync_service_compaction_test` ×3, `data_providers/database_library_provider_test`,
`tools/calendar/helpers/calendar_print_pdf_test` ×4, `settings/dialogs/change_location_dialog_test`,
`shamor_zachor/shamor_zachor_data_provider_test`), ושני flakes מוכרים תחת עומס — `navigation/tab_context_menu_test`
ו-`text_book/bloc/text_book_bloc_test` — שעוברים בהרצה מבודדת (61/61). אין כשל חדש.

## אימות חזותי
רינדור החלונית (widget test + `matchesGoldenFile`, גופנים אמיתיים) בשלושה שלבים — חיפוש קיים "אבג", הקלדת "ד"
במקומו, ורבע שנייה אחרי (דיבאונס + הד):

- לפני: https://raw.githubusercontent.com/dudua99/otzaria/pr-screenshots/1430/before.png — בשלב 3 השדה ריק.
- אחרי: https://raw.githubusercontent.com/dudua99/otzaria/pr-screenshots/1430/after.png — בשלב 3 השדה מכיל "ד".
