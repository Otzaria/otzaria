# מדריך API למפתחי תוספים - אוצריא

מסמך זה מרכז את כל ה-APIs הזמינים לתוספים באוצריא.

---

## כפתור לשונית חדשה של תוסף

`plugin.setNewTabPage({enabled: true})` דורש `navigation.write` ומחזיר boolean.
בעלים ראשון מקבל את כפתור `+`; בקשה מתחרה מחזירה `false` ומציגה הודעה למשתמש
עם אפשרות לבחור בעלים. החלטת `plugin.new_tab_page` נשמרת בהרשאות התוספים רק
אחרי בקשת רישום בפועל; אין צורך להוסיף אותה למניפסט. אין תור של בקשות נדחות.
המשתמש יכול לשנות את הבחירה בהרשאות התוסף. דחיית '+' אינה שוללת ניווט רגיל.
`enabled: false` משחרר את הרישום ומאפשר בקשה חדשה, אך אינו מבטל חסימה שהמשתמש בחר. שלילת הרשאת
הכפתור או `navigation.write`, השבתה והסרה משחררות את הבעלות הפעילה.

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
| `bookUid` | **המזהה היציב המומלץ** — מחרוזת חוצה-ספקים (`id:<n>` לספרייה, `uid:<n>` לספר אישי, `ext:<...>` לספר חיצוני, `db:<slug>:<id>` לספר ממסד ספרים מצורף). זהו המזהה שמנוע החיפוש כבר משתמש בו: יציב בין עדכוני ספרייה והעברת ספרייה, ושורד שינויי כותרת. **מומלץ לתוסף לאחסן אותו במקום כותרת.** |
| `source` | מקור הספר: `"library"` לספרייה המובנית, `"user"` ל־`user_books.db`, `"external"` לקטלוג חיצוני, או `"attached"` למסד ספרים מצורף (ראו [personal_databases.md](../personal_databases.md); לזיהוי חד-משמעי השתמשו ב-`bookUid`). חובה לשלוח אותו עם `id` כאשר ה־ID עלול להתנגש בין מסדי נתונים. |

> **יציבות `bookUid` ו-fallback חינני:** גם `bookUid` עלול להתייתם במקרה קצה נדיר — ספר שגם משנה שם וגם עובר עריכה מסיבית באותה גרסת ספרייה (זיהוי שינוי-השם הוא היוריסטי). תוסף השומר `bookUid` צריך לשמור לצדו גם את הכותרת האחרונה שנראתה, וליפול אליה בחן אם ה-`bookUid` לא נמצא עוד.

### APIs שמחזירים זהות מלאה

| API | id | type | bookId | bookUid |
|-----|-----|------|--------|---------|
| `library.findBooks` | ✓ | ✓ | ✓ | ✓ |
| `library.resolveRef` | ✓* | ✓* | ✓ | ✓* |
| `library.getBookMetadata` | ✓ | ✓ | ✓ | ✓ |
| `library.getBookDetails` | ✓ | ✓ | ✓ | ✓ |
| `library.listRecentBooks` | ✓ | ✓ | ✓ | ✓ |
| `library.getTree` | ✓ | ✓ | ✓ | ✓ |
| `library.openBookFile` | קלט | קלט | קלט | קלט |
| `reader.openBook` | קלט | קלט | קלט | קלט |
| `reader.openBookAtRef` | קלט | קלט | קלט | קלט |
| `reader.printRange` | קלט | קלט | קלט | קלט |

\* ב-`library.resolveRef` השדות `id`/`type`/`bookUid` חסרים כשההתאמה היא ספר
אישי או PDF ממערכת הקבצים — ראה את האזהרה בתיאור המתודה.
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

## שמות הקודש בטקסט שמגיע לתוסף

**מגרסה:** 0.9.98.1

המשתמש בוחר בהגדרות התצוגה איך ייכתבו שמות הקודש: שם הוי"ה — ככתבו, `יקוק`,
`ה'`, `יי` או `ידוד`; ושאר השמות (אלהים, אדני, שדי, צבאות ועוד) — ככתבם או
בצורה חלופית (`אלקים`, `אד-ני`, `ש-די`, `צבקות`). **כל API שמוסר לתוסף טקסט
מתוך ספר מחיל את הבחירה הזו כברירת מחדל**, כפי שהקורא היה מציג את אותו ספר:

- **ההגדרה נקבעת ברגע הקריאה.** שינוי שהמשתמש עשה לפני שנייה חל כבר בקריאה
  הבאה, בלי טעינה מחדש של התוסף. טקסט שהתוסף שמר קודם לכן אינו מתעדכן מעצמו —
  ראו [`app.getDivineNamesDisplay`](#appgetdivinenamesdisplay).
- **כמו בקורא:** ספר שפתוח בכרטיסייה — ההגדרות של הכרטיסייה (כולל שינוי זמני
  מסרגל הכלים) מעל הגדרות הספר וההגדרה הכללית. ספר שאינו פתוח — הגדרות הספר
  (כשהגדרות לפי ספר מופעלות), שכבת התנ"ך וההגדרה הכללית. מפרשים ותוכן קישורים —
  לפי הגדרות המפרשים.

**מה מוחלף באיזה טקסט:**

| הטקסט | מה מוחלף | איפה |
|-------|----------|------|
| שורות ספר שיש להן זהות במסד | שם הוי"ה לפי הסגנון; שאר השמות — רק במופעים שמסד הספרייה מסמן, ורק אם המשתמש בחר להחליף אותם | `library.getBookContent`, `library.getLinkContent`, הבחירה בטקסט הראשי (`reader.getSelection`, `reader.selection_changed`, אירועי תפריט ההקשר), השכבה המוצגת (`rendered`) של `reader.getSectionTextMap` ו-`reader.findTextOccurrences` |
| טקסט נגזר בלי זהות שורה | שם הוי"ה בלבד (זיהוי לפי תבנית, כמו בתוצאות החיפוש של אוצריא) | תקצירי `search.fullText` / `search.query`, כותרות `library.getBookToc` / `library.getBookAltToc`, `heTitle` של `library.listBookAltStructures`, `anchor.label` של `library.getLinks`, טקסט שסומן במפרש או ב-PDF ונמסר בתפריט ההקשר |
| מידע על ספרים וכלים | שם הוי"ה בלבד, לפי ההגדרה לספר (או הכללית) | `shortDescription` / `fullDescription` של `library.getBookDetails`, `meanings` של `tools.dictionary`, `summary` / `remember` של `tools.biographies` |
| מסד נתונים של טקסט ספרייה | שם הוי"ה בלבד, לפי ההגדרה הכללית, בכל ערך מחרוזת בתוצאה | `database.query`, `database.batchQuery` ו-`database.select` הדקלרטיבי על המקור `talmud_synopsis` |

> **מחבר מילים סמוי (U+2060).** בצורות החלופיות של שאר השמות יש מקף ASCII
> (`ש-די`), ובתצוגה בא אחריו U+2060 כדי שהשם לא יישבר בין שורות. הכלל:
>
> - **כל שדה טקסט רגיל — בלי התו**, ב-`reader.getSelection`, באירועים ובכל
>   מתודה: תוכן ספר (`library.getBookContent`), `content` של קישורים, תקצירים,
>   `text`, `selectedText`, `renderedSelectedText`, `sourceSelectedText` ו-`normalizedSelectedText`,
>   גם בכל איבר של `sections`.
> - **מבנה שנושא אופסטים של השכבה המוצגת — עם התו**, כי האופסטים נספרים איתו:
>   `renderedText`, הטוקנים, המילים והתווים של `reader.getSectionTextMap`
>   בשכבה `rendered`; טווחי `reader.findTextOccurrences` בשכבה הזו; ו-`renderedRange`
>   של בחירה — `start`/`end` וגם `exactText`, `beforeText` ו-`afterText` שבתוכו.
>
> לכן `renderedSelectedText` עשוי להיות קצר מ-`renderedRange.exactText` בתווים
> האלה. לפני השוואה או הצגה של מבנה עם אופסטים הסירו אותו:
> `s.replace(/\u2060/g, '')`.

### מה נשאר כפי שנשמר

אלה אינם מסוננים לעולם, כי הם עוגנים או מפתחות שחייבים להתאים לספר השמור:

- **שכבת המקור** — `layer: 'source'` ב-`reader.findTextOccurrences` /
  `reader.getSectionTextMap`, `sourceText`, `sourceSelectedText` ו-`sourceRange`.
  זה העוגן היציב ש-`reader.setHighlight` מקבל.
- **עוגני הדגשות** — מה שמחזיר `reader.getHighlights`.
- **תיקונים** — סשן התיקונים (`reader.beginCorrectionSession` והפעולות שלו)
  ו-`feedback.submitBookCorrection` עובדים מול הנוסח השמור, והתיקון חייב
  להתאים לו.
- **מפתחות לחיפוש ולניווט** — `ref`, `currentRef`, `reference`,
  `targetHeRef`, כתובות בהיסטוריה ובסימניות, ושמות ספרים. הם נשארים כפי שנשמרו
  כדי שאפשר יהיה להחזיר אותם ל-`reader.openBookAtRef` או ל-`library.resolveRef`.
  כשמציגים אותם למשתמש — סננו בעצמכם (ראו האזהרה להלן).
- **אופסטים מול הטקסט השמור** — `anchor.start` / `anchor.end` של
  `library.getLinks` נספרים בטקסט השמור, כלומר מול
  `library.getBookContent` עם `rawDivineNames: true`.
- **קבצים בינאריים** — [`library.openBookFile`](#libraryopenbookfile) מוסר את
  הקובץ עצמו (PDF, DOCX, EPUB וכו'). אוצריא אינה משנה את תוכנו: טקסט שהתוסף
  מחלץ מהקובץ ומציג למשתמש — **סננו בעצמכם** לפי
  [`app.getDivineNamesDisplay`](#appgetdivinenamesdisplay).

> 💡 **נווטו לפי `index`, לא לפי טקסט הכותרת.** כותרת מסוננת מתוכן העניינים
> (למשל `ה'` במקום השם) עשויה שלא להתאים לשום `ref`. העבירו את ה-`index` של
> הרשומה ל-`reader.openBook` או ל-`reader.scrollToSection`.

### `rawDivineNames` — טקסט כפי שנשמר

`rawDivineNames: true` מחזיר את השמות כפי שנשמרו, בלי בחירת המשתמש. הפרמטר
חייב להיות בוליאני (ערך אחר: `error.invalid_params`); השמטתו או `false` הם
ברירת המחדל המסוננת. **קראו קודם את האזהרה להלן.**

| API | מה מגיע גולמי |
|-----|---------------|
| `library.getBookContent` | כל התוכן. עם `textReaderDisplay: true` שאר פרופיל התצוגה נשאר, ורק השמות גולמיים |
| `library.getBookToc`, `library.getBookAltToc` | `text` |
| `library.listBookAltStructures` | `heTitle` |
| `library.getLinks` | `anchor.label` (משפיע רק עם `includeAnchors: true`, אך נבדק תמיד) |
| `library.getBookDetails` | `shortDescription`, `fullDescription` |
| `tools.dictionary` | `meanings` |
| `tools.biographies` | `summary`, `remember`, `description` של `works` |
| `database.query`, `database.batchQuery` | ערכי המחרוזת במקור `talmud_synopsis` (הפרמטר הוא שדה של כל שאילתה) |
| `library.getLinkContent` | `content` |
| `search.fullText`, `search.query` | `text` של כל תוצאה |
| `reader.getSelection` | `text`, `renderedSelectedText`, `normalizedSelectedText` ו-`renderedRange` (וכך גם בכל איבר של `sections`) |
| `reader.findTextOccurrences`, `reader.getSectionTextMap` | השכבה `rendered`: שאר פרופיל התצוגה נשאר, ורק השמות גולמיים |

באירועים ההגדרה היא לפי נושא — [`events.setOptions`](#eventssetoptions). בפריטי
תפריט ההקשר היא שדה של הפריט — `rawDivineNames` ב-[`reader.addContextMenuItem`](#readeraddcontextmenuitem).

> **מגבלה — טקסט שנלקח מהמסך.** בטקסט שסומן במפרש או ב-PDF (תפריט ההקשר
> ואירועיו), ובבחירה בטקסט הראשי שאי אפשר לעגן (`reader.getSelection`,
> `reader.selection_changed`), אין לאוצריא את הנוסח השמור. שם `rawDivineNames: true`
> מחזיר את הטקסט כפי שהוצג על המסך — והוא עשוי כבר להיות מסונן לפי ההגדרה
> שהייתה בתצוגה.

> ⚠️ **אל תבקשו טקסט גולמי אלא אם התוסף באמת זקוק למקור כפי שנשמר** — למשל
> להשוואה מול המקור, לעיבוד פנימי שאינו מוצג, או כדי לסנן בעצמכם לפי
> [`app.getDivineNamesDisplay`](#appgetdivinenamesdisplay). טקסט גולמי שמוצג
> למשתמש, מודפס, נשמר בקובץ או נשלח החוצה עוקף את בחירת המשתמש באופן כתיבת
> שמות הקודש, ועלול להציג לו שם קודש בדיוק באופן שביקש להימנע ממנו. **קיבלתם
> טקסט גולמי והוא מגיע בסוף לעיני המשתמש? סננו אותו בעצמכם לפי ההגדרה.** אותו
> כלל חל על המפתחות שנשארים גולמיים תמיד (`ref`, כותרות בהיסטוריה וכו').

**מארחים ישנים.** לפני 0.9.98.1 לא היה סינון אחיד: רוב ה-APIs מסרו את הטקסט כפי
שנשמר, ושדות שנלקחו מהמסך (כמו `text` של בחירה) — כפי שהוצגו. הפרמטר
`rawDivineNames` אינו מוכר שם: רוב המתודות מתעלמות ממנו, אבל `search.query`
דוחה כל פרמטר לא מוכר ב-`error.invalid_params`. תוסף שתומך בגרסאות קודמות שולח
אותו רק כשגרסת אוצריא (`payload.app.version` ב-`plugin.boot`) היא 0.9.98.1 ומעלה.

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
| `error.forbidden` | `permission` | ההרשאה קיימת אך היעד עצמו חסום — נתיב מחוץ לתיקייה מאושרת, תיקייה מוגנת, URL שאינו ב-allowlist, או ספר שהמו"ל הגביל את מסירת הטקסט שלו |
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
| `app.getDivineNamesDisplay` | 0.9.98.1 |
| `app.registerShortcut` | 0.9.97 |
| `app.unregisterShortcut` | 0.9.97 |
| `app.updateShortcut` | 0.9.97 |
| `fonts.resolveFamilies` | 0.9.97 |
| `fonts.listInstalled` | 0.9.97 |
| `library.findBooks` | 0.9.89 |
| `library.resolveRef` | 0.9.97 |
| `library.getBookMetadata` | 0.9.89 |
| `library.getBookDetails` | 0.9.98 |
| `library.getBookProtections` | 0.9.98.1 |
| `library.resolveBooks` | 0.9.97 |
| `library.resolveCategoryPaths` | 0.9.97 |
| `library.listRecentBooks` | 0.9.89 |
| `library.getBookContent` | 0.9.89 |
| `library.getBookToc` | 0.9.89 |
| `library.listBookAltStructures` | 0.9.96 |
| `library.getBookAltToc` | 0.9.96 |
| `library.getTree` | 0.9.93 |
| `library.openBookFile` | 0.9.98 |
| `library.getCommentators` | 0.9.97 |
| `library.getLinks` | 0.9.97 |
| `library.getRawLinks` | 0.9.97 |
| `library.getLinkTargetsSummary` | 0.9.97 |
| `library.getLinkContent` | 0.9.97 |
| `library.refreshUserBooks` | 0.9.97 |
| `library.setProviderBooks` | 0.9.98 |
| `network.fetchStream` | 0.9.97 |
| `network.download` | 0.9.93 |
| `network.fetchFile` | 0.9.98.1 |
| `search.fullText` | 0.9.89 |
| `search.query` | 0.9.97 |
| `search.getOptions` | 0.9.97 |
| `search.setFieldText` | 0.9.98.1 |
| `search.setFieldActionState` | 0.9.98.1 |
| `search.endFieldSession` | 0.9.98.1 |
| `reader.openBook` | 0.9.89 |
| `reader.openBookAtRef` | 0.9.89 |
| `reader.printRange` | 0.9.98.1 |
| `reader.openSearchTab` | 0.9.89 |
| `reader.getCurrentState` | 0.9.89 |
| `reader.getDefaultTextReader` | 0.9.98.1 |
| `reader.reportTextReaderLocation` | 0.9.98.1 |
| `reader.setDefaultTextReader` | 0.9.98.1 |
| `reader.setTextReaderFontSize` | 0.9.98.1 |
| `reader.getCurrentRef` | 0.9.89 |
| `reader.closeTab` | 0.9.97 |
| `reader.activateTab` | 0.9.97 |
| `reader.getSelection` | 0.9.89 |
| `reader.getActiveCommentators` | 0.9.97 |
| `reader.setActiveCommentators` | 0.9.97 |
| `reader.getPageShapeLayout` | 0.9.97 |
| `reader.setPageShapeCommentatorVisibility` | 0.9.97 |
| `reader.scrollToSection` | 0.9.97 |
| `reader.getHighlightCapabilities` | 0.9.97 |
| `reader.findTextOccurrences` | 0.9.95 |
| `reader.getSectionTextMap` | 0.9.95 |
| `reader.beginCorrectionSession` | 0.9.98.1 |
| `reader.getCorrectionSession` | 0.9.98.1 |
| `reader.restoreCorrectionDraft` | 0.9.98.1 |
| `reader.resetCorrection` | 0.9.98.1 |
| `reader.endCorrectionSession` | 0.9.98.1 |
| `reader.acknowledgeCorrectionDraft` | 0.9.98.1 |
| `reader.listCorrectionDrafts` | 0.9.98.1 |
| `reader.getCorrectionDraft` | 0.9.98.1 |
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
| `workspace.list` | 0.9.97 |
| `workspace.getActive` | 0.9.97 |
| `workspace.create` | 0.9.97 |
| `workspace.switch` | 0.9.97 |
| `navigation.goTo` | 0.9.89 |
| `plugin.openSelf` | 0.9.96 |
| `plugin.setNewTabPage` | 0.9.97 |
| `plugin.openOther` | 0.9.97 |
| `plugin.backgroundDone` | 0.9.97 |
| `plugin.setRestoreState` | 0.9.98.1 |
| `plugin.listInstalled` | 0.9.97 |
| `events.setOptions` | 0.9.98.1 |
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
| `ui.print` | 0.9.97 |
| `ui.printFile` | 0.9.98.1 |
| `ui.exportPdf` | 0.9.97 |
| `ui.setUnsavedChanges` | 0.9.97 |
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
| `fs.deleteFolder` | 0.9.98 |
| `fs.moveEntry` | 0.9.98 |
| `fs.pickUserFolder` | 0.9.98 |
| `fs.listUserFolder` | 0.9.98 |
| `fs.openFolderFile` | 0.9.98 |
| `fs.revokeFolder` | 0.9.98 |
| `feedback.sendEmail` | 0.9.89 |
| `feedback.report` | 0.9.97 |
| `feedback.submitBookCorrection` | 0.9.98.1 |
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
| `tools.biographies` | 0.9.98 |
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

> מקור האמת לאכיפה הוא הקטלוג `pluginApiMethods` ב-`lib/plugins/models/plugin_api_catalog.dart`. הטבלה כאן תואמת לגרסאות הקטלוג, ו-`test/plugins/plugin_method_versions_test.dart` מוודא שהן זהות.

---

## app.* - מידע על האפליקציה

**הרשאה נדרשת:** `app.info.read` (למעט `app.getUserEmail` שמצריכה `app.user_email.read` - ראה למטה)

### `app.getInfo`
מחזיר מידע על גרסת האפליקציה והפלטפורמה.

```javascript
const { data } = await Otzaria.call('app.getInfo');
// { version: "0.9.98.1", buildNumber: "99801", platform: "windows" }
```

`version` כולל את גרסת התיקון (hotfix) כרכיב רביעי, באותו פורמט שבו `minAppVersion` מציין גרסת תיקון. בלי
גרסת תיקון הוא בן שלושה רכיבים (`0.9.98`). אותו ערך מגיע ב-`payload.app.version`
של `plugin.boot`. זו אינה גרסת SemVer, ולכן `semver.valid('0.9.98.1')` מחזיר
`null`. השוו רכיב אחר רכיב, ורכיב חסר נחשב 0.

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
//     fontFamily:             "FrankRuhlCLM",   // גופן הקריאה — לטקסט הספר בלבד
//     fontSize:               25,    // לפי הגדרת המשתמש — אל תניח ערך קבוע!
//     lineHeight:             1.5,
//     commentatorsFontFamily: "NotoRashiHebrew",
//     commentatorsFontSize:   22,
//     uiFontFamily:           "Rubik",           // גופן הממשק — כפתורים ותפריטים
//   }
// }
```

הצבעים הם **Material Design 3 Color Roles** בפורמט hex RGB (`#rrggbb`).
ראה [DESIGN_GUIDE.md](DESIGN_GUIDE.md) להסבר מלא על השימוש בהם.

> **`surfaceContainerHigh` — רקע פס הכותרת שלך.** התוסף נפתח כטאב קריאה ואוצריא אינה מציירת כותרת מעל ה-WebView; שם התוסף חייב להופיע בפס עליון קבוע בצבע הזה, כדי שיתיישר עם הסרגל העליון של מסכי הספרים. ראה [DESIGN\_GUIDE.md § סרגל כותרת התוסף](DESIGN_GUIDE.md#סרגל-כותרת-התוסף-top-bar).

> **גופנים מוטמעים אוטומטית:** כל הגופנים המובנים של אוצריא (`FrankRuhlCLM`, `TaameyDavidCLM`, `Shofar`, `NotoRashiHebrew`, `KeterYG`, `NotoSerifHebrew`, `Tinos`, `Rubik`, `TaameyAshkenaz`) נטענים ב-WebView של התוסף כ-`@font-face` עוד לפני ה-`plugin.boot`, ואיתם גם גופן מערכת שהמשתמש בחר בהגדרות. אין צורך לארוז קבצי גופן — מספיק `font-family: 'FrankRuhlCLM', serif;`. כל משפחה נשלחת עם ה-face הבולד האמיתי שלה (או עם טווח משקלים בגופן משתנה), כך ש-`font-weight: bold` מקבל ציור אות אמיתי ולא עיבוי מלאכותי. לממשק עצמו השתמש ב-`uiFontFamily` ולא בגופן הקריאה — גופן ספרים בכפתור בן 12px נראה מטושטש.

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

### `app.getDivineNamesDisplay`
**הרשאה:** `app.info.read` (הרשאת בסיס) · **מגרסה:** 0.9.98.1

מחזיר איך שמות הקודש יגיעו לתוסף בטקסט של ספר — לפי בחירת המשתמש ברגע הקריאה,
כפי שהקורא היה מציג את אותו ספר. כל API שמוסר טקסט של ספר מחיל את ההגדרה הזו,
אלא אם התוסף ביקש `rawDivineNames: true` (ראו
[שמות הקודש בטקסט שמגיע לתוסף](#שמות-הקודש-בטקסט-שמגיע-לתוסף)).

שני שימושים עיקריים: לדעת מראש מה התוסף יקבל (למשל כדי להשוות מחרוזת חיפוש
שהמשתמש הקליד מול טקסט מסונן), ותוסף שביקש טקסט גולמי ומציג אותו בסוף למשתמש —
כדי לסנן אותו בעצמו לפי אותה בחירה.

```javascript
const { data } = await Otzaria.call('app.getDivineNamesDisplay', { bookUid: 'id:1' });
// { holyName: 'kufKuf', otherNames: 'asIs', filtered: true, holyNameSample: 'יקוק' }
```

| פרמטר | משמעות |
|-------|---------|
| `id` / `bookUid` / `bookId` | אופציונלי — הספר, כמו ב-`library.getBookContent`. ספר שפתוח בכרטיסייה — לפי הכרטיסייה (כולל שינוי זמני מסרגל הכלים); אחרת — הגדרות הספר, שכבת התנ"ך וההגדרה הכללית. ספר שלא נמצא: `error.not_found` |
| `target` | `'body'` (ברירת מחדל) — טקסט הספר; `'commentary'` — מפרשים ותוכן קישורים. ערך אחר: `error.invalid_params` |

בלי ספר מוחזרת ההגדרה הכללית בלבד, בלי שכבת התנ"ך ובלי הגדרות של ספר. כשהתוצאה
נוגעת לספר מסוים — העבירו את זהותו.

| שדה | משמעות |
|-----|---------|
| `holyName` | `asIs` (ככתבו), `kufKuf` (`יקוק`), `hehApostrophe` (`ה'`), `doubleYod` (`יי`) או `daletDalet` (`ידוד`) |
| `otherNames` | `asIs` או `substitute`. גם ב-`substitute` מוחלפים רק מופעים שמסד הספרייה מסמן; בטקסט נגזר (תקצירים, כותרות) הם נשארים ככתבם |
| `filtered` | `true` כשמוחלף שם כלשהו — `holyName` אינו `asIs` או ש-`otherNames` הוא `substitute` |
| `holyNameSample` | שם הוי"ה כפי שיגיע לתוסף: `יהוה`, `יקוק`, `ה'`, `יי` או `ידוד` (בלי ניקוד) |

> **סינון עצמי.** את שם הוי"ה אפשר להחליף בעצמכם לפי `holyName`. את שאר השמות
> אי אפשר לשחזר נאמנה בלי הסימון שבמסד (`אל` שבתוך מילה אינו שם), ולכן תוסף
> שצריך טקסט מסונן מבקש אותו מה-API ולא מסנן טקסט גולמי בעצמו.

**ההגדרה יכולה להשתנות בכל רגע.** תוסף ששומר טקסט שקיבל (מטמון, תצוגה שכבר
צוירה) צריך לקרוא שוב לפני שהוא משתמש בו. אין אירוע ייעודי לשינוי הזה. שינוי
בהגדרה הכללית נמסר ב-`settings.changed` עם `key: 'key-text-display-policy'`
(הרשאה `events.subscribe:settings.changed`), ובקורא טקסט משובץ שינוי בתצוגת
הכרטיסייה שולח את פקודת `display` (ראו [DEFAULT_TEXT_READER.md](DEFAULT_TEXT_READER.md)).
שינוי בהגדרות של ספר בודד אינו מודיע על עצמו.

### `app.openUrl`
**הרשאה נדרשת:** `app.open_url`

פותח כתובת אינטרנט בדפדפן ברירת המחדל של מערכת ההפעלה (לא בתוך התוסף).

```javascript
await Otzaria.call('app.openUrl', { url: 'https://example.com' });
// מחזיר true כשהכתובת נפתחה, ו-false כשהמשתמש סירב
```

מותרות אך ורק כתובות `http`/`https`. סכמות אחרות (`file://`, `javascript:`, פרוטוקולים מותאמים) נדחות עם `error.forbidden`.

כתובת שהתוסף רשאי לפנות אליה ממילא ברשת (`network.allowlist` שאושר) נפתחת מיד. כל כתובת אחרת נפתחת רק אחרי שהמשתמש מאשר אותה בדיאלוג — הכתובת עצמה יכולה לשאת מידע לאתר. ממופע רקע, שאין לו דיאלוג, כתובת כזו אינה נפתחת.

### `app.registerShortcut` / `app.unregisterShortcut` / `app.updateShortcut`
**הרשאה נדרשת:** `app.shortcuts`

רישום קיצור מקלדת שהתוסף מציע. לחיצה על הקיצור במסך העיון מפעילה:

- **פקודה חופשית** — נשלח לתוסף אירוע `app.command` עם `{ command, shortcutId }`;
  התוסף מאזין עם `Otzaria.on('app.command', ...)` ומבצע.
- **פעולת תפריט הקשר** — `contextMenuItemId` מפנה לפריט שהוסף עם
  `reader.addContextMenuItem`; הקיצור מפעיל אותו בדיוק כמו לחיצה ימנית עליו
  (דורש טקסט מסומן בספר).

הקיצור מופיע במסך **הגדרות → קיצורי מקשים** תחת "קיצורי תוספים", והמשתמש
יכול לשנות אותו או לבטלו. הקיצור פעיל כשמסך העיון פתוח.

```javascript
// פקודה חופשית — התוסף מאזין ל-app.command ומבצע
await Otzaria.call('app.registerShortcut', {
  id: 'toggle-night-mode',
  label: 'מצב לילה',
  key: 'ctrl+alt+n',
  command: 'toggleNightMode',
});

Otzaria.on('app.command', (payload) => {
  if (payload.command === 'toggleNightMode') { /* ... */ }
});

// קיצור לפעולה שכבר נוספה לתפריט הלחיצה הימנית
await Otzaria.call('app.registerShortcut', {
  id: 'highlight-selection',
  label: 'הדגש את הסימון',
  key: 'ctrl+alt+h',
  contextMenuItemId: 'highlight-action',
});

// עדכון הקיצור (נכון לעכשיו רק key נתמך)
await Otzaria.call('app.updateShortcut', {
  id: 'toggle-night-mode',
  patch: { key: 'ctrl+alt+m' },
});

// הסרה
await Otzaria.call('app.unregisterShortcut', { id: 'toggle-night-mode' });
```

| שדה | טיפוס | חובה | תיאור |
|-----|-------|------|-------|
| `id` | string | כן | מזהה ייחודי לקיצור בתוך התוסף |
| `label` | string | כן | תווית תצוגה במסך קיצורי המקשים |
| `key` | string | לא | קיצור ברירת מחדל בפורמט קנוני (`ctrl+alt+x`); ריק = המשתמש מקצה |
| `command` | string | לא* | שם פקודה שנשלחת באירוע `app.command` |
| `contextMenuItemId` | string | לא* | מזהה פריט תפריט הקשר שהקיצור מפעיל |

\* נדרש לפחות אחד מ-`command` או `contextMenuItemId` — קיצור בלי יעד נדחה
עם `error.invalid_params`.

ניתן להצהיר על קיצורים גם **במניפסט** בלי להריץ קוד — ראו §
[contributes.startup.shortcuts](#contributesstartup---תרומות-עלייה-דקלרטיביות).

---

## fonts.* - גופנים למסמכים

### `fonts.resolveFamilies`

מחזיר כללי `@font-face` מוכנים להזרקה, שהבייטים שלהם מגיעים מהגופנים הארוזים של אוצריא או מגופני המערכת — **תחת שם שאתם מבקשים**.

למה זה קיים: `src: local()` בתוך WebView של תוסף פותר רק גופנים **מותקנים במערכת**, ולעולם לא את ה-faces שאוצריא מזריקה בעצמה. תוסף שמציג מסמך שמבקש גופן שאיש לא התקין אינו יכול להגיע לגופנים הארוזים בלי הבייטים.

זה משנה יותר ממראה: ב-DOCX, `w:lineRule="auto"` גוזר את גובה השורה ממדדי הגופן **שנבחר בפועל**, ולכן גופן חסר משנה את פריסת המסמך כולו.

לכל משפחה מבוקשת מציינים רשימת תחליפים לפי סדר עדיפות. מוחזר ה-`@font-face` של הראשון שאוצריא מצליחה להרכיב, כשהוא נושא את השם שביקשתם.

```javascript
const { data } = await Otzaria.call('fonts.resolveFamilies', {
  families: [
    { name: 'FrankRuehl DP', substitutes: ['FrankRuehl', 'FrankRuhlCLM', 'David'] }
  ]
});

const style = document.createElement('style');
style.textContent = data.css;
document.head.appendChild(style);
```

| שדה | טיפוס | הסבר |
|---|---|---|
| `families` | array | עד 24 פריטים. כל פריט: `name` (השם שהמסמך מבקש) ו-`substitutes` (עד 12 שמות, לפי סדר). |

מוחזר:

| שדה | טיפוס | הסבר |
|---|---|---|
| `css` | string | כללי `@font-face`, מופרדים בשורות. ריק כשלא נמצאה אף התאמה. |
| `resolved` | string[] | השמות המבוקשים שקיבלו face. |

המדיניות — אילו תחליפים ובאיזה סדר — נשארת אצלכם: אתם יודעים מה המסמך מבקש, ואוצריא נותנת רק את מה שרק היא יכולה לתת.

כללי `fonts.resolveFamilies` כוללים את בייטי הגופן כ-`data:` URL, ולכן ניתן לשמור או לייצא אותם גם אחרי סגירת אוצריא. ההחזרה הזאת עצמאית ממסלול הגופנים האוטומטי של דף התוסף.

הרשאה: `app.info.read` (baseline — אין דיאלוג נוסף).

---

### `fonts.listInstalled`

מחזיר את משפחות הגופנים **המותקנות במכונה**. בלי ארגומנטים.

למה זה קיים: `fonts.resolveFamilies` נותן בייטים, אבל כדי לבחור תחליף נכון צריך קודם לדעת מה בכלל קיים כאן. בלי הרשימה נותר רק לנחש, או לבקש בייטים של משפחה אחר משפחה רק כדי לגלות מי מהן נפתרת — יקר בהרבה מרשימת שמות.

```javascript
const { data } = await Otzaria.call('fonts.listInstalled');

const installed = new Set(data.families.map(f => f.name));
const hebrew = data.families.filter(f => f.scripts.includes('hebrew'));
```

מוחזר:

| שדה | טיפוס | הסבר |
|---|---|---|
| `families` | array | המשפחות המותקנות, ממוינות לפי שם. כל שם מופיע פעם אחת. |
| `platform` | string | הפלטפורמה, למשל `windows`. |

כל פריט ב-`families`:

| שדה | טיפוס | הסבר |
|---|---|---|
| `name` | string | השם **בדיוק כפי ש-CSS `font-family` מקבל אותו** — לא שם קובץ, ולא `David Bold`. |
| `scripts` | string[] | מתוך `latin` `hebrew` `arabic` `cyrillic` `greek` `cjk` `thai` `symbol`. משפחה מרובת-שפות נושאת כמה. |
| `monospace` | boolean | `true` לגופן ברוחב קבוע, למשל `Consolas`. |

פלטפורמה שאין בה מימוש מחזירה `families: []` — זו אינה שגיאה, ועליכם ליפול חזרה למדיניות התחליפים שלכם.

שתי מגבלות ב-Windows, שנובעות מ-GDI עצמו:

- גופני raster ישנים (`.fon` — `Terminal`, `Fixedsys`, `MS Sans Serif` וכדומה) **אינם ברשימה**, משום ש-WebView אינו מרנדר אותם ולכן שמם אינו שם שאפשר למסור ל-CSS.
- שם משפחה נקטע ב-31 תווים. `Bahnschrift SemiBold SemiCondensed`, למשל, חוזר כ-`Bahnschrift SemiBold SemiConden`. אין דרך לקבל אותו שלם דרך GDI.

הרשאה: `app.info.read` (baseline — אין דיאלוג נוסף).

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

### `library.resolveRef`
**הרשאה:** `library.books.read`

פותר הפניה חופשית שנכתבה בידי אדם — שם ספר ומיקום יחד — למיקום קונקרטי,
בלי לפתוח אותו. זו הצורה השאילתתית של `reader.openBookAtRef`, ומאחוריה אותו
מנוע `find_ref` שמפעיל את מסך "איתור מקורות".

השתמש בה כדי לבנות קישור עומק, להציע השלמה בזמן הקלדה, או לאמת הפניה לפני
שמציגים אותה. לניווט בפועל השתמש ב-`reader.openBookAtRef`.

```javascript
const { data } = await Otzaria.call('library.resolveRef', {
  ref: 'פסחים לד',
  limit: 5  // אופציונלי, ברירת מחדל: 20
});
// [{
//   id: 42, bookId: "פסחים", bookUid: "id:42", type: "text",
//   title: "פסחים", reference: "פסחים דף לד", index: 1234,
//   isPdf: false, isSourceLine: true, isUserBook: false,
//   bookPath: "ש\"ס, בבלי"
// }, ...]
```

התוצאות מדורגות — הראשונה היא ההתאמה הטובה ביותר, לפי אותו דירוג שמסך
"איתור מקורות" מציג. הפניה קצרה משני תווים מוחזרת כרשימה ריקה.

`isSourceLine` מבחין בין שתי רמות דיוק: `true` = נפתר לשורת מקור מדויקת
(פסוק, סעיף) דרך אינדקס ההפניות; `false` = נפתר לכותרת בתוכן העניינים,
כלומר לרמת פרק או דף בלבד.

**בניית קישור עומק — קרא את זה:** `id` הוא המזהה שקישור `otzaria://open/book/<id>`
מצפה לו, אבל הוא מוחזר `null` כשההתאמה היא ספר אישי (`isUserBook`) או PDF
ממערכת הקבצים. `user_books.db` מקצה מזהים באותו טווח כמו ספריית הבסיס, ולכן
מזהה של ספר אישי אינו מזהה ספר יחיד ברמת האפליקציה. במקרה כזה נווט עם
`reader.openBookAtRef` (שמקבל גם כותרת), או השתמש ב-`otzaria://open/detection?q=<ההפניה>`
שמעביר את פתירת ההפניה לאוצריא עצמה.

```javascript
const hit = data[0];
const href = hit && hit.id != null
  ? (hit.isPdf
      ? `otzaria://open/pdf/${hit.id}?index=${hit.index}`
      : `otzaria://open/book/${hit.id}?index=${hit.index}`)
  : `otzaria://open/detection?q=${encodeURIComponent(ref)}`;
```

שים לב ש-`index` הוא אינדקס שורה (0-based) בספר טקסט, אך **מספר עמוד
(1-based)** ב-PDF — בדיוק כפי ששני נתיבי הקישור מצפים.

### `library.getBookMetadata`
**הרשאה:** `library.books.read`

קבלת מטא-דאטה על ספר ספציפי.

```javascript
const { data } = await Otzaria.call('library.getBookMetadata', {
  bookId: 'בראשית'
});
// { id: 1, bookId: "בראשית", title: "בראשית", categoryPath: "/תנך/תורה", topics: [...] }
```

### `library.getBookDetails`
**הרשאה:** `library.books.read` · **מגרסה:** 0.9.98

נתוני חלון "אודות הספר" של אוצריא — מחברים, דור, תקופה, מקום
ותאריך חיבור ופרסום, נושאים, תיאורים ומקור הטקסט. אותו מקור נתונים
שהדיאלוג עצמו קורא ממנו, כך שהערכים זהים למה שהמשתמש רואה.

קלט: אותם שדות זהות כמו `library.getBookMetadata` — `bookUid` (מומלץ), `id` או
`bookId`. ספר שלא נמצא → `null`.

```javascript
const { data } = await Otzaria.call('library.getBookDetails', {
  bookUid: 'id:183'
});
// {
//   id: 183, type: 'text', source: 'library', bookUid: 'id:183',
//   bookId: 'שולחן ערוך אורח חיים', title: 'שולחן ערוך אורח חיים',
//   authors: ['רבי יוסף קארו'], generation: 'אחרונים', era: 'אחרונים',
//   categories: 'הלכה', categoryPath: '/הלכה',
//   compositionDate: null, compositionPlace: 'צפת',
//   publicationDates: ['שס"ו'], publicationPlaces: ['וונציה'],
//   topics: ['הלכה'], shortDescription: '...', fullDescription: '...',
//   textSource: { key: 'Sefaria', name: 'ספריא', url: 'https://www.sefaria.org/texts' },
//   reference: '...', lineCount: 4210, libraryPath: 'הלכה/שולחן ערוך',
//   protection: { level: 0, textAvailable: true, editableExport: true,   // מ-0.9.98.1
//                 pdfExport: true, copyLimit: null, printLimit: null }
// }
```

שדה שאין לו ערך מוחזר כ-`null` (או כמערך ריק). שתי הערות:

- `textSource` הוא מקור הטקסט (ספריא, דיקטה וכדומה) — לא לבלבל עם שדה
  הזהות `source`, שהוא `library`/`user`/`external`. מקור שאינו מוכר מוחזר
  עם `name` זהה ל-`key` וללא `url`.
- `libraryPath` הוא הנתיב היחסי בספרייה בלבד. לספר אישי הוא `null` — נתיב
  הקובץ שלו אינו נחשף לתוספים.
- `protection` (מגרסה 0.9.98.1) — הגבלת המו"ל של הספר. ראו
  [`library.getBookProtections`](#librarygetbookprotections).
- `shortDescription` ו-`fullDescription` מגיעים עם שם הוי"ה לפי בחירת המשתמש
  לספר (מ-0.9.98.1); `rawDivineNames: true` מחזיר אותם כפי שנשמרו (ראו
  [שמות הקודש בטקסט שמגיע לתוסף](#שמות-הקודש-בטקסט-שמגיע-לתוסף)).

### `library.getBookProtections`
**הרשאה:** `library.books.read` · **מגרסה:** 0.9.98.1

הגבלת המו"ל (טבלת `book_protection` במסד) של כמה ספרים בקריאה אחת — הספר עצמו
ומפרשיו. מאפשר לתוסף לדעת **מראש** מה מותר, במקום לגלות זאת מ-`error.forbidden`
באמצע עבודה, ולהציג את ההגבלה למשתמש כמו הממשק: לא להציע פעולה שאסורה.

```javascript
const { data } = await Otzaria.call('library.getBookProtections', {
  items: [
    { bookUid: 'id:183' },                              // זהות ספר, כמו getBookMetadata
    { title: 'שער הציון', categoryId: 12 },            // מפרש, כפי שחוזר מ-getLinks
  ]  // עד 500
});
// [
//   { level: 1, textAvailable: false, editableExport: false, pdfExport: true,
//     copyLimit: 40, printLimit: null },
//   null   // ספר שלא נמצא
// ]
```

| שדה | משמעות |
|---|---|
| `level` | 0 — ללא הגבלה; 1–2 — רמת ההגבלה (רמה לא מוכרת מעל 2 נמסרת כ-2) |
| `textAvailable` | האם הטקסט נמסר לתוספים (`getBookContent`, `getLinkContent`, חיפוש) |
| `editableExport` | האם מותר לייצא לפורמט קל לעריכה — Word, טקסט, EPUB, FB2 |
| `pdfExport` | האם מותרת שמירה כ-PDF |
| `copyLimit` / `printLimit` | מספר השורות המרבי בהעתקה / בהדפסה; `null` — ללא הגבלה |

**תוסף שמייצא טקסט לקובץ צריך לבדוק את הספר ואת כל המפרשים שהוא כולל**, ולא
להציע ייצוא כש-`editableExport` הוא `false` — כמו שהממשק מסתיר את "ייצוא הספר".
ספר אישי אינו מוגבל.


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
  includeBooks: true,      // אופציונלי, ברירת מחדל: true — האם לכלול את רשימות הספרים
  types: ['docx', 'odt']   // אופציונלי (מ-0.9.98): רק ספרים מסוגים אלו
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

`types` (מגרסה 0.9.98) משאיר רק ספרים שה-`type` שלהם ברשימה, וגוזם כל קטגוריה
שאין תחתיה — בשום עומק — אף ספר כזה. כך עץ "ספרי Word" חוצה את הגשר כתת-עץ
קטן ולא כספרייה כולה. שורש שאין תחתיו אף ספר מתאים מוחזר ריק (`categories: []`),
לא `null`. בלי `types` ההתנהגות לא השתנתה. גרסה ישנה מתעלמת מהשדה ומחזירה את
העץ המלא, ולכן תוסף שתומך בה צריך לגזום גם בעצמו.

### `library.openBookFile`
**הרשאה:** `library.content.read` · **מגרסה:** 0.9.98

מוסר לתוסף את הקובץ שמאחורי ספר בספרייה — DOCX/ODT/RTF וכו', PDF או EPUB —
כ-`token` ו-`url` של קובץ משתמש רגיל. הבייטים אינם חוצים את הגשר והקובץ אינו
מועתק: הנתיב הקיים נרשם בשרת הקבצים, ועל ה-`token` עובדים
[`fs.resolveFileUrl`](#fsresolvefileurl),
[`fs.commitUserFileWrite`](#fscommituserfilewrite) ו-[`fs.revokeFile`](#fsrevokefile).

קלט: אותם שדות זהות כמו `library.getBookMetadata` — `bookUid` (מומלץ), `id` או
`bookId` + `type`.

```javascript
const { data } = await Otzaria.call('library.openBookFile', {
  bookUid: 'uid:42',
  access: 'readwrite'   // אופציונלי: 'read' (ברירת מחדל) או 'readwrite'
});
// data = { token, url, name, size, access, source }
```

`source` זהה לשדה הזהות (`library`/`user`/`attached`). כתיבה (`access: 'readwrite'`)
מותרת **לספר אישי בלבד** (`source: 'user'`) ודורשת גם `fs.user_files.write`;
על ספר של הספרייה מוחזר `error.permission_denied: library books are read-only`,
והתוסף פותח אותו מחדש לקריאה. `access` שחוזר הוא מה שה-token מאפשר בפועל.

פתיחה חוזרת של אותו קובץ — מכאן, מ-`fs.openFolderFile` או מ-`fs.pickUserFile`
קודם — מחזירה את **אותו `token`**, כדי שרשימת "אחרונים" שממופתחת לפיו לא
תתמלא כפילויות. token לקריאה משודרג לכתיבה כשהיא התבקשה ואושרה.

שמירה במקום של ספר אישי אינה משאירה טקסט ישן: מטמון ההמרה של המסמכים ממופתח לפי
גודל הקובץ וזמן השינוי שלו. כדי שגם החיפוש יכיר את התוכן החדש יש לקרוא
ל-`library.refreshUserBooks`.

שגיאות: `error.not_found` (ספר לא מוכר, או שהקובץ שלו נמחק),
`error.unsupported` (ספר בלי קובץ מקומי — טקסט מהמסד או ספר חיצוני),
`error.permission_denied`, `error.invalid_params` (אין זהות, או `access` לא חוקי).

**שמות הקודש.** הקובץ נמסר כפי שהוא, בלי הגדרת התצוגה של שמות הקודש. טקסט
שהתוסף מחלץ ממנו ומציג, מדפיס או שולח — עליו לסנן בעצמו לפי
[`app.getDivineNamesDisplay`](#appgetdivinenamesdisplay) (ראו
[שמות הקודש בטקסט שמגיע לתוסף](#שמות-הקודש-בטקסט-שמגיע-לתוסף)).

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

**שמות הקודש (מ-0.9.98.1):** התוכן מגיע עם שמות הקודש לפי בחירת המשתמש לספר הזה,
שם הוי"ה ושאר השמות שהמסד מסמן (ראו
[שמות הקודש בטקסט שמגיע לתוסף](#שמות-הקודש-בטקסט-שמגיע-לתוסף)).
`offset` ו-`limit` נספרים **בטקסט המסונן**, והסגנון `ה'` משנה את אורכו — אל
תערבבו אופסטים מקריאה מסוננת עם קריאה גולמית. `section` נמצא קודם בטקסט
המסונן; מחרוזת שאינה שם — למשל מהטקסט השמור, או כותרת מ-`library.getBookToc`
(שבה רק שם הוי"ה הוחלף) — מאותרת בטקסט השמור, והקריאה מתחילה מהמקום המקביל
בטקסט המסונן. מחרוזת שלא נמצאה כלל — הקריאה מתחילה מתחילת הספר.

- `rawDivineNames: true` — השמות כפי שנשמרו. ⚠️ ראו
  [האזהרה](#rawdivinenames--טקסט-כפי-שנשמר) לפני שימוש.
- `textReaderDisplay: true` (קורא משובץ בלבד) — פרופיל התצוגה של הכרטיסייה,
  כולל החלפת שאר השמות; ראו [DEFAULT_TEXT_READER.md](DEFAULT_TEXT_READER.md).

### `library.getBookToc`
**הרשאה:** `library.content.read`

קבלת תוכן עניינים של ספר.

```javascript
const { data } = await Otzaria.call('library.getBookToc', {
  bookId: 'בראשית'
});
// [{ text: "פרק א", index: 0, level: 1 }, ...]
```

`text` מגיע עם שם הוי"ה לפי בחירת המשתמש (מ-0.9.98.1); `rawDivineNames: true`
מחזיר אותו כפי שנשמר (⚠️ [האזהרה](#rawdivinenames--טקסט-כפי-שנשמר)). לניווט
העבירו את `index`, לא את `text`.

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

`heTitle` מגיע עם שם הוי"ה לפי בחירת המשתמש (מ-0.9.98.1); `rawDivineNames: true`
מחזיר אותו כפי שנשמר (⚠️ [האזהרה](#rawdivinenames--טקסט-כפי-שנשמר)). `key`
ו-`title` אינם משתנים.

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

`text` מגיע עם שם הוי"ה לפי בחירת המשתמש, כמו ב-`getBookToc` (מ-0.9.98.1);
`rawDivineNames: true` מחזיר אותו כפי שנשמר (⚠️ [האזהרה](#rawdivinenames--טקסט-כפי-שנשמר)).

### `library.refreshUserBooks`
**הרשאה:** `library.refresh` · **מ-0.9.97**

סורק מחדש את התיקיות האישיות שהמשתמש הגדיר, מעדכן את `user_books.db`
לפי מה שנמצא בהן, ומרענן בעקבות זאת את קטלוג הספרייה. זו בדיוק הפעולה
שמבצע הלחצן „סרוק מחדש תיקיות אישיות” בהגדרות.

**מתי להשתמש:** תוסף שמוריד למשתמש ספרים וכותב אותם לתיקייה אישית
(`network.download` / `fs.*` אל תוך תיקייה שהמשתמש אישר) — קורא לו בסיום, והספרים
מופיעים בספרייה בלי שהמשתמש יפעיל מחדש את אוצריא.

**אין פרמטרים.** אילו תיקיות ייסרקו נקבע מהגדרות המשתמש בלבד — התוסף אינו
מעביר נתיב, ולכן אינו יכול לגרום לסריקה של תיקייה שלא הוגדרה.

```javascript
const { data } = await Otzaria.call('library.refreshUserBooks');
// { addedBooks: 3, updatedBooks: 0, errors: [] }
```

| שדה | משמעות |
|------|---------|
| `addedBooks` | מספר הספרים החדשים שנוספו בסריקה. |
| `updatedBooks` | מספר הספרים שתוכנם השתנה ועודכן. |
| `errors` | כשלים חלקיים — קבצים בודדים שלא נסרקו. מערך ריק = הכל עבר בהצלחה. |

הקריאה ממתינה לסיום הסריקה, שמשכה תלוי בכמות הקבצים אצל המשתמש, ולכן אינה
כפופה ל-timeout הגנרי של 30 שניות. אחרי 15 דקות היא מוחזרת עם `error.timeout`.
רענון הקטלוג עצמו נשלח לפני החזרת התשובה, אך מושלם ברקע; אינדוקס החיפוש מתעדכן
לפי הגדרת „עדכון אינדקס אוטומטי” של המשתמש.

**שגיאות:** `error.unavailable` — רענון אינו זמין בהקשר הנוכחי;
`error.timeout` — הסריקה לא הסתיימה בזמן; `error.internal` — הסריקה נכשלה.

### `library.setProviderBooks`
**הרשאה:** `library.books.provide` · **מ-0.9.98**

מחליף את רשימת הספרים של ספק שהתוסף הצהיר עליו ב-
[`contributes.startup.libraryBooks`](#ספרים-בחיפוש-הספרייה-librarybooks).
הספרים מופיעים באיתור הספרים של מסך הספרייה, ולחיצה על ספר כזה מבצעת את
`openAction` של הספק, או — בלעדיה — נמסרת לתוסף באירוע
[`library.providerBook.openRequested`](#event-libraryproviderbookopenrequested).

```javascript
const { data } = await Otzaria.call('library.setProviderBooks', {
  provider: 'mylib',
  books: [
    { id: 17, title: 'שו"ת אבני נזר', author: 'רבי אברהם בורנשטיין', categoryPath: '/שו"ת/אחרונים' },
    { id: 18, title: 'חידושי הרשב"א' },
  ],
});
// { count: 2 }
```

| שדה | חובה | תיאור |
|-----|:----:|-------|
| `provider` | ✓ | שם הספק כפי שהוצהר במניפסט. ספק שלא הוצהר מחזיר `error.not_found`. |
| `books` | ✓ | הרשימה המלאה — מחליפה את הקודמת. מערך ריק מסיר את כל ספרי הספק. עד 50,000 ספרים. |
| `books[].id` | ✓ | מספר שלם חיובי, ייחודי בספק. זה המזהה שיחזור באירוע הפתיחה. |
| `books[].title` | ✓ | שם הספר (עד 300 תווים). |
| `books[].author` | | המחבר (עד 200 תווים) — מוצג בכרטיס ומשתתף בחיפוש. |
| `books[].categoryPath` | | נתיב קטגוריות מופרד ב-`/`, בצורה של [`library.getTree`](#librarygettree) (עד 300 תווים). מוצג בכרטיס בתצוגת רשת (`שו"ת, אחרונים`) ומשתתף בחיפוש. |

שורות חדשות, טאבים ותווי כיוון (RLM/LRM וכו') בטקסט מוחלפים ברווח אחד.

- **נשמר אצל אוצריא.** הרשימה נשמרת במסד התוספים ונטענת בעליית התוכנה, כך
  שהספרים מופיעים גם כשמנוע התוסף אינו פעיל. אין צורך לשלוח אותה בכל עלייה —
  רק כשהיא משתנה; שליחה חוזרת של אותה רשימה אינה כותבת דבר. היא נמחקת בהסרת
  התוסף ובאיפוס נתוניו.
- **הכול או כלום.** רשומה לא תקינה (מזהה כפול, שם חסר, שדה ארוך מדי) מחזירה
  `error.invalid_params` עם מיקום הרשומה, והרשימה הקודמת נשארת בתוקף.
- **קריאה אחת לכל הרשימה**, לא קריאה לכל ספר: היא נספרת כקריאה אחת במגביל
  הקצב.
- **חלון אחד.** כל חלון של אוצריא מחזיק עותק משלו של הרשימה. החלון שבו התוסף
  רץ מתעדכן מיד; חלון אחר שכבר פתוח ממשיך להציג את הרשימה הקודמת עד הפעלה
  מחדש של אוצריא.

---

## מפרשים וקישורים

חמש הקריאות הבאות חושפות את מפת הקישורים של הספרייה: אילו מפרשים קיימים על
ספר, אילו קישורים יוצאים מטווח שורות נתון, ומה התוכן שבצד השני של הקישור.

**כל מספרי השורות ב-API הזה 0-based** — כמו ה-`index` של `library.getBookToc`
ושל `reader.getCurrentRef`. אין צורך בהיסט כלשהו בין הקריאות. היוצא היחיד הוא
ה**פלט** של `getRawLinks`, שנושא את מוסכמת ה-1-based של פורמט `links.json`;
הפרמטרים שלו נשארים 0-based ככל השאר.

> ⚠️ **גרשיים עבריים.** שמות הספרים במסד שמורים בגרשיים עבריים (`״` U+05F4,
> `׳` U+05F3) ולא במרכאות ASCII (`"`, `'`). השוואה מול ליטרל כמו `'רש"י על
> בראשית'` תיכשל בשקט. תמיד השוו/העבירו את המחרוזת שהתקבלה מהקריאה הקודמת.

הקישורים תלויים במהדורת הטקסט של הספר. ספר שקיים כ-PDF בלבד מוחזר כ-
`error.not_found`; לספר שיש לו שתי מהדורות, העבירו את כותרת מהדורת הטקסט.

> 💡 **התחילו מ-`getLinkTargetsSummary`.** הוא מחזיר את כל ספרי היעד של הספר
> בקריאה אחת וזולה, כולל `maxSourceLine` — ומאפשר לבחור אילו יעדים לבקש
> ב-`getLinks`/`getRawLinks` (`targetTitles`/`targetTitlePrefixes`) במקום
> לסרוק את כל הקישורים.

**`getLinks` או `getRawLinks`?** שתיהן בוחרות בדיוק את אותם קישורים ונבדלות
רק בצורת הפלט. `getLinks` היא ברירת המחדל לכל שימוש תכנותי: 0-based כמו שאר
ה-SDK, שמות שדות מפורשים, ומידע שקיים רק במסד (`isCommentary`, עוגני-מילה,
קישורי-טווח, `targetCategoryId`, `targetIsUserBook`, `targetSource` — `'o'` רשמי,
`'u'` אישי או `'d:<slug>'` לספר במסד מצורף). `getRawLinks` מיועדת
לכלי שכבר יודע לקרוא את פורמט `links.json` ומצפה בדיוק למפתחות שלו.

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
- `titlePrefixes` — סינון למפרשים ששמם פותח באחת התחיליות. שימושי לבחירת
  ספרי הערות/הגהות בלבד (למשל `['הערות ', 'הגהות ', 'נוסחאות ']`) — במסד אין
  סיווג "הערות" נפרד; ההבחנה היא לפי שם ספר היעד, והתוסף קובע את הרשימה.

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
- `targetTitlePrefixes` — סינון לספרי יעד ששמם פותח באחת התחיליות. כשהוא
  ניתן יחד עם `targetTitles`, קישור עובר אם כותרת היעד מופיעה ברשימה **או**
  פותחת באחת התחיליות (איחוד).
- `includeAnchors` — כשהוא `true`, קישור בעל עוגן-מילה מקבל שדה `anchor`:
  אופסטים בתווים גלויים של טקסט השורה כפי ש-`getBookContent` מחזיר אותו. בספר
  שהערות השוליים שלו בטבלה נפרדת, גופי ההערות אינם בטקסט הזה; עוגן שכולו בתוך
  גוף הערה אינו מוחזר, וטווח שחוצה הערה מוחזר בלי החלק שבה.
  האופסטים נספרים בטקסט **השמור** — כפי ש-`getBookContent` מחזיר אותו עם
  `rawDivineNames: true`; בטקסט המסונן הם עלולים לזוז.
- `anchor.label` מגיע עם שם הוי"ה לפי בחירת המשתמש (מ-0.9.98.1).
  `rawDivineNames: true` מחזיר אותו כפי שנשמר (⚠️ [האזהרה](#rawdivinenames--טקסט-כפי-שנשמר)).
  ערך שאינו בוליאני נדחה ב-`error.invalid_params` גם בלי `includeAnchors`.
  `targetHeRef` ו-`targetTitle` הם מפתחות ונשארים תמיד כפי שנשמרו.

```javascript
const { data } = await Otzaria.call('library.getLinks', {
  bookId: 'בראשית',
  startLine: 0,
  endLine: 40,
  connectionTypes: ['COMMENTARY'],  // אופציונלי
  targetTitles: ['רש״י על בראשית'], // אופציונלי
  targetTitlePrefixes: ['הערות '],  // אופציונלי — איחוד עם targetTitles
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

### `library.getRawLinks`
**הרשאה:** `library.links.read` · **מגרסה:** 0.9.97

אותם קישורים בדיוק של `getLinks`, בחמשת המפתחות של פורמט `links.json`.
מיועד לכלים שכבר יודעים לקרוא את הפורמט.

> ⚠️ **זו צורת `links.json`, לא ייצוא נאמן שלו — ובוודאי לא גיבוי.**
> הקישורים משוחזרים מהמסד, ולא נקראים מקובץ. שלוש השלכות:
>
> 1. **התשובה כוללת קישורים שלא היו באף `links.json`.** אוצריא מייצרת קישור
>    הפוך (`SOURCE`) לכל מפרש שמצביע אל הספר, וממזגת קישורי-משתמש שיובאו
>    מ-CSV. שניהם מוחזרים כאן ככל קישור אחר.
> 2. **כתיבת התשובה לקובץ `<שם הספר>_links.json` וייבואה חזרה תשכפל את
>    הספרייה בהיפוך.** הייבוא המובנה של אוצריא קורא בדיוק את תבנית השם הזו
>    ומקבל `SOURCE`. אל תשתמשו בפלט הזה כגיבוי.
> 3. **חלק מהערכים משוחזרים ולא מקוריים:** `path_2` הוא כותרת ספר היעד
>    במסלול המסד, אך במסלול הקבצים הוא הנתיב כפי שהופיע בקובץ (עם תיקייה
>    וסיומת); `heRef_2` נופל לכותרת היעד כשאין לשורה כתובת.

> ⚠️ **שתי מוסכמות אינדוקס באותה קריאה.** `startLine`/`endLine` שבבקשה הם
> 0-based כמו בכל ה-SDK, אך `line_index_1`/`line_index_2` שבפלט הם **1-based**
> — זו מוסכמת `links.json`, ותיקונה היה שובר את הפורמט.
>
> המפתח `Conection Type` כתוב כך, בשגיאת כתיב, גם בפורמט המקורי. אל תתקנו.

- `startLine`/`endLine` — אופציונליים, אך **חובה יחד** (0-based, כולל), כמו
  ב-`getCommentators`. בלעדיהם נסרקות 1000 השורות הראשונות. חלון גדול מ-**1000
  שורות** מוחזר כ-`error.invalid_params`. הטווח שנסרק בפועל חוזר בתשובה.
- `targetTitles` / `targetTitlePrefixes` / `connectionTypes` — סינון זהה לזה
  של `getLinks`.
- התשובה נחתכת אחרי **10,000** קישורים ומסומנת `truncated: true`.

הפלט נושא בדיוק את המפתחות שהפורמט מגדיר. `targetCategoryId`, `isCommentary`,
`targetIsUserBook`, עוגני-מילה וקישורי-טווח **אינם** חלק ממנו — מי שצריך אותם
משתמש ב-`getLinks`. שימו לב במיוחד ש-`targetIsUserBook` נשמט: קישור אישי לספר
ששמו זהה לספר רשמי אינו ניתן להבחנה בפלט הזה.

```javascript
const { data } = await Otzaria.call('library.getRawLinks', {
  bookId: 'בראשית',
  startLine: 0,                     // אופציונלי, חובה יחד עם endLine
  endLine: 40,
  targetTitles: ['רש״י על בראשית'], // אופציונלי
  connectionTypes: ['COMMENTARY']   // אופציונלי
});
// {
//   truncated: false,
//   startLine: 0,
//   endLine: 40,                    // הטווח שנסרק בפועל
//   links: [{
//     "heRef_2": "רש״י על בראשית א, א",
//     "line_index_1": 1,            // 1-based!
//     "path_2": "רש״י על בראשית",
//     "line_index_2": 4,            // 1-based!
//     "Conection Type": "COMMENTARY"
//     // "start" / "end" — רק בספרים שהקישורים שלהם נקראים מקובץ
//   }]
// }
```

לייצוא ספר שלם, קחו את `maxSourceLine` מ-`getLinkTargetsSummary` וצעדו
בחלונות. **`endLine` הוא נקודת המשך תקפה רק כש-`truncated` הוא `false`** —
בחלון שנחתך אין שום סימן היכן החיתוך נפל, ולכן חובה לצמצם ולנסות שוב במקום
להתקדם:

```javascript
const { data: summary } = await Otzaria.call('library.getLinkTargetsSummary', {
  bookId: 'בראשית'
});

const all = [];
let line = 0;
let window = 1000;                  // תקרת החלון של הקריאה
while (line <= summary.maxSourceLine) {
  const { data } = await Otzaria.call('library.getRawLinks', {
    bookId: 'בראשית',
    startLine: line,
    endLine: line + window - 1
  });
  if (data.truncated) {
    if (window === 1) throw new Error(`שורה ${line} חורגת מ-10,000 קישורים`);
    window = Math.max(1, window >> 1);
    continue;                       // אותה שורת התחלה, חלון קטן יותר
  }
  all.push(...data.links);
  line = data.endLine + 1;
  window = 1000;
}
```

### `library.getLinkTargetsSummary`
**הרשאה:** `library.links.read` · **מגרסה:** 0.9.97

כל ספרי היעד של הספר לפי סוג חיבור, בלי לטעון את הקישורים עצמם.
`maxSourceLine` הוא השורה הגבוהה ביותר שיש עליה קישור (0-based), או `-1`
כשאין לספר קישורים כלל.

- `targetTitles` / `targetTitlePrefixes` — סינון רשימת `targets` באותה
  סמנטיקת איחוד של `getLinks`. `maxSourceLine` נשאר של הספר כולו, בלי קשר
  לסינון.

```javascript
const { data } = await Otzaria.call('library.getLinkTargetsSummary', {
  bookId: 'בראשית',
  targetTitlePrefixes: ['הערות ', 'הגהות ']  // אופציונלי
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
לטעון מוחזר כ-`{ error: "not_found" }`, ופריט מספר שהמו"ל הגביל — כ-`{ error: "forbidden" }`.

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

`content` מגיע עם שמות הקודש לפי בחירת המשתמש **למפרשים** (מ-0.9.98.1): שם הוי"ה,
ושאר השמות שהמסד מסמן בשורות היעד. בתוסף שמשובץ בכרטיסיית ספר (קורא טקסט) —
לפי הגדרות המפרשים של אותה כרטיסייה, אבל רק ליעד שהוא מפרש או קישור של הספר
שפתוח בה; יעד אחר — לפי הגדרות המפרשים של הספר עצמו. שורות של קישור-טווח מחוברות ב-`<br>`. `rawDivineNames: true`
ברמת הבקשה מחזיר את כל הפריטים כפי שנשמרו (⚠️ [האזהרה](#rawdivinenames--טקסט-כפי-שנשמר)).

---

## network.* - גישה לרשת

> כל גישת רשת מוגבלת לרשימת ההיתר של אוצריא — ראו [⚠️ הרשאת `network.access`](#️-הרשאת-networkaccess--דרישה-מיוחדת-אישור-מאוצריא).
>
> **שתי הרשאות שונות — ההרשאה נקבעת לפי הכתובת שאליה פונים:**
> - יעד **באינטרנט** (`https://api.example.com/...`) ← `network.access` בלבד.
> - יעד **מקומי** (`localhost`, `::1`, `127.0.0.0` עד `127.0.0.255`, למשל `http://127.0.0.1:36900`) ← `network.localhost` בלבד.
> - פנייה לשני סוגי יעדים ← מצהירים על **שתיהן**.
>
> **מאוצריא 0.9.98.1 ההפרדה מלאה:** תוסף שהצהיר רק על `network.access` לא יגיע לשירות מקומי, ותוסף שהצהיר רק על `network.localhost` לא יגיע לאינטרנט — בלי קשר ל-`minAppVersion` של התוסף. לפני כן `network.access` עדיין מכסה יעד מקומי (תאימות); אל תסתמכו על כך. הפירוט המלא, טבלת הבדלים וטעויות נפוצות — ב-[שירותים מקומיים](#שירותים-מקומיים-localhost--הרשאת-networklocalhost).

### `network.fetchStream`
**הרשאה:** `network.access` ליעד אינטרנט, `network.localhost` ליעד מקומי (מאוצריא גרסה 0.9.98.1 ואילך אחת אינה מחליפה את השנייה) · **מגרסה:** 0.9.97

מבצעת בקשת HTTP בצד אוצריא ומחזירה `AsyncIterable` מיד עם קבלת כותרות
התשובה (ללא מעקב אחר redirects). פרמטרים: `url` (חובה), `method`
(ברירת מחדל `GET`; מומר לאותיות גדולות וחייב להיות אותיות בלבד), `headers`
(אובייקט מפתח→מחרוזת, אופציונלי; ערך שאינו מחרוזת מומר ב-`toString`),
`body` (מחרוזת, אופציונלי; מחרוזת ריקה אינה נשלחת) ו-`timeoutMs` (מספר שלם
חיובי). חסם הזמן חל על הבקשה כולה, כולל קריאת הגוף; ברירת המחדל היא
30,000 והמקסימום 120,000 מילישניות.

שגיאות אפשריות: `error.permission_denied` (אין ההרשאה המתאימה ליעד: network.access לאינטרנט או network.localhost למקומי),
`error.forbidden` (URL לא ברשימת ההיתר), `error.invalid_params` (URL
חסר/לא תקין, `method` לא חוקי, `body` שאינו מחרוזת, `timeoutMs` שאינו
שלם חיובי או מעל התקרה), `error.timeout` (חסם הזמן פקע). הפרמטרים נבדקים
לפני שליחת הבקשה.

**חשוב — מתי להשתמש בזה במקום `fetch()` רגיל:** קריאת `fetch()` ישירה מתוך
ה-WebView של התוסף כפופה ל-CORS (ה-origin הוא `null` כי הדף נטען מ-`file://`).
שרת שלא מחזיר `Access-Control-Allow-Origin` יחסום את הבקשה. `network.fetchStream`
רץ בצד אוצריא (Flutter) ואינו כפוף ל-CORS — לכן לקריאות ל-APIs חיצוניים
(במיוחד `POST`) יש להשתמש בו ולא ב-`fetch()` ישיר.

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

### `network.download`
**הרשאה:** `network.access` ליעד אינטרנט, `network.localhost` ליעד מקומי (מאוצריא גרסה 0.9.98.1 ואילך אחת אינה מחליפה את השנייה)

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

שגיאות אפשריות: `error.permission_denied` (אין ההרשאה המתאימה ליעד: network.access לאינטרנט או network.localhost למקומי),
`error.forbidden` (URL לא ברשימת ההיתר, או `destPath` מחוץ לתיקייה מאושרת),
`error.invalid_params` (URL חסר/לא תקין), `error.internal` (כשל הורדה).

### `network.fetchFile`
**הרשאה:** `network.access` ליעד אינטרנט, `network.localhost` ליעד מקומי (מאוצריא גרסה 0.9.98.1 ואילך אחת אינה מחליפה את השנייה) · **מגרסה:** 0.9.98.1

מורידה קובץ מ-URL מותר **בלי לשמור אותו בתיקיית המשתמש**: הקובץ נשמר במטמון
זמני פרטי של התוסף, והתוסף מקבל עליו `token` לקריאה בלבד, מאותו סוג ש-
[`fs.pickUserFile`](#fspickuserfile) מחזיר. לכן כל מה שעובד על token כזה עובד
גם כאן — `<iframe>`/PDF.js על ה-`url`, [`fs.resolveFileUrl`](#fsresolvefileurl),
[`fs.readTextFile`](#fsreadtextfile), [`ui.printFile`](#uiprintfile) ו-
[`fs.revokeFile`](#fsrevokefile). התוסף אינו מקבל נתיב דיסק.

> **הרשאות:** `network.fetchFile`, `<iframe>` על ה-`url` ו-`ui.printFile` דורשים
> רק את הרשאת הרשת. `fs.resolveFileUrl`, `fs.readTextFile` ו-`fs.revokeFile`
> דורשים, כמו תמיד, גם את `fs.user_files.read` (הצהרה במניפסט והענקה); תוסף
> שאינו מצהיר עליה אינו יכול לשחרר קובץ בעצמו, והמטמון מתפנה לפי המכסה, אחרי
> יממה או בהסרת התוסף (ראו להלן).

פרמטרים: `url` (חובה; אותה בדיקת הרשאה, allowlist ו-redirects כמו
`network.download` — גם יעד redirect בודק את הרשאת הרשת המתאימה לו, כך שהפניה
מאתר מותר ל-`127.0.0.1` נחסמת כשאין לתוסף `network.localhost`; מאוצריא 0.9.98.1 `network.access` אינה מספיקה), `maxBytes` (תקרת גודל לקובץ; ברירת מחדל 50MB, מקסימום
100MB) ו-`timeoutMs` (חסם זמן להורדה כולה; ברירת מחדל 120,000, מקסימום
600,000). קובץ שחורג מהתקרה — כבר לפי `Content-Length`, ואם הוא חסר תוך כדי
ההורדה — נמחק ומוחזרת `error.too_large`; הורדה שנכשלה באמצע אינה משאירה
קובץ חלקי.

```javascript
const { data } = await Otzaria.call('network.fetchFile', {
  url: 'https://example.org/books/sample.pdf',
  maxBytes: 30 * 1024 * 1024  // אופציונלי
});
// { token, url, name: "sample.pdf", size: 1048576, mime: "application/pdf" }
document.querySelector('iframe').src = data.url;
```

רינדור PDF בתוך `<iframe>` עובד רק ב-Windows/macOS; ב-Android/Linux יש לרנדר
עם PDF.js (שמבצע `fetch` מה-`url`).

הערות:
- **הקובץ נשאר במטמון זמני פרטי עד שמשהו מוחק אותו.** אוצריא אינה מנקה את
  המטמון ביציאה, וה-`token` נשמר בין הפעלות; הקובץ נמחק רק ב-`fs.revokeFile`
  (קראו לו כשסיימתם), בפינוי מהמכסה (עד 256MB או 128 קבצים לכל תוסף, הוותיקים קודם),
  בהסרה, בכיבוי, באיפוס נתונים או בשלילת ההרשאה `fs.user_files.read`
  מהתוסף, או בניקוי של הורדה ראשונה אחרי הפעלה של אוצריא אם הקובץ ותיק מיממה.
  עד אז הוא נשאר בדיסק, וגם `fs.resolveFileUrl` ממשיך לעבוד אחרי הפעלה מחדש.
  **אל תניחו שה-`token` שורד:** אחרי כל אחד מהמחיקות האלה
  `fs.resolveFileUrl` מחזיר `error.not_found` — הורידו שוב.
- עד שלוש הורדות במקביל לתוסף; הורדה נוספת מוחזרת ב-`error.too_many_requests`.
  אותה שגיאה מוחזרת אם המטמון מלא וקבצים נעולים מונעים פינוי; הקובץ החדש נמחק.
- שם הקובץ נגזר מה-URL ומנוקה: עד 60 תווים (הסיומת נשמרת), בלי נקודות ורווחים
  בסוף, ושם התקן שמור של ווינדוס (`CON`, `NUL`…) מקבל קו תחתון בהתחלה.
- **סוג התוכן נקבע לפי סיומת השם, לא לפי תוכן הקובץ.** `mime` הוא מה ששרת
  הקבצים של אוצריא מגיש ל-`<iframe>`, והוא נגזר מהסיומת בלבד. תשובה מסוג
  `application/pdf` שה-URL שלה אינו מסתיים ב-`.pdf` נשמרת עם הסיומת; סוג אחר
  בלי סיומת מוגש כ-`application/octet-stream`, וקובץ שסיומתו אינה מתאימה לתוכנו
  (למשל דף שגיאה של שרת שנשמר כ-`.pdf`) מוגש לפי הסיומת. בדקו את התוכן בעצמכם
  אם הוא חשוב לכם.

שגיאות אפשריות: `error.permission_denied`, `error.forbidden` (URL או redirect
לא ברשימת ההיתר), `error.invalid_params` (`url` חסר/לא תקין, `maxBytes` או
`timeoutMs` שאינם שלמים חיוביים או מעל התקרה), `error.too_large`,
`error.timeout`, `error.too_many_requests`, `error.internal` (כשל הורדה, כולל
סטטוס HTTP שאינו 2xx, או כשל בכתיבת הקובץ).

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
- `textStatus` — מצב הטקסט (ראו `search.query` להלן)
- `continuesToNextLine` — הביטוי נמשך לשורה הבאה (ראו `search.query` להלן)
- `index` — אינדקס השורה/עמוד בספר
- `error` — `"forbidden"` בתוצאה מספר שהמו"ל הגביל; `text` ריק בה

`text` מגיע עם שם הוי"ה לפי בחירת המשתמש לספר של כל תוצאה (מ-0.9.98.1), כמו
בתוצאות החיפוש של אוצריא; שאר השמות נשארים בתקציר ככתבם. `rawDivineNames: true`
מחזיר את התקצירים כפי שנשמרו (⚠️ [האזהרה](#rawdivinenames--טקסט-כפי-שנשמר)).

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
| `anyOrder` (מגרסה 0.9.98.1) | `false` | `true` = אותו מרווח כמו בחיפוש לפי הסדר (`distance`), אבל המילים יכולות להופיע בכל סדר; חל גם על `negativeQuery` ואינו משפיע על שאילתה של מילה אחת. נדחה במצב `'fuzzy'`, עם `proximityScope` שאינו `'wordDistance'`, עם `wordMatchMode` שאינו `'all'` ועם `customSpacing` |
| `grouping` | `'none'` | `'none'` \| `'sameSection'` (איחוד לפי סעיף) \| `'identicalText'` (איחוד טקסט זהה) |
| `options` | `{}` | אפשרויות מילה שחלות על **כל** מילות השאילתה |
| `wordOptions` | `{}` | אפשרויות פר-מילה במפתח `"{מילה}_{אינדקס}"`; גובר על `options` |
| `alternativeWords` | `{}` | מילים חלופיות לפי אינדקס מילה: `{ "0": ["אהבת", "יאהב"] }` |
| `customSpacing` | `{}` | מרווח ידני בין זוג מילים **סמוכות**: `{ "0-1": "3" }` |
| `negativeDistance`, `negativeProximityScope`, `negativeOptions`, `negativeWordOptions`, `negativeAlternativeWords`, `negativeCustomSpacing` | כמו החיוביים | אותם פרמטרים עבור `negativeQuery` |
| `includeBookCounts` | `false` | להחזיר גם ספירת תוצאות לפי ספר |
| `rawDivineNames` (מגרסה 0.9.98.1) | `false` | `true` = `text` של התוצאות עם שם הוי"ה כפי שנשמר. ⚠️ ראו [האזהרה](#rawdivinenames--טקסט-כפי-שנשמר) |

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
    textStatus: 'ok',     // 'ok' | 'stale' | 'unavailable' — ראו להלן
    continuesToNextLine: false, // הביטוי נמשך מסוף השורה לשורה הבאה — ראו להלן
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

**`textStatus`** — האם `text` הוא השורה שבה נמצאה ההתאמה:
- `'ok'` — כן.
- `'stale'` — הספר השתנה מאז עדכון אינדקס החיפוש; `text` הוא השורה הנוכחית
  באותו מיקום, בלי הדגשה, או ריק אם השורה כבר אינה קיימת.
- `'unavailable'` — הטקסט אינו זמין כעת (למשל בזמן עדכון ספרייה); `text` ריק.

בגרסאות קודמות השדה חסר; יש להתייחס להיעדרו כ-`'ok'`.

**`error`** — `"forbidden"` בתוצאה מספר שהמו"ל הגביל את מסירת הטקסט שלו;
`text` ריק בה, ושאר השדות (זהות, `index`) נשמרים.

**שמות הקודש ב-`text`** (מ-0.9.98.1) — שם הוי"ה לפי בחירת המשתמש לספר של כל
תוצאה; שאר השמות נשארים ככתבם, כמו במסך החיפוש של אוצריא. `reference` הוא מפתח
ונשאר כפי שנשמר. ראו [שמות הקודש בטקסט שמגיע לתוסף](#שמות-הקודש-בטקסט-שמגיע-לתוסף).

**`continuesToNextLine`** — `true` כשהביטוי מתחיל בסוף השורה `index` ונמשך
בתחילת השורה הבאה (`index + 1`). `text` מחבר אז את סוף השורה ואת תחילת הבאה
במעבר שורה (`<br>`), והמילים מודגשות בשתיהן. התוצאה נספרת פעם אחת, לשורה `index`.
בגרסאות קודמות השדה חסר; יש להתייחס להיעדרו כ-`false`.

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
> `wordOptions.exact` שלמעלה. `anyOrder: true` נדחה בכל מקום שבו הוא היה
> נבלע (מקורב, טווח פסקה/כותרת, התאמה חלקית, מרווח ידני).

### `search.setFieldText`
**הרשאה:** `search.field_actions` · **מגרסה:** 0.9.98.1

כותב טקסט לשדה חיפוש בתוך סשן שהמשתמש פתח בלחיצה על כפתור התוסף בשדה
(ראו [כפתורים בשדות החיפוש](#כפתורים-בשדות-החיפוש-searchfieldactions)).

```javascript
await Otzaria.call('search.setFieldText', { sessionId, text: 'ברכות דף ב' });
```

- התוסף שולח **תמיד את כל הטקסט שלו** בסשן, לא תוספות. כל קריאה מחליפה את
  הקריאה הקודמת.
- אוצריא שומרת את הטקסט שהיה בשדה מחוץ לבחירה ברגע הלחיצה (`before` ו-`after`),
  ומרכיבה `before + text + after`. כשאין רווח בגבול, נוסף רווח מפריד. הסמן
  ממוקם בסוף הטקסט של התוסף.
- עד 1000 תווים בקריאה. תווי בקרה (כמו שבירת שורה) מוחלפים ברווח. טקסט
  שהשדה המורכב ממנו מכיל `://` נדחה (`error.invalid_params`), כולל טקסט שנשמר
  מחוץ לבחירה: Enter בחלק מהשדות פותח קישורי
  `otzaria://`, ותוסף אינו רשאי להפעיל אותם בדרך זו.
- השדה מגיב כמו להקלדה: חיפוש תוך כדי הקלדה (בספרייה, בתוך ספר, באיתור מקור)
  מתעדכן. החיפוש בטקסט המלא רץ רק ב-`submit`.
- סשן שאינו קיים, שהסתיים, או של תוסף אחר: `error.not_found`.

### `search.setFieldActionState`
**הרשאה:** `search.field_actions` · **מגרסה:** 0.9.98.1

משנה את מראה הכפתור בזמן הסשן.

```javascript
await Otzaria.call('search.setFieldActionState', {
  sessionId,
  state: 'active',          // 'idle' | 'active' | 'busy'
  tooltip: 'מקשיב... לחץ לעצירה',
});
```

- `active` מציג את `activeIcon`, `busy` מציג חיווי התקדמות, `idle` את האייקון הרגיל.
  כל עוד הסשן פתוח הכפתור מודגש.
- `tooltip` (לא חובה, עד 120 תווים בשורה אחת) מחליף את הכותרת בזמן הסשן.

### `search.endFieldSession`
**הרשאה:** `search.field_actions` · **מגרסה:** 0.9.98.1

```javascript
await Otzaria.call('search.endFieldSession', { sessionId, submit: true });
```

מסיים את הסשן. `submit: true` מריץ את החיפוש כאילו המשתמש לחץ Enter. גם כאן
התוסף מקבל `search.fieldAction.ended` עם `reason: 'plugin'`. אם השדה מכיל
`://`, הגשה נדחית ב-`error.invalid_params` גם אם התוסף לא כתב טקסט; אפשר לסיים
את הסשן ללא הגשה. Enter של המשתמש ממשיך לעבוד כרגיל.

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

האירוע נושא גם את מדיניות ההתאמה של הטאב: `proximityScope`
(`wordDistance` / `sameParagraph` / `sameSection`), `wordMatchMode`
(`all` / `anyWord` / `mostWords` / `atLeast`) ו-`wordMatchCount`. מחוץ למצב
`advanced` נשלחת תמיד ברירת המחדל (`wordDistance`, `all`). **`distance` מחייב
רק כש-`proximityScope` הוא `wordDistance` ו-`wordMatchMode` הוא `all`** —
אחרת אוצריא עצמה מתעלמת ממנו, והספק צריך לחפש בחלון רחב במקום במרווח.
`distance` הוא מספר המילים שמותר שיופיעו *בין* מילות השאילתה (0 = צמודות),
ומנוע שמודד מרחק ביחידה אחרת חייב לתרגם אותו. מארח ותיק אינו שולח את השדות.

מגרסה 0.9.98.1 האירוע נושא `anyOrder: true` כשהמשתמש ביטל "שמור על סדר המילים
המקורי" והבחירה חלה (גם במצב `exact`): אותו מרווח כמו בחיפוש לפי הסדר,
אבל המילים יכולות להופיע בכל סדר. כשהשדה חסר — לפי הסדר.

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
מדיניות התאמה, אפשרויות מילה, ומגרסה 0.9.98.1 גם שאילתה שלילית, מילים חלופיות,
מרווחים מותאמים והיקף החיפוש. הפרמטרים והערכים זהים ל-`search.query` (ראו
`search.getOptions` לערכים החוקיים), ומפתחות פר-מילה נבדקים מול פיצול מילות
השאילתה. ההיקף מוצג בתפריט "היקף החיפוש" של הכרטיסייה, והחיפוש רץ בתוכו.
כך תוסף שקיבל `search.requested` יכול להחזיר את אותו חיפוש למסך החיפוש עם
ה-`request` שקיבל: `query` עובר לשדה הראשי, ו-`order`, `limit` ו-`grouping`
אינם נכללים ב-`settings`. יתר ההגדרות, כולל השלילה וההיקף, נשמרות:

```javascript
Otzaria.on('search.requested', async ({ request }) => {
  const { query, order, limit, grouping, ...settings } = request;
  await Otzaria.call('reader.openSearchTab', { query, settings });
});
```

```javascript
await Otzaria.call('reader.openSearchTab', {
  query: 'ברכת המזון',
  selectItems: ['include-hebrewbooks'],
  autoSearch: false,
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

// מגרסה 0.9.98.1: היקף ושלילה — חיפוש בהלכה בלבד, בלי תוצאות עם "גוי"
await Otzaria.call('reader.openSearchTab', {
  query: 'שבת',
  settings: {
    mode: 'advanced',
    negativeQuery: 'גוי',
    categories: ['/הלכה'],
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
| `anyOrder` (מגרסה 0.9.98.1) | `false` | אותו מרווח, אבל המילים בכל סדר; אותם כללים כמו ב-`search.query` |
| `options` | `{}` | אפשרויות מילה שחלות על כל מילות השאילתה (למשל `'קידומות דקדוקיות'`) |
| `wordOptions` | `{}` | אפשרויות פר-מילה במפתח `"{מילה}_{אינדקס}"`; גובר על `options` |
| `negativeQuery`, `negativeOptions`, `negativeWordOptions` (מגרסה 0.9.98.1) | — | שאילתה שלילית ואפשרויות המילה שלה, כמו ב-`search.query`. רק במצב `'advanced'` |
| `alternativeWords`, `negativeAlternativeWords` (מגרסה 0.9.98.1) | `{}` | מילים חלופיות לפי אינדקס המילה. רק במצב `'advanced'` |
| `customSpacing`, `negativeCustomSpacing` (מגרסה 0.9.98.1) | `{}` | מרווח בין זוג מילים סמוכות (`"0-1"`). רק במצב `'advanced'` |
| `facets`, `categories`, `books`, `authors`, `eras`, `baseBooksOnly` (מגרסה 0.9.98.1) | כל הספרייה | היקף החיפוש, כמו ב-`search.query` |

שגיאות אפשריות: `error.invalid_params` (פרמטר או ערך לא מוכר, פרמטר שאינו
נתמך במצב שנבחר, או מפתח פר-מילה שאינו תואם לשאילתה), `error.not_found`
(ספר ב-`books` שלא נמצא בספרייה).

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

### `reader.printRange`
**הרשאה:** `reader.open` · **מגרסה:** 0.9.98.1

פותח את מסך ההדפסה של אוצריא — אותו מסך שכפתור ההדפסה בקורא פותח — על טווח
שורות בספר טקסט, כשהטווח כבר מסומן. המשתמש בוחר בו גופן, עימוד, ניקוד,
מפרשים ויעד (מדפסת, PDF או Word) כמו בהדפסה רגילה מהקורא, ויכול גם לשנות את
הטווח. התוסף אינו מקבל את הטקסט.

קלט: זהות ספר (`bookUid` מומלץ, או `id` / `bookId` + `type`), `startIndex`
(שורת ההתחלה, 0-based) ו-`endIndex` (אופציונלי, **בלעדי**). אלה אותם
אינדקסים ש-`library.getBookToc` מחזיר, כך שטווח של פרק הוא מה-`index` של
כותרת הפרק עד ה-`index` של הכותרת הבאה. כשהטווח מתחיל ומסתיים בדיוק בגבולות
כותרות, המסך מציג אותו כבחירת כותרות ("מפרק א עד פרק ט"); אחרת — כטווח שורות.
בלי `endIndex` המסך נפתח על הכותרת שסביב `startIndex`, כמו בהדפסה מהקורא.

`commentators` הוא מערך אופציונלי של שמות מפרשים מקושרים (עד 256 שמות), לבחירה
התחלתית במסך. `[]` משאיר את הבחירה ריקה. כשהפרמטר חסר, נבחרים המפרשים הפעילים
בחלונית הקריאה של **אותו `bookUid`**, ואם אינה פתוחה — כל המפרשים המקושרים.
המשתמש יכול להפעיל "כלול מפרשים" ולשנות את הבחירה במסך; מצב הקורא אינו משתנה.
הקריאה ממתינה לסגירת מסך ההדפסה ללא פסק הזמן הכללי של 30 שניות; ביטול מחזיר
`{ printed: false }` גם אחרי המתנה ממושכת.

```javascript
// לחיצה של המשתמש בלבד — כמו ui.print
button.onclick = async () => {
  const toc = (await Otzaria.call('library.getBookToc', { bookId: 'תהילים' })).data;
  const from = toc.find((e) => e.text === 'פרק א').index;
  const to = toc.find((e) => e.text === 'פרק י').index;   // בלעדי: פרקים א–ט
  const res = await Otzaria.call('reader.printRange', {
    bookId: 'תהילים', startIndex: from, endIndex: to
  });
  // res.data = { printed: true } — הודפס/יוצא; { printed: false } — בוטל
};
```

הערות:
- **דורש מחוות משתמש.** כמו `ui.print`, הקריאה תקפה רק מתוך handler של לחיצה,
  ואם כבר פתוח דיאלוג מערכת של המופע מוחזר `error.forbidden`.
- נתמך רק בספרי טקסט; ספר PDF מחזיר `error.unsupported`, ספר שלא נמצא —
  `error.not_found`.
- `endIndex` שאינו גדול מ-`startIndex`, או אינדקס שלילי/לא שלם, מחזירים
  `error.invalid_params`. גם `commentators` שאינו מערך של שמות לא ריקים מחזיר
  `error.invalid_params`; מפרש שאינו מקושר לספר מחזיר `error.not_found`.

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
//       toolId: null,     // מזהה כלי/תוסף, לכרטיסייה שאינה ספר
//       isSelf: false,    // true לכרטיסייה של התוסף הקורא
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

### `reader.closeTab`
**הרשאה:** `reader.open` · **מגרסה:** 0.9.97

סוגר את הכרטיסייה שבמקום `index` **ברשימה ש-`reader.getCurrentState`
מחזיר** (`openTabs`), הכוללת גם כרטיסיות של כלים ותוספים. תוסף יכול לסגור
את עצמו דרך הכרטיסייה המסומנת `isSelf`.

אינדקס חסר או מחוץ לתחום מוחזר כ-`error.invalid_params`. הכרטיסייה נכנסת
לרשימת "נסגרו לאחרונה" ולכן המשתמש יכול לשחזר אותה, בדיוק כמו סגירה ידנית.

```javascript
const { data: state } = await Otzaria.call('reader.getCurrentState');
const i = state.openTabs.findIndex((tab) => tab.bookUid === bookUid);
if (i !== -1) await Otzaria.call('reader.closeTab', { index: i });
// true

// התוסף סוגר את עצמו
const self = state.openTabs.findIndex((tab) => tab.isSelf);
await Otzaria.call('reader.closeTab', { index: self });
```

### `reader.activateTab`
**הרשאה:** `reader.open` · **מגרסה:** 0.9.97

הופך את הכרטיסייה שבמקום `index` (באותה רשימת `openTabs`) לכרטיסייה הפעילה.
אותם כללי אינדקס ואותה שגיאה כמו ב-`reader.closeTab`.

```javascript
await Otzaria.call('reader.activateTab', { index: 0 });
// true
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

בספר שהמו"ל הגביל, `text` כולל לכל היותר את 40 השורות הראשונות של הבחירה,
והעוגן המורחב אינו מוחזר כשהבחירה קוצרה.

**שמות הקודש (מ-0.9.98.1).** `text`, `renderedSelectedText`, `normalizedSelectedText`
ו-`renderedRange` מגיעים לפי בחירת המשתמש העדכנית לכרטיסייה — גם אם שינה אותה
אחרי שהבחירה סומנה. כשהשמות המבוקשים שונים ממה שעל המסך, `renderedRange` (כולל
`exactText` והקשרו) נבנה מחדש מולם, כמו השכבה `rendered` של
`reader.getSectionTextMap`. `sourceSelectedText` ו-`sourceRange` נשארים מול הטקסט
השמור, ולכן `reader.setHighlight` עם `sourceRange` ממשיך לעבוד בכל הגדרה.
`start`/`end` הוותיקים הם אופסטים בטקסט שעל המסך.

- `rawDivineNames: true` — שדות הטקסט ו-`renderedRange` עם השמות כפי שנשמרו
  (⚠️ [האזהרה](#rawdivinenames--טקסט-כפי-שנשמר)).
- בחירה חוצת פסקאות, בחירה שקוצרה בספר מוגבל, או בחירה שהטווח שלה אינו תקף —
  מעוגנת לפי הטקסט, כמו בתפריט ההקשר, ומגיעה באותו אופן.
- רק בחירה שאי אפשר לעגן כלל (אין `sourceRange` ואין `sections`) נמסרת מהטקסט
  שעל המסך: שם הוי"ה מוחלף בה לפי ההגדרה העדכנית, אבל `rawDivineNames` אינו יכול
  לשחזר ממנה את הנוסח השמור.

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

### `reader.getPageShapeLayout`
**הרשאה:** `reader.open` · **מגרסה:** 0.9.97

מחזיר את מפרשי תצוגת "צורת הדף" הפעילה ואת נראותו הנוכחית של כל מפרש.
`null` כשאין טאב טקסט בצורת הדף, או כשהמסך עדיין טוען את ההגדרות. בטור הימני
יכולים להיות כמה מפרשים, ולכן הוא מערך. הנראות שמדווחת כאן כוללת גם שינוי
זמני שביצע תוסף.

```javascript
const { data } = await Otzaria.call('reader.getPageShapeLayout');
// {
//   available: ["ביאור הלכה", "רש״י על בראשית"],
//   left: { commentator: "ביאור הלכה", visible: false },
//   right: [{ commentator: "רש״י על בראשית", visible: true }],
//   bottom: null,
//   bottomRight: null
// }
```

### `reader.setPageShapeCommentatorVisibility`
**הרשאה:** `reader.open` · **מגרסה:** 0.9.97

מציג או מסתיר זמנית מפרש שכבר משובץ בצורת הדף. השינוי אינו משנה את שיבוץ
המפרשים ואינו נשמר בהגדרות המשתמש; קריאה עם `visible: true` מחזירה גם מפרש
שהוסתר קודם. מפרש שאינו משובץ נדחה ב-`error.not_found`.

```javascript
await Otzaria.call('reader.setPageShapeCommentatorVisibility', {
  commentator: 'ביאור הלכה',
  visible: true
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
בחלוניות המפרשים — ו-PDF אינו תומך בהדגשות וב-`reader.getSelection`.

| שדה | משמעות |
|-----|--------|
| `surface` | `'combined'` \| `'pageShape'` \| `'pdf'` \| `null` |
| `highlights` | האם `reader.setHighlight` ייראה במשטח הזה |
| `selection` | האם `reader.getSelection` יכול להחזיר בחירה |
| `contextMenu` | האזורים במשטח הנוכחי שבהם פריטי `reader.addContextMenuItem` מוצגים: `mainText` בספר טקסט, `commentary` (מ-0.9.98.1), ו-`pdf` בספר PDF (מ-0.9.98.1) |

```javascript
const { data } = await Otzaria.call('reader.getHighlightCapabilities');
if (data.highlights) { /* ... */ }
// { surface: 'combined', highlights: true, selection: true,
//   contextMenu: ['mainText', 'commentary'] }
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

**שמות הקודש (מ-0.9.98.1).** `layer: 'source'` מחפש בטקסט השמור, ללא שינוי.
`layer: 'rendered'` מחפש בטקסט כפי שהקורא מציג את הספר ברגע הקריאה — כולל שמות
הקודש לפי בחירת המשתמש — ולכן שאילתה `אלקים` נמצאת בו כשהמשתמש בחר בצורה הזו,
ו-`אלהים` לא. גם ה-hash של השכבה הזו משתנה כשההגדרה משתנה, וה-cursor נפסל.
`rawDivineNames: true` משאיר בשכבה המוצגת את שאר פרופיל התצוגה ומחזיר רק את
השמות כפי שנשמרו (⚠️ [האזהרה](#rawdivinenames--טקסט-כפי-שנשמר)). `text` של
תוצאה בשכבה המוצגת עשוי לכלול U+2060.

### `reader.beginCorrectionSession`

**גרסת מינימום:** `0.9.98.1`. **הרשאה:** `reader.local_edit` לכל פעולות הסשן.
קבלת `tabId` דרך `reader.getCurrentState` דורשת גם `reader.open`.

פותחת שכבת תיקונים זמנית בלשונית טקסט רשמית ממסד הספרייה, עם מפרשים בצד או מתחת.
צורת הדף וקורא תוסף אינם נתמכים. פסקה שטרם תוקנה נשארת בתצוגת הקורא המקורית.
לחיצה כפולה על הפסקה או מיקוד ישיר ב־Tab פותחים שדה עריכה מובנה (`RtlTextField`).
העריכה היא של טקסט פשוט, ללא סגנונות ה־HTML או עיבודי פרופיל התצוגה; רווחים
שנוצרו מתגיות בלוק בקצוות מוסתרים בשדה ונשמרים בנוסח הסשן. עיצוב המקור אינו משתנה.
אוצריא אינה כותבת לספר, לקובץ המקור או למסד הספרייה.
כל הטקסט של סשן התיקונים (`originalSourceText`, `originalText`, `proposedText`)
הוא הנוסח השמור — שמות הקודש אינם מוחלפים בו לפי בחירת המשתמש, כי התיקון חייב
להתאים למקור (ראו [מה נשאר כפי שנשמר](#מה-נשאר-כפי-שנשמר)).

```javascript
const { data: state } = await Otzaria.call('reader.getCurrentState');
const { data: session } = await Otzaria.call('reader.beginCorrectionSession', {
  tabId: state.currentTabId,
});
```

מ־`0.9.98.1`, `getCurrentState` מחזירה `currentTabId` ו־`openTabs[].tabId`:
מזהה יציב למשך חיי לשונית הטקסט, ו־`null` עבור לשוניות אחרות. המזהה אינו נשמר
בין הפעלות. מעבר ללשונית אחרת אינו משנה את יעד הסשן. לכל לשונית בעלים יחיד;
פתיחה חוזרת של אותו תוסף באותה לשונית מחזירה את הסשן הקיים (עם `recovery: null`).
תוסף אחר מקבל `error.correction_busy`. לכל תוסף+`bookUid` יש סשן פעיל אחד בלבד,
בכל הלשוניות ובכל החלונות: פתיחה של אותו ספר בלשונית או בחלון נוסף מחזירה
`error.correction_busy`. כשל בפתיחת הטיוטה העמידה מחזיר `error.storage_failed`.
בזמן שחזור טיוטה (ראו [חוזה שמירה והתאוששות](#חוזה-שמירה-והתאוששות-של-טיוטות-תיקון)),
כשל זמני בקריאת מקור הספר מחזיר `error.storage_failed`, וטיוטה שאושרה או השתנתה
בזמן השחזור מחזירה `error.revision_conflict`; בשני המקרים הטיוטה אינה משתנה ואפשר
לנסות שוב. לשונית שנסגרה לפני שהפתיחה הסתיימה מחזירה `error.not_found`.

התוצאה היא snapshot עם שדה נוסף `recovery` — `null`, או תיאור הטיוטה ששוחזרה
(ראו [חוזה שמירה והתאוששות](#חוזה-שמירה-והתאוששות-של-טיוטות-תיקון)):

```json
{
  "sessionId": "q3J…",
  "tabId": "Zx8…",
  "bookId": "בראשית",
  "bookUid": "id:1",
  "libraryVersion": "1",
  "revision": 1,
  "capabilities": { "plainTextOnly": true, "maxChanges": 500, "…": "…" },
  "changes": [
    {
      "sectionIndex": 0,
      "originalSourceText": "<b>בראשית</b> ברא",
      "originalText": "בראשית ברא",
      "proposedText": "בראשית ברא אלהים"
    }
  ],
  "draft": {
    "draftId": "hR2…",
    "version": 42,
    "persisted": true,
    "pending": false,
    "displaced": false,
    "error": null,
    "conflicts": [
      {
        "sectionIndex": 7,
        "originalSourceText": "נוסח ישן",
        "originalText": "נוסח ישן",
        "proposedText": "נוסח מתוקן",
        "reason": "source_changed"
      }
    ]
  },
  "recovery": {
    "draftId": "hR2…",
    "fromVersion": 37,
    "restoredSectionIndices": [0],
    "conflicts": [
      {
        "sectionIndex": 7,
        "originalSourceText": "נוסח ישן",
        "originalText": "נוסח ישן",
        "proposedText": "נוסח מתוקן",
        "reason": "source_changed"
      }
    ]
  }
}
```

`currentCorrectionSessionId` ו־`openTabs[].correctionSessionId` מפנים רק לסשן קיים
השייך לתוסף הקורא, או מחזירים `null`. אפשר לקרוא `getCorrectionSession` עם המזהה
לאחר פתיחת דף התוסף כדי להציג עריכה שהופעלה ברקע, ללא `beginCorrectionSession` נוסף.
המזהים זמניים ואינם זהות טיוטה בין הפעלות. אירועי הסשן נמסרים למופע הקדמי
אם הוא קיים, כולל חידוש מופע מושהה; אחרת הם נמסרים למופע הרקע.
בלשונית שמחולקת לשתי חלוניות, `openTabs` מציגה רק את החלונית הפעילה; את `tabId`
של החלונית השנייה מקבלים מ־`selection.tabId` בתפריט `reader-book`.

מעבר לצורת הדף אינו מסיים את הסשן. התיקונים מוסתרים בה ומוצגים שוב בחזרה
למפרשים בצד או מתחת. בזמן צורת הדף `restoreCorrectionDraft` ו־`resetCorrection`
מחזירות `error.unsupported_context`, ו־`getCorrectionSession` ו־`endCorrectionSession` זמינות.

כל הפעולות מחזירות `CorrectionSessionSnapshot`: `sessionId`, `tabId`, `bookId`,
`bookUid`, `libraryVersion`, `revision`, `changes`, `capabilities` ו־`draft`
(`{ draftId, version, persisted, pending, displaced, error, conflicts }`, מצב השמירה
העמידה; `version` אינו `null` רק כשאפשר לאשר אותו, ראו חוזה השמירה).
כל שינוי כולל `sectionIndex` אפסי, `originalSourceText`, `originalText` ו־`proposedText`.
`originalSourceText` שומר את המקור הגולמי כולל תגיות וישויות HTML;
`originalText` הוא הטקסט הקנוני לאחר `TextRendererService.stripHtml`.
ההצעה היא טקסט פשוט; תגיות, ישויות לא מפוענחות, מעברי שורה ו־surrogates פגומים נדחים.
אין שינוי גבולות פסקה, והיסטים נמדדים ביחידות UTF-16 בטקסט הקנוני.
פסקת מקור ריקה אינה ניתנת לעריכה בתוך הקורא. בקריאה רציפה יש שדה נפרד לכל
פסקת מקור נתמכת, ואינדקסי המקור נשמרים.
פסקה שטרם תוקנה שומרת את תצוגת המקור ואת הקישורים, ההערות והבחירה שלה. כניסה לעריכה נעשית בלחיצה כפולה או במיקוד ישיר באמצעות Tab; מיקוד בתוך תוכן הפסקה אינו מפעיל את העורך.

היכולות הן `plainTextOnly: true`, `htmlSource: true`, `paragraphBoundaries: false`, `offsetUnit: 'utf16'`,
`maxChanges: 500`, `maxTextLength: 20000` ו־`maxChangesBytes: 1048576`.
מגבלת הבתים מתייחסת לסכום ייצוגי JSON של השינויים ב־UTF-8, ללא מעטפת הסשן.
יכולות התצוגה הן `sourceSelection: false`,
`sourceAnchorsOnCorrectedParagraphs: false`, `continuousReading: true`,
`pageShape: false` ו־`splitView: true`.

בשליחה דרך `feedback.submitBookCorrection` מעבירים `snapshots[].text` לפי `originalText`,
ולא לפי `originalSourceText`. השליחה מאמתת את הטקסט הקנוני מול המקור הרשמי;
שחזור טיוטה מאמת גם את המקור הגולמי. שינוי שחוצה תגיות ונעדר
מיפוי מדויק נשלח כדיווח חופשי עם המקור וההצעה, ללא שינוי HTML בספר המקומי.

פסקאות מתוקנות שומרות את אינדקסי המקור לצורך ניווט. אין עליהן קישורים,
הערות, הדגשות תוסף או הדגשות חיפוש
המבוססים על היסטים במקור. מעקב המקור נשאר ביחס לנוסח הרשמי.
כל עוד הסשן פעיל בלשונית ואינה בצורת הדף, `reader.getSelection` מחזירה
`error.unsupported_context`. תפריט הבחירה המובנה מאפשר העתקה בלבד,
כטקסט פשוט של הנוסח המוצע; אין להשתמש בבחירה כעוגן למקור.

`reader.getSectionTextMap` עם `layer: 'source'` וללא בקשת מפת מקור ממשיכה להחזיר
את המקור הרשמי. `layer: 'rendered'`, `layer: 'both'` ובקשות `includeSourceMap`
מחזירות `error.unsupported_context` כל עוד יש סשן פעיל באחת הלשוניות של אותו ספר.
גם `reader.findTextOccurrences` בשכבת rendered אינה זמינה באותו מצב;
חיפוש וקריאת source נשארים ביחס למקור הרשמי.

### `reader.getCorrectionSession`

**הרשאה:** `reader.local_edit`. מקבלת `{ sessionId }` ומחזירה snapshot מלא ועקבי.
רק התוסף המאומת שפתח את הסשן יכול לקרוא אותו. כל שינוי טקסט שהתקבל בשדה
המובנה מסנכרן את הסשן מיד ומעלה revision. ה־snapshot כולל את הטקסט האחרון
גם כשהשדה עדיין ממוקד או במהלך composition; אין צורך להוציא ממנו את המיקוד.

לפני החזרה היא שולחת `correctionSessionChanged` ממתין, ומחכה עד 3 שניות לשמירת
המצב הנוכחי. היא גם קוראת את הטיוטה העמידה, כך שהתנגשויות שנוספו מחלון אחר (הצלה)
מופיעות בלי עריכה נוספת. כש־`draft.version` אינו `null` הוא בדיוק הגרסה של התוכן
שב־snapshot, ואפשר לאשר אותה. אם השמירה לא הסתיימה בזמן או נכשלה, `persisted` הוא
false (ו־`pending` או `error` מסבירים למה), ו־`version` הוא `null`.

### `reader.restoreCorrectionDraft`

**הרשאה:** `reader.local_edit`. מקבלת
`{ sessionId, bookUid, libraryVersion, expectedRevision, changes }`.
מחליפה את **כל** הטיוטה אטומית, לאחר אימות הגרסה וכל פסקאות המקור. `changes: []`
מנקה את כל התיקונים וגם מאמתת גרסה והרשאה. פסקה שלא נכללה חוזרת למקור;
הצעה זהה למקור אינה נשמרת כשינוי. כשל אימות אינו מחיל אף פסקה.

אוצריא שומרת את התוצאה בטיוטה העמידה כמו כל שינוי אחר; restore שנכשל אינו משנה אותה.
`expectedRevision` חייב להתאים ל־snapshot האחרון; שינוי בפועל מעלה `revision`.
גרסה ישנה מחזירה `error.revision_conflict`; מקור או גרסת ספרייה שהשתנו מחזירים
`error.source_changed`. בעלים שגוי או סשן שהסתיים מחזירים `error.not_found`.
קלט פגום מחזיר `error.invalid_params`, תוכן או הקשר שאינם נתמכים מחזירים
`error.unsupported_context`, וחריגה ממגבלה מחזירה `error.limit_exceeded`.

### `reader.resetCorrection`

**הרשאה:** `reader.local_edit`. מקבלת `{ sessionId, sectionIndex, expectedRevision }`,
מסירה תיקון לפסקה ומחזירה snapshot. פסקה ללא תיקון אינה משנה את `revision`.

### `reader.endCorrectionSession`

**הרשאה:** `reader.local_edit`. מקבלת `{ sessionId, expectedRevision }`, מחזירה את
ה־snapshot האחרון ומסירה את הסשן ושכבת התצוגה. היא ממתינה (עד 3 שניות) לשמירה
האחרונה, כך שה־snapshot המוחזר כולל `draft.version` שאפשר לאשר כשהוא אינו `null`.
סיום **אינו** מוחק את הטיוטה העמידה ואינו שולח דיווח; שליחה נעשית בנפרד באמצעות
`feedback.submitBookCorrection` ובהרשאת `feedback.send_email`, ואחריה (או אחרי שמירה
באחסון התוסף) מאשרים ב־`acknowledgeCorrectionDraft`.

### Event: `reader.correctionSessionChanged`

אירוע ממוקד לבעלים בלבד, ללא הרשאת subscribe נפרדת, מ־`0.9.98.1`.
כולל `{ sessionId, revision, sectionIndices }`; מבקש מהתוסף למשוך snapshot,
ואינו מחליף קריאת מצב מלא. האירוע מוגבל בקצב (לא debounce): לכל היותר אחד לכל
חלון של 300ms לסשן, גם בהקלדה רצופה. `sectionIndices` הוא רשימה ממוינת וללא כפילויות
של כל הפסקאות ששונו מאז האירוע הקודם (עריכה מובנית, restore ו־reset), ו־`revision`
הוא האחרון. `getCorrectionSession` שולחת אירוע ממתין לפני שהיא חוזרת. בסיום הסשן
אירוע ממתין אינו מובטח: `correctionSessionEnded` נושא את ה־snapshot הסופי.

### Event: `reader.correctionSessionEnded`

אירוע ממוקד לבעלים בלבד, ללא הרשאת subscribe נפרדת, מ־`0.9.98.1`.
כולל `{ sessionId, reason, snapshot }`. הסיבות:

| `reason` | מתי |
|---|---|
| `explicit` | התוסף קרא `endCorrectionSession` |
| `user` | המשתמש סיים את העריכה מהממשק של אוצריא |
| `tab_closed` | הלשונית נסגרה |
| `plugin_unavailable` | התוסף הוסר, הושבת או שהרשאת `reader.local_edit` בוטלה |
| `window_closed` | חלון משני שהסשן בו נסגר |
| `app_exit` | אוצריא נסגרת כרגיל |
| `ownership_lost` | ה־lease על הטיוטה אבד (ראו מגבלות עמידות); שינויים שלא נשמרו עברו להתנגשויות `displaced` בטיוטה, ו־`draft.displaced` הוא true |

`snapshot` הוא המצב הסופי, כולל `draft`. אם השמירה האחרונה הסתיימה בתוך 3 שניות,
האירוע נשלח אחריה ואחרי שחרור ה־lease, עם `draft.persisted: true`. אחרת הוא נשלח
אחרי 3 שניות עם `draft.persisted: false`; אוצריא ממשיכה לנסות לשמור ומחזיקה את
ה־lease עד שהמצב נשמר, ועד אז פתיחת אותו ספר מחזירה `error.correction_busy`.
מחיקה שהמשתמש אישר (הסרת התוסף או איפוס נתוניו) מסיימת את הסשנים בלי אירוע זה.
האירוע אינו הבטחת מסירה: תוסף שכבר נסגר או הושבת עשוי שלא
לקבל אותו. במקרה כזה הטיוטה נשארת, ומגלים אותה ב־`listCorrectionDrafts`.

### חוזה שמירה והתאוששות של טיוטות תיקון

אוצריא שומרת את המצב המלא של כל סשן בטיוטה עמידה בבעלותה (במסד המקומי של
התוספים), במפתח `draftId` יציב שנגזר מהתוסף ומ־`bookUid`. אותו תוסף ואותו ספר
מקבלים אותו `draftId` בכל סשן, לשונית, חלון והפעלה. התוסף אינו נדרש לשמור טיוטה
בעצמו כדי לא לאבד הקלדה; עליו לאשר כל גרסה אחרי שטיפל בה.

- **כתיבה.** הכתיבות לכל סשן סדרתיות, ותמיד של המצב האחרון; כתיבה ישנה אינה דורסת
  חדשה. קצב הכתיבה מוגבל לכל היותר לאחת לכל 250ms (הגבלת קצב, לא debounce).
  כשל כתיבה מוצג למשתמש ומנוסה שוב אוטומטית (1, 2, 5, 10, 30 שניות).
- **`draft.persisted`** הוא true רק כאשר ה־commit האחרון שמר בדיוק את `revision`
  הנוכחי. `pending` מציין כתיבה מתוזמנת או בביצוע, ו־`error` את כשל הכתיבה האחרון.
- **`draft.version`** היא הגרסה העמידה שתוכנה הוא בדיוק ה־`changes` וה־`conflicts`
  שב־snapshot, ממונה גלובלי עולה שאינו חוזר לעולם — גם לא אחרי מחיקת טיוטה ויצירתה
  מחדש. היא `null` בכל מצב אחר: לפני ה־commit הראשון, כש־`persisted` false, וכש־
  `displaced` true (הטיוטה המשותפת כוללת תוכן של הבעלים החדש שאינו ב־snapshot הזה).
  לכן אין דרך לאשר גרסה מלאה באמצעות snapshot חלקי. `getCorrectionSession`
  ו־`endCorrectionSession` ממתינות עד 3 שניות לשמירה וקוראות את הגרסה העמידה.
- **סיום אינו מוחק.** סיום סשן מכל סיבה משאיר את הטיוטה. רק
  `acknowledgeCorrectionDraft` עם ה־`version` הנוכחית בדיוק מנקה אותה.
- **אישור.** פירושו "התוסף שמר את המצב הזה" (באחסון שלו או בדיווח שבתור) — **לא**
  שדיווח הגיע לאתר. גרסה ישנה מחזירה `error.revision_conflict` ואינה מוחקת שינוי
  חדש יותר; אישור חוזר של אותה גרסה מחזיר `duplicate: true`. אישור בזמן סשן פעיל
  אינו עוצר את העריכה, ועריכה שאחריו יוצרת גרסה חדשה שוב ממתינה לאישור.
- **שחזור.** `beginCorrectionSession` על ספר שיש לו טיוטה שלא אושרה מחזירה
  `recovery`. כל שינוי נבדק מחדש מול המקור הגולמי הנוכחי לפי `sectionIndex`:
  שינוי ש־`originalSourceText` ו־`originalText` שלו זהים למקור מוחל מחדש — שינוי
  גרסת ספרייה לבדו אינו פוסל אותו. שינוי שלא ניתן לאמת עובר ל־`draft.conflicts`
  עם `reason`: `source_changed` (המקור השתנה), `not_found` (הפסקה אינה קיימת),
  או `invalid` (נתונים פגומים או הצעה שאינה נתמכת). כשל זמני בקריאת המקור אינו
  התנגשות: הפתיחה נכשלת ב־`error.storage_failed`, הטיוטה אינה משתנה, והפתיחה הבאה
  מנסה שוב. גם ack או שינוי של הטיוטה בזמן השחזור מכשילים את הפתיחה
  (`error.revision_conflict`) במקום להחזיר תוכן שאושר.
  התנגשויות נשמרות עד אישור ומוחזרות בכל snapshot; הן אינן מוצגות בספר.
  לאחר שחזור `revision` הוא 1 ונוצרת גרסה חדשה; השחזור עצמו אינו שולח
  `correctionSessionChanged`.
- **גילוי.** `listCorrectionDrafts` ו־`getCorrectionDraft` מאפשרות למצוא טיוטות
  שאירוע הסיום שלהן לא נמסר (קריסה, תוסף סגור), בלי לפתוח לשונית.
- **בעלות.** טיוטות שייכות לתוסף; תוסף אחר מקבל `error.not_found` גם אם ידוע לו
  ה־`draftId`. סשן פעיל אחד לכל תוסף+`bookUid` בכל הלשוניות והחלונות; ניסיון נוסף
  מקבל `error.correction_busy`. סיום סשן, וגם יציאה רגילה מאוצריא (`app_exit`),
  משחררים את ה־lease אחרי השמירה האחרונה, כך שהפעלה מחדש פותחת את הספר מיד.
  רק אחרי קריסה או הריגת התהליך, ה־lease שלו פג בתוך כ־20 שניות, ועד אז הפתיחה
  מחזירה `error.correction_busy`.
- **טיוטה שהתרוקנה.** טיוטה שכל שינוייה הוסרו (reset או חזרה לנוסח המקור) ושלא אושרה
  מעולם נמחקת כשהסשן משתחרר; אישור של גרסה שלה מחזיר `error.not_found`.
- **ניקוי.** הסרת התוסף או איפוס נתוניו, באישור המשתמש, מוחקים את טיוטותיו, בלי
  `correctionSessionEnded` לסשנים הפתוחים שלו.

**מגבלות עמידות:**

- בקריסת תהליך עלולים לאבוד עד כ־250ms של ההקלדה האחרונה, ועוד זמן הכתיבה שבביצוע.
- המסד פועל ב־WAL עם `synchronous=NORMAL`: בהפסקת חשמל או קריסת מערכת ההפעלה
  ה־commit האחרון עלול לאבוד (המסד נשאר תקין).
- אם ה־lease אבד (למשל התהליך הושהה מעבר לתוקף וחלון אחר פתח את הספר), הסשן
  מסתיים ב־`ownership_lost` והמשתמש מקבל הודעה. ההפרש שטרם נשמר (כולל איפוס פסקה)
  נוסף כהתנגשויות `reason: 'displaced'` לטיוטה של הבעלים החדש: ה־`changes` שלו
  ו־ה־lease שלו אינם משתנים, והגרסה עולה. כתיבה שתשובתה אבדה נחשבת לא ודאית: פסקאות
  שניסתה לשנות נכללות בהצלה גם אם חזרו אחר כך לנוסח שנשמר קודם, כך שגם ביטול נשמר.
  עד שההצלה נשמרת, המצב נשאר `persisted: false` ונספר באזהרת הסגירה. אחריה ה־snapshot
  של הסשן שנדחק הוא `persisted: true` עם `version: null`; ה־snapshot הבא של הבעלים
  החדש (`getCorrectionSession`, סיום) כולל את ההתנגשויות ואת הגרסה לאישור.
  אם הטיוטה נמחקה באישור המשתמש אחרי פתיחת הסשן, ההצלה מוותרת.
- **הרשאות.** הסשן וכל ממשקי התיקון והטיוטות תלויים רק ב־`reader.local_edit`; ביטולה
  מסיים את הסשנים (`plugin_unavailable`). `reader.open` עצמאית: היא נדרשת רק לממשקים
  שלה (למשל `getCurrentState` לאיתור `tabId`), וביטולה אינו מסיים סשן פעיל.
- אזהרת הסגירה של אוצריא (סגירת לשונית — גם ב־`reader.closeTab` — העברת לשונית
  לחלון אחר בגרירה או בתפריט, סגירת חלון או התוכנה) מנסה קודם לשמור, וכוללת גם סשנים שהסתיימו
  (סיום עריכה, השבתה, סגירת לשונית) וטרם נשמרו; בסגירת התוכנה גם כשהלשונית כבר
  סגורה. אין אזהרה כשהמצב נשמר או כשהטיוטה נמחקה באישור המשתמש.

#### אחריות התוסף אחרי acknowledge

אישור מוחק את העותק של אוצריא (תוכן והתנגשויות), ומאותו רגע האחסון של התוסף הוא
העותק היחיד. snapshot מאוחר יותר אינו הוראת מחיקה: `conflicts: []` אחרי האישור, או
סשן חדש על אותו ספר עם `recovery: null` ו־`changes: []`, אינם אומרים שהנתונים
הקודמים בוטלו. על התוסף למזג כל snapshot לרשומה שלו ולא להחליף אותה, ולשמור נתון
שאושר עד שנשלח, נפתר או נמחק במפורש בידי המשתמש. התנגשות עשויה לשאת גם
`reason: 'displaced'` — עריכות שלא נשמרו בסשן שאיבד את הבעלות לחלון אחר, ונשמרו
כהתנגשות בטיוטה של הבעלים החדש. מתכון מלא: [COOKBOOK](COOKBOOK.md#תיקונים-מקומיים-שמירה-אישור-והתאוששות).

### `reader.acknowledgeCorrectionDraft`

**גרסת מינימום:** `0.9.98.1`. **הרשאה:** `reader.local_edit`. מקבלת
`{ draftId: string, version: int }`; מפתחות אחרים נדחים ב־`error.invalid_params`.
אינה דורשת סשן או לשונית פתוחים, ופועלת גם אחרי סיום הסשן.

```javascript
const ended = await rpc('reader.endCorrectionSession', {
  sessionId, expectedRevision: snapshot.revision,
});
await saveToPluginStorage(ended);           // או שליחה / הכנסה לתור
if (ended.draft.persisted) {
  await rpc('reader.acknowledgeCorrectionDraft', {
    draftId: ended.draft.draftId,
    version: ended.draft.version,
  });
}
```

```json
{ "draftId": "hR2…", "version": 42, "acknowledged": true, "duplicate": false }
```

| מצב | תוצאה |
|---|---|
| `version` היא הגרסה הנוכחית | התוכן וההתנגשויות נמחקים; `duplicate: false` |
| אותה גרסה כבר אושרה | `duplicate: true`, ללא שינוי |
| הגרסה אינה הנוכחית | `error.revision_conflict` (יש לקרוא את הטיוטה מחדש) |
| אין טיוטה (כולל טיוטה שהתרוקנה ונמחקה), או שהיא של תוסף אחר | `error.not_found` |
| כשל במסד | `error.storage_failed` |

### `reader.listCorrectionDrafts`

**גרסת מינימום:** `0.9.98.1`. **הרשאה:** `reader.local_edit`. מקבלת `{}` ומחזירה
`{ drafts }` — הטיוטות של התוסף הקורא שיש בהן תוכן או התנגשויות שלא אושרו, מהחדשה
לישנה, ללא התוכן עצמו:

```json
{
  "drafts": [
    {
      "draftId": "hR2…",
      "bookId": "בראשית",
      "bookUid": "id:1",
      "bookSource": "library",
      "libraryVersion": "1",
      "version": 42,
      "updatedAt": "2026-10-17T09:12:44.120Z",
      "active": false,
      "changeCount": 1,
      "conflictCount": 1
    }
  ]
}
```

`active` הוא true כשסשן חי (בכל לשונית או חלון) מחזיק בטיוטה.

### `reader.getCorrectionDraft`

**גרסת מינימום:** `0.9.98.1`. **הרשאה:** `reader.local_edit`. מקבלת `{ draftId }`
ומחזירה את אותם שדות מטא־דאטה, ובמקום המונים את `changes` ו־`conflicts` המלאים.
`version` היא הגרסה לאישור. טיוטה שאושרה, שאין בה תוכן או שאינה של התוסף מחזירה
`error.not_found`.

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

**שמות הקודש (מ-0.9.98.1).** `sourceText` הוא הטקסט השמור. `renderedText` הוא
הטקסט כפי שהקורא מציג את הספר ברגע הקריאה, כולל שמות הקודש לפי בחירת המשתמש
(ספר שאינו פתוח — לפי הגדרות הספר, שכבת התנ"ך וההגדרה הכללית). מפת
Source↔Rendered ממפה גם את השמות שהוחלפו, ו-`renderedText` עשוי לכלול U+2060
שנספר באופסטים. `rawDivineNames: true` משאיר את שאר פרופיל התצוגה
ומחזיר בשכבה המוצגת את השמות כפי שנשמרו (⚠️ [האזהרה](#rawdivinenames--טקסט-כפי-שנשמר)).

> **`includeDomRects` שמור לעתיד ואינו נתמך.** הפרמטר מתקבל ומאומת כבוליאני,
> אך `true` נדחה תמיד ב-`error.unsupported_context`. השאירו אותו `false`
> או השמיטו אותו.

---

## workspace.* - שולחנות עבודה

שולחן עבודה הוא אוסף הכרטיסיות הפתוחות. מעבר בין שולחנות מחליף את כל
הכרטיסיות — אלה שהיו פתוחות נשמרות בשולחן שממנו יצאתם, ואלה של שולחן היעד
נפתחות במקומן.

הקריאה והניהול הם שתי הרשאות נפרדות: **שם** שולחן עבודה הוא תוכן אישי
שיכול להסגיר מה המשתמש לומד, ולכן חשיפתו דורשת `workspace.read` בנפרד
מ-`workspace.manage` שרק יוצר ומחליף. מאותו טעם `key-workspaces` ו-
`key-current-workspace-id` חסומים ל-`settings.get`.

מעבר שולחן מפעיל את האירוע [`workspace.changed`](#אירועים-events), גם כשהוא
נעשה דרך ה-API.

> `workspace.*` אינו כולל מחיקת שולחן או שינוי שמו — פעולות הרסניות שנשארות
> בידי המשתמש.

### `workspace.list`
**הרשאה:** `workspace.read` · **מגרסה:** 0.9.97

```javascript
const { data } = await Otzaria.call('workspace.list');
// [{ id: '1756612800000000-0', name: 'שולחן עבודה 1',
//    isActive: true, tabCount: 3 }]
```

`tabCount` מונה את כל הכרטיסיות בשולחן, כולל כלים ותוספים — כמו
`reader.getCurrentState().openTabs`.
בשולחן הפעיל הספירה היא של המצב החי, ולא של העותק השמור בדיסק.

### `workspace.getActive`
**הרשאה:** `workspace.read` · **מגרסה:** 0.9.97

```javascript
const { data } = await Otzaria.call('workspace.getActive');
// { id: '1756612800000000-0', name: 'שולחן עבודה 1' }
// { id: null, name: null } — כשעדיין לא נטען שולחן
```

### `workspace.create`
**הרשאה:** `workspace.manage` · **מגרסה:** 0.9.97

יוצר שולחן עבודה **ריק** בשם `name` (עד 100 תווים; שם ריק →
`error.invalid_params`). `switchTo: true` עובר אליו מיד, ו-`reuseExisting:
true` מחזיר שולחן קיים באותו שם במקום ליצור כפילות — כך שהתוסף יכול לקרוא
לאותה קריאה בכל התחברות בלי לצבור שולחנות.

```javascript
const { data } = await Otzaria.call('workspace.create', {
  name: 'חברותא — יוסי',
  switchTo: true,
  reuseExisting: true
});
// { id: '1756612800000000-4', created: true }   // created: false = שולחן קיים
```

### `workspace.switch`
**הרשאה:** `workspace.manage` · **מגרסה:** 0.9.97

עובר לשולחן `id`. **הכרטיסיות הפתוחות כרגע נשמרות** בשולחן הנוכחי לפני
המעבר, בדיוק כמו מעבר מהממשק.

מחזיר `false` כשאין שולחן עם המזהה הזה — תוסף שמסנכרן בין מחשבים מקבל מזהה
מהצד השני ויכול ליפול בחזרה ל-`workspace.create` לפי השם. `id` חסר או ריק
מחזיר `error.invalid_params`. מעבר לשולחן שהוא כבר הפעיל מחזיר `true` ואינו
עושה דבר.

```javascript
const { data } = await Otzaria.call('workspace.switch', { id: workspaceId });
// true / false
```

> המעבר אינו מנווט את המשתמש למסך העיון. תוסף שרוצה גם להעביר מסך יקרא
> ל-`navigation.goTo` בנוסף, תחת ההרשאה `navigation.write` שלו.

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

**פתיחה בכרטיסייה נוספת (`newTab`)** — מגרסה 0.9.99

כברירת מחדל `plugin.openSelf` ממקד את הכרטיסייה הקיימת של התוסף. עם `newTab: true`
נפתח **מופע נוסף** של התוסף בכרטיסייה חדשה, וה-`param` נמסר למופע החדש בלבד:

```javascript
const { data } = await Otzaria.call('plugin.openSelf', {
  newTab: true,
  param: { projectId: 'abc' }   // אופציונלי; מגיע ל-plugin.page_opened של המופע החדש
});
// true  — הבקשה התקבלה והכרטיסייה החדשה נפתחת
// false — לא נפתחה (הכלי אינו זמין או מושבת, או שכבר פתוחות 10 כרטיסיות של התוסף)
```

- דורש `contributes.toolTab.allowMultipleInstances: true` במניפסט; בלעדיו הקריאה נדחית עם `error.forbidden`.
- `newTab` שאינו בוליאני (למעט `null`, שמתנהג כאילו לא סופק) — `error.invalid_params`.
- מופעים של אותו תוסף חולקים אחסון (`plugin.storage`, `localStorage`, IndexedDB). תוסף שמחזיק מצב בשם קבוע צריך להפריד בין מופעים.
- רק המופע שמוצג כרגע רץ; מופעים בכרטיסיות אחרות מושהים (`plugin.suspended`). בכרטיסייה מפוצלת שני המופעים מוצגים ורצים יחד.
- אוצריא מגבילה ל-10 כרטיסיות פתוחות של אותו תוסף בכל חלון (כולל הראשונה). מעבר לכך הקריאה מחזירה `false` ומוצגת הודעה למשתמש. כל מופע הוא WebView נפרד, ולכן יש לפתוח מופע נוסף רק בתגובה לפעולת משתמש, לא אוטומטית ולא בלולאה.
- `openSelf` רגיל (בלי `newTab`) מכוון תמיד לכרטיסייה **הראשית** של התוסף: ממקד אותה, או פותח אותה אם נסגרה, ו-`plugin.page_opened` נמסר לה בלבד, לא למופעים הנוספים. כך גם לחצנים ופריטי תפריט הקשר שהוגדרו עם `openPlugin: true`.
  כדי שלחצן או פריט תפריט הקשר יפתחו מופע נוסף במקום זאת, מצהירים עליהם `newTab: true` (ראו [פתיחה במופע נוסף מלחצן או מתפריט הקשר](#פתיחה-במופע-נוסף-מלחצן-או-מתפריט-הקשר)).
- כשאין כרטיסייה פתוחה של התוסף בכלל, `newTab: true` פותח את הכרטיסייה הראשית, כמו פתיחה רגילה.
- `plugin.page_opened` של המופע החדש נמסר פעם אחת. אחרי פינוי, נפילה, טעינה מחדש או שחזור סשן הוא לא חוזר, ולכן מה שצריך לשרוד שומרים ב-`plugin.setRestoreState`. פירוט בכל הנוגע למופעים מרובים ב-[README](README.md).
- בגרסאות שקדמו ל-0.9.99 הדגל `newTab` מתעלמים ממנו: הקריאה ממקדת את הכרטיסייה הקיימת ומחזירה `true`. תוסף שנשען על מופע נוסף צריך להצהיר `minAppVersion` של `0.9.99` לפחות.

#### פתיחה במופע נוסף מלחצן או מתפריט הקשר

מגרסה 0.9.99, לחצן סרגל (`toolbarItems`) ופריט תפריט הקשר (`contextMenuItems`)
שהוגדרו עם `openPlugin: true` יכולים להוסיף גם `newTab: true`:

```json
{ "id": "open-here", "title": "פתח בכרטיסייה חדשה", "openPlugin": true, "newTab": true }
```

- הלחיצה פותחת מופע נוסף של התוסף **ליד הטאב הנוכחי**, והאירוע (`reader.toolbar_item_clicked`, `reader.context_menu_item_clicked` או `onClickEvent`) נמסר למופע החדש בלבד.
- בלי `newTab` הלחיצה ממשיכה לפתוח או למקד את המופע הראשי, כמו קודם.
- `newTab` מחייב `openPlugin: true`, ערך בוליאני, ו-`allowMultipleInstances` במניפסט. בהצהרה במניפסט ההתקנה נדחית אחרת. ברישום דינמי (`reader.addToolbarItem`, `reader.addContextMenuItem` ועדכונים) הקריאה נדחית עם `error.forbidden` או `error.invalid_params`.
- כשאין כרטיסייה פתוחה של התוסף בחלון, הלחיצה פותחת את הראשית כמו פתיחה רגילה.
- התקרה של 10 כרטיסיות חלה גם כאן. בהגעה אליה מוצגת הודעה והאירוע לא נמסר.
- לא נתמך בפקדים קשורים (`binding`), ובקיצורי מקלדת.

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
- חל **רק על מופע רקע שהוער עצל**. קריאה מדף התוסף הנראה היא no-op בטוח
  שמחזיר `false` — דף התוסף ותוספים אחרים לעולם אינם מושפעים.
- אם בינתיים החלה עבודה חדשה (RPC פתוח או אירוע ממתין) — הכיבוי נדחה
  לשעון הרגיל במקום לקטוע אותה.
- אין צורך לקרוא לזה אחרי טיפול באירוע רגיל — שעון חוסר-הפעילות מטפל בזה;
  זה קיצור לעבודות חד-פעמיות שמסיימות מהר.

---

### `plugin.setRestoreState`
**הרשאה:** אין | **מגרסה:** 0.9.98.1

שומר אצל אוצריא מצב קטן של הכרטיסייה (מסך, גלילה, טיוטה בטופס), שיחזור
לתוסף ב-`plugin.boot` כשהדף של אותה כרטיסייה נטען מחדש. אוצריא עשויה לפנות
כרטיסיית תוסף שעזבו מזמן כדי לשחרר זיכרון, ולטעון אותה מחדש כשחוזרים אליה
(ראו §פינוי ושחזור ב-README). גם נפילה של תהליך הדפדפן, עדכון של התוסף
ושחזור הכרטיסיות בהפעלה הבאה טוענים את הדף מחדש.

```javascript
// בכל שינוי משמעותי — לא רק ב-plugin.suspended (ראו הערות)
function saveView() {
  Otzaria.call('plugin.setRestoreState', {
    state: { screen: currentScreen, scrollTop: list.scrollTop }
  });
}
// קראו ל-saveView אחרי כל מעבר מסך, ובסיום גלילה.
list.addEventListener('scrollend', saveView);

Otzaria.on('plugin.boot', (payload) => {
  const saved = payload.restore?.state;
  if (saved) showScreen(saved.screen, saved.scrollTop);
});

await Otzaria.call('plugin.setRestoreState', { state: null }); // מחיקה
// true — נשמר; false — מופע רקע (אין לו שחזור)
```

**הערות:**
- `state` הוא כל ערך JSON, עד 64KB אחרי קידוד. ערך גדול יותר מחזיר
  `error.invalid_params`. `state: null` מוחק את המצב.
- שמירת מצב שאינו `null` מאפשרת פינוי אוטומטי של המופע. רק מופע עם מצב
  שמור מפונה; מחיקת המצב או הסרתו ממטמון ה-LRU מונעת פינוי.
- הערך מחליף את הקודם. **קראו לה בכל שינוי משמעותי של המצב**, ולא רק
  ב-`plugin.suspended`: מעבר בין שולחנות עבודה ושמירת הסשן קוראים את המצב
  השמור לפני שהלשונית מושהית, ולכן מה שנשמר רק ב-`plugin.suspended` לא ייכנס
  אליהם. גם לפני פינוי אין אירוע, כי הדף כבר מושהה ברגע הזה.
- `restore` מגיע כשנטען מחדש הדף של כרטיסייה שכבר הייתה פתוחה (`discarded`,
  `crashed`, `reloaded`) — גם כשלא נשמר מצב, ואז `state` הוא `null`. בכרטיסייה
  ששוחזרה מסשן קודם או משולחן עבודה הוא מגיע רק אם נשמר לה מצב (`session`).
  בפתיחה רגילה של כרטיסייה הוא חסר.
- המצב שייך לכרטיסייה: הוא נמחק כשסוגרים אותה, ונשמר עם הכרטיסיות בסשן
  ובסביבות העבודה. בקורא טקסט של תוסף המצב נשמר רק עד סגירת התוכנה.
- לא לשמור כאן נתונים שאסור לאבד — לזה `storage.set`.

---

### `plugin.listInstalled`
**הרשאה:** `app.info.read` (הרשאת בסיס; אין צורך להצהיר עליה במניפסט) · **מגרסה:** 0.9.97

מחזיר רשימה של כל התוספים המותקנים כרגע באוצריא.

```javascript
const { data } = await Otzaria.call('plugin.listInstalled');
for (const plugin of data) {
  console.log(plugin.name, plugin.version);
}
```

**תוצאה לדוגמה:**

```json
[
  {
    "pluginId": "example-plugin",
    "name": "Example Plugin",
    "version": "1.0.0",
    "enabled": true,
    "showInTools": true,
    "sourceType": "packaged",
    "toolTabIconName": "book_24_regular"
  }
]
```

**שדות התוצאה:**

| שדה | סוג | תיאור |
|-----|-----|--------|
| `pluginId` | `string` | המזהה הייחודי של התוסף. |
| `name` | `string` | שם התוסף. |
| `version` | `string` | גרסת התוסף. |
| `enabled` | `boolean` | האם התוסף מופעל. |
| `showInTools` | `boolean` | האם התוסף מוגדר להצגה באזור הכלים של אוצריא. זהו ערך ההגדרה של התוסף ואינו מציין האם התוסף פתוח כרגע. |
| `sourceType` | `string` | מאיפה התוסף הותקן: `packaged` — מארכיון (חנות או קובץ), `development` — תוסף פיתוח שנטען מתיקייה, `localhost_dev` — תוסף פיתוח שנטען משרת פיתוח מקומי. **מ-0.9.98**; בגרסאות קודמות השדה חסר. |
| `toolTabIconName` | `string` | שם האייקון (מאוצריא או מ-Fluent) שבו התוסף משתמש באזור הכלים. אם שם האייקון שהוגדר בתוסף אינו מוכר באף אחת מהספריות (או שלא הוגדר), מוחזר `puzzle_piece_24_regular`. |

**למה `sourceType` חשוב לתוסף שבודק עדכונים.** תוסף פיתוח נטען מתיקייה שהמפתח
עורך, והגרסה שלו אינה באה מהחנות — אין שום משמעות להציע לו „עדכון”, וקל להתקין
מעליו בטעות את הגרסה הארוזה. בדיקת העדכונים הפנימית של אוצריא מחריגה אותו
(`PluginUpdateCheckService.eligiblePlugins` — `packaged` בלבד), וכך כדאי לעשות גם
בתוסף: להשוות גרסאות רק ל-`sourceType === 'packaged'`, ולכל היותר לסמן תוסף פיתוח
בתצוגה. **מ-0.9.98**

**Fallback של האייקון:**

- אייקון מוכר → מוחזר שם האייקון המקורי.
- אייקון לא מוכר או לא מוגדר → מוחזר `puzzle_piece_24_regular`.

**סדר הרשימה:**

הרשימה ממוינת לפי שלושה קריטריונים, כולם עולים ודטרמיניסטיים:

1. **סדר התצוגה** — תוסף שהמשתמש סידר ידנית (גרירה) מקבל ערך ≥ 1000; תוסף שלא סודר ידנית מקבל את הערך שהוצהר ב-`toolTab.order` במניפסט (ברירת מחדל: 900). ערך נמוך יותר = מוקדם יותר.
2. **תאריך התקנה** (tie-breaker) — כשלשניים אותו ערך סדר, הישן מגיע ראשון.
3. **`pluginId`** (tie-breaker אחרון) — סדר לקסיקוגרפי; מבטיח תוצאה זהה בכל הרצה.

---

## קישורי otzaria:// בדף התוסף

**הרשאה:** אין | **מגרסה:** 0.9.97

קישור לאפליקציה שנכתב בדף התוסף עובד כמו כל קישור — המשתמש לוחץ, והאפליקציה
פותחת את היעד:

```html
<a href="otzaria://open/book/1234?index=57">בבא קמא, דף ב</a>
```

אין צורך בהרשאה. הסיבה: לא פעם הקישור נכתב בידי המשתמש עצמו, בתוכן שהוא שומר
בתוסף — ולא בידי מחבר התוסף. במקום לגדר את זה בהרשאה, הגבול הוא **לחיצה של
המשתמש**.

**רק לחיצה מפעילה קישור.** ניווט שהתוסף יזם בעצמו — `location.href`,
‏`window.open`, ‏`<meta refresh>`, הפניה מהשרת או `iframe` — נחסם בשקט. תוסף שרוצה
לפתוח ספר מיוזמתו משתמש ב-API הרגיל (`reader.openBook`,‏ `navigation.goTo`), שם
ההרשאה נבדקת כרגיל.

שלוש פעולות חסומות גם בלחיצה, כי אין להן שימוש בתוכן שמשתמש כותב:
`otzaria://library/reindex`,‏ `otzaria://info/...` והתקנה מקובץ מקומי
(`otzaria://plugin/install-local`).

### הפיכת כתובות שנכתבו כטקסט לקישורים

כתובת שמופיעה כטקסט רגיל אינה לחיצה — בדיוק כמו בדפדפן. שתי דרכים להפוך אותה
לקישור:

**יזום** — קריאה ל-`Otzaria.linkify(root)` אחרי שהתוכן נכנס ל-DOM. מחזירה את מספר
צמתי הטקסט שהוחלפו:

```javascript
document.getElementById('note').textContent = userText;
Otzaria.linkify(document.getElementById('note'));
```

**אוטומטי** — דגל במניפסט. סורק את הדף בטעינה, וממשיך לעקוב אחרי תוכן שנוסף
מאוחר יותר:

```json
{
  "contributes": {
    "autoLinkify": true
  }
}
```

בשני המצבים הסריקה מדלגת על `<a>`,‏ `<code>`,‏ `<pre>`,‏ `<textarea>`,‏ `<input>`
ו-`<script>`, ועל כל אלמנט עם `contenteditable`. לחסימה מקומית נוספת יש
`data-otzaria-no-linkify`:

```html
<div data-otzaria-no-linkify>otzaria://open/book/1 יישאר טקסט</div>
```

> **שימו לב:** ההחלפה מנתקת את צומת הטקסט המקורי מה-DOM. אם התוסף בנוי על
> ספריית רינדור שמחזיקה הפניות לצמתים (React,‏ Vue,‏ Svelte), עדכון מאוחר של אותו
> טקסט עלול להיעלם. בתוסף כזה עדיפה קריאה יזומה על תוכן שכבר לא משתנה, על פני
> `autoLinkify`.

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

הצגת דיאלוג אישור. הקריאה ממתינה להחלטת המשתמש ואינה נחתכת בתקרת ה־RPC הכללית של 30 שניות.
מופע תוסף יכול להציג דיאלוג אישור אחד בכל רגע. ההגבלה חלה גם על אישורים מובנים שאוצריא מציגה בשם התוסף (פתיחת קישור חיצוני, יצירת קיצור דרך, `feedback.report`); בקשה מקבילה מחזירה `error.conflict`. סגירת החלון או המופע מסירה את דיאלוג האישור שלו ומסיימת אותו עם `confirmed: false`.

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
manifest. ההרשאה לתיקייה תקפה למשך ריצת התוסף. תיקייה שהמשתמש אישר לצמיתות דרך
[`fs.pickUserFolder`](#fspickuserfolder) נחשבת מאושרת גם כאן, בלי לבחור אותה שוב.

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

### `ui.print`
**הרשאה:** (אין — דיאלוג ההדפסה של המערכת הוא שער ההסכמה)

מדפיסה את דף התוסף: המנוע מייצר PDF מהדף, ואוצריא פותחת עליו את דיאלוג
ההדפסה של מערכת ההפעלה (בחירת מדפסת, צבע/שחור-לבן, מאפייני מדפסת).
מחזירה `{ printed: true }` אם המשתמש אישר, ו-`{ printed: false }` אם ביטל.

`window.print()` הרגיל ממשיך לפתוח את חלונית ההדפסה של המנוע, עם תצוגה
מקדימה ובחירת טווח עמודים. `ui.print` היא החלופה למי שרוצה את דיאלוג
המערכת ואת מאפייני המדפסת המלאים.

עיצוב התוכן המודפס נעשה ב-CSS `@media print` בדף התוסף. את **העימוד** —
גודל הדף, הכיוון, השוליים והרקעים — מעבירים כפרמטרים, באותם שדות בדיוק כמו
ב-[`ui.exportPdf`](#uiexportpdf); `@page { size: ... }` אינו מכובד כאן.

זה חשוב במיוחד מפני שברירת המחדל של מנוע ההדפסה היא **US Letter**: תוסף
שמיועד ל-A4 צריך לבקש זאת מפורשות, אחרת הדף מיוצר בגודל אמריקאי ונשלח כך
למדפסת בלי להיפרס מחדש.

```javascript
const res = await Otzaria.call('ui.print', {
  jobName: 'דף לדוגמה',  // אופציונלי; ברירת המחדל היא שם התוסף
  pageSize: 'a4',        // אופציונלי; כמו ב-ui.exportPdf
  orientation: 'portrait',
  marginMm: 12,
  printBackgrounds: true
});
// { printed: true }
```

> הפרמטרים מעמדים את ה-PDF לפני שדיאלוג המערכת נפתח, ולכן הם גוברים על גודל
> הנייר שהמשתמש יבחר שם — הדף לא נפרס מחדש. בקשו גודל רק כשהתוסף באמת תלוי
> בו; אחרת השאירו את השדה ריק ותנו למשתמש לשלוט.

### `ui.printFile`
**הרשאה:** `fs.user_files.read` לקובץ אישי; קובץ של `network.fetchFile` אינו דורש אותה · **מגרסה:** 0.9.98.1

מדפיסה קובץ PDF שהוענק לתוסף — `token` של [`fs.pickUserFile`](#fspickuserfile),
[`fs.openFolderFile`](#fsopenfolderfile) או [`network.fetchFile`](#networkfetchfile).
`ui.print` מדפיסה את דף התוסף עצמו, ו-`iframe.contentWindow.print()` נכשל
ב-`SecurityError` כי ה-PDF בא מ-origin אחר; זו הדרך להדפיס את הקובץ.

אוצריא פותחת עליו את מסך ההדפסה שלה — אותו מסך שכפתור ההדפסה בקורא ה-PDF
פותח: בחירת טווח עמודים, תצוגה מקדימה, כיוון וגודל דף, כמה עמודים בגיליון,
ובסוף דיאלוג ההדפסה של המערכת (במצב סייפר — בחירת המדפסת שלו). המשתמש יכול גם
לייצא את הטווח לקובץ PDF. התוסף אינו מקבל את התוכן, ואינו יכול לקבוע את
הטווח או את העימוד — הם בידי המשתמש.

הקריאה ממתינה לסגירת המסך ללא פסק הזמן הכללי של 30 שניות. מחזירה
`{ printed: true }` אם המשתמש הדפיס או ייצא, ו-`{ printed: false }` אם סגר את
המסך או ביטל. `jobName` אופציונלי (ברירת מחדל: שם הקובץ); הוא שם עבודת
ההדפסה ושם הקובץ המוצע בייצוא, ומוצג בכותרת המסך.

```javascript
printButton.onclick = async () => {
  const res = await Otzaria.call('ui.printFile', { token, jobName: 'הגהה' });
  // res.data = { printed: true } — הודפס/יוצא; { printed: false } — בוטל
};
```

הערות:
- **דורשת מחוות משתמש ודיאלוג אחד בכל רגע**, כמו [`ui.print`](#uiprint) וכמו
  [`reader.printRange`](#readerprintrange) (ראו ההערה בסוף הפרק). המסך הוא
  דיאלוג מודאלי של האפליקציה שחוסם את החלון הראשי, ולכן הוא נפתח רק מלחיצה של
  המשתמש, גם אם "הדפס" הסופי נלחץ בתוכו.
- רק קובץ PDF: סיומת `.pdf` ו-`%PDF-` ב-1024 הבייטים הראשונים (דף שגיאה של שרת
  שנשמר בשם `.pdf` אינו עובר); אחרת `error.unsupported`. `token` לא מוכר,
  של תוסף אחר או של קובץ שנמחק — `error.not_found`. כשאין חלון ראשי שאפשר
  להציג בו את המסך או שאי אפשר לקרוא את הקובץ — `error.unavailable`.
- `jobName` חייב להיות מחרוזת (אחרת `error.invalid_params`); תווי בקרה מוסרים
  ממנו והוא נחתך ל-120 תווים.
- התצוגה המקדימה מציגה עד 60 עמודים; ההדפסה והייצוא כוללים את כל הטווח.

### `ui.exportPdf`
**הרשאה:** (אין — דיאלוג „שמור בשם” של המערכת הוא שער ההסכמה)

מייצאת את דף התוסף לקובץ PDF: אותו PDF שנשלח להדפסה, נשמר במקום שהמשתמש
בוחר בדיאלוג המערכת. מחזירה `{ saved: true, name }` עם שם הקובץ שנשמר, או
`{ saved: false, name: null }` אם המשתמש ביטל.

**הנתיב המלא אינו מוחזר** — התוסף אינו מקבל גישה למה שנשמר; רק שם הקובץ.
מ-`fileName` נלקח שם מוצע לדיאלוג בלבד (מפרידי נתיב מוסרים ממנו).

**פרמטרי עימוד (אופציונליים):** שדה שלא סופק משאיר את ברירת המחדל של מנוע
ההדפסה של ה-WebView (גודל הדף — US Letter). אותם שדות תקפים גם ב-`ui.print`.

| שדה | ערך |
|---|---|
| `pageSize` | שם קבוע — `'a4'` / `'a5'` / `'letter'` / `'legal'` — או מפה `{ widthMm, heightMm }` למידות חופשיות (10–5080 מ"מ לכל מידה) |
| `orientation` | `'portrait'` או `'landscape'` |
| `marginMm` | מספר אחיד או מפה `{ top, right, bottom, left }`; 0–100 מ"מ, צד חסר במפה הוא 0 |
| `printBackgrounds` | האם להדפיס רקעים של CSS (בוליאני) |

ערך פסול מוחזר ב-`error.invalid_params` בלי לפתוח דיאלוג.

```javascript
const res = await Otzaria.call('ui.exportPdf', {
  fileName: 'שני טורים',  // אופציונלי; שם מוצע בדיאלוג
  title: 'ייצוא ל-PDF',   // אופציונלי; כותרת הדיאלוג
  pageSize: { widthMm: 210, heightMm: 297 },  // או 'a4'
  orientation: 'portrait',
  marginMm: 0,
  printBackgrounds: true
});
// { saved: true, name: 'שני טורים.pdf' }
```

### `ui.setUnsavedChanges`
**הרשאה:** (אין — הקריאה רק מרימה דגל; ההשפעה היחידה היא דיאלוג אישור)

מסמנת שבכרטיסיית התוסף יש מידע שלא נשמר. כל עוד הדגל דלוק, סגירת
הכרטיסיה — מה-X, מהתפריט, מ-Ctrl+W, ב"סגור הכל", בהעברה לשולחן עבודה אחר
ובמעבר בין שולחנות — פותחת קודם דיאלוג אזהרה, והמשתמש יכול לבטל.
`reader.closeTab` על כרטיסיה כזו מחזירה `false` אם המשתמש ביטל.

גם סגירת התוכנה עצמה (ה-X של החלון, בדסקטופ) עוברת דרך אותו דיאלוג.

הדגל הוא לכל מופע (כרטיסיה) בנפרד, ומתאפס בסגירה, בטעינה מחדש של הדף
וב-`hasChanges: false`.

> **רשת ביטחון, לא תחליף לשמירה.** במובייל אין אירוע סגירה — המערכת הורגת
> את התהליך בלי לשאול — וגם קריסה או כיבוי המחשב אינם עוברים דרך הדיאלוג.
> תוסף שמחזיק עבודה של המשתמש צריך לשמור טיוטה שוטפת (למשל ב-`storage.set`),
> ולהשתמש בדגל רק כדי למנוע סגירה בטעות. `message` (אופציונלי, עד 200 תווים) מוצג בדיאלוג
מתחת לשם הכרטיסיה — כתבו בו מה ייאבד. קראו עם `false` מיד אחרי שמירה
מוצלחת, אחרת המשתמש יישאל לחינם.

```javascript
editor.addEventListener('input', () => {
  Otzaria.call('ui.setUnsavedChanges', {
    hasChanges: true,
    message: 'הטיוטה שבעריכה תאבד'  // אופציונלי
  });
});

async function save() {
  await persist();
  await Otzaria.call('ui.setUnsavedChanges', { hasChanges: false });
}
```

> **`ui.print`, `ui.printFile` ו-`ui.exportPdf` דורשות פעולת משתמש מפורשת.** אוצריא בודקת ישירות ב-WebView
> אם קיימת הפעלת-משתמש חולפת (`navigator.userActivation`), ולכן אין דרך
> לזייף אותה מתוך התוסף. קריאה מטעינת הדף, מטיימר, או אחרי שרשרת `await`
> ארוכה — מוחזרת ב-`error.forbidden`. קראו להן ישירות מתוך מטפל לחיצה.
> בנוסף, דיאלוג אחד בכל רגע: קריאה נוספת בזמן שדיאלוג פתוח נדחית.

---

## fs.* - פעולות קבצים

> פעולות הקבצים מותרות אך ורק בתוך תיקייה שהמשתמש בחר דרך
> [`ui.pickFolder`](#uipickfolder) בריצה הזו, או בתוך תיקייה עם גישה קבועה
> ([`fs.pickUserFolder`](#fspickuserfolder)). נתיב מחוץ לתיקייה מאושרת מוחזר עם
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

### `fs.deleteFolder` (מ-0.9.98)
**הרשאה:** (אין — מגודר ע"י `ui.pickFolder`)

מחיקת תיקייה על כל תוכנה, בתוך תיקייה מאושרת. שורש התיקייה שנבחרה אינו
ניתן למחיקה. בשונה מ-`fs.deleteFile`, שמוגבל לקבצים בלבד. הפעולה idempotent
— תיקייה שאינה קיימת מסתיימת בהצלחה.

```javascript
await Otzaria.call('fs.deleteFolder', {
  path: folder + '/אוסף-ישן'
});
// true
```

שגיאות אפשריות: `error.forbidden` (נתיב מחוץ לתיקייה מאושרת),
`error.invalid_params` (הנתיב הוא קובץ), `error.internal`.

### `fs.moveEntry` (מ-0.9.98)
**הרשאה:** (אין — מגודר ע"י `ui.pickFolder`)

הזזה/שינוי שם של קובץ או תיקייה בתוך תיקייה מאושרת. גם `from` וגם `to`
חייבים להיות צאצאים של תיקייה מאושרת (לא השורש שנבחר); יעד של תיקייה אינו
יכול להיות בתוכה. תיקיית האב של `to` נוצרת אם אינה קיימת.
מיועד למשל לתוסף שצריך לשקף שינוי מבנה (rename/relocate) במקור נתונים
מרוחק גם בעותק המקומי של המשתמש, בלי להוריד הכל מחדש.

**לא דורס יעד קיים** — אם `to` כבר קיים, נדחית ב-`error.invalid_params`
(מחקו קודם עם `fs.deleteFolder`/`fs.deleteFile` אם דריסה היא הכוונה).

```javascript
await Otzaria.call('fs.moveEntry', {
  from: folder + '/שם-ישן',
  to: folder + '/שם-חדש'
});
// true
```

שגיאות אפשריות: `error.forbidden` (נתיב מחוץ לתיקייה מאושרת),
`error.invalid_params` (פרמטר חסר, היעד בתוך המקור, או שהיעד כבר קיים),
`error.not_found` (המקור אינו קיים), `error.internal`.

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
> שמתקבל ב-`<iframe>`/PDF.js (או `fetch`). שרת הקבצים מתיר הטמעה ב-`<iframe>`
> רק מדף תוסף (`file://` או `otzaria-plugin://`, דרך `frame-ancestors`), מגרסה 0.9.98.1; בגרסאות
> קודמות הוא שלח `X-Frame-Options: SAMEORIGIN` וה-`<iframe>` נחסם — שם יש
> לטעון עם `fetch` ← `Blob` ← `iframe src=blob:`. שימו לב: רינדור PDF ב-`<iframe>`
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

### `fs.pickUserFolder`
**הרשאה:** `fs.user_files.read` · מגרסה 0.9.98

פותח דיאלוג בחירת תיקייה ומעניק לתוסף גישה **קבועה** אליה — בשונה
מ-`ui.pickFolder`, שההרשאה שלו לריצה הנוכחית בלבד ואין בה מנייה. זו התשתית
לרשימת "התיקיות שלי" בדיאלוג פתיחה.

**הסכמת המשתמש.** אחרי בחירת התיקייה אוצריא מציגה דיאלוג משלה, "גישה קבועה
לתיקייה", שמציין את שם התוסף ואת שם התיקייה ומבהיר שהגישה נשארת גם בהפעלות הבאות
בלי לשאול שוב. "ביטול" מחזיר `{ cancelled: true }` ולא נשמר דבר. הדיאלוג הוא
ממשק של אוצריא, ואין ארגומנט שמדלג עליו. בחירה חוזרת של תיקייה שכבר אושרה מחזירה
את אותו `folderToken` בלי הדיאלוג.

**מה הגישה כוללת.** עיון (`fs.listUserFolder`) ופתיחת קבצים (`fs.openFolderFile`;
כתיבה לקובץ דורשת גם `fs.user_files.write`). בנוסף, גישה קבועה כוללת את מה
ש-`ui.pickFolder` מעניק: `network.download` עם `destPath`, `fs.extractZip`,
`fs.deleteFile`, `fs.deleteFolder` ו-`fs.moveEntry` מותרים בתוך התיקייה, גם אחרי
הפעלה מחדש של אוצריא.

**ביטול.** המשתמש רואה את התיקיות ומסיר אותן בהגדרות התוסף, תחת "תיקיות עם גישה
קבועה". התוסף עצמו מסיר דרך [`fs.revokeFolder`](#fsrevokefolder). ביטול חל מיד,
גם על תוסף שרץ כרגע.

```javascript
const { data } = await Otzaria.call('fs.pickUserFolder', {
  title: 'הוספת תיקייה'   // אופציונלי
});
// data = { cancelled: false, folderToken, name, path }  — או { cancelled: true }
```

`name` הוא שם התיקייה ו-`path` הנתיב המלא, לתצוגה בלבד — כל הקריאות הבאות
עובדות לפי `folderToken`. תיקיות המערכת, תיקיות אוצריא, שורש כונן, תיקיית הבית
עצמה ותיקיית רשת נדחות ב-`error.forbidden`, בדיוק כמו ב-`ui.pickFolder`.

### `fs.listUserFolder`
**הרשאה:** `fs.user_files.read` · מגרסה 0.9.98

רמה אחת של תיקייה מאושרת — לא רקורסיבי, כדי שהעץ ייטען בעצלות.

```javascript
const { data } = await Otzaria.call('fs.listUserFolder', {
  folderToken,
  path: 'שיעורים/תשפ"ו',          // אופציונלי: '' (ברירת מחדל) = שורש התיקייה
  extensions: ['docx', '.odt']     // אופציונלי: מסנן קבצים בלבד
});
// data = {
//   folderToken, name, path: 'שיעורים/תשפ"ו',
//   entries: [
//     { name: 'חורף', path: 'שיעורים/תשפ"ו/חורף', type: 'dir', size: 0, modified: '2026-09-01T08:00:00.000Z' },
//     { name: 'בראשית.docx', path: 'שיעורים/תשפ"ו/בראשית.docx', type: 'file', size: 18233, modified: '...' }
//   ],
//   truncated: false
// }
```

`path` תמיד יחסי לשורש התיקייה ומופרד ב-`/`. הסדר: תיקיות ואחריהן קבצים, כל
קבוצה לפי שם. `extensions` אינו תלוי רישיות, עם נקודה או בלעדיה, ותיקיות מוחזרות
תמיד. `modified` הוא ISO-8601 ב-UTC, או `null` כשאינו ידוע.

לא מוחזרים: שמות שמתחילים בנקודה, קובצי נעילה של Office (`~$…`), קובצי ביניים
של שמירה (`*.otztmp`), וקישור סימבולי או junction שמצביע אל מחוץ לתיקייה. מעל
2000 רשומות ברמה אחת מוחזרות 2000 הראשונות עם `truncated: true`.

שגיאות: `error.not_found: unknown folder token`, `error.not_found: folder no
longer exists` (התיקייה אינה בדיסק — למשל כונן שנותק; ההרשאה **נשמרת** ותעבוד
כשיחזור), `error.forbidden` (`..`, נתיב מוחלט או יציאה מהתיקייה דרך קישור),
`error.invalid_params`.

אם הנתיב של תיקייה מאושרת הוחלף בקישור ליעד אחר, הגישה נדחית ב-
`error.forbidden`; יש לבחור את התיקייה מחדש כדי לאשר את היעד החדש.

### `fs.openFolderFile`
**הרשאה:** `fs.user_files.read` · מגרסה 0.9.98

פותח קובץ מתוך תיקייה מאושרת. התשובה זהה לזו של
[`fs.pickUserFile`](#fspickuserfile), וה-`token` הוא token רגיל של קובץ משתמש:
`fs.resolveFileUrl`, `fs.commitUserFileWrite({ targetToken })` ו-`fs.revokeFile`
עובדים עליו. הקובץ אינו מועתק.

```javascript
const { data } = await Otzaria.call('fs.openFolderFile', {
  folderToken,
  path: 'שיעורים/בראשית.docx',
  access: 'readwrite'   // אופציונלי: 'read' (ברירת מחדל) או 'readwrite'
});
// data = { cancelled: false, token, url, name, size, access }
```

`access: 'readwrite'` דורש גם `fs.user_files.write`, כמו ב-`pickUserFile`.
פתיחה חוזרת של אותו קובץ מחזירה את **אותו `token`** (ראו
[`library.openBookFile`](#libraryopenbookfile)); `access` שחוזר הוא מה שה-token
מאפשר בפועל.

שגיאות: `error.not_found` (token תיקייה לא מוכר, תיקייה שנעלמה, או קובץ שאינו
קיים), `error.forbidden` (נתיב מחוץ לתיקייה), `error.permission_denied`,
`error.invalid_params`.

### `fs.revokeFolder`
**הרשאה:** `fs.user_files.read` · מגרסה 0.9.98

מסיר תיקייה מההרשאות הקבועות של התוסף. idempotent — `true` גם כשלא הייתה.
גם הרשאת `ui.pickFolder` של אותה תיקייה בריצה הזו מוסרת, כך שכתיבה ומחיקה בה
דורשות בחירה מחדש. קבצים שכבר נפתחו ממנה שומרים על ה-`token` שלהם; לביטולם יש
`fs.revokeFile`. זו אותה פעולה כמו הסרת התיקייה בהגדרות התוסף.

```javascript
await Otzaria.call('fs.revokeFolder', { folderToken });
// data = true
```

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

### `feedback.submitBookCorrection`

מגיש דיווח שגיאה בספר דרך `DirectErrorReportService` של אוצריא, באותו חוזה v2, תור והיסטוריית דיווחים של התוכנה. אינו משנה את טקסט הספר. דורש הרשאת `feedback.send_email`, המוצהרת במניפסט ומאושרת בידי המשתמש, וכתובת מייל שמורה בהגדרות אוצריא; אינו מקבל כתובת מהתוסף.

גרסת המינימום של ה־API היא `0.9.98.1`. ב-0.9.98 הוא אינו קיים, ומתקבל `error.unknown_method`.

```js
const result = await Otzaria.call('feedback.submitBookCorrection', {
  reportId: 'stable-correction-id',
  bookId: 'שם הספר', bookUid: 'id:42',
  sectionIndex: 7,
  snapshots: [{ index: 7, text: 'לפני המקור אחרי' }],
  original: 'המקור', proposed: 'התיקון',
  sourceStart: 5, sourceEnd: 10,
  allowQueue: false
});
```

- `reportId` הוא מזהה יציב באורך 1–160 תווים מתוך `[A-Za-z0-9_.:-]`. `details` אופציונלי ומוגבל ל־20,000 יחידות UTF-16.
- זהות הספר דורשת `bookId` כמחרוזת; `bookUid` אופציונלי. כאשר נמסר UID, ההתאמה אליו מחמירה וללא חזרה לחיפוש לפי כותרת. ללא UID, הכותרת חייבת לזהות ספר יחיד.
- `sectionIndex/endSectionIndex` הם אינדקסי מקור אפסיים; ברירת המחדל של הסיום היא פסקת ההתחלה. עד 32 פסקאות. `snapshots` מכסה את כולן ברצף, והטקסט חייב להתאים למקור הרשמי העדכני לאחר ניקוי HTML של אוצריא.
- `snapshots`, `original` ו-`proposed` נכתבים מול הנוסח השמור, עם שמות הקודש כפי שנשמרו. טקסט שהתקבל מ-API מסונן (למשל `getBookContent` בלי `rawDivineNames`) לא יתאים למקור — קחו אותו מסשן התיקונים, מ-`sourceSelectedText` או עם `rawDivineNames: true`.
- `original/proposed` נשמרים ללא נרמול, עד 20,000 יחידות UTF-16 כל אחד. הצעה ריקה היא מחיקה. `sourceStart/sourceEnd` הם טווח מקומי בתוך פסקה יחידה; יש להעביר את שניהם או להשמיט את שניהם. הוספה ריקה דורשת טווח מפורש כדי לבנות תיקון מובנה.
- אוצריא בונה מיקום, מקור, גרסת ספרייה, digest ופרטי לקוח מהמידע שלה. תיקון חד־משמעי בפסקה אחת מקבל `text_correction` עם מקור HTML גולמי; טווח שאינו ממופה בבטחה או שינוי בין פסקאות מקבלים `free_text` v2 עם נוסח לפני/אחרי, בלי להמציא טווח DB. טווחי `sourceStart/sourceEnd` שנמסרו נשמרים גם בדיווח `free_text`.
- נתמכים רק ספרי טקסט רשמיים ממסד הספרייה, ללא ספר אישי, מסד מצורף, קובץ חיצוני או מהדורה חלופית. גוף הדיווח מוגבל ל־256 KiB UTF-8.
- `allowQueue` ברירת מחדל true. כאשר false, מצב מנותק או כשל רשת מחזירים `error.report_failed` ללא שמירה בתור. התוסף משאיר את הטיוטה וניסיון חוזר משתמש באותו `reportId`.
- `forceFreeText: true` מגיש v2 חופשי גם כאשר טווח יחיד ניתן למיפוי. יש להשתמש בו בחלקים של תיקון גדול, כדי שלא ליצור הצעות שורה שלמה חלופיות עבור חלקי הוספה אחת. פירוט סדר החלקים נמצא ב־`details`.
- מיפוי HTML משתמש בהיסטים הקנוניים גם במילים חוזרות ובישויות. טקסט מוצע עובר escape; תגיות והקשר שלא השתנה נשמרים. הוספה בגבול משותף לשני צמתים או שינוי שחוצה תגית נדחים ממיפוי מובנה. מגבלת האורך נבדקת גם על המקור המלא לאחר ההחלפה.
- `requireTextCorrection: true` (ברירת מחדל false) אוסר נפילה שקטה ל־`free_text`: אם לא ניתן לבנות `text_correction` מדויק (שינוי שחוצה תגיות HTML, טווח עמום, יותר מפסקה אחת או פסקה ארוכה מדי), מתקבלת `error.text_correction_unavailable` לפני שליחה, ושום דיווח אינו נשלח או נשמר בתור. שילוב עם `forceFreeText: true` נדחה ב־`error.invalid_params`. בלי האפשרות מיפוי שאינו נתמך ממשיך לדיווח חופשי.
- לפי סקירת המתחזק של צד השרת, דיווח `free_text` מנותב באתר לדוא"ל בלבד ואינו נכנס לתור התיקונים של האתר; אוצריא אינה מאמתת זאת. תוסף שהתיקון שלו חייב להגיע לתור התיקונים צריך להעביר `requireTextCorrection: true`.
- תוצאה: `{status: 'sent'|'queued', reportId, nativeReportId, message, duplicate, reportKind, correctionSupported}`. כשל או שינוי במקור מחזירים שגיאה ואינם מאשרים את התיקון. שלושת השדות עונים על שאלות שונות:
  - `status` — מה קרה למשלוח: `sent` נמסר לשרת עכשיו; `queued` נשמר בתור המקומי של אוצריא וישלח בהמשך, והבעלות עליו עוברת לאוצריא.
  - `reportKind` — `'text_correction'` או `'free_text'`: סוג הדיווח שנבנה ונשלח או נשמר בתור. זו קביעה מקומית של אוצריא ואינה אישור שהשרת קיבל אותו.
  - `correctionSupported` — עבור `sent` בלבד: true כשנשלח `text_correction` והשרת לא דיווח שאינו תומך בו; false עבור `free_text` או כשהשרת דחה את סוג התיקון. ב־`queued` הערך null, כי עדיין אין תשובת שרת.
- `error.report_id_conflict` מציין התנגשות בתור המקומי או HTTP 409: יש ליצור `reportId` חדש לפני ניסיון נוסף. כשל זמני משתמש באותו מזהה ובאותו תוכן.

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

מגרסה 0.9.99 כל ערך ארמי נושא `dictionary` - שם המילון שממנו הוא. כברירת מחדל
מוחזרים ערכי "מילון פשיטא" בלבד, כמו עד כה. הפרמטר האופציונלי `dictionaries`
(מערך שמות, עד 20) מחליף את הברירת מחדל: `['מילון פשיטא', 'מילון שיח ישראל',
'מפירוש אונקלוס על התורה', 'מושגים ואישים']`. בכל רמת התאמה (המילה עצמה, ואחריה
צירופים שמכילים אותה) ערכי "פשיטא" באים ראשונים, ומפתח שקיים בכמה מילונים מוחזר בכולם.

> לעזי רש"י אינם נכללים: הם נקראים ממסד הנתונים של הספרייה ומטבלת
> הקישורים, ולא ממילון מצורף.

`meanings` מגיעים עם שם הוי"ה לפי בחירת המשתמש (מ-0.9.98.1); `rawDivineNames: true`
מחזיר אותם כפי שנשמרו. ראו
[שמות הקודש בטקסט שמגיע לתוסף](#שמות-הקודש-בטקסט-שמגיע-לתוסף).

### `tools.biographies`
**הרשאה:** `tools.read` · **מגרסה:** 0.9.98

קריאה במאגר הביוגרפיות המצורף לתוכנה ("תולדות גדולי ישראל") - אותם ערכים
שבמסך "ביוגרפיות", באותו סדר התאמה. החיפוש הוא על השם ועל הכינויים.

| פרמטר | תיאור |
|--------|-------|
| `query` | מחרוזת חיפוש, עד 200 תווים. חסרה או ריקה = כל הערכים |
| `id` | מזהה ערך יחיד: מספר תאימות או מחרוזת, למשל `'Q127398'`. גובר על `query` |
| `formatVersion` | `1` (ברירת מחדל): תאימות למבנה הישן; `2`: המבנה החדש המוצג להלן |
| `limit` | מספר התוצאות המוחזרות, 1-50. ברירת מחדל: 20 |

```javascript
const { data } = await Otzaria.call('tools.biographies', {
  query: 'הרמב"ם', formatVersion: 2
});
// { total: 1,
//   results: [{
//     id: 'Q127398', name: 'רבינו משה בן מימון', honorific: 'זצ"ל',
//     era: 'rishonim', eraLabel: 'ראשונים', generation: null,
//     appelations: ['הרמב"ם', 'הנשר הגדול'], countries: ['ספרד', 'מצרים'],
//     birth: "ד'תתצ\"ח (1138), קורדובה", death: '...', buried: 'טבריה',
//     roles: ['נגיד יהודי מצרים', ...],
//     teachers: [{ name: 'רבי יוסף אבן מיגאש', relation: null, ref: 'Q958361' }],
//     students: [...], family: [{ name: '...', relation: 'אביו', ref: '...' }],
//     works: [{ title: 'משנה תורה', description: '...' }],
//     mentionedIn: null, summary: '...', remember: '...',
//     sources: [{ credit: 'wikipedia', title: 'רמב"ם', url: 'https://...' }],
//     attribution: 'הביוגרפיות נערכו ע"י abaye'
//   }] }
```

`total` הוא מספר ההתאמות לפני ה-`limit`. שדות חסרים במאגר מוחזרים כ-`null`
(או כמערך ריק). `ref` הוא ה-`id` של הערך של אותו אדם, כשיש לו ערך משלו.

**הצגת ערכים מחייבת קרדיט:** תוסף שמציג למשתמש תוכן מהביוגרפיות חייב להציג
גם את `attribution`, ולצד כל ערך את המקורות שלו (`sources`).

**מגרסה 0.9.99:** המאגר הוחלף ב"תולדות גדולי ישראל". ללא `formatVersion: 2`
נשמרת תאימות למבנה התשובה: `id` מספרי ויציב, `communities` הוא מערך ריק
ו-`biographyShort` מכיל את `summary`. שדות הטקסט מכבדים את הגדרת שמות הקודש.
המזהים המספריים החדשים שליליים ובטוחים ל-`Number` של JavaScript. אפשר להעביר
אותם חזרה ב-`id`. מזהים מהמאגר הקודם אינם ניתנים למיפוי למאגר החדש ומחזירים
`{ total: 0, results: [] }`, גם אם נשלח `query`; הם אינם משויכים לאדם אחר.

עם `formatVersion: 2`, `id` הוא המזהה המקורי כמחרוזת, ו-`communities`
ו-`biographyShort` אינם נכללים. בשני המבנים נוספו `honorific`, `era`,
`eraLabel`, `buried`, `roles`, `teachers`, `students`, `family`, `works`,
`mentionedIn`, `remember`, `sources` ו-`attribution`. `ref` נשאר מזהה מחרוזת
בשני המבנים, וניתן להעבירו ב-`id`. `birth` ו-`death` כוללים גם שנה לועזית ומקום.
לתוספים חדשים מומלץ להשתמש ב-`formatVersion: 2`.

`summary`, `remember` ו-`description` של `works` מגיעים עם שם הוי"ה לפי בחירת
המשתמש (מ-0.9.98.1); `rawDivineNames: true` מחזיר אותם כפי שנשמרו. ראו
[שמות הקודש בטקסט שמגיע לתוסף](#שמות-הקודש-בטקסט-שמגיע-לתוסף).

> המאגר ארוז באפליקציה ומתעדכן מהרשת. בהתקנה שבה הנתונים אינם
> זמינים הקריאה נכשלת ב-`error.not_supported`.

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
- `id` שבשימוש התראה של לוח השנה נדחה עם `error.invalid_params: id is in use`
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
- `id` שבשימוש התראה של לוח השנה נדחה עם `error.invalid_params: id is in use`

### `notifications.cancel`
**הרשאה:** `notifications.system`

ביטול התראה ספציפית.

```javascript
const { data } = await Otzaria.call('notifications.cancel', {
  id: 12345
});
// true
```

**הערה:** רק התראה שהתוסף עצמו שלח או תזמן מבוטלת. `id` שאינו של התוסף מחזיר `true` ואינו משנה דבר.

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
//   parasha: "אחרי מות",
//   dafYomi: { masechet: "ברכות", daf: 2 },
//   holidays: [
//     { text: "שביעי של פסח", kind: "yomTov" }
//   ]
// }
```

שדות נוספים בתשובה:

- `monthName` - שם החודש בעברית.
- `isLeapYear` - האם השנה העברית היא שנה מעוברת.
- `isShabbat` - האם התאריך חל בשבת.
- `parasha` - שם פרשת השבוע הקרובה מהתאריך הנתון (ה-Shabbat הבא, או התאריך עצמו אם הוא שבת). מושפע מ-`inIsrael` של הלוח הנבחר עבור פרשיות מחוברות (כגון ויקהל-פקודי) שבהן בארץ קוראים פרשה אחת ובחו"ל שתיים.
- `dafYomi` - הדף היומי (בבלי) לתאריך, בפורמט `{ masechet, daf }` (שם מסכת בעברית ומספר דף). `null` עבור תאריכים שקדמו לתחילת המחזור הראשון (י"א בספטמבר 1923).
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
| `hebrew_books` | `id_book`,‏ `title`,‏ `author`,‏ `printing_place`,‏ `printing_year`,‏ `pub_date`,‏ `pages`,‏ `tags` |
| `otzar_hahochma` | `book_id`,‏ `title`,‏ `authors`,‏ `places`,‏ `from_year`,‏ `to_year`,‏ `subjects`,‏ `pages` |

join יחיד מותר: `otzaria_hebrew_books.hb_id = hebrew_books.id_book`.

מגרסה 0.9.98 נחשפות גם טבלת אוצר החכמה והעמודות הביבליוגרפיות של היברובוקס.
`authors`,‏ `subjects` ו-`tags` הם מערכי JSON שמורים כטקסט. `pub_date` הוא
שנה לועזית, ו-`printing_year` שנה עברית כטקסט.

```javascript
const { data } = await Otzaria.call('database.query', {
  sourceId: 'external_catalog',
  from: { table: 'otzar_hahochma' },
  select: ['book_id', 'title', 'authors', 'places', 'from_year', 'to_year', 'subjects', 'pages']
    .map((column) => ({ expr: column })),
  where: { op: 'in', left: 'book_id', value: [1234, 5678] },
  limit: 100,
  rowFormat: 'object'
});
```

פתיחת ספר של אוצר החכמה לפי `book_id` (בתוכנת אוצר החכמה כשהיא מותקנת והספר
על הכונן, אחרת בדפדפן):

```javascript
await Otzaria.call('reader.openBook', { external: { provider: 'otzar', id: 1234 } });
```

בעמוד מסוים: `index` הוא מספר העמוד (מבוסס-1, כמו בספר PDF). הוא נשלח לתוכנת אוצר החכמה המקומית; באתר נפתח הספר כולו.

```javascript
await Otzaria.call('reader.openBook', {
  external: { provider: 'otzar', id: 1234 },
  index: 57
});
```

האם המשתמש מציג תוצאות אוצר החכמה — שתי הגדרות, שתיהן חייבות להיות דלוקות:

```javascript
const { data } = await Otzaria.call('settings.getMany', {
  keys: ['key-show-external-books', 'key-show-otzar-hachochma']
});
const showsOtzar = data['key-show-external-books'] && data['key-show-otzar-hachochma'];
```

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
| `rawDivineNames` | `boolean` | — | מ-0.9.98. במקור של טקסט ספרייה: `true` — ערכי המחרוזת כפי שנשמרו |

**שמות הקודש (מ-0.9.98.1).** במקור שמכיל טקסט ספרייה — היום `talmud_synopsis` —
שם הוי"ה בכל ערך מחרוזת בתוצאה מגיע לפי ההגדרה הכללית של המשתמש, כמו
ב-[שמות הקודש בטקסט שמגיע לתוסף](#שמות-הקודש-בטקסט-שמגיע-לתוסף). מספרים ומזהים
אינם משתנים. `rawDivineNames: true` (⚠️ [האזהרה](#rawdivinenames--טקסט-כפי-שנשמר))
מחזיר את הערכים כפי שנשמרו; ערך שאינו בוליאני — `database.invalid_spec`. המכסה
`maxResultBytes` נמדדת על הערכים השמורים, וההחלפה אינה מאריכה אותם. אותו כלל חל
על כל שאילתה ב-`database.batchQuery` ועל `database.select` הדקלרטיבי.

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

### `events.setOptions`
**הרשאה:** `events.subscribe:<topic>` של הנושא | **מגרסה:** 0.9.98.1

קובע את אפשרויות המסירה של נושא אירוע **למופע הזה** של התוסף. האפשרות היחידה
כרגע היא `rawDivineNames`: עם `true`, טקסט מספר שהאירוע נושא (היום — `text`
ו-`renderedSelectedText` של `reader.selection_changed`) מגיע עם שמות הקודש כפי
שנשמרו, בלי בחירת המשתמש. ⚠️ קראו את [האזהרה](#rawdivinenames--טקסט-כפי-שנשמר)
לפני שימוש.

```javascript
const { data } = await Otzaria.call('events.setOptions', {
  topic: 'reader.selection_changed',
  rawDivineNames: true
});
// { topic: 'reader.selection_changed', rawDivineNames: true }
```

| פרמטר | משמעות |
|-------|---------|
| `topic` | חובה. נושא שתוסף נרשם אליו בהרשאת `events.subscribe:<topic>` |
| `rawDivineNames` | חובה, בוליאני. `false` מחזיר את ברירת המחדל המסוננת |

- **הרשאה:** הרשאת המנוי של אותו נושא, מאושרת (או הרשאת בסיס כמו
  `events.subscribe:theme.changed`). בלעדיה: `error.forbidden`.
- **שגיאות נוספות:** `error.invalid_params` — פרמטר חסר או שאינו מהסוג הנכון,
  או נושא שאין לו הרשאת מנוי (למשל `contextMenu.itemClicked` או `onClickEvent`
  מותאם — בפריטי תפריט ההקשר האפשרות היא שדה של הפריט, ראו
  [`reader.addContextMenuItem`](#readeraddcontextmenuitem)).
  `error.unavailable` — המופע אינו רץ.
- **היקף:** המופע הקורא בלבד — כל כרטיסייה של התוסף ומופע הרקע שלו נפרדים —
  ולכל המאזינים לנושא במופע הזה. `Otzaria.off` אינו מבטל את האפשרות.
- **משך:** עד שהדף נטען מחדש (כולל טעינה אחרי פינוי או נפילה). דף חדש מתחיל
  בברירת המחדל, ולכן קבעו את האפשרות בכל טעינה — למשל לצד ה-`Otzaria.on`.
- **אפשרויות של ה-boot חלות לפני אירועים שהמתינו לדף.** אפשרות שנקבעה
  ב-`Otzaria.on` לפני ה-boot, או באופן סינכרוני בתוך מאזין `plugin.boot` /
  `plugin.ready`, חלה לפני מסירת אירועים שהמתינו לטעינת הדף — כולל האירוע
  שהעיר את מופע הרקע בהפעלה עצלה ואירועים שנמסרים שוב אחרי טעינה מחדש.
- **אירועים שנמסרו לפני שהאפשרות נקבעה** (למשל כשנקבעה אחרי `await` ב-boot)
  מגיעים מסוננים. זה הכיוון הבטוח: לא יגיע טקסט גולמי שלא התבקש. בקשה של דף
  שנטען מחדש לפני שהסתיימה אינה חלה על הדף החדש (`error.unavailable`).

**קיצור — `Otzaria.on` עם אפשרויות:** הארגומנט השלישי קורא ל-`events.setOptions`
בשבילכם ומחזיר את ה-Promise שלו; כשל נרשם בקונסול ואינו נזרק. רישום שנעשה לפני
`plugin.boot` נשמר בתור, והאפשרות נשלחת ב-boot; במקרה הזה `on` מחזיר `undefined`.
בתוך ה-boot (עד סוף מאזיני `plugin.boot` ו-`plugin.ready`) גם `on` עם אפשרויות וגם
`Otzaria.call('events.setOptions')` רק נרשמים, וה-Promise מתממש מיד ב-`success: true`;
אוצריא מחילה אותם לפי הסדר עם סיום ה-boot, וכשל (למשל `error.forbidden`) אינו מוחזר
לתוסף — האפשרות פשוט אינה חלה.

```javascript
Otzaria.on('reader.selection_changed', (data) => {
  compareWithSource(data.text);            // השוואה פנימית בלבד — לא להצגה
}, { rawDivineNames: true });
```

### אירועים זמינים:

**הרשאה נדרשת:** כל אירוע מצריך הרשאה מתאימה מסוג `events.subscribe:<event_name>`

- `plugin.boot` - נורה פעם אחת בטעינת הדף (ללא הרשאה). כשהדף של כרטיסייה שכבר הייתה פתוחה נטען מחדש (פינוי, נפילה, עדכון), ה-payload כולל `restore: { reason, state }`, גם כש-`state` הוא `null`; בכרטיסייה ששוחזרה מסשן או משולחן עבודה — רק אם נשמר לה מצב. ראה [`plugin.setRestoreState`](#pluginsetrestorestate). ה-payload כולל `app.runMode: 'foreground' | 'background'` — ראה §ריצת רקע — וכן `connectivity` (מצב האינטרנט; ראה [`app.getConnectivity`](#appgetconnectivity)). שדה ה-`app` כולל גם `language` (קוד השפה, זהה ל-[`app.getLocale`](#appgetlocale)) ו-`devMode` (`true` רק כשהתוסף נטען כתוסף פיתוח). שים לב: `buildNumber` אינו נשלח ב-`plugin.boot` — לקבלתו יש לקרוא ל-[`app.getInfo`](#appgetinfo).
- `plugin.ready` - נורה אחרי boot (ללא הרשאה)
- `plugin.suspended` - התוסף הושהה (יציאה מלשונית התוסף, מזעור החלון, או מעבר של האפליקציה לרקע במובייל). ללא הרשאה — ראה §השהיה ברקע ב-README
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
- `search.fieldAction.invoked` / `search.fieldAction.stopRequested` / `search.fieldAction.ended` - סשן של כפתור התוסף בשדה חיפוש. נשלחים רק לתוסף הבעלים, ללא הרשאת subscribe (מגרסה 0.9.98.1; ראו [כפתורים בשדות החיפוש](#כפתורים-בשדות-החיפוש-searchfieldactions))

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
    "app.shortcuts",
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
      "shortcuts": [
        {
          "id": "lookup-shortcut",
          "label": "חפש במילון",
          "key": "ctrl+alt+l",
          "contextMenuItemId": "lookup"
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
| `shortcuts` | זהה ל-`app.registerShortcut` | `app.shortcuts` |
| `publishedData` | `{type, key, payload, scope?}` | `published_data.write` |
| `programs` | תכניות חישוב Host מוולדות | הרשאות הפקודות שבתכנית |
| `searchDialogItems` | שורות checkbox סטטיות בדיאלוג החיפוש | `search.dialog` |
| `searchFieldActions` | כפתורי פעולה בתוך שדות החיפוש | `search.field_actions` |
| `externalEditions` | קונפיגורציית מהדורות מקבילות חיצוניות (טבלת מיפוי במקור DB מוכרז) | `database.read` וגם `library.books.read` |
| `libraryBooks` | ספקי ספרים שמתווספים לאיתור הספרים במסך הספרייה | `library.books.provide` |
| `activationEvents` | שמות אירועים או `app.startup`; אפשר גם `{topic, when}` | הרשאת ה-subscribe של כל נושא |
| `keepAlive` | `boolean` (ברירת מחדל: `false`) | `app.background_keep_alive` וגם `app.run_on_startup` |

### קיצורי מקלדת (shortcuts)

`startup.shortcuts` מאפשר לתוסף להצהיר על קיצורי מקלדת בלי להריץ קוד —
אותה סכימה של `app.registerShortcut` (ראו § app.registerShortcut). כל קיצור
דורש `command` או `contextMenuItemId`, ויכול לצרף קיצור ברירת מחדל (`key`).
הקיצורים מופיעים במסך **הגדרות → קיצורי מקשים** תחת "קיצורי תוספים",
והמשתמש יכול לשנות או לבטל כל אחד מהם.

קיצור עם `command` מפעיל את מנוע התוסף ושולח לו אירוע `app.command`;
קיצור עם `contextMenuItemId` מפעיל את פעולת תפריט ההקשר בדיוק כמו לחיצה
ימנית עליה (דורש טקסט מסומן בטקסט הראשי של הספר — לא במפרש ולא ב-PDF).

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
- מ־0.9.98 קיימת פעולת host לשירות מקומי — [`localService.post`](#localservicepost--פנייה-לשירות-מקומי).
- מ־0.9.97 פעולה יכולה גם לכתוב לאחסון התוסף בלי להעיר את המנוע:
  `storage.set` (‏`args: {key, value}`) ו־`storage.remove` (‏`args: {key}`),
  בהרשאה `plugin.storage.write`. הכתיבה נעולה למרחב האחסון הרגיל של התוסף
  (אותו אחד של `storage.get`/`storage.set` בגשר). `key` — מחרוזת עד 128
  תווים; `value` — ערך JSON קטן (עד 256 צמתים, עומק עד 10, מחרוזות עד
  4096 תווים) ואינו `null`. מפתח שתנאי `when` קורא מתעדכן מיד — כך לחיצה
  יכולה להציג/להסתיר פקדים באופן מיידי (פלטי תכניות, לעומת זאת, מחושבים
  מחדש רק בהחלפת ספר).
- מ־`minAppVersion: 0.9.98.1`, כפתור יכול להצהיר `openPlugin: true` במקום `action`.
  הוא מוצג לפי `binding`,
  כמו כל פקד קשור, ולחיצה עליו פותחת את דף התוסף ומוסרת לו
  `reader.toolbar_item_clicked` עם המיקום הנוכחי (`currentBook`,
  `currentIndex`) — כמו בכפתור רגיל עם `openPlugin`. כך, למשל, כפתור שמוצג רק
  בספרים מסוימים ופותח את התוסף במקום שבו הלומד נמצא. `openPlugin` סותר את
  `action`, ומותר רק ב־`"type": "button"`. עצם הצהרת השדה בפקד קשור, גם כ־`false`,
  דורשת גרסה 0.9.98.1 לפחות; `openPlugin` בפקד רגיל נשאר נתמך מגרסה 0.9.96.
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
| `resultsAction` | לא | מגרסה 0.9.99: כיתוב כפתור (עד 120 תווים) בטאב החיפוש. הכפתור מוצג כשהחיפוש הסתיים, גם בלי תוצאות, ולחיצה פותחת את דף התוסף עם `search.requested` על אותו חיפוש. דורש `openPluginOnSubmit`. |
| `visibleInModes` | לא | מערך לא-ריק מתוך `"exact"`, `"advanced"`, `"fuzzy"`; ברירת המחדל היא כל המצבים. |
| `disabledSearchOptions` | לא | אובייקט `מצב → מזהי אפשרויות מילה` להשבתה כשה-checkbox מסומן. |

בלי `openPluginOnSubmit`, הבחירה נשמרת בקונפיגורציית טאב החיפוש במפתח
`"<pluginId>/<itemId>"`. כשהשדה פעיל, פתיחת הדיאלוג והסימון עדיין סטטיים;
רק לחיצה על "חפש" פותחת את התוסף ומוסרת `{itemId, request}`. `request` הוא
חוזה חוקי של `search.query`, אחרי נרמול המצב והאפשרויות. אם כמה שורות פעילות
מבקשות ניתוב, כל תוסף נפתח ומקבל את הבקשה. מצב `fuzzy` יכול פשוט להיעדר
מ־`visibleInModes`.

`resultsAction` מאפשר למשתמש להחליט אחרי שראה את התוצאות: החיפוש רץ באוצריא
כרגיל (גם בלי לסמן את השורה), ובמצבי `visibleInModes` מוצג כפתור בשלושה
מקומות בטאב: בסרגל העליון, במסך "אין תוצאות" ליד "ערוך חיפוש", ואחרי התוצאה
האחרונה ברשימה (רק אחרי שכל התוצאות נטענו). הכפתור אינו מוצג בזמן ספירה או
בטעינה שטרם החזירה תוצאה, בשגיאה, במסך "לא נבחרו קטגוריות" או במסך מגבלת
האפשרויות; טעינת תוצאות נוספות אינה מסתירה אותו.
לחיצה עליו מוסרת לתוסף אותו `{itemId, request}` כמו שליחה עם השורה מסומנת:
השאילתה והיקף החיפוש של הטאב, והשלילה במצב מתקדם. כך תוסף של מנוע חיצוני
לא צריך להריץ את החיפוש באוצריא בעצמו כדי לדעת אם נמצאו תוצאות.

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

### כפתורים בשדות החיפוש (searchFieldActions)

מגרסה 0.9.98.1, `startup.searchFieldActions` מוסיף כפתור לתוך שדות החיפוש של
אוצריא. התוסף יכול לכתוב טקסט לשדה, אבל רק אחרי שהמשתמש לחץ על הכפתור.
השימוש העיקרי הוא הקלדה בדיבור: מנוע הזיהוי רץ מחוץ לאוצריא, והתוסף מעביר
לשדה את מה שזוהה. אותו מנגנון מתאים גם לתעתיק, למקלדת וירטואלית ועוד.

הכפתור נבנה מהמניפסט בלבד: הצגתו אינה מפעילה את התוסף. לחיצה מעירה את מנוע
הרקע בעצלנות, כמו פקד בשורת העיון (`headless` הוא המבנה המתאים). בלי
`app.run_on_startup`, לחיצה פותחת את דף התוסף ומוסרת אליו את האירוע.

```json
{
  "minAppVersion": "0.9.98.1",
  "headless": true,
  "permissions": [
    "app.startup_contributions",
    "app.run_on_startup",
    "search.field_actions"
  ],
  "contributes": {
    "startup": {
      "searchFieldActions": [
        {
          "id": "dictate",
          "title": "חיפוש בדיבור",
          "icon": "mic_24_regular",
          "activeIcon": "mic_24_filled",
          "fields": ["fullText", "library", "inBook", "findRef"]
        }
      ]
    }
  }
}
```

| שדה | חובה | תיאור |
|---|---:|---|
| `id` | כן | מזהה ייחודי בתוסף (עד 64 תווים); אותיות ASCII, מספרים, `.`, `_`, `-`. |
| `title` | כן | כותרת הכפתור (tooltip), עד 120 תווים. |
| `icon` | לא | שם אייקון, כמו ב-`toolbarItems` (ראו ICONS.md). |
| `activeIcon` | לא | האייקון כשהתוסף מדווח `state: 'active'`. |
| `fields` | לא | באילו שדות להציג. בלי השדה: בכל השדות הנתמכים. ערך לא מוכר מדולג. |

עד 2 כפתורים לתוסף, ועד 3 כפתורים של תוספים בשדה אחד.

השדות הנתמכים:

| ערך | השדה |
|---|---|
| `fullText` | החיפוש בטקסט המלא של הספרייה |
| `library` | איתור ספר או מחבר במסך הספרייה |
| `inBook` | חיפוש בתוך ספר פתוח (טקסט או PDF) |
| `findRef` | איתור מקור |

**סשן.** לחיצה על הכפתור פותחת סשן ושולחת לתוסף (בלי הרשאת subscribe, רק
לתוסף הבעלים):

```javascript
Otzaria.on('search.fieldAction.invoked', async ({ actionId, sessionId, field,
                                                 text, selectionStart, selectionEnd }) => {
  await Otzaria.call('search.setFieldActionState', { sessionId, state: 'active' });
  // ... לאחר זיהוי:
  await Otzaria.call('search.setFieldText', { sessionId, text: recognized });
});
Otzaria.on('search.fieldAction.stopRequested', ({ sessionId }) => { /* עצירה */ });
Otzaria.on('search.fieldAction.ended', ({ sessionId, reason }) => { /* ניקוי */ });
```

- `text`, `selectionStart` ו-`selectionEnd` מתארים את השדה ברגע הלחיצה. הטקסט
  המסומן הוא מה שהתוסף יחליף.
- לחיצה נוספת על הכפתור בזמן סשן פתוח שולחת `search.fieldAction.stopRequested`
  ואינה סוגרת את הסשן; התוסף מחליט מתי לסיים (`search.endFieldSession`).
- `search.fieldAction.ended` נשלח בכל סיום, עם `reason`:
  `"plugin"` (התוסף סיים), `"edited"` (המשתמש שינה את הטקסט בשדה),
  `"closed"` (השדה או הכרטיסייה נסגרו, או שהתוסף הושבת), `"replaced"` (נפתח
  סשן חדש באותו שדה, או סשן אחר של אותו תוסף).
- סשן אחד לכל שדה ולכל תוסף בכל רגע.

**אבטחה.** סשן נוצר רק מלחיצת משתמש על כפתור של התוסף בשדה מסוים. הקריאות
`search.setFieldText` / `setFieldActionState` / `endFieldSession` נכשלות
ב-`error.not_found` עבור סשן שאינו קיים, שהסתיים או ששייך לתוסף אחר. המופע
של התוסף שקרא ראשון בסשן "נועל" אותו, וקריאות ממופע אחר נדחות. עריכה של
המשתמש בשדה סוגרת את הסשן מיד, כך שהתוסף אינו יכול לדרוס את מה שהמשתמש הקליד.

**זיהוי תמיכה.** בגרסה ללא התכונה הכפתור לא יוצג, ו-`search.setFieldText` מחזיר
`error.unknown_method`. מומלץ להצהיר `minAppVersion: "0.9.98.1"`.

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

### ספרים בחיפוש הספרייה (libraryBooks)

מגרסה 0.9.98, `startup.libraryBooks` מצהיר על ספק ספרים משל התוסף. ספרי הספק
מצטרפים לתוצאות איתור הספר או המחבר במסך הספרייה — לצד הספרים של אוצריא ושל
הקטלוגים החיצוניים — ולחיצה על ספר כזה נמסרת לתוסף, שפותח אותו, או מבצעת את
`openAction` של הספק בלי להעיר את המנוע. הרשימה עצמה
נשלחת בזמן ריצה ב-[`library.setProviderBooks`](#librarysetproviderbooks) ונשמרת
אצל אוצריא, כך שהספרים מופיעים מעליית התוכנה בלי להעיר את מנוע התוסף. עד 2
ספקים לתוסף.

```json
{
  "permissions": ["app.startup_contributions", "library.books.provide"],
  "minAppVersion": "0.9.98",
  "contributes": {
    "startup": {
      "libraryBooks": [
        {
          "id": "books",
          "provider": "mylib",
          "title": "הספרייה שלי",
          "icon": "library_24_regular",
          "when": { "storage": { "key": "showInLibrary", "notEquals": false } }
        }
      ]
    }
  }
}
```

| שדה | חובה | תיאור |
|---|---:|---|
| `id` | כן | מזהה ייחודי בתוסף, עד 64 תווים: אותיות ASCII, מספרים, `.`, `_`, `-`. |
| `provider` | כן | שם הספק: מתחיל באות, ואחריה אותיות לטיניות קטנות, ספרות ומקף (2–64 תווים). שייך לתוסף הראשון שרשם אותו. `hebrewbooks`, `otzar` ושמות שנקראים כהם (למשל `myoh`, שהמזהה שלו `myoh:1` מכיל `oh:`) נדחים. |
| `title` | כן | שם הספק לתצוגה (עד 40 תווים) — בכפתור "פתח ב-..." של התצוגה המקדימה. |
| `icon` | לא | אייקון 24px לכרטיסי הספרים (ראו [ICONS.md](ICONS.md)). ברירת מחדל: `contributes.toolTab.iconName` של התוסף, ובלעדיו אייקון ספר. |
| `when` | לא | תנאי [`when`](#when--תרומה-תלוית-הגדרה). כשאינו מתקיים הספרים אינם מוצגים, ומוצגים שוב מיד כשהוא מתקיים — כך הגדרה בתוסף מדליקה ומכבה את ההצגה בלי לשלוח את הרשימה מחדש. |
| `openAction` | לא | פעולת host שמבוצעת בלחיצה על ספר, בלי להעיר את מנוע התוסף. בלעדיה הלחיצה נמסרת באירוע [`library.providerBook.openRequested`](#event-libraryproviderbookopenrequested). |

#### `openAction` — פתיחה בלי מנוע

פעולת host כמו ב-[`action` של תפריט הקשר](#action--פעולת-host-על-פריט-תפריט-הקשר),
עם אותן הפעולות ו-`$storage`, אבל במקום `$selection` ההפניה היא `$book` — הספר
שנבחר:

| נתיב `$book` | ערך |
|---|---|
| `id` | המזהה מ-`books[].id` |
| `title` | שם הספר |
| `author` | המחבר, כשנשלח (אחרת `null`) |
| `provider` | שם הספק |

לדוגמה, פתיחה בתוכנה חיצונית דרך שירות מקומי:

```json
{
  "permissions": [
    "app.startup_contributions",
    "library.books.provide",
    "network.localhost",
    "plugin.storage.read"
  ],
  "network": { "enabled": true, "allowlist": ["127.0.0.1"] },
  "contributes": {
    "startup": {
      "libraryBooks": [
        {
          "id": "books",
          "provider": "mylib",
          "title": "הספרייה שלי",
          "openAction": {
            "type": "localService.post",
            "args": {
              "port": { "$storage": "servicePort" },
              "path": "/book/open",
              "body": { "id": { "$book": "id" } },
              "unavailableMessage": "התוכנה שלי אינה פועלת"
            }
          }
        }
      ]
    }
  }
}
```

הרשאת הפעולה נבדקת בהתקנה ושוב בלחיצה, כמו בתפריט ההקשר.

**רק מחיפוש הספרייה.** ספרי ספק אינם נפתרים דרך `library.resolveBooks` או
`reader.openBook`: כך תוסף אחד אינו יכול להעיר תוסף אחר בשם "פתיחת ספר".

### הפעלה עצלה

**עיקרון:** כל הדלקת מנוע שלא דרך כניסה גלויה לדף התוסף — דורשת **גם** את ההרשאה `app.run_on_startup` (כבויה כברירת מחדל, עם הבאנר הבולט בהתקנה). המשתמש לא אמור להריץ קוד תוסף בלי לדעת.

- **לחיצה על פקד/פריט** שנרשם דקלרטיבית: אם הוגדר `openPlugin: true` — נפתח דף התוסף והאירוע נמסר לו. אחרת: עם `app.run_on_startup` — אוצריא מרימה מופע רקע שקט באותו רגע ואירוע הלחיצה נמסר אחרי ה-boot; **בלי** ההרשאה — הלחיצה נופלת לפתיחת דף התוסף (כמו `openPlugin: true`), כך שהפקד תמיד עובד וההפעלה גלויה.
- **`activationEvents`**: כשאירוע מהרשימה קורה ואין לתוסף מנוע חי — מופע הרקע קם והאירוע נמסר לו. דורש `app.run_on_startup`, וכל נושא רגיל דורש בנוסף את הרשאת `events.subscribe:<topic>` שלו.
- **`app.startup`**: טריגר מיוחד — נורה **פעם אחת לכל תוסף**: מופע הרקע קם כמה שניות **אחרי** שעליית אוצריא הסתיימה (לא מתחרה בעלייה), וגם כשתוסף מותקן לאחר שהאפליקציה כבר עלתה — הוא נורה לו בסיום ההתקנה. מיועד לתוספים שחייבים קוד בעלייה (למשל בדיקת עדכונים). דורש `app.run_on_startup` כמו כל הפעלה שקטה.

### כיבוי אוטומטי אחרי חוסר פעילות

מופע רקע שהוער עצל ולא הראה פעילות (קריאת API, רשת, או אירוע נכנס) במשך כ-3 דקות — **מכובה אוטומטית** ומשחרר את משאבי ה-WebView. זה שקוף לתוסף: הטריגר הבא (לחיצה, אירוע מוכרז) יעיר אותו מחדש, והרישומים הדקלרטיביים ממילא לא תלויים בו. עבודה חד-פעמית שמסיימת מהר יכולה לקצר את ההמתנה לאפס עם `plugin.backgroundDone`. השלכות למפתח:

- אל תסתמכו על `setTimeout`/`setInterval` ארוכים במופע הרקע — לתזמון השתמשו ב-`notifications.scheduleSystem`, ולמעקב מתמשך ב-`activationEvents`.
- שמרו state שצריך לשרוד ב-`storage.set` (או ב-`localStorage`, שנשמר בפרופיל) — משתני JS בזיכרון אובדים בכיבוי.

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

### separatorBefore — קו חוצץ בין תוספים

מ-`0.9.98.1`. כשכמה תוספים מוסיפים פריטים לאותו תפריט הקשר, התוכנה מציירת
כברירת מחדל קו חוצץ בין קבוצת הפריטים של כל תוסף. תוסף שמעדיף שהפריטים שלו
ימשיכו ברצף עם מה שמעליהם מצהיר על הפריט העליון הראשון שלו:

```json
{ "id": "my-item", "title": "הפעולה שלי", "separatorBefore": false }
```

- ערך בוליאני בלבד; ברירת המחדל היא `true`.
- נקרא רק מהפריט העליון הראשון של התוסף בתפריט; בפריט ילד הרישום נדחה
  עם `error.invalid_params`.
- עובד גם ברישום דינמי דרך `reader.addContextMenuItem`, וב-`reader.updateContextMenuItem`.
- פריט `separator` שהתוסף הוסיף בעצמו בתחילת הקבוצה אינו מכפיל את הקו.

### action — פעולת host על פריט תפריט הקשר

מ-`minAppVersion: 0.9.97`. פריט `contextMenuItems` מסוג `item` (גם ילד של
`submenu`) יכול לשאת `action` — פעולה שהתוכנה מבצעת בלחיצה **בלי להעיר את
מנוע התוסף**. סותר את `onClickEvent` ואת `openPlugin` על אותו פריט.
הפעולות הן אותן פעולות של פקדי הסרגל (`reader.openBook`,
`reader.openBookInSidePane`, `storage.set`, `storage.remove`, ומ־0.9.98 גם
`localService.post`), אך במקום `$output`/`$item` ההפניות הן `$selection` —
נתוני הסימון בזמן הלחיצה — ומ־0.9.98 גם `$storage` (לצד `$literal`
ו-`$concat`):

| נתיב `$selection` | ערך |
|---|---|
| `selectedText` | הטקסט המסומן, עם שמות הקודש לפי בחירת המשתמש (מ־0.9.98.1; `rawDivineNames: true` על הפריט — כפי שנשמרו) |
| `currentRef` | הכותרת הנוכחית |
| `currentBook` / `currentBookId` | שם הספר |
| `currentIndex` | אינדקס השורה |
| `id` / `type` / `source` | זהות הספר (לבניית `identity`) |

מ־0.9.98, ערך טקסט מנתוני הלחיצה (`$selection`, `$book`) מותאם לבדיקת
הפעולה: מעברי שורה ותווי בקרה אחרים הופכים לרווח (סימון של כמה שורות מגיע
כשורה אחת), וטקסט ארוך מ-4096 תווים נחתך לאורך הזה.

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

#### `$storage` — ערך מאחסון התוסף

מ-`minAppVersion: 0.9.98`, בהרשאה `plugin.storage.read` שחייבת להיות מוצהרת
ומוענקת בזמן הלחיצה. ‏`{ "$storage": "key" }` נפתר בזמן הלחיצה לערך
שהתוסף שמר ב-`storage.set` (אותו מרחב אחסון של `storage.get`), או ל-`null`
כשהמפתח אינו קיים. כך דף התוסף שומר פעם אחת נתון שמשתנה בין מחשבים — למשל
הפורט של שירות מקומי — והפעולה משתמשת בו בלי מנוע. זמין בפעולות לחיצה בלבד:
תפריט הקשר ו-[`openAction`](#ספרים-בחיפוש-הספרייה-librarybooks) של ספק ספרים.
ערך שאינו מתאים לפעולה נדחה בזמן הלחיצה, ושום דבר אינו מבוצע (חריג אחד:
`port` ריק ב-`localService.post`, למטה). כדי שפריט לא יוצג לפני שהערך נשמר,
מצרפים לו `when` עם `{ "storage": { "key": "...", "exists": true } }`.

#### `localService.post` — פנייה לשירות מקומי

מ-`minAppVersion: 0.9.98`, בהרשאה `network.localhost`. שולח בקשת `POST`
עם גוף JSON לשירות שהתוסף מתקין על המחשב, ומציג למשתמש את התשובה — בלי
להעיר את מנוע התוסף. זמין בכל מקום שבו יש פעולת host: פקדי הסרגל, תפריט
הקשר ו-`openAction` של ספק ספרים.

```json
{
  "contextMenuItems": [
    {
      "id": "search-in-service",
      "title": "חיפוש בתוכנה שלי",
      "action": {
        "type": "localService.post",
        "args": {
          "port": { "$storage": "servicePort" },
          "path": "/text/search",
          "body": { "text": { "$selection": "selectedText" } },
          "pendingMessage": "מחפש…",
          "unavailableMessage": "התוכנה שלי אינה פועלת. פתחו את לשונית התוסף.",
          "timeoutMs": 60000
        }
      }
    }
  ]
}
```

| ארגומנט | חובה | תיאור |
|---|---:|---|
| `port` | כן | פורט 1–65535. היעד תמיד `http://127.0.0.1:<port>`; אין דרך לבנות כתובת אחרת. `null` (למשל `$storage` שעוד לא נשמר) פירושו שהשירות לא עלה: מוצגת `unavailableMessage`, בלי בקשה. |
| `path` | כן | נתיב מוחלט: אותיות לטיניות, ספרות, `-`, `_`, `.`, `~` ו-`/`, עד 256 תווים. בלי query, בלי `//` ובלי `.`/`..`. |
| `body` | לא | אובייקט JSON קטן (עד 256 צמתים, עומק עד 10, מחרוזות עד 4096 תווים, בלי תווי בקרה). ברירת מחדל: `{}`. |
| `pendingMessage` | לא | הודעת המתנה שמוצגת מיד ונשארת עד התשובה (עד 200 תווים). |
| `unavailableMessage` | לא | הודעה כשהשירות אינו עונה — חיבור שנדחה, זמן המתנה שעבר או `port` ריק (עד 200 תווים). ברירת מחדל: הודעה כללית של אוצריא. |
| `timeoutMs` | לא | 1000–120000. ברירת מחדל: 30000. |

ערך מילולי של ארגומנט (שאינו הפניה) נבדק כבר בהתקנה; הפניות נבדקות אחרי הפתרון, בזמן הלחיצה. `port` ריק מותר רק בפעולת
לחיצה (תפריט הקשר, `openAction`); בפקדים ובתכניות הוא שגיאה.

**הרשאה ויעד.** כמו `network.fetchStream`: המניפסט מצהיר על
`network.enabled` ועל `127.0.0.1` ב-`network.allowlist` (כשהפורט נשמר
ב-`$storage` ומשתנה בין מחשבים, `127.0.0.1` בלי פורט), וההרשאה
`network.localhost` מוענקת. כל אלה נבדקים בזמן הלחיצה, לפני שהבקשה יוצאת;
יעד חסום מציג הודעה שהגישה חסומה בהגדרות הרשת.

**לחיצה כפולה.** בזמן שבקשה זהה של התוסף (אותה כתובת ואותו גוף) עוד רצה,
לחיצה נוספת אינה שולחת אותה שוב ואינה מחליפה את הודעת ההמתנה הקיימת.
בקשה עם גוף אחר (למשל טקסט מסומן אחר) נשלחת, והשירות מחליט אם הוא פנוי.

**התשובה.** השירות עונה JSON בצורה
`{ "message": "...", "severity": "info" | "success" | "error" }` (שני
השדות אופציונליים). `message` מוצג כהודעת מערכת עם ייחוס לתוסף, כמו
`ui.showSnack`; הודעה ארוכה מ-200 תווים מקוצרת. בלי `severity`, תשובת 2xx
מוצגת כהצלחה וכל קוד אחר כשגיאה. שגיאה בלי `message`, או תשובה שאינה
UTF-8 תקין, מציגה הודעה כללית; הצלחה בלי `message` רק מסירה את הודעת
ההמתנה. מהתשובה נקראים כ-64 אלף תווים לכל היותר, ותוכן אחר בה אינו מגיע
לתוסף.

הבקשה נשלחת מאוצריא (Dart), בלי `Origin` ובלי כותרות `Sec-Fetch-*`, עם
`Content-Type: application/json; charset=utf-8`.

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

## ריצת רקע (app.run\_on\_startup)

ההרשאה `app.run_on_startup` מתירה לאוצריא להריץ את מנוע התוסף ברקע בלי שהמשתמש פתח את דף התוסף. המנוע קם **רק לפי דרישה** — לחיצה על תרומה דקלרטיבית, נושא מתוך `activationEvents`, או הטריגר `app.startup`; ראו §הפעלה עצלה. ללא `contributes.startup` אין טריגר, ולכן ההרשאה לבדה אינה מרימה מנוע.

### הצהרה במניפסט

```json
{
  "permissions": ["app.run_on_startup", "notifications.send"],
  "contributes": {
    "startup": { "activationEvents": ["app.startup"] }
  }
}
```

### זיהוי מצב ב-plugin.boot

```javascript
Otzaria.on('plugin.boot', async (payload) => {
  // payload.app.runMode === 'background'  → מופע רקע שהוער לפי דרישה
  // payload.app.runMode === 'foreground' → רץ בלשונית הנראית

  if (payload.app.runMode === 'background') {
    await Otzaria.call('notifications.showInApp', {
      message: 'מופע הרקע של התוסף נטען בהצלחה',
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
    "library.refresh",
    "library.books.provide",
    "search.fulltext.read",
    "search.field_actions",
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

הצהרה על ההרשאה `network.access` ב-`manifest.json` **אינה מספיקה** כדי שתוסף יוכל לגשת לרשת. הסעיף הזה חל על יעדי **אינטרנט** בלבד; יעד מקומי (`localhost` / `127.0.0.x`) נבדק לפי `network.localhost` ואינו דורש אישור מאוצריא (ראו [שירותים מקומיים](#שירותים-מקומיים-localhost--הרשאת-networklocalhost)). בפועל, ה-URL חייב לעבור שתי בדיקות מצטברות:

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

גישה לשירות שרץ על מחשב המשתמש — למשל מודל שפה מקומי כמו **Ollama** או **LM Studio**, או יישום מקומי אחר — מטופלת בהרשאה נפרדת. **היא אינה `network.access`.**

| | `network.access` | `network.localhost` |
|---|---|---|
| יעד | אתר או שרת באינטרנט | `localhost`, `::1`, `127.0.0.0` עד `127.0.0.255` |
| מתירה אינטרנט | כן | **לא, בשום גרסה** |
| מתירה יעד מקומי | **לא** מאוצריא 0.9.98.1 (לפני כן כן, לתאימות) | כן |
| allowlist גלובלי (PR לאוצריא) | נדרש | לא נדרש |

**כלל ההחלטה:** הסתכלו על ה-host שב-URL. `localhost` או `127.0.0.x` ← `network.localhost`. כל דבר אחר ← `network.access`.

- **0.9.98.1 ומעלה:** ההפרדה מלאה וחובה, בלי קשר ל-`minAppVersion` של התוסף. תוסף שהצהיר רק על `network.access` — אין לו גישה לשום שירות מקומי. תוסף שהצהיר רק על `network.localhost` — אין לו גישה לאינטרנט. פנייה לשני סוגי יעדים דורשת את שתי ההרשאות.
- **לפני 0.9.98.1 (תקופת מעבר):** יעד מקומי מתקבל עם `network.localhost` או עם `network.access`, כדי שתוסף שנכתב לפני ההפרדה לא יישבר. `network.localhost` לעולם אינה מתירה אינטרנט. כדי שהתוסף יעבוד נכון בשתי התקופות, הצהירו על ההרשאה שמתאימה לכל יעד שלו.
- **אריזה והתקנה:** תוסף עם `minAppVersion` `0.9.98.1` ומעלה ו-`network.allowlist` שאינו תואם להרשאות שהוצהרו נכשל באריזה ובהתקנה. מתחת ל-`0.9.98.1` זו אזהרה.
- **רק `127.0.0.0`–`127.0.0.255` בכתיבה עשרונית מלאה מוכרים כמקומיים.** `127.0.1.1`, `127.10.10.1`, `127.1`, `127.0.0.01`, `0.0.0.0`, `172.x.x.x`, `192.168.x.x`, `10.x.x.x` ושמות מחשב ברשת הם **אינטרנט** לצורך ההרשאות, ודורשים `network.access` ואישור ב-allowlist הגלובלי.
- היעד חייב להופיע ב-`network.allowlist` של התוסף, אבל **אין צורך ב-PR לאוצריא** — יעד מקומי אינו נכלל ב-allowlist הגלובלי. הכתובת בהצהרה חייבת להיות זהה לכתובת בפנייה: הצהרה על `127.0.0.1` אינה מכסה `127.0.0.9`.
- הצהרת host חשוף (`"127.0.0.1"` / `"localhost"`) מתירה כל פורט על אותו host; הצהרת URL מלא (`"http://127.0.0.1:36900"`) נועלת לפורט שהוצהר.
- כמו כל גישת רשת — חובה גם `network.enabled: true` ב-manifest. הקריאות חייבות לעבור דרך `network.fetchStream` (או `network.download` / `network.fetchFile`), לא `fetch()` ישיר מה-WebView, שנחסם ב-CORS מול שרת מקומי שדוחה `Origin: null`.

**טעויות נפוצות**
- ❌ `network.access` כדי לגשת ל-Ollama או ליישום מקומי — נחסם מאוצריא 0.9.98.1. השתמשו ב-`network.localhost`.
- ❌ `network.localhost` כדי להוריד קובץ מ-GitHub או לקרוא ל-API באינטרנט — נחסם בכל גרסה. הוסיפו `network.access`.
- ❌ הצהרה על ההרשאה בלי להוסיף את הכתובת ל-`network.allowlist`.

רק שירות מקומי:

```json
"permissions": ["network.localhost"],
"network": { "enabled": true, "allowlist": ["127.0.0.1", "http://127.0.0.9:36900"] }
```

אינטרנט ושירות מקומי:

```json
"permissions": ["network.access", "network.localhost"],
"network": { "enabled": true, "allowlist": ["https://api.example.com/v1", "127.0.0.1"] }
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
  icon: 'bookmark_24_regular',  // שם אייקון מאוצריא או מפלואנט (אופציונלי) — ראה ICONS.md
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
- `contexts` הוא מערך ויכול להכיל את `reader-selection`, את `reader-page-shape-selection`, או את שניהם באותו פריט. מ-`0.9.97` נתמך גם `reader-highlight` (ראו למטה), ומ־`0.9.98.1` נתמכים גם `reader-book` (ללא סימון) וארבעת הקשרי המפרשים וה־PDF (ראו למטה). ערכי `contexts` חייבים להיות חוקיים וייחודיים. פריט שלא מגדיר `contexts` מופיע בשני הקשרי הבחירה (כהתנהגות הרישום המקורית).
- ילד שלא מגדיר `contexts` יורש את המערך של אביו. ילד שמגדיר `contexts` במפורש מוצג רק בהקשרים שלו, ללא איחוד אוטומטי עם הקשר האב; ההקשרים המפורשים חייבים להיות תת־קבוצה של הקשרי האב.
- אפשר להגדיר `onClickEvent` או `onColorClickEvent` כאירוע מותאם אישית

**שמות הקודש בלחיצה — `rawDivineNames` (מ־`0.9.98.1`):**
הטקסט שבלחיצה — `selectedText`, וב־`selection` גם `text`, `renderedSelectedText`,
`normalizedSelectedText` ואיברי `sections` — מגיע כברירת מחדל עם שמות הקודש לפי
בחירת המשתמש, כפי שהקורא מציג את הספר ברגע הלחיצה (ראו
[שמות הקודש בטקסט שמגיע לתוסף](#שמות-הקודש-בטקסט-שמגיע-לתוסף)). בטקסט הראשי
מוחלפים שם הוי"ה ושאר השמות שהמסד מסמן; במפרש וב־PDF — שם הוי"ה בלבד.
`sourceSelectedText` ו־`sourceRange` נשארים מול הטקסט השמור.

פריט שצריך את הנוסח השמור מצהיר `rawDivineNames: true`:

```javascript
await Otzaria.call('reader.addContextMenuItem', {
  id: 'compare-source',
  title: 'השווה למקור',
  rawDivineNames: true        // ⚠️ רק אם הטקסט אינו מוצג למשתמש כמו שהוא
});
```

- ערך בוליאני בלבד (אחר: `error.invalid_params`); ברירת המחדל `false`.
- ילד יורש את הערך מאביו, ויכול לקבוע ערך משלו.
- חל על כל מסלולי הלחיצה של הפריט: אירועי הלחיצה, שורת צבעים
  (`contextMenu.colorClicked`), `openPlugin`, קיצור מקלדת עם `contextMenuItemId`
  ופעולה דקלרטיבית (`$selection.selectedText`). עובד גם בפריטי `contextMenuItems`
  במניפסט.
- `showWhen` נבדק מול הטקסט כפי שהוא מוצג על המסך.
- במפרש וב־PDF, ובבחירה שאי אפשר לעגן, `rawDivineNames: true` מחזיר את הטקסט כפי
  שהוצג על המסך (ראו [המגבלה](#rawdivinenames--טקסט-כפי-שנשמר)).
- ⚠️ קראו את [האזהרה](#rawdivinenames--טקסט-כפי-שנשמר) לפני שימוש. בפריטים אין
  `events.setOptions` — האפשרות היא של הפריט בלבד.

**פעולה ללא סימון — `reader-book` (מ־`0.9.98.1`):**
מ־`0.9.98.1`, `selection.tabId` מזהה את לשונית הטקסט המדויקת שממנה נפתח התפריט,
גם כשאותו ספר פתוח בכמה לשוניות או בחלוניות מפוצלות. מעבירים אותו ישירות ל־
`reader.beginCorrectionSession`; אין לבחור לשונית לפי כותרת הספר או לפי הלשונית
הפעילה לאחר פתיחת התוסף. השדה יכול להיעדר בתצוגה מקדימה שאינה מחוברת ללשונית.
אפשר לרשום `contexts: ['reader-book']` להצגת פעולה בלחיצה ימנית ללא סימון, בשני קוראי הטקסט: הקורא הרגיל וקורא צורת הדף. ה־payload כולל את זהות הספר ואת `sectionIndex` ו־`currentIndex` של הפסקה שנלחצה. בשדה `selection`, הערך `text` הוא מחרוזת ריקה, `start` ו־`end` הם `null`, ואין `sourceRange`. ברירות המחדל של פריט ללא `contexts` נשארות שני הקשרי הבחירה; ילדים ללא `contexts` יורשים את הקשרי האב גם עבור `reader-book`.

**מפרשים ו־PDF — `reader-commentary`, `reader-pdf` וגרסאות `-selection` (מ־`0.9.98.1`):**

| הקשר | היכן מופיע הפריט |
|------|------------------|
| `reader-commentary` | לחיצה ימנית על מפרש, ללא סימון |
| `reader-commentary-selection` | לחיצה ימנית על מפרש עם טקסט מסומן בו |
| `reader-pdf` | לחיצה ימנית על עמוד PDF, ללא סימון |
| `reader-pdf-selection` | לחיצה ימנית על עמוד PDF עם טקסט מסומן |

"מפרש" הוא רשימת המפרשים של התצוגה הרגילה (גם בחלונית הצד), עמודות המפרשים
של צורת הדף וחלונית המפרשים של ספר PDF — לא לשונית הקישורים. ההקשרים אינם
נכללים בברירת המחדל: פריט שלא מגדיר `contexts` ממשיך להופיע רק בטקסט הראשי.
`reader-highlight` אינו פעיל במפרשים וב־PDF, וקיצור מקלדת עם
`contextMenuItemId` פועל על בחירה בטקסט הראשי בלבד. (`reader-pdf` כאן אינו
ההקשר באותו שם של `reader.addToolbarItem`, שמשמעו כל ספר PDF.)

**ב־payload של מפרש, המפרש הוא הספר הנוכחי:** `currentBook`, `bookTitle`,
`bookId` ו־`id` מתארים את ספר המפרש; `sectionIndex`/`currentIndex` הם השורה
בתוכו (מבוסס־0), ו־`currentRef` הוא כתובת המפרש. כך פריט ופעולה דקלרטיבית
(`action`) שנכתבו לטקסט הראשי עובדים גם על מפרש בלי שינוי. `bookUid` חסר
כשאין לספר המפרש `id` (למשל ספר משתמש). הספר הנקרא נמסר ב־`selection.mainBook`:

| שדה | בספר טקסט | בספר PDF |
|-----|-----------|----------|
| זהות (`id`, `bookId`, `bookUid`, `type`, `source`) | הספר הנקרא | ה־PDF |
| `currentRef` | המיקום הנוכחי בספר | כתובת העמוד הנוכחי |
| `sectionIndex` | השורה שאליה המפרש מקושר (מבוסס־0); חסר בעמודת צורת הדף | העמוד הנוכחי (מבוסס־1) |
| `pageNumber` | — | העמוד הנוכחי (מבוסס־1) |

**ב־payload של עמוד PDF** מספר העמוד שנלחץ (או עמוד תחילת הסימון) נמסר
ב־`pageNumber`, וכמו ב־`reader.getCurrentState` גם ב־`sectionIndex`/`currentIndex`
(מבוסס־1). `currentRef` הוא כותרת העמוד מתוכן העניינים של ה־PDF, או "עמוד N".

אין `sourceRange` במפרשים וב־PDF. הטקסט כפוף למגבלות ההעתקה: בספר מוגן הוא
נחתך כמו בטקסט הראשי, ובמסמך PDF שאוסר העתקה — או בבחירה החוצה כמה מפרשים
מעבר למגבלה — הלחיצה נמסרת עם `selectedText` ריק. ב־PDF שעמודי הסימון שלו
עוד לא נטענו הטקסט נקרא בזמן הלחיצה, ולכן פריט עם `showWhen` אינו מוצג במצב
כזה.

```javascript
await Otzaria.call('reader.addContextMenuItem', {
  id: 'search',
  title: 'חפש במאגר שלי',
  contexts: [
    'reader-selection',
    'reader-page-shape-selection',
    'reader-commentary-selection',
    'reader-pdf-selection'
  ],
  onClickEvent: 'myPlugin.search'
});

Otzaria.on('myPlugin.search', ({ selectedText, currentBook, selection }) => {
  // currentBook — הספר שבו סומן הטקסט: הספר הנקרא, המפרש או ה-PDF
  // selection.mainBook — הספר הנקרא, רק כשהלחיצה הייתה על מפרש
  // selection.pageNumber — רק בעמוד PDF
});
```

בגרסאות שלפני `0.9.98.1` הפריט כולו נדחה עם `error.unsupported_context`, גם כשהוא
כולל לצדם הקשרים מוכרים. תוסף שתומך בגרסאות קודמות רושם שוב בלי ההקשרים
החדשים:

```javascript
const legacy = ['reader-selection', 'reader-page-shape-selection'];
const item = { id: 'search', title: 'חפש', onClickEvent: 'myPlugin.search' };
try {
  await Otzaria.call('reader.addContextMenuItem', {
    ...item, contexts: [...legacy, 'reader-commentary-selection']
  });
} catch (error) {
  if (!String(error?.code ?? error).includes('unsupported_context')) throw error;
  await Otzaria.call('reader.addContextMenuItem', { ...item, contexts: legacy });
}
```

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

### Event: `library.providerBook.openRequested`
**מ-0.9.98** — אירוע ממוקד; אינו דורש הרשאת `events.subscribe`.

המשתמש בחר ספר של הספק במסך הספרייה (בכרטיס, בשורת הרשימה או בכפתור
הפתיחה של התצוגה המקדימה). אוצריא אינה פותחת את הספר בעצמה — התוסף הוא שפותח
אותו, למשל בתוכנה חיצונית דרך שירות מקומי.

```javascript
Otzaria.on('library.providerBook.openRequested', async ({ provider, id, title, author }) => {
  await openInMyProgram(id);
});
```

| שדה | תיאור |
|-----|-------|
| `provider` | שם הספק. |
| `id` | המזהה מ-`books[].id`. |
| `title` | שם הספר. |
| `author` | המחבר, כשנשלח. |

האירוע נמסר עם `preferBackground`: לתוסף שאושרה לו `app.run_on_startup` — למנוע
הרקע, בלי שהמשתמש יעזוב את מסך הספרייה; בלי ההרשאה — נפתח דף התוסף והאירוע
נמסר אליו, כך שהלחיצה תמיד עובדת. ספק עם `openAction` אינו מקבל את האירוע:
הלחיצה מבצעת את הפעולה.

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

`selectedText` ו-`selection.text` מגיעים עם שמות הקודש לפי בחירת המשתמש, בלי
U+2060 (מ-0.9.98.1). פריט שנרשם עם `rawDivineNames: true` מקבל אותם כפי שנשמרו —
ראו `rawDivineNames` ב-[`reader.addContextMenuItem`](#readeraddcontextmenuitem).

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
  icon: 'bookmark_24_regular',  // שם אייקון מאוצריא או מפלואנט (חובה בפקד עליון) — ראה ICONS.md
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

בספר שהמו"ל הגביל, `text` כולל לכל היותר את 40 השורות הראשונות של הבחירה.

**שמות הקודש (מ-0.9.98.1).** `text` (ו-`renderedSelectedText` כשהוא קיים) מגיע לפי
בחירת המשתמש העדכנית לכרטיסייה, שם הוי"ה ושאר השמות שהמסד מסמן, בלי U+2060.
`start`/`end` הם אופסטים בטקסט שעל המסך. מאזין שצריך את הנוסח השמור מבקש אותו
לנושא כולו — `Otzaria.on('reader.selection_changed', handler, { rawDivineNames: true })`
או [`events.setOptions`](#eventssetoptions) (⚠️ [האזהרה](#rawdivinenames--טקסט-כפי-שנשמר)).
בחירה שלא ניתן לעגן נמסרת כפי שהוצגה על המסך גם במקרה הזה.

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

העוגנים שבהדגשות הם עוגני מקור, עם הטקסט השמור — שמות הקודש אינם מסוננים בהם
(ראו [מה נשאר כפי שנשמר](#מה-נשאר-כפי-שנשמר)); הציגו למשתמש טקסט מסונן ממקור אחר.

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
## קורא תוספים משובץ

למימוש תצוגת טקסט חלופית בתוך כרטיסיית ספר, ראו [קורא טקסט באמצעות תוסף](DEFAULT_TEXT_READER.md): בחירת משתמש, מופע לכל כרטיסייה, ניווט ושמירת מיקום, פרופיל תצוגה וחזרה לקורא המובנה.
