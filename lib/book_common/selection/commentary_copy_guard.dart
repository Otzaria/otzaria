import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:otzaria/book_common/selection/commentary_selection.dart';
import 'package:otzaria/book_common/selection/selected_text_restore.dart';
import 'package:otzaria/book_protection/models/book_protection.dart';
import 'package:otzaria/book_protection/repository/book_protection_repository.dart';
import 'package:otzaria/data/data_providers/file_system_data_provider.dart';
import 'package:otzaria/data/repository/text_book_repository.dart';
import 'package:otzaria/models/books.dart';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/utils/text/text_manipulation.dart'
    show getTitleFromPath;
import 'package:otzaria/widgets/smart_text/render_settings.dart';

/// הבחירה בגוף מפרש, באופסטים של הטקסט המרונדר ללא כותרות הפריט.
typedef CommentarySourceSelection = ({String text, int start, int end});

/// עוקב אחרי בחירת הגוף בלבד, גם כשאזור הבחירה חוצה כמה מפרשים.
class CommentarySelectionTracker extends StatefulWidget {
  const CommentarySelectionTracker({super.key, required this.child});
  final Widget child;

  static CommentarySourceSelection? selectionIn(GlobalKey key) {
    CommentarySourceSelection? selection;
    void visit(Element element) {
      if (element is StatefulElement &&
          element.state is _CommentarySelectionTrackerState) {
        selection =
            (element.state as _CommentarySelectionTrackerState).snapshot;
      } else {
        element.visitChildren(visit);
      }
    }

    final context = key.currentContext;
    if (context is Element) visit(context);
    return selection;
  }

  @override
  State<CommentarySelectionTracker> createState() =>
      _CommentarySelectionTrackerState();
}

class _CommentarySelectionTrackerState
    extends State<CommentarySelectionTracker> {
  final _notifier = SelectionListenerNotifier();

  CommentarySourceSelection? get snapshot {
    final range = _notifier.registered ? _notifier.selection.range : null;
    if (range == null || range.startOffset == range.endOffset) return null;
    final text = StringBuffer();
    void visit(RenderObject object) {
      if (object is RenderParagraph && object.registrar != null) {
        text.write(object.text.toPlainText(includeSemanticsLabels: false));
      }
      object.visitChildren(visit);
    }

    final root = context.findRenderObject();
    if (root == null) return null;
    visit(root);
    return (
      text: text.toString(),
      start: range.startOffset,
      end: range.endOffset,
    );
  }

  // בלי SelectionArea מעל אין מה לעקוב, ומיכל בחירה יתום משנה את רינדור הטקסט.
  @override
  Widget build(BuildContext context) =>
      SelectionContainer.maybeOf(context) == null
      ? widget.child
      : SelectionListener(selectionNotifier: _notifier, child: widget.child);

  @override
  void dispose() {
    _notifier.dispose();
    super.dispose();
  }
}

String _compact(String text) => text.replaceAll(RegExp(r'\s+'), '');

/// קטעי המקור שנבחרו בפועל; אי-התאמה מחמירה לטווח המקור המלא.
Set<int> selectedCommentarySourceSegments(
  Link link,
  CommentarySourceSelection selection,
  List<String> renderedSourceLines,
) {
  final last = link.index2End ?? link.index2;
  Set<int> all() => {for (var i = link.index2; i <= last; i++) i};
  final compact = _compact(selection.text);
  final source = renderedSourceLines.map(_compact).toList();
  if (source.length != last - link.index2 + 1 || source.join() != compact) {
    return all();
  }
  final firstOffset = selection.start < selection.end
      ? selection.start
      : selection.end;
  final lastOffset = selection.start > selection.end
      ? selection.start
      : selection.end;
  if (firstOffset < 0 || lastOffset > selection.text.length) return all();
  final start = _compact(selection.text.substring(0, firstOffset)).length;
  final end = _compact(selection.text.substring(0, lastOffset)).length;
  final segments = <int>{};
  var offset = 0;
  for (var i = 0; i < source.length; i++) {
    final next = offset + source[i].length;
    if (offset < end && next > start) segments.add(link.index2 + i);
    offset = next;
  }
  return segments;
}

Future<List<String>> _readSourceLines(Link link) async {
  final range =
      await TextBookRepository(
        fileSystem: FileSystemData.instance,
      ).getBookContentRange(
        TextBook(
          id: link.targetBookId,
          title: getTitleFromPath(link.path2),
          categoryId: link.targetCategoryId,
          fileType: link.targetFileType,
          source: link.targetSource,
        ),
        startLine: link.index2 - 1,
        endLine: link.index2End ?? link.index2,
      );
  return range?.lines ?? const [];
}

/// סופר רק קטעים נבחרים, בנפרד לכל ספר מוגן ובמסד שלו.
Future<CommentaryCopyGuard> buildCommentaryCopyGuard(
  Iterable<Link> links, {
  required CommentarySourceSelection? Function(Link) selectionOf,
  required RenderSettings renderSettings,
  bool selectAll = false,
  Future<BookProtection> Function(Link)? protectionResolver,
  Future<List<String>> Function(Link)? sourceResolver,
}) async {
  final protectionOf =
      protectionResolver ?? BookProtectionRepository.instance.forLink;
  final read = sourceResolver ?? _readSourceLines;
  final protectionByBook = <String, BookProtection>{};
  final segmentsByBook = <String, Set<int>>{};
  for (final link in links) {
    final selection = selectAll ? null : selectionOf(link);
    if (!selectAll && selection == null) continue;
    final key = link.targetIdentityKey;
    final protection = protectionByBook[key] ??= await protectionOf(link);
    if (!protection.isProtected) continue;
    final last = link.index2End ?? link.index2;
    var selected = {for (var i = link.index2; i <= last; i++) i};
    final fullBody =
        selection != null &&
        ((selection.start == 0 && selection.end == selection.text.length) ||
            (selection.end == 0 && selection.start == selection.text.length));
    if (!selectAll && !fullBody && last != link.index2) {
      try {
        selected = selectedCommentarySourceSegments(
          link,
          selection!,
          (await read(link))
              .map(
                (raw) => renderSelectionLine(
                  rawText: raw,
                  settings: renderSettings,
                ),
              )
              .toList(),
        );
      } catch (error) {
        debugPrint(
          'Commentary selection source read failed (${link.path2}): $error',
        );
      }
    }
    (segmentsByBook[key] ??= {}).addAll(selected);
  }
  var strictest = BookProtection.none;
  var largestCount = 0;
  for (final entry in segmentsByBook.entries) {
    strictest = strictest.strictest(protectionByBook[entry.key]!);
    if (entry.value.length > largestCount) largestCount = entry.value.length;
  }
  return (protection: strictest, segmentCount: largestCount);
}
