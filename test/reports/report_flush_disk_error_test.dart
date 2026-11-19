import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:otzaria/app_report/services/app_report_service.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/core/error_log_file.dart';
import 'package:otzaria/core/user_state/pending_report_store.dart';
import 'package:otzaria/core/user_state/user_state_database.dart';
import 'package:otzaria/data/sqlite/sqlite3_api.dart';
import 'package:otzaria/plugins/services/plugin_report_service.dart';
import 'package:otzaria/services/direct_error_report_service.dart';
import 'package:otzaria/services/sent_reports_counter.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria_report_contract/otzaria_report_contract.dart';

import '../test_helpers/memory_cache_provider.dart';

/// כונן פגום: קריאת התור נכשלת כמו בדיווח (SQLITE_IOERR_IN_PAGE).
class _FailingQueueStore extends PendingReportStore {
  _FailingQueueStore({super.database});

  bool failing = false;

  void _failIfBroken() {
    if (failing) {
      throw SqliteException(
        extendedResultCode: 8714,
        message: 'disk I/O error',
      );
    }
  }

  @override
  Future<List<int>> listRowIds(
    String kind, {
    String? additionalKind,
    required int afterId,
    required int limit,
  }) async {
    _failIfBroken();
    return super.listRowIds(
      kind,
      additionalKind: additionalKind,
      afterId: afterId,
      limit: limit,
    );
  }

  @override
  Future<List<PendingReport>> listByKind(
    String kind, {
    String? additionalKind,
    String? whereField,
    Object? equals,
    int? limit,
  }) async {
    _failIfBroken();
    return super.listByKind(
      kind,
      additionalKind: additionalKind,
      whereField: whereField,
      equals: equals,
      limit: limit,
    );
  }
}

/// שירות תור אחד: הוספה לתור באופליין, שליחה מוצלחת, הפעלת השליחה האוטומטית.
typedef _Queue = ({
  Future<void> Function(String id) enqueueOffline,
  Future<void> Function(String id) sendOnline,
  Future<void> Function() startAutomaticFlush,
  Future<int> Function() flushPendingReports,
  Future<void> Function() suspend,
});

AppReport _appReport(String id) => AppReport(
  reportId: id,
  type: AppReportType.bug,
  trigger: AppReportTrigger.manual,
  title: 'באג',
  description: 'תיאור',
  reporterEmail: 'a@b.com',
  appVersion: '0.9.98',
  platform: 'windows',
  createdAt: DateTime.utc(2026, 11, 15),
);

PluginReportRecord _pluginReport(String id) => PluginReportRecord(
  reportId: id,
  pluginUid: 'test.plugin',
  pluginName: 'תוסף בדיקה',
  pluginVersion: '1.0.0',
  reportType: 'bug',
  details: 'התוסף קורס',
  reporterEmail: 'me@example.com',
  appVersion: '0.9.98',
  platform: 'windows',
  createdAt: DateTime.utc(2026, 11, 15),
);

DirectErrorReport _directReport(String id) => DirectErrorReport(
  id: id,
  senderEmail: 'user@example.com',
  subject: 'דיווח על טעות: ספר מבחן',
  bookTitle: 'ספר מבחן',
  currentRef: 'פרק א',
  lineNumber: 12,
  selectedText: 'טקסט עם טעות',
  errorDetails: 'חסר ניקוד',
  contextText: 'הקשר',
  filePath: '/books/test.txt',
  sourceFolder: 'local',
  createdAt: DateTime.utc(2026, 11, 15),
);

final Map<String, _Queue Function(PendingReportStore store)> _queues = {
  'דיווח על התוכנה': (store) {
    final service = AppReportService(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({'success': true, 'issueNumber': 1}),
          200,
          headers: const {'content-type': 'application/json'},
        ),
      ),
      reportStore: store,
      sentCounter: SentReportsCounter.inMemory(),
    );
    return (
      enqueueOffline: (id) => service.send(_appReport(id)),
      sendOnline: (id) => service.send(_appReport(id)),
      startAutomaticFlush: service.startAutomaticFlush,
      flushPendingReports: service.flushPendingReports,
      suspend: AppReportService.suspendAutomaticFlush,
    );
  },
  'דיווח על תוסף': (store) {
    final service = PluginReportService(
      client: MockClient((_) async => http.Response('{}', 200)),
      reportStore: store,
      sentCounter: SentReportsCounter.inMemory(),
    );
    return (
      enqueueOffline: (id) => service.submitReport(_pluginReport(id)),
      sendOnline: (id) => service.submitReport(_pluginReport(id)),
      startAutomaticFlush: service.startAutomaticFlush,
      flushPendingReports: service.flushPendingReports,
      suspend: PluginReportService.suspendAutomaticFlush,
    );
  },
  'דיווח על טעות בספר': (store) {
    final service = DirectErrorReportService(
      client: MockClient((_) async => http.Response('', 200)),
      reportStore: store,
      sentCounter: SentReportsCounter.inMemory(),
    );
    return (
      enqueueOffline: (id) => service.submitReport(_directReport(id)),
      sendOnline: (id) => service.submitReport(_directReport(id)),
      startAutomaticFlush: service.startAutomaticFlush,
      flushPendingReports: () =>
          service.flushPendingReports(onlyAutomaticRetry: true),
      suspend: DirectErrorReportService.suspendAutomaticFlush,
    );
  },
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Settings.init(cacheProvider: MemoryCacheProvider());
  });

  late Directory tmp;
  late UserStateDatabase db;
  late _FailingQueueStore store;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('otzaria_report_flush_disk_');
    AppPaths.debugOverrideDataRootPath(tmp.path);
    db = UserStateDatabase.openAt(
      '${tmp.path}${Platform.pathSeparator}user_state.db',
    );
    store = _FailingQueueStore(database: db);
    await Settings.setValue<bool>(
      SettingsRepository.keyQueueErrorReportsWhenOffline,
      true,
    );
  });

  tearDown(() async {
    await ErrorLogFile.flushPending();
    AppPaths.debugOverrideDataRootPath(null);
    db.close();
    tmp.deleteSync(recursive: true);
  });

  Future<int> loggedFailures() async {
    await ErrorLogFile.flushPending();
    final log = File('${tmp.path}/logs/errors.txt');
    if (!log.existsSync()) return 0;
    return 'disk I/O error'.allMatches(log.readAsStringSync()).length;
  }

  for (final MapEntry(key: name, value: build) in _queues.entries) {
    test(
      '$name: כשל דיסק בשליחה האוטומטית מהתור נרשם פעם אחת ואינו שגיאה '
      'לא מטופלת; הדיווח נשאר בתור ונשלח בסבב הבא (issue #5087)',
      () async {
        final queue = build(store);
        addTearDown(queue.suspend);

        await Settings.setValue<bool>(SettingsRepository.keyOfflineMode, true);
        await queue.enqueueOffline('queued-1');
        await Settings.setValue<bool>(
          SettingsRepository.keyOfflineMode,
          false,
        );

        store.failing = true;
        final unhandled = <Object>[];
        await runZonedGuarded(() async {
          await queue.startAutomaticFlush();
          await pumpEventQueue();
          // שליחה מוצלחת מפעילה גם היא שליחה מהתור ברקע.
          await queue.sendOnline('online-1');
          await pumpEventQueue();
        }, (error, _) => unhandled.add(error));

        expect(unhandled, isEmpty);
        expect(await loggedFailures(), 1);
        // שליחה ידנית מההגדרות ממשיכה להציג את השגיאה.
        await expectLater(
          queue.flushPendingReports(),
          throwsA(isA<SqliteException>()),
        );

        store.failing = false;
        expect(await queue.flushPendingReports(), 1);
        expect(await queue.flushPendingReports(), 0);
        await queue.suspend();
      },
      timeout: const Timeout(Duration(seconds: 60)),
    );
  }
}
