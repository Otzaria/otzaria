import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';

class PluginRuntimeDispatcher {
  static final PluginRuntimeDispatcher instance = PluginRuntimeDispatcher._();
  PluginRuntimeDispatcher._();

  final Map<String, InAppWebViewController> _controllers = {};
  final PluginRegistryRepository _repository = PluginRegistryRepository();
  
  void registerController(String pluginId, InAppWebViewController controller) {
    _controllers[pluginId] = controller;
  }
  
  void unregisterController(String pluginId) {
    _controllers.remove(pluginId);
  }

  final Map<String, Future<void> Function()> _reloadCallbacks = {};

  void registerReloadCallback(String pluginId, Future<void> Function() callback) {
    _reloadCallbacks[pluginId] = callback;
  }

  void unregisterReloadCallback(String pluginId) {
    _reloadCallbacks.remove(pluginId);
  }

  Future<void> reloadPlugin(String pluginId) async {
    final callback = _reloadCallbacks[pluginId];
    if (callback != null) {
      await callback();
    }
  }

  Future<void> dispatchEvent(String topic, Map<String, dynamic> payload) async {
    final jsonPayload = jsonEncode(payload);
    debugPrint('PluginRuntimeDispatcher: Dispatching $topic');

    for (final entry in _controllers.entries) {
      final pluginId = entry.key;
      final controller = entry.value;

      try {
        // בדוק שהתוסף מופעל לפני שליחת event
        final isEnabled = await _repository.getIsEnabled(pluginId);
        if (isEnabled == false) continue;

        final granted = await _repository.getPermission(pluginId, 'events.subscribe:$topic');
        if (granted == true) {
          await controller.evaluateJavascript(source: "window.dispatchEvent(new CustomEvent('$topic', { detail: $jsonPayload }));");
        }
      } catch (e) {
        debugPrint('Failed to dispatch $topic to plugin $pluginId: $e');
      }
    }
  }

  /// שולח event לפלאגין ספציפי בלבד (ללא בדיקת הרשאת subscribe).
  /// משמש לאירועים ממוקדים כמו reader.context_menu_item_clicked.
  Future<void> dispatchEventToPlugin(
    String pluginId,
    String topic,
    Map<String, dynamic> payload,
  ) async {
    final controller = _controllers[pluginId];
    if (controller == null) return;
    try {
      final isEnabled = await _repository.getIsEnabled(pluginId);
      if (isEnabled == false) return;
      final jsonPayload = jsonEncode(payload);
      await controller.evaluateJavascript(
        source: "window.dispatchEvent(new CustomEvent('$topic', { detail: $jsonPayload }));",
      );
    } catch (e) {
      debugPrint('Failed to dispatch $topic to plugin $pluginId: $e');
    }
  }
}
