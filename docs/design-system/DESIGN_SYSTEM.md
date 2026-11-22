# מערכת העיצוב של אוצריא — מסמך התקן

> **מעמד:** גרסה 1.6 (19.11.2026). כל ההכרעות DD-01..32 אושרו בידי בעל הפרויקט, ונימוקיהן ב־[DESIGN_DECISIONS.md](DESIGN_DECISIONS.md). האכיפה האוטומטית: [CI_ENFORCEMENT.md](CI_ENFORCEMENT.md).
> **קהל:** כל מי שכותב קוד ממשק באוצריא: מפתחים, סוקרים וסוכני AI. מתחילים ב"מתחילים כאן" שלמטה. סעיף 8 מסביר איך עובדים לפי התקן בפועל.
> **גרסאות:**
> - **1.0 (1.11.2026):** נעילת ההכרעות של חמשת סבבי ההכרעה.
> - **השלמות 2.11 ו־3.11:** ארבעה סבבי המשך שעלו מהמימוש, משולבים בסעיפים ומסומנים "השלמה 2.11" או "השלמה 3.11". פירוטם ב־DESIGN_DECISIONS.
> - **1.1 (3.11.2026):** סימוני המימוש נבדקו מול הקוד ב־`design-system/stage-b`. מה שמומש מסומן **קיים**, ומה שמומש בחלקו מסומן **חלקי** עם מה שנשאר.
> - **1.2 (3.11.2026):** תשובות הסבב החמישי (q10) משולבות, מסומנות "q10", ומספרי ה־baseline עודכנו.
> - **1.3 (5.11.2026):** תשובות q11, ‏q12 וחמשת סבבי "סקירת 4.11" משולבות (ערכת "לבן", מסכים קטנים, צפיפות "אוטומטית", כרטיסי ההערות, אייקונים 20). נוסף "מתחילים כאן". מה שעוד פתוח מרוכז בסוף DESIGN_DECISIONS.
> - **DD-32 (18.11.2026, נכנס מהענף הראשי לפני סבב ההשלמה):** מתג או בורר (DD-32, §3.3): שני מצבים הפכים מוצגים כמתג, ומצב "לפי הגדרה אחרת" כמתג ותג.
> - **1.4 (18.11.2026):** סבב "השלמת מערכת העיצוב". נוספו: מדיניות "אין מקום" ותשתית בדיקות ה־responsive (§5.4, ‏§5.5), מגע ופלטפורמות עם המגבלות הידועות (§5.6, ‏§5.7), הידוע במצב לילה ובנגישות (§6.4, ‏§7), ומדריך QA קצר (§8.8). מספרי ה־baseline ומצב ההחלטות עודכנו לפי הקוד. החלטות שעוד ממתינות לבעל הפרויקט מסומנות ⚠ ומפורטות ב־DESIGN_DECISIONS ("שאלות פתוחות").
> - **1.5 (18.11.2026):** בעל הפרויקט הכריע בכל 71 סעיפי ההכרעה של סבב ההשלמה, והמימוש משולב כאן ומסומן "הוכרע (18.11.2026)". נוספו: חריגות מותרות לשטחי מגע (§2.5.6), זיהוי מגע ותפריט הקשר באצבע, במקלדת ובעט (§5.6), טבלת רוחבי חלוניות הצד `SidePaneSpecs` (§2.5.7), סרגל עליון עם עדיפויות ותקרת הגדלה 1.3 (§5.4, ‏§6.4), טוקני הבחירה, פס הגלילה ו־`readableInkOn` (§2.1.5), עובי מסגרת (§2.5.3), הרכיבים `AppColorSwatch`, ‏`AppInlineLink`, גוון `tertiary` ומצב "עם רקע" ל־`AppIconButton` (§3.2–3.5), ניסוחי מחיקה והסרה (§3.1), ומטריצת הפלטפורמות המעודכנת (§5.7). מה שעוד לא מומש בקוד מסומן "טרם מומש" בטקסט וב־DESIGN_DECISIONS ("הכרעות 18.11.2026").
> - **1.6 (19.11.2026):** סבב ג' של ההשלמה: מומש מה שסומן "טרם מומש" ב־1.5, ושוכלל בהכרעות הבעלים מ־19.11. ידית שינוי גודל גלויה ובשטח לחיצה 32 במגע, חלונית צפה ברוחב 350, פתיחה אוטומטית של חלונית הניווט רק כשיש מקום, וסף 600 בלוח השנה (§5.3.1). מצביע אחרון ב־Android וב־iOS, עט בכל אזורי הבחירה, תפריט מקלדת על שורת הבחירה, וכפתורי 40 בשדה חיפוש במגע כשיש מקום (§2.5.6, ‏§5.6). תקרת 1.3 רק לכותרת הסרגל, מיזוג שני ה־⋮ בקורא, "סגור" ב־`AppDialog.singleAction` נשאר כפתור בולט (הוכרע סופית 19.11, כרטיס 212; בלי שינוי קוד), "נסה שוב" גם ב"אין נתוני ספרייה" ותיאור בכרטיס קטגוריה (§3.4–3.6, ‏§5.4, ‏§6.4). חבילת תפריט ההקשר נסרקת ב־ui_lint ונקראת `AppMenuVisuals`, ואוספי גופנים `.ttc`/`.otc` ותפריט "עריכה" ב־macOS (§5.7). עודכן באותו יום בסבב ג'־2: תקרה נפרדת 1.6 לשדות חיפוש בסרגל (`AppTopBarField`, §6.4), חלונית צפה ברוחב 350, מקשי הקיצור של תפריט "עריכה" כבויים בדגל const עד בדיקה על Mac, וב־iOS גופני מערכת לתצוגה בלבד והוספת גופן מקובץ (§5.7). בסבב ג'־3: כפתור "שתף" במובייל בסרגל הבחירה ובשורת הפעולות של הקורא (`share_plus`, §5.6).

## מתחילים כאן

**לפני שכותבים ממשק** (מפתח שמוסיף מסך, או סוכן AI שמקבל משימת UI):
1. מוצאים ברשימה שלמטה את הרכיב לכל צורך. רכיב קיים קודם לכל קוד חדש. הסעיף שבסוגריים מפרט וריאנטים והתנהגות.
2. כל ערך (צבע, ריווח, רדיוס, גודל אייקון, גופן, משך) נלקח מטוקן או מתפקיד: הטבלאות ב־§2, והמיפוי "אני צריך… ← משתמש ב…" ב־§8.1. אין מספרים ואין צבעים בקוד פיצ'ר.
3. החלטת פריסה לפי `WindowClass` או לפי ה־constraints שהרכיב קיבל, לא לפי פלטפורמה או כיוון המסך (§5).
4. בודקים: `dart tool/ui_lint_cli.dart`, ‏`flutter test test/design_system/ui_lint_test.dart` והבדיקות של הקבצים שנגעו בהם (§8.6, ‏§8.7). בהיר, כהה ו"לבן"; RTL; רוחב 320 ו־360 ורוחב מלא; טקסט ×1.3 ו־×2.0. מסך חדש מקבל סצנת `testResponsive` (§5.5). הצ'קליסט המלא: §8.8.
5. רכיב משותף חדש רק לפי רשימת הבדיקה ב־§8.5. כשאין רכיב מתאים והשימוש ייחודי לפיצ'ר אחד, בונים אותו בפיצ'ר מרכיבי הקטלוג.

**איזה רכיב לאיזה צורך:**

| צורך | רכיב | § |
|---|---|---|
| שאלת כן/לא, אזהרה, הודעה, קלט, בחירה מרשימה, 3+ פעולות | `showTwoActionsDialog` / `showWarningDialog` / `showSingleActionDialog` / `showInputDialog` / `showSelectionDialog` / `showChoiceDialog` | 3.1 |
| דיאלוג עם תוכן משלו (טופס, רשימה, לשוניות) | `AppDialogFrame(size: AppDialogSize.small\|medium\|large\|full)`, נפתח ב־`showDialogUntilTornDown` | 3.1 |
| כפתור טקסט: ראשי / משני וביטול / שקט / בתוך הודעה | `ActionButton.recommended` / `.neutral` / `.ghost` / `.inline` | 3.2 |
| כפתור הרסני: בדיאלוג / על מסך הגדרות | `ActionButton.warning` / `.warningSoft` | 3.2 |
| כפתור אייקון / בסרגל | `AppIconButton(size:, tooltip:)` / `BarButton` בתוך `ResponsiveActionBar` | 3.2, 3.6 |
| תפריט פעולות או בחירה מתפריט | `AppPopupMenuButton`, או `showAnchoredAppMenu` מעוגן לרכיב | 3.3 |
| שדה טקסט / חיפוש | `RtlTextField` / `OtzariaSearchField` | 3.3 |
| 2–4 אפשרויות / רשימה נפתחת / מתג קטן / פילטר | `AppSegmentedControl` (בהגדרות `SettingsSegmentedTile`) / `AppDropdownField` / `AppTogglePill` / `FilterChip` | 3.3 |
| כרטיס מידע / כרטיס תוצאה / קבוצת שורות | `AppCard(tone:)` / `ResultCardFrame` / `AppCard.section` | 3.4 |
| תגית או מונה / כותרת מקטע / חץ הרחבה | `MetaChip(tone:)` / `AppSectionLabel` / `ExpandingChevron` | 3.4 |
| קישור בתוך טקסט / בחירת צבע | `AppInlineLink` / `AppColorSwatch` | 3.4 |
| שורת הגדרה | `SettingsCard` עם `SettingsSwitchTile`, `SettingsDropdownTile`, `SettingsSegmentedTile` וכו' | 3.4 |
| הודעה קצרה / באנר במסך | `UiSnack.show(<Module>Messages.x)` / `AppInfoBanner(tone:)` | 3.5 |
| טעינה / ריק / שגיאה | `LoadingIndicator` (`.inline()`, `SkeletonLines`) / `OtzariaEmptyState` / `OtzariaErrorState` | 3.5 |
| מסך לוח או כלי | `AppTopBar` + `panelBackground`, או `ToolScaffold` לכלי חיפוש | 3.6 |
| חלונית ניווט / חלונית צד או צפה | `NavSidePanel` / `AdaptiveSidePane`, `ContextOverlayPanel` | 3.6 |
| פס גלילה מפורש | `AppScrollbar` (בלי כלום: `EdgeScrollbarBehavior` של האפליקציה) | 6.1 |

**חמישה דברים שאסור לכתוב** (ui_lint חוסם את רובם):

```dart
// ❌                                         // ✅
Color(0xFF8A6D3B) / Colors.grey              // cs.onSurfaceVariant, AppSurfaces.hoverRow(cs)
TextStyle(fontSize: 13)                      // Theme.of(context).textTheme.bodySmall
EdgeInsets.only(left: 10)                    // EdgeInsetsDirectional.only(start: AppTokens.spaceSMD)
Icon(icon, size: 22)                         // Icon(icon, size: AppTokens.iconMD)
AlertDialog(...) / TextButton(...) / Card()  // showTwoActionsDialog / ActionButton.neutral / AppCard
```

**כש־ui_lint נכשל:** מתקנים לפי התחליף שבהודעה. רק כשהשימוש מוצדק (תוכן, ייצוא, חיקוי מערכת ההפעלה) מוסיפים `// ui-lint: allow UIL-xxx — <נימוק>`. לא מוסיפים חריגה משלך ל־baseline: הגדלת baseline דורשת את התווית `ui-baseline` ממתחזק, ושינוי תמונת golden את התווית `goldens-approved` (§8.6).

## 0. איך לקרוא את המסמך

**סוג הכלל:**

| סימון | משמעות | מה עושים |
|---|---|---|
| **[מחייב]** | כלל התקן: הוכרע ב־DD, או כלל הנדסי שאין עליו מחלוקת. | פועלים לפיו. סוקר רשאי לחסום PR שמפר אותו. |
| **[אסור]** | דפוס שאין להוסיף בקוד חדש. | קוד קיים שמפר את הכלל רשום ב־baseline של ה־CI ויוסר בהדרגה. |

**מצב המימוש** (בכל סעיף או שורה):

| סימון | משמעות | מה עושים |
|---|---|---|
| **קיים** | הטוקן, הרכיב או ההתנהגות כבר בקוד. | משתמשים בו. |
| **חלקי** | הרכיב או הטוקן קיים, אבל חלק מהקוד עוד לא עבר אליו. מה שנשאר מצוין לצידו. | קוד חדש משתמש בו. קוד ישן עובר אליו כשנוגעים בו. |
| **יעד** | הוכרע, אבל עוד לא בקוד. | קוד חדש משתמש ברכיב או בטוקן הקיים הקרוב ביותר (מצוין לצידו). לא משנים מראה קיים בלי commit מיישם עם תמונות. |
| **⚠** | ממתין להכרעה של בעל הפרויקט (הרשימה בסוף DESIGN_DECISIONS). | לא מיישמים את החלק המסומן עד תשובה. |

**ערך שלא נקבע בהכרעה** (גוון מדויק, ריפוד שלא נשאל עליו) נקבע ב־commit המיישם, עם תמונות לפני/אחרי לאישור בעל הפרויקט. המסמך לא ממציא ערכים.

**מקור אמת:** לכל סוג ערך יש מקור אחד בקוד, וטבלה מרוכזת שלהם מופיעה בנספח א'. כשהמסמך והקוד סותרים בערך **קיים**, הקוד ב־`lib/theme/` קובע את הערך, ומתקנים את המסמך. בערך **יעד**, ההכרעה קובעת.

**מה לא נכלל:** טיפוגרפיה וצבעים של **תוכן הספרים** כפופים להגדרות הקריאה של המשתמש, ולא לטוקני הממשק. ראו סעיף 2.4.2.

**מספרים "היום"** במסמך הם ספירות ה־baseline של `tool/ui_lint` ב־18.11.2026 (652 רשומות ב־12 כללים; `CI_ENFORCEMENT.md` מכיל את הטבלה, ובדיקה אוטומטית שומרת עליה מעודכנת). המצב העדכני: `dart tool/ui_lint_cli.dart`.

---

## 1. עקרונות העיצוב

### 1.1 עקרונות מחייבים

1. **מקצועי, נקי ועקבי.** אותו תפקיד נראה ומתנהג אותו דבר בכל מקום. דיאלוג אישור במסך ההגדרות זהה לדיאלוג אישור בכלי לוח השנה.
2. **עברית ו־RTL הם מצב הבסיס, לא תרגום.** כל רכיב נבנה ונבדק קודם ב־RTL. מצב LTR קיים בשני מקרים בלבד: מצב האנגלית של כרום הממשק (`ChromeDirectionality`, DD-20), ותוכן שהוא LTR מטבעו, כמו נתיבים, כתובות, מזהים וגרסאות.
3. **הקריאה במרכז.** התוכנה היא כלי קריאה וחיפוש בספרים. אזור הקריאה שקט, וכל ממשק אחר משרת אותו. צבע, צל ותנועה לא מתחרים בטקסט.
4. **צפיפות מאוזנת לשימוש ממושך במחשב.** ברירת המחדל מותאמת לעכבר ולמקלדת ולשעות עבודה ארוכות. מגע נתמך דרך שטחי לחיצה מינימליים (סעיף 2.5.6) ולא דרך הגדלה כללית של כל הממשק.
5. **הבחנה ברורה בין תוכן, ניווט ופעולות.** שלושה אזורים, לכל אחד משטח משלו (DD-18, סעיף 2.1): רקע קריאה, רקע לוח לכלים, ורקע חלונית לצד הקריאה.
6. **נגישות היא חלק מההגדרה של רכיב.** רכיב משותף שאין לו שם נגיש, פוקוס מקלדת ומצב (נבחר, מורחב, מושבת) לא נחשב שלם.
7. **ביצועים.** אין עטיפות Widget שנועדו רק "ליישור", אין חישובי עיצוב בתוך פריטי רשימה גדולה, ואין `TextPainter` בלולאה בתוך כפתור.
8. **שימוש חוזר לפני שכפול.** לפני שכותבים רכיב, מחפשים את הקיים בקטלוג (סעיף 3). רכיב חדש נוסף רק לפי הכללים בסעיף 8.5.
9. **שינוי סגנון גלובלי במקום אחד.** החלפת צבע, רדיוס, גופן או צפיפות נעשית ב־`lib/theme/` בלבד, בלי לגעת בקבצי פיצ'רים.
10. **מינימום חריגים.** חריג מותר רק עם הערת `ui-lint: allow` ונימוק (סעיף 8.6, `CI_ENFORCEMENT.md` §3.5), או כשהוא רשום ברשימת ההחרגות שבהגדרות ה־CI.

### 1.2 הכרעות סגנון שאושרו

ההעדפות שהסבבים הקודמים (#3322, #3539, #3794) הנהיגו הן עכשיו תקן **[מחייב]**:
- רצועת כותרת (`AppDialogHeader`) ותג אייקון **בכל** דיאלוג, כולל `small` (DD-07 B). ב־`small` אין X (השלמה 2.11).
- כפתור ביטול בסגנון `neutral` (tonal) (DD-09 A). פעולה מסוכנת: `ActionButton.warning`, כפתור מלא ברקע `error` (השלמה 3.11), ועל מסך הגדרות `ActionButton.warningSoft` (4.11).
- כותרות מקטע בצבע `primary`, דרך `AppSectionLabel` (DD-14 A). חריג: בדיאלוג החיפוש ובאיתור המקורות נשארות הכותרות הקטנות שלהם, 13 (השלמה 2.11).
- מסגרת `outlineVariant` ולא צל לכרטיסים (DD-12 A).
- רדיוס אחד, 8, לכל רכיב מלבני, כולל צ'יפים, כפתור סרגל, כפתור אייקון בלבד ותג אייקון (DD-04 A, השלמה 19.11). הריחוף של `IconButton` גולמי בפינות 8 דרך ערכת הנושא. חריג אחד: `BarSplitButton` (אייקון וחץ) נשאר גלולה (השלמה 2.11).
- תוויות קטנות מהסולם: `AppTogglePill` ותווית הסינון של תוסף ב־`labelMedium` (12), ותווית פריט בעמודת הניווט ב־`labelSmall` (11) (q10 Q1, Q2, Q23).

---

## 2. מערכת הטוקנים

### 2.0 מבנה הטוקנים בקוד

| קובץ | מחלקה | תוכן |
|---|---|---|
| `lib/theme/app_tokens.dart` | `AppTokens` | ריווח 2/4/8/12/16/24/32, טוקנים סמנטיים (`cardPadding`, `listItemGap`, `dialogPadding`), רדיוס 8, גופן 11–22 (לשכבת ה־Theme בלבד), גדלי אייקון 14–48, `focusRingWidth`, `multiSelectedBorderWidth`, `borderThin`, הגבהה 1/3, משכי אנימציה ו־`hoverPreviewDelay`. |
| `lib/theme/app_tokens.dart` | `AppTextStyles` | `settingTitle` 16, `settingSubtitle` 13 (שורות הגדרה בלבד), `monospaceFamily`. |
| `lib/theme/app_surface_colors.dart` | `AppSurfaceColors` (ThemeExtension, DD-19) | המשטחים, האזהרה והמצבים, נבנים ב־`AppThemeData` מתוך ה־`ColorScheme`. |
| `lib/theme/app_surfaces.dart` | `AppSurfaces` | הגישה למשטחים ולמצבים: `AppSurfaces.card(context)` קורא את `AppSurfaceColors`, ופונקציות של `ColorScheme` (`selectedRow(cs)` וכדומה) לצבעי מצב שנגזרים ישירות מתפקיד. |
| `lib/theme/app_density.dart` | `AppDensity` (ThemeExtension, DD-10) | "צפיפות ממשק": `isCompact`, גובה סרגל, מידות כפתור ותפריט. |
| `lib/theme/app_motion.dart` | `AppMotion` | משך אנימציה וגלילה מונפשת (`duration`, `scroll`, `scrollPosition`) בכפוף ל"הפחתת אנימציות" של המערכת (DD-21). |
| `lib/theme/app_shadows.dart` | `AppShadows` | הצל היחיד (DD-12): צבע הצל ו־`floating`. |
| `lib/theme/app_colors.dart` | `AppColors` | שלושה צבעים קבועים: `darkScaffold` (רקע קריאה כהה), `warningHue` (גוון האזהרה) ו־`pageWhite` (דף נייר). |
| `lib/theme/app_input_tokens.dart` | `AppInputTokens` | גובה שדה 48/36, גופן השדה ושקיפויות. |
| `lib/theme/layout_tokens.dart` | `LayoutBreakpoints`, `WindowClass`, `LayoutPadding`, `LayoutConstraints` | 600/840/1200, סוג החלון (DD-15), 16/24/32, ‏860, רוחב חלונית צד 340 ורוחב תוכן מינימלי 500. |
| `lib/theme/app_theme_data.dart` | `AppThemeData` | בניית `ColorScheme`, `ThemeData`, ‏`textTheme` המלא וה־component themes. |
| `packages/otzaria_context_menu` | `AppMenuMetrics`, ‏`AppMenuVisuals` | מידות התפריטים, צפופות יותר במצב הקומפקטי (DD-10), וקבועי הצורה הקבועים ב־`menu_visuals.dart` (`AppMenuVisuals`, לא מיוצא): ריפוד שורה מודגשת, רדיוסי לחיצה, גודל תווית שורת האייקונים, צל הפאנל ומשך אנימציית הדגימה. אין ליטרלים בחבילה (UIL-017/019/020/023/029/030 נאכפים בה). מי שמוסיף ידית עיצוב לחבילה מוסיף אותה ל־`AppMenuVisuals` או ל־`AppMenuMetrics`, לא ליטרל בבנאי. |
| `lib/theme/app_seed_colors.dart`, `calendar_event_colors.dart` | `AppSeedColors`, `CalendarEventColors` | פלטות תוכן. תוכן, לא מדיניות. מוחרגים מכללי ה־CI. `AppSeedColors.checkColorOn(swatch)` מחזיר שחור או לבן לסימון על עיגול צבע, לפי בהירות העיגול (q10 Q4.1). |

**[מחייב]** טוקנים חדשים נוספים לקבצים האלה בלבד. לא פותחים קובץ טוקנים מקביל בתיקיית פיצ'ר.
**[מחייב]** טוקן הוא `static const` כשהערך לא תלוי בערכת הנושא, כמו ריווח, רדיוס, משך וגודל. כשהערך תלוי בערכת הנושא (צבע) או בצפיפות, הוא שדה ב־ThemeExtension: `AppSurfaceColors` או `AppDensity` (DD-19 A). ריווח ורדיוס **לא** נכנסים ל־ThemeExtension.

### 2.1 צבעים

**כלל היסוד [מחייב]:** קוד פיצ'ר בוחר **תפקיד** ולא צבע. הסדר הוא:
1. תפקיד של `ColorScheme`: `primary`, `onSurface`, `onSurfaceVariant`, `error`, `outlineVariant` וכו'.
2. אם אין תפקיד מתאים, משטח או מצב מ־`AppSurfaces`.
3. אם גם זה לא קיים, מוסיפים שדה ל־`AppSurfaceColors` (או פונקציה ל־`AppSurfaces`) עם תיעוד. לא מוסיפים שקיפות מקומית.

**[אסור]** בקבצי פיצ'ר:
- `Color(0x…)`.
- `Colors.<גוון>` (`red`, `blue`, `grey` וכו').
- `.withValues(alpha:)`, `.withAlpha(` ו־`.withOpacity(` על צבעי ממשק (UIL-016; 79 מופעים ב־baseline).
- `Theme.of(context).primaryColor`. זהו באג מוכח: במצב כהה Flutter מחזיר דרכו את `surface`, ולכן טקסט ותיבות סימון נעלמו.
- `hoverColor`, `splashColor` ו־`overlayColor` (UIL-007). חריג אחד: `hoverColor: Colors.transparent` ב־`ListTile` שיש לו `onTap` וגם כפתורים ב־`trailing`, כדי שהריחוף של השורה לא יתחרה בהם. ערך מ־`AppSurfaces` (למשל `hoverRow`) אינו עקיפה, גם בתנאי שכל ענפיו `AppSurfaces` או `null`.
- ענף `brightness == Brightness.dark` לבחירת צבע. ההחלטה שייכת ל־`AppSurfaceColors`. UIL-027 חוסם תנאי בהירות שהענפים שלו צבעים (הכרעת בעל הפרויקט 10.11); שלושה אתרים ב־baseline.

`Colors.transparent` מותר. החריגים המותרים מפורטים בסעיף 2.1.3.

#### 2.1.1 קטלוג תפקידי הצבע

| טוקן (תפקיד) | מקור בקוד | ערך בהיר | ערך כהה | סטטוס | שימוש |
|---|---|---|---|---|---|
| רקע קריאה | `AppSurfaces.readerBackground` | `cs.surface` | נייטרלי, לא נגזר מהזרע: `AppColors.darkScaffold` `#242424`, לכל ערכת צבע (DD-05, השלמה 2.11) | קיים | מסכי ספר ו־PDF |
| רקע לוח (מסכי עבודה) | `AppSurfaces.panelBackground` | `surface` + `surfaceContainerHighest` בשקיפות 47.5% | `surfaceContainerLow` (DD-05 C) | קיים | הגדרות, ספרייה וכלים, ואזור התוצאות בכרטיסיית החיפוש (DD-18) |
| סרגל עליון | `AppSurfaces.topBarBackground` | `surfaceContainerHigh` | `surfaceContainerHigh` | קיים | `AppTopBar` |
| חלונית ניווט | `AppSurfaces.navPanelBackground` | = topBar | = topBar | קיים (שם נרדף מכוון) | `NavSidePanel`, חלוניות לצד הקריאה (DD-18) |
| כרטיס | `AppSurfaces.card` | `surface` | `surfaceContainer` | קיים | `AppCard`, `DetailsCard` |
| גוף דיאלוג שבנוי מכרטיסים | `AppSurfaces.cardDialogBackground` | = רקע לוח | `surface` | קיים. חריג מתועד לגוון הדיאלוג של DD-07, כדי שהכרטיס יהיה בהיר מהגוף בשתי הערכות | היסטוריה, סימניות |
| מפריד בתוך כרטיס | `AppSurfaces.cardRowDivider` | רווח שקוף בתוך `AppCard.section` (DD-12) | כנ"ל | קיים | `AppCard.section` |
| מפריד עדין | `AppSurfaces.subtleDivider` | `outlineVariant` בשקיפות 50% | כנ"ל | קיים | רשימות |
| כרטיס עדין ברשימת חלונית | `AppSurfaces.tintedRow(cs)` | `surfaceTint` בשקיפות 5% | כנ"ל | קיים | כרטיסי ההערות בחלונית ההערות: כל הערה כרטיס מעוגל בגוון הזה, עם רווח ובלי קו (#3086, סקירת 4.11, סבב חמישי). לא `panelSectionAccent`, שבולט בהרבה |
| קו אזורים | `AppSurfaces.regionBorder` (`AppSurfaceColors.regionBorder`) | ב"לבן": אפור בינוני־בהיר 9F9F9F (`onSurface` ב־42% מעל `surface`, אטום; 2.6:1 מול FF ו־FC, מתחת ל־3:1 בכוונה, סקירת 4.11, סבב שלישי). בשאר הערכות `null` | `null` | קיים | ב"לבן" בבהיר: שורת הכותרת והכרטיסייה הפעילה, עמודת הניווט, עמודת הכרטיסיות, `AppTopBar`, חלונית ניווט צמודה וחלונית צד צפה, `PaneCard`, דיאלוג, תפריטים ו־tooltip (`AppThemeData.raisedShape` / `AppSurfaces.raisedShape`). הקורא כותב `regionBorder(context) ?? <הקו הקיים>` (#2850, #1939) |
| קו בחירה | `AppSurfaces.selectedBorder` (`AppSurfaceColors.selectedBorder`) | ב"לבן": כמו קו האזורים, 9F9F9F. בשאר הערכות `null` | `null` | קיים | ב"לבן" בבהיר, סביב פריט נבחר: `AppCard(selected)` (גם שורה עצמאית ברשימת הספרייה), שורה מקובצת ברשימת הספרייה (קו עליון ותחתון), המקטע הנבחר ב־`AppSegmentedControl`, והפריט הנבחר בתפריט נפתח (קו עליון ותחתון). ב"לבן" מילוי הבחירה E0 קרוב לריחוף, ולכן הקו מסמן את הנבחר (סקירת 4.11, סבב רביעי, q-white-selected) |
| מקטע ניטרלי בחלונית | `AppSurfaces.panelSection` | `surfaceContainerHighest` בשקיפות 50% | כנ"ל | קיים | חלוניות הגדרות |
| מקטע מודגש | `AppSurfaces.panelSectionAccent` / `…AccentBorder` | `primaryContainer` 30% / `primary` 30% | כנ"ל | קיים | — |
| משטח מוגבה (תפריט, tooltip, דיאלוג) | `dialogTheme`/`menuTheme`/`popupMenuTheme`/`tooltipTheme` | `surfaceContainerHigh` | `surfaceContainerHigh` | קיים. גם `popupMenuTheme` על רקע התפריטים המשותף | — |
| טקסט ראשי | `cs.onSurface` | M3 | M3 | קיים | — |
| טקסט משני | `cs.onSurfaceVariant` | M3 | M3 | קיים. מחליף את `onSurface` בשקיפות 50–60% | תת־כותרות, מטא־דאטה |
| מסגרת והפרדה | `cs.outlineVariant` | M3 | M3 | קיים | מסגרת כרטיס (DD-12) |
| פעולה ראשית / משנית | `cs.primary` / `cs.secondaryContainer` | M3 | M3 | קיים, דרך `ActionButton` | — |
| שגיאה | `cs.error` / `cs.errorContainer` | M3 | M3 | קיים | — |
| אזהרה | `AppSurfaces.warning`, `onWarning`, `warningContainer`, `onWarningContainer` | הגוון הקבוע `AppColors.warningHue` (`#FB8C00`) עובר `harmonize` מול `primary` של הערכה, ולכן משתנה מעט מערכה לערכה (DD-24, השלמה 2.11) | כנ"ל | קיים | באנרים, תגיות `warning` |
| הצלחה | `cs.secondaryContainer` / `onSecondaryContainer` | הגוון הנייטרלי הקיים (חום בערכת ברירת המחדל), **לא ירוק** | M3 | קיים (DD-24, DD-13) | הודעת הצלחה, סמל ה־וי, תגית `success` |
| Hover / Pressed / Focus של כפתורים | `_hoverButtonStyle` (שקיפות 8%/12% על primary) | | | קיים בערכת הנושא | — |
| שורה נבחרת | `AppSurfaces.selectedRow` / `onSelectedRow` = `secondaryContainer` (ב"לבן" בבהיר E0E0E0) | | | קיים (DD-06 C). "נבחר" מסומן גם במשקל, באייקון או ב"לבן" בקו הבחירה (`selectedBorder`) | רשימות, עצים, כרטיסיות |
| שורה בפוקוס | `AppSurfaces.focusedRow` (`primary` 8%) + `focusRingDecoration` (טבעת `primary`, ‏`AppTokens.focusRingWidth` 2) | | | קיים | — |
| ריחוף | `AppSurfaces.hoverRow` = שכבת ה־hover של M3 (`onSurface` 8%) | | | קיים | — |
| בחירה מרובה | `AppSurfaces.multiSelected` (`primaryContainer`) + `multiSelectedBorder` (‏`AppTokens.multiSelectedBorderWidth` 1.5) | | | קיים | כרטיסיות, הכרטיס הפעיל בבורר שולחנות העבודה |
| מושבת | Material (שקיפות 38%) | | | קיים. לא מגדירים ידנית | — |
| הדגשת חיפוש וסימון | `AppSurfaces.searchHit`, `searchHitCurrent`, `permanentMark`, ו־CSS role tokens בתוך ה־HTML (`SearchHighlightCss`, כמו `otzaria-reader-link`) | הרקעים שקופים 80%, כדי שסימון בעכבר ייראה גם בתוכם (DD-17, השלמה 2.11) | | קיים (DD-17 A) | קורא, PDF |
| הדגשה בקטעי תוצאות החיפוש | `cs.error` | | | קיים, **נשאר** (DD-17) | קטעי תוצאה |
| קישור בספר | `AppSurfaces.readerLink` | `primary` (אפור בערכה נייטרלית) | | קיים | תוכן |
| בחירת פסקה / שורה מודגשת | `highlightedLineBackground`; שורת מפרש קשורה בצורת הדף: `relatedLineMarker` (סמן צד, בלי רקע) | | | קיים | קורא |
| scrim | `AppSurfaces.scrim`, אחד לדיאלוגים ולחלוניות | `cs.scrim` עדין (`0x22`) | כנ"ל | קיים (DD-12 A). לסיור ההיכרות החשכה כהה יותר, בשם משלה | — |
| צל | `AppShadows` | `cs.shadow` 22% | | קיים (DD-12 A). כרטיסים בלי צל | תפריט, חלונית צפה, כפתור צף |

#### 2.1.2 צבעי ניווט, קריאה וסימון
- **ניווט [מחייב] · קיים:** הסרגל העליון וחלונית הניווט חולקים צבע אחד (`topBarBackground`), כדי שייראו כרצועה רציפה. עמודת הניווט והסרגל התחתון בטלפון באותו צבע, `navPanelBackground` (q10 Q18).
- **כרטיסיות [מחייב] · קיים (DD-06):** שתי רצועות הכרטיסיות (האופקית והאנכית) מקבלות את צבעי המצב מ־`TabStateColors` אחד (`lib/navigation/view/tab_visuals.dart`): `hoverRow` ו־`multiSelected`. הכרטיסייה הפעילה, בשתי הרצועות, בצבע הסרגל (`topBarBackground`) ובמשקל w600 (השלמה 2.11). ברצועה האופקית הצורה מחברת אותה לפס, וברצועה האנכית היא בולטת על רקע הלוח. בחיפוש הכרטיסיות הכרטיסייה הנוכחית ב־`selectedRow`. "נבחר" מסומן גם במשקל הגופן או באייקון, לא רק בצבע.
- **פרטי הכרטיסייה · קיים (q10 Q14):** זהים בשתי הרצועות: אייקון PDF אחד (של אוצריא), X בגודל 12, ונעץ לחיץ בתחילת כרטיסייה מוצמדת (`TabPinButton`, שמבטל את ההצמדה). הרווחים סביב הנעץ מתכווצים עם הכרטיסייה, מ־4/4 ברחבה ל־0/2 בצרה, כדי שבהרבה כרטיסיות הוא יישאר צמוד לכותרת (LQ-14, סקירת 4.11).
- **סימון טקסט בקורא:** צבעי הדגשה שהמשתמש בוחר (מרקר, צבעי אירועים) הם **תוכן**. שומרים אותם כנתון (אינדקס או ARGB) ומתאימים אותם לבהירות בזמן ציור, כפי ש־`CalendarEventColors` עושה.

#### 2.1.3 חריגים מותרים לצבע מקומי [מחייב] (DD-24)
צבע מקומי מותר **רק** בארבעה מקרים:
1. **תוכן:** `AppSeedColors`, `CalendarEventColors`, צבעי מרקר, צבעי CSS שמגיעים מתוך הספר, וציור של תוכן ב־`CustomPainter` (דף PDF, הצללת דפדוף). גם שם עדיף לקבל צבע מתפקיד.
2. **ייצוא והדפסה** (`package:pdf`, ‏`pw.*`): הפלט הוא דף נייר לבן, ללא תלות בערכת הנושא.
3. **חיקוי כרום של מערכת ההפעלה**, כמו כפתורי חלון בסגנון Windows.
4. **צללים** — רק דרך `AppShadows` ב־`lib/theme/app_shadows.dart`. צללים מקומיים שנשארו רשומים ב־baseline של UIL-030.

#### 2.1.4 ערכת "לבן" בבהיר [מחייב] · קיים (DD-18, #2850)
הזרע "לבן" (`AppThemeVariant.white`) במצב בהיר דורס ב־`AppThemeData.createColorScheme` את סולם המשטחים ואת צבע הבחירה. ב"לבן" בכהה אין דריסה, ובשאר הערכות רק ל"פרגמנט" בבהיר יש סולם משטחים משלו.

| תפקיד | ערך ב"לבן" בבהיר |
|---|---|
| `surface` / `surfaceContainerLowest` (קריאה) | FFFFFF / FFFFFF |
| `surfaceContainerLow` / `surfaceContainer` | FEFEFE / FDFDFD |
| `surfaceContainerHigh` (סרגלים, חלונית ניווט, גוף דיאלוג) | FCFCFC (לוח הכלים יוצא כ־FA) |
| `surfaceContainerHighest` (כותרת דיאלוג) | F5F5F5 |
| `secondaryContainer` (בחירה, `selectedRow`) | E0E0E0 (`AppThemeData.whiteSelectedFill`) |
| `AppSurfaces.regionBorder` (קו בין אזורים) | 9F9F9F, ‏`borderThin` |
| `AppSurfaces.selectedBorder` (קו סביב הנבחר) | 9F9F9F, ‏`borderThin` |

בערכה הזו האזורים נבדלים בקו ולא בגוון, והנבחר בקו ולא רק במילוי. לכן רכיב שמצייר גבול אזור או פריט נבחר כותב `AppSurfaces.regionBorder(context) ?? <הגבול הרגיל>` (או `selectedBorder`), ולא בודק איזה זרע פעיל. התפריטים, ה־tooltip והחלוניות הצפות מקבלים את הקו דרך `AppThemeData.raisedShape` / `AppSurfaces.raisedShape`, ובורר המקטעים דרך `segmentedButtonTheme`.

---

#### 2.1.5 טוקני בחירה וגלילה, וטקסט על רקע תוכן (הוכרע 18.11.2026)
כל הערכים נמדדו מול כל 14 הזרעים בבהיר ובכהה (`test/theme/`).

- **בחירת טקסט** (`AppThemeData.textSelection`, מוזרם כ־`ThemeData.textSelectionTheme.selectionColor`): `primary` בשקיפות 0.38 בבהיר ו־0.28 בכהה. ב־0.28 בכהה האותיות מעל הבחירה ב־4.76:1 לפחות על כל 14 הזרעים (ב"לבן" וב"אפור" היה 3.24:1 עם ברירת המחדל 0.4 של Flutter). אין להגדיר `selectionColor` מקומי.
- **שורה נבחרת ב"פרגמנט" בבהיר** (`AppThemeData.parchmentSelectedFill` = `D8C6A3`, נדרס כ־`secondaryContainer`, כמו `whiteSelectedFill` של "לבן"): 1.31:1 מהלוח ו־1.44:1 מהקריאה והכרטיס; טקסט `onSecondaryContainer` 5.60:1, וטבעת פוקוס `primary` 3.84:1. הערך של M3 היה ורדרד ובאותה בהירות כמו הלוח (1.01:1).
- **פס גלילה במנוחה** (`AppSurfaces.scrollbarThumb`): `onSurfaceVariant` בשקיפות 0.65 בבהיר ו־0.5 בכהה; 3:1 מול הקריאה, הלוח והכרטיס בכל 14 הזרעים (הנמוך ביותר 3.19 בבהיר, 3.37 בכהה). היה 0.4 (1.93 עד 2.66).
- **סימן שורה קשורה** (`AppSurfaces.relatedLineMarker`): `primary` בשקיפות 0.7 בבהיר ו־0.5 בכהה; 3:1 מול הקריאה והכרטיס (הנמוך ביותר 3.06 בבהיר, 3.35 בכהה). היה 0.5 בשניהם (2.13 בבהיר).
- **טקסט על רקע תוכן.** כשתוכן מביא צבע רקע משלו (הדגשה בהערה אישית, הדגשת קטע ספר על ידי תוסף), צבע האותיות לא נשאר בצבע הערכה אלא נגזר מבהירות הרקע בזמן ההצגה: `readableInkOn(background)` ב־`lib/theme/readable_ink.dart` (כהה `1F1F1F` מעל בהירות יחסית 0.179, אחרת לבן). החישוב בזמן הצגה ולא בכתיבה לנתונים, כדי שגם תוכן שנשמר קודם וגם משתמש שעובר בין בהיר לכהה יקבלו אותיות קריאות. בהדגשת תוסף (`PluginHighlightRenderer._inkOn`) רקע שקוף נבדק מול רקע קריאה לבן ומול `AppColors.darkScaffold`, והצבע נקבע רק אם הוא קריא (4.5:1) על שניהם; `foregroundColor` שהתוסף קבע גובר תמיד. כך ב־`personalNoteBackgroundInkStyle` ובשלושת מסלולי ההערה האישית (עורך, תצוגת Quill בכרטיס, תצוגה מקדימה קלה).


### 2.2 ריווח

**[מחייב] (DD-03 C) · קיים:**

| טוקן | ערך | תפקיד |
|---|---|---|
| `AppTokens.space2XS` | 2 | הפרדה בין שורות טקסט צמודות, מרווח אייקון־מונה |
| `AppTokens.spaceXS` | 4 | בין אייקון לטקסט צמוד, ריפוד תגית אנכי |
| `AppTokens.spaceSM` | 8 | בין פריטים קשורים, בין כפתורים |
| `AppTokens.spaceSMD` | 12 | ריפוד פנימי של שורת רשימה, בין קבוצות קטנות |
| `AppTokens.spaceMD` | 16 | ריפוד דיאלוג אופקי, בין כרטיסים |
| `AppTokens.spaceLG` | 24 | ריפוד דיאלוג (M3), בין מקטעים |
| `AppTokens.spaceXL` | 32 | שוליים של מסך רחב |

**כלל העיגול [מחייב] (DD-03):** ריווח שמחוץ לסולם **עולה** לערך הבא: 6→8, ‏10→12, ‏14→16. העיגול נעשה כשהקובץ מוסב, לא בהחלפה גורפת. UIL-020 חוסם ריווח חדש מחוץ לסולם (131 מופעים ב־baseline).

**טוקנים סמנטיים** (`static const` ב־`AppTokens`, DD-03 C). כל הערכים נגזרים מהסולם. ערך שלא הוכרע נקבע ב־commit המיישם, עם תמונות:

| שם | ערך | סטטוס |
|---|---|---|
| `cardPadding` | `all(12)` (DD-11, כרטיס תוצאה) | קיים |
| `listItemGap` | 8 בין תוצאות (DD-11) | קיים |
| `dialogPadding` | הערך הקיים: 24 אופקי, 16 אנכי | קיים |
| `listRowPadding` (16/12), `sectionGap` (24), `titleContentGap` (12), `labelFieldGap` (4) | נגזרים מהסולם, ב־`AppTokens` | קיים, אבל כמעט בלי קוראים: `SettingsCard` משתמש בשלושה והשדה הנפתח בארבעה. קוד חדש משתמש בהם, וקוד קיים עובר אליהם כשנוגעים בו |
| `screenPadding` | `LayoutPadding.compact/medium/expanded` (16/24/32) | קיים, כמעט לא בשימוש |

**[מחייב]**
- ריווח בקוד פיצ'ר נכתב רק כטוקן או כצירוף של טוקנים (`spaceSM + spaceXS`). אסור "טוקן ± 1" (`spaceSM + 1`), כי זה ערך שמחוץ לסולם בתחפושת.
- `EdgeInsets.only(left/right)` ו־`EdgeInsets.fromLTRB` אסורים כשהריווח תלוי כיוון. משתמשים ב־`EdgeInsetsDirectional`.

### 2.3 רדיוסים

**[מחייב] (DD-04 A) · קיים:** **ערך אחד, 8**, לכל רכיב מלבני: `AppTokens.radius`, ‏`borderRadiusAll` ו־`roundedShape`.

| תפקיד | התקן | סטטוס |
|---|---|---|
| שדה, כפתור טקסט, כרטיס, דיאלוג, תפריט, tooltip | 8 | קיים |
| תגית `MetaChip`, צ'יפ בחירה (`chipTheme`) | 8 | קיים |
| כפתור סרגל עם תווית (`BarButton.icon` + `label`) | 8, בלי גלולה, גם ברקע הבחירה | קיים |
| תג אייקון של דיאלוג (`AppDialogIconBadge`) | ריבוע מעוגל 8, כמו `ListIconBadge` | קיים |
| רכיב פנימי בתוך מכל מעוגל (כפתורי הדפדוף ב־PDF) | נגזר מהמכל (clip). **אין** `radiusInner` | קיים: כפתור הדפדוף עגול עם ink עגול |
| רכיבים עגולים מטבעם (נקודת סטטוס, אווטאר) | עיגול | קיים |
| כפתור אייקון בלבד ב־`BarButton` (בחירה ו־hover) | 8, כמו כל כפתור (DD-04, השלמה 19.11) | קיים |
| כפתור סרגל מפוצל (`BarSplitButton`, אייקון וחץ בלי תווית) | **גלולה**, חריג מאושר (DD-04, השלמה 2.11) | קיים |
| `IconButton` גולמי בלי צורה משלו (`iconButtonTheme`) | 8 (`roundedShape`), כמו `AppIconButton` (DD-04, השלמה 19.11). כפתור אייקון עם רקע גלוי משלו קובע `roundedShape` בעצמו | קיים |
| כפתור סינון של תוסף בשדה חיפוש, במצב סינון עם תווית | 8, בצורת צ'יפ, עם תווית `labelMedium` (12) (DD-31, q10 Q23) | קיים |
| ידית פס גלילה | חצי מהעובי, מחושב מקבוע העובי (q10 Q10) | קיים |

**[אסור]** כל רדיוס אחר: `circular(n)` ליטרלי, `StadiumBorder`, ו־4 בתוך תפריט. `CircleBorder` מותר רק לרכיב עגול מטבעו, עם allow (גם לא בכפתור אייקון). UIL-019 בודק את כולם, עם החריגים שבטבלה (q10 Q13). אין לו חוב, והוא נעול.

### 2.4 טיפוגרפיה

#### 2.4.1 טיפוגרפיית ממשק

**גופן הממשק [מחייב] (DD-01 A) · קיים:** גופני המערכת במפורש. `fontFamily: null`, ורשימת `fontFamilyFallback` מפורשת לפי פלטפורמה (`'Segoe UI'`, `'SF Pro Text'`, `'.AppleSystemUIFont'`, `'Noto Sans Hebrew'`, `'Arial'`), שמוגדרת ב־`AppThemeData` בלבד. אין 'Roboto' בשום מקום. ב־Windows אין שינוי חזותי (Segoe UI נשאר).

**הסולם [מחייב] (DD-02 C) · קיים:** סולם תפקידים אחד, מוגדר במלואו ב־`AppThemeData.textTheme` מתוך `AppTokens.font*`. קוד פיצ'ר בוחר **תפקיד**:

| תפקיד בממשק | slot ב־textTheme | גודל / משקל |
|---|---|---|
| כותרת ראשית (מסך ריק גדול, אודות) | `headlineSmall` | 22 / w600 |
| כותרת מסך / סרגל עליון | `titleLarge` (`AppTopBar.titleStyle`) | 18 / w600 |
| כותרת דיאלוג | `titleLarge` | 18 / w600 |
| כותרת מקטע (`AppSectionLabel`, `SettingsCard`, `NavTreeHeader`) | `titleMedium` | 16 / w700, `primary` (DD-14) |
| כותרת כרטיס / שורה | `titleSmall` | 14 / w600 |
| טקסט גוף | `bodyLarge` | 16 |
| טקסט גוף משני / תיאור | `bodyMedium` | 14 |
| מטא, הערות שוליים, מונים | `bodySmall` | 12 |
| תווית שדה / כפתור | `labelLarge` | 14 / w500 |
| תווית קטנה (צ'יפ, `AppTogglePill`, לשונית) / פריט בעמודת הניווט | `labelMedium` / `labelSmall` | 12 / 11 (q10 Q1, Q2) |
| הודעת שגיאה בשדה | `bodySmall` + `cs.error` | 12 |
| מונוספייס (נתיב, קיצור מקשים, גרסה) | המשפחה: `AppTextStyles.monospaceFamily` (קיים). סגנון `AppTextStyles.mono` עם גודל מה־slots: יעד | גופן `monospace` של המערכת |

**[מחייב]**
- **`fontSize:` אסור בקוד פיצ'ר (DD-02).** מותר רק ב־`lib/theme/` ובציור תוכן הספר (2.4.2). משתמשים ב־`Theme.of(context).textTheme.<slot>`, ובמקרה הצורך ב־`.copyWith(fontWeight:/color:)`. גם `AppTokens.font*` (ו־`fontSM - 1` וכדומה) נשאר בשכבת ה־Theme. UIL-017 חוסם את שניהם (173 מופעים ב־baseline). גם גודל שאין לו תפקיד ברור מקבל את ה־slot הקרוב, ולא חריג (q10 Q5).
- `TextStyle(fontFamily: '…')` ליטרלי אסור (UIL-018). המשפחה נקבעת ב־`AppThemeData` (גופן ממשק), ב־`AppFonts` (תוכן) או ב־`AppTextStyles.monospaceFamily`.
- `AppTextStyles.settingTitle/settingSubtitle` שמורים לשורות הגדרה. לא בונים מהם סגנונות לשימושים אחרים.

#### 2.4.2 טיפוגרפיית תוכן הספרים (מערכת נפרדת)

**[מחייב] · קיים** טקסט ספר, מפרשים ותצוגות מקדימות של קישורים מקבלים גופן, גודל וגובה שורה **מהגדרות הקריאה** (`SettingsState.fontFamily`/`fontSize`/`lineHeight`/`commentators*` ו־`TextDisplayProfile`). הם **לא** כפופים ל־textTheme.

**[מחייב] · קיים** קטעי תוצאות החיפוש (המנוע, המנועים החיצוניים והחיפוש הסמנטי) לוקחים את הגופן ואת `TextDisplayProfile` מהגדרות הקריאה, ואת הגודל מהגדרה נפרדת: `SettingsState.searchResultsFontSize`, "גודל טקסט בתוצאות החיפוש" (q12 Q2, #2826). גודל הספר לא משנה אותו. בשדרוג הוא מקבל פעם אחת את גודל הספר, ולכן אצל משתמש קיים לא משתנה דבר. התצוגה המקדימה של תוצאה היא טקסט ספר, ולכן בגודל הספר.

**[מחייב] · קיים** חלונית הגדרות התצוגה (הכפתור בשורת הכותרת) מציגה רק את מה שחל על הכרטיסייה הפעילה: רכיב אחד, `TextSettingsTab(scope:)`, ולא עותק. ‏`all` במסך ההגדרות; ‏`book` בכרטיסיית ספר (בלי גודל התוצאות); ‏`searchResults` בכרטיסיית חיפוש: גודל הספר והגופן, מרווח השורות (של התצוגה המקדימה) וגודל התוצאות, ממש מעל הקריאה הרציפה, "תצוגת הטקסט", העתקת כותרות והגדרות לפי ספר. בלי גודל וגופן המפרשים ורוחב הטקסט, שלא חלים על התוצאות ועל התצוגה המקדימה. הגדרה חדשה בכרטיס נכנסת ל־scope שבו היא חלה.

הכללים:
- גדלים יחסיים בתוך תוכן (×0.85 לכותרת מפרש, ‎sup/small ב־HTML) הם חלק מהתוכן ומותרים. גם כותרת החלונית הקומפקטית של קישור (Linker, שם הספר והמקום) היא ×0.85 מגודל התוכן של החלונית, אבל בין 11 (`labelSmall`) ל־14 (`titleSmall`), כדי שלא תתחרה בתוכן בגודל קריאה גדול (`compactPreviewTitleFontSize`, סקירת 4.11, סבב רביעי, q-linker-title).
- **הודעות ממשק בתוך אזור התוכן** ("טוען מפרשים…", "אין תוכן זמין", שגיאת טעינה) הן ממשק, ולכן `textTheme`, וטקסט משני בהן `onSurfaceVariant`. חלקי: "טוען מפרשים…" כבר ב־`onSurfaceVariant` (q10 Q4.2), אבל עדיין בגודל הקריאה.
- גופני ספר נקבעים דרך `AppFonts` בלבד.
- ההחרגה ב־CI נעשית לפי נתיבים ודפוסים ולא בהערות. הרשימה ב־`CI_ENFORCEMENT.md` §3.6.

### 2.5 טוקנים נוספים

#### 2.5.1 אייקונים
**[מחייב] · קיים** הכללים ב־`docs/agent_ui_reference.md` §1 (otzaria_icons קודם, אחר כך Fluent; בלי Material). אייקון Fluent שמוגדר `matchTextDirection: true` (חיצים ושברונים שמאלה/ימינה, קודם/הבא, יישור טקסט) נכתב ב־`Icon` רגיל עם הגליף של LTR, ו־Flutter מהפך אותו ב־RTL. `RtlIcon` מעביר אייקון כזה כמו שהוא, ומהפך רק את הרשומים בו (UIL-006).

**גדלי אייקון [מחייב] (DD-03) · קיים:**

| טוקן | ערך | שימוש |
|---|---|---|
| `AppTokens.iconXS` | 14 | עץ ניווט, תגיות |
| `AppTokens.iconSM` | 16 | בתוך שדה, כפתור קומפקטי, פעולת שורה |
| `AppTokens.iconMD` | 20 | ברירת המחדל בממשק: סרגלים (`BarButton`), תפריטים, אייקון השדה ב־`OtzariaSearchField`, תג כותרת הדיאלוג |
| `AppTokens.iconLG` | 24 | ברירת מחדל של M3 |
| `AppTokens.iconXL` | 48 | מצב ריק |

**[אסור]** גודל אייקון מספרי בקוד פיצ'ר, וטוקן גופן כגודל אייקון (UIL-029; 87 מופעים ב־baseline). גודל מחוץ לסולם עובר לטוקן: 18 ל־`iconSM` ‏(16), ‏22 ל־`iconMD` ‏(20) (סקירת 4.11, סבבים רביעי וחמישי, גם בתוך `OtzariaSearchField`), ו־56/64 ל־`iconXL` ‏(48) (q10 Q9).

#### 2.5.2 גבהים סטנדרטיים
| רכיב | ערך | מקור | סטטוס |
|---|---|---|---|
| שדה קלט רגיל / קומפקטי | 48 / 36 | `AppInputTokens` | קיים |
| שדה חיפוש slim | `AppInputTokens.compactHeight` | `OtzariaSearchField.heightSlim` | קיים |
| סרגל עליון רגיל / קומפקטי | לפי `AppDensity.topBarHeight` | `AppDensity` | קיים |
| כפתור סרגל | 40 / 36 | `BarButton` (פרמטר `compact`) | חלקי: הקורא מעביר את הצפיפות מ־`AppDensity` |
| פריט תפריט | `AppMenuMetrics` | `packages/otzaria_context_menu` | קיים. צפוף יותר במצב הקומפקטי (DD-10). תווית רחבה מהתפריט מתקצרת ב־"…" ולא גולשת (סקירת 4.11, סבב שני) |
| לשונית חלונית | 44 | `AppTokens.panelTabHeight` | קיים |
| סרגל ניווט תחתון (טלפון לאורך) | 64, תווית לכל יעד; רק לנבחר כשהתווית הארוכה לא נכנסת ברוחב של יעד (נמדד) | `LayoutConstraints.bottomNavigationBarHeight`, דרך `navigationBarTheme`; `BottomNavLabels.behaviorFor` | קיים (q12 Q8, ss6, סקירת 4.11, סבב שלישי) |

#### 2.5.3 גבולות
| טוקן | ערך | שימוש | סטטוס |
|---|---|---|---|
| `AppTokens.borderHairline` | 0.5 | מפריד בין שורות בטבלה וברשימה, גם בהדפסת לוח השנה, כשקו דק (1) כבד מדי (הוכרע 18.11) | קיים |
| `AppTokens.focusRingWidth` | 2 | טבעת פוקוס ופס פעיל | קיים |
| `AppTokens.multiSelectedBorderWidth` | 1.5 | מסגרת בחירה מרובה וכרטיס פעיל | קיים |
| `AppTokens.borderThin` | 1 | מסגרת כרטיס, שדה ומפריד, וקו האזורים של "לבן" | קיים, ב־17 מקומות ב־`lib` (ערכת הנושא, קו האזורים של #2850). חלק מהמסגרות עדיין ברירת המחדל של `BorderSide` (1) |
| `AppTokens.borderThick` | 3 | טבעת בחירה ופוקוס סביב עיגול צבע (`AppColorSwatch`), וסימון קצה של פסקה מתוקנת (הוכרע 18.11) | קיים |

סולם העוביים: 0.5 (`borderHairline`), 1 (`borderThin`), 1.5 (`multiSelectedBorderWidth`), 2 (`focusRingWidth`), 3 (`borderThick`). עוביים ליטרליים בודדים שנשארו מחוץ לסולם (למשל 1.2 ב־`StatusChip` ובעורך ההערות, 1.5 בחלון הפרסומת וב־`grid_items.dart`) אינם ערך רשמי, ולא מוסיפים כאלה.

#### 2.5.4 צלליות והגבהה [מחייב] (DD-12 A) · קיים
**התקן:** מסגרת ולא צל. שלוש רמות בלבד:
- 0: כרטיסים ומשטחים רגילים. כרטיס מקבל מסגרת `outlineVariant` בלי צל.
- 1 (`AppTokens.elevation1`): סרגל עליון וחלונית מוצמדת.
- 3 (`AppTokens.elevation2`): תפריט, tooltip וחלונית צפה.

הדיאלוג נשאר לפי M3. צל רק דרך `AppShadows`. ה־scrim אחד, עדין כמו בדיאלוגים (2.1.1). UIL-030 חוסם הגבהה ליטרלית ו־`BoxShadow` מחוץ ל־`lib/theme` (3 מופעים ב־baseline: אנימציות הדגשה). צל הנייר של עמוד PDF הוא תוכן, ומסומן allow (JX-05, q10 Q11).

#### 2.5.5 תנועה
| טוקן | ערך | סטטוס |
|---|---|---|
| `AppTokens.animFast` | 150ms | קיים |
| `AppTokens.animPanelOpacity` | 200ms | קיים |
| `AppTokens.animNormal` | 250ms | קיים |
| `AppTokens.animPanelSlide` | 300ms | קיים |
| `AppTokens.hoverPreviewDelay` | 280ms | קיים |
| `AppTokens.curveStandard` / `curveEnter` / `curveExit` | `easeInOut` / `easeOutCubic` / `easeInCubic` | קיים. `AppMotion.scrollPosition` משתמש ב־`curveStandard`. עקומות ליטרליות בקוד קיים עוד לא הוסבו |

**[מחייב]**
- משך אנימציה של ממשק הוא טוקן. UIL-023 נעול (`strict`) ואין לו חוב ב־baseline. `AnimationController` מקבל את המשך דרך `AppMotion.controller(...)`, שמטפל בהפחתת תנועה.
- **הפחתת תנועה (DD-21 A) · קיים:** כל משך של אנימציית ממשק עובר דרך `AppMotion.duration(context, AppTokens.animNormal)`, שמחזיר `Duration.zero` כשהמערכת מבקשת להפחית אנימציות. כך נכבות פתיחת חלונית והחלפת לשונית. אנימציה שמעבירה מידע, כמו התקדמות, נשארת.
- **גלילה מונפשת · קיים (q10 Q12):** דרך `AppMotion.scroll` או `AppMotion.scrollPosition`, שקופצים ליעד תחת הפחתת תנועה, כי `animateTo` לא מקבל משך 0. ‏`Scrollable.ensureVisible` מקבל `AppMotion.duration`.
- משכים ייחודיים של אנימציות קישוט (חגיגת סיום 2000ms, הבהוב עוגן ההגדרות 1300ms, ועוד כמה ב־`AppMotion.controller` עם ערך ליטרלי) נשארו כקבועים מקומיים בלי טוקן. הוכרע (10.11) שכל `AnimationController` עובר דרך `AppMotion`, ובהפחתת תנועה מגיע מיד למצב הסיום. הכלל המועמד UIL-036 מדווח על המשכים האלה (22, דוח בלבד, ‏`CI_ENFORCEMENT.md` §3.8). המשכים 120/180/280 מ־DD-21 כבר אינם: 280 הוא `hoverPreviewDelay`, ו־120 הוא השהיית טעינה ולא אנימציה.
- **גלילה חלקה בגלגל העכבר (`SmoothWheelScroll`) אינה אנימציית ממשק אלא החלקת קלט, ולכן אינה מכבדת `MediaQuery.disableAnimations` (הוכרע 18.11.2026, הפחתת תנועה).** היא נשארת כמו שהיא גם כשהמשתמש ביקש הפחתת תנועה: ריכוך של תנועת היד, לא תנועה שהממשק יוזם. מי שרוצה קפיצה של שורה שלמה בלי החלקה אינו נתמך (נשקל כאפשרות ב' ונדחה). `AppMotion.duration` ו־`AppMotion.controller` ממשיכים לכבד `disableAnimations` בכל שאר האנימציות. הקובץ: `lib/widgets/misc/smooth_wheel_scroll.dart` (אין בו התייחסות ל־`disableAnimations`, וה־`Ticker` מנפיש כל מחוות גלגל); גלילת ה־PDF נגזרת ממנו (`SmoothWheelScroll.decayRatePerMs`).

```dart
AppMotion.scrollPosition(_scroll.position, offset, AppTokens.animPanelSlide);
AppMotion.scroll(context, AppTokens.animPanelSlide,
    animate: (d) => _pages.animateToPage(i, duration: d, curve: Curves.easeInOut),
    jump: () => _pages.jumpToPage(i));
```

#### 2.5.6 שטחי לחיצה [מחייב] · קיים
- מינימום 40×40 בדסקטופ, ו־48×48 במגע (`MaterialTapTargetSize.padded`). `AppIconButton` במובייל 48 גם בשורה צפופה, כשהשורה גבוהה ב־8 (DD-11, השלמה 3.11).
- אפשר לצייר אייקון קטן בתוך שטח לחיצה גדול יותר. מקטינים את השטח רק כשהרכיב הוא חלק משורה צפופה שיש לה חלופה במקלדת.
- **מומש (10.11, בעל הפרויקט: B):** במגע (`MaterialTapTargetSize.padded`) תופסים 48×48 באותו מראה `BarButton.icon`, ‏`AppTogglePill`, ‏`StatusChip`, כפתור הניקוי של `OtzariaSearchField` וכפתורי כרטיס ההערה במסך הניהול (הכרטיס גבוה יותר במגע). ‏`a11y_guidelines_test.dart` בודק `androidTapTargetGuideline` ברכיבי הליבה, ובדיקת "במחשב שטחי המגע נשארים צמודים" נועלת את הדסקטופ. במחשב הכול כמו קודם (40 ו־32).
- **חריגות מותרות (הוכרע 18.11.2026, בעל הפרויקט):** נשארים קטנים מ־48 גם במגע, ואין צורך להגדיל אותם:
  - הכפתורים שבתוך שדה החיפוש (`OtzariaSearchFieldButton`: מתגי מילה שלמה/רגקס, תפריט היקף, כפתורי תוספים, איתור): בשדה צר (36) הם 26, **ובמסך מגע 40 (והשדה 40) כשיש מקום** (הוכרע 19.11.2026, q4, מומש): רק אם אחרי הכפתורים נשארים לתיבת הקלט לפחות 116 פיקסלים (`minInputWidthTouchButtons`, כשמונה אותיות). החישוב: רוחב השדה פחות אייקון (36) וריפוד (8), פחות 40 לכל כפתור ו־48 ל־X של הניקוי (נספר תמיד כשיש `onClear`, כדי שהכפתורים לא יקפצו בהקלדה הראשונה). בפועל: עד שני כפתורים מ־320, ארבעה מ־400. בכל מקרה אחר הם נשארים 26 והשדה 36 (חריגה מותרת, כמו לפני). כשהפעולות מוצגות מתחת לשדה (`actionsBelow`) הן לא נספרות. שדה רחב (48) נשאר 32, ושדה טופס 40. הנימוק לחריגה: בטלפון צר הגדלה אוכלת את רוחב תיבת הקלט (המדידה ב־18.11, שדה צר 36, עם X של 48: ב־320 עם 4 כפתורים ועם ה־X נשארים 92 פיקסלים לטקסט כשהכפתורים 26, ‏36 ב־40, ו־4 ב־48). ה־X של הניקוי ממשיך להיות 48 במגע.
  - `SquareIconButton` (36 במצומצם), ‏`PrimaryIconButton`/`SecondaryIconButton` בכרטיסי תוצאה (36 קבוע), תיבות הסימון של המפרשים והצ'יפים של המסננים (`compact` + `shrinkWrap`).
  - פריטי תפריט הקשר: גובה 36 (28 בצפיפות מצומצמת, `menu_metrics.dart`), גם במגע. רק תפריט היסטוריית החיפוש וחיפוש הכרטיסיות הם 48 במגע.
  - ידית שינוי הגודל של חלונית במגע (§5.3.1): גלויה תמיד ושטחה 32 (מומש 19.11.2026).
  החלופה במגע לכל אלה היא פעולה אחרת באותו מסך (כפתור גדול יותר, או תפריט הקשר), ולא הגדלה.
- **איך מזהים "מגע" (הוכרע 18.11.2026, ללא שינוי בקוד):** "מגע" נקבע לפי **מערכת ההפעלה**. פירוט ב־§5.6.

#### 2.5.7 מגבלות רוחב
| טוקן | ערך | סטטוס |
|---|---|---|
| `LayoutConstraints.panelContentMaxWidth` | 860 | קיים |
| רוחבי דיאלוג | `AppDialogSize.small` ‏400 / `medium` ‏560 / `large` ‏720 / `full` (DD-07) | קיים |
| חלונית צד | `LayoutConstraints.sidePaneWidth` ‏340, טוקן אחד (DD-28). מידות כל חלונית לפי מסך: `SidePaneSpecs` (§5.3) | קיים |
| חלונית צפה (`ContextOverlayPanel`) | `SidePaneSpecs.overlayPanelWidth` ‏350 (קבוע ב־`SidePaneSpecs`, לא רשומת `SidePaneSpec`; סעיף 45, מומש 19.11.2026; 340 בסבב ג', 350 מ־19.11 סבב ג'־2, כמו חלונית המפרשים). `LayoutConstraints.overlayPanelWidth` ‏400 נשאר לשכבת ההשלמה בשמור וזכור | קיים |
| רוחב תוכן מינימלי ליד חלונית | `LayoutConstraints.mainContentMinWidth` ‏500 | קיים |
| רוחב ברירת מחדל של חלונית המפרשים | `LayoutConstraints.commentaryPaneDefaultWidth` ‏350 (הוכרע 18.11.2026): ספר טקסט וספר PDF שומרים את הרוחב באותו מפתח (`key-commentary-pane-width`) ומתחילים מאותו ערך. הערך מוגדר פעם אחת; הפעלה ראשונה כותבת אותו להגדרות | קיים |

#### 2.5.8 צפיפות: קומפקטי ורגיל [מחייב] (DD-10 B) · קיים
`ThemeExtension<AppDensity>` אחד שנבנה ב־`AppThemeData` מתוך ההגדרה "צפיפות ממשק" ומכיל:
- גובה סרגל, גובה שדה וגודל כפתור סרגל;
- גודל אייקון בסרגל ו־menu metrics. **התפריטים צפופים יותר במצב הקומפקטי**;
- `isCompact`.

שינוי ההגדרה מתעדכן מיד בכל הממשק. שם ההגדרה למשתמש נשאר **"צפיפות ממשק"**, והבורר הוא "רגיל | אוטומטי | מצומצם" ("אוטומטי" באמצע; סקירת 4.11, סבבים רביעי וחמישי, q-density-auto ו־q-auto-order). "אוטומטי" הוא ברירת המחדל, בלי מפתח שמור (`key-compact-menu-mode` נמחק): מצומצם ב"חלון קטן" (`AppDensity.isSmallWindow`: בטלפון ובטאבלט צד קצר מתחת ל־600, במחשב רוחב מתחת ל־600 או גובה מתחת ל־480, לכל חלון לפי גודלו) ורגיל בשאר, ותת־הכותרת אומרת למה הוא מתורגם כרגע. "רגיל" ו"מצומצם" נשמרים כבחירה מפורשת, גם בחלון נמוך. כשהצפיפות שבפועל מתהפכת עם החלון, התוספים מקבלים `theme.changed` (DD-15). רכיבים קוראים `AppDensity.of(context)`. **[אסור]** לקרוא את `compactMenuMode` מתוך רכיב תצוגה. מחוץ ל־`lib/theme` ולהגדרות הוא נקרא היום רק ב־`app.dart` וב־`main_window_screen.dart`, וב־`lib/widgets` הכלל UIL-025 נועל אותו.

---

## 3. קטלוג הרכיבים המשותפים

**כלל השימוש [מחייב]:** בכל תפקיד שמופיע בקטלוג משתמשים ברכיב שהקטלוג מציין. רכיב שמסומן **יעד** עוד לא קיים. עד שיתווסף, משתמשים ברכיב הקיים שמצוין לצידו, ולא בונים עותק מקומי.

**כלל עיצוב ה־API [מחייב]** (חל על כל רכיב חדש ועל כל שינוי חתימה):
1. וריאנטים בנויים כ־named constructors או כ־enum סגור, למשל `ActionButton.recommended`. אין בוליאנים שמשנים את המראה.
2. אין פרמטרים של צבע, ריפוד, `TextStyle` או `shape` שנועדו לעקוף את התקן. פרמטר כזה מותר רק כשהוא חלק מהתפקיד עצמו, למשל `MetaChip(tone:)`, או כשהוא מקבל תפקיד ולא ערך: `AppDialogFrame(backgroundColor: AppSurfaces.panelBackground(context))` בדיאלוג שגופו לוח כלים.
3. אין `dynamic`.
4. רכיב משותף לא מייבא קוד פיצ'ר: לא settings bloc, plugins registry, tabs או models של ספרים (UIL-024). את הצפיפות הוא מקבל מ־`AppDensity`, ונתוני תחום מגיעים כפרמטרים.
5. פרמטר שאין לו אף קורא נמחק בשינוי שנוגע ברכיב.
6. לפני שינוי חתימה בודקים את כל הקוראים, וכותבים בדיקת חוזה לפני ההסבה. שכבת תאימות זמנית נשארת רק כשהיא נחוצה בפועל, עם תנאי הסרה כתוב, ולא נשארות שתי דרכי מימוש מתחרות.

### 3.1 דיאלוגים

**המסגרות:** `AppDialog` (שאלות קצרות, מאחורי `showTwoActionsDialog`/`showWarningDialog`/`showSingleActionDialog`), `AppDialogFrame(size:)` לכל השאר, ו־`InputDialog`/`SelectionDialog` מאחורי `showInputDialog`/`showSelectionDialog`. `AppCustomContentDialog` ו־`ListDialogFrame` הוסרו לטובת `AppDialogFrame`. UIL-001 נעול (`strict`) בלי חוב: הדיאלוג הגולמי היחיד מחוץ למסגרת הוא `ad_popup_dialog.dart` (פטור לפי נתיב `lib/widgets/dialogs/**`, ברוחב קבוע 600 שאינו מותאם לחלון צר). כל פתיחה עוברת ב־`showDialogUntilTornDown` (הוכרע 18.11.2026): `showDialog` גולמי בלשונית קריאה לוכד את ערכת הנושא של הלשונית ונשאר בצבעי הערכה הישנה כשמחליפים ערכה. `barrierColor` אופציונלי בתוך העזר. הבדיקה `test/widgets/dialogs/dialog_open_path_test.dart` סורקת את `lib` ומזהה גם פתיחה גולמית שה־builder שלה הוא `settingsDialogBuilder`. אין עוד פתיחה גולמית ב־`lib` (הרשימה הזמנית `_pending` בבדיקה נמחקה); מה ש־UIL-028 עוד סופר ב־baseline מפורט ב־`CI_ENFORCEMENT.md`.

#### משפחות הדיאלוג [מחייב] (DD-07 B, DD-16 A) · קיים

**[מחייב]** רצועת כותרת (`AppDialogHeader`) ותג אייקון **בכל** דיאלוג, כולל `small` (DD-07 B). האייקון מתאר את הפעולה. אם אין לה אייקון שאומר משהו, משתמשים באייקון של משפחת הדיאלוג (`AppDialogIcons`: מידע, אישור, אזהרה, קלט, בחירה, התקדמות).

**[מחייב]** ב־`small` אין X (DD-07, השלמה 2.11): סוגרים ב״ביטול״ (או בכפתור הסגירה של הדיאלוג), ב־Escape או בלחיצה בחוץ. `AppDialogFrame` קובע את זה לפי הגודל. מ־`medium` ומעלה ה־X נשאר.

**[מחייב]** (DD-07, השלמה 2.11): שאלה קצרה עם שלוש או ארבע פעולות (טיוטת הערה, התנגשויות בייבוא) היא `medium`, כדי שכל הכפתורים יהיו בשורה אחת, ולכן יש בה X. גוף כל דיאלוג בצבע הדיאלוג (`surfaceContainerHigh`). דיאלוג עם `height` מפורש מוגבל לגובה החלון ולא ל־85%.

| משפחה | רכיב | מתי | כותרת | תג אייקון | X | גודל / גובה | גלילה | פעולות |
|---|---|---|---|---|---|---|---|---|
| **אישור פשוט** | `showTwoActionsDialog` | שאלת כן/לא שאינה הרסנית | רצועה | כן | לא | `small` (400), לפי התוכן | לא | ביטול (`neutral`) + אישור (ראשי) |
| **אזהרה** | `showWarningDialog` | פעולה הרסנית או בלתי הפיכה | רצועה, טון שגיאה | כן, אזהרה בטון שגיאה | לא | `small` | לא | ביטול (מוקד) + אישור (`warning`) |
| **מידע** | `showSingleActionDialog` | הודעה שדורשת קריאה, כשאין די ב־`UiSnack` | רצועה | כן | לא ב־`small`, כן ב־`medium` | `small`/`medium` | אם התוכן ארוך | סגור: `AppDialog.singleAction` מציג כפתור אישור יחיד בולט (`ActionButton.recommended`), גם עם `confirmText: 'סגור'`; הוכרע להשאיר רועש (19.11.2026, q56, כרטיס 212) |
| **קלט** | `showInputDialog` | שדה טקסט אחד | רצועה | כן | לא | `small` | לא | ביטול + אישור. Enter בשדה = אישור |
| **בחירה** | `showSelectionDialog` | בחירת פריט אחד מרשימה | רצועה | כן | לא | `small` × עד 60% גובה | רשימה | ביטול. Enter על פריט = בחירה |
| **בחירה בין N אפשרויות** | `showChoiceDialog` | 3+ פעולות שוות, למשל "טקסט / Word / ביטול" | רצועה | כן | לא | `small` | לא | N ראשיות/ניטרליות + ביטול |
| **בינוני (טופס, תוכן מורכב)** | `AppDialogFrame(size: medium)` | טופס של כמה שדות, הגדרה ממוקדת, עורך ההערות (השלמה 2.11), שאלה עם 3–4 פעולות | רצועה | כן | כן | 560, לפי התוכן עד 85% | `AppDialogFrame(scrollable: true)` | בשורת הפעולות: משני → ראשי |
| **גדול / "מסך כדיאלוג"** | `AppDialogFrame(size: large)` | רשימות (סימניות, היסטוריה, גרסאות), ניהול | רצועה + מונה ב־`trailing` | כן | כן | 720, **לפי התוכן עד 85%**. רשימה עם שורת חיפוש: **85% קבוע**, כדי שהחיפוש לא יזוז בזמן ההקלדה (השלמה 2.11) | מובנה | אופציונלי |
| **עם לשוניות** | `AppDialogFrame(size: large, tabs:)` | דיווח שגיאה, הגדרות מרובות | כנ"ל + `TabBar` | כן | כן | 720, בגובה קבוע. דיווח שגיאה: 720×560 (השלמות 2.11 ו־3.11) | לכל לשונית | |
| **תהליך / התקדמות** | `runWithBlockingProgress` | פעולה חוסמת של יותר מ־~300ms | רצועה | כן | לא (או "בטל" אם התהליך ניתן לביטול) | `small` | — | בטל (אופציונלי) |
| **מסך מלא** (הדפסה) | `AppDialogFrame(size: full)` | תצוגה מקדימה עם חלונית הגדרות. עורך ההערות אינו כאן: `medium` (השלמה 2.11) | רצועה + פקדים בתחילת הכותרת, לפני התג (השלמה 2.11) | כן | כן | 100% פחות שוליים | | |

**ניסוחים [מחייב] (הוכרע 18.11.2026):**
- **כותרת דיאלוג של מחיקה או הסרה היא שאלה: "למחוק את X?" / "להסיר את X?", ולא שם פעולה ("מחיקת X", "הסרת X").** כפתור האישור הוא "מחק" כשהפעולה מוחקת מידע, ו"הסר" כשהיא מסירה בלי למחוק את המקור (תיקיית ספרייה, מסד מקושר, עמודה, ספר מרשימת המעקב).
- דיאלוג שיש בו רק סגירה: התווית היא "סגור" (לא "סגירה"). ב־`AppDialog.singleAction` זה כפתור `ActionButton.recommended`, בולט, גם עם `confirmText: 'סגור'`: ההכרעה הסופית של הבעלים (19.11.2026, q56, כרטיס 212) היא להשאיר רועש, והקוד לא השתנה בסבב ג'. דיאלוג שנבנה ביד ורוצים בו כפתור סגירה שקט משתמש ב־`ActionButton.neutral` מפורש; `ActionButton.recommended` מפורש עם "סגור" נאסר ב־`dialog_wording_test`.
- נאכף ב־`test/widgets/dialogs/dialog_wording_test.dart`. הכותרות החדשות מתורגמות לאנגלית בקטלוג (`settings_en.arb`) כמחרוזת שאלה.
- **לא הוכרע ולא מומש:** כלל "'בטל' רק לביטול אמיתי" וכלל "כותרת שמתארת את הפעולה ולא 'אזהרה'" (הצעת המקור שלא נשאלה).

**חוזה התנהגות של כל המשפחות [מחייב] (DD-08 A) · קיים:**

| נושא | התקן |
|---|---|
| **Escape** | סוגר תמיד. אם יש שינויים שלא נשמרו, מוצגת קודם שאלת אישור. Escape לא בולע מקשים מרכיבים פנימיים, ונשען על `DismissIntent` של ה־route ועל `PopScope`. |
| **Enter** | כשהפוקוס בשדה טקסט חד־שורתי, Enter מפעיל את **הפעולה הראשית** אם היא זמינה. בשדה רב־שורתי Enter מוסיף שורה. כשהפוקוס על כפתור או על פריט ברשימה, Enter מפעיל **את הרכיב הממוקד**: על "ביטול" הוא מבטל. |
| **חיצים** | לא נבלעים ברמת הדיאלוג. ניווט בין כפתורים נעשה ב־Tab, או בחיצים רק בתוך `FocusTraversalGroup` של שורת הפעולות. |
| **barrier** | לחיצה מחוץ לדיאלוג סוגרת אותו, אלא אם יש שינויים שלא נשמרו או תהליך פעיל. |
| **שינויים שלא נשמרו** | פרמטר אחד, `isDirty` (או `onDismissRequest`), ב־`AppDialogFrame` וב־`AppDialog`, שחל על **כל** דרכי היציאה: X, ביטול, Escape ו־barrier. השאלה "לסגור בלי לשמור?" היא `AppDialog.warning`. |
| **פוקוס פותח** | השדה הראשון. בדיאלוג אזהרה: כפתור הביטול. |
| **פוקוס בסגירה** | חוזר לרכיב שפתח את הדיאלוג (`showDialogUntilTornDown` / `registerDialogFocusRestorer`). |
| **Semantics** | ל־route יש `label` עם כותרת הדיאלוג. `AppDialogFrame` מספק אותו, ו־`Dialog` גולמי לא. |
| **מובייל (<600, DD-16)** | `small`/`medium` ברוחב החלון פחות 16, ו־`large`/`full` במסך מלא עם X (בדסקטופ: מתחת לשורת הכותרת של החלון). הרצועה נשארת. ב־`small` אין X, ומ־`medium` ומעלה ה־X הוא שטח מגע של 48. גם בכל חלון נמוך (גובה <480, בכל רוחב) `large`/`full` במסך מלא (q12 Q8). |
| **פתיחה** | תמיד דרך `showDialogUntilTornDown` (או העזרים שעוטפים אותו, כמו `showTwoActionsDialog`), כדי לשמור על הכיווניות של הפותח ועל ניקוי מסודר בסגירה. בהגדרות: `settingsDialogBuilder`. |

**[אסור]** בקוד חדש:
- `AlertDialog(`, `Dialog(`, `SimpleDialog(` מחוץ ל־`lib/widgets/dialogs/` (UIL-001).
- `showDialog(` עם builder שמחזיר אחד מהם.
- `Navigator.of(context).pop()` על route שנפתח ב־root navigator. משתמשים ב־handle שהעזר מחזיר.

### 3.2 כפתורים ופעולות

| תפקיד | רכיב | הערות |
|---|---|---|
| ראשי | `ActionButton.recommended` | אחד לכל קבוצת פעולות |
| משני / ניטרלי, **וביטול בדיאלוג** | `ActionButton.neutral` (tonal) | DD-09 A |
| פעולה משנית שקטה שאינה ביטול ("דלג", "איפוס" בתוך פאנל) | `ActionButton.ghost` | גם מספר העמוד ו"אפס" בסרגלי ה־PDF (q10 Q7.2, Q7.3) |
| פעולה צפופה בתוך הודעה, שורה או פירורי לחם | `ActionButton.inline(text:, onPressed:, color:, tooltip:)`: ghost בלי גודל מינימלי, ריפוד 8×4 ושטח מגע בגודל הכפתור (q10 Q7.1, Q7.8, Q7.9) | פעולת `UiSnack`, פירורי הלחם ו"רק" בתפריט ההיקף. `color` רק כשההקשר קובע אותו, למשל טון ההודעה |
| אייקון אחרי הטקסט ("הבא", "הצג עוד") | `iconAlignment: IconAlignment.end` בכל וריאנט חוץ מ־`inline` (q10 Q7.4, Q7.6) | ברירת המחדל `start` |
| מסוכן (אישור מחיקה) | `ActionButton.warning`: כפתור מלא, רקע `error` וטקסט `onError` (DD-09, השלמה 3.11) | רק בתוך דיאלוג אזהרה או אחרי אישור. כפתור "מחק" ראשוני ברשימה הוא `neutral` או אייקון. גם ״דרוס״ בייבוא ההערות, ליד שלושה כפתורי `neutral` (השלמה 3.11) |
| מסוכן על מסך הגדרות (לא בדיאלוג): "נקה הכל", "הסר", "מחק" | `ActionButton.warningSoft`: רקע `errorContainer` וטקסט `onErrorContainer` (DD-09, הערה 4.11) | **[מחייב]** אדום מלא רק בדיאלוג. על מסך או חלונית הגדרות הכפתור ההרסני רך, וכפתור האישור בדיאלוג שהוא פותח הוא `ActionButton.warning`. נאכף ב־`destructive_button_contract_test` (‏`lib/settings/tabs`, ‏`lib/settings/panels`) |
| אייקון בלבד, כללי | `AppIconButton(size: small\|medium\|large)`: עטיפה דקה על `IconButton` שמחייבת `tooltip`. אייקון 16/20/24 מ־`AppTokens.icon*`, ריבוע האייקון ועוד 16 (ועוד 12 בצפיפות קומפקטית), פינות 8 (DD-04, השלמה 19.11). `isSelected` צובע ב־`primary`. ‏`small`: אייקון 16 בריבוע 32 (השלמה 3.11). **עם רקע (הוכרע 18.11.2026):** `fill: AppIconButtonFill.tonal` (`secondaryContainer`, כמו `IconButton.filledTonal`) או `neutral` (`surfaceContainerHighest`); צבע מבחוץ: `backgroundColor`/`foregroundColor`. הצורה זהה עם רקע ובלי: פינות 8 (DD-04, השלמה 19.11). `extent:` קובע צלע כשהמארח קובע אותה (שדה חיפוש); `selectedIcon:` לאייקון במצב נבחר | חלקי: השכבה המשותפת, שורת הכותרת ועמודת הכרטיסיות הוסבו, ועשרה כפתורי רקע צבועים עברו ל־`fill:`. בפיצ'רים (מחוץ ל־`lib/widgets`) נשארו `IconButton` גולמיים פשוטים ומכוילים (כ־84 לפני ההסבה, ספירת grep 18.11) |
| אייקון בתוך שדה / בסרגל צר | `SquareIconButton.field` / `.toolbar` | קיים |
| פעולת סרגל | `BarButton.icon` / `.text` | צורה 8, בלי גלולה (DD-04) |
| פעולה מפוצלת | `BarSplitButton` | צורה: גלולה, חריג מאושר ל־״8 בלבד״ (DD-04, השלמה 2.11) |
| פעולת רשימה / שורה | `AppIconButton(size: small)`. בשורת הגדרה: `SettingsActionTile` actions | אין hover כפול על השורה. גם כפתורי הפעולה בכרטיס הערה, ליד הספר ובמסך הניהול (השלמה 3.11, q10 Q25) |
| רמות ופתיחה אוטומטית בתוכן העניינים בעיון | תפריט `AppPopupMenuButton` במקום `NavTreeCollapseAllButton` (#3236) | כווץ הכל, הצג עד רמה N, הרחב הכל, ומתג "פתיחה אוטומטית לפי מיקום הקריאה"; הבחירה נשמרת לכל הספרים. ב"כותרות" `NavTreeCollapseAllButton` חל על המבנה המוצג, ואינו מוצג ב"דיבורי המתחיל". כשהכותרת נגללת החוצה הכפתור צף ליד אייקון החיפוש (`NavPanelCollapsibleSearch.floatingActions`, #4607) |
| "הרחב הכל / כווץ הכל" בכותרת עץ ניווט | `NavTreeCollapseAllButton(isCollapsed:, onCollapseAll:, onExpandAll:)` על `AppIconButton(small)` (DD-27, q12 Q4, #3103) | **[מחייב]** כלל אחד בתוכן העניינים ובעץ החיפוש: כשהכל מכווץ "הרחב הכל", כשמשהו פתוח "כווץ הכל". "מכווץ" = אין ענף גלוי פתוח מעבר למצב המכווץ, גם כשענף (או השורש) נסגר ביד. אין כפתור כשאין ענף שאפשר לפתוח |
| גלולת מצב בשורת הכותרת (עדכון זמין, מוריד, מוכן להתקנה) | `StatusChip`. מצב פעיל שאינו פעולה ("מוריד…"): `StatusChip.busy(icon:, label:, tooltip:)` (q10 Q6) | משטח `primaryContainer` עם מסגרת `primary`, אייקון ותווית `labelLarge` w700. `onPressed: null` מושבת. `busy` באותם צבעים כמו הלחיץ, בלי ריחוף, וקורא מסך קורא אותו כטקסט. `tone: StatusChipTone.error` (משטח `errorContainer`, מסגרת `error`) לכשל. כרטיס עבודה ברקע שמצטמצם (`WorkStatusItem.chipLabel` + `collapseAfter`, #2082) מוצג בשורת הכותרת כ־`StatusChip` לחיץ (`WorkStatusTitleChips`) שפותח את הכרטיס מחדש |
| קומפקטי | אותם רכיבים עם `AppDensity` | אין רכיב "קומפקטי" נפרד |

**מצבים [מחייב]:**
- **hover/pressed/focus:** מגיעים מערכת הנושא (`_hoverButtonStyle`). לא מגדירים אותם מקומית. ב־`IconButton` גם הצורה (פינות 8) מערכת הנושא (DD-04, השלמה 19.11).
- **פוקוס מקלדת:** טבעת `primary` בעובי `focusRingWidth`, במרחק 2 מחוץ לכפתור (`AppFocusRing`, q11 Q2). רק במצב ניווט מקלדת: מאז הלחיצה האחרונה נלחץ Tab או חץ (לא Enter, ‏Delete או קיצור), כך שדיאלוג שנפתח במקלדת נפתח בלי טבעת. לחיצת עכבר או מגע מכבה אותה, גם כשהפוקוס נשאר (סקירת 4.11). היא ה־`side` שבערכת הנושא, ולכן כפתור לא קובע `side` משלו (זה דורס את הטבעת).
- **disabled:** `onPressed: null`.
- **loading:** `ActionButton(isLoading:)`. יעד: לשמור על רוחב הכפתור ולהוסיף `Semantics(liveRegion)` "טוען".

**מדיניות Tooltip [מחייב]:** לכל כפתור שמכיל אייקון בלבד יש `tooltip` (UIL-003). הטקסט שלו הוא גם השם הנגיש. אם יש קיצור מקשים, הוא מופיע ב־tooltip בצורה `"הדפסה (Ctrl+P)"`, בעזרת `ShortcutHelper.formatShortcutForDisplay`. כפתור עם תווית טקסט לא צריך tooltip.

**[אסור]**
- `TextButton(`, `FilledButton(`, `OutlinedButton(`, `ElevatedButton(` מחוץ ל־`lib/widgets/controls/`. תשעת הכפתורים הגולמיים האחרונים הוסבו (q10 Q7), ואין יותר כאלה בפיצ'רים. נאכף ב־UIL-002 (נעול).
- `IconButton` בלי `tooltip`.
- `IconButton` בתוך `ResponsiveActionBar` במקום `BarButton`.

### 3.3 שדות וטפסים

| תפקיד | רכיב | הערות |
|---|---|---|
| שדה טקסט | `RtlTextField` + `InputDecoration` מערכת הנושא | `TextField` גולמי אסור (UIL-011) |
| שדה מספרי | `RtlTextField(keyboardType: number, inputFormatters)` | הספרות תמיד LTR |
| חיפוש | `OtzariaSearchField`. בחלונית ניווט: `NavPanelCollapsibleSearch` | אייקון לפי היקף החיפוש (`agent_ui_reference` §1). כפתור ניקוי אחד, `OtzariaSearchClearButton`, וגודל הכפתורים נגזר מהשדה. כפתור סינון של תוסף (`providerBooksFilter`): במצב סינון אייקון ותווית קצרה בצורת צ'יפ (פינות 8, ‏`labelMedium`, q10 Q23), ״רק התוסף״ / ״רק הספרייה״, שהתוסף יכול להחליף (`pluginOnlyLabel`, `libraryOnlyLabel` במניפסט); בשדה שאין בו מקום לתווית, אייקון ו־tooltip (DD-31, השלמה 3.11). **רמז מקוצר (הוכרע 18.11.2026):** `OtzariaSearchField.compactHintText` מוצג כשהרמז המלא (`hintText`) לא נכנס ברוחב הפנוי של הקלט; ההחלטה לפי **מדידה** של הרוחב בפועל והגדלת הטקסט, לא לפי סף קבוע של חלון. בספרייה הרמז המלא "איתור ספר או מחבר ב{category}" והמקוצר "איתור ספר או מחבר". גם המקוצר נחתך בשדה של 80 פיקסלים (320 במגע); מקובל. כפתורי השדה נשארים בגודלם (§2.5.6) |
| ניווט בין תוצאות | `SearchResultNavigator` | אחד, בשדות, בחלוניות החיפוש, בתצוגה המשולבת וב־PDF |
| תפריט פעולות, או בחירה מתפריט שנפתח מכפתור | `AppPopupMenuButton`, או `showAnchoredAppMenu` (‏`lib/widgets/misc/app_popup_menu.dart`) | צפיפות לפי `AppMenuMetrics` (DD-10). `PopupMenuButton`, ‏`showMenu` ו־`MenuAnchor` גולמיים חסומים (UIL-014) |
| בחירה אחת מרשימה נפתחת | `AppDropdownField` | `decoration.labelText` מוצג כתווית `labelMedium` מעל הכפתור ונקרא יחד עמו בקורא מסך (השלמה 2.11). בשדות בסרגל, שאין בהם מקום מעל: `semanticLabel` בלבד (שם נגיש ו־tooltip, בלי תווית גלויה) |
| 2–4 אפשרויות | `AppSegmentedControl`. בהגדרות: `SettingsSegmentedTile` | קיים. שני מצבים שהם הפכים של מצב אחד: מתג ולא בורר (DD-32, למטה). גם בורר מצב החיפוש ובורר שבוע/חודש בלוח השנה (DD-31a). במקטע צר מ־96 (`narrowBelowSegmentWidth`) האייקונים יורדים, ותווית ארוכה מתחלפת ב־`SegmentOption.shortLabel`, והמלאה ב־tooltip ("חיפוש חכם" ← "חכם", q12 Q8). עם `twoRowsWhenClipped` ההחלטה במדידה (`TextPainter`, ‏`segmentPadding`), וכשגם התווית הקצרה בלי אייקון נחתכת — שתי שורות (2×2), באותו סגנון, בחירה, חצים ו־semantics (q-ss7) |
| מתג קטן בתוך שורה | `AppTogglePill` | קיים. תווית `labelMedium` (12), כמו הצ'יפים שלידה (q10 Q1). גם מתג שתוסף מוסיף לדיאלוג החיפוש (q10 Q8e) |
| בחירה מרובה (פילטר) | `FilterChip` של Material + `chipTheme` (DD-13: פינות 8, תווית `labelMedium` 12) | `FilterChipsSelector` / `compactFilterChips`; `ChoiceChip` לבחירה אחת. גם תיבת סימון שתוסף מוסיף לדיאלוג החיפוש (q10 Q8e) |
| Checkbox | `Checkbox` של Material | יעד: `checkboxTheme`. השורה כולה לחיצה (`CheckboxListTile` או `InkWell`) |
| Switch | `SettingsSwitchTile`. מחוץ להגדרות: `Switch` | לכל הגדרה של הצג/הסתר, פעיל/כבוי (DD-32). `switchTheme` אחד בערכת הנושא. `CustomSwitch` הוסר, ו־UIL-033 חוסם את החזרה שלו |
| Slider | `SettingsSliderTile` | `SliderTheme` מקומי אסור |
| תאריך | `showDatePicker` + `datePickerTheme` | קיים |
| שגיאת אימות | `InputDecoration.errorText` | לא טקסט אדום שנבנה ידנית מתחת לשדה |
| קבוצת שדות | `SettingsCard`, או `AppCard` בתוך דיאלוג | |
| תווית מעל שדה | `InputDecoration.labelText` | לא `Text` נפרד עם `TextStyle` מקומי |

#### מתג או בורר [מחייב] (DD-32) · קיים

**[מחייב]** הגדרה עם שני מצבים שהם הפכים של מצב אחד (הצג/הסתר, פעיל/כבוי, כן/לא) מוצגת **כמתג**: `SettingsSwitchTile`, ומחוץ להגדרות `Switch`. לא בורר מקטעים ולא תפריט. דולק = המצב החיובי, כפי שהוא מנוסח בכותרת השורה: "ניקוד" דולק = הניקוד מוצג. כשהכותרת לא מבהירה מה דולק, מנסחים אותה מחדש, ולא משאירים בורר.

| ההגדרה | הפקד |
|---|---|
| שני מצבים, הפכים של מצב אחד | מתג |
| שתי חלופות שוות שאין ביניהן "דולק" (בהיר/כהה, ככתבם/בכינוי, רשת/רשימה, אשכנז/ספרדי) | `AppSegmentedControl` / `SettingsSegmentedTile` |
| שתי אפשרויות שהתוויות שלהן הן המידע, ובמתג הן נעלמות | בורר מקטעים |
| שלוש אפשרויות ומעלה | בורר מקטעים (עד 4), או `AppDropdownField` / `SettingsDropdownTile` כשהן רבות או ארוכות |

**מצב "לפי הגדרה אחרת":** כשיש מצב שלישי שעוקב אחרי הגדרה אחרת, מציגים מתג ולצידו תג קטן לחיץ בשם ההגדרה ("כמו הניקוד"):
- כשהתג בחור, המתג דהוי ומראה את המצב בפועל, ועדיין לחיץ.
- לחיצה על המתג קובעת ערך מפורש ומבטלת את התג. לחיצה על התג מחזירה את המעקב.
- דוגמה: טעמי המקרא בחלונית "תצוגת הטקסט" ובכרטיס "תצוגת הטקסט" בהגדרות (`TextDisplayProfileEditor.followNikudChip` + `teamimSwitch`).

**[אסור]** למחוק אפשרויות כדי שהפקד יהיה מתג. הגדרה שצריכה יותר משני מצבים, כמו "ללא שינוי / הצג / הסתר" בקיצור מקשים דינמי, שומרת עליהם: בורר, או מתג ותג כמו למעלה.

### 3.4 כרטיסים ורשימות

| תפקיד | רכיב | הערות |
|---|---|---|
| כרטיס מידע | `AppCard(tone: normal\|primary\|error\|inset)` | `Card(` גולמי אסור (UIL-012 נעול, אין חוב: כרטיס הזמן בלוח השנה עבר ל־`AppCard`). מסגרת, בלי צל (DD-12). `primary`/`error` על `primaryContainer`/`errorContainer`, והטקסט והאייקונים בצבע ה־on. `inset` לכרטיס בתוך כרטיס, על `surfaceContainerHigh` (q10 Q8a) |
| קבוצת שורות בכרטיס | `AppCard.section(children:)` | מפריד = רווח שקוף |
| כרטיס תוצאה (חיפוש וכלים) | `ResultCardFrame` (DD-11 A): צבע כרטיס, מסגרת `outlineVariant`, ריפוד `AppTokens.cardPadding` (12) ומרווח `AppTokens.listItemGap` (8) בין תוצאות | חלקי. בכלים דרך `ToolResultCardShell` (טקסט נבחר ולחיצה). מספר התוצאה: `SearchResultRankBadge`. עוד לא על המסגרת: כרטיסי איתור מקורות ורשימת תוצאות החיפוש במפרשים |
| היסטוריה וסימניות | **כרטיס בהיר לכל קבוצה** (DD-11, q12 Q9): `ItemsListView` בונה שורות בסגנון `AppCard.section`, רקע `AppSurfaces.card`, פינות בקצות הקבוצה ורווח `AppCard.sectionSpacing` בין השורות, בלי קו. גוף הדיאלוג `AppSurfaces.cardDialogBackground` וריפוד 16, כמו ב־upstream (סקירת 4.11) | גם הסימניות המרוכזות. |
| רשימה בחלונית צד (קישורים, מפרשים, הערות) | שורות שקופות על רקע החלונית, עם מפריד דק ביניהן. **בחלונית ההערות בלבד** כל הערה כרטיס מעוגל ברקע `AppSurfaces.tintedRow`, מוזח `spaceSM` מהקצוות, ובין הכרטיסים רווח `spaceSM` בלי קו (`NoteTile(backgroundColor:)`; ‏#3086, סקירת 4.11, סבב חמישי) | הערה חסרת מיקום מזוהה בכותרת הקבוצה שמעליה, לא בגוון. כרטיס הערה במסך ניהול ההערות הוא `AppCard` עם ריפוד `cardPadding` |
| דיאלוג הסבר בכמה נושאים | מקטעים כמו בדיאלוג "שינוי מיקום": `SettingsCard(title:)` לכל מקטע, כלומר `AppSectionLabel` ומתחתיו `AppCard.section` עם שורה לכל פריט (ריפוד 16/12 כמו `SettingsActionTile`), על גוף הדיאלוג בגוון הדיאלוג. בלי `Divider` בין המקטעים ובלי גוף כהה יותר | "הצגה או הוספה של הקבצים" (סקירת 4.11, ושנייה; 10.11: כרטיסים) |
| כרטיס עם פעולות | `AppCard` + שורת `ActionButton`/`AppIconButton` בסוף | |
| כרטיס פעיל ברשת (בורר שולחנות העבודה) | `AppCard(active: true)`: מסגרת `multiSelectedBorder` ‏1.5 במקום `outlineVariant`. אזור התצוגה המקדימה בלבד ב־`selectedRow` (אייקון וטקסט `onSelectedRow`); בלא פעילים `surfaceContainerHighest` ו־`primary` (DD-06, השלמה 3.11) | שורת השם בצבע הכרטיס. מחיקה: פח בשורת השם, מושבת בפעיל (DD-11) |
| כרטיס מתרחב | `ExpandableCard`, גם בהגדרות (DD-27) | חץ: `ExpandingChevron(style: accordion\|tree)` עם `Semantics(expanded:)` מובנה (DD-27 A). עץ (`NavTreeTile`, כותרות המפרשים, רשימת הקישורים): חץ לכיוון הקריאה, למטה כשפתוח. אקורדיון (`ExpandableCard`): חץ למטה, למעלה כשפתוח. כרטיסי התיקיות בספרייה (`ExpandableCard`) הם אקורדיון (השלמה 2.11). **פערים ידועים בהכרזת "מורחב":** כותרת קבוצת המפרשים ב־PDF (`pdf_commentary_panel.dart`) מסובבת חץ ידנית בלי `Semantics(expanded:)`, ושבעה מקומות מחליפים `chevron_up`/`chevron_down` בלי להכריז מצב (`app_report_preview_section`, ‏`search_dialog`, ‏`biography_card`, ‏`tantivy_search_results`, ‏`ad_popup_dialog`, ‏`work_status_overlay`, ‏`note_tile`). `ExpansionTile` גולמי נשאר בארבעה מקומות. ראו DD-27 |
| כותרת מקטע מתקפל בטבלה או בעץ עם עמודות | `TreeSectionHeader(isExpanded:, onToggle:, child:, leadingExtent:, padding:)` (‏`lib/widgets/lists/tree_section_header.dart`) | כל השורה לחיצה, החץ בסגנון עץ בתחילת השורה ברוחב `leadingExtent`, ושורות הילדים משאירות אותו רוחב ריק כדי שהעמודות יתיישרו. במקום `ExpansionTile` עטוף ב־Theme מקומי (q10 Q8d, שמור וזכור) |
| שורת הגדרה | `SettingsSwitchTile`, `SettingsDropdownTile`, `SettingsSegmentedTile`, `SettingsPathTile`, `SettingsSliderTile`, ו־`SettingsActionTile` (.text/.path/radioOption) לשאר, בתוך `SettingsCard` | **כותרת של שורת הגדרה** (`SettingsActionTile.text`, ‏`.path`, ‏`SettingsSwitchTile`, ‏`SettingsSegmentedTile`, ‏`SettingsDropdownTile`, ‏`ExpandableSettingsTile`) מקבלת **עד שתי שורות** (`maxLines: 2`, ‏`ellipsis` רק אחרי השנייה; הוכרע 18.11.2026), בכל מסכי ההגדרות. כך כותרת כמו "הדגש פרשנים קשורים" נקראת במלואה ב־320 ובהגדלת טקסט 1.3; השורה גבוהה יותר כשצריך, ואין לחתוך כותרת לשורה אחת. תת־כותרת ממשיכה להתעטף בלי הגבלה (`test/settings/widgets/settings_title_lines_test.dart`). בין כרטיסים בלשונית: **24 בכל הלשוניות** (השלמה 3.11): ריפוד הכותרת של `SettingsCard`, בלי מרווח נוסף. כרטיס שלפעמים לא מוצג לא משאיר מרווח. חלקי: עדיין נבנים ידנית ההדפסה, חלונית צורת הדף, `ShortcutDropDownTile`, `ColorPickerTile` ועוד |
| פריט רשימה | `ListTile`, או `NavTreeTile` בחלוניות | יעד: `listTileTheme` |
| פריט ניווט | `NavRailItem`, `SidebarNavItem`, `NavTreeTile` | |
| כרטיס ספר בספרייה | `BookGridItem` (`lib/library/view/grid_items.dart`) | התיאור הקצר חזר לגוף הכרטיס (הוכרע 18.11.2026): עד 3 שורות (שתיים כשהכותרת עוטפת, שורה אחת בכרטיס נמוך מ־100), ועד 120 תווים (`kBookCardDescriptionMaxCharacters`). הוסתר זמנית ב־28.7.2026 ("זמני"), ללא סיבה מתועדת. כרטיס **הקטגוריה** (`CategoryGridItem`) מציג גם הוא את התיאור הקצר (`Category.shortDescription`, הוכרע 19.11.2026, q63, מומש): עד שתי שורות, בשורות שנשארות מתחת לכותרת (ומתחת לנתיב ההורה בתוצאות חיפוש). כשגובה הכרטיס לא משאיר מקום (כותרת בשתי שורות בפס הצר) התיאור מוסתר, והטקסט המלא נשאר ב־tooltip של כפתור המידע |
| תגית / מונה | `MetaChip(tone: neutral\|primary\|error\|warning\|success\|tertiary, size: regular\|small, tooltip:)` (DD-13 A). תווית `labelMedium` 12 (`small`: `labelSmall` 11), צורה 8. `success` בגוון החום הנייטרלי (`secondaryContainer`), לא ירוק. `neutral` ב־`surfaceContainerHighest` (השלמה 2.11) | לא בונים צ'יפ מקומי. **גוון משלים (הוכרע 18.11.2026):** `MetaChipTone.tertiary` ו־`AppInfoBannerTone.tertiary`: `tertiaryContainer` על `onTertiaryContainer` (האייקון בצבע הטקסט). שימושים: תגית מקור התוצאה בחיפוש (`SearchResultSourceTag` עוטף `MetaChip(small)`), תגית "DEV" של תוסף פיתוח (`PluginDevBadge` עוטף `MetaChip(small)`), באנר סשן התיקון של תוסף, והצעת תיקון הפריסה בחיפוש. נשארו: `PluginUpdateChip`, תג הגימטריה |
| תג אייקון | `ListIconBadge` / `AppDialogIconBadge` | ריבוע מעוגל 8 בשניהם (DD-04) |
| קישור בתוך טקסט | `AppInlineLink(text:, onTap:, tooltip:, style:, textDirection:)` בתיקיית `lib/widgets/text` (הוכרע 18.11.2026): טקסט `primary` עם קו תחתון באותו צבע, `InkWell` עם פינות 8 וריפוד אופקי 2, פוקוס מקלדת רגיל. בלי `onTap` זה טקסט רגיל בסגנון שהועבר. קישור באמצע משפט (`Text.rich`): `TextSpan(style: AppInlineLink.styleOf(context, base), recognizer: ...)` (`TextSpan` אינו מקבל פוקוס מקלדת, ולכן שם משותף רק הסגנון) | הועברו: `app_info_dialog` (נתיב תיקייה, "הצג עוד"), `details_info_section`, `offline_donation_dialog`, `book_source_dialog`, `book_source_banner`, `biography_card`, `biographies_credit_line`, `zmanim_settings_dialog`, `layout_fix_suggestion_banner`. לא הועברו: שבב `about_settings_tab._InfoChip` (בלי קו תחתון), `book_detail_screen._SectionTitleLink` (קו תחתון רק בריחוף), וקישורים בתוכן הספר (`reader_line_spec`, ‏`continuous_reading_paragraph`, ‏`inline_html_document`) |
| בחירת צבע (עיגול) | `AppColorSwatch` (`lib/widgets/controls/app_color_swatch.dart`; הוכרע 18.11.2026): הרכיב היחיד לבוררי הצבע (צבע בסיס בהגדרות, צבע אירוע בלוח השנה). קוטר 40 ושטח לחיצה 48. הנבחר מסומן בוי (צבע הוי מחושב מבהירות העיגול, `AppSeedColors.checkColorOn`) ובמסגרת עבה (`borderThick`); עיגול שלא נבחר נשאר עם מסגרת `outline` דקה, כדי שלבן על דיאלוג בהיר וכחול כהה על דיאלוג כהה לא ייעלמו. `Semantics(button, selected, label)`, tooltip, ופוקוס/Enter/רווח. `color: null` = "ללא צבע" | אסור לצייר עיגול צבע בנפרד בבורר חדש |
| כותרת מקטע | `AppSectionLabel` (DD-14 A): `titleMedium`, `primary`, כותרת לקורא מסך. חריג: בדיאלוג החיפוש ובאיתור המקורות הכותרות הקטנות (13, w600, `primary`) נשארות (השלמה 2.11) | `SettingsCard` מצייר את כותרתו דרכו |
| מפריד שורות בדיאלוג | `listDialogRowDivider` | |

**[מחייב]** רשימה ארוכה (יותר מכ־50 פריטים) נבנית עם `ListView.builder` או `SliverList`. לא מחשבים סגנון בכל פריט: את `Theme.of` קוראים פעם אחת מחוץ ל־builder.

### 3.5 משוב ומצבים

| מצב | רכיב | הערות |
|---|---|---|
| טעינה, מסך או חלונית | `LoadingIndicator`, ועם הודעה `LoadingIndicator(message:)`, ועם אייקון `otzaria_icons` במרכז הטבעת `LoadingIndicator(icon:)` (מסכי טעינת ספרייה וספר: `strokeWidth: 3`) | חלקי: נשארו 45 מופעי `CircularProgressIndicator` גולמיים ב־baseline של UIL-013, מחוץ ל־`lib/widgets/feedback` (התקדמות מדודה, `value:`, יש לה רכיב משותף רק ב־inline) |
| טעינה, inline | `LoadingIndicator.inline()` (‏16px, ‏stroke 2); עם `value:` טבעת התקדמות מדודה | |
| טעינה, חלונית צרה עם הודעה | `LoadingIndicator.compact(message:)` (הוכרע 18.11.2026): ספינר 24, עובי 2, ההודעה מתחתיו ב־`bodySmall`. משמש את חלוניות המפרשים. גודל ההודעה אינו עוקב אחרי גופן המפרשים | |
| טעינה, שלד (skeleton) | `SkeletonLines` (רוחב כחלק מהמקום שקיבלו) | |
| ריק | `OtzariaEmptyState` (`isCompact` בחלונית) | |
| ריק "גדול" (ספרייה ריקה, הגדרה ראשונית) | `OtzariaEmptyState.large` (DD-31d) | גם מסך הנעילה של מצב סייפר (q10 Q8c) |
| שגיאה | `OtzariaErrorState(actions: [נסה שוב])` | לא `Text` אדום. **שמור וזכור** (`ErrorBoundary`) מציג `OtzariaErrorState` עם כפתור אחד "נסה שוב" (`_retry` ו־`_reset` היו זהים, ו"איפוס" נמחק); פרטים טכניים (debug בלבד) ב־`body` (הוכרע 18.11.2026). **שגיאת טעינת הספרייה** (`library_browser.dart`): כפתור מומלץ "נסה שוב" ששולח `RefreshLibrary` ל־`LibraryBloc` (הוכרע 18.11.2026); אם הבעיה קבועה (מסד פגום) הניסיון ייכשל שוב באותה שגיאה. גם מצב "אין נתוני ספרייה" (`noLibraryData`) מקבל כפתור מומלץ "נסה שוב" שישלח `RefreshLibrary` (הוכרע 19.11.2026, q35, מומש): שני מסכי הכשל של הספרייה (`loadFailed` ו־`noLibraryData`) נושאים אותו |
| הצלחה / הודעה קצרה | `UiSnack.show(<Module>Messages.x)` (למשל `SettingsMessages`) | מחרוזות מקטלוג בלבד (UIL-009). `UiSnack` מכריז את ההודעה לקורא מסך |
| באנר בתוך המסך | `AppInfoBanner(tone: info/warning/error/success/tertiary, title:)` (נוספו: `AppInfoBanner.rich` להודעה כ־`TextSpan`, ‏`trailing`, ‏`messageMaxLines`, ו־`onTap`/`focusNode` לבאנר לחיץ) (DD-24). `warning` מטוקני האזהרה, `success` בגוון הנייטרלי. `info` על רקע נייטרלי `surfaceContainerHighest`, אייקון `primary` וטקסט רגיל (השלמה 2.11). בלי מסגרת, כותרת `titleSmall`, הודעה `bodyMedium` | חלקי: נשארו הבאנרים ברוחב מלא בתוצאות החיפוש |
| תוכן לא זמין | `OtzariaEmptyState` עם הסבר | |
| פעולה מתמשכת | `ActionButton(isLoading:)`, או `runWithBlockingProgress` | |
| אישור מחיקה | `showWarningDialog` | כולל מחיקת קבוצת סימניות או היסטוריה (DD-31c) |

**[מחייב]** `UiSnack` אינו משמש למידע קריטי.

### 3.6 מסכים ופריסות

| דפוס | רכיב | הערות |
|---|---|---|
| מעטפת מסך לוח (הגדרות, ספרייה, כלים) | `AppTopBar` + רקע `panelBackground` + `LayoutConstraints.panelContentMaxWidth` | אזור "כלים ועבודה" (DD-18). גם מסך ההגדרות בטלפון, עם `BarButton.icon` (q10 Q8b) |
| מעטפת כלי חיפוש | `ToolScaffold` (`lib/widgets/layout`): סרגל עם שדה החיפוש, מסננים, גוף ושורת תחתית; הסרגל נשאר בטעינה ובשגיאת טעינה (`loading`, `loadError` + `onRetry`); קיצור "חפש בחלון" | קיים בחמשת כלי החיפוש |
| אזור תוכן | `PanelScrollableContent` / `CenteredScrollableState` | |
| כותרת מסך | `AppTopBar(center:)` עם `AppTopBar.titleStyle(context)` (`titleLarge`) / `subtitleStyle(context)` (`bodySmall`) | |
| סרגל עליון בחלונית צרה | `AppTopBar`: `leadingItems` ו־`trailingItems` מקבלים רוחב חסום, ולכן סרגל שמסתגל (`ResponsiveActionBar`, סרגל הקורא) מקפל את הפעולות ל־⋮ לפי המקום. פריט עם `AppTopBarItem.priority` שאינו `critical` (וגם `menuAction`) עובר ל־⋮ של הסרגל עצמו כשהפריטים לא נכנסים: `low` ראשון, אחריו `normal`, ובאותה עדיפות המאוחר. `critical` (ברירת המחדל) לא עובר לעולם. הסרגל עצמו לא גולל. גובה הסרגל קבוע (`AppDensity.topBarHeight`), וכותרתו (`AppTopBarTitle`) גדלה עד `AppTopBar.maxTextScale` = 1.3 ועוצרת (כמו תוויות הסרגל התחתון, §6.4; הוכרע 18.11.2026 ושוכלל 19.11.2026: התקרה חלה על הכותרת בלבד, ושדות חיפוש וכפתורים בסרגל גדלים כרגיל). בסרגל הקורא פריטי ההתחלה שקופלו נכנסים לתפריט ה־⋮ של פעולות הקורא (`AppTopBar(mergeFoldedIntoTrailingMenu: true)`): כפתור ⋮ אחד, לא שניים (q17, מומש). שורת "חזרה" בו פעילה רק כשיש היסטוריה | מדיניות "אין מקום": §5.4. במגע הריווח האנכי מצטמצם כך שכפתור 48 נכנס |
| סרגל פעולות | `ResponsiveActionBar` + `ActionButtonData` | פריטים דרך `BarButton` בלבד. תמיד שורה אחת: מה שלא נכנס עובר ל"עוד פעולות" לפי `toolbarOverflowOrder`, מהנדיר לנפוץ. גם סרגל העיצוב בעורך ההערות (q12 Q6): ברוחב הדיאלוג 10 כלים ו"עוד", בצפיפות קומפקטית כל 12 |
| הגדרות תצוגה לכמה יעדים בחלונית צפה | `TextDisplayPopupPanel` + `TextDisplayProfileEditor.popupTiles` (חלונית "תצוגת הטקסט" בסרגל הקורא, #3371) | רשימה צרה (300): כותרת ושם התצוגה בשורה מתחתיה; מקטע "גוף הספר" פתוח, ומקטע "מפרשים" בתחתית, מקופל ונפתח בלחיצה. הצג/הסתר כמתגים וטעמי המקרא כמתג ותג "כמו הניקוד" (DD-32). "שמות הקודש" מתג אחד לכל המקטעים: הסתרה מחליפה את שם הוי"ה בנוסח שבהגדרות (או יקוק) ואת שאר השמות בכינוי. בחירת הנוסח עצמו נשארת במסך ההגדרות. Esc סוגר. מחליף את הטבלה של q12 Q7 |
| חלונית ניווט | `NavSidePanel` | אזור "חלוניות לצד הקריאה" (DD-18). נסגרת אחרי מעבר רק כשהיא מכסה את התוכן (DD-26) |
| חלונית משנית או צפה | `AdaptiveSidePane` / `ContextOverlayPanel` | DD-28 A: רוחב 340 מ־`LayoutConstraints.sidePaneWidth`, הגבהה לפי DD-12, רקע לפי DD-18. מידות לפי מסך: `SidePaneSpecs` (§5.3). `ContextOverlayPanel` ברירת מחדל 350 (`SidePaneSpecs.overlayPanelWidth`; הוכרע 18.11.2026 כ־340, סעיף 45, מומש 19.11.2026, ועודכן ל־350 ב־19.11 סבב ג'־2). `LayoutConstraints.overlayPanelWidth` (400) נשאר רק לשכבת ההשלמה בשמור וזכור. זה שינוי מראה מכוון מההחלטה: הוא משפיע על לוח שנה, גימטריה, תיקון קוראים, הגדרות קריאה, צורת הדף ותוספים |
| ידית פתיחה של חלונית | `PositionedPanelOpenHandle` | ממוקמת לפי המכל שלה ולא לפי החלון |
| Split pane | `SplitPaneView` (tabs) | |
| מסך הגדרות | `SettingsTabScrollView` + `SettingsCard` | |
| מסך תוצאות | `ResultCardFrame`; מעל תוצאות כלי: `ToolResultsHeader(label, leading, child)` | אזור התוצאות על `panelBackground`, ועץ הסינון על `navPanelBackground` (DD-18) |
| סרגל תוצאות חיפוש | `SearchResultsLayout` (משותף לחיפוש הרגיל ולסמנטי): בחלון צר מ־600 מילות החיפוש (`SearchTermsDisplay` בתוך `OtzariaSearchDisplayBar`) עוברות לשורה שנייה של `AppTopBar` (`secondaryRow`) ברוחב מלא, והשורה הראשונה נשארת לכפתורים (עץ, מונים, מיון, איחוד, מקור חיצוני). מ־600 ומעלה הן במרכז הסרגל כמו קודם. בחלון צר הסרגל גבוה בשורה נוספת (כ־44 פיקסלים בטלפון) (הוכרע 18.11.2026) | **Enter במקלדת:** על תוצאה שעדיין לא מוצגת בתצוגה המקדימה הוא מציג אותה בה; על תוצאה שכבר מוצגת (גם כשהפוקוס בכרטיס שלה וגם ברשימה אחרי שהוצגה) הוא פותח את הספר בעיון, כמו לחיצה כפולה. כשהתצוגה המקדימה כבויה Enter פותח את הספר ישר. Enter עם Ctrl/Shift/Alt/Meta לא משתנה (הוכרע 18.11.2026; Ctrl+Enter נדחה) |
| מסך קריאה | `TextBookScreen` / `PdfBookScreen` על `readerBackground` | אזור "קריאה": בלי כרטיסים סביב טקסט הספר, צבע רק לתוכן. סרגל המפרשים המשותף: `CommentaryPanelToolbar` |

**[מחייב]** מעדיפים קומפוזיציה: מעטפת מסך מקבלת `child` ולא עשרות דגלים. מסך שלא מתאים לאף דפוס בונה פריסה משלו, אבל רק מרכיבים מהקטלוג.

---

## 4. ארכיטקטורת UI וגבולות אחריות

### 4.1 השכבות והמיפוי לתיקיות קיימות

המבנה הקיים כבר מממש את רוב החלוקה. **אין צורך בתיקיות חדשות**, רק בגבולות מוגדרים ונאכפים.

| # | שכבה | תיקייה קיימת | מותר | אסור |
|---|---|---|---|---|
| 1 | **Foundation** | `lib/theme/app_tokens.dart`, `app_colors.dart`, `app_input_tokens.dart`, `layout_tokens.dart`, `app_seed_colors.dart` | קבועים (`static const`): ריווח, רדיוס, גודל, משך, נקודות שבירה, פלטות תוכן | `BuildContext`, ייבוא Widgets, לוגיקה |
| 2 | **Theme** | `lib/theme/app_theme_data.dart`, `app_surfaces.dart`, ו־ThemeExtensions `AppSurfaceColors`/`AppDensity` | מיפוי של seed, בהירות וצפיפות לתפקידים ול־component themes. הגדרת שקיפויות ומצבים | קריאה ל־Bloc או ל־Settings. החלטות של פיצ'ר מסוים |
| 3 | **Shared Components** | `lib/widgets/**`, `lib/settings/widgets/**` (רכיבי שורת הגדרה), `packages/otzaria_context_menu` | רכיבים כלליים שמקבלים נתונים כפרמטרים ולוקחים סגנון מערכת הנושא | ייבוא מ־`lib/<feature>/`, קריאה ישירה ל־`SettingsBloc`, `Settings.getValue` או repositories, ומחרוזות תחום |
| 4 | **Layout Patterns** | `lib/widgets/layout/`, `lib/widgets/navigation/` | מעטפות מסך, חלוניות, סרגלים ופריסה רספונסיבית | ידע על סוג תוכן מסוים |
| 5 | **Feature Widgets** | `lib/<feature>/view/widgets/` | הרכבה של רכיבים משותפים לרכיב ייחודי, וגאומטריה שנגזרת מהתוכן | הגדרת צבע, גופן, רדיוס או ריווח שאינם טוקן. עותק של רכיב משותף |
| 6 | **Application Screens** | `lib/<feature>/view/*_screen.dart` | הרכבת מסך, חיבור ל־Bloc וניווט | IO, גישה ל־DB, `Settings.setValue`, חישובים כבדים ב־`build` |
| 7 | **Business Logic** | `lib/<feature>/bloc/`, `repository/`, `services/` | מצב, נתונים ו־IO | ייבוא `material.dart` (חוץ מ־`Color` כנתון) |

### 4.2 החלטות לפי שכבה

- **ערך עיצובי חדש** (גודל, צבע, משך): מוסיפים לשכבה 1 או 2, בתוך אותו שינוי שמשתמש בו.
- **וריאנט של רכיב קיים:** מוסיפים בשכבה 3 כ־named constructor. אם הווריאנט משמש פיצ'ר אחד בלבד, הוא נשאר בשכבה 5.
- **רספונסיביות:** נקודת שבירה כללית (סוג החלון) נקבעת ב־`LayoutBreakpoints`/`WindowClass`. החלטה שתלויה ברוחב הזמין לרכיב מתקבלת עם `LayoutBuilder` בתוך הרכיב, וקבוע הסף שלה מוגדר כ־`static const` עם שם בתוך אותו רכיב (סעיף 5).
- **התנהגות** (Escape, פוקוס, dirty) של משפחת רכיבים מוגדרת בשכבה 3 ולא בכל מסך בנפרד.

### 4.3 הפרות ידועות שנשארו

**רכיבים משותפים שמייבאים פיצ'רים** (UIL-024, 28 מופעים ב־baseline): `lib/widgets/commentary/**`, `lib/widgets/smart_text/smart_text_widget.dart`, תפריטי הקישורים (`link_context_menu_entry`, `direct_link_menu_entries`, `link_preview_overlay`), `ad_popup_dialog` ו־`phone_report_tab`. רכיב חדש לא מצטרף אליהם: הכלל חוסם.

**קבצים גדולים שמערבבים IO ולוגיקה עם בניית תצוגה:** `text_book_screen.dart`, `library_browser.dart`, `error_report_dialog.dart`, `system_settings_tab.dart`, `search_dialog.dart`, `find_ref_dialog.dart` ו־`page_shape_screen.dart`. חלקם פורקו (צינור השאילתה של החיפוש, פעולות הקורא, עמודות צורת הדף, הגדרות המערכת דרך `SettingsBloc`), והשאר עדיין גדולים.

**[מחייב] (DD-30 B)** שינוי שנוגע בקובץ כזה לא מוסיף לו IO או לוגיקה. אין פירוק נפרד מראש: הפירוק נעשה **בתוך ההסבה שזקוקה לו**, כ־commit נפרד שמשמר התנהגות (עם בדיקות characterization), **לפני** ה־commit שמשנה את המראה.

---

## 5. פריסה רספונסיבית

### 5.1 נקודות השבירה הכלליות
`LayoutBreakpoints`: ‏`compact < 600`, ‏`medium < 840`, ‏`expanded < 1200`, ומעל זה `large`. הערכים עקביים עם M3 ונשארים **[מחייב] · קיים**.

**[מחייב] (DD-15 A) · קיים:** סף "דיאלוג צר" 520 הוחלף ב־`LayoutBreakpoints.compact` (600), דרך `WindowClass.isCompact`. דיאלוגים בחלון ברוחב 520–600 עוברים לפריסה הצרה. UIL-022 חוסם השוואת רוחב חדשה לליטרל, גם כשהרוחב במשתנה מקומי (`width`, `screenWidth` וכדומה). אין לו חוב, והוא נעול.

**[מחייב] (q12 Q8) · קיים:** סף הגובה הוא `LayoutBreakpoints.compactHeight` (480, ה־compact height של M3), דרך `WindowClass.isShortOf(context)`. חלון נמוך הוא טלפון לרוחב, או חלון שטוח במחשב. בחלון כזה הגובה הוא האילוץ:
- **ניווט וכרטיסיות:** עמודה בצד, וכרטיסיות בשורת הכותרת ולא בשורה שנייה, גם מתחת ל־600 (`WindowClass.usesSideNavigationOf`).
- **צפיפות:** מצומצמת כשלא נבחרה, כי חלון נמוך הוא גם קטן (`SettingsState.compactMenuModeFor`). "רגיל" מפורש נשמר (סקירת 4.11, סבב שני).
- **דיאלוגים:** בכל רוחב, ‏`large`/`full` במסך מלא.

### 5.2 שני סוגי החלטות [מחייב] (DD-15 A) · קיים
1. **סוג החלון** (window class): ניווט צדדי מול ניווט תחתון, דיאלוג במסך מלא מול דיאלוג צף, מספר עמודות בדף הבית. נקבע דרך עזר יחיד, `WindowClass.of(context)` → `compact|medium|expanded|large`, לפי רוחב החלון מול `LayoutBreakpoints`.
2. **רוחב זמין לרכיב:** אם שורה גולשת לשתי שורות, אם מונה מוצג, אם התווית הופכת לאייקון. נקבע **רק** עם `LayoutBuilder`/`constraints`, כי הרכיב יכול לשבת בחלונית צרה בתוך חלון רחב. הסף הוא קבוע עם שם ברכיב, למשל `static const _iconOnlyBelow = 560.0`.

**[אסור]**
- `MediaQuery…size.width` להחלטה שתלויה במקום שהרכיב מקבל (skeletons, רוחב חלונית, ידית פתיחה).
- החלטת פריסה לפי `Platform.isAndroid` או לפי orientation, כשהשאלה האמיתית היא רוחב. דוגמה: חלונית ניווט נסגרת אחרי מעבר רק כשהיא מכסה את התוכן (DD-26).
- מספר קסם להשוואת רוחב בלי שם.

### 5.3 תרחישים נתמכים
| תרחיש | דרישה |
|---|---|
| מסך רחב (≥1200) | תוכן לוח מוגבל ל־860 וממורכז. חלוניות מוצמדות |
| מחשב נייד (840–1200) | כמו רחב. חלונית צד אחת מוצמדת לכל היותר |
| טאבלט (600–840) | חלוניות צפות עם scrim. דיאלוג `large` צף; במסך מלא רק מתחת ל־600 או בחלון נמוך (DD-16) |
| טלפון (<600) | ניווט תחתון. דיאלוגים לפי גודלם (DD-16, סעיף 3.1). שורות הגדרה בעמודה. כפתור "מסך מלא" בשורת הכותרת משמאל ל"הגדרות תצוגת הספרים", ובלי מקום שם בסרגל הקורא (במחשב: ליד כפתורי החלון ו־F11). "צפיפות ממשק" האוטומטית מצומצמת כשהצד הקצר מתחת ל־600. סרגל תחתון 64 עם תווית לכל יעד. בסרגל הקורא, ה־PDF וכרטיסיית המפרשים, חיצי הניווט בראש "עוד" רק כשארבעתם לא נכנסים ברוחב שהמרכז מקבל (`ReaderNavCenter.navFits`), והמרכז לכותרת. כשהם נכנסים הם קודמים לכותרת. בספרייה כרטיסי התיקייה נמוכים מכרטיסי הספר. כותרת מסך שרק חוזרת על שורת הכותרת של החלון לא מוצגת: בתפריט ההגדרות אין `AppTopBar`, והוא מופיע רק עם "חזור" (בלשונית ובתוצאות החיפוש) |
| חלון צר במחשב (420–600) | **כמו טלפון אבל עם עכבר.** שטחי הלחיצה נשארים לפי דסקטופ. "צפיפות ממשק" האוטומטית מצומצמת: במחשב חלון צר מ־600 או נמוך מ־480 הוא "חלון קטן". החלון המינימלי הוא 420×400 |
| חלון נמוך (גובה <480: טלפון לרוחב) | עמודה בצד וכרטיסיות בשורת הכותרת, גם מתחת ל־600. כרום בצפיפות קומפקטית. דיאלוג `large`/`full` במסך מלא בכל רוחב (q12 Q8). בספרייה התצוגה המקדימה סגורה עד שהמשתמש פותח אותה, והבחירה שם נשמרת בנפרד. במסך ההגדרות אין כותרת "הגדרות" מעל הרשימה, כי שורת הכותרת של החלון כבר אומרת אותה |
| חלוניות מפוצלות | כל חלונית מחליטה לפי ה־constraints שלה ולא לפי החלון. ידית הגרירה בסרגל (`AppTopBar`). לחלונית בלי סרגל, כמו תוסף, `FloatingPaneDragHandle`: במחשב רק בריחוף על הרצועה העליונה של החלונית (`hoverStripHeight`, ‏44, לכל הרוחב), ובמנוחה שקופה ולא חוסמת. במגע מוסתרת באותו אופן, ומופיעה בגרסה הקטנה רק אחרי נגיעה ברצועה. הנגיעה מגיעה גם לתוסף (`Listener`, לא נבלעת). הידית נעלמת אחרי `touchRevealDuration` (‏3 שניות), נשארת בזמן גרירה, והספירה מתחילה מחדש בסוף הגרירה. במגע לחיצה ארוכה על הידית (גם בסרגל הספר) מתחילה גרירה ולא הסבר: ה־tooltip שלה ב־`TooltipTriggerMode.manual` (#2635) |
| שינוי גודל בזמן ריצה | אין מצב שמחושב פעם אחת ב־`initState` לפי רוחב. רוחב שמור נשמר **כיחס** ולא בפיקסלים |
| הגדלת טקסט | ראו 6.3 |

#### 5.3.1 חלוניות צד: מידות והתנהגות (הוכרע 18.11.2026)

- **טבלה אחת לרוחבי חלוניות הצד.** כל מידות חלוניות הצד (`minMainContentWidth`, ‏`minPaneWidth`, ‏`maxPaneWidth`, רוחב קבוע, חלק מהרוחב) חיות ב־`SidePaneSpecs` (`lib/widgets/layout/side_pane_specs.dart`). מסך לא כותב מספרי רוחב בעצמו. `test/design_system/side_pane_specs_test.dart` מקבעת את הערכים ואוסרת מספרים כאלה בקוד מסך. יש 14 רשומות בטבלה (12 מסכים, שניים מהם עם שתי חלוניות: קורא PDF ותצוגה מקדימה בחיפוש/בספרייה). הערכים הם אלה שהיו, בלי שינוי מראה, והם שונים זה מזה בכוונה (קורא טקסט 520 לתוכן, קורא PDF 200). לא נכתב כלל lint: הבדיקה היא `flutter test` רגילה, כי הכלל דורש להבין ארגומנטים בשם ושמות של קבועים מקומיים, והתועלת מול מנוע ה־lint אינה מצדיקה כלל חדש או baseline.
- **רוחב חלונית המפרשים.** ספר טקסט וספר PDF שומרים את הרוחב באותו מפתח (`key-commentary-pane-width`) ומתחילים מאותו ערך, `LayoutConstraints.commentaryPaneDefaultWidth` = 350 (§2.5.7). "הרוחב של המפרשים אצלי" הוא הגדרה אחת משותפת.
- **חלונית ניווט נעוצה בחלון צר (כרטיסיית המפרשים).** בחלון צר החלונית הנעוצה היא שכבה עם הצללה. הקשה על ההצללה, Esc וכפתור הניווט סוגרים **רק את השכבה**; הנעיצה נשמרת (כפתור "בטל נעיצה" נשאר), והחלונית נפתחת שוב מעצמה כשהחלון מתרחב עד שיש מקום לדחיקה (`CommentatorsTabScreen`, ‏`PdfCommentatorsTabScreen`: `_pinnedOverlayDismissed`). בחלון רחב (דחיקה) נעוצה = פתוחה תמיד, והכפתור אינו עושה דבר; אייקון הכפתור משקף את הפתיחות בפועל. צמצום החלון אינו סוגר חלונית נעוצה מעצמו.
- **פתיחה מחדש בהרחבה.** `AdaptiveSidePane` פותחת מחדש (`onOpen`) רק חלונית שנסגרה אוטומטית בצמצום, או שהמסך פתח אותה סגורה בחלון צר. חלונית שהמשתמש סגר בעצמו (הקשה על ההצללה, כפתור, קיצור) נשארת סגורה גם אחרי צמצום והרחבה; פתיחה ידנית מבטלת את הסגירה.
- **ידית שינוי גודל במגע (הוכרע 18.11.2026, מומש 19.11.2026):** במסך מגע (`BarButton.isTouch`, כלומר `materialTapTargetSize == padded`) הידית של חלונית צד גלויה תמיד (`showIdleGrip` ברירת מחדל true, כמו בעמודת הכרטיסיות), ושטח הלחיצה שלה 32 (`AppTokens.dragHandleTouchHitSize`): 4 נכנסים לתוך החלונית (`kPaneHandleInnerReach`) ו־28 יוצאים מעבר לקצה. בעכבר: 24 (18 בצפיפות מצומצמת) והידית שקופה במנוחה, כמו קודם. הידית לחיצה כולה, כולל החלק שיוצא מעבר לקצה החלונית. הבדיקות `resizable_drag_handle_test` (4) ו־`adaptive_side_pane_test` (1) שמקבעות 24 והידית השקופה רצות כווריאנט Windows (`TargetPlatformVariant.only(TargetPlatform.windows)`), כי ב־`flutter test` ערכת הנושא ברירת המחדל היא מגע. תיקון נלווה (באג קיים): בפריסה הרחבה הידית יושבת בשכבה מעל השורה כולה (`_buildWideHandleLayer`), לא בתוך משבצת החלונית; קודם החלק של שטח הלחיצה שגלש מחוץ למשבצת לא קיבל נגיעות ונצבע מתחת לתוכן הראשי, כך שרק 14 מ־24 פיקסל היו לחיצים. בפריסה הצרה הידית מוגבלת לגבולות החלון.
- **פיצול כרטיסיות שכבר קיים כשהחלון מצטמצם (הוכרע להשאיר).** פיצול קיים נשאר שתי חלוניות צרות (`max(140, 20%)` כל אחת: `kMinPaneExtent` ו־`kMinPaneRatio` ב־`pane_drop_geometry.dart`), והסרגל הפנימי נבדק. החלון המזערי 420 פחות עמודת ניווט נותן כ־346 לשתי החלוניות, מעל הסף 298 של שער הרוחב לפתיחת פיצול (`canSplitPane`, ‏`TabsBloc`). מתחת ל־298 אין מעבר לכרטיסיות.
- **עמודת כרטיסיות מכווצת, סגירה במגע (הוכרע להשאיר).** הסגירה בלחיצה ארוכה שפותחת את תפריט הכרטיסייה (`TabTitleTooltip(alwaysShow: true)` בעמודה המכווצת, ‏`vertical_reading_tab_strip.dart`; "סגור"). אין X גלוי. בעכבר: X בריחוף.
- **לוח שנה בגובה נמוך וברוחב צר.** ברוחב מתחת ל־600 ובגובה לוח מתחת ל־600 (`_kStackedSidePanelMinHeight` ב־`calendar_screen.dart`; הסף עלה מ־450 ב־19.11.2026, סעיף 19) חלונית הזמנים/אירועים שמתחת ללוח מוסתרת כברירת מחדל והלוח תופס את כל הגובה; כפתורי "זמנים" ו"אירועים" בסרגל מציגים אותה. עם הגדלת הגובה היא חוזרת, אלא אם המשתמש סגר אותה. נמדד: מ־600 ומעלה אין גלישה בתאי היום גם כשהחלונית מוצגת.
- **פתיחה אוטומטית של חלונית הניווט בחלון בינוני (הוכרע ב', מומש 19.11.2026).** חלונית הניווט (ברירת מחדל, חיפוש, נעיצה) נפתחת אוטומטית רק כשיש מקום לדחיקה: לא מתחת ל־600, ורוחב החלון מכיל את הרוחב השמור של החלונית ועוד `SidePaneSpecs.<textReaderNav|pdfReaderNav>.minMainContentWidth` (520 לטקסט, 200 ל־PDF; בברירת מחדל 300 זה 842 בטקסט ו־522 ב־PDF). בחלון בינוני (600 עד 842 בטקסט) החלונית נשארת סגורה במקום להיפתח כשכבה עם הצללה על הספר, והמשתמש פותח אותה (כשכבה). בקשה מפורשת של המשתמש תמיד נשמרת. המדיניות ב־`readingLeftPaneFitsSideBySide` (`lib/utils/ui/reading_left_pane_policy.dart`).


### 5.4 מדיניות "אין מקום" [מחייב] · קיים

כשפעולה או תווית לא נכנסות ברוחב או בגובה שהרכיב קיבל, בוחרים **אחת מארבע** דרכים, לפי הסדר. הכלל המשותף: **פעולה חיונית לא נעלמת בלי חלופה גלויה** (כפתור "עוד ⋮", שורה שנייה, או גלילה שמגיעה אליה).

| סדר | דרך | מתי | הרכיב הקיים |
|---|---|---|---|
| 1 | **צמצום תווית**: תווית מתקצרת או הופכת לאייקון, והמלאה עוברת ל־tooltip ול־`Semantics` | התווית היא המקום היחיד שחסר | `AppSegmentedControl` (`SegmentOption.shortLabel`, האייקונים יורדים); לשוניות `NavPanelTabHeader` / `PanelTab` עוברות לאייקון בלבד כש־`PanelTab.labelFits` שלילי; פקד מיקום התוצאות החיצוניות הופך לכפתור אייקון; תוויות הסרגל התחתון (`BottomNavLabels.behaviorFor`) |
| 2 | **"עוד ⋮"**: פעולות עוברות לתפריט, מהנדירה לנפוצה | סרגל פעולות, כל הפעולות חשובות אבל לא חייבות להיראות | `ResponsiveActionBar` + `toolbarOverflowOrder`, תמיד שורה אחת; סרגל העיצוב בעורך ההערות (10 כלים ו"עוד" ברוחב הדיאלוג) |
| 3 | **שורה שנייה או עטיפה**: הטקסט יורד שורה במקום להיחתך | תווית או קבוצת נתונים שאי אפשר לקצר | תאריך ודף יומי בסרגל הספרייה; מעבר חודש/שבוע בלוח השנה ברוחב צר בשורה משלו מעל שורת התאריך; בורר "הצג \| הסתר \| כמו הניקוד" בהגדלת טקסט; תווית "שמור על סדר המילים"; `AppSegmentedControl(twoRowsWhenClipped)` ב־2×2 |
| 4 | **גלילה**: התוכן נגלל | אין חלופה נאותה, או שהמכל תוחם גובה | דיאלוג עם `scrollable: true`; כרטיס חיווי בחלון נמוך |

**אסור:** `Offstage`/`visible: false` של פעולה בלי "עוד"; חיתוך ב־`ClipRect` או `overflow: ellipsis` של פעולה (ellipsis מותר לטקסט תיאורי עם tooltip); גובה קבוע לרכיב עם טקסט (§6.3); בדיקת רוחב בליטרל (§5.2).

**דוגמה: `AppTopBar` בחלונית צרה.** `AppTopBar` נותן ל־`leadingItems` ול־`trailingItems` רוחב חסום, כדי שסרגל מסתגל (`ResponsiveActionBar`) יראה את המקום האמיתי ויקפל פעולות ל־⋮. עטיפה ב־`SingleChildScrollView` אופקי נוסתה ובוטלה: היא נותנת רוחב לא חסום, הסרגל המסתגל לא מקפל, והפעולות יוצאות מהחלון ונגישות רק בגלילה (נתפס בסצנות הקורא ב־320 ו־390 במגע). פריטים שאפשר להסתיר (נעיצה, הגדרות צורת הדף בקורא) מסומנים בעדיפות ועוברים ל־⋮ של הסרגל; ידית הגרירה והניווט נשארים `critical`; החזרה `normal` (שורת התפריט שלה פעילה רק כשיש היסטוריה, הוכרע 19.11.2026, q17). בקורא: צורת הדף (`low`), אחריה נעיצה וחזרה (`normal`, המאוחר קודם) עוברים ל־⋮ של הסרגל; ניווט וידית גרירה נשארים `critical`. ב־210 וב־260 במחשב נשארים רק ידית וניווט (ובצד השני ⋮ פעולות הקורא; בקורא שני ה־⋮ מתמזגים לאחד: פריטי ההתחלה שקופלו נכנסים לראש התפריט של פעולות הקורא, `mergeFoldedIntoTrailingMenu`, q17). זה סוגר את הגלישה של 11 פיקסלים שהייתה בסרגל הקורא בחלונית צרה מ־420 (הוכרע 18.11.2026: מעבר ל־⋮ לפי עדיפויות; גלילה במגע לא מומשה).

```dart
AppTopBar(
  leadingItems: [NavPanelToggleButton(isOpen: _open, onToggle: _toggle)],
  center: Text(title, style: AppTopBar.titleStyle(context)),
  trailingItems: [
    BarButton.icon(tooltip: 'חיפוש', icon: ..., onPressed: _search),
    BarButton.icon(tooltip: 'הדפסה', icon: ..., onPressed: _print),
  ], // בחלון צר מקפלים ל־⋮ לפי עדיפות, לא גוללים
)
```

### 5.5 בדיקות Responsive [מחייב] · קיים

התשתית: `test/design_system/responsive/responsive_harness.dart`. מסך חדש או שינוי פריסה מקבלים סצנה אחת לפחות בקובץ `test/design_system/responsive/<תחום>_responsive_test.dart`. ‏`testResponsive` רושם בדיקה לכל חלון במטריצה, ובסוף כל הרצה בודק **תמיד** שאין overflow ושגיאות layout (כולן, לא רק הראשונה) ושאין גלילה אופקית בלתי מכוונת.

(סכמה; ה־stubs וה־fakes ב־`test/test_helpers/`)

```dart
testResponsive(
  'דיאלוג ייבוא',
  wrapApp: (app) => BlocProvider<SettingsBloc>.value(value: StubSettingsBloc(), child: app),
  build: (context) => const ImportDialog(),
  act: (tester, run) async {
    await tester.tap(find.text('ייבוא'));
    await tester.pumpAndSettle();
  },
  verify: (tester, run) async {
    expectVisible(tester, run, find.text('אישור'), name: 'כפתור אישור');
    await expectReachable(tester, run, find.text('הערות'),
        name: 'שדה הערות', scrollable: find.byType(Scrollable).first);
    expectInsideViewport(tester, run, find.byType(AppDialogFrame), name: 'הדיאלוג');
    if (run.viewport.touch) {
      expectTapTarget(tester, run, find.byType(AppIconButton), name: 'כפתור סגירה');
    }
  },
);
```

**החלונות.** `ResponsiveViewport(width, height, brightness, textScale, compact, touch)`. שכבת **quick** (בכל PR עם `run-ci`): שישה חלונות מייצגים (320×640 מגע, ‏390×844 כהה מגע, ‏600×400, ‏800×500 בהגדלת טקסט 1.3, ‏1280×800, ‏1920×1080 כהה). שכבת **full** (`--dart-define=RESPONSIVE_TIER=full`, כ־40 חלונות; בשינויי ממשק ובלוח זמנים): כל הרוחבים (320…1920), כל הגבהים (400…1080), קצוות, כהה, הגדלות 1.3 / 1.5 / 2.0 וצפיפות מצומצמת. הפירוט והשכבות ב־`CI_ENFORCEMENT.md` §10. `viewports:` מחליף את המטריצה כשיש סיבה (רכיב שרלוונטי לרוחב אחד).

**מה כל חלון קובע.** `touch` מדליק `DeviceChrome.debugMobileOverride` **וגם** מריץ את הבדיקה ב־`TargetPlatform.android` (אחרת ענפי "מובייל בלבד", כמו שטחי 48 ובלי פס גלילה, לא היו נבדקים; תוקן ב־`responsive_harness.dart`). בחלון בלי `touch` הפלטפורמה Windows (פלטפורמת ה־golden). ‏`compact` = `AppDensity` מצומצמת. ‏`textScale` = הגדלת הטקסט של המערכת. ‏`keyboardHeight:` מדמה מקלדת וירטואלית.

**מה הבדיקות לא יודעות.** גודל נייטיבי של גופן המערכת (הבדיקה בגופן Rubik בשם 'Segoe UI' או 'Roboto'), התנהגות מערכת הפעלה אמיתית, ו־`Platform.is*` שאין לו override (§5.7).

**כללים.**
- הפעולה החיונית נבדקת ב־`expectVisible` (תמיד בהישג) או ב־`expectReachable(scrollable:)` (בתוך גלילה). לא מסתפקים ב"אין overflow".
- `run.allowError(pattern)` **רק** ל־overflow ידוע שממתין להכרעה, עם הערה מה ולמה. אסור להחליש בדיקה קיימת כדי שתעבור.
- מסך שאי אפשר להרים בלי תלויות כבדות (DB, מנוע, WebView) נבנה עם ה־stubs וה־fakes שב־`test/test_helpers/` (`stub_*_bloc.dart`, ‏`fake_*`). אם באמת אי אפשר, בודקים את הרכיבים הפנימיים ומתעדים למה.
- עבור קוד ייצור, התיקון הוא לפי §5.4 ובטוקנים, ולא ספי רוחב שרירותיים.

### 5.6 מגע, מצביע וצפיפות

**מה הוכרע ומומש.**
- שטחי לחיצה: 40×40 בדסקטופ, 48×48 במגע (§2.5.6). הרכיבים שגדלים במגע נבדקים ב־`a11y_guidelines_test.dart`, וה־harness בודק `expectTapTarget` בחלון `touch`.
- `AppDensity` (§2.5.8) מכריע **רק** גובה סרגל ושדה, מידות כפתור סרגל ותפריט וגובה כותרת/כרטיסייה, לפי `isCompact`. הוא **לא** מכריע שטחי מגע. "חלון קטן" (`AppDensity.isSmallWindow`): במכשיר מגע צד קצר מתחת ל־600, במחשב גובה מתחת ל־480.
- חלון צר במחשב (420–600) הוא "כמו טלפון עם עכבר": פריסה צרה, שטחי דסקטופ (§5.3).
- לחיצה ארוכה פותחת תפריט הקשר במגע ובעט (`AppContextMenuRegion`), וגרירת ידית חלונית במגע דורשת לחיצה ארוכה (§5.3, חלוניות מפוצלות).

**איך מזהים "מגע" (הוכרע 18.11.2026, בעל הפרויקט, ללא שינוי בקוד):** "מגע" נקבע לפי **מערכת ההפעלה**: Android ו־iOS הם מגע; Windows, ‏Linux ו־macOS הם מחשב, **גם עם מסך מגע**, והאצבע נתמכת שם כ"מצב שני" (פעולות שמופיעות רק בריחוף מקבלות חלופה נקודתית, ראו להלן). ב־Android וב־iOS בלבד יש רכיב אחד שזוכר את המצביע האחרון (ראו להלן, q2); בשולחן העבודה אין.
- `DeviceChrome.isMobile` הוא `Platform.isAndroid || Platform.isIOS`, ושטחי ה־48 נגזרים מ־`MaterialTapTargetSize.padded`, שברירת המחדל שלו ב־Flutter תלויה ב־`defaultTargetPlatform`.
- **מחשב נייד עם מסך מגע ב־Windows או Linux** מקבל התנהגות דסקטופ מלאה: שטחי 40, ופעולות בריחוף עם חלופה נקודתית. **iPad או טאבלט עם עכבר** מקבל מידות מחשב כל עוד המצביע האחרון הוא עכבר (ראו להלן).
- תקדימים שכבר מזהים לפי המצביע בפועל, ונשארים: `search_scope_menu.dart` (`_touchInput`: ברירת מחדל לפי הפלטפורמה או "אין עכבר מחובר", ואז המצביע האחרון), ‏`rtl_text_field.dart` (`_lastPointerKind`), ‏`reading_tab_strip.dart`, ו־`inline_link_targets.dart` (`touchLinkTapPosition`). הם אינם מנגנון משותף.
- **מצביע אחרון ב־Android/iOS (הוכרע 18.11.2026, מומש):** ב־Android וב־iOS עכבר או משטח מגע שהופיעו אחרונים מחזירים את הערכה לשטח לחיצה ולצפיפות של מחשב (`MaterialTapTargetSize.shrinkWrap`, ‏`VisualDensity.compact`), ואצבע או עט מחזירים למגע. ברירת המחדל במסך חדש, ובבדיקות, נשארת מגע. ב־Windows, ‏Linux ו־macOS אין שינוי: מחשב תמיד, גם עם מסך מגע. המימוש: `InputModalityScope(adaptTheme: true)` אחד מעל האפליקציה (`lib/app.dart`, ב־`MaterialApp.builder` מתחת ל־`MiddleClickAutoScroll`), הרשום ל־`GestureBinding.pointerRouter` ומפרסם את סוג המצביע האחרון ב־`InputModality.lastPointerIsMouseOf(context)`. כל רכיב שקורא `BarButton.isTouch` או `materialTapTargetSize` מהערכה מתעדכן בלי שינוי בו. מחיר: כפתורים בסרגל, בשדה החיפוש וביד־הגרירה משנים גודל באמצע שימוש כשעוברים בין עכבר לאצבע (קפיצה במראה). רק `adaptTheme: true` מחליף ערכה; מחוץ ל־`InputModalityScope` ובבדיקות אין מעקב ואין שינוי.

**חלופות לפעולות שמופיעות רק בריחוף (הוכרע 18.11.2026).** בכרטיס המילון הארמי הכפתורים בריחוף נשארים. בנוסף, לחיצה ארוכה, לחיצה ימנית או Shift+F10 על הכרטיס פותחים תפריט הקשר עם אותן פעולות: פעולות שורת הפירוש שנלחצה, ואחריהן פעולות הכותרת, ואחריהן "העתק" של הבחירה. המנגנון: `ToolResultCardShell(menuEntries:)` ו־`AppSelectionArea(extraMenuEntries:)`. ידית הגרירה של חלונית תוסף וחיצי ה־PDF לא נכללו בהחלטה (יש להם חלופות: רצועת גרירה, מקלדת וגלילה).

**מיקום תפריט הקשר שנפתח באצבע (הוכרע 18.11.2026).** בלחיצה ארוכה באצבע (`PointerDeviceKind.touch`) התפריט לא נפתח מתחת לאצבע. הסדר: מעל האצבע; ואם אין מקום, לצדה (בצד שלפי כיוון הקריאה, ואם אין מקום בו, בצד השני); ואם אין מקום, מתחתיה במרחק `kFingerClearance` (32) מנקודת הנגיעה כשהוא נכנס כולו; ורק אם אין שום מקום כזה (תפריט גבוה במסך קטן) חוזרים לפתיחה הרגילה בתוך המסך. עכבר (לחיצה ימנית), עט ומקלדת לא השתנו. המימוש: `placeMenuAwayFromFinger` ב־`packages/otzaria_context_menu/lib/src/menu_placement.dart`. קוראים חיצוניים של `openMenuAt` מעבירים `kind:` (ב־PDF `PointerDeviceKind.touch` קבוע, כי pdfrx לא מדווח את סוג ההתקן). גובה פריט תפריט הקשר נשאר 36 (חריגה מותרת, §2.5.6).

**תפריט הקשר במקלדת (הוכרע 18.11.2026).** מקש Menu ו־Shift+F10 פותחים את תפריט ההקשר של האזור הקרוב לרכיב הממוקד (`ContextMenuRegion`, בכל האתרים). התפריט נפתח ליד הרכיב, מקבל פוקוס (חיצים ו־Enter), ו־Escape או בחירה סוגרים אותו ומחזירים את הפוקוס. כשהפוקוס על רכיב **מעל** האזורים (למשל ה־`Focus` של הקורא או צפיין ה־PDF), נפתח **האזור המועדף** (`keyboardPreferred`) הנראה העליון, ורק כשאין כזה (או שאינו נראה) האזור הנראה העליון (הוכרע 19.11.2026, q10, מומש). בקורא (צורת הדף והתצוגה המשולבת) האזור המועדף הוא שורת הבחירה, כלומר הפריט שיש בו סמן הבחירה שבשוליים. `ContextMenuRegion.keyboardPreferred` ו־`AppContextMenuRegion.keyboardPreferred` (ברירת מחדל `false`). העוגן הוא מרכז החלק הנראה של האזור, ולכן בפריט רב־שורתי (פסקה) התפריט נפתח ליד אמצע הפסקה ולא ליד הסמן עצמו. כמו בלחיצה ימנית, `onSecondaryTapDown` של האזור נקרא עם נקודת העוגן. כפתור "עוד" גלוי בכל שורה לא נוסף (אפשרות ב' של ההחלטה).

**בחירה מרובה של שורות בקורא (הוכרע 18.11.2026).** נשארת Ctrl+לחיצה ו־Shift+לחיצה, כלומר עכבר או מקלדת בלבד, ללא חלופה במגע. זו **חריגה מותרת** מהעיקרון "אין פעולה מרכזית שמחייבת עכבר" (הבחירה המרובה אינה פעולה חיונית). בספרייה כבר יש "הוסף לבחירה" בתפריט.

**עט בבחירת טקסט (הוכרע 18.11.2026).** עט נחשב כמו עכבר: גרירה בעט בוחרת טקסט ולא גוללת. `PenSelectionGestures` (`lib/widgets/selection/pen_selection_gestures.dart`) עוטף את תוכן `AppSelectionArea`. מ־19.11.2026 (q9, מומש) כל אזורי הבחירה באפליקציה עטופים ב־`PenSelectionGestures`: `AppSelectionArea` (דרכו כמעט כל האפליקציה) וכן ה־`SelectionArea`/`SelectableRegion` הישירים של הקורא ושל המפרשים: צורת הדף (`simple_text_viewer.dart`), התצוגה המשולבת (`combined_book_screen.dart`), רשימת המפרשים והערות (`commentary_list_base.dart`, שני אתרים), רשימת הקישורים (`links_list_view.dart`) ומפרשי ה־PDF (`pdf_commentary_panel.dart`). כל אתר מעביר ל־`PenSelectionGestures.onSelectionChanged` את אותו handler שהוא נותן ל־`onSelectionChanged` של האזור, כי `SelectableRegion` לא מעדכן אותו על בחירה שלא עברה דרכו (גרירת עט). **כלל לאתר חדש:** אזור בחירה ישיר חייב לעטוף את תוכנו ב־`PenSelectionGestures(onSelectionChanged: <אותו handler>)`; אחרת עט לא בוחר בו. נבדק בסימולציה בלבד (`PointerDeviceKind.stylus`), לא בהתקן עט.

**שיתוף טקסט נבחר (הוכרע 19.11.2026, q66 / 117 / 211, מומש בסבב ג'־3).** במובייל אין גרירת טקסט החוצה; במקומה כפתור "שתף" שפותח את גיליון השיתוף של המערכת (`share_plus ^13.3.1`, מאחורי `TextShareService` ב־`lib/core/share/`). הכפתור מופיע בסרגל המגע של `AppSelectionArea` (לפי `Theme.platform`: Android ו־iOS) ובשורת הפעולות של תפריט הקורא אחרי "העתקה" (`buildReaderIconRow(onShare:)`, אייקון `OtzariaIcons.document_share_24_regular`, לפי `DeviceChrome.isMobile`); בשולחן העבודה אין כפתור. שיתוף הוא העתקה לאפליקציה אחרת, ולכן `shareSelectedText` עובר את `ensureCopyAllowed` (מגבלת ההעתקה של ספרים מוגנים) ומסיר מחברי שמות קדושים. ב־Android הכפתור שלנו מחליף את "Share" המובנה של Flutter (`ContextMenuButtonType.share`), שעקף את מגבלת ההעתקה; ב־iOS הכפתור נוסף. בקורא שותף הטקסט כפי שהוצג, בלי כותרת מקור. לא כלול: תפריט ה־PDF ושיתוף עם ציטוט המקור. ב־Windows התוסף מוסיף ספרייה נייטיבית ל־`generated_plugins.cmake` (בלי שימוש בקוד); ב־Linux הוא Dart בלבד. **לא נבדק על מכשיר אמיתי** (לא נפתח גיליון שיתוף, לא נבדק עוגן ה־iPad) ולא נבנה APK (אין Android SDK בסביבה).

**גרירת שורת תוסף בהגדרות (תוקן 18.11.2026).** באנדרואיד ובאייפון/אייפד גרירת שורה לסידור מחדש מתחילה רק אחרי לחיצה ארוכה (`LongPressDraggable` ב־`tools_management_panel.dart`), כדי שגלילת הרשימה באצבע לא תיתפס; בשאר הפלטפורמות הגרירה מיידית, וגם Windows עם מסך מגע מקבל גרירה מיידית (נחשב מחשב).

### 5.7 פלטפורמות: מטריצה ומה שונה בכוונה

הכלל: **אותו מוצר בכל פלטפורמה**. שונה רק בגלל מגבלה טכנית או מוסכמה של מערכת ההפעלה, וההבדל המכוון מתועד עם סיבתו. גם הבדל הגופן בין פלטפורמות הוא החלטה (DD-01 A).

**מקרא:** **זהה** — אותו קוד והתנהגות. **בכוונה** — שונה, ויש סיבה (מצוינת). **פער** — שונה בלי סיבה מוצהרת (מפורט בטבלה). **לא אומת** — תלוי בהתנהגות מערכת הפעלה שלא הורצה.

**כל התאים נבדקו מול הקוד (HEAD של 18.11), לא על מכשירים.** מלבד Windows, אף פלטפורמה לא הורצה בסבב זה. ה־CI מריץ את בדיקות ה־UI של Flutter (shards, ‏responsive) על Linux עם `TargetPlatform.android` כברירת מחדל (ענפי Windows ו־macOS נבדקים רק במקומות שעוקפים במפורש); ב־macOS רץ רק `native_macos`, ו־goldens רצים רק ב־Windows (`flutter_tests.yml`). בנוסף רץ שבועית (ביום ראשון) וידנית workflow `Apple platforms weekly`: ‏`flutter test test/core test/shortcuts test/widgets` על macOS ובניית iOS בלי חתימה (debug). בנייה זו לא רצה ב־PR; תחביר ה־YAML אומת בלבד, וה־workflow עוד לא רץ ב־GitHub (pf8, הוכרע 18.11.2026).

| יכולת | Windows | Linux | macOS | Android | iOS |
|---|---|---|---|---|---|
| סרגל וכפתורי חלון | סרגל מותאם (`hidden`), כפתורי Windows 11 ו־Snap Layouts (בכוונה) | אותו סרגל, ומסגרת מעוגלת עם צל (`VirtualWindowFrame`, בכוונה: חלון GTK בלי מסגרת) | **בכוונה (הכרעת בעלים 18.11, pf6):** סרגל בסגנון Windows בכל פלטפורמות הדסקטופ, לשם אחידות המוצר; אורות התנועה של macOS מוסתרים (`windowButtonVisibility: false` ב־`lib/main.dart`) | אין חלון: כותרת עם שורת סטטוס (בכוונה) | כמו Android |
| תפריט מערכת | אין (אין מקבילה) | אין | `MacMenuBar` נייטיב (בכוונה), עם תפריט "עריכה" (`buildMacEditMenu`): בטל, בצע שוב, גזור, העתק, הדבק, בחר הכל. הפריטים שולחים Intent לרכיב שבפוקוס (`Actions.maybeInvoke`), המקשים (Cmd+Z, Cmd+Shift+Z, Cmd+X, Cmd+C, Cmd+V, Cmd+A) מוגדרים בקוד אך כבויים בדגל `kMacEditMenuShortcutsEnabled = false` (`lib/core/windowing/mac_menu_bar.dart`), כדי ש־macOS לא תתפוס Cmd+C לפני Flutter או ה־WebView של תוסף. TODO(q114): להדליק רק אחרי בדיקה על Mac אמיתי | אין | אין |
| קיצורי מקלדת | `ctrl` | `ctrl`; מקש meta מוצג `SUPER` ולא `WIN` (pf4) | `ctrl` בהגדרות = Cmd, תצוגה ⌘⌥⇧, ‏`ctrl+h`/`ctrl+m` שמורים ומוחלפים (בכוונה). Ctrl+Tab בודק Ctrl פיזי בכוונה (Cmd+Tab שמור למערכת). Cmd+1..9 וזום Cmd+גלגלת מתקבלים בנוסף ל־Ctrl (pf5, ‏`ShortcutHelper.isCtrlOrMacCmdOnly`). לוח שנה: PageUp/PageDown לחודש ו־Shift עם אלה לשנה, בכל הפלטפורמות, בנוסף ל־Ctrl+חצים (pf1; קיצורים קבועים, לא ניתנים לשינוי בהגדרות). לא אומת על Mac. עורך ההערות תוקן | מקלדת חיצונית בלבד; מסך הגדרות הקיצורים מוסתר | בדיקת 'זה Mac' (`ShortcutHelper._isMac`) כוללת iOS: באייפד עם מקלדת חיצונית Cmd הוא המקש הרגיל, ו־`ctrl` בהגדרות = Cmd, כמו ב־macOS (pf4). מסך הגדרות הקיצורים עדיין אינו זמין באייפד. לא אומת על מכשיר. |
| בוררי קבצים | מודאלי לחלון (`DialogOwner.hwnd`) | `lockParentWindow: true` | `FilePickerDarwin(viewId)` לכל חלון | SAF; ייצוא "בתוך הספרייה" לא זמין (בכוונה) | כמו Android |
| הדפסה | `printing` + סימון spool ופורטים | `printing` | `printing` | `printing`; `ui.print`/`ui.exportPdf` לתוספים לא נתמכים (בכוונה; לא מתועד ב־API_REFERENCE) | `ui.print` נתמך; `printing` של האפליקציה: לא אומת |
| תוספים (WebView) | WebView2, השהיה natively | WPE, השהיה לפי visibility, חוקי חסימה | WKWebView, סכימת `otzaria-plugin`, מחוות אחורה כבויות, החזרת פוקוס ל־Flutter | WebView מערכת, השהיה natively, מחוות מגע | WKWebView; השהיה `eventOnly`; מחוות אחורה **פועלות** (בניגוד ל־macOS); בלי החזרת פוקוס למקלדת |
| מסך מלא | `setFullScreen` | זהה | זהה; ניווט למסך אחר לא יוצא ממסך מלא (הסיבה לא מתועדת, לא אומת) | `immersiveSticky`, כפתור בסרגל (בכוונה) | כמו Android |
| ריבוי חלונות | כן, כולל גרירת כרטיסיה בין חלונות (Windows בלבד, בכוונה) | כן, בלי גרירה בין חלונות (Wayland אין מיקום חלון) | רק אחרי handshake של ה־runner; בלי גרירה | אין (בכוונה) | אין (בכוונה) |
| חיפוש סמנטי | כן | כן | arm64 בלבד (בכוונה) | מוסתר (בכוונה) | מוסתר (בכוונה) |
| עדכונים | התקנה/zip, `zstd.exe` | עדכון עץ, מצב portable | עדכון עץ + `.app` | `AndroidUpdateHost` (בכוונה) | חנות בלבד; לא אומת היכן הכפתור מוסתר |
| גופן ממשק | Segoe UI + fallback | **פער:** `Roboto` לא מצורף ורשימת ה־fallback מחליפה את זו של Flutter, והגופן שנבחר בפועל לא אומת | גופן מערכת (SF) + fallback | Roboto מערכת + fallback | גופן מערכת; לא אומת |
| גופני קריאה | גופני הקריאה והכותרות מצורפים (`pubspec.yaml`), כולל עברית מנוקדת; אין גופן ממשק מצורף | זהה | זהה | זהה | זהה |
| גופן מערכת לבחירה | רישום + תיקיות | `~/.fonts` ו־`$XDG_DATA_HOME/fonts` נסרקות (`fontDirectoriesFor`; pf2) | נסרקים קבצי `.ttf`/`.otf` ואוספי `.ttc`/`.otc` בתיקיות הגופנים (כל face באוסף הוא משפחה בנפרד; `.dfont` ישנים אינם נסרקים). בעת הטעינה (או הדפסה, PDF, תוספים) ה־face שנבחר מחולץ לקובץ גופן עצמאי במטמון `otzaria_font_faces` בתיקיית הקבצים הזמניים של המערכת (פעם אחת לכל אוסף וגרסתו). לא אומת על Mac | גופני המערכת ב־`/system/fonts` (ותיקיות OEM) נסרקים וזמינים בבחירת הגופן (pf2). לא אומת על מכשיר | קובצי הגופנים של המערכת אינם נגישים (ארגז החול), ולכן שמות המשפחות עם עברית מגיעים מערוץ נייטיבי (`otzaria/native_fonts`, ‏`ios/Runner/AppDelegate.swift`) ומוצגים **לתצוגה בלבד** (`FontInfo.displayOnly`): בהדפסה, בייצוא PDF, בטיקון ובתוספים הם מוחלפים בגופן מובנה (10 הגופנים המובנים נשארים הבסיס). `FontDropdownField` מסמן גופן כזה "לתצוגה בלבד" בתווית (טקסט `labelSmall` בצבע `onSurfaceVariant` ו־Tooltip), ובראש הרשימה נוספת שורת פעולה "הוסף גופן מקובץ…" (`FontImportFlow`): המשתמש בוחר קובץ `.ttf`/`.otf`/`.ttc`/`.otc`, הוא מאומת (חתימת SFNT, עד 64MB, יש עברית) ומועתק לתיקיית האפליקציה `otzaria_user_fonts`, ומאותו רגע הוא גופן רגיל עם בתים, גם להדפסה ולתוספים. הוכרע 19.11 סבב ג'־2 (116). **לא נבדק על מכשיר iOS או ב־Xcode:** קוד ה־Swift לא הורכב ולא הורץ |
| מצב כהה מהמערכת | `ThemeMode.system`, והתוספים מקבלים `theme.changed` (תוקן, §7) | זהה | זהה | זהה, וצבע שורת הסטטוס לפי הערכה | זהה |
| גרירת קבצים וטקסט | טקסט נבחר החוצה (CF_HTML) וקבצים לתוספים (`IDropTarget`) | טקסט נבחר החוצה: טקסט רגיל ו־HTML (`text/plain`/`text/html`), בלי תבנית CF_HTML (pf3). לא אומת על Linux | כמו Linux: `public.utf8-plain-text` ו־`public.html` (pf3). לא אומת על Mac. גרירת קבצים לתוסף: Windows בלבד, בכוונה | אין: הגרירה מתחילה מעכבר ומתנגשת בידיות הבחירה במגע | אין: כמו Android |
| מקלדת וירטואלית ו־SafeArea | — | — | — | `resizeToAvoidBottomInset`, ציור ידני של שורת הסטטוס ו־`SafeArea(top: false)`, בלי autofocus בחיפוש הספרייה | כמו Android; דינמיק איילנד לא אומת |
| תפריט הקשר | לחיצה ימנית | זהה | זהה; `ctrl+click` לא אומת | לחיצה ארוכה, גם בעט | כמו Android |
| בחירת טקסט | בלי ידיות, תפריט אוצריא | זהה | זהה, קפיצת מילה ב־Alt | `materialTextSelectionHandleControls` | `cupertinoTextSelectionHandleControls` |
| Ctrl+גלגלת | זהה | זהה | Cmd+גלגלת וגם Ctrl+גלגלת (pf5) | פינץ' | פינץ' |
| DPI ומעבר בין מסכים | פיקסלים פיזיים + `savedDpr` | זהה | נקודות, DPR=1 בשחזור (בכוונה) | DPR של המכשיר | DPR של המכשיר |

הפערים הפתוחים (גופן הממשק, תפריטי הקשר בלינוקס, יכולות Windows בלבד, ומקשי קיצור לפריטי תפריט "עריכה" ב־`MacMenuBar`: ממומש וכבוי בדגל, ממתין לבדיקה על Mac) לא נסגרו; חלקם דורש הכרעת מוצר (⚠), והרשימה ב־DESIGN_DECISIONS. נסגרו בהכרעות 18.11.2026: קיצורי Cmd וקיצורי לוח השנה ב־macOS (pf1, pf5), אוספי גופנים `.ttc`/`.otc` ותפריט "עריכה" ב־macOS (65, מומש 19.11.2026), סרגל החלון (בכוונה, pf6), ברירת המחדל של ערכת הנושא (תמיד בהיר, בכוונה, pf7; "לפי המערכת" נבחר ידנית בהגדרות), וזיהוי מגע לפי מערכת ההפעלה (הוכרע להשאיר, §5.6). בדיקות Mac ו־iOS אוטומטיות: `.github/workflows/apple_platforms_weekly.yml` (pf8). שלושה ממצאים נסגרו קודם: ה־harness מריץ `touch` ב־Android, ‏`theme.changed` נשלח כשהמערכת מחליפה בהיר/כהה, וקפיצת מילה בעורך ההערות לפי פלטפורמה.

---

## 6. RTL, עברית ונגישות

### 6.1 כיווניות [מחייב]
- **הכיווניות גלובלית:** `Locale('he','IL')`. לא מוסיפים `TextDirection.rtl` ל־`Text`. כן מוסיפים `TextDirection.ltr` לתוכן שהוא LTR מטבעו: נתיב, URL, דוא"ל, גרסה, hash ומזהה.
- **Directional APIs בלבד:** `EdgeInsetsDirectional`, `AlignmentDirectional`, `PositionedDirectional`, `BorderRadiusDirectional`, `start`/`end`.
  - אסור: `left`/`right` ו־`Alignment.centerLeft` (UIL-021; 42 מופעים ב־baseline).
  - ערך סימטרי (`fromLTRB(a, b, a, c)`) אינו תלוי כיוון ומותר. גאומטריה אחרת שתלויה בצד הפיזי מקבלת `ui-lint: allow` עם נימוק. כך סווגו (q10 Q15–Q17): ידית "הצג מפרשים" בשמאל, ליד החלונית ש־`AdaptiveSidePane` פותח בשמאל; המרווח בחלונית הכלים בימין, מול פס הגלילה; `AdaptiveSidePane` ו־`ContextOverlayPanel`, שמחשבים את הצד בעצמם; ועוגני הרשימה בדיאלוג הדוא"ל. כרטיס הסיור עבר ל־Directional.
- **פס גלילה [מחייב] (הכרעת בעל הפרויקט, 4.11) · קיים:** פס אנכי בקצה הימני הפיזי, בכל כיוון ובכל שפת ממשק.
  - כשיש מה לגלול הוא שומר לעצמו רצועה של `AppTokens.scrollbarGutter` (12 = מרחק 2 + עובי 8 + מרווח 2), והתוכן מצטמצם לידה. האגודל לא עולה על טקסט, כרטיסים או פקדים. כשאין מה לגלול אין פס ואין רצועה.
  - `EdgeScrollbarBehavior.right()` הוא ה־`scrollBehavior` של ה־`MaterialApp`, ולכן חל על כל רשימה. לא מוסיפים ריווח ידני לפס.
  - פס מפורש (אגודל קבוע, בקר משלו) הוא `AppScrollbar`. כשלתוכן יש כבר ריווח בצד הפס, `contentInset:` מצמצם את הרצועה. `Scrollbar`/`RawScrollbar` גולמי נחסם ב־UIL-031.
  - העובי 8 קבוע גם בריחוף, והפינות בחצי העובי (`scrollbarTheme`, q10 Q10). אזור הקריאה וה־PDF בונים מסילה משלהם, באותו צד ובאותן מידות.
  - **חריגים:** חלונית צד משמאל לתוכן (`AdaptiveSidePane`, `ContextOverlayPanel`) מציבה את הפס בקצה החיצוני, בשמאל, כי בקצה הפנימי יושבת ידית שינוי הגודל (q10 Q17). חלונית הכלים שומרת רצועה קבועה משלה (q10 Q16, `reserveGutter: false`). מסך ההגדרות: הפס בקצה ה־end של שפת ההגדרות, כמו לפני הכלל, בעברית בשמאל (`SettingsScrollbar`: ‏`scope` לכל המסך ו־`sideOf` לפס המפורש; הערת בעל הפרויקט בסקירת 4.11). דיאלוגים שנפתחים מההגדרות נשארים בימין. פס אופקי וגלילה במובייל: ללא שינוי.
- **ממשק אנגלי (DD-20 A) · קיים:** שפת הממשק חלה על "כרום הממשק" בלבד, לפי הרשימה הסגורה הזו:
  1. **שורת הכותרת:** כפתורי החלון ומסך מלא, כותרת המסך, היסטוריה/סימניות/שולחן עבודה, הגדרות תצוגת הספרים, רצועת הכרטיסיות, תפריט הכרטיסייה וחיפוש הכרטיסיות, ועמודת הכרטיסיות האנכית.
  2. **סרגל הניווט** (צדדי ותחתון) ותפריט היישום ב־macOS.
  3. **חלוניות שנפתחות מהכרום:** חלונית הכלים וחלונית "הגדרות תצוגת הספרים" (`ContextOverlayPanel`).
  4. **מסך ההגדרות**, הדיאלוגים שנפתחים ממנו (`settingsDialogBuilder`) והגדרות התוספים.
  5. **הסיור והטיפים.**
  6. **ניהול כרטיסייה מפוצלת:** ידית הגרירה והמפריד בין החלוניות.
  7. **מעטפת הדיאלוגים המשותפים**, כשהקורא לא מסר טקסט משלו: תוויות ברירת המחדל (אישור, ביטול, המשך, שמור, איפוס), ה־X בכותרת, שאלת "לסגור בלי לשמור?" (DD-08), ורמז החיפוש וה"אין תוצאות" ב־`SelectionDialog`.
  8. **תוויות מובנות ברכיבים המשותפים:** ה־tooltip של הרחב/כווץ, נקה, תוצאה קודמת/הבאה, סגור חלונית, הצג מפרשים.
  9. **tooltip של פעולה בתוך כלי** (DD-20, השלמה 3.11): הוא חלק מהכפתור ולא מתוכן הכלי, ולכן כרום ומתורגם בכל כלי, גם כשתוכן הכלי נשאר בעברית. ששת ה־tooltips של כפתורי כרטיס המילון הארמי (״העתק״ ועוד) עוברים דרך `settingsText` (השלמה 2.11). תוכן המילון נשאר בעברית.

  **מחוץ לכרום** (עברית ו־RTL בכל שפה): תוכן המסכים — ספרייה, איתור, עיון, חיפוש ותוצאותיו, הכלים והתוספים בתוך המסך (חוץ מ־tooltip של כפתור, סעיף 9); טקסט הספרים; הודעות `UiSnack` (הקטלוגים בעברית); ה־locale של Material; כותרת החלון במערכת ההפעלה. מסכי תוכן שכבר קוראים ל־`settingsText` (דיאלוג החיפוש, האיתור, הספריות המצורפות) נשארים כמו שהם, אבל אינם חלק מההתחייבות.

  בתוך הכרום כל מחרוזת עוברת דרך `context.settingsText` (מחוץ לעץ: `resolveSettingsText`), והפריסה ב־Directional APIs בלבד. הכרום עטוף ב־`ChromeDirectionality`, ותוכן המסכים ב־`ContentDirectionality`. תווית ברירת מחדל של דיאלוג היא `null` בפרמטר ונפתרת בבנייה, כדי שטקסט שהקורא מסר לא יתורגם. ברירת המחדל של שפת הממשק **נשארת "לפי מערכת ההפעלה"**.
- **טקסט מעורב:** שם ספר עם מספרים, או אנגלית בתוך עברית. משתמשים בכיוון הבסיס של הפסקה ולא כופים כיוון. לנתיב או מזהה בתוך משפט עברי עוטפים את הקטע ב־`Text.rich` עם `TextSpan` שבו `textDirection: ltr`, או משתמשים בתווי בידוד (`⁦…⁩`).
  - **שם קובץ בתבנית** (`<שם הספר>.כותרות.csv`): שם קובץ שיש בו כמה מקטעים עבריים נקרא הפוך גם ב־`Text(textDirection: ltr)`, כי הנייטרליים שבין שני מקטעים עבריים מקבלים כיוון RTL. עוטפים כל רצף עברית בשם ב־RLI…PDI (`U+2067…U+2069`) ומציגים את השם ב־`Text` נפרד, ב־`textDirection: ltr` וב־`AppTextStyles.monospaceFamily`, ומתחתיו ההסבר. לא משלבים את השם בתוך משפט. הדוגמה: `_StorageInfoFile` ב־`custom_folders_panel.dart`.
- **מספרים:** ספרות מערביות בכל המקומות. גימטריה ואותיות עבריות לפי ההקשר.
- **קיצורי מקשים:** תמיד LTR, ובצורה אחידה `Ctrl+Shift+P` דרך `ShortcutHelper`.
- **אייקונים כיווניים:** ראו 2.5.1.
- **LTR מכוון בתוך RTL:** עורך קוד או נתיב, פריסת מקלדת וכפתורי חלון של מערכת ההפעלה. עוטפים ב־`Directionality(ltr)` מקומי עם הערה של שורה אחת.

### 6.2 מקלדת ופוקוס [מחייב]
- כל פעולה זמינה במקלדת. סדר ה־Tab הוא סדר הקריאה (RTL) בתוך כל `FocusTraversalGroup`.
- ברשימה עם פריט נבחר, Tab נוחת עליו (`NavTreeFocusGroup` הוא הדפוס הקיים).
- טבעת פוקוס נראית. **אסור** `focusColor: Colors.transparent` בלי חלופה נראית.
- Escape סוגר שכבה אחת (`EscapeLayers`) ולא יותר.
- רכיב מותאם (`GestureDetector`/`Listener`) שמגיב ללחיצה חייב גם `Focus`, `Semantics(button: true)` ו־Enter/Space. בכרטיסיות זה `TabActivationRegion` (קיים).

### 6.3 Semantics, tooltip, טקסט וניגודיות [מחייב]
- **שם נגיש:** לכל רכיב אינטראקטיבי. לכפתור אייקון זה ה־`tooltip`. לרכיב מותאם: `Semantics(label:)`.
- **מצב:**
  - נבחר: `Semantics(selected:)`. קיים בכרטיסיות, בפריטי הניווט ובשורות radio של ההגדרות.
  - מורחב: `expanded:`, מובנה ב־`ExpandingChevron` (DD-27).
  - מושבת: `enabled:`.
  - נבחר בקבוצה: `inMutuallyExclusiveGroup` + `checked`.
- **הודעות:** `UiSnack` מכריז את ההודעה לקורא מסך (קיים).
- **הגדלת טקסט:**
  - אין `MediaQuery.withNoTextScaling` או `textScaler: TextScaler.noScaling` בממשק.
  - `RichText` גולמי מתעלם מהגדלת הטקסט של מערכת ההפעלה. משתמשים ב־`Text.rich`, או מעבירים `textScaler: MediaQuery.textScalerOf(context)`, כמו שנעשה בקטעי התוצאות ובמדידות הגלישה. UIL-026 נועל את שלושתם.
  - כל פריסה נבדקת ב־`TextScaler.linear(1.3)` בלי גלישה. גובה קבוע לרכיב עם טקסט אסור. משתמשים ב־`minHeight`. הרכיבים המשותפים נבדקים ב־1.0, ‏1.3 ו־2.0 ב־`test/design_system/contracts/text_scale_contract_test.dart`.
- **ניגודיות:**
  - טקסט רגיל ≥4.5:1, ורכיבים גרפיים וטקסט גדול ≥3:1. נבדק לכל זרע בבדיקות `test/theme/app_theme_data_test.dart`, וברכיבים המשותפים גם ב־`meetsGuideline(textContrastGuideline)` (`test/design_system/a11y_guidelines_test.dart`).
  - טקסט משני הוא `onSurfaceVariant`, לא `onSurface` בשקיפות.
  - צבע אינו הסימן היחיד למצב: נבחר מסומן גם במשקל, באייקון, או ב"לבן" בקו `selectedBorder` (DD-06, §2.1.4).
- **הפחתת תנועה:** ראו 2.5.5 (DD-21).
- **גופנים שונים:** הממשק מוצג בגופן המערכת (DD-01), ולכן משתנה בין פלטפורמות. אסור להניח רוחב תו קבוע: אין רוחב בפיקסלים שמחושב מאורך מחרוזת.

### 6.4 נגישות: מה קיים ומה ידוע (18.11.2026)

**קיים ונבדק:**
- **תפריט הקשר במקלדת (הוכרע 18.11.2026, קיצור כללי):** כל אתר `AppContextMenuRegion` (36 אתרים, חבילת `otzaria_context_menu`) נפתח במקש Menu וב־Shift+F10, ליד הרכיב הממוקד (בקצה ההתחלה שלו, בתוך החלון). הפוקוס עובר לפריט הראשון, חיצים ו־Enter פועלים, ו־Escape או בחירה סוגרים ומחזירים את הפוקוס לרכיב שפתח (לא כשהפעולה פתחה דיאלוג). תפריט שנפתח בעכבר או במגע אינו לוקח פוקוס, כדי לא לפגוע בבחירת טקסט. (בדיקות: `packages/otzaria_context_menu/test/keyboard_open_test.dart` ו־`test/design_system/responsive/a11y_cross_cutting_test.dart`.) כפתור "עוד" גלוי בכל שורה לא נוסף (אפשרות ב' של ההחלטה): הפעולות האלה נגישות בקליק ימני, בלחיצה ארוכה ובמקשים האלה בלבד. כשהפוקוס על רכיב **מעל** האזורים (ה־`Focus` של הקורא, צפיין ה־PDF), נפתח האזור הנראה העליון שבתוכו, ו־`onSecondaryTapDown` של האזור נקרא עם נקודת העוגן, כמו בלחיצה ימנית (§5.6).
- **פוקוס מקלדת:** טבעת `primary` רק בניווט מקלדת (§3.2); ידית שינוי גודל של חלונית (`ResizableDragHandle`) ממוקדת ונשלטת בחצים (16 פיקסל לצעד), חושפת מחוון עם פעולות הגדלה והקטנה, והכיוון הסמנטי הפוך לפי הצד שהחלונית יושבת בו; Enter על כפתור ממוקד בדיאלוג מפעיל אותו ולא מגיש את הדיאלוג (`DialogKeyboardNavigator.focusedControlOwnsEnter`, ‏`lib/widgets/misc/keyboard_dialog_navigation.dart`).
- **שמות ומצבים לקורא מסך:** סליידר (שם וערך, לא אחוז מהטווח) ושורת מתג בהגדרות (`MergeSemantics`); תא יום בלוח השנה; כפתור ההצגה בדיאלוג סיסמת מצב סייפר; כפתור החיפוש המוטבע בשדה השאילתה.
- **הפחתת תנועה:** דרך `AppMotion` (§2.5.5), כולל הפיכת דף ב־PDF.
- **הגדלת טקסט:** הרכיבים המשותפים נבדקים ב־1.0 / 1.3 / 2.0 (`text_scale_contract_test.dart`), וכל מסך ב־`testResponsive` ב־1.3 לפחות (שכבת full גם 1.5 ו־2.0). מדידות `TextPainter` בתוך רכיבים מקבלות `textScaler` (UIL-026 נועל את הדפוסים הידועים).
- **ניגודיות:** בדיקות לכל הזרעים ב־`test/theme/` וב־`a11y_guidelines_test.dart` (§6.3).

**הוכרע 18.11.2026 (היה "ידוע ולא הוכרע ⚠"):**
- **טקסט הספר גדל עם הגדלת הטקסט של מערכת ההפעלה: התנהגות מכוונת (הוכרע 18.11.2026).** ראו §7 ("הכיוון ההפוך"). הבדיקה המאפיינת נועלת את ההחלטה.
- **כותרת הסרגל העליון: תקרה 1.3 (`AppTopBarTitle`, `AppTopBar.maxTextScale`), בגלל גובה קבוע** (`AppDensity.topBarHeight` 44/56). הכותרת גדלה עד פי 1.3 ועוצרת, כמו תוויות הסרגל התחתון. שדות בסרגל (שדות חיפוש ושדה מיקום הדף ב־PDF) עטופים ב־`AppTopBarField` וגדלים עם הטקסט של המערכת עד `AppTopBar.maxFieldTextScale` = 1.6, תקרה גבוהה מזו של הכותרת (הערת הבעלים לכרטיס 30, 19.11 סבב ג'־2); שדה חיפוש חדש בסרגל חייב להיות עטוף ב־`AppTopBarField`. כפתורים בסרגל לא מוגבלים (החלטת הבעלים 19.11, q30). מי שמגדיל פי 2 רואה כותרת בגודל 1.3 ושאר המסך פי 2 (הוכרע 18.11.2026 ושוכלל 19.11.2026: התקרה על הכותרת בלבד, דרך `AppTopBarTitle` סביב הכותרת ולא על שורת הסרגל כולה; נבדק ב־`app_top_bar_title_scale_test.dart` וב־`reader_top_bar_title_scale_test.dart`). בקורא עם מחבר שתי שורות הכותרת נבלעות במינימום; פריטי הסרגל עוברים ל־⋮ לפי עדיפות (§5.4).
- **כותרות שורות הגדרה:** עד שתי שורות בכל מסכי ההגדרות (הוכרע 18.11.2026, §3.4). הכותרת המלאה נקראת גם בקורא מסך.
- **בחירה מרובה של שורות בקורא** היא Ctrl או Shift+לחיצה בלבד, בלי חלופה במגע: חריגה מותרת (הוכרע 18.11.2026, §5.6).
- **ידית שינוי גודל במגע:** גלויה תמיד ושטחה 32, כחריגה מותרת מ־48 (הוכרע 18.11.2026, מומש 19.11.2026; §5.3.1).
- **לשוניות חלונית צד (`PanelTab`, `NavPanelTabHeader`) בגובה קבוע של 44** (הוכרע 18.11.2026, אושר ונשאר): כשהתווית לא נכנסת בגובה זה בהגדלת הטקסט של המערכת, הלשונית מציגה אייקון בלבד והתווית עוברת ל־`Tooltip` (`PanelTab.labelFits`, דפוס זהה למצב compact). ב־1.0 התוכן 33 מתוך 44, ב־1.5 הוא 41, וב־2.0 הוא 48.5 ולכן אייקון בלבד. בדיקה: `קורא: חלונית ניווט נעוצה בהגדלת טקסט` (1.3, 1.5, 2.0).

---

## 7. מצבי משתמש וערכות נושא

| הגדרה | איפה נשמרת | איפה מוחלת | היקף | הערות |
|---|---|---|---|---|
| ערכת צבע (seed), בהיר | `SettingsBloc.seedColor` | `app.dart` → `createColorScheme` | גלובלי, כל הכרום | 14 זרעים. ל"לבן" ול"פרגמנט" יש override לסולם המשטחים, לפי הזרע. ב"לבן" הקריאה לבנה, והסרגלים, הדיאלוגים והלוח כמעט לבנים (FC, לוח FA), והאזורים מופרדים בקו דק אפור בינוני־בהיר (9F), `regionBorder` (q12 Q3, סקירת 4.11). צבע הבחירה (`secondaryContainer`) E0, והנבחר גם בקו `selectedBorder` (סקירת 4.11, סבב רביעי) |
| ערכת צבע, כהה | `darkSeedColor` | כנ"ל | גלובלי | הבורר עורך רק את הזרע של הבהירות הנוכחית. לוחות כהים `surfaceContainerLow`, קריאה נייטרלית (DD-05) |
| בהיר/כהה/מערכת | `isDarkMode`, `followSystemTheme` | `MaterialApp.themeMode` | גלובלי | "מערכת" מתעדכן בזמן ריצה, והתוספים מקבלים `theme.changed` (§7 סעיף 3). ברירת המחדל בהתקנה חדשה היא בהיר (`followSystemTheme` false, `SettingsState.initial()`), **בכוונה** (הוכרע 18.11.2026, pf7). "לפי המערכת" נבחר ידנית בהגדרות |
| גופן קריאה, גודל, גובה שורה | `SettingsState.fontFamily/fontSize/lineHeight` | הקורא, התצוגה המקדימה, ייצוא; הגופן גם בקטעי תוצאות | **תוכן בלבד** | לא משפיע על הממשק, ונשאר כך **[מחייב]** |
| גודל טקסט בתוצאות החיפוש | `SettingsState.searchResultsFontSize` | קטעי תוצאות החיפוש | תוכן בלבד | נפרד מגודל הספר (§2.4.2, q12 Q2) |
| גופן וגודל של מפרשים | `commentators*` | תוכן | תוכן בלבד | |
| פרופיל תצוגת טקסט (ניקוד, טעמים) | `TextDisplayProfile` | תוכן | תוכן ו־export | |
| "צפיפות ממשק" | `compactMenuMode` (`key-compact-menu-mode`; בלי מפתח = "אוטומטי") | `AppDensity` בערכת הנושא (DD-10 B), דרך `SettingsState.compactMenuModeFor` | סרגלים, שדות ותפריטים | השם "צפיפות ממשק" נשאר. "רגיל \| אוטומטי \| מצומצם", ו"אוטומטי" לפי גודל החלון (§2.5.8, DD-15). התפריטים צפופים יותר במצב הקומפקטי |
| שפת הממשק | `settingsLanguageCode` (ברירת מחדל "מערכת") | `SettingsTextScope`, `ChromeDirectionality` | כרום הממשק — הרשימה הסגורה ב־6.1 (DD-20) | ברירת המחדל נשארת "לפי מערכת ההפעלה" |
| גודל ממשק | **אין** | — | — | לא מוסיפים. מספיקה הגדלת הטקסט של מערכת ההפעלה (6.3) |
| גופן ממשק | **אין** הגדרה | `AppThemeData` | — | גופני המערכת (DD-01) |
| הגדרות תפריטים (הצגת פריטים) | `SettingsState` (מקשים שונים) | תפריטי הקשר | תוכן התפריט, לא מראה | לא שייך למערכת העיצוב |

**[מחייב]**
1. החלפת ערכת נושא לא מחייבת שינוי ברכיבים. רכיב שבודק `brightness == Brightness.dark` כדי לבחור צבע מפר את התקן: ההחלטה שייכת ל־`AppSurfaceColors`.
2. הגדרות קריאה והגדרות ממשק נשארות נפרדות. לא מאחדים אותן ל"גודל טקסט" אחד.
   - **הכיוון ההפוך (הגדלת הטקסט של מערכת ההפעלה; הוכרע 18.11.2026, מכוון):** טקסט הספר (גוף הספר, המפרשים, התצוגה המקדימה של ספר, תוצאות חיפוש בתוך ספר) גדל יחד עם הגדלת הטקסט של המערכת, מעל הגודל שנבחר בהגדרות הקריאה (הגדלה פי 1.5 וגודל ספר 18 נותנים בפועל כ־27). מי שרואה לא טוב מקבל טקסט גדול יותר בלי לשנות הגדרה באפליקציה. החריג היחיד הוא טקסט סת"ם (ספר תורה, תפילין ומזוזות; `MediaQuery.withNoTextScaling` ב־`lib/tools/tikkun_korim/view/widgets/reader_page.dart`), שאינו גדל עם המערכת. אין `noScaling` בשום נתיב אחר של הספר. הבדיקה המאפיינת `קורא: גודל טקסט הספר מול הגדלת הטקסט של המערכת (מאפיין)` ב־`test/design_system/responsive/text_reader_responsive_test.dart` נועלת את ההחלטה. התאמת פריסה אינה כוללת הגדלת טקסט שהמשתמש עשה במערכת בכוונה; זו מתווספת לגודל הקריאה.
3. **תוספים (DD-25 A) · קיים:** תוספים (WebView) מקבלים את ערכת הנושא דרך `buildThemePayloadFromScheme`. מ־0.9.99 ה־payload כולל, כתוספת שאינה שוברת, גם `surfaces` (reader, panel, card, topBar מתוך `AppSurfaceColors`), `radius`, `spacing`, `density` (מתוך `AppDensity`) ו־`typography.uiFont` (גופן הממשק של המארח כערך CSS). `uiFontFamily` נשאר 'Rubik' לתאימות. השדות מתועדים ב־`otzaria_plugin.d.ts`, ב־`API_REFERENCE.md` וב־`DESIGN_GUIDE.md` כאופציונליים מ־0.9.99. כשמוסיפים טוקן משטח או גופן ממשק, מוסיפים אותו גם ל־payload. `theme.changed` נשלח (`main_window_screen.dart`, ‏`_dispatchThemeChanged`) כשהמשתמש משנה ערכה או צפיפות, וגם כשהמערכת עוברת בין בהיר לכהה בזמן ש־`followSystemTheme` דלוק (`PlatformBrightnessListener`, ‏`lib/plugins/utils/platform_brightness_listener.dart`). בלי "עקוב אחרי המערכת" אין שליחה. הבדיקה מכסה את המאזין עצמו; השליחה ב־`main_window_screen.dart` לא נבדקת בנפרד. גרסת השחרור של התיקון: 0.9.99, כמו במדריך (הוכרע 18.11.2026). בסבב ההשלמה 18.11 ה־payload הורחב ב־`surfaces.regionBorder` (קו האזורים, רק ב"לבן" בבהיר; אחרת `null`) וב־`surfaces.warning`, ‏`onWarning`, ‏`warningContainer`, ‏`onWarningContainer` (צבעי האזהרה של DD-24); `theme.changed` נבנה עם `AppThemeVariant.ofSeed` כדי שגם בו יישלח קו האזורים (`buildThemeChangedPayload`). תוספת שאינה שוברת, מ־0.9.99. ל־WebView של תוסף רקע שקוף עד שהדף נצבע (`transparentBackground`), כך שרואים את רקע הלוח ולא לבן בכהה. אירוע `ui.fullscreenChanged` נשלח לתוסף בכל שינוי של מצב המסך המלא (`PluginFullscreenEventForwarder`, ‏`lib/plugins/utils`; מ־0.9.99).
4. **ידוע במצב לילה ובערכות (18.11):**
   - **בחירת טקסט בכהה ב"לבן" וב"אפור":** תוקן (הוכרע 18.11.2026): `AppThemeData.textSelection`, שקיפות לפי בהירות, ראו §2.1.5.
   - **דיאלוג פתוח מתעדכן בהחלפת ערכה** (`showDialogUntilTornDown`, ‏`showBlockingProgress`, ‏`PluginConfirmationDialog`). כל פתיחה עוברת דרך `showDialogUntilTornDown` (הוכרע 18.11.2026); `showDialog` רגיל אינו מקבל את התיקון, ו־`barrierColor` נקבע פעם אחת בפתיחה (§3.1, UIL-028).
   - **ענפי בהירות בקוד פיצ'ר:** UIL-027 חוסם תנאי שהענפים שלו צבעים, ו־3 נשארו ב־baseline (`error_report_dialog.dart` ‏2, ‏`text_correction_editor.dart` ‏1). ענפים שמחוץ לתחום הכלל: `caption_button_colors.dart` (חיקוי כרום, §2.1.3), ‏`pdf_color_filter.dart` (תוכן), ‏`splash_screen.dart`, ‏`design_settings_tab.dart`, והדפסה, שתמיד על נייר לבן (`lib/printing/**` מוחרג מכללי הצבע).
   - **מסך הפתיחה והבהירות (הוכרע 18.11.2026: להשאיר ולתעד).** `SplashApp` נבנה לפני `Settings.init`, ולכן אין לו גישה לבחירת הבהירות של המשתמש: הוא נוטל את הבהירות ממערכת ההפעלה (`theme` ו־`darkTheme` עם `ThemeMode.system` ב־`SplashApp`) ואת הצבעים מזרעי ברירת המחדל (`lib/core/splash_screen.dart`). משתמש שבחר כהה באפליקציה כש־Windows בהיר רואה הבהוב לבן עד שהערכה נטענת; הסרגל והמסגרת הנייטיבים של החלון ב־Windows עוקבים אחרי מערכת ההפעלה ולא אחרי האפליקציה. החלון הראשי מוסתר לאורך שלב ה־splash, והסמל שהמשתמש רואה הוא חלון ה־splash הנייטיבי הנפרד (`windows/runner/splash_window`, נסגר דרך הערוץ `otzaria/splash`). מצב מוכר ומתועד, לא באג. אפשרות עתידית: לשמור בקובץ קטן את הבהירות האחרונה ולקרוא אותו לפני `runApp`; לא נבדק אם זה מתקן גם את הסרגל והמסגרת.
   - **ציור הדגשה בעמוד PDF:** הצופה הראשי משתמש ב־`AppSurfaces.pdfSearchHit` (בהיר וכהה). חלונית התצוגה המקדימה של הספרייה (`book_preview_panel.dart`) עדיין נופלת לצהוב קבוע `AppColors.pdfSearchHighlight`, זהה בבהיר ובכהה.

---

## 8. עבודה לפי התקן

### 8.1 מאיפה לוקחים מה

| אני צריך… | משתמש ב… | לא ב… |
|---|---|---|
| צבע טקסט משני | `cs.onSurfaceVariant` | `cs.onSurface.withValues(alpha: .6)` |
| רקע כרטיס | `AppCard`, או `AppSurfaces.card(context)` | `cs.surface` + `BoxDecoration` |
| רקע מסך לוח | `AppSurfaces.panelBackground(context)` | `Colors.black` / ענף `isDark` |
| שורה נבחרת | `AppSurfaces.selectedRow(cs)` / `onSelectedRow(cs)`, ו"נבחר" גם במשקל או באייקון | `secondaryContainer.withValues(alpha: .4)` |
| צבע "ראשי" | `cs.primary` | **`theme.primaryColor`** |
| אזהרה | `AppSurfaces.warning(context)` / `onWarning` / `warningContainer` / `onWarningContainer`, או `AppInfoBanner` | `Colors.orange`, `cs.tertiary` |
| טקסט | `Theme.of(context).textTheme.<slot>` (2.4.1), ‏`AppSectionLabel` לכותרת מקטע | `TextStyle(fontSize: 13)` |
| ריווח | `AppTokens.space2XS…spaceXL`, `cardPadding`, `listItemGap` | `8`, ‏`spaceSM + 1` |
| רדיוס | `AppTokens.borderRadiusAll` / `roundedShape` | `BorderRadius.circular(12)`, `StadiumBorder()` |
| גודל אייקון | `AppTokens.iconXS…iconXL` (14/16/20/24/48) | `size: 18`, `size: AppTokens.fontLG` |
| משך אנימציה | `AppMotion.duration(context, AppTokens.animNormal)` | `Duration(milliseconds: 250)` |
| צפיפות | `AppDensity.of(context)` | `context.read<SettingsBloc>()` בתוך `build` |
| הגבהה / צל | מסגרת `outlineVariant`, בלי צל. הגבהה `AppTokens.elevation1/2`, צל `AppShadows` | `BoxShadow(...)`, `elevation: 6` |
| החלטה לפי רוחב | `WindowClass.of(context)` לחלון, `LayoutBuilder` לרכיב | `MediaQuery.of(context).size.width < 520` |

**בחירת ערך:** יש תפקיד? משתמשים בו. אין? ערך מהסולם. ערך מחוץ לסולם מתעגל **כלפי מעלה** (6→8, ‏10→12, ‏14→16). גודל גופן 13 או 15 עובר ל־slot הקרוב.

### 8.2 דיאלוג

```dart
// ✅ שאלה פשוטה (small: רצועה ותג, בלי X)
final ok = await showTwoActionsDialog(
  context: context,
  title: 'מחיקת שולחן עבודה',
  content: 'השולחן "$name" יימחק.',
  cancelText: 'ביטול',
  confirmText: 'מחק',
);

// ✅ פעולה הרסנית
await showWarningDialog(context: context, title: 'איפוס הגדרות',
  content: 'כל ההגדרות יחזרו לברירת המחדל.', subtitle: 'לא ניתן לבטל פעולה זו',
  cancelText: 'ביטול', confirmText: 'אפס');

// ✅ טופס (medium), עם שאלה לפני סגירה כשיש קלט שלא נשמר
showDialogUntilTornDown(context: context, builder: (_) => AppDialogFrame(
  title: 'ייבוא ספרים', icon: FluentIcons.folder_add_24_regular,
  size: AppDialogSize.medium, scrollable: true,
  isDirty: _dirty, // ValueNotifier<bool> שהטופס מעדכן
  actions: [ActionButton.neutral(text: 'ביטול', onPressed: ...),
            ActionButton.recommended(text: 'ייבא', onPressed: ...)],
  child: _form(),
));

// ❌ דיאלוג גולמי: כותרת, כפתורים, Escape ו-Semantics משוכפלים
showDialog(context: context, builder: (_) => AlertDialog(
  title: Text('ייבוא', style: TextStyle(fontSize: 18)),
  actions: [TextButton(onPressed: ..., child: Text('ביטול'))],
));
```

בדיאלוג חדש בודקים: Escape סוגר; עם קלט שלא נשמר X, ביטול, Escape ו־barrier שואלים; Enter על "ביטול" מבטל; ברוחב 360 אין overflow ותוכן ארוך נגלל; בתוך `lib/settings/` נפתח דרך `settingsDialogBuilder`; כל מחרוזת כרום עוברת דרך `context.settingsText`.

### 8.3 שדה, כרטיס ומסך

```dart
// ✅ שדה, חיפוש ובחירה
RtlTextField(controller: _c, onSubmitted: (_) => _save(),
  decoration: const InputDecoration(labelText: 'שם השולחן'));
OtzariaSearchField(controller: _q, hintText: 'חיפוש בהערות',
  icon: OtzariaIcons.search_in_document_24_regular);
AppDropdownField<String>(value: _v, entries: _entries, onSelected: _set,
  decoration: const InputDecoration(labelText: 'יחידה'));

// ✅ כרטיס מידע, כרטיס מודגש וכפתור אייקון
AppCard(onTap: _open, padding: AppTokens.cardPadding, child: Column(
  crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(title, style: text.titleSmall),
    const SizedBox(height: AppTokens.spaceXS),
    Text(subtitle, style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
  ]));
AppCard(tone: AppCardTone.error, padding: AppTokens.cardPadding, child: errors);
AppIconButton(icon: const Icon(FluentIcons.dismiss_24_regular),
  tooltip: 'סגור', size: AppIconButtonSize.small, onPressed: _close);
AppCard(tone: AppCardTone.inset, padding: AppTokens.cardPadding, child: quote);

// ✅ פעולה צפופה בתוך הודעה או שורה, ואייקון אחרי הטקסט
ActionButton.inline(text: 'פתח מיקום', onPressed: _reveal);
ActionButton.ghost(text: 'הצג עוד', icon: FluentIcons.chevron_down_24_regular,
  iconAlignment: IconAlignment.end, onPressed: _more);

// ✅ מסך לוח
Scaffold(
  backgroundColor: AppSurfaces.panelBackground(context),
  body: Column(children: [
    AppTopBar(center: Text('גימטריה', style: AppTopBar.titleStyle(context))),
    Expanded(child: Center(child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: LayoutConstraints.panelContentMaxWidth),
      child: _content()))),
  ]),
);

// ✅ החלטה לפי הרוחב שהרכיב קיבל
static const _stackBelow = 560.0; // שתי עמודות של 240 ועוד פעולות
LayoutBuilder(builder: (context, c) =>
  c.maxWidth < _stackBelow ? _stacked() : _row());
```

- ❌ `TextField(`, ‏`Card(`, ‏`Text` אדום מתחת לשדה במקום `errorText`, ‏`InputDecoration(border: …)` מקומי, ‏`IconButton(iconSize: 18, style: …)`.
- כלי חיפוש בונים על `ToolScaffold`, ותוצאות על `ResultCardFrame` (בכלים `ToolResultCardShell`).

### 8.4 טעינה, ריק ושגיאה

```dart
return switch (state) {
  Loading() => const LoadingIndicator(),
  Empty() => const OtzariaEmptyState(icon: OtzariaIcons.otzaria_icon_2_page_24_regular,
      title: 'אין סימניות', message: 'סמן קטע בספר כדי לשמור אותו כאן'),
  Failed() => OtzariaErrorState(title: 'טעינת הסימניות נכשלה',
      actions: [ActionButton.neutral(text: 'נסה שוב', onPressed: _reload)]),
  Loaded(:final items) => _list(items),
};
```

- רק אזור התוכן נטען. שדה החיפוש והסרגל נשארים במקומם.
- ❌ `Center(child: CircularProgressIndicator())`, ‏`Text('שגיאה: $e', style: TextStyle(color: Colors.red))`.

### 8.5 רכיב משותף חדש, רכיב ייחודי וטוקן חדש

- **טוקן חדש:** קודם תפקיד קיים או ערך מהסולם. משטח או מצב חדש נכנס ל־`AppSurfaceColors` (או ל־`AppSurfaces`) עם הערה של שורה אחת, באותו שינוי שמשתמש בו. ערך שתלוי בערכת הנושא או בצפיפות שייך ל־ThemeExtension, וגודל קבוע ל־`AppTokens`. טוקן משטח או גופן ממשק נוסף גם ל־payload של התוספים (7.3).
- **רכיב משותף חדש** ב־`lib/widgets/` רק כשכל התנאים מתקיימים:
  1. אותו תפקיד מופיע ב־3 מקומות לפחות, או ב־2 מודולים לפחות;
  2. אין רכיב קיים שאפשר להרחיב בווריאנט בלי לשבור את ה־API שלו;
  3. ה־API עומד בכללי סעיף 3 (וריאנטים ולא בוליאנים, בלי פתחי מילוט כמו `legacyMode` או `forceColor`);
  4. הוא לא מייבא קוד פיצ'ר;
  5. הוא נכנס עם בדיקת חוזה ב־`test/design_system/contracts/`, ואם יש לו מראה גם עם golden ב־`test/goldens/`;
  6. באותו שינוי עוברים אליו לפחות המופעים שהצדיקו אותו.
- **רכיב ייחודי** מתאים לתצוגה שתלויה בתוכן או בגאומטריה של פיצ'ר אחד (צורת הדף, טבלת שמור וזכור, תא בלוח השנה). הוא מורכב מרכיבי הקטלוג וכל ערך בו הוא טוקן. מיקומו `lib/<feature>/view/widgets/`, ולא מייבאים אותו ממודול אחר.

**ובנוסף, לפני שמסמנים רכיב משותף כגמור** (מפתח או סוכן AI):
- [ ] כל צבע, ריווח, רדיוס, גודל אייקון, גופן ומשך מטוקן או מתפקיד, ו־`dart tool/ui_lint_cli.dart` לא מדווח על הקבצים החדשים.
- [ ] צפיפות מ־`AppDensity.of(context)`, החלטת רוחב ב־`LayoutBuilder` עם סף בעל שם (§5.2), ריווח Directional.
- [ ] `tooltip` לכפתור אייקון, `Semantics` למצב (נבחר, מורחב, מושבת), ופוקוס עם Enter/Space לרכיב לחיץ שאינו כפתור Material (§6.2, ‏§6.3).
- [ ] נבדק בבהיר, בכהה וב"לבן" (§2.1.4), ב־RTL, ברוחב 360 ובטקסט ×1.3.
- [ ] נוספה שורה בקטלוג (§3), ב"מתחילים כאן" אם הוא עונה על צורך חדש, ובטבלת הרכיבים ב־`AGENTS.md` ("UI rules").

### 8.6 חריג, ומה עושים כש־ui_lint נכשל

הדוח המלא מקומית: `dart tool/ui_lint_cli.dart` (ברירת המחדל Markdown; גם `--format=json` או `--format=github`). הבדיקה החוסמת: `flutter test test/design_system/ui_lint_test.dart`. כשהיא נכשלת ב"חריגה חדשה", ההודעה מציינת את הקובץ, השורה, הכלל והתחליף. לפי הסדר:

1. **מתקנים** לפי התחליף. זה המקרה הרגיל.
2. **חריג מוצדק** (תוכן, ייצוא והדפסה, חיקוי מערכת ההפעלה, או חריג שמתועד ב־DD): הערת allow בשורה שמעל הצומת. כלל אחד בכל הערה, נימוק של 12 תווים לפחות (רצוי עם מספר ה־DD), והיא חלה על הצומת הבא בלבד. אין `// ignore:` לכללי ui_lint ואין חריג לקובץ שלם.
3. **תיקייה שלמה** שהכלל לא חל עליה (ייצוא, painters): רשומה ב־`tool/ui_lint/config.yaml` עם `reason:`, דרך PR שמתחזק מאשר.
4. **baseline:** רק לחוב ישן. לא מוסיפים אליו חריגה חדשה כדי לעבור. `--allow-growth` מגדיל אותו, ו־PR כזה נחסם ב־`ui_baseline_guard` עד שמתחזק מוסיף את התווית `ui-baseline`.

```dart
// ui-lint: allow UIL-015 — צבע הפס הוא צבע המרקר שהמשתמש בחר (תוכן)
final band = Color(markerArgb);
```

- **"baseline מת":** תיקנת חריגה ישנה. מריצים `dart tool/ui_lint_cli.dart --update-baseline`, שרק מוחק רשומות, ומצרפים את `tool/ui_lint/baseline.json` ל־commit.
- **golden נכשל:** אם השינוי החזותי מכוון, מעדכנים את התמונות על Windows (`flutter test --update-goldens test/goldens/<רכיב>`, או ה־workflow "Regenerate goldens"), וה־PR צריך את התווית `goldens-approved` (`goldens_guard`). אם לא היה שינוי מכוון, זו רגרסיה.

### 8.7 בדיקות חובה

| שינוי | בדיקה |
|---|---|
| רכיב משותף חדש או שינוי חתימה | בדיקת widget לחוזה (וריאנטים, מצבים, מקלדת), ו־golden אם יש לו מראה |
| פרט קטן שה־golden לא תופס (X, תג אייקון, אייקון בכפתור) | בדיקת widget שמקבעת אותו. סף ה־golden נשאר 0.05% (DD-22) |
| דיאלוג חדש | Escape, dirty (אם יש קלט), Enter על ביטול, רוחב 360, טקסט ×1.3. סצנת `testResponsive` (§5.5) |
| מסך חדש או שינוי פריסה | סצנת `testResponsive` ב־`test/design_system/responsive/<תחום>_responsive_test.dart` עם `verify` לפעולה החיונית (§5.5). `flutter test test/design_system/responsive/<הקובץ>` |
| רכיב שמחליט לפי רוחב או לפי הגדלת טקסט | חלון `touch` וחלון `textScale: 1.3` לפחות; מדיניות "אין מקום" מ־§5.4 |
| שינוי טוקן או ערכת נושא | `test/theme/` (ניגודיות לכל הזרעים), ועדכון golden מכוון |
| פירוק קובץ גדול (DD-30) | characterization לפני, אותן בדיקות אחרי, בלי שינוי חזותי, ב־commit נפרד לפני ה־commit החזותי |
| רכיב שמגיב ללחיצה שאינו כפתור Material | `Semantics(button:)` + Enter/Space + פוקוס |
| מחרוזת בכרום מתורגם | `test/settings/l10n/` |
| כל שינוי | `flutter analyze`, ‏`test/design_system/ui_lint_test.dart` והבדיקות שקשורות לשינוי (`docs/agent_test_map.md`) |

רשימת הבדיקה ל־PR חזותי נמצאת ב־`AGENTS.md` ("UI rules") וב־`.github/PULL_REQUEST_TEMPLATE.md`. מדריך QA מקוצר: §8.8.

### 8.8 מדריך QA קצר למפתחי ממשק

לפני PR שנוגע בממשק (הפירוט בסעיפים שמצוינים):

**הרצה אוטומטית** (רק הקבצים הרלוונטיים, לא כל הסוויטה):
1. `dart tool/ui_lint_cli.dart` — אין חריגה חדשה, ואין `// ui-lint: allow` או הגדלת baseline בלי נימוק (§8.6).
2. `flutter test test/design_system/` (או הקבצים שנגעת בהם) — `ui_lint_test`, חוזים, `agent_docs_paths_test` כשנגעת במסמכים.
3. `flutter test test/design_system/responsive/<קובץ-התחום>` — שכבת quick (6 חלונות). לשינוי פריסה מהותי גם `--dart-define=RESPONSIVE_TIER=full` (כ־40 חלונות) (§5.5).
4. `flutter analyze <הקבצים ששונו>`, ו־`dart format` רק עליהם.
5. רכיב משותף או ערכה: בדיקות `test/theme/` ובדיקת חוזה ב־`test/design_system/contracts/` (§8.7).

**בדיקה ידנית** (בהרצה אמיתית, ולא רק בבדיקה):
6. בהיר, כהה ו"לבן" (§2.1.4); RTL; ובמצב האנגלית אם המסך כרום (§6.1).
7. רוחב 320 ו־360, וחלון נמוך (גובה 400): כל פעולה חיונית גלויה או בהישג (§5.4).
8. טקסט מערכת ×1.3 ו־×2.0: בלי חיתוך או גלישה (§6.3).
9. צפיפות "מצומצם" (§2.5.8).
10. מגע: שטחי 48 לאורך המסך, לחיצה ארוכה במקום ריחוף. זיהוי המגע הוא לפי מערכת ההפעלה (§5.6), ולכן במחשב עם מסך מגע בודקים את שני המצבים.
11. מקלדת בלבד: Tab לכל פעולה, טבעת פוקוס נראית, Escape סוגר שכבה אחת, Enter מפעיל את הרכיב הממוקד (§3.1, ‏§6.2).

**מתי נדרש golden:** רכיב משותף חדש עם מראה, או שינוי מראה מכוון של רכיב שיש לו golden. מעדכנים ב־Windows (`flutter test --update-goldens test/goldens/<רכיב>` או ה־workflow "Regenerate goldens") (§8.6). פרט קטן שה־golden לא תופס נבדק בבדיקת widget.

**תוויות:** `ui-baseline` כשה־baseline או `max_allows` גדלים; `goldens-approved` כשתמונת golden משתנה; `run-ci` להרצת ה־CI המלא (`CI_ENFORCEMENT.md` §1, ‏§10). שער ה־lint חוסם בכל PR גם בלי `run-ci`. את התוויות מוסיף מתחזק.

**דיווח בדיקות שלא הורצו:** ב־PR כותבים במפורש מה **לא** הורץ, למה, ומה הסיכון: "לא נבדק ב־macOS/Linux/iOS (אין מכשיר)", "לא נבדק עם קורא מסך", "לא הורצה שכבת full", "לא נבדק על מסך מגע אמיתי". שורת תוצאה מלאה עם מספר (`+N: All tests passed!`) לכל הרצה שמצוטטת, לא "עבר". בדיקה שנכשלה: עוצרים ומדווחים, לא מחלישים אותה.

---

## נספח א' — מקור אמת לכל סוג הגדרה

| סוג | מקור אמת אחד | סטטוס | מה עוד נשאר מחוץ לו |
|---|---|---|---|
| תפקידי צבע | `AppThemeData.createColorScheme` | קיים | — |
| משטחים ומצבים | `AppSurfaceColors` (ThemeExtension, DD-19) דרך `AppSurfaces` | חלקי | שקיפויות מקומיות (UIL-016) וענפי `isDark` בפיצ'רים |
| אזהרה והדגשה | `AppSurfaces.warning*` (DD-24), `searchHit*`/`permanentMark` (DD-17) | קיים | — |
| טיפוגרפיית ממשק | `ThemeData.textTheme` (מלא, DD-02) | חלקי | `fontSize:` בפיצ'רים (UIL-017) |
| גופן ממשק | `ThemeData.fontFamilyFallback` ב־`AppThemeData` (DD-01) | קיים | `'Rubik'` ב־`uiFontFamily` של התוספים, לתאימות (DD-25) |
| טיפוגרפיית תוכן | `SettingsState` + `AppFonts` | קיים | — |
| ריווח | `AppTokens.space*` + טוקנים סמנטיים | חלקי | ריווח מחוץ לסולם (UIL-020); ארבעת הטוקנים הסמנטיים קיימים, כמעט בלי קוראים |
| רדיוסים | `AppTokens.radius` (ערך אחד, DD-04) | קיים | — (UIL-019 נעול) |
| הגבהה וצל | `AppTokens.elevation*` + `AppShadows` (DD-12) | קיים | 3 צללים מקומיים (UIL-030) |
| גבהים | `AppInputTokens` + `AppDensity` | קיים | — |
| גדלי אייקון | `AppTokens.icon*` (DD-03) | חלקי | גדלים מספריים (UIL-029) |
| אנימציות | `AppTokens.anim*`, ‏`AppTokens.curve*` + `AppMotion` (DD-21) | קיים (UIL-023 נעול, בלי חוב) | משכי אנימציות קישוט כקבועים מקומיים בלי טוקן (UIL-036, דוח בלבד), ועקומות ליטרליות בקוד קיים |
| הגדרות דיאלוג | `lib/widgets/dialogs/` (`AppDialog`, `AppDialogFrame(size: AppDialogSize)`) | חלקי | 50 `showDialog` ישירים (UIL-028); `ad_popup_dialog.dart` גולמי בפטור נתיב (UIL-001 נעול) |
| פריסות מסך | `lib/widgets/layout/`, `navigation/`, `ToolScaffold` | חלקי | מעטפות מקומיות; מעטפת מסך ההגדרות במחשב בלי הפרדת אזורים (DD-18) |
| רכיבי ניווט | `NavSidePanel`, `NavRailItem`, `NavTreeTile`; רוחב חלונית `LayoutConstraints.sidePaneWidth` (DD-28) | קיים | — |
| רספונסיביות | `LayoutBreakpoints` + `WindowClass` (DD-15) | קיים | — |
| צפיפות | `AppDensity` (DD-10) | קיים | — |
