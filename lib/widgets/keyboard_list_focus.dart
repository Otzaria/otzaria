import 'package:flutter/material.dart';

/// עזר משותף לניווט focus ברשימות עם גלילה.
class KeyboardListFocusController {
  final ScrollController scrollController;
  final double estimatedItemExtent;
  int focusedIndex;

  KeyboardListFocusController({
    required this.scrollController,
    required this.estimatedItemExtent,
    this.focusedIndex = -1,
  });

  int moveFocus({
    required int delta,
    required int itemCount,
  }) {
    if (itemCount <= 0) return focusedIndex = -1;

    focusedIndex = (focusedIndex + delta).clamp(0, itemCount - 1);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!scrollController.hasClients) return;
      final offset = focusedIndex * estimatedItemExtent;
      scrollController.animateTo(
        offset.clamp(0.0, scrollController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
      );
    });

    return focusedIndex;
  }

  int reset({bool setToFirstWhenNotEmpty = false, int itemCount = 0}) {
    focusedIndex = setToFirstWhenNotEmpty && itemCount > 0 ? 0 : -1;
    return focusedIndex;
  }
}
