import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/semantic_search/models/semantic_paths.dart';
import 'package:otzaria/utils/move_directory.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('otzaria_move_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  String src(String name) => p.join(tempDir.path, name);

  group('moveDirectory', () {
    test('מעביר קבצים ומוחק תיקיית המקור', () async {
      final source = src('from');
      final dest = src('to');
      await Directory(source).create();
      await File(p.join(source, 'file.txt')).writeAsString('שלום');

      final result = await moveDirectory(source, dest);

      expect(result, isNull);
      expect(await File(p.join(dest, 'file.txt')).readAsString(), 'שלום');
      expect(await Directory(source).exists(), isFalse);
    });

    test('מעביר תיקיות מקוננות', () async {
      final source = src('from');
      final dest = src('to');
      await Directory(p.join(source, 'sub')).create(recursive: true);
      await File(p.join(source, 'sub', 'nested.txt')).writeAsString('תוכן');

      final result = await moveDirectory(source, dest);

      expect(result, isNull);
      expect(await File(p.join(dest, 'sub', 'nested.txt')).exists(), isTrue);
    });

    test('מעביר מספר קבצים בתיקייה', () async {
      final source = src('from');
      await Directory(source).create();
      for (var i = 0; i < 5; i++) {
        await File(p.join(source, 'f$i.txt')).writeAsString('data $i');
      }

      await moveDirectory(source, src('to'));

      for (var i = 0; i < 5; i++) {
        expect(await File(p.join(src('to'), 'f$i.txt')).exists(), isTrue);
      }
    });

    test('מחזיר null כשמקור ויעד זהים (ללא פעולה)', () async {
      final dir = src('same');
      await Directory(dir).create();
      await File(p.join(dir, 'f.txt')).writeAsString('x');

      final result = await moveDirectory(dir, dir);

      expect(result, isNull);
      expect(await File(p.join(dir, 'f.txt')).exists(), isTrue);
    });

    test('יוצר את תיקיית היעד אם לא קיימת', () async {
      final source = src('from');
      final dest = src('a/b/c/dest');
      await Directory(source).create();
      await File(p.join(source, 'x.txt')).writeAsString('y');

      await moveDirectory(source, dest);

      expect(await File(p.join(dest, 'x.txt')).exists(), isTrue);
    });

    test('זורק Exception כשתיקיית המקור לא קיימת', () async {
      await expectLater(
        () => moveDirectory(src('nonexistent'), src('dest')),
        throwsA(isA<Exception>()),
      );
    });

    test('זורק Exception כשהיעד בתוך המקור', () async {
      final source = src('from');
      await Directory(source).create();

      await expectLater(
        () => moveDirectory(source, p.join(source, 'sub')),
        throwsA(isA<Exception>()),
      );
    });

    test('תיקיית יעד כבר קיימת — מאחד תכנים ולא זורק שגיאה', () async {
      final source = src('from');
      final dest = src('to');
      await Directory(source).create();
      await Directory(dest).create();
      await File(p.join(source, 'new.txt')).writeAsString('new');
      await File(p.join(dest, 'existing.txt')).writeAsString('old');

      final result = await moveDirectory(source, dest);

      expect(result, isNull);
      expect(await File(p.join(dest, 'new.txt')).exists(), isTrue);
      expect(await File(p.join(dest, 'existing.txt')).exists(), isTrue);
    });
  });

  group('moveDirectory — includeOnly', () {
    test('מעביר רק קבצים מזוהים ומשאיר את השאר במקום', () async {
      final source = src('from');
      final dest = src('to');
      await Directory(source).create();
      await File(p.join(source, 'seforim.db')).writeAsString('db');
      await File(p.join(source, 'my_notes.txt')).writeAsString('של המשתמש');

      final result = await moveDirectory(
        source,
        dest,
        includeOnly: {'seforim.db'},
      );

      expect(result, isNull);
      expect(await File(p.join(dest, 'seforim.db')).exists(), isTrue);
      // הקובץ שאינו מזוהה לא הועבר
      expect(await File(p.join(dest, 'my_notes.txt')).exists(), isFalse);
    });

    test('תיקיית המקור נשארת כשנותר בה תוכן לא מזוהה', () async {
      final source = src('from');
      final dest = src('to');
      await Directory(source).create();
      await File(p.join(source, 'seforim.db')).writeAsString('db');
      await File(p.join(source, 'my_notes.txt')).writeAsString('נשאר');

      await moveDirectory(source, dest, includeOnly: {'seforim.db'});

      expect(await Directory(source).exists(), isTrue);
      expect(await File(p.join(source, 'seforim.db')).exists(), isFalse);
      expect(await File(p.join(source, 'my_notes.txt')).exists(), isTrue);
    });

    test('תיקיית המקור נמחקת כשנותרה ריקה אחרי ההעברה', () async {
      final source = src('from');
      final dest = src('to');
      await Directory(source).create();
      await File(p.join(source, 'seforim.db')).writeAsString('db');

      await moveDirectory(source, dest, includeOnly: {'seforim.db'});

      expect(await Directory(source).exists(), isFalse);
    });

    test('מעביר תיקייה מזוהה (כמו "תלמוד בבלי") עם תכנה', () async {
      final source = src('from');
      final dest = src('to');
      await Directory(p.join(source, 'תלמוד בבלי')).create(recursive: true);
      await File(p.join(source, 'תלמוד בבלי', 'a.pdf')).writeAsString('pdf');

      await moveDirectory(source, dest, includeOnly: {'תלמוד בבלי'});

      expect(await File(p.join(dest, 'תלמוד בבלי', 'a.pdf')).exists(), isTrue);
    });

    test('רשימת קבצי הספרייה המנוהלים כוללת lexical.db', () async {
      final source = src('from');
      final dest = src('to');
      await Directory(source).create();
      await File(
        p.join(source, DatabaseConstants.databaseFileName),
      ).writeAsString('db');
      await File(
        p.join(source, DatabaseConstants.lexicalDatabaseFileName),
      ).writeAsString('lexical');
      // סימון הגרסה והעותק הממתין — בלעדיהם המילון היה מורד שוב.
      const sidecars = ['lexical.db.version', 'lexical.db.next'];
      for (final name in sidecars) {
        await File(p.join(source, name)).writeAsString(name);
      }
      await File(p.join(source, 'my_notes.txt')).writeAsString('נשאר');

      await moveDirectory(
        source,
        dest,
        includeOnly: DatabaseConstants.libraryManagedEntryNames(),
      );

      expect(
        await File(p.join(dest, DatabaseConstants.databaseFileName)).exists(),
        isTrue,
      );
      expect(
        await File(
          p.join(dest, DatabaseConstants.lexicalDatabaseFileName),
        ).exists(),
        isTrue,
      );
      for (final name in sidecars) {
        expect(await File(p.join(dest, name)).exists(), isTrue, reason: name);
      }
      expect(await File(p.join(dest, 'my_notes.txt')).exists(), isFalse);
      expect(await File(p.join(source, 'my_notes.txt')).exists(), isTrue);
    });

    test('תיקיית המודל של החיפוש הסמנטי עוברת עם הספרייה', () async {
      final source = src('from');
      final dest = src('to');
      final model = p.join(source, kSemanticModelFolderName, 'tokenizer.json');
      await File(model).create(recursive: true);

      await moveDirectory(
        source,
        dest,
        includeOnly: DatabaseConstants.libraryManagedEntryNames(),
      );

      expect(
        await File(
          p.join(dest, kSemanticModelFolderName, 'tokenizer.json'),
        ).exists(),
        isTrue,
      );
    });

    test('קבצי ארכיון דחוסים נשארים במקומם בהעברת הספרייה', () async {
      final source = src('from');
      final dest = src('to');
      await Directory(source).create();
      await File(
        p.join(source, DatabaseConstants.databaseFileName),
      ).writeAsString('db');
      for (final archive in [
        DatabaseConstants.databaseArchiveFileName,
        DatabaseConstants.externalCatalogArchiveFileName,
        DatabaseConstants.talmudBavliArchiveFileName,
      ]) {
        await File(p.join(source, archive)).writeAsString('archive');
      }

      await moveDirectory(
        source,
        dest,
        includeOnly: DatabaseConstants.libraryManagedEntryNames(),
      );

      for (final archive in [
        DatabaseConstants.databaseArchiveFileName,
        DatabaseConstants.externalCatalogArchiveFileName,
        DatabaseConstants.talmudBavliArchiveFileName,
      ]) {
        expect(await File(p.join(source, archive)).exists(), isTrue);
        expect(await File(p.join(dest, archive)).exists(), isFalse);
      }
    });
  });

  group('moveDirectory — בטיחות יעד', () {
    test('לא דורס קובץ קיים ביעד — זורק שגיאה ולא מוחק את המקור', () async {
      final source = src('from');
      final dest = src('to');
      await Directory(source).create();
      await Directory(dest).create();
      await File(p.join(source, 'seforim.db')).writeAsString('חדש');
      await File(p.join(dest, 'seforim.db')).writeAsString('קיים');

      await expectLater(
        () => moveDirectory(source, dest),
        throwsA(isA<Exception>()),
      );

      // הקובץ ביעד נשמר, והמקור לא נמחק
      expect(await File(p.join(dest, 'seforim.db')).readAsString(), 'קיים');
      expect(await File(p.join(source, 'seforim.db')).exists(), isTrue);
    });

    test('כשל באמצע מנקה רק את מה שהועתק, וניסיון חוזר מצליח', () async {
      final source = src('from');
      final dest = src('to');
      await Directory(p.join(source, 'archive')).create(recursive: true);
      await Directory(p.join(dest, 'archive')).create(recursive: true);
      for (var i = 0; i < 30; i++) {
        final name = 'book_${i.toString().padLeft(2, '0')}.pdf';
        await File(p.join(source, name)).writeAsString('$i');
      }
      await File(p.join(source, 'archive', 'new.txt')).writeAsString('חדש');
      await File(p.join(dest, 'archive', 'keep.txt')).writeAsString('קיים');
      final collision = File(p.join(dest, 'book_29.pdf'));
      await collision.writeAsString('קיים');

      await expectLater(
        () => moveDirectory(source, dest),
        throwsA(isA<Exception>()),
      );

      final left = Directory(dest)
          .listSync(recursive: true)
          .map((e) => p.relative(e.path, from: dest))
          .toSet();
      expect(left, {'book_29.pdf', 'archive', p.join('archive', 'keep.txt')});
      expect(await collision.readAsString(), 'קיים');

      await collision.delete();
      expect(await moveDirectory(source, dest), isNull);
      expect(await Directory(source).exists(), isFalse);
      expect(
        await File(p.join(dest, 'archive', 'keep.txt')).readAsString(),
        'קיים',
      );
      expect(
        await File(p.join(dest, 'archive', 'new.txt')).readAsString(),
        'חדש',
      );
      for (var i = 0; i < 30; i++) {
        final name = 'book_${i.toString().padLeft(2, '0')}.pdf';
        expect(await File(p.join(dest, name)).readAsString(), '$i');
      }
    });

    test('מעביר תיקייה ריקה', () async {
      final source = src('from');
      final dest = src('to');
      await Directory(p.join(source, 'empty_dir')).create(recursive: true);

      await moveDirectory(source, dest);

      expect(await Directory(p.join(dest, 'empty_dir')).exists(), isTrue);
    });

    test('מעביר קישור סימבולי', () async {
      final source = src('from');
      final dest = src('to');
      await Directory(source).create();
      final target = src('target.txt');
      await File(target).writeAsString('יעד');
      try {
        await Link(p.join(source, 'link.txt')).create(target);
      } catch (_) {
        // יצירת symlink עשויה לדרוש הרשאות (Windows) — מדלגים אם לא ניתן.
        markTestSkipped('אין אפשרות ליצור קישור סימבולי בסביבה זו');
        return;
      }

      await moveDirectory(source, dest);

      final movedLink = Link(p.join(dest, 'link.txt'));
      expect(await movedLink.exists(), isTrue);
      expect(await movedLink.target(), target);
    });
  });

  group('copyDirectoryEntries / deleteMovedEntries', () {
    test('copy בלי created שומר תיקיות ריקות גם בעומק העץ', () async {
      final source = src('from');
      final dest = src('to');
      await Directory(
        p.join(source, 'empty', 'nested'),
      ).create(recursive: true);

      await copyDirectoryEntries(source, dest);

      expect(await Directory(p.join(dest, 'empty', 'nested')).exists(), isTrue);
      expect(
        await Directory(p.join(source, 'empty', 'nested')).exists(),
        isTrue,
      );
    });

    test('copy בלי created שומר קישורים לקובץ, לתיקייה וליעד חסר', () async {
      final source = src('from');
      final dest = src('to');
      await Directory(source).create();
      final target = await File(src('target.txt')).writeAsString('יעד');
      final folder = await Directory(src('target-folder')).create();
      final targets = {
        'file-link': target.path,
        'folder-link': folder.path,
        'missing-link': src('missing.txt'),
      };
      try {
        for (final entry in targets.entries) {
          await Link(p.join(source, entry.key)).create(entry.value);
        }
      } on FileSystemException {
        markTestSkipped('אין אפשרות ליצור קישור סימבולי בסביבה זו');
        return;
      }

      await copyDirectoryEntries(source, dest);

      for (final entry in targets.entries) {
        final copied = Link(p.join(dest, entry.key));
        expect(await copied.exists(), isTrue, reason: entry.key);
        expect(await copied.target(), entry.value);
        expect(await Link(p.join(source, entry.key)).exists(), isTrue);
      }
      expect(await target.readAsString(), 'יעד');
      expect(await folder.exists(), isTrue);
    });

    test('staging ומחיקת המקור שומרים את כל פריטי הספרייה שנבחרו', () async {
      final source = src('from');
      final staged = src('staging');
      final dest = src('books');
      final talmud = DatabaseConstants.talmudBavliFolderName;
      await Directory(p.join(source, talmud, 'empty')).create(recursive: true);
      await File(p.join(source, talmud, 'book.pdf')).writeAsString('pdf');
      await File(p.join(source, 'my_notes.txt')).writeAsString('נשאר');
      final target = await File(src('outside-db')).writeAsString('db');
      final database = DatabaseConstants.databaseFileName;
      try {
        await Link(p.join(source, database)).create(target.path);
      } on FileSystemException {
        markTestSkipped('אין אפשרות ליצור קישור סימבולי בסביבה זו');
        return;
      }
      final include = DatabaseConstants.libraryManagedEntryNames();

      await copyDirectoryEntries(source, staged, includeOnly: include);
      await Directory(staged).rename(dest);
      expect(await deleteMovedEntries(source, includeOnly: include), isNull);

      expect(await Link(p.join(dest, database)).target(), target.path);
      expect(await Directory(p.join(dest, talmud, 'empty')).exists(), isTrue);
      expect(
        await File(p.join(dest, talmud, 'book.pdf')).readAsString(),
        'pdf',
      );
      expect(await File(p.join(source, 'my_notes.txt')).readAsString(), 'נשאר');
      expect(await Link(p.join(source, database)).exists(), isFalse);
      expect(await Directory(p.join(source, talmud)).exists(), isFalse);
      expect(await target.readAsString(), 'db');
    });

    test('copy מעתיק בלי למחוק מהמקור', () async {
      final source = src('from');
      final dest = src('to');
      await Directory(source).create();
      await File(p.join(source, 'seforim.db')).writeAsString('db');

      await copyDirectoryEntries(source, dest, includeOnly: {'seforim.db'});

      expect(await File(p.join(dest, 'seforim.db')).exists(), isTrue);
      expect(await File(p.join(source, 'seforim.db')).exists(), isTrue);
    });

    test('delete מוחק את הרשומות שהועברו ושומר על קבצים אחרים', () async {
      final source = src('from');
      await Directory(source).create();
      await File(p.join(source, 'seforim.db')).writeAsString('db');
      await File(p.join(source, 'other.txt')).writeAsString('x');

      final result = await deleteMovedEntries(
        source,
        includeOnly: {'seforim.db'},
      );

      expect(result, isNull);
      expect(await File(p.join(source, 'seforim.db')).exists(), isFalse);
      expect(await File(p.join(source, 'other.txt')).exists(), isTrue);
      expect(await Directory(source).exists(), isTrue);
    });
  });
}
