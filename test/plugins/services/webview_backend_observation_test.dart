import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_inappwebview_windows/flutter_inappwebview_windows.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/diagnostics/developer_diagnostics.dart';
import 'package:otzaria/plugins/services/webview_backend_observation.dart';

class _OtherController extends Fake implements PlatformInAppWebViewController {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  InAppWebViewController controller(Object? native, {String? channel}) {
    final platform = WindowsInAppWebViewController(
      WindowsInAppWebViewControllerCreationParams(
        id: channel ?? 'backend-test',
        creationDetails: native == null
            ? null
            : WindowsWebViewCreationResult.fromNative(native).creationDetails,
      ),
    );
    addTearDown(platform.dispose);
    return InAppWebViewController.fromPlatform(platform: platform);
  }

  Map<String, Object?> read(
    InAppWebViewController value, {
    String force = '0',
  }) => observeWebViewBackend(
    value,
    platform: 'windows',
    environment: {'FLUTTER_INAPPWEBVIEW_WINDOWS_FORCE_HWND': force},
  );

  for (final mode in ['composition', 'hwnd']) {
    test('reads the public $mode getter without treating it as live state', () {
      final result = read(controller({'id': 31, 'renderMode': mode}));
      expect(result['nativeViewId'], 31);
      expect(result['observed'], mode);
      expect(result['availability'], 'collected');
      expect(result['verified'], isTrue);
      expect(result['scope'], 'nativeCreation');
      expect(result['ongoingModeVerified'], isFalse);
      expect(result['fallbackReasonAvailable'], isFalse);
    });
  }

  for (final value in <Object>[
    31,
    {'id': 31},
    {'id': 31, 'renderMode': 'future-mode'},
    {'id': 31, 'fallbackStage': 'forced', 'fallbackHresult': 0},
  ]) {
    test('legacy or unknown metadata stays unverified: $value', () {
      final result = read(controller(value), force: '1');
      expect(result['requested'], 'hwnd');
      expect(result['observed'], isNull);
      expect(result['verified'], isFalse);
      expect(result['reason'], 'native_render_mode_unknown');
    });
  }

  test('a composition request with native capture fallback stays HWND', () {
    final result = read(
      controller({
        'id': 31,
        'renderMode': 'hwnd',
        'fallbackStage': 'capture',
        'fallbackHresult': -2147467259,
      }),
    );
    expect(result['requested'], 'composition');
    expect(result['observed'], 'hwnd');
    expect(result['verified'], isTrue);
    expect(result['fallbackReasonAvailable'], isTrue);
    expect(result['fallbackHresult'], 0x80004005);
  });

  test('partial reasons do not invalidate an independently verified mode', () {
    final result = read(
      controller({'id': 31, 'renderMode': 'hwnd', 'fallbackStage': 'capture'}),
    );
    expect(result['verified'], isTrue);
    expect(result['fallbackStage'], 'capture');
    expect(result['fallbackReasonAvailable'], isFalse);
    expect(result['fallbackHresult'], isNull);
  });

  test('absent observations and disposed controllers remain unavailable', () {
    expect(read(controller(null))['reason'], 'creation_details_unavailable');
    final value = controller({'id': 31, 'renderMode': 'hwnd'});
    (value.platform as WindowsInAppWebViewController).dispose();
    expect(read(value)['verified'], isFalse);
    expect(read(value)['observed'], isNull);
  });

  test('other platforms and missing Windows implementation stay explicit', () {
    final value = InAppWebViewController.fromPlatform(
      platform: _OtherController(),
    );
    expect(read(value)['reason'], 'windows_controller_unavailable');
    final unsupported = observeWebViewBackend(value, platform: 'macos');
    expect(unsupported['availability'], 'unsupported');
    expect(unsupported['requested'], isNull);
    expect(unsupported['verified'], isFalse);
  });

  test('the force request follows the exact native environment contract', () {
    expect(requestedWebViewBackend({}), 'composition');
    for (final value in ['0', '', 'true', '01', '1 ', 'parent-value']) {
      expect(
        requestedWebViewBackend({
          'FLUTTER_INAPPWEBVIEW_WINDOWS_FORCE_HWND': value,
        }),
        'composition',
      );
    }
    expect(
      requestedWebViewBackend({'FLUTTER_INAPPWEBVIEW_WINDOWS_FORCE_HWND': '1'}),
      'hwnd',
    );
  });

  test(
    'late collection replays only the current attachment, then releases it',
    () {
      final collecting = ValueNotifier(false);
      final records = <Map<String, Object?>>[];
      final tracker = WebViewBackendDiagnostics(
        collecting: collecting,
        record: (type, fields) => records.add({'type': type, ...fields}),
      );
      addTearDown(tracker.dispose);
      addTearDown(collecting.dispose);
      tracker.attach(
        controller({'id': 31, 'renderMode': 'composition'}, channel: 'old'),
        host: const {'instanceId': 'same-logical-instance'},
        platform: 'windows',
      );
      tracker.attach(
        controller({'id': 31, 'renderMode': 'hwnd'}, channel: 'current'),
        host: const {'instanceId': 'same-logical-instance'},
        platform: 'windows',
      );
      expect(records, isEmpty);
      collecting.value = true;
      expect(records.single['event'], 'present');
      expect((records.single['backend'] as Map)['observed'], 'hwnd');
      tracker.detach();
      expect(records.last['event'], 'detached');
      expect(records.last['attachmentId'], records.first['attachmentId']);
      collecting.value = false;
      collecting.value = true;
      expect(records.length, 2);
    },
  );

  test(
    'mixed views and native id reuse have independent attachment lifetimes',
    () {
      final collecting = ValueNotifier(true);
      final records = <Map<String, Object?>>[];
      final first = WebViewBackendDiagnostics(
        collecting: collecting,
        record: (_, fields) => records.add(fields),
      );
      final second = WebViewBackendDiagnostics(
        collecting: collecting,
        record: (_, fields) => records.add(fields),
      );
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      addTearDown(collecting.dispose);
      for (final entry in [(first, 'composition'), (second, 'hwnd')]) {
        entry.$1.attach(
          controller({'id': 8, 'renderMode': entry.$2}, channel: entry.$2),
          host: const {'instanceId': 'same'},
          platform: 'windows',
        );
      }
      expect(records.map((r) => r['attachmentId']).toSet().length, 2);
      first.dispose();
      first.dispose();
      collecting.value = false;
      collecting.value = true;
      expect(records.length, 4);
      expect(records[2]['event'], 'detached');
      expect(records.last['attachmentId'], records[1]['attachmentId']);
      expect((records.last['backend'] as Map)['observed'], 'hwnd');
    },
  );

  test(
    'diagnostics correlate events and ticks only in an opt-in session',
    () async {
      final diagnostics = DeveloperDiagnostics.instance..resetForTesting();
      diagnostics.errorLogWriter = (_) {};
      diagnostics.processSampler = () async => null;
      final directory = await Directory.systemTemp.createTemp(
        'backend-events-',
      );
      addTearDown(diagnostics.resetForTesting);
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/events.jsonl');
      diagnostics.outputPath = file.path;
      diagnostics.recordEvent('webview_backend', const {'event': 'ignored'});
      expect(file.existsSync(), isFalse);
      diagnostics.initFromLaunch(
        ['--dev-diagnostics=log'],
        environment: {'OTZARIA_WEBVIEW_PROBE_RUN_ID': 'specific-run'},
      );
      diagnostics.recordEvent('webview_backend', const {
        'event': 'attached',
        'pid': -1,
        'session': -1,
        'probeRunId': 'wrong',
      });
      diagnostics.debugTick();
      await diagnostics.snapshot();
      final records = file
          .readAsLinesSync()
          .map((s) => jsonDecode(s) as Map)
          .toList();
      final session = records.singleWhere((r) => r['type'] == 'session');
      final event = records.singleWhere((r) => r['type'] == 'webview_backend');
      final tick = records.singleWhere(
        (r) => r['type'] == 'webview_probe_tick',
      );
      for (final record in [event, tick]) {
        expect(record['pid'], pid);
        expect(record['session'], session['session']);
        expect(record['probeRunId'], 'specific-run');
        expect(DateTime.tryParse(record['utc'] as String), isNotNull);
      }
      diagnostics.toggle();
      await diagnostics.snapshot();
      final end = file
          .readAsLinesSync()
          .map((s) => jsonDecode(s) as Map)
          .singleWhere((r) => r['type'] == 'end');
      expect(end['probeRunId'], 'specific-run');
    },
  );
}
