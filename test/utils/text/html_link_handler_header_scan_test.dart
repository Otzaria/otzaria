import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/utils/text/heading_slug.dart';
import 'package:otzaria/utils/text/html_link_handler.dart';

bool _referenceMatch(String text, String headerName) {
  final cleanText = text.trim().replaceAll(RegExp(r'\s+'), '');
  final cleanHeader = headerName.trim().replaceAll(RegExp(r'\s+'), '');
  if (cleanText == cleanHeader) return true;
  return headingSlug(text) == headingSlug(headerName);
}

void main() {
  final samples = <String>[
    '',
    ' ',
    'א',
    'ב',
    'סימן א',
    'סימן   א',
    'סימן\tא',
    'סימן א',
    'סימן-א',
    'סימן--א',
    '-סימן-',
    'פרק: מבוא כללי',
    'פרק-מבוא-כללי',
    'פרק מבוא כללי',
    'וַיֹּאמֶר משֶׁה',
    'ויאמר משה',
    'בְּרֵאשִׁ֖ית בָּרָ֣א אֱלֹהִ֑ים',
    'בראשית ברא אלהים',
    'אֵ֣לֶּה תּוֹלְדֹ֣ת',
    'ה"ג',
    "ה'ג",
    'הג',
    'ה״ג',
    'ה׳ג',
    'דף כג א',
    'דף כג ב',
    'דף כג',
    'Hello World',
    'hello world',
    'HELLO-WORLD',
    'JSON ← מיפוי',
    'ערכי JSON ← מיפוי',
    'ערכי-json--מיפוי',
    'a_b-c 1',
    '0. מפה מהירה',
    '0-מפה-מהירה',
    'ß İ',
    'ÀÉ',
    'àé',
    '日本語',
    '١٢٣',
    'x' * 300,
    'סימן א ' * 60,
  ];

  group('isHeaderMatch equivalence', () {
    test('זהה למימוש הייחוס על כל זוגות הדוגמאות', () {
      for (final text in samples) {
        for (final header in samples) {
          expect(
            HtmlLinkHandler.isHeaderMatch(text, header),
            _referenceMatch(text, header),
            reason: '"$text" vs "$header"',
          );
        }
      }
    });
  });

  group('סריקת שורות ארוכות', () {
    test('כותרת שאינה מופיעה: מהיר פי 4 לפחות ממימוש הייחוס', () {
      final lines = List.generate(
        5000,
        (i) => 'פרק $i וַיֹּאמֶר משֶׁה אֶל־הָעָם ' * 6,
      );
      int scanMicros(bool Function(String, String) match) {
        final watch = Stopwatch()..start();
        var matches = 0;
        for (final line in lines) {
          if (match(line, 'כותרת קצרה')) matches++;
        }
        watch.stop();
        expect(matches, 0);
        return watch.elapsedMicroseconds;
      }

      // השוואה יחסית באותה מכונה, כדי שמהירות ה-runner לא תשפיע.
      scanMicros(HtmlLinkHandler.isHeaderMatch);
      final reference = scanMicros(_referenceMatch);
      final current = scanMicros(HtmlLinkHandler.isHeaderMatch);
      expect(current * 4, lessThan(reference));
    });

    test('שורה שה-slug שלה שווה לכותרת מזוהה גם בין שורות ארוכות', () {
      expect(
        HtmlLinkHandler.isHeaderMatch('ערכי JSON ← מיפוי', 'ערכי-json--מיפוי'),
        isTrue,
      );
      expect(
        HtmlLinkHandler.isHeaderMatch('ערכי JSON ← מיפוי ' * 40, 'ערכי-json'),
        isFalse,
      );
    });
  });
}
