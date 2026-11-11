import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/pdf_book/bloc/pdf_book_bloc.dart';
import 'package:otzaria/pdf_book/bloc/pdf_book_state.dart';
import 'package:otzaria/pdf_book/models/pdf_reading_location.dart';
import 'package:otzaria/pdf_book/view/widgets/pdf_navigation_back_scope.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';

import '../helpers/memory_settings_cache.dart';

class _TabsBloc extends MockBloc<TabsEvent, TabsState> implements TabsBloc {}

void main() {
  testWidgets('חזרת מערכת משתמשת רק בהיסטוריית החלונית הפעילה', (tester) async {
    await Settings.init(cacheProvider: MemorySettingsCache());
    final tab = PdfBookTab(
      book: PdfBook(title: 'ספר', path: '/book.pdf'),
      pageNumber: 1,
    );
    final other = PdfBookTab(
      book: PdfBook(title: 'ספר אחר', path: '/other.pdf'),
      pageNumber: 1,
    );
    final bloc = PdfBookBloc(
      tab: tab,
      initialState: PdfBookInitial(book: tab.book, initialPageNumber: 1),
      pdfrxInit: () async {},
    );
    final loaded = PdfBookLoaded(
      book: tab.book,
      currentPageNumber: 1,
      totalPages: 10,
      isLoading: false,
    );
    // ignore: invalid_use_of_visible_for_testing_member
    bloc.emit(loaded);
    tab.navigationHistory.remember(
      const PdfReadingLocation(pageNumber: 1, pageOffset: Offset.zero, zoom: 1),
    );
    final tabsBloc = _TabsBloc();
    final states = StreamController<TabsState>();
    whenListen(
      tabsBloc,
      states.stream,
      initialState: TabsState(tabs: [tab, other], currentTabIndex: 0),
    );
    addTearDown(states.close);
    addTearDown(tabsBloc.close);
    addTearDown(bloc.close);
    addTearDown(tab.dispose);
    addTearDown(other.dispose);
    final navigator = GlobalKey<NavigatorState>();
    var returns = 0;
    var builds = 0;
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: const Text('home'),
      ),
    );
    unawaited(
      navigator.currentState!.push<void>(
        MaterialPageRoute(
          builder: (_) => BlocProvider<TabsBloc>.value(
            value: tabsBloc,
            child: PdfNavigationBackScope(
              bloc: bloc,
              onBack: () => returns++,
              child: Builder(
                builder: (_) {
                  builds++;
                  return const Scaffold(body: Text('reader'));
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(returns, 1);
    expect(find.text('reader'), findsOneWidget);
    final previousBuilds = builds;
    states.add(TabsState(tabs: [tab, other], currentTabIndex: 1));
    await tester.pump();
    await tester.pump();
    expect(tabsBloc.state.activePane, same(other));
    expect(
      tester
          .widget<PopScope>(
            find.byWidgetPredicate((widget) => widget is PopScope),
          )
          .canPop,
      isTrue,
    );
    expect(builds, previousBuilds);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(returns, 1);
    expect(find.text('home'), findsOneWidget);
  });
}
