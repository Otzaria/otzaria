import 'dart:io';
import 'package:otzaria/indexing/utils/indexing_crash_canary.dart';
import 'dart:async';
import 'dart:isolate';
import 'dart:ui' as ui show IsolateNameServer;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/plugins/bloc/plugin_system_bloc.dart';
import 'package:otzaria/plugins/bloc/plugin_system_event.dart';
import 'package:otzaria/plugins/bloc/plugin_system_state.dart';
import 'package:window_manager/window_manager.dart' show TitleBarStyle;
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/windowing/app_window_controller.dart';
import 'package:otzaria/core/windowing/app_window_id.dart';
import 'package:otzaria/core/windowing/app_window_scope.dart';
import 'package:otzaria/core/windowing/multi_window_service.dart';
import 'package:otzaria/core/windowing/window_bus.dart';
import 'package:otzaria/core/windowing/window_bus_host.dart';
import 'package:otzaria/core/windowing/window_role.dart';
import 'package:otzaria/plugins/utils/plugin_safe_mode.dart';

/// ⚠️ קידומת ייחודית לסוויטה — [ui.IsolateNameServer] גלובלי לתהליך.
const String _namespace = 'otzaria.test.bushost.close';

/// בקשת "אנא היסגר" בין חלונות, שנולדה כדי שמעדכן חיצוני יוכל להחליף קבצים.
///
/// הדרישה שקבעה את הצורה: **שומרי הסגירה חייבים לרוץ**. כיבוי כפוי
/// (`TerminateProcess`) הורג את ה-isolates של שאר החלונות בלי לשאול, ותוסף
/// עם שינויים שלא נשמרו היה מאבד אותם בשקט.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    MultiWindowService.debugSupportedOverride = true;
    WindowBus.namespace = _namespace;
  });

  tearDown(() {
    PluginSafeMode.resetForTesting();
    WindowBus.instance.onRequest = null;
    WindowBus.instance.unregister();
    for (var i = 1; i <= WindowBus.slotCount; i++) {
      ui.IsolateNameServer.removePortNameMapping('$_namespace.$i');
    }
    ui.IsolateNameServer.removePortNameMapping('$_namespace.owner');
    WindowBus.namespace = 'otzaria.window';
    MultiWindowService.debugSupportedOverride = null;
    MultiWindowService.closingAll = false;
    WindowRole.isSecondary = false;
  });

  Future<Object?> deliverCloseRequest(
    WidgetTester tester,
    _RecordingWindow window,
  ) async {
    await tester.pumpWidget(
      AppWindowScope(
        controller: window,
        geometry: window,
        child: const WindowBusHost(child: SizedBox()),
      ),
    );
    return WindowBus.instance.onRequest!({
      'type': MultiWindowService.requestCloseWindow,
    });
  }

  testWidgets('בקשת מוכנות מחלון משני ממתינה להחלטה ומשתחררת פעם אחת', (
    tester,
  ) async {
    final decision = Completer<void>();
    PluginSafeMode.ready = decision.future;
    final window = _RecordingWindow();
    await tester.pumpWidget(
      AppWindowScope(
        controller: window,
        geometry: window,
        child: const WindowBusHost(child: SizedBox()),
      ),
    );
    var completed = false;
    final request = WindowBus
        .instance
        .onRequest!({'type': PluginSafeMode.readyRequest})
        .then((value) {
          completed = true;
          return value;
        });
    await tester.pump();
    expect(completed, isFalse);
    PluginSafeMode.active.value = true;
    decision.complete();
    expect(await request, isTrue);
    expect(
      await WindowBus.instance.onRequest!({
        'type': PluginSafeMode.readyRequest,
      }),
      isTrue,
    );
  });

  testWidgets('בחירה מחלון משני מוחלת גם על ראשי מוסתר בלי איפוס כרטיסיות', (
    tester,
  ) async {
    final plugins = _RecordingPlugins();
    final window = _RecordingWindow(visible: false);
    await tester.pumpWidget(
      BlocProvider<PluginSystemBloc>.value(
        value: plugins,
        child: AppWindowScope(
          controller: window,
          geometry: window,
          child: const WindowBusHost(child: SizedBox()),
        ),
      ),
    );
    for (final mode in [true, false]) {
      expect(
        await WindowBus.instance.onRequest!({
          'type': MultiWindowService.requestRestart,
          'pluginSafeMode': mode,
        }),
        isFalse,
      );
      expect(PluginSafeMode.isActive, mode);
      expect(
        await WindowBus.instance.onRequest!({
          'type': PluginSafeMode.readyRequest,
        }),
        mode,
      );
    }
    expect(plugins.events, everyElement(isA<LoadPlugins>()));
    expect(plugins.events, hasLength(2));
    expect(window.closeCalls, 0);
  });

  test('restartPeers carries the explicit session choice', () async {
    final peer = _FakePeer(2)..register();
    addTearDown(peer.dispose);
    MultiWindowService.restartPeers(pluginSafeMode: false);
    await peer.received.future.timeout(const Duration(seconds: 2));
    expect(peer.lastType, MultiWindowService.requestRestart);
    expect(peer.lastBody!['pluginSafeMode'], isFalse);
  });

  testWidgets('כיבוי תהליך מחלון אחר מסיים מעקב אינדוקס בראשי מוסתר', (
    tester,
  ) async {
    final temp = Directory.systemTemp.createTempSync('canary_owner_');
    addTearDown(() => temp.deleteSync(recursive: true));
    IndexingCrashCanary.start('${temp.path}/index');
    final canary = IndexingCrashCanary.current!;
    addTearDown(canary.finish);
    canary.begin('id:active');
    final window = _RecordingWindow(visible: false);
    await tester.pumpWidget(
      AppWindowScope(
        controller: window,
        geometry: window,
        child: const WindowBusHost(child: SizedBox()),
      ),
    );
    expect(
      await WindowBus.instance.onRequest!({
        'type': IndexingCrashCanary.finishRequest,
      }),
      isTrue,
    );
    expect(IndexingCrashCanary.current, isNull);
    expect(File('${temp.path}/index.in_flight.json').readAsStringSync(), '{}');
    expect(window.closeCalls, 0);
  });

  testWidgets('בקשת סגירה נכנסת עוברת במסלול הסגירה הרגיל', (tester) async {
    final window = _RecordingWindow();
    final handled = await deliverCloseRequest(tester, window);

    expect(handled, isTrue);
    expect(window.closeCalls, 1, reason: 'close() הוא בדיוק המסלול של X');
    expect(MultiWindowService.closingAll, isTrue, reason: 'הסשן נשמר');
    expect(
      window.quitCalls,
      0,
      reason: 'כיבוי כפוי היה מדלג על שומרי הסגירה של החלון',
    );
  });

  testWidgets('חלון משני נסגר באותה בקשה כמו הראשי', (tester) async {
    WindowRole.isSecondary = true;
    final window = _RecordingWindow();

    expect(await deliverCloseRequest(tester, window), isTrue);
    expect(window.closeCalls, 1);
  });

  // חלון סגור מוסתר ולא נהרס, וה-isolate שלו ממשיך לענות על האפיק.
  testWidgets('חלון מוסתר אינו נסגר שוב', (tester) async {
    final window = _RecordingWindow(visible: false);

    expect(await deliverCloseRequest(tester, window), isFalse);
    expect(window.closeCalls, 0);
  });

  testWidgets('חלון שסירב נשאר פתוח, ואין אחריו כפייה', (tester) async {
    // שומר הסגירה (שינויים שלא נשמרו בתוסף) עצר את הסגירה: `close()` נקרא
    // והחלון נשאר גלוי. זהו מצב לגיטימי ולא כשל.
    final window = _RecordingWindow(closeSucceeds: false);

    expect(await deliverCloseRequest(tester, window), isTrue);
    expect(await window.isVisible(), isTrue);
    expect(window.quitCalls, 0);
  });

  test('closePeers משדר את סוג הבקשה לכל שאר החלונות', () async {
    WindowBus.instance.register();
    final peer = _FakePeer(WindowBus.instance.slot == 1 ? 2 : 1)..register();
    addTearDown(peer.dispose);

    MultiWindowService.closePeers();
    await peer.received.future.timeout(const Duration(seconds: 2));

    expect(peer.lastType, MultiWindowService.requestCloseWindow);
  });

  test('סירוב של חלון אחר אינו מחזיר כשל לשולח', () async {
    WindowBus.instance.register();
    final peer = _FakePeer(WindowBus.instance.slot == 1 ? 2 : 1, answer: false)
      ..register();
    addTearDown(peer.dispose);

    // שידור הוא void: אין ערך שאפשר להיכשל בו, ואין חריגה שתעצור את הקורא.
    expect(MultiWindowService.closePeers, returnsNormally);
    await peer.received.future.timeout(const Duration(seconds: 2));
  });
}

/// חלון אחר שתופס משבצת ורושם את מה שקיבל.
class _FakePeer {
  _FakePeer(this.slot, {this.answer = true});

  final int slot;
  final bool answer;
  final Completer<void> received = Completer<void>();
  Object? lastType;
  Map? lastBody;
  late final ReceivePort _port;

  void register() {
    _port = ReceivePort();
    ui.IsolateNameServer.registerPortWithName(
      _port.sendPort,
      '$_namespace.$slot',
    );
    _port.listen((message) {
      final map = message as Map;
      lastBody = map['body'] as Map;
      lastType = lastBody!['type'];
      (map['reply'] as SendPort).send({'ok': true, 'result': answer});
      if (!received.isCompleted) received.complete();
    });
  }

  void dispose() {
    ui.IsolateNameServer.removePortNameMapping('$_namespace.$slot');
    _port.close();
  }
}

/// בקר חלון שסופר קריאות. [closeSucceeds] false מדמה שומר סגירה שסירב:
/// `close()` נקרא, והחלון נשאר גלוי.
class _RecordingWindow implements AppWindowController, AppWindowGeometry {
  _RecordingWindow({this.visible = true, this.closeSucceeds = true});

  bool visible;
  final bool closeSucceeds;
  int closeCalls = 0;
  int quitCalls = 0;

  @override
  final AppWindowId id = const AppWindowId('test-window');

  @override
  Future<void> close() async {
    closeCalls++;
    if (closeSucceeds) visible = false;
  }

  @override
  Future<void> quitApplication() async => quitCalls++;

  @override
  Future<bool> isVisible() async => visible;

  @override
  Future<void> center() async {}
  @override
  Future<void> focus() async {}
  @override
  Future<Rect> getBounds() async => Rect.zero;
  @override
  Future<bool> isFullScreen() async => false;
  @override
  Future<bool> isMaximized() async => false;
  @override
  Future<bool> isMinimized() async => false;
  @override
  Future<void> maximize() async {}
  @override
  Future<void> minimize() async {}
  @override
  Future<void> setBounds(Rect bounds) async {}
  @override
  Future<void> setFullScreen(bool value) async {}
  @override
  Future<void> setMinimumSize(Size size) async {}
  @override
  Future<void> setProgressBar(double progress) async {}
  @override
  Future<void> setSize(Size size) async {}
  @override
  Future<void> setTitleBarStyle(
    TitleBarStyle style, {
    required bool windowButtonVisibility,
  }) async {}
  @override
  Future<void> show() async {}
  @override
  Future<void> startDragging() async {}
  @override
  Future<void> unmaximize() async {}
}

class _RecordingPlugins extends Fake implements PluginSystemBloc {
  @override
  Stream<PluginSystemState> get stream => const Stream.empty();
  @override
  PluginSystemState get state => PluginSystemInitial();
  final events = <PluginSystemEvent>[];
  @override
  void add(PluginSystemEvent event) => events.add(event);
}
