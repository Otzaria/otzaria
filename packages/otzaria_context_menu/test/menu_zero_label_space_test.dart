import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria_context_menu/otzaria_context_menu.dart';

MenuPresentation _presentation() => MenuPresentation(
  metrics: AppMenuMetrics.create(compactMenus: false),
  borderRadius: BorderRadius.circular(8),
  iconBuilder: (context, icon, size, color, mirrorForRtl) =>
      SizedBox.square(dimension: size),
  selectedMarkBuilder: (context, size, color) => const Text('✓'),
  submenuArrowBuilder: (context, openToRight, size, color) =>
      Text(openToRight ? '›' : '‹'),
  downArrowBuilder: (context, size, color) => const Text('⌄'),
);

void main() {
  final metrics = AppMenuMetrics.create(compactMenus: false);

  test('a bounded menu always constrains its text label', () {
    final minimumSlots = metrics.itemPadding.horizontal + metrics.iconSize + 8;
    for (final width in [0.0, 1.0, minimumSlots - 1, minimumSlots]) {
      expect(
        calculateAppMenuLabelMaxWidth(
          metrics,
          maxWidth: width,
          hasLeadingIcon: true,
          hasTrailingWidget: false,
        ),
        0,
      );
    }
    expect(
      calculateAppMenuLabelMaxWidth(
        metrics,
        maxWidth: null,
        hasLeadingIcon: true,
        hasTrailingWidget: false,
      ),
      isNull,
      reason: 'An unbounded menu retains the existing intrinsic width',
    );
  });

  testWidgets('long labels cannot grow beyond the remaining menu space', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 150,
              child: Builder(
                builder: (context) => buildAppMenuRowContent(
                  context,
                  metrics,
                  presentation: _presentation(),
                  maxWidth: 40,
                  icon: Icons.content_copy,
                  label: 'An intentionally long label that must not overflow',
                ),
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.textContaining('An intentionally long label'), findsOneWidget);
  });
}
