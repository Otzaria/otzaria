import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:otzaria/data/repository/hive_list_repository.dart';
import 'package:otzaria/models/direct_error_report.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/services/direct_error_report_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
          script.content, contains('https://otzaria.org/api/reportingerrors'));
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
          script.content, contains('https://otzaria.org/api/reportingerrors'));
      expect(script.content, contains('zenity'));
      expect(script.content, contains('osascript'));
      expect(script.content, contains("'report-42'"));
      expect(script.content, isNot(contains('FromBase64String')));
    });
  });

  group('DirectErrorReportService.flushPendingReports', () {
    test('automatic flush sends only retryable queued reports', () async {
      final repository = InMemoryDirectErrorReportRepository();
      final sentRepository = InMemoryDirectErrorReportRepository();

      await repository.save([
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
        client: MockClient((request) async {
          final payload = jsonDecode(request.body) as Map<String, dynamic>;
          sentReportIds.add(payload['report_id'] as String);
          return http.Response('', 200);
        }),
        queueRepository: repository,
        sentRepository: sentRepository,
      );

      final sentCount =
          await service.flushPendingReports(onlyAutomaticRetry: true);
      final remainingReports = await repository.load();

      expect(sentCount, 1);
      expect(sentReportIds, ['retry-report']);
      expect((await sentRepository.load()).single.id, 'retry-report');
      expect(
        remainingReports.map((report) => report.id).toList(),
        ['manual-report'],
      );
    });

    test('permanent failure is removed and does not block later reports',
        () async {
      final repository = InMemoryDirectErrorReportRepository();
      final sentRepository = InMemoryDirectErrorReportRepository();

      await repository.save([
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
      final service = DirectErrorReportService(
        client: MockClient((request) async {
          final payload = jsonDecode(request.body) as Map<String, dynamic>;
          final reportId = payload['report_id'] as String;
          attemptedReportIds.add(reportId);

          if (reportId == 'invalid-report') {
            return http.Response('bad request', 400);
          }

          return http.Response('', 200);
        }),
        queueRepository: repository,
        sentRepository: sentRepository,
      );

      final sentCount =
          await service.flushPendingReports(onlyAutomaticRetry: true);
      final remainingReports = await repository.load();

      expect(sentCount, 1);
      expect(attemptedReportIds, ['invalid-report', 'valid-report']);
      expect((await sentRepository.load()).single.id, 'valid-report');
      expect(
        remainingReports.map((report) => report.id).toList(),
        ['manual-report'],
      );
    });
  });

  group('DirectErrorReportService.submitReport', () {
    test('success message uses sefaria label for sefaria sourced books',
        () async {
      final repository = InMemoryDirectErrorReportRepository();
      final sentRepository = InMemoryDirectErrorReportRepository();
      final service = DirectErrorReportService(
        client: MockClient((request) async => http.Response('', 200)),
        queueRepository: repository,
        sentRepository: sentRepository,
      );

      final result = await service.submitReport(
        _buildReport(
          id: 'sefaria-success-report',
          sourceFolder: 'sefariaToOtzaria',
        ),
      );

      expect(result.status, DirectReportDeliveryStatus.sent);
      expect(result.message, 'הדיווח נשלח בהצלחה לספריא.');
      expect((await sentRepository.load()).single.id, 'sefaria-success-report');
    });

    test('submitPendingReport removes sent report from queue', () async {
      final repository = InMemoryDirectErrorReportRepository();
      final sentRepository = InMemoryDirectErrorReportRepository();
      final report = _buildReport(id: 'pending-report');
      await repository.save([report]);
      final service = DirectErrorReportService(
        client: MockClient((request) async => http.Response('', 200)),
        queueRepository: repository,
        sentRepository: sentRepository,
      );

      final result = await service.submitPendingReport(report);

      expect(result.status, DirectReportDeliveryStatus.sent);
      expect(await repository.load(), isEmpty);
      expect((await sentRepository.load()).single.id, 'pending-report');
    });

    test('updatePendingReport edits a saved queued report', () async {
      final repository = InMemoryDirectErrorReportRepository();
      final report = _buildReport(id: 'editable-report');
      await repository.save([report]);
      final service = DirectErrorReportService(
        queueRepository: repository,
      );

      await service.updatePendingReport(
        report.copyWith(errorDetails: 'פרט מתוקן'),
      );

      final reports = await repository.load();
      expect(reports.single.errorDetails, 'פרט מתוקן');
    });

    test('markPendingReportAsSent moves a queued report to sent history',
        () async {
      final repository = InMemoryDirectErrorReportRepository();
      final sentRepository = InMemoryDirectErrorReportRepository();
      final report = _buildReport(id: 'manual-sent-report');
      await repository.save([
        report,
        _buildReport(id: 'other-report'),
      ]);
      final service = DirectErrorReportService(
        queueRepository: repository,
        sentRepository: sentRepository,
      );

      await service.markPendingReportAsSent(report);

      expect(
        (await repository.load()).map((report) => report.id).toList(),
        ['other-report'],
      );
      expect((await sentRepository.load()).single.id, 'manual-sent-report');
    });

    test('deleteSentReport removes a report from sent history', () async {
      final sentRepository = InMemoryDirectErrorReportRepository();
      await sentRepository.save([
        _buildReport(id: 'sent-a'),
        _buildReport(id: 'sent-b'),
      ]);
      final service = DirectErrorReportService(
        sentRepository: sentRepository,
      );

      await service.deleteSentReport('sent-a');

      expect(
        (await sentRepository.load()).map((report) => report.id).toList(),
        ['sent-b'],
      );
    });

    test('clearSentReports clears sent history', () async {
      final sentRepository = InMemoryDirectErrorReportRepository();
      await sentRepository.save([
        _buildReport(id: 'sent-a'),
        _buildReport(id: 'sent-b'),
      ]);
      final service = DirectErrorReportService(
        sentRepository: sentRepository,
      );

      await service.clearSentReports();

      expect(await sentRepository.load(), isEmpty);
    });

    test('permanent failure does not queue the current report', () async {
      final repository = InMemoryDirectErrorReportRepository();
      final service = DirectErrorReportService(
        client:
            MockClient((request) async => http.Response('bad request', 400)),
        queueRepository: repository,
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
      final repository = InMemoryDirectErrorReportRepository();
      final service = DirectErrorReportService(
        client: MockClient((request) async => http.Response('not found', 404)),
        queueRepository: repository,
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
      final repository = InMemoryDirectErrorReportRepository();
      final service = DirectErrorReportService(
        client: MockClient((request) async => http.Response('not found', 404)),
        queueRepository: repository,
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
    });
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

class InMemoryDirectErrorReportRepository
    extends HiveListRepository<DirectErrorReport> {
  List<DirectErrorReport> _items = [];

  InMemoryDirectErrorReportRepository()
      : super(
          boxName: 'in_memory',
          key: 'pending_reports',
          fromJson: DirectErrorReport.fromJson,
          toJson: (report) => report.toJson(),
        );

  @override
  Future<List<DirectErrorReport>> load() async {
    return List<DirectErrorReport>.from(_items);
  }

  @override
  Future<void> save(List<DirectErrorReport> items) async {
    _items = List<DirectErrorReport>.from(items);
  }

  @override
  Future<void> clear() async {
    _items = [];
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
