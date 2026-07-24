import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/migration/models/book.dart' as migration;
import 'package:otzaria/migration/models/category.dart';
import 'package:otzaria/migration/models/toc_entry.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/tools/shamor_zachor/providers/shamor_zachor_data_provider.dart';
import '../test_helpers/memory_cache_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late String dbPath;
  late Map<String, int> fixtureBookIds;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('sz_provider_test_');
    dbPath = '${tempDir.path}/seforim.db';
    final database = MyDatabase.withPath(dbPath);
    final repository = SeforimRepository(database);
    await repository.ensureInitialized();
    fixtureBookIds = await _insertFixture(repository);
    database.close();

    await Settings.init(cacheProvider: MemoryCacheProvider());
    await Settings.setValue<String>(
      SettingsRepository.keyLibraryPath,
      tempDir.path,
    );
    await Settings.setValue<String>(
      SettingsRepository.keyLibraryFolderName,
      '',
    );
    await Settings.setValue<String>(SettingsRepository.keyDbEffectivePath, '');
    await Settings.setValue<String>(
      'sz:tracked_books',
      '[${fixtureBookIds['ספר אישי']}]',
    );

    await SqliteDataProvider.instance.dispose();
  });

  tearDown(() async {
    await SqliteDataProvider.instance.dispose();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('loadAllData hydrates provider state from loader result', () async {
    final provider = ShamorZachorDataProvider(
      sqliteDataProvider: SqliteDataProvider.instance,
      categoryTreeLoader:
          ({
            required String dbPath,
            required List<int> trackedBookIds,
          }) async {
            expect(dbPath, endsWith('seforim.db'));
            expect(trackedBookIds, [fixtureBookIds['ספר אישי']]);
            return {
              'categories': [
                {
                  'name': 'תנ"ך',
                  'contentType': 'text',
                  'books': {
                    'בראשית': {
                      'contentType': 'text',
                      'id': 10,
                      'originalPageCount': 3,
                      'parts': [
                        {'name': 'ראשי', 'start': 1, 'end': 3},
                      ],
                      'sections': [
                        {
                          'id': '1000',
                          'title': 'פרק א',
                          'level': 1,
                          'startPage': 0,
                          'endPage': 2,
                        },
                      ],
                      'categoryPath': 'תנ"ך',
                    },
                  },
                  'defaultStartPage': 1,
                  'isCustom': false,
                  'sourceFile': 'db',
                  'schemaVersion': 1,
                },
              ],
              'relevantBookCount': 2,
              'allBookCount': 3,
              'categoryCount': 3,
            };
          },
    );

    await provider.loadAllData();

    expect(provider.error, isNull);
    expect(provider.isLoading, isFalse);
    expect(provider.hasData, isTrue);

    final category = provider.getCategory('תנ"ך');
    expect(category, isNotNull);
    expect(category!.contentType, 'text');

    final details = provider.getBookDetails('תנ"ך', 'בראשית');
    expect(details, isNotNull);
    expect(details!.id, 10);
    expect(details.categoryPath, 'תנ"ך');
    expect(details.sections, isNotNull);
    expect(details.sections, hasLength(1));
    expect(details.sections!.single.title, 'פרק א');
  });

  test(
    'loadAllData falls back to sqlite provider when loader throws',
    () async {
      final provider = ShamorZachorDataProvider(
        sqliteDataProvider: SqliteDataProvider.instance,
        categoryTreeLoader:
            ({
              required String dbPath,
              required List<int> trackedBookIds,
            }) async {
              throw Exception('worker failed');
            },
      );

      await provider.loadAllData();

      expect(provider.error, isNull);
      expect(provider.isLoading, isFalse);
      expect(provider.hasData, isTrue);

      final category = provider.getCategory('תנ"ך');
      expect(category, isNotNull);

      final details = provider.getBookDetails('תנ"ך', 'בראשית');
      expect(details, isNotNull);
      expect(details!.id, fixtureBookIds['בראשית']);
      expect(details.categoryPath, 'תנ"ך');

      expect(provider.getBookDetails('תנ"ך', 'ספר אישי'), isNotNull);
      expect(provider.getBookDetails('תנ"ך', 'לא במעקב'), isNull);
    },
  );

  group('addCustomBooks', () {
    ShamorZachorDataProvider buildProvider() => ShamorZachorDataProvider(
      sqliteDataProvider: SqliteDataProvider.instance,
      categoryTreeLoader:
          ({
            required String dbPath,
            required List<int> trackedBookIds,
          }) async {
            throw Exception('force fallback');
          },
    );

    test('מזהה לפי id מול המסד הרשמי גם כשהשם לא קיים', () async {
      final provider = buildProvider();
      await provider.loadAllData();

      final result = await provider.addCustomBooks([
        (
          id: fixtureBookIds['לא במעקב'],
          bookName: 'שם שלא קיים במסד',
          categoryId: null,
        ),
      ]);

      expect(result.added, 1);
      expect(result.failed, 0);
      expect(provider.trackedBookIds, contains(fixtureBookIds['לא במעקב']));
    });

    test('נופל לזיהוי לפי כותרת כאשר אין id', () async {
      final provider = buildProvider();
      await provider.loadAllData();

      final result = await provider.addCustomBooks([
        (id: null, bookName: 'לא במעקב', categoryId: null),
      ]);

      expect(result.added, 1);
      expect(provider.trackedBookIds, contains(fixtureBookIds['לא במעקב']));
    });

    test('ספר שלא נמצא נספר ככישלון', () async {
      final provider = buildProvider();
      await provider.loadAllData();

      final result = await provider.addCustomBooks([
        (id: null, bookName: 'ספר שאינו קיים', categoryId: null),
      ]);

      expect(result.added, 0);
      expect(result.failed, 1);
    });
  });
}

Future<Map<String, int>> _insertFixture(SeforimRepository repository) async {
  final tanachCategoryId = await repository.insertCategory(
    const Category(title: 'תנ"ך'),
  );
  final chumashCategoryId = await repository.insertCategory(
    Category(title: 'חומש', parentId: tanachCategoryId, level: 1),
  );
  await repository.insertCategory(
    const Category(title: 'ספרים מספריות חיצוניות'),
  );

  final sourceId = await repository.insertSource('test-source', -1);

  final bereshitId = await repository.insertBook(
    migration.Book(
      id: 0,
      categoryId: chumashCategoryId,
      sourceId: sourceId,
      title: 'בראשית',
      totalLines: 3,
      isBaseBook: true,
      fileType: 'txt',
    ),
  );
  final personalId = await repository.insertBook(
    migration.Book(
      id: 0,
      categoryId: chumashCategoryId,
      sourceId: sourceId,
      title: 'ספר אישי',
      totalLines: 2,
      isBaseBook: false,
      fileType: 'txt',
    ),
  );
  final untrackedId = await repository.insertBook(
    migration.Book(
      id: 0,
      categoryId: chumashCategoryId,
      sourceId: sourceId,
      title: 'לא במעקב',
      totalLines: 2,
      isBaseBook: false,
      fileType: 'txt',
    ),
  );

  await repository.insertTocEntry(
    TocEntry(
      id: 1000,
      bookId: bereshitId,
      text: 'פרק א',
      level: 1,
      lineIndex: 0,
      isLastChild: true,
      hasChildren: false,
    ),
  );

  return {
    'בראשית': bereshitId,
    'ספר אישי': personalId,
    'לא במעקב': untrackedId,
  };
}
