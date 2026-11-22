import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/pdf_book/view/pdf_search_screen.dart';
import 'package:otzaria/pdf_book/utils/pdf_search_result_list.dart';
import 'package:pdfrx/pdfrx.dart';

PdfTextSearchResult _match(int page) => PdfTextSearchResult.fromRange(
  PdfPageTextRange(
    pageText: PdfPageText(
      pageNumber: page,
      fullText: 'שלום עולם',
      charRects: List.filled(9, const PdfRect(0, 1, 1, 0)),
      fragments: const [],
    ),
    start: 0,
    end: 4,
  ),
);

PdfTextSearchResult _rangeIn(String fullText, String word) {
  final start = fullText.indexOf(word);
  return PdfTextSearchResult.fromRange(
    PdfPageTextRange(
      pageText: PdfPageText(
        pageNumber: 1,
        fullText: fullText,
        charRects: List.filled(fullText.length, const PdfRect(0, 1, 1, 0)),
        fragments: const [],
      ),
      start: start,
      end: start + word.length,
    ),
    contextLength: 160,
  );
}

class _InvalidMatch extends Fake implements PdfTextSearchResult {
  @override
  String get contextText => 'קצר';
  @override
  int get contextStart => 0;
  @override
  int get start => 2;
  @override
  int get end => 99;
}

void main() {
  group('matchLineSnippet — שורת ההקשר של תוצאה', () {
    const page = 'שורה ראשונה\nבראשית ברא אלהים\nשורה אחרונה';

    test('מחזיר את השורה שבה ההתאמה', () {
      expect(
        PdfBookSearchView.matchLineSnippet(_rangeIn(page, 'ברא '), 'ברא'),
        'בראשית ברא אלהים',
      );
    });

    test('התאמה בתחילת הטקסט ובסופו', () {
      expect(
        PdfBookSearchView.matchLineSnippet(_rangeIn(page, 'שורה'), 'x'),
        'שורה ראשונה',
      );
      expect(
        PdfBookSearchView.matchLineSnippet(_rangeIn(page, 'אחרונה'), 'x'),
        'שורה אחרונה',
      );
    });

    test('טווח לא תקין — חוזר לשאילתה', () {
      final broken = _InvalidMatch();
      expect(PdfBookSearchView.matchLineSnippet(broken, 'שאילתה'), 'שאילתה');
    });

    test('שכבת טקסט ללא שורות אינה משכפלת עמוד שלם לכל התאמה', () {
      final page =
          '${List.filled(10000, 'א').join()}שלום${List.filled(10000, 'ב').join()}';
      final match = _rangeIn(page, 'שלום');
      final snippet = PdfBookSearchView.matchLineSnippet(match, 'שלום');
      expect(match.contextText.length, 324);
      expect(match.pageTextLength, page.length);
      expect(
        snippet,
        '…${List.filled(80, 'א').join()}שלום${List.filled(156, 'ב').join()}…',
      );
      expect(snippet.length, 242);
    });
  });

  group('תוצאות לפי דרישה ומנות עמוד', () {
    test(
      'תמונות מצב של pdfrx שומרות זהות לאורך סריקה אמיתית עם wrap',
      () async {
        var created = 0;
        final results = PdfSearchResultList<_Result>((match, id) {
          created++;
          return _Result(match, id);
        });
        final session = _ScanningSession(_ScanningController());
        addTearDown(session.dispose);
        final completed = Completer<void>();
        final seenPages = <List<int>>[];
        session.addListener(() {
          results.update(session.matches, generation: 1);
          if (results.isNotEmpty) {
            seenPages.add([
              for (final result in results) result.match.pageNumber,
            ]);
          }
          if (!session.isSearching &&
              results.length == 4 &&
              !completed.isCompleted) {
            completed.complete();
          }
        });
        session.startTextSearch(
          'שלום',
          startPageNumber: 3,
          searchImmediately: true,
          goToFirstMatch: false,
        );
        await completed.future.timeout(const Duration(seconds: 5));
        expect(seenPages, [
          [3],
          [3, 4],
          [1, 3, 4],
          [1, 2, 3, 4],
        ]);
        expect(created, 4);
        expect(results.groupedItems.whereType<int>().toList(), [1, 2, 3, 4]);
      },
    );

    test('קיבוץ וכותרות אינם יוצרים תוצאות או קטעי הקשר', () {
      var created = 0;
      final results = PdfSearchResultList<_Result>((match, id) {
        created++;
        return _Result(match, id);
      });
      results.update([_match(2), _match(2), _match(5)], generation: 1);
      expect(results.length, 3);
      expect(results.groupedItems.length, 5);
      expect(results.groupedItems[0], 2);
      expect(results.groupedItems[3], 5);
      expect(results.visualIndexForPage(1), 0);
      expect(results.visualIndexForPage(3), 3);
      expect(results.visualIndexForPage(100), 3);
      expect(created, 0);
      final first = results[0];
      expect(results.groupedItems[1], same(first));
      expect(created, 1);
    });

    test('עדכון בלי wrap נוגע רק בתוספות ובקבוצה האחרונה', () {
      final initial = List.generate(1000, (i) => _match(i + 1));
      final results = PdfSearchResultList<_Result>(_Result.new);
      results.update(initial, generation: 1);
      final last = results.last;

      final unchanged = _CountedMatches(initial);
      results.update(unchanged, generation: 1);
      expect(unchanged.reads, lessThan(10));

      final appended = _CountedMatches([
        ...initial,
        _match(1000),
        _match(1001),
      ]);
      results.update(appended, generation: 1);
      expect(appended.reads, lessThan(30));
      expect(results[999], same(last));
      expect(results.groupedItems[1998], 1000);
      expect(results.groupedItems[2000], same(results[1000]));
      expect(results.groupedItems[2001], 1001);
      expect(results.visualIndexForPage(1001), 2001);
    });

    test('wrap והוספה באמצע שומרים אובייקטים ומעדכנים ניווט וקיבוץ', () {
      var created = 0;
      final results = PdfSearchResultList<_Result>((match, id) {
        created++;
        return _Result(match, id);
      });
      final page5 = _match(5);
      final page8 = _match(8);
      results.update([page5, page8], generation: 1);
      final fifth = results[0];
      final eighth = results[1];
      final page1 = _match(1);
      results.update([page1, page5, page8], generation: 1);
      final first = results[0];
      expect(results[1], same(fifth));
      expect(results[2], same(eighth));
      final current = [page1, _match(3), page5, page8];
      results.update(current, generation: 1);
      expect(results[0], same(first));
      expect(results[2], same(fifth));
      expect(results[3], same(eighth));
      expect(created, 3);
      expect(results.matchIndexOf(fifth, current), 2);
      expect(results.groupedItems.whereType<int>().toList(), [1, 3, 5, 8]);
      expect(results.groupedItems[5], same(fifth));
      expect(created, 4);
    });

    test('ניווט פותר את המיקום גם לפני הודעת העדכון הבאה', () {
      final results = PdfSearchResultList<_Result>(_Result.new);
      final target = _rangeIn('שלום ראשון שלום שני', 'שני');
      results.update([target], generation: 1);
      final result = results[0];
      final current = [_rangeIn('שלום ראשון שלום שני', 'ראשון'), target];
      expect(results.matchIndexOf(result, current), 1);
      expect(results.matchIndexOf(result, [_match(1)]), isNull);
    });

    test('שינוי דור מבטל תוצאה ישנה גם אם ההתאמה באותו מקום', () {
      final results = PdfSearchResultList<_Result>(_Result.new);
      final matches = [_match(2)];
      results.update(matches, generation: 1);
      final previous = results[0];
      results.update(matches, generation: 2);
      expect(results[0], isNot(same(previous)));
      expect(results.matchIndexOf(previous, matches), isNull);
      results.reset();
      expect(results, isEmpty);
      expect(results.groupedItems, isEmpty);
      expect(results.visualIndexForPage(2), 0);
    });

    test('החלפה בתוך עמוד ואיפוס לרשימה קצרה אינם משאירים תוצאות ישנות', () {
      var created = 0;
      final results = PdfSearchResultList<_Result>((match, id) {
        created++;
        return _Result(match, id);
      });
      final first = _match(1);
      final middle = _match(1);
      final last = _match(1);
      results.update([first, middle, last, _match(7)], generation: 1);
      final initial = results.toList();
      results.update([first, _match(1), last], generation: 1);
      expect(results[0], same(initial[0]));
      expect(results[1], isNot(same(initial[1])));
      expect(results[2], same(initial[2]));
      expect(created, 5);
      expect(results.groupedItems.length, 4);
      expect(results.matchIndexOf(initial[1], [first, last]), isNull);
      results.update(const [], generation: 1);
      expect(results.groupedItems, isEmpty);
    });

    test('1000 עמודים בחיפוש מעגלי יוצרים כל תוצאה פעם אחת', () {
      const pages = 1000;
      const matchesPerPage = 10;
      var created = 0;
      final results = PdfSearchResultList<_Result>((match, id) {
        created++;
        return _Result(match, id);
      });
      final pageMatches = List.generate(
        pages,
        (page) => List.generate(matchesPerPage, (_) => _match(page + 1)),
      );
      final scanned = <int>{};
      for (var batch = 0; batch < pages ~/ 10; batch++) {
        for (var i = 0; i < 10; i++) {
          scanned.add((pages ~/ 2 + batch * 10 + i) % pages);
        }
        final sorted = scanned.toList()..sort();
        final snapshot = [for (final page in sorted) ...pageMatches[page]];
        results.update(snapshot, generation: 1);
        // גם צרכן שקורא את כל התוצאות אינו בונה מחדש התאמות קיימות.
        expect(results.toList().length, snapshot.length);
        expect(results.groupedItems.length, snapshot.length + scanned.length);
      }
      expect(created, pages * matchesPerPage);
    });

    test('תוצאות וקבוצות נשארות לקריאה בלבד', () {
      final results = PdfSearchResultList<_Result>(_Result.new);
      results.update([_match(1)], generation: 1);
      expect(() => results.length = 0, throwsUnsupportedError);
      expect(() => results[0] = results[0], throwsUnsupportedError);
      expect(() => results.groupedItems.length = 0, throwsUnsupportedError);
      expect(() => results.groupedItems[0] = 7, throwsUnsupportedError);
      expect(() => results[-1], throwsRangeError);
      expect(() => results.groupedItems[2], throwsRangeError);
    });
  });
}

class _CountedMatches extends Fake implements List<PdfTextSearchResult> {
  _CountedMatches(this.matches);

  final List<PdfTextSearchResult> matches;
  int reads = 0;

  @override
  int get length => matches.length;

  @override
  PdfTextSearchResult operator [](int index) {
    reads++;
    return matches[index];
  }
}

class _Result {
  _Result(this.match, this.id);

  final PdfTextSearchResult match;
  final int id;
}

class _ScanningPage extends Fake implements PdfPage {
  _ScanningPage(this.pageNumber);

  @override
  final int pageNumber;
  @override
  bool get isLoaded => true;
}

class _ScanningDocument extends Fake implements PdfDocument {
  @override
  final List<PdfPage> pages = List.generate(4, (i) => _ScanningPage(i + 1));
  @override
  Stream<PdfDocumentEvent> get events => const Stream.empty();
}

class _ScanningController extends PdfViewerController {
  @override
  final PdfDocument document = _ScanningDocument();
  @override
  bool get isReady => true;
  @override
  void invalidate() {}
  @override
  FutureOr<T?> useDocument<T>(
    FutureOr<T> Function(PdfDocument document) task, {
    bool ensureLoaded = true,
    Completer<dynamic>? cancelLoading,
  }) => task(document);
}

class _ScanningSession extends PdfTextSearchSession {
  _ScanningSession(super.controller)
    : super(notificationInterval: Duration.zero);

  @override
  Future<PdfPageText?> loadText({required int pageNumber}) async => PdfPageText(
    pageNumber: pageNumber,
    fullText: 'שלום עולם',
    charRects: List.filled(9, const PdfRect(0, 1, 1, 0)),
    fragments: const [],
  );
}
