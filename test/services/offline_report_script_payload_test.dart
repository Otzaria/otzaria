import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/services/direct_error_report_service.dart';
import 'package:otzaria_report_contract/otzaria_report_contract.dart';
import 'package:path/path.dart' as p;

import '../models/direct_error_report_text_correction_test.dart'
    show buildCorrectionReport;

const _endpoint = 'https://otzaria.org/api/reportingerrors';

List<DirectErrorReport> _reports() => [
  buildCorrectionReport(id: 'corr-1'),
  buildCorrectionReport(id: 'corr-del', proposed: ''),
  buildCorrectionReport(
    id: 'corr-none',
    proposed: null,
    errorDetails:
        "גרש ' מירכאות \" לוכסן \\ '@ %PATH% \$HOME `x` \u2028 \u2029 \u0085 ‘’“” !x! ^& %~f0 סוף",
  ),
  DirectErrorReport(
    id: 'legacy',
    senderEmail: 'a@b.c',
    subject: 's',
    bookTitle: 'ספר',
    currentRef: 'פרק',
    lineNumber: 1,
    errorDetails: 'ישן',
    createdAt: DateTime.utc(2026),
  ),
];

/// מה שהשרת צריך לקבל: ה-payload אחרי מעבר ב-JSON.
Object? _expected(DirectErrorReport report) =>
    jsonDecode(jsonEncode(report.toApiPayload()));

/// שרת מקומי שאוסף את גופי הבקשות כבייטים.
Future<(HttpServer, List<String>)> _startCollector() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final bodies = <String>[];
  server.listen((request) async {
    bodies.add(await utf8.decoder.bind(request).join());
    request.response
      ..statusCode = 200
      ..write('{"success":true}');
    await request.response.close();
  });
  return (server, bodies);
}

void main() {
  final service = DirectErrorReportService();

  group('[T5] ייצוא סקריפט שליחה — ה-payload החדש עובר כלשונו', () {
    test('[T5] bat: שורת JSON לכל דיווח, זהה ל-payload', () {
      final reports = _reports();
      final script = service.buildOfflineSendScript(
        reports,
        target: OfflineSendScriptTarget.windows,
      );
      final lines = script.content.split('\r\n');
      final start = lines.indexOf(r"$payloadLines = @'") + 1;
      final end = lines.indexOf("'@", start);
      final payloadLines = lines.sublist(start, end);

      expect(payloadLines, hasLength(reports.length));
      for (var i = 0; i < reports.length; i++) {
        expect(payloadLines[i], jsonEncode(reports[i].toApiPayload()));
      }
      // שום שורת נתונים לא תסגור את ה-here-string.
      expect(payloadLines.where((l) => l.startsWith("'@")), isEmpty);
      expect(script.content, isNot(contains('ConvertTo-Json')));
    });

    test('[T5] sh: heredoc לכל דיווח, זהה ל-payload', () {
      final reports = _reports();
      final script = service.buildOfflineSendScript(
        reports,
        target: OfflineSendScriptTarget.unix,
      );
      final lines = script.content.split('\n');
      for (var i = 0; i < reports.length; i++) {
        final header = lines.indexWhere(
          (l) => l.endsWith("<<'OTZARIA_PAYLOAD_$i'"),
        );
        expect(header, greaterThan(0));
        expect(lines[header + 2], 'OTZARIA_PAYLOAD_$i');
        expect(jsonDecode(lines[header + 1]), _expected(reports[i]));
      }
    });

    test(
      '[T5] sh מופעל ב-bash מול שרת מקומי — השרת מקבל בדיוק את ה-payload',
      () async {
        final bash = Platform.isWindows
            ? r'C:\Program Files\Git\bin\bash.exe'
            : 'bash';
        if (Platform.isWindows && !File(bash).existsSync()) {
          markTestSkipped('Git Bash לא מותקן');
          return;
        }
        final (server, bodies) = await _startCollector();
        addTearDown(() => server.close(force: true));
        final dir = await Directory.systemTemp.createTemp('otz_sh_');
        addTearDown(() => dir.delete(recursive: true));

        final reports = _reports();
        final script = service
            .buildOfflineSendScript(
              reports,
              target: OfflineSendScriptTarget.unix,
            )
            .content
            .replaceFirst(_endpoint, 'http://127.0.0.1:${server.port}/')
            // הסקריפט למשתמש מסיים בחלון סיכום; בבדיקה חלון כזה חוסם את
            // Process.run ב-macOS (osascript), ולכן מחליפים אותו בפלט למסוף.
            .replaceFirst(
              RegExp(r'if command -v zenity[\s\S]*?\nfi\n'),
              r'cat "$tmp"'
              '\n',
            );
        final file = File('${dir.path}/send.sh');
        await file.writeAsString(script);

        final result = await Process.run(bash, [file.path]);
        expect(result.exitCode, 0, reason: '${result.stderr}');
        expect(bodies, hasLength(reports.length));
        for (var i = 0; i < reports.length; i++) {
          expect(bodies[i], jsonEncode(reports[i].toApiPayload()));
        }
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      '[T5] ה-bat מופעל ב-cmd מול שרת מקומי — השרת מקבל בדיוק את ה-payload',
      () async {
        if (!Platform.isWindows) {
          markTestSkipped('PowerShell 5.1 — Windows בלבד');
          return;
        }
        final (server, bodies) = await _startCollector();
        addTearDown(() => server.close(force: true));
        final dir = await Directory.systemTemp.createTemp('otz_ps_');
        addTearDown(() => dir.delete(recursive: true));

        final reports = _reports();
        final bat = service
            .buildOfflineSendScript(
              reports,
              target: OfflineSendScriptTarget.windows,
            )
            .content;
        // ה-bat כפי שהוא, בלי חלון הסיכום החוסם.
        final script = bat
            .replaceFirst(_endpoint, 'http://127.0.0.1:${server.port}/')
            .replaceFirst(
              RegExp(r'\[System\.Windows\.Forms\.MessageBox\]::Show[^\r\n]*'),
              r'Write-Output $summary',
            );
        final file = File(p.join(dir.path, 'send.bat'));
        await file.writeAsString(script);

        final result = await Process.run('cmd', ['/c', file.path]);
        expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
        expect(bodies, hasLength(reports.length));
        for (var i = 0; i < reports.length; i++) {
          expect(bodies[i], jsonEncode(reports[i].toApiPayload()));
        }
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  });
}
