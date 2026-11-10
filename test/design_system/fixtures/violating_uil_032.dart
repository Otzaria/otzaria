import 'package:flutter/material.dart';

const Widget a = SelectableText('א'); // LINT
Widget b() => SelectableText.rich(const TextSpan(text: 'ב')); // LINT
Widget c(Widget child) => SelectionArea(child: child); // LINT
Widget d(Widget child, FocusNode focus) => /* LINT */ SelectableRegion(
  focusNode: focus,
  selectionControls: materialTextSelectionControls,
  child: Column(
    children: [
      child,
      SelectionArea(
        contextMenuBuilder: (context, state) => const SizedBox.shrink(),
        child: child,
      ),
    ],
  ),
);
