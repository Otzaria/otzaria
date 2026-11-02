import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';

import '../golden_harness.dart';

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
          ActionButton.recommended(text: 'שמירה', onPressed: () {}),
          ActionButton.neutral(text: 'ביטול', onPressed: () {}),
          ActionButton.ghost(text: 'דלג', onPressed: () {}),
          ActionButton.warning(text: 'מחיקה', onPressed: () {}),
        ],
      ),
      Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 8,
        children: [
          ActionButton.recommended(
            text: 'הוספה',
            icon: FluentIcons.add_24_regular,
            onPressed: () {},
          ),
          ActionButton.neutral(
            text: 'בטל התראה',
            errorText: true,
            onPressed: () {},
          ),
          const ActionButton.recommended(text: 'לא זמין', onPressed: null),
          const ActionButton.neutral(text: 'לא זמין', onPressed: null),
        ],
      ),
    ],
  ),
);

void main() {
  for (final brightness in Brightness.values) {
    goldenTest('ActionButton: כל הווריאנטים, ${brightness.name}', (
      tester,
    ) async {
      await pumpGolden(tester, _variants(), brightness: brightness);
      await expectGolden('action_button_variants.${brightness.name}');
    });
  }
}
