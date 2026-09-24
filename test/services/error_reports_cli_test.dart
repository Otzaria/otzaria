import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/user_state/pending_report_store.dart';
import 'package:otzaria/core/user_state/user_state_database.dart';
import 'package:otzaria/models/direct_error_report.dart';
import 'package:otzaria/services/direct_error_report_service.dart';
import 'package:otzaria/services/error_reports_cli.dart';
import 'package:path/path.dart' as p;

import '../models/direct_error_report_text_correction_test.dart'
    show buildCorrectionReport;

void main() {
  late Directory tmp;
  late String dbPath;
  late String dataRoot;
  late UserStateDatabase db;
  late PendingReportStore store;
  late DirectErrorReportService service;
  late StringBuffer out;
  late StringBuffer err;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('otzaria_reports_cli_');
    dataRoot = p.join(tmp.path, 'data');
    Directory(dataRoot).createSync();
    dbPath = p.join(tmp.path, 'user_state.db');
    db = UserStateDatabase.openAt(dbPath);
    await db.database;
    store = PendingReportStore(database: db);
    service = DirectErrorReportService(reportStore: store);
    out = StringBuffer();
    err = StringBuffer();
  });

  tearDown(() {
    db.close();
    tmp.deleteSync(recursive: true);
  });

  Future<int> run(
    List<String> args, {
    bool settingsFound = true,
    bool settingsLoaded = true,
    String? databasePath,
  }) => ErrorReportsCli.run(
    args,
    out: out,
    err: err,
    resolvePaths: () async => (
      settingsFound: settingsFound,
      settingsLoaded: settingsLoaded,
      dataRoot: dataRoot,
      databasePath: databasePath ?? dbPath,
    ),
  );

  Future<List<String>> pendingIds() async =>
      (await service.getPendingReports()).map((r) => r.id).toList();

  Future<List<String>> sentIds() async =>
      (await service.getSentReports()).map((r) => r.id).toList();

  String outDir() => p.join(tmp.path, 'drive', 'reports');

  Map<String, dynamic> readJson(String path) =>
      jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

  group('parseArgs', () {
    test('pending עם ובלי --out', () {
      final request = ErrorReportsCli.parseArgs(['pending'], err)!;
      expect(request.action, ErrorReportsCliAction.pending);
      expect(request.outPath, isNull);

      expect(
        ErrorReportsCli.parseArgs(['PENDING', '--out=n.json'], err)!.outPath,
        'n.json',
      );
    });

    test('handoff דורש --out', () {
      final request = ErrorReportsCli.parseArgs([
        'handoff',
        '--out=E:\\reports',
      ], err)!;
      expect(request.action, ErrorReportsCliAction.handoff);
      expect(request.outPath, 'E:\\reports');

      expect(ErrorReportsCli.parseArgs(['handoff'], err), isNull);
      expect(err.toString(), contains('--out'));
    });

    test('--help עוצר את הפענוח', () {
      for (final args in [
        ['--help'],
        ['-h'],
        ['handoff', '--help'],
      ]) {
        expect(
          ErrorReportsCli.parseArgs(args, err)!.action,
          ErrorReportsCliAction.help,
          reason: '$args',
        );
      }
    });

    test('שגיאות שימוש נדחות עם הודעה', () {
      final cases = {
        <String>[]: 'חסרה פעולה',
        ['send']: 'פעולה לא מוכרת',
        ['help']: 'פעולה לא מוכרת',
        ['pending', 'handoff']: 'פעולה אחת בלבד',
        ['pending', '--verbose']: 'דגל לא מוכר',
        ['pending', '--out=']: '--out',
      };
      cases.forEach((args, message) {
        final localErr = StringBuffer();
        expect(
          ErrorReportsCli.parseArgs(args, localErr),
          isNull,
          reason: '$args',
        );
        expect(localErr.toString(), contains(message), reason: '$args');
      });
    });
  });

  group('run', () {
    test('שגיאת שימוש מחזירה 64 בלי פלט ל-stdout', () async {
      expect(await run(['send']), ErrorReportsCliExitCode.usageError);
      expect(out.toString(), isEmpty);
    });

    test('--help מדפיס שימוש ומחזיר 0', () async {
      expect(await run(['--help']), ErrorReportsCliExitCode.success);
      expect(out.toString(), contains('otzaria reports'));
    });

    test('הגדרות שלא נקראו — 1 עם סיבה, בלי לגעת בתור', () async {
      await service.queueReport(_report('a'));

      for (final action in [
        ['pending'],
        ['handoff', '--out=${outDir()}'],
      ]) {
        expect(
          await run(action, settingsLoaded: false),
          ErrorReportsCliExitCode.failed,
          reason: '$action',
        );
      }
      expect(err.toString(), contains('הגדרות'));
      expect(out.toString(), isEmpty);
      expect(await pendingIds(), ['a']);
      expect(Directory(outDir()).existsSync(), isFalse);
    });

    test('תור שעוד ב-Hive — 2 עם הוראה, בלי לשנות דבר', () async {
      await service.queueReport(_report('a'));
      final hive = File(p.join(dataRoot, 'error_reports_queue.hive'))
        ..writeAsStringSync('legacy');

      for (final action in [
        ['pending'],
        ['handoff', '--out=${outDir()}'],
      ]) {
        expect(
          await run(action),
          ErrorReportsCliExitCode.queueNotMigrated,
          reason: '$action',
        );
      }
      expect(err.toString(), contains('לפתוח את אוצריא'));
      expect(out.toString(), isEmpty);
      expect(hive.readAsStringSync(), 'legacy');
      expect(await pendingIds(), ['a']);
      expect(Directory(outDir()).existsSync(), isFalse);
    });

    test('אוצריא לא הופעלה כאן מעולם — 0 דיווחים, בלי ליצור דבר', () async {
      await service.queueReport(_report('a'));
      for (final action in [
        ['pending'],
        ['handoff', '--out=${outDir()}'],
      ]) {
        expect(
          await run(action, settingsFound: false, settingsLoaded: false),
          ErrorReportsCliExitCode.success,
          reason: '$action',
        );
      }
      expect(
        jsonDecode(LineSplitter.split(out.toString()).first)['pending'],
        0,
      );
      expect(err.toString(), isEmpty);
      expect(Directory(outDir()).existsSync(), isFalse);
      expect(await pendingIds(), ['a']);
    });

    test('מסד שאינו קיים — 0 דיווחים, בלי ליצור אותו', () async {
      final missing = p.join(tmp.path, 'databases', 'user_state.db');

      expect(
        await run(['pending'], databasePath: missing),
        ErrorReportsCliExitCode.success,
      );
      expect(jsonDecode(out.toString())['pending'], 0);
      expect(
        await run(['handoff', '--out=${outDir()}'], databasePath: missing),
        ErrorReportsCliExitCode.success,
      );

      expect(Directory(p.dirname(missing)).existsSync(), isFalse);
      expect(Directory(outDir()).existsSync(), isFalse);
    });
  });

  group('pending', () {
    test('סופר את שני סוגי התור, ואינו משנה דבר', () async {
      await service.queueReport(_report('a'));
      await service.queueReport(
        _report('b'),
        queueType: DirectErrorReportQueueType.automaticRetry,
      );
      final outFile = p.join(tmp.path, 'pending.json');

      expect(
        await run(['pending', '--out=$outFile']),
        ErrorReportsCliExitCode.success,
      );

      final bytes = File(outFile).readAsBytesSync();
      expect(bytes.take(3), isNot([0xEF, 0xBB, 0xBF]));
      expect(jsonDecode(utf8.decode(bytes)), {
        'format': 'otzaria-reports-pending',
        'version': 1,
        'pending': 2,
      });
      expect(await pendingIds(), ['a', 'b']);
      expect(await sentIds(), isEmpty);
    });

    test('דיווח פסול אינו נספר', () async {
      await service.queueReport(_invalidReport('broken'));
      await service.queueReport(_report('a'));

      await run(['pending']);

      expect(jsonDecode(out.toString())['pending'], 1);
    });
  });

  group('handoff', () {
    test('כותב קובץ לכל דיווח עם הגוף שנשלח לשרת בדיוק', () async {
      final correction = buildCorrectionReport(id: 'correction-1');
      await service.queueReport(_report('free-1'));
      await service.queueReport(correction);

      expect(
        await run(['handoff', '--out=${outDir()}']),
        ErrorReportsCliExitCode.success,
      );

      for (final report in [_report('free-1'), correction]) {
        final bytes = File(
          p.join(outDir(), '${report.id}.json'),
        ).readAsBytesSync();
        expect(bytes.take(3), isNot([0xEF, 0xBB, 0xBF]));
        expect(jsonDecode(utf8.decode(bytes)), {
          'format': 'otzaria-report',
          'version': 1,
          'report_id': report.id,
          'endpoint': 'https://otzaria.org/api/reportingerrors',
          'book_title': report.bookTitle,
          'created_at': report.createdAt.toIso8601String(),
          'body': jsonDecode(report.apiBody),
        });
      }
      expect(
        Directory(outDir()).listSync().map((e) => p.basename(e.path)),
        unorderedEquals(['free-1.json', 'correction-1.json']),
      );
    });

    test('דיווח שנכתב עובר להיסטוריה ונספר כנשלח', () async {
      await service.queueReport(_report('a'));
      await service.queueReport(_report('b'));

      await run(['handoff', '--out=${outDir()}']);

      expect(await pendingIds(), isEmpty);
      expect(await sentIds(), ['b', 'a']);
      expect(await service.getSentReportsTotal(), 2);
      expect(out.toString(), contains('הועברו 2'));
    });

    test('תור ריק — מחזיר 0', () async {
      expect(
        await run(['handoff', '--out=${outDir()}']),
        ErrorReportsCliExitCode.success,
      );
      expect(Directory(outDir()).listSync(), isEmpty);
    });

    test('כשל באמצע משאיר בתור רק את מה שלא נכתב', () async {
      for (final id in ['a', 'b', 'c']) {
        await service.queueReport(_report(id));
      }
      // תיקייה בשם הקובץ חוסמת את ה-rename של `b` בלבד.
      Directory(p.join(outDir(), 'b.json')).createSync(recursive: true);

      expect(
        await run(['handoff', '--out=${outDir()}']),
        ErrorReportsCliExitCode.failed,
      );

      expect(await pendingIds(), ['b']);
      expect(await sentIds(), ['c', 'a']);
      expect(File(p.join(outDir(), 'a.json')).existsSync(), isTrue);
      expect(File(p.join(outDir(), 'c.json')).existsSync(), isTrue);
      expect(File(p.join(outDir(), 'b.json.tmp')).existsSync(), isFalse);
      final errLines = err.toString().trim().split('\n');
      expect(errLines, hasLength(1));
      expect(errLines.single, contains('b'));
    });

    test('דיווח פסול מדולג עם הודעה, ואינו מכשיל', () async {
      await service.queueReport(_invalidReport('broken'));
      await service.queueReport(_report('a'));

      expect(
        await run(['handoff', '--out=${outDir()}']),
        ErrorReportsCliExitCode.success,
      );

      expect(await pendingIds(), ['broken']);
      expect(await sentIds(), ['a']);
      expect(err.toString(), contains('broken'));
      expect(
        Directory(outDir()).listSync().map((e) => p.basename(e.path)),
        ['a.json'],
      );
    });

    test('קובץ קיים של אותו דיווח נדרס', () async {
      await service.queueReport(_report('a'));
      final target = File(p.join(outDir(), 'a.json'))
        ..createSync(recursive: true)
        ..writeAsStringSync(jsonEncode({'report_id': 'a', 'stale': true}));

      expect(
        await run(['handoff', '--out=${outDir()}']),
        ErrorReportsCliExitCode.success,
      );
      expect(readJson(target.path).containsKey('stale'), isFalse);
      expect(Directory(outDir()).listSync(), hasLength(1));
    });

    test('שם תפוס בידי דיווח אחר מקבל סיומת יציבה', () async {
      await service.queueReport(_report('a/b'));
      final other = File(p.join(outDir(), 'a_b.json'))
        ..createSync(recursive: true)
        ..writeAsStringSync(jsonEncode({'report_id': 'a_b'}));

      await run(['handoff', '--out=${outDir()}']);

      expect(readJson(other.path)['report_id'], 'a_b');
      final suffixed = p.join(
        outDir(),
        ErrorReportsCli.fileNameFor('a/b', disambiguate: true),
      );
      expect(readJson(suffixed)['report_id'], 'a/b');
    });

    test('קובץ שאינו UTF-8 באותו שם אינו נדרס', () async {
      await service.queueReport(_report('a'));
      final foreign = File(p.join(outDir(), 'a.json'))
        ..createSync(recursive: true)
        ..writeAsBytesSync([0xFF, 0xFE, 0x00]);

      expect(
        await run(['handoff', '--out=${outDir()}']),
        ErrorReportsCliExitCode.success,
      );
      expect(foreign.readAsBytesSync(), [0xFF, 0xFE, 0x00]);
      final suffixed = p.join(
        outDir(),
        ErrorReportsCli.fileNameFor('a', disambiguate: true),
      );
      expect(readJson(suffixed)['report_id'], 'a');
    });

    test('מזהה עם תווים אסורים נכתב בשם בטוח בתוך התיקייה', () async {
      await service.queueReport(_report('../x:y*z'));

      await run(['handoff', '--out=${outDir()}']);

      final file = File(p.join(outDir(), '___x_y_z.json'));
      expect(readJson(file.path)['report_id'], '../x:y*z');
      expect(Directory(outDir()).listSync(), hasLength(1));
    });

    test('רשומה באותו מזהה בהיסטוריה מוחלפת ואינה נספרת שוב', () async {
      await store.add(DirectErrorReportService.sentKind, _report('a').toJson());
      await service.queueReport(_report('a'));
      final totalBefore = await service.getSentReportsTotal();

      await run(['handoff', '--out=${outDir()}']);

      expect(await sentIds(), ['a']);
      expect(await pendingIds(), isEmpty);
      expect(await service.getSentReportsTotal(), totalBefore);
    });
  });

  group('handOffPendingReports', () {
    test('חלון שערך או שלח בינתיים גובר, והדיווח אינו נספר', () async {
      for (final id in ['a', 'b', 'c']) {
        await service.queueReport(_report(id));
      }
      final written = <String>[];
      final rows = await store.listByKind(DirectErrorReportService.pendingKind);

      final result = await service.handOffPendingReports((report) async {
        written.add(report.id);
        if (report.id == 'b') {
          await store.updatePayload(
            rows[1].id,
            _report('b').copyWith(errorDetails: 'נערך').toJson(),
          );
        }
        if (report.id == 'c') await store.deleteIds([rows[2].id]);
      });

      expect(written, ['a', 'b', 'c']);
      expect(result.handedOff, 1);
      expect(result.changedMeanwhile, 2);
      expect(result.failures, isEmpty);
      expect(await pendingIds(), ['b']);
      expect(await sentIds(), ['a']);
    });
  });

  group('fileNameFor', () {
    test('משאיר מזהה רגיל כפי שהוא', () {
      expect(
        ErrorReportsCli.fileNameFor('1712345678-42'),
        '1712345678-42.json',
      );
    });

    test('מחליף כל תו שאינו אות לטינית, ספרה, _ או -', () {
      expect(ErrorReportsCli.fileNameFor('a/b\\c:d.e f'), 'a_b_c_d_e_f.json');
      expect(ErrorReportsCli.fileNameFor('..'), '__.json');
      expect(ErrorReportsCli.fileNameFor('דיווח'), '_____.json');
      expect(ErrorReportsCli.fileNameFor(''), '_.json');
    });

    test('סיומת ההבחנה יציבה ושונה בין מזהים', () {
      final first = ErrorReportsCli.fileNameFor('a/b', disambiguate: true);
      expect(first, matches(RegExp(r'^a_b-[0-9a-f]{8}\.json$')));
      expect(ErrorReportsCli.fileNameFor('a/b', disambiguate: true), first);
      expect(
        ErrorReportsCli.fileNameFor('a:b', disambiguate: true),
        isNot(first),
      );
    });
  });

  test('assets/cli_capabilities.json מכריז על שתי הפעולות', () {
    expect(
      jsonDecode(File('assets/cli_capabilities.json').readAsStringSync()),
      {
        'version': 1,
        'capabilities': ['reports-pending-v1', 'reports-handoff-v1'],
      },
    );
  });
}

DirectErrorReport _report(String id) => DirectErrorReport(
  id: id,
  senderEmail: 'user@example.com',
  subject: 'בדיקה',
  bookTitle: 'ספר מבחן',
  currentRef: 'פרק ב',
  lineNumber: 7,
  selectedText: 'שגיאה',
  errorDetails: 'פרט',
  contextText: 'הקשר',
  filePath: 'C:/books/book.txt',
  createdAt: DateTime.parse('2026-03-16T10:15:00Z'),
);

/// surrogate בודד — אין לו digest קנוני, והשרת היה דוחה אותו.
DirectErrorReport _invalidReport(String id) =>
    buildCorrectionReport(id: id, errorDetails: 'x\uD83D');
