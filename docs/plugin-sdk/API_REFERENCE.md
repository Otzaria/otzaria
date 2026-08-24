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
  "bookUid": "id:183",
  "source": "library"
}
```

| שדה | משמעות |
|-----|--------|
| `id` | המזהה המספרי של הספר במסד הנתונים (`int?` — יכול להיות `null` לספרים ללא מזהה. אם ה-id לא זמין, ניתן לחפש לפי `bookId` + `type`) |
| `type` | סוג הספר: `"text"` \| `"pdf"` \| `"docx"` \| `"epub"` \| `"external"`. `null` עבור טאבים שאינם ספרים (SearchingTab, CombinedTab) |
| `bookId` | שם הספר — נשמר לצורך תאימות לאחור ולאימות כאשר נשלח יחד עם `id`. **אינו מובטח ייחודי** (שני ספרים בעלי אותו שם, ספר אישי מול רשמי, נוסחאות) ואינו יציב (עלול להשתנות בעדכון ספרייה) — עדיף `bookUid`. |
| `bookUid` | **המזהה היציב המומלץ** — מחרוזת חוצה-ספקים (`id:<n>` לספרייה, `uid:<n>` לספר אישי, `ext:<...>` לספר חיצוני). זהו המזהה שמנוע החיפוש כבר משתמש בו: יציב בין עדכוני ספרייה והעברת ספרייה, ושורד שינויי כותרת. **מומלץ לתוסף לאחסן אותו במקום כותרת.** |
| `source` | מקור הספר: `"library"` לספרייה המובנית, `"user"` ל־`user_books.db`, או `"external"` לקטלוג חיצוני. חובה לשלוח אותו עם `id` כאשר ה־ID עלול להתנגש בין מסדי נתונים. |

> **יציבות `bookUid` ו-fallback חינני:** גם `bookUid` עלול להתייתם במקרה קצה נדיר — ספר שגם משנה שם וגם עובר עריכה מסיבית באותה גרסת ספרייה (זיהוי שינוי-השם הוא היוריסטי). תוסף השומר `bookUid` צריך לשמור לצדו גם את הכותרת האחרונה שנראתה, וליפול אליה בחן אם ה-`bookUid` לא נמצא עוד.

### APIs שמחזירים זהות מלאה

| API | id | type | bookId | bookUid |
|-----|-----|------|--------|---------|
| `library.findBooks` | ✓ | ✓ | ✓ | ✓ |
| `library.getBookMetadata` | ✓ | ✓ | ✓ | ✓ |
| `library.listRecentBooks` | ✓ | ✓ | ✓ | ✓ |
| `library.getTree` | ✓ | ✓ | ✓ | ✓ |
| `reader.openBook` | קלט | קלט | קלט | קלט |
| `reader.openBookAtRef` | קלט | קלט | קלט | קלט |
| `reader.getCurrentState` | ✓ | ✓ | ✓ | ✓ |
| `reader.getCurrentRef` | ✓ | ✓ | ✓ | ✓ |
| `reader.getSelection` | ✓ | ✓ | ✓ | ✓ |
| `history.list` | ✓ | ✓ | ✓ | ✓ |
| `history.remove` | קלט | קלט | קלט | קלט |
| `bookmarks.list` | ✓ | ✓ | ✓ | ✓ |
| `bookmarks.add` | קלט | קלט | קלט | קלט |
| `bookmarks.remove` | קלט | קלט | קלט | קלט |
| `search.fullText` | ✗ (ראה הערה) | ✓ | — | — |
| `search.query` | ✓ | ✓ | ✓ | ✓ |
| `library.getBookContent` | ✗ | ✗ | ✓ | — |
| `library.getBookToc` | ✗ | ✗ | ✓ | — |
| `library.getBookAltToc` | ✗ | ✗ | ✓ | — |

> **הערה על `search.fullText`:** מנוע החיפוש (Tantivy) אינו שומר את ה-`id` מה-DB. כדי לקבל `id` — קרא ל-`library.getBookMetadata({ bookId, type })` עם התוצאה.

> **הערה על DocxBook / EpubBook:** ספרים בפורמטים אלו נפתחים בתצוגת טקסט, אך `type` נשאר `"docx"` או `"epub"` כדי לשמור על הזהות הקנונית.

- **`bookId` לא השתנה** — תוספים קיימים שמסתמכים עליו ימשיכו לעבוד. `bookUid` נוסף כשדה חדש; שום שדה קיים לא הוסר.
- **`bookUid` כקלט** — כל API שמקבל זהות ספר (`reader.openBook`, `reader.openBookAtRef`, `library.getBookMetadata`, `history.remove`, `bookmarks.add`, `bookmarks.remove` ועוד) מקבל גם `bookUid`. כשהוא נשלח הוא פותר את הספר **ישירות וחד-משמעית**, ומתעלם מ-`id`/`bookId`/`type` שאולי נשלחו לצדו.
- **כאשר שולחים כמה שדות זהות** (למשל `id` + `bookId` + `type` + `source`, בלי `bookUid`), כולם חייבים להתאים לאותו ספר. אם יש סתירה או שהזהות אינה חד-משמעית, ה-API מחזיר `null` / `false`.
- **חיפוש לפי `bookUid` בלבד** — הנתיב המומלץ; חד-משמעי ואינו דורש שדות נוספים.
- **חיפוש לפי `id` בלבד** — נתמך ב-`library.getBookMetadata`, `reader.openBook`, `reader.openBookAtRef`.
- **חיפוש לפי `bookId` בלבד** — נשמר לתאימות לאחור בכל API. כשקיימים שני ספרים בעלי אותו שם, העדיפו `bookUid`.

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

### קודי שגיאה נפוצים

| קוד | קטגוריה | משמעות |
|---|---|---|
| `permission_denied` / `error.permission_denied` | `permission` | ההרשאה לא הוצהרה במניפסט או לא אושרה |
| `error.forbidden` | `permission` | ההרשאה קיימת אך היעד עצמו חסום — נתיב מחוץ לתיקייה מאושרת, תיקייה מוגנת, או URL שאינו ב-allowlist |
| `error.invalid_params` | `validation` | פרמטרים חסרים או שגויים |
| `error.selection_empty` | `validation` | הבחירה שהתבקשה ריקה — אין טקסט לחפש בו התאמות |
| `error.not_found` | `not_found` | הפריט המבוקש אינו קיים |
| `error.conflict` | `conflict` | התנגשות — למשל שם ספק שכבר תפוס |
| `error.timeout` | `timeout` | הפעולה לא הושלמה בזמן (`retryable: true`) |
| `error.rate_limited` | `too_large` | דלי אסימונים בקיבולת 50 שמתמלא אסימון כל 10ms — 100 קריאות/שנייה בקצב מתמשך, אך פרץ גדול מ-50 נכשל מיד (`retryable: true`) |
| `error.payload_too_large` / `error.section_too_large` | `too_large` | הקלט או הקטע גדולים מדי |
| `error.unknown_method` | `unsupported` | ה-method אינו קיים במארח הזה — איות שגוי, או API חדש מ-`minAppVersion` שהוצהר |
| `error.unavailable` | `unsupported` | ה-API קיים אך אינו זמין בהקשר הנוכחי (אין טאב קריאה פעיל, שירות כבוי) |
| `error.unsupported_context` / `error.unsupported_layer` | `unsupported` | ההקשר או השכבה אינם נתמכים לפעולה הזו |
| `error.internal` | `internal` | שגיאה פנימית בצד אוצריא |

### ⚠️ הקריאות חייבות לצאת מה-frame הראשי

הגשר נעול לדף התוסף עצמו: `Otzaria.call` נושא nonce שמוזרק רק ל-frame הראשי,
ו-iframe חוצה-origin אינו יכול לקרוא בשמכם. שתי השלכות מעשיות:

- **אל תקראו ל-`window.flutter_inappwebview.callHandler('otzaria_rpc', ...)` ישירות.**
  קריאה כזו עוקפת את ה-nonce ותידחה. `Otzaria.call` הוא הממשק היחיד הנתמך.
- **ה-nonce אינו מגן מפני iframe שיורש את ה-origin שלכם.** `iframe` מסוג
  `srcdoc`, `about:blank` או `blob:` הוא same-origin עם הדף שלכם, ולכן יכול
  לקרוא `parent.Otzaria.call(...)` בלי לדעת את ה-nonce. **תוסף שמרנדר HTML
  מרוחק לתוך `iframe.srcdoc` מעניק לתוכן הזר את מלוא סמכות התוסף** — כל
  ההרשאות שלכם, כולל רשת, קבצים והערות. הציגו תוכן שאינו שלכם רק כטקסט
  מנוקה (sanitized), ואם אתם חייבים iframe — טענו אותו מ-URL עם origin נפרד.

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
| `app.getConnectivity` | 0.9.96 |
| `library.findBooks` | 0.9.89 |
| `library.getBookMetadata` | 0.9.89 |
| `library.resolveBooks` | 0.9.97 |
| `library.resolveCategoryPaths` | 0.9.97 |
| `library.listRecentBooks` | 0.9.89 |
| `library.getBookContent` | 0.9.89 |
| `library.getBookToc` | 0.9.89 |
| `library.listBookAltStructures` | 0.9.96 |
| `library.getBookAltToc` | 0.9.96 |
| `library.getTree` | 0.9.93 |
| `library.getCommentators` | 0.9.97 |
| `library.getLinks` | 0.9.97 |
| `library.getLinkTargetsSummary` | 0.9.97 |
| `library.getLinkContent` | 0.9.97 |
| `network.fetch` | 0.9.93 |
| `network.fetchStream` | 0.9.97 |
| `network.download` | 0.9.93 |
| `search.fullText` | 0.9.89 |
| `search.query` | 0.9.97 |
| `search.getOptions` | 0.9.97 |
| `reader.openBook` | 0.9.89 |
| `reader.openBookAtRef` | 0.9.89 |
| `reader.openSearchTab` | 0.9.89 |
| `reader.getCurrentState` | 0.9.89 |
| `reader.getCurrentRef` | 0.9.89 |
| `reader.getSelection` | 0.9.89 |
| `reader.getActiveCommentators` | 0.9.97 |
| `reader.setActiveCommentators` | 0.9.97 |
| `reader.scrollToSection` | 0.9.97 |
| `reader.getHighlightCapabilities` | 0.9.97 |
| `reader.findTextOccurrences` | 0.9.95 |
| `reader.getSectionTextMap` | 0.9.95 |
| `reader.registerInBookSearchProvider` | 0.9.97 |
| `reader.respondInBookSearch` | 0.9.97 |
| `reader.registerExternalSearchProvider` | 0.9.97 |
| `reader.respondExternalSearch` | 0.9.97 |
| `reader.addContextMenuItem` | 0.9.89 |
| `reader.removeContextMenuItem` | 0.9.89 |
| `reader.updateContextMenuItem` | 0.9.95 |
| `reader.addToolbarItem` | 0.9.97 |
| `reader.removeToolbarItem` | 0.9.97 |
| `reader.updateToolbarItem` | 0.9.97 |
| `reader.setHighlight` | 0.9.89 |
| `reader.updateHighlight` | 0.9.95 |
| `reader.getHighlights` | 0.9.89 |
| `reader.revealHighlight` | 0.9.96 |
| `reader.clearHighlight` | 0.9.89 |
| `reader.clearAllHighlights` | 0.9.89 |
| `navigation.goTo` | 0.9.89 |
| `plugin.openSelf` | 0.9.96 |
| `plugin.openOther` | 0.9.97 |
| `plugin.backgroundDone` | 0.9.97 |
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
| `fs.beginBinaryWrite` | 0.9.97 |
| `fs.commitUserFileWrite` | 0.9.97 |
| `fs.abortBinaryWrite` | 0.9.97 |
| `fs.writeFile` | 0.9.97 |
| `fs.readFile` | 0.9.97 |
| `fs.listDir` | 0.9.97 |
| `fs.makeDir` | 0.9.97 |
| `fs.deleteEntry` | 0.9.97 |
| `fs.stat` | 0.9.97 |
| `feedback.sendEmail` | 0.9.89 |
| `feedback.report` | 0.9.97 |
| `feedback.hasReporterEmail` | 0.9.97 |
| `history.list` | 0.9.89 |
| `history.listSearches` | 0.9.89 |
| `history.clear` | 0.9.89 |
| `history.remove` | 0.9.89 |
| `bookmarks.list` | 0.9.97 |
| `bookmarks.add` | 0.9.97 |
| `bookmarks.remove` | 0.9.97 |
| `tools.gematria` | 0.9.97 |
| `tools.dictionary` | 0.9.97 |
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
| `calendar.getDailyTimes` | 0.9.92 |
| `calendar.getHalachicTimes` | 0.9.92 |
| `calendar.getJewishDate` | 0.9.89 |
| `calendar.getEvents` | 0.9.89 |
| `calendar.getCities` | 0.9.96 |
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

> **`surfaceContainerHigh` — רקע פס הכותרת שלך.** התוסף נפתח כטאב קריאה ואוצריא אינה מציירת כותרת מעל ה-WebView; שם התוסף חייב להופיע בפס עליון קבוע בצבע הזה, כדי שיתיישר עם הסרגל העליון של מסכי הספרים. ראה [DESIGN\_GUIDE.md § סרגל כותרת התוסף](DESIGN_GUIDE.md#סרגל-כותרת-התוסף-top-bar).

> **גופנים מוטמעים אוטומטית:** השמות שמגיעים ב-`typography.fontFamily` ו-`typography.commentatorsFontFamily` (כגון `FrankRuhlCLM`, `Shofar`, `NotoRashiHebrew`) נטענים אוטומטית ב-WebView של התוסף כ-`@font-face` עוד לפני ה-`plugin.boot`. אין צורך לארוז את קבצי הגופן בתוסף — מספיק להפנות לשם שהתקבל ב-CSS: `font-family: 'FrankRuhlCLM', serif;`. אם המשתמש בחר גופן מערכת (לא מובנה), ההזרקה האוטומטית מדלגת עליו וה-WebView ייפול חזרה ל-fallback של מערכת ההפעלה.

### `app.getLocale`
מחזיר את שפת הממשק שבחר המשתמש (או שפת המערכת, בזיהוי אוטומטי) ואת כיוון
הטקסט שלה. עד 0.9.96 הוחזר תמיד `he-IL`; מ-0.9.97 הערך משקף את הגדרת השפה
באפליקציה, ונוסף שדה `language` עם קוד השפה הנקי.

```javascript
const { data } = await Otzaria.call('app.getLocale');
// { locale: "he-IL", language: "he", textDirection: "rtl" }
// באנגלית: { locale: "en", language: "en", textDirection: "ltr" }
```

אותם שדות מגיעים גם ב-`payload.app` של אירוע `plugin.boot`. שינוי שפה תוך
כדי ריצה נמסר באירוע `settings.changed` עם המפתח `key-settings-language` ועם
קוד השפה האפקטיבי (`he` או `en`) ב-`newValue` — גם כאשר בחירת המשתמש היא
`system` (ראו § תוסף רב-לשוני).

### תוסף רב-לשוני (i18n)

עברית היא שפת הבסיס של אוצריא — תוסף כותב את ממשקו בעברית, ומוסיף תרגום
לכל שפה שירצה. העיקרון:

1. **קובץ תרגום לכל שפה**, מוטמע בתוסף (ללא רשת), למשל `i18n/en.js` הרושם
   מילון תחת `window.TRANSLATIONS.en`. המפתחות הם מחרוזות המקור בעברית:

   ```javascript
   // i18n/en.js
   window.TRANSLATIONS = window.TRANSLATIONS || {};
   window.TRANSLATIONS.en = {
     'הגדרות': 'Settings',
     'הצג': 'Show',
   };
   ```

2. **בחירת השפה** — מ-`payload.app.language` שבאירוע `plugin.boot` (או
   `app.getLocale`). אם אין מילון לשפה — נשארים בעברית:

   ```javascript
   const dict = window.TRANSLATIONS[payload.app.language] || null;
   const t = s => (dict && dict[s]) || s;   // נפילה טבעית לעברית
   ```

3. **כיוון** — כש-`textDirection` הוא `ltr`, קבעו
   `document.documentElement.dir = 'ltr'` בזמן ריצה (ה-HTML הסטטי נשאר
   `dir="rtl"`, כדרישת ולידציית העיצוב).

4. **עדכון חי** — האזינו ל-`settings.changed` (הרשאת
   `events.subscribe:settings.changed`) ובדקו `key === 'key-settings-language'`;
   או הסתפקו בשפה שנקבעה ב-boot.

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

### `app.getConnectivity`
**הרשאה:** `app.info.read`

מחזיר את מצב הקישוריות של אוצריא — כדי שתוכלו להסתיר יכולות מקוונות ממשתמש שאין לו אינטרנט, במקום להציג לו כפתור שנכשל בלחיצה.

```javascript
const { data } = await Otzaria.call('app.getConnectivity');
// { isOfflineMode: false, hasNetwork: true, isOnline: true }
```

להכרחת בדיקה חדשה, למשל כשהמשתמש נכנס במפורש למסך מקוון:

```javascript
const { data } = await Otzaria.call('app.getConnectivity', { forceRefresh: true });
```

| שדה | משמעות |
|-----|---------|
| `isOfflineMode` | המשתמש סימן "ללא גישה לאינטרנט" בהגדרות אוצריא |
| `hasNetwork` | נמצא חיבור בפועל |
| `isOnline` | `!isOfflineMode && hasNetwork` — הדגל היחיד שרוב התוספים צריכים |

**חשוב לדעת על ההתנהגות:**

- **תוצאת בדיקת הרשת נשמרת ל-30 שניות.** קריאות בתוך החלון הזה זולות ואינן פותחות חיבורים חדשים. לאחר מכן הקריאה הבאה מרעננת את המצב.
- **`forceRefresh: true` עוקף תוצאה שמורה**, אבל עדיין מתלכד עם בדיקה שכבר רצה. השתמשו בו בנקודות מעבר משמעותיות, לא בכל רינדור.
- **`isOfflineMode` נקרא מחדש בכל קריאה**, ולכן שינוי ההגדרה נכנס לתוקף מיד גם כשתוצאת הרשת עדיין שמורה.
- **אל תקראו לזה מכל רינדור.** הקריאה עצמה זולה בצד אוצריא, אבל היא נספרת במגביל הקצב של ה-RPC (דלי של 50 אסימונים שמתמלא אסימון כל 10ms), וקריאה מכל פריים תחזיר `error.rate_limited`. שמרו את הערך במשתנה ורעננו לפי צורך.
- **במצב מנותק לא מתבצעת בדיקת רשת כלל** — התשובה מיידית, `hasNetwork` תמיד `false`.
- הבדיקה מנסה את `otzaria.org` וגם יעדים ניטרליים. די בכך שאחד עונה, ולכן תקלה זמנית בשרת של אוצריא לא מסמנת את כל המשתמשים כמנותקים.

**הדפוס המומלץ — בלי הבהוב.** מצב הקישוריות מגיע כבר ב-`plugin.boot`, אבל בתוסף הראשון שנפתח בריצה הוא עשוי להיות `null` ("טרם הוכרע") — אוצריא לא מעכבת את פתיחת התוסף כדי להמתין לרשת. לכן התחילו כשהיכולת המקוונת **מוסתרת**, וחשפו אותה רק כשהתשובה חיובית:

```javascript
Otzaria.on('plugin.boot', async (payload) => {
  // מוסתר כברירת מחדל — ככה הכפתור לא מופיע ונעלם למי שאין לו רשת
  let online = payload.connectivity.isOnline;
  if (online === null) {
    const { data } = await Otzaria.call('app.getConnectivity');
    online = data.isOnline;
  }
  if (online) document.getElementById('online-section').hidden = false;
});
```

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
// { id: 1, bookId: "בראשית", title: "בראשית", categoryPath: "/תנך/תורה", topics: [...] }
```

### `library.resolveBooks`
**הרשאה:** `library.books.read`

פותר עד 100 זהויות ספר באצווה, לרבות זהות חיצונית, בלי לחשוף נתיבים. סדר
התשובות זהה לסדר הקלט; זהות שאינה קיימת או אינה חד־משמעית מוחזרת כ־`null`.

```javascript
const { data } = await Otzaria.call('library.resolveBooks', {
  items: [
    { id: 183, type: 'text' },
    { external: { provider: 'hebrewbooks', id: 42 } }
  ]
});
// [{ id, type, source, bookId, title, categoryPath, external? }, ...]
```

### `library.resolveCategoryPaths`
**הרשאה:** `library.books.read`

נתיב הקטגוריה בעץ הספרייה לכל מזהה ספר, באצווה של עד 20,000 מזהים —
מסלול bulk לסיווג אינדקס שלם של ספק תוצאות חיצוני בקריאה אחת. סדר
התשובות זהה לסדר הקלט; מזהה לא מוכר מוחזר כ־`null`.

```javascript
const { data } = await Otzaria.call('library.resolveCategoryPaths', {
  ids: [183, 42, 9999]
});
// ["/תנך/תורה", "/הלכה", null]
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

## מפרשים וקישורים

ארבע הקריאות הבאות חושפות את מפת הקישורים של הספרייה: אילו מפרשים קיימים על
ספר, אילו קישורים יוצאים מטווח שורות נתון, ומה התוכן שבצד השני של הקישור.

**כל מספרי השורות ב-API הזה 0-based** — כמו ה-`index` של `library.getBookToc`
ושל `reader.getCurrentRef`. אין צורך בהיסט כלשהו בין הקריאות.

> ⚠️ **גרשיים עבריים.** שמות הספרים במסד שמורים בגרשיים עבריים (`״` U+05F4,
> `׳` U+05F3) ולא במרכאות ASCII (`"`, `'`). השוואה מול ליטרל כמו `'רש"י על
> בראשית'` תיכשל בשקט. תמיד השוו/העבירו את המחרוזת שהתקבלה מהקריאה הקודמת.

הקישורים תלויים במהדורת הטקסט של הספר. ספר שקיים כ-PDF בלבד מוחזר כ-
`error.not_found`; לספר שיש לו שתי מהדורות, העבירו את כותרת מהדורת הטקסט.

> 💡 **התחילו מ-`getLinkTargetsSummary`.** הוא מחזיר את כל ספרי היעד של הספר
> בקריאה אחת וזולה, כולל `maxSourceLine` — ומאפשר לבחור אילו יעדים לבקש
> ב-`getLinks` (`targetTitles`) במקום לסרוק את כל הקישורים.

### `library.getCommentators`
**הרשאה:** `library.links.read` · **מגרסה:** 0.9.97

רשימת המפרשים של ספר. זיהוי הספר: `bookId` (=כותרת) עם `categoryId` אופציונלי
שמכריע בין ספרים שווי-שם, או `id` מספרי.

- ללא `startLine`/`endLine` — כל מפרשי הספר, עם `linkCount` ועם `isRare`
  (מפרש שהממשק מסתיר מרשימת הבחירה הכללית בספרים גדולים).
- עם `startLine`+`endLine` (חובה יחד, 0-based וכולל) — רק המפרשים על אותו
  טווח שורות. בקריאה זו `isRare` תמיד `false` — הנדירות מוגדרת ביחס לספר כולו.
- `grouped: true` — במקום `commentators` מוחזר `groups`, המפרשים מקובצים לפי
  דורות באותו סדר שבו הממשק מציג אותם. קבוצות ריקות מושמטות.

```javascript
const { data } = await Otzaria.call('library.getCommentators', {
  bookId: 'בראשית',
  categoryId: 7,     // אופציונלי — מכריע בין ספרים שווי-שם
  startLine: 0,      // אופציונלי, חובה יחד עם endLine
  endLine: 40,
  grouped: false     // אופציונלי, ברירת מחדל: false
});
// { commentators: [
//     { title: "רש״י על בראשית", author: "רש״י", linkCount: 1420, isRare: false },
//     ...
// ] }

// grouped: true
// { groups: [{ title: "ראשונים", commentators: ["רש״י על בראשית", ...] }, ...] }
```

### `library.getLinks`
**הרשאה:** `library.links.read` · **מגרסה:** 0.9.97

הקישורים היוצאים מטווח שורות בספר — מפרשים והפניות כאחד, כולל קישורי-משתמש
שיובאו מקבצי CSV.

`startLine` ו-`endLine` חובה (0-based, כולל), והחלון מוגבל ל-**200 שורות**;
חלון גדול יותר מוחזר כ-`error.invalid_params`. תשובה נחתכת אחרי 2,000 רשומות
ומסומנת `truncated: true`.

- `connectionTypes` — סינון לפי סוג חיבור (`"COMMENTARY"`, `"TARGUM"`,
  `"REFERENCE"` …). ההשוואה אינה תלוית רישיות.
- `targetTitles` — סינון לספרי יעד מסוימים.
- `includeAnchors` — כשהוא `true`, קישור בעל עוגן-מילה מקבל שדה `anchor`.

```javascript
const { data } = await Otzaria.call('library.getLinks', {
  bookId: 'בראשית',
  startLine: 0,
  endLine: 40,
  connectionTypes: ['COMMENTARY'],  // אופציונלי
  targetTitles: ['רש״י על בראשית'], // אופציונלי
  includeAnchors: false             // אופציונלי, ברירת מחדל: false
});
// {
//   truncated: false,
//   links: [{
//     sourceLine: 0,
//     targetTitle: "רש״י על בראשית",
//     targetLine: 3,
//     targetLineEnd: null,       // קישור-טווח בלבד
//     targetHeRef: "רש״י על בראשית א, א",
//     connectionType: "COMMENTARY",
//     isCommentary: true,        // מפרש (ולא הפניה)
//     targetIsUserBook: false,
//     targetCategoryId: 12,      // להעברה ל-getLinkContent
//     anchor: { start: 4, end: 9, label: "א" }  // רק עם includeAnchors
//   }]
// }
```

### `library.getLinkTargetsSummary`
**הרשאה:** `library.links.read` · **מגרסה:** 0.9.97

כל ספרי היעד של הספר לפי סוג חיבור, בלי לטעון את הקישורים עצמם.
`maxSourceLine` הוא השורה הגבוהה ביותר שיש עליה קישור (0-based), או `-1`
כשאין לספר קישורים כלל.

```javascript
const { data } = await Otzaria.call('library.getLinkTargetsSummary', {
  bookId: 'בראשית'
});
// {
//   maxSourceLine: 1533,
//   targets: [
//     { targetTitle: "רש״י על בראשית", connectionType: "COMMENTARY", linkCount: 1420 },
//     ...
//   ]
// }
```

### `library.getLinkContent`
**הרשאה:** `library.content.read` · **מגרסה:** 0.9.97

תוכן הצד המקושר — עד **25 פריטים** בקריאה אחת (יותר מכך:
`error.invalid_params`). ה-`items` מוחזרים באותו סדר של הקלט; פריט שלא ניתן
לטעון מוחזר כ-`{ error: "not_found" }`.

העבירו את `targetTitle`, `targetLine`, `targetLineEnd`, `targetIsUserBook`
ו-`targetCategoryId` בדיוק כפי שהתקבלו מ-`getLinks` — הם מזהים את הספר הנכון
כשקיימים ספרים שווי-שם או מהדורה אישית.

```javascript
const { data } = await Otzaria.call('library.getLinkContent', {
  links: [
    { targetTitle: 'רש״י על בראשית', targetLine: 3, targetCategoryId: 12 }
  ]
});
// { items: [{ content: "בראשית ברא — אמר רבי יצחק..." }] }
```

---

## network.* - גישה לרשת

> כל גישת רשת מוגבלת לרשימת ההיתר של אוצריא — ראו [⚠️ הרשאת `network.access`](#️-הרשאת-networkaccess--דרישה-מיוחדת-pr-לאוצריא).

### `network.fetchStream`
**הרשאה:** `network.access` (או `network.localhost` ליעד מקומי) · **מגרסה:** 0.9.97

מבצעת בקשת HTTP בצד אוצריא ומחזירה `AsyncIterable` מיד עם קבלת כותרות
התשובה. הפרמטרים זהים ל-`network.fetch`: `url`, `method`, `headers`, `body`
ו-`timeoutMs`. חסם הזמן חל על הבקשה כולה, כולל קריאת הגוף; ברירת המחדל היא
30,000 והמקסימום 120,000 מילישניות.

הפריט הראשון הוא תמיד `{ type: "response", sequence, status, ok, headers }`.
אחריו מתקבלים פריטי `{ type: "data", sequence, body }`. כל `body` הוא מקטע
UTF-8 תקין, אך גבול המקטע אינו מבטיח סוף שורה או אובייקט JSON שלם. יציאה
מוקדמת מ-`for await` מבטלת את בקשת ה-HTTP. יש לצרוך את האיטרטור ברציפות;
תור של 256 מקטעים מגן מפני צרכן תקוע, ולאחריו הזרם נכשל והבקשה מבוטלת.

```javascript
const chunks = Otzaria.call('network.fetchStream', {
  url: 'http://127.0.0.1:5000/search',
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ query: 'בראשית' }),
  timeoutMs: 120000
});

let pending = '';
for await (const chunk of chunks) {
  if (chunk.type === 'response') {
    if (!chunk.ok) throw new Error(`HTTP ${chunk.status}`);
    continue;
  }
  pending += chunk.body;
  const lines = pending.split('\n');
  pending = lines.pop() ?? '';
  for (const line of lines) {
    if (line.trim()) consumeResult(JSON.parse(line));
  }
}
if (pending.trim()) consumeResult(JSON.parse(pending));
```

### `network.fetch`
**הרשאה:** `network.access` (או `network.localhost` ליעד מקומי — ראו [שירותים מקומיים](#שירותים-מקומיים-localhost--הרשאת-networklocalhost))

> **מיושן — מוסר ב-0.9.98:** השתמשו ב-`network.fetchStream`. ה-API הישן
> ממתין לכל גוף התשובה ומחזיר אותו כמחרוזת אחת.

שליפת תוכן מ-URL מותר (ללא מעקב אחר redirects). מחזירה את גוף התשובה כטקסט.

**חשוב — מתי להשתמש בזה במקום `fetch()` רגיל:** קריאת `fetch()` ישירה מתוך
ה-WebView של התוסף כפופה ל-CORS (ה-origin הוא `null` כי הדף נטען מ-`file://`).
שרת שלא מחזיר `Access-Control-Allow-Origin` יחסום את הבקשה. `network.fetch`
רץ בצד אוצריא (Flutter) ואינו כפוף ל-CORS — לכן לקריאות ל-APIs חיצוניים
(במיוחד `POST`) יש להשתמש בו ולא ב-`fetch()` ישיר.

פרמטרים: `url` (חובה), `method` (ברירת מחדל `GET`), `headers` (אובייקט,
אופציונלי), `body` (מחרוזת, אופציונלי), `timeoutMs` (מספר שלם חיובי;
ברירת מחדל 30,000 ומקסימום 120,000 מילישניות).

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
  body: JSON.stringify({ key: 'value' }),
  timeoutMs: 120000
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

- ה-`url` חייב להופיע גם ב-`network.allowlist` של התוסף וגם ברשימת ההיתר הרשמית של אוצריא (הקובץ `plugin_network_allowlist.txt` בענף `dev` ב-GitHub, או הגיבוי המקומפל `pluginNetworkAllowlist`).
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

> **הערה:** `search.fullText` אינו מחזיר `id` כי מנוע החיפוש (Tantivy) אינו שומר את מזהה הספר מה-DB. כדי לקבל את `id` — יש לקרוא ל-`library.getBookMetadata({ bookId, type })` עם התוצאה. `search.query` (להלן) כן מחזיר זהות מלאה.

### `search.query`
**הרשאה:** `search.fulltext.read`

חיפוש מלא עם **כל** הפרמטרים של מסך החיפוש של אוצריא — מצב, היקף, מדיניות
התאמה, אפשרויות מילה, מילים חלופיות, מרווחים, שלילה, מיון, איחוד ודפדוף.
החיפוש רץ באותו מסלול מנוע שהאפליקציה מריצה, אך התוצאות חוזרות לתוסף ואינן
נפתחות בטאב.

```javascript
const chunks = Otzaria.call('search.query', {
  query: 'ואהבת לרעך',
  mode: 'advanced',       // 'exact' (ברירת מחדל) | 'advanced' | 'fuzzy'
  distance: 2,            // מרווח מילים מותר במצב מתקדם/מקורב
  limit: 100,             // ברירת מחדל 50, מקסימום 500
  offset: 0,              // דפדוף
  order: 'relevance',     // 'relevance' (ברירת מחדל) | 'catalogue' | 'generation'
  categories: ['/תנך/תורה'],
  options: { 'קידומות דקדוקיות': true },
  includeBookCounts: true
});

for await (const chunk of chunks) {
  appendResults(chunk.results);
  updateTotal(chunk.total);
}
```

**פרמטרים**

| פרמטר | ברירת מחדל | משמעות |
|-------|-----------|--------|
| `query` | — (חובה) | מחרוזת החיפוש |
| `negativeQuery` | `''` | מילים ש**לא** יופיעו בתוצאה |
| `mode` | `'exact'` | `'exact'` מדויק, `'advanced'` מתקדם (אפשרויות/חלופות/מרווחים), `'fuzzy'` מקורב (מרחק עריכה) |
| `limit` / `offset` | `50` / `0` | דפדוף. `limit` נחתך ל-500, ו-`offset + limit` הממשיים אינם יכולים לעלות על 10,000 |
| `order` | `'relevance'` | `'relevance'` \| `'catalogue'` (סדר הספרייה) \| `'generation'` (סדר הדורות) |
| `distance` | `0` | מספר המילים המותר בין מילות החיפוש; במצב `'fuzzy'` הטווח הוא 0–2 |
| `proximityScope` | `'wordDistance'` | `'wordDistance'` מרווח מילים \| `'sameParagraph'` באותה פסקה \| `'sameSection'` תחת אותה כותרת |
| `wordMatchMode` | `'all'` | `'all'` \| `'anyWord'` \| `'mostWords'` \| `'atLeast'` |
| `wordMatchCount` | `2` | מספר המילים הנדרש; ניתן לשלוח רק עם `mode: 'advanced'` ו-`wordMatchMode: 'atLeast'` |
| `grouping` | `'none'` | `'none'` \| `'sameSection'` (איחוד לפי סעיף) \| `'identicalText'` (איחוד טקסט זהה) |
| `options` | `{}` | אפשרויות מילה שחלות על **כל** מילות השאילתה |
| `wordOptions` | `{}` | אפשרויות פר-מילה במפתח `"{מילה}_{אינדקס}"`; גובר על `options` |
| `alternativeWords` | `{}` | מילים חלופיות לפי אינדקס מילה: `{ "0": ["אהבת", "יאהב"] }` |
| `customSpacing` | `{}` | מרווח ידני בין זוג מילים **סמוכות**: `{ "0-1": "3" }` |
| `negativeDistance`, `negativeProximityScope`, `negativeOptions`, `negativeWordOptions`, `negativeAlternativeWords`, `negativeCustomSpacing` | כמו החיוביים | אותם פרמטרים עבור `negativeQuery` |
| `includeBookCounts` | `false` | להחזיר גם ספירת תוצאות לפי ספר |

**היקף החיפוש** (ניתן לשלב; ריק = כל הספרייה):

| פרמטר | דוגמה |
|-------|-------|
| `categories` | `['/תנך/תורה', '/הלכה']` — נתיב קטגוריה |
| `books` | `[{ id: 183, type: 'text' }]` — זהות ספר כמו בשאר ה-APIs |
| `authors` | `['רש"י']` |
| `eras` | `['ראשונים']` — הערכים החוקיים מ-`search.getOptions` |
| `baseBooksOnly` | `true` — ספרי יסוד בלבד |
| `facets` | `['/תנך']` — נתיבי facet גולמיים (שימוש מתקדם) |

היקפים מאותו סוג מתחברים ב-OR; סוגים שונים מתחברים ב-AND (למשל `eras` + `categories`
= ספרי אותה תקופה שבאותה קטגוריה).

**פלט — `AsyncIterable` של chunks**

הקריאה אינה מחזירה `Promise` ואינה ממתינה לכל התוצאות. משתמשים ב־`for await`;
הפסקת הלולאה (`break` או `return`) מבטלת את החיפוש בצד אוצריא. ה־chunk הראשון
נושא את הספירות, והבאים נושאים עד 50 תוצאות כל אחד.

> **צרכן איטי קוטע את הזרם.** ה-SDK מחזיק תור של 256 chunks; אם הלולאה אינה
> מדביקה את הקצב, הזרם נכשל עם `Stream consumer is too slow` והחיפוש מבוטל.
> תוסף שמרנדר DOM בתוך הלולאה לכל תוצאה יראה חיפוש שנקטע ללא סיבה נראית —
> אספו את התוצאות למערך ורנדרו מחוץ ללולאה, או ב-`requestAnimationFrame`.

```javascript
{
  sequence: 0,
  results: [{
    id: 183, type: 'text', bookId: 'ויקרא', source: 'library',
    book: 'ויקרא', categoryPath: '/הלכה/משנה תורה',
    reference: 'ויקרא, פרק יט',
    text: 'ואהבת לרעך כמוך...',
    index: 1234,          // אינדקס השורה/עמוד לפתיחה עם reader.openBook
    mergedCount: 1,       // מספר התוצאות שאוחדו לכרטיס (במצב grouping)
    merged: [{ id, type, bookId, source, book, categoryPath, reference, index }]
                            // רק כשיש איחוד; לכל אח זהות וקטגוריה מלאות
  }],
  total: 812,             // סך ההתאמות; זמין מה-chunk הראשון
  groupCount: null,       // מספר הקבוצות כש-grouping פעיל, אחרת null
  truncated: false,       // true = שאילתה רחבה מדי, התוצאות והספירה חלקיות
  limit: 100, offset: 0,
  facets: ['/תנך/תורה'],  // ההיקף כפי שנפתר בפועל
  bookCounts: [{ id, type, bookId, source, title, count }]  // רק עם includeBookCounts
}
```

אין לצבור את כל התוצאות לפני ציור המסך: יש להוסיף כל `results` מיד עם הגעת
ה־chunk. אם החיפוש נכשל, האיטרטור זורק שגיאה; chunks שכבר התקבלו נשארים בידי
התוסף.

**מפתחות פר-מילה** — `wordOptions`, `alternativeWords` ו-`customSpacing` נבדקים
מול פיצול המילים של השאילתה: מפתח `"{מילה}_{אינדקס}"` שאינו תואם, אינדקס מחוץ
לטווח או זוג מרווח שאינו סמוך מוחזרים כ-`error.invalid_params` (ולא נבלעים
בשקט כמו במנוע).

רק הפרמטרים המתועדים מתקבלים; מפתח עליון לא מוכר או מבנה ערך שגוי (למשל
רשימה שאינה מכילה מחרוזות) נדחים במפורש ולא נבלעים בשקט.

שגיאות אפשריות: `error.invalid_params` (פרמטר או ערך לא מוכר, פרמטר שאינו
נתמך במצב שנבחר, או מפתח פר-מילה שאינו תואם לשאילתה), `error.not_found`
(ספר שנשלח ב-`books` לא נמצא), `error.timeout` (שאילתה רחבה מדי — צמצמו את
ההיקף או את `limit`).

### `search.getOptions`
**הרשאה:** `search.fulltext.read`

מחזיר את כל הערכים החוקיים לפרמטרים של `search.query` — כדי לבנות מסך חיפוש
בתוסף בלי לקבע רשימות שעלולות להשתנות.

```javascript
const { data } = await Otzaria.call('search.getOptions', {});
// {
//   modes: ['exact', 'advanced', 'fuzzy'],
//   orders: ['relevance', 'catalogue', 'generation'],
//   proximityScopes: ['wordDistance', 'sameParagraph', 'sameSection'],
//   grouping: ['none', 'sameSection', 'identicalText'],
//   wordMatchModes: ['all', 'anyWord', 'mostWords', 'atLeast'],
//   wordOptions: {
//     exact: ['קידומות דקדוקיות', ...],      // האפשרויות שהמצב המדויק תומך בהן
//     advanced: ['קידומות', 'ראשי תיבות', ...],
//     vocalized: ['ניקוד', 'טעמים']
//   },
//   eras: ['חז"ל', 'ראשונים', 'אחרונים', 'מחברי זמננו'],
//   maxLimit: 500, maxResultWindow: 10000,
//   fuzzyMaxDistance: 2, defaultLimit: 50
// }
```

> פרמטר שהמצב הנבחר אינו מריץ **נדחה** ב-`error.invalid_params` ולא נבלע
> בשקט: `negativeQuery`, `alternativeWords`, `customSpacing`, `proximityScope`,
> `wordMatchMode` וכל פרמטרי ה-`negative*` דורשים `mode: 'advanced'`; המצב
> `'fuzzy'` אינו מקבל אפשרויות מילה כלל; המצב `'exact'` מקבל רק את
> `wordOptions.exact` שלמעלה.

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
  navigateToPositionIfReused: false, // אופציונלי — אם הטאב פתוח, נווט אליו
  openInSidePane: false, // אופציונלי — הצג בטאב הנוכחי כחלונית לצד הספר
  matchPages: [8, 12],   // אופציונלי (PDF) — עמודי התאמה של חיפוש חיצוני
  matchedTerms: ['שבת']  // אופציונלי — המונחים שנמצאו, לתצוגה בסרגל ההתאמות
});
// true — פתח בהצלחה; false — הספר לא נמצא או הזהות לא תואמת
```

עם `openInSidePane: true` הספר אינו מחליף את מסך הקריאה אלא נפתח כחלונית
נוספת בטאב הנוכחי, לצד הספר שכבר פתוח (כמו "הצג לצד"). כשהטאב הנוכחי כבר
מפוצל, או כשאין טאב פתוח, הספר נפתח ככרטיסייה רגילה.

עם `matchPages` (בספר PDF) קורא ה-PDF מציג סרגל "עמודי התאמה" עם ניווט
מופע קודם/הבא בין העמודים שסופקו — למשל תוצאות חיפוש של מנוע חיצוני שהתוסף
מפעיל. העמודים מבוססי-1; רשימה ריקה או ערכים לא חיוביים נדחים.

**כאשר נשלחים מספר שדות זהות (id + bookId + type), כולם חייבים להתאים לאותו ספר. אי-התאמה מחזירה `false`.**

### `reader.registerInBookSearchProvider`
**הרשאה:** `reader.open`

רושם את התוסף כספק חיפוש-בתוך-ספר לספרים חיצוניים של `provider`
(למשל `hebrewbooks`). מאותו רגע, כשהמשתמש מחפש בסרגל ההתאמות של קורא
ה-PDF בספר חיצוני של אותו provider, אוצריא שולחת לתוסף אירוע ממוקד
`reader.inBookSearch.requested` עם `{ requestId, provider, externalId, query }`.
התוסף מריץ את החיפוש במנוע שלו ועונה עם `reader.respondInBookSearch`.
שם ספק שייך לתוסף הראשון שרשם אותו; ניסיון של תוסף אחר לרשום אותו נדחה
עם `error.conflict`.

```javascript
await Otzaria.call('reader.registerInBookSearchProvider', {
  provider: 'hebrewbooks',
});

window.addEventListener('reader.inBookSearch.requested', async (event) => {
  const { requestId, externalId, query } = event.detail;
  const result = await searchInMyEngine(externalId, query);
  await Otzaria.call('reader.respondInBookSearch', {
    requestId,
    pages: result.pages,          // עמודי התאמה מבוססי-1
    matchedTerms: result.terms,   // אופציונלי
    query,
  });
});
```

### `reader.respondInBookSearch`
**הרשאה:** `reader.open`

תשובת הספק לאירוע `reader.inBookSearch.requested`. חובה להעביר את
`requestId` מהאירוע; בכישלון מעבירים `error` עם הודעה קצרה במקום `pages`.
בקשה שלא נענתה בתוך 30 שניות נכשלת בצד הקורא.
התשובה מתקבלת רק מהתוסף שאליו הבקשה נשלחה.

### `reader.registerExternalSearchProvider`
**הרשאה:** `reader.open`

רושם את התוסף כספק תוצאות חיצוני לטאב החיפוש המובנה. הספק מופעל דרך שורת
דיאלוג חיפוש (`searchDialogItems`) שמצהירה `resultsProvider` עם אותו שם:
כשהמשתמש מסמן את השורה ומחפש, נפתח טאב חיפוש רגיל ובראשו מדור תוצאות
מהתוסף (בכותרת `resultsTitle`), לצד תוצאות המנוע המובנה. אוצריא שולחת
לתוסף אירוע ממוקד `search.external.requested` עם
`{ requestId, provider, query, mode, distance, offset, limit }` — ובבקשת
העמוד הראשון גם `indexTitles` — והתוסף עונה עם
`reader.respondExternalSearch`.

כשלטאב יש אפשרויות מילה פעילות (קידומות דקדוקיות, כתיב מלא/חסר וכו')
האירוע נושא גם `wordOptions` — מפת `'<מילה>_<אינדקס>' → { '<אפשרות>': true }`
באותו פורמט של `search.requested` — ובמצב "אפשרויות לכל המילים" גם
`options`, המפה הגלובלית שחלה על כל השאילתה. הספק מחיל מהן את מה שהמנוע
שלו תומך בו ומתעלם מהשאר. **העדיפו את `options` כשקיימת:** מפתחות
`wordOptions` נבנים לפי הטוקניזציה של מנוע אוצריא (מקף מפצל מילה — `בית-דין`
נשלח כ-`'בית_0'`,`'דין_1'`), וספק שמפרק את השאילתה אחרת לא יזהה אותם.
מארח ותיק אינו שולח את השדות.
שם ספק שייך לתוסף הראשון שרשם אותו; ניסיון של תוסף אחר לרשום אותו נדחה
עם `error.conflict`.

```javascript
await Otzaria.call('reader.registerExternalSearchProvider', {
  provider: 'hebrewbooks',
});

window.addEventListener('search.external.requested', async (event) => {
  const { requestId, query, offset, limit } = event.detail;
  const page = await searchMyEngine(query, offset, limit);
  await Otzaria.call('reader.respondExternalSearch', {
    requestId,
    results: page.items.map((item) => ({
      title: item.name,          // חובה
      meta: item.byline,         // אופציונלי — מחבר · מקום · שנה
      snippet: item.snippet,     // אופציונלי — טקסט רגיל; ההדגשה בצד אוצריא
      hitCount: item.hits,
      firstPage: item.firstPage, // מבוסס-1
      externalId: item.id,       // זהות חיצונית לפתיחת הספר
    })),
    totalBooks: page.totalBooks,
    totalHits: page.totalHits,
    hasMore: page.hasMore,
  });
});
```

לחיצה על תוצאה פותחת את הספר במציג המובנה לפי הזהות החיצונית
(`external: { provider, id }`) — מקומית כשהקובץ קיים, אחרת בדפדפן — ועם
עמודי ההתאמה כשהתוסף רשום גם כספק חיפוש-בתוך-ספר.

### `reader.respondExternalSearch`
**הרשאה:** `reader.open`

תשובת הספק לאירוע `search.external.requested`. חובה להעביר את `requestId`;
בכישלון מעבירים `error` במקום `results`. מגבלות: עד 50 תוצאות לעמוד,
כותרת עד 300 תווים, קטע טקסט עד 600.
התשובה מתקבלת רק מהתוסף שאליו הבקשה נשלחה.

**הזרמה:** מותר לענות כמה פעמים לאותה בקשה עם `done: false` — כל תשובה
כזו היא עדכון חלקי שמחליף את חלון העמוד במדור (הספירות נחשבות רף-תחתון),
והבקשה נשארת פתוחה. התשובה האחרונה נשלחת בלי `done` (או `done: true`)
וסוגרת את הבקשה. הטיימאוט (45 שניות) הוא חוסר-פעילות ומתאפס בכל עדכון
חלקי.

**אינדקס קטגוריות (אופציונלי):** על בקשת העמוד הראשון הספק יכול לצרף
`index` — מערך תמציתי של **כלל** תוצאות החיפוש (עד 20,000 רשומות), כל
רשומה `[id, hits]`, `[id, hits, categoryPath]` או
`[id, hits, categoryPath, title]` כשהנתיב הוא קטגוריית אוצריא משוערת
(מתחיל ב-'/', עד 200 תווים; מחרוזת ריקה כשיש שם בלי סיווג) והשם הוא שם
הספר (עד 300 תווים). אוצריא בונה מהאינדקס ספירות בעץ הקטגוריות של טאב
החיפוש, מעדנת מול קטלוג ההשוואות המקומי, ומציגה דלי "עוד מ<resultsTitle>"
לתוצאות ללא סיווג — ועם השמות הדלי נפתח לרשימת הספרים שבו, ולחיצה על ספר
מסננת אליו. עדכון בלי `index` אינו מוחק אינדקס שכבר נשלח באותה בקשה.

שלחו רשומות בנות ארבעה איברים **רק** כשהבקשה נשאה `indexTitles: true`:
מארח ותיק אינו מכיר את השם וזורק רשומה כזו בסניטציה, ואיתה כל הסיווג.
הדגל מגיע רק בבקשה שיכולה לשאת אינדקס (העמוד הראשון, בלי `ids`).

**דפדוף לפי מזהים:** כשמסוננת קטגוריה בעץ, אוצריא שולחת בקשות
`search.external.requested` עם שדה `ids` (עד 50 מזהים) במקום
`offset`/`limit` — הספק מחזיר את הספרים הללו בסדרם (מהמטמון של אותו
חיפוש; `hasMore: false`).

### `reader.openSearchTab`
**הרשאה:** `reader.open`

פותח כרטיסיית חיפוש מובנית עם השאילתה — כך תוסף מפנה חיפוש שהתחיל אצלו אל
מסך החיפוש הרגיל. `selectItems` (אופציונלי, עד 4 מזהים) מסמן שורות
`searchDialogItems` של התוסף הקורא בכרטיסייה החדשה; יחד עם `resultsProvider`
זה מפעיל בה את מדור התוצאות החיצוני. מפתחות הבחירה נגזרים תמיד מה-pluginId
של הקורא — תוסף אינו יכול לסמן שורות של תוסף אחר.

`autoSearch` (אופציונלי, ברירת מחדל `true`) — כש-`false` הכרטיסייה נפתחת עם
השאילתה בשדה החיפוש **מבלי להריץ את החיפוש**; המשתמש מפעיל אותו ידנית
(Enter או כפתור החיפוש). שימושי כשהתוסף רוצה להראות למשתמש את השאילתה
ולאפשר לו לערוך אותה לפני ההרצה. בשני המקרים השאילתה מוצגת בשדה וניתנת
לעריכה.

`settings` (אופציונלי) — הגדרות החיפוש איתן תיפתח הכרטיסייה: מצב, מרחק,
מדיניות התאמה ואפשרויות מילה. הפרמטרים והערכים זהים ל-`search.query` (ראו
`search.getOptions` לערכים החוקיים), ומפתחות `wordOptions` פר-מילה נבדקים
מול פיצול מילות השאילתה.

```javascript
await Otzaria.call('reader.openSearchTab', {
  query: 'ברכת המזון',
  selectItems: ['include-hebrewbooks'],
});
// true

// פתיחה עם הטקסט בשדה בלי להריץ, והגדרות חיפוש קבועות מראש:
await Otzaria.call('reader.openSearchTab', {
  query: 'ואהבת לרעך',
  autoSearch: false,
  settings: {
    mode: 'advanced',
    distance: 2,
    proximityScope: 'sameParagraph',
    wordMatchMode: 'all',
    options: { 'קידומות דקדוקיות': true },
  },
});
```

**פרמטרים של `settings`**

| פרמטר | ברירת מחדל | משמעות |
|-------|-----------|--------|
| `mode` | `'advanced'` | `'exact'` \| `'advanced'` \| `'fuzzy'` |
| `distance` | `0` | מרווח מילים בין מילות החיפוש; במצב `'fuzzy'` הטווח 0–2 |
| `proximityScope` | `'wordDistance'` | `'wordDistance'` \| `'sameParagraph'` \| `'sameSection'` |
| `wordMatchMode` | `'all'` | `'all'` \| `'anyWord'` \| `'mostWords'` \| `'atLeast'` |
| `wordMatchCount` | `2` | חוקי רק עם `mode: 'advanced'` ו-`wordMatchMode: 'atLeast'` |
| `options` | `{}` | אפשרויות מילה שחלות על כל מילות השאילתה (למשל `'קידומות דקדוקיות'`) |
| `wordOptions` | `{}` | אפשרויות פר-מילה במפתח `"{מילה}_{אינדקס}"`; גובר על `options` |

שגיאות אפשריות: `error.invalid_params` (פרמטר או ערך לא מוכר, פרמטר שאינו
נתמך במצב שנבחר, או מפתח פר-מילה שאינו תואם לשאילתה).

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
//       id: 183,          // מזהה מספרי
//       type: "text",     // סוג הספר
//       source: "library", // מקור הספר
//       bookId: "בראשית",
//       book: "בראשית",
//       index: 42,
//       currentRef: "בראשית פרק ג"
//     },
//     {
//       id: 204,
//       type: "pdf",
//       source: "library",
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

### `reader.getActiveCommentators`
**הרשאה:** `reader.open` · **מגרסה:** 0.9.97

מצב המפרשים של טאב הקריאה הנוכחי, כפי שהוא כבר טעון בו — ללא פרמטרים וללא
שאילתה נוספת. `null` כשאין טאב קריאה, כשהטאב עדיין נטען או כשאין בו מפרשים.

בטאב PDF אין מצב מפרשים מלא: `available` נגזר מהקישורים שכבר נטענו לטאב,
ו-`rare`/`groups` חוזרים ריקים. לרשימה המלאה קראו ל-`library.getCommentators`
עם כותרת הספר.

```javascript
const { data } = await Otzaria.call('reader.getActiveCommentators');
// {
//   available: ["רש״י על בראשית", "רמב״ן על בראשית", ...],
//   active:    ["רש״י על בראשית"],
//   rare:      ["ספר נדיר"],
//   groups:    [{ title: "ראשונים", commentators: ["רש״י על בראשית", ...] }]
// }
```

### `reader.setActiveCommentators`
**הרשאה:** `reader.open` · **מגרסה:** 0.9.97

מוסיף ומסיר מפרשים בטאב הקריאה הנוכחי. הפעולה מצטברת על הבחירה הקיימת —
`add` מוסיף בסוף הסדר הקיים ו-`remove` מסיר; יש להעביר לפחות אחד מהם.
מחזיר את אותה מבנה של `reader.getActiveCommentators` אחרי השינוי, או `null`
כשאין טאב טקסט טעון (כולל PDF — שם הבחירה אינה נתמכת לכתיבה).

שם שאינו ב-`available` של הספר נדחה ב-`error.not_found`, כדי שלא תישמר
בחירה שאין לה מפרש.

```javascript
await Otzaria.call('reader.setActiveCommentators', {
  add: ['רש״י על בראשית'],
  remove: ['רמב״ן על בראשית']
});
```

### `reader.scrollToSection`
**הרשאה:** `reader.open` · **מגרסה:** 0.9.97

גולל את הספר ה**פתוח** לקטע, בלי לפתוח אותו מחדש ובלי לדרוש הדגשה. בספר
טקסט `sectionIndex` הוא אינדקס השורה (מבוסס-0); ב-PDF זהו מספר העמוד
(מבוסס-1) — אותה סמנטיקה של `currentIndex` ב-`reader.getCurrentState`.

`highlight: true` מסמן גם את הקטע; ברירת המחדל `false` מנקה סימון קיים.
מחזיר `false` כשאין חלונית קריאה, או ב-PDF שהצפיין שלו עדיין לא מוכן.

```javascript
await Otzaria.call('reader.scrollToSection', { sectionIndex: 42 });
```

### `reader.getHighlightCapabilities`
**הרשאה:** `reader.open` · **מגרסה:** 0.9.97

מה נתמך **בפועל** בהקשר הקריאה הנוכחי, כדי שתוסף לא ינסה פעולה שאינה
קיימת במשטח שבו המשתמש נמצא. הדגשות מצוירות רק בטור הטקסט הראשי — לא
בחלוניות המפרשים — ו-PDF אינו תומך בהדגשות, בבחירת טקסט ובפריטי תפריט הקשר.

| שדה | משמעות |
|-----|--------|
| `surface` | `'combined'` \| `'pageShape'` \| `'pdf'` \| `null` |
| `highlights` | האם `reader.setHighlight` ייראה במשטח הזה |
| `selection` | האם `reader.getSelection` יכול להחזיר בחירה |
| `contextMenu` | האזורים שבהם פריטי `reader.addContextMenuItem` מוצגים |

```javascript
const { data } = await Otzaria.call('reader.getHighlightCapabilities');
if (data.highlights) { /* ... */ }
// { surface: 'combined', highlights: true, selection: true,
//   contextMenu: ['mainText'] }
```

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

> **`includeDomRects` שמור לעתיד ואינו נתמך.** הפרמטר מתקבל ומאומת כבוליאני,
> אך `true` נדחה תמיד ב-`error.unsupported_context`. השאירו אותו `false`
> או השמיטו אותו.

---

## navigation.* - ניווט באפליקציה

### `navigation.goTo`
**הרשאה:** `navigation.write`

מעבר למסך ראשי באפליקציה.

```javascript
const { data } = await Otzaria.call('navigation.goTo', {
  target: 'library'  // 'library' | 'reading' | 'more' | 'settings'
  // 'more' נשמר לתאימות אחורה — פותח כיום את פאנל הכלים.
  // הכלים והתוספים עצמם חיים ככרטיסיות בתוך 'reading'.
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
- לפתיחת תוסף אחר יש API נפרד — `plugin.openOther`.

---

### `plugin.openOther`
**הרשאה:** `plugin.open_other` | **מגרסה:** 0.9.97

פותח את דף של תוסף **אחר** המותקן אצל המשתמש, עם פרמטר אופציונלי שיימסר לו.
מיועד לתוספים משלימים — למשל תוסף אינדקס שמעביר מקור לתוסף מציג.

```javascript
await Otzaria.call('plugin.openOther', {
  pluginId: 'com.example.viewer',
  param: { ref: 'בראשית א׳ א׳' }      // כל ערך JSON (אופציונלי)
});
// true
```

התוסף הנפתח מקבל `plugin.page_opened` — עם `openedBy` שמזהה מי פתח אותו:

```javascript
Otzaria.on('plugin.page_opened', (data) => {
  if (data.openedBy) {
    // נפתח בידי תוסף אחר; ללא השדה — המשתמש או openSelf
  }
});
```

**הערות:**
- ההרשאה נפרדת מ-`navigation.write` כי הקריאה **מפעילה את הקוד** של תוסף שלישי,
  ולא רק מזיזה את המשתמש בין מסכים. המשתמש רואה אותה בשמה בעת ההתקנה.
- `pluginId` שאינו מותקן מחזיר `error.not_found`. תוסף מותקן שאינו זמין כרגע
  (מושבת, מוסתר מהכלים, או דורש רשת במצב מנותק) מחזיר `true`, והמשתמש מקבל
  הודעה מדויקת על הסיבה — אותה התנהגות כמו כל פתיחת כלי אחרת.
- אין כאן ערוץ קריאה: הפרמטר נמסר בכיוון אחד. תוסף היעד רשאי להתעלם ממנו,
  והוא פועל בהרשאות שלו בלבד — לא בשל הקורא.
- כלים מובנים (לוח שנה, גימטריה וכד') אינם נפתחים בערוץ הזה.

---

### `plugin.backgroundDone`
**הרשאה:** אין | **מגרסה:** 0.9.97

מופע רקע שהוער בעצלנות (`contributes.startup`) מכריז שסיים את עבודתו —
ואוצריא מכבה אותו מיד, בלי להמתין לשעון חוסר-הפעילות (3 דקות). זהו הסיום
האידיומטי לעבודה חד-פעמית כמו בדיקת עדכונים ב-`app.startup`:

```javascript
Otzaria.on('plugin.boot', async (payload) => {
  if (payload.app.runMode !== 'background') return;
  try {
    await checkForUpdates(payload);
  } finally {
    await Otzaria.call('plugin.backgroundDone');  // כיבוי מיידי
  }
});
// true — הכיבוי תוזמן; false — הקריאה לא חלה (ראו הערות)
```

**הערות:**
- חל **רק על מופע רקע שהוער עצל**. קריאה מדף התוסף הנראה, או ממופע רקע
  של המסלול הישן (טעינה בעלייה), היא no-op בטוח שמחזיר `false` — דף
  התוסף ותוספים אחרים לעולם אינם מושפעים.
- אם בינתיים החלה עבודה חדשה (RPC פתוח או אירוע ממתין) — הכיבוי נדחה
  לשעון הרגיל במקום לקטוע אותה.
- אין צורך לקרוא לזה אחרי טיפול באירוע רגיל — שעון חוסר-הפעילות מטפל בזה;
  זה קיצור לעבודות חד-פעמיות שמסיימות מהר.

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

**הודעה לחיצה (מגרסה 0.9.97):** העברת `tapPayload` (ואופציונלית `tapEvent`)
הופכת את ההודעה ללחיצה — לחיצה עליה משגרת לתוסף את האירוע `ui.messageClicked`
(או שם מותאם שנמסר ב-`tapEvent`, באותיות/ספרות/נקודה/מקף/קו תחתון בלבד)
עם `{ payload: tapPayload }`. זמין גם ב-`ui.showSuccess` וב-`ui.showError`.

עם `tapOpenPlugin: true` הלחיצה גם **מנווטת את המשתמש לדף התוסף**, והאירוע
נמסר לדף — גם אם הוא נטען רק עכשיו (כמו `openPlugin` בתפריט ההקשר). זו הדרך
הנכונה להודעה ממופע רקע, שהמנוע שלו כבר עשוי להיות כבוי בזמן הלחיצה.

```javascript
await Otzaria.call('ui.showMessage', {
  message: 'הסנכרון הסתיים — לחצו לפרטים',
  tapPayload: { syncId: 42 }
});

Otzaria.on('ui.messageClicked', (data) => {
  console.log(data.payload.syncId); // 42
});
```

### `ui.showSuccess`
**הרשאה:** `ui.feedback`

הצגת הודעת הצלחה. תומכת ב-`tapEvent`/`tapPayload` כמו `ui.showMessage`.

```javascript
await Otzaria.call('ui.showSuccess', {
  message: 'הנתונים נשמרו'
});
```

### `ui.showError`
**הרשאה:** `ui.feedback`

הצגת הודעת שגיאה. תומכת ב-`tapEvent`/`tapPayload` כמו `ui.showMessage`.

```javascript
await Otzaria.call('ui.showError', {
  message: 'אירעה שגיאה'
});
```

### Event: `ui.messageClicked`
**הרשאה:** אין צורך בהרשאה נוספת — נשלח רק לתוסף שהציג את ההודעה

נורה כאשר המשתמש לוחץ על הודעה שהתוסף הציג עם `tapPayload`. שם האירוע
ניתן להחלפה דרך `tapEvent` בקריאת ההצגה.

```javascript
Otzaria.on('ui.messageClicked', (data) => {
  console.log('payload:', data.payload); // הערך שנמסר ב-tapPayload (null אם לא נמסר)
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
**הרשאה:** `fs.folder_access` (מ-0.9.97; הצהרה ותיקה על `ui.feedback` עדיין מכסה)

פתיחת דיאלוג מערכת לבחירת תיקייה. מחזירה את הנתיב שנבחר, או `{ path: null }`
אם המשתמש ביטל.

מעבר להחזרת הנתיב, בחירת התיקייה **מעניקה לתוסף הרשאת כתיבה/מחיקה בתוכה**:
מכאן ואילך מותר לו להוריד אליה (`network.download` עם `destPath`), לחלץ
אליה (`fs.extractZip`) ולמחוק קבצים בתוכה (`fs.deleteFile`). זהו גבול
האבטחה לגישת התוסף לדיסק — היא נובעת מהסכמת המשתמש בדיאלוג, לא מהרשאת
manifest. ההרשאה לתיקייה תקפה למשך ריצת התוסף.

**תיקיות מוגנות:** בחירה בתיקייה רגישה נדחית עם `error.forbidden` — כלומר
`ui.pickFolder` יכולה גם להיכשל, לא רק להחזיר `path: null`. נדחים:

- שורש כונן (`C:\`, `/`), ותיקיית רשת (נתיב UNC).
- תיקיית הבית של המשתמש עצמה (תת-תיקייה בתוכה, כמו `Documents\MyPlugin`, מותרת).
- `Program Files`, `ProgramData`, `SystemRoot`, תיקיית ה-Startup — ובלינוקס/מק
  `/etc`,‏ `/usr`,‏ `/bin`,‏ `/System`,‏ `/Library`,‏ `~/.ssh`,‏ `~/.config`.
- תיקיית ההרצה של אוצריא, תיקיית הנתונים שלה ותיקיית הספרייה.
- **כל אלה חלים גם על תת-תיקיותיהן** (למעט תיקיית הבית, שהיא בדיקה מדויקת).

הפנו את המשתמש לתיקייה ייעודית — למשל תיקייה חדשה תחת `Documents`.

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

## fs.* - המרחב הפרטי של התוסף (מ-0.9.97)

> **אין צורך בשום הרשאה.** לכל תוסף יש תיקייה פרטית משלו, והוא כותב וקורא בה
> בחופשיות. **אל תבקשו `fs.folder_access` בשביל קבצי עבודה** — היא נועדה לעבוד
> בתיקייה של המשתמש, וזו ההרשאה הרחבה ביותר במערכת.
>
> כל הנתיבים ב-API הזה הם **יחסיים לשורש הפרטי**, ומופרדים ב-`/`. נתיב שיוצא
> מהשורש — `..`, נתיב מוחלט או כתובת רשת (UNC) — נדחה ב-`error.forbidden`.
> **כל רכיב symlink בנתיב נדחה**, בין אם יעדו בתוך השורש ובין אם מחוצה לו.
> הנתיב המוחלט על הדיסק אינו נחשף לתוסף.
>
> **מכסה:** 100MB לכל תוסף. חריגה מוחזרת כ-`error.too_large`. `writeFile`
> ו-`listDir` מחזירים `usedBytes`/`quotaBytes` כדי לעקוב.
>
> **תקרת רשומות:** 10,000 קבצים ותיקיות, ועומק עד 32 רמות. קובץ ריק ותיקייה
> אינם צורכים בתים, ולכן המכסה לבדה לא הגבילה את מספרם. חריגה מוחזרת
> כ-`error.too_large`.
>
> **תקרת העברה:** 10MB לקריאה או כתיבה בודדת — הגשר מעביר את התוכן כמחרוזת
> JSON. לקבצים גדולים יותר יש `fs.pickUserFile` ושרת הקבצים.
>
> התיקייה נמחקת בהסרת התוסף, ונכללת בגיבוי ובשחזור של אוצריא.

### `fs.writeFile`
**הרשאה:** (אין)

כתיבת קובץ. תיקיות האב נוצרות לפי הצורך. `encoding` הוא `'utf8'` (ברירת מחדל)
או `'base64'` לתוכן בינארי. `append: true` מוסיף לסוף קובץ קיים — גם אז המכסה
נאכפת על סך המרחב.

```javascript
const { data } = await Otzaria.call('fs.writeFile', {
  path: 'cache/index.json',
  content: JSON.stringify({ updated: Date.now() })
});
// data = { path, size, usedBytes, quotaBytes }
```

### `fs.readFile`
**הרשאה:** (אין)

```javascript
const { data } = await Otzaria.call('fs.readFile', { path: 'cache/index.json' });
// data = { path, encoding: 'utf8', size, content: '{"updated":...}' }
```

`encoding: 'base64'` מחזיר את הבייטים כ-base64. קובץ שאינו קיים מוחזר עם
`error.not_found`.

### `fs.listDir`
**הרשאה:** (אין)

פירוט תיקייה. `path` ריק או חסר = שורש המרחב. תיקיות מופיעות לפני קבצים.

```javascript
const { data } = await Otzaria.call('fs.listDir', { path: 'cache' });
// data.entries = [{ path: 'cache/index.json', name: 'index.json',
//                   type: 'file', size: 42, modified: '2026-08-24T...Z' }]
```

### `fs.makeDir`
**הרשאה:** (אין)

יוצר תיקייה וכל האבות שלה. idempotent.

```javascript
await Otzaria.call('fs.makeDir', { path: 'cache/images' });
// true
```

### `fs.deleteEntry`
**הרשאה:** (אין)

מוחק קובץ או תיקייה. מחזיר `true` אם נמחק משהו ו-`false` אם הנתיב לא היה
קיים (idempotent). מחיקת תיקייה **לא ריקה** דורשת `recursive: true`, אחרת
מוחזר `error.invalid_params`. מחיקת השורש עצמו אינה אפשרית.

```javascript
await Otzaria.call('fs.deleteEntry', { path: 'cache', recursive: true });
```

### `fs.stat`
**הרשאה:** (אין)

```javascript
const { data } = await Otzaria.call('fs.stat', { path: 'cache/index.json' });
// { exists: true, path, name, type: 'file', size, modified }
// או { exists: false }
```

שגיאות אפשריות: `error.forbidden` (נתיב שיוצא מהשורש),
`error.invalid_params` (פרמטר חסר, קידוד לא מוכר, נתיב שהוא תיקייה בכתיבה,
תיקייה לא ריקה במחיקה), `error.not_found` (קריאה מקובץ שאינו קיים),
`error.too_large` (חריגה מהמכסה או מתקרת ההעברה), `error.internal`.

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
  extensions: ['pdf'], // אופציונלי
  access: 'read'       // אופציונלי: 'read' (ברירת מחדל) או 'readwrite'
});
// res.data = { cancelled: false, token, url, name, size, access }  — או { cancelled: true }
if (res.success && !res.data.cancelled) {
  await Otzaria.call('storage.set', { key: 'lastFile', value: res.data.token });
  document.querySelector('iframe').src = res.data.url;
}
```

`access: 'readwrite'` (מגרסה 0.9.97) מבקש token שאפשר לכתוב אליו בחזרה דרך
[`fs.commitUserFileWrite`](#fscommituserfilewrite), בלי דיאלוג נוסף. הוא דורש
**גם** את ההרשאה `fs.user_files.write`, ובלעדיה מוחזר `error.permission_denied`.
קריאה בלי `access` מקבלת token לקריאה בלבד, בדיוק כמו קודם.

### `fs.resolveFileUrl`
**הרשאה:** `fs.user_files.read`

בונה URL טרי לקובץ שכבר אושר, לפי ה-`token` שנשמר. נצרך אחרי טעינה מחדש של
התוסף (הפורט של השרת משתנה בכל הפעלה). מחזיר `error.not_found` אם ה-`token`
לא מוכר או שהקובץ נמחק.

> שמרו את ה-`token` בלבד, לעולם לא את ה-`url` — מבנה ה-URL אינו חוזה יציב,
> ו-URL שנשמר מהפעלה קודמת יפסיק לעבוד.

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

### `fs.beginBinaryWrite`
**הרשאה:** `fs.user_files.write` · מגרסה 0.9.97

פותח העלאה ומחזיר לאן לשלוח את הבייטים. **הבייטים אינם עוברים בגשר ה-JS** —
העברת קובץ כ-base64 ב-JSON-RPC מכפילה את הזיכרון ותוקעת את הממשק. במקום זה
התוסף שולח `PUT` יחיד לשרת ה-loopback הפנימי, והכתיבה לדיסק נעשית רק
ב-[`fs.commitUserFileWrite`](#fscommituserfilewrite).

```javascript
const { data } = await Otzaria.call('fs.beginBinaryWrite', {
  purpose: 'user-file',      // הערך הנתמך היחיד כרגע
  expectedSize: blob.size    // אופציונלי; נדחה מעל maxBytes
});
// data = { writeToken, uploadUrl, expiresAt, maxBytes }

await fetch(data.uploadUrl, {
  method: 'PUT',
  headers: { 'Content-Type': blob.type },
  body: blob
});
```

מגבלות: 100MB להעלאה, שתי העלאות פעילות לכל תוסף, וה-`writeToken` פג תוך שתי
דקות. העלאה שנמצאת ב-commit — כלומר דיאלוג „שמור בשם” פתוח — ממשיכה לתפוס
מקום במכסה עד שה-commit מסתיים, ואינה פגה בזמן הזה: המשתמש יכול להשאיר את
הדיאלוג פתוח כמה שירצה. ה-`PUT` חייב לכלול `Content-Length` (`fetch` עם `body: blob` עושה זאת
לבד), הוא חד-פעמי, והוא היחיד שמותר על ה-URL הזה. גוף חלקי או חורג נמחק ואינו
יכול להפוך למסמך שנשמר.

`purpose` חסר נחשב `'user-file'`. `expectedSize` הוא אופציונלי ומשמש לדחייה
מוקדמת בלבד — המגבלה נאכפת בכל מקרה על ה-`Content-Length` ועל הבייטים בפועל.

שגיאות: `error.too_large` (`expectedSize` מעל המגבלה), `error.invalid_params`
(`expectedSize` אינו חיובי), `error.too_many_requests` (יותר משתי העלאות),
`error.unsupported` (`purpose` אחר), `error.permission_denied`.

תשובות ה-`PUT`: `204` הצלחה · `404` token לא מוכר · `410` פג · `409` העלאה שנייה
על אותו token · `411` חסר `Content-Length` · `413` מעל המגבלה · `400` גוף קטוע.

### `fs.commitUserFileWrite`
**הרשאה:** `fs.user_files.write` · מגרסה 0.9.97

כותב העלאה שהושלמה אל קובץ של המשתמש. שני מסלולים:

- **עם `targetToken`** — token שהתקבל מ-`pickUserFile({ access: 'readwrite' })`
  או מ-commit קודם. נכתב במקום, בלי דיאלוג. זה „שמור”.
- **בלי `targetToken`** — נפתח דיאלוג „שמור בשם”. זה גם המסלול של token
  שנפתח לקריאה בלבד: הוא **אינו** יעד כתיבה חוקי ומוחזר עליו
  `error.permission_denied`.

```javascript
// שמור בשם
const { data } = await Otzaria.call('fs.commitUserFileWrite', {
  writeToken: data.writeToken,
  suggestedName: 'חידושים',
  extension: 'docx',
  title: 'שמירת המסמך'   // אופציונלי, כותרת הדיאלוג
});
// data = { cancelled: false, token, name, size }  — או { cancelled: true }

// שמור (לאותו קובץ, בלי דיאלוג)
await Otzaria.call('fs.commitUserFileWrite', {
  writeToken: next.writeToken,
  targetToken: data.token
});
```

הכתיבה נעשית ל-staging באותה תיקייה כמו היעד, ואז מחליפה אותו ב-rename.
**מה שמובטח: כשל אינו הורס את הקובץ הקיים.** אין מסלול שכותב ישירות על היעד —
rename שנכשל מחזיר שגיאה, ולא מתדרדר להעתקה. אטומיות ההחלפה עצמה תלויה במערכת
הקבצים ואינה מובטחת על ידי Dart; היא מתקיימת ב-POSIX באותו volume וב-Windows
דרך החלפה. ביטול הדיאלוג מחזיר `{ cancelled: true }`,
מוחק את ההעלאה ואינו משנה שום הרשאה. ההעלאה נשארת בבעלות המערכת עד שה-commit
מסתיים — כולל כל הזמן שהדיאלוג פתוח — ולכן היא אינה פגה תחת ידיו של המשתמש
ואינה נשארת יתומה אם התוסף נסגר באמצע. ה-token שחוזר הוא token לכתיבה, כך
שהשמירה הבאה יכולה להשתמש בו כ-`targetToken`.

`extension` חייב להיות סיומת ממש (אותיות/ספרות, עד 10 תווים); כל דבר אחר
מתעלמים ממנו, כדי שלא ייקבע דרכו נתיב או שם מלא בדיאלוג.

שגיאות: `error.not_found` (העלאה לא מוכרת, לא הושלמה, פגה או נצרכה כבר; או
קובץ יעד שנמחק), `error.permission_denied` (token לקריאה בלבד),
`error.invalid_params` (`writeToken` חסר, או נתיב יעד שלא ניתן לפתור).

הערת תאימות: ברגע שקובץ נבחר בגרסה שתומכת ב-`access`, ה-grant שלו נשמר בצורה
החדשה. גרסה קודמת של אוצריא תמשיך לקרוא grants ותיקים שלא נשמרו מחדש, אך לא את
החדשים.

### `fs.abortBinaryWrite`
**הרשאה:** `fs.user_files.write` · מגרסה 0.9.97

מבטל העלאה שטרם נכתבה, ומשחרר מיד את הקובץ הזמני ואת מקומה במכסה. נצרך כשהתוסף
מחליט שההעלאה אינה רלוונטית יותר — למשל שמירה שהמסמך שלה הוחלף באמצע. בלי
הקריאה הזאת ההעלאה נתפסת עד שה-`writeToken` פג (שתי דקות).

```javascript
await Otzaria.call('fs.abortBinaryWrite', { writeToken });
// data = true
```

אידמפוטנטי: `true` גם כשלא היה מה לבטל. מחזיר `false` כשה-`writeToken` שייך
לתוסף אחר, או כש-[`fs.commitUserFileWrite`](#fscommituserfilewrite) שלו כבר רץ —
ביטול באמצע commit היה מוחק את הקובץ מתחת לדיאלוג „שמור בשם” פתוח.

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

### `feedback.report`
**הרשאה:** אינה נדרשת — הדיווח נשלח רק אחרי אישור המשתמש בדיאלוג, וההסכמה בדיאלוג היא גבול האבטחה.

שליחת דיווח של המשתמש על התוסף לאתר אוצריא. האתר מזהה את מפתח התוסף ומעביר לו את הדיווח.

```javascript
const { data } = await Otzaria.call('feedback.report', {
  details: 'התוסף קורס בפתיחת ספר',
  reportType: 'bug',            // אופציונלי: bug | crash | content | other
  reporterEmail: 'me@example.com' // אופציונלי
});
// 'sent' — נשלח | 'queued' — נשמר לשליחה מאוחרת | 'cancelled' — המשתמש ביטל
```

**פרמטרים:**
- `details` (חובה) - תוכן הדיווח; נחתך ל-5000 תווים
- `reportType` (אופציונלי) - `bug` / `crash` / `content` / `other`; ערך לא מוכר מתורגם ל-`other`, וברירת המחדל היא `other`
- `reporterEmail` (אופציונלי) - כתובת המשתמש לחזרה. **הכתובת השמורה בהגדרות דיווח השגיאות גוברת תמיד**: הפרמטר משמש רק כשאין כתובת שמורה (ואם שניהם ריקים — לא נשלחת כתובת כלל). בדקו מראש עם `feedback.hasReporterEmail` אם בכלל צריך לבקש כתובת מהמשתמש

**דיאלוג אישור:** לפני השליחה מוצג למשתמש דיאלוג עם שם התוסף, יעד הדיווח ותצוגה מקדימה של הטקסט. אין דרך לעקוף אותו.

**החזרה:** `'sent'` — הדיווח נשלח לשרת; `'queued'` — הדיווח נשמר בתור מקומי ויישלח אוטומטית כשיהיה חיבור; `'cancelled'` — המשתמש ביטל בדיאלוג.

**תור שליחה מאוחרת:** במצב לא-מקוון או בכשל רשת זמני הדיווח נשמר בתור מקומי (באותו מנגנון של דיווחי הטעויות בספרים): ניסיון חוזר אוטומטי כל 5 דקות, והמשתמש יכול לנהל את התור בהגדרות — לשלוח ידנית, למחוק, או להוריד סקריפט שליחה למחשב מחובר.

**שגיאות אפשריות:** `error.invalid_params` — `details` חסר או ריק. `error.internal` — דחייה קבועה של השרת (HTTP 400/422), או מצב לא-מקוון כשהמשתמש כיבה את תור הדיווחים בהגדרות. דחייה קבועה אינה נכנסת לתור.

### `feedback.hasReporterEmail`
**הרשאה:** אינה נדרשת — מוחזר ביט קיום בלבד, בלי הכתובת עצמה.

בדיקה האם למשתמש שמורה כתובת מייל לחזרה בהגדרות דיווח השגיאות. שימושי לפני `feedback.report`: כשקיימת כתובת שמורה אין טעם לבקש כתובת מהמשתמש — היא גוברת בכל מקרה. הכתובת עצמה לעולם אינה נחשפת לתוסף.

```javascript
const { data } = await Otzaria.call('feedback.hasReporterEmail');
// true — קיימת כתובת שמורה | false — אין
```

**החזרה:** `boolean`.

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

## bookmarks.* - סימניות

הסימניות של המשתמש. הקריאה והכתיבה הן שתי הרשאות נפרדות, כמו
`notes.read`/`notes.write`.

### `bookmarks.list`
**הרשאה:** `bookmarks.read` · **מגרסה:** 0.9.97

```javascript
const { data } = await Otzaria.call('bookmarks.list', { limit: 50 });
// [{ id, type, source, title: 'בראשית', ref: 'בראשית, פרק א',
//    index: 0, label: 'בראשית ברא', targetKind: 'book',
//    createdAt: '2026-08-24T10:00:00.000' }]
```

### `bookmarks.add`
**הרשאה:** `bookmarks.write` · **מגרסה:** 0.9.97

הספר מזוהה כמו בכל API אחר (`id` או `bookId`). כש-`ref` אינו נמסר הוא
מחושב מתוכן העניינים של הספר, בדיוק כמו סימנייה שהמשתמש הוסיף מהתפריט.
מחזיר `false` כשהספר לא נמצא **או** כשכבר קיימת סימנייה זהה (אותו ספר
ואותו `index`) — אין כפילויות.

```javascript
await Otzaria.call('bookmarks.add', {
  bookId: 'בראשית',
  index: 12,
  label: 'להמשיך מכאן'   // אופציונלי
});
```

### `bookmarks.remove`
**הרשאה:** `bookmarks.write` · **מגרסה:** 0.9.97

מוחק את הסימנייה הראשונה שמתאימה לזהות. בלי `index` — הראשונה של הספר.

```javascript
await Otzaria.call('bookmarks.remove', { bookId: 'בראשית', index: 12 });
// true או false
```

---

## tools.* - כלי עזר מובנים

**הרשאה:** `tools.read` — נתוני עזר של התוכנה בלבד, ללא גישה לנתוני המשתמש.

### `tools.gematria`
**מגרסה:** 0.9.97

חישוב גימטריה של מחרוזת. `method` הוא `'regular'` (ברירת מחדל), `'small'`
או `'finalLetters'`; `withKolel: true` מוסיף את מספר המילים ("עם הכולל").
תווים שאינם אותיות עבריות מתעלמים. מגבלה: 2000 תווים.

```javascript
const { data } = await Otzaria.call('tools.gematria', { text: 'אברהם' });
// { value: 248, method: 'regular', words: 1 }
```

> חיפוש הפוך (ערך → מילים) אינו נחשף: הוא סורק את ספרי הספרייה ואינו
> פעולה זולה. לצורך זה השתמשו ב-`search.query`.

### `tools.dictionary`
**מגרסה:** 0.9.97

חיפוש מונח במילוני העזר המצורפים לתוכנה: ראשי תיבות ומילון ארמית.
`acronyms` מחזיר התאמה מדויקת, ואם אין — התאמות קידומת. `hebrew` בערכי
הארמית הוא טקסט עם סימון מקורי. מגבלה: 200 תווים.

```javascript
const { data } = await Otzaria.call('tools.dictionary', { term: 'רמב״ם' });
// { term: 'רמב״ם',
//   acronyms: [{ acronym: 'רמב״ם', meanings: ['רבי משה בן מיימון'] }],
//   aramaic: [] }
```

> לעזי רש"י אינם נכללים: הם נקראים ממסד הנתונים של הספרייה ומטבלת
> הקישורים, ולא ממילון מצורף.

---

## notifications.* - התראות

### `notifications.showInApp`
**הרשאה:** `notifications.send`

הצגת התראה בתוך האפליקציה (UiSnack).

> **Alias:** זו למעשה כפילות של `ui.showMessage` (עם `type` שבוחר בין
> info/success/error). היא נשמרת לתאימות אחורה; לקוד חדש עדיפות משפחת
> `ui.show*`. שימו לב שההרשאה שונה — כאן `notifications.send` ולא `ui.feedback`.

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

**התראה לחיצה (מגרסה 0.9.97):** נתמכים אותם `tapEvent`/`tapPayload`/`tapOpenPlugin`
כמו ב-`ui.showMessage` — שימושי במיוחד להתראה ממופע רקע שמזמינה את המשתמש
לפתוח את דף התוסף בלחיצה:

```javascript
await Otzaria.call('notifications.showInApp', {
  message: 'יש עדכונים — לחצו לפתיחה',
  type: 'info',
  tapOpenPlugin: true
});
```

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

> ⚠️ **המסלול הוא `storage.*`, ההרשאה היא `plugin.storage.*`.** קל לטעות
> ולקרוא ל-`plugin.storage.get`: הנתב מפצל על הנקודה הראשונה, אינו מוצא
> מסלול, והקריאה נכשלת בשקט אם התוסף אינו בודק את `success` — כל ההעדפות
> פשוט אינן נשמרות. **קראו תמיד `storage.get` / `storage.set` /
> `storage.remove` / `storage.list`**; `plugin.storage.*` הוא שם ההרשאה
> במניפסט בלבד.

### `storage.get`
**הרשאה:** `plugin.storage.read`

קריאת ערך שמור.

```javascript
const { data } = await Otzaria.call('storage.get', {
  key: 'myData'
});
// כל ערך JSON או null
```

`data` הוא **הערך עצמו**, לא `{ value }` עטוף. מפתח שאינו קיים מחזיר `null`.

### `storage.set`
**הרשאה:** `plugin.storage.write`

שמירת ערך.

```javascript
await Otzaria.call('storage.set', {
  key: 'myData',
  value: { count: 42, name: 'test' }
});
```

> **אי אפשר לשמור `null`.** `value` חייב להיות שונה מ-`null`, אחרת חוזרת
> `error.invalid_params`. למחיקת ערך השתמשו ב-`storage.remove` — `null`
> חוזר ממילא מ-`storage.get` על מפתח שאינו קיים.

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

### מה מותר לקרוא (השתנה ב-0.9.97)

עד 0.9.97 הייתה רשימת היתר סגורה של ~19 מפתחות. **מ-0.9.97 הכלל הפוך:** כל
הגדרה קריאה, למעט מה שחסום מטעמי פרטיות ואבטחה. כך העדפת תצוגה חדשה זמינה
לתוספים מיד, בלי להמתין לרליס.

**חסום לקריאה:**

- כל מפתח שבשמו `password`, `secret`, `credential`, `token`, `api-key`,
  `client-id` — סודות ואסימונים.
- כל מפתח שבשמו `path`, `folder`, `root` — נתיבים במערכת הקבצים (כולל
  `key-library-path`, `key-index-path`, `key-backup-path`,
  `key-hebrew-books-path`, `key-custom-folders`). נתיב חושף את שם המשתמש ואת
  מבנה הדיסק; לעבודה על קבצים יש את המרחב הפרטי ואת `ui.pickFolder`.
- כל מפתח שבשמו `email` — כתובת המייל של המשתמש. היא נקראת רק דרך
  `app.getUserEmail` עם ההרשאה `app.user_email.read`.
- `key-google-calendar-*` — חשבון Google של המשתמש.
- `key-calendar-event*` — אירועי לוח השנה. נקראים דרך `calendar.getEvents`
  עם ההרשאה `calendar.read`.
- `key-protected-mode-*`, `sz:*` (ספרים במעקב והתקדמות "שמור וזכור").
- `page_shape_book_*`, `page_shape_highlight_*`, `page_shape_visibility_*`,
  `page_shape_use_book_settings_*`, `page_shape_view_mode_*`,
  `page_shape_category_*` — שם הספר או הקטגוריה הוא חלק מהמפתח, ולכן קריאתם
  חושפת מה המשתמש לומד. ‎`page_shape_global_visibility_*`‎ **כן** קריא — הוא
  העדפת תצוגה גלובלית בלי זהות ספר.
- `key-shortcut-open-plugin-*` — קיצור פר-תוסף. קריאתו הייתה מונה את התוספים
  האחרים המותקנים; לאוצריא אין API כזה ואין הרשאה כזו.
- תוכן אישי: `key-bookmarks`, `key-tabs`, `key-current-tab`, `key-workspaces`,
  `key-current-workspace-id`, `key-saved-alternative-words`,
  `key-plugin-search-selections`.

`settings.get` על מפתח חסום מחזיר `error.forbidden` (ולא `null`, כדי שאפשר
יהיה להבחין בינו לבין הגדרה שלא נקבעה). `settings.getMany` **מדלג** על מפתח
חסום — הוא פשוט חסר מהמפה המוחזרת, ואין דרך להבחין בינו לבין מפתח שלא נקבע.
זו אי-סימטריה מכוונת: `getMany` נועד לקריאת אצווה של העדפות תצוגה, שבה מפתח
חסר אינו מצב שגיאה.

> **⚠️ שינוי שובר — יש לבדוק לפני שדרוג ל-0.9.97**
>
> עד 0.9.97 `settings.get` על **כל** מפתח שלא היה ברשימת ההיתר החזיר `null`
> בשקט. מ-0.9.97 הוא זורק `error.forbidden`, ולכן קוד כמו
> `const v = (await Otzaria.call('settings.get', {key})).data` על מפתח חסום
> מקבל promise **נדחה** — חריגה לא-מטופלת במקום `null`.
>
> יש לעטוף בדיקות כאלה ב-`try/catch`, או לעבור ל-`settings.getMany` שמדלג
> בשקט. שים לב שגם מפתחות שלא נראו חסומים קודם נחסמו כאן (משפחות
> `page_shape_*` פר-ספר ו-`key-shortcut-open-plugin-*`).

מפתחות נפוצים שאפשר לקרוא: `key-dark-mode`, `key-follow-system-theme`,
`key-swatch-color`, `key-dark-swatch-color`, `key-font-size`,
`key-font-family`, `key-commentators-font-family`,
`key-commentators-font-size`, `key-line-height`, `key-selected-city`,
`key-calendar-type`, `key-settings-language`, `key-show-teamim`,
`key-default-nikud`, `key-remove-nikud-tanach`, `key-replace-holy-names`,
`key-library-view-mode`, `key-copy-with-headers`, `key-copy-header-format`.

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
**הרשאה:** `calendar.read` · **מגרסה:** 0.9.97

קבלת זמנים הלכתיים ליום.

```javascript
const { data } = await Otzaria.call('calendar.getDailyTimes');
// { sunrise: "06:23", sunset: "19:11", tzet: "19:45", ... }
```

מגרסה 0.9.97 אפשר לבקש זמנים לתאריך ולמיקום שרירותיים — עיר מתוך
`calendar.getCities`, או קואורדינטות למקום שאינו ברשימה; בלי הפרמטרים
מוחזרים זמני התאריך והעיר הנבחרים בלוח, כבגרסאות קודמות. עיר לא מוכרת או
אזור זמן לא מוכר מחזירים שגיאה; אין להעביר גם `city` וגם `lat`/`lng`.

```javascript
// לפי עיר מרשימת הלוח
const { data } = await Otzaria.call('calendar.getDailyTimes', {
  date: '2026-08-14',      // אופציונלי — ברירת מחדל: התאריך הנבחר בלוח
  city: 'ניו יורק',        // אופציונלי — ברירת מחדל: העיר הנבחרת בלוח
});

// לפי קואורדינטות (מקום שאינו ברשימת הערים)
const { data } = await Otzaria.call('calendar.getDailyTimes', {
  date: '2026-08-14',
  lat: 43.6,               // חובה יחד עם lng
  lng: -79.4,
  elevation: 76,           // אופציונלי (מטרים; ברירת מחדל 0)
  timezone: 'America/Toronto', // אופציונלי — מזהה IANA; בלעדיו נגזר אזור
                               // נומינלי מקו האורך (Etc/GMT±n)
  inIsrael: false,         // אופציונלי — לזמנים תלויי יו"ט שני
});
// בקואורדינטות: קידוש לבנה מושמט, הדלקת נרות לפי ברירת המחדל (30 דק'),
// וחצות הלילה בקירוב (חצות היום + 12 שעות).
```

### `calendar.getHalachicTimes`
**הרשאה:** `calendar.read` · **מגרסה:** 0.9.97

קבלת זמנים הלכתיים מלאים ליום.

> **Alias:** מתודה זו היא כפילות מדויקת של `calendar.getDailyTimes` — אותה
> תוצאה ואותם פרמטרים אופציונליים (`date`, `city`, או `lat` ו-`lng`). היא
> קיימת לנוחות בלבד; אין הבדל התנהגותי בין השתיים.

```javascript
const { data } = await Otzaria.call('calendar.getHalachicTimes');
// { sunrise: "06:23", sunset: "19:11", tzet: "19:45", ... }
```

### `calendar.getCities`
**הרשאה:** `calendar.read` · **מגרסה:** 0.9.97

רשימת הערים שהלוח מכיר — לשימוש עם `calendar.getDailyTimes { city }`.

```javascript
const { data } = await Otzaria.call('calendar.getCities');
// [
//   { name: "ירושלים", country: "ארץ ישראל", lat: 31.7784, lng: 35.2354,
//     elevation: 800.0, timezone: "Asia/Jerusalem", inIsrael: true },
//   ...
// ]
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
  scope: 'global',          // 'global' | 'workspace:<id>' | 'book:<bookUid>' (מזוהה גם 'book:<כותרת>')
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

בכל רשומת `databaseSources` מותרים רק `id`,‏ `label` ו־`required`. נתיב הקובץ
וה־policy נקבעים בלעדית על ידי אוצריא; שדה כמו `path` יגרום לדחיית המניפסט.

> **`required` אינו נאכף.** הוא מאומת כבוליאני בזמן אריזה, אך שום חלק
> באוצריא אינו קורא את ערכו — תוסף שמצהיר `required: true` על מקור חסר
> ייטען כרגיל. בדקו זמינות בעצמכם עם `database.listSources`.

### מקורות הנתונים המובנים

| `id` | תוכן | קובץ |
|------|------|------|
| `talmud_synopsis` | עדי נוסח לתלמוד הבבלי | `talmud_synopsis_pooled.db` |
| `external_catalog` | מיפוי קטלוגים חיצוניים (HebrewBooks) | קטלוגים חיצוניים |

#### `talmud_synopsis` — סכימה מנורמלת (pooled)

**כל הטקסטים מרוכזים בטבלת `strings`.** אין עמודת טקסט ישירה בשום טבלה
אחרת — כל שם, הפניה ונוסח מיוצגים כמזהה `*_text_id` שיש לחבר ל-`strings.id`
ולקרוא מ-`strings.value`.

| טבלה | עמודות |
|------|--------|
| `tractates` | `id`,‏ `sort_order`,‏ `name_text_id` |
| `pages` | `id`,‏ `tractate_id`,‏ `sort_order`,‏ `name_text_id` |
| `witnesses` | `id`,‏ `name_text_id` |
| `alignments` | `id`,‏ `page_id`,‏ `kind`,‏ `sequence_number`,‏ `reference_text_id` |
| `readings` | `alignment_id`,‏ `witness_id`,‏ `text_text_id` |
| `strings` | `id`,‏ `value` |
| `page_witnesses` | `page_id`,‏ `kind`,‏ `column_index`,‏ `witness_id` |

**11 חוקי ה-join המותרים** (בשני הכיוונים):

`tractates.id ↔ pages.tractate_id` · `pages.id ↔ alignments.page_id` ·
`alignments.id ↔ readings.alignment_id` · `witnesses.id ↔ readings.witness_id` ·
`pages.id ↔ page_witnesses.page_id` · `witnesses.id ↔ page_witnesses.witness_id` ·
וחמישה חיבורים ל-`strings.id`: `tractates.name_text_id`,‏ `pages.name_text_id`,‏
`witnesses.name_text_id`,‏ `alignments.reference_text_id`,‏ `readings.text_text_id`.

**אותה טבלה מותרת כמה פעמים תחת aliases שונים.** שאילתה מלאה מחברת את
`strings` חמש פעמים — פעם לכל שדה טקסט — ולכן `maxJoins` במקור הזה הוא **8**
ולא ברירת המחדל 4.

#### `external_catalog`

| טבלה | עמודות |
|------|--------|
| `otzaria_hebrew_books` | `hb_id`,‏ `otzaria_id`,‏ `otzaria_title`,‏ `is_best`,‏ `confidence` |
| `hebrew_books` | `id_book`,‏ `title`,‏ `author` |

join יחיד מותר: `otzaria_hebrew_books.hb_id = hebrew_books.id_book`.

### מגבלות ה-policy

לכל מקור עשר מגבלות. שלוש מהן נחשפות ב-`database.describeSource`; השאר
נאכפות בשקט ומחזירות `database.query_too_large` בחריגה.

| מגבלה | ברירת מחדל | `talmud_synopsis` | `external_catalog` | מה חוסמת |
|-------|-----------|-------------------|--------------------|----------|
| `maxLimit` | 5000 | 5000 | 1000 | `limit` גדול מהערך → שגיאה (אינו נחתך) |
| `maxBatchQueries` | 5 | 5 | 10 | מספר השאילתות ב-`database.batchQuery` |
| `maxJoins` | 4 | **8** | 1 | מספר הרשומות במערך `joins` |
| `maxColumns` | 32 | 32 | 8 | אורך `select`, ובנפרד אורך `orderBy` |
| `maxOffset` | 10000 | 10000 | **0** | `offset` גדול מהערך → שגיאה |
| `maxWhereConditions` | 32 | 32 | 8 | סך התנאים ב-`where`, כולל קבוצות `and`/`or` |
| `maxInValues` | 100 | 100 | 1000 | אורך המערך ב-`{ op: 'in' }` |
| `maxParameterBytes` | 64KB | 64KB | 16KB | גודל ערך פרמטר יחיד |
| `maxResultBytes` | 4MB | 4MB | 256KB | גודל משוער של כלל התוצאה |
| `maxQueryDuration` | 3 שניות | 3 שניות | 3 שניות | משך ריצה → `database.query_timeout` |

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

מוחזרים רק המקורות שהתוסף הצהיר עליהם במניפסט, בסדר ההצהרה.

> **`available: false` מכסה שני מצבים שונים ואינו מבחין ביניהם:** מזהה שאוצריא
> אינה מכירה כלל (בדרך כלל שגיאת כתיב ב-`id` שבמניפסט), וקובץ DB מוכר שאינו
> קיים אצל המשתמש הזה. הסימן היחיד להבדל הוא ש-`label` נופל למזהה עצמו כשהמקור
> אינו רשום — אבל אין להסתמך על כך. אל תציגו למשתמש "המסד חסר" על סמך
> `available: false` בלבד; בדקו קודם את איות ה-`id` מול טבלת המקורות המובנים.

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
//       { name: "alignments", columns: ["id", "kind", "page_id", "reference_text_id", "sequence_number"] },
//       { name: "pages",      columns: ["id", "name_text_id", "sort_order", "tractate_id"] },
//       { name: "readings",   columns: ["alignment_id", "text_text_id", "witness_id"] },
//       ...
//     ]
//   },
//   limits: { maxLimit: 5000, maxBatchQueries: 5, maxQueryDurationMs: 3000 }
// }
```

הטבלאות והעמודות מוחזרות ממוינות אלפביתית. `limits` מחזיר שלושה שדות בלבד —
שאר המגבלות אינן נחשפות (ראו הטבלה למעלה).

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

הסכימה מנורמלת, ולכן כל שדה טקסט מחייב join נפרד ל-`strings` תחת alias משלו.
הדוגמה מחברת את `strings` ארבע פעמים — `tn` (שם מסכת), `pn` (שם דף),
`wn` (שם עד הנוסח) ו-`rt` (הנוסח עצמו).

```javascript
const { data } = await Otzaria.call('database.query', {
  sourceId: 'talmud_synopsis',
  from: { table: 'tractates', alias: 't' },
  select: [
    { expr: 'a.id',              as: 'alignment_id' },
    { expr: 'a.sequence_number', as: 'sequence_number' },
    { expr: 'wn.value',          as: 'witness_name' },
    { expr: 'rt.value',          as: 'text' }
  ],
  joins: [
    { type: 'inner', table: 'strings',    alias: 'tn',
      on: [{ left: 'tn.id', op: '=', right: 't.name_text_id' }] },
    { type: 'inner', table: 'pages',      alias: 'p',
      on: [{ left: 'p.tractate_id', op: '=', right: 't.id' }] },
    { type: 'inner', table: 'strings',    alias: 'pn',
      on: [{ left: 'pn.id', op: '=', right: 'p.name_text_id' }] },
    { type: 'inner', table: 'alignments', alias: 'a',
      on: [{ left: 'a.page_id', op: '=', right: 'p.id' }] },
    { type: 'inner', table: 'readings',   alias: 'r',
      on: [{ left: 'r.alignment_id', op: '=', right: 'a.id' }] },
    { type: 'inner', table: 'witnesses',  alias: 'w',
      on: [{ left: 'w.id', op: '=', right: 'r.witness_id' }] },
    { type: 'inner', table: 'strings',    alias: 'wn',
      on: [{ left: 'wn.id', op: '=', right: 'w.name_text_id' }] },
    { type: 'inner', table: 'strings',    alias: 'rt',
      on: [{ left: 'rt.id', op: '=', right: 'r.text_text_id' }] }
  ],
  where: {
    op: 'and',
    conditions: [
      { op: '=', left: 'tn.value', value: 'מסכת ברכות' },
      { op: '=', left: 'pn.value', value: 'ב' }
    ]
  },
  orderBy: [
    { expr: 'a.sequence_number', direction: 'asc' },
    { expr: 'wn.value',          direction: 'asc' }
  ],
  limit: 2000,
  rowFormat: 'array'
});
// {
//   meta: { sourceId: "talmud_synopsis", rowCount: 240, limit: 2000, offset: 0, hasMore: false, elapsedMs: 12 },
//   columns: [
//     { name: "alignment_id" }, { name: "sequence_number" },
//     { name: "witness_name" }, { name: "text" }
//   ],
//   rows: [
//     [1, 1, "כ\"י מינכן 95", "..."],
//     ...
//   ]
// }
```

הדוגמה משתמשת בשמונה joins — בדיוק ה-`maxJoins` של המקור הזה. הוספת
`strings` חמישית (למשל עבור `a.reference_text_id`) תחזיר
`database.query_too_large`; פצלו לשתי שאילתות או ל-`database.batchQuery`.

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
| `=` `!=` `>` `>=` `<` `<=` | `{ op: '=', left: 'pn.value', value: 'ב' }` |
| `like` | `{ op: 'like', left: 'wn.value', value: '%כ"י%' }` |
| `in` | `{ op: 'in', left: 'p.id', value: [1, 2, 3] }` |
| `between` | `{ op: 'between', left: 'a.sequence_number', value: [1, 50] }` |
| `isNull` / `isNotNull` | `{ op: 'isNull', left: 'r.text_text_id' }` |
| `and` / `or` | `{ op: 'and', conditions: [...] }` |

**כללי ולידציה שקל לפספס** — כולם מחזירים `database.invalid_spec`:

- **שדה לא מוכר נדחה, ולא מתעלמים ממנו.** בכל רמה נאכפת רשימת מפתחות סגורה:
  ברמת השאילתה רק `sourceId`,‏ `from`,‏ `select`,‏ `joins`,‏ `where`,‏ `orderBy`,‏
  `limit`,‏ `offset`,‏ `rowFormat`; ב-`from` רק `table`/`alias`; ב-`join` רק
  `type`/`table`/`alias`/`on`; ב-`select` רק `expr`/`as`; ב-`orderBy` רק
  `expr`/`direction`. שגיאת כתיב בשם שדה מפילה את השאילתה.
- **הפניה לעמודה חייבת להיות בדיוק `alias.column`** — שני חלקים, כל אחד מזהה
  חוקי (`[a-zA-Z_][a-zA-Z0-9_]*`). `t.*`, שם טבלה ללא alias, או ביטוי SQL —
  נדחים.
- **האופרטור ב-`join.on` חייב להיות `=`.** אין תמיכה בשום אופרטור אחר, ולכל
  join נדרש לפחות תנאי `on` אחד.
- **כל join חייב לחבר את ה-alias החדש לטבלה שכבר נכנסה** — צד אחד של התנאי
  ה-alias החדש, הצד השני alias קודם. alias כפול נדחה.
- **`limit` מעבר ל-`maxLimit` זורק** `database.query_too_large` — הוא אינו
  נחתך בשקט. כך גם `offset` מעבר ל-`maxOffset` (ב-`external_catalog` הוא 0,
  כלומר כל `offset` חיובי נדחה). ערך שלילי בשניהם → `database.invalid_spec`.
- **`select` ריק נדחה**, ושמות הפלט חייבים להיות ייחודיים — שתי עמודות
  בשם זהה מחייבות `as` מבדיל. ב-`rowFormat: 'object'` כפילות מתגלה גם על
  שמות העמודות שחוזרים מ-sqlite.
- **`isNull`/`isNotNull` אסור שיכללו `value`**, וכל שאר האופרטורים חייבים
  לכלול אותו. `in` דורש מערך לא ריק, `between` מערך בן שני איברים בדיוק.
- **קינון `where` מוגבל ל-5 רמות**, וערכי פרמטר חייבים להיות סקלרים של JSON
  (מחרוזת, מספר, בוליאני או `null`).

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
- מקסימום `maxBatchQueries` שאילתות ל-batch — 5 ב-`talmud_synopsis`,‏ 10
  ב-`external_catalog` (ניתן לבדוק ב-`database.describeSource`)
- כל שאילתה עוברת ולידציה נפרדת מול ה-policy
- אין תמיכה ב-references בין תוצאות (כל שאילתה עצמאית)

---

**קודי שגיאה:**

| קוד | משמעות |
|-----|--------|
| `permission_denied` | חסרה הרשאת `database.read` (קוד גנרי של ה-RPC bridge) |
| `database.source_not_found` | המקור לא הוצהר במניפסט |
| `database.source_unavailable` | קובץ ה-DB לא קיים או לא רשום |
| `database.source_not_read_only` | המקור רשום ככתיב — אוצריא מסרבת לפתוח אותו לתוסף |
| `database.table_not_allowed` | טבלה לא מורשית |
| `database.column_not_allowed` | עמודה לא מורשית |
| `database.join_not_allowed` | join לא מורשה על פי ה-policy |
| `database.query_too_large` | חריגה מאחת ממגבלות ה-policy (ראו טבלת המגבלות) |
| `database.invalid_spec` | בקשה לא תקינה (שדה לא מוכר, ערך לא חוקי, alias כפול) |
| `database.query_timeout` | השאילתה חרגה מ-`maxQueryDuration` (3 שניות) |
| `database.query_failed` | כשל ריצה ב-sqlite או ב-worker |

> **timeout:** לשאילתות DB יש חסם זמן משלהן. השאילתה רצה ב-isolate נפרד
> שנהרג בתום `maxQueryDuration` — 3 שניות כברירת מחדל — והשגיאה שחוזרת היא
> `database.query_timeout`, לא `error.timeout` הגנרי. חסם 30 השניות של
> ה-RPC לעולם אינו זה שנוגע בשאילתת DB.

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

- `plugin.boot` - נורה פעם אחת בטעינת התוסף (ללא הרשאה). ה-payload כולל `app.runMode: 'foreground' | 'background'` — ראה §ריצת רקע — וכן `connectivity` (מצב האינטרנט; ראה [`app.getConnectivity`](#appgetconnectivity)). שדה ה-`app` כולל גם `language` (קוד השפה, זהה ל-[`app.getLocale`](#appgetlocale)) ו-`devMode` (`true` רק כשהתוסף נטען כתוסף פיתוח). שים לב: `buildNumber` אינו נשלח ב-`plugin.boot` — לקבלתו יש לקרוא ל-[`app.getInfo`](#appgetinfo).
- `plugin.ready` - נורה אחרי boot (ללא הרשאה)
- `plugin.suspended` - התוסף הושהה (יציאה מלשונית התוסף / מעבר לרקע). ללא הרשאה — ראה §השהיה ברקע ב-README
- `plugin.resumed` - התוסף חזר מהשהיה (ללא הרשאה)
- `theme.changed` - שינוי בערכת הצבעים (הרשאה: `events.subscribe:theme.changed`)
- `navigation.changed` - מעבר בין מסכים ראשיים בלבד (library ↔ reading ↔ more ↔ settings) (הרשאה: `events.subscribe:navigation.changed`)
- `reader.current_book_changed` - שינוי הספר/טאב הפעיל בלבד (הרשאה: `events.subscribe:reader.current_book_changed`)
- `reader.current_ref_changed` - שינוי מיקום הקריאה הנוכחי (דף, פרק, סעיף) - **זה האירוע למעקב אחרי מיקום!** (הרשאה: `events.subscribe:reader.current_ref_changed`)
- `calendar.date_changed` - שינוי התאריך בלוח השנה (הרשאה: `events.subscribe:calendar.date_changed`)
- `calendar.city_changed` - שינוי העיר הנבחרת בלוח השנה; payload: `{ city: string }` (הרשאה: `events.subscribe:calendar.city_changed`, מגרסה 0.9.97)
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

## תרומות עלייה דקלרטיביות (contributes.startup)

**זו הדרך המומלצת** לתוסף להיות נוכח מיד עם עליית אוצריא — בלי שאוצריא תרים עבורו מנוע JS. במקום קוד שרץ בעלייה, התוסף מצהיר במניפסט מה להציג ולרשום, ואוצריא קוראת את ההצהרה ב-Dart. קוד התוסף מופעל **בעצלנות** — רק כשמשתמש לוחץ על פקד, או כשקורה אירוע שהתוסף ביקש להתעורר עליו.

דורש את ההרשאה `app.startup_contributions` (ברירת מחדל: **דלוקה** — לא רץ שום קוד תוסף, רק פרסינג JSON מוולד), וכל קטגוריה דורשת גם את הרשאת התחום שלה.

```json
{
  "permissions": [
    "app.startup_contributions",
    "app.run_on_startup",
    "reader.toolbar",
    "reader.context_menu",
    "published_data.write"
  ],
  "contributes": {
    "startup": {
      "toolbarItems": [
        {
          "id": "my-button",
          "title": "הכלי שלי",
          "icon": "sparkle_24_regular",
          "contexts": ["reader-text"],
          "openPlugin": true
        }
      ],
      "contextMenuItems": [
        {
          "id": "lookup",
          "title": "חפש במילון",
          "showWhen": { "selectionContainsAny": ["רש\"י", "תוס'"] }
        }
      ],
      "publishedData": [
        {
          "type": "calendar.event",
          "key": "daily-reminder",
          "scope": "global",
          "payload": {
            "title": "תזכורת",
            "startsAt": "2026-08-10T18:00:00+03:00",
            "importance": "normal"
          }
        }
      ],
      "activationEvents": ["app.startup", "reader.sectionContentChanged"],
      "keepAlive": false
    }
  }
}
```

### הקטגוריות

| שדה | סכימה | הרשאת תחום נדרשת |
|---|---|---|
| `toolbarItems` | זהה ל-`reader.addToolbarItem` | `reader.toolbar` |
| `contextMenuItems` | זהה ל-`reader.addContextMenuItem` | `reader.context_menu` |
| `publishedData` | `{type, key, payload, scope?}` | `published_data.write` |
| `programs` | תכניות חישוב Host מוולדות | הרשאות הפקודות שבתכנית |
| `searchDialogItems` | שורות checkbox סטטיות בדיאלוג החיפוש | `search.dialog` |
| `externalEditions` | קונפיגורציית מהדורות מקבילות חיצוניות (טבלת מיפוי במקור DB מוכרז) | `database.read` וגם `library.books.read` |
| `activationEvents` | שמות אירועים או `app.startup`; אפשר גם `{topic, when}` | הרשאת ה-subscribe של כל נושא |
| `keepAlive` | `boolean` (ברירת מחדל: `false`) | `app.background_keep_alive` וגם `app.run_on_startup` |

### תכניות Host ללא WebView

החל מ־`minAppVersion: 0.9.96`, `startup.programs` מאפשר לחשב תרומת UI מתוך
הקשר הקורא וממקורות DB שאוצריא אישרה. התכנית עוברת קומפילציה ואימות ב־Dart,
ואינה טוענת HTML או JavaScript.

ה־triggers הנתמכים:

| trigger | מתי רץ | ההקשר (`$context`) |
|---|---|---|
| `reader.activeBookChanged` | בכל החלפת ספר/חלונית קריאה | `reader.context` ו־`reader.book` |
| `app.startup` | פעם אחת לכל תוסף — בסיום סנכרון התוספים בעליית האפליקציה, וגם כשתוסף מותקן לאחר העלייה (בסיום ההתקנה שלו) | ריק, אלא אם ספר כבר פתוח |
| `settings.changed` | בכל שינוי הגדרה, אחרי השהיית איחוד של 150ms | כנ"ל |

שני האחרונים אינם נגזרים מהקשר הקריאה, ולכן `$context` יהיה ריק כשאין ספר
פתוח — תכנית שנשענת על `reader.book` צריכה `reader.activeBookChanged`.

דוגמה שמוצאת מהדורות היברובוקס המקבילות לספר הטקסט הפעיל:

```json
{
  "permissions": [
    "app.startup_contributions",
    "database.read",
    "reader.toolbar",
    "reader.open"
  ],
  "contributes": {
    "databaseSources": [
      {
        "id": "external_catalog",
        "label": "קטלוגים חיצוניים",
        "required": true
      }
    ],
    "startup": {
      "programs": [
        {
          "id": "hebrewbooks-editions",
          "version": 1,
          "triggers": ["reader.activeBookChanged"],
          "when": {
            "op": "exists",
            "value": { "$context": "reader.book.id" }
          },
          "commands": [
            {
              "id": "matches",
              "type": "database.select",
              "args": {
                "sourceId": "external_catalog",
                "from": {
                  "table": "otzaria_hebrew_books",
                  "alias": "m"
                },
                "select": [
                  { "expr": "m.hb_id", "as": "hb_id" },
                  { "expr": "m.is_best", "as": "is_best" },
                  { "expr": "h.title", "as": "title" }
                ],
                "joins": [
                  {
                    "table": "hebrew_books",
                    "alias": "h",
                    "type": "left",
                    "on": [
                      {
                        "left": "m.hb_id",
                        "op": "=",
                        "right": "h.id_book"
                      }
                    ]
                  }
                ],
                "where": {
                  "op": "=",
                  "left": "m.otzaria_id",
                  "value": { "$context": "reader.book.id" }
                },
                "orderBy": [
                  { "expr": "m.is_best", "direction": "desc" }
                ],
                "limit": 20,
                "rowFormat": "object"
              }
            },
            {
              "id": "editions",
              "type": "data.map",
              "args": {
                "items": { "$result": "matches.rows" },
                "maxItems": 20,
                "template": {
                  "title": { "$row": "title" },
                  "identity": {
                    "external": {
                      "provider": "hebrewbooks",
                      "id": { "$row": "hb_id" }
                    }
                  }
                }
              }
            },
            {
              "id": "default-edition",
              "type": "data.first",
              "args": {
                "items": { "$result": "editions" }
              }
            }
          ],
          "outputs": {
            "defaultEdition": { "$result": "default-edition" },
            "editions": { "$result": "editions" }
          }
        }
      ],
      "toolbarItems": [
        {
          "id": "open-default-hb",
          "type": "button",
          "title": "פתח במהדורת היברובוקס",
          "icon": "book_24_regular",
          "contexts": ["reader-text", "reader-pdf"],
          "binding": {
            "program": "hebrewbooks-editions",
            "visibleOutput": "defaultEdition"
          },
          "action": {
            "type": "reader.openBook",
            "args": {
              "identity": {
                "$output": "defaultEdition.identity"
              }
            }
          }
        },
        {
          "id": "open-hb-edition",
          "type": "menu",
          "title": "בחר מהדורת היברובוקס",
          "icon": "book_24_regular",
          "contexts": ["reader-text", "reader-pdf"],
          "binding": {
            "program": "hebrewbooks-editions",
            "visibleOutput": "editions"
          },
          "childrenBinding": {
            "itemsOutput": "editions",
            "maxItems": 20,
            "itemTemplate": {
              "id": {
                "$concat": [
                  "hb-",
                  { "$item": "identity.external.id" }
                ]
              },
              "title": { "$item": "title" },
              "action": {
                "type": "reader.openBook",
                "args": {
                  "identity": { "$item": "identity" }
                }
              }
            }
          }
        }
      ]
    }
  }
}
```

#### פקודות חישוב

| פקודה | הרשאה | תיאור הפלט |
|---|---|---|
| `database.select` | `database.read` | `{rows, columns, meta}`; בתכנית נדרש `rowFormat: "object"` |
| `data.first` | — | האיבר הראשון ברשימה, או `null` |
| `data.choose` | — | מ־0.9.97: מחזיר `whenTrue` או `whenFalse` לפי `condition` מובנה |
| `data.map` | — | מיפוי של עד 20 רשומות בעזרת `template` ו־`$row` |
| `library.resolveBooks` | `library.books.read` | זהות קנונית רק להתאמה יחידה; עמימות מוחזרת כאי־התאמה |
| `settings.get` | `settings.read` | מ־0.9.97: ערך הגדרת תוכנה לפי `key` (ליטרל מחרוזת). רק מפתחות שתוספים רשאים לקרוא — מפתח חסום נכשל בזמן החישוב, לא בהתקנה |
| `storage.get` | `plugin.storage.read` | מ־0.9.97: ערך מאחסון התוסף לפי `key` (ליטרל מחרוזת). נעול למרחב האחסון הרגיל של התוסף (אותו אחד של `storage.set`) — אין פרמטר namespace; מפתח שאינו קיים מחזיר `null` |
| `library.parallelEditions` | `library.books.read` | מ־0.9.97: מהדורות מקבילות לזהות ספר — המהדורה המובנית בספרייה ואז מהדורות ספקים חיצוניים שנרשמו דרך `startup.externalEditions` ונפתחות מקומית; שורות `{title, isCompanion, identity}` |

ערכים יכולים להפנות אל `$context`,‏ `$result` של פקודה קודמת, או `$row`
בתוך תבנית שורה. `$concat` מחבר עד שמונה חלקים, ו־`$literal` מונע פירוש של
אובייקט כ־reference. ההפניות הן לאחור בלבד; אין SQL חופשי, נתיב קובץ או URL.

#### binding לשורת הפקדים

- `binding.program` מפנה לתכנית באותו manifest.
- `binding.visibleOutput` מציג את הפקד רק כשהפלט קיים ואינו ריק.
- כפתור משתמש ב־`action` עם `reader.openBook`, או עם
  `reader.openBookInSidePane` — אותם ארגומנטים ואותה הרשאה (`reader.open`),
  אלא שהספר נפתח כחלונית לצד הספר הנוכחי במקום להחליף אותו. בטאב שכבר מפוצל
  הפעולה יורדת לפתיחה ככרטיסייה רגילה.
- מ־0.9.97 קיימות עוד שלוש פעולות host, כולן בלי להעיר את המנוע:
  - `reader.scrollToRef` (‏`args: {ref, highlight?}`, הרשאה `reader.open`) —
    גולל את הספר ה**פתוח** להפניה, בלי לפתוח אותו מחדש. ההפניה נפתרת מול
    אותם מסלולים של `reader.openBookAtRef` (heRef פר-שורה, ואז תוכן
    העניינים). נכשל כשאין ספר טקסט פתוח או שההפניה לא נפתרה.
  - `search.open` (‏`args: {query, autoSearch?}`, הרשאה `reader.open`) —
    פותח כרטיסיית חיפוש עם השאילתה. `autoSearch: false` ממלא את השדה בלי
    להריץ, כמו ב-`reader.openSearchTab`.
  - `ui.showSnack` (‏`args: {message, severity?}`, הרשאה `notifications.send`) —
    הודעת מערכת. `severity`: `"info"` (ברירת מחדל), `"success"`, `"error"`.
    ההודעה מוצגת עם ייחוס לתוסף — `<message> · מאת <שם התוסף>` — כדי שהמשתמש
    ידע איזה תוסף פנה אליו; אין צורך להוסיף את שם התוסף ל-`message` בעצמכם.
- מ־0.9.97 פעולה יכולה גם לכתוב לאחסון התוסף בלי להעיר את המנוע:
  `storage.set` (‏`args: {key, value}`) ו־`storage.remove` (‏`args: {key}`),
  בהרשאה `plugin.storage.write`. הכתיבה נעולה למרחב האחסון הרגיל של התוסף
  (אותו אחד של `storage.get`/`storage.set` בגשר). `key` — מחרוזת עד 128
  תווים; `value` — ערך JSON קטן (עד 256 צמתים, עומק עד 10, מחרוזות עד
  4096 תווים) ואינו `null`. מפתח שתנאי `when` קורא מתעדכן מיד — כך לחיצה
  יכולה להציג/להסתיר פקדים באופן מיידי (פלטי תכניות, לעומת זאת, מחושבים
  מחדש רק בהחלפת ספר).
- תפריט משתמש ב־`childrenBinding.itemsOutput` וב־`itemTemplate`; בתוך התבנית
  זמינה ההפניה `$item`.
- לחצן מפוצל (`"type": "split"`) מצהיר על שניהם: `action` לפעולה הראשית
  ו־`childrenBinding` לפריטי החץ.
- לתוסף מותר להציג לכל היותר שני פקדים עליונים. הקבוצה מוחלפת אטומית: בתחילת
  חישוב חדש שני הפקדים מוסתרים, ורק תוצאה מלאה ועדכנית מחזירה אותם.
- `placement` (אופציונלי, על פריט עליון בלבד): `"primary"` (ברירת מחדל) —
  בשורת הפקדים, נדחס לתפריט כשאין מקום; `"overflow"` — תמיד בתוך תפריט
  "עוד פעולות" (שלוש נקודות), כתת-תפריט כשיש ילדים.
- `order` (אופציונלי, מספר שלם 0–10000; דורש `"placement": "overflow"`, על
  פריט עליון בלבד): משקל מיון בתוך תפריט שלוש הנקודות. הפריטים המובנים
  תופסים משקלים קבועים, כך שפריט תוסף משתבץ ביניהם לפי ערכו; ללא `order`
  הפריט מוצג אחרי כל המובנים. בשוויון משקלים המובנה קודם, ותוספים לפי סדר
  הרישום. המשקלים המובנים —
  מסך טקסט: סימניות 10, הערות אישיות 20, שמור וזכור 30, אפס הגדרות 40,
  העתק קישור 45, ייצוא הספר 50, **הדפסה 60**, אודות הספר 70;
  מסך PDF: הערות אישיות 10, הוסף הערה 20, סימניות 30, אפס הגדרות 40,
  **הדפס 60**, העתק קישור 70, אודות הספר 80. לדוגמה, `"order": 55` ממקם
  את הפריט מיד לפני "הדפסה" בשני המסכים.
- ההרשאות נבדקות בקומפילציה, בזמן החישוב ושוב בלחיצה. הפעולה אינה עוברת דרך
  `PluginRuntimeDispatcher`, אינה מפעילה WebView ואינה דורשת
  `app.run_on_startup`.

### שורות בדיאלוג החיפוש

`startup.searchDialogItems` מוסיף שורות checkbox סטטיות בתחתית דיאלוג
**החיפוש בספרייה**, מעל כפתורי "ביטול" ו"חפש". הן אינן מוצגות בחיפוש
בתוך ספר, שחוזה התוצאות שלו אינו נושא בחירות תוסף. הן נבנות ישירות מהמניפסט: פתיחת
הדיאלוג, החלפת מצב, ולחיצה על ה-checkbox **אינן** מפעילות WebView ואינן
שולחות אירוע לתוסף.

```json
{
  "permissions": [
    "app.startup_contributions",
    "search.dialog"
  ],
  "contributes": {
    "startup": {
      "searchDialogItems": [
        {
          "id": "include-external-source",
          "type": "checkbox",
          "title": "חפש גם במקור חיצוני",
          "defaultValue": true,
          "openPluginOnSubmit": true,
          "visibleInModes": ["exact", "advanced"],
          "disabledSearchOptions": {
            "advanced": [
              "word.partial",
              "word.typo-tolerance"
            ]
          }
        }
      ]
    }
  }
}
```

| שדה | חובה | תיאור |
|---|---:|---|
| `id` | כן | מזהה ייחודי בתוסף; אותיות ASCII, מספרים, `.`, `_`, `-`. |
| `type` | כן | כעת רק `"checkbox"`. |
| `title` | כן | הכיתוב המוצג למשתמש (עד 120 תווים). |
| `defaultValue` | לא | ערך התחלתי, `false` כברירת מחדל. |
| `openPluginOnSubmit` | לא | מגרסה 0.9.97: אם `true`, אישור חיפוש כשהשורה מסומנת פותח את דף התוסף ושולח אליו `search.requested`. |
| `resultsProvider` | לא | שם ספק תוצאות חיצוני (אותיות קטנות, עד 64 תווים). כשהשורה מסומנת, טאב החיפוש מציג מדור תוצאות מהתוסף דרך `search.external.requested` (ראו `reader.registerExternalSearchProvider`). סותר את `openPluginOnSubmit`. |
| `resultsTitle` | לא | כותרת מדור התוצאות בטאב החיפוש (עד 120 תווים); דורש `resultsProvider`. ברירת המחדל: `title`. |
| `visibleInModes` | לא | מערך לא-ריק מתוך `"exact"`, `"advanced"`, `"fuzzy"`; ברירת המחדל היא כל המצבים. |
| `disabledSearchOptions` | לא | אובייקט `מצב → מזהי אפשרויות מילה` להשבתה כשה-checkbox מסומן. |

בלי `openPluginOnSubmit`, הבחירה נשמרת בקונפיגורציית טאב החיפוש במפתח
`"<pluginId>/<itemId>"`. כשהשדה פעיל, פתיחת הדיאלוג והסימון עדיין סטטיים;
רק לחיצה על "חפש" פותחת את התוסף ומוסרת `{itemId, request}`. `request` הוא
חוזה חוקי של `search.query`, אחרי נרמול המצב והאפשרויות. אם כמה שורות פעילות
מבקשות ניתוב, כל תוסף נפתח ומקבל את הבקשה. מצב `fuzzy` יכול פשוט להיעדר
מ־`visibleInModes`.

`disabledSearchOptions` משפיע רק על ממשק האפשרויות: הוא מאפיר את ה-chip
ואת אותה אפשרות בתפריט ברירות המחדל, ואינו מוחק בחירה קיימת של המשתמש
בחיפוש המקומי. ההשבתה פעילה רק כששורת אותו תוסף מסומנת. אין דרך לתוסף לשנות
ערכים, להריץ קוד, או להשבית פקדים שאינם ברשימת היתר זו.

מזהי האפשרויות המותרים כיום:

| מזהה | אפשרות באוצריא |
|---|---|
| `word.grammatical-prefixes` | קידומות דקדוקיות |
| `word.grammatical-suffixes` | סיומות דקדוקיות |
| `word.prefixes` / `word.suffixes` | קידומות / סיומות |
| `word.full-or-defective-spelling` | כתיב מלא/חסר |
| `word.partial` | חלק ממילה |
| `word.typo-tolerance` | שגיאות כתיב |
| `word.aramaic-prefixes` / `word.aramaic-suffixes` | קידומות / סיומות ארמיות |
| `word.ignore-quotes` | התעלם מגרשיים |
| `word.aramaic-translation` | תרגום ארמי |
| `word.acronyms` | ראשי תיבות |
| `word.nikud` / `word.taamim` | ניקוד / טעמים |

### מהדורות מקבילות חיצוניות (externalEditions)

מגרסה 0.9.97, `startup.externalEditions` מצהיר על טבלת מיפוי במקור נתונים
מוכרז (`contributes.databaseSources`) שמקשרת מזהי ספק חיצוני לספרי אוצריא.
לחצן "מהדורה מקבילה" המובנה — ופקודת `library.parallelEditions` בתכניות
Host — יצרפו את מהדורות הספק לספר הפתוח, אחרי המהדורה המובנית (טקסט↔PDF).
נכללות רק מהדורות שנפתחות מקומית בקורא. הכול רץ ב-Dart בלי להעיר WebView,
והשאילתות כפופות ל-policy של המקור. דורש את ההרשאות `database.read`
ו-`library.books.read`. עד 2 תרומות לתוסף.

```json
{
  "contributes": {
    "startup": {
      "externalEditions": [
        {
          "id": "hebrewbooks-editions",
          "provider": "hebrewbooks",
          "sourceId": "external_catalog",
          "table": "otzaria_hebrew_books",
          "externalIdColumn": "hb_id",
          "otzariaIdColumn": "otzaria_id",
          "orderBy": [
            { "column": "is_best", "direction": "desc" },
            { "column": "confidence", "direction": "desc" }
          ]
        }
      ]
    }
  }
}
```

| שדה | חובה | תיאור |
|---|---:|---|
| `id` | כן | מזהה ייחודי בתוסף; אותיות ASCII, מספרים, `.`, `_`, `-`. |
| `provider` | כן | שם הספק כפי שמופיע בזהות `external.provider` של ספריו (אותיות קטנות, עד 64 תווים). |
| `sourceId` | כן | מקור נתונים שהוכרז ב-`contributes.databaseSources`. |
| `table` | כן | טבלת המיפוי (חייבת להיות מותרת ב-policy של המקור). |
| `externalIdColumn` | כן | עמודת מזהה הספק החיצוני. |
| `otzariaIdColumn` | כן | עמודת מזהה ספר אוצריא. |
| `orderBy` | לא | עד 4 עמודות מיון של איכות ההתאמה: `{column, direction: asc/desc}`. |

כשהספר הפתוח שייך לספק (זהות חיצונית תואמת), המנוע מוצא את ספרי האוצריא
הממופים אליו ומהם את שאר מהדורות הספק (שני צעדים); כשהספר הפתוח הוא ספר
ספרייה, המיפוי ישיר. הספר הפתוח עצמו לעולם אינו מוחזר כמהדורה.

### הפעלה עצלה

**עיקרון:** כל הדלקת מנוע שלא דרך כניסה גלויה לדף התוסף — דורשת **גם** את ההרשאה `app.run_on_startup` (כבויה כברירת מחדל, עם הבאנר הבולט בהתקנה). המשתמש לא אמור להריץ קוד תוסף בלי לדעת.

- **לחיצה על פקד/פריט** שנרשם דקלרטיבית: אם הוגדר `openPlugin: true` — נפתח דף התוסף והאירוע נמסר לו. אחרת: עם `app.run_on_startup` — אוצריא מרימה מופע רקע שקט באותו רגע ואירוע הלחיצה נמסר אחרי ה-boot; **בלי** ההרשאה — הלחיצה נופלת לפתיחת דף התוסף (כמו `openPlugin: true`), כך שהפקד תמיד עובד וההפעלה גלויה.
- **`activationEvents`**: כשאירוע מהרשימה קורה ואין לתוסף מנוע חי — מופע הרקע קם והאירוע נמסר לו. דורש `app.run_on_startup`, וכל נושא רגיל דורש בנוסף את הרשאת `events.subscribe:<topic>` שלו.
- **`app.startup`**: טריגר מיוחד — נורה **פעם אחת לכל תוסף**: מופע הרקע קם כמה שניות **אחרי** שעליית אוצריא הסתיימה (לא מתחרה בעלייה), וגם כשתוסף מותקן לאחר שהאפליקציה כבר עלתה — הוא נורה לו בסיום ההתקנה. מיועד לתוספים שחייבים קוד בעלייה (למשל בדיקת עדכונים). דורש `app.run_on_startup` כמו כל הפעלה שקטה.

### כיבוי אוטומטי אחרי חוסר פעילות

מופע רקע שהוער עצל ולא הראה פעילות (קריאת API, רשת, או אירוע נכנס) במשך כ-3 דקות — **מכובה אוטומטית** ומשחרר את משאבי ה-WebView. זה שקוף לתוסף: הטריגר הבא (לחיצה, אירוע מוכרז) יעיר אותו מחדש, והרישומים הדקלרטיביים ממילא לא תלויים בו. עבודה חד-פעמית שמסיימת מהר יכולה לקצר את ההמתנה לאפס עם `plugin.backgroundDone`. השלכות למפתח:

- אל תסתמכו על `setTimeout`/`setInterval` ארוכים במופע הרקע — לתזמון השתמשו ב-`notifications.scheduleSystem`, ולמעקב מתמשך ב-`activationEvents`.
- שמרו state שצריך לשרוד ב-`storage.set` (או ב-`localStorage`, שנשמר בפרופיל) — משתני JS בזיכרון אובדים בכיבוי.
- מופעי `app.run_on_startup` במסלול הישן (טעינה בעלייה) אינם מכובים — רק מופעים שהוערו עצל.

### תקרת מופעי רקע בו-זמניים

אוצריא מחזיקה עד **4 מופעי רקע לפי-דרישה** בו-זמנית. כשמופע חמישי מתעורר,
הוותיק ביותר שאינו `keepAlive`, אינו באמצע `plugin.boot` ואינו עסוק בקריאת
API — מפונה. הפינוי שקוף באותו אופן ככיבוי אחרי חוסר פעילות: הטריגר הבא מעיר
את התוסף מחדש, אבל **כל state שנשמר במשתני JS בזיכרון אובד**. לכן:

- שמרו state ב-`storage.set` (או `localStorage`), לא בזיכרון.
- תוסף שחייב רציפות (מנוע חיפוש ספק, מעקב מתמשך) יצהיר `"keepAlive": true`,
  ואז אינו מועמד לפינוי.

תוסף שחייב לשמור מנוע חי יכול להצהיר `"keepAlive": true`. עליו להצהיר גם על
`app.background_keep_alive`, והמשתמש חייב לאשר אותה בנפרד. זו הרשאה רגישה,
כבויה כברירת מחדל ומוצגת באדום, משום שהיא מאפשרת ל-WebView לצרוך משאבים ללא
הגבלת זמן. `plugin.backgroundDone` עדיין מכבה את המופע מיד כשהתוסף מבקש זאת.

### showWhen — פריט תפריט תלוי-תוכן

פריט `contextMenuItems` יכול להופיע רק כשהטקסט המסומן מכיל אחת מרשימת מילים:

```json
{ "showWhen": { "selectionContainsAny": ["מילה", "ביטוי אחר"] } }
```

עד 50 מחרוזות, כל אחת עד 100 תווים. אין תמיכה ב-regex (בכוונה). ה-`showWhen` עובד גם ברישום דינמי דרך `reader.addContextMenuItem`.

### action — פעולת host על פריט תפריט הקשר

מ-`minAppVersion: 0.9.97`. פריט `contextMenuItems` מסוג `item` (גם ילד של
`submenu`) יכול לשאת `action` — פעולה שהתוכנה מבצעת בלחיצה **בלי להעיר את
מנוע התוסף**. סותר את `onClickEvent` ואת `openPlugin` על אותו פריט.
הפעולות הן אותן פעולות של פקדי הסרגל (`reader.openBook`,
`reader.openBookInSidePane`, `storage.set`, `storage.remove`), אך במקום
`$output`/`$item` ההפניה היחידה היא `$selection` — נתוני הסימון בזמן
הלחיצה (לצד `$literal` ו-`$concat`):

| נתיב `$selection` | ערך |
|---|---|
| `selectedText` | הטקסט המסומן |
| `currentRef` | הכותרת הנוכחית |
| `currentBook` / `currentBookId` | שם הספר |
| `currentIndex` | אינדקס השורה |
| `id` / `type` / `source` | זהות הספר (לבניית `identity`) |

דוגמה — "הוסף את הספר הפתוח לרשימה" בלי מנוע, כולל הסתרה מיידית דרך `when`:

```json
{
  "contextMenuItems": [
    {
      "id": "save-book",
      "title": "שמור את הספר לרשימה",
      "when": { "storage": { "key": "savedBook", "exists": false } },
      "action": {
        "type": "storage.set",
        "args": {
          "key": "savedBook",
          "value": {
            "id": { "$selection": "id" },
            "title": { "$selection": "currentBook" }
          }
        }
      }
    }
  ]
}
```

ההרשאה של הפעולה נבדקת בהתקנה (הצהרה במניפסט), ושוב בזמן הלחיצה מול
ההרשאות המוענקות. `action` עובד גם ברישום דינמי דרך
`reader.addContextMenuItem`; שם הצהרת ההרשאה נבדקת רק בלחיצה.

### when — תרומה תלוית-הגדרה

מ-`minAppVersion: 0.9.97`. כל פריט ב-`toolbarItems`, `contextMenuItems` ו-`searchDialogItems`, וכן כל איבר ב-`activationEvents`, יכול לשאת אובייקט `when`. הפריט נרשם תמיד; הוא מוצג רק כשהתנאי מתקיים, ומופיע/נעלם מיד כשהערך משתנה — בלי לטעון את מנוע ה-JS של התוסף.

> אל תבלבלו עם ה-`when` של `startup.programs` — שם זו סכימה אחרת לגמרי (`{op, value}`) שמחליטה אם התכנית בכלל רצה. ה-`when` שמתואר כאן חל על תרומות, ומבנהו `setting`/`storage`.

#### הסכימה

```json
{ "setting": { "key": "key-dark-mode", "equals": true } }
{ "storage": { "key": "showButton",   "equals": "yes" } }
{ "all": [ ... ] }
{ "any": [ ... ] }
{ "not": { ... } }
```

לכל אובייקט `when` בדיוק מפתח אחד. שני סוגי עלים ושלושה קומבינטורים:

| מפתח | משמעות |
|---|---|
| `setting` | הגדרת אוצריא. נקראת דרך אותו סינון של `settings.get` — הגדרה שתוספים אינם רשאים לקרוא מוערכת כ-`false` |
| `storage` | ערך מאחסון התוסף עצמו (אותו מרחב של `storage.get`/`storage.set`), מושווה לערך המפוענח שנשמר |
| `all` | מערך תנאים — כולם חייבים להתקיים |
| `any` | מערך תנאים — לפחות אחד |
| `not` | תנאי יחיד, מתהפך |

עלה חייב `key` (מחרוזת עד 128 תווים) ובדיוק אחד מהאופרטורים:

| אופרטור | ערך | משמעות |
|---|---|---|
| `equals` | מחרוזת / מספר / בוליאני / `null` | שוויון מדויק לערך השמור |
| `notEquals` | כנ"ל | היפוך של `equals` |
| `exists` | `true` / `false` | האם קיים ערך שאינו `null` |
| `contains` | מחרוזת / מספר / בוליאני | הכלה: במחרוזת — תת-מחרוזת; במערך — קיום איבר שווה. ערך שאינו מחרוזת ואינו מערך מוערך כ-`false` |
| `greaterThan` | מספר | הערך השמור גדול ממנו. מחרוזת שנפרסת כמספר נבדקת כמספר; ערך שאינו מספרי מוערך כ-`false` |

`exists` מבדיל בין "אין מפתח" ל"יש מפתח עם ערך": מפתח שלא נכתב מעולם ומפתח שערכו `null` מתנהגים שניהם כלא-קיימים, ולכן `{"exists": false}` מתקיים בשניהם ו-`{"equals": null}` מתקיים בשניהם.

מגבלות (נאכפות בהתקנה וגם בזמן ריצה): עומק מקסימלי 5, עד 20 עלים בסך הכול, `key` עד 128 תווים. `when` פגום פוסל את הפריט בהתקנה; ללא `when` — הפריט מוצג תמיד.

#### when על activationEvents

איבר ב-`activationEvents` יכול להיות מחרוזת (כמו קודם) או אובייקט `{"topic": "...", "when": {...}}`. מפתחות אחרים באובייקט נדחים — טעות כתיב כמו `"wen"` פוסלת את האיבר בהתקנה במקום להתעלם מהתנאי בשקט.

```json
"activationEvents": [
  "app.startup",
  { "topic": "reader.sectionContentChanged",
    "when": { "storage": { "key": "autoSync", "equals": true } } }
]
```

**האירוע נזרק כשהתנאי אינו מתקיים** — המנוע לא מוער, וגם אין נפילה לפתיחת דף התוסף. התנאי חל רק על **הערת** מנוע כבוי: כשמנוע התוסף כבר חי, האירועים ממשיכים להימסר אליו כרגיל. זו סמנטיקה של חיסכון במשאבים, לא של סינון תוכן.

### רשומות publishedData זרועות

מפתחות הרשומות נשמרים עם קידומת `manifest:` (למשל `manifest:daily-reminder`) — הן בבעלות המניפסט: מתעדכנות בכל עלייה, ומוסרות אוטומטית כשהסעיף/ההרשאה מוסרים או בעדכון גרסה שמשמיט אותן. אל תעדכן אותן בזמן ריצה — הערך מהמניפסט ידרוס בכל עלייה.

---

## ריצת רקע (app.run\_on\_startup) — מיושן

> ⚠️ **מיושן — מוסר ב-0.9.98:** מסלול הטעינה המיידית (WebView מלא שקם בעליית אוצריא לכל תוסף רקע) עובד בפעם האחרונה בגרסה 0.9.97. **החל מ-0.9.98 תוסף שלא עבר ל-`contributes.startup` פשוט לא ירוץ בעלייה** — בלי שגיאה, ההרשאה תישאר אך לא יקום עבורה מנוע.

### מדריך מעבר למפתחי תוספים (חובה עד 0.9.98)

1. **הוסיפו למניפסט** `contributes.startup` ואת ההרשאה `app.startup_contributions` (לצד `app.run_on_startup` הקיימת — היא נשארת, ומשמעותה מעתה "מותר לרוץ ברקע בלי פתיחה").
2. **רישומים סטטיים** (`reader.addToolbarItem` / `reader.addContextMenuItem` שרצים ב-`plugin.boot` של הרקע) — העבירו את אותו JSON בדיוק אל `startup.toolbarItems` / `startup.contextMenuItems` ומחקו את הקריאות מקובץ הרקע. רישומים דינמיים בדף הנראה ממשיכים לעבוד כרגיל.
3. **נתונים קבועים** (`publishedData.upsert` בעלייה) — העבירו אל `startup.publishedData`.
4. **קוד שחייב לרוץ בעלייה** (בדיקת עדכונים וכד') — הצהירו `activationEvents: ["app.startup"]`; קובץ הרקע שלכם ייטען כמה שניות אחרי העלייה ויקבל `plugin.boot` כרגיל, כך שקוד קיים שמסתנן לפי `runMode === 'background'` עובד ללא שינוי.
5. **האזנה מתמשכת לאירועים** — הצהירו את הנושאים ב-`activationEvents`; המופע יוער כשאירוע באמת קורה במקום לחיות כל הסשן.
6. **עדכנו `minAppVersion` ל-0.9.96** ומעלה — הסעיף אינו מוכר בגרסאות ישנות יותר.
7. שימו לב לכיבוי האוטומטי אחרי חוסר פעילות (סעיף קודם) — בלי טיימרים ארוכים, state ששורד ב-`storage`.

תוסף שהצהיר `contributes.startup` יוצא ממסלול הטעינה המיידית כבר ב-0.9.96 — אין מצב ביניים של ריצה כפולה.

התיעוד שלהלן מתאר את המסלול הישן, לתחזוקת תוספים שטרם עברו. יש להסירו יחד עם המימוש הישן ב-0.9.98.

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
    "library.links.read",
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
    "bookmarks.read",
    "bookmarks.write",
    "tools.read",
    "notifications.send",
    "notifications.system",
    "app.run_on_startup",
    "app.background_keep_alive",
    "app.startup_contributions",
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

רשימת ההיתר הרשמית מנוהלת בקובץ `plugin_network_allowlist.txt` שבשורש הריפו `Otzaria/otzaria`, בענף **`dev`**:

<https://github.com/Otzaria/otzaria/blob/dev/plugin_network_allowlist.txt>

אוצריא מושכת את הקובץ הזה בזמן ריצה וטוענת אישורים ממנו **לזיכרון בלבד** עד סגירת האפליקציה. מיזוג עריכה של הקובץ ל-`dev` נכנס לתוקף **מיד אצל כל המשתמשים, בכל גרסה מותקנת** — אין צורך ב-release חדש של אוצריא.

### תהליך הוספת URL חדש

כל תוסף שזקוק לגישה ל-URL כלשהו ברשת **חייב**:

1. להצהיר על ה-URL ב-`manifest.json` תחת `network.allowlist`.
2. לפנות למתחזקי אוצריא (או לפתוח Pull Request לענף `dev`) כדי להוסיף את ה-URL לקובץ הנ"ל.

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
- `contexts` הוא מערך ויכול להכיל את `reader-selection`, את `reader-page-shape-selection`, או את שניהם באותו פריט. מ-`0.9.97` נתמך גם `reader-highlight` (ראו למטה). ערכי `contexts` חייבים להיות חוקיים וייחודיים. פריט שלא מגדיר `contexts` מופיע בשני הקשרי הבחירה (כהתנהגות הרישום המקורית).
- ילד שלא מגדיר `contexts` יורש את המערך של אביו. ילד שמגדיר `contexts` במפורש מוצג רק בהקשרים שלו, ללא איחוד אוטומטי עם הקשר האב; ההקשרים המפורשים חייבים להיות תת־קבוצה של הקשרי האב.
- אפשר להגדיר `onClickEvent` או `onColorClickEvent` כאירוע מותאם אישית

**בחירה חוצת־פסקאות — `selection.sections` (מ-`0.9.97`):**
כשהבחירה משתרעת על כמה פסקאות, ה־`selection` שנמסר לאירועי הלחיצה של
פריטי התפריט כולל מערך `sections` — איבר לכל פסקה, עם `sectionIndex`,
`sourceRange` ו־`renderedRange` מלאים משלה. השדות העליונים נשארים כבעבר
(ללא `sourceRange`, לתאימות עם תוספים קיימים). תוסף שמחיל פעולה על
הבחירה (הדגשה, הערה) צריך לפעול על כל איבר בנפרד:

```javascript
Otzaria.on('contextMenu.colorClicked', async (data) => {
  const targets = data.selection.sections
    ?? [data.selection];                       // בחירה חד־פסקתית — כרגיל
  for (const target of targets) {
    if (!target.sourceRange) continue;
    await Otzaria.call('reader.setHighlight', {
      bookId: target.bookId,
      sectionIndex: target.sectionIndex,
      range: target.sourceRange,
      style: { backgroundColor: '#FFEB3B' }
    });
  }
});
```

**ההקשר `reader-highlight` (מ-`0.9.97`):**
פריט בהקשר זה מופיע בלחיצה ימנית על טקסט שמודגש על־ידי תוסף — **גם כשאין
בחירה פעילה**. ה־Host מזהה אילו הדגשות נמצאות מתחת לנקודת הלחיצה, ואירוע
הלחיצה מקבל `selection.clickedHighlights` — מערך של
`{ highlightId, pluginId }`. התוסף פועל רק על ההדגשות שבבעלותו
(`reader.clearHighlight` על מזהה של תוסף אחר מחזיר שגיאה ממילא). שימוש
אופייני: פריט "הסר סימון" שזמין בלחיצה על ההדגשה עצמה:

```javascript
await Otzaria.call('reader.addContextMenuItem', {
  id: 'my-remove-highlight',
  title: 'הסר סימון',
  icon: 'eraser_24_regular',
  contexts: ['reader-highlight'],
  onClickEvent: 'myPlugin.removeClicked'
});

Otzaria.on('myPlugin.removeClicked', async (data) => {
  for (const clicked of data.selection?.clickedHighlights ?? []) {
    await Otzaria.call('reader.clearHighlight', {
      highlightId: clicked.highlightId
    }).catch(() => {});
  }
});
```

בגרסאות שלפני `0.9.97` רישום עם `reader-highlight` נדחה עם
`error.unsupported_context` — עטפו את הקריאה ב־catch כדי לתמוך בשתי
הגרסאות.

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

### Event: `reader.context_menu_item_clicked`
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

### `reader.addToolbarItem`
**הרשאה:** `reader.toolbar`

**זמין מגרסה:** `0.9.97`

רישום פקד בשורת הפקדים של מסך העיון (ספר טקסט ו-PDF) — לחצן בודד,
תפריט נפתח או לחצן מפוצל, באותו מראה של הפקדים המובנים. כל תוסף יכול לרשום לכל היותר
**שני פקדים**; עדכון פקד קיים באותו `id` אינו צורך מקום נוסף במכסה.
כשאין מקום בשורה, הפקד נבלע אוטומטית בתפריט "עוד פעולות" (overflow).

```javascript
// לחצן בודד
await Otzaria.call('reader.addToolbarItem', {
  id: 'my-button',              // מזהה ייחודי (חובה)
  title: 'שמור מראה מקום',      // tooltip + טקסט בתפריט ה-overflow (חובה)
  icon: 'bookmark_24_regular',  // שם אייקון FluentUI System Icons (חובה בפקד עליון)
  openPlugin: true,             // לחיצה תפתח את דף התוסף (אופציונלי)
  param: 'save-mode'            // ערך חופשי שיוחזר ב-payload של הלחיצה (אופציונלי)
});

// תפריט נפתח
await Otzaria.call('reader.addToolbarItem', {
  id: 'my-menu',
  type: 'menu',
  title: 'סימון',
  icon: 'highlight_24_regular',
  children: [
    { id: 'add-mark', title: 'הוסף סימון', icon: 'add_24_regular' },
    { id: 'clear-marks', title: 'נקה סימונים', onClickEvent: 'marks.clear' }
  ]
});

// לחצן מפוצל — פעולה ראשית, ולצידה חץ שפותח את הילדים
await Otzaria.call('reader.addToolbarItem', {
  id: 'open-edition',
  type: 'split',
  title: 'פתח במהדורה המועדפת',   // הפעולה הראשית: לחיצה על האייקון
  icon: 'book_24_regular',
  param: 'default',
  children: [
    { id: 'edition-a', title: 'מהדורת ורשה' },
    { id: 'edition-b', title: 'מהדורת וילנא' }
  ]
});
// true
```

**הערות:**
- `type` יכול להיות `button` (ברירת מחדל), `menu` או `split`. תפריט ולחצן
  מפוצל חייבים `children` (עד 20 ילדים, לחצנים בלבד — אין קינון תפריטים)
- בלחצן מפוצל, לחיצה על החלק הראשי שולחת אירוע לחיצה של הפקד עצמו (עם ה-`id`
  וה-`param` שלו), ולחיצה על חץ התפריט שולחת את האירוע של הילד שנבחר. בתפריט
  ה-overflow הפקד מוצג כתת-תפריט שהפעולה הראשית היא פריטו הראשון
- הפקדים נשמרים בזיכרון בלבד — יש לרשום מחדש בכל `plugin.boot`. לפקד קבוע
  שקיים גם בלי שהתוסף רץ, העדיפו רישום דקלרטיבי ב-`contributes.startup`
  (ראו "תרומות עלייה דקלרטיביות")
- `contexts` הוא מערך ויכול להכיל את `reader-text` (ספר טקסט), את
  `reader-pdf` (ספר PDF), או את שניהם. פקד שלא מגדיר `contexts` מופיע
  בשני ההקשרים. ילד יורש את הקשרי אביו, וילד שמגדיר `contexts` במפורש
  חייב תת־קבוצה של הקשרי האב
- אם פקד עם אותו `id` כבר קיים, הוא יוחלף
- עם `openPlugin: true`, לחיצה מעבירה את המשתמש לדף התוסף ואירוע הלחיצה
  נמסר לדף גם אם הוא נטען רק עכשיו (כמו בתפריט ההקשר)
- אפשר להגדיר `onClickEvent` מותאם אישית לכל פקד או ילד; בהיעדרו נורה
  האירוע `reader.toolbar_item_clicked`

---

### `reader.removeToolbarItem`
**הרשאה:** `reader.toolbar`

**זמין מגרסה:** `0.9.97`

הסרת פקד שנרשם קודם משורת הפקדים.

```javascript
await Otzaria.call('reader.removeToolbarItem', {
  id: 'my-button'
});
// true
```

---

### `reader.updateToolbarItem`
**הרשאה:** `reader.toolbar`

**זמין מגרסה:** `0.9.97`

מעדכן פקד של התוסף הקורא ללא רישום מחדש. ניסיון לעדכן פקד שאינו קיים או
שאינו שייך לתוסף מחזיר `error.not_found`.

```javascript
await Otzaria.call('reader.updateToolbarItem', {
  id: 'my-button',
  patch: { title: 'שמור שוב', icon: 'bookmark_add_24_regular' }
});
```

---

### Event: `reader.toolbar_item_clicked`
**הרשאה:** אין צורך בהרשאה נוספת — נשלח רק לפלאגין שרשם את הפקד

נורה כאשר המשתמש לוחץ על פקד (או על פריט בתפריט נפתח) שהפלאגין רשם.

```javascript
Otzaria.on('reader.toolbar_item_clicked', (data) => {
  console.log('נלחץ פקד:', data.itemId);   // בתפריט — ה-id של הילד שנבחר
  console.log('הקשר:', data.context);       // 'reader-text' או 'reader-pdf'
  console.log('מיקום:', data.currentRef);
  console.log('ספר:', data.currentBook);
});
// {
//   itemId: "my-button",
//   context: "reader-text",
//   currentBook: "בראשית",
//   currentBookId: "בראשית",
//   currentId: 123,
//   currentType: "text",
//   currentIndex: 40,
//   currentRef: "בראשית פרק א",
//   param: "save-mode"   // הערך שנמסר ברישום (null אם לא נמסר)
// }
```

---

### Event: `reader.selection_changed`
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
//   currentIndex: 0,
//   id: 42,            // מ-0.9.97: זהות הספר הקנונית (כשידועה)
//   type: "text",
//   source: "library"
// }
```

---

### Event: `reader.sectionContentChanged`
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
    "reader.toolbar",
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
