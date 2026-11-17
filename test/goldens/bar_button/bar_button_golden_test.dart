import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/widgets/controls/bar_button.dart';

import '../golden_harness.dart';

// BarButton.icon עם label לא נכלל: התווית נבנית ב־AnimatedDefaultTextStyle עם
// TextStyle חדש בלי fontFamily, ולכן ב־golden היא מצוירת בגופן הבדיקה
// (ריבועים, CI_ENFORCEMENT.md §5.4). זה ממצא פתוח ברכיב, לא בבדיקה.
Widget _variants() => Padding(
  padding: const EdgeInsets.all(16),
  child: Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    spacing: 12,
    children: [
      Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 8,
        children: [
          BarButton.icon(
            tooltip: 'חיפוש',
            icon: FluentIcons.search_24_regular,
            onPressed: () {},
          ),
          BarButton.icon(
            tooltip: 'מפרשים',
            icon: FluentIcons.panel_left_24_regular,
            selected: true,
            onPressed: () {},
          ),
          const BarButton.icon(
            tooltip: 'הדפסה',
            icon: FluentIcons.print_24_regular,
            onPressed: null,
          ),
          BarButton.icon(
            tooltip: 'הקודם',
            icon: FluentIcons.chevron_left_24_regular,
            compact: true,
            onPressed: () {},
          ),
        ],
      ),
      Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 8,
        children: [
          BarButton.text(text: 'כניסה', onPressed: () {}),
          BarButton.text(
            text: 'הוספה',
            icon: FluentIcons.add_24_regular,
            onPressed: () {},
          ),
          const BarButton.text(text: 'לא זמין', onPressed: null),
        ],
      ),
    ],
  ),
);

void main() {
  for (final brightness in Brightness.values) {
    goldenTest('BarButton: כל הווריאנטים, ${brightness.name}', (tester) async {
      await pumpGolden(tester, _variants(), brightness: brightness);
      await expectGolden('bar_button_variants.${brightness.name}');
    });
  }
}
