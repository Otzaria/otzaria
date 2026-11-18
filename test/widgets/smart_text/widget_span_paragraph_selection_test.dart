import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:otzaria/widgets/smart_text/render_settings.dart';
import 'package:otzaria/widgets/smart_text/smart_text_widget.dart';

// PNG שקוף 1x1.
const _pngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=';
const _img =
    '<img width="20" height="20" src="data:image/png;base64,$_pngBase64">';
const _imageLine = 'אלף בית $_img גימל דלת $_img הא וו';
const _above = 'שורה עליונה פשוטה';
const _below = 'שורה תחתונה פשוטה';

Future<SelectedContent? Function()> _pumpLines(WidgetTester tester) async {
  SelectedContent? selected;
  await tester.pumpWidget(
    MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: SelectionArea(
            onSelectionChanged: (content) => selected = content,
            child: const SizedBox(
              width: 600,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SmartTextWidget(
                    text: _above,
                    settings: RenderSettings(fontSize: 20),
                  ),
                  SmartTextWidget(
                    text: _imageLine,
                    settings: RenderSettings(fontSize: 20),
                  ),
                  SmartTextWidget(
                    text: _below,
                    settings: RenderSettings(fontSize: 20),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return () => selected;
}

Offset _wordCenter(WidgetTester tester, String word) {
  for (final paragraph
      in tester.allRenderObjects.whereType<RenderParagraph>()) {
    final text = paragraph.text.toPlainText();
    final index = text.indexOf(word);
    if (index < 0) continue;
    final boxes = paragraph.getBoxesForSelection(
      TextSelection(baseOffset: index, extentOffset: index + word.length),
    );
    return paragraph.localToGlobal(boxes.first.toRect().center);
  }
  throw StateError('המילה "$word" לא נמצאה');
}

Future<void> _click(WidgetTester tester, Offset position, int count) async {
  final gesture = await tester.startGesture(
    position,
    kind: PointerDeviceKind.mouse,
  );
  for (var i = 0; i < count; i++) {
    if (i > 0) await gesture.down(position);
    await tester.pump();
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 50));
  }
  await gesture.removePointer();
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  testWidgets('שורת התמונות עוברת ב-HtmlWidget עם WidgetSpan', (tester) async {
    await _pumpLines(tester);
    expect(find.byType(HtmlWidget), findsOneWidget);
    final imageParagraph = tester.allRenderObjects
        .whereType<RenderParagraph>()
        .singleWhere((p) => p.text.toPlainText().contains('גימל'));
    expect(imageParagraph.text.toPlainText(), contains('￼'));
  });

  for (final word in ['בית', 'דלת', 'וו']) {
    testWidgets('לחיצה משולשת על "$word" בוחרת את כל שורת התמונות בלבד', (
      tester,
    ) async {
      final selected = await _pumpLines(tester);
      await _click(tester, _wordCenter(tester, word), 3);

      final text = selected()?.plainText ?? '';
      expect(text, contains('אלף בית'));
      expect(text, contains('גימל דלת'));
      expect(text, contains('הא וו'));
      expect(text, isNot(contains('עליונה')));
      expect(text, isNot(contains('תחתונה')));
    });
  }

  testWidgets('לחיצה כפולה בשורת התמונות בוחרת מילה אחת', (tester) async {
    final selected = await _pumpLines(tester);
    await _click(tester, _wordCenter(tester, 'דלת'), 2);
    expect(selected()?.plainText, 'דלת');
  });

  testWidgets('לחיצה משולשת בשורה פשוטה בוחרת רק אותה', (tester) async {
    final selected = await _pumpLines(tester);
    await _click(tester, _wordCenter(tester, 'עליונה'), 3);
    expect(selected()?.plainText, _above);
  });

  testWidgets('גרירה בין שורות כוללת את שורת התמונות כולה', (tester) async {
    final selected = await _pumpLines(tester);
    final gesture = await tester.startGesture(
      _wordCenter(tester, 'עליונה'),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await gesture.moveTo(_wordCenter(tester, 'תחתונה'));
    await tester.pump();
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 500));

    final text = selected()?.plainText ?? '';
    expect(text, contains('אלף בית'));
    expect(text, contains('גימל דלת'));
    expect(text, contains('הא וו'));
    expect(text, contains('תח'));
  });
}
