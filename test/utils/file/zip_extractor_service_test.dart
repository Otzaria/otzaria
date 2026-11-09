import 'dart:async';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/utils/file/zip_extractor_service.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('zip_extractor_test'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('מסלול הספרייה מחלץ ZIP ושומר את המקור לפי בחירת המשתמש', () async {
    final zip = File(p.join(tmp.path, 'ספרים.zip'))
      ..writeAsBytesSync(
        ZipEncoder().encodeBytes(
          Archive()..add(ArchiveFile.string('ספרים/ספר.txt', 'שלום עולם')),
        ),
      );
    final target = p.join(tmp.path, 'out');
    final result = await ZipExtractorService.checkAndExtractZipIfNeeded(
      tmp.path,
      outputDirectoryPath: target,
      onAskDeleteZip: () async => false,
    );
    expect(result.successfullyExtracted, isTrue);
    expect(
      File(p.join(target, 'ספרים/ספר.txt')).readAsStringSync(),
      'שלום עולם',
    );
    expect(zip.existsSync(), isTrue);
  });

  test('חילוץ חלופי חוסם נתיב שמנסה לברוח מתיקיית היעד', () async {
    final zip = File(p.join(tmp.path, 'unsafe.zip'))
      ..writeAsBytesSync(
        ZipEncoder().encodeBytes(
          Archive()..addFile(ArchiveFile.string('../outside.txt', 'escaped')),
        ),
      );
    final target = p.join(tmp.path, 'target');
    await expectLater(
      ZipExtractorService.extractManuallyInIsolate(zip.path, target, null),
      throwsA(isA<FormatException>()),
    );
    expect(File(p.join(tmp.path, 'outside.txt')).existsSync(), isFalse);
  });

  test('חילוץ חלופי מסוגל לחלץ קובץ גדול מתוך ZIP', () async {
    final bytes = List<int>.generate(3 * 1024 * 1024, (i) => i & 0xff);
    final zip = File(p.join(tmp.path, 'large.zip'))
      ..writeAsBytesSync(ZipEncoder().encodeBytes(
        Archive()..addFile(ArchiveFile.bytes('assets/data.bin', bytes)),
      ));
    final target = p.join(tmp.path, 'target');
    final updates = <double>[];
    await ZipExtractorService.extractManuallyInIsolate(
      zip.path,
      target,
      (progress, message) => updates.add(progress),
    );
    expect(File(p.join(target, 'assets', 'data.bin')).readAsBytesSync(),
        bytes);
    expect(updates, isNotEmpty);
    expect(updates.last, lessThanOrEqualTo(1.0));
  });

  // בדיאלוג החילוץ onProgress לוכד את ה-State — אסור שייגרר ל-isolate.
  test('חילוץ חלופי עם onProgress שלוכד אובייקט לא-sendable', () async {
    final archive = Archive()
      ..addFile(ArchiveFile.string('book.txt', 'שלום עולם'));
    final zipPath = p.join(tmp.path, 'books.zip');
    File(zipPath).writeAsBytesSync(ZipEncoder().encode(archive));
    final outDir = p.join(tmp.path, 'out');
    final unsendable = Completer<void>();

    await ZipExtractorService.extractManuallyInIsolate(
      zipPath,
      outDir,
      (progress, message) => unsendable.isCompleted,
    );

    expect(File(p.join(outDir, 'book.txt')).readAsStringSync(), 'שלום עולם');
  });
}
