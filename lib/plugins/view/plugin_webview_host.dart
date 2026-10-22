import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/core/windowing/app_window_keys.dart';
import 'package:otzaria/plugins/plugin_constants.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:otzaria/settings/engine/app_settings_store.dart';
import 'package:otzaria/bookmarks/bloc/bookmark_bloc.dart';
import 'package:otzaria/core/connectivity_status_service.dart';
import 'package:otzaria/find_ref/repository/find_ref_factory.dart';
import 'package:otzaria/find_ref/repository/find_ref_repository.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/library/bloc/library_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/personal_notes/repository/personal_notes_repository.dart';
import 'package:otzaria/plugins/bloc/plugin_system_bloc.dart';
import 'package:otzaria/plugins/bloc/plugin_system_event.dart';
import 'package:otzaria/plugins/bridge/plugin_bridge_adapter.dart';
import 'package:otzaria/plugins/bridge/plugin_bridge_handler.dart';
import 'package:otzaria/plugins/view/plugin_confirmation_dialog.dart';
import 'package:otzaria/plugins/bridge/plugin_reference_resolver.dart';
import 'package:otzaria/plugins/bridge/plugin_save_target.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/services/plugin_asset_scheme.dart';
import 'package:otzaria/plugins/services/plugin_content_blockers.dart';
import 'package:otzaria/plugins/services/plugin_content_security_policy.dart';
import 'package:otzaria/plugins/services/plugin_file_server.dart';
import 'package:otzaria/plugins/services/plugin_fonts.dart';
import 'package:otzaria/plugins/services/plugin_headless_shell.dart';
import 'package:otzaria/plugins/services/plugin_network_gate.dart';
import 'package:otzaria/plugins/services/plugin_network_policy.dart';
import 'package:otzaria/plugins/services/plugin_ref_line_resolver.dart';
import 'package:otzaria/plugins/services/plugin_runtime_dispatcher.dart';
import 'package:otzaria/plugins/services/plugin_webview_diagnostics.dart';
import 'package:otzaria/plugins/services/plugin_webview_failure_log.dart';
import 'package:otzaria/plugins/storage/plugin_system_database.dart';
import 'package:otzaria/plugins/view/plugin_sdk_scripts.dart';
import 'package:otzaria/search/search_repository.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/settings/l10n/settings_language.dart';
import 'package:otzaria/settings/services/custom_folders/bloc/custom_folders_bloc.dart';
import 'package:otzaria/settings/services/safer_mode_guard.dart';
import 'package:otzaria/plugins/services/plugin_install_report_service.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/tools/calendar/bloc/calendar_cubit.dart';
import 'package:otzaria/update/app_release_version.dart';
import 'package:otzaria/utils/file/file_picker_dialog_options.dart';
import 'package:otzaria/utils/navigation/book_open_coordinator.dart';
import 'package:otzaria/widgets/dialogs/dialogs_exports.dart';
import 'package:otzaria/workspaces/bloc/workspace_bloc.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:otzaria/utils/ui/reading_left_pane_policy.dart';

// Restricts localhost access to the exact dev server origin (host + scheme + port).
bool isPluginDevServerUri(Uri uri, String? devRootPath) {
  if (devRootPath == null) return false;
  final devUri = Uri.tryParse(devRootPath);
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

/// ב-Windows cacheEnabled/clearAllCache לא ממומשים: עוקפים מטמון ו-service worker ישנים.
Future<void> loadPluginDevServer(
  InAppWebViewController controller,
  WebUri url,
) async {
  if (Platform.isWindows) {
    for (final (method, params) in const [
      ('Network.setCacheDisabled', {'cacheDisabled': true}),
      ('Network.setBypassServiceWorker', {'bypass': true}),
    ]) {
      try {
        await controller.callDevToolsProtocolMethod(
          methodName: method,
          parameters: params,
        );
      } catch (_) {}
    }
  }
  await controller.loadUrl(urlRequest: URLRequest(url: url));
}

WebResourceResponse _forbidden() =>
    WebResourceResponse(statusCode: 403, reasonPhrase: 'Forbidden');

/// החיווט המשותף ללשונית התוסף ולמופע הרקע: ה-bridge, שערי הניווט והבקשות
/// וקריאות ה-WebView הזהות. ההבדלים בין המופעים נשארים אצל כל אחד מהם.
mixin PluginWebViewHost<T extends StatefulWidget> on State<T> {
  // Cache PackageInfo so the async gap in onLoadStop never crosses a dispose
  static PackageInfo? cachedPackageInfo;
  static const _fileServerDenialLogInterval = Duration(minutes: 1);

  InstalledPlugin get plugin;
  String get instanceId;

  /// קידומת הודעות הדיבאג ('Plugin' / 'Background plugin').
  String get logTag;

  /// ה-context לדיאלוגים שהתוסף מבקש, או null כשאין דרך להציגם.
  BuildContext? get dialogContext;

  InAppWebViewController? webViewController;

  /// האם [controller] שהגיע ב-callback שייך ל-WebView הנוכחי. כל callback
  /// מקבל עטיפה חדשה, ולכן משווים את המימוש שמתחתיה.
  bool isCurrentWebView(InAppWebViewController controller) =>
      identical(controller.platform, webViewController?.platform);
  late final PluginBridgeHandler bridge;
  late final PluginBridgeAdapter adapter;
  late final PluginRegistryRepository pluginRegistryRepository;
  late final PluginSystemBloc pluginSystemBloc;
  late final FindRefRepository _findRefRepository;
  late final PluginBridgeWindowDependencies Function()
  _initialWindowDependencies;
  final _confirmationDialog = PluginConfirmationDialog();
  DateTime? _lastFileServerDenialLogAt;
  Future<PluginNetworkPolicy>? _networkPolicy;
  StreamSubscription<String?>? _networkPolicyChanges;
  List<ContentBlocker>? _contentBlockers;
  bool _contentBlockersPushPending = false;

  /// מדיניות הרשת העדכנית של התוסף; מחושבת מחדש אחרי כל שינוי בה.
  Future<PluginNetworkPolicy> get networkPolicy => _networkPolicy ??=
      resolvePluginNetworkPolicy(
        pluginId: plugin.pluginId,
        manifest: plugin.manifest,
        registry: pluginRegistryRepository,
      ).catchError((Object e) {
        debugPrint('$logTag [${plugin.pluginId}] network policy error: $e');
        return PluginNetworkPolicy.none;
      });

  /// ה-CSP שמצורף לכל קובץ של התוסף שמוגש דרך אוצריא.
  Future<String> pluginContentSecurityPolicy() async =>
      buildPluginContentSecurityPolicy(
        pluginId: plugin.pluginId,
        policy: await networkPolicy,
        fileServerPort: await PluginFileServer.instance.ensurePort(),
      );

  /// חוקי החסימה ל-`initialSettings`, או `null` כשעדיין אינם מוכנים — ואז אין
  /// ליצור את ה-WebView: בלעדיהם הוא נטען בלי שום שער רשת.
  List<ContentBlocker>? get pluginContentBlockers =>
      pluginNetworkUsesContentBlockers ? _contentBlockers : const [];

  Map<String, dynamic> currentThemePayload() {
    if (!mounted) {
      return {
        'mode': 'light',
        'colorScheme': <String, dynamic>{},
        'typography': <String, dynamic>{},
      };
    }
    return buildThemePayload(context);
  }

  /// בונה את ה-bridge של המופע ורושם אצל ה-Dispatcher את [onReload].
  void initPluginHost({
    required Future<void> Function() onReload,
    TextBookTab? readerTab,
    bool Function()? onBackgroundInstanceDone,
    VoidCallback Function()? onWorkStarted,
  }) {
    pluginSystemBloc = context.read<PluginSystemBloc>();
    final historyBloc = context.read<HistoryBloc>();
    final tabsBloc = context.read<TabsBloc>();
    final navigationBloc = context.read<NavigationBloc>();
    final libraryBloc = context.read<LibraryBloc>();
    _findRefRepository = buildFindRefRepository(respectHiddenLibrary: false);
    final findRefRepository = _findRefRepository;

    final dependencies = PluginBridgeDependencies(
      windowContext: context,
      historyBloc: historyBloc,
      tabsBloc: tabsBloc,
      navigationBloc: navigationBloc,
      calendarCubit: context.read<CalendarCubit>(),
      workspaceBloc: context.read<WorkspaceBloc>(),
      bookmarkBloc: context.read<BookmarkBloc>(),
      customFoldersBloc: context.read<CustomFoldersBloc>(),
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
      searchRepository: SearchRepository(),
      personalNotesRepository: PersonalNotesRepository(),
      bookOpenCoordinator: BookOpenCoordinator(
        tabsBloc: tabsBloc,
        historyBloc: historyBloc,
        navigationBloc: navigationBloc,
        layoutWidth: readingLayoutWidthResolverOf(context),
      ),
      resolveReference: buildPluginReferenceResolver(findRefRepository),
      resolveRefToLine: (book, ref) =>
          PluginRefLineResolver().resolve(book: book, ref: ref),
      themePayloadBuilder: currentThemePayload,
      showConfirmDialog:
          ({
            required String title,
            required String content,
          }) async {
            final ctx = adapter.rpcWindowContext ?? dialogContext;
            if (ctx == null || !ctx.mounted) return false;
            return _confirmationDialog.show(
              context: ctx,
              title: title,
              content: content,
            );
          },
      showWarningDialog:
          ({
            required String title,
            required String content,
            required String subtitle,
          }) async {
            final ctx = adapter.rpcWindowContext ?? dialogContext;
            if (ctx == null || !ctx.mounted) return false;
            return await showWarningDialog(
                  context: ctx,
                  title: title,
                  content: content,
                  subtitle: subtitle,
                  cancelText: 'ביטול',
                  confirmText: 'המשך',
                ) ==
                true;
          },
      requestPluginInstall: (downloadUrl, {reportContext}) async {
        if (await _verifiedDialogContext() == null) {
          if (reportContext != null) {
            unawaited(
              PluginInstallReportService.report(
                reportContext,
                success: false,
                errorMessage: 'ההתקנה נחסמה במצב סייפר',
              ),
            );
          }
          return;
        }
        pluginSystemBloc.add(
          InstallRemotePluginRequested(
            downloadUrl,
            reportContext: reportContext,
            storeOnly: true,
          ),
        );
      },
      pickFolder: ({String? title}) async {
        if (await _verifiedDialogContext() == null) return null;
        return FilePicker.getDirectoryPath(
          windowsOptions: kModalWindowsOptions,
          linuxOptions: kModalLinuxOptions,
          dialogTitle: title,
        );
      },
      onBackgroundInstanceDone: onBackgroundInstanceDone,
      pickFile: ({List<String>? allowedExtensions, String? title}) async {
        if (await _verifiedDialogContext() == null) return null;
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
      pickSaveLocation:
          ({
            required String suggestedName,
            List<String>? allowedExtensions,
            String? title,
          }) async {
            final ctx = await _verifiedDialogContext();
            if (ctx == null) return null;
            final folder = await FilePicker.getDirectoryPath(
              dialogTitle: pluginSaveFolderDialogTitle(title),
              windowsOptions: kModalWindowsOptions,
              linuxOptions: kModalLinuxOptions,
            );
            if (folder == null || !ctx.mounted) return null;
            final typed = await showInputDialog(
              context: ctx,
              title: title ?? 'שמירת קובץ',
              labelText: 'שם הקובץ',
              initialValue: suggestedName,
              confirmText: 'שמור',
            );
            if (typed == null) return null;
            final fileName = pluginSaveFileName(
              typed,
              allowedExtensions?.firstOrNull,
            );
            return pluginSaveTargetPath(folder: folder, fileName: fileName);
          },
    );

    _initialWindowDependencies = () => dependencies.window;
    pluginRegistryRepository = PluginRegistryRepository();
    adapter = PluginBridgeAdapter(
      plugin,
      dependencies: dependencies,
      windowDependenciesResolver: instanceId == PluginInstanceIds.background
          ? _activeWindowDependencies
          : null,
      instanceId: instanceId,
      readerTab: readerTab,
      pluginRepository: pluginRegistryRepository,
    );
    bridge = PluginBridgeHandler(
      plugin,
      adapter: adapter,
      registry: pluginRegistryRepository,
      onWorkStarted: onWorkStarted,
    );
    // Pre-fetch so onLoadStop has no async gap
    ensurePackageInfo();

    PluginRuntimeDispatcher.instance.registerReloadCallback(
      plugin.pluginId,
      onReload,
      instanceId: instanceId,
      token: this,
    );

    _networkPolicyChanges = PluginNetworkPolicy.changes.listen((pluginId) {
      if (pluginId == null || pluginId == plugin.pluginId) {
        _networkPolicy = null;
        unawaited(_refreshContentBlockers());
      }
    });
    unawaited(_refreshContentBlockers());
  }

  PluginBridgeWindowDependencies _activeWindowDependencies() {
    final owner = AppWindowKeys.current.navigator.currentContext;
    if (owner == null || !owner.mounted) {
      return _initialWindowDependencies();
    }
    final tabs = owner.read<TabsBloc>();
    final history = owner.read<HistoryBloc>();
    final navigation = owner.read<NavigationBloc>();
    final library = owner.read<LibraryBloc>();
    return (
      context: owner,
      viewId: View.of(owner).viewId,
      windowKeys: AppWindowKeys.of(owner),
      tabsBloc: tabs,
      historyBloc: history,
      navigationBloc: navigation,
      workspaceBloc: owner.read<WorkspaceBloc>(),
      customFoldersBloc: owner.read<CustomFoldersBloc>(),
      bookOpenCoordinator: BookOpenCoordinator(
        tabsBloc: tabs,
        historyBloc: history,
        navigationBloc: navigation,
        layoutWidth: readingLayoutWidthResolverOf(owner),
      ),
      waitForLibraryRefresh: (requestId) async {
        final state = await library.stream.firstWhere(
          (state) =>
              state.completedRefreshRequestIds?.contains(requestId) == true ||
              (!state.isLoading && state.error != null),
        );
        if (state.completedRefreshRequestIds?.contains(requestId) != true) {
          throw StateError(state.error!);
        }
      },
    );
  }

  Future<void> _refreshContentBlockers() async {
    if (!pluginNetworkUsesContentBlockers) return;
    final rules = buildPluginContentBlockers(
      pluginId: plugin.pluginId,
      policy: await networkPolicy,
      fileServerPort: await PluginFileServer.instance.ensurePort(),
      devServerOrigin: plugin.isLocalhostDev ? plugin.devRootPath : null,
    );
    if (!mounted) return;
    if (_contentBlockers == null) {
      setState(() => _contentBlockers = rules);
      return;
    }
    _contentBlockers = rules;
    _contentBlockersPushPending = true;
    await _pushContentBlockers();
  }

  /// ה-WebView כבר נוצר עם החוקים הקודמים, ולכן מעדכנים אותו במקום.
  Future<void> _pushContentBlockers() async {
    final controller = webViewController;
    final rules = _contentBlockers;
    if (controller == null || rules == null || !_contentBlockersPushPending) {
      return;
    }
    _contentBlockersPushPending = false;
    try {
      final settings = await controller.getSettings();
      if (settings == null) return;
      settings.contentBlockers = rules;
      await controller.setSettings(settings: settings);
    } catch (e) {
      debugPrint('$logTag [${plugin.pluginId}] content blockers update: $e');
    }
  }

  /// ה-context אחרי אימות סיסמת "מצב בטוח", או null.
  Future<BuildContext?> _verifiedDialogContext() async {
    final ctx = adapter.rpcWindowContext ?? dialogContext;
    if (ctx == null || !ctx.mounted || !await verifySaferModePassword(ctx)) {
      return null;
    }
    return ctx.mounted ? ctx : null;
  }

  Future<void> ensurePackageInfo() async {
    cachedPackageInfo ??= await PackageInfo.fromPlatform();
  }

  /// [onOwnerClosed] רץ רק אם המופע עדיין הבעלים של ה-controller.
  void disposePluginHost({
    void Function()? afterAdapter,
    void Function()? onOwnerClosed,
  }) {
    _confirmationDialog.dispose();
    _findRefRepository.dispose();
    unawaited(_networkPolicyChanges?.cancel());
    final pluginId = plugin.pluginId;
    final id = instanceId;
    final controller = webViewController;
    final dispatcher = PluginRuntimeDispatcher.instance;
    // WebView שפונה אינו רשום כ-controller, אבל הדף הזה עדיין בעל המופע.
    final ownsReleased = dispatcher.isReleasedBy(
      pluginId,
      instanceId: id,
      token: this,
    );
    // העץ נעול בזמן dispose וניקוי הרישומים מודיע ל-ListenableBuilders
    // (הדגשות, סרגל כלים) — לכן נדחה למיקרוטסק, אחרי שחרור הנעילה.
    scheduleMicrotask(() {
      adapter.dispose();
      afterAdapter?.call();
      // ביטול הרישום רק אם הדף הזה עדיין הבעלים. עדכון תוסף משנה את ה-key,
      // ו-initState של הדף החדש רץ *לפני* ה-dispose של הישן — בלי הבדיקה
      // הישן היה מוחק את הרישום של החדש ומשתיק אותו.
      if (ownsReleased ||
          dispatcher.ownsController(pluginId, controller, instanceId: id)) {
        onOwnerClosed?.call();
        dispatcher.unregisterController(pluginId, instanceId: id);
      }
      dispatcher.unregisterInstanceHost(pluginId, instanceId: id, token: this);
      dispatcher.unregisterReloadCallback(
        pluginId,
        instanceId: id,
        token: this,
      );
    });
  }

  /// ה-URI של נקודת הכניסה — `file://` ברוב הפלטפורמות, ובמק דרך
  /// [pluginAssetScheme].
  WebUri pluginEntrypointUri(String htmlPath, {required bool assetScheme}) =>
      plugin.isLocalhostDev
      ? WebUri(htmlPath)
      : assetScheme
      ? pluginAssetUri(
          pluginId: plugin.pluginId,
          rootPath: plugin.resolvedRootPath,
          filePath: htmlPath,
        )
      : WebUri.uri(Uri.file(htmlPath));

  /// רושם את ה-controller אצל ה-Dispatcher וה-bridge (ו-[onAttached]);
  /// שרת פיתוח נטען כאן ([entrypoint]) ולא ב-initialUrlRequest.
  /// בכשל מבטל את הרישום ומחזיר false.
  bool attachPluginController(
    InAppWebViewController controller,
    WebUri entrypoint, [
    void Function()? onAttached,
  ]) {
    try {
      webViewController = controller;
      registerPluginWebViewDiagnostics();
      PluginRuntimeDispatcher.instance.registerController(
        plugin.pluginId,
        controller,
        instanceId: instanceId,
        viewId: View.of(context).viewId,
      );
      bridge.register(controller);
      unawaited(_pushContentBlockers());
      if (plugin.isLocalhostDev) {
        unawaited(loadPluginDevServer(controller, entrypoint));
      }
      onAttached?.call();
      return true;
    } catch (e) {
      PluginRuntimeDispatcher.instance.unregisterController(
        plugin.pluginId,
        instanceId: instanceId,
      );
      debugPrint('$logTag [${plugin.pluginId}] WebView init error: $e');
      return false;
    }
  }

  Future<ShowFileChooserResponse?> verifyPluginFileChooser(
    InAppWebViewController controller,
    ShowFileChooserRequest request,
  ) async {
    final ctx = adapter.rpcWindowContext ?? dialogContext;
    if (ctx == null || !ctx.mounted || !await verifySaferModePassword(ctx)) {
      return ShowFileChooserResponse(handledByClient: true, filePaths: null);
    }
    return null;
  }

  bool _isInsideRoot(Uri uri) {
    final normalizedUri = p.normalize(uri.toFilePath());
    final normalizedInstall = p.normalize(plugin.resolvedRootPath);
    return p.isWithin(normalizedInstall, normalizedUri) ||
        normalizedUri == normalizedInstall;
  }

  bool _isDevServerRequest(Uri uri) =>
      (uri.scheme == 'http' || uri.scheme == 'https') &&
      plugin.isLocalhostDev &&
      isPluginDevServerUri(uri, plugin.devRootPath);

  Future<bool> _isNetworkUriAllowed(Uri uri) => isPluginNetworkAccessAllowed(
    uri: uri,
    pluginId: plugin.pluginId,
    manifest: plugin.manifest,
    registry: pluginRegistryRepository,
  );

  /// מאפשרת רק קבצים (/f/) והעלאה פעילה (/w/) של התוסף עצמו.
  bool _isOwnFileServerRequest(Uri uri) =>
      PluginFileServer.isUriForPlugin(uri, plugin.pluginId) ||
      PluginFileServer.instance.isUploadUriForPlugin(uri, plugin.pluginId);

  void _logFileServerDenial(Uri uri) {
    final now = DateTime.now();
    final lastLogAt = _lastFileServerDenialLogAt;
    if (lastLogAt != null &&
        now.difference(lastLogAt) < _fileServerDenialLogInterval) {
      return;
    }
    _lastFileServerDenialLogAt = now;
    final kind = uri.pathSegments.isEmpty
        ? uri.path
        : '/${uri.pathSegments.first}/…';
    final message = 'בקשת התוסף לשרת הקבצים נחסמה בשער ה-WebView: $kind';
    debugPrint('$logTag [${plugin.pluginId}]: $message');
    // fire-and-forget, כמו כל כתיבה ללוג הריצה.
    unawaited(
      PluginSystemDatabase.instance.writeLog(plugin.pluginId, 'warn', message),
    );
  }

  /// [onDeepLink] — רק בלשונית: קישור otzaria:// שנלחץ בדף.
  Future<NavigationActionPolicy> pluginNavigationPolicy(
    NavigationAction navigationAction, {
    Future<void> Function(Uri, NavigationAction)? onDeepLink,
  }) async {
    try {
      final uri = navigationAction.request.url;
      if (uri == null) return NavigationActionPolicy.CANCEL;
      if (onDeepLink != null && uri.scheme == 'otzaria') {
        await onDeepLink(uri, navigationAction);
        return NavigationActionPolicy.CANCEL;
      }
      if (uri.scheme == pluginAssetScheme) return NavigationActionPolicy.ALLOW;
      if (uri.scheme == 'file') {
        if (_isInsideRoot(uri)) return NavigationActionPolicy.ALLOW;
      } else if (uri.scheme == 'data' ||
          uri.scheme == 'blob' ||
          uri.scheme == 'about') {
        return NavigationActionPolicy.ALLOW;
      }
      if (_isDevServerRequest(uri)) return NavigationActionPolicy.ALLOW;
      // שרת הקבצים הפנימי (loopback). זו נקודת האכיפה היחידה של בידוד בין
      // תוספים — השרת אינו יכול לזהות מי הפונה, והפורט אקראי.
      if (uri.scheme == 'http' && PluginFileServer.instance.isServerUri(uri)) {
        if (_isOwnFileServerRequest(uri)) return NavigationActionPolicy.ALLOW;
        _logFileServerDenial(uri);
        return NavigationActionPolicy.CANCEL;
      }
      if ((uri.scheme == 'http' || uri.scheme == 'https') &&
          await _isNetworkUriAllowed(uri)) {
        return NavigationActionPolicy.ALLOW;
      }
      return NavigationActionPolicy.CANCEL;
    } catch (e) {
      debugPrint('$logTag [${plugin.pluginId}] URL override error: $e');
      return NavigationActionPolicy.CANCEL;
    }
  }

  /// [headless] — מגיש את מעטפת ה-HTML הווירטואלית של תוסף ללא ממשק.
  Future<WebResourceResponse?> interceptPluginRequest(
    WebResourceRequest request, {
    bool headless = false,
  }) async {
    try {
      final uri = request.url;
      if (headless &&
          uri.scheme == 'file' &&
          isPluginHeadlessShellPath(
            uri.toFilePath(),
            plugin.resolvedRootPath,
          )) {
        return await _pluginFileResponse(
          utf8.encode(
            pluginHeadlessShellHtml(plugin.entrypointPath, module: false),
          ),
          contentType: 'text/html',
        );
      }
      if (uri.scheme == 'file') {
        if (!_isInsideRoot(uri)) return _forbidden();
        // כל קובץ מוגש מכאן עם ה-CSP, לא רק HTML: גם SVG או XML שנפתחים כמסמך
        // מריצים סקריפט, ו-Worker מקבל את המדיניות מתשובת הסקריפט שלו.
        final path = uri.toFilePath();
        try {
          return await _pluginFileResponse(
            await File(path).readAsBytes(),
            contentType: pluginAssetContentType(path),
          );
        } on FileSystemException {
          // לא null: אז ה-WebView היה קורא את הקובץ בעצמו, בלי ה-CSP.
          return WebResourceResponse(
            statusCode: 404,
            reasonPhrase: 'Not Found',
          );
        }
      }
      if (_isDevServerRequest(uri)) return null; // dev server + HMR
      if (uri.scheme == 'http' && PluginFileServer.instance.isServerUri(uri)) {
        final font = await pluginFontResponse(request);
        if (font != null) return font;
        // גם נתיב ההעלאה (/w/) של התוסף: בלי ההחרגה ה-PUT של
        // fs.beginBinaryWrite נחסם כאן, וכל שמירה בינארית נופלת ב-"Failed to
        // fetch" (נמדד בווינדוס, שבו ה-fork של אוצריא מפעיל shouldInterceptRequest).
        if (_isOwnFileServerRequest(uri)) return null;
        _logFileServerDenial(uri);
        return _forbidden();
      }
      if (uri.scheme == 'http' || uri.scheme == 'https') {
        return await _isNetworkUriAllowed(uri) ? null : _forbidden();
      }
      return null;
    } catch (e) {
      debugPrint('$logTag [${plugin.pluginId}] intercept request error: $e');
      return _forbidden();
    }
  }

  Future<WebResourceResponse> _pluginFileResponse(
    Uint8List data, {
    required String contentType,
  }) async => WebResourceResponse(
    contentType: contentType,
    contentEncoding: 'utf-8',
    statusCode: 200,
    reasonPhrase: 'OK',
    headers: {
      pluginContentSecurityPolicyHeader: await pluginContentSecurityPolicy(),
    },
    data: data,
  );

  /// סקריפט ה-boot: ה-SDK האמיתי וה-payload שהתוסף מקבל ב-plugin.boot.
  String pluginBootScript({
    required String runMode,
    required PackageInfo packageInfo,
    required List<String> permissions,
    required Map<String, dynamic> theme,
    Map<String, dynamic>? reader,
    Map<String, dynamic>? restore,
    String? fontFaceJson,
  }) {
    final bootPayload = {
      'plugin': {'id': plugin.pluginId, 'version': plugin.version},
      'app': {
        'version': canonicalAppVersion(packageInfo),
        'platform': Platform.operatingSystem,
        // שפת הממשק הפעילה (he-IL לתאימות; 'language' — קוד השפה)
        ...pluginLocalePayload(
          code: Settings.getValue<String>(
            SettingsRepository.keySettingsLanguage,
          ),
        ),
        // חושף לתוסף אם הוא נטען כתוסף פיתוח (sourceType=development).
        // בתוסף ארוז זה false — מאפשר לדלג על שערים פיתוחיים רק בפיתוח.
        'devMode': plugin.isDevelopment,
        // 'background' — אין UI גלוי (למשל לא לבצע ניווט יזום).
        'runMode': runMode,
      },
      'connectivity': ConnectivityStatusService.instance.bootPayload(),
      'theme': theme,
      'permissions': permissions,
      'reader': ?reader,
      'restore': ?restore,
    };
    return buildPluginBootScript(
      nonceJson: jsonEncode(bridge.bridgeNonce),
      payloadJson: jsonEncode(bootPayload),
      fontFaceJson: fontFaceJson,
    );
  }

  final Map<String, DateTime> _processFailureLoggedAt = {};

  /// רישום מה-callback הייעודי לנפילה. ב-Windows אותה נפילה כבר נרשמת דרך
  /// onProcessFailed, עם קוד היציאה.
  void logPluginWebViewGoneOnce(String kind) {
    if (Platform.isWindows) return;
    logPluginWebViewGone(kind);
  }

  /// רושם נפילה של תהליך — פעם אחת לכל סוג בכל 10 דקות, כי "לא מגיב"
  /// חוזר כל כמה שניות.
  void logPluginWebViewGone(
    String kind, {
    Map<String, String?> details = const {},
  }) {
    final now = DateTime.now();
    final last = _processFailureLoggedAt[kind];
    if (last != null && now.difference(last) < const Duration(minutes: 10)) {
      return;
    }
    _processFailureLoggedAt[kind] = now;
    logPluginWebViewFailure(
      '$logTag WebView process gone',
      kind,
      details: {'Plugin': plugin.pluginId, ...details},
    );
  }

  /// רישום בלבד: ההתאוששות מבוססת על ה-callbacks הייעודיים, שמגיעים גם הם
  /// על אותה נפילה.
  void logPluginProcessFailed(ProcessFailedDetail detail) =>
      logPluginWebViewGone(
        detail.kind.name(),
        details: {
          'Reason': detail.reason?.name(),
          'ExitCode': detail.exitCode?.toString(),
          'Process': detail.processDescription,
        },
      );

  void logPluginConsole(ConsoleMessage consoleMessage, {String prefix = ''}) {
    try {
      if (consoleMessage.messageLevel == ConsoleMessageLevel.ERROR ||
          consoleMessage.messageLevel == ConsoleMessageLevel.WARNING) {
        PluginSystemDatabase.instance.writeLog(
          plugin.pluginId,
          consoleMessage.messageLevel.toString(),
          '$prefix${consoleMessage.message}',
        );
      }
      debugPrint('$logTag [${plugin.pluginId}]: ${consoleMessage.message}');
    } catch (e) {
      debugPrint('$logTag [${plugin.pluginId}] console log error: $e');
    }
  }
}
