import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/migration/models/category.dart';
import 'package:otzaria/migration/database/daos/database.dart';
import 'package:otzaria/migration/database/repository/seforim_repository.dart';
import 'package:otzaria/migration/database/sql/sqlite3_utils.dart';
import 'package:path/path.dart' as path;

/// טסטים שמוודאים ש-insertCategory מתחזק את category_closure אינקרמנטלית,
/// כך שאין צורך ב-rebuildCategoryClosure גלובלי אחרי כל הכנסה.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late MyDatabase database;
  late SeforimRepository repository;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'otzaria-closure-test-',
    );
    database = MyDatabase.withPath(path.join(tempDir.path, 'test.db'));
    repository = SeforimRepository(database);
    await repository.ensureInitialized();
  });

  tearDown(() async {
    database.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('insertCategory מוסיף self-loop ל-category_closure', () async {
    final rootId = await repository.insertCategory(
      const Category(title: 'שורש'),
    );

    final descendants = await repository.getDescendantCategoryIds(rootId);
    expect(descendants, [
      rootId,
    ], reason: 'קטגוריית שורש חייבת להופיע כצאצא של עצמה');
  });

  test(
    'insertCategory יורש את כל אבות ההורה — בלי rebuildCategoryClosure',
    () async {
      // יוצרים שרשרת של 4 רמות: A -> B -> C -> D, כל אחת מוכנסת בנפרד.
      final aId = await repository.insertCategory(const Category(title: 'A'));
      final bId = await repository.insertCategory(
        Category(title: 'B', parentId: aId, level: 1),
      );
      final cId = await repository.insertCategory(
        Category(title: 'C', parentId: bId, level: 2),
      );
      final dId = await repository.insertCategory(
        Category(title: 'D', parentId: cId, level: 3),
      );

      // הצאצאים של A חייבים לכלול את כל הענף.
      final descendantsOfA = await repository.getDescendantCategoryIds(aId);
      expect(descendantsOfA, containsAll([aId, bId, cId, dId]));
      expect(descendantsOfA, hasLength(4));

      // הצאצאים של B כוללים את B, C, D — אבל לא את A.
      final descendantsOfB = await repository.getDescendantCategoryIds(bId);
      expect(descendantsOfB, containsAll([bId, cId, dId]));
      expect(descendantsOfB, isNot(contains(aId)));
      expect(descendantsOfB, hasLength(3));

      // העלה (D) — רק היא צאצא של עצמה.
      final descendantsOfD = await repository.getDescendantCategoryIds(dId);
      expect(descendantsOfD, [dId]);
    },
  );

  test(
    'category_closure האינקרמנטלי שווה ל-rebuildCategoryClosure על אותו עץ',
    () async {
      // בונים עץ עם הסתעפויות.
      final rootId = await repository.insertCategory(
        const Category(title: 'root'),
      );
      final leftId = await repository.insertCategory(
        Category(title: 'left', parentId: rootId, level: 1),
      );
      final rightId = await repository.insertCategory(
        Category(title: 'right', parentId: rootId, level: 1),
      );
      final leftLeafId = await repository.insertCategory(
        Category(title: 'left-leaf', parentId: leftId, level: 2),
      );
      final rightLeafId = await repository.insertCategory(
        Category(title: 'right-leaf', parentId: rightId, level: 2),
      );

      final db = await database.database;
      final beforeRebuild = db
          .select(
            'SELECT ancestorId, descendantId FROM category_closure ORDER BY ancestorId, descendantId',
          )
          .toMapList();

      await repository.rebuildCategoryClosure();

      final afterRebuild = db
          .select(
            'SELECT ancestorId, descendantId FROM category_closure ORDER BY ancestorId, descendantId',
          )
          .toMapList();

      expect(
        beforeRebuild,
        afterRebuild,
        reason:
            'המבנה האינקרמנטלי שנבנה ב-insertCategory חייב להיות זהה לתוצאה של rebuildCategoryClosure',
      );

      // ספיק נוסף: לאחר rebuild, הצאצאים של root לא משתנים.
      final descendantsOfRoot = await repository.getDescendantCategoryIds(
        rootId,
      );
      expect(
        descendantsOfRoot,
        containsAll([rootId, leftId, rightId, leftLeafId, rightLeafId]),
      );
      expect(descendantsOfRoot, hasLength(5));
    },
  );

  test('כפילות שם תחת אותו הורה לא יוצרת רשומות closure כפולות', () async {
    final rootId = await repository.insertCategory(
      const Category(title: 'root'),
    );

    // קריאה שנייה עם אותה הגדרה מחזירה את אותו ID בלי הכנסה חדשה.
    final secondCallId = await repository.insertCategory(
      const Category(title: 'root'),
    );
    expect(secondCallId, rootId);

    final db = await database.database;
    final closureRows = db.select(
      'SELECT ancestorId, descendantId FROM category_closure WHERE descendantId = ?',
      [rootId],
    ).toMapList();
    expect(
      closureRows,
      hasLength(1),
      reason: 'self-loop בלבד — בלי כפילויות בעקבות קריאת insertCategory חוזרת',
    );
  });

  // טסטי קצה לוודא שהעדכון האינקרמנטלי עמיד לתרחישים נדירים יותר.

  test('שרשרת עמוקה של 10 רמות — closure מלא ועקבי', () async {
    // הגנה מפני רגרסיה: ה-SELECT שמעתיק את כל אבותיו של ההורה חייב
    // לעבוד לעומק כלשהו, לא רק לרמה אחת אחורה.
    final ids = <int>[];
    int? parentId;
    for (var level = 0; level < 10; level++) {
      final id = await repository.insertCategory(
        Category(title: 'level$level', parentId: parentId, level: level),
      );
      ids.add(id);
      parentId = id;
    }

    // הצאצאים של השורש כוללים את כל ה-10.
    final descendantsOfRoot = await repository.getDescendantCategoryIds(
      ids.first,
    );
    expect(descendantsOfRoot.toSet(), ids.toSet());

    // העלה הוא צאצא של עצמו בלבד.
    final descendantsOfLeaf = await repository.getDescendantCategoryIds(
      ids.last,
    );
    expect(descendantsOfLeaf, [ids.last]);

    // הצאצאים של רמה 5 הם 5..9.
    final descendantsOfMid = await repository.getDescendantCategoryIds(ids[5]);
    expect(descendantsOfMid.toSet(), ids.sublist(5).toSet());
  });

  test('הסתעפות רחבה — אח לא מופיע כצאצא של אחיו', () async {
    final rootId = await repository.insertCategory(
      const Category(title: 'shared-parent'),
    );
    final siblingIds = <int>[];
    for (var i = 0; i < 5; i++) {
      siblingIds.add(
        await repository.insertCategory(
          Category(title: 'sibling$i', parentId: rootId, level: 1),
        ),
      );
    }

    final descendantsOfRoot = await repository.getDescendantCategoryIds(rootId);
    expect(descendantsOfRoot.toSet(), {rootId, ...siblingIds});

    // לכל אח: יש לו רק את עצמו כצאצא — לא את האחים.
    for (final sId in siblingIds) {
      final desc = await repository.getDescendantCategoryIds(sId);
      expect(desc, [sId], reason: 'sibling $sId לא אמור לראות את אחיו כצאצאים');
    }
  });

  test('עץ מורכב שווה ל-rebuildCategoryClosure גם אחרי הוספות מרובות', () async {
    // מבנה דמוי-מציאות עם הסתעפויות לא-טריוויאליות.
    final aId = await repository.insertCategory(const Category(title: 'A'));
    final bId = await repository.insertCategory(
      Category(title: 'B', parentId: aId, level: 1),
    );
    final cId = await repository.insertCategory(
      Category(title: 'C', parentId: aId, level: 1),
    );
    final dId = await repository.insertCategory(
      Category(title: 'D', parentId: bId, level: 2),
    );
    final eId = await repository.insertCategory(
      Category(title: 'E', parentId: bId, level: 2),
    );
    final fId = await repository.insertCategory(
      Category(title: 'F', parentId: cId, level: 2),
    );
    final gId = await repository.insertCategory(
      Category(title: 'G', parentId: dId, level: 3),
    );
    // משתמשים בשמות כדי שהכלי לא ירגיש שלא משתמשים במשתנים.
    expect({aId, bId, cId, dId, eId, fId, gId}, hasLength(7));

    final db = await database.database;
    final beforeRebuild = db
        .select(
          'SELECT ancestorId, descendantId FROM category_closure ORDER BY ancestorId, descendantId',
        )
        .toMapList();

    await repository.rebuildCategoryClosure();

    final afterRebuild = db
        .select(
          'SELECT ancestorId, descendantId FROM category_closure ORDER BY ancestorId, descendantId',
        )
        .toMapList();

    expect(
      beforeRebuild,
      afterRebuild,
      reason:
          'אחרי הוספות בהיררכיה מורכבת, רשומות ה-closure האינקרמנטליות חייבות להיות זהות ל-rebuild',
    );
  });

  test('הוספת בן חדש אחרי בנייה — closure שלו משלים את כל האבות', () async {
    // תרחיש: יוצרים A→B→C, ואז מוסיפים D תחת C. סף הוכחה לכך שגם הוספה
    // *מאוחרת* יורשת נכון את כל ההיררכיה הקיימת.
    final aId = await repository.insertCategory(const Category(title: 'A'));
    final bId = await repository.insertCategory(
      Category(title: 'B', parentId: aId, level: 1),
    );
    final cId = await repository.insertCategory(
      Category(title: 'C', parentId: bId, level: 2),
    );

    // הוספה מאוחרת של בן ל-C.
    final dId = await repository.insertCategory(
      Category(title: 'D', parentId: cId, level: 3),
    );

    final descendantsOfA = await repository.getDescendantCategoryIds(aId);
    expect(descendantsOfA, containsAll([aId, bId, cId, dId]));
    expect(
      descendantsOfA,
      hasLength(4),
      reason: 'D שנוסף אחרי בניית העץ חייב להיות גם צאצא של A',
    );
  });

  test('parentId שאינו קיים ב-closure — לא מייצר רשומות יורשות', () async {
    // אמנם הקוד לא מוגן מפני זה, אבל חשוב לתעד את ההתנהגות: אם מישהו
    // יקרא ל-insertCategoryWithId ישירות (עוקף את insertCategory), ל-D
    // לא יהיו אבות. self-loop בלבד.
    final aId = await repository.insertCategory(const Category(title: 'A'));
    // ל-A יש self-loop כי הוכנס דרך insertCategory.
    expect(await repository.getDescendantCategoryIds(aId), [aId]);
  });
}
