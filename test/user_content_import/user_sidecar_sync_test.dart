import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/user_content_import/models/user_import_models.dart';
import 'package:otzaria/user_content_import/repository/user_content_repository.dart';
import 'package:otzaria/user_content_import/services/user_content_importer.dart';
import 'package:otzaria/user_content_import/services/user_sidecar_sync.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import '../helpers/seforim_fixture_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Directory folder;
  late MyDatabase db;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('otzaria_sidecar');
    folder = Directory(p.join(tempDir.path, 'ספרים'))..createSync();
    db = MyDatabase.withPath(p.join(tempDir.path, 'user_books.db'));
    final raw = await db.database;
    raw.execute("INSERT INTO source (name) VALUES ('external')");
  });

  tearDown(() async {
    db.close();
    await tempDir.delete(recursive: true);
  });

  /// יוצר קובץ ספר בתיקייה ורשומת ספר תואמת (כמו אחרי סריקה).
  Future<int> addBook(String fileName, String content) async {
    final path = p.join(folder.path, fileName);
    File(path).writeAsStringSync(content);
    final raw = await db.database;
    raw.execute(
      'INSERT INTO book (categoryId, sourceId, title, filePath, fileType, lastModified) '
      'VALUES (1, 1, ?, ?, ?, 1)',
      [
        p.basenameWithoutExtension(fileName),
        path,
        p.extension(fileName).substring(1),
      ],
    );
    return raw.lastInsertRowId;
  }

  File writeSidecar(String name, String content) =>
      File(p.join(folder.path, name))..writeAsStringSync(content);

  Future<List<Map<String, Object?>>> headingRows(int bookId) async {
    final raw = await db.database;
    return raw.select(
      'SELECT s.heTitle, s.key, e.text, e.lineIndex, e.parentId '
      'FROM user_alt_toc_structure s '
      'JOIN user_alt_toc_entry e ON e.structureId = s.id '
      'WHERE s.bookId = ? ORDER BY e.id',
      [bookId],
    ).toList();
  }

  test('קובץ כותרות של ספר נקלט לפי שם הקובץ', () async {
    final bookId = await addBook('משנה.txt', 'הקדמה\nפרק ראשון\nפרק שני');
    writeSidecar(
      'משנה.כותרות.csv',
      'מבנה,כותרת,שורה,טקסט\nסימנים,סימן א,2,\nסימנים,סימן ב,,פרק שני\n',
    );

    final errors = await UserSidecarSync.applyForFolder(
      userDb: db,
      folderPath: folder.path,
    );

    expect(errors, isEmpty);
    final rows = await headingRows(bookId);
    expect(rows.map((r) => r['text']), ['סימן א', 'סימן ב']);
    expect(rows.map((r) => r['lineIndex']), [1, 2]);
    expect(rows.first['key'], 'Simanim');
  });

  test('קובץ כותרות רוחבי מזהה ספרים לפי עמודת ספר', () async {
    final first = await addBook('א.txt', 'שורה\nשורה');
    final second = await addBook('ב.txt', 'שורה\nשורה');
    writeSidecar('כותרות.csv', 'ספר,כותרת,שורה\nא,ראשון,1\nב,שני,2\n');

    final errors = await UserSidecarSync.applyForFolder(
      userDb: db,
      folderPath: folder.path,
    );

    expect(errors, isEmpty);
    expect((await headingRows(first)).single['text'], 'ראשון');
    expect((await headingRows(second)).single['lineIndex'], 1);
  });

  test('עריכת הקובץ מחליפה את הכותרות, ומחיקתו מסירה אותן', () async {
    final bookId = await addBook('ספר.txt', 'א\nב\nג');
    final sidecar = writeSidecar('ספר.כותרות.csv', 'כותרת,שורה\nישן,1\n');
    await UserSidecarSync.applyForFolder(userDb: db, folderPath: folder.path);

    sidecar.writeAsStringSync('כותרת,שורה\nחדש,3\nנוסף,2\n');
    sidecar.setLastModifiedSync(DateTime.now().add(const Duration(hours: 1)));
    await UserSidecarSync.applyForFolder(userDb: db, folderPath: folder.path);
    expect((await headingRows(bookId)).map((r) => r['text']), ['חדש', 'נוסף']);

    sidecar.deleteSync();
    await UserSidecarSync.applyForFolder(userDb: db, folderPath: folder.path);
    expect(await headingRows(bookId), isEmpty);
  });

  test(
    'סריקת תיקייה אינה מוחקת כותרות של תיקייה אחות ששמה מתחיל כמותה',
    () async {
      final sibling = Directory(p.join(tempDir.path, 'ספרים חדשים'))
        ..createSync();
      final bookPath = p.join(sibling.path, 'ספר.txt');
      File(bookPath).writeAsStringSync('א\nב');
      final raw = await db.database;
      raw.execute(
        'INSERT INTO book (categoryId, sourceId, title, filePath, fileType, lastModified) '
        "VALUES (1, 1, 'ספר', ?, 'txt', 1)",
        [bookPath],
      );
      final bookId = raw.lastInsertRowId;
      File(
        p.join(sibling.path, 'ספר.כותרות.csv'),
      ).writeAsStringSync('כותרת,שורה\nפרק,1\n');
      await UserSidecarSync.applyForFolder(
        userDb: db,
        folderPath: sibling.path,
      );

      await UserSidecarSync.applyForFolder(userDb: db, folderPath: folder.path);

      expect((await headingRows(bookId)).single['text'], 'פרק');
    },
  );

  test('קבצים נלווים נמצאים גם כשנתיב התיקייה מסתיים במפריד', () async {
    final repo = UserContentRepository(db);
    final inside = p.join(folder.path, 'כותרות.csv');
    await repo.setSidecarSignature(inside, 'x');

    expect(await repo.trackedSidecarsUnder('${folder.path}${p.separator}'), [
      inside,
    ]);
  });

  test('שגיאה בקובץ מדווחת עם שם הקובץ', () async {
    await addBook('ספר.txt', 'שורה אחת');
    writeSidecar('ספר.כותרות.csv', 'כותרת,שורה\nרחוקה,50\n');

    final errors = await UserSidecarSync.applyForFolder(
      userDb: db,
      folderPath: folder.path,
    );

    expect(errors.single, contains('ספר.כותרות.csv'));
    expect(errors.single, contains('חורגת מגבולות הספר'));
  });

  test('כותרות לספר PDF נדחות', () async {
    await addBook('סרוק.pdf', '%PDF-1.4');
    writeSidecar('סרוק.כותרות.csv', 'כותרת,שורה\nפרק,1\n');

    final errors = await UserSidecarSync.applyForFolder(
      userDb: db,
      folderPath: folder.path,
    );

    expect(errors.single, contains('רק בספרי טקסט'));
  });

  test('קובץ גרסאות מקשר קבצים לפי נתיב יחסי', () async {
    final primary = await addBook('רשבא.txt', 'א');
    final version = await addBook('רשבא קוק.txt', 'א');
    writeSidecar(
      'גרסאות.csv',
      'ראשי,גרסה,שם\nרשבא.txt,רשבא קוק.txt,מוסד הרב קוק\n',
    );

    final errors = await UserSidecarSync.applyForFolder(
      userDb: db,
      folderPath: folder.path,
    );

    expect(errors, isEmpty);
    final raw = await db.database;
    final rows = raw.select('SELECT * FROM user_book_version').toList();
    expect(rows.single['primaryBookId'], primary);
    expect(rows.single['versionBookId'], version);
    expect(rows.single['versionTitle'], 'מוסד הרב קוק');
  });

  test('ייבוא מההגדרות קולט כותרות וגרסאות לפי כותרות ספרים', () async {
    final primary = await addBook('ראשי.txt', 'א\nב\nג');
    final version = await addBook('משני.txt', 'א');
    final headings = writeSidecar(
      'import-כותרות.csv',
      'ספר,מבנה,כותרת,שורה\nראשי,נושאים,הלכות א,3\n',
    );
    final headingsPath = p.join(tempDir.path, 'כותרות.csv');
    headings.renameSync(headingsPath);
    final versionsPath = p.join(tempDir.path, 'גרסאות.csv');
    File(versionsPath).writeAsStringSync('ראשי,גרסה,שם\nראשי,משני,דפוס ישן\n');

    final result = await UserContentImporter.importFiles([
      headingsPath,
      versionsPath,
    ], db);

    expect(result.errors, isEmpty);
    expect(result.headingsApplied, 1);
    expect(result.versionsApplied, 1);
    final rows = await headingRows(primary);
    expect(rows.single['key'], 'Topic');
    expect(rows.single['lineIndex'], 2);
    final raw = await db.database;
    expect(
      raw
          .select('SELECT versionBookId FROM user_book_version')
          .single['versionBookId'],
      version,
    );

    await UserContentRepository(db).clearAllUserContent();
    expect(await headingRows(primary), isEmpty);
  });

  group('קובצי קישורים בתיקייה', () {
    /// קובץ קישורים בפורמט ה-native של אוצריא, כפי שהוא יושב בתיקיית links.
    void writeNativeLinks(String baseTitle, String commentator, int line) =>
        writeSidecar(
          '${baseTitle}_links.json',
          '[{"line_index_1": $line, "line_index_2": 1, '
              '"heRef_2": "$commentator א", '
              '"path_2": "$commentator.txt", '
              '"Conection Type": "linker"}]',
        );

    Future<List<UserLinkRecord>> linksOf(String title) =>
        UserContentRepository(db).forwardUserLinks(
          title,
          sourceIsUserBook: true,
        );

    test('קובץ _links.json בתיקייה נקלט אוטומטית בסריקה', () async {
      await addBook('מגילה.txt', 'א\nב\nג');
      await addBook('מפרש.txt', 'פירוש');
      writeNativeLinks('מגילה', 'מפרש', 2);

      final errors = await UserSidecarSync.applyForFolder(
        userDb: db,
        folderPath: folder.path,
      );
      expect(errors, isEmpty);

      final stored = await linksOf('מגילה');
      expect(stored.single.targetTitle, 'מפרש');
      expect(stored.single.sourceLineIndex, 1);
      // LINKER נשמר כמפרש, כך שהוא מופיע בפאנל המפרשים של הבסיס.
      expect(stored.single.connectionType, 'COMMENTARY');
    });

    test('קישור מספר רשמי נקלט עם המאגר המקומי של סנכרון הרקע', () async {
      final officialDb = MyDatabase.withPath(
        p.join(tempDir.path, 'seforim.db'),
      );
      try {
        final official = await officialDb.database;
        official.execute("INSERT INTO source (name) VALUES ('official')");
        official.execute(
          'INSERT INTO book (categoryId, sourceId, title, totalLines) '
          'VALUES (1, 1, ?, 3)',
          ['מגילה רשמית'],
        );
        await addBook('מפרש.txt', 'פירוש');
        writeNativeLinks('מגילה רשמית', 'מפרש', 2);

        final errors = await UserSidecarSync.applyForFolder(
          userDb: db,
          folderPath: folder.path,
          officialRepository: SeforimRepository(officialDb),
        );

        expect(errors, isEmpty);
        final stored = await UserContentRepository(db).forwardUserLinks(
          'מגילה רשמית',
          sourceIsUserBook: false,
        );
        expect(stored, hasLength(1));
        expect(stored.single.sourceLineIndex, 1);
        expect(stored.single.targetTitle, 'מפרש');
        expect(stored.single.targetIsUserBook, isTrue);
      } finally {
        officialDb.close();
      }
    });

    test(
      'כשל בפתיחת המסד הרשמי דוחה את הקובץ ומשאיר אותו לסריקה הבאה',
      () async {
        await addBook('מפרש.txt', 'פירוש');
        final sidecar = writeSidecar(
          'מגילה רשמית_links.json',
          '[{"line_index_1": 2, "line_index_2": 1, '
              '"path_2": "מפרש.txt", "Conection Type": "linker"}]',
        );

        final errors = await UserSidecarSync.applyForFolder(
          userDb: db,
          folderPath: folder.path,
          officialError: Exception('seforim.db פגום'),
        );

        expect(errors, [
          'מגילה רשמית_links.json: לא ניתן לבדוק את הספרייה הרשמית',
        ]);
        final repo = UserContentRepository(db);
        expect(await repo.sidecarSignature(sidecar.path), isNull);
        expect(
          await repo.forwardUserLinks('מגילה רשמית', sourceIsUserBook: false),
          isEmpty,
        );
      },
    );

    test('שינוי במסד הרשמי מבטל חתימת קובץ קישורים שלא השתנה', () async {
      final officialPath = p.join(tempDir.path, 'seforim.db');
      final officialDb = MyDatabase.withPath(officialPath);
      try {
        final official = await officialDb.database;
        official.execute("INSERT INTO source (name) VALUES ('official')");
        official.execute(
          'INSERT INTO book (categoryId, sourceId, title, totalLines) '
          'VALUES (1, 1, ?, 3)',
          ['מגילה רשמית'],
        );
        await addBook('מפרש.txt', 'פירוש');
        final sidecar = writeSidecar(
          'מגילה רשמית_links.json',
          '[{"line_index_1": 2, "line_index_2": 1, '
              '"path_2": "מפרש.txt", "Conection Type": "linker"}]',
        );
        final repository = SeforimRepository(officialDb);
        Future<List<String>> scan() => UserSidecarSync.applyForFolder(
          userDb: db,
          folderPath: folder.path,
          officialRepository: repository,
        );
        expect(await scan(), isEmpty);
        final repo = UserContentRepository(db);
        final oldSignature = await repo.sidecarSignature(sidecar.path);

        final userRaw = await db.database;
        userRaw.execute('''
          CREATE TEMP TRIGGER fail_reimport BEFORE INSERT ON user_link
          BEGIN SELECT RAISE(ABORT, 'unchanged link was reimported'); END
        ''');
        expect(await scan(), isEmpty);
        userRaw.execute('DROP TRIGGER fail_reimport');

        official.execute(
          'UPDATE book SET totalLines = 1 WHERE title = ?',
          ['מגילה רשמית'],
        );
        File(officialPath).setLastModifiedSync(
          DateTime.now().add(const Duration(hours: 1)),
        );
        final errors = await scan();
        expect(errors.single, contains('חורגת מגבולות'));
        expect(await repo.sidecarSignature(sidecar.path), oldSignature);
        expect(
          await repo.forwardUserLinks(
            'מגילה רשמית',
            sourceIsUserBook: false,
          ),
          hasLength(1),
        );
      } finally {
        officialDb.close();
      }
    });

    test('קובץ בתיקייה מקשר לספר ממסד מצורף (#4237)', () async {
      final dir = Directory(p.join(tempDir.path, 'attached'))..createSync();
      final path = SeforimFixtureDb.create(dir, SeforimFixtureVariant.full);
      final raw = sqlite3.sqlite3.open(path);
      raw.execute("UPDATE book SET title = 'ספר מצורף' WHERE id = 1");
      raw.close();
      await addBook('מגילה.txt', 'א\nב\nג');
      writeNativeLinks('מגילה', 'ספר מצורף', 2);

      final errors = await UserSidecarSync.applyForFolder(
        userDb: db,
        folderPath: folder.path,
        attachedLibraries: [
          (slug: 'my-db', path: path, immutable: false, visible: true),
        ],
      );

      expect(errors, isEmpty);
      // מפרש נשמר בכיוון הקנוני: הספר המצורף הוא הבסיס.
      final stored = (await UserContentRepository(db).forwardUserLinks(
        'ספר מצורף',
        sourceIsUserBook: false,
        sourceDb: 'my-db',
      )).single;
      expect(stored.targetTitle, 'מגילה');
      expect(stored.sourceLineIndex, 0);
    });

    test('מסד רשמי חסר נרשם כלא זמין ומתעדכן כשהוא מופיע', () async {
      await addBook('מגילה.txt', 'א\nב\nג');
      await addBook('מפרש.txt', 'פירוש');
      final sidecar = writeSidecar(
        'מגילה_links.json',
        '[{"line_index_1": 2, "line_index_2": 1, '
            '"path_2": "מפרש.txt", "Conection Type": "linker"}]',
      );
      final officialDb = MyDatabase.withPath(
        p.join(tempDir.path, 'not-yet-created.db'),
      );
      try {
        final repository = SeforimRepository(officialDb);
        final errors = await UserSidecarSync.applyForFolder(
          userDb: db,
          folderPath: folder.path,
          officialRepository: repository,
        );

        expect(errors, isEmpty);
        final repo = UserContentRepository(db);
        expect(
          await repo.sidecarSignature(sidecar.path),
          contains('unavailable'),
        );
        expect(await linksOf('מגילה'), hasLength(1));

        expect(
          await UserSidecarSync.applyForFolder(
            userDb: db,
            folderPath: folder.path,
            officialRepository: repository,
          ),
          isEmpty,
        );
        expect(
          await repo.sidecarSignature(sidecar.path),
          isNot(contains('unavailable')),
        );
      } finally {
        officialDb.close();
      }
    });

    test('מאגר הרקע מזהה שם ספר שקיים גם ברשמי וגם באישי', () async {
      final officialDb = MyDatabase.withPath(
        p.join(tempDir.path, 'seforim.db'),
      );
      try {
        final official = await officialDb.database;
        official.execute("INSERT INTO source (name) VALUES ('official')");
        official.execute(
          'INSERT INTO book (categoryId, sourceId, title, totalLines) '
          'VALUES (1, 1, ?, 3)',
          ['מגילה'],
        );
        await addBook('מגילה.txt', 'א\nב\nג');
        await addBook('מפרש.txt', 'פירוש');
        writeNativeLinks('מגילה', 'מפרש', 2);

        final errors = await UserSidecarSync.applyForFolder(
          userDb: db,
          folderPath: folder.path,
          officialRepository: SeforimRepository(officialDb),
        );

        expect(errors.single, contains('קיים גם בספרייה האישית וגם ברשמית'));
        expect(await linksOf('מגילה'), isEmpty);
      } finally {
        officialDb.close();
      }
    });

    test('הסרת הקובץ מהתיקייה מורידה את קישוריו', () async {
      await addBook('מגילה.txt', 'א\nב\nג');
      await addBook('מפרש.txt', 'פירוש');
      final file = writeSidecar(
        'מגילה_links.json',
        '[{"line_index_1": 2, "line_index_2": 1, '
            '"path_2": "מפרש.txt", "Conection Type": "linker"}]',
      );
      await UserSidecarSync.applyForFolder(userDb: db, folderPath: folder.path);
      expect(await linksOf('מגילה'), hasLength(1));

      file.deleteSync();
      await UserSidecarSync.applyForFolder(userDb: db, folderPath: folder.path);
      expect(await linksOf('מגילה'), isEmpty);
    });

    test('עריכת הקובץ מחליפה את קישוריו ולא מוסיפה עליהם', () async {
      await addBook('מגילה.txt', 'א\nב\nג');
      await addBook('מפרש.txt', 'פירוש');
      writeNativeLinks('מגילה', 'מפרש', 2);
      await UserSidecarSync.applyForFolder(userDb: db, folderPath: folder.path);

      writeNativeLinks('מגילה', 'מפרש', 3);
      await UserSidecarSync.applyForFolder(userDb: db, folderPath: folder.path);

      final stored = await linksOf('מגילה');
      expect(stored, hasLength(1));
      expect(stored.single.sourceLineIndex, 2);
    });

    test('כשל כתיבה באמצע החלפת קישורים משאיר קישורים וחתימה ישנים', () async {
      await addBook('מגילה.txt', 'א\nב\nג');
      await addBook('מפרש.txt', 'פירוש');
      final sidecar = writeSidecar(
        'מגילה_links.json',
        '[{"line_index_1": 1, "line_index_2": 1, '
            '"path_2": "מפרש.txt", "Conection Type": "linker"}]',
      );
      await UserSidecarSync.applyForFolder(userDb: db, folderPath: folder.path);
      final repo = UserContentRepository(db);
      final oldSignature = await repo.sidecarSignature(sidecar.path);
      final raw = await db.database;
      raw.execute('''
        CREATE TEMP TRIGGER fail_second_link BEFORE INSERT ON user_link
        WHEN NEW.sourceLineIndex = 2
        BEGIN SELECT RAISE(ABORT, 'injected write failure'); END
      ''');

      sidecar.writeAsStringSync(
        '[{"line_index_1": 2, "line_index_2": 1, '
        '"path_2": "מפרש.txt", "Conection Type": "linker"},'
        '{"line_index_1": 3, "line_index_2": 1, '
        '"path_2": "מפרש.txt", "Conection Type": "linker"}]',
      );
      final errors = await UserSidecarSync.applyForFolder(
        userDb: db,
        folderPath: folder.path,
      );

      expect(errors.single, contains('injected write failure'));
      expect((await linksOf('מגילה')).single.sourceLineIndex, 0);
      expect(await repo.sidecarSignature(sidecar.path), oldSignature);
    });

    test('שינוי בספר יעד מפעיל קליטה חוזרת גם כשהקובץ לא השתנה', () async {
      await addBook('מגילה.txt', 'א\nב\nג');
      await addBook('מפרש.txt', 'א\nב\nג');
      final raw = await db.database;
      raw.execute("UPDATE book SET totalLines = 3 WHERE title = 'מפרש'");
      final sidecar = writeSidecar(
        'מגילה_links.json',
        '[{"line_index_1": 1, "line_index_2": 2, '
            '"path_2": "מפרש.txt", "Conection Type": "linker"}]',
      );
      expect(
        await UserSidecarSync.applyForFolder(
          userDb: db,
          folderPath: folder.path,
        ),
        isEmpty,
      );
      final repo = UserContentRepository(db);
      final oldSignature = await repo.sidecarSignature(sidecar.path);

      raw.execute("UPDATE book SET totalLines = 1 WHERE title = 'מפרש'");
      final errors = await UserSidecarSync.applyForFolder(
        userDb: db,
        folderPath: folder.path,
      );
      expect(errors.single, contains('חורגת מגבולות'));
      expect((await linksOf('מגילה')).single.targetLineIndex, 1);
      expect(await repo.sidecarSignature(sidecar.path), oldSignature);
    });

    test('הופעת ספר אישי בשם יעד רשמי מבטלת חתימת קישורים', () async {
      await addBook('מגילה.txt', 'א');
      final raw = await db.database;
      final source = p.join(folder.path, 'מגילה_links.json');
      raw.execute(
        'INSERT INTO user_link (sourceTitle, sourceIsUserBook, '
        'sourceLineIndex, targetTitle, targetIsUserBook, targetLineIndex, '
        'connectionType, source) VALUES (?, 1, 0, ?, 0, 0, ?, ?)',
        ['מגילה', 'מפרש', 'COMMENTARY', source],
      );
      final repo = UserContentRepository(db);
      await repo.replaceSidecarLinkBookDependencies(source);
      final before = await repo.sidecarLinkBookSignature(source);

      await addBook('מפרש.txt', 'א');

      expect(await repo.sidecarLinkBookSignature(source), isNot(before));
    });

    test('קובץ גדול נקלט פעם אחת וחתימה חוסכת קליטה חוזרת', () async {
      await addBook('מגילה.txt', List.filled(500, 'א').join('\n'));
      await addBook('מפרש.txt', 'א');
      final rows = [
        for (var line = 1; line <= 500; line++)
          '{"line_index_1": $line, "line_index_2": 1, '
              '"path_2": "מפרש.txt", "Conection Type": "linker"}',
      ];
      writeSidecar('מגילה_links.json', '[${rows.join(',')}]');
      expect(
        await UserSidecarSync.applyForFolder(
          userDb: db,
          folderPath: folder.path,
        ),
        isEmpty,
      );
      expect(await linksOf('מגילה'), hasLength(500));

      final raw = await db.database;
      raw.execute('''
        CREATE TEMP TRIGGER fail_reimport BEFORE INSERT ON user_link
        BEGIN SELECT RAISE(ABORT, 'unchanged file was reimported'); END
      ''');
      expect(
        await UserSidecarSync.applyForFolder(
          userDb: db,
          folderPath: folder.path,
        ),
        isEmpty,
      );
      expect(await linksOf('מגילה'), hasLength(500));
    });

    test('"נקה הכל" אינו מוחק קישורים שמקורם בתיקייה', () async {
      await addBook('מגילה.txt', 'א\nב\nג');
      await addBook('מפרש.txt', 'פירוש');
      writeNativeLinks('מגילה', 'מפרש', 2);
      await UserSidecarSync.applyForFolder(userDb: db, folderPath: folder.path);

      // הם חוזרים עם התיקייה ואינם חלק ממה שהמשתמש ייבא מההגדרות.
      await UserContentRepository(db).clearAllUserContent();
      expect(await linksOf('מגילה'), hasLength(1));
    });

    test('קובץ שנכשל נקלט שוב בסריקה הבאה', () async {
      // ספר היעד עדיין לא נסרק — הקליטה נכשלת ואין לרשום "לא השתנה".
      await addBook('מגילה.txt', 'א\nב\nג');
      writeNativeLinks('מגילה', 'מפרש', 2);
      final first = await UserSidecarSync.applyForFolder(
        userDb: db,
        folderPath: folder.path,
      );
      expect(first, isNotEmpty);
      expect(await linksOf('מגילה'), isEmpty);

      await addBook('מפרש.txt', 'פירוש');
      final second = await UserSidecarSync.applyForFolder(
        userDb: db,
        folderPath: folder.path,
      );
      expect(second, isEmpty);
      expect(await linksOf('מגילה'), hasLength(1));
    });
  });

  test('מחיקת ספר מוחקת את כותרותיו ואת רשומות הגרסאות שלו', () async {
    final primary = await addBook('ראשי.txt', 'א\nב');
    await addBook('משני.txt', 'א');
    writeSidecar('ראשי.כותרות.csv', 'כותרת,שורה\nפרק,1\n');
    writeSidecar('גרסאות.csv', 'ראשי,גרסה\nראשי.txt,משני.txt\n');
    await UserSidecarSync.applyForFolder(userDb: db, folderPath: folder.path);

    await SeforimRepository(db).deleteBookCompletely(primary);

    final raw = await db.database;
    expect(raw.select('SELECT * FROM user_alt_toc_structure'), isEmpty);
    expect(raw.select('SELECT * FROM user_alt_toc_entry'), isEmpty);
    expect(raw.select('SELECT * FROM user_book_version'), isEmpty);
  });

  group('גרסה אישית של ספר רשמי', () {
    test('קובץ הגרסאות שומר את הראשי לפי מקור, כותרת וקטגוריה', () async {
      final version = await addBook('בראשית כתב יד.txt', 'א');
      writeSidecar(
        'גרסאות.csv',
        'ראשי,גרסה,שם,מקור_ראשי,קטגוריית_ראשי\n'
            'בראשית,בראשית כתב יד.txt,כתב יד,רשמי,תורה\n',
      );

      final errors = await UserSidecarSync.applyForFolder(
        userDb: db,
        folderPath: folder.path,
      );

      expect(errors, isEmpty);
      final raw = await db.database;
      final row = raw.select('SELECT * FROM user_book_version').single;
      expect(row['versionBookId'], version);
      expect(row['primaryBookId'], isNull);
      expect(row['primarySource'], 'o');
      expect(row['primaryTitle'], 'בראשית');
      expect(row['primaryCategoryPath'], 'תורה');
      expect(row['versionTitle'], 'כתב יד');
    });

    test('קובץ הגרסה חסר — שגיאה בשורה, בלי לעצור את שאר הקובץ', () async {
      await addBook('קיים.txt', 'א');
      writeSidecar(
        'גרסאות.csv',
        'ראשי,גרסה,מקור_ראשי\nבראשית,חסר.txt,רשמי\nשמות,קיים.txt,רשמי\n',
      );

      final errors = await UserSidecarSync.applyForFolder(
        userDb: db,
        folderPath: folder.path,
      );

      expect(errors.single, contains('חסר.txt'));
      final raw = await db.database;
      final rows = raw.select('SELECT primaryTitle FROM user_book_version');
      expect(rows.single['primaryTitle'], 'שמות');
    });

    test('ייבוא מההגדרות: ראשי ממסד מצורף נשמר גם כשאינו מחובר', () async {
      final version = await addBook('גרסה מצורפת.txt', 'א');
      final versionsPath = p.join(tempDir.path, 'גרסאות.csv');
      File(versionsPath).writeAsStringSync(
        'ראשי,גרסה,מקור_ראשי\nבראשית,גרסה מצורפת,מסד:ספרייה\n',
      );

      final result = await UserContentImporter.importFiles([versionsPath], db);

      expect(result.errors, isEmpty);
      final raw = await db.database;
      final row = raw.select('SELECT * FROM user_book_version').single;
      expect(row['versionBookId'], version);
      expect(row['primarySource'], 'd:ספרייה');
    });
  });
}
