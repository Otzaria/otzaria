import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/feedback/edge_scrollbar_behavior.dart';
import 'package:otzaria/widgets/layout/floating_panel.dart';
import 'package:otzaria/widgets/layout/resizable_drag_handle.dart';

/// חלונית צד אדפטיבית:
/// במסך רחב דוחקת תוכן (או מרחפת מעליו — [floatOverContent]), ובמסך צר נפתחת כ-overlay.
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

  /// במצב רחב: מצמיד את החלונית לראש ולדופן החיצונית (ללא מרווח ופינה חיצונית
  /// עליונה מרובעת), כך שהיא נראית כהמשך של הסרגל העליון. שאר הפינות מעוגלות.
  final bool attachToTopEdge;

  /// במצב רחב: החלונית מרחפת מעל התוכן עם הצללה (לחיצה עליה סוגרת) במקום
  /// לדחוק אותו — כך פתיחה וסגירה אינן משנות את שבירת השורות.
  final bool floatOverContent;

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
    this.attachToTopEdge = false,
    this.floatOverContent = false,
  });

  @override
  State<AdaptiveSidePane> createState() => _AdaptiveSidePaneState();
}

class _AdaptiveSidePaneState extends State<AdaptiveSidePane> {
  bool? _lastHadRoomForSideBySide;
  bool? _lastReportedLayoutMode;
  bool _overlaysContent = false;

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

  // שלוש הפריסות בונות עצים שונים; המפתח מעביר את התוכן ביניהן בלי לבנות אותו
  // מחדש — אחרת נעיצה/ביטול נעיצה מאפסים את מיקום הקריאה.
  final GlobalKey _mainContentKey = GlobalKey();
  final GlobalKey _paneContentKey = GlobalKey();
  final FocusNode _paneFocusNode = FocusNode(
    canRequestFocus: false,
    skipTraversal: true,
  );

  /// תוכן החלונית עם מפתח קבוע — נעיצה מעבירה אותו בין הפריסות בלי לבנות מחדש
  /// (גלילה, ענפים פתוחים ושדה חיפוש פתוח נשמרים).
  Widget get _paneContent => KeyedSubtree(
    key: _paneContentKey,
    child: Focus(
      focusNode: _paneFocusNode,
      includeSemantics: false,
      child: widget.paneContent,
    ),
  );

  static const double _kWideTopGap = 14;
  static const double _kWideBottomGap = 10;
  static const double _kWideOuterSideGap = 10;
  static const double _kWideInnerSideGap = 12;

  // במצב הצמדה החלונית נצמדת לכל הקצוות (ראש, תחתית ודופן חיצונית) ללא
  // מרווחים — היא ממשיכה את הסרגל העליון ומגיעה עד קצוות החלון.
  double get _wideTopGap => widget.attachToTopEdge ? 0 : _kWideTopGap;
  double get _wideBottomGap => widget.attachToTopEdge ? 0 : _kWideBottomGap;
  double get _wideOuterSideGap =>
      widget.attachToTopEdge ? 0 : _kWideOuterSideGap;
  double get _wideInnerSideGap =>
      widget.attachToTopEdge ? 0 : _kWideInnerSideGap;
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
    _paneFocusNode.dispose();
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
    bool attached = false,
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
        behavior: EdgeScrollbarBehavior(
          paneOnRight ? ScrollbarOrientation.right : ScrollbarOrientation.left,
        ),
        child: child,
      ),
    );

    if (attached) {
      // מעטפת ריבועית צמודה לכל הקצוות; העיגול הקעור בפינה הפנימית-עליונה
      // מצויר בנפרד כטלאי (_buildTopCornerFillet) באזור התוכן.
      return Material(
        color: paneColor,
        elevation: 1,
        shadowColor: shadowColor,
        surfaceTintColor: Colors.transparent,
        child: scrollbarWrapped,
      );
    }

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

  // Esc מגיע לכאן רק אם אף צאצא ממוקד (שדה, בחירה) לא טיפל בו קודם.
  // החלונית הסגורה נשארת בעץ, ופוקוס שנשאר בה היה בולע הקלדה בשדה נסתר.
  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.escape ||
        !widget.isOpen ||
        !_overlaysContent) {
      return KeyEventResult.ignored;
    }
    if (_paneFocusNode.hasFocus) FocusManager.instance.primaryFocus?.unfocus();
    widget.onClose();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    // שני ה-Focus בקובץ בלי סמנטיקה: צומת עוטף שנוצר ומתמזג לפי התוכן מקריס
    // את גשר הנגישות של Windows ב-reparent מקונן (issue #3336).
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      includeSemantics: false,
      onKeyEvent: _handleKey,
      child: _buildLayout(context),
    );
  }

  Widget _buildLayout(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final paneOnRight = _isPaneOnRight(context);

        // _livePaneWidth הוא ה-source of truth לרוחב: מתעדכן בזמן גרירה,
        // ומסונכרן מ-widget.paneWidth ב-didUpdateWidget כשאין גרירה.
        final wideOccupiedWidth =
            _livePaneWidth.value + _wideOuterSideGap + _wideInnerSideGap;
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

        final usesPushLayout = hasRoomForSideBySide && !widget.floatOverContent;
        _overlaysContent = !usesPushLayout;
        if (widget.onLayoutModeChanged != null &&
            _lastReportedLayoutMode != usesPushLayout) {
          _lastReportedLayoutMode = usesPushLayout;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) widget.onLayoutModeChanged!(usesPushLayout);
          });
        }

        if (hasRoomForSideBySide && widget.floatOverContent) {
          return _buildFloatingWideLayout(
            context,
            paneOnRight: paneOnRight,
            areaWidth: constraints.maxWidth,
          );
        }

        if (hasRoomForSideBySide) {
          return _buildWideLayout(context, paneOnRight: paneOnRight);
        }

        return _buildNarrowLayout(
          context,
          paneOnRight: paneOnRight,
          maxWidth: constraints.maxWidth,
        );
      },
    );
  }

  Widget get _mainContent =>
      KeyedSubtree(key: _mainContentKey, child: widget.mainContent);

  Widget _buildWideLayout(BuildContext context, {required bool paneOnRight}) {
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
            top: _wideTopGap,
            bottom: _wideBottomGap,
            left: paneOnRight ? _wideOuterSideGap - outreach : null,
            right: paneOnRight ? null : _wideOuterSideGap - outreach,
            child: _buildResizeHandle(paneOnRight, true),
          )
        : null;

    // ה-slot של הפאנל עוטף ב-ValueListenableBuilder כדי לעדכן רק אותו בזמן גרירה
    final paneSlot = ValueListenableBuilder<double>(
      valueListenable: _livePaneWidth,
      builder: (context, liveWidth, child) {
        final currentWidth = liveWidth;
        final currentOccupied =
            currentWidth + _wideOuterSideGap + _wideInnerSideGap;
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
                  _paneContent,
                  currentWidth,
                )
              : _paneContent;
          paneSlotContent = Padding(
            padding: EdgeInsetsDirectional.only(
              top: _wideTopGap,
              bottom: _wideBottomGap,
              start: paneOnRight ? _wideInnerSideGap : _wideOuterSideGap,
              end: paneOnRight ? _wideOuterSideGap : _wideInnerSideGap,
            ),
            child: SizedBox(
              width: currentWidth,
              child: SizedBox(
                width: currentWidth,
                child: _buildPaneShell(
                  context,
                  widePaneContent,
                  paneOnRight: paneOnRight,
                  attached: widget.attachToTopEdge,
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

    final mainContent = _mainContent;
    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: paneOnRight
          ? [paneSlot, Expanded(child: mainContent)]
          : [Expanded(child: mainContent), paneSlot],
    );

    if (!widget.attachToTopEdge) return row;

    // במצב הצמדה מציירים עיגול קעור בפינה שבין החלונית לתוכן — טלאי בצבע
    // החלונית באזור התוכן, שמתעגל כלפי החלון הגדול.
    return Stack(
      children: [row, _buildTopCornerFillet(paneOnRight)],
    );
  }

  /// טלאי בצבע החלונית שנצמד לפינה הפנימית-עליונה (במפגש עם הסרגל) ומצייר שם
  /// עיגול קעור לעבר התוכן. מוצג רק כשהחלונית פתוחה.
  Widget _buildTopCornerFillet(bool paneOnRight) {
    return ValueListenableBuilder<double>(
      valueListenable: _livePaneWidth,
      builder: (context, liveWidth, _) {
        if (!widget.isOpen) return const SizedBox.shrink();
        final occupied = liveWidth + _wideOuterSideGap + _wideInnerSideGap;
        return Positioned(
          top: 0,
          right: paneOnRight ? occupied : null,
          left: paneOnRight ? null : occupied,
          width: AppTokens.radius,
          height: AppTokens.radius,
          child: CustomPaint(
            painter: _ConcaveCornerPainter(
              color: _effectivePaneColor(context),
              paneOnRight: paneOnRight,
            ),
          ),
        );
      },
    );
  }

  /// הצללה שמכסה את התוכן כשהחלונית פתוחה מעליו; לחיצה עליה סוגרת.
  Widget _buildScrim(BuildContext context) {
    return Positioned.fill(
      child: GestureDetector(
        onTap: widget.onClose,
        child: AnimatedOpacity(
          duration: AppTokens.animPanelOpacity,
          opacity: widget.isOpen ? 1.0 : 0.0,
          child: ColoredBox(
            color: Theme.of(context).colorScheme.scrim.withValues(alpha: 0.30),
          ),
        ),
      ),
    );
  }

  Widget _buildFloatingWideLayout(
    BuildContext context, {
    required bool paneOnRight,
    required double areaWidth,
  }) {
    final showHandle = widget.isResizable && widget.onPaneWidthChanged != null;
    final outreach = showHandle ? handleHitOutreach(context) : 0.0;
    final closedOffset = paneOnRight ? const Offset(1, 0) : const Offset(-1, 0);
    final pane = _paneEverOpened
        ? _buildPaneShell(
            context,
            _paneContent,
            paneOnRight: paneOnRight,
            attached: widget.attachToTopEdge,
          )
        : const SizedBox.shrink();

    // ClipRect: החלונית מחליקה מחוץ לאזור, ובתצוגה מפוצלת אסור לה לצוף מעל השכנה.
    return ClipRect(
      child: Stack(
        children: [
          Positioned.fill(child: _mainContent),
          IgnorePointer(
            ignoring: !widget.isOpen,
            child: Stack(
              children: [
                _buildScrim(context),
                ValueListenableBuilder<double>(
                  valueListenable: _livePaneWidth,
                  builder: (context, liveWidth, _) {
                    final width = liveWidth.clamp(0.0, areaWidth);
                    final slide = AnimatedSlide(
                      duration: AppTokens.animPanelSlide,
                      curve: Curves.easeInOut,
                      offset: widget.isOpen ? Offset.zero : closedOffset,
                      child: pane,
                    );
                    return Stack(
                      children: [
                        Positioned(
                          top: 0,
                          bottom: 0,
                          right: paneOnRight ? 0 : null,
                          left: paneOnRight ? null : 0,
                          width: width,
                          child: slide,
                        ),
                        if (showHandle && widget.isOpen)
                          Positioned(
                            top: 0,
                            bottom: 0,
                            left: paneOnRight
                                ? areaWidth - width - outreach
                                : null,
                            right: paneOnRight
                                ? null
                                : areaWidth - width - outreach,
                            child: _buildResizeHandle(paneOnRight, true),
                          ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
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
              _paneContent,
            ),
            paneOnRight: paneOnRight,
          )
        : const SizedBox.shrink();

    final showHandle = widget.isResizable && widget.onPaneWidthChanged != null;
    final closedOffset = paneOnRight ? const Offset(1, 0) : const Offset(-1, 0);

    return Stack(
      children: [
        Positioned.fill(child: _mainContent),
        IgnorePointer(
          ignoring: !widget.isOpen,
          child: Stack(
            children: [
              _buildScrim(context),
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

/// מצייר עיגול קעור (fillet) בפינה הפנימית-עליונה של החלונית: ריבוע בצבע
/// החלונית שממנו נגרעת רבע-עיגול בצד התוכן, כך שהמפגש מתעגל כלפי החלון הגדול.
class _ConcaveCornerPainter extends CustomPainter {
  final Color color;
  final bool paneOnRight;

  const _ConcaveCornerPainter({required this.color, required this.paneOnRight});

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width;
    // הפינה הפנימית של החלון (שממנה נגרע רבע-העיגול) הפוכה לצד החלונית.
    final carveCenter = paneOnRight ? Offset(0, r) : Offset(r, r);
    canvas.clipRect(Offset.zero & size);
    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Rect.fromLTWH(0, 0, r, r))
      ..addOval(Rect.fromCircle(center: carveCenter, radius: r));
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_ConcaveCornerPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.paneOnRight != paneOnRight;
}
