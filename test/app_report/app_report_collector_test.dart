import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/app_report/repository/app_report_collector.dart';
import 'package:otzaria/app_report/repository/app_report_redactor.dart';
import 'package:otzaria/app_report/repository/error_log_blocks.dart';
import 'package:otzaria/core/info/os_version.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  final now = DateTime(2026, 9, 17, 12);
  final redactor = AppReportRedactor(
    environment: const {'USERPROFILE': r'C:\Users\Moshe', 'USERNAME': 'Moshe'},
  );

  setUp(() => tmp = Directory.systemTemp.createTempSync('otzaria_collector_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  String entry(String title, DateTime at, [String body = '']) =>
      '=== $title ${at.toIso8601String()} ===\nVersion: 1\n$body\n';

  test('אבחון: מקטע שנכשל נרשם כשגיאה ושאר המקטעים נאספים ומוסתרים', () async {
    final collector = AppReportCollector(
      redactor: redactor,
      appInfoLoader: () async => throw StateError('library not loaded'),
      openTabCounts: () async => {'text': 2, 'pdf': 1},
      errorLogPath: p.join(tmp.path, 'missing.txt'),
      clock: () => now,
    );
    final diagnostics = await collector.collectDiagnostics();
    expect(diagnostics['appInfo'], {
      'error': 'Bad state: library not loaded',
    });
    expect(diagnostics['system'], containsPair('arch', isA<String>()));
    expect(diagnostics['openTabs'], {'text': 2, 'pdf': 1});
    expect(diagnostics['startupTimeline'], contains('lines'));
    expect(() => jsonEncode(diagnostics), returnsNormally);
  });

  test('אבחון: פרופיל המשתמש מוסתר בכל המבנה', () async {
    final collector = AppReportCollector(
      redactor: redactor,
      appInfoLoader: () async => {
        'app': {'dataRootPath': r'C:\Users\Moshe\AppData\Roaming\otzaria'},
      },
      clock: () => now,
    );
    final diagnostics = await collector.collectDiagnostics();
    expect(
      (diagnostics['appInfo'] as Map)['app'],
      {'dataRootPath': r'%USERPROFILE%\AppData\Roaming\otzaria'},
    );
  });

  test('לוג: רק השבוע האחרון, מסודר כרונולוגית, עם לוג הסגירה', () async {
    final errors = File(p.join(tmp.path, 'errors.txt'))
      ..writeAsStringSync(
        'tail of a cut block\n'
        '${entry('Old', now.subtract(const Duration(days: 8)))}'
        '${entry('Recent A', now.subtract(const Duration(days: 2)), r'Path: C:\Users\Moshe\x')}'
        '${entry('Recent B', now.subtract(const Duration(hours: 1)))}',
      );
    final shutdown = File(p.join(tmp.path, 'shutdown.log'))
      ..writeAsStringSync(
        '${now.subtract(const Duration(days: 30)).toIso8601String()} | old\n'
        '${now.subtract(const Duration(days: 1)).toIso8601String()} | forced\n',
      );
    final collector = AppReportCollector(
      redactor: redactor,
      errorLogPath: errors.path,
      shutdownLogPath: shutdown.path,
      clock: () => now,
    );
    final log = await collector.collectErrorLog();
    expect(log, isNot(contains('Old')));
    expect(log, isNot(contains('tail of a cut block')));
    expect(log.indexOf('Recent A'), lessThan(log.indexOf('Recent B')));
    expect(log, contains(r'%USERPROFILE%\x'));
    expect(log, contains('| forced'));
    expect(log, isNot(contains('| old')));
  });

  test('לוג: קבצים חסרים מחזירים טקסט ריק', () async {
    final collector = AppReportCollector(
      redactor: redactor,
      errorLogPath: tmp.path,
      shutdownLogPath: p.join(tmp.path, 'none.log'),
      clock: () => now,
    );
    final log = await collector.collectErrorLog();
    expect(log, isEmpty);
  });

  test('recentErrorLogExcerpt שומר את החדשות בגבול הגודל', () {
    final content = [
      for (var i = 0; i < 10; i++)
        entry('E$i', now.subtract(Duration(hours: 10 - i)), 'x' * 100),
    ].join();
    final excerpt = recentErrorLogExcerpt(
      content,
      since: now.subtract(const Duration(days: 7)),
      maxBytes: 450,
    );
    expect(excerpt, contains('E9'));
    expect(excerpt, isNot(contains('E0')));
    expect(utf8.encode(excerpt).length, lessThanOrEqualTo(450));
  });

  test('detectArch: אמולציית x64 על ARM', () {
    expect(
      AppReportCollector.detectArch(
        abi: Abi.windowsX64,
        environment: const {'PROCESSOR_IDENTIFIER': 'ARMv8 (64-bit) Family 8'},
      ),
      'x64-on-arm64',
    );
    expect(
      AppReportCollector.detectArch(
        abi: Abi.windowsX64,
        environment: const {'PROCESSOR_IDENTIFIER': 'Intel64 Family 6'},
      ),
      'x64',
    );
    expect(AppReportCollector.detectArch(abi: Abi.windowsArm64), 'arm64');
  });

  test('osVersion: הדיווח והאבחון מתקנים Windows 11 שמדווח כ-Windows 10', () {
    expect(
      AppReportCollector.osVersion(
        raw: '"Windows 10 Pro" 10.0 (Build 26100)',
        isWindows: true,
      ),
      '"Windows 11 Pro" 10.0 (Build 26100)',
    );
    expect(AppReportCollector.systemInfo()['osVersion'], displayOsVersion());
  });
}
