import 'dart:io';
import 'dart:ffi';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/empty_library/bloc/empty_library_bloc.dart';
import 'package:otzaria/empty_library/bloc/empty_library_event.dart';
import 'package:otzaria/empty_library/bloc/empty_library_state.dart';
import 'package:otzaria/empty_library/services/library_package/library_package_importer.dart';
import 'package:otzaria/utils/file/disk_free_space.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import '../test_helpers/memory_cache_provider.dart';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/empty_library/services/library_package/library_package.dart';
import 'package:otzaria/empty_library/services/library_package/library_package_extractor.dart';
import 'package:otzaria/empty_library/services/library_package/library_source.dart';
import 'package:otzaria/empty_library/services/library_package/package_folder.dart';
import 'package:otzaria/empty_library/services/library_package/raw_asset_extractor.dart';
import 'package:otzaria/empty_library/services/library_space_estimate.dart';
import 'package:otzaria/utils/file/zstd_stream_extractor_io.dart';
import 'package:path/path.dart' as p;
import '../support/zstd_test_lib.dart';
import 'library_package_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('pr2066-review-');
  });
  tearDown(() async {
    await temp.delete(recursive: true);
  });

  test(
    'cancel requested before extracted Talmud copy must prevent installation',
    () async {
      final src = Directory(p.join(temp.path, 'source'))..createSync();
      final talmud = DatabaseConstants.talmudBavliFolderName;
      Directory(p.join(src.path, talmud)).createSync();
      File(p.join(src.path, talmud, 'ברכות.pdf')).writeAsStringSync('pdf');
      final raw = await scanRawLibraryAssets(DirectoryPackageFolder(src.path));
      final dest = Directory(p.join(temp.path, 'staging'))..createSync();
      await expectLater(
        extractRawAssetJob(
          RawAssetJob(
            assets: raw.assets.values.toList(),
            destination: dest.path,
          ),
          openZstd: () =>
              throw StateError('plain directory must not open codec'),
          onProgress: (_, _, _) {},
          isCancelled: () => true,
        ),
        throwsA(isA<LibraryImportCancelled>()),
      );
    },
  );

  test(
    'parent folder detects nested DB even with a standalone companion',
    () async {
      File(p.join(temp.path, 'lexical.db')).writeAsStringSync('dictionary');
      final nested = Directory(
        p.join(temp.path, kAndroidFullBundlePrefix, 'library_db'),
      )..createSync(recursive: true);
      File(p.join(nested.path, 'seforim.db')).writeAsStringSync('db');
      final scan = await scanLibrarySource(DirectoryPackageFolder(temp.path));
      expect(scan.components, contains(LibraryComponent.libraryDb));
    },
  );

  test(
    'bloc does not commit Talmud after cancellation during directory copy',
    () async {
      await Settings.init(cacheProvider: MemoryCacheProvider());
      await Settings.setValue<String>(SettingsRepository.keyLibraryPath, '');
      final src = Directory(p.join(temp.path, 'source'))..createSync();
      final talmud = DatabaseConstants.talmudBavliFolderName;
      Directory(p.join(src.path, talmud)).createSync();
      File(p.join(src.path, talmud, 'ברכות.pdf')).writeAsStringSync('pdf');
      final books = Directory(p.join(temp.path, 'books'))..createSync();
      File(p.join(books.path, 'seforim.db')).writeAsStringSync('existing-db');
      final raw = await scanRawLibraryAssets(DirectoryPackageFolder(src.path));
      final bloc = EmptyLibraryBloc(
        downloadSpaceChecker: (_) async => null,
        packageImporter: LibraryPackageImporter(
          diskSpace: (_) async => DiskSpaceInfo.unknown,
          rawRunner: (job, {required onProgress, required cancel}) async {
            final cell = Pointer<Uint8>.fromAddress(cancel.address);
            await extractRawAssetJob(
              job,
              openZstd: () => throw StateError('no codec needed'),
              onProgress: (component, done, total) {
                onProgress(component, done, total);
                if (component == LibraryComponent.talmudBavli) cancel.cancel();
              },
              isCancelled: () => cell.value != 0,
            );
          },
        ),
      );
      addTearDown(bloc.close);
      final terminal = bloc.stream
          .where(
            (s) => s is EmptyLibraryError || s is EmptyLibraryDirectorySelected,
          )
          .first;
      bloc.add(
        ImportLibraryFolderRequested(assets: raw, targetPath: books.path),
      );
      final state = await terminal.timeout(const Duration(seconds: 15));
      expect(state, isA<EmptyLibraryError>());
      expect(
        File(p.join(books.path, talmud, 'ברכות.pdf')).existsSync(),
        isFalse,
      );
    },
  );

  test(
    'parent with partial manifest still scans sibling volume parts',
    () async {
      final lib = openZstdForTests();
      if (lib == null) {
        markTestSkipped('missing libzstd');
        return;
      }
      const archive = 'otzaria-1.2.3-library.tar.zst';
      final nested = Directory(p.join(temp.path, kAndroidFullBundlePrefix))
        ..createSync();
      writeSplitAsset(
        nested,
        archive,
        zstdCompress(
          lib,
          buildTar({
            'books/seforim.db': [1, 2, 3],
          }),
        ),
        partSize: 64,
      );
      File(
        p.join(nested.path, '$archive.manifest.json'),
      ).copySync(p.join(temp.path, '$archive.manifest.json'));
      final scan = await scanLibrarySource(DirectoryPackageFolder(temp.path));
      expect(scan.components, contains(LibraryComponent.libraryDb));
    },
  );

  test('ביטול אחרי סיום runner נבדק לפני promotion ומנקה staging', () async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
    await Settings.setValue<String>(SettingsRepository.keyLibraryPath, '');
    final source = Directory(p.join(temp.path, 'source'))..createSync();
    File(p.join(source.path, 'lexical.db')).writeAsStringSync('new');
    final books = Directory(p.join(temp.path, 'books'))..createSync();
    File(p.join(books.path, 'seforim.db')).writeAsStringSync('existing-db');
    final raw = await scanRawLibraryAssets(DirectoryPackageFolder(source.path));
    final bloc = EmptyLibraryBloc(
      downloadSpaceChecker: (_) async => null,
      packageImporter: LibraryPackageImporter(
        diskSpace: (_) async => DiskSpaceInfo.unknown,
        rawRunner: (job, {required onProgress, required cancel}) async {
          await File(
            p.join(job.destination, 'lexical.db'),
          ).writeAsString('new');
          cancel.cancel();
        },
      ),
    );
    addTearDown(bloc.close);
    final terminal = bloc.stream
        .where(
          (s) => s is EmptyLibraryError || s is EmptyLibraryDirectorySelected,
        )
        .first;
    bloc.add(ImportLibraryFolderRequested(assets: raw, targetPath: books.path));
    expect(
      await terminal.timeout(const Duration(seconds: 15)),
      isA<EmptyLibraryError>(),
    );
    expect(File(p.join(books.path, 'lexical.db')).existsSync(), isFalse);
    expect(
      Directory(LibraryPackageImporter.stagingRootFor(books.path)).existsSync(),
      isFalse,
    );
    expect(
      File(p.join(books.path, 'seforim.db')).readAsStringSync(),
      'existing-db',
    );
  });

  test('מקור תקין נשמר כשמניפסט פגום בשורש מסתיר אותו', () async {
    File(
      p.join(temp.path, 'seforim.db.zst.manifest.json'),
    ).writeAsStringSync('{}');
    File(p.join(temp.path, 'lexical.db')).writeAsStringSync('dictionary');
    final nested = Directory(p.join(temp.path, kAndroidFullBundlePrefix))
      ..createSync();
    File(p.join(nested.path, 'seforim.db')).writeAsStringSync('db');
    final scan = await scanLibrarySource(DirectoryPackageFolder(temp.path));
    expect(
      scan.components,
      containsAll([LibraryComponent.libraryDb, LibraryComponent.lexicon]),
    );
    expect(scan.raw.problem, isNull);
    final db = scan.raw.assets[LibraryComponent.libraryDb]!;
    expect(
      await db.folder
          .openRead(db.parts.single.entry)
          .expand((chunk) => chunk)
          .toList(),
      'db'.codeUnits,
    );
  });

  test('גרסה גולמית תקינה בשורש קודמת לכפילות בתיקיית החבילה', () async {
    File(p.join(temp.path, 'seforim.db')).writeAsStringSync('root-db');
    final nested = Directory(p.join(temp.path, kAndroidFullBundlePrefix))
      ..createSync();
    File(
      p.join(nested.path, 'seforim.db'),
    ).writeAsStringSync('nested-different-db');
    File(
      p.join(nested.path, DatabaseConstants.externalCatalogDatabaseFileName),
    ).writeAsStringSync('catalog');
    final scan = await scanLibrarySource(DirectoryPackageFolder(temp.path));
    expect(
      scan.components,
      containsAll([LibraryComponent.libraryDb, LibraryComponent.catalog]),
    );
    final db = scan.raw.assets[LibraryComponent.libraryDb]!;
    expect(
      await db.folder
          .openRead(db.parts.single.entry)
          .expand((chunk) => chunk)
          .toList(),
      'root-db'.codeUnits,
    );
  });

  test('רכיב נלווה בשורש אינו עוקף התנגשות בין כרכים', () async {
    File(p.join(temp.path, 'lexical.db')).writeAsStringSync('dictionary');
    final first = Directory(
      p.join(temp.path, '$kAndroidFullBundlePrefix-part1'),
    )..createSync();
    final second = Directory(
      p.join(temp.path, '$kAndroidFullBundlePrefix-part2'),
    )..createSync();
    const archive = 'otzaria-1.2.3-library.tar.zst';
    final parts = writeSplitAsset(
      first,
      archive,
      Uint8List(300),
      partSize: 100,
    );
    File(p.join(second.path, parts.first)).writeAsBytesSync([1]);
    final scan = await scanLibrarySource(DirectoryPackageFolder(temp.path));
    expect(scan.packages.problem, LibraryPackageProblem.conflictingParts);
    expect(scan.packages.problemFile, parts.first);
    expect(scan.components, isNot(contains(LibraryComponent.libraryDb)));
  });

  test('חבילה מלאה בתיקיית עטיפה מזוהה לצד רכיב בשורש', () async {
    File(p.join(temp.path, 'lexical.db')).writeAsStringSync('dictionary');
    final nested = Directory(p.join(temp.path, kAndroidFullBundlePrefix))
      ..createSync();
    const archive = 'otzaria-1.2.3-library.tar.zst';
    writeSplitAsset(nested, archive, Uint8List(300), partSize: 100);
    final scan = await scanLibrarySource(DirectoryPackageFolder(temp.path));
    expect(scan.packages.packages, isNotNull);
    expect(scan.packages.packages!.library.archiveName, archive);
    expect(scan.components, contains(LibraryComponent.libraryDb));
  });

  test('multiframe estimate accounts for all extracted bytes', () async {
    final lib = openZstdForTests();
    if (lib == null) {
      markTestSkipped('missing libzstd');
      return;
    }
    final first = Uint8List(300000);
    final second = Uint8List(400000);
    final archive = [...zstdCompress(lib, first), ...zstdCompress(lib, second)];
    final input = File(p.join(temp.path, 'seforim.db.zst'))
      ..writeAsBytesSync(archive);
    final output = p.join(temp.path, 'decoded');
    decompressSyncForTest(input.path, output, lib);
    expect(File(output).lengthSync(), first.length + second.length);
    final header = await readZstdArchiveContentSize(
      input.openRead(),
      compressedSize: archive.length,
    );
    final estimate = extractedSizeOf(
      archive.length,
      archiveContentSize: header,
      fallbackRatio: ExpansionFallback.database,
    );
    expect(estimate, greaterThanOrEqualTo(File(output).lengthSync()));
  });
}
