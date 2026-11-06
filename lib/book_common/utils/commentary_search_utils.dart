import 'package:flutter/rendering.dart';
import 'package:otzaria/search/utils/snippet_builder.dart';
import 'package:otzaria/text_display/models/text_display_profile.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as utils;
import 'package:otzaria/widgets/smart_text/text_renderer_service.dart';
import 'package:otzaria/widgets/smart_text/long_line_chunks.dart';
import 'package:positioned_sliver_list/positioned_list.dart'
    show TargetRectResolver;

/// ספירת התאמות חיפוש בתוכן מפרש.
///
/// הספירה תמיד על טקסט ללא ניקוד — תואמת את ה-regex הגמיש לניקוד של ההדגשה.
/// [partialWordMatch] חייב לשקף את `partialWordHighlight` שאיתו התוכן
/// מרונדר — אחרת המונה קטן ממספר ההדגשות שנראות בפועל (issue #1055).
int countCommentarySearchMatches({
  required String content,
  required String query,
  required TextDisplayProfile displayProfile,
  required bool partialWordMatch,
}) {
  return TextRendererService.countSearchMatches(
    _searchableText(content, displayProfile),
    query,
    partialWordMatch: partialWordMatch,
    punctuationHidden: displayProfile.removePunctuation,
  );
}

/// מכוון לתוצאה בגוף המפרש המרונדר; בלי מיפוי אמין נשארים בראש הפריט.
TargetRectResolver? commentarySearchMatchTarget({
  required String? content,
  required String query,
  required TextDisplayProfile displayProfile,
  required int matchIndex,
  RenderObject? Function()? renderedBody,
}) {
  if (content == null || matchIndex < 0) return null;
  final count = countCommentarySearchMatches(
    content: content,
    query: query,
    displayProfile: displayProfile,
    partialWordMatch: true,
  );
  if (matchIndex >= count) return null;
  return (_, box) {
    final root = renderedBody == null ? box : renderedBody();
    if (root == null) return null;
    final paragraphs = <RenderParagraph>[];
    void collect(RenderObject child) {
      if (child is RenderParagraph) {
        paragraphs.add(child);
      } else {
        child.visitChildren(collect);
      }
    }

    collect(root);
    final text = StringBuffer();
    final starts = <int>[];
    final lengths = <int>[];
    for (final paragraph in paragraphs) {
      // מקטעי שורה רצופים כבר מכילים את הרווח המקורי; בלוקים נפרדים דורשים גבול.
      if (text.isNotEmpty && (longLineChunkOf(paragraph)?.start ?? 0) == 0) {
        text.writeln();
      }
      starts.add(text.length);
      final plain = paragraph.text.toPlainText(includeSemanticsLabels: false);
      lengths.add(plain.length);
      text.write(plain);
    }
    final rendered = text.toString();
    final match = utils.searchMatchRangeAt(
      rendered,
      query,
      matchIndex,
      partialWordMatch: true,
      punctuationHidden: displayProfile.removePunctuation,
    );
    // תוכן מוסתר או WidgetSpan עשויים לשנות את הספירה; אין לנחש אז מיקום.
    if (match == null || match.totalCount != count) return null;
    for (var i = 0; i < paragraphs.length; i++) {
      final localStart = (match.start - starts[i]).clamp(0, lengths[i]);
      final localEnd = (match.end - starts[i]).clamp(0, lengths[i]);
      if (localStart >= localEnd) continue;
      final boxes = paragraphs[i].getBoxesForSelection(
        TextSelection(baseOffset: localStart, extentOffset: localEnd),
      );
      if (boxes.isEmpty) continue;
      final top = MatrixUtils.transformPoint(
        paragraphs[i].getTransformTo(box),
        boxes.first.toRect().topLeft,
      ).dy;
      return Rect.fromLTWH(0, top, 0, 0);
    }
    return null;
  };
}

String _searchableText(String content, TextDisplayProfile displayProfile) {
  final text = utils.removeVolwels(content);
  return displayProfile.removePunctuation
      ? utils.removePunctuation(text)
      : text;
}

/// קטע תצוגה סביב ההתאמה בתוכן מפרש, משמר את פרופיל התצוגה של המפרשים.
String buildCommentarySearchSnippet({
  required String content,
  required String query,
  required TextDisplayProfile displayProfile,
}) {
  var text = utils.removeMarks(
    content,
    nikud: displayProfile.removeNikud,
    teamim: displayProfile.removeTeamim,
  );
  if (displayProfile.removePunctuation) {
    text = utils.removePunctuation(text);
  }
  return SnippetBuilder.buildExcerptText(
    fullText: utils.stripHtmlIfNeeded(text),
    query: query,
    maxChars: 220,
  );
}

/// מייצג תוצאת חיפוש בודדת עם קטע טקסט וכתובת גלובלית לניווט.
///
/// חי כאן ולא בווידג'ט כדי ששני משטחי המפרשים (טקסט ו-PDF) יוכלו לדווח
/// ולצרוך את אותו טיפוס בלי לייבא זה את הווידג'ט של זה.
class CommentarySearchSnippet {
  final String path;
  final String snippet;
  final int globalIndex;

  const CommentarySearchSnippet({
    required this.path,
    required this.snippet,
    required this.globalIndex,
  });
}
