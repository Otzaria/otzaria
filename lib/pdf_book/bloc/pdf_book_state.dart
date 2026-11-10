import 'package:equatable/equatable.dart';
import 'package:otzaria/models/books.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/settings/services/per_book_settings_service.dart';

String _outlineNodeSignature(PdfOutlineNode n) =>
    '${n.title}|${n.dest?.pageNumber ?? -1}|[${n.children.map(_outlineNodeSignature).join(',')}]';

/// השוואת רשימה לפי תוכן, עם קיצור דרך לאותו מופע — copyWith מעביר את אותה
/// רשימה, ובלעדיו כל emit (גם פריים של זום) בנה חתימה לכל צומת.
final class _ContentKey<T> {
  const _ContentKey(this.items, this.signature);

  final List<T>? items;
  final String Function(T) signature;

  @override
  bool operator ==(Object other) {
    if (other is! _ContentKey<T>) return false;
    final a = items, b = other.items;
    if (identical(a, b)) return true;
    if (a == null || b == null || a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (signature(a[i]) != signature(b[i])) return false;
    }
    return true;
  }

  @override
  int get hashCode => items?.length ?? -1;
}

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
  final SearchMatchPolicy matchPolicy;
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
    this.matchPolicy = SearchMatchPolicy.standard,
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
  final SearchMatchPolicy matchPolicy;
  final PdfLayoutMode layoutMode;

  /// הפתיחה עדיין רצה אחרי ה-timeout הראשון; ה-UI מודיע שהטעינה נמשכת.
  final bool isSlow;

  const PdfBookLoading({
    required this.book,
    this.searchText = '',
    this.searchOptions = const {},
    this.alternativeWords = const {},
    this.spacingValues = const {},
    this.searchMode = SearchMode.exact,
    this.searchDistance = 0,
    this.matchPolicy = SearchMatchPolicy.standard,
    this.layoutMode = PdfLayoutMode.regularView,
    this.isSlow = false,
  });

  PdfBookLoading copyWith({bool? isSlow}) => PdfBookLoading(
    book: book,
    searchText: searchText,
    searchOptions: searchOptions,
    alternativeWords: alternativeWords,
    spacingValues: spacingValues,
    searchMode: searchMode,
    searchDistance: searchDistance,
    matchPolicy: matchPolicy,
    layoutMode: layoutMode,
    isSlow: isSlow ?? this.isSlow,
  );

  @override
  List<Object?> get props => [book.title, isSlow];
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

  /// עמודי היעד של חזרה ושל התקדמות בהיסטוריית הקפיצות.
  final ({int? back, int? forward}) locationHistory;
  bool get canReturnToLocation => locationHistory.back != null;

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

  // Search state
  final String searchText;
  final Map<String, Map<String, bool>> searchOptions;
  final Map<int, List<String>> alternativeWords;
  final Map<String, String> spacingValues;
  final SearchMode searchMode;
  final int searchDistance;
  final SearchMatchPolicy matchPolicy;

  // UI state
  final bool isLoading;
  final bool loadSucceeded;

  const PdfBookLoaded({
    required this.book,
    this.documentRef,
    this.outline,
    required this.currentPageNumber,
    this.totalPages = 1,
    this.locationHistory = (back: null, forward: null),
    this.zoom = 1.0,
    this.showZoomBar = false,
    this.layoutMode = PdfLayoutMode.regularView,
    this.showLeftPane = false,
    this.pinLeftPane = false,
    this.sidebarWidth = 300.0,
    this.showRightPane = false,
    this.rightPaneWidth = 300.0,
    this.searchText = '',
    this.searchOptions = const {},
    this.alternativeWords = const {},
    this.spacingValues = const {},
    this.searchMode = SearchMode.exact,
    this.searchDistance = 0,
    this.matchPolicy = SearchMatchPolicy.standard,
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
    ({int? back, int? forward})? locationHistory,
    double? zoom,
    bool? showZoomBar,
    PdfLayoutMode? layoutMode,
    bool? showLeftPane,
    bool? pinLeftPane,
    double? sidebarWidth,
    bool? showRightPane,
    double? rightPaneWidth,
    String? searchText,
    Map<String, Map<String, bool>>? searchOptions,
    Map<int, List<String>>? alternativeWords,
    Map<String, String>? spacingValues,
    SearchMode? searchMode,
    int? searchDistance,
    SearchMatchPolicy? matchPolicy,
    bool? isLoading,
    bool? loadSucceeded,
    // Special handling for nullable fields that need to be explicitly cleared
    bool clearDocumentRef = false,
    bool clearOutline = false,
  }) {
    return PdfBookLoaded(
      book: book ?? this.book,
      documentRef: clearDocumentRef ? null : (documentRef ?? this.documentRef),
      outline: clearOutline ? null : (outline ?? this.outline),
      currentPageNumber: currentPageNumber ?? this.currentPageNumber,
      totalPages: totalPages ?? this.totalPages,
      locationHistory: locationHistory ?? this.locationHistory,
      zoom: zoom ?? this.zoom,
      showZoomBar: showZoomBar ?? this.showZoomBar,
      layoutMode: layoutMode ?? this.layoutMode,
      showLeftPane: showLeftPane ?? this.showLeftPane,
      pinLeftPane: pinLeftPane ?? this.pinLeftPane,
      sidebarWidth: sidebarWidth ?? this.sidebarWidth,
      showRightPane: showRightPane ?? this.showRightPane,
      rightPaneWidth: rightPaneWidth ?? this.rightPaneWidth,
      searchText: searchText ?? this.searchText,
      searchOptions: searchOptions ?? this.searchOptions,
      alternativeWords: alternativeWords ?? this.alternativeWords,
      spacingValues: spacingValues ?? this.spacingValues,
      searchMode: searchMode ?? this.searchMode,
      searchDistance: searchDistance ?? this.searchDistance,
      matchPolicy: matchPolicy ?? this.matchPolicy,
      isLoading: isLoading ?? this.isLoading,
      loadSucceeded: loadSucceeded ?? this.loadSucceeded,
    );
  }

  @override
  List<Object?> get props => [
    book.title,
    currentPageNumber,
    locationHistory,
    zoom,
    showZoomBar,
    layoutMode,
    showLeftPane,
    pinLeftPane,
    sidebarWidth,
    showRightPane,
    rightPaneWidth,
    searchText,
    searchMode,
    searchDistance,
    matchPolicy,
    searchOptions,
    alternativeWords,
    spacingValues,
    totalPages,
    isLoading,
    loadSucceeded,
    _ContentKey<PdfOutlineNode>(outline, _outlineNodeSignature),
    documentRef,
  ];
}
