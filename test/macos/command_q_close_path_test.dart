import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// ⌘Q מגיע ל-NSApplication ולא ל-NSWindow, ולכן אי אפשר לכסות אותו בבדיקת
/// widget. בדיקת החוזה נועלת את הגשר בין ה-runner למסלול הסגירה של Dart.
void main() {
  final appDelegate = File('macos/Runner/AppDelegate.swift').readAsStringSync();
  final mainWindow = File(
    'macos/Runner/MainFlutterWindow.swift',
  ).readAsStringSync();
  final listener = File('lib/core/window_listener.dart').readAsStringSync();
  final bootstrap = File('lib/main.dart').readAsStringSync();

  test('⌘Q מנותב לרצף היציאה של Dart עד ש-Dart מתיר סיום', () {
    expect(appDelegate, contains('applicationShouldTerminate('));
    expect(appDelegate, contains('window.applicationShouldTerminate()'));
    expect(mainWindow, contains('otzaria/macos_termination'));
    expect(mainWindow, contains('case "enableCloseHandling"'));
    expect(mainWindow, contains('case "allowTermination"'));
    expect(mainWindow, contains('invokeMethod("quitRequested"'));
    expect(listener, contains("'quitRequested'"));
    expect(listener, contains('handleWindowClose(quit: true)'));
    expect(mainWindow, contains('return .terminateCancel'));
    expect(mainWindow, contains('return .terminateNow'));
    expect(bootstrap, contains('AppWindowListener.enableMacOSCloseHandling()'));

    final allow = listener.indexOf('allowMacOSApplicationTermination();');
    final quit = listener.indexOf('await _window.quitApplication();');
    expect(allow, greaterThanOrEqualTo(0));
    expect(quit, greaterThan(allow));
  });

  test('סגירת החלון האחרון משאירה את האפליקציה ב-Dock', () {
    expect(appDelegate, contains('applicationShouldHandleReopen('));
    expect(appDelegate, contains('restoreLastClosedWindow()'));
    final hide = mainWindow.indexOf('private func hide(');
    final hideEnd = mainWindow.indexOf('func showMainWindow(');
    expect(
      mainWindow.substring(hide, hideEnd),
      isNot(contains('exit(')),
      reason: 'הסתרת החלון האחרון אינה מסיימת את התהליך',
    );
  });

  test('סגירה במסך מלא יוצאת ממנו לפני ההסתרה (#3551)', () {
    final hide = mainWindow.indexOf('private func hide(');
    final hideEnd = mainWindow.indexOf('func showMainWindow(');
    final body = mainWindow.substring(hide, hideEnd);
    final fullScreen = body.indexOf('styleMask.contains(.fullScreen)');
    final toggle = body.indexOf('window.toggleFullScreen(nil)');
    expect(fullScreen, inInclusiveRange(0, toggle));
    expect(
      body.indexOf('isMainHidden = true'),
      greaterThan(toggle),
      reason: 'orderOut במסך מלא משאיר Space שחור',
    );
    expect(mainWindow, contains('NSWindow.didExitFullScreenNotification'));
    expect(mainWindow, contains('NSWindow.didEnterFullScreenNotification'));
  });
}
