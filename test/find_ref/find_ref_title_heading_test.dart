import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/find_ref/repository/find_ref_repository.dart';
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
