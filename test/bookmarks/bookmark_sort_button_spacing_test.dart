import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/bookmarks/bloc/bookmark_bloc.dart';
import 'package:otzaria/bookmarks/bloc/bookmark_state.dart';
import 'package:otzaria/bookmarks/models/bookmark.dart';
import 'package:otzaria/bookmarks/models/bookmark_sort_mode.dart';
import 'package:otzaria/bookmarks/view/bookmark_screen.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/widgets/misc/app_menu_exports.dart';

import '../helpers/memory_settings_cache.dart';

class _StubBookmarkBloc extends Cubit<BookmarkState> implements BookmarkBloc {
  _StubBookmarkBloc(List<Bookmark> bookmarks)
    : super(BookmarkState(bookmarks: bookmarks));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StubTabsBloc extends Cubit<TabsState> implements TabsBloc {
  _StubTabsBloc() : super(const TabsState(tabs: [], currentTabIndex: 0));

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
  });

  testWidgets('כפתור המיון עטוף ברווח מצד שדה החיפוש', (tester) async {
    final bookmarkBloc = _StubBookmarkBloc([
      Bookmark(
        ref: 'בראשית א',
        book: TextBook(title: 'בראשית', filePath: '/fake/בראשית.txt'),
        index: 1,
      ),
    ]);
    final tabsBloc = _StubTabsBloc();
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

    final sortButton = find.byType(AppPopupMenuButton<BookmarkSortMode>);
    expect(sortButton, findsOneWidget);

    final paddingFinder = find.ancestor(
      of: sortButton,
      matching: find.byType(Padding),
    );
    final hasSpacingPadding = tester
        .widgetList<Padding>(paddingFinder)
        .any((p) => p.padding == const EdgeInsetsDirectional.only(start: 8));
    expect(
      hasSpacingPadding,
      isTrue,
      reason: 'כפתור המיון צריך רווח של 8 מצד שדה החיפוש',
    );
  });
}
