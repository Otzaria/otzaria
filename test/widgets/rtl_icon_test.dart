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
    testWidgets('chevron_double_left_20_regular מוחלף ב-chevron_double_right', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(const RtlIcon(FluentIcons.chevron_double_left_20_regular)),
      );

      final icon = tester.widget<Icon>(find.byType(Icon));
      expect(icon.icon, FluentIcons.chevron_double_right_20_regular);
    });
  });

  // הגליף בפועל: האייקון שמצויר, והאם Icon עצמו משקף אותו (matchTextDirection).
  group('RtlIcon — הגליף שמצויר בפועל', () {
    Future<({IconData icon, bool mirrored})> painted(
      WidgetTester tester,
      IconData icon,
      TextDirection dir,
    ) async {
      await tester.pumpWidget(_wrap(RtlIcon(icon), dir: dir));
      final drawn = tester.widget<Icon>(find.byType(Icon)).icon!;
      final flips = find.descendant(
        of: find.byType(Icon),
        matching: find.byType(Transform),
      );
      final ownFlip = flips.evaluate().isNotEmpty;
      return (icon: drawn, mirrored: ownFlip);
    }

    for (final (name, icon) in const [
      ('chevron_right_24', FluentIcons.chevron_right_24_regular),
      ('chevron_left_16', FluentIcons.chevron_left_16_regular),
      ('arrow_left_24', FluentIcons.arrow_left_24_regular),
      ('arrow_left_24_filled', FluentIcons.arrow_left_24_filled),
      ('arrow_next_24', FluentIcons.arrow_next_24_regular),
      ('text_align_right_24', FluentIcons.text_align_right_24_regular),
    ]) {
      testWidgets('$name (matchTextDirection): RTL הוא תמונת המראה של LTR', (
        tester,
      ) async {
        expect(icon.matchTextDirection, isTrue);
        final ltr = await painted(tester, icon, TextDirection.ltr);
        final rtl = await painted(tester, icon, TextDirection.rtl);
        expect(ltr, (icon: icon, mirrored: false));
        expect(
          rtl,
          (icon: icon, mirrored: true),
          reason: 'אותו גליף, משוקף פעם אחת — לא מוחלף וגם משוקף',
        );
      });
    }
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
