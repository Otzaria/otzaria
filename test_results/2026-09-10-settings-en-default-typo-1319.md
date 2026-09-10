# issue #1319 — "Use the Lefault" במקום "Use the Default"

תאריך: 2026-09-10 | ענף: `fix/settings-en-default-typo-1319` | בסיס: `upstream/dev` (8c365b5cd) | קומיט אימות: `38b3b29fa`

## הבאג שאומת

באמולטור Android 14 במצב אנגלית, דיאלוג הגדרת הספרייה ← "Target Folder" ← הכפתור מופיע כ-"Use the Lefault"
(נראה במהלך העבודה על #1219). המקור: `settings_en.arb`, המפתח `"השתמש בברירת מחדל"`.

## התיקון

`settings_en.arb`: `"Use the Default"`, ו-`settings_catalogs.g.dart` נוצר מחדש ב-`dart run tool/generate_settings_l10n.dart`.

## בדיקות

| קובץ | מה נבדק |
|---|---|
| `test/settings/l10n/settings_default_button_translation_test.dart` | חדש: הערך האנגלי של המפתח בקטלוג הוא "Use the Default". על הבסיס נכשל ("Use the Lefault"). |

`flutter test test/settings/l10n/`: **142 עברו**. `flutter analyze` נקי.

## אימות ויזואלי

APK debug של הבסיס ושל הענף על האמולטור במצב אנגלית: הכפתור במקטע תיקיית היעד. הצילומים בענף `pr-screenshots`
(תיקייה `1319`).

## סוויטה מלאה

`flutter test` על הענף (במקביל לאמולטור, לבניית APK ולסוויטה נוספת — עומס גבוה): **12,600 עברו, 23 דולגו, 14 נכשלו**.
תשעת כשלי הבסיס המוכרים (release_packaging, compaction ×3, personal_notes_file_backed_book, search_scope_menu,
change_location_dialog, shamor_zachor, database_library_provider) + חמישה רגישי-עומס שעברו בבידוד:
`text_book_bloc_test` (53 עברו לבד), `hebrew_book_download_test`, `calendar_dialogs_test`, `my_update_widget_test`.
