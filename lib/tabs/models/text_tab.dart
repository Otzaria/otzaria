import 'dart:async';
import 'package:flutter/material.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/bloc/text_book_event.dart';
import 'package:otzaria/text_book/text_book_repository.dart';
import 'package:otzaria/text_book/editing/repository/local_overrides_repository.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/utils/text_manipulation.dart' as utils;

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

  /// Text to highlight when the tab is opened
  final String highlightText;

  /// Whether to highlight the full section (for text=true parameter)
  final bool fullSectionHighlight;

  /// The original index where highlighting should occur (for section-specific highlighting)
  final int? highlightIndex;

  final Map<String, Map<String, bool>> searchOptions;
  final Map<int, List<String>> alternativeWords;
  final Map<String, String> spacingValues;
  final SearchMode searchMode;

  /// The bloc that manages the text book state and logic.
  late final TextBookBloc bloc;

  final ItemScrollController scrollController = ItemScrollController();
  final ItemPositionsListener positionsListener =
      ItemPositionsListener.create();
  // בקרים נוספים עבור תצוגה מפוצלת או רשימות מקבילות
  final ItemScrollController auxScrollController = ItemScrollController();
  final ItemPositionsListener auxPositionsListener =
      ItemPositionsListener.create();
  final ScrollOffsetController mainOffsetController = ScrollOffsetController();
  final ScrollOffsetController auxOffsetController = ScrollOffsetController();

  List<String>? commentators;

  // StreamSubscription לניהול ה-listener
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
    this.fullSectionHighlight = false,
    this.searchOptions = const {},
    this.alternativeWords = const {},
    this.spacingValues = const {},
    this.searchMode = SearchMode.exact,
    this.commentators,
    bool openLeftPane = false,
    bool? splitedView,
    bool? showPageShapeView,
    bool isPinned = false,
  })  : highlightIndex =
            highlightText.isNotEmpty || fullSectionHighlight ? index : null,
        super(book.title, isPinned: isPinned) {
    // קביעת ברירת המחדל של splitedView מההגדרות אם לא סופק
    final bool effectiveSplitedView =
        splitedView ?? (Settings.getValue<bool>('key-splited-view') ?? false);

    // מצב צורת הדף הוא פר-ספר - ברירת המחדל היא false (תצוגה רגילה)
    // רק אם הספר כבר היה פתוח במצב צורת הדף, הוא יישאר כך
    final bool effectiveShowPageShapeView = showPageShapeView ?? false;

    // Initialize the bloc with initial state
    bloc = TextBookBloc(
      repository: TextBookRepository(
        fileSystem: FileSystemData.instance,
      ),
      overridesRepository: LocalOverridesRepository(),
      initialState: TextBookInitial.named(
        book,
        index,
        openLeftPane,
        commentators ?? [],
        searchText: searchText, // לא להעביר את highlightText כ-searchText!
        searchOptions: searchOptions,
        alternativeWords: alternativeWords,
        spacingValues: spacingValues,
        searchMode: searchMode,
        splitedView: effectiveSplitedView,
        showPageShapeView: effectiveShowPageShapeView,
      ),
      scrollController: scrollController,
      positionsListener: positionsListener,
    );

    // Start loading content
    bloc.add(LoadContent(
      fontSize: 25.0,
      showSplitView: effectiveSplitedView,
      removeNikud: false,
      loadCommentators: true,
    ));

    // Set up section-specific highlighting if needed
    if (highlightText.isNotEmpty || fullSectionHighlight) {
      if (fullSectionHighlight) {
        // Full section highlighting - no need to decode text
        WidgetsBinding.instance.addPostFrameCallback((_) {
          bloc.add(
              UpdateSectionSpecificHighlight('', index, fullSection: true));
        });

        // Also listen for when the bloc is loaded to ensure the event is processed
        bool eventSent = false;
        _stateSubscription = bloc.stream.listen((state) {
          if (state is TextBookLoaded && !eventSent) {
            // Send the event again to make sure it's processed after content is loaded
            // Add a small delay to ensure the UI is ready
            Future.delayed(const Duration(milliseconds: 100), () {
              if (!eventSent) {
                bloc.add(UpdateSectionSpecificHighlight('', index,
                    fullSection: true));
                eventSent = true;
              }
            });

            // Cancel the subscription after sending the event once
            _stateSubscription?.cancel();
            _stateSubscription = null;
          }
        });
      } else {
        // Regular text highlighting
        // Decode URL encoding including %20 for spaces before processing
        String decodedHighlightText = highlightText;
        try {
          decodedHighlightText = Uri.decodeComponent(highlightText);
        } catch (e) {
          // If decoding fails, try basic replacements
          decodedHighlightText =
              highlightText.replaceAll('%20', ' ').replaceAll('+', ' ');
        }

        // Additional cleanup
        decodedHighlightText = decodedHighlightText.trim();

        // Send the event immediately after bloc initialization
        WidgetsBinding.instance.addPostFrameCallback((_) {
          bloc.add(UpdateSectionSpecificHighlight(decodedHighlightText, index));
        });

        // Also listen for when the bloc is loaded to ensure the event is processed
        bool eventSent = false;
        _stateSubscription = bloc.stream.listen((state) {
          if (state is TextBookLoaded &&
              decodedHighlightText.isNotEmpty &&
              !eventSent) {
            // First, try to highlight in the original index without searching elsewhere
            bloc.add(
                UpdateSectionSpecificHighlight(decodedHighlightText, index));

            // Also try to find the text in nearby sections as backup
            final correctIndex = utils.findTextInNearbyContent(
                state.content, decodedHighlightText, index);

            if (correctIndex != null && correctIndex != index) {
              // Text found in nearby section - update both index and highlight
              // TODO: Consider refactoring to update tab through TabsBloc instead of direct mutation
              // This would maintain unidirectional data flow and make state management clearer
              index = correctIndex; // Update the tab's index
              bloc.add(UpdateSectionSpecificHighlight(
                  decodedHighlightText, correctIndex));

              // Scroll to the correct section
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (scrollController.isAttached) {
                  scrollController.scrollTo(
                    index: correctIndex,
                    duration: const Duration(milliseconds: 300),
                  );
                }
              });
            }
            // Note: We removed the error case - let the highlighting attempt work even if not found in nearby sections

            eventSent = true;

            // Cancel the subscription after sending the event once
            _stateSubscription?.cancel();
            _stateSubscription = null;
          }
        });
      }
    }
  }

  /// Cleanup when the tab is disposed
  @override
  void dispose() {
    _stateSubscription?.cancel();
    bloc.close();
    super.dispose();
  }

  /// Creates a new instance of [TextBookTab] from a JSON map.
  ///
  /// The JSON map should have 'initalIndex', 'title', 'commentaries',
  /// and 'type' keys.
  factory TextBookTab.fromJson(Map<String, dynamic> json) {
    // במצב side-by-side, חלונית הצד תמיד סגורה
    // אחרת, לפי ההגדרות
    final bool shouldOpenLeftPane =
        (Settings.getValue<bool>('key-pin-sidebar') ?? false) ||
            (Settings.getValue<bool>('key-default-sidebar-open') ?? false);

    // שחזור מצב התצוגה המפוצלת מה-JSON
    final bool splitedView = json['splitedView'] ??
        (Settings.getValue<bool>('key-splited-view') ?? false);

    debugPrint(
        'DEBUG: טעינת טאב ${json['title']} עם splitedView: $splitedView (מ-JSON: ${json['splitedView']})');

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
      highlightText: '', // לא שומרים highlight text ב-JSON
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
    bool splitedView = false;
    bool showPageShapeView = false;
    int currentIndex = index; // שמירת האינדקס הנוכחי כברירת מחדל

    if (bloc.state is TextBookLoaded) {
      final loadedState = bloc.state as TextBookLoaded;
      commentators = loadedState.activeCommentators;
      splitedView = loadedState.showSplitView;
      showPageShapeView = loadedState.showPageShapeView;
      // עדכון האינדקס מה-state הנטען - תמיד לוקחים את האינדקס האחרון שנראה
      if (loadedState.visibleIndices.isNotEmpty) {
        currentIndex = loadedState.visibleIndices.first;
        // עדכון גם את ה-index של הטאב עצמו כדי שישמר
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
      'isPinned': isPinned,
      'type': 'TextBookTab'
    };
  }
}
