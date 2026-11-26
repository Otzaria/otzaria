import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/find_ref/repository/find_ref_repository.dart';
import 'package:otzaria/find_ref/repository/reference_books_cache.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/user_content_import/services/user_link_ref_resolver.dart';

import 'support/seeded_reference_library.dart';

Future<SeforimRepository> _repoWithTitleHeading(
  String h1, {
  String title = 'חידושי הרן על נדה',
  int rootLine = 0,
  int? parentId,
  bool otherRoot = false,
  int? otherRootParent = 4,
  bool personal = false,
}) async {
  final dir = await Directory.systemTemp.createTemp('otzaria_title_heading');
  final database = MyDatabase.withPath('${dir.path}/seforim.db');
  addTearDown(() async {
    database.close();
    await dir.delete(recursive: true);
  });
  final db = await database.database;
  db.execute("INSERT INTO category(id,title,level) VALUES(1,'ספרייה',0)");
  db.execute("INSERT INTO source(id,name) VALUES(1,'אוצריא')");
  db.execute(
    "INSERT INTO book(id,categoryId,sourceId,title,orderIndex,filePath,fileType) "
    "VALUES(1,1,1,?,1,'/b.txt','txt')",
    [title],
  );
  if (personal) db.execute('UPDATE book SET isPersonal = 1 WHERE id = 1');
  final toc = [
    (id: 1, parent: parentId, level: 1, text: h1, line: rootLine),
    (id: 2, parent: 1, level: 2, text: 'פרק א - שמאי', line: 1),
    (id: 3, parent: 2, level: 3, text: 'דף יב.', line: 2),
    if (parentId == 4 || otherRoot)
      (id: 4, parent: null, level: 0, text: title, line: 3),
    if (otherRoot)
      (id: 5, parent: otherRootParent, level: 2, text: 'סימן תל', line: 4),
  ];
  for (final e in toc) {
    db.execute(
      'INSERT INTO line(id,bookId,lineIndex,content) VALUES(?,1,?,?)',
      [e.id + 100, e.line, e.text],
    );
    db.execute('INSERT INTO tocText(id,text) VALUES(?,?)', [e.id, e.text]);
    db.execute(
      'INSERT INTO tocEntry(id,bookId,parentId,textId,level,lineId) '
      'VALUES(?,1,?,?,?,?)',
      [e.id, e.parent, e.id, e.level, e.id + 100],
    );
  }
  final seforim = SeforimRepository(database);
  await seforim.ensureInitialized();
  return seforim;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('כותרת שם הספר אינה נכפלת בכתובת שאחרי שם הספר', () async {
    final seforim = await _repoWithTitleHeading('חדושי הרן על מסכת נדה');
    final toc = await seforim.getTocEntriesForReference(
      1,
      'חידושי הרן על נדה',
      queryTokens: const ['יב'],
    );
    expect(toc.map((e) => e['reference']), [
      'חידושי הרן על נדה פרק א - שמאי דף יב.',
    ]);
  });

  for (final h1 in [
    'מבוא למסכת נדה',
    'הקדמה לחידושי הרן על נדה',
    'חידושי הרן על נדה פרק ראשון',
    'מטה יהונתן (פסח)',
    'חלק ראשון',
  ]) {
    final title = h1 == 'מטה יהונתן (פסח)'
        ? 'מטה יהונתן על שולחן ערוך אורח חיים'
        : h1 == 'חלק ראשון'
        ? 'ימי מוהרנת חלק ראשון'
        : 'חידושי הרן על נדה';
    test('כותרת תוכן נשמרת גם כשיש חפיפה בשם: $h1', () async {
      final repo = await _repoWithTitleHeading(h1, title: title);
      final expected = {
        'reference': '$title $h1 פרק א - שמאי דף יב.',
        'segment': 2,
        'level': 3,
        'dbLineId': 103,
      };
      for (var i = 0; i < 2; i++) {
        expect(
          await repo.getTocEntriesForReference(1, title, queryTokens: ['יב']),
          [expected],
        );
      }
    });
  }

  for (final (title, h1) in [
    ('אבן העוזר על בבא בתרא', 'אבן העוזר על בבא בתרא'),
    ('חידושי הרן על נדה', 'חִדּוּשֵׁי הר״ן על נדה'),
    ('חידושי הרן על נדה', 'חדושי הרן על מסכת נדה'),
    ('איתן האזרחי', 'שו"ת איתן האזרחי'),
    ('שו"ת איתן האזרחי', 'איתן האזרחי'),
    ('זכרון אהרן', 'ספר זכרון אהרן'),
    ('My Book', 'MY BOOK'),
  ]) {
    for (final personal in [false, true]) {
      test('שם ודאי מקוצר במסד רשמי ואישי: $h1/$personal', () async {
        final repo = await _repoWithTitleHeading(
          h1,
          title: title,
          personal: personal,
        );
        final all = await repo.getTocEntriesForReference(1, title);
        expect(all, [
          {'reference': title, 'segment': 0, 'level': 1, 'dbLineId': 101},
          {
            'reference': '$title פרק א - שמאי',
            'segment': 1,
            'level': 2,
            'dbLineId': 102,
          },
          {
            'reference': '$title פרק א - שמאי דף יב.',
            'segment': 2,
            'level': 3,
            'dbLineId': 103,
          },
        ]);
        expect(
          await repo.getTocEntriesForReference(1, title, queryTokens: []),
          all,
        );
      });
    }
  }

  test('קיצור תצוגה משמר מילת כותרת בחיפוש שטוח לא טבעי', () async {
    final repo = await _repoWithTitleHeading('חדושי הרן על מסכת נדה');
    const title = 'חידושי הרן על נדה';
    final expected = {
      'reference': '$title פרק א - שמאי דף יב.',
      'segment': 2,
      'level': 3,
      'dbLineId': 103,
    };
    for (final tokens in [
      ['דף', 'מסכת', 'יב'],
      ['מסכת', 'דף', 'יב'],
      ['חידושי', 'הרן', 'על', 'נדה', 'דף', 'מסכת', 'יב'],
    ]) {
      expect(
        await repo.getTocEntriesForReference(1, title, queryTokens: tokens),
        [expected],
      );
    }
    expect(
      await repo.getTocEntriesForReference(
        1,
        title,
        queryTokens: ['דף', 'מסכת'],
      ),
      isEmpty,
    );
    final partial = await repo.getTocEntriesForReference(
      1,
      title,
      queryTokens: ['מסכת', 'חסר'],
    );
    expect(partial.single, {
      'reference': title,
      'segment': 0,
      'level': 1,
      'dbLineId': 101,
      'partialMatch': true,
    });
  });

  test('קישור משתמש נפתר עם מילה מכותרת שקוצרה', () async {
    final repo = await _repoWithTitleHeading(
      'חדושי הרן על מסכת נדה',
      personal: true,
    );
    final resolvers = userLinkResolversFor(
      repo.database,
      officialRepository: repo,
    );
    for (final userBook in [false, true]) {
      expect(
        await resolvers.resolveRef(
          targetTitle: 'חידושי הרן על נדה',
          targetCategoryId: 1,
          targetIsUserBook: userBook,
          ref: 'דף מסכת יב',
        ),
        2,
      );
    }
  });

  for (final parentId in [4, 999]) {
    test('שם תחת אב רמה אפס או אב חסר אינו שורש כותרת: $parentId', () async {
      final repo = await _repoWithTitleHeading(
        'חדושי הרן על מסכת נדה',
        parentId: parentId,
      );
      final rows = await repo.getTocEntriesForReference(
        1,
        'חידושי הרן על נדה',
        queryTokens: ['יב'],
      );
      expect(rows.single['reference'], contains('חדושי הרן על מסכת נדה'));
    });
  }

  for (final parentId in [null, 4, 999]) {
    test('שורש נוסף אינו מקבל מילים מה-h1: $parentId', () async {
      final repo = await _repoWithTitleHeading(
        'חדושי הרן על מסכת נדה',
        otherRoot: true,
        otherRootParent: parentId,
      );
      const title = 'חידושי הרן על נדה';
      final rows = await repo.getTocEntriesForReference(
        1,
        title,
        queryTokens: ['חידושי', 'מסכת', 'תל'],
      );
      expect(rows, isEmpty);
      final all = await repo.getTocEntriesForReference(1, title);
      expect(all.first['reference'], '$title חדושי הרן על מסכת נדה');
    });
  }

  test('איתור מלא וכינוי שומרים כתובת ומזהי ניווט בלי כפילות', () async {
    final seforim = await _repoWithTitleHeading('חדושי הרן על מסכת נדה');
    const title = 'חידושי הרן על נדה';
    seedLibrary(const [
      (id: 1, title: title, acronyms: ['רן נדה']),
    ]);
    addTearDown(resetSeededLibrary);
    final repo = FindRefRepository(
      isReferenceBooksCacheLoaded: () => true,
      getTocEntriesForReference: (id, title, {queryTokens}) => seforim
          .getTocEntriesForReference(id, title, queryTokens: queryTokens),
      getAltTocEntriesForReference: (id, title, {queryTokens}) async => [],
      getAltStructureBookIds: () async => [],
      getAllAltTocFlatEntries: () async => [],
      getCategoryPath: (_) async => 'ספרייה',
    );
    addTearDown(repo.dispose);
    for (final query in ['$title דף מסכת יב', 'רן נדה דף מסכת יב']) {
      final rows = await repo.findRefs(query);
      expect(rows, hasLength(1));
      expect(rows.single.reference, '$title פרק א - שמאי דף יב.');
      expect(rows.single.segment, 2);
      expect(rows.single.tocLevel, 3);
      expect(rows.single.sourceLineId, 103);
      expect(rows.single.isPartialTocMatch, false);
    }
  });

  const title = 'חוות דעת חדושים';
  Future<SeforimRepository> seferWithSimanim({bool alternate = false}) async {
    final dir = await Directory.systemTemp.createTemp('otzaria_title_heading');
    final database = MyDatabase.withPath('${dir.path}/seforim.db');
    addTearDown(() async {
      database.close();
      await dir.delete(recursive: true);
    });
    final db = await database.database;
    db.execute("INSERT INTO category(id,title,level) VALUES(1,'ספרייה',0)");
    db.execute("INSERT INTO source(id,name) VALUES(1,'MoreBooks')");
    db.execute(
      "INSERT INTO book(id,categoryId,sourceId,title,orderIndex,filePath,fileType) "
      "VALUES(1,1,1,?,1,'/b.txt','txt')",
      [title],
    );
    final toc = [
      (id: 1, parent: null, level: 1, text: title),
      (id: 2, parent: 1, level: 2, text: 'סימן סט'),
      (id: 3, parent: 2, level: 3, text: 'י'),
      (id: 4, parent: 1, level: 2, text: 'סימן צד'),
      (id: 5, parent: 4, level: 3, text: 'א'),
      (id: 6, parent: 4, level: 3, text: 'י'),
      (id: 9, parent: 4, level: 3, text: 'ב'),
    ];
    final textIds = <String, int>{};
    for (final (i, e) in toc.indexed) {
      db.execute(
        'INSERT INTO line(id,bookId,lineIndex,content) VALUES(?,1,?,?)',
        [e.id + 100, i, e.text],
      );
      final textId = textIds.putIfAbsent(e.text, () {
        db.execute('INSERT INTO tocText(id,text) VALUES(?,?)', [e.id, e.text]);
        return e.id;
      });
      db.execute(
        'INSERT INTO tocEntry(id,bookId,parentId,textId,level,lineId) '
        'VALUES(?,1,?,?,?,?)',
        [e.id, e.parent, textId, e.level, e.id + 100],
      );
    }
    db.execute(
      "INSERT INTO alt_toc_structure(id,bookId,key,heTitle) "
      "VALUES(1,1,'SimanNames','הלכות וסימנים')",
    );
    db.execute("INSERT INTO tocText(id,text) VALUES(7,?)", [
      alternate ? '[סימן צד] הלכות בשר בחלב' : 'הלכות בשר בחלב',
    ]);
    db.execute(
      'INSERT INTO alt_toc_entry(id,structureId,parentId,textId,level,lineId) '
      'VALUES(1,1,NULL,7,0,104)',
    );
    if (alternate) {
      db.execute("INSERT INTO tocText(id,text) VALUES(8,'אות י')");
      db.execute(
        'INSERT INTO alt_toc_entry(id,structureId,parentId,textId,level,lineId) '
        'VALUES(2,1,1,8,1,103)',
      );
    }
    final seforim = SeforimRepository(database);
    await seforim.ensureInitialized();

    return seforim;
  }

  test('סימן וסעיף קטן תחת כותרת שם הספר, כשיש לספר מבנה חלופי', () async {
    final seforim = await seferWithSimanim();
    for (final (letter, segment) in [('א', 4), ('ב', 6), ('י', 5)]) {
      final rows = await seforim.getTocEntriesForReference(
        1,
        title,
        queryTokens: ['צד', letter],
      );
      expect(rows.map((e) => (e['reference'], e['segment'])), [
        ('$title סימן צד $letter', segment),
      ]);
      expect(rows.single['partialMatch'], isNull);
    }
    expect(
      await seforim.getTocEntriesForReference(
        1,
        title,
        queryTokens: ['דף', 'צד', 'א'],
      ),
      isEmpty,
    );
  });

  test('יעד קישור קיים בתוכן העניינים החלופי נשמר', () async {
    final seforim = await seferWithSimanim(alternate: true);
    final resolveRef = userLinkResolversFor(
      seforim.database,
      officialRepository: seforim,
    ).resolveRef;
    expect(
      await resolveRef(
        targetTitle: title,
        targetCategoryId: null,
        targetIsUserBook: false,
        ref: 'צד י',
      ),
      2,
    );
  });

  // issue #5795
  Future<SeforimRepository> seferWithChildren(
    String title,
    List<String> children,
  ) async {
    final dir = await Directory.systemTemp.createTemp('otzaria_title_heading');
    final database = MyDatabase.withPath('${dir.path}/seforim.db');
    addTearDown(() async {
      database.close();
      await dir.delete(recursive: true);
    });
    final db = await database.database;
    db.execute("INSERT INTO category(id,title,level) VALUES(1,'ספרייה',0)");
    db.execute("INSERT INTO source(id,name) VALUES(1,'אוצריא')");
    db.execute(
      "INSERT INTO book(id,categoryId,sourceId,title,orderIndex,filePath,fileType) "
      "VALUES(1,1,1,?,1,'/b.txt','txt')",
      [title],
    );
    for (final (i, text) in [title, ...children].indexed) {
      final id = i + 1;
      db.execute(
        'INSERT INTO line(id,bookId,lineIndex,content) VALUES(?,1,?,?)',
        [id + 100, i, text],
      );
      db.execute('INSERT INTO tocText(id,text) VALUES(?,?)', [id, text]);
      db.execute(
        'INSERT INTO tocEntry(id,bookId,parentId,textId,level,lineId) '
        'VALUES(?,1,?,?,?,?)',
        [id, i == 0 ? null : 1, id, i == 0 ? 1 : 2, id + 100],
      );
    }
    final seforim = SeforimRepository(database);
    await seforim.ensureInitialized();
    return seforim;
  }

  test('מילה שחוזרת על שם הספר מגיעה לכותרות שתחתיו', () async {
    const title = 'חזון איש, טהרות';
    final seforim = await seferWithChildren(title, [
      'מסכת כלים',
      'מסכת טהרות',
      'הוספות לעניני טהרות',
    ]);
    final rows = await seforim.getTocEntriesForReference(
      1,
      title,
      queryTokens: ['טהרות'],
    );
    expect(rows.map((e) => e['reference']), [
      '$title מסכת טהרות',
      '$title הוספות לעניני טהרות',
    ]);
  });

  test('כותרת שחוזרת על שם הספר אינה מחליפה אותו', () async {
    const title = 'האלף לך שלמה (אולינוב)';
    final seforim = await seferWithChildren(title, ['האלף לך שלמה']);
    final rows = await seforim.getTocEntriesForReference(
      1,
      title,
      queryTokens: ['לך'],
    );
    expect(rows.map((e) => e['reference']), [title]);
  });

  test('"פ"ב" מגיע לפרק ב רק כשאין פרק פב', () async {
    final mishna = await seferWithChildren('משנה ברכות', ['פרק א', 'פרק ב']);
    expect(
      (await mishna.getTocEntriesForReference(
        1,
        'משנה ברכות',
        queryTokens: ['פב'],
      )).map((e) => e['reference']),
      ['משנה ברכות פרק ב'],
    );

    final tehillim = await seferWithChildren('תהלים', ['פרק ב', 'פרק פב']);
    expect(
      (await tehillim.getTocEntriesForReference(
        1,
        'תהלים',
        queryTokens: ['פב'],
      )).map((e) => e['reference']),
      ['תהלים פרק פב'],
    );
  });

  test('כינוי שבלע מילת כותרת אינו בולע אותה שוב מהזנב', () async {
    ReferenceBookHit hit(String term, int rank) => ReferenceBookHit(
      bookId: 1,
      title: 'חזון איש, טהרות',
      normalizedTitle: 'חזון איש טהרות',
      filePath: '',
      fileType: 'txt',
      matchRank: rank,
      matchedTerm: term,
      orderIndex: 1,
    );
    final tocQueries = <List<String>>[];
    final repo = FindRefRepository(
      isReferenceBooksCacheLoaded: () => true,
      warmUpReferenceBooksCache: () async {},
      searchReferenceBooks: (query, {int limit = 50}) => [
        if (query == 'חזוא טהרות טהרות')
          hit(query, ReferenceBooksCache.fuzzyMatchRank),
        if (query == 'חזוא טהרות') hit(query, 3),
      ],
      getTocEntriesForReference: (id, title, {queryTokens}) async {
        tocQueries.add(queryTokens!);
        return [];
      },
      getAltTocEntriesForReference: (id, title, {queryTokens}) async => [],
      getAltStructureBookIds: () async => [],
      getAllAltTocFlatEntries: () async => [],
    );
    addTearDown(repo.dispose);

    await repo.findRefs('חזוא טהרות טהרות');

    expect(tocQueries, isNotEmpty);
    expect(tocQueries, everyElement(['טהרות']));
  });

  test('כותרת בהמשך הספר אינה מקוצרת', () async {
    final repo = await _repoWithTitleHeading('חידושי הרן על נדה', rootLine: 10);
    final rows = await repo.getTocEntriesForReference(
      1,
      'חידושי הרן על נדה',
      queryTokens: ['יב'],
    );
    expect(
      rows.single['reference'],
      'חידושי הרן על נדה חידושי הרן על נדה פרק א - שמאי דף יב.',
    );
  });
}
