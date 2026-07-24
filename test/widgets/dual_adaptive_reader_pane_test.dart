import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/layout/dual_adaptive_reader_pane.dart';

void main() {
  Widget buildPane({
    required double width,
    required bool showLeftPane,
    required bool showRightPane,
    required VoidCallback onCloseLeftPane,
    required VoidCallback onCloseRightPane,
  }) {
    return MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: SizedBox(
            width: width,
            height: 700,
            child: DualAdaptiveReaderPane(
              mainContent: const Center(child: Text('main')),
              showLeftPane: showLeftPane,
              leftPaneContent: const Center(child: Text('left pane')),
              leftPaneWidth: 220,
              leftMinPaneWidth: 180,
              onCloseLeftPane: onCloseLeftPane,
              showRightPane: showRightPane,
              rightPaneContent: const Center(child: Text('right pane')),
              rightPaneWidth: 240,
              rightMinPaneWidth: 180,
              onCloseRightPane: onCloseRightPane,
              minMainContentWidth: 500,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets(
    'DualAdaptiveReaderPane shows both panes side by side when wide',
    (tester) async {
      await tester.pumpWidget(
        buildPane(
          width: 1400,
          showLeftPane: true,
          showRightPane: true,
          onCloseLeftPane: () {},
          onCloseRightPane: () {},
        ),
      );

      expect(find.text('main'), findsOneWidget);
      expect(find.text('left pane'), findsOneWidget);
      expect(find.text('right pane'), findsOneWidget);
    },
  );

  testWidgets('DualAdaptiveReaderPane closes overlay pane on scrim tap', (
    tester,
  ) async {
    var leftPaneOpen = true;
    var closeCalled = false;

    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          return buildPane(
            width: 620,
            showLeftPane: leftPaneOpen,
            showRightPane: false,
            onCloseLeftPane: () {
              closeCalled = true;
              setState(() {
                leftPaneOpen = false;
              });
            },
            onCloseRightPane: () {},
          );
        },
      ),
    );

    expect(find.text('left pane'), findsOneWidget);

    await tester.tapAt(const Offset(320, 300));
    await tester.pumpAndSettle();

    // הלחיצה על ה-scrim מבקשת סגירה; החלונית מוחלקת החוצה (נשארת בעץ
    // לצורך אנימציית היציאה) ומפסיקה לקלוט מגע.
    expect(closeCalled, isTrue);
    expect(find.text('main'), findsOneWidget);
  });

  testWidgets('DualAdaptiveReaderPane animates wide pane out on close', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildPane(
        width: 1400,
        showLeftPane: true,
        showRightPane: false,
        onCloseLeftPane: () {},
        onCloseRightPane: () {},
      ),
    );
    expect(find.text('left pane'), findsOneWidget);

    // סגירה: רוחב החלונית מונפש ל-0, אך התוכן נשאר בעץ בזמן הכיווץ (לפני
    // התיקון הוא נעלם מיד ללא אנימציה).
    await tester.pumpWidget(
      buildPane(
        width: 1400,
        showLeftPane: false,
        showRightPane: false,
        onCloseLeftPane: () {},
        onCloseRightPane: () {},
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('left pane'), findsOneWidget);

    // בתום האנימציה החלונית מכווצת לרוחב 0 אך נשמרת בעץ (state preservation).
    await tester.pumpAndSettle();
    expect(find.text('main'), findsOneWidget);
  });
}
