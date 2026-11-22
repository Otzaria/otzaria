import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/app_report/repository/app_report_collector.dart';
import 'package:otzaria/app_report/repository/error_log_blocks.dart';
import 'package:otzaria/app_report/services/android_hang_monitor.dart';
import 'package:otzaria/core/error_log_file.dart';

/// רשומה בפורמט שכותב android/.../HangMonitorChannel.kt.
String androidHangEntry(
  DateTime at, {
  String id = '42-123-1',
  List<String>? frames,
}) =>
    '\n=== App hang ${at.toUtc().toIso8601String()} ===\n'
    'Version: 0.9.98+99803\n'
    'Message: AppHang: UI thread not responding\n'
    'Hang ID: $id\n'
    'Detected: 120000ms after launch\n'
    'Unanswered: 5012ms\n'
    'Resumed: 230ms before the probe\n'
    'Stack:\n'
    '${(frames ?? const ['android.os.MessageQueue.nativePollOnce(Native Method)', 'android.os.MessageQueue.next(MessageQueue.java:335)', 'android.os.Looper.loop(Looper.java:183)', 'android.app.ActivityThread.main(ActivityThread.java:7656)']).map((f) => '  at $f').join('\n')}\n';

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

    test('חותמת הזמן בפורמט שכותב Kotlin, כולל מילישניות', () {
      final blocks = parseErrorLogBlocks(
        '\n=== App hang 2026-11-20T10:00:00.123Z ===\n'
        'Message: AppHang: UI thread not responding\n'
        'Stack:\n'
        '  at android.os.MessageQueue.nativePollOnce(Native Method)\n'
        '\n=== App hang recovered 2026-11-20T10:00:07.654Z ===\n'
        'Duration: 7400ms\n',
      );
      expect(blocks.first.isAppHang, isTrue);
      expect(blocks.first.timestamp, DateTime.utc(2026, 11, 20, 10, 0, 0, 123));
      expect(blocks.last.isAppHangRecovered, isTrue);
      expect(blocks.last.timestamp, DateTime.utc(2026, 11, 20, 10, 0, 7, 654));
    });
  });

  group('הודעת התאוששות', () {
    const id = '42-123-1';
    const duration = Duration(milliseconds: 7400);
    final at = DateTime.utc(2026, 11, 20, 10, 0, 0, 123);
    final record = androidHangEntry(
      at,
      id: id,
      frames: const [
        'org.otzaria.otzaria.FolderImportChannel.copy(FolderImportChannel.kt:88)',
      ],
    );

    test('הדיווח כולל את המחסנית והמשך של האירוע המזוהה', () {
      final candidate = AndroidHangMonitor.candidateForRecovery({
        'hangId': id,
        'record': record,
      }, duration);
      expect(candidate!.occurredInPreviousRun, isFalse);
      expect(candidate.hangDuration, duration);
      expect(candidate.entries.single.timestamp, at);
      expect(candidate.details, contains('Hang ID: $id'));
      expect(candidate.signature!.frames, [
        'org.otzaria.otzaria.FolderImportChannel.copy',
      ]);
    });

    test('רשומה מאירוע אחר או זנב מעורב אינם משויכים להתאוששות', () {
      final otherRecord = androidHangEntry(at, id: '42-123-2');
      for (final text in [otherRecord, '$record$otherRecord']) {
        expect(
          AndroidHangMonitor.candidateForRecovery({
            'hangId': id,
            'record': text,
          }, duration),
          isNull,
        );
      }
    });

    test('רשומת תקיעה בלי התאוששות זמינה לצירוף בדיווח ידני', () async {
      final tmp = await Directory.systemTemp.createTemp('otzaria_hang_');
      addTearDown(() => tmp.delete(recursive: true));
      final log = await File.fromUri(
        tmp.uri.resolve('errors.txt'),
      ).writeAsString(record);
      final collector = AppReportCollector(
        errorLogPath: log.path,
        clock: () => at.add(const Duration(hours: 1)),
      );
      final excerpt = await collector.collectErrorLog();
      expect(excerpt, contains('Hang ID: $id'));
      expect(excerpt, contains('FolderImportChannel.copy'));
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
    expect(called, isFalse);
  });
}
