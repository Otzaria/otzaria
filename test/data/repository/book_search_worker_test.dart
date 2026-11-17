import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/repository/book_search_worker.dart';
import 'package:otzaria/data/repository/data_repository.dart';

List<BookSearchEntry> _entries({
  String firstTitle = 'שולחן ערוך אורח חיים',
}) => [
  BookSearchEntry(index: 0, title: firstTitle, author: '', topics: ''),
  const BookSearchEntry(
    index: 1,
    title: 'משנה ברורה',
    author: 'החפץ חיים',
    topics: '',
    acronyms: ['מב'],
  ),
  const BookSearchEntry(
    index: 2,
    title: 'ביאור הלכה',
    author: '',
    topics: '',
    categoryPath: 'הלכה/שולחן ערוך',
  ),
  const BookSearchEntry(index: 3, title: 'שולחן ערוך', author: '', topics: ''),
];

BookSearchQuery _query(String text) => BookSearchQuery(
  queryWords: text.split(' '),
  topics: const [],
  sortByRatio: true,
  normalizedQuery: text,
);

List<int> _direct(List<BookSearchEntry> entries, String text) =>
    PreparedBookSearchIndex(entries).search(_query(text));

class _CountedEntry extends BookSearchEntry {
  _CountedEntry() : super(index: 0, title: 'שולחן', author: '', topics: '');

  int comparisons = 0;

  @override
  bool sameAs(BookSearchEntry other) {
    comparisons++;
    return super.sameAs(other);
  }
}

void main() {
  late BookSearchWorker worker;
  setUp(() => worker = BookSearchWorker());
  tearDown(() => worker.dispose());

  test('returns the same ordering as the in-process search', () async {
    for (final text in ['שולחן', 'שולחן ערוך', 'חיים', 'מב', 'הלכה']) {
      expect(
        await worker.search(_entries(), _query(text)),
        _direct(_entries(), text),
        reason: text,
      );
    }
    expect(worker.usesWorker, isTrue);
  });

  test('FIFO handles a burst of queued searches without reordering', () async {
    final entries = _entries();
    final queries = [
      'שולחן',
      'חיים',
      'הלכה',
      'מב',
      'ערוך',
      'ברורה',
      'ביאור',
      'שולחן ערוך',
      'החפץ',
      'טור',
    ];
    final completionOrder = <String>[];
    final pending = [
      for (final text in queries)
        worker.search(entries, _query(text)).then((result) {
          completionOrder.add(text);
          return result;
        }),
    ];
    final results = await Future.wait(pending);
    expect(completionOrder, queries);
    for (var i = 0; i < queries.length; i++) {
      expect(results[i], _direct(entries, queries[i]), reason: queries[i]);
    }
  });

  test('uploads the index only when the entries change', () async {
    await worker.search(_entries(), _query('שולחן'));
    await worker.search(_entries(), _query('שולחן ערוך'));
    expect(worker.indexUploads, 1);

    final changed = _entries(firstTitle: 'טור אורח חיים');
    expect(
      await worker.search(changed, _query('טור')),
      _direct(changed, 'טור'),
    );
    expect(worker.indexUploads, 2);
  });

  test(
    'only compares an equivalent replacement catalog on its first use',
    () async {
      final first = _CountedEntry();
      final replacement = <BookSearchEntry>[_CountedEntry()];
      await worker.search([first], _query('שולחן'));
      for (var i = 0; i < 4; i++) {
        expect(await worker.search(replacement, _query('שולחן')), [0]);
      }
      expect(first.comparisons, 1);
      expect(worker.indexUploads, 1);
    },
  );

  test('a newer search with the same key supersedes the older one', () async {
    final key = Object();
    final older = worker.search(_entries(), _query('שולחן'), supersedeKey: key);
    final unrelated = worker.search(_entries(), _query('חיים'));
    final newer = worker.search(_entries(), _query('הלכה'), supersedeKey: key);

    await expectLater(older, throwsA(isA<BookSearchSupersededException>()));
    expect(await unrelated, _direct(_entries(), 'חיים'));
    expect(await newer, _direct(_entries(), 'הלכה'));
  });

  test(
    'dispose during a search falls back and the next search restarts',
    () async {
      final pending = worker.search(_entries(), _query('שולחן'));
      worker.dispose();
      expect(await pending, _direct(_entries(), 'שולחן'));

      expect(
        await worker.search(_entries(), _query('הלכה')),
        _direct(_entries(), 'הלכה'),
      );
      expect(worker.usesWorker, isTrue);
    },
  );

  test(
    'dispose after a warm search does not strand active or queued jobs',
    () async {
      await worker.search(_entries(), _query('שולחן'));
      final pending = worker.search(_entries(), _query('הלכה'));
      final queued = worker.search(_entries(), _query('חיים'));
      worker.dispose();

      expect(
        await pending.timeout(const Duration(seconds: 2)),
        _direct(_entries(), 'הלכה'),
      );
      expect(
        await queued.timeout(const Duration(seconds: 2)),
        _direct(_entries(), 'חיים'),
      );
      expect(
        await worker
            .search(_entries(), _query('מב'))
            .timeout(const Duration(seconds: 2)),
        _direct(_entries(), 'מב'),
      );
    },
  );
}
