import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// היפוך הצבעים של ה-PDF חייב להיגזר מבהירות התמה בפועל: הדגל השמור
/// `isDarkMode` נשאר על ערכו הישן במצב "מערכת", וה-PDF נתקע כהה (issue #1426).
void main() {
  final lines = File(
    'lib/pdf_book/view/pdf_book_screen.dart',
  ).readAsLinesSync();
  final code = lines
      .where((line) => !line.trimLeft().startsWith('//'))
      .toList();

  test('אין צרכן של SettingsState.isDarkMode במסך ה-PDF', () {
    expect(code.join('\n'), isNot(contains('.state.isDarkMode')));
  });

  test('כל היפוך צבעים נגזר מ-Theme.of(context).brightness', () {
    const themeBrightness = 'Theme.of(context).brightness == Brightness.dark';
    var sites = 0;
    for (var i = 0; i < code.length; i++) {
      if (!code[i].contains('BlendMode.difference')) continue;
      sites++;
      final window = code.sublist(i - 10 < 0 ? 0 : i - 10, i + 1).join('\n');
      expect(
        window,
        contains(themeBrightness),
        reason: 'ההיפוך בשורה ${i + 1} אינו נגזר מבהירות התמה',
      );
    }
    expect(sites, 2);
  });

  // issue #1419: בפריסה נעוצה אין קליפ סביב התוכן, והשכבה ההפוכה כיסתה בלבן את
  // הסרגל העליון.
  test('ה-ColorFiltered של הצפיין עטוף ב-ClipRect', () {
    final index = code.indexWhere((l) => l.contains('child: ColorFiltered('));
    expect(index, greaterThan(0));
    expect(code[index - 1], contains('child: ClipRect('));
  });

  testWidgets('ClipRect מונע מהשכבה ההפוכה לצבוע את מה שמעליה', (tester) async {
    Future<int> barPixel({required bool clip}) async {
      final key = GlobalKey();
      Widget viewer = const ColorFiltered(
        colorFilter: ColorFilter.mode(Colors.white, BlendMode.difference),
        child: ColoredBox(color: Color(0xFFDBDBDB), child: SizedBox.expand()),
      );
      if (clip) viewer = ClipRect(child: viewer);
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: Column(
            children: [
              Container(height: 56, color: const Color(0xFF303030)),
              Expanded(child: RepaintBoundary(child: viewer)),
            ],
          ),
        ),
      );
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      late int red;
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        final bytes = await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        red = bytes!.getUint8((20 * image.width + 100) * 4);
        image.dispose();
      });
      return red;
    }

    expect(await barPixel(clip: false), 0xFF);
    expect(await barPixel(clip: true), 0x30);
  });
}
