import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/widgets/widgets_exports.dart';

void main() {
  testWidgets(
    'SegmentedSettingsTile remains stable on narrow width',
    (tester) async {
      String currentValue = 'closed';

      await tester.binding.setSurfaceSize(const Size(430, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SegmentedSettingsTile<String>(
              icon: FluentIcons.panel_left_24_regular,
              title: 'הצגת חלונית ניווט בכותרות ופרקים',
              subtitle: 'בדיקת יציבות פריסה',
              options: const [
                SegmentOption(value: 'pinned', label: 'הצמדה'),
                SegmentOption(value: 'openOnBook', label: 'בפתיחת ספר'),
                SegmentOption(value: 'closed', label: 'סגור תמיד'),
              ],
              currentValue: currentValue,
              onChanged: (value) => currentValue = value,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);

      await tester.tap(find.text('בפתיחת ספר'));
      await tester.pumpAndSettle();

      expect(currentValue, 'openOnBook');
      expect(tester.takeException(), isNull);
    },
  );
}
