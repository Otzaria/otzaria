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
import 'package:otzaria/plugins/services/plugin_new_tab_page_registry.dart';
import 'package:otzaria/plugins/view/plugin_new_tab_page_choice.dart';
import 'package:otzaria/plugins/services/plugin_new_tab_page_service.dart';
import 'package:otzaria/core/messages/plugin_messages.dart';
import 'package:otzaria/core/ui_snack.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';
import 'package:otzaria/widgets/dialogs/app_dialog_frame.dart';
import 'package:otzaria/widgets/dialogs/dialogs_exports.dart';
import 'package:otzaria/widgets/layout/meta_chip.dart';
import 'package:otzaria/settings/widgets/settings_card.dart';
import 'package:otzaria/theme/theme_exports.dart';
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
        'המחיקה תכלול את כל נתוני התוסף, המטמון והפעולות שלו, '
        'וגם טיוטות תיקון שלא נשלחו. הליך זה סופי.',
    cancelText: 'ביטול',
    confirmText: 'מחק',
  );
  if (confirmed != true) return false;
  bloc.add(
    UninstallPluginRequested(plugin.pluginId, deleteCorrectionDrafts: true),
  );
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
        'והתראות שתזמן, וגם טיוטות תיקון שלא נשלחו. התוסף יישאר מותקן. '
        'הליך זה סופי.',
    cancelText: 'ביטול',
    confirmText: 'אפס',
  );
  if (confirmed != true) return false;
  bloc.add(
    ResetPluginDataRequested(plugin.pluginId, deleteCorrectionDrafts: true),
  );
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
    builder: settingsDialogBuilder(
      context,
      (_) => BlocProvider<PluginSystemBloc>.value(
        value: context.read<PluginSystemBloc>(),
        child: PluginSettingsScreen(plugin: plugin),
      ),
    ),
  );
}

/// סימון "DEV" לתוסף פיתוח — משותף ל-tools_launcher_panel ול-tools_management_panel.
class PluginDevBadge extends StatelessWidget {
  const PluginDevBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: cs.tertiary,
        borderRadius: AppTokens.borderRadiusAll,
      ),
      child: Text(
        'DEV',
        style: TextStyle(
          fontSize: 8,
          fontWeight: FontWeight.bold,
          color: cs.onTertiary,
        ),
      ),
    );
  }
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
  String? _newTabOwnerName;

  static String _formatPathForDisplay(String path) =>
      path.replaceAllMapped(_pathSeparatorRegExp, (m) => '${m[0]!}\u200E');

  @override
  void initState() {
    super.initState();
    PluginNewTabPageRegistry.instance.addListener(_loadPermissions);
    _loadPermissions();
    _loadUserFolders();
  }

  @override
  void dispose() {
    PluginNewTabPageRegistry.instance.removeListener(_loadPermissions);
    super.dispose();
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
    final newTabPage = await _repo.getPermission(
      widget.plugin.pluginId,
      pluginNewTabPagePermission,
    );
    String? ownerName;
    if (newTabPage != null) {
      map[pluginNewTabPagePermission] = newTabPage;
      final ownerId = await PluginNewTabPageService.instance.ownerId(_repo);
      if (ownerId != null) {
        ownerName = (await _repo.getPlugin(ownerId))?.name ?? ownerId;
      }
    }
    if (!mounted) return;
    setState(() {
      _permissions = map;
      _newTabOwnerName = ownerName;
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

        final permissionKeys = orderedPluginPermissions(
          {
            ...effectiveManifestPermissions(currentPlugin.manifest.permissions),
            if (_permissions.containsKey(pluginNewTabPagePermission))
              pluginNewTabPagePermission,
          }.toList(),
          isOfflineMode: false,
        );
        return AppDialogFrame(
          icon: FluentIcons.shield_keyhole_24_regular,
          title: 'ניהול הרשאות: ${currentPlugin.name}',
          width: 620,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _PluginIdentity(
                  plugin: currentPlugin,
                  grantedCount: permissionKeys
                      .where(
                        (p) =>
                            _permissions[p] ??
                            pluginPermissionDefaultGrant(
                              p,
                              isOfflineMode: false,
                            ),
                      )
                      .length,
                  totalCount: permissionKeys.length,
                ),
                if (_permissions.isNotEmpty ||
                    effectiveManifestPermissions(
                      currentPlugin.manifest.permissions,
                    ).isNotEmpty) ...[
                  const SizedBox(height: AppTokens.spaceMD),
                  SettingsCard(
                    title: 'הרשאות מבוקשות',
                    subtitle: 'אפשר או חסום הרשאות ספציפיות כפי שנדרש במניפסט',
                    children:
                        orderedPluginPermissions(
                          {
                            ...effectiveManifestPermissions(
                              currentPlugin.manifest.permissions,
                            ),
                            if (_permissions.containsKey(
                              pluginNewTabPagePermission,
                            ))
                              pluginNewTabPagePermission,
                          }.toList(),
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
                            title: p == pluginNewTabPagePermission
                                ? context.settingsText('כפתור לשונית חדשה (+)')
                                : info.label,
                            subtitle: p == pluginNewTabPagePermission
                                ? context.settingsText(
                                    'פתיחת דף התוסף בכפתור "+". רק תוסף אחד יכול לקבל הרשאה זו. בעל הכפתור כעת: {owner}',
                                    args: {
                                      'owner':
                                          _newTabOwnerName ??
                                          context.settingsText('אין'),
                                    },
                                  )
                                : info.description,
                            value: isGranted,
                            enabled:
                                p != pluginNewTabPagePermission ||
                                isGranted ||
                                (currentPlugin.enabled &&
                                    _permissions['navigation.write'] == true),
                            onChanged: (val) async {
                              if (p == pluginNewTabPagePermission && val) {
                                try {
                                  await choosePluginNewTabPage(
                                    context,
                                    currentPlugin,
                                    _repo,
                                  );
                                  await _loadPermissions();
                                } catch (error) {
                                  UiSnack.showError(
                                    PluginMessages.updatePermissionError(error),
                                  );
                                }
                                return;
                              }
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
                  const SizedBox(height: AppTokens.spaceMD),
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
                  const SizedBox(height: AppTokens.spaceMD),
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
                if (currentPlugin.isDevelopment) ...[
                  const SizedBox(height: AppTokens.spaceMD),
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
          ),
        );
      },
    );
  }
}

/// פרטי התוסף בראש דיאלוג ההרשאות: שם ותיאור, ותגיות מצב (פעיל, גרסה, מפתח
/// וכמה מההרשאות מופעלות).
class _PluginIdentity extends StatelessWidget {
  const _PluginIdentity({
    required this.plugin,
    required this.grantedCount,
    required this.totalCount,
  });

  final InstalledPlugin plugin;
  final int grantedCount;
  final int totalCount;

  @override
  Widget build(BuildContext context) {
    final author = plugin.manifest.author.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DetailsHeading(
          title: plugin.name,
          subtitle: plugin.manifest.description,
        ),
        const SizedBox(height: AppTokens.spaceSM),
        Wrap(
          spacing: AppTokens.spaceSM - 2,
          runSpacing: AppTokens.spaceSM - 2,
          children: [
            MetaChip(
              icon: plugin.enabled
                  ? FluentIcons.checkmark_circle_24_regular
                  : FluentIcons.dismiss_circle_24_regular,
              label: plugin.enabled ? 'פעיל' : 'מושבת',
              outlined: !plugin.enabled,
            ),
            Directionality(
              textDirection: TextDirection.ltr,
              child: MetaChip(outlined: true, label: 'v${plugin.version}'),
            ),
            if (author.isNotEmpty) MetaChip(outlined: true, label: author),
            if (plugin.isDevelopment)
              const MetaChip(
                outlined: true,
                icon: FluentIcons.code_24_regular,
                label: 'פיתוח',
              ),
            if (totalCount > 0)
              MetaChip(
                icon: FluentIcons.shield_checkmark_24_regular,
                label: '$grantedCount מתוך $totalCount הרשאות מופעלות',
              ),
          ],
        ),
      ],
    );
  }
}
