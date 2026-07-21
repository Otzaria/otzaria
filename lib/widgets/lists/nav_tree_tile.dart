import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/theme/app_surfaces.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:otzaria/widgets/widgets_exports.dart';

/// שורת ניווט מרכזית בעיצוב מסך הספרייה: קופסת אייקון עם
/// [ColorScheme.secondaryContainer], כותרת, מונה ו-[ExpandingChevron].
/// משמשת בעץ ניווט תוצאות החיפוש, בהערות אישיות ובשמור וזכור.
class NavTreeTile extends StatelessWidget {
  final String title;
  final String? subtitle;

  /// רמת ההזחה (0 = שורש).
  final int level;

  final bool isSelected;
  final bool isExpanded;
  final bool hasChildren;
  final int? count;

  /// אייקון מותאם (כשלא משתמשים בקופסת תיקייה). נעטף בקופסת האייקון.
  final IconData? icon;

  /// קופסת תיקייה פתוחה/סגורה לפי [isExpanded] במקום [icon].
  final bool useFolderIcon;

  /// leading מותאם שמחליף את קופסת האייקון (למשל לוגו קטלוג חיצוני).
  final Widget? leading;

  /// trailing מותאם שמחליף את המונה (למשל כפתור "נקה סינון").
  final Widget? trailing;

  /// כשאינו null — הכרטיס הוא הסינון הפעיל: מוצג כפתור "נקה סינון" (במקום
  /// המונה) שלחיצתו מנקה. משותף לחיפוש, הערות ושמור-וזכור.
  final VoidCallback? onClearFilter;

  /// כשאינו null — קופסת האייקון הופכת ליעד סינון: בריחוף (או ב-[filterMode])
  /// היא מציגה אייקון סינון, ולחיצה עליה מסננת לפריט זה. לחיצה על שאר השורה
  /// נשארת ל-[onTap] (הרחבה/גלילה).
  final VoidCallback? onFilter;

  /// כופה את אייקון הסינון תמיד (ללא ריחוף) — למסכי מגע.
  final bool filterMode;

  final VoidCallback? onTap;
  final VoidCallback? onToggleExpand;

  /// הזחה נוספת (למשל לספרים תחת קטגוריה).
  final double extraIndent;

  final FontWeight fontWeight;

  const NavTreeTile({
    super.key,
    required this.title,
    required this.level,
    this.subtitle,
    this.isSelected = false,
    this.isExpanded = false,
    this.hasChildren = false,
    this.count,
    this.icon,
    this.useFolderIcon = true,
    this.leading,
    this.trailing,
    this.onClearFilter,
    this.onFilter,
    this.filterMode = false,
    this.onTap,
    this.onToggleExpand,
    this.extraIndent = 0,
    this.fontWeight = FontWeight.w600,
  });

  /// שורת קטגוריה (תיקייה).
  factory NavTreeTile.category({
    Key? key,
    required String title,
    required int level,
    bool isSelected = false,
    bool isExpanded = false,
    bool hasChildren = false,
    int? count,
    Widget? trailing,
    VoidCallback? onClearFilter,
    VoidCallback? onFilter,
    bool filterMode = false,
    VoidCallback? onTap,
    VoidCallback? onToggleExpand,
  }) {
    return NavTreeTile(
      key: key,
      title: title,
      level: level,
      isSelected: isSelected,
      isExpanded: isExpanded,
      hasChildren: hasChildren,
      count: count,
      trailing: trailing,
      onClearFilter: onClearFilter,
      onFilter: onFilter,
      filterMode: filterMode,
      useFolderIcon: true,
      onTap: onTap,
      onToggleExpand: onToggleExpand,
      fontWeight: level == 0 ? FontWeight.w700 : FontWeight.w600,
    );
  }

  /// שורת פריט-עלה (ספר/פריט).
  factory NavTreeTile.book({
    Key? key,
    required String title,
    required int level,
    String? subtitle,
    bool isSelected = false,
    int? count,
    IconData icon = FluentIcons.book_24_regular,
    Widget? leading,
    Widget? trailing,
    VoidCallback? onClearFilter,
    VoidCallback? onFilter,
    bool filterMode = false,
    VoidCallback? onTap,
  }) {
    return NavTreeTile(
      key: key,
      title: title,
      level: level,
      subtitle: subtitle,
      isSelected: isSelected,
      count: count,
      icon: icon,
      useFolderIcon: false,
      leading: leading,
      trailing: trailing,
      onClearFilter: onClearFilter,
      onFilter: onFilter,
      filterMode: filterMode,
      onTap: onTap,
      extraIndent: 12,
      fontWeight: FontWeight.w500,
    );
  }

  static const double _iconBoxSize = 26;
  static const double _iconSize = 14;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final indent = level * 12.0 + extraIndent;

    final iconData = useFolderIcon
        ? (isExpanded
              ? FluentIcons.folder_open_24_regular
              : FluentIcons.folder_24_regular)
        : (icon ?? FluentIcons.document_text_24_regular);

    final Widget baseLeading =
        leading ??
        Container(
          width: _iconBoxSize,
          height: _iconBoxSize,
          decoration: BoxDecoration(
            color: cs.secondaryContainer,
            borderRadius: AppTokens.borderRadiusAll,
          ),
          child: Center(
            child: Icon(
              iconData,
              color: cs.onSecondaryContainer,
              size: _iconSize,
            ),
          ),
        );

    // קופסת האייקון כיעד סינון: בריחוף/מגע מתחלפת לאייקון סינון ולחיצה מסננת.
    final leadingWidget = onFilter == null
        ? baseLeading
        : _FilterableIconBox(
            base: baseLeading,
            filterMode: filterMode,
            onFilter: onFilter!,
          );

    return InkWell(
      onTap: onTap,
      child: Container(
        color: isSelected ? cs.secondaryContainer.withValues(alpha: 0.4) : null,
        padding: EdgeInsetsDirectional.only(
          start: 12 + indent,
          end: 12,
          top: 8,
          bottom: 8,
        ),
        child: Row(
          children: [
            leadingWidget,
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.settingTitle.copyWith(
                      fontWeight: fontWeight,
                      color: cs.onSurface,
                      fontSize: AppTokens.fontMD,
                    ),
                  ),
                  if (subtitle != null && subtitle!.isNotEmpty)
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.settingSubtitle.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (trailing != null)
              trailing!
            else if (onClearFilter != null)
              _ClearFilterButton(onTap: onClearFilter!)
            else if (count != null && count! > 0)
              Text(
                '($count)',
                style: TextStyle(
                  fontSize: AppTokens.fontMD,
                  color: cs.onSurfaceVariant,
                ),
              ),
            if (hasChildren) ...[
              const SizedBox(width: 4),
              IconButton(
                icon: ExpandingChevron(
                  isExpanded: isExpanded,
                  color: cs.onSurfaceVariant,
                  size: 18,
                ),
                visualDensity: VisualDensity.compact,
                onPressed: onToggleExpand,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// כותרת שורש עץ הניווט — יושבת על רקע החלונית (ללא כרטיס/קופסת-אייקון),
/// עם כותרת מודגשת ואופציה לכפתור "נקה סינון" לצדה. משותפת לחיפוש, הערות
/// ושמור-וזכור.
class NavTreeHeader extends StatelessWidget {
  final String title;
  final int? count;
  final bool isSelected;
  final VoidCallback? onTap;
  final VoidCallback? onClearFilter;

  const NavTreeHeader({
    super.key,
    required this.title,
    this.count,
    this.isSelected = false,
    this.onTap,
    this.onClearFilter,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasFilter = onClearFilter != null;

    final content = Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.settingTitle.copyWith(
                fontWeight: FontWeight.w700,
                fontSize: AppTokens.fontMD,
                color: cs.primary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (hasFilter)
            _ClearFilterButton(onTap: onClearFilter!)
          else if (count != null && count! > 0)
            Text(
              '($count)',
              style: TextStyle(
                fontSize: AppTokens.fontMD,
                color: cs.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );

    // ריחוף (ולחיצה לניקוי) רק כשיש סינון פעיל — בפינות מעוגלות כמו הכרטיסים.
    if (!hasFilter) return content;
    return Material(
      color: Colors.transparent,
      borderRadius: AppTokens.borderRadiusAll,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppTokens.borderRadiusAll,
        child: content,
      ),
    );
  }
}

/// עוטף שורת-ניווט בעיצוב הכרטיס המקובץ של מסך הספרייה: רקע [AppSurfaces.card],
/// מפריד בין שורות ([AppCard.sectionDivider]) ופינות מעוגלות בקצות הקבוצה — כך
/// קבוצה עליונה שלמה (תיקייה + צאצאיה) נראית ככרטיס אחד רציף. משותף לחיפוש,
/// הערות ושמור-וזכור.
class NavTreeGroupCard extends StatelessWidget {
  final bool isGroupStart;
  final bool isGroupEnd;
  final Widget child;

  const NavTreeGroupCard({
    super.key,
    required this.isGroupStart,
    required this.isGroupEnd,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    const radius = Radius.circular(AppTokens.radius);
    return Padding(
      padding: EdgeInsets.only(
        top: isGroupStart ? 2 : 0,
        bottom: isGroupEnd ? 2 : 0,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.vertical(
          top: isGroupStart ? radius : Radius.zero,
          bottom: isGroupEnd ? radius : Radius.zero,
        ),
        child: Material(
          color: AppSurfaces.card(context),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!isGroupStart) AppCard.sectionDivider(context),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

/// קופסת אייקון שהופכת ליעד סינון: בריחוף (או ב-[filterMode]) מציגה אייקון
/// סינון על רקע primaryContainer; לחיצה מפעילה [onFilter]. אחרת מציגה את
/// [base] (אייקון התיקייה/הספר הרגיל).
class _FilterableIconBox extends StatefulWidget {
  final Widget base;
  final bool filterMode;
  final VoidCallback onFilter;

  const _FilterableIconBox({
    required this.base,
    required this.filterMode,
    required this.onFilter,
  });

  @override
  State<_FilterableIconBox> createState() => _FilterableIconBoxState();
}

class _FilterableIconBoxState extends State<_FilterableIconBox> {
  static const double _size = 26;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final showFilter = widget.filterMode || _hovered;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onFilter,
        child: showFilter
            ? Tooltip(
                message: 'סנן לפריט זה',
                child: Container(
                  width: _size,
                  height: _size,
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    borderRadius: AppTokens.borderRadiusAll,
                  ),
                  child: Center(
                    child: Icon(
                      FluentIcons.filter_24_regular,
                      color: cs.onPrimaryContainer,
                      size: 14,
                    ),
                  ),
                ),
              )
            : widget.base,
      ),
    );
  }
}

/// כפתור "נקה סינון" — מסמן שהכרטיס הוא הסינון הפעיל ולחיצה מנקה אותו.
/// גובה קבוע כדי לא להגדיל את שורת הכרטיס.
class _ClearFilterButton extends StatelessWidget {
  final VoidCallback onTap;

  const _ClearFilterButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.primaryContainer,
      borderRadius: AppTokens.borderRadiusAll,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 20,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  FluentIcons.dismiss_24_regular,
                  size: 14,
                  color: cs.onPrimaryContainer,
                ),
                const SizedBox(width: 4),
                Text(
                  'נקה סינון',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: cs.onPrimaryContainer,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
