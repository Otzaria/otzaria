# מערכת העיצוב של אוצריא — מסמך התקן

> **מעמד:** גרסה 1.3 (5.11.2026). כל ההכרעות DD-01..31 אושרו בידי בעל הפרויקט, ונימוקיהן ב־[DESIGN_DECISIONS.md](DESIGN_DECISIONS.md). האכיפה האוטומטית: [CI_ENFORCEMENT.md](CI_ENFORCEMENT.md).
> **קהל:** כל מי שכותב קוד ממשק באוצריא: מפתחים, סוקרים וסוכני AI. מתחילים ב"מתחילים כאן" שלמטה. סעיף 8 מסביר איך עובדים לפי התקן בפועל.
> **גרסאות:**
> - **1.0 (1.11.2026):** נעילת ההכרעות של חמשת סבבי ההכרעה.
> - **השלמות 2.11 ו־3.11:** ארבעה סבבי המשך שעלו מהמימוש, משולבים בסעיפים ומסומנים "השלמה 2.11" או "השלמה 3.11". פירוטם ב־DESIGN_DECISIONS.
> - **1.1 (3.11.2026):** סימוני המימוש נבדקו מול הקוד ב־`design-system/stage-b`. מה שמומש מסומן **קיים**, ומה שמומש בחלקו מסומן **חלקי** עם מה שנשאר.
> - **1.2 (3.11.2026):** תשובות הסבב החמישי (q10) משולבות, מסומנות "q10", ומספרי ה־baseline עודכנו.
> - **1.3 (5.11.2026):** תשובות q11, ‏q12 וחמשת סבבי "סקירת 4.11" משולבות (ערכת "לבן", מסכים קטנים, צפיפות "אוטומטית", כרטיסי ההערות, אייקונים 20). נוסף "מתחילים כאן". מה שעוד פתוח מרוכז בסוף DESIGN_DECISIONS.

## מתחילים כאן

**לפני שכותבים ממשק** (מפתח שמוסיף מסך, או סוכן AI שמקבל משימת UI):
1. מוצאים ברשימה שלמטה את הרכיב לכל צורך. רכיב קיים קודם לכל קוד חדש. הסעיף שבסוגריים מפרט וריאנטים והתנהגות.
2. כל ערך (צבע, ריווח, רדיוס, גודל אייקון, גופן, משך) נלקח מטוקן או מתפקיד: הטבלאות ב־§2, והמיפוי "אני צריך… ← משתמש ב…" ב־§8.1. אין מספרים ואין צבעים בקוד פיצ'ר.
3. החלטת פריסה לפי `WindowClass` או לפי ה־constraints שהרכיב קיבל, לא לפי פלטפורמה או כיוון המסך (§5).
4. בודקים: `dart tool/ui_lint_cli.dart`, ‏`flutter test test/design_system/ui_lint_test.dart` והבדיקות של הקבצים שנגעו בהם (§8.6, ‏§8.7). בהיר, כהה ו"לבן"; RTL; רוחב 360 ורוחב מלא; טקסט ×1.3.
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

**מספרים "היום"** במסמך הם ספירות ה־baseline של `tool/ui_lint` ב־5.11.2026. המצב העדכני: `dart tool/ui_lint_cli.dart`.

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
- רדיוס אחד, 8, לכל רכיב מלבני, כולל צ'יפים, כפתור סרגל עם תווית ותג אייקון (DD-04 A). שני חריגים: כפתור אייקון בלבד נשאר עגול, ו־`BarSplitButton` (אייקון וחץ) נשאר גלולה (השלמה 2.11). גם הריחוף של `IconButton` גולמי עגול, דרך ערכת הנושא (השלמה 3.11). כפתור אייקון עם רקע משלו נשאר 8 (q10 Q22).
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
| `packages/otzaria_context_menu` | `AppMenuMetrics` | מידות התפריטים, צפופות יותר במצב הקומפקטי (DD-10). |
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
- `.withValues(alpha:)`, `.withAlpha(` ו־`.withOpacity(` על צבעי ממשק (UIL-016; 86 מופעים ב־baseline).
- `Theme.of(context).primaryColor`. זהו באג מוכח: במצב כהה Flutter מחזיר דרכו את `surface`, ולכן טקסט ותיבות סימון נעלמו.
- `hoverColor`, `splashColor` ו־`overlayColor` (UIL-007). חריג אחד: `hoverColor: Colors.transparent` ב־`ListTile` שיש לו `onTap` וגם כפתורים ב־`trailing`, כדי שהריחוף של השורה לא יתחרה בהם. ערך מ־`AppSurfaces` (למשל `hoverRow`) אינו עקיפה, גם בתנאי שכל ענפיו `AppSurfaces` או `null`.
- ענף `brightness == Brightness.dark` לבחירת צבע. ההחלטה שייכת ל־`AppSurfaceColors`. בדיקה לפי שם מצאה 31 אתרים מחוץ ל־`lib/theme`, ורובם אינם החלטת צבע (בניית הערכה, פלטפורמה, תוכן). הכלל (UIL-027) עוד לא מומש.

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
| בחירת פסקה / שורה מודגשת | `paragraphSelectionBackground`, `highlightedLineBackground` | | | קיים | קורא |
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

**כלל העיגול [מחייב] (DD-03):** ריווח שמחוץ לסולם **עולה** לערך הבא: 6→8, ‏10→12, ‏14→16. העיגול נעשה כשהקובץ מוסב, לא בהחלפה גורפת. UIL-020 חוסם ריווח חדש מחוץ לסולם (146 מופעים ב־baseline).

**טוקנים סמנטיים** (`static const` ב־`AppTokens`, DD-03 C). כל הערכים נגזרים מהסולם. ערך שלא הוכרע נקבע ב־commit המיישם, עם תמונות:

| שם | ערך | סטטוס |
|---|---|---|
| `cardPadding` | `all(12)` (DD-11, כרטיס תוצאה) | קיים |
| `listItemGap` | 8 בין תוצאות (DD-11) | קיים |
| `dialogPadding` | הערך הקיים: 24 אופקי, 16 אנכי | קיים |
| `listRowPadding`, `sectionGap`, `titleContentGap`, `labelFieldGap` | ב־commit המיישם | יעד. עד אז: ערכי הסולם |
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
| כפתור אייקון בלבד ב־`BarButton` (`CircleBorder` לבחירה ול־hover) | **עיגול**, חריג מאושר (DD-04, השלמה 2.11) | קיים |
| כפתור סרגל מפוצל (`BarSplitButton`, אייקון וחץ בלי תווית) | **גלולה**, חריג מאושר (DD-04, השלמה 2.11) | קיים |
| `IconButton` גולמי בלי צורה משלו (`iconButtonTheme`) | **עיגול**, כמו `AppIconButton` (DD-04, השלמה 3.11). כפתור אייקון עם רקע גלוי משלו (`filled`, `filledTonal`, `backgroundColor`) קובע `roundedShape` בעצמו ונשאר 8 | קיים |
| כפתור סינון של תוסף בשדה חיפוש, במצב סינון עם תווית | 8, בצורת צ'יפ, עם תווית `labelMedium` (12) (DD-31, q10 Q23) | קיים |
| ידית פס גלילה | חצי מהעובי, מחושב מקבוע העובי (q10 Q10) | קיים |

**[אסור]** כל רדיוס אחר: `circular(n)` ליטרלי, `StadiumBorder`, ו־4 בתוך תפריט. `CircleBorder` מותר רק לרכיב עגול מטבעו ולכפתור אייקון בלבד. UIL-019 בודק את כולם, עם החריגים שבטבלה (q10 Q13). אין לו חוב, והוא נעול.

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
- **`fontSize:` אסור בקוד פיצ'ר (DD-02).** מותר רק ב־`lib/theme/` ובציור תוכן הספר (2.4.2). משתמשים ב־`Theme.of(context).textTheme.<slot>`, ובמקרה הצורך ב־`.copyWith(fontWeight:/color:)`. גם `AppTokens.font*` (ו־`fontSM - 1` וכדומה) נשאר בשכבת ה־Theme. UIL-017 חוסם את שניהם (184 מופעים ב־baseline). גם גודל שאין לו תפקיד ברור מקבל את ה־slot הקרוב, ולא חריג (q10 Q5).
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

**[אסור]** גודל אייקון מספרי בקוד פיצ'ר, וטוקן גופן כגודל אייקון (UIL-029; 105 מופעים ב־baseline). גודל מחוץ לסולם עובר לטוקן: 18 ל־`iconSM` ‏(16), ‏22 ל־`iconMD` ‏(20) (סקירת 4.11, סבבים רביעי וחמישי, גם בתוך `OtzariaSearchField`), ו־56/64 ל־`iconXL` ‏(48) (q10 Q9).

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
| `AppTokens.focusRingWidth` | 2 | טבעת פוקוס ופס פעיל | קיים |
| `AppTokens.multiSelectedBorderWidth` | 1.5 | מסגרת בחירה מרובה וכרטיס פעיל | קיים |
| `AppTokens.borderThin` | 1 | מסגרת כרטיס, שדה ומפריד, וקו האזורים של "לבן" | קיים לקו האזורים (#2850). בשאר עדיין ברירת המחדל של `BorderSide` (1) |

#### 2.5.4 צלליות והגבהה [מחייב] (DD-12 A) · קיים
**התקן:** מסגרת ולא צל. שלוש רמות בלבד:
- 0: כרטיסים ומשטחים רגילים. כרטיס מקבל מסגרת `outlineVariant` בלי צל.
- 1 (`AppTokens.elevation1`): סרגל עליון וחלונית מוצמדת.
- 3 (`AppTokens.elevation2`): תפריט, tooltip וחלונית צפה.

הדיאלוג נשאר לפי M3. צל רק דרך `AppShadows`. ה־scrim אחד, עדין כמו בדיאלוגים (2.1.1). UIL-030 חוסם הגבהה ליטרלית ו־`BoxShadow` מחוץ ל־`lib/theme` (4 מופעים ב־baseline: אנימציות הדגשה וחגיגת סיום). צל הנייר של עמוד PDF הוא תוכן, ומסומן allow (JX-05, q10 Q11).

#### 2.5.5 תנועה
| טוקן | ערך | סטטוס |
|---|---|---|
| `AppTokens.animFast` | 150ms | קיים |
| `AppTokens.animPanelOpacity` | 200ms | קיים |
| `AppTokens.animNormal` | 250ms | קיים |
| `AppTokens.animPanelSlide` | 300ms | קיים |
| `AppTokens.hoverPreviewDelay` | 280ms | קיים |
| `AppTokens.curveStandard` / `curveEnter` / `curveExit` | `Curves.easeInOut` / `easeOutCubic` לכניסה. הערכים הקיימים | יעד. עד אז: `Curves.easeInOut` |

**[מחייב]**
- משך אנימציה של ממשק הוא טוקן (UIL-023; 8 מופעים ב־baseline, כולם `AnimationController`).
- **הפחתת תנועה (DD-21 A) · קיים:** כל משך של אנימציית ממשק עובר דרך `AppMotion.duration(context, AppTokens.animNormal)`, שמחזיר `Duration.zero` כשהמערכת מבקשת להפחית אנימציות. כך נכבות פתיחת חלונית והחלפת לשונית. אנימציה שמעבירה מידע, כמו התקדמות, נשארת.
- **גלילה מונפשת · קיים (q10 Q12):** דרך `AppMotion.scroll` או `AppMotion.scrollPosition`, שקופצים ליעד תחת הפחתת תנועה, כי `animateTo` לא מקבל משך 0. ‏`Scrollable.ensureVisible` מקבל `AppMotion.duration`.
- ⚠ משכים בלי טוקן שווה (120, ‏180, ‏280) עוברים היום דרך `AppMotion` בערך ליטרלי. ממתין להכרעה אם להוסיף להם טוקנים.

```dart
AppMotion.scrollPosition(_scroll.position, offset, AppTokens.animPanelSlide);
AppMotion.scroll(context, AppTokens.animPanelSlide,
    animate: (d) => _pages.animateToPage(i, duration: d, curve: Curves.easeInOut),
    jump: () => _pages.jumpToPage(i));
```

#### 2.5.6 שטחי לחיצה [מחייב] · קיים
- מינימום 40×40 בדסקטופ, ו־48×48 במגע (`MaterialTapTargetSize.padded`). `AppIconButton` במובייל 48 גם בשורה צפופה, כשהשורה גבוהה ב־8 (DD-11, השלמה 3.11).
- אפשר לצייר אייקון קטן בתוך שטח לחיצה גדול יותר. מקטינים את השטח רק כשהרכיב הוא חלק משורה צפופה שיש לה חלופה במקלדת.
- ⚠ חמישה מקומות קטנים מ־48 במגע, וממתינים להכרעה: `BarButton.icon` ב־`AppTopBar` ‏(40), ‏`AppTogglePill` (גובה 24), ‏`StatusChip` (גובה 32), כפתור הניקוי של `OtzariaSearchField` ‏(32), וכפתורי כרטיס ההערה במסך הניהול (`AppIconButton(small)` עם `shrinkWrap`, ‏32, q10 Q25). ארבעת הראשונים נמדדים ב־`test/design_system/a11y_guidelines_test.dart`.

#### 2.5.7 מגבלות רוחב
| טוקן | ערך | סטטוס |
|---|---|---|
| `LayoutConstraints.panelContentMaxWidth` | 860 | קיים |
| רוחבי דיאלוג | `AppDialogSize.small` ‏400 / `medium` ‏560 / `large` ‏720 / `full` (DD-07) | קיים |
| חלונית צד | `LayoutConstraints.sidePaneWidth` ‏340, טוקן אחד (DD-28) | קיים |
| רוחב תוכן מינימלי ליד חלונית | `LayoutConstraints.mainContentMinWidth` ‏500 | קיים |

#### 2.5.8 צפיפות: קומפקטי ורגיל [מחייב] (DD-10 B) · קיים
`ThemeExtension<AppDensity>` אחד שנבנה ב־`AppThemeData` מתוך ההגדרה "צפיפות ממשק" ומכיל:
- גובה סרגל, גובה שדה וגודל כפתור סרגל;
- גודל אייקון בסרגל ו־menu metrics. **התפריטים צפופים יותר במצב הקומפקטי**;
- `isCompact`.

שינוי ההגדרה מתעדכן מיד בכל הממשק. שם ההגדרה למשתמש נשאר **"צפיפות ממשק"**, והבורר הוא "רגיל | אוטומטי | מצומצם" ("אוטומטי" באמצע; סקירת 4.11, סבבים רביעי וחמישי, q-density-auto ו־q-auto-order). "אוטומטי" הוא ברירת המחדל, בלי מפתח שמור (`key-compact-menu-mode` נמחק): מצומצם ב"חלון קטן" (`AppDensity.isSmallWindow`: בטלפון ובטאבלט צד קצר מתחת ל־600, במחשב רק גובה מתחת ל־480) ורגיל בשאר, ותת־הכותרת אומרת למה הוא מתורגם כרגע. "רגיל" ו"מצומצם" נשמרים כבחירה מפורשת, גם בחלון נמוך. כשהצפיפות שבפועל מתהפכת עם החלון, התוספים מקבלים `theme.changed` (DD-15). רכיבים קוראים `AppDensity.of(context)`. **[אסור]** לקרוא את `compactMenuMode` מתוך רכיב תצוגה. מחוץ ל־`lib/theme` ולהגדרות הוא נקרא היום רק ב־`app.dart` וב־`main_window_screen.dart`, וב־`lib/widgets` הכלל UIL-025 נועל אותו.

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

**המסגרות:** `AppDialog` (שאלות קצרות, מאחורי `showTwoActionsDialog`/`showWarningDialog`/`showSingleActionDialog`), `AppDialogFrame(size:)` לכל השאר, ו־`InputDialog`/`SelectionDialog` מאחורי `showInputDialog`/`showSelectionDialog`. `AppCustomContentDialog` ו־`ListDialogFrame` הוסרו לטובת `AppDialogFrame`. נשארו 3 דיאלוגים גולמיים, ב־baseline של UIL-001, ו־54 קריאות `showDialog` ישירות (UIL-028, דוח בלבד).

#### משפחות הדיאלוג [מחייב] (DD-07 B, DD-16 A) · קיים

**[מחייב]** רצועת כותרת (`AppDialogHeader`) ותג אייקון **בכל** דיאלוג, כולל `small` (DD-07 B). האייקון מתאר את הפעולה. אם אין לה אייקון שאומר משהו, משתמשים באייקון של משפחת הדיאלוג (`AppDialogIcons`: מידע, אישור, אזהרה, קלט, בחירה, התקדמות).

**[מחייב]** ב־`small` אין X (DD-07, השלמה 2.11): סוגרים ב״ביטול״ (או בכפתור הסגירה של הדיאלוג), ב־Escape או בלחיצה בחוץ. `AppDialogFrame` קובע את זה לפי הגודל. מ־`medium` ומעלה ה־X נשאר.

**[מחייב]** (DD-07, השלמה 2.11): שאלה קצרה עם שלוש או ארבע פעולות (טיוטת הערה, התנגשויות בייבוא) היא `medium`, כדי שכל הכפתורים יהיו בשורה אחת, ולכן יש בה X. גוף כל דיאלוג בצבע הדיאלוג (`surfaceContainerHigh`). דיאלוג עם `height` מפורש מוגבל לגובה החלון ולא ל־85%.

| משפחה | רכיב | מתי | כותרת | תג אייקון | X | גודל / גובה | גלילה | פעולות |
|---|---|---|---|---|---|---|---|---|
| **אישור פשוט** | `showTwoActionsDialog` | שאלת כן/לא שאינה הרסנית | רצועה | כן | לא | `small` (400), לפי התוכן | לא | ביטול (`neutral`) + אישור (ראשי) |
| **אזהרה** | `showWarningDialog` | פעולה הרסנית או בלתי הפיכה | רצועה, טון שגיאה | כן, אזהרה בטון שגיאה | לא | `small` | לא | ביטול (מוקד) + אישור (`warning`) |
| **מידע** | `showSingleActionDialog` | הודעה שדורשת קריאה, כשאין די ב־`UiSnack` | רצועה | כן | לא ב־`small`, כן ב־`medium` | `small`/`medium` | אם התוכן ארוך | סגור (ראשי) |
| **קלט** | `showInputDialog` | שדה טקסט אחד | רצועה | כן | לא | `small` | לא | ביטול + אישור. Enter בשדה = אישור |
| **בחירה** | `showSelectionDialog` | בחירת פריט אחד מרשימה | רצועה | כן | לא | `small` × עד 60% גובה | רשימה | ביטול. Enter על פריט = בחירה |
| **בחירה בין N אפשרויות** | `showChoiceDialog` | 3+ פעולות שוות, למשל "טקסט / Word / ביטול" | רצועה | כן | לא | `small` | לא | N ראשיות/ניטרליות + ביטול |
| **בינוני (טופס, תוכן מורכב)** | `AppDialogFrame(size: medium)` | טופס של כמה שדות, הגדרה ממוקדת, עורך ההערות (השלמה 2.11), שאלה עם 3–4 פעולות | רצועה | כן | כן | 560, לפי התוכן עד 85% | `AppDialogFrame(scrollable: true)` | בשורת הפעולות: משני → ראשי |
| **גדול / "מסך כדיאלוג"** | `AppDialogFrame(size: large)` | רשימות (סימניות, היסטוריה, גרסאות), ניהול | רצועה + מונה ב־`trailing` | כן | כן | 720, **לפי התוכן עד 85%**. רשימה עם שורת חיפוש: **85% קבוע**, כדי שהחיפוש לא יזוז בזמן ההקלדה (השלמה 2.11) | מובנה | אופציונלי |
| **עם לשוניות** | `AppDialogFrame(size: large, tabs:)` | דיווח שגיאה, הגדרות מרובות | כנ"ל + `TabBar` | כן | כן | 720, בגובה קבוע. דיווח שגיאה: 720×560 (השלמות 2.11 ו־3.11) | לכל לשונית | |
| **תהליך / התקדמות** | `runWithBlockingProgress` | פעולה חוסמת של יותר מ־~300ms | רצועה | כן | לא (או "בטל" אם התהליך ניתן לביטול) | `small` | — | בטל (אופציונלי) |
| **מסך מלא** (הדפסה) | `AppDialogFrame(size: full)` | תצוגה מקדימה עם חלונית הגדרות. עורך ההערות אינו כאן: `medium` (השלמה 2.11) | רצועה + פקדים בתחילת הכותרת, לפני התג (השלמה 2.11) | כן | כן | 100% פחות שוליים | | |

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
| אייקון בלבד, כללי | `AppIconButton(size: small\|medium\|large)`: עטיפה דקה על `IconButton` שמחייבת `tooltip`. אייקון 16/20/24 מ־`AppTokens.icon*`, ריבוע האייקון ועוד 16 (ועוד 12 בצפיפות קומפקטית), עגול (DD-04). `isSelected` צובע ב־`primary`. ‏`small`: אייקון 16 בריבוע 32 (השלמה 3.11) | חלקי: השכבה המשותפת, שורת הכותרת ועמודת הכרטיסיות הוסבו. בפיצ'רים נשארו כ־90 `IconButton` גולמיים |
| אייקון בתוך שדה / בסרגל צר | `SquareIconButton.field` / `.toolbar` | קיים |
| פעולת סרגל | `BarButton.icon` / `.text` | צורה 8, בלי גלולה (DD-04) |
| פעולה מפוצלת | `BarSplitButton` | צורה: גלולה, חריג מאושר ל־״8 בלבד״ (DD-04, השלמה 2.11) |
| פעולת רשימה / שורה | `AppIconButton(size: small)`. בשורת הגדרה: `SettingsActionTile` actions | אין hover כפול על השורה. גם כפתורי הפעולה בכרטיס הערה, ליד הספר ובמסך הניהול (השלמה 3.11, q10 Q25) |
| "הרחב הכל / כווץ הכל" בכותרת עץ ניווט | `NavTreeCollapseAllButton(isCollapsed:, onCollapseAll:, onExpandAll:)` על `AppIconButton(small)` (DD-27, q12 Q4, #3103) | **[מחייב]** כלל אחד בתוכן העניינים ובעץ החיפוש: כשהכל מכווץ "הרחב הכל", כשמשהו פתוח "כווץ הכל". "מכווץ" = אין ענף גלוי פתוח מעבר למצב המכווץ, גם כשענף (או השורש) נסגר ביד. אין כפתור כשאין ענף שאפשר לפתוח |
| גלולת מצב בשורת הכותרת (עדכון זמין, מוריד, מוכן להתקנה) | `StatusChip`. מצב פעיל שאינו פעולה ("מוריד…"): `StatusChip.busy(icon:, label:, tooltip:)` (q10 Q6) | משטח `primaryContainer` עם מסגרת `primary`, אייקון ותווית `labelLarge` w700. `onPressed: null` מושבת. `busy` באותם צבעים כמו הלחיץ, בלי ריחוף, וקורא מסך קורא אותו כטקסט |
| קומפקטי | אותם רכיבים עם `AppDensity` | אין רכיב "קומפקטי" נפרד |

**מצבים [מחייב]:**
- **hover/pressed/focus:** מגיעים מערכת הנושא (`_hoverButtonStyle`). לא מגדירים אותם מקומית. ב־`IconButton` הצורה עגולה גם היא מערכת הנושא (DD-04, השלמה 3.11).
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
| חיפוש | `OtzariaSearchField`. בחלונית ניווט: `NavPanelCollapsibleSearch` | אייקון לפי היקף החיפוש (`agent_ui_reference` §1). כפתור ניקוי אחד, `OtzariaSearchClearButton`, וגודל הכפתורים נגזר מהשדה. כפתור סינון של תוסף (`providerBooksFilter`): במצב סינון אייקון ותווית קצרה בצורת צ'יפ (פינות 8, ‏`labelMedium`, q10 Q23), ״רק התוסף״ / ״רק הספרייה״, שהתוסף יכול להחליף (`pluginOnlyLabel`, `libraryOnlyLabel` במניפסט); בשדה שאין בו מקום לתווית, אייקון ו־tooltip (DD-31, השלמה 3.11) |
| ניווט בין תוצאות | `SearchResultNavigator` | אחד, בשדות, בחלוניות החיפוש, בתצוגה המשולבת וב־PDF |
| תפריט פעולות, או בחירה מתפריט שנפתח מכפתור | `AppPopupMenuButton`, או `showAnchoredAppMenu` (‏`lib/widgets/misc/app_popup_menu.dart`) | צפיפות לפי `AppMenuMetrics` (DD-10). `PopupMenuButton`, ‏`showMenu` ו־`MenuAnchor` גולמיים חסומים (UIL-014) |
| בחירה אחת מרשימה נפתחת | `AppDropdownField` | `decoration.labelText` מוצג כתווית `labelMedium` מעל הכפתור ונקרא יחד עמו בקורא מסך (השלמה 2.11). בשדות בסרגל, שאין בהם מקום מעל: `semanticLabel` בלבד (שם נגיש ו־tooltip, בלי תווית גלויה) |
| 2–4 אפשרויות | `AppSegmentedControl`. בהגדרות: `SettingsSegmentedTile` | קיים. גם בורר מצב החיפוש ובורר שבוע/חודש בלוח השנה (DD-31a). במקטע צר מ־96 (`narrowBelowSegmentWidth`) האייקונים יורדים, ותווית ארוכה מתחלפת ב־`SegmentOption.shortLabel`, והמלאה ב־tooltip ("חיפוש חכם" ← "חכם", q12 Q8). עם `twoRowsWhenClipped` ההחלטה במדידה (`TextPainter`, ‏`segmentPadding`), וכשגם התווית הקצרה בלי אייקון נחתכת — שתי שורות (2×2), באותו סגנון, בחירה, חצים ו־semantics (q-ss7) |
| מתג קטן בתוך שורה | `AppTogglePill` | קיים. תווית `labelMedium` (12), כמו הצ'יפים שלידה (q10 Q1). גם מתג שתוסף מוסיף לדיאלוג החיפוש (q10 Q8e) |
| בחירה מרובה (פילטר) | `FilterChip` של Material + `chipTheme` (DD-13: פינות 8, תווית `labelMedium` 12) | `FilterChipsSelector` / `compactFilterChips`; `ChoiceChip` לבחירה אחת. גם תיבת סימון שתוסף מוסיף לדיאלוג החיפוש (q10 Q8e) |
| Checkbox | `Checkbox` של Material | יעד: `checkboxTheme`. השורה כולה לחיצה (`CheckboxListTile` או `InkWell`) |
| Switch | `SettingsSwitchTile`. מחוץ להגדרות: `Switch` | יעד: `switchTheme`. `CustomSwitch` (4 קוראים) יוסר באותו שינוי, כדי שלא יישארו שני מתגים |
| Slider | `SettingsSliderTile` | `SliderTheme` מקומי אסור |
| תאריך | `showDatePicker` + `datePickerTheme` | קיים |
| שגיאת אימות | `InputDecoration.errorText` | לא טקסט אדום שנבנה ידנית מתחת לשדה |
| קבוצת שדות | `SettingsCard`, או `AppCard` בתוך דיאלוג | |
| תווית מעל שדה | `InputDecoration.labelText` | לא `Text` נפרד עם `TextStyle` מקומי |

### 3.4 כרטיסים ורשימות

| תפקיד | רכיב | הערות |
|---|---|---|
| כרטיס מידע | `AppCard(tone: normal\|primary\|error\|inset)` | `Card(` גולמי אסור (UIL-012; נשארו 2: כרטיס הזמן בלוח השנה, כרטיס הארגון בחלון הגיוס). מסגרת, בלי צל (DD-12). `primary`/`error` על `primaryContainer`/`errorContainer`, והטקסט והאייקונים בצבע ה־on. `inset` לכרטיס בתוך כרטיס, על `surfaceContainerHigh` (q10 Q8a) |
| קבוצת שורות בכרטיס | `AppCard.section(children:)` | מפריד = רווח שקוף |
| כרטיס תוצאה (חיפוש וכלים) | `ResultCardFrame` (DD-11 A): צבע כרטיס, מסגרת `outlineVariant`, ריפוד `AppTokens.cardPadding` (12) ומרווח `AppTokens.listItemGap` (8) בין תוצאות | חלקי. בכלים דרך `ToolResultCardShell` (טקסט נבחר ולחיצה). מספר התוצאה: `SearchResultRankBadge`. עוד לא על המסגרת: כרטיסי איתור מקורות ורשימת תוצאות החיפוש במפרשים |
| היסטוריה וסימניות | **כרטיס בהיר לכל קבוצה** (DD-11, q12 Q9): `ItemsListView` בונה שורות בסגנון `AppCard.section`, רקע `AppSurfaces.card`, פינות בקצות הקבוצה ורווח `AppCard.sectionSpacing` בין השורות, בלי קו. גוף הדיאלוג `AppSurfaces.cardDialogBackground` וריפוד 16, כמו ב־upstream (סקירת 4.11) | גם הסימניות המרוכזות. |
| רשימה בחלונית צד (קישורים, מפרשים, הערות) | שורות שקופות על רקע החלונית, עם מפריד דק ביניהן. **בחלונית ההערות בלבד** כל הערה כרטיס מעוגל ברקע `AppSurfaces.tintedRow`, מוזח `spaceSM` מהקצוות, ובין הכרטיסים רווח `spaceSM` בלי קו (`NoteTile(backgroundColor:)`; ‏#3086, סקירת 4.11, סבב חמישי) | הערה חסרת מיקום מזוהה בכותרת הקבוצה שמעליה, לא בגוון. כרטיס הערה במסך ניהול ההערות הוא `AppCard` עם ריפוד `cardPadding` |
| דיאלוג הסבר בכמה נושאים | מקטעים: `AppSectionLabel` ומתחתיו הפריטים ישירות על גוף הדיאלוג, בגוון הדיאלוג, וקו `Divider` דק בין מקטע למקטע. בלי כרטיסים ובלי גוף כהה יותר | "הצגה או הוספה של הקבצים" (סקירת 4.11, ושנייה) |
| כרטיס עם פעולות | `AppCard` + שורת `ActionButton`/`AppIconButton` בסוף | |
| כרטיס פעיל ברשת (בורר שולחנות העבודה) | `AppCard(active: true)`: מסגרת `multiSelectedBorder` ‏1.5 במקום `outlineVariant`. אזור התצוגה המקדימה בלבד ב־`selectedRow` (אייקון וטקסט `onSelectedRow`); בלא פעילים `surfaceContainerHighest` ו־`primary` (DD-06, השלמה 3.11) | שורת השם בצבע הכרטיס. מחיקה: פח בשורת השם, מושבת בפעיל (DD-11) |
| כרטיס מתרחב | `ExpandableCard`. בהגדרות: `ExpandableSection` | חץ: `ExpandingChevron(style: accordion\|tree)` עם `Semantics(expanded:)` מובנה (DD-27 A). עץ (`NavTreeTile`, כותרות המפרשים, רשימת הקישורים): חץ לכיוון הקריאה, למטה כשפתוח. אקורדיון (`ExpandableSection`): חץ למטה, למעלה כשפתוח. כרטיסי התיקיות בספרייה (`ExpandableCard`) הם אקורדיון (השלמה 2.11) |
| כותרת מקטע מתקפל בטבלה או בעץ עם עמודות | `TreeSectionHeader(isExpanded:, onToggle:, child:, leadingExtent:, padding:)` (‏`lib/widgets/lists/tree_section_header.dart`) | כל השורה לחיצה, החץ בסגנון עץ בתחילת השורה ברוחב `leadingExtent`, ושורות הילדים משאירות אותו רוחב ריק כדי שהעמודות יתיישרו. במקום `ExpansionTile` עטוף ב־Theme מקומי (q10 Q8d, שמור וזכור) |
| שורת הגדרה | `SettingsSwitchTile`, `SettingsDropdownTile`, `SettingsSegmentedTile`, `SettingsPathTile`, `SettingsSliderTile`, ו־`SettingsActionTile` (.text/.path/radioOption) לשאר, בתוך `SettingsCard` | בין כרטיסים בלשונית: **24 בכל הלשוניות** (השלמה 3.11): ריפוד הכותרת של `SettingsCard`, בלי מרווח נוסף. כרטיס שלפעמים לא מוצג לא משאיר מרווח. חלקי: עדיין נבנים ידנית ההדפסה, חלונית צורת הדף, `ShortcutDropDownTile`, `ColorPickerTile` ועוד |
| פריט רשימה | `ListTile`, או `NavTreeTile` בחלוניות | יעד: `listTileTheme` |
| פריט ניווט | `NavRailItem`, `SidebarNavItem`, `NavTreeTile` | |
| תגית / מונה | `MetaChip(tone: neutral\|primary\|error\|warning\|success, size: regular\|small, tooltip:)` (DD-13 A). תווית `labelMedium` 12 (`small`: `labelSmall` 11), צורה 8. `success` בגוון החום הנייטרלי (`secondaryContainer`), לא ירוק. `neutral` ב־`surfaceContainerHighest` (השלמה 2.11) | לא בונים צ'יפ מקומי. נשארו: `SearchResultSourceTag`, `PluginDevBadge`, `PluginUpdateChip`, תג הגימטריה |
| תג אייקון | `ListIconBadge` / `AppDialogIconBadge` | ריבוע מעוגל 8 בשניהם (DD-04) |
| כותרת מקטע | `AppSectionLabel` (DD-14 A): `titleMedium`, `primary`, כותרת לקורא מסך. חריג: בדיאלוג החיפוש ובאיתור המקורות הכותרות הקטנות (13, w600, `primary`) נשארות (השלמה 2.11) | `SettingsCard` מצייר את כותרתו דרכו |
| מפריד שורות בדיאלוג | `listDialogRowDivider` | |

**[מחייב]** רשימה ארוכה (יותר מכ־50 פריטים) נבנית עם `ListView.builder` או `SliverList`. לא מחשבים סגנון בכל פריט: את `Theme.of` קוראים פעם אחת מחוץ ל־builder.

### 3.5 משוב ומצבים

| מצב | רכיב | הערות |
|---|---|---|
| טעינה, מסך או חלונית | `LoadingIndicator`, ועם הודעה `LoadingIndicator(message:)` | חלקי: נשארו 55 `CircularProgressIndicator` גולמיים מחוץ ל־`lib/widgets/feedback` (UIL-013), מהם 4 התקדמות מדודה (`value:`) שאין לה עדיין רכיב משותף |
| טעינה, inline | `LoadingIndicator.inline()` (‏16px, ‏stroke 2) | |
| טעינה, שלד (skeleton) | `SkeletonLines` (רוחב כחלק מהמקום שקיבלו) | |
| ריק | `OtzariaEmptyState` (`isCompact` בחלונית) | |
| ריק "גדול" (ספרייה ריקה, הגדרה ראשונית) | `OtzariaEmptyState.large` (DD-31d) | גם מסך הנעילה של מצב סייפר (q10 Q8c) |
| שגיאה | `OtzariaErrorState(actions: [נסה שוב])` | לא `Text` אדום |
| הצלחה / הודעה קצרה | `UiSnack.show(<Module>Messages.x)` (למשל `SettingsMessages`) | מחרוזות מקטלוג בלבד (UIL-009). `UiSnack` מכריז את ההודעה לקורא מסך |
| באנר בתוך המסך | `AppInfoBanner(tone: info/warning/error/success, title:)` (DD-24). `warning` מטוקני האזהרה, `success` בגוון הנייטרלי. `info` על רקע נייטרלי `surfaceContainerHighest`, אייקון `primary` וטקסט רגיל (השלמה 2.11). בלי מסגרת, כותרת `titleSmall`, הודעה `bodyMedium` | חלקי: נשארו הבאנרים ברוחב מלא בתוצאות החיפוש |
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
| סרגל פעולות | `ResponsiveActionBar` + `ActionButtonData` | פריטים דרך `BarButton` בלבד. תמיד שורה אחת: מה שלא נכנס עובר ל"עוד פעולות" לפי `toolbarOverflowOrder`, מהנדיר לנפוץ. גם סרגל העיצוב בעורך ההערות (q12 Q6): ברוחב הדיאלוג 10 כלים ו"עוד", בצפיפות קומפקטית כל 12 |
| כמה הגדרות לכמה יעדים בחלונית צפה | `TextDisplayProfileTable` (חלונית "תצוגת הטקסט" בסרגל הקורא) | טבלה: שורה לכל הגדרה ועמודה לכל יעד, אייקון ושם בעמודה הראשונה, וההסבר ב־tooltip על השם (q12 Q7). בלי מקום לטבלה השם עולה מעל, ושורה לכל יעד. מסך ההגדרות נשאר בשורות `SettingsCard` |
| חלונית ניווט | `NavSidePanel` | אזור "חלוניות לצד הקריאה" (DD-18). נסגרת אחרי מעבר רק כשהיא מכסה את התוכן (DD-26) |
| חלונית משנית או צפה | `AdaptiveSidePane` / `ContextOverlayPanel` | DD-28 A: רוחב 340 מ־`LayoutConstraints.sidePaneWidth`, הגבהה לפי DD-12, רקע לפי DD-18 |
| ידית פתיחה של חלונית | `PositionedPanelOpenHandle` | ממוקמת לפי המכל שלה ולא לפי החלון |
| Split pane | `SplitPaneView` (tabs) | |
| מסך הגדרות | `SettingsTabScrollView` + `SettingsCard` | |
| מסך תוצאות | `ResultCardFrame`; מעל תוצאות כלי: `ToolResultsHeader(label, leading, child)` | אזור התוצאות על `panelBackground`, ועץ הסינון על `navPanelBackground` (DD-18) |
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

**רכיבים משותפים שמייבאים פיצ'רים** (UIL-024, 30 מופעים ב־baseline): `lib/widgets/commentary/**`, `lib/widgets/smart_text/smart_text_widget.dart`, תפריטי הקישורים (`link_context_menu_entry`, `direct_link_menu_entries`, `link_preview_overlay`), `ad_popup_dialog` ו־`phone_report_tab`. רכיב חדש לא מצטרף אליהם: הכלל חוסם.

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
| חלון צר במחשב (420–600) | **כמו טלפון אבל עם עכבר.** שטחי הלחיצה נשארים לפי דסקטופ. "צפיפות ממשק" האוטומטית נשארת רגילה: במחשב רק חלון נמוך מ־480 הוא "חלון קטן" (q-density-desktop-narrow). החלון המינימלי הוא 420×400 |
| חלון נמוך (גובה <480: טלפון לרוחב) | עמודה בצד וכרטיסיות בשורת הכותרת, גם מתחת ל־600. כרום בצפיפות קומפקטית. דיאלוג `large`/`full` במסך מלא בכל רוחב (q12 Q8). בספרייה התצוגה המקדימה סגורה עד שהמשתמש פותח אותה, והבחירה שם נשמרת בנפרד. במסך ההגדרות אין כותרת "הגדרות" מעל הרשימה, כי שורת הכותרת של החלון כבר אומרת אותה |
| חלוניות מפוצלות | כל חלונית מחליטה לפי ה־constraints שלה ולא לפי החלון. ידית הגרירה בסרגל (`AppTopBar`). לחלונית בלי סרגל, כמו תוסף, `FloatingPaneDragHandle`: במחשב רק בריחוף על הרצועה העליונה של החלונית (`hoverStripHeight`, ‏44, לכל הרוחב), ובמנוחה שקופה ולא חוסמת. במגע מוסתרת באותו אופן, ומופיעה בגרסה הקטנה רק אחרי נגיעה ברצועה. הנגיעה מגיעה גם לתוסף (`Listener`, לא נבלעת). הידית נעלמת אחרי `touchRevealDuration` (‏3 שניות), נשארת בזמן גרירה, והספירה מתחילה מחדש בסוף הגרירה. במגע לחיצה ארוכה על הידית (גם בסרגל הספר) מתחילה גרירה ולא הסבר: ה־tooltip שלה ב־`TooltipTriggerMode.manual` (#2635) |
| שינוי גודל בזמן ריצה | אין מצב שמחושב פעם אחת ב־`initState` לפי רוחב. רוחב שמור נשמר **כיחס** ולא בפיקסלים |
| הגדלת טקסט | ראו 6.3 |

---

## 6. RTL, עברית ונגישות

### 6.1 כיווניות [מחייב]
- **הכיווניות גלובלית:** `Locale('he','IL')`. לא מוסיפים `TextDirection.rtl` ל־`Text`. כן מוסיפים `TextDirection.ltr` לתוכן שהוא LTR מטבעו: נתיב, URL, דוא"ל, גרסה, hash ומזהה.
- **Directional APIs בלבד:** `EdgeInsetsDirectional`, `AlignmentDirectional`, `PositionedDirectional`, `BorderRadiusDirectional`, `start`/`end`.
  - אסור: `left`/`right` ו־`Alignment.centerLeft` (UIL-021; 51 מופעים ב־baseline).
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

---

## 7. מצבי משתמש וערכות נושא

| הגדרה | איפה נשמרת | איפה מוחלת | היקף | הערות |
|---|---|---|---|---|
| ערכת צבע (seed), בהיר | `SettingsBloc.seedColor` | `app.dart` → `createColorScheme` | גלובלי, כל הכרום | 14 זרעים. ל"לבן" ול"פרגמנט" יש override לסולם המשטחים, לפי הזרע. ב"לבן" הקריאה לבנה, והסרגלים, הדיאלוגים והלוח כמעט לבנים (FC, לוח FA), והאזורים מופרדים בקו דק אפור בינוני־בהיר (9F), `regionBorder` (q12 Q3, סקירת 4.11). צבע הבחירה (`secondaryContainer`) E0, והנבחר גם בקו `selectedBorder` (סקירת 4.11, סבב רביעי) |
| ערכת צבע, כהה | `darkSeedColor` | כנ"ל | גלובלי | הבורר עורך רק את הזרע של הבהירות הנוכחית. לוחות כהים `surfaceContainerLow`, קריאה נייטרלית (DD-05) |
| בהיר/כהה/מערכת | `isDarkMode`, `followSystemTheme` | `MaterialApp.themeMode` | גלובלי | |
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
3. **תוספים (DD-25 A) · קיים:** תוספים (WebView) מקבלים את ערכת הנושא דרך `buildThemePayloadFromScheme`. מ־0.9.99 ה־payload כולל, כתוספת שאינה שוברת, גם `surfaces` (reader, panel, card, topBar מתוך `AppSurfaceColors`), `radius`, `spacing`, `density` (מתוך `AppDensity`) ו־`typography.uiFont` (גופן הממשק של המארח כערך CSS). `uiFontFamily` נשאר 'Rubik' לתאימות. השדות מתועדים ב־`otzaria_plugin.d.ts`, ב־`API_REFERENCE.md` וב־`DESIGN_GUIDE.md` כאופציונליים מ־0.9.99. כשמוסיפים טוקן משטח או גופן ממשק, מוסיפים אותו גם ל־payload.

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
| דיאלוג חדש | Escape, dirty (אם יש קלט), Enter על ביטול, רוחב 360, טקסט ×1.3 |
| שינוי טוקן או ערכת נושא | `test/theme/` (ניגודיות לכל הזרעים), ועדכון golden מכוון |
| פירוק קובץ גדול (DD-30) | characterization לפני, אותן בדיקות אחרי, בלי שינוי חזותי, ב־commit נפרד לפני ה־commit החזותי |
| רכיב שמגיב ללחיצה שאינו כפתור Material | `Semantics(button:)` + Enter/Space + פוקוס |
| מחרוזת בכרום מתורגם | `test/settings/l10n/` |
| כל שינוי | `flutter analyze`, ‏`test/design_system/ui_lint_test.dart` והבדיקות שקשורות לשינוי (`docs/agent_test_map.md`) |

רשימת הבדיקה ל־PR חזותי נמצאת ב־`AGENTS.md` ("UI rules") וב־`.github/PULL_REQUEST_TEMPLATE.md`.

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
| ריווח | `AppTokens.space*` + טוקנים סמנטיים | חלקי | ריווח מחוץ לסולם (UIL-020), ארבעה טוקנים סמנטיים ביעד |
| רדיוסים | `AppTokens.radius` (ערך אחד, DD-04) | קיים | — (UIL-019 נעול) |
| הגבהה וצל | `AppTokens.elevation*` + `AppShadows` (DD-12) | קיים | 4 צללים מקומיים (UIL-030) |
| גבהים | `AppInputTokens` + `AppDensity` | קיים | — |
| גדלי אייקון | `AppTokens.icon*` (DD-03) | חלקי | גדלים מספריים (UIL-029) |
| אנימציות | `AppTokens.anim*` + `AppMotion` (DD-21) | חלקי | 8 `AnimationController` עם משך ליטרלי (UIL-023), משכים בלי טוקן, עקומות ביעד |
| הגדרות דיאלוג | `lib/widgets/dialogs/` (`AppDialog`, `AppDialogFrame(size: AppDialogSize)`) | חלקי | 3 דיאלוגים גולמיים (UIL-001) ו־54 `showDialog` ישירים (UIL-028) |
| פריסות מסך | `lib/widgets/layout/`, `navigation/`, `ToolScaffold` | חלקי | מעטפות מקומיות |
| רכיבי ניווט | `NavSidePanel`, `NavRailItem`, `NavTreeTile`; רוחב חלונית `LayoutConstraints.sidePaneWidth` (DD-28) | קיים | — |
| רספונסיביות | `LayoutBreakpoints` + `WindowClass` (DD-15) | קיים | — |
| צפיפות | `AppDensity` (DD-10) | קיים | — |
