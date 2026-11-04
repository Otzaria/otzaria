import 'dart:io';

import 'package:bloc_test/bloc_test.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/data/data_providers/user_books_database_holder.dart';
import 'package:otzaria/settings/services/custom_folders/bloc/custom_folders_bloc.dart';
import 'package:otzaria/user_content_import/services/user_import_library.dart';
import 'package:path/path.dart' as p;

import '../../../test_helpers/memory_cache_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late int fileId;
  final previousDataRoot = AppPaths.cachedDataRootPath;

  setUp(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
    tempDir = await Directory.systemTemp.createTemp('otzaria_import_files');
    await UserBooksDatabaseHolder.instance.close();
    AppPaths.debugOverrideDataRootPath(p.join(tempDir.path, 'data_root'));

    // קובץ דורות עם כותרת בלבד: נקלט בלי ספרים במסד, ולכן מתאים לבדיקת
    // החיווט של ה-bloc בלי תלות בספרייה.
    final csv = File(p.join(tempDir.path, 'דורות.csv'))
      ..writeAsStringSync('ספר,דור,מחבר\n');
    final userDb = (await UserBooksDatabaseHolder.instance.repository).database;
    final library = UserImportLibrary(userDb);
    await library.addFiles([csv.path]);
    fileId = (await library.list()).single.id;
  });

  tearDown(() async {
    await UserBooksDatabaseHolder.instance.close();
    AppPaths.debugOverrideDataRootPath(previousDataRoot);
    await tempDir.delete(recursive: true);
  });

  CustomFoldersBloc build() => CustomFoldersBloc(addLibraryEvent: (_) {});

  blocTest<CustomFoldersBloc, CustomFoldersState>(
    'LoadUserImportFiles טוען את הקבצים השמורים',
    build: build,
    act: (bloc) => bloc.add(const LoadUserImportFiles()),
    verify: (bloc) {
      expect(bloc.state.importFiles.single.name, 'דורות.csv');
      expect(bloc.state.importFiles.single.enabled, isTrue);
    },
  );

  blocTest<CustomFoldersBloc, CustomFoldersState>(
    'SetUserImportFileEnabled משהה ומרענן את הרשימה',
    build: build,
    // הכתיבה רצה ב-isolate, ולכן ממתינים לסיום ולא רק לתור האירועים.
    act: (bloc) async {
      bloc.add(SetUserImportFileEnabled(fileId, enabled: false));
      await bloc.stream.firstWhere((state) => !state.isSyncing);
    },
    verify: (bloc) {
      expect(bloc.state.isSyncing, isFalse);
      expect(bloc.state.error, isNull);
      expect(bloc.state.importFiles.single.enabled, isFalse);
    },
  );

  blocTest<CustomFoldersBloc, CustomFoldersState>(
    'RemoveUserImportFile מסיר את הקובץ מהרשימה',
    build: build,
    act: (bloc) async {
      bloc.add(RemoveUserImportFile(fileId));
      await bloc.stream.firstWhere((state) => !state.isSyncing);
    },
    verify: (bloc) {
      expect(bloc.state.isSyncing, isFalse);
      expect(bloc.state.error, isNull);
      expect(bloc.state.importFiles, isEmpty);
    },
  );
}
