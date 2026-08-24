import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/models/plugin_network_allowlist.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/services/plugin_network_access_resolver.dart';

/// תוצאת בדיקת הגישה של תוסף ל-URL.
enum PluginNetworkDecision {
  allowed,

  /// המניפסט אינו מצהיר על גישה לרשת.
  notDeclared,

  /// הרשאת הרשת המתאימה ליעד לא הוענקה.
  permissionMissing,

  /// היעד אינו ברשימת ההיתר (המניפסט או הרשימה הרשמית).
  notAllowlisted,
}

/// הבדיקה היחידה של "האם תוסף רשאי לפנות ל-[uri]" — משמשת גם את גשר ה-RPC
/// (network.*) וגם את שערי הניווט/הבקשות של ה-WebView, כדי ששלושת השערים לא
/// ייפרדו זה מזה.
Future<PluginNetworkDecision> evaluatePluginNetworkAccess({
  required Uri uri,
  required String pluginId,
  required PluginManifest manifest,
  required PluginRegistryRepository registry,
}) async {
  if (!manifest.networkEnabled) return PluginNetworkDecision.notDeclared;
  final granted = await registry.getPermission(
    pluginId,
    requiredNetworkPermissionFor(uri),
  );
  if (granted != true) return PluginNetworkDecision.permissionMissing;
  final allowed = await PluginNetworkAccessResolver.instance
      .isUriAllowedForPlugin(uri, manifest);
  return allowed
      ? PluginNetworkDecision.allowed
      : PluginNetworkDecision.notAllowlisted;
}

/// גרסה בוליאנית ל-[evaluatePluginNetworkAccess], לשערים שאין להם מה לומר
/// למשתמש מעבר ל"נחסם".
Future<bool> isPluginNetworkAccessAllowed({
  required Uri uri,
  required String pluginId,
  required PluginManifest manifest,
  required PluginRegistryRepository registry,
}) async =>
    await evaluatePluginNetworkAccess(
      uri: uri,
      pluginId: pluginId,
      manifest: manifest,
      registry: registry,
    ) ==
    PluginNetworkDecision.allowed;
