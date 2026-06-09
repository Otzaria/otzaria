import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:otzaria/theme/theme_exports.dart';

/// אפשרות יחידה ב-[AppSegmentedControl]
class SegmentOption<T> {
  final T value;
  final String label;
  final IconData? icon;

  const SegmentOption({
    required this.value,
    required this.label,
    this.icon,
  });
}

/// פקד סגמנטד גנרי לשימוש בסרגלי כלים ובהגדרות.
///
/// [height] — גובה קבוע בפיקסלים (ברירת מחדל: null = compact density לסרגלי כלים).
/// [expandToFillWidth] — מלא את כל הרוחב הזמין.
///
/// דוגמה:
/// ```dart
/// AppSegmentedControl<String>(
///   options: const [
///     SegmentOption(value: 'all', label: 'הכל', icon: FluentIcons.library_24_regular),
///     SegmentOption(value: 'done', label: 'הושלם', icon: FluentIcons.checkmark_circle_24_regular),
///   ],
///   currentValue: _filter,
///   onChanged: (v) => setState(() => _filter = v),
/// )
/// ```
class AppSegmentedControl<T> extends StatelessWidget {
  final List<SegmentOption<T>> options;
  final T currentValue;
  final ValueChanged<T> onChanged;
  final bool expandToFillWidth;
  final double? height;

  const AppSegmentedControl({
    super.key,
    required this.options,
    required this.currentValue,
    required this.onChanged,
    this.expandToFillWidth = false,
    this.height,
  });

  List<ButtonSegment<T>> _segments() {
    final hasIcons = options.any((o) => o.icon != null);
    return options
        .map(
          (o) => ButtonSegment<T>(
            value: o.value,
            label: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(o.label, style: AppTextStyles.settingTitle),
            ),
            icon: hasIcons
                ? (o.icon != null
                    ? Icon(o.icon, size: 18)
                    : const SizedBox(width: 18))
                : null,
          ),
        )
        .toList();
  }

  static ButtonStyle _buttonStyle(ColorScheme cs) => ButtonStyle(
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return cs.onSecondaryContainer;
          }
          return cs.onSurfaceVariant;
        }),
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return cs.secondaryContainer;
          return cs.surface;
        }),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTokens.radiusSM),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isFixed = height != null;

    return SegmentedButton<T>(
      segments: _segments(),
      selected: {currentValue},
      expandedInsets: expandToFillWidth ? EdgeInsets.zero : null,
      onSelectionChanged: (Set<T> selection) {
        if (selection.isNotEmpty) onChanged(selection.first);
      },
      showSelectedIcon: true,
      selectedIcon: const Icon(FluentIcons.checkmark_24_regular, size: 16),
      style: isFixed
          ? _buttonStyle(cs).copyWith(
              minimumSize: WidgetStateProperty.all(Size(0, height!)),
              maximumSize:
                  WidgetStateProperty.all(Size(double.infinity, height!)),
            )
          : _buttonStyle(cs).copyWith(
              visualDensity: VisualDensity.compact,
            ),
    );
  }
}
