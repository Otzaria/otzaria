import 'package:flutter/material.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/pdf_headings.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/utils/text/text_manipulation.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/settings/services/per_book_settings_service.dart';
import 'package:otzaria/utils/ui/reading_left_pane_policy.dart';

/// Represents a tab with a PDF book.
///
/// The [PdfBookTab] class contains information about the PDF book,
/// such as its [book] and the current [pageNumber].
/// It also contains a [pdfViewerController] to control the viewer.
class PdfBookTab extends OpenedTab {
  /// The PDF book.
  final PdfBook book;

  /// The current page number.
  int pageNumber;

  /// The pdf viewer controller.
  PdfViewerController pdfViewerController = PdfViewerController();

  final outline = ValueNotifier<List<PdfOutlineNode>?>(null);

  final documentRef = ValueNotifier<PdfDocumentRef?>(null);

  final TextEditingController searchController = TextEditingController();

  String searchText;
  Map<String, Map<String, bool>> searchOptions;
  Map<int, List<String>> alternativeWords;
  Map<String, String> spacingValues;
  SearchMode searchMode;
  int searchDistance;

  List<PdfPageTextRange>? pdfSearchMatches;
  int? pdfSearchCurrentMatchIndex;

  final currentTitle = ValueNotifier<String>("");

  ///a flag that tells if the left pane should be shown
  late final ValueNotifier<bool> showLeftPane;

  ///a flag that tells if the left pane should be pinned on scrolling
  final pinLeftPane = ValueNotifier<bool>(false);

  /// counter שמתגלגל עם כל בקשה לטוגל חלונית הניווט (השמאלית) מקיצור מקלדת
  /// גלובלי. המאזין הוא [PdfBookScreen] בלבד; כל הגדלה = toggle יחיד.
  final ValueNotifier<int> toggleNavPaneNotifier = ValueNotifier<int>(0);

  /// counter שמתגלגל עם כל בקשה לטוגל חלונית המפרשים (הימנית) מקיצור מקלדת
  /// גלובלי. המאזין הוא [PdfBookScreen] בלבד; כל הגדלה = toggle יחיד.
  final ValueNotifier<int> toggleCommentatorsPaneNotifier = ValueNotifier<int>(
    0,
  );

  /// PDF headings mapping for commentaries and links
  PdfHeadings? pdfHeadings;

  /// Links for the current book
  List<Link> links = [];

  /// האם [links] מכיל את *כל* קישורי הספר. במסך ה-PDF נטען רק חלון קישורים
  /// סביב המיקום הנוכחי (false); כרטיסיית המפרשים העצמאית משדרגת לרשימה
  /// המלאה וקובעת true — ומאותו רגע טעינת החלון מפסיקה לגעת ברשימה.
  bool linksAreComplete = false;

  /// Active commentators to show
  Set<String> activeCommentators = <String>{};

  /// מצב טעינת הקישורים/המפרשים עבור ה-PDF המשותף.
  /// משמש גם את כרטסיית המפרשים העצמאית כדי להציג "טוען מפרשים..."
  /// בדיוק כמו הפאנל הראשי.
  final ValueNotifier<bool> linksLoadingNotifier = ValueNotifier<bool>(true);

  /// Current line number in text (based on PDF heading)
  int? currentTextLineNumber;

  /// End line number in text for the current page (start of next page - 1)
  int? currentTextLineNumberEnd;

  /// Saved zoom level for restoration after rebuild
  double? savedZoom;

  /// Saved layout mode for restoration after rebuild
  PdfLayoutMode? savedLayoutMode;

  /// כשפתיחה ישירה לעמוד גבוה — מבטל progressive loading כדי למנוע קפיצות
  /// ויזואליות שנובעות מעדכון ממדי עמודים שנטענים ברקע. תמורת כך הפתיחה
  /// איטית יותר. נכון רק לתרחישי פתיחה ישירה (דף יומי, מעבר מטקסט ל-PDF).
  final bool requiresStableLayout;

  /// Creates a new instance of [PdfBookTab].
  ///
  /// The [book] parameter represents the PDF book, and the [pageNumber]
  /// parameter represents the current page number.
  PdfBookTab({
    required this.book,
    required this.pageNumber,
    bool openLeftPane = false,
    this.searchText = '',
    this.searchOptions = const {},
    this.alternativeWords = const {},
    this.spacingValues = const {},
    this.searchMode = SearchMode.exact,
    this.searchDistance = 0,
    this.pdfSearchMatches,
    this.pdfSearchCurrentMatchIndex,
    bool isPinned = false,
    String? dedupeKey,
    this.requiresStableLayout = false,
  }) : super(book.title, isPinned: isPinned, dedupeKey: dedupeKey) {
    debugPrint(
      '🔧 PdfBookTab created: book=${book.title}, pageNumber=$pageNumber',
    );
    showLeftPane = ValueNotifier<bool>(openLeftPane);
    searchController.text = searchText;
    pinLeftPane.value = Settings.getValue<bool>('key-pin-sidebar') ?? false;
  }

  /// מתודה להוספת listener לעדכון מספר העמוד
  /// צריך לקרוא לזה אחרי שה-controller מוכן
  void setupPageTracking() {
    pdfViewerController.addListener(_updatePageNumber);
  }

  void _updatePageNumber() {
    if (pdfViewerController.isReady) {
      final newPage = pdfViewerController.pageNumber;
      if (newPage != null && newPage != pageNumber) {
        pageNumber = newPage;
      }
    }
  }

  /// Creates a new instance of [PdfBookTab] from a JSON map.
  ///
  /// The JSON map should have 'path' and 'pageNumber' keys.
  factory PdfBookTab.fromJson(Map<String, dynamic> json) {
    final bool shouldOpenLeftPane = resolveRestoredReadingLeftPaneState(json);

    final PdfBook restoredBook = json['book'] != null
        ? Book.fromJson(Map<String, dynamic>.from(json['book'])) as PdfBook
        : PdfBook(title: getTitleFromPath(json['path']), path: json['path']);

    final int pageNumber = json['pageNumber'] ?? 1;

    PdfLayoutMode? savedLayoutMode;
    if (json['savedLayoutMode'] != null) {
      savedLayoutMode = PdfLayoutMode.values.firstWhere(
        (e) => e.name == json['savedLayoutMode'],
        orElse: () => PdfLayoutMode.regularView,
      );
    }

    final tab = PdfBookTab(
      book: restoredBook,
      pageNumber: pageNumber,
      openLeftPane: shouldOpenLeftPane,
      isPinned: json['isPinned'] ?? false,
      requiresStableLayout: json['requiresStableLayout'] ?? false,
    );

    tab.savedLayoutMode = savedLayoutMode;

    return tab;
  }

  /// Cleanup when the tab is disposed
  @override
  void dispose() {
    pdfViewerController.removeListener(_updatePageNumber);
    searchController.dispose();
    outline.dispose();
    documentRef.dispose();
    currentTitle.dispose();
    linksLoadingNotifier.dispose();
    showLeftPane.dispose();
    pinLeftPane.dispose();
    toggleNavPaneNotifier.dispose();
    toggleCommentatorsPaneNotifier.dispose();
    super.dispose();
  }

  /// Converts the [PdfBookTab] instance into a JSON map.
  ///
  /// The JSON map contains 'path', 'pageNumber' and 'type' keys.
  @override
  Map<String, dynamic> toJson() {
    // שמירת מספר העמוד הנוכחי - אם ה-controller מוכן, נשתמש בו, אחרת נשתמש ב-pageNumber השמור
    int currentPage = pageNumber;
    try {
      if (pdfViewerController.isReady) {
        currentPage = pdfViewerController.pageNumber ?? pageNumber;
      }
    } catch (e) {
      // אם יש שגיאה בגישה ל-controller, נשתמש ב-pageNumber השמור
      currentPage = pageNumber;
    }

    return {
      'path': book.path,
      'book': book.toJson(),
      'pageNumber': currentPage,
      'showLeftPane': showLeftPane.value,
      'isPinned': isPinned,
      'type': 'PdfBookTab',
      'requiresStableLayout': requiresStableLayout,
      if (savedLayoutMode != null) 'savedLayoutMode': savedLayoutMode!.name,
    };
  }
}
