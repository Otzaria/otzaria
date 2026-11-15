import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/find_ref/repository/find_ref_repository.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/migration/models/category.dart';
import 'package:otzaria/migration/models/line.dart';
import 'package:otzaria/migration/models/toc_entry.dart';
import 'package:otzaria/utils/text/text_manipulation.dart';

import 'support/seeded_reference_library.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late MyDatabase database;
  late SeforimRepository data;
  late FindRefRepository finder;
  late int categoryId;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('structure-reference-');
    database = MyDatabase.withPath('${directory.path}/test.db');
    data = SeforimRepository(database);
    await data.ensureInitialized();
    final db = await database.database;
    db.execute(
      'CREATE TABLE line_dh (bookId INTEGER NOT NULL, dhText TEXT NOT NULL, '
      'lineIndex INTEGER NOT NULL, dhDisplay TEXT NOT NULL, '
      'PRIMARY KEY (bookId, dhText, lineIndex)) WITHOUT ROWID',
    );
    categoryId = await data.insertCategory(
      const Category(title: 'ספרייה', parentId: null, level: 0),
    );
    finder = FindRefRepository(
      isReferenceBooksCacheLoaded: () => true,
      warmUpReferenceBooksCache: () async {},
      getTocEntriesForReference: data.getTocEntriesForReference,
      getAltTocEntriesForReference: data.getAltTocEntriesForReference,
      getAllAltTocFlatEntries: () async => [],
      getCategoryPath: (_) async => 'ספרייה',
      resolveLineRefs: (ids, key) async => {
        for (final row in (await data.resolveRefKeyInBooks(ids, key)).entries)
          row.key: (
            lineIndex: row.value.lineIndex,
            lineId: row.value.lineId,
            heRef: row.value.heRef,
          ),
      },
      resolveDibburim:
          (
            ids,
            prefix, {
            containsBookIds = const [],
            locations = const {},
          }) async => [
            for (final row in await data.resolveDibburimInBooks(
              ids,
              prefix,
              containsBookIds: containsBookIds,
              locations: locations,
            ))
              {
                'bookId': row.bookId,
                'lineIndex': row.lineIndex,
                'lineId': row.lineId,
                'display': row.display,
                'heRef': row.heRef,
              },
          ],
    );
  });

  tearDown(() async {
    finder.disposeForTesting();
    resetSeededLibrary();
    database.close();
    await directory.delete(recursive: true);
  });

  Future<int> book(String title) async {
    final id = await data.insertExternalContentBook(
      categoryId: categoryId,
      title: title,
      filePath: '/tmp/reference.txt',
      fileType: 'txt',
      fileSize: 0,
      lastModified: 0,
      isPersonal: true,
    );
    seedLibrary([(id: id, title: title, acronyms: <String>[])]);
    return id;
  }

  Future<void> dibbur(int id, int index, String display, String heRef) async {
    await data.insertLine(
      Line(bookId: id, lineIndex: index, content: display, heRef: heRef),
    );
    final db = await database.database;
    db.execute(
      'INSERT INTO line_dh (bookId, lineIndex, dhText, dhDisplay) '
      'VALUES (?, ?, ?, ?)',
      [id, index, normalizeForFindRefMatch(display), display],
    );
  }

  Future<void> headings(int id, List<(int, String)> values) async {
    final db = await database.database;
    db.execute(
      'INSERT INTO alt_toc_structure (bookId, key, title, heTitle) '
      'VALUES (?, ?, ?, ?)',
      [id, 'Topic', 'Topic', 'נושאים'],
    );
    final structureId = db.lastInsertRowId;
    for (final (index, heading) in values) {
      final lineId = await data.insertLine(
        Line(bookId: id, lineIndex: index, content: heading),
      );
      db.execute('INSERT INTO tocText (text) VALUES (?)', [heading]);
      db.execute(
        'INSERT INTO alt_toc_entry (structureId, parentId, textId, level, '
        'lineId, isLastChild, hasChildren) VALUES (?, NULL, ?, 0, ?, 1, 0)',
        [structureId, db.lastInsertRowId, lineId],
      );
    }
  }

  Future<int> toc(int id, int index, String heading, {int? parentId}) async {
    final lineId = await data.insertLine(
      Line(bookId: id, lineIndex: index, content: heading),
    );
    return data.insertTocEntry(
      TocEntry(
        id: 0,
        bookId: id,
        text: heading,
        parentId: parentId,
        level: parentId == null ? 1 : 2,
        lineId: lineId,
        lineIndex: index,
        isLastChild: true,
        hasChildren: false,
      ),
    );
  }

  test('ד״ה סעיף קטן אינו מתחלף בדיבור ס״ק מאותו ספר', () async {
    const title = 'יד אפרים על שלחן ערוך אורח חיים';
    final id = await book(title);
    await dibbur(id, 1264, 'ס"ק יו"ד', '$title, תרו, ג');
    await dibbur(id, 1287, 'סעיף קטן יו"ד', '$title, תריג, ג');

    for (final marker in ['ד"ה', 'ד״ה', 'דיבור המתחיל']) {
      final results = await finder.findRefs('$title $marker סעיף קטן יוד');
      expect(results.where((r) => r.isSourceLine).map((r) => r.segment), [
        1287,
      ]);
    }
    final abbreviated = await finder.findRefs('$title ד״ה ס"ק יוד');
    expect(abbreviated.where((r) => r.isSourceLine).map((r) => r.segment), [
      1264,
    ]);
  });

  test('סעיף קטן באמצע ד״ה נשמר גם אחרי מילת מבנה אחרת', () async {
    const title = 'נקודות הכסף על שולחן ערוך יורה דעה';
    final id = await book(title);
    await dibbur(
      id,
      72,
      'סימן כ"ז ט"ז סעיף קטן א\') ותירץ אחי מהר"י הלוי כו\'',
      '$title, כז, א',
    );
    await dibbur(
      id,
      657,
      'שם בש"ך סעיף קטן ו\') והב"ח פסק כו\'',
      '$title, רכא, ב',
    );
    for (final (prefix, expected) in [
      ('סימן כז טז סעיף קטן א', 72),
      ('שם בשך סעיף קטן ו', 657),
    ]) {
      final results = await finder.findRefs('$title ד״ה $prefix');
      expect(results.where((r) => r.isSourceLine).map((r) => r.segment), [
        expected,
      ]);
    }
  });

  for (final (query, heading) in [
    ('הלכה א', 'אות א'),
    ('אות א', 'הלכה א'),
    ('דין א', 'אות א'),
    ('פסקה א', 'אות א'),
    ('כלל א', 'שער א'),
    ('שער א', 'כלל א'),
    ('מאמר א', 'שער א'),
    ('סעיף קטן א', 'סעיף א'),
    ('ס"ק א', 'סעיף א'),
    ('סעיף א', 'סק א'),
    ('סימן א', 'תשובה א'),
  ]) {
    test('AltToc: $query מגיע למשתמש כ־$heading בלבד', () async {
      const title = 'תוספות רבי עקיבא איגר על משנה תענית';
      final id = await book(title);
      await headings(id, [(4, heading), (9, heading.replaceFirst(' א', ' ב'))]);
      final results = await finder.findRefs('$title $query');
      expect(results.where((r) => r.isAltToc).map((r) => r.segment), [4]);
      expect(results.where((r) => r.isAltToc).map((r) => r.bookId), [id]);
    });
  }

  test('AltToc: שם מילולי קודם לחלופה גם כשזו מוקדמת יותר', () async {
    const title = 'תוספות רבי עקיבא איגר על משנה תענית';
    final id = await book(title);
    await headings(id, [(4, 'אות א'), (9, 'הלכה א')]);
    final results = await finder.findRefs('$title הלכה א');
    expect(results.where((r) => r.isAltToc).map((r) => r.segment), [9]);
  });

  test('ס״ק מילולי ב־TOC קודם לסעיף מחלוקה חלופית', () async {
    const title = 'כף החיים על שולחן ערוך אורח חיים';
    final id = await book(title);
    await toc(id, 5, 'סעיף קטן ב');
    await headings(id, [(16, 'סעיף ב')]);
    final results = await finder.findRefs('$title ס״ק ב');
    expect(results.map((r) => (r.isAltToc, r.segment)), [(false, 5)]);
  });

  test('קדימות מילולית שומרת סי↔סימן וטרנספוזיציית מספר', () async {
    const title = 'כף החיים על שולחן ערוך אורח חיים';
    final id = await book(title);
    final parent = await toc(id, 2, 'סימן לט');
    await toc(id, 5, 'סעיף קטן ב', parentId: parent);
    await headings(id, [(16, 'סימן לט סעיף ב')]);
    final results = await finder.findRefs('$title סי טל ס״ק ב');
    expect(results.map((r) => (r.isAltToc, r.segment)), [(false, 5)]);
  });

  test('TOC חלקי אינו חוסם שם חלופי מלא ב־AltToc', () async {
    const title = 'ספר ניסיוני';
    final id = await book(title);
    await toc(id, 5, 'סימן א');
    await headings(id, [(16, 'סימן א סעיף א')]);
    final results = await finder.findRefs('$title סימן א סק א');
    expect(results.where((r) => r.isAltToc).map((r) => r.segment), [16]);
    expect(results.any((r) => r.isPartialTocMatch), isTrue);
  });

  for (final title in ['ספר ניסיוני', 'ספר ניסיוני א']) {
    test('מספר בהורה או בשם הספר אינו ממלא שני טוקני מספר: $title', () async {
      final id = await book(title);
      await toc(id, 5, 'סימן א סק');
      await headings(id, [(16, 'סימן א סעיף א')]);
      final results = await finder.findRefs('$title סימן א סק א');
      expect(results.where((r) => r.isAltToc).map((r) => r.segment), [16]);
    });
  }

  for (final (query, heading) in [
    ('הלכה א', 'הלכה א'),
    ('ס״ק ב', 'סעיף קטן ב'),
  ]) {
    test('TOC מילולי אינו מוחק AltToc מילולי: $query', () async {
      const title = 'ספר ניסיוני';
      final id = await book(title);
      final parent = await toc(id, 2, 'פרק א');
      await toc(id, 5, heading, parentId: parent);
      await headings(id, [(16, 'נושאים $heading')]);
      final results = await finder.findRefs('$title $query');
      expect(results.map((r) => (r.isAltToc, r.segment)).toSet(), {
        (false, 5),
        (true, 16),
      });
    });
  }

  for (final word in ['פרק', 'משנה', 'סימן']) {
    test('AltToc: $word אינו חלופה לאות', () async {
      const title = 'ספר ניסיוני';
      final id = await book(title);
      await headings(id, [(4, 'אות א')]);
      final results = await finder.findRefs('$title $word א');
      expect(results.where((r) => r.isAltToc), isEmpty);
    });
  }

  test('מפתח בלי מילות מבנה משמר את השיפור המקורי ב־issue 4893', () async {
    const title = 'איסור והיתר הארוך';
    final id = await book(title);
    for (final (index, ref) in [(100, 'לה, יא'), (101, 'לה, יב')]) {
      await data.insertLine(
        Line(bookId: id, lineIndex: index, content: ref, heRef: '$title, $ref'),
      );
    }
    await data.rebuildLineRefIndex(id);
    final results = await finder.findRefs('$title כלל לה דין יא');
    expect(results.where((r) => r.isSourceLine).map((r) => r.segment), [100]);
  });
}
