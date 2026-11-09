// lib/widgets/text/otzaria_search_field.dart

import 'dart:math' as math;

import 'package:flutter/cupertino.dart' show cupertinoTextSelectionControls;
import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:otzaria_icons/otzaria_icons.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/text/otzaria_search_field_button.dart';
import 'package:otzaria/widgets/text/rtl_text_field.dart';

export 'package:otzaria/widgets/text/otzaria_search_field_button.dart';

abstract class _ST {
  // Touch (standard)
  static const double height = AppInputTokens.regularHeight;
  static const double heightCompact = 40.0;
  static const double fontSize = AppInputTokens.regularFontSize;

  // Desktop (slim)
  static const double heightSlim = AppInputTokens.compactHeight;
  static const double fontSizeSlim = AppInputTokens.compactFontSize;

  /// רוחב תיבת הקלט שתווית של כפתור לא תצמצם מתחתיו.
  static const double minInputWidthWithLabels = 120.0;

  static const double fillAlphaUnfocused = AppInputTokens.unfocusedAlpha;
  static const double fillAlphaFocused = AppInputTokens.focusedAlpha;
  static const Duration collapseAnim = Duration(milliseconds: 220);
}

// ─────────────────────────────────────────────────────────────────────────────
//  OtzariaSearchAction
// ─────────────────────────────────────────────────────────────────────────────

class OtzariaSearchAction {
  OtzariaSearchAction._();

  /// כפתור הגדרות
  static Widget settings({
    required VoidCallback onPressed,
    String tooltip = 'הגדרות חיפוש',
  }) => OtzariaSearchFieldButton(
    icon: FluentIcons.settings_24_regular,
    onPressed: onPressed,
    tooltip: tooltip,
  );

  /// כפתור עם אייקון מותאם. הגודל מהשדה ([OtzariaSearchActionSize]).
  static Widget icon({
    required IconData iconData,
    required VoidCallback onPressed,
    required String tooltip,
    Color? color,
  }) => OtzariaSearchFieldButton(
    icon: iconData,
    onPressed: onPressed,
    tooltip: tooltip,
    color: color,
  );

  /// ה-X של [OtzariaSearchClearButton], לקורא שמנהל בעצמו מתי הוא מוצג.
  static Widget clear({Key? key, required VoidCallback onPressed}) => Builder(
    key: key,
    builder: (context) => OtzariaSearchFieldButton(
      icon: FluentIcons.dismiss_24_regular,
      onPressed: onPressed,
      tooltip: context.settingsText('נקה'),
      clearGlyph: true,
    ),
  );
}

/// כפתור הניקוי של שדות החיפוש: מוצג רק כשיש טקסט ב-[controller], אלא אם
/// [showWhenEmpty]. הגודל מהשדה ([OtzariaSearchActionSize]).
class OtzariaSearchClearButton extends StatelessWidget {
  final TextEditingController controller;

  /// מופעל אחרי שהטקסט נוקה, לניקוי מצב נלווה.
  final VoidCallback? onCleared;

  /// מפתח הכפתור עצמו, שקיים רק כשהוא מוצג.
  final Key? buttonKey;

  /// כשהניקוי מאפס גם מצב נלווה ([onCleared]), הוא נחוץ גם בשדה ריק.
  final bool showWhenEmpty;

  const OtzariaSearchClearButton({
    super.key,
    required this.controller,
    this.onCleared,
    this.buttonKey,
    this.showWhenEmpty = false,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) => value.text.isEmpty && !showWhenEmpty
          ? const SizedBox.shrink()
          : OtzariaSearchAction.clear(
              key: buttonKey,
              onPressed: () {
                controller.clear();
                onCleared?.call();
              },
            ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  כפתורים פנימיים
// ─────────────────────────────────────────────────────────────────────────────

// ─────────────────────────────────────────────────────────────────────────────
//  OtzariaSearchDisplayBar
// ─────────────────────────────────────────────────────────────────────────────

/// סרגל בעיצוב [OtzariaSearchField] המציג תוכן קבוע, ולחיצה עליו — בכל
/// שטחו — מפעילה את [onTap].
///
/// [child] — התוכן המוצג (טקסט / תצוגת מילות חיפוש).
/// [icon] — האייקון בראש הסרגל, ומרמז על הפעולה שהלחיצה מבצעת.
/// [slim] = null: יורש אוטומטית מ-[AppDensity].
class OtzariaSearchDisplayBar extends StatelessWidget {
  final Widget child;
  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;
  final bool? slim;

  const OtzariaSearchDisplayBar({
    super.key,
    required this.child,
    this.icon = OtzariaIcons.search_24_regular,
    this.onTap,
    this.tooltip,
    this.slim,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isSlim = slim ?? AppDensity.of(context).isCompact;

    Widget bar = Container(
      height: isSlim ? _ST.heightSlim : _ST.height,
      padding: const EdgeInsets.symmetric(horizontal: AppTokens.spaceSM),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: AppTokens.iconMD, color: cs.onSurfaceVariant),
          const SizedBox(width: AppTokens.spaceSM),
          Flexible(child: child),
        ],
      ),
    );

    if (onTap != null) {
      bar = InkWell(
        onTap: onTap,
        borderRadius: AppTokens.borderRadiusAll,
        child: bar,
      );
    }
    if (tooltip != null) {
      bar = Tooltip(message: tooltip!, child: bar);
    }

    return Material(
      color: cs.onSurface.withValues(alpha: _ST.fillAlphaUnfocused),
      borderRadius: AppTokens.borderRadiusAll,
      clipBehavior: Clip.antiAlias,
      child: bar,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  OtzariaSearchField
// ─────────────────────────────────────────────────────────────────────────────

/// כפתורים שמוזרקים לשדה מבחוץ, לפני [OtzariaSearchField.trailingActions]
/// (למשל כפתורי תוספים). השדה נבנה מחדש כשהמקור מודיע על שינוי.
abstract class OtzariaSearchFieldExtraActions implements Listenable {
  const OtzariaSearchFieldExtraActions();

  /// כמה כפתורים [build] עשוי להחזיר לכל היותר, לחישוב המקום לתוויות.
  int get maxButtonCount => 1;

  /// האם אחד הכפתורים עשוי להציג [OtzariaSearchFieldButton.label].
  bool get mayShowLabels => false;

  /// הכפתורים לשדה פעיל; null כשאין כרגע כפתורים.
  Widget? build(
    BuildContext context, {
    required TextEditingController controller,
    required ValueChanged<String>? onChanged,
    required ValueChanged<String>? onSubmitted,
  });
}

/// שדה חיפוש של אוצריא.
///
/// מצבים:
/// • [slim] = null: יורש אוטומטית מ-[AppDensity]
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

  /// מציג את פעולות החיפוש מתחת לשדה, כדי להשאיר מקום לשאילתה בחלונית צרה.
  final bool actionsBelow;

  /// אייקון החיפוש. עדיף למקד אותו לפי מה שמחפשים בו — למשל
  /// `search_in_library_24_regular` בספרייה — כשהשדה מחפש בגוף תוכן
  /// שאינו מוצג על המסך. `leading` דוחה אותו.
  final IconData icon;

  /// כשמוגדר, אייקון החיפוש הוא כפתור (למשל "חפש" בשדה שמחפש רק ב-Enter),
  /// עם [iconTooltip]. הצבע נשאר זה של האייקון, לפי הפוקוס.
  final VoidCallback? onIconPressed;
  final String? iconTooltip;

  /// `null` = יורש אוטומטית מ-[AppDensity].
  /// `true` = שדה צר, `false` = שדה רחב.
  final bool? slim;

  /// כשאמת — מתכווץ לאייקון עגול (M3 scroll-hide)
  final bool isCompact;
  final VoidCallback? onExpand;
  final bool selectAllOnFocus;

  /// שדה מושבת — מוצג בצבע עמום ואינו מקבל קלט. משמש בסרגל שמעל חלונית
  /// ניווט כשללשונית הנבחרת אין פעולת חיפוש.
  final bool enabled;

  /// כפתורים נוספים מבחוץ, למשל של תוספים; null = אין.
  final OtzariaSearchFieldExtraActions? extraActions;

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
    this.actionsBelow = false,
    this.icon = OtzariaIcons.search_24_regular,
    this.onIconPressed,
    this.iconTooltip,
    this.slim,
    this.isCompact = false,
    this.onExpand,
    this.selectAllOnFocus = true,
    this.enabled = true,
    this.extraActions,
  }) : assert(
         onIconPressed == null || iconTooltip != null,
         'כפתור אייקון בלבד צריך tooltip',
       );

  @override
  State<OtzariaSearchField> createState() => _OtzariaSearchFieldState();
}

class _OtzariaSearchFieldState extends State<OtzariaSearchField> {
  // השדה עובר אל LayoutBuilder וממנו כשתווית אפשרית, בלי לאבד את מצבו.
  final _fieldKey = GlobalKey();
  late FocusNode _effectiveFocusNode;
  bool _hasFocus = false;

  bool _resolveSlim(BuildContext context) {
    if (widget.slim != null) return widget.slim!;
    return AppDensity.of(context).isCompact;
  }

  @override
  void initState() {
    super.initState();
    _effectiveFocusNode = widget.focusNode ?? FocusNode();
    _hasFocus = _effectiveFocusNode.hasFocus;
    _effectiveFocusNode.addListener(_onFocusChange);
    widget.controller.addListener(_onTextChange);
    widget.extraActions?.addListener(_onExtraActionsChanged);
  }

  @override
  void didUpdateWidget(OtzariaSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      _effectiveFocusNode.removeListener(_onFocusChange);
      if (oldWidget.focusNode == null) _effectiveFocusNode.dispose();
      _effectiveFocusNode = widget.focusNode ?? FocusNode();
      _hasFocus = _effectiveFocusNode.hasFocus;
      _effectiveFocusNode.addListener(_onFocusChange);
    }
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onTextChange);
      widget.controller.addListener(_onTextChange);
    }
    if (!identical(oldWidget.extraActions, widget.extraActions)) {
      oldWidget.extraActions?.removeListener(_onExtraActionsChanged);
      widget.extraActions?.addListener(_onExtraActionsChanged);
    }
  }

  @override
  void dispose() {
    _effectiveFocusNode.removeListener(_onFocusChange);
    if (widget.focusNode == null) _effectiveFocusNode.dispose();
    widget.controller.removeListener(_onTextChange);
    widget.extraActions?.removeListener(_onExtraActionsChanged);
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

  void _onExtraActionsChanged() {
    if (mounted) setState(() {});
  }

  // ── מצב compact (אייקון עגול) ────────────────────────────────────────────

  Widget _buildCompact(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: AppMotion.duration(context, _ST.collapseAnim),
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
          widget.icon,
          size: AppTokens.iconMD,
          color: cs.onSurfaceVariant,
        ),
        onPressed: widget.onExpand,
        tooltip: widget.hintText,
      ),
    );
  }

  // ── שדה מלא ──────────────────────────────────────────────────────────────

  double _selectionHandleClearance(BuildContext context, double fontSize) {
    final controls = switch (Theme.of(context).platform) {
      TargetPlatform.android ||
      TargetPlatform.fuchsia => materialTextSelectionControls,
      TargetPlatform.iOS => cupertinoTextSelectionControls,
      _ => null,
    };
    if (controls == null) return 0;
    final lineHeight = MediaQuery.textScalerOf(context).scale(fontSize);
    final height = controls.getHandleSize(lineHeight).height;
    final touchPadding = math.max(0.0, (kMinInteractiveDimension - height) / 2);
    return TextSelectionHandleType.values.fold<double>(
      0,
      (clearance, type) => math.max(
        clearance,
        height + touchPadding - controls.getHandleAnchor(type, lineHeight).dy,
      ),
    );
  }

  Widget _buildField(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasText = widget.controller.text.isNotEmpty;
    final isSlim = _resolveSlim(context);

    // גובה וגופן — slim (desktop) לעומת touch
    final double effectiveHeight = isSlim ? _ST.heightSlim : _ST.height;
    final double effectiveFontSize = isSlim ? _ST.fontSizeSlim : _ST.fontSize;
    // אייקון ממשק רגיל (DD-03) גם בשדה הרחב, כמו בצר; לא 22 (review-r5,
    // q-search-22).
    const double prefixIconSize = AppTokens.iconMD;

    // Fill
    final fillColor = _hasFocus && widget.enabled
        ? cs.primary.withValues(alpha: _ST.fillAlphaFocused)
        : cs.onSurface.withValues(alpha: _ST.fillAlphaUnfocused);
    final contentColor = widget.enabled
        ? cs.onSurface
        : cs.onSurfaceVariant.withValues(alpha: 0.5);
    final hintColor = widget.enabled
        ? cs.onSurfaceVariant
        : cs.onSurfaceVariant.withValues(alpha: 0.5);

    // Borders
    final noBorder = OutlineInputBorder(
      borderRadius: AppTokens.borderRadiusAll,
      borderSide: BorderSide.none,
    );

    // Suffix
    final List<Widget> suffixChildren = [];
    final extraActions = widget.enabled
        ? widget.extraActions?.build(
            context,
            controller: widget.controller,
            onChanged: widget.onChanged,
            onSubmitted: widget.onSubmitted,
          )
        : null;
    if (extraActions != null) suffixChildren.add(extraActions);
    if (widget.trailingActions != null) {
      suffixChildren.addAll(widget.trailingActions!);
    }
    final belowActions = widget.actionsBelow
        ? List<Widget>.of(suffixChildren)
        : const <Widget>[];
    if (widget.actionsBelow) suffixChildren.clear();
    if (hasText && widget.onClear != null) {
      suffixChildren.add(
        OtzariaSearchClearButton(
          controller: widget.controller,
          onCleared: widget.onClear,
        ),
      );
    }
    final suffixWidget = suffixChildren.isNotEmpty
        ? Row(mainAxisSize: MainAxisSize.min, children: suffixChildren)
        : SizedBox(width: isSlim ? 32.0 : 40.0);

    // Prefix icon color
    // slim (בסרגל secondaryContainer) → onSecondaryContainer
    // לא-slim (רקע surface) → primary (M3 standard)
    final Color focusedIconColor = isSlim
        ? cs.onSecondaryContainer
        : cs.primary;

    final Widget searchIcon = Icon(
      widget.icon,
      size: prefixIconSize,
      color: _hasFocus && widget.enabled ? focusedIconColor : hintColor,
    );
    final prefixIcon =
        widget.leading ??
        (widget.onIconPressed == null
            ? searchIcon
            : IconButton(
                icon: searchIcon,
                tooltip: widget.iconTooltip,
                onPressed: widget.enabled ? widget.onIconPressed : null,
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
              ));

    final contentPadding = EdgeInsets.symmetric(
      horizontal: AppTokens.spaceXS,
      vertical: 0,
    );

    final actionSize = isSlim
        ? OtzariaSearchActionSize.slim
        : OtzariaSearchActionSize.regular;
    final prefixMinWidth = isSlim ? 36.0 : 44.0;
    final mayShowLabels =
        (extraActions != null && widget.extraActions!.mayShowLabels) ||
        (widget.trailingActions?.any(
              (action) =>
                  action is OtzariaSearchFieldButton && action.label != null,
            ) ??
            false);
    Widget field = SizedBox(
      key: _fieldKey,
      height: effectiveHeight,
      child: RtlTextField(
        controller: widget.controller,
        focusNode: _effectiveFocusNode,
        enabled: widget.enabled,
        autofocus: widget.autofocus,
        onChanged: widget.onChanged,
        onSubmitted: widget.onSubmitted,
        textInputAction: TextInputAction.search,
        textAlignVertical: TextAlignVertical.center,
        cursorColor: cs.onSurface.withValues(alpha: 0.87),
        style: TextStyle(fontSize: effectiveFontSize, color: contentColor),
        decoration: InputDecoration(
          filled: true,
          fillColor: fillColor,
          contentPadding: contentPadding,
          isCollapsed: false,
          isDense: true,
          prefixIcon: prefixIcon,
          prefixIconConstraints: BoxConstraints(
            minWidth: prefixMinWidth,
            minHeight: effectiveHeight,
          ),
          suffixIcon: suffixWidget,
          suffixIconConstraints: BoxConstraints(
            minWidth: suffixChildren.isNotEmpty
                ? (suffixChildren.length * (isSlim ? 28.0 : 34.0)).clamp(
                    isSlim ? 28.0 : 34.0,
                    180.0,
                  )
                : (isSlim ? 32.0 : 40.0),
            minHeight: effectiveHeight,
          ),
          hintText: widget.hintText,
          hintStyle: TextStyle(fontSize: effectiveFontSize, color: hintColor),
          border: noBorder,
          enabledBorder: noBorder,
          focusedBorder: noBorder,
          errorBorder: noBorder,
          focusedErrorBorder: noBorder,
          disabledBorder: noBorder,
        ),
      ),
    );
    if (belowActions.isNotEmpty) {
      field = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          field,
          // Mobile selection handles extend below the input. Reserve their full
          // touch target even before focus, so the action row stays in place.
          SizedBox(
            height: _selectionHandleClearance(context, effectiveFontSize),
          ),
          Wrap(alignment: WrapAlignment.end, children: belowActions),
        ],
      );
    }
    Widget scoped(double labelBudget) => OtzariaSearchActionScope(
      size: actionSize,
      labelBudget: labelBudget,
      child: field,
    );
    if (!mayShowLabels) return scoped(0);
    // בשורה נפרדת התוויות חולקות רק את רוחב הפעולות; הניקוי נשאר בקלט.
    // בתוך השדה משאירים גם מקום לאייקון, לריפוד ולרוחב קלט שמיש.
    final clearButtons = hasText && widget.onClear != null ? 1 : 0;
    final buttons =
        (widget.trailingActions?.length ?? 0) +
        clearButtons +
        (extraActions == null ? 0 : widget.extraActions!.maxButtonCount);
    return LayoutBuilder(
      builder: (context, constraints) => scoped(
        constraints.maxWidth.isFinite
            ? math.max(
                0,
                widget.actionsBelow
                    ? constraints.maxWidth -
                          (buttons - clearButtons) * actionSize.button
                    : constraints.maxWidth -
                          prefixMinWidth -
                          contentPadding.horizontal -
                          buttons * actionSize.button -
                          _ST.minInputWidthWithLabels,
              )
            : double.infinity,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget content;

    if (widget.isCompact) {
      content = AnimatedSwitcher(
        duration: AppMotion.duration(context, _ST.collapseAnim),
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
