import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:otzaria/tabs/models/combined_tab.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/tabs/view/pane_drop_geometry.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/navigation/nav_panel_search.dart';
import 'package:otzaria/settings/l10n/settings_l10n_exports.dart';

export 'pane_drop_geometry.dart'
    show
        kMinPaneExtent,
        kMinPaneRatio,
        kPaneCardMargin,
        kPaneDividerThickness,
        kPaneDividerThicknessTouch,
        paneDividerThicknessFor;

/// עובי ידית המפריד.
const double _kDividerHandleThickness = 4;

/// אורך ידית המפריד לאורך הרצועה.
const double _kDividerHandleLength = 40;

/// כמה זז המפריד בכל הקשה על חץ.
const double _kKeyboardNudge = 24;

/// השהיית השמירה אחרי הקשות מקלדת, כדי שהקשה ממושכת תישמר פעם אחת.
const Duration _kKeyboardCommitDelay = Duration(milliseconds: 250);

/// מציג טאב בחלונית אחת או בשתי חלוניות עם מפריד ניתן לגרירה.
/// [paneBuilder] עטוף במפתח זהות כדי לשמר את מצב החלונית בפיצול ובפירוק.
class SplitPaneView extends StatelessWidget {
  /// הטאב המוצג — מפוצל או יחיד.
  final OpenedTab root;

  /// בונה את תוכן החלונית.
  final Widget Function(OpenedTab pane) paneBuilder;

  /// נקרא בתום גרירת המפריד, עם היחס החדש.
  final ValueChanged<double> onRatioChanged;

  const SplitPaneView({
    super.key,
    required this.root,
    required this.paneBuilder,
    required this.onRatioChanged,
  });

  @override
  Widget build(BuildContext context) {
    final node = root;
    if (node is! CombinedTab) {
      return buildPane(node, paneBuilder);
    }

    return ColoredBox(
      color: AppSurfaces.paneGutter(context),
      child: Padding(
        padding: const EdgeInsets.all(kPaneCardMargin),
        child: _SplitNode(
          // החלפת צדדים יוצרת צומת חדש, אך גרירת המפריד שומרת על הצומת.
          key: ObjectKey(node),
          node: node,
          thickness: paneDividerThicknessFor(Theme.of(context).platform),
          paneBuilder: paneBuilder,
          onRatioChanged: onRatioChanged,
        ),
      ),
    );
  }

  /// עוטפת חלונית במפתח זהות.
  @visibleForTesting
  static Widget buildPane(
    OpenedTab pane,
    Widget Function(OpenedTab pane) paneBuilder,
  ) {
    // _SplitNode בונה את החלוניות פעם אחת לפני ה-ValueListenableBuilder, כדי
    // שגרירת המפריד תפרוס אותן מחדש בלי לבנות את תצוגות הספרים. ה-child חייב
    // להישאר מחוץ ל-LayoutBuilder, שנקרא מחדש בכל שינוי רוחב.
    final child = paneBuilder(pane);
    return ClipRect(
      child: KeyedSubtree(
        key: GlobalObjectKey(pane),
        child: LayoutBuilder(
          builder: (context, constraints) => NavPanelPaneWidthScope(
            width: constraints.maxWidth,
            child: child,
          ),
        ),
      ),
    );
  }
}

/// מסגור חלונית בטאב מפוצל.
class PaneCard extends StatelessWidget {
  final bool isActive;
  final bool isSplit;
  final Widget child;

  const PaneCard({
    super.key,
    required this.isActive,
    required this.isSplit,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(isSplit ? AppTokens.radius : 0);
    final duration = AppMotion.duration(
      context,
      const Duration(milliseconds: 160),
    );
    // "לבן" (#2850): כל החלוניות במסגרת הכהה הדקה, והפעילה מסומנת בטבעת
    // בצבע הראשי שמצוירת מעל הקצה, כדי שהמעבר בין החלוניות לא ישנה את הריפוד.
    final regionBorder = AppSurfaces.regionBorder(context);
    final border = isSplit
        ? Border.all(
            color:
                regionBorder ??
                AppSurfaces.paneCardBorder(cs, isActive: isActive),
          )
        : null;
    // המסגרת מונפשת מאחורי התוכן ולא סביבו: ריפוד מונפש היה פורס מחדש את
    // שני הספרים בכל פריים של הפיצול והפירוק.
    return Stack(
      fit: StackFit.passthrough,
      children: [
        Positioned.fill(
          child: AnimatedContainer(
            duration: duration,
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              color: isSplit
                  ? AppSurfaces.paneCard(context)
                  : Colors.transparent,
              borderRadius: radius,
              border: border,
            ),
          ),
        ),
        Padding(
          padding: border?.dimensions ?? EdgeInsets.zero,
          child: ClipRRect(borderRadius: radius, child: child),
        ),
        if (isSplit && regionBorder != null)
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedContainer(
                duration: duration,
                curve: Curves.easeOut,
                decoration: BoxDecoration(
                  borderRadius: radius,
                  border: Border.all(
                    color: isActive ? cs.primary : Colors.transparent,
                    width: AppTokens.focusRingWidth,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// שתי חלוניות ומפריד ביניהן.
class _SplitNode extends StatefulWidget {
  final CombinedTab node;
  final double thickness;
  final Widget Function(OpenedTab pane) paneBuilder;
  final ValueChanged<double> onRatioChanged;

  const _SplitNode({
    super.key,
    required this.node,
    required this.thickness,
    required this.paneBuilder,
    required this.onRatioChanged,
  });

  @override
  State<_SplitNode> createState() => _SplitNodeState();
}

class _SplitNodeState extends State<_SplitNode> {
  /// מעדכן את יחס החלוניות בלי לבנות מחדש את תצוגות הספרים.
  late final ValueNotifier<double> _ratioNotifier;
  bool _dragging = false;
  Timer? _commitDebounce;

  double get _ratio => _ratioNotifier.value;

  @override
  void initState() {
    super.initState();
    _ratioNotifier = ValueNotifier<double>(widget.node.splitRatio);
  }

  @override
  void dispose() {
    _commitDebounce?.cancel();
    _ratioNotifier.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(_SplitNode oldWidget) {
    super.didUpdateWidget(oldWidget);
    // עדכון חיצוני לא ידרוס גרירה או הקשה שטרם נשמרו.
    if (!_dragging &&
        _commitDebounce == null &&
        widget.node.splitRatio != _ratio) {
      _ratioNotifier.value = widget.node.splitRatio;
    }
  }

  double? get _availableExtent {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    final available = box.size.width - widget.thickness;
    return available > 0 ? available : null;
  }

  void _applyAxisDelta(double delta) {
    final availableExtent = _availableExtent;
    if (availableExtent == null) return;

    final minRatio = minPaneRatioFor(availableExtent);
    // אין לשנות יחס כשאין מקום לשתי חלוניות קריאות.
    if (minRatio >= 0.5) return;
    final effectiveRatio = _ratio.clamp(minRatio, 1 - minRatio);
    _ratioNotifier.value = (effectiveRatio + delta / availableExtent).clamp(
      minRatio,
      1 - minRatio,
    );
  }

  void _onDragUpdate(DragUpdateDetails details) {
    // ב-RTL כיוון הגרירה הפוך.
    _applyAxisDelta(
      Directionality.of(context) == TextDirection.rtl
          ? -details.delta.dx
          : details.delta.dx,
    );
  }

  void _nudge({required bool towardFirst}) {
    final before = _ratio;
    _applyAxisDelta(towardFirst ? -_kKeyboardNudge : _kKeyboardNudge);
    if (_ratio == before) return;
    // השהיה מאגדת הקשות רצופות לשמירה אחת.
    _commitDebounce?.cancel();
    _commitDebounce = Timer(_kKeyboardCommitDelay, _commit);
  }

  /// היחס שיושג בהזזה אחת מ-[from], לדיווח לקורא מסך.
  /// [extent] מגיע מה-layout ולא מ-[_availableExtent], שאין לו מידה בבנייה
  /// הראשונה — ואז המחוון היה מדווח יחס שלא ניתן להגיע אליו.
  double _ratioAfterNudge(
    double extent,
    double from, {
    required bool towardFirst,
  }) {
    if (extent <= 0) return from;
    final minRatio = minPaneRatioFor(extent);
    if (minRatio >= 0.5) return from;
    final delta = (towardFirst ? -_kKeyboardNudge : _kKeyboardNudge) / extent;
    return (from + delta).clamp(minRatio, 1 - minRatio);
  }

  void _commit() {
    _commitDebounce?.cancel();
    _commitDebounce = null;
    _dragging = false;
    widget.node.splitRatio = _ratio;
    widget.onRatioChanged(_ratio);
  }

  void _resetRatio() {
    _ratioNotifier.value = 0.5;
    _commit();
  }

  @override
  Widget build(BuildContext context) {
    // שינוי יחס בונה רק את ה-Row, לא את תצוגות הספרים.
    final firstChild = SplitPaneView.buildPane(
      widget.node.rightTab,
      widget.paneBuilder,
    );
    final secondChild = SplitPaneView.buildPane(
      widget.node.leftTab,
      widget.paneBuilder,
    );

    return ValueListenableBuilder<double>(
      valueListenable: _ratioNotifier,
      builder: (context, ratio, _) {
        return LayoutBuilder(
          // גבול בין החלוניות על שבר פיקסל: חיתוך הכרטיס (hardEdge) מקצר את
          // הרוחב לפיקסל שלם ומוחק את קו המסגרת של החלונית הפעילה.
          builder: (context, constraints) {
            final available = constraints.maxWidth - widget.thickness;
            // גם יחס שנשמר לפני הרצפה היחסית לא יצייר רצועה במקום חלונית.
            final minRatio = minPaneRatioFor(available);
            final effectiveRatio = ratio.clamp(minRatio, 1 - minRatio);
            final firstWidth = available > 0
                ? (available * effectiveRatio).roundToDouble().clamp(
                    0.0,
                    available,
                  )
                : 0.0;

            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // הילדים נבנים מחוץ ל-builder, ולכן פריסה מחדש אינה בונה
                // מחדש את תצוגות הספרים.
                SizedBox(width: firstWidth, child: firstChild),
                _PaneDivider(
                  thickness: widget.thickness,
                  isTouch: widget.thickness == kPaneDividerThicknessTouch,
                  // המחוון מדווח את היחס המצויר, לא יחס שמור שנחסם ברצפה.
                  ratio: effectiveRatio,
                  increasedRatio: _ratioAfterNudge(
                    available,
                    effectiveRatio,
                    towardFirst: false,
                  ),
                  decreasedRatio: _ratioAfterNudge(
                    available,
                    effectiveRatio,
                    towardFirst: true,
                  ),
                  onDragStart: () => _dragging = true,
                  onDragUpdate: _onDragUpdate,
                  onDragEnd: _commit,
                  onReset: _resetRatio,
                  onNudge: (towardFirst) => _nudge(towardFirst: towardFirst),
                ),
                Expanded(child: secondChild),
              ],
            );
          },
        );
      },
    );
  }
}

/// רצועת מפריד עם אזור תפיסה רחב מהידית הנראית.
class _PaneDivider extends StatefulWidget {
  /// עובי רצועת התפיסה — רחבה יותר במגע.
  final double thickness;

  /// מאפשרת איפוס בלחיצה ארוכה במגע בלבד.
  final bool isTouch;

  /// היחס הנוכחי, לדיווח לקורא מסך בלבד.
  final double ratio;

  /// יחסי היעד של הזזה אחת לכל כיוון.
  final double increasedRatio;
  final double decreasedRatio;

  final VoidCallback onDragStart;
  final ValueChanged<DragUpdateDetails> onDragUpdate;
  final VoidCallback onDragEnd;
  final VoidCallback onReset;

  final ValueChanged<bool> onNudge;

  const _PaneDivider({
    required this.thickness,
    required this.isTouch,
    required this.ratio,
    required this.increasedRatio,
    required this.decreasedRatio,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onReset,
    required this.onNudge,
  });

  @override
  State<_PaneDivider> createState() => _PaneDividerState();
}

class _PaneDividerState extends State<_PaneDivider> {
  bool _hovering = false;
  bool _dragging = false;
  bool _focused = false;

  /// מאפשר למפריד לקבל פוקוס מקלדת.
  final FocusNode _focusNode = FocusNode(debugLabel: 'מפריד חלוניות');

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _setDragging(bool value) {
    if (_dragging != value) setState(() => _dragging = value);
  }

  static String _percent(double ratio) =>
      '${(ratio.clamp(0.0, 1.0) * 100).round()}%';

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final active = _hovering || _dragging || _focused;

    // הגרירה אינה תובעת פוקוס: הוא היה נשאר על המפריד גם אחריה, והחצים
    // ו-Home היו מזיזים אותו במקום לגלול את הספר.
    void handleDragStart(DragStartDetails _) {
      _focusNode.unfocus();
      _setDragging(true);
      widget.onDragStart();
    }

    void handleDragEnd(DragEndDetails _) {
      _setDragging(false);
      widget.onDragEnd();
    }

    // ב-RTL החצים משקפים את כיוון הגרירה.
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Focus(
        focusNode: _focusNode,
        // רכיב Semantics הפנימי מגדיר את המחוון.
        includeSemantics: false,
        onFocusChange: (value) => setState(() => _focused = value),
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
            return KeyEventResult.ignored;
          }
          // קיצורי מקשים שייכים למסך, לא למפריד.
          final keyboard = HardwareKeyboard.instance;
          if (keyboard.isAltPressed ||
              keyboard.isControlPressed ||
              keyboard.isMetaPressed) {
            return KeyEventResult.ignored;
          }
          final key = event.logicalKey;
          if (key == LogicalKeyboardKey.arrowLeft) {
            widget.onNudge(!isRtl);
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.arrowRight) {
            widget.onNudge(isRtl);
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.home) {
            widget.onReset();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onDoubleTap: widget.onReset,
          // לחיצה ארוכה בעכבר מתנגשת עם זיהוי הגרירה.
          onLongPress: widget.isTouch ? widget.onReset : null,
          onHorizontalDragStart: handleDragStart,
          onHorizontalDragUpdate: widget.onDragUpdate,
          onHorizontalDragEnd: handleDragEnd,
          child: Semantics(
            container: true,
            slider: true,
            focusable: true,
            focused: _focused,
            value: _percent(widget.ratio),
            increasedValue: _percent(widget.increasedRatio),
            decreasedValue: _percent(widget.decreasedRatio),
            label: context.settingsText(
              'מפריד בין חלוניות — גרירה או חצים לצדדים, Home לאיפוס',
            ),
            onIncrease: () => widget.onNudge(false),
            onDecrease: () => widget.onNudge(true),
            child: SizedBox(
              width: widget.thickness,
              child: Center(
                // דהייה בצבע ולא ב-AnimatedOpacity: אטימות חיה הופכת את המפריד
                // ל-repaint boundary, ומסגרת החלונית שמצוירת אחריו נעלמת.
                child: AnimatedContainer(
                  duration: AppMotion.duration(
                    context,
                    const Duration(milliseconds: 140),
                  ),
                  curve: Curves.easeOut,
                  width: _kDividerHandleThickness,
                  height: _kDividerHandleLength,
                  decoration: BoxDecoration(
                    color: AppSurfaces.paneDividerHandle(
                      colorScheme,
                      isActive: active,
                    ),
                    borderRadius: BorderRadius.circular(
                      _kDividerHandleThickness / 2,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
