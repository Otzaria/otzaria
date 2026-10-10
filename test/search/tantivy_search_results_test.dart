import 'package:bloc_test/bloc_test.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/messages/library_messages.dart';
import 'package:otzaria/data/data_providers/tantivy_data_provider.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/search/bloc/search_bloc.dart';
import 'package:otzaria/search/bloc/search_event.dart';
import 'package:otzaria/search/bloc/search_state.dart';
import 'package:otzaria/search/models/external_search_status.dart';
import 'package:otzaria/search/utils/index_freshness_warner.dart';
import 'package:otzaria/search/utils/result_text_status.dart';
import 'package:otzaria/search/view/search_result_source_tag.dart';
import 'package:otzaria/search/view/tantivy_search_results.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:otzaria/tabs/models/searching_tab.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';

import '../test_helpers/memory_cache_provider.dart';

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
          textStatus: TextStatus.ok,
          continuesToNextLine: false,
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
          textStatus: TextStatus.ok,
          continuesToNextLine: false,
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
          textStatus: TextStatus.ok,
          continuesToNextLine: false,
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
            textStatus: TextStatus.ok,
            continuesToNextLine: false,
          ),
        ),
      ];

      searchBloc = RecordingSearchBloc(
        SearchState(searchQuery: 'בדיקה', totalResults: 200, results: results),
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
            body: SizedBox(height: 500, child: TantivySearchResults(tab: tab)),
          ),
        ),
      );
    }

    testWidgets('בלי מדור תוצאות חיצוני אין תגית מקור על הכרטיסים', (
      tester,
    ) async {
      await tester.pumpWidget(buildWidget());
      await tester.pump();

      expect(find.byType(SearchResultSourceTag), findsNothing);
    });

    testWidgets('כשמדור חיצוני פעיל, כל כרטיס נושא תגית "אוצריא"', (
      tester,
    ) async {
      await tester.pumpWidget(buildWidget());
      await tester.pump();

      tab.externalSearchStatus.value = const ExternalSearchStatus(
        sourceTitle: 'היברובוקס',
        loading: false,
        books: 3,
        hits: 7,
      );
      await tester.pump();

      expect(find.byType(SearchResultSourceTag), findsWidgets);
      expect(find.text('אוצריא'), findsWidgets);
    });

    testWidgets('גלילה לתחתית טוענת עוד תוצאות אוטומטית', (tester) async {
      await tester.pumpWidget(buildWidget());

      await tester.pump();
      await tester.drag(
        find.byType(CustomScrollView),
        const Offset(0, -100000),
      );
      await tester.pump();

      expect(searchBloc.recordedEvents.whereType<LoadMoreResults>().length, 1);
    });

    testWidgets('חיפוש חדש (שינוי קטגוריה) מאפס את הגלילה לראש הרשימה', (
      tester,
    ) async {
      await tester.pumpWidget(buildWidget());
      await tester.pump();

      await tester.drag(find.byType(CustomScrollView), const Offset(0, -2000));
      await tester.pump();
      final scrolledOffset = tester
          .widget<CustomScrollView>(find.byType(CustomScrollView))
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
          .widget<CustomScrollView>(find.byType(CustomScrollView))
          .controller!
          .offset;
      expect(resetOffset, 0);
    });

    testWidgets('שינוי מיון (אותה שאילתה וקטגוריה) מאפס את הגלילה לראש', (
      tester,
    ) async {
      await tester.pumpWidget(buildWidget());
      await tester.pump();

      await tester.drag(find.byType(CustomScrollView), const Offset(0, -2000));
      await tester.pump();
      double offset() => tester
          .widget<CustomScrollView>(find.byType(CustomScrollView))
          .controller!
          .offset;
      expect(offset(), greaterThan(0));

      // כמו UpdateSortOrder: הגדרה חדשה וטעינה, ואז הרשימה בסדר חדש.
      searchBloc.emitState(
        searchBloc.state.copyWith(
          configuration: searchBloc.state.configuration.copyWith(
            sortBy: ResultsOrder.relevance,
          ),
          isLoading: true,
        ),
      );
      await tester.pump();
      searchBloc.emitState(
        searchBloc.state.copyWith(
          results: searchBloc.state.results.reversed.toList(),
          isLoading: false,
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(offset(), 0);
    });

    testWidgets('טעינת המשך (אותה חתימה) שומרת על מיקום הגלילה', (
      tester,
    ) async {
      await tester.pumpWidget(buildWidget());
      await tester.pump();

      await tester.drag(find.byType(CustomScrollView), const Offset(0, -2000));
      await tester.pump();
      final scrolledOffset = tester
          .widget<CustomScrollView>(find.byType(CustomScrollView))
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
          textStatus: TextStatus.ok,
          continuesToNextLine: false,
        ),
      ];
      searchBloc.emitState(searchBloc.state.copyWith(results: moreResults));
      await tester.pump();
      await tester.pump();

      final keptOffset = tester
          .widget<CustomScrollView>(find.byType(CustomScrollView))
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

    testWidgets('תוצאה שהמנוע לא קרא את הטקסט שלה מציגה הודעה ולא שורה ריקה', (
      tester,
    ) async {
      SearchResult result(int i, String text, TextStatus status) =>
          SearchResult(
            id: BigInt.from(i),
            title: 'ספר $i',
            reference: 'סימן $i',
            text: text,
            segment: BigInt.from(i),
            isPdf: false,
            filePath: 'id:$i',
            mergedCount: 1,
            merged: const [],
            textStatus: status,
            continuesToNextLine: false,
          );
      searchBloc.emitState(
        searchBloc.state.copyWith(
          totalResults: 2,
          results: [
            result(1, '', TextStatus.unavailable),
            result(2, 'שורה שהשתנתה &amp; נוספה', TextStatus.stale),
          ],
        ),
      );
      await tester.pumpWidget(buildWidget());
      await tester.pump();

      expect(find.text(unavailableResultText), findsOneWidget);
      final staleText = tester
          .widgetList<RichText>(find.byType(RichText))
          .map((widget) => _allTextFromInlineSpan(widget.text))
          .where((text) => text.contains('שורה שהשתנתה'));
      expect(staleText, ['שורה שהשתנתה & נוספה']);
    });

    group('טקסט שהשתנה או אינו זמין', () {
      SearchResult result(int i, String text, TextStatus status) =>
          SearchResult(
            id: BigInt.from(i),
            title: 'ספר $i',
            reference: 'סימן $i',
            text: text,
            segment: BigInt.from(i),
            isPdf: false,
            filePath: 'id:$i',
            mergedCount: 1,
            merged: const [],
            textStatus: status,
            continuesToNextLine: false,
          );

      Finder copyButtons() => find.ancestor(
        of: find.byWidgetPredicate(
          (w) => w is Icon && w.icon == FluentIcons.copy_24_regular,
        ),
        matching: find.byType(IconButton),
      );

      testWidgets('שורה שנמחקה (stale ריק) מוצגת כלא-זמינה, '
          'ואין מה להעתיק ממנה', (tester) async {
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
        searchBloc.emitState(
          searchBloc.state.copyWith(
            totalResults: 3,
            results: [
              result(1, '', TextStatus.unavailable),
              result(2, '', TextStatus.stale),
              result(3, 'שורה קיימת', TextStatus.ok),
            ],
          ),
        );
        await tester.pumpWidget(buildWidget());
        await tester.pump();

        expect(find.text(unavailableResultText), findsNWidgets(2));
        final enabled = tester
            .widgetList<IconButton>(copyButtons())
            .map((button) => button.onPressed != null)
            .toList();
        expect(enabled, [false, false, true]);

        await tester.tap(copyButtons().at(2));
        await tester.pump();
        expect(copiedText, 'שורה קיימת');
      });

      testWidgets('תוצאה stale מפעילה את בדיקת טריות האינדקס של הספר', (
        tester,
      ) async {
        final warner = IndexFreshnessWarner.instance;
        final checkedBooks = <String>[];
        final notifications = <String>[];
        final engine = _FingerprintEngine();
        warner
          ..resetForTesting()
          ..providerResolver = (() => _WarnerProvider(engine))
          ..debugBookVerifier = (book, _) async {
            checkedBooks.add(book.title);
            return false;
          }
          ..debugNotifier = notifications.add;
        addTearDown(warner.resetForTesting);
        await Settings.init(cacheProvider: MemoryCacheProvider());
        DataRepository.instance.library = Future.value(
          Library(categories: [])
            ..books.addAll([
              TextBook(id: 7, title: 'ספר 7'),
              TextBook(id: 8, title: 'ספר 8'),
            ]),
        );

        await tester.pumpWidget(buildWidget());
        await tester.pump();
        searchBloc.emitState(
          searchBloc.state.copyWith(
            totalResults: 3,
            results: [
              result(7, 'שורה שהשתנתה', TextStatus.stale),
              result(7, '', TextStatus.stale),
              result(8, 'שורה תקינה', TextStatus.ok),
            ],
          ),
        );
        await tester.pump();
        await tester.pump();

        expect(checkedBooks, ['ספר 7']);
        expect(notifications, [LibraryMessages.searchResultContentDrifted]);
      });
    });

    testWidgets('מספר תוצאה בן 4 ספרות נשאר בשורה אחת בתוך הריבוע', (
      tester,
    ) async {
      searchBloc.emitState(
        SearchState(
          searchQuery: 'בדיקה',
          totalResults: 1000,
          results: List.generate(
            1000,
            (i) => SearchResult(
              id: BigInt.from(i + 1),
              title: 'ספר ${i + 1}',
              reference: 'סימן ${i + 1}',
              text: 'טקסט ${i + 1}',
              segment: BigInt.from(i),
              isPdf: false,
              filePath: 'book_$i.txt',
              mergedCount: 1,
              merged: const [],
              textStatus: TextStatus.ok,
              continuesToNextLine: false,
            ),
          ),
        ),
      );

      await tester.pumpWidget(buildWidget());
      await tester.pump();

      final badge = find.text('1000');
      await tester.scrollUntilVisible(badge, 20000, maxScrolls: 200);

      expect(badge, findsOneWidget);
      // שבירה לשתי שורות הייתה מכפילה את גובה הטקסט (גופן 16)
      expect(tester.getSize(badge).height, lessThan(30));
    });

    // מיפוי התקלה: המשתמש מגדיר "העתקה עם כותרת" (copyWithHeaders +
    // copyHeaderFormat) — ההגדרה מכובדת בהעתקה ממסך הקריאה
    // (context_menu_utils) אבל כפתור ההעתקה בתוצאות החיפוש התעלם ממנה
    // והעתיק את הטקסט בלבד, בלי המקור והכותרת.
    group('העתקה עם כותרת ומקור לפי ההגדרות', () {
      Future<String?> copyWithSettings(
        WidgetTester tester, {
        required String copyWithHeaders,
        required String copyHeaderFormat,
        int resultIndex = _kPlainTextIndex,
      }) async {
        final headersSettingsBloc = MockSettingsBloc();
        addTearDown(headersSettingsBloc.close);
        whenListen(
          headersSettingsBloc,
          const Stream<SettingsState>.empty(),
          initialState: SettingsState.initial().copyWith(
            copyWithHeaders: copyWithHeaders,
            copyHeaderFormat: copyHeaderFormat,
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
          buildWidget(overrideSettingsBloc: headersSettingsBloc),
        );
        await tester.pump();

        final copyButtons = find.byWidgetPredicate(
          (w) => w is Icon && w.icon == FluentIcons.copy_24_regular,
        );
        await tester.tap(copyButtons.at(resultIndex));
        await tester.pump();
        return copiedText;
      }

      testWidgets('שם ספר ומקור בשורה נפרדת לפני הטקסט', (tester) async {
        final copied = await copyWithSettings(
          tester,
          copyWithHeaders: 'book_and_path',
          copyHeaderFormat: 'separate_line_before',
        );
        expect(copied, 'ספר א, סימן א\nטקסט בדיקה 0');
      });

      testWidgets('שם ספר בלבד, בסוגריים אחרי הטקסט', (tester) async {
        final copied = await copyWithSettings(
          tester,
          copyWithHeaders: 'book_name',
          copyHeaderFormat: 'same_line_after_brackets',
        );
        expect(copied, 'טקסט בדיקה 0 (ספר א)');
      });

      testWidgets('מקור שכבר פותח בשם הספר אינו מוכפל בכותרת', (tester) async {
        // כמו תוצאה אמיתית מהמנוע: reference = "עבודה זרה, דף עג." כשהספר
        // "עבודה זרה" — הכותרת חייבת להיות המקור המלא, בלי שם ספר כפול.
        searchBloc.emitState(
          searchBloc.state.copyWith(
            results: [
              SearchResult(
                id: BigInt.from(1),
                title: 'ספר א',
                reference: 'ספר א, סימן א',
                text: 'טקסט בדיקה 0',
                segment: BigInt.zero,
                isPdf: false,
                filePath: 'book_0.txt',
                mergedCount: 1,
                merged: const [],
                textStatus: TextStatus.ok,
                continuesToNextLine: false,
              ),
            ],
          ),
        );
        final copied = await copyWithSettings(
          tester,
          copyWithHeaders: 'book_and_path',
          copyHeaderFormat: 'same_line_after_brackets',
        );
        expect(copied, 'טקסט בדיקה 0 (ספר א, סימן א)');
      });

      testWidgets('ברירת המחדל none נשארת העתקת טקסט בלבד', (tester) async {
        final copied = await copyWithSettings(
          tester,
          copyWithHeaders: 'none',
          copyHeaderFormat: 'same_line_after_brackets',
        );
        expect(copied, 'טקסט בדיקה 0');
      });
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

class _FingerprintEngine implements SearchEngine {
  @override
  Future<BigInt> getBookTextFingerprint({required String filePath}) =>
      Future.value(BigInt.one);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _WarnerProvider implements TantivyDataProvider {
  _WarnerProvider(SearchEngine engine) : engine = Future.value(engine);

  @override
  Future<SearchEngine> engine;

  @override
  ValueNotifier<bool> isIndexing = ValueNotifier(false);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
