import 'package:otzaria/shortcuts/dynamic/dynamic_shortcut_dispatcher.dart';
import 'dart:async';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/text_book/text_book_repository.dart';
// [EDITING DISABLED] import 'package:otzaria/text_book/editing/repository/local_overrides_repository.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/tabs/models/reading_tab_search_state.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/text_book/view/page_shape/utils/page_shape_plugin_api.dart';
import 'package:otzaria/text_book/view/page_shape/utils/page_shape_settings_manager.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter/foundation.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/utils/text/ref_helper.dart';
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

  /// טקסט להדגשה בלבד — לא מפעיל חלונית חיפוש.
  final String highlightText;

  /// שורה להדגשת רקע קבועה — מ-?mark deep link.
  final int? permanentHighlightLine;
  final Map<String, Map<String, bool>> searchOptions;
  final Map<int, List<String>> alternativeWords;
  final Map<String, String> spacingValues;
  final SearchMode searchMode;

  /// מרחק העריכה לחיפוש מקורב. בלעדיו fuzzy במרחק 0 מתנהג כחיפוש מדויק,
  /// ותוצאה שנפתחה מהחיפוש הגלובלי לא תימצא שוב בסרגל החיפוש שבתוך הספר.
  final int searchDistance;

  /// טווח הקרבה ומצב התאמת המילים שבהם נמצאה התוצאה — ראו [SearchMatchPolicy].
  final SearchMatchPolicy matchPolicy;

  /// שורות תוצאה ידועות בעת פתיחת הטאב מהחיפוש הגלובלי.
  final Set<int>? initialSearchResultLines;

  /// תת-מחרוזת להדגשה ממוקדת **רק** בסעיף שצוין. נטענת מקישור עומק
  /// (`otzaria://open/book/<id>?index=<n>&highlight=<text>`) ואינה פותחת חלונית
  /// חיפוש. אם null — אין הדגשה ממוקדת.
  final String? pinpointHighlight;

  /// אינדקס הסעיף שעליו תחול ההדגשה הממוקדת. אם null וב‑[pinpointHighlight] יש
  /// טקסט — נופלים חזרה ל‑[index] (זה המסלול של deep link, שבו פותחים בסעיף
  /// המודגש). השדה הופך משמעותי בעת שיכפול טאב או side‑by‑side, שם ה‑index
  /// הנוכחי כבר השתנה לפי הגלילה ואנחנו רוצים לשמר את הסעיף המקורי.
  final int? pinpointHighlightSectionIndex;

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

  /// הכותרת הנוכחית של המיקום בספר (למשל "בראשית פרק ד")
  final currentTitle = ValueNotifier<String>("");

  /// שולף את כתובת השורה [index] ב-[book] בלי לטעון את תוכן הספר.
  @visibleForTesting
  static Future<String?> Function(TextBook book, int index)
  locationTitleResolver = refFromDbLine;

  Future<void>? _locationTitleResolution;
  bool _isDisposed = false;

  /// ממלא את [currentTitle] לטאב שטרם נבנה על המסך (למשל אחרי שחזור בעלייה),
  /// בשאילתת DB יחידה. הטאב הפעיל מקבל את הכותרת מה-BLoC, ולכן רק ערך ריק מתמלא.
  Future<void> ensureLocationTitle() =>
      _locationTitleResolution ??= _resolveLocationTitle();

  Future<void> _resolveLocationTitle() async {
    if (currentTitle.value.isNotEmpty) return;
    final title = (await locationTitleResolver(book, index))?.trim();
    if (_isDisposed || currentTitle.value.isNotEmpty) return;
    if (title == null || title.isEmpty) {
      // ה-DB אולי עוד לא נפתח — הקריאה הבאה תנסה שוב.
      _locationTitleResolution = null;
      return;
    }
    currentTitle.value = title;
  }

  /// counter שמתגלגל עם כל בקשה לטוגל חלונית המפרשים מקיצור מקלדת גלובלי.
  /// המאזין הוא [SplitedViewScreen] בלבד; כל הגדלה = toggle יחיד.
  final ValueNotifier<int> toggleCommentatorsPaneNotifier = ValueNotifier<int>(
    0,
  );

  /// counter שמתגלגל כשיש לפתוח את פאנל ההערות האישיות.
  /// המאזין הוא [SplitedViewScreen] בלבד; כל הגדלה = פתח על טאב הערות.
  final ValueNotifier<int> openNotesTabNotifier = ValueNotifier<int>(0);

  /// counter-ים שמתגלגלים עם בקשת ניווט מקיצור מקלדת גלובלי. המאזין הוא
  /// מסך הספר; כל הגדלה = ניווט יחיד (זהה ללחיצה על כפתור הניווט המתאים).
  final ValueNotifier<int> navPreviousSegmentNotifier = ValueNotifier<int>(0);
  final ValueNotifier<int> navNextSegmentNotifier = ValueNotifier<int>(0);
  final ValueNotifier<int> navPreviousTocNotifier = ValueNotifier<int>(0);
  final ValueNotifier<int> navNextTocNotifier = ValueNotifier<int>(0);

  /// בקשת העתקה מקיצור דינמי; המסך שמחזיק את הבחירה מבצע ומאפס ל-null.
  final ValueNotifier<DynamicCopyRequest?> dynamicCopyRequestNotifier =
      ValueNotifier<DynamicCopyRequest?>(null);

  final PageShapePluginController pageShapePluginController =
      PageShapePluginController();

  List<String>? commentators;
  bool _lastSplitView = false;
  bool _lastShowPageShapeView = false;

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
    this.permanentHighlightLine,
    this.searchOptions = const {},
    this.alternativeWords = const {},
    this.spacingValues = const {},
    this.searchMode = SearchMode.exact,
    this.searchDistance = 0,
    this.matchPolicy = SearchMatchPolicy.standard,
    this.initialSearchResultLines,
    this.commentators,
    bool openLeftPane = false,
    bool? splitedView,
    bool? showPageShapeView,
    super.isPinned,
    super.dedupeKey,
    this.pinpointHighlight,
    this.pinpointHighlightSectionIndex,
    @visibleForTesting TextBookBloc? blocOverride,
    // מהדורה חלופית מקבלת כותרת טאב עם שם המהדורה, להבחנה מהנוסח הממוזג.
  }) : super(
         book.versionDisplayTitle == null
             ? book.title
             : '${book.title} (${book.versionDisplayTitle})',
       ) {
    // קביעת ברירת המחדל של splitedView מההגדרות אם לא סופק
    final bool effectiveSplitedView =
        splitedView ?? (Settings.getValue<bool>('key-splited-view') ?? true);

    // מצב צורת הדף הוא פר-ספר: כשהקורא לא קבע במפורש (למשל שחזור טאב
    // שמור), נופלים להעדפה שנשמרה לספר בהחלפת התצוגה — כך ספר שהמשתמש
    // קורא בצורת הדף נפתח כך מכל מקום (ספרייה, היסטוריה, סימניות, קישור),
    // ולא רק מהמסלולים שזכרו לשאול (issue #1424). בלי העדפה — תצוגה רגילה.
    final bool effectiveShowPageShapeView =
        showPageShapeView ??
        PageShapeSettingsManager.getViewModePreference(book.title) ??
        false;

    _lastSplitView = effectiveSplitedView;
    _lastShowPageShapeView = effectiveShowPageShapeView;

    // Initialize the bloc with initial state. ב‑production תמיד נבנה bloc חדש;
    // ה‑blocOverride קיים רק לטסטים שצריכים להזריק bloc עם repository מזויף
    // ולהביא אותו ל‑Loaded בלי תשתית קבצים אמיתית.
    bloc =
        blocOverride ??
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
            searchDistance: searchDistance,
            matchPolicy: matchPolicy,
            initialSearchResultLines: initialSearchResultLines,
            splitedView: effectiveSplitedView,
            showPageShapeView: effectiveShowPageShapeView,
            highlightText: highlightText,
            permanentHighlightLine: permanentHighlightLine,
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

    // הוספת listener לעדכון האינדקס כשה-state משתנה
    _stateSubscription = bloc.stream.listen((state) {
      if (state is TextBookLoaded && state.visibleIndices.isNotEmpty) {
        index = state.visibleIndices.first;
        _lastSplitView = state.showSplitView;
        _lastShowPageShapeView = state.showPageShapeView;
        // עדכון הכותרת הנוכחית
        if (state.currentTitle != null && state.currentTitle!.isNotEmpty) {
          currentTitle.value = state.currentTitle!;
        }
      }
    });
  }

  /// `OpenedTab.from` מטפל ב-[TextBookTab] בענף ייעודי ואינו מגיע לכאן;
  /// המימוש קיים כדי שהחוזה המופשט של [OpenedTab.clone] יתקיים, ומפנה
  /// לאותו מקום אחד שבו יודעים אילו שדות לשמר.
  @override
  OpenedTab clone() => OpenedTab.from(this);

  /// Cleanup when the tab is disposed
  @override
  void dispose() {
    _isDisposed = true;
    _stateSubscription?.cancel();
    currentTitle.dispose();
    toggleCommentatorsPaneNotifier.dispose();
    openNotesTabNotifier.dispose();
    navPreviousSegmentNotifier.dispose();
    navNextSegmentNotifier.dispose();
    navPreviousTocNotifier.dispose();
    navNextTocNotifier.dispose();
    dynamicCopyRequestNotifier.dispose();
    pageShapePluginController.detach();
    bloc.close();
    super.dispose();
  }

  /// Creates a new instance of [TextBookTab] from a JSON map.
  ///
  /// The JSON map should have 'initalIndex', 'title', 'commentaries',
  /// and 'type' keys.
  factory TextBookTab.fromJson(Map<String, dynamic> json) {
    final bool shouldOpenLeftPane = resolveRestoredReadingLeftPaneState(json);

    // שחזור מצב התצוגה המפוצלת מה-JSON
    final bool splitedView =
        json['splitedView'] ??
        (Settings.getValue<bool>('key-splited-view') ?? true);

    final TextBook restoredBook = json['book'] != null
        ? Book.fromJson(Map<String, dynamic>.from(json['book'])) as TextBook
        : TextBook(
            title: json['title'],
          );
    // קונפיגורציית החיפוש נטענת מהדיסק: בלעדיה הספר נפתח מחדש עם מסלול
    // המחרוזת הרצופה, וחלונית החיפוש הציגה "אין תוצאות" על חיפוש מורכב.
    final searchState = ReadingTabSearchState.fromJson(json);

    // חמשת שדות ההדגשה. קובץ קיים מגרסה שלא שמרה אותם, או ערך פגום, חייבים
    // ליפול לברירת מחדל ולא לזרוק — כישלון כאן מפיל טאב שלם מהשחזור.
    final rawResultLines = json['initialSearchResultLines'];
    final Set<int>? restoredResultLines = rawResultLines is List
        // רשימה ריקה נשמרת כריקה: "רץ חיפוש ולא נמצאו תוצאות" אינו זהה
        // ל-null שמשמעותו "לא רץ חיפוש מנוע".
        ? rawResultLines.whereType<int>().toSet()
        : null;

    return TextBookTab(
      index: json['initalIndex'],
      book: restoredBook,
      highlightText: json['highlightText'] is String
          ? json['highlightText'] as String
          : '',
      permanentHighlightLine: json['permanentHighlightLine'] is int
          ? json['permanentHighlightLine'] as int
          : null,
      initialSearchResultLines: restoredResultLines,
      pinpointHighlight: json['pinpointHighlight'] is String
          ? json['pinpointHighlight'] as String
          : null,
      pinpointHighlightSectionIndex:
          json['pinpointHighlightSectionIndex'] is int
          ? json['pinpointHighlightSectionIndex'] as int
          : null,
      commentators: List<String>.from(json['commentators']),
      splitedView: splitedView,
      showPageShapeView: json['showPageShapeView'] ?? false,
      openLeftPane: shouldOpenLeftPane,
      isPinned: json['isPinned'] ?? false,
      searchText: searchState.searchText,
      searchOptions: searchState.searchOptions,
      alternativeWords: searchState.alternativeWords,
      spacingValues: searchState.spacingValues,
      searchMode: searchState.searchMode,
      searchDistance: searchState.searchDistance,
      matchPolicy: searchState.matchPolicy,
    );
  }

  /// Converts the [TextBookTab] instance into a JSON map.
  ///
  /// The JSON map contains 'title', 'initalIndex', 'commentaries',
  /// and 'type' keys.
  @override
  Map<String, dynamic> toJson() {
    // בטאב שטרם נטען (שולחן עבודה לא-פעיל) הערכים חיים רק בשדות/ב-state
    // ההתחלתי — ברירות מחדל קבועות היו מאפסות אותם בשמירה לדיסק.
    List<String> commentators = this.commentators ?? [];
    bool splitedView = _lastSplitView;
    bool showPageShapeView = _lastShowPageShapeView;
    int currentIndex = index; // שמירת האינדקס הנוכחי כברירת מחדל
    // ספר ה-state כולל העשרה שנעשתה ברקע (id/מחבר/קטגוריות) — עדיף לשמירה.
    TextBook bookToSave = book;
    // חמשת שדות ההדגשה. בלעדיהם הפעלה מחדש החזירה את הספר בלי ההדגשה
    // שהמשתמש רואה ובלי סימון שורות התוצאה. שמות המפתחות הם שמות השדות של
    // [TextBookTab] — ב-state שלושה מהם נקראים אחרת.
    String highlightText = this.highlightText;
    int? permanentHighlightLine = this.permanentHighlightLine;
    Set<int>? searchResultLines = initialSearchResultLines;
    String? pinpointHighlight = this.pinpointHighlight;
    int? pinpointHighlightSectionIndex = this.pinpointHighlightSectionIndex;

    var searchState = ReadingTabSearchState(
      searchText: searchText,
      searchOptions: searchOptions,
      alternativeWords: alternativeWords,
      spacingValues: spacingValues,
      searchMode: searchMode,
      searchDistance: searchDistance,
      matchPolicy: matchPolicy,
    );

    if (bloc.state is TextBookLoaded) {
      final loadedState = bloc.state as TextBookLoaded;
      bookToSave = loadedState.book;
      searchState = ReadingTabSearchState(
        searchText: loadedState.searchText,
        searchOptions: loadedState.searchOptions,
        alternativeWords: loadedState.alternativeWords,
        spacingValues: loadedState.spacingValues,
        searchMode: loadedState.searchMode,
        searchDistance: loadedState.searchDistance,
        matchPolicy: loadedState.matchPolicy,
      );
      commentators = loadedState.activeCommentators;
      splitedView = loadedState.showSplitView;
      showPageShapeView = loadedState.showPageShapeView;
      highlightText = loadedState.highlightText;
      permanentHighlightLine = loadedState.permanentHighlightLine;
      searchResultLines = loadedState.searchResultLines;
      pinpointHighlight = loadedState.pinpointHighlightText;
      pinpointHighlightSectionIndex = loadedState.pinpointHighlightIndex;
      // עדכון האינדקס מה-state הנטען - תמיד לוקחים את האינדקס האחרון שנראה
      if (loadedState.visibleIndices.isNotEmpty) {
        currentIndex = loadedState.visibleIndices.first;
        // עדכון גם את ה-index של הטאב עצמו כדי שישמר
        index = currentIndex;
      }
    }

    return {
      'title': title,
      'book': bookToSave.toJson(),
      'initalIndex': currentIndex,
      'commentators': commentators,
      'splitedView': splitedView,
      'showPageShapeView': showPageShapeView,
      'showLeftPane': bloc.state.showLeftPane,
      'isPinned': isPinned,
      'type': 'TextBookTab',
      // ערכי ברירת מחדל אינם נכתבים, כדי לא לנפח את הקובץ ולא להבדיל בין
      // "לא נשמר" ל"נשמר ריק" — בדיוק כמו [ReadingTabSearchState.toJson].
      if (highlightText.isNotEmpty) 'highlightText': highlightText,
      'permanentHighlightLine': ?permanentHighlightLine,
      // null = "לא רץ חיפוש מנוע"; רשימה ריקה = "רץ ולא מצא". הבחנה
      // משמעותית, ולכן null אינו נכתב כרשימה ריקה.
      if (searchResultLines != null)
        'initialSearchResultLines': searchResultLines.toList(),
      if (pinpointHighlight != null && pinpointHighlight.isNotEmpty)
        'pinpointHighlight': pinpointHighlight,
      'pinpointHighlightSectionIndex': ?pinpointHighlightSectionIndex,
      ...searchState.toJson(),
    };
  }
}
