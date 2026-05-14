import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/layout/adaptive_side_pane.dart';
import 'package:otzaria/widgets/layout/resizable_drag_handle.dart';

class _CounterPane extends StatefulWidget {
  const _CounterPane();

  @override
  State<_CounterPane> createState() => _CounterPaneState();
}

class _CounterPaneState extends State<_CounterPane> {
  int _count = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text('count: $_count'),
        TextButton(
          onPressed: () {
            setState(() {
              _count++;
            });
          },
          child: const Text('increment'),
        ),
      ],
    );
  }
}

void main() {
  testWidgets('AdaptiveSidePane calls onPaneResizeEnd after dragging',
      (tester) async {
    double paneWidth = 300;
    var resizeEnded = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: StatefulBuilder(
            builder: (context, setState) {
              return Scaffold(
                body: SizedBox(
                  width: 1200,
                  height: 700,
                  child: AdaptiveSidePane(
                    isOpen: true,
                    alignment: AlignmentDirectional.centerEnd,
                    paneWidth: paneWidth,
                    minMainContentWidth: 420,
                    onClose: () {},
                    mainContent: const SizedBox.expand(),
                    paneContent: const Text('pane'),
                    isResizable: true,
                    onPaneWidthChanged: (nextWidth) {
                      setState(() {
                        paneWidth = nextWidth;
                      });
                    },
                    onPaneResizeEnd: () {
                      resizeEnded = true;
                    },
                    autoHandleResponsiveVisibility: false,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );

    await tester.drag(find.byType(ResizableDragHandle), const Offset(-40, 0));
    await tester.pumpAndSettle();

    expect(resizeEnded, isTrue);
    expect(paneWidth, isNot(300));
  });

  testWidgets('AdaptiveSidePane preserves wide pane state across close/open',
      (tester) async {
    late StateSetter setRootState;
    var isOpen = true;

    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: StatefulBuilder(
            builder: (context, setState) {
              setRootState = setState;
              return Scaffold(
                body: SizedBox(
                  width: 1200,
                  height: 700,
                  child: AdaptiveSidePane(
                    isOpen: isOpen,
                    alignment: AlignmentDirectional.centerEnd,
                    paneWidth: 300,
                    minMainContentWidth: 420,
                    onClose: () {},
                    mainContent: const SizedBox.expand(),
                    paneContent: const _CounterPane(),
                    autoHandleResponsiveVisibility: false,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('increment'));
    await tester.pumpAndSettle();
    expect(find.text('count: 1'), findsOneWidget);

    setRootState(() {
      isOpen = false;
    });
    await tester.pumpAndSettle();

    setRootState(() {
      isOpen = true;
    });
    await tester.pumpAndSettle();

    expect(find.text('count: 1'), findsOneWidget);

    await tester.tap(find.text('increment'));
    await tester.pumpAndSettle();
    expect(find.text('count: 2'), findsOneWidget);
  });

  testWidgets(
      'AdaptiveSidePane does not build paneContent before first open (wide)',
      (tester) async {
    // אופטימיזציית ביצועים: paneContent כבד (TocViewer וכו') לא צריך להיבנות
    // לפני שהפאנל נפתח לראשונה - מונע frame builds של 12+ שניות בספרים גדולים.
    late StateSetter setRootState;
    var isOpen = false;
    var paneBuildCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: StatefulBuilder(
            builder: (context, setState) {
              setRootState = setState;
              return Scaffold(
                body: SizedBox(
                  width: 1200,
                  height: 700,
                  child: AdaptiveSidePane(
                    isOpen: isOpen,
                    alignment: AlignmentDirectional.centerEnd,
                    paneWidth: 300,
                    minMainContentWidth: 420,
                    onClose: () {},
                    mainContent: const SizedBox.expand(),
                    paneContent: Builder(builder: (context) {
                      paneBuildCount++;
                      return const Text('pane_marker');
                    }),
                    autoHandleResponsiveVisibility: false,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );

    // לפני פתיחה ראשונה - התוכן לא נבנה כלל
    expect(paneBuildCount, 0);
    expect(find.text('pane_marker'), findsNothing);

    // פתיחה ראשונה - התוכן נבנה ומופיע
    setRootState(() {
      isOpen = true;
    });
    await tester.pumpAndSettle();
    expect(paneBuildCount, greaterThan(0));
    expect(find.text('pane_marker'), findsOneWidget);

    // סגירה אחרי פתיחה - התוכן נשאר במגדל (לשמירת state)
    setRootState(() {
      isOpen = false;
    });
    await tester.pumpAndSettle();
    expect(find.text('pane_marker'), findsOneWidget);
  });

  testWidgets(
      'AdaptiveSidePane does not build paneContent before first open (narrow)',
      (tester) async {
    late StateSetter setRootState;
    var isOpen = false;
    var paneBuildCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: StatefulBuilder(
            builder: (context, setState) {
              setRootState = setState;
              return Scaffold(
                body: SizedBox(
                  width: 500,
                  height: 700,
                  child: AdaptiveSidePane(
                    isOpen: isOpen,
                    alignment: AlignmentDirectional.centerEnd,
                    paneWidth: 300,
                    minMainContentWidth: 420,
                    onClose: () {},
                    mainContent: const SizedBox.expand(),
                    paneContent: Builder(builder: (context) {
                      paneBuildCount++;
                      return const Text('pane_marker_narrow');
                    }),
                    autoHandleResponsiveVisibility: false,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );

    // לפני פתיחה ראשונה - התוכן לא נבנה גם במצב narrow
    expect(paneBuildCount, 0);
    expect(find.text('pane_marker_narrow'), findsNothing);

    // פתיחה - התוכן נבנה
    setRootState(() {
      isOpen = true;
    });
    await tester.pumpAndSettle();
    expect(paneBuildCount, greaterThan(0));
    expect(find.text('pane_marker_narrow'), findsOneWidget);
  });

  testWidgets('AdaptiveSidePane places overlay drag handle at pane edge',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: SizedBox(
              width: 500,
              height: 700,
              child: AdaptiveSidePane(
                isOpen: true,
                alignment: AlignmentDirectional.centerEnd,
                paneWidth: 300,
                minMainContentWidth: 420,
                onClose: () {},
                mainContent: const SizedBox.expand(),
                paneContent: const Text('pane'),
                isResizable: true,
                onPaneWidthChanged: (_) {},
                autoHandleResponsiveVisibility: false,
              ),
            ),
          ),
        ),
      ),
    );

    // handle ממוקם בקצה השמאלי של הפאנל (right: paneWidth - overhang)
    // → right edge dx = containerWidth - paneWidth + overhang = 500 - 300 + 12 = 212
    expect(tester.getTopRight(find.byType(ResizableDragHandle)).dx, 212.0);
  });
}
