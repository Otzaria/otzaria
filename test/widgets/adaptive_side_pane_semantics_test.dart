// issue #3336: צומת סמנטי של AdaptiveSidePane מעל התוכן נוצר ומתמזג לפי התוכן,
// וגשר הנגישות של Windows קורס על ה-reparent המקונן שזה גורם (flutter#175041).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/layout/adaptive_side_pane.dart';

import '../helpers/semantics_update_recorder.dart';

void main() {
  SemanticsRecordingBinding.ensure();
  final recorder = SemanticsRecordingBinding.recorder;

  Widget host({required bool float}) => MaterialApp(
    home: Scaffold(
      body: Column(
        children: [
          const Text('toolbar'),
          Expanded(
            child: AdaptiveSidePane(
              isOpen: true,
              alignment: AlignmentDirectional.centerEnd,
              paneWidth: 300,
              minMainContentWidth: 420,
              onClose: () {},
              floatOverContent: float,
              mainContent: const Text('main'),
              paneContent: const Column(
                children: [
                  Text('pane 0', textDirection: TextDirection.ltr),
                  Text('pane 1'),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );

  for (final float in [false, true]) {
    testWidgets(
      'החלונית אינה מוסיפה צומת סמנטי מעל התוכן (float=$float, issue #3336)',
      (tester) async {
        final handle = tester.ensureSemantics();
        await tester.pumpWidget(host(float: float));
        await tester.pumpAndSettle();

        final toolbar = tester.getSemantics(find.text('toolbar'));
        for (final text in ['pane 0', 'pane 1', 'main']) {
          final node = tester.getSemantics(find.text(text));
          expect(node.label, text, reason: 'לא מוזג לצומת משותף');
          expect(
            node.parent,
            same(toolbar.parent),
            reason: 'אין צומת ביניים מעל $text',
          );
        }
        handle.dispose();
      },
    );
  }

  // #5498: חלונית שנסגרה נשארת בעץ, וכל עדכון נגישות עבר על כל צאצאיה.
  testWidgets('חלונית סגורה אינה נסרקת לעץ הנגישות, ופתיחתה מחזירה אותה', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    recorder.reset();
    Widget pane({required bool open}) => MaterialApp(
      home: Scaffold(
        body: AdaptiveSidePane(
          isOpen: open,
          alignment: AlignmentDirectional.centerEnd,
          paneWidth: 300,
          minMainContentWidth: 300,
          onClose: () {},
          mainContent: const Text('main'),
          paneContent: Column(
            children: [for (var i = 0; i < 5; i++) Text('pane $i')],
          ),
        ),
      ),
    );
    bool visitedForSemantics(String text) {
      final target = tester.renderObject(find.text(text));
      bool reach(RenderObject node) {
        if (identical(node, target)) return true;
        var found = false;
        node.visitChildrenForSemantics(
          (child) => found = found || reach(child),
        );
        return found;
      }

      return reach(tester.binding.renderViews.first);
    }

    await tester.pumpWidget(pane(open: true));
    await tester.pumpAndSettle();
    expect(visitedForSemantics('pane 0'), isTrue);

    await tester.pumpWidget(pane(open: false));
    await tester.pumpAndSettle();
    expect(find.text('pane 0'), findsOneWidget, reason: 'התוכן נשמר בעץ');
    expect(visitedForSemantics('pane 0'), isFalse);
    expect(visitedForSemantics('main'), isTrue);

    await tester.pumpWidget(pane(open: true));
    await tester.pumpAndSettle();
    expect(tester.getSemantics(find.text('pane 0')).label, 'pane 0');
    expect(recorder.violations, isEmpty);
    handle.dispose();
  });
}
