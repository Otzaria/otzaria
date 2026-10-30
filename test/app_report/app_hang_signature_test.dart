import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/app_report/repository/error_log_blocks.dart';
import 'package:otzaria_report_contract/otzaria_report_contract.dart';

/// רשומות תקיעה אמיתיות מגרסה 0.9.98+99802 (אותו build-id), המחסנית הראשית בלבד.
final Map<String, ErrorLogBlock> _records = {
  for (final block in parseErrorLogBlocks(
    File('test/fixtures/app_report/app_hang_records.txt').readAsStringSync(),
  ))
    block.timestamp!.toUtc().toIso8601String(): block,
};

CrashSignature _signatureAt(String timestamp) =>
    _records[DateTime.parse(timestamp).toIso8601String()]!.signature;

// existsSync מ-resolveMovedFileBookPath, בעומק רקורסיה 5 ו-4 (#3650).
const _movedBookDepth5 = '2026-10-30T01:57:16Z';
const _movedBookDepth4 = '2026-10-30T06:47:41Z';
// existsSync מ-_BackgroundPluginRunnerState.build.
const _pluginRunnerExists = '2026-10-28T07:36:13Z';
// sqlite3_step מ-PluginSystemDatabase.setPluginKV ומ-WindowSessionStore.save.
const _pluginKvStep = '2026-10-27T17:28:46Z';
const _windowSessionStep = '2026-10-28T22:45:32Z';
// removeListener בפירוק עץ, כשהמנוע באמצע קריאה אחרת מעל Dart.
const _unmountA = '2026-10-28T19:49:00Z';
const _unmountB = '2026-10-28T12:08:28Z';
// deleteSync מ-CompanionAssetsService._ensureTalmud (#3654).
const _companionDelete = '2026-10-27T23:06:43Z';

void main() {
  test('אותה סיבה בעומק רקורסיה שונה — אותה חתימה', () {
    expect(
      _signatureAt(_movedBookDepth4).hash,
      _signatureAt(_movedBookDepth5).hash,
    );
  });

  test('אותה קריאת SDK מקוראים שונים — חתימות שונות', () {
    expect(
      _signatureAt(_pluginRunnerExists).hash,
      isNot(_signatureAt(_movedBookDepth5).hash),
    );
    expect(
      _signatureAt(_windowSessionStep).hash,
      isNot(_signatureAt(_pluginKvStep).hash),
    );
    expect(
      _signatureAt(_companionDelete).hash,
      isNot(_signatureAt(_movedBookDepth5).hash),
    );
  });

  test('פריימי המנוע מעל Dart משתנים בין דגימות ואינם בחתימה', () {
    expect(_signatureAt(_unmountB).hash, _signatureAt(_unmountA).hash);
  });

  test('החתימה רק מפריימי app.so, בגבולות שהשרת מקבל', () {
    final signature = _signatureAt(_movedBookDepth5);
    expect(signature.exceptionType, 'AppHang');
    expect(signature.frames, [
      'app.so+0x2361b43 app.so+0x11d6562 app.so+0x22125c0 app.so+0x184c2ff',
      'app.so+0x186ef8d app.so+0x186dc59 app.so+0x186e57f app.so+0x186df5e',
    ]);
    for (final record in _records.values) {
      final frames = record.signature.frames;
      expect(frames.length, lessThanOrEqualTo(CrashSignature.maxFrames));
      for (final frame in frames) {
        expect(frame.length, lessThanOrEqualTo(CrashSignature.maxFrameLength));
        expect(frame, isNot(contains('flutter_windows.dll')));
      }
    }
  });

  test('Dart בראש המחסנית: ה-PC של הקוד הרץ אינו בחתימה', () {
    // מחסנית אמיתית (firstWhere בזמן פענוח דיווחים ממתינים), בשתי נקודות בלולאה.
    String record(String pc) =>
        '=== App hang 2026-10-27T01:28:00Z ===\n'
        'Message: AppHang: UI thread not responding\n'
        'Stack (module+RVA):\n'
        '  $pc\n'
        '  app.so+0x1922320\n'
        '  app.so+0x1921968\n'
        '  app.so+0x191e56e\n'
        '  app.so+0x1922a23\n'
        '  app.so+0x104c41e\n'
        '  flutter_windows.dll+0x7fa80b\n';
    final a = parseErrorLogBlocks(record('app.so+0x153b585')).single.signature;
    final b = parseErrorLogBlocks(record('app.so+0x153b5a1')).single.signature;
    expect(b.hash, a.hash);
    expect(a.frames.first, startsWith('app.so+0x1922320 '));
  });
}
