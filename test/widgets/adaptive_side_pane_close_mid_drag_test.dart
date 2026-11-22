import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/layout/adaptive_side_pane.dart';
import 'package:otzaria/widgets/layout/resizable_drag_handle.dart';

// סגירת החלונית בעוד הידית נגררת מפרקת את הידית בלי onPanEnd. הדגל הפנימי
// של הגרירה חייב להתאפס, אחרת הפריסה קפואה על מצב תחילת הגרירה והסגירה
// והפתיחה האוטומטיות כבויות.

Widget _host({required bool open, void Function()? onResizeEnd}) => MaterialApp(
  home: Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(
      body: AdaptiveSidePane(
        isOpen: open,
        paneWidth: 300,
        minMainContentWidth: 420,
        isResizable: true,
        onPaneWidthChanged: (_) {},
        onPaneResizeEnd: onResizeEnd,
        onClose: () {},
        mainContent: const SizedBox.expand(key: Key('main')),
        paneContent: const SizedBox.expand(key: Key('pane')),
      ),
    ),
  ),
);

void main() {
  testWidgets('סגירה באמצע גרירה: אחרי שחרור ופתיחה מחדש החלונית הופכת לשכבה '
      'בחלון צר', (tester) async {
    tester.view.physicalSize = const Size(1000, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_host(open: true));
    await tester.pumpAndSettle();

    final center = tester.getCenter(find.byType(ResizableDragHandle));
    final gesture = await tester.startGesture(center);
    await gesture.moveBy(const Offset(-20, 0));
    await tester.pump();

    // ההורה סוגר בעוד הלחצן לחוץ: הידית מוסרת מהעץ בלי onPanEnd.
    await tester.pumpWidget(_host(open: false));
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.up();
    await tester.pumpWidget(_host(open: true));
    await tester.pumpAndSettle();

    // חלון צר: צפויה שכבה מעל התוכן (התוכן הראשי ברוחב החלון כולו), לא דחיקה.
    tester.view.physicalSize = const Size(500, 600);
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byKey(const Key('main'))).width, 500);
  });

  testWidgets('סגירה באמצע גרירה נשמרת כסיום גרירה (onPaneResizeEnd)', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var resizeEnds = 0;

    await tester.pumpWidget(_host(open: true, onResizeEnd: () => resizeEnds++));
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(ResizableDragHandle)),
    );
    await gesture.moveBy(const Offset(-20, 0));
    await tester.pump();
    expect(resizeEnds, 0);

    await tester.pumpWidget(
      _host(open: false, onResizeEnd: () => resizeEnds++),
    );
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(resizeEnds, 1);
  });
}
