import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// מסלול כיבוי התהליך מסתיים ב-`exit(0)` ואינו ניתן להרצה בבדיקה, ולכן
/// נועלים את סדר הצעדים במקור (#3735).
void main() {
  final listener = File('lib/core/window_listener.dart').readAsStringSync();

  String body(String start, String end) {
    final from = listener.indexOf(start);
    expect(from, greaterThanOrEqualTo(0), reason: start);
    final to = listener.indexOf(end, from);
    expect(to, greaterThan(from), reason: end);
    return listener.substring(from, to);
  }

  test('החלון מוסתר רק אחרי אישורי היציאה, ולפני צעדי הכיבוי הכבדים', () {
    final close = body(
      'Future<void> _handleWindowClose(',
      'Future<void> quitFromLastViewWindow(',
    );
    final cleanExit = close.indexOf('AppCrashSession.markCleanExitSync();');
    expect(
      close.indexOf('finishPreparedProcessCorrectionQuit()'),
      inInclusiveRange(0, cleanExit),
    );
    expect(
      close.indexOf('await _shutdownProcessUpToFlush();'),
      greaterThan(cleanExit),
    );
    expect(close, isNot(contains('windowManager.hide')));

    final shutdown = body(
      'Future<void> _shutdownProcessUpToFlush(',
      'Future<Object?> _closeWindowScoped(',
    );
    final watchdog = shutdown.indexOf("'armForceExitWatchdog'");
    final hide = shutdown.indexOf('windowManager.hide');
    expect(watchdog, greaterThanOrEqualTo(0));
    expect(hide, greaterThan(watchdog));
    for (final step in const [
      "'prepareForAppShutdown'",
      "'shutdownForAppExit'",
      'SqliteDataProvider.instance.dispose',
    ]) {
      expect(shutdown.indexOf(step), greaterThan(hide), reason: step);
    }
  });
}
