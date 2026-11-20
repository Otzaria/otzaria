import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'ה-runner כופה מצב HWND עבור WebView בחיבור מרוחק (RDP) כשלא הוגדר אחרת',
    () {
      final runnerSource = File('windows/runner/main.cpp').readAsStringSync();
      expect(runnerSource, contains('SM_REMOTESESSION'));
      expect(runnerSource, contains('FLUTTER_INAPPWEBVIEW_WINDOWS_FORCE_HWND'));
      expect(
        runnerSource,
        matches(
          RegExp(
            r'::GetSystemMetrics\(SM_REMOTESESSION\).*?::SetEnvironmentVariableW\(L"FLUTTER_INAPPWEBVIEW_WINDOWS_FORCE_HWND",\s*L"1"\)',
            dotAll: true,
          ),
        ),
      );
    },
  );

  test('לפני Windows 1903 ה-runner כופה HWND (קריסת GraphicsCapture, #4211)', () {
    final runnerSource = File('windows/runner/main.cpp').readAsStringSync();
    final policy = File(
      'windows/runner/webview_backend_policy.h',
    ).readAsStringSync();
    // ההחלטה נבדקת ב-static_assert בכל בניית Windows; כאן רק החיווט שלה.
    expect(policy, contains('kFirstReliableCaptureBuild = 18362'));
    for (final check in [
      'ShouldForceHwnd(false, 17763)',
      '!ShouldForceHwnd(false, 18362)',
      'ShouldForceHwnd(true, 26100)',
    ]) {
      expect(policy, contains('static_assert($check'));
    }
    expect(
      runnerSource,
      matches(
        RegExp(
          r'ShouldForceHwnd\(\s*::GetSystemMetrics\(SM_REMOTESESSION\) != 0,\s*webview_backend_policy::WindowsBuildNumber\(\)\)',
        ),
      ),
    );
  });
}
