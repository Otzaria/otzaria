import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/plugins/bloc/plugin_system_bloc.dart';
import 'package:otzaria/plugins/bloc/plugin_system_event.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_valid_permissions.dart';

const String _networkLocalhostPermission = 'network.localhost';

/// פעולות על תוסף בודד — משותפות לפאנל הצד וללוח ניהול הכלים בהגדרות.
/// (דיאלוג ההרשאות והמחיקה משותפים ב-plugin_settings_screen.dart).

/// מחליף את מצב הצגת [plugin] בלשונית הכלים (הסתרה/הצגה).
void togglePluginShowInTools(BuildContext context, InstalledPlugin plugin) {
  context.read<PluginSystemBloc>().add(
    SetPluginShowInToolsRequested(
      pluginId: plugin.pluginId,
      showInTools: !plugin.showInTools,
    ),
  );
}

/// מחליף את הצמדת [plugin] לסרגל הניווט הראשי (הצמדה/הסרה).
void togglePluginPinnedToNavRail(BuildContext context, InstalledPlugin plugin) {
  final bloc = context.read<PluginSystemBloc>();
  bloc.add(
    plugin.pinnedToNavRail
        ? UnpinPluginFromNavRailRequested(plugin.pluginId)
        : PinPluginToNavRailRequested(plugin.pluginId),
  );
}

/// מחליף את מצב הפעילות של [plugin] (השבתה/הפעלה).
void togglePluginEnabled(BuildContext context, InstalledPlugin plugin) {
  final bloc = context.read<PluginSystemBloc>();
  bloc.add(
    plugin.enabled
        ? DisablePluginRequested(plugin.pluginId)
        : EnablePluginRequested(plugin.pluginId),
  );
}

/// מחליף גישה לרשת עבור [plugin] (רק בהרשאות הרשת שהתוסף מצהיר עליהן).
void togglePluginNetworkAccess(BuildContext context, InstalledPlugin plugin) {
  final granted = !plugin.networkAccessGranted;
  final bloc = context.read<PluginSystemBloc>();
  for (final permission in const [
    pluginNetworkAccessPermission,
    _networkLocalhostPermission,
  ]) {
    if (!plugin.manifest.permissions.contains(permission)) continue;
    bloc.add(
      SetPluginPermissionRequested(
        pluginId: plugin.pluginId,
        permission: permission,
        granted: granted,
      ),
    );
  }
}

/// מחליף טעינה אוטומטית בעליית האפליקציה עבור [plugin].
void togglePluginRunOnStartup(BuildContext context, InstalledPlugin plugin) {
  context.read<PluginSystemBloc>().add(
    SetPluginPermissionRequested(
      pluginId: plugin.pluginId,
      permission: pluginRunOnStartupPermission,
      granted: !plugin.runOnStartupGranted,
    ),
  );
}

/// מחשב את סדר מזהי התוספים לאחר גרירת [sourceId] אל מיקום [targetId].
/// פועל על *כל* התוספים (כולל מוסתרים) כדי לא לייצר ערכי סדר כפולים.
List<String> reorderedPluginIds(
  List<InstalledPlugin> allPlugins,
  String sourceId,
  String targetId,
) {
  final ids = allPlugins.map((p) => p.pluginId).toList();
  if (sourceId == targetId) return ids;
  final sourceIdx = ids.indexOf(sourceId);
  final targetIdx = ids.indexOf(targetId);
  if (sourceIdx < 0 || targetIdx < 0) return ids;
  final src = ids.removeAt(sourceIdx);
  ids.insert(targetIdx, src);
  return ids;
}
