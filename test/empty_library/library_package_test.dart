import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/empty_library/services/library_package/library_package.dart';
import 'package:otzaria/empty_library/services/library_package/library_package_extractor.dart';
import 'package:otzaria/empty_library/services/library_package/package_folder.dart';
import 'package:otzaria/utils/file/zstd_patch_decoder.dart';
import 'package:path/path.dart' as p;

import '../support/zstd_test_lib.dart';
import 'library_package_test_support.dart';

const _library = 'otzaria-0.9.98-library.tar.zst';
const _index = 'otzaria-0.9.98-library-index.tar.zst';

Uint8List _noise(int length, int seed) {
  final random = Random(seed);
  return Uint8List.fromList(List.generate(length, (_) => random.nextInt(256)));
}

void main() {
  final lib = openZstdForTests();
  late Directory source;
  late Directory dest;

  setUp(() {
    source = Directory.systemTemp.createTempSync('pkg_source');
    dest = Directory.systemTemp.createTempSync('pkg_dest');
  });
  tearDown(() {
    source.deleteSync(recursive: true);
    dest.deleteSync(recursive: true);
  });

  Uint8List libraryArchive(DynamicLibrary lib, {bool checksum = true}) =>
      zstdCompress(
        lib,
        buildTar({
          'books/seforim.db': _noise(300000, 1),
          'books/תלמוד בבלי/ברכות.pdf': _noise(40000, 2),
          'books/lexical.db.version': utf8.encode('v2'),
        }),
        checksum: checksum,
      );

  group('scanLibraryPackages', () {
    void touch(String name, [int size = 10]) =>
        File(p.join(source.path, name)).writeAsBytesSync(List.filled(size, 0));

    test('תיקייה בלי קובצי מסייע — ריקה', () async {
      touch('seforim.db');
      final scan = await scanLibraryPackages(
        DirectoryPackageFolder(source.path),
      );
      expect(scan.isEmpty, isTrue);
    });

    test('חלקים ומניפסט של ספרייה ואינדקס מאותה גרסה', () async {
      final bytes = Uint8List.fromList(List.generate(250, (i) => i));
      writeSplitAsset(source, _library, bytes, partSize: 100);
      writeSplitAsset(source, _index, bytes, partSize: 200);
      final scan = await scanLibraryPackages(
        DirectoryPackageFolder(source.path),
      );
      final set = scan.packages!;
      expect(set.version, '0.9.98');
      expect(set.library.parts.map((x) => x.name), [
        '$_library.part-000',
        '$_library.part-001',
        '$_library.part-002',
      ]);
      expect(set.library.hasManifest, isTrue);
      expect(set.index!.parts, hasLength(2));
      expect(set.compressedSize, 500);
    });

    test('בכמה גרסאות נבחרת הגבוהה, ואינדקס של גרסה אחרת אינו נלקח', () async {
      touch('otzaria-0.9.98-library.tar.zst.part-000');
      touch('otzaria-0.10.1-library.tar.zst.part-000');
      touch('otzaria-0.9.98-library-index.tar.zst.part-000');
      final scan = await scanLibraryPackages(
        DirectoryPackageFolder(source.path),
      );
      expect(scan.packages!.version, '0.10.1');
      expect(scan.packages!.index, isNull);
      expect(scan.packages!.library.hasManifest, isFalse);
    });

    test('אינדקס בלי ספרייה — בעיה מוסברת', () async {
      touch('$_index.part-000');
      final scan = await scanLibraryPackages(
        DirectoryPackageFolder(source.path),
      );
      expect(scan.problem, LibraryPackageProblem.indexWithoutLibrary);
    });

    test('חלק חסר מול המניפסט מזוהה בשמו', () async {
      final names = writeSplitAsset(
        source,
        _library,
        Uint8List(250),
        partSize: 100,
      );
      File(p.join(source.path, names[1])).deleteSync();
      final scan = await scanLibraryPackages(
        DirectoryPackageFolder(source.path),
      );
      expect(scan.problem, LibraryPackageProblem.incompleteParts);
      expect(scan.problemFile, '$_library.part-001');
    });

    test('פער במספור החלקים בלי מניפסט מזוהה', () async {
      touch('$_library.part-000');
      touch('$_library.part-002');
      final scan = await scanLibraryPackages(
        DirectoryPackageFolder(source.path),
      );
      expect(scan.problem, LibraryPackageProblem.incompleteParts);
      expect(scan.problemFile, '$_library.part-001');
    });

    test('ארכיון שהמסייע הרכיב לקובץ אחד', () async {
      touch(_library, 1234);
      final scan = await scanLibraryPackages(
        DirectoryPackageFolder(source.path),
      );
      expect(scan.packages!.library.parts.single.name, _library);
      expect(scan.packages!.library.compressedSize, 1234);
    });
  });

  group('extractLibraryPackage', () {
    setUp(() {
      if (lib == null) markTestSkipped('libzstd אינו זמין');
    });

    Future<LibraryPackageSet> scanned() async => (await scanLibraryPackages(
      DirectoryPackageFolder(source.path),
    )).packages!;

    Future<void> extract(
      LibraryPackageSet set, {
      bool Function()? isCancelled,
      void Function(int)? onBytes,
    }) => extractLibraryPackage(
      package: set.library,
      folder: set.folder,
      destination: dest.path,
      zstd: lib!,
      isCancelled: isCancelled,
      onBytes: onBytes,
    );

    test('חלקים עם מניפסט נפרסים בזרימה, כולל שמות בעברית', () async {
      if (lib == null) return;
      writeSplitAsset(source, _library, libraryArchive(lib), partSize: 65536);
      final set = await scanned();
      expect(set.library.parts.length, greaterThan(3));
      var read = 0;
      await extract(set, onBytes: (n) => read += n);
      expect(read, set.library.compressedSize);
      expect(
        File(p.join(dest.path, 'books', 'seforim.db')).readAsBytesSync(),
        _noise(300000, 1),
      );
      expect(
        File(
          p.join(dest.path, 'books', 'תלמוד בבלי', 'ברכות.pdf'),
        ).lengthSync(),
        40000,
      );
    });

    test('חלק פגום מדווח בשמו', () async {
      if (lib == null) return;
      final names = writeSplitAsset(
        source,
        _library,
        libraryArchive(lib),
        partSize: 65536,
      );
      final part = File(p.join(source.path, names[1]));
      final bytes = part.readAsBytesSync();
      bytes[500] ^= 0xFF;
      part.writeAsBytesSync(bytes);
      await expectLater(
        extract(await scanned()),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains(names[1]),
          ),
        ),
      );
    });

    test('בלי מניפסט: checksum של zstd מאמת, וחלק אחרון חסר נתפס', () async {
      if (lib == null) return;
      final names = writeSplitAsset(
        source,
        _library,
        libraryArchive(lib),
        partSize: 65536,
        withManifest: false,
      );
      await extract(await scanned());
      expect(
        File(p.join(dest.path, 'books', 'seforim.db')).existsSync(),
        isTrue,
      );

      File(p.join(source.path, names.last)).deleteSync();
      await expectLater(extract(await scanned()), throwsFormatException);
    });

    test('בלי מניפסט ובלי checksum בארכיון — מסרב לייבא', () async {
      if (lib == null) return;
      writeSplitAsset(
        source,
        _library,
        libraryArchive(lib, checksum: false),
        partSize: 65536,
        withManifest: false,
      );
      await expectLater(extract(await scanned()), throwsFormatException);
      expect(Directory(p.join(dest.path, 'books')).existsSync(), isFalse);
    });

    Uint8List multiFrameArchive({bool middleChecksum = true}) {
      final tar = buildTar({'books/seforim.db': List.filled(64, 65)});
      final middle = Uint8List.fromList([
        0x28,
        0xb5,
        0x2f,
        0xfd,
        0x20,
        64,
        1,
        2,
        0,
        ...List.filled(64, 65),
      ]);
      middle[9] ^= 3;
      return Uint8List.fromList([
        ...zstdCompress(lib!, Uint8List.sublistView(tar, 0, 512)),
        ...(middleChecksum
            ? zstdCompress(lib, Uint8List.sublistView(tar, 512, 576))
            : middle),
        ...zstdCompress(lib, Uint8List.sublistView(tar, 576)),
      ]);
    }

    test('בלי מניפסט כל frame חייב checksum, גם באמצע תוכן קובץ', () async {
      if (lib == null) return;
      File(p.join(source.path, _library)).writeAsBytesSync(
        multiFrameArchive(middleChecksum: false),
      );
      await expectLater(extract(await scanned()), throwsFormatException);
    });

    test('checksum בכל frame מאפשר ארכיון מרובה frames', () async {
      if (lib == null) return;
      File(p.join(source.path, _library)).writeAsBytesSync(multiFrameArchive());
      await extract(await scanned());
      expect(
        File(p.join(dest.path, 'books', 'seforim.db')).readAsBytesSync(),
        List.filled(64, 65),
      );
    });

    test('בלי מניפסט כותרות frames יכולות להיחצות בין חלקים', () async {
      if (lib == null) return;
      writeSplitAsset(
        source,
        _library,
        multiFrameArchive(),
        partSize: 1,
        withManifest: false,
      );
      await extract(await scanned());
      expect(
        File(p.join(dest.path, 'books', 'seforim.db')).readAsBytesSync(),
        List.filled(64, 65),
      );
    });

    test('עם מניפסט SHA-256 מאמת גם frames בלי checksum', () async {
      if (lib == null) return;
      writeSplitAsset(
        source,
        _library,
        multiFrameArchive(middleChecksum: false),
        partSize: 17,
      );
      await extract(await scanned());
      expect(File(p.join(dest.path, 'books', 'seforim.db')).readAsBytesSync(), [
        66,
        ...List.filled(63, 65),
      ]);
    });

    test('ארכיון מורכב מאומת מול ה-sha256 שבמניפסט', () async {
      if (lib == null) return;
      final archive = libraryArchive(lib);
      writeSplitAsset(source, _library, archive, partSize: 65536);
      for (final f in source.listSync().whereType<File>()) {
        if (f.path.contains('.part-')) f.deleteSync();
      }
      final tampered = Uint8List.fromList(archive)..[archive.length - 1] ^= 1;
      File(p.join(source.path, _library)).writeAsBytesSync(tampered);
      final set = await scanned();
      expect(set.library.parts.single.name, _library);
      await expectLater(extract(set), throwsFormatException);
    });

    test('ביטול באמצע עוצר בחריגה ייעודית', () async {
      if (lib == null) return;
      writeSplitAsset(source, _library, libraryArchive(lib), partSize: 65536);
      var chunks = 0;
      await expectLater(
        extract(await scanned(), isCancelled: () => ++chunks > 2),
        throwsA(isA<LibraryImportCancelled>()),
      );
    });
  });

  group('runPackageExtractionInIsolate', () {
    test('תיקייה מאוחדת של כרכים עוברת ל-isolate ונפרסת', () async {
      if (lib == null) return markTestSkipped('libzstd אינו זמין');
      final names = writeSplitAsset(
        source,
        _library,
        libraryArchive(lib),
        partSize: 65536,
      );
      final second = Directory(p.join(source.path, 'part2'))..createSync();
      File(
        p.join(source.path, names.last),
      ).renameSync(p.join(second.path, names.last));
      final merged = MergedPackageFolder([
        DirectoryPackageFolder(source.path),
        DirectoryPackageFolder(second.path),
      ], displayName: 'volumes');
      final set = (await scanLibraryPackages(merged)).packages!;
      final cancel = ZstdCancelFlag();
      addTearDown(cancel.dispose);
      await runPackageExtractionInIsolate(
        PackageExtractionJob(packages: set, libraryDestination: dest.path),
        onProgress: (_, _, _) {},
        cancel: cancel,
        openZstd: () => openZstdForTests()!,
      );
      expect(
        File(p.join(dest.path, 'books', 'seforim.db')).readAsBytesSync(),
        _noise(300000, 1),
      );
    });

    test('פורס ב-isolate ומדווח התקדמות עד הסוף; דגל ביטול עוצר', () async {
      if (lib == null) return markTestSkipped('libzstd אינו זמין');
      writeSplitAsset(source, _library, libraryArchive(lib), partSize: 65536);
      final set = (await scanLibraryPackages(
        DirectoryPackageFolder(source.path),
      )).packages!;
      final job = PackageExtractionJob(
        packages: set,
        libraryDestination: dest.path,
      );
      final progress = <int>[];
      final cancel = ZstdCancelFlag();
      addTearDown(cancel.dispose);
      await runPackageExtractionInIsolate(
        job,
        onProgress: (_, done, _) => progress.add(done),
        cancel: cancel,
        openZstd: () => openZstdForTests()!,
      );
      expect(progress.last, set.compressedSize);
      expect(
        File(p.join(dest.path, 'books', 'seforim.db')).existsSync(),
        isTrue,
      );

      cancel.cancel();
      await expectLater(
        runPackageExtractionInIsolate(
          job,
          onProgress: (_, _, _) {},
          cancel: cancel,
          openZstd: () => openZstdForTests()!,
        ),
        throwsA(isA<LibraryImportCancelled>()),
      );
    });
  });
}
