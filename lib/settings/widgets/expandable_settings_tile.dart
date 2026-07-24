import 'package:flutter/material.dart';
import 'package:otzaria/settings/widgets/settings_card.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/layout/app_card.dart';
import 'package:otzaria/widgets/misc/expanding_chevron.dart';

/// שורת כותרת מורחבת עם תוכן המוסתר/מוצג בלחיצה, לשימוש ב-[AppCard.section].
/// הכותרת נבנית דרך [SettingsActionTile] — כך היא יורשת את אותה גלישת טקסט
class ExpandableSection extends StatelessWidget {
  final Key? headerKey;
  final IconData? icon;
  final String title;
  final String? subtitle;

  /// ווידג'ט אופציונלי לפני הצ'בֺרן (לדוגמה: [AppSegmentedControl]).
  final Widget? trailing;
  final VoidCallback onTap;
  final bool isExpanded;
  final List<Widget> children;

  /// כשאין תוכן להצגה, הצ'בֺרן מוסתר והלחיצה מושבתת.
  final bool hasContent;

  const ExpandableSection({
    super.key,
    this.headerKey,
    this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    required this.onTap,
    required this.isExpanded,
    required this.children,
    this.hasContent = true,
  });

  @override
  Widget build(BuildContext context) {
    // הכותרת היא שורת [SettingsActionTile] רגילה — כמו כל שורה אחרת בכרטיס —
    // עם הצ'בֺרן כ-[pinnedTrailing] כדי שיישאר צמוד לטקסט ולא יגלוש מתחתיו
    // יחד עם trailing כש-SettingsActionTile נופל ל-layout אנכי.
    final header = SettingsActionTile.text(
      key: headerKey,
      icon: icon,
      title: title,
      subtitle: subtitle,
      actions: trailing != null ? [trailing!] : const [],
      pinnedTrailing: hasContent
          ? ExpandingChevron(isExpanded: isExpanded)
          : null,
      onTap: hasContent ? onTap : null,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        header,
        AnimatedSize(
          duration: AppTokens.animNormal,
          curve: Curves.easeInOut,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: isExpanded && hasContent
                ? [
                    AppCard.sectionDivider(context),
                    for (int i = 0; i < children.length; i++) ...[
                      Material(
                        color: AppSurfaces.card(context),
                        child: children[i],
                      ),
                      if (i < children.length - 1)
                        AppCard.sectionDivider(context),
                    ],
                  ]
                : const [],
          ),
        ),
      ],
    );
  }
}
