// lib/widgets/buttons/action_buttons.dart
//
// כפתורי פעולה גנריים בסגנון M3.
//
// מכיל:
//  • [RecommendedActionButton] — כפתור פעולה מומלצת (Primary)
//  • [NeutralActionButton]     — כפתור פעולה ניטרלית (Tonal/SecondaryContainer)
//  • [ToolbarActionButton]     — כפתור סרגל כלי עבודה / פעיל (Pill)
//
// ℹ️ ניווט בסיידבר: ראה SidebarNavItem (lib/widgets/sidebar_nav_item.dart)
// ℹ️ ניווט ב-NavRail ראשי: ראה NavRailItem (lib/widgets/nav_rail_item.dart)
//
// **שימוש:**
// ```dart
// RecommendedActionButton(text: 'שמור', onPressed: _save)
// NeutralActionButton(text: 'בטל', onPressed: _cancel)
// RecommendedActionButton(text: 'שמור', onPressed: _save, icon: Icons.save, isLoading: _saving)
// ```

import 'package:flutter/material.dart';

// ── RecommendedActionButton ───────────────────────────────────────────────────

/// כפתור פעולה מומלצת — Primary FilledButton
///
/// - [isLoading] מציג CircularProgressIndicator קטן
/// - [icon] אופציונלי — מציג FilledButton.icon
class RecommendedActionButton extends StatelessWidget {
  final String text;
  final VoidCallback onPressed;
  final bool isLoading;
  final IconData? icon;

  const RecommendedActionButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.isLoading = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final style = FilledButton.styleFrom(
        backgroundColor: cs.primary, foregroundColor: cs.onPrimary);

    if (isLoading) {
      return FilledButton(
          onPressed: null,
          style: style,
          child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: cs.onPrimary)));
    }
    if (icon != null) {
      return FilledButton.icon(
          onPressed: onPressed,
          style: style,
          icon: Icon(icon),
          label: Text(text));
    }
    return FilledButton(onPressed: onPressed, style: style, child: Text(text));
  }
}

// ── NeutralActionButton ───────────────────────────────────────────────────────

/// כפתור פעולה ניטרלית — Tonal/SecondaryContainer FilledButton
///
/// - [isLoading] מציג CircularProgressIndicator קטן
/// - [icon] אופציונלי — מציג FilledButton.tonalIcon
class NeutralActionButton extends StatelessWidget {
  final String text;
  final VoidCallback onPressed;
  final bool isLoading;
  final IconData? icon;

  const NeutralActionButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.isLoading = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final style = FilledButton.styleFrom(
        backgroundColor: cs.secondaryContainer,
        foregroundColor: cs.onSecondaryContainer);

    if (isLoading) {
      return FilledButton.tonal(
          onPressed: null,
          style: style,
          child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: cs.onSecondaryContainer)));
    }
    if (icon != null) {
      return FilledButton.tonalIcon(
          onPressed: onPressed,
          style: style,
          icon: Icon(icon),
          label: Text(text));
    }
    return FilledButton.tonal(
        onPressed: onPressed, style: style, child: Text(text));
  }
}

// ── ToolbarActionButton ──────────────────────────────────────────────────────

/// כפתור סרגל כלים בסגנון M3.
///
/// מתאים לכפתורי AppBar, פאנלים צפים ותצוגות בינאריות/רב-מצביות.
/// כש-[selected] הוא `true`, הכפתור מקבל רקע בולט יותר.
class ToolbarActionButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final bool selected;
  final String? label;

  const ToolbarActionButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.selected = false,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final backgroundColor = selected ? cs.primaryContainer : cs.surfaceContainerHighest;
    final foregroundColor = selected ? cs.onPrimaryContainer : cs.onSurface;
    final style = FilledButton.styleFrom(
      backgroundColor: backgroundColor,
      foregroundColor: foregroundColor,
      padding: label == null
          ? const EdgeInsets.symmetric(horizontal: 12, vertical: 10)
          : const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      shape: const StadiumBorder(),
    );

    final button = label == null
        ? FilledButton(
            onPressed: onPressed,
            style: style,
            child: Icon(icon, size: 18),
          )
        : FilledButton.icon(
            onPressed: onPressed,
            style: style,
            icon: Icon(icon, size: 18),
            label: Text(label!),
          );

    return Tooltip(
      message: tooltip,
      child: button,
    );
  }
}
