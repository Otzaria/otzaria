import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:otzaria/core/user_state/pending_report_store.dart';
import 'package:otzaria/core/user_state/user_state_database.dart';
import 'package:otzaria/models/direct_error_report.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/services/direct_error_report_service.dart';
import 'package:otzaria/services/sent_reports_counter.dart';
import 'package:otzaria/core/messages/report_messages.dart';

import '../models/direct_error_report_text_correction_test.dart'
    show buildCorrectionReport, trickyLine;

late Directory tmp;
late UserStateDatabase db;
late PendingReportStore store;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('otzaria_reports_');
    db = UserStateDatabase.openAt(
      '${tmp.path}${Platform.pathSeparator}user_state.db',
    );
    store = PendingReportStore(database: db);
  });

  tearDown(() {
    db.close();
    tmp.deleteSync(recursive: true);
  });

  setUpAll(() async {
    await Settings.init(cacheProvider: _MemoryCacheProvider());
    await Settings.setValue<bool>(SettingsRepository.keyOfflineMode, false);
    await Settings.setValue<bool>(
      SettingsRepository.keyQueueErrorReportsWhenOffline,
      true,
    );
  });

  group('DirectErrorReport', () {
    test('serializes to json and api payload', () {
      final createdAt = DateTime.parse('2026-03-16T10:15:00Z');
      final report = DirectErrorReport(
        id: 'report-1',
        senderEmail: 'user@example.com',
        subject: 'דיווח על טעות: ספר מבחן',
        bookTitle: 'ספר מבחן',
        currentRef: 'פרק א',
        lineNumber: 12,
        selectedText: 'טקסט עם טעות',
        errorDetails: 'חסר ניקוד',
        contextText: 'הקשר רחב יותר',
        filePath: '/books/test.txt',
        sourceFolder: 'sefaria',
        queueType: DirectErrorReportQueueType.automaticRetry,
        createdAt: createdAt,
      );

      final json = report.toJson();
      final restored = DirectErrorReport.fromJson(json);
      final apiPayload = report.toApiPayload();

      expect(restored, equals(report));
      expect(apiPayload['sender_email'], 'user@example.com');
      expect(apiPayload.containsKey('recipient_email'), isFalse);
      expect(apiPayload['line_number'], 12);
      expect(apiPayload['current_ref'], 'פרק א');
      expect(apiPayload['selected_text'], 'טקסט עם טעות');
      expect(apiPayload['error_details'], 'חסר ניקוד');
      expect(apiPayload['context_text'], 'הקשר רחב יותר');
      expect(apiPayload['file_path'], '/books/test.txt');
      expect(apiPayload['source_folder'], 'sefaria');
      expect(apiPayload['created_at'], createdAt.toIso8601String());
      expect(apiPayload.containsKey('body'), isFalse);
      expect(apiPayload.containsKey('file_name'), isFalse);
      expect(json['queueType'], 'automaticRetry');
      expect(restored.queueType, DirectErrorReportQueueType.automaticRetry);
    });

    test('defaults missing queueType from json to manual', () {
      final report = DirectErrorReport.fromJson({
        'id': 'report-legacy',
        'senderEmail': 'user@example.com',
        'subject': 'legacy',
        'bookTitle': 'legacy book',
        'currentRef': 'legacy ref',
        'lineNumber': 3,
        'createdAt': '2026-03-16T10:15:00Z',
      });

      expect(report.queueType, DirectErrorReportQueueType.manual);
    });
  });

  group('DirectErrorReportService.isValidSenderEmail', () {
    test('accepts valid addresses', () {
      expect(
        DirectErrorReportService.isValidSenderEmail('name@example.com'),
        isTrue,
      );
      expect(
        DirectErrorReportService.isValidSenderEmail('user.name+tag@foo.co.il'),
        isTrue,
      );
    });

    test('rejects invalid addresses', () {
      expect(DirectErrorReportService.isValidSenderEmail(''), isFalse);
      expect(DirectErrorReportService.isValidSenderEmail('invalid'), isFalse);
      expect(
        DirectErrorReportService.isValidSenderEmail('no-domain@localhost'),
        isFalse,
      );
      expect(
        DirectErrorReportService.isValidSenderEmail('with space@example.com '),
        isFalse,
      );
    });
  });

  group('DirectErrorReportService.buildOfflineSendScript', () {
    final report = DirectErrorReport(
      id: 'report-42',
      senderEmail: 'user@example.com',
      subject: 'בדיקה',
      bookTitle: 'ספר מבחן',
      currentRef: 'פרק ב',
      lineNumber: 7,
      selectedText: 'שגיאה',
      errorDetails: 'פרט',
      contextText: 'הקשר',
      filePath: 'C:/books/book.txt',
      sourceFolder: 'local',
      createdAt: DateTime.parse('2026-03-16T10:15:00Z'),
    );

    test('windows target builds a readable bat with MessageBox output', () {
      final service = DirectErrorReportService();

      final script = service.buildOfflineSendScript(
        [report],
        target: OfflineSendScriptTarget.windows,
      );

      expect(script.fileName, 'otzaria_send_saved_reports.bat');
      expect(script.content, startsWith('@echo off'));
      expect(
        script.content,
        contains('https://otzaria.org/api/reportingerrors'),
      );
      expect(script.content, contains('Invoke-WebRequest'));
      // מונע את פרומפט "Script Execution Risk" של PowerShell 5.1.
      expect(script.content, contains('-UseBasicParsing'));
      expect(
        script.content,
        contains('[System.Windows.Forms.MessageBox]::Show'),
      );
      // קריא: ה-JSON מוטמע כפי שהוא, ללא Base64.
      expect(script.content, isNot(contains('FromBase64String')));
      expect(script.content, contains('report-42'));
      // הסמן המלא לא מופיע בשורת הפקודה (נבנה שם מ-[char]35).
      expect(script.content, contains('[char]35'));
      // עמידה במגבלת הקצב בשרת (8 לדקה): המתנה בין אצוות + הסבר בפלט.
      expect(script.content, contains('Start-Sleep -Seconds 65'));
      expect(script.content, contains('% 8'));
      expect(script.content, contains('עד 8 דיווחים בדקה'));
      expect(script.content, contains('להריץ קובץ זה שוב בבטחה'));
    });

    test('unix target builds an sh script with curl and a graphical popup', () {
      final service = DirectErrorReportService();

      final script = service.buildOfflineSendScript(
        [report],
        target: OfflineSendScriptTarget.unix,
      );

      expect(script.fileName, 'otzaria_send_saved_reports.sh');
      expect(script.content, startsWith('#!/usr/bin/env bash'));
      expect(script.content, contains('curl'));
      expect(
        script.content,
        contains('https://otzaria.org/api/reportingerrors'),
      );
      expect(script.content, contains('zenity'));
      expect(script.content, contains('osascript'));
      expect(script.content, contains("'report-42'"));
      expect(script.content, isNot(contains('FromBase64String')));
      // עמידה במגבלת הקצב בשרת (8 לדקה): המתנה בין אצוות + הסבר בפלט.
      expect(script.content, contains('sleep 65'));
      expect(script.content, contains('% 8'));
      expect(script.content, contains('עד 8 דיווחים בדקה'));
      expect(script.content, contains('להריץ קובץ זה שוב בבטחה'));
    });
  });

  group('DirectErrorReportService — ספירת הנשלחים (issue #1343)', () {
    test('המונה ממשיך מעבר לתקרת ההיסטוריה', () async {
      const max = DirectErrorReportService.maxSentReportsToKeep;
      final repository = _Queue(store, DirectErrorReportService.pendingKind);
      final sentRepository = _Queue(store, DirectErrorReportService.sentKind);
      await repository.overwrite([
        for (var i = 0; i < max + 3; i++) _buildReport(id: 'r-$i'),
      ]);
      final service = DirectErrorReportService(
        client: MockClient((_) async => http.Response('', 200)),
        reportStore: store,
        sentCounter: SentReportsCounter.inMemory(),
      );

      while ((await repository.load()).isNotEmpty) {
        await service.flushPendingReports();
      }

      expect((await sentRepository.load()).length, max);
      expect(await service.getSentReportsTotal(), max + 3);

      await service.clearSentReports();
      expect(await service.getSentReportsTotal(), 0);
    });
  });

  group('DirectErrorReportService.flushPendingReports', () {
    test('automatic flush sends only retryable queued reports', () async {
      final repository = _Queue(store, DirectErrorReportService.pendingKind);
      final sentRepository = _Queue(store, DirectErrorReportService.sentKind);

      await repository.overwrite([
        _buildReport(
          id: 'manual-report',
          queueType: DirectErrorReportQueueType.manual,
        ),
        _buildReport(
          id: 'retry-report',
          queueType: DirectErrorReportQueueType.automaticRetry,
        ),
      ]);

      final sentReportIds = <String>[];
      final service = DirectErrorReportService(
        reportStore: store,
        client: MockClient((request) async {
          final payload = jsonDecode(request.body) as Map<String, dynamic>;
          sentReportIds.add(payload['report_id'] as String);
          return http.Response('', 200);
        }),
      );

      final sentCount = await service.flushPendingReports(
        onlyAutomaticRetry: true,
      );
      final remainingReports = await repository.load();

      expect(sentCount, 1);
      expect(sentReportIds, ['retry-report']);
      expect((await sentRepository.load()).single.id, 'retry-report');
      expect(
        remainingReports.map((report) => report.id).toList(),
        ['manual-report'],
      );
    });

    test(
      'permanent failure is removed and does not block later reports',
      () async {
        final repository = _Queue(store, DirectErrorReportService.pendingKind);

        await repository.overwrite([
          _buildReport(
            id: 'invalid-report',
            queueType: DirectErrorReportQueueType.automaticRetry,
          ),
          _buildReport(
            id: 'valid-report',
            queueType: DirectErrorReportQueueType.automaticRetry,
          ),
          _buildReport(
            id: 'manual-report',
            queueType: DirectErrorReportQueueType.manual,
          ),
        ]);

        final attemptedReportIds = <String>[];
        final sentCounter = SentReportsCounter.inMemory();
        final service = DirectErrorReportService(
          reportStore: store,
          client: MockClient((request) async {
            final payload = jsonDecode(request.body) as Map<String, dynamic>;
            final reportId = payload['report_id'] as String;
            attemptedReportIds.add(reportId);

            if (reportId == 'invalid-report') {
              return http.Response('bad request', 400);
            }

            return http.Response('', 200);
          }),
          sentCounter: sentCounter,
        );

        final sentCount = await service.flushPendingReports(
          onlyAutomaticRetry: true,
        );
        final remainingReports = await repository.load();

        expect(sentCount, 1);
        expect(
          await service.getSentReportsTotal(),
          1,
          reason: 'דיווח שנדחה נשמר בהיסטוריה אך אינו נספר כנשלח',
        );
        expect(attemptedReportIds, ['invalid-report', 'valid-report']);
        final history = await service.getSentReports();
        expect(history.map((r) => r.id), ['valid-report', 'invalid-report']);
        expect(history.first.rejectionReason, isNull);
        expect(
          history.last.rejectionReason,
          ReportMessages.serverPermanentFailure(400),
          reason: 'דיווח שנדחה לצמיתות לא נעלם בשקט — הוא נשמר בהיסטוריה',
        );
        expect(
          remainingReports.map((report) => report.id).toList(),
          ['manual-report'],
        );
      },
    );
  });

  group('DirectErrorReportService.suspendAutomaticFlush', () {
    test('ממתינה לשליחה שבאמצע, כדי שכתיבה חיצונית לא תדרוס אותה', () async {
      final repository = _Queue(store, DirectErrorReportService.pendingKind);
      final sentRepository = _Queue(store, DirectErrorReportService.sentKind);
      await repository.overwrite([
        _buildReport(
          id: 'r-1',
          queueType: DirectErrorReportQueueType.automaticRetry,
        ),
      ]);

      final networkGate = Completer<http.Response>();
      final service = DirectErrorReportService(
        reportStore: store,
        client: MockClient((_) => networkGate.future),
      );

      final flush = service.flushPendingReports(onlyAutomaticRetry: true);
      var suspended = false;
      final suspend = DirectErrorReportService.suspendAutomaticFlush().then(
        (_) => suspended = true,
      );

      await pumpEventQueue();
      expect(
        suspended,
        isFalse,
        reason: 'השחזור אינו יכול לכתוב לתור בזמן שהשליחה באוויר',
      );

      networkGate.complete(http.Response('', 200));
      await flush;
      await suspend;

      expect(suspended, isTrue);
      expect((await sentRepository.load()).single.id, 'r-1');
      expect(await repository.load(), isEmpty);
    });
  });

  group('DirectErrorReportService.submitReport', () {
    test(
      'success message uses sefaria label for sefaria sourced books',
      () async {
        final sentRepository = _Queue(store, DirectErrorReportService.sentKind);
        final service = DirectErrorReportService(
          reportStore: store,
          client: MockClient((request) async => http.Response('', 200)),
        );

        final result = await service.submitReport(
          _buildReport(
            id: 'sefaria-success-report',
            sourceFolder: 'sefariaToOtzaria',
          ),
        );

        expect(result.status, DirectReportDeliveryStatus.sent);
        expect(result.message, 'הדיווח נקלט ויועבר לספריא. תודה!');
        expect(
          (await sentRepository.load()).single.id,
          'sefaria-success-report',
        );
      },
    );

    test(
      'sefaria label by containment, like the website email routing',
      () async {
        Future<String?> messageFor(String sourceFolder) async {
          final service = DirectErrorReportService(
            client: MockClient((request) async => http.Response('', 200)),
            reportStore: store,
          );
          final result = await service.submitReport(
            _buildReport(id: 'r-$sourceFolder', sourceFolder: sourceFolder),
          );
          return result.message;
        }

        for (final folder in [
          'Sefaria',
          ' SEFARIATOOTZARIA ',
          'sefaria-extra',
          'mysefaria',
        ]) {
          expect(await messageFor(folder), ReportMessages.sentToSefaria);
        }
        for (final folder in ['wikiSource', 'Tashma', '']) {
          expect(await messageFor(folder), ReportMessages.sentToOtzaria);
        }
      },
    );

    test(
      '200 with duplicate:true is sent-as-duplicate with a dedicated message',
      () async {
        final sentRepository = _Queue(store, DirectErrorReportService.sentKind);
        final service = DirectErrorReportService(
          reportStore: store,
          client: MockClient(
            (request) async => http.Response(
              jsonEncode({'success': true, 'duplicate': true}),
              200,
            ),
          ),
        );

        final result = await service.submitReport(
          _buildReport(id: 'duplicate-report', sourceFolder: 'sefaria'),
        );

        expect(result.status, DirectReportDeliveryStatus.sent);
        expect(result.isDuplicate, isTrue);
        expect(result.message, contains('כבר נשלח'));
        expect(result.message, contains('לספריא'));
        expect((await sentRepository.load()).single.id, 'duplicate-report');
      },
    );

    test(
      '200 with non-json or duplicate:false body is a regular send',
      () async {
        for (final body in [
          '',
          'ok',
          jsonEncode({'duplicate': false}),
        ]) {
          final service = DirectErrorReportService(
            reportStore: store,
            client: MockClient((request) async => http.Response(body, 200)),
          );

          final result = await service.submitReport(
            _buildReport(id: 'regular-report'),
          );

          expect(result.status, DirectReportDeliveryStatus.sent);
          expect(result.isDuplicate, isFalse);
        }
      },
    );

    test('submitPendingReport removes sent report from queue', () async {
      final repository = _Queue(store, DirectErrorReportService.pendingKind);
      final sentRepository = _Queue(store, DirectErrorReportService.sentKind);
      final report = _buildReport(id: 'pending-report');
      await repository.overwrite([report]);
      final service = DirectErrorReportService(
        reportStore: store,
        client: MockClient((request) async => http.Response('', 200)),
      );

      final result = await service.submitPendingReport(report);

      expect(result.status, DirectReportDeliveryStatus.sent);
      expect(await repository.load(), isEmpty);
      expect((await sentRepository.load()).single.id, 'pending-report');
    });

    test('updatePendingReport edits a saved queued report', () async {
      final repository = _Queue(store, DirectErrorReportService.pendingKind);
      final report = _buildReport(id: 'editable-report');
      await repository.overwrite([report]);
      final service = DirectErrorReportService(
        reportStore: store,
      );

      await service.updatePendingReport(
        report.copyWith(errorDetails: 'פרט מתוקן'),
      );

      final reports = await repository.load();
      expect(reports.single.errorDetails, 'פרט מתוקן');
    });

    test(
      'markPendingReportAsSent moves a queued report to sent history',
      () async {
        final repository = _Queue(store, DirectErrorReportService.pendingKind);
        final sentRepository = _Queue(store, DirectErrorReportService.sentKind);
        final report = _buildReport(id: 'manual-sent-report');
        await repository.overwrite([
          report,
          _buildReport(id: 'other-report'),
        ]);
        final service = DirectErrorReportService(
          reportStore: store,
        );

        await service.markPendingReportAsSent(report);

        expect(
          (await repository.load()).map((report) => report.id).toList(),
          ['other-report'],
        );
        expect((await sentRepository.load()).single.id, 'manual-sent-report');
      },
    );

    test('deleteSentReport removes a report from sent history', () async {
      final sentRepository = _Queue(store, DirectErrorReportService.sentKind);
      await sentRepository.overwrite([
        _buildReport(id: 'sent-a'),
        _buildReport(id: 'sent-b'),
      ]);
      final service = DirectErrorReportService(
        reportStore: store,
      );

      await service.deleteSentReport('sent-a');

      expect(
        (await sentRepository.load()).map((report) => report.id).toList(),
        ['sent-b'],
      );
    });

    test('clearSentReports clears sent history', () async {
      final sentRepository = _Queue(store, DirectErrorReportService.sentKind);
      await sentRepository.overwrite([
        _buildReport(id: 'sent-a'),
        _buildReport(id: 'sent-b'),
      ]);
      final service = DirectErrorReportService(
        reportStore: store,
      );

      await service.clearSentReports();

      expect(await sentRepository.load(), isEmpty);
    });

    test('permanent failure does not queue the current report', () async {
      final repository = _Queue(store, DirectErrorReportService.pendingKind);
      final service = DirectErrorReportService(
        reportStore: store,
        client: MockClient(
          (request) async => http.Response('bad request', 400),
        ),
      );

      final result = await service.submitReport(
        _buildReport(
          id: 'invalid-current-report',
          queueType: DirectErrorReportQueueType.automaticRetry,
        ),
      );
      final remainingReports = await repository.load();

      expect(result.status, DirectReportDeliveryStatus.failed);
      expect(result.isQueued, isFalse);
      expect(remainingReports, isEmpty);
    });

    test('404 is treated as transient and queues the current report', () async {
      final repository = _Queue(store, DirectErrorReportService.pendingKind);
      final service = DirectErrorReportService(
        reportStore: store,
        client: MockClient((request) async => http.Response('not found', 404)),
      );

      final result = await service.submitReport(
        _buildReport(
          id: 'missing-endpoint-report',
          queueType: DirectErrorReportQueueType.automaticRetry,
        ),
      );
      final remainingReports = await repository.load();

      expect(result.status, DirectReportDeliveryStatus.queued);
      expect(result.isQueued, isTrue);
      expect(remainingReports.map((report) => report.id).toList(), [
        'missing-endpoint-report',
      ]);
      expect(
        remainingReports.single.queueType,
        DirectErrorReportQueueType.automaticRetry,
      );
    });

    test(
      'transient failure queue message uses sefaria label for sefaria source',
      () async {
        final service = DirectErrorReportService(
          reportStore: store,
          client: MockClient(
            (request) async => http.Response('not found', 404),
          ),
        );

        final result = await service.submitReport(
          _buildReport(
            id: 'sefaria-missing-endpoint-report',
            sourceFolder: 'sefaria',
            queueType: DirectErrorReportQueueType.automaticRetry,
          ),
        );

        expect(result.status, DirectReportDeliveryStatus.queued);
        expect(result.message, contains('לספריא'));
      },
    );
  });

  group('שני חלונות על אותו מסד', () {
    test('דיווחים משני חיבורים נשמרים יחד, ושליחה מוחקת רק את הנשלח', () async {
      final path = '${tmp.path}${Platform.pathSeparator}user_state.db';
      final secondDb = UserStateDatabase.openAt(path);
      addTearDown(secondDb.close);
      final first = DirectErrorReportService(reportStore: store);
      final second = DirectErrorReportService(
        reportStore: PendingReportStore(database: secondDb),
      );

      await first.queueReport(_buildReport(id: 'w1-a'));
      await second.queueReport(_buildReport(id: 'w2-a'));
      await first.queueReport(_buildReport(id: 'w1-b'));
      await second.queueReport(_buildReport(id: 'w2-b'));

      expect((await first.getPendingReports()).map((r) => r.id), [
        'w1-a',
        'w2-a',
        'w1-b',
        'w2-b',
      ]);
      expect(await second.getPendingReportsCount(), 4);

      final sender = DirectErrorReportService(
        client: MockClient((_) async => http.Response('', 200)),
        reportStore: store,
      );
      await sender.submitPendingReport(_buildReport(id: 'w2-a'));
      await pumpEventQueue();

      expect((await second.getPendingReports()).map((r) => r.id), [
        'w1-a',
        'w1-b',
        'w2-b',
      ]);
      expect((await second.getSentReports()).single.id, 'w2-a');
    });
  });

  _textCorrectionServiceTests();
}

http.Response _utf8Response(String body) => http.Response.bytes(
  utf8.encode(body),
  200,
  headers: const {'content-type': 'application/json; charset=utf-8'},
);

void _textCorrectionServiceTests() {
  String supportedBody({bool replay = false}) => jsonEncode({
    'success': true,
    'accepted': true,
    'correction_supported': true,
    'duplicate': false,
    'idempotent_replay': replay,
    'message': 'הדיווח נקלט',
  });

  group('חוזה A — סיווג תשובות (§2.4)', () {
    for (final status in [400, 409, 413, 422]) {
      test('[T7/T9] $status הוא כשל קבוע — לא נכנס לתור', () async {
        final repository = _Queue(store, DirectErrorReportService.pendingKind);
        final service = DirectErrorReportService(
          client: MockClient((_) async => http.Response('{}', status)),
          reportStore: store,
        );

        final result = await service.submitReport(
          buildCorrectionReport(id: 'perm-$status'),
        );

        expect(result.status, DirectReportDeliveryStatus.failed);
        expect(await repository.load(), isEmpty);
        if (status == 409) {
          expect(result.message, ReportMessages.reportIdConflict);
        }
      });
    }

    for (final status in [408, 429, 500, 503]) {
      test('[T10] $status הוא כשל זמני — נשמר בתור לניסיון חוזר', () async {
        final repository = _Queue(store, DirectErrorReportService.pendingKind);
        final service = DirectErrorReportService(
          client: MockClient((_) async => http.Response('{}', status)),
          reportStore: store,
        );

        final report = buildCorrectionReport(id: 'transient-$status');
        final result = await service.submitReport(report);

        expect(result.status, DirectReportDeliveryStatus.queued);
        final queued = (await repository.load()).single;
        expect(queued.correction, report.correction);
        expect(queued.queueType, DirectErrorReportQueueType.automaticRetry);
      });
    }

    test('[T7] 409 בשליחה מהתור משאיר את הדיווח בתור', () async {
      final repository = _Queue(store, DirectErrorReportService.pendingKind);
      final report = buildCorrectionReport(id: 'conflict');
      await repository.overwrite([report]);
      final service = DirectErrorReportService(
        client: MockClient((_) async => http.Response('{}', 409)),
        reportStore: store,
      );

      final result = await service.submitPendingReport(report);

      expect(result.status, DirectReportDeliveryStatus.failed);
      expect(result.message, ReportMessages.pendingReportIdConflict);
      final kept = (await repository.load()).single;
      expect(kept.id, isNot('conflict'), reason: 'שליחה חוזרת = מזהה חדש');
      expect(kept.correction, report.correction);
      expect(kept.queueType, DirectErrorReportQueueType.manual);
    });

    test('[T7] אחרי 409, "שלח" שוב שולח במזהה החדש ונקלט', () async {
      final repository = _Queue(store, DirectErrorReportService.pendingKind);
      await repository.overwrite([buildCorrectionReport(id: 'conflict')]);
      final sentIds = <String>[];
      final service = DirectErrorReportService(
        client: MockClient((request) async {
          final id = (jsonDecode(request.body) as Map)['report_id'] as String;
          sentIds.add(id);
          return id == 'conflict'
              ? http.Response('{}', 409)
              : _utf8Response(supportedBody());
        }),
        reportStore: store,
      );

      await service.submitPendingReport((await repository.load()).single);
      final second = await service.submitPendingReport(
        (await repository.load()).single,
      );

      expect(second.isSent, isTrue);
      expect(sentIds, hasLength(2));
      expect(sentIds.last, isNot('conflict'));
      expect(await repository.load(), isEmpty);
    });

    test(
      '[T7] 409 בשליחה האוטומטית: מזהה חדש, נשאר בתור ולא נשלח שוב לבד',
      () async {
        final repository = _Queue(store, DirectErrorReportService.pendingKind);
        final sentRepository = _Queue(store, DirectErrorReportService.sentKind);
        await repository.overwrite([
          buildCorrectionReport(id: 'conflict').copyWith(
            queueType: DirectErrorReportQueueType.automaticRetry,
          ),
        ]);
        var calls = 0;
        final service = DirectErrorReportService(
          client: MockClient((_) async {
            calls++;
            return http.Response('{}', 409);
          }),
          reportStore: store,
        );

        await service.flushPendingReports(onlyAutomaticRetry: true);
        await service.flushPendingReports(onlyAutomaticRetry: true);

        final kept = (await repository.load()).single;
        expect(kept.id, isNot('conflict'));
        expect(kept.queueType, DirectErrorReportQueueType.manual);
        expect(calls, 1, reason: '409 הוא כשל קבוע — אין ניסיון חוזר אוטומטי');
        expect(await sentRepository.load(), isEmpty);
      },
    );
  });

  group('תקרת גוף הבקשה (§2.2: 256KB)', () {
    test('נמדדת בבתי UTF-8 ולא ביחידות UTF-16', () {
      // 140,000 אותיות עבריות = 280,000 בתים, אך רק 140,000 יחידות UTF-16.
      final report = buildCorrectionReport(errorDetails: 'א' * 140000);
      expect(
        report.apiBody.length,
        lessThan(DirectErrorReport.maxApiBodyBytes),
      );
      expect(report.exceedsApiBodyLimit, isTrue);
      expect(buildCorrectionReport().exceedsApiBodyLimit, isFalse);
    });

    test('גוף גדול מדי אינו נשלח, וההודעה ייעודית', () async {
      var calls = 0;
      final repository = _Queue(store, DirectErrorReportService.pendingKind);
      final service = DirectErrorReportService(
        client: MockClient((_) async {
          calls++;
          return http.Response('{}', 200);
        }),
        reportStore: store,
      );

      final result = await service.submitReport(
        buildCorrectionReport(errorDetails: 'א' * 140000),
      );

      expect(calls, 0);
      expect(result.status, DirectReportDeliveryStatus.failed);
      expect(result.message, ReportMessages.bodyTooLarge(256));
      expect(await repository.load(), isEmpty);
    });

    test('בשליחה מהתור: נשמר בהיסטוריה כנדחה עם ההצעה', () async {
      final repository = _Queue(store, DirectErrorReportService.pendingKind);
      final sentRepository = _Queue(store, DirectErrorReportService.sentKind);
      final big = buildCorrectionReport(id: 'big', errorDetails: 'א' * 140000);
      await repository.overwrite([big]);
      final service = DirectErrorReportService(
        client: MockClient((_) async => http.Response('{}', 200)),
        reportStore: store,
      );

      await service.flushPendingReports();

      expect(await repository.load(), isEmpty);
      final recorded = (await sentRepository.load()).single;
      expect(recorded.correction, big.correction);
      expect(recorded.rejectionReason, ReportMessages.bodyTooLarge(256));
    });
  });

  group('כשל קבוע בשליחה מהתור אינו מאבד את ההצעה', () {
    for (final status in [400, 413, 422]) {
      test('$status: לא חוזר לתור, נשמר בהיסטוריה כנדחה עם ההצעה', () async {
        final repository = _Queue(store, DirectErrorReportService.pendingKind);
        final sentRepository = _Queue(store, DirectErrorReportService.sentKind);
        final report = buildCorrectionReport(id: 'rejected-$status');
        await repository.overwrite([report]);
        final service = DirectErrorReportService(
          client: MockClient((_) async => http.Response('{}', status)),
          reportStore: store,
        );

        await service.flushPendingReports();

        expect(await repository.load(), isEmpty);
        final recorded = (await sentRepository.load()).single;
        expect(recorded.id, report.id);
        expect(recorded.correction, report.correction);
        expect(
          recorded.rejectionReason,
          ReportMessages.serverPermanentFailure(status),
        );
        final restored = DirectErrorReport.fromJson(
          jsonDecode(jsonEncode(recorded.toJson())) as Map<String, dynamic>,
        );
        expect(restored, recorded);
      });
    }
  });

  group('[T6] שליחה חוזרת באותו מזהה', () {
    test(
      '[T6] ניסיון חוזר אחרי כשל זמני שולח payload זהה בייט-לבייט',
      () async {
        final bodies = <String>[];
        var calls = 0;
        final repository = _Queue(store, DirectErrorReportService.pendingKind);
        final sentRepository = _Queue(store, DirectErrorReportService.sentKind);
        final service = DirectErrorReportService(
          client: MockClient((request) async {
            bodies.add(request.body);
            calls++;
            return calls == 1
                ? http.Response('{}', 503)
                : _utf8Response(supportedBody(replay: true));
          }),
          reportStore: store,
        );

        final first = await service.submitReport(
          buildCorrectionReport(id: 'retry-me'),
        );
        expect(first.isQueued, isTrue);
        final sentCount = await service.flushPendingReports();

        expect(sentCount, 1);
        expect(bodies, hasLength(2));
        expect(bodies[1], bodies[0]);
        expect(await repository.load(), isEmpty);
        expect((await sentRepository.load()).single.id, 'retry-me');
      },
    );
  });

  group('[T7] עריכה בתור מקבלת מזהה חדש', () {
    test('[T7] שינוי תוכן = report_id ו-digest חדשים; ההצעה נשמרת', () async {
      final repository = _Queue(store, DirectErrorReportService.pendingKind);
      final report = buildCorrectionReport(id: 'editable');
      await repository.overwrite([report]);
      final service = DirectErrorReportService(reportStore: store);

      await service.updatePendingReport(
        report.copyWith(errorDetails: 'הסבר חדש'),
      );

      final updated = (await repository.load()).single;
      expect(updated.id, isNot('editable'));
      expect(updated.errorDetails, 'הסבר חדש');
      expect(updated.correction, report.correction);
      expect(updated.correction!.originalLine, trickyLine);
      expect(updated.contentDigest, isNot(report.contentDigest));
    });

    test(
      'surrogate בודד בדיווח שמור אינו מפיל עריכה או ייצוא סקריפט',
      () async {
        final repository = _Queue(store, DirectErrorReportService.pendingKind);
        final broken = buildCorrectionReport(
          id: 'broken',
          errorDetails: 'x\uD83D',
        );
        final valid = buildCorrectionReport(id: 'valid');
        await repository.overwrite([broken, valid]);
        final service = DirectErrorReportService(reportStore: store);

        await service.updatePendingReport(
          broken.copyWith(errorDetails: 'תקין'),
        );
        final updated = (await repository.load()).first;
        expect(updated.id, isNot('broken'));
        expect(updated.errorDetails, 'תקין');

        final script = service.buildOfflineSendScript(
          [broken, valid],
          target: OfflineSendScriptTarget.unix,
        );
        expect(script.content, contains('valid'));
        expect(script.content, isNot(contains('broken')));
      },
    );

    test('[T7] עריכה שלא שינתה תוכן שומרת את המזהה', () async {
      final repository = _Queue(store, DirectErrorReportService.pendingKind);
      final report = buildCorrectionReport(id: 'same');
      await repository.overwrite([report]);
      final service = DirectErrorReportService(reportStore: store);

      await service.updatePendingReport(
        report.copyWith(queueType: DirectErrorReportQueueType.manual),
      );

      expect((await repository.load()).single.id, 'same');
    });
  });

  group('correction_supported — אתר חדש מול אתר ישן', () {
    test('אתר חדש: "נקלט" ודגל serverAcceptedCorrection=true', () async {
      final sentRepository = _Queue(store, DirectErrorReportService.sentKind);
      final service = DirectErrorReportService(
        client: MockClient((_) async => _utf8Response(supportedBody())),
        reportStore: store,
      );

      final result = await service.submitReport(buildCorrectionReport());

      expect(result.isSent, isTrue);
      expect(result.correctionNotSupported, isFalse);
      expect(result.message, contains('נקלט'));
      expect(result.message, isNot(contains('אושר')));
      expect(
        (await sentRepository.load()).single.serverAcceptedCorrection,
        isTrue,
      );
    });

    test(
      'אתר ישן בלי correction_supported: ההצעה לא אובדת — נשמרת עם דגל והודעה',
      () async {
        final bodies = <Map<String, dynamic>>[];
        final sentRepository = _Queue(store, DirectErrorReportService.sentKind);
        final service = DirectErrorReportService(
          client: MockClient((request) async {
            bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
            return http.Response('{"success":true}', 200);
          }),
          reportStore: store,
        );

        final report = buildCorrectionReport();
        final result = await service.submitReport(report);

        expect(result.isSent, isTrue);
        expect(result.correctionNotSupported, isTrue);
        expect(
          result.message,
          ReportMessages.correctionNotSupportedByServer('אוצריא'),
        );
        final saved = (await sentRepository.load()).single;
        expect(saved.serverAcceptedCorrection, isFalse);
        expect(saved.correction, report.correction);
        // האתר הישן קיבל את ההצעה כטקסט בפירוט הטעות.
        expect(bodies.single['error_details'], contains('מוצע: אֱלֹקִ֑ים'));
      },
    );

    test('דיווח חופשי אינו מסומן גם בלי correction_supported', () async {
      final sentRepository = _Queue(store, DirectErrorReportService.sentKind);
      final service = DirectErrorReportService(
        client: MockClient((_) async => http.Response('{"success":true}', 200)),
        reportStore: store,
      );

      final result = await service.submitReport(_buildReport(id: 'free'));

      expect(result.correctionNotSupported, isFalse);
      expect(
        (await sentRepository.load()).single.serverAcceptedCorrection,
        isNull,
      );
    });

    test('שליחה אוטומטית מהתור מסמנת גם היא את הדגל', () async {
      final repository = _Queue(store, DirectErrorReportService.pendingKind);
      final sentRepository = _Queue(store, DirectErrorReportService.sentKind);
      await repository.overwrite([
        buildCorrectionReport(
          id: 'queued',
        ).copyWith(queueType: DirectErrorReportQueueType.automaticRetry),
      ]);
      final service = DirectErrorReportService(
        client: MockClient((_) async => http.Response('', 200)),
        reportStore: store,
      );

      await service.flushPendingReports(onlyAutomaticRetry: true);

      expect(
        (await sentRepository.load()).single.serverAcceptedCorrection,
        isFalse,
      );
    });
  });

  test('[T1] דיווח ישן מהתור נשלח ב-payload הישן בדיוק', () async {
    final bodies = <Map<String, dynamic>>[];
    final service = DirectErrorReportService(
      client: MockClient((request) async {
        bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
        return http.Response('', 200);
      }),
      reportStore: store,
    );

    final legacy = DirectErrorReport.fromJson({
      'id': 'legacy',
      'senderEmail': 'user@example.com',
      'subject': 'legacy',
      'bookTitle': 'legacy book',
      'currentRef': 'legacy ref',
      'lineNumber': 3,
      'createdAt': '2026-03-16T10:15:00Z',
    });
    final result = await service.submitReport(legacy);

    expect(result.isSent, isTrue);
    expect(bodies.single, jsonDecode(jsonEncode(legacy.toApiPayload())));
    expect(bodies.single.containsKey('schema_version'), isFalse);
    expect(bodies.single.containsKey('content_digest'), isFalse);
  });
}

DirectErrorReport _buildReport({
  required String id,
  String sourceFolder = 'local',
  DirectErrorReportQueueType queueType = DirectErrorReportQueueType.manual,
}) {
  return DirectErrorReport(
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
    sourceFolder: sourceFolder,
    queueType: queueType,
    createdAt: DateTime.parse('2026-03-16T10:15:00Z'),
  );
}

/// מציג סוג אחד בתור המשותף כרשימה, כדי שהבדיקות יזרעו וייבדקו בנוחות.
class _Queue {
  _Queue(this._store, this._kind);

  final PendingReportStore _store;
  final String _kind;

  Future<List<DirectErrorReport>> load() async {
    final rows = await _store.listByKind(_kind);
    return rows.map((row) => DirectErrorReport.fromJson(row.payload)).toList();
  }

  Future<void> overwrite(List<DirectErrorReport> reports) async {
    await _store.deleteAllOfKind(_kind);
    for (final report in reports) {
      await _store.add(_kind, report.toJson());
    }
  }
}

class _MemoryCacheProvider extends CacheProvider {
  final Map<String, Object?> _values = {};

  @override
  Future<void> init() async {}

  @override
  bool containsKey(String key) => _values.containsKey(key);

  @override
  Set getKeys() => _values.keys.toSet();

  @override
  bool? getBool(String key, {bool? defaultValue}) =>
      _values[key] as bool? ?? defaultValue;

  @override
  double? getDouble(String key, {double? defaultValue}) =>
      _values[key] as double? ?? defaultValue;

  @override
  int? getInt(String key, {int? defaultValue}) =>
      _values[key] as int? ?? defaultValue;

  @override
  String? getString(String key, {String? defaultValue}) =>
      _values[key] as String? ?? defaultValue;

  @override
  T? getValue<T>(String key, {T? defaultValue}) {
    final value = _values[key];
    if (value is T) {
      return value;
    }
    return defaultValue;
  }

  @override
  Future<void> remove(String key) async {
    _values.remove(key);
  }

  @override
  Future<void> removeAll() async {
    _values.clear();
  }

  @override
  Future<void> setBool(String key, bool? value) async {
    _values[key] = value;
  }

  @override
  Future<void> setDouble(String key, double? value) async {
    _values[key] = value;
  }

  @override
  Future<void> setInt(String key, int? value) async {
    _values[key] = value;
  }

  @override
  Future<void> setString(String key, String? value) async {
    _values[key] = value;
  }

  @override
  Future<void> setObject<T>(String key, T? value) async {
    _values[key] = value;
  }
}
