import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:otzaria/plugins/bloc/plugin_system_bloc.dart';
import 'package:otzaria/plugins/bloc/plugin_system_event.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/services/plugin_install_results_log.dart';
import 'package:otzaria/plugins/services/plugin_installer_service.dart';

class _FakeRepo extends Mock implements PluginRegistryRepository {
  @override
  Future<List<InstalledPlugin>> getAllPlugins() async => [];
  @override
  Future<List<InstalledPlugin>> getDevelopmentPlugins() async => [];
}

class _RecordingLog extends PluginInstallResultsLog {
  final entries = <({String path, PluginInstallOutcome outcome, String? id})>[];

  @override
  Future<void> append({
    required String path,
    required PluginInstallOutcome outcome,
    String? pluginId,
    String? version,
    String? message,
  }) async => entries.add((path: path, outcome: outcome, id: pluginId));
}

class _ScriptedInstaller extends PluginInstallerService {
  _ScriptedInstaller(this.prepare) : super(repository: _FakeRepo());

  final Future<PreparedInstall> Function(bool forceOverwrite) prepare;

  @override
  Future<PreparedInstall> prepareInstall(
    String archivePath, {
    bool forceOverwrite = false,
  }) => prepare(forceOverwrite);

  @override
  Future<void> cancelInstall(String tempDirPath) async {}
}

PreparedInstall _prepared() => PreparedInstall(
  PluginManifest.fromJson({
    'schemaVersion': 1,
    'id': 'test.plugin',
    'name': 'תוסף',
    'version': '1.0.1',
    'entrypoint': 'index.html',
    'permissions': <String>[],
  }),
  '/tmp/otz_plugin_x',
  false,
);

const _path = r'D:\usb\plugins\test.otzplugin';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _RecordingLog log;

  PluginSystemBloc buildBloc(
    Future<PreparedInstall> Function(bool forceOverwrite) prepare,
  ) {
    log = _RecordingLog();
    final bloc = PluginSystemBloc(
      repository: _FakeRepo(),
      installerService: _ScriptedInstaller(prepare),
      installResultsLog: log,
    );
    addTearDown(bloc.close);
    return bloc;
  }

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 50));

  test('גרסה ישנה יותר — rejected_older', () async {
    final bloc = buildBloc(
      (_) async => throw PluginNewerVersionInstalledException(
        'תוסף',
        '1.0.0',
        '2.0.0',
        pluginId: 'test.plugin',
      ),
    );

    bloc.add(const InstallPluginRequested(_path, recordsResult: true));
    await settle();

    expect(log.entries.single.outcome, PluginInstallOutcome.rejectedOlder);
    expect(log.entries.single.path, _path);
    expect(log.entries.single.id, 'test.plugin');
  });

  test('גרסת אוצריא מחוץ לטווח — rejected_incompatible', () async {
    final bloc = buildBloc(
      (_) async => throw PluginIncompatibleAppVersionException('דורש 9.0.0'),
    );

    bloc.add(const InstallPluginRequested(_path, recordsResult: true));
    await settle();

    expect(
      log.entries.single.outcome,
      PluginInstallOutcome.rejectedIncompatible,
    );
  });

  test('ביטול בדיאלוג ההרשאות — cancelled עם מזהה התוסף', () async {
    final bloc = buildBloc((_) async => _prepared());

    bloc.add(const InstallPluginRequested(_path, recordsResult: true));
    await settle();
    expect(log.entries, isEmpty);

    bloc.add(const CancelPluginInstall('/tmp/otz_plugin_x'));
    await settle();

    expect(log.entries.single.outcome, PluginInstallOutcome.cancelled);
    expect(log.entries.single.id, 'test.plugin');
  });

  test('סירוב לדריסה — cancelled; אישור ממשיך את אותה בקשה', () async {
    final bloc = buildBloc(
      (force) async =>
          force ? _prepared() : throw PluginOverwriteException('תוסף', '1.0.1'),
    );

    bloc.add(const InstallPluginRequested(_path, recordsResult: true));
    await settle();
    bloc.add(const PluginOverwriteDeclined(_path));
    await settle();
    expect(log.entries.single.outcome, PluginInstallOutcome.cancelled);

    bloc.add(const InstallPluginRequested(_path, recordsResult: true));
    await settle();
    bloc.add(const InstallPluginRequested(_path, forceOverwrite: true));
    await settle();
    bloc.add(const CancelPluginInstall('/tmp/otz_plugin_x'));
    await settle();
    expect(log.entries.length, 2);
    expect(log.entries.last.path, _path);
  });

  test('התקנה שלא הגיעה מ-install-local אינה נרשמת', () async {
    final bloc = buildBloc((_) async => _prepared());

    bloc.add(const InstallPluginRequested(_path));
    await settle();
    bloc.add(const CancelPluginInstall('/tmp/otz_plugin_x'));
    await settle();

    expect(log.entries, isEmpty);
  });
}
