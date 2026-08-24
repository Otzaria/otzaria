import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/plugins/bloc/plugin_system_event.dart';
import 'package:otzaria/plugins/bloc/plugin_system_state.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_valid_permissions.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/services/plugin_installer_service.dart';
import 'package:otzaria/plugins/services/plugin_runtime_dispatcher.dart';
import 'package:otzaria/plugins/services/context_menu_registry.dart';
import 'package:otzaria/plugins/services/plugin_toolbar_registry.dart';
import 'package:otzaria/plugins/services/plugin_highlight_registry.dart';
import 'package:otzaria/plugins/services/plugin_startup_contributions_service.dart';
import 'package:otzaria/plugins/services/plugin_lazy_activation_service.dart';
import 'package:otzaria/plugins/services/plugin_dev_loader_service.dart';
import 'package:otzaria/plugins/services/plugin_dev_watch_service.dart';
import 'package:otzaria/plugins/services/plugin_download_service.dart';
import 'package:otzaria/plugins/services/plugin_external_search_service.dart';
import 'package:otzaria/plugins/services/plugin_file_server.dart';
import 'package:otzaria/plugins/services/plugin_in_book_search_service.dart';
import 'package:otzaria/plugins/services/plugin_install_report_service.dart';
import 'package:otzaria/plugins/declarative/services/declarative_plugin_host_service.dart';
import 'package:otzaria/shortcuts/shortcut_validator.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/core/messages/plugin_messages.dart';
import 'package:package_info_plus/package_info_plus.dart';

class PluginSystemBloc extends Bloc<PluginSystemEvent, PluginSystemState> {
  final PluginRegistryRepository repository;
  final PluginInstallerService _installerService;
  final PluginDownloadService _downloadService;
  final PluginDevLoaderService devLoader;
  final PluginDevWatchService devWatchService;
  final DeclarativePluginHost? declarativeHost;
  StreamSubscription<PluginDevFsChange>? _devWatchSub;
  StreamSubscription<TabsState>? _readerStateSub;

  /// חתימת הקלט האחרון שסונכרן ל-declarativeHost. סנכרון מלא (קומפילציה מחדש
  /// + שאילתות DB דקלרטיביות) יקר; רק שינוי בקלט שהוא נשען עליו מחייב אותו,
  /// ולא פעולות זולות (נעיצה, סידור, showInTools) שגם הן גוררות LoadPlugins.
  String? _lastDeclarativeSyncSignature;

  PluginSystemBloc({
    required this.repository,
    PluginInstallerService? installerService,
    PluginDownloadService? downloadService,
    PluginDevLoaderService? devLoader,
    PluginDevWatchService? devWatchService,
    this.declarativeHost,
    Stream<TabsState>? readerStates,
    TabsState? initialReaderState,
  }) : _installerService =
           installerService ?? PluginInstallerService(repository: repository),
       _downloadService = downloadService ?? PluginDownloadService(),
       devLoader = devLoader ?? PluginDevLoaderService(repository: repository),
       devWatchService = devWatchService ?? PluginDevWatchService(),
       super(PluginSystemInitial()) {
    on<LoadPlugins>(_onLoadPlugins, transformer: sequential());
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
    on<ReorderPluginsRequested>(
      _onReorderPluginsRequested,
      transformer: sequential(),
    );
    on<EnablePluginRequested>(_onEnablePluginRequested);
    on<DisablePluginRequested>(_onDisablePluginRequested);
    on<SetPluginPermissionRequested>(
      _onSetPluginPermissionRequested,
      transformer: sequential(),
    );
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
    if (declarativeHost != null) {
      if (initialReaderState != null) {
        _syncDeclarativeReaderContext(initialReaderState);
      }
      _readerStateSub = readerStates?.listen(_syncDeclarativeReaderContext);
    }
  }

  @override
  Future<void> close() async {
    await _devWatchSub?.cancel();
    await _readerStateSub?.cancel();
    devWatchService.dispose();
    declarativeHost?.dispose();
    await super.close();
  }

  Future<void> _onLoadPlugins(
    LoadPlugins event,
    Emitter<PluginSystemState> emit,
  ) async {
    // מצב "טוען" רק כשאין עדיין רשימה בזיכרון. טעינה חוזרת (אחרי התקנה,
    // הצמדה, סידור מחדש וכו') היא רענון — ואם נעבור דרך PluginSystemLoading
    // כל צרכן שבודק `is! PluginSystemLoaded` יראה לרגע "אין תוספים": מסך הכלי
    // יחליף את התוסף בספינר, ה-WebView ייהרס ויטען מאפס.
    if (state is! PluginSystemLoaded) emit(PluginSystemLoading());
    try {
      final plugins = await repository.getAllPlugins();
      devWatchService.syncWatchers(await repository.getDevelopmentPlugins());
      _registerPluginShortcuts(plugins);
      await PluginStartupContributionsService.instance.sync(
        plugins,
        repository,
      );
      if (declarativeHost != null) {
        final signature = await _declarativeSyncSignature(plugins);
        if (signature != _lastDeclarativeSyncSignature) {
          // השמירה רק אחרי סנכרון מוצלח: כשל באמצע משאיר את הרישומים חסרים,
          // וחתימה שמורה הייתה גורמת לכל LoadPlugins הבא לדלג על התיקון.
          await declarativeHost!.syncPlugins(plugins);
          _lastDeclarativeSyncSignature = signature;
        }
      }
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

  /// חתימת הקלט ש-[DeclarativePluginHost.syncPlugins] נשען עליו: לכל תוסף
  /// פעיל בעל `contributes.startup` — המניפסט כולו וההרשאות שהוענקו לו.
  /// חותמים על המניפסט השלם ולא על שדות נבחרים, כי הקומפילציה נשענת גם על
  /// permissions ו-databaseSources ועריכה שקטה שלהם הייתה מדלגת על הסנכרון.
  Future<String> _declarativeSyncSignature(
    List<InstalledPlugin> plugins,
  ) async {
    final parts = <String>[];
    for (final plugin in plugins) {
      if (!plugin.enabled) continue;
      // אותו פרדיקט כמו ב-syncPlugins: startup ריק אך קיים עדיין נרשם.
      if (plugin.manifest.startup == null) continue;
      final granted = (await repository.getGrantedPermissionNames(
        plugin.pluginId,
      )).toList()..sort();
      parts.add(
        jsonEncode({
          'id': plugin.pluginId,
          'version': plugin.version,
          'manifest': plugin.manifest.toJson(),
          'granted': granted,
        }),
      );
    }
    parts.sort();
    return parts.join('|');
  }

  /// מסיר את הרישומים הדקלרטיביים של תוסף ומאפס את החתימה — בלעדיה, שינוי
  /// שאינו מהפך אותה (למשל setPermission שהוא no-op) היה מדלג על השחזור.
  void _removeDeclarative(String pluginId) {
    if (declarativeHost == null) return;
    declarativeHost!.removePlugin(pluginId);
    _lastDeclarativeSyncSignature = null;
  }

  void _syncDeclarativeReaderContext(TabsState state) {
    final pane = state.readingPane;
    if (pane is TextBookTab) {
      unawaited(
        declarativeHost?.readerBookChanged(
          pane.book,
          context: 'reader-text',
        ),
      );
      return;
    }
    if (pane is PdfBookTab) {
      unawaited(
        declarativeHost?.readerBookChanged(
          pane.book,
          context: 'reader-pdf',
        ),
      );
      return;
    }
    unawaited(
      declarativeHost?.readerBookChanged(null, context: 'reader-text'),
    );
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

  /// מדווח את תוצאת ההתקנה לאתר, כשההקשר צמוד לבקשה שהסתיימה.
  /// fire-and-forget — הדיווח לעולם אינו מעכב או מכשיל את הזרימה.
  void _reportInstallResult(
    PluginInstallReportContext? report, {
    required bool success,
    String? errorMessage,
    bool updated = false,
  }) {
    if (report == null) return;
    unawaited(
      PluginInstallReportService.report(
        report,
        success: success,
        errorMessage: errorMessage,
        updated: updated,
      ),
    );
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
          previousGrantedPermissions: prepareInfo.previousGrantedPermissions,
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

    // אישור קבלה מיידי לאתר החנות — עוד לפני ההורדה ודיאלוג ההרשאות,
    // כדי שהדף יידע מהר שאוצריא קיבלה את הבקשה (fire-and-forget).
    final ack = event.reportContext;
    if (ack != null) {
      unawaited(PluginInstallReportService.acknowledge(ack));
    }

    try {
      String? appVersion;
      try {
        appVersion = (await PackageInfo.fromPlatform()).version;
      } catch (_) {}

      archivePath = await _downloadService.downloadPluginArchive(
        Uri.parse(event.downloadUrl),
        appVersion: appVersion,
        storeOnly: event.storeOnly,
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
          previousGrantedPermissions: prepareInfo.previousGrantedPermissions,
          reportContext: event.reportContext,
        ),
      );
    } on PluginOverwriteException catch (e) {
      UiSnack.show(PluginMessages.pluginAlreadyInstalledSameVersion);
      debugPrint(
        'Plugin overwrite required for "${e.pluginName}" version ${e.version}',
      );
      _reportInstallResult(
        event.reportContext,
        success: false,
        errorMessage: 'התוסף כבר מותקן בגרסה זו',
      );
      add(LoadPlugins());
    } on PluginStoreIncompatibleException catch (e) {
      // tryParse מבטיח שלפחות אחד הגבולות קיים, לכן maxAppVersion אינו null כאן.
      final String message;
      if (e.isAboveCeiling || e.minAppVersion.isEmpty) {
        message = PluginMessages.pluginRequiresOlderApp(e.maxAppVersion!);
      } else {
        final minSupported = e.minSupportedAppVersion;
        message = minSupported == null
            ? PluginMessages.pluginRequiresNewerApp(e.minAppVersion)
            : PluginMessages.pluginRequiresNewerAppWithFallback(
                e.minAppVersion,
                minSupported,
              );
      }
      UiSnack.showError(message);
      _reportInstallResult(
        event.reportContext,
        success: false,
        errorMessage: message,
      );
      add(LoadPlugins());
    } on PluginNewerVersionInstalledException catch (e) {
      UiSnack.show(
        PluginMessages.newerVersionInstalled(e.pluginName, e.installedVersion),
      );
      _reportInstallResult(
        event.reportContext,
        success: false,
        errorMessage: 'מותקנת כבר גרסה חדשה יותר (${e.installedVersion})',
      );
      add(LoadPlugins());
    } catch (e) {
      UiSnack.showError(PluginMessages.installRemotePluginError(e));
      _reportInstallResult(
        event.reportContext,
        success: false,
        errorMessage: 'שגיאה בהורדה או בפתיחת קובץ התוסף',
      );
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
      await _installerService.finalizeInstall(
        event.tempDirPath,
        event.manifest,
        allowOrderBeforeBuiltInsGranted: event.allowOrderBeforeBuiltInsGranted,
        grantedPermissions: event.grantedPermissions,
      );

      UiSnack.showSuccess(
        event.isUpdate
            ? PluginMessages.pluginUpdatedSuccess
            : PluginMessages.pluginInstalledSuccess,
      );
      _reportInstallResult(
        event.reportContext,
        success: true,
        updated: event.isUpdate,
      );
      add(LoadPlugins());
    } catch (e) {
      await _installerService.cancelInstall(event.tempDirPath);
      UiSnack.showError(PluginMessages.confirmInstallError(e));
      _reportInstallResult(
        event.reportContext,
        success: false,
        errorMessage: 'שגיאה בהשלמת ההתקנה',
      );
      add(LoadPlugins());
    }
  }

  Future<void> _onCancelPluginInstall(
    CancelPluginInstall event,
    Emitter<PluginSystemState> emit,
  ) async {
    await _installerService.cancelInstall(event.tempDirPath);
    _reportInstallResult(
      event.reportContext,
      success: false,
      errorMessage: 'ההתקנה בוטלה על ידי המשתמש',
    );
    add(LoadPlugins());
  }

  Future<void> _onUninstallPluginRequested(
    UninstallPluginRequested event,
    Emitter<PluginSystemState> emit,
  ) async {
    try {
      _removeDeclarative(event.pluginId);
      ContextMenuRegistry.instance.removeAll(event.pluginId);
      PluginToolbarRegistry.instance.removeAll(event.pluginId);
      PluginHighlightRegistry.instance.removePlugin(event.pluginId);
      PluginFileServer.instance.revokeAllForPlugin(event.pluginId);
      _removeSearchProviders(event.pluginId);
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
      _removeDeclarative(event.pluginId);
      ContextMenuRegistry.instance.removeAll(event.pluginId);
      PluginToolbarRegistry.instance.removeAll(event.pluginId);
      PluginHighlightRegistry.instance.removePlugin(event.pluginId);
      PluginFileServer.instance.revokeAllForPlugin(event.pluginId);
      _removeSearchProviders(event.pluginId);
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
      _removeDeclarative(event.pluginId);
      await repository.setPermission(
        event.pluginId,
        event.permission,
        event.granted,
      );
      if (!event.granted) {
        if (event.permission == 'reader.open') {
          _removeSearchProviders(event.pluginId);
        } else if (event.permission == 'search.dialog' ||
            event.permission == pluginStartupContributionsPermission) {
          PluginExternalSearchService.instance.removePlugin(event.pluginId);
        }
        if (event.permission == 'fs.user_files.read') {
          PluginFileServer.instance.revokeAllForPlugin(event.pluginId);
        }
        if (event.permission == 'reader.toolbar') {
          PluginToolbarRegistry.instance.removeAll(event.pluginId);
        }
        if (event.permission == 'reader.context_menu') {
          ContextMenuRegistry.instance.removeAll(event.pluginId);
        }
        if (event.permission == pluginRunOnStartupPermission ||
            event.permission == pluginStartupContributionsPermission) {
          PluginLazyActivationService.instance.removePlugin(event.pluginId);
        }
      }
      PluginRuntimeDispatcher.instance.invalidatePlugin(event.pluginId);
      final grantedPermissions = await repository.getGrantedPermissionNames(
        event.pluginId,
      );
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
      _removeDeclarative(event.pluginId);
      ContextMenuRegistry.instance.removeAll(event.pluginId);
      PluginToolbarRegistry.instance.removeAll(event.pluginId);
      PluginHighlightRegistry.instance.removePlugin(event.pluginId);
      _removeSearchProviders(event.pluginId);
      PluginFileServer.instance.revokeAllForPlugin(event.pluginId);
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
    _removeSearchProviders(event.pluginId);
    PluginRuntimeDispatcher.instance.reloadPlugin(event.pluginId);
  }

  Future<void> _onDevelopmentPluginManifestChanged(
    DevelopmentPluginManifestChanged event,
    Emitter<PluginSystemState> emit,
  ) async {
    try {
      _removeSearchProviders(event.pluginId);
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
          grantedPermissions: event.grantedPermissions,
          allowOrderBeforeBuiltInsGranted:
              event.allowOrderBeforeBuiltInsGranted,
        );
      } else {
        await devLoader.loadDevelopmentPlugin(
          event.sourcePath,
          preValidatedManifest: event.manifest,
          grantedPermissions: event.grantedPermissions,
          allowOrderBeforeBuiltInsGranted:
              event.allowOrderBeforeBuiltInsGranted,
        );
      }
      add(LoadPlugins());
      UiSnack.showSuccess(
        event.isUpdate
            ? PluginMessages.devPluginUpdatedSuccess
            : PluginMessages.devPluginInstalledSuccess,
      );
    } catch (e) {
      UiSnack.showError(PluginMessages.installDevPluginError(e));
      add(LoadPlugins());
    }
  }

  void _removeSearchProviders(String pluginId) {
    PluginExternalSearchService.instance.removePlugin(pluginId);
    PluginInBookSearchService.instance.removePlugin(pluginId);
  }
}
