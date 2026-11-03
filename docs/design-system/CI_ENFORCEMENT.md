# אכיפה ב־CI

> המטרה: לזהות חריגה מהתקן ([DESIGN_SYSTEM.md](DESIGN_SYSTEM.md)) לפני מיזוג, בלי לחסום שימושים לגיטימיים ובלי להכשיל את ה־CI על חוב ישן. ההכרעות שמאחורי המנגנון: DD-22 (golden) ו־DD-23 (המנוע והתוויות) ב־[DESIGN_DECISIONS.md](DESIGN_DECISIONS.md).
> **מצב (3.11.2026):** המנוע `tool/ui_lint` פועל עם 21 כללים, וכולם חוסמים חריגה חדשה מול baseline. golden tests רצים על Windows. שני guards בודקים גידול ב־baseline ושינוי בתמונות ה־golden. 9 כללים מהקטלוג (§3.3) עוד לא מומשו, ורמת Strict (§6) עוד לא קיימת. ה־workflows לא הורצו עדיין על GitHub.

## 1. איך זה רץ היום

| רכיב | מה הוא עושה | איפה |
|---|---|---|
| `flutter analyze` | `flutter_lints` | job ‏`analyze` ב־`.github/workflows/flutter_tests.yml` |
| **הבדיקה החוסמת** | `test/design_system/ui_lint_test.dart` מריץ את כל הכללים על `lib/`, משווה ל־`tool/ui_lint/baseline.json` ונכשל על חריגה חדשה, על baseline מת ועל הערת allow פגומה | ה־shards של Linux. `tool/ci/test_shards.dart` מכניס אוטומטית כל `*_test.dart` חוץ מ־`test/goldens/` |
| דוח ui_lint | `dart tool/ui_lint_cli.dart --format=github`: טבלה ל־`$GITHUB_STEP_SUMMARY` ו־annotations לחריגות חדשות. `continue-on-error`, כלומר דוח בלבד | step ‏"UI lint report" ב־job ‏`analyze` |
| golden tests | `flutter test test/goldens/` על Windows. כשל מעלה את `failures/` כ־artifact | job ‏`goldens_windows` ב־`flutter_tests.yml` |
| גידול ב־baseline | מכשיל PR שמוסיף מופעים ל־baseline, אלא אם יש עליו התווית `ui-baseline` | `.github/workflows/ui_baseline_guard.yml` |
| שינוי בתמונות golden | מכשיל PR שמשנה PNG תחת `test/goldens/`, אלא אם יש עליו התווית `goldens-approved` | `.github/workflows/goldens_guard.yml` |
| עדכון golden בלי Windows | `workflow_dispatch` שמצייר מחדש ומעלה את התמונות כ־artifact | `.github/workflows/regenerate_goldens.yml` |
| בדיקות סריקה ישנות | בדיקות שסורקות את `lib/` ולא עברו למנוע (נספח) | `test/**` |
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
  config.yaml             # החרגות לפי נתיב, כל אחת עם reason
  baseline.json           # חוב קיים, ממוין, נסקר ב-PR
tool/ui_lint_cli.dart     # dart tool/ui_lint_cli.dart --format=md|github|json [--update-baseline [--allow-growth]]
test/design_system/
  ui_lint_test.dart       # חוסם: אין חריגות חדשות, אין baseline מת, allow תקין, canaries
  fixtures/               # violating_/clean_/allowed_uil_xxx.dart לכל כלל
```
- המנוע **לא מייבא `package:otzaria`**, ולכן לא מושך Flutter או את מנוע החיפוש.
- מעבר AST אחד על כל `lib` לוקח בערך 8–10 שניות.

### 3.2 זיהוי בנאים ב־AST לא מפוענח (חובה בכל כלל)
ב־AST של `parseString`, שאינו מפוענח, `Foo(...)` בלי `new`/`const` מופיע כ־`MethodInvocation`. לכן כל כלל שמחפש בנאי מבקר **גם**:
- `InstanceCreationExpression`, עבור `new`/`const`;
- `MethodInvocation` עם `target == null` ושם שמתחיל באות גדולה, עבור `Foo(...)`;
- `MethodInvocation` עם `target` שהוא שם מחלקה, עבור `Foo.named(...)` (גם `const Foo.named()`);
- `PrefixedIdentifier`/`MethodInvocation` עם prefix של import, עבור `pw.TextStyle(...)`.

העזר `ctorCallsNamed(unit, {'AlertDialog'})` משמש את כל הכללים. גם `test/widgets/text_painter_direction_test.dart` עובר דרכו. לפני כן היא ביקרה רק `InstanceCreationExpression`, ולכן לא יכלה להיכשל.

### 3.3 קטלוג הכללים

"baseline" הוא מספר המופעים ב־`tool/ui_lint/baseline.json` ב־3.11.2026 (הראשון: כשהכלל נכנס). בכלל שעוד לא מומש: ספירת `git grep` גסה מאותו יום. כל הודעת כלל מציינת את התחליף מהתקן.

| ID | כלל | זיהוי | החרגות מובנות (config) | baseline | שלב · מצב |
|---|---|---|---|---|---|
| UIL-001 | אין `AlertDialog`/`Dialog`/`SimpleDialog` מחוץ ל־`lib/widgets/dialogs/` | ctor | `lib/widgets/dialogs/**` | 3 (ראשון 18) | 1 · **חוסם** |
| UIL-002 | אין `TextButton`/`FilledButton`/`OutlinedButton`/`ElevatedButton` מחוץ ל־`lib/widgets/controls/` | ctor (כולל `.icon`/`.tonal`) | `lib/widgets/controls/**`, ‏`app_dropdown_field.dart` | כ־10 | 1 · **לא מומש** (⚠ תשעת הכפתורים שנשארו ממתינים להכרעה, סבב 3.11) |
| UIL-003 | לכל `IconButton` יש `tooltip:` | ctor + named arg | `IconButton.styleFrom` (לא בנאי) | 8 (ראשון 25) | 1 · **חוסם** |
| UIL-004 | אין `Theme.of(…).primaryColor` / `theme.primaryColor` | PropertyAccess | — | 0 (ראשון 5) | 1 · **חוסם** |
| UIL-005 | אין `Icons.`/`CupertinoIcons.` | identifier prefix | — | 0 | 1 · **חוסם** |
| UIL-006 | `RtlIcon` רק לאייקון כיווני שרשום ב־`rtl_icon.dart` (אף פעם לא `OtzariaIcons`), ואין `Transform.flip`/`Transform.scale(scaleX: -n)` שעוטף `Icon` | ctor + ילד + הרשימה ב־`rtl_icon.dart` | `rtl_icon.dart` | 0 | 1 · **חוסם** |
| UIL-007 | אין `hoverColor`/`splashColor`/`overlayColor` מחוץ ל־`lib/theme/` | named arg | ערך מ־`AppSurfaces.*` (למשל `hoverRow`); `hoverColor: Colors.transparent` ב־`ListTile` שיש לו `onTap:` וגם `trailing:` (JX-14). ב־`ListTile` בלי `onTap` אין ריחוף, ולכן `transparent` שם נתפס כקוד מת | 0 | 1 · **חוסם** |
| UIL-008 | אין `ScaffoldMessenger`/`SnackBar(` | identifier/ctor | `lib/core/ui_snack.dart` | 0 | 1 · **חוסם**, נעול (strict) |
| UIL-009 | `UiSnack.*` מקבל מחרוזת מקטלוג, גם בארגומנט בשם | ארגומנט ליטרלי | — | 0 | 1 · **חוסם** |
| UIL-010 | אין `textDirection: TextDirection.rtl` ב־`Text`/`Text.rich`/`SelectableText` | ctor + named arg | חלונות `ContentDirectionality` (פסוקים בעברית במצב אנגלית), עם allow (JX-09) | 0 (5 חריגים ב־allow: ארבעת הציטוטים במסך "אודות" ומסך שגיאת האתחול) | 1 · **חוסם**, נעול (strict) |
| UIL-011 | אין `TextField(`/`TextFormField(`/`EditableText(` גולמי | ctor | `rtl_text_field.dart` | 0 | 1 · **חוסם** |
| UIL-012 | אין `Card(` גולמי | ctor | `lib/widgets/layout/**` | 3 (כרטיסי המשטח במסך "אודות", כרטיס הזמן בלוח השנה, כרטיס הארגון בחלון הפרסומת) | 2 · **חוסם** |
| UIL-013 | אין `CircularProgressIndicator(` מחוץ ל־`lib/widgets/feedback/` | ctor | `ActionButton` | כ־60 | 2 · לא מומש |
| UIL-014 | אין `PopupMenuButton`/`showMenu(`/`MenuAnchor` מחוץ ל־`lib/widgets/misc/` ולחבילה | ctor/invocation | `lib/widgets/misc/**` (מערכת התפריטים המשותפת) | 5 (שני `MenuAnchor` בדיאלוג החיפוש, סינון המאפיינים, חלון הפרסומת, תפריט ההקשר של `RtlTextField`) | 2 · **חוסם** |
| UIL-015 | אין `Color(0x…)`/`Color.fromARGB`/`Colors.<hue>` מחוץ ל־`lib/theme/`. ההודעה מפנה לתפקיד: כתום/ענבר → `AppSurfaces.warning*`; ירוק "הצלחה" → `secondaryContainer` (DD-24) | ctor/identifier | רק המקרים של DD-24: תוכן (`CustomPainter` שמצייר תוכן, פלטות, מרקר), ייצוא (`pw.*`, ‏`lib/printing/**`, ‏`**/export/**`), כרום מערכת ההפעלה (`lib/core/windowing/**`); וגם `Colors.transparent`, ו־`Colors.white`/`black` בתוך `BoxShadow` | 3 (ראשון 22) | 3 · **חוסם** (⚠ שלושת הנותרים ממתינים להכרעה, סבב 3.11) |
| UIL-016 | אין `.withValues(alpha:)`/`.withAlpha(`/`.withOpacity(` על צבע ממשק מחוץ ל־`lib/theme/` | MethodInvocation | `CustomPainter`, ייצוא, כפתורי החלון (`lib/core/windowing`), צבעי CSS של התוכן. צבע בתוך `BoxShadow(...)` נספר ב־UIL-030 | 93 (ראשון 95) | 3 · **חוסם** |
| UIL-017 | **אין `fontSize:` בקוד פיצ'ר (DD-02):** לא ליטרל, ולא `AppTokens.font*` או חשבון עליו (`fontSM - 1`). התחליף: `textTheme.<slot>` | named arg ב־`TextStyle`/`copyWith` | `lib/theme/**`; ‏`pw.TextStyle`; קבצי תוכן הספר (JX-01, JX-19), שבהם הגודל מחושב מהגדרות הקריאה | 203. הראשון היה 144 ליטרלים. הם ירדו ל־102, ואז הכלל הורחב ל־`AppTokens.font*` (עוד 101) | 3 · **חוסם** |
| UIL-018 | אין `fontFamily:` ליטרלי (כולל `'Roboto'`) מחוץ ל־`lib/theme/`. רשימת ה־fallback של DD-01 חיה רק ב־`AppThemeData` | named arg עם ליטרל מחרוזת, בכל בנאי | `lib/theme/**`. גופן תוכן דרך `AppFonts.*`, מונוספייס (JX-21) דרך `AppTextStyles.monospaceFamily` | 0 | 2 · **חוסם** |
| UIL-019 | **רדיוס רק מהטוקן היחיד (DD-04):** אין `BorderRadius.circular(n)`/`Radius.circular(n)` ליטרלי. מותר `AppTokens.radius`/`borderRadiusAll`/`roundedShape` | ctor + ליטרל | `CustomPainter`, ‏`pw.*`; `CircleBorder`/`BoxShape.circle` לרכיב עגול מטבעו ולכפתור אייקון בלבד (DD-04) | 2 (ראשון 14; `const Radius.circular(3)` בידיות גלילה) | 3 · **חוסם**. ⚠ `StadiumBorder` עוד לא נבדק; ממתין להכרעה על רשימת החריגים (סבב 3.11) |
| UIL-020 | ריווח ב־`EdgeInsets*`/`SizedBox(width/height)` מהסולם בלבד: 2/4/8/12/16/24/32 (DD-03). ההודעה מציעה את הערך הבא כלפי מעלה (6→8, 10→12, 14→16) | ctor + ליטרל: כל ארגומנט ליטרלי של `EdgeInsets.*`/`EdgeInsetsDirectional.*`, ו־`SizedBox(width/height)` **בלי `child`** וקטן מ־32 | 0, ‏`double.infinity`, ביטוי מחושב וטוקן, `CustomPainter`, ‏`pw.*`, נתיבי הייצוא | 153 | 3 · **חוסם** (off-scale בלבד) |
| UIL-021 | אין `EdgeInsets.only(left/right)`/`fromLTRB`/`Alignment.centerLeft/Right`/`Positioned(left/right)` | ctor + named arg, ו־`Alignment.*Left/*Right` | `CustomPainter`, ‏`pw.*`, נתיבי הייצוא; ערך סימטרי (JX-20): `fromLTRB(a, b, a, c)`, `only(left: x, right: x)`, `Positioned(left: x, right: x)`; גאומטריה אחרת עם allow | 74 (ראשון 78) | 3 · **חוסם** |
| UIL-022 | אין השוואת רוחב לליטרל ≥100 (`width < 520`). בדיאלוג: `LayoutBreakpoints.compact` (DD-15) | BinaryExpression על `.width`/`.maxWidth`/`.minWidth` מול ליטרל ≥100 | קבוע `static const` עם שם בתוך הרכיב, `WindowClass`/`LayoutBreakpoints`, ‏`CustomPainter` | 0 | 3 · **חוסם** |
| UIL-023 | אין `Duration(...)` ליטרלי (שאינו 0) ב־`duration:`/`reverseDuration:` של אנימציית ממשק: `Animated*`/`TweenAnimationBuilder`, ‏`AnimationController(...)`, וגלילה מונפשת (`animateTo`, `scrollTo`, `animateToPage`, `ensureVisible`). התחליף: `AppMotion.duration(context, AppTokens.anim*)` (DD-21) | ctor/method + parent arg | לא־UI (timeouts, debounce, `Future.delayed`, `waitDuration` של Tooltip) לא נתפס, כי הכלל מסתכל רק על הבעלים של `duration:`; `Duration.zero` מותר | 33 (21 גלילה, 8 `AnimationController`, 4 `ensureVisible`) | 3 · **חוסם** |
| UIL-024 | **רכיב משותף לא מייבא פיצ'ר:** קובץ ב־`lib/widgets/**` לא מייבא ולא מייצא את `lib/settings/engine/`, ‏`lib/settings/settings_exports.dart`, ‏`lib/plugins/`, ‏`lib/tabs/` או `lib/models/`. ‏`settings/l10n` (settingsText) ו־`theme` מותרים. התחליף: הנתון בפרמטר, הצפיפות מ־`AppDensity`, ומה שהפיצ'ר מוסיף דרך scope או ממשק שהפיצ'ר מממש | import/export directive, ‏`package:otzaria/` ויחסי (מנורמל לנתיב) | הכלל חל רק על `lib/widgets/**`; קוד פיצ'ר רשאי לייבא פיצ'ר | 30 (`widgets/commentary`, ‏`smart_text`, תפריטי הקישורים, `ad_popup_dialog`, ‏`phone_report_tab`) | 2 · **חוסם** |
| UIL-025 | אין `compactMenuMode` מתוך `lib/widgets/**`. התחליף: `AppDensity.of(context)` (DD-10) | PropertyAccess | — | 0 | 4 · לא מומש. החוב כבר אפס, ולכן הכלל יכול להיכנס ישר כ־strict |
| UIL-026 | אין `MediaQuery.withNoTextScaling`/`TextScaler.noScaling`/`RichText(` גולמי | ctor/invocation | עם allow ונימוק (JX-10) | כ־13 `RichText(` | 2 · לא מומש |
| UIL-027 | אין `Brightness.dark`/`isDark` מחוץ ל־`lib/theme/` להחלטת צבע | identifier | פלטפורמה (סרגל מערכת), תוספים | כ־54 | 4 · לא מומש |
| UIL-028 | `showDialog(` רק דרך `showDialogUntilTornDown`/`settingsDialogBuilder` והעזרים שעוטפים אותם | invocation | `lib/widgets/dialogs/**` | כ־28 | 4 · לא מומש |
| UIL-029 | **גודל אייקון מטוקן (DD-03):** אין `size:` ליטרלי ב־`Icon(`, אין `iconSize:` ליטרלי, ואין `AppTokens.font*` כגודל אייקון. התחליף: `AppTokens.icon*` | ctor + named arg: `size:` ב־`Icon`/`RtlIcon`/`ImageIcon`, ו־`iconSize:` בכל מקום | `CustomPainter`, ‏`pw.*`, ייצוא, מעבדי תוכן (`smart_text`, `reader_line`, JX-19); ביטוי מחושב | 182 (ראשון 223) | 3 · **חוסם** (⚠ גודל 18 ממתין להכרעה, סבב 3.11) |
| UIL-030 | **הגבהה וצל מהטוקנים (DD-12):** `elevation:` רק `0` או `AppTokens.elevation*`, ואין `BoxShadow(` מחוץ ל־`lib/theme/` | named arg + ctor | נייר PDF (JX-05), `CustomPainter`, גובה גאוגרפי שאינו ארגומנט של Widget (JX-16) | 6 `BoxShadow`: 2 צללי נייר של עמוד PDF (⚠ אישורם כ־allow ממתין, סבב 3.11) ו־4 אנימציות הדגשה וחגיגת סיום. הגבהה ליטרלית: 0. שקיפות בתוך `BoxShadow` נספרת כאן ולא ב־UIL-016 | 3 · **חוסם** |

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
- **`ui_baseline_guard.yml`** מכשיל PR שמוסיף מופעים לכלל באותו קובץ ובאותו `scope`, אלא אם יש עליו התווית **`ui-baseline`** (DD-23), שמתחזק מוסיף. ההשוואה היא לפי כלל, קובץ ו־`scope`, בלי `fp`, כך ששינוי ביטוי או גרסת מנוע אינם נספרים כגידול.
- **מה חוסם:** `ui_lint_test` מכשיל חריגה חדשה בכל כלל שהשלב שלו (`UiLintRule.stage`) עד `blockingStage` (היום 3). כל 21 הכללים הממומשים הם בשלבים 1–3, ולכן כולם חוסמים. כלל בשלב 4 יופיע בדוח בלבד. baseline מת והערת allow פגומה מכשילים בכל כלל.
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
5. כל ה־allow מופיעים בדוח עם הנימוק. היום יש 10 בקוד.
6. **מתוכנן, לא מומש:** תקרה לכל כלל (`max_allows`) ושדות בעלים ומעקב (issue) לכל החרגה. היום החרגה נושאת נימוק בלבד, והבעלות היא של מי שאישר את ה־PR.

**לפי נתיב או הקשר:** רק ב־`config.yaml`, ותמיד עם `reason:` (היום 49 החרגות). שם נרשמים גם עוטפים מורשים, כמו `RtlTextField` שבונה `TextField`. החרגה בלי `reason` היא שגיאת קונפיגורציה.

### 3.6 מה לא חוסמים
| הקשר | נימוק |
|---|---|
| `lib/theme/**` | שכבת הטוקנים |
| `extends CustomPainter`, ‏`paint(Canvas…)` | גאומטריה וצבע של ציור תוכן |
| `pw.*`, ‏`lib/printing/**` (הייצוא), `lib/tools/tikkun_korim/export/**`, `calendar_print_helpers.dart` | פלט נייר |
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
| JX-03 | הכול | ייצוא PDF והדפסה (`pw.*`, `lib/printing/**`, ייצוא תיקון קוראים ולוח השנה) | פלט נייר, תמיד בהיר |
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

## 4. בדיקות חוזה (Contract tests)

לכל רכיב משותף שמשנים, כותבים קודם בדיקת widget שמקבעת את החוזה. הבדיקות הקיימות ב־`test/design_system/contracts/`:
- `theme_contract_test.dart`: ערכת הנושא וה־component themes.
- `components_contract_test.dart`: `AppCard`, `MetaChip`, `AppSectionLabel`, `BarButton`, מצבי המשוב, `SquareIconButton`.
- `app_dialog_contract_test.dart`, `dialog_frames_contract_test.dart`, `golden_details_contract_test.dart`: משפחות הדיאלוג, הגדלים, הגובה עד 85%, ה־X והתג לפי הגודל, ומתחת ל־600.
- `dialog_keyboard_contract_test.dart`: Enter לפי הפוקוס, Escape ו־`isDirty`.
- `accessibility_contract_test.dart`: Semantics של נבחר ומורחב, tooltip והכרזת `UiSnack`.

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
| טקסט מוגדל | `TextScaler.linear(1.3)` בלי overflow | **מתוכנן:** אין עדיין מקרה כזה בבדיקות החוזה |
| נגישות אוטומטית | `meetsGuideline(textContrastGuideline)`, ‏`androidTapTargetGuideline`, ‏`labeledTapTargetGuideline` | **מתוכנן:** אין עדיין שימוש ב־`meetsGuideline` ב־`test/` |

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
6. **Comparator:** `TolerantGoldenFileComparator` (`test/goldens/golden_harness.dart`), תת־מחלקה של `LocalFileComparator` שמקבלת הבדל של עד 0.05% מהפיקסלים. תמונה בגודל אחר נכשלת תמיד. התמונות בגודל רכיב ולא מסך מלא, כדי שהאחוז יהיה משמעותי. שינוי ריפוד של פיקסל אחד ב־`ActionButton` הוא 0.51% ונכשל. **הסף נשאר 0.05% (DD-22, השלמה 2.11).** פרט שקטן מהסף, כמו X, תג אייקון או אייקון בכפתור, נבדק בבדיקת widget רגילה (`golden_details_contract_test.dart`), ולא בהידוק הסף.
7. **מטריצה:** pairwise, לא מכפלה מלאה. לכל רכיב: בסיס `light-rtl-wide-1.0`, ‏`dark-rtl-wide-1.0`, ‏`light-rtl-compact-1.0`, ‏`light-rtl-wide-1.3`, ‏`dark-rtl-compact-1.3`, ו־`light-ltr-wide-1.0` רק לכרום שתומך במצב אנגלית. מכפלה מלאה רק לרכיבים המרכזיים.
8. **מה מכוסה:** היום `ActionButton` (כל הווריאנטים, בהיר וכהה) ו־`AppDialog` (`twoActions` בהיר וכהה, `warning`). **מתוכנן,** לפני השינוי החזותי הבא של כל רכיב: `BarButton`, `SquareIconButton`, `RtlTextField`, `AppDropdownField`, `AppSegmentedControl`, שורות ההגדרה, `AppCard`, `ResultCardFrame`, `NavTreeTile`, `ItemsListView`, מצבי המשוב, `AppTopBar`, `NavRailItem` ורצועת הכרטיסיות.
9. **עדכון:** `flutter test --update-goldens test/goldens/<component>` על Windows בלבד, עם הגרסה המוצמדת. מי שאין לו Windows מריץ את "Regenerate goldens" (`regenerate_goldens.yml`) ומוריד את ה־artifact. עדכון גרסת Flutter מחדש את כל התמונות באותו PR.
10. **שינוי מכוון מול רגרסיה:**
    - **רגרסיה:** בדיקת golden נכשלת ב־PR שלא שינה אף PNG.
    - **שינוי מכוון:** ה־PR משנה PNG. ‏`goldens_guard.yml` מחייב את התווית **`goldens-approved`** (DD-23), והסוקר בודק את תצוגת ה־diff של GitHub.
    - **אסור** לעדכן golden ב־PR שאינו שינוי ממשק.

## 6. הכנסה בהדרגה

| רמה | מה רץ | חוסם? | מצב |
|---|---|---|---|
| **1. Report** | `ui_lint_cli --format=github` עם `continue-on-error`: טבלה ל־`$GITHUB_STEP_SUMMARY` ו־annotations לחריגות חדשות (GitHub מציג עד ~10 בכל step) | לא | קיים |
| **2. New violations** | `test/design_system/ui_lint_test.dart` חוסם חריגה חדשה מול ה־baseline, ו־`ui_baseline_guard.yml` חוסם גידול ב־baseline בלי תווית | כן, לחריגות חדשות | קיים |
| **3. כללי טוקנים** | UIL-015…023, ‏UIL-029, ‏UIL-030, עם ההחרגות של §3.6, כל אחד עם baseline של החוב שלו | כן, לחריגות חדשות | קיים |
| **4. Strict** | כלל שה־baseline שלו התרוקן ננעל, כך שגם `--allow-growth` עם תווית לא יכול להוסיף לו | כן | **מתוכנן, לא מומש:** אין היום מפתח `strict` במנוע או ב־`config.yaml`. מועמדים: UIL-004, 005, 006, 007, 009, 011, 018, 022, ו־UIL-025 כשייכנס |

**הבדיקות הקיימות** עוברות למנוע אחת אחרי השנייה. כל העברה נעשית ב־commit נפרד, שמוכיח שהכלל החדש מוצא כל מה שהישן מצא, ובנוסף את הצורות שהישן פספס. בדיקות exact-set (`quit_application_call_sites`, ‏`flutter_internal_imports`) נשארות כמות שהן.

## 7. בדיקת הכללים עצמם
לכל כלל ב־`test/design_system/fixtures/`:
- `violating_uil_xxx.dart`: חייב להחזיר בדיוק את השורות המסומנות. זה ה־canary.
- `clean_uil_xxx.dart`: חייב להחזיר 0. כאן נכנסים המקרים הלגיטימיים: ייצוא, painter ועוטף מורשה.
- `allowed_uil_xxx.dart`: allow תקין מחזיר 0. allow בלי נימוק, או allow שלא השתיק כלום, מדווחים (`bad_allows.dart`).
- ב־CI: PR שמכניס חריגה חדשה בקובץ ב־`lib` נכשל עם הודעה בעברית: `path:line`, הקטע, והרכיב או הטוקן שצריך להשתמש בו.
- baseline: הזזת קוד ופורמט לא שוברים אותו, חריגה חדשה נתפסת גם כשהיא זהה לחריגה קיימת, ו־`updated` רק מכווץ.
- golden: הבדיקה "הזזה של פיקסל אחד בריפוד חורגת מהסף" (`test/goldens/action_button/action_button_golden_test.dart`) מראה ש־`goldens_windows` נכשל על שינוי ריפוד בלי עדכון תמונה.

## נספח — בדיקות הסריקה הקיימות
| בדיקה | אוכפת | הערה |
|---|---|---|
| ~~`test/widgets/text/bare_text_field_scan_test.dart`~~ | אין `TextField(` גולמי | **הועברה ל־UIL-011**, שתופס גם `TextFormField`/`EditableText` |
| ~~`test/core/messages/uisnack_literal_scan_test.dart`~~ | אין ליטרל בארגומנט הראשון של `UiSnack` | **הועברה ל־UIL-009**, שתופס גם ארגומנט בשם |
| `test/widgets/text/default_context_menu_scan_test.dart` | `SelectionArea` עם `contextMenuBuilder` | חלון של 15 שורות |
| ~~`test/widgets/rtl_icon_registered_usage_test.dart`~~ | `RtlIcon` רק לאייקונים רשומים | **הועברה ל־UIL-006**, שתופס גם `Transform.flip`/`Transform.scale(scaleX: -n)` סביב אייקון. משתנים עדיין לא נבדקים |
| `test/plugins/utils/plugin_icon_resolver_usage_test.dart` | resolver יחיד | כוללת בדיקה שהסורק אכן מוצא משהו |
| `test/settings/no_scrollable_markdown_test.dart` | `MarkdownBody` | |
| `test/settings/l10n/settings_dialog_scope_test.dart` | `settingsDialogBuilder` | חלון של 8 שורות |
| `test/core/windowing/quit_application_call_sites_test.dart` | exact set | נשארת |
| `test/widgets/text_painter_direction_test.dart` | `TextPainter.textDirection` | דרך `ctorCallsNamed` (§3.2), ולכן מוצאת גם `TextPainter(...)` בלי `new` |
| `test/pdf_book/pdf_hardcoded_colors_test.dart` | אין `Colors.<hue>` בשני קבצים | יוחלף ב־UIL-015 |
| `test/utils/ui/image_decode_size_test.dart` | `cacheWidth` | נשארת |
| `test/design_system/agent_docs_paths_test.dart` | כל נתיב ב־`AGENTS.md`, בתבנית ה־PR, ב־`agent_ui_reference.md`, ב־`agent_test_map.md` ובמסמכי התקן קיים | קטע מחוק `~~…~~` מתעד קובץ שהוסר ולא נבדק |
