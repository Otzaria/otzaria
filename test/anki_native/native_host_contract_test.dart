import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final host = File(
    'windows/runner/anki_native_window_host.cpp',
  ).readAsStringSync();
  final factory = File('lib/tools/tool_page_factory.dart').readAsStringSync();
  final flutterWindow = File(
    'windows/runner/flutter_window.cpp',
  ).readAsStringSync();
  final repository = File(
    'lib/anki_native/repository/anki_native_repository.dart',
  ).readAsStringSync();
  final view = File(
    'lib/anki_native/view/anki_native_host_view.dart',
  ).readAsStringSync();

  test('ה־host מאמת PID ואת anki.exe לפני צירוף', () {
    expect(host, contains('GetWindowThreadProcessId'));
    expect(host, contains('QueryFullProcessImageNameW'));
    expect(host, contains('L"anki.exe"'));
    expect(host, contains('GetParent(target) != container_'));
  });

  test('הצירוף מוכן בליבה ומבוצע ב־Qt של Anki', () {
    expect(flutterWindow, contains('call.method_name() == "prepare"'));
    expect(repository, contains("invokeMethod<int>('prepare')"));
    expect(repository, contains("'containerHwnd':"));
    expect(repository, contains("'/v1/native/resize'"));
    expect(repository, contains("code.startsWith('native_')"));
    expect(repository, contains("code == 'stale_container'"));
    expect(repository, contains('_closeClient = _detachAndCloseClient'));
    expect(repository, contains('await detach();'));
    expect(host, isNot(contains('SetParent(')));
    expect(host, isNot(contains('SetWindowPos(target_')));
    expect(host, isNot(contains('SetWindowLongPtr(target_')));
    expect(view, contains('crossAxisAlignment: CrossAxisAlignment.stretch'));
    expect(view, contains('context.findRenderObject()'));
    expect(view, isNot(contains('_viewportKey.currentContext')));
    expect(host, contains('if (container_) ShowWindow(container_, SW_HIDE);'));
  });

  test('המסלול המיוחד מוגבל לתוסף Anki הרשמי ול־Windows', () {
    expect(factory, contains("pluginId == 'org.otzaria.anki'"));
    expect(factory, contains('platform == TargetPlatform.windows'));
  });

  test('כשל בהטמעה חוזר למסלול PluginTabPage', () {
    expect(view, contains('state.canUseFallback'));
    expect(view, contains('widget.onFallback()'));
    expect(factory, contains('if (_useMirrorFallback)'));
    expect(factory, contains('return PluginTabPage('));
  });
}
