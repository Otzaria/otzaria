import 'dart:math';

import 'package:pdfrx/pdfrx.dart';

typedef _OutlineEntry = ({int page, int? parent, PdfOutlineNode node});

/// אינדקס למציאת הנתיב הפעיל בעץ סימניות PDF לפי מספר עמוד.
class PdfOutlinePageLookup {
  PdfOutlinePageLookup(List<PdfOutlineNode>? outline) {
    void collect(List<PdfOutlineNode> nodes, int? parent, int? threshold) {
      for (final node in nodes) {
        final page = node.dest?.pageNumber;
        if (page == null) continue;
        // יעד מאוחר של אב או של אח קודם דוחה גם את ההגעה לצומת הזה.
        threshold = threshold == null ? page : max(threshold, page);
        final index = _entries.length;
        _entries.add((page: threshold, parent: parent, node: node));
        collect(node.children, index, threshold);
      }
    }

    collect(outline ?? const [], null, null);
    int? earliestPage;
    for (var i = _entries.length - 1; i >= 0; i--) {
      final page = _entries[i].page;
      // אם צומת מאוחר יותר בסריקה כבר פעיל בעמוד הזה, הקודם לעולם לא ייבחר.
      if (earliestPage != null && page >= earliestPage) continue;
      earliestPage = page;
      _breakpoints.add(i);
    }
  }

  final _entries = <_OutlineEntry>[];
  final _breakpoints = <int>[];

  /// הצומת הפעיל ב-[pageNumber] ואבותיו, מהצומת הפעיל עד לשורש.
  List<PdfOutlineNode> pathAt(int pageNumber) {
    var lo = 0;
    var hi = _breakpoints.length;
    while (lo < hi) {
      final mid = lo + ((hi - lo) >> 1);
      if (_entries[_breakpoints[mid]].page > pageNumber) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    if (lo == _breakpoints.length) return const [];

    final path = <PdfOutlineNode>[];
    int? current = _breakpoints[lo];
    while (current != null) {
      final entry = _entries[current];
      path.add(entry.node);
      current = entry.parent;
    }
    return path;
  }
}
