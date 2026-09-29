import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/find_ref/repository/find_ref_repository.dart';
import 'package:otzaria/find_ref/repository/reference_books_cache.dart';
import 'package:otzaria/utils/text/text_manipulation.dart';

class _MockDataRepository extends Mock implements DataRepository {}

ReferenceBookHit _hit(int bookId, String title, {double orderIndex = 999}) =>
    ReferenceBookHit(
      bookId: bookId,
      title: title,
      normalizedTitle: normalizeForFindRefMatch(title),
      filePath: '',
      fileType: 'txt',
      matchRank: 0,
      orderIndex: orderIndex,
    );

FindRefRepository _repo({
  required List<ReferenceBookHit> hits,
  Future<List<Map<String, dynamic>>> Function(
    int bookId,
    String title,
    List<String>? queryTokens,
  )?
  toc,
}) => FindRefRepository(
  dataRepository: _MockDataRepository(),
  isReferenceBooksCacheLoaded: () => true,
  warmUpReferenceBooksCache: () async {},
  searchReferenceBooks: (_, {int limit = 50}) => hits,
  getTocEntriesForReference: (bookId, title, {queryTokens}) async =>
      toc == null ? const [] : toc(bookId, title, queryTokens),
  getCategoryPathSync: (_) => null,
  getCategoryPath: (_) async => '',
);

void main() {
  test('שם ספר בגרשיים זהה לשאילתה מקבל התאמה מלאה', () async {
    final repo = _repo(
      hits: [
        _hit(1, 'רשי על בראשית רבה', orderIndex: 1),
        _hit(2, 'רש"י על בראשית', orderIndex: 2),
      ],
    );

    final results = await repo.findRefs('רש"י על בראשית');

    expect(results.first.title, 'רש"י על בראשית');
  });
}
