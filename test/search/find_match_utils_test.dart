import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/search/utils/find_match_utils.dart';

import '../support/search_engine_test_init.dart';

Future<void> main() async {
  // sanitizeQuery/splitQueryWords מאצילים למנוע ה-Rust; הטסטים שלהם דורשים
  // את הספרייה הנייטיבית ומדולגים כשאין build זמין.
  final engineReady = await tryInitSearchEngine();

  test('normalizeFindQuery מנרמל ניקוד וגרשיים כמו איתור', () {
    expect(normalizeFindQuery('שַׁבָּת "דף" ע׳'), 'שבת דף ע');
  }, skip: engineReady ? false : searchEngineSkipReason);

  test('findNormalizedTextMatchRank מעדיף התאמה מדויקת על contains', () {
    const query = 'שבת דף ע';

    final exactRank = findNormalizedTextMatchRank(
      normalizedQuery: query,
      normalizedPrimaryText: normalizeFindText('שבת דף ע'),
    );
    final containsRank = findNormalizedTextMatchRank(
      normalizedQuery: query,
      normalizedPrimaryText: normalizeFindText('מאירי על שבת דף ע'),
    );

    expect(exactRank, lessThan(containsRank));
  });
}
