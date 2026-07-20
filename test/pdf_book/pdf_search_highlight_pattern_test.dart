import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/pdf_book/view/pdf_search_screen.dart';

import '../support/search_engine_test_init.dart';

/// מייצר מונחים עבריים ייחודיים (ללא אותיות סופיות, למניעת נרמול-שקילות).
String _term(int i) {
  const letters = 'אבגדהוזחטיכלמנסעפצקרשת';
  return 'קדם${letters[i % 22]}${letters[i ~/ 22]}';
}

Future<void> main() async {
  final engineReady = await tryInitSearchEngine();

  group('buildAdvancedHighlightPattern - תבנית הדגשה על דפי PDF', () {
    test('תוצאות בלי תגי הדגשה מחזירות null', () {
      expect(
        PdfBookSearchView.buildAdvancedHighlightPattern([
          'טקסט בלי הדגשות',
          '<b>כותרת</b> עוד טקסט',
        ]),
        isNull,
      );
    });

    test('רשימת תוצאות ריקה מחזירה null', () {
      expect(
        PdfBookSearchView.buildAdvancedHighlightPattern(const []),
        isNull,
      );
    });

    group('עם המנוע', () {
      test('התבנית מתאימה למונח שהמנוע סימן, לא לשאילתה', () {
        // חיפוש fuzzy של "שבת" שמצא "שבתות" — על העמוד מודגש "שבתות".
        final pattern = PdfBookSearchView.buildAdvancedHighlightPattern([
          'ושמרו <font color="red">שבתות</font> הרבה',
        ])!;

        expect(pattern.hasMatch('בזכות שבתות שנשמרו'), isTrue);
        expect(pattern.hasMatch('טקסט אחר לגמרי'), isFalse);
      });

      test('מונחים מכמה תוצאות מאוחדים לתבנית אחת', () {
        final pattern = PdfBookSearchView.buildAdvancedHighlightPattern([
          'א <font>שבת</font> ב',
          'ג <mark>שבתות</mark> ד',
        ])!;

        expect(pattern.hasMatch('שבת קודש'), isTrue);
        expect(pattern.hasMatch('שתי שבתות'), isTrue);
      });

      test('התבנית סובלנית לניקוד בשכבת הטקסט של ה-PDF', () {
        final pattern = PdfBookSearchView.buildAdvancedHighlightPattern([
          '<font>פרעה</font>',
        ])!;

        expect(pattern.hasMatch('וַיֹּאמֶר פַּרְעֹה'), isTrue);
      });

      test('מכבדת גבולות מילה — לא מדגישה חלק ממילה אחרת', () {
        final pattern = PdfBookSearchView.buildAdvancedHighlightPattern([
          '<font>אמר</font>',
        ])!;

        expect(pattern.hasMatch('נאמרו דברים'), isFalse);
        expect(pattern.hasMatch('אמר רבא'), isTrue);
      });

      test('מונח שחוזר בכמה תוצאות נכלל פעם אחת', () {
        final single = PdfBookSearchView.buildAdvancedHighlightPattern([
          '<font>ברא</font>',
        ])!;
        final duplicated = PdfBookSearchView.buildAdvancedHighlightPattern([
          '<font>ברא</font>',
          'שוב <font>ברא</font> עולם',
        ])!;

        expect(duplicated.pattern, single.pattern);
      });

      test('נאכפת תקרת מונחים — מונחים מעבר לתקרה לא נכללים', () {
        final htmls = List.generate(
          60,
          (i) => 'לפני <font>${_term(i)}</font> אחרי',
        );
        final pattern = PdfBookSearchView.buildAdvancedHighlightPattern(htmls)!;

        expect(pattern.hasMatch(_term(0)), isTrue);
        expect(pattern.hasMatch(_term(49)), isTrue);
        expect(pattern.hasMatch(_term(59)), isFalse);
      });
    }, skip: engineReady ? false : searchEngineSkipReason);
  });
}
