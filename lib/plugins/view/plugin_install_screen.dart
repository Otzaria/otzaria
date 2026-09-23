import 'package:flutter/material.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria_icons/otzaria_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:otzaria/plugins/bloc/plugin_system_bloc.dart';
import 'package:otzaria/plugins/bloc/plugin_system_event.dart';
import 'package:otzaria/plugins/models/plugin_install_decision.dart';
import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/models/plugin_permission_labels.dart';
import 'package:otzaria/plugins/models/plugin_valid_permissions.dart';
import 'package:otzaria/plugins/services/plugin_install_report_service.dart';
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

  /// החלטות ההרשאה השמורות של הגרסה המותקנת. בעדכון מוצגות רק הרשאות
  /// שאינן במפה — אלה שהמשתמש טרם החליט לגביהן.
  final Map<String, bool> previousGrantedPermissions;
  final PluginInstallReportContext? reportContext;

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
    this.previousGrantedPermissions = const {},
    this.reportContext,
    this.onConfirm,
    this.onCancel,
    this.isOfflineMode = false,
  });

  bool get isUpdate => previousVersion != null;

  @override
  State<PluginInstallScreen> createState() => _PluginInstallScreenState();
}

class _PluginInstallScreenState extends State<PluginInstallScreen> {
  /// כל חישובי ההרשאות של המסך — משותפים עם המארח, שנשען עליהם כדי להחליט
  /// אם בכלל לפתוח את המסך.
  late PluginInstallDecision _decision;

  /// מצב toggle לכל הרשאה, לפי ברירת המחדל המשותפת למסכי ההרשאות.
  late Map<String, bool> _permissionToggles;
  late bool _allowOrderBeforeBuiltInsGranted;

  List<String> get _orderedPermissions => _decision.orderedPermissions;
  List<String> get _newPermissions => _decision.newPermissions;
  List<String> get _revokedPermissions => _decision.revokedPermissions;

  @override
  void initState() {
    super.initState();
    _decision = resolvePluginInstallDecision(
      manifest: widget.manifest,
      previousVersion: widget.previousVersion,
      previousGrantedPermissions: widget.previousGrantedPermissions,
      previousAllowOrderBeforeBuiltInsGranted:
          widget.previousAllowOrderBeforeBuiltInsGranted,
      isOfflineMode: widget.isOfflineMode,
      // המסך נבנה רק אחרי שהוחלט לפתוח דיאלוג; ההכרעה כאן היא מה להציג.
      isUserInitiated: true,
    );
    _permissionToggles = Map<String, bool>.of(_decision.permissionToggles);
    _allowOrderBeforeBuiltInsGranted =
        widget.previousAllowOrderBeforeBuiltInsGranted ??
        widget.manifest.allowOrderBeforeBuiltIns;
  }

  bool _isTemporarilyUnavailable(String permission) =>
      _decision.temporarilyUnavailablePermissions.contains(permission);

  /// בעדכון מוצגות רק הרשאות חדשות או כבויות; בהתקנה ראשונה — הכול.
  List<String> get _visiblePermissions =>
      widget.isUpdate ? _newPermissions : _orderedPermissions;

  /// באנר האזהרה מוצג רק כשההחלטה על ההרשאה שמאחוריו פתוחה בדיאלוג הזה.
  bool _showsPermission(String permission) =>
      _visiblePermissions.contains(permission) ||
      _revokedPermissions.contains(permission);

  bool get _requestsRunOnStartup =>
      _showsPermission(pluginRunOnStartupPermission);

  /// המניפסט מחייב את הרשאת keep_alive, ולכן די בהצגתה כדי לגזור את הבאנר.
  bool get _requestsKeepAlive =>
      widget.manifest.startup?.keepAlive == true &&
      _showsPermission(pluginBackgroundKeepAlivePermission);

  /// שאלת המיקום נשאלת רק כשאין עליה החלטה קודמת.
  bool get _requestsOrderBeforeBuiltIns =>
      _decision.requestsOrderBeforeBuiltIns;

  /// עדכון שאינו דורש שום החלטה — מוצג כאישור עדכון בלבד.
  /// במסלול הרגיל המארח כלל אינו פותח את המסך במצב הזה (issue #1410);
  /// נשאר עבור עדכון תוסף פיתוח, שאין לו החלטות הרשאה שמורות.
  bool get _isPlainUpdate => _decision.isPlainUpdate;

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
          reportContext: widget.reportContext,
          previousVersion: widget.previousVersion,
        ),
      );
    }
    // pop(true) = נסגר בפעולה מפורשת; סגירת barrier מחזירה null והמארח
    // מתרגם אותה לביטול (ניקוי תיקיית ה-temp ודיווח לחנות).
    Navigator.of(context).pop(true);
  }

  void _onCancel() {
    if (widget.onCancel != null) {
      widget.onCancel!();
    } else {
      context.read<PluginSystemBloc>().add(
        CancelPluginInstall(
          widget.tempDirPath,
          reportContext: widget.reportContext,
        ),
      );
    }
    Navigator.of(context).pop(true);
  }

  Widget _permissionTile(String permission, ColorScheme colorScheme) {
    final info = getPermissionInfo(permission, manifest: widget.manifest);
    final isTemporarilyUnavailable = _isTemporarilyUnavailable(permission);
    final isGranted =
        !isTemporarilyUnavailable && (_permissionToggles[permission] ?? true);
    final isSensitive = permission == pluginRunOnStartupPermission;
    final isCritical = permission == pluginBackgroundKeepAlivePermission;
    return SettingsActionTile.switchTile(
      icon: pluginPermissionIcon(
        permission,
        isGranted: isGranted,
        manifest: widget.manifest,
      ),
      iconColor: isCritical
          ? colorScheme.error
          : isSensitive
          ? colorScheme.tertiary
          : (isGranted ? colorScheme.primary : colorScheme.error),
      title: info.label,
      subtitle: isTemporarilyUnavailable
          ? '${info.description}\nחסומה זמנית במצב מנותק; ההרשאה השמורה תישמר.'
          : info.description,
      value: isGranted,
      enabled: !isTemporarilyUnavailable,
      onChanged: (val) {
        setState(() {
          _permissionToggles[permission] = val;
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasPermissions = _orderedPermissions.isNotEmpty;
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
                icon: OtzariaIcons.person_24_regular,
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
            _BackgroundActivationBanner(
              colorScheme: colorScheme,
              manifest: widget.manifest,
            ),
            const SizedBox(height: 16),
          ],

          if (widget.manifest.headless &&
              (_requestsRunOnStartup ||
                  _showsPermission(pluginStartupContributionsPermission))) ...[
            _HeadlessBanner(colorScheme: colorScheme),
            const SizedBox(height: 16),
          ],

          if (_requestsKeepAlive) ...[
            _KeepAliveBanner(colorScheme: colorScheme),
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
          if (_isPlainUpdate)
            SettingsCard(
              title: 'הרשאות',
              children: [
                SettingsActionTile.text(
                  icon: FluentIcons.shield_checkmark_24_regular,
                  iconColor: colorScheme.primary,
                  title: 'העדכון אינו מבקש הרשאות חדשות',
                  subtitle: 'ההרשאות שהענקת לתוסף יישמרו כפי שהן',
                ),
              ],
            )
          else if (!hasPermissions)
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
            if (_visiblePermissions.isNotEmpty)
              SettingsCard(
                title: isUpdate ? 'הרשאות חדשות' : 'הרשאות נדרשות',
                subtitle: isUpdate
                    ? 'הרשאות שהתוסף מבקש לראשונה בגרסה זו'
                    : 'הרשאות רגישות מתחילות כבויות ודורשות אישור מפורש',
                children: [
                  ..._visiblePermissions.map(
                    (permission) => _permissionTile(permission, colorScheme),
                  ),
                  SettingsActionTile.text(
                    icon: FluentIcons.info_24_regular,
                    iconColor: colorScheme.onSurfaceVariant,
                    title: 'ניתן לשנות הרשאות בכל עת מהגדרות התוסף',
                  ),
                ],
              ),
            if (isUpdate && _revokedPermissions.isNotEmpty) ...[
              if (_visiblePermissions.isNotEmpty) const SizedBox(height: 16),
              SettingsCard(
                title: 'הרשאות כבויות',
                subtitle:
                    'הרשאות מוכרות שאינן מוענקות כרגע — אינן חדשות בגרסה זו',
                children: [
                  ..._revokedPermissions.map(
                    (permission) => _permissionTile(permission, colorScheme),
                  ),
                ],
              ),
            ],
          ],

          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _BackgroundActivationBanner extends StatelessWidget {
  final ColorScheme colorScheme;
  final PluginManifest manifest;

  const _BackgroundActivationBanner({
    required this.colorScheme,
    required this.manifest,
  });

  @override
  Widget build(BuildContext context) {
    final startup = manifest.startup;
    final isDeclarative = startup != null && !startup.isEmpty;
    final hasBackgroundTrigger =
        startup?.hasBackgroundActivationTrigger == true;
    final reasons = pluginBackgroundActivationReasons(manifest).join(', ');
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
                  isDeclarative && !hasBackgroundTrigger
                      ? 'הרשאת הרקע אינה בשימוש בגרסה זו של התוסף'
                      : isDeclarative
                      ? 'התוסף מבקש לפעול ברקע כאשר: $reasons'
                      : 'התוסף מבקש לפעול ברקע עם עליית האפליקציה',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: colorScheme.onTertiaryContainer,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  isDeclarative && !hasBackgroundTrigger
                      ? 'לא הוגדר אירוע שמפעיל מנוע רקע. פקדים שפותחים את '
                            'דף התוסף ונתונים סטטיים אינם מפעילים WebView.'
                      : isDeclarative
                      ? 'בעת אחד מהאירועים האלה אוצריא תפעיל WebView נסתר '
                            'עבור התוסף. הוא יכובה לאחר 3 דקות ללא פעילות. '
                            'ההרשאה כבויה כברירת מחדל.'
                      : 'מסלול תאימות זה טוען WebView נסתר עם עליית אוצריא '
                            'ומשאיר אותו פעיל כל עוד התוכנה פתוחה. ההרשאה '
                            'כבויה כברירת מחדל.',
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

/// תוסף ללא ממשק אינו יכול ליפול לפתיחת דף, ולכן כיבוי הרשאות הרקע משבית אותו.
class _HeadlessBanner extends StatelessWidget {
  final ColorScheme colorScheme;

  const _HeadlessBanner({required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer,
        borderRadius: AppTokens.borderRadiusAll,
        border: Border.all(color: colorScheme.secondary, width: 1.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            FluentIcons.info_24_filled,
            color: colorScheme.secondary,
            size: 28,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'זהו תוסף ללא ממשק',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: colorScheme.onSecondaryContainer,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'אין לו דף משלו, והוא פועל רק ברקע. בלי ההרשאות '
                  '"${getPermissionInfo(pluginStartupContributionsPermission).label}" '
                  'ו-"${getPermissionInfo(pluginRunOnStartupPermission).label}" '
                  'התוסף לא יפעל כראוי.',
                  style: TextStyle(
                    fontSize: 13,
                    color: colorScheme.onSecondaryContainer,
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

class _KeepAliveBanner extends StatelessWidget {
  final ColorScheme colorScheme;

  const _KeepAliveBanner({required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer,
        borderRadius: AppTokens.borderRadiusAll,
        border: Border.all(color: colorScheme.error, width: 1.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            FluentIcons.warning_24_filled,
            color: colorScheme.error,
            size: 28,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'התוסף מבקש למנוע את כיבוי מנוע הרקע',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: colorScheme.onErrorContainer,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'אישור הבקשה ישאיר WebView פעיל ללא הגבלת זמן ויגדיל את '
                  'צריכת הזיכרון והמעבד. אפשרות זו כבויה כברירת מחדל.',
                  style: TextStyle(
                    fontSize: 13,
                    color: colorScheme.onErrorContainer,
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
