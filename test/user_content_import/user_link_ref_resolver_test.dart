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

  Future<void> addBook(
    MyDatabase db,
    String title, {
    bool isBaseBook = false,
  }) async {
    final raw = await db.database;
    raw.execute('PRAGMA foreign_keys = OFF');
    raw.execute("INSERT OR IGNORE INTO source (id, name) VALUES (1, 'test')");
    raw.execute(
      'INSERT INTO book (categoryId, sourceId, title, totalLines, isBaseBook) '
      'VALUES (1, 1, ?, 10, ?)',
      [title, isBaseBook ? 1 : 0],
    );
  }

  Future<LocatedUserLinkBook?> locate(
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
    expect(result.errors.single, contains('ביותר ממקור אחד'));
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
    expect(result.errors.single, contains('ביותר ממקור אחד'));
    expect(result.linksApplied, 0);
  });

  // #5222: ספר במסד מצורף בשם של ספר רשמי — native אינו יכול לדעת לאיזה מהם
  // התכוון הקובץ, ולכן אסור לו להיקשר בשקט לרשמי.
  for (final baseCollides in [true, false]) {
    test(
      'native דוחה כותרת שקיימת גם במסד מצורף (בסיס: $baseCollides)',
      () async {
        await addBook(userDb, 'אישי');
        await addBook(officialDb, 'רשמי');
        final attachedDb = MyDatabase.withPath(
          p.join(directory.path, 'attached.db'),
        );
        await addBook(attachedDb, 'רשמי');
        attachedDb.close();
        final attached = AttachedLinkBooks.open([
          (
            slug: 'attached',
            path: attachedDb.path,
            immutable: false,
            visible: true,
          ),
        ]);
        addTearDown(attached.close);

        final result = await UserContentImporter.importContents(
          [
            ImportedFile(
              name: '${baseCollides ? 'רשמי' : 'אישי'}_links.json',
              content:
                  '[{"line_index_1": 1, "line_index_2": 2, '
                  '"path_2": "${baseCollides ? 'אישי' : 'רשמי'}.txt"}]',
            ),
          ],
          userDb,
          locateBook: locate,
          attachedBooks: attached,
        );
        expect(result.errors.single, contains('ביותר ממקור אחד'));
        expect(result.linksApplied, 0);
      },
    );
  }

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

  test('native מאחד צמד קישורים של ספר בסיס רשמי ששמו כולל על', () async {
    const base = 'ילקוט שמעוני על התורה';
    const commentary = 'ביאור אישי';
    await addBook(officialDb, base, isBaseBook: true);
    await addBook(userDb, commentary);

    final result = await UserContentImporter.importContents(
      const [
        ImportedFile(
          name: '${base}_links.json',
          content:
              '[{"line_index_1": 3, "line_index_2": 5, "start": 2, '
              '"path_2": "$commentary.txt", "Conection Type": "commentary"}]',
        ),
        ImportedFile(
          name: '${commentary}_links.json',
          content:
              '[{"line_index_1": 5, "line_index_2": 3, '
              '"path_2": "$base.txt", "Conection Type": "commentary"}]',
        ),
      ],
      userDb,
      locateBook: locate,
    );

    expect(result.errors, isEmpty);
    expect(result.linksApplied, 1);
    final repo = UserContentRepository(userDb);
    final links = await repo.forwardUserLinks(base, sourceIsUserBook: false);
    expect(links.single.targetTitle, commentary);
    expect(links.single.anchorStart, 2);
    expect(
      await repo.forwardUserLinks(commentary, sourceIsUserBook: true),
      isEmpty,
    );
  });

  for (final isAttached in [false, true]) {
    test('native משאיר כיוון אל פירוש ללא על (מצורף: $isAttached)', () async {
      const source = 'ביאור אישי';
      const target = 'יכין מגילה';
      await addBook(userDb, source);
      await addBook(officialDb, target);
      final raw = await officialDb.database;
      raw.execute('ALTER TABLE book ADD COLUMN dependenceType TEXT');
      raw.execute('UPDATE book SET dependenceType = ?', ['commentary']);
      final attached = isAttached
          ? AttachedLinkBooks.open([
              (
                slug: 'attached',
                path: officialDb.path,
                immutable: false,
                visible: true,
              ),
            ])
          : AttachedLinkBooks.none;
      if (isAttached) addTearDown(attached.close);

      final result = await UserContentImporter.importContents(
        const [
          ImportedFile(
            name: '${source}_links.json',
            content:
                '[{"line_index_1": 5, "line_index_2": 3, '
                '"path_2": "$target.txt", "Conection Type": "commentary"}]',
          ),
        ],
        userDb,
        locateBook: (title) => locateUserLinkBookInRepositories(
          title,
          userRepository: userRepository,
          officialRepository: isAttached ? null : officialRepository,
        ),
        attachedBooks: attached,
      );

      expect(result.errors, isEmpty);
      expect(result.linksApplied, 1);
      final repo = UserContentRepository(userDb);
      final links = await repo.forwardUserLinks(source, sourceIsUserBook: true);
      expect(links.single.targetTitle, target);
      expect(links.single.targetDb, isAttached ? 'attached' : null);
      expect(
        await repo.forwardUserLinks(
          target,
          sourceIsUserBook: false,
          sourceDb: isAttached ? 'attached' : null,
        ),
        isEmpty,
      );
    });
  }

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

  group('כותרת עם גרשיים ושם קובץ בלעדיהם (issue #4512)', () {
    const riaf = 'רי"ף שבת';
    const commentary = 'ביאור אישי';
    const nativeRow =
        '[{"line_index_1": 3, "line_index_2": 5, '
        '"path_2": "$commentary.txt", "Conection Type": "commentary"}]';

    Future<UserImportResult> importNative(
      String name,
      String content, {
      AttachedLinkBooks? attached,
    }) => UserContentImporter.importContents(
      [ImportedFile(name: name, content: content)],
      userDb,
      locateBook: locate,
      attachedBooks: attached,
    );

    for (final fileTitle in ['ריף שבת', 'רי״ף שבת']) {
      test('בסיס רשמי משם הקובץ "$fileTitle"', () async {
        await addBook(officialDb, riaf, isBaseBook: true);
        await addBook(userDb, commentary);

        final result = await importNative('${fileTitle}_links.json', nativeRow);

        expect(result.errors, isEmpty);
        expect(result.linksApplied, 1);
        final links = await UserContentRepository(
          userDb,
        ).forwardUserLinks(riaf, sourceIsUserBook: false);
        expect(links.single.targetTitle, commentary);
        expect(links.single.sourceLineIndex, 2);
      });
    }

    test('יעד ב-path_2 עם ״ מול " במסד', () async {
      await addBook(userDb, commentary);
      await addBook(officialDb, 'רש"י על שבת');

      final result = await importNative(
        '${commentary}_links.json',
        '[{"line_index_1": 1, "line_index_2": 2, '
            '"path_2": "רש״י על שבת.txt"}]',
      );

      expect(result.errors, isEmpty);
      final links = await UserContentRepository(
        userDb,
      ).forwardUserLinks(commentary, sourceIsUserBook: true);
      expect(links.single.targetTitle, 'רש"י על שבת');
      expect(links.single.targetIsUserBook, isFalse);
    });

    test('הכותרת עצמה במסד מצורף גוברת על כתיב קרוב ברשמי', () async {
      await addBook(officialDb, riaf, isBaseBook: true);
      await addBook(userDb, commentary);
      final attachedDb = MyDatabase.withPath(
        p.join(directory.path, 'attached.db'),
      );
      addTearDown(attachedDb.close);
      await addBook(attachedDb, 'ריף שבת', isBaseBook: true);
      final attached = AttachedLinkBooks.open([
        (
          slug: 'attached',
          path: attachedDb.path,
          immutable: false,
          visible: true,
        ),
      ]);
      addTearDown(attached.close);

      final result = await importNative(
        'ריף שבת_links.json',
        nativeRow,
        attached: attached,
      );

      expect(result.errors, isEmpty);
      final links = await UserContentRepository(userDb).forwardUserLinks(
        'ריף שבת',
        sourceIsUserBook: false,
        sourceDb: 'attached',
      );
      expect(links.single.targetTitle, commentary);
    });

    test('כתיבים קרובים ברשמי ובמצורף אינם מצמידים לספר שרירותי', () async {
      await addBook(officialDb, riaf, isBaseBook: true);
      await addBook(userDb, commentary);
      final attachedDb = MyDatabase.withPath(
        p.join(directory.path, 'other.db'),
      );
      addTearDown(attachedDb.close);
      await addBook(attachedDb, 'רי״ף שבת', isBaseBook: true);
      final attached = AttachedLinkBooks.open([
        (
          slug: 'attached',
          path: attachedDb.path,
          immutable: false,
          visible: true,
        ),
      ]);
      addTearDown(attached.close);

      final result = await importNative(
        'ריף שבת_links.json',
        nativeRow,
        attached: attached,
      );

      expect(result.errors.single, contains('יותר מספר אחד'));
      expect(result.linksApplied, 0);
    });

    test('הסרת סוגריים או רווחים אינה תחליף לגרשיים', () async {
      await addBook(officialDb, riaf, isBaseBook: true);
      await addBook(userDb, commentary);

      for (final title in ['ריף <שבת>', 'ריף  שבת']) {
        final result = await importNative('${title}_links.json', nativeRow);
        expect(result.errors.single, contains('לא נמצא בספרייה'));
        expect(result.linksApplied, 0);
      }
    });

    test('שני כתיבים שמתנרמלים לאותה כותרת: לא נמצא, בלי חריגה', () async {
      await addBook(userDb, riaf);
      await addBook(officialDb, 'רי״ף שבת');
      await addBook(officialDb, "רי'ף שבת");
      await addBook(userDb, commentary);

      expect(await locate('ריף שבת'), isNull);
      final result = await importNative('ריף שבת_links.json', nativeRow);
      expect(result.errors.single, contains('לא נמצא בספרייה'));
      expect(result.linksApplied, 0);
    });
  });
}
