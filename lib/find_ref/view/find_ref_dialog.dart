import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
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
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/history/bloc/history_event.dart';
import 'package:otzaria/core/focus_repository.dart';
import 'package:otzaria/core/external_uri_router.dart';
import 'package:otzaria/core/windowing/settings_sync.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/find_ref/repository/find_ref_visibility.dart';
import 'package:otzaria/library/hidden/hidden_library_selection.dart';
import 'package:otzaria/library/hidden/hidden_library_store.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/book_source.dart';
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
import 'package:otzaria/utils/ui/reading_left_pane_policy.dart';
import 'package:otzaria/tour/tour_target_keys.dart';
import 'package:otzaria/library/view/grid_items.dart';
import 'package:otzaria/widgets/text/rtl_text_field.dart';
import 'package:otzaria/search/models/search_configuration.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria/navigation/view/main_window_screen.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';
import 'package:otzaria/widgets/layout/centered_scrollable_state.dart';
import 'package:otzaria/widgets/misc/rtl_icon.dart';

/// מה שהדיאלוג מבקש מהמסך הראשי — ניתוב קישורים ופתיחת חיפוש טקסט.
abstract interface class FindRefDialogHost {
  Future<bool> handleDeepLink(String uri);
  void openTextSearch(String query);
}

class _MainWindowFindRefHost implements FindRefDialogHost {
  const _MainWindowFindRefHost();

  @override
  Future<bool> handleDeepLink(String uri) async =>
      await mainWindowScreenKey.currentState?.handleInternalDeepLink(uri) ??
      false;

  @override
  void openTextSearch(String query) {
    final mainScreen = mainWindowScreenKey.currentState;
    if (mainScreen == null) {
      debugPrint('[FindRef] openTextSearch: main window screen not mounted');
      return;
    }
    mainScreen.openSearchDialog(
      SearchingTab(
        'חיפוש',
        query,
        initialConfiguration: const SearchConfiguration(),
      ),
    );
  }
}

class FindRefDialog extends StatefulWidget {
  const FindRefDialog({super.key, this.host = const _MainWindowFindRefHost()});

  final FindRefDialogHost host;

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

/// מפתח את עץ הספרייה במעבר אחד, כדי שפתרון ספרי המפרשים לא יסרוק את כל
/// העץ מחדש לכל מפרש. קטע בספר יסוד מגיע לעשרות מפרשים, וכל שורה נראית
/// מבקשת את שלה.
///
/// המפות נבנות בסדר ה-DFS של [findOfficialTextBookById] ושל
/// [_findBookInLibraryByTitle], עם `putIfAbsent`, ולכן כשכמה ספרים חולקים
/// מזהה או כותרת נבחר אותו ספר שהסריקות היו בוחרות.
@visibleForTesting
class LibraryBookIndex {
  LibraryBookIndex(this.library, {FindRefVisibility? visibility})
    : visibility = visibility ?? FindRefVisibility.empty() {
    _collect(library);
  }

  final Category library;
  final FindRefVisibility visibility;
  final Map<int, TextBook> _officialTextBookById = {};
  final Map<String, TextBook> _textBookByTitle = {};
  final Map<String, Book> _bookByTitle = {};

  void _collect(Category category) {
    for (final book in category.books) {
      if (!visibility.allowsBook(book)) continue;
      final id = book.id;
      if (book is TextBook) {
        if (book.source.isOfficial && id != null) {
          _officialTextBookById.putIfAbsent(id, () => book);
        }
        _textBookByTitle.putIfAbsent(book.title, () => book);
      }
      _bookByTitle.putIfAbsent(book.title, () => book);
    }
    for (final subCategory in category.subCategories) {
      _collect(subCategory);
    }
  }

  /// מאתר את ה-`Book` הנכון לפי [bookId] אם נמסר, ולפי [title] אם לא. הסיבה:
  /// שני ספרים יכולים לחלוק כותרת זהה (למשל גרסאות שונות של פירוש), וה-link
  /// משאילתת המפרשים יודע בדיוק לאיזה ספר ללכת — פתרון רק לפי title היה
  /// פותח את הראשון שנמצא בעץ.
  Book? resolveCommentatorBook(String title, {required int? bookId}) {
    if (bookId != null && bookId > 0) {
      final byId = _officialTextBookById[bookId];
      if (byId != null) return byId;
    }
    // fallback ל-title (תאימות לאחור עם DB שלא מחזיר targetBookId).
    return _textBookByTitle[title] ?? _bookByTitle[title];
  }
}

/// מאתר ספר טקסט רשמי לפי [bookId] מה-DB הראשי.
/// מזהי seforim.db אינם ייחודיים מול user_books.db ומול ייצוגי PDF בעץ —
/// ולכן ספרים אישיים וספרים שאינם TextBook מדולגים ולא מסתירים את היעד.
/// הספר בעל [bookId] במסד של [source] (אישי או מצורף), מכל סוג.
@visibleForTesting
Book? findBookBySourceAndId(Category category, int bookId, BookSource source) {
  for (final b in category.books) {
    if (b.source == source && b.id == bookId) return b;
  }
  for (final subCat in category.subCategories) {
    final found = findBookBySourceAndId(subCat, bookId, source);
    if (found != null) return found;
  }
  return null;
}

@visibleForTesting
TextBook? findOfficialTextBookById(Category category, int bookId) {
  for (final b in category.books) {
    if (b is TextBook && b.source.isOfficial && b.id == bookId) return b;
  }
  for (final subCat in category.subCategories) {
    final found = findOfficialTextBookById(subCat, bookId);
    if (found != null) return found;
  }
  return null;
}

Book? _findBookInLibraryByTitle(
  Category category,
  String title, {
  bool preferTextBook = false,
  required FindRefVisibility visibility,
}) {
  // עוברים פעמיים אם preferTextBook: ראשונה — רק TextBook; שנייה — כל סוג.
  for (final passOnlyText in preferTextBook ? [true, false] : [false]) {
    final result = _findBookInLibraryByTitlePass(
      category,
      title,
      onlyTextBook: passOnlyText,
      visibility: visibility,
    );
    if (result != null) return result;
  }
  return null;
}

Book? _findBookInLibraryByTitlePass(
  Category category,
  String title, {
  required bool onlyTextBook,
  required FindRefVisibility visibility,
}) {
  for (final b in category.books) {
    if (b.title != title) continue;
    if (onlyTextBook && b is! TextBook) continue;
    if (!b.source.isOfficial || !visibility.allowsBook(b)) continue;
    return b;
  }
  for (final subCat in category.subCategories) {
    final found = _findBookInLibraryByTitlePass(
      subCat,
      title,
      onlyTextBook: onlyTextBook,
      visibility: visibility,
    );
    if (found != null) return found;
  }
  return null;
}

@visibleForTesting
Book? resolveFindRefBookInLibrary(
  Category category,
  String title, {
  required int? bookId,
  required BookSource source,
  required FindRefVisibility visibility,
  bool preferTextBook = false,
}) {
  if (bookId != null) {
    final byId = source.isOfficial
        ? findOfficialTextBookById(category, bookId)
        : findBookBySourceAndId(category, bookId, source);
    if (byId != null) return visibility.allowsBook(byId) ? byId : null;
    if (!source.isOfficial) return null;
  }
  return _findBookInLibraryByTitle(
    category,
    title,
    preferTextBook: preferTextBook,
    visibility: visibility,
  );
}

class _FindRefDialogState extends State<FindRefDialog> {
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

  /// תקף כל עוד רענון ספרייה יוצר מופע `Category` חדש (`DataRepository.library`).
  LibraryBookIndex? _bookIndex;
  StreamSubscription<String>? _visibilityChanges;
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

  @override
  void initState() {
    super.initState();
    final hiddenStore = const HiddenLibraryStore();
    _lastVisibilitySelection = hiddenStore.load();
    _localVisibilityChanges = hiddenStore.changes.listen(
      (_) => _refreshVisibilityIfChanged(),
    );

    _visibilityChanges = SettingsSync.instance.changes.listen((key) {
      if (key.isNotEmpty &&
          key != HiddenLibraryStore.bookKeysSetting &&
          key != HiddenLibraryStore.categoryPathsSetting) {
        return;
      }
      _refreshVisibilityIfChanged();
    });

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
    final controller = FocusRepository().findRefSearchController;
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
    _focusRestorer = FocusRepository().registerActiveRestorer(
      restore: () {
        if (mounted) FocusRepository().findRefSearchFocusNode.requestFocus();
      },
      canRestore: () =>
          mounted &&
          FocusRepository().findRefSearchFocusNode.canRequestFocus &&
          (ModalRoute.of(context)?.isCurrent ?? false),
    );

    // listener מטפל בגלילה ידנית של המשתמש. עבור חיבור ראשון ולכל שינוי
    // ב-maxScrollExtent (סט תוצאות חדש) משתמשים ב-NotificationListener
    // ליד ה-ListView (ב-build).
    _resultsScrollController.addListener(_updateHasMoreBelow);
  }

  @override
  void dispose() {
    _visibilityChanges?.cancel();
    _localVisibilityChanges?.cancel();
    _resultsScrollController.removeListener(_updateHasMoreBelow);
    _resultsScrollController.dispose();
    _hasMoreBelow.dispose();
    FocusRepository().findRefSearchController.removeListener(
      _onQueryTextChanged,
    );
    _selectedIndex.dispose();
    _typedQuery.dispose();
    final restorer = _focusRestorer;
    if (restorer != null) FocusRepository().unregisterActiveRestorer(restorer);
    super.dispose();
  }

  /// כפתור הניקוי תלוי רק בשאלה אם השדה ריק — בנייה מחדש רק כשזה מתהפך.
  void _onQueryTextChanged() {
    final text = FocusRepository().findRefSearchController.text;
    _typedQuery.value = FindRefBloc.normalizeQuery(text);
    final isEmpty = text.isEmpty;
    if (isEmpty != _queryIsEmpty && mounted) {
      setState(() => _queryIsEmpty = isEmpty);
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

  void _refreshVisibilityIfChanged() {
    if (!mounted) return;
    final selection = const HiddenLibraryStore().load();
    if (selection == _lastVisibilitySelection) return;
    _lastVisibilitySelection = selection;
    final query = FocusRepository().findRefSearchController.text;
    _visibilityRevision++;
    final bloc = context.read<FindRefBloc>();
    _supersededVisibilityState = bloc.state is FindRefSuccess
        ? bloc.state
        : null;
    setState(() {
      _bookIndex = null;
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
      '${ref.bookId}:${ref.sourceLineId}:${ref.isAltToc ? 1 : 0}'
      ':${ref.tocLevel}:${ref.segment.toInt()}';

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
        final library = await DataRepository.instance.library;
        if (!mounted || visibilityRevision != _visibilityRevision) return;
        final index = _indexFor(library);
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
      if (!mounted) return;
      final state = context.read<FindRefBloc>().state;
      if (!_isCurrentSuccess(state)) return;
      final refs = (state as FindRefSuccess).refs;
      for (final index in rows) {
        if (index < refs.length) _ensureCommentatorsLoaded(refs[index]);
      }
    });
  }

  LibraryBookIndex _indexFor(Library library) {
    final selection = const HiddenLibraryStore().load();
    final existing = _bookIndex;
    if (existing != null &&
        identical(existing.library, library) &&
        existing.visibility.selection == selection) {
      return existing;
    }
    return _bookIndex = LibraryBookIndex(
      library,
      visibility: FindRefVisibility(selection, library),
    );
  }

  void _scrollToSelected() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final key = _getKeyForIndex(_selectedIndex.value);
      final context = key.currentContext;
      if (context != null) {
        Scrollable.ensureVisible(
          context,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          alignment: 0.5, // מרכז המסך
        );
      }
    });
  }

  /// חץ הגלילה לסוף הרשימה, לפי [_hasMoreBelow]. ה-IconButton נשאר במקומו
  /// ורק ה-opacity משתנה, כך שהפריסה לא זזה כשהחץ נכבה ונדלק.
  Widget _buildScrollToEndArrow() {
    return ValueListenableBuilder<bool>(
      valueListenable: _hasMoreBelow,
      builder: (context, hasMore, _) {
        return AnimatedOpacity(
          opacity: hasMore ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 150),
          child: IgnorePointer(
            ignoring: !hasMore,
            child: IconButton(
              iconSize: 18,
              visualDensity: VisualDensity.compact,
              icon: const Icon(FluentIcons.chevron_down_24_regular),
              tooltip: context.settingsText('גלול לסוף הרשימה'),
              onPressed: () {
                _resultsScrollController.animateTo(
                  _resultsScrollController.position.maxScrollExtent,
                  duration: const Duration(milliseconds: 250),
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
    Book? book;
    var openAsPdf = ref.isPdf;
    var segment = ref.segment.toInt();

    if (ref.isPdf && ref.filePath.isNotEmpty) {
      // Use filePath directly — library search may return a same-titled text book
      book = PdfBook(title: ref.title, path: ref.filePath);
    } else {
      // אם המשתמש ביקש מפרש מסוים — חייבים TextBookTab, כי PdfBookTab אינו
      // מקבל commentators כלל.
      final needsTextBook =
          initialCommentators != null && initialCommentators.isNotEmpty;

      Library? library;
      try {
        library = await DataRepository.instance.library;
      } catch (e) {
        debugPrint('Error loading library: $e');
      }

      final visibility = library == null
          ? null
          : const HiddenLibraryStore().load().isEmpty
          ? FindRefVisibility.empty()
          : _indexFor(library).visibility;
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
          library != null &&
          ref.bookId > 0) {
        final sourceBook = findOfficialTextBookById(library, ref.bookId);
        if (sourceBook != null) {
          final target = await resolveTalmudBavliPdfBook(sourceBook);
          if (target != null) {
            if (!mounted) return;
            final tabsBloc = context.read<TabsBloc>();
            final navigationBloc = context.read<NavigationBloc>();
            final historyBloc = context.read<HistoryBloc>();
            Navigator.of(context).pop();
            // כמו ב-BookOpenCoordinator.openBook: שמירת מיקום הקריאה של הטאב
            // הנוכחי להיסטוריה לפני שהטאב הדחוי תופס את המוקד.
            if (tabsBloc.state.hasOpenTabs) {
              historyBloc.add(
                CaptureStateForHistory(tabsBloc.state.currentTab!),
              );
            }
            final openLeftPane = shouldAutoOpenReadingLeftPane();
            final coordinator = BookOpenCoordinator(
              tabsBloc: tabsBloc,
              historyBloc: historyBloc,
              navigationBloc: navigationBloc,
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

      if (library != null) {
        // ספרים אישיים: ה-`bookId` שלהם שייך ל-user_books.db ואין לו תאומים
        // ב-library object, לכן ניפול ל-title; ספר רשמי עם `bookId > 0`
        // נפתח דרך ה-id כדי שלא יחליף שני ספרים בעלי אותה כותרת.
        book = resolveFindRefBookInLibrary(
          library,
          ref.title,
          bookId: ref.bookId > 0 ? ref.bookId : null,
          source: ref.source,
          preferTextBook: needsTextBook,
          visibility: visibility!,
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

    final overlayBox =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final box = buttonContext.findRenderObject() as RenderBox;
    final topLeft = box.localToGlobal(Offset.zero, ancestor: overlayBox);
    final bottomRight = box.localToGlobal(
      box.size.bottomRight(Offset.zero),
      ancestor: overlayBox,
    );

    // אנו רוצים שה-popup ייפתח לכיוון שמאל פיזית: הקצה הימני של ה-popup
    // יסיים בקצה השמאלי של ה-button (=topLeft.dx) וה-popup יתפשט שמאלה.
    // ב-_PopupMenuRouteLayout, fork-1 נבחר כאשר position.left > position.right
    // ואז `x = size.width - position.right - childSize.width`. לכן:
    //   position.right = overlayWidth - topLeft.dx → popup.right == button.left
    //   position.left  = overlayWidth (max possible) → ensures fork-1
    final position = RelativeRect.fromLTRB(
      overlayBox.size.width.toDouble(),
      bottomRight.dy,
      overlayBox.size.width - topLeft.dx,
      overlayBox.size.height - bottomRight.dy,
    );

    final selected = await showMenu<_CommentatorEntry>(
      context: context,
      position: position,
      constraints: const BoxConstraints(maxHeight: 400, minWidth: 220),
      items: [
        for (final e in commentators)
          PopupMenuItem<_CommentatorEntry>(
            value: e,
            child: Text(
              e.title,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
    );

    if (selected == null ||
        !mounted ||
        visibilityRevision != _visibilityRevision) {
      return;
    }
    if (const HiddenLibraryStore().load() != _lastVisibilitySelection ||
        !(_bookIndex?.visibility.allowsCommentator(
              selected.title,
              selected.bookId,
            ) ??
            false)) {
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
    openBook(context, entry.book, segment, '');
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

    final handled = await widget.host.handleDeepLink(normalized.toString());

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
  void _openTextSearch(String query) => widget.host.openTextSearch(query);

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
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: Theme.of(context).colorScheme.primary,
      ),
    );
  }

  Widget _buildHeader(bool isShort) {
    final colorScheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: AppSurfaces.card(context),
      child: Padding(
        padding: isShort
            ? const EdgeInsetsDirectional.fromSTEB(16, 8, 8, 8)
            : const EdgeInsetsDirectional.fromSTEB(24, 16, 12, 14),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(isShort ? 7 : 9),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: AppTokens.borderRadiusAll,
              ),
              child: Icon(
                OtzariaIcons.book_search_24_filled,
                size: isShort ? 18 : 22,
                color: colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.settingsText('איתור מקורות'),
                    style: TextStyle(
                      fontSize: isShort ? 17 : 20,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (!isShort) ...[
                    const SizedBox(height: 2),
                    Text(
                      context.settingsText(
                        'הקלד מקור מדויק והספר ייפתח במקומו',
                      ),
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            IconButton(
              icon: const Icon(FluentIcons.dismiss_24_regular),
              onPressed: () => Navigator.of(context).pop(),
              tooltip: context.settingsText('סגור'),
              // 48x48 של ברירת המחדל קובעים לבדם את גובה הכותרת בחלון נמוך.
              visualDensity: isShort ? VisualDensity.compact : null,
              constraints: isShort
                  ? const BoxConstraints(minWidth: 32, minHeight: 32)
                  : null,
            ),
          ],
        ),
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
          _buildQueryField(isLoading ? const <DbReferenceResult>[] : refs),
          TypingLayoutFixSuggestion(
            controller: context.read<FocusRepository>().findRefSearchController,
            fieldFocusNode: context
                .read<FocusRepository>()
                .findRefSearchFocusNode,
            hint: context.settingsText('לחיצה תחליף את הטקסט שהוקלד'),
            onApplied: _dispatchSearch,
          ),
          SizedBox(height: isShort ? 8 : 10),
          // Wrap ולא Row: ה-Switch אינו מתכווץ (Transform.scale משפיע על
          // הציור בלבד), ולכן בגופן מוגדל השורה הייתה גולשת. כאן הספירה
          // יורדת לשורה שנייה במקום.
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

        // טיפול בחיצים רק אם יש תוצאות
        if (refs.isNotEmpty) {
          if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
            _selectedIndex.value = (_selectedIndex.value + 1).clamp(
              0,
              refs.length - 1,
            );
            _scrollToSelected();
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
            _selectedIndex.value = (_selectedIndex.value - 1).clamp(
              0,
              refs.length - 1,
            );
            _scrollToSelected();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: RtlTextField(
        focusNode: focusRepository.findRefSearchFocusNode,
        autofocus: true,
        controller: controller,
        decoration: InputDecoration(
          filled: true,
          fillColor: colorScheme.surfaceContainerHigh,
          border: const OutlineInputBorder(),
          labelText: context.settingsText('מקור'),
          hintText: context.settingsText('לדוגמה: בראשית פרק א'),
          prefixIcon: const Icon(FluentIcons.search_24_regular),
          suffixIcon: _queryIsEmpty
              ? null
              : IconButton(
                  icon: const Icon(FluentIcons.dismiss_24_regular),
                  tooltip: context.settingsText('נקה'),
                  onPressed: () {
                    controller.clear();
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
                ),
        ),
        // ה-debounce מבוצע בבלוק, כך שכל הקלדה מבטלת מיד גם חיפוש שכבר רץ.
        onChanged: _dispatchSearch,
        onSubmitted: (value) {
          // ניסיון לטפל בקישור ישיר — אם זה קישור, ייפתח ישירות
          if (_isDeepLinkText(value)) {
            _tryHandleDeepLink(value);
            return;
          }
          // תוצאות של שאילתה קודמת אינן נפתחות: Enter ממתין לתוצאות החדשות.
          final state = context.read<FindRefBloc>().state;
          if (!_isCurrentSuccess(state)) {
            _pendingEnter = value.length >= 2;
            return;
          }
          final current = (state as FindRefSuccess).refs;
          if (current.isNotEmpty) {
            _openRef(
              current[_selectedIndex.value.clamp(0, current.length - 1)],
            );
          }
        },
      ),
    );
  }

  /// מתג גלולה קומפקטי, באותה שפה כמו מתגי דיאלוג החיפוש.
  Widget _buildPersonalBooksToggle() {
    final colorScheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: _includePersonalBooks
          ? context.settingsText('האיתור כולל גם ספרים שהוספת בעצמך')
          : context.settingsText('הפעל כדי לאתר גם בספרים שהוספת בעצמך'),
      child: Container(
        decoration: BoxDecoration(
          color: AppSurfaces.togglePill(
            colorScheme,
            active: _includePersonalBooks,
          ),
          borderRadius: AppTokens.borderRadiusAll,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                context.settingsText('כלול ספרים אישיים'),
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: _includePersonalBooks
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Transform.scale(
              scale: 0.75,
              child: Switch(
                value: _includePersonalBooks,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onChanged: (v) {
                  // איפוס הסימון: סט התוצאות משתנה, ואינדקס ישן היה מפיל
                  // את פתיחת התוצאה ב-Enter.
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
              ),
            ),
          ],
        ),
      ),
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
          if (state.query != _resultsQuery) {
            _resultsQuery = state.query;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _resultsScrollController.hasClients) {
                _resultsScrollController.jumpTo(0);
              }
            });
          }
          if (_pendingEnter && _isCurrentSuccess(state)) {
            _pendingEnter = false;
            if (state.refs.isNotEmpty) _openRef(state.refs.first);
          }
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
            ? AppSurfaces.selectedItem(colorScheme)
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

  /// אייקון סוג המקור — ספר, כותרת-משנה, PDF, ספר אישי או ספר ממסד מצורף.
  Widget _buildResultIcon(DbReferenceResult ref, Color color) {
    if (ref.isPdf) {
      return Icon(FluentIcons.document_pdf_24_regular, size: 20, color: color);
    }
    if (ref.source.isAttached) {
      return Icon(FluentIcons.database_24_regular, size: 20, color: color);
    }
    if (ref.isUserBook) {
      return Icon(FluentIcons.person_24_regular, size: 20, color: color);
    }
    if (ref.isAltToc) {
      return Icon(
        FluentIcons.text_bullet_list_24_regular,
        size: 20,
        color: color,
      );
    }
    return RtlIcon(FluentIcons.book_24_regular, size: 20, color: color);
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
          ? OtzariaIcons.links_24_regular
          : FluentIcons.document_search_24_regular,
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
              icon: OtzariaIcons.links_24_regular,
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
    final colorScheme = Theme.of(context).colorScheme;
    return CenteredScrollableState(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 52, color: iconColor),
          const SizedBox(height: 16),
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: TextStyle(fontSize: 14, color: colorScheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          if (action != null) ...[const SizedBox(height: 20), action],
        ],
      ),
    );
  }

  Widget _buildFooter(bool isShort) {
    final colorScheme = Theme.of(context).colorScheme;
    // הרמז נכנס רק כשיש לו רוחב אמיתי, ובחלון נמוך הוא מפנה מקום לתוצאות.
    final showKeyboardHint =
        !isShort && MediaQuery.sizeOf(context).width >= 560;
    return ColoredBox(
      color: AppSurfaces.card(context),
      child: Padding(
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final screenSize = media.size;
    // insetPadding של Dialog מתווסף ל-viewInsets (המקלדת במובייל), ולכן
    // הגובה הפנוי נמדד אחרי הורדתם — אחרת הדיאלוג נחתך כשהמקלדת עולה.
    final maxWidth = screenSize.width - 24;
    final maxHeight = screenSize.height - media.viewInsets.vertical - 24;
    final dialogWidth = math.min(
      maxWidth,
      (screenSize.width * 0.6).clamp(540.0, 720.0),
    );
    final dialogHeight = math.min(
      maxHeight,
      (screenSize.height * 0.84).clamp(480.0, 700.0),
    );

    final isCompact = screenSize.width < 600;
    final isShort = dialogHeight < 470;
    // מסך לרוחב בטלפון עם מקלדת פתוחה משאיר פחות מ-300: שם התחתית נסגרת
    // לטובת שדה ההקלדה (הסגירה זמינה ב-X שבכותרת ובלחיצה מחוץ לדיאלוג).
    final isTiny = dialogHeight < 300;
    final horizontalPadding = isCompact ? 12.0 : 16.0;

    return Dialog(
      insetPadding: const EdgeInsets.all(12),
      backgroundColor: AppSurfaces.solidPanelBackground(context),
      clipBehavior: Clip.antiAlias,
      // הפאנל בגובה קבוע, ולכן הגדלת גופן מעבר לכך הייתה דוחקת את הכותרת
      // והתחתית זו על זו. הכיתוב עדיין גדל, עד גבול שהפריסה נושאת.
      child: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.6,
        child: SizedBox(
          key: tourFindRefDialogTargetKey,
          width: dialogWidth,
          height: dialogHeight,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(isShort),
              const Divider(height: 1),
              // חסם הגובה מבטיח שגם בגופן מוגדל אזור ההקלדה יגלול בתוך
              // עצמו במקום לדחוק את רשימת התוצאות אל מחוץ לדיאלוג.
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: dialogHeight * 0.5),
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
