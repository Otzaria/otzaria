import 'package:otzaria/bookmarks/bloc/bookmark_bloc.dart';
import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;

import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/core/connectivity_status_service.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/history/bloc/history_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/personal_notes/repository/personal_notes_repository.dart';
import 'package:otzaria/settings/engine/settings_repository.dart';
import 'package:otzaria/settings/l10n/settings_language.dart';
import 'package:otzaria/plugins/bloc/plugin_system_bloc.dart';
import 'package:otzaria/plugins/bloc/plugin_system_event.dart';
import 'package:otzaria/plugins/bloc/plugin_system_state.dart';
import 'package:otzaria/plugins/bridge/plugin_bridge_adapter.dart';
import 'package:otzaria/plugins/bridge/plugin_bridge_handler.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/plugin_constants.dart';
import 'package:otzaria/plugins/models/plugin_valid_permissions.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/services/plugin_download_handler.dart';
import 'package:otzaria/plugins/services/plugin_file_server.dart';
import 'package:otzaria/plugins/services/plugin_ref_line_resolver.dart';
import 'package:otzaria/plugins/services/plugin_lazy_activation_service.dart';
import 'package:otzaria/plugins/services/plugin_runtime_dispatcher.dart';
import 'package:otzaria/plugins/storage/plugin_system_database.dart';
import 'package:otzaria/plugins/view/plugin_drop_guard_script.dart';
import 'package:otzaria/plugins/services/plugin_webview_failure_log.dart';
import 'package:otzaria/plugins/services/plugin_network_gate.dart';
import 'package:otzaria/plugins/view/webview_environment_holder.dart';
import 'package:otzaria/search/search_repository.dart';
import 'package:otzaria/tabs/bloc/tabs_bloc.dart';
import 'package:otzaria/tools/calendar/utils/calendar_cubit.dart';
import 'package:otzaria/find_ref/repository/find_ref_factory.dart';
import 'package:otzaria/utils/navigation/book_open_coordinator.dart';
import 'package:file_picker/file_picker.dart';
import 'package:otzaria/settings/services/safer_mode_guard.dart';
import 'package:otzaria/widgets/dialogs/dialogs_exports.dart';
import 'package:otzaria/workspaces/bloc/workspace_bloc.dart';

// Restricts localhost access to the exact dev server origin (host + scheme + port).
bool _isDevServerUri(Uri uri, String? devRootPath) {
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

/// Stub SDK זהה ל-plugin_tab_page — מבטיח שכל קריאת `Otzaria.on()` שמופעלת
/// לפני שה-SDK האמיתי מוזרק נשמרת בתור עד ל-_boot.
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
    _boot: function (sdk, payload) {
      _realSdk = sdk;
      // סמן חיוּת לדיספצ'ר — ראו plugin_tab_page.dart.
      window.Otzaria._booted = true;
      _queue.forEach(function (item) { sdk.on(item.event, item.cb); });
      _queue = [];
      window.dispatchEvent(new CustomEvent('plugin.boot', { detail: payload }));
      window.dispatchEvent(new CustomEvent('plugin.ready', { detail: null }));
    }
  };

  window.open = function () {
    console.error('window.open is locked for security.');
    return null;
  };
})();
''';

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

/// host נסתר שמטעין תוספים ברקע עם עליית האפליקציה.
///
/// לוקח מ-PluginSystemBloc את רשימת התוספים הפעילים, מסנן את אלה שקיבלו
/// את הרשאת [pluginRunOnStartupPermission], ומחזיק עבור כל אחד מהם
/// WebView מוסתר (Offstage) שטעון מ-disk וריצה תחת אותו bridge רגיל.
///
/// בנוסף משרת את המנגנון החדש (`contributes.startup`): מרים מופע רקע
/// **לפי דרישה** דרך [PluginLazyActivationService] — רק כשלחיצה או אירוע
/// שהתוסף הצהיר עליו באמת קרו, במקום מנוע שחי מהעלייה.
///
/// TODO(0.9.98): להסיר את מסלול app.run_on_startup (הטעינה בעלייה) — יישאר
/// רק המסלול לפי-דרישה; למחוק אז גם את מדריך המעבר ב-API_REFERENCE.md.
///
/// ה-instance הזה רשום אצל ה-Dispatcher תחת `instanceId: 'background'`,
/// כך שהוא חי במקביל ל-PluginTabPage רגיל אם המשתמש נכנס למסך "כלים".
class PluginBackgroundHost extends StatefulWidget {
  const PluginBackgroundHost({super.key});

  @override
  State<PluginBackgroundHost> createState() => _PluginBackgroundHostState();
}

class _PluginBackgroundHostState extends State<PluginBackgroundHost> {
  final PluginRegistryRepository _registry = PluginRegistryRepository();

  /// תוספים שהוטענו ברקע כרגע. שמירת מזהים שאינם משתנים תוך כדי build
  /// היא הכרחית כדי שה-WebView לא ייהרס ויקום מחדש בכל rebuild.
  final Map<String, InstalledPlugin> _activeBackgroundPlugins = {};

  /// מופעים שהורמו לפי דרישה (contributes.startup) — אינם כפופים לתנאי
  /// הרשאת run_on_startup של מסלול העלייה, ולכן הסנכרון מדלג עליהם.
  final Set<String> _onDemandPluginIds = {};
  final Map<String, int> _onDemandGenerations = {};

  /// הרשימה האחרונה מהבלוק — נדרשת להפעלה לפי דרישה בין סנכרונים.
  List<InstalledPlugin> _latestPlugins = const [];

  /// תוספים שכבר טעננו בהם את ההרשאה מ-SQLite אך עוד לא הוחלט עליהם.
  /// משמש כדי למנוע בקשות חוזרות מקבילות.
  final Set<String> _pluginsBeingEvaluated = {};

  /// הסנכרון אסינכרוני (בדיקת Runtime והרשאות ב-SQLite). התקנה/עדכון יכולים
  /// להגיע בזמן שסנכרון קודם עדיין רץ. במקום לדלג על הרשימה החדשה, שומרים את
  /// הרשימה העדכנית ומעבדים אותה מיד לאחר הסבב הנוכחי.
  List<InstalledPlugin>? _pendingPlugins;
  bool _syncInProgress = false;

  /// האם WebView2 Runtime זמין. ברגע שנמצא זמין הערך נשמר ולא נבדק שוב —
  /// Runtime אינו "נעלם" בזמן ריצה. אך כל עוד הוא חסר, הבדיקה חוזרת בכל
  /// סנכרון: כך אם המשתמש מתקין WebView2 בזמן שהאפליקציה פתוחה, הסנכרון
  /// הבא (למשל RefreshPlugins מכפתור "בדוק שוב" בטאב) יחזיר את תוספי הרקע
  /// לפעולה בלי צורך בהפעלה מחדש.
  bool _runtimeAvailable = false;
  bool _loggedRuntimeMissing = false;

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
        _queueBackgroundSync(state.plugins);
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
          _queueBackgroundSync(state.plugins);
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

  void _queueBackgroundSync(List<InstalledPlugin> plugins) {
    _latestPlugins = List<InstalledPlugin>.of(plugins);
    _pendingPlugins = List<InstalledPlugin>.of(plugins);
    if (_syncInProgress) return;
    unawaited(_drainBackgroundSyncQueue());
  }

  Future<void> _drainBackgroundSyncQueue() async {
    _syncInProgress = true;
    try {
      while (mounted && _pendingPlugins != null) {
        final plugins = _pendingPlugins!;
        _pendingPlugins = null;
        await _syncBackgroundPlugins(plugins);
      }
    } finally {
      _syncInProgress = false;
      // רשימה יכולה להגיע בדיוק בין תנאי ה-while ל-finally.
      if (mounted && _pendingPlugins != null) {
        _queueBackgroundSync(_pendingPlugins!);
      }
    }
  }

  Future<void> _syncBackgroundPlugins(List<InstalledPlugin> plugins) async {
    // ללא WebView2 Runtime (Windows) בניית ה-WebView המוסתר נכשלת. מדלגים
    // על כל תוספי הרקע — הם יוצגו עם מסך ההכוונה כשהמשתמש יפתח אותם ידנית.
    // כל עוד ה-Runtime חסר בודקים מחדש בכל סנכרון, כדי שהתקנה תוך כדי ריצה
    // תחזיר את תוספי הרקע בסנכרון הבא.
    if (!_runtimeAvailable) {
      _runtimeAvailable = await WebViewEnvironmentHolder.isRuntimeAvailable();
      if (!mounted) return;
      if (!_runtimeAvailable) {
        if (!_loggedRuntimeMissing) {
          _loggedRuntimeMissing = true;
          debugPrint(
            'PluginBackgroundHost: WebView2 Runtime missing — '
            'skipping background plugins',
          );
        }
        return;
      }
    }

    final enabledById = {
      for (final p in plugins.where((p) => p.enabled)) p.pluginId: p,
    };

    // הסרת תוספים שכבר לא מופעלים או הוסרו
    final toRemove = _activeBackgroundPlugins.keys
        .where((id) => !enabledById.containsKey(id))
        .toList(growable: false);
    if (toRemove.isNotEmpty) {
      setState(() {
        for (final id in toRemove) {
          _activeBackgroundPlugins.remove(id);
          _onDemandPluginIds.remove(id);
        }
      });
    }

    // עבור כל תוסף enabled — בדוק האם ההרשאה ל-startup הוענקה
    for (final plugin in enabledById.values) {
      // מופע לפי-דרישה (contributes.startup) אינו כפוף למסלול run_on_startup;
      // רק מרעננים את פרטי התוסף אם השתנו.
      if (_onDemandPluginIds.contains(plugin.pluginId)) {
        _refreshActivePluginDetails(plugin);
        continue;
      }
      // תוסף שהצהיר contributes.startup עבר למנגנון החדש — המנוע שלו קם
      // עצל בלבד (לחיצה/אירוע/app.startup), לא במסלול הטעינה-בעלייה הישן.
      final startup = plugin.manifest.startup;
      if (startup != null && !startup.isEmpty) {
        if (_activeBackgroundPlugins.containsKey(plugin.pluginId)) {
          setState(() {
            _activeBackgroundPlugins.remove(plugin.pluginId);
          });
        }
        continue;
      }
      // לא שולחים לרקע תוסף שלא הצהיר על ההרשאה ב-manifest
      if (!plugin.manifest.permissions.contains(pluginRunOnStartupPermission)) {
        if (_activeBackgroundPlugins.containsKey(plugin.pluginId)) {
          setState(() {
            _activeBackgroundPlugins.remove(plugin.pluginId);
          });
        }
        continue;
      }

      if (_pluginsBeingEvaluated.contains(plugin.pluginId)) continue;
      _pluginsBeingEvaluated.add(plugin.pluginId);
      try {
        final granted = await _registry.getPermission(
          plugin.pluginId,
          pluginRunOnStartupPermission,
        );
        if (!mounted) return;
        final shouldRun = granted == true;
        final isRunning = _activeBackgroundPlugins.containsKey(plugin.pluginId);
        if (shouldRun && !isRunning) {
          if (!await _ensureWebViewEnvironment()) return;
          if (!mounted) return;
          setState(() {
            _activeBackgroundPlugins[plugin.pluginId] = plugin;
          });
        } else if (!shouldRun && isRunning) {
          setState(() {
            _activeBackgroundPlugins.remove(plugin.pluginId);
          });
        } else if (shouldRun && isRunning) {
          _refreshActivePluginDetails(plugin);
        }
      } finally {
        _pluginsBeingEvaluated.remove(plugin.pluginId);
      }
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
        _onDemandPluginIds.remove(victim);
        _onDemandGenerations.remove(victim);
        _activeBackgroundPlugins.remove(victim);
      }
      _onDemandPluginIds.add(pluginId);
      _onDemandGenerations[pluginId] = activationGeneration;
      _activeBackgroundPlugins[pluginId] = plugin!;
    });
  }

  /// כשמספר מופעי הרקע לפי-דרישה עומד לחצות את התקרה — הוותיק ביותר (סדר
  /// ההפעלה) שאינו keepAlive ואינו באמצע boot, לפינוי. הטריגר הבא יעיר אותו
  /// מחדש. פינוי דרך הסרה מ-Stack → dispose של ה-runner → ניקוי בשירות העצל.
  String? _onDemandEvictionCandidate() => pickOnDemandEvictionCandidate(
    onDemandIds: _onDemandPluginIds,
    isKeepAlive: (id) =>
        _activeBackgroundPlugins[id]?.manifest.startup?.keepAlive == true,
  );

  /// מכבה מופע שהוער עצל ולא הראה פעילות — משחרר את תהליכי ה-WebView2.
  /// הטריגר הבא (לחיצה/אירוע) יעיר אותו מחדש בלי לאבד דבר.
  void _deactivateOnDemand(String pluginId) {
    if (!mounted || !_onDemandPluginIds.contains(pluginId)) return;
    setState(() {
      _onDemandPluginIds.remove(pluginId);
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

class _BackgroundPluginRunnerState extends State<_BackgroundPluginRunner> {
  static PackageInfo? _cachedPackageInfo;

  InAppWebViewController? _controller;
  late final PluginBridgeHandler _bridge;
  late final PluginBridgeAdapter _adapter;
  late final PluginRegistryRepository _pluginRegistryRepository;
  late final PluginSystemBloc _pluginSystemBloc;
  late String _localHtmlPath;

  /// נתיב שרת הקבצים הוא `/f/<pluginId>/<token>` — תוסף רקע מורשה רק בשלו.
  bool _isOwnFileServerPath(Uri uri) =>
      uri.pathSegments.length == 3 &&
      uri.pathSegments[1] == widget.plugin.pluginId;

  Future<bool> _isNetworkUriAllowed(Uri uri) => isPluginNetworkAccessAllowed(
    uri: uri,
    pluginId: widget.plugin.pluginId,
    manifest: widget.plugin.manifest,
    registry: _pluginRegistryRepository,
  );

  @override
  void initState() {
    super.initState();
    _pluginSystemBloc = context.read<PluginSystemBloc>();
    // ברקע טוענים את קובץ הרקע הקליל (אם הוצהר) במקום דף הכלים המלא —
    // אין UI גלוי, רק רישומים והאזנה לאירועים. ב-localhost dev השרת מגיש
    // את האפליקציה כולה, ולכן נשארים עם ה-root.
    _localHtmlPath = widget.plugin.isLocalhostDev
        ? widget.plugin.devRootPath!
        : '${widget.plugin.resolvedRootPath}/${widget.plugin.backgroundEntrypointPath}';

    final historyBloc = context.read<HistoryBloc>();
    final tabsBloc = context.read<TabsBloc>();
    final navigationBloc = context.read<NavigationBloc>();
    final calendarCubit = context.read<CalendarCubit>();
    final workspaceBloc = context.read<WorkspaceBloc>();
    final bookmarkBloc = context.read<BookmarkBloc>();
    final searchRepository = SearchRepository();
    final personalNotesRepository = PersonalNotesRepository();
    final pluginRegistryRepository = PluginRegistryRepository();
    final findRefRepository = buildFindRefRepository();

    final dependencies = PluginBridgeDependencies(
      historyBloc: historyBloc,
      tabsBloc: tabsBloc,
      navigationBloc: navigationBloc,
      calendarCubit: calendarCubit,
      workspaceBloc: workspaceBloc,
      bookmarkBloc: bookmarkBloc,
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
      // דיאלוגים מתוך תוסף-רקע מנותבים דרך ה-navigatorKey הגלובלי
      // כדי שלא יהיו תלויים ב-context של widget מוסתר.
      showConfirmDialog:
          ({
            required String title,
            required String content,
          }) async {
            final ctx = navigatorKey.currentContext;
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
            final ctx = navigatorKey.currentContext;
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
        _pluginSystemBloc.add(
          InstallRemotePluginRequested(
            downloadUrl,
            reportContext: reportContext,
                      storeOnly: true,
          ),
        );
      },
      pickFolder: ({String? title}) async {
        final ctx = navigatorKey.currentContext;
        if (ctx == null) return null;
        if (!await verifySaferModePassword(ctx)) return null;
        return FilePicker.getDirectoryPath(
          lockParentWindow: true,
          dialogTitle: title,
        );
      },
      onBackgroundInstanceDone: () => PluginLazyActivationService.instance
          .requestImmediateTeardown(widget.plugin.pluginId),
      pickFile: ({List<String>? allowedExtensions, String? title}) async {
        final ctx = navigatorKey.currentContext;
        if (ctx == null) return null;
        if (!await verifySaferModePassword(ctx)) return null;
        final hasExtensions =
            allowedExtensions != null && allowedExtensions.isNotEmpty;
        final result = await FilePicker.pickFiles(
          dialogTitle: title,
          lockParentWindow: true,
          type: hasExtensions ? FileType.custom : FileType.any,
          allowedExtensions: hasExtensions ? allowedExtensions : null,
        );
        return result?.files.single.path;
      },
    );

    _pluginRegistryRepository = pluginRegistryRepository;
    _adapter = PluginBridgeAdapter(
      widget.plugin,
      dependencies: dependencies,
      instanceId: PluginInstanceIds.background,
      pluginRepository: pluginRegistryRepository,
    );
    _bridge = PluginBridgeHandler(
      widget.plugin,
      adapter: _adapter,
      registry: pluginRegistryRepository,
      onWorkStarted: () => PluginLazyActivationService.instance.beginWork(
        widget.plugin.pluginId,
      ),
      onWorkEnded: () => PluginLazyActivationService.instance.endWork(
        widget.plugin.pluginId,
      ),
    );
    _ensurePackageInfo();

    PluginRuntimeDispatcher.instance.registerReloadCallback(
      widget.plugin.pluginId,
      _reloadFromDisk,
      instanceId: PluginInstanceIds.background,
      token: this,
    );
  }

  Future<void> _ensurePackageInfo() async {
    _cachedPackageInfo ??= await PackageInfo.fromPlatform();
  }

  Future<void> _reloadFromDisk() async {
    if (!mounted) return;
    try {
      if (widget.plugin.isLocalhostDev) {
        await InAppWebViewController.clearAllCache();
        await _controller?.reload();
      } else {
        await _controller?.loadUrl(
          urlRequest: URLRequest(url: WebUri.uri(Uri.file(_localHtmlPath))),
        );
      }
    } catch (e) {
      debugPrint(
        'Background plugin [${widget.plugin.pluginId}] reload error: $e',
      );
    }
  }

  @override
  void dispose() {
    final pluginId = widget.plugin.pluginId;
    final generation = widget.activationGeneration;
    final controller = _controller;
    // העץ נעול בזמן dispose וניקוי הרישומים מודיע ל-ListenableBuilders
    // (הדגשות, סרגל כלים) — לכן נדחה למיקרוטסק, אחרי שחרור הנעילה.
    scheduleMicrotask(() {
      _adapter.dispose();
      PluginLazyActivationService.instance.onBackgroundInstanceClosed(
        pluginId,
        generation: generation,
      );
      if (PluginRuntimeDispatcher.instance.ownsController(
        pluginId,
        controller,
        instanceId: PluginInstanceIds.background,
      )) {
        PluginRuntimeDispatcher.instance.unregisterController(
          pluginId,
          instanceId: PluginInstanceIds.background,
        );
      }
      PluginRuntimeDispatcher.instance.unregisterReloadCallback(
        pluginId,
        instanceId: PluginInstanceIds.background,
        token: this,
      );
    });
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.plugin.isLocalhostDev && !File(_localHtmlPath).existsSync()) {
      return const SizedBox.shrink();
    }

    if (Platform.isWindows && WebViewEnvironmentHolder.environment == null) {
      return const SizedBox.shrink();
    }

    return InAppWebView(
      webViewEnvironment: WebViewEnvironmentHolder.environment,
      initialUrlRequest: URLRequest(
        url: widget.plugin.isLocalhostDev
            ? WebUri(_localHtmlPath)
            : WebUri.uri(Uri.file(_localHtmlPath)),
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
      ),
      initialUserScripts: UnmodifiableListView<UserScript>([
        UserScript(
          source: _sdkStub,
          injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
        ),
        buildPluginDropGuardScript(),
      ]),
      onDownloadStarting: PluginDownloadHandler.onDownloadStarting,
      onWebViewCreated: (controller) {
        try {
          _controller = controller;
          PluginRuntimeDispatcher.instance.registerController(
            widget.plugin.pluginId,
            controller,
            instanceId: PluginInstanceIds.background,
          );
          _bridge.register(controller);
        } catch (e) {
          PluginRuntimeDispatcher.instance.unregisterController(
            widget.plugin.pluginId,
            instanceId: PluginInstanceIds.background,
          );
          debugPrint(
            'Background plugin [${widget.plugin.pluginId}] init error: $e',
          );
          PluginLazyActivationService.instance.onBackgroundInstanceFailed(
            widget.plugin.pluginId,
            generation: widget.activationGeneration,
          );
        }
      },
      onProcessFailed: (controller, detail) {
        // תוסף רקע מוסתר — בלי הרישום אין לכשל הזה שום עדות נראית.
        logPluginWebViewFailure(
          'Background plugin WebView2 process failed',
          detail.kind,
          details: {
            'Plugin': widget.plugin.pluginId,
            'Reason': detail.reason?.toString(),
            'ExitCode': detail.exitCode?.toString(),
            'Process': detail.processDescription,
          },
        );
        PluginLazyActivationService.instance.onBackgroundInstanceFailed(
          widget.plugin.pluginId,
          generation: widget.activationGeneration,
        );
      },
      shouldOverrideUrlLoading: (controller, navigationAction) async {
        // רשת דפדפנית ישירה (fetch רגיל) אינה עוברת ב-Bridge — נספרת
        // כפעילות כאן, כדי שהכיבוי העצל לא יקטע בקשה ארוכה.
        PluginLazyActivationService.instance.notifyActivity(
          widget.plugin.pluginId,
        );
        try {
          final uri = navigationAction.request.url;
          if (uri == null) return NavigationActionPolicy.CANCEL;
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
              _isDevServerUri(uri, widget.plugin.devRootPath)) {
            return NavigationActionPolicy.ALLOW;
          }
          // שרת הקבצים הפנימי (loopback) — הפורט אקראי ולכן אינו ניתן
          // להצהרה ב-allowlist; מאשרים רק נתיב של התוסף עצמו.
          if (uri.scheme == 'http' &&
              PluginFileServer.instance.isServerUri(uri)) {
            return _isOwnFileServerPath(uri)
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
            'Background plugin [${widget.plugin.pluginId}] URL override error: $e',
          );
          return NavigationActionPolicy.CANCEL;
        }
      },
      shouldInterceptRequest: (controller, request) async {
        PluginLazyActivationService.instance.notifyActivity(
          widget.plugin.pluginId,
        );
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
              _isDevServerUri(uri, widget.plugin.devRootPath)) {
            return null; // allow dev server + HMR requests
          }
          if (uri.scheme == 'http' &&
              PluginFileServer.instance.isServerUri(uri)) {
            if (_isOwnFileServerPath(uri)) return null;
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
            'Background plugin [${widget.plugin.pluginId}] intercept request error: $e',
          );
          return WebResourceResponse(
            statusCode: 403,
            reasonPhrase: 'Forbidden',
          );
        }
      },
      onLoadStop: (controller, url) async {
        try {
          final theme = mounted
              ? buildThemePayload(context)
              : <String, dynamic>{
                  'mode': 'light',
                  'colorScheme': <String, dynamic>{},
                  'typography': <String, dynamic>{},
                };
          final packageInfo =
              _cachedPackageInfo ?? await PackageInfo.fromPlatform();
          final permissions = await _pluginRegistryRepository
              .getGrantedPermissionNames(
                widget.plugin.pluginId,
              );
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
              // סימון לתוסף שהוא רץ ברקע — מאפשר לקוד התוסף להתנהג אחרת
              // (למשל לא לבצע ניווט יזום) כשאין UI גלוי.
              'runMode': 'background',
              // חושף לתוסף אם הוא נטען כתוסף פיתוח (sourceType=development).
              // בתוסף ארוז זה false.
              'devMode': widget.plugin.isDevelopment,
            },
            'connectivity': ConnectivityStatusService.instance.bootPayload(),
            'theme': theme,
            'permissions': permissions,
          };
          final jsonPayload = jsonEncode(bootPayload);
          final nonceJson = jsonEncode(_bridge.bridgeNonce);
          await controller.evaluateJavascript(
            source:
                '''
(function () {
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
          PluginLazyActivationService.instance.onBackgroundInstanceFailed(
            widget.plugin.pluginId,
            generation: widget.activationGeneration,
          );
        }
      },
      onConsoleMessage: (controller, consoleMessage) {
        try {
          if (consoleMessage.messageLevel == ConsoleMessageLevel.ERROR ||
              consoleMessage.messageLevel == ConsoleMessageLevel.WARNING) {
            PluginSystemDatabase.instance.writeLog(
              widget.plugin.pluginId,
              consoleMessage.messageLevel.toString(),
              '[background] ${consoleMessage.message}',
            );
          }
          debugPrint(
            'Background plugin [${widget.plugin.pluginId}]: ${consoleMessage.message}',
          );
        } catch (_) {}
      },
    );
  }
}
