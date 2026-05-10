import 'package:flutter/widgets.dart';
import 'package:otzaria/text_book/utils/reading_segments.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

Future<void> scrollToSourceLine({
  required ItemScrollController scrollController,
  required ScrollOffsetController? scrollOffsetController,
  required ItemPositionsListener? positionsListener,
  required List<ReadingSegment> segments,
  required int lineIndex,
  required double viewportExtent,
  double alignment = 0.05,
  Duration duration = const Duration(milliseconds: 250),
  Curve curve = Curves.ease,
}) async {
  if (segments.isEmpty || !scrollController.isAttached) {
    return;
  }

  final safeLineIndex = lineIndex
      .clamp(
        segments.first.startLineIndex,
        segments.last.sourceLineIndices.last,
      )
      .toInt();
  final segmentIndex = segmentIndexForLine(segments, safeLineIndex);
  if (duration == Duration.zero) {
    scrollController.jumpTo(
      index: segmentIndex,
      alignment: alignment,
    );
  } else {
    await scrollController.scrollTo(
      index: segmentIndex,
      alignment: alignment,
      duration: duration,
      curve: curve,
    );
  }

  final segment = segments[segmentIndex];
  final fraction = lineFractionWithinSegment(segment, safeLineIndex);
  if (fraction <= 0 ||
      scrollOffsetController == null ||
      positionsListener == null ||
      viewportExtent <= 0) {
    return;
  }

  await WidgetsBinding.instance.endOfFrame;

  ItemPosition? itemPosition;
  for (final position in positionsListener.itemPositions.value) {
    if (position.index == segmentIndex) {
      itemPosition = position;
      break;
    }
  }
  if (itemPosition == null) {
    return;
  }

  final itemExtent =
      (itemPosition.itemTrailingEdge - itemPosition.itemLeadingEdge) *
          viewportExtent;
  if (!itemExtent.isFinite || itemExtent <= 0) {
    return;
  }

  await scrollOffsetController.animateScroll(
    offset: itemExtent * fraction,
    duration: const Duration(milliseconds: 120),
    curve: Curves.easeOut,
  );
}
