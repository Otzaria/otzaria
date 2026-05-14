# מדריך עיצוב לתוספי אוצריא

מסמך זה מסביר כיצד לעצב תוסף שייראה כחלק טבעי מממשק אוצריא.
אוצריא בנויה על **Material Design 3** (M3) של גוגל — מערכת עיצוב שמגדירה צבעים, צורות, טיפוגרפיה ואינטראקציות.

---

## עקרון יסוד: צבעים תמיד מה-API

**אין לקודד צבעים ישירות ב-CSS.** כל צבע חייב להגיע מהמערכת דרך ה-API.

הסיבה: המשתמש יכול לבחור ערכת צבעים (theme) שונה, ולעבור בין מצב כהה למצב בהיר. תוסף עם צבעים קשיחים ייראה שבור בחלק מהערכות.

### קבלת ערכת הצבעים

הצבעים מגיעים בשני אירועים:

```javascript
// 1. בעת טעינת התוסף — plugin.boot כולל theme
Otzaria.on('plugin.boot', function(payload) {
  applyTheme(payload.theme);
});

// 2. כשהמשתמש משנה ערכת צבעים או מצב כהה/בהיר
//    ⚠️ דורש הרשאה: events.subscribe:theme.changed (ב-manifest.json)
Otzaria.on('theme.changed', function(theme) {
  applyTheme(theme);
});

// אפשר גם לשאול ישירות:
const { data: theme } = await Otzaria.call('app.getTheme');
applyTheme(theme);
```

### מבנה אובייקט ה-theme

```javascript
{
  mode: "light" | "dark",          // מצב בהיר / כהה
  colorScheme: {
    primary:                 "#...", // הצבע הראשי (כפתורים, הדגשות, גבולות נבחר)
    onPrimary:               "#...", // טקסט/אייקון מעל primary
    secondary:               "#...", // הדגשות משניות
    onSecondary:             "#...", // טקסט/אייקון מעל secondary
    surface:                 "#...", // רקע כללי (כרטיסים, חלוניות)
    onSurface:               "#...", // טקסט/אייקון על surface
    surfaceContainerHighest: "#...", // שכבת רקע הגבוהה ביותר (פופאובר, דיאלוג)
    error:                   "#...", // שגיאות
    onError:                 "#...", // טקסט/אייקון מעל error
    outline:                 "#...", // מסגרות ומפרידים
  },
  typography: {
    fontFamily:             "Frank Ruhl Libre", // גופן ראשי (טקסטים עבריים)
    fontSize:               25,                 // גודל גופן בסיסי (px) — לפי הגדרת המשתמש
    lineHeight:             1.5,                // גובה שורה
    commentatorsFontFamily: "Shofar",           // גופן מפרשים
    commentatorsFontSize:   22,                 // גודל גופן מפרשים (px)
  }
}
```

> **שים לב:** `fontSize` שונה ממשתמש למשתמש (טווח רגיל: 16–36). עצב את הפריסה כך שתעבוד בכל גודל.

---

## יישום הצבעים — CSS Variables

הדרך המומלצת: הפוך את הצבעים ל-CSS custom properties (משתנים). כך כל הרכיבים מתעדכנים אוטומטית בשינוי theme.

### הגדרת ברירות מחדל (לפני קבלת theme)

```css
:root {
  /* --- Color roles (ייוחלפו על-ידי applyTheme) --- */
  --color-primary:    #6750A4;
  --color-on-primary: #FFFFFF;
  --color-secondary:    #625B71;
  --color-on-secondary: #FFFFFF;
  --color-surface:    #FFFBFE;
  --color-on-surface: #1C1B1F;
  --color-surface-container-highest: #E6E0E9;
  --color-error:    #B3261E;
  --color-on-error: #FFFFFF;
  --color-outline:  #79747E;

  /* --- Derived / עיצוב --- */
  --color-primary-subtle:   rgba(103, 80, 164, 0.12); /* primary בשקיפות */
  --color-secondary-subtle: rgba(98, 91, 113, 0.12);  /* secondary בשקיפות */

  /* --- Typography --- */
  --font-main:     'Frank Ruhl Libre', 'David', serif;
  --font-size-base: 18px;
  --line-height:    1.5;

  /* --- Shape (כמו M3) --- */
  --radius-sm:  8px;   /* אלמנטים קטנים: שדות, chips */
  --radius-md:  12px;  /* כרטיסים */
  --radius-lg:  16px;  /* חלוניות */
  --radius-pill: 999px; /* chips/pills עגולים */
}
```

### פונקציית applyTheme

```javascript
function applyTheme(theme) {
  if (!theme || !theme.colorScheme) return;
  const cs = theme.colorScheme;
  const root = document.documentElement;

  root.style.setProperty('--color-primary',    cs.primary);
  root.style.setProperty('--color-on-primary',  cs.onPrimary);
  root.style.setProperty('--color-secondary',   cs.secondary);
  root.style.setProperty('--color-on-secondary', cs.onSecondary);
  root.style.setProperty('--color-surface',     cs.surface);
  root.style.setProperty('--color-on-surface',  cs.onSurface);
  root.style.setProperty('--color-surface-container-highest', cs.surfaceContainerHighest);
  root.style.setProperty('--color-error',    cs.error);
  root.style.setProperty('--color-on-error', cs.onError);
  root.style.setProperty('--color-outline',  cs.outline);

  // גזירת גוונים עדינים עם שקיפות (לרקעי hover, הדגשות קלות)
  root.style.setProperty('--color-primary-subtle',   hexToRgba(cs.primary, 0.12));
  root.style.setProperty('--color-secondary-subtle', hexToRgba(cs.secondary, 0.12));

  // כיסוי על-ידי המצב (כהה/בהיר) עם class ב-body
  document.body.classList.toggle('dark-mode', theme.mode === 'dark');

  if (theme.typography) {
    const t = theme.typography;
    root.style.setProperty('--font-main', `'${t.fontFamily}', 'David', serif`);
    root.style.setProperty('--font-size-base', `${t.fontSize}px`);
    root.style.setProperty('--line-height', String(t.lineHeight));
  }
}

function hexToRgba(hex, alpha) {
  const r = parseInt(hex.slice(1, 3), 16);
  const g = parseInt(hex.slice(3, 5), 16);
  const b = parseInt(hex.slice(5, 7), 16);
  return `rgba(${r}, ${g}, ${b}, ${alpha})`;
}
```

---

## Color Roles — מה כל צבע משמש לו

| משתנה CSS | תפקיד M3 | שימושים נפוצים |
|-----------|----------|----------------|
| `--color-primary` | Primary | כפתורים ראשיים, גבול יום נבחר, קישורים, הדגשות חשובות |
| `--color-on-primary` | On Primary | טקסט/אייקון בתוך אלמנטים בצבע primary |
| `--color-secondary` | Secondary | הדגשות משניות, chips, אינדיקטורים |
| `--color-on-secondary` | On Secondary | טקסט/אייקון על רקע secondary |
| `--color-surface` | Surface | רקע כרטיסים, חלוניות, תיבות קלט |
| `--color-on-surface` | On Surface | טקסט ראשי, אייקונים |
| `--color-surface-container-highest` | Surface Container Highest | פופאוברים, דיאלוגים, שכבות מוגבהות |
| `--color-error` | Error | הודעות שגיאה, גבולות שגיאה |
| `--color-on-error` | On Error | טקסט בתוך אלמנטי שגיאה |
| `--color-outline` | Outline | מסגרות, מפרידים, קווי גבול עדינים |
| `--color-primary-subtle` | — (נגזר) | רקעי hover, הדגשה קלה, badge |
| `--color-secondary-subtle` | — (נגזר) | רקעי hover על אלמנטים משניים |

### צבעים נוספים שאפשר לגזור

Material 3 מגדיר צבעי `*Container` שאינם חלק מה-API. ניתן לקרב אותם עם שקיפות:

```css
/* primaryContainer ≈ primary + שקיפות נמוכה */
.chip-primary {
  background: var(--color-primary-subtle);   /* ~12% opacity */
  color: var(--color-primary);
  border-radius: var(--radius-pill);
}

/* בדוגמה זו: שבת/יום טוב ב-primary subtle — בדיוק כמו הלוח הפנימי */
.day-cell.shabbat {
  background: var(--color-secondary-subtle);
}
```

---

## מצב כהה ובהיר

ה-API מספק `mode: 'light' | 'dark'`. אפשר להשתמש ב-class על body:

```css
/* ברירת מחדל (בהיר) */
body {
  background: var(--color-surface);
  color: var(--color-on-surface);
}

/* כהה — אם רוצים לשנות משהו ספציפי שאינו מכוסה ע"י הצבעים */
body.dark-mode .card {
  box-shadow: 0 1px 4px rgba(0, 0, 0, 0.4);
}
```

בדרך כלל ה-color roles (primary, surface וכד') כבר מותאמים אוטומטית למצב הכהה ע"י ה-API — אין צורך ב-overrides רבים.

---

## צורות וגדלים (Shape)

אוצריא משתמשת בסולם עקבי של `border-radius`. כדי להיראות אחיד:

| גודל | ערך | שימוש |
|------|-----|--------|
| `--radius-sm` | `8px` | תאי לוח, שדות קלט, chips קטנים |
| `--radius-md` | `12px` | כרטיסי תוכן (card) |
| `--radius-lg` | `16px` | חלוניות, פאנלים |
| `--radius-pill` | `999px` | pills, chips עגולים, badges |

```css
.card {
  border-radius: var(--radius-md);
  background: var(--color-surface);
  border: 1px solid var(--color-outline);
  padding: 16px;
}

.chip {
  border-radius: var(--radius-pill);
  background: var(--color-primary-subtle);
  color: var(--color-primary);
  padding: 4px 12px;
  font-size: 0.8rem;
  font-weight: 600;
}
```

---

## כרטיס (Card)

דפוס הבסיס לתוכן מקובץ:

```css
.card {
  background: var(--color-surface);
  border: 1px solid var(--color-outline);
  border-radius: var(--radius-md);
  padding: 16px 20px;
  /* אין elevation (elevation: 0) — סגנון M3 flat */
}

.card-title {
  font-size: 1rem;
  font-weight: 700;
  color: var(--color-primary);
  margin-bottom: 12px;
}
```

---

## כפתורים

### כפתור ראשי (Filled)
לפעולה מומלצת/חיובית:

```css
.btn-primary {
  background: var(--color-primary);
  color: var(--color-on-primary);
  border: none;
  border-radius: var(--radius-sm);
  padding: 9px 20px;
  font-family: var(--font-main);
  font-size: 0.95rem;
  font-weight: 600;
  cursor: pointer;
  transition: opacity 0.15s;
}
.btn-primary:hover    { opacity: 0.88; }
.btn-primary:disabled { opacity: 0.45; cursor: default; }
```

### כפתור משני (Tonal)
לפעולה ניטרלית/פחות חשובה:

```css
.btn-secondary {
  background: var(--color-secondary-subtle);
  color: var(--color-on-surface);
  border: 1px solid var(--color-outline);
  border-radius: var(--radius-sm);
  padding: 9px 20px;
  font-family: var(--font-main);
  font-size: 0.95rem;
  font-weight: 600;
  cursor: pointer;
  transition: opacity 0.15s;
}
.btn-secondary:hover    { opacity: 0.85; }
.btn-secondary:disabled { opacity: 0.45; cursor: default; }
```

---

## שדות קלט

```css
.input {
  padding: 9px 12px;
  border: 1.5px solid var(--color-outline);
  border-radius: var(--radius-sm);
  font-family: var(--font-main);
  font-size: 0.95rem;
  color: var(--color-on-surface);
  background: var(--color-surface);
  direction: rtl;
  outline: none;
  transition: border-color 0.15s;
  width: 100%;
  box-sizing: border-box;
}
.input:focus {
  border-color: var(--color-primary);
}
```

---

## טיפוגרפיה

```css
body {
  font-family: var(--font-main);
  font-size: var(--font-size-base);
  line-height: var(--line-height);
  direction: rtl;
}

/* היררכיה מומלצת (יחסית ל-base) */
.text-headline   { font-size: 1.4em; font-weight: 700; }
.text-title      { font-size: 1.1em; font-weight: 700; }
.text-body       { font-size: 1em;   font-weight: 400; }
.text-body-sm    { font-size: 0.88em; }
.text-label      { font-size: 0.78em; font-weight: 600; }
```

> **שים לב:** `font-size-base` מוגדר לפי הגדרת המשתמש. הימנע מ-`font-size: 16px` קשיח — השתמש ב-`em` / `rem` יחסית ל-base.

---

## אינטראקציות ואנימציות

### Hover
```css
.interactive {
  transition: background 0.15s, box-shadow 0.15s;
  cursor: pointer;
}
.interactive:hover {
  background: color-mix(in srgb, var(--color-primary) 8%, transparent);
}
```

### מעברים בין מצבים
```css
/* Fade קל בין תכנים */
.fade-in {
  animation: fadeIn 0.2s ease-out;
}
@keyframes fadeIn {
  from { opacity: 0; transform: translateY(4px); }
  to   { opacity: 1; transform: translateY(0); }
}
```

### ספינר טעינה
```css
.spinner {
  width: 36px; height: 36px;
  border: 3px solid var(--color-outline);
  border-top-color: var(--color-primary);
  border-radius: 50%;
  animation: spin 0.75s linear infinite;
}
@keyframes spin { to { transform: rotate(360deg); } }
```

---

## אינדיקטור מצב (State Indicator)

לאלמנט שיש לו מצבים (active, selected, error):

```css
.item { border-radius: var(--radius-sm); padding: 8px 12px; transition: background 0.15s; }
.item.selected  { background: var(--color-primary-subtle); color: var(--color-primary); font-weight: 700; }
.item.error     { background: rgba(179, 38, 30, 0.1); color: var(--color-error); }
.item:hover:not(.selected) { background: var(--color-secondary-subtle); }
```

---

## מיכל שלד אפליקציה

תבנית מומלצת לתוסף שלם:

```html
<!DOCTYPE html>
<html lang="he" dir="rtl">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <style>
    *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }

    :root {
      --color-primary: #6750A4; --color-on-primary: #FFFFFF;
      --color-secondary: #625B71; --color-on-secondary: #FFFFFF;
      --color-surface: #FFFBFE; --color-on-surface: #1C1B1F;
      --color-surface-container-highest: #E6E0E9;
      --color-error: #B3261E; --color-on-error: #FFFFFF;
      --color-outline: #79747E;
      --color-primary-subtle: rgba(103,80,164,0.12);
      --color-secondary-subtle: rgba(98,91,113,0.12);
      --font-main: 'Frank Ruhl Libre', 'David', serif;
      --font-size-base: 18px;
      --line-height: 1.5;
      --radius-sm: 8px; --radius-md: 12px;
      --radius-lg: 16px; --radius-pill: 999px;
    }

    body {
      font-family: var(--font-main);
      font-size: var(--font-size-base);
      line-height: var(--line-height);
      background: var(--color-surface);
      color: var(--color-on-surface);
      direction: rtl;
      min-height: 100vh;
    }
  </style>
</head>
<body>

  <!-- תוכן התוסף -->

  <script>
    function applyTheme(theme) {
      if (!theme || !theme.colorScheme) return;
      const cs = theme.colorScheme;
      const r = document.documentElement;
      r.style.setProperty('--color-primary',    cs.primary);
      r.style.setProperty('--color-on-primary',  cs.onPrimary);
      r.style.setProperty('--color-secondary',   cs.secondary);
      r.style.setProperty('--color-on-secondary', cs.onSecondary);
      r.style.setProperty('--color-surface',     cs.surface);
      r.style.setProperty('--color-on-surface',  cs.onSurface);
      r.style.setProperty('--color-surface-container-highest', cs.surfaceContainerHighest);
      r.style.setProperty('--color-error',    cs.error);
      r.style.setProperty('--color-on-error', cs.onError);
      r.style.setProperty('--color-outline',  cs.outline);
      document.body.classList.toggle('dark-mode', theme.mode === 'dark');
      if (theme.typography) {
        r.style.setProperty('--font-main', `'${theme.typography.fontFamily}', 'David', serif`);
        r.style.setProperty('--font-size-base', `${theme.typography.fontSize}px`);
        r.style.setProperty('--line-height', String(theme.typography.lineHeight));
      }
    }

    Otzaria.on('plugin.boot',   p => applyTheme(p.theme));
    // ⚠️ דורש הרשאה: events.subscribe:theme.changed
    Otzaria.on('theme.changed', applyTheme);
  </script>
</body>
</html>
```

---

## פאנל Overlay צף

אוצריא משתמשת בפאנל "הגדרות הקשר" שצף מעל התוכן מהצד — ראה לדוגמה את חלונית ההגדרות בלוח השנה. דפוס זה: scrim (שכבת רקע כהה) + פאנל שנכנס בהחלקה, גובה מלא, פינות מעוגלות.

הנה המקבילה ב-HTML/CSS:

```css
/* ── Scrim ───────────────────────────────────────── */
.overlay-scrim {
  position: fixed;
  inset: 0;
  background: rgba(0, 0, 0, 0.30);
  opacity: 0;
  pointer-events: none;
  transition: opacity 0.2s;
  z-index: 100;
}
.overlay-scrim.open {
  opacity: 1;
  pointer-events: auto;
}

/* ── Panel ───────────────────────────────────────── */
.overlay-panel {
  position: fixed;
  top: 10px;
  bottom: 12px;
  /* ימין ב-RTL: */
  right: 10px;
  width: 360px;
  background: var(--color-secondary-subtle);
  /* כמו secondaryContainer — secondary עם ~12% opacity מעל surface */
  background: color-mix(in srgb, var(--color-secondary) 15%, var(--color-surface));
  border-radius: 18px;
  box-shadow: 0 8px 24px rgba(0, 0, 0, 0.18);
  padding: 20px;
  overflow-y: auto;
  z-index: 101;
  opacity: 0;
  transform: translateX(30px);
  pointer-events: none;
  transition: opacity 0.2s, transform 0.25s cubic-bezier(0.4, 0, 0.2, 1);
}
.overlay-panel.open {
  opacity: 1;
  transform: translateX(0);
  pointer-events: auto;
}
```

```javascript
function openOverlay() {
  document.querySelector('.overlay-scrim').classList.add('open');
  document.querySelector('.overlay-panel').classList.add('open');
}
function closeOverlay() {
  document.querySelector('.overlay-scrim').classList.remove('open');
  document.querySelector('.overlay-panel').classList.remove('open');
}
document.querySelector('.overlay-scrim').addEventListener('click', closeOverlay);
```

---

## פופאובר ממוקם (Anchored Popover)

אוצריא משתמשת בפופאוברים שנפתחים **ליד הכפתור שנלחץ** — ראה לדוגמה כפתור "מעבר לתאריך" בסרגל לוח השנה. דפוס זה: מיכל `position: absolute` בתוך `position: relative`, עם `box-shadow` וצבע `surfaceContainerHighest`.

```css
.popover-anchor {
  position: relative;
  display: inline-block;
}

.popover {
  position: absolute;
  top: calc(100% + 6px);  /* מתחת לכפתור */
  right: 0;               /* ב-RTL: מיושר לימין */
  width: 320px;
  background: var(--color-surface-container-highest);
  border-radius: var(--radius-md);
  box-shadow: 0 4px 20px rgba(0, 0, 0, 0.15);
  border: 1px solid var(--color-outline);
  padding: 16px;
  z-index: 200;
  /* --- הנפשה --- */
  opacity: 0;
  transform: translateY(-6px) scale(0.97);
  pointer-events: none;
  transform-origin: top right;
  transition: opacity 0.15s, transform 0.15s cubic-bezier(0.4, 0, 0.2, 1);
}
.popover.open {
  opacity: 1;
  transform: translateY(0) scale(1);
  pointer-events: auto;
}
```

```javascript
// פתיחת/סגירת פופאובר + סגירה בלחיצה מחוץ
const btn     = document.querySelector('.popover-trigger');
const popover = document.querySelector('.popover');

btn.addEventListener('click', function(e) {
  e.stopPropagation();
  popover.classList.toggle('open');
});
document.addEventListener('click', function() {
  popover.classList.remove('open');
});
popover.addEventListener('click', function(e) {
  e.stopPropagation(); // לא לסגור בלחיצה בתוך הפופאובר
});
```

**מתי overlay vs. popover?**
- **Overlay** — תוכן עמוק (הגדרות, רשימות ארוכות). גובה מלא, נכנס מהצד.
- **Popover** — תוכן קצר שקשור לכפתור ספציפי (בורר תאריך, תפריט קצר). מוצג ממש מתחת לכפתור.

---

## דברים שיש להימנע מהם

| שגוי | נכון |
|------|------|
| `color: #6750A4` | `color: var(--color-primary)` |
| `background: white` | `background: var(--color-surface)` |
| `font-size: 16px` (קשיח) | `font-size: 0.9em` (יחסי) |
| `border: 1px solid #ccc` | `border: 1px solid var(--color-outline)` |
| `border-radius: 20px` (שרירותי) | `border-radius: var(--radius-md)` |
| ללא `Otzaria.on('theme.changed')` | תמיד להקשיב לשינוי theme (עם הרשאת `events.subscribe:theme.changed`) |

---

## אייקון לתוסף

אוצריא מאפשרת לתוסף להציג אייקון בשני מקומות:

1. **שורת הטאבים במסך "כלים"** — ליד שם הכרטיסייה.
2. **תפריט לחצן ימין במסכי עיון** — ליד שם הפריט בתפריט ההקשר.

שני המקומות משתמשים באייקונים מספריית **FluentUI System Icons** בלבד (אותה ספריה שאוצריא עצמה משתמשת בה).

---

### 1. אייקון בשורת הטאבים (מסך כלים)

מוגדר ב-`manifest.json`, בתוך `contributes.toolTab`:

```json
"contributes": {
  "toolTab": {
    "title": "לוח שנה",
    "order": 100,
    "defaultPinned": true,
    "iconName": "calendar_24_regular"
  }
}
```

| שדה | סוג | ברירת מחדל | תיאור |
|-----|-----|------------|-------|
| `iconName` | `string` | ללא (ללא אייקון) | שם אייקון FluentUI 24px, המסתיים ב-`_24_regular` או `_24_filled` |

#### כיצד בוחרים `iconName`?

גלוש ל-[FluentUI System Icons](https://github.com/microsoft/fluentui-system-icons) ובחר אייקון, או חפש בקוד אוצריא שמות בסגנון `FluentIcons.xxx_24_regular`. כלל השמות:
- `<base>_24_regular` — גרסה רגילה (קווים)
- `<base>_24_filled` — גרסה מלאה

**דוגמאות:**

| `iconName` |
|------------|
| `calendar_24_regular` |
| `book_24_regular` |
| `search_24_regular` |
| `star_24_filled` |

> **טיפ:** השתמש תמיד בגודל `_24_` — אלה הגדלים שאוצריא מציגה בטאבים. שם שאינו תואם תבנית זו יידחה בולידציה. שמות שאינם קיימים במפת האייקונים של אוצריא יוצגו כפאזל ברירת מחדל.
>
> **למה לא codepoint?** ב-Release Flutter מבצע tree-shaking של פונטי אייקונים — הוא משאיר רק את האייקונים שהוא רואה בקוד כקבועים. שימוש ב-`iconName` עם מפה סטטית מאפשר את האופטימיזציה הזו; codepoint דינמי מתוך manifest היה שובר אותה.

---

### 2. אייקון בתפריט הקשר (לחצן ימין במסך עיון)

תפריט ההקשר מוצג **במסכי טקסט בלבד** (CombinedView ו-PageShape). מסך PDF אינו תומך בפריטי תוסף בתפריט ההקשר כרגע.

כאשר מוסיפים פריט לתפריט ההקשר עם `reader.addContextMenuItem`, ניתן לציין שדה `icon`:

```javascript
await Otzaria.call('reader.addContextMenuItem', {
  id: 'my-bookmark-item',
  label: 'הוסף לסימניות שלי',
  icon: 'bookmark_24_regular'   // שם אייקון מ-FluentUI System Icons בגודל 24 (אופציונלי)
});
```

> **הערה:** השדה `icon` הוא אופציונלי. ללא אייקון הפריט עדיין יופיע — רק ללא אייקון לצידו.
>
> נתמכים כל אייקוני FluentUI System Icons בגודל 24 (למשל `bookmark_24_regular`, `star_24_filled`). שם לא מוכר לא ישגיא — הפריט יוצג ללא אייקון.

---

## דוגמה חיה

הקובץ `index.html` בתיקיית ה-SDK הוא דוגמת לוח שנה עובדת. הוא מדגים שימוש ב-API (אירועי boot, theme, calendar) אך אינו מיישם את כל דפוסי המדריך הזה (למשל, חסרים בו צבעי container ועדכון theme). השתמש בו כנקודת מוצא ל-API, ובמדריך זה כסמכות לעיצוב.
