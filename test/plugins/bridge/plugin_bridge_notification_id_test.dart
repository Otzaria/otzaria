import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/personal_notes/repository/personal_notes_repository.dart';
import 'package:otzaria/plugins/bridge/plugin_bridge_adapter.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/search/search_repository.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tools/calendar/bloc/calendar_cubit.dart';
import 'package:otzaria/tools/calendar/services/notification_service.dart';
import 'package:otzaria/utils/navigation/book_open_coordinator.dart';
import 'package:otzaria/workspaces/bloc/workspace_bloc.dart';

class _MockHistoryBloc extends Mock implements HistoryBloc {}

class _MockTabsBloc extends Mock implements TabsBloc {}

class _MockNavigationBloc extends Mock implements NavigationBloc {}

class _MockCalendarCubit extends Mock implements CalendarCubit {}

class _MockWorkspaceBloc extends Mock implements WorkspaceBloc {}

class _MockSearchRepository extends Mock implements SearchRepository {}

class _MockPersonalNotesRepository extends Mock
    implements PersonalNotesRepository {}

class _MockBookOpenCoordinator extends Mock implements BookOpenCoordinator {}

class _KvRepo extends Mock implements PluginRegistryRepository {
  final kv = <String, String>{};
  @override
  Future<String?> getKV(String pluginId, String namespace, String key) async =>
      kv['$pluginId/$namespace/$key'];
  @override
  Future<void> setKV(
    String pluginId,
    String namespace,
    String key,
    String valueJson,
  ) async => kv['$pluginId/$namespace/$key'] = valueJson;
}

class _RecordingPlugin extends Mock implements FlutterLocalNotificationsPlugin {
  final shownIds = <int>[];
  @override
  Future<void> show({
    required int id,
    String? title,
    String? body,
    NotificationDetails? notificationDetails,
    String? payload,
  }) async {
    // אותה בדיקה ש-validateId של flutter_local_notifications מריץ.
    if (id > 0x7FFFFFFF || id < -0x80000000) {
      throw ArgumentError.value(id, 'id', 'must fit within 32-bit');
    }
    shownIds.add(id);
  }
}

class _FakeNotifications extends Mock implements NotificationService {
  final scheduledIds = <int>[];
  final _plugin = _RecordingPlugin();
  List<int> get shownIds => _plugin.shownIds;

  @override
  FlutterLocalNotificationsPlugin get flutterLocalNotificationsPlugin =>
      _plugin;
  @override
  bool get isInitialized => true;
  @override
  bool get hasPermissions => true;
  @override
  Future<void> scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime eventDate,
    required int reminderMinutes,
    bool soundEnabled = true,
  }) async => scheduledIds.add(id);
}

InstalledPlugin _plugin() => InstalledPlugin(
  pluginId: 'test.plugin',
  name: 'Test Plugin',
  version: '1.0.0',
  installPath: '/',
  entrypointPath: 'index.html',
  enabled: true,
  pinned: true,
  manifest: PluginManifest(
    schemaVersion: 1,
    id: 'test.plugin',
    name: 'Test Plugin',
    version: '1.0.0',
    description: '',
    author: '',
    homepage: '',
    entrypoint: 'index.html',
    minAppVersion: '1.0.0',
    sdkVersion: '1.x',
    permissions: const ['notifications.system'],
    networkEnabled: false,
    networkAllowlist: const [],
    toolTabTitle: 'Test Plugin',
    toolTabOrder: 1,
    defaultPinned: true,
    publishedDataTypes: const [],
  ),
  installedAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

PluginBridgeAdapter _adapter(NotificationService notifications) =>
    PluginBridgeAdapter(
      _plugin(),
      dependencies: PluginBridgeDependencies(
        historyBloc: _MockHistoryBloc(),
        tabsBloc: _MockTabsBloc(),
        navigationBloc: _MockNavigationBloc(),
        calendarCubit: _MockCalendarCubit(),
        workspaceBloc: _MockWorkspaceBloc(),
        searchRepository: _MockSearchRepository(),
        personalNotesRepository: _MockPersonalNotesRepository(),
        bookOpenCoordinator: _MockBookOpenCoordinator(),
        themePayloadBuilder: () => <String, dynamic>{},
        showConfirmDialog: ({required title, required content}) async => true,
        showWarningDialog:
            ({required title, required content, required subtitle}) async =>
                true,
        dispatchEventToPlugin:
            (pluginId, topic, payload, {instanceId}) async {},
      ),
      pluginRepository: _KvRepo(),
      notificationService: notifications,
    );

String _future() =>
    DateTime.now().add(const Duration(hours: 1)).toIso8601String();

void main() {
  group('מזהה ברירת המחדל של התראת תוסף נכנס ב-32 ביט', () {
    test('sendSystem בלי id', () async {
      final notifications = _FakeNotifications();
      final result = await _adapter(
        notifications,
      ).execute('notifications', 'sendSystem', {'title': 't', 'body': 'b'});
      expect(result['id'], inInclusiveRange(-0x80000000, 0x7FFFFFFF));
      expect(notifications.shownIds, [result['id']]);
    });

    test('scheduleSystem בלי id', () async {
      final notifications = _FakeNotifications();
      await _adapter(notifications).execute('notifications', 'scheduleSystem', {
        'title': 't',
        'body': 'b',
        'scheduledTime': _future(),
      });
      expect(
        notifications.scheduledIds.single,
        inInclusiveRange(-0x80000000, 0x7FFFFFFF),
      );
    });
  });
}
