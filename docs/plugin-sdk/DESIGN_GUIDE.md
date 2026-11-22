# מדריך עיצוב לתוספי אוצריא

המדריך הזה אומר איך לבנות ממשק של תוסף HTML/WebView כך שייראה ויתנהג כמו חלק מאוצריא, בלי לנחש צבעים, גדלים, אייקונים או התנהגות.

- **דוגמה חיה שאפשר להריץ:** [`examples/design-gallery`](examples/design-gallery) מציגה כל רכיב שבמדריך, בכל ערכות הנושא וברוחבים שונים. [איך מריצים](#דוגמה-חיה-תוסף-design-gallery).
- **מקור האמת לצבעים, ריווח וגדלים** הוא מערכת העיצוב של האפליקציה; המדריך הזה מתרגם אותה ל-CSS. התוסף מקבל את הערכים מהאפליקציה בזמן ריצה (ה-payload של ה-theme), ולא מקודד אותם.
- **כל דוגמה כאן נבדקת אוטומטית:** קטעי ה-CSS וה-HTML עוברים את בדיקת העיצוב של הוולידטור, כל `Otzaria.call` ו-`Otzaria.on` קיימים ב-[`spec.json`](spec.json), וטבלת הטוקנים תואמת ל-payload האמיתי (`test/plugins/design_guide/`).

## בקצרה: עשר ההנחיות

1. צבעים רק מ-`var(--color-*)` ומ-`var(--surface-*)`; לעולם לא hex, `rgb()` או שם צבע.
2. מקבלים את ה-theme ב-`plugin.boot`, מחילים אותו, ומאזינים ל-`theme.changed`.
3. רקע הדף `--surface-panel`, כרטיס `--surface-card`, פס כותרת `--surface-top-bar`.
4. רדיוס אחד, `var(--radius)` (8). בלי גלולות ובלי פינות אחרות.
5. גופן הממשק `var(--font-ui)`; גופן הקריאה `var(--font-main)` רק לטקסט של ספרים. גודל גופן הקריאה של המשתמש אינו גודל הממשק.
6. ריווח מהסולם (`--space-*`), גבהי פקדים מ-`--tap-target` ו-`--field-height`.
7. כותרת התוסף בפס עליון קבוע, בגובה `var(--top-bar-height)`; התוכן הוא שגולל.
8. `<html lang="he" dir="rtl">`, ולוגיקה בכיוון (`inset-inline`, `padding-inline`) ולא ב-`left`/`right`.
9. פריסה לפי רוחב המכל (`@container`), לא לפי רוחב החלון, ויעדי מגע 48.
10. אייקונים כ-SVG inline ב-`currentColor`; מצבים (hover, focus, disabled) לפי [טבלת המצבים](#מצבים).

## מה אחיד ומה חופשי

האחידות מתבטאת במה שהמשתמש מרגיש בין מסך של אוצריא למסך של תוסף. מה שנוגע ב"כרום" אחיד; התוכן שלכם חופשי.

| אחיד עם האפליקציה (לא משנים) | חופשי לתוסף |
|---|---|
| תפקידי הצבע, המשטחים (`panel`, `card`, `topBar`) וצבעי המצב | מבנה הדף, הפריסה, מספר העמודות |
| רדיוס 8 לכל רכיב מלבני | התוכן, הטקסטים, שמות הכפתורים |
| גובה פקד: שדה `--field-height`, כפתור ושורה `--tap-target` | גופן הקריאה של תוכן ספרים: אחד מהגופנים המובנים |
| גופן הממשק וסולם הטקסט (11, 12, 14, 16, 18, 22) | איורים, תמונות וגרפים (צבעי נתונים מתפקידי הצבע, לא פלטה קבועה) |
| פס כותרת עליון קבוע בגובה `--top-bar-height` | תנועה עדינה (עד `--motion-normal`), ובכפוף להפחתת תנועה |
| מצבי hover, pressed, focus, disabled, selected | אילו רכיבים מציגים ובאיזה סדר |
| כיוון RTL וסימון שפה | אייקונים בתוך הדף (SVG), בקו אחד ובמשקל אחיד |
| ניגודיות לפי [ההנחיות שלמטה](#ניגודיות) | רוחב מקסימלי של התוכן (ברירת מחדל באפליקציה: 860 ללוחות) |

**אין** תוסף שמגדיר "צבע מותג" במקום `primary`, מצב כהה משלו, רדיוס אחר או גופן ממשק אחר. המשתמש בחר ערכה אחת לכל האפליקציה, ותוסף שחורג ממנה נראה שבור בחלק מהערכות.

---

## ערכת נושא

### איך ה-theme מגיע

| מסלול | מתי | מה מקבלים |
|---|---|---|
| `plugin.boot` | פעם אחת בטעינת הדף | `payload.theme`: ה-payload המלא |
| `theme.changed` | המשתמש או המערכת משנים משהו שמשפיע על הערכה ([הרשימה](#מתי-נשלח-themechanged)) | `ThemePayload` מלא (לא הפרש) |
| `app.getTheme` | לפי דרישה | אותו מבנה, במעטפת `{ success, data }` |

```javascript
Otzaria.on('plugin.boot', (payload) => applyTheme(payload.theme));
Otzaria.on('theme.changed', (theme) => applyTheme(theme));
```

`events.subscribe:theme.changed` היא **הרשאת בסיס** (מ-0.9.97): ניתנת לכל תוסף אוטומטית, ואין להצהיר עליה ב-`manifest.json` (הוולידטור מזהיר על הצהרה מיותרת). תוסף שתומך ב-`minAppVersion` שנמוך מ-0.9.97 מצהיר עליה, כי במארח כזה היא עדיין נדרשת.

ב-boot משתמשים ב-`payload.theme` ולא קוראים ל-`app.getTheme` מיד. `app.getTheme` נועד לרענון אחרי שהתוסף כבר רץ, למשל ב-`plugin.resumed`.

### מבנה אובייקט ה-theme

```javascript
{
  mode: "light" | "dark",
  colorScheme: { /* 32 תפקידי צבע, hex: הטבלה למטה */ },
  typography: {
    fontFamily:             "FrankRuhlCLM",     // גופן הקריאה: לטקסט של ספרים בלבד
    fontSize:               25,                 // גודל הקריאה של המשתמש (px). אינו גודל הממשק!
    lineHeight:             1.5,                // גובה שורה לטקסט קריאה
    commentatorsFontFamily: "NotoRashiHebrew",  // גופן מפרשים
    commentatorsFontSize:   22,                 // גודל מפרשים (px)
    uiFontFamily:           "Rubik",            // גופן ממשק לתאימות (0.9.97)
    uiFont:                 "'Segoe UI', …, system-ui, sans-serif", // גופן הממשק של אוצריא עצמה (0.9.99)
  },
  // מ-0.9.99. אופציונליים: מארח ישן אינו שולח אותם.
  surfaces: {
    reader: "#...", panel: "#...", card: "#...", topBar: "#...",
    regionBorder: "#..." | null,                  // קו בין אזורים; רק בערכת "לבן" בבהיר, אחרת null
    warning: "#...", onWarning: "#...",           // אזהרה: אייקון, מסגרת וטקסט מודגש
    warningContainer: "#...", onWarningContainer: "#...", // רקע באנר/תגית אזהרה
  },
  radius:  8,                                                  // px
  spacing: { "2xs": 2, xs: 4, sm: 8, smd: 12, md: 16, lg: 24, xl: 32 }, // px
  density: { compact: false, topBarHeight: 56, fieldHeight: 48 },      // "צפיפות ממשק"
}
```

> **קו האזורים וצבעי האזהרה.** בערכת "לבן" בבהיר האזורים כמעט באותו לבן, ולכן האפליקציה מפרידה ביניהם בקו דק (`regionBorder`, ובאותו צבע גם סביב פריט נבחר). בכל ערכה אחרת הוא `null`, וההפרדה היא בגוון. תוסף שרוצה להיראות כמו האפליקציה מציב `1px solid var(--surface-region-border)` על פס הכותרת, חלונית צד, תפריט ודיאלוג: כשאין קו המשתנה שקוף. צבעי האזהרה (`warning*`) הם אלה של שבב ובאנר האזהרה באפליקציה.

> **המשטחים הם הרקע של האפליקציה, לא `surface`.** במצב כהה רקע הלוח של אוצריא אינו אף תפקיד של `colorScheme`. תוסף שרוצה להיראות כמו מסך כלים מקורי צובע את הטאב ב-`surfaces.panel`, את פס הכותרת ב-`surfaces.topBar` ואת הכרטיסים ב-`surfaces.card`.

> **גופן הקריאה אינו גודל הממשק.** `typography.fontSize` הוא גודל הגופן ש**המשתמש בחר לקריאת ספרים** (ברירת מחדל 25, טווח 16-36). הוא חל על טקסט ספר בלבד, ואצל אוצריא הוא אינו משפיע על הממשק. אל תגזרו ממנו את גודל הכפתורים והתוויות; לממשק יש סולם קבוע ([טיפוגרפיה](#טיפוגרפיה-וגופנים)).

### טבלת הטוקנים

זו הרשימה הקנונית: כל שדה ב-payload, לאיזה משתנה CSS הוא הופך, ולמה משתמשים בו. `applyTheme` שלמטה מציב בדיוק את המשתנים האלה, ובדיקת חוזה נכשלת אם שדה נוסף ל-payload בלי להיכנס לכאן.

**א. משתנים שמגיעים מה-payload**

| משתנה CSS | שדה ב-payload | שימוש |
|---|---|---|
| `--color-primary` | `colorScheme.primary` | כפתור ראשי, קישור, טבעת פוקוס, כותרת מקטע |
| `--color-on-primary` | `colorScheme.onPrimary` | טקסט ואייקון על `primary` |
| `--color-primary-container` | `colorScheme.primaryContainer` | הדגשה עדינה: סימון חיפוש (`mark`), תגית ראשית |
| `--color-on-primary-container` | `colorScheme.onPrimaryContainer` | טקסט על `primaryContainer` |
| `--color-secondary` | `colorScheme.secondary` | הדגשות משניות |
| `--color-on-secondary` | `colorScheme.onSecondary` | טקסט על `secondary` |
| `--color-secondary-container` | `colorScheme.secondaryContainer` | נבחר, כפתור משני (tonal), תגית "הצלחה" |
| `--color-on-secondary-container` | `colorScheme.onSecondaryContainer` | טקסט על `secondaryContainer` |
| `--color-tertiary` | `colorScheme.tertiary` | הדגשה שלישונית (נדיר) |
| `--color-on-tertiary` | `colorScheme.onTertiary` | טקסט על `tertiary` |
| `--color-tertiary-container` | `colorScheme.tertiaryContainer` | הדגשה שלישונית רכה (נדיר). אזהרה היא `--surface-warning-container` |
| `--color-on-tertiary-container` | `colorScheme.onTertiaryContainer` | טקסט על `tertiaryContainer` |
| `--color-surface` | `colorScheme.surface` | רקע בסיס; כרטיס בערכה בהירה (דרך `--surface-card`) |
| `--color-on-surface` | `colorScheme.onSurface` | טקסט ראשי |
| `--color-on-surface-variant` | `colorScheme.onSurfaceVariant` | טקסט משני, תוויות, אייקוני פעולה |
| `--color-surface-container-lowest` | `colorScheme.surfaceContainerLowest` | שכבת רקע נמוכה ביותר |
| `--color-surface-container-low` | `colorScheme.surfaceContainerLow` | שכבת רקע נמוכה |
| `--color-surface-container` | `colorScheme.surfaceContainer` | כרטיס בתוך כרטיס (`inset`) |
| `--color-surface-container-high` | `colorScheme.surfaceContainerHigh` | תפריט, דיאלוג, פס כותרת (כמו `--surface-top-bar`) |
| `--color-surface-container-highest` | `colorScheme.surfaceContainerHighest` | תגית ניטרלית, באנר מידע |
| `--color-error` | `colorScheme.error` | שגיאה: גבול שדה, טקסט שגיאה, כפתור מסוכן |
| `--color-on-error` | `colorScheme.onError` | טקסט על `error` |
| `--color-error-container` | `colorScheme.errorContainer` | באנר שגיאה, כפתור מסוכן רך |
| `--color-on-error-container` | `colorScheme.onErrorContainer` | טקסט על `errorContainer` |
| `--color-outline` | `colorScheme.outline` | גבול שדה, מפריד חזק |
| `--color-outline-variant` | `colorScheme.outlineVariant` | גבול כרטיס ומפריד עדין |
| `--color-inverse-surface` | `colorScheme.inverseSurface` | רקע הפוך (tooltip, הודעה כהה) |
| `--color-on-inverse-surface` | `colorScheme.onInverseSurface` | טקסט על `inverseSurface` |
| `--color-inverse-primary` | `colorScheme.inversePrimary` | `primary` על רקע הפוך |
| `--color-shadow` | `colorScheme.shadow` | צבע הצל (דרך `--shadow-floating`) |
| `--color-scrim` | `colorScheme.scrim` | צבע הכיסוי (דרך `--scrim`) |
| `--color-surface-tint` | `colorScheme.surfaceTint` | גוון הגבהה; לא בשימוש בעיצוב שטוח |
| `color-scheme` | `mode` | פקדים מקוריים (פסי גלילה, שדות) לפי מצב האפליקציה |
| `--surface-reader` | `surfaces.reader` | רקע מסך עיון (ספר, PDF, חיפוש) |
| `--surface-panel` | `surfaces.panel` | רקע הדף של התוסף (לוח) |
| `--surface-card` | `surfaces.card` | רקע כרטיס, שדה וטבלה |
| `--surface-top-bar` | `surfaces.topBar` | רקע פס הכותרת |
| `--surface-region-border` | `surfaces.regionBorder` | קו דק בין אזורים: פס הכותרת, חלונית צד, תפריט, דיאלוג. רק בערכת "לבן" בבהיר; אחרת שקוף |
| `--surface-warning` | `surfaces.warning` | אזהרה: אייקון, מסגרת וטקסט מודגש |
| `--surface-on-warning` | `surfaces.onWarning` | טקסט ואייקון על `warning` |
| `--surface-warning-container` | `surfaces.warningContainer` | רקע באנר ותגית אזהרה |
| `--surface-on-warning-container` | `surfaces.onWarningContainer` | טקסט ואייקון על `warningContainer` |
| `--radius` | `radius` | רדיוס כל רכיב מלבני |
| `--space-2xs` | `spacing.2xs` | 2: מרווח בין שורות טקסט צמודות |
| `--space-xs` | `spacing.xs` | 4: בין אייקון לטקסט |
| `--space-sm` | `spacing.sm` | 8: בין פריטים קשורים וכפתורים |
| `--space-smd` | `spacing.smd` | 12: ריפוד שורה וכרטיס |
| `--space-md` | `spacing.md` | 16: ריפוד דף ודיאלוג, בין כרטיסים |
| `--space-lg` | `spacing.lg` | 24: בין מקטעים |
| `--space-xl` | `spacing.xl` | 32: שוליים של מסך רחב |
| `--top-bar-height` | `density.topBarHeight` | גובה פס הכותרת: 56, או 44 בצפיפות מצומצמת |
| `--field-height` | `density.fieldHeight` | גובה שדה: 48, או 36 בצפיפות מצומצמת |
| — | `density.compact` | הדגל עצמו; הגבהים כבר מוצבים לפיו |
| `--font-ui` | `typography.uiFont` | גופן הממשק של אוצריא (0.9.99) |
| `--font-ui` | `typography.uiFontFamily` | גופן ממשק במארח ישן (Rubik), כש-`uiFont` חסר |
| `--font-main` | `typography.fontFamily` | גופן קריאה: טקסט ספר בלבד |
| `--font-commentary` | `typography.commentatorsFontFamily` | גופן מפרשים |
| `--font-size-reading` | `typography.fontSize` | גודל הקריאה: טקסט ספר בלבד |
| `--font-size-commentary` | `typography.commentatorsFontSize` | גודל מפרשים |
| `--line-height-reading` | `typography.lineHeight` | גובה שורה בטקסט קריאה |

**ב. משתנים שמוגדרים ב-CSS ואינם ב-payload** (ערכי ברירת מחדל ב-`:root`, `css/tokens.css` בדוגמה)

| משתנה CSS | משמעות |
|---|---|
| `--tap-target` | שטח לחיצה מינימלי: 40, ו-48 במגע (`@media (pointer: coarse)`) |
| `--font-mono` | גופן קוד ונתיבים |
| `--text-headline` | 22: כותרת ראשית (מסך ריק גדול) |
| `--text-title` | 18: כותרת דיאלוג וכותרת פס |
| `--text-section` | 16: כותרת מקטע (700, `primary`) |
| `--text-body` | 16: טקסט גוף |
| `--text-body-sm` | 14: גוף משני, כותרת כרטיס, תווית כפתור |
| `--text-meta` | 12: מטא, מונים, תגיות |
| `--text-micro` | 11: תווית זעירה |
| `--state-hover` | שכבת hover: `on-surface` ב-8% |
| `--state-pressed` | שכבת לחיצה: `on-surface` ב-12% |
| `--disabled-fg` | טקסט מושבת: `on-surface` ב-38% |
| `--disabled-bg` | רקע מושבת: `on-surface` ב-12% |
| `--focus-ring` | טבעת פוקוס מקלדת: 2px `primary` |
| `--shadow-floating` | צל לתפריט, tooltip וחלונית צפה בלבד |
| `--scrim` | כיסוי מאחורי דיאלוג וחלונית |
| `--motion-fast` | 150ms |
| `--motion-normal` | 250ms |

### ברירות מחדל לפני ה-boot

הדף מוצג עוד לפני שה-theme מגיע, ומארח ישן אינו שולח את כל השדות. לכן `:root` מגדיר ערך לכל משתנה. הגדרת custom property אינה נבדקת כצבע קשיח, וזו הדרך הנכונה להחזיק hex בקוד:

```css
:root {
  color-scheme: light;
  --color-primary: #6750a4;
  --color-on-primary: #ffffff;
  --color-surface: #fffbfe;
  --color-on-surface: #1c1b1f;
  /* ... כל 32 התפקידים: examples/design-gallery/css/tokens.css */

  --surface-panel: var(--color-surface);
  --surface-card: var(--color-surface);
  --surface-top-bar: var(--color-surface-container-high);
  --surface-region-border: transparent;
  --surface-warning-container: var(--color-tertiary-container);
  --surface-on-warning-container: var(--color-on-tertiary-container);
  --radius: 8px;
  --space-md: 16px;
  --top-bar-height: 56px;
  --field-height: 48px;
  --font-ui: system-ui, 'Segoe UI', sans-serif;
  --font-main: 'FrankRuhlCLM', 'David', serif;
}

body {
  font-family: var(--font-ui);
  background: var(--surface-panel);
  color: var(--color-on-surface);
}
```

ה-WebView אינו שקוף: עד ה-boot מוצגים ערכי ה-`:root` שלכם, ולכן משתמש בערכה כהה עלול לראות הבהוב קצר של ברירת המחדל. אל תנפישו מעבר בין ערכות, ואל תשתמשו ב-`prefers-color-scheme` כדי "לנחש" את הערכה ([למה לא](#בהיר-וכהה)).

### פונקציית applyTheme

זו הפונקציה היחידה שצריך. היא מציבה כל שדה ב-payload כמשתנה CSS לפי [הטבלה](#טבלת-הטוקנים), מדלגת על שדות שחסרים (מארח ישן), מוחקת משתנה שנעלם בין שתי ערכות, ומחילה גם על אלמנט בודד ולא רק על הדף (לתצוגה של כמה ערכות במקביל). היא מצוטטת כאן מילה במילה מ-`examples/design-gallery/js/theme.js`:

```javascript
// applyTheme: ממיר את ה-payload של ה-theme למשתני CSS.
// הקובץ הזה הוא המקור היחיד: DESIGN_GUIDE.md מצטט אותו מילה במילה, ובדיקת חוזה
// מוודאת שהשניים זהים ושכל שדה ב-payload נמצא בטבלת הטוקנים.
(function () {
  const applied = new WeakMap(); // אלמנט -> שמות המשתנים שהוצבו בו בפעם הקודמת

  // onSurfaceVariant -> on-surface-variant
  const kebab = (key) => key.replace(/[A-Z]/g, (m) => '-' + m.toLowerCase());

  /**
   * target: האלמנט שמקבל את המשתנים. ברירת מחדל: כל הדף. בתצוגה של כמה ערכות
   * במקביל מוחלת ערכה על מסגרת, לא על :root.
   */
  window.applyTheme = function applyTheme(theme, target) {
    // מארח שהחלון שלו אינו מחובר מחזיר colorScheme ריק; אין מה להחיל.
    if (!theme || !theme.colorScheme || !theme.colorScheme.primary) return;
    const el = target || document.documentElement;
    const next = {};
    const set = (name, value) => {
      if (value !== undefined && value !== null && value !== '') {
        next[name] = String(value);
      }
    };

    const cs = theme.colorScheme;
    Object.keys(cs).forEach((key) => set('--color-' + kebab(key), cs[key]));

    // מ-0.9.99. במארח ישן השדות חסרים, והערכים נשארים אלה שב-:root.
    const s = theme.surfaces || {};
    set('--surface-reader', s.reader);
    set('--surface-panel', s.panel);
    set('--surface-card', s.card);
    set('--surface-top-bar', s.topBar);
    set('--surface-region-border', s.regionBorder);
    set('--surface-warning', s.warning);
    set('--surface-on-warning', s.onWarning);
    set('--surface-warning-container', s.warningContainer);
    set('--surface-on-warning-container', s.onWarningContainer);
    if (theme.radius != null) set('--radius', theme.radius + 'px');
    const spacing = theme.spacing || {};
    Object.keys(spacing).forEach((key) => set('--space-' + key, spacing[key] + 'px'));
    const d = theme.density || {};
    if (d.topBarHeight != null) set('--top-bar-height', d.topBarHeight + 'px');
    if (d.fieldHeight != null) set('--field-height', d.fieldHeight + 'px');

    const t = theme.typography || {};
    // גופן הממשק: uiFont (0.9.99) הוא מה שאוצריא מציירת; Rubik הוא fallback למארח ישן.
    if (t.uiFont) set('--font-ui', t.uiFont);
    else if (t.uiFontFamily) set('--font-ui', "'" + t.uiFontFamily + "', system-ui, sans-serif");
    // גופני הקריאה: רק לטקסט של ספרים, לא לממשק.
    if (t.fontFamily) set('--font-main', "'" + t.fontFamily + "', 'David', serif");
    if (t.commentatorsFontFamily) {
      set('--font-commentary', "'" + t.commentatorsFontFamily + "', 'David', serif");
    }
    if (t.fontSize) set('--font-size-reading', t.fontSize + 'px');
    if (t.commentatorsFontSize) set('--font-size-commentary', t.commentatorsFontSize + 'px');
    if (t.lineHeight) set('--line-height-reading', t.lineHeight);

    // משתנה שהוצב בפעם הקודמת ואינו ב-payload הנוכחי מוסר, כדי שלא יישאר ערך ישן.
    (applied.get(el) || []).forEach((name) => {
      if (!(name in next)) el.style.removeProperty(name);
    });
    Object.keys(next).forEach((name) => el.style.setProperty(name, next[name]));
    applied.set(el, Object.keys(next));

    // פקדים מקוריים (פסי גלילה, שדות) לפי מצב האפליקציה, לא לפי המערכת.
    el.style.colorScheme = theme.mode === 'dark' ? 'dark' : 'light';
    // למקרה נדיר שדרוש הבדל מבני בין מצבים (למשל וריאנט תמונה); לא לבחירת צבע.
    el.setAttribute('data-theme-mode', theme.mode === 'dark' ? 'dark' : 'light');
  };
})();
```

הערות:

- `colorScheme` ריק (`{}`) מגיע כשחלון התוסף אינו מחובר בזמן הבקשה; ה-guard בראש הפונקציה מונע קריסה.
- מארח ישן אינו שולח `surfaces`, `spacing`, `density`, `radius` ו-`uiFont`. הערכים נשארים אלה שב-`:root`.
- `el.style.colorScheme` גורם לפקדים המקוריים (פסי גלילה, תיבות סימון) להיראות לפי **מצב האפליקציה** ולא לפי מצב המערכת.

## מה הוולידטור אוכף

הוולידטור של החנות (גם `otzaria pack-plugin`, מצב תיקיית פיתוח והעלאה לחנות) בודק את הקבצים `.html` ו-`.css` ומדווח "מראה תואם לאוצריא". הכללים:

| כלל | מה נפסל | מה עובד |
|---|---|---|
| שורש | `<html>` בלי `dir="rtl"` או בלי `lang="he"` | `<html lang="he" dir="rtl">` |
| צבעים | `#xxx`, `rgb()`, `rgba()`, `hsl()`, שמות צבע (`white`) בערכי `color`, `background`, `border`, `outline`, `fill`, `stroke` | `var(--color-*)`, `transparent`, `currentcolor`, `inherit`, `none` |
| גופן | `font-family` שאינו `var(--font-*)` ואינו אחד מ-`inherit`, `initial`, `unset`, `system-ui` | `font-family: var(--font-ui)` (לממשק) או `var(--font-main)` (לטקסט ספר). `inherit` על כפתור או שדה מותר. `font-family` בתוך `@font-face` אינו נבדק (בבודק שבאפליקציה; בבודק של החנות עד שיתעדכן הוא עדיין נפסל, ראו [מתכון ד'](COOKBOOK.md)) |
| גודל גופן | `font-size` ב-`px` | `em`, `rem`, `%`, `var(--text-*)`. `px` מותר רק בסלקטור שמכיל `topbar` או `top-bar` |
| רדיוס | `border-radius` ב-`px` | `var(--radius)`, `0`, `50%` |
| שימוש | קבצים שבהם אין אף `var(--color-*)` | לפחות שימוש אחד |

**מוצא החירום:** הוולידטור מדלג על הגדרות של custom properties (`--name: value;`). צל וכיסוי, שנחוצים ב-`rgba`, מוגדרים כך ונצרכים דרך `var()`:

```css
:root {
  --shadow-floating: 0 2px 8px color-mix(in srgb, var(--color-shadow) 24%, transparent);
  --scrim: color-mix(in srgb, var(--color-scrim) 32%, transparent);
}

.menu {
  box-shadow: var(--shadow-floating);
}
```

הודעות הכשל של הוולידטור מפנות לטוקנים האלה: `var(--radius) (8)` ללא גלולות, `var(--font-ui)` לממשק או `var(--font-main)` לטקסט ספר, ו-`var(--text-*)` (או `em`/`rem`) לגודל. כללי העיצוב עצמם (מילות המפתח המותרות, הסלקטור של הסרגל העליון, ההודעות) מתפרסמים ב-[`spec.json`](spec.json) תחת `designRules`, כדי שהעותק של החנות לא יסטה מהעותק שבאפליקציה.

מה שהוולידטור **אינו** בודק, ועדיין חלק מהחוזה: ריווח, גבהים, `font` המקוצר, סגנונות ב-`style=""`, צבעים שמוצבים מ-JS, ו-`fill` ב-SVG. אל תנצלו את זה: הבדיקה היא רשת ביטחון, והמדריך הוא החוזה.

---

## צבעים, מצבים וניגודיות

### בחירת צבע לפי תפקיד

בוחרים **תפקיד**, לא גוון. הסדר: תפקיד של `colorScheme`; אם אין מתאים, משטח מ-`surfaces`; ואם גם זה חסר, לא ממציאים צבע אלא פותחים בקשה (ראו [תאימות](#תאימות-גרסאות)).

- טקסט על רקע `X` נצבע ב-`onX` (`on-primary` על `primary`, `on-error-container` על `error-container`). לעולם לא `on-surface` על `primary`.
- טקסט משני הוא `--color-on-surface-variant`, **לא** `--color-on-surface` בשקיפות.
- גבול כרטיס ומפריד עדין: `--color-outline-variant`. גבול שדה ומפריד חזק: `--color-outline`.
- אזהרה: `--surface-warning-container` עם `--surface-on-warning-container` (רקע וטקסט), ו-`--surface-warning` לאייקון ולמסגרת. במארח לפני 0.9.99 הם נשארים ערכי ה-`:root`, שנופלים ל-`tertiary-container`.
- הצלחה באוצריא היא הגוון **הניטרלי** (`secondary-container`), לא ירוק.
- אין לבחור צבע לפי `mode`. החלטה כזו שייכת לאפליקציה, ו-`mode` כבר מובנה בתפקידים.

### מצבים

כל פקד אינטראקטיבי מציג את אותם מצבים. השכבות נוצרות מצבע ה-`on` של הרכיב, כמו באפליקציה:

| מצב | איך |
|---|---|
| רגיל | צבעי התפקיד |
| hover | שכבה של 8% מצבע ה-on של הרכיב (`::before` עם `opacity: 0.08`, או `--state-hover` על שורה וכרטיס) |
| pressed | שכבה של 12% |
| focus מקלדת | `outline: var(--focus-ring)` עם `outline-offset: 2px`, רק ב-`:focus-visible`. אסור `outline: none` בלי חלופה גלויה |
| נבחר | `secondary-container` ובנוסף סימן שאינו צבע: משקל, אייקון `check` או גבול (צבע אינו הסימן היחיד) |
| מושבת | `--disabled-fg` על `--disabled-bg`, ו-`cursor: default`. לא `opacity` על כל הרכיב |
| שגיאה | גבול `--color-error` ו-`aria-invalid="true"`, וטקסט שגיאה `--color-error` מתחת לשדה |
| טוען | `aria-busy="true"`, ספינר בתוך הכפתור ורוחב קבוע (התווית נשארת, מוסתרת) |

```css
.btn {
  --overlay: var(--color-on-secondary-container);
  position: relative;
  isolation: isolate;
  background: var(--color-secondary-container);
  color: var(--color-on-secondary-container);
}

.btn::before {
  content: '';
  position: absolute;
  inset: 0;
  z-index: -1;
  border-radius: inherit;
  background: var(--overlay);
  opacity: 0;
  pointer-events: none;
}

.btn:hover::before {
  opacity: 0.08;
}

.btn:active::before,
.btn:focus-visible::before {
  opacity: 0.12;
}

.btn:focus-visible {
  outline: var(--focus-ring);
  outline-offset: 2px;
}

.btn:disabled {
  background: var(--disabled-bg);
  color: var(--disabled-fg);
  cursor: default;
}
```

במגע אין hover: אל תסתירו פעולה או מידע מאחורי hover בלבד.

### ניגודיות

- טקסט רגיל: יחס ניגודיות של לפחות **4.5:1**; טקסט גדול ורכיבים גרפיים (אייקון, גבול של פקד): **3:1**.
- זוגות `X` ו-`onX` מובטחים לעבור בכל ערכות האפליקציה (נבדק בבדיקות של האפליקציה). שילוב אחר, למשל `on-surface-variant` על `primary-container`, אינו מובטח: השתמשו בזוג שהוגדר.
- טקסט על תמונה או על רקע שאינו מ-theme: הוסיפו רקע מ-theme מאחוריו.
- אל תסתמכו על צבע לבד: נבחר, שגיאה ופעיל מסומנים גם בצורה (משקל, אייקון, גבול, טקסט).
- רכיב מושבת פטור מדרישת הניגודיות, אבל עדיין חייב להיראות מושבת.

## טיפוגרפיה וגופנים

יש שני סולמות נפרדים, ואסור לערבב:

| | גופן | גודל | לאן |
|---|---|---|---|
| **ממשק** | `var(--font-ui)` | סולם קבוע: `--text-*` (11, 12, 14, 16, 18, 22) | כפתורים, תפריטים, שדות, כותרות, תוויות, מטא |
| **קריאה** | `var(--font-main)`, `var(--font-commentary)` | `--font-size-reading`, `--font-size-commentary` | טקסט של ספרים ומפרשים בלבד |

סולם הממשק (כמו באפליקציה):

| תפקיד | משתנה | משקל |
|---|---|---|
| כותרת ראשית (מצב ריק גדול) | `--text-headline` (22) | 600 |
| כותרת דיאלוג ופס | `--text-title` (18) | 600 |
| כותרת מקטע | `--text-section` (16) | 700, צבע `primary` |
| גוף | `--text-body` (16) | 400 |
| גוף משני, כותרת כרטיס, תווית כפתור | `--text-body-sm` (14) | 400 / 600 / 500 |
| מטא, תגית, מונה, טקסט שגיאה בשדה | `--text-meta` (12) | 400 / 500 |
| תווית זעירה | `--text-micro` (11) | 500 |

```css
body {
  font-family: var(--font-ui);
  font-size: var(--text-body);
  line-height: 1.5;
}

.card-title {
  font-size: var(--text-body-sm);
  font-weight: 600;
}

/* טקסט של ספר: גופן הקריאה, בגודל שהתוסף קובע */
.excerpt {
  font-family: var(--font-main);
  font-size: var(--text-body);
  line-height: 1.6;
}
```

- **טקסט ספר בתוך כרטיס** (תוצאת חיפוש, קטע) הוא בגודל הממשק. רק תוסף שהוא **קורא** (מציג את טקסט הספר כמסמך) משתמש ב-`--font-size-reading`.
- **`uiFont` במקום Rubik.** אוצריא מציירת את הממשק בגופן המערכת (Segoe UI ב-Windows). `applyTheme` מציב את `uiFont` ב-`--font-ui`, ו-Rubik (`uiFontFamily`) הוא רק fallback למארח שלפני 0.9.99. כך הכפתורים בתוסף נראים כמו הכפתורים שמסביב. אם צריך מראה זהה בכל פלטפורמה, אפשר להשתמש ב-`uiFontFamily`, אבל הוא יראה שונה מהאפליקציה.
- **אל תניחו רוחב תו.** גופן המערכת משתנה בין פלטפורמות: אין לחשב רוחב בפיקסלים מאורך מחרוזת.
- **מספרים:** ספרות מערביות. בעמודות מספרים השתמשו ב-`font-variant-numeric: tabular-nums` וביישור לסוף.
- **גופן קבוע** (נתיב, מזהה, קיצור): `var(--font-mono)`.
- **גובה שורה:** 1.5 לממשק; `--line-height-reading` לטקסט קריאה.
- `rem` נקבע לפי `html`, לא לפי משתנה כלשהו: אל תניחו ש-`1rem` הוא "גודל הממשק". השתמשו ב-`--text-*`.

### גופנים מובנים

כל הגופנים המובנים של אוצריא (`FrankRuhlCLM`, `TaameyDavidCLM`, `Shofar`, `NotoRashiHebrew`, `KeterYG`, `NotoSerifHebrew`, `Tinos`, `Rubik`, `TaameyAshkenaz`) רשומים כ-`@font-face` ב-WebView **עוד לפני `plugin.boot`**, ואיתם גם גופן מערכת שהמשתמש בחר בהגדרות. אין צורך לארוז קבצי גופן. כל משפחה נשלחת עם ה-face הבולד האמיתי שלה, כך ש-`font-weight: bold` מצייר אות אמיתית ולא עיבוי מלאכותי.

```css
:root {
  --font-main: 'FrankRuhlCLM', 'David', serif;
}

.excerpt {
  font-family: var(--font-main);
}
```

**מתי הגופן מוכן למדידה:** לפני `plugin.boot` אוצריא ממתינה **עד 1.5 שניות** לטעינת המשפחות שב-`typography` (`fontFamily`, `commentatorsFontFamily`, `uiFontFamily`). זו אינה הבטחה: ב-macOS, ב-iOS ובמסלול החלופי אין המתנה. תוסף שצריך ודאות לפני מדידת טקסט (canvas, `getBoundingClientRect`) ממתין בעצמו:

```javascript
await document.fonts.load("16px 'FrankRuhlCLM'");
```

אוצריא מוסיפה לדף `<style data-otzaria-fonts>` עם כללי `@font-face` שמפנים לשרת מקומי; כשהטעינה נכשלת (למשל בגלל CSP של התוסף) הכללים מוחלפים בבייטים מוטבעים (`data:`), ובמקרה של macOS ו-iOS תמיד. לייצוא ולשמירה של כללים עצמאיים השתמשו ב-`fonts.resolveFamilies`. השאירו תמיד `'David', serif` בסוף שרשרת `font-family` של גופן ספר, למשפחה שאינה קיימת במכונה.

## ריווח, רדיוס וגבהים

- **סולם ריווח:** 2, 4, 8, 12, 16, 24, 32 (`--space-2xs` עד `--space-xl`). ערך שמחוץ לסולם עולה לערך הבא: 6 הופך ל-8, 10 ל-12, 14 ל-16. אל תכתבו "טוקן ועוד 1".
- **רדיוס:** 8 (`--radius`) לכל רכיב מלבני: כרטיס, כפתור, שדה, תפריט, דיאלוג, תגית. אין גלולות ואין פינות גדולות יותר. חריגים: רכיב עגול מטבעו (ספינר, נקודת סטטוס, אווטאר) `50%`, וכפתור אייקון בלבד שהוא עגול.
- **גבולות:** `1px solid var(--color-outline-variant)` לכרטיס; `1px solid var(--color-outline)` לשדה.
- **גבהים:** שדה `var(--field-height)` (48, או 36 בצפיפות מצומצמת); כפתור, שורת רשימה ופריט תפריט לפחות `var(--tap-target)` (40, ו-48 במגע).
- **הגבהה:** מסגרת ולא צל. רמה 0 לכרטיסים ולמשטחים רגילים (גבול `outline-variant`, בלי צל); צל (`--shadow-floating`) רק לתפריט, tooltip וחלונית צפה.
- **רוחב תוכן:** לוח מוגבל ל-860 וממורכז; חלונית צד 340; דיאלוג 400, 560 או 720.

## RTL

- `<html lang="he" dir="rtl">` חובה (הוולידטור פוסל בלעדיו).
- כיוון בלוגיקה ולא ב-`left`/`right`: `padding-inline`, `margin-inline`, `inset-inline-start`, `text-align: start`, `border-inline-start`. הדף RTL, ולכן `start` הוא ימין ו-`end` הוא שמאל.
- **אייקונים כיווניים** (חץ, שברון, "הבא"): ציירו אותם לכיוון RTL; בדף אין היפוך אוטומטי. אייקוני אוצריא עצמם מצוירים מלכתחילה לממשק הפוך.
- **טקסט מעורב:** שם ספר עם מספרים או אנגלית בתוך עברית משתמש בכיוון הפסקה. לנתיב, כתובת או מזהה בתוך משפט עברי עטפו ב-`<bdi>` או ב-`unicode-bidi: isolate` עם `direction: ltr`.
- **פס גלילה:** באפליקציה אנכי בקצה הימני. בדף הוא נקבע לפי `color-scheme`; אל תעצבו אותו מחדש.
- **קיצורי מקשים** מוצגים תמיד LTR (`Ctrl+Shift+P`).

---

## שלד התוסף

### סרגל כותרת התוסף (Top Bar)

תוסף נפתח כטאב קריאה, ליד טאבים של ספרים. אוצריא **אינה** מציירת כותרת מעל ה-WebView: כל מה שנראה בטאב הוא של התוסף. לכן:

> **כותרת התוסף חייבת להופיע בפס עליון קבוע, ברקע `--surface-top-bar` (`surfaces.topBar`), בדיוק כמו הסרגל העליון של מסכי האפליקציה.**

המשתמש עובר מטאב של ספר לטאב של תוסף ורואה אותו פס באותו צבע ובאותו גובה. **מה שגוי:** כותרת ענקית בגוף התוכן (`<h1>` בתוך הדף) שגוללת יחד עם התוכן ונחתכת בחלון צר.

| פריט | ערך |
|---|---|
| רקע | `var(--surface-top-bar)` (`colorScheme.surfaceContainerHigh` במארח ישן) |
| גובה | `var(--top-bar-height)`: 56, או 44 בצפיפות מצומצמת. **לא** לפי רוחב הדף |
| כותרת | 18px, `font-weight: 600`, `onSurface` |
| כותרת משנה | 12px, 400, `onSurfaceVariant` |
| קו תחתון | `border-block-end: 1px solid var(--surface-region-border)`: מופיע רק בערכת "לבן" בבהיר, אחרת שקוף |
| הפס עצמו | `flex-shrink: 0`: לא נדחס ולא נגלל |
| פעולות | בצד ה-start, צמודות לכותרת; הקצה ה-end נשאר פנוי (ראו [מה המארח מצייר מעל התוכן](#מה-המארח-מצייר-מעל-התוכן)) |

**גדלי הפס הם px קשיחים, לא `em`.** זה החריג היחיד לכלל "יחידות יחסיות": הפס אינו מתנפח עם גופן הקריאה, בדיוק כמו הסרגל של אוצריא שלידו. הוולידטור מחריג `font-size` ב-`px` רק בסלקטור שמכיל `topbar` או `top-bar`; שמרו על השם הזה לפס ואל תשתמשו בו לתוכן.

**הגובה מגיע מ-`density`, לא מ-`@media`.** "צפיפות ממשק" היא הגדרה של המשתמש ("אוטומטי" = חלון נמוך מ-480 במחשב, או צד קצר מתחת ל-600 בטלפון). בחלון צר במחשב (420-600) הצפיפות נשארת רגילה, ולכן `@media (max-width: 600px) { .topbar { height: 44px } }` מציג פס נמוך משל אוצריא. הערך `--top-bar-height` נכון תמיד; במארח שלפני 0.9.99 נשאר ערך ברירת המחדל, 56.

```css
html,
body {
  height: 100%;
  margin: 0;
}

body {
  overflow: hidden; /* הגלילה קורית בתוכן, לא בעמוד */
}

.app-shell {
  display: flex;
  flex-direction: column;
  height: 100%;
}

.topbar {
  display: flex;
  align-items: center;
  gap: var(--space-smd);
  height: var(--top-bar-height);
  padding-inline: var(--space-md);
  background: var(--surface-top-bar);
  border-block-end: 1px solid var(--surface-region-border);
  flex-shrink: 0;
}

.topbar h1 {
  margin: 0;
  font-size: 18px;
  font-weight: 600;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.topbar .subtitle {
  font-size: 12px;
  color: var(--color-on-surface-variant);
}

.app-content {
  flex: 1;
  min-width: 0;
  overflow-y: auto;
  padding: var(--space-md);
  container-type: inline-size;
}
```

```html
<div class="app-shell">
  <header class="topbar">
    <div class="topbar-titles">
      <h1>שם התוסף</h1>
      <span class="subtitle">כותרת משנה אופציונלית</span>
    </div>
    <div class="topbar-actions"><!-- כפתורי פעולה --></div>
  </header>
  <main class="app-content"><!-- התוכן: הוא שגולל --></main>
</div>
```

מתכון מלא, עם בורר במרכז הפס, ב-[COOKBOOK.md § 4](COOKBOOK.md#4-סרגל-כותרת-התוסף-top-bar).

### מה המארח מצייר מעל התוכן

אוצריא מצמידה לטאב של תוסף כמה רכיבים משלה, מעל ה-WebView. אל תציבו שם פעולות חיוניות:

| רכיב | איפה | מתי |
|---|---|---|
| כפתור יציאה ממסך מלא | 8px מהפינה העליונה בצד ה-end (שמאל ב-RTL) | רק במסך מלא |
| צ'יפ עדכון תוסף | 16px מהפינה התחתונה בצד ה-start (ימין ב-RTL) | כשיש עדכון זמין |
| ידית גרירה | רצועה בגובה 44 לאורך הצד העליון של חלונית | בטאב מפוצל: בריחוף במחשב, אחרי נגיעה במגע |

לכן הפעולות בפס הכותרת יושבות בצד ה-start, והקצה ה-end נשאר פנוי; ופעולה צפה בתחתית לא תשב בפינה ה-start.

### בחירת טקסט

גרירה של פיקסלים בודדים ברווח בין פסקאות או בשוליים בוחרת ב-WebView בלוקים שלמים, והדף נצבע בכחול. כבו את הבחירה בשלד והשאירו אותה רק בטקסט שמעתיקים:

```css
body {
  user-select: none;
}

.selectable,
input,
textarea {
  user-select: text;
}
```

### מיקוד אוטומטי בפתיחה

תוסף שנפתח על שדה עיקרי (חיפוש, שאילתה) ממקד אותו בעצמו. אוצריא מעבירה פוקוס מקלדת אל ה-WebView כשהטאב פעיל, אבל איזה אלמנט יקבל אותו נקבע בדף. `<input autofocus>` מספיק לשדה שקיים ב-HTML הראשוני; שדה שנוצר ב-JS צריך `focus()` מפורש אחרי שהוא בעץ ומוצג. `autofocus` על שדה מוסתר (`display: none`) אינו עושה דבר: מקדים אותו ברגע שהוא מוצג.

---

## ספריית הרכיבים

כל רכיב כאן קיים ב-[`examples/design-gallery`](examples/design-gallery) עם כל המצבים שלו, ושם אפשר לראות אותו בכל ערכה וברוחב. קטעי הקוד הם הליבה, לא כל ה-CSS.

### כפתורים

| סוג | מתי | class |
|---|---|---|
| ראשי (filled) | פעולה מומלצת; אחד לכל קבוצת פעולות | `btn btn-primary` |
| משני (tonal) | פעולה ניטרלית, וגם **ביטול** בדיאלוג | `btn` |
| שקט (ghost) | פעולה משנית שאינה ביטול ("דלג", "איפוס") | `btn btn-ghost` |
| מסוכן רך | הסרה ופעולה הרסנית במסך (לא בדיאלוג) | `btn btn-danger-soft` |
| מסוכן | אישור פעולה הרסנית, **רק בתוך דיאלוג** | `btn btn-danger` |
| אייקון בלבד | פעולת סרגל ושורה; חובה `aria-label` | `btn btn-icon` |

```html
<button type="button" class="btn btn-primary">שמירה</button>
<button type="button" class="btn">ביטול</button>
<button type="button" class="btn btn-icon" aria-label="חיפוש">
  <svg class="icon" aria-hidden="true"><use href="#i-search" /></svg>
</button>
```

```css
.btn {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  gap: var(--space-sm);
  min-height: var(--tap-target);
  padding-inline: var(--space-md);
  border: 0;
  border-radius: var(--radius);
  font-family: var(--font-ui);
  font-size: var(--text-body-sm);
  font-weight: 500;
  cursor: pointer;
}

.btn-primary {
  --overlay: var(--color-on-primary);
  background: var(--color-primary);
  color: var(--color-on-primary);
}

.btn-icon {
  width: var(--tap-target);
  padding: 0;
  border-radius: 50%;
  background: transparent;
  color: var(--color-on-surface-variant);
}
```

חובה `font-family: var(--font-ui)` על כפתור ושדה: הם אינם יורשים גופן. הגובה ממשתנה, כך שהוא גדל ל-48 במגע. אל תשתמשו ב-`opacity` למצב מושבת.

### שדות וחיפוש

```html
<div class="field">
  <label class="field-label" for="list-name">שם הרשימה</label>
  <input class="input" id="list-name" type="text" autofocus />
  <span class="field-error">שדה חובה.</span>
</div>

<div class="search" role="search">
  <svg class="icon" aria-hidden="true"><use href="#i-search" /></svg>
  <input class="search-input" type="search" aria-label="חיפוש בספרים" placeholder="חיפוש בספרים…" />
  <button type="button" class="btn btn-icon" aria-label="נקה חיפוש" hidden>
    <svg class="icon" aria-hidden="true"><use href="#i-close" /></svg>
  </button>
</div>
```

```css
.input {
  width: 100%;
  min-height: var(--field-height);
  padding-inline: var(--space-md);
  border: 1px solid var(--color-outline);
  border-radius: var(--radius);
  background: var(--surface-card);
  color: var(--color-on-surface);
  font-family: var(--font-ui);
  font-size: var(--text-body);
}

.input:focus-visible {
  outline: none;
  border-color: var(--color-primary);
  box-shadow: 0 0 0 1px var(--color-primary);
}

.input[aria-invalid='true'] {
  border-color: var(--color-error);
}

.field-error {
  font-size: var(--text-meta);
  color: var(--color-error);
}
```

- תווית **מעל** השדה (`--text-meta`, `on-surface-variant`), לא placeholder במקומה.
- שגיאת אימות מתחת לשדה בצבע `error`, עם `aria-invalid="true"`; לא טקסט אדום שנבנה ידנית.
- שדה חיפוש: אייקון בתחילת השורה, כפתור ניקוי אחד שמופיע רק כשיש טקסט, ו-`type="search"`. מיקוד אוטומטי בפתיחה.
- הפוקוס מעבה את הגבול ל-2px בלי להזיז את הפריסה (`box-shadow` של 1px).

### כרטיסים

כרטיס הוא `--surface-card` עם גבול `--color-outline-variant`, בלי צל. רדיוס 8, ריפוד `--space-smd` (12), ומרווח `--space-sm` (8) בין כרטיסים.

```html
<article class="card card-interactive" tabindex="0" aria-selected="false">
  <h3 class="card-title">ברכות</h3>
  <p class="card-meta">דף ב עמוד א</p>
  <p class="excerpt selectable">מאימתי קורין את שמע בערבין…</p>
</article>
```

```css
.card {
  padding: var(--space-smd);
  border: 1px solid var(--color-outline-variant);
  border-radius: var(--radius);
  background: var(--surface-card);
  color: var(--color-on-surface);
}

.card-interactive:hover {
  box-shadow: inset 0 0 0 999px var(--state-hover);
}

.card[aria-selected='true'] {
  border-color: var(--color-primary);
  box-shadow: inset 0 0 0 1px var(--color-primary);
}

.card-error {
  border-color: transparent;
  background: var(--color-error-container);
  color: var(--color-on-error-container);
}
```

כרטיס נבחר מסומן בגבול `primary`, לא ברקע בלבד. כרטיס שגיאה משתמש ב-`error-container`. כרטיס בתוך כרטיס: `card-inset` (`surface-container`, בלי גבול).

### רשימות

שורת רשימה היא לפחות `--tap-target` גבוהה, בריפוד `--space-smd` אנכי ו-`--space-md` אופקי, עם מפריד `outline-variant` בין שורות. שורה נבחרת ב-`secondary-container` ובמשקל 600.

```html
<ul class="list" role="listbox" aria-label="ספרים">
  <li class="list-row" role="option" aria-selected="true" tabindex="0">
    <div class="list-row-main">
      <div class="list-row-title">בראשית</div>
      <div class="list-row-meta">חמישה חומשי תורה</div>
    </div>
  </li>
</ul>
```

```css
.list-row {
  display: flex;
  align-items: center;
  gap: var(--space-smd);
  min-height: var(--tap-target);
  padding: var(--space-smd) var(--space-md);
}

.list-row[aria-selected='true'] {
  background: var(--color-secondary-container);
  color: var(--color-on-secondary-container);
  font-weight: 600;
}
```

רשימה ארוכה (יותר מכ-50 שורות) נבנית עם וירטואליזציה או בקטעים; אל תחשבו סגנון בכל שורה.

### תפריטים

תפריט הוא רכיב צף: רקע `surface-container-high`, רדיוס 8 וצל `--shadow-floating`. פריט תפריט גבוה `--tap-target`. תפריט נפתח מכפתור, נסגר בלחיצה בחוץ וב-Escape, והפוקוס עובר לפריט הראשון.

```html
<span class="popover-anchor">
  <button type="button" class="btn" aria-haspopup="menu" aria-expanded="false">פעולות</button>
  <div class="menu" role="menu" hidden>
    <button type="button" class="menu-item" role="menuitem">פתח בלשונית חדשה</button>
    <div class="menu-sep" role="separator"></div>
    <button type="button" class="menu-item" role="menuitem">הסר מהרשימה</button>
  </div>
</span>
```

```css
.menu {
  position: absolute;
  inset-block-start: calc(100% + var(--space-xs));
  inset-inline-start: 0;
  padding: var(--space-xs);
  border-radius: var(--radius);
  background: var(--color-surface-container-high);
  box-shadow: var(--shadow-floating);
}

.menu-item:hover,
.menu-item:focus-visible {
  background: var(--state-hover);
}
```

**תפריט של התוסף לעומת תפריט של אוצריא.** תפריט שנפתח בתוך הדף הוא של התוסף, ואתם מציירים אותו כאן. כדי להוסיף פריט לתפריט הקליק הימני של הקורא או לסרגל הקורא, משתמשים ב-`reader.addContextMenuItem` ו-`reader.addToolbarItem`: אוצריא מציירת אותם, והמראה אינו בשליטתכם (ראו [אייקונים](#אייקונים)).

### תגיות

תגית היא תווית קטנה לא אינטראקטיבית (12px, רדיוס 8). הגוון קובע משמעות:

| class | גוון | שימוש |
|---|---|---|
| `chip` | `surface-container-highest` | ניטרלי |
| `chip chip-primary` | `primary-container` | הדגשה |
| `chip chip-success` | `secondary-container` | הושלם (גוון ניטרלי, לא ירוק) |
| `chip chip-warning` | `surface-warning-container` | שימו לב |
| `chip chip-error` | `error-container` | שגיאה |

סינון: `chip chip-filter` עם `aria-pressed`. כשהוא לחוץ הוא מקבל `secondary-container` ואייקון `check` (סימן שאינו צבע). גובה 32, ושטח הלחיצה מורחב במגע.

```html
<span class="chip chip-success">הושלם</span>
<button type="button" class="chip chip-filter" aria-pressed="true">תנ"ך</button>
```

```css
.chip {
  display: inline-flex;
  align-items: center;
  gap: var(--space-xs);
  padding: var(--space-2xs) var(--space-sm);
  border-radius: var(--radius);
  background: var(--color-surface-container-highest);
  font-size: var(--text-meta);
  font-weight: 500;
}

.chip-filter[aria-pressed='true'] {
  background: var(--color-secondary-container);
  color: var(--color-on-secondary-container);
}
```

### התראות

יש שלושה סוגים, ולכל אחד מקום:

| סוג | מי מצייר | מתי | API |
|---|---|---|---|
| **באנר בדף** | התוסף | הודעה שקשורה למסך: אזהרה, שגיאה עם "נסה שוב", מידע | (HTML) |
| **הודעה קצרה** (snack) | אוצריא | משוב על פעולה: נשמר, הועתק, נכשל | `ui.showMessage`, `ui.showSuccess`, `ui.showError` |
| **דיאלוג אישור** | אוצריא | פעולה שדורשת החלטה: מחיקה, פעולה הרסנית | `ui.showConfirm`, `ui.showWarning` |

```javascript
Otzaria.call('ui.showSuccess', { message: 'הרשימה נשמרה' });

const response = await Otzaria.call('ui.showConfirm', {
  title: 'מחיקת הרשימה',
  content: 'האם למחוק את הרשימה?',
});
if (response.success && response.data.confirmed) {
  // המשתמש אישר
}
```

- **באנר:** `role="status"` להודעה רגילה, `role="alert"` לשגיאה. אייקון, כותרת (`--text-body-sm`, 600) וגוף. בלי גבול. גוונים: מידע `surface-container-highest`, אזהרה `surface-warning-container`, שגיאה `error-container`, הצלחה `secondary-container`.
- **הודעה קצרה:** מוצגת 6 שניות (`ui.showMessage`) או 3 שניות (`showSuccess`, `showError`), ברוחב עד 500. מידע והצלחה נראים זהים (`surface-container-highest`) ורק האייקון שונה; שגיאה ב-`error-container`. אין גוון "אזהרה" ל-snack של תוסף. **אל תשתמשו בהודעה קצרה למידע קריטי.** הודעה יכולה להיות לחיצה (`tapPayload`, אירוע `ui.messageClicked`).
- **דיאלוג של אוצריא** ממתין להחלטה ללא timeout, ומופע אחד יכול להציג דיאלוג אחד בכל רגע. מראהו אחיד עם האפליקציה, והתוסף אינו שולט בו.

```css
.banner {
  display: flex;
  align-items: flex-start;
  gap: var(--space-smd);
  padding: var(--space-smd) var(--space-md);
  border-radius: var(--radius);
  background: var(--color-surface-container-highest);
  color: var(--color-on-surface);
}

.banner-error {
  background: var(--color-error-container);
  color: var(--color-on-error-container);
}
```

### טעינה, ריק ושגיאה

לכל מקום שמציג תוכן צריכים להיות שלושה מצבים, ולא רק "הצלחה":

| מצב | מה מציגים |
|---|---|
| **טעינה** | שלד (skeleton) של התוכן שמגיע, או ספינר כשאין צורת תוכן ידועה; `aria-busy="true"` |
| **ריק** | אייקון, כותרת קצרה, הסבר, ופעולה אם יש ("נקה חיפוש") |
| **שגיאה** | אייקון שגיאה, כותרת, הסבר, וכפתור **"נסה שוב"**; לא רק טקסט אדום |

```html
<div class="state state-error" role="alert">
  <svg class="icon icon-lg" aria-hidden="true"><use href="#i-error" /></svg>
  <p class="state-title">הטעינה נכשלה</p>
  <p class="state-body">לא הצלחנו לטעון את התוצאות. אפשר לנסות שוב.</p>
  <button type="button" class="btn btn-primary">נסה שוב</button>
</div>
```

```css
.spinner {
  width: 36px;
  height: 36px;
  border: 3px solid var(--color-outline-variant);
  border-top-color: var(--color-primary);
  border-radius: 50%;
  animation: spin 0.75s linear infinite;
}

@keyframes spin {
  to {
    transform: rotate(360deg);
  }
}

.state {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: var(--space-sm);
  padding: var(--space-xl) var(--space-md);
  text-align: center;
}

.state-error .icon-lg {
  color: var(--color-error);
}
```

הטקסט במצב ריק מסביר **מה אפשר לעשות**, לא רק "אין תוצאות". כפתור בטעינה (`aria-busy`) שומר על רוחבו, כדי שהפריסה לא תקפוץ. בהפחתת תנועה של המערכת (`prefers-reduced-motion`) מכבים את השלד המהבהב; ספינר שמעביר מידע נשאר.

### חלוניות: דיאלוג וחלונית צד

**דיאלוג של התוסף** נבנה עם `<dialog>` (פוקוס, Escape ו-trap מובנים). רדיוס 8, ריפוד 24 אופקי ו-16 אנכי, רקע `surface-container-high`, כיסוי `--scrim`. ביטול הוא כפתור **משני**, ופעולה הרסנית מאושרת ב-`btn-danger`. רוחב 400 (קטן), 560 או 720.

```html
<dialog class="dialog" aria-labelledby="dlg-title">
  <h2 class="dialog-title" id="dlg-title">מחיקת הערה</h2>
  <p class="dialog-body">ההערה תימחק לצמיתות.</p>
  <div class="dialog-actions">
    <button type="button" class="btn">ביטול</button>
    <button type="button" class="btn btn-danger">מחק</button>
  </div>
</dialog>
```

```css
.dialog {
  width: min(400px, calc(100% - 2 * var(--space-md)));
  padding: var(--space-md) var(--space-lg);
  border: 0;
  border-radius: var(--radius);
  background: var(--color-surface-container-high);
  color: var(--color-on-surface);
}

.dialog::backdrop {
  background: var(--scrim);
}

.dialog-actions {
  display: flex;
  justify-content: flex-end;
  gap: var(--space-sm);
}
```

`showModal()` פותח, `close()` סוגר. `::backdrop` יורש את ה-custom properties מהאלמנט בדפדפנים מודרניים (WebView2 ו-WKWebView עדכניים); אם נדרשת תאימות רחבה יותר, השתמשו ב-scrim משלכם.

**חלונית צד** (הגדרות, פרטים): 340 רוחב, מהקצה ה-end, רקע `--surface-top-bar`, צל צף, כיסוי, וסגירה ב-Escape ובלחיצה על הכיסוי. היא מתאימה לתוכן עמוק; לתוכן קצר שקשור לכפתור משתמשים בתפריט.

```css
.side-panel {
  position: fixed;
  inset-block: 0;
  inset-inline-end: 0;
  width: min(340px, 100%);
  padding: var(--space-md);
  background: var(--surface-top-bar);
  box-shadow: var(--shadow-floating);
  transform: translateX(-100%);
  visibility: hidden;
  transition:
    transform var(--motion-normal) ease-out,
    visibility 0s linear var(--motion-normal);
}

.side-panel.open {
  transform: translateX(0);
  visibility: visible;
  transition-delay: 0s;
}
```

### טבלאות

טבלה נבנית כ-`<table>` אמיתי בתוך מעטפת `overflow-x: auto`. כותרות `th` דביקות (12px, 600, `on-surface-variant`), יישור `start`, ועמודות מספרים ביישור `end` עם `tabular-nums`. במסך צר המעטפת גוללת אופקית, והיא מקבלת `tabindex="0"`, `role="region"` ו-`aria-label` כדי שאפשר לגלול אותה במקלדת.

```html
<div class="table-wrap" role="region" aria-label="טבלת ספרים" tabindex="0">
  <table class="table">
    <thead>
      <tr><th scope="col">ספר</th><th scope="col" class="num">פרקים</th></tr>
    </thead>
    <tbody>
      <tr><td>בראשית</td><td class="num">50</td></tr>
    </tbody>
  </table>
</div>
```

```css
.table-wrap {
  overflow-x: auto;
  border: 1px solid var(--color-outline-variant);
  border-radius: var(--radius);
  background: var(--surface-card);
}

.table th {
  position: sticky;
  inset-block-start: 0;
  padding: var(--space-smd) var(--space-md);
  background: var(--surface-card);
  color: var(--color-on-surface-variant);
  font-size: var(--text-meta);
  font-weight: 600;
  text-align: start;
}

.table .num {
  text-align: end;
  font-variant-numeric: tabular-nums;
}
```

אל תשתמשו בטבלה לפריסה. מעל כ-50 שורות: וירטואליזציה או עימוד.

### אנימציה

תנועה קצרה ושקטה: `--motion-fast` (150ms) להחלפת מצב, `--motion-normal` (250ms) לפתיחת חלונית. כבדו את `prefers-reduced-motion: reduce` (מכבים הנפשות של כניסה, שלד וחלוניות). אל תנפישו מעבר בין ערכות נושא.

---

## בהיר וכהה

האפליקציה היא שקובעת: המשתמש בוחר בהיר, כהה או "עקוב אחר המערכת", וה-payload מגיע כבר מותאם (`mode` וכל תפקידי הצבע). לכן:

- **לא בוחרים צבע לפי `mode`.** כל מה שצריך לשנות במצב כהה כבר מגיע בתפקידי הצבע. אם נדרש הבדל מבני (תמונה שונה לכהה), השתמשו ב-`data-theme-mode` על האלמנט, לא בבדיקה בקוד הרכיב.
- **אל תשתמשו ב-`@media (prefers-color-scheme)`.** ה-WebView אינו יודע מה בחר המשתמש באפליקציה: הוא עוקב אחרי המערכת, ולכן "כהה" באפליקציה על מערכת בהירה ייראה בהיר.
- **הציבו `color-scheme`** (ה-`applyTheme` עושה זאת מ-`mode`), כדי שפסי גלילה, תיבות סימון ושדות מקוריים ייראו לפי האפליקציה.
- **אין לקודד תמונות ברקע לבן** (לוגו, איור): צבעו אותן ב-`currentColor` או הגישו וריאנט לכהה.
- **גרפים וקנבס:** אלה אינם `var()`. קראו את הצבע מחדש מ-`getComputedStyle(document.documentElement).getPropertyValue('--color-primary')` וצבעו מחדש ב-`theme.changed`.

## שינוי ערכת נושא בזמן ריצה

### מתי נשלח `theme.changed`

| שינוי | נשלח? |
|---|---|
| ערכת צבע (seed), בהיר או כהה | כן |
| מעבר בין בהיר, כהה ו"עקוב אחר המערכת" (שינוי ההגדרה) | כן |
| המערכת מחליפה בין בהיר לכהה כש"עקוב אחר המערכת" פעיל | כן, מ-0.9.99 (קודם לא נשלח) |
| גופן קריאה, גודל, גובה שורה, גופן ושגודל מפרשים | כן (משתנה `typography`) |
| "צפיפות ממשק" | כן, מ-0.9.99 |
| החלון חוצה את סף "חלון קטן" כשהצפיפות אוטומטית | כן, מ-0.9.99 |
| שינוי רוחב החלון שאינו חוצה את הסף | לא: השתמשו ב-`@container` |

בכל המקרים נשלח `ThemePayload` **מלא**, לא הפרש.

### מה התוסף עושה

1. מחיל את ה-payload מיד (`applyTheme`), בלי הנפשה. משתני CSS מעדכנים את כל הרכיבים.
2. מצייר מחדש מה שאינו CSS: קנבס, גרפים, צבעים שחושבו ב-JS.
3. לא שומר "העתק" של צבעים: תמיד קוראים מהמשתנים.
4. בהשהיה (טאב לא פעיל) אוצריא שומרת רק את `theme.changed` **האחרון** ומוסרת אותו מיד אחרי `plugin.resumed`. אין צורך לבקש אותו, אבל קריאה ל-`app.getTheme` ב-`plugin.resumed` היא רשת ביטחון זולה:

```javascript
Otzaria.on('plugin.resumed', async () => {
  const response = await Otzaria.call('app.getTheme');
  if (response.success) applyTheme(response.data);
});
```

5. מוכן ל-`colorScheme` ריק (חלון לא מחובר): `applyTheme` מתעלמת ממנו.

## חלונות קטנים ומגע

שלושה דברים שונים, ולכל אחד כלי משלו:

| השאלה | הכלי |
|---|---|
| כמה מקום יש **לרכיב** (תוסף בחלונית מפוצלת צרה בתוך חלון רחב) | `@container` על מעטפת התוכן (`container-type: inline-size`) |
| האם המשתמש אוחז **אצבע או עכבר** | `@media (pointer: coarse)` ו-`@media (hover: none)` |
| האם הממשק **צפוף** | `--top-bar-height`, `--field-height` מ-`density` |

```css
.app-content {
  container-type: inline-size;
}

@container (max-width: 600px) {
  .results {
    grid-template-columns: 1fr;
  }

  .hide-narrow {
    display: none;
  }
}
```

- **`@container` ולא `@media (max-width)`.** בטאב מפוצל התוסף מקבל חלונית צרה גם כשהחלון רחב. `@media` בודק את החלון כולו ויתן פריסה שגויה.
- **חלון מינימלי:** האפליקציה יורדת עד 420×400 במחשב, וטלפון בגודל 360 ומטה. תכננו מ-320.
- **צפיפות:** בחלון צר במחשב (420-600) הצפיפות נשארת רגילה, ובחלון נמוך (גובה מתחת ל-480) היא מצומצמת. אל תנחשו מהרוחב: קראו את `--top-bar-height` ו-`--field-height`.
- **מגע:** `--tap-target` הופך ל-48 תחת `pointer: coarse`. כל פקד, שורה ופריט תפריט משתמשים בו. רווח בין יעדי לחיצה לפחות `--space-sm`. אל תסתירו פעולה מאחורי hover (אין hover במגע).
- **אין זום:** ה-WebView של התוסף חוסם זום וצביטה, ולכן גודל טקסט קריא הוא באחריותכם. לא יורדים מתחת ל-12px (מטא), וגוף לפחות 14.
- **מקלדת מסך:** בטלפון היא מקצרת את הגובה. שלד ב-flex עם `height: 100%` (ולא `100vh` קשיח), ושדה בפוקוס נגלל אל הנראה.
- **גלילה:** הגלילה האנכית היא של התוכן. אל תסתמכו על החלקה אופקית כפעולה חיונית: בטלפון עם כמה טאבים פתוחים החלקה אופקית מעבירה בין טאבים.
- **רצועת הגרירה** בראש חלונית מפוצלת (44px) מופיעה בריחוף או אחרי נגיעה: אל תשימו שם מידע קריטי שאינו נגיש גם דרך אחרת.

## אייקונים

אוצריא מציירת אייקון של תוסף **בעצמה** בשבעה מקומות, וה-API מקבל **שם**, לא קובץ:

| מקום | שדה |
|---|---|
| לשונית הכלים | `manifest.json`: `contributes.toolTab.iconName` |
| פקד בסרגל של מסך עיון | `reader.addToolbarItem` (`icon`), או `contributes.startup.toolbarItems[].icon` |
| ילד של פקד תפריט נפתח | `children[].icon` |
| פריט בתפריט הקליק הימני | `reader.addContextMenuItem` (`icon`) |
| צבע בשורת הצבעים של התפריט | `colors[].icon` |
| כרטיסי ספרים של ספק בספרייה | `contributes.startup.libraryBooks[].icon` |
| עדכון אייקון של פקד קיים | `reader.updateToolbarItem` (`patch.icon`) |

השם הוא `<שם>_24_regular` או `<שם>_24_filled`, משתי הספריות (אוצריא ו-FluentUI), לפי [כלל ההכרעה](ICONS.md#כלל-ההכרעה). ב-`manifest.json` תבנית שגויה נדחית בהתקנה; ב-API בזמן ריצה שם שגוי אינו שגיאה ופשוט לא מציג אייקון. השתמשו ב-`filled` למצב פעיל או נבחר וב-`regular` לרגיל. פירוט ורשימה מלאה: [ICONS.md](ICONS.md).

```json
"contributes": {
  "toolTab": {
    "title": "גלריית עיצוב",
    "order": 900,
    "defaultPinned": false,
    "iconName": "paint_brush_24_regular"
  }
}
```

```javascript
await Otzaria.call('reader.addContextMenuItem', {
  id: 'my-bookmark-item',
  label: 'הוסף לסימניות שלי',
  icon: 'bookmark_24_regular',
});
```

### אייקונים בתוך הדף

בתוך ה-WebView אוצריא אינה מציירת כלום, ו**אין API שמחזיר אייקון**. שם משתמשים ב-SVG inline מקומי:

- צובעים ב-`currentColor` (`stroke` או `fill`) כדי שיעקוב אחרי הצבע של הכפתור והערכה.
- גודל 20 לכפתור ושורה, 16 בתוך שדה ובשורה צפופה, 24 לאייקון בולט, 48 למצב ריק.
- אייקון כיווני (חץ, שברון) מצוירים ל-RTL.
- אייקון בלי תווית הוא `aria-hidden="true"` בתוך כפתור עם `aria-label`.
- **רישיון:** ספריית האייקונים של אוצריא (`otzaria_icons`) היא של אוצריא עצמה, והיא מתפרסמת תחת GPL-3.0-only. אין הגבלה על תוסף הדוגמה או על תוסף של אוצריא שמעתיקים אליו SVG ממנה. מי שמפיץ תוסף חיצוני עם SVG שהועתק מהספרייה מפיץ אותו בתנאי הרישיון הזה (ואייקונים שנגזרו מפלואנט נושאים גם את רישיון MIT שלה: `THIRD_PARTY_NOTICES.md` בריפו הספרייה). הגלריה מציירת את הסמלים שלה בעצמה, בקו פשוט בקובץ הדף. (ראו [ICONS.md](ICONS.md#אייקונים-בתוך-ה-webview-של-התוסף).)

```css
.icon {
  width: 20px;
  height: 20px;
  flex-shrink: 0;
  fill: none;
  stroke: currentcolor;
  stroke-width: 2;
  stroke-linecap: round;
  stroke-linejoin: round;
}
```

## מסך מלא

`ui.setFullscreen` (מגרסה **0.9.99**) מכניסה את אוצריא למסך מלא, כמו F11, או מוציאה ממנו. במסך מלא שורת הכותרת, הכרטיסיות וסרגלי הניווט מוסתרים, וכרטיסיית התוסף ממלאת את החלון. אין הרשאה לבקש.

```javascript
fullscreenButton.addEventListener('click', async () => {
  const response = await Otzaria.call('ui.setFullscreen', { fullscreen: true });
  if (!response.success) {
    // error.forbidden: לא מפעולת משתמש, או לא מסך עיון.
    // error.unknown_method: מארח לפני 0.9.99.
    showBanner('error', 'מסך מלא אינו זמין');
  }
});
```

- **כניסה רק מפעולת משתמש.** הקריאה חייבת לצאת ישירות ממטפל `click` או `keydown`. קריאה מטעינת הדף, מ-timer, או אחרי שרשרת `await` ארוכה מוחזרת ב-`error.forbidden`. (ב-macOS וב-iOS אין אכיפה, אבל אל תסתמכו על זה.)
- **רק במסך עיון** עם כרטיסייה פתוחה; אחרת `error.forbidden`.
- **אף פעם לא דביק.** Escape (גם כשהפוקוס בתוך התוסף), "חזור" באנדרואיד, כפתור היציאה של המארח ומעבר למסך אחר יוצאים ממסך מלא ללא שאלה. **אל תניחו שאתם עדיין במסך מלא**: האזינו ל-`ui.fullscreenChanged` (מ-0.9.99) והחליפו תווית כפתור לפי `fullscreen` שבאירוע, לא לפי "לחצתי, אז אני במסך מלא".
- **האירוע `ui.fullscreenChanged`** נשלח בכל שינוי (כפתור, F11, Escape, יציאה אוטומטית) עם `{ fullscreen: boolean }`, הרשאת בסיס בלי הצהרה. הוא מדווח על שינוי ולא נשלח בטעינה, ולכן הדף מתחיל ב"מסך מלא" ומתעדכן לפי האירוע ([פירוט](API_REFERENCE.md#event-uifullscreenchanged)).
- **יציאה** (`fullscreen: false`) תמיד מותרת, גם בלי פעולת משתמש; כשכבר לא במסך מלא אינה עושה דבר.
- **כפתור היציאה של אוצריא צף מעל התוכן** בפינה העליונה בצד ה-end. השאירו שם מקום ([מה המארח מצייר](#מה-המארח-מצייר-מעל-התוכן)).
- **נסיגה:** תוסף שתומך גם במארח ישן יעטוף את הקריאה ויסתיר את הכפתור (או יציג הסבר) כשהיא נכשלת ב-`error.unknown_method`. הוולידטור מחייב `minAppVersion` של 0.9.99 לתוסף שקורא ל-`ui.setFullscreen`, גם כשהקריאה מוגנת.

## תאימות גרסאות

תוסף ישן ממשיך לעבוד: שדות חדשים ב-payload הם **תוספת** ולא משנים שדה קיים. תוסף שמשתמש בשדה חדש מחזיק ערך ברירת מחדל ב-`:root` ובודק שהשדה קיים (`applyTheme` עושה זאת), או מצהיר `minAppVersion` מתאים.

| פריט | מגרסה | במארח ישן | מה לעשות |
|---|---|---|---|
| `theme`, `colorScheme`, `typography.fontFamily` | 0.9.89 | | זמין תמיד |
| `typography.uiFontFamily` | 0.9.97 | חסר | ברירת מחדל ב-`:root` |
| `events.subscribe:theme.changed` כהרשאת בסיס | 0.9.97 | דורש הצהרה | מצהירים רק אם `minAppVersion` נמוך מ-0.9.97 |
| `fonts.resolveFamilies`, `fonts.listInstalled` | 0.9.97 | `error.unknown_method` | |
| `surfaces` (כולל `regionBorder` ו-`warning*`), `radius`, `spacing`, `density`, `typography.uiFont` | 0.9.99 | חסרים | ערכי `:root`; `applyTheme` מדלגת |
| `theme.changed` בשינוי צפיפות ובהחלפת מערכת בהיר/כהה | 0.9.99 | לא נשלח | `plugin.resumed` ו-`app.getTheme` כרשת ביטחון |
| `ui.setFullscreen`, `ui.setTabInfo` | 0.9.99 | `error.unknown_method` | `minAppVersion: "0.9.99"` |
| אירוע `ui.fullscreenChanged` | 0.9.99 | לא נשלח | התווית הרגילה נשארת; אין צורך בהצהרה |

- **`minAppVersion`:** הוולידטור מתייחס לכל `Otzaria.call` לשיטה חדשה מ-`minAppVersion` כשגיאה חוסמת, גם כשהקריאה מוגנת. רשימת הגרסאות לכל שיטה: [API_REFERENCE.md § טבלת גרסאות API](API_REFERENCE.md#טבלת-גרסאות-api) ו-[`spec.json`](spec.json) (`methodMinVersions`).
- **מצב פיתוח** (תיקייה שנטענת עם `--dev-plugins`) אינו בודק גרסת אפליקציה, אבל כן מריץ את הוולידטור המורחב.
- **שם משתנה ישן:** התיעוד הקודם השתמש ב-`--font-size-base` כגודל הממשק. הוא נגזר מ-`typography.fontSize` שהוא גודל **הקריאה**, ולכן אינו מתאים לממשק; תוסף קיים שמגדיר אותו בעצמו ממשיך לעבוד. תוסף חדש משתמש ב-`--text-*` (ממשק) וב-`--font-size-reading` (קריאה).

## דברים שיש להימנע מהם

| שגוי | נכון |
|---|---|
| `color: #6750A4` | `color: var(--color-primary)` |
| `background: white` | `background: var(--surface-card)` (כרטיס) או `var(--surface-panel)` (דף) |
| `box-shadow: 0 2px 4px rgba(...)` | `box-shadow: var(--shadow-floating)` (תפריט וחלונית בלבד); כרטיס בלי צל |
| `font-size: 16px` בתוכן | `font-size: var(--text-body)`; px רק בפס הכותרת |
| גודל ממשק מ-`typography.fontSize` | סולם `--text-*`; `fontSize` רק לטקסט ספר |
| `font-family: 'Rubik'` | `font-family: var(--font-ui)` (`inherit` על כפתור או שדה מותר) |
| `border-radius: 20px` / `999px` | `border-radius: var(--radius)` |
| `border: 1px solid #ccc` | `border: 1px solid var(--color-outline-variant)` |
| `padding: 10px` | `padding: var(--space-smd)` (12): ערך מחוץ לסולם עולה לבא |
| `.topbar { height: 56px }` + `@media (max-width: 600px) { height: 44px }` | `height: var(--top-bar-height)` |
| `@media (max-width: 600px)` לפריסה | `@container (max-width: 600px)` |
| `@media (prefers-color-scheme: dark)` | `applyTheme` + `color-scheme` מ-`mode` |
| `opacity: 0.4` למצב מושבת | `color: var(--disabled-fg); background: var(--disabled-bg)` |
| `outline: none` בלי חלופה | `:focus-visible { outline: var(--focus-ring) }` |
| `<h1>` ענק בגוף התוכן ככותרת התוסף | פס עליון קבוע ב-`var(--surface-top-bar)` |
| `body { min-height: 100vh }` | `body { height: 100%; overflow: hidden }` ותוכן ב-`overflow-y: auto` |
| `left: 10px`, `margin-right` | `inset-inline-start`, `margin-inline-end` |
| ללא `Otzaria.on('theme.changed')` | להאזין תמיד לשינוי ה-theme |
| שדה חיפוש בלי מיקוד | `<input autofocus>` או `focus()` |
| הצהרה על `events.subscribe:theme.changed` ב-manifest | הרשאת בסיס: אין להצהיר (מ-0.9.97) |
| מסך מלא מ-`setTimeout` | מ-handler של `click` ישירות |

## דוגמה חיה: תוסף design-gallery

[`examples/design-gallery`](examples/design-gallery) הוא תוסף שלם וקטן בעברית: חיפוש, כרטיסי תוצאות, פעולות, תפריט, דיאלוג וחלונית צד, מצבי ריק וטעינה ושגיאה, טבלה, רשימה, תגיות והתראות. יש בו שתי תצוגות:

- **רכיבים:** הרכיבים חיים, עם ערכת הנושא של אוצריא, בהיר וכהה, מגיבים לרוחב החלונית ולמגע.
- **מטריצה:** ערכות הנושא (בהיר, כהה, לבן, פרגמנט, כחול, אפור, צפיפות מצומצמת, "מארח ישן") ברוחבים 320 עד 1200, זו לצד זו. הערכה מוחלת על כל מסגרת בנפרד, והרכיבים מגיבים לרוחב המסגרת (`@container`). כך רואים איך רכיב נראה בכל ערכה בלי להחליף את הערכה של אוצריא.

מבנה: `manifest.json`, `index.html`, `css/` (`tokens.css`, `components.css`, `gallery.css`), `js/` (`theme.js` הוא `applyTheme` שלמעלה, `gallery.js`, `fixtures.js` מגונרר).

**הרצה בתוך אוצריא (מהיר):** בבנייה עם `--dev-plugins` (או debug), בפאנל "תוספים" לחצו על אייקון התיקייה ובחרו את `docs/plugin-sdk/examples/design-gallery`. התוסף נטען עם תג DEV, מתרענן בשמירה, ולא בודק גרסת אפליקציה. נדרשת אוצריא 0.9.99 ומעלה בשביל `ui.setFullscreen` (ראו [תאימות](#תאימות-גרסאות)).

**התקנה כקובץ:** `otzaria pack-plugin docs/plugin-sdk/examples/design-gallery` ואז התקנה של קובץ ה-`.otzplugin` (ראו [README § אריזה והפצה](README.md#אריזה-והפצה--יצירת-קובץ-otzplugin)). ההתקנה כקובץ דורשת בנייה של 0.9.99 ומעלה: ב-`manifest.json` של הגלריה `minAppVersion` הוא `0.9.99` בכוונה, כי היא מדגימה גם `ui.setFullscreen` ו-`ui.fullscreenChanged`, והוולידטור מחייב גרסה מינימלית גם כשהקריאה מוגנת. בבנייה של 0.9.98 ומטה ההתקנה מקובץ נדחית בגלל הגרסה (זו אינה תקלה, ולא מורידים את `minAppVersion` כדי לעקוף אותה). עד שיוצאת 0.9.99, מריצים את הגלריה במצב תיקייה (`--dev-plugins`, שאינו בודק גרסה), כפי שמתואר למעלה.

**בדפדפן רגיל:** פתחו את `index.html`. בלי אוצריא הוא רץ במצב עצמאי עם הערכות שב-`fixtures.js`, והודעות ודיאלוגים של אוצריא מושבתים.

### בדיקות שמגינות על המדריך

`flutter test test/plugins/design_guide` מריץ:

- **קטעי הקוד:** כל בלוק `css`/`html` במדריך ובמתכונים עובר את בדיקת העיצוב של הוולידטור; כל `Otzaria.call` ו-`Otzaria.on` קיימים ב-`spec.json`; אין "דורש הרשאה" ליד הרשאת בסיס; כל קישור יחסי קיים.
- **הטוקנים:** טבלת הטוקנים שווה לשדות ה-payload של `buildThemePayloadFromScheme` ולמשתני `tokens.css`; `applyTheme` במדריך זהה ל-`theme.js` ומציב בפועל כל משתנה בטבלה (בהרצה ב-node).
- **התוסף:** `manifest.json` תקין מול הסכימה האמיתית, הוולידטור המורחב מקבל אותו בלי שגיאות או אזהרות, כל קריאת API קיימת בגרסה שה-`manifest` מצהיר, ו-`fixtures.js` נגזר מה-payload האמיתי (רענון: `--dart-define=update_gallery_fixtures=true`).
