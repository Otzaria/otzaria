import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/widgets/controls/bar_button.dart';
import 'package:otzaria/widgets/navigation/app_top_bar.dart';

import '../golden_harness.dart';

Widget _bar() => SizedBox(
  width: 720,
  child: AppTopBar(
    leadingItems: [
      AppTopBarItem(
        widget: BarButton.icon(
          tooltip: 'חזרה',
          icon: FluentIcons.arrow_right_24_regular,
          onPressed: () {},
        ),
      ),
      AppTopBarItem(
        widget: BarButton.icon(
          tooltip: 'מפרשים',
          icon: FluentIcons.panel_left_24_regular,
          selected: true,
          onPressed: () {},
        ),
      ),
    ],
    center: const Text('בראשית א, א'),
    trailingItems: [
      AppTopBarItem(
        widget: BarButton.icon(
          tooltip: 'חיפוש',
          icon: FluentIcons.search_24_regular,
          onPressed: () {},
        ),
      ),
      AppTopBarItem(
        dividerBefore: true,
        widget: BarButton.icon(
          tooltip: 'הדפסה',
          icon: FluentIcons.print_24_regular,
          onPressed: () {},
        ),
      ),
    ],
  ),
);

void main() {
  for (final brightness in Brightness.values) {
    goldenTest('AppTopBar: התחלה, מרכז וסוף, ${brightness.name}', (
      tester,
    ) async {
      await pumpGolden(tester, _bar(), brightness: brightness);
      await expectGolden('app_top_bar.${brightness.name}');
    });
  }
}
