import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria_icons/otzaria_icons.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';
import 'package:otzaria/theme/app_surfaces.dart';
import 'package:otzaria/theme/app_tokens.dart';
import 'package:otzaria/widgets/widgets_exports.dart';

/// עוטף רשימת עץ ניווט כך שכניסת הפוקוס אליה (Tab) נופלת על השורה המסומנת
/// ולא על השורה הראשונה: [NavTreeTile] מסומנת מקבלת עדיפות מעבר (order -1),
/// ושאר השורות נשמרות בסדר הקריאה הרגיל.
class NavTreeFocusGroup extends StatelessWidget {
  final Widget child;

  const NavTreeFocusGroup({super.key, required this.child});

  /// עדיפות הרשימה בתוך החלונית — לפני שורת הלשוניות, כדי שכניסת פוקוס
  /// לחלונית (חץ למטה מסרגל החיפוש) תגיע לשורות ולא ללשוניות.
  static const FocusOrder traversalOrder = NumericFocusOrder(0);

  @override
  Widget build(BuildContext context) {
    return FocusTraversalOrder(
      order: traversalOrder,
      child: FocusTraversalGroup(
        policy: OrderedTraversalPolicy(),
        child: child,
      ),
    );
  }
}

/// שוליים אופקיים בין תוכן עץ הניווט לדופן החלונית. מוגדר כאן פעם אחת —
/// [NavTreeGroupCard] ו-[NavTreeHeader] מיישמים אותו, ואין להוסיף שוליים
/// אופקיים לרשימה בכל חלונית בנפרד.
const double kNavTreeSideInset = 14;

/// שוליים אנכיים בקצות רשימת עץ הניווט.
const EdgeInsets kNavTreeListPadding = EdgeInsets.symmetric(vertical: 6);

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
  /// null יחד עם [useFolderIcon] כבוי ובלי [leading] — שורה ללא קופסת אייקון.
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
    IconData icon = OtzariaIcons.book_24_regular,
    Widget? leading,
    Widget? trailing,
    VoidCallback? onClearFilter,
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
      onTap: onTap,
      extraIndent: 12,
      fontWeight: FontWeight.w500,
    );
  }

  /// שורת כותרת בתוכן עניינים (TOC) של ספר (טקסט או PDF) — טקסט בלבד,
  /// וההזחה לפי [level] בלבד, כדי שכותרות באותה רמה ייושרו לאותו קו.
  factory NavTreeTile.heading({
    Key? key,
    required String title,
    required int level,
    String? subtitle,
    bool isSelected = false,
    bool isExpanded = false,
    bool hasChildren = false,
    int? count,
    IconData? icon,
    Widget? leading,
    Widget? trailing,
    VoidCallback? onTap,
    VoidCallback? onToggleExpand,
  }) {
    return NavTreeTile(
      key: key,
      title: title,
      level: level,
      subtitle: subtitle,
      isSelected: isSelected,
      isExpanded: isExpanded,
      hasChildren: hasChildren,
      count: count,
      icon: icon,
      useFolderIcon: false,
      leading: leading,
      trailing: trailing,
      onTap: onTap,
      onToggleExpand: onToggleExpand,
      extraIndent: 0,
      fontWeight: level == 0
          ? FontWeight.w700
          : (level == 1 ? FontWeight.w600 : FontWeight.w500),
    );
  }

  static const double iconBoxSize = 26;
  static const double iconContentSize = 14;

  /// קופסת האייקון התקנית של שורת העץ — ל-[leading] מותאם שתוכנו אינו
  /// [IconData] (למשל לוגו או תמונה).
  static Widget iconBox(BuildContext context, {required Widget child}) {
    return Container(
      width: iconBoxSize,
      height: iconBoxSize,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: AppTokens.borderRadiusAll,
      ),
      child: Center(child: child),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final indent = level * 12.0 + extraIndent;

    final iconData = useFolderIcon
        ? (isExpanded
              ? FluentIcons.folder_open_24_regular
              : FluentIcons.folder_24_regular)
        : icon;

    final Widget? leadingWidget =
        leading ??
        (iconData == null
            ? null
            : iconBox(
                context,
                child: Icon(
                  iconData,
                  color: cs.onSecondaryContainer,
                  size: iconContentSize,
                ),
              ));

    final row = Semantics(
      selected: isSelected,
      expanded: hasChildren ? isExpanded : null,
      // רקע הבחירה על ה-Material, כדי שהריחוף והלחיצה יצוירו מעליו. הסגנון
      // הנורש נשמר: Material היה מחליף אותו ב-bodyMedium.
      child: Material(
        color: isSelected ? AppSurfaces.selectedRow(cs) : Colors.transparent,
        textStyle: DefaultTextStyle.of(context).style,
        child: InkWell(
          onTap: onTap,
          hoverColor: AppSurfaces.hoverRow(cs),
          child: Container(
            padding: EdgeInsetsDirectional.only(
              start: 12 + indent,
              end: 12,
              top: 8,
              bottom: 8,
            ),
            // גובה מזערי כגובה קופסת האייקון — שורה ללא קופסה (TOC) שומרת על
            // אותו קצב רשימה כמו שורה שיש בה קופסה.
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: iconBoxSize),
              child: Row(
                children: [
                  if (leadingWidget != null) ...[
                    leadingWidget,
                    const SizedBox(width: 9),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        OverflowTooltipText(
                          text: title,
                          maxLines: 1,
                          style: AppTextStyles.settingTitle.copyWith(
                            fontWeight: isSelected
                                ? FontWeight.w700
                                : fontWeight,
                            color: cs.onSurface,
                            fontSize: AppTokens.fontMD,
                          ),
                        ),
                        if (subtitle != null && subtitle!.isNotEmpty)
                          OverflowTooltipText(
                            text: subtitle!,
                            maxLines: 1,
                            style: AppTextStyles.settingSubtitle.copyWith(
                              color: cs.onSurfaceVariant,
                              fontSize: AppTokens.fontSM,
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
                      tooltip: context.settingsText(
                        isExpanded ? 'כווץ' : 'הרחב',
                      ),
                      // המצב שייך לשורה; הכפתור נקרא לפי הפעולה (הרחב/כווץ).
                      icon: ExcludeSemantics(
                        child: ExpandingChevron(
                          isExpanded: isExpanded,
                          style: ExpandingChevronStyle.tree,
                          color: cs.onSurfaceVariant,
                          size: AppTokens.iconSM,
                        ),
                      ),
                      visualDensity: VisualDensity.compact,
                      onPressed: onToggleExpand,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (!isSelected) return row;
    // בתוך [NavTreeFocusGroup] העדיפות הזו מביאה את הפוקוס לשורה המסומנת.
    return FocusTraversalOrder(
      order: const NumericFocusOrder(-1),
      child: row,
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

  /// פעולה קומפקטית בקצה הכותרת.
  final Widget? trailing;

  const NavTreeHeader({
    super.key,
    required this.title,
    this.count,
    this.isSelected = false,
    this.onTap,
    this.onClearFilter,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasFilter = onClearFilter != null;

    // הכותרת מיושרת לטקסט שבתוך הכרטיסים: שוליי הכרטיס + הזחת השורה.
    final content = Padding(
      padding: const EdgeInsets.fromLTRB(
        kNavTreeSideInset + 12,
        10,
        kNavTreeSideInset + 12,
        8,
      ),
      child: OverflowBar(
        alignment: MainAxisAlignment.spaceBetween,
        spacing: AppTokens.spaceSM,
        overflowSpacing: AppTokens.spaceXS,
        children: [
          OverflowTooltipText(
            text: title,
            maxLines: 1,
            style: AppTextStyles.settingTitle.copyWith(
              fontWeight: FontWeight.w700,
              fontSize: AppTokens.fontMD,
              color: cs.primary,
            ),
          ),
          if (hasFilter || (count != null && count! > 0) || trailing != null)
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              runSpacing: AppTokens.spaceXS,
              children: [
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
                ?trailing,
              ],
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

/// שורה בכרטיס עץ הניווט שתוכנה חופשי (למשל קטע של תוצאת חיפוש) — מרווחים
/// ורקע בחירה זהים ל-[NavTreeTile], כדי שלשונית החיפוש תיראה כמו לשוניות העץ.
class NavTreeContentRow extends StatelessWidget {
  final Widget child;
  final bool isSelected;
  final VoidCallback? onTap;

  const NavTreeContentRow({
    super.key,
    required this.child,
    this.isSelected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final row = Semantics(
      selected: isSelected,
      // רקע הבחירה על ה-Material, כדי שהריחוף והלחיצה יצוירו מעליו. הסגנון
      // הנורש נשמר: Material היה מחליף אותו ב-bodyMedium.
      child: Material(
        color: isSelected ? AppSurfaces.selectedRow(cs) : Colors.transparent,
        textStyle: DefaultTextStyle.of(context).style,
        child: InkWell(
          onTap: onTap,
          hoverColor: AppSurfaces.hoverRow(cs),
          child: Padding(
            padding: const EdgeInsetsDirectional.only(
              start: 12,
              end: 12,
              top: 10,
              bottom: 10,
            ),
            child: child,
          ),
        ),
      ),
    );

    if (!isSelected) return row;
    return FocusTraversalOrder(
      order: const NumericFocusOrder(-1),
      child: row,
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
        left: kNavTreeSideInset,
        right: kNavTreeSideInset,
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
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
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
