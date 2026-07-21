import 'package:flutter/material.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:flutter/services.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/find_ref/bloc/find_ref_bloc.dart';
import 'package:otzaria/find_ref/bloc/find_ref_event.dart';
import 'package:otzaria/find_ref/bloc/find_ref_state.dart';
import 'package:otzaria/find_ref/repository/db_reference_result.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/history/bloc/history_event.dart';
import 'package:otzaria/core/focus_repository.dart';
import 'package:otzaria/core/external_uri_router.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart' show Screen;
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
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria/search/view/search_dialog.dart';
import 'package:otzaria/navigation/view/main_window_screen.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';
import 'package:otzaria/widgets/misc/rtl_icon.dart';

class FindRefDialog extends StatefulWidget {
  const FindRefDialog({super.key});

  /// מפתח הגדרה לשמירת מצב הטוגל "כלול ספרים אישיים" בין פתיחות הדיאלוג.
  static const String _keyIncludePersonalBooks =
      'key-find-ref-include-personal-books';

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
  final int? targetSegment;
  final Book book;

  const _CommentatorEntry({
    required this.title,
    required this.targetSegment,
    required this.book,
  });
}

/// מאתר את ה-`Book` הנכון בעץ הספרייה לפי [bookId] אם נמסר, ולפי [title]
/// אם לא. הסיבה: שני ספרים יכולים לחלוק כותרת זהה (למשל גרסאות שונות של
/// פירוש), וה-link שייצא משאילתת המפרשים יודע בדיוק לאיזה ספר ללכת —
/// פתרון רק לפי title היה פותח את הראשון שנמצא בעץ.
Book? _resolveCommentatorBook(
  Category library,
  String title, {
  required int? bookId,
}) {
  if (bookId != null && bookId > 0) {
    final byId = findOfficialTextBookById(library, bookId);
    if (byId != null) return byId;
  }
  // fallback ל-title (תאימות לאחור עם DB שלא מחזיר targetBookId).
  return _findBookInLibraryByTitle(library, title, preferTextBook: true);
}

/// מאתר ספר טקסט רשמי לפי [bookId] מה-DB הראשי.
/// מזהי seforim.db אינם ייחודיים מול user_books.db ומול ייצוגי PDF בעץ —
/// ולכן ספרים אישיים וספרים שאינם TextBook מדולגים ולא מסתירים את היעד.
@visibleForTesting
TextBook? findOfficialTextBookById(Category category, int bookId) {
  for (final b in category.books) {
    if (b is TextBook && !b.isUserBook && b.id == bookId) return b;
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
}) {
  // עוברים פעמיים אם preferTextBook: ראשונה — רק TextBook; שנייה — כל סוג.
  for (final passOnlyText in preferTextBook ? [true, false] : [false]) {
    final result = _findBookInLibraryByTitlePass(
      category,
      title,
      onlyTextBook: passOnlyText,
    );
    if (result != null) return result;
  }
  return null;
}

Book? _findBookInLibraryByTitlePass(
  Category category,
  String title, {
  required bool onlyTextBook,
}) {
  for (final b in category.books) {
    if (b.title != title) continue;
    if (onlyTextBook && b is! TextBook) continue;
    return b;
  }
  for (final subCat in category.subCategories) {
    final found = _findBookInLibraryByTitlePass(
      subCat,
      title,
      onlyTextBook: onlyTextBook,
    );
    if (found != null) return found;
  }
  return null;
}

class _FindRefDialogState extends State<FindRefDialog> {
  int _selectedIndex = 0;
  bool _includePersonalBooks =
      Settings.getValue<bool>(
        FindRefDialog._keyIncludePersonalBooks,
        defaultValue: false,
      ) ??
      false;
  final Map<int, GlobalKey> _itemKeys = {};
  final Map<int, GlobalKey> _commentatorsButtonKeys = {};
  // המפתח כולל את כל הפרמטרים המבדילים בין refs (bookId/sourceLineId/isAltToc/
  // level/segment) — TOC רגיל ו-AltToc יכולים לחלוק שורת התחלה ולחשב טווח שונה.
  // value=null → טעינה בתהליך.
  // value=[] → אין מפרשים זמינים (לא יוצג כפתור).
  // value=[...] → רשומות מוכנות לפתיחה ישירה (כולל targetSegment ו-Book).
  final Map<String, List<_CommentatorEntry>?> _commentatorsByRef = {};
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

    // בחירת הטקסט הקיים כאשר חוזרים למסך
    // מבוצע מיד ולא ב-postFrameCallback כדי למנוע אובדן פוקוס באנדרואיד
    final controller = FocusRepository().findRefSearchController;
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
    _resultsScrollController.removeListener(_updateHasMoreBelow);
    _resultsScrollController.dispose();
    _hasMoreBelow.dispose();
    final restorer = _focusRestorer;
    if (restorer != null) FocusRepository().unregisterActiveRestorer(restorer);
    super.dispose();
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
    final repository = context.read<FindRefBloc>().findRefRepository;
    () async {
      try {
        final dbEntries = await repository.getCommentatorsForResult(ref);
        if (!mounted) return;
        if (dbEntries.isEmpty) {
          setState(() {
            _commentatorsByRef[key] = const [];
          });
          return;
        }
        // pre-resolve של ה-Book עבור כל מפרש כדי שהקליק יהיה סינכרוני.
        // `library` מוחזק בקאש ב-DataRepository.
        final library = await DataRepository.instance.library;
        if (!mounted) return;
        final entries = <_CommentatorEntry>[
          for (final e in dbEntries)
            _CommentatorEntry(
              title: e.title,
              targetSegment: e.targetSegment,
              // פתרון לפי `bookId` כשזמין כדי שלא ייפתח ספר בעל אותה כותרת
              // אך מזהה אחר; ה-fallback ל-title שומר על תאימות.
              book:
                  _resolveCommentatorBook(library, e.title, bookId: e.bookId) ??
                  TextBook(title: e.title),
            ),
        ];
        setState(() {
          _commentatorsByRef[key] = entries;
        });
      } catch (e) {
        debugPrint('[FindRef] commentators load failed: $e');
        if (!mounted) return;
        setState(() {
          _commentatorsByRef[key] = const [];
        });
      }
    }();
  }

  void _scrollToSelected() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final key = _getKeyForIndex(_selectedIndex);
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

  /// חץ קטן באותה שורה כמו "סגור" שמופיע כשיש תוצאות מתחת לאזור הנראה.
  /// קליק גולל לסוף הרשימה. ה-IconButton נשאר קבוע במקום — רק ה-opacity
  /// משתנה — כך שגודל הדיאלוג לא משתנה כשהחץ נכבה/נדלק.
  ///
  /// המקור הסינגלטוני של "האם יש יותר למטה" הוא [_hasMoreBelow], שמעודכן
  /// משני נקודות (ראה השדה לפרטים).
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
              tooltip: 'גלול לסוף הרשימה',
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

      // הגדרת "פורמט פתיחת תלמוד בבלי": תוצאת טקסט של מסכת בבלי נפתחת
      // מיידית כטאב טעינה שממופה ל-PDF בתוכו. מזהים את ספר המקור בעץ לפי
      // bookId (זהות יציבה); בלי זיהוי ודאי לא ממירים ל-PDF, אחרת בחירה
      // לפי כותרת בלבד עלולה לפתוח ספר אחר בעל שם זהה.
      if (!needsTextBook &&
          !ref.isUserBook &&
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
        final officialBookId = (ref.bookId > 0 && !ref.isUserBook)
            ? ref.bookId
            : null;
        book = _findBookInLibraryByIdThenTitle(
          library,
          ref.title,
          bookId: officialBookId,
          preferTextBook: needsTextBook,
        );
        // ספרי בבלי מופיעים בעץ הספרייה כ-PdfBook גם כשה-DB מכיר אותם
        // כ-txt; ה-segment הוא אינדקס טקסט, לכן נפתחת מהדורת הטקסט.
        if (book is PdfBook && isTalmudBavliBook(book)) {
          book = null;
        }
      }
      book ??= TextBook(title: ref.title);
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

    if (selected == null || !mounted) return;
    _openCommentator(selected);
  }

  /// פותח את ספר המפרש מתוך רשומה שהוכנה מראש: ה-`book` כבר ידוע, וה-
  /// `targetSegment` נלקח מה-[entry] (ה-`targetLineIndex` של ה-DB). אם חסר
  /// (row חריג) נפתח בתחילת ספר המפרש — לא ב-`ref.segment`, שהוא אינדקס בספר
  /// המקור וחסר משמעות בספר המפרש. הקליק סינכרוני לחלוטין — אין `await`, אין
  /// שאילתות DB ואין מעבר על עץ הספרייה בזמן הקליק.
  void _openCommentator(_CommentatorEntry entry) {
    final segment = entry.targetSegment ?? 0;
    Navigator.of(context).pop();
    openBook(context, entry.book, segment, '');
  }

  /// מחפש ספר ב-[category] לפי [bookId] כשנמסר, ונופל ל-[title] אם לא נמצא.
  /// פתרון לפי id מונע התנגשות בין שני ספרים בעלי כותרת זהה בעץ.
  Book? _findBookInLibraryByIdThenTitle(
    Category category,
    String title, {
    required int? bookId,
    bool preferTextBook = false,
  }) {
    if (bookId != null) {
      final byId = findOfficialTextBookById(category, bookId);
      if (byId != null) return byId;
    }
    return _findBookInLibraryByTitle(
      category,
      title,
      preferTextBook: preferTextBook,
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
    if (ExternalUriRouter.parseUri(normalized) == null) return false;

    final handled = await mainWindowScreenKey.currentState
        ?.handleInternalDeepLink(normalized.toString());

    if (handled == true && mounted) {
      final focusRepository = context.read<FocusRepository>();
      focusRepository.findRefSearchController.clear();
      BlocProvider.of<FindRefBloc>(context).add(const SearchRefRequested(''));
      BlocProvider.of<FindRefBloc>(context).add(ClearSearchRequested());
      Navigator.of(context).pop();
    }
    return handled == true;
  }

  /// פותח את דיאלוג החיפוש עם [query] מוכן בשדה — ללא הרצת חיפוש.
  void _openTextSearch(String query) {
    Navigator.of(context).pop();
    final tab = SearchingTab('חיפוש', query);
    showDialog(
      context: context,
      builder: (context) => SearchDialog(existingTab: tab),
    );
  }

  /// מצב ריק מעוצב: אייקון, הודעה ממוקדת וכפתור לפתיחת חיפוש טקסט.
  Widget _buildEmptyState(BuildContext context, String query) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDeepLink = _isDeepLinkText(query);

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RtlIcon(
              isDeepLink
                  ? FluentIcons.link_24_regular
                  : FluentIcons.document_search_24_regular,
              size: 64,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              isDeepLink
                  ? 'נראה שהכנסתם קישור ישיר'
                  : 'לא הצלחנו לאתר את הספר "$query"',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: colorScheme.onSurface,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              isDeepLink
                  ? 'לחצו על הכפתור לפתיחת הקישור'
                  : 'נסו טקסט אחר לאיתור הספר המבוקש במאגר',
              style: TextStyle(
                fontSize: 14,
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            if (isDeepLink) ...[
              ActionButton.recommended(
                text: 'פתיחת קישור',
                onPressed: () => _tryHandleDeepLink(query),
                icon: FluentIcons.link_24_regular,
              ),
            ] else ...[
              Text(
                'ניתן לאתר גם טקסט ספציפי במאגר',
                style: TextStyle(
                  fontSize: 14,
                  color: colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              ActionButton.recommended(
                text: 'פתח חיפוש טקסט',
                onPressed: () => _openTextSearch(query),
                icon: FluentIcons.search_24_regular,
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final focusRepository = context.read<FocusRepository>();

    return AlertDialog(
      title: const Text(
        'איתור מקורות',
        style: TextStyle(fontWeight: FontWeight.bold),
        textAlign: TextAlign.center,
      ),
      content: SizedBox(
        key: tourFindRefDialogTargetKey,
        width: 500,
        height: 600,
        child: Column(
          children: [
            BlocBuilder<FindRefBloc, FindRefState>(
              builder: (context, state) {
                final refs = state is FindRefSuccess ? state.refs : [];
                return Focus(
                  onKeyEvent: (node, event) {
                    // טיפול גם ב-KeyDownEvent וגם ב-KeyRepeatEvent (לחיצה רצופה)
                    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
                      return KeyEventResult.ignored;
                    }

                    // טיפול בחיצים רק אם יש תוצאות
                    if (refs.isNotEmpty) {
                      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                        setState(() {
                          _selectedIndex = (_selectedIndex + 1).clamp(
                            0,
                            refs.length - 1,
                          );
                        });
                        _scrollToSelected();
                        return KeyEventResult.handled;
                      } else if (event.logicalKey ==
                          LogicalKeyboardKey.arrowUp) {
                        setState(() {
                          _selectedIndex = (_selectedIndex - 1).clamp(
                            0,
                            refs.length - 1,
                          );
                        });
                        _scrollToSelected();
                        return KeyEventResult.handled;
                      }
                    }
                    return KeyEventResult.ignored;
                  },
                  child: RtlTextField(
                    focusNode: focusRepository.findRefSearchFocusNode,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText:
                          'הקלד מקור מדוייק, לדוגמה: בראשית פרק א או שוע אוח יב   ',
                      suffixIcon: IconButton(
                        icon: const Icon(FluentIcons.dismiss_24_regular),
                        onPressed: () {
                          focusRepository.findRefSearchController.clear();
                          // קודם מבטלים חיפוש שעדיין רץ (restartable יקטוף
                          // את ה-handler הקודם), ורק אחר-כך מחזירים את
                          // ה-state ל-Initial.
                          BlocProvider.of<FindRefBloc>(
                            context,
                          ).add(const SearchRefRequested(''));
                          BlocProvider.of<FindRefBloc>(
                            context,
                          ).add(ClearSearchRequested());
                          setState(() {
                            _selectedIndex = 0;
                          });
                        },
                      ),
                    ),
                    controller: focusRepository.findRefSearchController,
                    onChanged: (ref) {
                      setState(() => _selectedIndex = 0);
                      // ההקלדה נשלחת מיידית — ה-debounce עצמו מבוצע בתוך
                      // ה-handler ב-bloc, כך שכל הקלדה חדשה גם מבטלת מיידית
                      // כל handler שכבר רץ (גם אם הוא באמצע fetch).
                      BlocProvider.of<FindRefBloc>(context).add(
                        SearchRefRequested(
                          ref,
                          includePersonalBooks: _includePersonalBooks,
                        ),
                      );
                    },
                    onSubmitted: (value) {
                      // ניסיון לטפל בקישור ישיר — אם זה קישור, ייפתח ישירות
                      if (_isDeepLinkText(value)) {
                        _tryHandleDeepLink(value);
                        return;
                      }
                      // פתיחת המקור הנבחר בלחיצה על אנטר
                      if (refs.isNotEmpty) {
                        _openRef(refs[_selectedIndex]);
                      }
                    },
                  ),
                );
              },
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  'כלול ספרים אישיים',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 4),
                Transform.scale(
                  scale: 0.75,
                  alignment: Alignment.centerRight,
                  child: Switch(
                    value: _includePersonalBooks,
                    onChanged: (v) {
                      setState(() => _includePersonalBooks = v);
                      Settings.setValue<bool>(
                        FindRefDialog._keyIncludePersonalBooks,
                        v,
                      );
                      final text = focusRepository.findRefSearchController.text;
                      if (text.length >= 2) {
                        context.read<FindRefBloc>().add(
                          SearchRefRequested(
                            text,
                            includePersonalBooks: v,
                          ),
                        );
                      }
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: BlocConsumer<FindRefBloc, FindRefState>(
                // ברגע שעוזבים מצב של "Success עם תוצאות" — אין ListView,
                // אין ל-controller clients, ושום notification לא יישלח. בלי
                // איפוס יזום, _hasMoreBelow היה נשאר true מהחיפוש הקודם
                // וה-arrow היה מופיע באמצע spinner / "אין תוצאות" / Initial.
                listener: (context, state) {
                  final hasListView =
                      state is FindRefSuccess && state.refs.isNotEmpty;
                  if (!hasListView && _hasMoreBelow.value) {
                    _hasMoreBelow.value = false;
                  }
                },
                builder: (context, state) {
                  if (state is FindRefLoading) {
                    return const _DelayedLoader();
                  } else if (state is FindRefError) {
                    return Text('Error: ${state.message}');
                  } else if (state is FindRefSuccess && state.refs.isEmpty) {
                    final query = focusRepository.findRefSearchController.text;
                    if (query.length >= 3) {
                      return _buildEmptyState(context, query);
                    } else {
                      return const SizedBox.shrink();
                    }
                  } else if (state is FindRefSuccess) {
                    return NotificationListener<ScrollMetricsNotification>(
                      // נכנס לפעולה כאשר ה-ListView מתחבר לראשונה, וגם בכל
                      // שינוי של maxScrollExtent (סט תוצאות חדש שמשנה את
                      // גובה התוכן). מעדכן את _hasMoreBelow אחרי הסיום של
                      // ה-frame הנוכחי כדי שלא נשנה ValueNotifier בזמן build.
                      onNotification: (_) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) _updateHasMoreBelow();
                        });
                        return false;
                      },
                      child: ListView.builder(
                        controller: _resultsScrollController,
                        itemCount: state.refs.length,
                        itemBuilder: (context, index) {
                          final ref = state.refs[index];
                          final isSelected = index == _selectedIndex;
                          final eligible =
                              !ref.isPdf && ref.bookId > 0 && !ref.isUserBook;
                          // טעינה lazy בעת רינדור — ListView.builder יפעיל את
                          // ה-itemBuilder רק עבור שורות נראות. ה-cache ב-repository
                          // ימנע קריאות חוזרות.
                          if (eligible) _ensureCommentatorsLoaded(ref);
                          final cached =
                              _commentatorsByRef[_commentatorsKey(ref)];
                          final showButton =
                              eligible && cached != null && cached.isNotEmpty;
                          final menuButtonKey = _getCommentatorsButtonKey(
                            index,
                          );
                          return Container(
                            key: _getKeyForIndex(index),
                            margin: const EdgeInsets.symmetric(
                              horizontal: 8.0,
                              vertical: 4.0,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? Theme.of(
                                      context,
                                    ).colorScheme.primaryContainer
                                  : null,
                              borderRadius: AppTokens.borderRadiusAll,
                            ),
                            child: ListTile(
                              hoverColor: showButton
                                  ? Colors.transparent
                                  : null,
                              leading: ref.isPdf
                                  ? const Icon(
                                      FluentIcons.document_pdf_24_regular,
                                    )
                                  : null,
                              title: Text(
                                ref.reference,
                                style: TextStyle(
                                  fontWeight: isSelected
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                ),
                              ),
                              subtitle: ref.bookPath.isEmpty
                                  ? null
                                  : LibraryOverflowTooltipText(
                                      text: ref.bookPath,
                                      maxLines: 1,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                          ),
                                    ),
                              trailing: showButton
                                  ? IconButton(
                                      key: menuButtonKey,
                                      icon: const Icon(
                                        FluentIcons.library_24_regular,
                                      ),
                                      tooltip: 'הצג מפרשים זמינים',
                                      onPressed: () => _showCommentatorsMenu(
                                        menuButtonKey,
                                        cached,
                                      ),
                                    )
                                  : null,
                              onTap: () {
                                _openRef(ref);
                              },
                            ),
                          );
                        },
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
            ),
          ],
        ),
      ),
      // החץ "גלול לסוף הרשימה" יושב באותה שורה כמו "סגור" (actions), אך עם
      // padding עליון 0 ותחתון מצומצם — צמוד לתחתית התוכן.
      // Stack על מלוא הרוחב: ה-Align מצמיד את "סגור" לקצה (visual left ב-RTL),
      // וה-IconButton ממוקם במרכז ע"י alignment של ה-Stack עצמו.
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      actions: [
        SizedBox(
          width: double.infinity,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('סגור'),
                ),
              ),
              _buildScrollToEndArrow(),
            ],
          ),
        ),
      ],
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
