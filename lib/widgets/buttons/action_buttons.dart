// lib/widgets/buttons/action_buttons.dart
//
// כפתורי פעולה גנריים בסגנון M3.
//
// **שינויים v4:**
// • ToolbarActionButton — selected משתמש ב-primary/onPrimary
//   כדי לבלוט בצורה ברורה על סרגל secondaryContainer.
// • מצב לא נבחר נשאר שקט יותר עם surface containers.

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
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

// ── ToolCopyButton / ToolNavigateButton ──────────────────────────────────────

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

// ── ToolbarActionButton ──────────────────────────────────────────────────────

/// כפתור סרגל כלים בסגנון M3 עם נראות מוגברת למצב נבחר.
///
/// **2 מצבים:**
/// • [compact] = false (touch):   כפתור עגול/pill גדול, icon 20px
/// • [compact] = true (desktop):  כפתור עגול/pill קטן, icon 16px
///
/// **צבעים:**
/// • selected prominent: primary / onPrimary
/// • selected subtle:    secondaryContainer / onSecondaryContainer
/// • unselected:         transparent / onSurfaceVariant
enum ToolbarActionButtonEmphasis { prominent, subtle }

class ToolbarActionButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final Widget? iconWidget;
  final VoidCallback onPressed;
  final bool selected;
  final String? label;
  final ToolbarActionButtonEmphasis emphasis;

  /// true = desktop — כפתור קטן ועגול
  final bool compact;

  const ToolbarActionButton({
    super.key,
    required this.tooltip,
    required this.icon,
    this.iconWidget,
    required this.onPressed,
    this.selected = false,
    this.label,
    this.compact = false,
    this.emphasis = ToolbarActionButtonEmphasis.prominent,
  });

  Color _bgColor(ColorScheme cs) {
    if (!selected) return Colors.transparent;
    return switch (emphasis) {
      ToolbarActionButtonEmphasis.prominent => cs.primary,
      ToolbarActionButtonEmphasis.subtle =>
        cs.secondaryContainer.withValues(alpha: 0.72),
    };
  }

  Color _fgColor(ColorScheme cs) {
    if (!selected) return cs.onSurfaceVariant;
    return switch (emphasis) {
      ToolbarActionButtonEmphasis.prominent => cs.onPrimary,
      ToolbarActionButtonEmphasis.subtle => cs.onSecondaryContainer,
    };
  }

  Color _overlayColor(ColorScheme cs) {
    if (selected) {
      return switch (emphasis) {
        ToolbarActionButtonEmphasis.prominent =>
          cs.onPrimary.withValues(alpha: 0.10),
        ToolbarActionButtonEmphasis.subtle =>
          cs.onSecondaryContainer.withValues(alpha: 0.10),
      };
    }
    return cs.onSurface.withValues(alpha: 0.08);
  }

  @override
  Widget build(BuildContext context) {
    return compact ? _buildCompact(context) : _buildStandard(context);
  }

  // ── Touch ────────────────────────────────────────────────────────────────

  Widget _buildStandard(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = _bgColor(cs);
    final fg = _fgColor(cs);
    final overlay = _overlayColor(cs);

    Widget button;
    if (label != null) {
      button = FilledButton.icon(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: fg,
          padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 8.0),
          shape: const StadiumBorder(),
          minimumSize: const Size(0, 40),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ).copyWith(
          overlayColor: WidgetStatePropertyAll(overlay),
        ),
        icon: iconWidget ?? Icon(icon, size: 20),
        label: Text(label!, style: const TextStyle(fontSize: 14.0)),
      );
    } else {
      button = IconButton(
        onPressed: onPressed,
        icon: iconWidget ?? Icon(icon, size: 20),
        padding: const EdgeInsets.all(8.0),
        constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
        style: IconButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: fg,
          shape: const CircleBorder(),
          highlightColor: overlay,
        ),
      );
    }

    return Tooltip(message: tooltip, child: button);
  }

  // ── Desktop ───────────────────────────────────────────────────────────────

  Widget _buildCompact(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = _bgColor(cs);
    final fg = _fgColor(cs);
    final overlay = _overlayColor(cs);

    Widget button;
    if (label != null) {
      button = FilledButton.icon(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: fg,
          padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 5.0),
          shape: const StadiumBorder(),
          minimumSize: const Size(0, 28),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ).copyWith(
          overlayColor: WidgetStatePropertyAll(overlay),
        ),
        icon: iconWidget ?? Icon(icon, size: 15),
        label: Text(label!, style: const TextStyle(fontSize: 12.0)),
      );
    } else {
      button = IconButton(
        onPressed: onPressed,
        icon: iconWidget ?? Icon(icon, size: 16),
        padding: const EdgeInsets.all(6.0),
        constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
        style: IconButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: fg,
          shape: const CircleBorder(),
          highlightColor: overlay,
        ),
      );
    }

    return Tooltip(message: tooltip, child: button);
  }
}
