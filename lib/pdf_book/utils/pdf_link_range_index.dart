import 'dart:math' as math;

import 'package:otzaria/models/links.dart';

/// Inclusive source-line lookup for a PDF tab's sorted link snapshot.
final class PdfLinkRangeIndex {
  PdfLinkRangeIndex(this._links);

  static const _blockSize = 32;

  final List<Link> _links;
  ({int first, int last})? _previousRange;
  List<Link> _previousMatches = const [];
  late final List<int> _maxEnds = _buildMaxEnds();

  List<Link> overlapping(int first, int last) {
    final range = (first: first, last: last);
    if (_previousRange == range) return _previousMatches;

    var low = 0;
    var high = _links.length;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      if (_links[middle].index1 <= last) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }

    final matches = <Link>[];
    if (low <= _blockSize) {
      _collectBlock(0, low, first, last, matches);
    } else {
      // A long anchor in one block does not prevent pruning other blocks.
      _collect(
        1,
        0,
        _maxEnds.length ~/ 2 * _blockSize,
        low,
        first,
        last,
        matches,
      );
    }
    _previousRange = range;
    return _previousMatches = matches;
  }

  List<int> _buildMaxEnds() {
    var leaves = 1;
    while (leaves * _blockSize < _links.length) {
      leaves *= 2;
    }
    final maxEnds = List<int>.filled(leaves * 2, 0);
    for (var i = 0; i < _links.length; i++) {
      final link = _links[i];
      final block = leaves + i ~/ _blockSize;
      maxEnds[block] = math.max(maxEnds[block], link.index1End ?? link.index1);
    }
    for (var node = leaves - 1; node > 0; node--) {
      maxEnds[node] = math.max(maxEnds[node * 2], maxEnds[node * 2 + 1]);
    }
    return maxEnds;
  }

  void _collect(
    int node,
    int start,
    int end,
    int stop,
    int first,
    int last,
    List<Link> matches,
  ) {
    if (start >= stop || _maxEnds[node] < first) return;
    if (end - start == _blockSize) {
      _collectBlock(start, math.min(end, stop), first, last, matches);
      return;
    }

    final middle = (start + end) ~/ 2;
    _collect(node * 2, start, middle, stop, first, last, matches);
    _collect(node * 2 + 1, middle, end, stop, first, last, matches);
  }

  void _collectBlock(int start, int end, int first, int last, List<Link> matches) {
    for (var i = start; i < end; i++) {
      final link = _links[i];
      if (link.overlapsSourceLines(first, last)) matches.add(link);
    }
  }
}
