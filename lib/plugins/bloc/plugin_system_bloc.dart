import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/plugins/utils/plugin_safe_mode.dart';
import 'package:otzaria/plugins/bloc/plugin_system_event.dart';
import 'package:otzaria/plugins/bloc/plugin_system_state.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/models/plugin_valid_permissions.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/services/bundled_plugin_seed_service.dart';
import 'package:otzaria/plugins/services/plugin_installer_service.dart';
import 'package:otzaria/plugins/services/plugin_runtime_dispatcher.dart';
import 'package:otzaria/plugins/services/context_menu_registry.dart';
import 'package:otzaria/plugins/services/plugin_shortcut_registry.dart';
import 'package:otzaria/plugins/services/plugin_toolbar_registry.dart';
import 'package:otzaria/plugins/services/plugin_new_tab_page_registry.dart';
import 'package:otzaria/plugins/services/plugin_new_tab_page_service.dart';
import 'package:otzaria/plugins/services/plugin_network_policy.dart';
import 'package:otzaria/plugins/services/plugin_text_reader_registry.dart';
import 'package:otzaria/plugins/services/plugin_highlight_registry.dart';
import 'package:otzaria/plugins/services/plugin_correction_session_service.dart';
import 'package:otzaria/plugins/services/plugin_startup_contributions_service.dart';
import 'package:otzaria/plugins/services/plugin_lazy_activation_service.dart';
import 'package:otzaria/plugins/services/plugin_dev_loader_service.dart';
import 'package:otzaria/plugins/services/plugin_dev_watch_service.dart';
import 'package:otzaria/plugins/services/plugin_download_service.dart';
import 'package:otzaria/plugins/services/plugin_external_search_service.dart';
import 'package:otzaria/plugins/services/plugin_file_server.dart';
import 'package:otzaria/plugins/services/plugin_search_dialog_registry.dart';
import 'package:otzaria/plugins/services/plugin_search_field_actions_registry.dart';
import 'package:otzaria/plugins/services/plugin_search_field_session_service.dart';
import 'package:otzaria/plugins/services/plugin_external_editions_registry.dart';
import 'package:otzaria/plugins/services/plugin_condition_evaluator.dart';
import 'package:otzaria/plugins/services/plugin_in_book_search_service.dart';
import 'package:otzaria/plugins/services/plugin_library_books_registry.dart';
import 'package:otzaria/plugins/services/plugin_install_report_service.dart';
import 'package:otzaria/plugins/services/plugin_install_results_log.dart';
import 'package:otzaria/plugins/declarative/services/declarative_plugin_host_service.dart';
import 'package:otzaria/shortcuts/shortcut_validator.dart';
import 'package:otzaria/tabs/bloc/tabs_state.dart';
import 'package:otzaria/tabs/models/pdf_tab.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/tools/calendar/services/calendar_alerts_client.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:otzaria/app_scope/process_duties.dart';
import 'package:flutter/foundation.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/core/messages/plugin_messages.dart';
import 'package:otzaria/update/app_release_version.dart';
import 'package:package_info_plus/package_info_plus.dart';

class PluginSystemBloc extends Bloc<PluginSystemEvent, PluginSystemState> {
  final PluginRegistryRepository repository;
  final PluginInstallerService _installerService;
  final PluginDownloadService _downloadService;
  final BundledPluginSeedService _bundledSeedService;
  final PluginDevLoaderService devLoader;
  final PluginDevWatchService devWatchService;
  final DeclarativePluginHost? declarativeHost;
  final PluginToolbarRegistry? toolbarRegistry;
  final bool _sharedDevWatcher;
  StreamSubscription<PluginDevFsChange>? _devWatchSub;
  StreamSubscription<TabsState>? _readerStateSub;

  /// חתימת הקלט האחרון שסונכרן ל-declarativeHost. סנכרון מלא (קומפילציה מחדש
  /// + שאילתות DB דקלרטיביות) יקר; רק שינוי בקלט שהוא נשען עליו מחייב אותו,
  /// ולא פעולות זולות (נעיצה, סידור, showInTools) שגם הן גוררות LoadPlugins.
  String? _lastDeclarativeSyncSignature;

  final PluginInstallResultsLog _installResultsLog;

  /// `null` — [ProcessDuties.current], שנקרא בכל אירוע ולא נלכד ביצירה.
  final ProcessDuties? processDuties;
  bool get _isProcessOwner =>
      (processDuties ?? ProcessDuties.current).isProcessOwner;

  /// התקנות מקישור install-local שממתינות להחלטת המשתמש, לפי תיקיית ה-temp.
  final Map<String, ({String path, String pluginId, String version})>
  _pendingLocalInstalls = {};

  /// קישורי install-local שממתינים לאישור דריסה, לפי נתיב הארכיון.
  final Map<String, String> _pendingLocalOverwrites = {};

  PluginSystemBloc({
    required this.repository,
    PluginInstallerService? installerService,
    PluginDownloadService? downloadService,
    PluginDevLoaderService? devLoader,
    PluginDevWatchService? devWatchService,
    BundledPluginSeedService? bundledSeedService,
    this.declarativeHost,
    this.toolbarRegistry,
    Stream<TabsState>? readerStates,
    TabsState? initialReaderState,
    PluginInstallResultsLog? installResultsLog,
    CalendarAlertsClient? alertsClient,
    this.processDuties,
  }) : _alertsOverride = alertsClient,
       _installResultsLog =
           installResultsLog ?? PluginInstallResultsLog.instance,
       _installerService =
           installerService ?? PluginInstallerService(repository: repository),
       _downloadService = downloadService ?? PluginDownloadService(),
       _bundledSeedService =
           bundledSeedService ??
           BundledPluginSeedService(repository: repository),
       devLoader = devLoader ?? PluginDevLoaderService(repository: repository),
       _sharedDevWatcher = devWatchService == null,
       devWatchService = devWatchService ?? PluginDevWatchService.acquire(),
       super(PluginSystemInitial()) {
    on<LoadPlugins>(_onLoadPlugins, transformer: _sequentialCoalesced());
    on<SeedBundledPlugins>(_onSeedBundledPlugins);
    on<InstallPluginRequested>(_onInstallPluginRequested);
    on<InstallRemotePluginRequested>(_onInstallRemotePluginRequested);
    on<ConfirmPluginInstall>(_onConfirmPluginInstall);
    on<CancelPluginInstall>(_onCancelPluginInstall);
    on<PluginOverwriteDeclined>(_onPluginOverwriteDeclined);
    on<UninstallPluginRequested>(_onUninstallPluginRequested);
    on<ResetPluginDataRequested>(_onResetPluginDataRequested);
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
    on<RescanDevelopmentManifests>(_onRescanDevelopmentManifests);
    on<LoadLocalhostPluginRequested>(_onLoadLocalhostPluginRequested);
    on<ConfirmDevPluginInstall>(_onConfirmDevPluginInstall);

    PluginShortcutRegistry.instance.addListener(_onPluginShortcutsChanged);

    _devWatchSub = this.devWatchService.events.listen((change) {
      unawaited(_handleDevChange(change));
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
    PluginShortcutRegistry.instance.removeListener(_onPluginShortcutsChanged);
    await _devWatchSub?.cancel();
    await _readerStateSub?.cancel();
    if (_sharedDevWatcher) {
      PluginDevWatchService.release();
    } else {
      devWatchService.dispose();
    }
    declarativeHost?.dispose();
    toolbarRegistry?.dispose();
    await super.close();
  }

  Future<void> _handleDevChange(PluginDevFsChange change) async {
    try {
      await devWatchService.handleOnce(change, () async {
        try {
          if (change.manifestChanged) {
            _removeSearchProviders(change.pluginId);
            final plugin = await repository.getPlugin(change.pluginId);
            if (plugin?.devRootPath case final root?) {
              await devLoader.loadDevelopmentPlugin(root);
            }
          }
        } finally {
          await PluginRuntimeDispatcher.instance.reloadPlugin(change.pluginId);
        }
      });
      if (change.manifestChanged && !isClosed) add(LoadPlugins());
    } catch (error) {
      debugPrint('Plugin dev reload error [${change.pluginId}]: $error');
    }
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
      await PluginSafeMode.ready;
      final plugins = await repository.getAllPlugins();
      if (PluginSafeMode.isActive) {
        devWatchService.syncWatchers(const []);
        // Listing only. Contribution sync treats a disabled plugin as removed
        // and unpublishes its data, so nothing else runs in safe mode.
        for (final plugin in plugins) {
          _clearPluginRegistrations(plugin.pluginId);
          PluginRuntimeDispatcher.instance.invalidatePlugin(plugin.pluginId);
        }
        _registerPluginShortcuts(const []);
        emit(PluginSystemLoaded(plugins));
        return;
      }
      devWatchService.syncWatchers(await repository.getDevelopmentPlugins());
      await PluginTextReaderRegistry.instance.sync(plugins, repository);
      _registerPluginShortcuts(plugins);
      await PluginStartupContributionsService.instance.sync(
        plugins,
        repository,
      );
      _registerPluginDeclaredShortcuts();
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

  Future<void> _onSeedBundledPlugins(
    SeedBundledPlugins event,
    Emitter<PluginSystemState> emit,
  ) async {
    // פר-מחשב: חלון משני היה מתקין במקביל לראשי לאותה תיקייה ו-DB.
    if (!_isProcessOwner) return;
    await PluginSafeMode.ready;
    if (PluginSafeMode.isActive) return;
    try {
      if (await _bundledSeedService.seedPending()) add(LoadPlugins());
    } catch (e) {
      debugPrint('Bundled plugin seeding failed: $e');
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

  void _onPluginShortcutsChanged() => _registerPluginDeclaredShortcuts();

  void _registerPluginDeclaredShortcuts() {
    final targets = <String, PluginShortcutTarget>{};
    for (final record in PluginShortcutRegistry.instance.getAll()) {
      final pluginId = record.$1;
      final shortcut = record.$2;
      final key = ShortcutValidator.pluginShortcutKey(pluginId, shortcut.id);
      targets[key] = (
        pluginId: pluginId,
        shortcutId: shortcut.id,
        label: shortcut.label,
        defaultKey: shortcut.key,
        command: shortcut.command,
        contextMenuItemId: shortcut.contextMenuItemId,
      );
    }
    ShortcutValidator.registerPluginShortcuts(targets);
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
        declarativeHost?.readerBookChanged(pane.book, context: 'reader-text'),
      );
      return;
    }
    if (pane is PdfBookTab) {
      unawaited(
        declarativeHost?.readerBookChanged(pane.book, context: 'reader-pdf'),
      );
      return;
    }
    unawaited(declarativeHost?.readerBookChanged(null, context: 'reader-text'));
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

  void _recordLocalResult(
    String? path,
    PluginInstallOutcome outcome, {
    String? pluginId,
    String? version,
    String? message,
  }) {
    if (path == null) return;
    unawaited(
      _installResultsLog
          .append(
            path: path,
            outcome: outcome,
            pluginId: pluginId,
            version: version,
            message: message,
          )
          .catchError(
            (Object e) => debugPrint('Plugin install result log failed: $e'),
          ),
    );
  }

  Future<void> _onInstallPluginRequested(
    InstallPluginRequested event,
    Emitter<PluginSystemState> emit,
  ) async {
    final localPath = event.recordsResult
        ? event.archivePath
        : _pendingLocalOverwrites.remove(event.archivePath);
    try {
      final prepareInfo = await _installerService.prepareInstall(
        event.archivePath,
        forceOverwrite: event.forceOverwrite,
      );

      if (localPath != null) {
        _pendingLocalInstalls[prepareInfo.tempDirPath] = (
          path: localPath,
          pluginId: prepareInfo.manifest.id,
          version: prepareInfo.manifest.version,
        );
      }
      emit(
        PluginSystemInstallRequiresPermissions(
          manifest: prepareInfo.manifest,
          tempDirPath: prepareInfo.tempDirPath,
          previousVersion: prepareInfo.previousVersion,
          previousGrantedPermissions: prepareInfo.previousGrantedPermissions,
          isUserInitiated: event.isUserInitiated,
        ),
      );
    } on PluginOverwriteException catch (e) {
      if (localPath != null) {
        _pendingLocalOverwrites[event.archivePath] = localPath;
      }
      emit(
        PluginSystemOverwriteRequired(
          archivePath: event.archivePath,
          pluginName: e.pluginName,
          version: e.version,
          isUserInitiated: event.isUserInitiated,
        ),
      );
    } on PluginNewerVersionInstalledException catch (e) {
      final message = PluginMessages.newerVersionInstalled(
        e.pluginName,
        e.installedVersion,
      );
      UiSnack.show(message);
      _recordLocalResult(
        localPath,
        PluginInstallOutcome.rejectedOlder,
        pluginId: e.pluginId,
        version: e.requestedVersion,
        message: message,
      );
      add(LoadPlugins());
    } catch (e) {
      UiSnack.showError(PluginMessages.installPluginError(e));
      _recordLocalResult(
        localPath,
        e is PluginIncompatibleAppVersionException
            ? PluginInstallOutcome.rejectedIncompatible
            : PluginInstallOutcome.failed,
        message: e.toString(),
      );
      add(LoadPlugins()); // Reset state
    }
  }

  void _onPluginOverwriteDeclined(
    PluginOverwriteDeclined event,
    Emitter<PluginSystemState> emit,
  ) {
    _recordLocalResult(
      _pendingLocalOverwrites.remove(event.archivePath),
      PluginInstallOutcome.cancelled,
      message: 'הדריסה בוטלה על ידי המשתמש',
    );
    add(LoadPlugins());
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
        appVersion = appReleaseVersion(await PackageInfo.fromPlatform());
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
          previousGrantedPermissions: prepareInfo.previousGrantedPermissions,
          reportContext: event.reportContext,
          isUserInitiated: event.isUserInitiated,
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
    var local = _pendingLocalInstalls.remove(event.tempDirPath);
    try {
      await _installerService.finalizeInstall(
        event.tempDirPath,
        event.manifest,
        grantedPermissions: event.grantedPermissions,
      );

      if (!event.manifest.permissions.contains('navigation.write') ||
          event.grantedPermissions['navigation.write'] != true) {
        PluginNewTabPageRegistry.instance.remove(event.manifest.id);
      }
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
      _recordLocalResult(
        local?.path,
        event.isUpdate
            ? PluginInstallOutcome.updated
            : PluginInstallOutcome.installed,
        pluginId: event.manifest.id,
        version: event.manifest.version,
      );
      local = null;
      final duplicates = await _findSameNameDuplicates(event.manifest);
      if (duplicates.isNotEmpty) {
        // הממשק מציג דיאלוג ומוסיף בעצמו UninstallPluginRequested / LoadPlugins.
        emit(
          PluginSystemDuplicateNameDetected(
            installedPluginId: event.manifest.id,
            pluginName: event.manifest.name,
            installedVersion: event.manifest.version,
            duplicates: duplicates,
          ),
        );
        return;
      }
      add(LoadPlugins());
    } catch (e) {
      await _installerService.cancelInstall(event.tempDirPath);
      UiSnack.showError(PluginMessages.confirmInstallError(e));
      _recordLocalResult(
        local?.path,
        PluginInstallOutcome.failed,
        pluginId: event.manifest.id,
        version: event.manifest.version,
        message: e.toString(),
      );
      _reportInstallResult(
        event.reportContext,
        success: false,
        errorMessage: 'שגיאה בהשלמת ההתקנה',
      );
      add(LoadPlugins());
    }
  }

  /// תוספים מותקנים (ארוזים, לא פיתוח) שנקראים כמו [manifest] אך בעלי id אחר.
  /// הזהות במערכת היא ה-id בלבד, ולכן שינוי id אצל המפתח משאיר את הגרסה
  /// הישנה מותקנת לצד החדשה בלי שום מנגנון שינקה אותה.
  Future<List<InstalledPlugin>> _findSameNameDuplicates(
    PluginManifest manifest,
  ) async {
    final name = manifest.name.trim();
    if (name.isEmpty) return const [];
    final all = await repository.getAllPlugins();
    return all
        .where(
          (p) =>
              p.pluginId != manifest.id &&
              p.name.trim() == name &&
              p.sourceType == 'packaged',
        )
        .toList();
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
    final local = _pendingLocalInstalls.remove(event.tempDirPath);
    _recordLocalResult(
      local?.path,
      PluginInstallOutcome.cancelled,
      pluginId: local?.pluginId,
      version: local?.version,
      message: 'ההתקנה בוטלה על ידי המשתמש',
    );
    add(LoadPlugins());
  }

  Future<void> _onUninstallPluginRequested(
    UninstallPluginRequested event,
    Emitter<PluginSystemState> emit,
  ) async {
    try {
      await _endCorrectionSessions(
        event.pluginId,
        deleteDrafts: event.deleteCorrectionDrafts,
      );
      _removeDeclarative(event.pluginId);
      ContextMenuRegistry.instance.removeAll(event.pluginId);
      PluginToolbarRegistry.instance.removeAll(event.pluginId);
      PluginShortcutRegistry.instance.removeAll(event.pluginId);
      PluginHighlightRegistry.instance.removePlugin(event.pluginId);
      PluginFileServer.instance.revokeAllForPlugin(event.pluginId);
      _removeSearchProviders(event.pluginId);
      // מיד, ולא בסנכרון שאחרי: רשימה שבאמצע שמירה הייתה נכתבת שוב ל-DB.
      PluginLibraryBooksRegistry.instance.removePlugin(event.pluginId);
      PluginNewTabPageRegistry.instance.remove(event.pluginId);
      await _cancelPluginNotifications(event.pluginId);
      await _installerService.uninstallPlugin(event.pluginId);
      _pluginCalendarEventsRemoved();
      PluginNewTabPageRegistry.instance.remove(event.pluginId);
      add(LoadPlugins());
    } catch (e) {
      UiSnack.showError(PluginMessages.uninstallPluginError(e));
    }
  }

  Future<void> _onResetPluginDataRequested(
    ResetPluginDataRequested event,
    Emitter<PluginSystemState> emit,
  ) async {
    try {
      final plugin = await repository.getPlugin(event.pluginId);
      if (plugin == null) return;
      await _endCorrectionSessions(
        event.pluginId,
        deleteDrafts: event.deleteCorrectionDrafts,
      );
      _removeDeclarative(event.pluginId);
      ContextMenuRegistry.instance.removeAll(event.pluginId);
      PluginToolbarRegistry.instance.removeAll(event.pluginId);
      PluginShortcutRegistry.instance.removeAll(event.pluginId);
      PluginHighlightRegistry.instance.removePlugin(event.pluginId);
      PluginFileServer.instance.revokeAllForPlugin(event.pluginId);
      _removeSearchProviders(event.pluginId);
      // הרשימה נמחקת מה-DB באיפוס; בלי זה היא נשארת בזיכרון עד הפעלה מחדש.
      PluginLibraryBooksRegistry.instance.clearBooks(event.pluginId);
      await _cancelPluginNotifications(event.pluginId);
      await _installerService.resetPluginData(event.pluginId);
      _pluginCalendarEventsRemoved();
      PluginRuntimeDispatcher.instance.invalidatePlugin(event.pluginId);
      PluginNetworkPolicy.notifyChanged(event.pluginId);
      await PluginRuntimeDispatcher.instance.reloadPlugin(event.pluginId);
      add(LoadPlugins());
      UiSnack.show(PluginMessages.pluginDataReset(plugin.name));
    } catch (e) {
      UiSnack.showError(PluginMessages.resetPluginDataError(e));
    }
  }

  /// הטיוטות נמחקות רק בפעולה שהמשתמש אישר במפורש שהיא מוחקת אותן.
  Future<void> _endCorrectionSessions(
    String pluginId, {
    required bool deleteDrafts,
  }) async {
    final sessions = PluginCorrectionSessionService.instance;
    if (deleteDrafts) {
      await sessions.purgeOwner(pluginId);
    } else {
      sessions.removeOwner(pluginId);
    }
  }

  final CalendarAlertsClient? _alertsOverride;

  late final CalendarAlertsClient _alerts =
      _alertsOverride ?? CalendarAlertsClient.forCurrentWindow();

  /// מבטל אצל הבעלים את התראות המערכת שהתוסף תזמן. כשל זורק, כדי שהמזהים
  /// לא יימחקו עם שאר הנתונים לפני שההתראות בוטלו.
  Future<void> _cancelPluginNotifications(String pluginId) async {
    final ack = await _alerts.send('pluginCancelAll', {'pluginId': pluginId});
    if (!ack.ok) {
      throw StateError(ack.error ?? 'Plugin notifications were not cancelled');
    }
  }

  /// אירועי הלוח של התוסף נמחקו עם נתוניו; תזכורותיהם מבוטלות אצל הבעלים.
  void _pluginCalendarEventsRemoved() =>
      unawaited(_alerts.send('pluginEventsChanged'));

  Future<void> _onEnablePluginRequested(
    EnablePluginRequested event,
    Emitter<PluginSystemState> emit,
  ) async {
    if (PluginSafeMode.isActive) {
      await _saveChoiceInSafeMode(event.pluginId, enabled: true);
      return;
    }
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
    if (PluginSafeMode.isActive) {
      await _saveChoiceInSafeMode(event.pluginId, enabled: false);
      return;
    }
    try {
      _clearPluginRegistrations(event.pluginId);
      final plugin = await repository.getPlugin(event.pluginId);
      if (plugin != null) {
        await repository.savePlugin(plugin.copyWith(enabled: false));
        PluginNewTabPageRegistry.instance.remove(event.pluginId);
        PluginRuntimeDispatcher.instance.invalidatePlugin(event.pluginId);
        add(LoadPlugins());
      }
    } catch (e) {
      UiSnack.showError(PluginMessages.disablePluginError(e));
    }
  }

  /// Nothing loads or unloads in safe mode; only the user's choice is stored
  /// for the next normal start.
  Future<void> _saveChoiceInSafeMode(
    String pluginId, {
    required bool enabled,
  }) async {
    try {
      await repository.saveEnabledChoice(pluginId, enabled);
      UiSnack.show(PluginMessages.safeModeChoiceSaved(enabled: enabled));
      add(LoadPlugins());
    } catch (e) {
      UiSnack.showError(
        enabled
            ? PluginMessages.enablePluginError(e)
            : PluginMessages.disablePluginError(e),
      );
    }
  }

  void _clearPluginRegistrations(String pluginId) {
    PluginCorrectionSessionService.instance.removeOwner(pluginId);
    PluginTextReaderRegistry.instance.remove(pluginId);
    _removeDeclarative(pluginId);
    ContextMenuRegistry.instance.removeAll(pluginId);
    PluginToolbarRegistry.instance.removeAll(pluginId);
    PluginShortcutRegistry.instance.removeAll(pluginId);
    PluginHighlightRegistry.instance.removePlugin(pluginId);
    PluginFileServer.instance.revokeAllForPlugin(pluginId);
    _removeSearchProviders(pluginId);
    PluginLibraryBooksRegistry.instance.removePlugin(pluginId);
    PluginNewTabPageRegistry.instance.remove(pluginId);
    PluginSearchDialogRegistry.instance.removeAll(pluginId);
    PluginSearchFieldActionsRegistry.instance.removeAll(pluginId);
    PluginSearchFieldSessionService.instance.removePlugin(pluginId);
    PluginExternalEditionsRegistry.instance.removePlugin(pluginId);
    PluginLazyActivationService.instance.removePlugin(pluginId);
    PluginConditionEvaluator.instance.removePlugin(pluginId);
  }

  Future<void> _onSetPluginPermissionRequested(
    SetPluginPermissionRequested event,
    Emitter<PluginSystemState> emit,
  ) async {
    try {
      _removeDeclarative(event.pluginId);
      if (event.permission == pluginNewTabPagePermission && event.granted) {
        if (!await PluginNewTabPageService.instance.grant(
          event.pluginId,
          repository,
          expectedOwner: await PluginNewTabPageService.instance.ownerId(
            repository,
          ),
        )) {
          return;
        }
      } else {
        await repository.setPermission(
          event.pluginId,
          event.permission,
          event.granted,
        );
      }
      if (!event.granted) {
        if (event.permission == 'navigation.write' ||
            event.permission == pluginNewTabPagePermission) {
          PluginNewTabPageRegistry.instance.remove(event.pluginId);
        }
        if (event.permission == 'reader.local_edit') {
          PluginCorrectionSessionService.instance.removeOwner(event.pluginId);
        }
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
        if (event.permission == 'app.shortcuts') {
          PluginShortcutRegistry.instance.removeAll(event.pluginId);
        }
        if (event.permission == pluginSearchFieldActionsPermission) {
          PluginSearchFieldActionsRegistry.instance.removeAll(event.pluginId);
          PluginSearchFieldSessionService.instance.removePlugin(event.pluginId);
        }
        if (event.permission == 'reader.highlight') {
          PluginHighlightRegistry.instance.removePlugin(event.pluginId);
        }
        if (event.permission == pluginRunOnStartupPermission ||
            event.permission == pluginStartupContributionsPermission) {
          PluginLazyActivationService.instance.removePlugin(event.pluginId);
        }
      }
      PluginRuntimeDispatcher.instance.invalidatePlugin(event.pluginId);
      if (event.permission.startsWith('network.')) {
        PluginNetworkPolicy.notifyChanged(event.pluginId);
      }
      final grantedPermissions = await repository.getGrantedPermissionNames(
        event.pluginId,
      );
      // ההרשאות של התוסף הזה בלבד — לתוספים אחרים אין מה לדעת עליהן.
      PluginRuntimeDispatcher.instance.dispatchStateEventToPlugin(
        event.pluginId,
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
        if (!manifest.permissions.contains('navigation.write')) {
          PluginNewTabPageRegistry.instance.remove(manifest.id);
        }
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
      PluginCorrectionSessionService.instance.removeOwner(event.pluginId);
      _removeDeclarative(event.pluginId);
      ContextMenuRegistry.instance.removeAll(event.pluginId);
      PluginToolbarRegistry.instance.removeAll(event.pluginId);
      PluginHighlightRegistry.instance.removePlugin(event.pluginId);
      _removeSearchProviders(event.pluginId);
      PluginNewTabPageRegistry.instance.remove(event.pluginId);
      PluginFileServer.instance.revokeAllForPlugin(event.pluginId);
      await repository.detachDevelopmentPlugin(event.pluginId);
      PluginNewTabPageRegistry.instance.remove(event.pluginId);
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

  /// תוסף פיתוח שה-manifest שלו נערך כשהתוכנה הייתה סגורה — ה-watcher לא היה
  /// שם כדי לרענן את הרשומה, והגרסה שנשמרה נשארת תקועה. כאן משווים את הגרסה
  /// שבקובץ לזו שברשומה, ומעדכנים דרך אותו נתיב של ה-watcher.
  ///
  /// עלות בעלייה: שאילתה שכבר נעשית ל-`syncWatchers`, ואם אין תוספי פיתוח —
  /// שום קריאת קבצים. הכשל בכל תוסף נבלע בנפרד: תיקייה שנעלמה או manifest
  /// שנשבר באמצע עריכה אינם אמורים להפיל את הסריקה על השאר.
  Future<void> _onRescanDevelopmentManifests(
    RescanDevelopmentManifests event,
    Emitter<PluginSystemState> emit,
  ) async {
    // הרשומה משותפת לכל החלונות; חלון משני היה כותב אותה שוב על אותם נתונים.
    if (!_isProcessOwner) return;
    final devPlugins = await repository.getDevelopmentPlugins();
    for (final plugin in devPlugins) {
      // localhost_dev נטען מ-HTTP (HMR) ואין לו תיקייה לקרוא ממנה.
      if (plugin.isLocalhostDev) continue;
      final devRootPath = plugin.devRootPath;
      if (devRootPath == null) continue;
      try {
        final file = File(path.join(devRootPath, 'manifest.json'));
        if (!await file.exists()) continue;
        final json = jsonDecode(await file.readAsString());
        final version = json is Map ? json['version'] : null;
        if (version is! String || version == plugin.version) continue;
        add(DevelopmentPluginManifestChanged(plugin.pluginId));
      } catch (error) {
        debugPrint(
          'Plugin dev manifest rescan [${plugin.pluginId}]: $error',
        );
      }
    }
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
        );
      } else {
        await devLoader.loadDevelopmentPlugin(
          event.sourcePath,
          preValidatedManifest: event.manifest,
          grantedPermissions: event.grantedPermissions,
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

/// כמו [sequential], אבל בקשות טעינה מתמזגות ומתחילות בתור הבא של לולאת
/// האירועים: פעולה גורפת על N תוספים ביקשה N טעינות מלאות ברצף (#3688).
EventTransformer<E> _sequentialCoalesced<E extends Object>() =>
    (events, mapper) {
      late final StreamController<E> out;
      StreamSubscription<E>? input;
      StreamSubscription<E>? running;
      Timer? scheduled;
      E? pending;
      var inputDone = false;

      void start() {
        scheduled = Timer(Duration.zero, () {
          scheduled = null;
          final event = pending!;
          pending = null;
          running = mapper(event).listen(
            out.add,
            onError: out.addError,
            onDone: () {
              running = null;
              if (pending != null) {
                start();
              } else if (inputDone) {
                out.close();
              }
            },
          );
        });
      }

      out = StreamController<E>(
        onListen: () => input = events.listen(
          (event) {
            pending = event;
            if (running == null && scheduled == null) start();
          },
          onError: out.addError,
          onDone: () {
            inputDone = true;
            if (running == null && scheduled == null) out.close();
          },
        ),
        onCancel: () async {
          scheduled?.cancel();
          await running?.cancel();
          await input?.cancel();
        },
      );
      return out.stream;
    };
