import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/widgets/controls/status_chip.dart';
import 'package:otzaria/widgets/layout/meta_chip.dart';

import '../golden_harness.dart';

Widget _chips() => SizedBox(
  width: 480,
  child: Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 12,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final tone in MetaChipTone.values)
              MetaChip(
                label: 'ראשונים · ${tone.name}',
                icon: FluentIcons.clock_24_regular,
                tone: tone,
              ),
            const MetaChip(label: 'קטן', size: MetaChipSize.small),
          ],
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 8,
          children: [
            StatusChip(
              icon: const Icon(FluentIcons.arrow_download_24_regular),
              label: 'עדכון זמין',
              tooltip: 'עדכון',
              onPressed: () {},
            ),
            const StatusChip(
              icon: Icon(FluentIcons.cloud_off_24_regular),
              label: 'לא מחובר',
              tooltip: 'חיבור',
              onPressed: null,
            ),
          ],
        ),
      ],
    ),
  ),
);

void main() {
  for (final brightness in Brightness.values) {
    goldenTest('MetaChip ו-StatusChip, ${brightness.name}', (tester) async {
      await pumpGolden(tester, _chips(), brightness: brightness);
      await expectGolden('chips.${brightness.name}');
    });
  }
}
