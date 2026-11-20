import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/app_report/repository/error_log_blocks.dart';
import 'package:otzaria/app_report/services/android_hang_monitor.dart';
import 'package:otzaria/app_report/services/unclean_exit_detector.dart';
import 'package:otzaria/core/error_log_file.dart';
import 'package:path/path.dart' as p;

/// רשומה בפורמט שכותב android/.../HangMonitorChannel.kt.
String androidHangEntry(DateTime at, {List<String>? frames}) =>
    '\n=== App hang ${at.toUtc().toIso8601String()} ===\n'
    'Version: 0.9.98+99803\n'
    'Message: AppHang: UI thread not responding\n'
    'Detected: 120000ms after launch\n'
    'Unanswered: 5012ms\n'
    'Resumed: 230ms before the hang\n'
    'Stack:\n'
    '${(frames ?? const ['android.os.MessageQueue.nativePollOnce(Native Method)', 'android.os.MessageQueue.next(MessageQueue.java:335)', 'android.os.Looper.loop(Looper.java:183)', 'android.app.ActivityThread.main(ActivityThread.java:7656)']).map((f) => '  at $f').join('\n')}\n';

String recoveredEntry(DateTime at) =>
    '\n=== App hang recovered ${at.toUtc().toIso8601String()} ===\n'
    'Duration: 7400ms\n';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('חתימה של תקיעה באנדרואיד', () {
    test('נבחרים פריימי האפליקציה מתוך מחסנית Java', () {
      final signature = parseErrorLogBlocks(
        androidHangEntry(
          DateTime.utc(2026, 11, 20, 10),
          frames: const [
            'java.io.FileInputStream.readBytes(Native Method)',
            'org.otzaria.otzaria.FolderImportChannel.copy(FolderImportChannel.kt:88)',
            'android.os.Looper.loop(Looper.java:183)',
          ],
        ),
      ).single.signature;
      expect(signature.exceptionType, 'AppHang');
      expect(signature.frames, [
        'org.otzaria.otzaria.FolderImportChannel.copy',
      ]);
    });

    test(
      'תקיעה ב-Dart או במנוע (ראש המחסנית nativePollOnce) — חתימה קבועה',
      () {
        final signature = parseErrorLogBlocks(
          androidHangEntry(DateTime.utc(2026, 11, 20, 10)),
        ).single.signature;
        expect(signature.frames, [
          'MessageQueue.nativePollOnce (Dart or engine)',
        ]);
      },
    );

    test('חותמת הזמן בפורמט שכותב Kotlin, בלי מילישניות', () {
      final blocks = parseErrorLogBlocks(
        '\n=== App hang 2026-11-20T10:00:00Z ===\n'
        'Message: AppHang: UI thread not responding\n'
        'Stack:\n'
        '  at android.os.MessageQueue.nativePollOnce(Native Method)\n'
        '\n=== App hang recovered 2026-11-20T10:00:07Z ===\n'
        'Duration: 7400ms\n',
      );
      expect(blocks.first.isAppHang, isTrue);
      expect(blocks.first.timestamp, DateTime.utc(2026, 11, 20, 10));
      expect(blocks.last.isAppHangRecovered, isTrue);
      expect(blocks.last.timestamp, DateTime.utc(2026, 11, 20, 10, 0, 7));
    });
  });

  group('תקיעה שלא השתחררה בהפעלה קודמת', () {
    late Directory tmp;
    final previousStart = DateTime.utc(2026, 11, 19, 8);
    final thisStart = DateTime.utc(2026, 11, 20, 8);

    setUp(() => tmp = Directory.systemTemp.createTempSync('otzaria_hang_a_'));
    tearDown(() => tmp.deleteSync(recursive: true));

    UncleanExitDetector detector() => UncleanExitDetector(
      logsDirectory: tmp.path,
      sentryDatabaseDirs: const [],
      isProcessAlive: (_) => false,
      processStartedAt: thisStart,
    );

    void writeErrors(String content) =>
        File(p.join(tmp.path, 'errors.txt')).writeAsStringSync(content);

    AndroidHangMonitor monitor() => AndroidHangMonitor(
      stateFilePath: p.join(tmp.path, AndroidHangMonitor.stateFileName),
      detector: detector(),
      processStartedAt: () => thisStart,
      isAndroid: true,
    );

    void writeWatermark(DateTime at) =>
        File(
          p.join(tmp.path, AndroidHangMonitor.stateFileName),
        ).writeAsStringSync(
          jsonEncode({'lastCheckedMs': at.millisecondsSinceEpoch}),
        );

    test('תקיעה בלי שחרור — מועמד מהפעלה קודמת', () async {
      writeErrors(
        androidHangEntry(previousStart.add(const Duration(hours: 1))),
      );
      final candidate = await detector().detectUnrecoveredHang(
        since: previousStart,
      );
      expect(candidate!.isHang, isTrue);
      expect(candidate.occurredInPreviousRun, isTrue);
      expect(candidate.signature!.exceptionType, 'AppHang');
    });

    test('תקיעה שהשתחררה כבר דווחה בזמן ריצה — אין מועמד', () async {
      final at = previousStart.add(const Duration(hours: 1));
      writeErrors(
        androidHangEntry(at) +
            recoveredEntry(at.add(const Duration(seconds: 7))),
      );
      expect(
        await detector().detectUnrecoveredHang(since: previousStart),
        isNull,
      );
    });

    test('תקיעה של התהליך הנוכחי אינה של הפעלה קודמת', () async {
      writeErrors(androidHangEntry(thisStart.add(const Duration(minutes: 1))));
      expect(
        await detector().detectUnrecoveredHang(since: previousStart),
        isNull,
      );
    });

    test('הרצה ראשונה רק שומרת סימן-מים, גם כשיש תקיעה ישנה', () async {
      writeErrors(
        androidHangEntry(previousStart.add(const Duration(hours: 1))),
      );
      expect(await monitor().takeUnrecoveredHang(), isNull);
      expect(
        File(p.join(tmp.path, AndroidHangMonitor.stateFileName)).existsSync(),
        isTrue,
      );
    });

    test('כל תקיעה מוצעת פעם אחת', () async {
      writeWatermark(previousStart);
      writeErrors(
        androidHangEntry(previousStart.add(const Duration(hours: 1))),
      );
      expect(await monitor().takeUnrecoveredHang(), isNotNull);
      expect(await monitor().takeUnrecoveredHang(), isNull);
    });
  });

  test('start מעביר לנייטיב את נתיב הלוג ואת הגרסה', () async {
    const channel = MethodChannel('otzaria/hang_monitor_test');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    await AndroidHangMonitor(channel: channel, isAndroid: true).start();

    expect(calls.single.method, 'start');
    expect(calls.single.arguments, {
      'logPath': ErrorLogFile.resolvePath(),
      'version': ErrorLogFile.appVersion,
    });
  });

  test('מחוץ לאנדרואיד אין קריאה לנייטיב', () async {
    const channel = MethodChannel('otzaria/hang_monitor_test');
    var called = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          called = true;
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    await AndroidHangMonitor(channel: channel, isAndroid: false).start();
    expect(
      await AndroidHangMonitor(isAndroid: false).takeUnrecoveredHang(),
      isNull,
    );
    expect(called, isFalse);
  });
}
