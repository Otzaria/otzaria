import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import '../../../integration_test/support/perf_fixture.dart';

void main() {
  late Directory temp;
  setUp(
    () async =>
        temp = await Directory.systemTemp.createTemp('perf-fixture-test-'),
  );
  tearDown(() async {
    await Hive.close();
    AppPaths.debugOverrideDataRootPath(null);
    AppPaths.debugOverrideDocumentsRootPath(null);
    await temp.delete(recursive: true);
  });

  test(
    'fresh fixtures have identical bytes, stable IDs, sizes and neutral text',
    () async {
      final first = PerfFixture(Directory(p.join(temp.path, 'first')));
      final second = PerfFixture(Directory(p.join(temp.path, 'second')));
      await first.prepare(preparationOnly: true);
      await second.prepare(preparationOnly: true);
      expect(first.id, second.id);
      final db = sqlite3.open(first.dbPath, mode: OpenMode.readOnly);
      try {
        final books = db.select(
          'SELECT id,title,totalLines FROM book ORDER BY id',
        );
        expect(books.map((book) => book['id']), [1, 2, 3]);
        expect(books.map((book) => book['title']), perfBooks.keys);
        expect(books.map((book) => book['totalLines']), perfBooks.values);
        expect(db.select('SELECT count(*) AS n FROM line').single['n'], 69760);
        expect(
          db
              .select(
                'SELECT content FROM line WHERE bookId=3 AND lineIndex=65535',
              )
              .single['content'],
          perfLine(65535),
        );
        expect(db.select('SELECT count(*) AS n FROM link').single['n'], 0);
      } finally {
        db.close();
      }
      final prefs = File(p.join(first.appDataPath, 'app_preferences.hive'));
      final before = await prefs.readAsBytes();
      await first.prepare(preparationOnly: false);
      expect(
        await prefs.readAsBytes(),
        before,
        reason: 'Measured startup must not open or reseed Hive.',
      );
      final mutate = sqlite3.open(first.dbPath);
      try {
        mutate.execute("UPDATE line SET content='changed' WHERE id=1");
      } finally {
        mutate.close();
      }
      await expectLater(
        first.prepare(preparationOnly: false),
        throwsStateError,
      );
    },
  );

  test('measured run requires separate preparation', () async {
    final fixture = PerfFixture(Directory(p.join(temp.path, 'unprepared')));
    await expectLater(
      fixture.prepare(preparationOnly: false),
      throwsStateError,
    );
    expect(await File(fixture.dbPath).exists(), isFalse);
  });

  test('nonempty folders are never overwritten by preparation', () async {
    final root = await Directory(p.join(temp.path, 'existing')).create();
    final sentinel = File(p.join(root.path, 'keep.txt'));
    await sentinel.writeAsString('untouched');
    await expectLater(
      PerfFixture(root).prepare(preparationOnly: true),
      throwsStateError,
    );
    expect(await sentinel.readAsString(), 'untouched');
    expect(await root.list().length, 1);
  });
}
