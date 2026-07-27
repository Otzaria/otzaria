// לוגיקת צ׳יפי הסינון לפי סוג מפרש, המשותפת לכל מסכי בחירת המפרשים.
// עד לחילוץ הזה הלוגיקה ישבה בתוך CommentaryListBase והצ׳יפים סיננו במסך אחד
// בלבד, בעוד המסכים האחרים הציגו אותם בלי לחבר אותם לסינון.
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/link_types.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/text_book/utils/commentary_type_filter.dart';

void main() {
  group('chipKeys', () {
    test('סוג שאין לו קישורים אינו מקבל צ׳יפ', () {
      expect(
        CommentaryTypeFilter.chipKeys([
          _link(path2: 'אונקלוס.txt', type: LinkTypes.targum),
        ]),
        [LinkTypes.targum],
      );
    });

    test('רשימה ריקה מחזירה ללא צ׳יפים', () {
      expect(CommentaryTypeFilter.chipKeys(const []), isEmpty);
    });

    test('הסדר קבוע לפי commentaryFilterTypes ולא לפי סדר הקישורים', () {
      final keys = CommentaryTypeFilter.chipKeys([
        _link(path2: 'א.txt', type: LinkTypes.elucidation),
        _link(path2: 'ב.txt', type: LinkTypes.diburHamatchil),
        _link(path2: 'ג.txt', type: LinkTypes.parshanut),
        _link(path2: 'ד.txt', type: LinkTypes.midrash),
        _link(path2: 'ה.txt', type: LinkTypes.targum),
      ]);

      expect(keys, LinkTypes.commentaryFilterTypes);
    });

    test('COMMENTARY ו-SUPER_COMMENTARY אינם מקבלים צ׳יפ', () {
      final keys = CommentaryTypeFilter.chipKeys([
        _link(path2: 'רש"י.txt', type: LinkTypes.commentary),
        _link(path2: 'שפתי חכמים.txt', type: LinkTypes.superCommentary),
        _link(path2: 'אונקלוס.txt', type: LinkTypes.targum),
      ]);

      expect(keys, [LinkTypes.targum]);
    });

    test('סוג שאינו תלוי-טקסט (עין משפט) אינו מקבל צ׳יפ', () {
      expect(
        CommentaryTypeFilter.chipKeys([
          _link(path2: 'עין משפט.txt', type: LinkTypes.einMishpat),
        ]),
        isEmpty,
      );
    });

    test('EXPLICATION ו-ELUCIDATION ממוזגים לצ׳יפ אחד', () {
      final keys = CommentaryTypeFilter.chipKeys([
        _link(path2: 'א.txt', type: LinkTypes.explication),
        _link(path2: 'ב.txt', type: LinkTypes.elucidation),
      ]);

      expect(keys, [LinkTypes.elucidation]);
    });

    test('רישיות ומפרידים שונים אינם מייצרים צ׳יפ כפול', () {
      final keys = CommentaryTypeFilter.chipKeys([
        _link(path2: 'א.txt', type: 'targum'),
        _link(path2: 'ב.txt', type: 'TARGUM'),
        _link(path2: 'ג.txt', type: ' Targum '),
      ]);

      expect(keys, [LinkTypes.targum]);
    });

    test('קישורים כפולים מאותו סוג מייצרים צ׳יפ אחד', () {
      final keys = CommentaryTypeFilter.chipKeys([
        _link(path2: 'א.txt', type: LinkTypes.midrash),
        _link(path2: 'ב.txt', type: LinkTypes.midrash),
      ]);

      expect(keys, [LinkTypes.midrash]);
    });
  });

  group('chipKeysForCommentators', () {
    test('סוג שכל מפרשיו אינם נבחרים אינו מקבל צ׳יפ', () {
      final keys = CommentaryTypeFilter.chipKeysForCommentators(
        links: [
          _link(path2: 'אונקלוס.txt', type: LinkTypes.targum),
          _link(path2: 'מדרש רבה.txt', type: LinkTypes.midrash),
        ],
        selectedCommentators: const ['אונקלוס'],
      );

      expect(keys, [LinkTypes.targum]);
    });

    test('סוג שחלק ממפרשיו נבחרים כן מקבל צ׳יפ', () {
      final keys = CommentaryTypeFilter.chipKeysForCommentators(
        links: [
          _link(path2: 'מדרש רבה.txt', type: LinkTypes.midrash),
          _link(path2: 'מדרש תנחומא.txt', type: LinkTypes.midrash),
        ],
        selectedCommentators: const ['מדרש תנחומא'],
      );

      expect(keys, [LinkTypes.midrash]);
    });

    test('רשימת מפרשים ריקה = אין צ׳יפים', () {
      final keys = CommentaryTypeFilter.chipKeysForCommentators(
        links: [_link(path2: 'אונקלוס.txt', type: LinkTypes.targum)],
        selectedCommentators: const [],
      );

      expect(keys, isEmpty);
    });
  });

  group('commentatorsByType', () {
    test('כל סוג ממופה לשמות המפרשים שלו', () {
      final byType = CommentaryTypeFilter.commentatorsByType([
        _link(path2: 'אונקלוס.txt', type: LinkTypes.targum),
        _link(path2: 'יונתן.txt', type: LinkTypes.targum),
        _link(path2: 'מדרש רבה.txt', type: LinkTypes.midrash),
      ]);

      expect(byType, {
        LinkTypes.targum: {'אונקלוס', 'יונתן'},
        LinkTypes.midrash: {'מדרש רבה'},
      });
    });

    test('סוגים בלי צ׳יפ (COMMENTARY) אינם נכללים', () {
      final byType = CommentaryTypeFilter.commentatorsByType([
        _link(path2: 'רש"י.txt', type: LinkTypes.commentary),
        _link(path2: 'אונקלוס.txt', type: LinkTypes.targum),
      ]);

      expect(byType.keys, [LinkTypes.targum]);
    });

    test('EXPLICATION נכנס תחת המפתח הקנוני ELUCIDATION', () {
      final byType = CommentaryTypeFilter.commentatorsByType([
        _link(path2: 'ביאור א.txt', type: LinkTypes.explication),
        _link(path2: 'ביאור ב.txt', type: LinkTypes.elucidation),
      ]);

      expect(byType, {
        LinkTypes.elucidation: {'ביאור א', 'ביאור ב'},
      });
    });

    test('אותו מפרש בשני קישורים מופיע פעם אחת', () {
      final byType = CommentaryTypeFilter.commentatorsByType([
        _link(path2: 'אונקלוס.txt', type: LinkTypes.targum),
        _link(path2: 'אונקלוס.txt', type: LinkTypes.targum, index1: 2),
      ]);

      expect(byType[LinkTypes.targum], {'אונקלוס'});
    });

    test('רשימה ריקה מחזירה מפה ריקה', () {
      expect(CommentaryTypeFilter.commentatorsByType(const []), isEmpty);
    });
  });

  group('effectiveTypes — ריק = הצג הכל', () {
    test('בחירה ריקה נשארת ריקה', () {
      expect(
        CommentaryTypeFilter.effectiveTypes(
          selectedTypes: const {},
          availableKeys: const [LinkTypes.targum],
        ),
        isEmpty,
      );
    });

    test('בחירה שאין לה צ׳יפ קיים נחשבת ריקה ואינה מסתירה הכל', () {
      expect(
        CommentaryTypeFilter.effectiveTypes(
          selectedTypes: const {LinkTypes.midrash},
          availableKeys: const [LinkTypes.targum],
        ),
        isEmpty,
      );
    });

    test('נשמרים רק המפתחות שקיימים בצ׳יפים', () {
      expect(
        CommentaryTypeFilter.effectiveTypes(
          selectedTypes: const {LinkTypes.midrash, LinkTypes.targum},
          availableKeys: const [LinkTypes.targum],
        ),
        {LinkTypes.targum},
      );
    });

    test('רשימת צ׳יפים ריקה מאפסת כל בחירה', () {
      expect(
        CommentaryTypeFilter.effectiveTypes(
          selectedTypes: const {LinkTypes.targum},
          availableKeys: const [],
        ),
        isEmpty,
      );
    });
  });

  group('visibleChipKeys — סוג יחיד אינו מסנן כלום', () {
    test('שני סוגים ומעלה מוצגים תמיד', () {
      expect(
        CommentaryTypeFilter.visibleChipKeys(
          chipKeys: const [LinkTypes.targum, LinkTypes.midrash],
          effectiveTypes: const {},
        ),
        [LinkTypes.targum, LinkTypes.midrash],
      );
    });

    test('סוג יחיד בלי בחירה מוסתר', () {
      expect(
        CommentaryTypeFilter.visibleChipKeys(
          chipKeys: const [LinkTypes.targum],
          effectiveTypes: const {},
        ),
        isEmpty,
      );
    });

    test('סוג יחיד שנבחר נשאר מוצג, אחרת אין דרך לבטל את הסינון', () {
      expect(
        CommentaryTypeFilter.visibleChipKeys(
          chipKeys: const [LinkTypes.targum],
          effectiveTypes: const {LinkTypes.targum},
        ),
        [LinkTypes.targum],
      );
    });

    test('בלי צ׳יפים כלל — ריק', () {
      expect(
        CommentaryTypeFilter.visibleChipKeys(
          chipKeys: const [],
          effectiveTypes: const {},
        ),
        isEmpty,
      );
    });
  });

  group('CommentaryTypeSelection', () {
    test('מתחיל ריק', () {
      final selection = CommentaryTypeSelection();
      addTearDown(selection.dispose);

      expect(selection.value, isEmpty);
    });

    test('מודיע למאזינים בשינוי', () {
      final selection = CommentaryTypeSelection();
      addTearDown(selection.dispose);
      var notified = 0;
      selection.addListener(() => notified++);

      selection.value = const {LinkTypes.targum};

      expect(notified, 1);
      expect(selection.value, {LinkTypes.targum});
    });

    test('הצבת אותו ערך אינה מודיעה שוב', () {
      final selection = CommentaryTypeSelection();
      addTearDown(selection.dispose);
      selection.value = const {LinkTypes.targum};
      var notified = 0;
      selection.addListener(() => notified++);

      selection.value = const {LinkTypes.targum};

      expect(notified, 0);
    });
  });
}

Link _link({required String path2, required String type, int index1 = 1}) =>
    Link(
      heRef: 'בראשית א',
      index1: index1,
      path2: path2,
      index2: 1,
      connectionType: type,
      targetCategoryId: 1,
      targetFileType: 'txt',
    );
