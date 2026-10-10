import 'package:flutter/foundation.dart';
import 'package:otzaria/plugins/services/plugin_page_launcher.dart';

/// Controls what the reader's "+" (new tab) button opens.
///
/// Registration belongs to the plugin, not to one WebView instance. This is
/// intentional: a startup/background instance may register the target and then
/// be disposed, while the "+" must continue to open the plugin's visible page.
/// The first plugin to register owns the button exclusively until it unregisters.
/// Competing registrations are rejected rather than queued for a later takeover.
/// When the owner unregisters, the new-tab button is hidden.
class PluginNewTabPageRegistry extends ChangeNotifier {
  static final PluginNewTabPageRegistry instance = PluginNewTabPageRegistry._();
  PluginNewTabPageRegistry._();

  String? _activePluginId;

  /// Returns false when another plugin already owns the new-tab button.
  /// Re-registering the current owner is an idempotent success.
  bool register(String pluginId) {
    if (_activePluginId == pluginId) return true;
    if (_activePluginId != null) return false;
    _activePluginId = pluginId;
    notifyListeners();
    return true;
  }

  void remove(String pluginId) {
    if (_activePluginId != pluginId) return;
    _activePluginId = null;
    notifyListeners();
  }

  bool get hasActiveRegistration => _activePluginId != null;

  String? get activePluginId => _activePluginId;

  /// Opens the registered plugin page. With no registration the button is hidden.
  void open() {
    final pluginId = activePluginId;
    if (pluginId == null) return;
    PluginPageLauncher.instance.open(
      pluginId,
      topic: 'plugin.page_opened',
      payload: const {'source': 'newTabButton'},
    );
  }
}
