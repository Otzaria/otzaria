import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/misc/app_menu_exports.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final metrics = AppMenuMetrics.create(compactMenus: false);
  const widest = 'WWW: WASHINGTON WASHINGTON WWW';
  final entries = [
    for (var i = 0; i < 64; i++)
      AppMenuEntry<int>(
        value: i,
        label: 'Illinois: little cities, little districts $i',
      ),
    const AppMenuEntry<int>(value: 64, label: widest),
  ];

  setUpAll(() async {
    await (FontLoader(
      'Roboto',
    )..addFont(rootBundle.load('fonts/Rubik-VariableFont_wght.ttf'))).load();
  });

  testWidgets('תווית קצרה ורחבה נמדדת גם אחרי 64 תוויות צרות', (tester) async {
    final singleWidth = calculateAppMenuPreferredWidth(metrics, [entries.last]);
    final width64 = calculateAppMenuPreferredWidth(metrics, entries.sublist(1));
    final width65 = calculateAppMenuPreferredWidth(metrics, entries);

    expect(width64, greaterThanOrEqualTo(singleWidth));
    expect(width65, greaterThanOrEqualTo(singleWidth));
    expect(width65, greaterThanOrEqualTo(width64));
  });

  testWidgets('תפריט RTL מציג את התווית הרחבה בלי קיצוץ', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          textTheme: const TextTheme(bodyMedium: TextStyle(letterSpacing: 0)),
        ),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showAnchoredAppSearchMenu<int>(
                  context: context,
                  anchorContext: context,
                  entries: entries,
                  initialValue: 64,
                  // השורה משוריינת לסימן הבחירה ב־4 פיקסלים יותר מחישוב הרוחב.
                  menuMinWidth:
                      calculateAppMenuPreferredWidth(metrics, entries) + 4,
                ),
                child: const Text('פתח'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('פתח'));
    await tester.pumpAndSettle();

    final paragraph = tester.renderObject<RenderParagraph>(find.text(widest));
    expect(paragraph.didExceedMaxLines, isFalse);
  });

  testWidgets('מדידת מנות מכסה כל תווית גם בכיוונים ושבירות שורה מעורבים', (
    tester,
  ) async {
    const labels = [
      'טקסט עִבְרִי עם ניקוד',
      'WWW office ffi',
      'קצר\nשורה שנייה ארוכה הרבה יותר מהראשונה',
      'CR\rשורה נוספת',
      'CRLF\r\nשורה נוספת',
      'LS\u2028שורה נוספת',
      'PS\u2029שורה נוספת',
      '\u202eoverride',
      '\u2067isolate',
      'רווחים בסוף     ',
      '\tטאב\tWWW',
      '🙂 👩‍❤️‍👨',
    ];
    final mixed = [
      for (var i = 0; i < 130; i++)
        AppMenuEntry<int>(value: i, label: '${labels[i % labels.length]} $i'),
    ];
    final style = TextStyle(
      fontFamily: 'Roboto',
      fontSize: metrics.fontSize,
      fontWeight: FontWeight.w600,
    );
    var exact = 0.0;
    for (final entry in mixed) {
      final painter = TextPainter(
        text: TextSpan(text: entry.label, style: style),
        textDirection: TextDirection.rtl,
        maxLines: 1,
      )..layout();
      exact = max(exact, painter.width);
      painter.dispose();
    }
    exact = max(
      metrics.menuMinWidth,
      exact + metrics.itemPadding.horizontal + metrics.iconSize + 4,
    );
    final width = calculateAppMenuPreferredWidth(metrics, mixed);

    expect(width, greaterThanOrEqualTo(exact));
    expect(width - exact, lessThanOrEqualTo(2));
  });
  testWidgets('תווית חריגה באורכה נמדדת בלי להשמיט את שכנותיה', (tester) async {
    final long = List.filled(5000, 'אW').join();
    final huge = [
      ...entries,
      AppMenuEntry<int>(value: 65, label: long),
    ];
    expect(
      calculateAppMenuPreferredWidth(metrics, huge),
      calculateAppMenuPreferredWidth(metrics, [huge.last]),
    );
  });
  testWidgets('ZWJ בתחילת תווית אינו מחבר אותה לפסקה הקודמת במדידה', (
    tester,
  ) async {
    const label = 'WWWWWWWWWWWWWWWWWWWW';
    const separate = [
      AppMenuEntry<int>(value: 1, label: label),
      AppMenuEntry<int>(value: 2, label: '\u200d$label'),
    ];
    expect(
      calculateAppMenuPreferredWidth(metrics, separate),
      max(
        calculateAppMenuPreferredWidth(metrics, [separate.first]),
        calculateAppMenuPreferredWidth(metrics, [separate.last]),
      ),
    );
  });
}
