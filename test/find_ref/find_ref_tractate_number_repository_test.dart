import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/find_ref/repository/find_ref_repository.dart';

import 'support/seeded_reference_library.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(resetSeededLibrary);

  FindRefRepository repository() {
    seedLibrary(
      const [
        (id: 1, title: 'משנה שבת', acronyms: ['מסכת שבת']),
        (id: 2, title: 'שבת', acronyms: ['מסכת שבת', 'תלמוד בבלי שבת']),
        (id: 3, title: 'משנה בבא קמא', acronyms: <String>[]),
        (id: 4, title: 'בבא קמא', acronyms: ['ב"ק']),
        (id: 5, title: 'משנה ראש השנה', acronyms: ['ר"ה']),
        (id: 6, title: 'ראש השנה', acronyms: ['ר"ה']),
      ],
      categoryPaths: {
        for (var id = 1; id <= 6; id++)
          id: id.isOdd ? 'משנה, סדר מועד' : 'תלמוד בבלי, סדר מועד',
      },
    );
    final finder = FindRefRepository(
      isReferenceBooksCacheLoaded: () => true,
      warmUpReferenceBooksCache: () async {},
      getTocEntriesForReference: (id, title, {queryTokens}) async {
        final location = queryTokens!.where((t) => t != 'פרק').toList();
        return [
          {
            'reference': id.isOdd
                ? '$title פרק ${location.join(' משנה ')}'
                : '$title דף ${location.first}.',
            'segment': id,
            'level': 2,
            if (id.isEven && location.length > 1) 'partialMatch': true,
          },
        ];
      },
      getAltTocEntriesForReference: (id, title, {queryTokens}) async => [],
      getAllAltTocFlatEntries: () async => [],
      getCategoryPath: (_) async => '',
    );
    addTearDown(finder.dispose);
    return finder;
  }

  for (final (query, expected) in [
    ('שבת יג', 'שבת'),
    ('בבא קמא ג', 'בבא קמא'),
    ('ב"ק ג', 'בבא קמא'),
    ('ר"ה ג', 'ראש השנה'),
    ('ראש השנה ג', 'ראש השנה'),
    ('שבת יג ג', 'משנה שבת'),
    ('מסכת שבת יג ג', 'משנה שבת'),
    ('מסכת שבת ג', 'משנה שבת'),
    ('תלמוד בבלי שבת יג', 'שבת'),
    ('שבת טו ג', 'משנה שבת'),
    ('בבא קמא יג ג', 'משנה בבא קמא'),
    ('ר"ה יג ג', 'משנה ראש השנה'),
    ('שבת פרק ג', 'משנה שבת'),
    ('משנה שבת ג', 'משנה שבת'),
  ]) {
    test('שם/כינוי ומספר: $query → $expected', () async {
      final results = await repository().findRefs(query);
      expect(results, isNotEmpty);
      expect(results.first.title, expected);
      expect(results.first.isPartialTocMatch, isFalse);
    });
  }
}
