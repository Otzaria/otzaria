// lib/widgets/buttons/action_buttons.dart
//
// כפתורי פעולה גנריים בסגנון M3.
//
// מכיל:
//  • [RecommendedActionButton] — כפתור פעולה מומלצת (Primary)
//  • [NeutralActionButton]     — כפתור פעולה ניטרלית (Tonal/SecondaryContainer)
//  • [ToolbarActionButton]     — כפתור סרגל כלים — תומך ב-2 מצבים:
//       compact=false (touch):   Pill FilledButton עם/בלי תווית
//       compact=true  (desktop): IconButton עגול קטן בסגנון Chrome M3
//
// **שימוש:**
// ```dart
// // Touch (ברירת מחדל):
// ToolbarActionButton(tooltip: 'הגדרות', icon: Icons.settings, onPressed: _s)
//
// // Desktop:
// ToolbarActionButton(tooltip: 'הגדרות', icon: Icons.settings, onPressed: _s,
//                     compact: true)
//
// // עם תווית (מוצגת רק כאשר label != null — ב-compact: תווית קטנה בתוך pill):
// ToolbarActionButton(tooltip: '...', icon: Icons.sync, onPressed: _s,
//                     label: 'סנכרון')
// ```

import 'package:flutter/material.dart';

// ── RecommendedActionButton ───────────────────────────────────────────────────

/// כפתור פעולה מומלצת — Primary FilledButton
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
/// **2 מצבים:**
/// • [compact] = false (touch, ברירת מחדל):
///     - Pill (StadiumBorder), גודל סטנדרטי
///     - עם [label]: FilledButton.icon; בלי: FilledButton עם אייקון
///     - גובה ~40px, אייקון 18px
///
/// • [compact] = true (desktop/Chrome-like):
///     - IconButton עגול קטן (CircleBorder), 32px
///     - עם [label]: Pill קטן (StadiumBorder), אייקון 16px, טקסט 12px
///     - גובה ~32px, אייקון 16px
///
/// כש-[selected] = true, הכפתור מקבל רקע `primaryContainer`.
class ToolbarActionButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final bool selected;
  final String? label;

  /// true = מצב desktop/עכבר — כפתור קטן ועגול (בסגנון Chrome)
  /// false = מצב touch — pill גדול (ברירת מחדל)
  final bool compact;

  const ToolbarActionButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.selected = false,
    this.label,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return compact ? _buildCompact(context) : _buildStandard(context);
  }

  // ── מצב touch (סטנדרטי) ─────────────────────────────────────────────────

  Widget _buildStandard(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = selected ? cs.primaryContainer : Colors.transparent;
    final fg = selected ? cs.onPrimaryContainer : cs.onSurfaceVariant;

    Widget button;
    if (label != null) {
      // עם תווית: pill גדול
      button = FilledButton.icon(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: bg == Colors.transparent
              ? cs.surfaceContainerHighest.withValues(alpha: 0.6)
              : bg,
          foregroundColor: fg,
          padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 8.0),
          shape: const StadiumBorder(),
          minimumSize: const Size(0, 40),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        icon: Icon(icon, size: 20),
        label: Text(label!, style: const TextStyle(fontSize: 14.0)),
      );
    } else {
      // ללא תווית: כפתור עגול גדול
      button = IconButton(
        onPressed: onPressed,
        icon: Icon(icon, size: 20),
        padding: const EdgeInsets.all(8.0),
        constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
        style: IconButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: fg,
          shape: const CircleBorder(),
          // הוסף overlay בהיר ב-hover
          highlightColor: cs.onSurface.withValues(alpha: 0.08),
        ),
      );
    }

    return Tooltip(message: tooltip, child: button);
  }

  // ── מצב desktop/compact (בסגנון Chrome) ─────────────────────────────────

  Widget _buildCompact(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = selected ? cs.primaryContainer : Colors.transparent;
    final fg = selected ? cs.onPrimaryContainer : cs.onSurfaceVariant;

    Widget button;
    if (label != null) {
      // עם תווית: pill קטן
      button = FilledButton.icon(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: bg == Colors.transparent
              ? cs.surfaceContainerHighest.withValues(alpha: 0.6)
              : bg,
          foregroundColor: fg,
          padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 5.0),
          shape: const StadiumBorder(),
          minimumSize: const Size(0, 28),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        icon: Icon(icon, size: 15),
        label: Text(label!, style: const TextStyle(fontSize: 12.0)),
      );
    } else {
      // ללא תווית: כפתור עגול בסגנון Chrome
      button = IconButton(
        onPressed: onPressed,
        icon: Icon(icon, size: 16),
        padding: const EdgeInsets.all(6.0),
        constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
        style: IconButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: fg,
          shape: const CircleBorder(),
          // הוסף overlay בהיר ב-hover (אפקט Chrome)
          highlightColor: cs.onSurface.withValues(alpha: 0.08),
        ),
      );
    }

    return Tooltip(message: tooltip, child: button);
  }
}
