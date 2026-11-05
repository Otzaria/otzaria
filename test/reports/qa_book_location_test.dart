import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:otzaria/core/user_state/pending_report_store.dart';
import 'package:otzaria/core/user_state/user_state_database.dart';
import 'package:otzaria/reports/book_report_selection.dart';
import 'package:otzaria/services/direct_error_report_service.dart';
import 'package:otzaria/text_book/view/error_report_dialog.dart';
// ignore: depend_on_referenced_packages
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:url_launcher_platform_interface/link.dart';
// ignore: depend_on_referenced_packages
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

class _ComposerLauncher extends UrlLauncherPlatform
    with MockPlatformInterfaceMixin {
  String? openedUrl;

  @override
  Future<bool> canLaunch(String url) async => true;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    openedUrl = url;
    return true;
  }

  @override
  LinkDelegate? get linkDelegate => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('QA opening a mail composer does not acknowledge delivery', (
    tester,
  ) async {
    final previousLauncher = UrlLauncherPlatform.instance;
    final launcher = _ComposerLauncher();
    UrlLauncherPlatform.instance = launcher;
    addTearDown(() => UrlLauncherPlatform.instance = previousLauncher);
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (value) {
              context = value;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    final completed = await ErrorReportHelper.handleRegularReportAction(
      context,
      ErrorReportAction.sendEmail,
      ReportedErrorData(selectedText: 'מילה', errorDetails: 'תיקון'),
      'ספר',
      'פרק א',
      const {},
      1,
      'הקשר הטעות',
      'v1',
    );
    expect(launcher.openedUrl, startsWith('mailto:'));
    expect(
      completed,
      isFalse,
      reason:
          'A successful launch does not prove that the user sent the email.',
    );
  });

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
    'QA: precise range survives SQLite queue, email, and a real exported shell request',
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
      final email = ErrorReportHelper.buildEmailBody(
        restored.bookTitle,
        restored.currentRef,
        const {},
        restored.selectedText,
        restored.errorDetails,
        restored.lineNumber,
        restored.contextText,
        restored.libraryVersion,
        restored.senderEmail,
      );
      expect(email, contains('22000–22004'));
      final mailto = Uri.parse(
        'mailto:qa@example.com?${ErrorReportHelper.encodeQueryParameters({'body': email})}',
      );
      expect(mailto.queryParameters['body'], email);

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
