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
  ColumnCompletionDatesMap columnDatesById = {};

  @override
  Future<ColumnCompletionDatesMap> loadColumnCompletionDates() async =>
      columnDatesById;

  @override
  Future<void> saveColumnCompletionDates(
    ColumnCompletionDatesMap dates,
  ) async {
    columnDatesById = dates;
  }

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
  Future<void> saveCompletionDateById(int bookId, String date) async {
    completionDatesById[bookId] = date;
  }

  @override
  Future<void> saveColumnsByBookId(
    Map<int, List<ProgressColumn>> columns,
  ) async {
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
      final service = _FakeProgressService(
        progressById: {},
        completionDatesById: {},
      );
      final provider = buildProvider(service);
      await provider.ensureLoaded();

      expect(provider.getColumnsForBook(42), kDefaultProgressColumns);
    });

    test('addColumn appends a custom column', () async {
      final service = _FakeProgressService(
        progressById: {},
        completionDatesById: {},
      );
      final provider = buildProvider(service);
      await provider.ensureLoaded();

      await provider.addColumn(42, 'רש"י');
      final columns = provider.getColumnsForBook(42);

      expect(columns.length, kDefaultProgressColumns.length + 1);
      expect(columns.last.label, 'רש"י');
      expect(service.columnsById[42], isNotNull);
    });

    test('renameColumn updates only the label, keeping the id', () async {
      final service = _FakeProgressService(
        progressById: {},
        completionDatesById: {},
      );
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

      expect(
        provider.getColumnsForBook(42).any((c) => c.id == 'review1'),
        isFalse,
      );
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

    test(
      'columns are independent - a later column can be marked first',
      () async {
        final service = _FakeProgressService(
          progressById: {},
          completionDatesById: {},
        );
        final provider = buildProvider(service);
        await provider.ensureLoaded();
        final book = _singleItemBook();

        // סימון "חזרה 1" ללא "לימוד" - לא אמור להיחסם
        await provider.updateProgressById(42, 0, 'review1', true, book);

        expect(provider.getProgressForItemById(42, 0).review1, isTrue);
        expect(provider.getProgressForItemById(42, 0).learn, isFalse);
      },
    );
  });

  group('toggleRangeForColumnById', () {
    BookDetails tenPageBook() => BookDetails(
      id: 42,
      contentType: 'text',
      parts: const [BookPart(name: 'ראשי', startPage: 1, endPage: 10)],
    );

    Future<ShamorZachorProgressProvider> loadedProvider(
      _FakeProgressService service,
    ) async {
      final provider = ShamorZachorProgressProvider(progressService: service);
      await provider.ensureLoaded();
      return provider;
    }

    test('marks only the items inside the range', () async {
      final service = _FakeProgressService(
        progressById: {},
        completionDatesById: {},
      );
      final provider = await loadedProvider(service);

      await provider.toggleRangeForColumnById(
        42,
        tenPageBook(),
        'learn',
        2,
        5,
        true,
      );

      expect(provider.getProgressForItemById(42, 1).learn, isFalse);
      expect(provider.getProgressForItemById(42, 2).learn, isTrue);
      expect(provider.getProgressForItemById(42, 5).learn, isTrue);
      expect(provider.getProgressForItemById(42, 6).learn, isFalse);
    });

    test('reversed edges select the same range', () async {
      final service = _FakeProgressService(
        progressById: {},
        completionDatesById: {},
      );
      final provider = await loadedProvider(service);

      await provider.toggleRangeForColumnById(
        42,
        tenPageBook(),
        'learn',
        5,
        2,
        true,
      );

      expect(provider.getProgressForItemById(42, 2).learn, isTrue);
      expect(provider.getProgressForItemById(42, 5).learn, isTrue);
      expect(provider.getProgressForItemById(42, 6).learn, isFalse);
    });

    test('clears a range without touching other columns', () async {
      final service = _FakeProgressService(
        progressById: {
          42: {
            '2': PageProgress(learn: true, review1: true),
            '3': PageProgress(learn: true),
          },
        },
        completionDatesById: {},
      );
      final provider = await loadedProvider(service);

      await provider.toggleRangeForColumnById(
        42,
        tenPageBook(),
        'learn',
        2,
        3,
        false,
      );

      expect(provider.getProgressForItemById(42, 2).learn, isFalse);
      expect(provider.getProgressForItemById(42, 2).review1, isTrue);
      expect(provider.getProgressForItemById(42, 3).learn, isFalse);
    });

    test('ignores a column that is not configured for the book', () async {
      final service = _FakeProgressService(
        progressById: {},
        completionDatesById: {},
      );
      final provider = await loadedProvider(service);

      await provider.toggleRangeForColumnById(
        42,
        tenPageBook(),
        'unknown',
        0,
        3,
        true,
      );

      expect(provider.getProgressForBookById(42), isEmpty);
    });

    test('marking the full range records the completion date', () async {
      final service = _FakeProgressService(
        progressById: {},
        completionDatesById: {},
        columnsById: {
          42: const [ProgressColumn(id: 'learn', label: 'לימוד')],
        },
      );
      final provider = await loadedProvider(service);

      await provider.toggleRangeForColumnById(
        42,
        tenPageBook(),
        'learn',
        0,
        9,
        true,
      );

      expect(provider.getCompletionDateSyncById(42), isNotNull);
    });
  });
  group('column completion dates', () {
    BookDetails tenPageBook() => BookDetails(
      id: 42,
      contentType: 'text',
      parts: const [BookPart(name: 'ראשי', startPage: 1, endPage: 10)],
    );

    _FakeProgressService twoColumns() => _FakeProgressService(
      progressById: {},
      completionDatesById: {},
      columnsById: {
        42: const [
          ProgressColumn(id: 'learn', label: 'לימוד'),
          ProgressColumn(id: 'review1', label: 'חזרה 1'),
        ],
      },
    );

    Future<ShamorZachorProgressProvider> loaded(
      _FakeProgressService service,
    ) async {
      final provider = ShamorZachorProgressProvider(progressService: service);
      addTearDown(provider.dispose);
      await provider.ensureLoaded();
      return provider;
    }

    test('a column gets its own date the moment it becomes complete', () async {
      final service = twoColumns();
      final provider = await loaded(service);

      await provider.toggleSelectAllForColumnById(
        42,
        tenPageBook(),
        'learn',
        true,
      );

      expect(provider.getColumnCompletionDate(42, 'learn'), isNotNull);
      expect(provider.getColumnCompletionDate(42, 'review1'), isNull);
      expect(provider.getCompletionDateSyncById(42), isNull);
      expect(service.columnDatesById[42], contains('learn'));
    });

    test('a partly marked column has no date', () async {
      final provider = await loaded(twoColumns());

      await provider.toggleRangeForColumnById(
        42,
        tenPageBook(),
        'learn',
        0,
        8,
        true,
      );

      expect(provider.getColumnCompletionDate(42, 'learn'), isNull);
    });

    test(
      'single-item marking completes the column and unmarking drops it',
      () async {
        final service = twoColumns();
        final provider = await loaded(service);
        final book = tenPageBook();

        for (var i = 0; i < 10; i++) {
          await provider.updateProgressById(42, i, 'learn', true, book);
        }
        expect(provider.getColumnCompletionDate(42, 'learn'), isNotNull);

        await provider.updateProgressById(42, 3, 'learn', false, book);
        expect(provider.getColumnCompletionDate(42, 'learn'), isNull);
        expect(service.columnDatesById, isEmpty);
      },
    );

    test(
      're-marking an already complete column keeps the original date',
      () async {
        final service = twoColumns()
          ..progressById = {
            42: {
              for (var i = 0; i < 10; i++) '$i': PageProgress(learn: true),
            },
          }
          ..columnDatesById = {
            42: {'learn': '2025-03-10T09:00:00.000'},
          };
        final provider = await loaded(service);

        await provider.toggleRangeForColumnById(
          42,
          tenPageBook(),
          'learn',
          0,
          4,
          true,
        );

        expect(
          provider.getColumnCompletionDate(42, 'learn'),
          DateTime.parse('2025-03-10T09:00:00.000'),
        );
      },
    );

    test('removing a column and clearing the book drop their dates', () async {
      final service = twoColumns();
      final provider = await loaded(service);
      final book = tenPageBook();
      await provider.toggleSelectAllForColumnById(42, book, 'learn', true);
      await provider.toggleSelectAllForColumnById(42, book, 'review1', true);

      await provider.removeColumn(42, 'review1');
      expect(provider.getColumnCompletionDate(42, 'review1'), isNull);
      expect(provider.getColumnCompletionDate(42, 'learn'), isNotNull);

      await provider.clearBookProgressById(42);
      expect(provider.getColumnCompletionDate(42, 'learn'), isNull);
      expect(service.columnDatesById.containsKey(42), isFalse);
    });
  });
}
