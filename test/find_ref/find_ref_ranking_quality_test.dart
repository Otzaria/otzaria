import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/find_ref/repository/find_ref_repository.dart';
import 'package:otzaria/find_ref/repository/reference_books_cache.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/utils/text/text_manipulation.dart';

import '../helpers/seforim_fixture_db.dart';

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
  Future<List<Map<String, dynamic>>> Function(
    int bookId,
    String title,
    List<String>? queryTokens,
  )?
  altToc,
  List<ReferenceBookHit> Function(String query)? hitsFor,
}) => FindRefRepository(
  dataRepository: _MockDataRepository(),
  isReferenceBooksCacheLoaded: () => true,
  warmUpReferenceBooksCache: () async {},
  searchReferenceBooks: (query, {int limit = 50}) =>
      hitsFor?.call(query) ?? hits,
  getTocEntriesForReference: (bookId, title, {queryTokens}) async =>
      toc == null ? const [] : toc(bookId, title, queryTokens),
  getAltTocEntriesForReference: (bookId, title, {queryTokens}) async =>
      altToc == null ? const [] : altToc(bookId, title, queryTokens),
  getCategoryPathSync: (_) => null,
  getCategoryPath: (_) async => '',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  test('AltToc מלא באותו ספר קודם להתאמת TOC חלקית רדודה', () async {
    // קריאת TOC אחת מחזירה דגל complete אחד, ולכן החלקית מתחרה ב-AltToc.
    final repo = _repo(
      hits: [_hit(1, 'ספר בדיקה')],
      toc: (_, _, _) async => [
        {
          'reference': 'ספר בדיקה חלק ב',
          'segment': 10,
          'level': 1,
          'dbLineId': 0,
          'partialMatch': true,
        },
      ],
      altToc: (_, _, _) async => [
        {'reference': 'שער ב סימן א', 'segment': 50, 'level': 2, 'dbLineId': 0},
      ],
    );

    final results = await repo.findRefs('ספר בדיקה ב א');

    expect(results.map((r) => r.segment).take(2), [50, 10]);
    expect(results.first.isAltToc, isTrue);
  });

  test('TOC חלקי ו-AltToc מלא לאותה שורה — ההתאמה המלאה נשמרת', () async {
    // כמו "שיר השירים רבה א פרק א פרשה א": ה-TOC מקדים ל-AltToc בסדר האיסוף.
    final repo = _repo(
      hits: [_hit(1, 'ספר בדיקה')],
      hitsFor: (query) =>
          query.startsWith('ספר') ? [_hit(1, 'ספר בדיקה')] : const [],
      toc: (_, _, _) async => [
        {
          'reference': 'ספר בדיקה פרשה א',
          'segment': 2,
          'level': 1,
          'dbLineId': 0,
          'partialMatch': true,
        },
      ],
      altToc: (_, _, _) async => [
        {'reference': 'פרק א פרשה א', 'segment': 2, 'level': 1, 'dbLineId': 0},
        {'reference': 'פרשה ב פרק א', 'segment': 91, 'level': 1, 'dbLineId': 0},
      ],
    );

    final results = await repo.findRefs('ספר בדיקה פרק א פרשה א');

    expect(results.map((r) => r.segment).take(2), [2, 91]);
    expect(results.first.isPartialTocMatch, isFalse);
  });

  test('אב חלקי אינו מסתיר צאצא מלא באותו ספר', () async {
    // אותו ספר פעמיים: התאמה ישירה ל"ספר בדיקה" ומקורבת לצירוף בן 3 טוקנים.
    final fuzzy = ReferenceBookHit(
      bookId: 1,
      title: 'ספר בדיקה',
      normalizedTitle: 'ספר בדיקה',
      filePath: '',
      fileType: 'txt',
      matchRank: ReferenceBooksCache.fuzzyMatchRank,
      orderIndex: 999,
    );
    final repo = _repo(
      hits: const [],
      hitsFor: (query) => switch (query) {
        'ספר בדיקה' => [_hit(1, 'ספר בדיקה')],
        'ספר בדיקה פרק' => [fuzzy],
        _ => const [],
      },
      toc: (_, _, tokens) async => [
        if (tokens!.length == 2)
          {
            'reference': 'ספר בדיקה פרק א',
            'segment': 5,
            'level': 2,
            'dbLineId': 0,
          }
        else
          {
            'reference': 'ספר בדיקה פרק',
            'segment': 1,
            'level': 1,
            'dbLineId': 0,
            'partialMatch': true,
          },
      ],
    );

    final results = await repo.findRefs('ספר בדיקה פרק א');

    expect(results.first.segment, 5);
    expect(results.first.isPartialTocMatch, isFalse);
  });

  group('SeforimRepository.getTocEntriesForReference — סימון התאמה חלקית', () {
    late Directory tempDir;
    late MyDatabase database;
    late SeforimRepository repo;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('otzaria_toc_partial');
      final dbPath = SeforimFixtureDb.create(
        tempDir,
        SeforimFixtureVariant.full,
      );
      database = MyDatabase.withPath(dbPath, readOnly: true);
      repo = SeforimRepository(database);
      await repo.ensureInitialized();
    });

    tearDown(() async {
      database.close();
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    });

    test('ירידה שנעצרה לפני סוף השאילתה מסומנת partialMatch', () async {
      final full = await repo.getTocEntriesForReference(
        SeforimFixtureIds.bereshitId,
        SeforimFixtureIds.bereshitTitle,
        queryTokens: const ['א'],
      );
      final partial = await repo.getTocEntriesForReference(
        SeforimFixtureIds.bereshitId,
        SeforimFixtureIds.bereshitTitle,
        queryTokens: const ['א', 'ב'],
      );

      expect(full, isNotEmpty);
      expect(full.every((e) => e['partialMatch'] == null), isTrue);
      expect(partial, isNotEmpty);
      expect(partial.every((e) => e['partialMatch'] == true), isTrue);
    });
  });
}
