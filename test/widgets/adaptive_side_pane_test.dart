import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/theme/app_surfaces.dart';
import 'package:otzaria/widgets/layout/adaptive_side_pane.dart';
import 'package:otzaria/widgets/layout/floating_panel.dart';
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
  testWidgets('AdaptiveSidePane calls onPaneResizeEnd after dragging', (
    tester,
  ) async {
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

  testWidgets('onLayoutModeChanged מדווח push במסך רחב ו-overlay במסך צר', (
    tester,
  ) async {
    // ה-reanchor בטקסט צריך לרוץ רק כשהחלונית דוחקת את התוכן (push). בדיקה
    // שהדיווח מבחין בין רחב (push=true) לצר (overlay=false).
    late StateSetter setRootState;
    var containerWidth = 1200.0;
    final reported = <bool>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: StatefulBuilder(
            builder: (context, setState) {
              setRootState = setState;
              return Scaffold(
                body: Center(
                  child: SizedBox(
                    width: containerWidth,
                    height: 700,
                    child: AdaptiveSidePane(
                      isOpen: true,
                      alignment: AlignmentDirectional.centerEnd,
                      paneWidth: 300,
                      minMainContentWidth: 420,
                      onClose: () {},
                      mainContent: const SizedBox.expand(),
                      paneContent: const Text('pane'),
                      onLayoutModeChanged: reported.add,
                      autoHandleResponsiveVisibility: false,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(reported.last, isTrue);

    setRootState(() => containerWidth = 500);
    await tester.pumpAndSettle();

    expect(reported.last, isFalse);
  });

  testWidgets('AdaptiveSidePane preserves wide pane state across close/open', (
    tester,
  ) async {
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
                      paneContent: Builder(
                        builder: (context) {
                          paneBuildCount++;
                          return const Text('pane_marker');
                        },
                      ),
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
    },
  );

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
                      paneContent: Builder(
                        builder: (context) {
                          paneBuildCount++;
                          return const Text('pane_marker_narrow');
                        },
                      ),
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
    },
  );

  testWidgets('AdaptiveSidePane places overlay drag handle at pane edge', (
    tester,
  ) async {
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

    // handle ממוקם בקצה הפנימי של הפאנל, שמוזז _kNarrowSideGap (10) מהדופן,
    // וחודר פנימה רק kPaneHandleInnerReach (4) כדי לא לכסות את פס הגלילה
    // → right = 10 + 300 - 4 = 306 → dx = 500 - 306 = 194
    expect(tester.getTopRight(find.byType(ResizableDragHandle)).dx, 194.0);
  });

  // אזורי רגרסיה לאופטימיזציה של commit 4996fff (דחיית בנייה ראשונה של הפאנל)
  testWidgets('isOpen=true מ-initState בונה את הפאנל מיידית (לא נדחה)', (
    tester,
  ) async {
    // השדה _paneEverOpened מאותחל ל-widget.isOpen ב-initState. אם מישהו
    // ימחק את הקו הזה, הפאנל לא ייבנה בפתיחה הראשונה כשהוא נפתח כברירת מחדל.
    var paneBuildCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: SizedBox(
              width: 1200,
              height: 700,
              child: AdaptiveSidePane(
                isOpen: true, // פתוח כבר ב-initState
                alignment: AlignmentDirectional.centerEnd,
                paneWidth: 300,
                minMainContentWidth: 420,
                onClose: () {},
                mainContent: const SizedBox.expand(),
                paneContent: Builder(
                  builder: (context) {
                    paneBuildCount++;
                    return const Text('initial_pane');
                  },
                ),
                autoHandleResponsiveVisibility: false,
              ),
            ),
          ),
        ),
      ),
    );

    expect(paneBuildCount, greaterThan(0));
    expect(find.text('initial_pane'), findsOneWidget);
  });

  testWidgets('פתיחה→סגירה→פתיחה רב-פעמית שומרת state ולא מאפסת את הפאנל', (
    tester,
  ) async {
    // ממה שזה מגן: לוגיקה של "_paneEverOpened לא מתאפס לעולם". טסט קיים
    // בודק מחזור אחד; כאן מוודאים שגם 3+ מחזורים שומרים את ה-state ולא
    // מאפסים את ה-Counter.
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

    // 3 לחיצות → count=3
    await tester.tap(find.text('increment'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('increment'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('increment'));
    await tester.pumpAndSettle();
    expect(find.text('count: 3'), findsOneWidget);

    // שלושה מחזורים של סגירה ופתיחה — count חייב להישאר 3
    for (var i = 0; i < 3; i++) {
      setRootState(() => isOpen = false);
      await tester.pumpAndSettle();
      setRootState(() => isOpen = true);
      await tester.pumpAndSettle();
    }
    expect(find.text('count: 3'), findsOneWidget);
  });

  testWidgets('שינוי width לא בונה מחדש את paneContent אחרי שנפתח', (
    tester,
  ) async {
    // הגנה: paneContent ב-Builder לא צריך להיבנות מחדש כל פעם שה-parent
    // מעדכן את הרוחב. בנייה מחדש = איבוד state בילדים.
    late StateSetter setRootState;
    var width = 300.0;
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
                    isOpen: true,
                    alignment: AlignmentDirectional.centerEnd,
                    paneWidth: width,
                    minMainContentWidth: 420,
                    onClose: () {},
                    mainContent: const SizedBox.expand(),
                    paneContent: Builder(
                      builder: (context) {
                        paneBuildCount++;
                        return const Text('content');
                      },
                    ),
                    autoHandleResponsiveVisibility: false,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );

    final initialBuilds = paneBuildCount;
    expect(initialBuilds, greaterThan(0));

    // שינוי רוחב הפאנל — paneContent עצמו לא תלוי ברוחב
    setRootState(() => width = 350);
    await tester.pumpAndSettle();
    setRootState(() => width = 400);
    await tester.pumpAndSettle();

    // אסור שהרוחב יגרום לבנייה מחודשת רבה של ה-builder.
    // התרת רמת ביצועים סבירה (לא יותר מ-3 בנייות נוספות לשני שינויים).
    expect(
      paneBuildCount - initialBuilds,
      lessThanOrEqualTo(3),
      reason:
          'שינוי רוחב הפאנל לא אמור לבנות מחדש את paneContent — זה מאבד state בילדים',
    );
  });

  // ── בדיקות צבע רקע ──────────────────────────────────────────────────────────
  //
  // AdaptiveSidePane אחראי לצבע הרקע של החלונית דרך _buildPaneShell.
  // paneContent **לא** אמור להגדיר צבע רקע משלו (Material/Container עם color,
  // ColoredBox וכו') — אחרת הוא דורס את הצבע שמגיע מ-AdaptiveSidePane.
  //
  // החריג המותר: העברת paneColor מפורשת ל-AdaptiveSidePane עצמו (כמו ב-library_browser).

  Widget buildPaneWithColor({required Color paneContentColor}) {
    return MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: SizedBox(
            width: 1200,
            height: 700,
            child: AdaptiveSidePane(
              isOpen: true,
              alignment: AlignmentDirectional.centerEnd,
              paneWidth: 300,
              minMainContentWidth: 420,
              onClose: () {},
              mainContent: const SizedBox.expand(),
              // paneContent עם צבע רקע פנימי — זה הדפוס האסור
              paneContent: ColoredBox(
                color: paneContentColor,
                child: const SizedBox.expand(),
              ),
              autoHandleResponsiveVisibility: false,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets(
    'צבע הרקע של החלונית מגיע מ-AdaptiveSidePane ולא מ-paneContent (wide)',
    (tester) async {
      // בודק שה-FloatingPanel (שהוא _buildPaneShell במצב wide) מקבל את
      // AppSurfaces.solidPanelBackground ולא נדרס על ידי תוכן פנימי.
      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Builder(
              builder: (context) {
                final expectedColor = AppSurfaces.solidPanelBackground(context);
                return Scaffold(
                  body: SizedBox(
                    width: 1200,
                    height: 700,
                    child: AdaptiveSidePane(
                      isOpen: true,
                      alignment: AlignmentDirectional.centerEnd,
                      paneWidth: 300,
                      minMainContentWidth: 420,
                      onClose: () {},
                      mainContent: const SizedBox.expand(),
                      paneContent: Builder(
                        builder: (context) {
                          // מאמת שהצבע שמגיע ל-FloatingPanel תואם את ברירת המחדל
                          final panel = context
                              .findAncestorWidgetOfExactType<FloatingPanel>();
                          expect(
                            panel?.color,
                            expectedColor,
                            reason:
                                'FloatingPanel צריך לקבל את AppSurfaces.solidPanelBackground',
                          );
                          return const SizedBox.shrink();
                        },
                      ),
                      autoHandleResponsiveVisibility: false,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
    },
  );

  testWidgets('paneColor מפורש מועבר ל-FloatingPanel במקום ברירת המחדל (wide)', (
    tester,
  ) async {
    // זהו הדפוס המותר: העברת paneColor ל-AdaptiveSidePane עצמו (כמו library_browser).
    const customColor = Color(0xFFAABBCC);

    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: SizedBox(
              width: 1200,
              height: 700,
              child: AdaptiveSidePane(
                isOpen: true,
                alignment: AlignmentDirectional.centerEnd,
                paneWidth: 300,
                minMainContentWidth: 420,
                onClose: () {},
                mainContent: const SizedBox.expand(),
                paneContent: Builder(
                  builder: (context) {
                    final panel = context
                        .findAncestorWidgetOfExactType<FloatingPanel>();
                    expect(
                      panel?.color,
                      customColor,
                      reason:
                          'paneColor מפורש צריך להגיע ל-FloatingPanel כפי שהוגדר',
                    );
                    return const SizedBox.shrink();
                  },
                ),
                paneColor: customColor,
                autoHandleResponsiveVisibility: false,
              ),
            ),
          ),
        ),
      ),
    );
  });

  testWidgets(
    'paneContent עם ColoredBox ישיר מכיל ColoredBox בתוך FloatingPanel (רגרסיה: דריסת צבע)',
    (tester) async {
      // בודק את מבנה ה-widget tree: אם paneContent מכיל ColoredBox עם צבע,
      // הוא יופיע בתוך ה-FloatingPanel ויהיה נצפה ב-tree.
      // זה מתעד את ה-invariant: paneContent לא אמור להכיל ColoredBox/Material עם color.
      // אם יום אחד FloatingPanel יכלוא את הצבע — הטסט הזה יצביע על כך.

      await tester.pumpWidget(
        buildPaneWithColor(paneContentColor: Colors.red),
      );
      await tester.pumpAndSettle();

      expect(
        find.byType(FloatingPanel),
        findsOneWidget,
        reason:
            'AdaptiveSidePane חייב לעטוף את paneContent ב-FloatingPanel במצב wide',
      );

      // ColoredBox עם Colors.red אמור להיות בתוך ה-FloatingPanel —
      // זה מוכיח שהוא נמצא ב-tree ולא נחסם. אם הטסט יכשל כאן,
      // FloatingPanel מנע את הוספת ה-ColoredBox לעץ (שינוי ב-_buildPaneShell).
      final coloredBoxFinder = find.descendant(
        of: find.byType(FloatingPanel),
        matching: find.byType(ColoredBox),
      );
      expect(
        coloredBoxFinder,
        findsOneWidget,
        reason:
            'ColoredBox בתוך paneContent צריך להיות נצפה בתוך FloatingPanel — '
            'הוא דורס את הצבע שהוגדר ב-AdaptiveSidePane',
      );

      // מוודא שהצבע של ה-ColoredBox הפנימי שונה מהצבע שהוגדר ב-FloatingPanel —
      // זו הוכחה שיש סתירה בין הצבע הפנימי לצבע שמגיע מ-AdaptiveSidePane.
      final coloredBox = tester.widget<ColoredBox>(coloredBoxFinder);
      final floatingPanel = tester.widget<FloatingPanel>(
        find.byType(FloatingPanel),
      );
      expect(
        coloredBox.color,
        isNot(equals(floatingPanel.color)),
        reason:
            'הצבע של ColoredBox הפנימי שונה מצבע FloatingPanel — '
            'זו ראיה לדריסה ויזואלית אסורה',
      );
    },
  );

  // ── מיקום פס הגלילה בקצה החיצוני ─────────────────────────────────────────
  //
  // רגרסיה: ידית הגרירה (ResizableDragHandle) יושבת בקצה הפנימי של הפאנל.
  // אם פס הגלילה נשאר בקצה ה-trailing הרגיל (אותו צד ב-RTL) הידית חוסמת את
  // הלחיצה עליו. AdaptiveSidePane חייב לדחוף את הפס לקצה החיצוני (הצמוד לדופן
  // החלון), בצד הנגדי לידית.

  Widget buildScrollablePane({required AlignmentDirectional alignment}) {
    return MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: SizedBox(
            width: 1200,
            height: 700,
            child: AdaptiveSidePane(
              isOpen: true,
              alignment: alignment,
              paneWidth: 300,
              minMainContentWidth: 420,
              onClose: () {},
              mainContent: const SizedBox.expand(),
              paneContent: ListView(
                children: List.generate(
                  50,
                  (i) => SizedBox(height: 40, child: Text('item $i')),
                ),
              ),
              isResizable: true,
              onPaneWidthChanged: (_) {},
              autoHandleResponsiveVisibility: false,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('פאנל בצד ימין (centerEnd): פס הגלילה בקצה החיצוני (ימין)', (
    tester,
  ) async {
    // הפס נבנה דרך ScrollBehavior שמוסיף Scrollbar רק בדסקטופ — כופים פלטפורמה.
    // try/finally מבטיח איפוס גם אם pumpWidget/pumpAndSettle/expect יזרקו: כך
    // ה-override לא דולף, ולא נוצרת שגיאה משנית שמסתירה את הכשל האמיתי. (אסור
    // להשתמש כאן ב-addTearDown — הוא רץ אחרי בדיקת ה-invariant של foundation.)
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await tester.pumpWidget(
        buildScrollablePane(alignment: AlignmentDirectional.centerEnd),
      );
      await tester.pumpAndSettle();

      final scrollbar = tester.widget<Scrollbar>(find.byType(Scrollbar));
      expect(scrollbar.scrollbarOrientation, ScrollbarOrientation.right);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('פאנל בצד שמאל (centerStart): פס הגלילה בקצה החיצוני (שמאל)', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await tester.pumpWidget(
        buildScrollablePane(alignment: AlignmentDirectional.centerStart),
      );
      await tester.pumpAndSettle();

      final scrollbar = tester.widget<Scrollbar>(find.byType(Scrollbar));
      expect(scrollbar.scrollbarOrientation, ScrollbarOrientation.left);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  // ── שוליים במצב צף (narrow) ───────────────────────────────────────────────

  Widget buildNarrowPane({required double containerWidth}) {
    return MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: Center(
            child: SizedBox(
              width: containerWidth,
              height: 600,
              child: AdaptiveSidePane(
                isOpen: true,
                alignment: AlignmentDirectional.centerEnd,
                paneWidth: 300,
                minMainContentWidth: 420,
                onClose: () {},
                mainContent: const SizedBox.expand(),
                paneContent: const Text('pane'),
                autoHandleResponsiveVisibility: false,
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('מצב צף: הפאנל מוזז מהדופן ומשאיר שוליים חיצוניים', (
    tester,
  ) async {
    await tester.pumpWidget(buildNarrowPane(containerWidth: 500));
    await tester.pumpAndSettle();

    final containerRect = tester.getRect(find.byType(AdaptiveSidePane));
    final paneRect = tester.getRect(find.byType(FloatingPanel));

    // centerEnd → הפאנל בימין; שוליים חיצוניים (ימין) של 10px
    expect(containerRect.right - paneRect.right, closeTo(10, 0.5));
    // הרוחב לא צומצם (300 < 500-20)
    expect(paneRect.width, closeTo(300, 0.5));
  });

  testWidgets('מצב צף: בחלון צר מאוד הרוחב מצומצם ונשמרים שוליים משני הצדדים', (
    tester,
  ) async {
    await tester.pumpWidget(buildNarrowPane(containerWidth: 250));
    await tester.pumpAndSettle();

    final containerRect = tester.getRect(find.byType(AdaptiveSidePane));
    final paneRect = tester.getRect(find.byType(FloatingPanel));

    // 250 - 10*2 = 230 → הרוחב מצומצם לרוחב הזמין
    expect(paneRect.width, closeTo(230, 0.5));
    expect(paneRect.left - containerRect.left, closeTo(10, 0.5));
    expect(containerRect.right - paneRect.right, closeTo(10, 0.5));
  });
}
