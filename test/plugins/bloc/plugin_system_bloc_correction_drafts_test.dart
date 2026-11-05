import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/data/sqlite/sqlite3_api.dart';
import 'package:otzaria/plugins/bloc/plugin_system_bloc.dart';
import 'package:otzaria/plugins/bloc/plugin_system_event.dart';
import 'package:otzaria/plugins/bloc/plugin_system_state.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/models/plugin_permission_grant.dart';
import 'package:otzaria/plugins/repository/plugin_correction_draft_repository.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/services/plugin_correction_session_service.dart';
import 'package:otzaria/plugins/services/plugin_installer_service.dart';
import 'package:otzaria/plugins/storage/plugin_correction_draft_store.dart';

import '../../test_helpers/plugin_alerts_client.dart';

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
    permissions: const [],
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

class _FakeRepo implements PluginRegistryRepository {
  final plugins = {'p1': _plugin('p1')};

  @override
  Future<InstalledPlugin?> getPlugin(String pluginId) async =>
      plugins[pluginId];
  @override
  Future<String?> getKV(String id, String ns, String key) async => null;
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
  Future<void> detachDevelopmentPlugin(String pluginId) async =>
      plugins.remove(pluginId);
  @override
  Future<void> savePlugin(InstalledPlugin plugin) async =>
      plugins[plugin.pluginId] = plugin;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _StubInstaller extends PluginInstallerService {
  _StubInstaller(this.repo) : super(repository: repo);
  final _FakeRepo repo;

  @override
  Future<void> uninstallPlugin(String pluginId) async =>
      repo.plugins.remove(pluginId);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  late PluginCorrectionDraftRepository drafts;

  setUp(() async {
    db = sqlite3.openInMemory();
    drafts = PluginCorrectionDraftRepository.direct(db);
    PluginCorrectionSessionService.instance.draftRepository = drafts;
    final lease = await drafts.acquire(
      pluginId: 'p1',
      draftId: correctionDraftId('p1', 'id:1'),
      bookUid: 'id:1',
      bookId: 'ספר',
      bookSource: '',
      libraryVersion: 'v1',
    );
    await drafts.write(
      pluginId: 'p1',
      draftId: correctionDraftId('p1', 'id:1'),
      token: lease.token,
      revision: 1,
      libraryVersion: 'v1',
      changesJson: jsonEncode([
        {
          'sectionIndex': 0,
          'originalSourceText': 'מקור',
          'originalText': 'מקור',
          'proposedText': 'תיקון',
        },
      ]),
    );
    await drafts.release(
      pluginId: 'p1',
      draftId: correctionDraftId('p1', 'id:1'),
      token: lease.token,
    );
  });

  tearDown(() => db.close());

  Future<void> run(PluginSystemEvent event) async {
    final repo = _FakeRepo();
    final bloc = PluginSystemBloc(
      repository: repo,
      alertsClient: pluginAlertsClientFor(repo),
      installerService: _StubInstaller(repo),
    );
    addTearDown(bloc.close);
    bloc.add(event);
    await expectLater(bloc.stream, emitsThrough(isA<PluginSystemLoaded>()));
  }

  test('הסרה שאושרה עם מחיקת טיוטות מוחקת את טיוטות התוסף', () async {
    await run(
      const UninstallPluginRequested('p1', deleteCorrectionDrafts: true),
    );
    expect(await drafts.list('p1'), isEmpty);
  });

  test('הסרה בלי הסימון שומרת את הטיוטות', () async {
    await run(const UninstallPluginRequested('p1'));
    expect(await drafts.list('p1'), hasLength(1));
  });

  test('ניתוק תוסף פיתוח שומר את הטיוטות', () async {
    await run(const DetachDevelopmentPluginRequested('p1'));
    expect(await drafts.list('p1'), hasLength(1));
  });

  group('סשן פעיל: העריכה האחרונה נשמרת בלי צרכן לאירוע', () {
    final service = PluginCorrectionSessionService.instance;
    const tabId = 'lifecycle-tab';

    Future<void> beginAndEdit() async {
      // אין onEvent: סביבת התוסף כבר אינה זמינה לקבל את אירוע הסיום.
      await service.begin(
        owner: 'p1',
        tabId: tabId,
        bookId: 'ספר',
        bookUid: 'id:1',
        libraryVersion: 'v1',
        loadSource: (_) async => 'מקור',
      );
      service.editParagraph(tabId, 0, 'מקור', 'עריכה אחרונה');
    }

    Future<void> expectLastEditKept() async {
      expect(service.hasSessionForTab(tabId), isFalse);
      expect(await service.flushAll(), isTrue);
      // השחרור רץ אחרי השמירה, בפעולות המאגר הבאות בתור.
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      final stored = await drafts.get('p1', correctionDraftId('p1', 'id:1'));
      expect(
        (stored!['changes'] as List).single['proposedText'],
        'עריכה אחרונה',
      );
      expect(stored['active'], isFalse, reason: 'ה-lease שוחרר');
    }

    for (final (name, event) in [
      ('השבתת התוסף', const DisablePluginRequested('p1')),
      // מה שדיאלוג "נמצא תוסף ישן באותו שם" שולח בהסרת הכפיל.
      ('הסרת כפיל', const UninstallPluginRequested('p1')),
    ]) {
      test(name, () async {
        await beginAndEdit();
        await run(event);
        await expectLastEditKept();
      });
    }
  });
}
