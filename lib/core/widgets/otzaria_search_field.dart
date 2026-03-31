import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/rtl_text_field.dart';

// ═════════════════════════════════════════════════════════════════════════════
//  OtzariaSearchField  v3.1
//  lib/core/widgets/otzaria_search_field.dart
//
//  שינויים מ-v3:
//  • שוחזר צבע focus border ל-cs.primary (כמו v2) — הוסר שינוי v3
//  • שוחזר fillColor בפוקוס ל-cs.primary × alpha (כמו v2)
//  • cursorColor מוגדר ל-cs.onSurface — לא אדום/primary בוהק
//  • resultCounter: גדול יותר, inherits font family של האפליקציה (קלאסי)
//  • collapse / isCompact — נשמר מ-v3
// ═════════════════════════════════════════════════════════════════════════════

abstract class _ST {
  static const double radius = 28.0;
  static const double height = 48.0;
  static const double heightCompact = 40.0;
  static const double fontSize = AppTokens.fontLG; // 16
  static const double fillAlphaUnfocused = 0.07;
  static const double fillAlphaFocused = 0.12; // primary × 12% כמו v2
  static const double focusBorderWidth = 1.5; // כמו v2
  static const Duration collapseAnim = Duration(milliseconds: 220);
}

// ─────────────────────────────────────────────────────────────────────────────
//  OtzariaSearchAction
// ─────────────────────────────────────────────────────────────────────────────
class OtzariaSearchAction {
  OtzariaSearchAction._();

  /// מונה תוצאות: "3/12" — בגופן קלאסי של האפליקציה
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
          // fontSize בינוני — נראה כמו שאר הטקסט בתוכנה
          fontSize: AppTokens.fontMD, // 14
          fontWeight: FontWeight.w500,
          // color ← מה-context; fallback → ירושה מהtheme (onSurfaceVariant)
          color: context != null
              ? Theme.of(context).colorScheme.onSurfaceVariant
              : null,
          // fontFamily ← ירושה מהtheme (גופן קלאסי של האפליקציה)
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

  /// כפתור כלשהו עם אייקון מותאם
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
class OtzariaSearchField extends StatefulWidget {
  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  /// callback לניקוי — אם null כפתור ✕ לא מוצג
  final VoidCallback? onClear;
  final FocusNode? focusNode;
  final bool autofocus;
  final double? maxWidth;

  /// אייקון מוביל מותאם (ברירת מחדל: FluentIcons.search)
  final Widget? leading;

  /// כפתורים / ווידג'טים בסוף השדה, לפני ✕
  /// בנה עם OtzariaSearchAction.xxx()
  final List<Widget>? trailingActions;

  /// כשאמת — השדה מתכווץ לאייקון עגול (M3 scroll-hide)
  final bool isCompact;

  /// callback כשמקישים על האייקון במצב compact
  final VoidCallback? onExpand;

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
    this.isCompact = false,
    this.onExpand,
  });

  @override
  State<OtzariaSearchField> createState() => _OtzariaSearchFieldState();
}

class _OtzariaSearchFieldState extends State<OtzariaSearchField> {
  late FocusNode _effectiveFocusNode;
  bool _hasFocus = false;

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
    if (mounted) setState(() => _hasFocus = _effectiveFocusNode.hasFocus);
  }

  void _onTextChange() {
    if (mounted) setState(() {});
  }

  // ── מצב compact ──────────────────────────────────────────────────────────
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

    // ── Fill ──────────────────────────────────────────────────────────────
    // בפוקוס: primary × 12% (כמו v2) — גוון צבע המערכת
    // ללא פוקוס: onSurface × 7% — ניטרלי
    final fillColor = _hasFocus
        ? cs.primary.withValues(alpha: _ST.fillAlphaFocused)
        : cs.onSurface.withValues(alpha: _ST.fillAlphaUnfocused);

    // ── Borders ─────────────────────────────────────────────────────────
    // שניהם OutlineInputBorder — מונע shift בגובה
    // border בפוקוס: cs.primary (כמו v2) — ברור, עקבי עם fill
    final noBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(_ST.radius),
      borderSide: BorderSide.none,
    );
    final focusBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(_ST.radius),
      borderSide: BorderSide(
        color: cs.primary,
        width: _ST.focusBorderWidth,
      ),
    );

    // ── Suffix ───────────────────────────────────────────────────────────
    final List<Widget> suffixChildren = [];
    // הוסף trailingActions תמיד (לא רק כשיש טקסט)
    if (widget.trailingActions != null) {
      suffixChildren.addAll(widget.trailingActions!);
    }
    // כפתור X מופיע רק כשיש טקסט
    if (hasText && widget.onClear != null) {
      suffixChildren.add(SizedBox(
        width: 32,
        height: 32,
        child: IconButton(
          icon: Icon(FluentIcons.dismiss_24_regular,
              size: 18, color: cs.onSurfaceVariant),
          onPressed: () {
            widget.controller.clear();
            widget.onClear!();
          },
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
        ),
      ));
    }
    // placeholder — מונע shift אופקי כשאין suffix
    final suffixWidget = suffixChildren.isNotEmpty
        ? Row(mainAxisSize: MainAxisSize.min, children: suffixChildren)
        : const SizedBox(width: 40);

    // ── Prefix icon ──────────────────────────────────────────────────────
    // בפוקוס: primary (גוון המערכת) — כמו v2
    final prefixIcon = widget.leading ??
        Icon(
          FluentIcons.search_24_regular,
          size: 20,
          color: _hasFocus ? cs.primary : cs.onSurfaceVariant,
        );

    return SizedBox(
      height: _ST.height,
      child: RtlTextField(
        controller: widget.controller,
        focusNode: _effectiveFocusNode,
        autofocus: widget.autofocus,
        onChanged: widget.onChanged,
        onSubmitted: widget.onSubmitted,
        textInputAction: TextInputAction.search,
        // cursorColor — onSurface כהה, לא primary בוהק/אדום
        // Flutter מנהל cursorHeight/cursorWidth אוטומטית (ללא הגדרה ידנית)
        cursorColor: cs.onSurface.withValues(alpha: 0.87),
        style: TextStyle(
          fontSize: _ST.fontSize,
          color: cs.onSurface,
          height: 1.0,
          leadingDistribution: TextLeadingDistribution.even,
        ),
        decoration: InputDecoration(
          filled: true,
          fillColor: fillColor,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppTokens.spaceXS,
            vertical: 0,
          ),
          isCollapsed: false,
          isDense: true,
          prefixIcon: prefixIcon,
          prefixIconConstraints: const BoxConstraints(
            minWidth: 44,
            minHeight: _ST.height,
          ),
          suffixIcon: suffixWidget,
          suffixIconConstraints: BoxConstraints(
            minWidth: suffixChildren.isNotEmpty
                ? (suffixChildren.length * 34.0).clamp(34.0, 180.0)
                : 40.0,
            minHeight: _ST.height,
          ),
          hintText: widget.hintText,
          hintStyle: TextStyle(
            fontSize: _ST.fontSize,
            color: cs.onSurfaceVariant,
            height: 1.0,
          ),
          border: focusBorder,
          enabledBorder: noBorder,
          focusedBorder: focusBorder,
          errorBorder: noBorder,
          focusedErrorBorder: focusBorder,
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
      content = AnimatedSwitcher(
        duration: _ST.collapseAnim,
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        transitionBuilder: (child, anim) => FadeTransition(
          opacity: anim,
          child: SizeTransition(
            sizeFactor: anim,
            axis: Axis.horizontal,
            child: child,
          ),
        ),
        child: KeyedSubtree(
          key: const ValueKey('full'),
          child: _buildField(context),
        ),
      );
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
