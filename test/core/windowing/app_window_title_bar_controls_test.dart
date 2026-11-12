// Intentional use of window_manager 0.6's legacy facade during the
// staged nativeapi migration; remove after moving these callers to Window.
// ignore_for_file: deprecated_member_use

import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/windowing/app_drag_to_move_area.dart';
import 'package:otzaria/core/windowing/app_window_caption.dart';
import 'package:otzaria/core/windowing/app_window_controller.dart';
import 'package:otzaria/core/windowing/app_window_scope.dart';
import 'package:otzaria/core/windowing/window_manager_app_window_controller.dart';
import 'package:window_manager/legacy.dart';

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

    expect(window.calls.where((c) => c != 'isMaximized'), [
      'minimize',
      'maximize',
      'close',
    ]);
  });

  testWidgets('לכל כפתור חלון tooltip, ובמסך מלא אין maximize', (tester) async {
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

  testWidgets('rebuilding the caption does not requery the native window', (
    tester,
  ) async {
    final window = await pump(tester, caption());
    await tester.pumpAndSettle();
    expect(
      window.calls.where((call) => call == 'isMaximized'),
      hasLength(1),
    );

    // Same controller in the same position, only the parent widget rebuilt.
    await tester.pumpWidget(
      MaterialApp(
        home: AppWindowScope(
          controller: window,
          geometry: const WindowManagerAppWindowController(),
          child: Scaffold(body: caption()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      window.calls.where((call) => call == 'isMaximized'),
      hasLength(1),
    );

    // A real maximize event invalidates the cached value exactly once.
    window.maximized = true;
    window.changes.notifyListeners();
    await tester.pumpAndSettle();
    expect(
      window.calls.where((call) => call == 'isMaximized'),
      hasLength(2),
    );
    expect(find.byTooltip('שחזר'), findsOneWidget);
  });

  testWidgets(
    'a late answer from the previous window cannot change a new caption',
    (
      tester,
    ) async {
      final oldWindow = _RecordingWindow()
        ..delayedMaximized = Completer<bool>();
      final newWindow = _RecordingWindow();
      addTearDown(oldWindow.changes.dispose);
      addTearDown(newWindow.changes.dispose);

      Future<void> show(_RecordingWindow window) => tester.pumpWidget(
        MaterialApp(
          home: AppWindowScope(
            controller: window,
            geometry: const WindowManagerAppWindowController(),
            child: Scaffold(body: caption()),
          ),
        ),
      );

      await show(oldWindow);
      await show(newWindow);
      await tester.pumpAndSettle();
      oldWindow.delayedMaximized!.complete(true);
      await tester.pump();

      expect(find.byTooltip('הגדל'), findsOneWidget);
      expect(find.byTooltip('שחזר'), findsNothing);
    },
  );

  testWidgets('יציאה ממסך מלא מעדכנת את המטמון דרך אירוע החלון הנייטיבי', (
    tester,
  ) async {
    const controller = WindowManagerAppWindowController();
    const channel = MethodChannel('window_manager');
    final messenger = tester.binding.defaultBinaryMessenger;
    var nativeMaximized = true;
    var nativeReads = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'isMaximized') {
        nativeReads++;
        return nativeMaximized;
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    Future<void> show({required bool fullscreen}) async {
      await tester.pumpWidget(
        MaterialApp(
          home: AppWindowScope(
            controller: controller,
            geometry: controller,
            child: Scaffold(body: caption(fullscreen: fullscreen)),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> nativeEvent(String name) async {
      await messenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(
          MethodCall('onEvent', {'eventName': name}),
        ),
        (_) {},
      );
      await tester.pumpAndSettle();
    }

    await show(fullscreen: false);
    expect(find.byTooltip('שחזר'), findsOneWidget);
    expect(nativeReads, 1);
    await show(fullscreen: true);
    await nativeEvent('enter-full-screen');
    expect(nativeReads, 2);
    await show(fullscreen: false);

    // במסלול Windows זה מתקבל leave-full-screen בלבד, בלי unmaximize.
    nativeMaximized = false;
    await nativeEvent('leave-full-screen');
    expect(find.byTooltip('הגדל'), findsOneWidget);
    expect(find.byTooltip('שחזר'), findsNothing);
    expect(nativeReads, 3);
    await show(fullscreen: false);
    expect(nativeReads, 3);
  });

  testWidgets('אירועי מצב רצופים מבצעים שאילתת caption אחת בפריים', (
    tester,
  ) async {
    final window = await pump(tester, caption());
    await tester.pumpAndSettle();
    window.calls.clear();
    window.maximized = true;

    for (var i = 0; i < 100; i++) {
      window.changes.notifyListeners();
    }
    expect(window.calls, isEmpty);
    await tester.pumpAndSettle();
    expect(window.calls, ['isMaximized']);
    expect(find.byTooltip('שחזר'), findsOneWidget);

    window.maximized = false;
    for (var i = 0; i < 100; i++) {
      window.changes.notifyListeners();
    }
    await tester.pumpAndSettle();
    expect(window.calls, ['isMaximized', 'isMaximized']);
    expect(find.byTooltip('הגדל'), findsOneWidget);
  });

  testWidgets('אירוע פוסל תשובה ישנה לפני שהשאילתה המאוחדת התחילה', (
    tester,
  ) async {
    final first = Completer<bool>();
    final second = Completer<bool>();
    final window = _RecordingWindow()
      ..maximizedResponses.addAll([first.future, second.future]);
    addTearDown(window.changes.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: AppWindowScope(
          controller: window,
          geometry: const WindowManagerAppWindowController(),
          child: Scaffold(body: caption()),
        ),
      ),
    );

    window.changes.notifyListeners();
    first.complete(true);
    await tester.pump();
    expect(window.calls, ['isMaximized', 'isMaximized']);
    expect(find.byTooltip('הגדל'), findsOneWidget);
    expect(find.byTooltip('שחזר'), findsNothing);

    second.complete(false);
    await tester.pumpAndSettle();
    expect(find.byTooltip('הגדל'), findsOneWidget);
  });

  testWidgets('החלפת scope מבטלת שאילתה מתוזמנת של החלון הקודם', (
    tester,
  ) async {
    final oldWindow = _RecordingWindow();
    final newWindow = _RecordingWindow();
    addTearDown(oldWindow.changes.dispose);
    addTearDown(newWindow.changes.dispose);
    Future<void> show(_RecordingWindow window, {bool notifyOld = false}) =>
        tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) {
                if (notifyOld) oldWindow.changes.notifyListeners();
                return AppWindowScope(
                  controller: window,
                  geometry: const WindowManagerAppWindowController(),
                  child: Scaffold(body: caption()),
                );
              },
            ),
          ),
        );
    await show(oldWindow);
    await tester.pumpAndSettle();
    await show(newWindow, notifyOld: true);
    await tester.pumpAndSettle();
    expect(oldWindow.calls, ['isMaximized']);
    expect(newWindow.calls, ['isMaximized']);
  });

  testWidgets('הסרת caption מבטלת שאילתה מתוזמנת', (tester) async {
    final window = await pump(tester, caption());
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      Builder(
        builder: (context) {
          window.changes.notifyListeners();
          return const SizedBox.shrink();
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(window.calls, ['isMaximized']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('תשובה שמגיעה אחרי הסרת caption אינה מעדכנת state', (
    tester,
  ) async {
    final pending = Completer<bool>();
    final window = _RecordingWindow()..delayedMaximized = pending;
    addTearDown(window.changes.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: AppWindowScope(
          controller: window,
          geometry: const WindowManagerAppWindowController(),
          child: Scaffold(body: caption()),
        ),
      ),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    pending.complete(true);
    await tester.pump();
    expect(tester.takeException(), isNull);
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
    windowManager.listeners.last.onWindowEnterFullScreen();
    windowManager.listeners.last.onWindowLeaveFullScreen();
    controller.stateChanges.removeListener(listener);

    expect(notified, 4);
    expect(windowManager.listeners.length, before);
  });
}

class _RecordingWindow extends Fake implements AppWindowController {
  final calls = <String>[];
  final changes = _Changes();
  bool maximized = false;
  Completer<bool>? delayedMaximized;
  final maximizedResponses = <Future<bool>>[];

  @override
  Listenable get stateChanges => changes;

  @override
  Future<void> startDragging() async => calls.add('startDragging');

  @override
  Future<bool> isMaximized() async {
    calls.add('isMaximized');
    if (maximizedResponses.isNotEmpty) return maximizedResponses.removeAt(0);
    final pending = delayedMaximized;
    if (pending != null) return pending.future;
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
