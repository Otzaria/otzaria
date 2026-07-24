import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/bookmarks/bloc/bookmark_bloc.dart';
import 'package:otzaria/bookmarks/bloc/bookmark_state.dart';
import 'package:otzaria/bookmarks/models/bookmark.dart';
import 'package:otzaria/bookmarks/view/bookmark_screen.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/commentators_tab.dart';
import 'package:otzaria/tabs/models/pdf_commentators_tab.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';

import '../helpers/memory_settings_cache.dart';

/// Cubit-based stand-in ל-BookmarkBloc שלוקח state התחלתי כפי שהוא,
/// בלי לרוץ דרך `_loadBookmarks()` של ה-repository.
class _StubBookmarkBloc extends Cubit<BookmarkState> implements BookmarkBloc {
  _StubBookmarkBloc(List<Bookmark> bookmarks)
    : super(BookmarkState(bookmarks: bookmarks));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// אוסף את ה-events ש-_BookmarkView שולח כדי שנוכל לוודא את סוג ה-Tab שנפתח.
class _CapturingTabsBloc extends Cubit<TabsState> implements TabsBloc {
  _CapturingTabsBloc() : super(const TabsState(tabs: [], currentTabIndex: 0));

  final List<TabsEvent> captured = [];

  @override
  void add(TabsEvent event) {
    captured.add(event);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StubNavigationBloc extends Cubit<NavigationState>
    implements NavigationBloc {
  _StubNavigationBloc()
    : super(const NavigationState(currentScreen: Screen.reading));

  @override
  void add(NavigationEvent event) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<OpenOrFocusTab> _tapBookmarkAndCapture(
  WidgetTester tester, {
  required Bookmark bookmark,
}) async {
  final bookmarkBloc = _StubBookmarkBloc([bookmark]);
  final tabsBloc = _CapturingTabsBloc();
  final navBloc = _StubNavigationBloc();

  addTearDown(() async {
    await bookmarkBloc.close();
    await tabsBloc.close();
    await navBloc.close();
  });

  await tester.pumpWidget(
    MaterialApp(
      home: MultiBlocProvider(
        providers: [
          BlocProvider<BookmarkBloc>.value(value: bookmarkBloc),
          BlocProvider<TabsBloc>.value(value: tabsBloc),
          BlocProvider<NavigationBloc>.value(value: navBloc),
        ],
        child: const Scaffold(body: BookmarkView()),
      ),
    ),
  );
  await tester.pump();

  // ItemsListView מרנדר גם InkWells פנימיים (כפתורי search/clear). שורת
  // הפריט עצמה היא ה-InkWell היחיד שעוטף את ה-Text של כותרת הספר; כותרת
  // הקבוצה היא Text רגיל ולכן לא מופיעה ב-ancestor של InkWell.
  final itemTap = find.ancestor(
    of: find.text(bookmark.book.title),
    matching: find.byType(InkWell),
  );
  expect(
    itemTap,
    findsOneWidget,
    reason: 'מצופה InkWell יחיד שעוטף את כותרת הספר ברשימה',
  );
  await tester.tap(itemTap);
  await tester.pump();

  expect(
    tabsBloc.captured,
    hasLength(1),
    reason: 'BookmarkView צריך לשלוח event יחיד ל-TabsBloc בלחיצה',
  );
  return tabsBloc.captured.single as OpenOrFocusTab;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  group('BookmarkView — פתיחת Tab לפי targetKind', () {
    testWidgets('סימניית מפרשים על PdfBook פותחת PdfCommentatorsTab', (
      tester,
    ) async {
      final bookmark = Bookmark(
        ref: 'מסכת ברכות',
        book: PdfBook(title: 'מסכת ברכות', path: '/fake/berachot.pdf'),
        index: 7,
        commentatorsToShow: const ['רש"י', 'תוספות'],
        targetKind: BookmarkTargetKind.commentators,
      );

      final event = await _tapBookmarkAndCapture(tester, bookmark: bookmark);

      expect(event.tab, isA<PdfCommentatorsTab>());
      final commentatorsTab = event.tab as PdfCommentatorsTab;
      expect(commentatorsTab.sourceTab.book.title, 'מסכת ברכות');
      expect(commentatorsTab.sourceTab.pageNumber, 7);
      expect(
        commentatorsTab.sourceTab.activeCommentators,
        containsAll(['רש"י', 'תוספות']),
      );
    });

    testWidgets('סימניית מפרשים על TextBook פותחת CommentatorsTab', (
      tester,
    ) async {
      final bookmark = Bookmark(
        ref: 'בראשית א',
        book: TextBook(title: 'בראשית', filePath: '/fake/בראשית.txt'),
        index: 4,
        commentatorsToShow: const ['רש"י'],
        targetKind: BookmarkTargetKind.commentators,
      );

      final event = await _tapBookmarkAndCapture(tester, bookmark: bookmark);

      expect(event.tab, isA<CommentatorsTab>());
      final commentatorsTab = event.tab as CommentatorsTab;
      expect(commentatorsTab.sourceTab.book.title, 'בראשית');
      expect(commentatorsTab.sourceTab.index, 4);
    });

    testWidgets('סימנייה רגילה על PdfBook פותחת PdfBookTab רגיל', (
      tester,
    ) async {
      final bookmark = Bookmark(
        ref: 'מסכת שבת',
        book: PdfBook(title: 'מסכת שבת', path: '/fake/shabbat.pdf'),
        index: 2,
      );

      final event = await _tapBookmarkAndCapture(tester, bookmark: bookmark);

      expect(event.tab, isA<PdfBookTab>());
      expect(event.tab, isNot(isA<PdfCommentatorsTab>()));
      final pdfTab = event.tab as PdfBookTab;
      expect(pdfTab.book.title, 'מסכת שבת');
      expect(pdfTab.pageNumber, 2);
    });

    testWidgets('סימנייה רגילה על TextBook פותחת TextBookTab רגיל', (
      tester,
    ) async {
      final bookmark = Bookmark(
        ref: 'דברים ל',
        book: TextBook(title: 'דברים', filePath: '/fake/דברים.txt'),
        index: 9,
      );

      final event = await _tapBookmarkAndCapture(tester, bookmark: bookmark);

      expect(event.tab, isA<TextBookTab>());
      expect(event.tab, isNot(isA<CommentatorsTab>()));
      final textTab = event.tab as TextBookTab;
      expect(textTab.book.title, 'דברים');
      expect(textTab.index, 9);
    });
  });
}
