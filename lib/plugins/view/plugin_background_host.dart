import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;

import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/plugins/bloc/plugin_system_bloc.dart';
import 'package:otzaria/plugins/bloc/plugin_system_state.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/plugin_constants.dart';
import 'package:otzaria/plugins/services/plugin_asset_scheme.dart';
import 'package:otzaria/plugins/services/plugin_download_handler.dart';
import 'package:otzaria/plugins/services/plugin_webview_permission_gate.dart';
import 'package:otzaria/plugins/services/plugin_headless_shell.dart';
import 'package:otzaria/plugins/services/plugin_lazy_activation_service.dart';
import 'package:otzaria/plugins/storage/plugin_system_database.dart';
import 'package:otzaria/plugins/view/plugin_drop_guard_script.dart';
import 'package:otzaria/plugins/view/plugin_sdk_scripts.dart';
import 'package:otzaria/plugins/view/plugin_webview_host.dart';
import 'package:otzaria/plugins/view/webview_environment_holder.dart';

/// תקרה רכה למופעי רקע לפי-דרישה: מעליה מפונה הוותיק שאינו keepAlive,
/// אינו באמצע boot ואינו עסוק ב-RPC. כשאין מועמד כזה הסט גדל מעל התקרה.
const int maxOnDemandBackgroundInstances = 4;

/// בוחר מופע רקע לפינוי LRU. חשוף לבדיקות — המדיניות היא הליבה, ואילו
/// ה-widget סביבה דורש עץ ספקים מלא.
@visibleForTesting
String? pickOnDemandEvictionCandidate({
  required Iterable<String> onDemandIds,
  required bool Function(String id) isKeepAlive,
  PluginLazyActivationService? lazyActivation,
}) {
  final ids = onDemandIds.toList(growable: false);
  if (ids.length < maxOnDemandBackgroundInstances) return null;
  final lazy = lazyActivation ?? PluginLazyActivationService.instance;
  for (final id in ids) {
    if (isKeepAlive(id)) continue;
    if (lazy.isBootPending(id)) continue;
    // RPC פתוח (הורדה/חילוץ) — הריגה כאן הייתה משאירה קובץ חלקי.
    if (lazy.isBusy(id)) continue;
    return id;
  }
  return null;
}

/// host נסתר שמחזיק את מופעי הרקע של התוספים — WebView מוסתר (Offstage)
/// שטעון מ-disk ורץ תחת ה-bridge הרגיל.
///
/// מופע קם **לפי דרישה** בלבד, דרך [PluginLazyActivationService]: כשלחיצה
/// או אירוע שהתוסף הצהיר עליו ב-`contributes.startup` באמת קרו.
///
/// ה-instance הזה רשום אצל ה-Dispatcher תחת `instanceId: 'background'`,
/// כך שהוא חי במקביל ל-PluginTabPage רגיל אם המשתמש נכנס למסך "כלים".
class PluginBackgroundHost extends StatefulWidget {
  const PluginBackgroundHost({super.key});

  @override
  State<PluginBackgroundHost> createState() => _PluginBackgroundHostState();
}

class _PluginBackgroundHostState extends State<PluginBackgroundHost> {
  /// המופעים החיים כרגע. שמירת מזהים שאינם משתנים תוך כדי build היא הכרחית
  /// כדי שה-WebView לא ייהרס ויקום מחדש בכל rebuild.
  final Map<String, InstalledPlugin> _activeBackgroundPlugins = {};
  final Map<String, int> _onDemandGenerations = {};

  /// הרשימה האחרונה מהבלוק — נדרשת להפעלה לפי דרישה בין סנכרונים.
  List<InstalledPlugin> _latestPlugins = const [];

  /// האם WebView2 Runtime זמין. ברגע שנמצא זמין הערך נשמר ולא נבדק שוב —
  /// Runtime אינו "נעלם" בזמן ריצה; כל עוד הוא חסר, הבדיקה חוזרת בכל הפעלה.
  bool _runtimeAvailable = false;

  @override
  void initState() {
    super.initState();
    PluginLazyActivationService.instance.backgroundActivator =
        _activateOnDemand;
    PluginLazyActivationService.instance.backgroundDeactivator =
        _deactivateOnDemand;
    // BlocListener מופעל רק על שינויי state. אם הבלוק כבר ב-PluginSystemLoaded
    // כשה-widget נבנה (מסלול נפוץ — LoadPlugins ב-main.dart), הסנכרון לא יופעל.
    // addPostFrameCallback מבטיח שה-context בשל לפני שאנחנו קוראים לבלוק.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final state = context.read<PluginSystemBloc>().state;
      if (state is PluginSystemLoaded) {
        _syncBackgroundPlugins(state.plugins);
      }
    });
  }

  @override
  void dispose() {
    if (identical(
      PluginLazyActivationService.instance.backgroundActivator,
      _activateOnDemand,
    )) {
      PluginLazyActivationService.instance.backgroundActivator = null;
    }
    if (identical(
      PluginLazyActivationService.instance.backgroundDeactivator,
      _deactivateOnDemand,
    )) {
      PluginLazyActivationService.instance.backgroundDeactivator = null;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<PluginSystemBloc, PluginSystemState>(
      listener: (context, state) {
        if (state is PluginSystemLoaded) {
          _syncBackgroundPlugins(state.plugins);
        }
      },
      child: ExcludeFocus(
        // ה-WebView של החבילה עוטף את עצמו ב-Focus(autofocus: true). בלי זה,
        // מופע רקע שנטען כשאין פוקוס באפליקציה חוטף אותו לחלון בלתי-נראה.
        child: Offstage(
          offstage: true,
          child: TickerMode(
            enabled: false,
            child: Stack(
              children: [
                for (final plugin in _activeBackgroundPlugins.values)
                  SizedBox(
                    key: ValueKey(
                      'background_${plugin.pluginId}'
                      '_${plugin.version}'
                      '_${plugin.installPath}'
                      '_${plugin.entrypointPath}'
                      '_${plugin.backgroundEntrypointPath}'
                      '_${plugin.devRootPath ?? ""}',
                    ),
                    width: 1,
                    height: 1,
                    child: _BackgroundPluginRunner(
                      plugin: plugin,
                      activationGeneration:
                          _onDemandGenerations[plugin.pluginId],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// המופעים עצמם קמים רק לפי דרישה; הסנכרון מהבלוק רק מסיר מופע של תוסף
  /// שכובה או הוסר, ומרענן פרטים שהשתנו במופע חי.
  void _syncBackgroundPlugins(List<InstalledPlugin> plugins) {
    _latestPlugins = List<InstalledPlugin>.of(plugins);

    final enabledById = {
      for (final p in plugins.where((p) => p.enabled)) p.pluginId: p,
    };

    final toRemove = _activeBackgroundPlugins.keys
        .where((id) => !enabledById.containsKey(id))
        .toList(growable: false);
    if (toRemove.isNotEmpty) {
      setState(() {
        for (final id in toRemove) {
          _activeBackgroundPlugins.remove(id);
          _onDemandGenerations.remove(id);
        }
      });
    }

    for (final plugin in enabledById.values) {
      _refreshActivePluginDetails(plugin);
    }
  }

  /// אם פרטים על התוסף השתנו (גרסה/נתיב) — מחליפים את הרשומה כך שתשתמש
  /// בנתונים החדשים בלי לאלץ דקונסטרקציה של WebView.
  void _refreshActivePluginDetails(InstalledPlugin plugin) {
    final existing = _activeBackgroundPlugins[plugin.pluginId];
    if (existing == null) return;
    if (existing.version != plugin.version ||
        existing.installPath != plugin.installPath ||
        existing.entrypointPath != plugin.entrypointPath ||
        existing.backgroundEntrypointPath != plugin.backgroundEntrypointPath ||
        existing.devRootPath != plugin.devRootPath) {
      setState(() {
        _activeBackgroundPlugins[plugin.pluginId] = plugin;
      });
    }
  }

  /// מרים מופע רקע לפי דרישה עבור תוסף עם contributes.startup — נקרא ע"י
  /// [PluginLazyActivationService] כשלחיצה/אירוע דורשים מנוע ואין אחד חי.
  /// זריקה כאן מודיעה לשירות לנקות את תור האירועים הממתין.
  Future<void> _activateOnDemand(String pluginId) async {
    if (!mounted) throw StateError('background host is not mounted');
    if (_activeBackgroundPlugins.containsKey(pluginId)) return;
    final lazyActivation = PluginLazyActivationService.instance;
    final activationGeneration = lazyActivation.activationGeneration(pluginId);
    if (!lazyActivation.isActivationCurrent(
      pluginId,
      activationGeneration,
    )) {
      throw StateError('background activation was revoked');
    }
    InstalledPlugin? plugin;
    for (final candidate in _latestPlugins) {
      if (candidate.pluginId == pluginId && candidate.enabled) {
        plugin = candidate;
        break;
      }
    }
    if (plugin == null) {
      throw StateError('plugin $pluginId is not installed or disabled');
    }
    if (!_runtimeAvailable) {
      _runtimeAvailable = await WebViewEnvironmentHolder.isRuntimeAvailable();
      if (!lazyActivation.isActivationCurrent(
        pluginId,
        activationGeneration,
      )) {
        throw StateError('background activation was revoked during init');
      }
      if (!_runtimeAvailable) {
        throw StateError('WebView2 Runtime is not available');
      }
    }
    if (!await _ensureWebViewEnvironment()) {
      throw StateError('WebView2 environment init failed');
    }
    if (!mounted) throw StateError('background host disposed during init');
    if (!lazyActivation.trackIdleTeardown(
      pluginId,
      generation: activationGeneration,
    )) {
      throw StateError('background activation was revoked during init');
    }
    final victim = _onDemandEvictionCandidate();
    setState(() {
      if (victim != null) {
        _onDemandGenerations.remove(victim);
        _activeBackgroundPlugins.remove(victim);
      }
      _onDemandGenerations[pluginId] = activationGeneration;
      _activeBackgroundPlugins[pluginId] = plugin!;
    });
  }

  /// כשמספר מופעי הרקע לפי-דרישה עומד לחצות את התקרה — הוותיק ביותר (סדר
  /// ההפעלה) שאינו keepAlive ואינו באמצע boot, לפינוי. הטריגר הבא יעיר אותו
  /// מחדש. פינוי דרך הסרה מ-Stack → dispose של ה-runner → ניקוי בשירות העצל.
  String? _onDemandEvictionCandidate() => pickOnDemandEvictionCandidate(
    onDemandIds: _activeBackgroundPlugins.keys,
    isKeepAlive: (id) =>
        _activeBackgroundPlugins[id]?.manifest.startup?.keepAlive == true,
  );

  /// מכבה מופע שהוער עצל ולא הראה פעילות — משחרר את תהליכי ה-WebView2.
  /// הטריגר הבא (לחיצה/אירוע) יעיר אותו מחדש בלי לאבד דבר.
  void _deactivateOnDemand(String pluginId) {
    if (!mounted || !_activeBackgroundPlugins.containsKey(pluginId)) return;
    setState(() {
      _onDemandGenerations.remove(pluginId);
      _activeBackgroundPlugins.remove(pluginId);
    });
  }

  /// מאתחל את סביבת WebView2 עם userDataFolder הניתן לכתיבה. בלעדיה WebView2
  /// כותב לתיקיית ברירת מחדל ליד ה-EXE (Program Files = read-only) ונכשל.
  /// נקרא רק כשעומדים באמת להריץ תוסף רקע — האתחול מצמיח תהליכי Edge.
  Future<bool> _ensureWebViewEnvironment() async {
    try {
      await WebViewEnvironmentHolder.initialize();
      return true;
    } catch (e) {
      debugPrint('PluginBackgroundHost: WebView2 environment init failed — $e');
      return false;
    }
  }
}

/// runner פנימי — אחראי על WebView יחיד שטוען תוסף בודד ברקע.
///
/// מקביל ל-PluginTabPage אבל ללא UI גלוי, ללא overlay error, וללא טיפול
/// במצב פיתוח (ה-watcher של dev-plugins ממילא קורא reloadPlugin על שני
/// ה-instances).
class _BackgroundPluginRunner extends StatefulWidget {
  final InstalledPlugin plugin;
  final int? activationGeneration;

  const _BackgroundPluginRunner({
    required this.plugin,
    this.activationGeneration,
  });

  @override
  State<_BackgroundPluginRunner> createState() =>
      _BackgroundPluginRunnerState();
}

class _BackgroundPluginRunnerState extends State<_BackgroundPluginRunner>
    with PluginWebViewHost {
  late String _localHtmlPath;

  @override
  InstalledPlugin get plugin => widget.plugin;
  @override
  String get instanceId => PluginInstanceIds.background;
  @override
  String get logTag => 'Background plugin';

  // דיאלוגים מתוך תוסף-רקע מנותבים דרך ה-navigatorKey הגלובלי
  // כדי שלא יהיו תלויים ב-context של widget מוסתר.
  @override
  BuildContext? get dialogContext => navigatorKey.currentContext;

  @override
  void initState() {
    super.initState();
    // ברקע טוענים את קובץ הרקע הקליל (אם הוצהר) במקום דף הכלים המלא —
    // אין UI גלוי, רק רישומים והאזנה לאירועים. ב-localhost dev השרת מגיש
    // את האפליקציה כולה, ולכן נשארים עם ה-root.
    _localHtmlPath = widget.plugin.isLocalhostDev
        ? widget.plugin.devRootPath!
        : _isHeadless
        ? pluginHeadlessShellPath(widget.plugin.resolvedRootPath)
        : '${widget.plugin.resolvedRootPath}/${widget.plugin.backgroundEntrypointPath}';
    final lazy = PluginLazyActivationService.instance;
    final pluginId = widget.plugin.pluginId;
    initPluginHost(
      onReload: _reloadFromDisk,
      onBackgroundInstanceDone: () => lazy.requestImmediateTeardown(pluginId),
      onWorkStarted: () => lazy.beginWork(pluginId),
      onWorkEnded: () => lazy.endWork(pluginId),
    );
  }

  bool get _usesAssetScheme => pluginUsesAssetScheme(headless: _isHeadless);

  WebUri get _entrypointUri =>
      pluginEntrypointUri(_localHtmlPath, assetScheme: _usesAssetScheme);

  Future<void> _reloadFromDisk() async {
    if (!mounted) return;
    try {
      if (widget.plugin.isLocalhostDev) {
        await InAppWebViewController.clearAllCache();
        await webViewController?.reload();
      } else {
        await webViewController?.loadUrl(
          urlRequest: URLRequest(url: _entrypointUri),
        );
      }
    } catch (e) {
      debugPrint(
        'Background plugin [${widget.plugin.pluginId}] reload error: $e',
      );
    }
  }

  void _onInstanceFailed() =>
      PluginLazyActivationService.instance.onBackgroundInstanceFailed(
        widget.plugin.pluginId,
        generation: widget.activationGeneration,
      );

  @override
  void dispose() {
    final pluginId = widget.plugin.pluginId;
    final generation = widget.activationGeneration;
    disposePluginHost(
      afterAdapter: () => PluginLazyActivationService.instance
          .onBackgroundInstanceClosed(pluginId, generation: generation),
    );
    super.dispose();
  }

  bool get _isHeadless =>
      widget.plugin.manifest.headless && !widget.plugin.isLocalhostDev;

  @override
  Widget build(BuildContext context) {
    final entryFile = _isHeadless
        ? p.join(widget.plugin.resolvedRootPath, widget.plugin.entrypointPath)
        : _localHtmlPath;
    if (!widget.plugin.isLocalhostDev && !File(entryFile).existsSync()) {
      return const SizedBox.shrink();
    }

    if (Platform.isWindows && WebViewEnvironmentHolder.environment == null) {
      return const SizedBox.shrink();
    }

    return InAppWebView(
      webViewEnvironment: WebViewEnvironmentHolder.environment,
      initialUrlRequest: widget.plugin.isLocalhostDev
          ? null
          : URLRequest(url: _entrypointUri),
      onLoadResourceWithCustomScheme: (controller, request) => servePluginAsset(
        url: request.url,
        pluginId: widget.plugin.pluginId,
        rootPath: widget.plugin.resolvedRootPath,
        headlessEntrypoint: _isHeadless ? widget.plugin.entrypointPath : null,
      ),
      initialSettings: InAppWebViewSettings(
        allowFileAccessFromFileURLs: false,
        allowUniversalAccessFromFileURLs: false,
        useShouldOverrideUrlLoading: true,
        useShouldInterceptRequest: true,
        useOnDownloadStart: PluginDownloadHandler.isSupported,
        // ב-Windows ה-status bar של WebView2 מציג את ה-URI בריחוף על קישור
        // ומאפשר לתוסף לכתוב לשם טקסט חופשי (window.status).
        statusBarEnabled: false,
        cacheEnabled: !widget.plugin.isDevelopment,
        isInspectable: kDebugMode,
        resourceCustomSchemes: _usesAssetScheme
            ? const [pluginAssetScheme]
            : const [],
      ),
      initialUserScripts: UnmodifiableListView<UserScript>([
        UserScript(
          source: pluginBackgroundSdkStubScript,
          injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
        ),
        buildPluginDropGuardScript(),
      ]),
      onShowFileChooser: verifyPluginFileChooser,
      onDownloadStarting: PluginDownloadHandler.onDownloadStarting,
      onPermissionRequest: (controller, request) =>
          PluginWebViewPermissionGate.respond(
            plugin: widget.plugin,
            request: request,
            registry: pluginRegistryRepository,
          ),
      onWebViewCreated: (controller) {
        if (!attachPluginController(controller, _entrypointUri)) {
          _onInstanceFailed();
        }
      },
      onProcessFailed: (controller, detail) {
        // תוסף רקע מוסתר — בלי הרישום אין לכשל הזה שום עדות נראית.
        logPluginProcessFailed(detail);
        _onInstanceFailed();
      },
      // מופע רקע אינו מציג ממשק ואין בו לחיצת משתמש — otzaria:// לעולם אינו
      // מגיע למטפל הפרוטוקול של המערכת.
      onLaunchingExternalUriScheme: (controller, request) async =>
          LaunchingExternalUriSchemeResponse(cancel: true),
      shouldOverrideUrlLoading: (controller, navigationAction) {
        // רשת דפדפנית ישירה (fetch רגיל) אינה עוברת ב-Bridge — נספרת
        // כפעילות כאן, כדי שהכיבוי העצל לא יקטע בקשה ארוכה.
        PluginLazyActivationService.instance.notifyActivity(
          widget.plugin.pluginId,
        );
        return pluginNavigationPolicy(navigationAction);
      },
      shouldInterceptRequest: (controller, request) {
        PluginLazyActivationService.instance.notifyActivity(
          widget.plugin.pluginId,
        );
        return interceptPluginRequest(request, headless: _isHeadless);
      },
      onLoadStop: (controller, url) async {
        try {
          final theme = currentThemePayload();
          final packageInfo =
              PluginWebViewHost.cachedPackageInfo ??
              await PackageInfo.fromPlatform();
          final permissions = await pluginRegistryRepository
              .getGrantedPermissionNames(widget.plugin.pluginId);
          await controller.evaluateJavascript(
            source: pluginBootScript(
              runMode: 'background',
              packageInfo: packageInfo,
              permissions: permissions,
              theme: theme,
            ),
          );
          // המופע מוכן — מוסר אירועים שהמתינו להפעלה עצלה (contributes.startup).
          unawaited(
            PluginLazyActivationService.instance.onBackgroundInstanceReady(
              widget.plugin.pluginId,
              generation: widget.activationGeneration,
            ),
          );
        } catch (e, st) {
          debugPrint(
            'Background plugin [${widget.plugin.pluginId}] boot error: $e\n$st',
          );
          PluginSystemDatabase.instance.writeLog(
            widget.plugin.pluginId,
            'ERROR',
            'Background boot failed: $e',
          );
          _onInstanceFailed();
        }
      },
      onConsoleMessage: (controller, consoleMessage) =>
          logPluginConsole(consoleMessage, prefix: '[background] '),
    );
  }
}
