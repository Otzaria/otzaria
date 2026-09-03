import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/find_ref/repository/find_ref_repository.dart';
import 'package:otzaria/find_ref/repository/reference_books_cache.dart';
import 'package:otzaria/utils/text/text_manipulation.dart';

class MockDataRepository extends Mock implements DataRepository {}

/// איתור "פרשה + דף" בזוהר: הפרשה נושאת שם של ספר חומש, ושני מגנים כלליים
/// (חסימת ירידה חוצת-ספרים, ועצירת זיהוי הספר על הצירוף הארוך ביותר) חסמו
/// אותה. שניהם נפתחים כשזנב השאילתה הוא ציטוט דף.
void main() {
  const zohar = 1; // "ספר הזהר" — הדפים ב-AltToc
  const meturgam = 2; // "הזוהר המתורגם - בראשית" — הדפים ב-TOC הרגיל
  const chumash = 3; // "בראשית" — הספר שהפרשה מתנגשת בשמו

  const titles = {
    zohar: 'ספר הזהר',
    meturgam: 'הזוהר המתורגם - בראשית',
    chumash: 'בראשית',
  };

  /// ראשי-התיבות כפי שהם ב-`book_acronym` — "זוהר בראשית" שייך למהדורה
  /// המתורגמת, ולכן הוא ה"ספר" הארוך ביותר שהשאילתה מתאימה לו.
  const acronyms = {
    zohar: ['זוהר', 'זהר'],
    meturgam: ['זוהר בראשית', 'הזוהר המתורגם'],
    chumash: <String>[],
  };

  ReferenceBookHit hit(int bookId, int matchRank, String term) =>
      ReferenceBookHit(
        bookId: bookId,
        title: titles[bookId]!,
        normalizedTitle: normalizeForFindRefMatch(titles[bookId]!),
        filePath: '',
        fileType: 'txt',
        matchRank: matchRank,
        matchedTerm: term,
        orderIndex: bookId.toDouble(),
      );

  List<ReferenceBookHit> searchBooks(String query, {int limit = 50}) {
    final out = <ReferenceBookHit>[];
    for (final entry in titles.entries) {
      final normalizedTitle = normalizeForFindRefMatch(entry.value);
      if (normalizedTitle == query) {
        out.add(hit(entry.key, 0, query));
      } else if (acronyms[entry.key]!.contains(query)) {
        out.add(hit(entry.key, 3, query));
      }
    }
    return out.take(limit).toList();
  }

  /// כותרות ה-TOC/AltToc של כל ספר, בפורמט שה-DB מחזיר.
  const altTocByBook = {
    zohar: ['כרך א בראשית דף לו.', 'כרך א בראשית דף לו:'],
  };
  const tocByBook = {
    meturgam: ['פרשת בראשית דף לו ע"א', 'פרשת בראשית דף לו ע"ב'],
  };

  /// סינון שטוח כמו ב-`_searchAltTocFlat`: כל טוקני השאילתה בנתיב הערך.
  List<Map<String, dynamic>> entriesFor(
    Iterable<String> references,
    List<String>? queryTokens,
    String? bookTitlePrefix,
  ) => [
    for (final reference in references)
      if (queryTokens == null ||
          queryTokens.every(
            (token) => normalizeForFindRefMatch(
              reference,
            ).split(' ').contains(token),
          ))
        {
          'reference': bookTitlePrefix == null
              ? reference
              : '$bookTitlePrefix $reference',
          'segment': 10,
          'level': 2,
          'dbLineId': 1,
        },
  ];

  FindRefRepository buildRepo() => FindRefRepository(
    dataRepository: MockDataRepository(),
    isReferenceBooksCacheLoaded: () => true,
    warmUpReferenceBooksCache: () async {},
    searchReferenceBooks: searchBooks,
    getAltStructureBookIds: () async => [zohar],
    getAllAltTocFlatEntries: () async => const [],
    getTocEntriesForReference: (bookId, bookTitle, {queryTokens}) async =>
        entriesFor(tocByBook[bookId] ?? const [], queryTokens, bookTitle),
    getAltTocEntriesForReference: (bookId, bookTitle, {queryTokens}) async =>
        entriesFor(altTocByBook[bookId] ?? const [], queryTokens, null),
    getCategoryPath: (bookId) async => '',
  );

  test('"זוהר בראשית דף לו" מחזיר את שתי המהדורות', () async {
    final results = await buildRepo().findRefs('זוהר בראשית דף לו');
    final bookIds = results.map((r) => r.bookId).toSet();

    expect(
      bookIds,
      containsAll([zohar, meturgam]),
      reason:
          'הצירוף "זוהר בראשית" הוא ראש-תיבות של המהדורה המתורגמת, אבל בציטוט '
          'דף גם הפירוש הקצר ("זוהר" + פרשת בראשית) חייב להיבדק',
    );
    expect(
      results.where((r) => r.isAltToc).map((r) => r.reference),
      contains('ספר הזהר כרך א בראשית דף לו.'),
    );
  });

  test('"זהר בראשית דף לו" — פרשה ששמה ספר אינה חוסמת את הירידה', () async {
    final results = await buildRepo().findRefs('זהר בראשית דף לו');

    expect(
      results.map((r) => r.reference),
      contains('ספר הזהר כרך א בראשית דף לו.'),
      reason:
          '"בראשית" היא ספר בפני עצמו, והמגן חוצה-הספרים איפס את השאילתה לגמרי',
    );
  });

  test('בלי ציטוט דף המגן חוצה-הספרים נשאר בתוקף', () async {
    final results = await buildRepo().findRefs('זהר בראשית פרק לו');

    expect(
      results.where((r) => r.bookId == zohar && r.tocLevel >= 2),
      isEmpty,
      reason: '"פרק לו" אינו ציטוט דף — אין להתיר ירידה לכותרות של ספר אחר',
    );
  });

  test('בלי ציטוט דף אין צירוף של הפירוש הקצר', () async {
    final results = await buildRepo().findRefs('זוהר בראשית פרק לו');

    expect(
      results.map((r) => r.bookId),
      isNot(contains(zohar)),
      reason:
          'הצירוף הארוך זיהה את המהדורה המתורגמת; בלי ציטוט דף אין סיבה לפרש '
          'את השאילתה גם כספר אחר',
    );
  });
}
