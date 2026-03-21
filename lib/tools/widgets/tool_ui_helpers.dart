// lib/tools/widgets/tool_ui_helpers.dart
//
// עזרי UI לכלי האפליקציה — צבע רקע כרטיסים ו-ToolPanelWrapper.
//
// מכיל:
//  • [toolCardColor]       — צבע רקע כרטיס תוצאות (תואם SettingsCard)
//  • [ToolPanelWrapper]    — עוטף תוכן כלי ברקע הגדרות + מרכוז אופקי
//
// **שימוש:**
// ```dart
// // כרטיס תוצאה
// Container(color: toolCardColor(context), ...)
//
// // עוטף מסך
// ToolPanelWrapper(child: Column(...))
// ToolPanelWrapper(hasNavigationBar: true, child: TabBarView(...))
// ```

import 'package:flutter/material.dart';
import 'package:otzaria/theme/theme_exports.dart';

// ── toolCardColor ─────────────────────────────────────────────────────────────

/// צבע רקע כרטיסי תוצאות בכלי האפליקציה — תואם לסגנון SettingsCard.
///
/// - כהה: [ColorScheme.surfaceContainer]
/// - בהיר: [ColorScheme.surface]
Color toolCardColor(BuildContext context) {
  return AppSurfaces.card(context);
}

// ── ToolPanelWrapper ──────────────────────────────────────────────────────────

/// עוטף תוכן כלי עם אפשרות למרכוז אופקי והגבלת רוחב.
///
/// כברירת מחדל הווידג'ט רק ממרכז ומגביל רוחב, בלי לצבוע רקע נוסף.
/// כך נמנעים משכבות רקע כפולות במסכים שבהם מסך האב כבר קובע את הרקע.
///
/// [centerContent] = true  → Align(topCenter) + maxWidth.
/// [centerContent] = false → מציג את התוכן ברוחב מלא.
/// [paintBackground] = true → צובע את אזורי הרקע שמחוץ לתוכן.
///
/// **שימוש:**
/// ```dart
/// // מסך עצמאי
/// return ToolPanelWrapper(child: Column(...));
///
/// // מסך עם ניווט פנימי/Sidebar
/// return ToolPanelWrapper(centerContent: false, child: Row(...));
/// ```
class ToolPanelWrapper extends StatelessWidget {
  final Widget child;
  final bool centerContent;
  final bool paintBackground;

  const ToolPanelWrapper({
    super.key,
    required this.child,
    this.centerContent = true,
    this.paintBackground = false,
  });

  @override
  Widget build(BuildContext context) {
    Widget content = child;

    if (centerContent) {
      content = Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: LayoutConstraints.panelContentMaxWidth,
          ),
          child: child,
        ),
      );
    }

    if (!paintBackground) {
      return content;
    }

    return ColoredBox(
      color: AppSurfaces.panelBackground(context),
      child: content,
    );
  }
}
