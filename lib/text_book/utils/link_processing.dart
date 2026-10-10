import 'dart:isolate';
import 'dart:collection';
import 'package:otzaria/models/links.dart';
import 'package:otzaria/models/link_types.dart';
import 'package:otzaria/utils/text/text_manipulation.dart' as utils;

List<Link> mergeLinksByIdentity(
  List<Link> existing,
  List<Link> incoming,
) {
  final merged = <String, Link>{
    for (final link in existing) linkIdentityKey(link): link,
  };

  for (final link in incoming) {
    final key = linkIdentityKey(link);
    final existingLink = merged[key];
    if (existingLink == null ||
        link.baseProvenance >= existingLink.baseProvenance) {
      merged[key] = link;
    }
  }

  final links = merged.values.toList();
  links.sort((a, b) {
    final indexCompare = a.index1.compareTo(b.index1);
    if (indexCompare != 0) return indexCompare;

    final pathCompare = a.path2.compareTo(b.path2);
    if (pathCompare != 0) return pathCompare;

    final targetCompare = a.index2.compareTo(b.index2);
    if (targetCompare != 0) return targetCompare;

    return a.connectionType.compareTo(b.connectionType);
  });

  return links;
}

String linkIdentityKey(Link link) {
  final anchors = link.anchorSpans
      .map((span) => '${span.start}:${span.end}:${span.label}')
      .join(',');
  return '${link.index1}|${link.index1End}|${link.path2}|${link.index2}|${link.index2End}|${link.connectionType}|${link.targetSource.wireKey}|${link.targetBookId}|${link.targetCategoryId}|${link.targetFileType}|${link.start}|${link.end}|${link.anchorStart}|${link.anchorEnd}|${link.anchorLabel}|$anchors';
}

Map<int, List<Link>> buildLinksByLineMap(List<Link> links) {
  return _LinksByLineMap(links);
}

typedef _OrderedLink = ({Link link, int order});

class _RangeNode {
  final _OrderedLink value;
  final _RangeNode? left;
  final _RangeNode? right;
  final int maxEnd;

  _RangeNode(this.value, this.left, this.right)
    : maxEnd = [
        value.link.index1End!,
        if (left != null) left.maxEnd,
        if (right != null) right.maxEnd,
      ].reduce((a, b) => a > b ? a : b);
}

class _LinksByLineMap extends MapBase<int, List<Link>> {
  final Map<int, List<_OrderedLink>> _starts = {};
  final List<_OrderedLink> _ranged = [];
  late final _RangeNode? _ranges;

  _LinksByLineMap(List<Link> links) {
    for (var i = 0; i < links.length; i++) {
      final item = (link: links[i], order: i);
      _starts.putIfAbsent(links[i].index1, () => []).add(item);
      if ((links[i].index1End ?? links[i].index1) > links[i].index1) {
        _ranged.add(item);
      }
    }
    _ranged.sort((a, b) => a.link.index1.compareTo(b.link.index1));
    _ranges = _buildRanges(_ranged, 0, _ranged.length);
  }

  _RangeNode? _buildRanges(List<_OrderedLink> items, int first, int last) {
    if (first == last) return null;
    final middle = (first + last) ~/ 2;
    return _RangeNode(
      items[middle],
      _buildRanges(items, first, middle),
      _buildRanges(items, middle + 1, last),
    );
  }

  void _collect(_RangeNode? node, int line, List<_OrderedLink> result) {
    if (node == null || node.maxEnd < line) return;
    if (node.left != null) _collect(node.left, line, result);
    final link = node.value.link;
    if (link.index1 < line && link.index1End! >= line) {
      result.add(node.value);
    }
    if (link.index1 < line) _collect(node.right, line, result);
  }

  // כל גלילה שואלת שוב על אותן שורות; המפה קבועה, ולכן התשובה נשמרת.
  final Map<int, List<Link>?> _memo = {};

  @override
  List<Link>? operator [](Object? key) =>
      key is int ? _memo.putIfAbsent(key, () => _lookup(key)) : null;

  List<Link>? _lookup(int key) {
    final found = <_OrderedLink>[...?_starts[key]];
    if (_ranges != null) {
      _collect(_ranges, key, found);
      found.sort((a, b) => a.order.compareTo(b.order));
    }
    if (found.isEmpty) return null;
    return List.unmodifiable(found.map((item) => item.link));
  }

  @override
  Iterable<int> get keys sync* {
    final seen = <int>{};
    for (final line in _starts.keys) {
      if (seen.add(line)) yield line;
    }
    for (final item in _ranged) {
      for (
        var line = item.link.index1 + 1;
        line <= item.link.index1End!;
        line++
      ) {
        if (seen.add(line)) yield line;
      }
    }
  }

  @override
  void operator []=(int key, List<Link> value) =>
      throw UnsupportedError('Links by line are read-only');

  @override
  void clear() => throw UnsupportedError('Links by line are read-only');

  @override
  List<Link>? remove(Object? key) =>
      throw UnsupportedError('Links by line are read-only');
}

List<Link> computeVisibleLinks({
  required List<Link> links,
  required List<int> visibleIndices,
  required Set<int> selectedIndices,
  required Map<int, List<Link>> linksByLine,
}) {
  final targetIndices = selectedIndices.isNotEmpty
      ? selectedIndices
      : visibleIndices;

  final visibleLinks = <Link>[];
  final seenLinks = <Link>{};

  for (final index in targetIndices) {
    final candidates = linksByLine[index + 1] ?? const [];

    for (final link in candidates) {
      if (!LinkTypes.isDependentTextLink(link.connectionType) &&
          link.start == null &&
          link.end == null) {
        if (seenLinks.add(link)) visibleLinks.add(link);
      }
    }
  }

  // הכותרת מחושבת פעם אחת לקישור ונצמדת אליו — בלי חיפוש במפה בכל השוואה.
  final pathCache = <String, String>{};
  final byTitle = [
    for (final link in visibleLinks)
      (
        pathCache.putIfAbsent(
          link.path2,
          () => utils.getTitleFromPath(link.path2),
        ),
        link,
      ),
  ]..sort((a, b) => a.$1.compareTo(b.$1));

  return [for (final (_, link) in byTitle) link];
}

Future<
  ({
    List<Link> links,
    Map<int, List<Link>> linksByLine,
    List<Link> visibleLinks,
  })
>
processLinksForState({
  required List<Link> existingLinks,
  required List<Link> incomingLinks,
  required bool replaceExisting,
  required List<int> visibleIndices,
  required Set<int> selectedIndices,
}) async {
  const asyncProcessingThreshold = 250;
  final estimatedLinkCount =
      (replaceExisting ? 0 : existingLinks.length) + incomingLinks.length;

  if (estimatedLinkCount <= asyncProcessingThreshold) {
    final links = mergeLinksByIdentity(
      replaceExisting ? const [] : existingLinks,
      incomingLinks,
    );
    final linksByLine = buildLinksByLineMap(links);
    final visibleLinks = computeVisibleLinks(
      links: links,
      visibleIndices: visibleIndices,
      selectedIndices: selectedIndices,
      linksByLine: linksByLine,
    );
    return (
      links: links,
      linksByLine: linksByLine,
      visibleLinks: visibleLinks,
    );
  }

  return Isolate.run(() {
    final links = mergeLinksByIdentity(
      replaceExisting ? const [] : existingLinks,
      incomingLinks,
    );
    final linksByLine = buildLinksByLineMap(links);
    final visibleLinks = computeVisibleLinks(
      links: links,
      visibleIndices: visibleIndices,
      selectedIndices: selectedIndices,
      linksByLine: linksByLine,
    );
    return (
      links: links,
      linksByLine: linksByLine,
      visibleLinks: visibleLinks,
    );
  });
}

List<String> buildPreviewLines(String previewContent, int previewStartLine) {
  final previewLines = previewContent.split('\n');
  if (previewStartLine <= 0) {
    return previewLines;
  }

  return List<String>.filled(previewStartLine, '', growable: true)
    ..addAll(previewLines);
}

Future<List<String>> splitContentLines(String content) async {
  if (content.isEmpty) {
    return const [];
  }

  return Isolate.run(() => content.split('\n'));
}
