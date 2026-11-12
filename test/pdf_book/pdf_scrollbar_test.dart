import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/pdf_book/view/pdf_scrollbar.dart';
import 'package:pdfrx/pdfrx.dart';

// ─── fake controllers ─────────────────────────────────────────────────────────
// מדמה את מצב הריבוע שגרם לקריסה: isReady=true אבל visibleRect זורק
class _UnreadyController extends PdfViewerController {
  @override
  bool get isReady => true;

  @override
  Rect get visibleRect => throw StateError('_visibleRect is null');
}

// visibleRect תקין אבל layout זורק — תרחיש race condition שני
class _ControllerWithThrowingLayout extends PdfViewerController {
  @override
  bool get isReady => true;

  @override
  Rect get visibleRect => const Rect.fromLTWH(0, 0, 400, 600);

  @override
  PdfPageLayout get layout => throw StateError('layout not available');
}

class _InteractiveController extends PdfViewerController {
  _InteractiveController({
    Size documentSize = const Size(1000, 200),
    this.page = 1234,
  }) : _visibleRect = const Rect.fromLTWH(0, 0, 100, 100),
       _layout = PdfPageLayout(
         pageLayouts: const [],
         documentSize: documentSize,
       );

  final int page;
  final PdfPageLayout _layout;
  final Rect _visibleRect;
  final List<Duration> goToDurations = [];
  final List<Offset> calcMatrixPositions = [];

  @override
  bool get isReady => true;

  @override
  Rect get visibleRect => _visibleRect;

  @override
  PdfPageLayout get layout => _layout;

  @override
  int? get pageNumber => page;

  @override
  Matrix4 get value => Matrix4.identity();

  @override
  Size get viewSize => const Size(100, 100);

  @override
  Matrix4 calcMatrixFor(Offset position, {double? zoom, Size? viewSize}) {
    calcMatrixPositions.add(position);
    return Matrix4.identity();
  }

  @override
  Future<void> goTo(
    Matrix4? destination, {
    Duration duration = const Duration(milliseconds: 200),
  }) async {
    goToDurations.add(duration);
  }
}

const _verticalHostKey = Key('vertical-scroll-host');
const _horizontalHostKey = Key('horizontal-scroll-host');

Widget _buildVerticalScrollbarHarness(
  _InteractiveController controller, {
  bool freezeThumb = false,
  VoidCallback? onNavigationStarted,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          key: _verticalHostKey,
          width: 24,
          height: 200,
          child: PdfScrollbar(
            controller: controller,
            orientation: ScrollbarOrientation.right,
            trackThickness: 16,
            thumbMinSize: 40,
            thumbColor: Colors.green,
            scrollBoundsBuilder: (_) => const Rect.fromLTWH(0, 0, 100, 1000),
            freezeThumb: freezeThumb,
            onNavigationStarted: onNavigationStarted,
          ),
        ),
      ),
    ),
  );
}

Widget _buildHorizontalScrollbarHarness(
  _InteractiveController controller, {
  VoidCallback? onNavigationStarted,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          key: _horizontalHostKey,
          width: 200,
          height: 16,
          child: PdfHorizontalScrollbar(
            controller: controller,
            trackThickness: 12,
            thumbColor: Colors.orange,
            onNavigationStarted: onNavigationStarted,
          ),
        ),
      ),
    ),
  );
}

Finder _thumbFinder(Color color) => find.byWidgetPredicate((widget) {
  if (widget is! Container || widget.decoration is! BoxDecoration) {
    return false;
  }
  final decoration = widget.decoration! as BoxDecoration;
  return decoration.color == color;
});

Finder _verticalDragGestureFinder() => find.byWidgetPredicate(
  (widget) => widget is GestureDetector && widget.onVerticalDragUpdate != null,
);

Finder _horizontalDragGestureFinder() => find.byWidgetPredicate(
  (widget) =>
      widget is GestureDetector && widget.onHorizontalDragUpdate != null,
);

void main() {
  group('PdfScrollbar - לפני חיבור ל-viewer', () {
    testWidgets('גלילה אופקית לא קורסת לפני חיבור', (tester) async {
      final controller = PdfViewerController();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: PdfHorizontalScrollbar(controller: controller)),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(PdfHorizontalScrollbar), findsOneWidget);
    });

    testWidgets('גלילה אנכית (ברירת מחדל) לא קורסת לפני חיבור', (tester) async {
      final controller = PdfViewerController();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PdfScrollbar(
              controller: controller,
              orientation: ScrollbarOrientation.right,
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('גלילה אנכית שמאל לא קורסת לפני חיבור', (tester) async {
      final controller = PdfViewerController();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PdfScrollbar(
              controller: controller,
              orientation: ScrollbarOrientation.left,
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('גלילה אנכית עם scrollBoundsBuilder לא קורסת לפני חיבור', (
      tester,
    ) async {
      final controller = PdfViewerController();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PdfScrollbar(
              controller: controller,
              orientation: ScrollbarOrientation.right,
              scrollBoundsBuilder: (_) => Rect.zero,
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  // ─── תרחיש race condition שני: visibleRect עובד אבל layout זורק ────────────
  group('PdfHorizontalScrollbar - layout זורק', () {
    testWidgets('לא קורס כאשר layout זורק (visibleRect תקין)', (tester) async {
      final controller = _ControllerWithThrowingLayout();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: PdfHorizontalScrollbar(controller: controller)),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byType(PdfHorizontalScrollbar), findsOneWidget);
    });

    testWidgets('קריסות חוזרות של layout לא גורמות לקריסה', (tester) async {
      final controller = _ControllerWithThrowingLayout();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: PdfHorizontalScrollbar(controller: controller)),
        ),
      );
      for (int i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(tester.takeException(), isNull);
    });
  });

  // ─── תרחיש הקריסה המדויק מה-LOG ──────────────────────────────────────────
  group(
    'PdfScrollbar - תרחיש race condition (isReady=true + visibleRect זורק)',
    () {
      testWidgets(
        'PdfHorizontalScrollbar לא קורס כאשר isReady=true אבל visibleRect זורק',
        (tester) async {
          final controller = _UnreadyController();
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: PdfHorizontalScrollbar(controller: controller),
              ),
            ),
          );
          // פריים שני - מדמה את ה-drawFrame שגרם לקריסה
          await tester.pump();
          await tester.pump();
          expect(tester.takeException(), isNull);
          expect(find.byType(PdfHorizontalScrollbar), findsOneWidget);
        },
      );

      testWidgets(
        'PdfScrollbar (אנכי, ברירת מחדל) לא קורס כאשר isReady=true אבל visibleRect זורק',
        (tester) async {
          final controller = _UnreadyController();
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: PdfScrollbar(
                  controller: controller,
                  orientation: ScrollbarOrientation.right,
                ),
              ),
            ),
          );
          await tester.pump();
          await tester.pump();
          expect(tester.takeException(), isNull);
        },
      );

      testWidgets(
        'PdfScrollbar (תחתון) לא קורס כאשר isReady=true אבל visibleRect זורק',
        (tester) async {
          final controller = _UnreadyController();
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: PdfScrollbar(
                  controller: controller,
                  orientation: ScrollbarOrientation.bottom,
                ),
              ),
            ),
          );
          await tester.pump();
          expect(tester.takeException(), isNull);
        },
      );

      testWidgets(
        'PdfScrollbar עם scrollBoundsBuilder לא קורס כאשר isReady=true אבל visibleRect זורק',
        (tester) async {
          final controller = _UnreadyController();
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: PdfScrollbar(
                  controller: controller,
                  orientation: ScrollbarOrientation.right,
                  scrollBoundsBuilder: (_) =>
                      const Rect.fromLTWH(0, 0, 100, 1000),
                ),
              ),
            ),
          );
          await tester.pump();
          expect(tester.takeException(), isNull);
        },
      );

      testWidgets('קריסות חוזרות בפריימים רצופים לא גורמות לקריסה', (
        tester,
      ) async {
        final controller = _UnreadyController();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: PdfHorizontalScrollbar(controller: controller),
            ),
          ),
        );
        // שישה פריימים - כמו בLOG שהראה קריסות כל ~4 שניות
        for (int i = 0; i < 6; i++) {
          await tester.pump(const Duration(seconds: 4));
        }
        expect(tester.takeException(), isNull);
      });
    },
  );

  group('PdfScrollbar - אינטראקציות drag', () {
    testWidgets('גרירה אנכית זוכרת מיקום פעם אחת, ולחיצה על המסילה בנפרד', (
      tester,
    ) async {
      var starts = 0;
      final controller = _InteractiveController();
      await tester.pumpWidget(
        _buildVerticalScrollbarHarness(
          controller,
          onNavigationStarted: () => starts++,
        ),
      );
      final center = tester.getCenter(_thumbFinder(Colors.green));
      final gesture = tester.widget<GestureDetector>(
        _verticalDragGestureFinder(),
      );
      gesture.onVerticalDragStart!(
        DragStartDetails(localPosition: const Offset(8, 20)),
      );
      for (final delta in [20.0, 40.0, 60.0]) {
        gesture.onVerticalDragUpdate!(
          DragUpdateDetails(globalPosition: center + Offset(0, delta)),
        );
        await tester.pump();
      }
      expect(starts, 1);
      gesture.onVerticalDragEnd!(DragEndDetails());
      await tester.pump();
      final origin = tester.getTopLeft(find.byKey(_verticalHostKey));
      await tester.tapAt(origin + const Offset(12, 170));
      expect(starts, 2);
    });

    testWidgets('גרירה אופקית זוכרת מיקום פעם אחת, ולחיצה על המסילה בנפרד', (
      tester,
    ) async {
      var starts = 0;
      final controller = _InteractiveController();
      await tester.pumpWidget(
        _buildHorizontalScrollbarHarness(
          controller,
          onNavigationStarted: () => starts++,
        ),
      );
      final center = tester.getCenter(_thumbFinder(Colors.orange));
      final gesture = tester.widget<GestureDetector>(
        _horizontalDragGestureFinder(),
      );
      gesture.onHorizontalDragStart!(
        DragStartDetails(localPosition: const Offset(30, 6)),
      );
      for (final delta in [20.0, 40.0, 60.0]) {
        gesture.onHorizontalDragUpdate!(
          DragUpdateDetails(globalPosition: center + Offset(delta, 0)),
        );
        await tester.pump();
      }
      expect(starts, 1);
      gesture.onHorizontalDragEnd!(DragEndDetails());
      await tester.pump();
      final origin = tester.getTopLeft(find.byKey(_horizontalHostKey));
      await tester.tapAt(origin + const Offset(180, 6));
      expect(starts, 2);
    });

    for (final vertical in [true, false]) {
      testWidgets(
        'גלילה בשתי אצבעות בלוח מגע על האגודל ${vertical ? 'האנכי' : 'האופקי'} '
        'אינה מנווטת במסמך (issue #2680)',
        (tester) async {
          var starts = 0;
          final controller = _InteractiveController();
          await tester.pumpWidget(
            vertical
                ? _buildVerticalScrollbarHarness(
                    controller,
                    onNavigationStarted: () => starts++,
                  )
                : _buildHorizontalScrollbarHarness(
                    controller,
                    onNavigationStarted: () => starts++,
                  ),
          );
          final at = tester.getCenter(
            _thumbFinder(vertical ? Colors.green : Colors.orange),
          );
          final gesture = await tester.createGesture(
            kind: PointerDeviceKind.trackpad,
          );
          await gesture.panZoomStart(at);
          for (var i = 1; i <= 3; i++) {
            final step = 10.0 * i;
            await gesture.panZoomUpdate(
              at,
              pan: vertical ? Offset(0, step) : Offset(step, 0),
            );
            await tester.pump(const Duration(milliseconds: 16));
          }
          await gesture.panZoomEnd();
          await tester.pumpAndSettle();

          expect(controller.goToDurations, isEmpty);
          expect(starts, 0);
        },
      );
    }

    testWidgets('drag אנכי משתמש ב-Duration.zero בזמן גרירה', (tester) async {
      final controller = _InteractiveController();
      await tester.pumpWidget(_buildVerticalScrollbarHarness(controller));

      final thumb = _thumbFinder(Colors.green);
      expect(thumb, findsOneWidget);
      final initialCenter = tester.getCenter(thumb);
      final dragGesture = tester.widget<GestureDetector>(
        _verticalDragGestureFinder(),
      );

      dragGesture.onVerticalDragStart!(
        DragStartDetails(localPosition: const Offset(8, 20)),
      );
      await tester.pump();
      dragGesture.onVerticalDragUpdate!(
        DragUpdateDetails(globalPosition: initialCenter + const Offset(0, 60)),
      );
      await tester.pump();

      expect(controller.goToDurations, isNotEmpty);
      expect(controller.goToDurations.last, Duration.zero);

      dragGesture.onVerticalDragEnd!(DragEndDetails());
    });

    testWidgets('thumb אנכי נצמד ויזואלית לאצבע בזמן גרירה', (tester) async {
      final controller = _InteractiveController();
      await tester.pumpWidget(_buildVerticalScrollbarHarness(controller));

      final thumb = _thumbFinder(Colors.green);
      final initialTop = tester.getTopLeft(thumb).dy;
      final initialCenter = tester.getCenter(thumb);
      final dragGesture = tester.widget<GestureDetector>(
        _verticalDragGestureFinder(),
      );

      dragGesture.onVerticalDragStart!(
        DragStartDetails(localPosition: const Offset(8, 20)),
      );
      await tester.pump();
      dragGesture.onVerticalDragUpdate!(
        DragUpdateDetails(globalPosition: initialCenter + const Offset(0, 60)),
      );
      await tester.pump();

      final movedTop = tester.getTopLeft(thumb).dy;
      expect(movedTop, greaterThan(initialTop + 30));

      dragGesture.onVerticalDragEnd!(DragEndDetails());
    });

    testWidgets('freezeThumb מונע drag ויזואלי וגם goTo', (tester) async {
      final controller = _InteractiveController();
      var starts = 0;
      await tester.pumpWidget(
        _buildVerticalScrollbarHarness(
          controller,
          freezeThumb: true,
          onNavigationStarted: () => starts++,
        ),
      );

      final thumb = _thumbFinder(Colors.green);
      final initialTop = tester.getTopLeft(thumb).dy;
      final initialCenter = tester.getCenter(thumb);
      final dragGesture = tester.widget<GestureDetector>(
        _verticalDragGestureFinder(),
      );

      dragGesture.onVerticalDragStart!(
        DragStartDetails(localPosition: const Offset(8, 20)),
      );
      await tester.pump();
      dragGesture.onVerticalDragUpdate!(
        DragUpdateDetails(globalPosition: initialCenter + const Offset(0, 60)),
      );
      await tester.pump();

      expect(controller.goToDurations, isEmpty);
      expect(tester.getTopLeft(thumb).dy, initialTop);

      dragGesture.onVerticalDragEnd!(DragEndDetails());
      final origin = tester.getTopLeft(find.byKey(_verticalHostKey));
      await tester.tapAt(origin + const Offset(12, 170));
      expect(starts, 0);
    });

    testWidgets('tap על track אנכי שומר אנימציית 200ms', (tester) async {
      final controller = _InteractiveController();
      await tester.pumpWidget(_buildVerticalScrollbarHarness(controller));

      final hostTopLeft = tester.getTopLeft(find.byKey(_verticalHostKey));
      await tester.tapAt(Offset(hostTopLeft.dx + 12, hostTopLeft.dy + 140));
      await tester.pump();

      expect(controller.goToDurations, isNotEmpty);
      expect(
        controller.goToDurations.last,
        const Duration(milliseconds: 200),
      );
    });

    testWidgets('מספר עמוד ארוך מרונדר בתוך FittedBox בפס האנכי', (
      tester,
    ) async {
      final controller = _InteractiveController(page: 1234);
      await tester.pumpWidget(_buildVerticalScrollbarHarness(controller));

      expect(find.text('1234'), findsOneWidget);
      expect(find.byType(FittedBox), findsOneWidget);
    });

    testWidgets('drag אופקי משתמש ב-Duration.zero בזמן גרירה', (tester) async {
      final controller = _InteractiveController();
      await tester.pumpWidget(_buildHorizontalScrollbarHarness(controller));

      final thumb = _thumbFinder(Colors.orange);
      expect(thumb, findsOneWidget);
      final initialCenter = tester.getCenter(thumb);
      final dragGesture = tester.widget<GestureDetector>(
        _horizontalDragGestureFinder(),
      );

      dragGesture.onHorizontalDragStart!(
        DragStartDetails(localPosition: const Offset(30, 6)),
      );
      await tester.pump();
      dragGesture.onHorizontalDragUpdate!(
        DragUpdateDetails(globalPosition: initialCenter + const Offset(60, 0)),
      );
      await tester.pump();

      expect(controller.goToDurations, isNotEmpty);
      expect(controller.goToDurations.last, Duration.zero);

      dragGesture.onHorizontalDragEnd!(DragEndDetails());
    });

    testWidgets('thumb אופקי נצמד ויזואלית לאצבע בזמן גרירה', (tester) async {
      final controller = _InteractiveController();
      await tester.pumpWidget(_buildHorizontalScrollbarHarness(controller));

      final thumb = _thumbFinder(Colors.orange);
      final initialLeft = tester.getTopLeft(thumb).dx;
      final initialCenter = tester.getCenter(thumb);
      final dragGesture = tester.widget<GestureDetector>(
        _horizontalDragGestureFinder(),
      );

      dragGesture.onHorizontalDragStart!(
        DragStartDetails(localPosition: const Offset(30, 6)),
      );
      await tester.pump();
      dragGesture.onHorizontalDragUpdate!(
        DragUpdateDetails(globalPosition: initialCenter + const Offset(60, 0)),
      );
      await tester.pump();

      final movedLeft = tester.getTopLeft(thumb).dx;
      expect(movedLeft, greaterThan(initialLeft + 30));

      dragGesture.onHorizontalDragEnd!(DragEndDetails());
    });
  });

  // ─── יציבות rebuild ───────────────────────────────────────────────────────
  group('PdfScrollbar - יציבות rebuild', () {
    testWidgets('rebuild מרובים עם controller לא מחובר', (tester) async {
      final controller = PdfViewerController();

      Widget buildScrollbars() => MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              Expanded(
                child: PdfScrollbar(
                  controller: controller,
                  orientation: ScrollbarOrientation.right,
                ),
              ),
              Expanded(
                child: PdfScrollbar(
                  controller: controller,
                  orientation: ScrollbarOrientation.right,
                  scrollBoundsBuilder: (_) => Rect.zero,
                ),
              ),
            ],
          ),
        ),
      );

      await tester.pumpWidget(buildScrollbars());
      await tester.pumpWidget(buildScrollbars());
      await tester.pumpWidget(buildScrollbars());

      expect(tester.takeException(), isNull);
      expect(find.byType(PdfScrollbar), findsNWidgets(2));
    });

    testWidgets('החלפת controller לא גורמת לקריסה', (tester) async {
      final controller1 = PdfViewerController();
      final controller2 = PdfViewerController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PdfHorizontalScrollbar(controller: controller1),
          ),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PdfHorizontalScrollbar(controller: controller2),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('dispose של widget לא גורם לקריסה', (tester) async {
      final controller = PdfViewerController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: PdfHorizontalScrollbar(controller: controller)),
        ),
      );
      // הסרת ה-widget מה-tree
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: SizedBox.shrink())),
      );

      expect(tester.takeException(), isNull);
    });
  });

  // ─── ארבע כיוונים ─────────────────────────────────────────────────────────
  group('PdfScrollbar - כל הכיוונים', () {
    for (final orientation in ScrollbarOrientation.values) {
      testWidgets('כיוון $orientation לא קורס', (tester) async {
        final controller = PdfViewerController();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: PdfScrollbar(
                controller: controller,
                orientation: orientation,
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('כיוון $orientation עם _UnreadyController לא קורס', (
        tester,
      ) async {
        final controller = _UnreadyController();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: PdfScrollbar(
                controller: controller,
                orientation: orientation,
              ),
            ),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
      });
    }
  });
}
