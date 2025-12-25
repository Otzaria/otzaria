import 'dart:async';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/text_book_repository.dart';
import 'package:otzaria/text_book/editing/repository/local_overrides_repository.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter/foundation.dart';

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
    this.commentators,
    bool openLeftPane = false,
    bool? splitedView,
    bool showPageShapeView = false,
    bool isPinned = false,
  }) : super(book.title, isPinned: isPinned) {
    debugPrint('DEBUG: TextBookTab נוצר עם אינדקס: $index לספר: ${book.title}');

    // קביעת ברירת המחדל של splitedView מההגדרות אם לא סופק
    final bool effectiveSplitedView =
        splitedView ?? (Settings.getValue<bool>('key-splited-view') ?? false);

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
        searchText: searchText,
        splitedView: effectiveSplitedView,
        showPageShapeView: showPageShapeView,
      ),
      scrollController: scrollController,
      positionsListener: positionsListener,
    );

    // הוספת listener לעדכון האינדקס כשה-state משתנה
    _stateSubscription = bloc.stream.listen((state) {
      if (state is TextBookLoaded && state.visibleIndices.isNotEmpty) {
        index = state.visibleIndices.first;
        debugPrint('DEBUG: עדכון אינדקס ל-$index עבור ספר: ${book.title}');
      }
    });
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

    return TextBookTab(
      index: json['initalIndex'],
      book: TextBook(
        title: json['title'],
      ),
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
        debugPrint(
            'DEBUG: שמירת טאב ${book.title} עם אינדקס: $currentIndex, splitedView: $splitedView (מתוך visibleIndices)');
      } else {
        debugPrint(
            'DEBUG: שמירת טאב ${book.title} עם אינדקס: $currentIndex, splitedView: $splitedView (ברירת מחדל)');
      }
    } else {
      debugPrint(
          'DEBUG: שמירת טאב ${book.title} עם אינדקס: $currentIndex, splitedView: $splitedView (state לא loaded)');
    }

    return {
      'title': title,
      'initalIndex': currentIndex,
      'commentators': commentators,
      'splitedView': splitedView,
      'showPageShapeView': showPageShapeView,
      'isPinned': isPinned,
      'type': 'TextBookTab'
    };
  }
}
