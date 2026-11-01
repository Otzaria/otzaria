# מערכת העיצוב של אוצריא — מסמך התקן

> **מעמד:** טיוטה 0.1 לאישור מתחזקים. נכתב מול `upstream/dev` ב־`f86ecd7c7`, עודכן מול `ac97e4490` אחרי #3794 (1.11.2026).
> **קהל:** כל מי שכותב קוד ממשק באוצריא: מפתחים, סוקרים וסוכני AI.
> **מסמכים נלווים** (כולם בתיקייה זו):
> - [UI_AUDIT.md](UI_AUDIT.md): הממצאים בקוד הקיים, עם מזהים `UI-xxx`.
> - [DESIGN_DECISIONS.md](DESIGN_DECISIONS.md): הכרעות פתוחות, עם מזהים `DD-xx`.
> - [MIGRATION_PLAN.md](MIGRATION_PLAN.md): סדר ה־PRs.
> - [CI_ENFORCEMENT.md](CI_ENFORCEMENT.md): אכיפה אוטומטית.
> - [DEVELOPER_GUIDE.md](DEVELOPER_GUIDE.md): איך עובדים בפועל.
> - [ui-audit.json](ui-audit.json): הממצאים בפורמט מכונה.

## 0. איך לקרוא את המסמך

המסמך מבחין בין שלושה סוגי כללים. כל כלל מסומן באחד מהם:

| סימון | משמעות | מה עושים |
|---|---|---|
| **[מחייב]** | התקן קיים כבר בקוד, או שהוא כלל הנדסי שאין עליו מחלוקת. | פועלים לפיו כבר עכשיו. סוקר רשאי לחסום PR שמפר אותו. |
| **[מוצע · DD-xx]** | המלצה שממתינה להכרעת מתחזק ב־`DESIGN_DECISIONS.md`. | עד ההכרעה לא משנים מראה קיים לפיה. קוד חדש משתמש בטוקן או ברכיב הקיים הקרוב ביותר. |
| **[אסור]** | דפוס שאין להוסיף בקוד חדש. | קוד קיים שמפר את הכלל רשום ב־baseline של ה־CI ויוסר בהדרגה. |

**מקור אמת:** לכל סוג ערך יש מקור אחד בקוד, וטבלה מרוכזת שלהם מופיעה בנספח א'. כשהמסמך והקוד סותרים, הקוד ב־`lib/theme/` קובע את הערך. המסמך קובע את הכלל, ואת הסתירה עצמה מתעדים כממצא.

**מה לא נכלל:** טיפוגרפיה וצבעים של **תוכן הספרים** כפופים להגדרות הקריאה של המשתמש, ולא לטוקני הממשק. ראו סעיף 2.4.2.

---

## 1. עקרונות העיצוב (ב.1)

### 1.1 עקרונות מחייבים

1. **מקצועי, נקי ועקבי.** אותו תפקיד נראה ומתנהג אותו דבר בכל מקום. דיאלוג אישור במסך ההגדרות זהה לדיאלוג אישור בכלי לוח השנה.
2. **עברית ו־RTL הם מצב הבסיס, לא תרגום.** כל רכיב נבנה ונבדק קודם ב־RTL. מצב LTR קיים בשני מקרים בלבד: מצב האנגלית של ההגדרות והממשק (`ChromeDirectionality`), ותוכן שהוא LTR מטבעו, כמו נתיבים, כתובות, מזהים וגרסאות.
3. **הקריאה במרכז.** התוכנה היא כלי קריאה וחיפוש בספרים. אזור הקריאה שקט, וכל ממשק אחר משרת אותו. צבע, צל ותנועה לא מתחרים בטקסט.
4. **צפיפות מאוזנת לשימוש ממושך במחשב.** ברירת המחדל מותאמת לעכבר ולמקלדת ולשעות עבודה ארוכות. מגע נתמך דרך שטחי לחיצה מינימליים (סעיף 2.5.6) ולא דרך הגדלה כללית של כל הממשק.
5. **הבחנה ברורה בין תוכן, ניווט ופעולות.** לכל אחד מהם משטח משלו (סעיף 2.1): רקע קריאה, רקע חלוניות וסרגלים, וכרטיסים.
6. **נגישות היא חלק מההגדרה של רכיב.** רכיב משותף שאין לו שם נגיש, פוקוס מקלדת ומצב (נבחר, מורחב, מושבת) לא נחשב שלם.
7. **ביצועים.** אין עטיפות Widget שנועדו רק "ליישור", אין חישובי עיצוב בתוך פריטי רשימה גדולה, ואין `TextPainter` בלולאה בתוך כפתור.
8. **שימוש חוזר לפני שכפול.** לפני שכותבים רכיב, מחפשים את הקיים בקטלוג (סעיף 3). רכיב חדש נוסף רק לפי הכללים ב־`DEVELOPER_GUIDE.md` §8.
9. **שינוי סגנון גלובלי במקום אחד.** החלפת צבע, רדיוס, גופן או צפיפות נעשית ב־`lib/theme/` בלבד, בלי לגעת בקבצי פיצ'רים.
10. **מינימום חריגים.** חריג מותר רק עם הערת `ui-lint: allow` ונימוק (ראו `CI_ENFORCEMENT.md` §3.5), או כשהוא רשום ברשימת ההחרגות שבהגדרות ה־CI.

### 1.2 העדפות סגנוניות שטרם אושרו

את הנושאים הבאים הסבבים הקודמים (#3322, #3539, #3794) הנהיגו בפועל, אבל לא אושרו כתקן. עד להכרעה הם מוגדרים "ברירת מחדל נוכחית" ולא "חובה":

- פס כותרת (`headerBand`) עם תג אייקון בדיאלוגים בינוניים וגדולים (DD-07).
- כפתור ביטול בסגנון `neutral` (tonal) מול `ghost` (DD-09).
- כותרות מקטע בצבע `primary` (DD-14).
- כרטיסים עם מסגרת `outlineVariant` מול כרטיסים בלי מסגרת (DD-11, DD-12).
- רדיוס אחיד 8 לכל דבר (DD-04).

---

## 2. מערכת הטוקנים (ב.2)

### 2.0 מבנה הטוקנים בקוד — מה קיים

| קובץ | מחלקה | תוכן | הערכה |
|---|---|---|---|
| `lib/theme/app_tokens.dart` | `AppTokens` | ריווח 4/8/16/24/32, רדיוס 8, גופן 12/14/16/18, elevation 1/3, משכי אנימציה, מידות ידית גרירה ולשונית. | בסיס טוב. חסרים 2/12 בריווח, ואין טוקנים לאייקונים, לגבולות ולמשטחי לחיצה. |
| `lib/theme/app_tokens.dart` | `AppTextStyles` | `settingTitle` 16, `settingSubtitle` 13. | שני סגנונות בלבד. אין סולם תפקידים (UI-001). |
| `lib/theme/app_surfaces.dart` | `AppSurfaces` | 31 פונקציות סטטיות של משטחים וצבעי מצב. | מקור האמת למשטחים. סטטי, ולכן אי אפשר לדרוס אותו לתת־עץ (DD-19). |
| `lib/theme/app_colors.dart` | `AppColors` | 4 צבעים קבועים. | תקין. `permanentHighlight` לא מותאם למצב כהה. |
| `lib/theme/app_input_tokens.dart` | `AppInputTokens` | גובה שדה 48/36, גופן 16/13 וערכי שקיפות. | תקין. גובה שלישי, 40, מוגדר מחוץ לקובץ (`otzaria_search_field.dart:17`). |
| `lib/theme/layout_tokens.dart` | `LayoutBreakpoints`, `LayoutPadding`, `LayoutConstraints` | 600/840/1200, 16/24/32, 860. | בשימוש ב־8 קבצים בלבד, מול 32 ספי רוחב מספריים בקוד. |
| `lib/theme/app_theme_data.dart` | `AppThemeData` | בניית `ColorScheme` ו־`ThemeData`. | חסרים component themes ו־textTheme מלא (UI-001, DD-02). |
| `packages/otzaria_context_menu` | `AppMenuMetrics` | ה־ThemeExtension היחידה באפליקציה. | הערכים זהים בשני מצבי הצפיפות (`menu_metrics.dart:30-46`). |
| `lib/theme/app_seed_colors.dart`, `calendar_event_colors.dart` | — | פלטות תוכן. | תוכן, לא מדיניות. מוחרגים מכללי ה־CI. |

**[מחייב]** טוקנים חדשים נוספים לקבצים האלה בלבד. לא פותחים קובץ טוקנים מקביל בתיקיית פיצ'ר.
**[מחייב]** טוקן הוא `static const` כשהערך לא תלוי בערכת הנושא, כמו ריווח, רדיוס, משך וגודל. כשהערך תלוי בערכת הנושא (צבע), הטוקן הוא פונקציה של `ColorScheme`/`BuildContext` ב־`AppSurfaces`, או שדה ב־ThemeExtension אם DD-19 יאושר.

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

`Colors.transparent` מותר. החריגים המותרים מפורטים בסעיף 2.1.3.

#### 2.1.1 קטלוג תפקידי הצבע

| טוקן (תפקיד) | מקור בקוד | ערך בהיר | ערך כהה | סטטוס | שימוש |
|---|---|---|---|---|---|
| רקע קריאה | `AppSurfaces.readerBackground` | `cs.surface` | `AppColors.darkScaffold` `#242424` (זהה לכל זרע) | קיים · DD-05 | מסכי ספר, PDF ותוצאות חיפוש |
| רקע לוח (מסכי עבודה) | `AppSurfaces.panelBackground` | `surface` + `surfaceContainerHighest` בשקיפות 47.5% | `Colors.black` | קיים · DD-05 | הגדרות, ספרייה וכלים |
| ~~רקע לוח "מוצק"~~ | `AppSurfaces.solidPanelBackground` | כמו panelBackground | כמו panelBackground | **כפילות: להסיר** (UI-128) | — |
| סרגל עליון | `AppSurfaces.topBarBackground` | `surfaceContainerHigh` | `surfaceContainerHigh` | קיים | `AppTopBar` |
| חלונית ניווט | `AppSurfaces.navPanelBackground` | = topBar | = topBar | קיים (שם נרדף מכוון) | `NavSidePanel` |
| כרטיס | `AppSurfaces.card` | `surface` | `surfaceContainer` | קיים · DD-11 | `AppCard`, `ListDialogCard`, `DetailsCard` |
| מפריד שורות בכרטיס | `AppSurfaces.cardRowDivider` | = panelBackground | שחור | **שגוי מעל דיאלוג** · DD-12 | `AppCard.sectionDivider` |
| מקטע ניטרלי בחלונית | `AppSurfaces.panelSection` | `surfaceContainerHighest` בשקיפות 50% | כנ"ל | קיים | חלוניות הגדרות |
| מקטע מודגש | `AppSurfaces.panelSectionAccent` / `…AccentBorder` | `primaryContainer` 30% / `primary` 30% | כנ"ל | קיים | — |
| משטח מוגבה (תפריט, tooltip, דיאלוג) | `dialogTheme`/`menuTheme`/`tooltipTheme` | `surfaceContainerHigh` | `surfaceContainerHigh` | קיים. **popupMenu חורג:** `surfaceContainer` (UI-076) | — |
| טקסט ראשי | `cs.onSurface` | M3 | M3 | מחייב | — |
| טקסט משני | `cs.onSurfaceVariant` | M3 | M3 | **מחייב.** מחליף את `onSurface` בשקיפות 50–60% (כ־20 מופעים) | תת־כותרות, מטא־דאטה |
| מסגרת והפרדה | `cs.outlineVariant` | M3 | M3 | מחייב | — |
| מפריד עדין | *חסר* | `outlineVariant` בשקיפות 50%, כפול ב־3 מקומות | | **מוצע: `AppSurfaces.subtleDivider`** | — |
| פעולה ראשית / משנית | `cs.primary` / `cs.secondaryContainer` | M3 | M3 | מחייב, דרך `ActionButton` | — |
| שגיאה | `cs.error` / `cs.errorContainer` | M3 | M3 | מחייב | — |
| אזהרה / הצלחה | *חסר*: אין תפקיד ב־M3 | — | — | **מוצע · DD-24:** `AppSurfaces.warning`/`success` + `on…` | באנרים ותגיות סטטוס |
| Hover / Pressed / Focus של כפתורים | `_hoverButtonStyle` (שקיפות 8%/12% על primary) | | | קיים בערכת הנושא | — |
| שורה נבחרת | ‎≥8 הגדרות שונות (UI-018) | | | **מוצע · DD-06:** `selectedRow`, `focusedRow`, `hoverRow` | רשימות, עצים, כרטיסיות |
| מושבת | Material (שקיפות 38%) | | | מחייב: לא מגדירים ידנית | — |
| הדגשת תוצאות חיפוש | 4 מערכות: CSS אדום/כחול/צהוב, `error`, `secondaryContainer` 40%, צהוב קבוע | | | **מוצע · DD-17:** `searchHit`, `searchHitCurrent`, `permanentMark` | קורא, קטעי תוצאה |
| קישור בספר | `AppSurfaces.readerLink` | `primary` (אפור בערכה נייטרלית) | | קיים | תוכן |
| בחירת פסקה / שורה מודגשת | `paragraphSelectionBackground`, `highlightedLineBackground` | | | קיים | קורא |
| scrim | 0.30 ב־`AdaptiveSidePane`/`ContextOverlayPanel`, `0x22000000` לדיאלוג | | | **מוצע · DD-12:** טוקן `scrim` אחד | — |
| צל | `Colors.black` בשקיפות 0.22 (×3 בערכת הנושא), `cs.shadow` 0.22, 0.14, 0.10 | | | **מוצע · DD-12:** `AppShadows` | — |

#### 2.1.2 צבעי ניווט, קריאה וסימון
- **ניווט:** הסרגל העליון וחלונית הניווט חולקים צבע אחד (`topBarBackground`), כדי שייראו כרצועה רציפה. **[מחייב]**
- **כרטיסיות:** אין היום טוקן אחד. שלוש רצועות הכרטיסיות משתמשות בצבעי "נבחר", "ריחוף" ו"בחירה מרובה" שונים (UI-014). **[מוצע · DD-06]**
- **סימון טקסט בקורא:** צבעי הדגשה שהמשתמש בוחר (מרקר, צבעי אירועים) הם **תוכן**. שומרים אותם כנתון (אינדקס או ARGB) ומתאימים אותם לבהירות בזמן ציור, כפי ש־`CalendarEventColors` כבר עושה.

#### 2.1.3 חריגים מותרים לצבע מקומי [מחייב]
1. פלטות תוכן: `AppSeedColors`, `CalendarEventColors`, צבעי מרקר, וצבעי CSS שמגיעים מתוך הספר.
2. ייצוא והדפסה (`package:pdf`, ‏`pw.*`): הפלט הוא דף נייר לבן, ללא תלות בערכת הנושא.
3. מדידה וציור ב־`CustomPainter`. גם שם עדיף לקבל צבע מתפקיד.
4. חיקוי כרום של מערכת ההפעלה, כמו כפתורי חלון בסגנון Windows.
5. צללים, כל עוד DD-12 לא הוכרע.

---

### 2.2 ריווח

**קיים:** `spaceXS=4`, `spaceSM=8`, `spaceMD=16`, `spaceLG=24`, `spaceXL=32`. בקוד יש 468 שימושים בטוקנים האלה.
**הפער:** 12 מופיע כ־133 ערכים קשיחים ו־6 כ־39, וגם 10 ו־14 נפוצים. אין להם טוקן, ולכן כל מסך בוחר ערך אחר.

| טוקן | ערך | סטטוס | תפקיד |
|---|---|---|---|
| `AppTokens.space2XS` | 2 | **מוצע · DD-03** | הפרדה בין שורות טקסט צמודות, מרווח אייקון־מונה |
| `AppTokens.spaceXS` | 4 | קיים | בין אייקון לטקסט צמוד, ריפוד תגית אנכי |
| `AppTokens.spaceSM` | 8 | קיים | בין פריטים קשורים, בין כפתורים |
| `AppTokens.spaceSMD` | 12 | **מוצע · DD-03** | ריפוד פנימי של שורת רשימה, בין קבוצות קטנות |
| `AppTokens.spaceMD` | 16 | קיים | ריפוד כרטיס, ריפוד דיאלוג אופקי, בין כרטיסים |
| `AppTokens.spaceLG` | 24 | קיים | ריפוד דיאלוג (M3), בין מקטעים |
| `AppTokens.spaceXL` | 32 | קיים | שוליים של מסך רחב |

**טוקנים סמנטיים** (`static const EdgeInsets` ב־`AppTokens`, **[מוצע · DD-03]**). כל הערכים נגזרים מהסולם:

| שם | ערך מוצע | ערך נפוץ היום |
|---|---|---|
| `cardPadding` | `all(16)` | 12 / 14×12 / 16 |
| `cardPaddingCompact` | `all(12)` | — |
| `listRowPadding` | `symmetric(h: 12, v: 8)` | 12/8, 12/10, 14/10, 16/12 |
| `listItemGap` | 8 | 6 / 8 / 16 |
| `sectionGap` | 24 | 16–32 |
| `dialogPadding` | `fromLTRB(24, 16, 24, 16)` | (#3794 משנה את התחתון ל־16) |
| `titleContentGap` | 16 | 8–16 |
| `labelFieldGap` | 4 | 4–8 |
| `screenPadding` | `LayoutPadding.compact/medium/expanded` (16/24/32) | קיים, כמעט לא בשימוש |

**[מחייב]**
- ריווח בקוד פיצ'ר נכתב רק כטוקן או כצירוף של טוקנים (`spaceSM + spaceXS`). אסור "טוקן ± 1" (`spaceSM + 1`), כי זה ערך שמחוץ לסולם בתחפושת.
- `EdgeInsets.only(left/right)` ו־`EdgeInsets.fromLTRB` אסורים כשהריווח תלוי כיוון. משתמשים ב־`EdgeInsetsDirectional`.

### 2.3 רדיוסים

**קיים:** `AppTokens.radius = 8`, עם `borderRadiusAll` ו־`roundedShape`. השימוש נרחב: 244 שימושים, ורק 11 פעמים `circular(8)` קשיח. **בפועל כבר קיימות צורות נוספות:** גלולה (`BarButton.text` ‏`circular(100)`, `StadiumBorder` בצ'יפ), עיגול (`AppDialogIconBadge`), ו־4 בסימון בתוך תפריט.

| תפקיד | ערך היום | סטטוס |
|---|---|---|
| שדה קלט | 8 (`inputDecorationTheme`) | מחייב |
| כפתור טקסט | 8 (`_hoverButtonStyle`) | מחייב |
| כרטיס, דיאלוג, תפריט, tooltip | 8 | מחייב |
| תגית / צ'יפ | 8 ב־`MetaChip`, גלולה ב־`FilterChipsSelector` | **DD-04** |
| כפתור טקסט בסרגל | גלולה | **DD-04** |
| תג אייקון של דיאלוג | עיגול; ב־`ListIconBadge` ריבוע עגול | **DD-04** |
| רכיבים עגולים (נקודת סטטוס, אווטאר) | עיגול | מחייב |
| רכיב פנימי בתוך רכיב מעוגל | 8, ולכן הפינות "בורחות" מהקונטיינר | **מוצע · DD-04:** `radiusInner = 4` |

**[מוצע · DD-04]** מדרג מצומצם של ארבעה ערכים בלבד:
- `radius` (8): ברירת המחדל לכל רכיב מלבני.
- `radiusInner` (4): לרכיב פנימי בתוך מכל של 8.
- `StadiumBorder`: לצ'יפים ולתגיות בלבד.
- `CircleBorder`: לרכיבים עגולים בלבד.

כל ערך אחר אסור.

### 2.4 טיפוגרפיה

#### 2.4.1 טיפוגרפיית ממשק

**המצב היום:**
- `ThemeData.textTheme` דורס רק את `bodyMedium = 18` (`app_theme_data.dart:97-99`). התוצאה היא היפוך היררכיה: תת־כותרת של `ListTile` (18) גדולה מהכותרת שלה (16), ובמצב ריק ההודעה גדולה מהכותרת (UI-015).
- `fontFamily: 'Roboto'` מוגדר אבל **הגופן לא כלול באפליקציה**, ולכן הממשק מוצג בגופן מערכת שונה בכל מחשב (DD-01).
- בנוסף קיימים 158 גדלי גופן קשיחים, ובהם ערכים מחוץ לסולם: 13 (×32), 11 (×10), 15 (×9) ו־10.

**התקן [מוצע · DD-02]:** סולם תפקידים אחד, מוגדר במלואו ב־`ThemeData.textTheme`. קוד פיצ'ר בוחר **תפקיד**:

| תפקיד בממשק | slot ב־textTheme | גודל/משקל מוצע | היום |
|---|---|---|---|
| כותרת ראשית (מסך ריק גדול, אודות) | `headlineSmall` | 22 / w600 | 24 (M3) |
| כותרת מסך / סרגל עליון | `titleLarge` | 18 / w600 | AppTopBar ‏16/w600 קשיח |
| כותרת דיאלוג | `titleLarge` | 18 / w600 | 22 / w400 (M3) |
| כותרת מקטע (`SettingsCard`, `NavTreeHeader`) | `titleMedium` | 16 / w700 | 16 w500 + bold ידני / 14 w700 |
| כותרת כרטיס / שורה | `titleSmall` | 14 / w600 | 14–16 מעורב, וגם 15 (`fontMD + 1`) |
| טקסט גוף | `bodyLarge` | 16 | 16 |
| טקסט גוף משני / תיאור | `bodyMedium` | **14** (היום 18) | 18 |
| מטא, הערות שוליים, מונים | `bodySmall` | 12 (13?) | 12, ו־13 ב־32 מקומות |
| תווית שדה / כפתור | `labelLarge` | 14 / w500 | 14 |
| תווית קטנה (צ'יפ, לשונית) | `labelMedium` / `labelSmall` | 12 / 11 | 10–12 |
| הודעת שגיאה בשדה | `bodySmall` + `cs.error` | 12 | `AppDialog.warning` ‏13 קשיח |
| מונוספייס (נתיב, קיצור מקשים, גרסה) | **חסר** → `AppTextStyles.mono` | גופן `monospace` ממערכת ההפעלה, 13 | — |

**[מחייב] כבר עכשיו, בלי קשר להכרעה:**
- `fontSize:` מספרי בקובץ פיצ'ר אסור לטקסט ממשק. משתמשים ב־`Theme.of(context).textTheme.<slot>`, ובמקרה הצורך ב־`.copyWith(fontWeight:/color:)`.
- `TextStyle(fontFamily: 'Roboto')` אסור. המשפחה נקבעת במקום אחד (DD-01).
- `AppTextStyles.settingTitle/settingSubtitle` שמורים לשורות הגדרה. לא בונים מהם סגנונות לשימושים אחרים: `NavTreeTile` מקטין את `settingTitle` ל־14 (UI-015).

#### 2.4.2 טיפוגרפיית תוכן הספרים (מערכת נפרדת)

**[מחייב]** טקסט ספר, מפרשים, קטעי תוצאות ותצוגות מקדימות של קישורים מקבלים גופן, גודל וגובה שורה **מהגדרות הקריאה** (`SettingsState.fontFamily`/`fontSize`/`lineHeight`/`commentators*` ו־`TextDisplayProfile`). הם **לא** כפופים ל־textTheme.

הכללים:
- גדלים יחסיים בתוך תוכן (×0.85 לכותרת מפרש, ‎sup/small ב־HTML) הם חלק מהתוכן ומותרים.
- **הודעות ממשק בתוך אזור התוכן** ("טוען מפרשים…", "אין תוכן זמין", שגיאת טעינה) הן ממשק, ולכן `textTheme`. היום הן מוגדלות לפי גודל הקריאה (UI-066).
- גופני ספר נקבעים דרך `AppFonts` בלבד.
- ההחרגה ב־CI נעשית לפי נתיבים ודפוסים ולא בהערות. הרשימה ב־`CI_ENFORCEMENT.md` §3.6.

### 2.5 טוקנים נוספים

#### 2.5.1 אייקונים
**[מחייב]** הכללים הקיימים ב־`docs/agent_ui_reference.md` §1 (otzaria_icons קודם, אחר כך Fluent; בלי Material). **חריג חשוב:** מודל `RtlIcon` שגוי עבור אייקוני Fluent שמוגדרים `matchTextDirection: true`. ההחלפה וההיפוך האוטומטי מבטלים זה את זה, ולכן התוצאה זהה ב־RTL וב־LTR (UI-023). את התיעוד צריך לתקן לפני שמרחיבים את השימוש ב־`RtlIcon`.

| טוקן מוצע · DD-03 | ערך | שימוש היום |
|---|---|---|
| `AppTokens.iconXS` | 14 | עץ ניווט, תגיות |
| `AppTokens.iconSM` | 16 | בתוך שדה, כפתור קומפקטי |
| `AppTokens.iconMD` | 20 | סרגלים (`BarButton`), תפריטים |
| `AppTokens.iconLG` | 24 | ברירת מחדל של M3 |
| `AppTokens.iconXL` | 48 | מצב ריק |

**[אסור]** להשתמש בטוקן גופן כגודל אייקון. היום זה קורה ב־`meta_chip.dart:50` וב־`details_info_section.dart:86`.

#### 2.5.2 גבהים סטנדרטיים
| רכיב | ערך | מקור | סטטוס |
|---|---|---|---|
| שדה קלט רגיל / קומפקטי | 48 / 36 | `AppInputTokens` | קיים |
| שדה חיפוש slim | 40 | `otzaria_search_field.dart:17` | **להעביר ל־`AppInputTokens`** |
| סרגל עליון רגיל / קומפקטי | 56 / 44 | `app_top_bar.dart` (קשיח) | **להעביר לטוקן צפיפות · DD-10** |
| כפתור סרגל | 40 / 36 | `bar_button.dart` | כנ"ל |
| פריט תפריט | 36 | `AppMenuMetrics` | קיים |
| לשונית חלונית | 44 | `AppTokens.panelTabHeight` | קיים |

#### 2.5.3 גבולות
| טוקן מוצע | ערך | שימוש |
|---|---|---|
| `AppTokens.borderThin` | 1 | מסגרת כרטיס, שדה ומפריד |
| `AppTokens.borderFocus` | 2 | טבעת פוקוס ופס פעיל |
| `AppTokens.sectionGap` | 1.5 | רווח בין שורות ב־`AppCard.section` (קיים כקבוע פרטי) |

#### 2.5.4 צלליות והגבהה [מוצע · DD-12]
**היום:** elevation בערכים 0/1/2/3/4/6/8/10/18, וצללים בשקיפויות 0.05–0.22.
**המוצע:** שלוש רמות בלבד:
- `flat` (0): כרטיסים ומשטחים רגילים.
- `raised` (1): סרגל עליון וחלונית מוצמדת.
- `overlay` (3): תפריט, tooltip וחלונית צפה.

הדיאלוג נשאר לפי M3. כל הרמות דרך `AppShadows`/`AppTokens.elevation*`.

#### 2.5.5 תנועה
| טוקן | ערך | סטטוס |
|---|---|---|
| `AppTokens.animFast` | 150ms | קיים, 16 שימושים |
| `AppTokens.animPanelOpacity` | 200ms | קיים |
| `AppTokens.animNormal` | 250ms | קיים |
| `AppTokens.animPanelSlide` | 300ms | קיים |
| עקומה סטנדרטית | `Curves.easeInOut` (44 שימושים) / `easeOutCubic` לכניסה | **מוצע:** `AppTokens.curveStandard`/`curveEnter`/`curveExit` |
| עיכוב תצוגה מקדימה בריחוף | 280ms קשיח ×6 | **מוצע:** `AppTokens.hoverPreviewDelay` |

**[מחייב]**
- בקוד יש כ־90 משכי אנימציה קשיחים. בקוד חדש משך אנימציה של ממשק הוא טוקן.
- **הפחתת תנועה:** אנימציה שאינה חיונית לתפקוד בודקת את `MediaQuery.disableAnimationsOf(context)`. אף מקום באפליקציה לא בודק זאת היום (UI-028). מוצע עזר יחיד, `AppMotion.duration(context, AppTokens.animNormal)`, שמחזיר `Duration.zero` כשההפחתה פעילה.

#### 2.5.6 שטחי לחיצה [מחייב]
- מינימום 40×40 בדסקטופ, ו־48×48 במגע (`MaterialTapTargetSize.padded`).
- כפתורים של 28×28 (ניווט תוצאות, סרגל מפרשים) ו־32×32 (עין בהגדרות צורת הדף) מתחת לסף, ורשומים בביקורת.
- אפשר לצייר אייקון קטן בתוך שטח לחיצה גדול יותר. מקטינים את השטח רק כשהרכיב הוא חלק משורה צפופה שיש לה חלופה במקלדת.

#### 2.5.7 מגבלות רוחב
| טוקן | ערך | סטטוס |
|---|---|---|
| `LayoutConstraints.panelContentMaxWidth` | 860 | קיים |
| רוחבי דיאלוג | היום 400, 440, 460×4, 480, 500, 540, 560, 620, 640, 680, וגם 50%/80%/90%/95% | **מוצע · DD-07:** `AppDialogSize.small` ‏400 / `medium` ‏560 / `large` ‏720 / `full` |
| חלונית צד | 340 (`AdaptiveSidePane`) ו־`kSidePanelWidth` כפול | **לאחד לטוקן אחד** |
| רוחב תוכן מינימלי ליד חלונית | 500 | כנ"ל |

#### 2.5.8 צפיפות: קומפקטי ורגיל
**היום:** ההגדרה `compactMenuMode` נקראת ישירות 68 פעמים. `AppMenuMetrics` מחזיר ערכים זהים בשני המצבים, ו־`VisualDensity.adaptivePlatformDensity` פועל במקביל.
**התקן [מוצע · DD-10]:** `ThemeExtension<AppDensity>` אחד שנבנה ב־`AppThemeData` מתוך ההגדרה ומכיל:
- גובה סרגל, גובה שדה וגודל כפתור סרגל;
- גודל אייקון בסרגל ו־menu metrics;
- `isCompact`.

רכיבים קוראים `AppDensity.of(context)`. **[אסור]** בקוד חדש לקרוא את `context.read<SettingsBloc>().state.compactMenuMode` מתוך רכיב תצוגה.

---

## 3. קטלוג הרכיבים המשותפים (ב.3)

**כלל השימוש [מחייב]:** בכל תפקיד שמופיע בקטלוג משתמשים ברכיב שהקטלוג מציין. רכיב שמסומן "מוצע" עוד לא קיים. עד שיתווסף, משתמשים ברכיב הקיים שמצוין לצידו, ולא בונים עותק מקומי.

**כלל עיצוב ה־API [מחייב]** (חל על כל רכיב חדש ועל כל שינוי חתימה):
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

#### 3.1.2 משפחות הדיאלוג — התקן [מוצע · DD-07, DD-08]

| משפחה | רכיב מומלץ | מתי | כותרת | אייקון | X | רוחב / גובה | גלילה | פעולות |
|---|---|---|---|---|---|---|---|---|
| **אישור פשוט** | `showTwoActionsDialog` | שאלת כן/לא שאינה הרסנית | `AppDialogTitle` | לא | לא | `small` (400), גובה לפי התוכן | לא | ביטול + אישור (ראשי) |
| **אזהרה** | `showWarningDialog` | פעולה הרסנית או בלתי הפיכה | `AppDialogTitle` + תג שגיאה | כן (ברירת מחדל) | לא | `small` | לא | ביטול (ראשי, מוקד) + אישור (`warning`) |
| **מידע** | `showSingleActionDialog` | הודעה שדורשת קריאה, כשאין די ב־`UiSnack` | `AppDialogTitle`, או headerBand לתוכן עשיר | אופציונלי | לא | `small`/`medium` | אם התוכן ארוך | סגור (ראשי) |
| **קלט** | `showInputDialog` | שדה טקסט אחד | `AppDialogTitle` | לא | לא | `small` | לא | ביטול + אישור. Enter בשדה = אישור |
| **בחירה** | `showSelectionDialog` | בחירת פריט אחד מרשימה | `AppDialogTitle` | לא | לא | `small` × עד 60% גובה | רשימה | ביטול. Enter על פריט = בחירה |
| **בחירה בין N אפשרויות** | **מוצע: `showChoiceDialog`** | 3+ פעולות שוות, למשל "טקסט / Word / ביטול" | `AppDialogTitle` | לא | לא | `small` | לא | N ראשיות/ניטרליות + ביטול |
| **בינוני (טופס, תוכן מורכב)** | `AppDialogFrame` (`size: medium`) | טופס של כמה שדות, הגדרה ממוקדת | `AppDialogHeader` (headerBand) | DD-07 | כן | 560 / לפי התוכן, עד 85% | `PanelScrollableContent` (מוצע: מובנה) | `Wrap` בסוף הכותרת: משני → ראשי |
| **גדול / "מסך כדיאלוג"** | `AppDialogFrame` (`size: large`); יחליף את `AppCustomContentDialog` ואת `ListDialogFrame` | רשימות (סימניות, היסטוריה, גרסאות), ניהול | `AppDialogHeader` + מונה ב־`trailing` | DD-07 | כן | 720 / עד 85% (היום: 50%×80% קבוע) | מובנה | אופציונלי |
| **עם לשוניות** | `AppDialogFrame(size: large, tabs:)` (מוצע) | דיווח שגיאה, הגדרות מרובות | כנ"ל + `TabBar` | | כן | | לכל לשונית | |
| **תהליך / התקדמות** | **מוצע: `runWithBlockingProgress`** | פעולה חוסמת של יותר מ־~300ms | הודעה | — | לא (או "בטל" אם התהליך ניתן לביטול) | `small` | — | בטל (אופציונלי) |
| **מסך מלא** (הדפסה, עורך) | `AppDialogFrame(size: full)` (מוצע) | תצוגה מקדימה עם חלונית הגדרות | `AppDialogHeader` + פקדים בתחילת הכותרת | | כן | 100% פחות שוליים | | |

**חוזה התנהגות של כל המשפחות [מוצע · DD-08, ההמלצה: מחייב]:**

| נושא | התקן |
|---|---|
| **Escape** | סוגר תמיד. אם יש שינויים שלא נשמרו, מוצגת קודם שאלת אישור. Escape לא בולע מקשים מרכיבים פנימיים, ונשען על `DismissIntent` של ה־route ועל `PopScope`. |
| **Enter** | כשהפוקוס בשדה טקסט חד־שורתי, Enter מפעיל את **הפעולה הראשית** אם היא זמינה. כשהפוקוס על כפתור או על פריט ברשימה, Enter מפעיל **את הרכיב הממוקד** ולא את כפתורי הדיאלוג. |
| **חיצים** | לא נבלעים ברמת הדיאלוג. ניווט בין כפתורים נעשה ב־Tab, או בחיצים רק בתוך `FocusTraversalGroup` של שורת הפעולות. |
| **barrier** | לחיצה מחוץ לדיאלוג סוגרת אותו, אלא אם יש שינויים שלא נשמרו או תהליך פעיל. |
| **שינויים שלא נשמרו** | פרמטר אחד, `isDirty`/`onDismissRequest`, ב־`AppDialogFrame` וב־`AppDialog`, שחל על **כל** דרכי היציאה: X, ביטול, Escape ו־barrier. היום `hasUnsavedChanges` חוסם רק את ה־barrier. |
| **פוקוס פותח** | השדה הראשון. בדיאלוג אזהרה: כפתור הביטול. |
| **פוקוס בסגירה** | חוזר לרכיב שפתח את הדיאלוג (`showDialogUntilTornDown` / `registerDialogFocusRestorer`). |
| **Semantics** | ל־route יש `label` עם כותרת הדיאלוג. `AppDialogFrame` מספק את זה היום, ו־`Dialog` גולמי לא. |
| **מובייל (<600)** | `small`/`medium` ברוחב מלא פחות 16, ו־`large`/`full` במסך מלא. ה־headerBand נשאר, וה־X הוא שטח מגע של 48. |
| **פתיחה** | תמיד דרך `showAppDialog` / `showDialogUntilTornDown`, כדי לשמור על הכיווניות של הפותח ועל ניקוי מסודר בסגירה. בהגדרות: `settingsDialogBuilder`. |

**[אסור]** בקוד חדש:
- `AlertDialog(`, `Dialog(`, `SimpleDialog(` מחוץ ל־`lib/widgets/dialogs/`.
- `showDialog(` עם builder שמחזיר אחד מהם.
- `Navigator.of(context).pop()` על route שנפתח ב־root navigator. משתמשים ב־handle שהעזר מחזיר.

### 3.2 כפתורים ופעולות

| תפקיד | רכיב | הערות |
|---|---|---|
| ראשי | `ActionButton.recommended` | אחד לכל קבוצת פעולות |
| משני / ניטרלי | `ActionButton.neutral` | |
| ביטול / טקסט שקט | `ActionButton.ghost` | **DD-09:** האם ביטול בדיאלוג הוא ghost או neutral. התיעוד אומר ghost, והקוד משתמש ב־neutral (18 מופעים מול 9). |
| מסוכן (אישור מחיקה) | `ActionButton.warning` | רק בתוך דיאלוג אזהרה או אחרי אישור. כפתור "מחק" ראשוני ברשימה הוא `neutral` או אייקון. |
| אייקון בלבד, כללי | **מוצע: `AppIconButton`** (עטיפה דקה על `IconButton` שמחייבת `tooltip`) | היום יש כ־180 `IconButton` גולמיים, ובכ־43 מהם אין tooltip (UI-004, UI-030) |
| אייקון בתוך שדה / בסרגל צר | `SquareIconButton.field` / `.toolbar` | |
| פעולת סרגל | `BarButton.icon` / `.text` | צפיפות מ־`AppDensity`. ההחלטה על צורת הגלולה ב־DD-04 |
| פעולה מפוצלת | `BarSplitButton` | |
| פעולת רשימה / שורה | `AppIconButton` בגודל `iconSM`. בשורת הגדרה: `SettingsActionTile` actions | אין hover כפול על השורה |
| קומפקטי | אותם רכיבים עם `AppDensity` | אין רכיב "קומפקטי" נפרד |

**מצבים [מחייב]:**
- **hover/pressed/focus:** מגיעים מערכת הנושא (`_hoverButtonStyle`). לא מגדירים אותם מקומית.
- **disabled:** `onPressed: null`. `SecondaryIconButton` ו־`PrimaryIconButton` לא מאפשרים זאת היום, וזה ממצא בביקורת.
- **loading:** `ActionButton(isLoading:)`. **מוצע:** לשמור על רוחב הכפתור ולהוסיף `Semantics(liveRegion)` "טוען".

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
| חיפוש | `OtzariaSearchField`. בחלונית ניווט: `NavPanelCollapsibleSearch` | אייקון לפי היקף החיפוש (`agent_ui_reference` §1) |
| בחירה אחת מרשימה נפתחת | `AppDropdownField` | **באג:** `decoration.labelText` לא מוצג. עד התיקון התווית נכתבת מחוץ לשדה. |
| 2–4 אפשרויות | `AppSegmentedControl`. בהגדרות: `SettingsActionTile.segmentedTile` | |
| בחירה מרובה | `FilterChipsSelector` / `compactFilterChips` | DD-13 |
| Checkbox | `Checkbox` של Material + `checkboxTheme` (מוצע) | השורה כולה לחיצה (`CheckboxListTile` או `InkWell`) |
| Switch | `SettingsActionTile.switchTile`. מחוץ להגדרות: `Switch` + `switchTheme` (מוצע) | `CustomSwitch` יוסר כשיתווסף `switchTheme` |
| Slider | `SettingsSliderTile` | `SliderTheme` מקומי אסור |
| תאריך | `showDatePicker` + `datePickerTheme` (מגיע ב־#3794) | |
| שגיאת אימות | `InputDecoration.errorText` | לא טקסט אדום שנבנה ידנית מתחת לשדה |
| קבוצת שדות | `SettingsCard`, או `ListDialogCard` בתוך דיאלוג | |
| תווית מעל שדה | `InputDecoration.labelText` | לא `Text` נפרד עם `TextStyle` מקומי |

### 3.4 כרטיסים ורשימות

| תפקיד | רכיב | הערות |
|---|---|---|
| כרטיס מידע | `AppCard` | `Card(` גולמי אסור (היום 8 מופעים) |
| קבוצת שורות בכרטיס | `AppCard.section` | `selected` ב־section שבור ויוסר |
| כרטיס תוצאת חיפוש | `SearchResultCardFrame` בחיפוש, `ToolResultCardShell` בכלים | **DD-11:** האם לאחד את שניהם לרכיב אחד. היום יש 7 מימושים |
| כרטיס עם פעולות | `AppCard` + שורת `ActionButton`/`AppIconButton` בסוף | |
| כרטיס מתרחב | `ExpandableCard`. בהגדרות: `ExpandableSection` | שני מנגנונים. מוצע לאחד (DD-27) |
| שורת הגדרה | `SettingsActionTile.*` בתוך `SettingsCard` | כ־10 דפוסים נבנים היום ידנית |
| פריט רשימה | `ListTile` + `listTileTheme` (מוצע), או `NavTreeTile` בחלוניות | |
| פריט ניווט | `NavRailItem`, `SidebarNavItem`, `NavTreeTile` | |
| תגית / מונה | `MetaChip(tone:)` (מוצע להוסיף `tone`) | היום יש כ־12 מימושי צ'יפ |
| תג אייקון | `ListIconBadge` / `AppDialogIconBadge` | DD-04: עיגול מול ריבוע |
| כותרת מקטע | **מוצע: `AppSectionLabel`** | היום יש 7+ עותקים מקומיים |
| מפריד שורות בדיאלוג | `listDialogRowDivider` | |

**[מחייב]** רשימה ארוכה (יותר מכ־50 פריטים) נבנית עם `ListView.builder` או `SliverList`. לא מחשבים סגנון בכל פריט: את `Theme.of` קוראים פעם אחת מחוץ ל־builder.

### 3.5 משוב ומצבים

| מצב | רכיב | הערות |
|---|---|---|
| טעינה, מסך או חלונית | `LoadingIndicator` (מוצע להוסיף `message`) | היום יש 72 `CircularProgressIndicator` גולמיים |
| טעינה, inline | **מוצע: `LoadingIndicator.inline`** (16px, ‏stroke 2) | 13 עותקים מקומיים |
| טעינה, שלד (skeleton) | **מוצע: `SkeletonLines`** (רוחב לפי `LayoutBuilder`) | 2 עותקים שמחושבים לפי רוחב החלון |
| ריק | `OtzariaEmptyState` (`isCompact` בחלונית) | `ToolEmptyState` הוא כינוי ישן, להחליף |
| שגיאה | `OtzariaErrorState(actions: [נסה שוב])` | לא `Text` אדום |
| הצלחה / הודעה קצרה | `UiSnack.show(CatalogMessages.x)` | מחרוזות מקטלוג בלבד (נאכף) |
| אזהרה בתוך המסך | **מוצע: `AppInfoBanner(tone: info/warning/error/success)`** | היום יש 6+ באנרים מקומיים |
| תוכן לא זמין | `OtzariaEmptyState` עם הסבר | |
| פעולה מתמשכת | `ActionButton(isLoading:)`, או `runWithBlockingProgress` (מוצע) | |
| אישור מחיקה | `showWarningDialog` | 3 סגנונות שונים היום |

**[מחייב]** `UiSnack` אינו משמש למידע קריטי. הודעות `UiSnack` לא מוקראות היום לקורא מסך, ומוצע לתקן זאת בתוך `UiSnack` עצמו.

### 3.6 מסכים ופריסות

| דפוס | רכיב | הערות |
|---|---|---|
| מעטפת מסך לוח (הגדרות, ספרייה, כלים) | `AppTopBar` + רקע `panelBackground` + `LayoutConstraints.panelContentMaxWidth` | |
| מעטפת כלי | **מוצע: `ToolScaffold`** (שדה חיפוש, כותרת תוצאות, מצבי טעינה/ריק/שגיאה) | 5 מסכי כלים בונים את אותו מבנה ידנית |
| אזור תוכן | `PanelScrollableContent` / `CenteredScrollableState` | |
| כותרת מסך | `AppTopBar(title:, subtitle:)` | `titleStyle` קשיח יעבור ל־`textTheme` |
| סרגל פעולות | `ResponsiveActionBar` + `ActionButtonData` | פריטים דרך `BarButton` בלבד |
| חלונית ניווט | `NavSidePanel` | |
| חלונית משנית או צפה | `AdaptiveSidePane` / `ContextOverlayPanel` | DD-28: איחוד ברירות המחדל (רוחב, צל, scrim) |
| Split pane | `SplitPaneView` (tabs) | |
| מסך הגדרות | `SettingsTabScrollView` + `SettingsCard` | |
| מסך תוצאות | `SearchResultCardFrame`/`ToolResultsHeader` | |
| מסך קריאה | `TextBookScreen` / `PdfBookScreen` על `readerBackground` | |

**[מחייב]** מעדיפים קומפוזיציה: מעטפת מסך מקבלת `child` ולא עשרות דגלים. מסך שלא מתאים לאף דפוס בונה פריסה משלו, אבל רק מרכיבים מהקטלוג.

---

## 4. ארכיטקטורת UI וגבולות אחריות (ב.4)

### 4.1 השכבות והמיפוי לתיקיות קיימות

המבנה הקיים כבר מממש את רוב החלוקה. **אין צורך בתיקיות חדשות**, רק בגבולות מוגדרים ונאכפים.

| # | שכבה | תיקייה קיימת | מותר | אסור |
|---|---|---|---|---|
| 1 | **Foundation** | `lib/theme/app_tokens.dart`, `app_colors.dart`, `app_input_tokens.dart`, `layout_tokens.dart`, `app_seed_colors.dart` | קבועים (`static const`): ריווח, רדיוס, גודל, משך, נקודות שבירה, פלטות תוכן | `BuildContext`, ייבוא Widgets, לוגיקה |
| 2 | **Theme** | `lib/theme/app_theme_data.dart`, `app_surfaces.dart` (ו־ThemeExtensions לפי DD-19) | מיפוי של seed, בהירות וצפיפות לתפקידים ול־component themes. הגדרת שקיפויות ומצבים | קריאה ל־Bloc או ל־Settings. החלטות של פיצ'ר מסוים |
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

**רכיבים משותפים שמייבאים פיצ'רים:**
- `ActionButton` → `SettingsBloc`
- `AppTopBar` → `tabs/view/pane_drag_handle`
- `OtzariaSearchField` → plugins registry
- `ItemsListView` → `models/books.dart`
- `NavSidePanel` → `Settings.getValue`

**מסכים שמערבבים IO ולוגיקה עם בניית תצוגה:**
- `text_book_screen.dart` (3795 שורות)
- `error_report_dialog.dart` (1746)
- `system_settings_tab.dart` (1728)
- `search_dialog.dart` (2260)
- `find_ref_dialog.dart` (1971)
- `library_browser.dart` (3017)
- ה־`build` של `page_shape_screen.dart` לבדו הוא כ־770 שורות

**[מחייב]** PR שנוגע בקובץ כזה לא מוסיף לו IO או לוגיקה. פירוק הקובץ נעשה ב־PR נפרד שמוקדש לכך (MIGRATION_PLAN שלב 9).

---

## 5. פריסה רספונסיבית (ב.5)

### 5.1 נקודות השבירה הכלליות
`LayoutBreakpoints`: ‏`compact < 600`, ‏`medium < 840`, ‏`expanded < 1200`, ומעל זה `large`. הערכים עקביים עם M3 ונשארים **[מחייב]**.

**המצב היום:**
- `LayoutBreakpoints` מופיע רק ב־8 קבצים.
- יש 32 השוואות רוחב לערכים קשיחים:
  - 520 ×7 (סף "דיאלוג צר" שלא מוגדר כטוקן)
  - 560 ×4, 600 ×4, 800 ×3, 720 ×2, 700 ×2, 400 ×2
  - ערכים בודדים: 270, 290, 360, 392, 620, 760, 1100, 1400

### 5.2 שני סוגי החלטות
1. **סוג החלון** (window class): ניווט צדדי מול ניווט תחתון, דיאלוג במסך מלא מול דיאלוג צף, מספר עמודות בדף הבית. נקבע לפי `MediaQuery.sizeOf(context).width` מול `LayoutBreakpoints`, דרך עזר יחיד שמוצע: `WindowClass.of(context)` → `compact|medium|expanded|large`.
2. **רוחב זמין לרכיב:** אם שורה גולשת לשתי שורות, אם מונה מוצג, אם התווית הופכת לאייקון. נקבע **רק** עם `LayoutBuilder`/`constraints`, כי הרכיב יכול לשבת בחלונית צרה בתוך חלון רחב. הסף הוא קבוע עם שם ברכיב, למשל `static const _iconOnlyBelow = 560.0`.

**[אסור]**
- `MediaQuery…size.width` להחלטה שתלויה במקום שהרכיב מקבל. דוגמאות היום: skeletons, רוחב חלונית צורת הדף, ידית `PanelOpenHandle`.
- החלטת פריסה לפי `Platform.isAndroid` או לפי orientation, כשהשאלה האמיתית היא רוחב. דוגמאות: סגירת חלונית ניווט אחרי מעבר, שורת כרטיסיות שנייה בשורת הכותרת.
- מספר קסם להשוואת רוחב בלי שם.

### 5.3 תרחישים נתמכים
| תרחיש | דרישה |
|---|---|
| מסך רחב (≥1200) | תוכן לוח מוגבל ל־860 וממורכז. חלוניות מוצמדות |
| מחשב נייד (840–1200) | כמו רחב. חלונית צד אחת מוצמדת לכל היותר |
| טאבלט (600–840) | חלוניות צפות עם scrim. דיאלוג `large` במסך מלא |
| טלפון (<600) | ניווט תחתון. דיאלוגים ברוחב מלא. שורות הגדרה בעמודה |
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
  - היום יש 42 שימושים ב־`Alignment.left/right`, 57 ב־`fromLTRB` ו־14 ב־`only(left/right)`. חלקם תקינים (גאומטריית ציור), והם יסווגו ב־baseline.
- **ממשק אנגלי:** כרום הממשק עטוף ב־`ChromeDirectionality`, ותוכן הספרים ב־`ContentDirectionality`. מחרוזת ממשק מתורגמת עוברת דרך `context.settingsText`. דיאלוג מתוך ההגדרות נפתח עם `settingsDialogBuilder`. **פער:** היקף מצב האנגלית לא מוגדר (UI-022, DD-20).
- **טקסט מעורב:** שם ספר עם מספרים, או אנגלית בתוך עברית. משתמשים בכיוון הבסיס של הפסקה ולא כופים כיוון. לנתיב או מזהה בתוך משפט עברי עוטפים את הקטע ב־`Text.rich` עם `TextSpan` שבו `textDirection: ltr`, או משתמשים בתווי בידוד (`⁦…⁩`).
- **מספרים:** ספרות מערביות בכל המקומות. גימטריה ואותיות עבריות לפי ההקשר.
- **קיצורי מקשים:** תמיד LTR, ובצורה אחידה `Ctrl+Shift+P` דרך `ShortcutHelper`.
- **אייקונים כיווניים:** ראו 2.5.1. אייקון Fluent עם `matchTextDirection` משתמש ב־`Icon` רגיל, **לא** ב־`RtlIcon`. זה מחכה לתיקון `RtlIcon` (UI-023).
- **LTR מכוון בתוך RTL:** עורך קוד או נתיב, פריסת מקלדת וכפתורי חלון של מערכת ההפעלה. עוטפים ב־`Directionality(ltr)` מקומי עם הערה של שורה אחת.

### 6.2 מקלדת ופוקוס [מחייב]
- כל פעולה זמינה במקלדת. סדר ה־Tab הוא סדר הקריאה (RTL) בתוך כל `FocusTraversalGroup`.
- ברשימה עם פריט נבחר, Tab נוחת עליו (`NavTreeFocusGroup` הוא הדפוס הקיים).
- טבעת פוקוס נראית. **אסור** `focusColor: Colors.transparent` בלי חלופה נראית. היום כך ב־`ToolResultCardShell`.
- Escape סוגר שכבה אחת (`EscapeLayers`) ולא יותר.
- רכיב מותאם (`GestureDetector`/`Listener`) שמגיב ללחיצה חייב גם `Focus`, `Semantics(button: true)` ו־Enter/Space. היום הרצועות של הכרטיסיות ו־`PanelOpenHandle` לא נגישים.

### 6.3 Semantics, tooltip, טקסט וניגודיות [מחייב]
- **שם נגיש:** לכל רכיב אינטראקטיבי. לכפתור אייקון זה ה־`tooltip`. לרכיב מותאם: `Semantics(label:)`.
- **מצב:**
  - נבחר: `Semantics(selected:)`. חסר היום בכרטיסיות, בפריטי ניווט ובשורות radio של ההגדרות.
  - מורחב: `expanded:`.
  - מושבת: `enabled:`.
  - נבחר בקבוצה: `inMutuallyExclusiveGroup` + `checked`.
- **הודעות:** `UiSnack` מכריז ב־`SemanticsService.announce`. מוצע לשנות זאת בתוך `UiSnack`.
- **הגדלת טקסט:**
  - אין `MediaQuery.withNoTextScaling` או `textScaler: TextScaler.noScaling` בממשק.
  - `RichText` גולמי מתעלם מהגדלת הטקסט של מערכת ההפעלה, ולכן משתמשים ב־`Text.rich`. היום ב־`RichText` משתמשים קטעי תוצאות, סרגל מונחי החיפוש ושורות אוצר החכמה.
  - כל פריסה נבדקת ב־`TextScaler.linear(1.3)` בלי גלישה. גובה קבוע לרכיב עם טקסט אסור. משתמשים ב־`minHeight`.
- **ניגודיות:**
  - טקסט רגיל ≥4.5:1, ורכיבים גרפיים וטקסט גדול ≥3:1. נבדק לכל זרע בבדיקות `test/theme/app_theme_data_test.dart`.
  - טקסט משני הוא `onSurfaceVariant`, לא `onSurface` בשקיפות.
  - צבע אינו הסימן היחיד למצב: נבחר מסומן גם במשקל או באייקון.
- **הפחתת תנועה:** ראו 2.5.5.
- **גופנים שונים:** הממשק נבדק עם גופן ממשק אחד שנקבע ב־DD-01. אסור להניח רוחב תו קבוע: אין רוחב בפיקסלים שמחושב מאורך מחרוזת.

---

## 7. מצבי משתמש וערכות נושא (ב.7)

| הגדרה | איפה נשמרת | איפה מוחלת | היקף | הערות |
|---|---|---|---|---|
| ערכת צבע (seed), בהיר | `SettingsBloc.seedColor` | `app.dart:43` → `createColorScheme` | גלובלי, כל הכרום | 14 זרעים. ל"לבן" ול"פרגמנט" יש override לסולם המשטחים |
| ערכת צבע, כהה | `darkSeedColor` | כנ"ל | גלובלי | הבורר עורך רק את הזרע של הבהירות הנוכחית |
| בהיר/כהה/מערכת | `isDarkMode`, `followSystemTheme` | `MaterialApp.themeMode` | גלובלי | |
| גופן קריאה, גודל, גובה שורה | `SettingsState.fontFamily/fontSize/lineHeight` | הקורא, קטעי תוצאות, ייצוא | **תוכן בלבד** | לא משפיע על הממשק, ונשאר כך **[מחייב]** |
| גופן וגודל של מפרשים | `commentators*` | תוכן | תוכן בלבד | |
| פרופיל תצוגת טקסט (ניקוד, טעמים) | `TextDisplayProfile` | תוכן | תוכן ו־export | |
| "צפיפות ממשק" | `compactMenuMode` | 68 קריאות ישירות, `AppMenuMetrics` (זהה בשני המצבים) | **בפועל: סרגלים, שדות ותפריטים, באופן לא עקבי** | DD-10: להפוך ל־`AppDensity` אמיתי, או לשנות את שם ההגדרה |
| שפת ההגדרות | `settingsLanguageCode` (ברירת מחדל "מערכת") | `SettingsTextScope`, `ChromeDirectionality` | ההגדרות, הכרום והניווט. **לא:** הודעות, תוויות ברירת מחדל של דיאלוגים ו־locale של Material | DD-20 |
| גודל ממשק | **אין** | — | — | מוצע לא להוסיף. מספיקה הגדלת הטקסט של מערכת ההפעלה (6.3) |
| גופן ממשק | **אין** ('Roboto' שאינו כלול) | — | — | DD-01 |
| הגדרות תפריטים (הצגת פריטים) | `SettingsState` (מקשים שונים) | תפריטי הקשר | תוכן התפריט, לא מראה | לא שייך למערכת העיצוב |

**[מחייב]**
1. החלפת ערכת נושא לא מחייבת שינוי ברכיבים. רכיב שבודק `brightness == Brightness.dark` כדי לבחור צבע מפר את התקן: ההחלטה שייכת ל־`AppSurfaces` או ל־ThemeExtension. היום יש 57 בדיקות כאלה מחוץ ל־`lib/theme`.
2. הגדרות קריאה והגדרות ממשק נשארות נפרדות. לא מאחדים אותן ל"גודל טקסט" אחד.
3. תוספים (WebView) מקבלים את ערכת הנושא דרך `buildThemePayloadFromScheme`. כשמוסיפים טוקן משטח או גופן ממשק, מוסיפים אותו גם ל־payload (DD-25).

---

## נספח א' — מקור אמת לכל סוג הגדרה

| סוג | מקור אמת אחד | מקורות מתחרים שיש להסיר |
|---|---|---|
| תפקידי צבע | `AppThemeData.createColorScheme` | בנייה נוספת ב־`main_window_screen.dart:3352` (להחליף בקריאה משותפת) |
| משטחים ומצבים | `AppSurfaces` (→ ThemeExtension לפי DD-19) | שקיפויות מקומיות, `primaryColor`, ענפי `isDark` בפיצ'רים |
| טיפוגרפיית ממשק | `ThemeData.textTheme` (מלא, DD-02) | `AppTokens.font*` בפיצ'רים, `AppTextStyles` מחוץ להגדרות, `AppTopBar.titleStyle`, `fontSize:` מספרי |
| גופן ממשק | `ThemeData.fontFamily`/`fontFamilyFallback` (DD-01) | 8 מופעים של `'Roboto'` קשיח, `'Rubik'` ב־payload התוספים |
| טיפוגרפיית תוכן | `SettingsState` + `AppFonts` | `Settings.getValue('key-font-family')` ב־build |
| ריווח | `AppTokens.space*` + טוקנים סמנטיים | מספרים קשיחים |
| רדיוסים | `AppTokens.radius*` | `circular(n)` |
| גבהים | `AppInputTokens` + `AppDensity` | `heightCompact` ב־`OtzariaSearchField`, גבהים ב־`AppTopBar`/`BarButton` |
| גדלי אייקון | `AppTokens.icon*` (מוצע) | טוקני גופן כגודל אייקון, מספרים |
| אנימציות | `AppTokens.anim*`, `curve*`, `AppMotion` | ~90 משכים קשיחים |
| הגדרות דיאלוג | `lib/widgets/dialogs/` (`AppDialogSize`) | 8 מסגרות, רוחבים קשיחים |
| פריסות מסך | `lib/widgets/layout/`, `navigation/` | מעטפות מקומיות |
| רכיבי ניווט | `NavSidePanel`, `NavRailItem`, `NavTreeTile` | — |
| רספונסיביות | `LayoutBreakpoints` + `WindowClass` (מוצע) | 32 ספים קשיחים |
| צפיפות | `AppDensity` (מוצע) | 68 קריאות ל־`compactMenuMode` |
