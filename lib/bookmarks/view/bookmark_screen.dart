import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria_icons/otzaria_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/widgets/dialogs/reusable_items_dialog.dart';
import 'package:otzaria/bookmarks/bloc/bookmark_bloc.dart';
import 'package:otzaria/bookmarks/bloc/bookmark_state.dart';
import 'package:otzaria/bookmarks/models/bookmark.dart';
import 'package:otzaria/bookmarks/models/bookmark_group.dart';
import 'package:otzaria/bookmarks/models/bookmark_sort_mode.dart';
import 'package:otzaria/bookmarks/view/save_group_bookmark_dialog.dart';
import 'package:otzaria/widgets/misc/app_menu_exports.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/models/commentators_tab.dart';
import 'package:otzaria/tabs/models/pdf_commentators_tab.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/core/messages/notes_messages.dart';
import 'package:otzaria/utils/ui/reading_left_pane_policy.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';
import 'package:otzaria/widgets/lists/items_list_view.dart';
import 'package:otzaria/widgets/dialogs/app_dialogs.dart';
import 'package:otzaria/widgets/dialogs/input_dialog.dart';

class BookmarksDialog extends StatelessWidget {
  /// אם מסופק, יוצגו רק סימניות של ספר זה (הדיאלוג הופך לתצוגת
  /// "סימניות בספר הנוכחי").
  final Book? bookFilter;

  const BookmarksDialog({super.key, this.bookFilter});

  @override
  Widget build(BuildContext context) {
    return AppCustomContentDialog(
      title: bookFilter == null ? 'סימניות' : 'סימניות בספר זה',
      scrollable: false,
      child: BookmarkView(bookFilter: bookFilter),
    );
  }
}

class BookmarkView extends StatefulWidget {
  /// אם מסופק, מסונן לרשימה רק סימניות שזהות הספר שלהן זהה לזו של [bookFilter].
  final Book? bookFilter;

  const BookmarkView({super.key, this.bookFilter});

  @override
  State<BookmarkView> createState() => _BookmarkViewState();
}

class _BookmarkViewState extends State<BookmarkView> {
  late BookmarkSortMode _sortMode;
  final FocusNode _searchFocusNode = FocusNode();

  /// קאש לספירת הסימניות לפי ספר — נמנע מחישוב בכל קריאה ל-build
  /// כשרשימת הסימניות לא משתנה.
  List<Bookmark>? _cachedBookmarks;
  Map<String, int>? _cachedCountPerBook;

  final _dateGroups = BookmarkDateGroups();

  @override
  void initState() {
    super.initState();
    _sortMode = loadBookmarkSortMode();
  }

  @override
  void dispose() {
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _onSortModeChanged(BookmarkSortMode mode) {
    if (mode == _sortMode) return;
    setState(() => _sortMode = mode);
    saveBookmarkSortMode(mode);
    _searchFocusNode.requestFocus();
  }

  Map<String, int> _getCountPerBook(List<Bookmark> bookmarks) {
    if (identical(_cachedBookmarks, bookmarks)) return _cachedCountPerBook!;
    final counts = <String, int>{};
    for (final bm in bookmarks) {
      final id = bookIdentity(bm.book);
      counts[id] = (counts[id] ?? 0) + 1;
    }
    _cachedBookmarks = bookmarks;
    _cachedCountPerBook = counts;
    return counts;
  }

  static int _compareBookmarks(Bookmark a, Bookmark b) {
    final aPath = a.book.categoryPath ?? '';
    final bPath = b.book.categoryPath ?? '';
    final pathCmp = aPath.compareTo(bPath);
    if (pathCmp != 0) return pathCmp;
    final aCmp = bookIdentity(a.book).compareTo(bookIdentity(b.book));
    if (aCmp != 0) return aCmp;
    return a.index.compareTo(b.index);
  }

  /// מיון לפי מועד הוספה — החדש למעלה. סימניות ישנות ללא [createdAt]
  /// נדחקות לתחתית.
  static int _compareByDateAdded(Bookmark a, Bookmark b) {
    final aDate = a.createdAt;
    final bDate = b.createdAt;
    if (aDate == null && bDate == null) return 0;
    if (aDate == null) return 1;
    if (bDate == null) return -1;
    return bDate.compareTo(aDate);
  }

  /// בונה את ה-Tab המתאים לסימניה. עבור [BookmarkTargetKind.commentators]
  /// יוצרים sourceTab בלתי-תלוי וגורסה אותו ל-PdfCommentatorsTab/CommentatorsTab,
  /// בדומה לזרימה ב-HistoryScreen.
  OpenedTab _buildTabForBookmark(Bookmark bookmark) {
    final openLeftPane = shouldAutoOpenReadingLeftPane();
    if (bookmark.targetKind == BookmarkTargetKind.commentators) {
      if (bookmark.book is PdfBook) {
        final sourceTab = PdfBookTab(
          book: bookmark.book as PdfBook,
          pageNumber: bookmark.index,
          openLeftPane: openLeftPane,
        )..activeCommentators = bookmark.commentatorsToShow.toSet();
        return PdfCommentatorsTab(sourceTab: sourceTab);
      }

      final sourceTab =
          OpenedTab.fromBook(
                bookmark.book,
                bookmark.index,
                commentators: bookmark.commentatorsToShow,
                openLeftPane: openLeftPane,
              )
              as TextBookTab;
      return CommentatorsTab(sourceTab: sourceTab);
    }

    return OpenedTab.fromBook(
      bookmark.book,
      bookmark.index,
      commentators: bookmark.commentatorsToShow,
      openLeftPane: openLeftPane,
    );
  }

  void _openBook(
    BuildContext context,
    Bookmark bookmark, {
    String? targetTitle,
  }) {
    final tab = _buildTabForBookmark(bookmark);

    context.read<TabsBloc>().add(
      OpenOrFocusTab(
        tab,
        targetTitle: targetTitle,
        // סימניה מצביעה על מיקום ספציפי. אם הספר כבר פתוח בטאב אחר,
        // נרצה לגלול אותו למיקום של הסימניה ולא רק לתת לו focus.
        navigateToPositionIfReused: true,
      ),
    );
    context.read<NavigationBloc>().add(const NavigateToScreen(Screen.reading));
    // Close the dialog if this view is displayed inside one
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  /// פותח את כל ספרי הקבוצה במיקומם השמור, לצד הטאבים הקיימים.
  /// ספר שכבר פתוח מקבל מיקוד ונגלל למיקום הסימניה.
  void _openGroup(BuildContext context, BookmarkGroup group) {
    final tabsBloc = context.read<TabsBloc>();
    for (final bookmark in group.items) {
      tabsBloc.add(
        OpenOrFocusTab(
          _buildTabForBookmark(bookmark),
          targetTitle: bookmark.ref,
          navigateToPositionIfReused: true,
        ),
      );
    }
    // הספר הראשון בקבוצה הוא הראשי — מחזירים אליו את המיקוד אחרי שכולם נפתחו.
    if (group.items.length > 1) {
      final first = group.items.first;
      tabsBloc.add(
        OpenOrFocusTab(_buildTabForBookmark(first), targetTitle: first.ref),
      );
    }
    context.read<NavigationBloc>().add(const NavigateToScreen(Screen.reading));
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _renameGroup(BuildContext context, BookmarkGroup group) async {
    final bloc = context.read<BookmarkBloc>();
    final result = await showInputDialog(
      context: context,
      title: 'שינוי שם הסימניה המרוכזת',
      labelText: 'שם',
      initialValue: group.name,
    );
    if (result == null || result.trim().isEmpty) return;
    bloc.renameGroup(group.id, result);
  }

  Widget _buildGroupsSection(BuildContext context, List<BookmarkGroup> groups) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(
            'סימניות מרוכזות',
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 180),
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: groups.length,
            itemBuilder: (context, i) {
              final group = groups[i];
              final count = group.items.length;
              return ListTile(
                dense: true,
                hoverColor: Colors.transparent,
                leading: const Icon(FluentIcons.bookmark_multiple_24_regular),
                title: Text(group.name),
                subtitle: Text(count == 1 ? 'ספר אחד' : '$count ספרים'),
                onTap: () => _openGroup(context, group),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(FluentIcons.edit_24_regular),
                      tooltip: 'שינוי שם',
                      onPressed: () => _renameGroup(context, group),
                    ),
                    IconButton(
                      icon: const Icon(FluentIcons.delete_24_regular),
                      tooltip: 'מחיקה',
                      onPressed: () {
                        context.read<BookmarkBloc>().removeGroup(group.id);
                        UiSnack.show(NotesMessages.groupBookmarkDeleted);
                      },
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildSearchTrailing(BuildContext context) {
    final sortButton = _buildSortButton(context);
    if (widget.bookFilter != null) return sortButton;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 8),
          child: IconButton(
            icon: const Icon(FluentIcons.bookmark_multiple_24_regular),
            tooltip: 'שמור סימניה לכל הספרים הפתוחים',
            onPressed: () => showSaveGroupBookmarkDialog(context),
          ),
        ),
        sortButton,
      ],
    );
  }

  /// עריכת טקסט התיאור המוצג של סימניה. ערך ריק מאפס לברירת המחדל (המיקום).
  Future<void> _editBookmarkLabel(
    BuildContext context,
    Bookmark bookmark,
    int originalIndex,
  ) async {
    final bloc = context.read<BookmarkBloc>();
    final current = bookmark.label?.trim().isNotEmpty == true
        ? bookmark.label!.trim()
        : (ItemsListView.locationSubtitle(bookmark) ?? '');
    final result = await showInputDialog(
      context: context,
      title: 'עריכת תיאור הסימניה',
      labelText: 'תיאור',
      initialValue: current,
    );
    if (result == null) return;
    bloc.updateBookmarkLabel(originalIndex, result);
  }

  /// מחיקה גורפת של סימניות. פעולה בלתי הפיכה ולכן מאושרת בדיאלוג אזהרה.
  Future<void> _clearAll(BuildContext context, Book? bookFilter) async {
    final bloc = context.read<BookmarkBloc>();
    final confirmed = await showWarningDialog(
      context: context,
      title: bookFilter == null
          ? 'למחוק את כל הסימניות?'
          : 'למחוק את סימניות הספר?',
      content: bookFilter == null
          ? 'כל הסימניות השמורות יימחקו.'
          : 'כל הסימניות בספר "${bookFilter.title}" יימחקו.',
      subtitle: 'לא ניתן לשחזר סימניות שנמחקו.',
      confirmText: 'מחק',
    );
    if (confirmed != true) return;

    if (bookFilter == null) {
      bloc.clearBookmarks();
      UiSnack.show(NotesMessages.allBookmarksDeleted);
      return;
    }
    // הודעת ההצלחה תוצג רק אם באמת נמחקה סימניה - בלי זה היה
    // ייתכן שתוצג "סימניות הספר נמחקו" גם כשלא היו לספר סימניות
    // (לחיצת כפתור בעת מצב ריק).
    if (bloc.clearBookmarksForBook(bookFilter)) {
      UiSnack.show(NotesMessages.bookBookmarksDeleted);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bookFilter = widget.bookFilter;
    final filterIdentity = bookFilter == null ? null : bookIdentity(bookFilter);
    return BlocBuilder<BookmarkBloc, BookmarkState>(
      builder: (context, state) {
        // ספר עם 2+ סימניות יקבל קבוצה משלו
        final countPerBook = _getCountPerBook(state.bookmarks);

        String bookmarkGroupKey(Bookmark bm) {
          final id = bookIdentity(bm.book);
          if ((countPerBook[id] ?? 0) > 1) return 'book:$id';
          return 'folder:${bm.book.categoryPath ?? id}';
        }

        String? bookmarkGroupTitle(Bookmark bm) {
          final id = bookIdentity(bm.book);
          if ((countPerBook[id] ?? 0) > 1) return bm.book.title;
          final path = bm.book.categoryPath;
          if (path == null || path.isEmpty) return bm.book.title;
          final segments = path.split(', ').where((s) => s.isNotEmpty).toList();
          return segments.isNotEmpty ? segments.last : bm.book.title;
        }

        final byDate = _sortMode == BookmarkSortMode.dateAdded;

        final listView = ItemsListView(
          searchFocusNode: _searchFocusNode,
          items: state.bookmarks,
          searchFieldTrailing: _buildSearchTrailing(context),
          itemSortComparator: byDate
              ? (a, b) => _compareByDateAdded(a as Bookmark, b as Bookmark)
              : (a, b) => _compareBookmarks(b as Bookmark, a as Bookmark),
          additionalFilter: filterIdentity == null
              ? null
              : (item) => bookIdentity(item.book) == filterIdentity,
          groupKeyBuilder: byDate
              ? (item) => _dateGroups.keyFor((item as Bookmark).createdAt)
              : (item) => bookmarkGroupKey(item as Bookmark),
          groupTitleBuilder: byDate
              ? (item) => _dateGroups.labelFor((item as Bookmark).createdAt)
              : (item) => bookmarkGroupTitle(item as Bookmark),
          onItemTap: (ctx, item, originalIndex) => _openBook(
            ctx,
            item,
            targetTitle: item.ref,
          ),
          onEdit: (ctx, item, originalIndex) =>
              _editBookmarkLabel(ctx, item as Bookmark, originalIndex),
          onDelete: (ctx, originalIndex) {
            ctx.read<BookmarkBloc>().removeBookmark(originalIndex);
            UiSnack.show(NotesMessages.bookmarkDeleted);
          },
          onClearAll: (ctx) => _clearAll(ctx, bookFilter),
          hintText: 'חפש בסימניות...',
          searchIcon: OtzariaIcons.search_in_titles_24_regular,
          emptyText: bookFilter == null ? 'אין סימניות' : 'אין סימניות בספר זה',
          notFoundText: 'לא נמצאו תוצאות',
          clearAllText: bookFilter == null
              ? 'מחק את כל הסימניות'
              : 'מחק סימניות הספר',
          leadingIconBuilder: (item) => item.book is PdfBook
              ? const Icon(OtzariaIcons.book_pdf_24_regular)
              : null,
          subtitleBuilder: (item) {
            final label = (item as Bookmark).label?.trim();
            if (label != null && label.isNotEmpty) return label;
            return ItemsListView.locationSubtitle(item);
          },
          // כשמוצג ה-label, המיקום (פרק/עמוד) זמין בריחוף כדי לא לאבד אותו.
          subtitleTooltipBuilder: (item) {
            final label = (item as Bookmark).label?.trim();
            if (label == null || label.isEmpty) return null;
            return ItemsListView.locationSubtitle(item);
          },
        );

        // כשאין סימניות ItemsListView מציג רק את טקסט המצב הריק, בלי שורת
        // החיפוש — ולכן כפתור השמירה המרוכזת שבה לא נראה. מציגים אותו במרכז.
        if (bookFilter == null && state.bookmarks.isEmpty) {
          return Column(
            children: [
              if (state.groups.isNotEmpty)
                _buildGroupsSection(context, state.groups),
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('אין סימניות'),
                      const SizedBox(height: 16),
                      ActionButton.neutral(
                        text: 'שמור סימניה לכל הספרים הפתוחים',
                        onPressed: () => showSaveGroupBookmarkDialog(context),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        }

        if (bookFilter != null || state.groups.isEmpty) return listView;
        return Column(
          children: [
            _buildGroupsSection(context, state.groups),
            Expanded(child: listView),
          ],
        );
      },
    );
  }

  Widget _buildSortButton(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 8),
      child: AppPopupMenuButton<BookmarkSortMode>(
        icon: const Icon(FluentIcons.arrow_sort_24_regular),
        tooltip: 'מיון',
        highlighted: true,
        initialValue: _sortMode,
        onSelected: _onSortModeChanged,
        entries: const [
          AppMenuEntry(value: BookmarkSortMode.category, label: 'לפי קטגוריה'),
          AppMenuEntry(
            value: BookmarkSortMode.dateAdded,
            label: 'לפי תאריך הוספה',
          ),
        ],
      ),
    );
  }
}

/// קיבוץ "לפי תאריך הוספה". השבוע מתחיל ביום ראשון (מנהג ישראלי).
/// הגבולות נשמרים כל עוד היום והיסטי אזור הזמן שלהם לא השתנו.
@visibleForTesting
class BookmarkDateGroups {
  static const _keys = [
    '1_today',
    '2_yesterday',
    '3_this_week',
    '4_last_week',
    '5_this_month',
    '6_prev_month',
    '7_this_year',
  ];

  static const _labels = {
    '1_today': 'היום',
    '2_yesterday': 'אתמול',
    '3_this_week': 'השבוע',
    '4_last_week': 'שבוע שעבר',
    '5_this_month': 'החודש',
    '6_prev_month': 'חודש קודם',
    '7_this_year': 'השנה',
    '8_older': 'ישן יותר',
  };

  List<DateTime> _starts = const [];
  List<Duration> _offsets = const [];

  /// תחילת כל תקופה ב-[_keys], מהחדשה לישנה.
  List<DateTime> periodStarts(DateTime now) {
    if (_starts.isNotEmpty) {
      final today = _starts.first;
      if (today.year == now.year &&
          today.month == now.month &&
          today.day == now.day &&
          _offsetsUnchanged()) {
        return _starts;
      }
    }
    final today = DateTime(now.year, now.month, now.day);
    // ראשון=weekday 7 → 7%7=0, שני=1, ..., שבת=6
    final startOfThisWeek = today.subtract(Duration(days: today.weekday % 7));
    _starts = [
      today,
      today.subtract(const Duration(days: 1)),
      startOfThisWeek,
      startOfThisWeek.subtract(const Duration(days: 7)),
      DateTime(now.year, now.month, 1),
      now.month == 1
          ? DateTime(now.year - 1, 12, 1)
          : DateTime(now.year, now.month - 1, 1),
      DateTime(now.year, 1, 1),
    ];
    _offsets = [for (final start in _starts) start.timeZoneOffset];
    return _starts;
  }

  bool _offsetsUnchanged() {
    // ההיסט ב-DateTime ישן מחושב מחדש; גם גבול היסטורי יכול לשנות היסט לבדו.
    for (var i = 0; i < _starts.length; i++) {
      if (_starts[i].timeZoneOffset != _offsets[i]) return false;
    }
    return true;
  }

  String keyFor(DateTime? date, {DateTime? now}) {
    if (date == null) return '8_older';
    final starts = periodStarts(now ?? DateTime.now());
    final d = DateTime(date.year, date.month, date.day);
    for (var i = 0; i < starts.length; i++) {
      if (!d.isBefore(starts[i])) return _keys[i];
    }
    return '8_older';
  }

  String labelFor(DateTime? date, {DateTime? now}) =>
      _labels[keyFor(date, now: now)]!;
}
