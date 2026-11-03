import 'dart:io';
import 'dart:ui' as ui;

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';

import '../golden_harness.dart';

Widget _variants({
  EdgeInsetsGeometry padding = const EdgeInsets.all(16),
}) => Padding(
  padding: padding,
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

  // הסף (0.05%, DD-22) תופס שינוי ריפוד של פיקסל אחד.
  // התוכן זז בפיקסל אחד בתוך אותו גודל, ולכן ההבדל הוא בפיקסלים ולא בגודל.
  goldenTest('הזזה של פיקסל אחד בריפוד חורגת מהסף ונכשלת', (tester) async {
    await pumpGolden(
      tester,
      _variants(padding: const EdgeInsetsDirectional.fromSTEB(17, 16, 15, 16)),
    );
    final result = await tester.runAsync(() async {
      final image = await captureImage(
        find.byKey(goldenBoundaryKey).evaluate().single,
      );
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      return GoldenFileComparator.compareLists(
        data!.buffer.asUint8List(),
        File(
          'test/goldens/action_button/goldens/action_button_variants.light.png',
        ).readAsBytesSync(),
      );
    });
    addTearDown(result!.dispose);
    expect(result.passed, isFalse);
    expect(result.diffPercent, greaterThan(goldenTolerance));
  });
}
