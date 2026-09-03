import 'package:otzaria/bookmarks/bloc/bookmark_bloc.dart';
import 'package:otzaria/settings/services/custom_folders/bloc/custom_folders_bloc.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_inappwebview_windows/flutter_inappwebview_windows.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/core/connectivity_status_service.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/services/plugin_manifest_validator.dart';
import 'package:otzaria/plugins/bridge/plugin_bridge_handler.dart';
import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:collection';
import 'package:path/path.dart' as p;
import 'package:otzaria/plugins/services/plugin_page_launcher.dart';
import 'package:otzaria/plugins/services/plugin_ref_line_resolver.dart';
import 'package:otzaria/plugins/services/plugin_runtime_dispatcher.dart';
import 'package:otzaria/plugins/storage/plugin_system_database.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:otzaria/plugins/bridge/plugin_bridge_adapter.dart';
import 'package:otzaria/tools/calendar/utils/calendar_cubit.dart';
import 'package:otzaria/search/search_repository.dart';
import 'package:otzaria/personal_notes/repository/personal_notes_repository.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/view/main_window_screen.dart';
import 'package:otzaria/workspaces/bloc/workspace_bloc.dart';
import 'package:otzaria/find_ref/repository/find_ref_factory.dart';
import 'package:otzaria/find_ref/repository/find_ref_repository.dart';
import 'package:otzaria/utils/navigation/book_open_coordinator.dart';
import 'package:file_picker/file_picker.dart';
import 'package:otzaria/utils/file/file_picker_dialog_options.dart';
import 'package:otzaria/settings/services/safer_mode_guard.dart';
import 'package:otzaria/widgets/dialogs/dialogs_exports.dart';
import 'package:otzaria/widgets/misc/middle_click_autoscroll.dart';
import 'package:otzaria/plugins/view/plugin_dev_error_view.dart';
import 'package:otzaria/plugins/view/webview_environment_holder.dart';
import 'package:otzaria/plugins/bloc/plugin_system_bloc.dart';
import 'package:otzaria/plugins/bloc/plugin_system_event.dart';
import 'package:otzaria/plugins/services/plugin_crash_guard.dart';
import 'package:otzaria/plugins/services/plugin_deep_link_policy.dart';
import 'package:otzaria/plugins/services/plugin_webview_failure_log.dart';
import 'package:otzaria/plugins/services/plugin_network_gate.dart';
import 'package:otzaria/plugins/view/plugin_crashed_view.dart';
import 'package:otzaria/plugins/view/plugin_data_folder_unwritable_view.dart';
import 'package:otzaria/plugins/view/plugin_webview2_missing_view.dart';
import 'package:otzaria/plugins/view/plugin_webview_failed_view.dart';
import 'package:otzaria/plugins/services/windows_arch_info.dart';
import 'package:otzaria/plugins/view/plugin_drop_guard_script.dart';
import 'package:otzaria/plugins/view/plugin_linkify_script.dart';
import 'package:otzaria/plugins/services/plugin_file_server.dart';
import 'package:otzaria/plugins/services/plugin_download_handler.dart';
import 'package:otzaria/plugins/services/plugin_webview_permission_gate.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/utils/ui/fullscreen_helper.dart';

// ---------------------------------------------------------------------------
// Stub SDK — injected at AT_DOCUMENT_START before any page JS runs.
// Queues all Otzaria.on() calls so they survive the async boot gap.
// ---------------------------------------------------------------------------
const String _sdkStub = r'''
(function () {
  var _queue = [];
  var _realSdk = null;
  var _notReadyStream = function () {
    return {
      next: function () {
        return Promise.reject(new Error('Otzaria SDK not ready yet'));
      },
      [Symbol.asyncIterator]: function () { return this; }
    };
  };

  window.Otzaria = {
    call: function (method, payload) {
      if (_realSdk) return _realSdk.call(method, payload);
      if (method === 'search.query' || method === 'network.fetchStream') {
        return _notReadyStream();
      }
      return Promise.reject(new Error('Otzaria SDK not ready yet'));
    },
    on: function (event, cb) {
      if (_realSdk) { _realSdk.on(event, cb); }
      else { _queue.push({ event: event, cb: cb }); }
    },
    off: function (event, cb) {
      if (_realSdk) _realSdk.off(event, cb);
    },
    /* Called by Flutter once the real SDK + boot payload are ready */
    _boot: function (sdk, payload) {
      _realSdk = sdk;
      // סמן חיוּת לדיספצ'ר: קיים רק ב-context שבו התוסף באמת רץ. context
      // טרי שנוצר אחרי השמדת ה-platform view מקבל את ה-stub מחדש אך לא את
      // ה-boot — והיעדר הדגל מזוהה בפינג ומפעיל reload.
      window.Otzaria._booted = true;
      // Re-register all listeners that were queued before boot
      _queue.forEach(function (item) { sdk.on(item.event, item.cb); });
      _queue = [];
      window.dispatchEvent(new CustomEvent('plugin.boot', { detail: payload }));
      window.dispatchEvent(new CustomEvent('plugin.ready', { detail: null }));
    }
  };

  // Block window.open for security
  window.open = function () {
    console.error('window.open is locked for security.');
    return null;
  };

  // מקשי מקלדת נבלעים ב-WebView ולא מגיעים ל-Flutter — מעבירים ESC לאפליקציה
  // (יציאה ממסך מלא).
  window.addEventListener('keydown', function (e) {
    if (e.key === 'Escape' && window.flutter_inappwebview) {
      window.flutter_inappwebview.callHandler('otzaria_escape_pressed');
    }
  }, true);
})();
''';

/// האם אירוע כשל היצירה שייך לטאב הזה.
@visibleForTesting
bool shouldHandleCreationFailure({
  required Key? failureKey,
  required Key expectedKey,
  required String? failureUrl,
  required String expectedUrl,
  required bool isCreated,
  required bool alreadyFailed,
}) {
  if (isCreated || alreadyFailed) return false;
  if (failureKey != null) return failureKey == expectedKey;
  if (failureUrl == null || failureUrl.isEmpty) return true;
  return failureUrl == expectedUrl;
}

InAppWebViewSettings buildPluginTabWebViewSettings({
  required bool isDevelopment,
}) {
  return InAppWebViewSettings(
    allowFileAccessFromFileURLs: false,
    allowUniversalAccessFromFileURLs: false,
    useShouldOverrideUrlLoading: true,
    useShouldInterceptRequest: true,
    useOnDownloadStart: PluginDownloadHandler.isSupported,
    // ב-Windows ה-status bar של WebView2 מציג את ה-URI בריחוף על קישור
    // ומאפשר לתוסף לכתוב לשם טקסט חופשי (window.status).
    statusBarEnabled: false,
    // זום (צביטת מגע / Ctrl+גלגלת) משנה את סקאלת התוסף בלי דרך גלויה
    // לאיפוס — לכן חסום.
    supportZoom: false,
    pinchZoomEnabled: false,
    cacheEnabled: !isDevelopment,
    isInspectable: isDevelopment || kDebugMode,
  );
}

class PluginTabPage extends StatefulWidget {
  final InstalledPlugin plugin;

  /// מזהה המופע של הטאב (ToolTab.instanceId) — מזהה את הרישום של הדף הזה
  /// אצל PluginRuntimeDispatcher, לצד מופעים נוספים של אותו תוסף.
  final String instanceId;

  const PluginTabPage({
    super.key,
    required this.plugin,
    required this.instanceId,
  });

  @override
  State<PluginTabPage> createState() => _PluginTabPageState();
}

/// תוצאת בדיקת התנאים המוקדמים ל-WebView לפני הצגת התוסף.
enum _WebViewPrereqStatus {
  /// סביבת ה-WebView מוכנה — אפשר לבנות את ה-WebView.
  ready,

  /// WebView2 Runtime אינו מותקן (Windows) — יש להציג מסך הכוונה להתקנה.
  runtimeMissing,

  /// תיקיית הנתונים של WebView2 חסומה לכתיבה — יש להציג הסבר במקום לתת
  /// ל-WebView2 להעלות דיאלוג מערכת של Edge.
  dataFolderNotWritable,
}

class _PluginTabPageState extends State<PluginTabPage> {
  // future של בדיקת התנאים המוקדמים. שמור ברמת המופע (לא static) כדי
  // שכפתור "בדוק שוב" יוכל לאפסו (setState(() => _prereqFuture = null))
  // ולהריץ בדיקה מחדש לאחר שהמשתמש התקין את WebView2.
  Future<_WebViewPrereqStatus>? _prereqFuture;

  InAppWebViewController? webViewController;
  late String localHtmlPath;

  /// נבדק פעם אחת ולא בכל build: existsSync בכל פריים resize הוא I/O סינכרוני,
  /// וכשל חולף אחד (נעילת אנטי-וירוס) היה מפיל את ה-WebView וטוען אותו מאפס.
  late bool _entrypointMissing;

  /// צורת העץ של build ננעלת לכל חיי ה-State: מעבר FutureBuilder ↔ ישיר
  /// היה מייצר הורה חדש ל-WebView והורס אותו.
  late final bool _usePrereqGate = _needsWebViewPrerequisites;

  /// GlobalKey ל-InAppWebView — שורד החלפת הורה באותו פריים בלי טעינה מחדש.
  final GlobalKey _webViewKey = GlobalKey();
  late final PluginBridgeHandler _bridge;
  late final PluginBridgeAdapter _adapter;
  late final PluginRegistryRepository _pluginRegistryRepository;
  late final PluginSystemBloc _pluginSystemBloc;
  late final FindRefRepository _findRefRepository;
  bool _hasError = false;
  String? _devErrorMessage;

  // כשל יצירה native לא מפעיל אף callback ב-Dart — נשאר רק מסך ריק.
  // השעון נדרך בבניית ה-WebView ומבוטל ב-onWebViewCreated, כדי לרשום ללוג.
  Timer? _creationWatchdog;

  // כשל היצירה מגיע מהפלאגין כאירוע גלובלי (אין callback על ה-widget).
  StreamSubscription<WindowsWebViewCreationFailure>? _creationFailureSub;
  String? _creationFailure;

  // Cache PackageInfo so the async gap in onLoadStop never crosses a dispose
  static PackageInfo? _cachedPackageInfo;

  @override
  void initState() {
    super.initState();
    _pluginSystemBloc = context.read<PluginSystemBloc>();
    // For localhost_dev the dev server root IS the entrypoint (e.g. http://localhost:5173/).
    // The manifest entrypoint (e.g. dist/index.html) is the production-build path only.
    localHtmlPath = widget.plugin.isLocalhostDev
        ? widget.plugin.devRootPath!.replaceAll(RegExp(r'/+$'), '')
        : '${widget.plugin.resolvedRootPath}/${widget.plugin.entrypointPath}';
    _entrypointMissing =
        !widget.plugin.isLocalhostDev && !File(localHtmlPath).existsSync();
    final historyBloc = context.read<HistoryBloc>();
    final tabsBloc = context.read<TabsBloc>();
    final navigationBloc = context.read<NavigationBloc>();
    final calendarCubit = context.read<CalendarCubit>();
    final workspaceBloc = context.read<WorkspaceBloc>();
    final bookmarkBloc = context.read<BookmarkBloc>();
    final customFoldersBloc = context.read<CustomFoldersBloc>();
    final libraryBloc = context.read<LibraryBloc>();
    final searchRepository = SearchRepository();
    final personalNotesRepository = PersonalNotesRepository();
    final pluginRegistryRepository = PluginRegistryRepository();
    _findRefRepository = buildFindRefRepository();
    final findRefRepository = _findRefRepository;

    final dependencies = PluginBridgeDependencies(
      historyBloc: historyBloc,
      tabsBloc: tabsBloc,
      navigationBloc: navigationBloc,
      calendarCubit: calendarCubit,
      workspaceBloc: workspaceBloc,
      bookmarkBloc: bookmarkBloc,
      customFoldersBloc: customFoldersBloc,
      waitForLibraryRefresh: (requestId) async {
        final state = await libraryBloc.stream.firstWhere(
          (state) =>
              state.completedRefreshRequestIds?.contains(requestId) == true ||
              (!state.isLoading && state.error != null),
        );
        if (state.completedRefreshRequestIds?.contains(requestId) != true) {
          throw StateError(state.error!);
        }
      },
      searchRepository: searchRepository,
      personalNotesRepository: personalNotesRepository,
      bookOpenCoordinator: BookOpenCoordinator(
        tabsBloc: tabsBloc,
        historyBloc: historyBloc,
        navigationBloc: navigationBloc,
      ),
      resolveReference: (reference) async {
        final results = await findRefRepository.findRefs(reference);
        return results
            .map(
              (r) => (title: r.title, index: r.segment.toInt(), isPdf: r.isPdf),
            )
            .toList();
      },
      resolveRefToLine: (book, ref) =>
          PluginRefLineResolver().resolve(book: book, ref: ref),
      themePayloadBuilder: () {
        if (!mounted) {
          return {
            'mode': 'light',
            'colorScheme': <String, dynamic>{},
            'typography': <String, dynamic>{},
          };
        }
        return buildThemePayload(context);
      },
      showConfirmDialog:
          ({
            required String title,
            required String content,
          }) async {
            if (!mounted) return false;
            return await showTwoActionsDialog(
                  context: context,
                  title: title,
                  content: content,
                  cancelText: 'ביטול',
                  confirmText: 'אישור',
                ) ==
                true;
          },
      showWarningDialog:
          ({
            required String title,
            required String content,
            required String subtitle,
          }) async {
            if (!mounted) return false;
            return await showWarningDialog(
                  context: context,
                  title: title,
                  content: content,
                  subtitle: subtitle,
                  cancelText: 'ביטול',
                  confirmText: 'המשך',
                ) ==
                true;
          },
      requestPluginInstall: (downloadUrl, {reportContext}) {
        _pluginSystemBloc.add(
          InstallRemotePluginRequested(
            downloadUrl,
            reportContext: reportContext,
            storeOnly: true,
          ),
        );
      },
      pickFolder: ({String? title}) async {
        if (!mounted) return null;
        if (!await verifySaferModePassword(context)) return null;
        if (!mounted) return null;
        return FilePicker.getDirectoryPath(
          windowsOptions: kModalWindowsOptions,
          linuxOptions: kModalLinuxOptions,
          dialogTitle: title,
        );
      },
      pickFile: ({List<String>? allowedExtensions, String? title}) async {
        if (!mounted) return null;
        if (!await verifySaferModePassword(context)) return null;
        if (!mounted) return null;
        final hasExtensions =
            allowedExtensions != null && allowedExtensions.isNotEmpty;
        final result = await FilePicker.pickFile(
          dialogTitle: title,
          windowsOptions: kModalWindowsOptions,
          linuxOptions: kModalLinuxOptions,
          type: hasExtensions ? FileType.custom : FileType.any,
          allowedExtensions: hasExtensions ? allowedExtensions : null,
        );
        return result?.path;
      },
    );

    _pluginRegistryRepository = pluginRegistryRepository;
    _adapter = PluginBridgeAdapter(
      widget.plugin,
      dependencies: dependencies,
      instanceId: widget.instanceId,
      pluginRepository: pluginRegistryRepository,
    );
    _bridge = PluginBridgeHandler(
      widget.plugin,
      adapter: _adapter,
      registry: pluginRegistryRepository,
    );
    // Pre-fetch so onLoadStop has no async gap
    _ensurePackageInfo();

    PluginRuntimeDispatcher.instance.registerReloadCallback(
      widget.plugin.pluginId,
      _reloadFromDisk,
      instanceId: widget.instanceId,
      token: this,
    );
  }

  Future<void> _reloadFromDisk() async {
    if (!mounted) return;
    if (!widget.plugin.isDevelopment) return;

    // במסך שגיאה ה-WebView ירד מהעץ וה-controller מת — ניקוי הדגל בונה
    // WebView חדש שטוען מחדש את נקודת הכניסה, במקום reload על controller מת.
    if (_hasError) {
      setState(() => _hasError = false);
      return;
    }

    // localhost_dev: HMR handles JS/CSS changes automatically.
    // A manual reload clears the cache and reloads the page.
    if (widget.plugin.isLocalhostDev) {
      // במסך שגיאת חיבור אין WebView חי (ה-controller מת) — ניקוי השגיאה בונה
      // WebView חדש שטוען את כתובת השרת מחדש, במקום reload על controller מת.
      if (_devErrorMessage != null) {
        setState(() => _devErrorMessage = null);
        return;
      }
      try {
        await InAppWebViewController.clearAllCache();
      } catch (_) {}
      await webViewController?.reload();
      return;
    }

    try {
      await _ensurePackageInfo();
      final manifestFile = File(
        p.join(widget.plugin.resolvedRootPath, 'manifest.json'),
      );
      if (!manifestFile.existsSync()) {
        setState(() => _devErrorMessage = 'קובץ manifest.json חסר בתיקייה.');
        return;
      }
      final manifestStr = await manifestFile.readAsString();
      final manifestJson = jsonDecode(manifestStr);

      // Perform strict manifest validation
      final manifest = PluginManifest.fromJson(manifestJson);

      // תוסף פיתוח פטור מבדיקת תאימות גרסה — כמו במסלול הטעינה
      // (PluginDevLoaderService), כדי לאפשר בדיקה מול גרסאות עתידיות.
      await PluginManifestValidator.validateManifest(
        manifest: manifest,
        directoryPath: widget.plugin.resolvedRootPath,
        skipAppVersionValidation: true,
      );

      if (manifest.id != widget.plugin.pluginId) {
        setState(
          () => _devErrorMessage =
              'מזהה התוסף (id) השתנה.\nמצופה: ${widget.plugin.pluginId}\nנמצא: ${manifest.id}\nשינוי ID דורש התקנה מחדש.',
        );
        return;
      }

      setState(() => _devErrorMessage = null);

      try {
        await InAppWebViewController.clearAllCache();
      } catch (_) {}

      localHtmlPath = p.join(
        widget.plugin.resolvedRootPath,
        manifest.entrypoint,
      );
      _entrypointMissing = !File(localHtmlPath).existsSync();
      await webViewController?.loadUrl(
        urlRequest: URLRequest(url: WebUri.uri(Uri.file(localHtmlPath))),
      );
    } catch (e) {
      if (mounted) {
        setState(
          () => _devErrorMessage = 'שגיאה בלתי צפויה בריענון התוסף: $e',
        );
      }
    }
  }

  void _onCreationFailure(WindowsWebViewCreationFailure failure) {
    if (!mounted ||
        !shouldHandleCreationFailure(
          failureKey: failure.creationKey,
          expectedKey: _webViewKey,
          failureUrl: failure.requestedUrl,
          expectedUrl: _expectedCreationUrl(),
          isCreated: webViewController != null,
          alreadyFailed: _creationFailure != null,
        )) {
      return;
    }
    _creationWatchdog?.cancel();
    _creationWatchdog = null;
    logPluginWebViewFailure(
      'Plugin WebView creation failed',
      failure.error,
      stackTrace: failure.stackTrace,
      details: {
        'Plugin': widget.plugin.pluginId,
        'EmulatedOnArm': WindowsArchInfo.isEmulatedOnArm ? 'true' : 'false',
      },
    );
    setState(() => _creationFailure = failure.error.toString());
  }

  /// ה-URL שהטאב הזה ביקש ליצור — מפתח ההתאמה מול אירוע כשל.
  String _expectedCreationUrl() => widget.plugin.isLocalhostDev
      ? WebUri(localHtmlPath).toString()
      : WebUri.uri(Uri.file(localHtmlPath)).toString();

  Future<void> _ensurePackageInfo() async {
    _cachedPackageInfo ??= await PackageInfo.fromPlatform();
  }

  @override
  void dispose() {
    _findRefRepository.dispose();
    // dispose = unmount רגיל (סגירת טאב) בזמן שהתהליך חי — לא קריסה, מנקים
    // את ה-canary. סגירת האפליקציה לא מריצה dispose; אותה מכסה
    // PluginCrashGuard.markCleanShutdownSync ב-onWindowClose.
    PluginCrashGuard.markLoadSuccessSync(
      widget.plugin.pluginId,
      owner: widget.instanceId,
    );
    _creationWatchdog?.cancel();
    unawaited(_creationFailureSub?.cancel());
    final pluginId = widget.plugin.pluginId;
    final instanceId = widget.instanceId;
    final controller = webViewController;
    // העץ נעול בזמן dispose וניקוי הרישומים מודיע ל-ListenableBuilders
    // (הדגשות, סרגל כלים) — לכן נדחה למיקרוטסק, אחרי שחרור הנעילה.
    scheduleMicrotask(() {
      _adapter.dispose();
      // ביטול הרישום רק אם הדף הזה עדיין הבעלים. עדכון תוסף משנה את ה-key,
      // ו-initState של הדף החדש רץ *לפני* ה-dispose של הישן — בלי הבדיקה
      // הישן היה מוחק את הרישום של החדש ומשתיק אותו.
      if (PluginRuntimeDispatcher.instance.ownsController(
        pluginId,
        controller,
        instanceId: instanceId,
      )) {
        PluginPageLauncher.instance.markPageClosed(
          pluginId,
          instanceId: instanceId,
        );
        PluginRuntimeDispatcher.instance.unregisterController(
          pluginId,
          instanceId: instanceId,
        );
      }
      PluginRuntimeDispatcher.instance.unregisterReloadCallback(
        pluginId,
        instanceId: instanceId,
        token: this,
      );
    });
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.plugin.enabled) {
      return Center(
        child: Text(
          'התוסף כבוי על ידי המשתמש ולא ניתן להציגו.',
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      );
    }

    if (_devErrorMessage != null) {
      return PluginDevErrorView(
        plugin: widget.plugin,
        errorMessage: _devErrorMessage!,
      );
    }

    if (_hasError) {
      return Center(child: Text('שגיאה בטעינת הקובץ: $localHtmlPath'));
    }

    if (_entrypointMissing) {
      return const SizedBox.shrink(); // התוסף כבר הוסר — הטאב ייסגר בקרוב
    }

    // אם בהפעלה הקודמת התוסף הזה הקריס את התוכנה (נשאר ב-PluginCrashGuard),
    // אנחנו לא טוענים אותו אוטומטית — מציגים מסך הסבר עם כפתור "נסה שוב".
    // כשהבאג יתוקן (upstream או דרך עדכון WebView2), הטעינה הראשונה
    // המוצלחת תקרא ל-markLoadSuccess ותסיר את הסימון לבד.
    if (PluginCrashGuard.isBlocked(widget.plugin.pluginId)) {
      return PluginCrashedView(
        pluginId: widget.plugin.pluginId,
        pluginName: widget.plugin.name,
        onRetry: () {
          if (mounted) setState(() {});
        },
      );
    }

    if (_usePrereqGate) {
      return FutureBuilder<_WebViewPrereqStatus>(
        future: _prereqFuture ??= _resolveWebViewPrerequisites(),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const SizedBox.shrink();
          }
          if (snapshot.hasError) {
            debugPrint('WebView prerequisites init error: ${snapshot.error}');
            return Center(
              child: Text(
                'שגיאה באתחול סביבת הדפדפן: ${snapshot.error}',
              ),
            );
          }
          if (snapshot.data == _WebViewPrereqStatus.dataFolderNotWritable) {
            return PluginDataFolderUnwritableView(
              folderPath: WebViewEnvironmentHolder.unwritableDataFolder ?? '',
              onRetry: () {
                if (!mounted) return;
                setState(() => _prereqFuture = null);
              },
            );
          }
          if (snapshot.data == _WebViewPrereqStatus.runtimeMissing) {
            return PluginWebView2MissingView(
              onRetry: () {
                if (!mounted) return;
                // מרעננים גם את מערכת התוספים: אם WebView2 הותקן בינתיים,
                // RefreshPlugins יגרום לסנכרון מחדש של ה-background host כך
                // שתוספי run_on_startup יחזרו לרוץ — בלי הפעלה מחדש.
                _pluginSystemBloc.add(RefreshPlugins());
                setState(() => _prereqFuture = null);
              },
            );
          }
          return _buildWebView();
        },
      );
    }

    return _buildWebView();
  }

  // Allows only the exact dev server origin (host + scheme + port) to prevent
  // unintended access to other localhost services running on different ports.
  bool _isDevServerUri(Uri uri) {
    final devUri = Uri.tryParse(widget.plugin.devRootPath ?? '');
    if (devUri == null) return false;
    final reqHost = uri.host.toLowerCase();
    final devHost = devUri.host.toLowerCase();
    const localhosts = {'localhost', '127.0.0.1', '::1'};
    if (!localhosts.contains(reqHost) || reqHost != devHost) return false;
    if (uri.scheme != devUri.scheme) return false;
    final devPort = devUri.hasPort
        ? devUri.port
        : (devUri.scheme == 'https' ? 443 : 80);
    final reqPort = uri.hasPort ? uri.port : (uri.scheme == 'https' ? 443 : 80);
    return reqPort == devPort;
  }

  /// משגר קישור `otzaria://` שנלחץ בדף התוסף — רק בלחיצת משתמש אמיתית.
  Future<void> _dispatchPluginDeepLink(
    Uri uri,
    NavigationAction navigationAction,
  ) async {
    final target = PluginDeepLinkPolicy.dispatchUriForUserNavigation(
      uri,
      navigationAction,
    );
    if (target == null) return;
    await mainWindowScreenKey.currentState?.handleInternalDeepLink(
      target.toString(),
    );
  }

  Future<bool> _isNetworkUriAllowed(Uri uri) => isPluginNetworkAccessAllowed(
    uri: uri,
    pluginId: widget.plugin.pluginId,
    manifest: widget.plugin.manifest,
    registry: _pluginRegistryRepository,
  );

  Widget _buildWebView() {
    if (_creationFailure != null) {
      return PluginWebViewFailedView(
        pluginName: widget.plugin.name,
        errorDetails: _creationFailure,
        isEmulatedOnArm: WindowsArchInfo.isEmulatedOnArm,
        onRetry: () {
          if (!mounted) return;
          setState(() => _creationFailure = null);
        },
      );
    }

    if (_creationWatchdog == null && webViewController == null) {
      _creationWatchdog = Timer(const Duration(seconds: 20), () {
        logPluginWebViewFailure(
          'Plugin WebView never created (silent blank)',
          'onWebViewCreated did not fire within 20s',
          details: {'Plugin': widget.plugin.pluginId},
        );
      });
      _creationFailureSub ??= WindowsWebViewCreationFailures.stream.listen(
        _onCreationFailure,
      );
    }
    final initialUrl = widget.plugin.isLocalhostDev
        ? WebUri(localHtmlPath)
        : WebUri.uri(Uri.file(localHtmlPath));

    final webView = InAppWebView(
      key: _webViewKey,
      webViewEnvironment: WebViewEnvironmentHolder.environment,
      initialUrlRequest: URLRequest(url: initialUrl),
      initialSettings: buildPluginTabWebViewSettings(
        isDevelopment: widget.plugin.isDevelopment,
      ),
      // Stub SDK — injected BEFORE any page JS runs
      initialUserScripts: UnmodifiableListView<UserScript>([
        UserScript(
          source: _sdkStub,
          injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
        ),
        buildPluginDropGuardScript(),
        buildPluginLinkifyScript(auto: widget.plugin.manifest.autoLinkify),
      ]),
      onWebViewCreated: (controller) {
        _creationWatchdog?.cancel();
        unawaited(_creationFailureSub?.cancel());
        _creationFailureSub = null;
        // מסמנים שמתחיל ניסיון טעינה. שימוש בגרסה הסינכרונית מבטיח שהקובץ
        // מתעדכן מיד (לפני שיש הזדמנות ל-dispose לרוץ ולנקות ריק) — אחרת
        // קיים race שבו סגירה מהירה של הטאב לפני שה-Future של ה-async
        // markLoadAttempt הספיק להוסיף לזיכרון, מוביל ל-canary שגוי.
        // הסימון נשאר ב-disk **רק** אם התהליך מת native לפני שהגענו
        // לאחד מנתיבי הסיום ב-Dart (catch / success / dispose).
        PluginCrashGuard.markLoadAttemptSync(
          widget.plugin.pluginId,
          owner: widget.instanceId,
        );
        try {
          webViewController = controller;
          PluginRuntimeDispatcher.instance.registerController(
            widget.plugin.pluginId,
            controller,
            instanceId: widget.instanceId,
          );
          _bridge.register(controller);
          controller.addJavaScriptHandler(
            handlerName: 'otzaria_escape_pressed',
            callback: (_) {
              if (!mounted) return;
              if (context.read<SettingsBloc>().state.isFullscreen) {
                FullscreenHelper.toggleFullscreen(context, false);
              }
            },
          );
        } catch (e) {
          // bridge.register נכשל — התהליך חי, לא קריסה native. מנקים גם את
          // ה-registration הלא שלם וגם את ה-canary של ה-crash guard.
          PluginRuntimeDispatcher.instance.unregisterController(
            widget.plugin.pluginId,
            instanceId: widget.instanceId,
          );
          unawaited(
            PluginCrashGuard.markLoadSuccess(
              widget.plugin.pluginId,
              owner: widget.instanceId,
            ),
          );
          debugPrint(
            'Plugin [${widget.plugin.pluginId}] WebView init error: $e',
          );
          if (mounted) setState(() => _hasError = true);
        }
      },
      onDownloadStarting: PluginDownloadHandler.onDownloadStarting,
      onPermissionRequest: (controller, request) =>
          PluginWebViewPermissionGate.respond(
            plugin: widget.plugin,
            request: request,
            registry: _pluginRegistryRepository,
          ),
      // WebView2 מריץ otzaria:// דרך מטפל הפרוטוקול של המערכת אם האירוע אינו
      // מבוטל — עקיפה של המדיניות כאן. הביטול הוא רשת ביטחון בלבד: ההחלטה
      // מתקבלת ב-shouldOverrideUrlLoading, שנורה לפניו.
      onLaunchingExternalUriScheme: (controller, request) async =>
          LaunchingExternalUriSchemeResponse(cancel: true),
      shouldOverrideUrlLoading: (controller, navigationAction) async {
        try {
          final uri = navigationAction.request.url;
          if (uri == null) return NavigationActionPolicy.CANCEL;

          if (uri.scheme == 'otzaria') {
            await _dispatchPluginDeepLink(uri, navigationAction);
            return NavigationActionPolicy.CANCEL;
          }

          if (uri.scheme == 'file') {
            final normalizedUri = p.normalize(uri.toFilePath());
            final normalizedInstall = p.normalize(
              widget.plugin.resolvedRootPath,
            );
            if (p.isWithin(normalizedInstall, normalizedUri) ||
                normalizedUri == normalizedInstall) {
              return NavigationActionPolicy.ALLOW;
            }
          } else if (uri.scheme == 'data' ||
              uri.scheme == 'blob' ||
              uri.scheme == 'about') {
            return NavigationActionPolicy.ALLOW;
          }

          if ((uri.scheme == 'http' || uri.scheme == 'https') &&
              widget.plugin.isLocalhostDev &&
              _isDevServerUri(uri)) {
            return NavigationActionPolicy.ALLOW;
          }

          // שרת הקבצים הפנימי (loopback). זו נקודת האכיפה היחידה של בידוד בין
          // תוספים — השרת אינו יכול לזהות מי הפונה.
          if (uri.scheme == 'http' &&
              PluginFileServer.instance.isServerUri(uri)) {
            return PluginFileServer.isUriForPlugin(uri, widget.plugin.pluginId)
                ? NavigationActionPolicy.ALLOW
                : NavigationActionPolicy.CANCEL;
          }

          if (uri.scheme == 'http' || uri.scheme == 'https') {
            if (await _isNetworkUriAllowed(uri)) {
              return NavigationActionPolicy.ALLOW;
            }
          }

          return NavigationActionPolicy.CANCEL;
        } catch (e) {
          debugPrint(
            'Plugin [${widget.plugin.pluginId}] URL override error: $e',
          );
          return NavigationActionPolicy.CANCEL;
        }
      },
      shouldInterceptRequest: (controller, request) async {
        try {
          final uri = request.url;
          if (uri.scheme == 'file') {
            final normalizedUri = p.normalize(uri.toFilePath());
            final normalizedInstall = p.normalize(
              widget.plugin.resolvedRootPath,
            );
            if (!p.isWithin(normalizedInstall, normalizedUri) &&
                normalizedUri != normalizedInstall) {
              return WebResourceResponse(
                statusCode: 403,
                reasonPhrase: 'Forbidden',
              );
            }
          }
          if ((uri.scheme == 'http' || uri.scheme == 'https') &&
              widget.plugin.isLocalhostDev &&
              _isDevServerUri(uri)) {
            return null; // allow all localhost requests for localhost_dev
          }
          // שרת הקבצים הפנימי (loopback). זו נקודת האכיפה היחידה של בידוד בין
          // תוספים — השרת אינו יכול לזהות מי הפונה.
          if (uri.scheme == 'http' &&
              PluginFileServer.instance.isServerUri(uri)) {
            if (PluginFileServer.isUriForPlugin(uri, widget.plugin.pluginId)) {
              return null;
            }
            return WebResourceResponse(
              statusCode: 403,
              reasonPhrase: 'Forbidden',
            );
          }
          if (uri.scheme == 'http' || uri.scheme == 'https') {
            if (await _isNetworkUriAllowed(uri)) {
              return null;
            }
            return WebResourceResponse(
              statusCode: 403,
              reasonPhrase: 'Forbidden',
            );
          }
          return null;
        } catch (e) {
          debugPrint(
            'Plugin [${widget.plugin.pluginId}] intercept request error: $e',
          );
          return WebResourceResponse(
            statusCode: 403,
            reasonPhrase: 'Forbidden',
          );
        }
      },
      onLoadStop: (controller, url) async {
        try {
          // לוכד theme לפני ה-await (context חייב להישמר synchronously)
          final theme = buildThemePayload(context);

          // טוען CSS עם @font-face לגופנים המובנים, כדי שה-WebView
          // יוכל לפענח שמות כמו 'FrankRuhlCLM' שמגיעים ב-theme payload
          // (אחרת ב-macOS ה-fallback של המערכת לעברית נראה דקורטיבי).
          final fontFaceCss = await buildPluginFontFaceCss();
          if (!mounted) return;

          // Use cached PackageInfo — avoids async gap crossing a dispose
          final packageInfo =
              _cachedPackageInfo ?? await PackageInfo.fromPlatform();
          if (!mounted) return;
          final permissions = await _pluginRegistryRepository
              .getGrantedPermissionNames(
                widget.plugin.pluginId,
              );
          if (!mounted) return;
          final bootPayload = {
            'plugin': {
              'id': widget.plugin.pluginId,
              'version': widget.plugin.version,
            },
            'app': {
              'version': packageInfo.version,
              'platform': Platform.operatingSystem,
              // שפת הממשק הפעילה (he-IL לתאימות; 'language' — קוד השפה)
              ...pluginLocalePayload(
                code: Settings.getValue<String>(
                  SettingsRepository.keySettingsLanguage,
                ),
              ),
              // חושף לתוסף אם הוא נטען כתוסף פיתוח (sourceType=development).
              // בתוסף ארוז זה false — מאפשר לתוסף לדלג על שערים פיתוחיים
              // (כמו שער סיסמה) רק במצב פיתוח ולא בפרודקשן.
              'devMode': widget.plugin.isDevelopment,
              'runMode': 'foreground',
            },
            'connectivity': ConnectivityStatusService.instance.bootPayload(),
            'theme': theme,
            'permissions': permissions,
          };

          final jsonPayload = jsonEncode(bootPayload);
          final nonceJson = jsonEncode(_bridge.bridgeNonce);
          final fontFaceJson = jsonEncode(fontFaceCss);

          // Real SDK — injected after load, calls _boot() which re-plays queued
          // Otzaria.on() calls and then fires plugin.boot
          await controller.evaluateJavascript(
            source:
                '''
(function () {
  try {
    var __css = $fontFaceJson;
    if (__css) {
      var __style = document.createElement('style');
      __style.setAttribute('data-otzaria-fonts', '1');
      __style.appendChild(document.createTextNode(__css));
      (document.head || document.documentElement).appendChild(__style);
    }
  } catch (e) { console.error('font-face inject failed', e); }
  var _ls = {};
  var _searchStreams = {};
  var _searchSequence = 0;
  var _searchEvent = '__otzaria.search.query.chunk';
  var _networkStreams = {};
  var _networkSequence = 0;
  var _networkEvent = '__otzaria.network.fetchStream.chunk';
  var rpc = function (method, payload) {
    return window.flutter_inappwebview.callHandler('otzaria_rpc', {
      method: method,
      payload: payload || {},
      nonce: $nonceJson
    });
  };
  window.addEventListener(_searchEvent, function (event) {
    var detail = event.detail || {};
    var stream = _searchStreams[detail.streamId];
    if (stream) stream.push(detail.chunk);
  });
  window.addEventListener(_networkEvent, function (event) {
    var detail = event.detail || {};
    var stream = _networkStreams[detail.streamId];
    if (stream) stream.push(detail.chunk);
  });
  var createRpcStream = function (method, payload, streams, streamId) {
    var maxQueuedChunks = 256;
    var queue = [];
    var waiters = [];
    var ended = false;
    var failure = null;
    var flush = function () {
      while (waiters.length && queue.length) {
        waiters.shift().resolve({ value: queue.shift(), done: false });
      }
      if (queue.length || !ended) return;
      while (waiters.length) {
        var waiter = waiters.shift();
        if (failure) waiter.reject(failure);
        else waiter.resolve({ value: undefined, done: true });
      }
    };
    var session = {
      push: function (chunk) {
        if (ended) return;
        if (queue.length >= maxQueuedChunks) {
          session.fail(new Error('Stream consumer is too slow'));
          void rpc(method, { __cancelStreamId: streamId });
          return;
        }
        queue.push(chunk);
        flush();
      },
      finish: function () {
        if (ended) return;
        ended = true;
        delete streams[streamId];
        flush();
      },
      fail: function (error) {
        if (ended) return;
        failure = error instanceof Error ? error : new Error(String(error));
        ended = true;
        delete streams[streamId];
        flush();
      }
    };
    streams[streamId] = session;
    var request = Object.assign({}, payload || {}, { __streamId: streamId });
    rpc(method, request).then(function (response) {
      if (!response || response.success !== true) {
        var message = response && response.error && response.error.message;
        session.fail(new Error(message || 'Stream failed'));
        return;
      }
      session.finish();
    }, session.fail);
    return {
      next: function () {
        if (queue.length) return Promise.resolve({ value: queue.shift(), done: false });
        if (ended) {
          return failure
            ? Promise.reject(failure)
            : Promise.resolve({ value: undefined, done: true });
        }
        return new Promise(function (resolve, reject) {
          waiters.push({ resolve: resolve, reject: reject });
        });
      },
      return: function () {
        if (!ended) {
          ended = true;
          delete streams[streamId];
          flush();
          void rpc(method, { __cancelStreamId: streamId });
        }
        return Promise.resolve({ value: undefined, done: true });
      },
      [Symbol.asyncIterator]: function () { return this; }
    };
  };
  var createSearchStream = function (payload) {
    var id = 'search_' + Date.now().toString(36) + '_' + (++_searchSequence).toString(36);
    return createRpcStream('search.query', payload, _searchStreams, id);
  };
  var createNetworkFetchStream = function (payload) {
    var id = 'network_' + Date.now().toString(36) + '_' + (++_networkSequence).toString(36);
    return createRpcStream('network.fetchStream', payload, _networkStreams, id);
  };
  var realSdk = {
    call: function (method, payload) {
      if (method === 'search.query') return createSearchStream(payload);
      if (method === 'network.fetchStream') return createNetworkFetchStream(payload);
      return rpc(method, payload);
    },
    on: function (event, cb) {
      if (!_ls[event]) _ls[event] = [];
      var w = function (e) { cb(e.detail); };
      _ls[event].push({ orig: cb, wrap: w });
      window.addEventListener(event, w);
    },
    off: function (event, cb) {
      var list = _ls[event];
      if (!list) return;
      for (var i = 0; i < list.length; i++) {
        if (list[i].orig === cb) {
          window.removeEventListener(event, list[i].wrap);
          list.splice(i, 1);
          break;
        }
      }
    }
  };
  window.Otzaria._boot(realSdk, $jsonPayload);
})();
''',
          );
          // הטעינה הצליחה עד הסוף (גם ה-stub וגם ה-boot payload הוזרקו).
          // מסירים את התוסף מ-quarantine כדי שהפעלה הבאה תאפשר טעינה רגילה.
          unawaited(
            PluginCrashGuard.markLoadSuccess(
              widget.plugin.pluginId,
              owner: widget.instanceId,
            ),
          );
          // אם התוסף נטען בזמן שאינו ה-foreground הפעיל — להשהותו מיד, כדי
          // שלא ירוץ ברקע. ההשהיה כאן (אחרי load) ולא ב-registerController
          // כי pause על WebView שעוד לא נטען עלול לקטוע את הטעינה עצמה.
          unawaited(
            PluginRuntimeDispatcher.instance.onForegroundInstanceReady(
              widget.plugin.pluginId,
              instanceId: widget.instanceId,
            ),
          );
          PluginPageLauncher.instance.markPageReady(
            widget.plugin.pluginId,
            instanceId: widget.instanceId,
          );
        } catch (e, st) {
          // Boot ב-Dart נכשל — התהליך חי, לא קריסה native. מנקים את ה-canary
          // כדי שלא נחסום בהפעלה הבאה תוסף שפשוט החזיר שגיאת אתחול רגילה.
          unawaited(
            PluginCrashGuard.markLoadSuccess(
              widget.plugin.pluginId,
              owner: widget.instanceId,
            ),
          );
          debugPrint('Plugin [${widget.plugin.pluginId}] boot error: $e\n$st');
          PluginSystemDatabase.instance.writeLog(
            widget.plugin.pluginId,
            'ERROR',
            'Boot failed: $e',
          );
          if (!mounted) return;
          if (widget.plugin.isDevelopment) {
            setState(() => _devErrorMessage = 'שגיאה באתחול התוסף:\n$e');
          } else {
            setState(() => _hasError = true);
          }
        }
      },
      onProcessFailed: (controller, detail) {
        // תהליך WebView2 (renderer/browser/GPU) מת — התוכן נעלם בלי חריגה.
        logPluginWebViewFailure(
          'Plugin WebView2 process failed',
          detail.kind,
          details: {
            'Plugin': widget.plugin.pluginId,
            'Reason': detail.reason?.toString(),
            'ExitCode': detail.exitCode?.toString(),
            'Process': detail.processDescription,
          },
        );
      },
      onReceivedError: (controller, request, error) {
        // only fail the view for the entrypoint file load itself
        if (request.url.scheme == 'file') {
          // שגיאת רשת/קובץ נתפסה ב-Dart — התהליך חי, לא קריסה native.
          // מנקים את ה-canary כדי שלא נחסום שגיאה רגילה כ"קריסה".
          unawaited(
            PluginCrashGuard.markLoadSuccess(
              widget.plugin.pluginId,
              owner: widget.instanceId,
            ),
          );
          if (mounted) setState(() => _hasError = true);
          return;
        }
        // localhost_dev: כשל בטעינת ה-main frame = שרת הפיתוח אינו רץ. מציגים
        // מסך מותאם במקום דף השגיאה של הדפדפן (ERR_CONNECTION_REFUSED).
        if (widget.plugin.isLocalhostDev &&
            request.isForMainFrame == true &&
            _isDevServerUri(request.url)) {
          unawaited(
            PluginCrashGuard.markLoadSuccess(
              widget.plugin.pluginId,
              owner: widget.instanceId,
            ),
          );
          if (mounted) {
            setState(
              () => _devErrorMessage =
                  'שרת הפיתוח אינו זמין בכתובת ${widget.plugin.devRootPath}.\n'
                  'ודא ששרת הפיתוח רץ (למשל: npm run dev) ולחץ "נסה קריאה מחדש".',
            );
          }
        }
      },
      onConsoleMessage: (controller, consoleMessage) {
        try {
          if (consoleMessage.messageLevel == ConsoleMessageLevel.ERROR ||
              consoleMessage.messageLevel == ConsoleMessageLevel.WARNING) {
            PluginSystemDatabase.instance.writeLog(
              widget.plugin.pluginId,
              consoleMessage.messageLevel.toString(),
              consoleMessage.message,
            );
          }
          debugPrint(
            'Plugin [${widget.plugin.pluginId}]: ${consoleMessage.message}',
          );
        } catch (e) {
          debugPrint(
            'Plugin [${widget.plugin.pluginId}] console log error: $e',
          );
        }
      },
    );

    // ה-WebView מגיב ללחצן האמצעי בעצמו (Chromium מפעיל שם גלילה אוטומטית
    // משלו), ובלי החסימה היו נפתחים שני עוגנים במקביל.
    return AutoScrollBarrier(child: webView);
  }

  static bool get _needsWebViewPrerequisites {
    if (kIsWeb) return false;
    // סביבה קיימת (pre-warm ב-main) הופכת את הבדיקה למיותרת, וה-FutureBuilder
    // היה עולה פריים ריק שחושף את מסך הכלים מאחורי התוסף. נבדק כאן ולא בדגל
    // סטטי, כדי ש-restart בתוך התהליך (שמאפס את הסביבה) יאתחל אותה מחדש.
    if (Platform.isWindows && WebViewEnvironmentHolder.environment != null) {
      return false;
    }
    return Platform.isAndroid || Platform.isWindows;
  }

  /// מבצע את בדיקת/אתחול התנאים המוקדמים ל-WebView לפי הפלטפורמה.
  ///
  /// ב-Windows נבדק תחילה אם WebView2 Runtime מותקן; אם לא — מוחזר
  /// [_WebViewPrereqStatus.runtimeMissing] **בלי** לנסות אתחול שייכשל, כדי
  /// שהמשתמש יראה מסך הכוונה להתקנה ולא שגיאה טכנית גולמית.
  static Future<_WebViewPrereqStatus> _resolveWebViewPrerequisites() async {
    if (Platform.isAndroid) {
      await InAppWebViewController.setWebContentsDebuggingEnabled(kDebugMode);
      return _WebViewPrereqStatus.ready;
    }
    if (Platform.isWindows) {
      if (!await WebViewEnvironmentHolder.isRuntimeAvailable()) {
        return _WebViewPrereqStatus.runtimeMissing;
      }
      if (await WebViewEnvironmentHolder.checkDataFolderWritable() != null) {
        return _WebViewPrereqStatus.dataFolderNotWritable;
      }
      await WebViewEnvironmentHolder.initialize();
    }
    return _WebViewPrereqStatus.ready;
  }
}
