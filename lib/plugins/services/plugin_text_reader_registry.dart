import 'package:flutter/foundation.dart';
import 'package:flutter_settings_screens/flutter_settings_screens.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_book_identity.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/utils/plugin_safe_mode.dart';
import 'package:otzaria/tabs/models/text_tab.dart';
import 'package:otzaria/tabs/models/tool_tab.dart';
import 'package:otzaria/text_book/bloc/text_book_state.dart';
import 'package:otzaria/plugins/services/plugin_runtime_dispatcher.dart';

/// בחירת תוסף כקורא טקסט, עם חזרה לקורא המובנה כשאינו זמין.
class PluginTextReaderRegistry extends ChangeNotifier {
  static final instance = PluginTextReaderRegistry();
  static const settingsKey = 'key-plugin-default-text-reader';
  static const requiredPermissions = {
    'reader.open',
    'library.books.read',
    'library.content.read',
  };

  PluginTextReaderRegistry({
    String? Function()? loadSelection,
    Future<void> Function(String?)? saveSelection,
  }) : _loadSelection = loadSelection ?? _load,
       _saveSelection = saveSelection ?? _save {
    PluginSafeMode.active.addListener(notifyListeners);
  }

  final String? Function() _loadSelection;
  final Future<void> Function(String?) _saveSelection;
  String? _selectedId;
  bool _loaded = false;
  int _revision = 0;
  InstalledPlugin? _active;
  Expando<bool> _nativeTabs = Expando<bool>();
  final Expando<String> _instances = Expando<String>();

  static String? _load() {
    try {
      return Settings.getValue<String>(settingsKey);
    } catch (_) {
      return null;
    }
  }

  static Future<void> _save(String? id) =>
      Settings.setValue<String>(settingsKey, id ?? '');

  String? get selectedPluginId {
    if (!_loaded) {
      _selectedId = _loadSelection();
      _loaded = true;
    }
    return _selectedId;
  }

  InstalledPlugin? get activePlugin => PluginSafeMode.isActive ? null : _active;

  /// ספר עם הגבלת מו"ל נפתח תמיד בקורא הרגיל — התוסף אינו מקבל את הטקסט.
  bool usesPlugin(TextBookTab tab) =>
      activePlugin != null &&
      PluginBookIdentity.typeOf(tab.book) == 'text' &&
      !(tab.bloc.state is TextBookLoaded &&
          ((tab.bloc.state as TextBookLoaded).showPageShapeView ||
              (tab.bloc.state as TextBookLoaded).protection.isProtected)) &&
      _nativeTabs[tab] != true;

  String instanceIdFor(TextBookTab tab) =>
      _instances[tab] ??= 'reader-${ToolTab.newInstanceId()}';

  static Map<String, dynamic> bookPayload(TextBookTab tab) => {
    ...PluginBookIdentity.toJsonWithUid(tab.book),
    'title': tab.book.title,
    'currentIndex': tab.index,
    'searchQuery': switch (tab.bloc.state) {
      TextBookLoaded state => state.searchText,
      _ => tab.searchText,
    },
    'embedded': true,
    'nativeToolbar': true,
    if (tab.bloc.state case final TextBookLoaded state)
      'display': displayPayload(state),
  };

  static Map<String, dynamic> displayPayload(TextBookLoaded state) => {
    'fontSize': state.fontSize,
    'profile': state.bodyDisplayProfile.toPatch().toJson(),
  };

  Future<void> command(TextBookTab tab, String action, {int? direction}) async {
    final plugin = activePlugin;
    if (plugin == null || !usesPlugin(tab)) return;
    await PluginRuntimeDispatcher.instance.dispatchEventToPlugin(
      plugin.pluginId,
      'reader.textReaderCommand',
      {...bookPayload(tab), 'action': action, 'direction': ?direction},
      instanceId: instanceIdFor(tab),
      resumeForegroundIfNeeded: true,
    );
  }

  Future<void> sync(
    List<InstalledPlugin> plugins,
    PluginRegistryRepository repository,
  ) async {
    final id = selectedPluginId;
    final revision = _revision;
    InstalledPlugin? next;
    for (final plugin in plugins) {
      if (plugin.pluginId != id || !plugin.enabled || !plugin.hasToolPage) {
        continue;
      }
      final granted = await repository.getGrantedPermissionNames(id!);
      if (requiredPermissions.every(granted.contains)) next = plugin;
      break;
    }
    if (revision != _revision) return;
    if (!identical(_active, next)) {
      _active = next;
      notifyListeners();
    }
  }

  Future<void> select(InstalledPlugin plugin, bool enabled) async {
    if (!enabled && selectedPluginId != plugin.pluginId) return;
    final id = enabled ? plugin.pluginId : null;
    await _saveSelection(id);
    _revision++;
    _loaded = true;
    _selectedId = id;
    _active = enabled ? plugin : null;
    _nativeTabs = Expando<bool>();
    notifyListeners();
  }

  void useNative(TextBookTab tab) {
    if (_nativeTabs[tab] == true) return;
    _nativeTabs[tab] = true;
    notifyListeners();
  }

  void remove(String pluginId) {
    if (selectedPluginId != pluginId) return;
    _revision++;
    _active = null;
    notifyListeners();
  }

  @override
  void dispose() {
    PluginSafeMode.active.removeListener(notifyListeners);
    super.dispose();
  }
}
