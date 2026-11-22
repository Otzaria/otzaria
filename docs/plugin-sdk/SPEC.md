# spec.json — מפרט ה-SDK המכונה-קריא

`docs/plugin-sdk/spec.json` הוא הייצוג המכונה-קריא של ממשק התוספים: המתודות,
ההרשאה והגרסה המינימלית של כל אחת, ההרשאות התקפות, האירועים, מדיניות ההגדרות
שתוסף רשאי לקרוא, וערכי `stability` המותרים במניפסט.

עד לגרסה הזו כללי הוולידציה נכתבו שלוש פעמים — כאן, באתר החנות
(`Otzaria_Website`), וב-`otzaria-plugin-validator` — והם סחפו זה מזה. שני
כלי ה-JS גם פרסרו את `API_REFERENCE.md` בזמן אמת, כך שתוסף עבר או נדחה לפי
זמינות הרשת. `spec.json` הוא כעת המקור היחיד לשלושתם.

## מי מייצר, ומתי

הקובץ **מחולל** — אין לערוך אותו ביד:

```bash
dart run tool/plugins/generate_plugin_spec.dart          # כותב
dart run tool/plugins/generate_plugin_spec.dart --check   # רק בודק, יוצא 1 אם מיושן
```

המחולל מייבא את קטלוג שיטות ה-SDK, שהוא Dart טהור ללא תלות ב-Flutter.
את יתר הקבועים הוא קורא מקוד האפליקציה באמצעות AST:

| מקור | מה נלקח |
|---|---|
| `lib/plugins/models/plugin_api_catalog.dart` | שיטות מתועדות ופנימיות, הרשאות הגשר והאריזה, גרסאות מינימום ורמזי הרשאות |
| `lib/plugins/services/plugin_extended_validator.dart` | `_knownEvents`, `_whenConditionMinVersion`, `_headlessMinVersion` |
| `lib/plugins/services/plugin_design_rules.dart` | `designRules`: מילות המפתח המותרות ב-`font-family` ובצבע, הסלקטור של הסרגל העליון, כללי @ שאינם נבדקים, והודעות הכשל של בדיקת העיצוב |
| `lib/plugins/models/plugin_valid_permissions.dart` | `pluginValidPermissions`, `pluginBaselinePermissions`, `pluginLegacyPermissionAliases` |
| `lib/plugins/services/plugin_manifest_validator.dart` | `validStabilityValues` |
| `lib/plugins/services/plugin_settings_access_policy.dart` | `blockedSubstrings` / `blockedPrefixes` / `blockedKeys` |

**הוספת API חדש דורשת רשומה בקטלוג** — הגשר, הוולידטורים והמחולל משתמשים בה.
הרשאת הגשר גוברת במפרט; כשאין כזו, מפורסמת הרשאת האריזה. כך פעולות רשת
ממשיכות לפרסם `network.access` אף שההרשאה בפועל נבדקת לפי היעד.
מפת רמזי ההרשאות חלקית במכוון, ונקבעת בשדה `hasPermissionHint`.
אם שם קבוע משתנה, המחולל נכשל בקול (`PluginSpecError`) ולא מייצר מפרט חסר.

## מה נכשל אם שוכחים

* `test/plugins/plugin_spec_freshness_test.dart` מריץ את המחולל ומשווה לדיסק —
  `spec.json` מיושן מפיל את הבנייה.
* ב-CI (`.github/workflows/flutter_tests.yml`, job `analyze`) רץ
  `generate_plugin_spec.dart --check` לפני `flutter analyze`.

## איך המפרט נצרך

שני מאגרי ה-JS **מצרפים עותק** (vendoring) של הקובץ, ולכן הם מכירים את המשטח
המלא גם בלי רשת; אחזור חי של אותו קובץ נעשה בנוסף ויכול רק **להרחיב** את
המשטח המוכר, לא לצמצם אותו:

| מאגר | העותק המצורף | רענון |
|---|---|---|
| `otzaria-plugin-validator` | `src/spec.json` | `npm run sync:spec` (ו-`npm run test:spec-drift` נכשל על סחיפה) |
| `Otzaria_Website` | `src/lib/pluginSdkSpec.js` | `npm run sync:plugin-spec` |

שני העותקים נמשכים מ-`Otzaria/otzaria@dev`, כלומר **המפרט צריך להיות מקומט
ודחוף לפני שהם מתרעננים**.

## כללי העיצוב (`designRules`)

בדיקת העיצוב ("מראה תואם לאוצריא") קיימת בשני מימושים: ב-Dart
(`PluginExtendedValidator`) ובכל אחד ממאגרי ה-JS. כללי העיצוב עצמם ישבו
בשני המקומות, ולכן סטו. הם נמצאים עכשיו כנתונים ב-`plugin_design_rules.dart`
ומתפרסמים ב-`designRules`: `colorKeywords`, `fontFamilyKeywords`,
`topBarSelectorPattern`, `skippedAtRules` ו-`hints` (הסיומת של הודעת הכשל לכל
סוג). `plugin_design_rules_test.dart` מוודא שהפרסום שווה לקבועים. מאגרי ה-JS
צריכים לקרוא את `designRules` מהעותק המצורף של המפרט במקום לשכפל אותו, ובדיקת
הסחיפה שלהם משווה אותו לעותק החי. שינוי כלל = שינוי בקובץ אחד.

## מדיניות ההגדרות מועברת ככללים, לא כרשימה

מ-0.9.97 `PluginSettingsAccessPolicy` הופכה ל-**blocklist**: כל הגדרה קריאה
למעט מה שחסום. לכן `settings` במפרט מכיל את שלושת הכללים
(`blockedSubstrings`, `blockedPrefixes`, `blockedKeys`) ולא רשימת היתר. שני
כלי ה-JS משחזרים את `isBlocked` בדיוק — אותו סדר, ואותו נירמול
(trim + lowercase). שינוי באלגוריתם עצמו (ולא ברשימות) דורש עדכון
ידני בשני מאגרי ה-JS — המפרט מעביר נתונים, לא קוד.

## מה *לא* במפרט

כללים שאין להם קבוע מקביל באפליקציה נשארים מקומיים לכלי ה-JS ומסומנים שם
כ-`VALIDATOR-LOCAL`, למשל `PERMISSION_MIN_VERSION` (הגרסה שבה הרשאה מוצהרת
נוספה — האפליקציה מכירה רק את גרסתה) ורשימת ה-methods הלא-מתועדים שבתוספים
קיימים. גם כללי הרשת (`network.allowlist`, hosts מקומיים) אינם חלק מהמפרט.
