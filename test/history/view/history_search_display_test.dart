import 'dart:async';
import 'dart:collection';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/bookmarks/models/bookmark.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/history/bloc/history_event.dart';
import 'package:otzaria/history/bloc/history_state.dart';
import 'package:otzaria/history/view/history_screen.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/widgets/lists/items_list_view.dart';

import '../../helpers/memory_settings_cache.dart';

class _HistoryBloc extends MockBloc<HistoryEvent, HistoryState>
    implements HistoryBloc {}

class _CountingFacets extends ListBase<String> {
  final List<String> values;
  int reads = 0;

  _CountingFacets(this.values);

  @override
  int get length => values.length;

  @override
  set length(int value) => values.length = value;

  @override
  String operator [](int index) {
    reads++;
    return values[index];
  }

  @override
  void operator []=(int index, String value) => values[index] = value;
}

Bookmark _search({
  String query = 'שבת',
  List<String>? scope,
  List<String>? filter,
  Map<String, dynamic>? configuration,
}) => Bookmark(
  ref: query,
  book: TextBook(title: query),
  index: 0,
  isSearch: true,
  searchScopeFacets: scope,
  searchFilterFacets: filter,
  searchConfiguration: configuration,
);

({String? subtitle, String? tooltip}) _display(
  ItemsListView list,
  Bookmark item,
) => (
  subtitle: list.subtitleBuilder!(item),
  tooltip: list.subtitleTooltipBuilder!(item),
);

void main() {
  late _HistoryBloc bloc;
  late StreamController<HistoryState> states;

  setUpAll(() => Settings.init(cacheProvider: MemorySettingsCache()));
  setUp(() {
    bloc = _HistoryBloc();
    states = StreamController<HistoryState>.broadcast();
    whenListen(bloc, states.stream, initialState: HistoryLoaded([]));
  });
  tearDown(() => states.close());

  Widget buildWidget() => MaterialApp(
    home: Scaffold(
      body: BlocProvider<HistoryBloc>.value(
        value: bloc,
        child: const HistoryView(),
      ),
    ),
  );

  testWidgets('התיאורים משמרים null, בחירה ריקה, סדר, כפילויות ונתיבים', (
    tester,
  ) async {
    await tester.pumpWidget(buildWidget());
    final list = tester.widget<ItemsListView>(find.byType(ItemsListView));
    final cases = [
      (_search(), (subtitle: null, tooltip: null)),
      (_search(configuration: {}), (subtitle: null, tooltip: null)),
      (_search(scope: []), (subtitle: null, tooltip: null)),
      (
        _search(scope: ['/scope/א', '/scope/ב', '/scope/ג'], filter: []),
        (subtitle: 'ללא ספרים מסומנים', tooltip: null),
      ),
      (
        _search(configuration: {'distance': 5}),
        (subtitle: 'הגדרות: מרחק 5', tooltip: null),
      ),
      (
        _search(scope: ['/מדף/בראשית']),
        (subtitle: 'בקטגוריות: בראשית', tooltip: null),
      ),
      (
        _search(scope: ['/מדף/בראשית/', '//מדף//שמות///']),
        (subtitle: 'בקטגוריות: בראשית, שמות', tooltip: null),
      ),
      (
        _search(scope: ['//מדף//שם///', '/', '']),
        (subtitle: 'בקטגוריות: שם, /...', tooltip: 'בקטגוריות: שם, /, '),
      ),
      (
        _search(scope: ['מדף/א', 'מדף/ב', 'מדף/א', '////', 'bookKey:123']),
        (
          subtitle: 'בקטגוריות: א, ב...',
          tooltip: 'בקטגוריות: א, ב, א, ////, bookKey:123',
        ),
      ),
      (
        _search(
          scope: ['/scope/א'],
          filter: ['/filter/ג', '/filter/ב', '/filter/א'],
          configuration: {
            'distance': 5,
            'currentFacets': ['/ignored/ד'],
          },
        ),
        (
          subtitle: 'הגדרות: מרחק 5  •  בקטגוריות: ג, ב...',
          tooltip: 'הגדרות: מרחק 5  •  בקטגוריות: ג, ב, א',
        ),
      ),
      (
        _search(filter: [], configuration: {'distance': 5}),
        (subtitle: 'הגדרות: מרחק 5  •  ללא ספרים מסומנים', tooltip: null),
      ),
    ];
    for (final (item, expected) in cases) {
      expect(_display(list, item), expected);
      expect(_display(list, item), expected);
    }
    final names = List.generate(1000, (index) => 'ספר$index');
    expect(
      _display(
        list,
        _search(scope: names.map((name) => '/מדף/$name').toList()),
      ),
      (
        subtitle: 'בקטגוריות: ספר0, ספר1...',
        tooltip: 'בקטגוריות: ${names.join(', ')}',
      ),
    );
  });

  testWidgets('רשומות שונות באותה זהות חיפוש משמרות סדר ותיאורים עצמאיים', (
    tester,
  ) async {
    await tester.pumpWidget(buildWidget());
    final list = tester.widget<ItemsListView>(find.byType(ItemsListView));
    final first = _search(scope: ['/מדף/א', '/מדף/ב', '/מדף/ג']);
    final second = _search(scope: ['/מדף/ג', '/מדף/ב', '/מדף/א']);
    expect(first.historyKey, second.historyKey);
    expect(_display(list, first).tooltip, 'בקטגוריות: א, ב, ג');
    expect(_display(list, second).tooltip, 'בקטגוריות: ג, ב, א');
  });

  testWidgets('שני builders, הקלדה וחיצים חולקים מעבר יחיד על המסננים', (
    tester,
  ) async {
    await tester.pumpWidget(buildWidget());
    final facets = _CountingFacets(
      List.generate(1000, (index) => '/מדף/ספר$index'),
    );
    final item = _search(scope: facets);
    states.add(HistoryLoaded([item]));
    await tester.pump();
    expect(facets.reads, 1000);
    expect(find.text('בקטגוריות: ספר0, ספר1...'), findsOneWidget);
    expect(
      tester.widgetList<Tooltip>(find.byType(Tooltip)).map((t) => t.message),
      contains(
        'בקטגוריות: ${facets.values.map((f) => f.split('/').last).join(', ')}',
      ),
    );

    await tester.enterText(find.byType(TextField).first, 'שב');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    await tester.enterText(find.byType(TextField).first, '');
    await tester.pump();
    expect(find.text('בקטגוריות: ספר0, ספר1...'), findsOneWidget);
    expect(facets.reads, 1000);
  });

  testWidgets('היסטוריה בת 200 רשומות מחושבת רק לפי שורות שהתבקשו', (
    tester,
  ) async {
    await tester.pumpWidget(buildWidget());
    final facets = List.generate(
      200,
      (index) =>
          _CountingFacets(['/מדף/$index/א', '/מדף/$index/ב', '/מדף/$index/ג']),
    );
    final history = [for (final scope in facets) _search(scope: scope)];
    states.add(HistoryLoaded(history));
    await tester.pump();
    final visited = facets.where((f) => f.reads != 0).toList();
    expect(visited, isNotEmpty);
    expect(visited.length, lessThan(200));
    expect(visited.every((f) => f.reads == 3), isTrue);
    expect(facets.last.reads, 0);

    final list = tester.widget<ItemsListView>(find.byType(ItemsListView));
    final expected = (
      subtitle: 'בקטגוריות: א, ב...',
      tooltip: 'בקטגוריות: א, ב, ג',
    );
    expect(_display(list, history.last), expected);
    expect(facets.last.reads, 3);
    expect(_display(list, history.last), expected);
    expect(facets.last.reads, 3);
  });

  testWidgets('המטמון מוגבל ל-24 רשומות ומפנה את הרשומה שלא נקראה לאחרונה', (
    tester,
  ) async {
    await tester.pumpWidget(buildWidget());
    final list = tester.widget<ItemsListView>(find.byType(ItemsListView));
    final facets = List.generate(
      25,
      (index) =>
          _CountingFacets(['/מדף/$index/א', '/מדף/$index/ב', '/מדף/$index/ג']),
    );
    final history = [for (final scope in facets) _search(scope: scope)];
    for (final item in history.take(24)) {
      _display(list, item);
    }
    _display(list, history.first);
    _display(list, history.last);
    _display(list, history.first);
    expect(facets.first.reads, 3);
    expect(facets.last.reads, 3);
    _display(list, history[1]);
    expect(facets[1].reads, 6);
    expect(facets.skip(2).every((f) => f.reads == 3), isTrue);
  });

  testWidgets('מצב חדש מרענן גם שינויים בתוך אותן רשימות ומפות', (
    tester,
  ) async {
    await tester.pumpWidget(buildWidget());
    final scope = _CountingFacets(['/מדף/א', '/מדף/ב', '/מדף/ג']);
    final filter = _CountingFacets(['/מסנן/א', '/מסנן/ב', '/מסנן/ג']);
    final item = _search(
      scope: scope,
      filter: filter,
      configuration: {'distance': 5},
    );
    final history = [item];
    states.add(HistoryLoaded(history));
    await tester.pump();
    expect(filter.reads, 3);
    expect(scope.reads, 0);

    filter[0] = '/מסנן/ד';
    item.searchConfiguration!['distance'] = 9;
    states.add(HistoryLoaded(history));
    await tester.pump();
    var list = tester.widget<ItemsListView>(find.byType(ItemsListView));
    expect(_display(list, item), (
      subtitle: 'הגדרות: מרחק 9  •  בקטגוריות: ד, ב...',
      tooltip: 'הגדרות: מרחק 9  •  בקטגוריות: ד, ב, ג',
    ));
    expect(filter.reads, 6);

    filter.clear();
    states.add(HistoryLoaded(history));
    await tester.pump();
    expect(find.text('הגדרות: מרחק 9  •  ללא ספרים מסומנים'), findsOneWidget);
    list = tester.widget<ItemsListView>(find.byType(ItemsListView));
    expect(_display(list, item).tooltip, isNull);
    expect(scope.reads, 0);

    final scopedHistory = [_search(scope: scope)];
    states.add(HistoryLoaded(scopedHistory));
    await tester.pump();
    expect(find.text('בקטגוריות: א, ב...'), findsOneWidget);
    expect(scope.reads, 3);

    scope[0] = '/מדף/ה';
    states.add(HistoryLoaded(scopedHistory));
    await tester.pump();
    expect(find.text('בקטגוריות: ה, ב...'), findsOneWidget);
    expect(scope.reads, 6);

    states.add(HistoryLoaded(List.of(scopedHistory)));
    await tester.pump();
    expect(scope.reads, 9);
  });

  testWidgets('פריט קריאה אינו ממיר מסננים ותיאור המיקום נשמר', (tester) async {
    await tester.pumpWidget(buildWidget());
    final list = tester.widget<ItemsListView>(find.byType(ItemsListView));
    final facets = _CountingFacets(['/מדף/א', '/מדף/ב', '/מדף/ג']);
    final item = Bookmark(
      ref: 'שבת פרק א',
      book: TextBook(title: 'שבת'),
      index: 1,
      searchScopeFacets: facets,
    );
    expect(_display(list, item), (subtitle: 'פרק א', tooltip: null));
    expect(facets.reads, 0);
  });
}
