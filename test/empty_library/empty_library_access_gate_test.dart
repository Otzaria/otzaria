import 'dart:async';
import 'dart:io';

import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/windowing/library_suspension_marker.dart';
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/empty_library/bloc/empty_library_bloc.dart';
import 'package:otzaria/empty_library/bloc/empty_library_event.dart';
import 'package:otzaria/empty_library/bloc/empty_library_state.dart';
import 'package:otzaria/empty_library/services/library_package/library_source.dart';
import 'package:otzaria/empty_library/services/library_package/package_folder.dart';
import 'package:otzaria/library_update/services/library_access_gate.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:path/path.dart' as path;

import '../test_helpers/memory_cache_provider.dart';
import 'library_release_test_support.dart';

/// מתעד את קריאות ההשעיה; בלי חלונות אחרים ההשעיה עצמה אמיתית.
class _RecordingGate extends LibraryAccessGate {
  _RecordingGate({this.failSuspend = false})
    : super(
        selfAccess: LibraryAccessRoutine(
          suspend: () async {},
          resume: (_) async {},
        ),
        renameProbe: false,
        logError: (_, _, _) {},
      );

  final bool failSuspend;
  final calls = <String>[];
  final resumed = Completer<void>();

  @override
  Future<LibrarySuspension> suspendAll() async {
    calls.add('suspend');
    if (failSuspend) {
      throw const LibrarySuspendFailed('חלון אחר לא שחרר', slots: [2]);
    }
    return super.suspendAll();
  }

  @override
  Future<void> verifyReleased(String dbPath) async {
    calls.add('verify:${path.basename(dbPath)}');
  }

  @override
  Future<void> resumeAll(
    LibrarySuspension suspension, {
    required bool dbReplaced,
  }) async {
    calls.add('resume:$dbReplaced');
    await super.resumeAll(suspension, dbReplaced: dbReplaced);
    if (!resumed.isCompleted) resumed.complete();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  late Directory libDir;
  late Directory srcDir;
  final dbName = DatabaseConstants.databaseFileName;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('otzaria-gate-bloc-');
    // ההורדה כותבת לשמות קבועים ב-temp; בידוד מריצות מקבילות.
    IOOverrides.global = _TempOverrides(temp);
    EmptyLibraryBloc.tempRootOverride = temp.path;
    libDir = await Directory(path.join(temp.path, 'lib')).create();
    srcDir = await Directory(path.join(temp.path, 'src')).create();
    await File(path.join(libDir.path, dbName)).writeAsString('old-db');
    await Settings.init(cacheProvider: MemoryCacheProvider());
    await Settings.setValue<String>(
      SettingsRepository.keyLibraryPath,
      libDir.path,
    );
  });

  tearDown(() async {
    EmptyLibraryBloc.tempRootOverride = null;
    IOOverrides.global = null;
    LibrarySuspensionMarker.resetForTesting();
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  UpdateLibraryRequested update() => UpdateLibraryRequested(
    targetPath: libDir.path,
    existingLibraryPath: libDir.path,
  );

  /// [db] null — ההורדה נכשלת.
  EmptyLibraryBloc updateBloc(_RecordingGate gate, String? db) =>
      EmptyLibraryBloc(
        accessGate: gate,
        httpClient: fakeLibraryReleaseClient(() => db),
        extractCompressedDatabase: copyAsExtracted,
        extractTarArchive: ignoreTarArchive,
      );

  test('עדכון מוצלח משעה את כל החלונות ומחדש עם דגל החלפה', () async {
    final gate = _RecordingGate();
    final bloc = updateBloc(gate, 'new-db');
    addTearDown(bloc.close);

    bloc.add(update());
    await gate.resumed.future.timeout(const Duration(seconds: 5));

    expect(bloc.state, isA<EmptyLibraryDirectorySelected>());
    expect(gate.calls, ['suspend', 'verify:$dbName', 'resume:true']);
    expect(LibrarySuspensionMarker.isRegistered, isFalse);
    expect(
      await File(path.join(libDir.path, dbName)).readAsString(),
      'new-db',
    );
  });

  test('עדכון שנכשל מחדש את החלונות בלי דגל החלפה', () async {
    final gate = _RecordingGate();
    final bloc = updateBloc(gate, null);
    addTearDown(bloc.close);

    bloc.add(update());
    await gate.resumed.future.timeout(const Duration(seconds: 5));

    expect(bloc.state, isA<EmptyLibraryError>());
    expect(gate.calls, ['suspend', 'verify:$dbName', 'resume:false']);
    expect(
      await File(path.join(libDir.path, dbName)).readAsString(),
      'old-db',
    );
  });

  test('חלון שלא שחרר: המסד לא זז והמשתמש מקבל שגיאה', () async {
    final gate = _RecordingGate(failSuspend: true);
    final bloc = updateBloc(gate, 'new-db');
    addTearDown(bloc.close);

    final error = bloc.stream
        .where((s) => s is EmptyLibraryError)
        .cast<EmptyLibraryError>()
        .first;
    bloc.add(update());
    final state = await error.timeout(const Duration(seconds: 5));

    expect(state.errorMessage, contains('חלון אחר לא שחרר'));
    expect(gate.calls, ['suspend']);
    expect(
      await File(path.join(libDir.path, dbName)).readAsString(),
      'old-db',
    );
    expect(Directory(EmptyLibraryBloc.dbBackupDirPath).existsSync(), isFalse);
  });

  test('ייבוא תיקייה עם גיבוי עובר דרך ההשעיה', () async {
    await File(path.join(srcDir.path, dbName)).writeAsString('new-db');
    final gate = _RecordingGate();
    final bloc = EmptyLibraryBloc(accessGate: gate);
    addTearDown(bloc.close);

    bloc.add(
      ImportLibraryFolderRequested(
        assets: await scanRawLibraryAssets(DirectoryPackageFolder(srcDir.path)),
        targetPath: libDir.path,
        backupExistingPath: libDir.path,
      ),
    );
    await gate.resumed.future.timeout(const Duration(seconds: 5));

    expect(gate.calls, ['suspend', 'verify:$dbName', 'resume:true']);
  });
}

final class _TempOverrides extends IOOverrides {
  _TempOverrides(this.root);

  final Directory root;

  @override
  Directory getSystemTempDirectory() => root;
}
