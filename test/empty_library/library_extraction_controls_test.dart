import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/empty_library/services/library_package/library_package.dart';
import 'package:otzaria/empty_library/services/library_package/library_package_extractor.dart';
import 'package:otzaria/empty_library/services/library_package/library_package_importer.dart';
import 'package:otzaria/empty_library/services/library_package/library_source.dart';
import 'package:otzaria/empty_library/services/library_package/package_folder.dart';
import 'package:otzaria/empty_library/services/library_package/raw_asset_extractor.dart';
import 'package:otzaria/utils/file/zstd_library.dart';
import 'package:otzaria/utils/file/zstd_patch_decoder.dart';
import 'package:otzaria/utils/file/zstd_stream_extractor.dart';
import 'package:path/path.dart' as p;

import '../support/zstd_test_lib.dart';
import 'library_package_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final zstd = openZstdForTests();
  late Directory tmp;
  late Directory source;
  late String books;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('library_extraction_controls_');
    source = Directory(p.join(tmp.path, 'source'))..createSync();
    books = p.join(tmp.path, 'books');
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<RawLibraryScan> scanRaw(Directory folder) =>
      scanRawLibraryAssets(DirectoryPackageFolder(folder.path));

  LibraryPackageImporter inlineImporter(int limit) => LibraryPackageImporter(
    maxOutputBytes: limit,
    rawRunner: (job, {required onProgress, required cancel}) =>
        extractRawAssetJob(
          job,
          openZstd: () => zstd!,
          onProgress: onProgress,
          isCancelled: () =>
              Pointer<Uint8>.fromAddress(cancel.address).value != 0,
        ),
    runner: (job, {required onProgress, required cancel}) => extractPackageJob(
      job,
      zstd: zstd!,
      onProgress: onProgress,
      isCancelled: () => Pointer<Uint8>.fromAddress(cancel.address).value != 0,
    ),
  );

  test('raw output cap spans concatenated frames and cleans staging', () async {
    if (zstd == null) return markTestSkipped('libzstd אינו זמין');
    final frame = Uint8List(4 << 20);
    final compressed = zstdCompress(zstd, frame);
    final archive = File(p.join(source.path, 'seforim.db.zst'))
      ..writeAsBytesSync([...compressed, ...compressed]);
    final raw = await scanRaw(source);
    final cancel = ZstdCancelFlag();
    addTearDown(cancel.dispose);
    await expectLater(
      inlineImporter(frame.length).stageRaw(
        raw: raw,
        booksTarget: books,
        onProgress: (_, _, _) {},
        cancel: cancel,
      ),
      throwsA(isA<ZstdOutputLimitExceeded>()),
    );
    expect(Directory('$books.import').existsSync(), isFalse);
    expect(archive.readAsBytesSync(), [...compressed, ...compressed]);
    final staged = await inlineImporter(2 * frame.length).stageRaw(
      raw: raw,
      booksTarget: books,
      onProgress: (_, _, _) {},
      cancel: cancel,
    );
    expect(File(p.join(staged, 'seforim.db')).lengthSync(), 2 * frame.length);
  });

  test(
    'package cap is enforced during tar expansion and source survives',
    () async {
      if (zstd == null) return markTestSkipped('libzstd אינו זמין');
      final bytes = buildTar({'books/seforim.db': Uint8List(8 << 20)});
      writeSplitAsset(
        source,
        'otzaria-0.9.98-library.tar.zst',
        zstdCompress(zstd, bytes),
        partSize: 1 << 20,
      );
      final packages = (await scanLibraryPackages(
        DirectoryPackageFolder(source.path),
      )).packages!;
      final cancel = ZstdCancelFlag();
      addTearDown(cancel.dispose);
      await expectLater(
        inlineImporter(4 << 20).stage(
          packages: packages,
          booksTarget: books,
          indexTarget: null,
          onProgress: (_, _, _) {},
          cancel: cancel,
        ),
        throwsA(isA<ZstdOutputLimitExceeded>()),
      );
      expect(Directory('$books.import').existsSync(), isFalse);
      for (final part in packages.library.parts) {
        expect(
          File(packages.folder.localPath(part.entry)!).existsSync(),
          isTrue,
        );
      }
    },
  );

  test(
    'raw cancellation is checked inside one highly compressed input read',
    () async {
      if (zstd == null) return markTestSkipped('libzstd אינו זמין');
      final archive = File(p.join(source.path, 'seforim.db.zst'))
        ..writeAsBytesSync(zstdCompress(zstd, Uint8List(32 << 20)));
      expect(archive.lengthSync(), lessThan(64 << 10));
      final raw = await scanRaw(source);
      final outputDir = Directory(books)..createSync();
      final output = File(p.join(books, 'seforim.db'));
      await expectLater(
        extractRawAssetJob(
          RawAssetJob(assets: raw.assets.values.toList(), destination: books),
          openZstd: () => zstd,
          onProgress: (_, _, _) {},
          isCancelled: () => output.existsSync() && output.lengthSync() > 0,
        ),
        throwsA(isA<LibraryImportCancelled>()),
      );
      expect(output.lengthSync(), lessThanOrEqualTo(zstdOutputChunkBytes));
      expect(archive.existsSync(), isTrue);
      await outputDir.delete(recursive: true); // החילוץ סגר את כל ה-handles.
    },
  );

  for (final package in [false, true]) {
    test(
      'progress within one compressed read permits cancellation: package=$package',
      () async {
        if (zstd == null) return markTestSkipped('libzstd אינו זמין');
        final rawBytes = Uint8List(12 << 20);
        final compressed = zstdCompress(
          zstd,
          package ? buildTar({'books/seforim.db': rawBytes}) : rawBytes,
        );
        expect(compressed.length, lessThan(64 << 10));
        if (package) {
          writeSplitAsset(
            source,
            'otzaria-0.9.98-library.tar.zst',
            compressed,
            partSize: 1 << 20,
          );
        } else {
          await File(
            p.join(source.path, 'seforim.db.zst'),
          ).writeAsBytes(compressed);
        }
        final cancel = ZstdCancelFlag();
        addTearDown(cancel.dispose);
        var progressed = false;
        void progress(Object _, int done, int total) {
          if (done > 0 && done < total) {
            progressed = true;
            cancel.cancel();
          }
        }

        final importer = inlineImporter(64 << 20);
        final operation = package
            ? importer.stage(
                packages: (await scanLibraryPackages(
                  DirectoryPackageFolder(source.path),
                )).packages!,
                booksTarget: books,
                indexTarget: null,
                onProgress: progress,
                cancel: cancel,
              )
            : importer.stageRaw(
                raw: await scanRaw(source),
                booksTarget: books,
                onProgress: progress,
                cancel: cancel,
              );
        await expectLater(operation, throwsA(isA<LibraryImportCancelled>()));
        expect(progressed, isTrue);
        expect(Directory('$books.import').existsSync(), isFalse);
        expect(await source.list().isEmpty, isFalse);
      },
    );
  }

  for (final throwFromCallback in [false, true]) {
    test(
      'late raw worker callback drains before cleanup: throw=$throwFromCallback',
      () async {
        final original = File(p.join(source.path, 'seforim.db'))
          ..writeAsBytesSync(Uint8List(4096));
        final raw = await scanRaw(source);
        final cancel = ZstdCancelFlag();
        addTearDown(cancel.dispose);
        final failure = StateError('final progress observer failed');
        await expectLater(
          LibraryPackageImporter().stageRaw(
            raw: raw,
            booksTarget: books,
            cancel: cancel,
            onProgress: (_, done, total) {
              if (done == total && done > 0) {
                if (throwFromCallback) throw failure;
                cancel.cancel();
              }
            },
          ),
          throwFromCallback
              ? throwsA(same(failure))
              : throwsA(isA<LibraryImportCancelled>()),
        );
        expect(Directory('$books.import').existsSync(), isFalse);
        expect(original.lengthSync(), 4096);
      },
    );
  }

  for (final package in [false, true]) {
    test(
      'staging cleanup refuses a selected source within staging: package=$package',
      () async {
        final staging = Directory('$books.import')..createSync();
        final original = File(
          p.join(
            staging.path,
            package ? 'otzaria-0.9.98-library.tar.zst' : 'seforim.db',
          ),
        )..writeAsStringSync('caller-owned source');
        final cancel = ZstdCancelFlag();
        addTearDown(cancel.dispose);
        final importer = LibraryPackageImporter();
        final action = package
            ? importer.stage(
                packages: (await scanLibraryPackages(
                  DirectoryPackageFolder(staging.path),
                )).packages!,
                booksTarget: books,
                indexTarget: null,
                onProgress: (_, _, _) {},
                cancel: cancel,
              )
            : importer.stageRaw(
                raw: await scanRaw(staging),
                booksTarget: books,
                onProgress: (_, _, _) {},
                cancel: cancel,
              );
        await expectLater(action, throwsArgumentError);
        expect(original.readAsStringSync(), 'caller-owned source');
      },
    );
  }

  test(
    'source alias into staging is rejected before deleting source',
    () async {
      final staging = Directory('$books.import')..createSync();
      final original = File(p.join(staging.path, 'seforim.db'))
        ..writeAsStringSync('caller-owned source');
      final alias = Link(p.join(tmp.path, 'source-alias'))
        ..createSync(staging.path);
      final cancel = ZstdCancelFlag();
      addTearDown(cancel.dispose);
      await expectLater(
        LibraryPackageImporter().stageRaw(
          raw: await scanRaw(Directory(alias.path)),
          booksTarget: books,
          onProgress: (_, _, _) {},
          cancel: cancel,
        ),
        throwsArgumentError,
      );
      expect(original.readAsStringSync(), 'caller-owned source');
      expect(alias.existsSync(), isTrue);
    },
    skip: Platform.isWindows
        ? 'symlink privileges depend on host policy'
        : false,
  );

  test(
    'pre-cancellation leaves existing staging and source untouched',
    () async {
      final original = File(p.join(source.path, 'seforim.db'))
        ..writeAsStringSync('source');
      final staging = Directory('$books.import')..createSync();
      final retained = File(p.join(staging.path, 'retained'))
        ..writeAsStringSync('keep');
      final cancel = ZstdCancelFlag()..cancel();
      addTearDown(cancel.dispose);
      await expectLater(
        LibraryPackageImporter().stageRaw(
          raw: await scanRaw(source),
          booksTarget: books,
          onProgress: (_, _, _) {},
          cancel: cancel,
        ),
        throwsA(isA<LibraryImportCancelled>()),
      );
      expect(original.readAsStringSync(), 'source');
      expect(retained.readAsStringSync(), 'keep');
    },
  );
}
