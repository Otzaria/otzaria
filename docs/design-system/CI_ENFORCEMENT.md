# אכיפה ב־CI

> המטרה: לזהות חריגה מהתקן ([DESIGN_SYSTEM.md](DESIGN_SYSTEM.md)) לפני מיזוג, בלי לחסום שימושים לגיטימיים ובלי להכשיל את ה־CI על חוב ישן. ההכרעות שמאחורי המנגנון: DD-22 (golden) ו־DD-23 (המנוע והתוויות) ב־[DESIGN_DECISIONS.md](DESIGN_DECISIONS.md).
> **מצב (5.11.2026, אחרי ביקורת האכיפה):** המנוע `tool/ui_lint` פועל עם 30 כללים, ו־741 מופעים ב־baseline. כולם חוסמים חריגה חדשה מול baseline, חוץ מ־UIL-028 (שלב 4, דוח בלבד). רמת Strict (§6) קיימת, ו־16 כללים נעולים. כלל אחד מהקטלוג (§3.3) עוד לא מומש: UIL-027 (צריך הכרעה על הזיהוי). כל כלל עבר בדיקת מוטציה על קובץ אמיתי ב־`lib`; מה שהיא לא תופסת מפורט ב־§8. golden tests רצים על Windows, ושני guards בודקים גידול ב־baseline ושינוי בתמונות ה־golden. יש בדיקות `meetsGuideline`, חוזה הגדלת טקסט ומדידת ביצועים (§4). ה־workflows לא הורצו עדיין על GitHub.

## 1. איך זה רץ היום

| רכיב | מה הוא עושה | איפה |
|---|---|---|
| `flutter analyze` | `flutter_lints` | job ‏`analyze` ב־`.github/workflows/flutter_tests.yml` |
| **הבדיקה החוסמת** | `test/design_system/ui_lint_test.dart` מריץ את כל הכללים על `lib/`, משווה ל־`tool/ui_lint/baseline.json` ונכשל על חריגה חדשה, על baseline מת ועל הערת allow פגומה | ה־shards של Linux. `tool/ci/test_shards.dart` מכניס אוטומטית כל `*_test.dart` חוץ מ־`test/goldens/` |
| דוח ui_lint | `dart tool/ui_lint_cli.dart --format=github`: טבלה ל־`$GITHUB_STEP_SUMMARY` ו־annotations לחריגות חדשות. `continue-on-error`, כלומר דוח בלבד | step ‏"UI lint report" ב־job ‏`analyze` |
| golden tests | `flutter test test/goldens/` על Windows. כשל מעלה את `failures/` כ־artifact | job ‏`goldens_windows` ב־`flutter_tests.yml` |
| גידול ב־baseline והחרגות | מכשיל PR שמוסיף מופעים ל־baseline, או מוסיף/מרחיב החרגת נתיב (`path:`) ב־`tool/ui_lint/config.yaml`, אלא אם יש עליו התווית `ui-baseline` | `.github/workflows/ui_baseline_guard.yml` |
| שינוי בתמונות golden | מכשיל PR שמשנה PNG תחת `test/goldens/`, אלא אם יש עליו התווית `goldens-approved` | `.github/workflows/goldens_guard.yml` |
| עדכון golden בלי Windows | `workflow_dispatch` שמצייר מחדש ומעלה את התמונות כ־artifact | `.github/workflows/regenerate_goldens.yml` |
| בדיקות סריקה ישנות | בדיקות שסורקות את `lib/` ולא עברו למנוע (נספח) | `test/**` |
| נגישות, הגדלת טקסט וביצועים | `meetsGuideline` והגדלת טקסט ברכיבים המשותפים (חוסמים), ומדידת ביצועים בלי ספים (מדפיסה בלבד) (§4) | ה־shards של Linux |
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

prefix של ייבוא Flutter (`import 'package:flutter/material.dart' as m;`) נמחק ב־`asCtorCall`: ‏`m.AlertDialog(...)` נבדק כמו `AlertDialog(...)`. בלי זה כל כלל, שמדלג על prefix כדי לא לתפוס את `pw.*`, היה עקיף בשורת import אחת. prefix אחר (`pw`) נשאר.

העזר `ctorCallsNamed(unit, {'AlertDialog'})` משמש את כל הכללים. גם `test/widgets/text_painter_direction_test.dart` עובר דרכו. לפני כן היא ביקרה רק `InstanceCreationExpression`, ולכן לא יכלה להיכשל.

### 3.3 קטלוג הכללים

"baseline" הוא מספר המופעים ב־`tool/ui_lint/baseline.json` ב־3.11.2026 (הראשון: כשהכלל נכנס). בכלל שעוד לא מומש: ספירת `git grep` גסה מאותו יום. כל הודעת כלל מציינת את התחליף מהתקן.

| ID | כלל | זיהוי | החרגות מובנות (config) | baseline | שלב · מצב |
|---|---|---|---|---|---|
| UIL-001 | אין `AlertDialog`/`Dialog`/`SimpleDialog` מחוץ ל־`lib/widgets/dialogs/` | ctor | `lib/widgets/dialogs/**` | 3 (ראשון 18) | 1 · **חוסם** |
| UIL-002 | אין `TextButton`/`FilledButton`/`OutlinedButton`/`ElevatedButton` מחוץ ל־`lib/widgets/controls/` | ctor (כולל `.icon`/`.tonal`/`.tonalIcon`, ‏`const`, ‏collection-if). ‏`X.styleFrom` אינו בנאי ומותר | `lib/widgets/controls/**`, ‏`app_dropdown_field.dart` | 0. תשעת הכפתורים האחרונים הוסבו (q10 Q7): `ActionButton.inline`, ‏`iconAlignment:`, ‏`ghost`, ‏`neutral`, ‏`AppIconButton`. המופע היחיד (`app_dropdown_field.dart`) מוחרג | 1 · **חוסם**, נעול (`strict`) מהיום הראשון (5.11) |
| UIL-003 | לכל `IconButton` יש `tooltip:` | ctor + named arg | `IconButton.styleFrom` (לא בנאי) | 8 (ראשון 25) | 1 · **חוסם** |
| UIL-004 | אין `Theme.of(…).primaryColor` / `theme.primaryColor` | PropertyAccess | — | 0 (ראשון 5) | 1 · **חוסם**, נעול (strict) |
| UIL-005 | אין `Icons.`/`CupertinoIcons.` | identifier prefix, גם `m.Icons.x` דרך prefix של Flutter | — | 0 | 1 · **חוסם**, נעול (strict) |
| UIL-006 | `RtlIcon` רק לאייקון כיווני שרשום ב־`rtl_icon.dart` (אף פעם לא `OtzariaIcons`), ואין `Transform.flip`/`Transform.scale(scaleX: -n)` שעוטף `Icon` | ctor + ילד + הרשימה ב־`rtl_icon.dart` | `rtl_icon.dart` | 0 | 1 · **חוסם**, נעול (strict) |
| UIL-007 | אין `hoverColor`/`splashColor`/`overlayColor` מחוץ ל־`lib/theme/` | named arg | ערך מ־`AppSurfaces.*` (למשל `hoverRow`); `hoverColor: Colors.transparent` ב־`ListTile` שיש לו `onTap:` וגם `trailing:` (JX-14). ב־`ListTile` בלי `onTap` אין ריחוף, ולכן `transparent` שם נתפס כקוד מת | 0 | 1 · **חוסם**, נעול (strict) |
| UIL-008 | אין `ScaffoldMessenger`/`SnackBar(` | identifier/ctor | `lib/core/ui_snack.dart` | 0 | 1 · **חוסם**, נעול (strict) |
| UIL-009 | `UiSnack.*` מקבל מחרוזת מקטלוג, גם בארגומנט בשם | ארגומנט ליטרלי, גם בענף של תנאי (`ok ? 'נשמר' : 'נכשל'`) | — | 0 | 1 · **חוסם**, נעול (strict) |
| UIL-010 | אין `textDirection: TextDirection.rtl` ב־`Text`/`Text.rich`/`SelectableText` | ctor + named arg | חלונות `ContentDirectionality` (פסוקים בעברית במצב אנגלית), עם allow (JX-09) | 0 (5 חריגים ב־allow: ארבעת הציטוטים במסך "אודות" ומסך שגיאת האתחול) | 1 · **חוסם**, נעול (strict) |
| UIL-011 | אין `TextField(`/`TextFormField(`/`EditableText(` גולמי | ctor | `rtl_text_field.dart` | 0 | 1 · **חוסם**, נעול (strict) |
| UIL-012 | אין `Card(` גולמי | ctor | `lib/widgets/layout/**` | 2 (ראשון 3): כרטיס הזמן בלוח השנה, כרטיס הארגון בחלון הגיוס. כרטיסי "אודות" עברו ל־`AppCard(tone: inset)` (q10 Q8a) | 2 · **חוסם** |
| UIL-013 | אין `CircularProgressIndicator(` מחוץ ל־`lib/widgets/feedback/` | ctor | `ActionButton` | 55, מהם 4 התקדמות מדודה (`value:`) שאין לה עדיין רכיב משותף | 2 · **חוסם** |
| UIL-014 | אין `PopupMenuButton`/`showMenu(`/`MenuAnchor` מחוץ ל־`lib/widgets/misc/` ולחבילה | ctor/invocation | `lib/widgets/misc/**` (מערכת התפריטים המשותפת) | 5 (שני `MenuAnchor` בדיאלוג החיפוש, סינון המאפיינים, חלון הפרסומת, תפריט ההקשר של `RtlTextField`) | 2 · **חוסם** |
| UIL-015 | אין `Color(0x…)`/`Color.fromARGB`/`Colors.<hue>`/`CupertinoColors.<hue>` מחוץ ל־`lib/theme/`. ההודעה מפנה לתפקיד: כתום/ענבר → `AppSurfaces.warning*`; ירוק "הצלחה" → `secondaryContainer` (DD-24) | ctor/identifier | רק המקרים של DD-24: תוכן (`CustomPainter` שמצייר תוכן, פלטות, מרקר), ייצוא (`pw.*`, ‏`lib/printing/**`, ‏`**/export/**`), כרום מערכת ההפעלה (`lib/core/windowing/**`); וגם `Colors.transparent`, ו־`Colors.white`/`black` בתוך `BoxShadow` | 0 (ראשון 22). שלושת האחרונים הוסבו ב־q10 Q4.1–Q4.3 | 3 · **חוסם**, נעול (`strict`) |
| UIL-016 | אין `.withValues(alpha:)`/`.withAlpha(`/`.withOpacity(` על צבע ממשק מחוץ ל־`lib/theme/` | MethodInvocation | `CustomPainter`, ייצוא, כפתורי החלון (`lib/core/windowing`), צבעי CSS של התוכן. צבע בתוך `BoxShadow(...)` נספר ב־UIL-030 | 86 (ראשון 95) | 3 · **חוסם** |
| UIL-017 | **אין `fontSize:` בקוד פיצ'ר (DD-02):** לא ליטרל, ולא `AppTokens.font*` או חשבון עליו (`fontSM - 1`). התחליף: `textTheme.<slot>` | named arg ב־`TextStyle`/`copyWith` | `lib/theme/**`; ‏`pw.TextStyle`; קבצי תוכן הספר (JX-01, JX-19), שבהם הגודל מחושב מהגדרות הקריאה | 184. הראשון היה 144 ליטרלים. הם ירדו ל־102, ואז הכלל הורחב ל־`AppTokens.font*` (עוד 101). ‏q10 Q1, Q2, Q5 ו־Q8a הורידו עוד. שלוש הכותרות הקטנות 13 בדיאלוג החיפוש ובאיתור ב־allow (DD-14) | 3 · **חוסם** |
| UIL-018 | אין `fontFamily:` ליטרלי (כולל `'Roboto'`) מחוץ ל־`lib/theme/`. רשימת ה־fallback של DD-01 חיה רק ב־`AppThemeData` | named arg עם ליטרל מחרוזת, בכל בנאי | `lib/theme/**`. גופן תוכן דרך `AppFonts.*`, מונוספייס (JX-21) דרך `AppTextStyles.monospaceFamily` | 0 | 2 · **חוסם**, נעול (strict) |
| UIL-019 | **רדיוס רק מהטוקן היחיד (DD-04):** אין `BorderRadius.circular(n)`/`BorderRadiusDirectional.circular(n)`/`Radius.circular(n)` ליטרלי. מותר `AppTokens.radius`/`borderRadiusAll`/`roundedShape` | ctor + ליטרל | `CustomPainter`, ‏`pw.*`. נבדקים גם `StadiumBorder(` ו־`CircleBorder(`, עם החריגים שאושרו (q10 Q13): הגלולה של `BarSplitButton` (`bar_split_button.dart`), ו־`CircleBorder` לכפתור אייקון בלבד — בתוך `IconButton(...)`/`IconButton.styleFrom(...)`, וב־`app_icon_button.dart` ו־`bar_button.dart` (config). רכיב עגול מטבעו (עיגול צבע) ב־allow. `BoxShape.circle` לא נבדק | 0 (ראשון 14). ידיות הגלילה בחצי העובי, מחושב (q10 Q10); גלולת הסינון של תוסף בפינות 8 (q10 Q23) | 3 · **חוסם**, נעול (`strict`) |
| UIL-020 | ריווח ב־`EdgeInsets*`/`SizedBox(width/height)` מהסולם בלבד: 2/4/8/12/16/24/32 (DD-03). ההודעה מציעה את הערך הבא כלפי מעלה (6→8, 10→12, 14→16) | ctor + ליטרל: כל ארגומנט ליטרלי של `EdgeInsets.*`/`EdgeInsetsDirectional.*`, ו־`SizedBox(width/height)` **בלי `child`** וקטן מ־32 | 0, ‏`double.infinity`, ביטוי מחושב וטוקן, `CustomPainter`, ‏`pw.*`, נתיבי הייצוא | 146 | 3 · **חוסם** (off-scale בלבד) |
| UIL-021 | אין `EdgeInsets.only(left/right)`/`fromLTRB`/`Alignment.centerLeft/Right`/`Positioned(left/right)` | ctor + named arg, ו־`Alignment.*Left/*Right` | `CustomPainter`, ‏`pw.*`, נתיבי הייצוא; ערך סימטרי (JX-20): `fromLTRB(a, b, a, c)`, `only(left: x, right: x)`, `Positioned(left: x, right: x)`; גאומטריה אחרת עם allow | 51 (ראשון 78). ‏25 חריגים ב־allow אחרי הסיווג של q10 Q15–Q17 (הידית, חלונית הכלים, `AdaptiveSidePane`, ‏`ContextOverlayPanel`, דיאלוג הדוא"ל) | 3 · **חוסם** |
| UIL-022 | אין השוואת רוחב לליטרל ≥100 (`width < 520`). בדיאלוג: `LayoutBreakpoints.compact` (DD-15) | BinaryExpression מול ליטרל ≥100, על `.width`/`.maxWidth`/`.minWidth`, או על משתנה מקומי בשם `width`, `maxWidth`, `minWidth`, `screenWidth`, `availableWidth`, `windowWidth` | קבוע `static const` עם שם בתוך הרכיב, `WindowClass`/`LayoutBreakpoints`, ‏`CustomPainter`. שם מקומי אחר (`tabWidth`) הוא מידה של רכיב ולא נבדק | 0 | 3 · **חוסם**, נעול (`strict`) |
| UIL-023 | אין `Duration(...)` ליטרלי (שאינו 0) ב־`duration:`/`reverseDuration:` של אנימציית ממשק: `Animated*`/`TweenAnimationBuilder`, ‏`AnimationController(...)`, וגלילה מונפשת (`animateTo`, `scrollTo`, `animateToPage`, `nextPage`, `previousPage`, `ensureVisible`). התחליף: `AppMotion.duration(context, AppTokens.anim*)`, ובגלילה `AppMotion.scroll`/`scrollPosition` (DD-21) | ctor/method + parent arg | לא־UI (timeouts, debounce, `Future.delayed`, `waitDuration` של Tooltip) לא נתפס, כי הכלל מסתכל רק על הבעלים של `duration:`; `Duration.zero` ו־`AppMotion.duration(...)` מותרים, גם עם `const Duration(...)` בפנים (המשכים 120/180/280 שאין להם טוקן) | 8 (ראשון 33): `AnimationController` (ממתינים להכרעה). 25 הגלילות עברו ל־`AppMotion.scroll`/`scrollPosition` ו־`ensureVisible` ל־`AppMotion.duration`: תחת הפחתת תנועה הן קופצות (q10 Q12) | 3 · **חוסם** |
| UIL-024 | **רכיב משותף לא מייבא פיצ'ר:** קובץ ב־`lib/widgets/**` לא מייבא ולא מייצא את `lib/settings/engine/`, ‏`lib/settings/settings_exports.dart`, ‏`lib/plugins/`, ‏`lib/tabs/` או `lib/models/`. ‏`settings/l10n` (settingsText) ו־`theme` מותרים. התחליף: הנתון בפרמטר, הצפיפות מ־`AppDensity`, ומה שהפיצ'ר מוסיף דרך scope או ממשק שהפיצ'ר מממש | import/export directive, ‏`package:otzaria/` ויחסי (מנורמל לנתיב) | הכלל חל רק על `lib/widgets/**`; קוד פיצ'ר רשאי לייבא פיצ'ר | 30 (`widgets/commentary`, ‏`smart_text`, תפריטי הקישורים, `ad_popup_dialog`, ‏`phone_report_tab`) | 2 · **חוסם** |
| UIL-025 | אין `compactMenuMode` מתוך `lib/widgets/**`. התחליף: `AppDensity.of(context)` (DD-10) | PropertyAccess | — | 0 | 4 · **חוסם** כי נעול (strict) |
| UIL-026 | אין `MediaQuery.withNoTextScaling`/`TextScaler.noScaling`/`RichText(` גולמי | ctor/invocation | עם allow ונימוק (JX-10) | 0. ‏RichText עם `textScaler:` אינו גולמי; החריג היחיד, טור הסת"ם בתיקון קוראים, ב־allow (JX-10) | 2 · **חוסם**, נעול (strict) |
| UIL-027 | אין `Brightness.dark`/`isDark` מחוץ ל־`lib/theme/` להחלטת צבע | identifier | פלטפורמה (סרגל מערכת), תוספים | 31 אתרים בזיהוי לפי שם. רובם אינם החלטת צבע בפיצ'ר (בניית הערכה, סרגל המערכת, כפתורי החלון, גשר התוספים, מסנן עמוד ה־PDF), ורק כ־3 הם כאלה | 4 · **לא מומש**: שיעור ההתראות השגויות גבוה בהרבה מ־10%. צריך הכרעה איך לזהות "החלטת צבע", למשל תנאי שענפיו צבעים, או רשימת נתיבים מוחרגים |
| UIL-028 | `showDialog(` רק דרך `showDialogUntilTornDown`/`settingsDialogBuilder` והעזרים שעוטפים אותם | invocation | `lib/widgets/dialogs/**` | 54 (showDialog שה־builder שלו אינו settingsDialogBuilder) | 4 · **דוח בלבד** |
| UIL-029 | **גודל אייקון מטוקן (DD-03):** אין `size:` ליטרלי ב־`Icon(`, אין `iconSize:` ליטרלי, ואין `AppTokens.font*` כגודל אייקון. התחליף: `AppTokens.icon*` | ctor + named arg: `size:` ב־`Icon`/`RtlIcon`/`ImageIcon`, ו־`iconSize:` בכל מקום | `CustomPainter`, ‏`pw.*`, ייצוא, מעבדי תוכן (`smart_text`, `reader_line`, JX-19); ביטוי מחושב | 105 (ראשון 223). 18 עבר ל־`iconSM` ‏(16), ‏22 ל־`iconMD` ‏(20), ו־56/64 ל־`iconXL` ‏(48) (q10 Q9, סקירת 4.11 סבב רביעי); נשארו ערכים בגודל של טוקן שעוד לא הוסבו, ו־15, 44 ואחרים | 3 · **חוסם** |
| UIL-030 | **הגבהה וצל מהטוקנים (DD-12):** `elevation:` רק `0` או `AppTokens.elevation*`, ואין `BoxShadow(` מחוץ ל־`lib/theme/` | named arg + ctor | נייר PDF (JX-05), `CustomPainter`, גובה גאוגרפי שאינו ארגומנט של Widget (JX-16) | 4 `BoxShadow`: אנימציות הדגשה וחגיגת סיום. שני צללי הנייר של עמוד PDF ב־allow כתוכן (JX-05, q10 Q11). הגבהה ליטרלית: 0. שקיפות בתוך `BoxShadow` נספרת כאן ולא ב־UIL-016 | 3 · **חוסם** |
| UIL-031 | **פס גלילה רק דרך `AppScrollbar` (הכרעת בעל הפרויקט 4.11):** אין `Scrollbar(`/`RawScrollbar(`/`CupertinoScrollbar(` גולמי. פס גולמי קובע את הצד לפי הכיוון (שמאל בעברית) ומצויר מעל התוכן | ctor | `lib/widgets/feedback/app_scrollbar.dart` (הרכיב עצמו). פס אופקי ב־allow | 0. שמונת הפסים האנכיים הוסבו ל־`AppScrollbar`; שני הפסים האופקיים (תצוגת הטקסט בהגדרות החיפוש, תיקון קוראים) ב־allow | 2 · **חוסם**, נעול (`strict`) |

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
- **מה חוסם:** `ui_lint_test` מכשיל חריגה חדשה בכל כלל שהשלב שלו (`UiLintRule.stage`) עד `blockingStage` (היום 3), ובכל כלל נעול (`strict`) בכל שלב. 28 מ־30 הכללים בשלבים 1–3. בשלב 4: ‏UIL-025, שחוסם כי הוא נעול, ו־UIL-028, שמופיע בדוח בלבד. baseline מת והערת allow פגומה מכשילים בכל כלל.
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
5. כל ה־allow מופיעים בדוח עם הנימוק. היום יש 45 בקוד, מהם 25 של UIL-021. הוספת allow אינה דורשת תווית: היא גלויה ב־diff ונסקרת כקוד.
6. **מתוכנן, לא מומש:** תקרה לכל כלל (`max_allows`) ושדות בעלים ומעקב (issue) לכל החרגה. היום החרגה נושאת נימוק בלבד, והבעלות היא של מי שאישר את ה־PR.

**לפי נתיב או הקשר:** רק ב־`config.yaml`, ותמיד עם `reason:` (היום 60 החרגות). שם נרשמים גם עוטפים מורשים, כמו `RtlTextField` שבונה `TextField`. החרגה בלי `reason` היא שגיאת קונפיגורציה.

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
- `components_contract_test.dart`: `AppCard` (כולל `tone: inset`), `MetaChip`, `AppSectionLabel`, `BarButton`, מצבי המשוב, `SquareIconButton`, וצורת כפתור האייקון: שקוף עגול, עם רקע משלו 8 (q10 Q22).
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
| נגישות אוטומטית | `meetsGuideline(labeledTapTargetGuideline)` ו־`textContrastGuideline` בכל רכיב, ו־`androidTapTargetGuideline` ברכיבי מגע, בבהיר ובכהה | קיים (`a11y_guidelines_test`). 12 מקרים ב־`skip` ככשל ידוע, עם המספרים שנמדדו: ארבעה רכיבים קטנים מ־48×48 במגע (`BarButton.icon` ב־`AppTopBar`, ‏`AppTogglePill`, ‏`StatusChip`, כפתור הניקוי בשדה החיפוש), שממתינים להכרעה; ו־`NavRailItem` בבהיר, שנמדד 2.78:1 בפיקסלים אף שצבע התווית 8.9:1 (נבדק ישירות, ועובר). אחרי שינוי באחד הרכיבים מריצים שוב ומסירים `skip` שעבר |
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
6. **Comparator:** `TolerantGoldenFileComparator` (`test/goldens/golden_harness.dart`), תת־מחלקה של `LocalFileComparator` שמקבלת הבדל של עד 0.05% מהפיקסלים. תמונה בגודל אחר נכשלת תמיד. התמונות בגודל רכיב ולא מסך מלא, כדי שהאחוז יהיה משמעותי. שינוי ריפוד של פיקסל אחד ב־`ActionButton` הוא 0.51% ונכשל. **הסף נשאר 0.05% (DD-22, השלמה 2.11).** פרט שקטן מהסף, כמו X, תג אייקון או אייקון בכפתור, נבדק בבדיקת widget רגילה (`golden_details_contract_test.dart`), ולא בהידוק הסף.
7. **מטריצה:** pairwise, לא מכפלה מלאה. לכל רכיב: בסיס `light-rtl-wide-1.0`, ‏`dark-rtl-wide-1.0`, ‏`light-rtl-compact-1.0`, ‏`light-rtl-wide-1.3`, ‏`dark-rtl-compact-1.3`, ו־`light-ltr-wide-1.0` רק לכרום שתומך במצב אנגלית. מכפלה מלאה רק לרכיבים המרכזיים.
8. **מה מכוסה:** היום `ActionButton` (כל הווריאנטים, בהיר וכהה) ו־`AppDialog` (`twoActions` בהיר וכהה, `warning`). **מתוכנן,** לפני השינוי החזותי הבא של כל רכיב: `BarButton`, `SquareIconButton`, `RtlTextField`, `AppDropdownField`, `AppSegmentedControl`, שורות ההגדרה, `AppCard`, `ResultCardFrame`, `NavTreeTile`, `ItemsListView`, מצבי המשוב, `AppTopBar`, `NavRailItem` ורצועת הכרטיסיות.
9. **עדכון:** `flutter test --update-goldens test/goldens/<component>` על Windows בלבד, עם הגרסה המוצמדת. מי שאין לו Windows מריץ את "Regenerate goldens" (`regenerate_goldens.yml`) ומוריד את ה־artifact. עדכון גרסת Flutter מחדש את כל התמונות באותו PR.
10. **שינוי מכוון מול רגרסיה:**
    - **רגרסיה:** בדיקת golden נכשלת ב־PR שלא שינה אף PNG.
    - **שינוי מכוון:** ה־PR משנה PNG. ‏`goldens_guard.yml` מחייב את התווית **`goldens-approved`** (DD-23), והסוקר בודק את תצוגת ה־diff של GitHub. כשב־base אין אף תמונת golden, וה־PR רק מוסיף תמונות, ה־PR הוא זה שמכניס את התשתית, וה־guard עובר. התמונות נבדקות בסקירה של אותו PR.
    - **אסור** לעדכן golden ב־PR שאינו שינוי ממשק.

## 6. הכנסה בהדרגה

| רמה | מה רץ | חוסם? | מצב |
|---|---|---|---|
| **1. Report** | `ui_lint_cli --format=github` עם `continue-on-error`: טבלה ל־`$GITHUB_STEP_SUMMARY` ו־annotations לחריגות חדשות (GitHub מציג עד ~10 בכל step) | לא | קיים |
| **2. New violations** | `test/design_system/ui_lint_test.dart` חוסם חריגה חדשה מול ה־baseline, ו־`ui_baseline_guard.yml` חוסם גידול ב־baseline בלי תווית | כן, לחריגות חדשות | קיים |
| **3. כללי טוקנים** | UIL-015…023, ‏UIL-029, ‏UIL-030, עם ההחרגות של §3.6, כל אחד עם baseline של החוב שלו | כן, לחריגות חדשות | קיים |
| **4. Strict** | כלל שה־baseline שלו התרוקן ננעל, כך שגם `--allow-growth` עם תווית לא יכול להוסיף לו | כן | **קיים:** `strict: true` ב־`config.yaml`. כלל נעול חוסם בכל שלב, ו־`--allow-growth` לא כותב לו רשומות. ‏ui_lint_test דורש strict לכל כלל בלי רשומות baseline, ואוסר רשומות בכלל נעול. נעולים (16): UIL-002, 004, 005, 006, 007, 008, 009, 010, 011, 015, 018, 019, 022, 025, 026, 031 |

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

| פער | השפעה | למה לא נסגר |
|---|---|---|
| UIL-028 (`showDialog` גולמי) בשלב 4, לא נעול | `showDialog` חדש עובר את ה־CI; מסומן רק ב־annotation של הדוח | 54 מופעים בחוב, והכלל בדוח עד שההמרה מתקדמת. הפיכה לחוסם = להוריד אותו לשלב 3 |
| UIL-027 (`Brightness.dark`/`isDark`) לא מומש | החלטת צבע לפי בהירות בקוד פיצ'ר לא נתפסת | שיעור התראות השווא בזיהוי לפי שם גבוה מ־10% (§3.3) |
| `IconThemeData(size: n)`, ‏`TextStyle.apply(fontSizeDelta:)`, ‏`SizedBox.square(dimension:)` | גודל אייקון, גופן או ריווח ליטרלי בצורה הזו לא נתפס ב־UIL-029/017/020 | `IconThemeData(size:)` קיים פעמיים ב־lib (רשימת האייקונים ושכבת האבחון), והרחבת UIL-029 הייתה מגדילה את ה־baseline. השאר: לא חלק מהקטלוג |
| `LinearProgressIndicator`, ‏`CupertinoAlertDialog`, ‏`focusColor`/`highlightColor` | מחוץ להיקף של UIL-013/001/007 | הקטלוג לא אוסר אותם. ‏`LinearProgressIndicator` (כ־9 מופעים) מחכה לרכיב התקדמות מדודה משותף |
| `Alignment(-1, 0)` מספרי, `BorderRadius.only(topLeft:)`/`horizontal(left:)` | כיוון פיזי שלא בשם (`centerLeft`) ולא ב־`EdgeInsets`/`Positioned` לא נתפס ב־UIL-021 | לא חלק מהקטלוג; נדיר |
| הערת allow | מוסיפים בלי תווית, בלי תקרה ובלי בעלים | מכוון: הנימוק גלוי ב־diff ונסקר. התקרה (`max_allows`) מתוכננת (§3.5) |
| החלפת חוב באותו `scope` | תיקון חריגה אחת והוספת אחרת באותה מתודה, עם `--allow-growth`, לא נספר כגידול | ה־guard סופר לפי כלל, קובץ ו־`scope` בלי `fp`, כדי ששינוי ביטוי לא ייחשב גידול (§3.4). ה־diff של `baseline.json` עדיין נסקר |
| golden: סף, `skip` או מחיקת בדיקה | שינוי ב־`golden_harness.dart` או בבדיקה (בלי PNG) לא דורש את `goldens-approved` | הסף מקובע ב־`golden_comparator_test.dart`, ושינוי בו נראה ב־diff; מחיקת בדיקה מוחקת בדרך כלל גם PNG ואז נתפסת |
| בדיקות סריקה ישנות (נספח) | regex על שורות, בלי AST: למשל `ActionButton.warning (` עם רווח, או בתוך הערה (התרעת שווא) | עוברות למנוע אחת אחרי השנייה (§6) |
| הגנת ענף | אי אפשר לראות מתוך המאגר אם ה־jobs (`Test (shard n/5)`, ‏`ui_lint baseline growth`, ‏`Golden image changes`, ‏`Goldens (Windows)`) מוגדרים כ־required ב־GitHub | נבדק רק ב־YAML; ה־workflows לא הורצו עדיין על GitHub |

## נספח — בדיקות הסריקה הקיימות
| בדיקה | אוכפת | הערה |
|---|---|---|
| ~~`test/widgets/text/bare_text_field_scan_test.dart`~~ | אין `TextField(` גולמי | **הועברה ל־UIL-011**, שתופס גם `TextFormField`/`EditableText` |
| ~~`test/core/messages/uisnack_literal_scan_test.dart`~~ | אין ליטרל בארגומנט הראשון של `UiSnack` | **הועברה ל־UIL-009**, שתופס גם ארגומנט בשם |
| `test/widgets/text/default_context_menu_scan_test.dart` | `SelectionArea` עם `contextMenuBuilder` | חלון של 15 שורות |
| ~~`test/widgets/rtl_icon_registered_usage_test.dart`~~ | `RtlIcon` רק לאייקונים רשומים | **הועברה ל־UIL-006**, שתופס גם `Transform.flip`/`Transform.scale(scaleX: -n)` סביב אייקון. משתנים עדיין לא נבדקים |
| `test/plugins/utils/plugin_icon_resolver_usage_test.dart` | resolver יחיד | כוללת בדיקה שהסורק אכן מוצא משהו |
| `test/settings/no_scrollable_markdown_test.dart` | `MarkdownBody` | כוללת בדיקה שהסורק תופס `Markdown(` ולא `MarkdownBody(` |
| `test/settings/l10n/settings_dialog_scope_test.dart` | `settingsDialogBuilder` | חלון של 8 שורות |
| `test/core/windowing/quit_application_call_sites_test.dart` | exact set | נשארת |
| `test/widgets/text_painter_direction_test.dart` | `TextPainter.textDirection` | דרך `ctorCallsNamed` (§3.2), ולכן מוצאת גם `TextPainter(...)` בלי `new` |
| `test/pdf_book/pdf_hardcoded_colors_test.dart` | אין `Colors.<hue>` בשני קבצים | יוחלף ב־UIL-015 |
| `test/utils/ui/image_decode_size_test.dart` | `cacheWidth` | נשארת |
| `test/design_system/agent_docs_paths_test.dart` | כל נתיב ב־`AGENTS.md`, בתבנית ה־PR, ב־`agent_ui_reference.md`, ב־`agent_test_map.md` ובמסמכי התקן קיים | קטע מחוק `~~…~~` מתעד קובץ שהוסר ולא נבדק |
