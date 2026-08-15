import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final host = File(
    'windows/runner/anki_native_window_host.cpp',
  ).readAsStringSync();
  final factory = File('lib/tools/tool_page_factory.dart').readAsStringSync();

  test('ה־host מאמת PID ואת anki.exe לפני SetParent', () {
    expect(host, contains('GetWindowThreadProcessId'));
    expect(host, contains('QueryFullProcessImageNameW'));
    expect(host, contains('L"anki.exe"'));
    expect(
      host.indexOf('ValidateAnkiWindow'),
      lessThan(host.indexOf('SetParent')),
    );
  });

  test('ה־host שומר ומשחזר מצב חלון מקורי', () {
    expect(host, contains('original_parent_'));
    expect(host, contains('original_style_'));
    expect(host, contains('original_extended_style_'));
    expect(host, contains('original_placement_'));
    expect(host, contains('SetWindowPlacement'));
    expect(host, contains('if (container_) ShowWindow(container_, SW_HIDE);'));
  });

  test('המסלול המיוחד מוגבל לתוסף Anki הרשמי ול־Windows', () {
    expect(factory, contains("pluginId == 'org.otzaria.anki'"));
    expect(factory, contains('platform == TargetPlatform.windows'));
  });

  test('כשל בהטמעה חוזר למסלול PluginTabPage', () {
    final view = File(
      'lib/anki_native/view/anki_native_host_view.dart',
    ).readAsStringSync();

    expect(view, contains('state.canUseFallback'));
    expect(view, contains('widget.onFallback()'));
    expect(factory, contains('if (_useMirrorFallback)'));
    expect(factory, contains('return PluginTabPage('));
  });
}
