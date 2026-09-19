import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:otzaria/app_report/models/app_report.dart';
import 'package:otzaria/app_report/models/app_report_image.dart';
import 'package:otzaria/app_report/services/app_report_service.dart';
import 'package:otzaria/core/user_state/pending_report_store.dart';
import 'package:otzaria/core/user_state/user_state_database.dart';
import 'package:otzaria/services/sent_reports_counter.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';

AppReport _report({String? id, String title = 'באג'}) => AppReport(
  reportId: id ?? AppReport.generateReportId(),
  type: AppReportType.bug,
  trigger: AppReportTrigger.manual,
  title: title,
  description: 'תיאור',
  reporterEmail: 'a@b.com',
  appVersion: '0.9.98',
  platform: 'windows',
  createdAt: DateTime.utc(2026, 9, 17),
  diagnostics: const {'x': 1},
  errorLog: 'log',
);

http.Response _json(int status, Map<String, dynamic> body) => http.Response(
  jsonEncode(body),
  status,
  headers: const {'content-type': 'application/json'},
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: _MemoryCacheProvider());
  });

  late Directory tmp;
  late UserStateDatabase db;
  late PendingReportStore store;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('otzaria_app_reports_');
    db = UserStateDatabase.openAt(
      '${tmp.path}${Platform.pathSeparator}user_state.db',
    );
    store = PendingReportStore(database: db);
    await Settings.setValue<bool>(SettingsRepository.keyOfflineMode, false);
    await Settings.setValue<bool>(
      SettingsRepository.keyQueueErrorReportsWhenOffline,
      true,
    );
  });

  tearDown(() async {
    await AppReportService.suspendAutomaticFlush();
    db.close();
    tmp.deleteSync(recursive: true);
  });

  AppReportService build(MockClient client) => AppReportService(
    client: client,
    reportStore: store,
    sentCounter: SentReportsCounter.inMemory(),
  );

  test('200: נשלח, שדות ה-issue נשמרים בהיסטוריה בלי צרופות', () async {
    Map<String, dynamic>? sentBody;
    final service = build(
      MockClient((request) async {
        expect(request.url, AppReportService.endpoint);
        sentBody = jsonDecode(utf8.decode(request.bodyBytes));
        return _json(200, {
          'success': true,
          'issueNumber': 55,
          'issueUrl': 'https://github.com/Otzaria/otzaria/issues/55',
          'duplicate': false,
          'merged': true,
          'issuePending': false,
        });
      }),
    );
    final report = _report();
    final result = await service.send(report);
    await pumpEventQueue();

    expect(result.isSent, isTrue);
    expect(result.issueNumber, 55);
    expect(result.merged, isTrue);
    expect(sentBody!['reportId'], report.reportId);
    expect(sentBody!['attachments'], {
      'diagnostics': {'x': 1},
      'errorLog': 'log',
    });

    final sent = await service.getSentReports();
    expect(sent, hasLength(1));
    expect(sent.single.issueUrl, contains('/55'));
    expect(sent.single.diagnostics, isNull);
    expect(sent.single.sentAt, isNotNull);
    expect(await service.getPendingReportsCount(), 0);
    expect(await service.getSentReportsTotal(), 1);
  });

  test('200 עם issuePending נחשב נשלח ולא נכנס לתור', () async {
    final service = build(
      MockClient(
        (_) async => _json(200, {
          'success': true,
          'issueNumber': null,
          'issueUrl': null,
          'issuePending': true,
        }),
      ),
    );
    final result = await service.send(_report());
    await pumpEventQueue();
    expect(result.isSent, isTrue);
    expect(result.issuePending, isTrue);
    expect(result.issueNumber, isNull);
    expect(await service.getPendingReportsCount(), 0);
  });

  test('409: מזהה חדש וניסיון חוזר', () async {
    final ids = <String>[];
    final service = build(
      MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        ids.add(body['reportId'] as String);
        if (ids.length == 1) return _json(409, {'error': 'reportId conflict'});
        return _json(200, {'success': true, 'issueNumber': 1});
      }),
    );
    final report = _report();
    final result = await service.send(report);
    await pumpEventQueue();
    expect(ids, hasLength(2));
    expect(ids.first, report.reportId);
    expect(ids.last, isNot(report.reportId));
    expect(result.isSent, isTrue);
    expect(result.report.reportId, ids.last);
  });

  test('422: דחייה קבועה, לא נכנס לתור', () async {
    final service = build(
      MockClient(
        (_) async => _json(422, {'error': 'invalid', 'field': 'reporterEmail'}),
      ),
    );
    final result = await service.send(_report());
    expect(result.isFailed, isTrue);
    expect(result.failureReason, AppReportFailureReason.rejected);
    expect(result.rejectedField, 'reporterEmail');
    expect(result.httpStatus, 422);
    expect(await service.getPendingReportsCount(), 0);
  });

  test('429 נשמר בתור', () async {
    final service = build(MockClient((_) async => http.Response('', 429)));
    final result = await service.send(_report());
    expect(result.isQueued, isTrue);
    expect(await service.getPendingReportsCount(), 1);
    // הרשומה בתור שומרת את הצרופות לשליחה חוזרת.
    expect((await service.getPendingReports()).single.errorLog, 'log');
  });

  test('timeout נשמר בתור', () async {
    final service = build(
      MockClient((_) async => throw TimeoutException('slow')),
    );
    final result = await service.send(_report());
    expect(result.isQueued, isTrue);
    expect(await service.getPendingReportsCount(), 1);
  });

  test('מצב לא-מקוון: נשמר בתור בלי פנייה לשרת; תור כבוי = כשל', () async {
    await Settings.setValue<bool>(SettingsRepository.keyOfflineMode, true);
    var calls = 0;
    final service = build(
      MockClient((_) async {
        calls++;
        return _json(200, {'success': true});
      }),
    );
    expect((await service.send(_report())).isQueued, isTrue);
    expect(calls, 0);

    await Settings.setValue<bool>(
      SettingsRepository.keyQueueErrorReportsWhenOffline,
      false,
    );
    final failed = await service.send(_report());
    expect(failed.failureReason, AppReportFailureReason.offlineQueueDisabled);
    expect(await service.getPendingReportsCount(), 1);
  });

  test('flush: שולח, מסיר נדחים, מחליף מזהה ב-409 ועוצר בכשל זמני', () async {
    final a = _report(title: 'a');
    final rejected = _report(title: 'rejected');
    final conflict = _report(title: 'conflict');
    final transient = _report(title: 'transient');
    final after = _report(title: 'after');

    final seen = <String>[];
    final service = build(
      MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final title = body['title'] as String;
        seen.add(title);
        return switch (title) {
          'a' => _json(200, {'success': true, 'issueNumber': 9}),
          'rejected' => _json(400, {'error': 'bad'}),
          'conflict' => _json(409, {'error': 'reportId conflict'}),
          'transient' => http.Response('', 503),
          _ => _json(200, {'success': true}),
        };
      }),
    );
    for (final r in [a, rejected, conflict, transient, after]) {
      await service.queueReport(r);
    }

    final sentCount = await service.flushPendingReports();
    expect(sentCount, 1);
    expect(seen, ['a', 'rejected', 'conflict', 'transient']);

    final pending = await service.getPendingReports();
    expect(pending.map((r) => r.title), ['conflict', 'transient', 'after']);
    expect(pending.first.reportId, isNot(conflict.reportId));
    expect((await service.getSentReports()).single.issueNumber, 9);
  });

  test('updatePendingReport: תוכן ששונה מקבל מזהה חדש', () async {
    final service = build(MockClient((_) async => http.Response('', 500)));
    final report = _report();
    await service.queueReport(report);

    final same = await service.updatePendingReport(report);
    expect(same!.reportId, report.reportId);

    final changed = await service.updatePendingReport(
      report.copyWith(description: 'אחר'),
    );
    expect(changed!.reportId, isNot(report.reportId));
    expect(
      (await service.getPendingReports()).single.description,
      'אחר',
    );
  });

  test('צילומי מסך: נשלחים, נשמרים בתור בכשל, ונמחקים מההיסטוריה', () async {
    final image = AppReportImage(
      bytes: Uint8List.fromList([0x89, 0x50, 0x4e, 0x47, 9]),
      fileName: 'screenshot-1.png',
      mimeType: 'image/png',
    );
    final report = _report().copyWith(images: [image]);

    final offline = build(MockClient((_) async => http.Response('', 503)));
    expect((await offline.send(report)).isQueued, isTrue);
    final queued = (await offline.getPendingReports()).single;
    expect(queued.images.single.bytes, image.bytes);
    await offline.clearPendingReports();

    Map<String, dynamic>? sentBody;
    final online = build(
      MockClient((request) async {
        sentBody = jsonDecode(utf8.decode(request.bodyBytes));
        return _json(200, {'success': true, 'issueNumber': 7});
      }),
    );
    expect((await online.send(report)).isSent, isTrue);
    await pumpEventQueue();
    final images = (sentBody!['attachments'] as Map)['images'] as List;
    expect(images.single['data'], base64Encode(image.bytes));
    final sent = (await online.getSentReports()).single;
    expect(sent.images, isEmpty);
    expect(sent.toJson().containsKey('images'), isFalse);
  });
}

class _MemoryCacheProvider extends CacheProvider {
  final Map<String, Object?> _values = {};

  @override
  Future<void> init() async {}

  @override
  bool containsKey(String key) => _values.containsKey(key);

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
  T? getValue<T>(String key, {T? defaultValue}) =>
      _values[key] as T? ?? defaultValue;

  @override
  Set getKeys() => _values.keys.toSet();

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
