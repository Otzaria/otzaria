// lib/widgets/floating_panel.dart
//
// FloatingPanel — פאנל צף בסגנון Material 3.
//
// משמש ליצירת "משטח צף" — מקביל ל-NavigationDrawer, BottomSheet וה-Cards
// המוגבהים שמופיעים בהנחיות M3. מספק elevation + shadow + clip + צבע surface.
//
// **מתי להשתמש:**
// • סרגל ניווט / AppBar שצף מעל הרקע
// • סרגל צד (Sidebar) שצף במסך רחב
// • כרטיס-מיכל (Container Card) לתוכן מקובץ
//
// **Elevation מומלץ (M3 Elevation Levels):**
// • elevation 1 — שכבה עדינה (SettingsCard, Sidebar)
// • elevation 2 — AppBar / TabBar (ברירת מחדל)
// • elevation 4 — Floating Action / Dialog Card
//
// **שימוש בסיסי:**
// ```dart
// FloatingPanel(
//   child: TabBar(...),
// )
// ```
//
// **עם ריפוד:**
// ```dart
// FloatingPanel(
//   elevation: 4,
//   padding: const EdgeInsets.all(AppTokens.spaceMD),
//   child: Column(...),
// )
// ```
//
// **הוספת אפקט ריחוף (hover):**
// FloatingPanel מספק רק את המיכל הצף. כדי להוסיף אפקט ריחוף לפריטים בתוכו,
// השתמש ב-InkWell עם overlayColor:
// ```dart
// InkWell(
//   onTap: onTap,
//   borderRadius: AppTokens.borderRadiusAll,
//   overlayColor: WidgetStateProperty.resolveWith((states) {
//     if (states.contains(WidgetState.hovered)) {
//       return cs.primary.withValues(alpha: 0.08);
//     }
//     if (states.contains(WidgetState.pressed)) {
//       return cs.primary.withValues(alpha: 0.12);
//     }
//     return null;
//   }),
//   child: ...,
// )
// ```

import 'package:flutter/material.dart';
import 'package:otzaria/theme/theme_exports.dart';

/// רוחב מינימלי של פאנל צד בלוח שנה ובמסכים אחרים
const double kSidePanelWidth = 340.0;

/// רוחב מינימלי של תוכן ראשי לצד פאנל צד
const double kMainPanelMinWidth = 500.0;

/// סך הרוחב המינימלי להצגת פאנל צד ותוכן ראשי זה לצד זה
const double kSideBySideMinWidth = kSidePanelWidth + kMainPanelMinWidth;

/// פאנל צף בסגנון M3 — elevation + shadow + clip.
///
/// בונה [Material] עם [elevation], [shadowColor] ו-[clipBehavior].
/// צבע הפאנל:
/// - מצב בהיר: [ColorScheme.surface] (לבן)
/// - מצב כהה: [ColorScheme.surfaceContainer] (אפור כהה)
/// ניתן לדרוס עם [color].
class FloatingPanel extends StatelessWidget {
  /// התוכן בתוך הפאנל
  final Widget child;

  /// גובה ה-elevation (M3 tonal + shadow) — ברירת מחדל: 2
  final double elevation;

  /// ריפוד פנימי אופציונלי
  final EdgeInsetsGeometry? padding;

  /// דריסת צבע הפאנל (אופציונלי)
  final Color? color;

  /// דריסת צבע הצל (אופציונלי) — ברירת מחדל: shadow עם 10% אופקסיטי
  final Color? shadowColor;

  const FloatingPanel({
    super.key,
    required this.child,
    this.elevation = 2,
    this.padding,
    this.color,
    this.shadowColor,
  });

  @override
  Widget build(BuildContext context) {
    // M3: panelBackground (כמו settings_screen ו-measurement_converter)
    final panelColor = color ?? AppSurfaces.panelBackground(context);

    final content = padding != null
        ? Padding(padding: padding!, child: child)
        : child;

    return Material(
      color: panelColor,
      elevation: elevation,
      shadowColor:
          shadowColor ??
          Theme.of(context).colorScheme.shadow.withValues(alpha: 0.10),
      surfaceTintColor: Colors.transparent,
      borderRadius: AppTokens.borderRadiusAll,
      clipBehavior: Clip.antiAlias,
      child: content,
    );
  }
}
