import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/find_ref/repository/find_ref_repository.dart';
import 'package:otzaria/find_ref/repository/reference_books_cache.dart';
import 'package:otzaria/utils/text/ref_key.dart';
import 'package:otzaria/utils/text/text_manipulation.dart';

class MockDataRepository extends Mock implements DataRepository {}

/// ע"א/ע"ב שהוקלדו בשאילתה הם ציון עמוד, ו"עא" חשוף נשאר דף ע"א (71).
void main() {
  const bavli = 1;
  const yerushalmi = 2;
  const titles = {bavli: 'ברכות', yerushalmi: 'ברכות ירושלמי'};

  /// כותרות ה-TOC בפורמט של ה-DB ("דף ב." = עמוד א).
  const tocByBook = {
    bavli: ['דף ב.', 'דף ב:', 'דף עא.', 'דף עא:'],
    yerushalmi: ['פרק ב הלכה א'],
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
        orderIndex: bookId == bavli ? 5 : 1,
      );

  List<ReferenceBookHit> searchBooks(String query, {int limit = 50}) => [
    if (query == 'ברכות') ...[hit(bavli, 0, query), hit(yerushalmi, 1, query)],
  ];

  /// כמו החיפוש ההיררכי בייצור: ציטוט דף מותאם מיקומית, השאר לפי טוקנים.
  List<Map<String, dynamic>> tocFor(
    int bookId,
    String bookTitle,
    List<String>? queryTokens,
  ) {
    final cite = queryTokens == null ? null : parseDafCitation(queryTokens);
    final headings = tocByBook[bookId] ?? const <String>[];
    return [
      for (final (i, heading) in headings.indexed)
        if (queryTokens == null ||
            (cite != null &&
                matchDafCitation(
                      normalizeForFindRefMatch(heading).split(' '),
                      cite,
                    ) ==
                    true) ||
            (cite == null &&
                queryTokens.every(
                  normalizeForFindRefMatch(heading).split(' ').contains,
                )) ||
            (bookId == yerushalmi && cite != null))
          {'reference': '$bookTitle $heading', 'segment': i * 10, 'level': 1},
    ];
  }

  FindRefRepository buildRepo() => FindRefRepository(
    dataRepository: MockDataRepository(),
    isReferenceBooksCacheLoaded: () => true,
    warmUpReferenceBooksCache: () async {},
    searchReferenceBooks: searchBooks,
    getAltStructureBookIds: () async => const [],
    getAllAltTocFlatEntries: () async => const [],
    getTocEntriesForReference: (bookId, bookTitle, {queryTokens}) async =>
        tocFor(bookId, bookTitle, queryTokens),
    getCategoryPath: (bookId) async => '',
  );

  Future<List<String>> bavliRefs(String query) async => [
    for (final r in await buildRepo().findRefs(query))
      if (r.bookId == bavli) r.reference,
  ];

  for (final query in ['ברכות ב ע"א', 'ברכות ב ע״א', "ברכות ב ע'א"]) {
    test('"$query" — עמוד א של דף ב', () async {
      expect(await bavliRefs(query), ['ברכות דף ב.']);
    });
  }

  for (final query in ['ברכות ב ע"ב', 'ברכות ב ע״ב']) {
    test('"$query" — עמוד ב של דף ב', () async {
      expect(await bavliRefs(query), ['ברכות דף ב:']);
    });
  }

  test('"ברכות עא" — "עא" חשוף הוא דף ע"א (71)', () async {
    expect(
      await bavliRefs('ברכות עא'),
      containsAll(['ברכות דף עא.', 'ברכות דף עא:']),
    );
  });

  test('"ברכות עא ע״ב" — עמוד ב של דף ע"א', () async {
    expect(await bavliRefs('ברכות עא ע״ב'), ['ברכות דף עא:']);
  });

  test('ציון עמוד מדרג ערכי "דף" מעל כותרות שאינן דף', () async {
    final refs = [
      for (final r in await buildRepo().findRefs('ברכות ב ע"א')) r.reference,
    ];
    expect(refs.first, 'ברכות דף ב.');
    expect(refs, contains('ברכות ירושלמי פרק ב הלכה א'));
  });

  test('expandQueryAmudMarks לא נוגע בראשי תיבות ובמספר חשוף', () {
    expect(expandQueryAmudMarks('חידושי רע"א'), 'חידושי רע"א');
    expect(expandQueryAmudMarks('ברכות עא'), 'ברכות עא');
    expect(expandQueryAmudMarks('ברכות ב ע״ב'), 'ברכות ב עמוד ב');
  });
}
