# תוכנית אכיפה ב־CI

> בסיס: `upstream/dev` ‏`f86ecd7c7` (עודכן מול `ac97e4490` אחרי #3794). המטרה: לזהות חריגה מהתקן לפני מיזוג, בלי לחסום שימושים לגיטימיים ובלי להכשיל את ה־CI על חוב ישן.
> הכרעות קשורות: DD-22 (golden tests), DD-23 (מנוע האכיפה).

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
- גדלי גופן וצבעים קשיחים.

## 2. עקרונות
1. **AST עדיף על regex** כשצריך להבין תחביר: שם בנאי, ארגומנט בשם, ערך ליטרלי, מחלקה עוטפת (`extends CustomPainter`) או prefix (`pw.`).
2. **מנוע אחד לכל הכללים.** הקוד ב־`tool/` והבדיקה מייבאת אותו, לפי התקדים של `test_shards`, ‏`plugin_spec_generator` ו־`settings_l10n_generator`.
3. **בלי תלויות חדשות.** `analyzer` כבר תלות dev, ו־`path` ו־`yaml` כבר קיימים.
4. **חוב ישן לא מכשיל.** baseline שיכול רק לקטון.
5. **אין השתקה גורפת.** חריג נכתב על צומת בודד, עם נימוק חובה.
6. **כל כלל נבדק בעצמו.** לכל כלל יש מקרה שחייב להיכשל ומקרה שחייב לעבור, ובדיקה שהסורק אכן מוצא משהו.

## 3. המנוע: `tool/ui_lint/` [מוצע · DD-23]

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

הגודל ההתחלתי של ה־baseline מבוסס על הסריקה הסטטית (UI_AUDIT §2.3). הערכים מעוגלים, והמספר הסופי ייקבע בהרצה הראשונה.

| ID | כלל | זיהוי | החרגות מובנות (config) | baseline משוער | שלב |
|---|---|---|---|---|---|
| UIL-001 | אין `AlertDialog`/`Dialog`/`SimpleDialog` מחוץ ל־`lib/widgets/dialogs/` | ctor | `lib/widgets/dialogs/**`, ‏`lib/settings/dialogs/list_dialog_frame.dart` | ~27 | 1 |
| UIL-002 | אין `TextButton`/`FilledButton`/`OutlinedButton`/`ElevatedButton` מחוץ ל־`lib/widgets/controls/` | ctor (כולל `.icon`/`.tonal`) | `lib/widgets/controls/**`, ‏`lib/widgets/misc/app_dropdown_field.dart` | ~26 | 1 |
| UIL-003 | לכל `IconButton` יש `tooltip:` | ctor + named arg | `IconButton.styleFrom` (לא בנאי) | ~40 | 1 |
| UIL-004 | אין `Theme.of(…).primaryColor` / `theme.primaryColor` | PropertyAccess | — | 5 | 1 |
| UIL-005 | אין `Icons.`/`CupertinoIcons.` | identifier prefix | — | 0 | 1 |
| UIL-006 | אין `RtlIcon(OtzariaIcons…)` ואין `Transform.flip` שעוטף `Icon` | ctor + ילד | `rtl_icon.dart` | 0 | 1 (מחליף את הבדיקה הקיימת) |
| UIL-007 | אין `hoverColor`/`splashColor`/`overlayColor` מחוץ ל־`lib/theme/` | named arg | `hoverColor: Colors.transparent` ב־`ListTile` עם actions (לפי התיעוד) | ~7 | 1 |
| UIL-008 | אין `ScaffoldMessenger`/`SnackBar(` | identifier/ctor | `lib/core/ui_snack.dart` | ~0 | 1 |
| UIL-009 | `UiSnack.*` מקבל מחרוזת מקטלוג, גם בארגומנט בשם | ארגומנט ליטרלי | — | ~0 | 1 (מחליף בדיקה קיימת ומרחיב אותה) |
| UIL-010 | אין `textDirection: TextDirection.rtl` ב־`Text`/`Text.rich`/`SelectableText` | ctor + named arg | חלונות `ContentDirectionality` (פסוקים בעברית במצב אנגלית), עם allow | ~15 | 1 |
| UIL-011 | אין `TextField(`/`TextFormField(`/`EditableText(` גולמי | ctor | `rtl_text_field.dart` | 0 | 1 (מרחיב בדיקה קיימת) |
| UIL-012 | אין `Card(` גולמי | ctor | `lib/widgets/layout/**` | 8 | 2 |
| UIL-013 | אין `CircularProgressIndicator(` מחוץ ל־`lib/widgets/feedback/` | ctor | `ActionButton` | ~70 | 2 |
| UIL-014 | אין `PopupMenuButton`/`showMenu(`/`MenuAnchor` מחוץ ל־`lib/widgets/misc/` ולחבילה | ctor/invocation | — | ~8 | 2 |
| UIL-015 | אין `Color(0x…)`/`Color.fromARGB`/`Colors.<hue>` מחוץ ל־`lib/theme/` | ctor/identifier | `extends CustomPainter`, ‏`pw.*`, ‏`lib/printing/**`, ‏`**/export/**`, פלטות (`app_seed_colors`, `calendar_event_colors`), `Colors.transparent`, `Colors.white`/`black` בתוך `BoxShadow` | ~40 | 3 |
| UIL-016 | אין `.withValues(alpha:)`/`.withAlpha(`/`.withOpacity(` על צבע ממשק מחוץ ל־`lib/theme/` | MethodInvocation | בתוך `BoxShadow(color:)`, ‏`CustomPainter`, ייצוא | ~110 | 3 |
| UIL-017 | אין `fontSize:` ליטרלי ב־`TextStyle` של ממשק | named arg + ליטרל | `pw.TextStyle`, קבצי תוכן הקריאה (רשימה ב־config, נגזרת מ־UI_AUDIT `justified_exceptions`), ביטוי מחושב (לא ליטרל) | ~150 | 3 |
| UIL-018 | אין `fontFamily: 'Roboto'` או ליטרל משפחה אחר מחוץ ל־`lib/theme/` | named arg + string | `AppFonts`, הגדרות קריאה | ~8 | 2 |
| UIL-019 | אין `BorderRadius.circular(n)`/`Radius.circular(n)` ליטרלי | ctor + ליטרל | `CustomPainter`, ‏`pw.*`, ביטוי מחושב | ~15 | 3 |
| UIL-020 | ריווח ב־`EdgeInsets*`/`SizedBox(width/height)` מהסולם בלבד | ctor + ליטרל | 0, ‏`double.infinity`, ביטוי מחושב, `CustomPainter` | ~540 (מתוכם ~150 מחוץ לסולם) | 3 (בהתחלה: off-scale בלבד) |
| UIL-021 | אין `EdgeInsets.only(left/right)`/`fromLTRB`/`Alignment.centerLeft/Right`/`Positioned(left/right)` | ctor + named arg | גאומטריית ציור, עם allow | ~110 | 3 |
| UIL-022 | אין השוואת רוחב לליטרל ≥100 (`width < 520`) | BinaryExpression על `.width`/`maxWidth` | קבוע `static const` עם שם בתוך הרכיב | 32 | 3 |
| UIL-023 | אין `Duration(milliseconds: n)` בפרמטר `duration:` של רכיב Animated*/Transition | ctor + parent arg | לא־UI (timeouts, debounce) לא נתפס, כי הכלל מסתכל רק על `duration:` של Widget | ~90 | 3 |
| UIL-024 | רכיב משותף לא מייבא פיצ'ר | import directive | — | ~8 | 2 |
| UIL-025 | אין `compactMenuMode` מתוך `lib/widgets/**` (אחרי DD-10) | PropertyAccess | — | ~12 | 4 |
| UIL-026 | אין `MediaQuery.withNoTextScaling`/`TextScaler.noScaling`/`RichText(` גולמי | ctor/invocation | עם allow ונימוק | ~10 | 2 |
| UIL-027 | אין `Brightness.dark`/`isDark` מחוץ ל־`lib/theme/` להחלטת צבע | identifier | פלטפורמה (סרגל מערכת), תוספים | ~57 | 4 |
| UIL-028 | `showDialog(` רק דרך `showAppDialog`/`showDialogUntilTornDown`/`settingsDialogBuilder` | invocation | `lib/widgets/dialogs/**` | ~90 | 4 |

**כלל לא נכנס לשלב 1** אם שיעור ההתראות השגויות שלו בהרצה ראשונה גבוה מ־10%. כלל כזה נשאר בדוח עד שהוא משתפר.

### 3.4 Baseline
```json
{ "version": 1,
  "rules": { "UIL-001": { "lib/foo/view/bar_dialog.dart": [
      {"scope": "_BarDialogState._confirm", "fp": "9f2c1a7e", "n": 1} ] } } }
```
- **המפתח:** כלל + קובץ + `scope` (מחלקה.מתודה מתוך ה־AST) + `fp` (hash של קוד הצומת המנורמל). אין מספרי שורות.
- **ספירה:** `n` סופר מופעים זהים.
- **הזזת קוד ופורמט** לא שוברים את ה־baseline. שינוי הביטוי עצמו כן: מי שנגע בשורה מתקן אותה.
- **חריגה שאינה ב־baseline** מכשילה את הבדיקה: "חריגה חדשה".
- **רשומה שלא נוצלה** מכשילה את הבדיקה: "baseline מת — הרץ `--update-baseline`". זה ה־ratchet, לפי התקדים של `backup_storage_coverage_test.dart:134`.
- **`--update-baseline`** רק מוחק רשומות. הוספה דורשת `--allow-growth`.
- **workflow ‏`ui_baseline_guard.yml`** (העתק של `lockfile_guard.yml`) מכשיל PR שמגדיל את מספר הרשומות, אלא אם יש עליו תווית `ui-baseline`, שמתחזק מוסיף.

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
| קבצי תוכן הקריאה: `reader_line/**`, `smart_text/**`, `continuous_reading_paragraph.dart`, `commentary_list_base.dart` (חלקי תוכן), `links_list_view.dart` (גדלים יחסיים) | טיפוגרפיה לפי הגדרות המשתמש |
| `lib/plugins/utils/fluent_icon_resolver.dart`, `*.g.dart` | קוד שנוצר אוטומטית |
| `app_seed_colors.dart`, `calendar_event_colors.dart`, מרקר | פלטות תוכן |
| `lib/core/windowing/**` (כפתורי חלון) | חיקוי של מערכת ההפעלה |
| צבע בתוך `BoxShadow(color:)` | צל מחייב שקיפות (עד DD-12) |

## 4. בדיקות חוזיות (Contract tests)

לכל רכיב משותף שמשנים, כותבים קודם בדיקת widget שמקבעת את החוזה. **פערים שקיימים היום:** אין בדיקה ישירה ל־`AppDialog` (וריאנטים), ל־`AppDialogFrame`, ל־`ListDialogFrame`, ל־`OtzariaErrorState`, ל־`SquareIconButton`/`PrimaryIconButton`, ל־`LoadingIndicator` או ל־`SettingsCard` עצמו.

| נושא | מה נבדק | איך |
|---|---|---|
| שימוש ב־Theme | רכיב ללא override מקבל את צבעי ה־component theme. שינוי זרע משנה את הרכיב בלי שינוי קוד | `pumpWidget` עם שני `ColorScheme`. בדיקה ש־`Material.color`/`TextStyle.color` נגזרים מהתפקיד |
| בהיר/כהה | ניגודיות ≥4.5 לכל זוג טקסט/רקע של הרכיב, בשני מצבי הבהירות ובכל הזרעים | הרחבה של `test/theme/app_theme_data_test.dart:101-136` |
| פריסת דיאלוג | `small`/`medium`/`large` ברוחב 360/800/1400. אין overflow. ה־X מוצג. כותרת ארוכה נחתכת עם tooltip | `tester.view.physicalSize` |
| גלילה | תוכן ארוך גולל, ושורת הפעולות נשארת קבועה | |
| מקלדת | Escape סוגר. Escape עם dirty שואל. Enter ב־`SelectionDialog` על פריט בוחר אותו (רגרסיה לבאג UI-024). Tab מקיף את שורת הפעולות | `sendKeyEvent` |
| שינוי גודל חלון | רכיב בחלונית ברוחב 300 בתוך חלון ברוחב 1400 מחליט לפי 300 | `SizedBox(width:300)` בתוך view רחב |
| תוכן ארוך | כותרת של 200 תווים, ושם ספר עם מספרים ואנגלית | |
| RTL | פריסה ב־RTL ובמצב האנגלית (`ChromeDirectionality`). חצים לפי כיוון | |
| שמירת התנהגות | לפני שכתוב: בדיקה שמתעדת את ההתנהגות הקיימת (characterization). אחרי השכתוב היא עוברת ללא שינוי, או שהשינוי מתועד ב־DD | |
| טקסט מוגדל | `TextScaler.linear(1.3)` בלי overflow | |
| נגישות | `meetsGuideline(textContrastGuideline)`, ‏`androidTapTargetGuideline`, ‏`labeledTapTargetGuideline` | `flutter_test` accessibility guidelines |

## 5. Golden tests [מוצע · DD-22]
1. **מיקום:** `test/goldens/<component>/<component>_golden_test.dart`, והתמונות ב־`test/goldens/<component>/goldens/`. ‏`failures/` נוסף ל־`.gitignore`.
2. **הרצה:** job חדש, `goldens_windows` (‏windows-2025, אותה גרסת Flutter), שמריץ `flutter test test/goldens/` ומעלה את `failures/` כ־artifact.
   - `test/goldens/` מוחרג מ־shards של Linux ב־`tool/ci/test_shards.dart::_testFiles()`, עם בדיקה לכך.
   - בתוך הבדיקות: `skip: !Platform.isWindows`, לפי התקדים של `otzaria_icons`.
3. **קונפיגורציה:** `test/goldens/flutter_test_config.dart` טוען גופנים ומתקין comparator, **ואז קורא ל־`root.testExecutable`**. אחרת אתחול המנוע ותיקיית הנתונים הזמנית הולכים לאיבוד, כי Flutter משתמש רק בקובץ הקונפיגורציה הקרוב ביותר.
4. **גופנים:** `test/support/golden_fonts.dart` טוען:
   - את גופן הממשק לפי DD-01. עד אז: Rubik בשם 'Roboto', לפי התקדים של 4 בדיקות קיימות.
   - `packages/otzaria_icons/OtzariaIcons`.
   - `packages/fluentui_system_icons/FluentSystemIcons-Regular/-Filled`.
   - `FluentSystemIcons-Light`.

   Segoe UI לא נכנס למאגר (רישיון).
5. **דטרמיניזם:**
   - `physicalSize` קבוע ו־`devicePixelRatio = 1`.
   - `EditableText.debugDeterministicCursor = true`.
   - `pumpAndSettle`.
   - זרע קבוע דרך `AppThemeData.createColorScheme`.
   - `debugDisableShadows = false` כשהצל הוא חלק מהבדיקה.
6. **Comparator:** תת־מחלקה של `LocalFileComparator`, שמקבלת הבדל של עד 0.05%. התמונות בגודל רכיב ולא מסך מלא, כדי שהאחוז יהיה משמעותי.
7. **מטריצה:** pairwise, לא מכפלה מלאה. לכל רכיב:
   - בסיס: `light-rtl-wide-1.0`;
   - `dark-rtl-wide-1.0`;
   - `light-rtl-compact-1.0` (רוחב 360 או צפיפות קומפקטית);
   - `light-rtl-wide-1.3`;
   - `dark-rtl-compact-1.3`;
   - `light-ltr-wide-1.0`, רק לכרום שתומך במצב אנגלית.

   מכפלה מלאה רק לרכיבים המרכזיים: משפחת `AppDialog`, שורת `ActionButton`, `SettingsCard`/`SettingsActionTile`, `NavTreeTile`.
8. **רכיבים בגל הראשון:**
   - דיאלוגים: single, two, warning, frame medium/large;
   - כפתורים: כל וריאנטי `ActionButton`, `BarButton`, `SquareIconButton`;
   - טפסים: `RtlTextField` עם תווית/שגיאה, `AppDropdownField`, `AppSegmentedControl`, `SettingsActionTile.*`;
   - כרטיסים: `AppCard`, `AppCard.section`, כרטיס תוצאה;
   - רשימות: `NavTreeTile`, `ItemsListView`;
   - מצבים: `LoadingIndicator`, `OtzariaEmptyState`, `OtzariaErrorState`;
   - ניווט: `AppTopBar`, `NavRailItem`, רצועת כרטיסיות.
9. **עדכון:** `flutter test --update-goldens test/goldens/<component>` על Windows בלבד, עם הגרסה המוצמדת. בנוסף, workflow ‏`workflow_dispatch` בשם "Regenerate goldens" מעלה את התמונות החדשות כ־artifact, כך שגם תורם בלי Windows יכול לעדכן. עדכון גרסת Flutter מחדש את כל התמונות באותו PR.
10. **שינוי מכוון מול רגרסיה:**
    - **רגרסיה:** בדיקת golden נכשלת ב־PR שלא שינה אף PNG.
    - **שינוי מכוון:** ה־PR משנה PNG. ‏workflow בסגנון lockfile guard מחייב את התווית `goldens-approved`, והסוקר בודק את תצוגת ה־diff של GitHub.
    - **אסור** לעדכן golden ב־PR שאינו שינוי ממשק.

## 6. הכנסה בהדרגה

| רמה | מה רץ | חוסם? | מתי |
|---|---|---|---|
| **0. תיקון התקדים** | תיקון `text_painter_direction_test` (ראו 3.2) ועדכון התיעוד שהתיישן (`AGENTS.md`, `agent_ui_reference.md`, `rtl-text-field-guide.md`, `agent_test_map.md`) | כן (בדיקות קיימות) | MIG-01 |
| **1. Report** | המנוע עם כל הכללים. ‏job ‏`ui_lint_report` עם `continue-on-error: true`, שכותב טבלה ל־`$GITHUB_STEP_SUMMARY` ומוסיף annotations לחריגות **חדשות** בלבד (GitHub מציג עד ~10 בכל step) | לא | מחזור שחרור אחד |
| **2. New violations** | ‏`test/design_system/ui_lint_test.dart` חוסם על כללי שלב 1–2 עם baseline, ו־`ui_baseline_guard.yml` | כן, לחריגות חדשות | אחרי שהכללים הגיעו לשיעור התראות שגויות נמוך |
| **3. כללי טוקנים** | UIL-015…023, עם ההחרגות של §3.6 | כן, לחריגות חדשות | אחרי DD-02/03/04/12 |
| **4. Strict** | כלל שה־baseline שלו התרוקן עובר ל־`strict: true` בקונפיגורציה. מעתה גם `--allow-growth` לא יכול להוסיף לו | כן | לכל כלל בנפרד, כשהחוב שלו נגמר |

**הבדיקות הקיימות** (`bare_text_field_scan`, ‏`uisnack_literal_scan`, ‏`default_context_menu_scan`, ‏`rtl_icon_registered_usage`, ‏`no_scrollable_markdown`, ‏`pdf_hardcoded_colors`) עוברות למנוע אחת אחרי השנייה. כל העברה נעשית ב־PR נפרד, שמוכיח שהכלל החדש מוצא כל מה שהישן מצא, ובנוסף את הצורות שהישן פספס: ארגומנט בשם, `TextFormField`, ‏`withAlpha`. בדיקות exact-set (`quit_application_call_sites`, ‏`flutter_internal_imports`) נשארות כמות שהן.

## 7. בדיקת הכללים עצמם
לכל כלל ב־`test/design_system/fixtures/`:
- `violating_UIL-xxx.dart`: חייב להחזיר ≥1 ממצא. זה ה־canary.
- `clean_UIL-xxx.dart`: חייב להחזיר 0. כאן נכנסים המקרים הלגיטימיים: ייצוא, painter ועוטף מורשה.
- `allowed_UIL-xxx.dart`: allow תקין מחזיר 0. allow בלי נימוק מכשיל. allow שלא השתיק כלום מכשיל.
- ב־CI: PR שמכניס חריגה חדשה בקובץ ב־`lib` נכשל עם הודעה בעברית, `path:line: snippet`, הרכיב שצריך להשתמש בו וקישור לסעיף ב־`DESIGN_SYSTEM.md`.
- golden: PR שמשנה ריפוד ב־`ActionButton` בלי לעדכן golden נכשל ב־`goldens_windows`.

## נספח — בדיקות הסריקה הקיימות
| בדיקה | אוכפת | הערה |
|---|---|---|
| `test/widgets/text/bare_text_field_scan_test.dart` | אין `TextField(` גולמי | מפספסת `TextFormField`/`EditableText` |
| `test/core/messages/uisnack_literal_scan_test.dart` | אין ליטרל בארגומנט הראשון של `UiSnack` | מפספסת ארגומנט בשם |
| `test/widgets/text/default_context_menu_scan_test.dart` | `SelectionArea` עם `contextMenuBuilder` | חלון של 15 שורות |
| `test/widgets/rtl_icon_registered_usage_test.dart` | `RtlIcon` רק לאייקונים רשומים | לא בודקת משתנים |
| `test/plugins/utils/plugin_icon_resolver_usage_test.dart` | resolver יחיד | כוללת בדיקה שהסורק אכן מוצא משהו (non-vacuity) |
| `test/settings/no_scrollable_markdown_test.dart` | `MarkdownBody` | |
| `test/settings/l10n/settings_dialog_scope_test.dart` | `settingsDialogBuilder` | חלון של 8 שורות |
| `test/core/windowing/quit_application_call_sites_test.dart` | exact set | נשארת |
| `test/widgets/text_painter_direction_test.dart` | `TextPainter.textDirection` | **לא יכולה להיכשל**, לתקן ב־PR 0 |
| `test/pdf_book/pdf_hardcoded_colors_test.dart` | אין `Colors.<hue>` בשני קבצים | יוחלף ב־UIL-015 |
| `test/utils/ui/image_decode_size_test.dart` | `cacheWidth` | נשארת |
