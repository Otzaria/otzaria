import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/indexing/repository/indexing_repository.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/search/utils/facet_helper.dart';

class _FakeSearchResult {
  final String filePath;

  _FakeSearchResult(this.filePath);
}

void main() {
  group('FacetHelper.buildFacetCountsFromResults', () {
    test('מחשב ספירות עבור שורש, אבות וספרים', () {
      final genesis = TextBook(
        id: 101,
        title: 'בראשית',
        categoryPath: '/תנ"ך/תורה',
      );
      final berachot = TextBook(
        id: 202,
        title: 'ברכות',
        categoryPath: '/משנה/זרעים',
      );

      final bookByIndexedFilePath = <String, Book>{
        IndexingRepository.buildIndexedBookFilePath(genesis): genesis,
        IndexingRepository.buildIndexedBookFilePath(berachot): berachot,
      };

      final counts = FacetHelper.buildFacetCountsFromResults(
        [
          _FakeSearchResult(
              IndexingRepository.buildIndexedBookFilePath(genesis)),
          _FakeSearchResult(
              IndexingRepository.buildIndexedBookFilePath(berachot)),
        ],
        bookByIndexedFilePath,
      );

      expect(counts['/'], 2);
      expect(counts['/תנ"ך'], 1);
      expect(counts['/תנ"ך/תורה'], 1);
      expect(counts['/תנ"ך/תורה/id:101'], 1);
      expect(counts['/משנה'], 1);
      expect(counts['/משנה/זרעים'], 1);
      expect(counts['/משנה/זרעים/id:202'], 1);
    });

    test('מבדיל בין ספרים עם אותו שם לפי מפתח ה-filePath היציב', () {
      final firstBook = TextBook(
        id: 11,
        title: 'שבת',
        categoryPath: '/תלמוד בבלי/סדר מועד',
      );
      final secondBook = TextBook(
        id: 22,
        title: 'שבת',
        categoryPath: '/הלכה',
      );

      final counts = FacetHelper.buildFacetCountsFromResults(
        [
          _FakeSearchResult(
              IndexingRepository.buildIndexedBookFilePath(firstBook)),
          _FakeSearchResult(
              IndexingRepository.buildIndexedBookFilePath(secondBook)),
        ],
        {
          IndexingRepository.buildIndexedBookFilePath(firstBook): firstBook,
          IndexingRepository.buildIndexedBookFilePath(secondBook): secondBook,
        },
      );

      expect(counts['/תלמוד בבלי/סדר מועד/id:11'], 1);
      expect(counts['/הלכה/id:22'], 1);
    });

    test('תוצאה של ספר שכבר אינו בספרייה מדולגת בשקט', () {
      final counts = FacetHelper.buildFacetCountsFromResults(
        [_FakeSearchResult('uid:99')],
        const <String, Book>{},
      );

      expect(counts, isEmpty);
    });
  });

  group('FacetHelper.buildFacetCountsFromBookCounts', () {
    test('מחשב ספירות אגרגטיביות ממפת ספרים ייחודית', () {
      final genesis = TextBook(
        title: 'בראשית',
        id: 101,
        categoryPath: '/תנ"ך/תורה',
      );
      final berachot = TextBook(
        title: 'ברכות',
        id: 202,
        categoryPath: '/משנה/זרעים',
      );

      final counts = FacetHelper.buildFacetCountsFromBookCounts(
        {
          IndexingRepository.buildIndexedBookFilePath(genesis): 3,
          IndexingRepository.buildIndexedBookFilePath(berachot): 2,
        },
        {
          IndexingRepository.buildIndexedBookFilePath(genesis): genesis,
          IndexingRepository.buildIndexedBookFilePath(berachot): berachot,
        },
      );

      expect(counts['/'], 5);
      expect(counts['/תנ"ך'], 3);
      expect(counts['/תנ"ך/תורה'], 3);
      expect(counts['/תנ"ך/תורה/id:101'], 3);
      expect(counts['/משנה'], 2);
      expect(counts['/משנה/זרעים'], 2);
      expect(counts['/משנה/זרעים/id:202'], 2);
    });

    test('מנרמל categoryPath עם פסיקים לפני בניית facets', () {
      final genesis = TextBook(
        title: 'בראשית',
        id: 101,
        categoryPath: 'תנ"ך, תורה',
      );

      final counts = FacetHelper.buildFacetCountsFromBookCounts(
        {
          IndexingRepository.buildIndexedBookFilePath(genesis): 1,
        },
        {
          IndexingRepository.buildIndexedBookFilePath(genesis): genesis,
        },
      );

      expect(counts['/'], 1);
      expect(counts['/תנ"ך'], 1);
      expect(counts['/תנ"ך/תורה'], 1);
      expect(counts['/תנ"ך/תורה/id:101'], 1);
      expect(counts.containsKey('/תנ"ך, תורה'), isFalse);
    });
  });
}
