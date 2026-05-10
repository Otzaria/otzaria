import 'package:equatable/equatable.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/text_book/models/commentator_group.dart';
import 'package:otzaria/text_book/utils/reading_segments.dart';
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

  const TextBookInitial(
      super.book, super.index, super.showLeftPane, super.commentators,
      [this.searchText = '',
      this.searchOptions = const {},
      this.alternativeWords = const {},
      this.spacingValues = const {},
      this.searchMode = SearchMode.exact,
      this.searchDistance = 0,
      this.splitedView = true,
      this.showPageShapeView = false]);

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
  }) : splitedView = splitedView ?? false; // ברירת מחדל: מפרשים מתחת

  @override
  List<Object?> get props => [
        book.title,
        searchText,
        _searchOptionsSignature(searchOptions),
        _alternativeWordsSignature(alternativeWords),
        _spacingValuesSignature(spacingValues),
        searchMode,
        searchDistance,
        splitedView,
        showPageShapeView,
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
  final bool continuousReadingMode;
  final List<ReadingSegment> readingSegments;

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
  final ScrollOffsetController? scrollOffsetController;

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
    this.scrollOffsetController,
    this.currentTitle,
    this.selectedTextForNote,
    this.selectedTextStart,
    this.selectedTextEnd,
    this.highlightedLine,
    this.continuousReadingMode = false,
    this.readingSegments = const [],
    this.isEditorOpen = false,
    this.editorIndex,
    this.editorSectionId,
    this.editorText,
    this.hasDraft = false,
    this.hasLinksFile = false,
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
      scrollOffsetController: null,
      visibleIndices: [index],
      selectedTextForNote: null,
      selectedTextStart: null,
      selectedTextEnd: null,
      highlightedLine: null,
      continuousReadingMode: false,
      readingSegments: const [],
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
    ScrollOffsetController? scrollOffsetController,
    String? currentTitle,
    String? selectedTextForNote,
    int? selectedTextStart,
    int? selectedTextEnd,
    int? highlightedLine,
    bool clearHighlight = false,
    bool? continuousReadingMode,
    List<ReadingSegment>? readingSegments,
    bool? isEditorOpen,
    int? editorIndex,
    String? editorSectionId,
    String? editorText,
    bool? hasDraft,
    bool? hasLinksFile,
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
      scrollOffsetController:
          scrollOffsetController ?? this.scrollOffsetController,
      currentTitle: currentTitle ?? this.currentTitle,
      selectedTextForNote: selectedTextForNote ?? this.selectedTextForNote,
      selectedTextStart: selectedTextStart ?? this.selectedTextStart,
      selectedTextEnd: selectedTextEnd ?? this.selectedTextEnd,
      highlightedLine:
          clearHighlight ? null : (highlightedLine ?? this.highlightedLine),
      continuousReadingMode:
          continuousReadingMode ?? this.continuousReadingMode,
      readingSegments: readingSegments ?? this.readingSegments,
      isEditorOpen: isEditorOpen ?? this.isEditorOpen,
      editorIndex: editorIndex ?? this.editorIndex,
      editorSectionId: editorSectionId ?? this.editorSectionId,
      editorText: editorText ?? this.editorText,
      hasDraft: hasDraft ?? this.hasDraft,
      hasLinksFile: hasLinksFile ?? this.hasLinksFile,
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
        continuousReadingMode,
        readingSegments.length,
        isEditorOpen,
        editorIndex,
        editorSectionId,
        editorText,
        hasDraft,
        hasLinksFile,
      ];
}
