import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/plugins/models/installed_plugin.dart';
import 'package:otzaria/plugins/bloc/plugin_system_bloc.dart';
import 'package:otzaria/plugins/bloc/plugin_system_event.dart';
import 'package:otzaria/plugins/bloc/plugin_system_state.dart';
import 'package:otzaria/plugins/models/plugin_permission_labels.dart';
import 'package:otzaria/plugins/models/plugin_valid_permissions.dart';
import 'package:otzaria/plugins/repository/plugin_registry_repository.dart';
import 'package:otzaria/plugins/services/plugin_user_folder_grants.dart';
import 'package:otzaria/widgets/dialogs/dialogs_exports.dart';
import 'package:otzaria/settings/widgets/settings_card.dart';
import 'package:path/path.dart' as p;

/// פונקציה משותפת לדיאלוג אישור מחיקת תוסף — קוראת מ-tools_management_panel
/// ומ-PluginSettingsScreen.
///
/// מחזירה `true` אם המשתמש אישר ומחיקה הופעלה, `false` אם ביטל.
Future<bool> showDeletePluginDialog(
  BuildContext context,
  InstalledPlugin plugin,
) async {
  final bloc = context.read<PluginSystemBloc>();
  if (plugin.isDevelopment) {
    bloc.add(DetachDevelopmentPluginRequested(plugin.pluginId));
    return true;
  }
  final confirmed = await showWarningDialog(
    context: context,
    title: 'מחיקת תוסף סופית',
    content: 'האם אתה בטוח שברצונך למחוק את התוסף "${plugin.name}"?',
    subtitle:
        'המחיקה תכלול את כל נתוני התוסף, המטמון והפעולות שלו. הליך זה סופי.',
    cancelText: 'ביטול',
    confirmText: 'מחק',
  );
  if (confirmed != true) return false;
  bloc.add(UninstallPluginRequested(plugin.pluginId));
  return true;
}

/// דיאלוג אישור לאיפוס כל הנתונים שהתוסף אגר (KV, אירועי לוח, התראות, קבצים).
/// התוסף עצמו, הרשאותיו והגדרות התצוגה נשארים.
///
/// מחזירה `true` אם המשתמש אישר והאיפוס הופעל, `false` אם ביטל.
Future<bool> showResetPluginDataDialog(
  BuildContext context,
  InstalledPlugin plugin,
) async {
  final bloc = context.read<PluginSystemBloc>();
  final confirmed = await showWarningDialog(
    context: context,
    title: 'איפוס נתוני התוסף',
    content: 'האם לאפס את כל הנתונים של התוסף "${plugin.name}"?',
    subtitle:
        'כל המידע שהתוסף שמר יימחק — הגדרות, נתונים, אירועים שהוסיף ללוח השנה '
        'והתראות שתזמן. התוסף יישאר מותקן. הליך זה סופי.',
    cancelText: 'ביטול',
    confirmText: 'אפס',
  );
  if (confirmed != true) return false;
  bloc.add(ResetPluginDataRequested(plugin.pluginId));
  return true;
}

/// פונקציה משותפת לפתיחת דיאלוג הגדרות תוסף — קוראת מ-tools_management_panel
/// ומ-tools_launcher_panel.
Future<bool?> showPluginSettingsDialog(
  BuildContext context,
  InstalledPlugin plugin,
) {
  return showDialog<bool>(
    context: context,
    builder: (_) => BlocProvider<PluginSystemBloc>.value(
      value: context.read<PluginSystemBloc>(),
      child: PluginSettingsScreen(plugin: plugin),
    ),
  );
}

class PluginSettingsScreen extends StatefulWidget {
  final InstalledPlugin plugin;

  const PluginSettingsScreen({super.key, required this.plugin});

  @override
  State<PluginSettingsScreen> createState() => _PluginSettingsScreenState();
}

class _PluginSettingsScreenState extends State<PluginSettingsScreen> {
  final _repo = PluginRegistryRepository();
  static final RegExp _pathSeparatorRegExp = RegExp(r'[/\\]');
  late final _folderGrants = PluginUserFolderGrants(_repo);
  Map<String, bool> _permissions = {};
  List<PluginUserFolderGrant> _userFolders = const [];

  static String _formatPathForDisplay(String path) =>
      path.replaceAllMapped(_pathSeparatorRegExp, (m) => '${m[0]!}\u200E');

  @override
  void initState() {
    super.initState();
    _loadPermissions();
    _loadUserFolders();
  }

  Future<void> _loadUserFolders() async {
    final folders = await _folderGrants.list(widget.plugin.pluginId);
    if (!mounted) return;
    setState(() => _userFolders = folders);
  }

  /// ביטול גישה קבועה — אותה פעולה כמו `fs.revokeFolder`. אינו מוחק דבר מהדיסק,
  /// ולכן אין דיאלוג אישור.
  Future<void> _revokeUserFolder(PluginUserFolderGrant folder) async {
    await _folderGrants.revoke(widget.plugin.pluginId, folder.token);
    await _loadUserFolders();
  }

  Future<void> _loadPermissions() async {
    Map<String, bool> map = {};
    for (final p in effectiveManifestPermissions(
      widget.plugin.manifest.permissions,
    )) {
      final granted = await _repo.getPermission(widget.plugin.pluginId, p);
      final defaultValue = pluginPermissionDefaultGrant(
        p,
        isOfflineMode: false,
      );
      map[p] = granted ?? defaultValue;
    }
    if (!mounted) return;
    setState(() {
      _permissions = map;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Wrap with BlocBuilder so that we get latest state (e.g. for enabled)
    return BlocBuilder<PluginSystemBloc, PluginSystemState>(
      builder: (context, state) {
        InstalledPlugin currentPlugin = widget.plugin;
        if (state is PluginSystemLoaded) {
          try {
            currentPlugin = state.plugins.firstWhere(
              (p) => p.pluginId == widget.plugin.pluginId,
            );
          } catch (_) {
            // plugin uninstalled or not found
          }
        }

        return AppCustomContentDialog(
          title: 'ניהול הרשאות: ${currentPlugin.name}',
          actions: const [],
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (effectiveManifestPermissions(
                currentPlugin.manifest.permissions,
              ).isNotEmpty) ...[
                const SizedBox(height: 16),
                SettingsCard(
                  title: 'ניהול הרשאות',
                  subtitle: 'אפשר או חסום הרשאות ספציפיות כפי שנדרש במניפסט',
                  children:
                      orderedPluginPermissions(
                        effectiveManifestPermissions(
                          currentPlugin.manifest.permissions,
                        ),
                        isOfflineMode: false,
                      ).map((p) {
                        final info = getPermissionInfo(
                          p,
                          manifest: currentPlugin.manifest,
                        );
                        final defaultValue = pluginPermissionDefaultGrant(
                          p,
                          isOfflineMode: false,
                        );
                        final isGranted = _permissions[p] ?? defaultValue;
                        final isSensitive = p == pluginRunOnStartupPermission;
                        final isCritical =
                            p == pluginBackgroundKeepAlivePermission;
                        final colorScheme = Theme.of(context).colorScheme;
                        final iconData = pluginPermissionIcon(
                          p,
                          isGranted: isGranted,
                          manifest: currentPlugin.manifest,
                        );
                        final iconColor = isCritical
                            ? colorScheme.error
                            : isSensitive
                            ? colorScheme.tertiary
                            : (isGranted
                                  ? colorScheme.primary
                                  : colorScheme.error);
                        return SettingsActionTile.switchTile(
                          icon: iconData,
                          iconColor: iconColor,
                          title: info.label,
                          subtitle: info.description,
                          value: isGranted,
                          onChanged: (val) async {
                            context.read<PluginSystemBloc>().add(
                              SetPluginPermissionRequested(
                                pluginId: currentPlugin.pluginId,
                                permission: p,
                                granted: val,
                              ),
                            );
                            setState(() {
                              _permissions[p] = val;
                            });
                          },
                        );
                      }).toList(),
                ),
              ] else ...[
                const SizedBox(height: 16),
                SettingsCard(
                  title: 'הרשאות',
                  children: [
                    SettingsActionTile.text(
                      icon: FluentIcons.shield_checkmark_24_regular,
                      iconColor: Theme.of(context).colorScheme.primary,
                      title: 'אין הרשאות מיוחדות נדרשות',
                      subtitle: 'תוסף זה אינו מבקש גישה למשאבים רגישים',
                    ),
                  ],
                ),
              ],
              if (_userFolders.isNotEmpty) ...[
                const SizedBox(height: 16),
                SettingsCard(
                  title: 'תיקיות עם גישה קבועה',
                  subtitle:
                      'התוסף קורא וכותב בתיקיות אלה בלי לשאול שוב. הסרה מבטלת '
                      'את הגישה ואינה מוחקת דבר מהדיסק.',
                  children: [
                    for (final folder in _userFolders)
                      SettingsActionTile.path(
                        key: ValueKey(folder.token),
                        icon: FluentIcons.folder_24_regular,
                        iconColor: Theme.of(context).colorScheme.primary,
                        title: p.basename(folder.path).isEmpty
                            ? folder.path
                            : p.basename(folder.path),
                        path: folder.path,
                        placeholder: '',
                        pinnedTrailing: IconButton(
                          icon: const Icon(
                            FluentIcons.dismiss_24_regular,
                            size: 18,
                          ),
                          tooltip: 'הסר גישה',
                          onPressed: () => _revokeUserFolder(folder),
                        ),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 32),
              if (currentPlugin.isDevelopment) ...[
                SettingsCard(
                  title: 'פיתוח',
                  children: [
                    SettingsActionTile.text(
                      icon: FluentIcons.folder_24_regular,
                      title: 'נתיב תיקייה',
                      subtitle: _formatPathForDisplay(
                        currentPlugin.resolvedRootPath,
                      ),
                      subtitleLtr: true,
                    ),
                    SettingsActionTile.text(
                      icon: FluentIcons.arrow_clockwise_24_regular,
                      title: 'רענן עכשיו',
                      onTap: () {
                        context.read<PluginSystemBloc>().add(
                          ReloadDevelopmentPluginRequested(
                            currentPlugin.pluginId,
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
