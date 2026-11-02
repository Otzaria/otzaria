# מערכת העיצוב של אוצריא — מסמך התקן

> **מעמד:** גרסה 1.0 (1.11.2026). כל ההכרעות DD-01..31 אושרו בידי בעל הפרויקט. נכתב מול `upstream/dev` ב־`f86ecd7c7`, עודכן מול `ac97e4490` אחרי #3794 (1.11.2026).
> **הקוד עוד לא שונה.** כל כלל מסומן אם הוא כבר **קיים** בקוד, או **יעד — טרם מומש**, עם ה־PR שיממש אותו (`MIG-xx` ב־[MIGRATION_PLAN.md](MIGRATION_PLAN.md)).
> **קהל:** כל מי שכותב קוד ממשק באוצריא: מפתחים, סוקרים וסוכני AI.
> **מסמכים נלווים** (כולם בתיקייה זו):
> - [UI_AUDIT.md](UI_AUDIT.md): הממצאים בקוד הקיים, עם מזהים `UI-xxx`.
> - [DESIGN_DECISIONS.md](DESIGN_DECISIONS.md): ההכרעות, עם מזהים `DD-xx`, והרשומה המלאה ב־[decisions/](decisions/).
> - [MIGRATION_PLAN.md](MIGRATION_PLAN.md): סדר ה־PRs ושיטת העבודה.
> - [CI_ENFORCEMENT.md](CI_ENFORCEMENT.md): אכיפה אוטומטית.
> - [DEVELOPER_GUIDE.md](DEVELOPER_GUIDE.md): איך עובדים בפועל.
> - [ui-audit.json](ui-audit.json): הממצאים בפורמט מכונה.

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
| **יעד — טרם מומש (MIG-xx)** | הוכרע, אבל הקוד עוד לא שונה. | עד שה־PR המצוין נכנס: קוד חדש משתמש בטוקן או ברכיב הקיים הקרוב ביותר (מצוין לצידו), ולא משנים מראה קיים מחוץ ל־PR המיישם. |
| **⚠** | פתוח, או ממתין לאישור חוזר על פרשנות. | לא מיישמים את החלק המסומן עד תשובה. |

**ערך שלא נקבע בהכרעה** (גוון מדויק, ריפוד שלא נשאל עליו) נקבע ב־commit המיישם, עם תמונות לפני/אחרי לאישור בעל הפרויקט. המסמך לא ממציא ערכים.

**מקור אמת:** לכל סוג ערך יש מקור אחד בקוד, וטבלה מרוכזת שלהם מופיעה בנספח א'. בערך **קיים**, כשהמסמך והקוד סותרים, הקוד ב־`lib/theme/` קובע את הערך, ואת הסתירה מתעדים כממצא. בערך **יעד**, ההכרעה קובעת.

**מה לא נכלל:** טיפוגרפיה וצבעים של **תוכן הספרים** כפופים להגדרות הקריאה של המשתמש, ולא לטוקני הממשק. ראו סעיף 2.4.2.

---

## 1. עקרונות העיצוב (ב.1)

### 1.1 עקרונות מחייבים

1. **מקצועי, נקי ועקבי.** אותו תפקיד נראה ומתנהג אותו דבר בכל מקום. דיאלוג אישור במסך ההגדרות זהה לדיאלוג אישור בכלי לוח השנה.
2. **עברית ו־RTL הם מצב הבסיס, לא תרגום.** כל רכיב נבנה ונבדק קודם ב־RTL. מצב LTR קיים בשני מקרים בלבד: מצב האנגלית של כרום הממשק (`ChromeDirectionality`, DD-20), ותוכן שהוא LTR מטבעו, כמו נתיבים, כתובות, מזהים וגרסאות.
3. **הקריאה במרכז.** התוכנה היא כלי קריאה וחיפוש בספרים. אזור הקריאה שקט, וכל ממשק אחר משרת אותו. צבע, צל ותנועה לא מתחרים בטקסט.
4. **צפיפות מאוזנת לשימוש ממושך במחשב.** ברירת המחדל מותאמת לעכבר ולמקלדת ולשעות עבודה ארוכות. מגע נתמך דרך שטחי לחיצה מינימליים (סעיף 2.5.6) ולא דרך הגדלה כללית של כל הממשק.
5. **הבחנה ברורה בין תוכן, ניווט ופעולות.** שלושה אזורים, לכל אחד משטח משלו (DD-18, סעיף 2.1): רקע קריאה, רקע לוח לכלים, ורקע חלונית לצד הקריאה.
6. **נגישות היא חלק מההגדרה של רכיב.** רכיב משותף שאין לו שם נגיש, פוקוס מקלדת ומצב (נבחר, מורחב, מושבת) לא נחשב שלם.
7. **ביצועים.** אין עטיפות Widget שנועדו רק "ליישור", אין חישובי עיצוב בתוך פריטי רשימה גדולה, ואין `TextPainter` בלולאה בתוך כפתור.
8. **שימוש חוזר לפני שכפול.** לפני שכותבים רכיב, מחפשים את הקיים בקטלוג (סעיף 3). רכיב חדש נוסף רק לפי הכללים ב־`DEVELOPER_GUIDE.md` §8.
9. **שינוי סגנון גלובלי במקום אחד.** החלפת צבע, רדיוס, גופן או צפיפות נעשית ב־`lib/theme/` בלבד, בלי לגעת בקבצי פיצ'רים.
10. **מינימום חריגים.** חריג מותר רק עם הערת `ui-lint: allow` ונימוק (ראו `CI_ENFORCEMENT.md` §3.5), או כשהוא רשום ברשימת ההחרגות שבהגדרות ה־CI.

### 1.2 הכרעות סגנון שאושרו (גרסה 1.0)

ההעדפות שהסבבים הקודמים (#3322, #3539, #3794) הנהיגו הן עכשיו תקן **[מחייב]**:
- רצועת כותרת (`headerBand`) ותג אייקון **בכל** דיאלוג, כולל `small` (DD-07 B). ב־`small` אין X (השלמה 2.11).
- כפתור ביטול בסגנון `neutral` (tonal) (DD-09 A).
- כותרות מקטע בצבע `primary`, דרך `AppSectionLabel` (DD-14 A). חריג: בדיאלוג החיפוש ובאיתור המקורות נשארות הכותרות הקטנות שלהם, 13 (השלמה 2.11).
- מסגרת `outlineVariant` ולא צל לכרטיסים (DD-12 A).
- רדיוס אחד, 8, לכל רכיב מלבני, כולל צ'יפים, כפתור סרגל עם תווית ותג אייקון (DD-04 A). שני חריגים: כפתור אייקון בלבד נשאר עגול, ו־`BarSplitButton` (אייקון וחץ) נשאר גלולה (השלמה 2.11).

**⚠ פתוח או ממתין לאישור חוזר:**
- **ממצא לסבב הבא (DD-07, DD-09):** בדיאלוג ההתנגשויות בייבוא ההערות, ״דרוס״ (`ActionButton.warning`) הוא טקסט אדום בלי רקע, ליד שלושה כפתורי `neutral` עם רקע, ולכן הפעולה המסוכנת נראית החלשה בשורה. לא הוכרע ולא שונה.
- **שולחנות העבודה (MIG-17):** הוכרע להסב (השלמה 2.11), והתמונה של ההסבה תוצג לפני המימוש.

---

## 2. מערכת הטוקנים (ב.2)

### 2.0 מבנה הטוקנים בקוד — מה קיים

| קובץ | מחלקה | תוכן | הערכה |
|---|---|---|---|
| `lib/theme/app_tokens.dart` | `AppTokens` | ריווח 4/8/16/24/32, רדיוס 8, גופן 12/14/16/18, elevation 1/3, משכי אנימציה, מידות ידית גרירה ולשונית. | בסיס טוב. חסרים 2/12 בריווח, טוקנים סמנטיים, אייקונים וגבולות (DD-03, MIG-04). |
| `lib/theme/app_tokens.dart` | `AppTextStyles` | `settingTitle` 16, `settingSubtitle` 13. | שני סגנונות בלבד. הסולם עובר ל־`textTheme` (DD-02, MIG-05). |
| `lib/theme/app_surfaces.dart` | `AppSurfaces` | כ־31 פונקציות סטטיות של משטחים וצבעי מצב. | מקור האמת למשטחים. עובר ל־ThemeExtension (DD-19, MIG-06). |
| `lib/theme/app_colors.dart` | `AppColors` | 4 צבעים קבועים. | תקין. `permanentHighlight` עובר לטוקן תפקיד (DD-17, MIG-23). |
| `lib/theme/app_input_tokens.dart` | `AppInputTokens` | גובה שדה 48/36, גופן 16/13 וערכי שקיפות. | תקין. גובה שלישי, 40, מוגדר מחוץ לקובץ (`otzaria_search_field.dart:17`). |
| `lib/theme/layout_tokens.dart` | `LayoutBreakpoints`, `LayoutPadding`, `LayoutConstraints` | 600/840/1200, 16/24/32, 860. | בשימוש ב־8 קבצים בלבד, מול 32 ספי רוחב מספריים בקוד (DD-15, MIG-21). |
| `lib/theme/app_theme_data.dart` | `AppThemeData` | בניית `ColorScheme` ו־`ThemeData`. | חסרים component themes ו־textTheme מלא (DD-02, MIG-05, MIG-08). |
| `packages/otzaria_context_menu` | `AppMenuMetrics` | ה־ThemeExtension היחידה באפליקציה. | הערכים זהים בשני מצבי הצפיפות (`menu_metrics.dart:30-46`, DD-10). |
| `lib/theme/app_seed_colors.dart`, `calendar_event_colors.dart` | — | פלטות תוכן. | תוכן, לא מדיניות. מוחרגים מכללי ה־CI. |

**[מחייב]** טוקנים חדשים נוספים לקבצים האלה בלבד. לא פותחים קובץ טוקנים מקביל בתיקיית פיצ'ר.
**[מחייב]** טוקן הוא `static const` כשהערך לא תלוי בערכת הנושא, כמו ריווח, רדיוס, משך וגודל. כשהערך תלוי בערכת הנושא (צבע) או בצפיפות, הוא שדה ב־ThemeExtension: `AppSurfaceColors` ו־`AppDensity` (DD-19 A, **יעד — טרם מומש, MIG-06**). ריווח ורדיוס **לא** נכנסים ל־ThemeExtension. עד MIG-06: פונקציה של `ColorScheme`/`BuildContext` ב־`AppSurfaces`, שתישאר אחר כך כעטיפה דקה בזמן המעבר.

### 2.1 צבעים

**כלל היסוד [מחייב]:** קוד פיצ'ר בוחר **תפקיד** ולא צבע. הסדר הוא:
1. תפקיד של `ColorScheme`: `primary`, `onSurface`, `onSurfaceVariant`, `error`, `outlineVariant` וכו'.
2. אם אין תפקיד מתאים, משטח או מצב מ־`AppSurfaces`.
3. אם גם זה לא קיים, מוסיפים פונקציה חדשה ל־`AppSurfaces` עם תיעוד. לא מוסיפים שקיפות מקומית.

**[אסור]** בקבצי פיצ'ר:
- `Color(0x…)`.
- `Colors.<גוון>` (`red`, `blue`, `grey` וכו').
- `.withValues(alpha:)`, `.withAlpha(` ו־`.withOpacity(` על צבעי ממשק.
- `Theme.of(context).primaryColor`. זהו באג מוכח: במצב כהה Flutter מחזיר דרכו את `surface` (UI-019).
- `hoverColor`, `splashColor` ו־`overlayColor`.
- ענף `brightness == Brightness.dark` לבחירת צבע. ההחלטה שייכת ל־`AppSurfaces`.

`Colors.transparent` מותר. החריגים המותרים מפורטים בסעיף 2.1.3.

#### 2.1.1 קטלוג תפקידי הצבע

| טוקן (תפקיד) | מקור בקוד | ערך בהיר | ערך כהה | סטטוס | שימוש |
|---|---|---|---|---|---|
| רקע קריאה | `AppSurfaces.readerBackground` | `cs.surface` | נייטרלי, לא נגזר מהזרע: `AppColors.darkScaffold` `#242424`, לכל ערכת צבע (DD-05, השלמה 2.11) | קיים (DD-05 C) | מסכי ספר ו־PDF |
| רקע לוח (מסכי עבודה) | `AppSurfaces.panelBackground` | `surface` + `surfaceContainerHighest` בשקיפות 47.5% | **`surfaceContainerLow`** (היום `Colors.black`) | בהיר קיים. כהה: יעד — טרם מומש (DD-05 C, MIG-07) | הגדרות, ספרייה וכלים, ואזור התוצאות בכרטיסיית החיפוש (DD-18, UI-143) |
| ~~רקע לוח "מוצק"~~ | ~~`AppSurfaces.solidPanelBackground`~~ | — | — | **הוסר** (UI-128, MIG-03); הקוראים עברו ל־`panelBackground` | — |
| סרגל עליון | `AppSurfaces.topBarBackground` | `surfaceContainerHigh` | `surfaceContainerHigh` | קיים, ללא שינוי | `AppTopBar` |
| חלונית ניווט | `AppSurfaces.navPanelBackground` | = topBar | = topBar | קיים (שם נרדף מכוון) | `NavSidePanel`, חלוניות לצד הקריאה (DD-18) |
| כרטיס | `AppSurfaces.card` | `surface` | `surfaceContainer` | קיים | `AppCard`, `ListDialogCard`, `DetailsCard` |
| מפריד | `AppSurfaces.cardRowDivider` | = panelBackground | שחור, ושגוי מעל דיאלוג | יעד — טרם מומש (DD-12, MIG-08): מפריד אחד. רווח שקוף בתוך `AppCard.section`, וקו `subtleDivider` ברשימות | — |
| מפריד עדין | `AppSurfaces.subtleDivider` | `outlineVariant` בשקיפות 50% (הערך הקיים, כפול היום ב־3 מקומות) | כנ"ל | יעד — טרם מומש (MIG-08) | רשימות |
| מקטע ניטרלי בחלונית | `AppSurfaces.panelSection` | `surfaceContainerHighest` בשקיפות 50% | כנ"ל | קיים | חלוניות הגדרות |
| מקטע מודגש | `AppSurfaces.panelSectionAccent` / `…AccentBorder` | `primaryContainer` 30% / `primary` 30% | כנ"ל | קיים | — |
| משטח מוגבה (תפריט, tooltip, דיאלוג) | `dialogTheme`/`menuTheme`/`tooltipTheme` | `surfaceContainerHigh` | `surfaceContainerHigh` | קיים. **popupMenu חורג:** `surfaceContainer` (UI-076, MIG-03) | — |
| טקסט ראשי | `cs.onSurface` | M3 | M3 | קיים | — |
| טקסט משני | `cs.onSurfaceVariant` | M3 | M3 | קיים. מחליף את `onSurface` בשקיפות 50–60% (כ־20 מופעים) | תת־כותרות, מטא־דאטה |
| מסגרת והפרדה | `cs.outlineVariant` | M3 | M3 | קיים | מסגרת כרטיס (DD-12) |
| פעולה ראשית / משנית | `cs.primary` / `cs.secondaryContainer` | M3 | M3 | קיים, דרך `ActionButton` | — |
| שגיאה | `cs.error` / `cs.errorContainer` | M3 | M3 | קיים | — |
| אזהרה | `AppSurfaces.warning`, `onWarning`, `warningContainer`, `onWarningContainer` | הגוון הקבוע `AppColors.warningHue` (`#FB8C00`) עובר `harmonize` מול `primary` של הערכה, ולכן משתנה מעט מערכה לערכה (DD-24, השלמה 2.11: מותאם לערכה ולא כתום קבוע) | כנ"ל | יעד — טרם מומש (DD-24 A, MIG-12) | באנרים, תגיות `warning` |
| הצלחה | `cs.secondaryContainer` / `onSecondaryContainer` | הגוון הנייטרלי הקיים (חום בערכת ברירת המחדל), **לא ירוק** | M3 | קיים (DD-24, DD-13) | הודעת הצלחה, סמל ה־וי, תגית `success` |
| Hover / Pressed / Focus של כפתורים | `_hoverButtonStyle` (שקיפות 8%/12% על primary) | | | קיים בערכת הנושא | — |
| שורה נבחרת | `selectedRow` = `secondaryContainer` | | | יעד — טרם מומש (DD-06 C, MIG-07). היום ≥8 הגדרות (UI-018); עד אז `AppSurfaces.selectedItem` | רשימות, עצים, כרטיסיות |
| שורה בפוקוס | `focusedRow` = טבעת פוקוס + `primary` בשקיפות 8% | | | יעד — טרם מומש (MIG-07) | — |
| ריחוף | `hoverRow` = שכבת ה־hover של M3 (`onSurface` 8%) | | | יעד — טרם מומש (MIG-07) | — |
| בחירה מרובה | `multiSelected` | ערך ב־commit עם תמונות | | יעד — טרם מומש (MIG-07) | כרטיסיות |
| מושבת | Material (שקיפות 38%) | | | קיים. לא מגדירים ידנית | — |
| הדגשת חיפוש וסימון | `searchHit`, `searchHitCurrent`, `permanentMark`, ו־CSS role tokens בתוך ה־HTML (כמו `otzaria-reader-link`) | גוונים ב־commit עם תמונות, בהיר וכהה. הרקעים שקופים 80%, כדי שסימון בעכבר ייראה גם בתוכם (DD-17, השלמה 2.11) | | יעד — טרם מומש (DD-17 A, MIG-23). היום 4 מערכות במקביל | קורא, PDF |
| הדגשה בקטעי תוצאות החיפוש | `cs.error` | | | קיים, **נשאר** (DD-17) | קטעי תוצאה |
| קישור בספר | `AppSurfaces.readerLink` | `primary` (אפור בערכה נייטרלית) | | קיים | תוכן |
| בחירת פסקה / שורה מודגשת | `paragraphSelectionBackground`, `highlightedLineBackground` | | | קיים | קורא |
| scrim | `AppSurfaces.scrim`, אחד לדיאלוגים ולחלוניות | עדין, כמו היום בדיאלוגים (`0x22000000`) | כנ"ל | יעד — טרם מומש (DD-12 A, MIG-08). היום 0.30 ב־`AdaptiveSidePane`/`ContextOverlayPanel` | — |
| צל | `AppShadows` | | | יעד — טרם מומש (DD-12 A, MIG-08). כרטיסים בלי צל | תפריט, חלונית צפה |

#### 2.1.2 צבעי ניווט, קריאה וסימון
- **ניווט [מחייב] · קיים:** הסרגל העליון וחלונית הניווט חולקים צבע אחד (`topBarBackground`), כדי שייראו כרצועה רציפה.
- **כרטיסיות [מחייב] · יעד — טרם מומש (DD-06, MIG-21):** שלוש רצועות הכרטיסיות משתמשות באותם `hoverRow` ו־`multiSelected` (היום שונים, UI-014). הכרטיסייה הפעילה, ברצועה האופקית וברצועה האנכית, בצבע הסרגל (`topBarBackground`) ובמשקל w600 (השלמה 2.11). ברצועה האופקית הצורה מחברת אותה לפס, וברצועה האנכית היא בולטת על רקע הלוח. בחיפוש הכרטיסיות הכרטיסייה הנוכחית ב־`selectedRow`. "נבחר" מסומן גם במשקל הגופן או באייקון, לא רק בצבע.
- **סימון טקסט בקורא:** צבעי הדגשה שהמשתמש בוחר (מרקר, צבעי אירועים) הם **תוכן**. שומרים אותם כנתון (אינדקס או ARGB) ומתאימים אותם לבהירות בזמן ציור, כפי ש־`CalendarEventColors` כבר עושה.

#### 2.1.3 חריגים מותרים לצבע מקומי [מחייב] (DD-24)
צבע מקומי מותר **רק** בארבעה מקרים:
1. **תוכן:** `AppSeedColors`, `CalendarEventColors`, צבעי מרקר, צבעי CSS שמגיעים מתוך הספר, וציור של תוכן ב־`CustomPainter` (דף PDF, הצללת דפדוף). גם שם עדיף לקבל צבע מתפקיד.
2. **ייצוא והדפסה** (`package:pdf`, ‏`pw.*`): הפלט הוא דף נייר לבן, ללא תלות בערכת הנושא.
3. **חיקוי כרום של מערכת ההפעלה**, כמו כפתורי חלון בסגנון Windows.
4. **צללים** — רק בתוך `AppShadows` ב־`lib/theme/` (יעד, MIG-08). עד אז הצללים הקיימים נשארים כחריג.

---

### 2.2 ריווח

**קיים:** `spaceXS=4`, `spaceSM=8`, `spaceMD=16`, `spaceLG=24`, `spaceXL=32`. בקוד יש 468 שימושים בטוקנים האלה.
**הפער:** 12 מופיע כ־133 ערכים קשיחים ו־6 כ־39, וגם 10 ו־14 נפוצים.

| טוקן | ערך | סטטוס | תפקיד |
|---|---|---|---|
| `AppTokens.space2XS` | 2 | יעד — טרם מומש (DD-03 C, MIG-04) | הפרדה בין שורות טקסט צמודות, מרווח אייקון־מונה |
| `AppTokens.spaceXS` | 4 | קיים | בין אייקון לטקסט צמוד, ריפוד תגית אנכי |
| `AppTokens.spaceSM` | 8 | קיים | בין פריטים קשורים, בין כפתורים |
| `AppTokens.spaceSMD` | 12 | יעד — טרם מומש (DD-03 C, MIG-04) | ריפוד פנימי של שורת רשימה, בין קבוצות קטנות |
| `AppTokens.spaceMD` | 16 | קיים | ריפוד דיאלוג אופקי, בין כרטיסים |
| `AppTokens.spaceLG` | 24 | קיים | ריפוד דיאלוג (M3), בין מקטעים |
| `AppTokens.spaceXL` | 32 | קיים | שוליים של מסך רחב |

**כלל העיגול [מחייב] (DD-03):** ריווח שמחוץ לסולם **עולה** לערך הבא: 6→8, ‏10→12, ‏14→16. העיגול נעשה כשהקובץ מוסב, לא בהחלפה גורפת.

**טוקנים סמנטיים** (`static const EdgeInsets` ב־`AppTokens`, DD-03 C, **יעד — טרם מומש, MIG-04**). כל הערכים נגזרים מהסולם. ערך שלא הוכרע נקבע ב־commit המיישם, עם תמונות:

| שם | ערך | מקור הערך | ערך נפוץ היום |
|---|---|---|---|
| `cardPadding` | `all(12)` | DD-11 (כרטיס תוצאה) | 12 / 14×12 / 16 |
| `listRowPadding` | ב־commit המיישם | — | 12/8, 12/10, 14/10, 16/12 |
| `listItemGap` | 8 בין תוצאות | DD-11 | 6 / 8 / 16 |
| `sectionGap` | ב־commit המיישם | — | 16–32 |
| `dialogPadding` | הערך הקיים, `fromLTRB(24, 16, 24, 16)` | קוד (UI-144) | — |
| `titleContentGap` | ב־commit המיישם | — | 8–16 |
| `labelFieldGap` | ב־commit המיישם | — | 4–8 |
| `screenPadding` | `LayoutPadding.compact/medium/expanded` (16/24/32) | קיים | כמעט לא בשימוש |

**[מחייב]**
- ריווח בקוד פיצ'ר נכתב רק כטוקן או כצירוף של טוקנים (`spaceSM + spaceXS`). אסור "טוקן ± 1" (`spaceSM + 1`), כי זה ערך שמחוץ לסולם בתחפושת.
- `EdgeInsets.only(left/right)` ו־`EdgeInsets.fromLTRB` אסורים כשהריווח תלוי כיוון. משתמשים ב־`EdgeInsetsDirectional`.

### 2.3 רדיוסים

**[מחייב] (DD-04 A):** **ערך אחד, 8**, לכל רכיב מלבני: `AppTokens.radius`, ‏`borderRadiusAll` ו־`roundedShape` (קיים, 244 שימושים).

| תפקיד | היום | התקן | סטטוס |
|---|---|---|---|
| שדה, כפתור טקסט, כרטיס, דיאלוג, תפריט, tooltip | 8 | 8 | קיים |
| תגית `MetaChip` | 8 | 8 | קיים |
| צ'יפ בחירה (`compactFilterChips`) | 8 (`Chip` של M3). ה־`StadiumBorder` ב־`FilterChipsSelector` הוא רק צורת ה־InkWell, ולא נראה | 8. מסירים את ה־`StadiumBorder` הלא נראה | קיים חזותית; הניקוי ב־MIG-08 |
| כפתור סרגל עם תווית (`BarButton.icon` + `label`) | גלולה (`StadiumBorder`, `circular(100)`) | 8. הגלולה מוסרת | יעד — טרם מומש (MIG-13) |
| תג אייקון של דיאלוג (`AppDialogIconBadge`) | עיגול | ריבוע מעוגל 8, כמו `ListIconBadge` | יעד — טרם מומש (MIG-13) |
| רכיב פנימי בתוך מכל מעוגל (InkWell בכפתורי הדפדוף ב־PDF, UI-080) | 8, והפינות בולטות | נגזר מהמכל (clip). **אין** `radiusInner` | יעד — טרם מומש (MIG-23) |
| רכיבים עגולים מטבעם (נקודת סטטוס, אווטאר) | עיגול | עיגול | קיים |
| כפתור אייקון בלבד ב־`BarButton` (`CircleBorder` לבחירה ול־hover) | עיגול | **עיגול**, חריג מאושר (DD-04, השלמה 2.11) | קיים |
| כפתור סרגל מפוצל (`BarSplitButton`, אייקון וחץ בלי תווית) | גלולה (רדיוס חצי הגובה) | **גלולה**, חריג מאושר (DD-04, השלמה 2.11) | קיים |

**[אסור]** כל רדיוס אחר: `circular(n)` ליטרלי, `StadiumBorder`, ו־4 בתוך תפריט. `CircleBorder` מותר רק לרכיב עגול מטבעו ולכפתור אייקון בלבד.

### 2.4 טיפוגרפיה

#### 2.4.1 טיפוגרפיית ממשק

**המצב היום:**
- `ThemeData.textTheme` דורס רק את `bodyMedium = 18` (`app_theme_data.dart:97-99`). התוצאה היא היפוך היררכיה: תת־כותרת של `ListTile` (18) גדולה מהכותרת שלה (16), ובמצב ריק ההודעה גדולה מהכותרת (UI-015).
- `fontFamily: 'Roboto'` מוגדר אבל **הגופן לא כלול באפליקציה**, ולכן הממשק מוצג בגופן מערכת שונה בכל מחשב.
- בנוסף קיימים 158 גדלי גופן קשיחים, ובהם ערכים מחוץ לסולם: 13 (×32), 11 (×10), 15 (×9) ו־10.

**גופן הממשק [מחייב] (DD-01 A) · יעד — טרם מומש (MIG-05):** גופני המערכת במפורש. `fontFamily: null`, ורשימת `fontFamilyFallback` מפורשת לפי פלטפורמה (`'Segoe UI'`, `'SF Pro Text'`, `'.AppleSystemUIFont'`, `'Noto Sans Hebrew'`, `'Arial'`), שמוגדרת ב־`AppThemeData` בלבד. אין 'Roboto' בשום מקום: 9 המופעים הקשיחים (6 ב־`lib`, 3 ב־`otzaria_context_menu`) נמחקים. אין שינוי חזותי ב־Windows (Segoe UI נשאר).

**הסולם [מחייב] (DD-02 C) · יעד — טרם מומש (MIG-05):** סולם תפקידים אחד, מוגדר במלואו ב־`ThemeData.textTheme`. קוד פיצ'ר בוחר **תפקיד**. הגדלים הוכרעו ב־DD-02. המשקלים הם אלה שהוצגו בטבלה שאושרה:

| תפקיד בממשק | slot ב־textTheme | גודל / משקל | היום |
|---|---|---|---|
| כותרת ראשית (מסך ריק גדול, אודות) | `headlineSmall` | 22 / w600 | 24 (M3) |
| כותרת מסך / סרגל עליון | `titleLarge` | 18 / w600 | AppTopBar ‏16/w600 קשיח |
| כותרת דיאלוג | `titleLarge` | 18 / w600 | 22 / w400 (M3) |
| כותרת מקטע (`AppSectionLabel`, `SettingsCard`, `NavTreeHeader`) | `titleMedium` | 16 / w700, `primary` (DD-14) | 16 w500 + bold ידני / 14 w700 |
| כותרת כרטיס / שורה | `titleSmall` | 14 / w600 | 14–16 מעורב, וגם 15 (`fontMD + 1`) |
| טקסט גוף | `bodyLarge` | 16 | 16 |
| טקסט גוף משני / תיאור | `bodyMedium` | **14** | 18 |
| מטא, הערות שוליים, מונים | `bodySmall` | 12 | 12, ו־13 ב־32 מקומות |
| תווית שדה / כפתור | `labelLarge` | 14 / w500 | 14 |
| תווית קטנה (צ'יפ, לשונית) | `labelMedium` / `labelSmall` | 12 / 11 | 10–12 |
| הודעת שגיאה בשדה | `bodySmall` + `cs.error` | 12 | `AppDialog.warning` ‏13 קשיח |
| מונוספייס (נתיב, קיצור מקשים, גרסה) | `AppTextStyles.mono` (יעד) | גופן `monospace` של המערכת. הגודל מסולם ה־slots, ונקבע ב־commit המיישם | — |

**[מחייב]**
- **`fontSize:` אסור בקוד פיצ'ר (DD-02).** מותר רק ב־`lib/theme/` ובציור תוכן הספר (2.4.2). משתמשים ב־`Theme.of(context).textTheme.<slot>`, ובמקרה הצורך ב־`.copyWith(fontWeight:/color:)`. גם `AppTokens.font*` (ו־`fontSM - 1` וכדומה) נשאר בשכבת ה־Theme. עד MIG-05 קוד חדש בוחר את ה־slot הקרוב, גם אם גודלו היום שונה.
- `TextStyle(fontFamily: '…')` ליטרלי אסור. המשפחה נקבעת ב־`AppThemeData` (גופן ממשק) או ב־`AppFonts` (תוכן).
- `AppTextStyles.settingTitle/settingSubtitle` שמורים לשורות הגדרה. לא בונים מהם סגנונות לשימושים אחרים: `NavTreeTile` מקטין את `settingTitle` ל־14 (UI-015).

#### 2.4.2 טיפוגרפיית תוכן הספרים (מערכת נפרדת)

**[מחייב] · קיים** טקסט ספר, מפרשים, קטעי תוצאות ותצוגות מקדימות של קישורים מקבלים גופן, גודל וגובה שורה **מהגדרות הקריאה** (`SettingsState.fontFamily`/`fontSize`/`lineHeight`/`commentators*` ו־`TextDisplayProfile`). הם **לא** כפופים ל־textTheme.

הכללים:
- גדלים יחסיים בתוך תוכן (×0.85 לכותרת מפרש, ‎sup/small ב־HTML) הם חלק מהתוכן ומותרים.
- **הודעות ממשק בתוך אזור התוכן** ("טוען מפרשים…", "אין תוכן זמין", שגיאת טעינה) הן ממשק, ולכן `textTheme`. היום הן מוגדלות לפי גודל הקריאה (UI-066).
- גופני ספר נקבעים דרך `AppFonts` בלבד.
- ההחרגה ב־CI נעשית לפי נתיבים ודפוסים ולא בהערות. הרשימה ב־`CI_ENFORCEMENT.md` §3.6.

### 2.5 טוקנים נוספים

#### 2.5.1 אייקונים
**[מחייב] · קיים** הכללים ב־`docs/agent_ui_reference.md` §1 (otzaria_icons קודם, אחר כך Fluent; בלי Material). אייקון Fluent שמוגדר `matchTextDirection: true` (חיצים ושברונים שמאלה/ימינה, קודם/הבא, יישור טקסט) נכתב ב־`Icon` רגיל עם הגליף של LTR, ו־Flutter מהפך אותו ב־RTL. `RtlIcon` מעביר אייקון כזה כמו שהוא, ומהפך רק את הרשומים בו (UI-023, MIG-11).

**גדלי אייקון [מחייב] (DD-03) · יעד — טרם מומש (MIG-04):**

| טוקן | ערך | שימוש |
|---|---|---|
| `AppTokens.iconXS` | 14 | עץ ניווט, תגיות |
| `AppTokens.iconSM` | 16 | בתוך שדה, כפתור קומפקטי, פעולת שורה |
| `AppTokens.iconMD` | 20 | סרגלים (`BarButton`), תפריטים |
| `AppTokens.iconLG` | 24 | ברירת מחדל של M3 |
| `AppTokens.iconXL` | 48 | מצב ריק |

**[אסור]** גודל אייקון מספרי בקוד פיצ'ר, וטוקן גופן כגודל אייקון. היום זה קורה ב־`meta_chip.dart:50` וב־`details_info_section.dart:86`.

#### 2.5.2 גבהים סטנדרטיים
| רכיב | ערך | מקור | סטטוס |
|---|---|---|---|
| שדה קלט רגיל / קומפקטי | 48 / 36 | `AppInputTokens` | קיים |
| שדה חיפוש slim | 40 | `otzaria_search_field.dart:17` | יעד: לעבור ל־`AppInputTokens` (MIG-16) |
| סרגל עליון רגיל / קומפקטי | 56 / 44 | `app_top_bar.dart` (קשיח) | יעד: לעבור ל־`AppDensity` (DD-10, MIG-06) |
| כפתור סרגל | 40 / 36 | `bar_button.dart` | כנ"ל |
| פריט תפריט | 36 | `AppMenuMetrics` | קיים. במצב קומפקטי צפוף יותר (DD-10, MIG-06) |
| לשונית חלונית | 44 | `AppTokens.panelTabHeight` | קיים |

#### 2.5.3 גבולות
טוקנים הנדסיים שנותנים שם לערך הקיים, בלי שינוי חזותי. **יעד — טרם מומש (MIG-04):**

| טוקן | ערך | שימוש |
|---|---|---|
| `AppTokens.borderThin` | 1 | מסגרת כרטיס, שדה ומפריד |
| `AppTokens.borderFocus` | 2 | טבעת פוקוס ופס פעיל |
| (שם ב־MIG-04) | 1.5 | רווח בין שורות ב־`AppCard.section`, קיים כקבוע פרטי. השם `sectionGap` תפוס לטוקן הסמנטי ב־2.2 |

#### 2.5.4 צלליות והגבהה [מחייב] (DD-12 A) · יעד — טרם מומש (MIG-08)
**היום:** elevation בערכים 0/1/2/3/4/6/8/10/18, וצללים בשקיפויות 0.05–0.22.
**התקן:** מסגרת ולא צל. שלוש רמות בלבד:
- 0: כרטיסים ומשטחים רגילים. כרטיס מקבל מסגרת `outlineVariant` בלי צל.
- 1: סרגל עליון וחלונית מוצמדת.
- 3: תפריט, tooltip וחלונית צפה.

הדיאלוג נשאר לפי M3. כל הרמות דרך `AppTokens.elevation*` (קיימים היום `elevation1`=1 ו־`elevation2`=3) ו־`AppShadows`. ה־scrim אחד, עדין כמו היום בדיאלוגים (2.1.1).

#### 2.5.5 תנועה
| טוקן | ערך | סטטוס |
|---|---|---|
| `AppTokens.animFast` | 150ms | קיים, 16 שימושים |
| `AppTokens.animPanelOpacity` | 200ms | קיים |
| `AppTokens.animNormal` | 250ms | קיים |
| `AppTokens.animPanelSlide` | 300ms | קיים |
| `AppTokens.curveStandard` / `curveEnter` / `curveExit` | `Curves.easeInOut` (44 שימושים) / `easeOutCubic` לכניסה. הערכים הקיימים | יעד — טרם מומש (MIG-04) |
| `AppTokens.hoverPreviewDelay` | 280ms (היום קשיח ×6) | יעד — טרם מומש (MIG-04) |

**[מחייב]**
- בקוד יש כ־90 משכי אנימציה קשיחים. בקוד חדש משך אנימציה של ממשק הוא טוקן.
- **הפחתת תנועה (DD-21 A) · יעד — טרם מומש (MIG-04):** כל משך של אנימציית ממשק עובר דרך `AppMotion.duration(context, AppTokens.animNormal)`, שמחזיר `Duration.zero` כש־`MediaQuery.disableAnimationsOf(context)` פעיל. כך נכבות פתיחת חלונית והחלפת לשונית. אנימציה שמעבירה מידע, כמו התקדמות, נשארת. היום אף מקום באפליקציה לא בודק זאת (UI-028).

#### 2.5.6 שטחי לחיצה [מחייב] · קיים
- מינימום 40×40 בדסקטופ, ו־48×48 במגע (`MaterialTapTargetSize.padded`).
- כפתורים של 28×28 (ניווט תוצאות, סרגל מפרשים) ו־32×32 (עין בהגדרות צורת הדף) מתחת לסף, ורשומים בביקורת.
- אפשר לצייר אייקון קטן בתוך שטח לחיצה גדול יותר. מקטינים את השטח רק כשהרכיב הוא חלק משורה צפופה שיש לה חלופה במקלדת.

#### 2.5.7 מגבלות רוחב
| טוקן | ערך | סטטוס |
|---|---|---|
| `LayoutConstraints.panelContentMaxWidth` | 860 | קיים |
| רוחבי דיאלוג | `AppDialogSize.small` ‏400 / `medium` ‏560 / `large` ‏720 / `full` (DD-07). היום 400, 440, 460×4, 480, 500, 540, 560, 620, 640, 680, וגם 50%/80%/90%/95% | יעד — טרם מומש (MIG-10) |
| חלונית צד | **340**, טוקן אחד (DD-28). היום 340 ב־`AdaptiveSidePane` ו־`kSidePanelWidth` כפול | יעד — טרם מומש (MIG-14) |
| רוחב תוכן מינימלי ליד חלונית | 500 (`kMainPanelMinWidth`) | עובר לאותו קובץ טוקנים (MIG-14) |

#### 2.5.8 צפיפות: קומפקטי ורגיל [מחייב] (DD-10 B) · יעד — טרם מומש (MIG-06)
**היום:** ההגדרה `compactMenuMode` נקראת ישירות 68 פעמים, לעתים ב־`context.read` בתוך `build`, ולכן לא מתעדכנת מיד. `AppMenuMetrics` מחזיר ערכים זהים בשני המצבים, ו־`VisualDensity.adaptivePlatformDensity` פועל במקביל.
**התקן:** `ThemeExtension<AppDensity>` אחד שנבנה ב־`AppThemeData` מתוך ההגדרה ומכיל:
- גובה סרגל, גובה שדה וגודל כפתור סרגל;
- גודל אייקון בסרגל ו־menu metrics. **התפריטים צפופים יותר במצב הקומפקטי** (הערכים ב־commit עם תמונות);
- `isCompact`.

שם ההגדרה למשתמש נשאר **"צפיפות ממשק"**. רכיבים קוראים `AppDensity.of(context)`. **[אסור]** בקוד חדש לקרוא את `context.read<SettingsBloc>().state.compactMenuMode` מתוך רכיב תצוגה.

---

## 3. קטלוג הרכיבים המשותפים (ב.3)

**כלל השימוש [מחייב]:** בכל תפקיד שמופיע בקטלוג משתמשים ברכיב שהקטלוג מציין. רכיב שמסומן **(יעד)** עוד לא קיים. עד שיתווסף, משתמשים ברכיב הקיים שמצוין לצידו, ולא בונים עותק מקומי.

**כלל עיצוב ה־API [מחייב]** (חל על כל רכיב חדש ועל כל שינוי חתימה; פירוט ב־`MIGRATION_PLAN.md` §7.3):
1. וריאנטים בנויים כ־named constructors או כ־enum סגור, למשל `ActionButton.recommended`. אין בוליאנים שמשנים את המראה.
2. אין פרמטרים של צבע, ריפוד, `TextStyle` או `shape` שנועדו לעקוף את התקן. פרמטר כזה מותר רק כשהוא חלק מהתפקיד עצמו, למשל `MetaChip(tone:)`.
3. אין `dynamic`. היום `AppDialog.title`, `SettingsCard.title` ו־callbacks של `ItemsListView` מוגדרים כ־`dynamic`.
4. רכיב משותף לא מייבא קוד פיצ'ר: לא settings bloc, plugins registry, tabs או models של ספרים. את הצפיפות הוא מקבל מ־`AppDensity`, ונתוני תחום מגיעים כפרמטרים.
5. פרמטר שאין לו אף קורא נמחק במסגרת ה־PR שמשנה את הרכיב.

### 3.1 דיאלוגים

#### 3.1.1 מצב קיים (תמצית)
בקוד יש **8 מסגרות דיאלוג** (UI-001, UI-034):
- `AppDialog` (`AlertDialog`)
- `AppDialogFrame`
- `AppCustomContentDialog`
- `ListDialogFrame`
- `InputDialog`
- `SelectionDialog`
- `AdPopupDialog`
- `ZipExtractionProgressDialog`

בנוסף יש כ־27 דיאלוגים שבנויים על `AlertDialog` או `Dialog` גולמיים, ושלושה ממשקי "אישור" שחופפים זה לזה:
- `showTwoActionsDialog`
- `showWarningDialog`
- `showConfirmationDialog`

ההתנהגות (Escape, Enter, שינויים שלא נשמרו) שונה בין המסגרות. ב־`DialogKeyboardNavigator` יש באג מוכח: הוא בולע Enter וחיצים מכל רכיב בתוך הדיאלוג.

#### 3.1.2 משפחות הדיאלוג — התקן [מחייב] (DD-07 B, DD-16 A) · יעד — טרם מומש (MIG-10, MIG-17, MIG-18)

**[מחייב]** רצועת כותרת (`AppDialogHeader`) ותג אייקון **בכל** דיאלוג, כולל `small` (DD-07 B). האייקון מתאר את הפעולה. אם אין לה אייקון שאומר משהו, משתמשים באייקון של משפחת הדיאלוג. `AppDialogFrame(size:)` מחליף את `AppCustomContentDialog` ואת `ListDialogFrame`. אייקוני המשפחות: `AppDialogIcons` (מידע, אישור, אזהרה, קלט, בחירה, התקדמות).

**[מחייב]** ב־`small` אין X (DD-07, השלמה 2.11): סוגרים ב״ביטול״ (או בכפתור הסגירה של הדיאלוג), ב־Escape או בלחיצה בחוץ. `AppDialogFrame` קובע את זה לפי הגודל. מ־`medium` ומעלה ה־X נשאר.

**[מחייב]** (DD-07, השלמה שלישית 2.11): שאלה קצרה עם שלוש או ארבע פעולות (טיוטת הערה, התנגשויות בייבוא) היא `medium`, כדי שכל הכפתורים יהיו בשורה אחת, ולכן יש בה X. גוף כל דיאלוג בצבע הדיאלוג (`surfaceContainerHigh`), גם בדיאלוגי התוכן שהיו `AppCustomContentDialog`. דיאלוג עם `height` מפורש מוגבל לגובה החלון ולא ל־85%.

| משפחה | רכיב | מתי | כותרת | תג אייקון | X | גודל / גובה | גלילה | פעולות |
|---|---|---|---|---|---|---|---|---|
| **אישור פשוט** | `showTwoActionsDialog` | שאלת כן/לא שאינה הרסנית | רצועה | כן | לא | `small` (400), לפי התוכן | לא | ביטול (`neutral`) + אישור (ראשי) |
| **אזהרה** | `showWarningDialog` | פעולה הרסנית או בלתי הפיכה | רצועה, טון שגיאה | כן, אזהרה בטון שגיאה | לא | `small` | לא | ביטול (מוקד) + אישור (`warning`) |
| **מידע** | `showSingleActionDialog` | הודעה שדורשת קריאה, כשאין די ב־`UiSnack` | רצועה | כן | לא ב־`small`, כן ב־`medium` | `small`/`medium` | אם התוכן ארוך | סגור (ראשי) |
| **קלט** | `showInputDialog` | שדה טקסט אחד | רצועה | כן | לא | `small` | לא | ביטול + אישור. Enter בשדה = אישור |
| **בחירה** | `showSelectionDialog` | בחירת פריט אחד מרשימה | רצועה | כן | לא | `small` × עד 60% גובה | רשימה | ביטול. Enter על פריט = בחירה |
| **בחירה בין N אפשרויות** | `showChoiceDialog` (יעד, MIG-10) | 3+ פעולות שוות, למשל "טקסט / Word / ביטול" | רצועה | כן | לא | `small` | לא | N ראשיות/ניטרליות + ביטול |
| **בינוני (טופס, תוכן מורכב)** | `AppDialogFrame(size: medium)` | טופס של כמה שדות, הגדרה ממוקדת, עורך ההערות (השלמה 2.11), שאלה עם 3–4 פעולות | רצועה | כן | כן | 560, לפי התוכן עד 85% | `PanelScrollableContent` (יעד: מובנה) | `Wrap` בסוף הכותרת: משני → ראשי |
| **גדול / "מסך כדיאלוג"** | `AppDialogFrame(size: large)` | רשימות (סימניות, היסטוריה, גרסאות), ניהול | רצועה + מונה ב־`trailing` | כן | כן | 720, **לפי התוכן עד 85%** (היום 50%×80% קבוע). רשימה עם שורת חיפוש: **85% קבוע**, כדי שהחיפוש לא יזוז בזמן ההקלדה (השלמה 2.11) | מובנה | אופציונלי |
| **עם לשוניות** | `AppDialogFrame(size: large, tabs:)` (יעד) | דיווח שגיאה, הגדרות מרובות | כנ"ל + `TabBar` | כן | כן | 720, בגובה קבוע. דיווח שגיאה: 560, ועם עורך תיקון 660 או 70% מהחלון (השלמה 2.11) | לכל לשונית | |
| **תהליך / התקדמות** | `runWithBlockingProgress` (יעד, MIG-10) | פעולה חוסמת של יותר מ־~300ms | רצועה | כן | לא (או "בטל" אם התהליך ניתן לביטול) | `small` | — | בטל (אופציונלי) |
| **מסך מלא** (הדפסה, עורך) | `AppDialogFrame(size: full)` (יעד) | תצוגה מקדימה עם חלונית הגדרות. עורך ההערות אינו כאן: `medium` (השלמה 2.11) | רצועה + פקדים בתחילת הכותרת, לפני התג (הדפסה, השלמה 2.11) | כן | כן | 100% פחות שוליים | | |

**חוזה התנהגות של כל המשפחות [מחייב] (DD-08 A) · יעד — טרם מומש (MIG-09):**

| נושא | התקן |
|---|---|
| **Escape** | סוגר תמיד. אם יש שינויים שלא נשמרו, מוצגת קודם שאלת אישור. Escape לא בולע מקשים מרכיבים פנימיים, ונשען על `DismissIntent` של ה־route ועל `PopScope`. |
| **Enter** | כשהפוקוס בשדה טקסט חד־שורתי, Enter מפעיל את **הפעולה הראשית** אם היא זמינה. בשדה רב־שורתי Enter מוסיף שורה. כשהפוקוס על כפתור או על פריט ברשימה, Enter מפעיל **את הרכיב הממוקד**: על "ביטול" הוא מבטל. |
| **חיצים** | לא נבלעים ברמת הדיאלוג. ניווט בין כפתורים נעשה ב־Tab, או בחיצים רק בתוך `FocusTraversalGroup` של שורת הפעולות. |
| **barrier** | לחיצה מחוץ לדיאלוג סוגרת אותו, אלא אם יש שינויים שלא נשמרו או תהליך פעיל. |
| **שינויים שלא נשמרו** | פרמטר אחד, `isDirty`/`onDismissRequest`, ב־`AppDialogFrame` וב־`AppDialog`, שחל על **כל** דרכי היציאה: X, ביטול, Escape ו־barrier. היום `hasUnsavedChanges` חוסם רק את ה־barrier. |
| **פוקוס פותח** | השדה הראשון. בדיאלוג אזהרה: כפתור הביטול. |
| **פוקוס בסגירה** | חוזר לרכיב שפתח את הדיאלוג (`showDialogUntilTornDown` / `registerDialogFocusRestorer`). |
| **Semantics** | ל־route יש `label` עם כותרת הדיאלוג. `AppDialogFrame` מספק את זה היום, ו־`Dialog` גולמי לא. |
| **מובייל (<600, DD-16)** | `small`/`medium` ברוחב מלא פחות 16, ו־`large`/`full` במסך מלא עם X. הרצועה נשארת. ב־`small` אין X, ומ־`medium` ומעלה ה־X הוא שטח מגע של 48. |
| **פתיחה** | תמיד דרך `showDialogUntilTornDown` (או העזרים שעוטפים אותו, כמו `showTwoActionsDialog`), כדי לשמור על הכיווניות של הפותח ועל ניקוי מסודר בסגירה. בהגדרות: `settingsDialogBuilder`. |

**[אסור]** בקוד חדש:
- `AlertDialog(`, `Dialog(`, `SimpleDialog(` מחוץ ל־`lib/widgets/dialogs/`.
- `showDialog(` עם builder שמחזיר אחד מהם.
- `Navigator.of(context).pop()` על route שנפתח ב־root navigator. משתמשים ב־handle שהעזר מחזיר.

### 3.2 כפתורים ופעולות

| תפקיד | רכיב | הערות |
|---|---|---|
| ראשי | `ActionButton.recommended` | אחד לכל קבוצת פעולות |
| משני / ניטרלי, **וביטול בדיאלוג** | `ActionButton.neutral` (tonal) | DD-09 A. קיים (18 מופעים) |
| פעולה משנית שקטה שאינה ביטול ("דלג", "איפוס" בתוך פאנל) | `ActionButton.ghost` | ביטול ב־ghost (9 מופעים) עובר ל־`neutral` (MIG-17, MIG-19) |
| מסוכן (אישור מחיקה) | `ActionButton.warning` | רק בתוך דיאלוג אזהרה או אחרי אישור. כפתור "מחק" ראשוני ברשימה הוא `neutral` או אייקון. |
| אייקון בלבד, כללי | `AppIconButton(size: small\|medium\|large)` (MIG-13): עטיפה דקה על `IconButton` שמחייבת `tooltip`. אייקון 16/20/24 מ־`AppTokens.icon*`, ריבוע האייקון ועוד 16 (ועוד 12 בצפיפות קומפקטית), עגול (DD-04). `isSelected` צובע ב־`primary` | הוסבו השכבה המשותפת, שורת הכותרת ועמודת הכרטיסיות. בפיצ'רים נשארו כ־190 `IconButton` גולמיים (UI-004, UI-030) |
| אייקון בתוך שדה / בסרגל צר | `SquareIconButton.field` / `.toolbar` | קיים |
| פעולת סרגל | `BarButton.icon` / `.text` | צפיפות מ־`AppDensity`. צורה 8, בלי גלולה (DD-04, MIG-13) |
| פעולה מפוצלת | `BarSplitButton` | קיים. צורה: גלולה, חריג מאושר ל־״8 בלבד״ (DD-04, השלמה 2.11) |
| פעולת רשימה / שורה | `AppIconButton(size: small)`. בשורת הגדרה: `SettingsActionTile` actions | אין hover כפול על השורה |
| קומפקטי | אותם רכיבים עם `AppDensity` | אין רכיב "קומפקטי" נפרד |

**מצבים [מחייב]:**
- **hover/pressed/focus:** מגיעים מערכת הנושא (`_hoverButtonStyle`). לא מגדירים אותם מקומית.
- **disabled:** `onPressed: null`. `SecondaryIconButton` ו־`PrimaryIconButton` לא מאפשרים זאת היום, וזה ממצא בביקורת.
- **loading:** `ActionButton(isLoading:)`. יעד: לשמור על רוחב הכפתור ולהוסיף `Semantics(liveRegion)` "טוען".

**מדיניות Tooltip [מחייב]:** לכל כפתור שמכיל אייקון בלבד יש `tooltip`. הטקסט שלו הוא גם השם הנגיש. אם יש קיצור מקשים, הוא מופיע ב־tooltip בצורה `"הדפסה (Ctrl+P)"`, בעזרת `ShortcutHelper.formatShortcutForDisplay`. כפתור עם תווית טקסט לא צריך tooltip.

**[אסור]**
- `TextButton(`, `FilledButton(`, `OutlinedButton(`, `ElevatedButton(` מחוץ ל־`lib/widgets/controls/`.
- `IconButton` בלי `tooltip`.
- `IconButton` בתוך `ResponsiveActionBar` במקום `BarButton`.

### 3.3 שדות וטפסים

| תפקיד | רכיב | הערות |
|---|---|---|
| שדה טקסט | `RtlTextField` + `InputDecoration` מערכת הנושא | `TextField` גולמי אסור (נאכף בבדיקה) |
| שדה מספרי | `RtlTextField(keyboardType: number, inputFormatters)` | הספרות תמיד LTR |
| חיפוש | `OtzariaSearchField`. בחלונית ניווט: `NavPanelCollapsibleSearch` | אייקון לפי היקף החיפוש (`agent_ui_reference` §1). כפתור ניקוי אחד, `OtzariaSearchClearButton` (UI-138, MIG-16) |
| בחירה אחת מרשימה נפתחת | `AppDropdownField` | `decoration.labelText` מוצג כתווית `labelMedium` מעל הכפתור ונקרא יחד עמו בקורא מסך (MIG-11; אושר בהשלמה 2.11: תווית מעל השדה). בשדות בסרגל, שאין בהם מקום מעל: `semanticLabel` בלבד (שם נגיש ו־tooltip, בלי תווית גלויה). |
| 2–4 אפשרויות | `AppSegmentedControl`. בהגדרות: `SettingsSegmentedTile` | קיים. גם בורר מצב החיפוש (DD-31a) |
| בחירה מרובה (פילטר) | `FilterChip` של Material + `chipTheme` (DD-13: פינות 8, תווית `labelMedium` 12) | `FilterChipsSelector` / `compactFilterChips`; `ChoiceChip` לבחירה אחת |
| Checkbox | `Checkbox` של Material + `checkboxTheme` (יעד, MIG-08) | השורה כולה לחיצה (`CheckboxListTile` או `InkWell`) |
| Switch | `SettingsSwitchTile`. מחוץ להגדרות: `Switch` + `switchTheme` (יעד, MIG-08) | `CustomSwitch` יוסר כשיתווסף `switchTheme` (MIG-26) |
| Slider | `SettingsSliderTile` | `SliderTheme` מקומי אסור |
| תאריך | `showDatePicker` + `datePickerTheme` | קיים (#3794) |
| שגיאת אימות | `InputDecoration.errorText` | לא טקסט אדום שנבנה ידנית מתחת לשדה |
| קבוצת שדות | `SettingsCard`, או `ListDialogCard` בתוך דיאלוג | |
| תווית מעל שדה | `InputDecoration.labelText` | לא `Text` נפרד עם `TextStyle` מקומי |

### 3.4 כרטיסים ורשימות

| תפקיד | רכיב | הערות |
|---|---|---|
| כרטיס מידע | `AppCard(tone: normal\|primary\|error)` | `Card(` גולמי אסור (נשארו 3: אודות, פופאפ ההודעות, לוח השנה). מסגרת, בלי צל (DD-12). `primary`/`error` על `primaryContainer`/`errorContainer`, והטקסט והאייקונים בצבע ה־on. כרטיס הרשימה בדיאלוג הוא `AppCard` |
| קבוצת שורות בכרטיס | `AppCard.section(children:)` | בלי `selected`/`padding`/`margin`. מפריד = רווח שקוף |
| כרטיס תוצאה (חיפוש וכלים) | `ResultCardFrame` (DD-11 A, MIG-20): צבע כרטיס, מסגרת `outlineVariant`, ריפוד `AppTokens.cardPadding` (12) ומרווח `AppTokens.listItemGap` (8) בין תוצאות | בכלים דרך `ToolResultCardShell` (טקסט נבחר ולחיצה). מספר התוצאה: `SearchResultRankBadge`. עוד לא על המסגרת: כרטיסי איתור מקורות ורשימת תוצאות החיפוש במפרשים |
| היסטוריה, סימניות ונתונים חוזרים קצרים | רשימה פשוטה, **בלי כרטיס** (DD-11): `ItemsListView` — שורות על רקע המשטח וקו `subtleDivider` בין שורות של אותה קבוצה | גם הסימניות המרוכזות. הערות אישיות נשארות כרטיסי מידע (`AppCard`, ריפוד `cardPadding`) |
| כרטיס עם פעולות | `AppCard` + שורת `ActionButton`/`AppIconButton` בסוף | |
| כרטיס מתרחב | `ExpandableCard`. בהגדרות: `ExpandableSection` | חץ: `ExpandingChevron(style: accordion\|tree)` עם `Semantics(expanded:)` מובנה (DD-27 A). עץ (`NavTreeTile`, כותרות המפרשים, רשימת הקישורים): חץ לכיוון הקריאה, למטה כשפתוח. אקורדיון (`ExpandableSection`): חץ למטה, למעלה כשפתוח. כרטיסי התיקיות בספרייה (`ExpandableCard`) הם אקורדיון, כמו היום (השלמה 2.11). מנגנון ההרחבה האחד עוד לא אוחד: `ExpandableCard` משמש רק אותם |
| שורת הגדרה | `SettingsSwitchTile`, `SettingsDropdownTile`, `SettingsSegmentedTile`, `SettingsPathTile`, `SettingsSliderTile`, ו־`SettingsActionTile` (.text/.path/radioOption) לשאר, בתוך `SettingsCard` (MIG-15) | בין כרטיסים בלשונית: `kSettingsCardSpacing` (16, ועם ריפוד הכותרת 40). כרטיס שלפעמים לא מוצג: `SettingsCard(spacedAbove: true)`. עדיין נבנים ידנית: ההדפסה, חלונית צורת הדף, ShortcutDropDownTile, ColorPickerTile ועוד (UI-006) |
| פריט רשימה | `ListTile` + `listTileTheme` (יעד, MIG-05), או `NavTreeTile` בחלוניות | |
| פריט ניווט | `NavRailItem`, `SidebarNavItem`, `NavTreeTile` | |
| תגית / מונה | `MetaChip(tone: neutral\|primary\|error\|warning\|success, size: regular\|small, tooltip:)` (DD-13 A). תווית `labelMedium` 12 (`small`: `labelSmall` 11), צורה 8. `success` בגוון החום הנייטרלי (`secondaryContainer`), לא ירוק. `neutral` ב־`surfaceContainerHighest` (השלמה 2.11) | לא נבנה צ'יפ מקומי. נשארו: `SearchResultSourceTag`, `PluginDevBadge`, `PluginUpdateChip`, תג הגימטריה |
| תג אייקון | `ListIconBadge` / `AppDialogIconBadge` | ריבוע מעוגל 8 בשניהם (DD-04, MIG-13). היום תג הדיאלוג עגול |
| כותרת מקטע | `AppSectionLabel` (DD-14 A): `titleMedium`, `primary`, כותרת לקורא מסך. חריג: בדיאלוג החיפוש ובאיתור המקורות הכותרות הקטנות (13, w600, `primary`) נשארות (השלמה 2.11) | `SettingsCard` מצייר את כותרתו דרכו |
| מפריד שורות בדיאלוג | `listDialogRowDivider` | |

**[מחייב]** רשימה ארוכה (יותר מכ־50 פריטים) נבנית עם `ListView.builder` או `SliverList`. לא מחשבים סגנון בכל פריט: את `Theme.of` קוראים פעם אחת מחוץ ל־builder.

### 3.5 משוב ומצבים

| מצב | רכיב | הערות |
|---|---|---|
| טעינה, מסך או חלונית | `LoadingIndicator`, ועם הודעה `LoadingIndicator(message:)` | עוד כ־70 `CircularProgressIndicator` גולמיים |
| טעינה, inline | `LoadingIndicator.inline` (‏16px, ‏stroke 2) | עוד כ־10 עותקים מקומיים |
| טעינה, שלד (skeleton) | `SkeletonLines` (רוחב כחלק מהמקום שקיבלו, `FractionallySizedBox`) | |
| ריק | `OtzariaEmptyState` (`isCompact` בחלונית) | |
| ריק "גדול" (ספרייה ריקה, הגדרה ראשונית) | `OtzariaEmptyState.large` (DD-31d) | |
| שגיאה | `OtzariaErrorState(actions: [נסה שוב])` | לא `Text` אדום |
| הצלחה / הודעה קצרה | `UiSnack.show(<Module>Messages.x)` (למשל `SettingsMessages`) | מחרוזות מקטלוג בלבד (נאכף) |
| באנר בתוך המסך | `AppInfoBanner(tone: info/warning/error/success, title:)` (DD-24, MIG-12). `warning` מטוקני האזהרה, `success` בגוון הנייטרלי הקיים. `info` על רקע נייטרלי `surfaceContainerHighest`, אייקון `primary` וטקסט רגיל (השלמה 2.11). בלי מסגרת, כותרת `titleSmall`, הודעה `bodyMedium` (אושר בהשלמה 2.11) | נשארו הבאנרים ברוחב מלא בתוצאות החיפוש |
| תוכן לא זמין | `OtzariaEmptyState` עם הסבר | |
| פעולה מתמשכת | `ActionButton(isLoading:)`, או `runWithBlockingProgress` (יעד) | |
| אישור מחיקה | `showWarningDialog` | כולל מחיקת קבוצת סימניות או היסטוריה (DD-31c, MIG-20). 3 סגנונות שונים היום |

**[מחייב]** `UiSnack` אינו משמש למידע קריטי. הודעות `UiSnack` לא מוקראות היום לקורא מסך, והתיקון נעשה בתוך `UiSnack` עצמו (MIG-11).

### 3.6 מסכים ופריסות

| דפוס | רכיב | הערות |
|---|---|---|
| מעטפת מסך לוח (הגדרות, ספרייה, כלים) | `AppTopBar` + רקע `panelBackground` + `LayoutConstraints.panelContentMaxWidth` | אזור "כלים ועבודה" (DD-18) |
| מעטפת כלי | `ToolScaffold` (`lib/widgets/layout`): סרגל עם שדה החיפוש, מסננים, גוף ושורת תחתית; הסרגל נשאר בטעינה ובשגיאת טעינה (`loading`, `loadError` + `onRetry`); קיצור "חפש בחלון" | מבנה ידני, או ספינר במקום המסך כולו בזמן טעינה |
| אזור תוכן | `PanelScrollableContent` / `CenteredScrollableState` | |
| כותרת מסך | `AppTopBar(center:)` עם `AppTopBar.titleStyle(context)` / `subtitleStyle(context)` | `titleStyle` קשיח יעבור ל־`textTheme.titleLarge` (MIG-05) |
| סרגל פעולות | `ResponsiveActionBar` + `ActionButtonData` | פריטים דרך `BarButton` בלבד |
| חלונית ניווט | `NavSidePanel` | אזור "חלוניות לצד הקריאה" (DD-18). נסגרת אחרי מעבר רק כשהיא מכסה את התוכן (DD-26) |
| חלונית משנית או צפה | `AdaptiveSidePane` / `ContextOverlayPanel` | DD-28 A: רוחב 340 מטוקן אחד, הגבהה לפי DD-12, רקע לפי DD-18 (יעד, MIG-14) |
| Split pane | `SplitPaneView` (tabs) | |
| מסך הגדרות | `SettingsTabScrollView` + `SettingsCard` | |
| מסך תוצאות | `ResultCardFrame`; מעל תוצאות כלי: `ToolResultsHeader(label, leading, child)` | אזור התוצאות על `panelBackground`, ועץ הסינון על `navPanelBackground` (DD-18, UI-143) |
| מסך קריאה | `TextBookScreen` / `PdfBookScreen` על `readerBackground` | אזור "קריאה": בלי כרטיסים סביב טקסט הספר, צבע רק לתוכן |

**[מחייב]** מעדיפים קומפוזיציה: מעטפת מסך מקבלת `child` ולא עשרות דגלים. מסך שלא מתאים לאף דפוס בונה פריסה משלו, אבל רק מרכיבים מהקטלוג.

---

## 4. ארכיטקטורת UI וגבולות אחריות (ב.4)

### 4.1 השכבות והמיפוי לתיקיות קיימות

המבנה הקיים כבר מממש את רוב החלוקה. **אין צורך בתיקיות חדשות**, רק בגבולות מוגדרים ונאכפים.

| # | שכבה | תיקייה קיימת | מותר | אסור |
|---|---|---|---|---|
| 1 | **Foundation** | `lib/theme/app_tokens.dart`, `app_colors.dart`, `app_input_tokens.dart`, `layout_tokens.dart`, `app_seed_colors.dart` | קבועים (`static const`): ריווח, רדיוס, גודל, משך, נקודות שבירה, פלטות תוכן | `BuildContext`, ייבוא Widgets, לוגיקה |
| 2 | **Theme** | `lib/theme/app_theme_data.dart`, `app_surfaces.dart`, ו־ThemeExtensions `AppSurfaceColors`/`AppDensity` (DD-19, יעד) | מיפוי של seed, בהירות וצפיפות לתפקידים ול־component themes. הגדרת שקיפויות ומצבים | קריאה ל־Bloc או ל־Settings. החלטות של פיצ'ר מסוים |
| 3 | **Shared Components** | `lib/widgets/**`, `lib/settings/widgets/**` (רכיבי שורת הגדרה), `packages/otzaria_context_menu` | רכיבים כלליים שמקבלים נתונים כפרמטרים ולוקחים סגנון מערכת הנושא | ייבוא מ־`lib/<feature>/`, קריאה ישירה ל־`SettingsBloc`, `Settings.getValue` או repositories, ומחרוזות תחום |
| 4 | **Layout Patterns** | `lib/widgets/layout/`, `lib/widgets/navigation/` | מעטפות מסך, חלוניות, סרגלים ופריסה רספונסיבית | ידע על סוג תוכן מסוים |
| 5 | **Feature Widgets** | `lib/<feature>/view/widgets/` | הרכבה של רכיבים משותפים לרכיב ייחודי, וגאומטריה שנגזרת מהתוכן | הגדרת צבע, גופן, רדיוס או ריווח שאינם טוקן. עותק של רכיב משותף |
| 6 | **Application Screens** | `lib/<feature>/view/*_screen.dart` | הרכבת מסך, חיבור ל־Bloc וניווט | IO, גישה ל־DB, `Settings.setValue`, חישובים כבדים ב־`build` |
| 7 | **Business Logic** | `lib/<feature>/bloc/`, `repository/`, `services/` | מצב, נתונים ו־IO | ייבוא `material.dart` (חוץ מ־`Color` כנתון) |

### 4.2 החלטות לפי שכבה

- **ערך עיצובי חדש** (גודל, צבע, משך): מוסיפים לשכבה 1 או 2, בתוך אותו PR שמשתמש בו.
- **וריאנט של רכיב קיים:** מוסיפים בשכבה 3 כ־named constructor. אם הווריאנט משמש פיצ'ר אחד בלבד, הוא נשאר בשכבה 5.
- **רספונסיביות:** נקודת שבירה כללית (סוג החלון) נקבעת ב־`LayoutBreakpoints`. החלטה שתלויה ברוחב הזמין לרכיב מתקבלת עם `LayoutBuilder` בתוך הרכיב, וקבוע הסף שלה מוגדר כ־`static const` עם שם בתוך אותו רכיב (ראו סעיף 5).
- **התנהגות** (Escape, פוקוס, dirty) של משפחת רכיבים מוגדרת בשכבה 3 ולא בכל מסך בנפרד.

### 4.3 הפרות קיימות שידועות (לצורך תכנון)

הפירוט המלא ב־UI_AUDIT, בקטגוריה `separation-of-concerns`.

**רכיבים משותפים שמייבאים פיצ'רים (MIG-14):**
- `ActionButton` → `SettingsBloc`
- `AppTopBar` → `tabs/view/pane_drag_handle`
- `OtzariaSearchField` → plugins registry
- `ItemsListView` → `models/books.dart`
- `NavSidePanel` → `Settings.getValue`

**מסכים שמערבבים IO ולוגיקה עם בניית תצוגה:**
- `text_book_screen.dart` (3795 שורות)
- `error_report_dialog.dart` (1746)
- `system_settings_tab.dart` (1728)
- `search_dialog.dart` (2306 אחרי #3794)
- `find_ref_dialog.dart` (1961)
- `library_browser.dart` (3041)
- ה־`build` של `page_shape_screen.dart` לבדו הוא כ־770 שורות

**[מחייב] (DD-30 B)** PR שנוגע בקובץ כזה לא מוסיף לו IO או לוגיקה. אין PR פירוק נפרד מראש: הפירוק נעשה **בתוך ה־PR של ההסבה שזקוק לו**, כ־commit נפרד שמשמר התנהגות (עם בדיקות characterization), **לפני** ה־commit שמשנה את המראה. השיוך לכל קובץ ב־`MIGRATION_PLAN.md` §6 (MIG-25).

---

## 5. פריסה רספונסיבית (ב.5)

### 5.1 נקודות השבירה הכלליות
`LayoutBreakpoints`: ‏`compact < 600`, ‏`medium < 840`, ‏`expanded < 1200`, ומעל זה `large`. הערכים עקביים עם M3 ונשארים **[מחייב] · קיים**.

**המצב היום:**
- `LayoutBreakpoints` מופיע רק ב־8 קבצים.
- יש 32 השוואות רוחב לערכים קשיחים:
  - 520 ×7 (סף "דיאלוג צר" שלא מוגדר כטוקן)
  - 560 ×4, 600 ×4, 800 ×3, 720 ×2, 700 ×2, 400 ×2
  - ערכים בודדים: 270, 290, 360, 392, 620, 760, 1100, 1400

**[מחייב] (DD-15 A):** סף "דיאלוג צר" 520 מוחלף ב־`LayoutBreakpoints.compact` (600). דיאלוגים בחלון ברוחב 520–600 עוברים לפריסה הצרה. **יעד — טרם מומש (MIG-21).**

### 5.2 שני סוגי החלטות [מחייב] (DD-15 A)
1. **סוג החלון** (window class): ניווט צדדי מול ניווט תחתון, דיאלוג במסך מלא מול דיאלוג צף, מספר עמודות בדף הבית. נקבע דרך עזר יחיד, `WindowClass.of(context)` → `compact|medium|expanded|large` (יעד, MIG-21), לפי `MediaQuery.sizeOf(context).width` מול `LayoutBreakpoints`.
2. **רוחב זמין לרכיב:** אם שורה גולשת לשתי שורות, אם מונה מוצג, אם התווית הופכת לאייקון. נקבע **רק** עם `LayoutBuilder`/`constraints`, כי הרכיב יכול לשבת בחלונית צרה בתוך חלון רחב. הסף הוא קבוע עם שם ברכיב, למשל `static const _iconOnlyBelow = 560.0`.

**[אסור]**
- `MediaQuery…size.width` להחלטה שתלויה במקום שהרכיב מקבל. דוגמאות היום: skeletons, רוחב חלונית צורת הדף, ידית `PanelOpenHandle`.
- החלטת פריסה לפי `Platform.isAndroid` או לפי orientation, כשהשאלה האמיתית היא רוחב. דוגמאות: סגירת חלונית ניווט אחרי מעבר (DD-26: נסגרת רק כשהיא מכסה את התוכן), שורת כרטיסיות שנייה בשורת הכותרת.
- מספר קסם להשוואת רוחב בלי שם.

### 5.3 תרחישים נתמכים
| תרחיש | דרישה |
|---|---|
| מסך רחב (≥1200) | תוכן לוח מוגבל ל־860 וממורכז. חלוניות מוצמדות |
| מחשב נייד (840–1200) | כמו רחב. חלונית צד אחת מוצמדת לכל היותר |
| טאבלט (600–840) | חלוניות צפות עם scrim. דיאלוג `large` במסך מלא |
| טלפון (<600) | ניווט תחתון. דיאלוגים לפי גודלם (DD-16, 3.1.2). שורות הגדרה בעמודה |
| חלון צר במחשב (420–600) | **כמו טלפון אבל עם עכבר.** שטחי הלחיצה נשארים לפי דסקטופ. החלון המינימלי הוא 420×400 |
| חלוניות מפוצלות | כל חלונית מחליטה לפי ה־constraints שלה ולא לפי החלון |
| שינוי גודל בזמן ריצה | אין מצב שמחושב פעם אחת ב־`initState` לפי רוחב. רוחב שמור נשמר **כיחס** ולא בפיקסלים |
| הגדלת טקסט | ראו 6.3 |

---

## 6. RTL, עברית ונגישות (ב.6)

### 6.1 כיווניות [מחייב]
- **הכיווניות גלובלית:** `Locale('he','IL')`. לא מוסיפים `TextDirection.rtl` ל־`Text`. כן מוסיפים `TextDirection.ltr` לתוכן שהוא LTR מטבעו: נתיב, URL, דוא"ל, גרסה, hash ומזהה.
- **Directional APIs בלבד:** `EdgeInsetsDirectional`, `AlignmentDirectional`, `PositionedDirectional`, `BorderRadiusDirectional`, `start`/`end`.
  - אסור: `left`/`right` ו־`Alignment.centerLeft`.
  - היום יש 42 שימושים ב־`Alignment.left/right`, 57 ב־`fromLTRB` ו־14 ב־`only(left/right)`. חלקם תקינים (גאומטריית ציור, ערכים סימטריים), והם יסווגו ב־baseline.
- **ממשק אנגלי (DD-20 A) · קיים (MIG-24):** שפת הממשק חלה על "כרום הממשק" בלבד, לפי הרשימה הסגורה הזו:
  1. **שורת הכותרת:** כפתורי החלון ומסך מלא, כותרת המסך, היסטוריה/סימניות/שולחן עבודה, הגדרות תצוגת הספרים, רצועת הכרטיסיות, תפריט הכרטיסייה וחיפוש הכרטיסיות, ועמודת הכרטיסיות האנכית.
  2. **סרגל הניווט** (צדדי ותחתון) ותפריט היישום ב־macOS.
  3. **חלוניות שנפתחות מהכרום:** חלונית הכלים וחלונית "הגדרות תצוגת הספרים" (`ContextOverlayPanel`).
  4. **מסך ההגדרות**, הדיאלוגים שנפתחים ממנו (`settingsDialogBuilder`) והגדרות התוספים.
  5. **הסיור והטיפים.**
  6. **ניהול כרטיסייה מפוצלת:** ידית הגרירה והמפריד בין החלוניות.
  7. **מעטפת הדיאלוגים המשותפים**, כשהקורא לא מסר טקסט משלו: תוויות ברירת המחדל (אישור, ביטול, המשך, שמור, איפוס), ה־X בכותרת, שאלת "לסגור בלי לשמור?" (DD-08), ורמז החיפוש וה"אין תוצאות" ב־`SelectionDialog`.
  8. **תוויות מובנות ברכיבים המשותפים:** ה־tooltip של הרחב/כווץ, נקה, תוצאה קודמת/הבאה, סגור חלונית, הצג מפרשים (MIG-11).
  9. **tooltip של כפתור בתוך כלי:** הוא חלק מהכפתור ולא מתוכן הכלי. ששת ה־tooltips של כפתורי כרטיס המילון הארמי (״העתק״ ועוד) עוברים דרך `settingsText` (DD-20, השלמה 2.11, UI-145). תוכן המילון נשאר בעברית.

  **מחוץ לכרום** (עברית ו־RTL בכל שפה): תוכן המסכים — ספרייה, איתור, עיון, חיפוש ותוצאותיו, הכלים והתוספים בתוך המסך (חוץ מ־tooltip של כפתור, סעיף 9); טקסט הספרים; הודעות `UiSnack` (הקטלוגים בעברית); ה־locale של Material; כותרת החלון במערכת ההפעלה. מסכי תוכן שכבר קוראים ל־`settingsText` (דיאלוג החיפוש, האיתור, הספריות המצורפות) נשארים כמו שהם, אבל אינם חלק מההתחייבות.

  בתוך הכרום כל מחרוזת עוברת דרך `context.settingsText` (מחוץ לעץ: `resolveSettingsText`), והפריסה ב־Directional APIs בלבד. הכרום עטוף ב־`ChromeDirectionality`, ותוכן המסכים ב־`ContentDirectionality`. תווית ברירת מחדל של דיאלוג היא `null` בפרמטר ונפתרת בבנייה, כדי שטקסט שהקורא מסר לא יתורגם. ברירת המחדל של שפת הממשק **נשארת "לפי מערכת ההפעלה"**.
- **טקסט מעורב:** שם ספר עם מספרים, או אנגלית בתוך עברית. משתמשים בכיוון הבסיס של הפסקה ולא כופים כיוון. לנתיב או מזהה בתוך משפט עברי עוטפים את הקטע ב־`Text.rich` עם `TextSpan` שבו `textDirection: ltr`, או משתמשים בתווי בידוד (`⁦…⁩`).
- **מספרים:** ספרות מערביות בכל המקומות. גימטריה ואותיות עבריות לפי ההקשר.
- **קיצורי מקשים:** תמיד LTR, ובצורה אחידה `Ctrl+Shift+P` דרך `ShortcutHelper`.
- **אייקונים כיווניים:** ראו 2.5.1. אייקון Fluent עם `matchTextDirection` משתמש ב־`Icon` רגיל עם הגליף של LTR (חזרה = `arrow_left`, כניסה/הבא = `chevron_right`), ומתהפך מעצמו במצב עברית (UI-023, MIG-11).
- **LTR מכוון בתוך RTL:** עורך קוד או נתיב, פריסת מקלדת וכפתורי חלון של מערכת ההפעלה. עוטפים ב־`Directionality(ltr)` מקומי עם הערה של שורה אחת.

### 6.2 מקלדת ופוקוס [מחייב]
- כל פעולה זמינה במקלדת. סדר ה־Tab הוא סדר הקריאה (RTL) בתוך כל `FocusTraversalGroup`.
- ברשימה עם פריט נבחר, Tab נוחת עליו (`NavTreeFocusGroup` הוא הדפוס הקיים).
- טבעת פוקוס נראית. **אסור** `focusColor: Colors.transparent` בלי חלופה נראית. היום כך ב־`ToolResultCardShell`.
- Escape סוגר שכבה אחת (`EscapeLayers`) ולא יותר.
- רכיב מותאם (`GestureDetector`/`Listener`) שמגיב ללחיצה חייב גם `Focus`, `Semantics(button: true)` ו־Enter/Space. היום הרצועות של הכרטיסיות ו־`PanelOpenHandle` לא נגישים (MIG-11, MIG-21).

### 6.3 Semantics, tooltip, טקסט וניגודיות [מחייב]
- **שם נגיש:** לכל רכיב אינטראקטיבי. לכפתור אייקון זה ה־`tooltip`. לרכיב מותאם: `Semantics(label:)`.
- **מצב:**
  - נבחר: `Semantics(selected:)`. חסר היום בכרטיסיות, בפריטי ניווט ובשורות radio של ההגדרות.
  - מורחב: `expanded:`, מובנה ב־`ExpandingChevron` (DD-27).
  - מושבת: `enabled:`.
  - נבחר בקבוצה: `inMutuallyExclusiveGroup` + `checked`.
- **הודעות:** `UiSnack` מכריז ב־`SemanticsService.announce` (יעד, MIG-11).
- **הגדלת טקסט:**
  - אין `MediaQuery.withNoTextScaling` או `textScaler: TextScaler.noScaling` בממשק.
  - `RichText` גולמי מתעלם מהגדלת הטקסט של מערכת ההפעלה, ולכן משתמשים ב־`Text.rich`. היום ב־`RichText` משתמשים קטעי תוצאות, סרגל מונחי החיפוש ושורות אוצר החכמה.
  - כל פריסה נבדקת ב־`TextScaler.linear(1.3)` בלי גלישה. גובה קבוע לרכיב עם טקסט אסור. משתמשים ב־`minHeight`.
- **ניגודיות:**
  - טקסט רגיל ≥4.5:1, ורכיבים גרפיים וטקסט גדול ≥3:1. נבדק לכל זרע בבדיקות `test/theme/app_theme_data_test.dart`.
  - טקסט משני הוא `onSurfaceVariant`, לא `onSurface` בשקיפות.
  - צבע אינו הסימן היחיד למצב: נבחר מסומן גם במשקל או באייקון (DD-06).
- **הפחתת תנועה:** ראו 2.5.5 (DD-21).
- **גופנים שונים:** הממשק מוצג בגופן המערכת (DD-01), ולכן משתנה בין פלטפורמות. אסור להניח רוחב תו קבוע: אין רוחב בפיקסלים שמחושב מאורך מחרוזת.

---

## 7. מצבי משתמש וערכות נושא (ב.7)

| הגדרה | איפה נשמרת | איפה מוחלת | היקף | הערות |
|---|---|---|---|---|
| ערכת צבע (seed), בהיר | `SettingsBloc.seedColor` | `app.dart:43` → `createColorScheme` | גלובלי, כל הכרום | 14 זרעים. ל"לבן" ול"פרגמנט" יש override לסולם המשטחים |
| ערכת צבע, כהה | `darkSeedColor` | כנ"ל | גלובלי | הבורר עורך רק את הזרע של הבהירות הנוכחית. לוחות כהים `surfaceContainerLow`, קריאה נייטרלית (DD-05) |
| בהיר/כהה/מערכת | `isDarkMode`, `followSystemTheme` | `MaterialApp.themeMode` | גלובלי | |
| גופן קריאה, גודל, גובה שורה | `SettingsState.fontFamily/fontSize/lineHeight` | הקורא, קטעי תוצאות, ייצוא | **תוכן בלבד** | לא משפיע על הממשק, ונשאר כך **[מחייב]** |
| גופן וגודל של מפרשים | `commentators*` | תוכן | תוכן בלבד | |
| פרופיל תצוגת טקסט (ניקוד, טעמים) | `TextDisplayProfile` | תוכן | תוכן ו־export | |
| "צפיפות ממשק" | `compactMenuMode` | היום: 68 קריאות ישירות, `AppMenuMetrics` (זהה בשני המצבים) | סרגלים, שדות ותפריטים | DD-10 B: `AppDensity` (יעד, MIG-06). השם "צפיפות ממשק" נשאר. התפריטים צפופים יותר במצב הקומפקטי |
| שפת הממשק | `settingsLanguageCode` (ברירת מחדל "מערכת") | `SettingsTextScope`, `ChromeDirectionality` | כרום הממשק — הרשימה הסגורה ב־6.1 (DD-20) | ברירת המחדל נשארת "לפי מערכת ההפעלה". מומש ב־MIG-24 |
| גודל ממשק | **אין** | — | — | לא מוסיפים. מספיקה הגדלת הטקסט של מערכת ההפעלה (6.3) |
| גופן ממשק | **אין** הגדרה | `AppThemeData` | — | גופני המערכת (DD-01). היום 'Roboto' שאינו כלול (MIG-05) |
| הגדרות תפריטים (הצגת פריטים) | `SettingsState` (מקשים שונים) | תפריטי הקשר | תוכן התפריט, לא מראה | לא שייך למערכת העיצוב |

**[מחייב]**
1. החלפת ערכת נושא לא מחייבת שינוי ברכיבים. רכיב שבודק `brightness == Brightness.dark` כדי לבחור צבע מפר את התקן: ההחלטה שייכת ל־`AppSurfaces` או ל־ThemeExtension. היום יש 57 בדיקות כאלה מחוץ ל־`lib/theme`.
2. הגדרות קריאה והגדרות ממשק נשארות נפרדות. לא מאחדים אותן ל"גודל טקסט" אחד.
3. **תוספים (DD-25 A):** תוספים (WebView) מקבלים את ערכת הנושא דרך `buildThemePayloadFromScheme`. מ־0.9.99 ה־payload כולל, כתוספת שאינה שוברת, גם `surfaces` (reader, panel, card, topBar מתוך `AppSurfaceColors`), `radius`, `spacing`, `density` (מתוך `AppDensity`) ו־`typography.uiFont` (גופן הממשק של המארח כערך CSS). `uiFontFamily` נשאר 'Rubik' לתאימות. השדות מתועדים ב־`otzaria_plugin.d.ts`, ב־`API_REFERENCE.md` וב־`DESIGN_GUIDE.md` כאופציונליים מ־0.9.99. כשמוסיפים טוקן משטח או גופן ממשק, מוסיפים אותו גם ל־payload.

---

## נספח א' — מקור אמת לכל סוג הגדרה

הבעלים של כל סוג, ומתי הוא נקבע: `MIGRATION_PLAN.md` §7.1.

| סוג | מקור אמת אחד | סטטוס | מקורות מתחרים שיש להסיר |
|---|---|---|---|
| תפקידי צבע | `AppThemeData.createColorScheme` | קיים | בנייה נוספת ב־`main_window_screen.dart:3352` (להחליף בקריאה משותפת) |
| משטחים ומצבים | `AppSurfaces` → `AppSurfaceColors` (ThemeExtension, DD-19) | יעד (MIG-06, MIG-07) | שקיפויות מקומיות, `primaryColor`, ענפי `isDark` בפיצ'רים |
| אזהרה והדגשה | `AppSurfaces.warning*` (DD-24), `searchHit*`/`permanentMark` (DD-17) | יעד (MIG-12, MIG-23) | באנרים בכתום קשיח, `tertiary` כאזהרה, CSS אדום/כחול/צהוב |
| טיפוגרפיית ממשק | `ThemeData.textTheme` (מלא, DD-02) | יעד (MIG-05) | `AppTokens.font*` בפיצ'רים, `AppTextStyles` מחוץ להגדרות, `AppTopBar.titleStyle`, `fontSize:` מספרי |
| גופן ממשק | `ThemeData.fontFamilyFallback` ב־`AppThemeData` (DD-01) | יעד (MIG-05) | 9 מופעים של `'Roboto'` קשיח, `'Rubik'` ב־payload התוספים (DD-25) |
| טיפוגרפיית תוכן | `SettingsState` + `AppFonts` | קיים | `Settings.getValue('key-font-family')` ב־build |
| ריווח | `AppTokens.space*` + טוקנים סמנטיים | חלקי (MIG-04) | מספרים קשיחים |
| רדיוסים | `AppTokens.radius` (ערך אחד, DD-04) | קיים | `circular(n)`, `StadiumBorder`, תג עגול |
| הגבהה וצל | `AppTokens.elevation*` + `AppShadows` (DD-12) | יעד (MIG-08) | elevation 2/4/6/8/10/18, `BoxShadow` מקומי |
| גבהים | `AppInputTokens` + `AppDensity` | יעד (MIG-06) | `heightCompact` ב־`OtzariaSearchField`, גבהים ב־`AppTopBar`/`BarButton` |
| גדלי אייקון | `AppTokens.icon*` (DD-03) | יעד (MIG-04) | טוקני גופן כגודל אייקון, מספרים |
| אנימציות | `AppTokens.anim*`, `curve*`, `AppMotion` (DD-21) | חלקי (MIG-04) | ~90 משכים קשיחים |
| הגדרות דיאלוג | `lib/widgets/dialogs/` (`AppDialog`, `AppDialogFrame(size: AppDialogSize)`) | יעד (MIG-10) | 8 מסגרות, רוחבים קשיחים |
| פריסות מסך | `lib/widgets/layout/`, `navigation/`, `ToolScaffold` | חלקי (MIG-22) | מעטפות מקומיות |
| רכיבי ניווט | `NavSidePanel`, `NavRailItem`, `NavTreeTile`; רוחב חלונית מטוקן אחד (DD-28) | קיים; הטוקן יעד (MIG-14) | `kSidePanelWidth` כפול |
| רספונסיביות | `LayoutBreakpoints` + `WindowClass` (DD-15) | יעד (MIG-21) | 32 ספים קשיחים |
| צפיפות | `AppDensity` (DD-10) | יעד (MIG-06) | 68 קריאות ל־`compactMenuMode` |
