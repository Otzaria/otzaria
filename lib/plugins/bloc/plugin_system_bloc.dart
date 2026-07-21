import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/plugins/bloc/plugin_system_event.dart';
import 'package:otzaria/plugins/bloc/plugin_system_state.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/services/plugin_installer_service.dart';
import 'package:otzaria/plugins/services/plugin_runtime_dispatcher.dart';
import 'package:otzaria/plugins/services/context_menu_registry.dart';
import 'package:otzaria/plugins/services/plugin_highlight_registry.dart';
import 'package:otzaria/plugins/services/plugin_dev_loader_service.dart';
import 'package:otzaria/plugins/services/plugin_dev_watch_service.dart';
import 'package:otzaria/plugins/services/plugin_download_service.dart';
import 'package:otzaria/shortcuts/shortcut_validator.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/core/messages/plugin_messages.dart';

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
  }) : _installerService =
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
    on<SetPluginShowInToolsRequested>(_onSetPluginShowInToolsRequested);
    on<ReorderPluginsRequested>(_onReorderPluginsRequested);
    on<EnablePluginRequested>(_onEnablePluginRequested);
    on<DisablePluginRequested>(_onDisablePluginRequested);
    on<SetPluginPermissionRequested>(_onSetPluginPermissionRequested);
    on<RefreshPlugins>((event, emit) => add(LoadPlugins()));
    on<LoadDevelopmentPluginRequested>(_onLoadDevelopmentPluginRequested);
    on<DetachDevelopmentPluginRequested>(_onDetachDevelopmentPluginRequested);
    on<ReloadDevelopmentPluginRequested>(_onReloadDevelopmentPluginRequested);
    on<DevelopmentPluginManifestChanged>(_onDevelopmentPluginManifestChanged);
    on<LoadLocalhostPluginRequested>(_onLoadLocalhostPluginRequested);
    on<ConfirmDevPluginInstall>(_onConfirmDevPluginInstall);

    _devWatchSub = this.devWatchService.events.listen((change) {
      if (change.manifestChanged) {
        add(DevelopmentPluginManifestChanged(change.pluginId));
      } else {
        unawaited(
          PluginRuntimeDispatcher.instance
              .reloadPlugin(change.pluginId)
              .then(
                (_) {},
                onError: (e) => debugPrint(
                  'Plugin dev reload error [${change.pluginId}]: $e',
                ),
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
    LoadPlugins event,
    Emitter<PluginSystemState> emit,
  ) async {
    emit(PluginSystemLoading());
    try {
      final plugins = await repository.getAllPlugins();
      devWatchService.syncWatchers(await repository.getDevelopmentPlugins());
      _registerPluginShortcuts(plugins);
      emit(PluginSystemLoaded(plugins));
    } catch (e) {
      emit(PluginSystemError(e.toString()));
      UiSnack.showError(PluginMessages.loadPluginsError(e));
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
    PinPluginRequested event,
    Emitter<PluginSystemState> emit,
  ) async {
    try {
      await repository.updatePinState(event.pluginId, true);
      add(LoadPlugins());
    } catch (e) {
      UiSnack.showError(PluginMessages.pinPluginError(e));
    }
  }

  Future<void> _onUnpinPluginRequested(
    UnpinPluginRequested event,
    Emitter<PluginSystemState> emit,
  ) async {
    try {
      await repository.updatePinState(event.pluginId, false);
      add(LoadPlugins());
    } catch (e) {
      UiSnack.showError(PluginMessages.unpinPluginError(e));
    }
  }

  Future<void> _onPinPluginToNavRailRequested(
    PinPluginToNavRailRequested event,
    Emitter<PluginSystemState> emit,
  ) async {
    try {
      await repository.updateNavRailPinState(event.pluginId, true);
      add(LoadPlugins());
    } catch (e) {
      UiSnack.showError(PluginMessages.pinPluginToNavRailError(e));
    }
  }

  Future<void> _onUnpinPluginFromNavRailRequested(
    UnpinPluginFromNavRailRequested event,
    Emitter<PluginSystemState> emit,
  ) async {
    try {
      await repository.updateNavRailPinState(event.pluginId, false);
      add(LoadPlugins());
    } catch (e) {
      UiSnack.showError(PluginMessages.unpinPluginFromNavRailError(e));
    }
  }

  Future<void> _onSetPluginShowInToolsRequested(
    SetPluginShowInToolsRequested event,
    Emitter<PluginSystemState> emit,
  ) async {
    try {
      await repository.updateShowInTools(event.pluginId, event.showInTools);
      add(LoadPlugins());
    } catch (e) {
      UiSnack.showError(
        event.showInTools
            ? PluginMessages.showPluginInToolsError(e)
            : PluginMessages.hidePluginFromToolsError(e),
      );
    }
  }

  Future<void> _onReorderPluginsRequested(
    ReorderPluginsRequested event,
    Emitter<PluginSystemState> emit,
  ) async {
    try {
      await repository.reorderPlugins(event.orderedPluginIds);
      add(LoadPlugins());
    } catch (e) {
      UiSnack.showError(PluginMessages.reorderPluginsError(e));
    }
  }

  Future<void> _onInstallPluginRequested(
    InstallPluginRequested event,
    Emitter<PluginSystemState> emit,
  ) async {
    try {
      final prepareInfo = await _installerService.prepareInstall(
        event.archivePath,
        forceOverwrite: event.forceOverwrite,
      );

      emit(
        PluginSystemInstallRequiresPermissions(
          manifest: prepareInfo.manifest,
          tempDirPath: prepareInfo.tempDirPath,
          previousVersion: prepareInfo.previousVersion,
          previousAllowOrderBeforeBuiltInsGranted:
              prepareInfo.previousAllowOrderBeforeBuiltInsGranted,
        ),
      );
    } on PluginOverwriteException catch (e) {
      emit(
        PluginSystemOverwriteRequired(
          archivePath: event.archivePath,
          pluginName: e.pluginName,
          version: e.version,
        ),
      );
    } catch (e) {
      UiSnack.showError(PluginMessages.installPluginError(e));
      add(LoadPlugins()); // Reset state
    }
  }

  Future<void> _onInstallRemotePluginRequested(
    InstallRemotePluginRequested event,
    Emitter<PluginSystemState> emit,
  ) async {
    String? archivePath;

    try {
      archivePath = await _downloadService.downloadPluginArchive(
        Uri.parse(event.downloadUrl),
      );

      final prepareInfo = await _installerService.prepareInstall(
        archivePath,
        forceOverwrite: event.forceOverwrite,
      );

      emit(
        PluginSystemInstallRequiresPermissions(
          manifest: prepareInfo.manifest,
          tempDirPath: prepareInfo.tempDirPath,
          previousVersion: prepareInfo.previousVersion,
          previousAllowOrderBeforeBuiltInsGranted:
              prepareInfo.previousAllowOrderBeforeBuiltInsGranted,
        ),
      );
    } on PluginOverwriteException catch (e) {
      UiSnack.show(PluginMessages.pluginAlreadyInstalledSameVersion);
      debugPrint(
        'Plugin overwrite required for "${e.pluginName}" version ${e.version}',
      );
      add(LoadPlugins());
    } on PluginNewerVersionInstalledException catch (e) {
      UiSnack.show(
        PluginMessages.newerVersionInstalled(e.pluginName, e.installedVersion),
      );
      add(LoadPlugins());
    } catch (e) {
      UiSnack.showError(PluginMessages.installRemotePluginError(e));
      add(LoadPlugins());
    } finally {
      if (archivePath != null) {
        await _downloadService.cleanupDownloadedArchive(archivePath);
      }
    }
  }

  Future<void> _onConfirmPluginInstall(
    ConfirmPluginInstall event,
    Emitter<PluginSystemState> emit,
  ) async {
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
          event.manifest.id,
          entry.key,
          entry.value,
        );
      }

      UiSnack.showSuccess(PluginMessages.pluginInstalledSuccess);
      add(LoadPlugins());
    } catch (e) {
      await _installerService.cancelInstall(event.tempDirPath);
      UiSnack.showError(PluginMessages.confirmInstallError(e));
      add(LoadPlugins());
    }
  }

  Future<void> _onCancelPluginInstall(
    CancelPluginInstall event,
    Emitter<PluginSystemState> emit,
  ) async {
    await _installerService.cancelInstall(event.tempDirPath);
    add(LoadPlugins());
  }

  Future<void> _onUninstallPluginRequested(
    UninstallPluginRequested event,
    Emitter<PluginSystemState> emit,
  ) async {
    try {
      ContextMenuRegistry.instance.removeAll(event.pluginId);
      PluginHighlightRegistry.instance.removePlugin(event.pluginId);
      await _installerService.uninstallPlugin(event.pluginId);
      add(LoadPlugins());
    } catch (e) {
      UiSnack.showError(PluginMessages.uninstallPluginError(e));
    }
  }

  Future<void> _onEnablePluginRequested(
    EnablePluginRequested event,
    Emitter<PluginSystemState> emit,
  ) async {
    try {
      final plugin = await repository.getPlugin(event.pluginId);
      if (plugin != null) {
        await repository.savePlugin(plugin.copyWith(enabled: true));
        PluginRuntimeDispatcher.instance.invalidatePlugin(event.pluginId);
        add(LoadPlugins());
      }
    } catch (e) {
      UiSnack.showError(PluginMessages.enablePluginError(e));
    }
  }

  Future<void> _onDisablePluginRequested(
    DisablePluginRequested event,
    Emitter<PluginSystemState> emit,
  ) async {
    try {
      ContextMenuRegistry.instance.removeAll(event.pluginId);
      PluginHighlightRegistry.instance.removePlugin(event.pluginId);
      final plugin = await repository.getPlugin(event.pluginId);
      if (plugin != null) {
        await repository.savePlugin(plugin.copyWith(enabled: false));
        PluginRuntimeDispatcher.instance.invalidatePlugin(event.pluginId);
        add(LoadPlugins());
      }
    } catch (e) {
      UiSnack.showError(PluginMessages.disablePluginError(e));
    }
  }

  Future<void> _onSetPluginPermissionRequested(
    SetPluginPermissionRequested event,
    Emitter<PluginSystemState> emit,
  ) async {
    try {
      await repository.setPermission(
        event.pluginId,
        event.permission,
        event.granted,
      );
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
      UiSnack.showError(PluginMessages.updatePermissionError(e));
    }
  }

  Future<void> _onLoadDevelopmentPluginRequested(
    LoadDevelopmentPluginRequested event,
    Emitter<PluginSystemState> emit,
  ) async {
    try {
      final manifest = await devLoader.fetchDevelopmentManifest(
        event.directoryPath,
      );
      final existing = await repository.getPlugin(manifest.id);
      if (existing != null && !existing.isDevelopment) {
        UiSnack.showError(PluginMessages.duplicatePluginIdError);
        return;
      }
      if (existing != null) {
        await devLoader.loadDevelopmentPlugin(
          event.directoryPath,
          preValidatedManifest: manifest,
        );
        add(LoadPlugins());
        UiSnack.showSuccess(PluginMessages.devPluginReloaded);
      } else {
        emit(
          PluginSystemDevInstallRequiresPermissions(
            manifest: manifest,
            sourcePath: event.directoryPath,
            sourceType: 'development',
          ),
        );
      }
    } catch (e, stackTrace) {
      debugPrint(
        '[PluginDevLoader] Failed to load plugin from "${event.directoryPath}": $e',
      );
      debugPrint('$stackTrace');
      UiSnack.showError(PluginMessages.loadDevPluginError(e));
    }
  }

  Future<void> _onDetachDevelopmentPluginRequested(
    DetachDevelopmentPluginRequested event,
    Emitter<PluginSystemState> emit,
  ) async {
    try {
      ContextMenuRegistry.instance.removeAll(event.pluginId);
      PluginHighlightRegistry.instance.removePlugin(event.pluginId);
      await repository.detachDevelopmentPlugin(event.pluginId);
      devWatchService.stopWatcher(event.pluginId);
      add(LoadPlugins());
    } catch (e) {
      UiSnack.showError(PluginMessages.detachDevPluginError(e));
    }
  }

  Future<void> _onReloadDevelopmentPluginRequested(
    ReloadDevelopmentPluginRequested event,
    Emitter<PluginSystemState> emit,
  ) async {
    PluginHighlightRegistry.instance.removePlugin(event.pluginId);
    PluginRuntimeDispatcher.instance.reloadPlugin(event.pluginId);
  }

  Future<void> _onDevelopmentPluginManifestChanged(
    DevelopmentPluginManifestChanged event,
    Emitter<PluginSystemState> emit,
  ) async {
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

  Future<void> _onLoadLocalhostPluginRequested(
    LoadLocalhostPluginRequested event,
    Emitter<PluginSystemState> emit,
  ) async {
    try {
      final manifest = await devLoader.fetchLocalhostManifest(event.baseUrl);
      final existing = await repository.getPlugin(manifest.id);
      if (existing != null && !existing.isDevelopment) {
        UiSnack.showError(PluginMessages.duplicatePluginIdError);
        return;
      }
      if (existing != null) {
        await devLoader.loadLocalhostPlugin(
          event.baseUrl,
          preValidatedManifest: manifest,
        );
        add(LoadPlugins());
        UiSnack.showSuccess(PluginMessages.localhostPluginReloaded);
      } else {
        emit(
          PluginSystemDevInstallRequiresPermissions(
            manifest: manifest,
            sourcePath: event.baseUrl,
            sourceType: 'localhost_dev',
          ),
        );
      }
    } catch (e, stackTrace) {
      debugPrint(
        '[PluginLocalhostLoader] Failed to load plugin from "${event.baseUrl}": $e',
      );
      debugPrint('$stackTrace');
      UiSnack.showError(PluginMessages.loadLocalhostPluginError(e));
    }
  }

  Future<void> _onConfirmDevPluginInstall(
    ConfirmDevPluginInstall event,
    Emitter<PluginSystemState> emit,
  ) async {
    try {
      // מעביר את המניפסט שהוצג למשתמש — מונע re-fetch שעלול להכניס הרשאות
      // חדשות שלא אושרו בדיאלוג.
      if (event.sourceType == 'localhost_dev') {
        await devLoader.loadLocalhostPlugin(
          event.sourcePath,
          preValidatedManifest: event.manifest,
        );
      } else {
        await devLoader.loadDevelopmentPlugin(
          event.sourcePath,
          preValidatedManifest: event.manifest,
        );
      }
      // דרוס הרשאות ו-allowOrderBeforeBuiltInsGranted בבחירות המשתמש המפורשות
      for (final entry in event.grantedPermissions.entries) {
        await repository.setPermission(
          event.manifest.id,
          entry.key,
          entry.value,
        );
      }
      final saved = await repository.getPlugin(event.manifest.id);
      if (saved != null &&
          saved.allowOrderBeforeBuiltInsGranted !=
              event.allowOrderBeforeBuiltInsGranted) {
        await repository.savePlugin(
          saved.copyWith(
            allowOrderBeforeBuiltInsGranted:
                event.allowOrderBeforeBuiltInsGranted,
          ),
        );
      }
      add(LoadPlugins());
      UiSnack.showSuccess(PluginMessages.devPluginInstalledSuccess);
    } catch (e) {
      UiSnack.showError(PluginMessages.installDevPluginError(e));
      add(LoadPlugins());
    }
  }
}
