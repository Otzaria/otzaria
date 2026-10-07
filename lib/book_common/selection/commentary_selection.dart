import 'package:flutter/material.dart';
import 'package:otzaria/book_protection/models/book_protection.dart';
import 'package:otzaria/book_common/selection/selected_text_restore.dart';

/// Restores the line breaks of a multi-line selection that Flutter returns
/// flat, from the rendered title and text of each shown commentary item.
String? restoreCommentaryLineBreaks(
  String? flat, {
  required Iterable<String> orderedKeys,
  required Map<String, String> titlesByKey,
  required Map<String, String> textsByKey,
}) {
  if (flat == null || flat.isEmpty || flat.contains('\n')) return flat;
  final lines = <String>[];
  for (final key in orderedKeys) {
    final title = titlesByKey[key];
    if (title != null && title.isNotEmpty) lines.add(title);
    final content = textsByKey[key];
    if (content != null && content.isNotEmpty) lines.add(content);
  }
  if (lines.isEmpty) return flat;
  return restoreSelectedTextLineBreaks(
    selectedText: flat,
    visibleLines: lines,
  );
}

/// The global endpoints of the selection that holds [itemKeys], or null.
(Offset, Offset)? _selectionEndpoints(Map<String, GlobalKey> itemKeys) {
  SelectableRegionState? sa;
  for (final k in itemKeys.values) {
    sa = k.currentContext?.findAncestorStateOfType<SelectableRegionState>();
    if (sa != null) break;
  }
  final saRender = sa?.context.findRenderObject();
  if (saRender is! RenderBox) return null;
  final List<TextSelectionPoint> eps;
  try {
    eps = sa!.selectionEndpoints;
  } catch (_) {
    return null;
  }
  if (eps.length < 2) return null;
  return (
    saRender.localToGlobal(eps.first.point),
    saRender.localToGlobal(eps.last.point),
  );
}

Rect? _itemRect(GlobalKey key) {
  final box = key.currentContext?.findRenderObject();
  if (box is! RenderBox || !box.attached) return null;
  return box.localToGlobal(Offset.zero) & box.size;
}

/// Whether the selection ends fall in two different commentary items.
/// Such a selection gets no source title of a single item. Returns false
/// when the ends cannot be located.
bool selectionSpansMultipleItems(Map<String, GlobalKey> itemKeys) {
  final ends = _selectionEndpoints(itemKeys);
  if (ends == null) return false;
  String? k1;
  String? k2;
  for (final entry in itemKeys.entries) {
    final rect = _itemRect(entry.value);
    if (rect == null) continue;
    if (rect.contains(ends.$1)) k1 = entry.key;
    if (rect.contains(ends.$2)) k2 = entry.key;
  }
  return k1 != null && k2 != null && k1 != k2;
}

/// The keys of the items that lie between the selection ends (inclusive).
Set<String> selectedItemKeys(Map<String, GlobalKey> itemKeys) {
  final ends = _selectionEndpoints(itemKeys);
  if (ends == null) return const {};
  final top = ends.$1.dy < ends.$2.dy ? ends.$1.dy : ends.$2.dy;
  final bottom = ends.$1.dy < ends.$2.dy ? ends.$2.dy : ends.$1.dy;
  return {
    for (final entry in itemKeys.entries)
      if (_itemRect(entry.value) case final rect?
          when rect.bottom >= top && rect.top <= bottom)
        entry.key,
  };
}

/// הגבלת המו"ל ומספר הקטעים של בחירה בכמה מפרשים.
typedef CommentaryCopyGuard = ({BookProtection protection, int segmentCount});
