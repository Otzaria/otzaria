import 'dart:convert';

import 'package:crypto/crypto.dart';
// The CLI measures the engine pinned transitively by pdfrx without Flutter UI.
// ignore: depend_on_referenced_packages
import 'package:pdfrx_engine/pdfrx_engine.dart';

import 'pdf_text_profile_report.dart';

class PdfTextProfileQuery {
  const PdfTextProfileQuery.literal(
    this.id,
    this.source, {
    this.caseSensitive = false,
  }) : isRegex = false,
       multiLine = false,
       unicode = true,
       dotAll = false;

  const PdfTextProfileQuery.regex(
    this.id,
    this.source, {
    this.caseSensitive = true,
    this.multiLine = false,
    this.unicode = true,
    this.dotAll = false,
  }) : isRegex = true;

  final String id;
  final String source;
  final bool isRegex;
  final bool caseSensitive;
  final bool multiLine;
  final bool unicode;
  final bool dotAll;

  Pattern get pattern => isRegex
      ? RegExp(
          source,
          caseSensitive: caseSensitive,
          multiLine: multiLine,
          unicode: unicode,
          dotAll: dotAll,
        )
      : source;

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': isRegex ? 'regex' : 'literal',
    'source': source,
    'caseSensitive': caseSensitive,
    'multiLine': multiLine,
    'unicode': unicode,
    'dotAll': dotAll,
  };
}

class PdfTextProfileCancelled implements Exception {
  const PdfTextProfileCancelled();
}

/// מודד API ציבורי בלבד; טעינת raw כוללת native, נרמול, תזמון והעברה יחד.
Future<Map<String, Object?>> runPdfTextProfile({
  required PdfDocument document,
  required List<PdfTextProfileQuery> queries,
  List<int>? pageNumbers,
  int warmup = 1,
  int repetitions = 5,
  void Function(Map<String, Object?>)? onObservation,
  bool Function()? isCancelled,
}) async {
  final numbers = List<int>.unmodifiable(
    pageNumbers ?? List.generate(document.pages.length, (i) => i + 1),
  );
  queries = List<PdfTextProfileQuery>.unmodifiable(queries);
  final pageCount = document.pages.length;
  final cache = PdfPageTextCache();
  if (warmup < 0 ||
      repetitions < 1 ||
      numbers.length <= cache.maximumPages ||
      numbers.toSet().length != numbers.length ||
      numbers.any((n) => n < 1 || n > pageCount) ||
      queries.isEmpty ||
      queries.any((q) => q.id.isEmpty) ||
      queries.map((q) => q.id).toSet().length != queries.length) {
    throw ArgumentError('נדרשים עמודים ייחודיים מעבר ל-LRU ושאילתות תקינות');
  }
  final compiled = [
    for (final query in queries) (query: query, pattern: query.pattern),
  ];
  final normalization = (
    Pdfrx.normalizeHebrewText,
    Pdfrx.decodeLegacyHebrewText,
  );
  var closed = false;
  var pageChanged = false;
  Object? documentError;
  void check() {
    if (isCancelled?.call() == true) throw const PdfTextProfileCancelled();
    if (closed ||
        pageChanged ||
        documentError != null ||
        document.pages.length != pageCount ||
        normalization !=
            (Pdfrx.normalizeHebrewText, Pdfrx.decodeLegacyHebrewText)) {
      throw StateError('המסמך או הגדרות הנרמול השתנו במהלך המדידה');
    }
  }

  final pages = <PdfPage>[];
  for (final number in numbers) {
    check();
    pages.add(await document.pages[number - 1].ensureLoaded());
    check();
  }
  final selectedPages = numbers.toSet();
  var measuring = false;
  final documentEvents = document.events.listen(
    (event) {
      if (measuring &&
          event is PdfDocumentPageStatusChangedEvent &&
          (event.changes.keys.any(selectedPages.contains) ||
              event.changes.values.whereType<PdfPageStatusMoved>().any(
                (change) => selectedPages.contains(change.oldPageNumber),
              ))) {
        pageChanged = true;
      }
    },
    onDone: () => closed = true,
    onError: (Object error) => documentError = error,
  );
  void checkPage(PdfPage page) {
    check();
    if (!identical(page, document.pages[page.pageNumber - 1])) {
      throw StateError('עמוד הוחלף במהלך מדידת הטקסט');
    }
  }

  final observations = <Map<String, Object?>>[];
  final signatures = <int, String>{};
  void record(Map<String, Object?> row) {
    check();
    final signature = _signature(row);
    final previous = signatures[row['pageNumber']];
    if (previous != null && signature != previous) {
      throw StateError('תוכן או תוצאות השתנו בין מעברי הטקסט');
    }
    signatures[row['pageNumber'] as int] = signature;
    observations.add(row);
    onObservation?.call(Map.unmodifiable(row));
  }

  try {
    // PDFium may replay page notifications from before this measurement.
    await Future<void>.delayed(Duration.zero);
    measuring = true;
    check();
    for (var iteration = 0; iteration < warmup + repetitions; iteration++) {
      cache.clear();
      for (final page in pages) {
        checkPage(page);
        final measured = _TextPage(page);
        final raw = await measured.loadText();
        checkPage(page);
        final captured = _TextPage(page, captured: raw);
        final format = Stopwatch()..start();
        final text = await captured.loadStructuredText();
        format.stop();
        checkPage(page);
        final matches = await _matches(text, compiled, check);
        final row = _observation(
          text,
          matches,
          iteration: iteration,
          warmup: iteration < warmup,
          phase: 'pipeline',
          rawLoadUs: measured.rawLoadUs,
          rawLoadCalls: measured.rawLoadCalls,
          formatUs: format.elapsedMicroseconds,
          formatRawCalls: captured.capturedCalls,
          cache: cache,
        );

        // שאילתת הבקרה אינה חלק מהתזמונים; היא משתמשת במסלול המקורי.
        final reference = await page.loadStructuredText();
        checkPage(page);
        final referenceMatches = await _matches(reference, compiled, check);
        if (text != reference ||
            _signature(row) !=
                _signature(
                  _observation(
                    reference,
                    referenceMatches,
                    iteration: iteration,
                    warmup: iteration < warmup,
                    phase: 'pipeline',
                    rawLoadUs: 0,
                    rawLoadCalls: 1,
                    formatUs: 0,
                    formatRawCalls: 1,
                    cache: cache,
                  ),
                )) {
          throw StateError('פירוק השלבים אינו שווה למסלול הטקסט המקורי');
        }
        record(row);
      }

      for (final phase in ['cacheFirst', 'cacheRepeat']) {
        for (final page in pages) {
          checkPage(page);
          final measured = _TextPage(page);
          final clock = Stopwatch()..start();
          final text = await cache.load(measured);
          clock.stop();
          checkPage(page);
          final matches = await _matches(text, compiled, check);
          record(
            _observation(
              text,
              matches,
              iteration: iteration,
              warmup: iteration < warmup,
              phase: phase,
              rawLoadUs: measured.rawLoadUs,
              rawLoadCalls: measured.rawLoadCalls,
              cacheLoadUs: clock.elapsedMicroseconds,
              cache: cache,
            ),
          );
        }
      }
    }
    // Deliver changes queued by the final observation before returning success.
    await Future<void>.delayed(Duration.zero);
    check();
    return buildPdfTextProfileReport(
      configuration: {
        'pageNumbers': numbers,
        'documentPageCount': pageCount,
        'warmup': warmup,
        'repetitions': repetitions,
        'normalizeHebrewText': normalization.$1,
        'decodeLegacyHebrewText': normalization.$2,
        'cache': {
          'maximumPages': cache.maximumPages,
          'maximumBytes': cache.maximumBytes,
        },
        'queries': [for (final query in queries) query.toJson()],
      },
      observations: observations,
    );
  } finally {
    cache.clear();
    await documentEvents.cancel();
  }
}

typedef _Query = ({PdfTextProfileQuery query, Pattern pattern});
typedef _Matches = ({
  int matchingUs,
  int rectsUs,
  List<List<PdfTextSearchResult>> results,
  List<Map<String, Object?>> counts,
});

Future<_Matches> _matches(
  PdfPageText text,
  List<_Query> queries,
  void Function() check,
) async {
  var matchingUs = 0;
  var rectsUs = 0;
  final results = <List<PdfTextSearchResult>>[];
  final counts = <Map<String, Object?>>[];
  for (final query in queries) {
    check();
    final clock = Stopwatch()..start();
    final ranges = await text
        .allMatches(query.pattern, caseInsensitive: !query.query.caseSensitive)
        .toList();
    clock.stop();
    matchingUs += clock.elapsedMicroseconds;
    check();
    clock
      ..reset()
      ..start();
    final matches = [
      for (final range in ranges) PdfTextSearchResult.fromRange(range),
    ];
    clock.stop();
    rectsUs += clock.elapsedMicroseconds;
    check();
    results.add(matches);
    counts.add({
      'id': query.query.id,
      'matches': matches.length,
      'rects': matches.fold<int>(0, (sum, match) => sum + match.rects.length),
    });
  }
  return (
    matchingUs: matchingUs,
    rectsUs: rectsUs,
    results: results,
    counts: counts,
  );
}

Map<String, Object?> _observation(
  PdfPageText text,
  _Matches matches, {
  required int iteration,
  required bool warmup,
  required String phase,
  required int rawLoadUs,
  required int rawLoadCalls,
  required PdfPageTextCache cache,
  int? formatUs,
  int formatRawCalls = 0,
  int? cacheLoadUs,
}) => {
  'iteration': iteration,
  'warmup': warmup,
  'pageNumber': text.pageNumber,
  'phase': phase,
  'rawLoadUs': rawLoadUs,
  'formatUs': formatUs,
  'cacheLoadUs': cacheLoadUs,
  'matchingUs': matches.matchingUs,
  'rectsUs': matches.rectsUs,
  'rawLoadCalls': rawLoadCalls,
  'formatRawCalls': formatRawCalls,
  'cachedPagesAfter': cache.length,
  'cachedBytesAfter': cache.estimatedBytes,
  'parity': true,
  'textCharacters': text.fullText.length,
  'characterRects': text.charRects.length,
  'fragments': text.fragments.length,
  'queries': matches.counts,
  'textSha256': sha256.convert(utf8.encode(text.fullText)).toString(),
  'geometrySha256': _hash([
    [for (final rect in text.charRects) _rect(rect)],
    [
      for (final fragment in text.fragments)
        [
          fragment.index,
          fragment.length,
          fragment.direction.name,
          _rect(fragment.bounds),
          [for (final rect in fragment.charRects) _rect(rect)],
        ],
    ],
  ]),
  'matchesSha256': _hash([
    for (final query in matches.results)
      [
        for (final match in query)
          [
            match.pageNumber,
            match.start,
            match.end,
            match.contextStart,
            match.contextText,
            match.pageTextLength,
            [for (final rect in match.rects) _rect(rect)],
          ],
      ],
  ]),
};

String _signature(Map<String, Object?> row) => jsonEncode([
  row['textSha256'],
  row['geometrySha256'],
  row['matchesSha256'],
  row['queries'],
]);
String _hash(Object value) =>
    sha256.convert(utf8.encode(jsonEncode(value))).toString();
List<double> _rect(PdfRect rect) => [
  rect.left,
  rect.top,
  rect.right,
  rect.bottom,
];

class _TextPage implements PdfPage {
  _TextPage(this.base, {this._captured});
  final PdfPage base;
  final PdfPageRawText? _captured;
  var rawLoadCalls = 0;
  var rawLoadUs = 0;
  var capturedCalls = 0;

  @override
  Future<PdfPageRawText?> loadText() async {
    final captured = _captured;
    if (captured != null) {
      capturedCalls++;
      return captured;
    }
    rawLoadCalls++;
    final clock = Stopwatch()..start();
    final raw = await base.loadText();
    clock.stop();
    rawLoadUs += clock.elapsedMicroseconds;
    if (raw == null) throw StateError('עמוד טעון לא החזיר שכבת טקסט');
    return raw;
  }

  @override
  PdfDocument get document => base.document;
  @override
  int get pageNumber => base.pageNumber;
  @override
  bool get isLoaded => base.isLoaded;
  @override
  double get width => base.width;
  @override
  double get height => base.height;
  @override
  PdfPageRotation get rotation => base.rotation;
  @override
  Future<List<PdfLink>> loadLinks({
    bool compact = false,
    bool enableAutoLinkDetection = true,
  }) => throw UnsupportedError('Text measurement does not load links');
  @override
  PdfPageRenderCancellationToken createCancellationToken() =>
      throw UnsupportedError('Text measurement does not render');
  @override
  Future<PdfImage?> render({
    int x = 0,
    int y = 0,
    int? width,
    int? height,
    double? fullWidth,
    double? fullHeight,
    int? backgroundColor,
    PdfPageRotation? rotationOverride,
    PdfAnnotationRenderingMode annotationRenderingMode =
        PdfAnnotationRenderingMode.annotationAndForms,
    int flags = PdfPageRenderFlags.none,
    PdfPageRenderCancellationToken? cancellationToken,
    PdfPageRenderPriority? priority,
  }) => throw UnsupportedError('Text measurement does not render');
}
