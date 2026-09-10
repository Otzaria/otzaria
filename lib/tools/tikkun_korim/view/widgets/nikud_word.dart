/// מילה בטור המנוקד: אותיות, ניקוד וטעמים בגופן המנוקד, עם סימוני זעירא/רבתי.
library;

import 'package:flutter/material.dart';
import 'package:otzaria/tools/tikkun_korim/view/widgets/stam_word.dart';

/// עובי המשיחה (בפיקסלים לוגיים) שמעבה את הגופן המנוקד, כולל הניקוד והטעמים.
const double kTikkunNikudStrokeWidth = 0.10;

class NikudWord extends StatelessWidget {
  final String text;
  final TextStyle style;

  const NikudWord({super.key, required this.text, required this.style});

  @override
  Widget build(BuildContext context) => tikkunStrokedText(
    context: context,
    style: style,
    strokeWidth: kTikkunNikudStrokeWidth,
    builder: (style) => tikkunWordText(text, style),
  );
}
