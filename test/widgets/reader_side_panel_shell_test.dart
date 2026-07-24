import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/layout/floating_panel.dart';
import 'package:otzaria/widgets/layout/reader_side_panel_shell.dart';

void main() {
  Widget buildShell(AlignmentDirectional alignment) {
    return MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: ReaderSidePanelShell(
            alignment: alignment,
            child: const SizedBox(width: 120, height: 80),
          ),
        ),
      ),
    );
  }

  testWidgets('ReaderSidePanelShell wraps content in FloatingPanel', (
    tester,
  ) async {
    await tester.pumpWidget(buildShell(AlignmentDirectional.centerStart));

    expect(find.byType(FloatingPanel), findsOneWidget);
  });

  testWidgets('ReaderSidePanelShell adds outer margin on right-side panes', (
    tester,
  ) async {
    await tester.pumpWidget(buildShell(AlignmentDirectional.centerStart));

    final padding = tester.widget<Padding>(
      find
          .ancestor(
            of: find.byType(FloatingPanel),
            matching: find.byType(Padding),
          )
          .first,
    );

    expect(
      padding.padding,
      const EdgeInsets.only(top: 12, bottom: 10, right: 10),
    );
  });

  testWidgets('ReaderSidePanelShell adds outer margin on left-side panes', (
    tester,
  ) async {
    await tester.pumpWidget(buildShell(AlignmentDirectional.centerEnd));

    final padding = tester.widget<Padding>(
      find
          .ancestor(
            of: find.byType(FloatingPanel),
            matching: find.byType(Padding),
          )
          .first,
    );

    expect(
      padding.padding,
      const EdgeInsets.only(top: 12, bottom: 10, left: 10),
    );
  });
}
