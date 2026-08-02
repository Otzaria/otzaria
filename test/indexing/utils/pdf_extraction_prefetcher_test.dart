import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/indexing/utils/pdf_extraction_prefetcher.dart';
import 'package:otzaria/models/books.dart';

/// חילוץ מזויף בשליטת הטסט: כל ספר מקבל [Completer] משלו, כך שהטסט מכתיב
/// מתי כל חילוץ מסתיים ובאיזה סדר.
class _ControlledExtractor {
  final started = <String>[];
  final _completers = <String, Completer<PdfExtraction>>{};

  Future<PdfExtraction> call(PdfBook book) {
    started.add(book.title);
    final completer = Completer<PdfExtraction>();
    _completers[book.title] = completer;
    return completer.future;
  }

  /// מסיים את החילוץ של [title] עם [chars] תווי טקסט בעמוד יחיד.
  Future<void> finish(String title, {int chars = 0}) async {
    _completers[title]!.complete(_extractionOf(title, chars));
    // סבב אירועים אחד — נותן ל-then הפנימי של התור לרשום את התוצאה.
    await Future<void>.delayed(Duration.zero);
  }

  Future<void> fail(String title, Object error) async {
    _completers[title]!.completeError(error, StackTrace.current);
    await Future<void>.delayed(Duration.zero);
  }
}

PdfExtraction _extractionOf(String title, int chars) => (
  pages: [
    (reference: '$title, עמוד 1', text: 'א' * chars, pageIndex: 0),
  ],
  outline: const [],
  error: null,
  stackTrace: null,
  extractMs: 0,
);

PdfBook _pdf(String title) => PdfBook(title: title, path: 'C:\\$title.pdf');

bool _always(PdfBook book) => true;

void main() {
  group('PdfExtractionPrefetcher.fill', () {
    test('מזניק את כל ספרי ה-PDF עד תקרת המקביליות', () {
      final extractor = _ControlledExtractor();
      final prefetcher = PdfExtractionPrefetcher(
        extract: extractor.call,
        maxInFlight: 3,
        fileSizeOf: (_) => 0,
      );
      final books = [for (var i = 0; i < 5; i++) _pdf('p$i')];

      prefetcher.fill(books, 0, shouldPrefetch: _always);

      expect(extractor.started, ['p0', 'p1', 'p2']);
      expect(prefetcher.length, 3);
    });

    test('מדלג על ספרי טקסט ועל ספרים ש-shouldPrefetch דוחה', () {
      final extractor = _ControlledExtractor();
      final prefetcher = PdfExtractionPrefetcher(
        extract: extractor.call,
        fileSizeOf: (_) => 0,
      );
      final skipped = _pdf('מאונדקס');
      final books = <Book>[
        TextBook(title: 'טקסט'),
        skipped,
        _pdf('חדש'),
      ];

      prefetcher.fill(
        books,
        0,
        shouldPrefetch: (book) => !identical(book, skipped),
      );

      expect(extractor.started, ['חדש']);
    });

    test('הסריקה מתקדמת בלבד — ספר שנסרק לא מוזנק שוב בקריאה חוזרת', () {
      final extractor = _ControlledExtractor();
      final prefetcher = PdfExtractionPrefetcher(
        extract: extractor.call,
        fileSizeOf: (_) => 0,
      );
      final books = [_pdf('p0'), _pdf('p1')];

      prefetcher.fill(books, 0, shouldPrefetch: _always);
      prefetcher.fill(books, 0, shouldPrefetch: _always);

      expect(extractor.started, ['p0', 'p1']);
    });

    test('fromIndex מקדם את הסריקה קדימה ואינו מחזיר אותה אחורה', () {
      final extractor = _ControlledExtractor();
      final prefetcher = PdfExtractionPrefetcher(
        extract: extractor.call,
        maxInFlight: 1,
        fileSizeOf: (_) => 0,
      );
      final books = [_pdf('p0'), _pdf('p1'), _pdf('p2')];

      prefetcher.fill(books, 2, shouldPrefetch: _always);
      expect(extractor.started, ['p2']);

      // בקשה לחזור לתחילת הרשימה אינה מזניקה את p0/p1 שכבר נסרקו מעליהם.
      prefetcher.take(books[2]);
      prefetcher.fill(books, 0, shouldPrefetch: _always);
      expect(extractor.started, ['p2']);
    });
  });

  group('PdfExtractionPrefetcher — שליפה', () {
    test('takeReady מחזיר null כל עוד אף חילוץ לא הסתיים', () {
      final extractor = _ControlledExtractor();
      final prefetcher = PdfExtractionPrefetcher(
        extract: extractor.call,
        fileSizeOf: (_) => 0,
      );
      final books = [_pdf('p0'), _pdf('p1')];
      prefetcher.fill(books, 0, shouldPrefetch: _always);

      expect(prefetcher.takeReady(), isNull);
      expect(prefetcher.readyCount, 0);
    });

    test('takeReady מחזיר את המוכנים בסדר התור ומרוקן אותו', () async {
      final extractor = _ControlledExtractor();
      final prefetcher = PdfExtractionPrefetcher(
        extract: extractor.call,
        fileSizeOf: (_) => 0,
      );
      final books = [_pdf('p0'), _pdf('p1'), _pdf('p2')];
      prefetcher.fill(books, 0, shouldPrefetch: _always);

      // p2 מסתיים ראשון — סדר השליפה נקבע לפי סדר התור, לא סדר הסיום.
      await extractor.finish('p2');
      await extractor.finish('p0');

      expect(prefetcher.readyCount, 2);
      expect(prefetcher.takeReady()!.book.title, 'p0');
      expect(prefetcher.takeReady()!.book.title, 'p2');
      expect(prefetcher.takeReady(), isNull);
      expect(prefetcher.length, 1);
    });

    test('takeReady מדלג על הספר המוחרג ומחזיר את הבא אחריו', () async {
      final extractor = _ControlledExtractor();
      final prefetcher = PdfExtractionPrefetcher(
        extract: extractor.call,
        fileSizeOf: (_) => 0,
      );
      final books = [_pdf('p0'), _pdf('p1')];
      prefetcher.fill(books, 0, shouldPrefetch: _always);
      await extractor.finish('p0');
      await extractor.finish('p1');

      expect(prefetcher.takeReady(exclude: books[0])!.book.title, 'p1');
      // המוחרג נשאר בתור לצריכה במסלול הרגיל.
      expect(prefetcher.take(books[0]), isNotNull);
    });

    test('take מחזיר את החילוץ גם כשעדיין רץ, ומפנה את הסלוט', () async {
      final extractor = _ControlledExtractor();
      final prefetcher = PdfExtractionPrefetcher(
        extract: extractor.call,
        maxInFlight: 2,
        fileSizeOf: (_) => 0,
      );
      final books = [_pdf('p0'), _pdf('p1'), _pdf('p2')];
      prefetcher.fill(books, 0, shouldPrefetch: _always);

      final pending = prefetcher.take(books[0]);
      expect(pending, isNotNull);
      expect(prefetcher.length, 1);

      // הסלוט שהתפנה מתמלא בחילוץ הבא.
      prefetcher.fill(books, 0, shouldPrefetch: _always);
      expect(extractor.started, ['p0', 'p1', 'p2']);

      await extractor.finish('p0', chars: 4);
      expect((await pending!).pages.single.text.length, 4);
    });

    test('take על ספר שאינו בתור מחזיר null', () {
      final extractor = _ControlledExtractor();
      final prefetcher = PdfExtractionPrefetcher(
        extract: extractor.call,
        fileSizeOf: (_) => 0,
      );

      expect(prefetcher.take(_pdf('לא-בתור')), isNull);
      expect(extractor.started, isEmpty);
    });
  });

  group('PdfExtractionPrefetcher — תקרות זיכרון', () {
    test('תוצאות שהצטברו מעל תקרת התווים עוצרות הזנקות חדשות', () async {
      final extractor = _ControlledExtractor();
      final prefetcher = PdfExtractionPrefetcher(
        extract: extractor.call,
        maxInFlight: 10,
        maxPendingChars: 100,
        fileSizeOf: (_) => 0,
      );
      final books = [for (var i = 0; i < 10; i++) _pdf('p$i')];

      prefetcher.fill(books, 0, shouldPrefetch: _always);
      expect(extractor.started.length, 10);

      // כל העשרה מסתיימים ותופסים 600 תווים — הרבה מעל התקרה.
      for (var i = 0; i < 10; i++) {
        await extractor.finish('p$i', chars: 60);
      }
      expect(prefetcher.pendingChars, 600);

      // שליפה בודדת מפנה 60 תווים בלבד — עדיין מעל התקרה, אין הזנקה.
      prefetcher.takeReady();
      prefetcher.fill(books, 0, shouldPrefetch: _always);
      expect(extractor.started.length, 10);

      // אחרי ריקון התור, ההזנקות מתחדשות.
      while (prefetcher.takeReady() != null) {}
      expect(prefetcher.pendingChars, 0);
      final more = [...books, _pdf('נוסף')];
      prefetcher.fill(more, 0, shouldPrefetch: _always);
      expect(extractor.started.last, 'נוסף');
    });

    test('גודל קבצי ה-PDF שבטיסה חוסם הזנקה מעבר לתקציב הנייטיבי', () {
      final extractor = _ControlledExtractor();
      final prefetcher = PdfExtractionPrefetcher(
        extract: extractor.call,
        maxInFlight: 10,
        maxInFlightBytes: 100,
        fileSizeOf: (_) => 60,
      );
      final books = [for (var i = 0; i < 5; i++) _pdf('p$i')];

      // הראשון תופס 60 בייטים, השני מגיע ל-120 — ורק אז נחסם.
      prefetcher.fill(books, 0, shouldPrefetch: _always);

      expect(extractor.started, ['p0', 'p1']);
      expect(prefetcher.inFlightBytes, 120);
    });

    test('סיום חילוץ משחרר את תקציב הבייטים גם לפני שנצרך', () async {
      final extractor = _ControlledExtractor();
      final prefetcher = PdfExtractionPrefetcher(
        extract: extractor.call,
        maxInFlight: 10,
        maxInFlightBytes: 100,
        fileSizeOf: (_) => 60,
      );
      final books = [for (var i = 0; i < 5; i++) _pdf('p$i')];
      prefetcher.fill(books, 0, shouldPrefetch: _always);

      await extractor.finish('p0');

      expect(prefetcher.inFlightBytes, 60);
      prefetcher.fill(books, 0, shouldPrefetch: _always);
      expect(extractor.started, ['p0', 'p1', 'p2']);
    });

    test('ספר יחיד החורג מכל התקרות מוזנק בכל זאת — התור לא נתקע', () {
      final extractor = _ControlledExtractor();
      final prefetcher = PdfExtractionPrefetcher(
        extract: extractor.call,
        maxPendingChars: 1,
        maxInFlightBytes: 1,
        fileSizeOf: (_) => 999999,
      );
      final books = [_pdf('ענק'), _pdf('הבא')];

      prefetcher.fill(books, 0, shouldPrefetch: _always);

      // הענק לבדו מוזנק; השני ממתין עד שהסלוט מתפנה.
      expect(extractor.started, ['ענק']);
    });
  });

  group('PdfExtractionPrefetcher — כשלים וניקוי', () {
    test('חילוץ שנכשל משחרר את הסלוט, והשגיאה מגיעה לצרכן', () async {
      final extractor = _ControlledExtractor();
      final prefetcher = PdfExtractionPrefetcher(
        extract: extractor.call,
        maxInFlight: 1,
        fileSizeOf: (_) => 50,
      );
      final books = [_pdf('שבור'), _pdf('תקין')];
      prefetcher.fill(books, 0, shouldPrefetch: _always);

      await extractor.fail('שבור', StateError('פתיחה נכשלה'));

      // הסלוט השתחרר — גם התקציב הנייטיבי וגם המקום בתור.
      expect(prefetcher.inFlightBytes, 0);
      final ready = prefetcher.takeReady();
      expect(ready!.book.title, 'שבור');
      await expectLater(ready.extraction, throwsStateError);

      prefetcher.fill(books, 0, shouldPrefetch: _always);
      expect(extractor.started, ['שבור', 'תקין']);
    });

    test('dispose משליך את הנותרים — כשל אחריו אינו שגיאה ללא-מטפל', () async {
      final extractor = _ControlledExtractor();
      final prefetcher = PdfExtractionPrefetcher(
        extract: extractor.call,
        fileSizeOf: (_) => 10,
      );
      final books = [for (var i = 0; i < 3; i++) _pdf('p$i')];
      prefetcher.fill(books, 0, shouldPrefetch: _always);

      prefetcher.dispose();

      expect(prefetcher.length, 0);
      expect(prefetcher.inFlightBytes, 0);
      // סיום אחרי ה-dispose אינו מחזיר את הסלוטים לתור ואינו מזייף מונים.
      await extractor.fail('p0', StateError('כשל אחרי עצירה'));
      await extractor.finish('p1');
      expect(prefetcher.takeReady(), isNull);
    });
  });
}
