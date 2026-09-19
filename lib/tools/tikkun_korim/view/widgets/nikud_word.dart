/// מילה בטור המנוקד: אותיות, ניקוד וטעמים בגופן המנוקד, עם סימוני זעירא/רבתי.
library;

import 'package:flutter/material.dart';
import 'package:otzaria/tools/tikkun_korim/view/widgets/stam_word.dart';

class NikudWord extends StatelessWidget {
  final String text;
  final TextStyle style;

  /// כיווץ אופקי (עד 1) — שורה שאינה נכנסת לרוחב הטור.
  final double condense;

  const NikudWord({
    super.key,
    required this.text,
    required this.style,
    this.condense = 1,
  });

  @override
  Widget build(BuildContext context) =>
      tikkunWordText(text, style, condense: condense);
}
