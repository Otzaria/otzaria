import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';
import 'package:otzaria/widgets/smart_text/smart_text_widget.dart';

// סמני הערות ועוגני מפרשים חייבים להישאר TextSpan טהור. הגבהה ב-fwfh
// (vertical-align / <sup>) בונה WidgetSpan, ו-Flutter משבץ placeholders בפסקת
// RTL בסדר ויזואלי — כך שתוכן שני סמנים באותה שורה מתחלף.
void main() {
  final theme = ThemeData(
    colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
  );

  Future<List<InlineSpan>> pumpAndCollect(
    WidgetTester tester,
    String html,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: SmartTextWidget(
            text: html,
            settings: const RenderSettings(
              fontSize: 20,
              fontFamily: 'FrankRuhlCLM',
            ),
            onAnchorTap: (_) {},
            onNoteTap: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final spans = <InlineSpan>[];
    for (final element in find.byType(RichText).evaluate()) {
      (element.widget as RichText).text.visitChildren((span) {
        spans.add(span);
        return true;
      });
    }
    return spans;
  }

  const cases = <String, String>{
    'סמן הערה לא-מספרי': 'לפני <sup class="footnote-marker">א</sup> אחרי',
    'סמן הערת ספר':
        'לפני <a class="book-note-marker" href="otzaria://note?id=1">א</a> '
        'אחרי',
    'סמן הערת ספר מספרי':
        'לפני <a class="book-note-marker" href="otzaria://note?id=1">3</a> '
        'אחרי',
    'עוגן מפרש':
        'לפני <a class="link-anchor link-anchor-2" '
        'href="otzaria://anchor?ref=3_0">א</a> אחרי',
  };

  for (final entry in cases.entries) {
    testWidgets('${entry.key}: בלי WidgetSpan', (tester) async {
      final spans = await pumpAndCollect(tester, entry.value);

      expect(spans, isNotEmpty);
      expect(
        spans.whereType<WidgetSpan>(),
        isEmpty,
        reason:
            'הסמן נבנה כ-placeholder — סדר הסמנים יתהפך בשורת RTL עם שני סמנים',
      );
    });
  }

  testWidgets('שני סמנים בשורה — התוכן נשאר בסדר הלוגי', (tester) async {
    final spans = await pumpAndCollect(
      tester,
      'ראשון <sup class="footnote-marker">א</sup> '
      'שני <sup class="footnote-marker">ב</sup> סוף',
    );

    expect(spans.whereType<WidgetSpan>(), isEmpty);

    final text = spans
        .whereType<TextSpan>()
        .map((span) => span.text ?? '')
        .join();
    expect(text.indexOf('א'), lessThan(text.indexOf('ב')));
  });
}
