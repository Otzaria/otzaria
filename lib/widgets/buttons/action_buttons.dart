// lib/widgets/buttons/action_buttons.dart
//
// כפתורי פעולה גנריים בסגנון M3.
//
// מכיל:
//  • [RecommendedActionButton] — כפתור פעולה מומלצת (Primary)
//  • [NeutralActionButton]     — כפתור פעולה ניטרלית (Tonal/SecondaryContainer)
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

// ── CustomSidebarItem ─────────────────────────────────────────────────────────

/// פריט sidebar גנרי עם תמיכה ב-Material 3 states
///
/// - Unselected: אייקון regular, רקע שקוף
/// - Selected: אייקון filled, רקע secondaryContainer
/// - Hover: primary.withOpacity(0.08)
class CustomSidebarItem extends StatelessWidget {
  final IconData icon;
  final IconData? selectedIcon; // אייקון filled אופציונלי
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const CustomSidebarItem({
    super.key,
    required this.icon,
    this.selectedIcon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final effectiveIcon = isSelected ? (selectedIcon ?? icon) : icon;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      overlayColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.hovered)) {
          return cs.primary.withValues(alpha: 0.08);
        }
        return null;
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: isSelected ? cs.secondaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              effectiveIcon,
              size: 32,
              color: isSelected ? cs.onSecondaryContainer : cs.onSurfaceVariant,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                color:
                    isSelected ? cs.onSecondaryContainer : cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
