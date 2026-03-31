// lib/settings/widgets/switch_settings_tile.dart
//
// מכיל:
//  • [CustomSwitch]       — Switch תואם M3 עם hover מדויק
//  • [SwitchSettingsTile] — ListTile עם CustomSwitch
//
// **שימוש:**
// ```dart
// SwitchSettingsTile(
//   title: const Text('הפעל מצב חסוך'),
//   value: state.safeModeEnabled,
//   onChanged: (v) => context.read<Bloc>().add(SetSafeMode(v)),
// )
// ```

import 'package:flutter/material.dart';

// ── CustomSwitch ───────────────────────────────────────────────────────────────

/// [Switch] תואם M3 — thumb/track/overlay מוגדרים לפי:
/// https://m3.material.io/components/switch/specs
///
/// תיקון hover במצב כהה: ברירת המחדל של Flutter משתמשת ב-primary חזק מדי.
/// overlayColor מינימלי — 8% שקיפות דינמי לפי מצב המתג.
class CustomSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool autofocus;
  final FocusNode? focusNode;

  const CustomSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.autofocus = false,
    this.focusNode,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Switch(
      value: value,
      onChanged: onChanged,
      autofocus: autofocus,
      focusNode: focusNode,
      thumbColor: WidgetStateProperty.resolveWith((s) {
        if (s.contains(WidgetState.disabled)) {
          return cs.onSurface.withValues(alpha: 0.38);
        }
        if (s.contains(WidgetState.selected)) return cs.onPrimary;
        if (s.contains(WidgetState.hovered)) return cs.onSurfaceVariant;
        return cs.outline;
      }),
      trackColor: WidgetStateProperty.resolveWith((s) {
        if (s.contains(WidgetState.disabled)) {
          return cs.surfaceContainerHighest.withValues(alpha: 0.12);
        }
        if (s.contains(WidgetState.selected)) return cs.primary;
        return cs.surfaceContainerHighest;
      }),
      trackOutlineColor: WidgetStateProperty.resolveWith((s) {
        if (s.contains(WidgetState.selected)) return Colors.transparent;
        return cs.outline;
      }),
      overlayColor: WidgetStateProperty.resolveWith((s) {
        if (s.contains(WidgetState.hovered)) {
          return (value ? cs.primary : cs.onSurface).withValues(alpha: 0.12);
        }
        return null;
      }),
    );
  }
}

// ── SwitchSettingsTile ────────────────────────────────────────────────────────

/// [ListTile] עם [CustomSwitch] — עקבי עם כל שורות on/off בהגדרות.
///
/// tap על ה-ListTile כולו מחליף את הערך (נגישות מלאה).
class SwitchSettingsTile extends StatelessWidget {
  final Widget? leading;
  final Widget title;
  final Widget? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool enabled;

  const SwitchSettingsTile({
    super.key,
    this.leading,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: leading,
      title: title,
      subtitle: subtitle,
      enabled: enabled,
      trailing: CustomSwitch(
        value: value,
        onChanged: enabled ? onChanged : null,
      ),
      onTap: enabled && onChanged != null ? () => onChanged!(!value) : null,
    );
  }
}
