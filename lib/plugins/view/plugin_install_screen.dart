import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/plugins/bloc/plugin_system_bloc.dart';
import 'package:otzaria/plugins/bloc/plugin_system_event.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/models/plugin_permission_labels.dart';
import 'package:otzaria/widgets/buttons/action_buttons.dart';
import 'package:otzaria/settings/settings_card.dart';

/// מסך אישור התקנת תוסף — מאפשר למשתמש לבחור אילו הרשאות להעניק
class PluginInstallScreen extends StatefulWidget {
  final PluginManifest manifest;
  final String tempDirPath;

  const PluginInstallScreen({
    super.key,
    required this.manifest,
    required this.tempDirPath,
  });

  @override
  State<PluginInstallScreen> createState() => _PluginInstallScreenState();
}

class _PluginInstallScreenState extends State<PluginInstallScreen> {
  /// מצב toggle לכל הרשאה — ברירת מחדל: הכל מופעל
  late Map<String, bool> _permissionToggles;

  @override
  void initState() {
    super.initState();
    _permissionToggles = {
      for (final p in widget.manifest.permissions) p: true,
    };
  }

  void _onInstall() {
    context.read<PluginSystemBloc>().add(
          ConfirmPluginInstall(
            widget.tempDirPath,
            widget.manifest,
            Map.unmodifiable(_permissionToggles),
          ),
        );
    Navigator.of(context).pop();
  }

  void _onCancel() {
    context
        .read<PluginSystemBloc>()
        .add(CancelPluginInstall(widget.tempDirPath));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final hasPermissions = widget.manifest.permissions.isNotEmpty;
    final colorScheme = Theme.of(context).colorScheme;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 60),
      clipBehavior: Clip.antiAlias,
      child: PopScope(
        // מניעת יציאה בלי ניקוי — Back של מערכת מטופל ידנית
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _onCancel();
        },
        child: Scaffold(
          appBar: AppBar(
            title: const Text(
              'אישור התקנת תוסף',
              textDirection: TextDirection.rtl,
            ),
            leading: IconButton(
              icon: const Icon(FluentIcons.dismiss_24_regular),
              tooltip: 'ביטול',
              onPressed: _onCancel,
            ),
          ),
          body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ===== כרטיס פרטי התוסף =====
            SettingsCard(
              title: widget.manifest.name,
              subtitle: widget.manifest.description.isNotEmpty
                  ? widget.manifest.description
                  : null,
              children: [
                if (widget.manifest.author.isNotEmpty)
                  ListTile(
                    leading: const Icon(FluentIcons.person_24_regular),
                    title: const Text(
                      'מחבר',
                      textDirection: TextDirection.rtl,
                    ),
                    subtitle: Text(
                      widget.manifest.author,
                      textDirection: TextDirection.rtl,
                    ),
                    hoverColor: Colors.transparent,
                  ),
                ListTile(
                  leading: const Icon(FluentIcons.tag_24_regular),
                  title: const Text(
                    'גרסה',
                    textDirection: TextDirection.rtl,
                  ),
                  subtitle: Text(
                    widget.manifest.version,
                    textDirection: TextDirection.rtl,
                  ),
                  hoverColor: Colors.transparent,
                ),
              ],
            ),

            const SizedBox(height: 16),

            // ===== הרשאות =====
            if (!hasPermissions)
              SettingsCard(
                title: 'הרשאות',
                children: [
                  ListTile(
                    leading: Icon(
                      FluentIcons.shield_checkmark_24_regular,
                      color: colorScheme.primary,
                    ),
                    title: const Text(
                      'אין הרשאות מיוחדות נדרשות',
                      textDirection: TextDirection.rtl,
                    ),
                    subtitle: const Text(
                      'תוסף זה אינו מבקש גישה למשאבים רגישים',
                      textDirection: TextDirection.rtl,
                    ),
                    hoverColor: Colors.transparent,
                  ),
                ],
              )
            else ...[
              SettingsCard(
                title: 'הרשאות נדרשות',
                subtitle:
                    'בחר אילו הרשאות להעניק לתוסף זה (ברירת מחדל: הכל מופעל)',
                children: widget.manifest.permissions.map((permission) {
                  final info = getPermissionInfo(permission);
                  final isGranted = _permissionToggles[permission] ?? true;
                  return SwitchListTile(
                    secondary: Icon(
                      isGranted
                          ? FluentIcons.shield_checkmark_24_regular
                          : FluentIcons.shield_error_24_regular,
                      color:
                          isGranted ? colorScheme.primary : colorScheme.error,
                    ),
                    title: Text(
                      info.label,
                      textDirection: TextDirection.rtl,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                    subtitle: Text(
                      info.description,
                      textDirection: TextDirection.rtl,
                    ),
                    value: isGranted,
                    onChanged: (val) {
                      setState(() {
                        _permissionToggles[permission] = val;
                      });
                    },
                    hoverColor: Colors.transparent,
                  );
                }).toList(),
              ),
              const SizedBox(height: 8),
              // הסבר שניתן לשנות אחרי ההתקנה
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  children: [
                    Icon(
                      FluentIcons.info_24_regular,
                      size: 16,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'ניתן לשנות הרשאות בכל עת מהגדרות התוסף',
                        textDirection: TextDirection.rtl,
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 32),

            // ===== כפתורי פעולה =====
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                NeutralActionButton(
                  text: 'ביטול',
                  onPressed: _onCancel,
                ),
                const SizedBox(width: 12),
                RecommendedActionButton(
                  text: 'התקן',
                  onPressed: _onInstall,
                ),
              ],
            ),

            const SizedBox(height: 16),
          ],
        ),
      ),
    ),
  );
  }
}
