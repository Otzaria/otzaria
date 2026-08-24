# מדריך פיתוח תוספים לאוצריא

גרסת SDK: **1.1**  
תאריך עדכון אחרון: אפריל 2026

מערכת התוספים של אוצריא מאפשרת למפתחי צד-שלישי להרחיב את יכולות האפליקציה באמצעות טכנולוגיות מבוססות רשת (HTML, CSS, JS). תוסף הוא **קובץ ZIP** עם הסיומת `.otzplugin`; לאחר התקנה אוצריא פותחת את קובץ ה-HTML שלו ב-WebView מוגן ומזריקה אוטומטית אובייקט גלובלי `Otzaria` — אין צורך לייבא ספריית JS, רק לקרוא ל-`Otzaria.call(...)` ו-`Otzaria.on(...)`.

---

## תוכן עניינים

1. [מבוא](#מבוא)
2. [מבנה תוסף](#מבנה-תוסף)
3. [קובץ ה-manifest](#קובץ-ה-manifest)
4. [ה-SDK](#ה-sdk)
5. [אירועי מחזור חיים](#אירועי-מחזור-חיים)
6. [Host API — סיכום](#host-api--סיכום)
7. [פרסום נתונים חזרה לאפליקציה](#פרסום-נתונים-חזרה-לאפליקציה)
8. [ניהול ערכת נושא](#ניהול-ערכת-נושא)
9. [אחסון פרטי](#אחסון-פרטי)
10. [הרשאות](#הרשאות)
11. [ריצת רקע (app.run\_on\_startup)](#ריצת-רקע-apprun_on_startup)
12. [אבטחה ומגבלות](#אבטחה-ומגבלות)
13. [מסך "אודות" וקיצור דרך לתוסף](#מסך-אודות-וקיצור-דרך-לתוסף)
14. [מצב פיתוח (Hot Reload)](#מצב-פיתוח-hot-reload) — טעינה מתיקייה או משרת localhost/HMR
15. [אריזה והפצה — יצירת קובץ `.otzplugin`](#אריזה-והפצה--יצירת-קובץ-otzplugin)
16. [פרסום אוטומטי ל-CI (GitHub Action)](#פרסום-אוטומטי-ל-ci-github-action)
17. [התקנה ובדיקה](#התקנה-ובדיקה)
18. [שגיאות נפוצות](#שגיאות-נפוצות)
19. [עיצוב וקבצי עזר](#עיצוב-וקבצי-עזר)
20. [תמיכה](#תמיכה)

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
  "minAppVersion": "0.9.94",
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
      "title": "שם התוסף",
      "order": 200,
      "allowOrderBeforeBuiltIns": false,
      "defaultPinned": true,
      "iconName": "calendar_24_regular"
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
| `name` | `string` | שם התוסף כפי שיוצג למשתמש (עד 14 תווים — מוצג בראש לשונית התוסף ב"כלים") |
| `version` | `string` | גרסה בפורמט SemVer: `major.minor.patch` |
| `entrypoint` | `string` | נתיב יחסי לקובץ HTML הראשי |
| `minAppVersion` | `string` | גרסת אוצריא המינימלית הנתמכת |
| `sdkVersion` | `string` | גרסת ה-SDK הנדרשת (כעת `"1.x"`) |

`minAppVersion` נאכף משני הכיוונים, ולכן שווה לדייק בו:

- **מלמעלה** — התקנה נדחית אם הערך גבוה מגרסת אוצריא המותקנת. ערך "עתידי" הופך
  את התוסף לבלתי-מותקן.
- **מלמטה** — האריזה נדחית אם התוסף קורא ל-API שנוסף בגרסה **מאוחרת** מהערך
  המוצהר. הגרסה שבה נוספה כל מתודה מופיעה בטבלה שבראש
  [API_REFERENCE.md](API_REFERENCE.md).

כלומר הערך הנכון הוא הגרסה שבה נוסף ה-API החדש ביותר שהתוסף משתמש בו — לא
הגרסה האחרונה שיצאה.

### שדות חובה לצורך העלאה לחנות

בנוסף לשדות החובה הבסיסיים של `manifest.json`, תוסף שמיועד לפרסום בחנות צריך לכלול גם מטא-דאטה שיווקי ותאימות גרסאות.

| שדה | חובה | תיאור |
|-----|------|--------|
| `name` | ✓ | שם התוסף כפי שיוצג למשתמש (עד 14 תווים — מוצג בראש לשונית התוסף ב"כלים") |
| `author` | ✓ | שם המפתח או הגוף המפרסם |
| `description` | ✓ | תיאור קצר של התוסף, מוצג בכרטיס בחנות (עד 150 תווים) |
| `version` | ✓ | גרסת התוסף |
| `stability` | | מצב שחרור: `stable`, `beta`, או `experimental`. כשהשדה חסר מונח `stable` — אך ערך שאינו אחד השלושה נדחה |
| `minAppVersion` | ✓ | גרסת אוצריא המינימלית הנתמכת |

החנות אוכפת את השדות האלה בהעלאה, וכך גם [ה-Action ל-CI](#פרסום-אוטומטי-ל-ci-github-action). הם חייבים להיות מדויקים גם כשאינם נדרשים לטעינה מקומית במצב פיתוח.

### שדות אופציונליים

| שדה | ברירת מחדל | תיאור |
|-----|-----------|--------|
| `description` | `""` | תיאור קצר של התוסף, מוצג בכרטיס בחנות (עד 150 תווים) |
| `author` | `""` | שם המפתח |
| `homepage` | `""` | כתובת לדף הבית של התוסף, למשל עמוד GitHub, תיעוד, או אתר פרויקט |
| `icon` | `null` | נתיב לאייקון (PNG, 64×64 מומלץ) |
| `maxAppVersion` | `null` | גרסת אוצריא המקסימלית הנתמכת |
| `network.enabled` | `false` | האם להצהיר על שימוש ברשת (חובה כדי להפעיל את מנגנון הרשת בתוסף) |
| `network.allowlist` | `[]` | רשימת ה-URLs שהתוסף מצהיר שהוא צריך. ה-URL חייב להופיע כאן **וגם** להיות מאושר ע"י אוצריא בקובץ `plugin_network_allowlist.txt` שבשורש ריפו אוצריא ב-GitHub (ענף `dev`). הצהרה ב-manifest לבדה **אינה** מספיקה. |
| `contributes.toolTab.title` | שם התוסף | כותרת הטאב. אם מגדירים אותה במפורש — חייבת להיות זהה ל-`name` (עד 14 תווים), אחרת התוסף יידחה |
| `contributes.toolTab.order` | `900` | סדר הופעה בטאבים (מספר נמוך = קודם) |
| `contributes.toolTab.allowOrderBeforeBuiltIns` | `false` | חריג מפורש שמאפשר לתוסף להתחרות מול הכלים המובנים ולהופיע לפניהם במסך "כלים" |
| `contributes.toolTab.defaultPinned` | `true` | האם להצמיד אוטומטית בהתקנה |
| `contributes.toolTab.iconName` | `null` | שם אייקון FluentUI 24px שיוצג בטאב, למשל `"book_24_regular"` |
| `contributes.publishedDataTypes` | `[]` | סוגי נתונים שהתוסף מפרסם |
| `contributes.background.entrypoint` | `null` | נתיב יחסי לקובץ HTML קליל (ללא UI) שייטען ברקע במקום ה-`entrypoint` המלא. רלוונטי רק לתוסף עם `app.run_on_startup`. ראה §ריצת רקע. |
| `contributes.startup` | `null` | פקדים, פריטי תפריט ונתונים שאוצריא טוענת ישירות מהמניפסט בלי להפעיל WebView. |
| `contributes.startup.programs` | `[]` | תכניות חישוב Host מוולדות, ללא JavaScript; ראו `API_REFERENCE.md` §תכניות Host ללא WebView. |
| `contributes.startup.searchDialogItems` | `[]` | שורות checkbox סטטיות; `openPluginOnSubmit` יכול לנתב את אישור החיפוש לתוסף. |
| `contributes.startup.externalEditions` | `[]` | קונפיגורציית מהדורות מקבילות של ספק חיצוני (טבלת מיפוי במקור DB מוכרז); ראו `API_REFERENCE.md` §מהדורות מקבילות חיצוניות. |
| `contributes.startup.activationEvents` | `[]` | אירועים שמעירים את מנוע הרקע בעצלנות; כל נושא דורש גם הרשאת subscribe מתאימה. |
| `contributes.startup.keepAlive` | `false` | בקשה למנוע כיבוי אוטומטי; דורשת אישור נפרד של `app.background_keep_alive`. |

`homepage` הוא שדה אופציונלי, אבל מומלץ מאוד כשמעלים תוסף לחנות. זה המקום לשים קישור לעמוד ה־GitHub של התוסף, לתיעוד, לאתר הפרויקט, או לכל דף רשמי אחר שמסביר על התוסף ונותן למשתמש מקום לקבל מידע נוסף.

`iconName` חייב להיות שם תקני של אייקון FluentUI בגודל 24px, המסתיים ב-`_24_regular` או `_24_filled`. השם נפתר באוצריא ל-`IconData` קבוע באמצעות מפה סטטית, מה שמאפשר ל-Flutter לבצע tree-shaking של פונט האייקונים ב-Release. שמות שאינם נמצאים במפה יוצגו כאייקון פאזל ברירת מחדל.

דוגמאות תקפות: `"calendar_24_regular"`, `"calendar_24_filled"`, `"book_24_regular"`, `"settings_24_filled"`.

`allowOrderBeforeBuiltIns` אינו שדה הרשאות ואינו קשור לאבטחה. זהו דגל מיקום תצוגתי בלבד: כברירת מחדל תוספים מופיעים אחרי הכלים המובנים, גם אם ה-`order` שלהם נמוך יותר. רק אם תוסף מצהיר במפורש על `allowOrderBeforeBuiltIns: true`, המערכת תאפשר לו להופיע לפני כלים מובנים בהתאם ל-`order`.

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
| `plugin.suspended` | 🔁 חוזר | (ללא) — ראה §השהיה ברקע |
| `plugin.resumed` | 🔁 חוזר | (ללא) — ראה §השהיה ברקע |
| `theme.changed` | 🔁 חוזר | `ThemePayload` |
| `navigation.changed` | 🔁 חוזר | `{ screen: string }` |
| `reader.current_book_changed` | 🔁 חוזר | `{ bookId: string, id: number?, type: string?, source: string?, index: number }` |
| `calendar.date_changed` | 🔁 חוזר | `{ date: string }` |
| `calendar.city_changed` | 🔁 חוזר | `{ city: string }` |
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
  payload.app.runMode        // 'foreground' | 'background' — ראה §ריצת רקע
  payload.theme              // ThemePayload (ראה §ניהול ערכת נושא)
  payload.connectivity       // { isOfflineMode, hasNetwork, isOnline } — ראה app.getConnectivity
  payload.permissions        // string[] — הרשאות שאושרו
});
```

> ⚠️ **חשוב:** כל הלוגיקה הראשונית חייבת להיות בתוך callback של `plugin.boot`.  
> לא לקרוא ל-`Otzaria.call()` לפני שאירוע `plugin.boot` ירה.

### השהיה ברקע — `plugin.suspended` / `plugin.resumed`

כשהמשתמש עוזב את לשונית התוסף (מעבר לכלי אחר או למסך אחר), אוצריא **מקפיאה** את
ה-WebView של התוסף כדי לחסוך CPU/זיכרון, ומחדשת אותו בכניסה חזרה — **בלי לטעון
מחדש** (ה-state נשמר). ב-Windows/Android ההקפאה נייטיבית ועוצרת את כל ה-timers
מעצמה; בשאר הפלטפורמות התוסף **אחראי לעצור בעצמו** עבודה מתמשכת.

המודל: `plugin.boot` מתחיל את העבודה, `plugin.suspended` עוצר, `plugin.resumed`
מתחיל מחדש. שים לב — בטעינה ראשונה **לא** נורה `resumed`, ולכן את העבודה
הראשונית יש להתחיל ב-`plugin.boot`:

```javascript
let timer = null;
function start() { timer = setInterval(poll, 1000); }
function stop()  { clearInterval(timer); }

Otzaria.on('plugin.boot', start);       // התחלה ראשונית
Otzaria.on('plugin.resumed', start);    // חזרה מהשהיה
Otzaria.on('plugin.suspended', stop);   // עצירת timers / polling / WebSocket
```

> 💡 תוסף שרץ ברקע דרך הרשאת `app.run_on_startup` (`runMode: 'background'`) **אינו**
> מושהה — זו בדיוק מטרתו. ההשהיה חלה רק על ה-instance של הלשונית.

---

## Host API — סיכום

> 📘 **תיעוד מלא** של כל method — כולל כל הפרמטרים, ערכי ההחזרה ודוגמאות קוד — נמצא ב-[API_REFERENCE.md](API_REFERENCE.md). הטבלאות כאן הן סיכום מהיר בלבד.

### app.*

| Method | הרשאה | תיאור |
|--------|-------|--------|
| `app.getInfo` | `app.info.read` | גרסת האפליקציה, פלטפורמה |
| `app.getTheme` | `app.info.read` | ערכת נושא מלאה (colorScheme + typography) |
| `app.getLocale` | `app.info.read` | locale, language ו-textDirection (מ-0.9.97 — לפי שפת הממשק שנבחרה) |
| `app.openUrl` | `app.open_url` | פתיחת כתובת http/https בדפדפן המערכת |
| `app.getConnectivity` | `app.info.read` | האם יש אינטרנט — להסתרת יכולות מקוונות |

### library.*

| Method | הרשאה | פרמטרים | החזרה |
|--------|-------|----------|-------|
| `library.findBooks` | `library.books.read` | `{ query, limit? }` | `BookMeta[]` |
| `library.getBookMetadata` | `library.books.read` | `{ bookId }` | `BookMeta \| null` |
| `library.resolveBooks` | `library.books.read` | `{ items: BookIdentity[] }` (עד 100) | `(BookMeta \| null)[]` |
| `library.listRecentBooks` | `library.books.read` | — | `{ bookId, title, ref }[]` |
| `library.getBookContent` | `library.content.read` | `{ bookId, offset?, limit?, section? }` | `string` (max 5000 תווים) |
| `library.getBookToc` | `library.content.read` | `{ bookId }` | `TocEntry[]` |
| `library.listBookAltStructures` | `library.content.read` | `{ bookId }` | `AltStructure[]` |
| `library.getBookAltToc` | `library.content.read` | `{ bookId, structureKey? }` | `TocEntry[]` |
| `library.getCommentators` | `library.links.read` | `{ bookId, categoryId?, startLine?, endLine?, grouped? }` | `{ commentators }` או `{ groups }` |
| `library.getLinks` | `library.links.read` | `{ bookId, categoryId?, startLine, endLine, connectionTypes?, targetTitles?, includeAnchors? }` (חלון עד 200 שורות) | `{ links, truncated }` |
| `library.getLinkTargetsSummary` | `library.links.read` | `{ bookId, categoryId? }` | `{ targets, maxSourceLine }` |
| `library.getLinkContent` | `library.content.read` | `{ links }` (עד 25) | `{ items }` |

### network.*

| Method | הרשאה | פרמטרים | החזרה |
|--------|-------|----------|-------|
| `network.fetchStream` | `network.access` או `network.localhost` | `{ url, method?, headers?, body?, timeoutMs? }` | `AsyncIterable` של metadata ומקטעי UTF-8 |
| `network.fetch` | כנ״ל | אותם פרמטרים | תגובה מלאה; מיושן ומוסר ב-0.9.98 |
| `network.download` | כנ״ל | `{ url, filename?, destPath?, resume? }` | נתיב הקובץ שנשמר |

### search.*

| Method | הרשאה | פרמטרים | החזרה |
|--------|-------|----------|-------|
| `search.fullText` | `search.fulltext.read` | `{ query, limit? }` | `SearchResult[]` |
| `search.query` | `search.fulltext.read` | `{ query, mode?, distance?, proximityScope?, order?, grouping?, wordMatchMode?, options?, wordOptions?, alternativeWords?, customSpacing?, negativeQuery?, categories?, books?, authors?, eras?, baseBooksOnly?, limit?, offset?, includeBookCounts? }` | `AsyncIterable<{ sequence, results, total, groupCount, truncated, facets, bookCounts? }>` |
| `search.getOptions` | `search.fulltext.read` | `{}` | הערכים החוקיים לכל פרמטר של `search.query` |

ב-`search.query`, גודל עמוד מוגבל ל-500 וחלון הדפדוף (`offset + limit`
לאחר החיתוך) מוגבל ל-10,000 כדי למנוע הקצאת זיכרון לא חסומה במנוע.

### reader.*

| Method | הרשאה | פרמטרים | החזרה |
|--------|-------|----------|-------|
| `reader.openBook` | `reader.open` | `{ bookId, index?, searchQuery? }` | `boolean` |
| `reader.openBookAtRef` | `reader.open` | `{ bookId, ref, index?, highlight? }` | `boolean` |
| `reader.getCurrentState` | `reader.open` | — | `ReaderState` |

### navigation.*

| Method | הרשאה | פרמטרים | החזרה |
|--------|-------|----------|-------|
| `navigation.goTo` | `navigation.write` | `{ target: 'library'\|'reading'\|'more'\|'settings' }` | `boolean` |

> `'more'` נשמר לתאימות אחורה ופותח את פאנל הכלים. כלים ותוספים נפתחים ככרטיסיות בתוך `'reading'`, ולכן `navigation.changed` לא ישדר `'more'` יותר. כדי לדעת אם התוסף מוצג כעת השתמשו באירועי `plugin.suspended` / `plugin.resumed`.

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

### feedback.*

| Method | הרשאה | פרמטרים | החזרה |
|--------|-------|----------|-------|
| `feedback.sendEmail` | `feedback.send_email` | `{ to, subject, body, includeSystemInfo? }` | `boolean` |
| `feedback.report` | — (אישור המשתמש בדיאלוג) | `{ details, reportType?, reporterEmail? }` | `'sent' \| 'queued' \| 'cancelled'` |
| `feedback.hasReporterEmail` | — (ביט קיום בלבד) | — | `boolean` |

`feedback.report` שולח דיווח של המשתמש על התוסף לאתר אוצריא, שמעביר אותו למפתח התוסף. מוצג דיאלוג אישור חובה; `'queued'` פירושו שהדיווח נשמר בתור מקומי ויישלח אוטומטית כשיהיה חיבור. כתובת לחזרה השמורה בהגדרות גוברת על `reporterEmail`; בדקו קיומה מראש עם `feedback.hasReporterEmail` (הכתובת עצמה אינה נחשפת לתוסף).

### fs.* — המרחב הפרטי (מ-0.9.97)

תיקיית קבצים פרטית לכל תוסף, **בלי שום הרשאה**. כל הנתיבים יחסיים לשורש
הפרטי, ונתיב שיוצא ממנו (`..`, נתיב מוחלט, UNC, symlink) נדחה ב-`error.forbidden`.
מכסה 100MB לתוסף, ותקרה של 10MB לקריאה/כתיבה בודדת.

| Method | הרשאה | פרמטרים | החזרה |
|--------|-------|----------|-------|
| `fs.writeFile` | — | `{ path, content, encoding?, append? }` | `{ path, size, usedBytes, quotaBytes }` |
| `fs.readFile` | — | `{ path, encoding? }` | `{ path, encoding, size, content }` |
| `fs.listDir` | — | `{ path? }` | `{ path, entries, usedBytes, quotaBytes }` |
| `fs.makeDir` | — | `{ path }` | `boolean` |
| `fs.deleteEntry` | — | `{ path, recursive? }` | `boolean` |
| `fs.stat` | — | `{ path? }` | `{ exists, path?, name?, type?, size?, modified? }` |

> אין לבקש `fs.folder_access` בשביל קבצי עבודה — היא ההרשאה הרחבה במערכת,
> ונועדה לעבודה בתיקייה של המשתמש. הפירוט ב-[API_REFERENCE](API_REFERENCE.md).

### storage.*

| Method | הרשאה |
|--------|-------|
| `storage.get`    | `plugin.storage.read` |
| `storage.set`    | `plugin.storage.write` |
| `storage.remove` | `plugin.storage.write` |
| `storage.list`   | `plugin.storage.read` |

> ⚠️ **שם המסלול שונה משם ההרשאה.** קריאה ל-`plugin.storage.get` אינה קיימת
> ותיכשל בשקט אם התוסף אינו בודק את `success`. `storage.set` דורש `value`
> שאינו `null` — למחיקה יש `storage.remove`.

### settings.*

| Method | הרשאה | פרמטרים |
|--------|-------|----------|
| `settings.get`     | `settings.read` | `{ key }` |
| `settings.getMany` | `settings.read` | `{ keys: string[] }` |

**מ-0.9.97 כל הגדרה קריאה, למעט רשימת חסומים** (עד אז הייתה רשימת היתר סגורה).
חסומים: כל מפתח שבשמו `password` / `secret` / `credential` / `token` /
`api-key` / `client-id`, כל מפתח שבשמו `path` / `folder` / `root` (נתיבים,
כולל `key-hebrew-books-path` שהיה מותר עד 0.9.96), כל מפתח שבשמו `email`,
וכן `key-google-calendar-*`, `key-calendar-event*`, `key-protected-mode-*`,
`sz:*` ותוכן אישי (`key-bookmarks`, `key-tabs`, `key-workspaces` ודומיהם).
הפירוט המלא ב-[API_REFERENCE](API_REFERENCE.md#settings---הגדרות-אפליקציה).

> ⚠️ `settings.get` על מפתח חסום מחזיר `error.forbidden` (מ-0.9.97; קודם החזיר
> `null` בשקט). `settings.getMany` מדלג עליו — הוא חסר מהמפה המוחזרת.

### calendar.*

| Method | הרשאה | החזרה |
|--------|-------|-------|
| `calendar.getSelectedDate` | `calendar.read` | `string` (ISO 8601) |
| `calendar.getDailyTimes`   | `calendar.read` | `Record<string, string>` — מ-0.9.97 מקבל `{ date?, city?, lat?, lng?, elevation?, timezone?, inIsrael? }` |
| `calendar.getHalachicTimes`| `calendar.read` | `Record<string, string>` — אותם פרמטרים כמו `calendar.getDailyTimes` (מ-0.9.97) |
| `calendar.getCities`       | `calendar.read` | `CityInfo[]` (מ-0.9.97) |
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

> **גופנים — אין צורך לארוז:** השמות שמגיעים ב-`theme.typography.fontFamily` ו-`theme.typography.commentatorsFontFamily` (כגון `FrankRuhlCLM`, `Shofar`) נטענים אוטומטית כ-`@font-face` ב-WebView של התוסף לפני ה-`plugin.boot`. ניתן להפנות אליהם ישירות מ-CSS. כשהמשתמש בחר גופן מערכת מותאם, ההזרקה מדלגת עליו ויש להסתמך על fallback של מערכת ההפעלה — לכן השאירו תמיד `serif` (ועדיף גם `'David'`) בסוף שרשרת ה-`font-family`.

> **כותרת התוסף — בפס עליון, לא בגוף התוכן:** התוסף נפתח כטאב קריאה ואוצריא אינה מציירת כותרת מעל ה-WebView. שם התוסף חייב להופיע בפס עליון קבוע ברקע `colorScheme.surfaceContainerHigh` — אותו צבע וגובה כמו הסרגל העליון של מסכי הספרים. ראה [DESIGN\_GUIDE.md § סרגל כותרת התוסף](DESIGN_GUIDE.md#סרגל-כותרת-התוסף-top-bar) ומתכון מלא ב-[COOKBOOK.md § 4](COOKBOOK.md#4-סרגל-כותרת-התוסף-top-bar).

> מדריך עיצוב מלא — Color Roles, צורות, טיפוגרפיה, כפתורים, כרטיסים ואנימציות — ב-[DESIGN_GUIDE.md](DESIGN_GUIDE.md).

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

### הרשאות בסיס (מ-0.9.97 — אין צורך להצהיר)

ההרשאות הבאות ניתנות **אוטומטית לכל תוסף**, אינן מוצגות למשתמש, והצהרה עליהן
במניפסט מיותרת (נסבלת לתאימות לאחור, עם אזהרת ולידטור):

`plugin.storage.read` · `plugin.storage.write` · `app.info.read` ·
`ui.feedback` · `notifications.send` · `events.subscribe:theme.changed`

### רשימת ההרשאות המלאה

שש ההרשאות שברשימה למעלה נכללות גם כאן לשם השלמות — אין צורך להצהיר עליהן.

| הרשאה | מה מאפשרת |
|-------|-----------|
| `app.info.read` | קריאת מידע על האפליקציה |
| `app.open_url` | פתיחת קישור http/https בדפדפן ברירת המחדל של מערכת ההפעלה |
| `library.books.read` | חיפוש וקריאת metadata של ספרים |
| `library.content.read` | קריאת תוכן ספרים (TOC + טקסט) |
| `library.links.read` | קריאת מפרשים וקישורים של ספר (מבנה בלבד, ללא תוכן) |
| `search.fulltext.read` | חיפוש טקסט מלא |
| `reader.open` | פתיחת ספרים + קריאת מצב הקורא |
| `navigation.write` | ניווט בין מסכים |
| `plugin.open_other` | פתיחת דף של תוסף אחר המותקן אצל המשתמש (`plugin.openOther`), כולל הפעלת הקוד שלו |
| `notes.read` | קריאת הערות אישיות |
| `notes.write` | הוספה/עדכון/מחיקה של הערות |
| `calendar.read` | גישה לנתוני לוח שנה |
| `settings.read` | קריאת הגדרות התוכנה (הכל למעט רשימת החסומים — סודות, נתיבים, מייל ותוכן אישי) |
| `plugin.storage.read` | קריאת storage פרטי — ⚠️ המסלולים הם `storage.get`/`storage.list`, **לא** `plugin.storage.*` |
| `plugin.storage.write` | כתיבה ל-storage פרטי — ⚠️ המסלולים הם `storage.set`/`storage.remove` |
| `published_data.write` | פרסום נתונים לאפליקציה |
| `ui.feedback` | הצגת הודעות ודיאלוגים |
| `ui.create_shortcut` | יצירת קיצור דרך (deep-link) בשולחן העבודה / תפריט ההתחל — דורש אישור משתמש |
| `network.access` | גישה לאינטרנט (דורש `network.enabled: true` במניפסט + שה-URL מופיע ב-allowlist הרשמי של אוצריא ב-GitHub) |
| `network.localhost` | גישה לשירות מקומי על המחשב (`localhost` / `127.0.0.1`), כמו Ollama / LM Studio. נפרדת מ-`network.access` — אינה מתירה אינטרנט, ואינה דורשת allowlist גלובלי |
| `fs.user_files.read` | בחירה וקריאה של קובץ אישי (PDF/טקסט) שהמשתמש בוחר בדיאלוג — מוגבל לקובץ שנבחר בלבד |
| `fs.user_files.write` | שמירה לקובץ שהמשתמש בחר, או יצירת קובץ חדש דרך „שמור בשם”. אין דרך להזין נתיב מה-JS |
| `fs.folder_access` | בחירת תיקייה בדיאלוג מערכת (`ui.pickFolder`) ועבודה על קבצים בתוכה. מ-0.9.97 — פוצלה מ-`ui.feedback`; הצהרה ותיקה על `ui.feedback` עדיין מכסה אותה. **לקבצי עבודה השתמשו במרחב הפרטי (`fs.writeFile` וחבריו) — הוא אינו דורש הרשאה** |
| `bookmarks.read` | קריאת רשימת הסימניות של המשתמש |
| `bookmarks.write` | הוספה ומחיקה של סימניות |
| `tools.read` | כלי העזר המובנים — גימטריה ומילוני ראשי תיבות/ארמית (`tools.*`) |
| `notifications.send` | הצגת הודעות בתוך האפליקציה (UiSnack) |
| `notifications.system` | התראות מערכת הפעלה (Native notifications) |
| `app.run_on_startup` | **הרשאה רגישה** — הפעלת WebView ברקע לפי אירוע שהוצהר ב-`contributes.startup`. ברירת מחדל: **כבויה**. בתוסף ישן ללא `contributes.startup`, מפעילה זמנית בעליית אוצריא עד 0.9.97. |
| `app.background_keep_alive` | **הרשאה רגישה מאוד** — מניעת כיבוי אוטומטי של WebView רקע עצל. דורשת `startup.keepAlive: true`; כבויה כברירת מחדל ומוצגת באדום. |
| `app.startup_contributions` | הזרקת פקדים ונתונים סטטיים מהמניפסט בלי להפעיל את התוסף. ברירת מחדל: **מופעלת**. |

> **עיקרון מינימום הרשאות:** בקש רק את מה שאתה צריך בפועל.

---

## ריצת רקע (app.run\_on\_startup)

הדרך המומלצת היא להצהיר על `contributes.startup`. אוצריא קוראת את הפקדים,
פריטי התפריט והנתונים הסטטיים ב-Dart, ולכן WebView כלל לא נוצר בעלייה. אם נדרש
קוד JavaScript, `app.run_on_startup` מתירה להפעיל WebView רק כשמתרחש אירוע
שהוצהר: לחיצה על תרומה, `app.startup`, או נושא מתוך `activationEvents`.

מנוע כזה נסגר אחרי כשלוש דקות ללא פעילות, והאירוע הבא יפעיל אותו מחדש. אפשר
לסיים מוקדם באמצעות `plugin.backgroundDone`. רק צורך אמיתי במנוע רציף מצדיק
`startup.keepAlive: true` ואת ההרשאה הנפרדת `app.background_keep_alive`.

### הצהרה במניפסט

```json
{
  "permissions": [
    "app.startup_contributions",
    "app.run_on_startup",
    "notifications.send"
  ],
  "contributes": {
    "startup": { "activationEvents": ["app.startup"] }
  }
}
```

### התנהגות ברירת מחדל

`app.startup_contributions` מתחילה מופעלת; היא אינה מריצה JavaScript.
`app.run_on_startup` ו-`app.background_keep_alive` מתחילות כבויות ודורשות אישור מכוון.

מסך ההתקנה מציג למשתמש אילו אירועים עשויים להפעיל את התוסף. בקשת keep-alive
מוצגת בנפרד באדום ומבהירה שהמנוע עשוי להישאר פעיל ללא הגבלת זמן.

### זיהוי מצב רקע ב-JavaScript

כשהתוסף רץ ברקע, `payload.app.runMode === 'background'`.  
כשהתוסף רץ בלשונית הנראית, `payload.app.runMode === 'foreground'`.

השתמש בזה כדי **לשלוח הודעה פעם אחת בלבד** — מה-instance הרקע בלבד:

```javascript
Otzaria.on('plugin.boot', async (payload) => {
  const isBackground = payload.app.runMode === 'background';
  const hasStartupPerm = payload.permissions.includes('app.run_on_startup');

  if (isBackground && hasStartupPerm) {
    // רץ כשהאירוע המוצהר מעיר את מופע הרקע
    await Otzaria.call('notifications.showInApp', {
      message: 'שלום! התוסף נטען בהצלחה עם עליית אוצריא',
      type: 'success'
    });
  }
});
```

> ⚠️ **חשוב:** אם לא תבדוק את `runMode`, ההודעה תישלח **פעמיים** — פעם מה-instance הרקע ופעם נוספת כשהמשתמש נכנס ללשונית.

### מה מותר לתוסף רקע לעשות

תוסף שרץ ברקע יכול לקרוא לכל ה-APIs הרגילים — `notifications.showInApp`, `storage.set/get`, `calendar.getJewishDate`, וכו'. דיאלוגים (`ui.showConfirm` וכו') יופיעו מעל המסך הראשי.

**מה שלא מומלץ ברקע:**
- `navigation.goTo` — יגרום לניווט בלתי צפוי ברגע שהאפליקציה נפתחת
- קריאות כבדות שיאטו את עליית האפליקציה

### קובץ כניסה ייעודי לרקע (`contributes.background.entrypoint`)

כברירת מחדל, ה-instance הרקע טוען את אותו `entrypoint` של הלשונית הנראית — דף ה-UI המלא, על כל ה-DOM, ה-CSS, הגופנים וה-bundle של ה-framework. ברקע אף אחד לא רואה את הדף הזה, ולכן זה בזבוז: אתה משלם את עלות טעינת ה-UI בכל עליית אוצריא רק כדי לרשום תפריט הקשר או להאזין לאירועים.

כדי לייעל, הצהר על קובץ כניסה **קליל ונפרד** לרקע:

```json
{
  "entrypoint": "dist/index.html",
  "permissions": ["app.run_on_startup", "reader.context_menu"],
  "contributes": {
    "background": { "entrypoint": "dist/background.html" }
  }
}
```

- `background.html` צריך להכיל **רק** את לוגיקת ה-headless — רישומים (`reader.addContextMenuItem`), מאזיני אירועים (`Otzaria.on(...)`), תזמון התראות — בלי framework ובלי UI.
- אם השדה לא מוצהר, הרקע נופל ל-`entrypoint` הרגיל (התנהגות קיימת, ללא שינוי).
- הקובץ חייב להיכלל באריזה (אל תחריג אותו ב-`.otzignore`) — האריזה תיכשל עם שגיאה ברורה אם הוא חסר או מוחרג.
- במצב פיתוח מ-localhost, אוצריא ממשיכה לטעון את שורש שרת הפיתוח (האופטימיזציה חלה על תוסף ארוז).

> 💡 זהו אותו רעיון של "service worker" בתוספי דפדפן: דף קליל לרקע, נפרד מדף ה-UI.

### מחזור החיים של מופע רקע עצל

| מצב | מה קורה |
|-----|---------|
| אוצריא נפתחת | תרומות סטטיות נטענות ללא WebView |
| אירוע מוצהר + הרשאת רקע מאושרת | WebView נסתר נוצר, `plugin.boot` נורה עם `runMode: 'background'`, ואז האירוע נמסר |
| המשתמש נכנס ללשונית התוסף | **instance נוסף** נוצר (foreground), ה-background נמשך במקביל |
| ההרשאה מבוטלת בהגדרות | ה-instance הרקע נסגר מיידית |
| אין פעילות במשך כ-3 דקות | המופע נסגר, אלא אם אושרה הרשאת keep-alive |
| התוסף מוסר | שני ה-instances נסגרים |

### תאימות זמנית לתוספים ישנים

בגרסאות 0.9.96–0.9.97, תוסף שמבקש `app.run_on_startup` אך אינו מצהיר על
`contributes.startup` עדיין נטען בעליית אוצריא ונשאר פעיל לאורך הסשן. המסלול
הישן יוסר ב-0.9.98; תוסף שלא יעבור להצהרות דקלרטיביות לא יופעל עוד ברקע.

---

## אבטחה ומגבלות

### Rate limiting

המגביל הוא **דלי אסימונים**, לא מכסה לשנייה:

- **קיבולת הדלי: 50 אסימונים.** כל קריאה צורכת אחד.
- **קצב המילוי: אסימון כל 10ms** — כלומר 100 קריאות לשנייה בקצב מתמשך.
- חריגה מחזירה `{ success: false, error: { code: "error.rate_limited" } }`.

שני המספרים חיים יחד, וזו ההשלכה המעשית: פרץ של 60 קריאות בבת אחת ייכשל
בקריאה ה-51 — **גם אם חלפה שנייה שלמה מאז הקריאה הקודמת**, כי הדלי אינו
מתמלא מעבר ל-50. תוסף שמנפיק פרצים גדולים חייב לפזר אותם בזמן.

**שתי החרגות מהמגביל:**

1. `library.getBookContent` — היא מחולקת ל-chunks של 5000 תווים, כך שספר
   שלם מחייב עשרות קריאות רצופות. **המלכוד:** ההחרגה חלה רק כאשר ההרשאה
   `library.content.read` **הוענקה בפועל**, לא כשהוצהרה במניפסט. תוסף
   שההרשאה שלו כבויה יעבור דרך המגביל ועלול לקבל `error.rate_limited`
   במקום `permission_denied` המצופה — אל תסיקו מהקוד הזה שהקריאה תקינה.
2. **ביטול stream** — קריאת ביטול של `search.query` או של
   `network.fetchStream` אינה נספרת, כדי שתמיד ניתן יהיה לעצור.

### Timeout
- כברירת מחדל, קריאת `Otzaria.call()` נחתכת אחרי **30 שניות** ומחזירה
  `error.timeout`.
- **שישה מסלולים מוחרגים** ומנהלים חסם זמן משלהם — הם עשויים להמתין ללא
  הגבלה מצד ה-RPC: `search.query`,‏ `network.fetch`,‏ `network.fetchStream`,‏
  `network.download`,‏ `fs.extractZip` ו-`feedback.report`.
- **אל תעטפו אותם ב-timeout עצמי של 30 שניות.** `feedback.report` וכל פעולה
  שממתינה לדיאלוג ממתינות למשתמש; ביטול מצד התוסף יקטע פעולה שהמשתמש
  באמצע אישורה, ובמקרה של דיווח — אחרי שכבר נשלח.
- שאילתות `database.*` הן מקרה נפרד: להן חסם משלהן של 3 שניות שמחזיר
  `database.query_timeout` (ראו API_REFERENCE).

### מפתחות ושמות שמורים

ה-SDK משתמש בכמה שמות בתוך ה-payload ובמרחב האירועים של הדף. שימוש חוזר
בהם **אינו מחזיר שגיאה** — הוא פשוט משבש את הזרימה בשקט:

- **`__streamId`** ו-**`__cancelStreamId`** — ה-SDK מזריק אותם ל-payload של
  `search.query` ושל `network.fetchStream` כדי לשייך chunks לזרם ולבטל אותו.
  שדה משלכם באותו שם ידרוס אותם.
- **`__otzaria.*`** — נושאי ה-`CustomEvent` שבהם ה-chunks מגיעים ל-דף
  (`__otzaria.search.query.chunk`,‏ `__otzaria.network.fetchStream.chunk`).
  אל תשלחו ואל תיירטו אירועים בקידומת הזאת.

### `window.open` מנוטרל

מטעמי אבטחה `window.open` מוחלף בפונקציה שמדפיסה לקונסולה ומחזירה `null`.
היא **אינה זורקת**, ולכן ספריית צד-שלישי שנשענת עליה (פתיחת חלון תצוגה,
הדפסה, OAuth popup) תיכשל בלי חריגה ובלי סימן. לפתיחת קישור חיצוני יש
`app.openUrl` (הרשאה `app.open_url`).

### גישת קבצים
התוסף יכול לטעון רק קבצים מ:
- ✅ תיקיית ההתקנה שלו
- ✅ `data:` URLs
- ✅ `blob:` URLs
- ❌ `file:///` לנתיבים חיצוניים
- ❌ קבצי ספרים/נתונים של אוצריא

### רשת
- חסומה כברירת מחדל
- כדי שתוסף יוכל לגשת ל**אינטרנט** (לשירות מקומי יש מסלול נפרד — ראו בהמשך) חייבות להתקיים **שלוש שכבות** במצטבר:
  1. **הצהרה במניפסט** — `network.enabled: true`, ההרשאה `network.access`, וגם שה-URL המבוקש יופיע ב-`network.allowlist` של התוסף.
  2. **אישור המשתמש** — המשתמש אישר את הרשאת `network.access` בעת ההתקנה.
  3. **מקור אמון רשמי של אוצריא** — ה-URL חייב להיות תואם קידומת לערך שמופיע בקובץ [`plugin_network_allowlist.txt`](https://github.com/Otzaria/otzaria/blob/dev/plugin_network_allowlist.txt) שבשורש ריפו אוצריא ב-GitHub, כפי שהוא בענף `dev`. מיזוג עריכה ל-`dev` נכנס לתוקף מיד, בלי release. האישור נטען לזיכרון בלבד עד סגירת האפליקציה.
- ההתאמה היא **התאמת קידומת מלאה** — אם ברשימה רשום `https://github.com/Otzaria/otzaria-library`, יותרו רק URLs שמתחילים במחרוזת זו (ואחריה `/`, `?`, `#` או סוף המחרוזת). `https://github.com/` או `https://github.com/Otzaria/another-repo` ייחסמו.
- ה-`network.allowlist` במניפסט הוא **תנאי חובה אך לא תנאי מספיק** — בלי הצהרה במניפסט ה-URL ייחסם, וגם עם הצהרה הוא ייחסם אם אינו מופיע במקור אמון רשמי של אוצריא.
- אם תוסף מבקש גישה ל-URL שאינו ב-allowlist הגלובלי, יש לפנות למתחזקי אוצריא בבקשה להוסיף אותו.

**שירותים מקומיים (localhost):** גישה ל-`localhost` / `127.0.0.1` / `::1` (למשל מודל שפה מקומי כמו Ollama / LM Studio) משתמשת בהרשאה הנפרדת **`network.localhost`** — לא `network.access`. מסלול זה **אינו** דורש את שכבה 3 (allowlist גלובלי / PR לאוצריא); די בשלושה: `network.enabled: true`, הצהרת היעד ב-`network.allowlist` של התוסף (מותר host חשוף כמו `"127.0.0.1"` שמתיר כל פורט, או URL מלא שנועל לפורט מסוים), ואישור המשתמש להרשאת `network.localhost`. הקריאות חייבות לעבור דרך `network.fetchStream` (לא `fetch()` ישיר מה-WebView — הוא נחסם ב-CORS מול שרת מקומי שדוחה `Origin: null`).

### window.open
חסום לחלוטין מטעמי אבטחה.

### זום דפדפן
זום ברמת הדפדפן **מבוטל** בטאב של תוסף — גם צביטת מגע (Page Scale) וגם Ctrl+גלגלת / Ctrl+מינוס-פלוס. הסיבה: מחוות זום של הדפדפן משנות את הסקאלה של כל התוסף בלי דרך גלויה למשתמש לאפס אותה.

זה **לא** מגביל זום שהתוסף מממש בעצמו: אירועי המגע והגלגלת ממשיכים להגיע לדף כרגיל, כך שקנבס או תצוגה עם pinch-zoom משלכם (האזנה ל-pointer/touch events, בדרך כלל עם `touch-action: none` על האלמנט) עובדים ללא הפרעה — ואף בלי תחרות מצד זום הדפדפן על אותה מחווה.

---

## מסך "אודות" וקיצור דרך לתוסף

מומלץ לכלול בתוסף **מסך/כפתור "אודות"** שמרכז מידע למשתמש: שם התוסף, המפתח, הגרסה, תיאור קצר וקישור לדף הבית. זהו גם המקום הטבעי להציע למשתמש **ליצור קיצור דרך** לתוסף — בשולחן העבודה (וב-Windows גם בתפריט ההתחל) — כדי שיוכל לפתוח את התוסף בלחיצה אחת.

### מאיפה מגיע המידע ל"אודות"

הפרטים שהצהרת ב-`manifest.json` (`name`, `author`, `version`, `description`, `homepage`) ידועים לך ממילא. בנוסף, אירוע `plugin.boot` מספק את מזהה התוסף, הגרסה והפלטפורמה הנוכחית:

```javascript
let pluginId, platform;

Otzaria.on('plugin.boot', (payload) => {
  pluginId = payload.plugin.id;      // 'com.example.myplugin'
  platform = payload.app.platform;   // 'windows' | 'macos' | 'linux' | 'android' | 'ios'
  renderAbout();
});

const isDesktop = () => ['windows', 'macos', 'linux'].includes(platform);
```

### יצירת קיצור דרך — `shortcut.create`

קיצור הדרך הוא בעצם **deep-link**: קובץ תלוי-פלטפורמה שאוצריא יוצרת עבורך (`.url` ב-Windows, `.webloc` ב-macOS, `.desktop` ב-Linux). אינך צריך להתעסק בפורמטים — רק לקרוא ל-API אחד. הקיצור פותח תמיד את **התוסף הקורא**, ואוצריא בונה את הקישור (`otzaria://open/plugin/<id>`) בעצמה — אינך מעביר אותו, ולכן אי אפשר ליצור קיצור ל-route אחר.

הוסף את ההרשאה ל-`manifest.json`:

```json
{ "permissions": ["ui.create_shortcut"] }
```

הפונקציה שיוצרת את הקיצור:

```javascript
async function createDesktopShortcut(location = 'desktop') {
  const res = await Otzaria.call('shortcut.create', {
    label: 'לוח שנה הלכתי',   // שם התוסף — ישמש כשם הקיצור
    location,                  // 'desktop' (ברירת מחדל) או 'startMenu' (Windows בלבד)
  });

  if (!res.success) {
    await Otzaria.call('ui.showError', { message: 'לא ניתן ליצור קיצור דרך' });
    return;
  }
  if (res.data.created) {
    await Otzaria.call('ui.showSuccess', { message: 'קיצור הדרך נוצר בהצלחה!' });
  }
  // res.data.created === false → המשתמש ביטל את דיאלוג האישור
}
```

במסך ה"אודות", הצג את כפתור הקיצור **רק בדסקטופ**, וב-Windows הוסף כפתור נפרד לתפריט ההתחל:

```javascript
function renderAbout() {
  // ... הצגת שם התוסף, המפתח, הגרסה, התיאור וקישור לדף הבית ...

  if (!isDesktop()) return;   // אין קיצורי דרך במובייל

  showButton('צור קיצור דרך בשולחן העבודה', () => createDesktopShortcut('desktop'));

  if (platform === 'windows') {
    showButton('הוסף לתפריט ההתחל', () => createDesktopShortcut('startMenu'));
  }
}
```

> **אישור משתמש אוטומטי:** לפני יצירת הקיצור, אוצריא מציגה למשתמש דיאלוג אישור. אם אישר — הקובץ נוצר ו-`created` יהיה `true`; אם ביטל — `created` יהיה `false` ולא נוצר דבר. אין צורך להוסיף אישור משלך.

> **מגבלות:** `shortcut.create` זמין בדסקטופ בלבד. `location: 'startMenu'` נתמך ב-Windows בלבד (אחרת מוחזר `error.unsupported`). הקישור נבנה בצד אוצריא ופותח תמיד את התוסף הקורא — אינך מעביר אותו.

---

## מצב פיתוח (Hot Reload)

לצורך פיתוח מהיר ונוח של תוספים חדשים, אוצריא מספקת שתי שיטות פיתוח "חי":

| שיטה | מתי להשתמש |
|------|------------|
| **טעינה מתיקייה** | תוספים פשוטים — HTML/CSS/JS ישיר ללא bundler |
| **טעינה משרת localhost** | תוספים עם Vite / webpack — מקבלים HMR (החלפת מודול בזמן אמת) |

### הפעלת כלי הפיתוח

כפתורי הפיתוח (טעינת תיקייה, localhost, רענון) מופיעים בפאנל "תוספים" ובפאנל "כלים ותוספים" באחד משני מצבים:

- **הרצת אוצריא במצב debug** (דרך IDE או `flutter run`) — הכפתורים מופיעים תמיד.
- **גרסה רגילה (מותקנת) עם דגל ההפעלה `--dev-plugins`**:

  ```
  otzaria.exe --dev-plugins
  ```

  טיפ: צרו קיצור דרך ייעודי עם הדגל בשדה Target — "אוצריא למפתחים" בלחיצה אחת.

> **שימו לב:** אוצריא היא single-instance. אם אוצריא כבר רצה בלי הדגל, הפעלה נוספת עם הדגל רק תמקד את החלון הקיים — סגרו את אוצריא והפעילו מחדש דרך הקיצור.

---

### שיטה א: טעינה מתיקייה מקומית

1. **סביבת הרצה**: הפעילו את כלי הפיתוח (מצב debug או דגל `--dev-plugins`, ראו למעלה).
2. **טעינת התיקייה**:
   - פתחו את פאנל "תוספים" באוצריא.
   - לחצו על אייקון התיקייה בסרגל העליון.
   - בחרו את התיקייה שבה ממוקם `manifest.json`.
3. **סמל DEV**: התוסף יופיע עם תג `DEV`.

**Hot Reload:** כל שמירה של קובץ בתיקיית התוסף תזוהה אוטומטית — אוצריא מרעננת את ה-WebView מיד. מטמון מכובה כברירת מחדל.

**מסך שגיאות:** שבירת `manifest.json` (JSON פגום, הסרת entrypoint, הרשאה חסרה) מציגה מסך שגיאה ייעודי עם אפשרות לרענן לאחר תיקון.

**הגדרות מתקדמות:** לחיצה על גלגל השיניים של התוסף חושפת ריענון יזום, הצגת נתיב המקור, וניתוק בטוח (ללא מחיקת קבצים).

---

### שיטה ב: טעינה משרת פיתוח (localhost / HMR)

כאשר התוסף בנוי עם Vite, webpack, או כל bundler אחר שתומך ב-HMR (Hot Module Replacement) — הפעל את שרת הפיתוח המקומי וחבר אותו לאוצריא.

#### הפעלה

1. **הפעל את שרת הפיתוח** (דוגמה עם Vite):
   ```bash
   cd my-plugin
   npx vite dev  # → http://localhost:3000
   ```

2. **טען משרת localhost**:
   - פתחו את פאנל "תוספים" באוצריא (עם כלי הפיתוח פעילים — ראו למעלה).
   - לחצו על אייקון הגלובוס בסרגל העליון.
   - הכניסו את כתובת השרת (ברירת מחדל: `http://localhost:3000`).

3. **דיאלוג הרשאות**: בטעינה ראשונה יוצג דיאלוג הרשאות זהה לזה של התקנת תוסף רגיל. אשרו את ההרשאות הנדרשות. טעינה חוזרת (לאחר כיבוי והדלקת אוצריא) שקטה — ללא דיאלוג.

4. **HMR אוטומטי**: ה-WebSocket של ה-HMR מחובר לשרת הפיתוח — כל שמירה מרעננת את התוסף מיידית בתוך אוצריא, בדיוק כמו בדפדפן.

#### כיבוי ואתחול מחדש

אם עצרת את שרת הפיתוח ורוצה לחדש:
1. הפעל שוב את השרת המקומי.
2. בפאנל "תוספים" לחץ על גלגל השיניים של התוסף → "טען מחדש" — או פשוט הפעל מחדש את אוצריא.

#### הגבלת אבטחה חשובה — port ספציפי בלבד

אוצריא מאפשרת גישה **רק ל-origin המדויק** שהוגדר בטעינה (host + port). אם הגדרת `http://localhost:3000`, רק פורט 3000 יותר — שירותים אחרים על localhost בפורטים אחרים ייחסמו. אין צורך בהגדרה נוספת; זו ברירת המחדל.

#### דרישות Vite — manifest.json

שרת הפיתוח של Vite מחזיר `index.html` (SPA fallback) לכל נתיב לא מוכר — כולל `/manifest.json`. אוצריא מזהה זאת ומציגה שגיאה ברורה. הפתרון: הוסף `manifest.json` לתיקיית `public/` של Vite, שמשמשת כנכסים סטטיים:

```
my-plugin/
├── public/
│   └── manifest.json   ← ישמש גם ב-dev וגם ב-build
├── src/
│   └── main.ts
└── vite.config.ts
```

> ה-`entrypoint` ב-`manifest.json` צריך להצביע על נתיב קובץ ה-build (למשל `dist/index.html`) — אוצריא מתעלמת ממנו בעת טעינה מ-localhost ומנווטת לשורש השרת.

#### תאימות WebView2 (Windows) — `type="module"`

WebView2 אינו תומך ב-`<script type="module">` מתוך `file://` URLs. בשרת localhost זה בדרך כלל עובד, אבל אם אתם משתמשים ב-plugin Vite שמסיר `type="module"` (למשל `vite-plugin-legacy`), ודאו שהוא פועל **רק במצב build** (`apply: 'build'`) — לא במצב dev — כדי שה-HMR לא יישבר.

---

### טיפ: פיתוח ב-browser רגיל

אפשר גם לפתח ולבדוק ישירות ב-browser רגיל (Chrome/Firefox) — הוסף stub שמדמה את ה-host:

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
        app: { version: '0.9.96', platform: 'dev', locale: 'he-IL', textDirection: 'rtl' },
        theme: {
          mode: 'light',
          colorScheme: {
            primary: '#1565C0', onPrimary: '#fff',
            secondary: '#6750A4', onSecondary: '#fff',
            secondaryContainer: '#E8DEF8', onSecondaryContainer: '#1D192B',
            surface: '#f8f9fa', onSurface: '#1a1a2e',
            surfaceContainerHigh: '#ece6f0', surfaceContainerHighest: '#e0e0e0',
            error: '#b00020', onError: '#fff', outline: '#cbd5e1',
          },
          typography: { fontFamily: 'Frank Ruhl Libre', fontSize: 18, lineHeight: 1.5,
            commentatorsFontFamily: 'Shofar', commentatorsFontSize: 14 },
        },
        connectivity: { isOfflineMode: false, hasNetwork: true, isOnline: true },
        permissions: ['app.info.read', 'library.books.read', 'calendar.read',
          'plugin.storage.read', 'plugin.storage.write', 'ui.feedback'],
      },
    }));
  }, 100);
}
```

---

## אריזה והפצה — יצירת קובץ `.otzplugin`

קובץ `.otzplugin` הוא **ארכיון ZIP** עם סיומת שונה, המכיל את כל קבצי תיקיית התוסף כאשר `manifest.json` יושב בשורש הארכיון.

לפני אריזה והפצה, ודאו שה-`manifest.json` עומד בכל הדרישות, כולל שדות החובה לצורך העלאה לחנות (ראו §[קובץ ה-manifest](#קובץ-ה-manifest)).

יש שתי דרכים שקולות לאריזה עם **ולידציה אוטומטית** — בחרו את הנוחה לכם.

### א. דרך התוכנה הארוזה — `otzaria pack-plugin`

מומלץ למשתמשי קצה: אין צורך ב־Dart SDK או בקוד המקור, רק את אוצריא המותקנת.

**דרישה מקדימה ל־Windows:** כדי להריץ את הפקודה בקיצור `otzaria pack-plugin` (בלי לציין נתיב מלא ל־exe), אוצריא צריכה להיות ב־PATH. המתקין מוסיף את אוצריא ל־PATH אוטומטית: בהתקנת מנהל ל־PATH המערכתי, אחרת ל־PATH של המשתמש (`HKCU\Environment`). ההסרה מה־PATH מתבצעת אוטומטית בהסרת ההתקנה.

בהתקנות ישנות (עד 0.9.95, שבהן זו הייתה משימה אופציונלית באשף שלא סומנה) אפשר להריץ עם הנתיב המלא:

```bash
"C:\Program Files\otzaria\otzaria.exe" pack-plugin <path>
```

או להתקין גרסה עדכנית. ב־Linux/macOS אין צורך — ה־launcher של אוצריא נמצא ב־PATH ממילא.

```bash
# מתוך תיקיית התוסף עצמה:
otzaria pack-plugin

# או עם נתיב מפורש:
otzaria pack-plugin C:\path\to\my-plugin
```

**אופציות נתמכות:**

| דגל | תיאור |
|-----|--------|
| `--force` | דריסת `.otzplugin` קיים בנתיב הפלט |
| `--output <file>` (קיצור: `-o`) | נתיב פלט מפורש. ברירת מחדל: `{id}-{version}.otzplugin` בתיקיית האב |
| `--help` / `-h` | הצגת מסך עזרה |

הפקודה מקבלת גם `--pack-plugin` (עם מקפים כפולים) ו־`pack_plugin` (קווים תחתונים) כשמות מקבילים.

**דוגמאות:**

```bash
# אריזה לתיקייה הנוכחית, פלט בתיקיית האב:
otzaria pack-plugin

# פלט במיקום מותאם אישית עם דריסה:
otzaria pack-plugin C:\my-plugin --output C:\releases\my-plugin.otzplugin --force

# Linux/macOS:
otzaria pack-plugin ~/projects/my-plugin -o ~/Desktop/my.otzplugin
```

> **טיפ ל־Windows:** אם מריצים מ־PowerShell ורוצים לראות את הפלט בטרמינל, השתמשו ב־`Start-Process -Wait -NoNewWindow otzaria pack-plugin ...` או הפנו את הפלט: `otzaria pack-plugin ... | Out-Default`.

הפקודה מדלגת על מנגנון הריצה היחידה (single-instance) — אפשר להריץ אותה גם כשאוצריא פתוחה ב־GUI.

### ב. דרך סקריפט ה־`tool/` (זהה לוגית, דורש קוד מקור)

```bash
dart tool/plugins/package_plugin.dart <path/to/your/plugin/folder> [--force]
```

### מה הפקודה עושה

שתי הדרכים משתמשות באותה לוגיקה (`PluginPackager` ב־[lib/plugins/services/plugin_packager.dart](../../lib/plugins/services/plugin_packager.dart)):

1. **ולידציית מבנה (חוסמת)** — בודקת ש־`manifest.json` קיים, JSON תקין, גרסת סכמה, פורמט `id` ו־SemVer, קיום קובץ ה־entrypoint, ושכל ההרשאות המבוקשות נמצאות ברשימת ההרשאות הרשמית. בתוך `contributes.toolTab`, השדה `allowOrderBeforeBuiltIns` הוא דגל בוליאני אופציונלי שמגדיר חריג תצוגתי בלבד: הוא לא מעניק הרשאה, אלא רק מאפשר לתוסף להתחרות מול הכלים המובנים על מיקום במסך "כלים".

2. **ולידציה מורחבת** — מפיקה דו"ח עם שלושה חלקים:
   - **`errors`** — חוסמות אריזה (כיום: רק חריגות מ־ולידציית המבנה).
   - **`warnings`** — לא חוסמות. כוללות:
     - שימוש ב־API לא מוכר (`Otzaria.call('...')` או shorthand כמו `Otzaria.app.getInfo()`).
     - הרשמה לאירוע לא מוכר (`Otzaria.on('...')` / `.off(...)`).
     - שימוש ב־method שדורש הרשאה שלא הוכרזה ב־`manifest.permissions`.
     - הרשמה לאירוע שדורשת `events.subscribe:X` שלא הוכרזה.
     - `network.access` או `network.enabled` בלי `network.allowlist` מפורט — אזהרה בלבד; בפועל ה-URLים חייבים להופיע גם במניפסט וגם במקור אמון רשמי של אוצריא בזמן ריצה.
   - **`design`** — דו"ח תאימות ל־[DESIGN_GUIDE.md](DESIGN_GUIDE.md): דורש `<html lang="he" dir="rtl">`, ניצול CSS variables (`var(--color-*)`, `var(--font-*)`, `var(--radius-*)`), ואיסור hex/rgb/named colors מחוץ להגדרות `:root`. גם זה אינו חוסם אריזה — נועד לעזור למפתח לוודא שהתוסף משתלב באוצריא.

3. **אריזה** — `.otzplugin` (ZIP) עם כל קבצי התיקייה, פרט לתיקיות פיתוח (`.git/`, `node_modules/`, `.idea/`, `.vscode/`, `__pycache__/`, `.claude/`…), לקבצי מטא-דאטה של המאגר (ראו למטה) ולקבצים שהוחרגו ע"י `.otzignore`. אם נתיב הפלט יושב בתוך התיקייה הנארזת, הקובץ מוחרג מהארכיון כדי שלא ייכלל בעצמו.

### קבצי מטא-דאטה מוחרגים אוטומטית

כדי שהארכיון יכיל רק מה שנדרש בזמן ריצה, מוחרגים אוטומטית גם: קבצי `*.md`, `LICENSE*`/`LICENCE*`, קבצים נסתרים (`.env`, `.DS_Store`…), קובצי lock (`package-lock.json`, `yarn.lock`, `pnpm-lock.yaml`), וכן התיקיות `.github/`, `screenshots/` וכל תיקייה נסתרת.

> ⚠️ **אם התוסף טוען אחד מהם בזמן ריצה** (למשל `fetch('help.md')` או `<img src="screenshots/demo.png">`) — הקובץ לא ייכלל בארכיון והבקשה תיכשל ב-404 אצל המשתמש. החזירו אותו במפורש בכלל `!` ב-`.otzignore`:
>
> ```gitignore
> !help.md
> !screenshots/demo.png
> ```
>
> כלל `!` מפורש **גובר** על החרגת המטא-דאטה. תיקיות פיתוח (`.git/`, `node_modules/`…) חסומות מוחלט ו-`!` אינו פותח אותן. מספר קבצי המטא-דאטה שהוחרגו מודפס בסיום האריזה, כדי שההחרגה לא תהיה שקטה.

### החרגת קבצים נוספים (`.otzignore`)

מעבר לתיקיות הפיתוח המוחרגות אוטומטית, אפשר להחריג קבצים נוספים שאין בהם צורך בזמן ריצה (מקורות גולמיים, source maps, נתונים גדולים) ע"י הוספת קובץ **`.otzignore`** בשורש תיקיית התוסף. התחביר זהה ל-`.gitignore`:

```gitignore
# הערות מותרות בתחילת שורה בלבד (כמו .gitignore) — לא בסוף שורת תבנית

# glob לפי שם הקובץ בכל עומק
*.map

# תיקייה שלמה (וכל מה שתחתיה)
src/

# נתיב מעוגן לשורש התוסף
data/raw.json

# ** חוצה מפרידי נתיב
build/**

# ! מחזיר קובץ שהוחרג ע"י כלל קודם
!src/keep.js
```

- `*` מתאים בתוך מקטע נתיב יחיד, `**` חוצה מקטעים, `?` תו בודד.
- `/` בסוף = תיקייה בלבד; `/` בתוך התבנית מעגן אותה לשורש התוסף; בלי `/` ההתאמה לפי שם הקובץ בכל עומק.
- `!` בתחילת שורה מחזיר נתיב שהוחרג ע"י כלל קודם (הכלל האחרון שמתאים קובע).
- ה-`.otzignore` עצמו לעולם לא נארז; מספר הקבצים שהוחרגו מודפס בסיום (`קבצים: N, M מוחרגים`).
- אם כלל מחריג בטעות את ה-`entrypoint` (או את נקודת הכניסה לרקע), האריזה נכשלת עם שגיאה ברורה (במקום לייצר תוסף שבור). זה תקף גם ל-entrypoint שהוא קובץ מטא-דאטה — החזירו אותו בכלל `!`.

החרגה זו פועלת באופן זהה גם ב-`otzaria pack-plugin`/סקריפט ה-`tool/` וגם ב-[Action הרשמי ל-CI](#פרסום-אוטומטי-ל-ci-github-action).

### קודי יציאה (Exit codes)

| קוד | משמעות |
|-----|---------|
| `0` | אריזה הצליחה (אזהרות אפשריות בפלט) |
| `1` | שגיאה חוסמת — manifest פגום/חסר, ולידציה נכשלה, או חריגה |
| `64` | שגיאת CLI — דגל לא מוכר, ערך חסר, או יותר מנתיב תוסף אחד |

### אריזה ידנית (ZIP — ללא ולידציה)

אם אין גישה לאוצריא המותקנת או לקוד המקור, אפשר ליצור את ה-`.otzplugin` ידנית כ-ZIP. שיטה זו **מדלגת על הולידציה** — באחריותכם לוודא שה-manifest תקין.

```bash
# macOS / Linux:
cd my-plugin/
zip -r ../my-plugin.otzplugin . -x "*.DS_Store" -x "__MACOSX/*"
```

```powershell
# Windows (PowerShell):
Compress-Archive -Path .\my-plugin\* -DestinationPath .\my-plugin.zip
Rename-Item .\my-plugin.zip my-plugin.otzplugin
```

### כללים חשובים

1. **`manifest.json` חייב להיות בשורש ה-ZIP** — לא בתוך תיקיית-מעטפת.
2. ה-`id` ב-manifest חייב להיות ייחודי — בפורמט `com.company.plugin-name`.
3. ה-`version` חייב לעלות בכל שחרור.
4. אל תכלול קבצי פיתוח (`.git/`, `node_modules/`, `*.map`).

---

## פרסום אוטומטי ל-CI (GitHub Action)

אם קוד התוסף נמצא ב-GitHub, אפשר לוותר על אריזה והעלאה ידנית בכל גרסה: ה-Action הרשמי
[**Otzaria/otzaria-plugin-validator**](https://github.com/Otzaria/otzaria-plugin-validator)
מאמת את התוסף (אותן בדיקות בדיוק כמו בחנות), בונה את ה-`.otzplugin`, ו**מפרסם אותו לחנות**
אוטומטית — מזהה את התוסף לפי ה-`id` שב-`manifest.json`, כך שאין צורך לדעת מזהים פנימיים.

Workflow מינימלי, ב-`.github/workflows/release.yml`:

```yaml
name: Publish plugin
on:
  push:
    branches: [main]

jobs:
  publish:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: Otzaria/otzaria-plugin-validator@v1
        with:
          otzaria-user: ${{ secrets.OTZARIA_USER }}
          otzaria-password: ${{ secrets.OTZARIA_PASSWORD }}
```

מגדירים את `OTZARIA_USER`/`OTZARIA_PASSWORD` כ-Secrets בריפו של התוסף
(`Settings → Secrets and variables → Actions`) — ומכאן כל `push` ל-`main` שמעלה `version`
ב-`manifest.json` מאמת, בונה ומפרסם אוטומטית. בלי הסודות ה-Action רק מאמת, בלי לפרסם —
מצוין כבדיקת PR; מטעמי אבטחה, פרסום לחנות **לעולם לא רץ** באירוע `pull_request`.

כל השאר מתועד במלואו, ומתעדכן ראשון, ב-README של
[המאגר עצמו](https://github.com/Otzaria/otzaria-plugin-validator#readme): רשימת כל
הקלטים/פלטים, אימות מקומי לפני דחיפה (כולל git hook מוכן), תגובת סיכום אוטומטית שמתעדכנת
על ה-PR, החרגת קבצים מהבנייה עם `.otzignore`, ומה בדיוק קורה מול חנות (אישור מנהל, עדכון
גרסה, ההבדל בין יוצר למנהל).

---

## התקנה ובדיקה

1. פתח את אוצריא ועבור ל-מסך "כלים"
2. לחץ על כפתור 🧩 (תוספים) בפינה
3. לחץ "⊕ התקן תוסף חדש"
4. בחר את קובץ `.otzplugin`
5. אשר את ההרשאות
6. התוסף יופיע בפאנל הצדדי; אם `defaultPinned: true` — יוצג כטאב מיד

### פתיחה ישירה דרך deep-link

אפשר לפתוח תוסף מותקן ישירות (גם אם אינו מוצמד ללשוניות) באמצעות קישור:

```text
otzaria://open/plugin/<plugin-id>
```

לדוגמה: `otzaria://open/plugin/com.example.myplugin`. שימושי לקישור מתוך אתר התוסף, מאפליקציה אחרת, או מקיצור דרך. פירוט מלא של סכמת `otzaria://` — בקובץ [`docs/deep_links.md`](../deep_links.md).

---

## שגיאות נפוצות

קריאה שנכשלה מחזירה סכמת שגיאה v1. השדות `code` ו־`message` הוותיקים נשמרו, ונוספו שדות שמאפשרים לתוסף להחליט אם להציע ניסיון חוזר:

```javascript
{
  success: false,
  data: null,
  error: {
    schemaVersion: 1,
    code: 'error.highlight_not_found',
    message: 'Highlight was not found',
    retryable: false,
    category: 'not_found'
  }
}
```

`category` הוא אחד מהערכים `permission`,‏ `validation`,‏ `not_found`,‏ `conflict`,‏ `timeout`,‏ `too_large`,‏ `internal` או `unsupported`. מטעמי תאימות, שגיאת הרשאה כללית עשויה עדיין להחזיר את הקוד הוותיק `permission_denied`; הקטגוריה שלה תמיד `permission`, וכך גם של `error.forbidden`. `error.unknown_method` ו-`error.unavailable` מקבלים `unsupported`.

| קוד שגיאה | סיבה | פתרון |
|-----------|------|--------|
| `permission_denied` | הרשאה לא הוצהרה ב-manifest או לא אושרה | הוסף לרשימת `permissions` ב-manifest |
| `error.rate_limited` | דלי של 50 אסימונים התרוקן (מילוי: אסימון כל 10ms) | הוסף debounce/throttle, ופזר פרצים גדולים בזמן |
| `error.timeout` | הפעולה לא הושלמה תוך 30 שניות | חלק לפעולות קטנות יותר |
| `error.invalid_params` | פרמטרים חסרים או שגויים | בדוק את החתימה של ה-method |
| `error.internal` | שגיאה פנימית בצד אוצריא | בדוק לוגים בהגדרות → תוספים |
| `error.forbidden` | הפעולה נחסמה גם כשההרשאה קיימת (נתיב מחוץ לתיקייה מאושרת, תיקייה מוגנת, URL שאינו ב-allowlist) | תקן את היעד או בקש מהמשתמש תיקייה אחרת |
| `error.unknown_method` | שם ה-method אינו קיים במארח הזה | בדוק איות, והעלה את `minAppVersion` אם ה-API חדש |
| `error.unavailable` | ה-API קיים אך אינו זמין בהקשר הנוכחי (אין טאב קריאה פעיל, שירות כבוי) | בדוק את ההקשר לפני הקריאה |

---

## מגבלות Highlights בגרסה הנוכחית

- ההדגשות זמניות בזיכרון. התוסף אחראי לשמור אותן ב־storage שלו ולהקים אותן מחדש ב־`plugin.boot`.
- אין בשלב זה סנכרון בין מכשירים, undo/redo מרכזי או פתרון קונפליקטים מרכזי.
- ה־Host מבודד בעלות לפי מזהה התוסף; תוסף אינו יכול לקרוא, לעדכן או למחוק הדגשות של תוסף אחר.
- החתימה הוותיקה לפי `index` נשמרת לתאימות, אך תוסף חדש צריך להשתמש ב־`TextRangeAnchor` מתוך `reader.getSelection`.
- בחירה שחוצה כמה מקטעים אינה נתמכת כעוגן יחיד בשלב זה.

---

## עיצוב וקבצי עזר

כדי שהתוסף ייראה כחלק טבעי מאוצריא, חשוב להתאים את עיצובו לשפת ה-UI של האפליקציה.

**הנקודה החשובה ביותר:** אין לקודד צבעים ישירות. **כל הצבעים חייבים להגיע מה-API** (מאירוע `plugin.boot` או מ-`app.getTheme`), מפני שהמשתמש יכול לבחור ערכת צבעים שונה ולעבור בין מצב כהה לבהיר.

מסמכים נוספים בתיקייה זו:

| קובץ | תוכן |
|------|------|
| [`API_REFERENCE.md`](API_REFERENCE.md) | תיעוד מלא של כל ה-API — כל method עם פרמטרים, ערכי החזרה ודוגמאות |
| [`DESIGN_GUIDE.md`](DESIGN_GUIDE.md) | מדריך עיצוב מלא — Color Roles, צורות, טיפוגרפיה, כפתורים, כרטיסים ואנימציות |
| [`COOKBOOK.md`](COOKBOOK.md) | מתכוני קוד מעשיים — גופן מותאם אישית, אייקונים מאוצריא, וחלונית הגדרות בסגנון "לוח שנה" |
| [`otzaria_plugin.d.ts`](otzaria_plugin.d.ts) | הגדרות TypeScript עבור האובייקט הגלובלי `Otzaria`. ניתן לכלול בפרויקטי TypeScript של תוספים לקבלת השלמה אוטומטית (autocomplete) ב-IDE. אינו נטען בריצה — האובייקט עצמו מוזרק על-ידי ה-host. |

---

## תמיכה

- GitHub Issues: https://github.com/Otzaria/otzaria/issues
- תג: `plugin-sdk`

אם אתם מעוניינים ב-API נוסף, כתבו לנו בגיטהאב!
