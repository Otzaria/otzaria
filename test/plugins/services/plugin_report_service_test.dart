import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:otzaria/core/user_state/pending_report_store.dart';
import 'package:otzaria/core/user_state/user_state_database.dart';
import 'package:otzaria/plugins/models/plugin_report_record.dart';
import 'package:otzaria/plugins/services/plugin_report_service.dart';
import 'package:otzaria/services/offline_report_script_builder.dart';
import 'package:otzaria/services/sent_reports_counter.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  PackageInfo.setMockInitialValues(
    appName: 'Otzaria',
    packageName: 'com.otzaria.app',
    version: '0.9.97',
    buildNumber: '1',
    buildSignature: '',
  );

  setUpAll(() async {
    await Settings.init(cacheProvider: _MemoryCacheProvider());
  });

  late Directory tmp;
  late UserStateDatabase db;
  late PendingReportStore store;

  tearDown(() {
    db.close();
    tmp.deleteSync(recursive: true);
  });

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('otzaria_plugin_reports_');
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

  PluginReportService buildService({
    required http.Client client,
    SentReportsCounter? counter,
  }) {
    return PluginReportService(
      client: client,
      reportStore: store,
      sentCounter: counter,
    );
  }

  group('PluginReportService.generateReportId', () {
    test('מייצר UUID v4 תקין וייחודי', () {
      final id = PluginReportService.generateReportId();
      expect(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ).hasMatch(id),
        isTrue,
        reason: 'מזהה לא בפורמט UUID v4: $id',
      );
      expect(id, isNot(PluginReportService.generateReportId()));
    });
  });

  group('PluginReportService.buildRecord', () {
    test('בונה רשומה עם כל שדות החוזה, נרמול וחיתוך', () async {
      final service = PluginReportService(
        reportStore: store,
        client: MockClient((_) async => http.Response('{}', 200)),
      );

      final record = await service.buildRecord(
        pluginUid: 'test.plugin',
        pluginName: 'תוסף בדיקה',
        pluginVersion: '1.2.3',
        details: '  ${'א' * 6000}  ',
        reportType: 'whatever',
        reporterEmail: ' me@example.com ',
      );

      expect(record.pluginUid, 'test.plugin');
      expect(record.reportType, 'other');
      expect(record.details.length, 5000);
      expect(record.reporterEmail, 'me@example.com');
      expect(record.appVersion, '0.9.97');
      expect(record.platform, Platform.operatingSystem);

      final payload = record.toApiPayload();
      expect(
        payload.keys,
        containsAll(<String>[
          'reportId',
          'pluginUid',
          'pluginName',
          'pluginVersion',
          'reportType',
          'details',
          'reporterEmail',
          'appVersion',
          'platform',
        ]),
      );
      expect(payload.containsKey('createdAt'), isFalse);
    });

    test('פירוט ריק נדחה, ומייל ריק מושמט מה-payload', () async {
      final service = PluginReportService(
        reportStore: store,
        client: MockClient((_) async => http.Response('{}', 200)),
      );

      await expectLater(
        service.buildRecord(
          pluginUid: 'test.plugin',
          pluginName: 'Test',
          pluginVersion: '1.0.0',
          details: '   ',
        ),
        throwsA(isA<Exception>()),
      );

      final record = await service.buildRecord(
        pluginUid: 'test.plugin',
        pluginName: 'Test',
        pluginVersion: '1.0.0',
        details: 'משהו',
        reporterEmail: '   ',
      );
      expect(record.toApiPayload().containsKey('reporterEmail'), isFalse);
    });
  });

  group('PluginReportService.submitReport', () {
    test('הצלחה: נשלח, נשמר בהיסטוריה ולא בתור', () async {
      late Map<String, dynamic> body;
      final queue = _Queue(store, PluginReportService.pendingKind);
      final sent = _Queue(store, PluginReportService.sentKind);
      final service = buildService(
        client: MockClient((request) async {
          body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(request.url, PluginReportService.endpoint);
          return http.Response('{"success":true}', 200);
        }),
      );

      final status = await service.submitReport(_buildRecord('r-1'));

      expect(status, PluginReportDeliveryStatus.sent);
      expect(body['reportId'], 'r-1');
      expect(await queue.load(), isEmpty);
      expect((await sent.load()).single.reportId, 'r-1');
    });

    test('כשל זמני: נכנס לתור עם אותו reportId', () async {
      final queue = _Queue(store, PluginReportService.pendingKind);
      final sent = _Queue(store, PluginReportService.sentKind);
      final service = buildService(
        client: MockClient((_) async {
          throw const SocketException('no route to host');
        }),
      );

      final status = await service.submitReport(_buildRecord('r-2'));

      expect(status, PluginReportDeliveryStatus.queued);
      expect((await queue.load()).single.reportId, 'r-2');
      expect(await sent.load(), isEmpty);
    });

    test('דחייה קבועה (400): נזרקת ולא נכנסת לתור', () async {
      final queue = _Queue(store, PluginReportService.pendingKind);
      final service = buildService(
        client: MockClient((_) async => http.Response('bad', 400)),
      );

      await expectLater(
        service.submitReport(_buildRecord('r-3')),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('400'),
          ),
        ),
      );
      expect(await queue.load(), isEmpty);
    });

    test('429 נחשב זמני ונכנס לתור', () async {
      final queue = _Queue(store, PluginReportService.pendingKind);
      final service = buildService(
        client: MockClient((_) async => http.Response('rate limited', 429)),
      );

      final status = await service.submitReport(_buildRecord('r-4'));

      expect(status, PluginReportDeliveryStatus.queued);
      expect((await queue.load()).single.reportId, 'r-4');
    });

    test('מצב לא-מקוון: נכנס לתור בלי ניסיון רשת', () async {
      await Settings.setValue<bool>(SettingsRepository.keyOfflineMode, true);
      var called = false;
      final queue = _Queue(store, PluginReportService.pendingKind);
      final service = buildService(
        client: MockClient((_) async {
          called = true;
          return http.Response('{}', 200);
        }),
      );

      final status = await service.submitReport(_buildRecord('r-5'));

      expect(status, PluginReportDeliveryStatus.queued);
      expect(called, isFalse);
      expect((await queue.load()).single.reportId, 'r-5');
    });

    test('מצב לא-מקוון עם תור כבוי: נזרק ולא נשמר', () async {
      await Settings.setValue<bool>(SettingsRepository.keyOfflineMode, true);
      await Settings.setValue<bool>(
        SettingsRepository.keyQueueErrorReportsWhenOffline,
        false,
      );
      final queue = _Queue(store, PluginReportService.pendingKind);
      final service = buildService(
        client: MockClient((_) async => http.Response('{}', 200)),
      );

      await expectLater(
        service.submitReport(_buildRecord('r-6')),
        throwsA(isA<Exception>()),
      );
      expect(await queue.load(), isEmpty);
    });

    test('שליחה חוזרת של אותו דיווח לא יוצרת כפילות בתור', () async {
      final queue = _Queue(store, PluginReportService.pendingKind);
      final service = buildService(
        client: MockClient((_) async {
          throw const SocketException('down');
        }),
      );

      final record = _buildRecord('r-7');
      await service.submitReport(record);
      await service.submitReport(record);

      expect((await queue.load()).length, 1);
    });
  });

  group('PluginReportService.submitPendingReport', () {
    test('הרשומה מוסרת מהתור לפני השליחה — אין שליחה כפולה מה-flush', () async {
      final queue = _Queue(store, PluginReportService.pendingKind);
      await queue.seed([_buildRecord('p-1')]);
      final sent = _Queue(store, PluginReportService.sentKind);
      var calls = 0;
      late final PluginReportService service;
      service = PluginReportService(
        reportStore: store,
        client: MockClient((request) async {
          calls++;
          // בזמן השליחה הרשומה כבר לא בתור — כך flush מקביל לא ימצא אותה.
          expect(await queue.load(), isEmpty);
          return http.Response('{"success":true}', 200);
        }),
      );

      final status = await service.submitPendingReport(_buildRecord('p-1'));

      expect(status, PluginReportDeliveryStatus.sent);
      expect(calls, 1);
      expect(await queue.load(), isEmpty);
      expect((await sent.load()).single.reportId, 'p-1');
    });

    test('כשל זמני בשליחה ידנית מחזיר את הרשומה לתור', () async {
      final queue = _Queue(store, PluginReportService.pendingKind);
      await queue.seed([_buildRecord('p-2')]);
      final service = buildService(
        client: MockClient((_) async {
          throw const SocketException('down');
        }),
      );

      final status = await service.submitPendingReport(_buildRecord('p-2'));

      expect(status, PluginReportDeliveryStatus.queued);
      expect((await queue.load()).single.reportId, 'p-2');
    });
  });

  group('PluginReportService.flushPendingReports', () {
    test('שולח את התור, מעביר להיסטוריה ושומר reportId יציב', () async {
      final queue = _Queue(store, PluginReportService.pendingKind);
      await queue.seed([_buildRecord('q-1'), _buildRecord('q-2')]);
      final sent = _Queue(store, PluginReportService.sentKind);
      final sentIds = <String>[];
      final service = buildService(
        client: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          sentIds.add(body['reportId'] as String);
          return http.Response('{"success":true}', 200);
        }),
      );

      final sentCount = await service.flushPendingReports();

      expect(sentCount, 2);
      expect(sentIds, ['q-1', 'q-2']);
      expect(await queue.load(), isEmpty);
      expect((await sent.load()).length, 2);
    });

    test('עוצר בכשל זמני ראשון ומשאיר את השאר בתור', () async {
      final queue = _Queue(store, PluginReportService.pendingKind);
      await queue.seed([_buildRecord('q-1'), _buildRecord('q-2')]);
      var calls = 0;
      final service = buildService(
        client: MockClient((_) async {
          calls++;
          throw const SocketException('down');
        }),
      );

      final sentCount = await service.flushPendingReports();

      expect(sentCount, 0);
      expect(calls, 1);
      expect((await queue.load()).length, 2);
    });

    test('דחייה קבועה מוסרת מהתור בלי להיספר כנשלחה', () async {
      final queue = _Queue(store, PluginReportService.pendingKind);
      await queue.seed([_buildRecord('q-bad'), _buildRecord('q-good')]);
      final service = buildService(
        client: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          return body['reportId'] == 'q-bad'
              ? http.Response('bad', 400)
              : http.Response('{"success":true}', 200);
        }),
      );

      final sentCount = await service.flushPendingReports();

      expect(sentCount, 1);
      expect(await queue.load(), isEmpty);
    });

    test('במצב לא-מקוון לא שולח כלום', () async {
      await Settings.setValue<bool>(SettingsRepository.keyOfflineMode, true);
      final queue = _Queue(store, PluginReportService.pendingKind);
      await queue.seed([_buildRecord('q-1')]);
      var called = false;
      final service = buildService(
        client: MockClient((_) async {
          called = true;
          return http.Response('{}', 200);
        }),
      );

      expect(await service.flushPendingReports(), 0);
      expect(called, isFalse);
    });
  });

  group('PluginReportService.updatePendingReport (issue #1340)', () {
    PluginReportService serviceFor() => buildService(
      client: MockClient((_) async => http.Response('{}', 200)),
    );

    test('שינוי בתוכן: סוג ופירוט מתעדכנים ומתקבל reportId חדש', () async {
      final queue = _Queue(store, PluginReportService.pendingKind);
      await queue.seed([_buildRecord('q-1'), _buildRecord('q-2')]);

      await serviceFor().updatePendingReport(
        'q-1',
        reportType: 'crash',
        details: '  חדש  ',
      );

      final records = await queue.load();
      expect(records, hasLength(2));
      expect(records.first.reportId, isNot('q-1'));
      expect(records.first.reportType, 'crash');
      expect(records.first.details, 'חדש');
      expect(records.first.pluginUid, _buildRecord('q-1').pluginUid);
      expect(records.last.reportId, 'q-2');
    });

    test('בלי שינוי: המזהה נשמר', () async {
      final original = _buildRecord('q-1');
      final queue = _Queue(store, PluginReportService.pendingKind);
      await queue.seed([original]);

      await serviceFor().updatePendingReport(
        'q-1',
        reportType: original.reportType,
        details: original.details,
      );

      expect((await queue.load()).single.reportId, 'q-1');
    });

    test('פירוט ריק נדחה והדיווח לא משתנה', () async {
      final queue = _Queue(store, PluginReportService.pendingKind);
      await queue.seed([_buildRecord('q-1')]);

      await expectLater(
        serviceFor().updatePendingReport(
          'q-1',
          reportType: 'bug',
          details: '   ',
        ),
        throwsException,
      );
      expect((await queue.load()).single.reportId, 'q-1');
    });

    test('סוג לא מוכר מנורמל ל-other', () async {
      final queue = _Queue(store, PluginReportService.pendingKind);
      await queue.seed([_buildRecord('q-1')]);

      await serviceFor().updatePendingReport(
        'q-1',
        reportType: 'weird',
        details: 'אחר',
      );

      expect((await queue.load()).single.reportType, 'other');
    });
  });

  group('PluginReportService — ספירת הנשלחים מעבר לתקרה (issue #1343)', () {
    test('המונה ממשיך מעבר לתקרת ההיסטוריה', () async {
      final max = PluginReportService.maxSentReportsToKeep;
      final queue = _Queue(store, PluginReportService.pendingKind);
      await queue.seed([
        for (var i = 0; i < max + 5; i++) _buildRecord('q-$i'),
      ]);
      final sent = _Queue(store, PluginReportService.sentKind);
      final service = buildService(
        client: MockClient((_) async => http.Response('{}', 200)),
      );

      while ((await queue.load()).isNotEmpty) {
        await service.flushPendingReports();
      }

      expect((await sent.load()).length, max);
      expect(await service.getSentReportsTotal(), max + 5);
    });

    test('שליחה חוזרת של אותו מזהה לא נספרת פעמיים', () async {
      final counter = SentReportsCounter.inMemory();
      final service = buildService(
        client: MockClient((_) async => http.Response('{}', 200)),
        counter: counter,
      );

      await service.submitReport(_buildRecord('r-1'));
      await service.submitReport(_buildRecord('r-1'));

      expect(await counter.read(), 1);
    });

    test('מתקין בלי מונה: מתחיל מגודל ההיסטוריה, וניקוי מאפס', () async {
      await _Queue(
        store,
        PluginReportService.sentKind,
      ).seed([_buildRecord('old-1'), _buildRecord('old-2')]);
      final service = buildService(
        client: MockClient((_) async => http.Response('{}', 200)),
      );

      expect(await service.getSentReportsTotal(), 2);
      await service.submitReport(_buildRecord('new'));
      expect(await service.getSentReportsTotal(), 3);

      await service.clearSentReports();
      expect(await service.getSentReportsTotal(), 0);
    });
  });

  group('שני חלונות על אותו מסד', () {
    test('דיווחים משני חיבורים נשמרים יחד, ושליחה מוחקת רק את הנשלח', () async {
      final secondDb = UserStateDatabase.openAt(
        '${tmp.path}${Platform.pathSeparator}user_state.db',
      );
      addTearDown(secondDb.close);
      final first = PluginReportService(
        client: MockClient((_) async {
          throw const SocketException('down');
        }),
        reportStore: store,
      );
      final second = PluginReportService(
        client: MockClient((_) async {
          throw const SocketException('down');
        }),
        reportStore: PendingReportStore(database: secondDb),
      );

      await first.submitReport(_buildRecord('w1-a'));
      await second.submitReport(_buildRecord('w2-a'));
      await first.submitReport(_buildRecord('w1-b'));

      expect((await second.getPendingReports()).map((r) => r.reportId), [
        'w1-a',
        'w2-a',
        'w1-b',
      ]);
      expect(await first.getPendingReportsCount(), 3);

      // רק w2-a נשלח; שאר התור נכשל זמנית, כך שה-flush שברקע אינו מרוקן אותו.
      final sender = PluginReportService(
        client: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          if (body['reportId'] != 'w2-a') throw const SocketException('down');
          return http.Response('{"success":true}', 200);
        }),
        reportStore: store,
      );
      await sender.submitPendingReport(_buildRecord('w2-a'));
      await pumpEventQueue();

      expect((await second.getPendingReports()).map((r) => r.reportId), [
        'w1-a',
        'w1-b',
      ]);
      expect((await first.getSentReports()).single.reportId, 'w2-a');
    });
  });

  group('PluginReportService.buildOfflineSendScript', () {
    test('סקריפט Windows נבנה עם CRLF ומכיל את ה-payload והמזהה', () {
      final service = buildService(
        client: MockClient((_) async => http.Response('{}', 200)),
      );

      final script = service.buildOfflineSendScript(
        [_buildRecord('s-1')],
        target: OfflineSendScriptTarget.windows,
      );

      expect(script.fileName, 'otzaria_send_plugin_reports.bat');
      expect(script.content, contains('\r\n'));
      // cmd.exe דורש CRLF — אסור שיישאר \n בודד ללא \r לפניו.
      expect(RegExp(r'[^\r]\n').hasMatch(script.content), isFalse);
      expect(script.content, contains('s-1'));
      expect(script.content, contains(PluginReportService.endpoint.toString()));
      expect(script.content, contains(r'($body | ConvertFrom-Json).reportId'));
    });

    test('סקריפט Unix נשאר LF ומכיל את המזהה', () {
      final service = buildService(
        client: MockClient((_) async => http.Response('{}', 200)),
      );

      final script = service.buildOfflineSendScript(
        [_buildRecord('s-2')],
        target: OfflineSendScriptTarget.unix,
      );

      expect(script.fileName, 'otzaria_send_plugin_reports.sh');
      expect(script.content, isNot(contains('\r')));
      expect(script.content, contains("'s-2'"));
    });
  });

  group('PluginReportRecord', () {
    test('serializes to json and back', () {
      final record = _buildRecord('json-1');
      final restored = PluginReportRecord.fromJson(record.toJson());
      expect(restored.reportId, record.reportId);
      expect(restored.pluginUid, record.pluginUid);
      expect(restored.reportType, record.reportType);
      expect(restored.details, record.details);
      expect(restored.reporterEmail, record.reporterEmail);
      expect(restored.createdAt, record.createdAt);
    });
  });
}

PluginReportRecord _buildRecord(String id) {
  return PluginReportRecord(
    reportId: id,
    pluginUid: 'test.plugin',
    pluginName: 'תוסף בדיקה',
    pluginVersion: '1.0.0',
    reportType: 'bug',
    details: 'התוסף קורס',
    reporterEmail: 'me@example.com',
    appVersion: '0.9.97',
    platform: 'windows',
    createdAt: DateTime.parse('2026-08-18T10:00:00Z'),
  );
}

/// מציג סוג אחד בתור המשותף כרשימה, כדי שהבדיקות יזרעו וייבדקו בנוחות.
class _Queue {
  _Queue(this._store, this._kind);

  final PendingReportStore _store;
  final String _kind;

  Future<void> seed(List<PluginReportRecord> records) async {
    await _store.deleteAllOfKind(_kind);
    for (final record in records) {
      await _store.add(_kind, record.toJson());
    }
  }

  Future<List<PluginReportRecord>> load() async {
    final rows = await _store.listByKind(_kind);
    return rows.map((row) => PluginReportRecord.fromJson(row.payload)).toList();
  }
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
