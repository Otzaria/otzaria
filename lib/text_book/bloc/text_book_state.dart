import 'package:equatable/equatable.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/text_book/models/commentator_group.dart';

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

  const TextBookInitial(
      super.book, super.index, super.showLeftPane, super.commentators,
      [this.searchText = '']);

  @override
  List<Object?> get props => [book.title, searchText];
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
  final List<String> activeCommentators;
  final List<CommentatorGroup> commentatorGroups;
  final List<String> availableCommentators;
  final List<Link> links;
  final List<Link> visibleLinks;
  final List<TocEntry> tableOfContents;
  final bool removeNikud;
  final List<int> visibleIndices;
  final int? selectedIndex;
  final bool pinLeftPane;
  final String searchText;
  final String? currentTitle;
  final String? selectedTextForNote;
  final int? selectedTextStart;
  final int? selectedTextEnd;

  // Editor state
  final bool isEditorOpen;
  final int? editorIndex;
  final String? editorSectionId;
  final String? editorText;
  final bool hasDraft;
  final bool hasLinksFile;

  // Controllers
  final ItemScrollController scrollController;
  final ItemPositionsListener positionsListener;

  const TextBookLoaded({
    required TextBook book,
    required bool showLeftPane,
    required this.content,
    required this.fontSize,
    required this.showSplitView,
    required this.activeCommentators,
    required this.commentatorGroups,
    required this.availableCommentators,
    required this.links,
    this.visibleLinks = const [],
    required this.tableOfContents,
    required this.removeNikud,
    required this.visibleIndices,
    this.selectedIndex,
    required this.pinLeftPane,
    required this.searchText,
    required this.scrollController,
    required this.positionsListener,
    this.currentTitle,
    this.selectedTextForNote,
    this.selectedTextStart,
    this.selectedTextEnd,
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
      activeCommentators: commentators ?? const [],
      commentatorGroups: const [],
      availableCommentators: const [],
      links: const [],
      visibleLinks: const [],
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
    List<String>? activeCommentators,
    List<CommentatorGroup>? commentatorGroups,
    List<String>? availableCommentators,
    List<Link>? links,
    List<Link>? visibleLinks,
    List<TocEntry>? tableOfContents,
    bool? removeNikud,
    int? selectedIndex,
    List<int>? visibleIndices,
    bool? pinLeftPane,
    String? searchText,
    ItemScrollController? scrollController,
    ItemPositionsListener? positionsListener,
    String? currentTitle,
    String? selectedTextForNote,
    int? selectedTextStart,
    int? selectedTextEnd,
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
      activeCommentators: activeCommentators ?? this.activeCommentators,
      commentatorGroups: commentatorGroups ?? this.commentatorGroups,
      availableCommentators:
          availableCommentators ?? this.availableCommentators,
      links: links ?? this.links,
      visibleLinks: visibleLinks ?? this.visibleLinks,
      tableOfContents: tableOfContents ?? this.tableOfContents,
      removeNikud: removeNikud ?? this.removeNikud,
      visibleIndices: visibleIndices ?? this.visibleIndices,
      selectedIndex: selectedIndex,
      pinLeftPane: pinLeftPane ?? this.pinLeftPane,
      searchText: searchText ?? this.searchText,
      scrollController: scrollController ?? this.scrollController,
      positionsListener: positionsListener ?? this.positionsListener,
      currentTitle: currentTitle ?? this.currentTitle,
      selectedTextForNote: selectedTextForNote ?? this.selectedTextForNote,
      selectedTextStart: selectedTextStart ?? this.selectedTextStart,
      selectedTextEnd: selectedTextEnd ?? this.selectedTextEnd,
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
        activeCommentators.length,
        commentatorGroups,
        availableCommentators.length,
        links.length,
        visibleLinks.length,
        tableOfContents.length,
        removeNikud,
        visibleIndices,
        selectedIndex,
        pinLeftPane,
        searchText,
        currentTitle,
        selectedTextForNote,
        selectedTextStart,
        selectedTextEnd,
        isEditorOpen,
        editorIndex,
        editorSectionId,
        editorText,
        hasDraft,
        hasLinksFile,
      ];
}
