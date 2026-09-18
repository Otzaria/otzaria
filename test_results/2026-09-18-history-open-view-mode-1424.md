# issue #1424 — ספר שנקרא בצורת הדף נפתח מההיסטוריה בתצוגה רגילה

**ענף:** `fix/history-open-view-mode-1424` על `upstream/dev` 15a654476 · **worktree:** otzaria-wt6 · **תאריך:** 18.9.2026

## השורש
העדפת התצוגה (רגילה / צורת הדף) נשמרת פר-ספר בהחלפת התצוגה
(`PageShapeSettingsManager.saveViewModePreference`), אבל רק שני מסלולי פתיחה קראו אותה בפתיחת ספר:
הספרייה (`BookOpenCoordinator.buildTab`) ותוצאות החיפוש. מסך ההיסטוריה ומסך הסימניות בנו את הטאב דרך
`OpenedTab.fromBook(...)` בלי לציין מצב, ובנאי `TextBookTab` נפל ל-`false` — תצוגה רגילה.

היסטוריה: ההעדפה הפר-ספרית וקריאתה בקואורדינטור נוספו יחד; ההיסטוריה והסימניות, שנכתבו קודם, מעולם לא חוברו.

## התיקון
ברירת המחדל עוברת למקום אחד — בנאי `TextBookTab`: כשהקורא לא קבע במפורש, הטאב נפתח לפי ההעדפה השמורה לספר
(`getViewModePreference(book.title) ?? false`), כפי שהבנאי כבר עושה לתצוגה המפוצלת מההגדרות. כך **כל** מסלול
פתיחה — היסטוריה, סימניות, קישור, מפרש — מכבד את בחירת המשתמש. ערך מפורש (שחזור טאב שמור מ-JSON, שבו מצב
התצוגה של הטאב נשמר) ממשיך לגבור.

## בדיקות — `test/tabs/models/text_tab_view_mode_preference_test.dart`

| בדיקה (issue #1424) | לפני | אחרי |
|---|---|---|
| ספר שנשמר לו "צורת הדף" נפתח כך גם בלי שהקורא ציין מצב (`OpenedTab.fromBook`, מסלול ההיסטוריה) | ❌ `Expected: true / Actual: false` | ✅ |
| ספר בלי העדפה שמורה נפתח בתצוגה רגילה | ✅ | ✅ |
| העדפה שמורה "תצוגה רגילה" מכובדת | ✅ | ✅ |
| ערך מפורש מהקורא (שחזור טאב שמור) גובר על ההעדפה | ✅ | ✅ |

`flutter analyze` — No issues found. `dart format` — ללא שינוי.

## סוויטה מלאה (otzaria-wt6, 22:09 דק', 13,254 בדיקות)
12 כשלים — כולם בבסיס הסביבתי המוכר שנכשל גם על dev נקי: `installer/release_packaging_test` ×2,
`migration/sync/file_sync_service_compaction_test` ×3, `data_providers/database_library_provider_test`,
`tools/calendar/helpers/calendar_print_pdf_test` ×4 (`opentype_shaper.dll` חסר), `settings/dialogs/change_location_dialog_test`,
`shamor_zachor/shamor_zachor_data_provider_test`. אין כשל חדש.

## אימות התנהגות
התיקון קובע את מצב הטאב ברגע יצירתו; הבדיקה מאמתת בדיוק את המסלול שבו עוברת פתיחה מההיסטוריה
(`OpenedTab.fromBook` → `TextBookTab` → `TextBookInitial.showPageShapeView`). לפני התיקון הספר נפתח
ב-`showPageShapeView: false` ממסך ההיסטוריה; אחריו — לפי ההעדפה השמורה, זהה לפתיחה מהספרייה.
