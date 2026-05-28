import 'package:bloc_test/bloc_test.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/search/bloc/search_bloc.dart';
import 'package:otzaria/search/bloc/search_event.dart';
import 'package:otzaria/search/bloc/search_state.dart';
import 'package:otzaria/search/view/tantivy_search_results.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';

class MockSearchBloc extends MockBloc<SearchEvent, SearchState>
    implements SearchBloc {}

class MockSettingsBloc extends MockBloc<SettingsEvent, SettingsState>
    implements SettingsBloc {}

class RecordingSearchBloc extends SearchBloc {
  RecordingSearchBloc(this.initialSearchState) {
    emit(initialSearchState);
  }

  final SearchState initialSearchState;
  final List<SearchEvent> recordedEvents = [];

  @override
  void add(SearchEvent event) {
    recordedEvents.add(event);
    if (event is! LoadMoreResults) {
      super.add(event);
    }
  }
}

// אינדקסים קבועים לתוצאות הטסט
const _kPlainTextIndex = 0;
const _kHtmlTextIndex = 1;
const _kHolyNamesIndex = 2;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TantivySearchResults', () {
    late RecordingSearchBloc searchBloc;
    late MockSettingsBloc settingsBloc;
    late SearchingTab tab;

    setUp(() {
      settingsBloc = MockSettingsBloc();
      tab = SearchingTab('חיפוש', 'בדיקה');

      final results = [
        SearchResult(
          id: BigInt.from(1),
          title: 'ספר א',
          reference: 'סימן א',
          text: 'טקסט בדיקה 0',
          segment: BigInt.zero,
          isPdf: false,
          filePath: 'book_0.txt',
        ),
        SearchResult(
          id: BigInt.from(2),
          title: 'ספר ב',
          reference: 'סימן ב',
          text: '<b>טקסט</b> עם <em>HTML</em>',
          segment: BigInt.one,
          isPdf: false,
          filePath: 'book_1.txt',
        ),
        SearchResult(
          id: BigInt.from(3),
          title: 'ספר ג',
          reference: 'סימן ג',
          text: 'ברוך יהוה',
          segment: BigInt.two,
          isPdf: false,
          filePath: 'book_2.txt',
        ),
        ...List.generate(
          97,
          (i) => SearchResult(
            id: BigInt.from(i + 4),
            title: 'ספר ${i + 3}',
            reference: 'סימן ${i + 3}',
            text: 'טקסט בדיקה ${i + 3}',
            segment: BigInt.from(i + 3),
            isPdf: false,
            filePath: 'book_${i + 3}.txt',
          ),
        ),
      ];

      searchBloc = RecordingSearchBloc(
        SearchState(
          searchQuery: 'בדיקה',
          totalResults: 200,
          results: results,
        ),
      );

      whenListen(
        settingsBloc,
        const Stream<SettingsState>.empty(),
        initialState: SettingsState.initial(),
      );
    });

    tearDown(() async {
      tab.dispose();
      await searchBloc.close();
      await settingsBloc.close();
    });

    Widget buildWidget({MockSettingsBloc? overrideSettingsBloc}) {
      return MaterialApp(
        home: MultiBlocProvider(
          providers: [
            BlocProvider<SearchBloc>.value(value: searchBloc),
            BlocProvider<SettingsBloc>.value(
              value: overrideSettingsBloc ?? settingsBloc,
            ),
          ],
          child: Scaffold(
            body: SizedBox(
              height: 500,
              child: TantivySearchResults(tab: tab),
            ),
          ),
        ),
      );
    }

    testWidgets('גלילה לתחתית טוענת עוד תוצאות אוטומטית', (tester) async {
      await tester.pumpWidget(buildWidget());

      await tester.pump();
      await tester.drag(find.byType(ListView), const Offset(0, -12000));
      await tester.pump();

      expect(
        searchBloc.recordedEvents.whereType<LoadMoreResults>().length,
        1,
      );
    });

    testWidgets('כפתור העתקה מוצג בכרטיסי תוצאות', (tester) async {
      await tester.pumpWidget(buildWidget());
      await tester.pump();

      expect(
        find.byWidgetPredicate(
          (w) => w is Icon && w.icon == FluentIcons.copy_24_regular,
        ),
        findsWidgets,
      );
    });

    testWidgets('לחיצה על כפתור העתקה מעתיקה את טקסט התוצאה ללוח',
        (tester) async {
      String? copiedText;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copiedText = (call.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );

      await tester.pumpWidget(buildWidget());
      await tester.pump();

      final copyButtons = find.byWidgetPredicate(
        (w) => w is Icon && w.icon == FluentIcons.copy_24_regular,
      );
      await tester.tap(copyButtons.at(_kPlainTextIndex));
      await tester.pump();

      expect(copiedText, 'טקסט בדיקה 0');
    });

    testWidgets('כפתור העתקה מסיר תגיות HTML מהטקסט', (tester) async {
      String? copiedText;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copiedText = (call.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );

      await tester.pumpWidget(buildWidget());
      await tester.pump();

      final copyButtons = find.byWidgetPredicate(
        (w) => w is Icon && w.icon == FluentIcons.copy_24_regular,
      );
      await tester.tap(copyButtons.at(_kHtmlTextIndex));
      await tester.pump();

      expect(copiedText, isNotNull);
      expect(copiedText, isNot(contains('<b>')));
      expect(copiedText, isNot(contains('<em>')));
      expect(copiedText, contains('טקסט'));
      expect(copiedText, contains('HTML'));
    });

    testWidgets('כאשר replaceHolyNames פעיל, הטקסט המועתק כולל החלפת שמות קודש',
        (tester) async {
      final holyNamesSettingsBloc = MockSettingsBloc();
      addTearDown(holyNamesSettingsBloc.close);
      whenListen(
        holyNamesSettingsBloc,
        const Stream<SettingsState>.empty(),
        initialState: SettingsState.initial().copyWith(replaceHolyNames: true),
      );

      String? copiedText;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copiedText = (call.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );

      await tester.pumpWidget(
        buildWidget(overrideSettingsBloc: holyNamesSettingsBloc),
      );
      await tester.pump();

      final copyButtons = find.byWidgetPredicate(
        (w) => w is Icon && w.icon == FluentIcons.copy_24_regular,
      );
      await tester.tap(copyButtons.at(_kHolyNamesIndex));
      await tester.pump();

      expect(copiedText, isNotNull);
      expect(copiedText, isNot(contains('יהוה')));
      expect(copiedText, contains('יקוק'));
    });
  });
}
