import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/attached_libraries/repository/external_link_core.dart';
import 'package:otzaria/migration/database/untrusted_database.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  for (final platform in [
    TargetPlatform.windows,
    TargetPlatform.linux,
    TargetPlatform.macOS,
    TargetPlatform.android,
    TargetPlatform.iOS,
  ]) {
    for (final untrusted in [false, true]) {
      test(
        '${platform.name}: מיון שומר סדר, אחסון והקשחת מקור (untrusted=$untrusted)',
        () {
          final desktop = switch (platform) {
            TargetPlatform.windows ||
            TargetPlatform.linux ||
            TargetPlatform.macOS => true,
            _ => false,
          };
          debugDefaultTargetPlatformOverride = platform;
          addTearDown(() => debugDefaultTargetPlatformOverride = null);
          // Android may have no SQLite-writable temp directory on a fresh install.
          // Deny temp-file creation on mobile rather than hiding that failure in a VFS.
          final vfs = _RecordingVfs(rejectTemporaryFiles: !desktop);
          sqlite3.registerVirtualFileSystem(vfs, makeDefault: true);
          addTearDown(() => sqlite3.unregisterVirtualFileSystem(vfs));
          const count = 12000;
          final db = sqlite3.open('/source.db');
          addTearDown(db.close);
          db.execute('''
      CREATE TABLE book (id INTEGER PRIMARY KEY, title TEXT);
      CREATE TABLE external_link (
        sourceBookId INTEGER, sourceLineIndex INTEGER, targetTitle TEXT,
        targetSource TEXT, targetLineIndex INTEGER
      );
      INSERT INTO book VALUES (1, '${'s' * 400}');
      WITH RECURSIVE numbers(n) AS (
        SELECT $count - 1 UNION ALL SELECT n - 1 FROM numbers WHERE n > 0
      )
      INSERT INTO external_link
      SELECT 1, n, 'target', 'official', 0 FROM numbers;
    ''');
          final target = sqlite3.open('/target.db');
          target.execute('''
      CREATE TABLE book (id INTEGER PRIMARY KEY, title TEXT);
      CREATE TABLE line (bookId INTEGER, lineIndex INTEGER);
      INSERT INTO book VALUES (1, 'target');
      INSERT INTO line VALUES (1, 0);
    ''');
          target.close();
          List<int> scan() {
            final lines = <int>[];
            expect(
              readResolvedExternalLinks(
                source: (
                  path: '/source.db',
                  untrusted: untrusted,
                  immutable: false,
                ),
                sourceWireKey: 'd:source',
                targets: [
                  (
                    wireKey: 'o',
                    slug: null,
                    target: trustedDbTarget('/target.db'),
                    version: '1',
                  ),
                ],
                onRow: (row) => lines.add(row.sourceLineIndex),
              ),
              isEmpty,
            );
            return lines;
          }

          vfs.temporaryFiles = 0;
          final unindexed = scan();
          expect(vfs.temporaryFiles, desktop ? greaterThan(0) : 0);
          expect(unindexed, List.generate(count, (index) => index));

          db.execute(
            'CREATE INDEX source_order ON external_link(sourceBookId, sourceLineIndex)',
          );
          vfs.temporaryFiles = 0;
          expect(scan(), unindexed);
          expect(vfs.temporaryFiles, 0);
        },
      );
    }
  }
}

final class _RecordingVfs extends BaseVirtualFileSystem {
  _RecordingVfs({required this.rejectTemporaryFiles})
    : super(name: 'external-link-sort-test');

  final bool rejectTemporaryFiles;

  final _files = InMemoryFileSystem();
  var temporaryFiles = 0;

  @override
  int xAccess(String path, int flags) => _files.xAccess(path, flags);

  @override
  void xDelete(String path, int syncDir) => _files.xDelete(path, syncDir);

  @override
  String xFullPathName(String path) => _files.xFullPathName(path);

  @override
  XOpenResult xOpen(Sqlite3Filename path, int flags) {
    if (flags & SqlFlag.SQLITE_OPEN_DELETEONCLOSE != 0) {
      temporaryFiles++;
      if (rejectTemporaryFiles) {
        throw const VfsException(SqlExtendedError.SQLITE_IOERR_GETTEMPPATH);
      }
    }
    return _files.xOpen(path, flags);
  }

  @override
  void xSleep(Duration duration) {}
}
