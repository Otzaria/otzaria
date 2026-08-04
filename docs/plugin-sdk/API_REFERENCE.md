# מדריך API למפתחי תוספים - אוצריא

מסמך זה מרכז את כל ה-APIs הזמינים לתוספים באוצריא.

---

## זהות ספר אחידה

ב־APIs ובאירועים המפורטים להלן, אוצריא מחזירה שדות זהות נוספים לספר:

```json
{
  "id": 183,
  "type": "pdf",
  "bookId": "שם הספר",
  "source": "library"
}
```

| שדה | משמעות |
|-----|--------|
| `id` | המזהה המספרי של הספר במסד הנתונים (`int?` — יכול להיות `null` לספרים ללא מזהה. אם ה-id לא זמין, ניתן לחפש לפי `bookId` + `type`) |
| `type` | סוג הספר: `"text"` \| `"pdf"` \| `"docx"` \| `"epub"` \| `"external"`. `null` עבור טאבים שאינם ספרים (SearchingTab, CombinedTab) |
| `bookId` | שם הספר — נשמר לצורך תאימות לאחור ולאימות כאשר נשלח יחד עם `id` |
| `source` | מקור הספר: `"library"` לספרייה המובנית, `"user"` ל־`user_books.db`, או `"external"` לקטלוג חיצוני. חובה לשלוח אותו עם `id` כאשר ה־ID עלול להתנגש בין מסדי נתונים. |

### APIs שמחזירים זהות מלאה

| API | id | type | bookId |
|-----|-----|------|--------|
| `library.findBooks` | ✓ | ✓ | ✓ |
| `library.getBookMetadata` | ✓ | ✓ | ✓ |
| `library.listRecentBooks` | ✓ | ✓ | ✓ |
| `library.getTree` | ✓ | ✓ | ✓ |
| `reader.openBook` | קלט | קלט | קלט |
| `reader.openBookAtRef` | קלט | קלט | קלט |
| `reader.getCurrentState` | ✓ | ✓ | ✓ |
| `reader.getCurrentRef` | ✓ | ✓ | ✓ |
| `reader.getSelection` | ✓ | ✓ | ✓ |
| `history.list` | ✓ | ✓ | ✓ |
| `history.remove` | קלט | קלט | קלט |
| `search.fullText` | ✗ (ראה הערה) | ✓ | — |
| `library.getBookContent` | ✗ | ✗ | ✓ |
| `library.getBookToc` | ✗ | ✗ | ✓ |
| `library.getBookAltToc` | ✗ | ✗ | ✓ |

> **הערה על `search.fullText`:** מנוע החיפוש (Tantivy) אינו שומר את ה-`id` מה-DB. כדי לקבל `id` — קרא ל-`library.getBookMetadata({ bookId, type })` עם התוצאה.

> **הערה על DocxBook / EpubBook:** ספרים בפורמטים אלו נפתחים בתצוגת טקסט, אך `type` נשאר `"docx"` או `"epub"` כדי לשמור על הזהות הקנונית.

- **`bookId` לא השתנה** — תוספים קיימים שמסתמכים עליו ימשיכו לעבוד.
- **כאשר שולחים כמה שדות זהות** (למשל `id` + `bookId` + `type` + `source`), כולם חייבים להתאים לאותו ספר. אם יש סתירה או שהזהות אינה חד-משמעית, ה-API מחזיר `null` / `false`.
- **חיפוש לפי `id` בלבד** — נתמך ב-`library.getBookMetadata`, `reader.openBook`, `reader.openBookAtRef`.
- **חיפוש לפי `bookId` בלבד** — נשמר לתאימות לאחור בכל API.
- **שני ספרים בעלי אותו שם** — ניתן להבדיל ביניהם בעזרת `id` + `type`.

---

## שימוש בסיסי

```javascript
const response = await Otzaria.call('method.name', { param: value });
if (response.success) {
  console.log(response.data);
} else {
  console.error(response.error.code, response.error.message);
  if (response.error.retryable) {
    // אפשר להציע למשתמש לנסות שוב.
  }
}
```

כל שגיאה כוללת `schemaVersion: 1`,‏ `code`,‏ `message`,‏ `retryable` ו־`category`. השדות הקיימים נשמרו לתאימות לאחור.

---

## טבלת גרסאות API

הטבלה מציינת מאיזו גרסת אוצריא כל API זמין. הגדר את `minAppVersion` במניפסט כך שיהיה **לפחות** הגרסה הגבוהה ביותר מבין ה-APIs שבהם התוסף משתמש.

> סקריפט האריזה (`otzaria pack-plugin` / `dart run tool/plugins/package_plugin.dart`) **חוסם אריזה** אם התוסף קורא ל-API חדש מ-`minAppVersion` שהוצהר — כך תוסף לא יישלח עם דרישת גרסה נמוכה מדי שתגרום לו לקרוס אצל משתמשים בגרסה ישנה.

| API | קיים מגרסה |
|-----|-----------|
| `app.getInfo` | 0.9.89 |
| `app.getTheme` | 0.9.89 |
| `app.getLocale` | 0.9.89 |
| `app.getUserEmail` | 0.9.89 |
| `app.getGrantedPermissions` | 0.9.89 |
| `app.openUrl` | 0.9.95 |
| `library.findBooks` | 0.9.89 |
| `library.getBookMetadata` | 0.9.89 |
| `library.listRecentBooks` | 0.9.89 |
| `library.getBookContent` | 0.9.89 |
| `library.getBookToc` | 0.9.89 |
| `library.listBookAltStructures` | 0.9.96 |
| `library.getBookAltToc` | 0.9.96 |
| `library.getTree` | 0.9.93 |
| `network.fetch` | 0.9.93 |
| `network.download` | 0.9.93 |
| `search.fullText` | 0.9.89 |
| `reader.openBook` | 0.9.89 |
| `reader.openBookAtRef` | 0.9.89 |
| `reader.getCurrentState` | 0.9.89 |
| `reader.getCurrentRef` | 0.9.89 |
| `reader.getSelection` | 0.9.89 |
| `reader.findTextOccurrences` | 0.9.95 |
| `reader.getSectionTextMap` | 0.9.95 |
| `reader.addContextMenuItem` | 0.9.89 |
| `reader.removeContextMenuItem` | 0.9.89 |
| `reader.updateContextMenuItem` | 0.9.95 |
| `reader.setHighlight` | 0.9.89 |
| `reader.updateHighlight` | 0.9.95 |
| `reader.getHighlights` | 0.9.89 |
| `reader.revealHighlight` | 0.9.96 |
| `reader.clearHighlight` | 0.9.89 |
| `reader.clearAllHighlights` | 0.9.89 |
| `navigation.goTo` | 0.9.89 |
| `plugin.openSelf` | 0.9.96 |
| `notes.list` | 0.9.89 |
| `notes.getBookNotesSummary` | 0.9.89 |
| `notes.add` | 0.9.89 |
| `notes.update` | 0.9.89 |
| `notes.delete` | 0.9.89 |
| `ui.showMessage` | 0.9.89 |
| `ui.showSuccess` | 0.9.89 |
| `ui.showError` | 0.9.89 |
| `ui.showConfirm` | 0.9.89 |
| `ui.showWarning` | 0.9.89 |
| `ui.pickFolder` | 0.9.93 |
| `fs.extractZip` | 0.9.93 |
| `fs.deleteFile` | 0.9.93 |
| `fs.pickUserFile` | 0.9.94 |
| `fs.resolveFileUrl` | 0.9.94 |
| `fs.readTextFile` | 0.9.94 |
| `fs.revokeFile` | 0.9.94 |
| `feedback.sendEmail` | 0.9.89 |
| `history.list` | 0.9.89 |
| `history.listSearches` | 0.9.89 |
| `history.clear` | 0.9.89 |
| `history.remove` | 0.9.89 |
| `notifications.showInApp` | 0.9.89 |
| `notifications.sendSystem` | 0.9.89 |
| `notifications.scheduleSystem` | 0.9.89 |
| `notifications.cancel` | 0.9.89 |
| `notifications.cancelAll` | 0.9.89 |
| `notifications.checkPermissions` | 0.9.89 |
| `notifications.requestPermissions` | 0.9.89 |
| `storage.get` | 0.9.89 |
| `storage.set` | 0.9.89 |
| `storage.remove` | 0.9.89 |
| `storage.list` | 0.9.89 |
| `settings.get` | 0.9.89 |
| `settings.getMany` | 0.9.89 |
| `calendar.getSelectedDate` | 0.9.89 |
| `calendar.getDailyTimes` | 0.9.89 |
| `calendar.getHalachicTimes` | 0.9.89 |
| `calendar.getJewishDate` | 0.9.89 |
| `calendar.getEvents` | 0.9.89 |
| `publishedData.upsert` | 0.9.89 |
| `publishedData.remove` | 0.9.89 |
| `publishedData.listOwn` | 0.9.89 |
| `database.listSources` | 0.9.89 |
| `database.describeSource` | 0.9.89 |
| `database.query` | 0.9.89 |
| `database.batchQuery` | 0.9.89 |
| `shortcut.create` | 0.9.94 |

> מקור-האמת לאכיפה הוא המפה `_methodMinVersion` ב-`lib/plugins/services/plugin_extended_validator.dart`. הטבלה כאן נגזרת ממנה ו-`test/plugins/plugin_method_versions_test.dart` מוודא ששתיהן זהות.

---

## app.* - מידע על האפליקציה

**הרשאה נדרשת:** `app.info.read` (למעט `app.getUserEmail` שמצריכה `app.user_email.read` - ראה למטה)

### `app.getInfo`
מחזיר מידע על גרסת האפליקציה והפלטפורמה.

```javascript
const { data } = await Otzaria.call('app.getInfo');
// { version: "5.2.1", buildNumber: "123", platform: "windows" }
```

### `app.getTheme`
מחזיר את ערכת הצבעים והטיפוגרפיה הנוכחית.

> **חשוב:** אל תקרא ל-`app.getTheme` ידנית בטעינה — הנתונים כבר נכללים ב-`plugin.boot`.
> השתמש ב-API הזה רק אם צריך לרענן את הנתונים לאחר שכבר עלה התוסף.
> האזן לאירוע `theme.changed` כדי לקבל עדכונים בזמן אמת.

```javascript
const { data } = await Otzaria.call('app.getTheme');
// {
//   mode: "light" | "dark",
//   colorScheme: {
//     primary:                 "#6750A4",  // הצבע הראשי
//     onPrimary:               "#FFFFFF",  // טקסט/אייקון מעל primary
//     secondary:               "#625B71",  // הדגשות משניות
//     onSecondary:             "#FFFFFF",  // טקסט/אייקון מעל secondary
//     secondaryContainer:      "#E8DEF8",  // רקע כפתור ניווט פעיל בסרגל הצד (pill)
//     onSecondaryContainer:    "#1D192B",  // אייקון/טקסט מעל secondaryContainer
//     surface:                 "#FFFBFE",  // רקע כרטיסים וחלוניות
//     onSurface:               "#1C1B1F",  // טקסט ראשי
//     surfaceContainerHigh:    "#ECE6F0",  // רקע הסרגל העליון (AppTopBar) במסכי הספרים
//     surfaceContainerHighest: "#E6E0E9",  // פופאוברים, דיאלוגים
//     error:                   "#B3261E",  // שגיאות
//     onError:                 "#FFFFFF",  // טקסט מעל error
//     outline:                 "#79747E",  // מסגרות ומפרידים
//     ... (תפקידי הצבע העיקריים — ראה otzaria_plugin.d.ts → ColorScheme)
//   },
//   typography: {
//     fontFamily:             "Frank Ruhl Libre",
//     fontSize:               25,    // לפי הגדרת המשתמש — אל תניח ערך קבוע!
//     lineHeight:             1.5,
//     commentatorsFontFamily: "Shofar",
//     commentatorsFontSize:   22,
//   }
// }
```

הצבעים הם **Material Design 3 Color Roles** בפורמט hex RGB (`#rrggbb`).
ראה [DESIGN_GUIDE.md](DESIGN_GUIDE.md) להסבר מלא על השימוש בהם.

> **גופנים מוטמעים אוטומטית:** השמות שמגיעים ב-`typography.fontFamily` ו-`typography.commentatorsFontFamily` (כגון `FrankRuhlCLM`, `Shofar`, `NotoRashiHebrew`) נטענים אוטומטית ב-WebView של התוסף כ-`@font-face` עוד לפני ה-`plugin.boot`. אין צורך לארוז את קבצי הגופן בתוסף — מספיק להפנות לשם שהתקבל ב-CSS: `font-family: 'FrankRuhlCLM', serif;`. אם המשתמש בחר גופן מערכת (לא מובנה), ההזרקה האוטומטית מדלגת עליו וה-WebView ייפול חזרה ל-fallback של מערכת ההפעלה.

### `app.getLocale`
מחזיר את השפה וכיוון הטקסט.

```javascript
const { data } = await Otzaria.call('app.getLocale');
// { locale: "he-IL", textDirection: "rtl" }
```

### `app.getUserEmail`
**הרשאה נדרשת:** `app.user_email.read`

מחזיר את כתובת המייל של המשתמש לזיהוי (אם הוגדרה).

```javascript
const { data } = await Otzaria.call('app.getUserEmail');
// { email: "user@example.com" } או { email: "" }
```

### `app.getGrantedPermissions`
**הרשאה:** `app.info.read`

מחזיר snapshot עדכני של ההרשאות המאושרות בפועל עבור התוסף.

```javascript
const { data } = await Otzaria.call('app.getGrantedPermissions');
// { permissions: ["app.info.read", "reader.open"] }
```

הערה: בשדה `permissions` של `plugin.boot` מתקבל snapshot בזמן העלייה בלבד. אם אתם צריכים מצב עדכני אחרי שהמשתמש שינה הרשאות, השתמשו ב-API הזה או האזינו ל-`plugin.permissions_changed`.

### `app.openUrl`
**הרשאה נדרשת:** `app.open_url`

פותח כתובת אינטרנט בדפדפן ברירת המחדל של מערכת ההפעלה (לא בתוך התוסף).

```javascript
await Otzaria.call('app.openUrl', { url: 'https://example.com' });
// מחזיר true בהצלחה
```

מותרות אך ורק כתובות `http`/`https`. סכמות אחרות (`file://`, `javascript:`, פרוטוקולים מותאמים) נדחות עם `error.forbidden`.

---

## library.* - גישה לספרייה

### `library.findBooks`
**הרשאה:** `library.books.read`

חיפוש ספרים לפי כותרת.

```javascript
const { data } = await Otzaria.call('library.findBooks', {
  query: 'רמב"ם',
  limit: 10  // אופציונלי, ברירת מחדל: 20
});
// [{ bookId: "משנה תורה", title: "משנה תורה", topics: [...] }, ...]
```

### `library.getBookMetadata`
**הרשאה:** `library.books.read`

קבלת מטא-דאטה על ספר ספציפי.

```javascript
const { data } = await Otzaria.call('library.getBookMetadata', {
  bookId: 'בראשית'
});
// { bookId: "בראשית", title: "בראשית", topics: ["תנ\"ך", "תורה"] }
```

### `library.listRecentBooks`
**הרשאה:** `library.books.read`

רשימת הספרים שנפתחו לאחרונה.

```javascript
const { data } = await Otzaria.call('library.listRecentBooks');
// [{ bookId: "בראשית", title: "בראשית", ref: "פרק א" }, ...]
```

### `library.getTree`
**הרשאה:** `library.books.read`

קבלת מבנה עץ הספרייה המלא — כל הקטגוריות, תתי-הקטגוריות והספרים, כפי שמוצג במסך הראשי (כולל ספרים אישיים שהמשתמש הוסיף). העץ מתעדכן אוטומטית כשהספרייה משתנה.

```javascript
const { data } = await Otzaria.call('library.getTree', {
  path: '/תנך/ראשונים',  // אופציונלי: צמצום לתת-קטגוריה לפי נתיב. ברירת מחדל: כל הספרייה
  includeBooks: true       // אופציונלי, ברירת מחדל: true — האם לכלול את רשימות הספרים
});
// {
//   title: "ספריית אוצריא",
//   path: "/",
//   categories: [
//     {
//       title: "תנך",
//       path: "/תנך",
//       categories: [ ... ],
//       books: [
//         { bookId: "בראשית", title: "בראשית", type: "text", author: "...", topics: "..." },
//         ...
//       ]
//     },
//     ...
//   ],
//   books: []
// }
// כש-path לא נמצא: מוחזר null.
```

### `library.getBookContent`
**הרשאה:** `library.content.read`

קבלת תוכן הספר (עד 5000 תווים בקריאה).

```javascript
const { data } = await Otzaria.call('library.getBookContent', {
  bookId: 'בראשית',
  offset: 0,      // אופציונלי, ברירת מחדל: 0
  limit: 2000,    // אופציונלי, ברירת מחדל: 1000, מקסימום: 5000
  section: ''     // אופציונלי, קפיצה לקטע מסוים
});
// "בראשית ברא אלהים..."
```

### `library.getBookToc`
**הרשאה:** `library.content.read`

קבלת תוכן עניינים של ספר.

```javascript
const { data } = await Otzaria.call('library.getBookToc', {
  bookId: 'בראשית'
});
// [{ text: "פרק א", index: 0, level: 1 }, ...]
```

---

### `library.listBookAltStructures`
**הרשאה:** `library.content.read`

קבלת רשימת מבני תוכן-העניינים החלופיים ("כותרות") של ספר — למשל חלוקה לפי
פרשות לצד החלוקה לפי פרקים. כל מבנה מוחזר עם `key` (מזהה יציב בין גרסאות
ספרייה, לשימוש כ-`structureKey` ב-`getBookAltToc`), `title` ו-`heTitle`.

ספר ללא מבנים חלופיים, ספר אישי או קובץ מקומי — מחזיר מערך ריק.

```javascript
const { data } = await Otzaria.call('library.listBookAltStructures', {
  bookId: 'בראשית'
});
// [{ key: "Parasha", title: "Parasha", heTitle: "פרשה" }, ...]
```

---

### `library.getBookAltToc`
**הרשאה:** `library.content.read`

קבלת מבנה תוכן-עניינים חלופי של ספר כמערך שטוח — באותו מבנה בדיוק כמו
`getBookToc`: `[{ text, index, level }]`.

פרמטרים: `bookId` (חובה), `structureKey` (אופציונלי — ה-`key` שהתקבל מ-
`listBookAltStructures`; תלוי-רישיות — למשל `"Parasha"`). אם לא סופק
`structureKey`, נבחר המבנה הראשון. אם סופק `key` שאינו קיים — נזרקת שגיאה
עם קוד `error.not_found`.

הסדר הוא סדר המסמך (flatten היררכי depth-first). כותרת-אב ללא שורה משלה
מקבלת את ה-`index` של הצאצא הראשון (depth-first) שיש לו שורה; כותרת שאין
לה ולאף צאצא שורה — מושמטת. ספר ללא מבנים חלופיים / ספר אישי / קובץ —
מחזיר מערך ריק.

```javascript
const { data } = await Otzaria.call('library.getBookAltToc', {
  bookId: 'בראשית',
  structureKey: 'Parasha' // אופציונלי; ברירת מחדל = המבנה הראשון
});
// [{ text: "בראשית", index: 0, level: 1 }, ...]
```

---

## network.* - גישה לרשת

> כל גישת רשת מוגבלת לרשימת ההיתר של אוצריא — ראו [⚠️ הרשאת `network.access`](#️-הרשאת-networkaccess--דרישה-מיוחדת-pr-לאוצריא).

### `network.fetch`
**הרשאה:** `network.access` (או `network.localhost` ליעד מקומי — ראו [שירותים מקומיים](#שירותים-מקומיים-localhost--הרשאת-networklocalhost))

שליפת תוכן מ-URL מותר (ללא מעקב אחר redirects). מחזירה את גוף התשובה כטקסט.

**חשוב — מתי להשתמש בזה במקום `fetch()` רגיל:** קריאת `fetch()` ישירה מתוך
ה-WebView של התוסף כפופה ל-CORS (ה-origin הוא `null` כי הדף נטען מ-`file://`).
שרת שלא מחזיר `Access-Control-Allow-Origin` יחסום את הבקשה. `network.fetch`
רץ בצד אוצריא (Flutter) ואינו כפוף ל-CORS — לכן לקריאות ל-APIs חיצוניים
(במיוחד `POST`) יש להשתמש בו ולא ב-`fetch()` ישיר.

פרמטרים: `url` (חובה), `method` (ברירת מחדל `GET`), `headers` (אובייקט,
אופציונלי), `body` (מחרוזת, אופציונלי).

```javascript
// GET פשוט
const { data } = await Otzaria.call('network.fetch', {
  url: 'https://api.github.com/repos/Owner/Repo/releases/latest'
});
// { status: 200, ok: true, body: "..." }

// POST עם גוף JSON (למשל קריאה ל-API חיצוני)
const res = await Otzaria.call('network.fetch', {
  url: 'https://api.example.com/endpoint',
  method: 'POST',
  headers: { 'Content-Type': 'application/json;charset=UTF-8' },
  body: JSON.stringify({ key: 'value' })
});
if (res.success && res.data.ok) {
  const parsed = JSON.parse(res.data.body);
}
```

### `network.download`
**הרשאה:** `network.access` (או `network.localhost` ליעד מקומי)

הורדה רגילה של קובץ מ-URL מותר אל **תיקיית ההורדות** של המערכת. ההורדה
מתבצעת בצד אוצריא (Flutter), כך שאין צורך ב-`showDirectoryPicker` או
ב-File System Access API (שאינם זמינים ל-WebView של התוסף).

- ה-`url` חייב להופיע גם ב-`network.allowlist` של התוסף וגם ברשימת ההיתר הרשמית של אוצריא (הקובץ בענף `plugin-network-allowlist` ב-GitHub, או הגיבוי המקומפל `pluginNetworkAllowlist`).
  redirect של גיטהאב ל-CDN מטופל אוטומטית בצד אוצריא.
- `filename` אופציונלי; אם לא סופק, שם הקובץ נגזר מה-URL.
- אם קיים כבר קובץ באותו שם, נוספת סיומת מספרית (` (1)`) כדי לא לדרוס.
- `destPath` אופציונלי: נתיב קובץ מלא שאליו תישמר ההורדה במקום תיקיית
  ההורדות. **הנתיב חייב להיות בתוך תיקייה שהמשתמש בחר דרך `ui.pickFolder`**
  (ראו [`ui.pickFolder`](#uipickfolder)); אחרת מוחזרת `error.forbidden`.
  כאשר `destPath` סופק, תיקיית האב נוצרת במידת הצורך וקובץ קיים נדרס.
- `resume` אופציונלי ורלוונטי רק יחד עם `destPath`. כאשר ערכו `true`, אוצריא
  שומר הורדה חלקית וממשיך אותה בניסיון הבא באמצעות `Range` ו-`If-Range`.
  המשך מתבצע רק כשיש `ETag` חזק שמוכיח שהמשאב לא השתנה; אחרת מתחילים מחדש.

```javascript
const { data } = await Otzaria.call('network.download', {
  url: 'https://github.com/Owner/Repo/releases/latest/download/books.zip',
  filename: 'books.zip' // אופציונלי
});
// { path: "C:\\Users\\...\\Downloads\\books.zip", filename: "books.zip" }

// הורדה אל נתיב מלא בתוך תיקייה שהמשתמש בחר:
const folder = await Otzaria.call('ui.pickFolder', { title: 'בחר תיקיית יעד' });
if (folder.success && folder.data.path) {
  await Otzaria.call('network.download', {
    url: 'https://github.com/Owner/Repo/releases/latest/download/books.zip',
    destPath: folder.data.path + '/books.zip',
    resume: true
  });
}
```

שגיאות אפשריות: `error.permission_denied` (אין הרשאת network.access),
`error.forbidden` (URL לא ברשימת ההיתר, או `destPath` מחוץ לתיקייה מאושרת),
`error.invalid_params` (URL חסר/לא תקין), `error.internal` (כשל הורדה).

---

## search.* - חיפוש

### `search.fullText`
**הרשאה:** `search.fulltext.read`

חיפוש טקסט מלא בכל הספרייה.

```javascript
const { data } = await Otzaria.call('search.fullText', {
  query: 'ואהבת לרעך כמוך',
  limit: 50  // אופציונלי, ברירת מחדל: 50
});
// [{ type: "text", book: "ויקרא", text: "ואהבת לרעך כמוך...", index: 1234 }, ...]
```

פלט כל תוצאה:
- `type` — סוג הספר: `"text"` לספר טקסט, `"pdf"` ל-PDF
- `book` — שם הספר
- `text` — קטע הטקסט
- `index` — אינדקס השורה/עמוד בספר

> **הערה:** `search.fullText` אינו מחזיר `id` כי מנוע החיפוש (Tantivy) אינו שומר את מזהה הספר מה-DB. כדי לקבל את `id` — יש לקרוא ל-`library.getBookMetadata({ bookId, type })` עם התוצאה.

---

## reader.* - פעולות קריאה

### `reader.openBook`
**הרשאה:** `reader.open`

פתיחת ספר במיקום מסוים.

```javascript
// קריאה ישנה — עדיין עובדת:
await Otzaria.call('reader.openBook', { bookId: 'בראשית', index: 0 });

// קריאה חדשה עם זהות מלאה:
await Otzaria.call('reader.openBook', {
  id: 183,              // מזהה מספרי (אופציונלי)
  bookId: 'בראשית',    // נדרש אחד מ-id / bookId
  type: 'text',         // אופציונלי — מוודא שמדובר בסוג הנכון
  index: 0,             // אופציונלי, ברירת מחדל: 0
  searchQuery: '',      // אופציונלי, הדגשת טקסט
  navigateToPositionIfReused: false  // אופציונלי — אם הטאב פתוח, נווט אליו
});
// true — פתח בהצלחה; false — הספר לא נמצא או הזהות לא תואמת
```

**כאשר נשלחים מספר שדות זהות (id + bookId + type), כולם חייבים להתאים לאותו ספר. אי-התאמה מחזירה `false`.**

### `reader.openBookAtRef`
**הרשאה:** `reader.open`

פתיחת ספר בהתייחסות. תומך גם ברמת תת-כותרת — פסוק בתוך פרק, סעיף בתוך סימן —
בפורמט `רכיב-על:רכיב-משנה` (או עם פסיק/רווח/מילות מיקום כמו "פרק"/"סעיף").

```javascript
// רמת כותרת (TOC):
await Otzaria.call('reader.openBookAtRef', {
  bookId: 'בראשית',
  ref: 'פרק א',
  index: 0  // אופציונלי, גיבוי אם ההתייחסות לא נמצאה
});

// רמת תת-כותרת (מגרסה 0.9.96) — פסוק/סעיף מדויק, עם הדגשה:
await Otzaria.call('reader.openBookAtRef', {
  bookId: 'במדבר',
  ref: 'לג:ה',        // גם 'לג, ה' / 'פרק לג פסוק ה'
  highlight: true      // אופציונלי (ברירת מחדל false) — הדגשת רקע ליעד
});
// true
```

הערות:
- אם ההתייחסות כוללת טווח (`'לג:ה-ז'`) — הניווט הוא לתחילת הטווח.
- `highlight` חל גם על התאמה ברמת כותרת; אם ההתייחסות לא נמצאה כלל — אין הדגשה,
  והטקסט מועבר לתיבת החיפוש כגיבוי (התנהגות קיימת).

### `reader.getCurrentState`
**הרשאה:** `reader.open`

קבלת מצב הקורא הנוכחי.

```javascript
const { data } = await Otzaria.call('reader.getCurrentState');
// {
//   currentBook: "בראשית",
//   currentBookId: "בראשית",
//   currentId: 183,           // מזהה מספרי של הספר הפעיל
//   currentType: "text",      // סוג הספר הפעיל
//   currentSource: "library",  // מקור הספר הפעיל
//   currentIndex: 42,
//   currentRef: "בראשית פרק ג",
//   openTabs: [
//     {
//       id: 183,        // מזהה מספרי
//       type: "text",   // סוג הספר
//       bookId: "בראשית",
//       book: "בראשית",
//       index: 42,
//       currentRef: "בראשית פרק ג"
//     },
//     {
//       id: 204,
//       type: "pdf",
//       bookId: "שמות",
//       book: "שמות",
//       index: 0,
//       currentRef: null
//     }
//   ]
// }
```

### `reader.getCurrentRef`
**הרשאה:** `reader.open`

מחזיר את ה-reference הנוכחי של הטאב הפעיל. `currentRef` יהיה `null` אם עדיין אין reference אמין.

```javascript
const { data } = await Otzaria.call('reader.getCurrentRef');
// {
//   currentBook: "בראשית",
//   currentBookId: "בראשית",
//   currentId: 183,        // מזהה מספרי
//   currentType: "text",   // סוג הספר
//   currentSource: "library",
//   currentIndex: 42,
//   currentRef: "בראשית פרק ג"
// }
```

### `reader.getSelection`
**הרשאה:** `reader.open`

**העוגן המורחב זמין מגרסה:** `0.9.95` (השדות הוותיקים זמינים מ־`0.9.89`)

מחזיר את הבחירה הנוכחית בטאב טקסט פעיל. אם אין בחירה פעילה, או שהטאב הפעיל אינו טאב טקסט, הערך יהיה `null`. כאשר ה־Host יכול לאמת את הטווח, מוחזר גם עוגן v1 המבוסס על טקסט המקור. השדות הוותיקים נשמרים לתאימות.

```javascript
const { data } = await Otzaria.call('reader.getSelection');
// {
//   id: 183,               // מזהה מספרי של הספר
//   type: "text",          // סוג הספר
//   text: "ויאמר אלהים",
//   start: 120,
//   end: 131,
//   currentRef: "בראשית פרק א",
//   currentBook: "בראשית",
//   currentBookId: "בראשית",
//   currentIndex: 42,
//   schemaVersion: 1,
//   selectionId: "...",
//   bookId: "בראשית",
//   sectionIndex: 42,
//   renderedSelectedText: "ויאמר אלהים",
//   sourceSelectedText: "וַיֹּאמֶר אֱלֹהִים",
//   sourceRange: { ... }
// }
```

יחידת המיקום הקנונית היא grapheme cluster לפי חלוקת Unicode של ה־Host. `codePoint` ו־`utf16` נמסרים לצורכי שילוב בלבד; אין להשתמש ב־`String.length` של JavaScript כעוגן קנוני.

### `reader.findTextOccurrences`
**הרשאה:** `reader.open`

**זמין מגרסה:** `0.9.95`

מחפש מופעים במקטע יחיד ומחזיר עוגן מדויק לכל תוצאה. ברירת המחדל היא חיפוש ב־source עם פרופיל `strict`. המקטע נטען לבדו; אין טעינה של ספר שלם.

```javascript
const { data } = await Otzaria.call('reader.findTextOccurrences', {
  bookId: 'בראשית',
  sectionIndex: 42,
  query: 'בראשית',
  layer: 'source',
  normalize: { profile: 'search' },
  limit: 50
});

for (const occurrence of data.results) {
  console.log(occurrence.text, occurrence.range);
}

if (data.hasMore) {
  const next = await Otzaria.call('reader.findTextOccurrences', {
    bookId: 'בראשית',
    sectionIndex: 42,
    query: 'בראשית',
    layer: 'source',
    normalize: { profile: 'search' },
    limit: 50,
    cursor: data.nextCursor
  });
}
```

פרופילי הנרמול:

- `strict` — ללא הסרת סימנים.
- `display` — בהתאם להגדרות התצוגה הפעילות.
- `search` — מתעלם מניקוד וטעמים ומאחד רווחים.
- `lenient` — מוסיף הסרת פיסוק ואיחוד אותיות סופיות.

ה־cursor קשור לספר, למקטע, לשכבה, לשאילתה, לפרופיל ול־hash של הטקסט. שימוש בו לאחר שינוי אחד מהם מחזיר `error.invalid_params`. מקטע מעל 50,000 grapheme clusters מחזיר `error.section_too_large`.

### `reader.getSectionTextMap`
**הרשאה:** `reader.open`

**זמין מגרסה:** `0.9.95`

מחזיר את טקסט המקור, הטקסט המוצג או שניהם עבור מקטע יחיד. אפשר לצרף מיפוי Source↔Rendered, טוקני מילים וטוקני תווים.

```javascript
const { data } = await Otzaria.call('reader.getSectionTextMap', {
  bookId: 'בראשית',
  sectionIndex: 42,
  layer: 'both',
  includeSourceMap: true,
  includeWords: true,
  includeChars: false,
  normalize: { profile: 'search' },
  limit: 500
});
```

`WordToken` כולל offsets ועוגנים הן למקור והן לתצוגה כאשר ניתן למפות אותם. `CharToken` מייצג grapheme cluster אחד ומחזיר offsets בכל שלוש היחידות. טוקני מילים ותווים מחולקים לעמודים משותפים; `nextCursor` ממשיך בדיוק מאותה בקשה.

המגבלות הן 2,000 טוקנים לעמוד ו־50,000 grapheme clusters למקטע. מקטעי מפת המקור משתמשים רק בסוגים `identity`,‏ `substitution`,‏ `hidden` ו־`inserted`.

---

## navigation.* - ניווט באפליקציה

### `navigation.goTo`
**הרשאה:** `navigation.write`

מעבר למסך ראשי באפליקציה.

```javascript
const { data } = await Otzaria.call('navigation.goTo', {
  target: 'library'  // 'library' | 'reading' | 'more' | 'settings'
});
// true
```

---

### `plugin.openSelf`
**הרשאה:** `navigation.write` | **מגרסה:** 0.9.96

מעביר את המשתמש לדף התוסף (מסך "כלים"), עם פרמטר אופציונלי שיימסר לתוסף.

שימושי בעיקר מ-instance רקע (`background.html`): למשל, בתגובה ללחיצה על פריט
תפריט הקשר או על התראה — פותחים את דף התוסף עם ההקשר הרלוונטי.

```javascript
await Otzaria.call('plugin.openSelf', {
  param: { view: 'results', query: 'ויאמר' }  // כל ערך JSON (אופציונלי)
});
// true
```

ה-`param` נמסר לדף התוסף באירוע `plugin.page_opened`:

```javascript
Otzaria.on('plugin.page_opened', (data) => {
  console.log(data.param);  // { view: 'results', query: 'ויאמר' }
});
```

**הערות:**
- אם דף התוסף עדיין לא נטען, האירוע יישלח מיד אחרי ה-boot שלו — אין צורך בהמתנה מיוחדת.
- תוסף יכול לפתוח רק את הדף של עצמו, לא של תוספים אחרים.

---

## notes.* - הערות אישיות

### `notes.list`
**הרשאה:** `notes.read`

רשימת הערות לספר מסוים.

```javascript
const { data } = await Otzaria.call('notes.list', {
  bookId: 'בראשית'
});
// [{ id: "123", lineNumber: 5, content: "הערה...", contentPlain: "הערה..." }, ...]
```

### `notes.getBookNotesSummary`
**הרשאה:** `notes.read`

סיכום של כל הספרים שיש להם הערות.

```javascript
const { data } = await Otzaria.call('notes.getBookNotesSummary');
// [{ bookId: "בראשית", noteCount: 5, lastModified: "2026-04-08T10:30:00Z" }, ...]
```

### `notes.add`
**הרשאה:** `notes.write`

הוספת הערה חדשה.

```javascript
const { data } = await Otzaria.call('notes.add', {
  bookId: 'בראשית',
  lineNumber: 10,
  content: 'הערה חשובה'
});
// true
```

### `notes.update`
**הרשאה:** `notes.write`

עדכון הערה קיימת.

```javascript
const { data } = await Otzaria.call('notes.update', {
  bookId: 'בראשית',
  noteId: '123',
  content: 'הערה מעודכנת'
});
// true
```

### `notes.delete`
**הרשאה:** `notes.write`

מחיקת הערה.

```javascript
const { data } = await Otzaria.call('notes.delete', {
  bookId: 'בראשית',
  noteId: '123'
});
// true
```

---

## ui.* - ממשק משתמש

### `ui.showMessage`
**הרשאה:** `ui.feedback`

הצגת הודעה רגילה.

```javascript
await Otzaria.call('ui.showMessage', {
  message: 'הפעולה בוצעה בהצלחה'
});
```

### `ui.showSuccess`
**הרשאה:** `ui.feedback`

הצגת הודעת הצלחה.

```javascript
await Otzaria.call('ui.showSuccess', {
  message: 'הנתונים נשמרו'
});
```

### `ui.showError`
**הרשאה:** `ui.feedback`

הצגת הודעת שגיאה.

```javascript
await Otzaria.call('ui.showError', {
  message: 'אירעה שגיאה'
});
```

### `ui.showConfirm`
**הרשאה:** `ui.feedback`

הצגת דיאלוג אישור.

```javascript
const { data } = await Otzaria.call('ui.showConfirm', {
  title: 'אישור מחיקה',
  content: 'האם אתה בטוח שברצונך למחוק?'
});
// { confirmed: true } או { confirmed: false }
```

### `ui.showWarning`
**הרשאה:** `ui.feedback`

הצגת דיאלוג אזהרה (לפעולות מסוכנות).

```javascript
const { data } = await Otzaria.call('ui.showWarning', {
  title: 'אזהרה',
  content: 'פעולה זו היא בלתי הפיכה',
  subtitle: 'לא ניתן לשחזר את הנתונים'  // אופציונלי
});
// { confirmed: true } או { confirmed: false }
```

### `ui.pickFolder`
**הרשאה:** `ui.feedback`

פתיחת דיאלוג מערכת לבחירת תיקייה. מחזירה את הנתיב שנבחר, או `{ path: null }`
אם המשתמש ביטל.

מעבר להחזרת הנתיב, בחירת התיקייה **מעניקה לתוסף הרשאת כתיבה/מחיקה בתוכה**:
מכאן ואילך מותר לו להוריד אליה (`network.download` עם `destPath`), לחלץ
אליה (`fs.extractZip`) ולמחוק קבצים בתוכה (`fs.deleteFile`). זהו גבול
האבטחה לגישת התוסף לדיסק — היא נובעת מהסכמת המשתמש בדיאלוג, לא מהרשאת
manifest. ההרשאה לתיקייה תקפה למשך ריצת התוסף.

```javascript
const res = await Otzaria.call('ui.pickFolder', {
  title: 'בחר תיקיית יעד'  // אופציונלי
});
if (res.success && res.data.path) {
  const folder = res.data.path;
  // אפשר כעת להוריד/לחלץ/למחוק בתוך folder
}
```

---

## fs.* - פעולות קבצים

> פעולות הקבצים מותרות אך ורק בתוך תיקייה שהמשתמש בחר דרך
> [`ui.pickFolder`](#uipickfolder). נתיב מחוץ לתיקייה מאושרת מוחזר עם
> `error.forbidden`. אין צורך בהרשאת manifest ייעודית — הסכמת המשתמש
> בבחירת התיקייה היא גבול האבטחה.

### `fs.extractZip`
**הרשאה:** (אין — מגודר ע"י `ui.pickFolder`)

חילוץ קובץ ZIP אל תיקיית יעד. גם `zipPath` וגם `destFolder` חייבים להיות
בתוך תיקייה מאושרת. תיקיית היעד נוצרת אם אינה קיימת.

```javascript
await Otzaria.call('fs.extractZip', {
  zipPath: folder + '/books.zip',
  destFolder: folder + '/אוצריא'
});
// true
```

### `fs.deleteFile`
**הרשאה:** (אין — מגודר ע"י `ui.pickFolder`)

מחיקת קובץ. ה-`path` חייב להיות בתוך תיקייה מאושרת. הפעולה idempotent —
אם הקובץ אינו קיים היא מצליחה בשקט. מחיקת תיקייה אינה נתמכת (מחזירה
`error.invalid_params`).

```javascript
await Otzaria.call('fs.deleteFile', {
  path: folder + '/books.zip'
});
// true
```

שגיאות אפשריות: `error.forbidden` (נתיב מחוץ לתיקייה מאושרת),
`error.invalid_params` (פרמטר חסר / הנתיב הוא תיקייה),
`error.not_found` (קובץ ה-ZIP לחילוץ אינו קיים), `error.internal`.

---

## fs.* - קבצים אישיים של המשתמש

> פעולות אלו מאפשרות לתוסף לפתוח קובץ אישי (PDF / טקסט וכו') שהמשתמש בוחר
> במפורש בדיאלוג. הגישה מוגבלת לקובץ שנבחר — לא לנתיב חופשי בדיסק — ודורשת
> את הרשאת ה-manifest `fs.user_files.read`.
>
> **PDF/בינארי גדול:** הקובץ מוגש דרך שרת `localhost` פנימי (`http://127.0.0.1`)
> עם תמיכת `Range`. הבייטים **אינם** עוברים דרך גשר ה-JS. מציבים את ה-`url`
> שמתקבל ב-`<iframe>`/PDF.js (או `fetch`). שימו לב: רינדור PDF ב-`<iframe>`
> מובנה עובד רק ב-Windows/macOS — לתאימות מלאה (Android/Linux) יש לרנדר עם
> PDF.js, ש-`fetch` מה-`url` בעצמו.

### `fs.pickUserFile`
**הרשאה:** `fs.user_files.read`

פותח דיאלוג בחירת קובץ, רושם את הקובץ הנבחר ומחזיר `token` ו-`url` לטעינה.
ה-`token` הוא מזהה אטום שכדאי לשמור ב-`storage` — בטעינה מחדש בונים ממנו URL
טרי דרך [`fs.resolveFileUrl`](#fsresolvefileurl). פרמטר `extensions` אופציונלי
מסנן את סוגי הקבצים בדיאלוג.

```javascript
const res = await Otzaria.call('fs.pickUserFile', {
  title: 'בחר קובץ PDF',
  extensions: ['pdf'] // אופציונלי
});
// res.data = { cancelled: false, token, url, name, size }  — או { cancelled: true }
if (res.success && !res.data.cancelled) {
  await Otzaria.call('storage.set', { key: 'lastFile', value: res.data.token });
  document.querySelector('iframe').src = res.data.url;
}
```

### `fs.resolveFileUrl`
**הרשאה:** `fs.user_files.read`

בונה URL טרי לקובץ שכבר אושר, לפי ה-`token` שנשמר. נצרך אחרי טעינה מחדש של
התוסף (הפורט של השרת משתנה בכל הפעלה). מחזיר `error.not_found` אם ה-`token`
לא מוכר או שהקובץ נמחק.

```javascript
const { data: token } = await Otzaria.call('storage.get', { key: 'lastFile' });
const { data } = await Otzaria.call('fs.resolveFileUrl', { token });
// data = { token, url, name, size }
```

### `fs.readTextFile`
**הרשאה:** `fs.user_files.read`

מחזיר את תוכן הקובץ המאושר כמחרוזת (לקבצי טקסט קטנים, עד 10MB). לקבצים
גדולים יש להשתמש ב-`url` מ-`pickUserFile`/`resolveFileUrl`.

```javascript
const { data } = await Otzaria.call('fs.readTextFile', { token });
// "תוכן הקובץ..."
```

### `fs.revokeFile`
**הרשאה:** `fs.user_files.read`

מבטל את האישור ל-`token` ומסיר אותו מהאחסון. פעולה idempotent.

```javascript
await Otzaria.call('fs.revokeFile', { token });
// { success: true, data: true }
```

שגיאות אפשריות: `error.not_found` (token לא מוכר / קובץ נמחק),
`error.invalid_params` (token חסר), `error.too_large` (קובץ טקסט מעל 10MB),
`error.internal`.

---

## feedback.* - משוב ומיילים

### `feedback.sendEmail`
**הרשאה:** `feedback.send_email`

שליחת משוב או דיווח למייל מותאם אישית (לא למייל דיווח השגיאות הראשי).

```javascript
const { data } = await Otzaria.call('feedback.sendEmail', {
  to: 'custom@example.com',
  subject: 'נושא המייל',
  body: 'תוכן המייל',
  includeSystemInfo: true  // אופציונלי, ברירת מחדל: false
});
// true
```

**פרמטרים:**
- `to` (חובה) - כתובת המייל של הנמען
- `subject` (חובה) - נושא המייל
- `body` (חובה) - תוכן המייל
- `includeSystemInfo` (אופציונלי) - אם `true`, מוסיף מידע מערכת (גרסה, פלטפורמה, שם התוסף) בסוף המייל

**שימושים אפשריים:**
- תוסף לשאלות ותשובות שרוצה לשלוח שאלות למייל ספציפי
- תוסף לסקרים/משוב שרוצה לאסוף תגובות
- תוסף לבקשות תכונות או דיווח באגים למפתח התוסף

---

## history.* - היסטוריית קריאה

### `history.list`
**הרשאה:** `history.read`

קבלת רשימת הספרים שנקראו לאחרונה (ללא חיפושים).

```javascript
const { data } = await Otzaria.call('history.list', {
  limit: 50  // אופציונלי, ברירת מחדל: 50
});
// [
//   { bookId: "בראשית", title: "בראשית", ref: "פרק א", index: 0, workspaceName: "לימוד יומי" },
//   { bookId: "שמות", title: "שמות", ref: "פרק ב", index: 42, workspaceName: null },
//   ...
// ]
```

### `history.listSearches`
**הרשאה:** `history.read`

קבלת רשימת החיפושים האחרונים (ללא ספרים).

```javascript
const { data } = await Otzaria.call('history.listSearches', {
  limit: 50  // אופציונלי, ברירת מחדל: 50
});
// [
//   { query: "ואהבת לרעך כמוך", ref: "...", workspaceName: "לימוד יומי" },
//   ...
// ]
```

### `history.clear`
**הרשאה:** `history.write`

ניקוי כל ההיסטוריה (ספרים וחיפושים).

```javascript
const { data } = await Otzaria.call('history.clear');
// true
```

### `history.remove`
**הרשאה:** `history.write`

מחיקת פריט ספציפי מההיסטוריה.

```javascript
const { data } = await Otzaria.call('history.remove', {
  bookId: 'בראשית',
  index: 0  // אופציונלי, אם לא מצוין - מוחק את הפריט הראשון עם bookId זה
});
// true או false
```

**שימושים אפשריים:**
- תוסף לניתוח דפוסי קריאה
- תוסף להמלצות על ספרים
- תוסף לסטטיסטיקות לימוד
- תוסף לניהול היסטוריה מתקדם

---

## notifications.* - התראות

### `notifications.showInApp`
**הרשאה:** `notifications.send`

הצגת התראה בתוך האפליקציה (UiSnack).

```javascript
const { data } = await Otzaria.call('notifications.showInApp', {
  message: 'הפעולה בוצעה בהצלחה',
  type: 'info'  // 'info' | 'success' | 'error', ברירת מחדל: 'info'
});
// true
```

**סוגי התראות:**
- `info` - הודעה רגילה (כחול)
- `success` - הודעת הצלחה (ירוק)
- `error` - הודעת שגיאה (אדום)

### `notifications.sendSystem`
**הרשאה:** `notifications.system`

שליחת התראה מיידית למערכת ההפעלה.

```javascript
const { data } = await Otzaria.call('notifications.sendSystem', {
  title: 'כותרת ההתראה',
  body: 'תוכן ההתראה',
  id: 12345  // אופציונלי, מזהה ייחודי להתראה
});
// { id: 12345 }
```

**הערות:**
- אם לא מצוין `id`, המערכת תיצור מזהה אוטומטי
- ההתראה תופיע במרכז ההתראות של מערכת ההפעלה
- דורש הרשאות מערכת (המשתמש יתבקש לאשר בפעם הראשונה)

### `notifications.scheduleSystem`
**הרשאה:** `notifications.system`

תזמון התראה למערכת ההפעלה לזמן עתידי.

```javascript
const { data } = await Otzaria.call('notifications.scheduleSystem', {
  title: 'תזכורת',
  body: 'זמן התפילה',
  scheduledTime: '2026-04-10T10:00:00Z',  // ISO 8601 format
  id: 12346  // אופציונלי
});
// { id: 12346 }
```

**הערות:**
- `scheduledTime` חייב להיות בפורמט ISO 8601
- הזמן חייב להיות בעתיד
- ההתראה תישלח אוטומטית בזמן שנקבע

### `notifications.cancel`
**הרשאה:** `notifications.system`

ביטול התראה ספציפית.

```javascript
const { data } = await Otzaria.call('notifications.cancel', {
  id: 12345
});
// true
```

### `notifications.cancelAll`
**הרשאה:** `notifications.system`

ביטול כל ההתראות של התוסף.

```javascript
const { data } = await Otzaria.call('notifications.cancelAll');
// true
```

### `notifications.checkPermissions`
**הרשאה:** `notifications.system`

בדיקת מצב הרשאות ההתראות.

```javascript
const { data } = await Otzaria.call('notifications.checkPermissions');
// { granted: true, initialized: true }
```

**שדות בתשובה:**
- `granted` - האם המשתמש אישר הרשאות התראות
- `initialized` - האם שירות ההתראות מאותחל

### `notifications.requestPermissions`
**הרשאה:** `notifications.system`

בקשת הרשאות התראות מהמשתמש.

```javascript
const { data } = await Otzaria.call('notifications.requestPermissions');
// { granted: true }
```

**הערה:** פעולה זו תציג דיאלוג למשתמש בפעם הראשונה.

**שימושים אפשריים:**
- תוסף לתזכורות לימוד
- תוסף לזמני תפילה
- תוסף לאירועי לוח שנה
- תוסף להתראות על עדכונים

---

## storage.* - אחסון נתונים

### `storage.get`
**הרשאה:** `plugin.storage.read`

קריאת ערך שמור.

```javascript
const { data } = await Otzaria.call('storage.get', {
  key: 'myData'
});
// כל ערך JSON או null
```

### `storage.set`
**הרשאה:** `plugin.storage.write`

שמירת ערך.

```javascript
await Otzaria.call('storage.set', {
  key: 'myData',
  value: { count: 42, name: 'test' }
});
```

### `storage.remove`
**הרשאה:** `plugin.storage.write`

מחיקת ערך.

```javascript
await Otzaria.call('storage.remove', {
  key: 'myData'
});
```

### `storage.list`
**הרשאה:** `plugin.storage.read`

רשימת כל המפתחות השמורים.

```javascript
const { data } = await Otzaria.call('storage.list');
// ["myData", "settings", "cache"]
```

---

## settings.* - הגדרות אפליקציה

### `settings.get`
**הרשאה:** `settings.read`

קריאת הגדרה בודדת (רק מפתחות מורשים).

```javascript
const { data } = await Otzaria.call('settings.get', {
  key: 'key-font-size'
});
// 25
```

### `settings.getMany`
**הרשאה:** `settings.read`

קריאת מספר הגדרות בבת אחת.

```javascript
const { data } = await Otzaria.call('settings.getMany', {
  keys: ['key-font-size', 'key-font-family']
});
// { "key-font-size": 25, "key-font-family": "Frank Ruhl Libre" }
```

**מפתחות מורשים לקריאה:**
- `key-dark-mode`
- `key-follow-system-theme`
- `key-swatch-color`, `key-dark-swatch-color`
- `key-font-size`, `key-font-family`
- `key-commentators-font-family`, `key-commentators-font-size`
- `key-line-height`
- `key-selected-city`
- `key-calendar-type`
- `key-show-teamim`
- `key-default-nikud`
- `key-remove-nikud-tanach`
- `key-replace-holy-names`
- `key-library-view-mode`
- `key-align-tabs-to-right`
- `key-copy-with-headers`, `key-copy-header-format`

---

## calendar.* - לוח שנה

### `calendar.getSelectedDate`
**הרשאה:** `calendar.read`

קבלת התאריך הנבחר בלוח השנה.

```javascript
const { data } = await Otzaria.call('calendar.getSelectedDate');
// "2026-04-08T00:00:00.000Z"
```

### `calendar.getDailyTimes`
**הרשאה:** `calendar.read`

קבלת זמנים הלכתיים ליום.

```javascript
const { data } = await Otzaria.call('calendar.getDailyTimes');
// { sunrise: "06:23", sunset: "19:11", tzet: "19:45", ... }
```

### `calendar.getHalachicTimes`
**הרשאה:** `calendar.read`

קבלת זמנים הלכתיים מלאים ליום (זהה ל-`getDailyTimes`).

```javascript
const { data } = await Otzaria.call('calendar.getHalachicTimes');
// { sunrise: "06:23", sunset: "19:11", tzet: "19:45", ... }
```

### `calendar.getJewishDate`
**הרשאה:** `calendar.read`

המרת תאריך לועזי לעברי.

```javascript
const { data } = await Otzaria.call('calendar.getJewishDate');
// {
//   year: 5786,
//   month: 1,
//   day: 10,
//   gregorian: "2026-04-08T00:00:00.000Z",
//   monthName: "ניסן",
//   isLeapYear: false,
//   isShabbat: false,
//   holidays: [
//     { text: "שביעי של פסח", kind: "yomTov" }
//   ]
// }
```

שדות נוספים בתשובה:

- `monthName` - שם החודש בעברית.
- `isLeapYear` - האם השנה העברית היא שנה מעוברת.
- `isShabbat` - האם התאריך חל בשבת.
- `holidays` - רשימת חגים/ימים מיוחדים לתאריך, בפורמט `{ text, kind }`.

ערכי `kind` אפשריים:

- `yomTov`
- `roshChodesh`
- `taanit`
- `special`

### `calendar.getEvents`
**הרשאה:** `calendar.read`

קבלת אירועים לתאריך מסוים.

```javascript
const { data } = await Otzaria.call('calendar.getEvents', {
  date: '2026-04-08'  // אופציונלי, ברירת מחדל: התאריך הנבחר
});
// [{ id: "1", title: "פסח", date: "2026-04-08T00:00:00Z", description: "..." }, ...]
```

---

## publishedData.* - פרסום נתונים

### `publishedData.upsert`
**הרשאה:** `published_data.write`

פרסום או עדכון רשומה.

```javascript
await Otzaria.call('publishedData.upsert', {
  type: 'calendar.event',  // 'calendar.event' | 'saved.query' | 'note.draft' | 'reference.link' | 'tool.badge'
  scope: 'global',          // 'global' | 'workspace:<id>' | 'book:<bookId>'
  key: 'myPlugin:event1',
  payload: {
    title: 'שקיעה',
    startsAt: '2026-04-08T19:11:00+03:00',
    source: 'התוסף שלי',
    importance: 'high'
  }
});
```

### `publishedData.remove`
**הרשאה:** `published_data.write`

הסרת רשומה שפורסמה.

```javascript
await Otzaria.call('publishedData.remove', {
  type: 'calendar.event',
  scope: 'global',
  key: 'myPlugin:event1'
});
```

### `publishedData.listOwn`
**הרשאה:** `published_data.write`

רשימת כל הרשומות שפורסמו על ידי התוסף.

```javascript
const { data } = await Otzaria.call('publishedData.listOwn');
// [{ type: "calendar.event", scope: "global", key: "myPlugin:event1", payload: {...} }, ...]
```

---

## database.* - גישה למסד נתונים SQLite

**הרשאה נדרשת:** `database.read`

API זה מאפשר לתוסף לקרוא נתונים ממסדי נתונים SQLite מקומיים שהאפליקציה רשמה ואישרה.  
התוסף **אינו** יכול לשלוח SQL חופשי — הוא שולח בקשה דקלרטיבית, והמארח מתרגם אותה ל-SQL פרמטרי לאחר אימות מול policy.

**הצהרה במניפסט:**

```json
{
  "permissions": ["database.read"],
  "contributes": {
    "databaseSources": [
      {
        "id": "talmud_synopsis",
        "label": "עדי נוסח בבלי",
        "required": true
      }
    ]
  }
}
```

---

### `database.listSources`

מחזיר את המקורות שהוצהרו במניפסט, יחד עם מצב הזמינות שלהם.

```javascript
const { data } = await Otzaria.call('database.listSources');
// {
//   sources: [
//     { id: "talmud_synopsis", label: "עדי נוסח בבלי", available: true }
//   ]
// }
```

---

### `database.describeSource`

מחזיר את ה-schema החשוף לתוסף — רק הטבלאות והעמודות שמותרות על פי ה-policy.

```javascript
const { data } = await Otzaria.call('database.describeSource', {
  sourceId: 'talmud_synopsis'
});
// {
//   source: { id: "talmud_synopsis", label: "עדי נוסח בבלי" },
//   schema: {
//     tables: [
//       { name: "line_alignments", columns: ["id", "page_id", "reference", "sequence_number"] },
//       { name: "line_readings",   columns: ["alignment_id", "id", "text", "witness_id"] },
//       ...
//     ]
//   },
//   limits: { maxLimit: 5000, maxBatchQueries: 5 }
// }
```

---

### `database.query`

ביצוע שאילתה דקלרטיבית.

**פרמטרים:**

| שדה | סוג | חובה | תיאור |
|-----|-----|------|--------|
| `sourceId` | `string` | ✓ | מזהה המקור |
| `from` | `{ table, alias? }` | ✓ | טבלת הבסיס |
| `select` | `SelectItem[]` | ✓ | עמודות לבחירה |
| `joins` | `Join[]` | — | חיבורי טבלאות |
| `where` | `WhereCondition` | — | תנאי סינון |
| `orderBy` | `OrderBy[]` | — | מיון |
| `limit` | `number` | — | מקסימום שורות (ברירת מחדל: maxLimit) |
| `offset` | `number` | — | דילוג שורות |
| `rowFormat` | `'array' \| 'object'` | — | פורמט תשובה (ברירת מחדל: `'array'`) |

**דוגמה — קריאת עדי נוסח לדף:**

```javascript
const { data } = await Otzaria.call('database.query', {
  sourceId: 'talmud_synopsis',
  from: { table: 'tractates', alias: 't' },
  select: [
    { expr: 'la.id',              as: 'alignment_id' },
    { expr: 'la.sequence_number', as: 'sequence_number' },
    { expr: 'la.reference',       as: 'reference' },
    { expr: 'w.name',             as: 'witness_name' },
    { expr: 'lr.text',            as: 'text' }
  ],
  joins: [
    {
      type: 'inner', table: 'pages', alias: 'p',
      on: [{ left: 'p.tractate_id', op: '=', right: 't.id' }]
    },
    {
      type: 'inner', table: 'line_alignments', alias: 'la',
      on: [{ left: 'la.page_id', op: '=', right: 'p.id' }]
    },
    {
      type: 'inner', table: 'line_readings', alias: 'lr',
      on: [{ left: 'lr.alignment_id', op: '=', right: 'la.id' }]
    },
    {
      type: 'inner', table: 'witnesses', alias: 'w',
      on: [{ left: 'w.id', op: '=', right: 'lr.witness_id' }]
    }
  ],
  where: {
    op: 'and',
    conditions: [
      { op: '=', left: 't.name', value: 'מסכת ברכות' },
      { op: '=', left: 'p.name', value: 'ב' }
    ]
  },
  orderBy: [
    { expr: 'la.sequence_number', direction: 'asc' },
    { expr: 'w.name',             direction: 'asc' }
  ],
  limit: 2000,
  rowFormat: 'array'
});
// {
//   meta: { sourceId: "talmud_synopsis", rowCount: 240, limit: 2000, offset: 0, hasMore: false, elapsedMs: 12 },
//   columns: [
//     { name: "alignment_id" }, { name: "sequence_number" },
//     { name: "reference" }, { name: "witness_name" }, { name: "text" }
//   ],
//   rows: [
//     [1, 1, "ע\"א 1 - 14", "כ\"י מינכן 95", "..."],
//     ...
//   ]
// }
```

**פורמט `object`:**

```javascript
const { data } = await Otzaria.call('database.query', {
  ...spec,
  rowFormat: 'object'
});
// rows: [
//   { alignment_id: 1, sequence_number: 1, reference: "ע\"א 1 - 14", ... },
//   ...
// ]
```

**אופרטורי `where` תמיכה:**

| אופרטור | דוגמה |
|---------|-------|
| `=` `!=` `>` `>=` `<` `<=` | `{ op: '=', left: 'p.name', value: 'ב' }` |
| `like` | `{ op: 'like', left: 'w.name', value: '%כ"י%' }` |
| `in` | `{ op: 'in', left: 'p.id', value: [1, 2, 3] }` |
| `between` | `{ op: 'between', left: 'la.sequence_number', value: [1, 50] }` |
| `isNull` / `isNotNull` | `{ op: 'isNull', left: 'lr.text' }` |
| `and` / `or` | `{ op: 'and', conditions: [...] }` |

---

### `database.batchQuery`

ביצוע מספר שאילתות ב-RPC roundtrip אחד — יעיל כשיש תלויות בין שאילתות שצריך לפתור ברצף.

```javascript
const { data } = await Otzaria.call('database.batchQuery', {
  queries: [
    {
      sourceId: 'talmud_synopsis',
      from: { table: 'tractates', alias: 't' },
      select: [{ expr: 't.id', as: 'id' }],
      where: { op: '=', left: 't.name', value: 'מסכת ברכות' },
      limit: 1
    },
    {
      sourceId: 'talmud_synopsis',
      from: { table: 'witnesses', alias: 'w' },
      select: [
        { expr: 'w.id',   as: 'id' },
        { expr: 'w.name', as: 'name' }
      ],
      limit: 100
    }
  ]
});
// { results: [ <תוצאה 1>, <תוצאה 2> ] }
```

**הגבלות:**
- מקסימום 5 שאילתות ל-batch (ניתן לבדוק ב-`database.describeSource`)
- כל שאילתה עוברת ולידציה נפרדת מול ה-policy
- אין תמיכה ב-references בין תוצאות (כל שאילתה עצמאית)

---

**קודי שגיאה:**

| קוד | משמעות |
|-----|--------|
| `permission_denied` | חסרה הרשאת `database.read` (קוד גנרי של ה-RPC bridge) |
| `database.source_not_found` | המקור לא הוצהר במניפסט |
| `database.source_unavailable` | קובץ ה-DB לא קיים או לא רשום |
| `database.table_not_allowed` | טבלה לא מורשית |
| `database.column_not_allowed` | עמודה לא מורשית |
| `database.join_not_allowed` | join לא מורשה על פי ה-policy |
| `database.query_too_large` | חריגה ממגבלת limit, joins, columns, או batch |
| `database.invalid_spec` | בקשה לא תקינה (שדה חסר, ערך לא חוקי, alias כפול) |
| `error.timeout` | השאילתה חרגה מ-30 שניות (מגבלת ה-RPC הכללית) |

> **הערה על timeout:** בגרסה נוכחית, שאילתות ש-sqlite3 מריץ באופן סינכרוני אינן ניתנות להפרעה. timeout נאכף על ידי מגבלת ה-RPC הכללית (30 שניות) שמחזירה `error.timeout`.

---

## אירועים (Events)

ניתן להאזין לאירועים מהאפליקציה:

```javascript
Otzaria.on('event.name', (data) => {
  console.log('אירוע התרחש:', data);
});
```

### אירועים זמינים:

**הרשאה נדרשת:** כל אירוע מצריך הרשאה מתאימה מסוג `events.subscribe:<event_name>`

- `plugin.boot` - נורה פעם אחת בטעינת התוסף (ללא הרשאה). ה-payload כולל `app.runMode: 'foreground' | 'background'` — ראה §ריצת רקע.
- `plugin.ready` - נורה אחרי boot (ללא הרשאה)
- `theme.changed` - שינוי בערכת הצבעים (הרשאה: `events.subscribe:theme.changed`)
- `navigation.changed` - מעבר בין מסכים ראשיים בלבד (library ↔ reading ↔ more ↔ settings) (הרשאה: `events.subscribe:navigation.changed`)
- `reader.current_book_changed` - שינוי הספר/טאב הפעיל בלבד (הרשאה: `events.subscribe:reader.current_book_changed`)
- `reader.current_ref_changed` - שינוי מיקום הקריאה הנוכחי (דף, פרק, סעיף) - **זה האירוע למעקב אחרי מיקום!** (הרשאה: `events.subscribe:reader.current_ref_changed`)
- `calendar.date_changed` - שינוי התאריך בלוח השנה (הרשאה: `events.subscribe:calendar.date_changed`)
- `workspace.changed` - שינוי סביבת העבודה (הרשאה: `events.subscribe:workspace.changed`)
- `settings.changed` - שינוי הגדרה (הרשאה: `events.subscribe:settings.changed`)
- `plugin.permissions_changed` - שינוי הרשאות (מחזיר `{ permissions: string[] }` - רשימת כל ההרשאות המאושרות) (הרשאה: `events.subscribe:plugin.permissions_changed`)

### הבדלים חשובים בין אירועי הקורא:

**חשוב להבין את ההבדל:**

- **`navigation.changed`** - נורה רק כאשר המשתמש עובר בין מסכים ראשיים (library → reading, reading → settings וכו'). **לא** נורה כאשר המשתמש מדפדף בתוך ספר.

- **`reader.current_book_changed`** - נורה כאשר הספר או הטאב הפעיל משתנה (פתיחת ספר חדש, החלפת טאב). **לא** נורה כאשר המשתמש גולל או עובר לדף אחר באותו ספר.

- **`reader.current_ref_changed`** - נורה כאשר **מיקום הקריאה הנוכחי משתנה**, כולל:
  - גלילה לפרק אחר באותו ספר
  - מעבר לדף אחר ב-PDF
  - פתיחת ספר חדש (כי גם המיקום השתנה)
  - החלפת טאב (אם המיקום החדש שונה)

**דוגמה:** אם המשתמש קורא את מסכת ברכות ועובר מדף ג' לדף ד':
- `navigation.changed` - לא יורה (נשאר במסך reading)
- `reader.current_book_changed` - לא יורה (נשאר באותו ספר)
- `reader.current_ref_changed` - **כן יורה** (המיקום השתנה)

**לכן:** אם אתם רוצים לעקוב אחרי המיקום של המשתמש בזמן קריאה, השתמשו ב-`reader.current_ref_changed`!

### דוגמת שימוש ב-`reader.current_ref_changed`:

```javascript
// מעקב אחרי מיקום הקריאה
Otzaria.on('reader.current_ref_changed', (location) => {
  console.log('מיקום חדש:', {
    book: location.currentBook,
    index: location.currentIndex,
    ref: location.currentRef  // למשל: "ברכות, דף ד" או "בראשית פרק ב"
  });
  
  // עדכון UI של התוסף
  updateFollowDisplay(location);
});
```

---

## דוגמה מלאה

```javascript
// האזנה לטעינת התוסף
Otzaria.on('plugin.boot', async (payload) => {
  console.log('התוסף נטען:', payload.plugin.id);
  
  // החלת ערכת צבעים
  const theme = payload.theme;
  document.body.style.background = theme.colorScheme.surface;
  document.body.style.color = theme.colorScheme.onSurface;
  
  // קבלת מידע על המשתמש
  const { data: emailData } = await Otzaria.call('app.getUserEmail');
  console.log('מייל משתמש:', emailData.email);
  
  // חיפוש ספרים
  const { data: books } = await Otzaria.call('library.findBooks', {
    query: 'תנ"ך',
    limit: 5
  });
  
  books.forEach(book => {
    console.log(book.title);
  });
  
  // בדיקת הרשאות התראות
  const { data: perms } = await Otzaria.call('notifications.checkPermissions');
  if (!perms.granted) {
    await Otzaria.call('notifications.requestPermissions');
  }
  
  // שליחת התראה בתוך האפליקציה
  await Otzaria.call('notifications.showInApp', {
    message: 'התוסף נטען בהצלחה',
    type: 'success'
  });
});

// האזנה לשינוי ערכת צבעים
Otzaria.on('theme.changed', (theme) => {
  document.body.style.background = theme.colorScheme.surface;
});

// האזנה לשינוי ספר
Otzaria.on('reader.current_book_changed', async (data) => {
  console.log('ספר חדש נפתח:', data.book);
  
  // קבלת היסטוריה
  const { data: history } = await Otzaria.call('history.list', { limit: 10 });
  console.log('ספרים אחרונים:', history);
});

// דוגמה לשליחת משוב
async function sendFeedback(message) {
  try {
    await Otzaria.call('feedback.sendEmail', {
      to: 'feedback@example.com',
      subject: 'משוב על התוסף',
      body: message,
      includeSystemInfo: true
    });
    
    await Otzaria.call('notifications.showInApp', {
      message: 'המשוב נשלח בהצלחה',
      type: 'success'
    });
  } catch (error) {
    await Otzaria.call('notifications.showInApp', {
      message: 'שגיאה בשליחת המשוב',
      type: 'error'
    });
  }
}

// דוגמה לתזמון התראה
async function scheduleReminder(title, body, dateTime) {
  const { data } = await Otzaria.call('notifications.scheduleSystem', {
    title: title,
    body: body,
    scheduledTime: dateTime.toISOString()
  });
  
  console.log('התראה תוזמנה עם ID:', data.id);
  
  // שמירת ה-ID לביטול עתידי
  await Otzaria.call('storage.set', {
    key: 'reminder_id',
    value: data.id
  });
}
```

---

## ריצת רקע (app.run\_on\_startup)

הרשאה `app.run_on_startup` מאפשרת לתוסף להיטען ולרוץ ברקע **מיד עם עליית אוצריא**, לפני שהמשתמש נכנס למסך "כלים".

### הצהרה במניפסט

```json
{
  "permissions": ["app.run_on_startup", "notifications.send"]
}
```

### זיהוי מצב ב-plugin.boot

```javascript
Otzaria.on('plugin.boot', async (payload) => {
  // payload.app.runMode === 'background'  → רץ ברקע (עם app.run_on_startup)
  // payload.app.runMode === 'foreground' → רץ בלשונית הנראית

  if (payload.app.runMode === 'background'
      && payload.permissions.includes('app.run_on_startup')) {
    // קוד שירוץ פעם אחת בעת עליית האפליקציה
    await Otzaria.call('notifications.showInApp', {
      message: 'התוסף נטען בהצלחה עם עליית אוצריא',
      type: 'success'
    });
  }
});
```

> ⚠️ **חשוב:** בלי בדיקת `runMode`, הקוד ירוץ **פעמיים** — פעם מה-instance הרקע ופעם נוספת כשהמשתמש נכנס ללשונית.

### התנהגות ברירת מחדל

- **ברירת מחדל: כבויה** — שונה מכל שאר ההרשאות שמופעלות כברירת מחדל
- בעת ההתקנה מוצג **באנר כתום בולט** שמסביר שהתוסף מבקש לרוץ ברקע
- המשתמש יכול להפעיל/לכבות את ההרשאה בכל עת מהגדרות התוסף

### קובץ כניסה ייעודי לרקע (`contributes.background.entrypoint`)

ברירת המחדל היא שהרקע טוען את אותו `entrypoint` של הלשונית הנראית — דף ה-UI המלא. ברקע אין UI גלוי, ולכן מומלץ להצהיר על קובץ כניסה קליל ונפרד שמכיל רק לוגיקת headless (רישומים, מאזיני אירועים), בלי framework/CSS/גופנים:

```json
{
  "entrypoint": "dist/index.html",
  "permissions": ["app.run_on_startup", "reader.context_menu"],
  "contributes": {
    "background": { "entrypoint": "dist/background.html" }
  }
}
```

- אם השדה לא מוצהר — הרקע נופל ל-`entrypoint` הרגיל (תאימות לאחור).
- הקובץ חייב להתקיים ולהיכלל באריזה; אחרת הוולידציה/אריזה נכשלת עם שגיאה ברורה.

---

## רשימת הרשאות מלאה

הרשאות שתוסף יכול לבקש ב-`manifest.json`:

```json
{
  "permissions": [
    "app.info.read",
    "app.user_email.read",
    "library.books.read",
    "library.content.read",
    "search.fulltext.read",
    "reader.open",
    "navigation.write",
    "notes.read",
    "notes.write",
    "calendar.read",
    "settings.read",
    "ui.feedback",
    "plugin.storage.read",
    "plugin.storage.write",
    "published_data.write",
    "network.access",
    "network.localhost",
    "feedback.send_email",
    "history.read",
    "history.write",
    "notifications.send",
    "notifications.system",
    "app.run_on_startup",
    "database.read",
    "events.subscribe:navigation.changed",
    "events.subscribe:reader.current_book_changed",
    "events.subscribe:reader.current_ref_changed",
    "events.subscribe:theme.changed",
    "events.subscribe:settings.changed",
    "events.subscribe:calendar.date_changed",
    "events.subscribe:workspace.changed",
    "events.subscribe:plugin.permissions_changed"
  ]
}
```

---

## ⚠️ הרשאת `network.access` — דרישה מיוחדת: אישור מאוצריא

הצהרה על ההרשאה `network.access` ב-`manifest.json` **אינה מספיקה** כדי שתוסף יוכל לגשת לרשת. בפועל, ה-URL חייב לעבור שתי בדיקות מצטברות:

1. להופיע ב-`network.allowlist` של התוסף עצמו.
2. להופיע ברשימת ההיתר הרשמית של אוצריא.

רשימת ההיתר הרשמית מנוהלת בקובץ `plugin_network_allowlist.txt` בענף הייעודי **`plugin-network-allowlist`** של הריפו `Otzaria/otzaria`:

<https://github.com/Otzaria/otzaria/blob/plugin-network-allowlist/plugin_network_allowlist.txt>

אוצריא מושכת את הקובץ הזה בזמן ריצה וטוענת אישורים ממנו **לזיכרון בלבד** עד סגירת האפליקציה. עריכת הקובץ בענף נכנסת לתוקף **מיד אצל כל המשתמשים, בכל גרסה מותקנת** — אין צורך ב-release חדש של אוצריא.

### תהליך הוספת URL חדש

כל תוסף שזקוק לגישה ל-URL כלשהו ברשת **חייב**:

1. להצהיר על ה-URL ב-`manifest.json` תחת `network.allowlist`.
2. לפנות למתחזקי אוצריא (או לפתוח Pull Request לענף `plugin-network-allowlist`) כדי להוסיף את ה-URL לקובץ הנ"ל.

ללא שני השלבים יחד — ה-URL ייחסם ב-runtime עם `403 Forbidden`, גם אם המשתמש אישר את הרשאת `network.access`.

### שירותים מקומיים (localhost) — הרשאת `network.localhost`

גישה לשירות מקומי על מחשב המשתמש (loopback: `localhost` / `127.0.0.1` / `::1`) — למשל מודל שפה מקומי כמו **Ollama** או **LM Studio** — מטופלת בנפרד:

- ההרשאה הנדרשת היא **`network.localhost`** (לא `network.access`). השתיים נפרדות: `network.localhost` אינה מתירה גישה לאינטרנט, ו-`network.access` אינה מתירה גישה ל-localhost.
- היעד חייב להופיע ב-`network.allowlist` של התוסף, אבל **אין צורך ב-PR לאוצריא** — localhost אינו נכלל ב-allowlist הגלובלי.
- הצהרת host חשוף (`"127.0.0.1"` / `"localhost"`) מתירה כל פורט על אותו host; הצהרת URL מלא (`"http://127.0.0.1:11434"`) נועלת לפורט שהוצהר.
- כמו כל גישת רשת — חובה גם `network.enabled: true` ב-manifest. הקריאות חייבות לעבור דרך `network.fetch` (לא `fetch()` ישיר מה-WebView, שנחסם ב-CORS מול שרת מקומי שדוחה `Origin: null`).

```json
"permissions": ["network.localhost"],
"network": { "enabled": true, "allowlist": ["127.0.0.1", "localhost"] }
```

### חובה: כתובות מדויקות בלבד

חובה לכלול **כתובות URL מדויקות ומלאות**, ולא דומיינים גנריים:

✅ **נכון** — כתובת מדויקת לנתיב הספציפי הנדרש:
```text
https://api.example.com/v1/specific-endpoint
https://github.com/Otzaria/otzaria-library
https://raw.githubusercontent.com/MyOrg/my-plugin-data/main
```

❌ **אסור** — כתובות גנריות שמתירות גישה רחבה מדי:
```text
https://github.com          # ❌ פותח את כל גיטהאב
https://api.example.com     # ❌ פותח את כל ה-API
https://googleapis.com      # ❌ פותח את כל שירותי גוגל
```

### איך ההתאמה עובדת

ההתאמה היא **תואמת קידומת** — URL מאושר אם הוא:
- שווה בדיוק לקידומת ברשימה, **או**
- מתחיל בקידומת ואחריה אחד מ-`/`, `?`, `#`.

לדוגמה, אם ברשימה מופיע `https://github.com/Otzaria/otzaria-library`:

| URL | מאושר? |
|-----|--------|
| `https://github.com/Otzaria/otzaria-library` | ✅ |
| `https://github.com/Otzaria/otzaria-library/releases/latest` | ✅ |
| `https://github.com/Otzaria/otzaria-library?tab=readme` | ✅ |
| `https://github.com/` | ❌ (נתיב הורה) |
| `https://github.com/Otzaria/another-repo` | ❌ (נתיב אחר תחת אותו דומיין) |
| `https://github.com/Otzaria/otzaria-library2` | ❌ (קידומת תואמת חלקית — לא מסתיימת בגבול נתיב) |

### תוכן ה-PR שיש לפתוח

ב-PR יש לכלול:

1. **את ה-URLs המדויקים** (כולל scheme `https://`, host, ונתיב מלא ככל האפשר).
2. **שם התוסף** ומזההו (`id` מה-manifest).
3. **הסבר קצר** למה התוסף זקוק לכל URL — לאיזה תכלית, ואילו נתונים עוברים.
4. **קישור למאגר התוסף** או ל-manifest שלו, כדי שניתן יהיה לאמת.

> **עיקרון:** רוצה לאשר רק את הנתיבים המינימליים שהתוסף באמת צריך. אם בעתיד נדרש URL נוסף — יש לפתוח PR נוסף.

---

## reader.* — APIs חדשים (v2)

### `reader.addContextMenuItem`

כל תוסף יכול לרשום לכל היותר **שני פריטים עליונים** בתפריט ההקשר.
כל אחד מהם יכול להיות פריט רגיל, תת־תפריט או שורת צבעים. עדכון פריט קיים
באותו `id` אינו צורך מקום נוסף במכסה.
**הרשאה:** `reader.context_menu`

**מבנה התפריט המורחב זמין מגרסה:** `0.9.95`

רישום פריט תפריט הקשר מותאם אישית. הפריט יופיע בתפריט שנפתח בלחיצה ימנית על טקסט בקורא.

```javascript
await Otzaria.call('reader.addContextMenuItem', {
  id: 'my-save-item',       // מזהה ייחודי (חובה)
  label: 'הוסף למראי המקומות שלי',  // טקסט לתצוגה (חובה)
  icon: 'bookmark_24_regular',  // שם אייקון FluentUI System Icons (אופציונלי)
  openPlugin: true,          // לחיצה תפתח את דף התוסף (אופציונלי, מגרסה 0.9.96)
  param: 'save-mode'         // ערך חופשי שיוחזר ב-payload של אירוע הלחיצה (אופציונלי)
});
// true
```

**הערות:**
- אם פריט עם אותו `id` כבר קיים, הוא יוחלף
- הפריטים נשמרים בזיכרון בלבד — יש לרשום מחדש בכל `plugin.boot`
- עם `openPlugin: true`, לחיצה על הפריט מעבירה את המשתמש לדף התוסף, ואירוע
  `reader.context_menu_item_clicked` נמסר לדף — גם אם הוא נטען רק עכשיו
  (האירוע ממתין לסיום ה-boot). כך תוסף ללא instance רקע יכול לקבל את
  הטקסט המסומן ולפעול עליו בדף שלו.
- `type` יכול להיות `item`,‏ `submenu`,‏ `color-row` או `separator`
- תת־תפריט מקבל `children`; שורת צבעים מקבלת `colors` עם `id`,‏ `color`,‏ `label`,‏ `selected` ו־`icon` אופציונלי. כאשר `icon` קיים הוא מוצג במקום גוש הצבע ומתאים לפעולות קומפקטיות כמו מחק
- `contexts` הוא מערך ויכול להכיל את `reader-selection`, את `reader-page-shape-selection`, או את שניהם באותו פריט. ערכי `contexts` חייבים להיות חוקיים וייחודיים. פריט שלא מגדיר `contexts` מופיע בשני ההקשרים (כהתנהגות הרישום המקורית).
- ילד שלא מגדיר `contexts` יורש את המערך של אביו. ילד שמגדיר `contexts` במפורש מוצג רק בהקשרים שלו, ללא איחוד אוטומטי עם הקשר האב; ההקשרים המפורשים חייבים להיות תת־קבוצה של הקשרי האב.
- אפשר להגדיר `onClickEvent` או `onColorClickEvent` כאירוע מותאם אישית

---

### `reader.removeContextMenuItem`
**הרשאה:** `reader.context_menu`

הסרת פריט תפריט הקשר שנרשם קודם.

```javascript
await Otzaria.call('reader.removeContextMenuItem', {
  id: 'my-save-item'
});
// true
```

---

### `reader.updateContextMenuItem`
**הרשאה:** `reader.context_menu`

**זמין מגרסה:** `0.9.95`

מעדכן פריט של התוסף הקורא ללא טעינה מחדש. ניסיון לעדכן פריט שאינו שייך לתוסף או שאינו קיים מחזיר `error.not_found`.

```javascript
await Otzaria.call('reader.updateContextMenuItem', {
  id: 'marker-colors',
  patch: {
    colors: [
      { id: 'yellow', color: '#FFEB3B', label: 'צהוב', selected: true },
      { id: 'green', color: '#4CAF50', label: 'ירוק' }
    ]
  }
});
```

---

### `reader.context_menu_item_clicked` (Event)
**הרשאה:** אין צורך בהרשאה נוספת — נשלח רק לפלאגין שרשם את הפריט

נורה כאשר המשתמש לוחץ על פריט תפריט שהפלאגין רשם.

```javascript
Otzaria.on('reader.context_menu_item_clicked', (data) => {
  console.log('נלחץ פריט:', data.itemId);
  console.log('טקסט מסומן:', data.selectedText);  // '' אם אין
  console.log('מיקום:', data.currentRef);
  console.log('ספר:', data.currentBook);
});
// {
//   itemId: "my-save-item",
//   selectedText: "ויאמר אלהים",
//   currentRef: "בראשית פרק א",
//   currentBook: "בראשית",
//   currentBookId: "בראשית",
//   param: "save-mode"   // הערך שנמסר ב-addContextMenuItem (null אם לא נמסר)
// }
```

---

### `reader.selection_changed` (Event)
**הרשאה:** `events.subscribe:reader.selection_changed`

נורה כאשר המשתמש מסמן טקסט בקורא. **לא** נורה כאשר הסימון מתנקה.

```javascript
Otzaria.on('reader.selection_changed', (data) => {
  console.log('טקסט נבחר:', data.text);
  // הצגת הצעה לשמירה...
});
// {
//   text: "ויאמר אלהים יהי אור",
//   start: 120,
//   end: 140,
//   currentRef: "בראשית פרק א",
//   currentBook: "בראשית",
//   currentBookId: "בראשית",
//   currentIndex: 0
// }
```

---

### `reader.sectionContentChanged` (Event)
**הרשאה:** `events.subscribe:reader.sectionContentChanged`

**זמין מגרסה:** `0.9.95`

נשלח כאשר התוכן של סעיף שכבר נצפה משתנה. התצפית הראשונה משמשת כקו בסיס ואינה שולחת אירוע; snapshots זהים מסוננים אוטומטית.

```javascript
Otzaria.on('reader.sectionContentChanged', (change) => {
  if (change.changeType === 'source-content') {
    // יש לבדוק מחדש עוגנים שנשמרו על ידי התוסף.
  } else {
    // המקור לא השתנה; רק אופן ההצגה השתנה.
  }
});
```

השדה `changeType` הוא `source-content` כאשר נוסח המקור השתנה, או `rendering-only` כאשר רק הטקסט המוצג השתנה. האירוע כולל hashes ישנים וחדשים ואינו כולל את תוכן הספר עצמו.

סיבות אפשריות כוללות `book-updated`,‏ `settings-changed`,‏ `nikud-toggle`,‏ `teamim-toggle`,‏ `font-render-change`,‏ `name-substitution` ו־`layout-change`.

---

### `reader.setHighlight`
**הרשאה:** `reader.highlight`

**עוגן source זמין מגרסה:** `0.9.95` (החתימה לפי שורה נשמרת לתאימות)

יוצר או מחליף הדגשה זמנית על טווח מדויק בטקסט. `ownerPluginId` נקבע בלעדית על־ידי ה־Host ואסור להעבירו ב־payload.

```javascript
await Otzaria.call('reader.setHighlight', {
  highlightId: 'marker-42',
  bookId: 'בראשית',
  sectionIndex: 42,
  range: selection.sourceRange,
  style: {
    backgroundColor: '#FFEB3B',
    opacity: 0.65,
    borderRadius: 3,
    priority: 10
  },
  metadata: { source: 'manual', tags: ['לימוד'] }
});
// HighlightRecord
```

הצבעים חייבים להיות `#RRGGBB` או `#RRGGBBAA`. ההדגשה ממופה מחדש אל הטקסט המוצג לאחר שינויי ניקוד, טעמים והחלפות תצוגה. ההדגשות אינן נשמרות בדיסק: התוסף אחראי להתמדה ולהקמה מחדש לאחר `plugin.boot`.

---

### `reader.updateHighlight`
**הרשאה:** `reader.highlight`

**זמין מגרסה:** `0.9.95`

מעדכן חלקית את העיצוב או המטא־נתונים של הדגשה קיימת. המזהה, העוגן, הספר וזמן היצירה אינם משתנים. כל עדכון מוצלח מגדיל את `version` ומרענן מיד את התצוגה.

אפשר להעביר `expectedVersion` או `expectedEtag` כדי למנוע דריסה של שינוי חדש יותר. במקרה שהערך אינו תואם מוחזרת השגיאה `error.conflict`. כל עדכון מוצלח מחזיר `version` ו־`etag` חדשים. תוסף רשאי לעדכן רק הדגשות שבבעלותו; מזהה של תוסף אחר מוחזר כ־`error.highlight_not_found`.

```javascript
const { data: updated } = await Otzaria.call('reader.updateHighlight', {
  highlightId: 'marker-42',
  expectedVersion: 1,
  style: { backgroundColor: '#FF9800', opacity: 0.8 },
  metadata: { note: 'חזרה חשובה' }
});
// updated.version === 2
```

האחסון נשאר באחריות התוסף: הפעולה משנה את הרשומה הזמנית של ה־Host ואינה שומרת אותה בדיסק.

---

### `reader.getHighlights`
**הרשאה:** `reader.highlight`

קבלת ההדגשות שבבעלות התוסף הקורא. אפשר לסנן לפי `bookId` ו־`sectionIndex`; תוסף אינו יכול לקרוא הדגשות של תוסף אחר.

ברירת המחדל מחזירה רק רשומות `active`. כאשר נוסח המקור משתנה, ה־Host מנסה לעגן מחדש לפי hash ו־offset, הטקסט המדויק, ההקשר לפני ואחרי, טקסט מנורמל ולבסוף occurrence index. התאמה עמומה מסומנת `stale`, והיעדר התאמה מסומן `failed_to_anchor`; שני המצבים אינם מצוירים. השתמשו ב־`includeStale: true` כדי לקבל גם אותם ולשמור או לתקן אותם בצד התוסף.

```javascript
const { data } = await Otzaria.call('reader.getHighlights', {
  bookId: 'בראשית',
  sectionIndex: 42,
  includeStale: true
}); // HighlightRecord[]
```

---

### `reader.revealHighlight`
**הרשאה:** `reader.highlight`

**זמין מגרסה:** `0.9.96`

פותח את הספר והמקטע של הדגשה השייכת לתוסף, גולל אליה ומבליט אותה זמנית. הפעולה מקבלת `highlightId` בלבד; הבעלות, הספר, המקטע והעוגן נלקחים מהרשומה הסמכותית של ה־Host.

```javascript
await Otzaria.call('reader.revealHighlight', {
  highlightId: 'marker-42'
});
```

מזהה שאינו קיים או שאינו שייך לתוסף מחזיר `error.highlight_not_found`.

---

### `reader.clearHighlight`
**הרשאה:** `reader.highlight`

הסרת הדגשה לפי `highlightId`. מזהה שאינו קיים בבעלות התוסף מחזיר `error.highlight_not_found`.

```javascript
await Otzaria.call('reader.clearHighlight', {
  highlightId: 'marker-42',
  expectedVersion: 2 // או expectedEtag
});
// true
```

---

### `reader.clearAllHighlights`
**הרשאה:** `reader.highlight`

ניקוי ההדגשות שבבעלות התוסף — לספר מסוים או לכולן. הפעולה אינה משפיעה על תוספים אחרים.

```javascript
// ניקוי ספר ספציפי
await Otzaria.call('reader.clearAllHighlights', { bookId: 'בראשית' });

// ניקוי כל ההדגשות
await Otzaria.call('reader.clearAllHighlights', {});
// true
```

---

### הרשאות חדשות

```json
{
  "permissions": [
    "reader.context_menu",
    "reader.highlight",
    "events.subscribe:reader.selection_changed"
  ]
}
```

### דוגמה — תוסף מראי מקומות

```javascript
Otzaria.on('plugin.boot', async () => {
  // רישום פריט תפריט
  await Otzaria.call('reader.addContextMenuItem', {
    id: 'save-ref',
    label: 'שמור מראה מקום'
  });

  // האזנה לסימון טקסט
  Otzaria.on('reader.selection_changed', async (data) => {
    // הצגת הצעה לשמירה
    showSaveButton(data.text, data.currentRef);
  });

  // האזנה ללחיצה על פריט התפריט
  Otzaria.on('reader.context_menu_item_clicked', async (data) => {
    if (data.itemId !== 'save-ref') return;
    await saveReference(data.currentRef, data.selectedText);
    await Otzaria.call('reader.setHighlight', {
      bookId: data.currentBookId,
      index: data.currentIndex,
      color: '#FFFACD',
      label: 'נשמר'
    });
    await Otzaria.call('notifications.showInApp', {
      message: 'מראה המקום נשמר!',
      type: 'success'
    });
  });
});
```

---

## shortcut.* - קיצורי דרך בשולחן העבודה

### `shortcut.create`
**הרשאה:** `ui.create_shortcut`

יוצר קובץ קיצור דרך תלוי-פלטפורמה שפותח את **התוסף הקורא**. זמין רק בפלטפורמות דסקטופ (Windows / macOS / Linux).

הקיצור פותח תמיד את הקישור `otzaria://open/plugin/<id>` של התוסף — **ה-host בונה אותו בעצמו**, כך שתוסף אינו יכול ליצור קיצור ל-route אחר או לסכמה זרה. לכן ה-API מקבל רק שם ומיקום, לא קישור חופשי.

לפני היצירה, אוצריא מציגה למשתמש דיאלוג אישור. אם המשתמש מבטל — מוחזר `{ created: false }` ולא נוצר קובץ.

| פרמטר | חובה | תיאור |
|--------|------|--------|
| `label` | ✓ | שם הקיצור (משמש גם כשם הקובץ וגם ככותרת המוצגת). תווים אסורים בשמות קבצים מנוקים אוטומטית. |
| `location` | | `'desktop'` (ברירת מחדל) או `'startMenu'`. **`'startMenu'` נתמך ב-Windows בלבד** — בפלטפורמות אחרות יוחזר `error.unsupported`. |

**הקובץ הנוצר לפי פלטפורמה:**

| פלטפורמה | סוג קובץ | מיקום |
|----------|----------|--------|
| Windows | `.url` (InternetShortcut) | שולחן העבודה / `Start Menu\Programs` (לפי ה-Known Folder האמיתי, מכבד הפניית OneDrive) |
| macOS | `.webloc` | `~/Desktop` |
| Linux | `.desktop` (מריץ `xdg-open`) | שולחן העבודה לפי `xdg-user-dir` |

הקיצור **לעולם אינו דורס** קובץ קיים — אם השם תפוס נוצר שם ייחודי (`שם (2).url`). אם אין שולחן עבודה אמיתי במערכת, מוחזר `error.unsupported`.

```javascript
const { data } = await Otzaria.call('shortcut.create', {
  label: 'לוח שנה הלכתי',
  location: 'desktop'
});

if (data.created) {
  await Otzaria.call('ui.showSuccess', { message: `קיצור הדרך נוצר: ${data.path}` });
} else {
  // המשתמש ביטל את דיאלוג האישור
}
```

> **למה צריך הרשאה + אישור?** יצירת קובץ בשולחן העבודה היא פעולה שהמשתמש צריך להיות מודע לה. לכן נדרשת גם הרשאת `ui.create_shortcut` ב-manifest (נאכפת בשכבת ה-RPC לפני שהפעולה רצה) וגם אישור מפורש בזמן ריצה — שתי שכבות שמונעות מתוסף ליצור קיצורים ללא ידיעת המשתמש.
