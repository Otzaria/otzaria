import 'package:flutter/material.dart';
import 'package:otzaria/widgets/layout/reader_side_panel_shell.dart';
import 'package:otzaria/widgets/layout/resizable_drag_handle.dart';

/// פריסת קריאה עם שתי חלוניות צד עצמאיות.
///
/// נועד למסכים כמו PDF שבהם יש גם חלונית ניווט וגם חלונית מפרשים/הערות,
/// בלי להשאיר את ניהול ה-layout מפוזר בתוך המסך עצמו.
class DualAdaptiveReaderPane extends StatelessWidget {
  final Widget mainContent;
  final bool showLeftPane;
  final Widget leftPaneContent;
  final double leftPaneWidth;
  final double leftMinPaneWidth;
  final double? leftMaxPaneWidth;
  final ValueChanged<double>? onLeftPaneWidthChanged;
  final VoidCallback onCloseLeftPane;
  final VoidCallback? onLeftPaneResizeEnd;
  final bool showRightPane;
  final Widget rightPaneContent;
  final double rightPaneWidth;
  final double rightMinPaneWidth;
  final double? rightMaxPaneWidth;
  final ValueChanged<double>? onRightPaneWidthChanged;
  final VoidCallback onCloseRightPane;
  final VoidCallback? onRightPaneResizeEnd;
  final double minMainContentWidth;

  const DualAdaptiveReaderPane({
    super.key,
    required this.mainContent,
    required this.showLeftPane,
    required this.leftPaneContent,
    required this.leftPaneWidth,
    required this.leftMinPaneWidth,
    this.leftMaxPaneWidth,
    this.onLeftPaneWidthChanged,
    required this.onCloseLeftPane,
    this.onLeftPaneResizeEnd,
    required this.showRightPane,
    required this.rightPaneContent,
    required this.rightPaneWidth,
    required this.rightMinPaneWidth,
    this.rightMaxPaneWidth,
    this.onRightPaneWidthChanged,
    required this.onCloseRightPane,
    this.onRightPaneResizeEnd,
    this.minMainContentWidth = 640,
  });

  bool _hasRoomForSideBySide(BoxConstraints constraints) {
    final requiredWidth = minMainContentWidth +
        (showLeftPane ? leftPaneWidth : 0) +
        (showRightPane ? rightPaneWidth : 0);
    return constraints.maxWidth >= requiredWidth;
  }

  Widget _buildOverlayPane({
    required BuildContext context,
    required bool isVisible,
    required bool isLeftPane,
    required double width,
    required Widget child,
  }) {
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    // In RTL the left pane is physically on the right (start), so it slides in
    // from the right. In LTR it slides in from the left.
    final hiddenOffset = isLeftPane
        ? (isRtl ? const Offset(1, 0) : const Offset(-1, 0))
        : (isRtl ? const Offset(-1, 0) : const Offset(1, 0));

    return PositionedDirectional(
      top: 0,
      bottom: 0,
      start: isLeftPane ? 0 : null,
      end: isLeftPane ? null : 0,
      width: width,
      child: IgnorePointer(
        ignoring: !isVisible,
        child: AnimatedSlide(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
          offset: isVisible ? Offset.zero : hiddenOffset,
          child: ReaderSidePanelShell(
            alignment: isLeftPane
                ? AlignmentDirectional.centerEnd
                : AlignmentDirectional.centerStart,
            child: child,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final hasRoomForSideBySide = _hasRoomForSideBySide(constraints);

        if (hasRoomForSideBySide) {
          return Row(
            children: [
              if (showLeftPane)
                SizedBox(
                  width: leftPaneWidth,
                  child: ReaderSidePanelShell(
                    alignment: AlignmentDirectional.centerEnd,
                    child: leftPaneContent,
                  ),
                ),
              if (showLeftPane)
                ResizableDragHandle(
                  isVertical: true,
                  hitSize: 4,
                  onDragDelta: onLeftPaneWidthChanged == null
                      ? null
                      : (delta) {
                          final nextWidth = (leftPaneWidth - delta).clamp(
                            leftMinPaneWidth,
                            leftMaxPaneWidth ?? double.infinity,
                          );
                          onLeftPaneWidthChanged!.call(nextWidth.toDouble());
                        },
                  onDragEnd: onLeftPaneResizeEnd,
                ),
              Expanded(child: mainContent),
              if (showRightPane)
                ResizableDragHandle(
                  isVertical: true,
                  hitSize: 4,
                  onDragDelta: onRightPaneWidthChanged == null
                      ? null
                      : (delta) {
                          final nextWidth = (rightPaneWidth + delta).clamp(
                            rightMinPaneWidth,
                            rightMaxPaneWidth ?? double.infinity,
                          );
                          onRightPaneWidthChanged!.call(nextWidth.toDouble());
                        },
                  onDragEnd: onRightPaneResizeEnd,
                ),
              if (showRightPane)
                SizedBox(
                  width: rightPaneWidth,
                  child: ReaderSidePanelShell(
                    alignment: AlignmentDirectional.centerStart,
                    child: rightPaneContent,
                  ),
                ),
            ],
          );
        }

        final showAnyPane = showLeftPane || showRightPane;

        return Stack(
          children: [
            Positioned.fill(child: mainContent),
            if (showAnyPane)
              Positioned.fill(
                child: GestureDetector(
                  onTap: () {
                    if (showRightPane) {
                      onCloseRightPane();
                    }
                    if (showLeftPane) {
                      onCloseLeftPane();
                    }
                  },
                  child: ColoredBox(
                    color: Theme.of(context)
                        .colorScheme
                        .scrim
                        .withValues(alpha: 0.30),
                  ),
                ),
              ),
            if (showLeftPane)
              _buildOverlayPane(
                context: context,
                isVisible: showLeftPane,
                isLeftPane: true,
                width: leftPaneWidth,
                child: leftPaneContent,
              ),
            if (showRightPane)
              _buildOverlayPane(
                context: context,
                isVisible: showRightPane,
                isLeftPane: false,
                width: rightPaneWidth,
                child: rightPaneContent,
              ),
          ],
        );
      },
    );
  }
}
