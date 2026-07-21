import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/misc/link_preview_overlay.dart';
import 'package:otzaria/widgets/misc/overlay_scroll_anchor.dart';

void main() {
  tearDown(LinkPreviewOverlay.dismiss);

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

  testWidgets('חלונית מקובעת נשארת פתוחה ונסגרת רק בלחיצה מחוץ לה', (
    tester,
  ) async {
    final hostContext = await pumpListHost(tester);

    LinkPreviewOverlay.showPinned(
      hostContext,
      contentBuilder: (_) => const Text('תוכן חלונית'),
      panelPosition: const Offset(200, 300),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('תוכן חלונית'), findsOneWidget);

    // המתנה ארוכה — אין סגירה מתוזמנת על חלונית מקובעת.
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('תוכן חלונית'), findsOneWidget);

    // לחיצה בתוך החלונית אינה סוגרת אותה.
    await tester.tapAt(tester.getCenter(find.text('תוכן חלונית')));
    await tester.pump();
    expect(find.text('תוכן חלונית'), findsOneWidget);

    // לחיצה מחוץ לחלונית סוגרת.
    await tester.tapAt(const Offset(700, 550));
    await tester.pump();
    expect(find.text('תוכן חלונית'), findsNothing);
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

  testWidgets('חלונית מקובעת זזה יחד עם גלילת הרשימה שעליה נפתחה', (
    tester,
  ) async {
    final hostContext = await pumpListHost(tester);

    final anchorPosition = tester.getCenter(find.text('פריט 3'));
    final anchor = OverlayScrollAnchor.capture(hostContext, anchorPosition);
    expect(anchor, isNotNull);

    LinkPreviewOverlay.showPinned(
      hostContext,
      contentBuilder: (_) => const Text('תוכן חלונית'),
      panelPosition: const Offset(200, 300),
      scrollAnchor: anchor,
    );
    await tester.pump();
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

  testWidgets('גלילה שמשליכה את שורת העוגן סוגרת את החלונית', (tester) async {
    final hostContext = await pumpListHost(tester);

    final anchorPosition = tester.getCenter(find.text('פריט 3'));
    final anchor = OverlayScrollAnchor.capture(hostContext, anchorPosition);

    LinkPreviewOverlay.showPinned(
      hostContext,
      contentBuilder: (_) => const Text('תוכן חלונית'),
      panelPosition: const Offset(200, 300),
      scrollAnchor: anchor,
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('תוכן חלונית'), findsOneWidget);

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
