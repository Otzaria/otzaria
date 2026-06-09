import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/inputs/segmented_button_tile.dart';
import 'settings_tile_helpers.dart';

const _kSegmentBaseWidthWithIcon = 80.0;
const _kSegmentBaseWidthNoIcon = 60.0;
const _kSegmentCharWidthMultiplier = 8.0;
const _kSegmentGroupPadding = 24.0;
const _kSegmentMinTotalWidth = 180.0;
const _kSegmentMaxTotalWidth = 400.0;
const _kSegmentNarrowLayoutThreshold = 200.0;

double _groupWidth(List<SegmentOption<dynamic>> options) {
  final hasIcons = options.any((o) => o.icon != null);
  final maxLen =
      options.map((o) => o.label.length).reduce((a, b) => a > b ? a : b);
  final btnWidth =
      (hasIcons ? _kSegmentBaseWidthWithIcon : _kSegmentBaseWidthNoIcon) +
          maxLen * _kSegmentCharWidthMultiplier;
  return (btnWidth * options.length + _kSegmentGroupPadding)
      .clamp(_kSegmentMinTotalWidth, _kSegmentMaxTotalWidth);
}

/// Widget להגדרה עם [SegmentedButton] — בהתאם לספציפיקציית M3.
///
/// [title] יכול להיות [String] או [Widget].
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
  void didUpdateWidget(covariant SegmentedSettingsTile<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentValue != widget.currentValue ||
        oldWidget.options != widget.options) {
      final idx =
          widget.options.indexWhere((o) => o.value == widget.currentValue);
      _focusedIndex = idx < 0 ? 0 : idx;
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final totalW = _groupWidth(widget.options);

    return LayoutBuilder(
      builder: (ctx, constraints) {
        final isNarrow =
            constraints.maxWidth < totalW + _kSegmentNarrowLayoutThreshold;
        final button = _buildButton(totalW);

        if (isNarrow) {
          return Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTokens.spaceMD,
              vertical: 12,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SettingsTileInfo(
                  icon: widget.icon,
                  title: widget.title,
                  subtitle: widget.subtitle,
                ),
                const SizedBox(height: 12),
                Align(alignment: Alignment.centerRight, child: button),
              ],
            ),
          );
        }

        return ListTile(
          leading: widget.icon != null ? Icon(widget.icon) : null,
          title: widget.title is String
              ? Text(widget.title as String, style: AppTextStyles.settingTitle)
              : widget.title as Widget,
          subtitle: widget.subtitle != null
              ? Text(widget.subtitle!, style: AppTextStyles.settingSubtitle)
              : null,
          trailing: button,
        );
      },
    );
  }

  Widget _buildButton(double totalW) {
    return Focus(
      focusNode: _focusNode,
      onKeyEvent: (_, ev) {
        if (ev is! KeyDownEvent) return KeyEventResult.ignored;
        if (ev.logicalKey == LogicalKeyboardKey.arrowRight) {
          setState(
              () => _focusedIndex = (_focusedIndex + 1) % widget.options.length);
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
        child: AppSegmentedControl<T>(
          options: widget.options,
          currentValue: widget.currentValue,
          onChanged: widget.onChanged,
          height: 40,
        ),
      ),
    );
  }
}
