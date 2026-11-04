import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/plugins/bloc/plugin_system_bloc.dart';
import 'package:otzaria/plugins/bloc/plugin_system_event.dart';
import 'package:otzaria/plugins/bloc/plugin_system_state.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/models/plugin_permission_grant.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/services/plugin_installer_service.dart';
import 'package:otzaria/tools/calendar/services/calendar_alerts_client.dart';
import 'package:otzaria/tools/calendar/services/calendar_alerts_owner.dart';
import 'package:otzaria/tools/calendar/services/calendar_alerts_store.dart';
import 'package:otzaria/tools/calendar/services/notification_service.dart';

import '../../tools/calendar/support/calendar_alerts_fakes.dart';

InstalledPlugin _plugin(String id) => InstalledPlugin(
  pluginId: id,
  name: 'תוסף $id',
  version: '1.0.0',
  installPath: '/tmp/$id',
  entrypointPath: '/tmp/$id/index.html',
  enabled: true,
  pinned: true,
  manifest: PluginManifest(
    schemaVersion: 1,
    id: id,
    name: 'תוסף $id',
    version: '1.0.0',
    description: 'test',
    author: 'tester',
    homepage: '',
    entrypoint: 'index.html',
    minAppVersion: '1.0.0',
    sdkVersion: '1.x',
    permissions: const ['notifications.system'],
    networkEnabled: false,
    networkAllowlist: const [],
    toolTabTitle: 'תוסף $id',
    toolTabOrder: 100,
    defaultPinned: true,
    publishedDataTypes: const [],
  ),
  installedAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

/// התוסף תזמן התראה 7; המזהה שמור ב-KV הפנימי כמו בגשר.
class _FakeRepo implements PluginRegistryRepository {
  final plugins = {'p1': _plugin('p1'), 'p2': _plugin('p2')};
  final ids = <String, String>{'p1': '[7]', 'p2': '[99]'};

  @override
  Future<InstalledPlugin?> getPlugin(String pluginId) async =>
      plugins[pluginId];
  @override
  Future<String?> getKV(String id, String ns, String key) async =>
      ns == '_internal' && key == 'notification_ids' ? ids[id] : null;
  @override
  Future<void> setKV(String id, String ns, String key, String value) async {
    if (ns == '_internal' && key == 'notification_ids') ids[id] = value;
  }

  @override
  Future<void> removeKV(String id, String ns, String key) async {
    if (ns == '_internal' && key == 'notification_ids') ids.remove(id);
  }

  @override
  Future<List<PluginPermissionGrant>> getPluginPermissions(String id) async =>
      [];
  @override
  Future<List<String>> getGrantedPermissionNames(String id) async => [];
  @override
  Future<String?> getNewTabPageOwner() async => null;

  @override
  Future<List<InstalledPlugin>> getAllPlugins() async =>
      plugins.values.toList();
  @override
  Future<List<InstalledPlugin>> getDevelopmentPlugins() async => [];
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// מדמה את ההסרה האמיתית: הרשומה ונתוני ה-KV נמחקים.
class _StubInstaller extends PluginInstallerService {
  _StubInstaller(this.repo) : super(repository: repo);
  final _FakeRepo repo;

  @override
  Future<void> uninstallPlugin(String pluginId) async {
    repo.plugins.remove(pluginId);
    repo.ids.remove(pluginId);
  }

  @override
  Future<void> resetPluginData(String pluginId) async {
    repo.ids.remove(pluginId);
  }
}

void main({bool initializeNotifications = true, bool resetFirst = false}) {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  final calls = <MethodCall>[];
  final cancelled = <Object?>[];
  String? failureMethod;
  Completer<void>? scheduleGate;
  late CalendarAlertsOwner owner;

  setUpAll(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    FlutterLocalNotificationsPlatform.instance =
        MacOSFlutterLocalNotificationsPlugin();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'zonedSchedule') await scheduleGate?.future;
          if (call.method == failureMethod) {
            throw PlatformException(code: 'unavailable');
          }
          if (call.method == 'cancel') cancelled.add(call.arguments);
          return true;
        });
    if (initializeNotifications) await NotificationService().init();
  });

  tearDownAll(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
  setUp(() {
    calls.clear();
    cancelled.clear();
    failureMethod = null;
    scheduleGate = null;
  });

  PluginSystemBloc blocFor(_FakeRepo repo) {
    final created = owner = CalendarAlertsOwner(
      store: MemoryAlertsStore(),
      notifications: NotificationService(),
      pluginIds: RegistryPluginNotificationIdStore(repo),
      pluginEvents: () async => const [],
      dedupeDuplicates: false,
    );
    final bloc = PluginSystemBloc(
      repository: repo,
      installerService: _StubInstaller(repo),
      alertsClient: LocalCalendarAlertsClient(owner),
    );
    addTearDown(() async {
      await created.idle;
      created.dispose();
    });
    addTearDown(bloc.close);
    return bloc;
  }

  Future<_FakeRepo> run(
    PluginSystemEvent event, {
    _FakeRepo? repository,
  }) async {
    final repo = repository ?? _FakeRepo();
    final bloc = blocFor(repo);
    bloc.add(event);
    await expectLater(bloc.stream, emitsThrough(isA<PluginSystemLoaded>()));
    return repo;
  }

  for (final ids in <String?>[null, '[]', '["7", null]']) {
    test('בלי מזהים שלמים ($ids) אין אתחול או ביטול', () async {
      final repo = _FakeRepo();
      if (ids == null) {
        repo.ids.remove('p1');
      } else {
        repo.ids['p1'] = ids;
      }
      await run(const UninstallPluginRequested('p1'), repository: repo);
      expect(calls, isEmpty);
      expect(NotificationService().isInitialized, initializeNotifications);
      expect(repo.plugins.containsKey('p1'), isFalse);
      expect(repo.ids['p2'], '[99]');
    });
  }

  final events = <PluginSystemEvent>[
    const UninstallPluginRequested('p1'),
    const ResetPluginDataRequested('p1'),
  ];
  for (final event in resetFirst ? events.reversed : events) {
    test('${event.runtimeType} מבטל לפני מחיקת המזהים', () async {
      final wasInitialized = NotificationService().isInitialized;
      final repo = await run(event);
      expect(cancelled, [7]);
      expect(repo.ids.containsKey('p1'), isFalse);
      expect(repo.ids['p2'], '[99]');
      expect(repo.plugins.containsKey('p2'), isTrue);
      expect(calls.map((call) => call.method), ['cancel']);
      expect(NotificationService().isInitialized, wasInitialized);
    });
  }

  for (final event in events) {
    test('כשל ביטול ב-${event.runtimeType} משאיר את נתוני התוסף', () async {
      failureMethod = 'cancel';
      final repo = _FakeRepo();
      blocFor(repo).add(event);
      await pumpEventQueue();
      expect(calls.map((call) => call.method), ['cancel']);
      expect(repo.plugins.containsKey('p1'), isTrue);
      expect(repo.ids['p1'], '[7]');
      expect(repo.ids['p2'], '[99]');
    });
  }

  if (initializeNotifications) {
    test('הסרה בזמן שתזמון ראשון בדרך מבטלת גם אותו', () async {
      final repo = _FakeRepo()..ids.remove('p1');
      final bloc = blocFor(repo);
      scheduleGate = Completer<void>();
      final scheduled = owner.execute('pluginSchedule', {
        'pluginId': 'p1',
        'id': 5,
        'title': 't',
        'body': 'b',
        'at': DateTime.now().add(const Duration(hours: 2)).toIso8601String(),
      });
      await pumpEventQueue();
      expect(calls.map((call) => call.method), ['zonedSchedule']);

      bloc.add(const UninstallPluginRequested('p1'));
      await pumpEventQueue();
      scheduleGate!.complete();
      expect((await scheduled)['ok'], isTrue);
      await expectLater(bloc.stream, emitsThrough(isA<PluginSystemLoaded>()));

      expect(cancelled, [5]);
      expect(repo.plugins.containsKey('p1'), isFalse);
      expect(repo.ids.containsKey('p1'), isFalse);
    });
  }

  test('כל מזהי התוסף מבוטלים בלי לגעת בתוסף אחר', () async {
    final repo = _FakeRepo()..ids['p1'] = '[7,11]';
    await run(const UninstallPluginRequested('p1'), repository: repo);
    expect(cancelled, [7, 11]);
    expect(repo.ids['p2'], '[99]');
  });

  test('אתחול רגיל שומר על בקשת ההרשאות', () async {
    await NotificationService().init();
    final settings =
        calls.firstWhere((call) => call.method == 'initialize').arguments
            as Map;
    for (final permission in ['Sound', 'Badge', 'Alert']) {
      expect(settings['request${permission}Permission'], isTrue);
    }
    expect(NotificationService().isInitialized, isTrue);
    expect(NotificationService().hasPermissions, isTrue);
  });
}
