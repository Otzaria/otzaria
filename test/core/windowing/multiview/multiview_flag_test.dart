import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:otzaria/core/windowing/runner_window_channel.dart';
import 'package:otzaria/core/windowing/window_opener.dart';
import 'package:otzaria/core/windowing/multiview/view_window_opener.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/windowing/multiview/cocoa_view_window_native.dart';
import 'package:otzaria/core/windowing/multiview/gtk_view_window_native.dart';
import 'package:otzaria/core/windowing/multiview/multiview_flag.dart';
import 'package:otzaria/core/windowing/multiview/view_window_native.dart';

import '../../../test_helpers/fake_view_window.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    MultiViewMode.debugOverride = false;
    MultiViewMode.debugResetOwnerInstalled();
    MultiViewMode.debugResetMacRunner();
  });

  test('Windows ו-Linux נתמכות, ושם אין מנוע לכל חלון', () {
    MultiViewMode.debugOverride = null;
    final supported = Platform.isWindows || Platform.isLinux;
    expect(MultiViewMode.supported, supported);
  });

  test('binding של בדיקות: הבעלים לא מותקן וריבוי התצוגות כבוי', () {
    MultiViewMode.debugOverride = null;

    expect(hasRealPlatformDispatcher(), isFalse);
    expect(installWindowingOwner(), isFalse);
    expect(MultiViewMode.ownerInstalled, isFalse);
    expect(MultiViewMode.enabled, isFalse);
    expect(RunnerWindowChannel.canOpenWindows, isFalse);
    expect(WindowOpener.current, same(ViewWindowOpener.instance));
  });

  test('בלי בעלים, יצירת חלון נכשלת בשגיאת Dart ולא בקריסה נייטיבית', () {
    expect(
      () => createViewWindow(
        size: const Size(800, 600),
        title: 't',
        onCloseRequested: (_) {},
        onDestroyed: (_) {},
      ),
      throwsStateError,
    );
  });

  test('nativeHandle: בקר שאינו נייטיב או חלון שנהרס מחזירים null', () {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    final handle = ViewWindowHandle.forTesting(StubWindowController(view));
    expect(handle.nativeHandle, isNull);
    expect(handle.hwnd, isNull);
    handle.markDestroyed();
    expect(handle.nativeHandle, isNull);
  });

  test('ViewWindowNative.platform: win32, GTK או Cocoa לפי הפלטפורמה', () {
    final native = ViewWindowNative.platform();
    if (Platform.isWindows) expect(native, isA<Win32ViewWindowNative>());
    if (Platform.isLinux) expect(native, isA<GtkViewWindowNative>());
    if (Platform.isMacOS) expect(native, isA<CocoaViewWindowNative>());
  });

  group('macOS: handshake עם ה-runner', () {
    const channel = CocoaViewWindowNative.defaultChannel;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    void runnerAnswers(bool ready) =>
        messenger.setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'multiViewReady') return ready;
          if (call.method == 'multiViewStatus') return 'flip not applied';
          return null;
        });

    setUp(() {
      MultiViewMode.debugOverride = null;
      MultiViewMode.debugIsMacOS = true;
    });

    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    test('לפני ה-handshake: חלון יחיד', () {
      expect(MultiViewMode.supported, isFalse);
      expect(installWindowingOwner(), isFalse);
    });

    test('מוכן: נתמך, בלי מנוע לכל חלון', () async {
      runnerAnswers(true);
      expect(await awaitMacRunnerHandshake(), isNull);
      expect(MultiViewMode.supported, isTrue);
    });

    test('לא מוכן: חלון יחיד, עם הסיבה', () async {
      runnerAnswers(false);
      expect(await awaitMacRunnerHandshake(), 'flip not applied');
      expect(MultiViewMode.supported, isFalse);
      expect(MultiViewMode.enabled, isFalse);
      expect(RunnerWindowChannel.canOpenWindows, isFalse);
      expect(RunnerWindowChannel.canDragTabsOut, isFalse);
      expect(WindowOpener.current, same(ViewWindowOpener.instance));
      expect(await WindowOpener.current.canOpenAnotherWindow(), isFalse);
      expect(await WindowOpener.current.openEmptyWindow(), isFalse);
    });

    test('חלון יחיד משאיר את ערוץ הראשי פעיל אך אינו יוצר מנוע נוסף', () async {
      runnerAnswers(false);
      await awaitMacRunnerHandshake();
      final calls = <String>[];
      messenger.setMockMethodCallHandler(RunnerWindowChannel.channel, (
        call,
      ) async {
        calls.add(call.method);
        return call.method == 'restoreLastClosedWindow' ? true : null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(
          RunnerWindowChannel.channel,
          null,
        ),
      );
      const runner = RunnerWindowChannel();
      expect(await WindowOpener.current.openWindow(), isFalse);
      await runner.closeSelf();
      await runner.raiseSelf();
      expect(await runner.restoreLastClosedWindow(), isTrue);
      expect(calls, ['closeSelf', 'raiseSelf', 'restoreLastClosedWindow']);
    });

    test('runner ישן בלי הערוץ: חלון יחיד', () async {
      expect(await awaitMacRunnerHandshake(), isNotNull);
      expect(MultiViewMode.supported, isFalse);
    });

    test('ה-handshake אינו משפיע מחוץ ל-macOS', () async {
      runnerAnswers(false);
      await awaitMacRunnerHandshake();
      MultiViewMode.debugIsMacOS = false;
      expect(MultiViewMode.supported, Platform.isWindows || Platform.isLinux);
    });
  });
}
