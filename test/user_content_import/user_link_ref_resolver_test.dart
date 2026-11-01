import 'dart:io';

import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/models/link_types.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/user_content_import/models/user_import_models.dart';
import 'package:otzaria/user_content_import/repository/user_content_repository.dart';
import 'package:otzaria/user_content_import/services/user_content_importer.dart';
import 'package:otzaria/user_content_import/services/user_link_ref_resolver.dart';
import 'package:path/path.dart' as p;

import '../test_helpers/memory_cache_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory directory;
  late MyDatabase userDb;
  late MyDatabase officialDb;
  late SeforimRepository userRepository;
  late SeforimRepository officialRepository;

  Future<void> addBook(MyDatabase db, String title) async {
    final raw = await db.database;
    raw.execute('PRAGMA foreign_keys = OFF');
    raw.execute("INSERT OR IGNORE INTO source (id, name) VALUES (1, 'test')");
    raw.execute(
      'INSERT INTO book (categoryId, sourceId, title, totalLines) '
      'VALUES (1, 1, ?, 10)',
      [title],
    );
  }

  Future<({bool isUserBook, int? categoryId, int totalLines})?> locate(
    String title,
  ) => locateUserLinkBookInRepositories(
    title,
    userRepository: userRepository,
    officialRepository: officialRepository,
  );

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('otzaria_link_locator');
    userDb = MyDatabase.withPath(p.join(directory.path, 'user.db'));
    officialDb = MyDatabase.withPath(p.join(directory.path, 'official.db'));
    userRepository = SeforimRepository(userDb);
    officialRepository = SeforimRepository(officialDb);
  });

  tearDown(() async {
    userDb.close();
    officialDb.close();
    await directory.delete(recursive: true);
  });

  test('כותרת בשני המסדים נדחית במקום לבחור ספר שרירותי', () async {
    await addBook(userDb, 'בסיס');
    await addBook(userDb, 'יעד');
    await addBook(officialDb, 'יעד');

    await expectLater(
      locate('יעד'),
      throwsA(isA<AmbiguousUserLinkBookException>()),
    );

    final result = await UserContentImporter.importContents(
      const [
        ImportedFile(
          name: 'בסיס_links.json',
          content:
              '[{"line_index_1": 1, "line_index_2": 2, '
              '"path_2": "יעד.txt"}]',
        ),
      ],
      userDb,
      locateBook: locate,
    );
    expect(result.errors.single, contains('גם בספרייה האישית וגם ברשמית'));
    expect(result.linksApplied, 0);
    expect(
      await UserContentRepository(userDb).forwardUserLinks(
        'בסיס',
        sourceIsUserBook: true,
      ),
      isEmpty,
    );
  });

  test('גם ספר בסיס עמום נדחה לפני כתיבה', () async {
    await addBook(userDb, 'בסיס');
    await addBook(officialDb, 'בסיס');
    await addBook(userDb, 'יעד');

    final result = await UserContentImporter.importContents(
      const [
        ImportedFile(
          name: 'בסיס_links.json',
          content:
              '[{"line_index_1": 1, "line_index_2": 2, '
              '"path_2": "יעד.txt"}]',
        ),
      ],
      userDb,
      locateBook: locate,
    );
    expect(result.errors.single, contains('ספר הבסיס'));
    expect(result.errors.single, contains('גם בספרייה האישית וגם ברשמית'));
    expect(result.linksApplied, 0);
  });

  test('ספרייה אישית עצמאית ללא מסד רשמי עדיין נקלטת', () async {
    await addBook(userDb, 'בסיס');
    await addBook(userDb, 'יעד');
    final result = await UserContentImporter.importContents(
      const [
        ImportedFile(
          name: 'בסיס_links.json',
          content:
              '[{"line_index_1": 1, "line_index_2": 2, '
              '"path_2": "יעד.txt"}]',
        ),
      ],
      userDb,
      locateBook: (title) => locateUserLinkBookInRepositories(
        title,
        userRepository: userRepository,
        officialRepository: null,
      ),
    );
    expect(result.errors, isEmpty);
    expect(result.linksApplied, 1);
    final links = await UserContentRepository(userDb).forwardUserLinks(
      'בסיס',
      sourceIsUserBook: true,
    );
    expect(links.single.targetIsUserBook, isTrue);
    expect(links.single.targetTitle, 'יעד');
  });

  test('native LINKER הפוך נשמר כ־COMMENTARY מהבסיס הרשמי למפרש', () async {
    await addBook(userDb, 'מפרש');
    await addBook(officialDb, 'בסיס');

    final result = await UserContentImporter.importContents(
      const [
        ImportedFile(
          name: 'מפרש_links.json',
          content:
              '[{"line_index_1": 2, "line_index_2": 3, '
              '"path_2": "בסיס.txt", "Conection Type": "linker"}]',
        ),
      ],
      userDb,
      locateBook: locate,
    );
    expect(result.errors, isEmpty);
    expect(result.linksApplied, 1);
    final links = await UserContentRepository(userDb).forwardUserLinks(
      'בסיס',
      sourceIsUserBook: false,
    );
    expect(links.single.connectionType, LinkTypes.commentary);
    expect(links.single.targetTitle, 'מפרש');
    expect(links.single.targetIsUserBook, isTrue);
    expect(links.single.sourceLineIndex, 2);
    expect(links.single.targetLineIndex, 1);
  });

  test('Settings מאותחל ללא seforim.db: ייבוא אישי עצמאי עובד', () async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
    await Settings.setValue(SettingsRepository.keyLibraryPath, directory.path);
    await addBook(userDb, 'בסיס');
    await addBook(userDb, 'יעד');

    final result = await UserContentImporter.importContents(
      const [
        ImportedFile(
          name: 'בסיס_links.json',
          content:
              '[{"line_index_1": 1, "line_index_2": 2, '
              '"path_2": "יעד.txt"}]',
        ),
      ],
      userDb,
      locateBook: userLinkResolversFor(userDb).locateBook,
    );
    expect(result.errors, isEmpty);
    expect(result.linksApplied, 1);
    expect(SqliteDataProvider.instance.isInitialized, isFalse);
  });

  test('מסד רשמי פגום: הייבוא נדחה בלי שיוך משוער', () async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
    await Settings.setValue(SettingsRepository.keyLibraryPath, directory.path);
    File(p.join(directory.path, 'seforim.db')).writeAsStringSync('invalid');
    await addBook(userDb, 'בסיס');
    await addBook(userDb, 'יעד');

    final result = await UserContentImporter.importContents(
      const [
        ImportedFile(
          name: 'בסיס_links.json',
          content:
              '[{"line_index_1": 1, "line_index_2": 2, '
              '"path_2": "יעד.txt"}]',
        ),
      ],
      userDb,
      locateBook: userLinkResolversFor(userDb).locateBook,
    );
    expect(result.errors.single, contains('לא ניתן לבדוק את הספרייה הרשמית'));
    expect(result.linksApplied, 0);
    expect(
      await UserContentRepository(userDb).forwardUserLinks(
        'בסיס',
        sourceIsUserBook: true,
      ),
      isEmpty,
    );
  });

  test('כשל המסד הרשמי נזרק רק כשפונים אליו', () async {
    await addBook(userDb, 'בסיס');
    await addBook(userDb, 'יעד');
    final resolvers = userLinkResolversFor(
      userDb,
      officialError: Exception('corrupt'),
    );
    Future<List<String>> errorsOf(ImportedFile file) async =>
        (await UserContentImporter.ingestContents(
          [file],
          userDb,
          resolveRef: resolvers.resolveRef,
          sourceExists: resolvers.sourceExists,
          locateBook: resolvers.locateBook,
        )).errors;

    expect(
      (await errorsOf(
        const ImportedFile(
          name: 'בסיס_links.json',
          content:
              '[{"line_index_1": 1, "line_index_2": 2, "path_2": "יעד.txt"}]',
        ),
      )).single,
      contains('לא ניתן לבדוק את הספרייה הרשמית'),
    );
    expect(
      await errorsOf(
        const ImportedFile(name: 'דורות.csv', content: 'ספר,דור\n'),
      ),
      isEmpty,
    );
  });
}
