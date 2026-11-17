import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/widgets/controls/segmented_control.dart';

import '../golden_harness.dart';

Widget _controls() => Padding(
  padding: const EdgeInsets.all(16),
  child: Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    spacing: 12,
    children: [
      AppSegmentedControl<int>(
        options: const [
          SegmentOption(value: 0, label: 'הכל'),
          SegmentOption(value: 1, label: 'ספרים'),
          SegmentOption(value: 2, label: 'מפרשים'),
        ],
        currentValue: 1,
        onChanged: (_) {},
      ),
      AppSegmentedControl<int>(
        options: const [
          SegmentOption(
            value: 0,
            label: 'רשימה',
            icon: FluentIcons.list_24_regular,
          ),
          SegmentOption(
            value: 1,
            label: 'רשת',
            icon: FluentIcons.grid_24_regular,
          ),
        ],
        currentValue: 0,
        showSelectedIcon: true,
        onChanged: (_) {},
      ),
      SizedBox(
        width: 360,
        child: AppSegmentedControl<int>(
          options: const [
            SegmentOption(value: 0, label: 'בהיר'),
            SegmentOption(value: 1, label: 'כהה'),
            SegmentOption(value: 2, label: 'מערכת'),
          ],
          currentValue: 2,
          expandToFillWidth: true,
          onChanged: (_) {},
        ),
      ),
    ],
  ),
);

void main() {
  for (final brightness in Brightness.values) {
    goldenTest('AppSegmentedControl: וריאנטים, ${brightness.name}', (
      tester,
    ) async {
      await pumpGolden(tester, _controls(), brightness: brightness);
      await expectGolden('segmented_control_variants.${brightness.name}');
    });
  }
}
