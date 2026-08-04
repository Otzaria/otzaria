import 'package:flutter/material.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/layout/floating_panel.dart';
import 'package:otzaria/widgets/layout/resizable_drag_handle.dart';

/// חלונית צד אדפטיבית:
/// במסך רחב דוחקת תוכן, ובמסך צר נפתחת כ-overlay.
///
/// כללי ברירת מחדל:
/// - תוכן החלונית מקבל שכבת רקע נוספת של חלון (solidPanelBackground).
/// - מעבר מרוחב רחב למסך צר סוגר אוטומטית את החלונית.
/// - חלונית ניווט אמורה להיות בצד ימין (`centerEnd`) וחלונית מידע בצד שמאל (`centerStart`).
///
/// ## התנהגות גרירה
/// בזמן גרירת הוו, רוחב הפאנל מנוהל פנימית ב-[ValueNotifier] ולא גורם ל-rebuild
/// של ה-parent בכל frame. המעבר בין מצב רחב (wide) לצר (narrow) מתרחש רק
/// ב-[onDragEnd] — לא במהלך הגרירה. כך הגרירה חלקה גם כשחוצים את הסף.
class AdaptiveSidePane extends StatefulWidget {
  final bool isOpen;
  final Widget mainContent;
  final Widget paneContent;
  final double paneWidth;
  final double minMainContentWidth;
  final VoidCallback onClose;
  final VoidCallback? onOpen;
  final Color? paneColor;
  final AlignmentDirectional alignment;
  final bool wrapPaneInFloatingPanel;
  final bool isResizable;
  final double minPaneWidth;
  final double? maxPaneWidth;
  final ValueChanged<double>? onPaneWidthChanged;
  final VoidCallback? onPaneResizeEnd;

  /// נקרא כשמצב הפריסה משתנה: true = דחיקת תוכן (wide), false = overlay (narrow).
  /// משמש הורים שצריכים לדעת אם פתיחה/סגירה משנה את רוחב התוכן.
  final ValueChanged<bool>? onLayoutModeChanged;
  final Widget Function(
    BuildContext context,
    Widget paneContent,
    double paneWidth,
  )?
  widePaneBuilder;
  final Widget Function(BuildContext context, Widget paneContent)?
  narrowPaneBuilder;
  final bool autoHandleResponsiveVisibility;

  /// רווח עליון ל-scrollbar thumb — null = ברירת מחדל (_kWideTopGap).
  /// העבר 0 כשיש כותרת קבועה בראש הפאנל שכבר יוצרת הפרדה ויזואלית.
  final double? scrollbarTopMargin;

  const AdaptiveSidePane({
    super.key,
    required this.isOpen,
    required this.mainContent,
    required this.paneContent,
    this.paneWidth = 340,
    this.minMainContentWidth = 500,
    required this.onClose,
    this.onOpen,
    this.paneColor,
    this.alignment = AlignmentDirectional.centerEnd,
    this.wrapPaneInFloatingPanel = true,
    this.isResizable = false,
    this.minPaneWidth = 220,
    this.maxPaneWidth,
    this.onPaneWidthChanged,
    this.onPaneResizeEnd,
    this.onLayoutModeChanged,
    this.widePaneBuilder,
    this.narrowPaneBuilder,
    this.autoHandleResponsiveVisibility = true,
    this.scrollbarTopMargin,
  });

  @override
  State<AdaptiveSidePane> createState() => _AdaptiveSidePaneState();
}

class _AdaptiveSidePaneState extends State<AdaptiveSidePane> {
  bool? _lastHadRoomForSideBySide;
  bool? _lastReportedLayoutMode;

  // ── Drag state ──────────────────────────────────────────────────────────────
  // רוחב פנימי בזמן גרירה — מנוהל דרך ValueNotifier כדי לא לגרום ל-parent rebuild
  late final ValueNotifier<double> _livePaneWidth;
  bool _isDragging = false;
  // snapshot של מצב תחילת גרירה
  bool? _dragStartedInWideMode;

  // אופטימיזציית ביצועים: דחיית בנייה ראשונה של תוכן הפאנל עד שהוא נפתח לראשונה.
  // זה מונע בנייה כבדה של התוכן (TocViewer וכו') כשהפאנל סגור מההתחלה.
  // אחרי הפתיחה הראשונה, התוכן נשמר במגדל הוויידג'טים גם בזמן סגירה כדי לשמור state.
  bool _paneEverOpened = false;

  static const double _kWideTopGap = 14;
  static const double _kWideBottomGap = 10;
  static const double _kWideOuterSideGap = 10;
  static const double _kWideInnerSideGap = 12;
  static const double _kNarrowTopGap = 14;
  static const double _kNarrowBottomGap = 10;
  static const double _kNarrowSideGap = 10;

  @override
  void initState() {
    super.initState();
    _livePaneWidth = ValueNotifier<double>(widget.paneWidth);
    _paneEverOpened = widget.isOpen;
  }

  @override
  void didUpdateWidget(AdaptiveSidePane oldWidget) {
    super.didUpdateWidget(oldWidget);
    // עדכון הרוחב הפנימי כשה-parent שולח רוחב חדש — אבל לא בזמן גרירה
    if (!_isDragging && oldWidget.paneWidth != widget.paneWidth) {
      _livePaneWidth.value = widget.paneWidth;
    }
    if (widget.isOpen && !_paneEverOpened) {
      _paneEverOpened = true;
    }
  }

  @override
  void dispose() {
    _livePaneWidth.dispose();
    super.dispose();
  }

  Color _effectivePaneColor(BuildContext context) {
    return widget.paneColor ?? AppSurfaces.solidPanelBackground(context);
  }

  bool _isPaneOnRight(BuildContext context) {
    if (widget.alignment == AlignmentDirectional.centerEnd) return true;
    if (widget.alignment == AlignmentDirectional.centerStart) return false;
    final resolved = widget.alignment.resolve(Directionality.of(context));
    return resolved.x >= 0;
  }

  bool _resolveHasRoomForSideBySide(bool calculatedHasRoomForSideBySide) {
    if (_isDragging) {
      return _dragStartedInWideMode ??
          (_lastHadRoomForSideBySide ?? calculatedHasRoomForSideBySide);
    }
    return calculatedHasRoomForSideBySide;
  }

  void _handleResponsiveAutoClose(bool hasRoomForSideBySide) {
    final previous = _lastHadRoomForSideBySide;
    _lastHadRoomForSideBySide = hasRoomForSideBySide;

    if (previous == true && !hasRoomForSideBySide && widget.isOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.isOpen) widget.onClose();
      });
    }

    if (previous == false &&
        hasRoomForSideBySide &&
        !widget.isOpen &&
        widget.onOpen != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !widget.isOpen) widget.onOpen!.call();
      });
    }
  }

  Widget _buildPaneShell(
    BuildContext context,
    Widget child, {
    required bool paneOnRight,
  }) {
    final paneColor = _effectivePaneColor(context);
    final shadowColor = Theme.of(
      context,
    ).colorScheme.shadow.withValues(alpha: 0.22);

    // ממקם את פסי הגלילה בקצה החיצוני של הפאנל (הצמוד לדופן החלון) ולא בקצה
    // הפנימי, שם יושבת ידית הגרירה (ResizableDragHandle) וחוסמת את הלחיצה על
    // הפס. בצד ימין של המסך הקצה החיצוני הוא ימין, ולהיפך.
    final scrollbarWrapped = ScrollbarTheme(
      data: ScrollbarThemeData(
        crossAxisMargin: 2,
        mainAxisMargin: widget.scrollbarTopMargin ?? _kWideTopGap,
      ),
      child: ScrollConfiguration(
        behavior: _OuterEdgePaneScrollBehavior(
          paneOnRight ? ScrollbarOrientation.right : ScrollbarOrientation.left,
        ),
        child: child,
      ),
    );

    if (widget.wrapPaneInFloatingPanel) {
      return FloatingPanel(
        color: paneColor,
        elevation: 8,
        shadowColor: shadowColor,
        child: scrollbarWrapped,
      );
    }

    return Material(
      color: paneColor,
      elevation: 4,
      shadowColor: shadowColor,
      surfaceTintColor: Colors.transparent,
      borderRadius: AppTokens.borderRadiusAll,
      clipBehavior: Clip.hardEdge,
      child: scrollbarWrapped,
    );
  }

  void _onDragStart(bool currentlyWide) {
    if (_isDragging) return;
    setState(() {
      _dragStartedInWideMode = currentlyWide;
      _isDragging = true;
    });
  }

  void _onDragDelta(double delta, bool paneOnRight) {
    final effectiveDelta = paneOnRight ? -delta : delta;
    final nextWidth = (_livePaneWidth.value + effectiveDelta).clamp(
      widget.minPaneWidth,
      widget.maxPaneWidth ?? double.infinity,
    );
    _livePaneWidth.value = nextWidth;
    // מעדכן את ה-parent בזמן אמת (עבור מסכים שצריכים זאת), ללא setState
    widget.onPaneWidthChanged?.call(nextWidth);
  }

  void _onDragEnd() {
    widget.onPaneResizeEnd?.call();
    if (!mounted) return;
    setState(() {
      _isDragging = false;
      _dragStartedInWideMode = null;
    });
  }

  Widget _buildResizeHandle(bool paneOnRight, bool currentlyWide) {
    return ResizableDragHandle(
      isVertical: true,
      showDivider: false,
      gripOffset: paneHandleGripOffset(context, paneOnRight: paneOnRight),
      onDragStart: () => _onDragStart(currentlyWide),
      onDragDelta: (delta) => _onDragDelta(delta, paneOnRight),
      onDragEnd: _onDragEnd,
    );
  }

  /// ברירת מחדל ל-narrowPaneBuilder: SafeArea בלבד.
  /// הצבע והפינות המעוגלות מגיעים מ-_buildPaneShell שעוטף תמיד את התוצאה.
  /// מסכים שרוצים התנהגות שונה יכולים לעקוף דרך [narrowPaneBuilder].
  Widget _defaultNarrowPaneBuilder(BuildContext context, Widget paneContent) {
    return SafeArea(child: paneContent);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final paneOnRight = _isPaneOnRight(context);

        // _livePaneWidth הוא ה-source of truth לרוחב: מתעדכן בזמן גרירה,
        // ומסונכרן מ-widget.paneWidth ב-didUpdateWidget כשאין גרירה.
        final wideOccupiedWidth =
            _livePaneWidth.value + _kWideOuterSideGap + _kWideInnerSideGap;
        final calculatedHasRoomForSideBySide =
            constraints.maxWidth >=
            (wideOccupiedWidth + widget.minMainContentWidth);
        final hasRoomForSideBySide = _resolveHasRoomForSideBySide(
          calculatedHasRoomForSideBySide,
        );

        if (widget.autoHandleResponsiveVisibility && !_isDragging) {
          _handleResponsiveAutoClose(hasRoomForSideBySide);
        }
        // עדכון ה-snapshot גם כשלא גוררים
        if (!_isDragging) {
          _lastHadRoomForSideBySide = hasRoomForSideBySide;
        }

        if (widget.onLayoutModeChanged != null &&
            _lastReportedLayoutMode != hasRoomForSideBySide) {
          _lastReportedLayoutMode = hasRoomForSideBySide;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) widget.onLayoutModeChanged!(hasRoomForSideBySide);
          });
        }

        if (hasRoomForSideBySide) {
          return _buildWideLayout(
            context,
            paneOnRight: paneOnRight,
          );
        }

        return _buildNarrowLayout(
          context,
          paneOnRight: paneOnRight,
          maxWidth: constraints.maxWidth,
        );
      },
    );
  }

  Widget _buildWideLayout(
    BuildContext context, {
    required bool paneOnRight,
  }) {
    final showHandle =
        widget.isOpen &&
        widget.isResizable &&
        widget.onPaneWidthChanged != null;

    // כאן ה-Positioned נמדד מהקצה שמעבר לדופן הפנימית של הפאנל (בשונה מהפריסה
    // הצרה), ולכן המרחק הוא הגלישה החוצה ולא הכניסה פנימה.
    final outreach = showHandle ? handleHitOutreach(context) : 0.0;

    // ה-handle לא תלוי ברוחב — מוגדר מחוץ ל-ValueListenableBuilder
    final handleWidget = showHandle
        ? Positioned(
            top: _kWideTopGap,
            bottom: _kWideBottomGap,
            left: paneOnRight ? _kWideOuterSideGap - outreach : null,
            right: paneOnRight ? null : _kWideOuterSideGap - outreach,
            child: _buildResizeHandle(paneOnRight, true),
          )
        : null;

    // ה-slot של הפאנל עוטף ב-ValueListenableBuilder כדי לעדכן רק אותו בזמן גרירה
    final paneSlot = ValueListenableBuilder<double>(
      valueListenable: _livePaneWidth,
      builder: (context, liveWidth, child) {
        final currentWidth = liveWidth;
        final currentOccupied =
            currentWidth + _kWideOuterSideGap + _kWideInnerSideGap;
        // אופטימיזציית ביצועים: לא לבנות את תוכן הפאנל לפני שנפתח לראשונה.
        // לפני האופטימיזציה, paneContent (כולל TocViewer עם אלפי ערכים)
        // היה נבנה תמיד גם בפאנל סגור, מה שיצר frame של 12+ שניות.
        // אחרי הפתיחה הראשונה התוכן נשמר במגדל גם בסגירה כדי לשמור state.
        final Widget paneSlotContent;
        if (!_paneEverOpened) {
          paneSlotContent = const SizedBox.shrink();
        } else {
          final widePaneContent = widget.widePaneBuilder != null
              ? widget.widePaneBuilder!(
                  context,
                  widget.paneContent,
                  currentWidth,
                )
              : widget.paneContent;
          paneSlotContent = Padding(
            padding: EdgeInsetsDirectional.only(
              top: _kWideTopGap,
              bottom: _kWideBottomGap,
              start: paneOnRight ? _kWideInnerSideGap : _kWideOuterSideGap,
              end: paneOnRight ? _kWideOuterSideGap : _kWideInnerSideGap,
            ),
            child: SizedBox(
              width: currentWidth,
              child: SizedBox(
                width: currentWidth,
                child: _buildPaneShell(
                  context,
                  widePaneContent,
                  paneOnRight: paneOnRight,
                ),
              ),
            ),
          );
        }

        return Stack(
          clipBehavior: Clip.none,
          children: [
            AnimatedContainer(
              duration: _isDragging ? Duration.zero : AppTokens.animPanelSlide,
              curve: Curves.easeInOut,
              width: widget.isOpen ? currentOccupied : 0,
              child: ClipRect(
                child: Align(
                  alignment: paneOnRight
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: OverflowBox(
                    maxWidth: currentOccupied,
                    minWidth: 0,
                    alignment: paneOnRight
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: paneSlotContent,
                  ),
                ),
              ),
            ),
            ?handleWidget,
          ],
        );
      },
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: paneOnRight
          ? [paneSlot, Expanded(child: widget.mainContent)]
          : [Expanded(child: widget.mainContent), paneSlot],
    );
  }

  Widget _buildNarrowLayout(
    BuildContext context, {
    required bool paneOnRight,
    required double maxWidth,
  }) {
    // בחלון צר מצמצמים את רוחב הפאנל כדי להשאיר שוליים משני הצדדים
    final maxPaneWidth = (maxWidth - _kNarrowSideGap * 2).clamp(
      0.0,
      double.infinity,
    );
    // אופטימיזציית ביצועים: לא לבנות את תוכן הפאנל לפני שנפתח לראשונה.
    // אחרי הפתיחה הראשונה התוכן נשמר במגדל גם בסגירה כדי לשמור state.
    final Widget narrowPane = _paneEverOpened
        ? _buildPaneShell(
            context,
            (widget.narrowPaneBuilder ?? _defaultNarrowPaneBuilder).call(
              context,
              widget.paneContent,
            ),
            paneOnRight: paneOnRight,
          )
        : const SizedBox.shrink();

    final showHandle = widget.isResizable && widget.onPaneWidthChanged != null;
    final closedOffset = paneOnRight ? const Offset(1, 0) : const Offset(-1, 0);

    return Stack(
      children: [
        Positioned.fill(child: widget.mainContent),
        IgnorePointer(
          ignoring: !widget.isOpen,
          child: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  onTap: widget.onClose,
                  child: AnimatedOpacity(
                    duration: AppTokens.animPanelOpacity,
                    opacity: widget.isOpen ? 1.0 : 0.0,
                    child: ColoredBox(
                      color: Theme.of(
                        context,
                      ).colorScheme.scrim.withValues(alpha: 0.30),
                    ),
                  ),
                ),
              ),
              ValueListenableBuilder<double>(
                valueListenable: _livePaneWidth,
                builder: (context, liveWidth, _) {
                  final currentWidth = liveWidth > maxPaneWidth
                      ? maxPaneWidth
                      : liveWidth;
                  final overhang = showHandle ? kPaneHandleInnerReach : 0.0;

                  return Stack(
                    children: [
                      Positioned(
                        top: _kNarrowTopGap,
                        bottom: _kNarrowBottomGap,
                        right: paneOnRight ? _kNarrowSideGap : null,
                        left: paneOnRight ? null : _kNarrowSideGap,
                        width: currentWidth,
                        child: AnimatedOpacity(
                          duration: AppTokens.animPanelOpacity,
                          opacity: widget.isOpen ? 1.0 : 0.0,
                          child: AnimatedSlide(
                            duration: AppTokens.animPanelSlide,
                            curve: Curves.easeInOut,
                            offset: widget.isOpen ? Offset.zero : closedOffset,
                            child: narrowPane,
                          ),
                        ),
                      ),
                      if (showHandle)
                        Positioned(
                          top: _kNarrowTopGap,
                          bottom: _kNarrowBottomGap,
                          right: paneOnRight
                              ? _kNarrowSideGap + currentWidth - overhang
                              : null,
                          left: paneOnRight
                              ? null
                              : _kNarrowSideGap + currentWidth - overhang,
                          child: AnimatedOpacity(
                            duration: AppTokens.animPanelOpacity,
                            opacity: widget.isOpen ? 1.0 : 0.0,
                            child: AnimatedSlide(
                              duration: AppTokens.animPanelSlide,
                              curve: Curves.easeInOut,
                              offset: widget.isOpen
                                  ? Offset.zero
                                  : closedOffset,
                              child: _buildResizeHandle(paneOnRight, false),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// התנהגות גלילה המציבה את פס הגלילה האנכי בקצה הנבחר של הפאנל במקום בקצה
/// ה-trailing שנקבע אוטומטית לפי כיוון הטקסט. נחוץ כי ידית הגרירה לשינוי רוחב
/// הפאנל יושבת בקצה הפנימי וחוסמת את הלחיצה על פס שנמצא באותו צד.
///
/// משכפלת את לוגיקת [MaterialScrollBehavior] (פס אנכי בדסקטופ בלבד) ומוסיפה
/// רק את [scrollbarOrientation].
class _OuterEdgePaneScrollBehavior extends MaterialScrollBehavior {
  const _OuterEdgePaneScrollBehavior(this.orientation);

  final ScrollbarOrientation orientation;

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    if (axisDirectionToAxis(details.direction) != Axis.vertical) {
      return child;
    }
    switch (getPlatform(context)) {
      case TargetPlatform.linux:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
        return Scrollbar(
          controller: details.controller,
          scrollbarOrientation: orientation,
          child: child,
        );
      case TargetPlatform.android:
      case TargetPlatform.fuchsia:
      case TargetPlatform.iOS:
        return child;
    }
  }
}
