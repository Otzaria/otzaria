import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/misc/link_preview_overlay.dart';
import 'package:otzaria/widgets/misc/overlay_scroll_anchor.dart';

import '../support/preview_selection_helpers.dart';

void main() {
  tearDown(LinkPreviewOverlay.dismiss);
  setUp(() => CountingPreviewContent.builds = 0);

  Future<BuildContext> pumpListHost(WidgetTester tester) async {
    late BuildContext hostContext;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              hostContext = context;
              return ListView.builder(
                itemExtent: 50,
                itemCount: 100,
                itemBuilder: (context, index) => Text('פריט $index'),
              );
            },
          ),
        ),
      ),
    );
    return hostContext;
  }

  /// פותחת חלונית לצד "פריט תפריט" דמוי — כמו תצוגה מקדימה בתפריט ההקשר.
  Object? showBesideItem(
    BuildContext context, {
    Rect itemRect = const Rect.fromLTWH(400, 300, 120, 30),
    WidgetBuilder? contentBuilder,
    OverlayScrollAnchor? scrollAnchor,
    VoidCallback? onPinned,
    bool touchTriggered = false,
  }) {
    return LinkPreviewOverlay.showBesideMenuItem(
      context,
      contentBuilder: contentBuilder ?? (_) => const Text('תוכן חלונית'),
      itemGlobalRect: itemRect,
      minWidth: 0,
      touchTriggered: touchTriggered,
      scrollAnchor: scrollAnchor,
      onPinned: onPinned,
    );
  }

  /// שני פריימים: מדידה סמויה ואז הצבה במקום הסופי.
  Future<void> pumpPanel(WidgetTester tester) async {
    await tester.pump();
    await tester.pump();
  }

  Rect panelRect(WidgetTester tester) => tester.getRect(
    find
        .ancestor(
          of: find.text('תוכן חלונית'),
          matching: find.byType(Material),
        )
        .first,
  );

  testWidgets('חלונית מקובעת נשארת פתוחה ונסגרת רק בלחיצה מחוץ לה', (
    tester,
  ) async {
    final hostContext = await pumpListHost(tester);

    showBesideItem(hostContext);
    await pumpPanel(tester);
    expect(find.text('תוכן חלונית'), findsOneWidget);

    // לחיצה בתוך החלונית מקבעת אותה ואינה סוגרת אותה.
    await tester.tapAt(tester.getCenter(find.text('תוכן חלונית')));
    await tester.pump();
    expect(find.text('תוכן חלונית'), findsOneWidget);

    // סגירה מתוזמנת אינה חלה על חלונית מקובעת.
    LinkPreviewOverlay.scheduleHide();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('תוכן חלונית'), findsOneWidget);

    // לחיצה מחוץ לחלונית סוגרת.
    await tester.tapAt(const Offset(700, 550));
    await tester.pump();
    expect(find.text('תוכן חלונית'), findsNothing);
  });

  group('showBesideMenuItem', () {
    testWidgets('החלונית מוצבת משמאל לפריט (כיוון הפתיחה ב-RTL)', (
      tester,
    ) async {
      final hostContext = await pumpListHost(tester);

      const itemRect = Rect.fromLTWH(400, 300, 120, 30);
      showBesideItem(hostContext, itemRect: itemRect);
      await pumpPanel(tester);

      final rect = panelRect(tester);
      expect(
        rect.right,
        moreOrLessEquals(itemRect.left - 6, epsilon: 0.01),
        reason: 'הקצה השמאלי של הפריט הוא הקצה הימני של החלונית (רווח 6)',
      );
      expect(rect.top, moreOrLessEquals(itemRect.top, epsilon: 0.01));
    });

    testWidgets('כשאין מקום משמאל — החלונית עוברת לימין הפריט', (tester) async {
      final hostContext = await pumpListHost(tester);

      const itemRect = Rect.fromLTWH(10, 100, 120, 30);
      showBesideItem(hostContext, itemRect: itemRect);
      await pumpPanel(tester);

      expect(
        panelRect(tester).left,
        moreOrLessEquals(itemRect.right + 6, epsilon: 0.01),
      );
    });

    testWidgets('גובה החלונית מוגבל והתוכן הארוך נגלל בתוכה', (tester) async {
      final hostContext = await pumpListHost(tester);

      showBesideItem(
        hostContext,
        contentBuilder: (_) => const SizedBox(
          width: 200,
          height: 900,
          child: Text('תוכן חלונית'),
        ),
      );
      await pumpPanel(tester);

      expect(panelRect(tester).height, lessThanOrEqualTo(360));
      expect(
        find.descendant(
          of: find.byType(SingleChildScrollView),
          matching: find.text('תוכן חלונית'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('הקשה מחוץ לחלונית שנפתחה במגע אינה מגיעה למה שמתחתיה', (
      tester,
    ) async {
      var tapsBelow = 0;
      late BuildContext hostContext;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                hostContext = context;
                return GestureDetector(
                  onTap: () => tapsBelow++,
                  child: const SizedBox.expand(
                    child: ColoredBox(color: Colors.amber),
                  ),
                );
              },
            ),
          ),
        ),
      );

      showBesideItem(hostContext, touchTriggered: true);
      await pumpPanel(tester);

      await tester.tapAt(const Offset(50, 550));
      await tester.pump();
      expect(find.text('תוכן חלונית'), findsNothing);
      expect(
        tapsBelow,
        0,
        reason: 'המחסום חוסם את מה שמתחת — כדי שהתפריט יישאר פתוח',
      );
    });
  });

  group('קיבוע בלחיצה — בלי בנייה מחדש של החלונית', () {
    testWidgets('הלחיצה מקבעת במקום: התוכן אינו נבנה מחדש והמיקום אינו זז', (
      tester,
    ) async {
      final hostContext = await pumpListHost(tester);
      var pinnedCalls = 0;

      showBesideItem(
        hostContext,
        contentBuilder: (_) => const CountingPreviewContent(),
        onPinned: () => pinnedCalls++,
      );
      await pumpPanel(tester);
      expect(CountingPreviewContent.builds, 1);
      final rectBefore = tester.getRect(
        find
            .ancestor(
              of: find.byType(CountingPreviewContent),
              matching: find.byType(Material),
            )
            .first,
      );

      await tester.tapAt(tester.getCenter(find.byType(CountingPreviewContent)));
      await tester.pump();

      expect(pinnedCalls, 1, reason: 'onPinned נקרא בקיבוע');
      expect(
        CountingPreviewContent.builds,
        1,
        reason:
            'קיבוע חייב להשאיר את אותו עץ widgets — בנייה מחדש קוטעת גרירת '
            'סימון טקסט וגורמת להבהוב',
      );
      expect(
        tester.getRect(
          find
              .ancestor(
                of: find.byType(CountingPreviewContent),
                matching: find.byType(Material),
              )
              .first,
        ),
        rectBefore,
        reason: 'החלונית נשארת בדיוק במקומה בעת הקיבוע',
      );
    });

    testWidgets('הגרירה הראשונה בתוך החלונית מסמנת את הטקסט', (tester) async {
      final hostContext = await pumpListHost(tester);

      showBesideItem(
        hostContext,
        contentBuilder: (_) => const Text('אבגד הוזח טיכל'),
      );
      await pumpPanel(tester);

      await dragAcross(tester, find.text('אבגד הוזח טיכל'));

      expect(find.text('אבגד הוזח טיכל'), findsOneWidget);
      expect(
        await selectionExistsInPanel(tester, find.text('אבגד הוזח טיכל')),
        isTrue,
        reason: 'הגרירה הראשונה בתוך החלונית חייבת לסמן טקסט',
      );
    });

    testWidgets('בלי גרירה אין סימון — בקרה לבדיקת הסימון', (tester) async {
      final hostContext = await pumpListHost(tester);

      showBesideItem(
        hostContext,
        contentBuilder: (_) => const Text('אבגד הוזח טיכל'),
      );
      await pumpPanel(tester);

      expect(
        await selectionExistsInPanel(tester, find.text('אבגד הוזח טיכל')),
        isFalse,
      );
    });

    testWidgets('גם בחלונית ריחוף (showContent) הקיבוע אינו בונה מחדש', (
      tester,
    ) async {
      final hostContext = await pumpListHost(tester);

      LinkPreviewOverlay.showContent(
        hostContext,
        contentBuilder: (_) => const CountingPreviewContent(),
        globalPosition: const Offset(300, 300),
        hoverMode: true,
      );
      await pumpPanel(tester);
      expect(CountingPreviewContent.builds, 1);

      await tester.tapAt(tester.getCenter(find.byType(CountingPreviewContent)));
      await tester.pump();

      expect(find.byType(CountingPreviewContent), findsOneWidget);
      expect(CountingPreviewContent.builds, 1);
    });
  });

  group('מזהה חלונית (token)', () {
    testWidgets('dismiss עם מזהה של חלונית שהוחלפה אינו סוגר את החדשה', (
      tester,
    ) async {
      final hostContext = await pumpListHost(tester);

      final firstToken = showBesideItem(
        hostContext,
        contentBuilder: (_) => const Text('ראשונה'),
      );
      await pumpPanel(tester);
      final secondToken = showBesideItem(
        hostContext,
        contentBuilder: (_) => const Text('שנייה'),
      );
      await pumpPanel(tester);
      expect(find.text('ראשונה'), findsNothing);
      expect(find.text('שנייה'), findsOneWidget);

      LinkPreviewOverlay.dismiss(token: firstToken);
      await tester.pump();
      expect(
        find.text('שנייה'),
        findsOneWidget,
        reason: 'מזהה מיושן אינו סוגר את החלונית הפעילה',
      );

      LinkPreviewOverlay.dismiss(token: secondToken);
      await tester.pump();
      expect(find.text('שנייה'), findsNothing);
    });

    testWidgets('scheduleHide עם מזהה מיושן אינו סוגר את החלונית הפעילה', (
      tester,
    ) async {
      final hostContext = await pumpListHost(tester);

      final firstToken = showBesideItem(
        hostContext,
        contentBuilder: (_) => const Text('ראשונה'),
      );
      await pumpPanel(tester);
      showBesideItem(hostContext, contentBuilder: (_) => const Text('שנייה'));
      await pumpPanel(tester);

      LinkPreviewOverlay.scheduleHide(firstToken);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('שנייה'), findsOneWidget);

      LinkPreviewOverlay.scheduleHide();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('שנייה'), findsNothing);
    });
  });

  testWidgets('showContent מציג תוכן כללי במצב ריחוף', (tester) async {
    final hostContext = await pumpListHost(tester);

    LinkPreviewOverlay.showContent(
      hostContext,
      contentBuilder: (_) => const Text('תוכן הערה'),
      globalPosition: const Offset(200, 300),
      hoverMode: true,
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('תוכן הערה'), findsOneWidget);
  });

  testWidgets(
    'בפריים המדידה החלונית מתעלמת מ-pointer ואחרי המיקום מפסיקה',
    (tester) async {
      final hostContext = await pumpListHost(tester);

      LinkPreviewOverlay.showContent(
        hostContext,
        contentBuilder: (_) => const Text('תוכן הערה'),
        globalPosition: const Offset(200, 300),
        hoverMode: true,
      );

      // פריים ראשון (טרם מיקום): החלונית בפינה, חייבת להתעלם מ-pointer כדי לא
      // לגנוב hover מהעוגן ולגרום לה להיסגר-ולהיפתח בלולאה (הבהוב).
      await tester.pump();
      final ignoreDuringMeasure = tester.widget<IgnorePointer>(
        find.ancestor(
          of: find.text('תוכן הערה'),
          matching: find.byType(IgnorePointer),
        ),
      );
      expect(ignoreDuringMeasure.ignoring, isTrue);

      // אחרי המיקום — שוב מגיבה ל-pointer (לסימון/העתקה בתוך החלונית).
      await tester.pump();
      final ignoreAfterPlaced = tester.widget<IgnorePointer>(
        find.ancestor(
          of: find.text('תוכן הערה'),
          matching: find.byType(IgnorePointer),
        ),
      );
      expect(ignoreAfterPlaced.ignoring, isFalse);
    },
  );

  testWidgets('לחיצה ימנית מחוץ לחלונית מקובעת סוגרת אותה', (tester) async {
    final hostContext = await pumpListHost(tester);

    showBesideItem(hostContext);
    await pumpPanel(tester);
    await tester.tapAt(tester.getCenter(find.text('תוכן חלונית')));
    await tester.pump();
    expect(find.text('תוכן חלונית'), findsOneWidget);

    final gesture = await tester.startGesture(
      const Offset(700, 550),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryButton,
    );
    await gesture.up();
    await tester.pump();

    expect(find.text('תוכן חלונית'), findsNothing);
  });

  testWidgets('חלונית מקובעת זזה יחד עם גלילת הרשימה שעליה נפתחה', (
    tester,
  ) async {
    final hostContext = await pumpListHost(tester);

    final anchorPosition = tester.getCenter(find.text('פריט 3'));
    final anchor = OverlayScrollAnchor.capture(hostContext, anchorPosition);
    expect(anchor, isNotNull);

    showBesideItem(hostContext, scrollAnchor: anchor);
    await pumpPanel(tester);
    await tester.tapAt(tester.getCenter(find.text('תוכן חלונית')));
    await tester.pump();

    final panelTopBefore = tester.getTopLeft(find.text('תוכן חלונית')).dy;
    final itemTopBefore = tester.getTopLeft(find.text('פריט 3')).dy;

    await tester.drag(find.byType(ListView), const Offset(0, -120));
    await tester.pumpAndSettle();

    final itemDelta = tester.getTopLeft(find.text('פריט 3')).dy - itemTopBefore;
    final panelDelta =
        tester.getTopLeft(find.text('תוכן חלונית')).dy - panelTopBefore;
    expect(itemDelta, lessThan(0));
    expect(panelDelta, moreOrLessEquals(itemDelta, epsilon: 0.01));
  });

  testWidgets('תצוגת ריחוף צמודה לתפריט אינה זזה לפני הקיבוע', (tester) async {
    final hostContext = await pumpListHost(tester);

    final anchorPosition = tester.getCenter(find.text('פריט 3'));
    final anchor = OverlayScrollAnchor.capture(hostContext, anchorPosition);
    expect(anchor, isNotNull);

    showBesideItem(hostContext, scrollAnchor: anchor);
    await pumpPanel(tester);
    final panelTopBefore = tester.getTopLeft(find.text('תוכן חלונית')).dy;

    await tester.drag(find.byType(ListView), const Offset(0, -120));
    await tester.pumpAndSettle();

    expect(
      tester.getTopLeft(find.text('תוכן חלונית')).dy,
      moreOrLessEquals(panelTopBefore, epsilon: 0.01),
      reason:
          'כל עוד התפריט פתוח החלונית נשארת צמודה לפריט התפריט, '
          'ולא לתוכן הנגלל שמתחתיו',
    );
  });

  testWidgets('גלילה שמשליכה את שורת העוגן סוגרת את החלונית', (tester) async {
    final hostContext = await pumpListHost(tester);

    final anchorPosition = tester.getCenter(find.text('פריט 3'));
    final anchor = OverlayScrollAnchor.capture(hostContext, anchorPosition);

    showBesideItem(hostContext, scrollAnchor: anchor);
    await pumpPanel(tester);
    expect(find.text('תוכן חלונית'), findsOneWidget);

    await tester.tapAt(tester.getCenter(find.text('תוכן חלונית')));
    await tester.pump();

    // גלילה רחוקה — פריט 3 מושלך מה-cache של הרשימה והעוגן מת.
    await tester.drag(find.byType(ListView), const Offset(0, -3000));
    await tester.pumpAndSettle();

    expect(find.text('תוכן חלונית'), findsNothing);
  });

  testWidgets('capture מחזיר null בנקודה ללא תוכן נגלל', (tester) async {
    late BuildContext hostContext;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              hostContext = context;
              return const Center(child: Text('סטטי'));
            },
          ),
        ),
      ),
    );

    final anchor = OverlayScrollAnchor.capture(
      hostContext,
      tester.getCenter(find.text('סטטי')),
    );
    expect(anchor, isNull);
  });
}
