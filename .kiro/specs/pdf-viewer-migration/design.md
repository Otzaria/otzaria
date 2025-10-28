# מסמך עיצוב: מעבר מ-pdfrx ל-Syncfusion PDF Viewer

## סקירה כללית

מסמך זה מפרט את העיצוב הטכני למעבר מחבילת `pdfrx` לחבילת `syncfusion_flutter_pdfviewer` באפליקציית אוצריא. המעבר כולל החלפת כל השימושים ב-API של pdfrx ב-API המקביל של Syncfusion, תוך שמירה על כל הפונקציונליות הקיימת.

## ארכיטקטורה

### מבנה נוכחי

```
lib/
├── pdf_book/
│   ├── pdf_book_screen.dart          # מסך ראשי להצגת PDF
│   ├── pdf_outlines_screen.dart      # תצוגת תוכן עניינים
│   ├── pdf_page_number_dispaly.dart  # תצוגת מספר דף
│   ├── pdf_search_screen.dart        # תצוגת חיפוש
│   └── pdf_thumbnails_screen.dart    # תצוגת thumbnails
├── tabs/models/
│   └── pdf_tab.dart                  # מודל טאב PDF
├── utils/
│   ├── page_converter.dart           # המרת דפים PDF<->טקסט
│   └── ref_helper.dart               # עזרים ליצירת הפניות
├── printing/
│   └── printing_screen.dart          # מסך הדפסה
├── indexing/repository/
│   └── indexing_repository.dart      # אינדוקס ספרים
└── daf_yomi/
    └── daf_yomi_helper.dart          # עזרים לדף יומי
```

### מיפוי API: pdfrx → Syncfusion

| pdfrx | Syncfusion | הערות |
|-------|-----------|-------|
| `PdfViewerController` | `PdfViewerController` | שם זהה, API שונה |
| `PdfViewer.file()` | `SfPdfViewer.file()` | שם שונה |
| `PdfDocument.openFile()` | `PdfDocument.openFile()` | שם זהה, API שונה |
| `PdfOutlineNode` | `PdfBookmark` | שם שונה, מבנה דומה |
| `PdfTextSearcher` | `PdfTextSearchResult` | API שונה לחלוטין |
| `PdfPageText` | `PdfTextLine` | מבנה שונה |
| `PdfViewerParams` | פרמטרים ישירים ל-SfPdfViewer | אין wrapper class |
| `PdfDocumentRef` | `PdfDocument` | גישה ישירה למסמך |

## רכיבים וממשקים

### 1. PdfBookScreen (pdf_book_screen.dart)

#### שינויים נדרשים:

**Import:**
```dart
// הסר:
import 'package:pdfrx/pdfrx.dart';

// הוסף:
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
```

**Controller:**
```dart
// נוכחי:
late final PdfViewerController pdfController;
pdfController = PdfViewerController();

// חדש:
late final PdfViewerController pdfController;
pdfController = PdfViewerController();
// הערה: שם זהה אבל API שונה
```

**Viewer Widget:**
```dart
// נוכחי:
PdfViewer.file(
  widget.tab.book.path,
  initialPageNumber: widget.tab.pageNumber,
  passwordProvider: () => passwordDialog(context),
  controller: widget.tab.pdfViewerController,
  params: PdfViewerParams(
    backgroundColor: Theme.of(context).colorScheme.surface,
    maxScale: 10,
    horizontalCacheExtent: 5,
    verticalCacheExtent: 5,
    onInteractionStart: (_) { /* ... */ },
    viewerOverlayBuilder: (context, size, handleLinkTap) => [ /* ... */ ],
    loadingBannerBuilder: (context, bytesDownloaded, totalBytes) => /* ... */,
    linkWidgetBuilder: (context, link, size) => /* ... */,
    pagePaintCallbacks: [textSearcher.pageTextMatchPaintCallback],
    onDocumentChanged: (document) async { /* ... */ },
    onViewerReady: (document, controller) async { /* ... */ },
  ),
)

// חדש:
SfPdfViewer.file(
  File(widget.tab.book.path),
  key: _pdfViewerKey,
  controller: widget.tab.pdfViewerController,
  initialPageNumber: widget.tab.pageNumber,
  canShowScrollHead: true,
  canShowScrollStatus: true,
  canShowPaginationDialog: true,
  pageLayoutMode: PdfPageLayoutMode.continuous,
  scrollDirection: PdfScrollDirection.vertical,
  interactionMode: PdfInteractionMode.selection,
  onDocumentLoaded: (PdfDocumentLoadedDetails details) {
    // אתחול לאחר טעינה - גישה למסמך דרך details.document
    widget.tab.outline.value = details.document.bookmarks;
  },
  onDocumentLoadFailed: (PdfDocumentLoadFailedDetails details) {
    // טיפול בשגיאות טעינה, כולל סיסמה
    if (details.error.contains('password')) {
      _showPasswordDialog();
    }
  },
  onPageChanged: (PdfPageChangedDetails details) {
    widget.tab.pageNumber = details.newPageNumber;
  },
  onTextSelectionChanged: (PdfTextSelectionChangedDetails details) {
    // טיפול בבחירת טקסט
    _textSelectionDetails = details;
  },
  // הערה: אין תמיכה ישירה ב-linkWidgetBuilder, pagePaintCallbacks, viewerOverlayBuilder
  // צריך לממש אלו בצורה אחרת
)
```

**Navigation Methods:**
```dart
// נוכחי:
pdfController.goToPage(pageNumber: page);
pdfController.zoomUp();
pdfController.zoomDown();
pdfController.goToDest(link.dest);

// חדש:
pdfController.jumpToPage(page);
pdfController.zoomLevel = pdfController.zoomLevel * 1.25;
pdfController.zoomLevel = pdfController.zoomLevel * 0.8;
// אין מתודה ישירה goToDest - צריך לחלץ את מספר הדף מה-destination
if (bookmark.destination != null) {
  pdfController.jumpToPage(bookmark.destination!.page);
}
```

**Properties:**
```dart
// נוכחי:
pdfController.pageNumber
pdfController.pageCount
pdfController.isReady
pdfController.documentRef

// חדש:
pdfController.pageNumber
pdfController.pageCount
// אין isReady - צריך לעקוב דרך onDocumentLoaded callback
// אין documentRef - גישה למסמך רק דרך onDocumentLoaded callback
```

**Selection Methods:**
```dart
// נוכחי:
pdfController.clearSelection();

// חדש:
pdfController.clearSelection();
// זהה!
```

### 2. OutlineView (pdf_outlines_screen.dart)

#### שינויים נדרשים:

**Data Structure:**
```dart
// נוכחי:
List<PdfOutlineNode>? outline;
class PdfOutlineNode {
  String title;
  PdfDest? dest;
  List<PdfOutlineNode> children;
}

// חדש:
List<PdfBookmark>? bookmarks;
class PdfBookmark {
  String title;
  PdfDestination? destination;
  List<PdfBookmark> bookmarks; // שם שונה לילדים
}
```

**Loading Outline:**
```dart
// נוכחי:
final outline = await PdfDocument.openFile(book.path)
    .then((doc) => doc.loadOutline());

// חדש:
final document = await PdfDocument.openFile(book.path);
final bookmarks = document.bookmarks;
```

**Navigation:**
```dart
// נוכחי:
if (node.dest != null) {
  controller.goTo(controller.calcMatrixFitWidthForPage(
    pageNumber: node.dest?.pageNumber ?? 1
  ));
}

// חדש:
if (bookmark.destination != null) {
  controller.jumpToPage(bookmark.destination!.page);
}
```

### 3. PdfBookSearchView (pdf_search_screen.dart)

#### שינויים נדרשים:

**Search Implementation:**
```dart
// נוכחי:
final textSearcher = PdfTextSearcher(pdfController);
textSearcher.startTextSearch(query, goToFirstMatch: false);
textSearcher.matches // List<PdfTextRangeWithFragments>
textSearcher.currentIndex
textSearcher.goToMatchOfIndex(index)

// חדש:
PdfTextSearchResult? searchResult;

Future<void> startSearch(String query) async {
  searchResult = await pdfController.searchText(query);
  if (searchResult != null && searchResult!.hasResult) {
    // עיבוד תוצאות
  }
}

// ניווט לתוצאה הבאה:
searchResult?.nextInstance();

// ניווט לתוצאה הקודמת:
searchResult?.previousInstance();

// קבלת מספר התוצאות:
searchResult?.totalInstanceCount
```

**Search Result Display:**
```dart
// נוכחי:
class SearchResultTile {
  final PdfTextRangeWithFragments match;
  // ...
}

// חדש:
// Syncfusion לא מספק גישה ישירה לטקסט התוצאות
// צריך לטעון את הטקסט של הדף ולחלץ את ההקשר ידנית
class SearchResultTile {
  final int pageNumber;
  final String searchText;
  // ...
}
```

**Page Text Loading:**
```dart
// נוכחי:
final pageText = await textSearcher.loadText(pageNumber: pageNumber);
final fullText = pageText.fullText;

// חדש:
final document = await PdfDocument.openFile(path);
final page = document.pages[pageNumber - 1];
final textExtractor = PdfTextExtractor(document);
final fullText = textExtractor.extractText(startPageIndex: pageNumber - 1, endPageIndex: pageNumber - 1);
```

### 4. ThumbnailsView (pdf_thumbnails_screen.dart)

#### שינויים נדרשים:

**Document Reference:**
```dart
// נוכחי:
final PdfDocumentRef? documentRef;
PdfDocumentViewBuilder(
  documentRef: documentRef!,
  builder: (context, document) => ...
)

// חדש:
final PdfDocument? document;
// אין צורך ב-builder נפרד, גישה ישירה למסמך
```

**Page View:**
```dart
// נוכחי:
PdfPageView(
  document: document,
  pageNumber: index + 1,
  alignment: Alignment.center,
)

// חדש:
// Syncfusion לא מספק widget מובנה ל-thumbnail
// צריך ליצור תמונה מהדף:
FutureBuilder<ui.Image>(
  future: _getPageImage(document, index + 1),
  builder: (context, snapshot) {
    if (snapshot.hasData) {
      return RawImage(image: snapshot.data);
    }
    return CircularProgressIndicator();
  },
)

Future<ui.Image> _getPageImage(PdfDocument document, int pageNumber) async {
  final page = document.pages[pageNumber - 1];
  final image = await page.toImage(width: 200);
  return image;
}
```

### 5. PageConverter (page_converter.dart)

#### שינויים נדרשים:

**Outline Loading:**
```dart
// נוכחי:
final outline = await PdfDocument.openFile(pdfBook.path)
    .then((doc) => doc.loadOutline());

// חדש:
final document = await PdfDocument.openFile(pdfBook.path);
final bookmarks = document.bookmarks;
```

**Anchor Collection:**
```dart
// נוכחי:
List<({int page, String ref})> _collectPdfAnchors(
  List<PdfOutlineNode> nodes,
  [String prefix = '']
) {
  for (final node in nodes) {
    final page = node.dest?.pageNumber;
    // ...
  }
}

// חדש:
List<({int page, String ref})> _collectPdfAnchors(
  List<PdfBookmark> bookmarks,
  [String prefix = '']
) {
  for (final bookmark in bookmarks) {
    final page = bookmark.destination?.page;
    // ...
  }
}
```

### 6. RefHelper (ref_helper.dart)

#### שינויים נדרשים:

**Outline Loading:**
```dart
// נוכחי:
final List<PdfOutlineNode> outlines = await PdfDocument.openFile(book.path)
    .then((value) => value.loadOutline());

// חדש:
final document = await PdfDocument.openFile(book.path);
final List<PdfBookmark> bookmarks = document.bookmarks;
```

**Ref Generation:**
```dart
// נוכחי:
Future<String> refFromPageNumber(
  int pageNumber,
  List<PdfOutlineNode>? outline,
  [String? bookTitle]
) async {
  // ...
  for (final entry in outline) {
    if (entry.dest?.pageNumber == null ||
        entry.dest!.pageNumber > pageNumber) {
      return;
    }
    // ...
  }
}

// חדש:
Future<String> refFromPageNumber(
  int pageNumber,
  List<PdfBookmark>? bookmarks,
  [String? bookTitle]
) async {
  // ...
  for (final bookmark in bookmarks) {
    if (bookmark.destination?.page == null ||
        bookmark.destination!.page > pageNumber) {
      return;
    }
    // ...
  }
}
```

### 7. IndexingRepository (indexing_repository.dart)

#### שינויים נדרשים:

**Document Opening:**
```dart
// נוכחי:
final document = await PdfDocument.openFile(book.path);
final pages = document.pages;
final outline = await document.loadOutline();

// חדש:
final document = await PdfDocument.openFile(book.path);
final pageCount = document.pages.count;
final bookmarks = document.bookmarks;
```

**Text Extraction:**
```dart
// נוכחי:
for (int i = 0; i < pages.length; i++) {
  final texts = (await pages[i].loadText()).fullText.split('\n');
  // ...
}

// חדש:
final textExtractor = PdfTextExtractor(document);
for (int i = 0; i < pageCount; i++) {
  final pageText = textExtractor.extractText(
    startPageIndex: i,
    endPageIndex: i
  );
  final texts = pageText.split('\n');
  // ...
}
```

### 8. DafYomiHelper (daf_yomi_helper.dart)

#### שינויים נדרשים:

**Outline Loading:**
```dart
// נוכחי:
Future<PdfOutlineNode?> getDafYomiOutline(PdfBook book, String daf) async {
  final outlines = await PdfDocument.openFile(book.path)
      .then((value) => value.loadOutline());
  return await findEntryInTree(
    Future.value(outlines),
    daf,
    (entry) => entry.title,
    (entry) => Future.value(entry.children),
  );
}

// חדש:
Future<PdfBookmark?> getDafYomiBookmark(PdfBook book, String daf) async {
  final document = await PdfDocument.openFile(book.path);
  final bookmarks = document.bookmarks;
  return await findEntryInTree(
    Future.value(bookmarks),
    daf,
    (entry) => entry.title,
    (entry) => Future.value(entry.bookmarks), // שם שונה
  );
}
```

**Page Navigation:**
```dart
// נוכחי:
final outline = await getDafYomiOutline(book, ref);
return outline?.dest?.pageNumber;

// חדש:
final bookmark = await getDafYomiBookmark(book, ref);
return bookmark?.destination?.page;
```

### 9. PrintingScreen (printing_screen.dart)

#### שינויים נדרשים:

**PDF Preview:**
```dart
// נוכחי:
PdfViewer.data(snapshot.data!, sourceName: 'printing')

// חדש:
SfPdfViewer.memory(
  snapshot.data!,
  canShowScrollHead: false,
  canShowScrollStatus: false,
)
```

### 10. PdfBookTab (pdf_tab.dart)

#### שינויים נדרשים:

**Properties:**
```dart
// נוכחי:
PdfViewerController pdfViewerController = PdfViewerController();
final outline = ValueNotifier<List<PdfOutlineNode>?>(null);
final documentRef = ValueNotifier<PdfDocumentRef?>(null);
List<PdfTextRangeWithFragments>? pdfSearchMatches;

// חדש:
PdfViewerController pdfViewerController = PdfViewerController();
final bookmarks = ValueNotifier<List<PdfBookmark>?>(null);
final document = ValueNotifier<PdfDocument?>(null);
PdfTextSearchResult? pdfSearchResult;
```

## מודלים של נתונים

### PdfBookmark vs PdfOutlineNode

```dart
// pdfrx:
class PdfOutlineNode {
  String title;
  PdfDest? dest;
  List<PdfOutlineNode> children;
}

class PdfDest {
  int? pageNumber;
  // ...
}

// Syncfusion:
class PdfBookmark {
  String title;
  PdfDestination? destination;
  List<PdfBookmark> bookmarks; // שם שונה!
}

class PdfDestination {
  int page;
  Offset location;
  double zoom;
}
```

### Search Results

```dart
// pdfrx:
class PdfTextSearcher {
  List<PdfTextRangeWithFragments> matches;
  int? currentIndex;
  void startTextSearch(String text, {bool goToFirstMatch});
  void goToMatchOfIndex(int index);
}

class PdfTextRangeWithFragments {
  int pageNumber;
  List<PdfTextFragment> fragments;
}

// Syncfusion:
class PdfTextSearchResult {
  int totalInstanceCount;
  int currentInstanceIndex;
  bool hasResult;
  void nextInstance();
  void previousInstance();
  void clear();
}
// הערה: Syncfusion לא מספק גישה לטקסט התוצאות!
```

## טיפול בשגיאות

### 1. שגיאות טעינת מסמך

```dart
// pdfrx:
try {
  final doc = await PdfDocument.openFile(path);
} catch (e) {
  // טיפול בשגיאה
}

// Syncfusion:
SfPdfViewer.file(
  File(path),
  onDocumentLoadFailed: (PdfDocumentLoadFailedDetails details) {
    // טיפול בשגיאה
    print('Failed to load: ${details.error}');
  },
)
```

### 2. שגיאות סיסמה

```dart
// pdfrx:
PdfViewer.file(
  path,
  passwordProvider: () async {
    return await passwordDialog(context);
  },
)

// Syncfusion:
// צריך לטפל בזה דרך onDocumentLoadFailed
// ולנסות שוב עם סיסמה
```

### 3. שגיאות חיפוש

```dart
// pdfrx:
textSearcher.addListener(() {
  if (textSearcher.matches.isEmpty) {
    // אין תוצאות
  }
});

// Syncfusion:
final result = await controller.searchText(query);
if (result == null || !result.hasResult) {
  // אין תוצאות
}
```

## אסטרטגיית בדיקות

### 1. בדיקות יחידה (Unit Tests)

- בדיקת המרת דפים (page_converter.dart)
- בדיקת יצירת refs (ref_helper.dart)
- בדיקת חיפוש בתוכן עניינים (daf_yomi_helper.dart)

### 2. בדיקות אינטגרציה

- בדיקת טעינת PDF ותצוגה
- בדיקת ניווט בתוכן עניינים
- בדיקת חיפוש טקסט
- בדיקת המרה בין PDF לטקסט
- בדיקת אינדוקס ספרים

### 3. בדיקות ידניות

- פתיחת ספרים שונים (עם ובלי סיסמה)
- ניווט בין דפים
- חיפוש טקסט
- שימוש בתוכן עניינים
- שימוש ב-thumbnails
- מעבר בין גרסאות PDF וטקסט
- הדפסה ושמירה
- מצב כהה
- דף יומי

## אתגרים ופתרונות

**הערה:** לאחר בדיקת הקוד הקיים, התברר שהאפליקציה לא משתמשת ב-viewerOverlayBuilder, linkWidgetBuilder, pagePaintCallbacks, או PdfDocumentRef. זה מפשט משמעותית את המעבר.

### אתגר 1: API שונה לחיפוש טקסט

**המצב:**
- pdfrx: `PdfTextSearcher` עם גישה ישירה לרשימת matches וטקסט
- Syncfusion: `PdfTextSearchResult` עם ניווט בין תוצאות אבל ללא גישה לטקסט

**פתרון:** 
- נשתמש ב-`controller.searchText(query)` לביצוע חיפוש
- נשתמש ב-`PdfTextExtractor` לחילוץ טקסט הדף להצגת הקשר
- נשתמש ב-`nextInstance()/previousInstance()` לניווט
- Syncfusion מספק highlighting אוטומטי של תוצאות

### אתגר 2: Syncfusion לא מספק widget מובנה ל-thumbnails

**פתרון:**
- נשתמש ב-`page.toImage()` ליצירת תמונה של הדף (אם נתמך)
- נציג את התמונה ב-`RawImage` או `Image.memory` widget
- נשמור cache של תמונות שכבר נוצרו
- נטען thumbnails באופן lazy (רק כשנראים)

### אתגר 3: API שונה לניהול זום

**פתרון:**
- נשתמש ב-`zoomLevel` property במקום `zoomUp()/zoomDown()`
- נכפיל/נחלק ב-1.25 לשינוי הזום
- נוודא שהזום נשאר בטווח המותר (1.0 - 10.0)

### אתגר 4: שינוי שם children ל-bookmarks

**פתרון:**
- נעדכן את כל הקוד הרקורסיבי
- נשנה `node.children` ל-`bookmark.bookmarks`
- נוודא שכל הגישות לילדים משתמשות בשם החדש

### אתגר 5: טיפול בסיסמאות

**פתרון:**
- נשתמש ב-`onDocumentLoadFailed` callback
- נבדוק אם השגיאה מכילה 'password'
- נציג דיאלוג ונטען מחדש עם הסיסמה

### אתגר 6: גישה למסמך

**פתרון:**
- נשמור reference ל-`PdfDocument` שמתקבל ב-`onDocumentLoaded`
- נשתמש בו לגישה ל-bookmarks, pages, וכו'
- נעדכן את `PdfBookTab` לשמור את המסמך

## ביצועים

### אופטימיזציות:

1. **Cache של Outlines/Bookmarks:**
   - נשמור את תוכן העניינים ב-ValueNotifier
   - נטען רק פעם אחת בפתיחת המסמך

2. **Cache של Page Maps:**
   - נשמור את מפות ההמרה PDF<->טקסט
   - נשתמש במפה קיימת אם הספר כבר נפתח

3. **Lazy Loading של Thumbnails:**
   - ניצור thumbnails רק כשהם נראים
   - נשמור cache של thumbnails שכבר נוצרו

4. **Debouncing של חיפוש:**
   - נמתין 300ms לפני ביצוע חיפוש
   - נבטל חיפושים קודמים שעדיין רצים

## תאימות לאחור

### שמירת API דומה:

1. **PdfViewerController:**
   - נשמור על שם זהה
   - ניצור wrapper methods לפונקציות שהשתנו

2. **PdfBookTab:**
   - נשמור על מבנה JSON זהה
   - נמיר בין outline ל-bookmarks בסריאליזציה

3. **Callbacks:**
   - נשמור על signatures דומים
   - נמיר פרמטרים בין הספריות

## סיכום שינויים נדרשים

### קבצים שיש לעדכן:

1. ✅ `pubspec.yaml` - החלפת תלות
2. ✅ `lib/pdf_book/pdf_book_screen.dart` - מסך ראשי
3. ✅ `lib/pdf_book/pdf_outlines_screen.dart` - תוכן עניינים
4. ✅ `lib/pdf_book/pdf_search_screen.dart` - חיפוש
5. ✅ `lib/pdf_book/pdf_thumbnails_screen.dart` - thumbnails
6. ✅ `lib/pdf_book/pdf_page_number_dispaly.dart` - תצוגת מספר דף
7. ✅ `lib/tabs/models/pdf_tab.dart` - מודל טאב
8. ✅ `lib/utils/page_converter.dart` - המרת דפים
9. ✅ `lib/utils/ref_helper.dart` - עזרי הפניות
10. ✅ `lib/printing/printing_screen.dart` - הדפסה
11. ✅ `lib/indexing/repository/indexing_repository.dart` - אינדוקס
12. ✅ `lib/daf_yomi/daf_yomi_helper.dart` - דף יומי

### שינויים עיקריים:

- **Import statements:** `pdfrx/pdfrx.dart` → `syncfusion_flutter_pdfviewer/pdfviewer.dart` + `syncfusion_flutter_pdf/pdf.dart`
- **Viewer widget:** `PdfViewer.file()` → `SfPdfViewer.file(File(path))`
- **Outline:** `PdfOutlineNode` → `PdfBookmark`, `children` → `bookmarks`, `dest` → `destination`
- **Search:** `PdfTextSearcher` → `PdfTextSearchResult` (API שונה לחלוטין)
- **Navigation:** `goToPage(pageNumber: x)` → `jumpToPage(x)`, `goToDest()` → `jumpToPage(destination.page)`
- **Zoom:** `zoomUp()/zoomDown()` → `zoomLevel` property
- **Document:** גישה דרך `onDocumentLoaded` callback
- **Text extraction:** `loadText()` → `PdfTextExtractor.extractText()`
- **Page number:** `dest.pageNumber` → `destination.page`

### תכונות שלא נפגעות:

✅ כל הפונקציונליות הקיימת נתמכת ב-Syncfusion
✅ אין שימוש בתכונות מתקדמות של pdfrx שאין להן תמיכה
✅ המעבר יהיה חלק יחסית
