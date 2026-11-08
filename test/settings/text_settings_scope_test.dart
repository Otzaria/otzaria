// חלונית הגדרות הקריאה מציגה את ההגדרות שחלות על החלונית הפעילה.

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/settings/panels/reading_settings_panel.dart';
import 'package:otzaria/settings/tabs/text_settings_tab.dart';
import 'package:otzaria/settings/widgets/settings_widgets_exports.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_event.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';

import '../test_helpers/memory_cache_provider.dart';

const _results = 'גודל טקסט בתוצאות החיפוש';
const _book = 'גודל גופן הספר';
const _bookOnly = ['גודל גופן מפרשים', 'גופן מפרשים', 'רוחב הטקסט'];
const _shared = [
  'גופן טקסט',
  'מרווח בין שורות',
  'מצב קריאה בתנ"ך ובתלמוד',
  'תצוגת הטקסט',
  'העתקת כותרות ופרקים',
  'הגדרות לפי ספר',
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  late _TestSettingsBloc settings;

  setUp(() {
    settings = _TestSettingsBloc(
      SettingsState.initial().copyWith(fontSize: 34, searchResultsFontSize: 20),
    );
  });
  tearDown(() => settings.close());

  Future<void> pump(WidgetTester tester, Widget child) async {
    // גבוה מספיק כדי שכל הכרטיסים ייבנו בלי גלילה.
    await tester.binding.setSurfaceSize(const Size(1400, 4000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BlocProvider<SettingsBloc>.value(value: settings, child: child),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> pumpPanel(WidgetTester tester, OpenedTab tab) async {
    final tabs = _TestTabsBloc(TabsState(tabs: [tab], currentTabIndex: 0));
    addTearDown(() async {
      await tabs.close();
      tab.dispose();
    });
    await pump(
      tester,
      BlocProvider<TabsBloc>.value(
        value: tabs,
        child: const ReadingSettingsPanel(),
      ),
    );
  }

  void expectShown(Iterable<String> labels, Matcher matcher) {
    for (final label in labels) {
      expect(find.text(label), matcher, reason: label);
    }
  }

  testWidgets('מסך ההגדרות מציג הכל, כולל גודל התוצאות', (tester) async {
    await pump(tester, const TextSettingsTab());

    expectShown([_results, _book, ..._bookOnly, ..._shared], findsOneWidget);
    expect(find.text('20'), findsOneWidget);
  });

  testWidgets('כרטיסיית חיפוש: רק מה שחל על התוצאות ועל התצוגה המקדימה', (
    tester,
  ) async {
    await pumpPanel(tester, SearchingTab('חיפוש', 'בראשית'));

    expect(
      tester.widget<TextSettingsTab>(find.byType(TextSettingsTab)).scope,
      TextSettingsScope.searchResults,
    );
    // גודל הספר נשאר: התצוגה המקדימה נפתחת בו.
    expectShown([_results, _book, ..._shared], findsOneWidget);
    expectShown(_bookOnly, findsNothing);
  });

  // הערת בעל הפרויקט 4.11: גודל התוצאות מעל "מצב קריאה בתנ"ך", ואחרי גודל
  // הספר והגופן, כמו בכרטיסיית ספר.
  testWidgets('בחיפוש גודל התוצאות מעל מצב הקריאה ושולח את האירוע שלו', (
    tester,
  ) async {
    await pumpPanel(tester, SearchingTab('חיפוש', 'בראשית'));

    double top(String label) => tester.getTopLeft(find.text(label)).dy;
    expect(top(_results), greaterThan(top(_book)));
    expect(top(_results), lessThan(top('מצב קריאה בתנ"ך ובתלמוד')));

    final resultsSlider = find.descendant(
      of: find.ancestor(
        of: find.text(_results),
        matching: find.byType(SettingsSliderTile),
      ),
      matching: find.byType(Slider),
    );
    tester.widget<Slider>(resultsSlider).onChanged!(24);
    await tester.pump();

    expect(settings.events.whereType<UpdateSearchResultsFontSize>(), [
      const UpdateSearchResultsFontSize(24),
    ]);
    expect(settings.events.whereType<UpdateFontSize>(), isEmpty);
  });

  testWidgets('כרטיסיית ספר: הכל חוץ מגודל התוצאות', (tester) async {
    await pumpPanel(
      tester,
      TextBookTab(book: TextBook(title: 'בראשית'), index: 0),
    );

    expectShown([_book, ..._bookOnly, ..._shared], findsOneWidget);
    expect(find.text(_results), findsNothing);
  });

  testWidgets('בתצוגה מפוצלת ההגדרות מתחלפות לפי החלונית הפעילה', (
    tester,
  ) async {
    final search = SearchingTab('חיפוש', 'בראשית');
    final book = TextBookTab(book: TextBook(title: 'בראשית'), index: 0);
    final combined = CombinedTab(rightTab: search, leftTab: book);
    final tabs = _TestTabsBloc(
      TabsState(tabs: [combined], currentTabIndex: 0, rawActivePane: search),
    );
    addTearDown(() async {
      await tabs.close();
      combined.dispose();
    });
    await pump(
      tester,
      BlocProvider<TabsBloc>.value(
        value: tabs,
        child: const ReadingSettingsPanel(),
      ),
    );

    expectShown([_results, _book, ..._shared], findsOneWidget);
    expectShown(_bookOnly, findsNothing);

    tabs.push(tabs.state.copyWith(activePane: ActivePaneUpdate.set(book)));
    await tester.pumpAndSettle();
    expectShown([_book, ..._bookOnly, ..._shared], findsOneWidget);
    expect(find.text(_results), findsNothing);

    tabs.push(tabs.state.copyWith(activePane: ActivePaneUpdate.set(search)));
    await tester.pumpAndSettle();
    expect(find.text(_results), findsOneWidget);
    expectShown(_bookOnly, findsNothing);
  });
}

class _TestSettingsBloc extends Bloc<SettingsEvent, SettingsState>
    implements SettingsBloc {
  _TestSettingsBloc(super.initialState) {
    on<SettingsEvent>((event, emit) => events.add(event));
  }

  final List<SettingsEvent> events = [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestTabsBloc extends Bloc<TabsEvent, TabsState> implements TabsBloc {
  _TestTabsBloc(super.initialState) {
    on<TabsEvent>((event, emit) {});
  }

  void push(TabsState state) => emit(state);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
