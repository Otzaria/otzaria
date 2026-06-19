import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tools/shamor_zachor/models/book_model.dart';
import 'package:otzaria/tools/shamor_zachor/models/progress_model.dart';
import 'package:otzaria/tools/shamor_zachor/providers/shamor_zachor_progress_provider.dart';
import 'package:otzaria/tools/shamor_zachor/services/progress_service.dart';

class _FakeProgressService extends ProgressService {
  _FakeProgressService({
    required this.progressById,
    required this.completionDatesById,
    Map<int, List<ProgressColumn>>? columnsById,
  }) : columnsById = columnsById ?? {};

  ProgressMapById progressById;
  CompletionDatesByIdMap completionDatesById;
  Map<int, List<ProgressColumn>> columnsById;

  @override
  Future<ProgressMapById> loadProgressDataById() async => progressById;

  @override
  Future<CompletionDatesByIdMap> loadCompletionDatesById() async =>
      completionDatesById;

  @override
  Future<Map<int, List<ProgressColumn>>> loadColumnsByBookId() async =>
      columnsById;

  @override
  Future<void> saveProgressDataById(ProgressMapById data) async {
    progressById = data;
  }

  @override
  Future<void> saveCompletionDatesById(CompletionDatesByIdMap dates) async {
    completionDatesById = dates;
  }

  @override
  Future<void> saveColumnsByBookId(
      Map<int, List<ProgressColumn>> columns) async {
    columnsById = columns;
  }
}

BookDetails _singleItemBook() => BookDetails(
      id: 42,
      contentType: 'text',
      parts: const [BookPart(name: 'ראשי', startPage: 1, endPage: 1)],
    );

void main() {
  group('ShamorZachorProgressProvider', () {
    test('clearBookProgressById clears id-based progress', () async {
      final service = _FakeProgressService(
        progressById: {
          42: {
            '0': PageProgress(learn: true, review1: true),
          },
        },
        completionDatesById: {
          42: '2026-04-06',
        },
      );

      final provider = ShamorZachorProgressProvider(progressService: service);

      await provider.ensureLoaded();
      await provider.clearBookProgressById(42);

      expect(provider.getProgressForBookById(42), isEmpty);
      expect(provider.getCompletionDateSyncById(42), isNull);
      expect(service.progressById.containsKey(42), isFalse);
      expect(service.completionDatesById.containsKey(42), isFalse);
    });
  });

  group('ShamorZachorProgressProvider columns', () {
    ShamorZachorProgressProvider buildProvider(_FakeProgressService service) =>
        ShamorZachorProgressProvider(progressService: service);

    test('getColumnsForBook returns defaults when none configured', () async {
      final service =
          _FakeProgressService(progressById: {}, completionDatesById: {});
      final provider = buildProvider(service);
      await provider.ensureLoaded();

      expect(provider.getColumnsForBook(42), kDefaultProgressColumns);
    });

    test('addColumn appends a custom column', () async {
      final service =
          _FakeProgressService(progressById: {}, completionDatesById: {});
      final provider = buildProvider(service);
      await provider.ensureLoaded();

      await provider.addColumn(42, 'רש"י');
      final columns = provider.getColumnsForBook(42);

      expect(columns.length, kDefaultProgressColumns.length + 1);
      expect(columns.last.label, 'רש"י');
      expect(service.columnsById[42], isNotNull);
    });

    test('renameColumn updates only the label, keeping the id', () async {
      final service =
          _FakeProgressService(progressById: {}, completionDatesById: {});
      final provider = buildProvider(service);
      await provider.ensureLoaded();

      await provider.renameColumn(42, 'review1', 'תוספות');
      final columns = provider.getColumnsForBook(42);
      final renamed = columns.firstWhere((c) => c.id == 'review1');

      expect(renamed.label, 'תוספות');
    });

    test('removeColumn removes the column and clears its progress', () async {
      final service = _FakeProgressService(
        progressById: {
          42: {'0': PageProgress(learn: true, review1: true)},
        },
        completionDatesById: {},
      );
      final provider = buildProvider(service);
      await provider.ensureLoaded();

      await provider.removeColumn(42, 'review1');

      expect(provider.getColumnsForBook(42).any((c) => c.id == 'review1'),
          isFalse);
      expect(provider.getProgressForItemById(42, 0).review1, isFalse);
      expect(provider.getProgressForItemById(42, 0).learn, isTrue);
    });

    test('removeColumn keeps at least one column', () async {
      final service = _FakeProgressService(
        progressById: {},
        completionDatesById: {},
        columnsById: {
          42: const [ProgressColumn(id: 'learn', label: 'לימוד')],
        },
      );
      final provider = buildProvider(service);
      await provider.ensureLoaded();

      await provider.removeColumn(42, 'learn');

      expect(provider.getColumnsForBook(42).length, 1);
    });

    test('book is completed only when all columns are checked', () async {
      final service = _FakeProgressService(
        progressById: {
          42: {'0': PageProgress(learn: true)},
        },
        completionDatesById: {},
        columnsById: {
          42: const [
            ProgressColumn(id: 'learn', label: 'לימוד'),
            ProgressColumn(id: 'rashi', label: 'רש"י'),
          ],
        },
      );
      final provider = buildProvider(service);
      await provider.ensureLoaded();
      final book = _singleItemBook();

      expect(provider.isBookCompletedById(42, book), isFalse);

      await provider.updateProgressById(42, 0, 'rashi', true, book);

      expect(provider.isBookCompletedById(42, book), isTrue);
    });

    test('columns are independent - a later column can be marked first',
        () async {
      final service =
          _FakeProgressService(progressById: {}, completionDatesById: {});
      final provider = buildProvider(service);
      await provider.ensureLoaded();
      final book = _singleItemBook();

      // סימון "חזרה 1" ללא "לימוד" - לא אמור להיחסם
      await provider.updateProgressById(42, 0, 'review1', true, book);

      expect(provider.getProgressForItemById(42, 0).review1, isTrue);
      expect(provider.getProgressForItemById(42, 0).learn, isFalse);
    });
  });
}
