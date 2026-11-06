import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:otzaria/core/app_paths.dart';
import 'package:otzaria/plugins/models/plugin_valid_permissions.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/services/plugin_fs_service.dart';
import 'package:otzaria/plugins/services/plugin_installer_service.dart';
import 'package:otzaria/plugins/storage/plugin_system_database.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:path/path.dart' as p;

import '../../helpers/memory_settings_cache.dart';
import 'bundled_plugin_seed_service_test.dart' as fixture;

class _DeletionBarrier {
  final String target;
  final started = Completer<void>();
  final resume = Completer<void>();

  _DeletionBarrier(this.target);

  bool matches(String path) =>
      path == target ||
      (p.dirname(path) == p.dirname(target) &&
          p.basename(path).startsWith('.delete-'));
}

class _ObservedDirectory implements Directory {
  final Directory delegate;
  final _DeletionBarrier? barrier;
  final String? failRename;

  _ObservedDirectory(this.delegate, {this.barrier, this.failRename});

  _ObservedDirectory wrap(Directory directory) => _ObservedDirectory(
    directory,
    barrier: barrier,
    failRename: failRename,
  );

  @override
  String get path => delegate.path;

  @override
  Directory get parent => wrap(delegate.parent);

  @override
  Future<bool> exists() => delegate.exists();

  @override
  bool existsSync() => delegate.existsSync();

  @override
  Directory createTempSync([String? prefix]) =>
      wrap(delegate.createTempSync(prefix));

  @override
  Directory renameSync(String newPath) {
    if (path == failRename) throw FileSystemException('rename denied', path);
    return delegate.renameSync(newPath);
  }

  @override
  Future<Directory> delete({bool recursive = false}) async {
    if (barrier != null && barrier!.matches(path)) {
      barrier!.started.complete();
      await barrier!.resume.future;
    }
    await delegate.delete(recursive: recursive);
    return delegate;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const id = 'test.uninstall.race';
  late Directory root;
  late PluginRegistryRepository repository;
  late PluginInstallerService installer;
  late Directory release;
  late String dataPath;
  late String cachePath;

  setUpAll(() async {
    root = await Directory.systemTemp.createTemp('otzaria_uninstall_race_');
    AppPaths.debugOverrideDataRootPath(root.path);
  });

  tearDownAll(() async {
    PluginSystemDatabase.instance.openDatabase?.close();
    AppPaths.debugOverrideDataRootPath(null);
    await root.delete(recursive: true);
  });

  setUp(() async {
    await Settings.init(cacheProvider: MemorySettingsCache());
    repository = PluginRegistryRepository();
    installer = PluginInstallerService(repository: repository);
    final installParent = await Directory(
      p.dirname(await AppPaths.getPluginInstallPath(id)),
    ).create(recursive: true);
    release = await installParent.createTemp('.release-old-');
    await File(p.join(release.path, 'index.html')).writeAsString('old');
    await repository.savePluginWithPermissions(
      fixture.installedPlugin(id, release.path),
      const {},
    );
    dataPath = await AppPaths.getPluginDataPath(id);
    cachePath = await AppPaths.getPluginCachePath(id);
    for (final path in [dataPath, cachePath]) {
      await File(p.join(path, 'old.txt')).create(recursive: true);
    }
  });

  tearDown(() => installer.uninstallPlugin(id));

  Future<void> intercepted(
    Future<void> Function() operation, {
    _DeletionBarrier? barrier,
    String? failRename,
  }) {
    final outerZone = Zone.current;
    return IOOverrides.runZoned(
      operation,
      createDirectory: (path) {
        final real = outerZone.run(() => Directory(path));
        return [release.path, dataPath, cachePath].contains(path)
            ? _ObservedDirectory(real, barrier: barrier, failRename: failRename)
            : real;
      },
    );
  }

  Future<void> writeNewData() async {
    await PluginFsService().writeWorkspaceFile(
      root: p.join(dataPath, 'files'),
      relativePath: 'new-user-notes.txt',
      bytes: 'new user data'.codeUnits,
    );
    await File(p.join(cachePath, 'new.txt')).create(recursive: true);
  }

  Future<void> expectNewData() async {
    expect(
      await File(
        p.join(dataPath, 'files', 'new-user-notes.txt'),
      ).readAsString(),
      'new user data',
    );
    expect(await File(p.join(cachePath, 'new.txt')).exists(), isTrue);
    for (final path in [dataPath, cachePath]) {
      expect(await File(p.join(path, 'old.txt')).exists(), isFalse);
      expect(
        Directory(p.dirname(path)).listSync().where(
          (entry) => p.basename(entry.path).startsWith('.delete-'),
        ),
        isEmpty,
      );
    }
  }

  for (final target in ['release', 'data', 'cache']) {
    test('התקנה מחדש בזמן מחיקת $target שומרת את הנתונים החדשים', () async {
      final original = (await repository.getPlugin(id))!;
      final prepared = await Directory(p.join(root.path, 'prepared')).create();
      await File(p.join(prepared.path, 'index.html')).writeAsString('new');
      final barrier = _DeletionBarrier(switch (target) {
        'release' => release.path,
        'data' => dataPath,
        _ => cachePath,
      });
      final removal = intercepted(
        () => installer.uninstallPlugin(id),
        barrier: barrier,
      );
      try {
        await barrier.started.future.timeout(const Duration(seconds: 10));
        expect(await repository.getPlugin(id), isNull);
        await installer.finalizeInstall(
          prepared.path,
          original.manifest,
          grantedPermissions: {
            for (final permission in effectiveManifestPermissions(
              original.manifest.permissions,
            ))
              permission: true,
          },
        );
        final replacement = (await repository.getPlugin(id))!;
        expect(replacement.installPath, isNot(release.path));
        await writeNewData();
        barrier.resume.complete();
        await removal;

        expect(await repository.getPlugin(id), isNotNull);
        expect(await Directory(replacement.installPath).exists(), isTrue);
        await expectNewData();
      } finally {
        if (!barrier.resume.isCompleted) barrier.resume.complete();
        await removal;
      }
    });
  }

  for (final target in ['data', 'cache']) {
    test('הפעלה חוזרת בזמן איפוס $target שומרת כתיבות חדשות', () async {
      final barrier = _DeletionBarrier(target == 'data' ? dataPath : cachePath);
      final reset = intercepted(
        () => installer.resetPluginData(id),
        barrier: barrier,
      );
      try {
        await barrier.started.future.timeout(const Duration(seconds: 10));
        expect(await repository.getPlugin(id), isNotNull);
        await writeNewData();
        barrier.resume.complete();
        await reset;

        expect(await release.exists(), isTrue);
        await expectNewData();
      } finally {
        if (!barrier.resume.isCompleted) barrier.resume.complete();
        await reset;
      }
    });
  }

  test('כשל בניתוק cache מדווח ומנקה את הנתונים שכבר נותקו', () async {
    await expectLater(
      intercepted(() => installer.resetPluginData(id), failRename: cachePath),
      throwsA(isA<FileSystemException>()),
    );
    expect(await Directory(dataPath).exists(), isFalse);
    expect(await File(p.join(cachePath, 'old.txt')).exists(), isTrue);
    for (final path in [dataPath, cachePath]) {
      expect(
        Directory(p.dirname(path)).listSync().where(
          (entry) => p.basename(entry.path).startsWith('.delete-'),
        ),
        isEmpty,
      );
    }
  });
}
