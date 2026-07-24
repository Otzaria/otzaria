import 'package:flutter/material.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/plugins/bloc/plugin_system_bloc.dart';
import 'package:otzaria/plugins/bloc/plugin_system_event.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/models/plugin_permission_labels.dart';
import 'package:otzaria/plugins/models/plugin_valid_permissions.dart';
import 'package:otzaria/widgets/controls/action_buttons.dart';
import 'package:otzaria/widgets/dialogs/dialogs_exports.dart';
import 'package:otzaria/settings/widgets/settings_card.dart';

/// מסך אישור התקנת/עדכון תוסף — מאפשר למשתמש לבחור אילו הרשאות להעניק
class PluginInstallScreen extends StatefulWidget {
  final PluginManifest manifest;
  final String tempDirPath;

  /// גרסה מותקנת קודמת — null אם זו התקנה ראשונה.
  final String? previousVersion;

  /// בחירה קודמת של המשתמש לגבי הקדמת התוסף לפני כלים מובנים.
  /// `null` = אין החלטה קודמת (התקנה ראשונה או תוסף ישן לפני הפיצ'ר).
  final bool? previousAllowOrderBeforeBuiltInsGranted;

  /// כאשר מסופק, נקרא במקום שליחת ConfirmPluginInstall לבלוק (למשל בתוסף פיתוח).
  final void Function(
    Map<String, bool> grantedPermissions,
    bool allowOrderBeforeBuiltInsGranted,
  )?
  onConfirm;

  /// כאשר מסופק, נקרא במקום שליחת CancelPluginInstall לבלוק.
  final VoidCallback? onCancel;

  /// האם אוצריא במצב 'מנותק' בעת ההתקנה. אם כן, הרשאת הרשת מתחילה כבויה.
  final bool isOfflineMode;

  const PluginInstallScreen({
    super.key,
    required this.manifest,
    required this.tempDirPath,
    this.previousVersion,
    this.previousAllowOrderBeforeBuiltInsGranted,
    this.onConfirm,
    this.onCancel,
    this.isOfflineMode = false,
  });

  bool get isUpdate => previousVersion != null;

  @override
  State<PluginInstallScreen> createState() => _PluginInstallScreenState();
}

class _PluginInstallScreenState extends State<PluginInstallScreen> {
  /// מצב toggle לכל הרשאה — ברירת מחדל: הכל מופעל, פרט להרשאות רגישות
  /// ([pluginRunOnStartupPermission]) שמתחילות כבויות, ול-network.access
  /// שמתחיל כבוי בהתקנה במצב 'מנותק'.
  late Map<String, bool> _permissionToggles;
  late bool _allowOrderBeforeBuiltInsGranted;

  @override
  void initState() {
    super.initState();
    _permissionToggles = {
      for (final p in widget.manifest.permissions) p: _defaultGrantFor(p),
    };
    _allowOrderBeforeBuiltInsGranted =
        widget.previousAllowOrderBeforeBuiltInsGranted ??
        widget.manifest.allowOrderBeforeBuiltIns;
  }

  bool _defaultGrantFor(String permission) {
    if (permission == pluginRunOnStartupPermission) return false;
    if (widget.isOfflineMode && permission == pluginNetworkAccessPermission) {
      return false;
    }
    return true;
  }

  bool get _requestsRunOnStartup =>
      widget.manifest.permissions.contains(pluginRunOnStartupPermission);

  bool get _requestsOrderBeforeBuiltIns =>
      widget.manifest.allowOrderBeforeBuiltIns;

  void _onInstall() {
    if (widget.onConfirm != null) {
      widget.onConfirm!(
        Map.unmodifiable(_permissionToggles),
        _allowOrderBeforeBuiltInsGranted,
      );
    } else {
      context.read<PluginSystemBloc>().add(
        ConfirmPluginInstall(
          widget.tempDirPath,
          widget.manifest,
          Map.unmodifiable(_permissionToggles),
          _allowOrderBeforeBuiltInsGranted,
        ),
      );
    }
    Navigator.of(context).pop();
  }

  void _onCancel() {
    if (widget.onCancel != null) {
      widget.onCancel!();
    } else {
      context.read<PluginSystemBloc>().add(
        CancelPluginInstall(widget.tempDirPath),
      );
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final hasPermissions = widget.manifest.permissions.isNotEmpty;
    final colorScheme = Theme.of(context).colorScheme;
    final isUpdate = widget.isUpdate;

    return AppCustomContentDialog(
      title: isUpdate
          ? 'עדכון תוסף: ${widget.manifest.name}'
          : 'התקנת תוסף: ${widget.manifest.name}',
      actions: [
        ActionButton.ghost(
          text: 'ביטול',
          onPressed: _onCancel,
        ),
        ActionButton.recommended(
          text: isUpdate ? 'עדכן' : 'התקן',
          onPressed: _onInstall,
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ===== כרטיס מידע על התוסף =====
          SettingsCard(
            title: 'מידע על התוסף',
            children: [
              if (widget.manifest.description.isNotEmpty)
                SettingsActionTile.text(
                  icon: FluentIcons.info_24_regular,
                  title: 'תכונות',
                  subtitle: widget.manifest.description,
                ),
              SettingsActionTile.text(
                icon: FluentIcons.person_24_regular,
                title: 'מחבר: ${widget.manifest.author}',
                subtitle: isUpdate
                    ? 'עדכון גרסה ${widget.previousVersion}  ←  ${widget.manifest.version}'
                    : 'גרסה ${widget.manifest.version}',
                subtitleLtr: true,
              ),
            ],
          ),

          const SizedBox(height: 16),

          // ===== באנר בולט: בקשת טעינה אוטומטית עם עליית האפליקציה =====
          if (_requestsRunOnStartup) ...[
            _RunOnStartupBanner(colorScheme: colorScheme),
            const SizedBox(height: 16),
          ],

          if (_requestsOrderBeforeBuiltIns) ...[
            SettingsCard(
              title: 'מיקום במסך כלים',
              subtitle: 'התוסף מבקש להופיע לפני הכלים המובנים במסך "כלים".',
              children: [
                SettingsActionTile.switchTile(
                  icon: _allowOrderBeforeBuiltInsGranted
                      ? FluentIcons.arrow_sort_up_24_regular
                      : FluentIcons.arrow_sort_24_regular,
                  iconColor: _allowOrderBeforeBuiltInsGranted
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant,
                  title: 'אפשר לתוסף להופיע לפני הכלים המובנים',
                  subtitle:
                      'אם תכבה את האפשרות, התוסף עדיין יותקן כרגיל, אבל '
                      'יופיע רק אחרי הכלים המובנים גם אם המניפסט שלו ביקש אחרת.',
                  value: _allowOrderBeforeBuiltInsGranted,
                  onChanged: (value) {
                    setState(() {
                      _allowOrderBeforeBuiltInsGranted = value;
                    });
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],

          // ===== הרשאות =====
          if (!hasPermissions)
            SettingsCard(
              title: 'הרשאות',
              children: [
                SettingsActionTile.text(
                  icon: FluentIcons.shield_checkmark_24_regular,
                  iconColor: colorScheme.primary,
                  title: 'אין הרשאות מיוחדות נדרשות',
                  subtitle: 'תוסף זה אינו מבקש גישה למשאבים רגישים',
                ),
              ],
            )
          else ...[
            SettingsCard(
              title: 'הרשאות נדרשות',
              subtitle:
                  'בחר אילו הרשאות להעניק לתוסף זה (ברירת מחדל: הכל מופעל)',
              children: [
                ...widget.manifest.permissions.map((permission) {
                  final info = getPermissionInfo(permission);
                  final isGranted = _permissionToggles[permission] ?? true;
                  final isSensitive =
                      permission == pluginRunOnStartupPermission;
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
                    onChanged: (val) {
                      setState(() {
                        _permissionToggles[permission] = val;
                      });
                    },
                  );
                }),
                SettingsActionTile.text(
                  icon: FluentIcons.info_24_regular,
                  iconColor: colorScheme.onSurfaceVariant,
                  title: 'ניתן לשנות הרשאות בכל עת מהגדרות התוסף',
                ),
              ],
            ),
          ],

          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

/// באנר בולט שמודיע למשתמש שהתוסף מבקש לרוץ ברקע עם עליית האפליקציה.
///
/// ההרשאה כבויה ברירת מחדל; הבאנר מסביר מה ההשלכות ומנחה להפעיל
/// רק תוספים מהימנים.
class _RunOnStartupBanner extends StatelessWidget {
  final ColorScheme colorScheme;

  const _RunOnStartupBanner({required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.tertiaryContainer,
        borderRadius: AppTokens.borderRadiusAll,
        border: Border.all(
          color: colorScheme.tertiary,
          width: 1.5,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            FluentIcons.warning_24_filled,
            color: colorScheme.tertiary,
            size: 28,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'התוסף מבקש לפעול ברקע עם עליית האפליקציה',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: colorScheme.onTertiaryContainer,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'אם תאשר את ההרשאה, התוסף ייטען וירוץ ברקע בכל פעם '
                  'שאוצריא נטענת, גם בלי שתיכנס למסך "כלים". '
                  'הדבר עלול להכביד על זמן העלייה ועל צריכת המשאבים של האפליקציה. '
                  'ברירת המחדל היא שההרשאה כבויה — הענק אותה רק לתוספים '
                  'שאתה סומך עליהם.',
                  style: TextStyle(
                    fontSize: 13,
                    color: colorScheme.onTertiaryContainer,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
