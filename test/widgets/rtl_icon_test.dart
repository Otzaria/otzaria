import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/misc/rtl_icon.dart';

Widget _wrap(Widget child, {TextDirection dir = TextDirection.rtl}) =>
    MaterialApp(
      home: Directionality(textDirection: dir, child: child),
    );

void main() {
  group('RtlIcon — LTR context', () {
    testWidgets('מציג אייקון מקורי ללא שינוי', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const RtlIcon(FluentIcons.arrow_left_24_regular),
          dir: TextDirection.ltr,
        ),
      );

      final icon = tester.widget<Icon>(find.byType(Icon));
      expect(icon.icon, FluentIcons.arrow_left_24_regular);
      expect(find.byType(Transform), findsNothing, reason: 'LTR — אין להפוך');
    });
  });

  group('RtlIcon — RTL context, מירור מהמפה', () {
    testWidgets('arrow_left_24_regular מוחלף ב-arrow_right_24_regular', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(const RtlIcon(FluentIcons.arrow_left_24_regular)),
      );

      final icon = tester.widget<Icon>(find.byType(Icon));
      expect(
        icon.icon,
        FluentIcons.arrow_right_24_regular,
        reason: 'arrow_left הוא כיווני — חייב להתחלף ב-RTL',
      );
    });

    testWidgets('chevron_right_24_regular מוחלף ב-chevron_left_24_regular', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(const RtlIcon(FluentIcons.chevron_right_24_regular)),
      );

      final icon = tester.widget<Icon>(find.byType(Icon));
      expect(icon.icon, FluentIcons.chevron_left_24_regular);
    });
  });

  group('RtlIcon — RTL context, היפוך גאומטרי (_flippableIcons)', () {
    testWidgets('book_24_regular מתהפך עם Transform.flip', (tester) async {
      await tester.pumpWidget(
        _wrap(const RtlIcon(FluentIcons.book_24_regular)),
      );

      expect(
        find.byType(Transform),
        findsOneWidget,
        reason: 'ספר אין לו גרסת RTL בספריה — חייב להתהפך גאומטרית',
      );
      final icon = tester.widget<Icon>(find.byType(Icon));
      expect(
        icon.icon,
        FluentIcons.book_24_regular,
        reason: 'האייקון עצמו לא מוחלף — רק עטוף ב-Transform',
      );
    });

    testWidgets('text_align_distributed_24_regular מתהפך', (tester) async {
      await tester.pumpWidget(
        _wrap(const RtlIcon(FluentIcons.text_align_distributed_24_regular)),
      );

      expect(find.byType(Transform), findsOneWidget);
    });
  });

  group('RtlIcon — RTL context, אייקון סימטרי', () {
    testWidgets('search_24_regular לא מוחלף ולא מתהפך', (tester) async {
      await tester.pumpWidget(
        _wrap(const RtlIcon(FluentIcons.search_24_regular)),
      );

      expect(
        find.byType(Transform),
        findsNothing,
        reason: 'חיפוש סימטרי — אין לגעת בו',
      );
      final icon = tester.widget<Icon>(find.byType(Icon));
      expect(icon.icon, FluentIcons.search_24_regular);
    });

    testWidgets('settings_24_regular לא מוחלף ולא מתהפך', (tester) async {
      await tester.pumpWidget(
        _wrap(const RtlIcon(FluentIcons.settings_24_regular)),
      );

      expect(find.byType(Transform), findsNothing);
      final icon = tester.widget<Icon>(find.byType(Icon));
      expect(icon.icon, FluentIcons.settings_24_regular);
    });
  });

  group('RtlIcon — regression: אין mirrorIcon', () {
    test('RtlIcon לא מקבל פרמטר mirrorIcon', () {
      // אם הקוד מתקמפל — אין mirrorIcon. הבדיקה מוודאת שה-API לא חזר.
      const widget = RtlIcon(FluentIcons.book_24_regular);
      expect(widget, isA<RtlIcon>());
    });
  });
}
