import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/empty_library/services/library_package/library_package_importer.dart';
import 'package:otzaria/empty_library/services/library_package/library_source.dart';
import 'package:otzaria/empty_library/services/library_package/package_folder.dart';
import 'package:otzaria/empty_library/services/library_space_estimate.dart';
import 'package:otzaria/utils/file/disk_free_space.dart';
import 'package:path/path.dart' as p;

import '../support/zstd_test_lib.dart';
import 'library_package_test_support.dart';

void main() {
  final lib = openZstdForTests();
  final skip = lib == null ? 'libzstd אינו זמין' : false;

  test('מחבר את כל ה-frames גם מעבר לגבולות נתחים וחלקים', () async {
    final archive = [
      ...zstdCompress(lib!, Uint8List(300000)),
      ...zstdCompress(lib, Uint8List(400000)),
    ];
    expect(
      await readZstdArchiveContentSize(
        Stream.fromIterable(archive.map((byte) => [byte])),
        compressedSize: archive.length,
      ),
      700000,
    );
    final source = await Directory.systemTemp.createTemp('multi-frame-parts');
    addTearDown(() => source.delete(recursive: true));
    writeSplitAsset(
      source,
      'seforim.db.zst',
      Uint8List.fromList(archive),
      partSize: 1,
    );
    final scan = await scanRawLibraryAssets(
      DirectoryPackageFolder(source.path),
    );
    final importer = LibraryPackageImporter(
      diskSpace: (_) async =>
          DiskSpaceInfo(volumeId: 'a', freeBytes: withSafetyMargin(699999)),
    );
    await expectLater(
      importer.checkRawSpace(scan, 'books'),
      throwsA(isA<InsufficientSpaceException>()),
    );
  }, skip: skip);

  test('skippable לפני ובין frames אינו מוסיף לפלט', () async {
    const skippable = [0x50, 0x2A, 0x4D, 0x18, 3, 0, 0, 0, 1, 2, 3];
    final archive = [
      ...skippable,
      ...zstdCompress(lib!, Uint8List(300000)),
      ...skippable,
      ...zstdCompress(lib, Uint8List(400000)),
      ...skippable,
    ];
    expect(
      await readZstdArchiveContentSize(
        Stream.value(archive),
        compressedSize: archive.length,
      ),
      700000,
    );
    for (final length in [archive.length - 1, archive.length + 1]) {
      expect(
        await readZstdArchiveContentSize(
          Stream.value(archive),
          compressedSize: length,
        ),
        isNull,
      );
    }
  }, skip: skip);

  test('frame בלי FCS או ארכיון קטוע נשארים לא ידועים', () async {
    const noFcs = [0x28, 0xB5, 0x2F, 0xFD, 0, 0, 9, 0, 0, 65];
    expect(
      await readZstdArchiveContentSize(
        Stream.value(noFcs),
        compressedSize: noFcs.length,
      ),
      isNull,
    );
    final archive = zstdCompress(lib!, Uint8List(300000));
    final truncated = archive.sublist(0, archive.length - 1);
    expect(
      await readZstdArchiveContentSize(
        Stream.value(truncated),
        compressedSize: truncated.length,
      ),
      isNull,
    );
  }, skip: skip);

  test('FCS שאינו ניתן לייצוג או סכום שגולש נשאר לא ידוע', () async {
    List<int> frame(List<int> size) => [
      0x28,
      0xB5,
      0x2F,
      0xFD,
      0xC0,
      0,
      ...size,
      1,
      0,
      0,
    ];
    final unsigned = frame(List.filled(8, 255));
    final signed = frame([...List.filled(7, 255), 127]);
    for (final archive in [
      unsigned,
      [...signed, ...signed],
    ]) {
      expect(
        await readZstdArchiveContentSize(
          Stream.value(archive),
          compressedSize: archive.length,
        ),
        isNull,
      );
    }
  });

  test('מקור גדול מהתקרה אינו נקרא ואומדן אינו מוכיח גודל ל-FAT32', () async {
    var read = false;
    Stream<List<int>> stream() async* {
      read = true;
      yield [0];
    }

    final known = await readZstdArchiveContentSize(
      stream(),
      compressedSize: zstdSizeProbeMaxBytes + 1,
    );
    expect(known, isNull);
    expect(read, isFalse);
    expect(
      extractedSizeOf(
        1807000000,
        archiveContentSize: known,
        fallbackRatio: ExpansionFallback.database,
      ),
      greaterThan(fat32MaxFileBytes),
    );
    expect(exceedsFat32FileLimit(known), isFalse);
    expect(
      volumeCanHoldLibrary(
        supportsLargeFiles: false,
        largestFileBytes: measuredDatabaseBytes,
      ),
      isTrue,
    );
  });

  test('תיקיית תלמוד מחולצת נספרת בבדיקת המקום', () async {
    final source = await Directory.systemTemp.createTemp('directory-space');
    addTearDown(() => source.delete(recursive: true));
    final talmud = Directory(
      p.join(source.path, DatabaseConstants.talmudBavliFolderName),
    );
    await talmud.create();
    await File(p.join(talmud.path, 'ברכות.pdf')).writeAsBytes([1, 2, 3]);
    final scan = await scanRawLibraryAssets(
      DirectoryPackageFolder(source.path),
    );
    final importer = LibraryPackageImporter(
      diskSpace: (_) async => const DiskSpaceInfo(volumeId: 'a', freeBytes: 2),
    );
    await expectLater(
      importer.checkRawSpace(scan, 'books'),
      throwsA(isA<InsufficientSpaceException>()),
    );
  });
}
