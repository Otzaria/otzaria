import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/windowing/app_drag_to_move_area.dart';
import 'package:otzaria/core/windowing/app_window_caption.dart';
import 'package:otzaria/core/windowing/app_window_controller.dart';
import 'package:otzaria/core/windowing/app_window_scope.dart';
import 'package:otzaria/core/windowing/window_caption_hit_test.dart';
import 'package:otzaria/core/windowing/window_manager_app_window_controller.dart';
import 'package:window_manager/window_manager.dart';

/// DD-16 (q11 Q3 B): כפתורי החלון ואזור הגרירה פעילים מעל שכבת ההחשכה של
/// דיאלוג. שאר האפליקציה נשארת חסומה.
void main() {
  late _RecordingWindow window;
  late int bodyTaps;
  late int barButtonTaps;
  late int dialogTaps;
  late BuildContext appContext;

  Future<void> pump(
    WidgetTester tester, {
    bool scope = true,
    bool splash = false,
  }) async {
    window = _RecordingWindow();
    addTearDown(window.changes.dispose);
    bodyTaps = 0;
    barButtonTaps = 0;
    dialogTaps = 0;
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => Directionality(
          textDirection: TextDirection.rtl,
          child: scope ? WindowCaptionHitTestScope(child: child!) : child!,
        ),
        home: AppWindowScope(
          controller: window,
          geometry: const WindowManagerAppWindowController(),
          child: Builder(
            builder: (context) {
              appContext = context;
              final screen = Scaffold(
                body: Column(
                  children: [
                    SizedBox(
                      height: 40,
                      child: Row(
                        children: [
                          TextButton(
                            onPressed: () => barButtonTaps++,
                            child: const Text('היסטוריה'),
                          ),
                          const Expanded(
                            child: AppDragToMoveArea(child: SizedBox.expand()),
                          ),
                          const SizedBox(
                            width: 138,
                            child: AppWindowCaption(
                              tooltips: AppWindowCaptionTooltips(
                                minimize: 'מזער',
                                maximize: 'הגדל',
                                restore: 'שחזר',
                                close: 'סגור',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Center(
                        child: TextButton(
                          onPressed: () => bodyTaps++,
                          child: const Text('גוף'),
                        ),
                      ),
                    ),
                  ],
                ),
              );
              // כמו מסך הפתיחה: התוכן מוסתר וחסום, ומעליו תיבה אטומה בגודל
              // החלון.
              return Stack(
                children: [
                  IgnorePointer(ignoring: splash, child: screen),
                  if (splash)
                    const Positioned.fill(
                      child: ColoredBox(color: Color(0xFFFFFFFF)),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openDialog(
    WidgetTester tester, {
    Alignment? at,
    bool dismissible = false,
  }) async {
    showDialog<void>(
      context: appContext,
      barrierDismissible: dismissible,
      builder: (_) => Align(
        alignment: at ?? Alignment.center,
        child: Material(
          child: SizedBox(
            width: 300,
            height: 120,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                TextButton(
                  autofocus: true,
                  onPressed: () => dialogTaps++,
                  child: const Text('בדיאלוג'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder captionButton(int i) => find.byType(WindowCaptionButton).at(i);

  bool reaches(WidgetTester tester, Finder target) {
    final box = tester.renderObject<RenderBox>(target);
    final result = HitTestResult();
    tester.binding.hitTestInView(
      result,
      tester.getCenter(target),
      tester.view.viewId,
    );
    return result.path.any((e) => identical(e.target, box));
  }

  testWidgets('בלי דיאלוג: הכול כרגיל', (tester) async {
    await pump(tester);
    await tester.tap(captionButton(0));
    await tester.tap(find.text('היסטוריה'));
    await tester.tap(find.text('גוף'));
    await tester.pump();
    expect(window.calls, ['minimize']);
    expect(barButtonTaps, 1);
    expect(bodyTaps, 1);
  });

  testWidgets('דיאלוג פתוח: מזער, הגדל וסגור פעילים', (tester) async {
    await pump(tester);
    await openDialog(tester);
    for (var i = 0; i < 3; i++) {
      expect(reaches(tester, captionButton(i)), isTrue, reason: 'כפתור $i');
    }
    await tester.tap(captionButton(0));
    await tester.pump();
    await tester.tap(captionButton(2));
    await tester.pump();
    expect(window.calls, contains('minimize'));
    expect(window.calls.last, 'close', reason: 'אותו מסלול כמו Alt+F4');
    expect(find.text('בדיאלוג'), findsOneWidget, reason: 'הדיאלוג נשאר פתוח');
  });

  testWidgets('דיאלוג פתוח: גרירת השורה מזיזה את החלון', (tester) async {
    await pump(tester);
    await openDialog(tester);
    await tester.drag(
      find.byType(AppDragToMoveArea).first,
      const Offset(40, 0),
    );
    await tester.pumpAndSettle(kDoubleTapTimeout);
    expect(window.calls, contains('startDragging'));
  });

  group('דיאלוג שנסגר בלחיצה בחוץ (R6-3)', () {
    Finder dragArea() => find.byType(AppDragToMoveArea).first;

    testWidgets('לחיצה על אזור ריק בשורה סוגרת אותו, כמו לחיצה על ההחשכה', (
      tester,
    ) async {
      await pump(tester);
      await openDialog(tester, dismissible: true);
      await tester.tap(dragArea());
      await tester.pumpAndSettle(kDoubleTapTimeout);
      expect(find.text('בדיאלוג'), findsNothing);
      expect(window.calls, isEmpty);
    });

    testWidgets('גרירה מהאזור הריק מזיזה את החלון, והדיאלוג נשאר', (
      tester,
    ) async {
      await pump(tester);
      await openDialog(tester, dismissible: true);
      await tester.drag(dragArea(), const Offset(40, 0));
      await tester.pumpAndSettle(kDoubleTapTimeout);
      expect(window.calls, ['startDragging']);
      expect(find.text('בדיאלוג'), findsOneWidget);
    });

    testWidgets('לחיצה כפולה על האזור הריק מגדילה, והדיאלוג נשאר', (
      tester,
    ) async {
      await pump(tester);
      await openDialog(tester, dismissible: true);
      final at = tester.getCenter(dragArea());
      await tester.tapAt(at);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tapAt(at);
      await tester.pumpAndSettle();
      expect(window.calls, ['maximize']);
      expect(find.text('בדיאלוג'), findsOneWidget);
    });

    testWidgets('כפתורי החלון פועלים בלי לסגור אותו', (tester) async {
      await pump(tester);
      await openDialog(tester, dismissible: true);
      await tester.tap(captionButton(0));
      await tester.pumpAndSettle(kDoubleTapTimeout);
      expect(window.calls, ['minimize']);
      expect(find.text('בדיאלוג'), findsOneWidget);
    });

    testWidgets('דיאלוג שאינו נסגר בלחיצה בחוץ נשאר פתוח', (tester) async {
      await pump(tester);
      await openDialog(tester);
      await tester.tap(dragArea());
      await tester.pumpAndSettle(kDoubleTapTimeout);
      expect(find.text('בדיאלוג'), findsOneWidget);
    });
  });

  testWidgets('דיאלוג פתוח: גוף האפליקציה וכפתורי השורה האחרים חסומים', (
    tester,
  ) async {
    await pump(tester);
    await openDialog(tester);
    expect(reaches(tester, find.text('גוף')), isFalse);
    expect(reaches(tester, find.text('היסטוריה')), isFalse);
    await tester.tap(find.text('גוף'), warnIfMissed: false);
    await tester.tap(find.text('היסטוריה'), warnIfMissed: false);
    await tester.pump();
    expect(bodyTaps, 0);
    expect(barButtonTaps, 0);
  });

  testWidgets('תוכן דיאלוג שמעל שורת הכותרת מקבל את הלחיצה', (tester) async {
    await pump(tester);
    // הדיאלוג בפינה העליונה, מעל כפתורי החלון (שמאל ב-RTL).
    await openDialog(tester, at: Alignment.topLeft);
    expect(
      tester
          .getRect(find.byType(AppWindowCaption))
          .contains(tester.getCenter(find.text('בדיאלוג'))),
      isTrue,
      reason: 'הלחיצה בתוך אזור כפתורי החלון',
    );
    await tester.tap(find.text('בדיאלוג'));
    await tester.pump();
    expect(dialogTaps, 1);
    expect(window.calls, isEmpty);
  });

  testWidgets('Esc והפוקוס בדיאלוג לא משתנים', (tester) async {
    await pump(tester);
    await openDialog(tester, dismissible: true);
    final focused = FocusManager.instance.primaryFocus!.context!;
    expect(
      find.descendant(
        of: find.byElementPredicate((e) => e == focused),
        matching: find.text('בדיאלוג'),
      ),
      findsOneWidget,
      reason: 'הפוקוס נשאר בדיאלוג',
    );
    // לחיצה על כפתור חלון לא לוקחת את הפוקוס.
    await tester.tap(captionButton(0));
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.context, focused);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('בדיאלוג'), findsNothing);
  });

  testWidgets('מתחת למסך הפתיחה (IgnorePointer) כפתורי החלון חסומים (R6-2)', (
    tester,
  ) async {
    await pump(tester, splash: true);
    for (var i = 0; i < 3; i++) {
      expect(reaches(tester, captionButton(i)), isFalse, reason: 'כפתור $i');
    }
    await tester.tap(captionButton(2), warnIfMissed: false);
    await tester.tap(captionButton(0), warnIfMissed: false);
    await tester.drag(
      find.byType(AppDragToMoveArea).first,
      const Offset(40, 0),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle(kDoubleTapTimeout);
    expect(window.calls, isEmpty);
  });

  testWidgets('מתחת למסך הפתיחה, גם עם דיאלוג פתוח, השורה חסומה (R6-2)', (
    tester,
  ) async {
    await pump(tester, splash: true);
    await openDialog(tester);
    expect(reaches(tester, captionButton(2)), isFalse);
    await tester.tap(captionButton(2), warnIfMissed: false);
    await tester.pump();
    expect(window.calls, isEmpty);
  });

  testWidgets('onlyAboveDialogs: בלי דיאלוג שקוף, ועם דיאלוג פעיל (R6-4)', (
    tester,
  ) async {
    var below = 0;
    var region = 0;
    late BuildContext context;
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => WindowCaptionHitTestScope(child: child!),
        home: Builder(
          builder: (c) {
            context = c;
            return Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: 200,
                height: 40,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: GestureDetector(
                        onTap: () => below++,
                        child: const ColoredBox(color: Color(0xFF00FF00)),
                      ),
                    ),
                    Positioned.fill(
                      child: WindowCaptionRegion(
                        onlyAboveDialogs: true,
                        child: GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onTap: () => region++,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
    final at = tester.getCenter(find.byType(Stack).last);
    await tester.tapAt(at);
    await tester.pump();
    expect((below, region), (1, 0), reason: 'בלי דיאלוג האזור לא קיים');

    showDialog<void>(
      context: context,
      builder: (_) => const Center(child: SizedBox(width: 50, height: 50)),
    );
    await tester.pumpAndSettle();
    await tester.tapAt(at);
    await tester.pump();
    expect((below, region), (1, 1), reason: 'מעל דיאלוג רק האזור פעיל');
  });

  testWidgets('בלי WindowCaptionHitTestScope (טלפון, רשת) השורה חסומה', (
    tester,
  ) async {
    await pump(tester, scope: false);
    await openDialog(tester);
    expect(reaches(tester, captionButton(2)), isFalse);
    await tester.tap(captionButton(2), warnIfMissed: false);
    await tester.pump();
    expect(window.calls, isEmpty);
  });
}

class _RecordingWindow extends Fake implements AppWindowController {
  final calls = <String>[];
  final changes = ChangeNotifier();

  @override
  Listenable get stateChanges => changes;

  @override
  Future<void> startDragging() async => calls.add('startDragging');

  @override
  Future<bool> isMaximized() async => false;

  @override
  Future<void> maximize() async => calls.add('maximize');

  @override
  Future<void> unmaximize() async => calls.add('unmaximize');

  @override
  Future<void> minimize() async => calls.add('minimize');

  @override
  Future<void> close() async => calls.add('close');
}
