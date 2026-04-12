import 'dart:async';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_rpc_request.dart';
import 'package:otzaria/plugins/models/plugin_rpc_response.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/bridge/plugin_bridge_adapter.dart';
import 'package:otzaria/plugins/storage/plugin_system_database.dart';
import 'package:otzaria/plugins/database/plugin_database_service.dart';

class RateLimiter {
  int tokens = 50;
  DateTime lastRefill = DateTime.now();

  bool consume() {
    final now = DateTime.now();
    final diff = now.difference(lastRefill).inMilliseconds;
    tokens += diff ~/ 10;
    if (tokens > 50) tokens = 50;
    lastRefill = now;
    if (tokens > 0) {
      tokens--;
      return true;
    }
    return false;
  }
}

class PluginBridgeHandler {
  final InstalledPlugin plugin;
  final PluginBridgeAdapter adapter;
  final RateLimiter _rateLimiter = RateLimiter();
  final PluginRegistryRepository _registry;

  PluginBridgeHandler(
    this.plugin, {
    required this.adapter,
    PluginRegistryRepository? registry,
  }) : _registry = registry ?? PluginRegistryRepository();

  void register(InAppWebViewController controller) {
    controller.addJavaScriptHandler(
        handlerName: 'otzaria_rpc', callback: _handleRpc);
  }

  Future<dynamic> _handleRpc(List<dynamic> args) async {
    if (!_rateLimiter.consume()) {
      return _errorResp("error.rate_limited", "Rate limit exceeded");
    }

    if (args.isEmpty) {
      return _errorResp("error.invalid_params", "No arguments provided");
    }

    late final PluginRpcRequest request;
    try {
      request = PluginRpcRequest.fromDynamic(args.first);
    } on FormatException catch (e) {
      return _errorResp("error.invalid_params", e.message);
    }

    if (!request.method.contains('.')) {
      return _errorResp("error.invalid_params", "Invalid method format");
    }

    final parts = request.method.split('.');
    final domain = parts[0];
    final action = parts[1];

    try {
      final requiredPermission = _getRequiredPermission(domain, action);
      if (requiredPermission != null) {
        if (!plugin.manifest.permissions.contains(requiredPermission)) {
          return _errorResp(
              "permission_denied", "Missing permission: $requiredPermission");
        }
        final granted =
            await _registry.getPermission(plugin.pluginId, requiredPermission);
        if (granted != true) {
          return _errorResp(
              "permission_denied", "Permission denied: $requiredPermission");
        }
      }

      // Execute with timeout
      final result = await adapter
          .execute(domain, action, request.payload)
          .timeout(const Duration(seconds: 30));
      return _successResp(result);
    } on PluginDatabaseException catch (e) {
      return _errorResp(e.code, e.message);
    } on TimeoutException {
      PluginSystemDatabase.instance
          .writeLog(plugin.pluginId, 'ERROR', 'RPC timeout: $domain.$action');
      return _errorResp("error.timeout", "Request timed out");
    } catch (e) {
      PluginSystemDatabase.instance
          .writeLog(plugin.pluginId, 'ERROR', 'RPC error $domain.$action: $e');
      return _errorResp("error.internal", e.toString());
    }
  }

  String? _getRequiredPermission(String domain, String action) {
    switch (domain) {
      case 'app':
        if (action == 'getUserEmail') {
          return 'app.user_email.read';
        }
        return 'app.info.read';
      case 'library':
        if (action == 'getBookContent' || action == 'getBookToc') {
          return 'library.content.read';
        }
        return 'library.books.read';
      case 'search':
        return 'search.fulltext.read';
      case 'reader':
        switch (action) {
          case 'addContextMenuItem':
          case 'removeContextMenuItem':
            return 'reader.context_menu';
          case 'setHighlight':
          case 'getHighlights':
          case 'clearHighlight':
          case 'clearAllHighlights':
            return 'reader.highlight';
          default:
            return 'reader.open';
        }
      case 'navigation':
        return 'navigation.write';
      case 'notes':
        if (action == 'add' || action == 'update' || action == 'delete') {
          return 'notes.write';
        }
        return 'notes.read';
      case 'ui':
        return 'ui.feedback';
      case 'storage':
        if (action == 'get' || action == 'list') {
          return 'plugin.storage.read';
        }
        return 'plugin.storage.write';
      case 'settings':
        return 'settings.read';
      case 'calendar':
        return 'calendar.read';
      case 'publishedData':
        return 'published_data.write';
      case 'feedback':
        return 'feedback.send_email';
      case 'history':
        if (action == 'clear' || action == 'remove') {
          return 'history.write';
        }
        return 'history.read';
      case 'notifications':
        if (action == 'showInApp') {
          return 'notifications.send';
        }
        return 'notifications.system';
      case 'database':
        return 'database.read';
      default:
        return null;
    }
  }

  Map<String, dynamic> _successResp(dynamic data) {
    return PluginRpcResponse.success(data).toJson();
  }

  Map<String, dynamic> _errorResp(String code, String message) {
    return PluginRpcResponse.error(code: code, message: message).toJson();
  }
}
