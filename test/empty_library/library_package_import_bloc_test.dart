import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/empty_library/bloc/empty_library_bloc.dart';
import 'package:otzaria/empty_library/bloc/empty_library_event.dart';
import 'package:otzaria/empty_library/bloc/empty_library_state.dart';
import 'package:otzaria/empty_library/services/library_package/library_package.dart';
import 'package:otzaria/empty_library/services/library_package/library_package_extractor.dart';
import 'package:otzaria/empty_library/services/library_package/library_package_importer.dart';
import 'package:otzaria/empty_library/services/library_package/library_source.dart';
import 'package:otzaria/empty_library/services/library_package/package_folder.dart';
import 'package:otzaria/library_update/services/library_access_gate.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/utils/file/disk_free_space.dart';
import 'package:otzaria/utils/file/zstd_patch_decoder.dart';
import 'package:path/path.dart' as p;

import '../support/zstd_test_lib.dart';
import '../test_helpers/memory_cache_provider.dart';
import 'library_package_test_support.dart';

const _library = 'otzaria-0.9.98-library.tar.zst';
const _index = 'otzaria-0.9.98-library-index.tar.zst';
final _dbName = DatabaseConstants.databaseFileName;

Uint8List _noise(int length, int seed) {
  final random = Random(seed);
  return Uint8List.fromList(List.generate(length, (_) => random.nextInt(256)));
}

/// השעיית המסד בלי חלונות אחרים; [resumed] מסמן שהמטפל סיים, כולל ניקוי הגיבוי.
class _Gate extends LibraryAccessGate {
  _Gate()
    : super(
        selfAccess: LibraryAccessRoutine(
          suspend: () async {},
          resume: (_) async {},
        ),
        renameProbe: false,
        logError: (_, _, _) {},
      );

  final resumed = Completer<void>();

  @override
  Future<void> resumeAll(
    LibrarySuspension suspension, {
    required bool dbReplaced,
  }) async {
    await super.resumeAll(suspension, dbReplaced: dbReplaced);
    if (!resumed.isCompleted) resumed.complete();
  }
}

class _FailingCache extends MemoryCacheProvider {
  String? failingKey;
  bool failAfterWrite = false;

  @override
  Future<void> setObject<T>(String key, T? value) async {
    if (key == failingKey) {
      if (failAfterWrite) {
        failingKey = null;
        await super.setObject<T>(key, value);
      }
      throw const FileSystemException('simulated settings I/O failure');
    }
    await super.setObject<T>(key, value);
  }
}

class _Importer extends LibraryPackageImporter {
  _Importer({
    required super.runner,
    required super.diskSpace,
    required super.indexHost,
    this.beforeCommit,
    this.afterCommit,
    this.afterDiscard,
  });

  final Future<void> Function()? beforeCommit;
  final Future<void> Function()? afterCommit;
  final Future<void> Function()? afterDiscard;

  @override
  Future<void> commitIndex(String indexTarget) async {
    await beforeCommit?.call();
    await super.commitIndex(indexTarget);
    await afterCommit?.call();
  }

  @override
  Future<void> discard(StagedLibraryPackage staged) async {
    await super.discard(staged);
    await afterDiscard?.call();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final lib = openZstdForTests();

  late Directory temp;
  late Directory source;
  late String root;
  late String books;
  late List<String> indexHostCalls;
  late _Gate gate;
  late _FailingCache cache;
  late List<(String?, String?)> reopenedLibrary;
  late Completer<void> reopened;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('otzaria-pkg-bloc-');
    EmptyLibraryBloc.tempRootOverride = temp.path;
    source = await Directory(p.join(temp.path, 'הורדות')).create();
    root = p.join(temp.path, 'ספרייה');
    books = p.join(root, 'books');
    indexHostCalls = [];
    reopenedLibrary = [];
    reopened = Completer<void>();
    await Settings.init(cacheProvider: cache = _FailingCache());
    await Settings.setValue<String>(SettingsRepository.keyLibraryPath, '');
    await Settings.setValue<String>(SettingsRepository.keyIndexPath, '');
  });

  tearDown(() async {
    EmptyLibraryBloc.tempRootOverride = null;
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  void writeLibrary(DynamicLibrary lib) {
    final archive = zstdCompress(
      lib,
      buildTar({
        'books/$_dbName': utf8.encode('new-db'),
        'books/תלמוד בבלי/ברכות.pdf': _noise(400000, 3),
      }),
    );
    writeSplitAsset(source, _library, archive, partSize: 65536);
  }

  void writeIndex(DynamicLibrary lib) {
    final archive = zstdCompress(
      lib,
      buildTar({
        'index/${AppPaths.prebuiltIndexMarkerFileName}': const [],
        'index/meta.json': utf8.encode('{"new":true}'),
      }),
    );
    writeSplitAsset(source, _index, archive, partSize: 65536);
  }

  /// הפריסה האמיתית, בלי isolate: ב-isolate של בדיקה אין את ה-DLL של zstd.
  Future<void> inlineRunner(
    PackageExtractionJob job, {
    required PackageExtractionProgress onProgress,
    required ZstdCancelFlag cancel,
  }) {
    final cell = Pointer<Uint8>.fromAddress(cancel.address);
    return extractPackageJob(
      job,
      zstd: lib!,
      onProgress: onProgress,
      isCancelled: () => cell.value != 0,
    );
  }

  EmptyLibraryBloc build({
    int freeBytes = -1,
    bool failReopen = false,
    bool failInstall = false,
    Future<void> Function()? beforeIndexCommit,
    Future<void> Function()? afterIndexCommit,
    Future<void> Function()? afterStagingDiscard,
  }) => EmptyLibraryBloc(
    accessGate: gate = _Gate(),
    downloadSpaceChecker: (_) async => null,
    packageImporter: _Importer(
      runner: inlineRunner,
      beforeCommit: beforeIndexCommit,
      afterCommit: afterIndexCommit,
      afterDiscard: afterStagingDiscard,
      diskSpace: (_) async =>
          DiskSpaceInfo(volumeId: 'test', freeBytes: freeBytes),
      indexHost: LibraryIndexHost(
        release: () async {
          indexHostCalls.add('release');
          if (failInstall) {
            await Directory(
              p.join('$books.import', 'index'),
            ).delete(recursive: true);
          }
        },
        reopen: () async {
          indexHostCalls.add('reopen');
          final db = File(p.join(books, _dbName));
          final meta = File(p.join(root, 'index', 'meta.json'));
          reopenedLibrary.add((
            db.existsSync() ? db.readAsStringSync() : null,
            meta.existsSync() ? meta.readAsStringSync() : null,
          ));
          if (!reopened.isCompleted) reopened.complete();
          if (failReopen) throw StateError('simulated reopen failure');
        },
      ),
    ),
  );

  Future<LibraryPackageSet> scanned() async => (await scanLibraryPackages(
    DirectoryPackageFolder(source.path),
  )).packages!;

  /// עדכון במקום מסתיים ב-resumeAll; הגדרה ראשונה — במצב הסופי, ואם האינדקס
  /// שוחרר גם בפתיחתו מחדש, שבאה אחרי שחזור וניקוי שעושים IO אמיתי.
  Future<void> settle(EmptyLibraryBloc bloc, {bool replacing = false}) async {
    if (replacing) {
      await gate.resumed.future.timeout(const Duration(seconds: 30));
      return;
    }
    await bloc.stream
        .firstWhere(
          (s) => s is EmptyLibraryDirectorySelected || s is EmptyLibraryError,
        )
        .timeout(const Duration(seconds: 30));
    if (indexHostCalls.contains('release')) {
      await reopened.future.timeout(const Duration(seconds: 30));
    }
    await pumpEventQueue();
  }

  void expectNoLeftovers() {
    expect(Directory('$books.import').existsSync(), isFalse);
    expect(Directory(EmptyLibraryBloc.dbBackupDirPath).existsSync(), isFalse);
  }

  late LibraryPackageSet packages;

  blocTest<EmptyLibraryBloc, EmptyLibraryState>(
    'הגדרה ראשונה: הספרייה והאינדקס נפרסים, וההגדרות מצביעות עליהם',
    setUp: () async {
      if (lib == null) return;
      writeLibrary(lib);
      writeIndex(lib);
      packages = await scanned();
    },
    build: build,
    act: (bloc) async {
      if (lib == null) return markTestSkipped('libzstd אינו זמין');
      bloc.add(
        ImportLibraryPackageRequested(packages: packages, targetPath: books),
      );
      await settle(bloc);
    },
    verify: (bloc) {
      if (lib == null) return;
      expect(bloc.state, isA<EmptyLibraryDirectorySelected>());
      expect(File(p.join(books, _dbName)).readAsStringSync(), 'new-db');
      expect(
        File(p.join(books, 'תלמוד בבלי', 'ברכות.pdf')).lengthSync(),
        400000,
      );
      final index = p.join(root, 'index');
      expect(
        File(p.join(index, AppPaths.prebuiltIndexMarkerFileName)).existsSync(),
        isTrue,
      );
      expect(
        Settings.getValue<String>(SettingsRepository.keyLibraryPath),
        books,
      );
      expect(Settings.getValue<String>(SettingsRepository.keyIndexPath), index);
      expect(indexHostCalls, ['release', 'reopen']);
      expect(reopenedLibrary, [('new-db', '{"new":true}')]);
      final report =
          (bloc.state as EmptyLibraryDirectorySelected).importReport!;
      expect(report.imported, {
        LibraryComponent.libraryDb,
        LibraryComponent.talmudBavli,
        LibraryComponent.searchIndex,
      });
      expect(report.missing, {
        LibraryComponent.catalog,
        LibraryComponent.lexicon,
      });
      expectNoLeftovers();
    },
  );

  blocTest<EmptyLibraryBloc, EmptyLibraryState>(
    'ההתקדמות ניתנת לביטול בזמן הפריסה, ולא בזמן ההעברה למקום',
    setUp: () async {
      if (lib == null) return;
      writeLibrary(lib);
      packages = await scanned();
    },
    build: build,
    act: (bloc) async {
      if (lib == null) return;
      bloc.add(
        ImportLibraryPackageRequested(packages: packages, targetPath: books),
      );
      await settle(bloc);
    },
    verify: (bloc) {},
    expect: () => lib == null
        ? const <EmptyLibraryState>[]
        : containsAllInOrder([
            isA<EmptyLibraryExtracting>().having(
              (s) => s.cancellable,
              'cancellable',
              isTrue,
            ),
            isA<EmptyLibraryExtracting>()
                .having((s) => s.cancellable, 'cancellable', isFalse)
                .having((s) => s.progress, 'progress', 1.0),
            isA<EmptyLibraryDirectorySelected>(),
          ]),
  );

  blocTest<EmptyLibraryBloc, EmptyLibraryState>(
    'העברת הספרים נכשלה אחרי החלפת האינדקס: האינדקס הקודם חוזר',
    setUp: () async {
      if (lib == null) return;
      writeLibrary(lib);
      writeIndex(lib);
      packages = await scanned();
      // תיקייה בשם המסד ביעד מכשילה את ה-rename האחרון של ההעברה.
      await Directory(p.join(books, _dbName, 'x')).create(recursive: true);
      await Directory(p.join(root, 'index')).create();
      await File(p.join(root, 'index', 'meta.json')).writeAsString('old');
    },
    build: build,
    act: (bloc) async {
      if (lib == null) return;
      bloc.add(
        ImportLibraryPackageRequested(packages: packages, targetPath: books),
      );
      await settle(bloc);
    },
    verify: (bloc) {
      if (lib == null) return;
      expect(bloc.state, isA<EmptyLibraryError>());
      expect(
        File(p.join(root, 'index', 'meta.json')).readAsStringSync(),
        'old',
      );
      expect(Directory(p.join(root, 'index.replaced')).existsSync(), isFalse);
      expect(Settings.getValue<String>(SettingsRepository.keyIndexPath), '');
      expect(indexHostCalls, ['release', 'reopen']);
      expectNoLeftovers();
    },
  );

  for (final replacing in [false, true]) {
    blocTest<EmptyLibraryBloc, EmptyLibraryState>(
      'כשל אחרי כתיבת ההגדרות ללא אינדקס קודם, replacing=$replacing',
      setUp: () async {
        if (lib == null) return;
        writeLibrary(lib);
        writeIndex(lib);
        packages = await scanned();
        if (replacing) {
          await Directory(books).create(recursive: true);
          await File(p.join(books, _dbName)).writeAsString('old-db');
          await Settings.setValue<String>(
            SettingsRepository.keyLibraryPath,
            books,
          );
        }
        cache.failingKey = SettingsRepository.keyDbEffectivePath;
        cache.failAfterWrite = true;
      },
      build: build,
      act: (bloc) async {
        if (lib == null) return;
        bloc.add(
          ImportLibraryPackageRequested(
            packages: packages,
            targetPath: books,
            backupExistingPath: replacing ? books : null,
          ),
        );
        await settle(bloc, replacing: replacing);
      },
      verify: (bloc) {
        if (lib == null) return;
        expect(bloc.state, isA<EmptyLibraryError>());
        expect(
          File(p.join(books, _dbName)).readAsStringSync(),
          replacing ? 'old-db' : 'new-db',
        );
        expect(Directory(p.join(root, 'index')).existsSync(), isFalse);
        expect(Directory(p.join(root, 'index.replaced')).existsSync(), isFalse);
        expect(
          Settings.getValue<String>(SettingsRepository.keyLibraryPath),
          replacing ? books : '',
        );
        expect(Settings.getValue<String>(SettingsRepository.keyIndexPath), '');
        expect(
          Settings.getValue<String>(SettingsRepository.keyLibraryFolderName),
          isNull,
        );
        expect(
          Settings.getValue<String>(SettingsRepository.keyDbEffectivePath),
          isNull,
        );
        expect(
          Settings.containsKey(SettingsRepository.keyDbEffectivePath),
          isFalse,
        );
        expect(
          Settings.containsKey(SettingsRepository.keyLibraryFolderName),
          isFalse,
        );
        expect(reopenedLibrary, [(replacing ? 'old-db' : 'new-db', null)]);
        expectNoLeftovers();
      },
    );
  }

  blocTest<EmptyLibraryBloc, EmptyLibraryState>(
    'כל כרך חולץ לתיקייה משלו: בחירת תיקיית האב מייבאת את החבילה המלאה',
    setUp: () async {
      if (lib == null) return;
      writeLibrary(lib);
      writeIndex(lib);
      final volume1 = await Directory(
        p.join(
          source.path,
          'otzaria-android-full-part1',
          'otzaria-android-full',
        ),
      ).create(recursive: true);
      final volume2 = await Directory(
        p.join(
          source.path,
          'otzaria-android-full-part2',
          'otzaria-android-full',
        ),
      ).create(recursive: true);
      await File(
        p.join(volume1.path, 'otzaria-android.apk'),
      ).writeAsBytes(_noise(5000, 9));
      for (final file in source.listSync().whereType<File>()) {
        final name = p.basename(file.path);
        final toFirst =
            name == '$_library.part-000' || name == '$_library.manifest.json';
        file.renameSync(p.join((toFirst ? volume1 : volume2).path, name));
      }
      for (final volume in [volume1, volume2]) {
        await File(p.join(volume.path, 'README.txt')).writeAsString('readme');
      }
      final scan = await scanLibrarySource(DirectoryPackageFolder(source.path));
      packages = scan.packages.packages!;
      expect(packages.folder, isA<MergedPackageFolder>());
      expect(packages.library.parts.length, greaterThan(1));
    },
    build: build,
    act: (bloc) async {
      if (lib == null) return markTestSkipped('libzstd אינו זמין');
      bloc.add(
        ImportLibraryPackageRequested(packages: packages, targetPath: books),
      );
      await settle(bloc);
    },
    verify: (bloc) {
      if (lib == null) return;
      expect(bloc.state, isA<EmptyLibraryDirectorySelected>());
      expect(File(p.join(books, _dbName)).readAsStringSync(), 'new-db');
      expect(
        File(p.join(books, 'תלמוד בבלי', 'ברכות.pdf')).lengthSync(),
        400000,
      );
      expect(reopenedLibrary, [('new-db', '{"new":true}')]);
      expectNoLeftovers();
    },
  );

  group('ספרייה קיימת', () {
    setUp(() async {
      await Directory(books).create(recursive: true);
      await File(p.join(books, _dbName)).writeAsString('old-db');
      await Directory(p.join(root, 'index')).create();
      await File(p.join(root, 'index', 'meta.json')).writeAsString('old');
      await Settings.setValue<String>(SettingsRepository.keyLibraryPath, books);
    });

    void expectOldLibraryIntact() {
      expect(File(p.join(books, _dbName)).readAsStringSync(), 'old-db');
      expect(
        File(p.join(root, 'index', 'meta.json')).readAsStringSync(),
        'old',
      );
      expectNoLeftovers();
    }

    blocTest<EmptyLibraryBloc, EmptyLibraryState>(
      'עדכון במקום מחליף את הספרייה ואת האינדקס',
      setUp: () async {
        if (lib == null) return;
        writeLibrary(lib);
        writeIndex(lib);
        packages = await scanned();
      },
      build: build,
      act: (bloc) async {
        if (lib == null) return;
        bloc.add(
          ImportLibraryPackageRequested(
            packages: packages,
            targetPath: books,
            backupExistingPath: books,
          ),
        );
        await settle(bloc, replacing: true);
      },
      verify: (bloc) {
        if (lib == null) return;
        expect(bloc.state, isA<EmptyLibraryDirectorySelected>());
        expect(File(p.join(books, _dbName)).readAsStringSync(), 'new-db');
        expect(
          File(p.join(root, 'index', 'meta.json')).readAsStringSync(),
          '{"new":true}',
        );
        expect(Directory(p.join(root, 'index.replaced')).existsSync(), isFalse);
        expectNoLeftovers();
      },
    );

    for (final failingKey in [
      SettingsRepository.keyIndexPath,
      SettingsRepository.keyLibraryPath,
      SettingsRepository.keyLibraryFolderName,
      SettingsRepository.keyDbEffectivePath,
    ]) {
      blocTest<EmptyLibraryBloc, EmptyLibraryState>(
        'כשל הגדרות $failingKey מחזיר DB ואינדקס תואמים',
        setUp: () async {
          if (lib == null) return;
          writeLibrary(lib);
          writeIndex(lib);
          packages = await scanned();
          await Settings.setValue<String>(
            SettingsRepository.keyIndexPath,
            p.join(root, 'index'),
          );
          await Settings.setValue<String>(
            SettingsRepository.keyLibraryFolderName,
            'ספרייה מקורית',
          );
          await Settings.setValue<String>(
            SettingsRepository.keyDbEffectivePath,
            p.join(books, _dbName),
          );
          cache.failingKey = failingKey;
        },
        build: build,
        act: (bloc) async {
          if (lib == null) return;
          bloc.add(
            ImportLibraryPackageRequested(
              packages: packages,
              targetPath: books,
              backupExistingPath: books,
            ),
          );
          await settle(bloc, replacing: true);
        },
        verify: (bloc) {
          if (lib == null) return;
          expect(bloc.state, isA<EmptyLibraryError>());
          expectOldLibraryIntact();
          expect(
            Directory(p.join(root, 'index.replaced')).existsSync(),
            isFalse,
          );
          expect(
            Settings.getValue<String>(SettingsRepository.keyLibraryPath),
            books,
          );
          expect(
            Settings.getValue<String>(SettingsRepository.keyIndexPath),
            p.join(root, 'index'),
          );
          expect(
            Settings.getValue<String>(SettingsRepository.keyLibraryFolderName),
            'ספרייה מקורית',
          );
          expect(
            Settings.getValue<String>(SettingsRepository.keyDbEffectivePath),
            p.join(books, _dbName),
          );
          expect(indexHostCalls, ['release', 'reopen']);
          expect(reopenedLibrary, [('old-db', 'old')]);
        },
      );
    }

    blocTest<EmptyLibraryBloc, EmptyLibraryState>(
      'ביטול אחרי הפריסה אינו קוטע החלפה שכבר הוגדרה כלא ניתנת לביטול',
      setUp: () async {
        if (lib == null) return;
        writeLibrary(lib);
        writeIndex(lib);
        packages = await scanned();
      },
      build: build,
      act: (bloc) async {
        if (lib == null) return;
        final sub = bloc.stream.listen((state) {
          if (state is EmptyLibraryExtracting &&
              !state.cancellable &&
              state.progress == 1) {
            bloc.add(CancelLibraryImportRequested());
          }
        });
        bloc.add(
          ImportLibraryPackageRequested(
            packages: packages,
            targetPath: books,
            backupExistingPath: books,
          ),
        );
        await settle(bloc, replacing: true);
        await sub.cancel();
      },
      verify: (bloc) {
        if (lib == null) return;
        expect(bloc.state, isA<EmptyLibraryDirectorySelected>());
        expect(reopenedLibrary, [('new-db', '{"new":true}')]);
        expectNoLeftovers();
      },
    );

    blocTest<EmptyLibraryBloc, EmptyLibraryState>(
      'כשל התקנת האינדקס אינו מוחק את האינדקס שהמתקין כבר שחזר',
      setUp: () async {
        if (lib == null) return;
        writeLibrary(lib);
        writeIndex(lib);
        packages = await scanned();
      },
      build: () => build(failInstall: true),
      act: (bloc) async {
        if (lib == null) return;
        bloc.add(
          ImportLibraryPackageRequested(
            packages: packages,
            targetPath: books,
            backupExistingPath: books,
          ),
        );
        await settle(bloc, replacing: true);
      },
      verify: (bloc) {
        if (lib == null) return;
        expect(bloc.state, isA<EmptyLibraryError>());
        expectOldLibraryIntact();
        expect(reopenedLibrary, [('old-db', 'old')]);
        expect(indexHostCalls, ['release', 'reopen']);
      },
    );

    blocTest<EmptyLibraryBloc, EmptyLibraryState>(
      'כשל פתיחת האינדקס לאחר commit משאיר התקנה תואמת ומחדש חלונות',
      setUp: () async {
        if (lib == null) return;
        writeLibrary(lib);
        writeIndex(lib);
        packages = await scanned();
      },
      build: () => build(failReopen: true),
      act: (bloc) async {
        if (lib == null) return;
        bloc.add(
          ImportLibraryPackageRequested(
            packages: packages,
            targetPath: books,
            backupExistingPath: books,
          ),
        );
        await settle(bloc, replacing: true);
      },
      verify: (bloc) {
        if (lib == null) return;
        expect(bloc.state, isA<EmptyLibraryDirectorySelected>());
        expect(reopenedLibrary, [('new-db', '{"new":true}')]);
        expect(indexHostCalls, ['release', 'reopen']);
        expect(Directory(p.join(root, 'index.replaced')).existsSync(), isFalse);
        expectNoLeftovers();
      },
    );

    if (!Platform.isWindows) {
      blocTest<EmptyLibraryBloc, EmptyLibraryState>(
        'כשל ניקוי גיבוי לאחר commit אינו משחזר DB שכבר אינו תואם לאינדקס',
        setUp: () async {
          if (lib == null) return;
          writeLibrary(lib);
          writeIndex(lib);
          packages = await scanned();
        },
        build: () => build(
          afterIndexCommit: () async {
            final backup = EmptyLibraryBloc.dbBackupDirPath;
            addTearDown(() => Process.run('chmod', ['700', backup]));
            final result = await Process.run('chmod', ['500', backup]);
            expect(result.exitCode, 0);
          },
        ),
        act: (bloc) async {
          if (lib == null) return;
          bloc.add(
            ImportLibraryPackageRequested(
              packages: packages,
              targetPath: books,
              backupExistingPath: books,
            ),
          );
          await settle(bloc, replacing: true);
        },
        verify: (bloc) {
          if (lib == null) return;
          expect(bloc.state, isA<EmptyLibraryDirectorySelected>());
          expect(reopenedLibrary, [('new-db', '{"new":true}')]);
          expect(
            File(
              p.join(EmptyLibraryBloc.dbBackupDirPath, _dbName),
            ).readAsStringSync(),
            'old-db',
          );
          expect(
            Directory(p.join(root, 'index.replaced')).existsSync(),
            isFalse,
          );
        },
      );
    }

    for (final cleanupPhase in [
      'beforeCommit',
      'afterCommit',
      'afterDiscard',
    ]) {
      Future<void> failCleanup() async =>
          throw const FileSystemException('simulated cleanup failure');
      blocTest<EmptyLibraryBloc, EmptyLibraryState>(
        'כשל ניקוי $cleanupPhase אינו הופך commit ל-rollback',
        setUp: () async {
          if (lib == null) return;
          writeLibrary(lib);
          writeIndex(lib);
          packages = await scanned();
        },
        build: () => build(
          beforeIndexCommit: cleanupPhase == 'beforeCommit'
              ? failCleanup
              : null,
          afterIndexCommit: cleanupPhase == 'afterCommit' ? failCleanup : null,
          afterStagingDiscard: cleanupPhase == 'afterDiscard'
              ? failCleanup
              : null,
        ),
        act: (bloc) async {
          if (lib == null) return;
          bloc.add(
            ImportLibraryPackageRequested(
              packages: packages,
              targetPath: books,
              backupExistingPath: books,
            ),
          );
          await settle(bloc, replacing: true);
        },
        verify: (bloc) {
          if (lib == null) return;
          expect(bloc.state, isA<EmptyLibraryDirectorySelected>());
          expect(reopenedLibrary, [('new-db', '{"new":true}')]);
          expect(indexHostCalls, ['release', 'reopen']);
          expect(
            Settings.getValue<String>(SettingsRepository.keyLibraryPath),
            books,
          );
          expect(
            Settings.getValue<String>(SettingsRepository.keyIndexPath),
            p.join(root, 'index'),
          );
          expect(
            Directory(p.join(root, 'index.replaced')).existsSync(),
            cleanupPhase == 'beforeCommit',
          );
          expectNoLeftovers();
        },
      );
    }

    blocTest<EmptyLibraryBloc, EmptyLibraryState>(
      'חלק פגום: שגיאה עם שם החלק, והספרייה הקיימת לא נפגעת',
      setUp: () async {
        if (lib == null) return;
        writeLibrary(lib);
        writeIndex(lib);
        final part = File(p.join(source.path, '$_library.part-002'));
        final bytes = part.readAsBytesSync()..[100] ^= 0xFF;
        part.writeAsBytesSync(bytes);
        packages = await scanned();
      },
      build: build,
      act: (bloc) async {
        if (lib == null) return;
        bloc.add(
          ImportLibraryPackageRequested(
            packages: packages,
            targetPath: books,
            backupExistingPath: books,
          ),
        );
        await settle(bloc, replacing: true);
      },
      verify: (bloc) {
        if (lib == null) return;
        final state = bloc.state as EmptyLibraryError;
        expect(state.errorMessage, contains('$_library.part-002'));
        expect(indexHostCalls, isEmpty);
        expectOldLibraryIntact();
      },
    );

    blocTest<EmptyLibraryBloc, EmptyLibraryState>(
      'ביטול באמצע הפריסה: הספרייה הקיימת נשארת ואין שאריות staging',
      setUp: () async {
        if (lib == null) return;
        writeLibrary(lib);
        packages = await scanned();
      },
      build: build,
      act: (bloc) async {
        if (lib == null) return;
        final sub = bloc.stream.listen((s) {
          if (s is EmptyLibraryExtracting && s.cancellable && s.progress > 0) {
            bloc.add(CancelLibraryImportRequested());
          }
        });
        bloc.add(
          ImportLibraryPackageRequested(
            packages: packages,
            targetPath: books,
            backupExistingPath: books,
          ),
        );
        await settle(bloc, replacing: true);
        await sub.cancel();
      },
      verify: (bloc) {
        if (lib == null) return;
        final state = bloc.state as EmptyLibraryError;
        expect(state.errorMessage, contains('בוטל'));
        expectOldLibraryIntact();
      },
    );

    blocTest<EmptyLibraryBloc, EmptyLibraryState>(
      'אין מספיק מקום: נעצר לפני כל כתיבה',
      setUp: () async {
        if (lib == null) return;
        writeLibrary(lib);
        packages = await scanned();
      },
      build: () => build(freeBytes: 1000),
      act: (bloc) async {
        if (lib == null) return;
        bloc.add(
          ImportLibraryPackageRequested(
            packages: packages,
            targetPath: books,
            backupExistingPath: books,
          ),
        );
        await settle(bloc, replacing: true);
      },
      verify: (bloc) {
        if (lib == null) return;
        final state = bloc.state as EmptyLibraryError;
        expect(state.errorMessage, contains('אין מספיק מקום'));
        expectOldLibraryIntact();
      },
    );
  });
}
