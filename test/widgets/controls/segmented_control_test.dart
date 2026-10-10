import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/controls/segmented_control.dart';

void main() {
  Widget control({bool? showSelectedIcon}) => MaterialApp(
    home: Scaffold(
      body: showSelectedIcon == null
          ? AppSegmentedControl<int>(
              options: const [
                SegmentOption(value: 1, label: 'One'),
                SegmentOption(value: 2, label: 'Two'),
              ],
              currentValue: 1,
              onChanged: (_) {},
            )
          : AppSegmentedControl<int>(
              options: const [
                SegmentOption(value: 1, label: 'One'),
                SegmentOption(value: 2, label: 'Two'),
              ],
              currentValue: 1,
              onChanged: (_) {},
              showSelectedIcon: showSelectedIcon,
            ),
    ),
  );

  testWidgets('AppSegmentedControl hides the selected check icon by default', (
    tester,
  ) async {
    await tester.pumpWidget(control());

    expect(find.byIcon(FluentIcons.checkmark_24_regular), findsNothing);
    expect(find.byIcon(Icons.check), findsNothing);
  });

  testWidgets('AppSegmentedControl shows the check icon when asked to', (
    tester,
  ) async {
    await tester.pumpWidget(control(showSelectedIcon: true));

    expect(find.byIcon(FluentIcons.checkmark_24_regular), findsOneWidget);
  });

  testWidgets(
    'AppSegmentedControl shows a cut label in full on hover (#1862)',
    (tester) async {
      const labels = [
        'העמוד הנוכחי',
        'הפרשה',
        'הכל',
        'טווח עמודים',
        'טווח פסוקים',
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: SizedBox(
                width: 460,
                child: AppSegmentedControl<String>(
                  expandToFillWidth: true,
                  options: [
                    for (final label in labels)
                      SegmentOption(value: label, label: label),
                  ],
                  currentValue: labels[1],
                  onChanged: (_) {},
                ),
              ),
            ),
          ),
        ),
      );

      final cut = tester.renderObject<RenderParagraph>(
        find.text('טווח פסוקים'),
      );
      expect(cut.didExceedMaxLines, isTrue);
      for (final label in labels) {
        expect(find.byTooltip(label), findsOneWidget, reason: label);
      }
    },
  );
}
