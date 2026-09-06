import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/info/app_info_cli.dart';
import 'package:otzaria/core/info/app_info_service.dart';
import 'package:otzaria/core/info/info_topic.dart';
import 'package:otzaria/core/info/personal_folders_info.dart';

void main() {
  late StringBuffer out;
  late StringBuffer err;

  setUp(() {
    out = StringBuffer();
    err = StringBuffer();
  });

  AppInfoReport reportFor(
    AppInfoCliRequest request, {
    bool settingsLoaded = true,
  }) => AppInfoReport(
    topic: request.topic,
    generatedAt: DateTime.parse('2026-08-20T14:32:00.000'),
    settingsLoaded: settingsLoaded,
    sections: {
      for (final section in request.topic.sections)
        section.slug: {'limit': request.errorLimit},
    },
  );

  Future<int> run(List<String> args) => AppInfoCli.run(
    args,
    out: out,
    err: err,
    collect: (request) async => reportFor(request),
  );

  group('parseArgs', () {
    test('ללא ארגומנטים — דוח מלא עם ברירות מחדל', () {
      final request = AppInfoCli.parseArgs(const [], err)!;

      expect(request.topic, InfoTopic.all);
      expect(request.errorLimit, 5);
      expect(request.fileLimit, PersonalFoldersInfo.defaultFileLimit);
      expect(request.compact, isFalse);
      expect(request.help, isFalse);
    });

    test('נושא מפורש, כולל alias', () {
      expect(AppInfoCli.parseArgs(['app'], err)!.topic, InfoTopic.app);
      expect(AppInfoCli.parseArgs(['logs'], err)!.topic, InfoTopic.errors);
      expect(AppInfoCli.parseArgs(['LIBRARY'], err)!.topic, InfoTopic.library);
    });

    test('--limit ו---compact', () {
      final request = AppInfoCli.parseArgs([
        'errors',
        '--limit=20',
        '--compact',
      ], err)!;

      expect(request.topic, InfoTopic.errors);
      expect(request.errorLimit, 20);
      expect(request.compact, isTrue);
    });

    test('--out קולט נתיב', () {
      final request = AppInfoCli.parseArgs(['app', '--out=r.json'], err)!;

      expect(request.outPath, 'r.json');
    });

    test('--out ריק נדחה', () {
      expect(AppInfoCli.parseArgs(['--out='], err), isNull);
      expect(err.toString(), contains('--out'));
    });

    test('--help עוצר את הפענוח', () {
      expect(AppInfoCli.parseArgs(['app', '--help'], err)!.help, isTrue);
      expect(AppInfoCli.parseArgs(['-h'], err)!.help, isTrue);
    });

    test('נושא לא מוכר נדחה עם הודעה', () {
      expect(AppInfoCli.parseArgs(['banana'], err), isNull);
      expect(err.toString(), contains('נושא לא מוכר'));
    });

    test('שני נושאים נדחים', () {
      expect(AppInfoCli.parseArgs(['app', 'library'], err), isNull);
      expect(err.toString(), contains('נושא אחד בלבד'));
    });

    test('--limit לא חוקי נדחה', () {
      for (final raw in ['--limit=0', '--limit=-3', '--limit=abc']) {
        final localErr = StringBuffer();
        expect(AppInfoCli.parseArgs([raw], localErr), isNull, reason: raw);
        expect(localErr.toString(), contains('--limit'));
      }
    });

    test('--files קולט מספר, כולל 0', () {
      expect(
        AppInfoCli.parseArgs(['folders', '--files=200'], err)!.fileLimit,
        200,
      );
      expect(
        AppInfoCli.parseArgs(['folders', '--files=0'], err)!.fileLimit,
        0,
      );
    });

    test('--files אינו כפוף לתקרת ה-URI', () {
      expect(AppInfoCli.parseArgs(['--files=100000'], err)!.fileLimit, 100000);
    });

    test('--files לא חוקי נדחה', () {
      for (final raw in ['--files=-1', '--files=abc', '--files=']) {
        final localErr = StringBuffer();
        expect(AppInfoCli.parseArgs([raw], localErr), isNull, reason: raw);
        expect(localErr.toString(), contains('--files'));
      }
    });

    test('דגל לא מוכר נדחה', () {
      expect(AppInfoCli.parseArgs(['--verbose'], err), isNull);
      expect(err.toString(), contains('דגל לא מוכר'));
    });
  });

  group('run', () {
    test('מדפיס JSON מוזח ל-stdout ומחזיר 0', () async {
      final code = await run(['app']);

      expect(code, AppInfoCliExitCode.success);
      expect(err.toString(), isEmpty);
      final decoded = jsonDecode(out.toString()) as Map<String, dynamic>;
      expect(decoded['topic'], 'app');
      // UTC עם סיומת Z — לא נאיבי, ובלי לקבע את אזור הזמן של מריץ הבדיקה.
      expect(
        decoded['generatedAt'],
        DateTime.parse('2026-08-20T14:32:00.000').toUtc().toIso8601String(),
      );
      expect(decoded['generatedAt'], endsWith('Z'));
      expect(decoded['settingsLoaded'], isTrue);
      expect(decoded.containsKey('app'), isTrue);
      // מוזח = יותר משורה אחת.
      expect(out.toString().trim().split('\n').length, greaterThan(1));
    });

    test('--compact מדפיס שורה אחת', () async {
      final code = await run(['app', '--compact']);

      expect(code, AppInfoCliExitCode.success);
      expect(out.toString().trim().split('\n'), hasLength(1));
      expect(jsonDecode(out.toString())['topic'], 'app');
    });

    test('דוח מלא מכיל את כל ארבעת המקטעים', () async {
      await run(const []);

      final decoded = jsonDecode(out.toString()) as Map<String, dynamic>;
      expect(decoded['topic'], 'all');
      for (final slug in ['app', 'library', 'plugins', 'errors']) {
        expect(decoded.containsKey(slug), isTrue, reason: slug);
      }
    });

    test('settingsLoaded=false נכנס ל-JSON — דוח ברירות מחדל מסומן', () async {
      await AppInfoCli.run(
        const ['app'],
        out: out,
        err: err,
        collect: (request) async => reportFor(request, settingsLoaded: false),
      );

      expect(jsonDecode(out.toString())['settingsLoaded'], isFalse);
    });

    test('--limit מועבר לאיסוף', () async {
      await run(['errors', '--limit=20']);

      final decoded = jsonDecode(out.toString()) as Map<String, dynamic>;
      expect((decoded['errors'] as Map)['limit'], 20);
    });

    test('--help מדפיס שימוש ל-stdout ומחזיר 0', () async {
      final code = await run(['--help']);

      expect(code, AppInfoCliExitCode.success);
      expect(out.toString(), contains('otzaria info'));
      expect(out.toString(), contains('--compact'));
    });

    test('שגיאת שימוש מחזירה 64 בלי פלט ל-stdout', () async {
      final code = await run(['banana']);

      expect(code, AppInfoCliExitCode.usageError);
      expect(out.toString(), isEmpty);
      expect(err.toString(), isNotEmpty);
    });

    test('--out כותב לקובץ ולא ל-stdout', () async {
      String? writtenPath;
      String? writtenJson;

      final code = await AppInfoCli.run(
        const ['app', '--out=report.json', '--compact'],
        out: out,
        err: err,
        collect: (request) async => reportFor(request),
        writeFile: (path, json) async {
          writtenPath = path;
          writtenJson = json;
        },
      );

      expect(code, AppInfoCliExitCode.success);
      expect(out.toString(), isEmpty);
      expect(writtenPath, 'report.json');
      expect(jsonDecode(writtenJson!)['topic'], 'app');
    });

    test('כשל בכתיבה לקובץ מחזיר 1', () async {
      final code = await AppInfoCli.run(
        const ['app', '--out=/nope/report.json'],
        out: out,
        err: err,
        collect: (request) async => reportFor(request),
        writeFile: (path, json) async =>
            throw FileSystemException('תיקייה חסרה', path),
      );

      expect(code, AppInfoCliExitCode.collectFailed);
      expect(err.toString(), contains('תיקייה חסרה'));
    });

    test('print במהלך האיסוף מנותב ל-stderr ולא מזהם את ה-JSON', () async {
      final code = await AppInfoCli.run(
        const ['app', '--compact'],
        out: out,
        err: err,
        collect: (request) async {
          // ignore: avoid_print
          print('רעש מתלות כלשהי');
          return reportFor(request);
        },
      );

      expect(code, AppInfoCliExitCode.success);
      expect(out.toString().trim().split('\n'), hasLength(1));
      expect(jsonDecode(out.toString())['topic'], 'app');
      expect(err.toString(), contains('רעש מתלות כלשהי'));
    });

    test('כשל באיסוף מחזיר 1 ומדווח ל-stderr', () async {
      final code = await AppInfoCli.run(
        const ['app'],
        out: out,
        err: err,
        collect: (_) async => throw StateError('DB נעול'),
      );

      expect(code, AppInfoCliExitCode.collectFailed);
      expect(out.toString(), isEmpty);
      expect(err.toString(), contains('DB נעול'));
    });
  });
}
