import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/semantic_search/services/semantic_slow_search_log.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';

SemanticSearchResponse _response({SemanticTimings? timings}) =>
    SemanticSearchResponse(
      results: const [],
      totalCount: 0,
      lexicalTotalCount: 0,
      countsAreExact: false,
      requestedMode: SemanticRetrievalMode.hybrid,
      executedMode: SemanticExecutedMode.hybrid,
      semanticAvailable: true,
      latencyMs: BigInt.from(61000),
      candidateWindowTruncated: false,
      truncated: false,
      timings: timings,
    );

const _timings = SemanticTimings(
  expansions: 2,
  lexicalMs: 1200.4,
  semanticMs: 58000,
  embedMs: 150,
  scanMs: 55000.6,
  resolveMs: 2000,
  fuseMs: 10,
  hydrateMs: 300,
  pageMs: 400,
  totalMs: 60950,
);

void main() {
  test('רק חיפוש שהגיע לסף נרשם, ולכל היותר פעם בפרק זמן', () {
    var now = DateTime(2026, 11, 19, 12);
    final written = <Duration>[];
    var wordCounts = 0;
    final log = SemanticSlowSearchLog(
      clock: () => now,
      write: (total, _) => written.add(total),
    );
    void record(int seconds) => log.record(
      total: Duration(seconds: seconds),
      prepare: Duration.zero,
      response: _response(),
      countQueryWords: () => ++wordCounts,
      facets: 0,
      offset: 0,
    );

    record(9);
    record(10);
    record(60);
    now = now.add(const Duration(minutes: 9));
    record(60);
    now = now.add(const Duration(minutes: 1));
    record(30);

    expect(wordCounts, 2);
    expect(written, [
      const Duration(seconds: 10),
      const Duration(seconds: 30),
    ]);
  });

  test('הרשומה כוללת את זמני השלבים של המנוע ואת ההקשר', () {
    Map<String, String?>? details;
    SemanticSlowSearchLog(write: (_, d) => details = d).record(
      total: const Duration(seconds: 62),
      prepare: const Duration(milliseconds: 900),
      response: _response(timings: _timings),
      countQueryWords: () => 5,
      facets: 0,
      offset: 0,
    );

    expect(details!['Prepare ms'], '900');
    expect(details!['Engine ms'], '61000');
    expect(
      details!['Stages'],
      'expansions=2 lexical=1200 semantic=58000 embed=150 scan=55001 '
      'resolve=2000 fuse=10 hydrate=300 page=400 total=60950',
    );
    expect(details!['Mode'], 'hybrid -> hybrid');
    expect(details!['Scope'], 'all books');
    expect(details!['Query words'], '5');
  });

  test('עמוד מה-session מציג אילו שלבים לא נמדדו', () {
    const cachedPage = SemanticTimings(
      expansions: 0,
      lexicalMs: 0,
      semanticMs: 0,
      fuseMs: 0,
      hydrateMs: 0,
      pageMs: 13,
      totalMs: 15,
    );

    expect(
      SemanticSlowSearchLog.formatStages(cachedPage),
      'expansions=0 lexical=0 semantic=0 embed=n/a scan=n/a '
      'resolve=n/a fuse=0 hydrate=0 page=13 total=15',
    );
  });

  test('מנוע שלא דיווח זמנים נרשם כך במפורש', () {
    expect(SemanticSlowSearchLog.formatStages(null), 'not reported');
  });
}
