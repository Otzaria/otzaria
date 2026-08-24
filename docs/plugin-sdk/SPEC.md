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

המחולל קורא את הקבועים מקוד האפליקציה (AST, לא Markdown):

| מקור | מה נלקח |
|---|---|
| `lib/plugins/services/plugin_extended_validator.dart` | `_knownApiMethods`, `_knownUndocumentedMethods`, `_methodRequiredPermission`, `_methodMinVersion`, `_knownEvents`, `_whenConditionMinVersion` |
| `lib/plugins/models/plugin_valid_permissions.dart` | `pluginValidPermissions`, `pluginBaselinePermissions`, `pluginLegacyPermissionAliases` |
| `lib/plugins/bridge/plugin_bridge_handler.dart` | `methodPermissions` (הטבלה הנאכפת בזמן ריצה — גוברת) |
| `lib/plugins/services/plugin_manifest_validator.dart` | `validStabilityValues` |
| `lib/plugins/services/plugin_settings_access_policy.dart` | `blockedSubstrings` / `blockedPrefixes` / `blockedKeys` |

**הוספת API חדש דורשת רק את השורות בקוד** — המחולל אינו מקודד רשימות בעצמו.
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
