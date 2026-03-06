import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:otzaria/theme/app_theme.dart';

// ════════════════════════════════════════════════════════════════════════════
// קבועי סגנון — גשרים ל-AppTextStyles
// ════════════════════════════════════════════════════════════════════════════

/// כותרת שורת הגדרה (16sp) — alias ל-[AppTextStyles.settingTitle].
/// קוד קיים שמשתמש ב-kSettingsTitleStyle ממשיך לעבוד ללא שינוי.
const TextStyle kSettingsTitleStyle = AppTextStyles.settingTitle;

/// תת-כותרת שורת הגדרה (13sp) — alias ל-[AppTextStyles.settingSubtitle].
const TextStyle kSettingsSubtitleStyle = AppTextStyles.settingSubtitle;

/// רווח אנכי סטנדרטי בין כרטיסי הגדרות.
const SizedBox kSettingsCardSpacing = SizedBox(height: AppTokens.spaceMD);

// ════════════════════════════════════════════════════════════════════════════
// SegmentedSettingsTile — שורת הגדרה עם SegmentedButton (M3)
// ════════════════════════════════════════════════════════════════════════════

/// Widget להגדרה עם [SegmentedButton] — בהתאם לספציפיקציית M3:
/// https://m3.material.io/components/segmented-buttons/overview
///
/// - ✓ מסמן את האפשרות הנבחרת
/// - גבולות חיצוניים קבועים (מונע קפיצת פריסה בעת בחירה)
/// - פריסה אדפטיבית: כותרת מעל ב-narrow, ListTile ב-wide
/// - ניווט מקלדת: חצים ← → לבחירה, Enter/Space לאישור
///
/// **שימוש:**
/// ```dart
/// SegmentedSettingsTile<int>(
///   title: 'שיטת גימטריה',
///   options: [
///     SegmentOption(value: 0, label: 'רגיל'),
///     SegmentOption(value: 1, label: 'קטנה'),
///   ],
///   currentValue: 0,
///   onChanged: (v) => setState(() => _method = v),
/// )
/// ```
class SegmentedSettingsTile<T> extends StatefulWidget {
  final dynamic title;
  final String? subtitle;
  final IconData? icon;
  final List<SegmentOption<T>> options;
  final T currentValue;
  final ValueChanged<T> onChanged;

  const SegmentedSettingsTile({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    required this.options,
    required this.currentValue,
    required this.onChanged,
  });

  @override
  State<SegmentedSettingsTile<T>> createState() =>
      _SegmentedSettingsTileState<T>();
}

class _SegmentedSettingsTileState<T> extends State<SegmentedSettingsTile<T>> {
  final FocusNode _focusNode = FocusNode();
  int _focusedIndex = 0;

  @override
  void initState() {
    super.initState();
    _focusedIndex =
        widget.options.indexWhere((o) => o.value == widget.currentValue);
    if (_focusedIndex < 0) _focusedIndex = 0;
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasIcons = widget.options.any((o) => o.icon != null);
    final maxLen = widget.options
        .map((o) => o.label.length)
        .reduce((a, b) => a > b ? a : b);
    final btnWidth = (hasIcons ? 80.0 : 60.0) + maxLen * 8.0;
    final totalW =
        (btnWidth * widget.options.length + 24.0).clamp(180.0, 400.0);

    return LayoutBuilder(builder: (ctx, constraints) {
      final isNarrow = constraints.maxWidth < totalW + 200;
      final button = _buildButton(cs, hasIcons, totalW);

      if (isNarrow) {
        return Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppTokens.spaceMD, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _titleWidget(ctx),
              const SizedBox(height: 12),
              Align(alignment: Alignment.centerRight, child: button),
            ],
          ),
        );
      }
      return ListTile(
        leading: widget.icon != null ? Icon(widget.icon) : null,
        title: _titleWidget(ctx),
        subtitle: widget.subtitle != null
            ? Text(widget.subtitle!, style: kSettingsSubtitleStyle)
            : null,
        trailing: button,
      );
    });
  }

  Widget _titleWidget(BuildContext context) {
    if (widget.title is! String) return widget.title as Widget;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(widget.title as String, style: kSettingsTitleStyle),
        if (widget.subtitle != null) ...[
          const SizedBox(height: 4),
          Text(widget.subtitle!,
              style: kSettingsSubtitleStyle.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ],
      ],
    );
  }

  // M3 SegmentedButton: secondaryContainer = selected, surface = unselected
  // Tokens: https://m3.material.io/components/segmented-buttons/specs
  Widget _buildButton(ColorScheme cs, bool hasIcons, double totalW) {
    return Focus(
      focusNode: _focusNode,
      onKeyEvent: (_, ev) {
        if (ev is! KeyDownEvent) return KeyEventResult.ignored;
        if (ev.logicalKey == LogicalKeyboardKey.arrowRight) {
          setState(() =>
              _focusedIndex = (_focusedIndex + 1) % widget.options.length);
          return KeyEventResult.handled;
        }
        if (ev.logicalKey == LogicalKeyboardKey.arrowLeft) {
          setState(() => _focusedIndex =
              (_focusedIndex - 1 + widget.options.length) %
                  widget.options.length);
          return KeyEventResult.handled;
        }
        if (ev.logicalKey == LogicalKeyboardKey.enter ||
            ev.logicalKey == LogicalKeyboardKey.space) {
          widget.onChanged(widget.options[_focusedIndex].value);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: SizedBox(
        width: totalW,
        child: SegmentedButton<T>(
          showSelectedIcon: true,
          selectedIcon: const Icon(Icons.check, size: 16),
          style: ButtonStyle(
            minimumSize: WidgetStateProperty.all(const Size(0, 40)),
            maximumSize:
                WidgetStateProperty.all(const Size(double.infinity, 40)),
            shape: WidgetStateProperty.all(RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTokens.radiusSM))),
            // M3 selected: secondaryContainer/onSecondaryContainer
            backgroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
              if (states.contains(WidgetState.selected)) {
                return cs.secondaryContainer;
              }
              return cs.surface;
            }),
            foregroundColor: WidgetStateProperty.resolveWith<Color?>((states) {
              if (states.contains(WidgetState.selected)) {
                return cs.onSecondaryContainer;
              }
              return cs.onSurfaceVariant;
            }),
          ),
          segments: widget.options
              .map((o) => ButtonSegment<T>(
                    value: o.value,
                    label: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(o.label, style: kSettingsTitleStyle)),
                    icon: hasIcons
                        ? (o.icon != null
                            ? Icon(o.icon, size: 18)
                            : const SizedBox(width: 18))
                        : null,
                  ))
              .toList(),
          selected: {widget.currentValue},
          onSelectionChanged: (s) => widget.onChanged(s.first),
        ),
      ),
    );
  }
}

/// אפשרות יחידה ב-[SegmentedSettingsTile]
class SegmentOption<T> {
  final T value;
  final String label;
  final IconData? icon;

  const SegmentOption({required this.value, required this.label, this.icon});
}

// ════════════════════════════════════════════════════════════════════════════
// CustomSwitch — Material 3 Switch עם תיקון hover במצב כהה
// ════════════════════════════════════════════════════════════════════════════

/// [Switch] תואם M3 עם thumb/track/overlay מוגדרים לפי:
/// https://m3.material.io/components/switch/specs
///
/// תיקון ידוע ב-Flutter: ב-dark mode, hover על Switch שאינו selected
/// מציג thumb לבן על track בהיר — מתוקן כאן ע"י הגדרה מפורשת של overlay.
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
      // M3 thumb tokens: onPrimary (on), outline (off), onSurface·38 (disabled)
      thumbColor: WidgetStateProperty.resolveWith((s) {
        if (s.contains(WidgetState.disabled)) {
          return cs.onSurface.withValues(alpha: 0.38);
        }
        if (s.contains(WidgetState.selected)) return cs.onPrimary;
        if (s.contains(WidgetState.hovered)) return cs.onSurfaceVariant;
        return cs.outline;
      }),
      // M3 track tokens: primary (on), surfaceContainerHighest (off)
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
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// SwitchSettingsTile — ListTile + CustomSwitch
// ════════════════════════════════════════════════════════════════════════════

/// [ListTile] עם [CustomSwitch] — עקבי עם כל שורות on/off בהגדרות.
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
