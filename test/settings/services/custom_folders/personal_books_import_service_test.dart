import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/services/custom_folders/personal_books_import_service.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempRoot;
  late Directory sourceDir;
  late String importPath;
  late PersonalBooksImportService service;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('personal_books_test');
    sourceDir = await Directory(p.join(tempRoot.path, 'source')).create();
    importPath = p.join(tempRoot.path, 'imported');
    service = PersonalBooksImportService(folderPathOverride: importPath);
  });

  tearDown(() async {
    await tempRoot.delete(recursive: true);
  });

  Future<String> createSourceFile(String name, String content) async {
    final file = File(p.join(sourceDir.path, name));
    await file.writeAsString(content);
    return file.path;
  }

  group('copyFiles', () {
    test('מעתיק קבצים נתמכים לתיקיית הייבוא ומשאיר את המקור', () async {
      final txt = await createSourceFile('ספר.txt', 'תוכן');
      final pdf = await createSourceFile('חוברת.pdf', 'pdf-bytes');

      final result = await service.copyFiles([txt, pdf]);

      expect(result.copied, 2);
      expect(result.skippedUnsupported, 0);
      expect(result.errors, isEmpty);
      expect(File(p.join(importPath, 'ספר.txt')).existsSync(), isTrue);
      expect(File(p.join(importPath, 'חוברת.pdf')).existsSync(), isTrue);
      expect(File(txt).existsSync(), isTrue);
      expect(File(pdf).existsSync(), isTrue);
    });

    test('מדלג על סיומות לא נתמכות', () async {
      final mobi = await createSourceFile('ספר.mobi', 'x');
      final txt = await createSourceFile('ספר.txt', 'תוכן');

      final result = await service.copyFiles([mobi, txt]);

      expect(result.copied, 1);
      expect(result.skippedUnsupported, 1);
      expect(File(p.join(importPath, 'ספר.mobi')).existsSync(), isFalse);
    });

    test('קובץ EPUB נתמך ומועתק', () async {
      final epub = await createSourceFile('ספר.epub', 'epub-bytes');

      final result = await service.copyFiles([epub]);

      expect(result.copied, 1);
      expect(result.skippedUnsupported, 0);
      expect(File(p.join(importPath, 'ספר.epub')).existsSync(), isTrue);
    });

    test('קובץ בשם קיים דורס את הגרסה הקודמת', () async {
      final v1 = await createSourceFile('ספר.txt', 'גרסה ראשונה');
      await service.copyFiles([v1]);
      final v2Path = p.join(sourceDir.path, 'v2', 'ספר.txt');
      await File(v2Path).create(recursive: true);
      await File(v2Path).writeAsString('גרסה שנייה');

      final result = await service.copyFiles([v2Path]);

      expect(result.copied, 1);
      expect(
        File(p.join(importPath, 'ספר.txt')).readAsStringSync(),
        'גרסה שנייה',
      );
    });

    test('ייבוא קובץ שכבר נמצא בתיקיית הייבוא לא מרוקן אותו', () async {
      final txt = await createSourceFile('ספר.txt', 'תוכן');
      await service.copyFiles([txt]);
      final imported = p.join(importPath, 'ספר.txt');

      final result = await service.copyFiles([imported]);

      expect(result.copied, 1);
      expect(result.errors, isEmpty);
      expect(File(imported).readAsStringSync(), 'תוכן');
    });

    test('קובץ מקור חסר נרשם כשגיאה בלי להפיל את השאר', () async {
      final txt = await createSourceFile('ספר.txt', 'תוכן');
      final missing = p.join(sourceDir.path, 'לא-קיים.txt');

      final result = await service.copyFiles([missing, txt]);

      expect(result.copied, 1);
      expect(result.errors, hasLength(1));
      expect(result.errors.single, contains('לא-קיים.txt'));
    });

    test('העתקה שנכשלה אינה משאירה קובץ בתיקיית הייבוא', () async {
      final missing = p.join(sourceDir.path, 'ספר.pdf');

      final result = await service.copyFiles([missing]);

      expect(result.errors, hasLength(1));
      expect(Directory(importPath).listSync(), isEmpty);
    });

    test('העתקה שנכשלה אינה פוגעת בגרסה הקודמת של הספר', () async {
      final existing = File(p.join(importPath, 'ספר.pdf'));
      await existing.create(recursive: true);
      await existing.writeAsString('גרסה קודמת');
      final missing = p.join(sourceDir.path, 'ספר.pdf');

      final result = await service.copyFiles([missing]);

      expect(result.errors, hasLength(1));
      expect(existing.readAsStringSync(), 'גרסה קודמת');
    });

    test('שם קובץ חוקי באורך המרבי עדיין מיובא', () async {
      final name = '${'a' * 251}.txt';
      final source = await createSourceFile(name, 'ספר');
      final result = await service.copyFiles([source]);

      expect(result.copied, 1, reason: result.errors.join('\n'));
      expect(File(p.join(importPath, name)).readAsStringSync(), 'ספר');
    }, skip: Platform.isWindows);

    test('קובץ part קודם אינו נכתב או נמחק בייבוא', () async {
      await Directory(importPath).create();
      final previousPartial = File(p.join(importPath, 'ספר.txt.part'));
      await previousPartial.writeAsString('שארית קודמת');
      final source = await createSourceFile('ספר.txt', 'ספר חדש');

      final result = await service.copyFiles([source]);

      expect(result.copied, 1);
      expect(previousPartial.readAsStringSync(), 'שארית קודמת');
      expect(Directory(importPath).listSync(), hasLength(2));
      expect(
        (await service.listImportedFiles()).single.path,
        p.join(importPath, 'ספר.txt'),
      );
    });

    test('ייבואים מקבילים באותו שם אינם משתפים את הקובץ הזמני', () async {
      final first = await createSourceFile('ספר.txt', 'a' * (1024 * 1024));
      final second = File(p.join(sourceDir.path, 'other', 'ספר.txt'));
      await second.create(recursive: true);
      await second.writeAsString('b' * (1024 * 1024));

      final results = await Future.wait([
        service.copyFiles([first]),
        service.copyFiles([second.path]),
      ]);

      expect(results.map((r) => r.copied), [1, 1]);
      expect(results.expand((r) => r.errors), isEmpty);
      final text = File(p.join(importPath, 'ספר.txt')).readAsStringSync();
      expect(
        text == 'a' * (1024 * 1024) || text == 'b' * (1024 * 1024),
        isTrue,
      );
      expect(Directory(importPath).listSync(), hasLength(1));
    });

    for (final denyCleanup in [false, true]) {
      test(
        'כשל באמצע הקריאה שומר את הספר וממשיך בייבוא (ניקוי חסום: $denyCleanup)',
        () async {
          await Directory(importPath).create();
          final existing = File(p.join(importPath, 'ספר.txt'));
          await existing.writeAsString('גרסה קודמת');
          final source = await createSourceFile('ספר.txt', 'ספר חדש');
          final second = await createSourceFile('שני.txt', 'ספר שני');
          final overrides = _InterruptedReadOverrides(
            source,
            beforeError: denyCleanup
                ? () async {
                    for (final dir in Directory(
                      importPath,
                    ).listSync().whereType<Directory>()) {
                      await Process.run('chmod', ['555', dir.path]);
                    }
                  }
                : null,
          );
          addTearDown(() async {
            if (denyCleanup) {
              for (final dir in Directory(
                importPath,
              ).listSync().whereType<Directory>()) {
                await Process.run('chmod', ['755', dir.path]);
              }
            }
          });

          final result = await IOOverrides.runZoned(
            () => service.copyFiles([source, second]),
            createFile: overrides.createFile,
          );

          expect(result.copied, 1);
          expect(result.errors, hasLength(1));
          expect(result.errors.single, contains('source interrupted'));
          expect(existing.readAsStringSync(), 'גרסה קודמת');
          expect(
            File(p.join(importPath, 'שני.txt')).readAsStringSync(),
            'ספר שני',
          );
          expect(await service.listImportedFiles(), hasLength(2));
          if (!denyCleanup) {
            expect(Directory(importPath).listSync(), hasLength(2));
          }
        },
        skip: denyCleanup && Platform.isWindows,
      );
    }

    test(
      'תיקיית יעד ללא הרשאת כתיבה מדווחת כל קובץ ושומרת part קודם',
      () async {
        await Directory(importPath).create();
        final previousPartial = File(p.join(importPath, 'ספר.txt.part'));
        await previousPartial.writeAsString('שארית');
        final first = await createSourceFile('ספר.txt', 'ראשון');
        final second = await createSourceFile('שני.txt', 'שני');
        addTearDown(() async => Process.run('chmod', ['755', importPath]));
        await Process.run('chmod', ['555', importPath]);

        final result = await service.copyFiles([first, second]);

        expect(result.copied, 0);
        expect(result.errors, hasLength(2));
        expect(previousPartial.readAsStringSync(), 'שארית');
      },
      skip: Platform.isWindows,
    );

    test('כשל החלפה אינו מוחק תיקיית יעד ומנקה רק את ההעתקה שלו', () async {
      final target = await Directory(
        p.join(importPath, 'ספר.txt'),
      ).create(recursive: true);
      final sentinel = File(p.join(target.path, 'שמור.txt'));
      await sentinel.writeAsString('שמור');
      final first = await createSourceFile('ספר.txt', 'חדש');
      final second = await createSourceFile('שני.txt', 'שני');

      final result = await service.copyFiles([first, second]);

      expect(result.copied, 1);
      expect(result.errors, hasLength(1));
      expect(sentinel.readAsStringSync(), 'שמור');
      expect(Directory(importPath).listSync(), hasLength(2));
    });
  });

  group('listImportedFiles', () {
    test('מחזיר רשימה ריקה כשהתיקייה לא קיימת', () async {
      expect(await service.listImportedFiles(), isEmpty);
    });

    test('מחזיר רק קבצים נתמכים, ממוינים לפי שם', () async {
      await service.copyFiles([
        await createSourceFile('ב.pdf', 'x'),
        await createSourceFile('א.txt', 'x'),
      ]);
      await File(p.join(importPath, 'זבל.tmp')).writeAsString('x');

      final files = await service.listImportedFiles();

      expect(
        files.map((f) => p.basename(f.path)).toList(),
        ['א.txt', 'ב.pdf'],
      );
    });
  });

  group('ייבוא תיקייה', () {
    test('יעד הייבוא הוא תת-תיקייה בשם התיקייה, בלי מפרידי נתיב', () async {
      expect(
        await service.folderImportTarget('ספרי מוסר'),
        p.join(importPath, 'ספרי מוסר'),
      );
      expect(
        await service.folderImportTarget('a/b'),
        p.join(importPath, 'a_b'),
      );
      expect(
        await service.folderImportTarget('  '),
        p.join(importPath, 'תיקייה מיובאת'),
      );
    });

    test('קובץ שהועתק ואינו ספר לפי תוכנו נמחק ונספר כמדולג', () async {
      final txt = await createSourceFile('ספר.txt', 'תוכן');
      final xml = await createSourceFile('לא-וורד.xml', '<root/>');

      final result = await service.keepValidCopiedFiles([txt, xml]);

      expect(result.copied, 1);
      expect(result.skippedUnsupported, 1);
      expect(File(txt).existsSync(), isTrue);
      expect(File(xml).existsSync(), isFalse);
    });

    test('שגיאת חוסר מקום מתורגמת להודעה ברורה', () {
      expect(
        PersonalBooksImportService.describeCopyError(
          'ספר.pdf',
          'write failed: ENOSPC (No space left on device)',
        ),
        '"ספר.pdf": אין מספיק מקום פנוי באחסון המכשיר',
      );
    });
  });

  group('deleteImportedFile', () {
    test('מוחק קובץ מתוך תיקיית הייבוא', () async {
      await service.copyFiles([await createSourceFile('ספר.txt', 'x')]);
      final target = p.join(importPath, 'ספר.txt');

      await service.deleteImportedFile(target);

      expect(File(target).existsSync(), isFalse);
    });

    test('זורק על נתיב מחוץ לתיקיית הייבוא', () async {
      final outside = await createSourceFile('ספר.txt', 'x');

      expect(
        () => service.deleteImportedFile(outside),
        throwsArgumentError,
      );
      expect(File(outside).existsSync(), isTrue);
    });
  });
}

final class _InterruptedReadOverrides extends IOOverrides {
  _InterruptedReadOverrides(this.sourcePath, {this.beforeError});
  final String sourcePath;
  final Future<void> Function()? beforeError;

  @override
  File createFile(String path) => path == sourcePath
      ? _InterruptedReadFile(path, beforeError)
      : super.createFile(path);
}

class _InterruptedReadFile implements File {
  _InterruptedReadFile(this.path, this.beforeError);
  @override
  final String path;
  final Future<void> Function()? beforeError;

  @override
  Stream<List<int>> openRead([int? start, int? end]) async* {
    yield [110, 101, 119];
    await beforeError?.call();
    throw FileSystemException('source interrupted', path);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
