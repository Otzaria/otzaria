import 'package:equatable/equatable.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/pdf_headings.dart';
import 'package:otzaria/models/links.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:otzaria/search/models/search_configuration.dart';

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

  const PdfBookInitial({
    required this.book,
    required this.initialPageNumber,
    this.searchText = '',
    this.searchOptions = const {},
    this.alternativeWords = const {},
    this.spacingValues = const {},
    this.searchMode = SearchMode.exact,
  });

  @override
  List<Object?> get props => [
        book.title,
        initialPageNumber,
        searchText,
      ];
}

/// Document is loading
class PdfBookLoading extends PdfBookState {
  final PdfBook book;

  const PdfBookLoading({required this.book});

  @override
  List<Object?> get props => [book.title];
}

/// Document failed to load
class PdfBookError extends PdfBookState {
  final PdfBook book;
  final String message;

  const PdfBookError({required this.book, required this.message});

  @override
  List<Object?> get props => [book.title, message];
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
  final List<PdfPageTextRange>? searchMatches;
  final int? currentSearchMatchIndex;

  // Commentary/Links
  final PdfHeadings? pdfHeadings;
  final List<Link> links;
  final int? currentTextLineNumber;

  const PdfBookLoaded({
    required this.book,
    this.documentRef,
    this.outline,
    required this.currentPageNumber,
    this.totalPages = 1,
    this.currentTitle = '',
    this.zoom = 1.0,
    this.showZoomBar = false,
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
    this.searchMatches,
    this.currentSearchMatchIndex,
    this.pdfHeadings,
    this.links = const [],
    this.currentTextLineNumber,
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
    List<PdfPageTextRange>? searchMatches,
    int? currentSearchMatchIndex,
    PdfHeadings? pdfHeadings,
    List<Link>? links,
    int? currentTextLineNumber,
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
      searchMatches:
          clearSearchMatches ? null : (searchMatches ?? this.searchMatches),
      currentSearchMatchIndex: clearCurrentSearchMatchIndex
          ? null
          : (currentSearchMatchIndex ?? this.currentSearchMatchIndex),
      pdfHeadings: clearPdfHeadings ? null : (pdfHeadings ?? this.pdfHeadings),
      links: links ?? this.links,
      currentTextLineNumber: clearCurrentTextLineNumber
          ? null
          : (currentTextLineNumber ?? this.currentTextLineNumber),
    );
  }

  @override
  List<Object?> get props => [
        book.title,
        currentPageNumber,
        currentTitle,
        zoom,
        showZoomBar,
        showLeftPane,
        pinLeftPane,
        sidebarWidth,
        showRightPane,
        rightPaneWidth,
        leftPaneTabIndex,
        rightPaneInitialTabIndex,
        searchText,
        searchMatches?.length,
        currentSearchMatchIndex,
        currentTextLineNumber,
        totalPages,
      ];
}
