import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/search/utils/snippet_builder.dart';

import '../support/search_engine_test_init.dart';

String _highlighted(List<InlineSpan> spans) => spans
    .whereType<TextSpan>()
    .where((span) => span.style?.fontWeight == FontWeight.bold)
    .map((span) => span.text ?? '')
    .join();

String _allText(List<InlineSpan> spans) =>
    spans.whereType<TextSpan>().map((span) => span.text ?? '').join();

const _defaultStyle = TextStyle();
const _highlightStyle = TextStyle(fontWeight: FontWeight.bold);

Future<void> main() async {
  // sanitizeQuery/splitQueryWords מאצילים למנוע ה-Rust; הטסטים שלהם דורשים
  // את הספרייה הנייטיבית ומדולגים כשאין build זמין.
  final engineReady = await tryInitSearchEngine();

  group('fromHighlightedHtml - הדגשות מהמנוע', () {
    test('מדגיש טקסט שעטוף בתג font ומשאיר את השאר רגיל', () {
      final spans = SnippetBuilder.fromHighlightedHtml(
        html: 'בראשית <font color="red">ברא</font> אלהים',
        defaultStyle: _defaultStyle,
        highlightStyle: _highlightStyle,
      );

      expect(_highlighted(spans), 'ברא');
      expect(_allText(spans), contains('בראשית'));
      expect(_allText(spans), contains('אלהים'));
      // תגי ה-HTML עצמם אינם מוצגים.
      expect(_allText(spans), isNot(contains('font')));
    });

    test('מדגיש גם תג mark', () {
      final spans = SnippetBuilder.fromHighlightedHtml(
        html: 'שלום <mark>עולם</mark>',
        defaultStyle: _defaultStyle,
        highlightStyle: _highlightStyle,
      );

      expect(_highlighted(spans), 'עולם');
    });

    test('תגי עיצוב של תוכן הספר (b) אינם נחשבים הדגשת חיפוש', () {
      final spans = SnippetBuilder.fromHighlightedHtml(
        html: '<b>כותרת</b> טקסט רגיל',
        defaultStyle: _defaultStyle,
        highlightStyle: _highlightStyle,
      );

      expect(_highlighted(spans), isEmpty);
      expect(_allText(spans), contains('כותרת'));
      expect(_allText(spans), contains('טקסט רגיל'));
    });
  });

  group('extractHighlightedTerms - חילוץ מונחי התאמה להדגשת PDF', () {
    test('מחלץ את תוכן תגי font ו-mark בלבד, ללא כפילויות', () {
      final terms = SnippetBuilder.extractHighlightedTerms(
        'בראשית <font color="red">ברא</font> אלהים '
        '<mark>שבתות</mark> וגם <font color="red">ברא</font>',
      );
      expect(terms, {'ברא', 'שבתות'});
    });

    test('תגי עיצוב של תוכן הספר (b) אינם נחשבים התאמה', () {
      final terms = SnippetBuilder.extractHighlightedTerms(
        '<b>כותרת</b> טקסט <font>מצא</font>',
      );
      expect(terms, {'מצא'});
    });

    test('HTML ללא תגי הדגשה מחזיר קבוצה ריקה', () {
      expect(
        SnippetBuilder.extractHighlightedTerms('טקסט רגיל בלי הדגשות'),
        isEmpty,
      );
    });

    test('מנרמל רווחים בתוך מונח מודגש', () {
      final terms = SnippetBuilder.extractHighlightedTerms(
        '<font>אבג   דהו</font>',
      );
      expect(terms, {'אבג דהו'});
    });
  });

  group(
    'highlightLiteral - חיפוש מקומי',
    () {
      test('מדגיש את השאילתה הליטרלית', () {
        final spans = SnippetBuilder.highlightLiteral(
          plainText: 'אמר שלום לכל אדם',
          query: 'שלום',
          defaultStyle: _defaultStyle,
          highlightStyle: _highlightStyle,
        );

        expect(_highlighted(spans), 'שלום');
      });

      test('סובלני לניקוד בטקסט המוצג', () {
        // "פַרעה" — פ עם פתח ואחריה רעה.
        final spans = SnippetBuilder.highlightLiteral(
          plainText: 'פַרעה אמר',
          query: 'פרעה',
          defaultStyle: _defaultStyle,
          highlightStyle: _highlightStyle,
        );

        final stripped = _highlighted(spans).replaceAll(RegExp(r'[֑-ׇ]'), '');
        expect(stripped, 'פרעה');
      });

      test('מכבד גבולות מילה ולא מדגיש חלק ממילה', () {
        // "אמר" מופיע בתוך "נאמרו" ולכן אסור להדגיש.
        final spans = SnippetBuilder.highlightLiteral(
          plainText: 'נאמרו דברים',
          query: 'אמר',
          defaultStyle: _defaultStyle,
          highlightStyle: _highlightStyle,
        );

        expect(_highlighted(spans), isEmpty);
      });

      test('מתאים גרשיים לועזיים בשאילתה לגרשיים עבריים בטקסט', () {
        // הטקסט מכיל ראשי תיבות עם ״ (U+05F4), השאילתה עם " רגיל.
        final spans = SnippetBuilder.highlightLiteral(
          plainText: 'רמב״ם אמר',
          query: 'רמב"ם',
          defaultStyle: _defaultStyle,
          highlightStyle: _highlightStyle,
        );

        expect(_highlighted(spans), 'רמב״ם');
      });

      test('מדגיש ביטוי רב-מילים כשמופיע ברצף', () {
        final spans = SnippetBuilder.highlightLiteral(
          plainText: 'פתיח אבג דהו סוף',
          query: 'אבג דהו',
          defaultStyle: _defaultStyle,
          highlightStyle: _highlightStyle,
        );

        final highlighted = _highlighted(spans);
        expect(highlighted, contains('אבג'));
        expect(highlighted, contains('דהו'));
      });

      test('ללא התאמה מחזיר את הטקסט כמות שהוא ללא הדגשה', () {
        final spans = SnippetBuilder.highlightLiteral(
          plainText: 'שלום עולם',
          query: 'ברכה',
          defaultStyle: _defaultStyle,
          highlightStyle: _highlightStyle,
        );

        expect(_highlighted(spans), isEmpty);
        expect(_allText(spans), 'שלום עולם');
      });
    },
    skip: engineReady ? false : searchEngineSkipReason,
  );

  group('buildExcerptText', () {
    test('טקסט קצר מהמגבלה מוחזר כמות שהוא', () {
      expect(
        SnippetBuilder.buildExcerptText(
          fullText: 'טקסט קצר',
          query: 'קצר',
          maxChars: 220,
        ),
        'טקסט קצר',
      );
    });

    test(
      'חותך קטע סביב ההתאמה ומוסיף "..."',
      () {
        final fullText = '${'מילה ' * 60}מצרים ${'עוד ' * 60}';
        final excerpt = SnippetBuilder.buildExcerptText(
          fullText: fullText,
          query: 'מצרים',
          maxChars: 60,
        );

        expect(excerpt, contains('מצרים'));
        expect(excerpt, contains('...'));
        expect(excerpt.length, lessThan(fullText.length));
      },
      skip: engineReady ? false : searchEngineSkipReason,
    );

    test(
      'ללא התאמה מחזיר את תחילת הטקסט עם "..."',
      () {
        final fullText = 'אבגד ' * 60;
        final excerpt = SnippetBuilder.buildExcerptText(
          fullText: fullText,
          query: 'מצרים',
          maxChars: 60,
        );

        expect(excerpt.trimRight(), endsWith('...'));
        expect(excerpt.length, lessThan(fullText.trim().length));
      },
      skip: engineReady ? false : searchEngineSkipReason,
    );
  });

  group('htmlToPlainText - חילוץ טקסט גולמי', () {
    test('מסיר תגי הדגשה של המנוע ומנרמל רווחים', () {
      final plain = SnippetBuilder.htmlToPlainText(
        'בראשית <font color="red">ברא</font>   אלהים',
      );
      expect(plain, 'בראשית ברא אלהים');
    });
  });

  group('spansFromRanges - הדגשת חלק מטוקן בסרגל התוצאות', () {
    test('מדגיש רק את הטווח שהתקבל ולא את המילה השלמה', () {
      const text = 'דכוותי כוונתו';
      // "כוו" בתוך "דכוותי" (אופסט 1) ובתוך "כוונתו" (אופסט 7)
      final spans = SnippetBuilder.spansFromRanges(
        plainText: text,
        ranges: const [
          [1, 4],
          [7, 10],
        ],
        defaultStyle: _defaultStyle,
        highlightStyle: _highlightStyle,
      );

      expect(_highlighted(spans), 'כווכוו');
      expect(_allText(spans), text);
    });

    test('רשימת טווחים ריקה משאירה את הטקסט ללא הדגשה', () {
      final spans = SnippetBuilder.spansFromRanges(
        plainText: 'טקסט בלי התאמה',
        ranges: const [],
        defaultStyle: _defaultStyle,
        highlightStyle: _highlightStyle,
      );
      expect(_highlighted(spans), isEmpty);
      expect(_allText(spans), 'טקסט בלי התאמה');
    });

    test('מתעלם מטווח חורג מגבולות הטקסט', () {
      const text = 'קצר';
      final spans = SnippetBuilder.spansFromRanges(
        plainText: text,
        ranges: const [
          [0, 99],
        ],
        defaultStyle: _defaultStyle,
        highlightStyle: _highlightStyle,
      );
      expect(_allText(spans), text);
    });
  });
}
