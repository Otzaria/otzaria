import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:otzaria/core/http_client_registry.dart';
import 'package:otzaria/plugins/bloc/plugin_system_bloc.dart';
import 'package:otzaria/plugins/bloc/plugin_system_event.dart';
import 'package:otzaria/plugins/bloc/plugin_system_state.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/services/plugin_download_service.dart';
import 'package:otzaria/plugins/services/plugin_installer_service.dart';
import 'package:otzaria/plugins/utils/plugin_safe_mode.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as path;

class _FakeRepo implements PluginRegistryRepository {
  int loads = 0;

  @override
  Future<List<InstalledPlugin>> getAllPlugins() async {
    loads++;
    return [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ControlledDownload extends PluginDownloadService {
  _ControlledDownload({
    this.abortOnDispose = false,
    this.failOnDispose = false,
  });

  final bool abortOnDispose;
  final bool failOnDispose;
  final started = Completer<void>();
  final result = Completer<String>();
  int disposals = 0;

  @override
  Future<String> downloadPluginArchive(
    Uri downloadUri, {
    String? appVersion,
    bool storeOnly = false,
  }) {
    started.complete();
    return result.future;
  }

  @override
  void dispose() {
    disposals++;
    super.dispose();
    if (abortOnDispose && started.isCompleted && !result.isCompleted) {
      result.completeError(http.RequestAbortedException());
    }
    if (failOnDispose) throw StateError('dispose failed');
  }
}

class _ControlledInstaller extends PluginInstallerService {
  _ControlledInstaller() : super(repository: _FakeRepo());

  final started = Completer<void>();
  final result = Completer<PreparedInstall>();
  final cancelled = <String>[];
  int prepares = 0;

  @override
  Future<PreparedInstall> prepareInstall(
    String archivePath, {
    bool forceOverwrite = false,
  }) {
    prepares++;
    started.complete();
    return result.future;
  }

  @override
  Future<void> cancelInstall(String tempDirPath) async {
    cancelled.add(tempDirPath);
    await super.cancelInstall(tempDirPath);
  }
}

class _ObservedBloc extends PluginSystemBloc {
  _ObservedBloc({
    required super.repository,
    required super.downloadService,
    required super.installerService,
  });

  final handled = Completer<void>();
  final errors = <Object>[];

  @override
  void onError(Object error, StackTrace stackTrace) {
    errors.add(error);
    super.onError(error, stackTrace);
  }

  @override
  void onDone(
    PluginSystemEvent event, [
    Object? error,
    StackTrace? stackTrace,
  ]) {
    if (event is InstallRemotePluginRequested && !handled.isCompleted) {
      handled.complete();
    }
    super.onDone(event, error, stackTrace);
  }
}

PreparedInstall _prepared(Directory directory) => PreparedInstall(
  PluginManifest.fromJson({
    'id': 'test.plugin',
    'name': 'תוסף בדיקה',
    'version': '1.0.0',
    'entrypoint': 'index.html',
  }),
  directory.path,
  false,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeRepo repository;
  late _ControlledInstaller installer;
  late Directory directory;
  late int registryBefore;

  setUp(() async {
    registryBefore = HttpClientRegistry.registeredCount;
    repository = _FakeRepo();
    installer = _ControlledInstaller();
    directory = await Directory.systemTemp.createTemp('plugin_close_test_');
    PackageInfo.setMockInitialValues(
      appName: 'Otzaria',
      packageName: 'com.otzaria.app',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  tearDown(() async {
    PluginSafeMode.resetForTesting();
    if (await directory.exists()) await directory.delete(recursive: true);
    expect(HttpClientRegistry.registeredCount, registryBefore);
  });

  _ObservedBloc create(_ControlledDownload download) {
    final bloc = _ObservedBloc(
      repository: repository,
      downloadService: download,
      installerService: installer,
    );
    addTearDown(bloc.close);
    return bloc;
  }

  void install(_ObservedBloc bloc) => bloc.add(
    const InstallRemotePluginRequested('https://example.com/plugin.otzplugin'),
  );

  Future<String> archive() async {
    final archiveDirectory = await directory.createTemp('download_');
    final file = File(path.join(archiveDirectory.path, 'test.otzplugin'));
    await file.writeAsString('archive');
    return file.path;
  }

  test('close cancels the download without a stale error or reload', () async {
    final download = _ControlledDownload(abortOnDispose: true);
    final bloc = create(download);
    install(bloc);
    await download.started.future;

    await bloc.close();
    await bloc.handled.future;
    await bloc.close();

    expect(download.disposals, 1);
    expect(installer.prepares, 0);
    expect(repository.loads, 0);
    expect(bloc.errors, isEmpty);
  });

  test('registry shutdown cancels a download before the bloc closes', () async {
    final download = _ControlledDownload(abortOnDispose: true);
    final bloc = create(download);
    install(bloc);
    await download.started.future;

    await HttpClientRegistry.closeAll();
    await bloc.handled.future;

    expect(bloc.isClosed, isFalse);
    expect(installer.prepares, 0);
    expect(repository.loads, 0);
    expect(bloc.errors, isEmpty);
    expect(HttpClientRegistry.registeredCount, registryBefore);
    await bloc.close();
  });

  test(
    'ordinary download failures still reset the live window state',
    () async {
      PluginSafeMode.active.value = true;
      final download = _ControlledDownload();
      final bloc = create(download);
      final reloaded = bloc.stream.firstWhere(
        (state) => state is PluginSystemLoaded,
      );
      install(bloc);
      await download.started.future;

      download.result.completeError(http.ClientException('network failed'));
      await bloc.handled.future;
      await reloaded;

      expect(bloc.isClosed, isFalse);
      expect(repository.loads, 1);
      expect(installer.prepares, 0);
      await bloc.close();
    },
  );

  test(
    'late successful download is cleaned without starting installation',
    () async {
      final download = _ControlledDownload();
      final bloc = create(download);
      final archivePath = await archive();
      install(bloc);
      await download.started.future;

      await bloc.close();
      download.result.complete(archivePath);
      await bloc.handled.future;

      expect(installer.prepares, 0);
      expect(repository.loads, 0);
      expect(bloc.errors, isEmpty);
      expect(await File(archivePath).exists(), isFalse);
    },
  );

  test(
    'preparation finishing after close releases extracted and source files',
    () async {
      final download = _ControlledDownload();
      final bloc = create(download);
      final archivePath = await archive();
      final extracted = await directory.createTemp('prepared_');
      download.result.complete(archivePath);
      install(bloc);
      await installer.started.future;

      await bloc.close();
      installer.result.complete(_prepared(extracted));
      await bloc.handled.future;

      expect(installer.cancelled, [extracted.path]);
      expect(await extracted.exists(), isFalse);
      expect(await File(archivePath).exists(), isFalse);
      expect(repository.loads, 0);
      expect(bloc.errors, isEmpty);
    },
  );

  test(
    'a live window still receives the prepared permission request',
    () async {
      final download = _ControlledDownload();
      final bloc = create(download);
      final archivePath = await archive();
      final extracted = await directory.createTemp('prepared_');
      download.result.complete(archivePath);
      installer.result.complete(_prepared(extracted));
      final state = bloc.stream.firstWhere(
        (state) => state is PluginSystemInstallRequiresPermissions,
      );

      install(bloc);
      final ready = await state as PluginSystemInstallRequiresPermissions;
      await bloc.handled.future;

      expect(ready.tempDirPath, extracted.path);
      expect(installer.cancelled, isEmpty);
      expect(await extracted.exists(), isTrue);
      expect(await File(archivePath).exists(), isFalse);
      expect(bloc.errors, isEmpty);
      await bloc.close();
    },
  );

  test('closing immediately does not start an enqueued download', () async {
    final download = _ControlledDownload();
    final bloc = create(download);

    install(bloc);
    await bloc.close();
    await pumpEventQueue();

    expect(download.started.isCompleted, isFalse);
    expect(download.disposals, 1);
    expect(installer.prepares, 0);
    expect(repository.loads, 0);
  });

  test('download disposal failure still closes the bloc', () async {
    final download = _ControlledDownload(failOnDispose: true);
    final bloc = _ObservedBloc(
      repository: repository,
      downloadService: download,
      installerService: installer,
    );

    await expectLater(bloc.close(), throwsStateError);
    expect(bloc.isClosed, isTrue);
    expect(download.disposals, 1);
  });
}
