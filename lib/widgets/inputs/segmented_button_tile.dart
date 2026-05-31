import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:otzaria/theme/theme_exports.dart';

const _kSegmentBaseWidthWithIcon = 80.0;
const _kSegmentBaseWidthNoIcon = 60.0;
const _kSegmentCharWidthMultiplier = 8.0;
const _kSegmentGroupPadding = 24.0;
const _kSegmentMinTotalWidth = 180.0;
const _kSegmentMaxTotalWidth = 400.0;
const _kSegmentNarrowLayoutThreshold = 200.0;

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

/// פקד סגמנטד גנרי לשימוש בסרגלי כלים
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

  const AppSegmentedControl({
    super.key,
    required this.options,
    required this.currentValue,
    required this.onChanged,
    this.expandToFillWidth = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return SegmentedButton<T>(
      segments: options
          .map(
            (opt) => ButtonSegment<T>(
              value: opt.value,
              label: Text(opt.label),
              icon: opt.icon != null ? Icon(opt.icon) : null,
            ),
          )
          .toList(),
      selected: {currentValue},
      expandedInsets: expandToFillWidth ? EdgeInsets.zero : null,
      onSelectionChanged: (Set<T> selection) {
        if (selection.isNotEmpty) onChanged(selection.first);
      },
      showSelectedIcon: false,
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        textStyle: WidgetStatePropertyAll(
          Theme.of(context).textTheme.bodySmall,
        ),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return cs.onPrimaryContainer;
          }
          return cs.onSurface;
        }),
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return cs.primaryContainer;
          }
          return cs.surface;
        }),
        side: WidgetStatePropertyAll(
          BorderSide(
            color: cs.outline.withValues(alpha: 0.4),
          ),
        ),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTokens.radiusMD),
          ),
        ),
      ),
    );
  }
}

/// Widget להגדרה עם [SegmentedButton] — בהתאם לספציפיקציית M3.
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
    if (_focusedIndex < 0) {
      _focusedIndex = 0;
    }
  }

  @override
  void didUpdateWidget(covariant SegmentedSettingsTile<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentValue != widget.currentValue ||
        oldWidget.options != widget.options) {
      final selectedIndex =
          widget.options.indexWhere((o) => o.value == widget.currentValue);
      _focusedIndex = selectedIndex < 0 ? 0 : selectedIndex;
    }
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
    final btnWidth =
        (hasIcons ? _kSegmentBaseWidthWithIcon : _kSegmentBaseWidthNoIcon) +
            maxLen * _kSegmentCharWidthMultiplier;
    final totalW = (btnWidth * widget.options.length + _kSegmentGroupPadding)
        .clamp(_kSegmentMinTotalWidth, _kSegmentMaxTotalWidth);

    return LayoutBuilder(
      builder: (ctx, constraints) {
        final isNarrow =
            constraints.maxWidth < totalW + _kSegmentNarrowLayoutThreshold;
        final button = _buildButton(cs, hasIcons, totalW);

        if (isNarrow) {
          return Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTokens.spaceMD,
              vertical: 12,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.icon != null) ...[
                      Icon(widget.icon, size: 24),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _titleOnlyWidget(),
                          if (widget.subtitle != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              widget.subtitle!,
                              style: AppTextStyles.settingSubtitle.copyWith(
                                color:
                                    Theme.of(ctx).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Align(alignment: Alignment.centerRight, child: button),
              ],
            ),
          );
        }

        return ListTile(
          leading: widget.icon != null ? Icon(widget.icon) : null,
          title: _titleOnlyWidget(),
          subtitle: widget.subtitle != null
              ? Text(
                  widget.subtitle!,
                  style: AppTextStyles.settingSubtitle,
                )
              : null,
          trailing: button,
        );
      },
    );
  }

  Widget _titleOnlyWidget() {
    if (widget.title is! String) {
      return widget.title as Widget;
    }
    return Text(
      widget.title as String,
      style: AppTextStyles.settingTitle,
    );
  }

  Widget _buildButton(ColorScheme cs, bool hasIcons, double totalW) {
    return Focus(
      focusNode: _focusNode,
      onKeyEvent: (_, ev) {
        if (ev is! KeyDownEvent) {
          return KeyEventResult.ignored;
        }
        if (ev.logicalKey == LogicalKeyboardKey.arrowRight) {
          setState(() {
            _focusedIndex = (_focusedIndex + 1) % widget.options.length;
          });
          return KeyEventResult.handled;
        }
        if (ev.logicalKey == LogicalKeyboardKey.arrowLeft) {
          setState(() {
            _focusedIndex = (_focusedIndex - 1 + widget.options.length) %
                widget.options.length;
          });
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
          // ללא אייקון "נבחר": כשלאפשרויות אין אייקון, הוא הופיע רק במקטע
          // הנבחר ודחק את התווית, וכך ה-FittedBox הקטין את הטקסט ושינה את
          // מבנה הכפתור בכל החלפת בחירה. הבחירה מסומנת ממילא ברקע ובצבע הטקסט.
          showSelectedIcon: false,
          style: ButtonStyle(
            minimumSize: WidgetStateProperty.all(const Size(0, 40)),
            maximumSize:
                WidgetStateProperty.all(const Size(double.infinity, 40)),
            shape: WidgetStateProperty.all(
              RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTokens.radiusSM),
              ),
            ),
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
              .toList(),
          selected: {widget.currentValue},
          onSelectionChanged: (selection) {
            widget.onChanged(selection.first);
          },
        ),
      ),
    );
  }
}
