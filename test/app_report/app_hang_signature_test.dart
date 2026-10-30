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

  group('מחסנית עמוקה: ראש, שורת השמטה ותחתית', () {
    String record(List<String> frames) =>
        '=== App hang 2026-10-30T02:00:00Z ===\n'
        'Message: AppHang: UI thread not responding\n'
        'Stack (module+RVA):\n'
        '${frames.map((f) => '  $f').join('\n')}\n';
    ErrorLogBlock block(List<String> frames) =>
        parseErrorLogBlocks(record(frames)).single;

    // רקורסיית performRebuild/update כמו ב-#3684, ותחתית עם כניסת המנוע.
    final rebuildTop = [
      'app.so+0x1b00010',
      for (var i = 0; i < 47; i++)
        'app.so+0x${(0x1a00000 + (i % 6) * 0x40).toRadixString(16)}',
    ];
    final bottom = [
      for (var i = 0; i < 20; i++)
        'app.so+0x${(0x1c00000 + i * 0x10).toRadixString(16)}',
      for (var i = 0; i < 10; i++)
        'flutter_windows.dll+0x${(0x7fa800 + i).toRadixString(16)}',
      'USER32.dll+0x152e6',
      'otzaria.exe+0x13144',
    ];
    const marker = '... (1234 frames omitted) ...';

    test('החתימה זהה לרשומה ישנה שנחתכה ב-48 פריימים', () {
      final old = block(rebuildTop);
      final deep = block([...rebuildTop, marker, ...bottom]);
      expect(deep.signature.hash, old.signature.hash);
      expect(deep.signature.frames.join(' '), isNot(contains('0x1c0')));
      expect(deep.stackText, contains(marker));
      expect(deep.stackText, contains('otzaria.exe+0x13144'));
    });

    test('ראש נייטיב בלי Dart: פריימי Dart בתחתית אינם משנים את החתימה', () {
      final nativeTop = [
        'ntdll.dll+0x164784',
        for (var i = 0; i < 47; i++)
          'flutter_windows.dll+0x${(0x100000 + i).toRadixString(16)}',
      ];
      final deep = block([...nativeTop, marker, ...bottom]);
      expect(deep.signature.hash, block(nativeTop).signature.hash);
      expect(deep.signature.frames.join(' '), isNot(contains('app.so')));
    });

    test('מחסנית בלי השמטה, ארוכה מ-48: החתימה רק מ-48 העליונים', () {
      final longer = [...rebuildTop, ...bottom.take(20)];
      expect(block(longer).signature.hash, block(rebuildTop).signature.hash);
    });

    test('שורת ההשמטה אינה פריים בחתימה הכללית', () {
      expect(CrashSignature.normalizeFrame('  $marker'), isNull);
      const atLimit = '... (8112 frames omitted, unwind limit reached) ...';
      expect(
        block([...rebuildTop, atLimit, ...bottom]).signature.hash,
        block(rebuildTop).signature.hash,
      );
    });
  });
}
