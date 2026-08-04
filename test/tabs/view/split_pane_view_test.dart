import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/view/split_pane_view.dart';
import 'package:otzaria/widgets/layout/split_pane_content_inset.dart';

class _LeafTab extends OpenedTab {
  _LeafTab(super.title);

  @override
  Map<String, dynamic> toJson() => {'type': '_LeafTab', 'title': title};
}

/// סופר כמה פעמים אותחל מחדש תוכן חלונית — הכלי שבו נמדד שימור ה-State.
class _CountingPane extends StatefulWidget {
  final String label;
  static final Map<String, int> initCount = {};

  const _CountingPane(this.label, {super.key});

  static void reset() => initCount.clear();

  @override
  State<_CountingPane> createState() => _CountingPaneState();
}

class _CountingPaneState extends State<_CountingPane> {
  /// ערך שנצבר בזמן ריצה — מדמה מיקום גלילה או controller של PDF.
  int scrollPosition = 0;

  @override
  void initState() {
    super.initState();
    _CountingPane.initCount.update(
      widget.label,
      (v) => v + 1,
      ifAbsent: () => 1,
    );
  }

  @override
  Widget build(BuildContext context) => Text(widget.label);
}

Widget _host(
  OpenedTab root, {
  ValueChanged<double>? onRatioChanged,
  Widget Function(OpenedTab)? paneBuilder,
}) {
  return MaterialApp(
    // עובי המפריד תלוי בפלטפורמה (רחב יותר במגע); כאן נבדקת התנהגות העכבר.
    theme: ThemeData(platform: TargetPlatform.windows),
    home: Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: SplitPaneView(
          root: root,
          paneBuilder:
              paneBuilder ??
              (pane) => _CountingPane(pane.title, key: ValueKey(pane)),
          onRatioChanged: onRatioChanged ?? (_) {},
        ),
      ),
    ),
  );
}

void main() {
  setUp(_CountingPane.reset);

  group('פריסה', () {
    testWidgets('חלונית בודדת מוצגת ללא מפריד', (tester) async {
      await tester.pumpWidget(_host(_LeafTab('א')));

      expect(find.text('א'), findsOneWidget);
      expect(find.byType(Row), findsNothing);
    });

    testWidgets('פיצול מציג את שתי החלוניות זו לצד זו', (tester) async {
      final root = CombinedTab(
        rightTab: _LeafTab('ימין'),
        leftTab: _LeafTab('שמאל'),
      );
      await tester.pumpWidget(_host(root));

      expect(find.text('ימין'), findsOneWidget);
      expect(find.text('שמאל'), findsOneWidget);

      // ב-RTL החלונית הראשונה יושבת בימין.
      final right = tester.getCenter(find.text('ימין'));
      final left = tester.getCenter(find.text('שמאל'));
      expect(right.dx, greaterThan(left.dx));
      expect(right.dy, closeTo(left.dy, 0.5));
    });

    testWidgets('ב-LTR הסדר מתהפך והחלונית הראשונה משמאל', (tester) async {
      final root = CombinedTab(
        rightTab: _LeafTab('ראשונה'),
        leftTab: _LeafTab('שנייה'),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.windows),
          home: Directionality(
            textDirection: TextDirection.ltr,
            child: Scaffold(
              body: SplitPaneView(
                root: root,
                paneBuilder: (pane) => Text(pane.title),
                onRatioChanged: (_) {},
              ),
            ),
          ),
        ),
      );

      expect(
        tester.getCenter(find.text('ראשונה')).dx,
        lessThan(tester.getCenter(find.text('שנייה')).dx),
      );
    });

    testWidgets('היחס קובע את רוחב החלוניות', (tester) async {
      final root = CombinedTab(
        rightTab: _LeafTab('רחבה'),
        leftTab: _LeafTab('צרה'),
        splitRatio: 0.75,
      );
      await tester.pumpWidget(_host(root));

      final wide = tester.getSize(find.text('רחבה')).width;
      final narrow = tester.getSize(find.text('צרה')).width;
      expect(wide, greaterThan(narrow * 2));
    });
  });

  group('שוליי תוכן', () {
    Future<Map<String, EdgeInsets>> capture(
      WidgetTester tester,
      OpenedTab root,
    ) async {
      final insets = <String, EdgeInsets>{};
      await tester.pumpWidget(
        _host(
          root,
          paneBuilder: (pane) => Builder(
            builder: (context) {
              insets[pane.title] = SplitPaneContentInset.of(
                context,
              ).resolve(TextDirection.rtl);
              return Text(pane.title);
            },
          ),
        ),
      );
      return insets;
    }

    testWidgets('חלונית יחידה אינה מקבלת שוליים', (tester) async {
      final insets = await capture(tester, _LeafTab('א'));
      expect(insets['א'], EdgeInsets.zero);
    });

    testWidgets('כל חלונית מפוצה בצד הנגדי למפריד', (tester) async {
      final insets = await capture(
        tester,
        CombinedTab(rightTab: _LeafTab('ימין'), leftTab: _LeafTab('שמאל')),
      );

      // הימנית גובלת במפריד בשמאלה ולכן מפוצה בימין, ולהפך.
      expect(insets['ימין']!.right, kPaneDividerThickness);
      expect(insets['ימין']!.left, 0);
      expect(insets['שמאל']!.left, kPaneDividerThickness);
      expect(insets['שמאל']!.right, 0);
    });
  });

  group('גרירת מפריד', () {
    testWidgets('גרירה שמאלה ב-RTL מגדילה את החלונית הימנית', (tester) async {
      final root = CombinedTab(
        rightTab: _LeafTab('ימין'),
        leftTab: _LeafTab('שמאל'),
      );
      double? reportedRatio;

      await tester.pumpWidget(
        _host(root, onRatioChanged: (ratio) => reportedRatio = ratio),
      );

      final widthBefore = tester.getSize(find.text('ימין')).width;
      await tester.drag(
        find.byType(MouseRegion).last,
        const Offset(-100, 0),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();

      expect(reportedRatio, greaterThan(0.5));
      expect(tester.getSize(find.text('ימין')).width, greaterThan(widthBefore));
      // היחס נשמר על הטאב עצמו, כדי שבנייה מחדש לא תאבד את הגרירה.
      expect(root.splitRatio, reportedRatio);
    });

    testWidgets('גרירה אינה מכווצת חלונית מתחת למינימום', (tester) async {
      final root = CombinedTab(
        rightTab: _LeafTab('ימין'),
        leftTab: _LeafTab('שמאל'),
      );
      double? reportedRatio;

      await tester.pumpWidget(
        _host(root, onRatioChanged: (ratio) => reportedRatio = ratio),
      );

      await tester.drag(
        find.byType(MouseRegion).last,
        const Offset(5000, 0),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();

      expect(reportedRatio, greaterThan(0.0));
      expect(tester.getSize(find.text('ימין')).width, greaterThan(0));
    });

    testWidgets('לחיצה כפולה מאפסת את היחס לחצי', (tester) async {
      final root = CombinedTab(
        rightTab: _LeafTab('ימין'),
        leftTab: _LeafTab('שמאל'),
        splitRatio: 0.8,
      );
      double? reportedRatio;

      await tester.pumpWidget(
        _host(root, onRatioChanged: (ratio) => reportedRatio = ratio),
      );

      await tester.tap(find.byType(MouseRegion).last, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.byType(MouseRegion).last, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(reportedRatio, 0.5);
    });
  });

  group('שימור State בשינוי מבנה', () {
    testWidgets('פיצול הטאב אינו מאתחל מחדש את החלונית הקיימת', (tester) async {
      final a = _LeafTab('א');
      final b = _LeafTab('ב');

      await tester.pumpWidget(_host(a));
      expect(_CountingPane.initCount['א'], 1);

      // מדמה מצב ריצה שנצבר בחלונית — מיקום גלילה, controller וכד'.
      tester
              .state<_CountingPaneState>(find.byType(_CountingPane).first)
              .scrollPosition =
          42;

      await tester.pumpWidget(_host(CombinedTab(rightTab: a, leftTab: b)));

      expect(find.text('ב'), findsOneWidget);
      // זהו החוזה: הספר שכבר היה על המסך לא נטען מחדש בפיצול.
      expect(_CountingPane.initCount['א'], 1);
      expect(_CountingPane.initCount['ב'], 1);
      expect(
        tester
            .state<_CountingPaneState>(find.byType(_CountingPane).first)
            .scrollPosition,
        42,
      );
    });

    testWidgets('פירוק הפיצול אינו מאתחל מחדש את החלונית שנשארה', (
      tester,
    ) async {
      final a = _LeafTab('א');
      final b = _LeafTab('ב');

      await tester.pumpWidget(_host(CombinedTab(rightTab: a, leftTab: b)));
      expect(_CountingPane.initCount['א'], 1);

      await tester.pumpWidget(_host(a));

      expect(find.text('ב'), findsNothing);
      expect(_CountingPane.initCount['א'], 1);
    });

    testWidgets('החלפת צדדים אינה מאתחלת מחדש את החלוניות', (tester) async {
      final a = _LeafTab('א');
      final b = _LeafTab('ב');

      await tester.pumpWidget(_host(CombinedTab(rightTab: a, leftTab: b)));
      final xBefore = tester.getCenter(find.text('א')).dx;

      await tester.pumpWidget(_host(CombinedTab(rightTab: b, leftTab: a)));

      expect(tester.getCenter(find.text('א')).dx, lessThan(xBefore));
      expect(_CountingPane.initCount['א'], 1);
      expect(_CountingPane.initCount['ב'], 1);
    });

    testWidgets('גרירת מפריד אינה בונה מחדש את תוכן החלוניות', (tester) async {
      final root = CombinedTab(
        rightTab: _LeafTab('א'),
        leftTab: _LeafTab('ב'),
      );
      await tester.pumpWidget(_host(root));

      await tester.drag(
        find.byType(MouseRegion).last,
        const Offset(-60, 0),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();

      expect(_CountingPane.initCount['א'], 1);
      expect(_CountingPane.initCount['ב'], 1);
    });

    testWidgets('החלפת טאב מפוצל באחר בונה את החלוניות החדשות בלבד', (
      tester,
    ) async {
      final a = _LeafTab('א');
      final b = _LeafTab('ב');
      final c = _LeafTab('ג');

      await tester.pumpWidget(_host(CombinedTab(rightTab: a, leftTab: b)));
      await tester.pumpWidget(_host(CombinedTab(rightTab: a, leftTab: c)));

      expect(_CountingPane.initCount['א'], 1);
      expect(_CountingPane.initCount['ג'], 1);
    });
  });
}
