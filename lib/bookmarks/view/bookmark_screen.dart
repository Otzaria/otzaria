import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/widgets/dialogs/reusable_items_dialog.dart';
import 'package:otzaria/bookmarks/bloc/bookmark_bloc.dart';
import 'package:otzaria/bookmarks/bloc/bookmark_state.dart';
import 'package:otzaria/bookmarks/models/bookmark.dart';
import 'package:otzaria/bookmarks/models/bookmark_sort_mode.dart';
import 'package:otzaria/widgets/misc/rtl_icon.dart';
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
import 'package:otzaria/utils/ui/reading_left_pane_policy.dart';
import 'package:otzaria/widgets/lists/items_list_view.dart';

class BookmarksDialog extends StatelessWidget {
  /// אם מסופק, יוצגו רק סימניות של ספר זה (הדיאלוג הופך לתצוגת
  /// "סימניות בספר הנוכחי").
  final Book? bookFilter;

  const BookmarksDialog({super.key, this.bookFilter});

  @override
  Widget build(BuildContext context) {
    return ReusableItemsDialog(
      title: bookFilter == null ? 'סימניות' : 'סימניות בספר זה',
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

  /// קאש לספירת הסימניות לפי ספר — נמנע מחישוב בכל קריאה ל-build
  /// כשרשימת הסימניות לא משתנה.
  List<Bookmark>? _cachedBookmarks;
  Map<String, int>? _cachedCountPerBook;

  @override
  void initState() {
    super.initState();
    _sortMode = loadBookmarkSortMode();
  }

  void _onSortModeChanged(BookmarkSortMode mode) {
    if (mode == _sortMode) return;
    setState(() => _sortMode = mode);
    saveBookmarkSortMode(mode);
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

      final sourceTab = OpenedTab.fromBook(
        bookmark.book,
        bookmark.index,
        commentators: bookmark.commentatorsToShow,
        openLeftPane: openLeftPane,
      ) as TextBookTab;
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

        return ItemsListView(
          items: state.bookmarks,
          searchFieldTrailing: _buildSortButton(context),
          itemSortComparator: byDate
              ? (a, b) => _compareByDateAdded(a as Bookmark, b as Bookmark)
              : (a, b) => _compareBookmarks(b as Bookmark, a as Bookmark),
          additionalFilter: filterIdentity == null
              ? null
              : (item) => bookIdentity(item.book) == filterIdentity,
          // במיון לפי תאריך מציגים רשימה כרונולוגית שטוחה — הקיבוץ
          // לפי ספר היה מערבב את הסדר.
          groupKeyBuilder:
              byDate ? null : (item) => bookmarkGroupKey(item as Bookmark),
          groupTitleBuilder:
              byDate ? null : (item) => bookmarkGroupTitle(item as Bookmark),
          onItemTap: (ctx, item, originalIndex) => _openBook(
            ctx,
            item,
            targetTitle: item.ref,
          ),
          onDelete: (ctx, originalIndex) {
            ctx.read<BookmarkBloc>().removeBookmark(originalIndex);
            UiSnack.show('הסימניה נמחקה');
          },
          onClearAll: (ctx) {
            if (bookFilter == null) {
              ctx.read<BookmarkBloc>().clearBookmarks();
              UiSnack.show('כל הסימניות נמחקו');
            } else {
              // הודעת ההצלחה תוצג רק אם באמת נמחקה סימניה - בלי זה היה
              // ייתכן שתוצג "סימניות הספר נמחקו" גם כשלא היו לספר סימניות
              // (לחיצת כפתור בעת מצב ריק).
              final removed =
                  ctx.read<BookmarkBloc>().clearBookmarksForBook(bookFilter);
              if (removed) {
                UiSnack.show('סימניות הספר נמחקו');
              }
            }
          },
          hintText: 'חפש בסימניות...',
          emptyText: bookFilter == null ? 'אין סימניות' : 'אין סימניות בספר זה',
          notFoundText: 'לא נמצאו תוצאות',
          clearAllText:
              bookFilter == null ? 'מחק את כל הסימניות' : 'מחק סימניות הספר',
          leadingIconBuilder: (item) => item.book is PdfBook
              ? const Icon(FluentIcons.document_pdf_24_regular)
              : null,
          subtitleBuilder: (item) => ItemsListView.locationSubtitle(item),
        );
      },
    );
  }

  Widget _buildSortButton(BuildContext context) {
    return PopupMenuButton<BookmarkSortMode>(
      icon: const RtlIcon(FluentIcons.arrow_sort_24_regular),
      tooltip: 'מיון',
      initialValue: _sortMode,
      onSelected: _onSortModeChanged,
      itemBuilder: (context) => [
        _sortMenuItem(BookmarkSortMode.category, 'לפי קטגוריה'),
        _sortMenuItem(BookmarkSortMode.dateAdded, 'לפי תאריך הוספה'),
      ],
    );
  }

  PopupMenuItem<BookmarkSortMode> _sortMenuItem(
    BookmarkSortMode mode,
    String label,
  ) {
    final selected = _sortMode == mode;
    return PopupMenuItem<BookmarkSortMode>(
      value: mode,
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: selected
                ? const RtlIcon(FluentIcons.checkmark_24_regular)
                : null,
          ),
          Text(label),
        ],
      ),
    );
  }
}
