import 'package:flutter/material.dart';
import 'package:otzaria_icons/otzaria_icons.dart';
import 'package:otzaria/widgets/text/otzaria_search_field.dart';

/// מתג "מילים שלמות בלבד" של החיפוש בתוך ספר, בשדה החיפוש עצמו.
/// משותף לחיפוש בספר טקסט ובספר PDF כדי שהאייקון והתווית לא יסטו.
Widget wholeWordSearchAction({
  required BuildContext context,
  required bool wholeWord,
  required VoidCallback onToggle,
}) {
  return OtzariaSearchAction.icon(
    // אל"ף שלמה = מילה שלמה; אל"ף שחציה מלא = התאמה גם בתוך מילה.
    iconData: wholeWord
        ? OtzariaIcons.alef_24_regular
        : OtzariaIcons.alef_mix_24_regular,
    onPressed: onToggle,
    tooltip: wholeWord
        ? 'מחפש מילים שלמות בלבד'
        : 'מחפש גם חלק ממילה — לחץ למילים שלמות',
    color: wholeWord ? Theme.of(context).colorScheme.primary : null,
  );
}
