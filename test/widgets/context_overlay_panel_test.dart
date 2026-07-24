import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/widgets/layout/context_overlay_panel.dart';
import 'package:otzaria/widgets/layout/floating_panel.dart';
import 'package:otzaria/widgets/layout/resizable_drag_handle.dart';

class _OverlayHarness extends StatefulWidget {
  final bool deferChildBuildOnOpen;
  final bool preserveChildStateOnClose;

  const _OverlayHarness({
    super.key,
    required this.deferChildBuildOnOpen,
    required this.preserveChildStateOnClose,
  });

  @override
  State<_OverlayHarness> createState() => _OverlayHarnessState();
}

class _OverlayHarnessState extends State<_OverlayHarness> {
  bool _isOpen = false;

  void open() {
    setState(() {
      _isOpen = true;
    });
  }

  void close() {
    setState(() {
      _isOpen = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: Stack(
            children: [
              const SizedBox.expand(),
              ContextOverlayPanel(
                isOpen: _isOpen,
                onClose: close,
                deferChildBuildOnOpen: widget.deferChildBuildOnOpen,
                preserveChildStateOnClose: widget.preserveChildStateOnClose,
                child: const Text(
                  'תוכן הפאנל',
                  textDirection: TextDirection.rtl,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void main() {
  testWidgets(
    'דוחה את בניית התוכן לפריים הבא כאשר deferChildBuildOnOpen פעיל',
    (tester) async {
      final key = GlobalKey<_OverlayHarnessState>();

      await tester.pumpWidget(
        _OverlayHarness(
          key: key,
          deferChildBuildOnOpen: true,
          preserveChildStateOnClose: false,
        ),
      );

      key.currentState!.open();
      await tester.pump();

      expect(find.text('תוכן הפאנל'), findsNothing);

      await tester.pump();

      expect(find.text('תוכן הפאנל'), findsOneWidget);
    },
  );

  testWidgets('שומר את התוכן אחרי סגירה כאשר preserveChildStateOnClose פעיל', (
    tester,
  ) async {
    final key = GlobalKey<_OverlayHarnessState>();

    await tester.pumpWidget(
      _OverlayHarness(
        key: key,
        deferChildBuildOnOpen: true,
        preserveChildStateOnClose: true,
      ),
    );

    key.currentState!.open();
    await tester.pump();
    await tester.pump();

    expect(find.text('תוכן הפאנל'), findsOneWidget);

    key.currentState!.close();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.text('תוכן הפאנל'), findsOneWidget);
  });

  group('ContextOverlayPanel — מיקום Scrollbar בתוך ה-padding הקיים', () {
    Widget buildPanel({
      bool scrollable = false,
      String? title,
      Widget child = const SizedBox.shrink(),
    }) {
      return MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: Stack(
              children: [
                const SizedBox.expand(),
                ContextOverlayPanel(
                  isOpen: true,
                  onClose: () {},
                  scrollable: scrollable,
                  title: title,
                  child: child,
                ),
              ],
            ),
          ),
        ),
      );
    }

    testWidgets('scrollable=true — ה-Scrollbar וה-ScrollbarTheme קיימים', (
      tester,
    ) async {
      await tester.pumpWidget(buildPanel(scrollable: true));
      await tester.pump();

      expect(
        find.byType(Scrollbar),
        findsOneWidget,
        reason: 'ContextOverlayPanel עם scrollable=true חייב להכיל Scrollbar',
      );
      expect(
        find.byType(ScrollbarTheme),
        findsOneWidget,
        reason:
            'ScrollbarTheme מגדיר crossAxisMargin=2 — זהה ל-adaptive_side_pane',
      );
    });

    testWidgets(
      'scrollable=true — SingleChildScrollView עם padding אופקי של 16px בדיוק',
      (tester) async {
        await tester.pumpWidget(buildPanel(scrollable: true));
        await tester.pump();

        final scrollView = tester.widget<SingleChildScrollView>(
          find.byType(SingleChildScrollView),
        );
        expect(
          scrollView.padding,
          equals(const EdgeInsets.symmetric(horizontal: 16)),
          reason:
              'padding 16px הסטנדרטי בלבד — הScrollbar יושב בתוך ה-16px הקיים',
        );
      },
    );

    testWidgets(
      'scrollable=true — התוכן מוצב ב-16px מקצה ה-Scrollbar, ללא חפיפה',
      (tester) async {
        const childKey = Key('panel-content');
        await tester.pumpWidget(
          buildPanel(
            scrollable: true,
            child: const SizedBox(key: childKey, height: 10),
          ),
        );
        await tester.pump();

        final scrollbarRect = tester.getRect(find.byType(Scrollbar));
        final contentRect = tester.getRect(find.byKey(childKey));

        expect(
          contentRect.left - scrollbarRect.left,
          closeTo(16.0, 0.5),
          reason:
              'המרחק מקצה ה-Scrollbar לתוכן הוא 16px — הScrollbar לא חופף לתוכן',
        );
      },
    );

    testWidgets(
      'scrollable=false (ברירת מחדל) — אין Scrollbar ואין SingleChildScrollView',
      (tester) async {
        await tester.pumpWidget(buildPanel(scrollable: false));
        await tester.pump();

        expect(find.byType(Scrollbar), findsNothing);
        expect(find.byType(SingleChildScrollView), findsNothing);
      },
    );

    testWidgets('scrollable=true עם title — הכותרת מוצגת מעל התוכן הגלילה', (
      tester,
    ) async {
      const childKey = Key('panel-content-titled');
      await tester.pumpWidget(
        buildPanel(
          scrollable: true,
          title: 'כותרת הפאנל',
          child: const SizedBox(key: childKey, height: 10),
        ),
      );
      await tester.pump();

      expect(
        find.text('כותרת הפאנל'),
        findsOneWidget,
        reason: 'הכותרת חייבת להיות מוצגת',
      );
      expect(
        find.byType(Scrollbar),
        findsOneWidget,
        reason: 'Scrollbar חייב להיות קיים גם כשיש כותרת',
      );

      final titleRect = tester.getRect(find.text('כותרת הפאנל'));
      final contentRect = tester.getRect(find.byKey(childKey));

      expect(
        titleRect.bottom,
        lessThan(contentRect.top),
        reason: 'הכותרת נמצאת מעל אזור הגלילה',
      );
    });
  });

  group('ContextOverlayPanel — צד פס הגלילה מול ידית הגרירה', () {
    Widget buildAligned(AlignmentDirectional alignment) {
      return MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: Stack(
              children: [
                const SizedBox.expand(),
                ContextOverlayPanel(
                  isOpen: true,
                  onClose: () {},
                  scrollable: true,
                  alignment: alignment,
                  child: const Text('תוכן', textDirection: TextDirection.rtl),
                ),
              ],
            ),
          ),
        ),
      );
    }

    testWidgets('פאנל מימין (centerStart) — פס גלילה יחיד בצד ימין, תוכן RTL', (
      tester,
    ) async {
      await tester.pumpWidget(buildAligned(AlignmentDirectional.centerStart));
      await tester.pump();

      expect(
        find.byType(Scrollbar),
        findsOneWidget,
        reason: 'פס גלילה יחיד בלבד — האוטומטי מבוטל דרך ScrollConfiguration',
      );

      final scrollbarContext = tester.element(find.byType(Scrollbar));
      expect(
        Directionality.of(scrollbarContext),
        TextDirection.ltr,
        reason: 'כיוון ה-Scrollbar מהופך ל-LTR כדי להצמידו לימין, הרחק מהידית',
      );

      final contentContext = tester.element(find.byType(SingleChildScrollView));
      expect(
        Directionality.of(contentContext),
        TextDirection.rtl,
        reason: 'התוכן נשאר RTL למרות היפוך כיוון ה-Scrollbar',
      );
    });

    testWidgets('פאנל משמאל (centerEnd) — פס גלילה נשאר בצד שמאל (RTL)', (
      tester,
    ) async {
      await tester.pumpWidget(buildAligned(AlignmentDirectional.centerEnd));
      await tester.pump();

      expect(find.byType(Scrollbar), findsOneWidget);

      final scrollbarContext = tester.element(find.byType(Scrollbar));
      expect(
        Directionality.of(scrollbarContext),
        TextDirection.rtl,
        reason: 'משמאל הידית בקצה ימין — פס הגלילה נשאר בשמאל ללא היפוך',
      );
    });
  });

  group('ContextOverlayPanel — כפתור סגירה (X)', () {
    testWidgets('הכפתור מוצג כשיש title ולחיצה עליו קוראת ל-onClose', (
      tester,
    ) async {
      var closed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: Stack(
                children: [
                  const SizedBox.expand(),
                  ContextOverlayPanel(
                    isOpen: true,
                    onClose: () => closed = true,
                    title: 'כותרת',
                    child: const Text('תוכן'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byTooltip('סגור'), findsOneWidget);

      await tester.tap(find.byTooltip('סגור'));
      await tester.pump();

      expect(closed, isTrue);
    });
  });

  group('ContextOverlayPanel — שוליים בחלון צר', () {
    Widget buildSizedPanel({required double containerWidth}) {
      return MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: Center(
              child: SizedBox(
                width: containerWidth,
                height: 600,
                child: Stack(
                  children: [
                    const SizedBox.expand(),
                    ContextOverlayPanel(
                      isOpen: true,
                      onClose: () {},
                      width: 520,
                      child: const Text('תוכן'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('הרוחב מצומצם לרוחב החלון ונשמרים שוליים משני הצדדים', (
      tester,
    ) async {
      await tester.pumpWidget(buildSizedPanel(containerWidth: 300));
      await tester.pumpAndSettle();

      final containerRect = tester.getRect(find.byType(ContextOverlayPanel));
      final panelRect = tester.getRect(find.byType(FloatingPanel));

      // 300 - 10*2 = 280 → הרוחב מצומצם לרוחב הזמין פחות השוליים
      expect(panelRect.width, closeTo(280, 0.5));
      expect(panelRect.left - containerRect.left, closeTo(10, 0.5));
      expect(containerRect.right - panelRect.right, closeTo(10, 0.5));
    });

    testWidgets('גרירה בחלון צר מ-minWidth לא זורקת (טווח clamp חוקי)', (
      tester,
    ) async {
      // רוחב זמין 180 (< minWidth 200) — הטווח היה מתהפך לולא effectiveDragMax
      await tester.pumpWidget(buildSizedPanel(containerWidth: 180));
      await tester.pumpAndSettle();

      await tester.drag(find.byType(ResizableDragHandle), const Offset(-30, 0));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });
}
