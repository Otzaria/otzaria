import 'package:flutter/material.dart';
import 'package:otzaria/theme/theme_exports.dart';
import 'package:otzaria/widgets/layout/reader_side_panel_shell.dart';
import 'package:otzaria/widgets/layout/resizable_drag_handle.dart';

/// פריסת קריאה עם שתי חלוניות צד עצמאיות.
///
/// נועד למסכים כמו PDF שבהם יש גם חלונית ניווט וגם חלונית מפרשים/הערות,
/// בלי להשאיר את ניהול ה-layout מפוזר בתוך המסך עצמו.
///
/// במסך רחב כל חלונית דוחקת את התוכן ונפתחת/נסגרת באנימציית רוחב; במסך צר
/// היא נפתחת כ-overlay מעל התוכן. בשני המצבים המעבר מונפש.
class DualAdaptiveReaderPane extends StatefulWidget {
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

  @override
  State<DualAdaptiveReaderPane> createState() => _DualAdaptiveReaderPaneState();
}

class _DualAdaptiveReaderPaneState extends State<DualAdaptiveReaderPane> {
  // רוחב אזור הפגיעה של ידית הגרירה (ידית עדינה).
  static const double _kHandleHitSize = 4;

  // אופטימיזציית ביצועים: לא לבנות את תוכן החלונית לפני שנפתחה לראשונה.
  // אחרי הפתיחה הראשונה התוכן נשמר במגדל הוויידג'טים גם בסגירה — כך נשמר
  // ה-state, וגם אנימציית הסגירה מציגה את התוכן בזמן הכיווץ.
  bool _leftEverOpened = false;
  bool _rightEverOpened = false;

  @override
  void initState() {
    super.initState();
    _leftEverOpened = widget.showLeftPane;
    _rightEverOpened = widget.showRightPane;
  }

  @override
  void didUpdateWidget(DualAdaptiveReaderPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.showLeftPane && !_leftEverOpened) _leftEverOpened = true;
    if (widget.showRightPane && !_rightEverOpened) _rightEverOpened = true;
  }

  bool _hasRoomForSideBySide(BoxConstraints constraints) {
    final requiredWidth =
        widget.minMainContentWidth +
        (widget.showLeftPane ? widget.leftPaneWidth : 0) +
        (widget.showRightPane ? widget.rightPaneWidth : 0);
    return constraints.maxWidth >= requiredWidth;
  }

  ResizableDragHandle _buildHandle({required bool isLeft}) {
    final onChanged = isLeft
        ? widget.onLeftPaneWidthChanged
        : widget.onRightPaneWidthChanged;
    return ResizableDragHandle(
      isVertical: true,
      hitSize: _kHandleHitSize,
      showDivider: false,
      onDragDelta: onChanged == null
          ? null
          : (delta) {
              if (isLeft) {
                // החלונית בימין (RTL) — גרירה ימינה מקטינה אותה.
                final nextWidth = (widget.leftPaneWidth - delta).clamp(
                  widget.leftMinPaneWidth,
                  widget.leftMaxPaneWidth ?? double.infinity,
                );
                widget.onLeftPaneWidthChanged!.call(nextWidth.toDouble());
              } else {
                final nextWidth = (widget.rightPaneWidth + delta).clamp(
                  widget.rightMinPaneWidth,
                  widget.rightMaxPaneWidth ?? double.infinity,
                );
                widget.onRightPaneWidthChanged!.call(nextWidth.toDouble());
              }
            },
      onDragEnd: isLeft
          ? widget.onLeftPaneResizeEnd
          : widget.onRightPaneResizeEnd,
    );
  }

  /// סלוט חלונית במצב רחב: רוחב מונפש בין 0 לרוחב המלא. התוכן נשאר ברוחבו
  /// המלא ונחתך הדרגתית מהקצה הפנימי (ClipRect + OverflowBox), כך שהחלונית
  /// "נדחפת" פנימה מהקצה החיצוני ודוחקת את תוכן הקריאה.
  Widget _buildWidePaneSlot(BuildContext context, {required bool isLeft}) {
    final show = isLeft ? widget.showLeftPane : widget.showRightPane;
    final everOpened = isLeft ? _leftEverOpened : _rightEverOpened;
    final width = isLeft ? widget.leftPaneWidth : widget.rightPaneWidth;
    final occupied = width + _kHandleHitSize;

    final Widget content;
    if (!everOpened) {
      content = const SizedBox.shrink();
    } else {
      final shell = SizedBox(
        width: width,
        child: ReaderSidePanelShell(
          alignment: isLeft
              ? AlignmentDirectional.centerEnd
              : AlignmentDirectional.centerStart,
          child: isLeft ? widget.leftPaneContent : widget.rightPaneContent,
        ),
      );
      final handle = _buildHandle(isLeft: isLeft);
      content = SizedBox(
        width: occupied,
        // ידית הגרירה יושבת בקצה הפנימי (הצמוד לתוכן הקריאה).
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: isLeft ? [shell, handle] : [handle, shell],
        ),
      );
    }

    return AnimatedContainer(
      duration: AppTokens.animPanelSlide,
      curve: Curves.easeInOut,
      width: show ? occupied : 0,
      child: ClipRect(
        child: OverflowBox(
          minWidth: 0,
          maxWidth: occupied,
          alignment: isLeft
              ? AlignmentDirectional.centerStart
              : AlignmentDirectional.centerEnd,
          child: content,
        ),
      ),
    );
  }

  /// חלונית במצב צר: מרחפת מעל התוכן ומחליקה פנימה/החוצה. נשארת בעץ גם
  /// בסגירה (מותנה ב-everOpened) כדי שאנימציית ההחלקה תרוץ בכניסה וביציאה.
  Widget _buildOverlayPane(BuildContext context, {required bool isLeft}) {
    final show = isLeft ? widget.showLeftPane : widget.showRightPane;
    final everOpened = isLeft ? _leftEverOpened : _rightEverOpened;
    final width = isLeft ? widget.leftPaneWidth : widget.rightPaneWidth;
    // החלונית השמאלית מחליקה פנימה מימין (האפליקציה RTL), הימנית — משמאל.
    final hiddenOffset = isLeft ? const Offset(1, 0) : const Offset(-1, 0);

    return PositionedDirectional(
      top: 0,
      bottom: 0,
      start: isLeft ? 0 : null,
      end: isLeft ? null : 0,
      width: width,
      child: IgnorePointer(
        ignoring: !show,
        child: AnimatedSlide(
          duration: AppTokens.animPanelSlide,
          curve: Curves.easeInOut,
          offset: show ? Offset.zero : hiddenOffset,
          child: everOpened
              ? ReaderSidePanelShell(
                  alignment: isLeft
                      ? AlignmentDirectional.centerEnd
                      : AlignmentDirectional.centerStart,
                  child: isLeft
                      ? widget.leftPaneContent
                      : widget.rightPaneContent,
                )
              : const SizedBox.shrink(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (_hasRoomForSideBySide(constraints)) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildWidePaneSlot(context, isLeft: true),
              Expanded(child: widget.mainContent),
              _buildWidePaneSlot(context, isLeft: false),
            ],
          );
        }

        final showAnyPane = widget.showLeftPane || widget.showRightPane;

        return Stack(
          children: [
            Positioned.fill(child: widget.mainContent),
            Positioned.fill(
              child: IgnorePointer(
                ignoring: !showAnyPane,
                child: GestureDetector(
                  onTap: () {
                    if (widget.showRightPane) widget.onCloseRightPane();
                    if (widget.showLeftPane) widget.onCloseLeftPane();
                  },
                  child: AnimatedOpacity(
                    duration: AppTokens.animPanelOpacity,
                    opacity: showAnyPane ? 1.0 : 0.0,
                    child: ColoredBox(
                      color: Theme.of(
                        context,
                      ).colorScheme.scrim.withValues(alpha: 0.30),
                    ),
                  ),
                ),
              ),
            ),
            _buildOverlayPane(context, isLeft: true),
            _buildOverlayPane(context, isLeft: false),
          ],
        );
      },
    );
  }
}
