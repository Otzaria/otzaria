import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/plugins/bloc/plugin_system_event.dart';
import 'package:otzaria/plugins/bloc/plugin_system_state.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/services/plugin_installer_service.dart';
import 'package:otzaria/plugins/services/plugin_runtime_dispatcher.dart';
import 'package:otzaria/plugins/services/context_menu_registry.dart';
import 'package:otzaria/plugins/services/plugin_dev_loader_service.dart';
import 'package:otzaria/plugins/services/plugin_dev_watch_service.dart';
import 'package:otzaria/plugins/services/plugin_download_service.dart';
import 'package:otzaria/shortcuts/shortcut_validator.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:otzaria/core/ui_snack.dart';

class PluginSystemBloc extends Bloc<PluginSystemEvent, PluginSystemState> {
  final PluginRegistryRepository repository;
  final PluginInstallerService _installerService;
  final PluginDownloadService _downloadService;
  final PluginDevLoaderService devLoader;
  final PluginDevWatchService devWatchService;
  StreamSubscription<PluginDevFsChange>? _devWatchSub;

  PluginSystemBloc({
    required this.repository,
    PluginInstallerService? installerService,
    PluginDownloadService? downloadService,
    PluginDevLoaderService? devLoader,
    PluginDevWatchService? devWatchService,
  })  : _installerService =
            installerService ?? PluginInstallerService(repository: repository),
        _downloadService = downloadService ?? PluginDownloadService(),
        devLoader = devLoader ?? PluginDevLoaderService(repository: repository),
        devWatchService = devWatchService ?? PluginDevWatchService(),
        super(PluginSystemInitial()) {
    on<LoadPlugins>(_onLoadPlugins);
    on<InstallPluginRequested>(_onInstallPluginRequested);
    on<InstallRemotePluginRequested>(_onInstallRemotePluginRequested);
    on<ConfirmPluginInstall>(_onConfirmPluginInstall);
    on<CancelPluginInstall>(_onCancelPluginInstall);
    on<UninstallPluginRequested>(_onUninstallPluginRequested);
    on<PinPluginRequested>(_onPinPluginRequested);
    on<UnpinPluginRequested>(_onUnpinPluginRequested);
    on<PinPluginToNavRailRequested>(_onPinPluginToNavRailRequested);
    on<UnpinPluginFromNavRailRequested>(_onUnpinPluginFromNavRailRequested);
    on<SetPluginHiddenRequested>(_onSetPluginHiddenRequested);
    on<ReorderPluginsRequested>(_onReorderPluginsRequested);
    on<EnablePluginRequested>(_onEnablePluginRequested);
    on<DisablePluginRequested>(_onDisablePluginRequested);
    on<SetPluginPermissionRequested>(_onSetPluginPermissionRequested);
    on<RefreshPlugins>((event, emit) => add(LoadPlugins()));
    on<LoadDevelopmentPluginRequested>(_onLoadDevelopmentPluginRequested);
    on<DetachDevelopmentPluginRequested>(_onDetachDevelopmentPluginRequested);
    on<ReloadDevelopmentPluginRequested>(_onReloadDevelopmentPluginRequested);
    on<DevelopmentPluginManifestChanged>(_onDevelopmentPluginManifestChanged);

    _devWatchSub = this.devWatchService.events.listen((change) {
      if (change.manifestChanged) {
        add(DevelopmentPluginManifestChanged(change.pluginId));
      } else {
        unawaited(
          PluginRuntimeDispatcher.instance.reloadPlugin(change.pluginId).then(
                (_) {},
                onError: (e) => debugPrint(
                    'Plugin dev reload error [${change.pluginId}]: $e'),
              ),
        );
      }
    });
  }

  @override
  Future<void> close() {
    _devWatchSub?.cancel();
    devWatchService.dispose();
    return super.close();
  }

  Future<void> _onLoadPlugins(
      LoadPlugins event, Emitter<PluginSystemState> emit) async {
    emit(PluginSystemLoading());
    try {
      final plugins = await repository.getAllPlugins();
      devWatchService.syncWatchers(await repository.getDevelopmentPlugins());
      _registerPluginShortcuts(plugins);
      emit(PluginSystemLoaded(plugins));
    } catch (e) {
      emit(PluginSystemError(e.toString()));
      UiSnack.showError('שגיאה בטעינת תוספים: ${e.toString()}');
    }
  }

  /// רושם מפתחות קיצור לפתיחת התוספים הפעילים — רק פעילים, כי תוסף מושבת
  /// אינו נפתח דרך ה-deep-link ולכן אין טעם לזהות לו קונפליקט.
  void _registerPluginShortcuts(List<InstalledPlugin> plugins) {
    ShortcutValidator.registerPluginShortcutKeys({
      for (final p in plugins)
        if (p.enabled)
          ShortcutValidator.openPluginShortcutKey(p.pluginId):
              'פתיחת ${p.name}',
    });
  }

  Future<void> _onPinPluginRequested(
      PinPluginRequested event, Emitter<PluginSystemState> emit) async {
    try {
      await repository.updatePinState(event.pluginId, true);
      add(LoadPlugins());
    } catch (e) {
      UiSnack.showError('שגיאה בהצמדת התוסף: ${e.toString()}');
    }
  }

  Future<void> _onUnpinPluginRequested(
      UnpinPluginRequested event, Emitter<PluginSystemState> emit) async {
    try {
      await repository.updatePinState(event.pluginId, false);
      add(LoadPlugins());
    } catch (e) {
      UiSnack.showError('שגיאה בהסרת הצמדת התוסף: ${e.toString()}');
    }
  }

  Future<void> _onPinPluginToNavRailRequested(PinPluginToNavRailRequested event,
      Emitter<PluginSystemState> emit) async {
    try {
      await repository.updateNavRailPinState(event.pluginId, true);
      add(LoadPlugins());
    } catch (e) {
      UiSnack.showError('שגיאה בהצמדת התוסף לסרגל הניווט: ${e.toString()}');
    }
  }

  Future<void> _onUnpinPluginFromNavRailRequested(
      UnpinPluginFromNavRailRequested event,
      Emitter<PluginSystemState> emit) async {
    try {
      await repository.updateNavRailPinState(event.pluginId, false);
      add(LoadPlugins());
    } catch (e) {
      UiSnack.showError(
          'שגיאה בהסרת הצמדת התוסף מסרגל הניווט: ${e.toString()}');
    }
  }

  Future<void> _onSetPluginHiddenRequested(
      SetPluginHiddenRequested event, Emitter<PluginSystemState> emit) async {
    try {
      await repository.updateHiddenState(event.pluginId, event.hidden);
      add(LoadPlugins());
    } catch (e) {
      UiSnack.showError(event.hidden
          ? 'שגיאה בהסתרת התוסף: ${e.toString()}'
          : 'שגיאה בהצגת התוסף: ${e.toString()}');
    }
  }

  Future<void> _onReorderPluginsRequested(
      ReorderPluginsRequested event, Emitter<PluginSystemState> emit) async {
    try {
      await repository.reorderPlugins(event.orderedPluginIds);
      add(LoadPlugins());
    } catch (e) {
      UiSnack.showError('שגיאה בעדכון סדר התוספים: ${e.toString()}');
    }
  }

  Future<void> _onInstallPluginRequested(
      InstallPluginRequested event, Emitter<PluginSystemState> emit) async {
    try {
      final prepareInfo = await _installerService.prepareInstall(
          event.archivePath,
          forceOverwrite: event.forceOverwrite);

      emit(PluginSystemInstallRequiresPermissions(
        manifest: prepareInfo.manifest,
        tempDirPath: prepareInfo.tempDirPath,
        previousVersion: prepareInfo.previousVersion,
        previousAllowOrderBeforeBuiltInsGranted:
            prepareInfo.previousAllowOrderBeforeBuiltInsGranted,
      ));
    } on PluginOverwriteException catch (e) {
      emit(PluginSystemOverwriteRequired(
        archivePath: event.archivePath,
        pluginName: e.pluginName,
        version: e.version,
      ));
    } catch (e) {
      UiSnack.showError('שגיאה בהתקנת התוסף: ${e.toString()}');
      add(LoadPlugins()); // Reset state
    }
  }

  Future<void> _onInstallRemotePluginRequested(
      InstallRemotePluginRequested event,
      Emitter<PluginSystemState> emit) async {
    String? archivePath;

    try {
      archivePath = await _downloadService.downloadPluginArchive(
        Uri.parse(event.downloadUrl),
      );

      final prepareInfo = await _installerService.prepareInstall(
        archivePath,
        forceOverwrite: event.forceOverwrite,
      );

      emit(PluginSystemInstallRequiresPermissions(
        manifest: prepareInfo.manifest,
        tempDirPath: prepareInfo.tempDirPath,
        previousVersion: prepareInfo.previousVersion,
        previousAllowOrderBeforeBuiltInsGranted:
            prepareInfo.previousAllowOrderBeforeBuiltInsGranted,
      ));
    } on PluginOverwriteException catch (e) {
      UiSnack.show(
        'תוסף זה כבר מותקן אצלך, באותה הגרסה. '
        'להתקנה מחדש השתמש בקישור עם overwrite=true.',
      );
      debugPrint(
        'Plugin overwrite required for "${e.pluginName}" version ${e.version}',
      );
      add(LoadPlugins());
    } on PluginNewerVersionInstalledException catch (e) {
      UiSnack.show(
        'כבר מותקנת אצלך גרסה חדשה יותר של "${e.pluginName}" (${e.installedVersion})',
      );
      add(LoadPlugins());
    } catch (e) {
      UiSnack.showError('שגיאה בהתקנת התוסף מהחנות: ${e.toString()}');
      add(LoadPlugins());
    } finally {
      if (archivePath != null) {
        await _downloadService.cleanupDownloadedArchive(archivePath);
      }
    }
  }

  Future<void> _onConfirmPluginInstall(
      ConfirmPluginInstall event, Emitter<PluginSystemState> emit) async {
    try {
      // finalizeInstall מגרנט את כל ההרשאות כברירת מחדל
      await _installerService.finalizeInstall(
        event.tempDirPath,
        event.manifest,
        allowOrderBeforeBuiltInsGranted: event.allowOrderBeforeBuiltInsGranted,
      );

      // כתוב את כל בחירות המשתמש במפורש (גם true וגם false) —
      // כך הבחירה הנוכחית גוברת על החלטות עבר בהתקנה חוזרת/עדכון
      for (final entry in event.grantedPermissions.entries) {
        await repository.setPermission(
            event.manifest.id, entry.key, entry.value);
      }

      UiSnack.showSuccess('התוסף הותקן בהצלחה');
      add(LoadPlugins());
    } catch (e) {
      await _installerService.cancelInstall(event.tempDirPath);
      UiSnack.showError('שגיאה באישור התקנה: ${e.toString()}');
      add(LoadPlugins());
    }
  }

  Future<void> _onCancelPluginInstall(
      CancelPluginInstall event, Emitter<PluginSystemState> emit) async {
    await _installerService.cancelInstall(event.tempDirPath);
    add(LoadPlugins());
  }

  Future<void> _onUninstallPluginRequested(
      UninstallPluginRequested event, Emitter<PluginSystemState> emit) async {
    try {
      ContextMenuRegistry.instance.removeAll(event.pluginId);
      await _installerService.uninstallPlugin(event.pluginId);
      add(LoadPlugins());
    } catch (e) {
      UiSnack.showError('שגיאה בהסרת התוסף: ${e.toString()}');
    }
  }

  Future<void> _onEnablePluginRequested(
      EnablePluginRequested event, Emitter<PluginSystemState> emit) async {
    try {
      final plugin = await repository.getPlugin(event.pluginId);
      if (plugin != null) {
        await repository.savePlugin(plugin.copyWith(enabled: true));
        PluginRuntimeDispatcher.instance.invalidatePlugin(event.pluginId);
        add(LoadPlugins());
      }
    } catch (e) {
      UiSnack.showError('שגיאה בהפעלת התוסף: ${e.toString()}');
    }
  }

  Future<void> _onDisablePluginRequested(
      DisablePluginRequested event, Emitter<PluginSystemState> emit) async {
    try {
      ContextMenuRegistry.instance.removeAll(event.pluginId);
      final plugin = await repository.getPlugin(event.pluginId);
      if (plugin != null) {
        await repository.savePlugin(plugin.copyWith(enabled: false));
        PluginRuntimeDispatcher.instance.invalidatePlugin(event.pluginId);
        add(LoadPlugins());
      }
    } catch (e) {
      UiSnack.showError('שגיאה בהשבתת התוסף: ${e.toString()}');
    }
  }

  Future<void> _onSetPluginPermissionRequested(
      SetPluginPermissionRequested event,
      Emitter<PluginSystemState> emit) async {
    try {
      await repository.setPermission(
          event.pluginId, event.permission, event.granted);
      PluginRuntimeDispatcher.instance.invalidatePlugin(event.pluginId);
      final permissions = await repository.getPluginPermissions(event.pluginId);
      final grantedPermissions = permissions
          .where((permission) => permission.granted)
          .map((permission) => permission.permission)
          .toList();
      PluginRuntimeDispatcher.instance.dispatchEvent(
        'plugin.permissions_changed',
        {'permissions': grantedPermissions},
      );
      add(LoadPlugins());
    } catch (e) {
      UiSnack.showError('שגיאה בעדכון הרשאה: ${e.toString()}');
    }
  }

  Future<void> _onLoadDevelopmentPluginRequested(
      LoadDevelopmentPluginRequested event,
      Emitter<PluginSystemState> emit) async {
    try {
      await devLoader.loadDevelopmentPlugin(event.directoryPath);
      add(LoadPlugins());
      UiSnack.showSuccess('תוסף פיתוח נטען בהצלחה');
    } catch (e, stackTrace) {
      debugPrint(
          '[PluginDevLoader] Failed to load plugin from "${event.directoryPath}": $e');
      debugPrint('$stackTrace');
      UiSnack.showError('שגיאה בטעינת תוסף פתוח: ${e.toString()}');
    }
  }

  Future<void> _onDetachDevelopmentPluginRequested(
      DetachDevelopmentPluginRequested event,
      Emitter<PluginSystemState> emit) async {
    try {
      ContextMenuRegistry.instance.removeAll(event.pluginId);
      await repository.detachDevelopmentPlugin(event.pluginId);
      devWatchService.stopWatcher(event.pluginId);
      add(LoadPlugins());
    } catch (e) {
      UiSnack.showError('שגיאה בניתוק התוסף: ${e.toString()}');
    }
  }

  Future<void> _onReloadDevelopmentPluginRequested(
      ReloadDevelopmentPluginRequested event,
      Emitter<PluginSystemState> emit) async {
    PluginRuntimeDispatcher.instance.reloadPlugin(event.pluginId);
  }

  Future<void> _onDevelopmentPluginManifestChanged(
      DevelopmentPluginManifestChanged event,
      Emitter<PluginSystemState> emit) async {
    try {
      final plugin = await repository.getPlugin(event.pluginId);
      if (plugin != null &&
          plugin.isDevelopment &&
          plugin.devRootPath != null) {
        await devLoader.loadDevelopmentPlugin(plugin.devRootPath!);
        add(LoadPlugins());
        PluginRuntimeDispatcher.instance.reloadPlugin(event.pluginId);
      }
    } catch (e) {
      PluginRuntimeDispatcher.instance.reloadPlugin(event.pluginId);
    }
  }
}
