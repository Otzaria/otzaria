import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

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
    for (final compression in CompressionType.values) {
      String writeArchive(Archive archive) {
        final zipPath = p.join(tempDir.path, '${compression.name}.zip');
        File(zipPath).writeAsBytesSync(ZipEncoder().encodeBytes(archive));
        return zipPath;
      }

      ArchiveFile entry(String name, Uint8List bytes) =>
          ArchiveFile.bytes(name, bytes)..compression = compression;

      test(
        '${compression.name}: נתיבים מנורמלים זהים נכתבים לפי הסדר',
        () async {
          final last = Uint8List(17)..fillRange(0, 17, 2);
          final archive = Archive()
            ..add(entry('dir/same.bin', Uint8List(2 * 1024 * 1024)))
            ..add(entry('dir/./same.bin', last));
          final destFolder = p.join(tempDir.path, 'out');

          await service.extractZip(writeArchive(archive), destFolder);

          expect(
            File(p.join(destFolder, 'dir/same.bin')).readAsBytesSync(),
            last,
          );
        },
      );

      test('${compression.name}: גודל מוצהר שקרי מסיר פלט חלקי', () async {
        final archive = Archive()
          ..add(entry('large.bin', Uint8List(2 * 1024 * 1024)));
        final zipPath = writeArchive(archive);
        final bytes = File(zipPath).readAsBytesSync();
        final header = ByteData.sublistView(bytes);
        final end = bytes.length - 22;
        final central = header.getUint32(end + 16, Endian.little);
        header.setUint32(central + 24, 1, Endian.little);
        File(zipPath).writeAsBytesSync(bytes);
        final destFolder = p.join(tempDir.path, 'out');

        await expectLater(
          service.extractZip(zipPath, destFolder),
          throwsA(isA<ArchiveException>()),
        );

        expect(File(p.join(destFolder, 'large.bin')).existsSync(), isFalse);
      });

      if (compression != CompressionType.none) {
        test('${compression.name}: פענוח פגום מסיר פלט חלקי', () async {
          final archive = Archive()..add(entry('bad.bin', Uint8List(1024)));
          final zipPath = writeArchive(archive);
          final bytes = File(zipPath).readAsBytesSync();
          final header = ByteData.sublistView(bytes);
          final start =
              30 +
              header.getUint16(26, Endian.little) +
              header.getUint16(28, Endian.little);
          bytes.fillRange(start, start + 4, 0);
          File(zipPath).writeAsBytesSync(bytes);
          final destFolder = p.join(tempDir.path, 'out');

          await expectLater(
            service.extractZip(zipPath, destFolder),
            throwsA(isA<FormatException>()),
          );

          expect(File(p.join(destFolder, 'bad.bin')).existsSync(), isFalse);
        });
      }
    }

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

    test('ארכיון עם קובץ הרצה נדחה בלי לחלץ דבר', () async {
      final zipPath = buildZip(p.join(tempDir.path, 'a.zip'), {
        'readme.txt': 'קרא',
        'bin/OtzariaAIProxy.exe': 'MZ',
      });
      final destFolder = p.join(tempDir.path, 'out');

      await expectLater(
        service.extractZip(zipPath, destFolder),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('error.forbidden'),
          ),
        ),
      );
      expect(File(p.join(destFolder, 'readme.txt')).existsSync(), isFalse);
    });

    test('תיקיות רגילות עם סיומת קובץ אינן נחסמות בחילוץ', () async {
      final archive = Archive()
        ..add(ArchiveFile.directory('example.com/'))
        ..add(ArchiveFile.string('example.com/notes.txt', 'שלום'))
        ..add(ArchiveFile.string('tools.exe/sub/notes.txt', 'עולם'));
      final zipPath = p.join(tempDir.path, 'documents.zip');
      File(zipPath).writeAsBytesSync(ZipEncoder().encodeBytes(archive));
      final destFolder = p.join(tempDir.path, 'out');

      await service.extractZip(zipPath, destFolder);

      expect(
        File(p.join(destFolder, 'example.com/notes.txt')).readAsStringSync(),
        'שלום',
      );
      expect(
        File(p.join(destFolder, 'tools.exe/sub/notes.txt')).readAsStringSync(),
        'עולם',
      );
    });

    for (final extension in ['app', 'pkg']) {
      for (final explicitDirectory in [false, true]) {
        test(
          'תיקיית $extension חסומה לפני החילוץ: רשומה=$explicitDirectory',
          () async {
            final archive = Archive()
              ..add(ArchiveFile.string('readme.txt', 'מסמך'));
            if (explicitDirectory) {
              archive.add(
                ArchiveFile.directory('Tool.${extension.toUpperCase()} . /'),
              );
            } else {
              archive.add(
                ArchiveFile.string(
                  'Tool.$extension/Contents/notes.txt',
                  'מסמך',
                ),
              );
            }
            final zipPath = p.join(tempDir.path, 'bundle.zip');
            File(zipPath).writeAsBytesSync(ZipEncoder().encodeBytes(archive));
            final destFolder = p.join(tempDir.path, 'out');

            await expectLater(
              service.extractZip(zipPath, destFolder),
              throwsA(
                predicate((e) => e.toString().contains('error.forbidden')),
              ),
            );
            expect(Directory(destFolder).listSync(), isEmpty);
          },
        );
      }
    }

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

    test('חילוצים מקבילים ממופעים שונים אינם מערבבים קובץ משותף', () async {
      const size = 48 * 1024 * 1024;
      final zipPaths = <String>[];
      for (var value = 1; value <= 3; value++) {
        final bytes = Uint8List(size)..fillRange(0, size, value);
        final archive = Archive()..add(ArchiveFile('same.bin', size, bytes));
        final zipPath = p.join(tempDir.path, '$value.zip');
        File(zipPath).writeAsBytesSync(ZipEncoder().encode(archive, level: 0));
        zipPaths.add(zipPath);
      }
      final destFolder = p.join(tempDir.path, 'shared');
      for (var round = 0; round < 3; round++) {
        await Future.wait([
          for (final zipPath in zipPaths)
            PluginFsService().extractZip(zipPath, destFolder),
        ]);
        final result = File(p.join(destFolder, 'same.bin')).readAsBytesSync();
        expect(result.length, size);
        expect(result.first, inInclusiveRange(1, 3));
        expect(result.every((value) => value == result.first), isTrue);
      }
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('כשל בחילוץ אינו חוסם חילוצים ממתינים ליעדים שונים', () async {
      final zipPath = buildZip(p.join(tempDir.path, 'a.zip'), {
        'a.txt': 'שלום',
      });
      final failed = expectLater(
        PluginFsService(maxUncompressedBytes: 1).extractZip(
          zipPath,
          p.join(tempDir.path, 'failed'),
        ),
        throwsA(predicate((e) => e.toString().contains('error.too_large'))),
      );
      final destinations = [
        p.join(tempDir.path, 'first'),
        p.join(tempDir.path, 'second'),
      ];
      await Future.wait([
        failed,
        for (final dest in destinations)
          PluginFsService().extractZip(zipPath, dest),
      ]);
      for (final dest in destinations) {
        expect(File(p.join(dest, 'a.txt')).readAsStringSync(), 'שלום');
      }
    });

    test('ה-isolate הקורא ממשיך להגיב בזמן חילוץ קובץ גדול (#3398)', () async {
      final rng = Random(3398);
      final words = Uint32List(8 * 1024 * 1024);
      for (var i = 0; i < words.length; i++) {
        words[i] = 0x61616161 + (rng.nextInt(1 << 32) & 0x0f0f0f0f);
      }
      final bytes = words.buffer.asUint8List();
      final src = File(p.join(tempDir.path, 'big.bin'))
        ..writeAsBytesSync(bytes);
      final zipPath = p.join(tempDir.path, 'big.zip');
      final encoder = ZipFileEncoder()..create(zipPath);
      encoder.addFileSync(src, 'big.bin');
      encoder.closeSync();
      final destFolder = p.join(tempDir.path, 'out');

      var maxGapMs = 0;
      final sinceTick = Stopwatch()..start();
      final extractTime = Stopwatch()..start();
      final ticker = Timer.periodic(const Duration(milliseconds: 10), (_) {
        maxGapMs = max(maxGapMs, sinceTick.elapsedMilliseconds);
        sinceTick.reset();
      });
      try {
        await service.extractZip(zipPath, destFolder);
      } finally {
        ticker.cancel();
        extractTime.stop();
      }

      expect(File(p.join(destFolder, 'big.bin')).lengthSync(), bytes.length);
      // יחסי ולא מוחלט: בחילוץ על ה-isolate הקורא הפער שווה לכל זמן החילוץ.
      expect(maxGapMs, lessThan(extractTime.elapsedMilliseconds ~/ 3));
    }, timeout: const Timeout(Duration(minutes: 2)));
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

  group('PluginFsService.deleteFolder', () {
    test('מוחקת תיקייה על כל תוכנה', () async {
      final dir = Directory(p.join(tempDir.path, 'coll'))
        ..createSync(recursive: true);
      File(p.join(dir.path, 'a.txt')).writeAsStringSync('x');
      Directory(p.join(dir.path, 'sub')).createSync();
      File(p.join(dir.path, 'sub', 'b.txt')).writeAsStringSync('y');

      await service.deleteFolder(dir.path);

      expect(await dir.exists(), isFalse);
    });

    test('idempotent — אינה זורקת כשהתיקייה אינה קיימת', () async {
      await service.deleteFolder(p.join(tempDir.path, 'nope'));
    });

    test('זורקת כשהנתיב הוא קובץ', () async {
      final file = File(p.join(tempDir.path, 'x.txt'))
        ..writeAsStringSync('data');
      await expectLater(
        service.deleteFolder(file.path),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('PluginFsService.moveEntry', () {
    test('שינוי שם תיקייה לסיומת קובץ שומר את תוכנה', () async {
      final from = Directory(p.join(tempDir.path, 'documents'))..createSync();
      File(p.join(from.path, 'notes.txt')).writeAsStringSync('שלום');
      final to = p.join(tempDir.path, 'example.com');

      await service.moveEntry(from.path, to);

      expect(from.existsSync(), isFalse);
      expect(File(p.join(to, 'notes.txt')).readAsStringSync(), 'שלום');
    });

    for (final extension in ['app', 'pkg']) {
      test('שינוי שם תיקייה ל-$extension חסום והמקור נשמר', () async {
        final from = Directory(p.join(tempDir.path, 'documents'))..createSync();
        File(p.join(from.path, 'notes.txt')).writeAsStringSync('שלום');
        final to = p.join(tempDir.path, 'Tool.${extension.toUpperCase()} . ');

        await expectLater(
          service.moveEntry(from.path, to),
          throwsA(predicate((e) => e.toString().contains('error.forbidden'))),
        );

        expect(File(p.join(from.path, 'notes.txt')).readAsStringSync(), 'שלום');
        expect(Directory(to).existsSync(), isFalse);
      });
    }

    test('מזיזה תיקייה עם תוכנה ליעד חדש', () async {
      final from = Directory(p.join(tempDir.path, 'old_name'))
        ..createSync(recursive: true);
      File(p.join(from.path, 'a.txt')).writeAsStringSync('שלום');
      Directory(p.join(from.path, 'sub')).createSync();
      File(p.join(from.path, 'sub', 'b.txt')).writeAsStringSync('עולם');

      final to = p.join(tempDir.path, 'new_name');
      await service.moveEntry(from.path, to);

      expect(await from.exists(), isFalse);
      expect(File(p.join(to, 'a.txt')).readAsStringSync(), 'שלום');
      expect(File(p.join(to, 'sub', 'b.txt')).readAsStringSync(), 'עולם');
    });

    test('מזיזה קובץ בודד ליעד חדש, כולל יצירת תיקיית האב', () async {
      final from = File(p.join(tempDir.path, 'a.txt'))
        ..writeAsStringSync('data');
      final to = p.join(tempDir.path, 'nested', 'deeper', 'a.txt');

      await service.moveEntry(from.path, to);

      expect(await from.exists(), isFalse);
      expect(File(to).readAsStringSync(), 'data');
    });

    test('שינוי שם לקובץ הרצה נדחה והמקור נשאר', () async {
      final from = File(p.join(tempDir.path, 'proxy.bin'))
        ..writeAsStringSync('MZ');

      await expectLater(
        service.moveEntry(from.path, p.join(tempDir.path, 'proxy.exe')),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('error.forbidden'),
          ),
        ),
      );
      expect(from.existsSync(), isTrue);
    });

    test('זורקת error.not_found כשהמקור אינו קיים', () async {
      await expectLater(
        service.moveEntry(
          p.join(tempDir.path, 'nope'),
          p.join(tempDir.path, 'dest'),
        ),
        throwsA(
          predicate(
            (e) => e is Exception && e.toString().contains('error.not_found'),
          ),
        ),
      );
    });

    test('זורקת error.invalid_params ולא דורסת כשהיעד כבר קיים', () async {
      final from = File(p.join(tempDir.path, 'a.txt'))
        ..writeAsStringSync('new content');
      final to = File(p.join(tempDir.path, 'b.txt'))
        ..writeAsStringSync('existing content');

      await expectLater(
        service.moveEntry(from.path, to.path),
        throwsA(
          predicate(
            (e) =>
                e is Exception && e.toString().contains('error.invalid_params'),
          ),
        ),
      );
      // היעד הקיים לא נדרס, והמקור לא נמחק.
      expect(to.readAsStringSync(), 'existing content');
      expect(await from.exists(), isTrue);
    });

    test('דוחה יעד שהוא צאצא של תיקיית המקור בלי ליצור אותו', () async {
      final from = Directory(p.join(tempDir.path, 'source'))
        ..createSync(recursive: true);
      File(p.join(from.path, 'data.txt')).writeAsStringSync('נשאר במקום');
      final to = p.join(from.path, 'child', 'moved');

      await expectLater(
        service.moveEntry(from.path, to),
        throwsA(
          predicate(
            (e) =>
                e is Exception && e.toString().contains('error.invalid_params'),
          ),
        ),
      );

      expect(
        File(p.join(from.path, 'data.txt')).readAsStringSync(),
        'נשאר במקום',
      );
      expect(Directory(to).existsSync(), isFalse);
    });

    test(
      'שומרת קישור סמלי בעת מעבר בין כרכים כשנתמכת תיקיית tmpfs',
      () async {
        final sharedMemory = Directory('/dev/shm');
        if (!Platform.isLinux || !sharedMemory.existsSync()) {
          markTestSkipped('אין בסביבה זו כרך tmpfs נפרד לבדיקת EXDEV');
          return;
        }

        final from = Directory(p.join(tempDir.path, 'source'))
          ..createSync(recursive: true);
        File(p.join(from.path, 'data.txt')).writeAsStringSync('תוכן');
        try {
          Link(p.join(from.path, 'pointer')).createSync('data.txt');
        } on FileSystemException {
          markTestSkipped('יצירת symlink אינה נתמכת בסביבה זו');
          return;
        }

        final targetRoot = await sharedMemory.createTemp('otzaria_fs_move_');
        final to = p.join(targetRoot.path, 'moved');
        try {
          await service.moveEntry(from.path, to);

          final copiedLink = Link(p.join(to, 'pointer'));
          expect(await copiedLink.exists(), isTrue);
          expect(await copiedLink.target(), 'data.txt');
          expect(File(p.join(to, 'data.txt')).readAsStringSync(), 'תוכן');
        } finally {
          if (await targetRoot.exists()) {
            await targetRoot.delete(recursive: true);
          }
        }
      },
    );
  });
}
