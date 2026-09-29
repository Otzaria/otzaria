import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/find_ref/repository/find_ref_repository.dart';
import 'package:otzaria/find_ref/repository/reference_books_cache.dart';
import 'package:otzaria/utils/text/ref_key.dart';
import 'package:otzaria/utils/text/text_manipulation.dart';

class MockDataRepository extends Mock implements DataRepository {}

/// ע"א/ע"ב אחרי מספר דף הם ציון עמוד; אחרי מילה ("תהלים ע"א") ובלי גרשיים
/// ("עא") הם המספרים 71/72.
void main() {
  const bavli = 1;
  const yerushalmi = 2;
  const tehillim = 3;
  const shulchan = 4;
  const titles = {
    bavli: 'ברכות',
    yerushalmi: 'ברכות ירושלמי',
    tehillim: 'תהלים',
    shulchan: 'שולחן ערוך אורח חיים',
  };

  /// כותרות ה-TOC בפורמט של ה-DB ("דף ב." = עמוד א).
  const tocByBook = {
    bavli: ['דף ב.', 'דף ב:', 'דף עא.', 'דף עא:'],
    yerushalmi: ['פרק ב הלכה א'],
    tehillim: ['פרק א', 'פרק עא', 'פרק עב'],
    shulchan: ['סימן עא', 'סימן עב'],
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
    if (query == 'תהלים') hit(tehillim, 0, query),
    if (query == 'שוע אוח') hit(shulchan, 3, query),
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
            ((cite == null
                    ? null
                    : matchDafCitation(
                        normalizeForFindRefMatch(heading).split(' '),
                        cite,
                      )) ??
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

  Future<List<String>> refsOf(int bookId, String query) async => [
    for (final r in await buildRepo().findRefs(query))
      if (r.bookId == bookId) r.reference,
  ];

  Future<List<String>> bavliRefs(String query) => refsOf(bavli, query);

  for (final query in ['תהלים ע"א', 'תהלים ע״א', 'תהלים פרק ע"א']) {
    test('"$query" — ע"א אחרי מילה הוא המספר 71', () async {
      expect(await refsOf(tehillim, query), ['תהלים פרק עא']);
    });
  }

  test('"שו"ע או"ח סימן ע"ב" — סימן 72', () async {
    expect(await refsOf(shulchan, 'שו"ע או"ח סימן ע"ב'), [
      'שולחן ערוך אורח חיים סימן עב',
    ]);
  });

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

  test('expandQueryAmudMarks מרחיב רק אחרי מספר דף', () {
    expect(expandQueryAmudMarks('חידושי רע"א'), 'חידושי רע"א');
    expect(expandQueryAmudMarks('ברכות עא'), 'ברכות עא');
    expect(expandQueryAmudMarks('ברכות ב ע״ב'), 'ברכות ב עמוד ב');
    expect(expandQueryAmudMarks('ברכות דף ב ע"ב'), 'ברכות דף ב עמוד ב');
    expect(expandQueryAmudMarks('ברכות קכ ע"א'), 'ברכות קכ עמוד א');
    expect(expandQueryAmudMarks('ברכות ק"כ ע"א'), 'ברכות ק"כ עמוד א');
    expect(expandQueryAmudMarks('ע"א'), 'ע"א');
    expect(expandQueryAmudMarks('שבת ע"א'), 'שבת ע"א');
    expect(expandQueryAmudMarks('ברכות דף ע"א'), 'ברכות דף ע"א');
    expect(expandQueryAmudMarks('תהלים פרק ע"א'), 'תהלים פרק ע"א');
    expect(expandQueryAmudMarks('סימן ע"ב'), 'סימן ע"ב');
  });

  test('isHebrewNumeral', () {
    for (final n in ['א', 'ב', 'יא', 'טו', 'טז', 'עא', 'קכ', 'קכא', 'תת']) {
      expect(isHebrewNumeral(n), isTrue, reason: n);
    }
    for (final n in ['שבת', 'פרק', 'דף', 'חלק', 'אב', 'יי', 'אבגד', '']) {
      expect(isHebrewNumeral(n), isFalse, reason: n);
    }
  });
}
