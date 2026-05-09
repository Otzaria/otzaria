import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';

enum _PluginRuntimeShutdownMode { idle, restart, exit }

class PluginRuntimeDispatcher {
  static final PluginRuntimeDispatcher instance = PluginRuntimeDispatcher._();
  PluginRuntimeDispatcher._();

  final Map<String, InAppWebViewController> _controllers = {};
  final PluginRegistryRepository _repository = PluginRegistryRepository();
  _PluginRuntimeShutdownMode _shutdownMode = _PluginRuntimeShutdownMode.idle;

  // Cache in-memory למניעת שאילתות SQLite חוזרות במסלול החם
  final Map<String, bool> _enabledCache = {};
  final Map<String, Map<String, bool?>> _permissionCache = {};

  void registerController(String pluginId, InAppWebViewController controller) {
    if (_shutdownMode == _PluginRuntimeShutdownMode.exit) {
      debugPrint(
        'PluginRuntimeDispatcher: ignoring controller registration for $pluginId during app exit',
      );
      return;
    }
    _shutdownMode = _PluginRuntimeShutdownMode.idle;
    _controllers[pluginId] = controller;
  }

  void unregisterController(String pluginId) {
    _controllers.remove(pluginId);
    _enabledCache.remove(pluginId);
    _permissionCache.remove(pluginId);
  }

  /// מנקה את ה-cache של תוסף ספציפי - יש לקרוא כשמשתמש משנה enabled/permissions
  void invalidatePlugin(String pluginId) {
    _enabledCache.remove(pluginId);
    _permissionCache.remove(pluginId);
  }

  final Map<String, Future<void> Function()> _reloadCallbacks = {};

  Future<void> prepareForAppRestart() async {
    await _prepareControllersForTeardown(_PluginRuntimeShutdownMode.restart);
  }

  Future<void> prepareForAppShutdown() async {
    await _prepareControllersForTeardown(_PluginRuntimeShutdownMode.exit);
  }

  Future<void> _prepareControllersForTeardown(
    _PluginRuntimeShutdownMode shutdownMode,
  ) async {
    _shutdownMode = shutdownMode;
    final controllerEntries = _controllers.entries.toList(growable: false);

    _controllers.clear();
    _enabledCache.clear();
    _permissionCache.clear();
    _reloadCallbacks.clear();

    for (final entry in controllerEntries) {
      try {
        await entry.value.loadUrl(
          urlRequest: URLRequest(
            url: WebUri.uri(Uri.parse('about:blank')),
          ),
        );
      } catch (e) {
        // The underlying WebView may already be tearing down.
        debugPrint(
            'PluginRuntimeDispatcher: error during controller teardown for ${entry.key}: $e');
      }
    }
  }

  void registerReloadCallback(
      String pluginId, Future<void> Function() callback) {
    _reloadCallbacks[pluginId] = callback;
  }

  void unregisterReloadCallback(String pluginId) {
    _reloadCallbacks.remove(pluginId);
  }

  Future<void> reloadPlugin(String pluginId) async {
    if (_shutdownMode != _PluginRuntimeShutdownMode.idle) return;
    final callback = _reloadCallbacks[pluginId];
    if (callback != null) {
      await callback();
    }
  }

  Future<void> dispatchEvent(String topic, Map<String, dynamic> payload) async {
    if (_shutdownMode != _PluginRuntimeShutdownMode.idle) return;
    final jsonPayload = jsonEncode(payload);
    debugPrint('PluginRuntimeDispatcher: Dispatching $topic');

    for (final entry in _controllers.entries) {
      final pluginId = entry.key;
      final controller = entry.value;

      try {
        // בדוק שהתוסף מופעל - עם cache למניעת שאילתות SQLite חוזרות
        final isEnabled =
            _enabledCache[pluginId] ?? await _repository.getIsEnabled(pluginId);
        _enabledCache[pluginId] = isEnabled;
        if (!isEnabled) continue;

        // בדוק הרשאה - עם cache
        _permissionCache[pluginId] ??= {};
        final permKey = 'events.subscribe:$topic';
        if (!_permissionCache[pluginId]!.containsKey(permKey)) {
          _permissionCache[pluginId]![permKey] =
              await _repository.getPermission(pluginId, permKey);
        }
        if (_permissionCache[pluginId]![permKey] == true) {
          await controller.evaluateJavascript(
              source:
                  "window.dispatchEvent(new CustomEvent('$topic', { detail: $jsonPayload }));");
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
    if (_shutdownMode != _PluginRuntimeShutdownMode.idle) return;
    final controller = _controllers[pluginId];
    if (controller == null) return;
    try {
      final isEnabled =
          _enabledCache[pluginId] ?? await _repository.getIsEnabled(pluginId);
      _enabledCache[pluginId] = isEnabled;
      if (!isEnabled) return;
      final jsonPayload = jsonEncode(payload);
      await controller.evaluateJavascript(
        source:
            "window.dispatchEvent(new CustomEvent('$topic', { detail: $jsonPayload }));",
      );
    } catch (e) {
      debugPrint('Failed to dispatch $topic to plugin $pluginId: $e');
    }
  }
}
