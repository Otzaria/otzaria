import 'package:equatable/equatable.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/text_book/models/commentator_group.dart';
import 'package:otzaria/search/models/search_configuration.dart';

String _searchOptionsSignature(Map<String, Map<String, bool>> options) {
  if (options.isEmpty) return '';

  final keys = options.keys.toList()..sort();
  return keys.map((key) {
    final inner = options[key]!;
    final innerKeys = inner.keys.toList()..sort();
    final innerSignature =
        innerKeys.map((innerKey) => '$innerKey=${inner[innerKey]}').join(',');
    return '$key:{$innerSignature}';
  }).join('|');
}

String _alternativeWordsSignature(Map<int, List<String>> words) {
  if (words.isEmpty) return '';

  final keys = words.keys.toList()..sort();
  return keys.map((key) => '$key:${words[key]!.join(',')}').join('|');
}

String _spacingValuesSignature(Map<String, String> values) {
  if (values.isEmpty) return '';

  final keys = values.keys.toList()..sort();
  return keys.map((key) => '$key=${values[key]}').join('|');
}

abstract class TextBookState extends Equatable {
  final TextBook book;
  final int index;
  final bool showLeftPane;
  final List<String> commentators;
  const TextBookState(
      this.book, this.index, this.showLeftPane, this.commentators);

  @override
  List<Object?> get props => [];
}

class TextBookInitial extends TextBookState {
  final String searchText;
  final Map<String, Map<String, bool>> searchOptions;
  final Map<int, List<String>> alternativeWords;
  final Map<String, String> spacingValues;
  final SearchMode searchMode;
  final int searchDistance;
  final bool splitedView;
  final bool showPageShapeView;
  /// טקסט להדגשה בלבד — לא מפעיל חלונית חיפוש.
  final String highlightText;
  /// שורה להדגשת רקע קבועה — משמש ל-?mark deep link.
  final int? permanentHighlightLine;

  /// אינדקס הסעיף שבו מותר לבצע הדגשה ממוקדת (deep link). null = אין הדגשה כזו.
  final int? pinpointHighlightIndex;

  /// הטקסט להדגשה ממוקדת בסעיף [pinpointHighlightIndex]. null = אין.
  final String? pinpointHighlightText;

  const TextBookInitial(
      super.book, super.index, super.showLeftPane, super.commentators,
      [this.searchText = '',
      this.searchOptions = const {},
      this.alternativeWords = const {},
      this.spacingValues = const {},
      this.searchMode = SearchMode.exact,
      this.searchDistance = 0,
      this.splitedView = true,
      this.showPageShapeView = false,
      this.highlightText = '',
      this.permanentHighlightLine,
      this.pinpointHighlightIndex,
      this.pinpointHighlightText]);

  // קונסטרקטור עם פרמטרים בשם
  const TextBookInitial.named(
    super.book,
    super.index,
    super.showLeftPane,
    super.commentators, {
    this.searchText = '',
    this.searchOptions = const {},
    this.alternativeWords = const {},
    this.spacingValues = const {},
    this.searchMode = SearchMode.exact,
    this.searchDistance = 0,
    bool? splitedView,
    this.showPageShapeView = false,
    this.highlightText = '',
    this.permanentHighlightLine,
    this.pinpointHighlightIndex,
    this.pinpointHighlightText,
  }) : splitedView = splitedView ?? false;

  @override
  List<Object?> get props => [
        book.title,
        searchText,
        highlightText,
        permanentHighlightLine,
        _searchOptionsSignature(searchOptions),
        _alternativeWordsSignature(alternativeWords),
        _spacingValuesSignature(spacingValues),
        searchMode,
        searchDistance,
        splitedView,
        showPageShapeView,
        pinpointHighlightIndex,
        pinpointHighlightText,
      ];
}

class TextBookLoading extends TextBookState {
  const TextBookLoading(
      super.book, super.index, super.showLeftPane, super.commentators);

  @override
  List<Object?> get props => [book.title];
}

class TextBookError extends TextBookState {
  final String message;

  const TextBookError(this.message, super.book, super.index, super.showLeftPane,
      super.commentators);

  @override
  List<Object?> get props => [message, book.title];
}

class TextBookLoaded extends TextBookState {
  final List<String> content;
  final double fontSize;
  final bool showSplitView;
  final bool showTzuratHadafView;
  final bool showPageShapeView;
  final List<String> activeCommentators;
  final List<CommentatorGroup> commentatorGroups;
  final List<String> availableCommentators;
  final List<Link> links;
  final List<Link> visibleLinks;
  final List<TocEntry> tableOfContents;
  final bool removeNikud;
  final bool removePunctuation;
  final bool isTanach;
  final List<int> visibleIndices;
  final int? selectedIndex;
  final bool pinLeftPane;
  final String searchText;
  final Map<String, Map<String, bool>> searchOptions;
  final Map<int, List<String>> alternativeWords;
  final Map<String, String> spacingValues;
  final SearchMode searchMode;
  final int searchDistance;
  final String? currentTitle;
  final String? selectedTextForNote;
  final int? selectedTextStart;
  final int? selectedTextEnd;
  final int? highlightedLine;

  /// אינדקס הסעיף שבו מבוצעת הדגשה ממוקדת (deep link). null = אין.
  final int? pinpointHighlightIndex;

  /// הטקסט להדגשה ממוקדת באותו סעיף. null = אין.
  final String? pinpointHighlightText;

  // Editor state
  final bool isEditorOpen;
  final int? editorIndex;
  final String? editorSectionId;
  final String? editorText;
  final bool hasDraft;
  final bool hasLinksFile;

  // Caches
  final Map<int, List<Link>> linksByLine;

  // Controllers
  final ItemScrollController scrollController;
  final ItemPositionsListener positionsListener;

  /// טקסט להדגשה בלבד — לא מפעיל חלונית חיפוש.
  final String highlightText;

  /// שורה להדגשת רקע קבועה (ללא timer ניקוי) — משמש ל-?mark deep link.
  /// מדגיש את רקע השורה בצבע secondaryContainer.
  final int? permanentHighlightLine;

  const TextBookLoaded({
    required TextBook book,
    required bool showLeftPane,
    required this.content,
    required this.fontSize,
    required this.showSplitView,
    this.showTzuratHadafView = false,
    this.showPageShapeView = false,
    required this.activeCommentators,
    required this.commentatorGroups,
    required this.availableCommentators,
    required this.links,
    this.visibleLinks = const [],
    required this.linksByLine,
    required this.tableOfContents,
    required this.removeNikud,
    this.removePunctuation = false,
    this.isTanach = false,
    required this.visibleIndices,
    this.selectedIndex,
    required this.pinLeftPane,
    required this.searchText,
    this.searchOptions = const {},
    this.alternativeWords = const {},
    this.spacingValues = const {},
    this.searchMode = SearchMode.exact,
    this.searchDistance = 0,
    required this.scrollController,
    required this.positionsListener,
    this.currentTitle,
    this.selectedTextForNote,
    this.selectedTextStart,
    this.selectedTextEnd,
    this.highlightedLine,
    this.pinpointHighlightIndex,
    this.pinpointHighlightText,
    this.isEditorOpen = false,
    this.editorIndex,
    this.editorSectionId,
    this.editorText,
    this.hasDraft = false,
    this.hasLinksFile = false,
    this.highlightText = '',
    this.permanentHighlightLine,
  }) : super(book, selectedIndex ?? 0, showLeftPane, activeCommentators);

  factory TextBookLoaded.initial({
    required TextBook book,
    required int index,
    required bool showLeftPane,
    required bool splitView,
    List<String>? commentators,
  }) {
    return TextBookLoaded(
      book: book,
      content: const [],
      fontSize: 25.0, // Default font size
      showLeftPane: showLeftPane,
      showSplitView: splitView,
      showTzuratHadafView: false,
      showPageShapeView: false,
      activeCommentators: commentators ?? const [],
      commentatorGroups: const [],
      availableCommentators: const [],
      links: const [],
      visibleLinks: const [],
      linksByLine: const {},
      tableOfContents: const [],
      removeNikud: false,
      pinLeftPane: Settings.getValue<bool>('key-pin-sidebar') ?? false,
      searchText: '',
      scrollController: ItemScrollController(),
      positionsListener: ItemPositionsListener.create(),
      visibleIndices: [index],
      selectedTextForNote: null,
      selectedTextStart: null,
      selectedTextEnd: null,
      highlightedLine: null,
      isEditorOpen: false,
      editorIndex: null,
      editorSectionId: null,
      editorText: null,
      hasDraft: false,
      hasLinksFile: false,
    );
  }

  TextBookLoaded copyWith({
    TextBook? book,
    List<String>? content,
    double? fontSize,
    bool? showLeftPane,
    bool? showSplitView,
    bool? showTzuratHadafView,
    bool? showPageShapeView,
    List<String>? activeCommentators,
    List<CommentatorGroup>? commentatorGroups,
    List<String>? availableCommentators,
    List<Link>? links,
    List<Link>? visibleLinks,
    Map<int, List<Link>>? linksByLine,
    List<TocEntry>? tableOfContents,
    bool? removeNikud,
    bool? removePunctuation,
    bool? isTanach,
    int? selectedIndex,
    bool clearSelectedIndex = false,
    List<int>? visibleIndices,
    bool? pinLeftPane,
    String? searchText,
    Map<String, Map<String, bool>>? searchOptions,
    Map<int, List<String>>? alternativeWords,
    Map<String, String>? spacingValues,
    SearchMode? searchMode,
    int? searchDistance,
    ItemScrollController? scrollController,
    ItemPositionsListener? positionsListener,
    String? currentTitle,
    String? selectedTextForNote,
    int? selectedTextStart,
    int? selectedTextEnd,
    int? highlightedLine,
    bool clearHighlight = false,
    int? pinpointHighlightIndex,
    String? pinpointHighlightText,
    bool clearPinpointHighlight = false,
    bool? isEditorOpen,
    int? editorIndex,
    String? editorSectionId,
    String? editorText,
    bool? hasDraft,
    bool? hasLinksFile,
    // לאיפוס highlightText ו-permanentHighlightLine יש להעביר ערכים מפורשים
    String? highlightText,
    int? permanentHighlightLine,
    bool clearPermanentHighlight = false,
  }) {
    return TextBookLoaded(
      book: book ?? this.book,
      content: content ?? this.content,
      fontSize: fontSize ?? this.fontSize,
      showLeftPane: showLeftPane ?? this.showLeftPane,
      showSplitView: showSplitView ?? this.showSplitView,
      showTzuratHadafView: showTzuratHadafView ?? this.showTzuratHadafView,
      showPageShapeView: showPageShapeView ?? this.showPageShapeView,
      activeCommentators: activeCommentators ?? this.activeCommentators,
      commentatorGroups: commentatorGroups ?? this.commentatorGroups,
      availableCommentators:
          availableCommentators ?? this.availableCommentators,
      links: links ?? this.links,
      visibleLinks: visibleLinks ?? this.visibleLinks,
      linksByLine: linksByLine ?? this.linksByLine,
      tableOfContents: tableOfContents ?? this.tableOfContents,
      removeNikud: removeNikud ?? this.removeNikud,
      removePunctuation: removePunctuation ?? this.removePunctuation,
      isTanach: isTanach ?? this.isTanach,
      visibleIndices: visibleIndices ?? this.visibleIndices,
      selectedIndex:
          clearSelectedIndex ? null : (selectedIndex ?? this.selectedIndex),
      pinLeftPane: pinLeftPane ?? this.pinLeftPane,
      searchText: searchText ?? this.searchText,
      searchOptions: searchOptions ?? this.searchOptions,
      alternativeWords: alternativeWords ?? this.alternativeWords,
      spacingValues: spacingValues ?? this.spacingValues,
      searchMode: searchMode ?? this.searchMode,
      searchDistance: searchDistance ?? this.searchDistance,
      scrollController: scrollController ?? this.scrollController,
      positionsListener: positionsListener ?? this.positionsListener,
      currentTitle: currentTitle ?? this.currentTitle,
      selectedTextForNote: selectedTextForNote ?? this.selectedTextForNote,
      selectedTextStart: selectedTextStart ?? this.selectedTextStart,
      selectedTextEnd: selectedTextEnd ?? this.selectedTextEnd,
      highlightedLine:
          clearHighlight ? null : (highlightedLine ?? this.highlightedLine),
      pinpointHighlightIndex: clearPinpointHighlight
          ? null
          : (pinpointHighlightIndex ?? this.pinpointHighlightIndex),
      pinpointHighlightText: clearPinpointHighlight
          ? null
          : (pinpointHighlightText ?? this.pinpointHighlightText),
      isEditorOpen: isEditorOpen ?? this.isEditorOpen,
      editorIndex: editorIndex ?? this.editorIndex,
      editorSectionId: editorSectionId ?? this.editorSectionId,
      editorText: editorText ?? this.editorText,
      hasDraft: hasDraft ?? this.hasDraft,
      hasLinksFile: hasLinksFile ?? this.hasLinksFile,
      highlightText: highlightText ?? this.highlightText,
      permanentHighlightLine: clearPermanentHighlight
          ? null
          : (permanentHighlightLine ?? this.permanentHighlightLine),
    );
  }

  @override
  List<Object?> get props => [
        book.title,
        content.length,
        fontSize,
        showLeftPane,
        showSplitView,
        showTzuratHadafView,
        showPageShapeView,
        activeCommentators.length,
        commentatorGroups,
        availableCommentators.length,
        links.length,
        visibleLinks.length,
        tableOfContents.length,
        removeNikud,
        removePunctuation,
        isTanach,
        visibleIndices,
        selectedIndex,
        pinLeftPane,
        searchText,
        _searchOptionsSignature(searchOptions),
        _alternativeWordsSignature(alternativeWords),
        _spacingValuesSignature(spacingValues),
        searchMode,
        searchDistance,
        currentTitle,
        selectedTextForNote,
        selectedTextStart,
        selectedTextEnd,
        highlightedLine,
        pinpointHighlightIndex,
        pinpointHighlightText,
        isEditorOpen,
        editorIndex,
        editorSectionId,
        editorText,
        hasDraft,
        hasLinksFile,
        highlightText,
        permanentHighlightLine,
      ];
}
