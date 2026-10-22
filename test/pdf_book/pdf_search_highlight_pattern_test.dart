import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/messages/pdf_messages.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/pdf_book/bloc/pdf_book_bloc.dart';
import 'package:otzaria/pdf_book/bloc/pdf_book_event.dart';
import 'package:otzaria/pdf_book/bloc/pdf_book_state.dart';
import 'package:otzaria/pdf_book/view/pdf_search_screen.dart';
import 'package:otzaria/search/in_book_search_preferences.dart';
import 'package:otzaria/search/utils/literal_search_pattern.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/engine/settings_event.dart';
import 'package:otzaria/settings/engine/settings_state.dart';
import 'package:pdfrx/pdfrx.dart';

import '../support/search_engine_test_init.dart';
import '../test_helpers/memory_cache_provider.dart';

class _MockSettingsBloc extends MockBloc<SettingsEvent, SettingsState>
    implements SettingsBloc {}

class _MockPdfBookBloc extends MockBloc<PdfBookEvent, PdfBookState>
    implements PdfBookBloc {}

class _FakeDocument extends Fake implements PdfDocument {
  @override
  Stream<PdfDocumentEvent> get events => const Stream.empty();
}

/// קונטרולר "מוכן" בלי PdfViewer אמיתי — [PdfTextSearchSession] דורש מסמך חי
/// בבנייה, ו-useDocument מוחזר null כדי שהחיפוש לא יגע ב-pdfium.
class _FakeReadyController extends PdfViewerController {
  @override
  bool get isReady => true;

  // קונטרולר אמיתי מוכן תמיד מחזיר עמוד; זה אינו מחובר לצפיין.
  @override
  int? get pageNumber => null;

  @override
  PdfDocument get document => _FakeDocument();

  @override
  void invalidate() {}

  @override
  FutureOr<T?> useDocument<T>(
    FutureOr<T> Function(PdfDocument document) task, {
    bool ensureLoaded = true,
    Completer<dynamic>? cancelLoading,
  }) => null;
}

/// מתעד את התבניות שנשלחו לסריקה ומחזיר התאמות שהטסט קובע, במקום לסרוק
/// מסמך אמיתי.
class _RecordingTextSearcher extends PdfTextSearchSession {
  _RecordingTextSearcher(super.controller, this.pageFullText);

  final String pageFullText;
  final List<Pattern> searches = [];
  List<PdfTextSearchResult> fakeMatches = const [];

  @override
  List<PdfTextSearchResult> get matches => fakeMatches;

  @override
  bool get isSearching => false;

  @override
  void startTextSearch(
    Pattern pattern, {
    bool caseInsensitive = true,
    bool goToFirstMatch = true,
    bool searchImmediately = false,
  }) {
    searches.add(pattern);
  }

  @override
  Future<PdfPageText?> loadText({required int pageNumber}) async => PdfPageText(
    pageNumber: pageNumber,
    fullText: pageFullText,
    charRects: const [],
    fragments: const [],
  );

  /// התאמה אחת בעמוד, כדי לדמות סריקה שהצליחה.
  void setSingleMatch() {
    final pageText = PdfPageText(
      pageNumber: 1,
      fullText: pageFullText,
      charRects: List.filled(pageFullText.length, const PdfRect(0, 1, 1, 0)),
      fragments: const [],
    );
    fakeMatches = [
      PdfTextSearchResult.fromRange(
        PdfPageTextRange(pageText: pageText, start: 0, end: 1),
      ),
    ];
  }

  /// התבניות שנשלחו לסריקה, בלי איפוסי השדה הריק.
  List<RegExp> get searchedPatterns => [
    for (final pattern in searches)
      if (pattern is RegExp) pattern,
  ];
}

/// שכבת טקסט של PDF סרוק בלי אף אות עברית — פיסוק וספרות בלבד.
final String _scannedOnlyPageText = List.generate(
  120,
  (i) => '.,;:${i % 10}"\'()[]-',
).join(' ');

PdfBookLoaded _loadedState() => PdfBookLoaded(
  book: PdfBook(title: 'ספר בדיקה', path: '/nonexistent/test.pdf'),
  currentPageNumber: 3,
  totalPages: 12,
  isLoading: false,
);

Future<_RecordingTextSearcher> _pumpSearchView(
  WidgetTester tester, {
  required String pageFullText,
}) async {
  final settingsBloc = _MockSettingsBloc();
  whenListen(
    settingsBloc,
    const Stream<SettingsState>.empty(),
    initialState: SettingsState.initial(),
  );
  final pdfBookBloc = _MockPdfBookBloc();
  whenListen(
    pdfBookBloc,
    const Stream<PdfBookState>.empty(),
    initialState: _loadedState(),
  );
  final searchController = TextEditingController();
  final focusNode = FocusNode();
  final textSearcher = _RecordingTextSearcher(
    _FakeReadyController(),
    pageFullText,
  );
  addTearDown(settingsBloc.close);
  addTearDown(pdfBookBloc.close);
  addTearDown(searchController.dispose);
  addTearDown(focusNode.dispose);
  addTearDown(textSearcher.dispose);

  await tester.pumpWidget(
    MaterialApp(
      home: MultiBlocProvider(
        providers: [
          BlocProvider<SettingsBloc>.value(value: settingsBloc),
          BlocProvider<PdfBookBloc>.value(value: pdfBookBloc),
        ],
        child: Scaffold(
          body: PdfBookSearchView(
            textSearcher: textSearcher,
            searchController: searchController,
            focusNode: focusNode,
            pdfFilePath: '/nonexistent/test.pdf',
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return textSearcher;
}

/// מקלידה שאילתה ומריצה את החיפוש הראשון (מעבר ל-debounce של השדה).
Future<void> _search(WidgetTester tester, String query) async {
  await tester.enterText(find.byType(EditableText).first, query);
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pump();
}

/// מדמה סיום סריקה: ה-listener של pdfrx מודיע עם התוצאות שנצברו.
Future<void> _finishScan(WidgetTester tester, _RecordingTextSearcher s) async {
  s.notifyListeners();
  await tester.pump();
  await tester.pump();
  await tester.pump();
}

/// מייצר מונחים עבריים ייחודיים (ללא אותיות סופיות, למניעת נרמול-שקילות).
String _term(int i) {
  const letters = 'אבגדהוזחטיכלמנסעפצקרשת';
  return 'קדם${letters[i % 22]}${letters[i ~/ 22]}';
}

Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final engineReady = await tryInitSearchEngine();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  group('buildAdvancedHighlightPattern - תבנית הדגשה על דפי PDF', () {
    test('תוצאות בלי תגי הדגשה מחזירות null', () {
      expect(
        PdfBookSearchView.buildAdvancedHighlightPattern([
          'טקסט בלי הדגשות',
          '<b>כותרת</b> עוד טקסט',
        ]),
        isNull,
      );
    });

    test('רשימת תוצאות ריקה מחזירה null', () {
      expect(
        PdfBookSearchView.buildAdvancedHighlightPattern(const []),
        isNull,
      );
    });

    group('עם המנוע', () {
      test('התבנית מתאימה למונח שהמנוע סימן, לא לשאילתה', () {
        // חיפוש fuzzy של "שבת" שמצא "שבתות" — על העמוד מודגש "שבתות".
        final pattern = PdfBookSearchView.buildAdvancedHighlightPattern([
          'ושמרו <font color="red">שבתות</font> הרבה',
        ])!;

        expect(pattern.hasMatch('בזכות שבתות שנשמרו'), isTrue);
        expect(pattern.hasMatch('טקסט אחר לגמרי'), isFalse);
      });

      test('מונחים מכמה תוצאות מאוחדים לתבנית אחת', () {
        final pattern = PdfBookSearchView.buildAdvancedHighlightPattern([
          'א <font>שבת</font> ב',
          'ג <mark>שבתות</mark> ד',
        ])!;

        expect(pattern.hasMatch('שבת קודש'), isTrue);
        expect(pattern.hasMatch('שתי שבתות'), isTrue);
      });

      test('התבנית סובלנית לניקוד בשכבת הטקסט של ה-PDF', () {
        final pattern = PdfBookSearchView.buildAdvancedHighlightPattern([
          '<font>פרעה</font>',
        ])!;

        expect(pattern.hasMatch('וַיֹּאמֶר פַּרְעֹה'), isTrue);
      });

      test('מכבדת גבולות מילה — לא מדגישה חלק ממילה אחרת', () {
        final pattern = PdfBookSearchView.buildAdvancedHighlightPattern([
          '<font>אמר</font>',
        ])!;

        expect(pattern.hasMatch('נאמרו דברים'), isFalse);
        expect(pattern.hasMatch('אמר רבא'), isTrue);
      });

      test('מונח שחוזר בכמה תוצאות נכלל פעם אחת', () {
        final single = PdfBookSearchView.buildAdvancedHighlightPattern([
          '<font>ברא</font>',
        ])!;
        final duplicated = PdfBookSearchView.buildAdvancedHighlightPattern([
          '<font>ברא</font>',
          'שוב <font>ברא</font> עולם',
        ])!;

        expect(duplicated.pattern, single.pattern);
      });

      test('נאכפת תקרת מונחים — מונחים מעבר לתקרה לא נכללים', () {
        final htmls = List.generate(
          60,
          (i) => 'לפני <font>${_term(i)}</font> אחרי',
        );
        final pattern = PdfBookSearchView.buildAdvancedHighlightPattern(htmls)!;

        expect(pattern.hasMatch(_term(0)), isTrue);
        expect(pattern.hasMatch(_term(49)), isTrue);
        expect(pattern.hasMatch(_term(59)), isFalse);
      });
    }, skip: engineReady ? false : searchEngineSkipReason);
  });

  group('buildSimpleSearchPattern - סדר השאילתה מול מסלול הנסיגה ההפוך', () {
    test('שאילתה ריקה מחזירה null בשני הסדרים', () {
      expect(PdfBookSearchView.buildSimpleSearchPattern('   '), isNull);
      expect(
        PdfBookSearchView.buildSimpleSearchPattern('   ', reversed: true),
        isNull,
      );
    });

    group('עם המנוע', () {
      test('סדר השאילתה זהה לתבנית הליטרלית הרגילה', () {
        expect(
          PdfBookSearchView.buildSimpleSearchPattern('תנו רבנן')!.source,
          buildLiteralPattern('תנו רבנן')!.source,
        );
      });

      test('תבנית סדר השאילתה אינה מתאימה לסדר ההפוך', () {
        final pattern = PdfBookSearchView.buildSimpleSearchPattern(
          'תנו רבנן',
        )!.regExp;

        expect(pattern.hasMatch('תנו רבנן שלושה'), isTrue);
        // הרעש שהוסר: איחוד גורף היה מחזיר כאן התאמה.
        expect(pattern.hasMatch('שלושה רבנן תנו'), isFalse);
      });

      test('תבנית הנסיגה מתאימה לסדר ההפוך בלבד', () {
        final pattern = PdfBookSearchView.buildSimpleSearchPattern(
          'תנו רבנן',
          reversed: true,
        )!.regExp;

        expect(pattern.hasMatch('שלושה רבנן תנו'), isTrue);
        expect(pattern.hasMatch('תנו רבנן שלושה'), isFalse);
        expect(pattern.hasMatch('רבנן לו תנו'), isFalse);
      });

      test('שלוש מילים — רק הסדר המלא ההפוך, לא תמורות אחרות', () {
        final pattern = PdfBookSearchView.buildSimpleSearchPattern(
          'אמר רבא אביי',
          reversed: true,
        )!.regExp;

        expect(pattern.hasMatch('אביי רבא אמר'), isTrue);
        expect(pattern.hasMatch('רבא אמר אביי'), isFalse);
        expect(pattern.hasMatch('אמר אביי רבא'), isFalse);
      });

      test('מילה אחת — אין מה להפוך', () {
        expect(
          PdfBookSearchView.buildSimpleSearchPattern('רבנן')!.source,
          buildLiteralPattern('רבנן')!.source,
        );
        expect(
          PdfBookSearchView.buildSimpleSearchPattern('רבנן', reversed: true),
          isNull,
        );
      });

      test('שאילתה סימטרית — אין נסיגה', () {
        expect(
          PdfBookSearchView.buildSimpleSearchPattern(
            'אמר רבא אמר',
            reversed: true,
          ),
          isNull,
        );
      });

      test('מילה כפולה בשאילתה — ההיפוך נשאר נכון', () {
        final pattern = PdfBookSearchView.buildSimpleSearchPattern(
          'אמר אמר רבא',
          reversed: true,
        )!.regExp;

        expect(pattern.hasMatch('רבא אמר אמר'), isTrue);
        expect(pattern.hasMatch('אמר אמר רבא'), isFalse);
      });

      test('בסדר ההפוך רווח בקצה אינו משנה — הקצוות שלו פנימיים', () {
        expect(
          PdfBookSearchView.buildSimpleSearchPattern(
            ' תנו רבנן ',
            wholeWord: false,
            reversed: true,
          )!.source,
          PdfBookSearchView.buildSimpleSearchPattern(
            'תנו רבנן',
            wholeWord: false,
            reversed: true,
          )!.source,
        );
      });

      test('נשמרת הסובלנות לניקוד גם בסדר ההפוך', () {
        final pattern = PdfBookSearchView.buildSimpleSearchPattern(
          'תנו רבנן',
          reversed: true,
        )!.regExp;

        expect(pattern.hasMatch('רַבָּנַן תָּנוּ'), isTrue);
      });

      test('רווחים מובילים/כפולים אינם שוברים את פיצול המילים', () {
        final pattern = PdfBookSearchView.buildSimpleSearchPattern(
          '  תנו   רבנן  ',
          reversed: true,
        )!.regExp;

        expect(pattern.hasMatch('שלושה רבנן תנו'), isTrue);
      });

      test('תו regex מיוחד במילה — מוברח גם בסדר ההפוך', () {
        final pattern = PdfBookSearchView.buildSimpleSearchPattern(
          'אמר (רבא',
          reversed: true,
        )!.regExp;

        expect(pattern.hasMatch('(רבא אמר'), isTrue);
      });

      test('גרשיים במילה שנעשית ראשונה בסדר ההפוך', () {
        final pattern = PdfBookSearchView.buildSimpleSearchPattern(
          'תנו רבנן"',
          reversed: true,
        )!.regExp;

        expect(pattern.hasMatch('שלושה רבנן" תנו'), isTrue);
      });

      test('דגלי הרגקס זהים לתבנית הליטרלית הרגילה', () {
        final pattern = PdfBookSearchView.buildSimpleSearchPattern(
          'תנו רבנן',
          reversed: true,
        )!.regExp;
        final forward = buildLiteralPattern('תנו רבנן')!.regExp;

        expect(pattern.isCaseSensitive, forward.isCaseSensitive);
        expect(pattern.isUnicode, forward.isUnicode);
      });
    }, skip: engineReady ? false : searchEngineSkipReason);
  });

  group('מסלול הנסיגה בזרימת החיפוש הפשוט', () {
    testWidgets('אפס תוצאות בספר עם עברית — מורץ חיפוש שני בסדר ההפוך', (
      tester,
    ) async {
      final searcher = await _pumpSearchView(
        tester,
        pageFullText: 'בראשית ברא אלהים את השמים ואת הארץ',
      );

      await _search(tester, 'תנו רבנן');
      expect(searcher.searchedPatterns.length, 1);
      expect(
        searcher.searchedPatterns.first.hasMatch('תנו רבנן שלושה'),
        isTrue,
      );

      await _finishScan(tester, searcher);

      expect(searcher.searchedPatterns.length, 2);
      final fallback = searcher.searchedPatterns.last;
      expect(fallback.hasMatch('שלושה רבנן תנו'), isTrue);
      expect(fallback.hasMatch('תנו רבנן שלושה'), isFalse);

      // הנסיגה עצמה אינה מפעילה נסיגה נוספת.
      await _finishScan(tester, searcher);
      expect(searcher.searchedPatterns.length, 2);
    });

    testWidgets('ספר בלי אות עברית — הודעת סריקה בלבד, בלי חיפוש שני', (
      tester,
    ) async {
      final searcher = await _pumpSearchView(
        tester,
        pageFullText: _scannedOnlyPageText,
      );

      await _search(tester, 'תנו רבנן');
      await _finishScan(tester, searcher);

      expect(find.text(PdfMessages.noTextLayer), findsOneWidget);
      expect(searcher.searchedPatterns.length, 1);
    });

    testWidgets('סריקה שמצאה התאמות — אין חיפוש שני', (tester) async {
      final searcher = await _pumpSearchView(
        tester,
        pageFullText: 'בראשית ברא אלהים את השמים ואת הארץ',
      );

      await _search(tester, 'תנו רבנן');
      searcher.setSingleMatch();
      await _finishScan(tester, searcher);

      expect(searcher.searchedPatterns.length, 1);
    });

    testWidgets('מילה אחת בלי תוצאות — אין מה להפוך, אין חיפוש שני', (
      tester,
    ) async {
      final searcher = await _pumpSearchView(
        tester,
        pageFullText: 'בראשית ברא אלהים את השמים ואת הארץ',
      );

      await _search(tester, 'רבנן');
      await _finishScan(tester, searcher);

      expect(searcher.searchedPatterns.length, 1);
    });

    testWidgets('רווח בקצה בחלק ממילה — הסריקה מעוגנת לגבול המילה (#2679)', (
      tester,
    ) async {
      await InBookSearchPreferences.saveWholeWord(false);
      final searcher = await _pumpSearchView(
        tester,
        pageFullText: 'לכם כמה הכמות עליכם',
      );

      for (final query in ['כם ', ' כמ', 'כם']) {
        await _search(tester, query);
        final pattern = searcher.searchedPatterns.last;
        expect(
          pattern.pattern,
          buildLiteralPattern(query, wholeWord: false)!.source,
          reason: '"$query"',
        );
      }
      expect(
        searcher.searchedPatterns.last.pattern,
        isNot(buildLiteralPattern('כם ', wholeWord: false)!.source),
      );
    });
  }, skip: engineReady ? false : searchEngineSkipReason);
}
