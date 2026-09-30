import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/find_ref/repository/find_ref_repository.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';

import 'support/seeded_reference_library.dart';

Future<FindRefRepository> _sqliteRepo({
  required List<(String, int)> toc,
  required List<(String, String, int)> altToc,
}) async {
  final dir = await Directory.systemTemp.createTemp('otzaria_dedupe');
  final database = MyDatabase.withPath('${dir.path}/seforim.db');
  addTearDown(() async {
    database.close();
    resetSeededLibrary();
    await dir.delete(recursive: true);
  });
  final db = await database.database;
  db.execute("INSERT INTO category(id,title,level) VALUES(1,'ספרייה',0)");
  db.execute("INSERT INTO source(id,name) VALUES(1,'אוצריא')");
  db.execute(
    "INSERT INTO book(id,categoryId,sourceId,title,orderIndex,filePath,fileType) "
    "VALUES(1,1,1,'ספר בדיקה',1,'/b.txt','txt')",
  );
  final segments = {
    for (final row in toc) row.$2,
    for (final row in altToc) row.$3,
  };
  for (final segment in segments) {
    db.execute(
      'INSERT INTO line(id,bookId,lineIndex,content) VALUES(?,1,?,?)',
      [segment, segment, 'שורה'],
    );
  }
  var textId = 0;
  final textIds = <String, int>{};
  int insertText(String text) {
    final existing = textIds[text];
    if (existing != null) return existing;
    db.execute('INSERT INTO tocText(id,text) VALUES(?,?)', [++textId, text]);
    return textIds[text] = textId;
  }

  for (var i = 0; i < toc.length; i++) {
    final (text, segment) = toc[i];
    db.execute(
      'INSERT INTO tocEntry(id,bookId,parentId,textId,level,lineId) '
      'VALUES(?,1,NULL,?,1,?)',
      [i + 1, insertText(text), segment],
    );
  }
  for (var i = 0; i < altToc.length; i++) {
    final (root, leaf, segment) = altToc[i];
    final structure = i + 1;
    final rootId = 2 * i + 1;
    db.execute(
      'INSERT INTO alt_toc_structure(id,bookId,key) VALUES(?,1,?)',
      [structure, 'edition-$structure'],
    );
    db.execute(
      'INSERT INTO alt_toc_entry(id,structureId,parentId,textId,level,lineId) '
      'VALUES(?,?,NULL,?,0,?),(?,?,?,?,1,?)',
      [
        rootId,
        structure,
        insertText(root),
        segment,
        rootId + 1,
        structure,
        rootId,
        insertText(leaf),
        segment,
      ],
    );
  }
  final seforim = SeforimRepository(database);
  await seforim.ensureInitialized();
  seedLibrary(const [(id: 1, title: 'ספר בדיקה', acronyms: [])]);
  const tokens = ['א', 'פרק', 'א', 'פרשה', 'א'];
  final partials = await seforim.getTocEntriesForReference(
    1,
    'ספר בדיקה',
    queryTokens: tokens,
  );
  final full = await seforim.getAltTocEntriesForReference(
    1,
    'ספר בדיקה',
    queryTokens: tokens,
  );
  expect(partials, hasLength(toc.length));
  expect(partials.every((r) => r['partialMatch'] == true), isTrue);
  expect(full, hasLength(altToc.length));
  final repo = FindRefRepository(
    isReferenceBooksCacheLoaded: () => true,
    getTocEntriesForReference: (id, title, {queryTokens}) =>
        seforim.getTocEntriesForReference(id, title, queryTokens: queryTokens),
    getAltTocEntriesForReference: (id, title, {queryTokens}) => seforim
        .getAltTocEntriesForReference(id, title, queryTokens: queryTokens),
    getAltStructureBookIds: () async => [1],
    getCategoryPath: (_) async => 'ספרייה',
    getAllAltTocFlatEntries: () async => const [],
  );
  addTearDown(repo.dispose);
  return repo;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('שורה וכתובת מגשרות בין TOC חלקי ושתי מהדורות AltToc מלאות', () async {
    final repo = await _sqliteRepo(
      toc: [('פרשה א', 20)],
      altToc: [('פרשה א', 'פרק א', 10), ('פרשה א', 'פרק א', 20)],
    );
    final results = await repo.findRefs('ספר בדיקה א פרק א פרשה א');
    expect(results, hasLength(1));
    expect(results.single.reference, 'ספר בדיקה פרשה א פרק א');
    expect(results.single.segment, 10);
    expect(results.single.isPartialTocMatch, isFalse);
  });

  test('שרשרת גשרים שומרת כינויים ישנים ואת ההתאמה המלאה הראשונה', () async {
    final repo = await _sqliteRepo(
      toc: [('פרשה א', 20)],
      altToc: [
        ('פרשה א', 'פרק א', 10),
        ('פרשה א', 'פרק א', 20),
        ('פרק א', 'פרשה א', 20),
        ('פרק א', 'פרשה א', 30),
        ('פרק א', 'פרשה א', 40),
        ('פרשה א', 'פרק א', 50),
      ],
    );
    final results = await repo.findRefs('ספר בדיקה א פרק א פרשה א');
    expect(results, hasLength(1));
    expect(results.single.reference, 'ספר בדיקה פרשה א פרק א');
    expect(results.single.segment, 10);
    expect(results.single.isPartialTocMatch, isFalse);
  });
}
