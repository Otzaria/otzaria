import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/app_report/services/recent_book_opens.dart';
import 'package:otzaria/models/book_source.dart';
import 'package:otzaria/models/books.dart';

typedef _Entry = ({String title, Object error, Map<String, String?> details});

class _SnapshotBook extends Fake implements TextBook {
  @override
  String title = 'בראשית';
  @override
  int? id = 7;
  @override
  int? categoryId = 4;
  @override
  String? versionTitle = 'edition';
  @override
  BookSource source = BookSource.official;
  @override
  bool get isUserBook => source.isUser;
}

void main() {
  late List<_Entry> written;

  void capture({
    required String title,
    required Object error,
    StackTrace? stackTrace,
    Map<String, String?> details = const {},
  }) => written.add((title: title, error: error, details: details));

  setUp(() => written = []);

  for (final source in [
    BookSource.official,
    BookSource.user,
    BookSource.attached('local'),
  ]) {
    test('פרטי הפתיחה והתקיעה הם צילום בזמן start: ${source.wireKey}', () {
      fakeAsync((async) {
        final now = DateTime(2026);
        final opens = RecentBookOpens(
          now: () => now.add(async.elapsed),
          writeLog: capture,
        );
        final book = _SnapshotBook()..source = source;
        final attempt = opens.start(book, BookOpenKind.text);
        book
          ..title = 'כותרת אחרת'
          ..id = 99
          ..categoryId = 88
          ..versionTitle = null
          ..source = BookSource.official;

        async.elapse(const Duration(seconds: 20));
        attempt.finish(BookOpenOutcome.closed);

        expect(opens.collect()['attempts'], [
          {
            'at': now.toUtc().toIso8601String(),
            'title': source.isUser ? null : 'בראשית',
            'kind': 'text',
            'outcome': 'stalled',
            'durationMs': 20000,
            'source': source.wireKey,
            'id': 7,
            'stalled': true,
          },
        ]);
        expect(written.single.title, 'Book Load Stalled');
        expect(
          written.single.error,
          'Book "בראשית" (text) still loading after 20s',
        );
        expect(written.single.details, {
          'book': 'בראשית',
          'id': '7',
          'source': source.wireKey,
          'categoryId': '4',
          'versionTitle': 'edition',
          'elapsedMs': '20000',
        });
        expect(async.pendingTimers, isEmpty);
      });
    });
  }

  test('שומר רק את הניסיונות האחרונים, מהחדש לישן', () {
    final opens = RecentBookOpens(
      capacity: 3,
      stallThreshold: null,
      writeLog: capture,
    );
    for (var i = 1; i <= 5; i++) {
      opens.start(TextBook(title: 'ספר $i'), BookOpenKind.text);
    }

    final attempts = opens.collect()['attempts'] as List;
    expect(attempts.map((a) => (a as Map)['title']), [
      'ספר 5',
      'ספר 4',
      'ספר 3',
    ]);
    expect(attempts.every((a) => (a as Map)['outcome'] == 'pending'), isTrue);
  });

  test('תוצאה ומשך: נקבעים פעם אחת, בלי לכתוב ללוג', () {
    var now = DateTime(2026, 11, 17, 10);
    final opens = RecentBookOpens(
      stallThreshold: null,
      now: () => now,
      writeLog: capture,
    );
    final attempt = opens.start(
      PdfBook(title: 'מסכת', path: '/x.pdf', source: BookSource.user),
      BookOpenKind.pdf,
    );
    now = now.add(const Duration(milliseconds: 250));
    attempt.finish(BookOpenOutcome.failed);
    now = now.add(const Duration(seconds: 5));
    attempt.finish(BookOpenOutcome.loaded);

    expect(attempt.describe(), {
      'at': DateTime(2026, 11, 17, 10).toUtc().toIso8601String(),
      'title': null,
      'kind': 'pdf',
      'outcome': 'failed',
      'durationMs': 250,
      'source': 'u',
    });
    expect(written, isEmpty);
  });

  test('טעינה שנתקעה נרשמת פעם אחת ונשארת stalled גם כשהלשונית נסגרת', () {
    fakeAsync((async) {
      final opens = RecentBookOpens(
        stallThreshold: const Duration(seconds: 20),
        now: () => DateTime(2026).add(async.elapsed),
        writeLog: capture,
      );
      final attempt = opens.start(
        TextBook(title: 'בראשית', id: 3),
        BookOpenKind.text,
      );

      async.elapse(const Duration(seconds: 19));
      expect(written, isEmpty);
      expect(attempt.outcome, BookOpenOutcome.pending);

      async.elapse(const Duration(seconds: 2));
      expect(written.single.title, 'Book Load Stalled');
      expect(written.single.details, containsPair('book', 'בראשית'));
      expect(written.single.details, containsPair('elapsedMs', '20000'));
      expect(attempt.outcome, BookOpenOutcome.stalled);

      attempt.finish(BookOpenOutcome.closed);
      async.elapse(const Duration(minutes: 1));
      expect(written, hasLength(1));
      expect(attempt.outcome, BookOpenOutcome.stalled);
      expect(async.pendingTimers, isEmpty);
    });
  });

  test('טעינה שהסתיימה בזמן מבטלת את הטיימר', () {
    fakeAsync((async) {
      final opens = RecentBookOpens(writeLog: capture);
      opens
          .start(TextBook(title: 'שמות'), BookOpenKind.text)
          .finish(BookOpenOutcome.loaded);
      expect(async.pendingTimers, isEmpty);
      async.elapse(const Duration(minutes: 1));
      expect(written, isEmpty);
    });
  });

  test('כשל: הכותרת לפי הסוג, בלי נתיב הקובץ', () {
    final opens = RecentBookOpens(writeLog: capture);
    opens.logLoadError(
      PdfBook(title: 'מסכת', path: r'C:\Users\Moshe\x.pdf', id: 9),
      BookOpenKind.pdf,
      StateError('broken'),
      details: {'page': '4'},
    );

    final entry = written.single;
    expect(entry.title, 'Book Load Error (pdf)');
    expect(entry.details, {
      'book': 'מסכת',
      'id': '9',
      'source': 'o',
      'categoryId': null,
      'errorType': 'StateError',
      'page': '4',
    });
  });
}
