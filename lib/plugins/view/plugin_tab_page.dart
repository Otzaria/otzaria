import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_inappwebview_windows/flutter_inappwebview_windows.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/services/plugin_manifest_validator.dart';
import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:collection';
import 'package:path/path.dart' as p;
import 'package:otzaria/plugins/services/plugin_page_launcher.dart';
import 'package:otzaria/plugins/services/plugin_runtime_dispatcher.dart';
import 'package:otzaria/plugins/services/plugin_unsaved_changes_registry.dart';
import 'package:otzaria/plugins/storage/plugin_system_database.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:otzaria/plugins/bridge/plugin_bridge_adapter.dart';
import 'package:otzaria/navigation/view/main_window_screen.dart';
import 'package:otzaria/widgets/misc/middle_click_autoscroll.dart';
import 'package:otzaria/plugins/view/plugin_dev_error_view.dart';
import 'package:otzaria/plugins/view/webview_environment_holder.dart';
import 'package:otzaria/plugins/bloc/plugin_system_event.dart';
import 'package:otzaria/plugins/services/plugin_asset_scheme.dart';
import 'package:otzaria/plugins/services/plugin_crash_guard.dart';
import 'package:otzaria/plugins/services/plugin_deep_link_policy.dart';
import 'package:otzaria/plugins/services/plugin_host_shortcuts.dart';
import 'package:otzaria/plugins/services/plugin_webview_failure_log.dart';
import 'package:otzaria/plugins/view/plugin_crashed_view.dart';
import 'package:otzaria/plugins/view/plugin_data_folder_unwritable_view.dart';
import 'package:otzaria/plugins/view/plugin_webview2_missing_view.dart';
import 'package:otzaria/plugins/view/plugin_webview_failed_view.dart';
import 'package:otzaria/plugins/services/windows_arch_info.dart';
import 'package:otzaria/plugins/view/plugin_drop_guard_script.dart';
import 'package:otzaria/plugins/view/plugin_sdk_scripts.dart';
import 'package:otzaria/plugins/view/plugin_webview_host.dart';
import 'package:otzaria/plugins/view/plugin_linkify_script.dart';
import 'package:otzaria/plugins/view/widgets/plugin_webview_focus_restorer.dart';
import 'package:otzaria/plugins/services/plugin_download_handler.dart';
import 'package:otzaria/plugins/services/plugin_webview_permission_gate.dart';
import 'package:otzaria/settings/settings_exports.dart';
import 'package:otzaria/utils/ui/fullscreen_helper.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/plugins/services/plugin_text_reader_registry.dart';

/// קוד JS שמעדכן בתוסף את רשימת קיצורי התוכנה שהוא מעביר חזרה.
@visibleForTesting
String buildSetHostShortcutsScript(List<PluginHostShortcut> shortcuts) =>
    'window.__otzariaSetHostShortcuts && window.__otzariaSetHostShortcuts('
    '${jsonEncode(shortcuts.map((s) => s.toJson()).toList())});';

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
    resourceCustomSchemes: pluginAssetSchemeEnabled
        ? const [pluginAssetScheme]
        : const [],
  );
}

/// בלי recognizer אנכי, הגרירה האופקית של ה-PageView (במובייל, כשיש יותר
/// מטאב אחד) מעכבת את המגע עד השחרור — והתוסף לא נגלל.
Set<Factory<OneSequenceGestureRecognizer>>? pluginTabWebViewGestureRecognizers({
  required bool isTouchPlatform,
}) {
  if (!isTouchPlatform) return null;
  return {
    Factory<VerticalDragGestureRecognizer>(VerticalDragGestureRecognizer.new),
  };
}

class PluginTabPage extends StatefulWidget {
  final InstalledPlugin plugin;
  final TextBookTab? readerTab;

  /// מזהה המופע של הטאב (ToolTab.instanceId) — מזהה את הרישום של הדף הזה
  /// אצל PluginRuntimeDispatcher, לצד מופעים נוספים של אותו תוסף.
  final String instanceId;

  const PluginTabPage({
    super.key,
    required this.plugin,
    required this.instanceId,
    this.readerTab,
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

class _PluginTabPageState extends State<PluginTabPage> with PluginWebViewHost {
  // future של בדיקת התנאים המוקדמים. שמור ברמת המופע (לא static) כדי
  // שכפתור "בדוק שוב" יוכל לאפסו (setState(() => _prereqFuture = null))
  // ולהריץ בדיקה מחדש לאחר שהמשתמש התקין את WebView2.
  Future<_WebViewPrereqStatus>? _prereqFuture;

  @override
  InstalledPlugin get plugin => widget.plugin;
  @override
  String get instanceId => widget.instanceId;
  @override
  String get logTag => 'Plugin';
  @override
  BuildContext? get dialogContext => mounted ? context : null;

  late String localHtmlPath;

  /// נבדק פעם אחת ולא בכל build: existsSync בכל פריים resize הוא I/O סינכרוני,
  /// וכשל חולף אחד (נעילת אנטי-וירוס) היה מפיל את ה-WebView וטוען אותו מאפס.
  late bool _entrypointMissing;

  /// צורת העץ של build ננעלת לכל חיי ה-State: מעבר FutureBuilder ↔ ישיר
  /// היה מייצר הורה חדש ל-WebView והורס אותו.
  late final bool _usePrereqGate = _needsWebViewPrerequisites;

  /// GlobalKey ל-InAppWebView — שורד החלפת הורה באותו פריים בלי טעינה מחדש.
  final GlobalKey _webViewKey = GlobalKey();
  bool _hasError = false;
  String? _devErrorMessage;

  // כשל יצירה native לא מפעיל אף callback ב-Dart — נשאר רק מסך ריק.
  // השעון נדרך בבניית ה-WebView ומבוטל ב-onWebViewCreated, כדי לרשום ללוג.
  Timer? _creationWatchdog;

  // כשל היצירה מגיע מהפלאגין כאירוע גלובלי (אין callback על ה-widget).
  StreamSubscription<WindowsWebViewCreationFailure>? _creationFailureSub;
  StreamSubscription<SettingsState>? _settingsSub;

  /// קיצורי הניווט שהוזרקו לתוסף, לפי המזהה שה-JS מחזיר.
  Map<String, PluginHostShortcut> _hostShortcuts = const {};
  String? _creationFailure;

  @override
  void initState() {
    super.initState();
    _settingsSub = context.read<SettingsBloc>().stream.listen((state) {
      final controller = webViewController;
      if (controller != null && !mapEquals(state.shortcuts, _lastShortcuts)) {
        unawaited(_pushHostShortcuts(controller));
      }
    });
    // For localhost_dev the dev server root IS the entrypoint (e.g. http://localhost:5173/).
    // The manifest entrypoint (e.g. dist/index.html) is the production-build path only.
    localHtmlPath = widget.plugin.isLocalhostDev
        ? widget.plugin.devRootPath!.replaceAll(RegExp(r'/+$'), '')
        : '${widget.plugin.resolvedRootPath}/${widget.plugin.entrypointPath}';
    _entrypointMissing =
        !widget.plugin.isLocalhostDev && !File(localHtmlPath).existsSync();
    initPluginHost(onReload: _reloadFromDisk, readerTab: widget.readerTab);
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
      await ensurePackageInfo();
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

      final wasInError = _devErrorMessage != null;
      setState(() => _devErrorMessage = null);

      try {
        await InAppWebViewController.clearAllCache();
      } catch (_) {}

      localHtmlPath = p.join(
        widget.plugin.resolvedRootPath,
        manifest.entrypoint,
      );
      final exists = File(localHtmlPath).existsSync();
      if (!exists) {
        setState(
          () => _devErrorMessage =
              'קובץ נקודת הכניסה חסר בתיקייה: $localHtmlPath',
        );
        return;
      }
      _entrypointMissing = false;

      if (wasInError || webViewController == null) {
        // במסך שגיאה ה-WebView ירד מהעץ וה-controller מת — איפוס הדגל
        // למעלה בונה WebView חדש שטוען מחדש את נקודת הכניסה, במקום
        // לקרוא ל-loadUrl על controller מת שזורק MissingPluginException.
        webViewController = null;
        return;
      }

      await webViewController?.loadUrl(
        urlRequest: URLRequest(url: _entrypointUri),
      );
    } catch (e) {
      webViewController = null;
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

  WebUri get _entrypointUri =>
      pluginEntrypointUri(localHtmlPath, assetScheme: pluginAssetSchemeEnabled);

  /// ה-URL שהטאב הזה ביקש ליצור — מפתח ההתאמה מול אירוע כשל.
  String _expectedCreationUrl() => _entrypointUri.toString();

  Map<String, String>? _lastShortcuts;

  /// מזריק לתוסף את קיצורי הניווט לפי ההגדרה הנוכחית של המשתמש.
  Future<void> _pushHostShortcuts(InAppWebViewController controller) async {
    final shortcuts = context.read<SettingsBloc>().state.shortcuts;
    final list = PluginHostShortcuts.build(shortcuts);
    _hostShortcuts = {for (final s in list) s.id: s};
    _lastShortcuts = Map.of(shortcuts);
    try {
      await controller.evaluateJavascript(
        source: buildSetHostShortcutsScript(list),
      );
    } catch (e) {
      debugPrint('PluginTabPage: host shortcuts inject failed: $e');
    }
  }

  @override
  void dispose() {
    // dispose = unmount רגיל (סגירת טאב) בזמן שהתהליך חי — לא קריסה, מנקים
    // את ה-canary. סגירת האפליקציה לא מריצה dispose; אותה מכסה
    // PluginCrashGuard.markCleanShutdownSync ב-onWindowClose.
    PluginCrashGuard.markLoadSuccessSync(
      widget.plugin.pluginId,
      owner: widget.instanceId,
    );
    _creationWatchdog?.cancel();
    unawaited(_creationFailureSub?.cancel());
    unawaited(_settingsSub?.cancel());
    final pluginId = widget.plugin.pluginId;
    final instanceId = widget.instanceId;
    disposePluginHost(
      onOwnerClosed: () => PluginPageLauncher.instance.markPageClosed(
        pluginId,
        instanceId: instanceId,
      ),
    );
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
                // הסנכרון מחדש מאפשר למופעי הרקע העצלים לקום בלי הפעלה מחדש.
                pluginSystemBloc.add(RefreshPlugins());
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
    final webView = InAppWebView(
      key: _webViewKey,
      webViewEnvironment: WebViewEnvironmentHolder.environment,
      initialUrlRequest: widget.plugin.isLocalhostDev
          ? null
          : URLRequest(url: _entrypointUri),
      onLoadResourceWithCustomScheme: (controller, request) => servePluginAsset(
        url: request.url,
        pluginId: widget.plugin.pluginId,
        rootPath: widget.plugin.resolvedRootPath,
      ),
      initialSettings: buildPluginTabWebViewSettings(
        isDevelopment: widget.plugin.isDevelopment,
      ),
      gestureRecognizers: pluginTabWebViewGestureRecognizers(
        isTouchPlatform: Platform.isAndroid || Platform.isIOS,
      ),
      // Stub SDK — injected BEFORE any page JS runs
      initialUserScripts: UnmodifiableListView<UserScript>([
        UserScript(
          source: pluginSdkStubScript,
          injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
        ),
        buildPluginDropGuardScript(),
        buildPluginLinkifyScript(auto: widget.plugin.manifest.autoLinkify),
      ]),
      onShowFileChooser: verifyPluginFileChooser,
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
        final attached = attachPluginController(controller, _entrypointUri, () {
          controller.addJavaScriptHandler(
            handlerName: 'otzaria_escape_pressed',
            callback: (_) {
              if (!mounted) return;
              if (context.read<SettingsBloc>().state.isFullscreen) {
                FullscreenHelper.toggleFullscreen(context, false);
              }
            },
          );
          controller.addJavaScriptHandler(
            handlerName: 'otzaria_host_shortcut',
            callback: (args) {
              if (!mounted || args.isEmpty) return;
              final shortcut = _hostShortcuts[args.first];
              if (shortcut != null) PluginHostShortcuts.dispatch(shortcut);
            },
          );
        });
        if (!attached) {
          // bridge.register נכשל — התהליך חי, לא קריסה native. מנקים גם את
          // ה-canary של ה-crash guard.
          unawaited(
            PluginCrashGuard.markLoadSuccess(
              widget.plugin.pluginId,
              owner: widget.instanceId,
            ),
          );
          if (mounted) setState(() => _hasError = true);
        }
      },
      onDownloadStarting: PluginDownloadHandler.onDownloadStarting,
      onPermissionRequest: (controller, request) =>
          PluginWebViewPermissionGate.respond(
            plugin: widget.plugin,
            request: request,
            registry: pluginRegistryRepository,
          ),
      // WebView2 מריץ otzaria:// דרך מטפל הפרוטוקול של המערכת אם האירוע אינו
      // מבוטל — עקיפה של המדיניות כאן. הביטול הוא רשת ביטחון בלבד: ההחלטה
      // מתקבלת ב-shouldOverrideUrlLoading, שנורה לפניו.
      onLaunchingExternalUriScheme: (controller, request) async =>
          LaunchingExternalUriSchemeResponse(cancel: true),
      shouldOverrideUrlLoading: (controller, navigationAction) =>
          pluginNavigationPolicy(
            navigationAction,
            onDeepLink: _dispatchPluginDeepLink,
          ),
      shouldInterceptRequest: (controller, request) =>
          interceptPluginRequest(request),
      onLoadStop: (controller, url) async {
        // טעינה מחדש של הדף מאפסת את מצב ה-JS, ואיתו את הדגל שהוא הרים.
        PluginUnsavedChangesRegistry.instance.removeInstance((
          pluginId: widget.plugin.pluginId,
          instanceId: widget.instanceId,
        ));
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
              PluginWebViewHost.cachedPackageInfo ??
              await PackageInfo.fromPlatform();
          if (!mounted) return;
          final permissions = await pluginRegistryRepository
              .getGrantedPermissionNames(widget.plugin.pluginId);
          if (!mounted) return;
          // Real SDK — injected after load, calls _boot() which re-plays queued
          // Otzaria.on() calls and then fires plugin.boot
          await controller.evaluateJavascript(
            source: pluginBootScript(
              runMode: 'foreground',
              packageInfo: packageInfo,
              permissions: permissions,
              theme: theme,
              reader: switch (widget.readerTab) {
                final tab? => PluginTextReaderRegistry.bookPayload(tab),
                null => null,
              },
              fontFaceCss: fontFaceCss,
            ),
          );
          await _pushHostShortcuts(controller);
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
        logPluginProcessFailed(detail);
      },
      onReceivedError: (controller, request, error) {
        // only fail the view for the entrypoint file load itself
        if (request.url.scheme == 'file' ||
            request.url.scheme == pluginAssetScheme) {
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
            isPluginDevServerUri(request.url, widget.plugin.devRootPath)) {
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
      onConsoleMessage: (controller, consoleMessage) =>
          logPluginConsole(consoleMessage),
    );

    // ה-WebView מגיב ללחצן האמצעי בעצמו (Chromium מפעיל שם גלילה אוטומטית
    // משלו), ובלי החסימה היו נפתחים שני עוגנים במקביל.
    return AutoScrollBarrier(
      child: PluginWebViewFocusRestorer(
        onRestore: () => unawaited(
          PluginRuntimeDispatcher.instance.requestKeyboardFocus(
            widget.plugin.pluginId,
            instanceId: widget.instanceId,
          ),
        ),
        child: webView,
      ),
    );
  }

  static bool get _needsWebViewPrerequisites {
    if (kIsWeb) return false;
    // סביבה שכבר אותחלה (מופע רקע או טאב קודם) מייתרת את הבדיקה — ה-FutureBuilder
    // היה עולה פריים ריק שחושף את מסך הכלים. נבדק כאן ולא בדגל סטטי, כדי
    // ש-restart בתוך התהליך (שמאפס את הסביבה) יאתחל אותה מחדש.
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
