import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/theme/layout_tokens.dart';
import 'package:otzaria/widgets/dialogs/app_dialog_header.dart';

void main() {
  group('WindowClass', () {
    test('fromWidth: הגבולות של LayoutBreakpoints שייכים לסוג הבא', () {
      expect(WindowClass.fromWidth(599.9), WindowClass.compact);
      expect(WindowClass.fromWidth(600), WindowClass.medium);
      expect(WindowClass.fromWidth(839.9), WindowClass.medium);
      expect(WindowClass.fromWidth(840), WindowClass.expanded);
      expect(WindowClass.fromWidth(1199.9), WindowClass.expanded);
      expect(WindowClass.fromWidth(1200), WindowClass.large);
    });

    testWidgets('of: לפי רוחב החלון', (tester) async {
      tester.view.physicalSize = const Size(560, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      late WindowClass windowClass;
      await tester.pumpWidget(
        Builder(
          builder: (context) {
            windowClass = WindowClass.of(context);
            return const SizedBox();
          },
        ),
      );
      expect(windowClass, WindowClass.compact);
      expect(windowClass.isCompact, isTrue);
    });

    // q12 Q8: בחלון נמוך הגובה הוא האילוץ — עמודה בצד ולא סרגל תחתון.
    for (final (size, short, side) in [
      (const Size(360, 640), false, false),
      (const Size(320, 568), false, false),
      (const Size(568, 320), true, true),
      (const Size(640, 360), true, true),
      (const Size(1024, 600), false, true),
      (const Size(420, 479), true, true),
      (const Size(420, 480), false, false),
    ]) {
      testWidgets(
        'חלון ${size.width.toInt()}×${size.height.toInt()}: '
        'נמוך=$short, ניווט בצד=$side',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          late bool isShort, usesSide;
          await tester.pumpWidget(
            Builder(
              builder: (context) {
                isShort = WindowClass.isShortOf(context);
                usesSide = WindowClass.usesSideNavigationOf(context);
                return const SizedBox();
              },
            ),
          );
          expect(isShort, short);
          expect(usesSide, side);
        },
      );
    }
  });

  // DD-15: סף "דיאלוג צר" הוא LayoutBreakpoints.compact (600), לא 520.
  group('AppDialogHeader — trailing לפי סוג החלון', () {
    Future<bool> stacked(WidgetTester tester, double width) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        const MaterialApp(
          home: Material(
            child: AppDialogHeader(title: 'כותרת', trailing: Text('12')),
          ),
        ),
      );
      final title = tester.getRect(find.text('כותרת'));
      final trailing = tester.getRect(find.text('12'));
      return trailing.top >= title.bottom;
    }

    testWidgets('ב-560 ה-trailing יורד לשורה משלו', (tester) async {
      expect(await stacked(tester, 560), isTrue);
    });

    testWidgets('ב-600 ה-trailing נשאר בשורת הכותרת', (tester) async {
      expect(await stacked(tester, 600), isFalse);
    });
  });
}
