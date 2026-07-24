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
import 'package:otzaria/widgets/dialogs/dialogs_exports.dart';
import 'package:otzaria/settings/widgets/settings_card.dart';

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

/// פונקציה משותפת לפתיחת דיאלוג הגדרות תוסף — קוראת מ-tools_management_panel
/// ומ-plugin_side_panel.
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
  Map<String, bool> _permissions = {};

  static String _formatPathForDisplay(String path) =>
      path.replaceAllMapped(_pathSeparatorRegExp, (m) => '${m[0]!}\u200E');

  @override
  void initState() {
    super.initState();
    _loadPermissions();
  }

  Future<void> _loadPermissions() async {
    Map<String, bool> map = {};
    for (final p in widget.plugin.manifest.permissions) {
      final granted = await _repo.getPermission(widget.plugin.pluginId, p);
      // הרשאות רגישות (כמו טעינה ברקע) ברירת מחדל = false;
      // שאר ההרשאות ברירת מחדל = true כפי שמטופל בגשר.
      final defaultValue = p != pluginRunOnStartupPermission;
      map[p] = granted ?? defaultValue;
    }
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
              if (currentPlugin.manifest.permissions.isNotEmpty) ...[
                const SizedBox(height: 16),
                SettingsCard(
                  title: 'ניהול הרשאות',
                  subtitle: 'אפשר או חסום הרשאות ספציפיות כפי שנדרש במניפסט',
                  children: currentPlugin.manifest.permissions.map((p) {
                    final info = getPermissionInfo(p);
                    final defaultValue = p != pluginRunOnStartupPermission;
                    final isGranted = _permissions[p] ?? defaultValue;
                    final isSensitive = p == pluginRunOnStartupPermission;
                    final colorScheme = Theme.of(context).colorScheme;
                    final iconData = isSensitive
                        ? (isGranted
                              ? FluentIcons.warning_24_filled
                              : FluentIcons.warning_24_regular)
                        : (isGranted
                              ? FluentIcons.shield_checkmark_24_regular
                              : FluentIcons.shield_error_24_regular);
                    final iconColor = isSensitive
                        ? colorScheme.tertiary
                        : (isGranted ? colorScheme.primary : colorScheme.error);
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
