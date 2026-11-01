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
}
