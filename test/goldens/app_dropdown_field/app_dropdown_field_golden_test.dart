import 'package:flutter/material.dart';
import 'package:otzaria/widgets/misc/app_dropdown_field.dart';
import 'package:otzaria/widgets/misc/app_popup_menu.dart';

import '../golden_harness.dart';

const _entries = [
  AppMenuEntry<String>(value: 'a', label: 'שולחן ערוך'),
  AppMenuEntry<String>(value: 'b', label: 'משנה ברורה'),
  AppMenuEntry<String>(
    value: 'long',
    label: 'ארבעה טורים, חלק אורח חיים, הלכות שבת ומועדים',
  ),
];

/// שלושה שדות בעמודה: עם ערך, בלי ערך (רמז), ומושבת.
Widget _fields(double width, {String selected = 'a'}) => SizedBox(
  width: width,
  child: Column(
    mainAxisSize: MainAxisSize.min,
    spacing: 16,
    children: [
      AppDropdownField<String>(
        value: selected,
        entries: _entries,
        onSelected: (_) {},
        decoration: const InputDecoration(labelText: 'ספר'),
      ),
      AppDropdownField<String>(
        value: null,
        entries: _entries,
        onSelected: (_) {},
        decoration: const InputDecoration(
          labelText: 'ספר',
          hintText: 'בחירת ספר',
        ),
      ),
      AppDropdownField<String>(
        value: selected,
        entries: _entries,
        onSelected: null,
        decoration: const InputDecoration(labelText: 'ספר (מושבת)'),
      ),
    ],
  ),
);

void main() {
  for (final brightness in Brightness.values) {
    goldenTest('AppDropdownField, מצבים, ${brightness.name}', (tester) async {
      await pumpGolden(
        tester,
        _fields(320),
        brightness: brightness,
        size: const Size(420, 320),
      );
      await expectGolden('app_dropdown_field.${brightness.name}');
    });
  }

  goldenTest('AppDropdownField, חלון צר וערך ארוך, light', (tester) async {
    await pumpGolden(
      tester,
      _fields(200, selected: 'long'),
      size: const Size(280, 320),
    );
    await expectGolden('app_dropdown_field_narrow_long.light');
  });
}
