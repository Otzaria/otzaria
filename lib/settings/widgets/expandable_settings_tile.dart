import 'package:flutter/material.dart';
import 'package:otzaria/settings/widgets/settings_card.dart';
import 'package:otzaria/widgets/misc/expanding_chevron.dart';

/// כותרת של `ExpandableCard` בהגדרות (DD-27): שורת [SettingsActionTile]
/// רגילה, עם חץ אקורדיון צמוד לטקסט.
///
/// ```dart
/// ExpandableCard(
///   wrapInCard: false,
///   isExpanded: _open,
///   header: ExpandableSettingsTile(
///     title: 'גיבוי אוטומטי',
///     isExpanded: _open,
///     onTap: () => setState(() => _open = !_open),
///   ),
///   children: [...],
/// )
/// ```
class ExpandableSettingsTile extends StatelessWidget {
  final Key? headerKey;
  final IconData? icon;
  final String title;
  final String? subtitle;

  /// ווידג'ט אופציונלי לפני החץ (לדוגמה: [AppSegmentedControl]).
  final Widget? trailing;
  final bool isExpanded;

  /// null — אין תוכן להצגה: בלי חץ ובלי לחיצה.
  final VoidCallback? onTap;

  const ExpandableSettingsTile({
    super.key,
    this.headerKey,
    this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    required this.isExpanded,
    required this.onTap,
  });

  // החץ ב-pinnedTrailing כדי שיישאר צמוד לטקסט ולא יגלוש מתחתיו יחד עם
  // trailing כש-SettingsActionTile נופל ל-layout אנכי.
  @override
  Widget build(BuildContext context) => SettingsActionTile.text(
    key: headerKey,
    icon: icon,
    title: title,
    subtitle: subtitle,
    actions: trailing != null ? [trailing!] : const [],
    pinnedTrailing: onTap != null
        ? ExpandingChevron(isExpanded: isExpanded)
        : null,
    onTap: onTap,
  );
}
