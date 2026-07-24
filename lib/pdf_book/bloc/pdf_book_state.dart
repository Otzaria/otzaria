import 'package:equatable/equatable.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/pdf_headings.dart';
import 'package:otzaria/models/links.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/settings/services/per_book_settings_service.dart';

String _outlineNodeSignature(PdfOutlineNode n) =>
    '${n.title}|${n.dest?.pageNumber ?? -1}|[${n.children.map(_outlineNodeSignature).join(',')}]';

/// Base class for PDF book states
sealed class PdfBookState extends Equatable {
  const PdfBookState();

  @override
  List<Object?> get props => [];
}

/// Initial state before document is loaded
class PdfBookInitial extends PdfBookState {
  final PdfBook book;
  final int initialPageNumber;
  final String searchText;
  final Map<String, Map<String, bool>> searchOptions;
  final Map<int, List<String>> alternativeWords;
  final Map<String, String> spacingValues;
  final SearchMode searchMode;
  final int searchDistance;
  final PdfLayoutMode layoutMode;

  const PdfBookInitial({
    required this.book,
    required this.initialPageNumber,
    this.searchText = '',
    this.searchOptions = const {},
    this.alternativeWords = const {},
    this.spacingValues = const {},
    this.searchMode = SearchMode.exact,
    this.searchDistance = 0,
    this.layoutMode = PdfLayoutMode.regularView,
  });

  @override
  List<Object?> get props => [
    book.title,
    initialPageNumber,
    searchText,
    layoutMode,
  ];
}

/// Document is loading
class PdfBookLoading extends PdfBookState {
  final PdfBook book;
  final String searchText;
  final Map<String, Map<String, bool>> searchOptions;
  final Map<int, List<String>> alternativeWords;
  final Map<String, String> spacingValues;
  final SearchMode searchMode;
  final int searchDistance;
  final PdfLayoutMode layoutMode;

  const PdfBookLoading({
    required this.book,
    this.searchText = '',
    this.searchOptions = const {},
    this.alternativeWords = const {},
    this.spacingValues = const {},
    this.searchMode = SearchMode.exact,
    this.searchDistance = 0,
    this.layoutMode = PdfLayoutMode.regularView,
  });

  @override
  List<Object?> get props => [book.title];
}

/// Document failed to load
class PdfBookError extends PdfBookState {
  final PdfBook book;
  final String message;

  /// כשאמת — הבלוק מצפה שה-UI יריץ retry אוטומטי (ללא הצגת כפתור).
  final bool autoRetry;

  const PdfBookError({
    required this.book,
    required this.message,
    this.autoRetry = false,
  });

  @override
  List<Object?> get props => [book.title, message, autoRetry];
}

/// Document is loaded and ready
class PdfBookLoaded extends PdfBookState {
  // Book info
  final PdfBook book;
  final PdfDocumentRef? documentRef;
  final List<PdfOutlineNode>? outline;

  // Navigation
  final int currentPageNumber;
  final int totalPages;
  final String currentTitle;

  // Zoom
  final double zoom;
  final bool showZoomBar;
  final PdfLayoutMode layoutMode;

  // Panes
  final bool showLeftPane;
  final bool pinLeftPane;
  final double sidebarWidth;
  final bool showRightPane;
  final double rightPaneWidth;
  final int leftPaneTabIndex;
  final int rightPaneInitialTabIndex;

  // Search state
  final String searchText;
  final Map<String, Map<String, bool>> searchOptions;
  final Map<int, List<String>> alternativeWords;
  final Map<String, String> spacingValues;
  final SearchMode searchMode;
  final int searchDistance;
  final List<PdfPageTextRange>? searchMatches;
  final int? currentSearchMatchIndex;

  // Commentary/Links
  final PdfHeadings? pdfHeadings;
  final List<Link> links;
  final int? currentTextLineNumber;

  // UI state
  final bool isRightPaneHovering;
  final bool isLoading;
  final bool loadSucceeded;

  const PdfBookLoaded({
    required this.book,
    this.documentRef,
    this.outline,
    required this.currentPageNumber,
    this.totalPages = 1,
    this.currentTitle = '',
    this.zoom = 1.0,
    this.showZoomBar = false,
    this.layoutMode = PdfLayoutMode.regularView,
    this.showLeftPane = false,
    this.pinLeftPane = false,
    this.sidebarWidth = 300.0,
    this.showRightPane = false,
    this.rightPaneWidth = 300.0,
    this.leftPaneTabIndex = 0,
    this.rightPaneInitialTabIndex = 0,
    this.searchText = '',
    this.searchOptions = const {},
    this.alternativeWords = const {},
    this.spacingValues = const {},
    this.searchMode = SearchMode.exact,
    this.searchDistance = 0,
    this.searchMatches,
    this.currentSearchMatchIndex,
    this.pdfHeadings,
    this.links = const [],
    this.currentTextLineNumber,
    this.isRightPaneHovering = false,
    this.isLoading = true,
    this.loadSucceeded = true,
  });

  /// Create a copy with updated fields
  PdfBookLoaded copyWith({
    PdfBook? book,
    PdfDocumentRef? documentRef,
    List<PdfOutlineNode>? outline,
    int? currentPageNumber,
    int? totalPages,
    String? currentTitle,
    double? zoom,
    bool? showZoomBar,
    PdfLayoutMode? layoutMode,
    bool? showLeftPane,
    bool? pinLeftPane,
    double? sidebarWidth,
    bool? showRightPane,
    double? rightPaneWidth,
    int? leftPaneTabIndex,
    int? rightPaneInitialTabIndex,
    String? searchText,
    Map<String, Map<String, bool>>? searchOptions,
    Map<int, List<String>>? alternativeWords,
    Map<String, String>? spacingValues,
    SearchMode? searchMode,
    int? searchDistance,
    List<PdfPageTextRange>? searchMatches,
    int? currentSearchMatchIndex,
    PdfHeadings? pdfHeadings,
    List<Link>? links,
    int? currentTextLineNumber,
    bool? isRightPaneHovering,
    bool? isLoading,
    bool? loadSucceeded,
    // Special handling for nullable fields that need to be explicitly cleared
    bool clearDocumentRef = false,
    bool clearOutline = false,
    bool clearSearchMatches = false,
    bool clearCurrentSearchMatchIndex = false,
    bool clearPdfHeadings = false,
    bool clearCurrentTextLineNumber = false,
  }) {
    return PdfBookLoaded(
      book: book ?? this.book,
      documentRef: clearDocumentRef ? null : (documentRef ?? this.documentRef),
      outline: clearOutline ? null : (outline ?? this.outline),
      currentPageNumber: currentPageNumber ?? this.currentPageNumber,
      totalPages: totalPages ?? this.totalPages,
      currentTitle: currentTitle ?? this.currentTitle,
      zoom: zoom ?? this.zoom,
      showZoomBar: showZoomBar ?? this.showZoomBar,
      layoutMode: layoutMode ?? this.layoutMode,
      showLeftPane: showLeftPane ?? this.showLeftPane,
      pinLeftPane: pinLeftPane ?? this.pinLeftPane,
      sidebarWidth: sidebarWidth ?? this.sidebarWidth,
      showRightPane: showRightPane ?? this.showRightPane,
      rightPaneWidth: rightPaneWidth ?? this.rightPaneWidth,
      leftPaneTabIndex: leftPaneTabIndex ?? this.leftPaneTabIndex,
      rightPaneInitialTabIndex:
          rightPaneInitialTabIndex ?? this.rightPaneInitialTabIndex,
      searchText: searchText ?? this.searchText,
      searchOptions: searchOptions ?? this.searchOptions,
      alternativeWords: alternativeWords ?? this.alternativeWords,
      spacingValues: spacingValues ?? this.spacingValues,
      searchMode: searchMode ?? this.searchMode,
      searchDistance: searchDistance ?? this.searchDistance,
      searchMatches: clearSearchMatches
          ? null
          : (searchMatches ?? this.searchMatches),
      currentSearchMatchIndex: clearCurrentSearchMatchIndex
          ? null
          : (currentSearchMatchIndex ?? this.currentSearchMatchIndex),
      pdfHeadings: clearPdfHeadings ? null : (pdfHeadings ?? this.pdfHeadings),
      links: links ?? this.links,
      currentTextLineNumber: clearCurrentTextLineNumber
          ? null
          : (currentTextLineNumber ?? this.currentTextLineNumber),
      isRightPaneHovering: isRightPaneHovering ?? this.isRightPaneHovering,
      isLoading: isLoading ?? this.isLoading,
      loadSucceeded: loadSucceeded ?? this.loadSucceeded,
    );
  }

  @override
  List<Object?> get props => [
    book.title,
    currentPageNumber,
    currentTitle,
    zoom,
    showZoomBar,
    layoutMode,
    showLeftPane,
    pinLeftPane,
    sidebarWidth,
    showRightPane,
    rightPaneWidth,
    leftPaneTabIndex,
    rightPaneInitialTabIndex,
    searchText,
    searchMode,
    searchDistance,
    searchOptions,
    alternativeWords,
    spacingValues,
    searchMatches?.length,
    currentSearchMatchIndex,
    currentTextLineNumber,
    totalPages,
    isRightPaneHovering,
    isLoading,
    loadSucceeded,
    pdfHeadings,
    links
        .map(
          (l) =>
              '${l.index1}|${l.path2}|${l.index2}|${l.index2End}|${l.connectionType}|${l.heRef}|${l.start}|${l.end}|${l.targetCategoryId}|${l.targetFileType}',
        )
        .toList(growable: false),
    outline?.map(_outlineNodeSignature).toList(growable: false),
    documentRef,
  ];
}
