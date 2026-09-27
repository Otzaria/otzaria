import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_bloc.dart';
import 'package:otzaria/navigation/bloc/navigation_event.dart';
import 'package:otzaria/navigation/bloc/navigation_state.dart';
import 'package:otzaria/plugins/services/plugin_page_launcher.dart';

/// Controls what the reader's "+" (new tab) button opens.
///
/// Registration belongs to the plugin, not to one WebView instance. This is
/// intentional: a startup/background instance may register the target and then
/// be disposed, while the "+" must continue to open the plugin's visible page.
/// A later registration wins; disabling the registration restores the library.
class PluginNewTabPageRegistry {
  static final PluginNewTabPageRegistry instance = PluginNewTabPageRegistry._();
  PluginNewTabPageRegistry._();

  final Map<String, int> _registrations = {};
  int _sequence = 0;

  void register(String pluginId) {
    _registrations[pluginId] = ++_sequence;
  }

  void remove(String pluginId) {
    _registrations.remove(pluginId);
  }

  String? get activePluginId {
    if (_registrations.isEmpty) return null;
    String? selected;
    var newest = -1;
    for (final entry in _registrations.entries) {
      if (entry.value > newest) {
        newest = entry.value;
        selected = entry.key;
      }
    }
    return selected;
  }

  /// Opens the registered plugin page, or the library when none is registered.
  void open(BuildContext context) {
    final pluginId = activePluginId;
    if (pluginId == null) {
      context.read<NavigationBloc>().add(const NavigateToScreen(Screen.library));
      return;
    }
    PluginPageLauncher.instance.open(
      pluginId,
      topic: 'plugin.page_opened',
      payload: const {'source': 'newTabButton'},
    );
  }
}
