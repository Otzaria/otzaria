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

  testWidgets('AppSegmentedControl uses a custom tooltip and a label key', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppSegmentedControl<int>(
            options: const [
              SegmentOption(value: 1, label: 'One', tooltip: 'First option'),
              SegmentOption(
                value: 2,
                label: 'Two',
                labelKey: ValueKey('second'),
              ),
            ],
            currentValue: 1,
            onChanged: (_) {},
          ),
        ),
      ),
    );

    expect(find.byTooltip('First option'), findsOneWidget);
    expect(find.byTooltip('One'), findsNothing);
    expect(find.byTooltip('Two'), findsOneWidget);
    expect(find.byKey(const ValueKey('second')), findsOneWidget);
  });

  // q12 Q8: בטלפון האייקונים לקחו את מקום התווית ("...מד").
  testWidgets('במקטע צר מ-96 בלי אייקונים ובתווית הקצרה, ברוחב רגיל לא', (
    tester,
  ) async {
    Widget at(double width) => MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            child: AppSegmentedControl<int>(
              expandToFillWidth: true,
              options: const [
                SegmentOption(
                  value: 1,
                  label: 'מדויק',
                  icon: FluentIcons.text_quote_24_regular,
                ),
                SegmentOption(
                  value: 2,
                  label: 'מתקדם',
                  icon: FluentIcons.search_24_regular,
                ),
                SegmentOption(
                  value: 3,
                  label: 'מקורב',
                  icon: FluentIcons.arrow_autofit_width_24_regular,
                ),
                SegmentOption(
                  value: 4,
                  label: 'חיפוש חכם',
                  shortLabel: 'חכם',
                  icon: FluentIcons.sparkle_24_regular,
                ),
              ],
              currentValue: 1,
              onChanged: (_) {},
            ),
          ),
        ),
      ),
    );

    await tester.pumpWidget(at(280));
    expect(find.byIcon(FluentIcons.search_24_regular), findsNothing);
    expect(find.text('מתקדם'), findsOneWidget);
    // במקטע צר התווית הקצרה, והמלאה ב-tooltip.
    expect(find.text('חכם'), findsOneWidget);
    expect(find.text('חיפוש חכם'), findsNothing);
    expect(find.byTooltip('חיפוש חכם'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(at(600));
    expect(find.byIcon(FluentIcons.search_24_regular), findsOneWidget);
    expect(find.text('חיפוש חכם'), findsOneWidget);
    expect(find.text('חכם'), findsNothing);
  });
}
