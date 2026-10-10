import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/empty_library/services/library_package/library_package.dart';
import 'package:otzaria/empty_library/services/library_package/library_package_importer.dart';
import 'package:otzaria/empty_library/services/library_package/package_folder.dart';
import 'package:otzaria/empty_library/services/library_space_estimate.dart';
import 'package:otzaria/utils/file/disk_free_space.dart';
import 'package:path/path.dart' as p;

import '../support/zstd_test_lib.dart';
import 'library_package_test_support.dart';

const _gib = 1 << 30;
const _currentDbBytes = 3738877952;

/// כותרת frame עם Frame_Content_Size של 8 בייטים, בלי Single_Segment.
List<int> _header(int contentSize) => [
  0x28, 0xB5, 0x2F, 0xFD, 0xC0, 0x00, //
  for (var i = 0; i < 8; i++) (contentSize >> (8 * i)) & 0xFF,
];

void main() {
  group('zstdFrameContentSize', () {
    test('קורא גודל של 8 בייטים', () {
      expect(zstdFrameContentSize(_header(_currentDbBytes)), _currentDbBytes);
    });

    test('שדה של שני בייטים מוסט ב-256', () {
      // descriptor 0x40: FCS של 2 בייטים, window descriptor אחריו.
      expect(
        zstdFrameContentSize([0x28, 0xB5, 0x2F, 0xFD, 0x40, 0, 1, 0]),
        257,
      );
    });

    test('Single_Segment בלי דגל FCS: בייט אחד, בלי window descriptor', () {
      expect(zstdFrameContentSize([0x28, 0xB5, 0x2F, 0xFD, 0x20, 200]), 200);
    });

    test('מדלג על Dictionary_ID', () {
      // FCS של 4 בייטים + Dictionary_ID של בייט אחד.
      expect(
        zstdFrameContentSize([0x28, 0xB5, 0x2F, 0xFD, 0x81, 0, 7, 1, 0, 0, 0]),
        1,
      );
    });

    test('דחיסה מצינור (בלי FCS) או בייטים שאינם zstd — לא ידוע', () {
      expect(
        zstdFrameContentSize([0x28, 0xB5, 0x2F, 0xFD, 0x00, 0x00]),
        isNull,
      );
      expect(zstdFrameContentSize([0x50, 0x4B, 0x03, 0x04, 0, 0]), isNull);
      expect(zstdFrameContentSize(_header(5).sublist(0, 8)), isNull);
    });

    final lib = openZstdForTests();
    test('תואם את מה ש-libzstd כותב', () async {
      final data = Uint8List(300000);
      final archive = zstdCompress(lib!, data);
      expect(
        await readZstdArchiveContentSize(
          Stream.value(archive),
          compressedSize: archive.length,
        ),
        data.length,
      );
    }, skip: lib == null ? 'libzstd אינו זמין' : false);
  });

  group('extractedSizeOf', () {
    test('גודל ארכיון מלא גובר על האומדן', () {
      expect(
        extractedSizeOf(
          1807000000,
          archiveContentSize: _currentDbBytes,
          fallbackRatio: ExpansionFallback.database,
        ),
        _currentDbBytes,
      );
    });

    test('בלי גודל מלא — האומדן', () {
      expect(extractedSizeOf(1000000, fallbackRatio: 2.5), 2500000);
    });

    test('גודל מלא קטן מהארכיון עדיין ידוע, כולל תוכן ריק', () {
      for (final known in [0, 1000]) {
        expect(
          extractedSizeOf(
            1000000,
            archiveContentSize: known,
            fallbackRatio: 2.5,
          ),
          known,
        );
      }
    });

    test('יחסי האומדן אינם קטנים מהיחסים שנמדדו', () {
      expect(ExpansionFallback.database, greaterThanOrEqualTo(3739 / 1807));
      expect(ExpansionFallback.searchIndex, greaterThanOrEqualTo(2413 / 1725));
      expect(ExpansionFallback.catalog, greaterThanOrEqualTo(37.6 / 6));
      expect(ExpansionFallback.pdfArchive, greaterThanOrEqualTo(473.5 / 472));
    });
  });

  group('הורדה', () {
    test('על אותו כונן: ההורדה ועוד שיא החילוץ — כ-6GB ולא 8GB', () {
      final download = measuredLibraryDownload.fold<int>(
        0,
        (sum, s) => sum + s.compressed,
      );
      final peak = peakExtractionGrowth(measuredLibraryDownload);
      // ה-DB מחולץ ראשון; כשהוא נמחק החילוצים הבאים קטנים ממנו.
      expect(peak, _currentDbBytes);
      final need = withSafetyMargin(download + peak);
      expect(need, greaterThan(6 * 1000 * 1000 * 1000));
      expect(need, lessThan(7 * _gib));
    });

    test('שיא החילוץ כשהנכס הגדול אחרון', () {
      expect(
        peakExtractionGrowth([
          (compressed: 10, extracted: 20),
          (compressed: 100, extracted: 300),
        ]),
        310,
      );
    });

    test('מרווח הביטחון: לפחות 256MiB, ו-5% בנפחים גדולים', () {
      expect(withSafetyMargin(0), 0);
      expect(withSafetyMargin(1000), 1000 + (256 << 20));
      expect(withSafetyMargin(100 * _gib), 105 * _gib);
    });
  });

  group('FAT32', () {
    test('ה-DB הנוכחי (3.74GB) מותר', () {
      expect(exceedsFat32FileLimit(_currentDbBytes), isFalse);
      expect(exceedsFat32FileLimit(fat32MaxFileBytes), isFalse);
    });

    test('DB של 4.5GB נחסם', () {
      expect(exceedsFat32FileLimit(4500000000), isTrue);
    });

    test('כרטיס FAT32 בבורר המיקום נחסם רק כשה-DB חורג', () {
      expect(
        volumeCanHoldLibrary(
          supportsLargeFiles: false,
          largestFileBytes: _currentDbBytes,
        ),
        isTrue,
      );
      expect(
        volumeCanHoldLibrary(
          supportsLargeFiles: false,
          largestFileBytes: 4500000000,
        ),
        isFalse,
      );
      expect(
        volumeCanHoldLibrary(
          supportsLargeFiles: true,
          largestFileBytes: 4500000000,
        ),
        isTrue,
      );
    });

    test('גודל ה-DB המותקן, או הגודל שנמדד כשאין ספרייה', () async {
      final books = Directory.systemTemp.createTempSync('installed_db');
      addTearDown(() => books.deleteSync(recursive: true));
      expect(await installedDatabaseBytes(''), measuredDatabaseBytes);
      expect(await installedDatabaseBytes(books.path), measuredDatabaseBytes);
      File(p.join(books.path, 'seforim.db')).writeAsBytesSync([1, 2, 3]);
      expect(await installedDatabaseBytes(books.path), 3);
    });

    test('גודל לא ידוע אינו חוסם', () {
      expect(exceedsFat32FileLimit(null), isFalse);
    });
  });

  group('comparableVolumeId', () {
    test('באנדרואיד /data ו-/storage/emulated הם אותו כונן', () {
      String? id(String path, String df) =>
          comparableVolumeId(path, df, isAndroid: true);
      expect(
        id('/data/user/0/com.otzaria/cache', '/dev/block/dm-5'),
        id('/storage/emulated/0/Android/data/com.otzaria/files', '/dev/fuse'),
      );
      expect(
        id('/storage/1234-ABCD/Android/data/com.otzaria', '/dev/fuse'),
        '/dev/fuse',
      );
    });

    test('מחוץ לאנדרואיד, או כש-df נכשל — ללא שינוי', () {
      expect(comparableVolumeId('/data/x', 'C:', isAndroid: false), 'C:');
      expect(comparableVolumeId('/data/x', null, isAndroid: true), isNull);
    });
  });

  group('insufficientSpaceMessage', () {
    test('מאחד מיקומים על אותו כונן ומציג נדרש מול פנוי', () {
      final message = insufficientSpaceMessage([
        const VolumeSpaceNeed(
          label: 'הספרייה',
          volumeId: 'a',
          requiredBytes: 600 << 20,
          freeBytes: 1000 << 20,
        ),
        const VolumeSpaceNeed(
          label: 'אינדקס החיפוש',
          volumeId: 'a',
          requiredBytes: 600 << 20,
          freeBytes: 1000 << 20,
        ),
      ]);
      expect(message, contains('הספרייה + אינדקס החיפוש'));
      expect(message, contains('1200 MB'));
      expect(message, contains('1000 MB'));
    });

    test('מקום לא ידוע אינו חוסם', () {
      expect(
        insufficientSpaceMessage([
          const VolumeSpaceNeed(
            label: 'הספרייה',
            volumeId: null,
            requiredBytes: 1 << 40,
            freeBytes: -1,
          ),
        ]),
        isNull,
      );
    });
  });

  group('LibraryPackageImporter.checkSpace', () {
    late Directory source;

    setUp(() => source = Directory.systemTemp.createTempSync('space_check'));
    tearDown(() => source.deleteSync(recursive: true));

    LibraryPackage package(
      LibraryPackageKind kind,
      int compressedSize, {
      int? contentSize,
    }) {
      final name = 'otzaria-1.0.0-${kind.assetSuffix}.tar.zst';
      File(
        p.join(source.path, name),
      ).writeAsBytesSync(
        contentSize == null ? [0, 0, 0, 0] : _header(contentSize),
      );
      return LibraryPackage(
        kind: kind,
        version: '1.0.0',
        archiveName: name,
        parts: [
          LibraryPackagePart(
            entry: PackageFileEntry(name: name, size: compressedSize),
          ),
        ],
      );
    }

    LibraryPackageSet packages({bool withIndex = true}) => LibraryPackageSet(
      folder: DirectoryPackageFolder(source.path),
      library: package(
        LibraryPackageKind.library,
        1807000000,
        contentSize: _currentDbBytes,
      ),
      index: withIndex
          ? package(LibraryPackageKind.searchIndex, 1725000000)
          : null,
    );

    LibraryPackageImporter importer(Map<String, DiskSpaceInfo> volumes) =>
        LibraryPackageImporter(diskSpace: (path) async => volumes[path]!);

    test('בלי אינדקס: אומדן הספרייה בלבד נדרש', () async {
      await expectLater(
        importer({
          'books': const DiskSpaceInfo(volumeId: 'sd', freeBytes: 4 * _gib),
        }).checkSpace(packages(withIndex: false), 'books', null),
        throwsA(isA<InsufficientSpaceException>()),
      );
      await importer({
        'books': const DiskSpaceInfo(volumeId: 'sd', freeBytes: 5 * _gib),
      }).checkSpace(packages(withIndex: false), 'books', null);
    });

    test('אינדקס בכונן נפרד שחסר בו מקום — נחסם רק הוא', () async {
      final error =
          await importer({
                'books': const DiskSpaceInfo(
                  volumeId: 'sd',
                  freeBytes: 5 * _gib,
                ),
                'index': const DiskSpaceInfo(
                  volumeId: 'int',
                  freeBytes: 2 * _gib,
                ),
              })
              .checkSpace(packages(), 'books', 'index')
              .then<Object?>(
                (_) => null,
                onError: (Object e) => e,
              );
      expect(error, isA<InsufficientSpaceException>());
      final shortfalls = (error! as InsufficientSpaceException).shortfalls;
      expect(shortfalls.single.label, startsWith('אינדקס החיפוש'));
      // בלי כותרת: 1.725GB × 1.6 ועוד מרווח.
      expect(shortfalls.single.requiredBytes, greaterThan(2760000000));
      expect('$error', contains('אין מספיק מקום'));
    });

    test('על אותו כונן נדרש סכום שניהם', () async {
      final volumes = {
        'books': const DiskSpaceInfo(volumeId: 'int', freeBytes: 6 * _gib),
        'index': const DiskSpaceInfo(volumeId: 'int', freeBytes: 6 * _gib),
      };
      await expectLater(
        importer(volumes).checkSpace(packages(), 'books', 'index'),
        throwsA(isA<InsufficientSpaceException>()),
      );
      await importer(
        volumes,
      ).checkSpace(packages(withIndex: false), 'books', null);
    });
  });
}
