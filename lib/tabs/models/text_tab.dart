import 'dart:async';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/text_book_repository.dart';
// [EDITING DISABLED] import 'package:otzaria/text_book/editing/repository/local_overrides_repository.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter/foundation.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/utils/ui/reading_left_pane_policy.dart';

/// Represents a tab that contains a text book.
///
/// It contains the book itself and a TextBookBloc that manages all the state
/// and business logic for the text book viewing experience.
class TextBookTab extends OpenedTab {
  /// The text book.
  final TextBook book;

  /// The index of the scrollable list.
  int index;

  /// The initial search text for this tab.
  final String searchText;
  /// ╫ר╫º╫í╫ר ╫£╫פ╫ף╫ע╫⌐╫פ ╫ס╫£╫ס╫ף Γאפ ╫£╫נ ╫₧╫ñ╫ó╫ש╫£ ╫ק╫£╫ץ╫á╫ש╫¬ ╫ק╫ש╫ñ╫ץ╫⌐.
  final String highlightText;
  /// ╫⌐╫ץ╫¿╫פ ╫£╫פ╫ף╫ע╫⌐╫¬ ╫¿╫º╫ó ╫º╫ס╫ץ╫ó╫פ Γאפ ╫₧╫⌐╫₧╫⌐ ╫£-?mark deep link.
  final int? permanentHighlightLine;
  final Map<String, Map<String, bool>> searchOptions;
  final Map<int, List<String>> alternativeWords;
  final Map<String, String> spacingValues;
  final SearchMode searchMode;

  /// ╫¬╫¬-╫₧╫ק╫¿╫ץ╫צ╫¬ ╫£╫פ╫ף╫ע╫⌐╫פ ╫₧╫₧╫ץ╫º╫ף╫¬ **╫¿╫º** ╫ס╫í╫ó╫ש╫ú ╫⌐╫ª╫ץ╫ש╫ƒ. ╫á╫ר╫ó╫á╫¬ ╫₧╫º╫ש╫⌐╫ץ╫¿ ╫ó╫ץ╫₧╫º
  /// (`otzaria://open/book/<id>?index=<n>&highlight=<text>`) ╫ץ╫נ╫ש╫á╫פ ╫ñ╫ץ╫¬╫ק╫¬ ╫ק╫£╫ץ╫á╫ש╫¬
  /// ╫ק╫ש╫ñ╫ץ╫⌐. ╫נ╫¥ null Γאפ ╫נ╫ש╫ƒ ╫פ╫ף╫ע╫⌐╫פ ╫₧╫₧╫ץ╫º╫ף╫¬.
  final String? pinpointHighlight;

  /// ╫נ╫ש╫á╫ף╫º╫í ╫פ╫í╫ó╫ש╫ú ╫⌐╫ó╫£╫ש╫ץ ╫¬╫ק╫ץ╫£ ╫פ╫פ╫ף╫ע╫⌐╫פ ╫פ╫₧╫₧╫ץ╫º╫ף╫¬. ╫נ╫¥ null ╫ץ╫סΓאס[pinpointHighlight] ╫ש╫⌐
  /// ╫ר╫º╫í╫ר Γאפ ╫á╫ץ╫ñ╫£╫ש╫¥ ╫ק╫צ╫¿╫פ ╫£Γאס[index] (╫צ╫פ ╫פ╫₧╫í╫£╫ץ╫£ ╫⌐╫£ deep link, ╫⌐╫ס╫ץ ╫ñ╫ץ╫¬╫ק╫ש╫¥ ╫ס╫í╫ó╫ש╫ú
  /// ╫פ╫₧╫ץ╫ף╫ע╫⌐). ╫פ╫⌐╫ף╫פ ╫פ╫ץ╫ñ╫ת ╫₧╫⌐╫₧╫ó╫ץ╫¬╫ש ╫ס╫ó╫¬ ╫⌐╫ש╫¢╫ñ╫ץ╫£ ╫ר╫נ╫ס ╫נ╫ץ sideΓאסbyΓאסside, ╫⌐╫¥ ╫פΓאסindex
  /// ╫פ╫á╫ץ╫¢╫ק╫ש ╫¢╫ס╫¿ ╫פ╫⌐╫¬╫á╫פ ╫£╫ñ╫ש ╫פ╫ע╫£╫ש╫£╫פ ╫ץ╫נ╫á╫ק╫á╫ץ ╫¿╫ץ╫ª╫ש╫¥ ╫£╫⌐╫₧╫¿ ╫נ╫¬ ╫פ╫í╫ó╫ש╫ú ╫פ╫₧╫º╫ץ╫¿╫ש.
  final int? pinpointHighlightSectionIndex;

  /// The bloc that manages the text book state and logic.
  late final TextBookBloc bloc;

  final ItemScrollController scrollController = ItemScrollController();
  final ItemPositionsListener positionsListener =
      ItemPositionsListener.create();
  // ╫ס╫º╫¿╫ש╫¥ ╫á╫ץ╫í╫ñ╫ש╫¥ ╫ó╫ס╫ץ╫¿ ╫¬╫ª╫ץ╫ע╫פ ╫₧╫ñ╫ץ╫ª╫£╫¬ ╫נ╫ץ ╫¿╫⌐╫ש╫₧╫ץ╫¬ ╫₧╫º╫ס╫ש╫£╫ץ╫¬
  final ItemScrollController auxScrollController = ItemScrollController();
  final ItemPositionsListener auxPositionsListener =
      ItemPositionsListener.create();
  final ScrollOffsetController mainOffsetController = ScrollOffsetController();
  final ScrollOffsetController auxOffsetController = ScrollOffsetController();

  /// ╫פ╫¢╫ץ╫¬╫¿╫¬ ╫פ╫á╫ץ╫¢╫ק╫ש╫¬ ╫⌐╫£ ╫פ╫₧╫ש╫º╫ץ╫¥ ╫ס╫í╫ñ╫¿ (╫£╫₧╫⌐╫£ "╫ס╫¿╫נ╫⌐╫ש╫¬ ╫ñ╫¿╫º ╫ף")
  final currentTitle = ValueNotifier<String>("");

  /// counter ╫⌐╫₧╫¬╫ע╫£╫ע╫£ ╫ó╫¥ ╫¢╫£ ╫ס╫º╫⌐╫פ ╫£╫ר╫ץ╫ע╫£ ╫ק╫£╫ץ╫á╫ש╫¬ ╫פ╫₧╫ñ╫¿╫⌐╫ש╫¥ ╫₧╫º╫ש╫ª╫ץ╫¿ ╫₧╫º╫£╫ף╫¬ ╫ע╫£╫ץ╫ס╫£╫ש.
  /// ╫פ╫₧╫נ╫צ╫ש╫ƒ ╫פ╫ץ╫נ [SplitedViewScreen] ╫ס╫£╫ס╫ף; ╫¢╫£ ╫פ╫ע╫ף╫£╫פ = toggle ╫ש╫ק╫ש╫ף.
  final ValueNotifier<int> toggleCommentatorsPaneNotifier =
      ValueNotifier<int>(0);

  /// counter ╫⌐╫₧╫¬╫ע╫£╫ע╫£ ╫¢╫⌐╫ש╫⌐ ╫£╫ñ╫¬╫ץ╫ק ╫נ╫¬ ╫ñ╫נ╫á╫£ ╫פ╫פ╫ó╫¿╫ץ╫¬ ╫פ╫נ╫ש╫⌐╫ש╫ץ╫¬.
  /// ╫פ╫₧╫נ╫צ╫ש╫ƒ ╫פ╫ץ╫נ [SplitedViewScreen] ╫ס╫£╫ס╫ף; ╫¢╫£ ╫פ╫ע╫ף╫£╫פ = ╫ñ╫¬╫ק ╫ó╫£ ╫ר╫נ╫ס ╫פ╫ó╫¿╫ץ╫¬.
  final ValueNotifier<int> openNotesTabNotifier = ValueNotifier<int>(0);

  List<String>? commentators;
  bool _lastSplitView = false;
  bool _lastShowPageShapeView = false;

  // StreamSubscription ╫£╫á╫ש╫פ╫ץ╫£ ╫פ-listener
  StreamSubscription<TextBookState>? _stateSubscription;

  /// Creates a new instance of [TextBookTab].
  ///
  /// The [index] parameter represents the initial index of the item in the scrollable list,
  /// and the [book] parameter represents the text book.
  /// The [searchText] parameter represents the initial search text,
  /// and the [commentators] parameter represents the list of commentaries to show.
  TextBookTab({
    required this.book,
    required this.index,
    this.searchText = '',
    this.highlightText = '',
    this.permanentHighlightLine,
    this.searchOptions = const {},
    this.alternativeWords = const {},
    this.spacingValues = const {},
    this.searchMode = SearchMode.exact,
    this.commentators,
    bool openLeftPane = false,
    bool? splitedView,
    bool? showPageShapeView,
    bool isPinned = false,
    String? dedupeKey,
    this.pinpointHighlight,
    this.pinpointHighlightSectionIndex,
    @visibleForTesting TextBookBloc? blocOverride,
  }) : super(book.title, isPinned: isPinned, dedupeKey: dedupeKey) {
    // ╫º╫ס╫ש╫ó╫¬ ╫ס╫¿╫ש╫¿╫¬ ╫פ╫₧╫ק╫ף╫£ ╫⌐╫£ splitedView ╫₧╫פ╫פ╫ע╫ף╫¿╫ץ╫¬ ╫נ╫¥ ╫£╫נ ╫í╫ץ╫ñ╫º
    final bool effectiveSplitedView =
        splitedView ?? (Settings.getValue<bool>('key-splited-view') ?? true);

    // ╫₧╫ª╫ס ╫ª╫ץ╫¿╫¬ ╫פ╫ף╫ú ╫פ╫ץ╫נ ╫ñ╫¿-╫í╫ñ╫¿ - ╫ס╫¿╫ש╫¿╫¬ ╫פ╫₧╫ק╫ף╫£ ╫פ╫ש╫נ false (╫¬╫ª╫ץ╫ע╫פ ╫¿╫ע╫ש╫£╫פ)
    // ╫¿╫º ╫נ╫¥ ╫פ╫í╫ñ╫¿ ╫¢╫ס╫¿ ╫פ╫ש╫פ ╫ñ╫¬╫ץ╫ק ╫ס╫₧╫ª╫ס ╫ª╫ץ╫¿╫¬ ╫פ╫ף╫ú, ╫פ╫ץ╫נ ╫ש╫ש╫⌐╫נ╫¿ ╫¢╫ת
    final bool effectiveShowPageShapeView = showPageShapeView ?? false;

    _lastSplitView = effectiveSplitedView;
    _lastShowPageShapeView = effectiveShowPageShapeView;

    // Initialize the bloc with initial state. ╫סΓאסproduction ╫¬╫₧╫ש╫ף ╫á╫ס╫á╫פ bloc ╫ק╫ף╫⌐;
    // ╫פΓאסblocOverride ╫º╫ש╫ש╫¥ ╫¿╫º ╫£╫ר╫í╫ר╫ש╫¥ ╫⌐╫ª╫¿╫ש╫¢╫ש╫¥ ╫£╫פ╫צ╫¿╫ש╫º bloc ╫ó╫¥ repository ╫₧╫צ╫ץ╫ש╫ú
    // ╫ץ╫£╫פ╫ס╫ש╫נ ╫נ╫ץ╫¬╫ץ ╫£ΓאסLoaded ╫ס╫£╫ש ╫¬╫⌐╫¬╫ש╫¬ ╫º╫ס╫ª╫ש╫¥ ╫נ╫₧╫ש╫¬╫ש╫¬.
    bloc = blocOverride ??
        TextBookBloc(
          repository: TextBookRepository(
            fileSystem: FileSystemData.instance,
          ),
          // [EDITING DISABLED] overridesRepository: LocalOverridesRepository(),
          initialState: TextBookInitial.named(
            book,
            index,
            openLeftPane,
            commentators ?? [],
            searchText: searchText,
            searchOptions: searchOptions,
            alternativeWords: alternativeWords,
            spacingValues: spacingValues,
            searchMode: searchMode,
            splitedView: effectiveSplitedView,
            showPageShapeView: effectiveShowPageShapeView,
            pinpointHighlightIndex:
                pinpointHighlight != null && pinpointHighlight!.isNotEmpty
                    ? (pinpointHighlightSectionIndex ?? index)
                    : null,
            pinpointHighlightText:
                pinpointHighlight != null && pinpointHighlight!.isNotEmpty
                    ? pinpointHighlight
                    : null,
          ),
          scrollController: scrollController,
          positionsListener: positionsListener,
          scrollOffsetController: mainOffsetController,
        );

    // ╫פ╫ץ╫í╫ñ╫¬ listener ╫£╫ó╫ף╫¢╫ץ╫ƒ ╫פ╫נ╫ש╫á╫ף╫º╫í ╫¢╫⌐╫פ-state ╫₧╫⌐╫¬╫á╫פ
    _stateSubscription = bloc.stream.listen((state) {
      if (state is TextBookLoaded && state.visibleIndices.isNotEmpty) {
        index = state.visibleIndices.first;
        _lastSplitView = state.showSplitView;
        _lastShowPageShapeView = state.showPageShapeView;
        // ╫ó╫ף╫¢╫ץ╫ƒ ╫פ╫¢╫ץ╫¬╫¿╫¬ ╫פ╫á╫ץ╫¢╫ק╫ש╫¬
        if (state.currentTitle != null && state.currentTitle!.isNotEmpty) {
          currentTitle.value = state.currentTitle!;
        }
      }
    });
  }

  /// Cleanup when the tab is disposed
  @override
  void dispose() {
    _stateSubscription?.cancel();
    currentTitle.dispose();
    toggleCommentatorsPaneNotifier.dispose();
    openNotesTabNotifier.dispose();
    bloc.close();
    super.dispose();
  }

  /// Creates a new instance of [TextBookTab] from a JSON map.
  ///
  /// The JSON map should have 'initalIndex', 'title', 'commentaries',
  /// and 'type' keys.
  factory TextBookTab.fromJson(Map<String, dynamic> json) {
    final bool shouldOpenLeftPane = resolveRestoredReadingLeftPaneState(json);

    // ╫⌐╫ק╫צ╫ץ╫¿ ╫₧╫ª╫ס ╫פ╫¬╫ª╫ץ╫ע╫פ ╫פ╫₧╫ñ╫ץ╫ª╫£╫¬ ╫₧╫פ-JSON
    final bool splitedView = json['splitedView'] ??
        (Settings.getValue<bool>('key-splited-view') ?? true);

    final TextBook restoredBook = json['book'] != null
        ? Book.fromJson(Map<String, dynamic>.from(json['book'])) as TextBook
        : TextBook(
            title: json['title'],
          );
    return TextBookTab(
      index: json['initalIndex'],
      book: restoredBook,
      commentators: List<String>.from(json['commentators']),
      splitedView: splitedView,
      showPageShapeView: json['showPageShapeView'] ?? false,
      openLeftPane: shouldOpenLeftPane,
      isPinned: json['isPinned'] ?? false,
    );
  }

  /// Converts the [TextBookTab] instance into a JSON map.
  ///
  /// The JSON map contains 'title', 'initalIndex', 'commentaries',
  /// and 'type' keys.
  @override
  Map<String, dynamic> toJson() {
    List<String> commentators = [];
    bool splitedView = _lastSplitView;
    bool showPageShapeView = _lastShowPageShapeView;
    int currentIndex = index; // ╫⌐╫₧╫ש╫¿╫¬ ╫פ╫נ╫ש╫á╫ף╫º╫í ╫פ╫á╫ץ╫¢╫ק╫ש ╫¢╫ס╫¿╫ש╫¿╫¬ ╫₧╫ק╫ף╫£

    if (bloc.state is TextBookLoaded) {
      final loadedState = bloc.state as TextBookLoaded;
      commentators = loadedState.activeCommentators;
      splitedView = loadedState.showSplitView;
      showPageShapeView = loadedState.showPageShapeView;
      // ╫ó╫ף╫¢╫ץ╫ƒ ╫פ╫נ╫ש╫á╫ף╫º╫í ╫₧╫פ-state ╫פ╫á╫ר╫ó╫ƒ - ╫¬╫₧╫ש╫ף ╫£╫ץ╫º╫ק╫ש╫¥ ╫נ╫¬ ╫פ╫נ╫ש╫á╫ף╫º╫í ╫פ╫נ╫ק╫¿╫ץ╫ƒ ╫⌐╫á╫¿╫נ╫פ
      if (loadedState.visibleIndices.isNotEmpty) {
        currentIndex = loadedState.visibleIndices.first;
        // ╫ó╫ף╫¢╫ץ╫ƒ ╫ע╫¥ ╫נ╫¬ ╫פ-index ╫⌐╫£ ╫פ╫ר╫נ╫ס ╫ó╫ª╫₧╫ץ ╫¢╫ף╫ש ╫⌐╫ש╫⌐╫₧╫¿
        index = currentIndex;
      }
    }

    return {
      'title': title,
      'book': book.toJson(),
      'initalIndex': currentIndex,
      'commentators': commentators,
      'splitedView': splitedView,
      'showPageShapeView': showPageShapeView,
      'showLeftPane': bloc.state is TextBookLoaded
          ? (bloc.state as TextBookLoaded).showLeftPane
          : false,
      'isPinned': isPinned,
      'type': 'TextBookTab'
    };
  }
}
