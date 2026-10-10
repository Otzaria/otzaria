import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

  testWidgets(
    'SegmentedSettingsTile labels keep their size across selections',
    (
      tester,
    ) async {
      const labels = ['Follow Nekudos', 'Hide', 'Show'];

      Future<Map<String, Size>> labelSizes(String selected) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SettingsActionTile.segmentedTile<String>(
                rtlIcon: FluentIcons.panel_left_24_regular,
                title: 'Taamim',
                options: [
                  for (final label in labels)
                    SegmentOption(value: label, label: label),
                ],
                currentValue: selected,
                onChanged: (_) {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        return {
          for (final label in labels) label: tester.getSize(find.text(label)),
        };
      }

      final unselected = await labelSizes(labels.last);
      final selected = await labelSizes(labels.first);

      expect(selected, unselected);
      expect(find.byIcon(FluentIcons.checkmark_24_regular), findsNothing);
    },
  );

  testWidgets(
    'SegmentedSettingsTile wraps long labels instead of cutting them',
    (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(500, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      const labels = ['הצמדה', 'בפתיחת ספר', 'סגור'];

      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: SettingsActionTile.segmentedTile<String>(
                rtlIcon: FluentIcons.panel_left_24_regular,
                title: 'הצגת חלונית ניווט',
                options: [
                  for (final label in labels)
                    SegmentOption(value: label, label: label),
                ],
                currentValue: labels.first,
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      for (final label in labels) {
        final paragraph = tester.renderObject<RenderParagraph>(
          find.text(label),
        );
        expect(paragraph.didExceedMaxLines, isFalse, reason: label);
      }
      final lineHeight = tester.getSize(find.text('סגור')).height;
      expect(
        tester.getSize(find.text('בפתיחת ספר')).height,
        greaterThan(lineHeight * 1.5),
      );
    },
  );

  // issue #1920: in a wide row the control sat in the ListTile trailing,
  // which does not grow, so a wrapped label was cut at the row's bottom.
  testWidgets('a long label in a wide row stays inside the row', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1333, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const labels = ['Show', 'Hide', 'Follow Nekudos'];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              SettingsActionTile.segmentedTile<String>(
                rtlIcon: FluentIcons.panel_left_24_regular,
                title: 'Taamim',
                options: [
                  for (final label in labels)
                    SegmentOption(value: label, label: label),
                ],
                currentValue: labels.last,
                onChanged: (_) {},
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final row = tester.getRect(
      find
          .ancestor(
            of: find.byType(AppSegmentedControl<String>),
            matching: find.byType(LayoutBuilder),
          )
          .first,
    );
    final control = tester.getRect(find.byType(AppSegmentedControl<String>));
    expect(control.bottom, lessThanOrEqualTo(row.bottom));
    for (final label in labels) {
      final paragraph = tester.renderObject<RenderParagraph>(find.text(label));
      expect(paragraph.didExceedMaxLines, isFalse, reason: label);
      expect(
        tester.getRect(find.text(label)).bottom,
        lessThanOrEqualTo(row.bottom),
        reason: label,
      );
    }
  });
}
