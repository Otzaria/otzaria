import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/settings/widgets/settings_card.dart';
import 'package:otzaria/widgets/controls/segmented_control.dart';

void main() {
  testWidgets(
    'SegmentedSettingsTile remains stable on narrow width',
    (tester) async {
      String currentValue = 'closed';

      await tester.binding.setSurfaceSize(const Size(430, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) =>
                    SettingsActionTile.segmentedTile<String>(
                      rtlIcon: FluentIcons.panel_left_24_regular,
                      title: 'הצגת חלונית ניווט בכותרות ופרקים',
                      subtitle: 'בדיקת יציבות פריסה',
                      options: const [
                        SegmentOption(value: 'pinned', label: 'הצמדה'),
                        SegmentOption(value: 'openOnBook', label: 'בפתיחת ספר'),
                        SegmentOption(value: 'closed', label: 'סגור תמיד'),
                      ],
                      currentValue: currentValue,
                      onChanged: (value) =>
                          setState(() => currentValue = value),
                    ),
              ),
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

  testWidgets(
    'SegmentedSettingsTile supports keyboard selection in RTL',
    (tester) async {
      String currentValue = 'closed';

      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) =>
                    SettingsActionTile.segmentedTile<String>(
                      rtlIcon: FluentIcons.panel_left_24_regular,
                      title: 'כותרת',
                      subtitle: 'תיאור',
                      options: const [
                        SegmentOption(value: 'pinned', label: 'הצמדה'),
                        SegmentOption(value: 'openOnBook', label: 'בפתיחת ספר'),
                        SegmentOption(value: 'closed', label: 'סגור תמיד'),
                      ],
                      currentValue: currentValue,
                      onChanged: (value) =>
                          setState(() => currentValue = value),
                    ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // מאתר את ה-FocusNode הפנימי של _SegmentedTile לפי debugLabel
      final focusNode = tester
          .widgetList<Focus>(find.byType(Focus))
          .firstWhere((w) => w.focusNode?.debugLabel == 'segmented_tile')
          .focusNode!;

      focusNode.requestFocus();
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(currentValue, 'openOnBook');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('AppSegmentedControl can hide the selected check icon', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: AppSegmentedControl<String>(
              options: const [
                SegmentOption(value: 'book', label: 'ספר זה'),
                SegmentOption(value: 'workspace', label: 'שולחן עבודה זה'),
                SegmentOption(value: 'global', label: 'גלובלי'),
              ],
              currentValue: 'workspace',
              onChanged: (_) {},
              expandToFillWidth: true,
              showSelectedIcon: false,
              height: 40,
            ),
          ),
        ),
      ),
    );

    expect(find.byIcon(FluentIcons.checkmark_24_regular), findsNothing);
  });
}
