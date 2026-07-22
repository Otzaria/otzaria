import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/utils/text/word_at_position.dart';

void main() {
  Future<String?> wordAt(
    WidgetTester tester,
    String text,
    String target,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: Center(child: Text(text))),
      ),
    );
    final paragraph = tester.renderObject<RenderParagraph>(find.text(text));
    final charIndex = text.indexOf(target) + target.length ~/ 2;
    final caret = paragraph.getOffsetForCaret(
      TextPosition(offset: charIndex),
      Rect.zero,
    );
    final global = paragraph.localToGlobal(caret + const Offset(1, 5));
    return wordAtGlobalPosition(global);
  }

  group('wordAtGlobalPosition', () {
    testWidgets('מחזיר מילה רגילה תחת הסמן', (tester) async {
      expect(await wordAt(tester, 'אמר שלום היום', 'שלום'), 'שלום');
    });

    testWidgets('שומר גרשיים ASCII בתוך המילה (לעז/ראשי תיבות)', (
      tester,
    ) async {
      expect(await wordAt(tester, 'אמר פוריל"ש היום', 'פוריל"ש'), 'פוריל"ש');
    });

    testWidgets('שומר גרשיים עבריים (U+05F4) בתוך המילה', (tester) async {
      expect(await wordAt(tester, 'אמר פוריל״ש היום', 'פוריל״ש'), 'פוריל״ש');
    });

    testWidgets('שומר גרשיים גם במילה מנוקדת', (tester) async {
      expect(
        await wordAt(tester, 'אמר פּוֹרִיל"ש היום', 'פּוֹרִיל"ש'),
        'פּוֹרִיל"ש',
      );
    });

    testWidgets('שומר גרש בסוף קיצור', (tester) async {
      expect(await wordAt(tester, 'אמר וכו\' היום', 'וכו\''), 'וכו\'');
    });
  });
}
