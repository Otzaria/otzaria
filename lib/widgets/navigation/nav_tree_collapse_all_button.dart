import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';
import 'package:otzaria/widgets/controls/app_icon_button.dart';

/// כפתור "הרחב הכל / כווץ הכל" בכותרת של עץ ניווט: תוכן העניינים בעיון
/// (`TocViewer`) ועץ הסינון של החיפוש (`SearchNavigationTree`).
///
/// כלל אחד לשני העצים (#3103, q12 Q4): כשהכל מכווץ הכפתור הוא "הרחב הכל",
/// וכשמשהו פתוח הוא "כווץ הכל". התווית, האייקון והפעולה הולכים יחד לפי
/// [isCollapsed]. העץ מחליט מה נחשב "הכל מכווץ", ומסתיר את הכפתור כשאין בו
/// ענף שאפשר לפתוח.
class NavTreeCollapseAllButton extends StatelessWidget {
  const NavTreeCollapseAllButton({
    super.key,
    required this.isCollapsed,
    required this.onCollapseAll,
    required this.onExpandAll,
  });

  /// אין בעץ ענף פתוח. אז הכפתור מרחיב, ואחרת מכווץ.
  final bool isCollapsed;
  final VoidCallback onCollapseAll;
  final VoidCallback onExpandAll;

  static const IconData collapseIcon =
      FluentIcons.arrow_collapse_all_24_regular;
  static const IconData expandIcon = FluentIcons.arrow_expand_all_24_regular;

  @override
  Widget build(BuildContext context) {
    return AppIconButton(
      size: AppIconButtonSize.small,
      tooltip: context.settingsText(isCollapsed ? 'הרחב הכל' : 'כווץ הכל'),
      icon: Icon(isCollapsed ? expandIcon : collapseIcon),
      onPressed: isCollapsed ? onExpandAll : onCollapseAll,
    );
  }
}
