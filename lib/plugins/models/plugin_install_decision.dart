import 'package:otzaria/plugins/models/plugin_manifest.dart';
import 'package:otzaria/plugins/models/plugin_permission_labels.dart';
import 'package:otzaria/plugins/models/plugin_valid_permissions.dart';

/// מה התקנה או עדכון של תוסף משאירים להחלטת המשתמש.
///
/// הכלל חי כאן ולא במסך ההרשאות משום ששני מקומות נשענים עליו: המסך, שמחליט
/// מה להציג, והמארח, שמחליט אם בכלל לפתוח אותו (issue #1410). שני עותקים של
/// הכלל היו מתפצלים בשינוי הראשון.
class PluginInstallDecision {
  /// הרשאות המניפסט בסדר ההצגה — הרגישות ראשונות.
  final List<String> orderedPermissions;

  /// הרשאות שהתוסף מבקש לראשונה (אין עליהן החלטה שמורה).
  final List<String> newPermissions;

  /// הרשאות מוכרות שמתחילות כבויות או שאינן זמינות זמנית במצב מנותק.
  final List<String> revokedPermissions;

  /// מצב ה-toggle ההתחלתי לכל הרשאה.
  final Map<String, bool> permissionToggles;

  /// שאלת ההקדמה לפני הכלים המובנים נשאלת רק כשאין עליה החלטה קודמת.
  final bool requestsOrderBeforeBuiltIns;

  /// הרשאות שההחלטה עליהן נשמרה אך הגישה אינה זמינה כרגע (מצב מנותק).
  final Set<String> temporarilyUnavailablePermissions;

  /// האם זהו עדכון לגרסה מותקנת.
  final bool isUpdate;

  const PluginInstallDecision({
    required this.orderedPermissions,
    required this.newPermissions,
    required this.revokedPermissions,
    required this.permissionToggles,
    required this.requestsOrderBeforeBuiltIns,
    required this.temporarilyUnavailablePermissions,
    required this.isUpdate,
  });

  /// עדכון שאינו דורש שום החלטה מהמשתמש.
  bool get isPlainUpdate =>
      isUpdate &&
      newPermissions.isEmpty &&
      revokedPermissions.isEmpty &&
      !requestsOrderBeforeBuiltIns;

  /// האם יש בכלל מה לשאול. עדכון שאין בו החלטה מאושר בלי דיאלוג — המשתמש
  /// הוא זה שביקש את העדכון, וההרשאות שהעניק נשארות כפי שהן.
  bool get requiresUserDecision => !isPlainUpdate;
}

/// מחשב את [PluginInstallDecision] עבור מניפסט שעומד להיות מותקן.
///
/// [previousVersion] `null` = התקנה ראשונה. [previousGrantedPermissions] הן
/// החלטות ההרשאה השמורות של הגרסה המותקנת.
PluginInstallDecision resolvePluginInstallDecision({
  required PluginManifest manifest,
  required String? previousVersion,
  required Map<String, bool> previousGrantedPermissions,
  required bool? previousAllowOrderBeforeBuiltInsGranted,
  required bool isOfflineMode,
}) {
  final isUpdate = previousVersion != null;
  final effective = effectiveManifestPermissions(manifest.permissions);

  /// החלטת עבר נשמרת גם כשהגישה עצמה אינה זמינה זמנית במצב מנותק.
  bool initialGrantFor(String permission) =>
      previousGrantedPermissions[permission] ??
      pluginPermissionDefaultGrant(permission, isOfflineMode: isOfflineMode);

  bool isTemporarilyUnavailable(String permission) =>
      isUpdate &&
      isOfflineMode &&
      permission == pluginNetworkAccessPermission &&
      previousGrantedPermissions[permission] == true;

  final toggles = {for (final p in effective) p: initialGrantFor(p)};
  final ordered = orderedPluginPermissions(
    effective,
    isOfflineMode: isOfflineMode,
  );

  return PluginInstallDecision(
    orderedPermissions: ordered,
    newPermissions: ordered
        .where((p) => !previousGrantedPermissions.containsKey(p))
        .toList(),
    revokedPermissions: ordered
        .where(
          (p) =>
              previousGrantedPermissions.containsKey(p) &&
              (toggles[p] == false || isTemporarilyUnavailable(p)),
        )
        .toList(),
    permissionToggles: toggles,
    requestsOrderBeforeBuiltIns:
        manifest.allowOrderBeforeBuiltIns &&
        previousAllowOrderBeforeBuiltInsGranted == null,
    temporarilyUnavailablePermissions: ordered
        .where(isTemporarilyUnavailable)
        .toSet(),
    isUpdate: isUpdate,
  );
}
