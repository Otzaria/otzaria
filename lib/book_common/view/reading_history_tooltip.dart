import 'package:flutter/widgets.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';

/// תיאור כפתור היסטוריה: עם שם היעד כשידוע, אחרת הנוסח הכללי.
String historyTooltip(
  BuildContext context,
  String place,
  String generic,
  String withPlace,
) {
  final trimmed = place.trim();
  return trimmed.isEmpty
      ? context.settingsText(generic)
      : context.settingsText(withPlace, args: {'place': trimmed});
}
