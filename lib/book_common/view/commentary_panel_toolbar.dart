import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/theme/app_theme_data.dart';
import 'package:otzaria/widgets/misc/commentators_filter_button.dart';

/// סרגל הכפתורים בראש חלונית המפרשים, בקורא הטקסט וב-PDF: בחירת מפרשים,
/// הרחבה או כיווץ של כולם, פתיחה בכרטיסייה וחיפוש.
class CommentaryPanelToolbar extends StatelessWidget {
  const CommentaryPanelToolbar({
    super.key,
    required this.onOpenFilter,
    required this.allExpanded,
    required this.onOpenSearch,
    this.onToggleAllExpanded,
    this.onOpenInNewTab,
  });

  /// ה-tooltip של פתיחת המפרשים בכרטיסייה, גם בכותרת החלונית המפוצלת.
  static const String openInNewTabTooltip = 'פתח כרטיסיית מפרשים';

  final VoidCallback onOpenFilter;
  final bool allExpanded;
  final VoidCallback onOpenSearch;

  /// null: אין מפרשים נבחרים, והכפתור מוסתר.
  final VoidCallback? onToggleAllExpanded;

  /// null: הכפתור מוסתר.
  final VoidCallback? onOpenInNewTab;

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(width: 16);
    final theme = Theme.of(context);
    // גובה 36 כשדה החיפוש המצומצם, כדי שפתיחת החיפוש לא תזיז את הרשימה.
    return IconButtonTheme(
      data: IconButtonThemeData(
        style: (theme.iconButtonTheme.style ?? const ButtonStyle()).copyWith(
          visualDensity: theme.extension<AppMenuMetrics>()?.compactMenus == true
              ? const VisualDensity(vertical: -1)
              : null,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CommentatorsFilterButton(
            isActive: false,
            onPressed: onOpenFilter,
          ),
          if (onToggleAllExpanded != null) ...[
            gap,
            IconButton(
              icon: Icon(
                allExpanded
                    ? FluentIcons.arrow_collapse_all_24_regular
                    : FluentIcons.arrow_expand_all_24_regular,
              ),
              tooltip: allExpanded
                  ? 'כווץ את כל המפרשים'
                  : 'הרחב את כל המפרשים',
              onPressed: onToggleAllExpanded,
            ),
          ],
          if (onOpenInNewTab != null) ...[
            gap,
            IconButton(
              icon: const Icon(FluentIcons.open_24_regular),
              tooltip: openInNewTabTooltip,
              onPressed: onOpenInNewTab,
            ),
          ],
          gap,
          IconButton(
            icon: const Icon(FluentIcons.search_24_regular),
            tooltip: 'חיפוש',
            onPressed: onOpenSearch,
          ),
        ],
      ),
    );
  }
}
