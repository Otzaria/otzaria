import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/empty_library/bloc/empty_library_bloc.dart';
import 'package:otzaria/empty_library/bloc/empty_library_event.dart';
import 'package:otzaria/empty_library/bloc/empty_library_state.dart';
import 'package:otzaria/empty_library/services/library_package/library_package_importer.dart';
import 'package:otzaria/empty_library/services/library_package/library_source.dart';
import 'package:otzaria/empty_library/services/library_package/package_folder.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/utils/file/disk_free_space.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import '../test_helpers/memory_cache_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temporary;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('library-db-validation-');
    EmptyLibraryBloc.tempRootOverride = temporary.path;
  });
  tearDown(() async {
    EmptyLibraryBloc.tempRootOverride = null;
    await temporary.delete(recursive: true);
  });

  String database(String name, {int? schema}) {
    final file = p.join(temporary.path, name);
    final db = sqlite3.sqlite3.open(file);
    try {
      db.execute('CREATE TABLE marker (value TEXT)');
      db.execute("INSERT INTO marker VALUES ('previous library')");
      if (schema != null) {
        db.execute(
          'CREATE TABLE schema_meta (key TEXT PRIMARY KEY, value TEXT)',
        );
        db.execute("INSERT INTO schema_meta VALUES ('db_schema_version', ?)", [
          schema.toString(),
        ]);
      }
    } finally {
      db.close();
    }
    return file;
  }

  test('healthy legacy SQLite without schema metadata remains readable', () {
    final file = database('legacy.db');
    expect(
      () => EmptyLibraryBloc.requireHealthyDatabase(file),
      returnsNormally,
    );
  });

  test('healthy supported schema passes and future schema is rejected', () {
    final supported = database('supported.db', schema: 6);
    final future = database('future.db', schema: 100000);
    expect(
      () => EmptyLibraryBloc.requireHealthyDatabase(supported),
      returnsNormally,
    );
    expect(
      () => EmptyLibraryBloc.requireHealthyDatabase(future),
      throwsA(isA<UnsupportedDbSchemaException>()),
    );
    // Companion databases use their own schema while retaining SQLite checks.
    expect(
      () => EmptyLibraryBloc.requireHealthyDatabase(
        future,
        verifyLibrarySchema: false,
      ),
      returnsNormally,
    );
  });

  for (final empty in [false, true]) {
    test('non-SQLite output is rejected: empty=$empty', () {
      final file = File(p.join(temporary.path, 'invalid.db'))
        ..writeAsStringSync(empty ? '' : 'not a SQLite database');
      expect(
        () => EmptyLibraryBloc.requireHealthyDatabase(file.path),
        throwsFormatException,
      );
    });
  }

  test('truncated SQLite and damaged b-tree pages fail before publication', () {
    final truncated = database('truncated.db');
    final truncatedHandle = File(truncated).openSync(mode: FileMode.append);
    truncatedHandle.truncateSync(512);
    truncatedHandle.closeSync();
    final damaged = database('damaged.db');
    final bytes = File(damaged).readAsBytesSync();
    bytes[100] = 0xff; // Invalid page type, retaining the SQLite file header.
    File(damaged).writeAsBytesSync(bytes);
    for (final file in [truncated, damaged]) {
      expect(
        () => EmptyLibraryBloc.requireHealthyDatabase(file),
        throwsFormatException,
      );
    }
  });

  test(
    'raw import with corrupt output preserves installed SQLite and source',
    () async {
      await Settings.init(cacheProvider: MemoryCacheProvider());
      final source = Directory(p.join(temporary.path, 'source'))..createSync();
      final incoming = File(p.join(source.path, 'seforim.db'))
        ..writeAsStringSync('not a SQLite database');
      final books = Directory(p.join(temporary.path, 'books'))..createSync();
      final installed = File(
        database('previous.db'),
      ).renameSync(p.join(books.path, 'seforim.db'));
      final previous = installed.readAsBytesSync();
      final bloc = EmptyLibraryBloc(
        downloadSpaceChecker: (_) async => null,
        packageImporter: LibraryPackageImporter(
          diskSpace: (_) async => DiskSpaceInfo.unknown,
        ),
      );
      addTearDown(bloc.close);
      final terminal = bloc.stream
          .where(
            (state) =>
                state is EmptyLibraryError ||
                state is EmptyLibraryDirectorySelected,
          )
          .first;
      bloc.add(
        ImportLibraryFolderRequested(
          assets: await scanRawLibraryAssets(
            DirectoryPackageFolder(source.path),
          ),
          targetPath: books.path,
        ),
      );
      expect(
        await terminal.timeout(const Duration(seconds: 10)),
        isA<EmptyLibraryError>(),
      );
      expect(installed.readAsBytesSync(), previous);
      expect(incoming.readAsStringSync(), 'not a SQLite database');
      expect(Directory('${books.path}.import').existsSync(), isFalse);
    },
  );
}
