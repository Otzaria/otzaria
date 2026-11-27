import 'package:flutter/material.dart';
import 'package:otzaria/book_common/view/book_source_dialog.dart'
    show splitShortAndFullDescription;
import 'package:otzaria/library/models/library.dart';
import 'package:otzaria/theme/app_tokens.dart';

/// מחלק את תיאור הקטגוריה לקצר ([lead]) ולארוך ([paragraphs], פסקה לכל שורה).
///
/// ארוך שפותח בקצר מוצג בלי הקצר שבראשו, וארוך הזהה לקצר אינו חוזר.
@visibleForTesting
({String lead, List<String> paragraphs}) categoryDescriptionParts(
  Category category,
) {
  final lead = category.shortDescription.trim();
  final full = category.description.trim();
  final split = splitShortAndFullDescription(lead, full);
  final rest = split?.rest ?? (full == lead ? '' : full);
  final paragraphs = rest
      .split('\n')
      .map((paragraph) => paragraph.trim())
      .where((paragraph) => paragraph.isNotEmpty)
      .toList();
  return (lead: lead, paragraphs: paragraphs);
}

/// האם לקטגוריה יש תיאור כלשהו להצגה.
bool categoryHasDescription(Category category) {
  final parts = categoryDescriptionParts(category);
  return parts.lead.isNotEmpty || parts.paragraphs.isNotEmpty;
}

final _bracketed = RegExp(r'\([^()]*\)|\[[^\[\]]*\]');

/// מפרק טקסט לקטעים: סוגריים עגולות מוקטנות משמעותית ובלי הדגשה, ומרובעות
/// מוקטנות מעט. [fontSize] הוא גודל הטקסט שסביבן.
@visibleForTesting
List<TextSpan> shelfDescriptionSpans(String text, double fontSize) {
  final spans = <TextSpan>[];
  var from = 0;
  for (final match in _bracketed.allMatches(text)) {
    if (match.start > from) {
      spans.add(TextSpan(text: text.substring(from, match.start)));
    }
    final round = text.startsWith('(', match.start);
    spans.add(
      TextSpan(
        text: match.group(0),
        style: round
            ? TextStyle(fontSize: fontSize * 0.76, fontWeight: FontWeight.w400)
            : TextStyle(fontSize: fontSize * 0.92),
      ),
    );
    from = match.end;
  }
  if (from < text.length) spans.add(TextSpan(text: text.substring(from)));
  return spans;
}

/// תיאור קטגוריה ברצף: פסקה לקצר (מודגש), ואחריה פסקה לכל שורה בארוך.
class ShelfDescription extends StatelessWidget {
  const ShelfDescription({
    super.key,
    required this.category,
    this.fontSize = AppTokens.fontMD,
  });

  final Category category;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final parts = categoryDescriptionParts(category);
    final color = Theme.of(context).colorScheme.onSurface;

    Widget paragraph(String text, {bool bold = false}) => Text.rich(
      TextSpan(
        style: TextStyle(
          fontSize: fontSize,
          height: 1.4,
          color: color,
          fontWeight: bold ? FontWeight.bold : null,
        ),
        children: shelfDescriptionSpans(text, fontSize),
      ),
    );

    final paragraphs = <Widget>[
      if (parts.lead.isNotEmpty) paragraph(parts.lead, bold: true),
      for (final text in parts.paragraphs) paragraph(text),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < paragraphs.length; i++) ...[
          if (i > 0) const SizedBox(height: AppTokens.spaceSM),
          paragraphs[i],
        ],
      ],
    );
  }
}
