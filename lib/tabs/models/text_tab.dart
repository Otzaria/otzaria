import 'package:otzaria/shortcuts/dynamic/dynamic_shortcut_dispatcher.dart';

import 'dart:async';

import 'package:otzaria/plugins/services/plugin_correction_session_service.dart';
import 'package:otzaria/text_book/bloc/text_book_bloc.dart';
import 'package:otzaria/data/repository/text_book_repository.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/tabs/models/reading_tab_search_state.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/text_book/view/page_shape/utils/page_shape_plugin_api.dart';
import 'package:otzaria/text_book/view/page_shape/utils/page_shape_settings_manager.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter/foundation.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/utils/text/ref_helper.dart';
import 'package:otzaria/utils/ui/reading_left_pane_policy.dart';
import 'package:otzaria/text_book/view/reading_viewport/line_scroll_controller.dart';
import 'package:otzaria/text_book/utils/reading_segment_navigation.dart'
    show initialReadingAlignment;

/// כרטיסיית קורא טקסט; ה-BLoC שלה נוצר רק בגישה הראשונה אליו.
class TextBookTab extends OpenedTab {
  /// The text book.
  final TextBook book;

  /// שורת המקור הנוכחית. נכתבת רק מ-[LineScrollController.position].
  int get index => _index;
  int _index;

  /// The initial search text for this tab.
  final String searchText;
  final InBookSearchOrigin searchOrigin;
  final InBookSearchTemplate? searchTemplate;

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

  /// הסעיף המודגש, שנשאר קבוע גם כשהמיקום הנוכחי משתנה; null משתמש ב-[index].
  final int? pinpointHighlightSectionIndex;

  /// נבנה בגישה הראשונה בלבד: פענוח ושמירת שולחן עבודה אינם צריכים BLoC חי.
  TextBookBloc get bloc => _bloc ??= _createBloc();
  TextBookBloc? _bloc;
  late final TextBookInitial _initialState;

  /// ה-state הנוכחי, בלי לבנות bloc לטאב שטרם הוצג.
  TextBookState get blocState => _bloc?.state ?? _initialState;

  /// גלילת הקורא ומיקומו, בשורות מקור.
  late final LineScrollController lines;

  ReadingAnchor get readingAnchor =>
      lines.captureAnchor() ??
      ReadingAnchor(line: index, alignment: initialReadingAlignment(index));

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

  /// כל הגדלה מפעילה בקשת ניווט אחת במסך הספר.
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

  TextBookTab({
    required this.book,
    required int index,
    ReadingAnchor? initialReadingAnchor,
    this.searchText = '',
    this.searchOrigin = InBookSearchOrigin.inBook,
    this.searchTemplate,
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
  }) : _index = initialReadingAnchor?.line ?? index,
       super(
         book.versionDisplayTitle == null
             ? book.title
             : '${book.title} (${book.versionDisplayTitle})',
       ) {
    lines = LineScrollController(initialAnchor: initialReadingAnchor);
    // קביעת ברירת המחדל של splitedView מההגדרות אם לא סופק
    final bool effectiveSplitedView =
        splitedView ?? (Settings.getValue<bool>('key-splited-view') ?? true);

    // כשאין בחירה מפורשת, גם פתיחה מהיסטוריה ומקישורים מכבדת את העדפת הספר.
    final bool effectiveShowPageShapeView =
        showPageShapeView ??
        PageShapeSettingsManager.getViewModePreference(book.title) ??
        false;

    _lastSplitView = effectiveSplitedView;
    _lastShowPageShapeView = effectiveShowPageShapeView;

    _initialState = TextBookInitial.named(
      book,
      _index,
      openLeftPane,
      commentators ?? [],
      searchText: searchText,
      searchOrigin: searchOrigin,
      searchTemplate: searchTemplate,
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
    );
    lines.position.addListener(_onReadingPosition);
    // ה‑blocOverride קיים רק לטסטים שצריכים להזריק bloc עם repository מזויף.
    if (blocOverride != null) _bloc = _attachBloc(blocOverride);
  }

  TextBookBloc _createBloc() {
    final created = _attachBloc(
      TextBookBloc(
        repository: TextBookRepository(fileSystem: FileSystemData.instance),
        initialState: _initialState,
        readingPosition: lines.position,
      ),
    );
    if (_isDisposed) created.close();
    return created;
  }

  void _onReadingPosition() {
    final position = lines.position.value;
    if (position != null) _index = position.topLine;
  }

  TextBookBloc _attachBloc(TextBookBloc bloc) {
    _stateSubscription = bloc.stream.listen((state) {
      if (state is TextBookLoaded) {
        _lastSplitView = state.showSplitView;
        _lastShowPageShapeView = state.showPageShapeView;
        // עדכון הכותרת הנוכחית
        if (state.currentTitle != null && state.currentTitle!.isNotEmpty) {
          currentTitle.value = state.currentTitle!;
        }
      }
    });
    return bloc;
  }

  @override
  OpenedTab clone() => TextReadingSnapshot._capture(this).createTab();

  /// Cleanup when the tab is disposed
  @override
  void dispose() {
    _isDisposed = true;
    final correctionTabId = PluginCorrectionSessionService.knownTabIdFor(this);
    if (correctionTabId != null) {
      PluginCorrectionSessionService.instance.removeTab(correctionTabId);
    }
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
    lines.position.removeListener(_onReadingPosition);
    _bloc?.close();
    lines.dispose();
    super.dispose();
  }

  /// משחזר כרטיסייה בפורמט הקיים, כולל שמירות ללא נתוני ספר מקוננים.
  factory TextBookTab.fromJson(Map<String, dynamic> json) {
    final bool shouldOpenLeftPane = resolveRestoredReadingLeftPaneState(json);

    // שחזור מצב התצוגה המפוצלת מה-JSON
    final bool splitedView =
        json['splitedView'] ??
        (Settings.getValue<bool>('key-splited-view') ?? true);

    final TextBook restoredBook = json['book'] != null
        ? Book.fromJson(Map<String, dynamic>.from(json['book'])) as TextBook
        : TextBook(title: json['title']);
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
      initialReadingAnchor: ReadingAnchor.tryFromJson(json['readingAnchor']),
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
      searchOrigin: searchState.searchOrigin,
      searchTemplate: searchState.searchTemplate,
      searchOptions: searchState.searchOptions,
      alternativeWords: searchState.alternativeWords,
      spacingValues: searchState.spacingValues,
      searchMode: searchState.searchMode,
      searchDistance: searchState.searchDistance,
      matchPolicy: searchState.matchPolicy,
    )..historySlot = json['historySlot'] as String?;
  }

  @override
  Map<String, dynamic> toJson() => TextReadingSnapshot._capture(this).toJson();
}

/// מצב הקריאה שמשותף לשכפול ולשמירה, ללא יצירת BLoC.
class TextReadingSnapshot {
  TextReadingSnapshot._capture(TextBookTab tab) {
    final state = tab.blocState;
    _book = tab.book;
    _persistedBook = state is TextBookLoaded ? state.book : tab.book;
    _title = tab.title;
    _readingAnchor = tab.lines.captureAnchor();
    _index = _readingAnchor?.line ?? tab.index;
    _isPinned = tab.isPinned;
    _dedupeKey = tab.dedupeKey;
    _historySlot = tab.historySlot;
    // חלונית צפה אינה נשמרת: חלונית שנפתחת עם הספר נעוצה (issue #3212).
    _showLeftPane =
        state.showLeftPane && (state is! TextBookLoaded || state.pinLeftPane);
    _commentators = tab.commentators;
    _persistedSplitView = tab._lastSplitView;
    _persistedPageShapeView = tab._lastShowPageShapeView;
    _highlightText = tab.highlightText;
    _permanentHighlightLine = tab.permanentHighlightLine;
    _searchResultLines = tab.initialSearchResultLines;
    _pinpointHighlight = tab.pinpointHighlight;
    _pinpointHighlightSectionIndex = tab.pinpointHighlightSectionIndex;

    final (
      text,
      options,
      alternatives,
      spacing,
      mode,
      distance,
      policy,
      origin,
      template,
    ) = switch (state) {
      TextBookLoaded s => (
        s.searchText,
        s.searchOptions,
        s.alternativeWords,
        s.spacingValues,
        s.searchMode,
        s.searchDistance,
        s.matchPolicy,
        s.searchOrigin,
        s.searchTemplate,
      ),
      TextBookInitial s => (
        s.searchText,
        s.searchOptions,
        s.alternativeWords,
        s.spacingValues,
        s.searchMode,
        s.searchDistance,
        s.matchPolicy,
        s.searchOrigin,
        s.searchTemplate,
      ),
      _ => (
        tab.searchText,
        tab.searchOptions,
        tab.alternativeWords,
        tab.spacingValues,
        tab.searchMode,
        tab.searchDistance,
        tab.matchPolicy,
        tab.searchOrigin,
        tab.searchTemplate,
      ),
    };
    _search = ReadingTabSearchState(
      searchText: text,
      searchOrigin: origin,
      searchTemplate: template,
      searchOptions: options,
      alternativeWords: alternatives,
      spacingValues: spacing,
      searchMode: mode,
      searchDistance: distance,
      matchPolicy: policy,
    ).copy();

    if (state is TextBookLoaded) {
      _splitView = state.showSplitView;
      _pageShapeView = state.showPageShapeView;
      _commentators = state.activeCommentators;
      _highlightText = state.highlightText;
      _permanentHighlightLine = state.permanentHighlightLine;
      _searchResultLines = state.searchResultLines;
      _pinpointHighlight = state.pinpointHighlightText;
      _pinpointHighlightSectionIndex = state.pinpointHighlightIndex;
      _persistedSplitView = state.showSplitView;
      _persistedPageShapeView = state.showPageShapeView;
    } else if (state is TextBookInitial) {
      _splitView = state.splitedView;
      _pageShapeView = state.showPageShapeView;
    }
    _commentators = _commentators == null ? null : List.of(_commentators!);
    _searchResultLines = _searchResultLines == null
        ? null
        : Set.of(_searchResultLines!);
  }

  late final TextBook _book;
  late final TextBook _persistedBook;
  late final String _title;
  late final int _index;
  late final ReadingAnchor? _readingAnchor;
  late final bool _isPinned;
  late final String? _dedupeKey;
  late final String? _historySlot;
  late final bool _showLeftPane;
  late final ReadingTabSearchState _search;
  List<String>? _commentators;
  bool? _splitView;
  bool? _pageShapeView;
  late bool _persistedSplitView;
  late bool _persistedPageShapeView;
  late String _highlightText;
  int? _permanentHighlightLine;
  Set<int>? _searchResultLines;
  String? _pinpointHighlight;
  int? _pinpointHighlightSectionIndex;

  /// בונה טאב עצמאי ושומר את זהותו הזמנית, שאינה נשמרת לדיסק.
  TextBookTab createTab() {
    final search = _search.copy();
    return TextBookTab(
      book: _book,
      index: _index,
      initialReadingAnchor: _readingAnchor,
      searchText: search.searchText,
      searchOrigin: search.searchOrigin,
      searchTemplate: search.searchTemplate,
      searchOptions: search.searchOptions,
      alternativeWords: search.alternativeWords,
      spacingValues: search.spacingValues,
      searchMode: search.searchMode,
      searchDistance: search.searchDistance,
      matchPolicy: search.matchPolicy,
      highlightText: _highlightText,
      permanentHighlightLine: _permanentHighlightLine,
      initialSearchResultLines: _searchResultLines == null
          ? null
          : Set.of(_searchResultLines!),
      pinpointHighlight: _pinpointHighlight,
      pinpointHighlightSectionIndex: _pinpointHighlightSectionIndex,
      commentators: _commentators == null ? null : List.of(_commentators!),
      openLeftPane: _showLeftPane,
      splitedView: _splitView,
      showPageShapeView: _pageShapeView,
      isPinned: _isPinned,
      dedupeKey: _dedupeKey,
    )..historySlot = _historySlot;
  }

  /// שומר את פורמט הטאב הקיים ואת נתוני הספר שהועשרו בזמן הקריאה.
  Map<String, dynamic> toJson() => {
    'title': _title,
    'book': _persistedBook.toJson(),
    'initalIndex': _index,
    if (_readingAnchor != null) 'readingAnchor': _readingAnchor.toJson(),
    'commentators': _commentators ?? <String>[],
    'splitedView': _persistedSplitView,
    'showPageShapeView': _persistedPageShapeView,
    'showLeftPane': _showLeftPane,
    'isPinned': _isPinned,
    'type': 'TextBookTab',
    'historySlot': ?_historySlot,
    if (_highlightText.isNotEmpty) 'highlightText': _highlightText,
    'permanentHighlightLine': ?_permanentHighlightLine,
    // null = חיפוש שלא רץ; סט ריק = חיפוש שלא מצא תוצאות.
    if (_searchResultLines != null)
      'initialSearchResultLines': _searchResultLines!.toList(),
    if (_pinpointHighlight != null && _pinpointHighlight!.isNotEmpty)
      'pinpointHighlight': _pinpointHighlight,
    'pinpointHighlightSectionIndex': ?_pinpointHighlightSectionIndex,
    ..._search.toJson(),
  };
}
