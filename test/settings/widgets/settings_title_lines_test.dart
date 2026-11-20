import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/settings/widgets/settings_card.dart';
import 'package:otzaria/widgets/controls/segmented_control.dart';

/// כותרת שורת הגדרה מקבלת עד שתי שורות (החלטת בעל הפרויקט, סבב ב' סעיף 31):
/// בחלון צר ועם הטקסט מוגדל פי 1.3 היא כבר לא נקטעת ב"...", ורק כותרת שלא
/// נכנסת גם בשתי שורות נקטעת, אחרי שתיים.
void main() {
  const shortTitle = 'הדגש פרשנים קשורים';
  final longTitle = List.filled(12, 'כותרת ארוכה מאוד').join(' ');

  Future<void> pumpTile(
    WidgetTester tester,
    Widget tile, {
    double textScale = 1.3,
  }) async {
    await tester.binding.setSurfaceSize(const Size(360, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: child!,
          ),
        ),
        home: Scaffold(body: SingleChildScrollView(child: tile)),
      ),
    );
    await tester.pumpAndSettle();
  }

  RenderParagraph paragraph(WidgetTester tester, String text) =>
      tester.renderObject<RenderParagraph>(find.text(text));

  final tiles = <String, Widget Function(String title)>{
    'SettingsSwitchTile': (title) =>
        SettingsSwitchTile(title: title, value: true, onChanged: (_) {}),
    'SettingsActionTile.text': (title) => SettingsActionTile.text(
      title: title,
      actions: const [Icon(Icons.chevron_left)],
      responsiveActions: false,
    ),
    'SettingsSegmentedTile': (title) => SettingsSegmentedTile<String>(
      title: title,
      options: const [
        SegmentOption(value: 'a', label: 'א'),
        SegmentOption(value: 'b', label: 'ב'),
      ],
      currentValue: 'a',
      onChanged: (_) {},
    ),
  };

  for (final entry in tiles.entries) {
    testWidgets('${entry.key}: כותרת שנכנסת בשתי שורות לא נקטעת', (
      tester,
    ) async {
      await pumpTile(tester, entry.value(shortTitle));

      final title = paragraph(tester, shortTitle);
      expect(title.maxLines, 2);
      expect(
        title.didExceedMaxLines,
        isFalse,
        reason: 'הכותרת "$shortTitle" נקטעה ב-1.3 בחלון של 360',
      );
    });

    testWidgets('${entry.key}: כותרת ארוכה מאוד נקטעת אחרי שתי שורות', (
      tester,
    ) async {
      await pumpTile(tester, entry.value(longTitle));

      final title = paragraph(tester, longTitle);
      expect(title.maxLines, 2);
      expect(title.didExceedMaxLines, isTrue);
    });
  }
}
