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
