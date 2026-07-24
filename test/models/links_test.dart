import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/links.dart';

void main() {
  test('getLinksforIndexs שומר קישורים נפרדים משורות מקור שונות', () async {
    final links = [
      Link(
        heRef: 'רש"י פסוק א',
        index1: 22,
        path2: 'רש"י על בראשית',
        index2: 5,
        connectionType: 'COMMENTARY',
      ),
      Link(
        heRef: 'רש"י פסוק א',
        index1: 23,
        path2: 'רש"י על בראשית',
        index2: 5,
        connectionType: 'COMMENTARY',
      ),
    ];

    final result = await getLinksforIndexs(
      indexes: const [21, 22],
      links: links,
      commentatorsToShow: const ['רש"י על בראשית'],
    );

    expect(result, hasLength(2));
    expect(result.first.path2, 'רש"י על בראשית');
    expect(result.first.index2, 5);
  });

  group('getLinksforIndexs - מיון לפי ערך מספרי של פרק (טו/טז)', () {
    // הבעיה: heRef ממוין כמחרוזת. בעברית, "פרק טו" מסודר אחרי "פרק יד"
    // אלפבתית רק במקרה — האותיות ט,י לא משקפות סדר מספרי (15>14).
    // הקוד מבצע replaceAll מטעמי מיון: ' טו,' -> ' יה,' ו-' טז,' -> ' יו,',
    // כך שמיון מחרוזות נותן את הסדר הנכון: יד(14) < יה(15) < יו(16) < יז(17).
    //
    // הבאג שתוקן ב-e3ecf388d: הקוד הקודם כתב ' ,יה' (פסיק לפני האותיות)
    // במקום ' יה,'. התוצאה: הפסיק (ASCII 44) מקדים את כל האותיות העבריות
    // (Unicode 0x05D0+), ולכן פרק טו היה מוצב לפני פרק יד במיון.
    test(
      'פרק יד/טו/טז/יז ממוינים בסדר מספרי נכון (לא בסדר אלפביתי של ט,י)',
      () async {
        final links = [
          Link(
            heRef: 'פרק טז, א',
            index1: 1,
            path2: 'רשי',
            index2: 16,
            connectionType: 'COMMENTARY',
          ),
          Link(
            heRef: 'פרק טו, א',
            index1: 1,
            path2: 'רשי',
            index2: 15,
            connectionType: 'COMMENTARY',
          ),
          Link(
            heRef: 'פרק יז, א',
            index1: 1,
            path2: 'רשי',
            index2: 17,
            connectionType: 'COMMENTARY',
          ),
          Link(
            heRef: 'פרק יד, א',
            index1: 1,
            path2: 'רשי',
            index2: 14,
            connectionType: 'COMMENTARY',
          ),
        ];

        final result = await getLinksforIndexs(
          indexes: const [0],
          links: links,
          commentatorsToShow: const ['רשי'],
        );

        expect(
          result.map((l) => l.index2).toList(),
          [14, 15, 16, 17],
          reason: 'הסדר חייב להיות יד(14), טו(15), טז(16), יז(17)',
        );
      },
    );

    test('טו ממוקם אחרי יד באותה כותרת (תיקון מיוחד לטו)', () async {
      // לפני התיקון: ' טו,' הוחלף ב-' ,יה' (פסיק לפני האותיות), כך ש-טו
      // הוצב לפני יד במיון. אחרי התיקון, ' טו,' מוחלף ב-' יה,' (פסיק אחרי),
      // והמיון נכון: יד(14) קודם ל-טו(15).
      final links = [
        Link(
          heRef: 'פרק טו, א',
          index1: 1,
          path2: 'רשי',
          index2: 15,
          connectionType: 'COMMENTARY',
        ),
        Link(
          heRef: 'פרק יד, א',
          index1: 1,
          path2: 'רשי',
          index2: 14,
          connectionType: 'COMMENTARY',
        ),
      ];

      final result = await getLinksforIndexs(
        indexes: const [0],
        links: links,
        commentatorsToShow: const ['רשי'],
      );

      expect(result.map((l) => l.heRef).toList(), ['פרק יד, א', 'פרק טו, א']);
    });

    test('טז ממוקם אחרי טו (בדיקת השלמת ההמרה)', () async {
      final links = [
        Link(
          heRef: 'פרק טז, א',
          index1: 1,
          path2: 'רשי',
          index2: 16,
          connectionType: 'COMMENTARY',
        ),
        Link(
          heRef: 'פרק טו, א',
          index1: 1,
          path2: 'רשי',
          index2: 15,
          connectionType: 'COMMENTARY',
        ),
      ];

      final result = await getLinksforIndexs(
        indexes: const [0],
        links: links,
        commentatorsToShow: const ['רשי'],
      );

      expect(result.map((l) => l.index2).toList(), [15, 16]);
    });

    test('טו במקום אמצעי לא משבש את הסדר של פרקים אחרים', () async {
      // וידוא שההחלפה אינה חודרת לפרקים שלא כוללים ' טו,' / ' טז,'.
      final links = [
        Link(
          heRef: 'פרק ב, א',
          index1: 1,
          path2: 'רשי',
          index2: 2,
          connectionType: 'COMMENTARY',
        ),
        Link(
          heRef: 'פרק טו, א',
          index1: 1,
          path2: 'רשי',
          index2: 15,
          connectionType: 'COMMENTARY',
        ),
        Link(
          heRef: 'פרק א, א',
          index1: 1,
          path2: 'רשי',
          index2: 1,
          connectionType: 'COMMENTARY',
        ),
      ];

      final result = await getLinksforIndexs(
        indexes: const [0],
        links: links,
        commentatorsToShow: const ['רשי'],
      );

      expect(result.map((l) => l.index2).toList(), [1, 2, 15]);
    });
  });
}
