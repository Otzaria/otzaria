# מדריך פיתוח תוספים לאוצריא

גרסת SDK: **1.0**  
תאריך עדכון אחרון: אפריל 2026

---

## תוכן עניינים

1. [מבוא](#מבוא)
2. [מבנה תוסף](#מבנה-תוסף)
3. [קובץ ה-manifest](#קובץ-ה-manifest)
4. [ה-SDK](#ה-sdk)
5. [אירועי מחזור חיים](#אירועי-מחזור-חיים)
6. [Host API — מדריך מלא](#host-api--מדריך-מלא)
7. [פרסום נתונים חזרה לאפליקציה](#פרסום-נתונים-חזרה-לאפליקציה)
8. [ניהול ערכת נושא](#ניהול-ערכת-נושא)
9. [אחסון פרטי](#אחסון-פרטי)
10. [הרשאות](#הרשאות)
11. [אבטחה ומגבלות](#אבטחה-ומגבלות)
12. [packaging — יצירת קובץ `.otzplugin`](#packaging--יצירת-קובץ-otzplugin)
13. [התקנה ובדיקה](#התקנה-ובדיקה)
14. [שגיאות נפוצות](#שגיאות-נפוצות)
15. [דוגמה מלאה](#דוגמה-מלאה)

---

## מבוא

תוסף אוצריא הוא **קובץ ZIP** עם הסיומת `.otzplugin`.  
לאחר התקנה, אוצריא פותחת את קובץ ה-HTML של התוסף ב-WebView מוגן ומזריקה אוטומטית את ה-SDK.

התוסף יכול:
- לצרוך נתוני ספרייה, לוח שנה, הגדרות וכו'
- לפתוח ספרים בקורא
- לפרסם אירועי לוח שנה חזרה לאפליקציה
- לשמור נתונים פרטיים (local key-value store)
- להציג הודעות ודיאלוגים מובנים

---

## מבנה תוסף

```
my-plugin/
├── manifest.json          ← חובה
├── index.html             ← נקודת הכניסה (entrypoint)
├── icon/
│   └── icon.png           ← אייקון 64×64 (PNG)
├── css/
│   └── style.css
└── js/
    └── app.js
```

> **הערה:** כל הקבצים חייבים להיות בתוך תיקיית התוסף בלבד.  
> אסור לטעון קבצים ממקום אחר (לא `file:///` חיצוני, לא רשת אלא אם כן ניתנה הרשאת `network.access`).

---

## קובץ ה-manifest

`manifest.json` הוא הקובץ הראשי שאוצריא קוראת בעת התקנה.

### דוגמה מלאה

```json
{
  "schemaVersion": 1,
  "id": "com.mycompany.my-plugin",
  "name": "שם התוסף",
  "version": "1.0.0",
  "description": "תיאור קצר של מה שהתוסף עושה.",
  "author": "שם המפתח",
  "homepage": "https://example.com/my-plugin",
  "entrypoint": "index.html",
  "icon": "icon/icon.png",
  "minAppVersion": "5.0.0",
  "sdkVersion": "1.x",
  "permissions": [
    "app.info.read",
    "library.books.read",
    "calendar.read",
    "plugin.storage.read",
    "plugin.storage.write",
    "ui.feedback"
  ],
  "network": {
    "enabled": false,
    "allowlist": []
  },
  "contributes": {
    "toolTab": {
      "title": "שם הטאב",
      "order": 200,
      "defaultPinned": true,
      "iconCodepoint": 983685,
      "iconVariant": "regular"
    },
    "publishedDataTypes": []
  }
}
```

### שדות חובה

| שדה | סוג | תיאור |
|-----|-----|--------|
| `schemaVersion` | `number` | תמיד `1` |
| `id` | `string` | מזהה ייחודי בסגנון reverse-domain: `com.company.plugin-name` |
| `name` | `string` | שם התוסף כפי שיוצג למשתמש |
| `version` | `string` | גרסה בפורמט SemVer: `major.minor.patch` |
| `entrypoint` | `string` | נתיב יחסי לקובץ HTML הראשי |
| `minAppVersion` | `string` | גרסת אוצריא המינימלית הנתמכת |
| `sdkVersion` | `string` | גרסת ה-SDK הנדרשת (כעת `"1.x"`) |

### שדות חובה לצורך העלאה לחנות

בנוסף לשדות החובה הבסיסיים של `manifest.json`, תוסף שמיועד לפרסום בחנות צריך לכלול גם מטא-דאטה שיווקי ותאימות גרסאות.

| שדה | חובה | תיאור |
|-----|------|--------|
| `name` | ✓ | שם התוסף כפי שיוצג למשתמש |
| `author` | ✓ | שם המפתח או הגוף המפרסם |
| `description` | ✓ | תיאור קצר של התוסף |
| `version` | ✓ | גרסת התוסף |
| `stability` | ✓ | מצב שחרור: `stable`, `beta`, או `experimental` |
| `minAppVersion` | ✓ | גרסת אוצריא המינימלית הנתמכת |

אם בעתיד יתווסף ולידטור לחנות, יש להתייחס לשדות אלו כאל דרישות חובה לפרסום ועליהם להיות מדוייקים גם אם חלקם אינם נדרשים לצורך טעינה מקומית במצב פיתוח.

### שדות אופציונליים

| שדה | ברירת מחדל | תיאור |
|-----|-----------|--------|
| `description` | `""` | תיאור מורחב |
| `author` | `""` | שם המפתח |
| `homepage` | `""` | כתובת לדף הבית של התוסף, למשל עמוד GitHub, תיעוד, או אתר פרויקט |
| `icon` | `null` | נתיב לאייקון (PNG, 64×64 מומלץ) |
| `maxAppVersion` | `null` | גרסת אוצריא המקסימלית הנתמכת |
| `network.enabled` | `false` | האם להצהיר על שימוש ברשת (חובה כדי להפעיל את מנגנון הרשת בתוסף) |
| `network.allowlist` | `[]` | **שדה הצהרתי בלבד** — לתיעוד/שקיפות מול המשתמש. רשימת ה-URLs שאליהם תוסף יכול לגשת בפועל מנוהלת אך ורק על-ידי אוצריא בקוד (`pluginNetworkAllowlist` ב-[`lib/plugins/models/plugin_network_allowlist.dart`](../lib/plugins/models/plugin_network_allowlist.dart)). הצהרה ב-manifest **אינה** מעניקה גישה. |
| `contributes.toolTab.title` | שם התוסף | כותרת הטאב |
| `contributes.toolTab.order` | `900` | סדר הופעה בטאבים (מספר נמוך = קודם) |
| `contributes.toolTab.defaultPinned` | `true` | האם להצמיד אוטומטית בהתקנה |

`homepage` הוא שדה אופציונלי, אבל מומלץ מאוד כשמעלים תוסף לחנות. זה המקום לשים קישור לעמוד ה־GitHub של התוסף, לתיעוד, לאתר הפרויקט, או לכל דף רשמי אחר שמסביר על התוסף ונותן למשתמש מקום לקבל מידע נוסף.
| `contributes.toolTab.iconCodepoint` | `null` | codepoint עשרוני של אייקון Fluent שיוצג בטאב |
| `contributes.toolTab.iconVariant` | `"regular"` | וריאנט האייקון: `regular` או `filled` |
| `contributes.publishedDataTypes` | `[]` | סוגי נתונים שהתוסף מפרסם |

אם מגדירים `iconVariant`, חייבים להגדיר גם `iconCodepoint`.

הערה: `iconCodepoint` הוא הערך העשרוני של אייקון Fluent. לדוגמה, `calendar_24_regular` הוא `983685`, ו-`calendar_24_filled` הוא `983704`.

---

## ה-SDK

ה-SDK מוזרק **אוטומטית** לכל WebView של תוסף. אין צורך להוסיף תגית `<script>`.

הוא חושף `window.Otzaria` עם שני מנגנונות:

### 1. `Otzaria.call(method, payload)` — קריאת API

```javascript
const res = await Otzaria.call('library.findBooks', { query: 'רמב"ם', limit: 10 });
if (res.success) {
  console.log(res.data); // BookMeta[]
} else {
  console.error(res.error.code, res.error.message);
}
```

**מבנה התשובה תמיד:**
```json
{ "success": true,  "data": <תוצאה>,  "error": null }
{ "success": false, "data": null,      "error": { "code": "...", "message": "..." } }
```

### 2. `Otzaria.on(event, callback)` / `Otzaria.off(event, callback)` — אירועים

```javascript
Otzaria.on('plugin.boot', (payload) => {
  // payload.theme, payload.app, payload.permissions
});

Otzaria.on('theme.changed', (theme) => {
  applyTheme(theme.colorScheme);
});

// ביטול הרשמה:
const handler = (detail) => { ... };
Otzaria.on('calendar.date_changed', handler);
Otzaria.off('calendar.date_changed', handler); // חייב להיות אותו reference
```

---

## אירועי מחזור חיים

| אירוע | פעם אחת? | payload |
|-------|----------|---------|
| `plugin.boot` | ✅ כן | `BootPayload` (ראה להלן) |
| `plugin.ready` | ✅ כן | (ללא) |
| `theme.changed` | 🔁 חוזר | `ThemePayload` |
| `navigation.changed` | 🔁 חוזר | `{ screen: string }` |
| `reader.current_book_changed` | 🔁 חוזר | `{ bookId: string, index: number }` |
| `calendar.date_changed` | 🔁 חוזר | `{ date: string }` |
| `workspace.changed` | 🔁 חוזר | `{ workspaceId: string }` |
| `settings.changed` | 🔁 חוזר | `{ key: string, newValue: * }` |
| `plugin.permissions_changed` | 🔁 חוזר | `{ permissions: string[] }` |

### מבנה BootPayload

```javascript
Otzaria.on('plugin.boot', (payload) => {
  payload.plugin.id          // מזהה התוסף
  payload.plugin.version     // גרסת התוסף
  payload.app.version        // גרסת אוצריא
  payload.app.platform       // 'windows' | 'linux' | 'macos' | 'android' | 'ios'
  payload.app.locale         // 'he-IL'
  payload.app.textDirection  // 'rtl'
  payload.theme              // ThemePayload (ראה §ניהול ערכת נושא)
  payload.permissions        // string[] — הרשאות שאושרו
});
```

> ⚠️ **חשוב:** כל הלוגיקה הראשונית חייבת להיות בתוך callback של `plugin.boot`.  
> לא לקרוא ל-`Otzaria.call()` לפני שאירוע `plugin.boot` ירה.

---

## Host API — מדריך מלא

### app.*

| Method | הרשאה | תיאור |
|--------|-------|--------|
| `app.getInfo` | `app.info.read` | גרסת האפליקציה, פלטפורמה |
| `app.getTheme` | `app.info.read` | ערכת נושא מלאה (colorScheme + typography) |
| `app.getLocale` | `app.info.read` | locale ו-textDirection |

### library.*

| Method | הרשאה | פרמטרים | החזרה |
|--------|-------|----------|-------|
| `library.findBooks` | `library.books.read` | `{ query, limit? }` | `BookMeta[]` |
| `library.getBookMetadata` | `library.books.read` | `{ bookId }` | `BookMeta \| null` |
| `library.listRecentBooks` | `library.books.read` | — | `{ bookId, title, ref }[]` |
| `library.getBookContent` | `library.content.read` | `{ bookId, offset?, limit?, section? }` | `string` (max 5000 תווים) |
| `library.getBookToc` | `library.content.read` | `{ bookId }` | `TocEntry[]` |

### search.*

| Method | הרשאה | פרמטרים | החזרה |
|--------|-------|----------|-------|
| `search.fullText` | `search.fulltext.read` | `{ query, limit? }` | `SearchResult[]` |

### reader.*

| Method | הרשאה | פרמטרים | החזרה |
|--------|-------|----------|-------|
| `reader.openBook` | `reader.open` | `{ bookId, index?, searchQuery? }` | `boolean` |
| `reader.openBookAtRef` | `reader.open` | `{ bookId, ref, index? }` | `boolean` |
| `reader.getCurrentState` | `reader.open` | — | `ReaderState` |

### navigation.*

| Method | הרשאה | פרמטרים | החזרה |
|--------|-------|----------|-------|
| `navigation.goTo` | `navigation.write` | `{ target: 'library'\|'reading'\|'more'\|'settings' }` | `boolean` |

### notes.*

| Method | הרשאה | פרמטרים | החזרה |
|--------|-------|----------|-------|
| `notes.list` | `notes.read` | `{ bookId }` | `Note[]` |
| `notes.getBookNotesSummary` | `notes.read` | — | `{ bookId, noteCount, lastModified }[]` |
| `notes.add` | `notes.write` | `{ bookId, lineNumber, content }` | `boolean` |
| `notes.update` | `notes.write` | `{ bookId, noteId, content }` | `boolean` |
| `notes.delete` | `notes.write` | `{ bookId, noteId }` | `boolean` |

### ui.*

| Method | הרשאה | פרמטרים | החזרה |
|--------|-------|----------|-------|
| `ui.showMessage` | `ui.feedback` | `{ message }` | `boolean` |
| `ui.showSuccess` | `ui.feedback` | `{ message }` | `boolean` |
| `ui.showError` | `ui.feedback` | `{ message }` | `boolean` |
| `ui.showConfirm` | `ui.feedback` | `{ title, content }` | `{ confirmed: boolean }` |
| `ui.showWarning` | `ui.feedback` | `{ title, content, subtitle? }` | `{ confirmed: boolean }` |

### storage.*

| Method | הרשאה |
|--------|-------|
| `storage.get`    | `plugin.storage.read` |
| `storage.set`    | `plugin.storage.write` |
| `storage.remove` | `plugin.storage.write` |
| `storage.list`   | `plugin.storage.read` |

### settings.*

| Method | הרשאה | פרמטרים |
|--------|-------|----------|
| `settings.get`     | `settings.read` | `{ key }` |
| `settings.getMany` | `settings.read` | `{ keys: string[] }` |

**מפתחות מותרים:**
`keyDarkMode`, `keyFollowSystemTheme`, `keySwatchColor`, `keyDarkSwatchColor`,
`keyFontSize`, `keyFontFamily`, `keyCommentatorsFontFamily`, `keyCommentatorsFontSize`,
`keyLineHeight`, `keySelectedCity`, `keyCalendarType`, `keyShowTeamim`,
`keyDefaultNikud`, `keyRemoveNikudFromTanach`, `keyReplaceHolyNames`,
`keyLibraryViewMode`, `keyAlignTabsToRight`, `keyCopyWithHeaders`, `keyCopyHeaderFormat`

> ⚠️ מפתחות לא-מורשים (סיסמאות, נתיבים, credentials) יחזירו `null` ולא ישלחו שגיאה.

### calendar.*

| Method | הרשאה | החזרה |
|--------|-------|-------|
| `calendar.getSelectedDate` | `calendar.read` | `string` (ISO 8601) |
| `calendar.getDailyTimes`   | `calendar.read` | `Record<string, string>` |
| `calendar.getJewishDate`   | `calendar.read` | `JewishDate` |
| `calendar.getEvents`       | `calendar.read` | `CalendarEvent[]` |

### publishedData.*

| Method | הרשאה | פרמטרים |
|--------|-------|----------|
| `publishedData.upsert`  | `published_data.write` | `{ type, scope, key, payload }` |
| `publishedData.remove`  | `published_data.write` | `{ type, scope, key }` |
| `publishedData.listOwn` | `published_data.write` | — |

---

## פרסום נתונים חזרה לאפליקציה

זהו המנגנון שמאפשר לתוסף להשפיע על האפליקציה.

### סוגי נתונים נתמכים

| type | תיאור |
|------|--------|
| `calendar.event` | אירוע לוח שנה — יוצג ב-`CalendarScreen` |
| `saved.query` | שאילתת חיפוש שמורה |
| `note.draft` | טיוטת הערה |
| `reference.link` | קישור להפניה |
| `tool.badge` | badge עדכון בטאב |

### ערכי scope

| scope | תיאור |
|-------|--------|
| `"global"` | גלובלי — גלוי בכל מצב |
| `"workspace:<id>"` | גלוי רק בסביבת עבודה ספציפית |
| `"book:<bookId>"` | גלוי רק כשהספר הזה פתוח |

### דוגמה — פרסום אירוע לוח שנה

```javascript
await Otzaria.call('publishedData.upsert', {
  type:    'calendar.event',
  scope:   'global',
  key:     'myPlugin:event:2026-04-05',   // מפתח ייחודי
  payload: {
    title:      'שקיעה',
    startsAt:   '2026-04-05T19:11:00+03:00',
    source:     'לוח שנה הלכתי',
    importance: 'high',                   // 'high' | 'medium' | 'low'
  },
});
```

> **כלל המפתח:** השתמש ב-`<pluginId>:<type>:<identifier>` כפורמט למפתח — מניע התנגשויות.

---

## ניהול ערכת נושא

כדי שהתוסף ייראה כמו חלק מאוצריא, יש לאמץ את ה-colorScheme המתקבל ב-boot.

```javascript
function applyTheme(theme) {
  const cs = theme.colorScheme;
  const root = document.documentElement;
  root.style.setProperty('--primary',   cs.primary);
  root.style.setProperty('--onPrimary', cs.onPrimary);
  root.style.setProperty('--surface',   cs.surface);
  root.style.setProperty('--onSurface', cs.onSurface);
  root.style.setProperty('--outline',   cs.outline);
  root.style.setProperty('--error',     cs.error);
  if (theme.typography?.fontFamily) {
    root.style.setProperty('--font', `'${theme.typography.fontFamily}', serif`);
  }
}

Otzaria.on('plugin.boot',    (p) => applyTheme(p.theme));
Otzaria.on('theme.changed',  applyTheme);   // ← חשוב! מעדכן בזמן אמת
```

---

## אחסון פרטי

כל תוסף מקבל storage מבודד — לא משותף עם תוספים אחרים.

```javascript
// שמירה
await Otzaria.call('storage.set',    { key: 'myKey', value: { count: 42 } });

// קריאה
const { data } = await Otzaria.call('storage.get',  { key: 'myKey' });

// מחיקה
await Otzaria.call('storage.remove', { key: 'myKey' });

// רשימת מפתחות
const { data: keys } = await Otzaria.call('storage.list');
```

- אפשר לשמור כל ערך JSON-serializable
- הנתונים שורדים סגירה של אוצריא
- הנתונים **נמחקים** בעת הסרת התוסף

---

## הרשאות

התוסף מצהיר על ההרשאות שלו ב-manifest. בעת התקנה, המשתמש רואה את ההרשאות ומאשר.

### רשימת ההרשאות המלאה

| הרשאה | מה מאפשרת |
|-------|-----------|
| `app.info.read` | קריאת מידע על האפליקציה |
| `library.books.read` | חיפוש וקריאת metadata של ספרים |
| `library.content.read` | קריאת תוכן ספרים (TOC + טקסט) |
| `search.fulltext.read` | חיפוש טקסט מלא |
| `reader.open` | פתיחת ספרים + קריאת מצב הקורא |
| `navigation.write` | ניווט בין מסכים |
| `notes.read` | קריאת הערות אישיות |
| `notes.write` | הוספה/עדכון/מחיקה של הערות |
| `calendar.read` | גישה לנתוני לוח שנה |
| `settings.read` | קריאת הגדרות מהרשימה המותרת |
| `plugin.storage.read` | קריאת storage פרטי |
| `plugin.storage.write` | כתיבה ל-storage פרטי |
| `published_data.write` | פרסום נתונים לאפליקציה |
| `ui.feedback` | הצגת הודעות ודיאלוגים |
| `network.access` | גישה לרשת (דורש `network.enabled: true` במניפסט + שה-URL מופיע ב-allowlist הגלובלי של אוצריא בקוד) |

> **עיקרון מינימום הרשאות:** בקש רק את מה שאתה צריך בפועל.

---

## אבטחה ומגבלות

### Rate limiting
- מקסימום **100 קריאות לשנייה** לתוסף
- חריגה מחזירה `{ success: false, error: { code: "error.rate_limited" } }`

### Timeout
- כל קריאת `Otzaria.call()` חייבת להסתיים תוך **30 שניות**
- חריגה מחזירה `error.timeout`

### גישת קבצים
התוסף יכול לטעון רק קבצים מ:
- ✅ תיקיית ההתקנה שלו
- ✅ `data:` URLs
- ✅ `blob:` URLs
- ❌ `file:///` לנתיבים חיצוניים
- ❌ קבצי ספרים/נתונים של אוצריא

### רשת
- חסומה כברירת מחדל
- כדי שתוסף יוכל לגשת לרשת חייבות להתקיים **שלוש שכבות** במצטבר:
  1. **הצהרה במניפסט** — `network.enabled: true` (וגם `network.access` ב-`permissions`).
  2. **אישור המשתמש** — המשתמש אישר את הרשאת `network.access` בעת ההתקנה.
  3. **רשימת ה-URLs המאושרים בקוד אוצריא** — ה-URL חייב להיות תואם קידומת לאחד מהערכים ב-`pluginNetworkAllowlist` בקובץ [`lib/plugins/models/plugin_network_allowlist.dart`](../lib/plugins/models/plugin_network_allowlist.dart). זוהי **שכבת האבטחה הקשה** — היא לא ניתנת לעקיפה ע"י הצהרת התוסף.
- ההתאמה היא **התאמת קידומת מלאה** — אם ברשימה רשום `https://github.com/Otzaria/otzaria-library`, יותרו רק URLs שמתחילים במחרוזת זו (ואחריה `/`, `?`, `#` או סוף המחרוזת). `https://github.com/` או `https://github.com/Otzaria/another-repo` ייחסמו.
- ה-`network.allowlist` במניפסט הוא **שדה הצהרתי בלבד** — שימושי לשקיפות מול המשתמש בעת ההתקנה, אך אינו מעניק גישה בפועל.
- אם תוסף מבקש גישה ל-URL שאינו ב-allowlist הגלובלי, יש לפנות למתחזקי אוצריא בבקשה להוסיף אותו.

### window.open
חסום לחלוטין מטעמי אבטחה.

---

## Packaging — יצירת קובץ `.otzplugin`

קובץ `.otzplugin` הוא **ZIP רגיל** עם סיומת שונה.

### מבנה הקובץ

```
my-plugin.otzplugin  (= ZIP)
├── manifest.json
├── index.html
├── icon/
│   └── icon.png
├── css/
│   └── style.css
└── js/
    └── app.js
```

### יצירה ב-macOS / Linux

```bash
cd my-plugin/
zip -r ../my-plugin.otzplugin . -x "*.DS_Store" -x "__MACOSX/*"
```

### יצירה ב-Windows (PowerShell)

```powershell
Compress-Archive -Path .\my-plugin\* -DestinationPath .\my-plugin.zip
Rename-Item .\my-plugin.zip my-plugin.otzplugin
```

### כללים חשובים

1. **manifest.json חייב להיות בשורש ה-ZIP** — לא בתוך תיקיית-מעטפת
2. ה-`id` ב-manifest חייב להיות ייחודי — בפורמט `com.company.plugin-name`
3. ה-`version` חייב לעלות בכל שחרור
4. אל תכלול קבצי פיתוח (`.git/`, `node_modules/`, `*.map`)

### בדיקת תקינות לפני shipping

```bash
# בדיקה שה-manifest תקין:
python3 -c "import json; json.load(open('manifest.json'))"

# בדיקת מבנה ה-ZIP:
unzip -l my-plugin.otzplugin | head -20
```

---

## התקנה ובדיקה

1. פתח את אוצריא ועבור ל-מסך "כלים"
2. לחץ על כפתור 🧩 (תוספים) בפינה
3. לחץ "⊕ התקן תוסף חדש"
4. בחר את קובץ `.otzplugin`
5. אשר את ההרשאות
6. התוסף יופיע בפאנל הצדדי; אם `defaultPinned: true` — יוצג כטאב מיד

### טיפ לפיתוח מהיר

במהלך פיתוח, אפשר לפתח ישירות ב-browser רגיל (Chrome/Firefox) — הוסף stub לבדיקות:

```javascript
// dev-stub.js — לא לכלול בפרודקשן!
if (typeof Otzaria === 'undefined') {
  window.Otzaria = {
    call: async (method, payload) => {
      console.log('[stub] call:', method, payload);
      return { success: true, data: null, error: null };
    },
    on:  (event, cb) => console.log('[stub] on:', event),
    off: (event, cb) => {},
  };

  // סימולציה של boot:
  setTimeout(() => {
    window.dispatchEvent(new CustomEvent('plugin.boot', {
      detail: {
        plugin: { id: 'dev', version: '0.0.0' },
        app: { version: '5.0.0', platform: 'dev', locale: 'he-IL', textDirection: 'rtl' },
        theme: {
          mode: 'light',
          colorScheme: {
            primary: '#1565C0', onPrimary: '#fff',
            secondary: '#6750A4', onSecondary: '#fff',
            surface: '#f8f9fa', onSurface: '#1a1a2e',
            surfaceContainerHighest: '#e0e0e0',
            error: '#b00020', onError: '#fff', outline: '#cbd5e1',
          },
          typography: { fontFamily: 'Frank Ruhl Libre', fontSize: 18, lineHeight: 1.5,
            commentatorsFontFamily: 'Shofar', commentatorsFontSize: 14 },
        },
        permissions: ['app.info.read', 'library.books.read', 'calendar.read',
          'plugin.storage.read', 'plugin.storage.write', 'ui.feedback'],
      },
    }));
  }, 100);
}
```

---

## שגיאות נפוצות

| קוד שגיאה | סיבה | פתרון |
|-----------|------|--------|
| `permission_denied` | הרשאה לא הוצהרה ב-manifest או לא אושרה | הוסף לרשימת `permissions` ב-manifest |
| `error.rate_limited` | יותר מ-100 קריאות/שניה | הוסף debounce/throttle לקוד |
| `error.timeout` | הפעולה לא הושלמה תוך 30 שניות | חלק לפעולות קטנות יותר |
| `error.invalid_params` | פרמטרים חסרים או שגויים | בדוק את החתימה של ה-method |
| `error.internal` | שגיאה פנימית בצד אוצריא | בדוק לוגים בהגדרות → תוספים |

---

## דוגמה מלאה

תוסף דמו מוכן לשימוש נמצא ב-`docs/plugin-sdk/hebrew-calendar-demo.otzplugin`.

קבצי התשתית נמצאים ב:

```
assets/plugin-sdk/
├── otzaria_plugin.js      — ספריית ה-JS שכל תוסף מייבא
├── otzaria_plugin.d.ts    — TypeScript definitions
└── example/               — תוסף דמו (לוח שנה עברי)
    ├── manifest.json      — manifest של תוסף הדמו
    └── index.html         — קוד ה-HTML/JS המלא של תוסף הדמו

docs/plugin-sdk/
├── hebrew-calendar-demo.otzplugin  — תוסף דמו מוכן להתקנה
├── API_REFERENCE.md
└── DESIGN_GUIDE.md
```

### יצירת `.otzplugin` מהדמו

```bash
cd /path/to/otzaria/assets/plugin-sdk/example

zip -r hebrew-calendar-demo.otzplugin \
  manifest.json \
  index.html \
  -x "*.DS_Store"
```

לאחר מכן התקן ב-אוצריא כרגיל.

---

## תמיכה

- GitHub Issues: https://github.com/Otzaria/otzaria/issues
- תג: `plugin-sdk`
