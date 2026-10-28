import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/utils/file/archive_extractor.dart';
import 'package:path/path.dart' as p;

const _fileSizeMb = 16;

void main() {
  late Directory tempDir;
  late String tarPath;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('archive_extractor_test');
    final source = Directory('${tempDir.path}/source')
      ..createSync(recursive: true);
    final chunk = Uint8List(1024 * 1024);
    final raf = File(
      '${source.path}/big.bin',
    ).openSync(mode: FileMode.writeOnly);
    for (var i = 0; i < _fileSizeMb; i++) {
      raf.writeFromSync(chunk);
    }
    raf.closeSync();
    tarPath = '${tempDir.path}/archive.tar';
    await TarFileEncoder().tarDirectory(source, filename: tarPath);
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  String writeZip(Archive archive) {
    final bytes = ZipEncoder().encodeBytes(archive);
    final data = ByteData.sublistView(bytes);
    // מסמנים יוצר UNIX כדי שהמקודד יאפשר לבדוק קישורים גם ב-Windows.
    for (var i = 0; i + 46 <= bytes.length; i++) {
      if (data.getUint32(i, Endian.little) == 0x02014b50) bytes[i + 5] = 3;
    }
    final zip = p.join(tempDir.path, 'ספרייה.ZIP');
    File(zip).writeAsBytesSync(bytes);
    return zip;
  }

  test('ZIP מחלץ שם עברי, תוכן בכמה נתחים ותיקייה ריקה', () async {
    final bytes = Uint8List.fromList(
      List.generate(3 * 1024 * 1024 + 123, (i) => i % 251),
    );
    final zip = writeZip(
      Archive()
        ..add(ArchiveFile.bytes('ספרים/ספר.bin', bytes))
        ..add(ArchiveFile.directory('ריק/'))
        ..add(ArchiveFile.bytes('אפס.txt', [])),
    );
    final target = p.join(tempDir.path, 'out');
    await extractArchiveFileToDisk(zip, target);
    expect(File(p.join(target, 'ספרים/ספר.bin')).readAsBytesSync(), bytes);
    expect(Directory(p.join(target, 'ריק')).existsSync(), isTrue);
    expect(File(p.join(target, 'אפס.txt')).lengthSync(), 0);
  });

  test('ZIP מדלג על נתיבים שיוצאים מתיקיית היעד', () async {
    final target = p.join(tempDir.path, 'out');
    final outside = p.join(tempDir.path, 'outside.txt');
    final zip = writeZip(
      Archive()
        ..add(ArchiveFile.string('../escape.txt', 'bad'))
        ..add(ArchiveFile.string(outside, 'bad'))
        ..add(ArchiveFile.string('../out-other/escape.txt', 'bad'))
        ..add(ArchiveFile.string('safe.txt', 'שלום')),
    );
    await extractArchiveFileToDisk(zip, target);
    expect(File(p.join(tempDir.path, 'escape.txt')).existsSync(), isFalse);
    expect(File(outside).existsSync(), isFalse);
    expect(Directory(p.join(tempDir.path, 'out-other')).existsSync(), isFalse);
    expect(File(p.join(target, 'safe.txt')).readAsStringSync(), 'שלום');
  });

  test('ZIP אינו יוצר קישור אל מחוץ לשורש', () async {
    final zip = writeZip(
      Archive()..add(ArchiveFile.string('escape', '../outside')..mode = 0xa1ff),
    );
    final target = p.join(tempDir.path, 'out');
    await extractArchiveFileToDisk(zip, target);
    expect(
      FileSystemEntity.typeSync(p.join(target, 'escape'), followLinks: false),
      FileSystemEntityType.notFound,
    );
  });

  test('ZIP דוחה שרשרת קישורים שיכולה להוביל מחוץ לשורש', () async {
    final zip = writeZip(
      Archive()
        ..add(ArchiveFile.string('d', '.')..mode = 0xa1ff)
        ..add(ArchiveFile.string('d/e', '..')..mode = 0xa1ff)
        ..add(ArchiveFile.string('e/book.txt', 'שלום')),
    );
    final target = p.join(tempDir.path, 'out');
    await extractArchiveFileToDisk(zip, target);
    expect(File(p.join(tempDir.path, 'book.txt')).existsSync(), isFalse);
    expect(File(p.join(target, 'e/book.txt')).readAsStringSync(), 'שלום');
  }, skip: Platform.isWindows ? 'יצירת symlink דורשת הרשאה ב-Windows' : false);

  test('ZIP משמר קישור פנימי והרשאת הרצה', () async {
    final zip = writeZip(
      Archive()
        ..add(ArchiveFile.string('alias', 'run')..mode = 0xa1ff)
        ..add(ArchiveFile.string('run', '#!/bin/sh\n')..mode = 0x81ed),
    );
    final target = p.join(tempDir.path, 'out');
    await extractArchiveFileToDisk(zip, target);
    expect(Link(p.join(target, 'alias')).targetSync(), 'run');
    expect(File(p.join(target, 'run')).statSync().mode & 0x1ff, 0x1ed);
  }, skip: Platform.isWindows ? 'הרשאות וקישורים נבדקים ב-POSIX' : false);

  test('ZIP פגום מסיר פלט חלקי ומשחרר את הארכיון', () async {
    final zip = writeZip(
      Archive()..add(
        ArchiveFile.bytes(
          'bad.bin',
          Uint8List(3 * 1024 * 1024),
        ),
      ),
    );
    final bytes = File(zip).readAsBytesSync();
    final data = ByteData.sublistView(bytes);
    for (var i = 0; i + 46 <= bytes.length; i++) {
      if (data.getUint32(i, Endian.little) == 0x02014b50) {
        data.setUint32(i + 24, 1024 * 1024 + 1, Endian.little);
      }
    }
    File(zip).writeAsBytesSync(bytes);
    final target = p.join(tempDir.path, 'out');
    await expectLater(
      extractArchiveFileToDisk(zip, target),
      throwsA(isA<ArchiveException>()),
    );
    expect(File(p.join(target, 'bad.bin')).existsSync(), isFalse);
    File(zip).deleteSync();
  });

  test('מחלץ את תוכן הארכיון אל תיקיית היעד', () async {
    final target = '${tempDir.path}/out';

    await extractArchiveFileToDisk(tarPath, target);

    final extracted = File('$target/source/big.bin');
    expect(extracted.existsSync(), isTrue);
    expect(extracted.lengthSync(), _fileSizeMb * 1024 * 1024);
  });

  test('אינו חוסם את לולאת ההודעות של ה-isolate הקורא', () async {
    final target = '${tempDir.path}/out';

    // חילוץ על ה-isolate הקורא אינו מאפשר לספירה להתקדם בזמן הפענוח.
    var eventLoopTurns = 0;
    var keepSpinning = true;
    Future<void> spin() async {
      while (keepSpinning) {
        await Future<void>.delayed(Duration.zero);
        eventLoopTurns++;
      }
    }

    final spinner = spin();
    await extractArchiveFileToDisk(tarPath, target);
    keepSpinning = false;
    await spinner;

    expect(File('$target/source/big.bin').existsSync(), isTrue);
    expect(eventLoopTurns, greaterThan(20));
  });

  test('שגיאת חילוץ חוצה את גבול ה-isolate עם הטיפוס המקורי', () async {
    await expectLater(
      extractArchiveFileToDisk(
        '${tempDir.path}/missing.tar',
        '${tempDir.path}/out',
      ),
      throwsA(isA<FileSystemException>()),
    );
    await expectLater(
      extractArchiveFileToDisk(
        '${tempDir.path}/archive',
        '${tempDir.path}/out',
      ),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('כל החילוצים ב-lib עוברים דרך extractArchiveFileToDisk', () {
    const helperPath = 'lib/utils/file/archive_extractor.dart';
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final relative = entity.path.replaceAll(r'\', '/');
      if (relative.endsWith(helperPath)) continue;
      if (entity.readAsStringSync().contains('extractFileToDisk(')) {
        offenders.add(relative);
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'קריאה ישירה ל-extractFileToDisk חוסמת את ה-isolate הקורא — '
          'יש לקרוא ל-extractArchiveFileToDisk',
    );
  });
}
