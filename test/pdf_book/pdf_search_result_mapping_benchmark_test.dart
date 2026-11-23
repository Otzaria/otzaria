import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/pdf_book/utils/pdf_search_result_list.dart';
import 'package:otzaria/pdf_book/view/pdf_search_screen.dart';
import 'package:otzaria_search_engine/otzaria_search_engine.dart';
import 'package:pdfrx/pdfrx.dart';

// flutter test --no-pub test/pdf_book/pdf_search_result_mapping_benchmark_test.dart
// מודד את מיפוי התוצאות באפליקציה, בלי לייחס את הזמן לסריקת PDF או לרינדור.
void main() {
  test('PDF search mapping: 1000 pages, 10 matches, wrap from page 501', () {
    const pageCount = 1000;
    const perPage = 10;
    final batches = _snapshots(pageCount, perPage);
    final before = <int>[];
    final after = <int>[];
    final visible = <int>[];
    late _Measurement baseline;
    late _Measurement changed;
    late _Measurement window;
    for (var run = 0; run < 7; run++) {
      baseline = _legacy(batches);
      changed = _incremental(batches, materializeAll: true);
      window = _incremental(batches, materializeAll: false);
      expect(baseline.created, 382500);
      expect(changed.created, pageCount * perPage);
      expect(window.created, lessThanOrEqualTo(20));
      expect(changed.snippetCharacters, lessThan(baseline.snippetCharacters));
      if (run >= 2) {
        before.add(baseline.elapsedUs);
        after.add(changed.elapsedUs);
        visible.add(window.elapsedUs);
      }
    }
    before.sort();
    after.sort();
    visible.sort();
    // ignore: avoid_print
    print(
      jsonEncode({
        'scenario': 'app-result-mapping-only',
        'pages': pageCount,
        'matchesPerPage': perPage,
        'notifications': batches.length,
        'legacy': {
          'constructedResults': baseline.created,
          'snippetCharacters': baseline.snippetCharacters,
          'medianUs': before[before.length ~/ 2],
          'maxUs': before.last,
        },
        'incrementalReadAll': {
          'constructedResults': changed.created,
          'snippetCharacters': changed.snippetCharacters,
          'medianUs': after[after.length ~/ 2],
          'maxUs': after.last,
        },
        'incrementalVisibleWindow': {
          'constructedResults': window.created,
          'snippetCharacters': window.snippetCharacters,
          'medianUs': visible[visible.length ~/ 2],
          'maxUs': visible.last,
        },
      }),
    );
  });
}

List<List<PdfTextSearchResult>> _snapshots(int pages, int matchesPerPage) {
  const phrase = 'שלום עולם ומלואו ';
  final pageText = List.filled(matchesPerPage, phrase).join();
  final matches = List.generate(pages, (page) {
    final text = PdfPageText(
      pageNumber: page + 1,
      fullText: pageText,
      charRects: List.filled(pageText.length, const PdfRect(0, 1, 1, 0)),
      fragments: const [],
    );
    return List.generate(
      matchesPerPage,
      (i) => PdfTextSearchResult.fromRange(
        PdfPageTextRange(
          pageText: text,
          start: i * phrase.length,
          end: i * phrase.length + 4,
        ),
      ),
    );
  });
  final scanned = <int>{};
  return [
    for (var batch = 0; batch < pages ~/ 10; batch++)
      (() {
        for (var i = 0; i < 10; i++) {
          scanned.add((pages ~/ 2 + batch * 10 + i) % pages);
        }
        final sorted = scanned.toList()..sort();
        return [for (final page in sorted) ...matches[page]];
      })(),
  ];
}

class _Measurement {
  int created = 0;
  int snippetCharacters = 0;
  int elapsedUs = 0;

  SearchResult create(PdfTextSearchResult match, int id) {
    final snippet = PdfBookSearchView.matchLineSnippet(match, 'שלום');
    created++;
    snippetCharacters += snippet.length;
    return SearchResult(
      id: BigInt.from(id),
      title: 'ספר',
      reference: '',
      text: snippet,
      segment: BigInt.from(match.pageNumber - 1),
      isPdf: true,
      filePath: '/book.pdf',
      mergedCount: 1,
      merged: const [],
      textStatus: TextStatus.ok,
      continuesToNextLine: false,
    );
  }
}

_Measurement _legacy(List<List<PdfTextSearchResult>> snapshots) {
  final measured = _Measurement();
  var previous = <PdfTextSearchResult>[];
  var results = <SearchResult>[];
  final stopwatch = Stopwatch()..start();
  for (final matches in snapshots) {
    final keep =
        previous.isNotEmpty &&
            matches.length >= previous.length &&
            identical(matches.first, previous.first) &&
            identical(matches[previous.length - 1], previous.last)
        ? previous.length
        : 0;
    if (keep == 0) results = [];
    for (var i = keep; i < matches.length; i++) {
      results.add(measured.create(matches[i], i));
    }
    previous = matches;
  }
  measured.elapsedUs = stopwatch.elapsedMicroseconds;
  expect(results.length, snapshots.last.length);
  return measured;
}

_Measurement _incremental(
  List<List<PdfTextSearchResult>> snapshots, {
  required bool materializeAll,
}) {
  final measured = _Measurement();
  final results = PdfSearchResultList<SearchResult>(measured.create);
  final stopwatch = Stopwatch()..start();
  for (final matches in snapshots) {
    results.update(matches, generation: 1);
    if (materializeAll) {
      for (var i = 0; i < results.length; i++) {
        results[i];
      }
    } else {
      final start = results.visualIndexForPage(501);
      for (
        var i = start;
        i < start + 20 && i < results.groupedItems.length;
        i++
      ) {
        results.groupedItems[i];
      }
    }
  }
  measured.elapsedUs = stopwatch.elapsedMicroseconds;
  return measured;
}
