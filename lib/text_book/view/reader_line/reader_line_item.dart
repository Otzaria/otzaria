/// פריט קריאה של כמה שורות, משותף למסך העיון ולצורת הדף: בניית החלקים,
/// זיהוי השורה שתחת הסמן וטיפול בקישורים בתוך פסקה ממוזגת.
library;

import 'package:flutter/material.dart';
import 'package:otzaria/tabs/models/tab.dart';
import 'package:otzaria/text_book/utils/link_preview_utils.dart';
import 'package:otzaria/text_book/view/reader_line/reader_line_render.dart';
import 'package:otzaria/text_book/view/reader_line/reader_line_spec.dart';
import 'package:otzaria/text_book/view/widgets/continuous_reading_paragraph.dart';
import 'package:otzaria/utils/text/html_link_handler.dart';
import 'package:otzaria/widgets/misc/inline_link_targets.dart';

/// השורה שתחת [globalPosition] בפריט; בפריט של שורה אחת — null.
ReaderLineHit? readerItemHit(
  BuildContext itemContext,
  Offset globalPosition, {
  required bool isMultiLine,
}) {
  if (!isMultiLine) return null;
  final root = itemContext.findRenderObject();
  return root == null ? null : readerLineAt(root, globalPosition);
}

/// השורה שבה התחילה הלחיצה בפריט. בפריט רב-שורתי null כשהלחיצה מחוץ
/// לשורות (למשל בכרטיס המפרשים).
int? readerItemPointerLine({
  required int? pointerLine,
  required bool Function(int line) inItem,
  required bool isMultiLine,
  required int primaryLine,
}) {
  if (pointerLine != null && inItem(pointerLine)) return pointerLine;
  return isMultiLine ? null : primaryLine;
}

/// קישור שנלחץ בתוך פסקה ממוזגת; מה שתלוי במסך מגיע בפרמטרים.
Future<bool> handleReaderParagraphUrl(
  BuildContext context,
  String url, {
  required void Function(String url, Offset globalPosition) onTouchPreview,
  required bool Function(String url) onAnchorTap,
  required void Function(int line) onNoteTap,
  required void Function(OpenedTab tab) openBook,
}) async {
  final touchPosition = touchLinkTapPosition();
  if (touchPosition != null && isTouchPreviewUrl(url)) {
    onTouchPreview(url, touchPosition);
    return true;
  }
  if (url.startsWith('otzaria://anchor')) return onAnchorTap(url);
  if (url.startsWith('otzaria://book-note')) return true;
  if (url.startsWith('otzaria://note-marker')) return true;
  if (url.startsWith('otzaria://note')) {
    final line = int.tryParse(
      Uri.tryParse(url)?.queryParameters['line'] ?? '',
    );
    if (line != null) onNoteTap(line);
    return true;
  }
  if (!context.mounted) return false;
  return HtmlLinkHandler.handleLink(context, url, openBook);
}

/// תוכן פריט של כמה שורות: פסקאות ממוזגות ושורות-בלוק לפי הסדר.
/// [splitAfter] — שורה שאחריה הפסקה נחתכת ו-[belowSplit] מוצג (כרטיס המפרשים).
Widget buildReaderMultiLineItem(
  BuildContext context, {
  required List<int> itemLines,
  required ReaderLineContext lineContext,
  required Widget Function(ReaderLineSpec spec) blockText,
  required ContinuousReadingUrlTap onTapUrl,
  required ContinuousReadingAnchorHover onAnchorHover,
  required ContinuousReadingAnchorExit onAnchorExit,
  Widget Function(List<String> headings)? blockHeadings,
  int? splitAfter,
  Widget Function(int line)? belowSplit,
  bool linesAsBlocks = false,
}) {
  final specs = <int, ReaderLineSpec>{
    for (final line in itemLines)
      if (line >= 0 && line < lineContext.lines.length)
        line: buildReaderLineSpec(line, lineContext),
  };
  final theme = Theme.of(context);
  final children = <Widget>[];
  for (final part in readerItemParts(
    specs.keys.toList(),
    (line) => linesAsBlocks || specs[line]!.isBlock,
    splitAfter: splitAfter,
  )) {
    if (part.isBlock) {
      final spec = specs[part.lines.single]!;
      final headings = spec.sectionHeadings;
      if (headings != null && blockHeadings != null) {
        children.add(blockHeadings(headings));
      }
      children.add(
        ReaderLineBlock(
          lineIndex: spec.lineIndex,
          selected: spec.marks.isSelected,
          child: ColoredBox(
            color:
                readerLineBackgroundColor(spec.marks.background, theme) ??
                Colors.transparent,
            child: blockText(spec),
          ),
        ),
      );
    } else {
      children.add(
        ReaderParagraphRun(
          specs: [for (final line in part.lines) specs[line]!],
          lineContext: lineContext,
          onTapUrl: onTapUrl,
          onMiddleClickUrl: (url) =>
              HtmlLinkHandler.openLinkInBackground(context, url),
          onAnchorHover: onAnchorHover,
          onAnchorExit: onAnchorExit,
        ),
      );
    }
    if (belowSplit != null && part.lines.last == splitAfter) {
      children.add(belowSplit(splitAfter!));
    }
  }
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: children,
  );
}
