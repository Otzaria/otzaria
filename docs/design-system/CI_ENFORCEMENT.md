# אכיפה ב־CI

> המטרה: לזהות חריגה מהתקן ([DESIGN_SYSTEM.md](DESIGN_SYSTEM.md)) לפני מיזוג, בלי לחסום שימושים לגיטימיים ובלי להכשיל את ה־CI על חוב ישן. ההכרעות שמאחורי המנגנון: DD-22 (golden) ו־DD-23 (המנוע והתוויות) ב־[DESIGN_DECISIONS.md](DESIGN_DECISIONS.md).
> **מצב (18.11.2026, אחרי סבב ההשלמה וההכרעות):** המנוע `tool/ui_lint` פועל עם 35 כללים חוסמים ועוד כלל מועמד אחד בדוח בלבד (§3.8). כללים חוסמים נבדקים מול baseline, ורמת Strict (§6) נועלת כלל שהחוב שלו נגמר. כל כלל עבר בדיקת מוטציה על קובץ אמיתי ב־`lib`; מה שהיא לא תופסת מפורט ב־§8. golden tests רצים על Windows (12 משפחות, §5), ו־`responsive_ui` בודק פריסה (§10). המספרים בבלוק הבא נבדקים אוטומטית מול הכלי (`ci_enforcement_catalog_test`), כך שהם לא יתיישנו:

<!-- ui-lint-status -->
- baseline: 565
- rules: 35
- strict: 24
- allows: 47
- path-exclusions: 40
- pending: 1
<!-- /ui-lint-status -->

> **שער ה־lint חוסם בכל PR, גם בלי `run-ci`:** `dart tool/ui_lint_cli.dart --check` ו־`dart test` לארבע בדיקות העיצוב רצים ב־job ‏`Analyze` (§1). **מה לא חוסם בפועל: ב־`dev` וב־`main` אין branch protection ואין ruleset, ולכן אף check אינו required** (נבדק ב־17.11 עם `gh api`, §9). מיזוג ידני של מי שיש לו הרשאת כתיבה לא נחסם, ורק ה־Automerge דורש `CI result`. הבקשה להגדרות למתחזק ב־§9. התוויות `ui-baseline`, `goldens-approved`, `run-ci` ו־`automerge` קיימות.

## 1. איך זה רץ היום

| רכיב | מה הוא עושה | איפה |
|---|---|---|
| `flutter analyze` | `flutter_lints` | job ‏`analyze` ב־`.github/workflows/flutter_tests.yml` |
| **שער ה־lint (חוסם בכל PR, גם בלי `run-ci`)** | `dart tool/ui_lint_cli.dart --check`: יציאה 1 על חריגה חדשה בכלל חוסם או נעול, baseline מת, הערת allow פגומה או חריגה מ־`max_allows`. אחריו `dart test` ל־`ui_lint_test`, ‏`ui_lint_pending_test`, ‏`ui_lint_scan_dirs_test`, ‏`agent_docs_paths_test`, ‏`import_cycles_test`, ‏`ci_enforcement_catalog_test` (בלי Flutter, כדקה) | step־ים ‏"UI lint gate" ו־"UI design tests" ב־job ‏`analyze` |
| **דוח עיצוב** | `tool/ci/design_report.dart` מפיק Markdown ל־`$GITHUB_STEP_SUMMARY`: חריגות לפי כלל עם הפרש baseline מול הבסיס (`git show` של `origin` base), כללים מועמדים, עשרת המודולים עם החוב הגדול, כשלי responsive (תרחיש, חלון, סוג, פרט, צילום) וכשלי golden, מצב הפלטפורמות מ־`needs`, ופקודות שחזור. שורה ראשונה כשחסרה התווית `run-ci`. אינו חוסם (`continue-on-error`). מקומית: `dart tool/ui_lint_cli.dart --format=md|modules|json` | job ‏`design_report` ב־`flutter_tests.yml`; הקלט מ־artifact ‏`design-lint` של `analyze` |
| בדיקות פריסה (responsive) | `flutter test test/design_system/responsive/`: שכבה מהירה (6 חלונות) בכל PR עם `run-ci`, ושכבה מלאה (`RESPONSIVE_TIER=full`, כ־40 חלונות) כשהשתנה ממשק. כשל נכתב ל־JSON ולצילום (artifact ‏`responsive-failures`). הבדיקות מוחרגות מה־shards | job ‏`responsive_ui`, ובלוח זמנים `responsive_nightly.yml` (§10) |
| golden tests | `flutter test test/goldens/` על Windows. כשל מעלה את `failures/` כ־artifact | job ‏`goldens_windows` ב־`flutter_tests.yml` |
| גידול ב־baseline, החרגות והחלשת האכיפה | מכשיל PR שמוסיף מופעים ל־baseline, מוסיף/מרחיב החרגת נתיב (`path:`) ב־`tool/ui_lint/config.yaml`, מעלה תקרת `max_allows`, מסיר `strict: true` מכלל נעול, או משנה את קוד האכיפה (`tool/ui_lint/rules/**`, ‏`ui_lint.dart`, ‏`ui_lint_cli.dart`, בדיקות ה־lint וה־fixtures, ארבעת ה־workflows של ה־guards), אלא אם יש עליו התווית `ui-baseline` | `.github/workflows/ui_baseline_guard.yml` |
| שינוי ב־golden | מכשיל PR שמשנה קובץ תחת `test/goldens/` (PNG, בדיקה, `skip`, ה־harness וסף ה־comparator), אלא אם יש עליו התווית `goldens-approved` | `.github/workflows/goldens_guard.yml` |
| עדכון golden בלי Windows | `workflow_dispatch` שמצייר מחדש ומעלה את התמונות כ־artifact | `.github/workflows/regenerate_goldens.yml` |
| בדיקות Mac ו־iOS (pf8, הוכרע 18.11, אפשרות ג) | שבועי (cron `0 3 * * 0`, יום ראשון 03:00 UTC) וידני (`workflow_dispatch`); שני jobs על `macos-latest`: `flutter test test/core test/shortcuts test/widgets`, ו־`flutter build ios --debug --no-codesign`. לא חוסם PR. נבדק תחבירית (YAML) בלבד ובבדיקת השומר `test/release/apple_platforms_weekly_workflow_test.dart`; **לא רץ ב־GitHub** | `.github/workflows/apple_platforms_weekly.yml` |
| הסרת אישורים בדחיפה | דחיפה חדשה (לא של הבוט) מסירה את `automerge`. `ui-baseline` מוסרת רק אם הדחיפה נגעה בקבצים שהיא מכסה (baseline, config, כללי ה־lint, בדיקותיהם וה־fixtures, ארבעת ה־workflows של ה־guards), ו־`goldens-approved` רק אם נגעה ב־`test/goldens/` (הכרעת בעל הפרויקט 18.11, אפשרות ב). דחיפה בכוח, או דחיפה שאי אפשר לדעת מה נגעה בה, מסירה הכול וגם את `run-ci`. תיקון בקובץ אחר לא מבטל את האישור. **נבדק רק תחבירית והקטע הורץ מקומית עם `gh` מדומה; לא רץ ב־GitHub.** | `.github/workflows/pr_labels.yml` |
| בדיקות סריקה ישנות | בדיקות שסורקות את `lib/` ולא עברו למנוע (נספח) | `test/**` |
| נגישות, הגדלת טקסט וביצועים | `meetsGuideline` והגדלת טקסט ברכיבים המשותפים (חוסמים), ומדידת ביצועים בלי ספים (מדפיסה בלבד) (§4) | ה־shards של Linux (בלי `test/goldens/` ובלי `test/design_system/responsive/`, שיש להם jobs משלהם) |
| Pre-commit | `dart_pre_commit`, אופציונלי ולא נשמר בגיט. לא נקודת אכיפה | `tool/install_git_hooks.dart` |

גרסת Flutter מוצמדת כליטרל בכל workflow (3.47.7).

## 2. עקרונות
1. **AST עדיף על regex** כשצריך להבין תחביר: שם בנאי, ארגומנט בשם, ערך ליטרלי, מחלקה עוטפת (`extends CustomPainter`) או prefix (`pw.`).
2. **מנוע אחד לכל הכללים.** הקוד ב־`tool/` והבדיקה מייבאת אותו, לפי התקדים של `test_shards`, ‏`plugin_spec_generator` ו־`settings_l10n_generator`.
3. **בלי תלויות חדשות.** `analyzer` כבר תלות dev, ו־`path` ו־`yaml` כבר קיימים.
4. **חוב ישן לא מכשיל.** baseline שיכול רק לקטון.
5. **אין השתקה גורפת.** חריג נכתב על צומת בודד, עם נימוק חובה.
6. **כל כלל נבדק בעצמו.** לכל כלל יש מקרה שחייב להיכשל ומקרה שחייב לעבור, ובדיקה שהסורק אכן מוצא משהו.

## 3. המנוע: `tool/ui_lint/` [מחייב · DD-23 A] · קיים

### 3.1 מבנה
```
tool/ui_lint/
  ui_lint.dart            # API: runUiLint(root, config), ה-baseline וההשוואה
  ast_helpers.dart        # ctorCallsNamed, scopeOf
  rules/                  # קובץ לכל כלל, RecursiveAstVisitor; rules.dart מרשם אותם
  rules/pending_rules.dart # כללים מועמדים, דוח בלבד (§3.8): uiLintPendingRules
  config.yaml             # החרגות לפי נתיב, כל אחת עם reason; strict; max_allows
  baseline.json           # חוב קיים, ממוין, נסקר ב-PR
tool/ui_lint_cli.dart     # dart tool/ui_lint_cli.dart --format=md|github|json|modules | --check | --update-baseline [--allow-growth]
tool/ci/design_report.dart # סיכום ל-$GITHUB_STEP_SUMMARY (§10)
test/design_system/
  ui_lint_test.dart       # חוסם: אין חריגות חדשות, אין baseline מת, allow תקין, canaries, החרגות שמשתיקות
  ui_lint_pending_test.dart # הכללים המועמדים, gateFailures, ו-ui_lint_cli --check בתהליך אמיתי
  ui_lint_scan_dirs_test.dart # תיקיות הסריקה (lib וחבילת תפריט ההקשר) קיימות, ואין בחבילה חריגה בלי החרגה או allow
  ci_enforcement_catalog_test.dart # הקטלוג והמספרים במסמך הזה מול הכלי
  fixtures/               # violating_/clean_/allowed_uil_xxx.dart לכל כלל
```
- המנוע **לא מייבא `package:otzaria`**, ולכן לא מושך Flutter או את מנוע החיפוש.
- הכלי סורק את `lib/` ואת `packages/otzaria_context_menu/lib` (`uiLintScanDirs` ב־`tool/ui_lint/ui_lint.dart`, §8). מעבר AST אחד על כל הקבצים לוקח בערך 8–10 שניות.

### 3.2 זיהוי בנאים ב־AST לא מפוענח (חובה בכל כלל)
ב־AST של `parseString`, שאינו מפוענח, `Foo(...)` בלי `new`/`const` מופיע כ־`MethodInvocation`. לכן כל כלל שמחפש בנאי מבקר **גם**:
- `InstanceCreationExpression`, עבור `new`/`const`;
- `MethodInvocation` עם `target == null` ושם שמתחיל באות גדולה, עבור `Foo(...)`;
- `MethodInvocation` עם `target` שהוא שם מחלקה, עבור `Foo.named(...)` (גם `const Foo.named()`);
- `PrefixedIdentifier`/`MethodInvocation` עם prefix של import, עבור `pw.TextStyle(...)`.

prefix של ייבוא Flutter (`import 'package:flutter/material.dart' as m;`) נמחק ב־`asCtorCall`: ‏`m.AlertDialog(...)` נבדק כמו `AlertDialog(...)`. בלי זה כל כלל, שמדלג על prefix כדי לא לתפוס את `pw.*`, היה עקיף בשורת import אחת. prefix אחר (`pw`) נשאר.

העזר `ctorCallsNamed(unit, {'AlertDialog'})` משמש את כל הכללים. גם `test/widgets/text_painter_direction_test.dart` עובר דרכו. לפני כן היא ביקרה רק `InstanceCreationExpression`, ולכן לא יכלה להיכשל.

### 3.3 קטלוג הכללים

"baseline" הוא מספר המופעים ב־`tool/ui_lint/baseline.json` ב־3.11.2026 (הראשון: כשהכלל נכנס). בכלל שעוד לא מומש: ספירת `git grep` גסה מאותו יום. כל הודעת כלל מציינת את התחליף מהתקן.

| ID | כלל | זיהוי | החרגות מובנות (config) | baseline | שלב · מצב |
|---|---|---|---|---|---|
| UIL-001 | אין `AlertDialog`/`Dialog`/`SimpleDialog`/`CupertinoAlertDialog` (מ־10.11) מחוץ ל־`lib/widgets/dialogs/` | ctor | `lib/widgets/dialogs/**` | 0 (ראשון 18). כל השימושים הוסבו לרכיבי הדיאלוג המשותפים | 1 · **חוסם**, נעול (strict) |
| UIL-002 | אין `TextButton`/`FilledButton`/`OutlinedButton`/`ElevatedButton` מחוץ ל־`lib/widgets/controls/` | ctor (כולל `.icon`/`.tonal`/`.tonalIcon`, ‏`const`, ‏collection-if). ‏`X.styleFrom` אינו בנאי ומותר | `lib/widgets/controls/**`, ‏`app_dropdown_field.dart` | 0. תשעת הכפתורים האחרונים הוסבו (q10 Q7): `ActionButton.inline`, ‏`iconAlignment:`, ‏`ghost`, ‏`neutral`, ‏`AppIconButton`. המופע היחיד (`app_dropdown_field.dart`) מוחרג | 1 · **חוסם**, נעול (`strict`) מהיום הראשון (5.11) |
| UIL-003 | לכל `IconButton` יש `tooltip:` | ctor + named arg | `IconButton.styleFrom` (לא בנאי) | 3 (ראשון 25) | 1 · **חוסם** |
| UIL-004 | אין `Theme.of(…).primaryColor` / `theme.primaryColor` | PropertyAccess | — | 0 (ראשון 5) | 1 · **חוסם**, נעול (strict) |
| UIL-005 | אין `Icons.`/`CupertinoIcons.` | identifier prefix, גם `m.Icons.x` דרך prefix של Flutter | — | 0 | 1 · **חוסם**, נעול (strict) |
| UIL-006 | `RtlIcon` רק לאייקון כיווני שרשום ב־`rtl_icon.dart` (אף פעם לא `OtzariaIcons`), ואין `Transform.flip`/`Transform.scale(scaleX: -n)` שעוטף `Icon` | ctor + ילד + הרשימה ב־`rtl_icon.dart` | `rtl_icon.dart` | 0 | 1 · **חוסם**, נעול (strict) |
| UIL-007 | אין `hoverColor`/`splashColor`/`overlayColor`/`focusColor`/`highlightColor` (השניים האחרונים מ־10.11) מחוץ ל־`lib/theme/` | named arg | ערך מ־`AppSurfaces.*` (למשל `hoverRow`); `hoverColor: Colors.transparent` ב־`ListTile` שיש לו `onTap:` וגם `trailing:` (JX-14). ב־`ListTile` בלי `onTap` אין ריחוף, ולכן `transparent` שם נתפס כקוד מת | 0. ‏`focusColor: Colors.transparent` בכרטיס התוצאה של הכלים הוסר (הכרעת בעל הפרויקט 10.11: להציג פוקוס) | 1 · **חוסם**, נעול (strict) |
| UIL-008 | אין `ScaffoldMessenger`/`SnackBar(` | identifier/ctor | `lib/core/ui_snack.dart` | 0 | 1 · **חוסם**, נעול (strict) |
| UIL-009 | `UiSnack.*` מקבל מחרוזת מקטלוג, גם בארגומנט בשם | ארגומנט ליטרלי, גם בענף של תנאי (`ok ? 'נשמר' : 'נכשל'`) | — | 0 | 1 · **חוסם**, נעול (strict) |
| UIL-010 | אין `textDirection: TextDirection.rtl` ב־`Text`/`Text.rich`/`SelectableText` | ctor + named arg | חלונות `ContentDirectionality` (פסוקים בעברית במצב אנגלית), עם allow (JX-09) | 0 (5 חריגים ב־allow: ארבעת הציטוטים במסך "אודות" ומסך שגיאת האתחול) | 1 · **חוסם**, נעול (strict) |
| UIL-011 | אין `TextField(`/`TextFormField(`/`EditableText(` גולמי | ctor | `rtl_text_field.dart` | 0 | 1 · **חוסם**, נעול (strict) |
| UIL-012 | אין `Card(` גולמי | ctor | `lib/widgets/layout/**` | 0 (ראשון 3). כרטיס הזמן בלוח השנה וכרטיס הארגון בחלון הגיוס הוסבו, וכרטיסי "אודות" עברו ל־`AppCard(tone: inset)` (q10 Q8a) | 2 · **חוסם**, נעול (strict) |
| UIL-013 | אין `CircularProgressIndicator(` מחוץ ל־`lib/widgets/feedback/` | ctor | `ActionButton` | 45. התקדמות מדודה (`value:`) עוד בלי רכיב משותף. ‏`LinearProgressIndicator` מחוץ להיקף (§8) | 2 · **חוסם** |
| UIL-014 | אין `PopupMenuButton`/`showMenu(`/`MenuAnchor` מחוץ ל־`lib/widgets/misc/` ולחבילה | ctor/invocation | `lib/widgets/misc/**` (מערכת התפריטים המשותפת) | 4 (‏`MenuAnchor` בדיאלוג החיפוש, בסינון המאפיינים, בחלון הפרסומת ובתפריט ההקשר של `RtlTextField`) | 2 · **חוסם** |
| UIL-015 | אין `Color(0x…)`/`Color.fromARGB`/`Colors.<hue>`/`CupertinoColors.<hue>` מחוץ ל־`lib/theme/`. ההודעה מפנה לתפקיד: כתום/ענבר → `AppSurfaces.warning*`; ירוק "הצלחה" → `secondaryContainer` (DD-24) | ctor/identifier | רק המקרים של DD-24: תוכן (`CustomPainter` שמצייר תוכן, פלטות, מרקר), ייצוא (`pw.*`, ‏`**/export/**`; ‏`lib/printing/**` נאכף, החרגת הנתיב נמחקה ב־18.11), כרום מערכת ההפעלה (`lib/core/windowing/**`); וגם `Colors.transparent`, ו־`Colors.white`/`black` בתוך `BoxShadow` | 0 (ראשון 22). שלושת האחרונים הוסבו ב־q10 Q4.1–Q4.3 | 3 · **חוסם**, נעול (`strict`) |
| UIL-016 | אין `.withValues(alpha:)`/`.withAlpha(`/`.withOpacity(` על צבע ממשק מחוץ ל־`lib/theme/` | MethodInvocation | `CustomPainter`, ייצוא, כפתורי החלון (`lib/core/windowing`), צבעי CSS של התוכן. צבע בתוך `BoxShadow(...)` נספר ב־UIL-030 | 78 (ראשון 95) | 3 · **חוסם** |
| UIL-017 | **אין `fontSize:` בקוד פיצ'ר (DD-02):** לא ליטרל, ולא `AppTokens.font*` או חשבון עליו (`fontSM - 1`), וגם לא `.apply(fontSizeDelta:/fontSizeFactor:)` ליטרלי. התחליף: `textTheme.<slot>` | named arg ב־`TextStyle`/`copyWith`, ו־`fontSizeDelta:`/`fontSizeFactor:` ב־`.apply(...)` (10.11) | `lib/theme/**`; ‏`pw.TextStyle`; קבצי תוכן הספר (JX-01, JX-19), שבהם הגודל מחושב מהגדרות הקריאה | 153. הראשון היה 144 ליטרלים, ואז הכלל הורחב ל־`AppTokens.font*`. שלוש הכותרות הקטנות 13 בדיאלוג החיפוש ובאיתור ב־allow (DD-14) | 3 · **חוסם** |
| UIL-018 | אין `fontFamily:` ליטרלי (כולל `'Roboto'`) מחוץ ל־`lib/theme/`. רשימת ה־fallback של DD-01 חיה רק ב־`AppThemeData` | named arg עם ליטרל מחרוזת, בכל בנאי | `lib/theme/**`. גופן תוכן דרך `AppFonts.*`, מונוספייס (JX-21) דרך `AppTextStyles.monospaceFamily` | 0 | 2 · **חוסם**, נעול (strict) |
| UIL-019 | **רדיוס רק מהטוקן היחיד (DD-04):** אין `BorderRadius.circular(n)`/`BorderRadiusDirectional.circular(n)`/`Radius.circular(n)` ליטרלי. מותר `AppTokens.radius`/`borderRadiusAll`/`roundedShape` | ctor + ליטרל | `CustomPainter`, ‏`pw.*`. נבדקים גם `StadiumBorder(` ו־`CircleBorder(`, עם החריגים שאושרו (q10 Q13): הגלולה של `BarSplitButton` (`bar_split_button.dart`). ‏`CircleBorder` נחסם גם בכפתור אייקון (DD-04, השלמה 19.11); רכיב עגול מטבעו (עיגול צבע, כפתור הדפדוף הצף ב־PDF) ב־allow. `BoxShape.circle` לא נבדק | 0 (ראשון 14). ידיות הגלילה בחצי העובי, מחושב (q10 Q10); גלולת הסינון של תוסף בפינות 8 (q10 Q23) | 3 · **חוסם**, נעול (`strict`) |
| UIL-020 | ריווח ב־`EdgeInsets*`/`SizedBox(width/height)` מהסולם בלבד: 2/4/8/12/16/24/32 (DD-03). ההודעה מציעה את הערך הבא כלפי מעלה (6→8, 10→12, 14→16) | ctor + ליטרל: כל ארגומנט ליטרלי של `EdgeInsets.*`/`EdgeInsetsDirectional.*`, ו־`SizedBox(width/height)`/`SizedBox.square(dimension:)` (10.11) **בלי `child`** וקטן מ־32. **מ־18.11 גם** `spacing:`/`runSpacing:` ב־`Wrap`/`Row`/`Column`/`Flex` ו־`mainAxisSpacing:`/`crossAxisSpacing:` ב־`GridView`/`SliverGrid*` (רכיב גאומטריה כמו `SkeletonLines` לא נתפס), וגם `AppTokens.space*`/`AppTokens.icon*` עם היסט ליטרלי (`spaceSM + 1`): הערך המחושב יוצא מהסולם. כפל לא נתפס. גופן מחושב נתפס ב־UIL-017 | 0, ‏`double.infinity`, ביטוי מחושב וטוקן, `CustomPainter`, ‏`pw.*`, נתיבי הייצוא | 122 (ראשון 146). 10 ערכי `spacing` ו־22 חישובי טוקן תוקנו ב־18.11 (6→8, 9 ו־10→12) והכללים המועמדים UIL-035 ו־UIL-037 התמזגו לכאן | 3 · **חוסם** (off-scale בלבד) |
| UIL-021 | אין `EdgeInsets.only(left/right)`/`fromLTRB`/`Alignment.centerLeft/Right`/`Positioned(left/right)`, וגם לא `Alignment(x, y)` עם x ליטרלי שאינו 0, `BorderRadius.only(topLeft…)`/`horizontal(left/right)` (10.11), ו־`Border(left:/right:)` אסימטרי (18.11; התחליף `BorderDirectional`) | ctor + named arg, ו־`Alignment.*Left/*Right` | `CustomPainter`, ‏`pw.*`, נתיבי הייצוא; ערך סימטרי (JX-20): `fromLTRB(a, b, a, c)`, `only(left: x, right: x)`, `Positioned(left: x, right: x)`, `BorderRadius.only(topLeft: r, topRight: r)`; גאומטריה אחרת עם allow | 42 (ראשון 78). 26 חריגים ב־allow (הידית, חלונית הכלים, `AdaptiveSidePane`, ‏`ContextOverlayPanel`, דיאלוג הדוא"ל). שלושת ה־`Border` הפיזיים הוסבו ל־`BorderDirectional` והכלל המועמד UIL-038 התמזג לכאן | 3 · **חוסם** |
| UIL-022 | אין השוואת רוחב לליטרל ≥100 (`width < 520`). בדיאלוג: `LayoutBreakpoints.compact` (DD-15) | BinaryExpression מול ליטרל ≥100, על `.width`/`.maxWidth`/`.minWidth`, או על משתנה מקומי בשם `width`, `maxWidth`, `minWidth`, `screenWidth`, `availableWidth`, `windowWidth` | קבוע `static const` עם שם בתוך הרכיב, `WindowClass`/`LayoutBreakpoints`, ‏`CustomPainter`. שם מקומי אחר (`tabWidth`) הוא מידה של רכיב ולא נבדק | 0 | 3 · **חוסם**, נעול (`strict`) |
| UIL-023 | אין `Duration(...)` ליטרלי (שאינו 0) ב־`duration:`/`reverseDuration:` של אנימציית ממשק: `Animated*`/`TweenAnimationBuilder`, ‏`AnimationController(...)`, וגלילה מונפשת (`animateTo`, `scrollTo`, `animateToPage`, `nextPage`, `previousPage`, `ensureVisible`), וגם `duration:` שהוא קבוע מקומי המאותחל ב־`Duration(<מספר>)` (18.11). **גלילה לשורה (`scrollToLine`) היא ניווט ולא אנימציית ממשק:** הכלל מחריג אותה, ומי שרוצה קפיצה כותב `Duration.zero` (הכרעה 18.11). התחליף: `AppMotion.duration(context, AppTokens.anim*)`, ובגלילה `AppMotion.scroll`/`scrollPosition` (DD-21) | ctor/method + parent arg | לא־UI (timeouts, debounce, `Future.delayed`, `waitDuration` של Tooltip) לא נתפס, כי הכלל מסתכל רק על הבעלים של `duration:`; `Duration.zero` ו־`AppMotion.duration(...)` מותרים, גם עם `const Duration(...)` בפנים (המשכים 120/180/280 שאין להם טוקן) | 0 (ראשון 33). כל הגלילות עברו ל־`AppMotion.scroll`/`scrollPosition` ו־`ensureVisible` ל־`AppMotion.duration` (q10 Q12). הפיכת דף ב־PDF קיבלה ערך מוגדר, `AppMotion.pageTurn` (500ms), ומשך הסרגל העליון עבר ל־`AppTokens.animNormal`; הכלל המועמד UIL-036 התמזג לכאן | 3 · **חוסם**, נעול (strict) |
| UIL-024 | **רכיב משותף לא מייבא פיצ'ר:** קובץ ב־`lib/widgets/**` לא מייבא ולא מייצא את `lib/settings/engine/`, ‏`lib/settings/settings_exports.dart`, ‏`lib/plugins/`, ‏`lib/tabs/` או `lib/models/`. ‏`settings/l10n` (settingsText) ו־`theme` מותרים. התחליף: הנתון בפרמטר, הצפיפות מ־`AppDensity`, ומה שהפיצ'ר מוסיף דרך scope או ממשק שהפיצ'ר מממש | import/export directive, ‏`package:otzaria/` ויחסי (מנורמל לנתיב) | הכלל חל רק על `lib/widgets/**`; קוד פיצ'ר רשאי לייבא פיצ'ר | 28 (`widgets/commentary`, ‏`smart_text`, תפריטי הקישורים, `ad_popup_dialog`, ‏`phone_report_tab`) | 2 · **חוסם** |
| UIL-025 | אין `compactMenuMode` מתוך `lib/widgets/**`. התחליף: `AppDensity.of(context)` (DD-10) | PropertyAccess | — | 0 | 4 · **חוסם** כי נעול (strict) |
| UIL-026 | אין `MediaQuery.withNoTextScaling`/`TextScaler.noScaling`/`RichText(` גולמי | ctor/invocation | עם allow ונימוק (JX-10) | 0. ‏RichText עם `textScaler:` אינו גולמי; החריג היחיד, טור הסת"ם בתיקון קוראים, ב־allow (JX-10) | 2 · **חוסם**, נעול (strict) |
| UIL-027 | **אין החלטת צבע לפי בהירות בקוד פיצ'ר (הכרעת בעל הפרויקט 10.11, A):** תנאי על `isDark`/`Brightness.dark` שהענפים שלו צבעים. התחליף: תפקיד מ־`colorScheme` או `AppSurfaces`, שכבר שונה בין בהיר לכהה | `isDark ? X : Y`, ‏`if/else` שכל ענף מחזיר או מציב צבע, ו־`switch` על `Brightness.dark`. צבע: `Color(...)`, ‏`Colors.*`, תפקיד של `cs`/`colorScheme`, ‏`AppSurfaces.*`/`AppColors.*`, ו־`.withValues` עליהם. תנאי שאינו בוחר צבע (סרגל המערכת, שם קובץ, זרע הערכה, גשר התוספים) לא נתפס | `lib/theme/**`, ‏`lib/core/windowing/**` (JX-06), ‏`pdf_color_filter.dart` (JX-05), ‏`CustomPainter` | 3 (10.11): שדות המילוי בדיווח על טעות (2) ובעורך התיקון. במדידה: 15 התאמות; 9 בשכבת הטוקנים, 5 בכפתורי החלון ובנייר ה־PDF (החלטות צבע אמיתיות, פטורות כמו ב־UIL-015), ו־3 בפיצ'ר. התראות שווא: 0 | 3 · **חוסם** |
| UIL-028 | **פתיחת דיאלוג גולמי (DD-23):** `showDialog(`, ‏`showAdaptiveDialog(`, ‏`showCupertinoDialog(` ו־`showGeneralDialog(`, גם עם prefix של ייבוא Flutter (`m.showDialog`), רק דרך `showDialogUntilTornDown`/`settingsDialogBuilder` והעזרים שעוטפים אותם | invocation | `lib/widgets/dialogs/**` | 0 (ראשון 54; showDialog שה־builder שלו אינו settingsDialogBuilder). הצורות העוקפות מ־17.11: 0 שימושים | 3 · **חוסם**, נעול (`strict`) מ־18.11, אחרי שעשרת הקבצים האחרונים עברו ל־`showDialogUntilTornDown` (הכרעת בעל הפרויקט 10.11, A). מחליף את הסריקה של `settings_dialog_scope_test` |
| UIL-029 | **גודל אייקון מטוקן (DD-03):** אין `size:` ליטרלי ב־`Icon(`/`IconThemeData(`, אין `iconSize:` ליטרלי, ואין `AppTokens.font*` כגודל אייקון. התחליף: `AppTokens.icon*` | ctor + named arg: `size:` ב־`Icon`/`RtlIcon`/`ImageIcon`/`IconThemeData`, ו־`iconSize:` בכל מקום | `CustomPainter`, ‏`pw.*`, ייצוא, מעבדי תוכן (`smart_text`, `reader_line`, JX-19); ביטוי מחושב | 84 (ראשון 223). ‏`IconThemeData(size:)` נוסף ב־10.11. ביטוי מחושב על `AppTokens.icon*` בכלל המועמד UIL-037 | 3 · **חוסם** |
| UIL-030 | **הגבהה וצל מהטוקנים (DD-12):** `elevation:` רק `0` או `AppTokens.elevation*`, ואין `BoxShadow(` מחוץ ל־`lib/theme/` | named arg + ctor | נייר PDF (JX-05), `CustomPainter`, גובה גאוגרפי שאינו ארגומנט של Widget (JX-16) | 3 `BoxShadow`: אנימציות הדגשה. שני צללי הנייר של עמוד PDF ב־allow כתוכן (JX-05, q10 Q11). הגבהה ליטרלית: 0. שקיפות בתוך `BoxShadow` נספרת כאן ולא ב־UIL-016 | 3 · **חוסם** |
| UIL-032 | **בחירת טקסט עם תפריט אוצריא (issue #1590):** אין `SelectableText`/`SelectableText.rich`, ואין `SelectionArea`/`SelectableRegion` בלי `contextMenuBuilder:`. התחליף: `Text` בתוך `AppSelectionArea` | ctor + named arg של הבנאי עצמו (לא חלון שורות) | — (`AppSelectionArea` עצמו מעביר `contextMenuBuilder`) | 0. הועבר מ־`default_context_menu_scan_test` (10.11) | 1 · **חוסם**, נעול (`strict`) |
| UIL-033 | **רכיב שיוצא משימוש (REQ A-40):** הרשימה ב־`DeprecatedComponentRule.replacements`. היום רק `CustomSwitch`, שהוסר עם `switchTheme` (DESIGN_SYSTEM §3.3); הכלל שומר שלא יחזור. התחליף: `SettingsSwitchTile`, ‏`AppTogglePill`, או `Switch` | ctor | — | 0 (ראשון 1, 10.11) | 2 · **חוסם**, נעול (strict) |
| UIL-031 | **פס גלילה רק דרך `AppScrollbar` (הכרעת בעל הפרויקט 4.11):** אין `Scrollbar(`/`RawScrollbar(`/`CupertinoScrollbar(` גולמי. פס גולמי קובע את הצד לפי הכיוון (שמאל בעברית) ומצויר מעל התוכן | ctor | `lib/widgets/feedback/app_scrollbar.dart` (הרכיב עצמו). פס אופקי ב־allow | 0. שמונת הפסים האנכיים הוסבו ל־`AppScrollbar`; שני הפסים האופקיים (תצוגת הטקסט בהגדרות החיפוש, תיקון קוראים) ב־allow | 2 · **חוסם**, נעול (`strict`) |
| UIL-039 | **רכיב אסור (DESIGN_SYSTEM §3.3, הכרעות 18.11):** `SliderTheme` מקומי (התחליף `SettingsSliderTile`), `AppBar`/`SliverAppBar` (`AppTopBar`), `DropdownButton`/`DropdownButtonFormField` (`AppDropdownField`), `SegmentedButton`/`ToggleButtons` (`AppSegmentedControl`), `FloatingActionButton`, גיליון תחתון (`showModalBottomSheet`, ‏`showBottomSheet`, ‏`BottomSheet`, ‏`DraggableScrollableSheet`) ורכיבי `Cupertino*`. מה שיש לו כלל משלו לא נספר פעמיים: `CupertinoAlertDialog` ב־UIL-001, ‏`CupertinoScrollbar` ב־UIL-031 | ctor/invocation, גם עם prefix של ייבוא Flutter | `lib/widgets/controls/segmented_control.dart` (`AppSegmentedControl` עצמו עוטף `SegmentedButton`) | 0. הייתה חריגה אחת (המחוון המקומי במסך ההדפסה), שהוסרה עם המעבר ל־`SettingsSliderTile`. גיליון תחתון: 0 שימושים (נבדק 18.11) | 2 · **חוסם**, נעול (`strict`) |
| UIL-040 | **יישור טקסט פיזי בכרום (הכרעת בעל הפרויקט 18.11):** אין `TextAlign.left`/`TextAlign.right`. התחליף: `TextAlign.start`/`TextAlign.end`, כי בעברית ימין ושמאל הפוכים ובמצב אנגלית הכרום מתהפך | PrefixedIdentifier `TextAlign.left/right` (`pw.TextAlign` לא נתפס) | תוכן הספר: `reader_line/**`, ‏`smart_text/**`, ‏`plugin_correction_paragraph.dart`. ערך LTR מטבעו (שדה כתובת) ב־allow (JX-09) | 0. 25 מקומות בכרום הוסבו ל־`start` (זהה בעברית), ושדה כתובת הקישור בהערות ב־allow אחד | 3 · **חוסם**, נעול (`strict`) |

**כלל חדש לא נכנס לשלב 1** אם שיעור ההתראות השגויות שלו בהרצה ראשונה גבוה מ־10%. כלל כזה נשאר בדוח עד שהוא משתפר.

### 3.4 Baseline
```json
{ "version": 1,
  "rules": { "UIL-001": { "lib/foo/view/bar_dialog.dart": [
      {"scope": "_BarDialogState._confirm", "fp": "9f2c1a7e", "n": 1} ] } } }
```
- **המפתח:** כלל + קובץ + `scope` (מחלקה.מתודה מתוך ה־AST) + `fp` (hash של קוד הצומת המנורמל). אין מספרי שורות. כלל שמדווח על בנאי עם תוכן גדול (UIL-001 דיאלוג, UIL-003 `IconButton`) מחשב את `fp` משם הבנאי בלבד, כדי ששינוי בתוכן הדיאלוג לא יהפוך אותו לחריגה חדשה. הוספת בנאי כזה באותו `scope` עדיין נתפסת דרך `n`.
- **ספירה:** `n` סופר מופעים זהים.
- **הזזת קוד ופורמט** לא שוברים את ה־baseline. שינוי הביטוי עצמו כן: מי שנגע בשורה מתקן אותה.
- **חריגה שאינה ב־baseline** מכשילה את הבדיקה: "חריגה חדשה".
- **רשומה שלא נוצלה** מכשילה את הבדיקה: "baseline מת — הרץ `--update-baseline`". זה ה־ratchet.
- **`--update-baseline`** רק מוחק רשומות. הוספה דורשת `--allow-growth`.
- **`ui_baseline_guard.yml`** מכשיל PR שמוסיף מופעים לכלל באותו קובץ ובאותו `scope`, אלא אם יש עליו התווית **`ui-baseline`** (DD-23), שמתחזק מוסיף. ההשוואה היא לפי כלל, קובץ ו־`scope`, בלי `fp`, כך ששינוי ביטוי או גרסת מנוע אינם נספרים כגידול. כשב־base אין `baseline.json` בכלל, ה־PR הוא זה שמכניס את ui_lint, ואין מול מה למדוד גידול. לכן ה־guard עובר.
- **החרגת נתיב** חדשה או מורחבת ב־`config.yaml` משתיקה חריגות בלי רשומת baseline, ולכן אותו guard מכשיל גם אותה בלי התווית `ui-baseline`: כל שורת `path:` שנוספה או שונתה מול הבסיס (git diff). הזזת שורה בלי שינוי נספרת גם היא (התרעת שווא נדירה). PR שמכניס כלל חדש עם החרגות צריך את התווית.
- **העלאת `max_allows`** (§3.5) מכשילה את אותו guard בלי התווית `ui-baseline` (הכרעת בעל הפרויקט 10.11.2026): כל כלל שהתקרה שלו ב־PR גבוהה מזו שב־base, כשכלל שלא מופיע הוא 0. כשב־base אין `max_allows` בכלל, ה־PR הוא זה שמכניס את התקרות, ואין מה להשוות.
- **מה חוסם:** `ui_lint_cli --check` (בכל PR, ב־job ‏`analyze`) ו־`ui_lint_test` (גם ב־shards) מכשילים חריגה חדשה בכל כלל שהשלב שלו (`UiLintRule.stage`) עד `blockingStage` (היום 3), ובכל כלל נעול (`strict`) בכל שלב. 34 מ־35 הכללים בשלבים 1–3. בשלב 4: ‏UIL-025, שחוסם כי הוא נעול. baseline מת והערת allow פגומה מכשילים בכל כלל. הכללים המועמדים (§3.8) אינם נכנסים לבדיקה הזו.
- הקובץ נשמר עם סוף שורה LF (`.gitattributes`), כי הבדיקה משווה אותו לפלט של הכלי בייט בבייט.

### 3.5 חריגים מתועדים
**inline**, על הצומת הבא בלבד:
```dart
// ui-lint: allow UIL-015 — צבעי המותג של מפרט הייצוא של Hebcal
const _hebcalBlue = Color(0xFF1565C0);
```
1. כלל **אחד** בכל הערה. אין `all`, אין רשימה ואין wildcard.
2. נימוק אחרי `—` או `--`, באורך 12 תווים לפחות. רצוי לציין את ה־DD או ה־JX שמתיר אותו.
3. אין צורה של "כל הקובץ".
4. הערת allow שלא השתיקה כלום מכשילה את הבדיקה.
5. כל ה־allow מופיעים בדוח עם הנימוק. היום (18.11) יש 47 בקוד, מהם 26 של UIL-021. הוספת allow אינה דורשת תווית: היא גלויה ב־diff ונסקרת כקוד.
6. **תקרה לכל כלל (`max_allows` ב־`config.yaml`, 10.11):** מספר הערות ה־allow של כל כלל ב־lib, וכלל שלא מופיע שם: 0. ‏`ui_lint_test` נכשל כשיש יותר הערות מהתקרה, וגם כשיש פחות (להוריד את התקרה, כמו baseline מת). כך כל allow חדש מעלה מספר ב־`config.yaml` שנראה ב־diff, ו־`ui_baseline_guard` דורש עליו את התווית `ui-baseline` (§3.4). הדוח מציג `allow/תקרה` לכל כלל. **לא מומש:** שדות בעלים ומעקב (issue) לכל החרגה. היום החרגה נושאת נימוק בלבד, והבעלות היא של מי שאישר את ה־PR.

**לפי נתיב או הקשר:** רק ב־`config.yaml`, ותמיד עם `reason:` (היום 40 החרגות, ועוד שתיים גלובליות לקוד שנוצר). החרגות נתיב קיימות גם בחבילות הנסרקות (`packages/otzaria_context_menu/lib/src/...`, שש החרגות, כל אחת רק בכלל ובקובץ שהיא מצדיקה). שם נרשמים גם עוטפים מורשים, כמו `RtlTextField` שבונה `TextField`. החרגה בלי `reason` היא שגיאת קונפיגורציה. **כל החרגת נתיב חייבת להשתיק לפחות ממצא אחד** (`ui_lint_test`: "כל החרגת נתיב משתיקה לפחות ממצא אחד"): החרגה שלא משתיקה כלום מסתירה חריגה עתידית בלי סיבה, ולכן נמחקת. היוצאות מן הכלל, בכוונה: `lib/theme/**` ב־UIL-021/023/029 (מדיניות "שכבת הטוקנים פטורה", שנבדקת ב"שכבת הטוקנים פטורה מכללי הטוקנים"). החרגות הנתיב של `lib/printing/**` (UIL-015/017/029/030) נמחקו ב־18.11: 13 חריגות במסך ההדפסה תוקנו, ואחריהן אף אחת מהן לא השתיקה דבר (קוד הנייר משתמש ב־`pw.*`, שפטור ממילא).

### 3.6 מה לא חוסמים
| הקשר | נימוק |
|---|---|
| `lib/theme/**` | שכבת הטוקנים |
| `extends CustomPainter`, ‏`paint(Canvas…)` | גאומטריה וצבע של ציור תוכן |
| `pw.*`, ‏`lib/tools/tikkun_korim/export/**`, `calendar_print_helpers.dart` (מסך ההדפסה עצמו, `lib/printing/**`, נאכף) | פלט נייר |
| קבצי תוכן הקריאה: `reader_line/**`, `smart_text/**`, `continuous_reading_paragraph.dart`, `commentary_list_base.dart` (חלקי תוכן), `links_list_view.dart` (גדלים יחסיים) | טיפוגרפיה לפי הגדרות המשתמש (DD-02 מתיר `fontSize` רק כאן וב־Theme) |
| `lib/plugins/utils/fluent_icon_resolver.dart`, `*.g.dart` | קוד שנוצר אוטומטית |
| `app_seed_colors.dart`, `calendar_event_colors.dart`, מרקר | פלטות תוכן |
| `lib/core/windowing/**` (כפתורי חלון, כולל `CaptionButtonColors`) | חיקוי של מערכת ההפעלה |
| `lib/pdf_book/utils/pdf_color_filter.dart`, ‏`lib/widgets/misc/app_cursors.dart` (UIL-015) | נייר ומסנן ההיפוך של עמוד PDF; ציור תמונת סמן העכבר |
| צבע בתוך `BoxShadow(color:)` | נספר ב־UIL-030 ולא ב־UIL-015/016. צל חדש עובר דרך `AppShadows` (DD-12) |

### 3.7 חריגים מוצדקים ברמת מדיניות (JX)
המזהים האלה מופיעים בנימוקים של `config.yaml` ושל הערות allow.

| ID | כלל | היקף | נימוק |
|---|---|---|---|
| JX-01 | גודל גופן | טיפוגרפיית תוכן הספר והמפרשים (`reader_line`, הקוראים, `smart_text`, `commentary`, קטעי תוצאות) | הגדרות הקריאה של המשתמש הן תוכן, לא כרום |
| JX-02 | צבע קשיח | מצייני מקום שקופים ב־`continuous_reading_paragraph.dart`, מפענחי צבעי CSS | צבעי סימון הספר הם תוכן |
| JX-03 | הכול | ייצוא PDF והדפסה (`pw.*`, ייצוא תיקון קוראים ולוח השנה). מסך ההדפסה עצמו נאכף כרגיל | פלט נייר, תמיד בהיר |
| JX-04 | שקיפות, צבע, גאומטריה | `CustomPainter`: דפדוף וכריכה ב־PDF, פס הבחירה, רקע הלשוניות, מפריד צורת הדף | הצללה וגאומטריה של ציור, נגזרות מה־`colorScheme` |
| JX-05 | צבע קשיח, צל | נייר עמוד ה־PDF: צל הדף, `pdf_color_filter.dart`, התמונות הממוזערות | צבע הנייר וצלו חייבים להתאים לצילומי העמוד |
| JX-06 | שקיפות | כפתורי החלון ב־`custom_title_bar.dart` | חיקוי כפתורי Windows 11 |
| JX-07 | צבע קשיח | `ShaderMask` ב־`tab_visuals.dart` | מסכת דהייה, לא צבע |
| JX-08 | הכול | `lib/core/windowing/tab_drag_preview.dart` | תמונה שמצוירת מחוץ ל־Flutter |
| JX-09 | `TextDirection.rtl` על טקסט | מדידות `TextPainter`, פסוקים בעברית במצב אנגלית, תיקון קוראים, LTR לנתיבים ומזהים | כיוון של תוכן שאינו תלוי בשפת הכרום |
| JX-10 | `MediaQuery` / הגדלת טקסט | מילוי הבחירה, הערכת גובה הקריאה, מסך תיקון הקוראים | מכבדים את הגדרות הנגישות או מודדים לפריסה |
| JX-11 | גאומטריה ליטרלית | מדדי `SettingsCard`, גובה עמודות לפי textScaler, חישובי איתור מקורות, טווחי הגדרות הקריאה | מדדי פריסה מחושבים, לא טוקני סגנון |
| JX-12 | צבע קשיח | פלטות `lib/theme/**` | שכבת הטוקנים היא המקור היחיד לערכי צבע |
| JX-13 | שקיפות | שקיפות בתוך `BoxShadow` ושכבות מבניות (זוהר הזזה, כיסוי חגיגת הסיום, צל גרירה) | צללים ושכבות מבניות |
| JX-14 | צבע ריחוף | `hoverColor: Colors.transparent` ב־`ListTile` עם `onTap` וכפתורים ב־`trailing` | כדי שהריחוף של השורה לא יתחרה בכפתורים |
| JX-15 | הכול | `fluent_icon_resolver.dart`, ‏`**/*.g.dart` | קוד שנוצר אוטומטית |
| JX-16 | הגבהה ליטרלית | `zmanim_helpers.dart`, ‏`plugin_bridge_adapter.dart` | גובה גאוגרפי במטרים, לא הגבהה |
| JX-17 | הכול | `lib/core/diagnostics/frame_stats_overlay.dart` | שכבת אבחון למפתחים |
| JX-18 | צבע קשיח | צבעי תוכן של המשתמש ושל תוספים (הדגשת הערה, צבעי תפריט ההקשר של תוסף, צבעי אירועים) | צבעים שנשמרו או הגיעו מתוסף |
| JX-19 | גודל גופן, צבע קשיח | מעבדי התוכן של תיקון קוראים (`stam_*`, `tikkun_render_metrics.dart`, `markers_column.dart`) | כל הגדלים הם `metrics.em(...)` של הכתב |
| JX-20 | כיוון פיזי | `fromLTRB`/`only` סימטריים | ערך סימטרי לא תלוי כיוון |
| JX-21 | גופן ליטרלי | בלוק ה־JSON המונוספייס ב־`app_info_dialog.dart` | תוכן דמוי קוד |
| JX-22 | גופן ליטרלי | מדידת `TextPainter` ב־`packages/otzaria_context_menu` | המדידה חייבת להתאים לציור; דרך קבוע גופן אחד |

### 3.8 כללים מועמדים (דוח בלבד)
כלל כאן מוצא חוב אמיתי ב־`lib/`, ולכן אי־אפשר להפעיל אותו כחוסם בלי להגדיל את ה־baseline, וזה דורש את התווית `ui-baseline` של המתחזק. הוא נמצא ב־`uiLintPendingRules` (`rules/pending_rules.dart`), מדווח כמספר ב־`--format=md`/`json` ובדוח העיצוב (§10), ו**אינו חוסם** ואינו נכנס ל־baseline: `--check` ו־`ui_lint_test` מתעלמים ממנו. אין הערת allow לכלל כזה. כשהחוב של כלל מתאפס, מעבירים אותו ל־`uiLintRules` (נעול), ואם הוא מרחיב כלל קיים מאחדים אותו איתו.

| ID | מה | מרחיב | התאמות (18.11) |
|---|---|---|---|
| UIL-034 | `IconButton` גולמי (כולל `.filled`/`.filledTonal`/`.outlined`) מחוץ ל־`lib/widgets`. התחליף: `AppIconButton`. ‏`IconButton.styleFrom` אינו כפתור | חדש | 70 |

**UIL-034 נשאר בדוח** (הכרעת בעל הפרויקט 18.11, 49 Q1 ב): לא נועלים בחריגות מותרות, וגם לא ממירים עכשיו את הכפתורים. הכלל ייכנס נעול, בלי חריגות, כשההמרה תסתיים. היום 70 מקומות (74 ב־17.11; 10 כפתורים צבועים עברו ל־`AppIconButton(fill:)` בעבודת הרכיבים). עד אז אין אכיפה, ואפשר להוסיף כפתור גולמי.

**מה שהיה כאן ועבר לכללים חוסמים ב־18.11** (תוקן עד 0 התאמות לפני המעבר): UIL-035 (`spacing:`) ו־UIL-037 (טוקן + היסט) התמזגו ל־UIL-020; UIL-038 (`Border(left/right)`) ל־UIL-021; UIL-036 (קבוע מקומי כמשך אנימציה) ל־UIL-023, כשגלילה לשורה מוחרגת מהכלל כניווט. נכנסו גם UIL-039 (רכיבים אסורים, כולל גיליון תחתון) ו־UIL-040 (`TextAlign.left/right`).

מה שנבדק ונדחה: `DialogRoute`/`RawDialogRoute` ל־UIL-001 (שימוש מכוון אחד ב־`plugin_confirmation_dialog.dart`, לכן אין 0 התראות שגויות).

## 4. בדיקות חוזה (Contract tests)

לכל רכיב משותף שמשנים, כותבים קודם בדיקת widget שמקבעת את החוזה. הבדיקות הקיימות ב־`test/design_system/contracts/`:
- `theme_contract_test.dart`: ערכת הנושא וה־component themes.
- `components_contract_test.dart`: `AppCard` (כולל `tone: inset`), `MetaChip`, `AppSectionLabel`, `BarButton`, מצבי המשוב, `SquareIconButton`, וצורת כפתור האייקון: פינות 8, שקוף ועם רקע משלו (DD-04).
- `app_dialog_contract_test.dart`, `dialog_frames_contract_test.dart`, `golden_details_contract_test.dart`: משפחות הדיאלוג, הגדלים, הגובה עד 85%, ה־X והתג לפי הגודל, ומתחת ל־600.
- `dialog_keyboard_contract_test.dart`: Enter לפי הפוקוס, Escape ו־`isDirty`.
- `accessibility_contract_test.dart`: Semantics של נבחר ומורחב, tooltip והכרזת `UiSnack`.
- `text_scale_contract_test.dart`: 14 רכיבים משותפים בהגדלה 1.0, ‏1.3 ו־2.0, בלי גלישה, והתווית שלמה.
- מחוץ לתיקייה: `test/design_system/a11y_guidelines_test.dart` (‏`meetsGuideline`), ובדיקות לרכיבים החדשים: `test/widgets/controls/status_chip_test.dart`, ‏`test/widgets/lists/tree_section_header_test.dart`.

| נושא | מה נבדק | מצב |
|---|---|---|
| שימוש ב־Theme | רכיב ללא override מקבל את צבעי ה־component theme. שינוי זרע משנה את הרכיב בלי שינוי קוד | קיים (`theme_contract_test`, `components_contract_test`) |
| בהיר/כהה | ניגודיות ≥4.5 לכל זוג טקסט/רקע, בשני מצבי הבהירות ובכל הזרעים | קיים (`test/theme/app_theme_data_test.dart`), ומצבי הבהירות בבדיקות הרכיבים |
| פריסת דיאלוג | `small`/`medium`/`large`/`full`, X ותג לפי הגודל (DD-07), מתחת ל־600 (DD-16) | קיים |
| גלילה | תוכן ארוך נעצר ב־85% וגולל, ושורת הפעולות נשארת | קיים לדיאלוג `large` |
| מקלדת | Escape סוגר. Escape עם dirty שואל. Enter ב־`SelectionDialog` על פריט בוחר אותו. Enter על "ביטול" מבטל (DD-08) | קיים |
| שינוי גודל חלון | רכיב בחלונית צרה בתוך חלון רחב מחליט לפי החלונית | קיים לחלק מהרכיבים (`SkeletonLines`, ידית הפתיחה) |
| צפיפות | החלפת "צפיפות ממשק" מעדכנת סרגל ותפריט בלי rebuild ידני (DD-10) | קיים (`test/theme/app_density_test.dart`) |
| הפחתת תנועה | עם `disableAnimations`, `AppMotion.duration` מחזיר אפס (DD-21) | קיים (`test/theme/app_motion_test.dart`) |
| RTL ומצב אנגלית | פריסה ב־RTL ובמצב האנגלית (`ChromeDirectionality`). חצים לפי כיוון | חלקי |
| שמירת התנהגות | לפני שכתוב, ולפני כל commit פירוק (DD-30): בדיקת characterization. אחרי השכתוב היא עוברת ללא שינוי, או שהשינוי מתועד ב־DD | קיים בפירוקים (למשל `page_shape_layout_characterization_test.dart`) |
| טקסט מוגדל | `TextScaler.linear(1.3)` בלי overflow | קיים לרכיבים המשותפים, גם ב־2.0 (`text_scale_contract_test`). מסכים ודיאלוגים שלמים עוד לא מכוסים |
| נגישות אוטומטית | `meetsGuideline(labeledTapTargetGuideline)` ו־`textContrastGuideline` בכל רכיב, ו־`androidTapTargetGuideline` ברכיבי מגע, בבהיר ובכהה | קיים (`a11y_guidelines_test`), בלי `skip` (נבדק 17.11: אין). רכיבים שעוד לא מכוסים: `BarButton`, ‏`SquareIconButton`, ‏`RtlTextField`, ‏`AppDropdownField`, ‏`AppSegmentedControl`, ‏`NavTreeTile`, ‏`MetaChip` ושורות ההגדרה |
| ביצועים | ארבעה מסלולים חמים: גלילה בקורא, ניווט בתוצאות החיפוש בספר, גלילת רשימת הספרייה, ופתיחת ההגדרות ומעבר בין לשוניות. מונה בניות וזמן `pump` | קיים (`test/perf/design_system_hot_paths_perf_test.dart`), בלי ספים: מדפיס שורות `PERF|` להשוואה בין גרסאות. אינו מחליף מדידה ב־profile |

## 5. Golden tests [מחייב · DD-22 A] · קיים
1. **מיקום:** `test/goldens/<component>/<component>_golden_test.dart`, והתמונות ב־`test/goldens/<component>/goldens/`. ‏`failures/` ב־`.gitignore`.
2. **הרצה:** job ‏`goldens_windows` (‏windows-2025, אותה גרסת Flutter), שמריץ `flutter test test/goldens/` ומעלה את `failures/` כ־artifact. Windows היא פלטפורמת הייחוס.
   - `test/goldens/` מוחרג מ־shards של Linux ב־`tool/ci/test_shards.dart`, עם בדיקה לכך.
   - בתוך הבדיקות: `skip: !Platform.isWindows`, לפי התקדים של `otzaria_icons`.
3. **קונפיגורציה:** `test/goldens/flutter_test_config.dart` טוען גופנים ומתקין comparator, **ואז קורא ל־`root.testExecutable`**. אחרת אתחול המנוע ותיקיית הנתונים הזמנית הולכים לאיבוד, כי Flutter משתמש רק בקובץ הקונפיגורציה הקרוב ביותר.
4. **גופנים:** `test/support/golden_fonts.dart` טוען:
   - **גופן בדיקה לממשק:** Rubik, שנרשם בשם המשפחה שה־textTheme מבקש בפלטפורמת ה־golden. ה־goldens רצים ב־`TargetPlatform.windows`, ולכן השם הוא 'Segoe UI', שהוא גם ראש רשימת ה־fallback. כך גם `visualDensity` והתפריטים הצפופים מחושבים כמו באפליקציה ב־Windows. Segoe UI לא נכנס למאגר (רישיון), ולכן ה־golden לא משחזר אותו, אלא בודק פריסה, ריווח, צבע וצורה. השם כאן הוא בבדיקות בלבד, ואינו סותר את UIL-018.
   - **מגבלה:** טקסט שאין לו `fontFamily` בכלל (`TextSpan`/`RichText` שלא יורשים סגנון, `TextPainter` בציור) מצויר ב־flutter_tester בגופן הבדיקה המובנה (ריבועים), ואי אפשר לכנות אותו מ־Dart. טקסט כזה ברכיב משותף הוא סימן שהוא לא יורש את ה־Theme.
   - `MaterialIcons`, `packages/otzaria_icons/OtzariaIcons`, `packages/fluentui_system_icons/FluentSystemIcons-Regular/-Filled` ו־`FluentSystemIcons-Light`, מתוך `FontManifest.json` של ה־bundle.
5. **דטרמיניזם:** `physicalSize` קבוע ו־`devicePixelRatio = 1`, ‏`EditableText.debugDeterministicCursor = true`, ‏`pumpAndSettle`, זרע קבוע דרך `AppThemeData.createColorScheme`, ו־`debugDisableShadows = false` כשהצל הוא חלק מהבדיקה.
6. **Comparator:** `TolerantGoldenFileComparator` (`test/goldens/golden_harness.dart`), תת־מחלקה של `LocalFileComparator` שמקבלת הבדל של עד 0.05% מהפיקסלים. תמונה בגודל אחר נכשלת תמיד. התמונות בגודל רכיב ולא מסך מלא, כדי שהאחוז יהיה משמעותי. שינוי ריפוד של פיקסל אחד ב־`ActionButton` הוא 0.51% ונכשל. **הסף נשאר 0.05% (DD-22, השלמה 2.11).** בפועל זה 15 עד 115 פיקסלים לפי גודל התמונה (`BarButton` 15, ‏`AppDialog` 115), ושינוי מקומי קטן בתמונה גדולה, כמו נקודת תג של 8×8, יכול לעבור. הצעה לתקרה מוחלטת (`min(0.05%, 12 פיקסלים)`) נדחתה בהכרעת בעל הפרויקט (18.11, 52 א): הסף נשאר 0.05%. **מדידה (18.11):** על מכונת Windows מקומית כל 33 הבדיקות מול תמונות הייחוס נתנו הבדל 0.0 (אפס פיקסלים שונים). ב־GitHub לא נמדד: ריצה עוברת לא רושמת את ההבדל, ו־`failures/` מועלה רק בכשל. למדידה שם צריך להדפיס זמנית `result.diffPercent` ב־`TolerantGoldenFileComparator.compare`. פרט שקטן מהסף, כמו X, תג אייקון או אייקון בכפתור, נבדק בבדיקת widget רגילה (`golden_details_contract_test.dart`), ולא בהידוק הסף.
7. **מטריצה:** pairwise, לא מכפלה מלאה. לכל רכיב: בסיס `light-rtl-wide-1.0`, ‏`dark-rtl-wide-1.0`, ‏`light-rtl-compact-1.0`, ‏`light-rtl-wide-1.3`, ‏`dark-rtl-compact-1.3`, ו־`light-ltr-wide-1.0` רק לכרום שתומך במצב אנגלית. מכפלה מלאה רק לרכיבים המרכזיים. **בפועל (18.11):** בהיר וכהה, RTL, ומשפחות הליבה מכוסות גם בחלון צר ובטקסט ארוך (`AppDialog`, ‏`RtlTextField`, ‏`AppDropdownField`). עוד לא קיימים: הגדלת טקסט 1.3, צפיפות מצומצמת, LTR מלא, hover ו־focus (הם מכוסים ב־assertions ב־contracts וב־responsive, בלי רגרסיה ויזואלית).
8. **מה מכוסה:** `ActionButton` (כל הווריאנטים) ו־`AppDialog` (`twoActions`, `warning`), ומ־10.11 גם `BarButton` (אייקון: רגיל, נבחר, מושבת, קומפקטי; טקסט), `AppCard` (חמשת הגוונים, נבחר, פעיל), `NavTreeTile` (שלוש רמות, מורחב, נבחר, מונה, כותרת משנה), `AppSegmentedControl` (רגיל, עם אייקון, ממלא רוחב), `AppTopBar` (התחלה, מרכז, סוף, מפריד), `MetaChip` (כל הגוונים, קטן) עם `StatusChip`, `AppInfoBanner` (כל הגוונים) ו־`OtzariaEmptyState`/`OtzariaErrorState`. כולם בבהיר ובכהה. **לא נכללו:** `LoadingIndicator` ו־`StatusChip.busy` (אנימציה אינסופית: `pumpAndSettle` לא נעצר, ופריים קבוע תלוי בזמן); `BarButton.icon` עם `label` (התווית ב־`AnimatedDefaultTextStyle` בלי `fontFamily`, ונראית כריבועים, ראו 4 למעלה: ממצא ברכיב). **נוספו ב־18.11 (בהיר, כהה, צר, טקסט ארוך):** `AppDialog` (צר 360, תוכן ארוך, `warning` כהה), ‏`RtlTextField` (ריק עם רמז, מלא, שגיאה, מושבת; חלון צר וטקסט ארוך; טקסט LTR בשדה RTL) ו־`AppDropdownField` (עם ערך, ריק, מושבת; חלון צר וערך ארוך). **מתוכנן,** לפני השינוי החזותי הבא של כל רכיב: `SquareIconButton`, שורות ההגדרה, `ResultCardFrame`, `ItemsListView`, `NavRailItem` ורצועת הכרטיסיות.
9. **עדכון:** `flutter test --update-goldens test/goldens/<component>` על Windows בלבד, עם הגרסה המוצמדת. מי שאין לו Windows מריץ את "Regenerate goldens" (`regenerate_goldens.yml`) ומוריד את ה־artifact. עדכון גרסת Flutter מחדש את כל התמונות באותו PR.
10. **שינוי מכוון מול רגרסיה:**
    - **רגרסיה:** בדיקת golden נכשלת ב־PR שלא שינה אף PNG.
    - **שינוי מכוון:** ה־PR משנה PNG. ‏`goldens_guard.yml` מחייב את התווית **`goldens-approved`** (DD-23), והסוקר בודק את תצוגת ה־diff של GitHub. אותה תווית נדרשת גם לשינוי בקוד שתחת `test/goldens/` בלי PNG (10.11): בדיקה שנמחקה או קיבלה `skip`, ‏`golden_harness.dart` וסף ה־comparator, ‏`flutter_test_config.dart`. כשב־base אין כלום תחת `test/goldens/`, וה־PR רק מוסיף, ה־PR הוא זה שמכניס את התשתית, וה־guard עובר. התמונות נבדקות בסקירה של אותו PR.
    - **אסור** לעדכן golden ב־PR שאינו שינוי ממשק.

## 6. הכנסה בהדרגה

| רמה | מה רץ | חוסם? | מצב |
|---|---|---|---|
| **1. Report** | `design_report.dart` (§10): טבלה ל־`$GITHUB_STEP_SUMMARY`; הכללים המועמדים (§3.8) נשארים ברמה הזו | לא | קיים |
| **2. New violations** | `ui_lint_cli --check` ו־`test/design_system/ui_lint_test.dart` חוסמים חריגה חדשה מול ה־baseline, ו־`ui_baseline_guard.yml` חוסם גידול ב־baseline בלי תווית | כן, לחריגות חדשות | קיים |
| **3. כללי טוקנים** | UIL-015…023, ‏UIL-029, ‏UIL-030, עם ההחרגות של §3.6, כל אחד עם baseline של החוב שלו | כן, לחריגות חדשות | קיים |
| **4. Strict** | כלל שה־baseline שלו התרוקן ננעל, כך שגם `--allow-growth` עם תווית לא יכול להוסיף לו | כן | **קיים:** `strict: true` ב־`config.yaml`. כלל נעול חוסם בכל שלב, ו־`--allow-growth` לא כותב לו רשומות. ‏ui_lint_test דורש strict לכל כלל בלי רשומות baseline, ואוסר רשומות בכלל נעול. נעולים (24): UIL-001, 002, 004, 005, 006, 007, 008, 009, 010, 011, 012, 015, 018, 019, 022, 023, 025, 026, 028, 031, 032, 033, 039, 040 |

**הבדיקות הקיימות** עוברות למנוע אחת אחרי השנייה. כל העברה נעשית ב־commit נפרד, שמוכיח שהכלל החדש מוצא כל מה שהישן מצא, ובנוסף את הצורות שהישן פספס. בדיקות exact-set (`quit_application_call_sites`, ‏`flutter_internal_imports`) נשארות כמות שהן.

## 7. בדיקת הכללים עצמם
לכל כלל ב־`test/design_system/fixtures/`:
- `violating_uil_xxx.dart`: חייב להחזיר בדיוק את השורות המסומנות. זה ה־canary.
- `clean_uil_xxx.dart`: חייב להחזיר 0. כאן נכנסים המקרים הלגיטימיים: ייצוא, painter ועוטף מורשה.
- `allowed_uil_xxx.dart`: allow תקין מחזיר 0. allow בלי נימוק, או allow שלא השתיק כלום, מדווחים (`bad_allows.dart`).
- ב־CI: PR שמכניס חריגה חדשה בקובץ ב־`lib` נכשל עם הודעה בעברית: `path:line`, הקטע, והרכיב או הטוקן שצריך להשתמש בו.
- baseline: הזזת קוד ופורמט לא שוברים אותו, חריגה חדשה נתפסת גם כשהיא זהה לחריגה קיימת, ו־`updated` רק מכווץ.
- golden: הבדיקה "הזזה של פיקסל אחד בריפוד חורגת מהסף" (`test/goldens/action_button/action_button_golden_test.dart`) מראה ש־`goldens_windows` נכשל על שינוי ריפוד בלי עדכון תמונה.
- בדיקות הסריקה שמחוץ למנוע (`agent_docs_paths_test`, ‏`no_scrollable_markdown_test`, הסריקה של `ActionButton.warning` ב־`destructive_button_contract_test`) בודקות גם את עצמן: הסורק מוצא את הצורה האסורה, לא תופס את המותרת, ולא רץ על רשימה ריקה.
- **בדיקת מוטציה (ביקורת 5.11.2026):** לכל כלל הוזרקו 2–7 חריגות מציאותיות (114 בסך הכול) לקובץ אמיתי ב־`lib` (‏`const`, בנאי שמי, `.icon(`, prefix של import, רב־שורתי, בתוך collection-if/for ותנאי), ו־`dart tool/ui_lint_cli.dart --format=json` דיווח עליהן כחדשות; ובנוסף 19 שימושים לגיטימיים שחייבים לעבור. ההזרקה הוחזרה. הממצאים והפערים: §8, והדוח המלא מחוץ למאגר.

## 8. פערים ידועים (ביקורת 5.11.2026)
מה שהאכיפה **לא** תופסת היום. כל פער כאן הוא החלטה מודעת או משימה פתוחה, לא באג נסתר.

נסגרו ב־18.11: `TextAlign.left/right` (UIL-040), רכיבים אסורים וגיליון תחתון (UIL-039), `Border(left:/right:)` (UIL-021), `spacing:` וחישוב על טוקן (UIL-020), קבוע מקומי כמשך אנימציה (UIL-023), והחרגת `lib/printing/**`, וחבילת `packages/otzaria_context_menu`, שנכללה בסריקה (השורה האחרונה בטבלה, היא נשארת שם כתיעוד של מה שנקבע).

נסגרו ב־10.11 (כל אחד עם בדיקת מוטציה על קובץ ב־`lib`): `IconThemeData(size:)` ‏(UIL-029), `apply(fontSizeDelta:/fontSizeFactor:)` ‏(UIL-017), `SizedBox.square(dimension:)` ‏(UIL-020), `Alignment(x, y)` ו־`BorderRadius.only`/`horizontal` ‏(UIL-021), שינוי בקוד ה־golden בלי PNG (`goldens_guard`), תקרת allow (`max_allows`, §3.5), ושלוש בדיקות סריקה מהנספח.

| פער | השפעה | למה לא נסגר |
|---|---|---|
| UIL-027: צבע דרך משתנה | `isDark ? a : b` כש־a ו־b משתנים מסוג `Color`, או `if` שבענף שלו יותר מהצבה אחת, לא נתפסים (AST לא מפוענח) | הזיהוי לפי צורה; חיפוש טיפוסים יחייב analyzer מלא |
| `LinearProgressIndicator` | מחוץ להיקף של UIL-013 | 11 מופעים (10.11); מחכה לרכיב התקדמות מדודה משותף (הכרעת בעל הפרויקט 10.11: להשאיר). `CupertinoAlertDialog` ו־`focusColor`/`highlightColor` נכנסו ל־UIL-001/007 |
| `FractionalOffset(x, y)`, ‏`Alignment(x, y)` עם x ממשתנה | לא נתפסים | נדיר; `Alignment(-1, 0)` ליטרלי ו־`BorderRadius.only`/`horizontal` נסגרו ב־10.11, ו־`Border(left:/right:)` ב־18.11 (UIL-021) |
| הערת allow | אין שדות בעלים ומעקב (issue) לכל החרגה | התקרה (`max_allows`) והתווית על העלאתה קיימות מ־10.11; בעלים ו־issue לא מומשו |
| החלפת חוב באותו `scope` | תיקון חריגה אחת והוספת אחרת באותה מתודה, עם `--allow-growth`, לא נספר כגידול | ה־guard סופר לפי כלל, קובץ ו־`scope` בלי `fp`, כדי ששינוי ביטוי לא ייחשב גידול (§3.4). ה־diff של `baseline.json` עדיין נסקר |
| golden: מה שמחוץ ל־`test/goldens/` | `goldens_guard` (מ־10.11 כל קובץ תחת `test/goldens/`) לא רואה את `test/support/golden_fonts.dart`, את ה־job ‏`goldens_windows` ואת ההחרגה ב־`tool/ci/test_shards.dart` | שינוי בגופנים משנה פיקסלים ואז נכשל או משנה PNG; שינוי ב־workflow נסקר כקוד |
| בדיקות סריקה ישנות (נספח) | regex על שורות, בלי AST, ב־`plugin_icon_resolver_usage_test`, ‏`image_decode_size_test` ו־`pdf_hardcoded_colors_test` | עוברות למנוע אחת אחרי השנייה (§6). ב־10.11: `default_context_menu_scan_test` עבר ל־UIL-032, הסריקה של `settings_dialog_scope_test` ל־UIL-028 החוסם, והסריקות של `Markdown` ושל `ActionButton.warning` עברו ל־AST |
| ייבוא פרטי בין פיצ'רים (REQ A-40) | אין כלל | אין במאגר הגדרה של 'פרטי': אין `src/`, אין קובצי `_*.dart`, ורק ארבעה barrels (`settings`, ‏`text_display`, ‏`theme`, ‏`widgets`). נמדדו (10.11) 2,318 ייבואים ישירים בין פיצ'רים, 147 מהם דרך barrel. כלל יחייב קודם להגדיר API ציבורי לכל פיצ'ר. UIL-024 מכסה את הכיוון החשוב (רכיב משותף → פיצ'ר) |
| ליטרל עברי בכרום (DD-20) | אין כלל | נמדד 10.11: 131 ליטרלים עבריים מוצגים (`Text(...)`, ‏`tooltip:`, ‏`title:` וכו', לא בתוך `settingsText`) בנתיבי הכרום (`lib/settings`, ‏`lib/navigation`, ‏`lib/tour`, ‏`lib/core/windowing`, ‏`lib/widgets`). כ־32 מהם דליפות אמיתיות; השאר מפתחות שמתורגמים בהמשך (`TourStep.title`), תוכן (ציטוטי 'אודות', פרשנים, חלון הגיוס) ודיאלוגים מחוץ לרשימה הסגורה. שיעור השווא כ־75%, הרבה מעל 10% (§3.3), ולכן לא נכנס. מחכה להכרעה |
| הגנת ענף | **אין הגנות** (17.11): ב־`dev` וב־`main` אין branch protection ואין ruleset, ואף check אינו required. הכרעת 10.11 (B) לא מומשה בהגדרות המאגר | הגדרת required היא הגדרה של המאגר, בהרשאת admin. הבקשה למתחזק: §9 |
| `packages/otzaria_context_menu` | **נסרקת (הוכרע 18.11, סעיף 54 Q3).** `uiLintScanDirs` ב־`tool/ui_lint/ui_lint.dart` כולל `lib` ו־`packages/otzaria_context_menu/lib`; בטבלת המצב לפי מודול החבילה היא מודול `otzaria_context_menu`. היו 26 ממצאים ב־11 כללים: 12 תוקנו בקוד (מידות נקראות בשם מ־`menu_visuals.dart`, כי החבילה עצמאית ואינה תלויה ב־`AppTokens`; בלי שינוי חזותי), ו־14 הוחרגו בנתיב עם נימוק, כל חריגה רק בכלל ובקובץ הרלוונטי: UIL-014 ב־`context_menu_rows.dart` (`MenuAnchor` של תפריט ההקשר), UIL-007 ו־UIL-016 ב־`menu_rows.dart` (מצבי hover/לחיצה ושקיפויות M3), UIL-026 ב־`menu_rows.dart` (מדידת רוחב), UIL-021 ב־`context_menu_region.dart` וב־`submenu_button.dart` (מיקום ופתיחת תת־תפריט בקואורדינטות מסך פיזיות). ה־baseline לא גדל; אין הערות allow חדשות. ערכי הצורה הקבועים נשארו כפי שהיו ב־`menu_visuals.dart` (לא נצמדו לסולם האפליקציה, כדי לא לשנות את מראה התפריטים) | הצמדה לסולם (6→8, 14→16 וכו') דורשת אישור חזותי. מי שמוסיף ידית עיצוב לחבילה מוסיף אותה ל־`AppMenuVisuals` או ל־`AppMenuMetrics`, לא ליטרל בבנאי (UIL-017/019/020/023/029/030 נאכפים בה). שינוי בחבילה מפעיל את שכבת ה־responsive המלאה (`packages/otzaria_context_menu/lib/` ב־`uipaths` ב־`flutter_tests.yml`, §10) |

## 9. הגנות הענף והבקשה למתחזק (נבדק ב־17.11.2026)

| בדיקה | תוצאה |
|---|---|
| תוויות | `ui-baseline`, ‏`goldens-approved`, ‏`run-ci`, ‏`automerge` קיימות (בלי תיאור וצבע) |
| `gh api repos/Otzaria/otzaria/rulesets` | `[]` (גם עם `includes_parents=true`) |
| `.../rules/branches/dev` ו־`/main` | `[]`: אין כללים פעילים מאף מקור |
| `.../branches/dev` ו־`/main` | `protected: false`, ‏`required_status_checks: {checks: [], enforcement_level: "off"}` |

**מסקנה:** אין check שהוגדר כ־required. מה שחוסם בפועל הוא ה־Automerge (דורש `CI result` מוצלח ושאף workflow על ה־head לא נכשל), ומיזוג ידני של מי שיש לו הרשאת כתיבה לא נחסם. לא ניתן לדעת מהחשבון שבדק (הרשאת triage): הגדרות ארגון, merge queue, מי מחזיק כתיבה ויכול להוסיף תוויות, והאם "Require approval for fork PR workflows" פעיל.

שני דברים שצריך לדעת לפני שמגדירים required:
- job שמדולג נחשב הצלחה. `Test (shard n/5)` ו־`CI result` מדולגים בלי `run-ci`. לכן שער ה־lint החוסם (§1) רץ ב־`Analyze`, שאינו מאחורי `run-ci`, ולכן `Analyze` הוא ה־check ש**כן** מבטיח שהשער רץ.
- ה־guards נבדקים מקוד ה־PR (`pull_request`), ואין `CODEOWNERS`: PR שמשנה את ה־guard נבדק מול הגרסה המשונה שלו. ההגנה שנוספה ב־`ui_baseline_guard.yml` (קוד האכיפה דורש `ui-baseline`) מקטינה את הסיכון, ולא סוגרת אותו בלי CODEOWNERS.

הבקשה למתחזק (הנוסח המלא נמסר למתחזק בנפרד): ruleset פעיל על `dev` ו־`main` עם PR חובה, required checks (`Analyze`, ‏`ui_lint baseline growth`, ‏`Golden image changes`, ‏`CI result`), חסימת force push ומחיקה, קובץ CODEOWNERS ל־`tool/ui_lint/`, ‏`test/goldens/`, ‏`.github/workflows/`, ‏`docs/design-system/`, ותיאור וצבע לתוויות.

## 10. בדיקות פריסה (responsive) ושכבות ה־CI

תשתית: `test/design_system/responsive/responsive_harness.dart`. ‏`testResponsive` רושם בדיקה לכל חלון במטריצה, ובסוף כל הרצה בודק שאין overflow, שגיאות layout או גלילה אופקית בלתי מכוונת. ‏`expectVisible`, ‏`expectReachable`, ‏`expectInsideViewport`, ‏`expectNoClippedText`, ‏`expectTapTarget`. בכשל נכתבת שורת JSON (`scenario`, ‏`viewport`, ‏`issues`, ‏`screenshot`) ל־`RESPONSIVE_REPORT`, וצילום ל־`RESPONSIVE_SHOTS`.

| שכבה | מה רץ | מתי | חוסם? | איפה |
|---|---|---|---|---|
| **0. מהירה, חוסמת** | `ui_lint_cli --check`, ‏`dart test` לבדיקות העיצוב, `flutter analyze` | כל PR, גם בלי `run-ci` | כן | job ‏`analyze` |
| **1. מהירה, עם `run-ci`** | שכבת ה־quick של ה־responsive (6 חלונות), ה־shards, goldens (Windows), בנייה | PR עם `run-ci` | כן (`CI result`) | `responsive_ui`, ‏`test`, ‏`goldens_windows` |
| **2. מורחבת לשינוי ממשק** | שכבת ה־full (`RESPONSIVE_TIER=full`, כ־40 חלונות, בהיר וכהה, הגדלות 1.3 ו־2.0, צפיפות מצומצמת) | כש־`changes.ui` (קבצי ממשק, ערכה, מסכים, דיאלוגים, `packages/otzaria_context_menu/lib/`, בדיקות העיצוב) | כן (אותו job) | `responsive_ui` |
| **3. כבדה, בלוח זמנים** | ה־full על Linux ועל Windows, ו־goldens על Windows לסטיית גופן ורינדור | `0 2 * * *` מענף ברירת המחדל, ו־`workflow_dispatch` | לא (לא PR) | `responsive_nightly.yml` |
| **4. ידנית, מתועדת** | מגע אמיתי ו־IME, DPI מעורב בין מסכים, גרירת חלון בין צגים, WebView של תוספים, תפריט ליד קצה במערכת אמיתית | לפני גרסה ובשינוי חלונות/מגע | לא | אין אוטומציה אמינה; רשימה ב־PR |

- `test/design_system/responsive/` **מוחרג מה־shards** של Linux (`tool/ci/test_shards.dart`, עם בדיקה), כדי שלא ירוץ פעמיים.
- זמן הריצה של שכבה 2 לא נמדד. ‏`timeout-minutes: 45` ב־`responsive_ui` הוא הערכה; להריץ פעם אחת את `responsive_nightly.yml` ב־`workflow_dispatch` ולהדק (ההרצה מדפיסה את הזמן).
- הדוח (`design_report.dart`) מסכם את כשלי ה־responsive והגולדן, ואת מצב הפלטפורמות. הוא אינו חוסם (`continue-on-error`), כי כשל של workflow על PR מעביר אותו לטיוטה (`auto-draft-failed-ci.yml`).
- כשל ב־`Analyze` (שער ה־lint) מעביר PR לטיוטה כמו כל כשל אחר ב־`Analyze`; הוא ב־`NO_RETRY_JOBS` ולכן לא ירוץ שוב.

## נספח — בדיקות הסריקה הקיימות
| בדיקה | אוכפת | הערה |
|---|---|---|
| ~~`test/widgets/text/bare_text_field_scan_test.dart`~~ | אין `TextField(` גולמי | **הועברה ל־UIL-011**, שתופס גם `TextFormField`/`EditableText` |
| ~~`test/core/messages/uisnack_literal_scan_test.dart`~~ | אין ליטרל בארגומנט הראשון של `UiSnack` | **הועברה ל־UIL-009**, שתופס גם ארגומנט בשם |
| ~~`test/widgets/text/default_context_menu_scan_test.dart`~~ | `SelectionArea` עם `contextMenuBuilder`, אין `SelectableText` | **הועברה ל־UIL-032** (10.11). חלון 15 השורות פספס `contextMenuBuilder` של ווידג'ט מקונן ו־`SelectableText (` עם רווח, ותפס בטעות builder שרחוק יותר מ־15 שורות |
| ~~`test/widgets/rtl_icon_registered_usage_test.dart`~~ | `RtlIcon` רק לאייקונים רשומים | **הועברה ל־UIL-006**, שתופס גם `Transform.flip`/`Transform.scale(scaleX: -n)` סביב אייקון. משתנים עדיין לא נבדקים |
| `test/plugins/utils/plugin_icon_resolver_usage_test.dart` | resolver יחיד | כוללת בדיקה שהסורק אכן מוצא משהו |
| `test/settings/no_scrollable_markdown_test.dart` | `MarkdownBody` | ב־AST דרך `ctorCallsNamed` (10.11): תופסת גם `Markdown (` ו־`md.Markdown(`, ולא הערה. כוללת בדיקה של הסורק עצמו |
| `test/settings/l10n/settings_dialog_scope_test.dart` | `settingsDialogBuilder` | **הסריקה הועברה ל־UIL-028** (חוסם מ־10.11), שחל על כל `lib` ולא רק על `lib/settings`. בדיקות ה־widget של העטיפה נשארות |
| `test/core/windowing/quit_application_call_sites_test.dart` | exact set | נשארת |
| `test/widgets/text_painter_direction_test.dart` | `TextPainter.textDirection` | דרך `ctorCallsNamed` (§3.2), ולכן מוצאת גם `TextPainter(...)` בלי `new` |
| ~~`test/pdf_book/pdf_hardcoded_colors_test.dart`~~ | אין `Colors.<hue>` בשני קבצים | **הועברה ל־UIL-015** |
| `test/utils/ui/image_decode_size_test.dart` | `cacheWidth` | נשארת |
| `test/design_system/contracts/destructive_button_contract_test.dart` (הסריקה) | אין `ActionButton.warning` במסכי ההגדרות | ב־AST דרך `ctorCallsNamed` (10.11): תופסת גם `ActionButton.warning (` ושבירת שורה, ולא הערה |
| `test/design_system/side_pane_specs_test.dart` | טבלת רוחבי חלוניות הצד | ערכים מקובעים, ואיסור על מספרי רוחב בקוד מסך (`minMainContentWidth`, `minPaneWidth`, `maxPaneWidth`, `_kNav*Width`) מחוץ ל־`SidePaneSpecs`. בדיקת `flutter test`, לא כלל ui_lint |
| `test/widgets/adaptive_side_pane_handle_hit_test.dart` | שטח הלחיצה של ידית שינוי הגודל | לחיץ כולו בפריסה הרחבה, בעכבר ובמגע (סעיף 12) |
| `test/widgets/resizable_drag_handle_touch_test.dart` | ידית שינוי הגודל במגע | גלויה במנוחה ובשטח לחיצה 32 (סעיף 12) |
| `test/design_system/agent_docs_paths_test.dart` | כל נתיב ב־`AGENTS.md`, בתבנית ה־PR, ב־`agent_ui_reference.md`, ב־`agent_test_map.md` ובמסמכי התקן קיים | קטע מחוק `~~…~~` מתעד קובץ שהוסר ולא נבדק |
