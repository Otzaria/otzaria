import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/widgets/feedback/app_info_banner.dart';

import '../golden_harness.dart';

Widget _banners() => SizedBox(
  width: 420,
  child: Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 8,
      children: [
        for (final tone in AppInfoBannerTone.values)
          AppInfoBanner(
            tone: tone,
            icon: FluentIcons.info_24_regular,
            title: 'שים לב (${tone.name})',
            message: 'הספרייה תתעדכן בהפעלה הבאה',
          ),
        const AppInfoBanner(message: 'הודעה בלי כותרת ובלי אייקון'),
      ],
    ),
  ),
);

void main() {
  for (final brightness in Brightness.values) {
    goldenTest('AppInfoBanner: כל הגוונים, ${brightness.name}', (
      tester,
    ) async {
      await pumpGolden(tester, _banners(), brightness: brightness);
      await expectGolden('app_info_banner_tones.${brightness.name}');
    });
  }
}
