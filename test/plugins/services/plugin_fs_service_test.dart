import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/services/plugin_fs_service.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;
  late PluginFsService service;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('plugin_fs_test_');
    service = PluginFsService();
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  /// יוצרת קובץ ZIP ב-[zipPath] המכיל את [entries] (שם יחסי → תוכן).
  String buildZip(String zipPath, Map<String, String> entries) {
    final srcDir = Directory(p.join(tempDir.path, 'src_${entries.hashCode}'))
      ..createSync(recursive: true);
    final encoder = ZipFileEncoder();
    encoder.create(zipPath);
    try {
      entries.forEach((name, content) {
        final f = File(p.join(srcDir.path, name))
          ..parent.createSync(recursive: true)
          ..writeAsStringSync(content);
        encoder.addFileSync(f, name);
      });
    } finally {
      encoder.closeSync();
    }
    return zipPath;
  }

  group('PluginFsService.extractZip', () {
    test('מחלץ קבצים אל תיקיית היעד ויוצר אותה אם אינה קיימת', () async {
      final zipPath = buildZip(p.join(tempDir.path, 'a.zip'), {
        'hello.txt': 'שלום עולם',
        'sub/inner.txt': 'פנימי',
      });
      final destFolder = p.join(tempDir.path, 'out', 'nested');

      await service.extractZip(zipPath, destFolder);

      final hello = File(p.join(destFolder, 'hello.txt'));
      final inner = File(p.join(destFolder, 'sub', 'inner.txt'));
      expect(await hello.exists(), isTrue);
      expect(await hello.readAsString(), 'שלום עולם');
      expect(await inner.exists(), isTrue);
      expect(await inner.readAsString(), 'פנימי');
    });

    test('זורק כשקובץ ה-ZIP אינו קיים', () async {
      await expectLater(
        service.extractZip(
          p.join(tempDir.path, 'missing.zip'),
          p.join(tempDir.path, 'out'),
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('זורק error.too_large כשהגודל המחולץ חורג מהתקרה', () async {
      final tinyLimit = PluginFsService(maxUncompressedBytes: 10);
      final zipPath = buildZip(p.join(tempDir.path, 'big.zip'), {
        'big.txt': 'תוכן ארוך מהתקרה של עשרה בייטים',
      });
      final destFolder = p.join(tempDir.path, 'out');

      await expectLater(
        tinyLimit.extractZip(zipPath, destFolder),
        throwsA(predicate((e) => e.toString().contains('error.too_large'))),
      );
    });

    test('זורק error.too_large כשמספר הרשומות חורג מהתקרה', () async {
      final fewEntries = PluginFsService(maxEntries: 1);
      final zipPath = buildZip(p.join(tempDir.path, 'many.zip'), {
        'a.txt': 'a',
        'b.txt': 'b',
      });
      final destFolder = p.join(tempDir.path, 'out');

      await expectLater(
        fewEntries.extractZip(zipPath, destFolder),
        throwsA(predicate((e) => e.toString().contains('error.too_large'))),
      );
    });

    test('מדלג על רשומה שיוצאת מתיקיית היעד (path-traversal)', () async {
      final zipPath = buildZip(p.join(tempDir.path, 'evil.zip'), {
        '../escaped.txt': 'ניסיון בריחה',
        'safe.txt': 'בטוח',
      });
      final destFolder = p.join(tempDir.path, 'out', 'nested');

      await service.extractZip(zipPath, destFolder);

      final escaped = File(p.join(tempDir.path, 'out', 'escaped.txt'));
      final safe = File(p.join(destFolder, 'safe.txt'));
      expect(await escaped.exists(), isFalse);
      expect(await safe.exists(), isTrue);
    });

    test(
      'חוסם יצירת תיקיות וכתיבה דרך symlink-תיקייה קיים שמצביע מחוץ ליעד',
      () async {
        final destFolder = p.join(tempDir.path, 'out');
        Directory(destFolder).createSync(recursive: true);
        final outside = Directory(p.join(tempDir.path, 'outside'))
          ..createSync();

        // יצירת symlink-תיקייה דורשת הרשאות בחלק מהפלטפורמות (Windows ללא
        // Developer Mode) — אם נכשלה, אין מה לבדוק.
        try {
          Link(p.join(destFolder, 'linkdir')).createSync(outside.path);
        } on FileSystemException {
          markTestSkipped('יצירת symlink אינה נתמכת בסביבה זו');
          return;
        }

        final zipPath = buildZip(p.join(tempDir.path, 'evil.zip'), {
          'linkdir/sub/evil.txt': 'בריחה דרך symlink',
        });

        await service.extractZip(zipPath, destFolder);

        // לא הקובץ ולא תיקיית האב שלו נוצרו מחוץ ליעד.
        expect(
          File(p.join(outside.path, 'sub', 'evil.txt')).existsSync(),
          isFalse,
        );
        expect(Directory(p.join(outside.path, 'sub')).existsSync(), isFalse);
      },
    );
  });

  group('PluginFsService.deleteFile', () {
    test('מוחק קובץ קיים', () async {
      final file = File(p.join(tempDir.path, 'x.txt'))
        ..writeAsStringSync('data');
      expect(await file.exists(), isTrue);

      await service.deleteFile(file.path);

      expect(await file.exists(), isFalse);
    });

    test('idempotent — אינו זורק כשהקובץ אינו קיים', () async {
      await service.deleteFile(p.join(tempDir.path, 'nope.txt'));
      // ללא חריגה — הצלחה שקטה.
    });

    test('זורק כשהנתיב הוא תיקייה', () async {
      final dir = Directory(p.join(tempDir.path, 'adir'))
        ..createSync(recursive: true);
      await expectLater(
        service.deleteFile(dir.path),
        throwsA(isA<Exception>()),
      );
    });
  });
}
