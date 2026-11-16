import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/bookmarks/models/bookmark.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/history/bloc/history_event.dart';
import 'package:otzaria/history/bloc/history_state.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/view/recent_books_empty_state.dart';

import '../helpers/memory_settings_cache.dart';

class _HistoryBloc extends MockBloc<HistoryEvent, HistoryState>
    implements HistoryBloc {}

class _RecordingTabsBloc extends MockBloc<TabsEvent, TabsState>
    implements TabsBloc {
  final sent = <TabsEvent>[];

  @override
  void add(TabsEvent event) => sent.add(event);
}

class _RecordingNavigationBloc
    extends MockBloc<NavigationEvent, NavigationState>
    implements NavigationBloc {
  final sent = <NavigationEvent>[];

  @override
  void add(NavigationEvent event) => sent.add(event);
}

Bookmark _book(String title, {String? path, int index = 4}) => Bookmark(
  ref: '$title דף ב',
  book: PdfBook(title: title, path: path ?? '/tmp/$title.pdf'),
  index: index,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => Settings.init(cacheProvider: MemorySettingsCache()));

  test('ללא חיפושים, ללא כפילויות, שומר על סדר ועל מהדורות שונות', () {
    final a = _book('שבת');
    final aSecondPlace = _book('שבת', index: 12);
    final b = _book('ברכות');
    final anotherEdition = _book('שבת', path: '/tmp/other.pdf');
    final search = Bookmark(
      ref: 'שבת',
      book: TextBook(title: 'שבת'),
      index: 0,
      isSearch: true,
    );
    final history = [search, a, aSecondPlace, b, anotherEdition];

    expect(recentReadingBooks(history, limit: 2), [a, b]);
    expect(recentReadingBooks(history), [a, b, anotherEdition]);
    expect(recentReadingBooks(history, limit: 0), isEmpty);
  });

  for (final (width, count) in [(360.0, 2), (800.0, 3), (1400.0, 4)]) {
    testWidgets('מסך ברוחב $width מציג רק $count ספרים אחרונים', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final history = _HistoryBloc();
      addTearDown(history.close);
      whenListen(
        history,
        const Stream<HistoryState>.empty(),
        initialState: HistoryLoaded([
          for (var i = 0; i < 5; i++) _book('ספר $i'),
        ]),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<HistoryBloc>.value(
            value: history,
            child: const RecentBooksEmptyState(),
          ),
        ),
      );

      for (var i = 0; i < 5; i++) {
        expect(find.text('ספר $i'), i < count ? findsOneWidget : findsNothing);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('ספר מההיסטוריה פותח את המיקום השמור באמצעות המסלול הרגיל', (
    tester,
  ) async {
    final history = _HistoryBloc();
    final tabs = _RecordingTabsBloc();
    final navigation = _RecordingNavigationBloc();
    addTearDown(history.close);
    addTearDown(tabs.close);
    addTearDown(navigation.close);
    whenListen(
      history,
      const Stream<HistoryState>.empty(),
      initialState: HistoryLoaded([_book('ברכות', index: 23)]),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: MultiBlocProvider(
          providers: [
            BlocProvider<HistoryBloc>.value(value: history),
            BlocProvider<TabsBloc>.value(value: tabs),
            BlocProvider<NavigationBloc>.value(value: navigation),
          ],
          child: const RecentBooksEmptyState(),
        ),
      ),
    );
    await tester.tap(find.text('ברכות'));
    expect(tabs.sent, hasLength(1));
    final event = tabs.sent.single as OpenOrFocusTab;
    expect(event.matchHistorySlot, isTrue);
    expect((event.tab as PdfBookTab).pageNumber, 23);
    expect(navigation.sent.single, isA<NavigateToScreen>());
  });

  testWidgets('אין הצעות כאשר ההיסטוריה ריקה', (tester) async {
    final history = _HistoryBloc();
    addTearDown(history.close);
    whenListen(
      history,
      const Stream<HistoryState>.empty(),
      initialState: HistoryLoaded([]),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<HistoryBloc>.value(
          value: history,
          child: const RecentBooksEmptyState(),
        ),
      ),
    );
    expect(find.text('נפתחו לאחרונה'), findsNothing);
    expect(find.text('דפדף בספרייה'), findsOneWidget);
  });
}
