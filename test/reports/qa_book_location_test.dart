import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:otzaria/core/user_state/pending_report_store.dart';
import 'package:otzaria/core/user_state/user_state_database.dart';
import 'package:otzaria/reports/book_report_selection.dart';
import 'package:otzaria/services/direct_error_report_service.dart';
import 'package:otzaria/text_book/view/error_report_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('QA: location chosen inside a long quote survives the direct payload', () {
    final text = 'מילה ' * 5000;
    const range = BookReportSelection(22000, 22004);
    final data = ReportedErrorData(
      selectedText: range.selectedText(text),
      errorDetails: 'יש לתקן כאן',
      selection: range,
      selectionContext: range.contextText(text),
    );
    // Callers may supply the original paragraph before the selected range;
    // the final payload must keep the precise location ahead of bounded text.
    final combinedContext = '$text\n\n${data.selectionContext}';
    final report = ErrorReportHelper.buildDirectReport(
      senderEmail: 'qa@example.com',
      reportData: data,
      bookTitle: 'ספר',
      currentRef: 'פרק א',
      bookDetails: const {},
      lineNumber: 1,
      contextText: combinedContext,
      libraryVersion: 'v1',
    );
    expect(report.selectedText, 'מילה');
    expect(
      report.contextText,
      contains('22000–22004'),
      reason:
          'A long original quote must not truncate away the exact chosen location.',
    );
  });

  test(
    'QA: precise range survives SQLite queue and a real exported shell request',
    () async {
      final text = 'מילה ' * 5000;
      const range = BookReportSelection(22000, 22004);
      final data = ReportedErrorData(
        selectedText: range.selectedText(text),
        errorDetails: 'יש לתקן כאן, גם כשאותה מילה חוזרת',
        selection: range,
        selectionContext: range.contextText(text),
      );
      final report = ErrorReportHelper.buildDirectReport(
        senderEmail: 'qa@example.com',
        reportData: data,
        bookTitle: 'ספר',
        currentRef: 'פרק א',
        bookDetails: const {},
        lineNumber: 1,
        contextText: '$text\n\n${data.selectionContext}',
        libraryVersion: 'v1',
      );
      final temporary = Directory.systemTemp.createTempSync(
        'qa_book_location_',
      );
      final database = UserStateDatabase.openAt(
        '${temporary.path}/user_state.db',
      );
      final client = http.Client();
      final service = DirectErrorReportService(
        client: client,
        reportStore: PendingReportStore(database: database),
      );
      addTearDown(() async {
        client.close();
        await database.flushWrites();
        database.close();
        temporary.deleteSync(recursive: true);
      });
      await service.queueReport(report);
      final restored = (await service.getPendingReports()).single;
      expect(restored.toApiPayload(), report.toApiPayload());
      expect(
        restored.contextText,
        startsWith('מיקום מסומן בציטוט המוצג: תווים 22000–22004'),
      );
      final received = <String>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        received.add(await utf8.decoder.bind(request).join());
        request.response.statusCode = 200;
        request.response.write('{"success":true}');
        await request.response.close();
      });
      final script = service
          .buildOfflineSendScript(
            [restored],
            target: OfflineSendScriptTarget.unix,
          )
          .content
          .replaceFirst(
            'https://otzaria.org/api/reportingerrors',
            'http://127.0.0.1:${server.port}/',
          )
          .replaceFirst(
            RegExp(r'if command -v zenity[\s\S]*?\nfi\n'),
            r'cat "$tmp"'
            '\n',
          );
      final file = File('${temporary.path}/send.sh');
      await file.writeAsString(script);
      final bash = Platform.isWindows
          ? r'C:\Program Files\Git\bin\bash.exe'
          : 'bash';
      final process = await Process.run(bash, [file.path]);
      expect(
        process.exitCode,
        0,
        reason: '${process.stdout}\n${process.stderr}',
      );
      expect(received, hasLength(1));
      expect(jsonDecode(received.single), report.toApiPayload());
      final artifactDirectory = Directory('build/reporting_qa');
      await artifactDirectory.create(recursive: true);
      await File(
        '${artifactDirectory.path}/book-selection-fixture.json',
      ).writeAsString(
        jsonEncode({
          'stored': restored.toJson(),
          'payload': restored.toApiPayload(),
          'range': '22000–22004',
        }),
      );
    },
  );
}
