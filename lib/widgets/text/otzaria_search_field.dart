// lib/widgets/otzaria_search_field.dart
//
// OtzariaSearchField  v5.0
//
// שינויים מ-v4:
// • הוסר shrinkOnScroll / isShrunkenNotifier — הגובה נקבע אך ורק לפי [slim].
//   פונקציית ה"כיווץ בגלילה" נגרמה לבלבול בין גובה הסרגל לגובה השדה,
//   ופעלה בצורה שונה על מסכים שונים.
// • [slim] = null (ברירת מחדל): יורש מ-[compactMenuMode] אם זמין ב-SettingsBloc
// • [slim] = false (touch / מרווח): גובה 48px, גופן 16px
// • [slim] = true  (desktop / compact): גובה 36px, גופן 13px
// • אין גלילה ב-RtlTextField: scrollPhysics = NeverScrollableScrollPhysics
// • שאר ה-API ללא שינוי; שדות shrinkOnScroll / isShrunkenNotifier הוסרו.

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/settings/engine/settings_bloc.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/text/rtl_text_field.dart';

abstract class _ST {
  // Touch (standard)
  static const double radius = AppInputTokens.regularRadius;
  static const double height = AppInputTokens.regularHeight;
  static const double heightCompact = 40.0;
  static const double fontSize = AppInputTokens.regularFontSize;

  // Desktop (slim)
  static const double heightSlim = AppInputTokens.compactHeight;
  static const double fontSizeSlim = AppInputTokens.compactFontSize;
  static const double radiusSlim = AppInputTokens.compactRadius;

  static const double fillAlphaUnfocused = AppInputTokens.unfocusedAlpha;
  static const double fillAlphaFocused = AppInputTokens.focusedAlpha;
  static const Duration collapseAnim = Duration(milliseconds: 220);
}

// ─────────────────────────────────────────────────────────────────────────────
//  OtzariaSearchAction
// ─────────────────────────────────────────────────────────────────────────────

class OtzariaSearchAction {
  OtzariaSearchAction._();

  /// מונה תוצאות: "3/12"
  static Widget resultCounter({
    required int current,
    required int total,
    BuildContext? context,
  }) {
    if (total <= 1) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Text(
        '$current/$total',
        style: TextStyle(
          fontSize: AppTokens.fontMD,
          fontWeight: FontWeight.w500,
          color: context != null
              ? Theme.of(context).colorScheme.onSurfaceVariant
              : null,
        ),
      ),
    );
  }

  /// תוצאה קודמת ↑
  static Widget prevResult({required VoidCallback? onPressed}) =>
      _NavButton(icon: FluentIcons.chevron_up_24_regular, onPressed: onPressed);

  /// תוצאה הבאה ↓
  static Widget nextResult({required VoidCallback? onPressed}) => _NavButton(
      icon: FluentIcons.chevron_down_24_regular, onPressed: onPressed);

  /// כפתור הגדרות
  static Widget settings({
    required VoidCallback onPressed,
    String tooltip = 'הגדרות חיפוש',
  }) =>
      _ActionButton(
          icon: FluentIcons.settings_24_regular,
          onPressed: onPressed,
          tooltip: tooltip);

  /// כפתור עם אייקון מותאם
  static Widget icon({
    required IconData iconData,
    required VoidCallback onPressed,
    String? tooltip,
    Color? color,
  }) =>
      _ActionButton(
          icon: iconData, onPressed: onPressed, tooltip: tooltip, color: color);
}

// ─────────────────────────────────────────────────────────────────────────────
//  כפתורים פנימיים
// ─────────────────────────────────────────────────────────────────────────────

class _NavButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  const _NavButton({required this.icon, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: 28,
      height: 28,
      child: IconButton(
        icon: Icon(icon, size: 18),
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        color: onPressed != null
            ? cs.onSurfaceVariant
            : cs.onSurface.withValues(alpha: 0.25),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final String? tooltip;
  final Color? color;
  const _ActionButton(
      {required this.icon, required this.onPressed, this.tooltip, this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 32,
      height: 32,
      child: IconButton(
        icon: Icon(icon, size: 20),
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        color: color ?? Theme.of(context).colorScheme.onSurfaceVariant,
        tooltip: tooltip,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  OtzariaSearchField
// ─────────────────────────────────────────────────────────────────────────────

/// שדה חיפוש של אוצריא.
///
/// מצבים:
/// • [slim] = null: יורש אוטומטית מ-[compactMenuMode] אם זמין
/// • [slim] = false (touch / מרווח): גובה 48px, גופן 16px
/// • [slim] = true  (desktop / compact): גובה 36px, גופן 13px
/// • [isCompact] = true: מתכווץ לאייקון עגול (scroll-hide)
class OtzariaSearchField extends StatefulWidget {
  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onClear;
  final FocusNode? focusNode;
  final bool autofocus;
  final double? maxWidth;
  final Widget? leading;
  final List<Widget>? trailingActions;

  /// `null` = יורש אוטומטית מ-compactMenuMode אם זמין.
  /// `true` = שדה צר, `false` = שדה רחב.
  final bool? slim;

  /// כשאמת — מתכווץ לאייקון עגול (M3 scroll-hide)
  final bool isCompact;
  final VoidCallback? onExpand;
  final bool selectAllOnFocus;

  const OtzariaSearchField({
    super.key,
    required this.controller,
    required this.hintText,
    this.onChanged,
    this.onSubmitted,
    this.onClear,
    this.focusNode,
    this.autofocus = false,
    this.maxWidth,
    this.leading,
    this.trailingActions,
    this.slim,
    this.isCompact = false,
    this.onExpand,
    this.selectAllOnFocus = true,
  });

  @override
  State<OtzariaSearchField> createState() => _OtzariaSearchFieldState();
}

class _OtzariaSearchFieldState extends State<OtzariaSearchField> {
  late FocusNode _effectiveFocusNode;
  bool _hasFocus = false;

  bool _resolveSlim(BuildContext context) {
    if (widget.slim != null) return widget.slim!;
    return context.read<SettingsBloc?>()?.state.compactMenuMode ?? false;
  }

  @override
  void initState() {
    super.initState();
    _effectiveFocusNode = widget.focusNode ?? FocusNode();
    _hasFocus = _effectiveFocusNode.hasFocus;
    _effectiveFocusNode.addListener(_onFocusChange);
    widget.controller.addListener(_onTextChange);
  }

  @override
  void didUpdateWidget(OtzariaSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      _effectiveFocusNode.removeListener(_onFocusChange);
      if (oldWidget.focusNode == null) _effectiveFocusNode.dispose();
      _effectiveFocusNode = widget.focusNode ?? FocusNode();
      _effectiveFocusNode.addListener(_onFocusChange);
    }
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onTextChange);
      widget.controller.addListener(_onTextChange);
    }
  }

  @override
  void dispose() {
    _effectiveFocusNode.removeListener(_onFocusChange);
    if (widget.focusNode == null) _effectiveFocusNode.dispose();
    widget.controller.removeListener(_onTextChange);
    super.dispose();
  }

  void _onFocusChange() {
    final hasFocus = _effectiveFocusNode.hasFocus;
    if (hasFocus &&
        !_hasFocus &&
        widget.selectAllOnFocus &&
        widget.controller.text.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_effectiveFocusNode.hasFocus) return;
        widget.controller.selection = TextSelection(
          baseOffset: 0,
          extentOffset: widget.controller.text.length,
        );
      });
    }
    if (mounted) setState(() => _hasFocus = hasFocus);
  }

  void _onTextChange() {
    if (mounted) setState(() {});
  }

  // ── מצב compact (אייקון עגול) ────────────────────────────────────────────

  Widget _buildCompact(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: _ST.collapseAnim,
      curve: Curves.easeInOut,
      width: _ST.heightCompact,
      height: _ST.heightCompact,
      decoration: BoxDecoration(
        color: cs.onSurface.withValues(alpha: _ST.fillAlphaUnfocused),
        shape: BoxShape.circle,
      ),
      child: IconButton(
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        icon: Icon(
          FluentIcons.search_24_regular,
          size: 20,
          color: cs.onSurfaceVariant,
        ),
        onPressed: widget.onExpand,
        tooltip: widget.hintText,
      ),
    );
  }

  // ── שדה מלא ──────────────────────────────────────────────────────────────

  Widget _buildField(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasText = widget.controller.text.isNotEmpty;
    final isSlim = _resolveSlim(context);

    // גובה וגופן — slim (desktop) לעומת touch
    final double effectiveHeight = isSlim ? _ST.heightSlim : _ST.height;
    final double effectiveFontSize = isSlim ? _ST.fontSizeSlim : _ST.fontSize;
    final double effectiveRadius = isSlim ? _ST.radiusSlim : _ST.radius;
    final double prefixIconSize = isSlim ? 18.0 : 20.0;

    // Fill
    final fillColor = _hasFocus
        ? cs.primary.withValues(alpha: _ST.fillAlphaFocused)
        : cs.onSurface.withValues(alpha: _ST.fillAlphaUnfocused);

    // Borders
    final noBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(effectiveRadius),
      borderSide: BorderSide.none,
    );

    // Suffix
    final List<Widget> suffixChildren = [];
    if (widget.trailingActions != null) {
      suffixChildren.addAll(widget.trailingActions!);
    }
    if (hasText && widget.onClear != null) {
      final clearSize = isSlim ? 26.0 : 32.0;
      suffixChildren.add(SizedBox(
        width: clearSize,
        height: clearSize,
        child: IconButton(
          icon: Icon(FluentIcons.dismiss_24_regular,
              size: isSlim ? 15 : 18, color: cs.onSurfaceVariant),
          onPressed: () {
            widget.controller.clear();
            widget.onClear!();
          },
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
        ),
      ));
    }
    final suffixWidget = suffixChildren.isNotEmpty
        ? Row(mainAxisSize: MainAxisSize.min, children: suffixChildren)
        : SizedBox(width: isSlim ? 32.0 : 40.0);

    // Prefix icon color
    // slim (בסרגל secondaryContainer) → onSecondaryContainer
    // לא-slim (רקע surface) → primary (M3 standard)
    final Color focusedIconColor =
        isSlim ? cs.onSecondaryContainer : cs.primary;

    final prefixIcon = widget.leading ??
        Icon(
          FluentIcons.search_24_regular,
          size: prefixIconSize,
          color: _hasFocus ? focusedIconColor : cs.onSurfaceVariant,
        );

    final contentPadding = EdgeInsets.symmetric(
      horizontal: AppTokens.spaceXS,
      vertical: 0,
    );

    return SizedBox(
      height: effectiveHeight,
      child: RtlTextField(
        controller: widget.controller,
        focusNode: _effectiveFocusNode,
        autofocus: widget.autofocus,
        onChanged: widget.onChanged,
        onSubmitted: widget.onSubmitted,
        textInputAction: TextInputAction.search,
        cursorColor: cs.onSurface.withValues(alpha: 0.87),
        style: TextStyle(
          fontSize: effectiveFontSize,
          color: cs.onSurface,
          height: 1.0,
          leadingDistribution: TextLeadingDistribution.even,
        ),
        decoration: InputDecoration(
          filled: true,
          fillColor: fillColor,
          contentPadding: contentPadding,
          isCollapsed: false,
          isDense: true,
          prefixIcon: prefixIcon,
          prefixIconConstraints: BoxConstraints(
            minWidth: isSlim ? 36 : 44,
            minHeight: effectiveHeight,
          ),
          suffixIcon: suffixWidget,
          suffixIconConstraints: BoxConstraints(
            minWidth: suffixChildren.isNotEmpty
                ? (suffixChildren.length * (isSlim ? 28.0 : 34.0))
                    .clamp(isSlim ? 28.0 : 34.0, 180.0)
                : (isSlim ? 32.0 : 40.0),
            minHeight: effectiveHeight,
          ),
          hintText: widget.hintText,
          hintStyle: TextStyle(
            fontSize: effectiveFontSize,
            color: cs.onSurfaceVariant,
            height: 1.0,
          ),
          border: noBorder,
          enabledBorder: noBorder,
          focusedBorder: noBorder,
          errorBorder: noBorder,
          focusedErrorBorder: noBorder,
          disabledBorder: noBorder,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget content;

    if (widget.isCompact) {
      content = AnimatedSwitcher(
        duration: _ST.collapseAnim,
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        transitionBuilder: (child, anim) => FadeTransition(
          opacity: anim,
          child: ScaleTransition(scale: anim, child: child),
        ),
        child: KeyedSubtree(
          key: const ValueKey('compact'),
          child: _buildCompact(context),
        ),
      );
    } else {
      content = _buildField(context);
    }

    if (widget.maxWidth != null) {
      content = ConstrainedBox(
        constraints: BoxConstraints(maxWidth: widget.maxWidth!),
        child: content,
      );
    }

    return content;
  }
}
