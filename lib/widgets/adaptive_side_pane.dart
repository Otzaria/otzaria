import 'package:flutter/material.dart';
import 'package:otzaria/theme/app_surfaces.dart';
import 'package:otzaria/widgets/floating_panel.dart';
import 'package:otzaria/widgets/resizable_drag_handle.dart';

/// חלונית צד אדפטיבית:
/// במסך רחב דוחקת תוכן, ובמסך צר נפתחת כ-overlay.
///
/// כללי ברירת מחדל:
/// - תוכן החלונית מקבל שכבת רקע נוספת של חלון (solidPanelBackground).
/// - מעבר מרוחב רחב למסך צר סוגר אוטומטית את החלונית.
/// - חלונית ניווט אמורה להיות בצד ימין (`centerEnd`) וחלונית מידע בצד שמאל (`centerStart`).
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
  final Widget Function(BuildContext context, Widget paneContent, double paneWidth)?
      widePaneBuilder;
  final Widget Function(BuildContext context, Widget paneContent)?
     narrowPaneBuilder;
  final bool autoHandleResponsiveVisibility;

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
    this.widePaneBuilder,
    this.narrowPaneBuilder,
    this.autoHandleResponsiveVisibility = true,
  });

  @override
  State<AdaptiveSidePane> createState() => _AdaptiveSidePaneState();
}

class _AdaptiveSidePaneState extends State<AdaptiveSidePane> {
  bool? _lastHadRoomForSideBySide;
  static const double _kWideTopGap = 14;
  static const double _kWideBottomGap = 10;
  static const double _kWideOuterSideGap = 10;
  static const double _kWideInnerSideGap = 12;
  static const double _kNarrowTopGap = 14;
  static const double _kNarrowBottomGap = 10;
  static const double _kNarrowHandleInset = 4;
  static const double _kHandleHitSize = 36;

  Color _effectivePaneColor(BuildContext context) {
    return widget.paneColor ?? AppSurfaces.solidPanelBackground(context);
  }

  bool _isPaneOnRight(BuildContext context) {
    if (widget.alignment == AlignmentDirectional.centerEnd) {
      return true;
    }
    if (widget.alignment == AlignmentDirectional.centerStart) {
      return false;
    }

    final resolved = widget.alignment.resolve(Directionality.of(context));
    return resolved.x >= 0;
  }

  void _handleResponsiveAutoClose(bool hasRoomForSideBySide) {
    final previous = _lastHadRoomForSideBySide;
    _lastHadRoomForSideBySide = hasRoomForSideBySide;

    if (previous == true && !hasRoomForSideBySide && widget.isOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.isOpen) {
          widget.onClose();
        }
      });
    }

    if (previous == false &&
        hasRoomForSideBySide &&
        !widget.isOpen &&
        widget.onOpen != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !widget.isOpen) {
          widget.onOpen!.call();
        }
      });
    }
  }

  Widget _buildPaneShell(
    BuildContext context,
    Widget child, {
    required bool paneOnRight,
    required bool isWide,
  }) {
    final paneColor = _effectivePaneColor(context);
    const shellRadius = BorderRadius.all(Radius.circular(18));
    final shadowColor =
        Theme.of(context).colorScheme.shadow.withValues(alpha: 0.22);

    final shell = widget.wrapPaneInFloatingPanel
        ? FloatingPanel(
            color: paneColor,
            elevation: 8,
            shadowColor: shadowColor,
            borderRadius: shellRadius,
            child: child,
          )
        : Material(
            color: paneColor,
            elevation: 4,
            shadowColor: shadowColor,
            surfaceTintColor: Colors.transparent,
            borderRadius: shellRadius,
            clipBehavior: Clip.antiAlias,
            child: child,
          );

    if (!widget.isResizable || widget.onPaneWidthChanged == null) {
      return shell;
    }

    final handleOffset = _kNarrowHandleInset;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(child: shell),
        Positioned(
          top: 0,
          bottom: 0,
          left: paneOnRight ? handleOffset : null,
          right: paneOnRight ? null : handleOffset,
          child: ResizableDragHandle(
            isVertical: true,
            hitSize: _kHandleHitSize,
            showDivider: false,
            onDragDelta: (delta) {
              final effectiveDelta = paneOnRight ? -delta : delta;
              final nextWidth = (widget.paneWidth + effectiveDelta).clamp(
                widget.minPaneWidth,
                widget.maxPaneWidth ?? double.infinity,
              );
              widget.onPaneWidthChanged?.call(nextWidth.toDouble());
            },
          ),
        ),
      ],
    );
  }

  Widget _buildNarrowPane(BuildContext context, Widget child) {
    return _buildPaneShell(
      context,
      widget.wrapPaneInFloatingPanel
          ? child
          : Material(
              color: _effectivePaneColor(context),
              child: child,
            ),
      paneOnRight: _isPaneOnRight(context),
      isWide: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final paneOnRight = _isPaneOnRight(context);
        final wideOccupiedWidth =
            widget.paneWidth + _kWideOuterSideGap + _kWideInnerSideGap;
        final hasRoomForSideBySide =
            constraints.maxWidth >= (wideOccupiedWidth + widget.minMainContentWidth);

        if (widget.autoHandleResponsiveVisibility) {
          _handleResponsiveAutoClose(hasRoomForSideBySide);
        }

        if (hasRoomForSideBySide) {
          final widePaneContent = widget.widePaneBuilder != null
              ? widget.widePaneBuilder!(context, widget.paneContent, widget.paneWidth)
              : widget.paneContent;

          final widePane = SizedBox(
            width: widget.paneWidth,
            child: _buildPaneShell(
              context,
              widePaneContent,
              paneOnRight: paneOnRight,
              isWide: true,
            ),
          );

          final paneSlot = AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            width: widget.isOpen ? wideOccupiedWidth : 0,
            child: ClipRect(
              child: Align(
                alignment:
                    paneOnRight ? Alignment.centerRight : Alignment.centerLeft,
                child: OverflowBox(
                  maxWidth: wideOccupiedWidth,
                  minWidth: 0,
                  alignment:
                      paneOnRight ? Alignment.centerRight : Alignment.centerLeft,
                  child: Padding(
                    padding: EdgeInsetsDirectional.only(
                      top: _kWideTopGap,
                      bottom: _kWideBottomGap,
                      start: paneOnRight
                          ? _kWideInnerSideGap
                          : _kWideOuterSideGap,
                      end: paneOnRight
                          ? _kWideOuterSideGap
                          : _kWideInnerSideGap,
                    ),
                    child: SizedBox(
                      width: widget.paneWidth,
                      child: widePane,
                    ),
                  ),
                ),
              ),
            ),
          );

          final children = paneOnRight
              ? <Widget>[
                  paneSlot,
                  Expanded(child: widget.mainContent),
                ]
              : <Widget>[
                  Expanded(child: widget.mainContent),
                  paneSlot,
                ];

          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          );
        }

        final narrowPaneContent = widget.narrowPaneBuilder != null
            ? widget.narrowPaneBuilder!(context, widget.paneContent)
            : _buildNarrowPane(context, SafeArea(child: widget.paneContent));
        final narrowPane = widget.narrowPaneBuilder != null
            ? _buildPaneShell(
                context,
                narrowPaneContent,
                paneOnRight: paneOnRight,
                isWide: false,
              )
            : narrowPaneContent;

        return Stack(
          children: [
            Positioned.fill(child: widget.mainContent),
            if (widget.isOpen)
              Positioned.fill(
                child: GestureDetector(
                  onTap: widget.onClose,
                  child: ColoredBox(
                    color: Theme.of(context).colorScheme.scrim.withValues(alpha: 0.30),
                  ),
                ),
              ),
            Positioned(
              top: _kNarrowTopGap,
              bottom: _kNarrowBottomGap,
              right: paneOnRight ? 0 : null,
              left: paneOnRight ? null : 0,
              width: widget.paneWidth,
              child: IgnorePointer(
                ignoring: !widget.isOpen,
                child: AnimatedSlide(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOut,
                  offset: widget.isOpen
                      ? Offset.zero
                      : (paneOnRight
                          ? const Offset(1, 0)
                          : const Offset(-1, 0)),
                  child: narrowPane,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
