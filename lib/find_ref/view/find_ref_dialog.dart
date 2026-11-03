import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:otzaria/widgets/misc/app_popup_menu.dart';
import 'package:otzaria/widgets/controls/toggle_pill.dart';
import 'package:otzaria/widgets/text/otzaria_search_field.dart';
import 'package:otzaria/plugins/models/plugin_search_field_action.dart';
import 'package:otzaria/plugins/services/plugin_search_field_actions_registry.dart';
import 'package:otzaria/plugins/view/plugin_search_field_actions.dart';
import 'package:otzaria/theme/layout_tokens.dart';
import 'package:otzaria/widgets/feedback/otzaria_empty_state.dart';
import 'package:otzaria/theme/app_surfaces.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:flutter/services.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria_icons/otzaria_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/find_ref/bloc/find_ref_bloc.dart';
import 'package:otzaria/search/view/layout_fix_suggestion_banner.dart';
import 'package:otzaria/find_ref/bloc/find_ref_event.dart';
import 'package:otzaria/find_ref/bloc/find_ref_state.dart';
import 'package:otzaria/find_ref/find_ref_personal_books_setting.dart';
import 'package:otzaria/find_ref/find_ref_recent_store.dart';
import 'package:otzaria/find_ref/repository/db_reference_result.dart';
import 'package:otzaria/find_ref/repository/find_ref_db_isolate.dart';
import 'package:otzaria/find_ref/repository/find_ref_repository.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/history/bloc/history_event.dart';
import 'package:otzaria/core/focus_repository.dart';
import 'package:otzaria/core/external_uri_router.dart';
import 'package:otzaria/find_ref/repository/library_book_index.dart';
import 'package:otzaria/library/hidden/hidden_library_selection.dart';
import 'package:otzaria/library/hidden/hidden_library_store.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart' show Screen;
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/utils/navigation/book_open_coordinator.dart';
import 'package:otzaria/utils/navigation/open_book.dart';
import 'package:otzaria/utils/navigation/talmud_bavli_open_format.dart';
import 'package:otzaria/utils/ui/book_format_icon.dart';
import 'package:otzaria/utils/ui/reading_left_pane_policy.dart';
import 'package:otzaria/tour/tour_target_keys.dart';
import 'package:otzaria/library/view/grid_items.dart';
import 'package:otzaria/widgets/text/rtl_text_field.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria/core/windowing/app_window_keys.dart';
import 'package:otzaria/navigation/view/main_window_screen.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';
import 'package:otzaria/widgets/dialogs/app_dialog_frame.dart';
import 'package:otzaria/widgets/layout/centered_scrollable_state.dart';
import 'package:otzaria/theme/app_motion.dart';

/// מה שהדיאלוג מבקש מהמסך הראשי — ניתוב קישורים ופתיחת חיפוש טקסט.
abstract interface class FindRefDialogHost {
  Future<bool> handleDeepLink(String uri);
  void openTextSearch(String query);
}

class _MainWindowFindRefHost implements FindRefDialogHost {
  const _MainWindowFindRefHost(this._screenKey);

  final GlobalKey<MainWindowScreenState> _screenKey;

  @override
  Future<bool> handleDeepLink(String uri) async =>
      await _screenKey.currentState?.handleInternalDeepLink(uri) ?? false;

  @override
  void openTextSearch(String query) {
    final mainScreen = _screenKey.currentState;
    if (mainScreen == null) {
      debugPrint('[FindRef] openTextSearch: main window screen not mounted');
      return;
    }
    mainScreen.openSearchDialog(SearchingTab.newSearch('חיפוש', query));
  }
}

class FindRefDialog extends StatefulWidget {
  const FindRefDialog({super.key, this.host});

  /// `null` — המסך הראשי של החלון שהדיאלוג יושב בו.
  final FindRefDialogHost? host;

  @visibleForTesting
  static void resetExamplesRotationForTesting([int offset = 0]) =>
      _FindRefDialogState._examplesOffset = offset;

  @override
  State<FindRefDialog> createState() => _FindRefDialogState();
}

/// רשומת מפרש מוכנה לפתיחה ישירה ללא שאילתות נוספות.
/// נוצרת בעת טעינת רשימת המפרשים — מאחדת את ה-`title` ו-`targetSegment`
/// מה-DB עם ה-[Book] המתאים מתוך הספרייה.
///
/// `targetSegment` הוא ה-`targetLineIndex` שהחזיר ה-DB — המיקום המקביל הראשון
/// בספר המפרש על פני הקטע. הוא nullable רק כאמצעי הגנה (row חריג בלי
/// `targetLineIndex`); במקרה כזה הקליק נופל לתחילת ספר המפרש (segment 0).
class _CommentatorEntry {
  final String title;
  final int? bookId;
  final int? targetSegment;
  final Book book;

  const _CommentatorEntry({
    required this.title,
    required this.bookId,
    required this.targetSegment,
    required this.book,
  });
}

class _FindRefDialogState extends State<FindRefDialog> {
  /// מאגר הפוקוס של החלון; נשמר כאן כי ב-dispose אסור לחפש ב-context.
  late final FocusRepository _focus;

  /// מאגר הדוגמאות שמוצגות כשאין עדיין איתורים אחרונים. בכל פתיחה מוצג
  /// חלון אחר מתוכו (ראו [_rotatedExamples]).
  static const List<String> _referenceExamples = [
    'בראשית פרק א',
    'שו"ע או"ח יב',
    'רמב"ם תפילה ב',
    'תהילים פרק כג',
    'שמות פרק כ',
    'משלי פרק ג',
  ];

  /// בזיכרון בלבד: כתיבה להגדרות בכל פתיחה משדרת סנכרון לכל החלונות.
  static int _examplesOffset = math.Random().nextInt(_referenceExamples.length);

  static const int _suggestionCount = 3;

  /// ההצעות שמוצגות במצב הפתיחה, ומאיזה מקור הן הגיעו.
  late List<String> _suggestions;
  late bool _suggestionsAreRecent;

  /// הסימון משתנה בכל חץ והקלדה — רק השורות מאזינות לו, לא הדיאלוג כולו.
  final ValueNotifier<int> _selectedIndex = ValueNotifier<int>(0);
  bool _queryIsEmpty = true;

  /// השאילתה המנורמלת שבשדה. תוצאות של שאילתה אחרת מוצגות אך אינן נפתחות.
  final ValueNotifier<String> _typedQuery = ValueNotifier<String>('');

  /// Enter נלחץ לפני שהגיעו תוצאות לשאילתה שבשדה — התוצאה הראשונה שלה
  /// תיפתח כשתגיע.
  bool _pendingEnter = false;

  /// השאילתה של סט התוצאות האחרון; סט של שאילתה אחרת מתחיל מראש הרשימה.
  String? _resultsQuery;

  /// התוצאות שמוצגות כרגע. נשמרות כדי שהקלדה של אות נוספת לא תרוקן את
  /// הרשימה ותחזיר אותה — הרשימה הקודמת נשארת עד שהחדשה מגיעה.
  List<DbReferenceResult> _shownRefs = const <DbReferenceResult>[];
  FindRefState? _supersededVisibilityState;
  bool _includePersonalBooks = FindRefPersonalBooksSetting.load();
  final Map<int, GlobalKey> _itemKeys = {};
  final Map<int, GlobalKey> _commentatorsButtonKeys = {};
  // המפתח כולל את כל הפרמטרים המבדילים בין refs (bookId/sourceLineId/isAltToc/
  // level/segment) — TOC רגיל ו-AltToc יכולים לחלוק שורת התחלה ולחשב טווח שונה.
  // value=null → טעינה בתהליך.
  // value=[] → אין מפרשים זמינים (לא יוצג כפתור).
  // value=[...] → רשומות מוכנות לפתיחה ישירה (כולל targetSegment ו-Book).
  final Map<String, List<_CommentatorEntry>?> _commentatorsByRef = {};

  final FindRefBookIndexCache _bookIndexes = FindRefBookIndexCache();
  StreamSubscription<void>? _personalBooksChanges;
  StreamSubscription<HiddenLibrarySelection>? _localVisibilityChanges;
  late HiddenLibrarySelection _lastVisibilitySelection;
  int _visibilityRevision = 0;
  final ScrollController _resultsScrollController = ScrollController();
  // `true` כשיש תוצאות מתחת לאזור הנראה. מעודכן משני מקורות:
  //   1. listener על ה-ScrollController — מטפל בגלילה ע"י המשתמש.
  //   2. NotificationListener<ScrollMetricsNotification> — מטפל בחיבור ראשון
  //      של ה-ListView ובשינוי maxScrollExtent (סט תוצאות חדש).
  // ScrollController.attach לבדו לא קורא notifyListeners, ולכן בלי ה-
  // metrics notification ה-arrow היה נשאר מוסתר עד גלילה ידנית.
  final ValueNotifier<bool> _hasMoreBelow = ValueNotifier<bool>(false);
  FocusRestorer? _focusRestorer;
  late final FindRefDialogHost _defaultHost;

  FindRefDialogHost get _host => widget.host ?? _defaultHost;

  @override
  void initState() {
    super.initState();
    _focus = FocusRepository.of(context);
    _defaultHost = _MainWindowFindRefHost(
      AppWindowKeys.of(context).mainWindowScreen,
    );
    final hiddenStore = const HiddenLibraryStore();
    _lastVisibilitySelection = hiddenStore.load();
    _localVisibilityChanges = hiddenStore.changes.listen(
      (_) => _refreshVisibilityIfChanged(),
    );

    _personalBooksChanges = FindRefPersonalBooksSetting.changes.listen(
      (_) => _syncPersonalBooksToggle(),
    );

    final recent = FindRefRecentStore.load();
    _suggestionsAreRecent = recent.isNotEmpty;
    _suggestions = _suggestionsAreRecent
        ? recent.take(_suggestionCount).toList()
        : _rotatedExamples();

    // חימום מוקדם של קאש ה-AltToc הגלובלי בתוך ה-worker — כדי שהחיפוש
    // הראשון שנופל ל-fallback לא ימתין לבנייתו (~1-2 שניות).
    unawaited(
      context.read<FindRefBloc>().findRefRepository.prewarmGlobalAltToc(),
    );

    // בחירת הטקסט הקיים כאשר חוזרים למסך
    // מבוצע מיד ולא ב-postFrameCallback כדי למנוע אובדן פוקוס באנדרואיד
    final controller = _focus.findRefSearchController;
    _queryIsEmpty = controller.text.isEmpty;
    _typedQuery.value = FindRefBloc.normalizeQuery(controller.text);
    controller.addListener(_onQueryTextChanged);
    if (controller.text.isNotEmpty) {
      controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: controller.text.length,
      );
    }

    // רישום כ-active restorer כדי שהדיאלוג יקבל שחזור פוקוס לאחר אירועי חלון
    _focusRestorer = _focus.registerActiveRestorer(
      restore: () {
        if (mounted) _focus.findRefSearchFocusNode.requestFocus();
      },
      canRestore: () =>
          mounted &&
          _focus.findRefSearchFocusNode.canRequestFocus &&
          (ModalRoute.of(context)?.isCurrent ?? false),
    );

    // listener מטפל בגלילה ידנית של המשתמש. עבור חיבור ראשון ולכל שינוי
    // ב-maxScrollExtent (סט תוצאות חדש) משתמשים ב-NotificationListener
    // ליד ה-ListView (ב-build).
    _resultsScrollController.addListener(_updateHasMoreBelow);
  }

  @override
  void dispose() {
    _personalBooksChanges?.cancel();
    _localVisibilityChanges?.cancel();
    _resultsScrollController.removeListener(_updateHasMoreBelow);
    _resultsScrollController.dispose();
    _hasMoreBelow.dispose();
    _focus.findRefSearchController.removeListener(
      _onQueryTextChanged,
    );
    _selectedIndex.dispose();
    _typedQuery.dispose();
    final restorer = _focusRestorer;
    if (restorer != null) _focus.unregisterActiveRestorer(restorer);
    super.dispose();
  }

  /// כפתור הניקוי תלוי רק בשאלה אם השדה ריק — בנייה מחדש רק כשזה מתהפך.
  void _onQueryTextChanged() {
    final text = _focus.findRefSearchController.text;
    final normalized = FindRefBloc.normalizeQuery(text);
    // גם שינוי שלא דרך ההקלדה (קישור איתור חיצוני) מבטל Enter ממתין.
    if (normalized != _typedQuery.value) _pendingEnter = false;
    _typedQuery.value = normalized;
    final isEmpty = text.isEmpty;
    if (isEmpty != _queryIsEmpty && mounted) {
      setState(() => _queryIsEmpty = isEmpty);
    }
  }

  /// ההגדרה היא המקור היחיד: חלון אחר או קישור עשויים לשנות אותה בזמן
  /// שהדיאלוג פתוח, ובלי עדכון התוצאות לא היו נחשבות עדכניות לעולם.
  void _syncPersonalBooksToggle() {
    final stored = FindRefPersonalBooksSetting.load();
    if (stored == _includePersonalBooks || !mounted) return;
    setState(() => _includePersonalBooks = stored);
    // גם תוצאות עדכניות אינן מוכיחות שאין חיפוש ישן ב-debounce.
    // הבלוק מבטל אותו ומדלג על חיפוש חוזר כשכבר מוצגות אותן תוצאות.
    final bloc = context.read<FindRefBloc>();
    final text = _focus.findRefSearchController.text;
    if (text.length >= 2) {
      _selectedIndex.value = 0;
      bloc.add(SearchRefRequested(text, includePersonalBooks: stored));
      _openPendingEnterIfCurrent(bloc.state);
    }
  }

  /// שולח איתור חדש מהמסך ומאפס את הסימון לתוצאה הראשונה.
  void _dispatchSearch(String text, {bool? includePersonalBooks}) {
    _selectedIndex.value = 0;
    _pendingEnter = false;
    context.read<FindRefBloc>().add(
      SearchRefRequested(
        text,
        includePersonalBooks: includePersonalBooks ?? _includePersonalBooks,
      ),
    );
  }

  /// התוצאות שייכות לשאילתה ולמתג שבמסך כרגע, ולכן מותר לפתוח אותן.
  bool _isCurrentSuccess(FindRefState state) =>
      state is FindRefSuccess &&
      !identical(state, _supersededVisibilityState) &&
      state.includePersonalBooks == _includePersonalBooks &&
      FindRefBloc.normalizeQuery(state.query) == _typedQuery.value;

  void _openPendingEnterIfCurrent(FindRefState state) {
    if (!_pendingEnter || !_isCurrentSuccess(state)) return;
    _pendingEnter = false;
    final refs = (state as FindRefSuccess).refs;
    if (refs.isNotEmpty) _openRef(refs.first);
  }

  void _refreshVisibilityIfChanged() {
    if (!mounted) return;
    final selection = const HiddenLibraryStore().load();
    if (selection == _lastVisibilitySelection) return;
    _lastVisibilitySelection = selection;
    final query = _focus.findRefSearchController.text;
    _visibilityRevision++;
    final bloc = context.read<FindRefBloc>();
    _supersededVisibilityState = bloc.state is FindRefSuccess
        ? bloc.state
        : null;
    setState(() {
      _bookIndexes.clear();
      _commentatorsByRef.clear();
      _shownRefs = const [];
    });
    bloc.add(ClearSearchRequested());
    if (query.isNotEmpty) {
      bloc.add(
        SearchRefRequested(
          query,
          includePersonalBooks: _includePersonalBooks,
        ),
      );
    }
  }

  /// מעדכן את [_hasMoreBelow] לפי המצב הנוכחי של ה-ScrollController.
  /// בטוח לקריאה בכל זמן — הוא חסום על `hasClients` ועל `hasContentDimensions`.
  void _updateHasMoreBelow() {
    final bool next;
    if (!_resultsScrollController.hasClients) {
      next = false;
    } else {
      final pos = _resultsScrollController.position;
      // hasContentDimensions=false לפני שה-ListView סיים מדידה ראשונית.
      next =
          pos.hasContentDimensions &&
          // 8 פיקסלים של סף — מונע flicker כשהמשתמש כמעט בתחתית.
          pos.maxScrollExtent - pos.pixels > 8;
    }
    if (_hasMoreBelow.value != next) _hasMoreBelow.value = next;
  }

  GlobalKey _getKeyForIndex(int index) {
    if (!_itemKeys.containsKey(index)) {
      _itemKeys[index] = GlobalKey();
    }
    return _itemKeys[index]!;
  }

  GlobalKey _getCommentatorsButtonKey(int index) {
    if (!_commentatorsButtonKeys.containsKey(index)) {
      _commentatorsButtonKeys[index] = GlobalKey();
    }
    return _commentatorsButtonKeys[index]!;
  }

  String _commentatorsKey(DbReferenceResult ref) =>
      FindRefRepository.commentatorsKeyFor(ref);

  /// טוען את רשימת המפרשים ל-[ref] ברקע אם עוד לא נטענה, יחד עם ה-[Book]
  /// המתאים לכל מפרש. רשומות מלאות נשמרות ב-[_commentatorsByRef] כך שהקליק
  /// על מפרש יוכל לפתוח אותו ישירות, בלי `await` וללא שאילתות.
  void _ensureCommentatorsLoaded(DbReferenceResult ref) {
    final key = _commentatorsKey(ref);
    if (_commentatorsByRef.containsKey(key)) return; // נטען / בתהליך טעינה
    _commentatorsByRef[key] = null; // sentinel: בתהליך
    final visibilityRevision = _visibilityRevision;
    final repository = context.read<FindRefBloc>().findRefRepository;
    () async {
      try {
        final dbEntries = await repository.getCommentatorsForResult(ref);
        if (!mounted || visibilityRevision != _visibilityRevision) return;
        if (dbEntries.isEmpty) {
          setState(() {
            _commentatorsByRef[key] = const [];
          });
          return;
        }
        final index = await _bookIndexes.load();
        if (!mounted || visibilityRevision != _visibilityRevision) return;
        final entries = <_CommentatorEntry>[
          for (final e in dbEntries)
            _CommentatorEntry(
              title: e.title,
              bookId: e.bookId,
              targetSegment: e.targetSegment,
              book:
                  index.resolveCommentatorBook(e.title, bookId: e.bookId) ??
                  TextBook(title: e.title, id: e.bookId),
            ),
        ];
        setState(() {
          _commentatorsByRef[key] = entries;
        });
      } on FindRefQueryCancelled {
        // הקלדה חדשה זרקה את הטעינה מהתור. מסירים את ה-sentinel כדי שהשורה
        // תנסה שוב — אחרת האייקון לא היה מופיע יותר לתוצאה הזו.
        if (visibilityRevision == _visibilityRevision) {
          _commentatorsByRef.remove(key);
        }
      } catch (e) {
        debugPrint('[FindRef] commentators load failed: $e');
        if (!mounted || visibilityRevision != _visibilityRevision) return;
        setState(() {
          _commentatorsByRef[key] = const [];
        });
      }
    }();
  }

  /// השורות שנבנו בפריים הנוכחי — ListView.builder בונה רק שורות נראות.
  final Set<int> _rowsAwaitingCommentators = {};
  bool _commentatorsLoadScheduled = false;

  /// הטעינה עצמה נדחית לאחר הפריים: build נשאר נקי מבקשות, ורשימה
  /// שהתיישנה עד אז אינה מבקשת מפרשים בכלל.
  void _requestCommentatorsAfterFrame(int index) {
    _rowsAwaitingCommentators.add(index);
    if (_commentatorsLoadScheduled) return;
    _commentatorsLoadScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _commentatorsLoadScheduled = false;
      final rows = _rowsAwaitingCommentators.toList();
      _rowsAwaitingCommentators.clear();
      // דיאלוג שנסגר (Enter ממתין פותח באותו פריים) לא יתחרה בטעינת הספר.
      if (!mounted || !(ModalRoute.isCurrentOf(context) ?? true)) return;
      final state = context.read<FindRefBloc>().state;
      if (!_isCurrentSuccess(state)) return;
      final refs = (state as FindRefSuccess).refs;
      for (final index in rows) {
        if (index < refs.length) _ensureCommentatorsLoaded(refs[index]);
      }
    });
  }

  void _scrollToSelected({int count = 0}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final index = _selectedIndex.value;
      final context = _getKeyForIndex(index).currentContext;
      if (context != null) {
        Scrollable.ensureVisible(
          context,
          duration: AppMotion.duration(context, AppTokens.animPanelOpacity),
          curve: Curves.easeInOut,
          alignment: 0.5, // מרכז המסך
        );
        return;
      }
      // שורה רחוקה (Ctrl+End, PageDown) עוד לא נבנתה ואין לה context:
      // קופצים לאומדן מיקומה, והשורה תמורכז בפריים הבא.
      if (count == 0 || !_resultsScrollController.hasClients) return;
      final position = _resultsScrollController.position;
      final rowExtent =
          (position.maxScrollExtent + position.viewportDimension) / count;
      _resultsScrollController.jumpTo(
        (rowExtent * index - position.viewportDimension / 2).clamp(
          0.0,
          position.maxScrollExtent,
        ),
      );
      _scrollToSelected();
    });
  }

  /// מספר השורות שנכנסות בגובה הרשימה, לפי הגובה הממוצע של שורה בה.
  int _resultsPageStep(int count) {
    if (!_resultsScrollController.hasClients || count == 0) return 1;
    final position = _resultsScrollController.position;
    final rowExtent =
        (position.maxScrollExtent + position.viewportDimension) / count;
    if (rowExtent <= 0) return 1;
    return math.max(1, (position.viewportDimension / rowExtent).floor());
  }

  /// חץ הגלילה לסוף הרשימה, לפי [_hasMoreBelow]. ה-IconButton נשאר במקומו
  /// ורק ה-opacity משתנה, כך שהפריסה לא זזה כשהחץ נכבה ונדלק.
  Widget _buildScrollToEndArrow() {
    return ValueListenableBuilder<bool>(
      valueListenable: _hasMoreBelow,
      builder: (context, hasMore, _) {
        return AnimatedOpacity(
          opacity: hasMore ? 1.0 : 0.0,
          duration: AppMotion.duration(context, AppTokens.animFast),
          child: IgnorePointer(
            ignoring: !hasMore,
            child: IconButton(
              iconSize: AppTokens.iconSM,
              visualDensity: VisualDensity.compact,
              icon: const Icon(FluentIcons.chevron_down_24_regular),
              tooltip: context.settingsText('גלול לסוף הרשימה'),
              onPressed: () {
                final position = _resultsScrollController.position;
                AppMotion.scrollPosition(
                  position,
                  position.maxScrollExtent,
                  AppTokens.animNormal,
                  curve: Curves.easeOut,
                );
              },
            ),
          ),
        );
      },
    );
  }

  /// פותח את התוצאה.
  ///
  /// [initialCommentators] סמנטיקה:
  ///   null  → ברירת מחדל: history fallback (התנהגות onTap הרגילה).
  ///   []    → bypass מפורש: ללא מפרשים, גם אם בעבר היו (= "פתח ללא מפרש").
  ///   [...] → רשימה מפורשת (= "פתח עם רש"י").
  Future<void> _openRef(
    DbReferenceResult ref, {
    List<String>? initialCommentators,
  }) async {
    _rememberCurrentQuery();
    // אינדקס 0 נקרא "בלי מיקום" ומשוחזר מההיסטוריה; רק תוצאת ספר-בלבד היא כזו.
    final hasExplicitLocation = ref.reference != ref.title;
    Book? book;
    var openAsPdf = ref.isPdf;
    var segment = ref.segment.toInt();

    if (ref.isPdf && ref.filePath.isNotEmpty) {
      // לפי הנתיב ולא לפי הכותרת — לאותה כותרת עשוי להיות גם ספר טקסט.
      final index = await _bookIndexes.tryLoad();
      book =
          index?.pdfBookByPath(ref.filePath) ??
          PdfBook(title: ref.title, path: ref.filePath);
    } else {
      // אם המשתמש ביקש מפרש מסוים — חייבים TextBookTab, כי PdfBookTab אינו
      // מקבל commentators כלל.
      final needsTextBook =
          initialCommentators != null && initialCommentators.isNotEmpty;

      final index = await _bookIndexes.tryLoad();
      final visibility = index?.visibility;
      if (visibility != null &&
          !visibility.allowsCandidate(
            ref.source,
            ref.bookId,
            ref.filePath,
            fileType: ref.isPdf ? 'pdf' : 'txt',
          )) {
        return;
      }

      // הגדרת "פורמט פתיחת תלמוד בבלי": תוצאת טקסט של מסכת בבלי נפתחת
      // מיידית כטאב טעינה שממופה ל-PDF בתוכו. מזהים את ספר המקור בעץ לפי
      // bookId (זהות יציבה); בלי זיהוי ודאי לא ממירים ל-PDF, אחרת בחירה
      // לפי כותרת בלבד עלולה לפתוח ספר אחר בעל שם זהה.
      if (!needsTextBook &&
          ref.source.isOfficial &&
          index != null &&
          ref.bookId > 0) {
        final sourceBook = index.officialTextBookById(ref.bookId);
        if (sourceBook != null) {
          final target = await resolveTalmudBavliPdfBook(sourceBook);
          if (target != null) {
            if (!mounted) return;
            final tabsBloc = context.read<TabsBloc>();
            final navigationBloc = context.read<NavigationBloc>();
            final historyBloc = context.read<HistoryBloc>();
            final layoutWidth = readingLayoutWidthResolverOf(context);
            Navigator.of(context).pop();
            // כמו ב-BookOpenCoordinator.openBook: שמירת מיקום הקריאה של הטאב
            // הנוכחי להיסטוריה לפני שהטאב הדחוי תופס את המוקד.
            if (tabsBloc.state.hasOpenTabs) {
              historyBloc.add(
                CaptureStateForHistory(tabsBloc.state.currentTab!),
              );
            }
            final openLeftPane = shouldAutoOpenReadingLeftPane(
              screenWidth: layoutWidth(),
            );
            final coordinator = BookOpenCoordinator(
              tabsBloc: tabsBloc,
              historyBloc: historyBloc,
              navigationBloc: navigationBloc,
              layoutWidth: layoutWidth,
            );
            final resolvingTab = buildTalmudBavliResolvingTab(
              target: target,
              textIndex: segment,
              // ה-fallback לטקסט נבנה דרך סמנטיקת openBook — שחזור מיקום
              // ומפרשים מההיסטוריה וצורת-דף שמורה, כמו במסלול הפתיחה הישיר.
              buildTextTab: (dedupeKey) => coordinator.buildTab(
                sourceBook,
                segment,
                '',
                explicitIndex: hasExplicitLocation,
                initialCommentators: initialCommentators,
                dedupeKey: dedupeKey,
              ),
              buildPdfTab: (page, dedupeKey) => PdfBookTab(
                book: target.pdfBook,
                pageNumber: page,
                dedupeKey: dedupeKey,
                openLeftPane: openLeftPane,
                requiresStableLayout: true,
              ),
            );
            tabsBloc.add(OpenOrFocusTab(resolvingTab));
            navigationBloc.add(const NavigateToScreen(Screen.reading));
            return;
          }
        }
      }

      if (index != null) {
        // רשמי לפי המזהה, ולפי כותרת רק כשהמזהה חסר בעץ; אישי/מצורף לפי מקור
        // ומזהה בלבד. בלי ספר גלוי תואם נבנה TextBook מהתוצאה (למטה).
        book = index.resolveFindRefBook(
          ref.title,
          bookId: ref.bookId > 0 ? ref.bookId : null,
          source: ref.source,
          preferTextBook: needsTextBook,
        );
        // ספרי בבלי מופיעים בעץ הספרייה כ-PdfBook גם כשה-DB מכיר אותם
        // כ-txt; ה-segment הוא אינדקס טקסט, לכן נפתחת מהדורת הטקסט.
        if (book is PdfBook && isTalmudBavliBook(book)) {
          book = null;
        }
      }
      book ??= TextBook(
        title: ref.title,
        id: ref.bookId > 0 && !ref.source.isOfficial ? ref.bookId : null,
        source: ref.source,
      );
    }

    if (!mounted) return;
    Navigator.of(context).pop();
    openBook(
      context,
      book,
      segment,
      '',
      ignoreHistory: openAsPdf,
      explicitIndex: hasExplicitLocation,
      navigateToPositionIfReused: hasExplicitLocation,
      requiresStableLayout: openAsPdf,
      initialCommentators: initialCommentators,
    );
  }

  /// פותח תפריט עם רשימת המפרשים הזמינים (כבר preloaded — כולל `Book` לכל
  /// רשומה). בחירה פותחת את ספר המפרש ישירות במיקומו (ראה [_openCommentator]).
  Future<void> _showCommentatorsMenu(
    GlobalKey buttonKey,
    List<_CommentatorEntry> commentators,
  ) async {
    if (commentators.isEmpty) return;
    final visibilityRevision = _visibilityRevision;

    final buttonContext = buttonKey.currentContext;
    if (buttonContext == null || !buttonContext.mounted) return;

    final selected = await showAnchoredAppMenu<_CommentatorEntry>(
      context: context,
      anchorContext: buttonContext,
      minWidth: 220,
      itemsBuilder: (metrics) => [
        for (final e in commentators)
          buildAppPopupMenuItem<_CommentatorEntry>(
            context,
            AppMenuEntry(value: e, label: e.title),
            metrics,
            null,
          ),
      ],
    );

    if (selected == null ||
        !mounted ||
        visibilityRevision != _visibilityRevision) {
      return;
    }
    if (const HiddenLibraryStore().load() != _lastVisibilitySelection ||
        !_bookIndexes.allowsCommentator(selected.title, selected.bookId)) {
      return;
    }
    _openCommentator(selected);
  }

  /// פותח את ספר המפרש מתוך רשומה שהוכנה מראש: ה-`book` כבר ידוע, וה-
  /// `targetSegment` נלקח מה-[entry] (ה-`targetLineIndex` של ה-DB). אם חסר
  /// (row חריג) נפתח בתחילת ספר המפרש — לא ב-`ref.segment`, שהוא אינדקס בספר
  /// המקור וחסר משמעות בספר המפרש. הקליק סינכרוני לחלוטין — אין `await`, אין
  /// שאילתות DB ואין מעבר על עץ הספרייה בזמן הקליק.
  void _openCommentator(_CommentatorEntry entry) {
    _rememberCurrentQuery();
    final segment = entry.targetSegment ?? 0;
    Navigator.of(context).pop();
    openBook(
      context,
      entry.book,
      segment,
      '',
      explicitIndex: true,
      navigateToPositionIfReused: true,
    );
  }

  /// בודק אם מחרוזת היא קישור otzaria:// או zayit:// תקין וניתן לפענוח.
  static bool _isDeepLinkText(String text) {
    final trimmed = text.trim().toLowerCase();
    if (!trimmed.startsWith('otzaria://') && !trimmed.startsWith('zayit://')) {
      return false;
    }
    final uri = Uri.tryParse(text.trim());
    if (uri == null) return false;
    return ExternalUriRouter.parseUri(uri) != null;
  }

  /// מנסה לטפל בקישור ישיר — מחזיר true אם הטיפול הצליח.
  /// השדה מנוקה ודיאלוג נסגר רק לאחר אימות הצלחת הטיפול.
  Future<bool> _tryHandleDeepLink(String text) async {
    final uri = Uri.tryParse(text.trim());
    if (uri == null) return false;
    final normalized = ExternalUriRouter.normalizeUri(uri);
    if (normalized == null) return false;
    final action = ExternalUriRouter.parseUri(normalized);
    if (action == null) return false;
    // ניתוב דרך המסך הראשי סוגר את הדיאלוג, והקוד שלמטה סוגר שוב את שמתחתיו.
    if (action is RunDetectionAction) {
      _applySuggestion(action.query);
      return true;
    }

    final handled = await _host.handleDeepLink(normalized.toString());

    if (handled && mounted) {
      final focusRepository = context.read<FocusRepository>();
      focusRepository.findRefSearchController.clear();
      BlocProvider.of<FindRefBloc>(context).add(const SearchRefRequested(''));
      BlocProvider.of<FindRefBloc>(context).add(ClearSearchRequested());
      Navigator.of(context).pop();
    }
    return handled;
  }

  /// פותח את דיאלוג החיפוש עם [query] מוכן בשדה — ללא הרצת חיפוש.
  void _openTextSearch(String query) => _host.openTextSearch(query);

  /// חלון הדוגמאות של הפתיחה הנוכחית — מתקדם בכל פתיחה.
  List<String> _rotatedExamples() {
    final offset = _examplesOffset;
    _examplesOffset = (offset + _suggestionCount) % _referenceExamples.length;
    return [
      for (var i = 0; i < _suggestionCount; i++)
        _referenceExamples[(offset + i) % _referenceExamples.length],
    ];
  }

  /// ממלא את השדה בהצעה ומריץ עליה איתור מיידי.
  void _applySuggestion(String suggestion) {
    final focusRepository = context.read<FocusRepository>();
    final controller = focusRepository.findRefSearchController;
    controller.text = suggestion;
    controller.selection = TextSelection.collapsed(offset: suggestion.length);
    _dispatchSearch(suggestion);
    focusRepository.findRefSearchFocusNode.requestFocus();
  }

  void _retrySearch() {
    _pendingEnter = false;
    final query = context.read<FocusRepository>().findRefSearchController.text;
    context.read<FindRefBloc>().add(
      SearchRefRequested(query, includePersonalBooks: _includePersonalBooks),
    );
  }

  /// שומר כאיתור אחרון את השאילתה שהניבה את התוצאות שנפתחו — ולא את מה
  /// שמוקלד בשדה, שעשוי כבר להיות טקסט חדש שטרם רץ.
  void _rememberCurrentQuery() {
    final state = context.read<FindRefBloc>().state;
    if (state is! FindRefSuccess) return;
    FindRefRecentStore.remember(state.query);
  }

  // ── שכבת התצוגה ─────────────────────────────────────────────────────

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: TextStyle(
        // ui-lint: allow UIL-017 — כותרת קטנה 13 של דיאלוג החיפוש ואיתור המקורות נשארת (DD-14, השלמה 2.11)
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: Theme.of(context).colorScheme.primary,
      ),
    );
  }

  /// כרטיס ההקלדה: שדה המקור, מתג הספרים האישיים ומספר התוצאות.
  Widget _buildQueryCard(FindRefState state, bool isShort) {
    final colorScheme = Theme.of(context).colorScheme;
    final isLoading = state is FindRefLoading;
    final refs = identical(state, _supersededVisibilityState)
        ? const <DbReferenceResult>[]
        : state is FindRefSuccess
        ? state.refs
        : (isLoading ? _shownRefs : const <DbReferenceResult>[]);
    return Container(
      padding: EdgeInsets.all(isShort ? 12 : 16),
      decoration: BoxDecoration(
        color: AppSurfaces.card(context),
        borderRadius: AppTokens.borderRadiusAll,
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!isShort) ...[
            _sectionLabel(context.settingsText('מה לאתר')),
            const SizedBox(height: 8),
          ],
          ListenableBuilder(
            listenable: PluginSearchFieldActionsRegistry.instance,
            builder: (context, _) => _buildQueryField(
              isLoading ? const <DbReferenceResult>[] : refs,
            ),
          ),
          TypingLayoutFixSuggestion(
            controller: context.read<FocusRepository>().findRefSearchController,
            fieldFocusNode: context
                .read<FocusRepository>()
                .findRefSearchFocusNode,
            hint: context.settingsText('לחיצה תחליף את הטקסט שהוקלד'),
            onApplied: _dispatchSearch,
          ),
          SizedBox(height: isShort ? 8 : 10),
          // Wrap ולא Row: בגופן מוגדל הספירה יורדת לשורה שנייה.
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              _buildPersonalBooksToggle(),
              if (isLoading)
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              if (refs.isNotEmpty)
                Text(
                  refs.length == 1
                      ? context.settingsText('מקור אחד')
                      : context.settingsText(
                          '{count} מקורות',
                          args: {'count': refs.length},
                        ),
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQueryField(List<DbReferenceResult> refs) {
    final focusRepository = context.read<FocusRepository>();
    final controller = focusRepository.findRefSearchController;
    final colorScheme = Theme.of(context).colorScheme;

    return Focus(
      onKeyEvent: (node, event) {
        // טיפול גם ב-KeyDownEvent וגם ב-KeyRepeatEvent (לחיצה רצופה)
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }

        if (refs.isEmpty) return KeyEventResult.ignored;
        final key = event.logicalKey;
        final current = _selectedIndex.value;
        // Home/End (גם Ctrl+Shift לבחירה) שייכים לשדה; Ctrl לבדו — לרשימה.
        final keyboard = HardwareKeyboard.instance;
        final ctrlOnly = keyboard.isControlPressed && !keyboard.isShiftPressed;
        final int? target = switch (key) {
          LogicalKeyboardKey.arrowDown => current + 1,
          LogicalKeyboardKey.arrowUp => current - 1,
          LogicalKeyboardKey.pageDown =>
            current + _resultsPageStep(refs.length),
          LogicalKeyboardKey.pageUp => current - _resultsPageStep(refs.length),
          LogicalKeyboardKey.home when ctrlOnly => 0,
          LogicalKeyboardKey.end when ctrlOnly => refs.length - 1,
          _ => null,
        };
        if (target == null) return KeyEventResult.ignored;
        _selectedIndex.value = target.clamp(0, refs.length - 1);
        _scrollToSelected(count: refs.length);
        return KeyEventResult.handled;
      },
      child: RtlTextField(
        focusNode: focusRepository.findRefSearchFocusNode,
        autofocus: true,
        controller: controller,
        decoration: InputDecoration(
          filled: true,
          fillColor: colorScheme.surfaceContainerHigh,
          labelText: context.settingsText('מקור'),
          hintText: context.settingsText('לדוגמה: בראשית פרק א'),
          prefixIcon: const Icon(FluentIcons.search_24_regular),
          suffixIcon: _buildSuffix(controller),
        ),
        // ה-debounce מבוצע בבלוק, כך שכל הקלדה מבטלת מיד גם חיפוש שכבר רץ.
        onChanged: _dispatchSearch,
        onSubmitted: _onSubmitted,
      ),
    );
  }

  void _onSubmitted(String value) {
    // ניסיון לטפל בקישור ישיר — אם זה קישור, ייפתח ישירות
    if (_isDeepLinkText(value)) {
      _tryHandleDeepLink(value);
      return;
    }
    // תוצאות של שאילתה קודמת אינן נפתחות: Enter ממתין לתוצאות החדשות.
    final state = context.read<FindRefBloc>().state;
    if (!_isCurrentSuccess(state)) {
      // במצב שגיאה אין תוצאות שבדרך — פתיחה ממתינה הייתה קופצת בניסיון חוזר.
      _pendingEnter =
          value.length >= 2 &&
          (state is FindRefLoading ||
              state is FindRefSuccess ||
              state is FindRefInitial);
      return;
    }
    final current = (state as FindRefSuccess).refs;
    if (current.isNotEmpty) {
      _openRef(
        current[_selectedIndex.value.clamp(0, current.length - 1)],
      );
    }
  }

  /// כפתורי תוספים (כשיש) ולצידם כפתור הניקוי; null כשאין אף אחד מהם.
  Widget? _buildSuffix(TextEditingController controller) {
    final hasPluginActions = PluginSearchFieldActionsRegistry.instance
        .hasActionsFor(PluginSearchField.findRef);
    if (_queryIsEmpty && !hasPluginActions) return null;
    final clear = _queryIsEmpty
        ? null
        : OtzariaSearchClearButton(
            controller: controller,
            onCleared: () {
              // קודם מבטלים חיפוש שעדיין רץ (restartable יקטוף
              // את ה-handler הקודם), ורק אחר-כך מחזירים את
              // ה-state ל-Initial.
              BlocProvider.of<FindRefBloc>(
                context,
              ).add(const SearchRefRequested(''));
              BlocProvider.of<FindRefBloc>(
                context,
              ).add(ClearSearchRequested());
              _selectedIndex.value = 0;
              _pendingEnter = false;
            },
          );
    if (!hasPluginActions) return clear;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        PluginSearchFieldActions(
          field: PluginSearchField.findRef,
          controller: controller,
          onChanged: _dispatchSearch,
          onSubmitted: _onSubmitted,
        ),
        ?clear,
      ],
    );
  }

  /// מתג גלולה קומפקטי, באותה שפה כמו מתגי דיאלוג החיפוש.
  Widget _buildPersonalBooksToggle() {
    return AppTogglePill(
      label: context.settingsText('כלול ספרים אישיים'),
      tooltip: _includePersonalBooks
          ? context.settingsText('האיתור כולל גם ספרים שהוספת בעצמך')
          : context.settingsText('הפעל כדי לאתר גם בספרים שהוספת בעצמך'),
      value: _includePersonalBooks,
      onChanged: (v) {
        // איפוס הסימון: סט התוצאות משתנה, ואינדקס ישן היה מפיל את פתיחת
        // התוצאה ב-Enter.
        setState(() => _includePersonalBooks = v);
        _selectedIndex.value = 0;
        FindRefPersonalBooksSetting.save(v);
        final text = context
            .read<FocusRepository>()
            .findRefSearchController
            .text;
        if (text.length >= 2) {
          _dispatchSearch(text, includePersonalBooks: v);
        }
      },
    );
  }

  /// אזור התוצאות: רשימה, מצב טעינה, מצב פתיחה ומצב ריק.
  Widget _buildResultsArea(double horizontalPadding) {
    return BlocConsumer<FindRefBloc, FindRefState>(
      // בלי ListView אין מי שישלח notification, ולכן בלי איפוס יזום החץ היה
      // נשאר דלוק מהחיפוש הקודם מעל spinner או מצב ריק.
      listener: (context, state) {
        if (!identical(state, _supersededVisibilityState)) {
          _supersededVisibilityState = null;
        }
        if (state is FindRefSuccess) {
          _shownRefs = state.refs;
        } else if (state is! FindRefLoading) {
          _shownRefs = const <DbReferenceResult>[];
        }
        if (_shownRefs.isEmpty && _hasMoreBelow.value) {
          _hasMoreBelow.value = false;
        }
        if (state is FindRefSuccess) {
          _syncPersonalBooksToggle();
          if (state.query != _resultsQuery) {
            _resultsQuery = state.query;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _resultsScrollController.hasClients) {
                _resultsScrollController.jumpTo(0);
              }
            });
          }
          _openPendingEnterIfCurrent(state);
        } else if (state is! FindRefLoading) {
          _pendingEnter = false;
        }
      },
      builder: (context, state) {
        if (identical(state, _supersededVisibilityState)) {
          return const _DelayedLoader();
        }
        if (state is FindRefLoading) {
          if (_shownRefs.isNotEmpty) {
            return _buildResultsList(_shownRefs, horizontalPadding);
          }
          return const _DelayedLoader();
        }
        if (state is FindRefNotReady) {
          return _buildNotReadyState();
        }
        if (state is FindRefLibraryMissing) {
          return _buildLibraryMissingState();
        }
        if (state is FindRefError) {
          return _buildErrorState(state.kind);
        }
        if (state is FindRefSuccess && state.refs.isNotEmpty) {
          return _buildResultsList(
            state.refs,
            horizontalPadding,
            source: state,
          );
        }
        final query = context
            .read<FocusRepository>()
            .findRefSearchController
            .text;
        if (state is FindRefSuccess && query.length >= 3) {
          return _buildEmptyState(context, query);
        }
        return _buildIdleState();
      },
    );
  }

  /// [source] — ה-state שהניב את [refs]; null בזמן טעינה, כשהרשימה ישנה.
  Widget _buildResultsList(
    List<DbReferenceResult> refs,
    double horizontalPadding, {
    FindRefSuccess? source,
  }) {
    final rowInputs = Listenable.merge([_selectedIndex, _typedQuery]);
    return NotificationListener<ScrollMetricsNotification>(
      // תופס את החיבור הראשון של ה-ListView וכל שינוי maxScrollExtent; העדכון
      // נדחה לסוף ה-frame כדי לא לשנות ValueNotifier בזמן build.
      onNotification: (_) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _updateHasMoreBelow();
        });
        return false;
      },
      child: ListView.builder(
        controller: _resultsScrollController,
        padding: EdgeInsets.fromLTRB(
          horizontalPadding,
          0,
          horizontalPadding,
          8,
        ),
        itemCount: refs.length,
        itemBuilder: (context, index) => ListenableBuilder(
          key: _getKeyForIndex(index),
          listenable: rowInputs,
          builder: (context, _) => _buildResultTile(
            refs[index],
            index,
            isSelected: index == _selectedIndex.value,
            interactive: source != null && _isCurrentSuccess(source),
          ),
        ),
      ),
    );
  }

  Widget _buildResultTile(
    DbReferenceResult ref,
    int index, {
    required bool isSelected,
    required bool interactive,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final eligible = !ref.isPdf && ref.bookId > 0 && ref.source.isOfficial;
    if (eligible && interactive) _requestCommentatorsAfterFrame(index);
    final cached = _commentatorsByRef[_commentatorsKey(ref)];
    final showButton = eligible && cached != null && cached.isNotEmpty;
    final menuButtonKey = _getCommentatorsButtonKey(index);

    // Material (ולא Container צבוע) כדי שהצבע והריפל של ה-ListTile ייראו —
    // ListTile מצייר אותם על ה-Material הקרוב, ורקע שמעליו מסתיר אותם.
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: isSelected
            ? AppSurfaces.selectedRow(colorScheme)
            : AppSurfaces.card(context),
        shape: RoundedRectangleBorder(
          borderRadius: AppTokens.borderRadiusAll,
          side: BorderSide(
            color: isSelected
                ? colorScheme.primary
                : colorScheme.outlineVariant,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          selected: isSelected,
          // selected צובע את כפתור המפרשים ב-primary; שומרים על צבעו הרגיל.
          selectedColor: colorScheme.onSurfaceVariant,
          hoverColor: showButton ? Colors.transparent : null,
          visualDensity: VisualDensity.compact,
          contentPadding: const EdgeInsetsDirectional.fromSTEB(12, 4, 8, 4),
          leading: Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isSelected
                  ? colorScheme.primaryContainer
                  : colorScheme.surfaceContainerHigh,
              borderRadius: AppTokens.borderRadiusAll,
            ),
            child: _buildResultIcon(
              ref,
              isSelected
                  ? colorScheme.onPrimaryContainer
                  : colorScheme.onSurfaceVariant,
            ),
          ),
          // reference ארוך (למשל AltToc עם שם הספר כתחילית) היה מותח שורה
          // אחת על פני כל אזור התוצאות.
          title: LibraryOverflowTooltipText(
            text: ref.reference,
            maxLines: 2,
            style: TextStyle(
              fontSize: 15,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              color: colorScheme.onSurface,
            ),
          ),
          subtitle: ref.bookPath.isEmpty
              ? null
              : LibraryOverflowTooltipText(
                  text: ref.bookPath,
                  maxLines: 1,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
          // רשימת המפרשים נטענת אחרי הרינדור, ולכן הופעת הכפתור הייתה מצמצמת
          // את רוחב הכותרת ומזיזה את הטקסט. השורה שומרת את מקומו מהפריים
          // הראשון לפי `eligible`, שידוע סינכרונית.
          trailing: eligible
              ? Visibility(
                  visible: showButton,
                  maintainSize: true,
                  maintainAnimation: true,
                  maintainState: true,
                  child: IconButton(
                    key: menuButtonKey,
                    icon: const Icon(FluentIcons.library_24_regular),
                    tooltip: context.settingsText('הצג מפרשים זמינים'),
                    onPressed: interactive && showButton
                        ? () => _showCommentatorsMenu(menuButtonKey, cached)
                        : null,
                  ),
                )
              : null,
          onTap: interactive ? () => _openRef(ref) : null,
        ),
      ),
    );
  }

  /// אייקון סוג המקור, כמו ברשימות הספרייה.
  Widget _buildResultIcon(DbReferenceResult ref, Color color) {
    return Icon(
      bookFormatIconFor(
        path: ref.filePath,
        fileType: ref.fileType,
        isPersonal: !ref.source.isOfficial,
        isPdf: ref.isPdf,
      ),
      size: 20,
      color: color,
    );
  }

  /// תווית מעל ההצעות — מבדילה בין איתורים אחרונים לדוגמאות, ומאפשרת
  /// לנקות את האחרונים (issue #1288).
  Widget _buildSuggestionsLabel(ColorScheme colorScheme) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          _suggestionsAreRecent
              ? FluentIcons.history_24_regular
              : FluentIcons.lightbulb_24_regular,
          size: 14,
          color: colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 4),
        Text(
          _suggestionsAreRecent
              ? context.settingsText('האיתורים האחרונים')
              : context.settingsText('דוגמאות'),
          style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
        ),
        if (_suggestionsAreRecent)
          IconButton(
            tooltip: context.settingsText('נקה'),
            icon: const Icon(FluentIcons.dismiss_16_regular, size: 14),
            color: colorScheme.onSurfaceVariant,
            visualDensity: VisualDensity.compact,
            onPressed: _clearRecentSuggestions,
          ),
      ],
    );
  }

  void _clearRecentSuggestions() {
    FindRefRecentStore.clear();
    setState(() {
      _suggestionsAreRecent = false;
      _suggestions = _rotatedExamples();
    });
  }

  void _forgetRecentSuggestion(String suggestion) {
    FindRefRecentStore.forget(suggestion);
    final remaining = FindRefRecentStore.load();
    if (remaining.isEmpty) {
      _clearRecentSuggestions();
      return;
    }
    setState(() {
      _suggestions = remaining.take(_suggestionCount).toList();
    });
  }

  /// מצב פתיחה: מסביר מה מקלידים, ומציע את האיתורים האחרונים — ובהיעדרם
  /// דוגמאות מתחלפות.
  Widget _buildIdleState() {
    final colorScheme = Theme.of(context).colorScheme;
    return CenteredScrollableState(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colorScheme.secondaryContainer,
              borderRadius: AppTokens.borderRadiusAll,
            ),
            child: Icon(
              OtzariaIcons.book_search_24_filled,
              size: 28,
              color: colorScheme.onSecondaryContainer,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            context.settingsText('איתור מקור מדויק'),
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            context.settingsText(
              'הקלד שם ספר ומיקום בתוכו. ראשי תיבות נתמכים, וגם קישור ישיר '
              'שהודבק לשדה ייפתח מכאן.',
            ),
            style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          _buildSuggestionsLabel(colorScheme),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              for (final suggestion in _suggestions)
                if (_suggestionsAreRecent)
                  InputChip(
                    label: Text(suggestion),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _applySuggestion(suggestion),
                    deleteIcon: const Icon(FluentIcons.dismiss_12_regular),
                    deleteButtonTooltipMessage: context.settingsText('הסר'),
                    onDeleted: () => _forgetRecentSuggestion(suggestion),
                  )
                else
                  ActionChip(
                    label: Text(suggestion),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _applySuggestion(suggestion),
                  ),
            ],
          ),
        ],
      ),
    );
  }

  /// מצב ריק מעוצב: אייקון, הודעה ממוקדת וכפתור לפתיחת חיפוש טקסט.
  Widget _buildEmptyState(BuildContext context, String query) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDeepLink = _isDeepLinkText(query);

    return _buildCenteredState(
      icon: isDeepLink
          ? OtzariaIcons.link_24_regular
          : OtzariaIcons.search_not_found_24_regular,
      iconColor: colorScheme.onSurfaceVariant,
      title: isDeepLink
          ? context.settingsText('נראה שהכנסת קישור ישיר')
          : context.settingsText(
              'לא הצלחנו לאתר את הספר "{query}"',
              args: {'query': query},
            ),
      message: isDeepLink
          ? context.settingsText('לחץ על הכפתור לפתיחת הקישור')
          : context.settingsText(
              'נסה טקסט אחר לאיתור הספר המבוקש, או חפש את הטקסט עצמו במאגר',
            ),
      action: isDeepLink
          ? ActionButton.recommended(
              text: context.settingsText('פתיחת קישור'),
              onPressed: () => _tryHandleDeepLink(query),
              icon: OtzariaIcons.link_24_regular,
            )
          : ActionButton.recommended(
              text: context.settingsText('פתח חיפוש טקסט'),
              onPressed: () => _openTextSearch(query),
              icon: FluentIcons.search_24_regular,
            ),
    );
  }

  Widget _buildNotReadyState() {
    final colorScheme = Theme.of(context).colorScheme;
    return _buildCenteredState(
      icon: FluentIcons.library_24_regular,
      iconColor: colorScheme.onSurfaceVariant,
      title: context.settingsText('הספרייה עדיין נטענת'),
      message: context.settingsText('האיתור יהיה זמין בעוד רגע'),
      action: ActionButton.recommended(
        text: context.settingsText('נסה שוב'),
        onPressed: _retrySearch,
        icon: FluentIcons.arrow_clockwise_24_regular,
      ),
    );
  }

  Widget _buildLibraryMissingState() {
    return _buildCenteredState(
      icon: FluentIcons.library_24_regular,
      iconColor: Theme.of(context).colorScheme.onSurfaceVariant,
      title: context.settingsText('לא נמצאה ספרייה'),
      message: context.settingsText('האיתור יהיה זמין לאחר התקנת הספרייה'),
      // קובץ שנעדר רגעית (עדכון מלא, כונן רשת) לא צריך להשאיר את המסך תקוע.
      action: ActionButton.recommended(
        text: context.settingsText('נסה שוב'),
        onPressed: _retrySearch,
        icon: FluentIcons.arrow_clockwise_24_regular,
      ),
    );
  }

  Widget _buildErrorState(FindRefErrorKind kind) {
    return _buildCenteredState(
      icon: FluentIcons.error_circle_24_regular,
      iconColor: Theme.of(context).colorScheme.error,
      title: context.settingsText('האיתור נכשל'),
      message: switch (kind) {
        FindRefErrorKind.cancelled => context.settingsText(
          'החיפוש בוטל לפני שהסתיים',
        ),
        FindRefErrorKind.failed => context.settingsText(
          'אירעה שגיאה בזמן האיתור',
        ),
      },
      action: ActionButton.recommended(
        text: context.settingsText('נסה שוב'),
        onPressed: _retrySearch,
        icon: FluentIcons.arrow_clockwise_24_regular,
      ),
    );
  }

  Widget _buildCenteredState({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String message,
    Widget? action,
  }) {
    return OtzariaEmptyState(
      customIcon: Icon(icon, size: AppTokens.iconXL, color: iconColor),
      title: title,
      message: message,
      action: action,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
    );
  }

  Widget _buildFooter(bool isShort) {
    final colorScheme = Theme.of(context).colorScheme;
    // הרמז נכנס רק כשיש לו רוחב אמיתי, ובחלון נמוך הוא מפנה מקום לתוצאות.
    const keyboardHintMinWidth = 560.0;
    final showKeyboardHint =
        !isShort && MediaQuery.sizeOf(context).width >= keyboardHintMinWidth;
    return Padding(
      padding: isShort
          ? const EdgeInsetsDirectional.fromSTEB(16, 4, 12, 6)
          : const EdgeInsetsDirectional.fromSTEB(24, 8, 12, 12),
      child: Row(
        children: [
          if (showKeyboardHint)
            Expanded(
              child: Text(
                context.settingsText(
                  'Enter פותח את המקור המסומן, מקשי החצים מנווטים בין התוצאות',
                ),
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurfaceVariant,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            )
          else
            const Spacer(),
          _buildScrollToEndArrow(),
          const SizedBox(width: 8),
          ActionButton.neutral(
            text: context.settingsText('סגור'),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final screenSize = media.size;
    // insetPadding של Dialog מתווסף ל-viewInsets (המקלדת במובייל), ולכן
    // הגובה הפנוי נמדד אחרי הורדתם — אחרת הדיאלוג נחתך כשהמקלדת עולה.
    final maxHeight = screenSize.height - media.viewInsets.vertical - 24;
    final dialogHeight = math.min(
      maxHeight,
      (screenSize.height * 0.7).clamp(440.0, 560.0),
    );

    final isCompact = WindowClass.of(context).isCompact;
    final isShort = dialogHeight < 470;
    // מסך לרוחב בטלפון עם מקלדת פתוחה משאיר פחות מ-300: שם התחתית נסגרת
    // לטובת שדה ההקלדה (הסגירה זמינה ב-X שבכותרת ובלחיצה מחוץ לדיאלוג).
    final isTiny = dialogHeight < 300;
    final horizontalPadding = isCompact ? 12.0 : 16.0;

    // הפאנל בגובה קבוע, ולכן הגדלת גופן מעבר לכך הייתה דוחקת את הכותרת
    // והתחתית זו על זו. הכיתוב עדיין גדל, עד גבול שהפריסה נושאת.
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.6,
      child: AppDialogFrame(
        surfaceKey: TourTargetKeys.of(context).findRefDialog,
        icon: OtzariaIcons.book_search_24_filled,
        title: context.settingsText('איתור מקורות'),
        subtitle: isShort
            ? null
            : context.settingsText('הקלד מקור מדויק והספר ייפתח במקומו'),
        subtitleMaxLines: 1,
        size: AppDialogSize.large,
        height: dialogHeight,
        padding: EdgeInsets.zero,
        backgroundColor: AppSurfaces.panelBackground(context),
        child: LayoutBuilder(
          builder: (context, body) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // חסם הגובה מבטיח שגם בגופן מוגדל אזור ההקלדה יגלול בתוך
              // עצמו במקום לדחוק את רשימת התוצאות אל מחוץ לדיאלוג. בחלון
              // נמוך מאוד (מקלדת פתוחה) הגוף שמתחת לרצועה הוא המגבלה.
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: math.min(
                    dialogHeight * 0.5,
                    body.maxHeight * 0.6,
                  ),
                ),
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    isShort ? 10 : 16,
                    horizontalPadding,
                    isShort ? 8 : 12,
                  ),
                  child: BlocBuilder<FindRefBloc, FindRefState>(
                    builder: (context, state) =>
                        _buildQueryCard(state, isShort),
                  ),
                ),
              ),
              Expanded(child: _buildResultsArea(horizontalPadding)),
              if (!isTiny) ...[const Divider(height: 1), _buildFooter(isShort)],
            ],
          ),
        ),
      ),
    );
  }
}

/// מציג spinner רק אחרי עיכוב קצר — מונע הבהוב על חיפושים מהירים.
class _DelayedLoader extends StatefulWidget {
  const _DelayedLoader();

  @override
  State<_DelayedLoader> createState() => _DelayedLoaderState();
}

class _DelayedLoaderState extends State<_DelayedLoader> {
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) setState(() => _visible = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();
    return const Center(child: CircularProgressIndicator());
  }
}
