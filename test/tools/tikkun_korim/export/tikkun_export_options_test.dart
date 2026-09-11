import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tools/tikkun_korim/export/tikkun_pdf_exporter.dart';

import '../support/tikkun_fakes.dart';

void main() {
  group('selectTikkunExportColumns', () {
    final columns = [
      [
        textLine(['שלום']),
      ],
      [
        textLine(['ברכה']),
      ],
      [
        textLine(['הצלחה']),
      ],
    ];

    test('הטור הנוכחי — טור אחד בלבד', () {
      final selected = selectTikkunExportColumns(
        columns,
        const TikkunExportOptions(),
        1,
      );

      expect(selected, hasLength(1));
      expect(selected.first, same(columns[1]));
    });

    test('טור נוכחי מחוץ לטווח נחתך לגבול', () {
      final selected = selectTikkunExportColumns(
        columns,
        const TikkunExportOptions(),
        9,
      );

      expect(selected.first, same(columns[2]));
    });

    test('הכל — כל הטורים', () {
      final selected = selectTikkunExportColumns(
        columns,
        const TikkunExportOptions(scope: TikkunExportScope.all),
        0,
      );

      expect(selected, hasLength(3));
    });

    test('טווח — כולל את שני הקצוות ונחתך לגבול', () {
      final selected = selectTikkunExportColumns(
        columns,
        const TikkunExportOptions(
          scope: TikkunExportScope.range,
          fromColumn: 1,
          toColumn: 7,
        ),
        0,
      );

      expect(selected, hasLength(2));
      expect(selected.first, same(columns[1]));
      expect(selected.last, same(columns[2]));
    });

    test('רשימה ריקה מחזירה ריק', () {
      expect(
        selectTikkunExportColumns(const [], const TikkunExportOptions(), 0),
        isEmpty,
      );
    });
  });

  group('paginateTikkunLines', () {
    test('שורה אינה נחתכת בין דפים', () {
      final ranges = paginateTikkunLines([40, 40, 40, 40], 100);

      expect(ranges, [
        const TikkunLineRange(0, 1),
        const TikkunLineRange(2, 3),
      ]);
    });

    test('שורה גבוהה מדף מקבלת דף לעצמה', () {
      final ranges = paginateTikkunLines([10, 500, 10], 100);

      expect(ranges, [
        const TikkunLineRange(0, 0),
        const TikkunLineRange(1, 1),
        const TikkunLineRange(2, 2),
      ]);
    });

    test('רשימה ריקה או גובה לא חוקי — בלי דפים', () {
      expect(paginateTikkunLines(const [], 100), isEmpty);
      expect(paginateTikkunLines([10], 0), isEmpty);
    });
  });

  group('TikkunExportOptions', () {
    test('הסתרת הטורים נגזרת מהבחירה', () {
      const both = TikkunExportOptions();
      expect(both.hideStam, isFalse);
      expect(both.hideNikud, isFalse);

      final stam = both.copyWith(columns: TikkunExportColumns.stamOnly);
      expect(stam.hideNikud, isTrue);
      expect(stam.hideStam, isFalse);

      final nikud = both.copyWith(columns: TikkunExportColumns.nikudOnly);
      expect(nikud.hideStam, isTrue);
    });

    test('copyWith משמר את שאר השדות', () {
      const options = TikkunExportOptions(
        mode: TikkunExportMode.flow,
        pageSize: TikkunExportPageSize.a5,
        columns: TikkunExportColumns.stamOnly,
      );
      final updated = options.copyWith(scope: TikkunExportScope.all);

      expect(updated.mode, TikkunExportMode.flow);
      expect(updated.pageSize, TikkunExportPageSize.a5);
      expect(updated.columns, TikkunExportColumns.stamOnly);
      expect(updated.scope, TikkunExportScope.all);
    });

    test('גדלי הדף — A4 גבוה מ-A5 ולכל אחד תווית', () {
      expect(
        TikkunExportPageSize.a4.heightPt,
        greaterThan(TikkunExportPageSize.a5.heightPt),
      );
      expect(TikkunExportPageSize.letter.label, 'Letter');
    });
  });

  group('sliceTikkunBookColumns', () {
    final columns = [
      [
        textLine(['א'], parashaName: 'בראשית'),
        textLine(['ב']),
      ],
      [
        textLine(['ג']),
        textLine(['ד'], parashaName: 'שמות'),
      ],
      [
        textLine(['ה']),
      ],
    ];

    test('חומש אמצעי — מהפרשה הראשונה שלו עד הפרשה הראשונה של הבא', () {
      final sliced = sliceTikkunBookColumns(
        columns,
        firstParasha: 'בראשית',
        nextBookFirstParasha: 'שמות',
      );

      expect(sliced, hasLength(2));
      expect(sliced[0], hasLength(2));
      expect(sliced[1], hasLength(1));
    });

    test('החומש האחרון נמשך עד הסוף, גם דרך שורות בלי שם פרשה', () {
      final sliced = sliceTikkunBookColumns(columns, firstParasha: 'שמות');

      expect(sliced, hasLength(2));
      expect(sliced[0].single.words.single.stam, 'ד');
      expect(sliced[1].single.words.single.stam, 'ה');
    });

    test('פרשה שאינה נמצאת — כל הטורים', () {
      expect(
        sliceTikkunBookColumns(columns, firstParasha: 'דברים'),
        same(columns),
      );
    });
  });

  group('טווח פסוקים', () {
    final columns = [
      [
        textLine(['א'], chapter: 1, verse: 1),
        textLine(['ב'], chapter: 1, verse: 2),
        textLine(['ג']),
      ],
      [
        textLine(['ד'], chapter: 2, verse: 1),
        textLine(['ה'], chapter: 2, verse: 5),
      ],
    ];

    test('tikkunVerseDomain — הפסוק האחרון של כל פרק, לפי הסדר', () {
      final domain = tikkunVerseDomain(columns);

      expect(domain.keys.toList(), [1, 2]);
      expect(domain[1], 2);
      expect(domain[2], 5);
    });

    test('שורה בלי מספר פסוק שייכת לפסוק שלפניה', () {
      final selected = selectTikkunExportColumns(
        columns,
        const TikkunExportOptions(
          scope: TikkunExportScope.verseRange,
          fromChapter: 1,
          fromVerse: 2,
          toChapter: 1,
          toVerse: 2,
        ),
        0,
      );

      expect(selected, hasLength(1));
      expect(selected.single, hasLength(2));
    });

    test('טווח חוצה טורים שומר על חלוקת הטורים ומשמיט ריקים', () {
      final selected = selectTikkunExportColumns(
        columns,
        const TikkunExportOptions(
          scope: TikkunExportScope.verseRange,
          fromChapter: 1,
          fromVerse: 3,
          toChapter: 2,
          toVerse: 1,
        ),
        0,
      );

      expect(selected, hasLength(1));
      expect(selected.single, hasLength(1));
      expect(selected.single.single.firstChapterNum, 2);
    });
  });
}
