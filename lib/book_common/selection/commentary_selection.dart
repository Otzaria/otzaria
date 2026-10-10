import 'package:flutter/material.dart';
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

/// Whether the selection ends fall in two different commentary items.
/// Such a selection gets no source title of a single item. Returns false
/// when the ends cannot be located.
bool selectionSpansMultipleItems(Map<String, GlobalKey> itemKeys) {
  SelectableRegionState? sa;
  for (final k in itemKeys.values) {
    sa = k.currentContext?.findAncestorStateOfType<SelectableRegionState>();
    if (sa != null) break;
  }
  final saRender = sa?.context.findRenderObject();
  if (saRender is! RenderBox) return false;
  final List<TextSelectionPoint> eps;
  try {
    eps = sa!.selectionEndpoints;
  } catch (_) {
    return false;
  }
  if (eps.length < 2) return false;
  final p1 = saRender.localToGlobal(eps.first.point);
  final p2 = saRender.localToGlobal(eps.last.point);
  String? k1;
  String? k2;
  for (final entry in itemKeys.entries) {
    final box = entry.value.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached) continue;
    final rect = box.localToGlobal(Offset.zero) & box.size;
    if (rect.contains(p1)) k1 = entry.key;
    if (rect.contains(p2)) k2 = entry.key;
  }
  return k1 != null && k2 != null && k1 != k2;
}
