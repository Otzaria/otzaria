# תוכנית אכיפה ב־CI

> בסיס: `upstream/dev` ‏`f86ecd7c7` (עודכן מול `ac97e4490` אחרי #3794). המטרה: לזהות חריגה מהתקן לפני מיזוג, בלי לחסום שימושים לגיטימיים ובלי להכשיל את ה־CI על חוב ישן.
> **גרסה 1.0 (1.11.2026):** ההכרעות אושרו. המנוע `tool/ui_lint` (DD-23 A), golden על Windows (DD-22 A), והכללים מיושרים לערכים שהוכרעו: DD-01, 02, 03, 04, 12, 15, 24. **מצב המימוש:** המנוע (MIG-01), הבדיקה החוסמת וה־guards (MIG-27) ותשתית ה־golden (MIG-29) מומשו, וגם גבול הייבוא של הרכיבים המשותפים (UIL-024). כללי הטוקנים (UIL-015…021, ‏023, ‏029, ‏030) חוסמים מ־MIG-28, כל אחד עם baseline של החוב הקיים שלו; UIL-014 (תפריטים גולמיים) ו־UIL-022 (ספי רוחב) נכנסו עם MIG-21. שאר הכללים טרם.

## 1. המצב היום

| רכיב | מצב | ראיה |
|---|---|---|
| Analyzer | `flutter_lints` בלבד, בלי כללים נוספים. `flutter analyze` רץ ב־job ‏`analyze` | `analysis_options.yaml`, `.github/workflows/flutter_tests.yml:146` |
| בדיקת פורמט | לא נבדקת לאפליקציה, רק לחבילת `otzaria_context_menu` | `flutter_tests.yml:145,161` |
| בדיקות | 5 shards על Linux, מאוזנים לפי זמן. כל `*_test.dart` חדש נכנס לאחד מהם אוטומטית | `tool/ci/test_shards.dart` |
| Windows | מריץ רק `test/core`, `tabs`, `navigation`, `workspaces` ו־`personal_notes` | `flutter_tests.yml:485-515` |
| גרסת Flutter | 3.47.7, מוצמדת כליטרל בכ־22 מקומות | כל ה־workflows |
| Pre-commit | `dart_pre_commit`, אופציונלי ולא נשמר בגיט. לא נקודת אכיפה | `tool/install_git_hooks.dart` |
| בדיקות סריקה (התקדים בבית) | כ־18 בדיקות שסורקות את `lib/`: `TextField` גולמי, מחרוזת ב־`UiSnack`, `SelectableText`, `RtlIcon`, `fluentIconFromName`, `Markdown(`, `settingsDialogBuilder`, `quitApplication`, `TextPainter` ועוד | `test/**/_scan_test.dart` ועוד (רשימה בנספח) |
| Golden tests | **אין** | — |

**ממצא חמור:** הבדיקה `test/widgets/text_painter_direction_test.dart`, בדיקת ה־AST היחידה, **לעולם לא נכשלת**:
- היא מבקרת רק `InstanceCreationExpression` (`:41-49`) על AST של `parseString`, שאינו מפוענח.
- ב־AST כזה, `TextPainter(...)` בלי `new`/`const` מופיע כ־`MethodInvocation`.
- כל 23 הקריאות ב־`lib` כתובות כך.

אותה מלכודת תחול על כל כלל AST עתידי, ולכן המנוע (סעיף 3) מטפל בה פעם אחת.

**כללים מתועדים שאין להם אכיפה:**
- כפתורים ודיאלוגים גולמיים.
- `hoverColor`/`splashColor`/`overlayColor`.
- `.withValues(alpha:)`/`.withAlpha(` בפיצ'רים.
- אייקוני Material/Cupertino (0 היום, אבל לא נאכף).
- `TextDirection.rtl` על `Text`.
- `Transform.flip` סביב אייקון.
- `ScaffoldMessenger.showSnackBar`.
- `Theme.of(context).primaryColor`.
- גדלי גופן, גדלי אייקון, רדיוסים, הגבהה וצבעים קשיחים.

## 2. עקרונות
1. **AST עדיף על regex** כשצריך להבין תחביר: שם בנאי, ארגומנט בשם, ערך ליטרלי, מחלקה עוטפת (`extends CustomPainter`) או prefix (`pw.`).
2. **מנוע אחד לכל הכללים.** הקוד ב־`tool/` והבדיקה מייבאת אותו, לפי התקדים של `test_shards`, ‏`plugin_spec_generator` ו־`settings_l10n_generator`.
3. **בלי תלויות חדשות.** `analyzer` כבר תלות dev, ו־`path` ו־`yaml` כבר קיימים.
4. **חוב ישן לא מכשיל.** baseline שיכול רק לקטון.
5. **אין השתקה גורפת.** חריג נכתב על צומת בודד, עם נימוק חובה.
6. **כל כלל נבדק בעצמו.** לכל כלל יש מקרה שחייב להיכשל ומקרה שחייב לעבור, ובדיקה שהסורק אכן מוצא משהו.

## 3. המנוע: `tool/ui_lint/` [מחייב · DD-23 A] · מומש: מצב דוח (MIG-01) ובדיקה חוסמת (MIG-27)

### 3.1 מבנה
```
tool/ui_lint/
  ui_lint.dart            # API: runUiLint(root, config) → List<Finding>
  rules/                  # קובץ לכל כלל, RecursiveAstVisitor
  config.yaml             # החרגות לפי נתיב/הקשר, כל אחת עם reason
  baseline.json           # חוב קיים, ממוין, נסקר ב-PR
tool/ui_lint_cli.dart     # dart run tool/ui_lint_cli.dart --format=md|github|json [--update-baseline]
test/design_system/
  ui_lint_test.dart       # חוסם: אין חריגות חדשות, אין baseline מת, allow תקין, canaries
  fixtures/               # קבצי dart קטנים: violating_*.dart / clean_*.dart לכל כלל
```
- המנוע **לא מייבא `package:otzaria`**, ולכן לא מושך Flutter או את מנוע החיפוש.
- מעבר AST אחד על כל `lib` לוקח בערך 8–10 שניות. לפי `test_timings.json:1442`, ‏text_painter_direction_test לוקח 10.9 שניות.

### 3.2 זיהוי בנאים ב־AST לא מפוענח (חובה בכל כלל)
כל כלל שמחפש בנאי מבקר **גם**:
- `InstanceCreationExpression`, עבור `new`/`const`;
- `MethodInvocation` עם `target == null` ושם שמתחיל באות גדולה, עבור `Foo(...)`;
- `MethodInvocation` עם `target` שהוא שם מחלקה, עבור `Foo.named(...)`;
- `PrefixedIdentifier`/`MethodInvocation` עם prefix של import, עבור `pw.TextStyle(...)`.

העזר `ctorCallsNamed(unit, {'AlertDialog'})` משמש את כל הכללים. הבדיקה הקיימת של `TextPainter` עוברת אליו בשלב 0.

### 3.3 קטלוג הכללים

הגודל ההתחלתי של ה־baseline מבוסס על הסריקה הסטטית (UI_AUDIT §2.3) ועל ספירה ב־`ac97e4490`. הערכים מעוגלים, והמספר הסופי ייקבע בהרצה הראשונה. כל הודעת כלל מציינת את התחליף מהתקן.

| ID | כלל | זיהוי | החרגות מובנות (config) | baseline משוער | שלב |
|---|---|---|---|---|---|
| UIL-001 | אין `AlertDialog`/`Dialog`/`SimpleDialog` מחוץ ל־`lib/widgets/dialogs/` | ctor | `lib/widgets/dialogs/**` | ~27 | 1 |
| UIL-002 | אין `TextButton`/`FilledButton`/`OutlinedButton`/`ElevatedButton` מחוץ ל־`lib/widgets/controls/` | ctor (כולל `.icon`/`.tonal`) | `lib/widgets/controls/**`, ‏`lib/widgets/misc/app_dropdown_field.dart` | ~26 | 1 |
| UIL-003 | לכל `IconButton` יש `tooltip:` | ctor + named arg | `IconButton.styleFrom` (לא בנאי) | ~40 | 1 |
| UIL-004 | אין `Theme.of(…).primaryColor` / `theme.primaryColor` | PropertyAccess | — | 5 | 1 |
| UIL-005 | אין `Icons.`/`CupertinoIcons.` | identifier prefix | — | 0 | 1 |
| UIL-006 | `RtlIcon` רק לאייקון כיווני שרשום ב־`rtl_icon.dart` (אף פעם לא `OtzariaIcons`), ואין `Transform.flip`/`Transform.scale(scaleX: -n)` שעוטף `Icon` | ctor + ילד + הרשימה ב־`rtl_icon.dart` | `rtl_icon.dart` | 0 | 1 (מחליף את הבדיקה הקיימת) |
| UIL-007 | אין `hoverColor`/`splashColor`/`overlayColor` מחוץ ל־`lib/theme/` | named arg | ערך מ־`AppSurfaces.*` (למשל `hoverRow` ברשימות המשותפות); `hoverColor: Colors.transparent` (גם בתנאי מול `null`) ב־`ListTile` שיש לו `onTap:` וגם `trailing:`. ב־`ListTile` בלי `onTap` אין ריחוף, ולכן `transparent` שם נתפס כקוד מת | 0 (מומש: 4 ה־no-ops של UI-063 הוסרו) | 1 · **מומש** |
| UIL-008 | אין `ScaffoldMessenger`/`SnackBar(` | identifier/ctor | `lib/core/ui_snack.dart` | ~0 | 1 |
| UIL-009 | `UiSnack.*` מקבל מחרוזת מקטלוג, גם בארגומנט בשם | ארגומנט ליטרלי | — | ~0 | 1 (מחליף בדיקה קיימת ומרחיב אותה) |
| UIL-010 | אין `textDirection: TextDirection.rtl` ב־`Text`/`Text.rich`/`SelectableText` | ctor + named arg | חלונות `ContentDirectionality` (פסוקים בעברית במצב אנגלית), עם allow | ~15 | 1 |
| UIL-011 | אין `TextField(`/`TextFormField(`/`EditableText(` גולמי | ctor | `rtl_text_field.dart` | 0 | 1 (מרחיב בדיקה קיימת) |
| UIL-012 | אין `Card(` גולמי | ctor | `lib/widgets/layout/**` | 8 | 2 |
| UIL-013 | אין `CircularProgressIndicator(` מחוץ ל־`lib/widgets/feedback/` | ctor | `ActionButton` | ~70 | 2 |
| UIL-014 | אין `PopupMenuButton`/`showMenu(`/`MenuAnchor` מחוץ ל־`lib/widgets/misc/` ולחבילה | ctor/invocation | — | 5 ב־baseline (שני `MenuAnchor` בדיאלוג החיפוש, סינון המאפיינים, חלון הפרסומת, תפריט ההקשר של `RtlTextField`) | 2 · **מומש, חוסם** (MIG-21) |
| UIL-015 | אין `Color(0x…)`/`Color.fromARGB`/`Colors.<hue>` מחוץ ל־`lib/theme/`. ההודעה מפנה לתפקיד: כתום/ענבר → `AppSurfaces.warning*`; ירוק "הצלחה" → `secondaryContainer` (DD-24) | ctor/identifier | רק המקרים של DD-24: תוכן (`extends CustomPainter` שמצייר תוכן, פלטות `app_seed_colors`/`calendar_event_colors`, מרקר), ייצוא (`pw.*`, ‏`lib/printing/**`, ‏`**/export/**`), כרום מערכת ההפעלה (`lib/core/windowing/**`); וגם `Colors.transparent`, ו־`Colors.white`/`black` בתוך `BoxShadow` (עד MIG-08) | 3 ב־baseline (מ־23; MIG-28) | 3 · **מומש, חוסם** |
| UIL-016 | אין `.withValues(alpha:)`/`.withAlpha(`/`.withOpacity(` על צבע ממשק מחוץ ל־`lib/theme/` | MethodInvocation (`withValues` עם `alpha:`) | `CustomPainter`, ייצוא (`pw.*` ונתיבי הייצוא), כפתורי החלון (`lib/core/windowing`), צבעי CSS של התוכן. צבע בתוך `BoxShadow(...)` נספר ב־UIL-030 ולא כאן | 95 ב־baseline ההתחלתי | 3 · **מומש, חוסם** |
| UIL-017 | **אין `fontSize:` בקוד פיצ'ר (DD-02):** לא ליטרל, ולא `AppTokens.font*` או חשבון עליו (`fontSM - 1`). התחליף: `textTheme.<slot>` | named arg ב־`TextStyle`/`copyWith` | `lib/theme/**`; ‏`pw.TextStyle`; קבצי תוכן הספר (רשימה ב־config, נגזרת מ־UI_AUDIT `justified_exceptions` JX-01, JX-19), שבהם הגודל מחושב מהגדרות הקריאה | 106 ליטרלים + 101 `AppTokens.font*` ב־baseline | 3 · **מומש, חוסם** |
| UIL-018 | אין `fontFamily:` ליטרלי (כולל `'Roboto'`) מחוץ ל־`lib/theme/`. רשימת ה־fallback של DD-01 חיה רק ב־`AppThemeData` | named arg (`fontFamily:` עם ליטרל מחרוזת, בכל בנאי) | `lib/theme/**`. גופן תוכן דרך `AppFonts.*` (גם ברירות המחדל של הגדרות הקריאה), מונוספייס (JX-21) דרך `AppTextStyles.monospaceFamily` | 0 (מומש) | 2 · **מומש** |
| UIL-019 | **רדיוס רק מהטוקן היחיד (DD-04):** אין `BorderRadius.circular(n)`/`Radius.circular(n)` ליטרלי, ואין `StadiumBorder`. מותר `AppTokens.radius`/`borderRadiusAll`/`roundedShape` | ctor + ליטרל | `CustomPainter`, ‏`pw.*`; `CircleBorder`/`BoxShape.circle` לרכיב עגול מטבעו (נקודת סטטוס, אווטאר) ולכפתור אייקון בלבד (DD-04) | 2 ב־baseline (`const Radius.circular(3)` בידיות גלילה). `StadiumBorder` עוד לא נבדק בכלל | 3 · **מומש, חוסם** |
| UIL-020 | ריווח ב־`EdgeInsets*`/`SizedBox(width/height)` מהסולם בלבד: 2/4/8/12/16/24/32 (DD-03, אחרי MIG-04). ההודעה מציעה את הערך הבא כלפי מעלה (6→8, 10→12, 14→16) | ctor + ליטרל: כל ארגומנט ליטרלי של `EdgeInsets.*`/`EdgeInsetsDirectional.*`, ו־`SizedBox(width/height)` **בלי `child`** וקטן מ־32 (מרווח; קופסה עם ילד או של 32 ומעלה היא מידה) | 0, ‏`double.infinity`, ביטוי מחושב וטוקן, `CustomPainter`, ‏`pw.*`, נתיבי הייצוא | 153 מחוץ לסולם ב־baseline ההתחלתי | 3 · **מומש, חוסם** (off-scale בלבד) |
| UIL-021 | אין `EdgeInsets.only(left/right)`/`fromLTRB`/`Alignment.centerLeft/Right`/`Positioned(left/right)` | ctor + named arg, ו־`Alignment.*Left/*Right` (PrefixedIdentifier) | `CustomPainter`, ‏`pw.*`, נתיבי הייצוא; ערך סימטרי (JX-20): `fromLTRB(a, b, a, c)`, `only(left: x, right: x)`, `Positioned(left: x, right: x)`; גאומטריה אחרת עם allow | 78 ב־baseline ההתחלתי (31 `Positioned`, 26 `EdgeInsets`, 21 `Alignment`) | 3 · **מומש, חוסם** |
| UIL-022 | אין השוואת רוחב לליטרל ≥100 (`width < 520`). בדיאלוג: `LayoutBreakpoints.compact` (DD-15) | BinaryExpression על `.width`/`.maxWidth`/`.minWidth` מול ליטרל ≥100 | קבוע `static const` עם שם בתוך הרכיב, `WindowClass`/`LayoutBreakpoints`, ‏`CustomPainter` | 0 (DD-15 נתן שם לכל ה־32) | 3 · **מומש, חוסם** (MIG-21) |
| UIL-023 | אין `Duration(...)` ליטרלי (שאינו 0) ב־`duration:`/`reverseDuration:` של אנימציית ממשק: רכיב `Animated*`/`TweenAnimationBuilder`, ‏`AnimationController(...)`, וגלילה מונפשת (`animateTo`, `scrollTo`, `animateToPage`, `ensureVisible`). התחליף: `AppMotion.duration(context, AppTokens.anim*)` (DD-21) | ctor/method + parent arg | לא־UI (timeouts, debounce, `Future.delayed`, `waitDuration` של Tooltip) לא נתפס, כי הכלל מסתכל רק על הבעלים של `duration:`; `Duration.zero` מותר | 33 ב־baseline ההתחלתי (21 גלילה, 8 `AnimationController`, 4 `ensureVisible`); רכיבי `Animated*` כבר נקיים (MIG-04) | 3 · **מומש, חוסם** |
| UIL-024 | **רכיב משותף לא מייבא פיצ'ר (DESIGN_SYSTEM §3 כלל 4):** קובץ ב־`lib/widgets/**` לא מייבא ולא מייצא את `lib/settings/engine/`, ‏`lib/settings/settings_exports.dart`, ‏`lib/plugins/`, ‏`lib/tabs/` או `lib/models/`. ‏`settings/l10n` (settingsText) ו־`theme` מותרים. התחליף: הנתון בפרמטר, הצפיפות מ־`AppDensity`, ומה שהפיצ'ר מוסיף דרך scope או ממשק שהפיצ'ר מממש | import/export directive, ‏`package:otzaria/` ויחסי (מנורמל לנתיב) | הכלל חל רק על `lib/widgets/**`; קוד פיצ'ר רשאי לייבא פיצ'ר | 30 (מומש: `widgets/commentary`, ‏`smart_text`, תפריטי הקישורים, `ad_popup_dialog`, ‏`phone_report_tab`) | 2 · **מומש** |
| UIL-025 | אין `compactMenuMode` מתוך `lib/widgets/**`. התחליף: `AppDensity.of(context)` (DD-10, אחרי MIG-06) | PropertyAccess | — | ~12 | 4 |
| UIL-026 | אין `MediaQuery.withNoTextScaling`/`TextScaler.noScaling`/`RichText(` גולמי | ctor/invocation | עם allow ונימוק (JX-10) | ~10 | 2 |
| UIL-027 | אין `Brightness.dark`/`isDark` מחוץ ל־`lib/theme/` להחלטת צבע | identifier | פלטפורמה (סרגל מערכת), תוספים | ~57 | 4 |
| UIL-028 | `showDialog(` רק דרך `showDialogUntilTornDown`/`settingsDialogBuilder` והעזרים שעוטפים אותם | invocation | `lib/widgets/dialogs/**` | ~90 | 4 |
| UIL-029 | **גודל אייקון מטוקן (DD-03):** אין `size:` ליטרלי ב־`Icon(`, אין `iconSize:` ליטרלי, ואין `AppTokens.font*` כגודל אייקון. התחליף: `AppTokens.icon*` (אחרי MIG-04) | ctor + named arg: `size:` ב־`Icon`/`RtlIcon`/`ImageIcon`, ו־`iconSize:` בכל מקום | `CustomPainter`, ‏`pw.*`, ייצוא, מעבדי תוכן (`smart_text`, `reader_line`, JX-19); ביטוי מחושב | 223 ב־baseline ההתחלתי (206 `size`, 17 `iconSize`). 117 מהם כבר בערך של טוקן (16/20/14/24), ו־63 הם 18 | 3 · **מומש, חוסם** |
| UIL-030 | **הגבהה וצל מהטוקנים (DD-12):** `elevation:` רק `0` או `AppTokens.elevation*`, ואין `BoxShadow(` מחוץ ל־`lib/theme/` (אחרי MIG-08) | named arg + ctor | נייר PDF (JX-05), `CustomPainter`, גובה גאוגרפי שאינו ארגומנט של Widget (JX-16) | `elevation:` שיש בו ליטרל שאינו 0 (גם `?? 3` ובענף תנאי): 0 ב־baseline. `BoxShadow(` מחוץ ל־`lib/theme` (לא `pw.BoxShadow`): 6 ב־baseline ההתחלתי, מהם 2 צללי נייר של עמוד PDF (JX-05, יעברו ל־allow) ו־4 שעוד לא עברו ל־`AppShadows` (אנימציות הדגשה וחגיגת הסיום). שקיפות בתוך `BoxShadow` נספרת כאן ולא ב־UIL-016 | 3 · **מומש, חוסם** |

**כלל לא נכנס לשלב 1** אם שיעור ההתראות השגויות שלו בהרצה ראשונה גבוה מ־10%. כלל כזה נשאר בדוח עד שהוא משתפר.

### 3.4 Baseline
```json
{ "version": 1,
  "rules": { "UIL-001": { "lib/foo/view/bar_dialog.dart": [
      {"scope": "_BarDialogState._confirm", "fp": "9f2c1a7e", "n": 1} ] } } }
```
- **המפתח:** כלל + קובץ + `scope` (מחלקה.מתודה מתוך ה־AST) + `fp` (hash של קוד הצומת המנורמל). אין מספרי שורות. כלל שמדווח על בנאי עם תוכן גדול (UIL-001 דיאלוג, UIL-003 `IconButton`) מחשב את `fp` משם הבנאי בלבד (`CtorCall.head`), כדי ששינוי בתוכן הדיאלוג לא יהפוך אותו לחריגה חדשה. הוספת בנאי כזה באותו `scope` עדיין נתפסת דרך `n`.
- **ספירה:** `n` סופר מופעים זהים.
- **הזזת קוד ופורמט** לא שוברים את ה־baseline. שינוי הביטוי עצמו כן: מי שנגע בשורה מתקן אותה.
- **חריגה שאינה ב־baseline** מכשילה את הבדיקה: "חריגה חדשה".
- **רשומה שלא נוצלה** מכשילה את הבדיקה: "baseline מת — הרץ `--update-baseline`". זה ה־ratchet, לפי התקדים של `backup_storage_coverage_test.dart:134`.
- **`--update-baseline`** רק מוחק רשומות. הוספה דורשת `--allow-growth`.
- **workflow ‏`ui_baseline_guard.yml`** (בסגנון `lockfile_guard.yml`) מכשיל PR שמוסיף מופעים לכלל באותו קובץ ובאותו `scope`, אלא אם יש עליו תווית **`ui-baseline`** (DD-23), שמתחזק מוסיף. ההשוואה היא לפי כלל, קובץ ו־`scope` בלי `fp`, כך ששינוי ביטוי או גרסת מנוע אינם נספרים כגידול.
- **מה חוסם:** הבדיקה `test/design_system/ui_lint_test.dart` מכשילה חריגה חדשה בכלל שהשלב שלו (`UiLintRule.stage`) עד `blockingStage` (היום 3: UIL-001, ‏003, ‏004, ‏005, ‏006, ‏007, ‏009, ‏011, ‏024, ומ־MIG-28 גם כללי הטוקנים UIL-015, ‏016, ‏017, ‏018, ‏019, ‏020, ‏021, ‏023, ‏029, ‏030). כלל בשלב 4 מופיע בדוח בלבד. baseline מת והערת allow פגומה מכשילים בכל כלל.

### 3.5 חריגים מתועדים
**inline**, על הצומת הבא בלבד:
```dart
// ui-lint: allow UIL-015 — צבעי המותג של מפרט הייצוא של Hebcal
const _hebcalBlue = Color(0xFF1565C0);
```
1. כלל **אחד** בכל הערה. אין `all`, אין רשימה ואין wildcard.
2. נימוק אחרי `—` או `--`, באורך 12 תווים לפחות.
3. אין צורה של "כל הקובץ".
4. הערת allow שלא השתיקה כלום מכשילה את הבדיקה.
5. כל ה־allow מופיעים בדוח עם הנימוק, ואפשר להגדיר תקרה לכל כלל (`max_allows`).

**לפי נתיב או הקשר:** רק ב־`config.yaml`, ותמיד עם `reason:`. שם נרשמים גם עוטפים מורשים, כמו `RtlTextField` שבונה `TextField`.

### 3.6 מה לא חוסמים (רשימת ההחרגות ההתחלתית)
| הקשר | נימוק |
|---|---|
| `lib/theme/**` | שכבת הטוקנים |
| `extends CustomPainter`, ‏`paint(Canvas…)` | גאומטריה וצבע של ציור תוכן |
| `pw.*`, ‏`lib/printing/**` (הייצוא), `lib/tools/tikkun_korim/export/**`, `calendar_print_helpers.dart` | פלט נייר |
| קבצי תוכן הקריאה: `reader_line/**`, `smart_text/**`, `continuous_reading_paragraph.dart`, `commentary_list_base.dart` (חלקי תוכן), `links_list_view.dart` (גדלים יחסיים) | טיפוגרפיה לפי הגדרות המשתמש (DD-02 מתיר `fontSize` רק כאן וב־Theme) |
| `lib/plugins/utils/fluent_icon_resolver.dart`, `*.g.dart` | קוד שנוצר אוטומטית |
| `app_seed_colors.dart`, `calendar_event_colors.dart`, מרקר | פלטות תוכן |
| `lib/core/windowing/**` (כפתורי חלון, כולל `CaptionButtonColors` של כפתורי הפעולה בשורת הכותרת) | חיקוי של מערכת ההפעלה |
| `lib/pdf_book/utils/pdf_color_filter.dart`, ‏`lib/widgets/misc/app_cursors.dart` (UIL-015) | נייר ומסנן ההיפוך של עמוד PDF; ציור תמונת סמן העכבר |
| צבע בתוך `BoxShadow(color:)` | **זמני, עד MIG-08.** אחר כך צל רק ב־`AppShadows` (DD-12) |

אין החרגה ל־`lib/text_book/editing/**`: העורך נמחק (DD-29, MIG-26), וההחרגה הזמנית JX-23 בטלה.

## 4. בדיקות חוזיות (Contract tests)

לכל רכיב משותף שמשנים, כותבים קודם בדיקת widget שמקבעת את החוזה. **פערים שקיימים היום:** אין בדיקה ישירה ל־`AppDialog` (וריאנטים), ל־`AppDialogFrame`, ל־`ListDialogFrame`, ל־`OtzariaErrorState`, ל־`SquareIconButton`/`PrimaryIconButton`, ל־`LoadingIndicator` או ל־`SettingsCard` עצמו.

| נושא | מה נבדק | איך |
|---|---|---|
| שימוש ב־Theme | רכיב ללא override מקבל את צבעי ה־component theme. שינוי זרע משנה את הרכיב בלי שינוי קוד | `pumpWidget` עם שני `ColorScheme`. בדיקה ש־`Material.color`/`TextStyle.color` נגזרים מהתפקיד |
| בהיר/כהה | ניגודיות ≥4.5 לכל זוג טקסט/רקע של הרכיב, בשני מצבי הבהירות ובכל הזרעים | הרחבה של `test/theme/app_theme_data_test.dart:101-136` |
| פריסת דיאלוג | `small`/`medium`/`large` ברוחב 360/800/1400. אין overflow. רצועת כותרת ותג אייקון בכל גודל (DD-07). מתחת ל־600: `large` במסך מלא (DD-16). ה־X מוצג מ־`medium` ומעלה, ולא ב־`small` (DD-07, השלמה 2.11). כותרת ארוכה נחתכת עם tooltip | `tester.view.physicalSize` |
| גלילה | תוכן ארוך גולל, ושורת הפעולות נשארת קבועה | |
| מקלדת | Escape סוגר. Escape עם dirty שואל. Enter ב־`SelectionDialog` על פריט בוחר אותו (רגרסיה לבאג UI-024). Enter על "ביטול" מבטל. Tab מקיף את שורת הפעולות (DD-08) | `sendKeyEvent` |
| שינוי גודל חלון | רכיב בחלונית ברוחב 300 בתוך חלון ברוחב 1400 מחליט לפי 300 | `SizedBox(width:300)` בתוך view רחב |
| צפיפות | החלפת "צפיפות ממשק" מעדכנת סרגל ותפריט בלי rebuild ידני (DD-10) | שינוי `AppDensity` ב־Theme |
| הפחתת תנועה | עם `disableAnimations`, `AppMotion.duration` מחזיר אפס (DD-21) | `MediaQuery(data: …disableAnimations: true)` |
| תוכן ארוך | כותרת של 200 תווים, ושם ספר עם מספרים ואנגלית | |
| RTL | פריסה ב־RTL ובמצב האנגלית (`ChromeDirectionality`). חצים לפי כיוון | |
| שמירת התנהגות | לפני שכתוב, ולפני כל commit פירוק (DD-30): בדיקה שמתעדת את ההתנהגות הקיימת (characterization). אחרי השכתוב היא עוברת ללא שינוי, או שהשינוי מתועד ב־DD | |
| טקסט מוגדל | `TextScaler.linear(1.3)` בלי overflow | |
| נגישות | `meetsGuideline(textContrastGuideline)`, ‏`androidTapTargetGuideline`, ‏`labeledTapTargetGuideline` | `flutter_test` accessibility guidelines |

## 5. Golden tests [מחייב · DD-22 A] · מומש (MIG-29)
1. **מיקום:** `test/goldens/<component>/<component>_golden_test.dart`, והתמונות ב־`test/goldens/<component>/goldens/`. ‏`failures/` נוסף ל־`.gitignore`.
2. **הרצה:** job חדש ב־CI, `goldens_windows` (‏windows-2025, אותה גרסת Flutter), שמריץ `flutter test test/goldens/` ומעלה את `failures/` כ־artifact. Windows היא פלטפורמת הייחוס (DD-22).
   - `test/goldens/` מוחרג מ־shards של Linux ב־`tool/ci/test_shards.dart::_testFiles()`, עם בדיקה לכך.
   - בתוך הבדיקות: `skip: !Platform.isWindows`, לפי התקדים של `otzaria_icons`.
3. **קונפיגורציה:** `test/goldens/flutter_test_config.dart` טוען גופנים ומתקין comparator, **ואז קורא ל־`root.testExecutable`**. אחרת אתחול המנוע ותיקיית הנתונים הזמנית הולכים לאיבוד, כי Flutter משתמש רק בקובץ הקונפיגורציה הקרוב ביותר.
4. **גופנים:** `test/support/golden_fonts.dart` טוען:
   - **גופן בדיקה לממשק:** Rubik, שנרשם בשם המשפחה שה־textTheme מבקש בפלטפורמת ה־golden. ה־goldens רצים ב־`TargetPlatform.windows` (`goldenPlatform`, דרך `TargetPlatformVariant` ב־`goldenTest`), ולכן השם הוא 'Segoe UI' (`goldenUiFontFamily`), שהוא גם ראש רשימת ה־fallback. כך גם `visualDensity` והתפריטים הצפופים מחושבים כמו באפליקציה ב־Windows. לפי DD-01 הממשק משתמש בגופני המערכת ואין גופן ממשק כלול, ו־Segoe UI לא נכנס למאגר (רישיון). לכן ה־golden לא משחזר את Segoe UI, אלא בודק פריסה, ריווח, צבע וצורה. השם כאן הוא בבדיקות בלבד, ואינו סותר את UIL-018.
   - **מגבלה:** טקסט שאין לו `fontFamily` בכלל (`TextSpan`/`RichText` שלא יורשים סגנון, `TextPainter` בציור) מצויר ב־flutter_tester בגופן הבדיקה המובנה (ריבועים), ואי אפשר לכנות אותו מ־Dart: `FontLoader` בשם 'Roboto', 'Segoe UI', 'Arial', 'FlutterTest', 'Ahem' או '' לא משנה אותו. ב־golden הוא נראה כריבועים, בצורה דטרמיניסטית. טקסט כזה ברכיב משותף הוא סימן שהוא לא יורש את ה־Theme.
   - `MaterialIcons`, `packages/otzaria_icons/OtzariaIcons`, `packages/fluentui_system_icons/FluentSystemIcons-Regular/-Filled` ו־`FluentSystemIcons-Light`, מתוך `FontManifest.json` של ה־bundle.
5. **דטרמיניזם:**
   - `physicalSize` קבוע ו־`devicePixelRatio = 1`.
   - `EditableText.debugDeterministicCursor = true`.
   - `pumpAndSettle`.
   - זרע קבוע דרך `AppThemeData.createColorScheme`.
   - `debugDisableShadows = false` כשהצל הוא חלק מהבדיקה.
6. **Comparator:** `TolerantGoldenFileComparator` (`test/goldens/golden_harness.dart`), תת־מחלקה של `LocalFileComparator` שמקבלת הבדל של עד 0.05% מהפיקסלים. תמונה בגודל אחר נכשלת תמיד. התמונות בגודל רכיב ולא מסך מלא, כדי שהאחוז יהיה משמעותי: `pumpGolden` עוטף את הרכיב ב־`RepaintBoundary`, ו־`expectGolden` מצלם אותו. שינוי ריפוד של פיקסל אחד ב־`ActionButton` הוא 0.51% ונכשל. **הסף נשאר 0.05% (DD-22, השלמה 2.11).** פרט שקטן מהסף (הסרת ה־X מדיאלוג `small` עברה), כמו X, תג אייקון או אייקון בכפתור, נבדק בבדיקת widget רגילה ליד בדיקות החוזה (`test/design_system/contracts/`), ולא בהידוק הסף.
7. **מטריצה:** pairwise, לא מכפלה מלאה. לכל רכיב:
   - בסיס: `light-rtl-wide-1.0`;
   - `dark-rtl-wide-1.0`;
   - `light-rtl-compact-1.0` (רוחב 360 או צפיפות קומפקטית);
   - `light-rtl-wide-1.3`;
   - `dark-rtl-compact-1.3`;
   - `light-ltr-wide-1.0`, רק לכרום שתומך במצב אנגלית.

   מכפלה מלאה רק לרכיבים המרכזיים: משפחת `AppDialog`, שורת `ActionButton`, `SettingsCard`/`SettingsActionTile`, `NavTreeTile`.
8. **רכיבים בגל הראשון** (קיימים: `ActionButton` כל הווריאנטים בבהיר ובכהה, `AppDialog.twoActions` בבהיר ובכהה, `AppDialog.warning`; השאר יתווספו לפני השינוי החזותי של כל רכיב):
   - דיאלוגים: single, two, warning, frame medium/large;
   - כפתורים: כל וריאנטי `ActionButton`, `BarButton`, `SquareIconButton`;
   - טפסים: `RtlTextField` עם תווית/שגיאה, `AppDropdownField`, `AppSegmentedControl`, `SettingsActionTile.*`;
   - כרטיסים: `AppCard`, `AppCard.section`, כרטיס תוצאה;
   - רשימות: `NavTreeTile`, `ItemsListView`;
   - מצבים: `LoadingIndicator`, `OtzariaEmptyState`, `OtzariaErrorState`;
   - ניווט: `AppTopBar`, `NavRailItem`, רצועת כרטיסיות.
9. **עדכון:** `flutter test --update-goldens test/goldens/<component>` על Windows בלבד, עם הגרסה המוצמדת. בנוסף, workflow ‏`workflow_dispatch` בשם "Regenerate goldens" (`regenerate_goldens.yml`) מעלה את התמונות החדשות כ־artifact, כך שגם תורם בלי Windows יכול לעדכן. עדכון גרסת Flutter מחדש את כל התמונות באותו PR.
10. **שינוי מכוון מול רגרסיה:**
    - **רגרסיה:** בדיקת golden נכשלת ב־PR שלא שינה אף PNG.
    - **שינוי מכוון:** ה־PR משנה PNG. ‏`goldens_guard.yml`, בסגנון lockfile guard, מחייב את התווית **`goldens-approved`** (DD-23), והסוקר בודק את תצוגת ה־diff של GitHub.
    - **אסור** לעדכן golden ב־PR שאינו שינוי ממשק.

## 6. הכנסה בהדרגה

| רמה | מה רץ | חוסם? | מתי |
|---|---|---|---|
| **0. תיקון התקדים** | תיקון `text_painter_direction_test` (ראו 3.2) ועדכון התיעוד שהתיישן (`AGENTS.md`, `agent_ui_reference.md`, `rtl-text-field-guide.md`, `agent_test_map.md`) | כן (בדיקות קיימות) | MIG-00, MIG-01 |
| **1. Report** | המנוע עם כל הכללים. ‏job ‏`ui_lint_report` עם `continue-on-error: true`, שכותב טבלה ל־`$GITHUB_STEP_SUMMARY` ומוסיף annotations לחריגות **חדשות** בלבד (GitHub מציג עד ~10 בכל step) | לא | מחזור שחרור אחד |
| **2. New violations** | ‏`test/design_system/ui_lint_test.dart` חוסם על כללי שלב 1–2 עם baseline, ו־`ui_baseline_guard.yml` | כן, לחריגות חדשות | MIG-27 — **מומש** |
| **3. כללי טוקנים** | UIL-015…023, ‏UIL-029, ‏UIL-030, עם ההחרגות של §3.6. **מומש חלקית:** UIL-015…023, ‏029, ‏030 חוסמים (UIL-018 בשלב 2), כל אחד עם baseline התחלתי של החוב שלו; UIL-022 מ־MIG-21, בלי חוב | כן, לחריגות חדשות | MIG-28, אחרי שהטוקנים קיימים בקוד: MIG-04 (ריווח, אייקונים, תנועה), MIG-05 (טיפוגרפיה), MIG-07 (מצבים), MIG-08 (הגבהה, צל) |
| **4. Strict** | כלל שה־baseline שלו התרוקן עובר ל־`strict: true` בקונפיגורציה. מעתה גם `--allow-growth` לא יכול להוסיף לו | כן | לכל כלל בנפרד, כשהחוב שלו נגמר |

**הבדיקות הקיימות** (`bare_text_field_scan`, ‏`uisnack_literal_scan`, ‏`default_context_menu_scan`, ‏`rtl_icon_registered_usage`, ‏`no_scrollable_markdown`, ‏`pdf_hardcoded_colors`) עוברות למנוע אחת אחרי השנייה. כל העברה נעשית ב־commit נפרד, שמוכיח שהכלל החדש מוצא כל מה שהישן מצא, ובנוסף את הצורות שהישן פספס: ארגומנט בשם, `TextFormField`, ‏`withAlpha`. בדיקות exact-set (`quit_application_call_sites`, ‏`flutter_internal_imports`) נשארות כמות שהן.

## 7. בדיקת הכללים עצמם
לכל כלל ב־`test/design_system/fixtures/`:
- `violating_UIL-xxx.dart`: חייב להחזיר ≥1 ממצא. זה ה־canary.
- `clean_UIL-xxx.dart`: חייב להחזיר 0. כאן נכנסים המקרים הלגיטימיים: ייצוא, painter ועוטף מורשה.
- `allowed_UIL-xxx.dart`: allow תקין מחזיר 0. allow בלי נימוק מכשיל. allow שלא השתיק כלום מכשיל.
- ב־CI: PR שמכניס חריגה חדשה בקובץ ב־`lib` נכשל עם הודעה בעברית, `path:line: snippet`, הרכיב או הטוקן שצריך להשתמש בו וקישור לסעיף ב־`DESIGN_SYSTEM.md`.
- golden: PR שמשנה ריפוד ב־`ActionButton` בלי לעדכן golden נכשל ב־`goldens_windows`. הבדיקה "הזזה של פיקסל אחד בריפוד חורגת מהסף" (`test/goldens/action_button/action_button_golden_test.dart`) מקבעת זאת: אותו רכיב, התוכן זז בפיקסל בתוך אותו גודל, וההבדל מהתמונה גדול מ־0.05%.

## נספח — בדיקות הסריקה הקיימות
| בדיקה | אוכפת | הערה |
|---|---|---|
| ~~`test/widgets/text/bare_text_field_scan_test.dart`~~ | אין `TextField(` גולמי | **הועברה ל־UIL-011**, שתופס גם `TextFormField`/`EditableText` |
| ~~`test/core/messages/uisnack_literal_scan_test.dart`~~ | אין ליטרל בארגומנט הראשון של `UiSnack` | **הועברה ל־UIL-009**, שתופס גם ארגומנט בשם |
| `test/widgets/text/default_context_menu_scan_test.dart` | `SelectionArea` עם `contextMenuBuilder` | חלון של 15 שורות |
| ~~`test/widgets/rtl_icon_registered_usage_test.dart`~~ | `RtlIcon` רק לאייקונים רשומים | **הועברה ל־UIL-006**, שתופס גם `Transform.flip`/`Transform.scale(scaleX: -n)` סביב אייקון. משתנים עדיין לא נבדקים |
| `test/plugins/utils/plugin_icon_resolver_usage_test.dart` | resolver יחיד | כוללת בדיקה שהסורק אכן מוצא משהו (non-vacuity) |
| `test/settings/no_scrollable_markdown_test.dart` | `MarkdownBody` | |
| `test/settings/l10n/settings_dialog_scope_test.dart` | `settingsDialogBuilder` | חלון של 8 שורות |
| `test/core/windowing/quit_application_call_sites_test.dart` | exact set | נשארת |
| `test/widgets/text_painter_direction_test.dart` | `TextPainter.textDirection` | **לא יכולה להיכשל**, לתקן ב־PR 0 |
| `test/pdf_book/pdf_hardcoded_colors_test.dart` | אין `Colors.<hue>` בשני קבצים | יוחלף ב־UIL-015 |
| `test/utils/ui/image_decode_size_test.dart` | `cacheWidth` | נשארת |
