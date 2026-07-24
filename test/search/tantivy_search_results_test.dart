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

  /// פליטת state ישירות מהטסט (emit מוגן ולכן נחשף דרך מתודה ציבורית).
  void emitState(SearchState state) => emit(state);

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

String _allTextFromInlineSpan(InlineSpan span) {
  if (span is TextSpan) {
    return [
      span.text ?? '',
      for (final child in span.children ?? const <InlineSpan>[])
        _allTextFromInlineSpan(child),
    ].join();
  }
  return '';
}

String _highlightedTextFromInlineSpan(InlineSpan span) {
  if (span is TextSpan) {
    return [
      if (span.style?.fontWeight == FontWeight.bold) span.text ?? '',
      for (final child in span.children ?? const <InlineSpan>[])
        _highlightedTextFromInlineSpan(child),
    ].join();
  }
  return '';
}

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
          mergedCount: 1,
          merged: const [],
        ),
        SearchResult(
          id: BigInt.from(2),
          title: 'ספר ב',
          reference: 'סימן ב',
          text: '<font color="red">טקסט</font> עם HTML',
          segment: BigInt.one,
          isPdf: false,
          filePath: 'book_1.txt',
          mergedCount: 1,
          merged: const [],
        ),
        SearchResult(
          id: BigInt.from(3),
          title: 'ספר ג',
          reference: 'סימן ג',
          text: 'ברוך יהוה',
          segment: BigInt.two,
          isPdf: false,
          filePath: 'book_2.txt',
          mergedCount: 1,
          merged: const [],
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
            mergedCount: 1,
            merged: const [],
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
      await tester.drag(find.byType(ListView), const Offset(0, -100000));
      await tester.pump();

      expect(
        searchBloc.recordedEvents.whereType<LoadMoreResults>().length,
        1,
      );
    });

    testWidgets('חיפוש חדש (שינוי קטגוריה) מאפס את הגלילה לראש הרשימה', (
      tester,
    ) async {
      await tester.pumpWidget(buildWidget());
      await tester.pump();

      await tester.drag(find.byType(ListView), const Offset(0, -2000));
      await tester.pump();
      final scrolledOffset = tester
          .widget<ListView>(find.byType(ListView))
          .controller!
          .offset;
      expect(scrolledOffset, greaterThan(0));

      // חיפוש חדש: אותה שאילתה אך קטגוריה שונה → גלילה לראש
      searchBloc.emitState(
        searchBloc.state.copyWith(
          configuration: searchBloc.state.configuration.copyWith(
            currentFacets: const ['קטגוריה אחרת'],
          ),
        ),
      );
      await tester.pump(); // listener
      await tester.pump(); // addPostFrameCallback → jumpTo(0)

      final resetOffset = tester
          .widget<ListView>(find.byType(ListView))
          .controller!
          .offset;
      expect(resetOffset, 0);
    });

    testWidgets('טעינת המשך (אותה חתימה) שומרת על מיקום הגלילה', (
      tester,
    ) async {
      await tester.pumpWidget(buildWidget());
      await tester.pump();

      await tester.drag(find.byType(ListView), const Offset(0, -2000));
      await tester.pump();
      final scrolledOffset = tester
          .widget<ListView>(find.byType(ListView))
          .controller!
          .offset;
      expect(scrolledOffset, greaterThan(0));

      // טעינת המשך: אותה שאילתה+קטגוריה, תוצאות נוספות נדחפות לסוף
      final moreResults = [
        ...searchBloc.state.results,
        SearchResult(
          id: BigInt.from(999),
          title: 'ספר נוסף',
          reference: 'סימן נוסף',
          text: 'טקסט נוסף',
          segment: BigInt.from(999),
          isPdf: false,
          filePath: 'book_999.txt',
          mergedCount: 1,
          merged: const [],
        ),
      ];
      searchBloc.emitState(searchBloc.state.copyWith(results: moreResults));
      await tester.pump();
      await tester.pump();

      final keptOffset = tester
          .widget<ListView>(find.byType(ListView))
          .controller!
          .offset;
      expect(keptOffset, scrolledOffset);
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

    testWidgets('לחיצה על כפתור העתקה מעתיקה את טקסט התוצאה ללוח', (
      tester,
    ) async {
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
      expect(copiedText, isNot(contains('<font')));
      expect(copiedText, contains('טקסט'));
      expect(copiedText, contains('HTML'));
    });

    testWidgets('מציג הדגשת HTML שמגיעה ממנוע החיפוש', (tester) async {
      await tester.pumpWidget(buildWidget());
      await tester.pump();

      final highlightedResultText = tester
          .widgetList<RichText>(
            find.byWidgetPredicate(
              (widget) =>
                  widget is RichText &&
                  _allTextFromInlineSpan(widget.text).contains('HTML'),
            ),
          )
          .single;

      expect(
        _allTextFromInlineSpan(highlightedResultText.text),
        'טקסט עם HTML',
      );
      expect(
        _highlightedTextFromInlineSpan(highlightedResultText.text),
        'טקסט',
      );
    });

    testWidgets(
      'כאשר replaceHolyNames פעיל, הטקסט המועתק כולל החלפת שמות קודש',
      (tester) async {
        final holyNamesSettingsBloc = MockSettingsBloc();
        addTearDown(holyNamesSettingsBloc.close);
        whenListen(
          holyNamesSettingsBloc,
          const Stream<SettingsState>.empty(),
          initialState: SettingsState.initial().copyWith(
            replaceHolyNames: true,
          ),
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
      },
    );
  });
}
