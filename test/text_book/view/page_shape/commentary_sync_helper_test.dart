import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/text_book/view/page_shape/utils/commentary_sync_helper.dart';

Link _link({required int index1, required int index2}) => Link(
  heRef: 'ref',
  index1: index1,
  path2: 'commentary.txt',
  index2: index2,
  connectionType: 'commentary',
);

void main() {
  group('CommentarySyncIndex', () {
    test('מחזיר null כשאין קישורים', () {
      expect(
        CommentarySyncIndex(const []).targetIndexFor(5),
        isNull,
      );
    });

    test('נצמד לקישור מדויק כשהשורה במקור היא בדיוק על קישור', () {
      final links = [
        _link(index1: 1, index2: 1),
        _link(index1: 10, index2: 50),
      ];
      // logicalMainIndex 0 => mainLineNumber 1 => בדיוק על הקישור הראשון
      expect(
        CommentarySyncIndex(links).targetIndexFor(0),
        0, // index2(1) - 1
      );
    });

    test('נצמד לקישור הקודם הקרוב גם כשיש קישור הבא', () {
      final links = [
        _link(index1: 1, index2: 1), // יעד 0-based: 0
        _link(index1: 11, index2: 101), // יעד 0-based: 100
      ];
      // mainLineNumber 6 => בין הקישורים, אך נצמד לקודם (יעד 0)
      expect(
        CommentarySyncIndex(links).targetIndexFor(5),
        0,
      );
    });

    test('נצמד לקישור הקודם גם קרוב מאוד לקישור הבא', () {
      final links = [
        _link(index1: 1, index2: 1),
        _link(index1: 5, index2: 41),
      ];
      // mainLineNumber 2 => הקישור הקודם הוא (1,1), היעד 0
      expect(
        CommentarySyncIndex(links).targetIndexFor(1),
        0,
      );
    });

    test('נצמד לקישור הקודם כשאין קישור הבא', () {
      final links = [
        _link(index1: 1, index2: 1),
        _link(index1: 10, index2: 50),
      ];
      // mainLineNumber 15 => אחרי הקישור האחרון
      expect(
        CommentarySyncIndex(links).targetIndexFor(14),
        49, // index2(50) - 1
      );
    });

    test('נצמד לקישור הראשון כשאין קישור קודם', () {
      final links = [
        _link(index1: 10, index2: 50),
        _link(index1: 20, index2: 100),
      ];
      // mainLineNumber 5 => לפני הקישור הראשון
      expect(
        CommentarySyncIndex(links).targetIndexFor(4),
        49, // index2(50) - 1
      );
    });

    test('מתמודד עם קישורים לא ממוינים', () {
      final links = [
        _link(index1: 11, index2: 101),
        _link(index1: 1, index2: 1),
      ];
      // mainLineNumber 6 => הקישור הקודם הוא (1,1), היעד 0
      expect(
        CommentarySyncIndex(links).targetIndexFor(5),
        0,
      );
    });

    test('שורת מקור עם כמה קטעי מפרש — נצמד לתחילת הבלוק', () {
      // אור החיים על בראשית מגיע ל-63 קישורים על שורת מקור אחת.
      final links = [
        _link(index1: 10, index2: 80),
        _link(index1: 10, index2: 42),
        _link(index1: 10, index2: 57),
      ];
      expect(
        CommentarySyncIndex(links).targetIndexFor(9),
        41, // index2(42) - 1 — הקטע הראשון, לא זה שבמקרה ראשון ברשימה
      );
    });

    test('היעד אינו תלוי בסדר הקישורים באותה שורת מקור', () {
      final ascending = [
        _link(index1: 7, index2: 20),
        _link(index1: 7, index2: 35),
      ];
      final descending = [
        _link(index1: 7, index2: 35),
        _link(index1: 7, index2: 20),
      ];
      for (final links in [ascending, descending]) {
        expect(
          CommentarySyncIndex(links).targetIndexFor(6),
          19, // index2(20) - 1, בשני סדרי הקלט
        );
      }
    });

    test('קישור הבא בריבוי קטעים — גם הוא נצמד לתחילת הבלוק', () {
      // אין קישור קודם, ולכן נופלים על הקישור הבא הראשון.
      final links = [
        _link(index1: 30, index2: 90),
        _link(index1: 30, index2: 65),
      ];
      expect(
        CommentarySyncIndex(links).targetIndexFor(4),
        64, // index2(65) - 1
      );
    });

    test('מחשב כמה יעדים מאותו אינדקס בלי לשנות את סדר הקישורים', () {
      final links = [
        _link(index1: 30, index2: 140),
        _link(index1: 10, index2: 40),
        _link(index1: 30, index2: 120),
        _link(index1: 20, index2: 80),
        _link(index1: 10, index2: 20),
      ];
      final original = List<Link>.of(links);
      final index = CommentarySyncIndex(links);

      expect(
        [-1, 9, 18, 19, 28, 29, 100].map(index.targetIndexFor),
        orderedEquals([19, 19, 19, 79, 79, 119, 119]),
      );
      expect(links, orderedEquals(original));

      links.add(_link(index1: 20, index2: 10));
      expect(index.targetIndexFor(19), 79);
      expect(CommentarySyncIndex(links).targetIndexFor(19), 9);
    });
  });

  group('glideDelta', () {
    const alignment = 1 / 3;
    const epsilon = 2.0;

    double? delta(double leadingEdge, {double viewportHeight = 600}) =>
        CommentarySyncHelper.glideDelta(
          leadingEdge: leadingEdge,
          viewportHeight: viewportHeight,
          alignment: alignment,
          epsilon: epsilon,
        );

    test('היעד כבר על קו העוגן — אין תזוזה', () {
      expect(delta(alignment), isNull);
    });

    test('סטייה מתחת לסף — אין תזוזה', () {
      // 1.8 פיקסלים: מתחת ל-2, אחרת כל שבר פיקסל היה יורה אנימציה חדשה.
      expect(delta(alignment + 1.8 / 600), isNull);
    });

    test('היעד מתחת לקו העוגן — גלילה קדימה', () {
      // חצי חלון מתחת לשליש: 600*(0.5-1/3) = 100
      expect(delta(0.5), closeTo(100, 0.001));
    });

    test('היעד מעל קו העוגן — גלילה אחורה', () {
      expect(delta(0), closeTo(-200, 0.001));
    });

    test('גובה חלון גדול יותר מגדיל את התזוזה באותו יחס', () {
      final small = delta(0.5, viewportHeight: 300)!;
      final large = delta(0.5, viewportHeight: 900)!;

      expect(large, closeTo(small * 3, 0.001));
    });

    test('ערך לא סופי אינו מייצר תזוזה', () {
      expect(delta(double.nan), isNull);
      expect(delta(0.5, viewportHeight: double.infinity), isNull);
    });

    test('הסף נמדד בפיקסלים ולא בשבר החלון', () {
      // אותו שבר סטייה: בחלון נמוך הוא פחות מ-2 פיקסלים ונבלע, בחלון גבוה
      // הוא חורג ומזיז. בלי זה חלוניות בגדלים שונים היו מתנהגות אחרת.
      const drift = 0.005;

      expect(delta(alignment + drift, viewportHeight: 200), isNull);
      expect(delta(alignment + drift, viewportHeight: 2000), isNotNull);
    });

    test('מעט מעל הסף — כן זזים', () {
      expect(delta(alignment + (epsilon + 0.5) / 600), isNotNull);
    });

    test('הסימן עקבי עם כיוון הסטייה', () {
      expect(delta(0.9)!, isPositive);
      expect(delta(0.05)!, isNegative);
    });

    test('גובה חלון אפס או שלילי אינו מייצר תזוזה', () {
      // מגן על מסלול שבו טרם נמדדה פריסה; בלעדיו הדלתא הייתה 0 ומתפרשת
      // כ"היעד במקומו" גם כשהוא רחוק.
      expect(delta(0.9, viewportHeight: 0), isNull);
    });

    test('יעד מחוץ לחלון הנראה מייצר תזוזה גדולה מגובה החלון', () {
      // itemLeadingEdge יכול לחרוג מ-[0,1] כשהפריט מעל או מתחת ל-viewport.
      expect(delta(2.0)!.abs(), greaterThan(600));
    });
  });

  group('getLogicalIndex', () {
    test('שורה רגילה מוחזרת כמות שהיא', () {
      expect(CommentarySyncHelper.getLogicalIndex(1, const ['a', 'b']), 1);
    });

    test('כותרת מדלגת לשורה שאחריה', () {
      // כותרות אינן נושאות קישורים, ולכן היעד נגזר מהשורה שמתחתן; בלי זה
      // כל כותרת נראית כפער מלאכותי במקור.
      const content = ['<h1>פרק א</h1>', 'תוכן'];

      expect(CommentarySyncHelper.getLogicalIndex(0, content), 1);
    });

    test('רצף כותרות מדלג עד לתוכן', () {
      const content = ['<h1>א</h1>', '<h2>ב</h2>', '<h3>ג</h3>', 'תוכן'];

      expect(CommentarySyncHelper.getLogicalIndex(0, content), 3);
    });

    test('כותרות עד סוף התוכן מחזירות את האינדקס המקורי', () {
      const content = ['תוכן', '<h1>סוף</h1>'];

      expect(CommentarySyncHelper.getLogicalIndex(1, content), 1);
    });

    test('אינדקס מחוץ לטווח מוחזר כמות שהוא', () {
      expect(CommentarySyncHelper.getLogicalIndex(9, const ['a']), 9);
      expect(CommentarySyncHelper.getLogicalIndex(-1, const ['a']), -1);
    });
  });

  group('shouldMoveCommentary', () {
    test('בחירת טקסט על אותה שורה נבחרת אינה מזיזה את המפרש', () {
      // UpdateSelectedTextForNote נפלט בכל תזוזת עכבר בזמן גרירת סימון. תזוזה
      // בכל אחת מהן הרעידה את המפרשים בצורת הדף (issue #976).
      expect(
        CommentarySyncHelper.shouldMoveCommentary(
          targetIndex: 12,
          selectedMainIndex: 5,
          lastSyncedIndex: 12,
          lastSyncedMainIndex: 5,
        ),
        isFalse,
      );
    });

    test('לחיצה על שורה אחרת שממופה לאותו יעד כן מזיזה', () {
      // המפרש נצמד לקישור הקודם, ולכן שורות סמוכות חולקות יעד. לחיצה חדשה
      // צריכה להחזיר את המפרש למקומו גם אחרי שהמשתמש גלל בו ידנית.
      expect(
        CommentarySyncHelper.shouldMoveCommentary(
          targetIndex: 12,
          selectedMainIndex: 6,
          lastSyncedIndex: 12,
          lastSyncedMainIndex: 5,
        ),
        isTrue,
      );
    });

    test('יעד חדש מזיז את המפרש', () {
      expect(
        CommentarySyncHelper.shouldMoveCommentary(
          targetIndex: 20,
          selectedMainIndex: 5,
          lastSyncedIndex: 12,
          lastSyncedMainIndex: 5,
        ),
        isTrue,
      );
    });

    test('גלילה ללא בחירה על יעד שסונכרן אינה מזיזה', () {
      expect(
        CommentarySyncHelper.shouldMoveCommentary(
          targetIndex: 12,
          selectedMainIndex: null,
          lastSyncedIndex: 12,
          lastSyncedMainIndex: null,
        ),
        isFalse,
      );
    });

    test('ביטול הבחירה על אותו יעד מזיז — הגלילה חוזרת לעקוב אחר הנראה', () {
      expect(
        CommentarySyncHelper.shouldMoveCommentary(
          targetIndex: 12,
          selectedMainIndex: null,
          lastSyncedIndex: 12,
          lastSyncedMainIndex: 5,
        ),
        isTrue,
      );
    });

    test('סנכרון ראשוני תמיד מזיז', () {
      expect(
        CommentarySyncHelper.shouldMoveCommentary(
          targetIndex: 0,
          selectedMainIndex: null,
          lastSyncedIndex: null,
          lastSyncedMainIndex: null,
        ),
        isTrue,
      );
    });
  });

  group('isHeaderLine', () {
    test('מזהה כותרות בכל הרמות', () {
      for (final level in [1, 2, 3, 4, 5, 6]) {
        expect(CommentarySyncHelper.isHeaderLine('<h$level>כותרת'), isTrue);
      }
    });

    test('מזהה כותרת עם רווח מוביל ובאותיות גדולות', () {
      expect(CommentarySyncHelper.isHeaderLine('  <H2>כותרת'), isTrue);
    });

    test('טקסט רגיל אינו כותרת', () {
      expect(CommentarySyncHelper.isHeaderLine('שורת תוכן'), isFalse);
      expect(CommentarySyncHelper.isHeaderLine('<p>פסקה'), isFalse);
      expect(CommentarySyncHelper.isHeaderLine(''), isFalse);
    });
  });
}
