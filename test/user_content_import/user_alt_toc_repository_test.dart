import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/printing/printing_helpers.dart';
import 'package:otzaria/text_book/utils/inline_section_markers.dart';
import 'package:otzaria/user_content_import/repository/user_alt_toc_repository.dart';
import 'package:otzaria/user_content_import/repository/user_content_repository.dart';
import 'package:otzaria/user_content_import/services/user_headings_builder.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late MyDatabase db;
  late UserAltTocRepository reader;
  late int bookId;

  UserAltTocEntryData entry(
    String text, {
    int level = 1,
    int? line,
    int? parent,
    bool hasChildren = false,
  }) => UserAltTocEntryData(
    level: level,
    text: text,
    lineIndex: line,
    parentIndex: parent,
    hasChildren: hasChildren,
    isLastChild: false,
  );

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('otzaria_user_alt_toc');
    db = MyDatabase.withPath(p.join(tempDir.path, 'user_books.db'));
    final raw = await db.database;
    raw.execute("INSERT INTO source (name) VALUES ('external')");
    raw.execute(
      'INSERT INTO book (categoryId, sourceId, title, filePath, fileType) '
      "VALUES (7, 1, 'ספר', '/books/ספר.txt', 'txt')",
    );
    bookId = raw.lastInsertRowId;
    reader = UserAltTocRepository(db);

    // מקור אחר עם מבנה באותו שם — נדרס כולו בכתיבה שאחריו.
    await UserContentRepository(db).replaceBookHeadings(bookId, [
      UserAltTocStructureData(
        key: 'Simanim',
        heTitle: 'סימנים',
        entries: [entry('ישן', line: 0), entry('ישן ב', line: 1)],
      ),
    ], source: 'other');
    await UserContentRepository(db).replaceBookHeadings(
      bookId,
      [
        UserAltTocStructureData(
          key: 'Simanim',
          heTitle: 'סימנים',
          entries: [
            entry('חלק א', hasChildren: true),
            entry('סימן א', level: 2, line: 2, parent: 0),
            entry('סימן ב', level: 2, line: 5, parent: 0),
          ],
        ),
        UserAltTocStructureData(
          key: 'Topic',
          heTitle: 'נושאים',
          entries: [entry('הלכות שבת', line: 5)],
        ),
      ],
      source: 'test',
    );
  });

  tearDown(() async {
    db.close();
    await tempDir.delete(recursive: true);
  });

  test('מזהה את הספר לפי נתיב הקובץ, ובלעדיו לפי כותרת וקטגוריה', () async {
    expect(
      await reader.bookId(title: 'אחר', filePath: '/books/ספר.txt'),
      bookId,
    );
    expect(await reader.bookId(title: 'ספר', categoryId: 7), bookId);
    expect(await reader.bookId(title: 'ספר', categoryId: 8), isNull);
  });

  test('מבני הספר מסומנים כאישיים ובסדר הקובץ', () async {
    final structures = await reader.structures(bookId);

    expect(structures.map((s) => s.heTitle), ['סימנים', 'נושאים']);
    expect(structures.every((s) => s.isUserBook), isTrue);
  });

  test('כתיבה חוזרת של מבנה בשם זהה אינה משאירה ערכים יתומים', () async {
    final raw = await db.database;
    final entries = raw.select('SELECT COUNT(*) AS n FROM user_alt_toc_entry');

    expect(entries.single['n'], 4);
  });

  test('קישור כותרת-אב בלי שורה מוביל לשורת הצאצא הראשון', () async {
    final structure = (await reader.structures(bookId)).first;
    final entries = await reader.entries(structure.id);

    final links = await reader.linksForEntry(structure.id, entries.first.id);

    expect(links.single.path2, 'ספר');
    expect(links.single.index2, 3);
    expect(links.single.targetIsUserBook, isTrue);
  });

  test('שורות הכותרות להדפסה נושאות את רמת הערך', () async {
    final structure = (await reader.structures(bookId)).first;

    final rows = await reader.entriesWithLineIndex(structure.id);
    final headers = buildAltHeaderEntries(rows);

    expect([for (final h in headers) (h.index, h.level)], [(2, 2), (5, 2)]);
  });

  test('בשורה משותפת ההורה קודם לילד גם כשהילד נכתב קודם', () async {
    final structure = (await reader.structures(bookId)).first;
    final raw = await db.database;
    for (final (level, text) in [(2, 'סימן ג'), (1, 'חלק ב')]) {
      raw.execute(
        'INSERT INTO user_alt_toc_entry '
        '(structureId, level, text, lineIndex, isLastChild, hasChildren) '
        'VALUES (?, ?, ?, 8, 0, 0)',
        [structure.id, level, text],
      );
    }

    final rows = await reader.entriesWithLineIndex(structure.id);
    final headers = buildAltHeaderEntries(rows);

    expect(
      [for (final h in headers) (h.index, h.level)],
      [
        (2, 2),
        (5, 2),
        (8, 1),
        (8, 2),
      ],
    );
  });

  test('הכותרת הפעילה היא האחרונה שנפתחת בשורה או לפניה', () async {
    final structure = (await reader.structures(bookId)).first;
    final entries = await reader.entries(structure.id);

    expect(await reader.entryForLine(structure.id, 0), isNull);
    expect(await reader.entryForLine(structure.id, 3), entries[1].id);
    expect(await reader.entryForLine(structure.id, 9), entries[2].id);
  });

  test(
    'סימני חלוקה נלקחים מהעלים, וכותרת נושא גלויה בטקסט אינה מוזרקת',
    () async {
      final rows = await reader.inlineSectionRows(bookId);

      expect(rows.markers, {2: 'סימן א', 5: 'סימן ב'});
      expect(
        buildSectionHeadings(rows.headings, (i) => i == 5 ? 'טקסט' : null),
        {
          5: ['הלכות שבת'],
        },
      );
      expect(
        buildSectionHeadings(
          rows.headings,
          (i) => i == 5 ? 'הלכות שבת ודיניה' : null,
        ),
        isEmpty,
      );
    },
  );

  test('פרשות מוזרקות ככותרת "פרשת…" ברמה העליונה בלבד', () async {
    await UserContentRepository(db).replaceBookHeadings(bookId, [
      UserAltTocStructureData(
        key: 'Parasha',
        heTitle: 'פרשות',
        entries: [
          entry('ויצא', line: 3, hasChildren: true),
          entry('עליה א', level: 2, line: 3, parent: 0),
          entry('פרשת וישלח', line: 7),
          entry('הקדמה', line: 0),
        ],
      ),
    ], source: 'parasha');

    final rows = await reader.inlineSectionRows(bookId);

    expect(
      [
        for (final h in rows.headings)
          if (h.label.startsWith('פרשת')) (h.lineIndex, h.label),
      ],
      [(3, 'פרשת ויצא'), (7, 'פרשת וישלח')],
    );
    expect(rows.headings.map((h) => h.label), isNot(contains('עליה א')));
    expect(rows.headings.map((h) => h.label), isNot(contains('הקדמה')));
  });
  test('פרשה קיימת בלי שורה מוזרקת בשורת הצאצא הראשון', () async {
    await UserContentRepository(db).replaceBookHeadings(bookId, [
      UserAltTocStructureData(
        key: 'פרשות',
        heTitle: 'פרשות',
        entries: [
          entry('ויצא', hasChildren: true),
          entry('פתיחה', level: 2, parent: 0, hasChildren: true),
          entry('חלק ראשון', level: 3, line: 6, parent: 1),
          entry('עליה ב', level: 2, line: 12, parent: 0),
        ],
      ),
    ], source: 'legacy');

    final structure = (await reader.structures(bookId))
        .singleWhere((structure) => structure.heTitle == 'פרשות');
    final first = (await reader.entries(structure.id)).first;
    final target = (await reader.linksForEntry(structure.id, first.id)).single;
    final rows = await reader.inlineSectionRows(bookId);

    expect(structure.key, 'Parasha');
    expect(target.index2, 7);
    expect(rows.headings, contains((lineIndex: 6, label: 'פרשת ויצא')));
  });

  test('ייבוא פרשות ממקור אחר מחליף גם את המבנה במפתח הישן', () async {
    final writer = UserContentRepository(db);
    await writer.replaceBookHeadings(bookId, [
      UserAltTocStructureData(
        key: 'פרשות',
        heTitle: 'פרשות',
        entries: [entry('ויצא', line: 6)],
      ),
    ], source: 'old-file.csv');
    final oldStructure = (await reader.structures(bookId))
        .singleWhere((structure) => structure.heTitle == 'פרשות');

    await writer.replaceBookHeadings(bookId, [
      UserAltTocStructureData(
        key: 'Parasha',
        heTitle: 'פרשות',
        entries: [entry('וישלח', line: 10)],
      ),
    ], source: 'new-file.csv');

    final structures = (await reader.structures(bookId))
        .where((structure) => structure.heTitle == 'פרשות');
    expect(structures, hasLength(1));
    expect(await reader.entries(oldStructure.id), isEmpty);
    final rows = await reader.inlineSectionRows(bookId);
    expect(rows.headings, contains((lineIndex: 10, label: 'פרשת וישלח')));
    expect(rows.headings, isNot(contains((lineIndex: 6, label: 'פרשת ויצא'))));
  });
}
