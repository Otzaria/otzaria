// lib/tools/widgets/tool_ui_helpers.dart
//
// עזרי UI לכלי האפליקציה — צבע רקע כרטיסים, כפתורי פעולה, ToolPanelWrapper.
//
// מכיל:
//  • [toolCardColor]       — צבע רקע כרטיס תוצאות (תואם SettingsCard)
//  • [ToolCopyButton]      — כפתור העתקה (secondaryContainer)
//  • [ToolNavigateButton]  — כפתור פתיחת מקור (primary)
//  • [ToolPanelWrapper]    — עוטף תוכן כלי ברקע הגדרות + מרכוז אופקי
//
// **שימוש:**
// ```dart
// // כרטיס תוצאה
// Container(color: toolCardColor(context), ...)
//
// // כפתורים
// ToolCopyButton(onPressed: () => _copy(context))
// ToolNavigateButton(onPressed: () => _navigate(context))
//
// // עוטף מסך
// ToolPanelWrapper(child: Column(...))
// ToolPanelWrapper(hasNavigationBar: true, child: TabBarView(...))
// ```

import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/theme/theme_exports.dart';

// ── toolCardColor ─────────────────────────────────────────────────────────────

/// צבע רקע כרטיסי תוצאות בכלי האפליקציה — תואם לסגנון SettingsCard.
///
/// - כהה: [ColorScheme.surfaceContainer]
/// - בהיר: [ColorScheme.surface]
Color toolCardColor(BuildContext context) {
  final theme = Theme.of(context);
  return theme.brightness == Brightness.dark
      ? theme.colorScheme.surfaceContainer
      : theme.colorScheme.surface;
}

// ── ToolCopyButton ────────────────────────────────────────────────────────────

/// כפתור העתקת תוצאה — Tonal (secondaryContainer) עם אייקון העתק.
class ToolCopyButton extends StatelessWidget {
  final VoidCallback onPressed;
  final String tooltip;

  const ToolCopyButton({
    super.key,
    required this.onPressed,
    this.tooltip = 'העתק',
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: IconButton(
        icon: const Icon(FluentIcons.copy_24_regular, size: 20),
        onPressed: onPressed,
        style: IconButton.styleFrom(
          backgroundColor: cs.secondaryContainer,
          foregroundColor: cs.onSecondaryContainer,
          minimumSize: const Size(36, 36),
          padding: EdgeInsets.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    );
  }
}

// ── ToolNavigateButton ────────────────────────────────────────────────────────

/// כפתור פתיחת מקור — Primary עם אייקון פתיחה.
class ToolNavigateButton extends StatelessWidget {
  final VoidCallback onPressed;
  final String tooltip;

  const ToolNavigateButton({
    super.key,
    required this.onPressed,
    this.tooltip = 'פתח מקור',
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: IconButton(
        icon: const Icon(FluentIcons.open_24_regular, size: 20),
        onPressed: onPressed,
        style: IconButton.styleFrom(
          backgroundColor: cs.primary,
          foregroundColor: cs.onPrimary,
          minimumSize: const Size(36, 36),
          padding: EdgeInsets.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    );
  }
}

// ── ToolPanelWrapper ──────────────────────────────────────────────────────────

/// עוטף תוכן כלי ברקע מסך ההגדרות ומרכז אותו אופקית עם הגבלת רוחב.
///
/// [hasNavigationBar] = true  → רק רקע, ללא הגבלת רוחב (כשיש TabBar/Sidebar).
/// [hasNavigationBar] = false → רקע + Align(topCenter) + maxWidth 860px.
///
/// **שימוש:**
/// ```dart
/// // מסך עצמאי
/// return ToolPanelWrapper(child: Column(...));
///
/// // מסך עם TabBar
/// Scaffold(
///   body: Column(
///     children: [
///       TabBar(...),
///       Expanded(
///         child: ToolPanelWrapper(hasNavigationBar: true, child: TabBarView(...)),
///       ),
///     ],
///   ),
/// )
/// ```
class ToolPanelWrapper extends StatelessWidget {
  final Widget child;
  final bool hasNavigationBar;

  const ToolPanelWrapper({
    super.key,
    required this.child,
    this.hasNavigationBar = false,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = AppSurfaces.panelBackground(context);

    if (hasNavigationBar) {
      return ColoredBox(color: bgColor, child: child);
    }

    return ColoredBox(
      color: bgColor,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: LayoutConstraints.panelContentMaxWidth,
          ),
          child: child,
        ),
      ),
    );
  }
}
