import 'dart:async';
import 'dart:convert';

// The probe deliberately uses the engine already pinned by pdfrx.
// ignore: depend_on_referenced_packages
import 'package:pdfrx_engine/pdfrx_engine.dart';
// Use the same event replay as the pinned native PDFium implementation.
// ignore: depend_on_referenced_packages
import 'package:rxdart/rxdart.dart';
import 'package:test/test.dart';

import '../../../tool/perf_probe/src/pdf_text_profile.dart';
import '../../../tool/perf_probe/src/pdf_text_profile_report.dart';

const _queries = [
  PdfTextProfileQuery.literal('hebrew', 'שלום'),
  PdfTextProfileQuery.literal('case-folded', 'ALPHA'),
  PdfTextProfileQuery.regex('numbers', r'\d+'),
  PdfTextProfileQuery.regex('zero-length', r'(?=alpha)'),
];

void main() {
  late _Document document;
  late (bool, bool) normalization;
  setUp(() {
    normalization = (Pdfrx.normalizeHebrewText, Pdfrx.decodeLegacyHebrewText);
    document = _Document(17);
  });
  tearDown(() async {
    Pdfrx.normalizeHebrewText = normalization.$1;
    Pdfrx.decodeLegacyHebrewText = normalization.$2;
    await document.dispose();
  });

  test(
    'measures real LRU misses across two full sweeps and excludes warmup',
    () async {
      final emitted = <Map<String, Object?>>[];
      final report = await runPdfTextProfile(
        document: document,
        queries: _queries,
        warmup: 1,
        repetitions: 2,
        onObservation: emitted.add,
      );
      validatePdfTextProfileReport(report);
      final rows = report['observations'] as List<Map<String, Object?>>;
      expect(rows, hasLength(17 * 3 * 3));
      expect(emitted, hasLength(rows.length));
      // Measured raw, independent reference, then both cache sweeps; formatting reuses raw.
      expect(document.pages.map((page) => page.loads), everyElement(12));
      for (final phase in pdfTextProfilePhases) {
        final part = rows.where((row) => row['phase'] == phase).toList();
        expect(part.map((row) => row['rawLoadCalls']), everyElement(1));
        expect(part.map((row) => row['parity']), everyElement(isTrue));
        final summary = (report['summary'] as Map)[phase] as Map;
        expect(summary['rawLoadCalls'], 34);
        expect((summary['matchingUs'] as Map)['count'], 2);
      }
      expect(rows.last['cachedPagesAfter'], 16);
      expect(rows.first['queries'], [
        {'id': 'hebrew', 'matches': 1, 'rects': 1},
        {'id': 'case-folded', 'matches': 1, 'rects': 1},
        {'id': 'numbers', 'matches': 1, 'rects': 1},
        {'id': 'zero-length', 'matches': 0, 'rects': 0},
      ]);
      expect(document.disposals, 0);
      expect(document.eventsController.hasListener, isFalse);
      expect(jsonEncode(report), isNot(contains('unreported-secret')));
    },
  );

  test('preserves explicit page order and query flags', () async {
    Pdfrx.normalizeHebrewText = true;
    Pdfrx.decodeLegacyHebrewText = true;
    final numbers = List.generate(17, (i) => 17 - i);
    final report = await runPdfTextProfile(
      document: document,
      pageNumbers: numbers,
      warmup: 0,
      repetitions: 1,
      queries: const [
        PdfTextProfileQuery.regex('multiline', r'^alpha', multiLine: true),
      ],
    );
    final configuration = report['configuration'] as Map;
    expect(configuration['pageNumbers'], numbers);
    expect(configuration['normalizeHebrewText'], isTrue);
    expect(configuration['decodeLegacyHebrewText'], isTrue);
    expect((configuration['queries'] as List).single, {
      'id': 'multiline',
      'kind': 'regex',
      'source': r'^alpha',
      'caseSensitive': true,
      'multiLine': true,
      'unicode': true,
      'dotAll': false,
    });
    expect((report['observations'] as List).first['pageNumber'], 17);
  });

  test(
    'rejects a changed page before emitting a successful observation',
    () async {
      final first = document.pages.first;
      first.loader = () async =>
          _raw(first.loads == 1 ? 'alpha שלום 42' : 'changed');
      final rows = <Map<String, Object?>>[];
      await expectLater(
        runPdfTextProfile(
          document: document,
          queries: _queries,
          warmup: 0,
          repetitions: 1,
          onObservation: rows.add,
        ),
        throwsStateError,
      );
      expect(rows, isEmpty);
      expect(document.eventsController.hasListener, isFalse);
    },
  );

  test(
    'cancellation before loading does not touch or dispose the document',
    () async {
      await expectLater(
        runPdfTextProfile(
          document: document,
          queries: _queries,
          isCancelled: () => true,
        ),
        throwsA(isA<PdfTextProfileCancelled>()),
      );
      expect(document.pages.map((page) => page.loads), everyElement(0));
      expect(document.disposals, 0);
    },
  );

  test(
    'cancellation waits for pending raw load and publishes no stale result',
    () async {
      final entered = Completer<void>();
      final gate = Completer<PdfPageRawText?>();
      document.pages.first.loader = () {
        entered.complete();
        return gate.future;
      };
      var cancelled = false;
      final rows = <Map<String, Object?>>[];
      final running = runPdfTextProfile(
        document: document,
        queries: _queries,
        isCancelled: () => cancelled,
        onObservation: rows.add,
      );
      final checked = expectLater(
        running,
        throwsA(isA<PdfTextProfileCancelled>()),
      );
      await entered.future;
      cancelled = true;
      gate.complete(_raw('alpha שלום 42'));
      await checked;
      expect(rows, isEmpty);
      expect(document.pages.first.loads, 1);
      expect(document.pages.skip(1).map((page) => page.loads), everyElement(0));
      expect(document.eventsController.hasListener, isFalse);
    },
  );

  test(
    'cancelling after one observation cannot produce a complete report',
    () async {
      var cancelled = false;
      var observations = 0;
      await expectLater(
        runPdfTextProfile(
          document: document,
          queries: _queries,
          isCancelled: () => cancelled,
          onObservation: (_) {
            observations++;
            cancelled = true;
          },
        ),
        throwsA(isA<PdfTextProfileCancelled>()),
      );
      expect(observations, 1);
      expect(document.pages.first.loads, 2);
      expect(document.pages.skip(1).map((page) => page.loads), everyElement(0));
    },
  );

  test(
    'raw failure remains an error and releases the event subscription',
    () async {
      final error = StateError('native extraction failed');
      document.pages.first.loader = () async => throw error;
      await expectLater(
        runPdfTextProfile(document: document, queries: _queries),
        throwsA(same(error)),
      );
      expect(document.eventsController.hasListener, isFalse);
      expect(document.disposals, 0);
    },
  );

  test(
    'null raw from a loaded page is not reported as an empty success',
    () async {
      document.pages.first.loader = () async => null;
      await expectLater(
        runPdfTextProfile(document: document, queries: _queries),
        throwsStateError,
      );
      expect(document.pages.first.loads, 1);
    },
  );

  test(
    'page replacement during raw load invalidates the measurement',
    () async {
      final first = document.pages.first;
      first.loader = () async {
        document.pages[0] = _Page(document, 1);
        return _raw('alpha שלום 42');
      };
      await expectLater(
        runPdfTextProfile(document: document, queries: _queries),
        throwsStateError,
      );
      expect(document.pages[0].loads, 0);
    },
  );

  test('changed normalization cannot be mixed into a report', () async {
    document.pages.first.loader = () async {
      Pdfrx.normalizeHebrewText = !normalization.$1;
      return _raw('alpha שלום 42');
    };
    await expectLater(
      runPdfTextProfile(document: document, queries: _queries),
      throwsStateError,
    );
  });

  test(
    'a changed-page event invalidates even a reused page identity',
    () async {
      final first = document.pages.first;
      first.loader = () async {
        document.eventsController.add(
          PdfDocumentPageStatusChangedEvent(
            document,
            changes: {1: PdfPageStatusChange.modified(page: first)},
          ),
        );
        await Future<void>.delayed(Duration.zero);
        return _raw('alpha שלום 42');
      };
      await expectLater(
        runPdfTextProfile(document: document, queries: _queries),
        throwsStateError,
      );
      expect(document.pages.first, same(first));
      expect(document.eventsController.hasListener, isFalse);
    },
  );

  test('document stream error is not silently turned into a timing', () async {
    document.pages.first.loader = () async {
      document.eventsController.addError(
        StateError('document closed unexpectedly'),
      );
      await Future<void>.delayed(Duration.zero);
      return _raw('alpha שלום 42');
    };
    await expectLater(
      runPdfTextProfile(document: document, queries: _queries),
      throwsStateError,
    );
    expect(document.eventsController.hasListener, isFalse);
  });

  test(
    'a page event replayed before measurement is not a new change',
    () async {
      final first = document.pages.first;
      document.eventsController.add(
        PdfDocumentPageStatusChangedEvent(
          document,
          changes: {1: PdfPageStatusChange.modified(page: first)},
        ),
      );
      document.eventsController.add(PdfDocumentLoadCompleteEvent(document));
      final report = await runPdfTextProfile(
        document: document,
        queries: _queries,
        warmup: 0,
        repetitions: 1,
      );
      validatePdfTextProfileReport(report);
    },
  );

  test('the final observation cannot hide a queued page change', () async {
    final first = document.pages.first;
    await expectLater(
      runPdfTextProfile(
        document: document,
        queries: _queries,
        warmup: 0,
        repetitions: 1,
        onObservation: (row) {
          if (row['phase'] == 'cacheRepeat' && row['pageNumber'] == 17) {
            document.eventsController.add(
              PdfDocumentPageStatusChangedEvent(
                document,
                changes: {1: PdfPageStatusChange.modified(page: first)},
              ),
            );
          }
        },
      ),
      throwsStateError,
    );
    expect(document.eventsController.hasListener, isFalse);
  });

  test('query input is captured before asynchronous extraction', () async {
    final queries = <PdfTextProfileQuery>[..._queries];
    document.pages.first.loader = () async {
      queries.clear();
      return _raw('alpha שלום 42');
    };
    final report = await runPdfTextProfile(
      document: document,
      queries: queries,
      warmup: 0,
      repetitions: 1,
    );
    expect((report['configuration'] as Map)['queries'], hasLength(4));
  });

  test(
    'invalid workload and malformed regex fail before native work',
    () async {
      for (final numbers in [
        List.generate(16, (i) => i + 1),
        List.filled(17, 1),
        List.generate(17, (i) => i + 2),
      ]) {
        await expectLater(
          runPdfTextProfile(
            document: document,
            queries: _queries,
            pageNumbers: numbers,
          ),
          throwsArgumentError,
        );
      }
      await expectLater(
        runPdfTextProfile(document: document, queries: const []),
        throwsArgumentError,
      );
      await expectLater(
        runPdfTextProfile(
          document: document,
          queries: const [PdfTextProfileQuery.regex('bad', '(')],
        ),
        throwsFormatException,
      );
      expect(document.pages.map((page) => page.loads), everyElement(0));
    },
  );
}

PdfPageRawText _raw(String text) => PdfPageRawText(text, [
  for (var i = 0; i < text.length; i++) PdfRect(i * 10.0, 40, i * 10.0 + 8, 20),
]);

class _Document implements PdfDocument {
  _Document(int count) {
    _pages = List.generate(count, (i) => _Page(this, i + 1));
  }
  late final List<_Page> _pages;
  @override
  List<_Page> get pages => _pages;
  @override
  set pages(List<PdfPage> value) =>
      throw UnsupportedError('Unexpected page setter');
  final eventsController = ReplaySubject<PdfDocumentEvent>(maxSize: 2);
  var disposals = 0;
  @override
  Stream<PdfDocumentEvent> get events => eventsController.stream;
  @override
  Future<void> dispose() async {
    disposals++;
    if (!eventsController.isClosed) await eventsController.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unexpected document call: ${invocation.memberName}',
  );
}

class _Page implements PdfPage {
  _Page(this.document, this.pageNumber);
  @override
  final _Document document;
  @override
  final int pageNumber;
  @override
  bool get isLoaded => true;
  var loads = 0;
  Future<PdfPageRawText?> Function()? loader;
  @override
  Future<PdfPageRawText?> loadText() async {
    loads++;
    return loader != null
        ? await loader!()
        : _raw('alpha שלום 42 unreported-secret');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unexpected page call: ${invocation.memberName}');
}
