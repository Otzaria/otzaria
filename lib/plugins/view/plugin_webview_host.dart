import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
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
import 'package:otzaria/plugins/bridge/plugin_reference_resolver.dart';
import 'package:otzaria/plugins/bridge/plugin_save_target.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/services/plugin_asset_scheme.dart';
import 'package:otzaria/plugins/services/plugin_file_server.dart';
import 'package:otzaria/plugins/services/plugin_headless_shell.dart';
import 'package:otzaria/plugins/services/plugin_network_gate.dart';
import 'package:otzaria/plugins/services/plugin_ref_line_resolver.dart';
import 'package:otzaria/plugins/services/plugin_runtime_dispatcher.dart';
import 'package:otzaria/plugins/services/plugin_webview_failure_log.dart';
import 'package:otzaria/plugins/storage/plugin_system_database.dart';
import 'package:otzaria/plugins/view/plugin_sdk_scripts.dart';
import 'package:otzaria/search/search_repository.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/settings/l10n/settings_language.dart';
import 'package:otzaria/settings/services/custom_folders/bloc/custom_folders_bloc.dart';
import 'package:otzaria/settings/services/safer_mode_guard.dart';
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

/// ב-Windows ‏cacheEnabled/clearAllCache לא ממומשים: עוקפים מטמון ו-service worker ישנים.
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
  late final PluginBridgeHandler bridge;
  late final PluginBridgeAdapter adapter;
  late final PluginRegistryRepository pluginRegistryRepository;
  late final PluginSystemBloc pluginSystemBloc;
  late final FindRefRepository _findRefRepository;
  DateTime? _lastFileServerDenialLogAt;

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
    void Function()? onWorkStarted,
    void Function()? onWorkEnded,
  }) {
    pluginSystemBloc = context.read<PluginSystemBloc>();
    final historyBloc = context.read<HistoryBloc>();
    final tabsBloc = context.read<TabsBloc>();
    final navigationBloc = context.read<NavigationBloc>();
    final libraryBloc = context.read<LibraryBloc>();
    _findRefRepository = buildFindRefRepository(respectHiddenLibrary: false);
    final findRefRepository = _findRefRepository;

    final dependencies = PluginBridgeDependencies(
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
            final ctx = dialogContext;
            if (ctx == null) return false;
            return await showTwoActionsDialog(
                  context: ctx,
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
            final ctx = dialogContext;
            if (ctx == null) return false;
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
      requestPluginInstall: (downloadUrl, {reportContext}) {
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

    pluginRegistryRepository = PluginRegistryRepository();
    adapter = PluginBridgeAdapter(
      plugin,
      dependencies: dependencies,
      instanceId: instanceId,
      readerTab: readerTab,
      pluginRepository: pluginRegistryRepository,
    );
    bridge = PluginBridgeHandler(
      plugin,
      adapter: adapter,
      registry: pluginRegistryRepository,
      onWorkStarted: onWorkStarted,
      onWorkEnded: onWorkEnded,
    );
    // Pre-fetch so onLoadStop has no async gap
    ensurePackageInfo();

    PluginRuntimeDispatcher.instance.registerReloadCallback(
      plugin.pluginId,
      onReload,
      instanceId: instanceId,
      token: this,
    );
  }

  /// ה-context אחרי אימות סיסמת "מצב בטוח", או null.
  Future<BuildContext?> _verifiedDialogContext() async {
    final ctx = dialogContext;
    if (ctx == null || !await verifySaferModePassword(ctx)) return null;
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
    _findRefRepository.dispose();
    final pluginId = plugin.pluginId;
    final id = instanceId;
    final controller = webViewController;
    // העץ נעול בזמן dispose וניקוי הרישומים מודיע ל-ListenableBuilders
    // (הדגשות, סרגל כלים) — לכן נדחה למיקרוטסק, אחרי שחרור הנעילה.
    scheduleMicrotask(() {
      adapter.dispose();
      afterAdapter?.call();
      // ביטול הרישום רק אם הדף הזה עדיין הבעלים. עדכון תוסף משנה את ה-key,
      // ו-initState של הדף החדש רץ *לפני* ה-dispose של הישן — בלי הבדיקה
      // הישן היה מוחק את הרישום של החדש ומשתיק אותו.
      if (PluginRuntimeDispatcher.instance.ownsController(
        pluginId,
        controller,
        instanceId: id,
      )) {
        onOwnerClosed?.call();
        PluginRuntimeDispatcher.instance.unregisterController(
          pluginId,
          instanceId: id,
        );
      }
      PluginRuntimeDispatcher.instance.unregisterReloadCallback(
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
      PluginRuntimeDispatcher.instance.registerController(
        plugin.pluginId,
        controller,
        instanceId: instanceId,
      );
      bridge.register(controller);
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
    final ctx = dialogContext;
    if (ctx == null || !await verifySaferModePassword(ctx)) {
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
        return WebResourceResponse(
          contentType: 'text/html',
          contentEncoding: 'utf-8',
          statusCode: 200,
          reasonPhrase: 'OK',
          data: utf8.encode(
            pluginHeadlessShellHtml(plugin.entrypointPath, module: false),
          ),
        );
      }
      if (uri.scheme == 'file' && !_isInsideRoot(uri)) return _forbidden();
      if (_isDevServerRequest(uri)) return null; // dev server + HMR
      if (uri.scheme == 'http' && PluginFileServer.instance.isServerUri(uri)) {
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

  /// סקריפט ה-boot: ה-SDK האמיתי וה-payload שהתוסף מקבל ב-plugin.boot.
  String pluginBootScript({
    required String runMode,
    required PackageInfo packageInfo,
    required List<String> permissions,
    required Map<String, dynamic> theme,
    Map<String, dynamic>? reader,
    String? fontFaceCss,
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
    };
    return buildPluginBootScript(
      nonceJson: jsonEncode(bridge.bridgeNonce),
      payloadJson: jsonEncode(bootPayload),
      fontFaceJson: fontFaceCss == null ? null : jsonEncode(fontFaceCss),
    );
  }

  void logPluginProcessFailed(ProcessFailedDetail detail) =>
      logPluginWebViewFailure(
        '$logTag WebView2 process failed',
        detail.kind,
        details: {
          'Plugin': plugin.pluginId,
          'Reason': detail.reason?.toString(),
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
