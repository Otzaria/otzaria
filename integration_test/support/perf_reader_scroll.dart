import 'package:flutter/widgets.dart';

ScrollPosition perfReaderScrollPosition(ScrollController? controller) {
  if (controller == null || controller.positions.length != 1) {
    throw StateError(
      'The current reader must have one attached scroll position.',
    );
  }
  final position = controller.position;
  if (position.axis != Axis.vertical ||
      !position.hasContentDimensions ||
      position.maxScrollExtent <= 500) {
    throw StateError(
      'The current reader must be ready for vertical scrolling.',
    );
  }
  return position;
}
