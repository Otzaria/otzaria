import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/view/pane_drop_geometry.dart';
import 'package:otzaria/tabs/view/pane_drop_target.dart';

class _LeafTab extends OpenedTab {
  _LeafTab(super.title);

  @override
  Map<String, dynamic> toJson() => {'type': '_LeafTab', 'title': title};
}

/// תופס את הקריאות ל-onDrop של המטרה הנבדקת.
class _DropLog {
  OpenedTab? dropped;
  PaneDropSide? side;
  int count = 0;

  void record(OpenedTab tab, PaneDropSide droppedSide) {
    dropped = tab;
    side = droppedSide;
    count++;
  }
}

/// יעד ההפלה של אזור הקריאה: מתי הוא מקבל גרירה, לאיזה צד, ומה הוא מציג
/// תוך כדי.
void main() {
  const paneKey = Key('pane');
  const handleKey = Key('handle');

  Widget host({
    required _DropLog log,
    required OpenedTab dragged,
    OpenedTab? tab,
    TextDirection textDirection = TextDirection.rtl,
    double paneWidth = 800,
  }) {
    return MaterialApp(
      home: Directionality(
        textDirection: textDirection,
        child: Scaffold(
          body: Column(
            children: [
              Draggable<OpenedTab>(
                data: dragged,
                feedback: const SizedBox(
                  width: 40,
                  height: 20,
                  child: ColoredBox(color: Color(0xFF000000)),
                ),
                child: const SizedBox(
                  key: handleKey,
                  width: 40,
                  height: 20,
                  child: ColoredBox(color: Color(0xFF888888)),
                ),
              ),
              Expanded(
                child: Center(
                  child: SizedBox(
                    width: paneWidth,
                    child: PaneDropTarget(
                      key: paneKey,
                      tab: tab ?? _LeafTab('יעד'),
                      onDrop: log.record,
                      child: const ColoredBox(
                        color: Color(0xFFEEEEEE),
                        child: SizedBox.expand(),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// גוררת מהידית אל [target] ומשחררת שם.
  Future<void> dragTo(WidgetTester tester, Offset target) async {
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(handleKey)),
    );
    await tester.pump();
    await gesture.moveTo(target);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
  }

  /// גוררת מעל היעד בלי לשחרר, כדי לבדוק את החיווי.
  Future<TestGesture> hoverOver(WidgetTester tester, Offset target) async {
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(handleKey)),
    );
    await tester.pump();
    await gesture.moveTo(target);
    await tester.pump();
    return gesture;
  }

  Rect paneRect(WidgetTester tester) => tester.getRect(find.byKey(paneKey));

  group('בחירת הצד', () {
    testWidgets('שחרור בחצי הימני ב-RTL נותן את החלונית הראשונה', (
      tester,
    ) async {
      final log = _DropLog();
      final dragged = _LeafTab('נגרר');
      await tester.pumpWidget(host(log: log, dragged: dragged));

      final rect = paneRect(tester);
      await dragTo(tester, Offset(rect.right - 20, rect.center.dy));

      expect(log.count, 1);
      expect(log.dropped, same(dragged));
      expect(log.side, PaneDropSide.start);
    });

    testWidgets('שחרור בחצי השמאלי ב-RTL נותן את החלונית השנייה', (
      tester,
    ) async {
      final log = _DropLog();
      await tester.pumpWidget(host(log: log, dragged: _LeafTab('נגרר')));

      final rect = paneRect(tester);
      await dragTo(tester, Offset(rect.left + 20, rect.center.dy));

      expect(log.count, 1);
      expect(log.side, PaneDropSide.end);
    });

    testWidgets('גובה השחרור אינו משנה — אין יותר פיצול אנכי', (tester) async {
      final log = _DropLog();
      await tester.pumpWidget(host(log: log, dragged: _LeafTab('נגרר')));

      final rect = paneRect(tester);
      await dragTo(tester, Offset(rect.right - 20, rect.top + 8));

      expect(log.side, PaneDropSide.start);
    });

    testWidgets('ב-LTR הצדדים מתהפכים', (tester) async {
      final log = _DropLog();
      await tester.pumpWidget(
        host(
          log: log,
          dragged: _LeafTab('נגרר'),
          textDirection: TextDirection.ltr,
        ),
      );

      final rect = paneRect(tester);
      await dragTo(tester, Offset(rect.left + 20, rect.center.dy));

      expect(log.side, PaneDropSide.start);
    });
  });

  group('מתי ההפלה נדחית', () {
    testWidgets('טאב שכבר מפוצל אינו מקבל הפלות', (tester) async {
      final log = _DropLog();
      await tester.pumpWidget(
        host(
          log: log,
          dragged: _LeafTab('נגרר'),
          tab: CombinedTab(rightTab: _LeafTab('א'), leftTab: _LeafTab('ב')),
        ),
      );

      final rect = paneRect(tester);
      await dragTo(tester, rect.center);

      expect(log.count, 0);
    });

    testWidgets('גרירת טאב מפוצל אל טאב אחר נדחית', (tester) async {
      final log = _DropLog();
      await tester.pumpWidget(
        host(
          log: log,
          dragged: CombinedTab(
            rightTab: _LeafTab('א'),
            leftTab: _LeafTab('ב'),
          ),
        ),
      );

      final rect = paneRect(tester);
      await dragTo(tester, rect.center);

      expect(log.count, 0);
    });

    testWidgets('גרירת הטאב המוצג על עצמו נדחית', (tester) async {
      final log = _DropLog();
      final shown = _LeafTab('מוצג');
      await tester.pumpWidget(host(log: log, dragged: shown, tab: shown));

      final rect = paneRect(tester);
      await dragTo(tester, rect.center);

      expect(log.count, 0);
    });

    testWidgets('מסך צר מדי לשתי חלוניות קריאות אינו מתפצל', (tester) async {
      final log = _DropLog();
      await tester.pumpWidget(
        host(
          log: log,
          dragged: _LeafTab('נגרר'),
          paneWidth: kMinPaneExtent * 2 - 20,
        ),
      );

      final rect = paneRect(tester);
      await dragTo(tester, rect.center);

      expect(log.count, 0);
    });
  });

  group('חיווי', () {
    Finder preview() => find.descendant(
      of: find.byKey(paneKey),
      matching: find.byType(AnimatedPositioned),
    );

    testWidgets('אין חיווי לפני שגוררים', (tester) async {
      await tester.pumpWidget(
        host(log: _DropLog(), dragged: _LeafTab('נגרר')),
      );

      expect(preview(), findsNothing);
    });

    testWidgets('החיווי מופיע בגרירה ונעלם בשחרור', (tester) async {
      await tester.pumpWidget(
        host(log: _DropLog(), dragged: _LeafTab('נגרר')),
      );

      final rect = paneRect(tester);
      final gesture = await hoverOver(
        tester,
        Offset(rect.right - 20, rect.center.dy),
      );
      expect(preview(), findsOneWidget);

      await gesture.up();
      await tester.pumpAndSettle();
      expect(preview(), findsNothing);
    });

    testWidgets('החיווי תופס את החצי שאליו הספר ייכנס', (tester) async {
      await tester.pumpWidget(
        host(log: _DropLog(), dragged: _LeafTab('נגרר')),
      );

      final rect = paneRect(tester);
      final gesture = await hoverOver(
        tester,
        Offset(rect.right - 20, rect.center.dy),
      );
      await tester.pumpAndSettle();

      final previewRect = tester.getRect(preview());
      expect(previewRect.center.dx, greaterThan(rect.center.dx));
      expect(previewRect.width, closeTo(rect.width / 2, 1));

      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('החיווי עובר לצד השני בתנועת המצביע', (tester) async {
      await tester.pumpWidget(
        host(log: _DropLog(), dragged: _LeafTab('נגרר')),
      );

      final rect = paneRect(tester);
      final gesture = await hoverOver(
        tester,
        Offset(rect.right - 20, rect.center.dy),
      );
      await tester.pumpAndSettle();
      final rightSide = tester.getRect(preview()).center.dx;

      await gesture.moveTo(Offset(rect.left + 20, rect.center.dy));
      await tester.pumpAndSettle();

      expect(tester.getRect(preview()).center.dx, lessThan(rightSide));

      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('טאב מפוצל אינו מציג חיווי כלל', (tester) async {
      await tester.pumpWidget(
        host(
          log: _DropLog(),
          dragged: _LeafTab('נגרר'),
          tab: CombinedTab(rightTab: _LeafTab('א'), leftTab: _LeafTab('ב')),
        ),
      );

      final rect = paneRect(tester);
      final gesture = await hoverOver(tester, rect.center);
      await tester.pumpAndSettle();

      expect(preview(), findsNothing);

      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('יציאה מהיעד מנקה את החיווי', (tester) async {
      await tester.pumpWidget(
        host(log: _DropLog(), dragged: _LeafTab('נגרר')),
      );

      final rect = paneRect(tester);
      final gesture = await hoverOver(tester, rect.center);
      expect(preview(), findsOneWidget);

      await gesture.moveTo(tester.getCenter(find.byKey(handleKey)));
      await tester.pump();
      expect(preview(), findsNothing);

      await gesture.up();
      await tester.pumpAndSettle();
    });
  });

  testWidgets('תוכן החלונית ממשיך להיות מוצג מתחת ליעד', (tester) async {
    await tester.pumpWidget(
      host(log: _DropLog(), dragged: _LeafTab('נגרר')),
    );

    expect(
      find.descendant(
        of: find.byKey(paneKey),
        matching: find.byType(ColoredBox),
      ),
      findsOneWidget,
    );
  });
}
