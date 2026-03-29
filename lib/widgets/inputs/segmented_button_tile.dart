// lib/widgets/inputs/segmented_button_tile.dart
//
// Widget להגדרה/קלט עם [SegmentedButton] — בהתאם לספציפיקציית M3:
// https://m3.material.io/components/segmented-buttons/overview
//
// ⚠️ קובץ זה הועבר מ-lib/settings/widgets/segmented_settings_tile.dart
//    ושמו שונה ל-SegmentedButtonTile כי הווידג'ט מתאים לכל מקום,
//    לא רק למסכי הגדרות.
//
// **שימוש:**
// ```dart
// SegmentedButtonTile<int>(
//   title: 'שיטת גימטריה',
//   options: [
//     SegmentOption(value: 0, label: 'רגיל'),
//     SegmentOption(value: 1, label: 'קטנה'),
//   ],
//   currentValue: 0,
//   onChanged: (v) => setState(() => _method = v),
// )
// ```
//
// **מאפיינים:**
// - פריסה אדפטיבית: narrow = כותרת מעל הכפתור; wide = ListTile
// - ניווט מקלדת: חצים ← → לבחירה, Enter/Space לאישור
// - ללא dependency על מסכי הגדרות — גנרי לחלוטין

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:otzaria/theme/theme_exports.dart';

// ── קבועי גודל ────────────────────────────────────────────────────────────────
const _kSegmentBaseWidthWithIcon = 80.0;
const _kSegmentBaseWidthNoIcon = 60.0;
const _kSegmentCharWidthMultiplier = 8.0;
const _kSegmentGroupPadding = 24.0;
const _kSegmentMinTotalWidth = 180.0;
const _kSegmentMaxTotalWidth = 400.0;
const _kSegmentNarrowLayoutThreshold = 200.0;

// ── SegmentOption ─────────────────────────────────────────────────────────────

/// אפשרות יחידה ב-[SegmentedButtonTile]
class SegmentOption<T> {
  final T value;
  final String label;
  final IconData? icon;

  const SegmentOption({required this.value, required this.label, this.icon});
}

// ── AppSegmentedControl ─────────────────────────────────────────────────────

/// בקר מקטעים גנרי — מחזיר רק [SegmentedButton] מעוצב.
class AppSegmentedControl<T> extends StatelessWidget {
  final List<SegmentOption<T>> options;
  final T currentValue;
  final ValueChanged<T> onChanged;

  const AppSegmentedControl({
    super.key,
    required this.options,
    required this.currentValue,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasIcons = options.any((o) => o.icon != null);
    return SegmentedButton<T>(
      showSelectedIcon: true,
      selectedIcon: const Icon(Icons.check, size: 16),
      style: ButtonStyle(
        minimumSize: WidgetStateProperty.all(const Size(0, 40)),
        maximumSize: WidgetStateProperty.all(const Size(double.infinity, 40)),
        shape: WidgetStateProperty.all(RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTokens.radiusSM))),
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
      segments: options
          .map((o) => ButtonSegment<T>(
                value: o.value,
                label: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(o.label, style: AppTextStyles.settingTitle)),
                icon: hasIcons
                    ? (o.icon != null
                        ? Icon(o.icon, size: 18)
                        : const SizedBox(width: 18))
                    : null,
              ))
          .toList(),
      selected: {currentValue},
      onSelectionChanged: (s) => onChanged(s.first),
    );
  }
}

// ── SegmentedButtonTile ───────────────────────────────────────────────────────

/// ListTile עם SegmentedButton — פריסה אדפטיבית narrow/wide.
///
/// מתאים לכל מסך שצריך בחירה מתוך מספר אפשרויות מוגדרות.
/// לא תלוי במסכי הגדרות — ניתן לשימוש בכל feature.
class SegmentedButtonTile<T> extends StatefulWidget {
  final dynamic title;
  final String? subtitle;
  final IconData? icon;
  final List<SegmentOption<T>> options;
  final T currentValue;
  final ValueChanged<T> onChanged;

  const SegmentedButtonTile({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    required this.options,
    required this.currentValue,
    required this.onChanged,
  });

  @override
  State<SegmentedButtonTile<T>> createState() => _SegmentedButtonTileState<T>();
}

class _SegmentedButtonTileState<T> extends State<SegmentedButtonTile<T>> {
  final FocusNode _focusNode = FocusNode();
  int _focusedIndex = 0;
  bool _hasFocus = false;

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
  void didUpdateWidget(covariant SegmentedButtonTile<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    // כשהערך משתנה מבחוץ ואין פוקוס — סנכרן את הסמן
    if (!_hasFocus && oldWidget.currentValue != widget.currentValue) {
      final idx =
          widget.options.indexWhere((o) => o.value == widget.currentValue);
      if (idx >= 0) _focusedIndex = idx;
    }
  }

  void _moveFocus(int delta) {
    if (widget.options.isEmpty) return;
    setState(() {
      _focusedIndex =
          (_focusedIndex + delta + widget.options.length) % widget.options.length;
    });
  }

  void _selectFocused() {
    if (widget.options.isEmpty) return;
    widget.onChanged(widget.options[_focusedIndex].value);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _focusNode.canRequestFocus) _focusNode.requestFocus();
    });
  }

  // בחירה דרך עכבר — מעדכן גם את הסמן
  void _selectByValue(T value) {
    final idx = widget.options.indexWhere((o) => o.value == value);
    if (idx >= 0) setState(() => _focusedIndex = idx);
    widget.onChanged(value);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _focusNode.canRequestFocus) _focusNode.requestFocus();
    });
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

    // הכפתור עצמו עטוף ב-Focus — לא ה-ListTile כולו
    final focusedButton = Focus(
      focusNode: _focusNode,
      onFocusChange: (hasFocus) {
        if (_hasFocus == hasFocus) return;
        setState(() {
          _hasFocus = hasFocus;
          if (!hasFocus) {
            final idx = widget.options
                .indexWhere((o) => o.value == widget.currentValue);
            if (idx >= 0) _focusedIndex = idx;
          }
        });
      },
      onKeyEvent: (_, ev) {
        if (ev is! KeyDownEvent) return KeyEventResult.ignored;
        if (ev.logicalKey == LogicalKeyboardKey.arrowRight ||
            ev.logicalKey == LogicalKeyboardKey.arrowDown) {
          _moveFocus(1);
          return KeyEventResult.handled;
        }
        if (ev.logicalKey == LogicalKeyboardKey.arrowLeft ||
            ev.logicalKey == LogicalKeyboardKey.arrowUp) {
          _moveFocus(-1);
          return KeyEventResult.handled;
        }
        if (ev.logicalKey == LogicalKeyboardKey.enter ||
            ev.logicalKey == LogicalKeyboardKey.space) {
          _selectFocused();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: _buildButton(cs, hasIcons, totalW),
    );

    return LayoutBuilder(builder: (ctx, constraints) {
      final isNarrow =
          constraints.maxWidth < totalW + _kSegmentNarrowLayoutThreshold;

      if (isNarrow) {
        return Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppTokens.spaceMD, vertical: 12),
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
                        _titleWidget(ctx),
                        if (widget.subtitle != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            widget.subtitle!,
                            style: AppTextStyles.settingSubtitle.copyWith(
                                color:
                                    Theme.of(ctx).colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Align(alignment: Alignment.centerRight, child: focusedButton),
            ],
          ),
        );
      }

      // wide: ListTile ללא focusNode/onTap — אין hover על השורה כולה
      return ListTile(
        leading: widget.icon != null ? Icon(widget.icon) : null,
        title: _titleWidget(ctx),
        subtitle: widget.subtitle != null
            ? Text(widget.subtitle!, style: AppTextStyles.settingSubtitle)
            : null,
        trailing: focusedButton,
      );
    });
  }

  Widget _titleWidget(BuildContext context) {
    if (widget.title is! String) return widget.title as Widget;
    return Text(widget.title as String, style: AppTextStyles.settingTitle);
  }

  Widget _buildButton(ColorScheme cs, bool hasIcons, double totalW) {
    // מציג את _focusedIndex כשיש פוקוס — משוב ויזואלי לניווט חצים
    final displayValue = _hasFocus && widget.options.isNotEmpty
        ? widget.options[_focusedIndex].value
        : widget.currentValue;

    return ExcludeFocus(
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
                        child:
                            Text(o.label, style: AppTextStyles.settingTitle)),
                    icon: hasIcons
                        ? (o.icon != null
                            ? Icon(o.icon, size: 18)
                            : const SizedBox(width: 18))
                        : null,
                  ))
              .toList(),
          selected: {displayValue},
          onSelectionChanged: (s) => _selectByValue(s.first),
        ),
      ),
    );
  }
}

// ── alias לתאימות לאחור ───────────────────────────────────────────────────────
// אם יש קוד שמשתמש עדיין ב-SegmentedSettingsTile, הוא ימשיך לעבוד.
typedef SegmentedSettingsTile<T> = SegmentedButtonTile<T>;
