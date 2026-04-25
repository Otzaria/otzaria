import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/find_ref/repository/reference_books_cache.dart';
import 'package:otzaria/generated_links/repository/generated_links_book_resolver.dart';

/// בונה resolver עם ספרייה מדומה.
///
/// [books] — רשימת ספרים בה יחפש; [toc] — טבלת TOC מדומה לפי bookId.
GeneratedLinksBookResolver _makeResolver({
  required List<ReferenceBookHit> books,
  Map<int, List<Map<String, dynamic>>> toc = const {},
}) {
  return GeneratedLinksBookResolver(
    warmUpReferenceBooks: () async {},
    isReferenceBooksLoaded: () => true,
    searchBooks: (query, {int limit = 50}) {
      return books.where((b) => b.title == query).toList();
    },
    getTocEntries: (bookId, title, {List<String>? queryTokens}) async {
      return toc[bookId] ?? const [];
    },
  );
}

ReferenceBookHit _book({
  required int id,
  required String title,
  int matchRank = 0,
}) =>
    ReferenceBookHit(
      bookId: id,
      title: title,
      filePath: '/books/$title.txt',
      fileType: 'txt',
      matchRank: matchRank,
      orderIndex: 0,
    );

void main() {
  group('GeneratedLinksBookResolver — ספר קיים', () {
    test('מחזיר target מלא כאשר הספר וה-ref נמצאים', () async {
      final resolver = _makeResolver(
        books: [_book(id: 10, title: 'ברכות')],
        toc: {
          10: [
            {'reference': 'ברכות ב א', 'segment': 42, 'level': 1}
          ]
        },
      );

      final target = await resolver.resolve(
        bookTitle: 'ברכות',
        refText: 'ב א',
      );

      expect(target, isNotNull);
      expect(target!.targetBookId, equals(10));
      expect(target.bookTitle, equals('ברכות'));
      expect(target.targetIndex, equals(42));
      expect(target.isResolved, isTrue);
    });
  });

  group('GeneratedLinksBookResolver — ספר לא קיים', () {
    test('מחזיר null כאשר הספר לא נמצא בספרייה', () async {
      final resolver = _makeResolver(books: []);

      final target = await resolver.resolve(
        bookTitle: 'ספר_לא_קיים',
        refText: 'א א',
      );

      expect(target, isNull);
    });
  });

  group('GeneratedLinksBookResolver — כפילות exact', () {
    test('שני ספרים עם matchRank==0 → null (אמביגואי)', () async {
      final resolver = GeneratedLinksBookResolver(
        warmUpReferenceBooks: () async {},
        isReferenceBooksLoaded: () => true,
        searchBooks: (q, {int limit = 50}) => [
          _book(id: 1, title: 'ברכות', matchRank: 0),
          _book(id: 2, title: 'ברכות', matchRank: 0), // כפילות
        ],
        getTocEntries: (bookId, title, {List<String>? queryTokens}) async => [],
      );

      final target =
          await resolver.resolve(bookTitle: 'ברכות', refText: 'ב א');
      expect(target, isNull);
    });
  });

  group('GeneratedLinksBookResolver — ref לא נמצא', () {
    test('מחזיר null כאשר ה-ref לא קיים ב-TOC', () async {
      final resolver = _makeResolver(
        books: [_book(id: 5, title: 'שבת')],
        toc: {5: const []}, // TOC ריק
      );

      final target = await resolver.resolve(
        bookTitle: 'שבת',
        refText: 'כ א',
      );

      expect(target, isNull);
    });
  });

  group('GeneratedLinksBookResolver — cache בזיכרון', () {
    test('קריאה שנייה לאותו מפתח לא קוראת ל-getTocEntries שוב', () async {
      var tocCallCount = 0;

      final resolver = GeneratedLinksBookResolver(
        warmUpReferenceBooks: () async {},
        isReferenceBooksLoaded: () => true,
        searchBooks: (q, {int limit = 50}) =>
            [_book(id: 7, title: 'פסחים')],
        getTocEntries: (bookId, title, {List<String>? queryTokens}) async {
          tocCallCount++;
          return [
            {'reference': 'פסחים ב א', 'segment': 10, 'level': 1}
          ];
        },
      );

      final first = await resolver.resolve(bookTitle: 'פסחים', refText: 'ב א');
      final second = await resolver.resolve(bookTitle: 'פסחים', refText: 'ב א');

      expect(first?.targetIndex, equals(10));
      expect(second?.targetIndex, equals(10));
      expect(tocCallCount, equals(1)); // רק קריאה אחת ל-DB
    });

    test('כשל — 3 ניסיונות בפועל לפני נעילה, ואז ניסיון רביעי לא קורא ל-search',
        () async {
      var searchCallCount = 0;

      final resolver = GeneratedLinksBookResolver(
        warmUpReferenceBooks: () async {},
        isReferenceBooksLoaded: () => true,
        searchBooks: (q, {int limit = 50}) {
          searchCallCount++;
          return []; // תמיד נכשל (אין התאמה מדויקת)
        },
        getTocEntries: (bookId, title, {List<String>? queryTokens}) async =>
            [],
      );

      // _maxFailedAttempts == 3; כל אחד מ-3 הראשונים חייב לקרוא ל-search
      for (var i = 0; i < 3; i++) {
        final result =
            await resolver.resolve(bookTitle: 'לא_קיים', refText: 'א א');
        expect(result, isNull);
      }
      expect(searchCallCount, equals(3)); // 3 ניסיונות אמיתיים

      // ניסיון רביעי — חסום ע"י _maxFailedAttempts, לא קורא ל-search
      await resolver.resolve(bookTitle: 'לא_קיים', refText: 'א א');
      expect(searchCallCount, equals(3)); // עדיין 3 — לא ניסיון נוסף
    });

    test('P1: כשל זמני לא ננעל — אחרי כשל ראשון הקריאה השנייה ניסיון אמיתי',
        () async {
      var tocCallCount = 0;

      final resolver = GeneratedLinksBookResolver(
        warmUpReferenceBooks: () async {},
        isReferenceBooksLoaded: () => true,
        searchBooks: (q, {int limit = 50}) =>
            [_book(id: 3, title: 'גיטין')],
        getTocEntries: (bookId, title, {List<String>? queryTokens}) async {
          tocCallCount++;
          // הקריאה הראשונה נכשלת, השנייה מצליחה
          if (tocCallCount == 1) return const [];
          return [
            {'reference': 'גיטין ב א', 'segment': 5, 'level': 1}
          ];
        },
      );

      final first =
          await resolver.resolve(bookTitle: 'גיטין', refText: 'ב א');
      expect(first, isNull); // כשל ראשון

      final second =
          await resolver.resolve(bookTitle: 'גיטין', refText: 'ב א');
      expect(second, isNotNull); // הצלחה בניסיון שני
      expect(second!.targetIndex, equals(5));
    });
  });
}
