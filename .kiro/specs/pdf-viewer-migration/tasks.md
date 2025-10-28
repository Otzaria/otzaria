# תוכנית יישום: מעבר מ-pdfrx ל-Syncfusion PDF Viewer

## סקירה

תוכנית זו מפרטת את השלבים הנדרשים להחלפת חבילת pdfrx בחבילת syncfusion_flutter_pdfviewer באפליקציית אוצריא. היישום יתבצע בצורה הדרגתית, תוך בדיקה של כל רכיב לפני המעבר לבא.

---

## 1. הכנה ועדכון תלויות

- [x] 1.1 עדכון pubspec.yaml
  - הסרת התלות `pdfrx: ^1.3.2`
  - הוספת התלות `syncfusion_flutter_pdfviewer: ^31.2.3`
  - הוספת התלות `syncfusion_flutter_pdf: ^31.2.3` (לעיבוד מסמכים)
  - הוספת התלות `syncfusion_flutter_core: ^31.2.3` (לנושאים)
  - הרצת `flutter pub get` לטעינת התלויות
  - בדיקה שאין התנגשויות חבילות
  - _דרישות: 1.1, 1.2, 1.3, 1.4, 1.5, 1.6_

- [x] 1.2 הגדרת רישוי Syncfusion
  - פתיחת קובץ `lib/main.dart`
  - הוספת `import 'package:syncfusion_flutter_core/core.dart';`
  - הוספת קריאה ל-`SyncfusionLicense.registerLicense('YOUR_LICENSE_KEY');` בתחילת main(), לפני runApp()
  - החלפת 'YOUR_LICENSE_KEY' במפתח הרישוי הקיים
  - בדיקה שהאפליקציה רצה ללא אזהרות רישוי
  - _דרישות: 1.7, 1.8_

- [ ]* 1.3 בדיקת תאימות גרסאות
  - בדיקה שהגרסה 31.2.3 תואמת לתלויות הקיימות
  - אם יש התנגשויות, ניסיון גרסאות ישנות יותר
  - תיעוד הגרסה הסופית שנבחרה
  - _דרישות: 1.5_

---

## 2. יצירת שכבת התאמה (Facade) - אופציונלי

- [ ]* 2.1 יצירת PdfViewerFacade
  - יצירת קובץ `lib/pdf_book/pdf_viewer_facade.dart`
  - עטיפת פעולות מרכזיות: `goToPage()`, `zoomIn()`, `zoomOut()`, `search()`
  - מיפוי אוטומטי בין API של pdfrx ל-Syncfusion
  - מטרה: לצמצם שינויים בקוד קיים ולאפשר rollback קל
  - _דרישות: 17.1, 17.3_

- [ ]* 2.2 שימוש ב-Facade בקוד
  - החלפת קריאות ישירות ל-controller בקריאות ל-facade
  - שמירה על ממשק API דומה לקוד המקורי
  - _דרישות: 17.1, 17.2_

---

## 3. עדכון מודל PdfBookTab

- [x] 3.1 עדכון imports ב-pdf_tab.dart
  - החלפת `import 'package:pdfrx/pdfrx.dart'` ב-`import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart'`
  - הוספת `import 'package:syncfusion_flutter_pdf/pdf.dart'`
  - _דרישות: 2.1, 2.2, 2.3_

- [x] 3.2 עדכון שדות המחלקה
  - שינוי `ValueNotifier<List<PdfOutlineNode>?>` ל-`ValueNotifier<List<PdfBookmark>?>`
  - שינוי `ValueNotifier<PdfDocumentRef?>` ל-`ValueNotifier<PdfDocument?>`
  - שינוי `List<PdfTextRangeWithFragments>?` ל-`PdfTextSearchResult?`
  - הוספת שדה `bool _isDocumentLoaded = false` למעקב אחר מצב הטעינה
  - _דרישות: 13.1, 13.2, 13.3, 13.4_

- [x] 3.3 עדכון סריאליזציה (toJson/fromJson)
  - עדכון המרה של outline/bookmarks
  - עדכון המרה של מצב חיפוש
  - שמירה על תאימות לאחור עם JSON קיים
  - _דרישות: 13.5, 13.6_

---

## 4. עדכון מסך PDF הראשי (PdfBookScreen)

- [x] 4.1 עדכון imports ב-pdf_book_screen.dart
  - החלפת `import 'package:pdfrx/pdfrx.dart'`
  - הוספת imports של Syncfusion
  - _דרישות: 2.1, 2.2, 2.3_

- [x] 4.2 עדכון אתחול Controller
  - שמירה על `PdfViewerController()` (שם זהה)
  - הסרת `PdfTextSearcher` - יוחלף בחיפוש מובנה
  - הוספת `GlobalKey<SfPdfViewerState>` לגישה ל-state
  - _דרישות: 3.1, 3.2_

- [x] 4.3 החלפת widget PdfViewer ב-SfPdfViewer
  - שינוי `PdfViewer.file()` ל-`SfPdfViewer.file()`
  - המרת `File(widget.tab.book.path)` במקום string path
  - הוספת `key: _pdfViewerKey`
  - הגדרת `initialPageNumber: widget.tab.pageNumber`
  - _דרישות: 4.1, 4.2_

- [x] 4.4 הגדרת פרמטרים בסיסיים
  - `canShowScrollHead: true`
  - `canShowScrollStatus: true`
  - `pageLayoutMode: PdfPageLayoutMode.continuous`
  - `scrollDirection: PdfScrollDirection.vertical`
  - `interactionMode: PdfInteractionMode.selection`
  - _דרישות: 4.3, 4.4, 4.6_

- [x] 4.5 יישום callback onDocumentLoaded
  - שמירת המסמך ב-`widget.tab.document.value`
  - טעינת bookmarks: `widget.tab.outline.value = details.document.bookmarks`
  - עדכון `_isDocumentLoaded = true`
  - הפעלת חיפוש ראשוני אם יש טקסט חיפוש
  - _דרישות: 5.1, 13.1, 13.4_

- [x] 4.6 יישום callback onPageChanged
  - עדכון `widget.tab.pageNumber = details.newPageNumber`
  - עדכון כותרת נוכחית מתוכן העניינים
  - _דרישות: 3.4, 5.4_

- [x] 4.7 יישום callback onDocumentLoadFailed
  - זיהוי שגיאת סיסמה (בדיקה אם השגיאה מכילה 'password')
  - הצגת דיאלוג סיסמה
  - טעינה מחדש של המסמך עם הסיסמה
  - _דרישות: 16.1, 16.2, 16.3, 16.4, 16.5_

- [x] 4.8 יישום callback onTextSelectionChanged
  - שמירת `_textSelectionDetails = details`
  - הצגת תפריט הקשר לטקסט נבחר
  - _דרישות: 14.1_

- [x] 4.9 עדכון מתודות ניווט
  - שינוי `goToPage(pageNumber: x)` ל-`jumpToPage(x)`
  - שינוי `zoomUp()` ל-`zoomLevel *= 1.25`
  - שינוי `zoomDown()` ל-`zoomLevel *= 0.8`
  - _דרישות: 3.3, 3.4, 3.5_

- [x] 4.10 יישום ColorFilter למצב כהה
  - עטיפת SfPdfViewer ב-ColorFilter
  - שימוש ב-`BlendMode.difference` במצב כהה
  - סנכרון עם SettingsBloc
  - _דרישות: 15.1, 15.2, 15.3, 15.4_



---

## 5. עדכון תצוגת תוכן עניינים (OutlineView)

- [x] 5.1 עדכון imports ב-pdf_outlines_screen.dart
  - החלפת imports של pdfrx
  - הוספת imports של Syncfusion
  - _דרישות: 2.1, 2.2_

- [x] 5.2 עדכון מבנה נתונים
  - שינוי `List<PdfOutlineNode>?` ל-`List<PdfBookmark>?`
  - שינוי `node.dest` ל-`bookmark.destination`
  - שינוי `node.children` ל-`bookmark.bookmarks`
  - _דרישות: 5.1, 5.2_

- [x] 5.3 עדכון מתודת ניווט
  - שינוי `controller.goTo(...)` ל-`controller.jumpToPage(bookmark.destination!.page)`
  - הסרת `calcMatrixFitWidthForPage` - לא נדרש ב-Syncfusion
  - _דרישות: 5.3_

- [x] 5.4 עדכון לוגיקת סנכרון
  - עדכון `_findPath` לעבודה עם `bookmark.bookmarks`
  - עדכון `_ensureParentsOpen` לעבודה עם bookmarks
  - שמירה על לוגיקת הרחבה אוטומטית
  - _דרישות: 5.4, 5.6_

- [x] 5.5 עדכון חיפוש בתוכן עניינים
  - עדכון `getAllNodes` לעבודה עם bookmarks
  - שמירה על פונקציונליות סינון
  - _דרישות: 5.5_

---

## 6. עדכון תצוגת חיפוש (PdfBookSearchView)

- [x] 6.1 עדכון imports ב-pdf_search_screen.dart
  - החלפת imports של pdfrx
  - הוספת imports של Syncfusion
  - _דרישות: 2.1, 2.2_

- [x] 6.2 החלפת מנגנון חיפוש
  - הסרת `PdfTextSearcher`
  - שימוש ב-`controller.searchText(query)` של Syncfusion
  - שמירת `PdfTextSearchResult` במקום רשימת matches
  - הצגת מספר תוצאות: `searchResult.totalInstanceCount`
  - _דרישות: 6.1, 6.2_

- [x] 6.3 יישום ניווט בין תוצאות
  - שימוש ב-`searchResult.nextInstance()`
  - שימוש ב-`searchResult.previousInstance()`
  - Syncfusion מספק highlighting אוטומטי של התוצאה הנוכחית
  - עדכון UI בהתאם
  - _דרישות: 6.3, 6.4_

- [ ]* 6.4 יישום תצוגת הקשר טקסטואלי (lazy loading)
  - **הערה:** תכונה זו אופציונלית - Syncfusion מספק highlighting אוטומטי
  - חילוץ טקסט דף באמצעות `PdfTextExtractor` רק כשהמשתמש מבקש
  - cache לטקסט דפים שכבר חולצו
  - הצגת הקשר סביב המילה
  - _דרישות: 6.5, 6.6_

- [x] 6.5 שמירת מצב חיפוש בטאב
  - שמירת `searchResult` ב-PdfBookTab
  - שמירת אינדקס נוכחי
  - שחזור חיפוש בפתיחה מחדש
  - _דרישות: 6.7_

---

## 7. עדכון תצוגת מספר דף (PageNumberDisplay)

- [x] 7.1 עדכון imports ב-pdf_page_number_dispaly.dart
  - החלפת imports של pdfrx
  - הוספת imports של Syncfusion
  - _דרישות: 2.1, 2.2_

- [x] 7.2 עדכון שימוש ב-controller
  - שמירה על `controller.pageNumber`
  - שמירה על `controller.pageCount`
  - שינוי `goToPage(pageNumber: x)` ל-`jumpToPage(x)`
  - _דרישות: 3.3, 3.4_

- [x] 7.3 בדיקת מצב isReady
  - החלפת `controller.isReady` במעקב אחר `_isDocumentLoaded`
  - או בדיקה ש-`controller.pageCount > 0`
  - _דרישות: 3.3_

---

## 8. עדכון Page Converter

- [x] 8.1 עדכון imports ב-page_converter.dart
  - החלפת imports של pdfrx
  - הוספת imports של Syncfusion
  - _דרישות: 2.1, 2.2_

- [x] 8.2 עדכון טעינת outline
  - שינוי `PdfDocument.openFile(path).then((doc) => doc.loadOutline())`
  - ל-`PdfDocument.openFile(path)` ואז גישה ל-`document.bookmarks`
  - _דרישות: 8.1, 9.1_

- [x] 8.3 עדכון _collectPdfAnchors
  - שינוי `List<PdfOutlineNode>` ל-`List<PdfBookmark>`
  - שינוי `node.dest?.pageNumber` ל-`bookmark.destination?.page`
  - שינוי `node.children` ל-`bookmark.bookmarks`
  - _דרישות: 8.2_

- [x] 8.4 עדכון מפות המרה
  - שמירה על לוגיקת המרה PDF<->טקסט
  - עדכון cache של מפות
  - _דרישות: 8.3, 8.4, 8.5_

---

## 9. עדכון Ref Helper

- [x] 9.1 עדכון imports ב-ref_helper.dart
  - החלפת imports של pdfrx
  - הוספת imports של Syncfusion
  - _דרישות: 2.1, 2.2_

- [x] 9.2 עדכון טעינת outline
  - שינוי טעינת outline לשימוש ב-Syncfusion
  - גישה ל-`document.bookmarks`
  - _דרישות: 9.1_

- [x] 9.3 עדכון _collectAllNodes
  - שינוי `List<PdfOutlineNode>` ל-`List<PdfBookmark>`
  - שינוי `node.children` ל-`bookmark.bookmarks`
  - _דרישות: 9.2_

- [x] 9.4 עדכון refFromPageNumber
  - שינוי `entry.dest?.pageNumber` ל-`bookmark.destination?.page`
  - שמירה על לוגיקת בניית ref מלא
  - _דרישות: 9.3, 9.4_

- [x] 9.5 עדכון שמירה ב-Isar
  - שמירה על לוגיקת שמירה במסד נתונים
  - _דרישות: 9.5_

---

## 10. עדכון Indexing Repository

- [x] 10.1 עדכון imports ב-indexing_repository.dart
  - החלפת imports של pdfrx
  - הוספת imports של Syncfusion
  - _דרישות: 2.1, 2.2_

- [x] 10.2 עדכון פתיחת מסמך
  - שימוש ב-`PdfDocument.openFile(book.path)`
  - גישה ל-`document.pages.count` במקום `pages.length`
  - גישה ל-`document.bookmarks` במקום `loadOutline()`
  - _דרישות: 10.1_

- [x] 10.3 עדכון חילוץ טקסט
  - יצירת `PdfTextExtractor(document)`
  - שימוש ב-`textExtractor.extractText(startPageIndex: i, endPageIndex: i)`
  - פיצול לשורות: `pageText.split('\n')`
  - _דרישות: 10.2_

- [x] 10.4 עדכון יצירת refs
  - שימוש ב-bookmarks במקום outline
  - שמירה על לוגיקת יצירת ref לכל שורה
  - _דרישות: 10.3_

- [x] 10.5 שמירה במנוע חיפוש
  - שמירה ב-Tantivy
  - דיווח התקדמות
  - תמיכה בביטול
  - _דרישות: 10.4, 10.5, 10.6_

---

## 11. עדכון Daf Yomi Helper

- [x] 11.1 עדכון imports ב-daf_yomi_helper.dart
  - החלפת imports של pdfrx
  - הוספת imports של Syncfusion
  - _דרישות: 2.1, 2.2_

- [x] 11.2 עדכון getDafYomiOutline
  - שינוי שם ל-`getDafYomiBookmark`
  - שינוי `PdfOutlineNode?` ל-`PdfBookmark?`
  - טעינת bookmarks מהמסמך
  - _דרישות: 11.1, 11.2_

- [x] 11.3 עדכון findEntryInTree
  - שינוי `entry.children` ל-`entry.bookmarks`
  - שמירה על לוגיקת חיפוש רקורסיבי
  - _דרישות: 11.2_

- [x] 11.4 עדכון חזרת מספר דף
  - שינוי `outline?.dest?.pageNumber` ל-`bookmark?.destination?.page`
  - _דרישות: 11.3, 11.4_

---

## 12. עדכון מסך הדפסה

- [x] 12.1 עדכון imports ב-printing_screen.dart
  - החלפת imports של pdfrx
  - הוספת imports של Syncfusion
  - _דרישות: 2.1, 2.2_

- [x] 12.2 החלפת PdfViewer ב-SfPdfViewer
  - שינוי `PdfViewer.data()` ל-`SfPdfViewer.memory()`
  - הגדרת `canShowScrollHead: false`
  - הגדרת `canShowScrollStatus: false`
  - _דרישות: 12.1, 12.2_

- [x] 12.3 שמירה על פונקציונליות שיתוף
  - שמירה על `Printing.sharePdf()`
  - שמירה על אפשרויות עיצוב
  - _דרישות: 12.3, 12.4_

---

## 13. טיפול בקישורים

- [x] 13.1 יישום טיפול בקישורים פנימיים
  - זיהוי לחיצה על קישור דרך Syncfusion callbacks
  - מיפוי `PdfDestination.page` ל-`controller.jumpToPage()`
  - ניווט לדף המתאים
  - _דרישות: 14.1_

- [x] 13.2 יישום טיפול בקישורים חיצוניים
  - זיהוי URL בקישור
  - הצגת דיאלוג אישור למשתמש
  - פתיחה בדפדפן חיצוני דרך `url_launcher`
  - _דרישות: 14.2, 14.3_

- [ ]* 13.3 הוספת logging לקישורים
  - רישום סוג הקישור (פנימי/חיצוני)
  - רישום URL של קישורים חיצוניים
  - שימוש ב-Telemetry/Analytics אם קיים
  - _דרישות: 14.2, 14.3_



---

## 14. בדיקות ואימות

- [x] 14.1 בדיקות קומפילציה
  - הרצת `flutter analyze`
  - תיקון כל אזהרות ושגיאות
  - _דרישות: 18.1_

- [ ] 14.2 בדיקות פונקציונליות בסיסיות (ידני)
  - פתיחת ספר PDF
  - ניווט בין דפים
  - זום פנימה וחוצה
  - _דרישות: 18.2_

- [ ] 14.3 בדיקות תוכן עניינים (ידני)
  - פתיחת תוכן עניינים
  - לחיצה על פריטים
  - סנכרון עם דף נוכחי
  - חיפוש בתוכן עניינים
  - _דרישות: 18.4_

- [ ] 14.4 בדיקות חיפוש (ידני)
  - חיפוש טקסט
  - ניווט בין תוצאות
  - הצגת הקשר
  - _דרישות: 18.3_

- [ ] 14.5 בדיקות thumbnails (ידני)
  - פתיחת תצוגת thumbnails
  - לחיצה על thumbnail
  - סנכרון עם דף נוכחי
  - _דרישות: 18.5_

- [ ] 14.6 בדיקות המרת דפים (ידני)
  - מעבר מ-PDF לטקסט
  - מעבר מטקסט ל-PDF
  - בדיקת דיוק ההמרה
  - _דרישות: 18.6_

- [ ] 14.7 בדיקות מצב כהה (ידני)
  - הפעלת מצב כהה
  - בדיקת תצוגת PDF
  - כיבוי מצב כהה
  - _דרישות: 15.1, 15.2, 15.3_

- [ ] 14.8 בדיקות סיסמאות (ידני)
  - פתיחת PDF מוגן
  - הזנת סיסמה נכונה
  - הזנת סיסמה שגויה
  - _דרישות: 16.1, 16.2, 16.3_

- [ ] 14.9 בדיקות הדפסה (ידני)
  - פתיחת מסך הדפסה
  - תצוגה מקדימה
  - שיתוף PDF
  - _דרישות: 12.1, 12.2, 12.3_

- [ ] 14.10 בדיקות דף יומי (ידני)
  - פתיחת דף יומי
  - ניווט לדף הנכון
  - _דרישות: 11.1, 11.3_

- [ ]* 14.11 בדיקות ביצועים (ידני)
  - זמן טעינת מסמך
  - זמן חיפוש
  - זמן יצירת thumbnails
  - שימוש בזיכרון
  - _דרישות: 18.7_

---

## 15. תיעוד ומסירה

- [ ] 15.1 עדכון תיעוד קוד
  - הוספת הערות לשינויים משמעותיים
  - תיעוד הבדלי API
  - _דרישות: 17.2_

- [ ] 15.2 עדכון README
  - עדכון רשימת תלויות
  - תיעוד שינויים משמעותיים
  - _דרישות: 17.2_

- [ ]* 15.3 יצירת מדריך מעבר
  - תיעוד כל השינויים
  - דוגמאות קוד לפני ואחרי
  - טיפים לפתרון בעיות נפוצות
  - _דרישות: 17.2_

---

## הערות חשובות

### תכונות שאין להן תמיכה ישירה ב-Syncfusion:

**הערה חשובה:** לאחר בדיקת הקוד הקיים, התברר שהאפליקציה **לא משתמשת** בתכונות הבאות:
- ❌ viewerOverlayBuilder - לא בשימוש בקוד הנוכחי
- ❌ linkWidgetBuilder - לא בשימוש בקוד הנוכחי  
- ❌ pagePaintCallbacks - לא בשימוש בקוד הנוכחי
- ❌ PdfDocumentRef - לא בשימוש בקוד הנוכחי
- ❌ PdfDocumentViewBuilder - לא בשימוש בקוד הנוכחי
- ❌ **ThumbnailsView - הקובץ קיים אבל לא בשימוש בשום מקום!**

**תכונות שדורשות התאמה:**

1. **גישה למסמך** - יש גישה מלאה דרך `onDocumentLoaded` callback
   - פתרון: שמירת reference ל-`PdfDocument` שמתקבל ב-callback
   
2. **חיפוש טקסט** - API שונה אבל עם אותה פונקציונליות
   - Syncfusion מספק highlighting אוטומטי של תוצאות
   - הצגת הקשר טקסטואלי היא אופציונלית (lazy loading)
   
3. **סיסמאות** - טיפול דרך `onDocumentLoadFailed` במקום `passwordProvider`
   - זיהוי שגיאת סיסמה והצגת דיאלוג
   - טעינה מחדש עם הסיסמה

### סדר עדיפויות:

1. **קריטי** - משימות 1, 3-7 (פונקציונליות ליבה)
2. **חשוב** - משימות 8-13, 14.1-14.10 (תכונות נוספות)
3. **אופציונלי** - משימות מסומנות ב-* (שיפורים, Facade, תיעוד)

### סיכום השפעת המעבר:

✅ **אין פגיעה בפונקציונליות קיימת** - כל התכונות שהאפליקציה משתמשת בהן נתמכות ב-Syncfusion

✅ **גישה למסמך** - קיימת דרך `onDocumentLoaded(PdfDocumentLoadedDetails details)` שמחזיר `details.document`

✅ **Thumbnails לא נדרש** - הקובץ קיים אבל לא בשימוש בשום מקום באפליקציה

✅ **חיפוש טקסט** - Syncfusion מספק highlighting אוטומטי, הצגת הקשר היא אופציונלית

✅ **רישוי** - נוסף סעיף להגדרת מפתח רישוי ב-main.dart

### הוראות רישוי:

במקום שכתוב `'YOUR_LICENSE_KEY'` ב-main.dart, יש להכניס את מפתח הרישוי הקיים שלך.
הקוד צריך להיראות כך:

```dart
import 'package:syncfusion_flutter_core/core.dart';

void main() {
  SyncfusionLicense.registerLicense('YOUR_ACTUAL_LICENSE_KEY_HERE');
  runApp(MyApp());
}
```
