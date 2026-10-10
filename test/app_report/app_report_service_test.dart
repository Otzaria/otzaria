import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:otzaria/app_report/models/app_report.dart';
import 'package:otzaria/app_report/models/app_report_image.dart';
import 'package:otzaria/app_report/models/app_report_minidump.dart';
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

  group('minidump שנדחה נשלח שוב בלעדיו (issue #1978)', () {
    final withDump = _report().copyWith(
      minidump: AppReportMinidump(
        gzipBytes: Uint8List.fromList(gzip.encode(utf8.encode('MDMP...'))),
        fileName: 'a.dmp',
      ),
    );

    for (final (status, field) in [
      (422, 'attachments.minidump'),
      (413, null),
    ]) {
      test('$status', () async {
        final bodies = <Map<String, dynamic>>[];
        final service = build(
          MockClient((request) async {
            final body = jsonDecode(utf8.decode(request.bodyBytes));
            bodies.add(body as Map<String, dynamic>);
            final attachments = body['attachments'] as Map;
            if (attachments.containsKey('minidump')) {
              return _json(status, {'error': 'x', 'field': ?field});
            }
            return _json(200, {'success': true, 'issueNumber': 7});
          }),
        );
        final result = await service.send(withDump);
        expect(result.isSent, isTrue);
        expect(bodies, hasLength(2));
        expect((bodies.first['attachments'] as Map)['minidump'], isNotNull);
        expect(bodies.last['reportId'], bodies.first['reportId']);
        expect((bodies.last['attachments'] as Map)['diagnostics'], isNotNull);
      });
    }

    for (final (status, field) in [
      (422, 'attachments.minidump'),
      (413, null),
    ]) {
      test('flush: $status ואז כשל זמני שומרים את הסרת ה-dump', () async {
        final bodies = <Map<String, dynamic>>[];
        final service = build(
          MockClient((request) async {
            final body =
                jsonDecode(utf8.decode(request.bodyBytes))
                    as Map<String, dynamic>;
            bodies.add(body);
            if ((body['attachments'] as Map).containsKey('minidump')) {
              return _json(status, {'error': 'x', 'field': ?field});
            }
            return _json(503, {'error': 'temporary'});
          }),
        );
        await service.queueReport(withDump);
        final original = (await store.listByKind(
          AppReportService.pendingKind,
        )).single;

        expect(await service.flushPendingReports(), 0);
        expect(await service.flushPendingReports(), 0);
        expect(
          bodies.map(
            (body) => (body['attachments'] as Map).containsKey('minidump'),
          ),
          [true, false, false],
        );
        expect(
          bodies.map((body) => body['reportId']),
          everyElement(withDump.reportId),
        );
        final pending = (await store.listByKind(
          AppReportService.pendingKind,
        )).single;
        expect(pending.id, original.id);
        expect(pending.createdAt, original.createdAt);
        expect(pending.payload, withDump.copyWith(minidump: null).toJson());
        expect(await service.getSentReports(), isEmpty);
        expect(await service.getSentReportsTotal(), 0);
      });
    }

    for (final fallbackStatus in [200, 400, 409]) {
      test('flush: הסרת dump וניסיון המשך $fallbackStatus', () async {
        final bodies = <Map<String, dynamic>>[];
        final service = build(
          MockClient((request) async {
            final body =
                jsonDecode(utf8.decode(request.bodyBytes))
                    as Map<String, dynamic>;
            bodies.add(body);
            return (body['attachments'] as Map).containsKey('minidump')
                ? _json(422, {'field': 'attachments.minidump'})
                : _json(fallbackStatus, {'success': true, 'issueNumber': 7});
          }),
        );
        await service.queueReport(withDump);

        expect(
          await service.flushPendingReports(),
          fallbackStatus == 200 ? 1 : 0,
        );
        expect(bodies, hasLength(2));
        expect(bodies.last, withDump.copyWith(minidump: null).toApiPayload());
        final pending = await service.getPendingReports();
        final sent = await service.getSentReports();
        if (fallbackStatus == 409) {
          expect(pending, hasLength(1));
          expect(pending.single.reportId, isNot(withDump.reportId));
          expect(pending.single.minidump, isNull);
        } else {
          expect(pending, isEmpty);
        }
        if (fallbackStatus == 200) {
          expect(sent.single.reportId, withDump.reportId);
          expect(sent.single.issueNumber, 7);
          expect(sent.single.minidump, isNull);
          expect(sent.single.diagnostics, isNull);
          expect(await service.getSentReportsTotal(), 1);
        } else {
          expect(sent, isEmpty);
          expect(await service.getSentReportsTotal(), 0);
        }
      });
    }

    test('flush: כשל זמני בלי דחיית dump שומר את כל המטען', () async {
      final service = build(MockClient((_) async => http.Response('', 503)));
      await service.queueReport(withDump);
      expect(await service.flushPendingReports(), 0);
      expect(
        (await service.getPendingReports()).single.toJson(),
        withDump.toJson(),
      );
    });

    test('422 על שדה אחר — דחייה רגילה, בלי ניסיון נוסף', () async {
      var calls = 0;
      final service = build(
        MockClient((_) async {
          calls++;
          return _json(422, {'error': 'x', 'field': 'reporterEmail'});
        }),
      );
      final result = await service.send(withDump);
      expect(result.isFailed, isTrue);
      expect(calls, 1);
    });

    test('ה-dump לא נשמר בהיסטוריה', () async {
      final service = build(
        MockClient((_) async => _json(200, {'success': true})),
      );
      await service.send(withDump);
      final sent = await service.getSentReports();
      expect(sent.single.minidump, isNull);
    });
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
    expect((await service.getPendingReports()).single.description, 'אחר');
  });

  test(
    'markPendingReportAsSent: עובר להיסטוריה בלי פנייה לשרת (#1766)',
    () async {
      var requests = 0;
      final service = build(
        MockClient((_) async {
          requests++;
          return http.Response('', 500);
        }),
      );
      final report = _report();
      await service.queueReport(report);

      await service.markPendingReportAsSent(report);

      expect(requests, 0);
      expect(await service.getPendingReportsCount(), 0);
      final sent = (await service.getSentReports()).single;
      expect(sent.reportId, report.reportId);
      expect(sent.sentAt, isNotNull);
      expect(sent.diagnostics, isNull);
      expect(await service.getSentReportsTotal(), 1);
    },
  );

  test('סימון כנשלח ממתין לסיום שליחה ידנית לפני שמחזיר אותה לתור', () async {
    final requestStarted = Completer<void>();
    final response = Completer<http.Response>();
    final report = _report();
    final sender = build(
      MockClient((_) {
        requestStarted.complete();
        return response.future;
      }),
    );
    final marker = build(
      MockClient((_) async => fail('הסימון לא אמור לשלוח בקשת רשת')),
    );
    await sender.queueReport(report);

    final submission = sender.submitPendingReport(report);
    await requestStarted.future;
    var marked = false;
    final marking = marker.markPendingReportAsSent(report).then((_) {
      marked = true;
    });
    expect(marked, isFalse);

    response.complete(http.Response('', 503));
    expect((await submission).isQueued, isTrue);
    await marking;

    expect(await sender.getPendingReportsCount(), 0);
    final sent = (await sender.getSentReports()).single;
    expect(sent.reportId, report.reportId);
    expect(sent.diagnostics, isNull);
  });

  test('סימון כנשלח ממתין גם לשליחת flush שכבר התחילה', () async {
    final requestStarted = Completer<void>();
    final response = Completer<http.Response>();
    final report = _report();
    final sender = build(
      MockClient((_) {
        requestStarted.complete();
        return response.future;
      }),
    );
    final marker = build(
      MockClient((_) async => fail('הסימון לא אמור לשלוח בקשת רשת')),
    );
    await sender.queueReport(report);

    final flushing = sender.flushPendingReports();
    await requestStarted.future;
    var marked = false;
    final marking = marker.markPendingReportAsSent(report).then((_) {
      marked = true;
    });
    expect(marked, isFalse);

    response.complete(http.Response('', 503));
    expect(await flushing, 0);
    await marking;

    expect(await sender.getPendingReportsCount(), 0);
    expect((await sender.getSentReports()).single.reportId, report.reportId);
  });

  test('flush מסיר כפילות pending שכבר קיימת בהיסטוריה בלי לשלוח', () async {
    var requests = 0;
    final service = build(
      MockClient((_) async {
        requests++;
        return http.Response('', 503);
      }),
    );
    final report = _report();
    await service.markPendingReportAsSent(report);
    await store.add(AppReportService.pendingKind, report.toJson());

    expect(await service.flushPendingReports(), 0);
    expect(requests, 0);
    expect(await service.getPendingReportsCount(), 0);
    expect((await service.getSentReports()).single.reportId, report.reportId);
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

  test(
    'גוף הבקשה (כולל צילומי מסך) מקודד מחוץ ל-UI isolate (issue #2008)',
    () async {
      Map<String, dynamic>? sentBody;
      final service = build(
        MockClient((request) async {
          sentBody = jsonDecode(utf8.decode(request.bodyBytes));
          return _json(200, {'issueNumber': 1});
        }),
      );
      final report = _report().copyWith(
        diagnostics: {'probe': const _EncodingIsolateProbe()},
        images: [
          AppReportImage(
            bytes: Uint8List.fromList([1, 2, 3]),
            fileName: 'screenshot.png',
            mimeType: 'image/png',
          ),
        ],
      );

      expect((await service.send(report)).isSent, isTrue);
      final attachments = sentBody!['attachments'] as Map;
      expect(attachments['images'], hasLength(1));
      expect(
        (attachments['diagnostics'] as Map)['probe'],
        allOf(isNotNull, isNot(Isolate.current.debugName)),
      );
    },
  );
}

class _EncodingIsolateProbe {
  const _EncodingIsolateProbe();

  String? toJson() => Isolate.current.debugName;
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
