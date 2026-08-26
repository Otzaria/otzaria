import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/find_ref/repository/find_ref_repository.dart';
import 'package:otzaria/utils/navigation/line_ref_matcher.dart';

import 'support/seeded_reference_library.dart';

/// issue #992 — איתור גם לפי פסוקים: "ישעיהו לב יא" צריך להגיע לשורת
/// הפסוק דרך ה-heRef הפר-שורתי, וכשגם זה לא נמצא — להשאיר את הכותרת
/// העמוקה ביותר שכן נמצאה במקום למחוק את כל התוצאות.
///
/// שני מודלים ל-TOC המדומה, כי לחיפוש ההיררכי האמיתי שתי התנהגויות:
/// החזרת התאמה *חלקית* (הפרק) כשהטוקן העמוק לא נמצא — כמו "ישעיהו כ ד"
/// בפועל — או רשימה ריקה. הפיצ'ר חייב לעבוד בשתיהן.
const _isaiahId = 12;

const _chapterEntry = {
  'reference': 'ישעיהו פרק לב',
  'segment': 637,
  'level': 2,
  'dbLineId': 11158,
};

/// מודל "חלקי": כמו _searchTocHierarchically — מחזיר את הפרק כל עוד
/// אחד הטוקנים הוא "לב", גם כשיש טוקנים עודפים שלא נמצאו.
Future<List<Map<String, dynamic>>> _partialToc(
  int bookId,
  String bookTitle, {
  List<String>? queryTokens,
}) async {
  if (bookId != _isaiahId || queryTokens == null) return const [];
  return queryTokens.contains('לב') ? const [_chapterEntry] : const [];
}

/// מודל "קפדני": מחזיר את הפרק רק כשכל הטוקנים שייכים לכותרת — מדמה את
/// המקרה שבו החיפוש הפנימי מחזיר ריק על טוקן עודף.
Future<List<Map<String, dynamic>>> _strictToc(
  int bookId,
  String bookTitle, {
  List<String>? queryTokens,
}) async {
  if (bookId != _isaiahId || queryTokens == null || queryTokens.isEmpty) {
    return const [];
  }
  const chapterTokens = ['פרק', 'לב'];
  if (!queryTokens.every(chapterTokens.contains)) return const [];
  return const [_chapterEntry];
}

typedef _TocFn =
    Future<List<Map<String, dynamic>>> Function(
      int bookId,
      String bookTitle, {
      List<String>? queryTokens,
    });

FindRefRepository _buildRepo({
  required _TocFn toc,
  Future<Map<String, dynamic>?> Function(
    int bookId,
    String bookTitle,
    List<String> refTokens,
  )?
  resolveLineRef,
  List<List<String>>? resolveCallsSeen,
}) {
  return FindRefRepository(
    isReferenceBooksCacheLoaded: () => true,
    warmUpReferenceBooksCache: () async {},
    getTocEntriesForReference: toc,
    getAltTocEntriesForReference: (bookId, bookTitle, {queryTokens}) async =>
        const [],
    getAllAltTocFlatEntries: () async => const [],
    getCategoryPath: (bookId) async => 'ספרייה',
    resolveLineRef: (bookId, bookTitle, refTokens) async {
      resolveCallsSeen?.add(refTokens);
      return resolveLineRef?.call(bookId, bookTitle, refTokens);
    },
  );
}

Future<Map<String, dynamic>?> _verse32_11(
  int bookId,
  String bookTitle,
  List<String> refTokens,
) async {
  if (bookId == _isaiahId && refTokens.join(' ') == 'לב יא') {
    return {'lineIndex': 648, 'dbLineId': 11169, 'heRef': 'ישעיהו לב, יא'};
  }
  return null;
}

void main() {
  setUp(() {
    seedLibrary([(id: _isaiahId, title: 'ישעיהו', acronyms: [])]);
  });

  tearDown(resetSeededLibrary);

  for (final (label, toc) in [('חלקי', _partialToc), ('קפדני', _strictToc)]) {
    group('TOC $label', () {
      test('"ישעיהו לב יא" נפתר לשורת הפסוק דרך ה-heRef', () async {
        final repo = _buildRepo(toc: toc, resolveLineRef: _verse32_11);

        final results = await repo.findRefs('ישעיהו לב יא');

        expect(results, isNotEmpty, reason: 'הפסוק חייב להימצא');
        final verse = results.first;
        expect(verse.reference, 'ישעיהו לב, יא');
        expect(verse.segment, 648);
        expect(
          verse.sourceLineId,
          11169,
          reason: 'dbLineId נדרש לטעינת מפרשים',
        );
        expect(verse.tocLevel, 3);
        expect(
          results.map((r) => r.reference),
          isNot(contains('ישעיהו פרק לב')),
          reason: 'הפסוק המדויק מסתיר את התאמת הפרק החלקית',
        );
      });

      test('פסוק שאינו קיים — הפרק נשאר במקום "לא נמצא"', () async {
        final repo = _buildRepo(toc: toc); // רזולוציית שורה תמיד null

        final results = await repo.findRefs('ישעיהו לב תתקצט');

        expect(
          results.map((r) => r.reference),
          contains('ישעיהו פרק לב'),
          reason: 'טוקן שלא נמצא לא מוחק את התוצאות — נשארת כותרת הפרק',
        );
      });

      test('"ישעיהו לב" לבדו — מסלול הכותרות הרגיל, בלי רזולוציית שורה',
          () async {
        final calls = <List<String>>[];
        final repo = _buildRepo(toc: toc, resolveCallsSeen: calls);

        final results = await repo.findRefs('ישעיהו לב');

        expect(results.first.reference, 'ישעיהו פרק לב');
        expect(
          calls,
          isEmpty,
          reason: 'הכותרת כיסתה את כל הטוקנים — אין סריקת heRef מיותרת',
        );
      });
    });
  }

  test('מילות מיקום מסוננות: "פרק לב פסוק יא" שקול ל"לב יא"', () {
    expect(filterLineRefLocators(['פרק', 'לב', 'פסוק', 'יא']), ['לב', 'יא']);
  });

  test('שם ספר בלבד — אין רזולוציית שורה ואין כותרות', () async {
    final calls = <List<String>>[];
    final repo = _buildRepo(toc: _strictToc, resolveCallsSeen: calls);

    final results = await repo.findRefs('ישעיהו');

    expect(results, hasLength(1));
    expect(results.first.reference, 'ישעיהו');
    expect(calls, isEmpty);
  });
}
