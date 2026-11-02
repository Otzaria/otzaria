import 'package:flutter/material.dart';
import 'package:otzaria/theme/app_surfaces.dart';

/// צבעי תצוגת הגרירה הנייטיבית, שמצוירת ב-GDI ב-`windows/runner` ואינה
/// יכולה לקרוא את `Theme.of(context)` — כאן הערכה מתורגמת אליה.
///
/// ⚠️ הצבעים נלקחים מ-`AppSurfaces` ומ-`colorScheme`, ולא מ-literal-ים.
/// הרקע של המוק מגיע מ-`ReadingTabStrip.stripColor`, שם הוא באמת נצבע.
@immutable
class DragPreviewColors {
  const DragPreviewColors({
    required this.tab,
    required this.border,
    required this.text,
  });

  /// בונה מהערכה של [context] — בדיוק אותם משטחים שהכרטיסיה האמיתית
  /// משתמשת בהם, כדי שהרוח תיראה כמו מה שתחליף אותה.
  factory DragPreviewColors.of(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DragPreviewColors(
      // הכרטיסיה הפעילה — אותו משטח בדיוק כמו ב-`_tabBackgroundPainter`.
      tab: AppSurfaces.topBarBackground(context),
      border: scheme.outlineVariant,
      text: scheme.onSurface,
    );
  }

  final Color tab;
  final Color border;
  final Color text;

  /// ⚠️ `toARGB32` ולא `.value`: השני יצא deprecated, והצד הנייטיבי מצפה
  /// ל-int יחיד שממנו הוא חולץ R/G/B.
  Map<String, int> toArgb() => {
    'tab': tab.toARGB32(),
    'border': border.toARGB32(),
    'text': text.toARGB32(),
  };
}
