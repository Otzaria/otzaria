import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/layout/adaptive_side_pane.dart';
import 'package:otzaria/widgets/navigation/nav_side_panel.dart';

const _contentKey = ValueKey('content');
const _paneKey = ValueKey('pane');

class _Harness extends StatefulWidget {
  const _Harness({required this.peek, this.onContentPointerDown});

  final NavPanelPeekController peek;
  final VoidCallback? onContentPointerDown;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  bool isOpen = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: NavPanelToggleButton(
            isOpen: isOpen,
            peek: widget.peek,
            onToggle: () => setState(() => isOpen = !isOpen),
          ),
        ),
        Expanded(
          child: NavSidePanel(
            isOpen: isOpen,
            peek: widget.peek,
            paneWidth: 300,
            minMainContentWidth: 500,
            onClose: () => setState(() => isOpen = false),
            paneContent: const SizedBox.expand(key: _paneKey),
            mainContent: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (_) => widget.onContentPointerDown?.call(),
              child: const SizedBox.expand(key: _contentKey),
            ),
          ),
        ),
      ],
    );
  }
}

void main() {
  late NavPanelPeekController peek;
  late TestGesture mouse;
  late int contentPointerDowns;

  Future<void> pump(WidgetTester tester) async {
    contentPointerDowns = 0;
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    peek = NavPanelPeekController();
    addTearDown(peek.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: _Harness(
            peek: peek,
            onContentPointerDown: () => contentPointerDowns++,
          ),
        ),
      ),
    );
    mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(10, 700));
    addTearDown(mouse.removePointer);
  }

  AdaptiveSidePane pane(WidgetTester tester) =>
      tester.widget<AdaptiveSidePane>(find.byType(AdaptiveSidePane));

  double contentWidth(WidgetTester tester) =>
      tester.getSize(find.byKey(_contentKey)).width;

  Offset button(WidgetTester tester) =>
      tester.getCenter(find.byType(NavPanelToggleButton));

  Future<void> hoverButton(WidgetTester tester) async {
    await mouse.moveTo(button(tester));
    await tester.pump(NavPanelPeekController.openDelay);
    await tester.pumpAndSettle();
  }

  testWidgets('ריחוף על הכפתור פותח מעל התוכן, בלי הצללה ובלי לצמצם אותו', (
    tester,
  ) async {
    await pump(tester);
    final fullWidth = contentWidth(tester);

    await hoverButton(tester);

    expect(pane(tester).isOpen, isTrue);
    expect(pane(tester).floatOverContent, isTrue);
    expect(pane(tester).showScrim, isFalse);
    expect(contentWidth(tester), fullWidth);
  });

  testWidgets('מעבר קצר על הכפתור לא פותח', (tester) async {
    await pump(tester);
    await mouse.moveTo(button(tester));
    await tester.pump(const Duration(milliseconds: 50));
    await mouse.moveTo(const Offset(10, 700));
    await tester.pumpAndSettle();

    expect(pane(tester).isOpen, isFalse);
  });

  testWidgets('נשאר פתוח כשהעכבר עובר לחלונית, ונסגר רק ביציאה ממנה', (
    tester,
  ) async {
    await pump(tester);
    await hoverButton(tester);

    await mouse.moveTo(tester.getCenter(find.byKey(_paneKey)));
    await tester.pump(NavPanelPeekController.buttonToPaneGrace * 2);
    expect(pane(tester).isOpen, isTrue);

    // יציאה מהחלונית סוגרת מיד, בלי השהיה.
    await mouse.moveTo(const Offset(10, 700));
    await tester.pump();
    expect(pane(tester).isOpen, isFalse);
    await tester.pump(const Duration(seconds: 1));
  });

  // אחרת לחיצה בשדה החיפוש מגיעה גם לספר, והוא לוקח ממנו את הפוקוס.
  testWidgets('לחיצה בחלונית בריחוף לא עוברת לתוכן שמתחתיה', (tester) async {
    await pump(tester);
    await hoverButton(tester);
    final inPane = tester.getCenter(find.byKey(_paneKey));
    await mouse.moveTo(inPane);
    await tester.pump();

    await mouse.down(inPane);
    await mouse.up();
    await tester.pump();

    expect(contentPointerDowns, 0);
    expect(peek.value, isTrue);
    await mouse.moveTo(const Offset(10, 700));
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('חזרה מהחלונית אל הכפתור לא סוגרת ופותחת שוב', (tester) async {
    await pump(tester);
    await hoverButton(tester);
    await mouse.moveTo(tester.getCenter(find.byKey(_paneKey)));
    await tester.pump();

    await mouse.moveTo(button(tester));
    await tester.pump();
    expect(peek.value, isTrue);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('תפריט שנפתח מתוך החלונית לא סוגר אותה', (tester) async {
    await pump(tester);
    await hoverButton(tester);
    await mouse.moveTo(tester.getCenter(find.byKey(_paneKey)));
    await tester.pump();

    final navigator = Navigator.of(tester.element(find.byKey(_paneKey)));
    unawaited(
      showGeneralDialog<void>(
        context: tester.element(find.byKey(_paneKey)),
        barrierDismissible: false,
        pageBuilder: (_, _, _) => const SizedBox(width: 10, height: 10),
      ),
    );
    await tester.pumpAndSettle();
    await mouse.moveBy(const Offset(1, 0));
    await tester.pump();
    expect(peek.value, isTrue);

    navigator.pop();
    await tester.pumpAndSettle();
    await mouse.moveTo(const Offset(10, 700));
    await tester.pump();
    expect(peek.value, isFalse);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('לחיצה על הכפתור פותחת חלונית שדוחקת את התוכן', (tester) async {
    await pump(tester);
    final fullWidth = contentWidth(tester);
    await hoverButton(tester);

    await tester.tap(find.byType(NavPanelToggleButton));
    await tester.pumpAndSettle();

    expect(peek.value, isFalse);
    expect(pane(tester).isOpen, isTrue);
    expect(pane(tester).floatOverContent, isFalse);
    expect(contentWidth(tester), lessThan(fullWidth));

    // יציאת העכבר לא סוגרת חלונית שנפתחה בלחיצה.
    await mouse.moveTo(const Offset(10, 700));
    await tester.pump(NavPanelPeekController.buttonToPaneGrace);
    await tester.pumpAndSettle();
    expect(pane(tester).isOpen, isTrue);

    // ריחוף על הכפתור כשהיא פתוחה לא משנה כלום, ולחיצה סוגרת.
    await hoverButton(tester);
    expect(peek.value, isFalse);
    await tester.tap(find.byType(NavPanelToggleButton));
    await tester.pumpAndSettle();
    expect(pane(tester).isOpen, isFalse);
    expect(contentWidth(tester), fullWidth);
  });
}
