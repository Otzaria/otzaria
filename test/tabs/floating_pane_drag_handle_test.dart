import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/tabs/models/tool_tab.dart';
import 'package:otzaria/tabs/view/pane_drag_handle.dart';

/// ידית הגרירה של חלונית תוסף בטאב מפוצל (#2635): מופיעה במחשב רק בריחוף
/// ברצועה העליונה של החלונית, במנוחה לא חוסמת את התוכן, ובמגע מופיעה
/// בגרסה הקטנה רק אחרי נגיעה ברצועה, ולכמה שניות.
void main() {
  final pane = ToolTab(toolId: 'x.plugin', title: 'מקבילות');

  late int contentTaps;
  late int contentBuilds;

  Widget app({
    bool split = true,
    bool enabled = true,
    TargetPlatform platform = TargetPlatform.windows,
  }) {
    return MaterialApp(
      theme: ThemeData(platform: platform),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: PaneDragHandleScope(
            pane: pane,
            enabled: split,
            child: FloatingPaneDragHandle(
              enabled: enabled,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => contentTaps++,
                child: _CountBuilds(onInit: () => contentBuilds++),
              ),
            ),
          ),
        ),
      ),
    );
  }

  setUp(() {
    contentTaps = 0;
    contentBuilds = 0;
  });

  final handle = find.byType(PaneDragHandleButton);

  double opacity(WidgetTester tester) => tester
      .widget<AnimatedOpacity>(
        find.ancestor(of: handle, matching: find.byType(AnimatedOpacity)),
      )
      .opacity;

  bool ignoring(WidgetTester tester) => tester
      .widget<IgnorePointer>(
        find.ancestor(of: handle, matching: find.byType(IgnorePointer)).first,
      )
      .ignoring;

  const reveal = FloatingPaneDragHandle.touchRevealDuration;
  const tick = Duration(milliseconds: 100);

  testWidgets('במחשב, במנוחה: שקופה, ולחיצה בפינה מגיעה לתוסף', (tester) async {
    await tester.pumpWidget(app());
    expect(handle, findsOneWidget);
    expect(opacity(tester), 0);

    await tester.tapAt(
      tester.getCenter(handle),
      kind: PointerDeviceKind.mouse,
    );
    expect(contentTaps, 1, reason: 'הידית השקופה לא בולעת את הלחיצה');
  });

  testWidgets('במחשב, בריחוף ברצועה העליונה: מופיעה בפינה העליונה בצד ההתחלה', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: const Offset(400, 400));
    await tester.pumpAndSettle();
    expect(opacity(tester), 0, reason: 'באמצע החלונית הידית לא מופיעה');

    // הרצועה העליונה, בקצה הרחוק מהידית (שמאל ב-RTL).
    final pageRect = tester.getRect(find.byType(_CountBuilds));
    await mouse.moveTo(pageRect.topLeft + const Offset(20, 20));
    await tester.pumpAndSettle();
    expect(opacity(tester), 1);

    // RTL: צד ההתחלה הוא ימין.
    final handleRect = tester.getRect(handle);
    expect(pageRect.right - handleRect.right, lessThan(12));
    expect(handleRect.top - pageRect.top, lessThan(12));
    expect(
      handleRect.bottom - pageRect.top,
      lessThan(FloatingPaneDragHandle.hoverStripHeight),
      reason: 'הידית כולה בתוך הרצועה',
    );

    // בתוך הידית הלחיצה שלה ולא של התוסף.
    await mouse.moveTo(tester.getCenter(handle));
    await tester.pumpAndSettle();
    expect(opacity(tester), 1);
    await tester.tapAt(tester.getCenter(handle), kind: PointerDeviceKind.mouse);
    expect(contentTaps, 0);

    // ברצועה, מחוץ לידית, הלחיצה מגיעה לתוסף.
    await tester.tapAt(
      pageRect.topLeft + const Offset(20, 20),
      kind: PointerDeviceKind.mouse,
    );
    expect(contentTaps, 1);

    // מתחת לרצועה היא נעלמת, גם בלי לצאת מהחלונית.
    await mouse.moveTo(
      Offset(
        handleRect.center.dx,
        pageRect.top + FloatingPaneDragHandle.hoverStripHeight + 1,
      ),
    );
    await tester.pumpAndSettle();
    expect(opacity(tester), 0, reason: 'נעלמת מתחת לרצועה');

    await mouse.moveTo(pageRect.topLeft + const Offset(20, 20));
    await tester.pumpAndSettle();
    await mouse.moveTo(const Offset(-10, -10));
    await tester.pumpAndSettle();
    expect(opacity(tester), 0, reason: 'נעלמת כשהעכבר יוצא');
  });

  testWidgets('במגע, במנוחה: מוסתרת ולא בולעת נגיעה', (tester) async {
    await tester.pumpWidget(app(platform: TargetPlatform.android));
    await tester.pumpAndSettle();
    expect(opacity(tester), 0);
    expect(ignoring(tester), isTrue);
    expect(tester.widget<PaneDragHandleButton>(handle).dense, isTrue);

    // נגיעה מתחת לרצועה: מגיעה לתוסף, והידית לא מופיעה.
    final pageRect = tester.getRect(find.byType(_CountBuilds));
    await tester.tapAt(
      Offset(
        tester.getCenter(handle).dx,
        pageRect.top + FloatingPaneDragHandle.hoverStripHeight + 4,
      ),
    );
    await tester.pumpAndSettle();
    expect(contentTaps, 1);
    expect(opacity(tester), 0, reason: 'רק הרצועה העליונה מציגה');
  });

  testWidgets('במגע, נגיעה ברצועה: מופיעה, הנגיעה מגיעה לתוסף, ונעלמת', (
    tester,
  ) async {
    await tester.pumpWidget(app(platform: TargetPlatform.android));
    await tester.pumpAndSettle();
    final pageRect = tester.getRect(find.byType(_CountBuilds));

    // בקצה הרחוק של הרצועה (שמאל ב-RTL).
    await tester.tapAt(pageRect.topLeft + const Offset(20, 20));
    await tester.pump();
    expect(contentTaps, 1, reason: 'הנגיעה שמציגה את הידית לא נבלעת');
    expect(opacity(tester), 1);
    expect(ignoring(tester), isFalse);
    final size = tester.getSize(handle);
    expect(size.width, lessThanOrEqualTo(24));
    expect(size.height, lessThanOrEqualTo(24));

    // נגיעה נוספת מתחילה את הספירה מחדש.
    await tester.pump(reveal - tick * 5);
    await tester.tapAt(pageRect.topLeft + const Offset(20, 20));
    await tester.pump(reveal - tick);
    expect(opacity(tester), 1, reason: 'עדיין לפני סוף הזמן');
    expect(contentTaps, 2);

    await tester.pump(tick * 2);
    await tester.pumpAndSettle();
    expect(opacity(tester), 0, reason: 'נעלמת אחרי הזמן');
    expect(ignoring(tester), isTrue);

    // נגיעה במקום הידית כשהיא מוסתרת: מגיעה לתוסף.
    await tester.tapAt(tester.getCenter(handle));
    await tester.pump();
    expect(contentTaps, 3);
    expect(opacity(tester), 1);
  });

  testWidgets('במגע: גרירה משאירה את הידית, והספירה מתחילה מחדש בסופה', (
    tester,
  ) async {
    await tester.pumpWidget(app(platform: TargetPlatform.android));
    await tester.pumpAndSettle();
    final pageRect = tester.getRect(find.byType(_CountBuilds));
    await tester.tapAt(pageRect.topLeft + const Offset(20, 20));
    await tester.pump();
    expect(opacity(tester), 1);

    // לחיצה ארוכה במגע על הידית והזזה: גרירה אמיתית, לא ההסבר (Tooltip).
    expect(find.text('מקבילות'), findsNothing);
    final drag = await tester.startGesture(tester.getCenter(handle));
    await tester.pump(kLongPressTimeout + tick);
    await drag.moveBy(const Offset(-60, 120));
    await tester.pump();
    expect(find.text('מקבילות'), findsOneWidget, reason: 'הגרירה התחילה');
    expect(
      find.text(_tooltip, findRichText: true),
      findsNothing,
      reason: 'ההסבר לא קופץ במגע',
    );

    await tester.pump(reveal * 2);
    expect(opacity(tester), 1, reason: 'בזמן גרירה הידית נשארת');
    expect(ignoring(tester), isFalse);

    await drag.up();
    await tester.pump(reveal - tick);
    expect(opacity(tester), 1, reason: 'הספירה התחילה מחדש בסוף הגרירה');
    await tester.pump(tick * 2);
    await tester.pumpAndSettle();
    expect(opacity(tester), 0);
  });

  testWidgets('במחשב, ריחוף על הידית מציג את ההסבר', (tester) async {
    await tester.pumpWidget(app());
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: const Offset(400, 400));
    await tester.pump();
    final pageRect = tester.getRect(find.byType(_CountBuilds));
    await mouse.moveTo(pageRect.topRight + const Offset(-20, 20));
    await tester.pumpAndSettle();
    await mouse.moveTo(tester.getCenter(handle));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text(_tooltip, findRichText: true), findsOneWidget);
    await mouse.moveTo(const Offset(-10, -10));
    await tester.pumpAndSettle();
  });

  testWidgets('במחשב, נגיעה ברצועה לא מציגה (רק ריחוף)', (tester) async {
    await tester.pumpWidget(app());
    final pageRect = tester.getRect(find.byType(_CountBuilds));
    await tester.tapAt(pageRect.topLeft + const Offset(20, 20));
    await tester.pumpAndSettle();
    expect(opacity(tester), 0);
    expect(contentTaps, 1);
    expect(tester.widget<PaneDragHandleButton>(handle).dense, isFalse);
  });

  testWidgets('בלי טאב מפוצל, או כש-enabled כבוי: אין ידית', (tester) async {
    await tester.pumpWidget(app(split: false));
    expect(handle, findsNothing);
    await tester.pumpWidget(app(enabled: false));
    expect(handle, findsNothing);
  });

  testWidgets('פיצול ופירוק לא בונים מחדש את התוכן', (tester) async {
    await tester.pumpWidget(app(split: false));
    await tester.pumpWidget(app());
    expect(handle, findsOneWidget);
    await tester.pumpWidget(app(split: false));
    expect(contentBuilds, 1);
  });
}

const _tooltip = 'גרור אל שורת הכרטיסיות כדי להחזיר לכרטיסייה נפרדת';

class _CountBuilds extends StatefulWidget {
  const _CountBuilds({required this.onInit});
  final VoidCallback onInit;

  @override
  State<_CountBuilds> createState() => _CountBuildsState();
}

class _CountBuildsState extends State<_CountBuilds> {
  @override
  void initState() {
    super.initState();
    widget.onInit();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}
