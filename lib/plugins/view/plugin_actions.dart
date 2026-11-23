import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/plugins/bloc/plugin_system_bloc.dart';
import 'package:otzaria/plugins/bloc/plugin_system_event.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/models/plugin_valid_permissions.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/settings/services/safer_mode_guard.dart';
import 'package:otzaria/utils/file/file_picker_dialog_options.dart';
import 'package:path/path.dart' as p;

bool _pickingPluginArchive = false;

/// פותח בורר מערכת להתקנת תוסף. מחזיר אם נפתחה בקשה, גם אם המשתמש ביטל.
Future<bool> pickAndInstallPluginArchive(
  BuildContext context, {
  bool requestedByPlugin = false,
}) async {
  if (!context.mounted || _pickingPluginArchive) return false;
  final settings = context.read<SettingsBloc>();
  if (requestedByPlugin &&
      (settings.state.protectedModeEnabled ||
          View.maybeOf(context) == null ||
          ModalRoute.of(context)?.isCurrent != true)) {
    return false;
  }

  _pickingPluginArchive = true;
  try {
    if (!requestedByPlugin &&
        (!await verifySaferModePassword(context) || !context.mounted)) {
      return false;
    }
    final selection = await withFilePickerOwner(
      context,
      (picker) async {
        final result = await picker.pickFile(
          type: FileType.custom,
          allowedExtensions: const ['otzplugin'],
          windowsOptions: modalWindowsOptions(context),
          linuxOptions: kModalLinuxOptions,
        );
        // תוצאת null מהבורר היא ביטול; null מהעטיפה מציין שאין חלון בעלים.
        return (path: result?.path);
      },
    );
    if (selection == null) return false;
    final selectedPath = selection.path;
    if (selectedPath != null &&
        context.mounted &&
        (!requestedByPlugin ||
            (!settings.state.protectedModeEnabled &&
                p.extension(selectedPath).toLowerCase() == '.otzplugin'))) {
      context.read<PluginSystemBloc>().add(
        requestedByPlugin
            ? InstallPluginRequested.fromPluginPicker(selectedPath)
            : InstallPluginRequested(selectedPath, isUserInitiated: true),
      );
    }
    return true;
  } catch (error, stackTrace) {
    if (!requestedByPlugin) rethrow;
    debugPrintStack(
      label: 'Plugin archive picker failed: $error',
      stackTrace: stackTrace,
    );
    return false;
  } finally {
    _pickingPluginArchive = false;
  }
}

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
    plugin.savedEnabled
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
