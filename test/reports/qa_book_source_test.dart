import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/data/data_providers/db_read_worker.dart';
import 'package:otzaria/data/data_providers/sqlite_data_provider.dart';
import 'package:otzaria/data/data_providers/user_books_database_holder.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/text_book/view/error_report_dialog.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import '../helpers/seforim_fixture_db.dart';
import '../test_helpers/memory_cache_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late String dbPath;
  final previousRoot = AppPaths.cachedDataRootPath;
  final target = <String, dynamic>{
    'bookTitle': SeforimFixtureIds.bereshitTitle,
    'libraryVersion': '1',
    'source': {
      'bookId': SeforimFixtureIds.bereshitId,
      'lineIndex': 0,
      'heRef': 'בראשית א, א',
      'originalLine': 'בראשית א',
    },
  };

  setUp(() async {
    directory = Directory.systemTemp.createTempSync('qa_book_source_');
    dbPath = SeforimFixtureDb.create(directory, SeforimFixtureVariant.full);
    await Settings.init(cacheProvider: MemoryCacheProvider());
    AppPaths.debugOverrideDataRootPath('${directory.path}/data');
    await Settings.setValue<String>(SettingsRepository.keyLibraryPath, directory.path);
    await Settings.setValue<String>(SettingsRepository.keyLibraryFolderName, '');
    await Settings.setValue<String>(SettingsRepository.keyDbEffectivePath, dbPath);
    await SqliteDataProvider.instance.dispose();
    await SqliteDataProvider.instance.initialize();
  });
  tearDown(() async {
    await SqliteDataProvider.instance.dispose();
    await UserBooksDatabaseHolder.instance.close();
    DbReadWorker.disposeForTesting();
    AppPaths.debugOverrideDataRootPath(previousRoot);
    directory.deleteSync(recursive: true);
  });

  Future<void> replaceLibraryData(String sql, [List<Object?> args = const []]) async {
    // Follow the existing library replacement lifecycle, which invalidates
    // readers before replacing or editing database content.
    await SqliteDataProvider.instance.dispose();
    DbReadWorker.disposeForTesting();
    final writer = sqlite3.sqlite3.open(dbPath);
    try {
      writer.execute(sql, args);
    } finally {
      writer.close();
    }
    await SqliteDataProvider.instance.initialize();
  }

  test(
    'QA source check accepts the frozen exact row and rejects a changed build',
    () async {
      expect(await ErrorReportHelper.draftSourceMatches(target), isTrue);
      await replaceLibraryData("UPDATE schema_meta SET value='2' WHERE key='db_version'");
      expect(await ErrorReportHelper.draftSourceMatches(target), isFalse);
    },
  );

  test(
    'QA source check rejects a changed raw line even when the build is unchanged',
    () async {
      expect(await ErrorReportHelper.draftSourceMatches(target), isTrue);
      await replaceLibraryData('UPDATE line SET content=? WHERE bookId=1 AND lineIndex=0',
        ['<b>בראשית</b> א']);
      expect(await ErrorReportHelper.draftSourceMatches(target), isFalse,
        reason: 'Equal rendered text is insufficient: raw HTML must match exactly.');
    },
  );

  test(
    'QA source check rejects a changed reference or missing source instead of retargeting',
    () async {
      expect(await ErrorReportHelper.draftSourceMatches(target), isTrue);
      await replaceLibraryData('UPDATE line SET heRef=? WHERE bookId=1 AND lineIndex=0',
        ['בראשית א, ב']);
      expect(await ErrorReportHelper.draftSourceMatches(target), isFalse);
      expect(await ErrorReportHelper.draftSourceMatches({...target, 'source': null}), isFalse);
      expect(await ErrorReportHelper.draftSourceMatches({
        ...target,
        'source': {...Map<String, dynamic>.from(target['source'] as Map), 'bookId': 2},
      }), isFalse);
    },
  );
}
