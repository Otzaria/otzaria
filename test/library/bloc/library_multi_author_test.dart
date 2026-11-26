import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/data/constants/database_constants.dart';
import 'package:otzaria/data/data_providers/database_library_provider.dart';
import 'package:otzaria/data/data_providers/user_books_database_holder.dart';
import 'package:otzaria/data/repository/data_repository.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/library/bloc/library_event.dart';
import 'package:otzaria/library/bloc/library_state.dart';
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import '../../helpers/seforim_fixture_db.dart';
import '../../test_helpers/memory_cache_provider.dart';

class _Repository extends Fake implements DataRepository {}

/// שם מחבר אמיתי מהקטלוג שיש בו ", " — אינו שני מחברים.
const _teitelbaum = 'הרב יואל טייטלבוים, האדמו"ר מסאטמר';

/// ספר של כמה מחברים: "כל ספרי המחבר" לכל אחד מהם (issue #4231).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final provider = DatabaseLibraryProvider.instance;
  final previousDataRoot = AppPaths.cachedDataRootPath;
  late Directory tempDir;
  late String libraryPath;

  setUp(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
    tempDir = await Directory.systemTemp.createTemp('otzaria_multi_author');
    libraryPath = p.join(tempDir.path, 'library');
    Directory(libraryPath).createSync();
    await UserBooksDatabaseHolder.instance.close();
    AppPaths.debugOverrideDataRootPath(p.join(tempDir.path, 'data_root'));
    await Settings.setValue<String>(
      SettingsRepository.keyLibraryPath,
      libraryPath,
    );
    await Settings.setValue<String>(
      SettingsRepository.keyLibraryFolderName,
      '',
    );
    await Settings.setValue<String>(SettingsRepository.keyDbEffectivePath, '');
  });

  tearDown(() async {
    provider.clearCache();
    await provider.sqliteProvider.dispose();
    await UserBooksDatabaseHolder.instance.close();
    AppPaths.debugOverrideDataRootPath(previousDataRoot);
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  /// "בראשית" של רש"י ושל [_teitelbaum] יחד; "רש"י על בראשית" של רש"י לבדו.
  Future<Library> buildCatalog() async {
    final created = SeforimFixtureDb.create(
      Directory(libraryPath),
      SeforimFixtureVariant.full,
    );
    final db = sqlite3.sqlite3.open(created);
    db.execute('INSERT INTO author VALUES (2, ?)', [_teitelbaum]);
    db.execute('INSERT INTO book_author VALUES (?, 1), (?, 2)', [
      SeforimFixtureIds.bereshitId,
      SeforimFixtureIds.bereshitId,
    ]);
    db.close();
    File(
      created,
    ).renameSync(p.join(libraryPath, DatabaseConstants.databaseFileName));
    await provider.sqliteProvider.dispose();
    provider.clearCache();
    await provider.initialize();
    return provider.buildLibraryCatalog({}, libraryPath);
  }

  Future<List<String>> authorBooks(Library library, String author) async {
    final bloc = LibraryBloc(repository: _Repository());
    addTearDown(bloc.close);
    bloc.emit(LibraryState(library: library, currentCategory: library));
    bloc.add(ShowAuthorBooks(author));
    final state = await bloc.stream.firstWhere((s) => s.authorFilter != null);
    return state.searchResults!.map((book) => book.title).toList();
  }

  group('multi-author books (issue #4231)', () {
    test('המחבר של ספר יחיד מוצא גם את הספר שכתב עם אחר', () async {
      final library = await buildCatalog();

      expect(
        await authorBooks(library, SeforimFixtureIds.authorName),
        unorderedEquals([
          SeforimFixtureIds.bereshitTitle,
          SeforimFixtureIds.rashiTitle,
        ]),
      );
    });

    test('שם מחבר שיש בו פסיק אינו מתפצל, ומוצא את ספרו', () async {
      final library = await buildCatalog();

      expect(await authorBooks(library, _teitelbaum), [
        SeforimFixtureIds.bereshitTitle,
      ]);
      expect(await authorBooks(library, 'האדמו"ר מסאטמר'), isEmpty);
    });

    test('המחרוזת המוצגת עדיין מחברת את כל השמות ב-", "', () async {
      final library = await buildCatalog();
      final bereshit = library.getAllBooks().singleWhere(
        (book) => book.title == SeforimFixtureIds.bereshitTitle,
      );

      expect(bereshit.author, '$_teitelbaum, ${SeforimFixtureIds.authorName}');
    });
  });
}
