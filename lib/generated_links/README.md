# Generated Inline Links — מדריך למפתח

## מה זה?
זיהוי אוטומטי של הפניות (גמרא, תנ"ך וכו') בתוך טקסט ספר, והפיכתן לקישורים לחיצים בממשק.

---

## איפה לוגיקת הזיהוי?

### `rules/` — כאן מוסיפים/משנים כללי זיהוי
כל כלל יורש מ-`GeneratedLinkRule` ומממש `detect(ctx, lines, range)`:

| קובץ | מה הוא מזהה |
|---|---|
| `gemara_reference_rule.dart` | הפניות לגמרא: "ברכות ב.", "סנהדרין כא:" |
| `gemara_sham_reference_rule.dart` | "שם" / "שם דף כ." לאחר הפניה קודמת |
| `tanach_reference_rule.dart` | הפניות לתנ"ך: "בראשית א ב", "תהלים קי"ט" |
| `tanach_sham_reference_rule.dart` | "שם" לאחר הפניה לתנ"ך |

**כדי להוסיף כלל חדש:** צור קובץ בתיקייה זו, הוסף אותו ל-`generated_link_rules_registry.dart`.

### `repository/generated_links_book_resolver.dart` — פתרון שם ספר לנתיב+שורה
מקבל `bookTitle + refText`, מחזיר `GeneratedLinkTarget` עם `targetBookId` ו-`targetIndex`.
מחפש בספרייה (דרך `ReferenceBooksCache`) ואחר כך ב-TOC.

**חשוב:** רק התאמה מדויקת (`matchRank == 0`) מתקבלת. שם עמום (שני ספרים באותו שם) → `null`.

---

## זרימת עיבוד (לסקירה מהירה)

```
TextBookBloc._scheduleGeneratedLinksForBook()
    → GeneratedLinksScheduler.schedule(ProcessingJob)
        → GeneratedLinksProcessor.processBatch()
            1. Isolate: כל הכללים ב-rules/ → List<DetectedReference>
            2. Main thread: BookResolver → List<GeneratedInlineLink>
        → GeneratedLinksCacheStore.save()  ← cache אטומי לפי bookId
        → BatchResult נפלט ל-stream
    → TextBookBloc מקבל event → state.generatedLinksByLine מתעדכן
```

---

## דברים שחשוב לדעת

- **Fingerprint** = `"${bookId}:${lineCount}"` — cache נפסל אוטומטי אם מספר השורות משתנה.
- **ביטול** — `scheduler.cancel(jobId)` עוצר גם job שרץ עכשיו (בדיקה אחרי `processBatch`). ה-BLoC מבטל אוטומטי ב-`close()` וב-preview→full-content.
- **WorkGate** — reference counting. כשאינדוקס או file-sync רצים הגייט סגור; `isIdle` רק כשכל המקורות שחררו.
- **URL scheme** — `otzaria://generated-link?bookId={id}&book={title}&index0={line}&ref={display}`. הפתיחה לפי `bookId` (יציב), `book` לתצוגה בלבד.
- **הזרקת HTML** — `addAllInlineLinksToText()` ב-`utils/text_with_inline_links.dart` — תמיד על הטקסט הגולמי, לא על HTML קיים.
