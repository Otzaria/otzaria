import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/text_book/utils/section_search_utils.dart';

import '../../support/search_engine_test_init.dart';

Future<void> main() async {
  final engineReady = await tryInitSearchEngine();

  group(
    'searchHighlightFractionInLine (issue #1642)',
    () {
      const line = 'אחת שתים שלוש ארבע חמש שמע נא ישראל שש שבע';

      test('locates a distance query that the literal phrase misses', () {
        expect(matchFractionInLine(line, 'שמע ישראל'), 0);

        final fraction = searchHighlightFractionInLine(
          line,
          'שמע ישראל',
          searchDistance: 2,
        );
        expect(fraction, closeTo(line.indexOf('שמע') / line.length, 1e-9));
      });

      test(
        'falls back to the literal match when the pattern finds nothing',
        () {
          expect(
            searchHighlightFractionInLine(line, 'ארבע'),
            matchFractionInLine(line, 'ארבע'),
          );
        },
      );
    },
    skip: engineReady ? false : searchEngineSkipReason,
  );
}
