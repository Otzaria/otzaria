import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:otzaria/widgets/mixins/dialog_navigation_mixin.dart';
import 'package:otzaria/theme/app_theme.dart';

// ── קבועי סגנון גלובליים ─────────────────────────────────────────────────────
/// סגנון כותרת בשורת הגדרה — alias ל-[AppTextStyles.settingTitle]
/// @deprecated השתמש ב-AppTextStyles.settingTitle ישירות
const kSettingsTitleStyle = AppTextStyles.settingTitle;

/// סגנון תת-כותרת בשורת הגדרה — alias ל-[AppTextStyles.settingSubtitle]
/// @deprecated השתמש ב-AppTextStyles.settingSubtitle ישירות
const kSettingsSubtitleStyle = AppTextStyles.settingSubtitle;

/// רווח אנכי סטנדרטי בין כרטיסי הגדרות
const kSettingsCardSpacing = SizedBox(height: 16);

// ── דיאלוגים ─────────────────────────────────────────────────────────────────

/// דיאלוג עם פעולה אחת (כפתור אישור בלבד)
class SingleActionDialog extends StatefulWidget {
  final dynamic title;
  final String content;
  final String confirmText;

  const SingleActionDialog({
    super.key,
    required this.title,
    required this.content,
    this.confirmText = 'אישור',
  });

  @override
  State<SingleActionDialog> createState() => _SingleActionDialogState();
}

class _SingleActionDialogState extends State<SingleActionDialog>
    with DialogNavigationMixin {
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return buildKeyboardNavigator(
      onConfirm: () => Navigator.of(context).pop(true),
      onCancel: () => Navigator.of(context).pop(false),
      child: AlertDialog(
        title: widget.title is String ? Text(widget.title) : widget.title,
        content: Text(widget.content),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: colorScheme.primary,
              foregroundColor: colorScheme.onPrimary,
            ),
            child: Text(widget.confirmText),
          ),
        ],
      ),
    );
  }
}

/// דיאלוג עם שתי פעולות (ביטול ואישור)
class TwoActionsDialog extends StatefulWidget {
  final dynamic title;
  final String content;
  final String cancelText;
  final String confirmText;

  const TwoActionsDialog({
    super.key,
    required this.title,
    required this.content,
    this.cancelText = 'ביטול',
    this.confirmText = 'אישור',
  });

  @override
  State<TwoActionsDialog> createState() => _TwoActionsDialogState();
}

class _TwoActionsDialogState extends State<TwoActionsDialog>
    with DialogNavigationMixin {
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return buildKeyboardNavigator(
      onConfirm: () => Navigator.of(context).pop(true),
      onCancel: () => Navigator.of(context).pop(false),
      child: AlertDialog(
        title: widget.title is String ? Text(widget.title) : widget.title,
        content: Text(widget.content),
        actions: [
          // כפתור ביטול — tonal
          FilledButton.tonal(
            onPressed: () => Navigator.of(context).pop(false),
            style: FilledButton.styleFrom(
              backgroundColor: colorScheme.secondaryContainer,
              foregroundColor: colorScheme.onSecondaryContainer,
            ),
            child: Text(widget.cancelText),
          ),
          // כפתור אישור — primary
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: colorScheme.primary,
              foregroundColor: colorScheme.onPrimary,
            ),
            child: Text(widget.confirmText),
          ),
        ],
      ),
    );
  }
}

/// דיאלוג אזהרה — כפתור ביטול כהה (הפעולה הבטוחה), אישור אדום
class WarningDialog extends StatefulWidget {
  final dynamic title;
  final String content;
  final String? subtitle;
  final String cancelText;
  final String confirmText;

  const WarningDialog({
    super.key,
    required this.title,
    required this.content,
    this.subtitle,
    this.cancelText = 'ביטול',
    this.confirmText = 'המשך',
  });

  @override
  State<WarningDialog> createState() => _WarningDialogState();
}

class _WarningDialogState extends State<WarningDialog>
    with DialogNavigationMixin {
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return buildKeyboardNavigator(
      onConfirm: () => Navigator.of(context).pop(true),
      onCancel: () => Navigator.of(context).pop(false),
      child: AlertDialog(
        title: widget.title is String ? Text(widget.title) : widget.title,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.content),
            if (widget.subtitle != null) ...[
              const SizedBox(height: 8),
              Text(widget.subtitle!,
                  style: TextStyle(color: colorScheme.error, fontSize: 13)),
            ],
          ],
        ),
        actions: [
          // ביטול — כהה (primary), "הפעולה הבטוחה"
          FilledButton(
            onPressed: () => Navigator.of(context).pop(false),
            style: FilledButton.styleFrom(
              backgroundColor: colorScheme.primary,
              foregroundColor: colorScheme.onPrimary,
            ),
            child: Text(widget.cancelText),
          ),
          // אישור — שקוף אדום (מסוכן)
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: colorScheme.error),
            child: Text(widget.confirmText),
          ),
        ],
      ),
    );
  }
}

// ── כפתורים ───────────────────────────────────────────────────────────────────

/// כפתור פעולה מומלצת (Primary)
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
    final bg = cs.primary;
    final fg = cs.onPrimary;

    if (isLoading) {
      return FilledButton(
        onPressed: null,
        style: FilledButton.styleFrom(backgroundColor: bg, foregroundColor: fg),
        child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: fg)),
      );
    }
    if (icon != null) {
      return FilledButton.icon(
        onPressed: onPressed,
        style: FilledButton.styleFrom(backgroundColor: bg, foregroundColor: fg),
        icon: Icon(icon),
        label: Text(text),
      );
    }
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(backgroundColor: bg, foregroundColor: fg),
      child: Text(text),
    );
  }
}

/// כפתור פעולה ניטרלית (Tonal)
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
    final bg = cs.secondaryContainer;
    final fg = cs.onSecondaryContainer;

    if (isLoading) {
      return FilledButton.tonal(
        onPressed: null,
        style: FilledButton.styleFrom(backgroundColor: bg, foregroundColor: fg),
        child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: fg)),
      );
    }
    if (icon != null) {
      return FilledButton.tonalIcon(
        onPressed: onPressed,
        style: FilledButton.styleFrom(backgroundColor: bg, foregroundColor: fg),
        icon: Icon(icon),
        label: Text(text),
      );
    }
    return FilledButton.tonal(
      onPressed: onPressed,
      style: FilledButton.styleFrom(backgroundColor: bg, foregroundColor: fg),
      child: Text(text),
    );
  }
}

// ── פונקציות עזר לדיאלוגים ────────────────────────────────────────────────────

Future<bool?> showSingleActionDialog({
  required BuildContext context,
  required String title,
  required String content,
  String confirmText = 'אישור',
}) =>
    showDialog<bool>(
      context: context,
      builder: (_) => SingleActionDialog(
          title: title, content: content, confirmText: confirmText),
    );

Future<bool?> showTwoActionsDialog({
  required BuildContext context,
  required String title,
  required String content,
  String cancelText = 'ביטול',
  String confirmText = 'אישור',
}) =>
    showDialog<bool>(
      context: context,
      builder: (_) => TwoActionsDialog(
          title: title,
          content: content,
          cancelText: cancelText,
          confirmText: confirmText),
    );

Future<bool?> showWarningDialog({
  required BuildContext context,
  required String title,
  required String content,
  String? subtitle,
  String cancelText = 'ביטול',
  String confirmText = 'המשך',
}) =>
    showDialog<bool>(
      context: context,
      builder: (_) => WarningDialog(
          title: title,
          content: content,
          subtitle: subtitle,
          cancelText: cancelText,
          confirmText: confirmText),
    );

// ── SegmentedSettingsTile ─────────────────────────────────────────────────────

/// Widget להגדרה עם SegmentedButton.
/// - מציג ✓ על האפשרות הנבחרת
/// - הגבולות החיצוניים של הווידג'ט קבועים (SizedBox עם רוחב מחושב מראש)
/// - הגבולות הפנימיים בין הקטעים יכולים לנוע בעת בחירה
/// - תומך בפריסה אדפטיבית (צר/רחב) וניווט מקלדת
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
    if (_focusedIndex == -1) _focusedIndex = 0;
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // חישוב רוחב פעם אחת — מועבר ל-_buildSegmentedButton
    final hasIcons = widget.options.any((o) => o.icon != null);
    final maxLabelLen = widget.options
        .map((o) => o.label.length)
        .reduce((a, b) => a > b ? a : b);

    return LayoutBuilder(
      builder: (context, constraints) {
        // הערכת רוחב הכפתור הבסיסי + 24px לסמן ✓ על הפריט הנבחר
        final buttonWidth = (hasIcons ? 80.0 : 60.0) + (maxLabelLen * 8.0);
        // +24 לסמן ✓ (נמצא רק על קטע אחד בו-זמנית, מסגרת חיצונית גדולה מספיק)
        final totalWidth =
            (buttonWidth * widget.options.length + 24.0).clamp(180.0, 400.0);
        final hasHorizontalSpace = constraints.maxWidth > (totalWidth + 200);

        if (!hasHorizontalSpace) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    if (widget.icon != null) ...[
                      Icon(widget.icon, size: 24),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          widget.title is String
                              ? Text(widget.title as String,
                                  style: kSettingsTitleStyle)
                              : widget.title as Widget,
                          if (widget.subtitle != null) ...[
                            const SizedBox(height: 4),
                            Text(widget.subtitle!,
                                style: TextStyle(
                                    fontSize: 13,
                                    color: colorScheme.onSurfaceVariant)),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: _buildSegmentedButton(
                      colorScheme, isDark, hasIcons, maxLabelLen, totalWidth),
                ),
              ],
            ),
          );
        }

        return ListTile(
          leading: widget.icon != null ? Icon(widget.icon) : null,
          title: widget.title is String
              ? Text(widget.title as String, style: kSettingsTitleStyle)
              : widget.title as Widget,
          subtitle: widget.subtitle != null
              ? Text(widget.subtitle!, style: kSettingsSubtitleStyle)
              : null,
          trailing: _buildSegmentedButton(
              colorScheme, isDark, hasIcons, maxLabelLen, totalWidth),
        );
      },
    );
  }

  /// בונה את SegmentedButton עם:
  /// - ✓ על האפשרות הנבחרת (showSelectedIcon: true)
  /// - SizedBox קבוע — מגבולות חיצוניים לא זזים בעת בחירה
  /// - הגבולות הפנימיים בין הקטעים עשויים לנוע מעט
  Widget _buildSegmentedButton(
    ColorScheme colorScheme,
    bool isDark,
    bool hasIcons,
    int maxLabelLen,
    double totalWidth,
  ) {
    return Focus(
      focusNode: _focusNode,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
          setState(() {
            _focusedIndex = (_focusedIndex + 1) % widget.options.length;
          });
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
          setState(() {
            _focusedIndex = (_focusedIndex - 1 + widget.options.length) %
                widget.options.length;
          });
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.space) {
          widget.onChanged(widget.options[_focusedIndex].value);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      // SizedBox קבוע — מגבולות חיצוניים לא זזים בעת בחירה
      child: SizedBox(
        width: totalWidth,
        child: SegmentedButton<T>(
          // showSelectedIcon: true — מציג ✓ על האפשרות הנבחרת
          // הגבולות החיצוניים קבועים; הפנימיים עשויים לנוע מעט
          showSelectedIcon: true,
          selectedIcon: const Icon(Icons.check, size: 16),
          style: ButtonStyle(
            minimumSize: WidgetStateProperty.all(const Size(0, 40)),
            maximumSize:
                WidgetStateProperty.all(const Size(double.infinity, 40)),
            shape: WidgetStateProperty.all(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            backgroundColor: WidgetStateProperty.resolveWith<Color?>(
              (states) {
                if (states.contains(WidgetState.selected)) {
                  return isDark
                      ? colorScheme.primaryContainer
                      : colorScheme.primary.withValues(alpha: 0.2);
                }
                return colorScheme.surface;
              },
            ),
            foregroundColor: WidgetStateProperty.resolveWith<Color?>(
              (states) {
                if (states.contains(WidgetState.selected)) {
                  return isDark
                      ? colorScheme.onPrimaryContainer
                      : colorScheme.primary;
                }
                return colorScheme.onSurface;
              },
            ),
            side: WidgetStateProperty.resolveWith<BorderSide?>(
              (states) {
                if (states.contains(WidgetState.selected) && isDark) {
                  return BorderSide(color: colorScheme.primary, width: 2);
                }
                return null;
              },
            ),
          ),
          segments: widget.options
              .map((o) => ButtonSegment<T>(
                    value: o.value,
                    label: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(o.label, style: kSettingsTitleStyle),
                    ),
                    icon: hasIcons
                        ? (o.icon != null
                            ? Icon(o.icon, size: 18)
                            : const SizedBox(width: 18, height: 18))
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

class SegmentOption<T> {
  final T value;
  final String label;
  final IconData? icon;

  const SegmentOption({required this.value, required this.label, this.icon});
}

// ── CustomSwitch ───────────────────────────────────────────────────────────────

/// Material 3 Switch מותאם אישית
/// תיקון מצב כהה: צבעי track ו-thumb מוגדרים בצורה ברורה גם בריחוף
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
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Switch(
      value: value,
      onChanged: onChanged,
      autofocus: autofocus,
      focusNode: focusNode,
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return colorScheme.onSurface.withValues(alpha: 0.38);
        }
        if (states.contains(WidgetState.selected)) {
          return colorScheme.onPrimary;
        }
        if (states.contains(WidgetState.hovered)) {
          return colorScheme.onSurfaceVariant;
        }
        return colorScheme.outline;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return colorScheme.surfaceContainerHighest.withValues(alpha: 0.12);
        }
        if (states.contains(WidgetState.selected)) {
          return colorScheme.primary;
        }
        return colorScheme.surfaceContainerHighest;
      }),
      trackOutlineColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return Colors.transparent;
        }
        return colorScheme.outline;
      }),
      overlayColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          if (states.contains(WidgetState.hovered)) {
            return isDark
                ? Colors.white.withValues(alpha: 0.1)
                : colorScheme.primary.withValues(alpha: 0.1);
          }
          if (states.contains(WidgetState.focused) ||
              states.contains(WidgetState.pressed)) {
            return isDark
                ? Colors.white.withValues(alpha: 0.15)
                : colorScheme.primary.withValues(alpha: 0.12);
          }
        }
        if (states.contains(WidgetState.hovered) ||
            states.contains(WidgetState.focused) ||
            states.contains(WidgetState.pressed)) {
          return colorScheme.onSurface.withValues(alpha: 0.12);
        }
        return Colors.transparent;
      }),
    );
  }
}

// ── SwitchSettingsTile ────────────────────────────────────────────────────────

/// SwitchSettingsTile — ListTile + CustomSwitch
/// עיצוב M3 עקבי, תיקון ריחוף במצב כהה
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
