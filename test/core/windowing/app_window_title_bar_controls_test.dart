import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/windowing/app_drag_to_move_area.dart';
import 'package:otzaria/core/windowing/app_window_caption.dart';
import 'package:otzaria/core/windowing/app_window_controller.dart';
import 'package:otzaria/core/windowing/app_window_scope.dart';
import 'package:otzaria/core/windowing/window_manager_app_window_controller.dart';
import 'package:window_manager/window_manager.dart';

void main() {
  Future<_RecordingWindow> pump(WidgetTester tester, Widget child) async {
    final window = _RecordingWindow();
    addTearDown(window.changes.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: AppWindowScope(
          controller: window,
          geometry: const WindowManagerAppWindowController(),
          child: Scaffold(body: child),
        ),
      ),
    );
    return window;
  }

  Widget dragArea() => const Center(
    child: SizedBox(
      width: 200,
      height: 40,
      child: AppDragToMoveArea(child: SizedBox.expand()),
    ),
  );

  testWidgets('AppDragToMoveArea גורר את החלון שב-scope', (tester) async {
    final window = await pump(tester, dragArea());

    await tester.drag(find.byType(AppDragToMoveArea), const Offset(40, 0));
    await tester.pumpAndSettle(kDoubleTapTimeout);

    expect(window.calls, ['startDragging']);
  });

  testWidgets('לחיצה כפולה ב-AppDragToMoveArea מחליפה maximize', (
    tester,
  ) async {
    final window = await pump(tester, dragArea());
    Future<void> doubleTap() async {
      await tester.tap(find.byType(AppDragToMoveArea));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byType(AppDragToMoveArea));
      await tester.pumpAndSettle(kDoubleTapTimeout);
    }

    await doubleTap();
    window.maximized = true;
    await doubleTap();

    expect(window.calls, [
      'isMaximized',
      'maximize',
      'isMaximized',
      'unmaximize',
    ]);
  });

  Widget caption({bool fullscreen = false}) => Align(
    alignment: Alignment.topRight,
    child: SizedBox(
      width: fullscreen ? null : 138,
      height: 40,
      child: AppWindowCaption(
        fullscreen: fullscreen,
        tooltips: const AppWindowCaptionTooltips(
          minimize: 'מזער',
          maximize: 'הגדל',
          restore: 'שחזר',
          close: 'סגור',
        ),
      ),
    ),
  );

  testWidgets('כפתורי AppWindowCaption פונים לחלון שב-scope', (tester) async {
    final window = await pump(tester, caption());
    await tester.pumpAndSettle();
    final buttons = find.byType(WindowCaptionButton);
    expect(buttons, findsNWidgets(3));

    await tester.tap(buttons.at(0));
    await tester.tap(buttons.at(1));
    await tester.tap(buttons.at(2));

    expect(
      window.calls.where((c) => c != 'isMaximized'),
      ['minimize', 'maximize', 'close'],
    );
  });

  testWidgets('לכל כפתור חלון tooltip, ובמסך מלא אין maximize', (
    tester,
  ) async {
    await pump(tester, caption());
    await tester.pumpAndSettle();
    for (final tip in ['מזער', 'הגדל', 'סגור']) {
      expect(find.byTooltip(tip), findsOneWidget);
    }

    final window = await pump(tester, caption(fullscreen: true));
    await tester.pumpAndSettle();
    expect(find.byType(WindowCaptionButton), findsNWidgets(2));
    expect(find.byTooltip('הגדל'), findsNothing);
    await tester.tap(find.byTooltip('סגור'));
    expect(window.calls.where((c) => c != 'isMaximized'), ['close']);
  });

  testWidgets('AppWindowCaption מתעדכן מ-stateChanges של החלון', (
    tester,
  ) async {
    final window = await pump(tester, caption());
    await tester.pumpAndSettle();
    window.calls.clear();

    window.maximized = true;
    window.changes.notifyListeners();
    await tester.pumpAndSettle();
    await tester.tap(find.byType(WindowCaptionButton).at(1));

    expect(window.calls, ['isMaximized', 'unmaximize']);
  });

  test('stateChanges של windowManager נרשם רק כשיש מאזינים', () {
    const controller = WindowManagerAppWindowController();
    final before = windowManager.listeners.length;
    var notified = 0;
    void listener() => notified++;

    controller.stateChanges.addListener(listener);
    expect(windowManager.listeners.length, before + 1);
    windowManager.listeners.last.onWindowMaximize();
    windowManager.listeners.last.onWindowUnmaximize();
    controller.stateChanges.removeListener(listener);

    expect(notified, 2);
    expect(windowManager.listeners.length, before);
  });
}

class _RecordingWindow extends Fake implements AppWindowController {
  final calls = <String>[];
  final changes = _Changes();
  bool maximized = false;

  @override
  Listenable get stateChanges => changes;

  @override
  Future<void> startDragging() async => calls.add('startDragging');

  @override
  Future<bool> isMaximized() async {
    calls.add('isMaximized');
    return maximized;
  }

  @override
  Future<void> maximize() async => calls.add('maximize');

  @override
  Future<void> unmaximize() async => calls.add('unmaximize');

  @override
  Future<void> minimize() async => calls.add('minimize');

  @override
  Future<void> close() async => calls.add('close');
}

class _Changes extends ChangeNotifier {
  @override
  void notifyListeners() => super.notifyListeners();
}
